-- ============================================================================
-- YEDEK + SAYAC SURUCUSU — AYNI SNAPSHOT (yontem A)
-- Tarih: 2026-09-13
-- ============================================================================
-- BU DOSYA ELLE CALISTIRILMAZ. `docs/kurulum/yedek-ve-sayac-al.ps1` calistirir.
-- SQL Editor'de CALISMAZ (meta komut icerir).
--
-- Ne yapar: tek bir psql oturumunda REPEATABLE READ islemi acar, snapshot
-- kimligini disari verir, ISLEM ACIKKEN pg_dump'i o snapshot ile calistirir ve
-- ayni islemin icinden sayaclari okur. Boylece yedek ile sayaclar ayni anlik
-- goruntuyu gorur; "ayni dakika" varsayimina gerek kalmaz (yayin plani E-5).
--
-- Yalnizca OKUR. Hicbir yazma yapmaz; islem commit ile kapanir (read-only).
--
-- Beklenen ortam degiskenleri (ps1 tarafindan kurulur):
--   PMS_PGDUMP  pg_dump.exe tam yolu       PMS_HOST / PMS_PORT / PMS_USER / PMS_DB
--   PMS_VERI    uretilecek veri yedegi yolu
--   PMS_AUTH_VERI / PMS_AUTH_SEMA  auth veri ve sema dosyalari
-- Beklenen psql degiskenleri: :sayac_dosyasi  :sayac_sorgusu
-- ============================================================================
\set ON_ERROR_STOP on

begin isolation level repeatable read;

select pg_export_snapshot() as pms_snapshot \gset
\setenv PMS_SNAPSHOT :pms_snapshot
\echo '--> snapshot kimligi alindi:' :pms_snapshot
\echo '--> pg_dump calisiyor (islem ACIK, ayni snapshot)...'

\! "%PMS_PGDUMP%" -h %PMS_HOST% -p %PMS_PORT% -U %PMS_USER% -d %PMS_DB% --data-only --no-owner --schema=public --schema=phase0_private --snapshot=%PMS_SNAPSHOT% -f "%PMS_VERI%"

\echo '--> auth semasi ayni snapshot ile aliniyor (SIR TASIR)...'
\! "%PMS_PGDUMP%" -h %PMS_HOST% -p %PMS_PORT% -U %PMS_USER% -d %PMS_DB% --data-only --no-owner --schema=auth --snapshot=%PMS_SNAPSHOT% -f "%PMS_AUTH_VERI%"
\! "%PMS_PGDUMP%" -h %PMS_HOST% -p %PMS_PORT% -U %PMS_USER% -d %PMS_DB% --schema-only --no-owner --no-privileges --schema=auth --snapshot=%PMS_SNAPSHOT% -f "%PMS_AUTH_SEMA%"

\echo '--> sayaclar ayni snapshot icinden okunuyor...'
\o :sayac_dosyasi
\i :sayac_sorgusu
\o

commit;
\echo '--> islem kapatildi (salt okuma).'
