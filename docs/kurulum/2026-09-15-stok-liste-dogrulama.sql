-- ============================================================================
-- STOK LISTE/OZET — MIGRATION SONRASI DOGRULAMA (SALT OKUMA)
-- Tarih: 2026-09-15
-- ============================================================================
-- Migration'in kendi dogrulama blogu ACL ve security_invoker'i kontrol etti.
-- Bu dosya BAGIMSIZ bir okuma: nesneler gercekten dogru veriyi mi veriyor?
-- Hicbir sey yazmaz.
-- ============================================================================

\echo '--- 1) stok_liste satir sayisi = stok satir sayisi (esit OLMALI) ---'
select (select count(*) from public.stok)       as stok,
       (select count(*) from public.stok_liste) as stok_liste,
       case when (select count(*) from public.stok) = (select count(*) from public.stok_liste)
            then 'ESIT' else 'FARKLI — DUR' end as sonuc;

\echo '--- 2) stok_ozet(null) toplami = stok satir sayisi ---'
select o.toplam, o.kritik, o.uyari, o.normal,
       case when o.toplam = (select count(*) from public.stok)
            then 'ESIT' else 'FARKLI — DUR' end as sonuc
  from public.stok_ozet(null) o;

\echo '--- 3) Depo bazinda: liste, ozet ve ham tablo ayni mi? ---'
select s.depo_kodu,
       s.ham,
       (select count(*) from public.stok_liste l where l.depo_kodu = s.depo_kodu) as liste,
       (select toplam from public.stok_ozet(s.depo_kodu)) as ozet
  from (select depo_kodu, count(*) as ham from public.stok group by 1) s
 order by 1;

\echo '--- 4) Kategoriler ve ABC girdileri cikiyor mu? ---'
select count(*) as kategori_adedi from public.stok_kategoriler(null);
select count(*) as abc_urun_adedi,
       sum(stok_miktar) as toplam_stok,
       sum(tuketim_miktar) as toplam_tuketim
  from public.stok_abc_girdi(7);

\echo '--- 5) Nesnelerin guvenlik ayarlari (security_invoker / INVOKER) ---'
select c.relname as gorunum,
       (c.reloptions::text like '%security_invoker=true%') as security_invoker
  from pg_class c join pg_namespace n on n.oid = c.relnamespace
 where n.nspname = 'public' and c.relname = 'stok_liste';

select p.proname as fonksiyon, p.prosecdef as security_definer, p.provolatile as volatilite,
       p.proconfig as ayarlar
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
 where n.nspname = 'public' and p.proname in ('stok_ozet','stok_kategoriler','stok_abc_girdi')
 order by 1;

\echo '--- 6) Yetkiler: anon KAPALI, authenticated ACIK olmali ---'
select 'stok_liste (select)' as nesne,
       has_table_privilege('anon','public.stok_liste','select') as anon,
       has_table_privilege('authenticated','public.stok_liste','select') as authenticated
union all
select 'stok_ozet (execute)',
       has_function_privilege('anon','public.stok_ozet(text)','execute'),
       has_function_privilege('authenticated','public.stok_ozet(text)','execute')
union all
select 'stok_kategoriler (execute)',
       has_function_privilege('anon','public.stok_kategoriler(text)','execute'),
       has_function_privilege('authenticated','public.stok_kategoriler(text)','execute')
union all
select 'stok_abc_girdi (execute)',
       has_function_privilege('anon','public.stok_abc_girdi(integer)','execute'),
       has_function_privilege('authenticated','public.stok_abc_girdi(integer)','execute');

\echo '--- 7) Preflight sayaclari degismedi mi? (24 / 1264 / 0 / 75 bekleniyor) ---'
select 'stok' as tablo, count(*) as adet from public.stok
union all select 'urunler', count(*) from public.urunler
union all select 'stok_minimumlar', count(*) from public.stok_minimumlar
union all select 'stok_hareketleri', count(*) from public.stok_hareketleri
order by 1;

\echo '--- 8) stok uzerindeki politikalar degismedi mi? (4 politika) ---'
select count(*) as politika_adedi from pg_policy where polrelid = 'public.stok'::regclass;
