-- ============================================================================
-- VERİTABANI DÜZEYİ TABAN — SALT OKUMA (FAZ 2)
-- Tarih: 2026-09-09 · Yeniden çalıştırılabilir · Her yayından ÖNCE
--
-- BU DOSYA HİÇBİR ŞEY DEĞİŞTİRMEZ. Tek bir `select` içerir.
-- Supabase SQL Editor'e yapıştırılır.
--
-- ---------------------------------------------------------------------------
-- NE İŞE YARAR
-- ---------------------------------------------------------------------------
-- `pg_dump --schema=...` veritabanı düzeyindeki nesneleri dökmez; roller ise
-- hiç dökülmez. Taban dosyamız bu sınıflara yapısal olarak kördü. Event
-- trigger'lar `2026-09-08-event-trigger-tabani.sql` ile kapatıldı; bu dosya
-- KALANLARI kapatır ve sürüklenmeyi yakalar.
--
-- ---------------------------------------------------------------------------
-- TABAN KAYNAĞI — 2026-09-09 üretim ölçümü
-- ---------------------------------------------------------------------------
-- Beklenen değerlerin tamamı `2026-09-08-veritabani-duzeyi-kesif.sql`'in
-- üretimde çalıştırılmasıyla ÖLÇÜLDÜ. Hiçbiri tahmin değildir.
--
-- ---------------------------------------------------------------------------
-- ÜRETİM DOĞRULAMASI — 2026-09-09
-- ---------------------------------------------------------------------------
-- Üretimde çalıştırıldı: **22/22** — yirmi kontrol `ESIT`, iki uyarı
-- kontrolü (`E2`, `E3`) `BILINEN`. **Blok 2'den hiç satır gelmedi**, yani
-- sapan tek bir kayıt yok.
--
-- Taban artık iki yönlü doğrulanmış durumda: değerler keşif sorgusundan
-- ölçüldü, karşılaştırma da bu dosyanın kendi sorgusuyla üretimde teyit
-- edildi. Bundan sonraki her sapma gerçek bir değişikliktir.
--
-- ---------------------------------------------------------------------------
-- YORUMLAMA
--   tur='esit'  -> bulunan <> beklenen ise SAPMA. Yayını durdur.
--   tur='uyari' -> bulunan > beklenen ise büyümüş; blocker değil ama
--                  açıklanmadan geçilmez.
--   Blok 2 sapan KAYITLARI tek tek listeler: "hangisi?" sorusunun cevabı.
-- ============================================================================

with

-- ---------------------------------------------------------------------------
-- Bilinen platform şemaları — 2026-09-09'da ölçülen tam liste.
-- Bu listede OLMAYAN bir şema belirirse ya bizimdir (taban dökümü onu
-- görmüyor demektir) ya da platform yeni bir şey kurmuştur. İkisi de
-- açıklanmadan geçilmez.
-- ---------------------------------------------------------------------------
bilinen_sema(ad) as (
  values ('auth'), ('extensions'), ('graphql'), ('graphql_public'),
         ('pgbouncer'), ('phase0_private'), ('public'), ('realtime'),
         ('storage'), ('vault')
),

-- Sahibi biz olan, RLS'i baypas eden roller. Hepsi platform tarafından
-- gelir; biz rol yaratmayız.
bypass_rolleri(ad) as (
  values ('postgres'), ('service_role'), ('supabase_admin'),
         ('supabase_etl_admin'), ('supabase_read_only_user')
),

-- anon'un USAGE hakkı olan şemalar — Supabase varsayılanı.
anon_semalari(ad) as (
  values ('auth'), ('extensions'), ('graphql'), ('graphql_public'),
         ('public'), ('realtime'), ('storage')
),

-- --- ROLLER ---------------------------------------------------------------
r_tum as (select count(*) n from pg_roles where rolname not like 'pg\_%'),
r_super as (select count(*) n from pg_roles
             where rolname not like 'pg\_%' and rolsuper),
r_bypass as (select count(*) n from pg_roles
              where rolname not like 'pg\_%' and rolbypassrls),
r_login as (select count(*) n from pg_roles
             where rolname not like 'pg\_%' and rolcanlogin),
-- Tabandaki bypass listesinden SAPAN roller (yeni eklenen ya da kaybolan)
r_bypass_sapma as (
  select count(*) n from (
    select rolname from pg_roles where rolname not like 'pg\_%' and rolbypassrls
    except select ad from bypass_rolleri
    union all
    select ad from bypass_rolleri
    except select rolname from pg_roles where rolname not like 'pg\_%' and rolbypassrls
  ) s
),

-- --- ÜYELİKLER ------------------------------------------------------------
u_toplam as (
  select count(*) n from pg_auth_members m
    join pg_roles uye on uye.oid = m.member
   where uye.rolname not like 'pg\_%'
),
u_super as (
  select count(*) n from pg_auth_members m
    join pg_roles uye  on uye.oid  = m.member
    join pg_roles grup on grup.oid = m.roleid
   where uye.rolname not like 'pg\_%' and grup.rolsuper
),

-- --- AYARLAR --------------------------------------------------------------
a_rol as (select count(*) n from pg_db_role_setting where setrole <> 0),
a_db  as (select count(*) n from pg_db_role_setting where setrole =  0),

-- --- YAYINLAR (realtime) --------------------------------------------------
y_sayi as (select count(*) n from pg_publication),
y_tablo as (select count(*) n from pg_publication_tables),
y_tumu as (select count(*) n from pg_publication where puballtables),

-- --- ŞEMALAR --------------------------------------------------------------
s_bilinmeyen as (
  select count(*) n from pg_namespace n
   where n.nspname not like 'pg\_%' and n.nspname <> 'information_schema'
     and n.nspname not in (select ad from bilinen_sema)
),
s_anon as (
  select count(*) n from pg_namespace n
   where n.nspname not like 'pg\_%' and n.nspname <> 'information_schema'
     and n.nspacl is not null
     and array_to_string(n.nspacl::text[], ', ') ~ '(^|, )anon='
),
-- ACL girdisinin ALICISI boşsa PUBLIC demektir: `=U/sahip`.
-- `postgres=UC/postgres` PUBLIC DEĞİLDİR (keşif dosyasının ilk sürümündeki
-- hata tam olarak buydu).
s_public as (
  select count(*) n from pg_namespace n
   where n.nspname not like 'pg\_%' and n.nspname <> 'information_schema'
     and n.nspacl is not null
     and array_to_string(n.nspacl::text[], ', ') ~ '(^|, )='
),
s_phase0_kapali as (
  select count(*) n from pg_namespace n
   where n.nspname = 'phase0_private'
     and coalesce(array_to_string(n.nspacl::text[], ', '), '') ~ '(^|, )(anon|authenticated|=)'
),

-- --- UZANTI / DİL / DIŞ KAYNAK -------------------------------------------
e_sayi as (select count(*) n from pg_extension),
e_riskli as (
  select count(*) n from pg_extension
   where extname in ('pg_cron','pg_net','http','plpython3u','plperlu',
                     'dblink','postgres_fdw','file_fdw')
),
d_guvensiz as (select count(*) n from pg_language where lanispl and not lanpltrusted),
f_sunucu as (select count(*) n from pg_foreign_server),
f_esleme as (select count(*) n from pg_user_mapping),

-- --- ZAMANLANMIŞ İŞ / WEBHOOK / AĞ ---------------------------------------
v_tablolar as (
  select count(*) n from pg_class c join pg_namespace ns on ns.oid = c.relnamespace
   where (ns.nspname, c.relname) in
         (('cron','job'), ('supabase_functions','hooks'),
          ('net','http_request_queue'), ('net','_http_response'))
)

-- ============================================================================
-- BLOK 1 — KARAR TABLOSU
-- ============================================================================
select 1 as blok, kontrol, bulunan, beklenen, tur,
       case when tur = 'uyari' and bulunan > beklenen then 'BUYUDU'
            when tur = 'uyari' then 'BILINEN'
            when bulunan = beklenen then 'ESIT'
            else 'SAPMA' end as durum
from (values
  ('A1 pg_ disi rol sayisi',            (select n from r_tum),        15, 'esit'),
  ('A2 superuser rol',                  (select n from r_super),       1, 'esit'),
  ('A3 RLS baypas eden rol',            (select n from r_bypass),      5, 'esit'),
  ('A4 giris yapabilen rol',            (select n from r_login),       9, 'esit'),
  ('A5 bypass listesinden sapma',       (select n from r_bypass_sapma),0, 'esit'),

  ('B1 rol uyeligi (pg_ disi uye)',     (select n from u_toplam),     18, 'esit'),
  ('B2 superuser role uyelik',          (select n from u_super),       0, 'esit'),

  ('C1 role sabitlenmis ayar',          (select n from a_rol),         8, 'esit'),
  ('C2 veritabani ayari',               (select n from a_db),          1, 'esit'),

  ('D1 yayin (publication)',            (select n from y_sayi),        1, 'esit'),
  ('D2 YAYINDAKI TABLO',                (select n from y_tablo),       0, 'esit'),
  ('D3 tum_tablolar bayrakli yayin',    (select n from y_tumu),        0, 'esit'),

  ('E1 bilinmeyen sema',                (select n from s_bilinmeyen),  0, 'esit'),
  ('E2 anon USAGE li sema',             (select n from s_anon),        7, 'uyari'),
  ('E3 PUBLIC USAGE li sema',           (select n from s_public),      1, 'uyari'),
  ('E4 phase0_private acik mi',         (select n from s_phase0_kapali),0,'esit'),

  ('F1 uzanti sayisi',                  (select n from e_sayi),        6, 'esit'),
  ('F2 dis-etki uzantisi',              (select n from e_riskli),      0, 'esit'),
  ('G1 guvensiz dil',                   (select n from d_guvensiz),    0, 'esit'),
  ('G2 FDW sunucusu',                   (select n from f_sunucu),      0, 'esit'),
  ('G3 FDW kullanici eslemesi',         (select n from f_esleme),      0, 'esit'),
  ('H1 cron/webhook/net tablosu',       (select n from v_tablolar),    0, 'esit')
) as t(kontrol, bulunan, beklenen, tur)

union all

-- ============================================================================
-- BLOK 2 — SAPAN KAYITLAR (yalnız sapma varsa satır döner)
-- Sayı saptığında "hangisi?" sorusunu cevaplayan tek şey budur.
-- ============================================================================
select 2, 'RLS baypas: ' || rolname, -1, -1, 'kayit',
       'tabanda YOK - yeni eklendi'
  from pg_roles
 where rolname not like 'pg\_%' and rolbypassrls
   and rolname not in (select ad from bypass_rolleri)

union all
select 2, 'RLS baypas: ' || ad, -1, -1, 'kayit', 'tabanda VAR ama uretimde yok'
  from bypass_rolleri
 where ad not in (select rolname from pg_roles
                   where rolname not like 'pg\_%' and rolbypassrls)

union all
select 2, 'bilinmeyen sema: ' || n.nspname, -1, -1, 'kayit',
       'sahip=' || n.nspowner::regrole::text ||
       ' - taban dokumu bu semayi GORMUYOR'
  from pg_namespace n
 where n.nspname not like 'pg\_%' and n.nspname <> 'information_schema'
   and n.nspname not in (select ad from bilinen_sema)

union all
select 2, 'anon semasi: ' || n.nspname, -1, -1, 'kayit',
       'tabanda olmayan anon USAGE'
  from pg_namespace n
 where n.nspacl is not null
   and array_to_string(n.nspacl::text[], ', ') ~ '(^|, )anon='
   and n.nspname not in (select ad from anon_semalari)

union all
select 2, 'yayindaki tablo: ' || t.schemaname || '.' || t.tablename, -1, -1, 'kayit',
       'realtime bu tabloyu istemciye AKITIYOR'
  from pg_publication_tables t

union all
select 2, 'superuser role uyelik: ' || uye.rolname || ' -> ' || grup.rolname,
       -1, -1, 'kayit', 'set role ile superuser olabilir'
  from pg_auth_members m
  join pg_roles uye  on uye.oid  = m.member
  join pg_roles grup on grup.oid = m.roleid
 where uye.rolname not like 'pg\_%' and grup.rolsuper

union all
select 2, 'riskli uzanti: ' || extname, -1, -1, 'kayit',
       'dis etki / kod calistirma yuzeyi'
  from pg_extension
 where extname in ('pg_cron','pg_net','http','plpython3u','plperlu',
                   'dblink','postgres_fdw','file_fdw')

order by 1, 2;

-- ============================================================================
-- STOP KRİTERLERİ
-- ----------------------------------------------------------------------------
-- D2 <> 0  -> DUR. Realtime bir tabloyu istemciye akıtıyor. Yayın, RLS'ten
--             AYRI yapılandırılır: tablonun RLS'i kapalıysa satır
--             değişiklikleri filtresiz gider. Blok 2 hangi tablo olduğunu
--             söyler. 2026-09-09 ölçümü: yayında SIFIR tablo var.
--
-- A5 <> 0  -> DUR. RLS'i baypas eden roller değişmiş. Bu roller tüm otel
--             izolasyonunu ve tüm politikaları atlar; listeye bir ekleme
--             sessizce yapılmamalıdır.
--
-- B2 <> 0  -> DUR. Bir rol `set role` ile superuser olabiliyor.
--
-- E1 <> 0  -> DUR. Bilinmeyen bir şema var. İçinde tablo varsa TABAN DÖKÜMÜ
--             ONU GÖRMÜYOR demektir — 2026-09-08'de event trigger'larda
--             yaşanan kör noktanın aynısı.
--
-- E4 <> 0  -> DUR. `phase0_private` denetim izi altyapısını barındırır ve
--             anon/authenticated/PUBLIC'e kapalı olmalıdır.
--
-- F2/G1/G2/G3/H1 <> 0 -> DUR. Veritabanına DIŞARIYLA konuşma ya da keyfi
--             kod çalıştırma yeteneği eklenmiş: pg_cron periyodik SQL,
--             pg_net/http giden istek, webhook DDL/DML olayında dışarı HTTP,
--             FDW uzak bağlantı, güvensiz dil sunucuda kod. Hiçbiri bugün
--             kurulu değil ve kurulması bilinçli bir karar olmalıdır.
--
-- E2/E3 büyürse -> DURMA, AÇIKLA. Şema düzeyi USAGE tek başına veri vermez;
--             nesne ACL'i ve RLS asıl savunmadır. Ama yeni bir şemanın
--             anon'a açılması bilinerek olmalıdır.
--
-- ---------------------------------------------------------------------------
-- 2026-09-09 ÖLÇÜMÜ — bu tabanın kaynağı
-- ---------------------------------------------------------------------------
-- 15 rol · 1 superuser (supabase_admin) · 5 RLS-baypas (postgres,
-- service_role, supabase_admin, supabase_etl_admin, supabase_read_only_user)
-- · 9 giriş yapabilen · 18 üyelik, superuser'a 0 · 8 rol ayarı · 1 db ayarı
-- (app.settings.jwt_exp=3600) · 1 yayın (supabase_realtime) ve İÇİNDE 0
-- TABLO · 10 bilinen şema · anon 7 şemada USAGE · PUBLIC yalnız `public`
-- şemasında · 6 uzantı (btree_gist, pg_stat_statements, pgcrypto, plpgsql,
-- supabase_vault, uuid-ossp) · güvensiz dil 0 · FDW 0 · cron/webhook/net 0.
--
-- ---------------------------------------------------------------------------
-- BAKIM
--   Taban değiştiğinde yukarıdaki `values` listeleri ve beklenen sayılar
--   güncellenir ve değişikliğin GEREKÇESİ commit mesajına yazılır.
--   Beklentiyi sessizce ölçüme uydurmak, kontrolü kontrol olmaktan çıkarır.
-- ============================================================================
