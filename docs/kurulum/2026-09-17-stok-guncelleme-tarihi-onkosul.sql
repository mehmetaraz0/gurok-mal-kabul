-- ===========================================================================
-- ONKOSUL OLCUMU (SALT OKUMA): 2026-09-17-stok-guncelleme-tarihi.sql uretimde
-- onkosulunda durur mu? Migration'in 0. bolumundeki kontrollerin aynisi,
-- raise yerine sonuc satiri olarak.
--   .\docs\kurulum\sql-uygula.ps1 -Dosya docs\kurulum\2026-09-17-stok-guncelleme-tarihi-onkosul.sql -SaltOkuma
-- ===========================================================================
set default_transaction_read_only = on;
\pset pager off

\echo '--- 1) Govde md5 (olculen: ekle 24d255cc..., transfer 4c6fe121...) ---'
select p.proname, md5(p.prosrc) as md5,
       md5(p.prosrc) in ('24d255cc03df86bb4c9f6c978cadce81', '4c6fe1217463841653bec7637f3bf259') as olcumle_ayni
  from pg_proc p
 where p.pronamespace = 'public'::regnamespace and p.proname in ('stok_ekle', 'stok_transfer')
 order by 1;

\echo '--- 2) EXECUTE ACL (beklenen: anon f, public f, authenticated t, service_role t) ---'
select p.oid::regprocedure as fonksiyon, p.proacl,
       has_function_privilege('anon', p.oid, 'EXECUTE') as anon,
       (p.proacl is null or exists (select 1 from aclexplode(p.proacl) a
                                     where a.grantee = 0 and a.privilege_type = 'EXECUTE')) as public_,
       has_function_privilege('authenticated', p.oid, 'EXECUTE') as authenticated,
       has_function_privilege('service_role', p.oid, 'EXECUTE') as service_role
  from pg_proc p
 where p.pronamespace = 'public'::regnamespace and p.proname in ('stok_ekle', 'stok_transfer')
 order by 1;

\echo '--- 3) stok.guncelleme_tarihi UPDATE yetkisi (beklenen: t / t) ---'
select has_column_privilege('authenticated', 'public.stok', 'guncelleme_tarihi', 'UPDATE') as authenticated,
       has_column_privilege('service_role', 'public.stok', 'guncelleme_tarihi', 'UPDATE') as service_role;

\echo '--- 4) stok UPDATE RLS politikalari (bilgi: sutun eklemek satir kosulunu degistirmez) ---'
select policyname, cmd, roles, qual, with_check
  from pg_policies where schemaname = 'public' and tablename = 'stok'
 order by cmd, policyname;
