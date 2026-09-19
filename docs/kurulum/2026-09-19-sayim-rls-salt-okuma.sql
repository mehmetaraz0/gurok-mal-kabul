-- ============================================================================
-- SAYIM TABLOLARI CANLI ERISIM — SALT OKUMA (2026-09-19)
-- ============================================================================
-- Soru: 2026-09-13 dokumunde sayim_oturumlari yalniz RESTRICTIVE politika,
-- sayim_detaylari hic politika tasiyor (RLS acik). Canlida da boyle mi, ve
-- stok-takip'teki mevcut cost_control kullanicisi sayim satirlarini gorebiliyor mu?
--
-- YAZMA YOK: tum sorgular READ ONLY islem icinde, sonda ROLLBACK. Rol/claim
-- ayari 'set local' ile yalniz bu islemde gecerlidir. Kisisel veri cikmaz:
-- yalniz sayilar, politika metinleri ve tarih.
--
-- Calistirma (parolayi kullanici girer):
--   .\docs\kurulum\sql-uygula.ps1 -Dosya docs\kurulum\2026-09-19-sayim-rls-salt-okuma.sql -SaltOkuma
-- ============================================================================
begin transaction read only;

\echo '== 1) RLS bayraklari'
select c.relname, c.relrowsecurity as rls, c.relforcerowsecurity as force_rls
  from pg_class c where c.relnamespace = 'public'::regnamespace
   and c.relname in ('sayim_oturumlari', 'sayim_detaylari') order by 1;

\echo '== 2) Politikalar (permissive/restrictive, komut, rol)'
select tablename, policyname, permissive, cmd, roles::text
  from pg_policies where schemaname = 'public' and tablename in ('sayim_oturumlari', 'sayim_detaylari')
 order by 1, 2;

\echo '== 3) authenticated tablo haklari'
select table_name, string_agg(privilege_type, ',' order by privilege_type) as haklar
  from information_schema.role_table_grants
 where table_schema = 'public' and grantee = 'authenticated'
   and table_name in ('sayim_oturumlari', 'sayim_detaylari')
 group by 1 order by 1;

\echo '== 4) Gercek satir sayisi (sahip rolle, RLS disi) ve son kullanim'
select 'sayim_oturumlari' as tablo, count(*) as satir, max(olusturma_tarihi)::date as son_kayit,
       count(*) filter (where olusturma_tarihi > now() - interval '30 days') as son_30_gun
  from public.sayim_oturumlari
union all
select 'sayim_detaylari', count(*), null, null from public.sayim_detaylari;

\echo '== 5) Aktif cost_control kullanicisi olarak gorunen satir (RLS ile)'
-- Kimlik: aktif bir cost_control kullanicisinin auth kimligi; cikti yalniz sayilardir.
select set_config('request.jwt.claims',
         json_build_object('sub', k.auth_user_id, 'role', 'authenticated')::text, true) is not null as kimlik_kuruldu,
       (select count(*) from public.kullanicilar where rol::text = 'cost_control' and aktif) as aktif_cost_control_sayisi
  from public.kullanicilar k
 where k.rol::text = 'cost_control' and k.aktif and k.auth_user_id is not null
 order by k.id limit 1;
set local role authenticated;
select 'sayim_oturumlari' as tablo, count(*) as gorunen from public.sayim_oturumlari
union all
select 'sayim_detaylari', count(*) from public.sayim_detaylari;
reset role;

rollback;
