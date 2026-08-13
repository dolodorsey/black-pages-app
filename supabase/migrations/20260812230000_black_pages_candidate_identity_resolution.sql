-- THE BLACK PAGES: candidate identity resolution.
-- Multiple discoveries of the same local business become one reviewable master identity.
-- This migration does not publish directory listings.

create or replace function public.black_pages_norm_business_name(p_value text)
returns text language sql immutable as $$
  select regexp_replace(lower(coalesce(p_value,'')),'[^a-z0-9]+','','g');
$$;

create or replace function public.black_pages_norm_city(p_value text)
returns text language sql immutable as $$
  select regexp_replace(lower(coalesce(p_value,'')),'[^a-z0-9]+','','g');
$$;

create or replace function public.black_pages_norm_phone(p_value text)
returns text language sql immutable as $$
  select case
    when length(regexp_replace(coalesce(p_value,''),'\D','','g'))=11 and left(regexp_replace(coalesce(p_value,''),'\D','','g'),1)='1'
      then right(regexp_replace(coalesce(p_value,''),'\D','','g'),10)
    when length(regexp_replace(coalesce(p_value,''),'\D','','g'))=10
      then regexp_replace(coalesce(p_value,''),'\D','','g')
    else '' end;
$$;

create or replace function public.black_pages_norm_domain(p_value text)
returns text language sql immutable as $$
  select case
    when lower(split_part(regexp_replace(coalesce(p_value,''),'^https?://(www\.)?','','i'),'/',1)) in
      ('','instagram.com','facebook.com','linkedin.com','x.com','twitter.com','tiktok.com','youtube.com') then ''
    else lower(split_part(regexp_replace(coalesce(p_value,''),'^https?://(www\.)?','','i'),'/',1)) end;
$$;

create or replace function public.black_pages_candidate_identity_key(
  p_name text,p_city text,p_state text,p_website text,p_phone text,p_email text
)
returns text language sql immutable as $$
  with n as (
    select public.black_pages_norm_business_name(p_name) name_key,
      public.black_pages_norm_city(p_city) city_key,
      upper(left(btrim(coalesce(p_state,'')),2)) state_key,
      public.black_pages_norm_domain(p_website) domain_key,
      public.black_pages_norm_phone(p_phone) phone_key,
      lower(btrim(coalesce(p_email,''))) email_key
  )
  select case
    when name_key<>'' and city_key<>'' then 'name_city:'||name_key||'|'||city_key||'|'||state_key
    when name_key<>'' and domain_key<>'' then 'name_web:'||name_key||'|'||domain_key
    when name_key<>'' and phone_key<>'' then 'name_phone:'||name_key||'|'||phone_key
    when name_key<>'' and email_key<>'' then 'name_email:'||name_key||'|'||email_key
    else 'candidate:'||md5(concat_ws('|',coalesce(p_name,''),coalesce(p_city,''),coalesce(p_state,''),coalesce(p_website,''),coalesce(p_phone,''),coalesce(p_email,''))) end
  from n;
$$;

create table if not exists public.black_pages_candidate_identities(
  id uuid primary key default gen_random_uuid(),
  identity_key text not null unique,
  canonical_candidate_id uuid references public.black_pages_candidate_queue(id) on delete set null,
  canonical_name text not null,
  city text,
  state text,
  category text,
  subcategory text,
  max_verification_score numeric not null default 0,
  member_count integer not null default 1,
  source_count integer not null default 0,
  identity_confidence numeric not null default .80 check(identity_confidence between 0 and 1),
  status text not null default 'active' check(status in('active','reviewed','rejected','needs_more_evidence','merged')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.black_pages_candidate_identity_members(
  identity_id uuid not null references public.black_pages_candidate_identities(id) on delete cascade,
  candidate_id uuid not null unique references public.black_pages_candidate_queue(id) on delete cascade,
  match_method text not null default 'deterministic',
  match_score numeric not null default .80 check(match_score between 0 and 1),
  is_canonical boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key(identity_id,candidate_id)
);

create table if not exists public.black_pages_candidate_identity_reviews(
  id uuid primary key default gen_random_uuid(),
  identity_id uuid not null references public.black_pages_candidate_identities(id) on delete cascade,
  decision text not null check(decision in('approve','reject','needs_more_evidence')),
  reason text not null,
  reviewer_user_id uuid,
  reviewer_role text,
  evidence_snapshot jsonb not null default '{}'::jsonb,
  candidates_affected integer not null default 0,
  new_directory_records_published integer not null default 0,
  created_at timestamptz not null default now()
);

create index if not exists black_pages_candidate_identity_members_identity_idx on public.black_pages_candidate_identity_members(identity_id);
create index if not exists black_pages_candidate_identity_reviews_identity_idx on public.black_pages_candidate_identity_reviews(identity_id,created_at desc);
create index if not exists black_pages_candidate_identities_review_idx on public.black_pages_candidate_identities(status,source_count desc,max_verification_score desc);

alter table public.black_pages_candidate_identities enable row level security;
alter table public.black_pages_candidate_identity_members enable row level security;
alter table public.black_pages_candidate_identity_reviews enable row level security;
revoke all on public.black_pages_candidate_identities,public.black_pages_candidate_identity_members,public.black_pages_candidate_identity_reviews from public,anon,authenticated;
grant all on public.black_pages_candidate_identities,public.black_pages_candidate_identity_members,public.black_pages_candidate_identity_reviews to service_role;

create or replace function public.black_pages_resolve_candidate_identities(p_limit integer default 30000)
returns jsonb
language plpgsql security definer set search_path='pg_catalog','public' as $$
declare
  v_limit integer:=least(50000,greatest(1,coalesce(p_limit,30000)));
  v_identity_count integer:=0;v_member_count integer:=0;
begin
  with src as(
    select q.*,
      public.black_pages_candidate_identity_key(q.business_name,q.city,q.state,q.website_url,q.public_phone,q.public_email) identity_key,
      case when q.source_external_key like 'external:%' then split_part(q.source_external_key,':',2) else coalesce(q.source_type,'unknown') end source_label,
      (coalesce(q.verification_score,0)
        +case when nullif(q.external_source_url,'') is not null then 20 else 0 end
        +case when nullif(q.website_url,'') is not null then 8 else 0 end
        +case when nullif(q.source_address,'') is not null then 8 else 0 end
        +case when nullif(q.public_phone,'') is not null then 4 else 0 end
        +case when nullif(q.public_email,'') is not null then 4 else 0 end
        +case when nullif(q.subcategory,'') is not null then 6 else 0 end
        +coalesce(q.priority_score,0)/1000.0) rank_score
    from public.black_pages_candidate_queue q
    where q.pipeline_stage not in('rejected','do_not_contact')
    order by q.priority_score desc nulls last,q.created_at
    limit v_limit
  ), grouped as(
    select identity_key,
      (array_agg(id order by rank_score desc,id))[1] canonical_candidate_id,
      (array_agg(business_name order by rank_score desc,id))[1] canonical_name,
      (array_agg(city order by rank_score desc,id))[1] city,
      (array_agg(state order by rank_score desc,id))[1] state,
      (array_agg(category order by rank_score desc,id))[1] category,
      (array_agg(subcategory order by rank_score desc,id))[1] subcategory,
      coalesce(max(verification_score),0) max_verification_score,
      count(*)::int member_count,
      count(distinct source_label)::int source_count,
      case when count(*)>1 and count(distinct source_label)>1 then .98
           when count(*)>1 then .93
           when identity_key like 'name_city:%' then .90
           else .78 end identity_confidence
    from src group by identity_key
  ), upserted as(
    insert into public.black_pages_candidate_identities(identity_key,canonical_candidate_id,canonical_name,city,state,category,subcategory,max_verification_score,member_count,source_count,identity_confidence,updated_at)
    select identity_key,canonical_candidate_id,canonical_name,city,state,category,subcategory,max_verification_score,member_count,source_count,identity_confidence,now() from grouped
    on conflict(identity_key) do update set
      canonical_candidate_id=excluded.canonical_candidate_id,canonical_name=excluded.canonical_name,
      city=excluded.city,state=excluded.state,category=excluded.category,subcategory=excluded.subcategory,
      max_verification_score=excluded.max_verification_score,member_count=excluded.member_count,source_count=excluded.source_count,
      identity_confidence=excluded.identity_confidence,updated_at=now()
    returning id
  ) select count(*)::int into v_identity_count from upserted;

  with src as(
    select q.id candidate_id,
      public.black_pages_candidate_identity_key(q.business_name,q.city,q.state,q.website_url,q.public_phone,q.public_email) identity_key
    from public.black_pages_candidate_queue q
    where q.pipeline_stage not in('rejected','do_not_contact')
    order by q.priority_score desc nulls last,q.created_at limit v_limit
  ), upserted as(
    insert into public.black_pages_candidate_identity_members(identity_id,candidate_id,match_method,match_score,is_canonical,updated_at)
    select i.id,s.candidate_id,
      case when i.member_count>1 then 'normalized_name_city' else 'deterministic_singleton' end,
      i.identity_confidence,s.candidate_id=i.canonical_candidate_id,now()
    from src s join public.black_pages_candidate_identities i on i.identity_key=s.identity_key
    on conflict(candidate_id) do update set identity_id=excluded.identity_id,match_method=excluded.match_method,
      match_score=excluded.match_score,is_canonical=excluded.is_canonical,updated_at=now()
    returning candidate_id
  ) select count(*)::int into v_member_count from upserted;

  return jsonb_build_object(
    'identities_upserted',v_identity_count,
    'members_resolved',v_member_count,
    'multi_candidate_identities',(select count(*) from public.black_pages_candidate_identities where member_count>1),
    'multi_source_identities',(select count(*) from public.black_pages_candidate_identities where source_count>1),
    'duplicate_rows_collapsed',(select coalesce(sum(member_count-1),0) from public.black_pages_candidate_identities where member_count>1)
  );
end $$;
revoke all on function public.black_pages_resolve_candidate_identities(integer) from public,anon,authenticated;
grant execute on function public.black_pages_resolve_candidate_identities(integer) to service_role;

create or replace view public.black_pages_candidate_identity_summary
with (security_invoker=true) as
select i.id identity_id,i.identity_key,i.canonical_candidate_id,i.canonical_name business_name,i.city,i.state,
  coalesce(c.category,i.category) category,coalesce(c.subcategory,i.subcategory) subcategory,
  i.member_count,i.source_count,i.identity_confidence,i.status,
  greatest(i.max_verification_score,coalesce(c.verification_score,0)) max_verification_score,
  count(*) filter(where q.verification_tier='ready')::int ready_members,
  count(*) filter(where q.verification_tier='research')::int research_members,
  count(*) filter(where q.verification_tier='hold')::int hold_members,
  count(*) filter(where q.pipeline_stage='approved')::int approved_members,
  count(*) filter(where q.pipeline_stage not in('approved','published','rejected','do_not_contact'))::int pending_members,
  count(distinct case when q.source_external_key like 'external:%' then split_part(q.source_external_key,':',2) else q.source_type end)::int observed_sources,
  array_remove(array_agg(distinct case when q.source_external_key like 'external:%' then split_part(q.source_external_key,':',2) else q.source_type end),null) source_keys,
  array_remove(array_agg(distinct s.source_name),null) source_names,
  array_remove(array_agg(distinct q.external_source_url),null) evidence_urls,
  bool_or(s.ownership_signal='certified_black_business') certified_black_source,
  bool_or(s.ownership_signal in('black_chamber_directory','black_business_directory','black_restaurant_week_participant')) strong_directory_source,
  case
    when count(*) filter(where q.verification_tier='ready')>0 and bool_or(nullif(q.external_source_url,'') is not null) then 'ready'
    when count(*) filter(where q.verification_tier in('ready','research'))>0 then 'research'
    else 'hold' end review_tier,
  c.website_url,c.instagram_handle,c.public_email,c.public_phone,c.source_address,c.external_source_url
from public.black_pages_candidate_identities i
join public.black_pages_candidate_identity_members m on m.identity_id=i.id
join public.black_pages_candidate_queue q on q.id=m.candidate_id
left join public.black_pages_external_sources s on s.source_key=case when q.source_external_key like 'external:%' then split_part(q.source_external_key,':',2) else null end
left join public.black_pages_candidate_queue c on c.id=i.canonical_candidate_id
group by i.id,i.identity_key,i.canonical_candidate_id,i.canonical_name,i.city,i.state,i.category,i.subcategory,i.member_count,i.source_count,i.identity_confidence,i.status,i.max_verification_score,
  c.category,c.subcategory,c.verification_score,c.website_url,c.instagram_handle,c.public_email,c.public_phone,c.source_address,c.external_source_url;
revoke all on public.black_pages_candidate_identity_summary from public,anon,authenticated;
grant select on public.black_pages_candidate_identity_summary to service_role;

create or replace function public.black_pages_staff_identity_review_snapshot(p_city text default null,p_limit integer default 500)
returns jsonb
language plpgsql security definer set search_path='pg_catalog','public','auth' as $$
declare v_role text:=coalesce(auth.jwt()->'app_metadata'->>'khg_role','');v_rows jsonb;v_counts jsonb;
begin
  if v_role not in('owner','admin','editor') then raise exception 'Staff access required' using errcode='42501';end if;
  perform public.black_pages_resolve_candidate_identities(50000);
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
grant execute on function public.black_pages_staff_identity_review_snapshot(text,integer) to authenticated;

create or replace function public.black_pages_staff_batch_identity_review(p_identity_ids uuid[],p_decision text,p_reason text)
returns jsonb
language plpgsql security definer set search_path='pg_catalog','public','auth' as $$
declare
  v_role text:=coalesce(auth.jwt()->'app_metadata'->>'khg_role','');
  v_decision text:=lower(btrim(coalesce(p_decision,'')));v_reason text:=left(btrim(coalesce(p_reason,'')),2000);
  v_ids uuid[]:=coalesce(p_identity_ids,'{}'::uuid[]);v_identity uuid;v_candidates integer:=0;v_identities integer:=0;v_snapshot jsonb;v_affected integer:=0;
begin
  if v_role not in('owner','admin','editor') then raise exception 'Staff access required' using errcode='42501';end if;
  if v_decision not in('approve','reject','needs_more_evidence') then raise exception 'Invalid decision';end if;
  if v_reason='' then raise exception 'A human review reason is required';end if;
  if coalesce(array_length(v_ids,1),0)=0 then raise exception 'Select at least one identity';end if;
  if array_length(v_ids,1)>100 then raise exception 'Maximum 100 business identities per review batch';end if;

  foreach v_identity in array v_ids loop
    if not exists(select 1 from public.black_pages_candidate_identities where id=v_identity and status not in('reviewed','rejected')) then continue;end if;
    select jsonb_build_object('identity',to_jsonb(s),'evidence',coalesce((
      select jsonb_agg(jsonb_build_object('candidate_id',q.id,'source_key',case when q.source_external_key like 'external:%' then split_part(q.source_external_key,':',2) else q.source_type end,
        'source_url',q.external_source_url,'ownership_status',q.ownership_evidence_status,'verification_tier',q.verification_tier))
      from public.black_pages_candidate_identity_members m join public.black_pages_candidate_queue q on q.id=m.candidate_id where m.identity_id=v_identity
    ),'[]'::jsonb)) into v_snapshot
    from public.black_pages_candidate_identity_summary s where s.identity_id=v_identity;

    if v_decision='approve' then
      if not exists(
        select 1 from public.black_pages_candidate_identity_members m join public.black_pages_candidate_queue q on q.id=m.candidate_id
        where m.identity_id=v_identity and q.ownership_evidence_status='evidence_found' and nullif(q.external_source_url,'') is not null
      ) then raise exception 'Identity % lacks reviewable ownership/source evidence',v_identity;end if;
      update public.black_pages_candidate_queue q set ownership_evidence_status='owner_confirmed',pipeline_stage='approved',
        assigned_researcher='staff:'||auth.uid()::text,next_action_at=null,
        notes=left(concat_ws(E'\n',nullif(q.notes,''),'Human identity-bundle review approved evidence: '||v_reason),4000),updated_at=now()
      where q.id in(select candidate_id from public.black_pages_candidate_identity_members where identity_id=v_identity)
        and q.pipeline_stage not in('published','rejected','do_not_contact');
      get diagnostics v_affected = row_count;v_candidates:=v_candidates+v_affected;
      update public.black_pages_candidate_verification_reviews r set status='approved',reviewer_user_id=auth.uid(),reviewer_role=v_role,reviewer_note=v_reason,reviewed_at=now(),updated_at=now()
      where r.candidate_id in(select candidate_id from public.black_pages_candidate_identity_members where identity_id=v_identity);
      update public.black_pages_candidate_identities set status='reviewed',updated_at=now() where id=v_identity;
    elsif v_decision='reject' then
      update public.black_pages_candidate_queue q set ownership_evidence_status='not_black_owned',pipeline_stage='rejected',assigned_researcher='staff:'||auth.uid()::text,
        notes=left(concat_ws(E'\n',nullif(q.notes,''),'Human identity-bundle review rejected business: '||v_reason),4000),updated_at=now()
      where q.id in(select candidate_id from public.black_pages_candidate_identity_members where identity_id=v_identity) and q.pipeline_stage not in('published','do_not_contact');
      get diagnostics v_affected = row_count;v_candidates:=v_candidates+v_affected;
      update public.black_pages_candidate_verification_reviews r set status='rejected',reviewer_user_id=auth.uid(),reviewer_role=v_role,reviewer_note=v_reason,reviewed_at=now(),updated_at=now()
      where r.candidate_id in(select candidate_id from public.black_pages_candidate_identity_members where identity_id=v_identity);
      update public.black_pages_candidate_identities set status='rejected',updated_at=now() where id=v_identity;
    else
      update public.black_pages_candidate_queue q set ownership_evidence_status='unreviewed',pipeline_stage='research',assigned_researcher='black-pages-research-worker',next_action_at=now(),
        notes=left(concat_ws(E'\n',nullif(q.notes,''),'Human identity-bundle review requested more evidence: '||v_reason),4000),updated_at=now()
      where q.id in(select candidate_id from public.black_pages_candidate_identity_members where identity_id=v_identity) and q.pipeline_stage not in('published','rejected','do_not_contact');
      get diagnostics v_affected = row_count;v_candidates:=v_candidates+v_affected;
      update public.black_pages_candidate_verification_reviews r set status='needs_more_evidence',reviewer_user_id=auth.uid(),reviewer_role=v_role,reviewer_note=v_reason,reviewed_at=now(),updated_at=now()
      where r.candidate_id in(select candidate_id from public.black_pages_candidate_identity_members where identity_id=v_identity);
      update public.black_pages_candidate_identities set status='needs_more_evidence',updated_at=now() where id=v_identity;
    end if;

    insert into public.black_pages_candidate_identity_reviews(identity_id,decision,reason,reviewer_user_id,reviewer_role,evidence_snapshot,candidates_affected,new_directory_records_published)
    values(v_identity,v_decision,v_reason,auth.uid(),v_role,v_snapshot,
      (select count(*) from public.black_pages_candidate_identity_members where identity_id=v_identity),0);

    insert into public.black_pages_candidate_activity(candidate_id,activity_type,outcome,details,performed_by)
    select candidate_id,'verification_note',v_decision,jsonb_build_object('identity_id',v_identity,'reason',v_reason,'identity_bundle_review',true,'automated_decision',false,'new_directory_record_published',false),'staff:'||auth.uid()::text
    from public.black_pages_candidate_identity_members where identity_id=v_identity;
    v_identities:=v_identities+1;
  end loop;

  return jsonb_build_object('identities_reviewed',v_identities,'candidate_records_advanced',v_candidates,'new_directory_records_published',0);
end $$;
revoke all on function public.black_pages_staff_batch_identity_review(uuid[],text,text) from public,anon,authenticated;
grant execute on function public.black_pages_staff_batch_identity_review(uuid[],text,text) to authenticated;
