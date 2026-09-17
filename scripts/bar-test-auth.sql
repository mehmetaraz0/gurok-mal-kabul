-- ============================================================================
-- TEST KIMLIK KATMANI — URETIME UYGULANMAZ
-- ============================================================================
-- supabase-shim.sql auth.uid()'i eski 'request.jwt.claim.sub' ayarindan okur.
-- PostgREST v12 ve Supabase kimligi 'request.jwt.claims' JSON'unda tasir.
-- Supabase'in kendi auth.uid() tanimi IKISINE de bakar; burada ayni tanim
-- kurulur. Shim kilitli dosya oldugu icin degistirilmez, ustune yazilir.
-- ============================================================================
create or replace function auth.uid() returns uuid language sql stable as $$
  select nullif(coalesce(
    current_setting('request.jwt.claim.sub', true),
    (nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub')
  ), '')::uuid;
$$;

create or replace function auth.role() returns text language sql stable as $$
  select nullif(coalesce(
    current_setting('request.jwt.claim.role', true),
    (nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role')
  ), '');
$$;
