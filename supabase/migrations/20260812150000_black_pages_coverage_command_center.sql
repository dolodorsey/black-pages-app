-- THE BLACK PAGES coverage command center.
-- Adds the source-enrichment queue, 11-city x 441-type matrix, candidate taxonomy routing,
-- gap-task reprioritization, staff-only dashboard RPC, and recurring workers.

alter table public.black_pages_candidate_queue add column if not exists subcategory text;

create table if not exists public.black_pages_source_enrichment_queue (
  id uuid primary key default gen_random_uuid(), source_type text not null default 'gt_venue', source_id uuid not null,
  business_name text not null, city text not null, state text, category_slug text, subcategory_slug text,
  website_url text, instagram_handle text, google_place_id text, issue_codes text[] not null default '{}'::text[],
  priority_score integer not null default 0, status text not null default 'pending' check (status in ('pending','processing','retry','manual','complete')),
  attempt_count integer not null default 0, locked_by text, locked_at timestamptz, next_action_at timestamptz not null default now(),
  result jsonb, created_at timestamptz not null default now(), updated_at timestamptz not null default now(), unique(source_type,source_id)
);
create index if not exists black_pages_source_enrichment_claim_idx on public.black_pages_source_enrichment_queue(status,next_action_at,priority_score desc);
alter table public.black_pages_source_enrichment_queue enable row level security;
revoke all on table public.black_pages_source_enrichment_queue from public,anon,authenticated;

create table if not exists public.black_pages_research_gap_tasks (
  id uuid primary key default gen_random_uuid(), city text not null, state text not null, category_slug text not null, subcategory_slug text not null,
  category_name text not null, subcategory_name text not null, target_count integer not null default 1, published_count integer not null default 0,
  candidate_count integer not null default 0, gap_count integer not null default 0, priority_score integer not null default 0, query_text text not null,
  status text not null default 'pending' check(status in('pending','active','complete','paused')), last_refreshed_at timestamptz not null default now(),
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(), unique(city,state,category_slug,subcategory_slug)
);
create index if not exists black_pages_research_gap_priority_idx on public.black_pages_research_gap_tasks(status,priority_score desc,gap_count desc);
alter table public.black_pages_research_gap_tasks enable row level security;
revoke all on table public.black_pages_research_gap_tasks from public,anon,authenticated;

create or replace function public.black_pages_canonical_subcategory(p_category text,p_subcategory text)
returns text language plpgsql stable set search_path=pg_catalog,public as $$
declare c text:=public.black_pages_canonical_category(p_category);raw text:=lower(btrim(coalesce(p_subcategory,'')));norm text;mapped text;
begin
 if raw='' then return null;end if; norm:=regexp_replace(regexp_replace(raw,'[^a-z0-9]+','-','g'),'^-|-$','','g');
 if c='business-services' and norm in('festival','day-party','brunch-party') then return null;end if;
 if c='nightlife-entertainment' and norm='event-series' then return null;end if;
 if c='food-beverage' and norm='day-party-brunch' then return null;end if;
 mapped:=case
  when c='arts-culture' and norm in('art-museum','black-history') then 'museums' when c='arts-culture' and norm='library' then 'cultural-centers' when c='arts-culture' and norm='live-music' then 'music'
  when c='beauty-wellness' and norm='barbershop' then 'barbershops' when c='beauty-wellness' and norm='day-spa' then 'spas' when c='beauty-wellness' and norm='natural-salon' then 'natural-hair-salons' when c='beauty-wellness' and norm='salon' then 'salons' when c='beauty-wellness' and norm='wellness-bar' then 'wellness-centers'
  when c='food-beverage' and norm='soul-food' then 'soul-food'
  when c='food-beverage' and norm in('casual-dining','brunch','soul-brunch','breakfast','southern','steakhouse','american','asian-fusion','burgers','cheesesteaks','chicken','creole','french','fusion','indian-lounge','late-night-24-hour-eats','mac-cheese','pizza','wings','quick-bites-fast-casual') then 'restaurants'
  when c='food-beverage' and norm in('caribbean','caribbean-cafe') then 'caribbean-restaurants' when c='food-beverage' and norm='vegan' then 'vegan-restaurants'
  when c='food-beverage' and norm in('coffee-shops','coffee-shop') then 'coffee-shops' when c='food-beverage' and norm='bbq' then 'bbq-restaurants' when c='food-beverage' and norm='seafood' then 'seafood-restaurants'
  when c='food-beverage' and norm='wine-bar' then 'wine-bars' when c='food-beverage' and norm='brewery' then 'bars' when c='food-beverage' and norm='ethiopian' then 'african-restaurants' when c='food-beverage' and norm='sports-bars' then 'bars' when c='food-beverage' and norm='tea' then 'coffee-tea'
  when c='nightlife-entertainment' and norm in('lounge','lounges','upscale-lounge','soul-lounge','speakeasy') then 'lounges' when c='nightlife-entertainment' and norm='hookah-lounge' then 'hookah-lounges'
  when c='nightlife-entertainment' and norm in('nightclub','nightclubs') then 'nightclubs' when c='nightlife-entertainment' and norm='gentleman-s-clubs' then 'gentlemens-clubs' when c='nightlife-entertainment' and norm='comedy-club' then 'comedy-clubs' when c='nightlife-entertainment' and norm='jazz-club' then 'jazz-clubs'
  when c='retail' and norm='bookshop' then 'bookstores' when c='retail' and norm in('boutique','boutiques','streetwear') then 'fashion'
  when c='sports-fitness' and norm='boutique-fitness' then 'fitness-studios' when c='sports-fitness' and norm='run-club' then 'run-clubs'
  when c='venues-spaces' and norm='event-venues' then 'event-venues' else null end;
 if mapped is not null then return mapped;end if;
 select s.slug into mapped from public.black_pages_subcategories s where s.active and s.category_slug=c and s.slug=norm limit 1; if mapped is not null then return mapped;end if;
 select s.slug into mapped from public.black_pages_subcategories s where s.active and s.category_slug=c and regexp_replace(regexp_replace(lower(s.name),'[^a-z0-9]+','-','g'),'^-|-$','','g')=norm limit 1;
 return mapped;
end$$;

create or replace function public.black_pages_candidate_category(p_raw text) returns text language sql immutable as $$
select case lower(btrim(coalesce(p_raw,'')))
 when 'restaurant' then 'food-beverage' when 'brunch' then 'food-beverage' when 'bar' then 'food-beverage' when 'coffee' then 'food-beverage' when 'food' then 'food-beverage' when 'food_hall' then 'food-beverage' when 'wine_bar' then 'food-beverage' when 'food_truck' then 'food-beverage'
 when 'nightlife' then 'nightlife-entertainment' when 'nightclub' then 'nightlife-entertainment' when 'hookah' then 'nightlife-entertainment' when 'rooftop' then 'nightlife-entertainment' when 'lounge' then 'nightlife-entertainment' when 'speakeasy' then 'nightlife-entertainment' when 'sports_bar' then 'nightlife-entertainment' when 'comedy' then 'nightlife-entertainment' when 'jazz' then 'nightlife-entertainment' when 'entertainment' then 'nightlife-entertainment' when 'experiences' then 'nightlife-entertainment'
 when 'event_venue' then 'venues-spaces' when 'beauty' then 'beauty-wellness' when 'spa' then 'beauty-wellness' when 'wellness' then 'beauty-wellness' when 'culture' then 'arts-culture' when 'shopping' then 'retail' when 'fitness' then 'sports-fitness' when 'outdoor_adventures' then 'sports-fitness'
 when 'day_party' then null when 'pool_party' then null when 'special_events' then null else public.black_pages_canonical_category(p_raw) end$$;

create or replace function public.black_pages_candidate_subcategory(p_raw text) returns text language sql immutable as $$
select case lower(btrim(coalesce(p_raw,'')))
 when 'restaurant' then 'restaurants' when 'brunch' then 'restaurants' when 'bar' then 'bars' when 'coffee' then 'coffee-shops' when 'food' then 'restaurants' when 'food_hall' then 'restaurants' when 'wine_bar' then 'wine-bars' when 'food_truck' then 'food-trucks'
 when 'nightlife' then 'lounges' when 'nightclub' then 'nightclubs' when 'hookah' then 'hookah-lounges' when 'rooftop' then 'lounges' when 'lounge' then 'lounges' when 'speakeasy' then 'lounges' when 'sports_bar' then 'sports-bars' when 'comedy' then 'comedy-clubs' when 'jazz' then 'jazz-clubs' when 'entertainment' then 'entertainment-centers' when 'experiences' then 'entertainment-centers'
 when 'event_venue' then 'event-venues' when 'beauty' then 'salons' when 'spa' then 'spas' when 'wellness' then 'wellness-centers' when 'culture' then 'cultural-centers' when 'shopping' then 'general-retail' when 'fitness' then 'fitness-studios'
 else null end$$;

revoke all on function public.black_pages_canonical_subcategory(text,text) from public,anon,authenticated;
revoke all on function public.black_pages_candidate_category(text) from public,anon,authenticated;
revoke all on function public.black_pages_candidate_subcategory(text) from public,anon,authenticated;

update public.black_pages_candidate_queue set subcategory=public.black_pages_candidate_subcategory(category),updated_at=now() where nullif(subcategory,'') is null and public.black_pages_candidate_subcategory(category) is not null;

insert into public.black_pages_source_enrichment_queue(source_type,source_id,business_name,city,state,category_slug,subcategory_slug,website_url,instagram_handle,google_place_id,issue_codes,priority_score,status,next_action_at)
select 'gt_venue',v.id,v.name,coalesce(c.city_name,initcap(replace(v.city_key,'-',' '))),c.state_code,public.black_pages_canonical_category(v.category_key),public.black_pages_canonical_subcategory(d.category,d.subcategory),nullif(btrim(v.website),''),nullif(btrim(v.instagram_handle),''),nullif(btrim(v.google_place_id),''),
array_remove(array[case when v.is_verified is not true then 'unverified_source' end,case when nullif(btrim(v.address),'') is null and (v.latitude is null or v.longitude is null) then 'missing_location' end,case when nullif(btrim(v.website),'') is null then 'missing_website' end,case when nullif(btrim(v.phone),'') is null and nullif(btrim(v.booking_link),'') is null and nullif(btrim(v.instagram_handle),'') is null then 'missing_contact' end]::text[],null),
1000+coalesce(ct.launch_priority,0)*100+case when nullif(btrim(v.address),'') is null and (v.latitude is null or v.longitude is null) then 500 else 0 end+case when v.is_verified is not true then 250 else 0 end,'pending',now()
from public.gt_venues v left join public.gt_cities c on c.city_key=v.city_key left join public.black_pages_city_targets ct on lower(ct.city)=lower(coalesce(c.city_name,initcap(replace(v.city_key,'-',' ')))) and coalesce(ct.state,'')=coalesce(c.state_code,'') left join public.black_pages_directory_v2 d on d.source_type='venue' and d.source_id=v.id
where coalesce(v.is_black_owned,false)=true and v.status='active' and not(v.is_verified is true and v.hero_image is not null and (nullif(btrim(v.address),'') is not null or (v.latitude is not null and v.longitude is not null)) and (nullif(btrim(v.website),'') is not null or nullif(btrim(v.phone),'') is not null or nullif(btrim(v.booking_link),'') is not null or nullif(btrim(v.instagram_handle),'') is not null))
on conflict(source_type,source_id) do update set business_name=excluded.business_name,city=excluded.city,state=excluded.state,category_slug=excluded.category_slug,subcategory_slug=excluded.subcategory_slug,website_url=excluded.website_url,instagram_handle=excluded.instagram_handle,google_place_id=excluded.google_place_id,issue_codes=excluded.issue_codes,priority_score=greatest(public.black_pages_source_enrichment_queue.priority_score,excluded.priority_score),updated_at=now();

create or replace view public.black_pages_coverage_matrix as
with target_cells as(
 select t.city,t.state,t.launch_priority,t.target_published_businesses city_launch_target,c.slug category_slug,c.name category_name,s.slug subcategory_slug,s.name subcategory_name,1::int target_count,greatest(coalesce(s.target_per_city,1),1)::int saturation_target
 from public.black_pages_city_targets t cross join public.black_pages_categories c join public.black_pages_subcategories s on s.category_slug=c.slug where t.is_active and c.active and s.active
), eligible_directory as(
 select d.* from public.black_pages_directory_v2 d where d.source_type='listing' or(d.source_type='venue' and exists(select 1 from public.gt_venues v where v.id=d.source_id and coalesce(v.is_black_owned,false)=true and v.status='active' and v.is_verified is true and v.hero_image is not null and(nullif(btrim(v.address),'') is not null or(v.latitude is not null and v.longitude is not null)) and(nullif(btrim(v.website),'') is not null or nullif(btrim(v.phone),'') is not null or nullif(btrim(v.booking_link),'') is not null or nullif(btrim(v.instagram_handle),'') is not null)))
), published as(
 select lower(city) city_key,coalesce(state,'') state,category category_slug,public.black_pages_canonical_subcategory(category,subcategory) subcategory_slug,count(*)::int published_count from eligible_directory where public.black_pages_canonical_subcategory(category,subcategory) is not null group by 1,2,3,4
), candidates as(
 select lower(city) city_key,coalesce(state,'') state,public.black_pages_candidate_category(category) category_slug,subcategory subcategory_slug,count(*) filter(where pipeline_stage not in('published','rejected','do_not_contact'))::int candidate_count from public.black_pages_candidate_queue where public.black_pages_candidate_category(category) is not null and nullif(subcategory,'') is not null group by 1,2,3,4
)
select tc.city,tc.state,tc.launch_priority,tc.category_slug,tc.category_name,tc.subcategory_slug,tc.subcategory_name,tc.target_count,coalesce(p.published_count,0)::int published_count,coalesce(q.candidate_count,0)::int candidate_count,greatest(tc.target_count-coalesce(p.published_count,0),0)::int gap_count,greatest(tc.target_count-coalesce(p.published_count,0)-coalesce(q.candidate_count,0),0)::int discovery_gap,
case when coalesce(p.published_count,0)>=tc.target_count then 'covered' when coalesce(q.candidate_count,0)>0 then 'candidate_found' else 'empty' end coverage_status,least(100.0,round(100.0*coalesce(p.published_count,0)/nullif(tc.target_count,0),1)) coverage_pct,
(tc.launch_priority*1000+case when coalesce(p.published_count,0)=0 then 500 else 0 end+case when coalesce(q.candidate_count,0)=0 then 250 else 0 end+least(tc.saturation_target,100))::int priority_score,tc.city_launch_target,tc.saturation_target
from target_cells tc left join published p on p.city_key=lower(tc.city) and p.state=tc.state and p.category_slug=tc.category_slug and p.subcategory_slug=tc.subcategory_slug left join candidates q on q.city_key=lower(tc.city) and q.state=tc.state and q.category_slug=tc.category_slug and q.subcategory_slug=tc.subcategory_slug;
revoke all on table public.black_pages_coverage_matrix from public,anon,authenticated;

create or replace view public.black_pages_coverage_city_summary as
select city,state,max(launch_priority)::int launch_priority,count(*)::int taxonomy_cells,count(*) filter(where coverage_status='covered')::int target_met_cells,count(*) filter(where coverage_status='empty')::int empty_cells,count(*) filter(where coverage_status='candidate_found')::int weak_cells,sum(target_count)::int target_business_slots,sum(published_count)::int published_business_slots,sum(candidate_count)::int candidate_slots,sum(gap_count)::int remaining_gap,round(100.0*count(*) filter(where coverage_status='covered')/nullif(count(*),0),1) average_coverage_pct,count(*) filter(where coverage_status='candidate_found')::int candidate_found_cells,max(city_launch_target)::int city_launch_target,round(100.0*count(*) filter(where coverage_status='covered')/nullif(count(*),0),1) taxonomy_coverage_pct
from public.black_pages_coverage_matrix group by city,state;
revoke all on table public.black_pages_coverage_city_summary from public,anon,authenticated;

create or replace function public.black_pages_refresh_gap_tasks() returns jsonb language plpgsql security definer set search_path=pg_catalog,public as $$
declare v_upserted int:=0;v_completed int:=0;v_reprioritized int:=0;
begin
 insert into public.black_pages_research_gap_tasks(city,state,category_slug,subcategory_slug,category_name,subcategory_name,target_count,published_count,candidate_count,gap_count,priority_score,query_text,status,last_refreshed_at,updated_at)
 select city,state,category_slug,subcategory_slug,category_name,subcategory_name,target_count,published_count,candidate_count,gap_count,priority_score,format('Find and verify Black-owned %s businesses in %s, %s',subcategory_name,city,state),case when gap_count>0 then 'pending' else 'complete' end,now(),now() from public.black_pages_coverage_matrix
 on conflict(city,state,category_slug,subcategory_slug) do update set category_name=excluded.category_name,subcategory_name=excluded.subcategory_name,target_count=excluded.target_count,published_count=excluded.published_count,candidate_count=excluded.candidate_count,gap_count=excluded.gap_count,priority_score=excluded.priority_score,query_text=excluded.query_text,status=case when excluded.gap_count=0 then 'complete' when public.black_pages_research_gap_tasks.status='paused' then 'paused' else 'pending' end,last_refreshed_at=now(),updated_at=now();get diagnostics v_upserted=row_count;
 update public.black_pages_research_gap_tasks set status='complete',updated_at=now(),last_refreshed_at=now() where gap_count=0 and status<>'complete';get diagnostics v_completed=row_count;
 with pressure as(select city,state,category_slug,max(priority_score)::int p,sum(gap_count)::int g from public.black_pages_coverage_matrix where gap_count>0 group by 1,2,3)
 update public.black_pages_candidate_queue q set priority_score=greatest(coalesce(q.priority_score,0),least(9999,1000+pressure.p/10+least(pressure.g,250))),next_action_at=case when q.pipeline_stage='research' then least(coalesce(q.next_action_at,now()),now()) else q.next_action_at end,updated_at=now() from pressure where lower(q.city)=lower(pressure.city) and coalesce(q.state,'')=pressure.state and public.black_pages_candidate_category(q.category)=pressure.category_slug and q.pipeline_stage='research';get diagnostics v_reprioritized=row_count;
 return jsonb_build_object('gap_tasks_refreshed',v_upserted,'tasks_completed',v_completed,'candidates_reprioritized',v_reprioritized,'refreshed_at',now());
end$$;
revoke all on function public.black_pages_refresh_gap_tasks() from public,anon,authenticated;

create or replace function public.black_pages_claim_source_enrichment_batch(p_limit int default 10,p_worker text default 'black-pages-enrichment-worker') returns jsonb language plpgsql security definer set search_path=pg_catalog,public as $$
declare v_rows jsonb;begin
 with claimed as(select id from public.black_pages_source_enrichment_queue where status in('pending','retry') and next_action_at<=now() and attempt_count<5 order by priority_score desc,next_action_at,created_at for update skip locked limit least(25,greatest(1,coalesce(p_limit,10)))),updated as(update public.black_pages_source_enrichment_queue q set status='processing',locked_by=p_worker,locked_at=now(),attempt_count=attempt_count+1,updated_at=now() from claimed c where q.id=c.id returning q.*)
 select coalesce(jsonb_agg(jsonb_build_object('id',id,'source_id',source_id,'business_name',business_name,'city',city,'state',state,'category_slug',category_slug,'subcategory_slug',subcategory_slug,'website_url',website_url,'instagram_handle',instagram_handle,'google_place_id',google_place_id,'issue_codes',issue_codes,'attempt_count',attempt_count) order by priority_score desc),'[]'::jsonb) into v_rows from updated;return jsonb_build_object('candidates',v_rows);end$$;
revoke all on function public.black_pages_claim_source_enrichment_batch(int,text) from public,anon,authenticated;

create or replace function public.black_pages_complete_source_enrichment(p_queue_id uuid,p_result jsonb,p_worker text default 'black-pages-enrichment-worker') returns jsonb language plpgsql security definer set search_path=pg_catalog,public as $$
declare v_source_id uuid;v_attempts int;v_address text;v_lat numeric;v_lng numeric;v_postal text;v_confidence text;v_has_location boolean:=false;v_status text;begin
 select source_id,attempt_count into v_source_id,v_attempts from public.black_pages_source_enrichment_queue where id=p_queue_id and locked_by=p_worker for update;if v_source_id is null then raise exception 'Enrichment queue item is not claimed by this worker';end if;
 v_address:=nullif(btrim(p_result->>'address'),'');v_postal:=nullif(btrim(p_result->>'postal_code'),'');v_confidence:=coalesce(nullif(p_result->>'confidence',''),'none');begin v_lat:=nullif(p_result->>'latitude','')::numeric;exception when others then v_lat:=null;end;begin v_lng:=nullif(p_result->>'longitude','')::numeric;exception when others then v_lng:=null;end;
 if v_confidence='high' and(v_address is not null or(v_lat is not null and v_lng is not null)) then update public.gt_venues set address=coalesce(nullif(btrim(address),''),v_address),latitude=coalesce(latitude,v_lat),longitude=coalesce(longitude,v_lng),enrichment_status='location_enriched',enrichment_source=coalesce(nullif(p_result->>'source',''),'black_pages_enrichment_worker'),enriched_at=now(),metadata=coalesce(metadata,'{}'::jsonb)||jsonb_strip_nulls(jsonb_build_object('black_pages_location_source_url',nullif(p_result->>'source_url',''),'black_pages_postal_code',v_postal,'black_pages_location_confidence',v_confidence)),updated_at=now() where id=v_source_id;end if;
 select(nullif(btrim(address),'') is not null or(latitude is not null and longitude is not null)) into v_has_location from public.gt_venues where id=v_source_id;v_status:=case when v_has_location then 'complete' when v_attempts>=2 then 'manual' else 'retry' end;
 update public.black_pages_source_enrichment_queue set status=v_status,result=p_result,locked_by=null,locked_at=null,next_action_at=case when v_status='retry' then now()+interval '2 hours' else next_action_at end,updated_at=now() where id=p_queue_id;return jsonb_build_object('ok',true,'status',v_status,'location_ready',v_has_location,'source_id',v_source_id);end$$;
revoke all on function public.black_pages_complete_source_enrichment(uuid,jsonb,text) from public,anon,authenticated;

create or replace function public.black_pages_staff_coverage_snapshot(p_city text default null,p_limit int default 1000) returns jsonb language plpgsql security definer set search_path=pg_catalog,public,auth as $$
declare v_role text:=coalesce(auth.jwt()->'app_metadata'->>'khg_role','');v_cities jsonb;v_cells jsonb;v_enrichment jsonb;v_gap_stats jsonb;begin
 if coalesce(auth.role(),'')<>'service_role' and v_role not in('owner','admin','editor') then raise exception 'Staff access required';end if;
 select coalesce(jsonb_agg(to_jsonb(x) order by x.launch_priority desc,x.city),'[]'::jsonb) into v_cities from public.black_pages_coverage_city_summary x;
 select coalesce(jsonb_agg(to_jsonb(x) order by x.priority_score desc,x.category_name,x.subcategory_name),'[]'::jsonb) into v_cells from(select * from public.black_pages_coverage_matrix where p_city is null or lower(city)=lower(p_city) order by priority_score desc,category_name,subcategory_name limit least(5000,greatest(1,coalesce(p_limit,1000))))x;
 select jsonb_build_object('total',count(*),'pending',count(*) filter(where status in('pending','retry')),'processing',count(*) filter(where status='processing'),'manual',count(*) filter(where status='manual'),'complete',count(*) filter(where status='complete'),'missing_location',count(*) filter(where 'missing_location'=any(issue_codes))) into v_enrichment from public.black_pages_source_enrichment_queue;
 select jsonb_build_object('total_gap_tasks',count(*),'open_gap_tasks',count(*) filter(where status in('pending','active')),'empty_subcategory_tasks',count(*) filter(where published_count=0 and gap_count>0),'discovery_gap',coalesce(sum(greatest(gap_count-candidate_count,0)) filter(where status in('pending','active')),0)) into v_gap_stats from public.black_pages_research_gap_tasks;
 return jsonb_build_object('cities',v_cities,'cells',v_cells,'enrichment',v_enrichment,'gap_tasks',v_gap_stats,'generated_at',now());end$$;
revoke all on function public.black_pages_staff_coverage_snapshot(text,int) from public,anon;grant execute on function public.black_pages_staff_coverage_snapshot(text,int) to authenticated;

create or replace function public.black_pages_dispatch_enrichment_worker(p_limit int default 25) returns bigint language plpgsql security definer set search_path=pg_catalog,public,net,vault as $$
declare v_token text;v_request_id bigint;begin select decrypted_secret into v_token from vault.decrypted_secrets where name='black_pages_research_worker_token' order by created_at desc limit 1;if nullif(v_token,'') is null then raise exception 'BLACK PAGES worker token missing';end if;select net.http_post(url:='https://dzlmtvodpyhetvektfuo.supabase.co/functions/v1/black-pages-enrichment-worker',headers:=jsonb_build_object('Content-Type','application/json','x-worker-token',v_token),body:=jsonb_build_object('limit',least(25,greatest(1,coalesce(p_limit,25))))) into v_request_id;return v_request_id;end$$;
revoke all on function public.black_pages_dispatch_enrichment_worker(int) from public,anon,authenticated;

select public.black_pages_refresh_gap_tasks();
do $$begin perform cron.unschedule('black-pages-gap-refresh');exception when others then null;end$$;
select cron.schedule('black-pages-gap-refresh','7 * * * *','select public.black_pages_refresh_gap_tasks();');
do $$begin perform cron.unschedule('black-pages-enrichment-worker');exception when others then null;end$$;
select cron.schedule('black-pages-enrichment-worker','*/10 * * * *','select public.black_pages_dispatch_enrichment_worker(25);');
