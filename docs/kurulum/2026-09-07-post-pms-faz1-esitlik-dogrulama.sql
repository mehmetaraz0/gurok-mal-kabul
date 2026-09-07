-- ============================================================================
-- POST-PMS-FAZ1 — ÜRETİM EŞİTLİK DOĞRULAMASI (SALT OKUMA)
-- ============================================================================
-- Bir veritabanının, PMS Faz 1 SONRASI üretimle eşit olup olmadığını sınar.
--
-- TABAN : 2026-09-07 doğrulanmış şema dökümü
--         (docs/kurulum/2026-09-07-post-pms-faz1-sema-dokumu.sql)
--         75 tablo · 234 politika · 40 kısıtlayıcı · 28 kapsam fonksiyonu
--
-- ESKİ DOSYA: docs/kurulum/2026-09-06-staging-esitlik-dogrulama.sql
--         PMS ÖNCESİ tabanı (66/193/31/26) temsil eder ve TARİHSEL KANIT
--         olarak durur. Silinmedi, değiştirilmedi. PMS uygulandıktan sonra
--         tasarımı gereği SAPMA raporlar; yeni ortamlar için BU dosya kullanılır.
--
-- KULLANIM:
--   node scripts/dokum-dogrula.mjs <dokum.sql> \
--        docs/kurulum/2026-09-07-post-pms-faz1-esitlik-dogrulama.sql
--   veya doğrudan hedef veritabanında (salt-okuma).
--
-- ÇIKTI: "SAPMA" ile başlayan satır varsa sorun var. Hiç yoksa yalnızca
-- "BILGI" satırları görünür.
--
-- ---------------------------------------------------------------------------
-- NEDEN md5(prosrc), md5(pg_get_functiondef) DEĞİL
-- ---------------------------------------------------------------------------
-- pg_get_functiondef gövdeyi SUNUCUNUN biçimlendiricisinden geçirir ve çıktısı
-- PostgreSQL minor sürümüne duyarlıdır. Üretim 17.6, doğrulama konteyneri
-- 17.11; ilk sürüm 26 fonksiyonun 25'ini, döküm kusursuz olsa bile "farklı"
-- göstermişti. prosrc ham gövdedir ve sürümden etkilenmez.
--
-- Bu dosyadaki hash'ler ELLE YAZILMADI; doğrulanmış dökümden çıkarıldı.
-- ============================================================================

with uretim(imza, secdef, ayarlar, govde_md5) as (values
  ('audit_log_damgala()',                            true,  'search_path=public',                                  '25c13af9bf1a0902e36b6fa840124b87'),
  ('auth_erp_kullanicisi()',                         true,  'search_path=pg_catalog, public, pg_temp',             'd2d7ccc47caefb11b475cd3ef026217b'),
  ('auth_kullanici_id()',                            true,  'search_path=pg_catalog, public, pg_temp',             'e737e12c33fa738df6fe9cef92512d98'),
  ('auth_kullanici_rol_id()',                        true,  'search_path=pg_catalog, public, pg_temp',             'd78add90861ae12056947927188a117b'),
  ('auth_otel_erisim(text)',                         true,  'search_path=pg_catalog, public, pg_temp',             '726e83b16316ee783c9ede8f8e734301'),
  ('auth_otel_id()',                                 true,  'search_path=pg_catalog, public, pg_temp',             'd3a58d923e16c24e70f4fae24d8f44b9'),
  ('auth_tum_oteller()',                             true,  'search_path=pg_catalog, public, pg_temp',             '47457292781f073bf9fef1455b44f70b'),
  ('auth_yetki_var(text,text)',                      true,  'search_path=pg_catalog, public, pg_temp',             'fc1351608035450f1a0d8af713416ae7'),
  ('bar_kullanilabilir_stok(text,text)',             true,  'search_path=public',                                  '7ad0d16150247564217e68e21e43b26c'),
  ('bar_siparis_durum_guncelle(uuid,bar_durum)',     true,  'search_path=pg_catalog, public, pg_temp',             'c323e93044d574953cd452cde53ba736'),
  ('bar_siparis_iptal(uuid)',                        true,  'search_path=pg_catalog, public, pg_temp',             '69d1a29b0759c275d11251801c956802'),
  ('bar_siparis_olustur(text,text,text,text,jsonb)', true,  'search_path=pg_catalog, public, pg_temp',             '69869a956520424545d8402a8ecc933e'),
  ('bar_siparis_teslim_et(uuid)',                    true,  'search_path=pg_catalog, public, pg_temp',             '202fb2660b8eb9d5d99c37c9d26cf2ab'),
  ('fatura_kaydet(uuid,jsonb,jsonb)',                true,  'search_path=pg_catalog, public, pg_temp',             '848950e28be36d41ab8e02170f62a803'),
  ('giris_kaydi_ekle(text)',                         true,  'search_path=public',                                  '2e36ac004fa0526f3942ae8c877a7260'),
  ('mal_kabul_kaydet(jsonb,jsonb)',                  true,  'search_path=pg_catalog, public, pg_temp',             'd57a5bb8a37fdad5ce4bd54eea268c74'),
  ('pin_ayarla(uuid,text)',                          true,  'search_path=public, extensions',                      'cd3138cf46711236fd3b382856c48557'),
  ('pin_dogrula(text,text)',                         true,  'search_path=public, extensions',                      '28296366cf39306b65da0d5097f34bf3'),
  ('pms_bar_folio_koprusu()',                        true,  'search_path=pg_catalog, public, pg_temp',             'ae9e7f6658111467eea7dc36e18caa16'),
  ('pms_folio_otomatik_ac()',                        true,  'search_path=pg_catalog, public, pg_temp',             '7aa9694513bda4f6f9d91f5d884215da'),
  ('rls_auto_enable()',                              true,  'search_path=pg_catalog',                              '99be20677b456ea8d3be47bdd44fb369'),
  ('siparis_yeniden_yonlendir(text,text)',           true,  'search_path=pg_catalog, public, pg_temp',             '129a4c9e08da85a1b0eb405065a157f1'),
  ('stok_ekle(text,text,text,numeric)',              false, 'search_path=pg_catalog, public, extensions, pg_temp', '24d255cc03df86bb4c9f6c978cadce81'),
  ('stok_transfer(text,text,text,text,numeric)',     false, 'search_path=pg_catalog, public, extensions, pg_temp', '4c6fe1217463841653bec7637f3bf259'),
  ('talep_asama_yetkili_mi(text,text,uuid)',         true,  'search_path=public',                                  'dfa97681636a6d1929bc5ecc533d1862'),
  ('talep_karar_ver(uuid,text,text,numeric)',        true,  'search_path=pg_catalog, public, pg_temp',             '52b6e4f176cdb9aa7ccb52097e90dd87'),
  ('talep_siparise_donustur(uuid)',                  true,  'search_path=pg_catalog, public, pg_temp',             'e658c914b5dacf646511b8cf4dd90234'),
  ('teklif_talebi_olustur(text,text,jsonb)',         true,  'search_path=pg_catalog, public, pg_temp',             'eb953f048b9938b7754b9bd8648e376e')
),
burada as (
  -- KAPSAM, PMS öncesi dosyayla AYNI kuraldır. Değiştirilirse ai_q_* gibi
  -- meşru SECURITY INVOKER fonksiyonlar "fazla fonksiyon" diye yanlış alarm
  -- üretir.
  select p.oid::regprocedure::text                        as imza,
         p.prosecdef                                      as secdef,
         coalesce(array_to_string(p.proconfig, ', '), '(yok)') as ayarlar,
         md5(p.prosrc)                                    as govde_md5
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public' and p.prokind = 'f'
    and (p.prosecdef
         or p.proname like 'auth\_%'
         or p.proname in ('stok_ekle','stok_transfer'))
),
b as (select replace(replace(imza, 'public.', ''), ' ', '') as imza,
             secdef, ayarlar, govde_md5 from burada),
u as (select replace(imza, ' ', '') as imza,
             secdef, ayarlar, govde_md5 from uretim)
select * from (

  select 1 as sira, 'SAPMA: fonksiyon YOK' as kontrol, u.imza as ayrinti
  from u where not exists (select 1 from b where b.imza = u.imza)

  union all
  -- Govde farki en tehlikeli sapmadir: imza ayni, davranis farkli.
  select 2, 'SAPMA: govde FARKLI (md5(prosrc))',
         u.imza || '  beklenen=' || u.govde_md5 || '  bulunan=' || b.govde_md5
  from u join b on b.imza = u.imza
  where b.govde_md5 is distinct from u.govde_md5

  union all
  select 3, 'SAPMA: SECURITY DEFINER / search_path farkli',
         u.imza || '  beklenen=' || u.secdef::text || '/' || u.ayarlar
                || '  bulunan=' || b.secdef::text || '/' || b.ayarlar
  from u join b on b.imza = u.imza
  where b.secdef is distinct from u.secdef or b.ayarlar is distinct from u.ayarlar

  union all
  select 4, 'SAPMA: kapsamda FAZLA fonksiyon (gozden gecirilmemis giris noktasi)', b.imza
  from b where not exists (select 1 from u where u.imza = b.imza)

  union all
  select 5, 'SAPMA: anon/PUBLIC tablo veya kolon izni (beklenen 0)',
         grantee || ' ' || table_name || ' ' || privilege_type
  from information_schema.role_table_grants
  where table_schema = 'public' and grantee in ('anon','PUBLIC')

  union all
  select 6, 'SAPMA: RLS kapali tablo (beklenen 0)', string_agg(c.relname, ', ')
  from pg_class c join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'public' and c.relkind = 'r' and not c.relrowsecurity
  having count(*) > 0

  union all
  select 7, 'SAPMA: phase0_private semasi veya fonksiyonlari eksik',
         coalesce((select count(*)::text from pg_proc p
                   join pg_namespace n on n.oid = p.pronamespace
                   where n.nspname = 'phase0_private'), '(sema yok)')
  where to_regnamespace('phase0_private') is null
     or (select count(*) from pg_proc p
         join pg_namespace n on n.oid = p.pronamespace
         where n.nspname = 'phase0_private') <> 3

  union all
  -- POST-PMS: audit 14 -> 19 (5 PMS tablosu), otel_degismez 27 -> 34 (7 PMS).
  -- 9 DEGIL 7: pms_folio_hareketleri ve pms_folio_odemeler append-only
  -- oldugu icin UPDATE zaten imkansiz; before-update tetikleyicisi olu kod.
  select 8, 'SAPMA: Phase 0 tetikleyici sayisi farkli (beklenen 19 audit + 34 otel)',
         'audit=' || (select count(*)::text from pg_trigger
                      where not tgisinternal and tgname like 'phase0\_islem\_audit%')
         || ' otel_degismez=' || (select count(*)::text from pg_trigger
                                  where not tgisinternal and tgname = 'phase0_otel_degismez')
  where (select count(*) from pg_trigger
         where not tgisinternal and tgname like 'phase0\_islem\_audit%') <> 19
     or (select count(*) from pg_trigger
         where not tgisinternal and tgname = 'phase0_otel_degismez') <> 34

  union all
  select 9, 'SAPMA: phase0_otel_kisit politika sayisi farkli (beklenen 36)', count(*)::text
  from pg_policy p join pg_class c on c.oid = p.polrelid
  join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'public' and p.polname = 'phase0_otel_kisit'
  having count(*) <> 36

  union all
  select 10, 'SAPMA: korumali yazma yolu acilmis', 'satin_alma_talepleri UPDATE'
  where has_table_privilege('authenticated','public.satin_alma_talepleri','UPDATE')
     or has_any_column_privilege('authenticated','public.satin_alma_talepleri','UPDATE')

  union all
  select 11, 'SAPMA: korumali yazma yolu acilmis', 'talep_onay_gecmisi yazma'
  where has_table_privilege('authenticated','public.talep_onay_gecmisi','INSERT,UPDATE,DELETE')
     or has_any_column_privilege('authenticated','public.talep_onay_gecmisi','INSERT,UPDATE')

  union all
  select 12, 'SAPMA: denetim izine istemci yazabiliyor', 'erp_islem_audit'
  where to_regclass('public.erp_islem_audit') is null
     or has_table_privilege('authenticated','public.erp_islem_audit','INSERT,UPDATE,DELETE')
     or has_any_column_privilege('authenticated','public.erp_islem_audit','INSERT,UPDATE')

  union all
  select 13, 'SAPMA: yeni fonksiyonlar anon a acik doguyor (varsayilan ACL)',
         array_to_string(d.defaclacl::text[], ', ')
  from pg_default_acl d join pg_namespace n on n.oid = d.defaclnamespace
  where n.nspname = 'public' and d.defaclrole = 'postgres'::regrole
    and d.defaclobjtype = 'f'
    and array_to_string(d.defaclacl::text[], ',') like '%anon=%'

  -- ==========================================================================
  -- PMS FAZ 1'E OZEL YAPISAL DEGISMEZLER (17-22)
  -- Sayilar degismeden de bozulabilecek seyler; ayrica sinaniyor.
  -- ==========================================================================
  union all
  select 17, 'SAPMA: PMS tablosu eksik veya fazla (beklenen 9)', count(*)::text
  from pg_class c join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'public' and c.relkind = 'r' and c.relname like 'pms\_%'
  having count(*) <> 9

  union all
  -- Finansal append-only: hareket/odeme tablolarinda authenticated icin
  -- update/delete AYRICALIGI da POLITIKASI da olmamali.
  select 18, 'SAPMA: finansal append-only bozulmus',
         'ayricalik=' || (has_table_privilege('authenticated','public.pms_folio_hareketleri','UPDATE')::int
                        + has_table_privilege('authenticated','public.pms_folio_hareketleri','DELETE')::int
                        + has_table_privilege('authenticated','public.pms_folio_odemeler','UPDATE')::int
                        + has_table_privilege('authenticated','public.pms_folio_odemeler','DELETE')::int)::text
         || ' politika=' || (select count(*)::text from pg_policy p
                             join pg_class c on c.oid = p.polrelid
                             where c.relname in ('pms_folio_hareketleri','pms_folio_odemeler')
                               and p.polcmd in ('w','d'))
  where has_table_privilege('authenticated','public.pms_folio_hareketleri','UPDATE')
     or has_table_privilege('authenticated','public.pms_folio_hareketleri','DELETE')
     or has_table_privilege('authenticated','public.pms_folio_odemeler','UPDATE')
     or has_table_privilege('authenticated','public.pms_folio_odemeler','DELETE')
     or (select count(*) from pg_policy p join pg_class c on c.oid = p.polrelid
         where c.relname in ('pms_folio_hareketleri','pms_folio_odemeler')
           and p.polcmd in ('w','d')) > 0

  union all
  -- Idempotency: index'in VARLIGI yetmez, BENZERSIZ olmali.
  select 19, 'SAPMA: idempotency index i yok veya benzersiz degil (beklenen 3)',
         coalesce(string_agg(c.relname || '=' || i.indisunique::text, ', '), '(hicbiri yok)')
  from pg_class c join pg_index i on i.indexrelid = c.oid
  where c.relname in ('pms_folio_gece_uniq','pms_folio_kaynak_uniq','pms_folio_odeme_anahtar_uniq')
  having count(*) filter (where i.indisunique) <> 3

  union all
  -- Asiri satis korumasi: atama tablosunda EXCLUDE kisiti.
  select 20, 'SAPMA: pms_oda_atamalari EXCLUDE kisiti yok', count(*)::text
  from pg_constraint
  where conrelid = 'public.pms_oda_atamalari'::regclass and contype = 'x'
  having count(*) <> 1

  union all
  -- Folyo tablolarinda DELETE de denetlenmeli (tgtype & 8 = DELETE).
  select 21, 'SAPMA: folyo denetim izi DELETE i kapsamiyor (beklenen 3)', count(*)::text
  from pg_trigger t join pg_class c on c.oid = t.tgrelid
  where c.relname in ('pms_folyolar','pms_folio_hareketleri','pms_folio_odemeler')
    and t.tgname = 'phase0_islem_audit' and not t.tgisinternal and (t.tgtype & 8) = 8
  having count(*) <> 3

  union all
  -- Bar durum makinesi ve kopru tetikleyicileri.
  select 22, 'SAPMA: PMS koruma tetikleyicisi eksik',
         'append_only=' || (select count(*)::text from pg_trigger
                            where tgname='pms_folio_degismez' and not tgisinternal)
         || ' bar_kilit=' || (select count(*)::text from pg_trigger
                              where tgname='pms_bar_durum_kilit' and not tgisinternal)
         || ' bar_kopru=' || (select count(*)::text from pg_trigger
                              where tgname='pms_bar_folio_koprusu' and not tgisinternal)
         || ' tutarlilik=' || (select count(*)::text from pg_trigger
                               where tgname in ('pms_tutarlilik_oda','pms_tutarlilik_rezervasyon',
                                                'pms_tutarlilik_atama') and not tgisinternal)
  where (select count(*) from pg_trigger where tgname='pms_folio_degismez' and not tgisinternal) <> 2
     or (select count(*) from pg_trigger where tgname='pms_bar_durum_kilit' and not tgisinternal) <> 1
     or (select count(*) from pg_trigger where tgname='pms_bar_folio_koprusu' and not tgisinternal) <> 1
     or (select count(*) from pg_trigger where tgname in ('pms_tutarlilik_oda',
         'pms_tutarlilik_rezervasyon','pms_tutarlilik_atama') and not tgisinternal) <> 3

  union all
  select 14, 'BILGI: eslesen fonksiyon (28 olmali)', count(*)::text
  from u join b on b.imza = u.imza where b.govde_md5 = u.govde_md5

  union all
  select 15, 'BILGI: politika / tablo (uretim: 234 / 75)',
         (select count(*)::text from pg_policy p
          join pg_class c on c.oid = p.polrelid
          join pg_namespace n on n.oid = c.relnamespace where n.nspname='public')
         || ' / ' ||
         (select count(*)::text from pg_class c
          join pg_namespace n on n.oid = c.relnamespace
          where n.nspname='public' and c.relkind in ('r','p'))

  union all
  select 16, 'BILGI: kisitlayici politika (uretim: 40)', count(*)::text
  from pg_policy p join pg_class c on c.oid = p.polrelid
  join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'public' and not p.polpermissive

) x
order by sira, kontrol, ayrinti;
