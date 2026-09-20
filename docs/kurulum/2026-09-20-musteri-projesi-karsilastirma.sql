-- ===========================================================================
-- MUSTERI PROJESI (bar/QR, ref udjpcsjifgdzvfflezaa) — SALT OKUMA KARSILASTIRMA
-- ===========================================================================
-- AMAC: canli musteri projesinin semasini repo'daki beklenen tanimla
--       (docs/kurulum/musteri-projesi/01-musteri-sema.sql + 03-menu-yayin.sql)
--       karsilastirmak. HICBIR YAZMA YOK.
--
-- KULLANIM (ana proje degil, MUSTERI projesi):
--   .\docs\kurulum\sql-uygula.ps1 -Dosya docs\kurulum\2026-09-20-musteri-projesi-karsilastirma.sql `
--      -SaltOkuma -Sunucu aws-0-<bolge>.pooler.supabase.com -Kullanici postgres.udjpcsjifgdzvfflezaa
--   (bolge ve parola musteri projesinin kendi bilgileridir; ana projeninkiyle ayni degildir)
--
-- NOT: anon anahtarla yapilabilen yuzeysel kontrol zaten yapildi (2026-09-20):
--   menu_urunler anon'a acik ve otel_id kolonu var; masa_tokenlari ve siparis_arsiv
--   anon'a bos donuyor. Bu dosya politika/fonksiyon duzeyinde derin karsilastirmadir.
-- ===========================================================================
begin transaction read only;

\echo '=== 1. TABLOLAR (beklenen: menu_urunler, masa_tokenlari, siparis_arsiv) ==='
select table_name
  from information_schema.tables
 where table_schema = 'public' and table_type = 'BASE TABLE'
 order by table_name;

\echo '=== 2. KOLONLAR ==='
select table_name, ordinal_position, column_name, data_type, is_nullable, column_default
  from information_schema.columns
 where table_schema = 'public'
 order by table_name, ordinal_position;

\echo '=== 3. RLS ACIK MI ==='
select c.relname, c.relrowsecurity, c.relforcerowsecurity
  from pg_class c join pg_namespace n on n.oid = c.relnamespace
 where n.nspname = 'public' and c.relkind = 'r'
 order by c.relname;

\echo '=== 4. POLITIKALAR (beklenen: yalniz menu_anon_select) ==='
select tablename, policyname, permissive, roles::text, cmd, qual, with_check
  from pg_policies where schemaname = 'public'
 order by tablename, policyname;

\echo '=== 5. ANON / AUTHENTICATED TABLO HAKLARI ==='
select table_name, grantee, string_agg(privilege_type, ',' order by privilege_type) as haklar
  from information_schema.role_table_grants
 where table_schema = 'public' and grantee in ('anon','authenticated','service_role')
 group by table_name, grantee
 order by table_name, grantee;

\echo '=== 6. FONKSIYONLAR (beklenen: masa_oteli_getir, menu_yenile) ==='
select p.proname,
       pg_get_function_identity_arguments(p.oid) as imza,
       p.prosecdef as security_definer,
       md5(pg_get_functiondef(p.oid))            as govde_md5
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
 where n.nspname = 'public'
 order by p.proname;

\echo '=== 7. SATIR SAYILARI (hacim kontrolu) ==='
select 'menu_urunler'   as tablo, count(*) from public.menu_urunler
union all select 'masa_tokenlari',   count(*) from public.masa_tokenlari
union all select 'siparis_arsiv',    count(*) from public.siparis_arsiv;

\echo '=== 8. SON ARSIV KAYITLARI (kopru calisiyor mu — icerik YOK, sayi/zaman) ==='
select date_trunc('day', olusturma_zamani) as gun, sonuc, count(*)
  from public.siparis_arsiv
 where olusturma_zamani > now() - interval '30 days'
 group by 1, 2 order by 1 desc, 2;

rollback;
