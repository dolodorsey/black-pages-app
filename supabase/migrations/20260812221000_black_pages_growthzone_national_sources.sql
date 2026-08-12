-- National GrowthZone Black Chamber source registry.
-- Sources remain private discovery evidence and never auto-publish.

update public.black_pages_external_sources set base_url='https://business.calbcc.org/directory/FindStartsWith?term=%23%21',adapter='growthzone_v2',updated_at=now()
where source_key='california_black_chamber';
update public.black_pages_external_sources set base_url='https://sacramentoblackchamberofcommerce.growthzoneapp.com/directory/FindStartsWith?term=%23%21',adapter='growthzone_v2',updated_at=now()
where source_key='capital_black_chamber';

insert into public.black_pages_external_sources(source_key,source_name,adapter,base_url,ownership_signal,credential_secret_name,active,priority,notes) values
('virginia_black_business_directory','Virginia Black Business Directory / Virginia Black Chamber','growthzone_v2','https://members.vablackbusinessdirectory.org/directory/FindStartsWith?term=%23%21','black_chamber_directory',null,false,114,'Large public GrowthZone directory; chamber/directory evidence requires human ownership review.'),
('greater_southwest_black_chamber','Greater Southwest Black Chamber of Commerce','growthzone_v2','https://members.gswbcc.net/directory','black_chamber_directory',null,false,104,'Public GrowthZone directory. Activate only after parser QA.')
on conflict(source_key) do update set source_name=excluded.source_name,adapter=excluded.adapter,base_url=excluded.base_url,ownership_signal=excluded.ownership_signal,priority=excluded.priority,notes=excluded.notes,updated_at=now();
