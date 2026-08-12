-- External source completion now preserves direct website/contact fields and feeds both classifier lanes.
create or replace function public.black_pages_complete_external_job(p_job_id uuid,p_items jsonb,p_error text default null)
returns jsonb language plpgsql security definer set search_path='pg_catalog','public' as $$
declare v_job public.black_pages_external_discovery_jobs%rowtype;v_inserted integer:=0;
begin
  if auth.role()<>'service_role' then raise exception 'Service role required' using errcode='42501';end if;
  select * into v_job from public.black_pages_external_discovery_jobs where id=p_job_id for update;
  if not found then raise exception 'External job not found';end if;
  if nullif(btrim(coalesce(p_error,'')),'') is not null then
    update public.black_pages_external_discovery_jobs set status='failed',error_message=left(p_error,1000),completed_at=now(),updated_at=now() where id=p_job_id;
    return jsonb_build_object('job_id',p_job_id,'inserted',0,'status','failed');
  end if;
  with raw as(
    select value item,ordinality n from jsonb_array_elements(coalesce(p_items,'[]'::jsonb)) with ordinality
  ),clean as(
    select left(btrim(item->>'business_name'),220) business_name,
      left(coalesce(nullif(btrim(item->>'city'),''),v_job.city,'Unknown'),120) city,
      upper(left(coalesce(nullif(btrim(item->>'state'),''),v_job.state,''),2)) state,
      nullif(left(btrim(item->>'source_category'),120),'') source_category,
      nullif(left(btrim(item->>'source_subcategory'),120),'') source_subcategory,
      nullif(left(btrim(item->>'address'),500),'') address,nullif(left(btrim(item->>'postal_code'),20),'') postal_code,
      nullif(left(btrim(item->>'detail_url'),700),'') detail_url,nullif(left(btrim(item->>'website_url'),700),'') website_url,
      nullif(left(regexp_replace(btrim(item->>'instagram_handle'),'^@','','g'),160),'') instagram_handle,
      nullif(left(btrim(item->>'public_email'),320),'') public_email,nullif(left(btrim(item->>'public_phone'),80),'') public_phone,
      nullif(left(btrim(item->>'description'),1000),'') description,coalesce(nullif(left(btrim(item->>'source_key'),180),''),n::text) source_key
    from raw
  ),ins as(
    insert into public.black_pages_candidate_queue(source_type,source_external_key,business_name,city,state,source_category,source_subcategory,source_address,source_postal_code,external_source_url,website_url,instagram_handle,public_email,public_phone,source_sheets,data_quality_status,ownership_evidence_status,pipeline_stage,priority_score,assigned_researcher,next_action_at,notes)
    select 'research','external:'||v_job.source_key||':'||source_key,business_name,city,nullif(state,''),source_category,source_subcategory,address,postal_code,detail_url,website_url,instagram_handle,public_email,public_phone,array[v_job.source_key],
      'external_directory_found','evidence_found','verification',85,'black-pages-owner-verification-agent',now(),
      left('External Black-business directory evidence; human verification required before publication. '||coalesce(description,''),4000)
    from clean where nullif(business_name,'') is not null and not exists(
      select 1 from public.black_pages_candidate_queue q where lower(btrim(q.business_name))=lower(btrim(clean.business_name)) and lower(btrim(q.city))=lower(btrim(clean.city)) and coalesce(q.state,'')=coalesce(nullif(clean.state,''),'')
    ) on conflict(source_type,source_external_key) where source_external_key is not null do nothing returning id
  )select count(*)::int into v_inserted from ins;
  update public.black_pages_external_discovery_jobs set status='completed',result_count=v_inserted,error_message=null,completed_at=now(),updated_at=now() where id=p_job_id;
  perform public.black_pages_auto_classify_batch(20000);
  perform public.black_pages_context_classify_batch(20000);
  perform public.black_pages_preverify_batch(20000);
  return jsonb_build_object('job_id',p_job_id,'inserted',v_inserted,'status','completed');
end $$;
revoke all on function public.black_pages_complete_external_job(uuid,jsonb,text) from public,anon,authenticated;
grant execute on function public.black_pages_complete_external_job(uuid,jsonb,text) to service_role;
