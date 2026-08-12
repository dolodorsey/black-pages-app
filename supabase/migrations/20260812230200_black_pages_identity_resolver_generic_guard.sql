-- Rebuild identity membership using candidate IDs for generic placeholder names.
-- Safe at introduction time because identity review has not yet been exposed in production UI.
create or replace function public.black_pages_resolve_candidate_identities(p_limit integer default 30000)
returns jsonb
language plpgsql security definer set search_path='pg_catalog','public' as $$
declare
  v_limit integer:=least(50000,greatest(1,coalesce(p_limit,30000)));
  v_identity_count integer:=0;v_member_count integer:=0;
begin
  with src as(
    select q.*,
      case when public.black_pages_identity_name_is_generic(q.business_name) then 'candidate:'||q.id::text
        else public.black_pages_candidate_identity_key(q.business_name,q.city,q.state,q.website_url,q.public_phone,q.public_email) end identity_key,
      case when q.source_external_key like 'external:%' then split_part(q.source_external_key,':',2) else coalesce(q.source_type,'unknown') end source_label,
      (coalesce(q.verification_score,0)+case when nullif(q.external_source_url,'') is not null then 20 else 0 end
        +case when nullif(q.website_url,'') is not null then 8 else 0 end+case when nullif(q.source_address,'') is not null then 8 else 0 end
        +case when nullif(q.public_phone,'') is not null then 4 else 0 end+case when nullif(q.public_email,'') is not null then 4 else 0 end
        +case when nullif(q.subcategory,'') is not null then 6 else 0 end+coalesce(q.priority_score,0)/1000.0) rank_score
    from public.black_pages_candidate_queue q
    where q.pipeline_stage not in('rejected','do_not_contact')
    order by q.priority_score desc nulls last,q.created_at limit v_limit
  ),grouped as(
    select identity_key,(array_agg(id order by rank_score desc,id))[1] canonical_candidate_id,
      (array_agg(business_name order by rank_score desc,id))[1] canonical_name,(array_agg(city order by rank_score desc,id))[1] city,
      (array_agg(state order by rank_score desc,id))[1] state,(array_agg(category order by rank_score desc,id))[1] category,
      (array_agg(subcategory order by rank_score desc,id))[1] subcategory,coalesce(max(verification_score),0) max_verification_score,
      count(*)::int member_count,count(distinct source_label)::int source_count,
      case when count(*)>1 and count(distinct source_label)>1 then .98 when count(*)>1 then .93
           when identity_key like 'name_city:%' then .90 when identity_key like 'name_web:%' then .92
           when identity_key like 'name_phone:%' then .94 when identity_key like 'name_email:%' then .94 else .78 end identity_confidence
    from src group by identity_key
  ),upserted as(
    insert into public.black_pages_candidate_identities(identity_key,canonical_candidate_id,canonical_name,city,state,category,subcategory,max_verification_score,member_count,source_count,identity_confidence,updated_at)
    select identity_key,canonical_candidate_id,canonical_name,city,state,category,subcategory,max_verification_score,member_count,source_count,identity_confidence,now() from grouped
    on conflict(identity_key) do update set canonical_candidate_id=excluded.canonical_candidate_id,canonical_name=excluded.canonical_name,
      city=excluded.city,state=excluded.state,category=excluded.category,subcategory=excluded.subcategory,max_verification_score=excluded.max_verification_score,
      member_count=excluded.member_count,source_count=excluded.source_count,identity_confidence=excluded.identity_confidence,updated_at=now()
    returning id
  )select count(*)::int into v_identity_count from upserted;

  with src as(
    select q.id candidate_id,case when public.black_pages_identity_name_is_generic(q.business_name) then 'candidate:'||q.id::text
      else public.black_pages_candidate_identity_key(q.business_name,q.city,q.state,q.website_url,q.public_phone,q.public_email) end identity_key
    from public.black_pages_candidate_queue q where q.pipeline_stage not in('rejected','do_not_contact')
    order by q.priority_score desc nulls last,q.created_at limit v_limit
  ),upserted as(
    insert into public.black_pages_candidate_identity_members(identity_id,candidate_id,match_method,match_score,is_canonical,updated_at)
    select i.id,s.candidate_id,case when i.member_count>1 then 'resolved_business_identity' else 'deterministic_singleton' end,
      i.identity_confidence,s.candidate_id=i.canonical_candidate_id,now()
    from src s join public.black_pages_candidate_identities i on i.identity_key=s.identity_key
    on conflict(candidate_id) do update set identity_id=excluded.identity_id,match_method=excluded.match_method,match_score=excluded.match_score,
      is_canonical=excluded.is_canonical,updated_at=now() returning candidate_id
  )select count(*)::int into v_member_count from upserted;

  -- Remove obsolete identities that no longer own any candidate member and have never been reviewed.
  delete from public.black_pages_candidate_identities i
  where not exists(select 1 from public.black_pages_candidate_identity_members m where m.identity_id=i.id)
    and not exists(select 1 from public.black_pages_candidate_identity_reviews r where r.identity_id=i.id);

  -- Recalculate counts from actual current memberships after moves.
  update public.black_pages_candidate_identities i set
    member_count=x.member_count,source_count=x.source_count,updated_at=now()
  from(
    select m.identity_id,count(*)::int member_count,
      count(distinct case when q.source_external_key like 'external:%' then split_part(q.source_external_key,':',2) else coalesce(q.source_type,'unknown') end)::int source_count
    from public.black_pages_candidate_identity_members m join public.black_pages_candidate_queue q on q.id=m.candidate_id group by m.identity_id
  )x where x.identity_id=i.id;

  return jsonb_build_object('identities_upserted',v_identity_count,'members_resolved',v_member_count,
    'identities',(select count(*) from public.black_pages_candidate_identities),
    'multi_candidate_identities',(select count(*) from public.black_pages_candidate_identities where member_count>1),
    'multi_source_identities',(select count(*) from public.black_pages_candidate_identities where source_count>1),
    'duplicate_rows_collapsed',(select coalesce(sum(member_count-1),0) from public.black_pages_candidate_identities where member_count>1));
end $$;
revoke all on function public.black_pages_resolve_candidate_identities(integer) from public,anon,authenticated;
grant execute on function public.black_pages_resolve_candidate_identities(integer) to service_role;
