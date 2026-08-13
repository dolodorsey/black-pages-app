-- High-trust source families beyond BRW and Black Chambers.
-- Signals are intentionally distinct: certified Black ownership > curated Black guide > minority cross-reference.

insert into public.black_pages_external_sources(source_key,source_name,adapter,base_url,ownership_signal,credential_secret_name,active,priority,notes) values
('byblack_certified_atlanta','ByBlack Certified — Atlanta','trusted_black_source_v1','https://byblack.us/search/Atlanta--GA/businesses/?is_certified=true','certified_black_business',null,true,132,'ByBlack certified search. Certification is Black-owned/operated evidence; human review remains required before publication.'),
('discover_atlanta_black_restaurants','Discover Atlanta — Black-Owned Restaurants','trusted_black_source_v1','https://discoveratlanta.com/stories/eat/atlantas-favorite-black-owned-restaurants/','curated_black_business_guide',null,true,108,'Current destination-marketing guide explicitly describing listed restaurants as Black-owned. Curated evidence; human review required.'),
('atlanta_occ_minority_vendor_reference','City of Atlanta OCC Certified Firm Database','cross_evidence_reference','https://www.atlantaga.gov/government/departments/finance/office-of-contract-compliance','minority_certification_reference',null,false,45,'Cross-reference only. Minority certification is not equivalent to Black ownership and must never be used alone to approve ownership.'),
('georgia_mbe_certification_reference','Georgia Minority-Owned Business Certification','cross_evidence_reference','https://georgia.org/business-support/small-business/minority-owned-small-businesses','minority_certification_reference',null,false,45,'Cross-reference only. Georgia MBE recognizes multiple minority groups; row-level Black ownership requires additional evidence.'),
('travel_noire_atlanta_black_restaurants','Travel Noire — Atlanta Black-Owned Restaurants','trusted_black_source_v1','https://travelnoire.com/black-owned-restaurants-atlanta','curated_black_business_guide',null,false,60,'Secondary curated Black-owned restaurant guide; staged until parser QA.')
on conflict(source_key) do update set source_name=excluded.source_name,adapter=excluded.adapter,base_url=excluded.base_url,
  ownership_signal=excluded.ownership_signal,credential_secret_name=excluded.credential_secret_name,
  active=excluded.active,priority=excluded.priority,notes=excluded.notes,updated_at=now();

-- Certified ByBlack discovery is split across broad category searches so a single first page does not cap the source at 15 records.
with queries(label,url) as(values
  ('business-services','https://byblack.us/search/Atlanta--GA/businesses/?is_certified=true&neighbors=Business+Services'),
  ('consulting','https://byblack.us/search/Atlanta--GA/businesses/?is_certified=true&neighbors=Consulting'),
  ('marketing','https://byblack.us/search/Atlanta--GA/businesses/?is_certified=true&neighbors=Marketing'),
  ('retail','https://byblack.us/search/Atlanta--GA/businesses/?is_certified=true&neighbors=Retail'),
  ('food-beverage','https://byblack.us/search/Atlanta--GA/businesses/?is_certified=true&neighbors=Food+%26+Beverage'),
  ('health-wellness','https://byblack.us/search/Atlanta--GA/businesses/?is_certified=true&neighbors=Health+%26+Wellness'),
  ('real-estate','https://byblack.us/search/Atlanta--GA/businesses/?is_certified=true&neighbors=Real+Estate'),
  ('technology','https://byblack.us/search/Atlanta--GA/businesses/?is_certified=true&neighbors=Technology'),
  ('transportation','https://byblack.us/search/Atlanta--GA/businesses/?is_certified=true&neighbors=Transportation'),
  ('training','https://byblack.us/search/Atlanta--GA/businesses/?is_certified=true&neighbors=Professional+Training+%26+Coaching'),
  ('branding','https://byblack.us/search/Atlanta--GA/businesses/?is_certified=true&neighbors=Branding'),
  ('beauty','https://byblack.us/search/Atlanta--GA/businesses/?is_certified=true&neighbors=Beauty')
)
insert into public.black_pages_external_discovery_jobs(source_key,city,state,category_slug,page_offset,request_url,requested_count,status,attempt_count,updated_at)
select 'byblack_certified_atlanta','Atlanta','GA',null,0,url,15,'pending',0,now() from queries
on conflict(source_key,request_url) do update set status='pending',attempt_count=0,error_message=null,updated_at=now();

insert into public.black_pages_external_discovery_jobs(source_key,city,state,category_slug,page_offset,request_url,requested_count,status,attempt_count,updated_at)
values('discover_atlanta_black_restaurants','Atlanta','GA','food-beverage',0,'https://discoveratlanta.com/stories/eat/atlantas-favorite-black-owned-restaurants/',100,'pending',0,now())
on conflict(source_key,request_url) do update set status='pending',attempt_count=0,error_message=null,updated_at=now();

create or replace function public.black_pages_claim_trusted_source_jobs(p_limit integer default 10)
returns jsonb language plpgsql security definer set search_path='pg_catalog','public' as $$
declare v_limit integer:=least(20,greatest(1,coalesce(p_limit,10)));v_jobs jsonb;
begin
 if auth.role()<>'service_role' then raise exception 'Service role required' using errcode='42501';end if;
 with due as(
   select j.id from public.black_pages_external_discovery_jobs j join public.black_pages_external_sources s using(source_key)
   where j.status in('pending','failed') and j.attempt_count<3 and s.active and s.adapter='trusted_black_source_v1'
   order by s.priority desc,j.created_at for update skip locked limit v_limit
 ),claimed as(
   update public.black_pages_external_discovery_jobs j set status='processing',attempt_count=attempt_count+1,started_at=now(),updated_at=now()
   from due d where j.id=d.id returning j.*
 )select coalesce(jsonb_agg(to_jsonb(claimed)),'[]'::jsonb) into v_jobs from claimed;
 return jsonb_build_object('jobs',v_jobs,'claimed',jsonb_array_length(v_jobs));
end $$;
revoke all on function public.black_pages_claim_trusted_source_jobs(integer) from public,anon,authenticated;
grant execute on function public.black_pages_claim_trusted_source_jobs(integer) to service_role;
