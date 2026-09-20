-- ============================================================================
-- YAYIN ONCESI / SONRASI ISLEM KONTROLU — SALT OKUMA (2026-09-20)
-- ============================================================================
-- Neden: A1 migration'indan sonra eski (yenilenmemis) stok ekranlari stok
-- yazamaz (ESKI_ISTEMCI). Migration tam da cok satirli bir islemin ortasina
-- denk gelirse o islem YARIM kalabilir. "Sessiz saat" tek basina yeterli degil;
-- yayindan once islemlerin BITTIGI ve yeni islem baslamadigi GORULMELI.
--
-- Bu dosya hicbir sey yazmaz: READ ONLY islem, sonda ROLLBACK.
-- Yayin ONCESI ve yayin SONRASI ayni dosya calistirilir, ciktilar karsilastirilir.
--
--   .\docs\kurulum\sql-uygula.ps1 -Dosya docs\kurulum\2026-09-20-yayin-oncesi-islem-kontrol.sql -SaltOkuma
-- ============================================================================
begin transaction read only;

\echo '== 1) SON STOK HAREKETI NE ZAMAN? (bos dakika = ekranlarda islem yok)'
select max(tarih) as son_hareket,
       round(extract(epoch from (now() - max(tarih))) / 60)::int as kac_dakika_once,
       count(*) filter (where tarih > now() - interval '15 minutes') as son_15_dk_hareket
  from public.stok_hareketleri;

\echo '== 2) SON 15 DAKIKADA HAREKET YAZAN DEPOLAR (bos olmali)'
select depo_kodu, count(*) as hareket, max(tarih) as son
  from public.stok_hareketleri
 where tarih > now() - interval '15 minutes'
 group by depo_kodu order by son desc;

\echo '== 3) YARIM KALMIS MAL KABUL (onaylandi ama stok islenmemis)'
-- Bu satirlar yayin ONCESI de olabilir. Yayin oncesi listeyi KAYDEDIN; yayin
-- sonrasi YENI satir cikarsa yarim kalan islem odur. Korlemesine yeniden
-- onaylamayin: 4. sorgu ile hangi kalemin yazildigi satir satir bulunur.
select id, mk_no, firma_ad, otel_id, durum, stok_islendi, tarih
  from public.mal_kabuller
 where durum = 'onaylandi' and coalesce(stok_islendi, false) = false
 order by tarih desc limit 50;

\echo '== 4) YARIM KALAN MAL KABULDE HANGI KALEM STOGA ISLENDI? (satir satir)'
-- Kalem sayisi ile o belge numarasina yazilmis hareket sayisi karsilastirilir.
-- Esit degilse EKSIK kalemler elle tamamlanir; tum belge yeniden onaylanmaz.
select m.mk_no,
       count(distinct k.id) filter (where coalesce(k.urun_kodu,'') <> '' and k.miktar > 0) as kalem_sayisi,
       count(distinct h.id)                                   as yazilan_hareket,
       count(distinct k.id) filter (where coalesce(k.urun_kodu,'') <> '' and k.miktar > 0) - count(distinct h.id) as eksik
  from public.mal_kabuller m
  left join public.mal_kabul_urunleri k on k.mk_id = m.id
  left join public.stok_hareketleri h on h.belge_no = m.mk_no and h.tip = 'giris'
 where m.durum = 'onaylandi' and coalesce(m.stok_islendi, false) = false
 group by m.mk_no order by m.mk_no;

\echo '== 5) ACIK SAYIM OTURUMLARI (yayin sirasinda onaylanmamali)'
select id, depo_kodu, durum, toplam_urun_sayisi, olusturma_tarihi,
       round(extract(epoch from (now() - olusturma_tarihi)) / 3600)::int as kac_saat_once
  from public.sayim_oturumlari
 where durum = 'onay_bekliyor' order by olusturma_tarihi;

\echo '== 6) ACIK BAR SIPARISLERI (migration sonrasi ucretli olanlar dogrulama bekler)'
select durum::text, count(*) as adet, count(*) filter (where oda_no is not null) as odali
  from public.bar_siparisleri
 where durum::text in ('yeni', 'hazirlaniyor', 'hazir')
 group by durum::text order by 1;

rollback;
