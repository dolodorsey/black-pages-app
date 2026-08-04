-- BLACK PAGES multi-city expansion research pipeline.
-- Non-Atlanta venue intelligence enters an internal research queue only.
-- Nothing is published or labeled Black-owned until ownership evidence is reviewed.

create table if not exists public.black_pages_candidate_queue (
  id uuid primary key default gen_random_uuid(),
  source_contact_id uuid references public.blackbook_master_contacts(id) on delete restrict,
  source_venue_id uuid references public.gt_venues(id) on delete restrict,
  source_type text not null default 'blackbook_contact' check (source_type in (
    'blackbook_contact','venue_intelligence','owner_submission','research'
  )),
  business_name text not null,
  city text not null,
  state text,
  category text,
  website_url text,
  instagram_handle text,
  public_email text,
  public_phone text,
  source_sheets text[] not null default '{}',
  data_quality_status text,
  ownership_evidence_status text not null default 'unreviewed' check (ownership_evidence_status in (
    'unreviewed','evidence_found','owner_confirmed','insufficient','not_black_owned'
  )),
  pipeline_stage text not null default 'candidate' check (pipeline_stage in (
    'candidate','research','outreach','claim_invited','claim_submitted',
    'verification','approved','published','rejected','do_not_contact'
  )),
  priority_score numeric not null default 0,
  assigned_researcher text,
  next_action_at timestamptz not null default now(),
  last_contact_at timestamptz,
  contact_attempts integer not null default 0,
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint black_pages_candidate_has_source check (
    source_contact_id is not null or source_venue_id is not null or source_type in ('owner_submission','research')
  )
);

create unique index if not exists black_pages_candidate_source_contact_uidx
  on public.black_pages_candidate_queue(source_contact_id)
  where source_contact_id is not null;
create unique index if not exists black_pages_candidate_source_venue_uidx
  on public.black_pages_candidate_queue(source_venue_id)
  where source_venue_id is not null;

create table if not exists public.black_pages_candidate_activity (
  id uuid primary key default gen_random_uuid(),
  candidate_id uuid not null references public.black_pages_candidate_queue(id) on delete cascade,
  activity_type text not null check (activity_type in (
    'research','email','sms','call','instagram_dm','claim_invite',
    'claim_submitted','verification_note','opt_out'
  )),
  outcome text,
  details jsonb not null default '{}'::jsonb,
  performed_by text,
  occurred_at timestamptz not null default now()
);

alter table public.black_pages_candidate_queue enable row level security;
alter table public.black_pages_candidate_activity enable row level security;
revoke all on public.black_pages_candidate_queue,public.black_pages_candidate_activity from anon,authenticated;

insert into public.black_pages_candidate_queue(
  source_contact_id,source_venue_id,source_type,business_name,city,state,category,
  website_url,instagram_handle,public_phone,source_sheets,data_quality_status,
  ownership_evidence_status,pipeline_stage,priority_score,next_action_at
)
select
  null,
  v.id,
  'venue_intelligence',
  v.name,
  initcap(replace(v.city_key,'_',' ')),
  case v.city_key
    when 'charlotte' then 'NC'
    when 'dallas' then 'TX'
    when 'houston' then 'TX'
    when 'las_vegas' then 'NV'
    when 'los_angeles' then 'CA'
    when 'miami' then 'FL'
    when 'new_york' then 'NY'
    when 'phoenix' then 'AZ'
    when 'scottsdale' then 'AZ'
    when 'washington_dc' then 'DC'
    else null
  end,
  coalesce(v.category_key,'business'),
  v.website,
  v.instagram_handle,
  v.phone,
  '{}'::text[],
  case
    when v.latitude is not null
     and v.longitude is not null
     and nullif(v.hero_image,'') is not null
     and (nullif(v.website,'') is not null or nullif(v.phone,'') is not null)
      then 'research_ready'
    else 'needs_enrichment'
  end,
  'unreviewed',
  'research',
  round((
    case when nullif(v.website,'') is not null then 15 else 0 end +
    case when nullif(v.instagram_handle,'') is not null then 15 else 0 end +
    case when nullif(v.phone,'') is not null then 10 else 0 end +
    case when nullif(v.hero_image,'') is not null then 10 else 0 end +
    case when v.latitude is not null and v.longitude is not null then 10 else 0 end +
    coalesce(v.google_rating,0)*5 +
    least(coalesce(v.google_reviews,0),250)::numeric/10
  )::numeric,2),
  now()+(
    row_number() over(
      order by coalesce(v.google_reviews,0) desc,coalesce(v.google_rating,0) desc
    )-1
  )*interval '5 minutes'
from public.gt_venues v
where v.status='active' and v.city_key<>'atlanta'
on conflict(source_venue_id) where source_venue_id is not null do update set
  business_name=excluded.business_name,
  city=excluded.city,
  state=excluded.state,
  category=excluded.category,
  website_url=excluded.website_url,
  instagram_handle=excluded.instagram_handle,
  public_phone=excluded.public_phone,
  data_quality_status=excluded.data_quality_status,
  priority_score=excluded.priority_score,
  updated_at=now();

create or replace view public.black_pages_candidate_city_summary
with (security_invoker=true)
as
select city,
       state,
       pipeline_stage,
       ownership_evidence_status,
       count(*)::integer as candidate_count,
       round(avg(priority_score),2) as average_priority,
       min(next_action_at) as next_action_at
from public.black_pages_candidate_queue
group by city,state,pipeline_stage,ownership_evidence_status;
revoke all on public.black_pages_candidate_city_summary from anon,authenticated;

create or replace view public.black_pages_expansion_readiness
with (security_invoker=true)
as
select t.city,
       t.state,
       t.target_published_businesses,
       t.target_owner_verified,
       t.weekly_research_target,
       t.weekly_claim_invite_target,
       t.launch_priority,
       count(distinct d.directory_id)::integer as published_businesses,
       count(distinct d.directory_id) filter (where d.owner_verified)::integer as owner_verified_businesses,
       count(distinct q.id) filter (
         where q.pipeline_stage not in ('published','rejected','do_not_contact')
       )::integer as candidate_pipeline,
       greatest(t.target_published_businesses-count(distinct d.directory_id),0)::integer as publishing_gap,
       greatest(
         t.target_owner_verified-count(distinct d.directory_id) filter (where d.owner_verified),0
       )::integer as verification_gap
from public.black_pages_city_targets t
left join public.black_pages_directory d
  on lower(d.city)=lower(t.city) and coalesce(d.state,'')=t.state
left join public.black_pages_candidate_queue q
  on lower(q.city)=lower(t.city) and coalesce(q.state,'')=t.state
where t.is_active
group by t.city,t.state,t.target_published_businesses,t.target_owner_verified,
  t.weekly_research_target,t.weekly_claim_invite_target,t.launch_priority;
revoke all on public.black_pages_expansion_readiness from anon,authenticated;

create index if not exists black_pages_candidate_next_action_idx
  on public.black_pages_candidate_queue(pipeline_stage,next_action_at,priority_score desc);
create index if not exists black_pages_candidate_city_idx
  on public.black_pages_candidate_queue(city,state,pipeline_stage);
create index if not exists black_pages_candidate_activity_idx
  on public.black_pages_candidate_activity(candidate_id,occurred_at desc);
