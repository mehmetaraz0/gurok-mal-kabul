-- ============================================================================
-- STAGING <-> ÜRETİM EŞİTLİK DOĞRULAMASI
-- ============================================================================
-- SALT-OKUMA. Tek sonuç kümesi üretir. Hiçbir mutation içermez.
--
-- NE İÇİN: Phase 0 sertleştirmesini staging'de test edeceğiz. Ama staging
-- üretimi TEMSİL ETMİYORSA oradaki "geçti" sonucu hiçbir şey ifade etmez --
-- hatta yanlış güven verir. Supabase preview branch'leri şemayı migration
-- dosyalarından kurar; bu repoda supabase/migrations YOK. Yani branch'in
-- üretimle aynı çıkacağı VARSAYILAMAZ, KANITLANMALIDIR. Bu dosya o kanıttır.
--
-- NE ZAMAN: Phase 0 migration'INDAN ÖNCE, staging ortamında çalıştırılır.
-- Migration auth_* fonksiyonlarını yeniden yazar ve parmak izlerini
-- DEĞİŞTİRİR; sonrasında çalıştırılırsa doğal olarak sapma raporlar.
--
-- TEMEL: 2026-09-06 tarihli üretim preflight çıktısı (01/02/03/04/05).
-- Üretimde bir şey değişirse bu dosya BAYATLAR; yeniden preflight alınıp
-- güncellenmelidir.
--
-- ÇIKTI: her satır bir kontrol. "SAPMA" ile başlayan satır varsa staging
-- üretimi temsil etmiyor demektir ve Phase 0 orada test EDİLMEMELİDİR.
-- Hiç SAPMA satırı yoksa yalnızca "BİLGİ" satırları görünür.
-- ============================================================================

with uretim(imza, secdef, ayarlar, parmak_izi) as (values
  ('audit_log_damgala()',                            true,  'search_path=public',             'a7cda566ac6094d6ef984ad73e51b2e8'),
  ('auth_erp_kullanicisi()',                         true,  'search_path=public',             '6a5c9a57c06b98eace813294837a6c32'),
  ('auth_kullanici_id()',                            true,  'search_path=public',             '663036252774bb4faa13b29d5af3450b'),
  ('auth_kullanici_rol_id()',                        false, '(yok)',                          '6ccec830fbfea01e0648d1e8ad123240'),
  ('auth_otel_erisim(text)',                         true,  'search_path=public',             'bc5136fe005c08e08113aa42e5899e57'),
  ('auth_otel_id()',                                 true,  'search_path=public',             'c4dea5ba89c3043a455a80c5efe4188e'),
  ('auth_tum_oteller()',                             true,  'search_path=public',             '1e5f903bdedb8a2643ea70c5f34f28ab'),
  ('auth_yetki_var(text,text)',                      true,  'search_path=public',             'd71c9f9d46fd65721801218b27da4377'),
  ('bar_kullanilabilir_stok(text,text)',             true,  'search_path=public',             'c0741660dfb6048b038977be1a64a203'),
  ('bar_siparis_durum_guncelle(uuid,bar_durum)',     true,  'search_path=public',             '40e55ef2f861df447c412960f89e1d40'),
  ('bar_siparis_iptal(uuid)',                        true,  'search_path=public',             '9a70695fc8b230a5dcf571fd42b6d1d0'),
  ('bar_siparis_olustur(text,text,text,text,jsonb)', true,  'search_path=public',             '3c8aff3e15c27d49b512f49083c2db46'),
  ('bar_siparis_teslim_et(uuid)',                    true,  'search_path=public',             '4f707549a1622838bc23f0329c2c4119'),
  ('fatura_kaydet(uuid,jsonb,jsonb)',                true,  'search_path=public',             'aedd1d191d82142bb6b1109dbe62254f'),
  ('giris_kaydi_ekle(text)',                         true,  'search_path=public',             'a4894989147f1a428c045565ecfcc63a'),
  ('mal_kabul_kaydet(jsonb,jsonb)',                  true,  'search_path=public',             '8a4c02dbc8bb03ca0ef1436a71239330'),
  ('pin_ayarla(uuid,text)',                          true,  'search_path=public, extensions', 'ce6dc02f01c630823c9db4bf41dd2d58'),
  ('pin_dogrula(text,text)',                         true,  'search_path=public, extensions', 'd35fe0f4bb01fef5cf8569c7f1aa0a75'),
  ('rls_auto_enable()',                              true,  'search_path=pg_catalog',         '6998ea6b4c2480f5d2e34b5dcf3f8d36'),
  ('siparis_yeniden_yonlendir(text,text)',           true,  'search_path=public',             '3ba46cd52c147d1aad60d3374edfbc4d'),
  ('stok_ekle(text,text,text,numeric)',              false, '(yok)',                          '82816a126a011d179f68fef872c07325'),
  ('stok_transfer(text,text,text,text,numeric)',     false, '(yok)',                          '9e6a4a5b8d151811b62bf037f0458cb3'),
  ('talep_asama_yetkili_mi(text,text,uuid)',         true,  'search_path=public',             'f650ca165206fb4679dca0ed98a50438'),
  ('talep_karar_ver(uuid,text,text,numeric)',        true,  'search_path=public',             '1dc0466e0b4d5a9f9ca941aa03e59b8f'),
  ('talep_siparise_donustur(uuid)',                  true,  'search_path=public',             '2448fb8a299435fe56630566d4812fe1'),
  ('teklif_talebi_olustur(text,text,jsonb)',         true,  'search_path=public',             'ac285c8771b5126846eb7e4f2749d5c6')
),
burada as (
  select p.oid::regprocedure::text                        as imza,
         p.prosecdef                                      as secdef,
         coalesce(array_to_string(p.proconfig, ', '), '(yok)') as ayarlar,
         md5(pg_get_functiondef(p.oid))                   as parmak_izi
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public' and p.prokind = 'f'
),
-- İmza metni tip adlarında şema önekiyle farklılaşabilir; normalleştiriyoruz.
b as (select replace(replace(imza, 'public.', ''), ' ', '') as imza,
             secdef, ayarlar, parmak_izi from burada),
u as (select replace(imza, ' ', '') as imza,
             secdef, ayarlar, parmak_izi from uretim)
select * from (

  select 1 as sira,
         'SAPMA: fonksiyon staging de YOK' as kontrol,
         u.imza                            as ayrinti
  from u where not exists (select 1 from b where b.imza = u.imza)

  union all
  -- Gövde farkı en tehlikeli sapmadir: imza ayni, davranis farkli.
  select 2, 'SAPMA: fonksiyon govdesi FARKLI (md5)',
         u.imza || '  uretim=' || u.parmak_izi || '  staging=' || b.parmak_izi
  from u join b on b.imza = u.imza
  where b.parmak_izi is distinct from u.parmak_izi

  union all
  select 3, 'SAPMA: SECURITY DEFINER / search_path farkli',
         u.imza || '  uretim=' || u.secdef::text || '/' || u.ayarlar
                || '  staging=' || b.secdef::text || '/' || b.ayarlar
  from u join b on b.imza = u.imza
  where b.secdef is distinct from u.secdef or b.ayarlar is distinct from u.ayarlar

  union all
  -- Staging de fazladan bir fonksiyon, gozden gecirilmemis bir giris noktasidir.
  select 4, 'SAPMA: staging de FAZLA fonksiyon var (uretimde yok)', b.imza
  from b where not exists (select 1 from u where u.imza = b.imza)

  union all
  -- Yapisal degismezler. Hepsi 2026-09-06 uretim preflight inde dogrulandi.
  select 5, 'SAPMA: anon/PUBLIC tablo veya kolon izni var (uretimde 0)',
         count(*)::text || ' satir'
  from (select 1 from information_schema.table_privileges
        where table_schema = 'public' and grantee in ('PUBLIC','anon')
        union all
        select 1 from information_schema.column_privileges
        where table_schema = 'public' and grantee in ('PUBLIC','anon')) z
  having count(*) > 0

  union all
  select 6, 'SAPMA: RLS kapali tablo var (uretimde 0)', string_agg(c.relname, ', ')
  from pg_class c join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'public' and c.relkind in ('r','p') and not c.relrowsecurity
  having count(*) > 0

  union all
  select 7, 'SAPMA: kisitlayici politika var (Phase 0 ONCESI uretimde 0)',
         string_agg(p.polname, ', ')
  from pg_policy p
  join pg_class c on c.oid = p.polrelid
  join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'public' and not p.polpermissive
  having count(*) > 0

  union all
  select 8, 'BILGI: politika sayisi', count(*)::text
  from pg_policy p
  join pg_class c on c.oid = p.polrelid
  join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'public'

  union all
  select 9, 'BILGI: public sema tablo sayisi', count(*)::text
  from pg_class c join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'public' and c.relkind in ('r','p')

  union all
  select 10, 'BILGI: birebir eslesen fonksiyon sayisi (26 olmali)', count(*)::text
  from u join b on b.imza = u.imza where b.parmak_izi = u.parmak_izi

) x
order by sira, kontrol, ayrinti;
