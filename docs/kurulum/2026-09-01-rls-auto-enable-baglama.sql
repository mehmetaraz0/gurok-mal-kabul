-- ============================================================
-- 2026-09-01 — N-1: rls_auto_enable() EVENT TRIGGER'A BAĞLANMASI
-- ============================================================
-- SORUN: public.rls_auto_enable() yazılmış ve canlıda MEVCUT, ama onu bir DDL
-- olayına bağlayan CREATE EVENT TRIGGER hiç çalıştırılmamış. Yani "yeni tabloda
-- RLS'i otomatik aç" güvenlik ağı kurulmuş ama fişe takılmamış.
--
-- Bu, 2026-07-22 RLS denetiminde de kök neden olarak işaretlenmişti; aradan
-- 6 hafta geçti ve hâlâ bağlı değil. Bu süre içinde eklenen tablolarda aynı
-- sınıf hata tekrar üretildi (bkz. 2026-08-10 politika denetimi sorgu 2).
--
-- FONKSİYON İNCELENDİ, GÜVENLİ: yalnız 'public' şemasındaki CREATE TABLE
-- olaylarında `alter table ... enable row level security` çalıştırıyor, tamamı
-- EXCEPTION WHEN OTHERS ile sarılı → başarısız olsa bile tablo oluşturmayı
-- ASLA engellemez, sadece log'a yazar.
--
-- ⚠️ ÖNEMLİ NÜANS — bu ağ neyi yakalar, neyi yakalamaz:
-- Trigger yalnızca RLS'i AÇAR, POLİTİKA EKLEMEZ. Yani yeni bir tablo
-- "RLS açık + 0 politika" = herkese kapalı durumda doğar. Bu GÜVENLİ olan
-- başarısızlık yönüdür (veri sızmaz), ama sessizdir: ekran hata vermez,
-- sadece BOŞ gelir. `urun_birim_donusum` ve `gelen_efaturalar` aylarca tam
-- bu şekilde ölü kaldı.
-- Yani bu trigger "açık unutma" hatasını kapatır, "politika yazmayı unutma"
-- hatasını KAPATMAZ. İkincisi için sistemik RLS denetim script'i (aşağıdaki
-- alternatif) gerekir.
--
-- ⚠️ PLATFORM KISITI: CREATE EVENT TRIGGER SUPERUSER gerektirir. Supabase'de
-- `postgres` rolü gerçek superuser DEĞİLDİR; aşağıdaki komut
-- "permission denied to create event trigger" ile REDDEDİLEBİLİR.
-- Reddedilirse bu bir hata değil, platform sınırıdır → en alttaki
-- ALTERNATİF bölümüne geç.
-- ============================================================

-- ------------------------------------------------------------
-- [1] MEVCUT DURUM — fonksiyon var mı, trigger bağlı mı?
-- ------------------------------------------------------------
select 'fonksiyon' as ne, p.proname as ad, p.prosecdef as security_definer
from pg_proc p join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public' and p.proname = 'rls_auto_enable'
union all
select 'event_trigger', evtname, evtenabled = 'O'
from pg_event_trigger
where evtfoid = 'public.rls_auto_enable'::regproc;
-- BEKLENEN (düzeltmeden önce): yalnız 'fonksiyon' satırı döner, event_trigger YOK.


-- ------------------------------------------------------------
-- [2] BAĞLAMA — reddedilirse ALTERNATİF bölümüne geç
-- ------------------------------------------------------------
create event trigger rls_auto_enable_trg
  on ddl_command_end
  when tag in ('CREATE TABLE', 'CREATE TABLE AS', 'SELECT INTO')
  execute function public.rls_auto_enable();


-- ------------------------------------------------------------
-- [3] DOĞRULAMA — iki satır dönmeli (fonksiyon + event_trigger, ikisi de true)
-- ------------------------------------------------------------
-- select 'fonksiyon' as ne, p.proname, p.prosecdef
-- from pg_proc p join pg_namespace n on n.oid = p.pronamespace
-- where n.nspname='public' and p.proname='rls_auto_enable'
-- union all
-- select 'event_trigger', evtname, evtenabled = 'O'
-- from pg_event_trigger where evtfoid = 'public.rls_auto_enable'::regproc;


-- ------------------------------------------------------------
-- [4] CANLI TEST — gerçekten çalışıyor mu? (tek seferlik, temizliğiyle)
-- ------------------------------------------------------------
-- create table public.zzz_rls_trigger_testi (id int);
-- select relname, relrowsecurity as rls_acik
-- from pg_class where relname = 'zzz_rls_trigger_testi';
--   -> rls_acik TRUE dönmeli (trigger çalıştı demektir)
-- drop table public.zzz_rls_trigger_testi;


-- ============================================================
-- GERİ ALMA
-- ============================================================
-- drop event trigger if exists rls_auto_enable_trg;


-- ============================================================
-- ALTERNATİF — [2] "permission denied" ile reddedilirse
-- ============================================================
-- Event trigger kurulamıyorsa güvenlik ağı DETECT tarafına taşınır:
-- `docs/kurulum/2026-08-23-sistemik-rls-denetim.sql` (ve 2026-08-10-politika-
-- denetimi.sql) zaten "RLS kapalı tablolar" ve "politikasız tablolar"
-- sorgularını içeriyor. Bunları periyodik çalıştırmak, önlemenin yerine
-- geçmez ama aynı sınıfı ERKEN yakalar.
--
-- Not: bu sorgular veritabanına bağlanmayı gerektirdiği için mevcut
-- .github/workflows/statik-kontroller.yml içine doğrudan konamaz — DB
-- kimlik bilgisi bir GitHub Secret olarak eklenmeli. Bu ayrı bir karar
-- (public depoda DB erişimi olan bir CI adımı) ve sahibinin onayını ister.
--
-- Asgari çözüm (kimlik bilgisi gerektirmez): yeni tablo ekleyen HER migration
-- dosyasının sonuna politika kontrolü sorgusunu koymayı alışkanlık hâline
-- getirmek.
