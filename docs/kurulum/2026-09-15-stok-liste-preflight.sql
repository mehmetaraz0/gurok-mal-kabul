-- ============================================================================
-- STOK LISTE/OZET MIGRATION'I — YAYIN ONCESI PREFLIGHT (SALT OKUMA)
-- Tarih: 2026-09-15
-- ============================================================================
-- Hicbir sey YAZMAZ. Migration'in varsayimlarini uretim uzerinde dogrular:
--   1. Beklenen tablolar ve sutunlar var mi?
--   2. Eklenecek isimler (stok_liste, stok_ozet, stok_kategoriler,
--      stok_abc_girdi) zaten kullaniliyor mu?
--   3. Migration sonrasi karsilastirilacak sayaclar.
-- ============================================================================

\echo '--- 1) Gerekli tablolar ve sutunlar ---'
select
  c.relname as tablo,
  count(*) filter (where a.attname = 'otel_id')   as otel_id,
  count(*) filter (where a.attname = 'depo_kodu') as depo_kodu,
  count(*) filter (where a.attname = 'urun_kodu') as urun_kodu,
  count(*) filter (where a.attname = 'miktar')    as miktar
from pg_class c
join pg_namespace n on n.oid = c.relnamespace
join pg_attribute a on a.attrelid = c.oid and a.attnum > 0 and not a.attisdropped
where n.nspname = 'public'
  and c.relname in ('stok', 'urunler', 'stok_minimumlar', 'stok_hareketleri')
group by c.relname
order by c.relname;

\echo '--- 2) Eklenecek isimler bos mu? (satir cikarsa CAKISMA var) ---'
select n.nspname as sema, c.relname as nesne, c.relkind as tur
  from pg_class c join pg_namespace n on n.oid = c.relnamespace
 where n.nspname = 'public' and c.relname = 'stok_liste';

select n.nspname as sema, p.proname as fonksiyon,
       pg_get_function_identity_arguments(p.oid) as imza
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
 where n.nspname = 'public'
   and p.proname in ('stok_ozet', 'stok_kategoriler', 'stok_abc_girdi');

\echo '--- 3) Sayaclar (migration sonrasi ayni degerler beklenir) ---'
select 'stok' as tablo, count(*) as adet from public.stok
union all select 'urunler', count(*) from public.urunler
union all select 'stok_minimumlar', count(*) from public.stok_minimumlar
union all select 'stok_hareketleri', count(*) from public.stok_hareketleri
order by 1;

\echo '--- 4) stok uzerindeki RLS ve politikalar (degismemeli) ---'
select c.relname as tablo, c.relrowsecurity as rls_acik, c.relforcerowsecurity as rls_zorunlu
  from pg_class c join pg_namespace n on n.oid = c.relnamespace
 where n.nspname = 'public' and c.relname in ('stok', 'stok_hareketleri', 'urunler')
 order by 1;

select polname as politika, polcmd as komut, pg_get_expr(polqual, polrelid) as kosul
  from pg_policy
 where polrelid = 'public.stok'::regclass
 order by polname;

\echo '--- 5) Yardimci yetki fonksiyonlari (gorunum bunlarin uzerine oturur) ---'
select p.proname, p.prosecdef as security_definer,
       pg_get_function_identity_arguments(p.oid) as imza
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
 where n.nspname = 'public' and p.proname in ('auth_yetki_var', 'auth_otel_erisim', 'auth_tum_oteller')
 order by 1;

\echo '--- 6) Depo basina satir dagilimi (sayfalama yuku) ---'
select depo_kodu, otel_id, count(*) as satir
  from public.stok
 group by 1, 2
 order by 3 desc
 limit 20;
