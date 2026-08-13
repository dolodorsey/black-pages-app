-- Snapshot the first 100 legacy Ready identities into a recommendation pack.
-- Recommendations never mutate verification or publication status; authenticated staff applies decisions through the existing audited review function.
create table if not exists public.black_pages_identity_review_packs(
 id uuid primary key default gen_random_uuid(),
 pack_key text not null unique,
 title text not null,
 status text not null default 'open' check(status in('open','completed','archived')),
 total_items integer not null default 0,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now()
);
create table if not exists public.black_pages_identity_review_pack_items(
 id uuid primary key default gen_random_uuid(),
 pack_id uuid not null references public.black_pages_identity_review_packs(id) on delete cascade,
 identity_id uuid not null references public.black_pages_candidate_identities(id) on delete cascade,
 rank integer not null,
 recommended_decision text not null check(recommended_decision in('approve','reject','needs_more_evidence')),
 recommendation_reason text not null,
 source_snapshot jsonb not null default '{}'::jsonb,
 created_at timestamptz not null default now(),
 unique(pack_id,identity_id)
);
create index if not exists black_pages_identity_review_pack_items_rank_idx on public.black_pages_identity_review_pack_items(pack_id,rank);
alter table public.black_pages_identity_review_packs enable row level security;
alter table public.black_pages_identity_review_pack_items enable row level security;
revoke all on public.black_pages_identity_review_packs,public.black_pages_identity_review_pack_items from public,anon,authenticated;
grant all on public.black_pages_identity_review_packs,public.black_pages_identity_review_pack_items to service_role;

insert into public.black_pages_identity_review_packs(pack_key,title,status)
values('first_100_ready_20260813','First 100 — ownership evidence review','open')
on conflict(pack_key) do update set title=excluded.title,updated_at=now();

with p as(select id from public.black_pages_identity_review_packs where pack_key='first_100_ready_20260813'),
ranked as(
 select s.*,row_number() over(order by (case when s.certified_black_source then 1 else 0 end) desc,s.source_count desc,s.max_verification_score desc,s.identity_confidence desc,s.business_name) rn
 from public.black_pages_candidate_identity_summary s
 where s.review_tier='ready' and s.status not in('reviewed','rejected')
), top100 as(select * from ranked where rn<=100)
insert into public.black_pages_identity_review_pack_items(pack_id,identity_id,rank,recommended_decision,recommendation_reason,source_snapshot)
select p.id,t.identity_id,t.rn,
 case
  when 'black_restaurant_week_national'=any(t.source_keys) then 'approve'
  when lower(t.business_name) in('citizens bank','pikes peak library district','amazon','aecom hunt','aaa auto club group','addition financial credit union') then 'reject'
  else 'needs_more_evidence' end,
 case
  when 'black_restaurant_week_national'=any(t.source_keys) then 'Black Restaurant Week provides explicit public Black-owned culinary/business evidence; approve ownership evidence, not publication.'
  when lower(t.business_name) in('citizens bank','pikes peak library district','amazon','aecom hunt','aaa auto club group','addition financial credit union') then 'Institutional/corporate ownership structure requires rejection from Black-owned business listing eligibility.'
  else 'Black Chamber membership alone does not establish Black ownership; obtain independent ownership corroboration.' end,
 jsonb_build_object('business_name',t.business_name,'city',t.city,'state',t.state,'source_keys',t.source_keys,'source_names',t.source_names,'evidence_urls',t.evidence_urls,'legacy_score',t.max_verification_score)
from top100 t cross join p
on conflict(pack_id,identity_id) do nothing;
update public.black_pages_identity_review_packs p set total_items=(select count(*) from public.black_pages_identity_review_pack_items i where i.pack_id=p.id),updated_at=now() where p.pack_key='first_100_ready_20260813';

create or replace function public.black_pages_staff_review_pack_snapshot(p_pack_key text default 'first_100_ready_20260813')
returns jsonb language plpgsql security definer set search_path='pg_catalog','public','auth' as $$
declare v_role text:=coalesce(auth.jwt()->'app_metadata'->>'khg_role','');v_result jsonb;
begin
 if v_role not in('owner','admin','editor') then raise exception 'Staff access required' using errcode='42501';end if;
 select jsonb_build_object('pack',to_jsonb(p),'counts',jsonb_build_object(
   'approve',count(*) filter(where i.recommended_decision='approve'),
   'needs_more_evidence',count(*) filter(where i.recommended_decision='needs_more_evidence'),
   'reject',count(*) filter(where i.recommended_decision='reject')),
  'items',coalesce(jsonb_agg(jsonb_build_object('identity_id',i.identity_id,'rank',i.rank,'recommended_decision',i.recommended_decision,'recommendation_reason',i.recommendation_reason,'source_snapshot',i.source_snapshot) order by i.rank),'[]'::jsonb))
 into v_result
 from public.black_pages_identity_review_packs p join public.black_pages_identity_review_pack_items i on i.pack_id=p.id
 where p.pack_key=p_pack_key group by p.id;
 return coalesce(v_result,jsonb_build_object('pack',null,'counts',jsonb_build_object(),'items','[]'::jsonb));
end $$;
revoke all on function public.black_pages_staff_review_pack_snapshot(text) from public,anon,authenticated;
grant execute on function public.black_pages_staff_review_pack_snapshot(text) to authenticated;