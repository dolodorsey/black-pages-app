-- SavorBLK: verified Black-owned food/hospitality directory. Business profiles only; events are excluded by worker.
insert into public.black_pages_external_sources(source_key,source_name,adapter,base_url,ownership_signal,credential_secret_name,active,priority,notes) values
('savorblk_national','SavorBLK — Verified Black-Owned Food & Hospitality','savorblk_v1','https://www.savorblk.com/explore','black_business_directory',null,true,126,'Verified Black-owned restaurants/food/hospitality across 60+ cities. Worker accepts only /business/ profiles and rejects event/event-brand records.')
on conflict(source_key) do update set source_name=excluded.source_name,adapter=excluded.adapter,base_url=excluded.base_url,ownership_signal=excluded.ownership_signal,active=excluded.active,priority=excluded.priority,notes=excluded.notes,updated_at=now();

insert into public.black_pages_external_discovery_jobs(source_key,city,state,category_slug,page_offset,request_url,requested_count,status,attempt_count,updated_at) values
('savorblk_national','Atlanta','GA','food-beverage',0,'https://www.savorblk.com/city/atlanta',20,'pending',0,now()),
('savorblk_national','Houston','TX','food-beverage',0,'https://www.savorblk.com/city/houston',20,'pending',0,now())
on conflict(source_key,request_url) do update set status='pending',attempt_count=0,error_message=null,updated_at=now();

create or replace function public.black_pages_claim_savorblk_jobs(p_limit integer default 5)
returns jsonb language plpgsql security definer set search_path='pg_catalog','public' as $$
declare v_limit integer:=least(10,greatest(1,coalesce(p_limit,5)));v_jobs jsonb;
begin if auth.role()<>'service_role' then raise exception 'Service role required' using errcode='42501';end if;
 with due as(select j.id from public.black_pages_external_discovery_jobs j join public.black_pages_external_sources s using(source_key)
   where j.status in('pending','failed') and j.attempt_count<3 and s.active and s.adapter='savorblk_v1'
   order by j.created_at for update skip locked limit v_limit),claimed as(
   update public.black_pages_external_discovery_jobs j set status='processing',attempt_count=attempt_count+1,started_at=now(),updated_at=now()
   from due d where j.id=d.id returning j.*)
 select coalesce(jsonb_agg(to_jsonb(claimed)),'[]'::jsonb) into v_jobs from claimed;
 return jsonb_build_object('jobs',v_jobs,'claimed',jsonb_array_length(v_jobs));end $$;
revoke all on function public.black_pages_claim_savorblk_jobs(integer) from public,anon,authenticated;
grant execute on function public.black_pages_claim_savorblk_jobs(integer) to service_role;
