-- ============================================================================
-- POST-PMS-FAZ1 — ÜRETİM PARMAK İZİ (SALT OKUMA)
-- ============================================================================
-- Nerede çalışır : Supabase SQL Editor, ÜRETİM.
-- Ne yapar       : HİÇBİR ŞEY YAZMAZ. Yalnız SELECT.
--                  DDL yok, DML yok, GRANT yok, yazan fonksiyon çağrısı yok.
-- Ne zaman       : PMS Faz 1 sonrası yeni tabanı sabitlemek için (2026-09-07)
--                  ve sonraki her yayından önce.
--
-- NEDEN YENİ DOSYA: `2026-09-07-pms-yayin-oncesi-preflight.sql` PMS ÖNCESİ
-- tabanı (66/193/31) sabitliyordu. PMS Faz 1 uygulandıktan sonra o dosya
-- tasarımı gereği SAPMA raporlar. Eski dosya tarihsel kanıt olarak DURUYOR;
-- bu dosya yeni tabanı temsil eder.
--
-- BEKLENEN TABAN (2026-09-07, PMS Faz 1 sonrası):
--   75 tablo · 234 politika · 40 kısıtlayıcı politika
--   ve üç kritik güvenlik sıfırı:
--     RLS kapalı tablo = 0
--     search_path pinsiz SECURITY DEFINER = 0
--     anon tablo hakkı = 0
--
-- YORUMLAMA: tur = 'esit' olan HER satırda bulunan = beklenen olmalı.
-- Tek bir sapma bile yayını DURDURUR. tur = 'bilgi' satırları karar
-- kriteri değildir; kayda geçer.
-- ============================================================================

with

-- ---------------------------------------------------------------------------
-- A) ÇEKİRDEK SAYILAR
-- ---------------------------------------------------------------------------
t_tablo as (
  select count(*) n from pg_class c join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public' and c.relkind = 'r'),
t_gorunum as (
  select count(*) n from pg_class c join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public' and c.relkind = 'v'),
t_politika as (
  select count(*) n from pg_policy p join pg_class c on c.oid = p.polrelid
   join pg_namespace n on n.oid = c.relnamespace where n.nspname = 'public'),
t_kisitlayici as (
  select count(*) n from pg_policy p join pg_class c on c.oid = p.polrelid
   join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public' and not p.polpermissive),
t_rls_kapali as (
  select count(*) n from pg_class c join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public' and c.relkind = 'r' and not c.relrowsecurity),
t_rls_forced as (
  select count(*) n from pg_class c join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public' and c.relkind = 'r' and c.relforcerowsecurity),

-- ---------------------------------------------------------------------------
-- B) GÜVENLİK DURUŞU
-- ---------------------------------------------------------------------------
t_sd as (
  select count(*) n from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public','phase0_private') and p.prosecdef),
t_sd_pinsiz as (
  select count(*) n from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public','phase0_private') and p.prosecdef
     and (p.proconfig is null
          or not exists (select 1 from unnest(p.proconfig) k where k like 'search\_path=%'))),
t_anon_tablo as (
  select count(*) n from information_schema.role_table_grants
   where table_schema = 'public' and grantee = 'anon'),
t_anon_sekans as (
  select count(*) n from information_schema.usage_privileges
   where object_schema = 'public' and grantee = 'anon' and object_type = 'SEQUENCE'),
-- PUBLIC ya da anon'a EXECUTE açık kalan fonksiyon (PostgreSQL varsayılanı
-- PUBLIC'e EXECUTE verir; Phase 0 bunu kapatmıştı).
t_public_execute as (
  select count(*) n from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
   where ns.nspname = 'public'
     and (has_function_privilege('public', p.oid, 'EXECUTE')
          or has_function_privilege('anon',   p.oid, 'EXECUTE'))),
-- Yetki motoru yardımcıları authenticated tarafından çağrılabilmeli.
t_auth_helper as (
  select count(*) n from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
   where ns.nspname = 'public'
     and p.proname in ('auth_yetki_var','auth_otel_erisim','auth_tum_oteller','auth_erp_kullanicisi')
     and has_function_privilege('authenticated', p.oid, 'EXECUTE')),

-- ---------------------------------------------------------------------------
-- C) PMS NESNELERİ
-- ---------------------------------------------------------------------------
t_pms_tablo as (
  select count(*) n from pg_class c join pg_namespace ns on ns.oid = c.relnamespace
   where ns.nspname = 'public' and c.relkind = 'r' and c.relname like 'pms\_%'),
t_pms_gorunum as (
  select count(*) n from pg_class c join pg_namespace ns on ns.oid = c.relnamespace
   where ns.nspname = 'public' and c.relkind = 'v' and c.relname like 'pms\_%'),
t_pms_politika as (
  select count(*) n from pg_policy p join pg_class c on c.oid = p.polrelid
   where c.relname like 'pms\_%'),
t_pms_kisitlayici as (
  select count(*) n from pg_policy p join pg_class c on c.oid = p.polrelid
   where c.relname like 'pms\_%' and not p.polpermissive),
t_pms_fonksiyon as (
  select count(*) n from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
   where ns.nspname = 'public' and p.proname like 'pms\_%'),
t_pms_modul as (
  select count(*) n from public.moduller where kod like 'pms\_%'),
-- PMS tablolarında RLS açık olmayan varsa kritik.
t_pms_rls_kapali as (
  select count(*) n from pg_class c join pg_namespace ns on ns.oid = c.relnamespace
   where ns.nspname = 'public' and c.relkind = 'r' and c.relname like 'pms\_%'
     and not c.relrowsecurity),
-- Her PMS tablosunda phase0_otel_kisit kısıtlayıcı tabanı olmalı.
t_pms_otel_kisit as (
  select count(*) n from pg_policy p join pg_class c on c.oid = p.polrelid
   where c.relname like 'pms\_%' and p.polname = 'phase0_otel_kisit'),

-- ---------------------------------------------------------------------------
-- D) PMS TETİKLEYİCİLERİ
-- ---------------------------------------------------------------------------
-- Denetim izi: rezervasyon, atama + üç folyo tablosu = 5
t_pms_audit as (
  select count(*) n from pg_trigger t join pg_class c on c.oid = t.tgrelid
   where c.relname like 'pms\_%' and t.tgname = 'phase0_islem_audit' and not t.tgisinternal),
-- Folyo tablolarında DELETE de denetlenmeli (tgtype & 8).
t_folio_audit_delete as (
  select count(*) n from pg_trigger t join pg_class c on c.oid = t.tgrelid
   where c.relname in ('pms_folyolar','pms_folio_hareketleri','pms_folio_odemeler')
     and t.tgname = 'phase0_islem_audit' and not t.tgisinternal and (t.tgtype & 8) = 8),
t_tutarlilik as (
  select count(*) n from pg_trigger
   where tgname in ('pms_tutarlilik_oda','pms_tutarlilik_rezervasyon','pms_tutarlilik_atama')
     and not tgisinternal),
t_append_only as (
  select count(*) n from pg_trigger where tgname = 'pms_folio_degismez' and not tgisinternal),
t_bar_kilit as (
  select count(*) n from pg_trigger where tgname = 'pms_bar_durum_kilit' and not tgisinternal),
t_bar_kopru as (
  select count(*) n from pg_trigger where tgname = 'pms_bar_folio_koprusu' and not tgisinternal),
t_otel_degismez as (
  select count(*) n from pg_trigger where tgname = 'phase0_otel_degismez' and not tgisinternal),

-- ---------------------------------------------------------------------------
-- E) PMS FİNANSAL BÜTÜNLÜK
-- ---------------------------------------------------------------------------
-- Append-only: hareket/ödeme tablolarında authenticated için update/delete
-- ayrıcalığı OLMAMALI (toplam 0).
t_finansal_yazma as (
  select (has_table_privilege('authenticated','public.pms_folio_hareketleri','UPDATE')::int
        + has_table_privilege('authenticated','public.pms_folio_hareketleri','DELETE')::int
        + has_table_privilege('authenticated','public.pms_folio_odemeler','UPDATE')::int
        + has_table_privilege('authenticated','public.pms_folio_odemeler','DELETE')::int) n),
-- Aynı tablolarda update/delete POLİTİKASI da olmamalı.
t_finansal_politika as (
  select count(*) n from pg_policy p join pg_class c on c.oid = p.polrelid
   where c.relname in ('pms_folio_hareketleri','pms_folio_odemeler') and p.polcmd in ('w','d')),
-- Üç idempotency index'i ve hepsi BENZERSİZ olmalı.
t_idempotency as (
  select count(*) n from pg_index i join pg_class c on c.oid = i.indexrelid
   where c.relname in ('pms_folio_gece_uniq','pms_folio_kaynak_uniq','pms_folio_odeme_anahtar_uniq')
     and i.indisunique),
-- Aşırı satış koruması: atama tablosunda EXCLUDE kısıtı.
t_exclude as (
  select count(*) n from pg_constraint
   where conrelid = 'public.pms_oda_atamalari'::regclass and contype = 'x'),
-- Sekans ACL: authenticated yalnız USAGE almalı, UPDATE almamalı.
t_sekans_update as (
  select (has_sequence_privilege('authenticated','public.pms_rezervasyon_no_seq','UPDATE')::int
        + has_sequence_privilege('authenticated','public.pms_folio_no_seq','UPDATE')::int) n),
t_sekans_usage as (
  select (has_sequence_privilege('authenticated','public.pms_rezervasyon_no_seq','USAGE')::int
        + has_sequence_privilege('authenticated','public.pms_folio_no_seq','USAGE')::int) n),

-- ---------------------------------------------------------------------------
-- F) VARSAYILAN ACL (P3 — yalnız ÖLÇÜM, değiştirme yok)
-- ---------------------------------------------------------------------------
-- anon'a hak üreten varsayılan ayrıcalık tanımı var mı?
t_default_acl_anon as (
  select count(*) n from pg_default_acl d
   where exists (select 1 from unnest(d.defaclacl) a where a::text like 'anon=%')),
t_default_acl_toplam as (select count(*) n from pg_default_acl),

-- ---------------------------------------------------------------------------
-- G) BİLGİ
-- ---------------------------------------------------------------------------
t_audit_satir as (select count(*) n from public.erp_islem_audit),
t_surum as (select current_setting('server_version') v)

select * from (values
  -- A) çekirdek
  ('A1 public tablo',                    (select n from t_tablo),            75,  'esit'),
  ('A2 public görünüm',                  (select n from t_gorunum),          -1,  'bilgi'),
  ('A3 politika',                        (select n from t_politika),         234, 'esit'),
  ('A4 kısıtlayıcı politika',            (select n from t_kisitlayici),      40,  'esit'),
  ('A5 RLS kapalı tablo',                (select n from t_rls_kapali),       0,   'esit'),
  ('A6 RLS forced tablo',                (select n from t_rls_forced),       -1,  'bilgi'),
  -- B) güvenlik
  ('B1 SECURITY DEFINER fonksiyon',      (select n from t_sd),               -1,  'bilgi'),
  ('B2 search_path pinsiz SECURITY DEFINER', (select n from t_sd_pinsiz),    0,   'esit'),
  ('B3 anon tablo hakkı',                (select n from t_anon_tablo),       0,   'esit'),
  ('B4 anon sekans USAGE',               (select n from t_anon_sekans),      0,   'esit'),
  ('B5 PUBLIC/anon EXECUTE acik fonksiyon', (select n from t_public_execute), -1, 'bilgi'),
  ('B6 auth_* yardimci (authenticated EXECUTE)', (select n from t_auth_helper), 4, 'esit'),
  -- C) PMS nesneleri
  ('C1 pms_* tablo',                     (select n from t_pms_tablo),        9,   'esit'),
  ('C2 pms_* görünüm',                   (select n from t_pms_gorunum),      1,   'esit'),
  ('C3 pms_* politika',                  (select n from t_pms_politika),     41,  'esit'),
  ('C4 pms_* kısıtlayıcı politika',      (select n from t_pms_kisitlayici),  9,   'esit'),
  ('C5 pms_* fonksiyon',                 (select n from t_pms_fonksiyon),    -1,  'bilgi'),
  ('C6 pms_* modül kaydı',               (select n from t_pms_modul),        6,   'esit'),
  ('C7 pms_* RLS kapalı tablo',          (select n from t_pms_rls_kapali),   0,   'esit'),
  ('C8 pms_* phase0_otel_kisit',         (select n from t_pms_otel_kisit),   9,   'esit'),
  -- D) tetikleyiciler
  ('D1 pms_* denetim izi tetikleyicisi', (select n from t_pms_audit),        5,   'esit'),
  ('D2 folyo audit DELETE kapsami',      (select n from t_folio_audit_delete), 3, 'esit'),
  ('D3 tutarlilik tetikleyicisi',        (select n from t_tutarlilik),       3,   'esit'),
  ('D4 append-only tetikleyicisi',       (select n from t_append_only),      2,   'esit'),
  ('D5 bar durum kilidi',                (select n from t_bar_kilit),        1,   'esit'),
  ('D6 bar folyo koprusu',               (select n from t_bar_kopru),        1,   'esit'),
  ('D7 phase0_otel_degismez tetikleyici',(select n from t_otel_degismez),    34,  'esit'),
  -- E) finansal bütünlük
  ('E1 finansal update/delete ayricaligi',(select n from t_finansal_yazma),  0,   'esit'),
  ('E2 finansal update/delete politikasi',(select n from t_finansal_politika),0,  'esit'),
  ('E3 idempotency index (BENZERSIZ)',   (select n from t_idempotency),      3,   'esit'),
  ('E4 atama EXCLUDE kisiti',            (select n from t_exclude),          1,   'esit'),
  ('E5 sekans authenticated UPDATE',     (select n from t_sekans_update),    0,   'esit'),
  ('E6 sekans authenticated USAGE',      (select n from t_sekans_usage),     2,   'esit'),
  -- F) varsayılan ACL (P3)
  ('F1 anon ureten varsayilan ACL',      (select n from t_default_acl_anon), -1,  'bilgi'),
  ('F2 varsayilan ACL kaydi (toplam)',   (select n from t_default_acl_toplam), -1,'bilgi'),
  -- G) bilgi
  ('G1 erp_islem_audit satiri',          (select n from t_audit_satir),      -1,  'bilgi')
) as t(kontrol, bulunan, beklenen, tur)
cross join (select v from t_surum) s
order by kontrol;

-- ============================================================================
-- D7 NOTU: phase0_otel_degismez beklentisi 34 = 27 (Phase 0) + 7 (PMS).
--          9 DEGIL 7: pms_folio_hareketleri ve pms_folio_odemeler bu
--          tetikleyiciyi ALMAZ. Append-only olduklari icin UPDATE zaten
--          imkansizdir; before-update tetikleyicisi olu kod olurdu.
--          (Adim 1: 2 tablo, Adim 2: 4 tablo, Adim 4: yalniz pms_folyolar.)
-- C3 NOTU: 41 = Adım 1 (2 tablo x 5) + Adım 2 (4 x 5) + Adım 4 (folyolar 5,
--          hareketler 3, ödemeler 3). Hareket/ödeme append-only olduğu için
--          4 değil 2 kalıcı politika alır — 45 DEĞİL 41 beklenmesinin sebebi.
-- B5/F1  : bilgi satırı; PostgreSQL varsayılanı ve Supabase varsayılan ACL'i
--          hakkında kayıt tutar. Sapma kriteri DEĞİLDİR, ayrı P3 maddesidir.
-- ============================================================================
