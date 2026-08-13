-- Corroboration scoring: chamber membership alone is discovery evidence, not Black-ownership proof.
alter table public.black_pages_candidate_identities
  add column if not exists corroboration_score numeric not null default 0,
  add column if not exists corroboration_tier text,
  add column if not exists corroboration_reasons text[] not null default '{}'::text[],
  add column if not exists corroborated_at timestamptz;

do $b$ begin
 if not exists(select 1 from pg_constraint where conname='black_pages_identity_corroboration_tier_check') then
  alter table public.black_pages_candidate_identities add constraint black_pages_identity_corroboration_tier_check
   check(corroboration_tier is null or corroboration_tier in('ready','research','hold'));
 end if;
end $b$;

create or replace function public.black_pages_refresh_corroboration_scores()
returns jsonb language plpgsql security definer set search_path='pg_catalog','public','auth' as $$
declare v_count integer:=0;
begin
 with evidence as(
  select i.id identity_id,
   count(distinct case when q.source_external_key like 'external:%' then split_part(q.source_external_key,':',2) else null end) external_source_count,
   count(*) filter(where s.ownership_signal='certified_black_business') certified_count,
   count(*) filter(where s.ownership_signal='black_restaurant_week_participant') brw_count,
   count(*) filter(where s.ownership_signal='black_business_directory') black_directory_count,
   count(*) filter(where s.ownership_signal='curated_black_business_guide') curated_count,
   count(*) filter(where s.ownership_signal='black_chamber_directory') chamber_count,
   count(*) filter(where s.ownership_signal in('minority_certification_reference','minority_supplier_reference')) cross_ref_count,
   count(*) filter(where nullif(q.external_source_url,'') is not null) evidence_url_count,
   bool_or(nullif(q.website_url,'') is not null) has_website,
   bool_or(nullif(q.source_address,'') is not null or (nullif(q.city,'') is not null and lower(q.city)<>'unknown')) has_location
  from public.black_pages_candidate_identities i
  join public.black_pages_candidate_identity_members m on m.identity_id=i.id
  join public.black_pages_candidate_queue q on q.id=m.candidate_id
  left join public.black_pages_external_sources s on s.source_key=case when q.source_external_key like 'external:%' then split_part(q.source_external_key,':',2) else null end
  where i.status not in('rejected')
  group by i.id
 ), scored as(
  select e.*,
   least(100,
    case when certified_count>0 then 90 else 0 end+
    case when brw_count>0 then 80 else 0 end+
    case when black_directory_count>0 then 70 else 0 end+
    case when curated_count>0 then 45 else 0 end+
    case when chamber_count>0 then 25 else 0 end+
    case when cross_ref_count>0 then 5 else 0 end+
    case when (certified_count+brw_count+black_directory_count+curated_count)>=2 then 10 else 0 end+
    case when external_source_count>=2 then 5 else 0 end+
    case when has_website then 3 else 0 end+
    case when has_location then 2 else 0 end
   )::numeric score,
   case
    when certified_count>0 then 'ready'
    when brw_count>0 then 'ready'
    when black_directory_count>0 and (certified_count+brw_count+black_directory_count+curated_count)>=2 then 'ready'
    when (certified_count+brw_count+black_directory_count+curated_count)>=2 then 'ready'
    when (certified_count+brw_count+black_directory_count+curated_count+chamber_count)>0 then 'research'
    else 'hold' end tier,
   array_remove(array[
    case when certified_count>0 then 'certified_black_business_source' end,
    case when brw_count>0 then 'black_restaurant_week_source' end,
    case when black_directory_count>0 then 'black_business_directory_source' end,
    case when curated_count>0 then 'curated_black_owned_guide' end,
    case when chamber_count>0 then 'black_chamber_membership_only_needs_corroboration' end,
    case when external_source_count>=2 then 'multiple_independent_sources' end,
    case when cross_ref_count>0 then 'minority_supplier_cross_reference_only' end,
    case when evidence_url_count=0 then 'missing_source_url' end
   ]::text[],null) reasons
  from evidence e
 ), upd as(
  update public.black_pages_candidate_identities i
  set corroboration_score=s.score,corroboration_tier=s.tier,corroboration_reasons=s.reasons,corroborated_at=now(),updated_at=now()
  from scored s where i.id=s.identity_id returning i.id
 ) select count(*)::int into v_count from upd;
 return jsonb_build_object('scored',v_count,
  'ready',(select count(*) from public.black_pages_candidate_identities where corroboration_tier='ready' and status not in('reviewed','rejected')),
  'research',(select count(*) from public.black_pages_candidate_identities where corroboration_tier='research' and status not in('reviewed','rejected')),
  'hold',(select count(*) from public.black_pages_candidate_identities where corroboration_tier='hold' and status not in('reviewed','rejected')));
end $$;
revoke all on function public.black_pages_refresh_corroboration_scores() from public,anon,authenticated;
grant execute on function public.black_pages_refresh_corroboration_scores() to service_role;

create or replace function public.black_pages_staff_identity_review_snapshot(p_city text default null,p_limit integer default 500)
returns jsonb language plpgsql security definer set search_path='pg_catalog','public','auth' as $$
declare v_role text:=coalesce(auth.jwt()->'app_metadata'->>'khg_role','');v_rows jsonb;v_counts jsonb;
begin
 if coalesce(auth.role(),'')<>'service_role' and v_role not in('owner','admin','editor') then raise exception 'Staff access required' using errcode='42501';end if;
 perform public.black_pages_refresh_identity_resolution();
 perform public.black_pages_refresh_corroboration_scores();
 select jsonb_build_object(
  'ready',count(*) filter(where coalesce(i.corroboration_tier,s.review_tier)='ready' and i.status not in('reviewed','rejected')),
  'research',count(*) filter(where coalesce(i.corroboration_tier,s.review_tier)='research' and i.status not in('reviewed','rejected')),
  'hold',count(*) filter(where coalesce(i.corroboration_tier,s.review_tier)='hold' and i.status not in('reviewed','rejected')),
  'multi_source',count(*) filter(where s.source_count>1),
  'duplicate_rows_collapsed',coalesce(sum(s.member_count-1) filter(where s.member_count>1),0)
 ) into v_counts
 from public.black_pages_candidate_identity_summary s join public.black_pages_candidate_identities i on i.id=s.identity_id
 where p_city is null or lower(s.city)=lower(p_city);
 select coalesce(jsonb_agg(row_json order by tier_rank,corroboration_score desc,source_count desc,max_verification_score desc,business_name),'[]'::jsonb) into v_rows
 from(
  select (to_jsonb(s)||jsonb_build_object('review_tier',coalesce(i.corroboration_tier,s.review_tier),'corroboration_score',i.corroboration_score,'corroboration_tier',i.corroboration_tier,'corroboration_reasons',i.corroboration_reasons,'evidence',coalesce((select jsonb_agg(jsonb_build_object('candidate_id',q.id,'source_key',case when q.source_external_key like 'external:%' then split_part(q.source_external_key,':',2) else q.source_type end,'source_name',es.source_name,'ownership_signal',es.ownership_signal,'source_url',q.external_source_url,'website_url',q.website_url,'phone',q.public_phone,'email',q.public_email,'address',q.source_address,'verification_score',q.verification_score,'verification_tier',q.verification_tier,'pipeline_stage',q.pipeline_stage) order by coalesce(q.verification_score,0) desc) from public.black_pages_candidate_identity_members mm join public.black_pages_candidate_queue q on q.id=mm.candidate_id left join public.black_pages_external_sources es on es.source_key=case when q.source_external_key like 'external:%' then split_part(q.source_external_key,':',2) else null end where mm.identity_id=s.identity_id),'[]'::jsonb))) row_json,
   case coalesce(i.corroboration_tier,s.review_tier) when 'ready' then 1 when 'research' then 2 else 3 end tier_rank,i.corroboration_score,s.source_count,s.max_verification_score,s.business_name
  from public.black_pages_candidate_identity_summary s join public.black_pages_candidate_identities i on i.id=s.identity_id
  where i.status not in('reviewed','rejected') and(p_city is null or lower(s.city)=lower(p_city))
  order by tier_rank,i.corroboration_score desc,s.source_count desc,s.max_verification_score desc
  limit least(1000,greatest(1,coalesce(p_limit,500)))
 ) x;
 return jsonb_build_object('counts',v_counts,'identities',v_rows,'generated_at',now());
end $$;
revoke all on function public.black_pages_staff_identity_review_snapshot(text,integer) from public,anon,authenticated;
grant execute on function public.black_pages_staff_identity_review_snapshot(text,integer) to authenticated,service_role;