-- BLACK PAGES research execution and QA controls.

create or replace function public.black_pages_claim_research_batch(
  p_limit integer default 10,
  p_worker text default 'black-pages-research-worker'
)
returns jsonb
language plpgsql
security definer
set search_path='pg_catalog','public'
as $function$
declare
  v_limit integer:=least(25,greatest(1,coalesce(p_limit,10)));
  v_worker text:=left(coalesce(nullif(trim(p_worker),''),'black-pages-research-worker'),120);
  v_run_id uuid;
  v_candidates jsonb;
  v_claimed integer;
begin
  if auth.role()<>'service_role' then raise exception 'Service role required' using errcode='42501'; end if;

  insert into public.black_pages_research_runs(worker,requested_limit)
  values(v_worker,v_limit) returning id into v_run_id;

  with due as (
    select q.id
    from public.black_pages_candidate_queue q
    where q.pipeline_stage='research'
      and q.ownership_evidence_status in ('unreviewed','insufficient')
      and q.next_action_at<=now()
      and q.assigned_researcher in ('black-pages-owner-verification-agent',v_worker)
      and not exists(
        select 1 from public.black_pages_candidate_activity a
        where a.candidate_id=q.id and a.activity_type='research' and a.outcome='claimed'
          and a.occurred_at>now()-interval '20 minutes'
      )
    order by q.priority_score desc,q.next_action_at,q.id
    for update skip locked
    limit v_limit
  ), claimed as (
    update public.black_pages_candidate_queue q
    set assigned_researcher=v_worker,next_action_at=now()+interval '30 minutes',updated_at=now()
    from due d where q.id=d.id returning q.*
  ), activities as (
    insert into public.black_pages_candidate_activity(candidate_id,activity_type,outcome,details,performed_by)
    select id,'research','claimed',jsonb_build_object('run_id',v_run_id),v_worker from claimed
    returning candidate_id
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'id',c.id,'business_name',c.business_name,'city',c.city,'state',c.state,
    'category',c.category,'website_url',c.website_url,'instagram_handle',c.instagram_handle,
    'public_email',c.public_email,'public_phone',c.public_phone,'priority_score',c.priority_score
  ) order by c.priority_score desc,c.id),'[]'::jsonb),count(*)::integer
  into v_candidates,v_claimed from claimed c;

  update public.black_pages_research_runs
  set claimed_count=coalesce(v_claimed,0),
      status=case when coalesce(v_claimed,0)=0 then 'completed' else status end,
      completed_at=case when coalesce(v_claimed,0)=0 then now() else completed_at end,
      summary=jsonb_build_object('claimed',coalesce(v_claimed,0))
  where id=v_run_id;

  return jsonb_build_object('run_id',v_run_id,'worker',v_worker,
    'claimed_count',coalesce(v_claimed,0),'candidates',coalesce(v_candidates,'[]'::jsonb));
end;
$function$;

create or replace function public.black_pages_complete_research_candidate(
  p_run_id uuid,p_candidate_id uuid,p_result jsonb,
  p_worker text default 'black-pages-research-worker'
)
returns jsonb
language plpgsql
security definer
set search_path='pg_catalog','public'
as $function$
declare
  v_reachable boolean:=coalesce((p_result->>'reachable')::boolean,false);
  v_explicit boolean:=coalesce((p_result->>'explicit_ownership_evidence')::boolean,false);
  v_error boolean:=nullif(p_result->>'error','') is not null;
  v_outcome text;
  v_prior_completed integer;
  v_stage text;
  v_evidence_status text;
  v_next_action timestamptz;
  v_final_url text:=nullif(left(coalesce(p_result->>'final_url',''),500),'');
begin
  if auth.role()<>'service_role' then raise exception 'Service role required' using errcode='42501'; end if;
  if not exists(select 1 from public.black_pages_research_runs where id=p_run_id and status='started') then
    raise exception 'Active research run not found';
  end if;
  if not exists(select 1 from public.black_pages_candidate_queue where id=p_candidate_id for update) then
    raise exception 'Candidate not found';
  end if;

  select count(*)::integer into v_prior_completed
  from public.black_pages_candidate_activity
  where candidate_id=p_candidate_id and activity_type='research'
    and outcome in ('evidence_found','reachable_no_evidence','unreachable','failed');

  if v_explicit then
    v_outcome:='evidence_found';v_stage:='verification';v_evidence_status:='evidence_found';v_next_action:=now();
  elsif v_reachable then
    v_outcome:='reachable_no_evidence';v_stage:='research';
    v_evidence_status:=case when v_prior_completed>=2 then 'insufficient' else 'unreviewed' end;
    v_next_action:=now()+case when v_prior_completed>=2 then interval '30 days' else interval '7 days' end;
  elsif v_error then
    v_outcome:='failed';v_stage:='research';
    v_evidence_status:=case when v_prior_completed>=2 then 'insufficient' else 'unreviewed' end;
    v_next_action:=now()+case when v_prior_completed>=2 then interval '14 days' else interval '2 days' end;
  else
    v_outcome:='unreachable';v_stage:='research';
    v_evidence_status:=case when v_prior_completed>=2 then 'insufficient' else 'unreviewed' end;
    v_next_action:=now()+case when v_prior_completed>=2 then interval '14 days' else interval '2 days' end;
  end if;

  update public.black_pages_candidate_queue
  set website_url=case when v_final_url ~* '^https?://' then v_final_url else website_url end,
      data_quality_status=case when v_explicit then 'ownership_evidence_found'
        when v_reachable then 'public_endpoint_checked' else 'needs_enrichment' end,
      ownership_evidence_status=v_evidence_status,pipeline_stage=v_stage,
      assigned_researcher=case when v_explicit then 'black-pages-owner-verification-agent'
        else left(coalesce(nullif(trim(p_worker),''),'black-pages-research-worker'),120) end,
      next_action_at=v_next_action,
      notes=left(concat_ws(E'\n',nullif(notes,''),case
        when v_explicit then 'Public ownership language found. Human verification required before any owner-verified label.'
        when v_reachable then 'Public business endpoint checked; no explicit Black-ownership statement found.'
        else 'Public endpoint unavailable or incomplete; no ownership conclusion made.' end),4000),
      updated_at=now()
  where id=p_candidate_id;

  insert into public.black_pages_candidate_activity(candidate_id,activity_type,outcome,details,performed_by)
  values(p_candidate_id,'research',v_outcome,
    coalesce(p_result,'{}'::jsonb)||jsonb_build_object('run_id',p_run_id,
      'ownership_decision','human_review_required','published',false,'owner_verified',false),
    left(coalesce(nullif(trim(p_worker),''),'black-pages-research-worker'),120));

  update public.black_pages_research_runs
  set processed_count=processed_count+1,
      reachable_count=reachable_count+case when v_reachable then 1 else 0 end,
      evidence_found_count=evidence_found_count+case when v_explicit then 1 else 0 end,
      failed_count=failed_count+case when v_error or not v_reachable then 1 else 0 end,
      summary=summary||jsonb_build_object('last_candidate_id',p_candidate_id,'last_outcome',v_outcome)
  where id=p_run_id;

  return jsonb_build_object('candidate_id',p_candidate_id,'outcome',v_outcome,
    'pipeline_stage',v_stage,'ownership_evidence_status',v_evidence_status,
    'published',false,'owner_verified',false);
end;
$function$;

create or replace function public.black_pages_finalize_research_run(p_run_id uuid,p_error text default null)
returns jsonb
language plpgsql
security definer
set search_path='pg_catalog','public'
as $function$
declare v_run public.black_pages_research_runs%rowtype;
begin
  if auth.role()<>'service_role' then raise exception 'Service role required' using errcode='42501'; end if;
  update public.black_pages_research_runs
  set status=case when nullif(trim(coalesce(p_error,'')),'') is null then 'completed' else 'failed' end,
      error_message=nullif(left(coalesce(p_error,''),1000),''),completed_at=now(),
      summary=summary||jsonb_build_object('finished_at',now())
  where id=p_run_id returning * into v_run;
  if not found then raise exception 'Research run not found'; end if;
  return to_jsonb(v_run);
end;
$function$;

revoke all on function public.black_pages_claim_research_batch(integer,text) from public,anon,authenticated;
revoke all on function public.black_pages_complete_research_candidate(uuid,uuid,jsonb,text) from public,anon,authenticated;
revoke all on function public.black_pages_finalize_research_run(uuid,text) from public,anon,authenticated;
grant execute on function public.black_pages_claim_research_batch(integer,text) to service_role;
grant execute on function public.black_pages_complete_research_candidate(uuid,uuid,jsonb,text) to service_role;
grant execute on function public.black_pages_finalize_research_run(uuid,text) to service_role;

create or replace view public.black_pages_research_pipeline_health with (security_invoker=true) as
select count(*)::integer total_candidates,
 count(*) filter(where lower(city)='atlanta')::integer atlanta_candidates,
 count(*) filter(where lower(city)<>'atlanta')::integer expansion_candidates,
 count(*) filter(where assigned_researcher is not null)::integer assigned_candidates,
 count(*) filter(where pipeline_stage='research' and next_action_at<=now())::integer due_research,
 count(*) filter(where ownership_evidence_status='evidence_found')::integer evidence_found,
 count(*) filter(where ownership_evidence_status='owner_confirmed')::integer owner_confirmed,
 count(*) filter(where pipeline_stage='verification')::integer awaiting_verification,
 count(*) filter(where pipeline_stage='published')::integer worker_published,
 (select count(*)::integer from public.black_pages_candidate_activity where activity_type='research' and outcome<>'claimed') completed_research_checks,
 (select count(*)::integer from public.black_pages_research_runs where status='completed') completed_worker_runs,
 now() evaluated_at
from public.black_pages_candidate_queue;
revoke all on public.black_pages_research_pipeline_health from public,anon,authenticated;

create or replace view public.black_pages_category_stock_health with (security_invoker=true) as
with cities as (
 select city,state,target_published_businesses from public.black_pages_city_targets where is_active
), public_counts as (
 select lower(city) city_key,coalesce(state,'') state,public.black_pages_canonical_category(category) category_slug,
 count(*)::integer published_count from public.black_pages_directory
 group by lower(city),coalesce(state,''),public.black_pages_canonical_category(category)
), candidate_counts as (
 select lower(city) city_key,coalesce(state,'') state,public.black_pages_canonical_category(category) category_slug,
 count(*) filter(where pipeline_stage not in ('rejected','do_not_contact'))::integer candidate_count,
 count(*) filter(where ownership_evidence_status='evidence_found')::integer evidence_count
 from public.black_pages_candidate_queue
 group by lower(city),coalesce(state,''),public.black_pages_canonical_category(category)
)
select ci.city,ci.state,c.slug category_slug,c.name category_name,
 coalesce(pc.published_count,0) published_count,coalesce(qc.candidate_count,0) candidate_count,
 coalesce(qc.evidence_count,0) evidence_count,
 greatest(ceil(ci.target_published_businesses/11.0)::integer-coalesce(pc.published_count,0),0) category_publishing_gap,
 c.sort_order
from cities ci cross join public.black_pages_categories c
left join public_counts pc on pc.city_key=lower(ci.city) and pc.state=ci.state and pc.category_slug=c.slug
left join candidate_counts qc on qc.city_key=lower(ci.city) and qc.state=ci.state and qc.category_slug=c.slug
where c.active;
revoke all on public.black_pages_category_stock_health from public,anon,authenticated;
