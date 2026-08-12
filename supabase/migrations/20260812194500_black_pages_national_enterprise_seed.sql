-- THE BLACK PAGES: expand private discovery across every city represented in the enterprise contact master.
-- These are unverified discovery leads only; publication still requires Black-owned evidence review.

create or replace function public.black_pages_seed_national_enterprise_company_leads()
returns jsonb
language plpgsql
security definer
set search_path='pg_catalog','public'
as $function$
declare v_inserted integer:=0; v_endpoint integer:=0;
begin
  if auth.role()<>'service_role' then raise exception 'Service role required' using errcode='42501'; end if;

  with source_rows as (
    select c.id,
      left(btrim(c.company),220) business_name,
      left(btrim(c.city),120) city,
      nullif(upper(left(btrim(coalesce(c.state,'')),2)),'') state,
      nullif(btrim(c.website),'') website_url,
      nullif(regexp_replace(btrim(coalesce(c.instagram_handle,'')),'^@','','g'),'') instagram_handle,
      nullif(btrim(c.email),'') public_email,
      nullif(btrim(c.phone),'') public_phone,
      coalesce(c.source,'contacts_master') source_name,
      coalesce(c.source_detail,'') source_detail,
      case
        when nullif(btrim(c.website),'') is not null then nullif(btrim(c.website),'')
        when nullif(btrim(c.instagram_handle),'') is not null then 'https://www.instagram.com/'||regexp_replace(btrim(c.instagram_handle),'^@','','g')||'/'
        else null
      end research_url
    from public.contacts_master c
    where nullif(btrim(c.company),'') is not null
      and nullif(btrim(c.city),'') is not null
  ), inserted as (
    insert into public.black_pages_candidate_queue(
      source_type,source_external_key,business_name,city,state,category,subcategory,website_url,
      instagram_handle,public_email,public_phone,source_sheets,data_quality_status,
      ownership_evidence_status,pipeline_stage,priority_score,assigned_researcher,next_action_at,notes
    )
    select 'research','contacts_master:'||s.id::text,s.business_name,s.city,s.state,null,null,s.research_url,
      s.instagram_handle,s.public_email,s.public_phone,array_remove(array[s.source_name,s.source_detail],''),
      case
        when s.website_url is not null then 'research_ready'
        when s.instagram_handle is not null then 'social_lookup_required'
        else 'endpoint_lookup_required'
      end,
      'unreviewed','research',
      (35 + case when s.website_url is not null then 20 else 0 end + case when s.instagram_handle is not null then 12 else 0 end +
       case when s.public_phone is not null then 6 else 0 end + case when s.public_email is not null then 6 else 0 end)::numeric,
      case
        when s.website_url is not null then 'black-pages-research-worker'
        when s.instagram_handle is not null then 'black-pages-social-research-worker'
        else 'black-pages-endpoint-enrichment'
      end,
      now(),
      'National bulk enterprise-company discovery lead. This record is NOT verified as Black-owned and must pass ownership evidence review before publication.'
    from source_rows s
    where not exists (
      select 1 from public.black_pages_candidate_queue q
      where lower(btrim(q.business_name))=lower(btrim(s.business_name))
        and lower(btrim(q.city))=lower(btrim(s.city))
        and q.pipeline_stage not in ('rejected','do_not_contact')
    )
    on conflict(source_type,source_external_key) where source_external_key is not null do nothing
    returning id,website_url
  )
  select count(*)::integer,count(*) filter(where website_url is not null)::integer
  into v_inserted,v_endpoint from inserted;

  return jsonb_build_object('inserted',v_inserted,'public_endpoint_rows',v_endpoint,'source','contacts_master','scope','national');
end;
$function$;

revoke all on function public.black_pages_seed_national_enterprise_company_leads() from public,anon,authenticated;
grant execute on function public.black_pages_seed_national_enterprise_company_leads() to service_role;
