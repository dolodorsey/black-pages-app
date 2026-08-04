-- Full digital directory foundation for THE BLACK PAGES.
-- The live directory combines approved owner-submitted listings with the
-- enterprise's active Black-owned business intelligence records.

create table if not exists public.black_pages_claims (
  id uuid primary key default gen_random_uuid(),
  directory_id text not null,
  claimant_auth_id uuid not null default auth.uid(),
  claimant_name text not null,
  claimant_email text not null,
  claimant_phone text,
  role_at_business text,
  proof_urls text[] not null default '{}',
  notes text,
  status text not null default 'pending' check (status in ('pending','under_review','approved','rejected')),
  reviewed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(directory_id, claimant_auth_id)
);

create table if not exists public.black_pages_favorites (
  user_auth_id uuid not null default auth.uid(),
  directory_id text not null,
  created_at timestamptz not null default now(),
  primary key(user_auth_id, directory_id)
);

create table if not exists public.black_pages_reviews (
  id uuid primary key default gen_random_uuid(),
  directory_id text not null,
  reviewer_auth_id uuid not null default auth.uid(),
  rating integer not null check (rating between 1 and 5),
  review_text text,
  status text not null default 'pending' check (status in ('pending','approved','rejected')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(directory_id, reviewer_auth_id)
);

create table if not exists public.black_pages_deals (
  id uuid primary key default gen_random_uuid(),
  directory_id text not null,
  title text not null,
  description text,
  redemption_code text,
  starts_at timestamptz,
  ends_at timestamptz,
  status text not null default 'draft' check (status in ('draft','active','paused','expired')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.black_pages_claims enable row level security;
alter table public.black_pages_favorites enable row level security;
alter table public.black_pages_reviews enable row level security;
alter table public.black_pages_deals enable row level security;

drop policy if exists black_pages_claims_own_select on public.black_pages_claims;
create policy black_pages_claims_own_select on public.black_pages_claims for select to authenticated using (claimant_auth_id = auth.uid());
drop policy if exists black_pages_claims_own_insert on public.black_pages_claims;
create policy black_pages_claims_own_insert on public.black_pages_claims for insert to authenticated with check (claimant_auth_id = auth.uid());
drop policy if exists black_pages_claims_own_update on public.black_pages_claims;
create policy black_pages_claims_own_update on public.black_pages_claims for update to authenticated using (claimant_auth_id = auth.uid() and status = 'pending') with check (claimant_auth_id = auth.uid());

drop policy if exists black_pages_favorites_own_all on public.black_pages_favorites;
create policy black_pages_favorites_own_all on public.black_pages_favorites for all to authenticated using (user_auth_id = auth.uid()) with check (user_auth_id = auth.uid());

drop policy if exists black_pages_reviews_public_select on public.black_pages_reviews;
create policy black_pages_reviews_public_select on public.black_pages_reviews for select to anon, authenticated using (status = 'approved' or reviewer_auth_id = auth.uid());
drop policy if exists black_pages_reviews_own_insert on public.black_pages_reviews;
create policy black_pages_reviews_own_insert on public.black_pages_reviews for insert to authenticated with check (reviewer_auth_id = auth.uid());
drop policy if exists black_pages_reviews_own_update on public.black_pages_reviews;
create policy black_pages_reviews_own_update on public.black_pages_reviews for update to authenticated using (reviewer_auth_id = auth.uid() and status = 'pending') with check (reviewer_auth_id = auth.uid());

drop policy if exists black_pages_deals_public_select on public.black_pages_deals;
create policy black_pages_deals_public_select on public.black_pages_deals for select to anon, authenticated using (status = 'active' and (starts_at is null or starts_at <= now()) and (ends_at is null or ends_at >= now()));

create or replace view public.black_pages_directory
with (security_invoker = true)
as
select
  'venue:' || v.id::text as directory_id,
  'venue'::text as source_type,
  v.id as source_id,
  v.name as business_name,
  lower(regexp_replace(v.name, '[^a-zA-Z0-9]+', '-', 'g')) as slug,
  coalesce(v.category_key, 'business') as category,
  v.subcategory,
  initcap(replace(v.city_key, '_', ' ')) as city,
  'GA'::text as state,
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
  'enterprise_sourced'::text as ownership_status,
  false as owner_verified,
  array_remove(coalesce(v.culture_tags,'{}'::text[]) || coalesce(v.vibe_tags,'{}'::text[]), null) as tags
from public.gt_venues v
where v.status = 'active' and coalesce(v.is_black_owned,false) = true
union all
select
  'listing:' || l.id::text,
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
  case when l.verified_at is not null then 'owner_verified' else 'approved' end,
  l.verified_at is not null,
  '{}'::text[]
from public.black_pages_listings l
where l.status = 'approved';

grant select on public.black_pages_directory to anon, authenticated;
grant select on public.black_pages_deals to anon, authenticated;
grant select, insert, update on public.black_pages_claims to authenticated;
grant select, insert, delete on public.black_pages_favorites to authenticated;
grant select, insert, update on public.black_pages_reviews to authenticated;

create index if not exists black_pages_claims_directory_idx on public.black_pages_claims(directory_id);
create index if not exists black_pages_reviews_directory_idx on public.black_pages_reviews(directory_id, status);
create index if not exists black_pages_deals_directory_idx on public.black_pages_deals(directory_id, status);
