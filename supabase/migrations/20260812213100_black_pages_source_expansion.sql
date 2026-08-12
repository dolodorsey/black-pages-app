-- THE BLACK PAGES: expand acquisition sources beyond chambers.

insert into public.black_pages_external_sources(source_key,source_name,adapter,base_url,ownership_signal,credential_secret_name,active,priority,notes) values
('black_restaurant_week_national','Black Restaurant Week National Directory','black_restaurant_week','https://blackrestaurantweeks.com/brw-campaigns/','black_restaurant_week_participant',null,true,125,'Public national Black Restaurant Week directory; human verification required before publication.'),
('greater_washington_black_chamber','Greater Washington DC Black Chamber','growthzone','https://business.gwbcc.org/member-directory/Find','black_chamber_directory',null,false,112,'Public GrowthZone member directory; activate after parser QA.'),
('california_black_chamber','California Black Chamber of Commerce','growthzone','https://business.calbcc.org/directory/Find','black_chamber_directory',null,false,108,'Public GrowthZone member directory; activate after parser QA.'),
('capital_black_chamber','Capital Black Chamber of Commerce','growthzone','https://members.sacblackchamber.org/directory/Find','black_chamber_directory',null,false,108,'Public GrowthZone member directory; activate after parser QA.'),
('memphis_black_restaurant_week','Memphis Black Restaurant Week','black_restaurant_week_city','https://www.blackrestaurantweek.com/menu','black_restaurant_week_participant',null,false,104,'Black-owned restaurant participant source; dedicated parser QA required.'),
('long_beach_black_restaurant_week','Long Beach Black Restaurant Week','black_restaurant_week_city','https://lbblackrestaurantweek.com/participating-restaurants','black_restaurant_week_participant',null,false,104,'Black-owned food-business participant source; dedicated parser QA required.'),
('san_antonio_black_restaurant_week','Black Restaurant Week San Antonio','black_restaurant_week_city','https://www.blackrestaurantweeksanantonio.com/brwsa-2026-participants','black_restaurant_week_participant',null,false,104,'Structured public participant table; dedicated parser QA required.'),
('byblack_public','ByBlack Public Directory','byblack_public','https://byblack.us/search','black_business_directory',null,false,115,'Public Black-owned business search pages are visible without an API key. Keep inactive until parser QA proves stable field extraction.')
on conflict(source_key) do update set
  source_name=excluded.source_name,adapter=excluded.adapter,base_url=excluded.base_url,
  ownership_signal=excluded.ownership_signal,credential_secret_name=excluded.credential_secret_name,
  priority=excluded.priority,notes=excluded.notes,updated_at=now();

insert into public.black_pages_taxonomy_aliases(alias,category_slug,subcategory_slug,confidence) values
('soul food','food-beverage','soul-food',.99),('barbecue','food-beverage','bbq-restaurants',.99),('bbq','food-beverage','bbq-restaurants',.99),
('caribbean','food-beverage','caribbean-restaurants',.99),('vegan','food-beverage','vegan-restaurants',.99),('seafood','food-beverage','seafood-restaurants',.99),
('african','food-beverage','african-restaurants',.98),('creole','food-beverage','restaurants',.92),('cajun','food-beverage','restaurants',.92),
('bakery','food-beverage','bakeries',.99),('dessert','food-beverage','dessert-shops',.94),('juice','food-beverage','juice-bars',.96),('smoothie','food-beverage','juice-bars',.93),
('pizzeria','food-beverage','restaurants',.95),('pizza','food-beverage','restaurants',.95),('steakhouse','food-beverage','restaurants',.95),('food truck','food-beverage','food-trucks',.99)
on conflict(alias) do update set category_slug=excluded.category_slug,subcategory_slug=excluded.subcategory_slug,confidence=excluded.confidence,active=true;

create or replace function public.black_pages_queue_source_scan(p_source_key text,p_pages integer default 1)
returns jsonb
language plpgsql security definer set search_path='pg_catalog','public','auth' as $$
declare
  v_role text:=coalesce(auth.jwt()->'app_metadata'->>'khg_role','');
  v_source public.black_pages_external_sources%rowtype;
  v_pages integer:=least(100,greatest(1,coalesce(p_pages,1)));
  v_page integer;v_url text;v_created integer:=0;
begin
  if coalesce(auth.role(),'')<>'service_role' and v_role not in('owner','admin','editor') then
    raise exception 'Staff access required' using errcode='42501';
  end if;
  select * into v_source from public.black_pages_external_sources where source_key=p_source_key;
  if not found then raise exception 'Unknown source'; end if;
  if not v_source.active then raise exception 'Source is not active'; end if;
  for v_page in 1..v_pages loop
    if v_source.adapter='black_restaurant_week' then
      v_url:=case when v_page=1 then v_source.base_url else rtrim(v_source.base_url,'/')||'/page/'||v_page::text||'/' end;
    elsif v_source.adapter='growthzone' then
      v_url:=v_source.base_url;
      if v_page>1 then exit; end if;
    else
      raise exception 'Bulk source scan not configured for adapter %',v_source.adapter;
    end if;
    insert into public.black_pages_external_discovery_jobs(source_key,city,state,category_slug,page_offset,request_url,requested_count,requested_by,status,attempt_count,error_message,updated_at)
    values(v_source.source_key,null,null,null,(v_page-1)*10,v_url,case when v_source.adapter='growthzone' then 50 else 10 end,auth.uid(),'pending',0,null,now())
    on conflict(source_key,request_url) do update set status='pending',attempt_count=0,error_message=null,updated_at=now();
    v_created:=v_created+1;
  end loop;
  return jsonb_build_object('source',v_source.source_key,'jobs_queued',v_created,'pages',v_created);
end $$;
revoke all on function public.black_pages_queue_source_scan(text,integer) from public,anon,authenticated;
grant execute on function public.black_pages_queue_source_scan(text,integer) to authenticated,service_role;
