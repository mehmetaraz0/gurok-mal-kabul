-- ============================================================================
-- DUZELTME MIGRATION — pms_oda_tipi_kilitle: service_role EXECUTE KARARI
-- ============================================================================
-- Standart : docs/kurulum/MIGRATION-GUVENLIK-STANDARDI.md
-- Denetim  : node scripts/migration-guvenlik-kontrol.mjs docs/kurulum/2026-10-10-pms-oda-tipi-kilitle-service-role-revoke.sql
--
-- NEDEN BU DOSYA VAR
-- ------------------------------------------------------------------------
-- R11 denetleyici kurali su bulguyu verdi:
--
--   R11-SERVICE-ROLE-KARARI-YOK  pms_oda_tipi_kilitle
--   docs/kurulum/2026-10-06-pms-rol-entegrasyon-kilit.sql:47
--
-- O migration YENI bir fonksiyon yaratti (`pms_oda_tipi_kilitle`) ve ACL
-- kararini yalniz `public, anon` icin verdi (satir 72-73):
--
--   revoke all on function ... from public, anon;
--   grant execute on function ... to authenticated;
--
-- `service_role` icin KARAR YOK. public/postgres varsayilan ACL'si (P3) yeni
-- fonksiyona `service_role` EXECUTE verir; karar yazilmadigi icin bu hak
-- oldugu gibi kalmistir. Fonksiyon `security definer`dir ve bir oda tipi
-- satirini kilitleyip dondurur.
--
-- NEDEN YENI DOSYA, NEDEN ESKISI DUZELTILMEDI
-- ------------------------------------------------------------------------
-- Standardin 5. bolumu: "uretime uygulanmis hicbir migration geriye donuk
-- yeniden yazilmaz ... gercek bir acik bulunursa YENI bir duzeltme
-- migration'i yazilir." 2026-10-06 dosyasi 2026-10-08'de uretime uygulandi
-- ve yayin kaydinda ozetiyle sabitlendi; o dosya tarihsel kanittir.
--
-- NEDEN REVOKE, NEDEN GRANT DEGIL
-- ------------------------------------------------------------------------
-- Olculdu (repo taramasi): `pms_oda_tipi_kilitle` fonksiyonunu `service_role`
-- ile cagiran hicbir yer yok — Edge Function izi yok, istemci onu
-- `authenticated` olarak cagiriyor, kalan atiflar test/preflight/prova.
-- Ayrica `pms_check_in` ve `pms_check_out` `security definer`dir; onlarin
-- icinden gecen cagri tanimlayicinin haklariyla kosar, cagiranin haklariyla
-- KOSMAZ. Dolayisiyla revoke hicbir mevcut yolu kirmaz.
--   `pms_check_in` / `pms_check_out` BU DOSYANIN KAPSAMINDA DEGILDIR: onlarin
--   ACL karari Faz 1 Adim 3'te acikca verilmistir (`grant execute ... to
--   authenticated, service_role`) ve KASITLIDIR; MY-4'un `create or replace`i
--   mevcut ACL'yi korudugu icin degismemistir.
--
-- KAPSAM
-- ------------------------------------------------------------------------
-- TEK fonksiyonun EXECUTE ayricaligi. Fonksiyon govdesi, politika, tablo,
-- rol veya yetki matrisi DEGISMEZ. Veri yazilmaz, okunmaz.
--
-- UYGULAMA
-- ------------------------------------------------------------------------
-- Bu dosya YAZILDI, UYGULANMADI. Uretime uygulamak ayri onaya baglidir
-- ("CANLIYA UYGULA"). Idempotenttir: birden fazla kez calistirilabilir.
--   .\docs\kurulum\sql-uygula.ps1 -Dosya docs\kurulum\2026-10-10-pms-oda-tipi-kilitle-service-role-revoke.sql
-- ============================================================================


-- ============================================================================
-- 0) ONKOSULLAR
-- ----------------------------------------------------------------------------
-- Hedef fonksiyon ve rol GERCEKTEN var mi? Yoksa hicbir sey degistirmeden dur.
-- ============================================================================
do $$
begin
  if to_regprocedure('public.pms_oda_tipi_kilitle(uuid, public.otel_id)') is null then
    raise exception 'ONKOSUL: pms_oda_tipi_kilitle(uuid, otel_id) yok. '
      'Once 2026-10-06-pms-rol-entegrasyon-kilit.sql uygulanmali.';
  end if;

  if not exists (select 1 from pg_roles where rolname = 'service_role') then
    raise exception 'ONKOSUL: service_role rolu yok. Bu dosya Supabase '
      'rol duzeniyle calisir.';
  end if;

  if not exists (select 1 from pg_roles where rolname = 'authenticated') then
    raise exception 'ONKOSUL: authenticated rolu yok.';
  end if;

  -- Bilgi: zaten uygulanmis mi?
  if has_function_privilege('service_role',
       'public.pms_oda_tipi_kilitle(uuid, public.otel_id)', 'EXECUTE') is false then
    raise notice 'service_role EXECUTE hakki ZATEN yok; dosya idempotent, '
      'yine de son durumu garanti eder.';
  end if;
end;
$$;


-- ============================================================================
-- 1) TRANSACTION
-- ----------------------------------------------------------------------------
-- Dosyanin tamami tek transaction icinde. Parca parca calistirma.
-- ============================================================================
begin;


-- ============================================================================
-- 2) ACL KARARI
-- ----------------------------------------------------------------------------
-- Son durum ACIKCA yazilir: cagirabilen YALNIZ `authenticated`.
-- `public, anon` revoke'u 2026-10-06'da verilmisti; burada idempotenslik ve
-- dosyanin kendi kendine yeterli olmasi icin yeniden ifade edilir.
-- `authenticated` grant'i da ayni sebeple yeniden ifade edilir — revoke
-- `public`ten hak dusurur, `authenticated`in DOGRUDAN grant'ini etkilemez.
-- ============================================================================
revoke all on function public.pms_oda_tipi_kilitle(uuid, public.otel_id)
  from public, anon, service_role;

grant execute on function public.pms_oda_tipi_kilitle(uuid, public.otel_id)
  to authenticated;


-- ============================================================================
-- 3) DOGRULAMA  (transaction icinde; tutmazsa hicbir sey kalmaz)
-- ----------------------------------------------------------------------------
-- "Calisti" demek yetmez; son durumu OLCUP tutmazsa transaction'i dusuruyoruz.
-- ============================================================================
do $$
declare
  v_imza text := 'public.pms_oda_tipi_kilitle(uuid, public.otel_id)';
  v_hata text := '';
begin
  if has_function_privilege('service_role', v_imza, 'EXECUTE') is not false then
    v_hata := v_hata || 'service_role EXECUTE hala VAR; ';
  end if;
  if has_function_privilege('anon', v_imza, 'EXECUTE') is not false then
    v_hata := v_hata || 'anon EXECUTE var; ';
  end if;
  if has_function_privilege('authenticated', v_imza, 'EXECUTE') is not true then
    v_hata := v_hata || 'authenticated EXECUTE YOK (uygulama kirilir); ';
  end if;

  if v_hata <> '' then
    raise exception 'DOGRULAMA BASARISIZ: %', v_hata;
  end if;

  raise notice 'pms_oda_tipi_kilitle ACL son durumu: authenticated=true, '
               'anon=false, service_role=false. R11 karari verildi.';
end;
$$;

commit;


-- ============================================================================
-- GERI ALMA
-- ----------------------------------------------------------------------------
-- Bu dosyanin geri alinmasi, varsayilan ACL'nin (P3) biraktigi hakki GERI
-- ACAR. Yalniz `service_role` ile cagiran mesru bir yol bulunursa yapilir ve
-- o zaman karar KASITLI GRANT olarak yazilir (R11 bunu kabul eder):
--
--   begin;
--   grant execute on function public.pms_oda_tipi_kilitle(uuid, public.otel_id)
--     to service_role;
--   commit;
--
-- Fonksiyon govdesi, politika veya veri degismedigi icin baska geri alma
-- adimi yoktur; yedekten donuse gerek duymaz.
-- ============================================================================
