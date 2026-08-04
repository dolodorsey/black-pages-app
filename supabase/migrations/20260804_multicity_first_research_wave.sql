-- Internal ownership research only. No candidate is published or labeled Black-owned.

with ranked as (
  select q.id,q.city,
         row_number() over(
           partition by q.city
           order by q.priority_score desc,q.id
         ) rn
  from public.black_pages_candidate_queue q
  where lower(q.city)<>'atlanta'
    and q.pipeline_stage='research'
), first_wave as (
  select id from ranked where rn<=25
), sequenced as (
  select q.id,row_number() over(order by q.priority_score desc,q.id) seq
  from public.black_pages_candidate_queue q
  join first_wave f on f.id=q.id
)
update public.black_pages_candidate_queue q
set assigned_researcher='black-pages-owner-verification-agent',
    next_action_at=now()+(s.seq-1)*interval '15 minutes',
    notes=concat_ws(E'\n',nullif(q.notes,''),
      'First multi-city research wave. Do not publish or label Black-owned until ownership evidence or a verified owner claim passes.'),
    updated_at=now()
from sequenced s
where q.id=s.id;

create or replace view public.black_pages_first_wave_summary
with (security_invoker=true)
as
select city,state,
       count(*)::integer candidates,
       count(*) filter(where ownership_evidence_status='owner_confirmed')::integer owner_confirmed,
       round(avg(priority_score),2) average_priority,
       min(next_action_at) next_action_at
from public.black_pages_candidate_queue
where assigned_researcher='black-pages-owner-verification-agent'
group by city,state;

revoke all on public.black_pages_first_wave_summary from public,anon,authenticated;
