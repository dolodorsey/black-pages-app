-- Dispatch and refresh orchestration for high-trust certified / curated source families.
create or replace function public.black_pages_internal_dispatch_worker(p_worker text,p_jobs integer default 5,p_shards integer default 1)
returns jsonb language plpgsql security definer set search_path='pg_catalog','public','net','vault' as $$
declare v_worker text:=lower(btrim(coalesce(p_worker,'')));v_jobs integer;v_shards integer:=least(8,greatest(1,coalesce(p_shards,1)));
 v_token text;v_id bigint;v_ids jsonb:='[]'::jsonb;i integer;v_slug text;
begin
 v_jobs:=case when v_worker='deep-enrichment' then least(100,greatest(1,coalesce(p_jobs,50))) else least(20,greatest(1,coalesce(p_jobs,5))) end;
 v_slug:=case v_worker when 'regional-brw' then 'black-pages-regional-brw-worker' when 'growthzone' then 'black-pages-growthzone-worker'
   when 'deep-enrichment' then 'black-pages-deep-enrichment-worker' when 'trusted-source' then 'black-pages-trusted-source-worker' else null end;
 if v_slug is null then raise exception 'Unknown worker';end if;
 select decrypted_secret into v_token from vault.decrypted_secrets where name='black_pages_research_worker_token' order by created_at desc limit 1;
 if nullif(v_token,'') is null then raise exception 'BLACK PAGES worker token missing';end if;
 for i in 1..v_shards loop
   select net.http_post(url:='https://dzlmtvodpyhetvektfuo.supabase.co/functions/v1/'||v_slug,
     headers:=jsonb_build_object('Content-Type','application/json','x-worker-token',v_token),
     body:=case when v_worker='deep-enrichment' then jsonb_build_object('limit',v_jobs) else jsonb_build_object('jobs',v_jobs) end) into v_id;
   v_ids:=v_ids||jsonb_build_array(v_id);
 end loop;
 return jsonb_build_object('worker',v_worker,'shards',v_shards,'jobs_or_limit',v_jobs,
   'max_candidates',case when v_worker='deep-enrichment' then v_jobs*v_shards else null end,'request_ids',v_ids);
end $$;
revoke all on function public.black_pages_internal_dispatch_worker(text,integer,integer) from public,anon,authenticated;
grant execute on function public.black_pages_internal_dispatch_worker(text,integer,integer) to service_role;

create or replace function public.black_pages_refresh_trusted_sources()
returns jsonb language plpgsql security definer set search_path='pg_catalog','public' as $$
declare v_count integer:=0;
begin
 update public.black_pages_external_discovery_jobs j set status='pending',attempt_count=0,error_message=null,started_at=null,completed_at=null,updated_at=now()
 from public.black_pages_external_sources s where s.source_key=j.source_key and s.active and s.adapter='trusted_black_source_v1';
 get diagnostics v_count=row_count;
 return jsonb_build_object('jobs_reset',v_count);
end $$;
revoke all on function public.black_pages_refresh_trusted_sources() from public,anon,authenticated;
grant execute on function public.black_pages_refresh_trusted_sources() to service_role;
