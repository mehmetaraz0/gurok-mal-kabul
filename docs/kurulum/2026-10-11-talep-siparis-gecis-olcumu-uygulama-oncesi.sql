-- ============================================================================
-- GECIS OLCUMU — UYGULAMA ONCESI · SALT OKUMA
-- Tasarim: docs/superpowers/specs/2026-10-11-talep-siparis-bagi-design.md §10
--
-- NEDEN AYRI DOSYA: kardes dosya
-- `2026-10-11-talep-siparis-gecis-olcumu.sql` UYGULAMA SONRASI icindir —
-- `talep_siparis_baglari` tablosunu ve gorunumun yeni `birim` kolonunu
-- sorgular. Ikisi de henuz URETIMDE YOK; `ON_ERROR_STOP=1` ile ilk sorguda
-- duser. Bu dosya YALNIZ bugun var olan nesnelere dokunur.
--
-- Uygulama ONCESI bag tablosu olmadigi icin "bagi olmayan talep" = durumu
-- 'siparis' veya 'siparise_donustu' olan HER talep. Karar bu listeye bakilarak
-- verilir; otomatik iptal ve otomatik baglama YAPILMAZ (tasarim §10).
--
-- Calistirma (SALT OKUMA, hicbir sey yazmaz):
--   .\docs\kurulum\sql-uygula.ps1 -Dosya docs\kurulum\2026-10-11-talep-siparis-gecis-olcumu-uygulama-oncesi.sql -SaltOkuma
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1) OZET: hangi etikette kac talep var?
--
-- Eski gorunum (`2026-10-11-stok-acik-talep-durum-filtresi.sql`) IKI etiketi
-- disliyordu: 'siparis' ve 'siparise_donustu'. Yeni gorunum yalniz
-- ('iptal','reddedildi') disliyor ve kalani BAG toplamindan hesapliyor.
-- Bag olmadigi icin bu taleplerin TAMAMI yeni gorunumde yeniden ACIK gorunur.
-- Tasarim §10 yalniz 'siparis' olanlari (7 kayit) olcmustu; 'siparise_donustu'
-- populasyonu HIC olculmedi.
-- ---------------------------------------------------------------------------
select t.durum::text                              as durum,
       count(*)                                   as talep_sayisi,
       count(*) filter (where t.siparis_no is not null) as siparis_no_dolu,
       count(*) filter (where t.siparis_no is null)     as siparis_no_bos,
       min(t.olusturma_tarihi)::date              as en_eski,
       max(t.olusturma_tarihi)::date              as en_yeni
  from public.satin_alma_talepleri t
 where t.durum::text in ('siparis', 'siparise_donustu')
 group by t.durum
 order by t.durum::text;

-- ---------------------------------------------------------------------------
-- 2) LISTE: yeni gorunumde yeniden acik gorunecek talepler
--
-- Karar bu listeye gore verilir. `olu_kolon_siparis_no` bugunku tek izdir ve
-- hic doldurulmadigi icin cogunlukla bos olmasi beklenir — kusurun kendisi.
-- ---------------------------------------------------------------------------
select t.durum::text        as durum,
       t.id,
       t.otel_id::text      as otel_id,
       t.talep_no,
       t.departman,
       t.siparis_no         as olu_kolon_siparis_no,
       t.olusturma_tarihi::date as olusturma,
       count(tk.id)         as kalem_sayisi
  from public.satin_alma_talepleri t
  left join public.satin_alma_talep_kalemleri tk on tk.talep_id = t.id
 where t.durum::text in ('siparis', 'siparise_donustu')
 group by t.durum, t.id, t.otel_id, t.talep_no, t.departman, t.siparis_no,
          t.olusturma_tarihi
 order by t.durum::text, t.olusturma_tarihi;

-- ---------------------------------------------------------------------------
-- 3) ETKI BUYUKLUGU: bu talepler gorunume birim bazinda ne EKLER?
--
-- Birimler TOPLANMAZ — farkli birimlerin toplami anlamsizdir.
-- ---------------------------------------------------------------------------
select tk.birim,
       count(*)        as kalem_sayisi,
       sum(tk.miktar)  as eklenecek_miktar
  from public.satin_alma_talep_kalemleri tk
  join public.satin_alma_talepleri t on t.id = tk.talep_id
 where t.durum::text in ('siparis', 'siparise_donustu')
 group by tk.birim
 order by tk.birim;

-- ---------------------------------------------------------------------------
-- 4) BUGUNKU GORUNUM TOPLAMI (karsilastirma tabani)
--
-- Eski gorunum `birim` kolonu DONDURMEZ; o yuzden burada secilmiyor.
-- Uygulamadan sonra bu sayinin madde 3 kadar artmasi beklenir.
-- ---------------------------------------------------------------------------
select count(*)                 as gorunum_satir_sayisi,
       count(distinct urun_kodu) as urun_sayisi
  from public.stok_acik_talep;

-- ---------------------------------------------------------------------------
-- 5) UYGULAMA SONRASI BAGLANAMAYACAK KALEMLER — beklenen 0 satir
--
-- Yeni yolda bag, kalemin birimine CEVRILEBILIYORSA kurulur. Kalemin birimi
-- ne urunun katalog birimi ne de tanimli buyuk birim ise, o kalem icin
-- siparis olusturma `birim_cevrilemez` ile REDDEDILIR. Satir cikarsa bu
-- kalemler yayindan sonra siparise donusturulemez; once katalog duzeltilmeli.
-- ---------------------------------------------------------------------------
select tk.id              as talep_kalem_id,
       t.otel_id::text    as otel_id,
       t.talep_no,
       tk.urun_kodu,
       tk.birim           as kalem_birimi,
       u.birim            as katalog_birimi,
       d.buyuk_birim      as tanimli_buyuk_birim,
       d.carpan
  from public.satin_alma_talep_kalemleri tk
  join public.satin_alma_talepleri t on t.id = tk.talep_id
  left join public.urunler u on u.kod = tk.urun_kodu
  left join public.urun_birim_donusum d
         on d.urun_kodu = tk.urun_kodu and d.silindi = false
 where t.durum::text not in ('iptal', 'reddedildi')
   and tk.birim is distinct from u.birim
   and tk.birim is distinct from d.buyuk_birim
 order by t.otel_id, tk.urun_kodu;

-- ---------------------------------------------------------------------------
-- 6) ONKOSUL KONTROLU: yeni nesneler henuz YOK olmali
--
-- Hepsi `f` donmeli. Biri `t` donerse bu dosya degil kardes dosya
-- (`...-gecis-olcumu.sql`) kosulmalidir.
-- ---------------------------------------------------------------------------
select to_regclass('public.talep_siparis_baglari') is not null as bag_tablosu_var,
       to_regclass('public.siparis_no_sayac')      is not null as sayac_var,
       to_regprocedure('public.siparis_no_uret(text)') is not null as uretec_var,
       exists (select 1 from information_schema.columns
                where table_schema='public' and table_name='stok_acik_talep'
                  and column_name='birim')                  as gorunum_birim_var;
