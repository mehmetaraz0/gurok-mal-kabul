-- ============================================================================
-- ÜRETİM EŞİTLİK / SÜRÜKLENME DOĞRULAMASI — Phase 0 SONRASI taban
-- ============================================================================
-- SALT-OKUMA. Tek sonuç kümesi üretir. Hiçbir mutation içermez.
--
-- İKİ İŞİ VAR:
--   1) STAGING KABULÜ — bir branch/kopya üretimi temsil ediyor mu? Etmiyorsa
--      orada alınan hiçbir test sonucu geçerli değildir.
--   2) ÜRETİM SÜRÜKLENMESİ — canlıda Phase 0 korumaları hâlâ yerinde mi?
--
-- TEMEL: 6 Eylül 2026, Phase 0 sertleştirmesi üretime uygulandıktan SONRAKİ
-- durum. Bayt-birebir doğrulanmış şema dökümünden üretildi (26 fonksiyonun
-- 26'sı üretim gövde hash'leriyle eşleşti).
--
-- ÇIKTI: "SAPMA" ile başlayan satır varsa sorun var. Hiç yoksa yalnızca
-- "BILGI" satırları görünür.
--
-- ---------------------------------------------------------------------------
-- NEDEN md5(prosrc), md5(pg_get_functiondef) DEĞİL
-- ---------------------------------------------------------------------------
-- pg_get_functiondef gövdeyi SUNUCUNUN biçimlendiricisinden geçirir ve çıktısı
-- PostgreSQL minor sürümüne duyarlıdır. Üretim 17.6, doğrulama konteyneri
-- 17.11 olduğu icin ilk sürüm 26 fonksiyonun 25'ini, döküm kusursuz olsa bile
-- "farklı" raporluyordu. prosrc gövdenin HAM metnidir: sürüm duyarlılığı yok.
--
-- UYARI — DÖKÜM ALIRKEN İKİ TUZAK:
--   * Kabuk yönlendirmesi ( > ) kullanma. PowerShell dosyayı metin modunda
--     yazar, kodlamayı ve satır sonlarını değiştirir. Üretimdeki gövdelerin
--     satır sonları KARIŞIK (kimi LF, kimi CRLF) ve prosrc bunu aynen saklar;
--     tekdüzeleştiren her dönüşüm gövdeleri sessizce bozar. Daima pg_dump -f.
--   * İKİ ŞEMAYI DA AL: --schema=public --schema=phase0_private
--     Phase 0 tetikleyicileri phase0_private içindeki fonksiyonları çağırır.
--     Yalnız public alınırsa tetikleyicilerin hiçbiri yüklenmez ve eksiklik
--     sessiz kalır — aşağıdaki 7 ve 8 numaralı kontroller bunu yakalar.
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
  -- KAPSAM, preflight 01b ile AYNI olmalidir. Aksi halde ai_q_* gibi mesru
  -- SECURITY INVOKER fonksiyonlar "fazla fonksiyon" diye yanlis alarm uretir.
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
         count(*)::text || ' satir'
  from (select 1 from information_schema.table_privileges
        where table_schema = 'public' and grantee in ('PUBLIC','anon')
        union all
        select 1 from information_schema.column_privileges
        where table_schema = 'public' and grantee in ('PUBLIC','anon')) z
  having count(*) > 0

  union all
  select 6, 'SAPMA: RLS kapali tablo (beklenen 0)', string_agg(c.relname, ', ')
  from pg_class c join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'public' and c.relkind in ('r','p') and not c.relrowsecurity
  having count(*) > 0

  union all
  -- 7 ve 8: dokum --schema=public ile alinirsa phase0_private DISARIDA KALIR
  -- ve tetikleyicilerin hicbiri yuklenmez. Bu sessiz bosluk tam olarak
  -- 6 Eylul 2026'da yasandi; bu iki kontrol onun icin var.
  select 7, 'SAPMA: phase0_private semasi veya fonksiyonlari eksik',
         'beklenen 3 fonksiyon (audit_immutable, islem_audit, otel_degismez), bulunan '
         || (select count(*)::text from pg_proc p
             join pg_namespace n on n.oid = p.pronamespace
             where n.nspname = 'phase0_private')
  where to_regnamespace('phase0_private') is null
     or (select count(*) from pg_proc p
         join pg_namespace n on n.oid = p.pronamespace
         where n.nspname = 'phase0_private') <> 3

  union all
  select 8, 'SAPMA: Phase 0 tetikleyici sayisi farkli (beklenen 14 audit + 27 otel)',
         'audit=' || (select count(*)::text from pg_trigger
                      where not tgisinternal and tgname like 'phase0\_islem\_audit%')
         || ' otel_degismez=' || (select count(*)::text from pg_trigger
                                  where not tgisinternal and tgname = 'phase0_otel_degismez')
  where (select count(*) from pg_trigger
         where not tgisinternal and tgname like 'phase0\_islem\_audit%') <> 14
     or (select count(*) from pg_trigger
         where not tgisinternal and tgname = 'phase0_otel_degismez') <> 27

  union all
  select 9, 'SAPMA: phase0_otel_kisit politika sayisi farkli (beklenen 27)', count(*)::text
  from pg_policy p join pg_class c on c.oid = p.polrelid
  join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'public' and p.polname = 'phase0_otel_kisit'
  having count(*) <> 27

  union all
  -- Korumali yazma yollari: onay motoru yalnizca sunucuda calismali.
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

  union all
  select 14, 'BILGI: eslesen fonksiyon (26 olmali)', count(*)::text
  from u join b on b.imza = u.imza where b.govde_md5 = u.govde_md5

  union all
  select 15, 'BILGI: politika / tablo (uretim: 193 / 66)',
         (select count(*)::text from pg_policy p
          join pg_class c on c.oid = p.polrelid
          join pg_namespace n on n.oid = c.relnamespace where n.nspname='public')
         || ' / ' ||
         (select count(*)::text from pg_class c
          join pg_namespace n on n.oid = c.relnamespace
          where n.nspname='public' and c.relkind in ('r','p'))

  union all
  select 16, 'BILGI: kisitlayici politika (uretim: 31)', count(*)::text
  from pg_policy p join pg_class c on c.oid = p.polrelid
  join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'public' and not p.polpermissive

) x
order by sira, kontrol, ayrinti;
