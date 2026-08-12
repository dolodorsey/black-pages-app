-- Keep the national Black Restaurant Week feed fresh and drain its page queue at a polite rate.
create or replace function public.black_pages_queue_brw_refresh_internal(p_pages integer default 73)
returns integer
language plpgsql security definer set search_path='pg_catalog','public' as $$
declare v_pages integer:=least(100,greatest(1,coalesce(p_pages,73)));v_page integer;v_url text;v_count integer:=0;
begin
  if not exists(select 1 from public.black_pages_external_sources where source_key='black_restaurant_week_national' and active) then return 0;end if;
  for v_page in 1..v_pages loop
    v_url:=case when v_page=1 then 'https://blackrestaurantweeks.com/brw-campaigns/' else 'https://blackrestaurantweeks.com/brw-campaigns/page/'||v_page::text||'/' end;
    insert into public.black_pages_external_discovery_jobs(source_key,city,state,category_slug,page_offset,request_url,requested_count,requested_by,status,attempt_count,error_message,started_at,completed_at,updated_at)
    values('black_restaurant_week_national',null,null,'food-beverage',(v_page-1)*10,v_url,10,null,'pending',0,null,null,null,now())
    on conflict(source_key,request_url) do update set status='pending',attempt_count=0,error_message=null,started_at=null,completed_at=null,updated_at=now();
    v_count:=v_count+1;
  end loop;
  return v_count;
end $$;
revoke all on function public.black_pages_queue_brw_refresh_internal(integer) from public,anon,authenticated;
grant execute on function public.black_pages_queue_brw_refresh_internal(integer) to service_role;

create or replace function public.black_pages_brw_cron_tick()
returns bigint
language plpgsql security definer set search_path='pg_catalog','public','net','vault' as $$
declare v_token text;v_request_id bigint;
begin
  if not exists(select 1 from public.black_pages_external_discovery_jobs where source_key='black_restaurant_week_national' and status in('pending','failed') and attempt_count<3) then return null;end if;
  select decrypted_secret into v_token from vault.decrypted_secrets where name='black_pages_research_worker_token' order by created_at desc limit 1;
  if nullif(v_token,'') is null then return null;end if;
  select net.http_post(url:='https://dzlmtvodpyhetvektfuo.supabase.co/functions/v1/black-pages-brw-worker',headers:=jsonb_build_object('Content-Type','application/json','x-worker-token',v_token),body:=jsonb_build_object('jobs',3)) into v_request_id;
  return v_request_id;
end $$;
revoke all on function public.black_pages_brw_cron_tick() from public,anon,authenticated;
grant execute on function public.black_pages_brw_cron_tick() to service_role;

do $block$
declare v_job bigint;
begin
  select jobid into v_job from cron.job where jobname='black-pages-brw-drain' limit 1;if v_job is not null then perform cron.unschedule(v_job);end if;
  select jobid into v_job from cron.job where jobname='black-pages-brw-weekly-refresh' limit 1;if v_job is not null then perform cron.unschedule(v_job);end if;
end $block$;
select cron.schedule('black-pages-brw-drain','*/2 * * * *',$cmd$select public.black_pages_brw_cron_tick();$cmd$);
select cron.schedule('black-pages-brw-weekly-refresh','23 5 * * 1',$cmd$select public.black_pages_queue_brw_refresh_internal(73);$cmd$);
