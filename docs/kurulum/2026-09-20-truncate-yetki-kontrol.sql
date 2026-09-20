-- ===========================================================================
-- TRUNCATE / DELETE YETKI DENETIMI — ** SALT OKUMA, HICBIR DENEME YOK **
-- ===========================================================================
-- BULGU (2026-09-20, uretim sema dokumunden olculdu): cok sayida tablo
-- 'GRANT ALL ... TO authenticated' almis. GRANT ALL, TRUNCATE'i de kapsar ve
-- **TRUNCATE, RLS'i DINLEMEZ**: satir duzeyi politikalar TRUNCATE'i durdurmaz.
-- Yani RLS ile korundugu varsayilan tablolar, TRUNCATE hakki duran bir rol icin
-- tek komutla bosaltilabilir durumdadir.
--
-- BU DOSYA YALNIZ OLCER. Uretimde TRUNCATE ** DENENMEZ ** (kullanici karari
-- 2026-09-20). Asagida hicbir DDL/DML yoktur; islem read only ve sonda rollback.
--
-- IKI AYRI SORU AYRI AYRI RAPORLANIR:
--   (A) VERITABANI YETKISI : rolde TRUNCATE/DELETE hakki var mi?
--   (B) API ULASILABILIRLIGI: bu hak bugunku API yuzeyinden kullanilabilir mi?
--       PostgREST'te TRUNCATE icin HTTP yolu YOKTUR; risk, rolun dogrudan
--       veritabani baglantisiyla ya da dinamik SQL calistiran bir RPC ile
--       kullanilmasindan gelir. (5) ve (6) tam da bunu olcer.
--
--   .\docs\kurulum\sql-uygula.ps1 -Dosya docs\kurulum\2026-09-20-truncate-yetki-kontrol.sql -SaltOkuma
-- ===========================================================================
begin transaction read only;

\echo '== (A1) OZET: TRUNCATE hakki olan tablo sayisi (rol bazinda)'
select grantee, count(*) as tablo_sayisi
  from information_schema.role_table_grants
 where table_schema = 'public' and privilege_type = 'TRUNCATE'
   and grantee in ('anon', 'authenticated')
 group by grantee order by grantee;

\echo '== (A2) TRUNCATE hakki olan tablolar — RLS durumuyla birlikte'
-- RLS acik olanlar en kritik: koruma RLS''e birakilmis ama TRUNCATE onu asar.
select g.grantee, g.table_name, c.relrowsecurity as rls_acik,
       (select count(*) from pg_policies p where p.schemaname = 'public' and p.tablename = g.table_name) as politika_sayisi,
       c.reltuples::bigint as yaklasik_satir
  from information_schema.role_table_grants g
  join pg_class c on c.oid = ('public.' || quote_ident(g.table_name))::regclass
 where g.table_schema = 'public' and g.privilege_type = 'TRUNCATE'
   and g.grantee in ('anon', 'authenticated')
 order by c.relrowsecurity desc, c.reltuples desc, g.table_name;

\echo '== (A3) DELETE hakki olan ama DELETE politikasi OLMAYAN tablolar'
-- DELETE, TRUNCATE''ten farkli olarak RLS''e tabidir; politika yoksa zaten
-- reddedilir. Yine de fazla hak olarak listelenir.
select g.grantee, g.table_name,
       (select count(*) from pg_policies p
         where p.schemaname = 'public' and p.tablename = g.table_name
           and p.permissive = 'PERMISSIVE' and p.cmd in ('DELETE','ALL')) as izin_veren_delete_politikasi
  from information_schema.role_table_grants g
 where g.table_schema = 'public' and g.privilege_type = 'DELETE'
   and g.grantee in ('anon', 'authenticated')
 order by 3, g.table_name;

\echo '== (A4) SEKANS ve SEMA haklari (GRANT ALL supurgesi baska ne birakmis?)'
select grantee, privilege_type, count(*) as adet
  from information_schema.role_usage_grants
 where object_schema = 'public' and grantee in ('anon', 'authenticated')
 group by grantee, privilege_type order by grantee, privilege_type;

\echo '== (B1) ROLLER DOGRUDAN BAGLANABILIYOR MU? (LOGIN bayragi)'
-- LOGIN yoksa rol yalnizca API gecidi (PostgREST) uzerinden ustlenilir; o zaman
-- TRUNCATE icin bir HTTP yolu bulunmadigindan ulasim sinirlidir.
select rolname, rolcanlogin, rolsuper, rolbypassrls
  from pg_roles where rolname in ('anon', 'authenticated', 'authenticator', 'service_role')
 order by rolname;

\echo '== (B2) DINAMIK SQL CALISTIRAN, DISA ACIK FONKSIYONLAR (varsa API yolu olusur)'
-- Govdesinde EXECUTE gecen ve anon/authenticated tarafindan cagrilabilen
-- fonksiyonlar: metin parametre aliyorsa dikkatle incelenmeli.
select p.oid::regprocedure::text as fonksiyon, p.prosecdef as security_definer,
       has_function_privilege('anon', p.oid, 'EXECUTE') as anon_cagirabilir,
       has_function_privilege('authenticated', p.oid, 'EXECUTE') as auth_cagirabilir
  from pg_proc p
 where p.pronamespace = 'public'::regnamespace
   and p.prosrc ~* '(^|\s)execute\s'
   and (has_function_privilege('anon', p.oid, 'EXECUTE')
        or has_function_privilege('authenticated', p.oid, 'EXECUTE'))
 order by 1;

\echo '== (B3) TRUNCATE ustunde koruyucu EVENT TRIGGER / tetikleyici var mi?'
select evtname, evtevent, evtenabled from pg_event_trigger order by evtname;
select c.relname, t.tgname
  from pg_trigger t join pg_class c on c.oid = t.tgrelid
  join pg_namespace n on n.oid = c.relnamespace
 where n.nspname = 'public' and not t.tgisinternal
   and (t.tgtype & 32) <> 0          -- TRUNCATE tetikleyicisi
 order by c.relname, t.tgname;

rollback;
