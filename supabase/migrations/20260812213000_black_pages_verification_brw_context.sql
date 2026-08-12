-- THE BLACK PAGES: scaled candidate verification, Black Restaurant Week / GrowthZone source registry,
-- and a second context-aware classification lane. No function in this migration publishes a listing.

alter table public.black_pages_candidate_queue
  add column if not exists verification_score numeric,
  add column if not exists verification_tier text,
  add column if not exists verification_reasons text[] not null default '{}'::text[],
  add column if not exists verification_prechecked_at timestamptz;

do $block$
begin
  if not exists(select 1 from pg_constraint where conname='black_pages_candidate_verification_tier_check') then
    alter table public.black_pages_candidate_queue add constraint black_pages_candidate_verification_tier_check
      check(verification_tier is null or verification_tier in('ready','research','hold'));
  end if;
end $block$;

create index if not exists black_pages_candidate_verification_lane_idx
  on public.black_pages_candidate_queue(verification_tier,verification_score desc,priority_score desc)
  where pipeline_stage not in('published','rejected','do_not_contact');

create table if not exists public.black_pages_candidate_verification_reviews(
  id uuid primary key default gen_random_uuid(),
  candidate_id uuid not null unique references public.black_pages_candidate_queue(id) on delete cascade,
  source_key text,
  source_url text,
  precheck_snapshot jsonb not null default '{}'::jsonb,
  status text not null default 'pending' check(status in('pending','approved','rejected','needs_more_evidence')),
  reviewer_user_id uuid,
  reviewer_role text,
  reviewer_note text,
  reviewed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists black_pages_candidate_verification_reviews_status_idx
  on public.black_pages_candidate_verification_reviews(status,created_at);
alter table public.black_pages_candidate_verification_reviews enable row level security;
revoke all on public.black_pages_candidate_verification_reviews from public,anon,authenticated;
grant all on public.black_pages_candidate_verification_reviews to service_role;

insert into public.black_pages_external_sources(source_key,source_name,adapter,base_url,ownership_signal,credential_secret_name,active,priority,notes) values
('black_restaurant_week_national','Black Restaurant Week National Directory','black_restaurant_week','https://blackrestaurantweeks.com/brw-campaigns/','black_restaurant_week_participant',null,true,125,'Public national Black Restaurant Week directory. 723 culinary listings observed August 2026; human verification still required before publication.'),
('greater_washington_black_chamber','Greater Washington DC Black Chamber','growthzone','https://business.gwbcc.org/member-directory/Find','black_chamber_directory',null,false,112,'Public GrowthZone member directory; activate after parser QA.'),
('california_black_chamber','California Black Chamber of Commerce','growthzone','https://business.calbcc.org/directory/Find','black_chamber_directory',null,false,108,'Public GrowthZone member directory; activate after parser QA.'),
('capital_black_chamber','Capital Black Chamber of Commerce','growthzone','https://members.sacblackchamber.org/directory/Find','black_chamber_directory',null,false,108,'Public GrowthZone member directory; activate after parser QA.'),
('memphis_black_restaurant_week','Memphis Black Restaurant Week','black_restaurant_week_city','https://www.blackrestaurantweek.com/menu','black_restaurant_week_participant',null,false,104,'Black-owned restaurant participant source; dedicated parser/QA required.'),
('long_beach_black_restaurant_week','Long Beach Black Restaurant Week','black_restaurant_week_city','https://lbblackrestaurantweek.com/participating-restaurants','black_restaurant_week_participant',null,false,104,'Black-owned food business participant source; dedicated parser/QA required.'),
('san_antonio_black_restaurant_week','Black Restaurant Week San Antonio','black_restaurant_week_city','https://www.blackrestaurantweeksanantonio.com/brwsa-2026-participants','black_restaurant_week_participant',null,false,104,'Structured public participant table; dedicated parser/QA required.'),
('byblack_public','ByBlack Public Directory','byblack_public','https://byblack.us/search','black_business_directory',null,false,115,'Public Black-owned business search pages are visible without an API key. Keep inactive until parser QA proves stable field extraction.')
on conflict(source_key) do update set
  source_name=excluded.source_name,adapter=excluded.adapter,base_url=excluded.base_url,
  ownership_signal=excluded.ownership_signal,credential_secret_name=excluded.credential_secret_name,
  priority=excluded.priority,notes=excluded.notes,updated_at=now();

insert into public.black_pages_taxonomy_aliases(alias,category_slug,subcategory_slug,confidence) values
('soul food','food-beverage','soul-food',.99),('barbecue','food-beverage','bbq-restaurants',.99),('bbq','food-beverage','bbq-restaurants',.99),
('caribbean','food-beverage','caribbean-restaurants',.99),('vegan','food-beverage','vegan-restaurants',.99),('seafood','food-beverage','seafood-restaurants',.99),
('african','food-beverage','african-restaurants',.98),('creole','food-beverage','restaurants',.92),('cajun','food-beverage','restaurants',.92),
('bakery','food-beverage','bakeries',.99),('dessert','food-beverage','desserts',.94),('juice','food-beverage','juice-bars',.96),('smoothie','food-beverage','smoothie-shops',.96),
('pizzeria','food-beverage','pizza',.97),('pizza','food-beverage','pizza',.97),('steakhouse','food-beverage','restaurants',.95),('food truck','food-beverage','food-trucks',.99)
on conflict(alias) do update set category_slug=excluded.category_slug,subcategory_slug=excluded.subcategory_slug,confidence=excluded.confidence,active=true;

create or replace function public.black_pages_context_classify_batch(p_limit integer default 10000)
returns jsonb
language plpgsql security definer set search_path='pg_catalog','public','extensions','auth' as $$
declare
  v_role text:=coalesce(auth.jwt()->'app_metadata'->>'khg_role','');
  v_limit integer:=least(30000,greatest(1,coalesce(p_limit,10000)));
  v_alias integer:=0; v_semantic integer:=0;
begin
  if coalesce(auth.role(),'')<>'service_role' and v_role not in('owner','admin','editor') then
    raise exception 'Staff access required' using errcode='42501';
  end if;

  with targets as (
    select q.id,
      lower(concat_ws(' ',q.business_name,q.source_category,q.source_subcategory,q.category,q.notes,
        regexp_replace(coalesce(q.website_url,''),'https?://|www\\.|[-_/?.=&]+',' ','g'),
        regexp_replace(coalesce(q.external_source_url,''),'https?://|www\\.|[-_/?.=&]+',' ','g'))) context_text
    from public.black_pages_candidate_queue q
    where (q.subcategory is null or btrim(q.subcategory)='')
      and q.pipeline_stage not in('published','rejected','do_not_contact')
    order by q.priority_score desc,q.id limit v_limit
  ), matches as (
    select distinct on(t.id) t.id,a.category_slug,a.subcategory_slug,
      least(.97,greatest(.78,a.confidence*.94)) confidence
    from targets t join public.black_pages_taxonomy_aliases a
      on a.active and length(a.alias)>=3 and t.context_text like '%'||lower(a.alias)||'%'
    order by t.id,a.confidence desc,length(a.alias) desc
  ), upd as (
    update public.black_pages_candidate_queue q set
      category=m.category_slug,subcategory=m.subcategory_slug,
      classification_confidence=m.confidence,classification_method='context_alias',
      classified_at=now(),updated_at=now()
    from matches m where q.id=m.id returning q.id
  ) select count(*)::int into v_alias from upd;

  with targets as (
    select q.id,q.category,
      lower(concat_ws(' ',q.business_name,q.source_category,q.source_subcategory,q.notes,
        regexp_replace(coalesce(q.website_url,''),'https?://|www\\.|[-_/?.=&]+',' ','g'))) context_text
    from public.black_pages_candidate_queue q
    where (q.subcategory is null or btrim(q.subcategory)='') and q.category is not null
      and q.pipeline_stage not in('published','rejected','do_not_contact')
    order by q.priority_score desc,q.id limit v_limit
  ), scored as (
    select distinct on(t.id) t.id,s.category_slug,s.slug subcategory_slug,
      greatest(word_similarity(lower(s.name),t.context_text),word_similarity(replace(lower(s.slug),'-',' '),t.context_text)) score
    from targets t join public.black_pages_subcategories s on s.active and s.category_slug=t.category
    where greatest(word_similarity(lower(s.name),t.context_text),word_similarity(replace(lower(s.slug),'-',' '),t.context_text))>=.72
    order by t.id,score desc,s.slug
  ), upd as (
    update public.black_pages_candidate_queue q set
      subcategory=s.subcategory_slug,classification_confidence=least(.91,greatest(.78,s.score)),
      classification_method='context_semantic',classified_at=now(),updated_at=now()
    from scored s where q.id=s.id returning q.id
  ) select count(*)::int into v_semantic from upd;

  return jsonb_build_object(
    'context_alias_classified',v_alias,'context_semantic_classified',v_semantic,
    'classified_total',v_alias+v_semantic,
    'remaining_unclassified',(select count(*) from public.black_pages_candidate_queue where subcategory is null or btrim(subcategory)='')
  );
end $$;
revoke all on function public.black_pages_context_classify_batch(integer) from public,anon,authenticated;
grant execute on function public.black_pages_context_classify_batch(integer) to authenticated,service_role;

create or replace function public.black_pages_preverify_batch(p_limit integer default 10000)
returns jsonb
language plpgsql security definer set search_path='pg_catalog','public','auth' as $$
declare
  v_role text:=coalesce(auth.jwt()->'app_metadata'->>'khg_role','');
  v_limit integer:=least(30000,greatest(1,coalesce(p_limit,10000)));
  v_count integer:=0;
begin
  if coalesce(auth.role(),'')<>'service_role' and v_role not in('owner','admin','editor') then
    raise exception 'Staff access required' using errcode='42501';
  end if;

  with base as (
    select q.id,q.business_name,q.city,q.state,q.category,q.subcategory,q.classification_confidence,
      q.website_url,q.instagram_handle,q.public_email,q.public_phone,q.source_address,q.external_source_url,
      case when q.source_external_key like 'external:%' then split_part(q.source_external_key,':',2) else null end source_key,
      count(*) over(partition by lower(btrim(q.business_name)),lower(btrim(q.city)),coalesce(q.state,'')) duplicate_count
    from public.black_pages_candidate_queue q
    where q.pipeline_stage not in('published','rejected','do_not_contact')
    order by q.priority_score desc,q.id limit v_limit
  ), scored as (
    select b.*,s.ownership_signal,
      (case when s.ownership_signal in('certified_black_business','black_chamber_directory','black_business_directory','black_restaurant_week_participant') then 45 else 0 end
       +case when nullif(b.external_source_url,'') is not null then 15 else 0 end
       +case when nullif(b.source_address,'') is not null or (nullif(b.city,'') is not null and nullif(b.state,'') is not null) then 10 else 0 end
       +case when nullif(b.website_url,'') is not null then 8 else 0 end
       +case when nullif(b.instagram_handle,'') is not null or nullif(b.public_email,'') is not null or nullif(b.public_phone,'') is not null then 6 else 0 end
       +case when nullif(b.subcategory,'') is not null and coalesce(b.classification_confidence,0)>=.78 then 10 else 0 end
       +case when nullif(b.category,'') is not null then 4 else 0 end
       -case when b.duplicate_count>1 then 30 else 0 end
       -case when nullif(b.external_source_url,'') is null and s.ownership_signal is not null then 20 else 0 end
      )::numeric score
    from base b left join public.black_pages_external_sources s on s.source_key=b.source_key
  ), routed as (
    select *,case
      when duplicate_count>1 then 'hold'
      when ownership_signal in('certified_black_business','black_chamber_directory','black_business_directory','black_restaurant_week_participant') and score>=75 then 'ready'
      when score>=40 then 'research'
      else 'hold' end tier,
      array_remove(array[
        case when ownership_signal in('certified_black_business','black_chamber_directory','black_business_directory','black_restaurant_week_participant') then 'strong_black_business_source' end,
        case when nullif(external_source_url,'') is not null then 'source_profile_present' end,
        case when nullif(source_address,'') is not null or (nullif(city,'') is not null and nullif(state,'') is not null) then 'location_present' end,
        case when nullif(website_url,'') is not null then 'website_present' end,
        case when nullif(subcategory,'') is not null and coalesce(classification_confidence,0)>=.78 then 'taxonomy_confident' end,
        case when duplicate_count>1 then 'possible_duplicate' end,
        case when ownership_signal is null then 'ownership_source_needs_research' end
      ]::text[],null) reasons
    from scored
  ), upd as (
    update public.black_pages_candidate_queue q set
      verification_score=r.score,verification_tier=r.tier,verification_reasons=r.reasons,
      verification_prechecked_at=now(),updated_at=now()
    from routed r where q.id=r.id returning q.id
  ) select count(*)::int into v_count from upd;

  insert into public.black_pages_candidate_verification_reviews(candidate_id,source_key,source_url,precheck_snapshot,status,updated_at)
  select q.id,
    case when q.source_external_key like 'external:%' then split_part(q.source_external_key,':',2) else null end,
    q.external_source_url,
    jsonb_build_object('score',q.verification_score,'tier',q.verification_tier,'reasons',q.verification_reasons,
      'category',q.category,'subcategory',q.subcategory,'classification_confidence',q.classification_confidence,
      'prechecked_at',q.verification_prechecked_at),
    'pending',now()
  from public.black_pages_candidate_queue q
  where q.verification_prechecked_at is not null and q.pipeline_stage not in('published','rejected','do_not_contact')
  on conflict(candidate_id) do update set
    source_key=excluded.source_key,source_url=excluded.source_url,precheck_snapshot=excluded.precheck_snapshot,
    status=case when public.black_pages_candidate_verification_reviews.status in('approved','rejected') then public.black_pages_candidate_verification_reviews.status else 'pending' end,
    updated_at=now();

  return jsonb_build_object('prechecked',v_count,
    'ready',(select count(*) from public.black_pages_candidate_queue where verification_tier='ready' and pipeline_stage not in('published','rejected','do_not_contact')),
    'research',(select count(*) from public.black_pages_candidate_queue where verification_tier='research' and pipeline_stage not in('published','rejected','do_not_contact')),
    'hold',(select count(*) from public.black_pages_candidate_queue where verification_tier='hold' and pipeline_stage not in('published','rejected','do_not_contact')));
end $$;
revoke all on function public.black_pages_preverify_batch(integer) from public,anon,authenticated;
grant execute on function public.black_pages_preverify_batch(integer) to authenticated,service_role;

create or replace function public.black_pages_staff_verification_snapshot(p_city text default null,p_limit integer default 250)
returns jsonb
language plpgsql security definer set search_path='pg_catalog','public','auth' as $$
declare v_role text:=coalesce(auth.jwt()->'app_metadata'->>'khg_role',''); v_rows jsonb; v_counts jsonb;
begin
  if v_role not in('owner','admin','editor') then raise exception 'Staff access required' using errcode='42501'; end if;
  perform public.black_pages_preverify_batch(10000);
  select jsonb_build_object(
    'ready',count(*) filter(where verification_tier='ready'),
    'research',count(*) filter(where verification_tier='research'),
    'hold',count(*) filter(where verification_tier='hold'),
    'pending_reviews',count(*) filter(where r.status='pending'),
    'approved_reviews',count(*) filter(where r.status='approved')) into v_counts
  from public.black_pages_candidate_queue q left join public.black_pages_candidate_verification_reviews r on r.candidate_id=q.id
  where q.pipeline_stage not in('published','rejected','do_not_contact') and (p_city is null or lower(q.city)=lower(p_city));

  select coalesce(jsonb_agg(to_jsonb(x) order by x.verification_score desc,x.priority_score desc),'[]'::jsonb) into v_rows
  from (
    select q.id,q.business_name,q.city,q.state,q.category,q.subcategory,q.website_url,q.instagram_handle,
      q.public_email,q.public_phone,q.external_source_url,q.source_address,q.source_category,q.source_subcategory,
      q.classification_confidence,q.classification_method,q.verification_score,q.verification_tier,q.verification_reasons,
      q.priority_score,r.source_key,r.status review_status,s.source_name,s.ownership_signal
    from public.black_pages_candidate_queue q
    left join public.black_pages_candidate_verification_reviews r on r.candidate_id=q.id
    left join public.black_pages_external_sources s on s.source_key=r.source_key
    where q.pipeline_stage not in('published','rejected','do_not_contact')
      and (p_city is null or lower(q.city)=lower(p_city))
    order by case q.verification_tier when 'ready' then 1 when 'research' then 2 else 3 end,q.verification_score desc,q.priority_score desc
    limit least(500,greatest(1,coalesce(p_limit,250)))
  ) x;
  return jsonb_build_object('counts',v_counts,'candidates',v_rows,'generated_at',now());
end $$;
revoke all on function public.black_pages_staff_verification_snapshot(text,integer) from public,anon,authenticated;
grant execute on function public.black_pages_staff_verification_snapshot(text,integer) to authenticated;

create or replace function public.black_pages_staff_batch_candidate_review(p_items jsonb,p_reason text)
returns jsonb
language plpgsql security definer set search_path='pg_catalog','public','auth' as $$
declare
  v_role text:=coalesce(auth.jwt()->'app_metadata'->>'khg_role','');
  v_reason text:=left(btrim(coalesce(p_reason,'')),2000); r record; v_done integer:=0;
begin
  if v_role not in('owner','admin','editor') then raise exception 'Staff access required' using errcode='42501'; end if;
  if v_reason='' then raise exception 'A human review reason is required'; end if;
  if jsonb_typeof(coalesce(p_items,'[]'::jsonb))<>'array' then raise exception 'p_items must be an array'; end if;
  if jsonb_array_length(coalesce(p_items,'[]'::jsonb))>250 then raise exception 'Maximum 250 candidate decisions per batch'; end if;

  for r in select (value->>'candidate_id')::uuid candidate_id,lower(value->>'decision') decision from jsonb_array_elements(p_items)
  loop
    if r.decision not in('approve','reject','needs_more_evidence') then raise exception 'Invalid decision'; end if;
    if not exists(select 1 from public.black_pages_candidate_queue q where q.id=r.candidate_id for update) then continue; end if;

    if r.decision='approve' then
      if not exists(select 1 from public.black_pages_candidate_queue q where q.id=r.candidate_id and q.ownership_evidence_status='evidence_found' and nullif(q.external_source_url,'') is not null) then
        raise exception 'Candidate % lacks source ownership evidence',r.candidate_id;
      end if;
      update public.black_pages_candidate_queue set ownership_evidence_status='owner_confirmed',pipeline_stage='approved',assigned_researcher='staff:'||auth.uid()::text,next_action_at=null,
        notes=left(concat_ws(E'\n',nullif(notes,''),'Human batch verification approved source ownership evidence: '||v_reason),4000),updated_at=now() where id=r.candidate_id;
      update public.black_pages_candidate_verification_reviews set status='approved',reviewer_user_id=auth.uid(),reviewer_role=v_role,reviewer_note=v_reason,reviewed_at=now(),updated_at=now() where candidate_id=r.candidate_id;
    elsif r.decision='reject' then
      update public.black_pages_candidate_queue set ownership_evidence_status='not_black_owned',pipeline_stage='rejected',assigned_researcher='staff:'||auth.uid()::text,
        notes=left(concat_ws(E'\n',nullif(notes,''),'Human batch verification rejected candidate: '||v_reason),4000),updated_at=now() where id=r.candidate_id;
      update public.black_pages_candidate_verification_reviews set status='rejected',reviewer_user_id=auth.uid(),reviewer_role=v_role,reviewer_note=v_reason,reviewed_at=now(),updated_at=now() where candidate_id=r.candidate_id;
    else
      update public.black_pages_candidate_queue set ownership_evidence_status='unreviewed',pipeline_stage='research',assigned_researcher='black-pages-research-worker',next_action_at=now(),
        notes=left(concat_ws(E'\n',nullif(notes,''),'Human batch verification requested more evidence: '||v_reason),4000),updated_at=now() where id=r.candidate_id;
      update public.black_pages_candidate_verification_reviews set status='needs_more_evidence',reviewer_user_id=auth.uid(),reviewer_role=v_role,reviewer_note=v_reason,reviewed_at=now(),updated_at=now() where candidate_id=r.candidate_id;
    end if;
    insert into public.black_pages_candidate_activity(candidate_id,activity_type,outcome,details,performed_by)
    values(r.candidate_id,'verification_note',r.decision,jsonb_build_object('reason',v_reason,'automated_decision',false,'new_directory_record_published',false),'staff:'||auth.uid()::text);
    v_done:=v_done+1;
  end loop;
  return jsonb_build_object('reviewed',v_done,'new_directory_records_published',0);
end $$;
revoke all on function public.black_pages_staff_batch_candidate_review(jsonb,text) from public,anon,authenticated;
grant execute on function public.black_pages_staff_batch_candidate_review(jsonb,text) to authenticated;

create or replace function public.black_pages_queue_source_scan(p_source_key text,p_pages integer default 1)
returns jsonb
language plpgsql security definer set search_path='pg_catalog','public','auth' as $$
declare v_role text:=coalesce(auth.jwt()->'app_metadata'->>'khg_role','');v_source public.black_pages_external_sources%rowtype;v_pages integer:=least(100,greatest(1,coalesce(p_pages,1)));v_page integer;v_url text;v_created integer:=0;
begin
  if coalesce(auth.role(),'')<>'service_role' and v_role not in('owner','admin','editor') then raise exception 'Staff access required' using errcode='42501'; end if;
  select * into v_source from public.black_pages_external_sources where source_key=p_source_key;
  if not found then raise exception 'Unknown source'; end if;
  if not v_source.active then raise exception 'Source is not active'; end if;
  for v_page in 1..v_pages loop
    if v_source.adapter='black_restaurant_week' then
      v_url:=case when v_page=1 then v_source.base_url else rtrim(v_source.base_url,'/')||'/page/'||v_page::text||'/' end;
    elsif v_source.adapter='growthzone' then
      v_url:=v_source.base_url;
      if v_page>1 then exit; end if;
    else
      raise exception 'Bulk source scan not configured for adapter %',v_source.adapter;
    end if;
    insert into public.black_pages_external_discovery_jobs(source_key,city,state,category_slug,page_offset,request_url,requested_count,requested_by,status,attempt_count,error_message,updated_at)
    values(v_source.source_key,null,null,null,(v_page-1)*10,v_url,case when v_source.adapter='growthzone' then 50 else 10 end,auth.uid(),'pending',0,null,now())
    on conflict(source_key,request_url) do update set status='pending',attempt_count=0,error_message=null,updated_at=now();
    v_created:=v_created+1;
  end loop;
  return jsonb_build_object('source',v_source.source_key,'jobs_queued',v_created,'pages',v_pages);
end $$;
revoke all on function public.black_pages_queue_source_scan(text,integer) from public,anon,authenticated;
grant execute on function public.black_pages_queue_source_scan(text,integer) to authenticated,service_role;

-- Run the two conservative batch lanes immediately. They do not publish records.
select public.black_pages_context_classify_batch(30000);
select public.black_pages_preverify_batch(30000);
