-- Whole-word/name-safe taxonomy mapping for the curated Atlanta Eats source.
update public.black_pages_candidate_queue q set
  category='food-beverage',
  subcategory=case
    when lower(q.business_name) ~ '\m(coffee|tea)\M' or lower(q.business_name) in('gilly brew bar','urban grind') then 'coffee-shops'
    when lower(q.business_name) ~ '\mbbq\M' or lower(q.business_name) ~ '\mbarbecue\M' then 'bbq-restaurants'
    when lower(q.business_name) ~ '\mvegan\M' or lower(q.business_name) ~ '\mplant based\M' or lower(q.business_name) ~ '\mplantbaed\M' then 'vegan-restaurants'
    when lower(q.business_name) ~ '\mseafood\M' then 'seafood-restaurants'
    when lower(q.business_name) ~ '\msoul\M' then 'soul-food'
    when lower(q.business_name) ~ '\m(cookie|creamery|donut|donuts)\M' then 'bakeries'
    when lower(q.business_name) ~ '\mtavern\M' or lower(q.business_name) in('the james room','the beverley') then 'bars'
    else 'restaurants' end,
  classification_confidence=.97,classification_method='curated_source_name',classified_at=now(),updated_at=now()
where q.source_external_key like 'external:atlanta_eats_black_restaurants:%';
select public.black_pages_refresh_identity_resolution();
