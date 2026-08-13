-- QA activation after live A-shard tests.
-- Oklahoma City returned 404 for the attempted GrowthZone shard route, so keep it staged.
update public.black_pages_external_sources set active=false,updated_at=now(),notes=coalesce(notes,'')||' Automated A-shard QA returned HTTP 404; staged pending corrected route.' where source_key='oklahoma_city_black_chamber';
update public.black_pages_external_sources set active=true,updated_at=now(),notes=coalesce(notes,'')||' Automated A-shard QA passed with clean structured records.' where source_key in('central_florida_african_american_chamber','san_joaquin_black_owned_directory','nashville_black_chamber');

-- Queue the remaining alphabet shards now for sources that passed live QA.
with letters as(select chr(g) letter from generate_series(ascii('B'),ascii('Z')) g),sources as(
 select * from public.black_pages_external_sources where source_key in('central_florida_african_american_chamber','san_joaquin_black_owned_directory','nashville_black_chamber') and active
)
insert into public.black_pages_external_discovery_jobs(source_key,city,state,category_slug,page_offset,request_url,requested_count,status,attempt_count,error_message,started_at,completed_at,result_count,updated_at)
select s.source_key,null,null,null,ascii(l.letter)-64,regexp_replace(s.base_url,'term=.*$','term='||l.letter),100,'pending',0,null,null,null,0,now()
from sources s cross join letters l
on conflict(source_key,request_url) do update set status='pending',attempt_count=0,error_message=null,started_at=null,completed_at=null,result_count=0,updated_at=now();
