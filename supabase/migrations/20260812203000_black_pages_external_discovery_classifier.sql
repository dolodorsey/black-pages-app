-- THE BLACK PAGES: external discovery feeds, automatic taxonomy classification, and staff burst control.

alter table public.black_pages_candidate_queue
  add column if not exists source_category text,
  add column if not exists source_subcategory text,
  add column if not exists source_address text,
  add column if not exists source_postal_code text,
  add column if not exists external_source_url text,
  add column if not exists classification_confidence numeric,
  add column if not exists classification_method text,
  add column if not exists classified_at timestamptz;

create table if not exists public.black_pages_taxonomy_aliases(
  alias text primary key,
  category_slug text not null references public.black_pages_categories(slug),
  subcategory_slug text not null,
  confidence numeric not null default .92 check(confidence between 0 and 1),
  active boolean not null default true,
  created_at timestamptz not null default now(),
  foreign key(category_slug,subcategory_slug) references public.black_pages_subcategories(category_slug,slug)
);

insert into public.black_pages_taxonomy_aliases(alias,category_slug,subcategory_slug,confidence) values
('restaurant','food-beverage','restaurants',.99),('restaurants','food-beverage','restaurants',.99),('brunch','food-beverage','restaurants',.90),
('cafe','food-beverage','coffee-shops',.96),('coffee','food-beverage','coffee-shops',.96),('coffee shop','food-beverage','coffee-shops',.99),
('bar','food-beverage','bars',.96),('sports bar','food-beverage','bars',.91),('wine bar','food-beverage','wine-bars',.99),
('food truck','food-beverage','food-trucks',.99),('hookah','nightlife-entertainment','hookah-lounges',.97),('hookah lounge','nightlife-entertainment','hookah-lounges',.99),
('nightclub','nightlife-entertainment','nightclubs',.99),('nightlife','nightlife-entertainment','lounges',.82),('lounge','nightlife-entertainment','lounges',.97),
('jazz','nightlife-entertainment','jazz-clubs',.94),('comedy','nightlife-entertainment','comedy-clubs',.94),('event venue','venues-spaces','event-venues',.98),
('venue','venues-spaces','event-venues',.83),('spa','beauty-wellness','spas',.98),('salon','beauty-wellness','salons',.97),('beauty','beauty-wellness','salons',.80),
('barber','beauty-wellness','barbershops',.99),('barbershop','beauty-wellness','barbershops',.99),('fitness','sports-fitness','fitness-studios',.90),
('gym','sports-fitness','gyms',.98),('retail','retail','general-retail',.90),('shopping','retail','general-retail',.85),('clothing','fashion-apparel','clothing-boutiques',.94),
('consulting','business-services','business-consultants',.95),('consultant','business-services','business-consultants',.93),('bookkeeping','business-services','bookkeeping-services',.97),
('staffing','business-services','staffing-agencies',.97),('accounting','financial-services','accountants',.97),('tax','financial-services','tax-preparation',.96),
('finance','financial-services','financial-advisors',.86),('insurance','financial-services','insurance-agencies',.97),('real estate','real-estate','real-estate-agents',.95),
('legal','professional-services','legal',.95),('law','professional-services','legal',.94),('attorney','professional-services','legal',.96),
('cleaning','cleaning-maintenance','commercial-cleaning',.88),('commercial cleaning','cleaning-maintenance','commercial-cleaning',.98),('residential cleaning','cleaning-maintenance','residential-cleaning',.98),
('marketing','marketing-advertising','marketing-agencies',.97),('video','creative-media','video-production',.92),('video production','creative-media','video-production',.99),
('photography','arts-culture','photography-studios',.94),('primary care physicians','health','primary-care',.99),('primary care','health','primary-care',.99),
('home care','health','home-care',.99),('non profit','community','nonprofits',.93),('nonprofit','community','nonprofits',.93),
('construction','construction-trades','general-contractors',.94),('logistics','logistics-transportation','logistics-consultants',.82),('trucking','logistics-transportation','trucking-companies',.98),
('education','education','adult-education',.80),('authors','creative-media','publishers',.84),('cosmetics','beauty-wellness','cosmetic-retailers',.91)
on conflict(alias) do update set category_slug=excluded.category_slug,subcategory_slug=excluded.subcategory_slug,confidence=excluded.confidence,active=true;

update public.black_pages_candidate_queue q
set source_category=d.category,
    source_address=coalesce(q.source_address,d.address),
    external_source_url=coalesce(q.external_source_url,d.website_url),
    updated_at=now()
from public.directory_listings d
where q.source_external_key='directory_listings:'||d.id::text
  and (q.source_category is null or q.source_address is null);

create or replace function public.black_pages_auto_classify_batch(p_limit integer default 10000)
returns jsonb
language plpgsql security definer set search_path='pg_catalog','public','extensions' as $$
declare v_limit integer:=least(20000,greatest(1,coalesce(p_limit,10000))); v_exact integer:=0; v_fuzzy integer:=0;
begin
  with targets as (
    select q.id,
      lower(concat_ws(' ',q.source_subcategory,q.source_category,q.category,q.business_name)) haystack,
      lower(coalesce(q.source_subcategory,'')) source_subcategory,
      lower(coalesce(q.source_category,'')) source_category
    from public.black_pages_candidate_queue q
    where (q.subcategory is null or btrim(q.subcategory)='')
      and q.pipeline_stage not in ('rejected','do_not_contact')
    order by q.priority_score desc,q.id limit v_limit
  ), matches as (
    select distinct on(t.id) t.id,a.category_slug,a.subcategory_slug,a.confidence,
      case when t.source_subcategory=a.alias then 4 when t.source_category=a.alias then 3 else 2 end rank
    from targets t join public.black_pages_taxonomy_aliases a on a.active and (
      t.source_subcategory=a.alias or t.source_category=a.alias or t.haystack like '%'||a.alias||'%')
    order by t.id,rank desc,a.confidence desc,length(a.alias) desc
  ), upd as (
    update public.black_pages_candidate_queue q set
      category=m.category_slug,subcategory=m.subcategory_slug,classification_confidence=m.confidence,
      classification_method='alias',classified_at=now(),updated_at=now()
    from matches m where q.id=m.id returning q.id
  ) select count(*)::int into v_exact from upd;

  with targets as (
    select q.id,public.black_pages_canonical_category(q.category) category_slug,
      lower(concat_ws(' ',q.source_subcategory,q.source_category,q.business_name)) hint
    from public.black_pages_candidate_queue q
    where (q.subcategory is null or btrim(q.subcategory)='') and q.category is not null
      and q.pipeline_stage not in ('rejected','do_not_contact')
    order by q.priority_score desc,q.id limit v_limit
  ), scored as (
    select distinct on(t.id) t.id,s.category_slug,s.slug subcategory_slug,
      greatest(similarity(t.hint,lower(s.name)),similarity(t.hint,replace(lower(s.slug),'-',' '))) score
    from targets t join public.black_pages_subcategories s on s.active and s.category_slug=t.category_slug
    where greatest(similarity(t.hint,lower(s.name)),similarity(t.hint,replace(lower(s.slug),'-',' ')))>=.30
    order by t.id,score desc,s.slug
  ), upd as (
    update public.black_pages_candidate_queue q set subcategory=s.subcategory_slug,
      classification_confidence=least(.89,s.score),classification_method='fuzzy_taxonomy',classified_at=now(),updated_at=now()
    from scored s where q.id=s.id returning q.id
  ) select count(*)::int into v_fuzzy from upd;

  return jsonb_build_object('alias_classified',v_exact,'fuzzy_classified',v_fuzzy,'classified_total',v_exact+v_fuzzy,
    'remaining_unclassified',(select count(*) from public.black_pages_candidate_queue where subcategory is null or btrim(subcategory)=''));
end; $$;
revoke all on function public.black_pages_auto_classify_batch(integer) from public,anon,authenticated;
grant execute on function public.black_pages_auto_classify_batch(integer) to service_role;

create table if not exists public.black_pages_external_sources(
  source_key text primary key,
  source_name text not null,
  adapter text not null,
  base_url text not null,
  ownership_signal text not null default 'discovery_only',
  credential_secret_name text,
  active boolean not null default true,
  priority integer not null default 50,
  notes text,
  created_at timestamptz not null default now(),updated_at timestamptz not null default now()
);

insert into public.black_pages_external_sources(source_key,source_name,adapter,base_url,ownership_signal,credential_secret_name,active,priority,notes) values
('atlanta_black_chambers','Atlanta Black Chambers Directory','iamblackbusiness','https://abc.iamblackbusiness.com/','black_business_directory',null,true,100,'Public chamber directory; server-rendered and paginated.'),
('black_package_store','Black Package Store Directory','iamblackbusiness','https://directory.blackpackagestore.com/','black_business_directory',null,true,60,'Public Black-owned package store directory.'),
('tallahassee_capital_chamber','Capital City Chamber Directory','iamblackbusiness','https://tallahasseecapcity.iamblackbusiness.com/','black_business_directory',null,true,60,'Public chamber directory.'),
('byblack','ByBlack / U.S. Black Chambers','byblack','https://www.byblack.us/search','certified_black_business','BYBLACK_API_KEY',false,95,'Credential/API adapter ready; activate when direct structured access is configured.'),
('google_places','Google Places','google_places','https://places.googleapis.com/v1/places:searchText','discovery_only','GOOGLE_PLACES_API_KEY',false,90,'Credential adapter ready; results still require Black-ownership verification.')
on conflict(source_key) do update set source_name=excluded.source_name,adapter=excluded.adapter,base_url=excluded.base_url,
 ownership_signal=excluded.ownership_signal,credential_secret_name=excluded.credential_secret_name,priority=excluded.priority,notes=excluded.notes;

create table if not exists public.black_pages_external_discovery_jobs(
  id uuid primary key default gen_random_uuid(),
  source_key text not null references public.black_pages_external_sources(source_key),
  city text,state text,category_slug text,
  page_offset integer not null default 0,
  request_url text not null,
  requested_count integer not null default 10,
  status text not null default 'pending' check(status in ('pending','processing','completed','failed','blocked')),
  result_count integer not null default 0,
  attempt_count integer not null default 0,
  error_message text,
  requested_by uuid,
  created_at timestamptz not null default now(),started_at timestamptz,completed_at timestamptz,updated_at timestamptz not null default now(),
  unique(source_key,request_url)
);
create index if not exists black_pages_external_jobs_status_idx on public.black_pages_external_discovery_jobs(status,created_at);

alter table public.black_pages_external_sources enable row level security;
alter table public.black_pages_external_discovery_jobs enable row level security;
revoke all on public.black_pages_external_sources,public.black_pages_external_discovery_jobs from public,anon,authenticated;
grant all on public.black_pages_external_sources,public.black_pages_external_discovery_jobs to service_role;

create or replace function public.black_pages_claim_external_jobs(p_limit integer default 10)
returns jsonb language plpgsql security definer set search_path='pg_catalog','public' as $$
declare v_limit integer:=least(20,greatest(1,coalesce(p_limit,10))); v_jobs jsonb;
begin
 if auth.role()<>'service_role' then raise exception 'Service role required' using errcode='42501'; end if;
 with due as (
   select j.id from public.black_pages_external_discovery_jobs j join public.black_pages_external_sources s using(source_key)
   where j.status in ('pending','failed') and j.attempt_count<3 and s.active order by s.priority desc,j.created_at for update skip locked limit v_limit
 ), claimed as (
   update public.black_pages_external_discovery_jobs j set status='processing',attempt_count=attempt_count+1,started_at=now(),updated_at=now()
   from due d where j.id=d.id returning j.*
 ) select coalesce(jsonb_agg(to_jsonb(claimed)),'[]'::jsonb) into v_jobs from claimed;
 return jsonb_build_object('jobs',v_jobs,'claimed',jsonb_array_length(v_jobs));
end; $$;
revoke all on function public.black_pages_claim_external_jobs(integer) from public,anon,authenticated;
grant execute on function public.black_pages_claim_external_jobs(integer) to service_role;

create or replace function public.black_pages_complete_external_job(p_job_id uuid,p_items jsonb,p_error text default null)
returns jsonb language plpgsql security definer set search_path='pg_catalog','public' as $$
declare v_job public.black_pages_external_discovery_jobs%rowtype; v_inserted integer:=0;
begin
 if auth.role()<>'service_role' then raise exception 'Service role required' using errcode='42501'; end if;
 select * into v_job from public.black_pages_external_discovery_jobs where id=p_job_id for update;
 if not found then raise exception 'External job not found'; end if;
 if nullif(btrim(coalesce(p_error,'')),'') is not null then
   update public.black_pages_external_discovery_jobs set status='failed',error_message=left(p_error,1000),completed_at=now(),updated_at=now() where id=p_job_id;
   return jsonb_build_object('job_id',p_job_id,'inserted',0,'status','failed');
 end if;
 if jsonb_typeof(coalesce(p_items,'[]'::jsonb))<>'array' then raise exception 'p_items must be array'; end if;
 with raw as (select value item,ordinality n from jsonb_array_elements(coalesce(p_items,'[]'::jsonb)) with ordinality), clean as (
   select left(btrim(item->>'business_name'),220) business_name,
     left(coalesce(nullif(btrim(item->>'city'),''),v_job.city,'Unknown'),120) city,
     upper(left(coalesce(nullif(btrim(item->>'state'),''),v_job.state,''),2)) state,
     nullif(left(btrim(item->>'source_category'),120),'') source_category,
     nullif(left(btrim(item->>'source_subcategory'),120),'') source_subcategory,
     nullif(left(btrim(item->>'address'),500),'') address,
     nullif(left(btrim(item->>'postal_code'),20),'') postal_code,
     nullif(left(btrim(item->>'detail_url'),700),'') detail_url,
     nullif(left(btrim(item->>'description'),1000),'') description,
     coalesce(nullif(left(btrim(item->>'source_key'),180),''),n::text) source_key
   from raw
 ), ins as (
   insert into public.black_pages_candidate_queue(source_type,source_external_key,business_name,city,state,source_category,source_subcategory,
     source_address,source_postal_code,external_source_url,source_sheets,data_quality_status,ownership_evidence_status,pipeline_stage,
     priority_score,assigned_researcher,next_action_at,notes)
   select 'research','external:'||v_job.source_key||':'||source_key,business_name,city,nullif(state,''),source_category,source_subcategory,address,postal_code,detail_url,
     array[v_job.source_key],'external_directory_found','evidence_found','verification',85,'black-pages-owner-verification-agent',now(),
     left('External Black-business/chamber directory evidence; human verification required before publication. '||coalesce(description,''),4000)
   from clean where nullif(business_name,'') is not null
     and not exists(select 1 from public.black_pages_candidate_queue q where lower(btrim(q.business_name))=lower(btrim(clean.business_name))
       and lower(btrim(q.city))=lower(btrim(clean.city)) and coalesce(q.state,'')=coalesce(nullif(clean.state,''),''))
   on conflict(source_type,source_external_key) where source_external_key is not null do nothing returning id
 ) select count(*)::int into v_inserted from ins;
 update public.black_pages_external_discovery_jobs set status='completed',result_count=v_inserted,error_message=null,completed_at=now(),updated_at=now() where id=p_job_id;
 perform public.black_pages_auto_classify_batch(20000);
 return jsonb_build_object('job_id',p_job_id,'inserted',v_inserted,'status','completed');
end; $$;
revoke all on function public.black_pages_complete_external_job(uuid,jsonb,text) from public,anon,authenticated;
grant execute on function public.black_pages_complete_external_job(uuid,jsonb,text) to service_role;

create or replace function public.black_pages_queue_external_discovery(p_city text,p_state text,p_quantity integer default 1000,p_categories text[] default '{}')
returns jsonb language plpgsql security definer set search_path='pg_catalog','public' as $$
declare v_qty integer:=least(1000,greatest(10,coalesce(p_quantity,1000))); v_pages integer; v_created integer:=0; v_offset integer; v_url text; v_city text:=btrim(p_city); v_state text:=upper(left(btrim(p_state),2));
begin
 v_pages:=ceil(v_qty/10.0)::int;
 for v_offset in select generate_series(0,(v_pages-1)*10,10) loop
   v_url:='https://abc.iamblackbusiness.com/?filter=state%7C'||v_state||case when nullif(v_city,'') is not null then '%2Bcity%7C'||replace(v_city,' ','%20') else '' end||'&sort=name&page='||v_offset;
   insert into public.black_pages_external_discovery_jobs(source_key,city,state,category_slug,page_offset,request_url,requested_count,requested_by)
   values('atlanta_black_chambers',v_city,v_state,nullif(array_to_string(p_categories,','),''),v_offset,v_url,10,auth.uid())
   on conflict(source_key,request_url) do update set status=case when public.black_pages_external_discovery_jobs.status='completed' then 'completed' else 'pending' end,updated_at=now();
   if found then v_created:=v_created+1; end if;
 end loop;
 return jsonb_build_object('jobs_queued',v_created,'pages',v_pages,'requested_quantity',v_qty,'source','atlanta_black_chambers');
end; $$;
revoke all on function public.black_pages_queue_external_discovery(text,text,integer,text[]) from public,anon,authenticated,service_role;

create or replace function public.black_pages_dispatch_external_worker(p_jobs integer default 10)
returns bigint language plpgsql security definer set search_path='pg_catalog','public','net','vault' as $$
declare v_token text; v_request_id bigint;
begin
 select decrypted_secret into v_token from vault.decrypted_secrets where name='black_pages_research_worker_token' order by created_at desc limit 1;
 if nullif(v_token,'') is null then raise exception 'BLACK PAGES worker token missing'; end if;
 select net.http_post(url:='https://dzlmtvodpyhetvektfuo.supabase.co/functions/v1/black-pages-external-discovery-worker',
 headers:=jsonb_build_object('Content-Type','application/json','x-worker-token',v_token),body:=jsonb_build_object('jobs',least(20,greatest(1,p_jobs)))) into v_request_id;
 return v_request_id;
end; $$;
revoke all on function public.black_pages_dispatch_external_worker(integer) from public,anon,authenticated;
grant execute on function public.black_pages_dispatch_external_worker(integer) to service_role;

create or replace function public.black_pages_staff_find_now(p_city text,p_categories text[] default '{}',p_quantity integer default 1000)
returns jsonb language plpgsql security definer set search_path='pg_catalog','public','net','vault','auth' as $$
declare v_role text:=coalesce(auth.jwt()->'app_metadata'->>'khg_role',''); v_state text; v_qty integer:=least(1000,greatest(100,coalesce(p_quantity,1000))); v_queue jsonb; v_class jsonb; v_requests jsonb:='[]'::jsonb; v_id bigint; v_shards integer; i integer; v_token text;
begin
 if v_role not in ('owner','admin','editor') then raise exception 'Staff role required' using errcode='42501'; end if;
 select state into v_state from public.black_pages_city_targets where lower(city)=lower(btrim(p_city)) and is_active order by launch_priority desc limit 1;
 if v_state is null then raise exception 'Unknown target city'; end if;
 v_class:=public.black_pages_auto_classify_batch(20000);
 v_queue:=public.black_pages_queue_external_discovery(p_city,v_state,v_qty,p_categories);
 select decrypted_secret into v_token from vault.decrypted_secrets where name='black_pages_research_worker_token' order by created_at desc limit 1;
 if nullif(v_token,'') is null then raise exception 'BLACK PAGES worker token missing'; end if;
 v_shards:=least(10,ceil(v_qty/100.0)::int);
 for i in 1..v_shards loop
   select net.http_post(url:='https://dzlmtvodpyhetvektfuo.supabase.co/functions/v1/black-pages-external-discovery-worker',
     headers:=jsonb_build_object('Content-Type','application/json','x-worker-token',v_token),body:=jsonb_build_object('jobs',10)) into v_id;
   v_requests:=v_requests||jsonb_build_array(v_id);
 end loop;
 return jsonb_build_object('ok',true,'city',p_city,'state',v_state,'quantity',v_qty,'categories',p_categories,'classification',v_class,'external_queue',v_queue,'external_worker_requests',v_requests,'message','External discovery launched; candidates remain private until verification.');
end; $$;
revoke all on function public.black_pages_staff_find_now(text,text[],integer) from public,anon;
grant execute on function public.black_pages_staff_find_now(text,text[],integer) to authenticated;

select public.black_pages_auto_classify_batch(20000);
