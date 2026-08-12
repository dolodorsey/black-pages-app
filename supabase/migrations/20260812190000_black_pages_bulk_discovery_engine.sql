-- THE BLACK PAGES: high-throughput discovery and research fan-out.
-- Bulk-loads private enterprise company leads, keeps them unverified, and processes research in parallel.

alter table public.black_pages_candidate_queue
  add column if not exists source_external_key text;

create unique index if not exists black_pages_candidate_source_external_key_uidx
  on public.black_pages_candidate_queue(source_type,source_external_key)
  where source_external_key is not null;

alter table public.black_pages_research_runs
  drop constraint if exists black_pages_research_runs_requested_limit_check;
alter table public.black_pages_research_runs
  add constraint black_pages_research_runs_requested_limit_check check(requested_limit between 1 and 100);

create or replace function public.black_pages_seed_enterprise_company_leads()
returns jsonb
language plpgsql
security definer
set search_path='pg_catalog','public'
as $function$
declare v_inserted integer:=0;
begin
  if auth.role()<>'service_role' then raise exception 'Service role required' using errcode='42501'; end if;

  with citymap(city,state) as (
    values ('Atlanta','GA'),('Houston','TX'),('Dallas','TX'),('Charlotte','NC'),('Miami','FL'),
           ('New York','NY'),('Los Angeles','CA'),('Las Vegas','NV'),('Washington DC','DC'),
           ('Memphis','TN'),('Phoenix','AZ')
  ), source_rows as (
    select c.id,
      left(btrim(c.company),220) business_name,
      m.city,m.state,
      nullif(btrim(c.website),'') website_url,
      nullif(regexp_replace(btrim(coalesce(c.instagram_handle,'')),'^@','','g'),'') instagram_handle,
      nullif(btrim(c.email),'') public_email,
      nullif(btrim(c.phone),'') public_phone,
      coalesce(c.source,'contacts_master') source_name,
      coalesce(c.source_detail,'') source_detail,
      case
        when nullif(btrim(c.website),'') is not null then nullif(btrim(c.website),'')
        when nullif(btrim(c.instagram_handle),'') is not null then 'https://www.instagram.com/'||regexp_replace(btrim(c.instagram_handle),'^@','','g')||'/'
        else null
      end research_url
    from public.contacts_master c
    join citymap m on lower(btrim(c.city))=lower(m.city)
    where nullif(btrim(c.company),'') is not null
  ), inserted as (
    insert into public.black_pages_candidate_queue(
      source_type,source_external_key,business_name,city,state,category,subcategory,website_url,
      instagram_handle,public_email,public_phone,source_sheets,data_quality_status,
      ownership_evidence_status,pipeline_stage,priority_score,assigned_researcher,next_action_at,notes
    )
    select 'research','contacts_master:'||s.id::text,s.business_name,s.city,s.state,null,null,s.research_url,
      s.instagram_handle,s.public_email,s.public_phone,array_remove(array[s.source_name,s.source_detail],''),
      case when s.research_url is not null then 'research_ready' else 'needs_enrichment' end,
      'unreviewed','research',
      (35 + case when s.website_url is not null then 20 else 0 end + case when s.instagram_handle is not null then 12 else 0 end +
       case when s.public_phone is not null then 6 else 0 end + case when s.public_email is not null then 6 else 0 end)::numeric,
      'black-pages-research-worker',now(),
      'Bulk enterprise-company discovery lead. This record is NOT verified as Black-owned and must pass ownership evidence review before publication.'
    from source_rows s
    where not exists (
      select 1 from public.black_pages_candidate_queue q
      where lower(btrim(q.business_name))=lower(btrim(s.business_name))
        and lower(btrim(q.city))=lower(btrim(s.city))
        and q.pipeline_stage not in ('rejected','do_not_contact')
    )
    on conflict(source_type,source_external_key) where source_external_key is not null do nothing
    returning id
  )
  select count(*)::integer into v_inserted from inserted;

  return jsonb_build_object('inserted',v_inserted,'source','contacts_master','target_markets',11);
end;
$function$;

revoke all on function public.black_pages_seed_enterprise_company_leads() from public,anon,authenticated;
grant execute on function public.black_pages_seed_enterprise_company_leads() to service_role;

create or replace function public.black_pages_bulk_ingest_discovery(p_items jsonb,p_source text default 'bulk_api')
returns jsonb
language plpgsql
security definer
set search_path='pg_catalog','public'
as $function$
declare v_source text:=left(coalesce(nullif(btrim(p_source),''),'bulk_api'),80); v_inserted integer:=0;
begin
  if auth.role()<>'service_role' then raise exception 'Service role required' using errcode='42501'; end if;
  if jsonb_typeof(p_items)<>'array' then raise exception 'p_items must be a JSON array'; end if;
  if jsonb_array_length(p_items)>1000 then raise exception 'Maximum 1000 discovery records per request'; end if;

  with raw as (
    select value item,ordinality n from jsonb_array_elements(p_items) with ordinality
  ), clean as (
    select
      left(coalesce(nullif(btrim(item->>'business_name'),''),nullif(btrim(item->>'name'),'')),220) business_name,
      left(coalesce(nullif(btrim(item->>'city'),''),'Unknown'),120) city,
      nullif(upper(left(btrim(item->>'state'),2)),'') state,
      nullif(left(btrim(item->>'category'),100),'') category,
      nullif(left(btrim(item->>'subcategory'),100),'') subcategory,
      nullif(left(btrim(item->>'website_url'),600),'') website_url,
      nullif(left(regexp_replace(btrim(coalesce(item->>'instagram_handle','')),'^@','','g'),100),'') instagram_handle,
      nullif(left(btrim(item->>'email'),254),'') public_email,
      nullif(left(btrim(item->>'phone'),40),'') public_phone,
      left(coalesce(nullif(btrim(item->>'source_key'),''),n::text),180) source_key,
      item source_payload
    from raw
  ), inserted as (
    insert into public.black_pages_candidate_queue(
      source_type,source_external_key,business_name,city,state,category,subcategory,website_url,instagram_handle,
      public_email,public_phone,source_sheets,data_quality_status,ownership_evidence_status,pipeline_stage,
      priority_score,assigned_researcher,next_action_at,notes
    )
    select 'research',v_source||':'||source_key,business_name,city,state,category,subcategory,
      coalesce(website_url,case when instagram_handle is not null then 'https://www.instagram.com/'||instagram_handle||'/' end),
      instagram_handle,public_email,public_phone,array[v_source],
      case when website_url is not null or instagram_handle is not null then 'research_ready' else 'needs_enrichment' end,
      'unreviewed','research',45,'black-pages-research-worker',now(),
      left('Bulk discovery intake. Unverified Black-ownership candidate. Source payload: '||source_payload::text,4000)
    from clean where business_name is not null
    on conflict(source_type,source_external_key) where source_external_key is not null do nothing
    returning id
  ) select count(*)::integer into v_inserted from inserted;

  return jsonb_build_object('inserted',v_inserted,'received',jsonb_array_length(p_items),'source',v_source);
end;
$function$;

revoke all on function public.black_pages_bulk_ingest_discovery(jsonb,text) from public,anon,authenticated;
grant execute on function public.black_pages_bulk_ingest_discovery(jsonb,text) to service_role;

create or replace function public.black_pages_claim_research_batch(
  p_limit integer default 50,
  p_worker text default 'black-pages-research-worker'
)
returns jsonb
language plpgsql
security definer
set search_path='pg_catalog','public'
as $function$
declare
  v_limit integer:=least(100,greatest(1,coalesce(p_limit,50)));
  v_worker text:=left(coalesce(nullif(trim(p_worker),''),'black-pages-research-worker'),120);
  v_run_id uuid; v_candidates jsonb; v_claimed integer;
begin
  if auth.role()<>'service_role' then raise exception 'Service role required' using errcode='42501'; end if;
  insert into public.black_pages_research_runs(worker,requested_limit) values(v_worker,v_limit) returning id into v_run_id;

  with due as (
    select q.id from public.black_pages_candidate_queue q
    where q.pipeline_stage='research'
      and q.ownership_evidence_status in ('unreviewed','insufficient')
      and q.next_action_at<=now()
      and (q.assigned_researcher is null or q.assigned_researcher in ('black-pages-owner-verification-agent','black-pages-research-worker',v_worker))
      and not exists(
        select 1 from public.black_pages_candidate_activity a
        where a.candidate_id=q.id and a.activity_type='research' and a.outcome='claimed'
          and a.occurred_at>now()-interval '20 minutes'
      )
    order by q.priority_score desc,q.next_action_at,q.id
    for update skip locked limit v_limit
  ), claimed as (
    update public.black_pages_candidate_queue q
    set assigned_researcher=v_worker,next_action_at=now()+interval '30 minutes',updated_at=now()
    from due d where q.id=d.id returning q.*
  ), activities as (
    insert into public.black_pages_candidate_activity(candidate_id,activity_type,outcome,details,performed_by)
    select id,'research','claimed',jsonb_build_object('run_id',v_run_id),v_worker from claimed returning candidate_id
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'id',c.id,'business_name',c.business_name,'city',c.city,'state',c.state,'category',c.category,
    'subcategory',c.subcategory,'website_url',c.website_url,'instagram_handle',c.instagram_handle,
    'public_email',c.public_email,'public_phone',c.public_phone,'priority_score',c.priority_score
  ) order by c.priority_score desc,c.id),'[]'::jsonb),count(*)::integer
  into v_candidates,v_claimed from claimed c;

  update public.black_pages_research_runs
  set claimed_count=coalesce(v_claimed,0),status=case when coalesce(v_claimed,0)=0 then 'completed' else status end,
      completed_at=case when coalesce(v_claimed,0)=0 then now() else completed_at end,
      summary=jsonb_build_object('claimed',coalesce(v_claimed,0),'bulk_mode',true)
  where id=v_run_id;

  return jsonb_build_object('run_id',v_run_id,'worker',v_worker,'claimed_count',coalesce(v_claimed,0),'candidates',coalesce(v_candidates,'[]'::jsonb));
end;
$function$;

revoke all on function public.black_pages_claim_research_batch(integer,text) from public,anon,authenticated;
grant execute on function public.black_pages_claim_research_batch(integer,text) to service_role;

create or replace function public.black_pages_dispatch_research_worker(p_limit integer default 100)
returns bigint
language plpgsql
security definer
set search_path='pg_catalog','public','net','vault'
as $function$
declare v_token text; v_request_id bigint;
begin
  select decrypted_secret into v_token from vault.decrypted_secrets
  where name='black_pages_research_worker_token' order by created_at desc limit 1;
  if nullif(v_token,'') is null then raise exception 'BLACK PAGES worker token missing'; end if;
  select net.http_post(
    url:='https://dzlmtvodpyhetvektfuo.supabase.co/functions/v1/black-pages-research-worker',
    headers:=jsonb_build_object('Content-Type','application/json','x-worker-token',v_token),
    body:=jsonb_build_object('limit',least(100,greatest(1,coalesce(p_limit,100))))
  ) into v_request_id;
  return v_request_id;
end;
$function$;

revoke all on function public.black_pages_dispatch_research_worker(integer) from public,anon,authenticated;
grant execute on function public.black_pages_dispatch_research_worker(integer) to service_role;

-- Replace the small research cadence with staggered high-throughput dispatches.
do $block$
declare r record;
begin
  for r in select jobid from cron.job where jobname in (
    'black-pages-research-worker','black-pages-research-worker-b','black-pages-research-worker-c','black-pages-research-worker-d'
  ) loop perform cron.unschedule(r.jobid); end loop;
end $block$;
select cron.schedule('black-pages-research-worker','*/5 * * * *',$$select public.black_pages_dispatch_research_worker(100);$$);
select cron.schedule('black-pages-research-worker-b','1-59/5 * * * *',$$select public.black_pages_dispatch_research_worker(100);$$);
select cron.schedule('black-pages-research-worker-c','2-59/5 * * * *',$$select public.black_pages_dispatch_research_worker(100);$$);
select cron.schedule('black-pages-research-worker-d','3-59/5 * * * *',$$select public.black_pages_dispatch_research_worker(100);$$);
