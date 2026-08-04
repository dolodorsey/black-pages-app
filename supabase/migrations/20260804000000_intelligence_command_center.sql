-- Shared intelligence command center for GOOD TIMES and BLACK PAGES.
create extension if not exists pgcrypto;

create table public.intel_categories (
  id uuid primary key default gen_random_uuid(),
  brand text not null check (brand in ('good_times','black_pages','shared')),
  slug text not null, name text not null, description text,
  active boolean not null default true, created_at timestamptz not null default now(),
  unique (brand, slug)
);
create table public.intel_subcategories (
  id uuid primary key default gen_random_uuid(), category_id uuid not null references public.intel_categories(id) on delete cascade,
  slug text not null, name text not null, target_per_city integer not null default 10 check (target_per_city >= 0),
  active boolean not null default true, created_at timestamptz not null default now(), unique(category_id,slug)
);
create table public.intel_sources (
  id uuid primary key default gen_random_uuid(), brand text not null check (brand in ('good_times','black_pages','shared')),
  city_id text references public.cities(id) on delete set null, category_id uuid references public.intel_categories(id) on delete set null,
  name text not null, source_type text not null, url text, trust_score smallint not null default 50 check(trust_score between 0 and 100),
  active boolean not null default true, last_checked_at timestamptz, created_at timestamptz not null default now(), unique(brand,name,city_id)
);
create table public.intel_tasks (
  id uuid primary key default gen_random_uuid(), brand text not null check (brand in ('good_times','black_pages','shared')),
  agent_key text not null, task_type text not null, city_id text references public.cities(id) on delete set null,
  category_id uuid references public.intel_categories(id) on delete set null, subcategory_id uuid references public.intel_subcategories(id) on delete set null,
  status text not null default 'queued' check(status in ('queued','claimed','in_progress','review','completed','failed','cancelled')),
  priority smallint not null default 50 check(priority between 0 and 100), payload jsonb not null default '{}', result jsonb not null default '{}',
  available_at timestamptz not null default now(), claimed_at timestamptz, completed_at timestamptz, attempts integer not null default 0,
  max_attempts integer not null default 3, created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create index intel_tasks_ready_idx on public.intel_tasks(status,priority desc,available_at) where status='queued';

create table public.gt_city_coverage_matrix (
  city_id text not null references public.cities(id) on delete cascade, subcategory_id uuid not null references public.intel_subcategories(id) on delete cascade,
  target_count integer not null default 10, discovered_count integer not null default 0, verified_count integer not null default 0,
  fresh_count integer not null default 0, coverage_pct numeric(5,2) generated always as (least(100,case when target_count=0 then 100 else verified_count*100.0/target_count end)) stored,
  last_scanned_at timestamptz, updated_at timestamptz not null default now(), primary key(city_id,subcategory_id)
);
create table public.gt_category_gap_queue (
  id uuid primary key default gen_random_uuid(), city_id text not null references public.cities(id) on delete cascade,
  subcategory_id uuid not null references public.intel_subcategories(id) on delete cascade, gap_count integer not null check(gap_count>=0),
  priority smallint not null default 50, status text not null default 'queued' check(status in ('queued','in_progress','resolved','dismissed')),
  intel_task_id uuid references public.intel_tasks(id) on delete set null, created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  unique(city_id,subcategory_id,status)
);

create table public.bp_city_expansion_matrix (
  city_id text primary key references public.cities(id) on delete cascade, target_businesses integer not null,
  discovered_businesses integer not null default 0, verified_businesses integer not null default 0,
  claimed_businesses integer not null default 0, launch_priority smallint not null default 50, status text not null default 'research', updated_at timestamptz not null default now()
);
create table public.bp_business_candidates (
  id uuid primary key default gen_random_uuid(), city_id text not null references public.cities(id) on delete cascade,
  category_id uuid not null references public.intel_categories(id), subcategory_id uuid references public.intel_subcategories(id),
  business_name text not null, website text, source_id uuid references public.intel_sources(id), owner_name text, owner_contact jsonb not null default '{}',
  cultural_relevance_score smallint check(cultural_relevance_score between 0 and 100), verification_status text not null default 'unverified'
    check(verification_status in ('unverified','researching','verified','rejected','stale')),
  evidence jsonb not null default '[]', last_verified_at timestamptz, created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  unique(city_id,business_name)
);
create table public.bp_verification_pipeline (
  id uuid primary key default gen_random_uuid(), candidate_id uuid not null references public.bp_business_candidates(id) on delete cascade,
  stage text not null check(stage in ('identity','ownership','operations','cultural_relevance','editorial_review')),
  status text not null default 'queued' check(status in ('queued','in_progress','passed','failed','needs_review')),
  assigned_agent_key text, evidence jsonb not null default '[]', confidence numeric(4,3) check(confidence between 0 and 1),
  intel_task_id uuid references public.intel_tasks(id) on delete set null, created_at timestamptz not null default now(), completed_at timestamptz,
  unique(candidate_id,stage)
);
create table public.bp_owner_claim_tasks (
  id uuid primary key default gen_random_uuid(), candidate_id uuid not null references public.bp_business_candidates(id) on delete cascade,
  status text not null default 'queued' check(status in ('queued','contacted','responded','claimed','declined','closed')),
  channel text, contact_attempts integer not null default 0, next_action_at timestamptz, created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);

alter table public.intel_categories enable row level security; alter table public.intel_subcategories enable row level security;
alter table public.intel_sources enable row level security; alter table public.intel_tasks enable row level security;
alter table public.gt_city_coverage_matrix enable row level security; alter table public.gt_category_gap_queue enable row level security;
alter table public.bp_city_expansion_matrix enable row level security; alter table public.bp_business_candidates enable row level security;
alter table public.bp_verification_pipeline enable row level security; alter table public.bp_owner_claim_tasks enable row level security;

insert into public.cities(id,name,country,timezone,lat,lng,is_active) values
 ('atlanta','Atlanta','US','America/New_York',33.749,-84.388,true),('houston','Houston','US','America/Chicago',29.7604,-95.3698,true),
 ('dallas','Dallas','US','America/Chicago',32.7767,-96.797,true),('miami','Miami','US','America/New_York',25.7617,-80.1918,true),
 ('charlotte','Charlotte','US','America/New_York',35.2271,-80.8431,true),('washington-dc','Washington, DC','US','America/New_York',38.9072,-77.0369,true),
 ('new-york','New York','US','America/New_York',40.7128,-74.006,true),('los-angeles','Los Angeles','US','America/Los_Angeles',34.0522,-118.2437,true),
 ('phoenix','Phoenix','US','America/Phoenix',33.4484,-112.074,true),('las-vegas','Las Vegas','US','America/Los_Angeles',36.1699,-115.1398,true),
 ('new-orleans','New Orleans','US','America/Chicago',29.9511,-90.0715,true)
on conflict(id) do update set name=excluded.name,timezone=excluded.timezone,lat=excluded.lat,lng=excluded.lng,is_active=true;

insert into public.intel_categories(brand,slug,name) values
 ('good_times','food-drink','Food & Drink'),('good_times','nightlife','Nightlife'),('good_times','arts-culture','Arts & Culture'),
 ('good_times','music','Music'),('good_times','wellness','Wellness'),('good_times','outdoors','Outdoors'),('good_times','events','Events'),
 ('black_pages','food-hospitality','Food & Hospitality'),('black_pages','beauty-wellness','Beauty & Wellness'),('black_pages','professional-services','Professional Services'),
 ('black_pages','retail','Retail'),('black_pages','home-auto','Home & Auto'),('black_pages','arts-media','Arts & Media'),('black_pages','community','Community')
on conflict(brand,slug) do update set name=excluded.name,active=true;

insert into public.intel_subcategories(category_id,slug,name,target_per_city)
select c.id,v.slug,v.name,v.target from public.intel_categories c join (values
 ('food-drink','restaurants','Restaurants',40),('food-drink','cocktail-bars','Cocktail Bars',15),('food-drink','coffee','Coffee',12),('food-drink','brunch','Brunch',15),
 ('nightlife','clubs','Clubs',12),('nightlife','lounges','Lounges',12),('nightlife','rooftops','Rooftops',8),('arts-culture','museums','Museums',8),
 ('arts-culture','galleries','Galleries',10),('music','live-music','Live Music',15),('music','festivals','Festivals',8),('wellness','spas','Spas',10),
 ('wellness','fitness','Fitness',12),('outdoors','parks','Parks',12),('outdoors','adventures','Adventures',8),('events','daily-events','Daily Events',30),
 ('events','cultural-events','Cultural Events',15),('food-hospitality','restaurants','Restaurants',100),('food-hospitality','catering','Catering',40),
 ('beauty-wellness','barbers','Barbers',40),('beauty-wellness','salons','Salons',50),('professional-services','legal','Legal',40),
 ('professional-services','financial','Financial',40),('professional-services','consulting','Consulting',40),('retail','fashion','Fashion',50),
 ('retail','specialty-retail','Specialty Retail',50),('home-auto','contractors','Contractors',50),('home-auto','automotive','Automotive',40),
 ('arts-media','creative-services','Creative Services',50),('arts-media','media','Media',30),('community','nonprofits','Nonprofits',30),('community','education','Education',30)
) v(category_slug,slug,name,target) on c.slug=v.category_slug
on conflict(category_id,slug) do update set name=excluded.name,target_per_city=excluded.target_per_city,active=true;

insert into public.gt_city_coverage_matrix(city_id,subcategory_id,target_count)
select ci.id,s.id,s.target_per_city from public.cities ci cross join public.intel_subcategories s join public.intel_categories c on c.id=s.category_id
where ci.id in ('atlanta','houston','dallas','miami','charlotte','washington-dc','new-york','los-angeles','phoenix','las-vegas','new-orleans') and c.brand='good_times'
on conflict(city_id,subcategory_id) do update set target_count=excluded.target_count,updated_at=now();

insert into public.bp_city_expansion_matrix(city_id,target_businesses,launch_priority) values
 ('atlanta',2500,100),('houston',1000,90),('dallas',1000,90),('miami',1000,90),('charlotte',750,80),
 ('washington-dc',750,70),('new-york',1500,70),('los-angeles',1500,70),('phoenix',750,60),('las-vegas',750,60)
on conflict(city_id) do update set target_businesses=excluded.target_businesses,launch_priority=excluded.launch_priority,updated_at=now();

insert into public.gt_agent_registry(agent_key,name,purpose,allowed_actions,data_domains,cadence,status,requires_human_review,config)
values
 ('city-discovery','City Discovery Agent','Discover venues by city/category',array['discover','enqueue'],array['cities','venues'],'daily','active',true,'{}'),
 ('event-discovery','Event Discovery Agent','Discover and refresh events',array['discover','refresh','enqueue'],array['events'],'hourly','active',true,'{}'),
 ('venue-refresh','Venue Refresh Agent','Refresh venue freshness and accuracy',array['refresh','score'],array['venues'],'daily','active',true,'{}'),
 ('category-gap','Category Gap Agent','Create work from coverage gaps',array['score','enqueue'],array['coverage'],'daily','active',false,'{}'),
 ('image-quality','Image Quality Agent','Score and queue image improvements',array['score','enqueue'],array['images'],'daily','active',true,'{}'),
 ('freshness','Freshness Agent','Detect stale records',array['score','enqueue'],array['venues','events'],'hourly','active',false,'{}'),
 ('bp-business-discovery','Business Discovery Agent','Discover Black-owned business candidates',array['discover','enqueue'],array['bp_candidates'],'daily','active',true,'{}'),
 ('bp-owner-verification','Owner Verification Agent','Verify ownership evidence',array['verify','enqueue'],array['bp_verification'],'daily','active',true,'{}'),
 ('bp-category-completion','Category Completion Agent','Close city/category gaps',array['score','enqueue'],array['bp_candidates'],'daily','active',false,'{}'),
 ('bp-cultural-ranking','Cultural Ranking Agent','Rank cultural relevance',array['score'],array['bp_candidates'],'daily','active',true,'{}'),
 ('bp-freshness-monitor','BP Freshness Monitor','Detect stale business records',array['score','enqueue'],array['bp_candidates'],'daily','active',false,'{}')
on conflict(agent_key) do update set name=excluded.name,purpose=excluded.purpose,allowed_actions=excluded.allowed_actions,data_domains=excluded.data_domains,cadence=excluded.cadence,status='active',config=excluded.config,updated_at=now();

insert into public.gt_category_gap_queue(city_id,subcategory_id,gap_count,priority)
select city_id,subcategory_id,greatest(target_count-verified_count,0),least(100,50+greatest(target_count-verified_count,0))::smallint
from public.gt_city_coverage_matrix where verified_count<target_count
on conflict(city_id,subcategory_id,status) do update set gap_count=excluded.gap_count,priority=excluded.priority,updated_at=now();

create or replace view public.intelligence_command_center with (security_invoker=true) as
select 'good_times'::text brand, c.id city_id, c.name city_name,
 count(m.*)::bigint matrix_cells, round(avg(m.coverage_pct),2) coverage_pct,
 sum(gap_count)::bigint open_gap_count, null::bigint discovered_count, null::bigint verified_count, null::bigint claimed_count
from public.cities c join public.gt_city_coverage_matrix m on m.city_id=c.id left join public.gt_category_gap_queue g on g.city_id=c.id and g.status in ('queued','in_progress') group by c.id,c.name
union all
select 'black_pages',c.id,c.name,0,0,0,b.discovered_businesses,b.verified_businesses,b.claimed_businesses
from public.cities c join public.bp_city_expansion_matrix b on b.city_id=c.id;
revoke all on public.intel_categories,public.intel_subcategories,public.intel_sources,public.intel_tasks,public.gt_city_coverage_matrix,public.gt_category_gap_queue,
 public.bp_city_expansion_matrix,public.bp_business_candidates,public.bp_verification_pipeline,public.bp_owner_claim_tasks from anon,authenticated;
revoke all on public.intelligence_command_center from anon,authenticated;
