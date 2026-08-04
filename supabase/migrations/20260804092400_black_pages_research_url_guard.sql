-- Preserve canonical candidate URLs. Redirect destinations remain evidence only.
update public.black_pages_candidate_queue q
set website_url=v.website,updated_at=now()
from public.gt_venues v
where q.source_venue_id=v.id
  and nullif(v.website,'') is not null
  and q.website_url is distinct from v.website;

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
  set data_quality_status=case when v_explicit then 'ownership_evidence_found'
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
      'ownership_decision','human_review_required','published',false,'owner_verified',false,
      'canonical_url_preserved',true),
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
    'published',false,'owner_verified',false,'canonical_url_preserved',true);
end;
$function$;

revoke all on function public.black_pages_complete_research_candidate(uuid,uuid,jsonb,text) from public,anon,authenticated;
grant execute on function public.black_pages_complete_research_candidate(uuid,uuid,jsonb,text) to service_role;
