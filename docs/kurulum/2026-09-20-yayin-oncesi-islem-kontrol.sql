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

\echo '== 4) YARIM KALAN MAL KABUL — SATIR SATIR STOK ETKISI (sayim degil, ESLESTIRME)'
-- UYARI: kalem sayisi ile hareket sayisini karsilastirmak KANIT DEGILDIR.
-- Miktar (stok) ve hareket AYRI isteklerde yazilir: hareket kaydi olmadigi halde
-- stok DEGISMIS olabilir. Asagida her kalem icin (a) eslesen hareket, (b) stok
-- satirinin onay zamanindan SONRA degisip degismedigi birlikte gosterilir.
-- 'SUPHELI' satirlar yeniden YAZILMAZ; once fiziksel/izsel dogrulama yapilir.
with mk as (
  select m.id, m.mk_no, m.otel_id, m.depo_kodu,
         (select max(a.server_timestamp) from public.erp_islem_audit a
           where a.entity_type = 'mal_kabuller' and a.entity_id = m.id::text and a.event_type = 'UPDATE') as onay_zamani
    from public.mal_kabuller m
   where m.durum = 'onaylandi' and coalesce(m.stok_islendi, false) = false)
select mk.mk_no, k.urun_kodu, k.miktar as kalem_miktar,
       (select count(*) from public.stok_hareketleri h
         where h.belge_no = mk.mk_no and h.urun_kodu = k.urun_kodu and h.tip = 'giris') as eslesen_hareket,
       s.miktar as otelde_toplam_stok, s.guncelleme_tarihi as stok_son_degisim, s.depo_sayisi, mk.onay_zamani,
       case
         when (select count(*) from public.stok_hareketleri h
                where h.belge_no = mk.mk_no and h.urun_kodu = k.urun_kodu and h.tip = 'giris') > 0
           then 'hareket VAR — kalem islenmis say'
         when mk.onay_zamani is not null and s.guncelleme_tarihi >= mk.onay_zamani
           then 'SUPHELI — hareket yok ama stok satiri onaydan SONRA degismis: yeniden yazma!'
         when coalesce(s.depo_sayisi, 0) = 0
           then 'stok satiri YOK — kalem islenmemis gorunuyor'
         else 'hareket yok ve stok satiri onaydan beri degismemis — islenmemis gorunuyor'
       end as degerlendirme
  from mk
  join public.mal_kabul_urunleri k on k.mk_id = mk.id
  -- Mal kabulun yazdigi depo kodu bilesik olabilir; TAHMIN etmiyoruz: urunun o
  -- OTELDEKI tum stok satirlari birlikte degerlendirilir (son degisim zamani esas).
  left join lateral (
    select max(s2.guncelleme_tarihi) as guncelleme_tarihi, sum(s2.miktar) as miktar, count(*) as depo_sayisi
      from public.stok s2 where s2.urun_kodu = k.urun_kodu and s2.otel_id = mk.otel_id) s on true
 where coalesce(k.urun_kodu, '') <> '' and k.miktar > 0
 order by mk.mk_no, k.urun_kodu;

\echo '== 4b) AYNI BELGEYE YAZILMIS TUM HAREKETLER (fazla/mukerrer var mi?)'
select h.belge_no, h.urun_kodu, h.tip, h.miktar, h.tarih, h.aciklama
  from public.stok_hareketleri h
 where h.belge_no in (select mk_no from public.mal_kabuller
                       where durum = 'onaylandi' and coalesce(stok_islendi, false) = false)
 order by h.belge_no, h.urun_kodu, h.tarih;

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
