-- Keep only validated external adapters active in Find Now routing.
update public.black_pages_external_sources
set active=false,updated_at=now(),notes=notes||' Adapter disabled after parser QA; directory retained for a dedicated parser revision.'
where source_key='dallas_black_chamber';

create or replace function public.black_pages_queue_external_discovery(p_city text,p_state text,p_quantity integer default 1000,p_categories text[] default '{}')
returns jsonb language plpgsql security definer set search_path='pg_catalog','public' as $$
declare
  v_qty integer:=least(1000,greatest(10,coalesce(p_quantity,1000)));
  v_city text:=btrim(p_city); v_state text:=upper(left(btrim(p_state),2));
  v_source text; v_per_page integer; v_pages integer; v_created integer:=0; v_page integer; v_cat text; v_cats text[];
  v_url text; v_qty_per_cat integer;
begin
  if lower(v_city)='houston' then v_source:='houston_buy_black'; v_per_page:=20;
  else v_source:='atlanta_black_chambers'; v_per_page:=10; end if;
  v_cats:=case when coalesce(array_length(p_categories,1),0)=0 then array[null::text] else p_categories end;
  v_qty_per_cat:=greatest(1,ceil(v_qty::numeric/greatest(array_length(v_cats,1),1))::int);
  foreach v_cat in array v_cats loop
    v_pages:=ceil(v_qty_per_cat::numeric/v_per_page)::int;
    for v_page in 1..v_pages loop
      if v_source='houston_buy_black' then
        v_url:=case when v_page=1 then 'https://houstonbuyblack.com/buyblack/' else 'https://houstonbuyblack.com/buyblack/page/'||v_page::text||'/' end;
      else
        v_url:='https://abc.iamblackbusiness.com/?filter=state%7C'||v_state||case when nullif(v_city,'') is not null then '%2Bcity%7C'||replace(v_city,' ','%20') else '' end||'&sort=name&page='||((v_page-1)*10)::text;
      end if;
      if v_cat is not null then v_url:=v_url||case when position('?' in v_url)>0 then '&' else '?' end||'_bp_category='||replace(v_cat,' ','%20'); end if;
      insert into public.black_pages_external_discovery_jobs(source_key,city,state,category_slug,page_offset,request_url,requested_count,requested_by)
      values(v_source,v_city,v_state,v_cat,(v_page-1)*v_per_page,v_url,least(v_per_page,v_qty_per_cat),auth.uid())
      on conflict(source_key,request_url) do update set status=case when public.black_pages_external_discovery_jobs.status='completed' then 'completed' else 'pending' end,updated_at=now();
      v_created:=v_created+1;
    end loop;
  end loop;
  return jsonb_build_object('jobs_queued',v_created,'requested_quantity',v_qty,'source',v_source,'categories',v_cats);
end; $$;
revoke all on function public.black_pages_queue_external_discovery(text,text,integer,text[]) from public,anon,authenticated,service_role;
