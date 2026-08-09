-- BLACK PAGES P0: remove browser-facing execute privileges on privileged
-- SECURITY DEFINER approval/verification routines. Only service_role may call them.

revoke all on function public.black_pages_approve_owner_claim(uuid, text)
  from public, anon, authenticated;
revoke all on function public.black_pages_initialize_claim_verification()
  from public, anon, authenticated;

grant execute on function public.black_pages_approve_owner_claim(uuid, text)
  to service_role;
grant execute on function public.black_pages_initialize_claim_verification()
  to service_role;

alter function public.black_pages_approve_owner_claim(uuid, text)
  set search_path = pg_catalog, public;
alter function public.black_pages_initialize_claim_verification()
  set search_path = pg_catalog, public;
