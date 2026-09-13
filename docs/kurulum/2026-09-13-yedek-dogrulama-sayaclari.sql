-- ============================================================================
-- YEDEK DOĞRULAMA SAYAÇLARI — SALT OKUMA
-- Tarih: 2026-09-13
-- ============================================================================
-- Nerede çalışır : Supabase SQL Editor, ÜRETİM. Tek SELECT; hiçbir şey yazmaz.
-- Ne zaman       : Elle veri yedeği alındıktan HEMEN SONRA (aynı dakika içinde).
-- Ne işe yarar   : Yedeğin izole kopyaya geri yüklenmesinden sonra satır
--                  sayılarının tutup tutmadığını karşılaştırmak için "beklenen"
--                  değerleri üretir. Yedek dosyasının var olması yeterli
--                  DEĞİLDİR; geri yükleme ve veri doğrulaması geçmelidir
--                  (yayın planı E-5).
--
-- NASIL KULLANILIR
--   1) Bu dosyayı SQL Editor'de çalıştırın.
--   2) Tek satırlık JSON sonucunu kopyalayıp REPO DIŞINDAKİ yedek klasörüne
--      `<etiket>-sayaclar.json` olarak kaydedin (varsayılan: C:\Users\USER\ERP-Yedek).
--   3) Geri yükleme provası:
--      node scripts/pms-yedek-geri-yukleme-provasi.mjs <veri-yedegi> <sayaclar.json>
--
-- NOT: Sayım `count(*)` ile YAPILIR (tahmini `reltuples` değil). Küçük veri
-- tabanında maliyeti önemsizdir.
-- ============================================================================

select jsonb_pretty(jsonb_build_object(
  'alinma_zamani', now(),
  'sunucu_surumu', current_setting('server_version'),
  'tablo_sayisi', (select count(*) from pg_class c
                    join pg_namespace n on n.oid = c.relnamespace
                   where n.nspname = 'public' and c.relkind = 'r'),
  'satir_sayilari', (
    select jsonb_object_agg(t.tablo, t.adet order by t.tablo)
      from (
        select c.relname as tablo,
               (xpath('/row/c/text()',
                      query_to_xml(format('select count(*) as c from public.%I', c.relname),
                                   false, true, '')))[1]::text::bigint as adet
          from pg_class c
          join pg_namespace n on n.oid = c.relnamespace
         where n.nspname = 'public' and c.relkind = 'r'
      ) t
  ),
  'denetim_izi_son_kayit', (select max(server_timestamp) from public.erp_islem_audit),
  'pms_ozet', jsonb_build_object(
    'oda', (select count(*) from public.pms_odalar),
    'dolu_oda', (select count(*) from public.pms_odalar where kullanim_durumu = 'dolu'),
    'devam_eden_konaklama', (select count(*) from public.pms_rezervasyonlar where durum = 'giris_yapildi'),
    'aktif_atama', (select count(*) from public.pms_oda_atamalari where aktif),
    'acik_folyo', (select count(*) from public.pms_folyolar where durum = 'acik')
  )
)) as sayaclar;

-- ============================================================================
-- YORUMLAMA
-- ============================================================================
-- Bu çıktı, yedeğin ALINDIĞI ANI temsil eder. Geri yükleme provasında
-- karşılaştırılır:
--   * satır sayıları birebir tutmalı;
--   * tutmayan her tablo raporlanır ve yedek KABUL EDİLMEZ;
--   * `alinma_zamani` ile yedek dosyasının tarihi arasındaki fark, olası veri
--     kaybı aralığının (RPO) alt sınırıdır.
-- ============================================================================
