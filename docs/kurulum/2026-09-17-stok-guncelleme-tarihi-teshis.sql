-- ===========================================================================
-- TESHIS (SALT OKUMA): stok.guncelleme_tarihi neden transferde degismiyor?
-- ===========================================================================
-- Calistirma:
--   .\docs\kurulum\sql-uygula.ps1 -Dosya docs\kurulum\2026-09-17-stok-guncelleme-tarihi-teshis.sql -SaltOkuma
-- -SaltOkuma yalniz tek-islem sarmalayicisini kaldirir; veritabani duzeyinde
-- salt okumayi ASAGIDAKI satir zorlar. Hicbir yazma yoktur.
-- ===========================================================================
set default_transaction_read_only = on;
\pset pager off

\echo '--- 1) stok_ekle / stok_transfer: imza, guvenlik, ayar, govde ozeti, sutun bahsi ---'
select p.oid::regprocedure as imza,
       p.prosecdef as security_definer,
       p.proconfig as ayarlar,
       md5(p.prosrc) as govde_md5,
       p.prosrc ~* 'guncelleme_tarihi' as govdede_guncelleme_tarihi
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
 where n.nspname = 'public' and p.proname in ('stok_ekle', 'stok_transfer')
 order by 1;

\echo '--- 2) Tam govdeler ---'
select pg_get_functiondef(p.oid)
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
 where n.nspname = 'public' and p.proname in ('stok_ekle', 'stok_transfer')
 order by p.proname;

\echo '--- 3) public.stok uzerindeki kullanici tetikleyicileri (varsa sutunu o mu guncelliyor?) ---'
select t.tgname, t.tgenabled, pg_get_triggerdef(t.oid) as tanim,
       p.oid::regprocedure as fonksiyon,
       p.prosrc ~* 'guncelleme_tarihi' as fonksiyonda_sutun
  from pg_trigger t join pg_proc p on p.oid = t.tgfoid
 where t.tgrelid = 'public.stok'::regclass and not t.tgisinternal;

\echo '--- 4) Sutun tanimi (varsayilan / null) ---'
select column_name, data_type, is_nullable, column_default
  from information_schema.columns
 where table_schema = 'public' and table_name = 'stok'
   and column_name in ('guncelleme_tarihi', 'olusturma_tarihi', 'miktar');

\echo '--- 5) public.stok a YAZAN tum fonksiyonlar ve sutunu set edip etmedikleri ---'
select p.oid::regprocedure as fonksiyon,
       p.prosrc ~* 'guncelleme_tarihi' as sutundan_bahsediyor
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
 where n.nspname = 'public'
   and p.prosrc ~* '(update|insert\s+into)\s+(public\.)?stok\M'
 order by 1;

\echo '--- 6) Duman testi satirlari (YIY01000002) ---'
select depo_kodu, otel_id, miktar, guncelleme_tarihi
  from public.stok where urun_kodu = 'YIY01000002' order by depo_kodu;

\echo '--- 7) Ayni urunun son hareketleri ---'
select *
  from public.stok_hareketleri where urun_kodu = 'YIY01000002'
 order by tarih desc limit 10;

\echo '--- 8) OLCUM: son hareketi guncelleme_tarihi nden 1 dk+ SONRA olan stok satirlari, hareket tipine gore ---'
-- Sutun dogru guncelleniyorsa bu sayilar ~0 olmali. Tip kirilimi hangi
-- yazma yolunun (giris/cikis = stok_ekle, transfer = stok_transfer) bozuk
-- oldugunu ayirir.
with son as (
  select distinct on (h.urun_kodu, h.depo_kodu)
         h.urun_kodu, h.depo_kodu, h.tip, h.tarih
    from public.stok_hareketleri h
   order by h.urun_kodu, h.depo_kodu, h.tarih desc
)
select son.tip,
       count(*) as satir,
       count(*) filter (where son.tarih > s.guncelleme_tarihi + interval '1 minute') as bayat,
       max(son.tarih) as en_yeni_hareket
  from son join public.stok s
    on s.urun_kodu = son.urun_kodu and s.depo_kodu = son.depo_kodu
 group by son.tip order by son.tip;

\echo '--- 9) Genel dagilim: guncelleme_tarihi en yeni degerleri ---'
select count(*) as toplam_satir,
       max(guncelleme_tarihi) as en_yeni,
       count(*) filter (where guncelleme_tarihi >= now() - interval '30 days') as son_30_gun
  from public.stok;

\echo '--- 10) stok_liste gorunumu sutunu tasiyor mu ---'
select pg_get_viewdef('public.stok_liste'::regclass) ~* 'guncelleme_tarihi' as gorunumde_var;
