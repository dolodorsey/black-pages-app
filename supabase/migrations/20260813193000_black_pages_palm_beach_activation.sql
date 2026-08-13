-- Palm Beach uses the same GrowthZone structure already supported by the hardened worker.
-- Membership remains low-trust ownership evidence and is routed through corroboration.
update public.black_pages_external_sources set active=true,updated_at=now(),notes=coalesce(notes,'')||' GrowthZone structure QA passed; membership requires corroboration.' where source_key='palm_beach_black_chamber';
with letters as(select chr(x) letter,x-64 offset_no from generate_series(65,90)x)
insert into public.black_pages_external_discovery_jobs(source_key,city,state,category_slug,page_offset,request_url,requested_count,status,attempt_count,error_message,started_at,completed_at,result_count,updated_at)
select 'palm_beach_black_chamber',null,null,null,offset_no,'https://business.blackchamberpbc.com/activememberdirectory/FindStartsWith?term='||letter,100,'pending',0,null,null,null,0,now() from letters
on conflict(source_key,request_url) do update set status='pending',attempt_count=0,error_message=null,started_at=null,completed_at=null,result_count=0,updated_at=now();