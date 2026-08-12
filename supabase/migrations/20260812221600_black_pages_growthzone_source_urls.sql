-- Normalize GrowthZone sources to FindStartsWith URLs so A-Z sharding is deterministic.
update public.black_pages_external_sources set base_url='https://business.gwbcc.org/member-directory/FindStartsWith?term=%23%21',updated_at=now()
where source_key='greater_washington_black_chamber';
