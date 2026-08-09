-- BLACK PAGES P0: RLS init-plan rewrite plus the missing foreign-key index.
--
-- Every policy below is recreated with identical semantics; the only change is
-- that per-row `auth.uid()` / `auth.jwt()` calls become `(select auth.uid())` /
-- `(select auth.jwt())` so Postgres evaluates them once per statement
-- (InitPlan) instead of once per row.
--
-- `black_pages_applications.reviewed_by` is a foreign key with no covering
-- index, which forces sequential scans on reviewer lookups and on parent-side
-- deletes.

create index if not exists black_pages_applications_reviewed_by_idx
  on public.black_pages_applications (reviewed_by);

-- public.black_pages_claims

drop policy if exists black_pages_claims_own_select on public.black_pages_claims;
create policy black_pages_claims_own_select
  on public.black_pages_claims
  for select to authenticated
  using (claimant_auth_id = (select auth.uid()));

drop policy if exists black_pages_claims_own_insert on public.black_pages_claims;
create policy black_pages_claims_own_insert
  on public.black_pages_claims
  for insert to authenticated
  with check (claimant_auth_id = (select auth.uid()));

drop policy if exists black_pages_claims_own_update on public.black_pages_claims;
create policy black_pages_claims_own_update
  on public.black_pages_claims
  for update to authenticated
  using (claimant_auth_id = (select auth.uid()) and status = 'pending')
  with check (claimant_auth_id = (select auth.uid()));

-- public.black_pages_favorites

drop policy if exists black_pages_favorites_own_all on public.black_pages_favorites;
create policy black_pages_favorites_own_all
  on public.black_pages_favorites
  for all to authenticated
  using (user_auth_id = (select auth.uid()))
  with check (user_auth_id = (select auth.uid()));

-- public.black_pages_reviews

drop policy if exists black_pages_reviews_public_select on public.black_pages_reviews;
create policy black_pages_reviews_public_select
  on public.black_pages_reviews
  for select to anon, authenticated
  using (status = 'approved' or reviewer_auth_id = (select auth.uid()));

drop policy if exists black_pages_reviews_own_insert on public.black_pages_reviews;
create policy black_pages_reviews_own_insert
  on public.black_pages_reviews
  for insert to authenticated
  with check (reviewer_auth_id = (select auth.uid()));

drop policy if exists black_pages_reviews_own_update on public.black_pages_reviews;
create policy black_pages_reviews_own_update
  on public.black_pages_reviews
  for update to authenticated
  using (reviewer_auth_id = (select auth.uid()) and status = 'pending')
  with check (reviewer_auth_id = (select auth.uid()));

-- staff policies

drop policy if exists black_pages_staff_listings on public.black_pages_listings;
create policy black_pages_staff_listings
  on public.black_pages_listings
  for all to authenticated
  using (
    coalesce(((select auth.jwt()) -> 'app_metadata' ->> 'khg_role'), '')
      = any (array['owner', 'admin', 'editor'])
  )
  with check (
    coalesce(((select auth.jwt()) -> 'app_metadata' ->> 'khg_role'), '')
      = any (array['owner', 'admin', 'editor'])
  );

drop policy if exists black_pages_staff_applications on public.black_pages_applications;
create policy black_pages_staff_applications
  on public.black_pages_applications
  for all to authenticated
  using (
    coalesce(((select auth.jwt()) -> 'app_metadata' ->> 'khg_role'), '')
      = any (array['owner', 'admin', 'editor'])
  )
  with check (
    coalesce(((select auth.jwt()) -> 'app_metadata' ->> 'khg_role'), '')
      = any (array['owner', 'admin', 'editor'])
  );
