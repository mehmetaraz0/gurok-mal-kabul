-- ============================================================================
-- SUPABASE SHIM — düz PostgreSQL konteynerinde Supabase dökümü yüklemek için
-- ============================================================================
-- Supabase'den alınan bir şema dökümü, o platformda hazır gelen rollere,
-- şemalara ve eklentilere REFERANS VERİR ama onları OLUŞTURMAZ. Düz bir
-- postgres imajında döküm bu yüzden hata verir.
--
-- Bu dosya yalnızca o iskeleyi kurar. İş mantığı İÇERMEZ; dökümün kendisini
-- doğrulamak için vardır. Üretime ASLA uygulanmaz.
--
-- Kullanım: scripts/dokum-dogrula.mjs bunu dökümden ÖNCE yükler.
-- ============================================================================

-- Supabase rolleri. Döküm bunlara GRANT verdiği için önce var olmalılar.
do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'anon')
    then create role anon nologin noinherit; end if;
  if not exists (select 1 from pg_roles where rolname = 'authenticated')
    then create role authenticated nologin noinherit; end if;
  if not exists (select 1 from pg_roles where rolname = 'service_role')
    then create role service_role nologin noinherit bypassrls; end if;
  if not exists (select 1 from pg_roles where rolname = 'authenticator')
    then create role authenticator nologin noinherit; end if;
  if not exists (select 1 from pg_roles where rolname = 'supabase_admin')
    then create role supabase_admin nologin; end if;
  if not exists (select 1 from pg_roles where rolname = 'supabase_auth_admin')
    then create role supabase_auth_admin nologin; end if;
  if not exists (select 1 from pg_roles where rolname = 'dashboard_user')
    then create role dashboard_user nologin; end if;
end;
$$;

-- Üretimdeki devralma zinciri (preflight 02'de doğrulandı): authenticator ve
-- postgres, üç PostgREST rolünün de üyesidir. Devralınan izinler tablo bazlı
-- revoke'u delebildiği için bu zincir doğrulamada ÖNEMLİDİR.
grant anon, authenticated, service_role to authenticator;
grant anon, authenticated, service_role to postgres;

create schema if not exists auth;
create schema if not exists extensions;
create schema if not exists graphql;
create schema if not exists graphql_public;
create schema if not exists storage;
create schema if not exists realtime;

grant usage on schema public to anon, authenticated, service_role;

-- Eklentiler Supabase'de `extensions` şemasındadır; pin_ayarla/pin_dogrula
-- search_path'inde bu şemayı taşır ve bcrypt oradan çözülür.
create extension if not exists pgcrypto with schema extensions;
create extension if not exists "uuid-ossp" with schema extensions;
create extension if not exists btree_gist with schema extensions;

-- auth.uid() / auth.role(): GoTrue'nun sağladığı sözleşmenin aynısı.
-- JWT yerine oturum ayarından okur; testte kimlik değiştirmeyi mümkün kılar.
create or replace function auth.uid() returns uuid language sql stable as $$
  select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid;
$$;

create or replace function auth.role() returns text language sql stable as $$
  select nullif(current_setting('request.jwt.claim.role', true), '');
$$;

create or replace function auth.email() returns text language sql stable as $$
  select nullif(current_setting('request.jwt.claim.email', true), '');
$$;

-- Döküm auth.users'a foreign key taşıyabilir (kullanicilar.auth_user_id).
create table if not exists auth.users (
  id uuid primary key,
  email text,
  created_at timestamptz default now()
);

grant usage on schema auth to anon, authenticated, service_role;
