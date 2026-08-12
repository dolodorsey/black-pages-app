-- THE BLACK PAGES: burst discovery + broad internal source intake.

create or replace function public.black_pages_seed_internal_business_sources(p_limit integer default 5000)
returns jsonb language plpgsql security definer set search_path='pg_catalog','public' as $$
declare v_limit integer:=least(10000,greatest(100,coalesce(p_limit,5000))); v_directory integer:=0; v_contacts integer:=0;
begin
  with src as (
    select d.id,d.name business_name,d.city,d.state,d.category,
      nullif(trim(d.website_url),'') website_url,nullif(trim(d.instagram_handle),'') instagram_handle,
      nullif(trim(d.phone),'') public_phone,'directory_listings:'||d.id::text source_key
    from public.directory_listings d
    where nullif(trim(d.name),'') is not null and nullif(trim(d.city),'') is not null
      and lower(coalesce(d.category,'')) not in ('day_party','pool_party','special_events','brunch_party')
    order by d.id limit v_limit
  ), ins as (
    insert into public.black_pages_candidate_queue(
      source_type,source_external_key,business_name,city,state,category,subcategory,website_url,instagram_handle,
      public_phone,source_sheets,data_quality_status,ownership_evidence_status,pipeline_stage,priority_score,
      assigned_researcher,next_action_at,notes)
    select 'research',s.source_key,s.business_name,s.city,nullif(trim(s.state),''),
      public.black_pages_canonical_category(s.category),null,
      coalesce(s.website_url,case when s.instagram_handle is not null then 'https://www.instagram.com/'||regexp_replace(s.instagram_handle,'^@','','g')||'/' end),
      regexp_replace(coalesce(s.instagram_handle,''),'^@','','g'),s.public_phone,array['directory_listings'],
      case when s.website_url is not null or s.instagram_handle is not null then 'research_ready' else 'needs_enrichment' end,
      'unreviewed','research',
      45+case when s.website_url is not null then 20 else 0 end+case when s.instagram_handle is not null then 10 else 0 end,
      'black-pages-research-worker',now(),
      'Bulk internal discovery candidate. Not verified Black-owned; ownership review required before publication.'
    from src s
    where not exists(select 1 from public.black_pages_candidate_queue q where q.source_type='research' and q.source_external_key=s.source_key)
      and not exists(select 1 from public.black_pages_candidate_queue q where lower(trim(q.business_name))=lower(trim(s.business_name)) and lower(trim(q.city))=lower(trim(s.city)) and coalesce(q.state,'')=coalesce(nullif(trim(s.state),''),''))
    on conflict(source_type,source_external_key) where source_external_key is not null do nothing returning 1
  ) select count(*) into v_directory from ins;

  with src as (
    select c.id,c.company business_name,c.city,c.state,nullif(trim(c.website),'') website_url,
      nullif(trim(c.instagram_handle),'') instagram_handle,nullif(trim(c.email),'') public_email,
      nullif(trim(c.phone),'') public_phone,'contacts_master:'||c.id::text source_key
    from public.contacts_master c
    where nullif(trim(c.company),'') is not null and nullif(trim(c.city),'') is not null
    order by c.id limit v_limit
  ), ins as (
    insert into public.black_pages_candidate_queue(
      source_type,source_external_key,business_name,city,state,website_url,instagram_handle,public_email,public_phone,
      source_sheets,data_quality_status,ownership_evidence_status,pipeline_stage,priority_score,assigned_researcher,next_action_at,notes)
    select 'research',s.source_key,s.business_name,s.city,nullif(trim(s.state),''),
      coalesce(s.website_url,case when s.instagram_handle is not null then 'https://www.instagram.com/'||regexp_replace(s.instagram_handle,'^@','','g')||'/' end),
      regexp_replace(coalesce(s.instagram_handle,''),'^@','','g'),s.public_email,s.public_phone,array['contacts_master'],
      case when s.website_url is not null or s.instagram_handle is not null then 'research_ready' else 'needs_enrichment' end,
      'unreviewed','research',
      35+case when s.website_url is not null then 20 else 0 end+case when s.instagram_handle is not null then 10 else 0 end+case when s.public_email is not null then 5 else 0 end,
      'black-pages-research-worker',now(),
      'Bulk internal contact-company candidate. Not verified Black-owned; ownership and category review required before publication.'
    from src s
    where not exists(select 1 from public.black_pages_candidate_queue q where q.source_type='research' and q.source_external_key=s.source_key)
      and not exists(select 1 from public.black_pages_candidate_queue q where lower(trim(q.business_name))=lower(trim(s.business_name)) and lower(trim(q.city))=lower(trim(s.city)) and coalesce(q.state,'')=coalesce(nullif(trim(s.state),''),''))
    on conflict(source_type,source_external_key) where source_external_key is not null do nothing returning 1
  ) select count(*) into v_contacts from ins;

  return jsonb_build_object('directory_listings_added',v_directory,'contacts_master_added',v_contacts,'total_added',v_directory+v_contacts);
end; $$;

revoke all on function public.black_pages_seed_internal_business_sources(integer) from public,anon,authenticated;
grant execute on function public.black_pages_seed_internal_business_sources(integer) to service_role;

create or replace function public.black_pages_research_burst(p_shards integer default 4,p_limit integer default 100)
returns jsonb language plpgsql security definer set search_path='pg_catalog','public' as $$
declare v_shards integer:=least(10,greatest(1,coalesce(p_shards,4))); v_limit integer:=least(100,greatest(1,coalesce(p_limit,100))); v_ids jsonb:='[]'::jsonb; v_id bigint; i integer;
begin
  if auth.role()<>'service_role' then raise exception 'Service role required' using errcode='42501'; end if;
  for i in 1..v_shards loop
    v_id:=public.black_pages_dispatch_research_worker(v_limit);
    v_ids:=v_ids||jsonb_build_array(v_id);
  end loop;
  return jsonb_build_object('shards',v_shards,'limit_per_shard',v_limit,'max_candidates_claimed',v_shards*v_limit,'request_ids',v_ids);
end; $$;

revoke all on function public.black_pages_research_burst(integer,integer) from public,anon,authenticated;
grant execute on function public.black_pages_research_burst(integer,integer) to service_role;

select cron.schedule('black-pages-internal-source-refresh','17 * * * *',$$select public.black_pages_seed_internal_business_sources(5000);$$);
