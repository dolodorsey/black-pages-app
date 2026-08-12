-- THE BLACK PAGES: source enrichment, city density, and coverage-gap operating system.
-- Keeps incomplete source data private while creating a repeatable path to publication.

alter table public.black_pages_candidate_queue
  add column if not exists subcategory text;

create table if not exists public.black_pages_source_enrichment_queue (
  id uuid primary key default gen_random_uuid(),
  source_type text not null default 'gt_venue',
  source_id uuid not null,
  business_name text not null,
  city text not null,
  state text,
  category_slug text,
  subcategory_slug text,
  website_url text,
  instagram_handle text,
  google_place_id text,
  issue_codes text[] not null default '{}'::text[],
  priority_score integer not null default 0,
  status text not null default 'pending' check (status in ('pending','processing','retry','manual','complete')),
  attempt_count integer not null default 0,
  locked_by text,
  locked_at timestamptz,
  next_action_at timestamptz not null default now(),
  result jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (source_type, source_id)
);

create index if not exists black_pages_source_enrichment_claim_idx
  on public.black_pages_source_enrichment_queue (status, next_action_at, priority_score desc);

alter table public.black_pages_source_enrichment_queue enable row level security;
revoke all on table public.black_pages_source_enrichment_queue from public, anon, authenticated;

-- Map legacy venue candidates into the new master subcategory whenever the directory already has one.
update public.black_pages_candidate_queue q
set subcategory = d.subcategory,
    updated_at = now()
from public.black_pages_directory_v2 d
where q.source_venue_id is not null
  and d.source_type = 'venue'
  and d.source_id = q.source_venue_id::text
  and nullif(d.subcategory, '') is not null
  and nullif(q.subcategory, '') is null;

-- Seed every Black-owned active source that is not currently eligible for customer display.
insert into public.black_pages_source_enrichment_queue (
  source_type, source_id, business_name, city, state, category_slug, subcategory_slug,
  website_url, instagram_handle, google_place_id, issue_codes, priority_score, status, next_action_at
)
select
  'gt_venue',
  v.id,
  v.name,
  coalesce(c.city_name, initcap(replace(v.city_key, '-', ' '))),
  c.state_code,
  public.black_pages_canonical_category(v.category_key),
  d.subcategory,
  nullif(btrim(v.website), ''),
  nullif(btrim(v.instagram_handle), ''),
  nullif(btrim(v.google_place_id), ''),
  array_remove(array[
    case when v.is_verified is not true then 'unverified_source' end,
    case when nullif(btrim(v.address), '') is null and (v.latitude is null or v.longitude is null) then 'missing_location' end,
    case when nullif(btrim(v.website), '') is null then 'missing_website' end,
    case when nullif(btrim(v.phone), '') is null and nullif(btrim(v.booking_link), '') is null and nullif(btrim(v.instagram_handle), '') is null then 'missing_contact' end
  ]::text[], null),
  1000
    + coalesce(ct.launch_priority, 0) * 100
    + case when nullif(btrim(v.address), '') is null and (v.latitude is null or v.longitude is null) then 500 else 0 end
    + case when v.is_verified is not true then 250 else 0 end,
  'pending',
  now()
from public.gt_venues v
left join public.gt_cities c on c.city_key = v.city_key
left join public.black_pages_city_targets ct
  on lower(ct.city) = lower(coalesce(c.city_name, initcap(replace(v.city_key, '-', ' '))))
 and coalesce(ct.state, '') = coalesce(c.state_code, '')
left join public.black_pages_directory_v2 d
  on d.source_type = 'venue' and d.source_id = v.id::text
where coalesce(v.is_black_owned, false) = true
  and v.status = 'active'
  and not (
    v.is_verified is true
    and v.hero_image is not null
    and (nullif(btrim(v.address), '') is not null or (v.latitude is not null and v.longitude is not null))
    and (
      nullif(btrim(v.website), '') is not null
      or nullif(btrim(v.phone), '') is not null
      or nullif(btrim(v.booking_link), '') is not null
      or nullif(btrim(v.instagram_handle), '') is not null
    )
  )
on conflict (source_type, source_id) do update set
  business_name = excluded.business_name,
  city = excluded.city,
  state = excluded.state,
  category_slug = excluded.category_slug,
  subcategory_slug = excluded.subcategory_slug,
  website_url = excluded.website_url,
  instagram_handle = excluded.instagram_handle,
  google_place_id = excluded.google_place_id,
  issue_codes = excluded.issue_codes,
  priority_score = greatest(public.black_pages_source_enrichment_queue.priority_score, excluded.priority_score),
  status = case when public.black_pages_source_enrichment_queue.status = 'complete' then 'complete' else 'pending' end,
  next_action_at = case when public.black_pages_source_enrichment_queue.status = 'complete' then public.black_pages_source_enrichment_queue.next_action_at else now() end,
  updated_at = now();

create table if not exists public.black_pages_research_gap_tasks (
  id uuid primary key default gen_random_uuid(),
  city text not null,
  state text not null,
  category_slug text not null,
  subcategory_slug text not null,
  category_name text not null,
  subcategory_name text not null,
  target_count integer not null default 0,
  published_count integer not null default 0,
  candidate_count integer not null default 0,
  gap_count integer not null default 0,
  priority_score integer not null default 0,
  query_text text not null,
  status text not null default 'pending' check (status in ('pending','active','complete','paused')),
  last_refreshed_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (city, state, category_slug, subcategory_slug)
);

create index if not exists black_pages_research_gap_priority_idx
  on public.black_pages_research_gap_tasks (status, priority_score desc, gap_count desc);

alter table public.black_pages_research_gap_tasks enable row level security;
revoke all on table public.black_pages_research_gap_tasks from public, anon, authenticated;

create or replace view public.black_pages_coverage_matrix as
with target_cells as (
  select
    t.city,
    t.state,
    t.launch_priority,
    c.slug as category_slug,
    c.name as category_name,
    s.slug as subcategory_slug,
    s.name as subcategory_name,
    greatest(coalesce(s.target_per_city, 1), 1)::integer as target_count
  from public.black_pages_city_targets t
  cross join public.black_pages_categories c
  join public.black_pages_subcategories s on s.category_slug = c.slug
  where t.is_active and c.active and s.active
), eligible_directory as (
  select d.*
  from public.black_pages_directory_v2 d
  where d.source_type = 'listing'
     or (
       d.source_type = 'venue'
       and exists (
         select 1
         from public.gt_venues v
         where v.id::text = d.source_id
           and coalesce(v.is_black_owned, false) = true
           and v.status = 'active'
           and v.is_verified is true
           and v.hero_image is not null
           and (nullif(btrim(v.address), '') is not null or (v.latitude is not null and v.longitude is not null))
           and (
             nullif(btrim(v.website), '') is not null
             or nullif(btrim(v.phone), '') is not null
             or nullif(btrim(v.booking_link), '') is not null
             or nullif(btrim(v.instagram_handle), '') is not null
           )
       )
     )
), published as (
  select
    lower(city) as city_key,
    coalesce(state, '') as state,
    category as category_slug,
    subcategory as subcategory_slug,
    count(*)::integer as published_count
  from eligible_directory
  where nullif(subcategory, '') is not null
  group by 1,2,3,4
), candidates as (
  select
    lower(city) as city_key,
    coalesce(state, '') as state,
    public.black_pages_canonical_category(category) as category_slug,
    subcategory as subcategory_slug,
    count(*) filter (where pipeline_stage not in ('published','rejected','do_not_contact'))::integer as candidate_count
  from public.black_pages_candidate_queue
  where nullif(subcategory, '') is not null
  group by 1,2,3,4
)
select
  tc.city,
  tc.state,
  tc.launch_priority,
  tc.category_slug,
  tc.category_name,
  tc.subcategory_slug,
  tc.subcategory_name,
  tc.target_count,
  coalesce(p.published_count, 0)::integer as published_count,
  coalesce(q.candidate_count, 0)::integer as candidate_count,
  greatest(tc.target_count - coalesce(p.published_count, 0), 0)::integer as gap_count,
  greatest(tc.target_count - coalesce(p.published_count, 0) - coalesce(q.candidate_count, 0), 0)::integer as discovery_gap,
  case
    when coalesce(p.published_count, 0) >= tc.target_count then 'target_met'
    when coalesce(p.published_count, 0) = 0 then 'empty'
    when coalesce(p.published_count, 0)::numeric / tc.target_count < 0.35 then 'critical'
    when coalesce(p.published_count, 0)::numeric / tc.target_count < 0.70 then 'weak'
    else 'building'
  end as coverage_status,
  round(100.0 * coalesce(p.published_count, 0) / nullif(tc.target_count, 0), 1) as coverage_pct,
  (
    tc.launch_priority * 1000
    + greatest(tc.target_count - coalesce(p.published_count, 0), 0) * 100
    + greatest(tc.target_count - coalesce(p.published_count, 0) - coalesce(q.candidate_count, 0), 0) * 50
    + case when coalesce(p.published_count, 0) = 0 then 500 else 0 end
  )::integer as priority_score
from target_cells tc
left join published p
  on p.city_key = lower(tc.city)
 and p.state = tc.state
 and p.category_slug = tc.category_slug
 and p.subcategory_slug = tc.subcategory_slug
left join candidates q
  on q.city_key = lower(tc.city)
 and q.state = tc.state
 and q.category_slug = tc.category_slug
 and q.subcategory_slug = tc.subcategory_slug;

revoke all on table public.black_pages_coverage_matrix from public, anon, authenticated;

create or replace view public.black_pages_coverage_city_summary as
select
  city,
  state,
  max(launch_priority)::integer as launch_priority,
  count(*)::integer as taxonomy_cells,
  count(*) filter (where coverage_status = 'target_met')::integer as target_met_cells,
  count(*) filter (where coverage_status = 'empty')::integer as empty_cells,
  count(*) filter (where coverage_status in ('critical','weak'))::integer as weak_cells,
  sum(target_count)::integer as target_business_slots,
  sum(published_count)::integer as published_business_slots,
  sum(candidate_count)::integer as candidate_slots,
  sum(gap_count)::integer as remaining_gap,
  round(avg(least(coverage_pct, 100)), 1) as average_coverage_pct
from public.black_pages_coverage_matrix
group by city, state;

revoke all on table public.black_pages_coverage_city_summary from public, anon, authenticated;

create or replace function public.black_pages_refresh_gap_tasks()
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  v_upserted integer := 0;
  v_completed integer := 0;
  v_reprioritized integer := 0;
begin
  insert into public.black_pages_research_gap_tasks (
    city, state, category_slug, subcategory_slug, category_name, subcategory_name,
    target_count, published_count, candidate_count, gap_count, priority_score,
    query_text, status, last_refreshed_at, updated_at
  )
  select
    city, state, category_slug, subcategory_slug, category_name, subcategory_name,
    target_count, published_count, candidate_count, gap_count, priority_score,
    format('Find and verify Black-owned %s businesses in %s, %s', subcategory_name, city, state),
    case when gap_count > 0 then 'pending' else 'complete' end,
    now(), now()
  from public.black_pages_coverage_matrix
  on conflict (city, state, category_slug, subcategory_slug) do update set
    category_name = excluded.category_name,
    subcategory_name = excluded.subcategory_name,
    target_count = excluded.target_count,
    published_count = excluded.published_count,
    candidate_count = excluded.candidate_count,
    gap_count = excluded.gap_count,
    priority_score = excluded.priority_score,
    query_text = excluded.query_text,
    status = case
      when excluded.gap_count = 0 then 'complete'
      when public.black_pages_research_gap_tasks.status = 'paused' then 'paused'
      else 'pending'
    end,
    last_refreshed_at = now(),
    updated_at = now();
  get diagnostics v_upserted = row_count;

  update public.black_pages_research_gap_tasks
  set status = 'complete', updated_at = now(), last_refreshed_at = now()
  where gap_count = 0 and status <> 'complete';
  get diagnostics v_completed = row_count;

  -- Route existing candidates toward the cities/categories with the largest actual publishing gaps.
  with category_pressure as (
    select city, state, category_slug,
      max(priority_score)::integer as pressure,
      sum(gap_count)::integer as total_gap
    from public.black_pages_coverage_matrix
    where gap_count > 0
    group by city, state, category_slug
  )
  update public.black_pages_candidate_queue q
  set priority_score = greatest(
        coalesce(q.priority_score, 0),
        least(9999, 1000 + cp.pressure / 10 + least(cp.total_gap, 250))
      ),
      next_action_at = case
        when q.pipeline_stage = 'research' then least(coalesce(q.next_action_at, now()), now())
        else q.next_action_at
      end,
      updated_at = now()
  from category_pressure cp
  where lower(q.city) = lower(cp.city)
    and coalesce(q.state, '') = cp.state
    and public.black_pages_canonical_category(q.category) = cp.category_slug
    and q.pipeline_stage = 'research';
  get diagnostics v_reprioritized = row_count;

  return jsonb_build_object(
    'gap_tasks_refreshed', v_upserted,
    'tasks_completed', v_completed,
    'candidates_reprioritized', v_reprioritized,
    'refreshed_at', now()
  );
end;
$$;

revoke all on function public.black_pages_refresh_gap_tasks() from public, anon, authenticated;

create or replace function public.black_pages_claim_source_enrichment_batch(
  p_limit integer default 10,
  p_worker text default 'black-pages-enrichment-worker'
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  v_rows jsonb;
begin
  with claimed as (
    select id
    from public.black_pages_source_enrichment_queue
    where status in ('pending','retry')
      and next_action_at <= now()
      and attempt_count < 5
    order by priority_score desc, next_action_at, created_at
    for update skip locked
    limit least(25, greatest(1, coalesce(p_limit, 10)))
  ), updated as (
    update public.black_pages_source_enrichment_queue q
    set status = 'processing',
        locked_by = p_worker,
        locked_at = now(),
        attempt_count = attempt_count + 1,
        updated_at = now()
    from claimed c
    where q.id = c.id
    returning q.*
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', id,
    'source_id', source_id,
    'business_name', business_name,
    'city', city,
    'state', state,
    'category_slug', category_slug,
    'subcategory_slug', subcategory_slug,
    'website_url', website_url,
    'instagram_handle', instagram_handle,
    'google_place_id', google_place_id,
    'issue_codes', issue_codes,
    'attempt_count', attempt_count
  ) order by priority_score desc), '[]'::jsonb)
  into v_rows
  from updated;

  return jsonb_build_object('candidates', v_rows);
end;
$$;

revoke all on function public.black_pages_claim_source_enrichment_batch(integer, text) from public, anon, authenticated;

create or replace function public.black_pages_complete_source_enrichment(
  p_queue_id uuid,
  p_result jsonb,
  p_worker text default 'black-pages-enrichment-worker'
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  v_source_id uuid;
  v_attempts integer;
  v_address text;
  v_lat numeric;
  v_lng numeric;
  v_postal text;
  v_confidence text;
  v_has_location boolean := false;
  v_status text;
begin
  select source_id, attempt_count into v_source_id, v_attempts
  from public.black_pages_source_enrichment_queue
  where id = p_queue_id and locked_by = p_worker
  for update;

  if v_source_id is null then
    raise exception 'Enrichment queue item is not claimed by this worker';
  end if;

  v_address := nullif(btrim(p_result->>'address'), '');
  v_postal := nullif(btrim(p_result->>'postal_code'), '');
  v_confidence := coalesce(nullif(p_result->>'confidence', ''), 'none');
  begin v_lat := nullif(p_result->>'latitude', '')::numeric; exception when others then v_lat := null; end;
  begin v_lng := nullif(p_result->>'longitude', '')::numeric; exception when others then v_lng := null; end;

  if v_confidence = 'high' and (v_address is not null or (v_lat is not null and v_lng is not null)) then
    update public.gt_venues
    set address = coalesce(nullif(btrim(address), ''), v_address),
        latitude = coalesce(latitude, v_lat),
        longitude = coalesce(longitude, v_lng),
        enrichment_status = 'location_enriched',
        enrichment_source = coalesce(nullif(p_result->>'source', ''), 'black_pages_enrichment_worker'),
        enriched_at = now(),
        metadata = coalesce(metadata, '{}'::jsonb) || jsonb_strip_nulls(jsonb_build_object(
          'black_pages_location_source_url', nullif(p_result->>'source_url', ''),
          'black_pages_postal_code', v_postal,
          'black_pages_location_confidence', v_confidence
        )),
        updated_at = now()
    where id = v_source_id;
  end if;

  select (nullif(btrim(address), '') is not null or (latitude is not null and longitude is not null))
  into v_has_location
  from public.gt_venues where id = v_source_id;

  v_status := case
    when v_has_location then 'complete'
    when v_attempts >= 3 then 'manual'
    else 'retry'
  end;

  update public.black_pages_source_enrichment_queue
  set status = v_status,
      result = p_result,
      locked_by = null,
      locked_at = null,
      next_action_at = case when v_status = 'retry' then now() + interval '12 hours' else next_action_at end,
      updated_at = now()
  where id = p_queue_id;

  return jsonb_build_object('ok', true, 'status', v_status, 'location_ready', v_has_location, 'source_id', v_source_id);
end;
$$;

revoke all on function public.black_pages_complete_source_enrichment(uuid, jsonb, text) from public, anon, authenticated;

create or replace function public.black_pages_staff_coverage_snapshot(
  p_city text default null,
  p_limit integer default 1000
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, auth
as $$
declare
  v_role text := coalesce(auth.jwt()->'app_metadata'->>'khg_role', '');
  v_cities jsonb;
  v_cells jsonb;
  v_enrichment jsonb;
  v_gap_stats jsonb;
begin
  if coalesce(auth.role(), '') <> 'service_role' and v_role not in ('owner','admin','editor') then
    raise exception 'Staff access required';
  end if;

  select coalesce(jsonb_agg(to_jsonb(x) order by x.launch_priority desc, x.city), '[]'::jsonb)
  into v_cities
  from public.black_pages_coverage_city_summary x;

  select coalesce(jsonb_agg(to_jsonb(x) order by x.priority_score desc, x.category_name, x.subcategory_name), '[]'::jsonb)
  into v_cells
  from (
    select *
    from public.black_pages_coverage_matrix
    where p_city is null or lower(city) = lower(p_city)
    order by priority_score desc, category_name, subcategory_name
    limit least(5000, greatest(1, coalesce(p_limit, 1000)))
  ) x;

  select jsonb_build_object(
    'total', count(*),
    'pending', count(*) filter (where status in ('pending','retry')),
    'processing', count(*) filter (where status = 'processing'),
    'manual', count(*) filter (where status = 'manual'),
    'complete', count(*) filter (where status = 'complete'),
    'missing_location', count(*) filter (where 'missing_location' = any(issue_codes))
  ) into v_enrichment
  from public.black_pages_source_enrichment_queue;

  select jsonb_build_object(
    'total_gap_tasks', count(*),
    'open_gap_tasks', count(*) filter (where status in ('pending','active')),
    'empty_subcategory_tasks', count(*) filter (where published_count = 0 and gap_count > 0),
    'discovery_gap', coalesce(sum(greatest(gap_count - candidate_count, 0)) filter (where status in ('pending','active')), 0)
  ) into v_gap_stats
  from public.black_pages_research_gap_tasks;

  return jsonb_build_object(
    'cities', v_cities,
    'cells', v_cells,
    'enrichment', v_enrichment,
    'gap_tasks', v_gap_stats,
    'generated_at', now()
  );
end;
$$;

revoke all on function public.black_pages_staff_coverage_snapshot(text, integer) from public, anon;
grant execute on function public.black_pages_staff_coverage_snapshot(text, integer) to authenticated;

create or replace function public.black_pages_dispatch_enrichment_worker(p_limit integer default 25)
returns bigint
language plpgsql
security definer
set search_path = pg_catalog, public, net, vault
as $$
declare
  v_token text;
  v_request_id bigint;
begin
  select decrypted_secret into v_token
  from vault.decrypted_secrets
  where name = 'black_pages_research_worker_token'
  order by created_at desc
  limit 1;

  if nullif(v_token, '') is null then
    raise exception 'BLACK PAGES worker token missing';
  end if;

  select net.http_post(
    url := 'https://dzlmtvodpyhetvektfuo.supabase.co/functions/v1/black-pages-enrichment-worker',
    headers := jsonb_build_object('Content-Type','application/json','x-worker-token',v_token),
    body := jsonb_build_object('limit', least(25, greatest(1, coalesce(p_limit, 25))))
  ) into v_request_id;

  return v_request_id;
end;
$$;

revoke all on function public.black_pages_dispatch_enrichment_worker(integer) from public, anon, authenticated;

-- Rebuild gaps immediately so the existing research worker is reprioritized now.
select public.black_pages_refresh_gap_tasks();

-- Keep coverage tasks current and continuously work the source-enrichment backlog.
do $$
begin
  perform cron.unschedule('black-pages-gap-refresh');
exception when others then null;
end $$;
select cron.schedule('black-pages-gap-refresh', '7 * * * *', 'select public.black_pages_refresh_gap_tasks();');

do $$
begin
  perform cron.unschedule('black-pages-enrichment-worker');
exception when others then null;
end $$;
select cron.schedule('black-pages-enrichment-worker', '*/10 * * * *', 'select public.black_pages_dispatch_enrichment_worker(25);');
