-- Dispatch the private BLACK PAGES research worker every fifteen minutes.
create extension if not exists pg_net;
create extension if not exists pg_cron;

create or replace function public.black_pages_dispatch_research_worker(p_limit integer default 10)
returns bigint
language plpgsql
security definer
set search_path='pg_catalog','public','net','vault'
as $function$
declare v_token text; v_request_id bigint;
begin
  select decrypted_secret into v_token from vault.decrypted_secrets
  where name='black_pages_research_worker_token' order by created_at desc limit 1;
  if nullif(v_token,'') is null then raise exception 'BLACK PAGES worker token missing'; end if;

  select net.http_post(
    url:='https://dzlmtvodpyhetvektfuo.supabase.co/functions/v1/black-pages-research-worker',
    headers:=jsonb_build_object('Content-Type','application/json','x-worker-token',v_token),
    body:=jsonb_build_object('limit',least(25,greatest(1,coalesce(p_limit,10))))
  ) into v_request_id;
  return v_request_id;
end;
$function$;

revoke all on function public.black_pages_dispatch_research_worker(integer) from public,anon,authenticated;
grant execute on function public.black_pages_dispatch_research_worker(integer) to service_role;

do $block$
begin
  if not exists(select 1 from cron.job where jobname='black-pages-research-worker') then
    perform cron.schedule('black-pages-research-worker','*/15 * * * *',
      $cmd$select public.black_pages_dispatch_research_worker(10);$cmd$);
  end if;
end
$block$;
