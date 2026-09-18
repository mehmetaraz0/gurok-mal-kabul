-- ===========================================================================
-- STOK TARIH YAYINI — ANLIK GORUNTU (SALT OKUMA)
-- ===========================================================================
-- Yayin boyunca UC kez ayni dosya calistirilir; ciktilar karsilastirilir:
--   T0  yedekten ve migration'dan ONCE  -> onkosullar + "oncesi" fotografi
--   T1  migration'dan hemen SONRA       -> satir parmak izi T0 ile AYNI olmali
--                                          (migration hicbir satira dokunmaz)
--   T2  duman testinden SONRA           -> yalniz duman testinin yazdigi
--                                          satirlar degismis olmali
--
--   .\docs\kurulum\sql-uygula.ps1 -Dosya docs\kurulum\2026-09-18-stok-tarih-yayin-anlik.sql -SaltOkuma
--
-- Veritabani duzeyinde salt okumayi asagidaki satir zorlar; hicbir yazma yok.
-- ===========================================================================
set default_transaction_read_only = on;
\pset pager off

\echo '=== A) ZAMAN DAMGASI (sunucu saati) ==='
select now() as sunucu_saati;

\echo '=== B) FONKSIYON DURUMU ==='
-- T0: olcumle_ayni = t, tarih_duzeltmesi = f   (migration uygulanabilir)
-- T1/T2: tarih_duzeltmesi = t                  (migration uygulanmis)
-- bar_a1_izi her zaman f olmali: bu yayin A1'i ICERMEZ.
select p.proname,
       md5(p.prosrc) as md5,
       md5(p.prosrc) in ('24d255cc03df86bb4c9f6c978cadce81', '4c6fe1217463841653bec7637f3bf259') as olcumle_ayni,
       p.prosrc ~* 'guncelleme_tarihi\s*=\s*now\(\)' as tarih_duzeltmesi,
       p.prosrc ~* 'stok_cikis_korumasi' as bar_a1_izi,
       p.prosecdef as security_definer,
       p.proconfig as ayarlar
  from pg_proc p
 where p.pronamespace = 'public'::regnamespace and p.proname in ('stok_ekle', 'stok_transfer')
 order by 1;

select to_regprocedure('public.stok_cikis_korumasi(text,text,numeric)') is null as bar_a1_fonksiyonu_yok;

\echo '=== C) ONKOSULLAR (beklenen: anon f, public_ f, authenticated t, service_role t) ==='
select p.oid::regprocedure as fonksiyon, p.proacl,
       has_function_privilege('anon', p.oid, 'EXECUTE') as anon,
       (p.proacl is null or exists (select 1 from aclexplode(p.proacl) a
                                     where a.grantee = 0 and a.privilege_type = 'EXECUTE')) as public_,
       has_function_privilege('authenticated', p.oid, 'EXECUTE') as authenticated,
       has_function_privilege('service_role', p.oid, 'EXECUTE') as service_role
  from pg_proc p
 where p.pronamespace = 'public'::regnamespace and p.proname in ('stok_ekle', 'stok_transfer')
 order by 1;

select has_column_privilege('authenticated', 'public.stok', 'guncelleme_tarihi', 'UPDATE') as sutun_authenticated,
       has_column_privilege('service_role', 'public.stok', 'guncelleme_tarihi', 'UPDATE') as sutun_service_role;

\echo '=== D) SATIR PARMAK IZI (T0 = T1 olmali; T2 de duman satirlari haric ayni) ==='
select count(*) as satir,
       md5(string_agg(urun_kodu || '|' || depo_kodu || '|' || miktar::text || '|' || guncelleme_tarihi::text,
                      E'\n' order by urun_kodu, depo_kodu)) as parmak_izi,
       max(guncelleme_tarihi) as en_yeni_tarih
  from public.stok;

\echo '=== E) SATIR SATIR GORUNTU (karsilastirma icin) ==='
select urun_kodu, depo_kodu, otel_id, miktar, guncelleme_tarihi
  from public.stok
 order by urun_kodu, depo_kodu;

\echo '=== F) YAZMA IZLERI (duman testi bunlari artirmali) ==='
select (select count(*) from public.stok_hareketleri) as hareket_sayisi,
       (select max(tarih) from public.stok_hareketleri) as son_hareket,
       (select count(*) from public.erp_islem_audit) as audit_satiri,
       (select max(server_timestamp) from public.erp_islem_audit) as son_audit;

\echo '=== G) SON 10 STOK HAREKETI ==='
select tarih, tip, urun_kodu, depo_kodu, kaynak_depo_kodu, miktar
  from public.stok_hareketleri
 order by tarih desc
 limit 10;
