-- Scale THE BLACK PAGES from small serial research batches to bulk private discovery.

alter table public.black_pages_candidate_queue drop constraint if exists black_pages_candidate_source_type_check;
alter table public.black_pages_candidate_queue add constraint black_pages_candidate_source_type_check
check (source_type = any(array['blackbook_contact','venue_intelligence','owner_submission','research','directory_listing','contacts_master','bulk_discovery']::text[]));

create unique index if not exists black_pages_candidate_source_external_key_uidx
on public.black_pages_candidate_queue(source_external_key) where source_external_key is not null;

create or replace function public.black_pages_map_bulk_category(p_category text)
returns text language sql immutable as $$
select case lower(trim(coalesce(p_category,'')))
  when 'nightlife' then 'nightlife-entertainment'
  when 'nightclub' then 'nightlife-entertainment'
  when 'hookah' then 'nightlife-entertainment'
  when 'lounge' then 'nightlife-entertainment'
  when 'speakeasy' then 'nightlife-entertainment'
  when 'jazz' then 'nightlife-entertainment'
  when 'restaurant' then 'food-beverage'
  when 'brunch' then 'food-beverage'
  when 'bar' then 'food-beverage'
  when 'coffee' then 'food-beverage'
  when 'food' then 'food-beverage'
  when 'food_hall' then 'food-beverage'
  when 'wine_bar' then 'food-beverage'
  when 'sports_bar' then 'food-beverage'
  when 'event_venue' then 'venues-spaces'
  when 'culture' then 'arts-culture'
  when 'comedy' then 'arts-culture'
  when 'beauty' then 'beauty-wellness'
  when 'spa' then 'beauty-wellness'
  when 'shopping' then 'retail'
  when 'fitness' then 'sports-fitness'
  else public.black_pages_canonical_category(p_category)
end; $$;

create or replace function public.black_pages_map_bulk_subcategory(p_category text)
returns text language sql immutable as $$
select case lower(trim(coalesce(p_category,'')))
  when 'nightclub' then 'nightclubs'
  when 'hookah' then 'hookah-lounges'
  when 'lounge' then 'lounges'
  when 'nightlife' then 'lounges'
  when 'speakeasy' then 'lounges'
  when 'jazz' then 'jazz-clubs'
  when 'restaurant' then 'restaurants'
  when 'brunch' then 'restaurants'
  when 'bar' then 'bars'
  when 'coffee' then 'coffee-shops'
  when 'food' then 'restaurants'
  when 'food_hall' then 'restaurants'
  when 'wine_bar' then 'wine-bars'
  when 'sports_bar' then 'sports-bars'
  when 'event_venue' then 'event-venues'
  when 'culture' then 'cultural-centers'
  when 'comedy' then 'performing-arts-centers'
  when 'beauty' then 'salons'
  when 'spa' then 'spas'
  when 'shopping' then 'general-retail'
  when 'fitness' then 'gyms'
  else null
end; $$;

create or replace function public.black_pages_bulk_ingest_internal_candidates(p_limit integer default 5000)
returns jsonb language plpgsql security definer set search_path='pg_catalog','public' as $$
declare v_limit integer:=least(10000,greatest(100,coalesce(p_limit,5000))); v_directory integer:=0; v_contacts integer:=0;
begin
  with src as (
    select d.id, d.name business_name, d.city, d.state, d.category,
      nullif(trim(d.website_url),'') website_url, nullif(trim(d.instagram_handle),'') instagram_handle,
      null::text public_email, nullif(trim(d.phone),'') public_phone,
      'directory_listing:'||d.id::text source_key
    from public.directory_listings d
    where nullif(trim(d.name),'') is not null and nullif(trim(d.city),'') is not null
      and lower(coalesce(d.category,'')) not in ('day_party','pool_party','special_events','brunch_party')
    order by d.id limit v_limit
  ), ins as (
    insert into public.black_pages_candidate_queue(
      business_name,city,state,category,subcategory,website_url,instagram_handle,public_email,public_phone,
      source_sheets,data_quality_status,ownership_evidence_status,pipeline_stage,priority_score,next_action_at,source_type,source_external_key,notes
    )
    select s.business_name,s.city,nullif(trim(s.state),''),public.black_pages_map_bulk_category(s.category),public.black_pages_map_bulk_subcategory(s.category),
      s.website_url,s.instagram_handle,s.public_email,s.public_phone,array['directory_listings'],'bulk_discovered','unreviewed','research',
      45 + case when s.website_url is not null then 20 else 0 end + case when s.instagram_handle is not null then 10 else 0 end,
      now(),'directory_listing',s.source_key,'Bulk-discovered private candidate. Ownership must be verified before publication.'
    from src s
    where not exists(select 1 from public.black_pages_candidate_queue q where q.source_external_key=s.source_key)
      and not exists(select 1 from public.black_pages_candidate_queue q where lower(q.business_name)=lower(s.business_name) and lower(q.city)=lower(s.city) and coalesce(q.state,'')=coalesce(nullif(trim(s.state),''),''))
    on conflict(source_external_key) where source_external_key is not null do nothing returning 1
  ) select count(*) into v_directory from ins;

  with src as (
    select c.id, c.company business_name, c.city, c.state, nullif(trim(c.website),'') website_url,
      nullif(trim(c.instagram_handle),'') instagram_handle, nullif(trim(c.email),'') public_email, nullif(trim(c.phone),'') public_phone,
      'contacts_master:'||c.id::text source_key
    from public.contacts_master c
    where nullif(trim(c.company),'') is not null and nullif(trim(c.city),'') is not null
    order by c.id limit v_limit
  ), ins as (
    insert into public.black_pages_candidate_queue(
      business_name,city,state,category,subcategory,website_url,instagram_handle,public_email,public_phone,
      source_sheets,data_quality_status,ownership_evidence_status,pipeline_stage,priority_score,next_action_at,source_type,source_external_key,notes
    )
    select s.business_name,s.city,nullif(trim(s.state),''),null,null,s.website_url,s.instagram_handle,s.public_email,s.public_phone,
      array['contacts_master'],'bulk_discovered','unreviewed','research',
      35 + case when s.website_url is not null then 20 else 0 end + case when s.instagram_handle is not null then 10 else 0 end + case when s.public_email is not null then 5 else 0 end,
      now(),'contacts_master',s.source_key,'Bulk-discovered private candidate. Ownership and business category must be verified before publication.'
    from src s
    where not exists(select 1 from public.black_pages_candidate_queue q where q.source_external_key=s.source_key)
      and not exists(select 1 from public.black_pages_candidate_queue q where lower(q.business_name)=lower(s.business_name) and lower(q.city)=lower(s.city) and coalesce(q.state,'')=coalesce(nullif(trim(s.state),''),''))
    on conflict(source_external_key) where source_external_key is not null do nothing returning 1
  ) select count(*) into v_contacts from ins;

  return jsonb_build_object('directory_listings_added',v_directory,'contacts_master_added',v_contacts,'total_added',v_directory+v_contacts);
end; $$;

revoke all on function public.black_pages_bulk_ingest_internal_candidates(integer) from public,anon,authenticated;

create or replace function public.black_pages_claim_research_batch(p_limit integer default 100,p_worker text default 'black-pages-research-worker')
returns jsonb language plpgsql security definer set search_path='pg_catalog','public' as $$
declare v_limit integer:=least(500,greatest(1,coalesce(p_limit,100))); v_worker text:=left(coalesce(nullif(trim(p_worker),''),'black-pages-research-worker'),120); v_run_id uuid; v_candidates jsonb; v_claimed integer;
begin
 if auth.role()<>'service_role' then raise exception 'Service role required' using errcode='42501'; end if;
 insert into public.black_pages_research_runs(worker,requested_limit) values(v_worker,v_limit) returning id into v_run_id;
 with due as (
  select q.id from public.black_pages_candidate_queue q
  where q.pipeline_stage='research' and q.ownership_evidence_status in ('unreviewed','insufficient') and q.next_action_at<=now()
    and (q.assigned_researcher is null or q.assigned_researcher in ('black-pages-owner-verification-agent','black-pages-research-worker',v_worker))
    and not exists(select 1 from public.black_pages_candidate_activity a where a.candidate_id=q.id and a.activity_type='research' and a.outcome='claimed' and a.occurred_at>now()-interval '20 minutes')
  order by q.priority_score desc,q.next_action_at,q.id for update skip locked limit v_limit
 ), claimed as (
  update public.black_pages_candidate_queue q set assigned_researcher=v_worker,next_action_at=now()+interval '30 minutes',updated_at=now() from due d where q.id=d.id returning q.*
 ), activities as (
  insert into public.black_pages_candidate_activity(candidate_id,activity_type,outcome,details,performed_by)
  select id,'research','claimed',jsonb_build_object('run_id',v_run_id),v_worker from claimed returning candidate_id
 )
 select coalesce(jsonb_agg(jsonb_build_object('id',c.id,'business_name',c.business_name,'city',c.city,'state',c.state,'category',c.category,'subcategory',c.subcategory,'website_url',c.website_url,'instagram_handle',c.instagram_handle,'public_email',c.public_email,'public_phone',c.public_phone,'priority_score',c.priority_score) order by c.priority_score desc,c.id),'[]'::jsonb),count(*)::integer into v_candidates,v_claimed from claimed c;
 update public.black_pages_research_runs set claimed_count=coalesce(v_claimed,0),status=case when coalesce(v_claimed,0)=0 then 'completed' else status end,completed_at=case when coalesce(v_claimed,0)=0 then now() else completed_at end,summary=jsonb_build_object('claimed',coalesce(v_claimed,0),'bulk_mode',true) where id=v_run_id;
 return jsonb_build_object('run_id',v_run_id,'worker',v_worker,'claimed_count',coalesce(v_claimed,0),'candidates',coalesce(v_candidates,'[]'::jsonb));
end; $$;

create or replace function public.black_pages_dispatch_research_worker(p_limit integer default 100)
returns bigint language plpgsql security definer set search_path='pg_catalog','public','net','vault' as $$
declare v_token text; v_request_id bigint;
begin
 select decrypted_secret into v_token from vault.decrypted_secrets where name='black_pages_research_worker_token' order by created_at desc limit 1;
 if nullif(v_token,'') is null then raise exception 'BLACK PAGES worker token missing'; end if;
 select net.http_post(url:='https://dzlmtvodpyhetvektfuo.supabase.co/functions/v1/black-pages-research-worker',headers:=jsonb_build_object('Content-Type','application/json','x-worker-token',v_token),body:=jsonb_build_object('limit',least(500,greatest(1,coalesce(p_limit,100))))) into v_request_id;
 return v_request_id;
end; $$;

select cron.unschedule(jobid) from cron.job where jobname='black-pages-research-worker';
select cron.schedule('black-pages-research-worker-a','*/5 * * * *',$$select public.black_pages_dispatch_research_worker(100);$$);
select cron.schedule('black-pages-research-worker-b','*/5 * * * *',$$select public.black_pages_dispatch_research_worker(100);$$);
select cron.schedule('black-pages-research-worker-c','*/5 * * * *',$$select public.black_pages_dispatch_research_worker(100);$$);
select cron.schedule('black-pages-research-worker-d','*/5 * * * *',$$select public.black_pages_dispatch_research_worker(100);$$);
select cron.schedule('black-pages-bulk-internal-ingest','17 * * * *',$$select public.black_pages_bulk_ingest_internal_candidates(5000);$$);
