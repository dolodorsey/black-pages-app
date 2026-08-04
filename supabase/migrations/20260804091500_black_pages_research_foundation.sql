-- BLACK PAGES research foundation.
-- Private controls only: no publishing and no ownership verification changes.

create extension if not exists pgcrypto;
create extension if not exists supabase_vault;

create table if not exists public.black_pages_categories (
  slug text primary key,
  name text not null,
  description text,
  sort_order smallint not null default 100,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.black_pages_subcategories (
  category_slug text not null references public.black_pages_categories(slug) on delete cascade,
  slug text not null,
  name text not null,
  target_per_city integer not null default 10 check(target_per_city>=0),
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key(category_slug,slug)
);

insert into public.black_pages_categories(slug,name,description,sort_order) values
 ('food-beverage','Food & Beverage','Restaurants, caterers, food makers, and beverage businesses',10),
 ('beauty-wellness','Beauty & Wellness','Beauty, grooming, fitness, and wellness providers',20),
 ('professional-services','Professional Services','Legal, financial, insurance, real estate, and consulting',30),
 ('retail','Retail','Fashion, products, books, gifts, and specialty stores',40),
 ('arts-culture','Arts & Culture','Creative services, media, music, and cultural institutions',50),
 ('home-services','Home Services','Construction, maintenance, cleaning, moving, and property services',60),
 ('technology','Technology','Software, IT, digital services, cybersecurity, and repair',70),
 ('automotive','Automotive','Repair, detailing, sales, rental, towing, and transportation',80),
 ('health','Health','Medical, dental, mental health, pharmacy, and care services',90),
 ('education','Education','Childcare, tutoring, training, trades, and education providers',100),
 ('community','Community','Nonprofits, faith organizations, civic groups, and community spaces',110)
on conflict(slug) do update set
 name=excluded.name,description=excluded.description,sort_order=excluded.sort_order,active=true,updated_at=now();

insert into public.black_pages_subcategories(category_slug,slug,name,target_per_city) values
 ('food-beverage','restaurants','Restaurants',100),('food-beverage','catering','Catering',35),
 ('food-beverage','food-trucks','Food Trucks',25),('food-beverage','bakeries-desserts','Bakeries & Desserts',25),
 ('food-beverage','coffee-tea','Coffee & Tea',25),('beauty-wellness','barbers','Barbers',40),
 ('beauty-wellness','salons','Salons',50),('beauty-wellness','spas','Spas',25),
 ('beauty-wellness','fitness','Fitness',30),('beauty-wellness','wellness','Wellness',30),
 ('professional-services','legal','Legal',35),('professional-services','accounting-tax','Accounting & Tax',35),
 ('professional-services','insurance','Insurance',30),('professional-services','consulting','Consulting',40),
 ('professional-services','real-estate','Real Estate',40),('retail','fashion','Fashion',45),
 ('retail','beauty-products','Beauty Products',30),('retail','specialty-retail','Specialty Retail',45),
 ('retail','home-goods','Home Goods',25),('retail','books-gifts','Books & Gifts',25),
 ('arts-culture','creative-services','Creative Services',40),('arts-culture','photography-video','Photography & Video',35),
 ('arts-culture','music','Music',30),('arts-culture','media','Media',30),
 ('arts-culture','museums-galleries','Museums & Galleries',20),('home-services','contractors','Contractors',40),
 ('home-services','cleaning','Cleaning',35),('home-services','landscaping','Landscaping',25),
 ('home-services','plumbing-electrical','Plumbing & Electrical',30),('home-services','moving','Moving',25),
 ('technology','software-it','Software & IT',35),('technology','web-design','Web & Design',35),
 ('technology','cybersecurity','Cybersecurity',20),('technology','electronics-repair','Electronics Repair',20),
 ('automotive','repair','Auto Repair',35),('automotive','detailing','Detailing',25),
 ('automotive','dealers-rental','Dealers & Rental',25),('automotive','towing-transport','Towing & Transport',25),
 ('health','medical','Medical',35),('health','dental','Dental',25),
 ('health','mental-health','Mental Health',30),('health','pharmacy','Pharmacy',15),
 ('health','home-care','Home Care',30),('education','childcare','Childcare',35),
 ('education','tutoring','Tutoring',25),('education','trade-schools','Trade Schools',20),
 ('education','training-coaching','Training & Coaching',30),('community','nonprofits','Nonprofits',30),
 ('community','faith','Faith Organizations',25),('community','civic-groups','Civic Groups',20),
 ('community','community-spaces','Community Spaces',25)
on conflict(category_slug,slug) do update set
 name=excluded.name,target_per_city=excluded.target_per_city,active=true,updated_at=now();

create or replace function public.black_pages_canonical_category(p_raw text)
returns text
language sql
immutable
set search_path='pg_catalog','public'
as $$
  select case
    when lower(coalesce(p_raw,'')) ~ '(restaurant|brunch|food|coffee|catering|bakery|dessert|bar|lounge|nightclub|hookah|wine|jazz|food_hall)' then 'food-beverage'
    when lower(coalesce(p_raw,'')) ~ '(beauty|barber|salon|spa|fitness|wellness)' then 'beauty-wellness'
    when lower(coalesce(p_raw,'')) ~ '(legal|law|account|tax|insurance|consult|real_estate|professional)' then 'professional-services'
    when lower(coalesce(p_raw,'')) ~ '(shopping|retail|fashion|boutique|books|gifts)' then 'retail'
    when lower(coalesce(p_raw,'')) ~ '(culture|creative|photo|video|music|media|museum|gallery|comedy|entertainment)' then 'arts-culture'
    when lower(coalesce(p_raw,'')) ~ '(contract|cleaning|landscap|plumb|electric|moving|home_service)' then 'home-services'
    when lower(coalesce(p_raw,'')) ~ '(technology|software|cyber|web_design|electronics)' then 'technology'
    when lower(coalesce(p_raw,'')) ~ '(auto|vehicle|detail|towing|transport)' then 'automotive'
    when lower(coalesce(p_raw,'')) ~ '(health|medical|dental|mental|pharmacy|home_care)' then 'health'
    when lower(coalesce(p_raw,'')) ~ '(education|childcare|tutor|school|training|coaching)' then 'education'
    when lower(coalesce(p_raw,'')) ~ '(nonprofit|faith|church|civic|community|event_venue)' then 'community'
    else 'community'
  end;
$$;

create table if not exists public.black_pages_research_runs (
  id uuid primary key default gen_random_uuid(),
  worker text not null,
  status text not null default 'started' check(status in ('started','completed','failed')),
  requested_limit integer not null default 10 check(requested_limit between 1 and 25),
  claimed_count integer not null default 0,
  processed_count integer not null default 0,
  reachable_count integer not null default 0,
  evidence_found_count integer not null default 0,
  failed_count integer not null default 0,
  summary jsonb not null default '{}',
  error_message text,
  started_at timestamptz not null default now(),
  completed_at timestamptz
);

create table if not exists public.black_pages_worker_config (
  config_key text primary key,
  token_hash bytea not null,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.black_pages_categories enable row level security;
alter table public.black_pages_subcategories enable row level security;
alter table public.black_pages_research_runs enable row level security;
alter table public.black_pages_worker_config enable row level security;
revoke all on public.black_pages_categories,public.black_pages_subcategories,
 public.black_pages_research_runs,public.black_pages_worker_config from public,anon,authenticated;

create index if not exists black_pages_research_runs_started_idx on public.black_pages_research_runs(started_at desc);
create index if not exists black_pages_candidate_research_worker_idx
 on public.black_pages_candidate_queue(assigned_researcher,pipeline_stage,next_action_at,priority_score desc)
 where pipeline_stage='research';

-- Add all existing live Atlanta profiles to the private verification queue.
insert into public.black_pages_candidate_queue(
  source_venue_id,source_type,business_name,city,state,category,website_url,
  instagram_handle,public_phone,source_sheets,data_quality_status,
  ownership_evidence_status,pipeline_stage,priority_score,next_action_at,notes
)
select v.id,'venue_intelligence',v.name,'Atlanta','GA',coalesce(v.category_key,'business'),
  v.website,v.instagram_handle,v.phone,'{}'::text[],
  case when nullif(v.website,'') is not null then 'research_ready' else 'needs_enrichment' end,
  'unreviewed','research',
  round((case when nullif(v.website,'') is not null then 20 else 0 end +
    case when nullif(v.instagram_handle,'') is not null then 15 else 0 end +
    case when nullif(v.phone,'') is not null then 10 else 0 end +
    case when nullif(v.hero_image,'') is not null then 10 else 0 end +
    case when v.latitude is not null and v.longitude is not null then 10 else 0 end +
    coalesce(v.google_rating,0)*5 + least(coalesce(v.google_reviews,0),250)::numeric/10)::numeric,2),
  now()+(row_number() over(order by coalesce(v.google_reviews,0) desc,coalesce(v.google_rating,0) desc,v.id)-1)*interval '5 minutes',
  'Private owner-verification research. Do not publish or mark owner-verified without an approved claim.'
from public.gt_venues v
where v.status='active' and v.city_key='atlanta' and coalesce(v.is_black_owned,false)=true
on conflict(source_venue_id) where source_venue_id is not null do update set
  business_name=excluded.business_name,category=excluded.category,website_url=excluded.website_url,
  instagram_handle=excluded.instagram_handle,public_phone=excluded.public_phone,
  data_quality_status=excluded.data_quality_status,priority_score=excluded.priority_score,updated_at=now();

with ranked as (
  select id,row_number() over(order by priority_score desc,id) rn
  from public.black_pages_candidate_queue
  where lower(city)='atlanta' and pipeline_stage='research'
)
update public.black_pages_candidate_queue q
set assigned_researcher='black-pages-owner-verification-agent',
    next_action_at=least(q.next_action_at,now()+(r.rn-1)*interval '15 minutes'),updated_at=now()
from ranked r where q.id=r.id and r.rn<=50;

-- Generate a dispatch token once. The raw value remains in Vault.
do $block$
declare v_token text;
begin
  select decrypted_secret into v_token from vault.decrypted_secrets
  where name='black_pages_research_worker_token' order by created_at desc limit 1;
  if nullif(v_token,'') is null then
    v_token:=encode(extensions.gen_random_bytes(32),'hex');
    perform vault.create_secret(v_token,'black_pages_research_worker_token','Internal BLACK PAGES research worker token');
  end if;
  insert into public.black_pages_worker_config(config_key,token_hash,is_active)
  values('research_worker',extensions.digest(convert_to(v_token,'UTF8'),'sha256'),true)
  on conflict(config_key) do update set token_hash=excluded.token_hash,is_active=true,updated_at=now();
end
$block$;

create or replace function public.black_pages_authorize_worker_token(p_token text)
returns boolean
language sql
security definer
set search_path='pg_catalog','public','extensions'
as $$
  select exists(
    select 1 from public.black_pages_worker_config
    where config_key='research_worker' and is_active
      and token_hash=extensions.digest(convert_to(coalesce(p_token,''),'UTF8'),'sha256')
  );
$$;

revoke all on function public.black_pages_authorize_worker_token(text) from public,anon,authenticated;
grant execute on function public.black_pages_authorize_worker_token(text) to service_role;
