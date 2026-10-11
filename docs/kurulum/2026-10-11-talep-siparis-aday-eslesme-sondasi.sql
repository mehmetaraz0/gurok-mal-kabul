-- ============================================================================
-- BAGSIZ 7 TALEP ICIN ADAY SIPARIS ESLESMESI — SALT OKUMA
-- Tasarim: docs/superpowers/specs/2026-10-11-talep-siparis-bagi-design.md §10
--
-- NEDEN: §10'un uc secenegi de ayni bilinmeyene dayaniyor — bu 7 talep
-- GERCEKTEN siparis edildi mi? Eski akis siparisi BIR SONRAKI sayfada
-- olusturuyordu, yani bazilari icin siparis yazilmis olabilir; bag hicbir
-- yerde kayitli olmadigi icin de bilinmiyor.
--
-- BU SONDA KARAR VERMEZ, KARARI DARALTIR. Cikti ADAY'dir: ayni otel, ayni
-- urun, talep tarihinden sonraki 21 gun. Esleşme kesinligi INSAN BILGISIDIR
-- (§10) — sonda yalniz "bu talebin urunu o tarihlerde hic siparis edilmis
-- mi?" sorusunu yanitlar.
--
-- Hicbir sey yazmaz, islem acmaz.
--
-- Calistirma:
--   .\docs\kurulum\sql-uygula.ps1 -Dosya docs\kurulum\2026-10-11-talep-siparis-aday-eslesme-sondasi.sql -SaltOkuma
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1) OZET: 17 kalemin kacinda aday siparis var?
--
-- `aday_yok` olan kalemler icin "gercekten siparis edildi" ihtimali DUSUKTUR;
-- o talepler yeni gorunumde hakli olarak acik gorunur.
-- ---------------------------------------------------------------------------
with bagsiz as (
  select t.id, t.otel_id, t.olusturma_tarihi
    from public.satin_alma_talepleri t
   where t.durum::text in ('siparis', 'siparise_donustu')
), kalem as (
  select b.id as talep_id, b.otel_id, b.olusturma_tarihi,
         tk.id as kalem_id, tk.urun_kodu, tk.urun_adi, tk.miktar, tk.birim
    from bagsiz b
    join public.satin_alma_talep_kalemleri tk on tk.talep_id = b.id
), aday as (
  select k.kalem_id,
         count(*) as aday_sayisi
    from kalem k
    join public.siparis_kalemleri sk
      on (k.urun_kodu is not null and sk.urun_kodu = k.urun_kodu)
      or (k.urun_kodu is null and sk.urun_adi = k.urun_adi)
    join public.siparisler s on s.siparis_no = sk.siparis_no
   where s.otel_id = k.otel_id
     and s.tarih >= k.olusturma_tarihi::date
     and s.tarih <= k.olusturma_tarihi::date + 21
   group by k.kalem_id
)
select case when a.aday_sayisi is null then 'aday_yok' else 'aday_var' end as durum,
       count(*) as kalem_sayisi
  from kalem k
  left join aday a on a.kalem_id = k.kalem_id
 group by 1
 order by 1;

-- ---------------------------------------------------------------------------
-- 2) TALEP BAZINDA: hangi talebin kac kaleminde aday var?
--
-- Butun kalemlerinde aday OLMAYAN talep, "siparis edilmemis" adayidir.
-- Butun kalemlerinde aday OLAN talep, "edilmis olabilir" adayidir.
-- ---------------------------------------------------------------------------
with bagsiz as (
  select t.id, t.otel_id, t.talep_no, t.departman, t.olusturma_tarihi
    from public.satin_alma_talepleri t
   where t.durum::text in ('siparis', 'siparise_donustu')
), kalem as (
  select b.id as talep_id, b.otel_id, b.talep_no, b.departman, b.olusturma_tarihi,
         tk.id as kalem_id, tk.urun_kodu, tk.urun_adi
    from bagsiz b
    join public.satin_alma_talep_kalemleri tk on tk.talep_id = b.id
), esli as (
  select distinct k.kalem_id
    from kalem k
    join public.siparis_kalemleri sk
      on (k.urun_kodu is not null and sk.urun_kodu = k.urun_kodu)
      or (k.urun_kodu is null and sk.urun_adi = k.urun_adi)
    join public.siparisler s on s.siparis_no = sk.siparis_no
   where s.otel_id = k.otel_id
     and s.tarih >= k.olusturma_tarihi::date
     and s.tarih <= k.olusturma_tarihi::date + 21
)
select k.talep_id,
       k.departman,
       k.olusturma_tarihi::date                  as talep_tarihi,
       count(*)                                  as kalem_sayisi,
       count(e.kalem_id)                         as aday_bulunan_kalem,
       count(*) - count(e.kalem_id)              as adaysiz_kalem
  from kalem k
  left join esli e on e.kalem_id = k.kalem_id
 group by k.talep_id, k.departman, k.olusturma_tarihi
 order by (count(*) - count(e.kalem_id)) desc, k.olusturma_tarihi;

-- ---------------------------------------------------------------------------
-- 3) AYRINTI: kalem basina aday siparisler (en fazla ilk 3 aday)
--
-- Insan bu tabloya bakarak karar verir. `gun_fark` kucukse esleşme ihtimali
-- yuksektir; miktar da tutuyorsa daha da yuksek.
-- ---------------------------------------------------------------------------
with bagsiz as (
  select t.id, t.otel_id, t.departman, t.olusturma_tarihi
    from public.satin_alma_talepleri t
   where t.durum::text in ('siparis', 'siparise_donustu')
), kalem as (
  select b.id as talep_id, b.otel_id, b.departman, b.olusturma_tarihi,
         tk.id as kalem_id, tk.urun_kodu, tk.urun_adi, tk.miktar, tk.birim
    from bagsiz b
    join public.satin_alma_talep_kalemleri tk on tk.talep_id = b.id
), aday as (
  select k.talep_id, k.departman, k.olusturma_tarihi::date as talep_tarihi,
         k.urun_kodu, k.urun_adi, k.miktar as talep_miktar, k.birim as talep_birim,
         s.siparis_no, s.tarih as siparis_tarihi, s.firma_ad, s.durum::text as siparis_durum,
         sk.miktar as siparis_miktar, sk.birim as siparis_birim,
         (s.tarih - k.olusturma_tarihi::date) as gun_fark,
         row_number() over (partition by k.kalem_id
                            order by abs(s.tarih - k.olusturma_tarihi::date),
                                     abs(sk.miktar - k.miktar)) as sira
    from kalem k
    join public.siparis_kalemleri sk
      on (k.urun_kodu is not null and sk.urun_kodu = k.urun_kodu)
      or (k.urun_kodu is null and sk.urun_adi = k.urun_adi)
    join public.siparisler s on s.siparis_no = sk.siparis_no
   where s.otel_id = k.otel_id
     and s.tarih >= k.olusturma_tarihi::date
     and s.tarih <= k.olusturma_tarihi::date + 21
)
select talep_id, departman, talep_tarihi, urun_kodu, urun_adi,
       talep_miktar, talep_birim,
       siparis_no, siparis_tarihi, gun_fark, siparis_miktar, siparis_birim,
       siparis_durum, firma_ad
  from aday
 where sira <= 3
 order by talep_tarihi, urun_kodu, sira;
