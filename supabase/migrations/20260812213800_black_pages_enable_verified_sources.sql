-- Source QA state: Black Restaurant Week and Greater Washington are live; California/Sacramento stay staged until phone parsing is hardened.
update public.black_pages_external_sources set active=true,updated_at=now() where source_key in('black_restaurant_week_national','greater_washington_black_chamber');
update public.black_pages_external_sources set active=false,updated_at=now() where source_key in('california_black_chamber','capital_black_chamber');
