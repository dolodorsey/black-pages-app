-- Activate QA-passed source adapters and keep acquisition/enrichment running.

update public.black_pages_external_sources
set active=true,updated_at=now(),notes=coalesce(notes,'')||' GrowthZone v2 phone/address QA passed August 2026.'
where source_key in (
 'greater_washington_black_chamber','california_black_chamber','capital_black_chamber',
 'colorado_springs_black_chamber','broward_county_black_chamber','baton_rouge_black_chamber',
 'northern_virginia_black_chamber','virginia_black_business_directory'
);
update public.black_pages_external_sources set active=false,updated_at=now()
where source_key='greater_southwest_black_chamber';

create or replace function public.black_pages_internal_queue_adapter(p_adapter text)
returns jsonb language plpgsql security definer set search_path='pg_catalog','public' as $$
declare s record;v_created integer:=0;letter text;v_url text;
begin
 if p_adapter not in('regional_brw_v2','growthzone_v2') then raise exception 'Unsupported adapter';end if;
 for s in select * from public.black_pages_external_sources where active and adapter=p_adapter order by priority desc loop
   if p_adapter='regional_brw_v2' then
     insert into public.black_pages_external_discovery_jobs(source_key,city,state,category_slug,page_offset,request_url,requested_count,status,attempt_count,error_message,started_at,completed_at,result_count,updated_at)
     values(s.source_key,null,null,null,0,s.base_url,100,'pending',0,null,null,null,0,now())
     on conflict(source_key,request_url) do update set status='pending',attempt_count=0,error_message=null,started_at=null,completed_at=null,result_count=0,updated_at=now();
     v_created:=v_created+1;
   else
     foreach letter in array array['A','B','C','D','E','F','G','H','I','J','K','L','M','N','O','P','Q','R','S','T','U','V','W','X','Y','Z'] loop
       if s.base_url like '%FindStartsWith?term=%' then v_url:=regexp_replace(s.base_url,'term=.*$','term='||letter);
       else v_url:=rtrim(s.base_url,'/')||'/FindStartsWith?term='||letter; end if;
       insert into public.black_pages_external_discovery_jobs(source_key,city,state,category_slug,page_offset,request_url,requested_count,status,attempt_count,error_message,started_at,completed_at,result_count,updated_at)
       values(s.source_key,null,null,null,ascii(letter)-64,v_url,100,'pending',0,null,null,null,0,now())
       on conflict(source_key,request_url) do update set status='pending',attempt_count=0,error_message=null,started_at=null,completed_at=null,result_count=0,updated_at=now();
       v_created:=v_created+1;
     end loop;
   end if;
 end loop;
 return jsonb_build_object('adapter',p_adapter,'jobs_queued',v_created);
end $$;
revoke all on function public.black_pages_internal_queue_adapter(text) from public,anon,authenticated;
grant execute on function public.black_pages_internal_queue_adapter(text) to service_role;

-- Remove prior versions if this migration is replayed.
do $block$ declare r record; begin
 for r in select jobid from cron.job where jobname in (
  'black-pages-regional-brw-refresh','black-pages-regional-brw-drain',
  'black-pages-growthzone-refresh','black-pages-growthzone-drain','black-pages-deep-enrichment-burst')
 loop perform cron.unschedule(r.jobid); end loop;
end $block$;

select cron.schedule('black-pages-regional-brw-refresh','12 4 * * 1',
 $$select public.black_pages_internal_queue_adapter('regional_brw_v2');$$);
select cron.schedule('black-pages-regional-brw-drain','*/10 * * * *',
 $$select public.black_pages_internal_dispatch_worker('regional-brw',5,1);$$);
select cron.schedule('black-pages-growthzone-refresh','22 4 * * 1',
 $$select public.black_pages_internal_queue_adapter('growthzone_v2');$$);
select cron.schedule('black-pages-growthzone-drain','*/5 * * * *',
 $$select public.black_pages_internal_dispatch_worker('growthzone',10,1);$$);
select cron.schedule('black-pages-deep-enrichment-burst','*/10 * * * *',
 $$select public.black_pages_internal_dispatch_worker('deep-enrichment',50,4);$$);
