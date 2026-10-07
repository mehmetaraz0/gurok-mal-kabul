-- ===========================================================================
-- PMS On Buro yayini — YAYIN ONCESI SALT-OKUMA PREFLIGHT (2026-10-07)
-- ===========================================================================
-- Paket: docs/kurulum/2026-10-07-pms-canliya-gecis-paketi.md
--
-- BU DOSYA HICBIR SEY YAZMAZ. Yalniz SELECT icerir; DDL, DML, GRANT, SET ve
-- fonksiyon cagirma yoktur. Amaci, uc migration uygulanmadan ONCE uretimin
-- gercek durumunu olcmek ve DURMA kosullarini kanitla beslemektir.
--
-- KANAL: dosya hem `psql -f` hem Supabase SQL Editor ile calisir. psql'e ozgu
-- meta komut (ornegin \echo) KULLANILMAZ; bolum basliklari normal SELECT
-- satirlaridir. Boylece yedek kanal da ayri bir surum gerektirmez.
--
-- NICIN GEREKLI: depodaki en guncel uretim parmak izi 2026-09-07 (post-Faz 1,
-- 75 tablo / 234 politika / 40 kisitlayici). Uretim o gunden sonra Faz 2
-- (09-13), stok (09-15, 09-18), Bar A1 (09-20) ve sayim onay kapisi (09-26)
-- aldi. Yani GUNCEL bir taban parmak izi YOKTUR; 7. bolum onu uretir ve yayin
-- kaydina yeni taban olarak yazilir.
-- ===========================================================================

select '=== 1) On Buro modul satirlari — tohumlamanin ne yapacagini belirler ===' as bolum;
-- Beklenen iki mesru durum vardir:
--   (a) satir YOK  -> tohumlama 5 modulu kendisi ekler (aktif = true)
--   (b) satir VAR ve aktif = true -> tohumlama dokunmaz (on conflict do nothing)
-- aktif = false ise tohumlama DURUR (PASIF MODUL) ve hicbir satir yazmaz.
select m.kod,
       m.aktif,
       m.sira,
       case when m.aktif is true then 'UYGUN'
            else 'SAPMA: pasif modul, tohumlama DURACAK' end as karar
  from public.moduller m
 where m.kod in ('pms_oda_tipi','pms_oda','pms_misafir','pms_rezervasyon','pms_folio')
 order by m.kod;

select count(*) as mevcut_onburo_modul_sayisi,
       5 - count(*) as tohumlamanin_ekleyecegi_modul
  from public.moduller
 where kod in ('pms_oda_tipi','pms_oda','pms_misafir','pms_rezervasyon','pms_folio');

select '=== 2) On Buro rolleri var mi — yoksa tohumlama EKSIK REFERANS ile durur ===' as bolum;
select v.kod,
       (select count(*) from public.roller r where r.kod = v.kod) as var_mi,
       case when exists (select 1 from public.roller r where r.kod = v.kod)
            then 'UYGUN' else 'SAPMA: rol yok, tohumlama DURACAK' end as karar
  from (values ('onburo_sef'),('onburo_vardiya'),('onburo_personel')) v(kod)
 order by v.kod;

select '=== 3) ONAYLI 15 HEDEF CIFT ile mevcut durumun karsilastirmasi ===' as bolum;
-- Sozlesme: tohumlama MEVCUT yetkileri DEGISTIRMEZ.
--   UYUMLU MEVCUT -> satir zaten dogru seviyede; tohumlama atlar (yeni satir YOK)
--   EKSIK         -> tohumlama bu satiri ekler ve damgalar
--   CELISEN       -> tohumlama DURUR (CELISEN MEVCUT YETKI), hicbir satir yazmaz
-- K1 = A karari geregi onburo_personel / pms_folio hedefi `kayit`tir.
with hedef(rol, modul, yetki) as (values
  ('onburo_sef','pms_oda_tipi','tam'),          ('onburo_sef','pms_oda','tam'),
  ('onburo_sef','pms_misafir','tam'),           ('onburo_sef','pms_rezervasyon','tam'),
  ('onburo_sef','pms_folio','tam'),
  ('onburo_vardiya','pms_oda_tipi','goruntule'),('onburo_vardiya','pms_oda','kayit'),
  ('onburo_vardiya','pms_misafir','kayit'),     ('onburo_vardiya','pms_rezervasyon','kayit'),
  ('onburo_vardiya','pms_folio','kayit'),
  ('onburo_personel','pms_oda_tipi','goruntule'),('onburo_personel','pms_oda','goruntule'),
  ('onburo_personel','pms_misafir','kayit'),    ('onburo_personel','pms_rezervasyon','kayit'),
  ('onburo_personel','pms_folio','kayit')
), olcum as (
  select h.rol, h.modul, h.yetki as hedef_yetki,
         ym.yetki::text as mevcut_yetki, ym.guncelleyen,
         case when ym.rol_id is null                  then 'EKSIK'
              when ym.yetki::text = h.yetki           then 'UYUMLU MEVCUT'
              else 'CELISEN' end as sinif
    from hedef h
    left join public.roller   r  on r.kod = h.rol
    left join public.moduller m  on m.kod = h.modul
    left join public.yetki_matrisi ym on ym.rol_id = r.id and ym.modul_id = m.id
)
select rol, modul, hedef_yetki, mevcut_yetki, guncelleyen, sinif,
       case when sinif = 'CELISEN' then 'SAPMA: DURULACAK — mevcut hak bu paketle degistirilmez'
            else 'uygun' end as karar
  from olcum
 order by sinif desc, rol, modul;

-- Yayin sonrasi kabul BU sayilarla yapilir:
--   eklenen damgali satir sayisi = EKSIK sayisi (15 DEGIL)
--   son durumda 15 hedef ciftin tamami dogru seviyede olmali
with hedef(rol, modul, yetki) as (values
  ('onburo_sef','pms_oda_tipi','tam'),          ('onburo_sef','pms_oda','tam'),
  ('onburo_sef','pms_misafir','tam'),           ('onburo_sef','pms_rezervasyon','tam'),
  ('onburo_sef','pms_folio','tam'),
  ('onburo_vardiya','pms_oda_tipi','goruntule'),('onburo_vardiya','pms_oda','kayit'),
  ('onburo_vardiya','pms_misafir','kayit'),     ('onburo_vardiya','pms_rezervasyon','kayit'),
  ('onburo_vardiya','pms_folio','kayit'),
  ('onburo_personel','pms_oda_tipi','goruntule'),('onburo_personel','pms_oda','goruntule'),
  ('onburo_personel','pms_misafir','kayit'),    ('onburo_personel','pms_rezervasyon','kayit'),
  ('onburo_personel','pms_folio','kayit')
), olcum as (
  select case when ym.rol_id is null        then 'EKSIK'
              when ym.yetki::text = h.yetki then 'UYUMLU MEVCUT'
              else 'CELISEN' end as sinif
    from hedef h
    left join public.roller   r  on r.kod = h.rol
    left join public.moduller m  on m.kod = h.modul
    left join public.yetki_matrisi ym on ym.rol_id = r.id and ym.modul_id = m.id
)
select count(*) filter (where sinif = 'UYUMLU MEVCUT') as uyumlu_mevcut,
       count(*) filter (where sinif = 'EKSIK')         as eksik_beklenen_yeni_satir,
       count(*) filter (where sinif = 'CELISEN')       as celisen,
       case when count(*) filter (where sinif = 'CELISEN') > 0
            then 'SAPMA: Adim 4 KOSULMAZ' else 'UYGUN' end as karar
  from olcum;

select '=== 3b) Bes modul icin TUM mevcut yetki satirlari (hedef disi roller dahil) ===' as bolum;
-- Menu ve kapsam kabulu ONCE/SONRA delta olarak yapilir. Burada gorunen
-- hedef disi roller KAPATILMAZ; yayin sonrasi ayni liste yeniden alinir.
select r.kod as rol, m.kod as modul, y.yetki, y.guncelleyen
  from public.yetki_matrisi y
  join public.roller   r on r.id = y.rol_id
  join public.moduller m on m.id = y.modul_id
 where m.kod in ('pms_oda_tipi','pms_oda','pms_misafir','pms_rezervasyon','pms_folio')
 order by r.kod, m.kod;

select '=== 3c) KAPSAM DISI pms_misafir_kimlik (KVKK) — mevcut satirlar korunur ===' as bolum;
-- Bu paket kimlik yetkisi VERMEZ. Mevcut satirlar varsa SILINMEZ; yayin
-- sonrasi ayni sayi beklenir (iki ayri olcut: yeni satir 0, mevcut sayi sabit).
select coalesce(r.kod, '(satir yok)') as rol, y.yetki, y.guncelleyen
  from public.moduller m
  left join public.yetki_matrisi y on y.modul_id = m.id
  left join public.roller r on r.id = y.rol_id
 where m.kod = 'pms_misafir_kimlik'
 order by r.kod;

select '=== 4) Mali ayrim kurali zaten kurulu mu (kismi uygulama kontrolu) ===' as bolum;
select 'pms_folio_hassas_kapi tetikleyici sayisi' as olcum,
       count(*)::text as olculen,
       '0 (henuz uygulanmadi) veya 2 (zaten uygulanmis)' as beklenen,
       case when count(*) in (0,2) then 'UYGUN'
            else 'SAPMA: kismi uygulama' end as karar
  from pg_trigger t
  join pg_class c on c.oid = t.tgrelid
 where t.tgname = 'pms_folio_hassas_kapi' and not t.tgisinternal
   and c.relname in ('pms_folio_hareketleri','pms_folio_odemeler');

select 'pms_folio_hassas_mi fonksiyonu' as olcum,
       count(*)::text as olculen, '0 veya 1' as beklenen,
       case when count(*) <= 1 then 'UYGUN' else 'SAPMA' end as karar
  from pg_proc where pronamespace = 'public'::regnamespace and proname = 'pms_folio_hassas_mi';

select '=== 5) MY-4 kilidi zaten uygulanmis mi ===' as bolum;
select p.proname, p.prosecdef as security_definer,
       case when p.prosecdef then 'kilit UYGULANMIS' else 'kilit UYGULANMAMIS' end as durum
  from pg_proc p
 where p.pronamespace = 'public'::regnamespace
   and p.proname in ('pms_rezervasyon_kontrol','pms_check_in','pms_check_out')
 order by p.proname;

select 'pms_oda_tipi_kilitle yardimcisi' as olcum, count(*)::text as olculen,
       '0 (uygulanmadi) veya 1 (uygulanmis)' as beklenen,
       case when count(*) <= 1 then 'UYGUN' else 'SAPMA' end as karar
  from pg_proc where pronamespace = 'public'::regnamespace and proname = 'pms_oda_tipi_kilitle';

select '=== 6) EN KRITIK: uretimdeki uc govde, kilidin uretildigi 09-06 govdeleri mi ===' as bolum;
-- Kilit dosyasi fonksiyon govdelerini 2026-09-06 migration'larindan BIREBIR
-- aldi. Uretimdeki govde baska biri tarafindan degistirilmisse, kilidi
-- uygulamak o degisikligi SESSIZCE geri alir.
-- Beklenen degerler izole tabanda (09-07 ve 09-13 dokumlerinde ayni) olculdu:
--   pms_rezervasyon_kontrol  83da45a3c84f8e64cd414b78817e5ed2
--   pms_check_in             3798c9461390f18f97e537bd9be07612
--   pms_check_out            6d6bb0ecbef41ff1a13fc437857f49fa
-- md5(prosrc) satir sonuna duyarlidir ve PostgreSQL surumunden BAGIMSIZDIR.
select p.proname, md5(p.prosrc) as govde_md5, length(p.prosrc) as govde_uzunluk,
       case md5(p.prosrc)
         when '83da45a3c84f8e64cd414b78817e5ed2' then 'UYGUN (Faz 1 govdesi)'
         when '3798c9461390f18f97e537bd9be07612' then 'UYGUN (Faz 1 govdesi)'
         when '6d6bb0ecbef41ff1a13fc437857f49fa' then 'UYGUN (Faz 1 govdesi)'
         else 'SAPMA: govde beklenen degil — Adim 2 KOSULMAZ' end as karar
  from pg_proc p
 where p.pronamespace = 'public'::regnamespace
   and p.proname in ('pms_rezervasyon_kontrol','pms_check_in','pms_check_out')
 order by p.proname;

select '=== 6b) Kesin imzalar, EFEKTIF EXECUTE haklari, definer ve search_path ===' as bolum;
-- `create or replace` ACL'yi korur; ama bu, mevcut ACL'nin DOGRU oldugunu tek
-- basina kanitlamaz. Beklenen Faz 1 sozlesmesi: anon KAPALI, PUBLIC KAPALI,
-- authenticated ve service_role ACIK. OTOMATIK GRANT/REVOKE YAPILMAZ; sapma
-- yalniz raporlanir ve karar kullanicinin olur.
select p.oid::regprocedure::text as kesin_imza,
       p.prosecdef as security_definer,
       (select string_agg(c, ', ') from unnest(coalesce(p.proconfig, '{}'::text[])) c) as proconfig,
       has_function_privilege('anon',          p.oid, 'execute') as anon_execute,
       has_function_privilege('authenticated', p.oid, 'execute') as authenticated_execute,
       has_function_privilege('service_role',  p.oid, 'execute') as service_role_execute,
       case when has_function_privilege('anon', p.oid, 'execute')
              then 'SAPMA: anon EXECUTE acik'
            when not has_function_privilege('authenticated', p.oid, 'execute')
              then 'SAPMA: authenticated EXECUTE kapali'
            when not has_function_privilege('service_role', p.oid, 'execute')
              then 'SAPMA: service_role EXECUTE kapali'
            when p.prosecdef and not exists (
                   select 1 from unnest(coalesce(p.proconfig, '{}'::text[])) c
                    where c like 'search\_path=%')
              then 'SAPMA: definer ama search_path pinsiz'
            else 'UYGUN' end as karar
  from pg_proc p
 where p.pronamespace = 'public'::regnamespace
   and p.proname in ('pms_check_in','pms_check_out','pms_oda_tipi_kilitle',
                     'pms_folio_hassas_mi','pms_bar_folio_koprusu')
 order by p.proname;

select '=== 7) GUNCEL TABAN PARMAK IZI — depoda yok, bu kosumda uretilir ===' as bolum;
select 'public tablo sayisi'      as olcum, count(*)::text as olculen
  from pg_class c join pg_namespace n on n.oid = c.relnamespace
 where n.nspname = 'public' and c.relkind = 'r'
union all
select 'public politika sayisi', count(*)::text from pg_policy p
  join pg_class c on c.oid = p.polrelid
  join pg_namespace n on n.oid = c.relnamespace where n.nspname = 'public'
union all
select 'kisitlayici politika', count(*)::text from pg_policy p
  join pg_class c on c.oid = p.polrelid
  join pg_namespace n on n.oid = c.relnamespace
 where n.nspname = 'public' and not p.polpermissive
union all
select 'RLS kapali tablo (0 olmali)', count(*)::text
  from pg_class c join pg_namespace n on n.oid = c.relnamespace
 where n.nspname = 'public' and c.relkind = 'r' and not c.relrowsecurity
union all
select 'search_path pinsiz SECURITY DEFINER (0 olmali)', count(*)::text
  from pg_proc p
 where p.pronamespace = 'public'::regnamespace and p.prosecdef
   and not exists (select 1 from unnest(coalesce(p.proconfig, '{}'::text[])) c
                    where c like 'search\_path=%')
union all
select 'anon tablo hakki (0 olmali)', count(*)::text
  from information_schema.role_table_grants
 where grantee = 'anon' and table_schema = 'public';

select '=== 8) GERI ALMA SINIRI — gercek para hareketi var mi ===' as bolum;
-- Faz 1 kurali: pms_folio_odemeler bos degilse geri alma yerine OZELLIK
-- KAPATMA tercih edilir. Bu paketin uc dosyasi da mali satir SILMEZ (izole
-- provada olculdu), ama sinir yayin kaydina yazilir.
select 'pms_folio_odemeler satir'  as olcum, count(*)::text as olculen from public.pms_folio_odemeler
union all
select 'pms_folio_hareketleri satir', count(*)::text from public.pms_folio_hareketleri
union all
select 'acik folyo', count(*)::text from public.pms_folyolar where durum = 'acik';

select '=== 9) ADIM 1 IN OPERASYONEL ETKISI — bugun folyoya kim yazabiliyor ===' as bolum;
-- Adim 1 uygulandigi anda, `kayit` seviyesindeki herkes icin iade / indirim /
-- duzeltme REDDEDILMEYE baslar. Kimin etkilenecegi onceden bilinmelidir.
select r.kod as rol, y.yetki,
       (select count(*) from public.kullanicilar k where k.rol_id = r.id and k.aktif) as aktif_kullanici,
       case when y.yetki = 'kayit' then 'ETKILENIR: iade/indirim/duzeltme icin tam gerekecek'
            when y.yetki = 'tam'   then 'etkilenmez (gerekce zorunlu olacak)'
            else 'etkilenmez' end as etki
  from public.yetki_matrisi y
  join public.roller   r on r.id = y.rol_id
  join public.moduller m on m.id = y.modul_id
 where m.kod = 'pms_folio'
 order by y.yetki, r.kod;

select '=== 10) DUMAN TESTI TABANI — denetim izi sayaci ===' as bolum;
select 'erp_islem_audit satir' as olcum, count(*)::text as olculen from public.erp_islem_audit;

select '=== PREFLIGHT BITTI — hicbir satir yazilmadi ===' as bolum;
