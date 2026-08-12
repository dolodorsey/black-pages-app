-- Identity-quality guard: generic placeholder labels must never merge unrelated records.
create or replace function public.black_pages_identity_name_is_generic(p_value text)
returns boolean language sql immutable as $$
  select public.black_pages_norm_business_name(p_value) in (
    '','business','company','organization','organisation','venue','festival','promoter','creator','celebrity','media','artist',
    'restaurant','nightclub','bar','lounge','event','events','vendor','vendors','supplier','contractor','consultant','professional',
    'store','retail','service','services','other','unknown','na','none'
  );
$$;

create or replace function public.black_pages_norm_city(p_value text)
returns text language sql immutable as $$
  select case when regexp_replace(lower(coalesce(p_value,'')),'[^a-z0-9]+','','g') in ('','unknown','na','none','national','online')
    then '' else regexp_replace(lower(coalesce(p_value,'')),'[^a-z0-9]+','','g') end;
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
      lower(btrim(coalesce(p_email,''))) email_key,
      public.black_pages_identity_name_is_generic(p_name) generic_name
  )
  select case
    when generic_name then 'candidate:'||md5(concat_ws('|',coalesce(p_name,''),coalesce(p_city,''),coalesce(p_state,''),coalesce(p_website,''),coalesce(p_phone,''),coalesce(p_email,''),random()::text))
    when name_key<>'' and city_key<>'' then 'name_city:'||name_key||'|'||city_key||'|'||state_key
    when name_key<>'' and domain_key<>'' then 'name_web:'||name_key||'|'||domain_key
    when name_key<>'' and phone_key<>'' then 'name_phone:'||name_key||'|'||phone_key
    when name_key<>'' and email_key<>'' then 'name_email:'||name_key||'|'||email_key
    else 'candidate:'||md5(concat_ws('|',coalesce(p_name,''),coalesce(p_city,''),coalesce(p_state,''),coalesce(p_website,''),coalesce(p_phone,''),coalesce(p_email,''))) end
  from n;
$$;
