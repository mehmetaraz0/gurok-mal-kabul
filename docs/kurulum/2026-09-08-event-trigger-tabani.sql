-- ============================================================================
-- EVENT TRIGGER TABANI — SALT OKUMA
-- Tarih: 2026-09-08 · Yeniden çalıştırılabilir · Her yayından ÖNCE
--
-- BU DOSYA HİÇBİR ŞEY DEĞİŞTİRMEZ. Tek bir `select` içerir.
-- Supabase SQL Editor'e yapıştırılır.
--
-- ---------------------------------------------------------------------------
-- NEDEN VAR — ölçülmeyen bir nesne sınıfı
-- ---------------------------------------------------------------------------
-- Taban şema dökümümüz event trigger'ları İÇERMİYOR:
--
--   pg_dump --schema=public --schema=phase0_private ...
--
-- `--schema` filtresi verildiğinde pg_dump veritabanı düzeyindeki nesneleri
-- dökmez. `2026-09-07-post-pms-faz1-sema-dokumu.sql` içinde "event trigger"
-- ifadesi SIFIR kez geçer. Eşitlik doğrulayıcısı ve üretim parmak izi de
-- ölçmüyordu.
--
-- Sonucu: `ensure_rls` üretimde altı hafta boyunca çalıştı ve biz onu "hiç
-- bağlanmamış" sandık (2026-07-22 → 2026-09-08). Ölçüm aracının kapsamı
-- dışında kalan şey, yok sanılır.
--
-- ---------------------------------------------------------------------------
-- NEDEN ÖNEMLİ — event trigger bir güvenlik yüzeyidir
-- ---------------------------------------------------------------------------
-- Bir event trigger, veritabanındaki HER DDL olayında, SAHİBİNİN yetkisiyle
-- kod çalıştırır. Eklenmesi, silinmesi ya da devre dışı bırakılması
-- fark edilmeden geçerse:
--
--   * güvenlik ağı sessizce sökülebilir (`ensure_rls` düşerse yeni tablolar
--     RLS'siz doğmaya başlar ve hiçbir kontrol bunu söylemez),
--   * ya da bir DDL kancası eklenip her migration'da kod çalıştırabilir.
--
-- Bu dosya o boşluğu kapatır.
--
-- ---------------------------------------------------------------------------
-- ÜRETİM DOĞRULAMASI — 2026-09-08
-- ---------------------------------------------------------------------------
-- Üretimde çalıştırıldı: **8/8 ESIT**, özet `7 / 7 beklenen`, `0 devre disi`.
--
--   ensure_rls                | BIZIM    | ESIT | postgres       | ddl_command_end -> rls_auto_enable()
--   issue_graphql_placeholder | platform | ESIT | supabase_admin | sql_drop        -> set_graphql_placeholder()
--   issue_pg_cron_access      | platform | ESIT | supabase_admin | ddl_command_end -> grant_pg_cron_access()
--   issue_pg_graphql_access   | platform | ESIT | supabase_admin | ddl_command_end -> grant_pg_graphql_access()
--   issue_pg_net_access       | platform | ESIT | supabase_admin | ddl_command_end -> grant_pg_net_access()
--   pgrst_ddl_watch           | platform | ESIT | supabase_admin | ddl_command_end -> pgrst_ddl_watch()
--   pgrst_drop_watch          | platform | ESIT | supabase_admin | sql_drop        -> pgrst_drop_watch()
--
-- Taban artık yalnız veriyle değil, karşılaştırma mantığıyla da doğrulandı.
--
-- ---------------------------------------------------------------------------
-- YORUMLAMA
--   durum = 'ESIT'       -> beklenen taban.
--   durum = 'DEVRE DISI' -> tetikleyici var ama ÇALIŞMIYOR. DUR.
--   durum = 'FAZLA'      -> tabanda olmayan yeni tetikleyici. DUR, incele.
--   durum = 'EKSIK'      -> tabandaki tetikleyici KAYBOLMUŞ. DUR.
-- ============================================================================

with

-- ---------------------------------------------------------------------------
-- TABAN — 2026-09-08'de üretimde ölçülen 7 event trigger.
-- Biri bizim (`ensure_rls`), altısı Supabase platformunun.
--
-- `fonksiyon` sütunu BİLGİDİR, karşılaştırmaya girmez: `regprocedure`
-- çıktısı şemayı `search_path`'e göre yazar ya da yazmaz, yani aynı nesne
-- iki oturumda farklı görünebilir. Ölçümde şemasız geldiler ve buraya
-- ÖLÇÜLDÜĞÜ GİBİ yazıldılar — şema öneki tahmin edilmedi.
-- Karşılaştırma ad + sahip + olay + etkinlik üzerinden yapılır.
-- ---------------------------------------------------------------------------
taban(ad, sahip, olay, fonksiyon, kaynak) as (
  values
    ('ensure_rls',                'postgres',       'ddl_command_end',
     'rls_auto_enable()',                           'BIZIM'),
    ('issue_graphql_placeholder', 'supabase_admin', 'sql_drop',
     'set_graphql_placeholder()',                   'platform'),
    ('issue_pg_cron_access',      'supabase_admin', 'ddl_command_end',
     'grant_pg_cron_access()',                      'platform'),
    ('issue_pg_graphql_access',   'supabase_admin', 'ddl_command_end',
     'grant_pg_graphql_access()',                   'platform'),
    ('issue_pg_net_access',       'supabase_admin', 'ddl_command_end',
     'grant_pg_net_access()',                       'platform'),
    ('pgrst_ddl_watch',           'supabase_admin', 'ddl_command_end',
     'pgrst_ddl_watch()',                           'platform'),
    ('pgrst_drop_watch',          'supabase_admin', 'sql_drop',
     'pgrst_drop_watch()',                          'platform')
),

mevcut as (
  select e.evtname                        as ad,
         e.evtowner::regrole::text        as sahip,
         e.evtevent                       as olay,
         e.evtfoid::regprocedure::text    as fonksiyon,
         e.evtenabled                     as etkin
    from pg_event_trigger e
),

-- Fonksiyon adları şema önekiyle değişebildiği için (uzantı taşınması),
-- eşleştirme ADA göre yapılır; fonksiyon farkı ayrıca raporlanır.
karsilastirma as (
  select coalesce(m.ad, t.ad) as ad,
         t.kaynak,
         m.sahip, m.olay, m.fonksiyon, m.etkin,
         t.sahip as beklenen_sahip, t.olay as beklenen_olay,
         (t.ad is not null) as tabanda,
         (m.ad is not null) as uretimde
    from mevcut m
    full outer join taban t on t.ad = m.ad
)

select
  case when kaynak = 'BIZIM' then 0 else 1 end as oncelik,
  ad,
  coalesce(kaynak, '(TABANDA YOK)')            as kaynak,
  case
    when not uretimde                       then 'EKSIK'
    when not tabanda                        then 'FAZLA'
    when etkin <> 'O'                       then 'DEVRE DISI'
    when sahip <> beklenen_sahip            then 'SAHIP DEGISTI'
    when olay  <> beklenen_olay             then 'OLAY DEGISTI'
    else                                         'ESIT'
  end                                          as durum,
  coalesce(sahip, '-')                         as sahip,
  coalesce(olay, '-') || ' -> ' || coalesce(fonksiyon, '-') as tanim
from karsilastirma

union all

-- Özet satırı: tek bakışta sayı.
select 2, 'OZET', 'sayac',
       case when (select count(*) from mevcut) = 7 then 'ESIT' else 'SAPMA' end,
       (select count(*) from mevcut)::text || ' / 7 beklenen',
       (select count(*) from mevcut where etkin <> 'O')::text || ' devre disi (0 olmali)'

order by 1, 2;

-- ============================================================================
-- STOP KRİTERLERİ
-- ----------------------------------------------------------------------------
-- `ensure_rls` satırı 'ESIT' DEĞİLSE -> DUR.
--   Bu bizim güvenlik ağımız. EKSIK ise yeni tablolar RLS'siz doğmaya
--   başlamıştır; DEVRE DISI ise katalogda görünür ama çalışmaz.
--   Her iki durumda da `public` şemasındaki RLS kapalı tablo sayısı
--   ayrıca ölçülmelidir (ACL uyarı kontrolü, D bloğu).
--
--   ⚠️ BU ARIZA SQL EDITOR'DEN ONARILAMAZ.
--   2026-09-08 ölçümü: `postgres` superuser DEĞİL ve üye olduğu dokuz
--   rolün (anon, authenticated, authenticator, pg_create_subscription,
--   pg_monitor, pg_read_all_data, pg_signal_backend, service_role,
--   supabase_privileged_role) hiçbiri superuser değil. `CREATE EVENT
--   TRIGGER` superuser ister ve grant edilebilen bir ayrıcalık değildir.
--
--   Yani `ensure_rls` bir kez düşerse ne doğrudan ne `set role` ile geri
--   konabilir — Supabase provizyon sırasında oluşturmuş, bizde yeniden
--   yaratma yolu yok. Kurtarma yolu Supabase desteğidir.
--
--   Sonuç: bu kontrolün yakaladığı arıza, "fark edip düzeltiriz"
--   sınıfında DEĞİL. Erken görmek tek savunma; görülmezse yeni tablolar
--   sessizce RLS'siz doğmaya devam eder. Her yayın öncesi çalıştırılır.
--
-- Herhangi bir satır 'FAZLA' ise -> DUR, incele.
--   Tabanda olmayan bir event trigger, her DDL olayında sahibinin
--   yetkisiyle kod çalıştıran yeni bir yüzeydir. Kim ekledi, ne yapıyor?
--
-- Platform tetikleyicilerinden biri 'EKSIK' ise -> DURMA, KAYDET.
--   Supabase kendi bileşenlerini değiştirmiş olabilir. Bu dosyadaki tabanı
--   güncelle ve nedenini yaz.
--
-- ---------------------------------------------------------------------------
-- BAKIM
--   Taban değiştiğinde bu dosyadaki `taban(...)` listesi güncellenir ve
--   değişikliğin GEREKÇESİ commit mesajına yazılır. Beklentiyi sessizce
--   ölçüme uydurmak, kontrolü kontrol olmaktan çıkarır.
-- ============================================================================
