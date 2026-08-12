-- THE BLACK PAGES: deeper enrichment lane for unresolved taxonomy candidates.

alter table public.black_pages_candidate_queue
  add column if not exists deep_enrichment_status text,
  add column if not exists deep_enrichment_attempts integer not null default 0,
  add column if not exists deep_enrichment_context text,
  add column if not exists deep_enrichment_last_at timestamptz;

do $block$
begin
 if not exists(select 1 from pg_constraint where conname='black_pages_candidate_deep_enrichment_status_check') then
   alter table public.black_pages_candidate_queue add constraint black_pages_candidate_deep_enrichment_status_check
   check(deep_enrichment_status is null or deep_enrichment_status in('pending','processing','complete','retry','manual'));
 end if;
end $block$;

create index if not exists black_pages_deep_enrichment_claim_idx
 on public.black_pages_candidate_queue(deep_enrichment_status,priority_score desc,next_action_at)
 where pipeline_stage not in('published','rejected','do_not_contact');

update public.black_pages_candidate_queue
set deep_enrichment_status='pending',next_action_at=least(coalesce(next_action_at,now()),now()),updated_at=now()
where (subcategory is null or btrim(subcategory)='')
  and pipeline_stage not in('published','rejected','do_not_contact')
  and (nullif(website_url,'') is not null or nullif(external_source_url,'') is not null)
  and coalesce(deep_enrichment_status,'') not in('processing','complete');

create or replace function public.black_pages_claim_deep_enrichment(p_limit integer default 50)
returns jsonb language plpgsql security definer set search_path='pg_catalog','public' as $$
declare v_limit integer:=least(100,greatest(1,coalesce(p_limit,50)));v_rows jsonb;
begin
 if auth.role()<>'service_role' then raise exception 'Service role required' using errcode='42501';end if;
 with due as(
   select id from public.black_pages_candidate_queue
   where pipeline_stage not in('published','rejected','do_not_contact')
     and (subcategory is null or btrim(subcategory)='')
     and coalesce(deep_enrichment_status,'pending') in('pending','retry')
     and deep_enrichment_attempts<3
     and (nullif(website_url,'') is not null or nullif(external_source_url,'') is not null)
     and coalesce(next_action_at,now())<=now()
   order by priority_score desc,id for update skip locked limit v_limit
 ), claimed as(
   update public.black_pages_candidate_queue q set deep_enrichment_status='processing',deep_enrichment_attempts=deep_enrichment_attempts+1,
     deep_enrichment_last_at=now(),updated_at=now()
   from due d where q.id=d.id
   returning q.id,q.business_name,q.city,q.state,q.category,q.subcategory,q.website_url,q.external_source_url,q.source_category,q.source_subcategory,q.notes,q.deep_enrichment_attempts
 ) select coalesce(jsonb_agg(to_jsonb(claimed)),'[]'::jsonb) into v_rows from claimed;
 return jsonb_build_object('claimed',jsonb_array_length(v_rows),'candidates',v_rows);
end $$;
revoke all on function public.black_pages_claim_deep_enrichment(integer) from public,anon,authenticated;
grant execute on function public.black_pages_claim_deep_enrichment(integer) to service_role;

create or replace function public.black_pages_complete_deep_enrichment(p_candidate_id uuid,p_context text,p_phone text default null,p_email text default null,p_error text default null)
returns jsonb language plpgsql security definer set search_path='pg_catalog','public' as $$
declare v_attempts integer;
begin
 if auth.role()<>'service_role' then raise exception 'Service role required' using errcode='42501';end if;
 select deep_enrichment_attempts into v_attempts from public.black_pages_candidate_queue where id=p_candidate_id for update;
 if not found then raise exception 'Candidate not found';end if;
 if nullif(btrim(coalesce(p_error,'')),'') is not null then
   update public.black_pages_candidate_queue set deep_enrichment_status=case when v_attempts>=3 then 'manual' else 'retry' end,
     next_action_at=case when v_attempts>=3 then now()+interval '30 days' else now()+interval '12 hours' end,
     deep_enrichment_context=left(coalesce(p_context,''),6000),deep_enrichment_last_at=now(),updated_at=now()
   where id=p_candidate_id;
   return jsonb_build_object('candidate_id',p_candidate_id,'status',case when v_attempts>=3 then 'manual' else 'retry' end);
 end if;
 update public.black_pages_candidate_queue set deep_enrichment_status='complete',deep_enrichment_context=left(coalesce(p_context,''),6000),
   notes=left(concat_ws(E'\n',nullif(notes,''),'Deep enrichment context: '||left(coalesce(p_context,''),3500)),4000),
   public_phone=coalesce(nullif(public_phone,''),nullif(btrim(coalesce(p_phone,'')),'')),
   public_email=coalesce(nullif(public_email,''),nullif(btrim(coalesce(p_email,'')),'')),
   deep_enrichment_last_at=now(),updated_at=now()
 where id=p_candidate_id;
 return jsonb_build_object('candidate_id',p_candidate_id,'status','complete');
end $$;
revoke all on function public.black_pages_complete_deep_enrichment(uuid,text,text,text,text) from public,anon,authenticated;
grant execute on function public.black_pages_complete_deep_enrichment(uuid,text,text,text,text) to service_role;

create or replace function public.black_pages_dispatch_deep_enrichment(p_limit integer default 50,p_shards integer default 4)
returns jsonb language plpgsql security definer set search_path='pg_catalog','public','net','vault','auth' as $$
declare v_role text:=coalesce(auth.jwt()->'app_metadata'->>'khg_role','');v_limit integer:=least(100,greatest(1,coalesce(p_limit,50)));
 v_shards integer:=least(8,greatest(1,coalesce(p_shards,4)));v_token text;v_id bigint;v_ids jsonb:='[]'::jsonb;i integer;
begin
 if coalesce(auth.role(),'')<>'service_role' and v_role not in('owner','admin','editor') then raise exception 'Staff access required' using errcode='42501';end if;
 select decrypted_secret into v_token from vault.decrypted_secrets where name='black_pages_research_worker_token' order by created_at desc limit 1;
 if nullif(v_token,'') is null then raise exception 'BLACK PAGES worker token missing';end if;
 for i in 1..v_shards loop
   select net.http_post(url:='https://dzlmtvodpyhetvektfuo.supabase.co/functions/v1/black-pages-deep-enrichment-worker',
     headers:=jsonb_build_object('Content-Type','application/json','x-worker-token',v_token),body:=jsonb_build_object('limit',v_limit)) into v_id;
   v_ids:=v_ids||jsonb_build_array(v_id);
 end loop;
 return jsonb_build_object('shards',v_shards,'limit_per_shard',v_limit,'max_candidates',v_shards*v_limit,'request_ids',v_ids);
end $$;
revoke all on function public.black_pages_dispatch_deep_enrichment(integer,integer) from public,anon,authenticated;
grant execute on function public.black_pages_dispatch_deep_enrichment(integer,integer) to authenticated,service_role;
