-- THE BLACK PAGES: approved-identity publication factory + source performance intelligence.
-- Draft generation is automatic/on-demand; final publication always requires a staff action + reason.

create table if not exists public.black_pages_publication_drafts(
  id uuid primary key default gen_random_uuid(),
  identity_id uuid not null unique references public.black_pages_candidate_identities(id) on delete cascade,
  listing_id uuid unique references public.black_pages_listings(id) on delete set null,
  business_name text not null,
  slug text not null,
  category text not null,
  subcategory text,
  city text not null,
  state text not null,
  address text,
  postal_code text,
  phone text,
  business_email text,
  website_url text,
  instagram_handle text,
  short_description text,
  specialties text[] not null default '{}',
  photo_urls text[] not null default '{}',
  source_names text[] not null default '{}',
  evidence_urls text[] not null default '{}',
  provenance jsonb not null default '{}'::jsonb,
  completeness_score integer not null default 0 check(completeness_score between 0 and 100),
  missing_fields text[] not null default '{}',
  status text not null default 'draft' check(status in('draft','ready','published','rejected')),
  generated_at timestamptz not null default now(),
  reviewed_at timestamptz,
  published_at timestamptz,
  reviewer_user_id uuid,
  reviewer_note text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists black_pages_publication_drafts_status_idx on public.black_pages_publication_drafts(status,completeness_score desc,updated_at desc);
alter table public.black_pages_publication_drafts enable row level security;
revoke all on public.black_pages_publication_drafts from public,anon,authenticated;
grant all on public.black_pages_publication_drafts to service_role;

create or replace function public.black_pages_build_publication_drafts(p_limit integer default 500)
returns jsonb language plpgsql security definer set search_path='pg_catalog','public','auth' as $$
declare v_role text:=coalesce(auth.jwt()->'app_metadata'->>'khg_role','');v_limit integer:=least(5000,greatest(1,coalesce(p_limit,500)));v_count integer:=0;
begin
 if coalesce(auth.role(),'')<>'service_role' and v_role not in('owner','admin','editor') then raise exception 'Staff access required' using errcode='42501';end if;
 with eligible as(
   select i.id identity_id,i.canonical_name business_name,coalesce(nullif(c.category,''),nullif(i.category,''),'business-services') category,
     coalesce(nullif(c.subcategory,''),nullif(i.subcategory,'')) subcategory,
     coalesce(nullif(c.city,''),nullif(i.city,''),'Unknown') city,upper(coalesce(nullif(c.state,''),nullif(i.state,''),'GA')) state,
     c.source_address address,c.source_postal_code postal_code,c.public_phone phone,c.public_email business_email,c.website_url,c.instagram_handle,
     left(coalesce(nullif(c.deep_enrichment_context,''),nullif(c.notes,''),nullif(c.source_subcategory,''),nullif(c.source_category,''),'Black-owned business verified through THE BLACK PAGES source review.'),900) short_description,
     array_remove(array[nullif(c.source_subcategory,''),nullif(c.subcategory,'')],null) specialties,
     array_remove(array_agg(distinct s.source_name),null) source_names,
     array_remove(array_agg(distinct q.external_source_url),null) evidence_urls,
     jsonb_build_object('identity_id',i.id,'canonical_candidate_id',i.canonical_candidate_id,'member_count',i.member_count,'source_count',i.source_count,
       'identity_confidence',i.identity_confidence,'verification_score',i.max_verification_score,
       'candidate_ids',jsonb_agg(distinct q.id),'source_keys',jsonb_agg(distinct case when q.source_external_key like 'external:%' then split_part(q.source_external_key,':',2) else q.source_type end)) provenance
   from public.black_pages_candidate_identities i
   join public.black_pages_candidate_queue c on c.id=i.canonical_candidate_id
   join public.black_pages_candidate_identity_members m on m.identity_id=i.id
   join public.black_pages_candidate_queue q on q.id=m.candidate_id
   left join public.black_pages_external_sources s on s.source_key=case when q.source_external_key like 'external:%' then split_part(q.source_external_key,':',2) else null end
   where i.status='reviewed' and exists(select 1 from public.black_pages_candidate_identity_members mm join public.black_pages_candidate_queue qq on qq.id=mm.candidate_id where mm.identity_id=i.id and qq.pipeline_stage='approved' and qq.ownership_evidence_status='owner_confirmed')
   group by i.id,i.canonical_name,i.category,i.subcategory,i.city,i.state,i.canonical_candidate_id,i.member_count,i.source_count,i.identity_confidence,i.max_verification_score,
     c.category,c.subcategory,c.city,c.state,c.source_address,c.source_postal_code,c.public_phone,c.public_email,c.website_url,c.instagram_handle,c.deep_enrichment_context,c.notes,c.source_subcategory,c.source_category
   order by i.max_verification_score desc,i.updated_at desc limit v_limit
 ), shaped as(
   select e.*,
     lower(trim(both '-' from regexp_replace(e.business_name||'-'||e.city||'-'||e.state,'[^a-zA-Z0-9]+','-','g'))) base_slug,
     (case when e.business_name<>'Unknown' then 20 else 0 end + case when e.category<>'' then 15 else 0 end + case when e.city<>'Unknown' and e.state<>'' then 15 else 0 end +
      case when e.address is not null then 10 else 0 end + case when e.phone is not null then 8 else 0 end + case when e.website_url is not null then 8 else 0 end +
      case when e.instagram_handle is not null then 5 else 0 end + case when e.business_email is not null then 5 else 0 end + case when length(coalesce(e.short_description,''))>=80 then 8 else 0 end +
      case when cardinality(e.evidence_urls)>=1 then 6 else 0 end)::int completeness_score,
     array_remove(array[case when e.business_name='Unknown' then 'business_name' end,case when e.category='' then 'category' end,case when e.city='Unknown' then 'city' end,
       case when e.state='' then 'state' end,case when e.address is null then 'address' end,case when e.phone is null then 'phone' end,case when e.website_url is null then 'website' end,
       case when length(coalesce(e.short_description,''))<80 then 'description' end],null) missing_fields
   from eligible e
 ), upserted as(
   insert into public.black_pages_publication_drafts(identity_id,business_name,slug,category,subcategory,city,state,address,postal_code,phone,business_email,website_url,instagram_handle,short_description,specialties,source_names,evidence_urls,provenance,completeness_score,missing_fields,status,generated_at,updated_at)
   select identity_id,business_name,case when exists(select 1 from public.black_pages_listings l where l.slug=base_slug) then base_slug||'-'||left(identity_id::text,8) else base_slug end,
     category,subcategory,city,state,address,postal_code,phone,business_email,website_url,instagram_handle,short_description,specialties,source_names,evidence_urls,provenance,completeness_score,missing_fields,
     case when completeness_score>=60 and business_name<>'Unknown' and city<>'Unknown' and category<>'' then 'ready' else 'draft' end,now(),now()
   from shaped
   on conflict(identity_id) do update set business_name=excluded.business_name,slug=excluded.slug,category=excluded.category,subcategory=excluded.subcategory,city=excluded.city,state=excluded.state,
     address=excluded.address,postal_code=excluded.postal_code,phone=excluded.phone,business_email=excluded.business_email,website_url=excluded.website_url,instagram_handle=excluded.instagram_handle,
     short_description=excluded.short_description,specialties=excluded.specialties,source_names=excluded.source_names,evidence_urls=excluded.evidence_urls,provenance=excluded.provenance,
     completeness_score=excluded.completeness_score,missing_fields=excluded.missing_fields,status=case when public.black_pages_publication_drafts.status='published' then 'published' else excluded.status end,generated_at=now(),updated_at=now()
   returning id
 )select count(*)::int into v_count from upserted;
 return jsonb_build_object('drafts_built',v_count,'ready',(select count(*) from public.black_pages_publication_drafts where status='ready'),'draft',(select count(*) from public.black_pages_publication_drafts where status='draft'),'published',(select count(*) from public.black_pages_publication_drafts where status='published'));
end $$;
revoke all on function public.black_pages_build_publication_drafts(integer) from public,anon,authenticated;
grant execute on function public.black_pages_build_publication_drafts(integer) to authenticated,service_role;

create or replace function public.black_pages_staff_publication_snapshot(p_limit integer default 250)
returns jsonb language plpgsql security definer set search_path='pg_catalog','public','auth' as $$
declare v_role text:=coalesce(auth.jwt()->'app_metadata'->>'khg_role','');v_rows jsonb;v_counts jsonb;
begin
 if coalesce(auth.role(),'')<>'service_role' and v_role not in('owner','admin','editor') then raise exception 'Staff access required' using errcode='42501';end if;
 perform public.black_pages_build_publication_drafts(5000);
 select jsonb_build_object('ready',count(*) filter(where status='ready'),'draft',count(*) filter(where status='draft'),'published',count(*) filter(where status='published'),'avg_completeness',coalesce(round(avg(completeness_score)),0)) into v_counts from public.black_pages_publication_drafts;
 select coalesce(jsonb_agg(to_jsonb(x) order by x.completeness_score desc,x.updated_at desc),'[]'::jsonb) into v_rows from(
   select id,identity_id,business_name,category,subcategory,city,state,address,postal_code,phone,business_email,website_url,instagram_handle,short_description,specialties,source_names,evidence_urls,completeness_score,missing_fields,status,listing_id,updated_at
   from public.black_pages_publication_drafts order by case status when 'ready' then 1 when 'draft' then 2 else 3 end,completeness_score desc,updated_at desc limit least(500,greatest(1,coalesce(p_limit,250)))
 )x;
 return jsonb_build_object('counts',v_counts,'drafts',v_rows,'generated_at',now());
end $$;
revoke all on function public.black_pages_staff_publication_snapshot(integer) from public,anon,authenticated;
grant execute on function public.black_pages_staff_publication_snapshot(integer) to authenticated,service_role;

create or replace function public.black_pages_staff_publish_draft(p_draft_id uuid,p_reason text)
returns jsonb language plpgsql security definer set search_path='pg_catalog','public','auth' as $$
declare v_role text:=coalesce(auth.jwt()->'app_metadata'->>'khg_role','');v_reason text:=left(btrim(coalesce(p_reason,'')),2000);d public.black_pages_publication_drafts%rowtype;v_listing uuid;
begin
 if v_role not in('owner','admin','editor') then raise exception 'Staff access required' using errcode='42501';end if;
 if v_reason='' then raise exception 'A final publication reason is required';end if;
 select * into d from public.black_pages_publication_drafts where id=p_draft_id for update;if not found then raise exception 'Draft not found';end if;
 if d.status<>'ready' then raise exception 'Draft must be Ready before publication';end if;
 if d.completeness_score<60 or d.business_name='' or d.category='' or d.city='' or d.state='' then raise exception 'Draft does not meet publication minimums';end if;
 if not exists(select 1 from public.black_pages_candidate_identities i where i.id=d.identity_id and i.status='reviewed') then raise exception 'Identity is not human-approved';end if;
 if cardinality(d.evidence_urls)=0 then raise exception 'Publication requires source evidence';end if;
 insert into public.black_pages_listings(business_name,slug,category,subcategory,city,state,short_description,website_url,instagram_handle,featured,status,verified_at,published_at,address,postal_code,phone,business_email,specialties,photo_urls)
 values(d.business_name,d.slug,d.category,d.subcategory,d.city,d.state,d.short_description,d.website_url,d.instagram_handle,false,'approved',now(),now(),d.address,d.postal_code,d.phone,d.business_email,d.specialties,d.photo_urls)
 returning id into v_listing;
 update public.black_pages_publication_drafts set listing_id=v_listing,status='published',reviewed_at=now(),published_at=now(),reviewer_user_id=auth.uid(),reviewer_note=v_reason,updated_at=now() where id=p_draft_id;
 update public.black_pages_candidate_queue q set pipeline_stage='published',updated_at=now() where q.id in(select candidate_id from public.black_pages_candidate_identity_members where identity_id=d.identity_id) and q.pipeline_stage='approved';
 insert into public.black_pages_candidate_activity(candidate_id,activity_type,outcome,details,performed_by)
 select candidate_id,'publication','published',jsonb_build_object('identity_id',d.identity_id,'draft_id',d.id,'listing_id',v_listing,'reason',v_reason,'human_final_publication',true),'staff:'||auth.uid()::text
 from public.black_pages_candidate_identity_members where identity_id=d.identity_id;
 return jsonb_build_object('published',true,'listing_id',v_listing,'identity_id',d.identity_id,'draft_id',d.id);
end $$;
revoke all on function public.black_pages_staff_publish_draft(uuid,text) from public,anon,authenticated;
grant execute on function public.black_pages_staff_publish_draft(uuid,text) to authenticated;

create or replace function public.black_pages_staff_source_performance_snapshot()
returns jsonb language plpgsql security definer set search_path='pg_catalog','public','auth' as $$
declare v_role text:=coalesce(auth.jwt()->'app_metadata'->>'khg_role','');v_rows jsonb;
begin
 if coalesce(auth.role(),'')<>'service_role' and v_role not in('owner','admin','editor') then raise exception 'Staff access required' using errcode='42501';end if;
 select coalesce(jsonb_agg(to_jsonb(x) order by x.active desc,x.unique_businesses desc,x.source_name),'[]'::jsonb) into v_rows from(
   with q as(
     select s.source_key,count(c.id)::int candidate_records,count(distinct m.identity_id)::int unique_businesses,count(distinct nullif(c.city,'Unknown'))::int cities_covered,
       count(distinct m.identity_id) filter(where i.status='reviewed')::int approved_businesses,
       count(distinct d.identity_id) filter(where d.status='published')::int published_businesses
     from public.black_pages_external_sources s left join public.black_pages_candidate_queue c on c.source_external_key like 'external:'||s.source_key||':%'
     left join public.black_pages_candidate_identity_members m on m.candidate_id=c.id left join public.black_pages_candidate_identities i on i.id=m.identity_id
     left join public.black_pages_publication_drafts d on d.identity_id=m.identity_id
     group by s.source_key
   ),j as(
     select source_key,count(*)::int jobs,count(*) filter(where status='completed')::int successful_jobs,count(*) filter(where status='failed')::int failed_jobs,
       coalesce(sum(result_count),0)::int inserted_across_jobs,max(completed_at) filter(where status='completed') last_successful_crawl
     from public.black_pages_external_discovery_jobs group by source_key
   )
   select s.source_key,s.source_name,s.adapter,s.ownership_signal,s.active,s.priority,
     coalesce(q.candidate_records,0) candidate_records,coalesce(q.unique_businesses,0) unique_businesses,
     greatest(coalesce(q.candidate_records,0)-coalesce(q.unique_businesses,0),0) duplicate_records_merged,coalesce(q.cities_covered,0) cities_covered,
     coalesce(q.approved_businesses,0) approved_businesses,coalesce(q.published_businesses,0) published_businesses,
     case when coalesce(q.unique_businesses,0)>0 then round((coalesce(q.approved_businesses,0)::numeric/q.unique_businesses)*100,1) else 0 end verification_conversion_pct,
     coalesce(j.jobs,0) jobs,coalesce(j.successful_jobs,0) successful_jobs,coalesce(j.failed_jobs,0) failed_jobs,coalesce(j.inserted_across_jobs,0) inserted_across_jobs,
     case when coalesce(j.jobs,0)>0 then round((coalesce(j.failed_jobs,0)::numeric/j.jobs)*100,1) else 0 end bad_job_rate_pct,j.last_successful_crawl
   from public.black_pages_external_sources s left join q using(source_key) left join j using(source_key)
 )x;
 return jsonb_build_object('sources',v_rows,'totals',jsonb_build_object(
   'active_sources',(select count(*) from public.black_pages_external_sources where active),
   'candidate_records',(select count(*) from public.black_pages_candidate_queue where source_external_key like 'external:%'),
   'business_identities',(select count(*) from public.black_pages_candidate_identities),
   'publication_ready',(select count(*) from public.black_pages_publication_drafts where status='ready'),
   'published_from_factory',(select count(*) from public.black_pages_publication_drafts where status='published')),'generated_at',now());
end $$;
revoke all on function public.black_pages_staff_source_performance_snapshot() from public,anon,authenticated;
grant execute on function public.black_pages_staff_source_performance_snapshot() to authenticated,service_role;

-- Keep publication drafts current as identities become human-approved.
do $block$ declare r record; begin
 for r in select jobid from cron.job where jobname='black-pages-publication-draft-refresh' loop perform cron.unschedule(r.jobid);end loop;
end $block$;
select cron.schedule('black-pages-publication-draft-refresh','8,18,28,38,48,58 * * * *',$$select public.black_pages_build_publication_drafts(5000);$$);
