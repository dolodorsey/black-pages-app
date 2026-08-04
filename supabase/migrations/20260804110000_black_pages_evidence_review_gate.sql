-- BLACK PAGES human evidence review and owner-verification gate.
-- Public-site evidence can only change a public owner-verified label after a service-role review.
-- This migration never publishes a new directory record and never treats the research worker as a reviewer.

create table if not exists public.black_pages_evidence_reviews (
  id uuid primary key default gen_random_uuid(),
  candidate_id uuid not null unique references public.black_pages_candidate_queue(id) on delete cascade,
  research_activity_id uuid not null unique references public.black_pages_candidate_activity(id) on delete cascade,
  directory_id text,
  source_url text,
  evidence_snapshot jsonb not null default '{}'::jsonb,
  status text not null default 'pending' check(status in ('pending','approved','rejected','needs_more_evidence','revoked')),
  reviewer text,
  decision_reason text,
  reviewed_at timestamptz,
  expires_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

comment on table public.black_pages_evidence_reviews is
  'Private BLACK PAGES human-review ledger for explicit public ownership evidence. Service role only.';

create index if not exists black_pages_evidence_reviews_status_idx
  on public.black_pages_evidence_reviews(status,created_at);
create index if not exists black_pages_evidence_reviews_directory_idx
  on public.black_pages_evidence_reviews(directory_id)
  where directory_id is not null;

alter table public.black_pages_evidence_reviews enable row level security;
revoke all on table public.black_pages_evidence_reviews from public,anon,authenticated;
grant select,insert,update,delete on table public.black_pages_evidence_reviews to service_role;

create or replace function public.black_pages_sync_evidence_review_queue()
returns integer
language plpgsql
security definer
set search_path='pg_catalog','public'
as $function$
declare
  v_count integer;
begin
  if auth.role()<>'service_role' then
    raise exception 'Service role required' using errcode='42501';
  end if;

  with evidence_candidates as (
    select q.id candidate_id,
           a.id research_activity_id,
           case when q.source_venue_id is not null then 'venue:'||q.source_venue_id::text else null end directory_id,
           coalesce(nullif(a.details->>'final_url',''),nullif(a.details->>'checked_url',''),q.website_url) source_url,
           jsonb_build_object(
             'business_name',q.business_name,
             'city',q.city,
             'state',q.state,
             'category',q.category,
             'checked_url',a.details->'checked_url',
             'final_url',a.details->'final_url',
             'fetch_status',a.details->'fetch_status',
             'page_title',a.details->'page_title',
             'explicit_ownership_evidence',a.details->'explicit_ownership_evidence',
             'ownership_evidence',coalesce(a.details->'ownership_evidence','[]'::jsonb),
             'research_run_id',a.details->'run_id',
             'research_checked_at',a.occurred_at
           ) evidence_snapshot
    from public.black_pages_candidate_queue q
    join lateral (
      select a.*
      from public.black_pages_candidate_activity a
      where a.candidate_id=q.id
        and a.activity_type='research'
        and a.outcome='evidence_found'
      order by a.occurred_at desc
      limit 1
    ) a on true
    where q.ownership_evidence_status='evidence_found'
      and q.pipeline_stage='verification'
  ), upserted as (
    insert into public.black_pages_evidence_reviews(
      candidate_id,research_activity_id,directory_id,source_url,evidence_snapshot,status,updated_at
    )
    select candidate_id,research_activity_id,directory_id,source_url,evidence_snapshot,'pending',now()
    from evidence_candidates
    on conflict(candidate_id) do update set
      research_activity_id=excluded.research_activity_id,
      directory_id=excluded.directory_id,
      source_url=excluded.source_url,
      evidence_snapshot=excluded.evidence_snapshot,
      status=case when public.black_pages_evidence_reviews.status in ('approved','rejected','revoked')
        then public.black_pages_evidence_reviews.status else 'pending' end,
      updated_at=now()
    returning id
  )
  select count(*)::integer into v_count from upserted;

  return coalesce(v_count,0);
end;
$function$;

create or replace function public.black_pages_review_public_ownership_evidence(
  p_candidate_id uuid,
  p_decision text,
  p_reviewer text,
  p_reason text,
  p_expiration_months integer default 24
)
returns jsonb
language plpgsql
security definer
set search_path='pg_catalog','public'
as $function$
declare
  v_candidate public.black_pages_candidate_queue%rowtype;
  v_review public.black_pages_evidence_reviews%rowtype;
  v_decision text:=lower(trim(coalesce(p_decision,'')));
  v_reviewer text:=left(trim(coalesce(p_reviewer,'')),160);
  v_reason text:=left(trim(coalesce(p_reason,'')),2000);
  v_expiry timestamptz;
  v_method text:='official_site_explicit_ownership_statement';
begin
  if auth.role()<>'service_role' then
    raise exception 'Service role required' using errcode='42501';
  end if;
  if v_decision not in ('approve','reject','needs_more_evidence') then
    raise exception 'Decision must be approve, reject, or needs_more_evidence';
  end if;
  if v_reviewer='' or v_reason='' then
    raise exception 'Reviewer and decision reason are required';
  end if;

  perform public.black_pages_sync_evidence_review_queue();

  select * into v_candidate
  from public.black_pages_candidate_queue
  where id=p_candidate_id
  for update;
  if not found then raise exception 'Candidate not found'; end if;

  select * into v_review
  from public.black_pages_evidence_reviews
  where candidate_id=p_candidate_id
  for update;
  if not found then raise exception 'Evidence review record not found'; end if;

  if v_decision='approve' then
    if v_candidate.pipeline_stage<>'verification'
       or v_candidate.ownership_evidence_status<>'evidence_found' then
      raise exception 'Candidate is not awaiting evidence verification';
    end if;
    if coalesce((v_review.evidence_snapshot->>'explicit_ownership_evidence')::boolean,false) is not true
       or jsonb_array_length(coalesce(v_review.evidence_snapshot->'ownership_evidence','[]'::jsonb))=0
       or nullif(v_review.source_url,'') is null then
      raise exception 'Explicit public ownership evidence is incomplete';
    end if;
    if v_review.directory_id is null
       or not exists(select 1 from public.black_pages_directory d where d.directory_id=v_review.directory_id) then
      raise exception 'Candidate is not an existing public directory record';
    end if;

    v_expiry:=now()+make_interval(months=>greatest(1,least(coalesce(p_expiration_months,24),36)));

    insert into public.black_pages_owner_verification_public(
      directory_id,claim_id,verification_method,verified_at,expires_at,status,updated_at
    ) values (
      v_review.directory_id,null,v_method,now(),v_expiry,'verified',now()
    )
    on conflict(directory_id) do update set
      claim_id=null,
      verification_method=excluded.verification_method,
      verified_at=excluded.verified_at,
      expires_at=excluded.expires_at,
      status='verified',
      updated_at=now();

    update public.black_pages_candidate_queue
    set ownership_evidence_status='owner_confirmed',
        pipeline_stage='approved',
        assigned_researcher=v_reviewer,
        next_action_at=v_expiry-interval '30 days',
        notes=left(concat_ws(E'\n',nullif(notes,''),
          'Human review approved explicit ownership evidence. Public owner-verification expires on '||v_expiry::date||'.'),4000),
        updated_at=now()
    where id=p_candidate_id;

    update public.black_pages_evidence_reviews
    set status='approved',reviewer=v_reviewer,decision_reason=v_reason,
        reviewed_at=now(),expires_at=v_expiry,updated_at=now()
    where candidate_id=p_candidate_id;

  elsif v_decision='reject' then
    update public.black_pages_candidate_queue
    set ownership_evidence_status='insufficient',
        pipeline_stage='research',
        assigned_researcher=v_reviewer,
        next_action_at=now()+interval '90 days',
        notes=left(concat_ws(E'\n',nullif(notes,''),'Human review rejected the captured ownership evidence.'),4000),
        updated_at=now()
    where id=p_candidate_id;

    update public.black_pages_evidence_reviews
    set status='rejected',reviewer=v_reviewer,decision_reason=v_reason,
        reviewed_at=now(),expires_at=null,updated_at=now()
    where candidate_id=p_candidate_id;

  else
    update public.black_pages_candidate_queue
    set ownership_evidence_status='unreviewed',
        pipeline_stage='research',
        assigned_researcher=v_reviewer,
        next_action_at=now()+interval '7 days',
        notes=left(concat_ws(E'\n',nullif(notes,''),'Human review requested additional ownership evidence.'),4000),
        updated_at=now()
    where id=p_candidate_id;

    update public.black_pages_evidence_reviews
    set status='needs_more_evidence',reviewer=v_reviewer,decision_reason=v_reason,
        reviewed_at=now(),expires_at=null,updated_at=now()
    where candidate_id=p_candidate_id;
  end if;

  insert into public.black_pages_candidate_activity(
    candidate_id,activity_type,outcome,details,performed_by
  ) values (
    p_candidate_id,'verification_note',v_decision,
    jsonb_build_object(
      'directory_id',v_review.directory_id,
      'source_url',v_review.source_url,
      'decision_reason',v_reason,
      'verification_method',case when v_decision='approve' then v_method else null end,
      'expires_at',v_expiry,
      'automated_decision',false,
      'new_directory_record_published',false
    ),v_reviewer
  );

  return jsonb_build_object(
    'candidate_id',p_candidate_id,
    'directory_id',v_review.directory_id,
    'decision',v_decision,
    'owner_verified',v_decision='approve',
    'verification_method',case when v_decision='approve' then v_method else null end,
    'expires_at',v_expiry,
    'new_directory_record_published',false
  );
end;
$function$;

create or replace function public.black_pages_revoke_public_ownership_verification(
  p_candidate_id uuid,
  p_reviewer text,
  p_reason text
)
returns jsonb
language plpgsql
security definer
set search_path='pg_catalog','public'
as $function$
declare
  v_review public.black_pages_evidence_reviews%rowtype;
  v_reviewer text:=left(trim(coalesce(p_reviewer,'')),160);
  v_reason text:=left(trim(coalesce(p_reason,'')),2000);
begin
  if auth.role()<>'service_role' then
    raise exception 'Service role required' using errcode='42501';
  end if;
  if v_reviewer='' or v_reason='' then
    raise exception 'Reviewer and reason are required';
  end if;

  select * into v_review
  from public.black_pages_evidence_reviews
  where candidate_id=p_candidate_id
  for update;
  if not found or v_review.status<>'approved' then
    raise exception 'Approved evidence review not found';
  end if;

  update public.black_pages_owner_verification_public
  set status='revoked',updated_at=now()
  where directory_id=v_review.directory_id;

  update public.black_pages_candidate_queue
  set ownership_evidence_status='unreviewed',pipeline_stage='verification',
      assigned_researcher=v_reviewer,next_action_at=now(),
      notes=left(concat_ws(E'\n',nullif(notes,''),'Public ownership verification revoked: '||v_reason),4000),
      updated_at=now()
  where id=p_candidate_id;

  update public.black_pages_evidence_reviews
  set status='revoked',reviewer=v_reviewer,decision_reason=v_reason,
      reviewed_at=now(),expires_at=null,updated_at=now()
  where candidate_id=p_candidate_id;

  insert into public.black_pages_candidate_activity(candidate_id,activity_type,outcome,details,performed_by)
  values(p_candidate_id,'verification_note','revoked',
    jsonb_build_object('directory_id',v_review.directory_id,'reason',v_reason,'automated_decision',false),v_reviewer);

  return jsonb_build_object('candidate_id',p_candidate_id,'directory_id',v_review.directory_id,'revoked',true);
end;
$function$;

create or replace view public.black_pages_evidence_review_health
with (security_invoker=true)
as
select
  count(*)::integer total_reviews,
  count(*) filter(where status='pending')::integer pending_reviews,
  count(*) filter(where status='approved')::integer approved_reviews,
  count(*) filter(where status='rejected')::integer rejected_reviews,
  count(*) filter(where status='needs_more_evidence')::integer needs_more_evidence,
  count(*) filter(where status='revoked')::integer revoked_reviews,
  count(*) filter(where status='approved' and expires_at>now())::integer active_public_verifications,
  min(created_at) filter(where status='pending') oldest_pending_at,
  now() evaluated_at
from public.black_pages_evidence_reviews;

revoke all on function public.black_pages_sync_evidence_review_queue() from public,anon,authenticated;
revoke all on function public.black_pages_review_public_ownership_evidence(uuid,text,text,text,integer) from public,anon,authenticated;
revoke all on function public.black_pages_revoke_public_ownership_verification(uuid,text,text) from public,anon,authenticated;
grant execute on function public.black_pages_sync_evidence_review_queue() to service_role;
grant execute on function public.black_pages_review_public_ownership_evidence(uuid,text,text,text,integer) to service_role;
grant execute on function public.black_pages_revoke_public_ownership_verification(uuid,text,text) to service_role;

revoke all on table public.black_pages_evidence_review_health from public,anon,authenticated;
grant select on table public.black_pages_evidence_review_health to service_role;

select public.black_pages_sync_evidence_review_queue();
