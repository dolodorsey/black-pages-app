-- Internal service-role QA may read the private identity review snapshot.
-- Human review decisions remain owner/admin/editor authenticated only.
create or replace function public.black_pages_staff_identity_review_snapshot(p_city text default null,p_limit integer default 500)
returns jsonb
language plpgsql security definer set search_path='pg_catalog','public','auth' as $$
declare v_role text:=coalesce(auth.jwt()->'app_metadata'->>'khg_role','');v_rows jsonb;v_counts jsonb;
begin
  if coalesce(auth.role(),'')<>'service_role' and v_role not in('owner','admin','editor') then raise exception 'Staff access required' using errcode='42501';end if;
  perform public.black_pages_refresh_identity_resolution();
  select jsonb_build_object(
    'ready',count(*) filter(where review_tier='ready' and status not in('reviewed','rejected')),
    'research',count(*) filter(where review_tier='research' and status not in('reviewed','rejected')),
    'hold',count(*) filter(where review_tier='hold' and status not in('reviewed','rejected')),
    'multi_source',count(*) filter(where source_count>1),
    'duplicate_rows_collapsed',coalesce(sum(member_count-1) filter(where member_count>1),0)
  ) into v_counts
  from public.black_pages_candidate_identity_summary
  where p_city is null or lower(city)=lower(p_city);

  select coalesce(jsonb_agg(to_jsonb(x) order by x.source_count desc,x.max_verification_score desc,x.business_name),'[]'::jsonb) into v_rows
  from(
    select s.*,
      coalesce((select jsonb_agg(jsonb_build_object(
        'candidate_id',q.id,'source_key',case when q.source_external_key like 'external:%' then split_part(q.source_external_key,':',2) else q.source_type end,
        'source_name',es.source_name,'ownership_signal',es.ownership_signal,'source_url',q.external_source_url,
        'website_url',q.website_url,'phone',q.public_phone,'email',q.public_email,'address',q.source_address,
        'verification_score',q.verification_score,'verification_tier',q.verification_tier,'pipeline_stage',q.pipeline_stage
      ) order by coalesce(q.verification_score,0) desc)
      from public.black_pages_candidate_identity_members mm
      join public.black_pages_candidate_queue q on q.id=mm.candidate_id
      left join public.black_pages_external_sources es on es.source_key=case when q.source_external_key like 'external:%' then split_part(q.source_external_key,':',2) else null end
      where mm.identity_id=s.identity_id),'[]'::jsonb) evidence
    from public.black_pages_candidate_identity_summary s
    where s.status not in('reviewed','rejected') and(p_city is null or lower(s.city)=lower(p_city))
    order by case s.review_tier when 'ready' then 1 when 'research' then 2 else 3 end,s.source_count desc,s.max_verification_score desc
    limit least(1000,greatest(1,coalesce(p_limit,500)))
  )x;
  return jsonb_build_object('counts',v_counts,'identities',v_rows,'generated_at',now());
end $$;
revoke all on function public.black_pages_staff_identity_review_snapshot(text,integer) from public,anon,authenticated;
grant execute on function public.black_pages_staff_identity_review_snapshot(text,integer) to authenticated,service_role;
