-- Internal dispatch helpers are not granted to client roles. They exist for cron/service orchestration only.
create or replace function public.black_pages_internal_dispatch_worker(p_worker text,p_jobs integer default 5,p_shards integer default 1)
returns jsonb language plpgsql security definer set search_path='pg_catalog','public','net','vault' as $$
declare v_jobs integer:=least(20,greatest(1,coalesce(p_jobs,5)));v_shards integer:=least(8,greatest(1,coalesce(p_shards,1)));
 v_token text;v_id bigint;v_ids jsonb:='[]'::jsonb;i integer;v_slug text;
begin
 v_slug:=case lower(btrim(coalesce(p_worker,''))) when 'regional-brw' then 'black-pages-regional-brw-worker' when 'growthzone' then 'black-pages-growthzone-worker' when 'deep-enrichment' then 'black-pages-deep-enrichment-worker' else null end;
 if v_slug is null then raise exception 'Unknown worker';end if;
 select decrypted_secret into v_token from vault.decrypted_secrets where name='black_pages_research_worker_token' order by created_at desc limit 1;
 if nullif(v_token,'') is null then raise exception 'BLACK PAGES worker token missing';end if;
 for i in 1..v_shards loop
   select net.http_post(url:='https://dzlmtvodpyhetvektfuo.supabase.co/functions/v1/'||v_slug,
     headers:=jsonb_build_object('Content-Type','application/json','x-worker-token',v_token),
     body:=case when p_worker='deep-enrichment' then jsonb_build_object('limit',v_jobs) else jsonb_build_object('jobs',v_jobs) end) into v_id;
   v_ids:=v_ids||jsonb_build_array(v_id);
 end loop;
 return jsonb_build_object('worker',p_worker,'shards',v_shards,'jobs_or_limit',v_jobs,'request_ids',v_ids);
end $$;
revoke all on function public.black_pages_internal_dispatch_worker(text,integer,integer) from public,anon,authenticated;
grant execute on function public.black_pages_internal_dispatch_worker(text,integer,integer) to service_role;
