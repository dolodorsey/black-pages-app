-- Protected dispatcher for external discovery workers.
create or replace function public.black_pages_dispatch_external_worker(p_jobs integer default 5)
returns jsonb
language plpgsql security definer set search_path='pg_catalog','public','net','vault','auth' as $$
declare
  v_role text:=coalesce(auth.jwt()->'app_metadata'->>'khg_role','');
  v_jobs integer:=least(20,greatest(1,coalesce(p_jobs,5)));
  v_token text;v_id bigint;
begin
  if coalesce(auth.role(),'')<>'service_role' and v_role not in('owner','admin','editor') then
    raise exception 'Staff access required' using errcode='42501';
  end if;
  select decrypted_secret into v_token from vault.decrypted_secrets where name='black_pages_research_worker_token' order by created_at desc limit 1;
  if nullif(v_token,'') is null then raise exception 'BLACK PAGES worker token missing';end if;
  select net.http_post(
    url:='https://dzlmtvodpyhetvektfuo.supabase.co/functions/v1/black-pages-external-discovery-worker',
    headers:=jsonb_build_object('Content-Type','application/json','x-worker-token',v_token),
    body:=jsonb_build_object('jobs',v_jobs)
  ) into v_id;
  return jsonb_build_object('request_id',v_id,'jobs_requested',v_jobs);
end $$;
revoke all on function public.black_pages_dispatch_external_worker(integer) from public,anon,authenticated;
grant execute on function public.black_pages_dispatch_external_worker(integer) to authenticated,service_role;
