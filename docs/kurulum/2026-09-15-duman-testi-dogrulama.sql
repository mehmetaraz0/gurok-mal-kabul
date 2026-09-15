-- ============================================================================
-- DUMAN TESTI DOGRULAMA (SALT OKUMA) — 2026-09-15
-- ============================================================================
-- Ekranda gorunen sonucun veritabaninda da oldugunu dogrular. Yazma YOK.
-- ============================================================================

\echo '--- 1) Son 10 stok hareketi ---'
select tarih, tip, urun_kodu, depo_kodu, kaynak_depo_kodu, miktar, aciklama
  from public.stok_hareketleri
 order by tarih desc
 limit 10;

\echo '--- 2) Test edilen urunun depo dagilimi (DANA BESLI SET) ---'
select depo_kodu, otel_id, miktar, guncelleme_tarihi
  from public.stok
 where urun_kodu = 'YIY01000002'
 order by depo_kodu;

\echo '--- 3) Toplam korunuyor mu? Transfer stok YARATMAZ/YOK ETMEZ ---'
select sum(miktar) as urun_toplami
  from public.stok
 where urun_kodu = 'YIY01000002';

\echo '--- 4) Depo sayaclari (once: 100=14, CMM201=6, ANA_DEPO=3, CSM302=1) ---'
select depo_kodu, count(*) as satir, sum(miktar) as toplam_miktar
  from public.stok
 group by 1
 order by 1;

\echo '--- 5) Gorunum ve ozet hala tutarli mi? ---'
select (select count(*) from public.stok)       as stok,
       (select count(*) from public.stok_liste) as stok_liste,
       (select toplam from public.stok_ozet(null)) as ozet_toplam;
