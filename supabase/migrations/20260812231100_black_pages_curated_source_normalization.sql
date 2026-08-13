-- Normalize the QA-passed Atlanta Eats source and retain it as curated/research evidence.
update public.black_pages_candidate_queue q set
  city=coalesce(
    substring(q.source_address from '(?i)(Atlanta|College Park|Kennesaw|Forest Park|Lawrenceville|Stone Mountain|Jonesboro|Smyrna|Duluth|Marietta|Conyers|Riverdale|Dunwoody|Suwanee|Decatur|Hapeville|East Point|Fairburn|Fayetteville|Douglasville|Norcross|Alpharetta|Roswell|Sandy Springs|Lithonia|Stonecrest)\s*,?\s*(?:Georgia|GA)\s*,?\s*\d{5}'),
    q.city
  ),
  category=case when lower(q.business_name) similar to '%(tavern|bar|the james room|the beverley)%' then 'food-beverage' else 'food-beverage' end,
  subcategory=case
    when lower(q.business_name) similar to '%(coffee|tea|brew bar|urban grind)%' then 'coffee-shops'
    when lower(q.business_name) like '%bbq%' then 'bbq-restaurants'
    when lower(q.business_name) similar to '%(vegan|plant based|plantbaed)%' then 'vegan-restaurants'
    when lower(q.business_name) like '%seafood%' then 'seafood-restaurants'
    when lower(q.business_name) like '%soul%' then 'soul-food'
    when lower(q.business_name) similar to '%(cookie|creamery|donut)%' then 'bakeries'
    when lower(q.business_name) similar to '%(tavern|the james room|the beverley)%' then 'bars'
    else 'restaurants' end,
  classification_confidence=greatest(coalesce(q.classification_confidence,0),.94),classification_method='curated_source_name',classified_at=now(),
  verification_score=greatest(coalesce(q.verification_score,0),62),verification_tier='research',
  verification_reasons=array(select distinct x from unnest(coalesce(q.verification_reasons,'{}'::text[])||array['curated_black_business_guide','source_profile_present']) x),
  verification_prechecked_at=now(),updated_at=now()
where q.source_external_key like 'external:atlanta_eats_black_restaurants:%';

-- Cross-evidence registries: valuable for business enrichment, but not sufficient Black-ownership proof.
insert into public.black_pages_external_sources(source_key,source_name,adapter,base_url,ownership_signal,credential_secret_name,active,priority,notes) values
('georgia_tech_supplier_diversity_reference','Georgia Tech Supplier Diversity','cross_evidence_reference','https://procurement.gatech.edu/Suppliers','minority_supplier_reference',null,false,40,'University supplier-diversity reference only. Minority/diverse supplier status is not Black-ownership proof.'),
('emory_supplier_diversity_reference','Emory Supplier Diversity & Inclusion','cross_evidence_reference','https://finance.emory.edu/home/procurement/supplier-engagement/index.html','minority_supplier_reference',null,false,40,'University supplier-diversity reference only. Diverse supplier status spans multiple groups and is not Black-ownership proof.')
on conflict(source_key) do update set source_name=excluded.source_name,adapter=excluded.adapter,base_url=excluded.base_url,ownership_signal=excluded.ownership_signal,active=false,priority=excluded.priority,notes=excluded.notes,updated_at=now();

-- Weekly refresh plus lightweight drain; inactive/staged trusted sources are never reset by the refresh function.
do $block$ declare r record;begin
 for r in select jobid from cron.job where jobname in('black-pages-trusted-source-refresh','black-pages-trusted-source-drain') loop perform cron.unschedule(r.jobid);end loop;
end $block$;
select cron.schedule('black-pages-trusted-source-refresh','52 4 * * 1',$$select public.black_pages_refresh_trusted_sources();$$);
select cron.schedule('black-pages-trusted-source-drain','7,22,37,52 * * * *',$$select public.black_pages_internal_dispatch_worker('trusted-source',5,1);$$);

select public.black_pages_refresh_identity_resolution();
