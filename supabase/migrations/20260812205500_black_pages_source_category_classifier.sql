-- Normalize chamber/source category labels before subcategory classification.
create or replace function public.black_pages_source_category_slug(p_value text)
returns text language sql immutable set search_path='pg_catalog','public' as $$
select case
  when lower(coalesce(p_value,'')) in ('business services','human resources') then 'business-services'
  when lower(coalesce(p_value,'')) in ('restaurants','food & beverage','food and beverage') then 'food-beverage'
  when lower(coalesce(p_value,'')) in ('finance & banking','finance and banking','finance') then 'financial-services'
  when lower(coalesce(p_value,'')) in ('health care & health services','health and wellness','health & wellness','healthcare & wellness') then 'health'
  when lower(coalesce(p_value,'')) in ('personal care','salon, barber & hair care','salon barber & hair care') then 'beauty-wellness'
  when lower(coalesce(p_value,''))='real estate' then 'real-estate'
  when lower(coalesce(p_value,''))='retail' then 'retail'
  when lower(coalesce(p_value,'')) in ('organizations','non-profit','nonprofit') then 'community'
  when lower(coalesce(p_value,''))='media' then 'creative-media'
  when lower(coalesce(p_value,'')) in ('arts & entertainment','arts and entertainment') then 'arts-culture'
  when lower(coalesce(p_value,''))='nightlife' then 'nightlife-entertainment'
  when lower(coalesce(p_value,''))='legal' then 'legal-services'
  when lower(coalesce(p_value,''))='cleaning services' then 'cleaning-maintenance'
  when lower(coalesce(p_value,''))='construction, planning & engineering' then 'construction-trades'
  when lower(coalesce(p_value,''))='education & training' then 'education'
  when lower(coalesce(p_value,''))='travel & lodging' then 'hospitality-travel'
  when lower(coalesce(p_value,''))='auto logistics & transportation' then 'logistics-transportation'
  when lower(coalesce(p_value,''))='personal services & care' then 'personal-services'
  else null end;
$$;

insert into public.black_pages_taxonomy_aliases(alias,category_slug,subcategory_slug,confidence) values
('cpa','financial-services','accountants',.98),('accounting firm','financial-services','accountants',.98),
('bookkeeping','business-services','bookkeeping-services',.98),('bookkeeper','financial-services','bookkeepers',.96),
('mortgage','financial-services','mortgage-brokers',.94),('credit repair','financial-services','credit-repair',.98),
('clinic','health','primary-care',.78),('physical therapy','health','physical-therapy',.99),('mental health','health','mental-health-clinics',.93),
('counseling','health','mental-health-clinics',.86),('lactation','childcare-family','lactation-consultants',.99),
('moving','logistics-transportation','moving-companies',.96),('moving company','logistics-transportation','moving-companies',.99),
('interior design','home-services','interior-designers',.98),('interior designer','home-services','interior-designers',.99),
('property management','real-estate','property-management',.99),('security','security-safety','security-companies',.91),
('investigation','security-safety','private-investigators',.96),('investigator','security-safety','private-investigators',.97),
('catering','food-beverage','catering',.97),('caterer','food-beverage','caterers',.97),
('academy','education','adult-education',.80),('training center','education','adult-education',.87)
on conflict(alias) do update set category_slug=excluded.category_slug,subcategory_slug=excluded.subcategory_slug,confidence=excluded.confidence,active=true;

create or replace function public.black_pages_auto_classify_batch(p_limit integer default 10000)
returns jsonb language plpgsql security definer set search_path='pg_catalog','public','extensions' as $$
declare v_limit integer:=least(30000,greatest(1,coalesce(p_limit,10000))); v_category integer:=0; v_exact integer:=0; v_fuzzy integer:=0;
begin
  with targets as (
    select id,public.black_pages_source_category_slug(source_category) category_slug
    from public.black_pages_candidate_queue
    where category is null and source_category is not null and pipeline_stage not in ('rejected','do_not_contact')
      and public.black_pages_source_category_slug(source_category) is not null
    order by priority_score desc,id limit v_limit
  ), upd as (
    update public.black_pages_candidate_queue q set category=t.category_slug,
      classification_method=coalesce(q.classification_method,'source_category'),
      classification_confidence=greatest(coalesce(q.classification_confidence,0),.84),classified_at=coalesce(q.classified_at,now()),updated_at=now()
    from targets t where q.id=t.id returning q.id
  ) select count(*)::int into v_category from upd;

  with targets as (
    select q.id,lower(concat_ws(' ',q.source_subcategory,q.source_category,q.category,q.business_name)) haystack,
      lower(coalesce(q.source_subcategory,'')) source_subcategory,lower(coalesce(q.source_category,'')) source_category
    from public.black_pages_candidate_queue q
    where (q.subcategory is null or btrim(q.subcategory)='') and q.pipeline_stage not in ('rejected','do_not_contact')
    order by q.priority_score desc,q.id limit v_limit
  ), matches as (
    select distinct on(t.id) t.id,a.category_slug,a.subcategory_slug,a.confidence,
      case when t.source_subcategory=a.alias then 5 when t.source_category=a.alias then 4 else 2 end rank
    from targets t join public.black_pages_taxonomy_aliases a on a.active and
      (t.source_subcategory=a.alias or t.source_category=a.alias or t.haystack like '%'||a.alias||'%')
    order by t.id,rank desc,a.confidence desc,length(a.alias) desc
  ), upd as (
    update public.black_pages_candidate_queue q set category=m.category_slug,subcategory=m.subcategory_slug,
      classification_confidence=m.confidence,classification_method='alias',classified_at=now(),updated_at=now()
    from matches m where q.id=m.id returning q.id
  ) select count(*)::int into v_exact from upd;

  with targets as (
    select q.id,q.category category_slug,lower(concat_ws(' ',q.source_subcategory,q.source_category,q.business_name)) hint
    from public.black_pages_candidate_queue q
    where (q.subcategory is null or btrim(q.subcategory)='') and q.category is not null
      and q.pipeline_stage not in ('rejected','do_not_contact')
    order by q.priority_score desc,q.id limit v_limit
  ), scored as (
    select distinct on(t.id) t.id,s.category_slug,s.slug subcategory_slug,
      greatest(similarity(t.hint,lower(s.name)),similarity(t.hint,replace(lower(s.slug),'-',' '))) score
    from targets t join public.black_pages_subcategories s on s.active and s.category_slug=t.category_slug
    where greatest(similarity(t.hint,lower(s.name)),similarity(t.hint,replace(lower(s.slug),'-',' ')))>=.30
    order by t.id,score desc,s.slug
  ), upd as (
    update public.black_pages_candidate_queue q set subcategory=s.subcategory_slug,
      classification_confidence=least(.89,s.score),classification_method='fuzzy_taxonomy',classified_at=now(),updated_at=now()
    from scored s where q.id=s.id returning q.id
  ) select count(*)::int into v_fuzzy from upd;

  return jsonb_build_object('source_category_mapped',v_category,'alias_classified',v_exact,'fuzzy_classified',v_fuzzy,
    'classified_total',v_exact+v_fuzzy,'remaining_unclassified',(select count(*) from public.black_pages_candidate_queue where subcategory is null or btrim(subcategory)=''));
end; $$;
revoke all on function public.black_pages_auto_classify_batch(integer) from public,anon,authenticated;
grant execute on function public.black_pages_auto_classify_batch(integer) to service_role;
select public.black_pages_auto_classify_batch(30000);
