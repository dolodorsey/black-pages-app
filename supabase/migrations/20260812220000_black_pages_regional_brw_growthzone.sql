-- THE BLACK PAGES: regional Black Restaurant Week + dedicated GrowthZone source lanes.
-- Discovery only. Nothing in this migration publishes a directory listing.

update public.black_pages_external_sources
set adapter='regional_brw_v2',active=true,updated_at=now()
where source_key in ('memphis_black_restaurant_week','long_beach_black_restaurant_week','san_antonio_black_restaurant_week');

update public.black_pages_external_sources
set adapter='growthzone_v2',updated_at=now()
where source_key in ('greater_washington_black_chamber','california_black_chamber','capital_black_chamber');

insert into public.black_pages_external_sources(source_key,source_name,adapter,base_url,ownership_signal,credential_secret_name,active,priority,notes) values
('colorado_springs_black_chamber','Colorado Springs Black Chamber','growthzone_v2','https://business.cosblackchamber.com/member-directory/FindStartsWith?term=%23%21','black_chamber_directory',null,false,104,'Public GrowthZone directory. Activate after parser QA.'),
('broward_county_black_chamber','Broward County Black Chamber of Commerce','growthzone_v2','https://members.browardcountyblackchamberofcommerce.com/member-directory/FindStartsWith?term=%23%21','black_chamber_directory',null,false,104,'Public GrowthZone directory. Activate after parser QA.'),
('baton_rouge_black_chamber','Baton Rouge Metropolitan Black Chamber of Commerce','growthzone_v2','https://business.brmetrocc.org/directory/FindStartsWith?term=%23%21','black_chamber_directory',null,false,104,'Public GrowthZone directory. Activate after parser QA.'),
('northern_virginia_black_chamber','Northern Virginia Black Chamber of Commerce','growthzone_v2','https://business.northernvirginiabcc.org/directory/FindStartsWith?term=%23%21','black_chamber_directory',null,false,106,'Public GrowthZone directory. Activate after parser QA.')
on conflict(source_key) do update set source_name=excluded.source_name,adapter=excluded.adapter,base_url=excluded.base_url,
 ownership_signal=excluded.ownership_signal,priority=excluded.priority,notes=excluded.notes,updated_at=now();

-- The generic worker should never steal jobs owned by source-specific parsers.
create or replace function public.black_pages_claim_external_jobs(p_limit integer default 10)
returns jsonb language plpgsql security definer set search_path='pg_catalog','public' as $$
declare v_limit integer:=least(20,greatest(1,coalesce(p_limit,10))); v_jobs jsonb;
begin
 if auth.role()<>'service_role' then raise exception 'Service role required' using errcode='42501'; end if;
 with due as (
   select j.id from public.black_pages_external_discovery_jobs j
   join public.black_pages_external_sources s using(source_key)
   where j.status in ('pending','failed') and j.attempt_count<3 and s.active
     and s.adapter not in ('black_restaurant_week','regional_brw_v2','growthzone_v2')
   order by s.priority desc,j.created_at for update skip locked limit v_limit
 ), claimed as (
   update public.black_pages_external_discovery_jobs j
   set status='processing',attempt_count=attempt_count+1,started_at=now(),updated_at=now()
   from due d where j.id=d.id returning j.*
 ) select coalesce(jsonb_agg(to_jsonb(claimed)),'[]'::jsonb) into v_jobs from claimed;
 return jsonb_build_object('jobs',v_jobs,'claimed',jsonb_array_length(v_jobs));
end $$;
revoke all on function public.black_pages_claim_external_jobs(integer) from public,anon,authenticated;
grant execute on function public.black_pages_claim_external_jobs(integer) to service_role;

create or replace function public.black_pages_claim_adapter_jobs(p_adapter text,p_limit integer default 10)
returns jsonb language plpgsql security definer set search_path='pg_catalog','public' as $$
declare v_limit integer:=least(20,greatest(1,coalesce(p_limit,10))); v_jobs jsonb;
begin
 if auth.role()<>'service_role' then raise exception 'Service role required' using errcode='42501'; end if;
 with due as (
   select j.id from public.black_pages_external_discovery_jobs j
   join public.black_pages_external_sources s using(source_key)
   where j.status in ('pending','failed') and j.attempt_count<3 and s.active and s.adapter=p_adapter
   order by s.priority desc,j.created_at for update skip locked limit v_limit
 ), claimed as (
   update public.black_pages_external_discovery_jobs j
   set status='processing',attempt_count=attempt_count+1,started_at=now(),updated_at=now()
   from due d where j.id=d.id returning j.*
 ) select coalesce(jsonb_agg(to_jsonb(claimed)),'[]'::jsonb) into v_jobs from claimed;
 return jsonb_build_object('jobs',v_jobs,'claimed',jsonb_array_length(v_jobs));
end $$;
revoke all on function public.black_pages_claim_adapter_jobs(text,integer) from public,anon,authenticated;
grant execute on function public.black_pages_claim_adapter_jobs(text,integer) to service_role;

create or replace function public.black_pages_queue_source_scan(p_source_key text,p_pages integer default 1)
returns jsonb language plpgsql security definer set search_path='pg_catalog','public','auth' as $$
declare v_role text:=coalesce(auth.jwt()->'app_metadata'->>'khg_role','');v_source public.black_pages_external_sources%rowtype;
 v_pages integer:=least(100,greatest(1,coalesce(p_pages,1)));v_page integer;v_url text;v_created integer:=0;
begin
 if coalesce(auth.role(),'')<>'service_role' and v_role not in('owner','admin','editor') then raise exception 'Staff access required' using errcode='42501'; end if;
 select * into v_source from public.black_pages_external_sources where source_key=p_source_key;
 if not found then raise exception 'Unknown source';end if; if not v_source.active then raise exception 'Source is not active';end if;
 for v_page in 1..v_pages loop
   if v_source.adapter='black_restaurant_week' then
     v_url:=case when v_page=1 then v_source.base_url else rtrim(v_source.base_url,'/')||'/page/'||v_page::text||'/' end;
   elsif v_source.adapter in ('regional_brw_v2','growthzone_v2') then
     v_url:=v_source.base_url; if v_page>1 then exit; end if;
   else raise exception 'Bulk source scan not configured for adapter %',v_source.adapter; end if;
   insert into public.black_pages_external_discovery_jobs(source_key,city,state,category_slug,page_offset,request_url,requested_count,requested_by,status,attempt_count,error_message,updated_at)
   values(v_source.source_key,null,null,null,(v_page-1)*50,v_url,case when v_source.adapter='growthzone_v2' then 500 else 100 end,auth.uid(),'pending',0,null,now())
   on conflict(source_key,request_url) do update set status='pending',attempt_count=0,error_message=null,updated_at=now();
   v_created:=v_created+1;
 end loop;
 return jsonb_build_object('source',v_source.source_key,'jobs_queued',v_created,'pages',v_created);
end $$;
revoke all on function public.black_pages_queue_source_scan(text,integer) from public,anon,authenticated;
grant execute on function public.black_pages_queue_source_scan(text,integer) to authenticated,service_role;

create or replace function public.black_pages_dispatch_adapter_worker(p_worker text,p_jobs integer default 5)
returns jsonb language plpgsql security definer set search_path='pg_catalog','public','net','vault','auth' as $$
declare v_role text:=coalesce(auth.jwt()->'app_metadata'->>'khg_role','');v_jobs integer:=least(20,greatest(1,coalesce(p_jobs,5)));
 v_token text;v_id bigint;v_worker text:=lower(btrim(coalesce(p_worker,'')));
begin
 if coalesce(auth.role(),'')<>'service_role' and v_role not in('owner','admin','editor') then raise exception 'Staff access required' using errcode='42501';end if;
 if v_worker not in ('regional-brw','growthzone') then raise exception 'Unknown adapter worker';end if;
 select decrypted_secret into v_token from vault.decrypted_secrets where name='black_pages_research_worker_token' order by created_at desc limit 1;
 if nullif(v_token,'') is null then raise exception 'BLACK PAGES worker token missing';end if;
 select net.http_post(url:='https://dzlmtvodpyhetvektfuo.supabase.co/functions/v1/'||case when v_worker='regional-brw' then 'black-pages-regional-brw-worker' else 'black-pages-growthzone-worker' end,
 headers:=jsonb_build_object('Content-Type','application/json','x-worker-token',v_token),body:=jsonb_build_object('jobs',v_jobs)) into v_id;
 return jsonb_build_object('request_id',v_id,'jobs_requested',v_jobs,'worker',v_worker);
end $$;
revoke all on function public.black_pages_dispatch_adapter_worker(text,integer) from public,anon,authenticated;
grant execute on function public.black_pages_dispatch_adapter_worker(text,integer) to authenticated,service_role;
