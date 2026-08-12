-- Improve identity resolution safely: only backfill missing/Unknown city/state using an exact same-name + phone/email/domain match.
-- Known locations are never overwritten, so separate known locations of one brand remain distinct.
create or replace function public.black_pages_backfill_identity_locations(p_limit integer default 10000)
returns jsonb language plpgsql security definer set search_path='pg_catalog','public' as $$
declare v_limit integer:=least(30000,greatest(1,coalesce(p_limit,10000)));v_updated integer:=0;
begin
  with targets as(
    select q.id,q.business_name,q.city,q.state,q.public_phone,q.public_email,q.website_url
    from public.black_pages_candidate_queue q
    where q.pipeline_stage not in('rejected','do_not_contact')
      and not public.black_pages_identity_name_is_generic(q.business_name)
      and (public.black_pages_norm_city(q.city)='' or nullif(btrim(coalesce(q.state,'')),'') is null)
    order by q.priority_score desc nulls last,q.created_at limit v_limit
  ), matches as(
    select distinct on(t.id) t.id,s.city,s.state,s.source_address,s.website_url,s.public_phone,s.public_email,
      case when public.black_pages_norm_phone(t.public_phone)<>'' and public.black_pages_norm_phone(t.public_phone)=public.black_pages_norm_phone(s.public_phone) then 3
           when nullif(lower(btrim(coalesce(t.public_email,''))),'') is not null and lower(btrim(t.public_email))=lower(btrim(s.public_email)) then 2
           when public.black_pages_norm_domain(t.website_url)<>'' and public.black_pages_norm_domain(t.website_url)=public.black_pages_norm_domain(s.website_url) then 1 else 0 end match_rank
    from targets t
    join public.black_pages_candidate_queue s on s.id<>t.id
      and public.black_pages_norm_business_name(s.business_name)=public.black_pages_norm_business_name(t.business_name)
      and public.black_pages_norm_city(s.city)<>'' and nullif(btrim(coalesce(s.state,'')),'') is not null
      and (
        (public.black_pages_norm_phone(t.public_phone)<>'' and public.black_pages_norm_phone(t.public_phone)=public.black_pages_norm_phone(s.public_phone))
        or (nullif(lower(btrim(coalesce(t.public_email,''))),'') is not null and lower(btrim(t.public_email))=lower(btrim(s.public_email)))
        or (public.black_pages_norm_domain(t.website_url)<>'' and public.black_pages_norm_domain(t.website_url)=public.black_pages_norm_domain(s.website_url))
      )
    order by t.id,match_rank desc,coalesce(s.verification_score,0) desc,s.priority_score desc nulls last
  ), upd as(
    update public.black_pages_candidate_queue q set
      city=m.city,state=m.state,
      source_address=coalesce(nullif(q.source_address,''),m.source_address),
      website_url=coalesce(nullif(q.website_url,''),m.website_url),
      public_phone=coalesce(nullif(q.public_phone,''),m.public_phone),
      public_email=coalesce(nullif(q.public_email,''),m.public_email),
      notes=left(concat_ws(E'\n',nullif(q.notes,''),'Identity resolution backfilled missing location from exact same-name contact/domain match.'),4000),
      updated_at=now()
    from matches m where q.id=m.id returning q.id
  )select count(*)::int into v_updated from upd;
  return jsonb_build_object('locations_backfilled',v_updated);
end $$;
revoke all on function public.black_pages_backfill_identity_locations(integer) from public,anon,authenticated;
grant execute on function public.black_pages_backfill_identity_locations(integer) to service_role;

create or replace function public.black_pages_refresh_identity_resolution()
returns jsonb language plpgsql security definer set search_path='pg_catalog','public' as $$
declare v_backfill jsonb;v_resolve jsonb;
begin
 v_backfill:=public.black_pages_backfill_identity_locations(30000);
 v_resolve:=public.black_pages_resolve_candidate_identities(50000);
 return jsonb_build_object('backfill',v_backfill,'resolution',v_resolve);
end $$;
revoke all on function public.black_pages_refresh_identity_resolution() from public,anon,authenticated;
grant execute on function public.black_pages_refresh_identity_resolution() to service_role;
