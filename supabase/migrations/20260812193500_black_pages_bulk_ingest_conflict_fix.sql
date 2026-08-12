create or replace function public.black_pages_bulk_ingest_internal_candidates(p_limit integer default 5000)
returns jsonb language plpgsql security definer set search_path='pg_catalog','public' as $$
declare v_limit integer:=least(10000,greatest(100,coalesce(p_limit,5000))); v_directory integer:=0; v_contacts integer:=0;
begin
  with src as (
    select d.id,d.name business_name,d.city,d.state,d.category,nullif(trim(d.website_url),'') website_url,
      nullif(trim(d.instagram_handle),'') instagram_handle,null::text public_email,nullif(trim(d.phone),'') public_phone,
      'directory_listing:'||d.id::text source_key
    from public.directory_listings d
    where nullif(trim(d.name),'') is not null and nullif(trim(d.city),'') is not null
      and lower(coalesce(d.category,'')) not in ('day_party','pool_party','special_events','brunch_party')
    order by d.id limit v_limit
  ), ins as (
    insert into public.black_pages_candidate_queue(
      business_name,city,state,category,subcategory,website_url,instagram_handle,public_email,public_phone,
      source_sheets,data_quality_status,ownership_evidence_status,pipeline_stage,priority_score,next_action_at,source_type,source_external_key,notes)
    select s.business_name,s.city,nullif(trim(s.state),''),public.black_pages_map_bulk_category(s.category),public.black_pages_map_bulk_subcategory(s.category),
      s.website_url,s.instagram_handle,s.public_email,s.public_phone,array['directory_listings'],'bulk_discovered','unreviewed','research',
      45+case when s.website_url is not null then 20 else 0 end+case when s.instagram_handle is not null then 10 else 0 end,
      now(),'directory_listing',s.source_key,'Bulk-discovered private candidate. Ownership must be verified before publication.'
    from src s
    where not exists(select 1 from public.black_pages_candidate_queue q where q.source_type='directory_listing' and q.source_external_key=s.source_key)
      and not exists(select 1 from public.black_pages_candidate_queue q where lower(q.business_name)=lower(s.business_name) and lower(q.city)=lower(s.city) and coalesce(q.state,'')=coalesce(nullif(trim(s.state),''),''))
    on conflict(source_type,source_external_key) where source_external_key is not null do nothing returning 1
  ) select count(*) into v_directory from ins;

  with src as (
    select c.id,c.company business_name,c.city,c.state,nullif(trim(c.website),'') website_url,
      nullif(trim(c.instagram_handle),'') instagram_handle,nullif(trim(c.email),'') public_email,nullif(trim(c.phone),'') public_phone,
      'contacts_master:'||c.id::text source_key
    from public.contacts_master c
    where nullif(trim(c.company),'') is not null and nullif(trim(c.city),'') is not null
    order by c.id limit v_limit
  ), ins as (
    insert into public.black_pages_candidate_queue(
      business_name,city,state,category,subcategory,website_url,instagram_handle,public_email,public_phone,
      source_sheets,data_quality_status,ownership_evidence_status,pipeline_stage,priority_score,next_action_at,source_type,source_external_key,notes)
    select s.business_name,s.city,nullif(trim(s.state),''),null,null,s.website_url,s.instagram_handle,s.public_email,s.public_phone,
      array['contacts_master'],'bulk_discovered','unreviewed','research',
      35+case when s.website_url is not null then 20 else 0 end+case when s.instagram_handle is not null then 10 else 0 end+case when s.public_email is not null then 5 else 0 end,
      now(),'contacts_master',s.source_key,'Bulk-discovered private candidate. Ownership and business category must be verified before publication.'
    from src s
    where not exists(select 1 from public.black_pages_candidate_queue q where q.source_type='contacts_master' and q.source_external_key=s.source_key)
      and not exists(select 1 from public.black_pages_candidate_queue q where lower(q.business_name)=lower(s.business_name) and lower(q.city)=lower(s.city) and coalesce(q.state,'')=coalesce(nullif(trim(s.state),''),''))
    on conflict(source_type,source_external_key) where source_external_key is not null do nothing returning 1
  ) select count(*) into v_contacts from ins;

  return jsonb_build_object('directory_listings_added',v_directory,'contacts_master_added',v_contacts,'total_added',v_directory+v_contacts);
end; $$;

revoke all on function public.black_pages_bulk_ingest_internal_candidates(integer) from public,anon,authenticated;
