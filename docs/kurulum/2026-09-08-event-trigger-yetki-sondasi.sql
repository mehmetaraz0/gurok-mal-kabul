-- ============================================================================
-- EVENT TRIGGER YETKİ SONDASI — SALT OKUMA
-- Tarih: 2026-09-08
--
-- BU DOSYA HİÇBİR ŞEY DEĞİŞTİRMEZ. Tek bir `select` içerir.
-- Supabase SQL Editor'e yapıştırılır.
--
-- ⚠️ TEK SORGU OLMASI KASITLIDIR: SQL Editor birden çok ifade çalıştırdığında
--    yalnız SONUNCUNUN sonucunu gösterir. İlk sürüm beş ayrı `select` idi ve
--    kullanıcıya yalnız beşincisi ulaştı. Tüm bloklar `union all` ile tek
--    sonuç kümesinde toplandı.
--
-- AMAÇ
--   `2026-09-08-rls-auto-enable-baglama.sql` uygulanmadan ÖNCE, uygulanabilir
--   olup olmadığını ölçmek.
--
-- NEDEN GEREKLİ
--   PostgreSQL'de `CREATE EVENT TRIGGER` **superuser** gerektirir. Bu, grant
--   edilebilen bir ayrıcalık DEĞİLDİR — `pg_create_event_trigger` diye bir
--   önceden tanımlı rol yoktur (PG 17 dâhil). Supabase'de SQL Editor
--   `postgres` olarak çalışır ve `postgres` gerçek superuser değildir.
--
--   Tek kaçış yolu üyeliktir: `postgres`, superuser olan bir role üyeyse
--   `set role` ile o role geçip oluşturabilir.
--
--   Migration ya çalışır ya "permission denied to create event trigger" ile
--   reddedilir. Hangisi olduğunu ÖNCEDEN bilmek, `CANLIYA UYGULA` onayını
--   boşa harcamamayı sağlar.
--
-- OKUMA SIRASI
--   satir 0  -> KARAR. Tek başına yeterli.
--   satir 1  -> rol nitelikleri (superuser kim?)
--   satir 2  -> üyelik zinciri (superuser bir role üye miyiz?)
--   satir 3  -> mevcut event trigger'lar
--   satir 4  -> hedef fonksiyon hazır mı
--   satir 5  -> ağın kapatacağı boşluk (RLS kapalı tablo)
-- ============================================================================

with

-- --- Ham ölçümler ----------------------------------------------------------
superuser_var as (
  select exists (select 1 from pg_roles
                  where rolname = current_user and rolsuper) as v
),
uyelik_superuser as (
  select exists (select 1
                   from pg_auth_members m
                   join pg_roles r on r.oid = m.member
                   join pg_roles g on g.oid = m.roleid
                  where r.rolname = current_user and g.rolsuper) as v
),
zaten_bagli as (
  select exists (select 1 from pg_event_trigger e
                   join pg_proc p on p.oid = e.evtfoid
                   join pg_namespace n on n.oid = p.pronamespace
                  where n.nspname = 'public'
                    and p.proname = 'rls_auto_enable') as v
),

-- --- 0) KARAR --------------------------------------------------------------
karar as (
  select 0 as satir,
         'KARAR' as ad,
         case
           when (select v from zaten_bagli)      then 'ZATEN BAGLI'
           when (select v from superuser_var)    then 'UYGULANABILIR (dogrudan)'
           when (select v from uyelik_superuser) then 'UYGULANABILIR (set role ile)'
           else                                       'PLATFORM SINIRI'
         end as deger1,
         'oturum: ' || current_user as deger2,
         case
           when (select v from zaten_bagli)
             then 'Event trigger zaten bagli. Migration GEREKSIZ; repo ile uretim arasinda sapma var, arastir.'
           when (select v from superuser_var)
             then 'Migration dogrudan uygulanabilir. CANLIYA UYGULA onayi istenebilir.'
           when (select v from uyelik_superuser)
             then 'set role <superuser rol>; ile uygulanabilir. Migration bu duruma gore guncellenmeli.'
           else
             'CREATE EVENT TRIGGER kurulamaz. Hata degil, platform sinirdir. Ag onlemeden tespite tasinir; Supabase destek maddesine eklenir.'
         end as aciklama
),

-- --- 1) Rol nitelikleri ----------------------------------------------------
roller as (
  select 1 as satir,
         r.rolname as ad,
         'superuser=' || r.rolsuper::text as deger1,
         'rls_baypas=' || r.rolbypassrls::text as deger2,
         case when r.rolname = current_user then '<<< BU OTURUM' else '' end as aciklama
    from pg_roles r
   where r.rolname in ('postgres', 'supabase_admin', 'supabase_auth_admin',
                       'service_role', 'authenticated', 'anon', current_user)
),

-- --- 2) Üyelik zinciri (boşsa da bir satır dönsün) -------------------------
uyelikler as (
  select 2 as satir,
         g.rolname as ad,
         'superuser=' || g.rolsuper::text as deger1,
         'admin_option=' || m.admin_option::text as deger2,
         current_user || ' bu role uye' as aciklama
    from pg_auth_members m
    join pg_roles r on r.oid = m.member
    join pg_roles g on g.oid = m.roleid
   where r.rolname = current_user
  union all
  select 2, '(uyelik yok)', '-', '-',
         current_user || ' hicbir role uye degil'
   where not exists (select 1 from pg_auth_members m
                       join pg_roles r on r.oid = m.member
                      where r.rolname = current_user)
),

-- --- 3) Mevcut event trigger'lar (boşsa da bir satır) ----------------------
tetikleyiciler as (
  select 3 as satir,
         e.evtname as ad,
         'sahip=' || e.evtowner::regrole::text as deger1,
         'durum=' || (case e.evtenabled when 'O' then 'acik'
                                        when 'D' then 'KAPALI'
                                        when 'R' then 'replica'
                                        else 'always' end) as deger2,
         e.evtevent || ' -> ' || e.evtfoid::regprocedure::text as aciklama
    from pg_event_trigger e
  union all
  select 3, '(event trigger yok)', '-', '-',
         'Bu veritabaninda hic event trigger tanimli degil'
   where not exists (select 1 from pg_event_trigger)
),

-- --- 4) Hedef fonksiyon ----------------------------------------------------
hedef as (
  select 4 as satir,
         'public.' || p.proname as ad,
         'returns_event_trigger=' ||
           (p.prorettype = 'event_trigger'::regtype)::text as deger1,
         'definer=' || p.prosecdef::text ||
         ' pinli=' || (p.proconfig is not null and exists (
             select 1 from unnest(p.proconfig) k where k like 'search_path=%'))::text as deger2,
         'zaten_bagli=' || (select v from zaten_bagli)::text as aciklama
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'rls_auto_enable'
  union all
  select 4, '(rls_auto_enable YOK)', '-', '-',
         'Hedef fonksiyon bulunamadi - migration onkosulu saglanmiyor'
   where not exists (select 1 from pg_proc p
                       join pg_namespace n on n.oid = p.pronamespace
                      where n.nspname = 'public' and p.proname = 'rls_auto_enable')
),

-- --- 5) Ağın kapatacağı boşluk --------------------------------------------
rls_durumu as (
  select 5 as satir,
         'public semasi RLS' as ad,
         'rls_kapali=' || count(*) filter (where not c.relrowsecurity)::text as deger1,
         'toplam_tablo=' || count(*)::text as deger2,
         case when count(*) filter (where not c.relrowsecurity) = 0
              then 'Temiz. Ag baglanirsa yalniz YENI tablolari korur.'
              else 'DIKKAT: gecmis tablolar var; ag onlari ACMAZ, ayrica ele alinmali.'
         end as aciklama
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public' and c.relkind in ('r', 'p')
)

select * from karar
union all select * from roller
union all select * from uyelikler
union all select * from tetikleyiciler
union all select * from hedef
union all select * from rls_durumu
order by satir, ad;

-- ============================================================================
-- KARAR TABLOSU (satır 0 zaten söylüyor; burası gerekçesi)
-- ----------------------------------------------------------------------------
-- UYGULANABILIR (dogrudan)
--   -> `2026-09-08-rls-auto-enable-baglama.sql` olduğu gibi uygulanır.
--      CANLIYA UYGULA onayı istenir.
--
-- UYGULANABILIR (set role ile)
--   -> Migration, transaction başında `set role <superuser rol>;` alacak
--      biçimde güncellenir. Rol değişimi transaction sonunda geri döner.
--
-- PLATFORM SINIRI
--   -> Event trigger kurulamaz. BU BİR HATA DEĞİLDİR.
--      Güvenlik ağı ÖNLEME'den TESPİT'e taşınır: `rls_kapali` sayacı kalıcı
--      kontrol hâline gelir ve Supabase destek maddesine eklenir.
--      Migration dosyası repoda kayıt olarak kalır — yeni kurulumlarda
--      (self-hosted, superuser'ın olduğu ortamlar) çalışır.
--
-- ZATEN BAGLI
--   -> İş yapılmış. Repo ile üretim arasında kayıtsız bir değişiklik var
--      demektir; ne zaman ve kim tarafından yapıldığı araştırılır.
-- ============================================================================
