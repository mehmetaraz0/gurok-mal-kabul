-- ============================================================================
-- PMS FAZ 1 — YAYIN ÖNCESİ ÜRETİM PREFLIGHT'I (SALT OKUMA)
-- ============================================================================
-- Nerede çalışır : Supabase SQL Editor, ÜRETİM.
-- Ne yapar       : HİÇBİR ŞEY YAZMAZ. Yalnız SELECT.
--                  DDL yok, DML yok, GRANT yok, fonksiyon çağrısı ile yazma yok.
-- Ne zaman       : Adım 1 migration'ı uygulanmadan HEMEN ÖNCE.
-- Beklenen       : TÜM satırlarda durum = 'GECTI'. Tek bir 'SAPMA' bile
--                  yayını DURDURUR (runbook 2.3 / STOP kriteri).
--
-- Bu dosya yayın kararının kanıtıdır: çıktısını runbook'taki yayın kaydına
-- OLDUĞU GİBİ yapıştırın. "Ekran açıldı" kanıt değildir (runbook 2.7).
-- ============================================================================

with

-- ---------------------------------------------------------------------------
-- 1) PMS NESNELERİ ÜRETİMDE HENÜZ OLMAMALI (isim/kolon çakışması)
-- ---------------------------------------------------------------------------
-- Aynı adlı bir nesne varsa migration ya çakışır ya da BAŞKASININ nesnesini
-- sessizce sahiplenir. Her iki hâl de yayını durdurur.
pms_tablo as (
  select count(*) as adet from pg_class c
   join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'public' and c.relkind in ('r','v','m')
    and c.relname like 'pms\_%'
),
pms_tip as (
  select count(*) as adet from pg_type t
   join pg_namespace n on n.oid = t.typnamespace
  where n.nspname = 'public' and t.typname like 'pms\_%'
),
pms_fonksiyon as (
  select count(*) as adet from pg_proc p
   join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public' and p.proname like 'pms\_%'
),
pms_sekans as (
  select count(*) as adet from pg_class c
   join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'public' and c.relkind = 'S' and c.relname like 'pms\_%'
),
pms_modul as (
  select count(*) as adet from public.moduller where kod like 'pms\_%'
),
-- Adım 4 bar_siparisleri üzerine iki tetikleyici kurar; aynı adlılar olmamalı.
bar_tetik as (
  select count(*) as adet from pg_trigger t
  where t.tgrelid = 'public.bar_siparisleri'::regclass
    and not t.tgisinternal
    and t.tgname in ('pms_bar_folio_koprusu','pms_bar_durum_kilit')
),
-- Adım 4 pms_rezervasyonlar'a gecelik_fiyat ekler; tablo yoksa kolon da yok.
gecelik_fiyat as (
  select count(*) as adet from information_schema.columns
  where table_schema = 'public' and column_name = 'gecelik_fiyat'
),

-- ---------------------------------------------------------------------------
-- 2) ADIM 1 ÖNKOŞULLARI SAĞLANIYOR MU
-- ---------------------------------------------------------------------------
-- Migration bunları kendi içinde de kontrol eder; burada ÖNCEDEN görülür ki
-- yayın penceresinde sürprizle karşılaşılmasın.
yetki_motoru as (
  select count(*) as adet from pg_class c
   join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'public' and c.relkind = 'r'
    and c.relname in ('kullanicilar','roller','moduller','yetki_matrisi')
),
phase0_yardimci as (
  select count(*) as adet from pg_proc p
   join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and p.proname in ('auth_yetki_var','auth_otel_erisim','auth_tum_oteller',
                      'auth_erp_kullanicisi')
),
phase0_sema as (
  select count(*) as adet from pg_namespace where nspname = 'phase0_private'
),
phase0_audit as (
  select count(*) as adet from pg_proc p
   join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'phase0_private' and p.proname = 'islem_audit'
),
otel_enum as (
  select count(*) as adet from pg_enum e
   join pg_type t on t.oid = e.enumtypid
   join pg_namespace n on n.oid = t.typnamespace
  where n.nspname = 'public' and t.typname = 'otel_id'
),
bar_modul as (
  select count(*) as adet from pg_class c
   join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'public' and c.relkind = 'r'
    and c.relname in ('bar_siparisleri','bar_siparis_kalemleri','menu_urunler')
),

-- ---------------------------------------------------------------------------
-- 3) PHASE 0 TABANI SAPMAMIŞ OLMALI
-- ---------------------------------------------------------------------------
-- Taban: 2026-09-06 doğrulanmış şema dökümü (66 tablo / 193 politika /
-- 31 kısıtlayıcı / 26 fonksiyon). Sayı değiştiyse üretim artık test edilen
-- şema DEĞİLDİR; fonksiyon gövdesi karşılaştırması için
-- docs/kurulum/2026-09-06-staging-esitlik-dogrulama.sql çalıştırılır.
tablo_sayisi as (
  select count(*) as adet from pg_class c
   join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'public' and c.relkind = 'r'
),
politika_sayisi as (
  select count(*) as adet from pg_policy p
   join pg_class c on c.oid = p.polrelid
   join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'public'
),
kisitlayici_sayisi as (
  select count(*) as adet from pg_policy p
   join pg_class c on c.oid = p.polrelid
   join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'public' and not p.polpermissive
),
-- RLS kapalı kalmış iş tablosu OLMAMALI.
rls_kapali as (
  select count(*) as adet from pg_class c
   join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'public' and c.relkind = 'r' and not c.relrowsecurity
),
-- SECURITY DEFINER fonksiyonların search_path'i PİNLENMİŞ olmalı.
sd_pinsiz as (
  select count(*) as adet from pg_proc p
   join pg_namespace n on n.oid = p.pronamespace
  where n.nspname in ('public','phase0_private') and p.prosecdef
    and (p.proconfig is null
         or not exists (select 1 from unnest(p.proconfig) k where k like 'search\_path=%'))
),
-- anon'un iş tablolarında hiçbir hakkı KALMAMALI.
anon_hak as (
  select count(*) as adet from information_schema.role_table_grants
  where table_schema = 'public' and grantee = 'anon'
),

-- ---------------------------------------------------------------------------
-- 4) YAYIN PENCERESİ İÇİN BİLGİ (karar değil, kayıt)
-- ---------------------------------------------------------------------------
denetim_izi as (select count(*) as adet from public.erp_islem_audit),
surum as (select current_setting('server_version') as v)

-- ---------------------------------------------------------------------------
select * from (
  values
  ('1.1 pms_* tablo/görünüm yok',        (select adet from pms_tablo),        0,  'esit'),
  ('1.2 pms_* tip yok',                  (select adet from pms_tip),          0,  'esit'),
  ('1.3 pms_* fonksiyon yok',            (select adet from pms_fonksiyon),    0,  'esit'),
  ('1.4 pms_* sekans yok',               (select adet from pms_sekans),       0,  'esit'),
  ('1.5 pms_* modül kaydı yok',          (select adet from pms_modul),        0,  'esit'),
  ('1.6 bar_siparisleri PMS tetikleyicisi yok', (select adet from bar_tetik), 0,  'esit'),
  ('1.7 gecelik_fiyat kolonu yok',       (select adet from gecelik_fiyat),    0,  'esit'),
  ('2.1 yetki motoru 4 tablo',           (select adet from yetki_motoru),     4,  'esit'),
  ('2.2 Phase 0 yardimcilari 4 fonksiyon',(select adet from phase0_yardimci), 4,  'esit'),
  ('2.3 phase0_private semasi',          (select adet from phase0_sema),      1,  'esit'),
  ('2.4 phase0_private.islem_audit',     (select adet from phase0_audit),     1,  'esit'),
  ('2.5 otel_id enum degeri',            (select adet from otel_enum),        2,  'esit'),
  ('2.6 bar modulu 3 tablo',             (select adet from bar_modul),        3,  'esit'),
  ('3.1 tablo sayisi (taban 66)',        (select adet from tablo_sayisi),     66, 'esit'),
  ('3.2 politika sayisi (taban 193)',    (select adet from politika_sayisi),  193,'esit'),
  ('3.3 kisitlayici politika (taban 31)',(select adet from kisitlayici_sayisi),31,'esit'),
  ('3.4 RLS kapali tablo',               (select adet from rls_kapali),       0,  'esit'),
  ('3.5 search_path pinsiz SECURITY DEFINER', (select adet from sd_pinsiz),   0,  'esit'),
  ('3.6 anon tablo hakki',               (select adet from anon_hak),         0,  'esit'),
  ('4.1 erp_islem_audit satiri (BILGI)', (select adet from denetim_izi),      -1, 'bilgi')
) as t(kontrol, bulunan, beklenen, tur)
cross join (select v from surum) s
order by kontrol;

-- ============================================================================
-- YORUMLAMA
-- ============================================================================
-- tur = 'esit' olan HER satırda bulunan = beklenen olmalı. Değilse: SAPMA.
--
-- 3.1 / 3.2 / 3.3 sapıyorsa: üretim, test edilen şemadan farklı. Yayını
--   DURDUR; önce docs/kurulum/2026-09-06-staging-esitlik-dogrulama.sql
--   çalıştırılıp farkın ne olduğu belirlenir.
--
-- 1.x sapıyorsa: PMS nesneleri üretimde ZATEN VAR. Yayını DURDUR — bu,
--   bilinmeyen bir uygulayıcının migration'ı çalıştırdığı anlamına gelir
--   (6 Eylül Phase 0 olayının tekrarı). Kim/ne zaman sorusu cevaplanmadan
--   ilerlenmez.
--
-- 4.1 bir karar kriteri DEĞİL, kayıttır. Yayın öncesi ve sonrası değeri
--   runbook 2.7'deki smoke test kanıtı için karşılaştırılır.
-- ============================================================================
