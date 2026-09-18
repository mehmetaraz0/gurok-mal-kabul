-- ===========================================================================
-- STOK TARIH YAYINI — DUMAN TESTI HAZIRLIGI (SALT OKUMA)
-- ===========================================================================
-- Amac: duman testine GIRMEDEN once, hangi belge / urun / depo ile ve hangi
-- yan etkilerle test yapilacagini olcmek. Hicbir sey yazmaz.
--
--   .\docs\kurulum\sql-uygula.ps1 -Dosya docs\kurulum\2026-09-18-stok-tarih-duman-hazirlik.sql -SaltOkuma
-- ===========================================================================
set default_transaction_read_only = on;
\pset pager off

\echo '=== 1) OPERASYONEL OLARAK BEKLEYEN MAL KABULLER (kullanici secer) ==='
-- Karar 2: zaten onaylanacak gercek bir belge varsa duman testinin "giris"i
-- o olur. Siparise bagli olanlar ayrica siparis_kalemleri/siparisler yazar.
select mk.mk_no, mk.otel_id, mk.depo_kodu, mk.firma_ad, mk.form_tarihi,
       mk.ln_siparis_no is not null as siparise_bagli,
       count(u.*) as kalem_sayisi,
       string_agg(u.urun_kodu || ' ' || u.miktar::text || ' ' || coalesce(u.birim, ''), ', ' order by u.urun_kodu) as kalemler
  from public.mal_kabuller mk
  left join public.mal_kabul_urunleri u on u.mk_id = mk.id
 where mk.durum = 'bekleyen'
 group by mk.id
 order by mk.form_tarihi desc nulls last
 limit 20;

\echo '=== 2) GUVENLIK AGI: onaylanmis ama stoga ISLENMEMIS belgeler ==='
-- stok-takip.html ACILDIGINDA bunlari kendiliginden stoga isler. Pencere
-- sirasinda biri ekrani acarsa T0-T2 arasina yabanci yazma girer.
select mk.mk_no, mk.otel_id, mk.firma_ad, mk.form_tarihi,
       string_agg(u.urun_kodu || ' ' || u.miktar::text, ', ' order by u.urun_kodu) as kalemler
  from public.mal_kabuller mk
  left join public.mal_kabul_urunleri u on u.mk_id = mk.id
 where mk.durum = 'onaylandi' and mk.stok_islendi = false
 group by mk.id;

\echo '=== 3) GIZLI YAN ETKILER: ilgili tablolardaki tetikleyiciler ==='
select c.relname as tablo, t.tgname, t.tgenabled,
       p.oid::regprocedure as fonksiyon
  from pg_trigger t
  join pg_class c on c.oid = t.tgrelid
  join pg_proc p on p.oid = t.tgfoid
 where not t.tgisinternal
   and c.relnamespace = 'public'::regnamespace
   and c.relname in ('mal_kabuller', 'mal_kabul_urunleri', 'koli_etiketleri', 'skt_kayitlari',
                     'stok', 'stok_hareketleri', 'siparisler', 'siparis_kalemleri')
 order by 1, 2;

\echo '=== 4) mal_kabul_kaydet / stok RPC''lerinin YAZDIGI tablolar ==='
select p.oid::regprocedure as fonksiyon,
       (select string_agg(distinct m[1], ', ')
          from regexp_matches(p.prosrc, '(?:insert\s+into|update)\s+(?:public\.)?([a-z_]+)', 'gi') m) as yazdigi_tablolar
  from pg_proc p
 where p.pronamespace = 'public'::regnamespace
   and p.proname in ('mal_kabul_kaydet', 'stok_ekle', 'stok_transfer')
 order by 1;

\echo '=== 5) MK NUMARALANDIRMA (istemci: bu yilin belge SAYISI + 1) ==='
select count(*) filter (where mk_no like 'MK-' || extract(year from now())::int || '-%') as bu_yil_belge,
       max(mk_no) as en_buyuk_mk_no,
       exists (select 1 from pg_index i join pg_attribute a on a.attrelid = i.indrelid and a.attnum = any(i.indkey)
                where i.indrelid = 'public.mal_kabuller'::regclass and i.indisunique and a.attname = 'mk_no') as mk_no_tekil_mi
  from public.mal_kabuller;

\echo '=== 6) SESSIZ ADAY URUNLER (810_100 + ayni otelde ikinci depo, son 14 gun hareketsiz) ==='
-- Duman testi icin: satirlar ZATEN var (transfer yeni satir yaratmasin),
-- merkez depoda en az 2 birim, iki satirda da son 14 gun hareket yok,
-- bekleyen / islenmemis hicbir belgede gecmiyor.
with son_hareket as (
  select urun_kodu, depo_kodu, max(tarih) as son from public.stok_hareketleri group by 1, 2
  union all
  select urun_kodu, kaynak_depo_kodu, max(tarih) from public.stok_hareketleri
   where kaynak_depo_kodu is not null group by 1, 2
), sessiz as (
  select s.urun_kodu, s.depo_kodu, s.miktar,
         (select max(h.son) from son_hareket h where h.urun_kodu = s.urun_kodu and h.depo_kodu = s.depo_kodu) as son_hareket
    from public.stok s
), belgede as (
  select distinct u.urun_kodu from public.mal_kabul_urunleri u
    join public.mal_kabuller mk on mk.id = u.mk_id
   where mk.durum = 'bekleyen' or (mk.durum = 'onaylandi' and mk.stok_islendi = false)
)
select m.urun_kodu, ur.ad as urun_adi, ur.birim,
       m.miktar as merkez_810_100, m.son_hareket as merkez_son_hareket,
       d.depo_kodu as ikinci_depo, d.miktar as ikinci_miktar, d.son_hareket as ikinci_son_hareket
  from sessiz m
  join sessiz d on d.urun_kodu = m.urun_kodu and d.depo_kodu like '810\_%' and d.depo_kodu <> '810_100'
  left join public.urunler ur on ur.kod = m.urun_kodu
 where m.depo_kodu = '810_100'
   and m.miktar >= 2
   and coalesce(m.son_hareket, '-infinity') < now() - interval '14 days'
   and coalesce(d.son_hareket, '-infinity') < now() - interval '14 days'
   and m.urun_kodu not in (select urun_kodu from belgede where urun_kodu is not null)
 order by m.urun_kodu, d.depo_kodu
 limit 15;

\echo '=== 7) YAZMA YOGUNLUGU: son 7 gun, saat basina stok hareketi (sessiz pencere secimi) ==='
select extract(hour from tarih at time zone 'Europe/Istanbul')::int as saat_tr,
       count(*) as hareket
  from public.stok_hareketleri
 where tarih > now() - interval '7 days'
 group by 1 order by 1;
