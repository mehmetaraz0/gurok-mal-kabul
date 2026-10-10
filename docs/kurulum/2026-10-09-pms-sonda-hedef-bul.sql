-- ===========================================================================
-- SONDA HEDEFINI BULMA — SALT OKUMA (hicbir sey YAZMAZ)
-- ===========================================================================
-- Amac: 2026-10-09-pms-mali-sunucu-retleri-sondasi.sql dosyasinin basindaki
-- dort `set local sonda.hedef_*` satirina yazilacak degerleri okumak.
--
-- Bu dosya SADECE SELECT icerir. Insert/update/delete/DDL YOKTUR, islem
-- acmaz, hicbir satiri degistirmez.
--
-- CALISTIRMA:
--   .\docs\kurulum\sql-uygula.ps1 -Dosya docs\kurulum\2026-10-09-pms-sonda-hedef-bul.sql -SaltOkuma
-- ===========================================================================

-- --- 1) hedef_personel ve hedef_yonetici ----------------------------------
-- `yetki = kayit`  olan satirin auth_user_id'si -> sonda.hedef_personel
-- `yetki = tam`    olan satirin auth_user_id'si -> sonda.hedef_yonetici
-- Her iki yetki seviyesinden BIRER satir secilmeli; birden fazla aday varsa
-- hangisiyle kosuldugu kayda gececegi icin bilerek BIR tanesi secilir.
select k.auth_user_id          as sonda_hedef_kimlik,
       k.ad,
       k.otel_id               as sonda_hedef_otel,
       r.kod                   as rol,
       y.yetki::text           as pms_folio_yetkisi,
       k.aktif
  from public.kullanicilar k
  join public.roller r         on r.id = k.rol_id
  join public.yetki_matrisi y  on y.rol_id = r.id
  join public.moduller m       on m.id = y.modul_id
 where m.kod = 'pms_folio'
   and k.aktif
   and k.otel_id is not null
 order by k.otel_id, y.yetki::text, k.ad;

-- --- 2) hedef_misafir -----------------------------------------------------
-- SENTETIK QA misafirinin SOYADI -> sonda.hedef_misafir
-- Sonda yalniz sentetik kayitla kosar; isarette QA gecmek zorundadir ve
-- ayni soyad birden fazla kez eslesiyorsa sonda DURUR.
select otel_id, soyad as sonda_hedef_misafir, ad, count(*) as eslesme
  from public.pms_misafirler
 where aktif and upper(soyad) like '%QA%'
 group by otel_id, soyad, ad
 order by otel_id, soyad;

-- --- 3) Onkosul: mali kural ve degismezlik yerinde mi ---------------------
-- Beklenen: hassas_kapi 2 (iki tabloda), degismez 2 (iki tabloda),
--           hassas_mi fonksiyonu 1.
select
  (select count(*) from pg_trigger t join pg_class c on c.oid = t.tgrelid
    where t.tgname = 'pms_folio_hassas_kapi' and not t.tgisinternal
      and c.relname in ('pms_folio_hareketleri','pms_folio_odemeler'))
    as hassas_kapi_tetikleyici,
  (select count(*) from pg_trigger t join pg_class c on c.oid = t.tgrelid
    where t.tgname = 'pms_folio_degismez' and not t.tgisinternal
      and c.relname in ('pms_folio_hareketleri','pms_folio_odemeler'))
    as degismez_tetikleyici,
  (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'pms_folio_hassas_mi')
    as hassas_mi_fonksiyonu;
