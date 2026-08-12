-- Keep Black Restaurant Week out of the generic external worker and give it a source-specific claim lane.
create or replace function public.black_pages_claim_external_jobs(p_limit integer default 10)
returns jsonb language plpgsql security definer set search_path='pg_catalog','public' as $$
declare v_limit integer:=least(20,greatest(1,coalesce(p_limit,10)));v_jobs jsonb;
begin
  if auth.role()<>'service_role' then raise exception 'Service role required' using errcode='42501';end if;
  with due as(
    select j.id from public.black_pages_external_discovery_jobs j join public.black_pages_external_sources s using(source_key)
    where j.status in('pending','failed') and j.attempt_count<3 and s.active and s.adapter<>'black_restaurant_week'
    order by s.priority desc,j.created_at for update skip locked limit v_limit
  ),claimed as(
    update public.black_pages_external_discovery_jobs j set status='processing',attempt_count=attempt_count+1,started_at=now(),updated_at=now()
    from due d where j.id=d.id returning j.*
  )select coalesce(jsonb_agg(to_jsonb(claimed)),'[]'::jsonb) into v_jobs from claimed;
  return jsonb_build_object('jobs',v_jobs,'claimed',jsonb_array_length(v_jobs));
end $$;
revoke all on function public.black_pages_claim_external_jobs(integer) from public,anon,authenticated;
grant execute on function public.black_pages_claim_external_jobs(integer) to service_role;

create or replace function public.black_pages_claim_external_source_jobs(p_source_key text,p_limit integer default 5)
returns jsonb language plpgsql security definer set search_path='pg_catalog','public' as $$
declare v_limit integer:=least(10,greatest(1,coalesce(p_limit,5)));v_jobs jsonb;
begin
  if auth.role()<>'service_role' then raise exception 'Service role required' using errcode='42501';end if;
  with due as(
    select j.id from public.black_pages_external_discovery_jobs j join public.black_pages_external_sources s using(source_key)
    where j.source_key=p_source_key and j.status in('pending','failed') and j.attempt_count<3 and s.active
    order by j.created_at for update skip locked limit v_limit
  ),claimed as(
    update public.black_pages_external_discovery_jobs j set status='processing',attempt_count=attempt_count+1,started_at=now(),updated_at=now()
    from due d where j.id=d.id returning j.*
  )select coalesce(jsonb_agg(to_jsonb(claimed)),'[]'::jsonb) into v_jobs from claimed;
  return jsonb_build_object('jobs',v_jobs,'claimed',jsonb_array_length(v_jobs));
end $$;
revoke all on function public.black_pages_claim_external_source_jobs(text,integer) from public,anon,authenticated;
grant execute on function public.black_pages_claim_external_source_jobs(text,integer) to service_role;

create or replace function public.black_pages_dispatch_brw_worker(p_jobs integer default 3)
returns bigint language plpgsql security definer set search_path='pg_catalog','public','net','vault','auth' as $$
declare v_role text:=coalesce(auth.jwt()->'app_metadata'->>'khg_role','');v_jobs integer:=least(10,greatest(1,coalesce(p_jobs,3)));v_token text;v_request_id bigint;
begin
  if coalesce(auth.role(),'')<>'service_role' and v_role not in('owner','admin','editor') then raise exception 'Staff access required' using errcode='42501';end if;
  select decrypted_secret into v_token from vault.decrypted_secrets where name='black_pages_research_worker_token' order by created_at desc limit 1;
  if nullif(v_token,'') is null then raise exception 'BLACK PAGES worker token missing';end if;
  select net.http_post(url:='https://dzlmtvodpyhetvektfuo.supabase.co/functions/v1/black-pages-brw-worker',headers:=jsonb_build_object('Content-Type','application/json','x-worker-token',v_token),body:=jsonb_build_object('jobs',v_jobs)) into v_request_id;
  return v_request_id;
end $$;
revoke all on function public.black_pages_dispatch_brw_worker(integer) from public,anon,authenticated;
grant execute on function public.black_pages_dispatch_brw_worker(integer) to authenticated,service_role;
