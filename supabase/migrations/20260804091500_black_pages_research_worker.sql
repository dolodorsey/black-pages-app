-- BLACK PAGES autonomous public-evidence research worker.
-- This migration never publishes a candidate and never marks ownership verified.
-- Explicit public ownership language can only route a candidate to human verification.

create extension if not exists pgcrypto;
create extension if not exists pg_net;
create extension if not exists pg_cron;
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
 ('food-beverage','restaurants','Restaurants',100),
 ('food-beverage','catering','Catering',35),
 ('food-beverage','food-trucks','Food Trucks',25),
 ('food-beverage','bakeries-desserts','Bakeries & Desserts',25),
 ('food-beverage','coffee-tea','Coffee & Tea',25),
 ('beauty-wellness','barbers','Barbers',40),
 ('beauty-wellness','salons','Salons',50),
 ('beauty-wellness','spas','Spas',25),
 ('beauty-wellness','fitness','Fitness',30),
 ('beauty-wellness','wellness','Wellness',30),
 ('professional-services','legal','Legal',35),
 ('professional-services','accounting-tax','Accounting & Tax',35),
 ('professional-services','insurance','Insurance',30),
 ('professional-services','consulting','Consulting',40),
 ('professional-services','real-estate','Real Estate',40),
 ('retail','fashion','Fashion',45),
 ('retail','beauty-products','Beauty Products',30),
 ('retail','specialty-retail','Specialty Retail',45),
 ('retail','home-goods','Home Goods',25),
 ('retail','books-gifts','Books & Gifts',25),
 ('arts-culture','creative-services','Creative Services',40),
 ('arts-culture','photography-video','Photography & Video',35),
 ('arts-culture','music','Music',30),
 ('arts-culture','media','Media',30),
 ('arts-culture','museums-galleries','Museums & Galleries',20),
 ('home-services','contractors','Contractors',40),
 ('home-services','cleaning','Cleaning',35),
 ('home-services','landscaping','Landscaping',25),
 ('home-services','plumbing-electrical','Plumbing & Electrical',30),
 ('home-services','moving','Moving',25),
 ('technology','software-it','Software & IT',35),
 ('technology','web-design','Web & Design',35),
 ('technology','cybersecurity','Cybersecurity',20),
 ('technology','electronics-repair','Electronics Repair',20),
 ('automotive','repair','Auto Repair',35),
 ('automotive','detailing','Detailing',25),
 ('automotive','dealers-rental','Dealers & Rental',25),
 ('automotive','towing-transport','Towing & Transport',25),
 ('health','medical','Medical',35),
 ('health','dental','Dental',25),
 ('health','mental-health','Mental Health',30),
 ('health','pharmacy','Pharmacy',15),
 ('health','home-care','Home Care',30),
 ('education','childcare','Childcare',35),
 ('education','tutoring','Tutoring',25),
 ('education','trade-schools','Trade Schools',20),
 ('education','training-coaching','Training & Coaching',30),
 ('community','nonprofits','Nonprofits',30),
 ('community','faith','Faith Organizations',25),
 ('community','civic-groups','Civic Groups',20),
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
    when lower(coalesce(p_raw,'')) ~ '(technology|software|\bit\b|cyber|web_design|electronics)' then 'technology'
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

create index if not exists black_pages_research_runs_started_idx
  on public.black_pages_research_runs(started_at desc);
create index if not exists black_pages_candidate_research_worker_idx
  on public.black_pages_candidate_queue(assigned_researcher,pipeline_stage,next_action_at,priority_score desc)
  where pipeline_stage='research';

-- Backfill the live Atlanta directory into the private owner-research queue.
-- Public labels and public directory rows are not changed.
insert into public.black_pages_candidate_queue(
  source_venue_id,source_type,business_name,city,state,category,website_url,
  instagram_handle,public_phone,source_sheets,data_quality_status,
  ownership_evidence_status,pipeline_stage,priority_score,next_action_at,notes
)
select
  v.id,'venue_intelligence',v.name,'Atlanta','GA',coalesce(v.category_key,'business'),
  v.website,v.instagram_handle,v.phone,'{}'::text[],
  case when nullif(v.website,'') is not null then 'research_ready' else 'needs_enrichment' end,
  'unreviewed','research',
  round((
    case when nullif(v.website,'') is not null then 20 else 0 end +
    case when nullif(v.instagram_handle,'') is not null then 15 else 0 end +
    case when nullif(v.phone,'') is not null then 10 else 0 end +
    case when nullif(v.hero_image,'') is not null then 10 else 0 end +
    case when v.latitude is not null and v.longitude is not null then 10 else 0 end +
    coalesce(v.google_rating,0)*5 + least(coalesce(v.google_reviews,0),250)::numeric/10
  )::numeric,2),
  now()+(
    row_number() over(order by coalesce(v.google_reviews,0) desc,coalesce(v.google_rating,0) desc,v.id)-1
  )*interval '5 minutes',
  'Private owner-verification research. Do not publish or mark owner-verified without an approved claim.'
from public.gt_venues v
where v.status='active' and v.city_key='atlanta' and coalesce(v.is_black_owned,false)=true
on conflict(source_venue_id) where source_venue_id is not null do update set
  business_name=excluded.business_name,
  category=excluded.category,
  website_url=excluded.website_url,
  instagram_handle=excluded.instagram_handle,
  public_phone=excluded.public_phone,
  data_quality_status=excluded.data_quality_status,
  priority_score=excluded.priority_score,
  updated_at=now();

with ranked as (
  select id,row_number() over(order by priority_score desc,id) rn
  from public.black_pages_candidate_queue
  where lower(city)='atlanta' and pipeline_stage='research'
)
update public.black_pages_candidate_queue q
set assigned_researcher='black-pages-owner-verification-agent',
    next_action_at=least(q.next_action_at,now()+(r.rn-1)*interval '15 minutes'),
    updated_at=now()
from ranked r
where q.id=r.id and r.rn<=50;

-- Create a private worker token once. The raw token stays in Vault; only its hash is stored here.
do $block$
declare
  v_token text;
begin
  select decrypted_secret into v_token
  from vault.decrypted_secrets
  where name='black_pages_research_worker_token'
  order by created_at desc
  limit 1;

  if nullif(v_token,'') is null then
    v_token:=encode(gen_random_bytes(32),'hex');
    perform vault.create_secret(
      v_token,
      'black_pages_research_worker_token',
      'Internal BLACK PAGES research worker dispatch token'
    );
  end if;

  insert into public.black_pages_worker_config(config_key,token_hash,is_active)
  values('research_worker',digest(v_token,'sha256'),true)
  on conflict(config_key) do update set
    token_hash=excluded.token_hash,is_active=true,updated_at=now();
end
$block$;

create or replace function public.black_pages_authorize_worker_token(p_token text)
returns boolean
language sql
security definer
set search_path='pg_catalog','public'
as $$
  select exists(
    select 1
    from public.black_pages_worker_config
    where config_key='research_worker'
      and is_active
      and token_hash=digest(coalesce(p_token,''),'sha256')
  );
$$;

create or replace function public.black_pages_claim_research_batch(
  p_limit integer default 10,
  p_worker text default 'black-pages-research-worker'
)
returns jsonb
language plpgsql
security definer
set search_path='pg_catalog','public'
as $function$
declare
  v_limit integer:=least(25,greatest(1,coalesce(p_limit,10)));
  v_worker text:=left(coalesce(nullif(trim(p_worker),''),'black-pages-research-worker'),120);
  v_run_id uuid;
  v_candidates jsonb;
  v_claimed integer;
begin
  if auth.role()<>'service_role' then
    raise exception 'Service role required' using errcode='42501';
  end if;

  insert into public.black_pages_research_runs(worker,requested_limit)
  values(v_worker,v_limit)
  returning id into v_run_id;

  with due as (
    select q.id
    from public.black_pages_candidate_queue q
    where q.pipeline_stage='research'
      and q.ownership_evidence_status in ('unreviewed','insufficient')
      and q.next_action_at<=now()
      and q.assigned_researcher in ('black-pages-owner-verification-agent',v_worker)
      and not exists(
        select 1 from public.black_pages_candidate_activity a
        where a.candidate_id=q.id
          and a.activity_type='research'
          and a.outcome='claimed'
          and a.occurred_at>now()-interval '20 minutes'
      )
    order by q.priority_score desc,q.next_action_at,q.id
    for update skip locked
    limit v_limit
  ), claimed as (
    update public.black_pages_candidate_queue q
    set assigned_researcher=v_worker,
        next_action_at=now()+interval '30 minutes',
        updated_at=now()
    from due d
    where q.id=d.id
    returning q.*
  ), activities as (
    insert into public.black_pages_candidate_activity(
      candidate_id,activity_type,outcome,details,performed_by
    )
    select id,'research','claimed',jsonb_build_object('run_id',v_run_id),v_worker
    from claimed
    returning candidate_id
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'id',c.id,
    'business_name',c.business_name,
    'city',c.city,
    'state',c.state,
    'category',c.category,
    'website_url',c.website_url,
    'instagram_handle',c.instagram_handle,
    'public_email',c.public_email,
    'public_phone',c.public_phone,
    'priority_score',c.priority_score
  ) order by c.priority_score desc,c.id),'[]'::jsonb),count(*)::integer
  into v_candidates,v_claimed
  from claimed c;

  update public.black_pages_research_runs
  set claimed_count=coalesce(v_claimed,0),
      status=case when coalesce(v_claimed,0)=0 then 'completed' else status end,
      completed_at=case when coalesce(v_claimed,0)=0 then now() else completed_at end,
      summary=jsonb_build_object('claimed',coalesce(v_claimed,0))
  where id=v_run_id;

  return jsonb_build_object(
    'run_id',v_run_id,
    'worker',v_worker,
    'claimed_count',coalesce(v_claimed,0),
    'candidates',coalesce(v_candidates,'[]'::jsonb)
  );
end;
$function$;

create or replace function public.black_pages_complete_research_candidate(
  p_run_id uuid,
  p_candidate_id uuid,
  p_result jsonb,
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
  v_final_url text:=nullif(left(coalesce(p_result->>'final_url',''),500),'');
  v_candidate public.black_pages_candidate_queue%rowtype;
begin
  if auth.role()<>'service_role' then
    raise exception 'Service role required' using errcode='42501';
  end if;

  if not exists(
    select 1 from public.black_pages_research_runs
    where id=p_run_id and status='started'
  ) then
    raise exception 'Active research run not found';
  end if;

  select * into v_candidate
  from public.black_pages_candidate_queue
  where id=p_candidate_id
  for update;
  if not found then raise exception 'Candidate not found'; end if;

  select count(*)::integer into v_prior_completed
  from public.black_pages_candidate_activity
  where candidate_id=p_candidate_id
    and activity_type='research'
    and outcome in ('evidence_found','reachable_no_evidence','unreachable','failed');

  if v_explicit then
    v_outcome:='evidence_found';
    v_stage:='verification';
    v_evidence_status:='evidence_found';
    v_next_action:=now();
  elsif v_reachable then
    v_outcome:='reachable_no_evidence';
    v_stage:='research';
    v_evidence_status:=case when v_prior_completed>=2 then 'insufficient' else 'unreviewed' end;
    v_next_action:=now()+case when v_prior_completed>=2 then interval '30 days' else interval '7 days' end;
  elsif v_error then
    v_outcome:='failed';
    v_stage:='research';
    v_evidence_status:=case when v_prior_completed>=2 then 'insufficient' else 'unreviewed' end;
    v_next_action:=now()+case when v_prior_completed>=2 then interval '14 days' else interval '2 days' end;
  else
    v_outcome:='unreachable';
    v_stage:='research';
    v_evidence_status:=case when v_prior_completed>=2 then 'insufficient' else 'unreviewed' end;
    v_next_action:=now()+case when v_prior_completed>=2 then interval '14 days' else interval '2 days' end;
  end if;

  update public.black_pages_candidate_queue
  set website_url=case
        when v_final_url ~* '^https?://' then v_final_url
        else website_url
      end,
      data_quality_status=case
        when v_explicit then 'ownership_evidence_found'
        when v_reachable then 'public_endpoint_checked'
        else 'needs_enrichment'
      end,
      ownership_evidence_status=v_evidence_status,
      pipeline_stage=v_stage,
      assigned_researcher=case
        when v_explicit then 'black-pages-owner-verification-agent'
        else left(coalesce(nullif(trim(p_worker),''),'black-pages-research-worker'),120)
      end,
      next_action_at=v_next_action,
      notes=left(concat_ws(E'\n',nullif(notes,''),
        case
          when v_explicit then 'Public ownership language found. Human verification required before any owner-verified label.'
          when v_reachable then 'Public business endpoint checked; no explicit Black-ownership statement found.'
          else 'Public endpoint unavailable or incomplete; no ownership conclusion made.'
        end
      ),4000),
      updated_at=now()
  where id=p_candidate_id;

  insert into public.black_pages_candidate_activity(
    candidate_id,activity_type,outcome,details,performed_by
  ) values (
    p_candidate_id,'research',v_outcome,
    coalesce(p_result,'{}'::jsonb)||jsonb_build_object(
      'run_id',p_run_id,
      'ownership_decision','human_review_required',
      'published',false,
      'owner_verified',false
    ),
    left(coalesce(nullif(trim(p_worker),''),'black-pages-research-worker'),120)
  );

  update public.black_pages_research_runs
  set processed_count=processed_count+1,
      reachable_count=reachable_count+case when v_reachable then 1 else 0 end,
      evidence_found_count=evidence_found_count+case when v_explicit then 1 else 0 end,
      failed_count=failed_count+case when v_error or not v_reachable then 1 else 0 end,
      summary=summary||jsonb_build_object('last_candidate_id',p_candidate_id,'last_outcome',v_outcome)
  where id=p_run_id;

  return jsonb_build_object(
    'candidate_id',p_candidate_id,
    'outcome',v_outcome,
    'pipeline_stage',v_stage,
    'ownership_evidence_status',v_evidence_status,
    'published',false,
    'owner_verified',false
  );
end;
$function$;

create or replace function public.black_pages_finalize_research_run(
  p_run_id uuid,
  p_error text default null
)
returns jsonb
language plpgsql
security definer
set search_path='pg_catalog','public'
as $function$
declare
  v_run public.black_pages_research_runs%rowtype;
begin
  if auth.role()<>'service_role' then
    raise exception 'Service role required' using errcode='42501';
  end if;

  update public.black_pages_research_runs
  set status=case when nullif(trim(coalesce(p_error,'')),'') is null then 'completed' else 'failed' end,
      error_message=nullif(left(coalesce(p_error,''),1000),''),
      completed_at=now(),
      summary=summary||jsonb_build_object('finished_at',now())
  where id=p_run_id
  returning * into v_run;

  if not found then raise exception 'Research run not found'; end if;
  return to_jsonb(v_run);
end;
$function$;

revoke all on function public.black_pages_authorize_worker_token(text) from public,anon,authenticated;
revoke all on function public.black_pages_claim_research_batch(integer,text) from public,anon,authenticated;
revoke all on function public.black_pages_complete_research_candidate(uuid,uuid,jsonb,text) from public,anon,authenticated;
revoke all on function public.black_pages_finalize_research_run(uuid,text) from public,anon,authenticated;
grant execute on function public.black_pages_authorize_worker_token(text) to service_role;
grant execute on function public.black_pages_claim_research_batch(integer,text) to service_role;
grant execute on function public.black_pages_complete_research_candidate(uuid,uuid,jsonb,text) to service_role;
grant execute on function public.black_pages_finalize_research_run(uuid,text) to service_role;

create or replace view public.black_pages_research_pipeline_health
with (security_invoker=true)
as
select
  count(*)::integer total_candidates,
  count(*) filter(where lower(city)='atlanta')::integer atlanta_candidates,
  count(*) filter(where lower(city)<>'atlanta')::integer expansion_candidates,
  count(*) filter(where assigned_researcher is not null)::integer assigned_candidates,
  count(*) filter(where pipeline_stage='research' and next_action_at<=now())::integer due_research,
  count(*) filter(where ownership_evidence_status='evidence_found')::integer evidence_found,
  count(*) filter(where ownership_evidence_status='owner_confirmed')::integer owner_confirmed,
  count(*) filter(where pipeline_stage='verification')::integer awaiting_verification,
  count(*) filter(where pipeline_stage='published')::integer worker_published,
  (select count(*)::integer from public.black_pages_candidate_activity where activity_type='research' and outcome<>'claimed') completed_research_checks,
  (select count(*)::integer from public.black_pages_research_runs where status='completed') completed_worker_runs,
  now() evaluated_at
from public.black_pages_candidate_queue;
revoke all on public.black_pages_research_pipeline_health from public,anon,authenticated;

create or replace view public.black_pages_category_stock_health
with (security_invoker=true)
as
with cities as (
  select city,state,target_published_businesses
  from public.black_pages_city_targets
  where is_active
), public_counts as (
  select lower(city) city_key,coalesce(state,'') state,
         public.black_pages_canonical_category(category) category_slug,
         count(*)::integer published_count
  from public.black_pages_directory
  group by lower(city),coalesce(state,''),public.black_pages_canonical_category(category)
), candidate_counts as (
  select lower(city) city_key,coalesce(state,'') state,
         public.black_pages_canonical_category(category) category_slug,
         count(*) filter(where pipeline_stage not in ('rejected','do_not_contact'))::integer candidate_count,
         count(*) filter(where ownership_evidence_status='evidence_found')::integer evidence_count
  from public.black_pages_candidate_queue
  group by lower(city),coalesce(state,''),public.black_pages_canonical_category(category)
)
select ci.city,ci.state,c.slug category_slug,c.name category_name,
       coalesce(pc.published_count,0) published_count,
       coalesce(qc.candidate_count,0) candidate_count,
       coalesce(qc.evidence_count,0) evidence_count,
       greatest(ceil(ci.target_published_businesses/11.0)::integer-coalesce(pc.published_count,0),0) category_publishing_gap,
       c.sort_order
from cities ci
cross join public.black_pages_categories c
left join public_counts pc
  on pc.city_key=lower(ci.city) and pc.state=ci.state and pc.category_slug=c.slug
left join candidate_counts qc
  on qc.city_key=lower(ci.city) and qc.state=ci.state and qc.category_slug=c.slug
where c.active;
revoke all on public.black_pages_category_stock_health from public,anon,authenticated;

create or replace function public.black_pages_dispatch_research_worker(p_limit integer default 10)
returns bigint
language plpgsql
security definer
set search_path='pg_catalog','public','net','vault'
as $function$
declare
  v_token text;
  v_request_id bigint;
begin
  select decrypted_secret into v_token
  from vault.decrypted_secrets
  where name='black_pages_research_worker_token'
  order by created_at desc
  limit 1;

  if nullif(v_token,'') is null then
    raise exception 'BLACK PAGES worker token missing';
  end if;

  select net.http_post(
    url:='https://dzlmtvodpyhetvektfuo.supabase.co/functions/v1/black-pages-research-worker',
    headers:=jsonb_build_object(
      'Content-Type','application/json',
      'x-worker-token',v_token
    ),
    body:=jsonb_build_object('limit',least(25,greatest(1,coalesce(p_limit,10))))
  ) into v_request_id;

  return v_request_id;
end;
$function$;

revoke all on function public.black_pages_dispatch_research_worker(integer) from public,anon,authenticated;
grant execute on function public.black_pages_dispatch_research_worker(integer) to service_role;

do $block$
begin
  if not exists(select 1 from cron.job where jobname='black-pages-research-worker') then
    perform cron.schedule(
      'black-pages-research-worker',
      '*/15 * * * *',
      $cmd$select public.black_pages_dispatch_research_worker(10);$cmd$
    );
  end if;
end
$block$;
