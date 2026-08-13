-- Record actual source-access QA. Keep valuable blocked/client-rendered sources registered but inactive for automated crawling.
update public.black_pages_external_sources set active=false,updated_at=now(),notes=notes||' Automated QA: source does not expose parseable business records to the Supabase worker; retain as reference/staged source.' where source_key in('byblack_certified_atlanta','savorblk_national');
update public.black_pages_external_sources set active=false,updated_at=now(),notes=notes||' Automated QA: source returns HTTP 403 to the Supabase worker; retain as manual/reference source.' where source_key='discover_atlanta_black_restaurants';
update public.black_pages_external_discovery_jobs set status='blocked',updated_at=now(),error_message=coalesce(error_message,'source access/parser QA did not pass') where source_key in('byblack_certified_atlanta','savorblk_national','discover_atlanta_black_restaurants');

insert into public.black_pages_external_sources(source_key,source_name,adapter,base_url,ownership_signal,credential_secret_name,active,priority,notes) values
('atlanta_eats_black_restaurants','Atlanta Eats — 50 Black-Owned Restaurants','trusted_black_source_v1','https://www.atlantaeats.com/blog/50-black-owned-restaurants-in-atlanta/','curated_black_business_guide',null,true,109,'Current Atlanta Eats editorial list explicitly identifying 50 Black-owned restaurants; human ownership review still required.')
on conflict(source_key) do update set source_name=excluded.source_name,adapter=excluded.adapter,base_url=excluded.base_url,ownership_signal=excluded.ownership_signal,active=true,priority=excluded.priority,notes=excluded.notes,updated_at=now();
insert into public.black_pages_external_discovery_jobs(source_key,city,state,category_slug,page_offset,request_url,requested_count,status,attempt_count,updated_at)
values('atlanta_eats_black_restaurants','Atlanta','GA','food-beverage',0,'https://www.atlantaeats.com/blog/50-black-owned-restaurants-in-atlanta/',60,'pending',0,now())
on conflict(source_key,request_url) do update set status='pending',attempt_count=0,error_message=null,updated_at=now();
