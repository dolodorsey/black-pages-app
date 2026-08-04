-- BLACK PAGES systematic owner verification.
-- Enterprise-sourced businesses stay clearly labeled until an owner claim passes
-- independent identity, authority, and ownership-evidence checks.

create table if not exists public.black_pages_claim_verification_checks (
  claim_id uuid not null references public.black_pages_claims(id) on delete cascade,
  check_type text not null check (check_type in (
    'identity','business_authority','domain_email','business_phone',
    'registration','social_control','ownership_evidence'
  )),
  required boolean not null default true,
  status text not null default 'pending' check (status in (
    'pending','submitted','under_review','passed','failed','waived','expired'
  )),
  evidence_urls text[] not null default '{}',
  reviewed_by text,
  reviewed_at timestamptz,
  expires_at timestamptz,
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key(claim_id,check_type)
);

create table if not exists public.black_pages_owner_verification_public (
  directory_id text primary key,
  claim_id uuid unique references public.black_pages_claims(id) on delete set null,
  verification_method text not null,
  verified_at timestamptz not null default now(),
  expires_at timestamptz,
  status text not null default 'verified' check (status in ('verified','expired','revoked')),
  updated_at timestamptz not null default now()
);

create table if not exists public.black_pages_city_targets (
  city text not null,
  state text not null,
  target_published_businesses integer not null default 100 check (target_published_businesses>=1),
  target_owner_verified integer not null default 25 check (target_owner_verified>=0),
  weekly_research_target integer not null default 25 check (weekly_research_target>=0),
  weekly_claim_invite_target integer not null default 10 check (weekly_claim_invite_target>=0),
  launch_priority smallint not null default 5 check (launch_priority between 1 and 10),
  is_active boolean not null default true,
  updated_at timestamptz not null default now(),
  primary key(city,state)
);

alter table public.black_pages_claim_verification_checks enable row level security;
alter table public.black_pages_owner_verification_public enable row level security;
alter table public.black_pages_city_targets enable row level security;
revoke all on public.black_pages_claim_verification_checks,public.black_pages_city_targets from anon,authenticated;

drop policy if exists black_pages_owner_verification_public_read on public.black_pages_owner_verification_public;
create policy black_pages_owner_verification_public_read
on public.black_pages_owner_verification_public
for select to anon,authenticated
using (status='verified' and (expires_at is null or expires_at>now()));
grant select on public.black_pages_owner_verification_public to anon,authenticated;

create or replace function public.black_pages_initialize_claim_verification()
returns trigger
language plpgsql
security definer
set search_path='pg_catalog','public'
as $$
begin
  insert into public.black_pages_claim_verification_checks(claim_id,check_type,required)
  values
    (new.id,'identity',true),
    (new.id,'business_authority',true),
    (new.id,'ownership_evidence',true),
    (new.id,'domain_email',false),
    (new.id,'business_phone',false),
    (new.id,'registration',false),
    (new.id,'social_control',false)
  on conflict(claim_id,check_type) do nothing;
  return new;
end;$$;

revoke all on function public.black_pages_initialize_claim_verification() from public;

drop trigger if exists black_pages_claim_verification_init on public.black_pages_claims;
create trigger black_pages_claim_verification_init
after insert on public.black_pages_claims
for each row execute function public.black_pages_initialize_claim_verification();

insert into public.black_pages_claim_verification_checks(claim_id,check_type,required)
select c.id,x.check_type,
       case when x.check_type in ('identity','business_authority','ownership_evidence') then true else false end
from public.black_pages_claims c
cross join (values
  ('identity'),('business_authority'),('domain_email'),('business_phone'),
  ('registration'),('social_control'),('ownership_evidence')
) x(check_type)
on conflict(claim_id,check_type) do nothing;

insert into public.black_pages_city_targets(
  city,state,target_published_businesses,target_owner_verified,
  weekly_research_target,weekly_claim_invite_target,launch_priority
)
values
  ('Atlanta','GA',500,150,50,25,10),
  ('Houston','TX',250,75,40,20,9),
  ('Dallas','TX',200,60,35,18,8),
  ('Miami','FL',200,60,35,18,8),
  ('Charlotte','NC',150,45,25,12,7),
  ('Washington','DC',200,60,30,15,8),
  ('New York','NY',300,90,45,22,9),
  ('Los Angeles','CA',300,90,45,22,9),
  ('Phoenix','AZ',125,35,20,10,6),
  ('Las Vegas','NV',125,35,20,10,6),
  ('Memphis','TN',175,50,30,15,8)
on conflict(city,state) do update set
  target_published_businesses=excluded.target_published_businesses,
  target_owner_verified=excluded.target_owner_verified,
  weekly_research_target=excluded.weekly_research_target,
  weekly_claim_invite_target=excluded.weekly_claim_invite_target,
  launch_priority=excluded.launch_priority,
  is_active=true,
  updated_at=now();

create or replace function public.black_pages_approve_owner_claim(
  p_claim_id uuid,
  p_verification_method text default 'manual_evidence_review'
)
returns text
language plpgsql
security definer
set search_path='pg_catalog','public'
as $$
declare v_claim public.black_pages_claims%rowtype;
begin
  if auth.role()<>'service_role' then
    raise exception 'Service role required' using errcode='42501';
  end if;

  select * into v_claim
  from public.black_pages_claims
  where id=p_claim_id
  for update;

  if not found then raise exception 'Claim not found'; end if;

  if exists(
    select 1 from public.black_pages_claim_verification_checks
    where claim_id=p_claim_id and required and status<>'passed'
  ) then
    raise exception 'All required owner verification checks must pass';
  end if;

  if (
    select count(*) from public.black_pages_claim_verification_checks
    where claim_id=p_claim_id and status='passed'
  )<4 then
    raise exception 'At least four independent checks must pass';
  end if;

  insert into public.black_pages_owner_verification_public(
    directory_id,claim_id,verification_method,verified_at,status,updated_at
  ) values (
    v_claim.directory_id,v_claim.id,
    left(coalesce(nullif(p_verification_method,''),'manual_evidence_review'),100),
    now(),'verified',now()
  )
  on conflict(directory_id) do update set
    claim_id=excluded.claim_id,
    verification_method=excluded.verification_method,
    verified_at=now(),
    status='verified',
    updated_at=now();

  update public.black_pages_claims
  set status='approved',reviewed_at=now(),updated_at=now()
  where id=p_claim_id;

  if v_claim.directory_id like 'listing:%' then
    update public.black_pages_listings
    set verified_at=now(),updated_at=now()
    where id::text=substring(v_claim.directory_id from 9);
  end if;

  return v_claim.directory_id;
end;$$;

revoke all on function public.black_pages_approve_owner_claim(uuid,text) from public;
grant execute on function public.black_pages_approve_owner_claim(uuid,text) to service_role;

create or replace view public.black_pages_directory
with (security_invoker=true)
as
select
  'venue:'||v.id::text as directory_id,
  'venue'::text as source_type,
  v.id as source_id,
  v.name as business_name,
  lower(regexp_replace(v.name,'[^a-zA-Z0-9]+','-','g')) as slug,
  coalesce(v.category_key,'business') as category,
  v.subcategory,
  initcap(replace(v.city_key,'_',' ')) as city,
  case v.city_key
    when 'atlanta' then 'GA'
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
  end::text as state,
  v.neighborhood,
  v.address,
  v.short_desc as short_description,
  v.website as website_url,
  v.instagram_handle,
  v.phone,
  v.hero_image as image_url,
  v.latitude::double precision as latitude,
  v.longitude::double precision as longitude,
  v.google_rating::double precision as rating,
  v.google_reviews as review_count,
  v.price_range,
  coalesce(v.is_khg,false) as featured,
  case when ov.directory_id is not null then 'owner_verified' else 'enterprise_sourced' end::text as ownership_status,
  ov.directory_id is not null as owner_verified,
  array_remove(coalesce(v.culture_tags,'{}'::text[])||coalesce(v.vibe_tags,'{}'::text[]),null) as tags
from public.gt_venues v
left join public.black_pages_owner_verification_public ov
  on ov.directory_id='venue:'||v.id::text
 and ov.status='verified'
 and (ov.expires_at is null or ov.expires_at>now())
where v.status='active' and coalesce(v.is_black_owned,false)=true

union all

select
  'listing:'||l.id::text,
  'listing'::text,
  l.id,
  l.business_name,
  l.slug,
  l.category,
  null::text,
  l.city,
  l.state,
  null::text,
  null::text,
  l.short_description,
  l.website_url,
  l.instagram_handle,
  null::text,
  l.logo_url,
  null::double precision,
  null::double precision,
  null::double precision,
  null::integer,
  null::text,
  l.featured,
  case when ov.directory_id is not null or l.verified_at is not null then 'owner_verified' else 'approved' end,
  (ov.directory_id is not null or l.verified_at is not null),
  '{}'::text[]
from public.black_pages_listings l
left join public.black_pages_owner_verification_public ov
  on ov.directory_id='listing:'||l.id::text
 and ov.status='verified'
 and (ov.expires_at is null or ov.expires_at>now())
where l.status='approved';

grant select on public.black_pages_directory to anon,authenticated;

create index if not exists black_pages_claim_checks_status_idx
  on public.black_pages_claim_verification_checks(status,check_type);
