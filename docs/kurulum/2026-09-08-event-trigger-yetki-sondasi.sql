-- ============================================================================
-- EVENT TRIGGER YETKİ SONDASI — SALT OKUMA
-- Tarih: 2026-09-08
--
-- BU DOSYA HİÇBİR ŞEY DEĞİŞTİRMEZ. Yalnız `select` içerir.
-- Supabase SQL Editor'e yapıştırılır.
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
--   Yani migration ya çalışır ya "permission denied to create event trigger"
--   ile reddedilir. Hangisi olduğunu ÖNCEDEN bilmek, `CANLIYA UYGULA`
--   onayını boşa harcamamayı sağlar.
--
--   Tek kaçış yolu üyeliktir: `postgres`, superuser olan bir role (ör.
--   `supabase_admin`) üyeyse `set role` ile o role geçip oluşturabilir.
--   Sorgu 2 tam olarak bunu ölçer.
-- ============================================================================


-- ---------------------------------------------------------------------------
-- 1) OTURUM VE ROL NİTELİKLERİ
--    `superuser = true` olan tek bir satır bile yeterlidir.
-- ---------------------------------------------------------------------------
select 1 as sorgu,
       r.rolname                        as rol,
       r.rolsuper                       as superuser,
       r.rolbypassrls                   as rls_baypas,
       r.rolcreaterole                  as rol_olusturabilir,
       (r.rolname = current_user)       as bu_oturum
  from pg_roles r
 where r.rolname in ('postgres', 'supabase_admin', 'supabase_auth_admin',
                     'service_role', 'authenticated', 'anon', current_user)
 order by r.rolname;


-- ---------------------------------------------------------------------------
-- 2) ÜYELİK ZİNCİRİ — current_user hangi rollere üye ve o roller superuser mı?
--
--    `uye_oldugu_rol_superuser = true` çıkan bir satır varsa,
--    `set role <o rol>;` ile event trigger oluşturulabilir.
--    Hiç satır dönmezse ya da hepsi false ise: PLATFORM SINIRI.
-- ---------------------------------------------------------------------------
select 2 as sorgu,
       r.rolname   as uye,
       g.rolname   as uye_oldugu_rol,
       g.rolsuper  as uye_oldugu_rol_superuser,
       m.admin_option
  from pg_auth_members m
  join pg_roles r on r.oid = m.member
  join pg_roles g on g.oid = m.roleid
 where r.rolname = current_user
 order by g.rolsuper desc, g.rolname;


-- ---------------------------------------------------------------------------
-- 3) MEVCUT EVENT TRIGGER'LAR
--    Zaten bir tane varsa, kim oluşturmuş? Sahibi bize bir yol gösterebilir:
--    o rol event trigger oluşturabilmiş demektir.
-- ---------------------------------------------------------------------------
select 3 as sorgu,
       e.evtname                as ad,
       e.evtowner::regrole::text as sahip,
       e.evtevent               as olay,
       case e.evtenabled when 'O' then 'acik'
                         when 'D' then 'KAPALI'
                         when 'R' then 'replica'
                         when 'A' then 'always' end as durum,
       e.evtfoid::regprocedure::text as fonksiyon,
       array_to_string(e.evttags, ', ') as etiketler
  from pg_event_trigger e
 order by e.evtname;


-- ---------------------------------------------------------------------------
-- 4) HEDEF FONKSİYON — bağlanacak fonksiyon gerçekten hazır mı?
--    Beklenen: 1 satır, returns_event_trigger = true, definer = true,
--    search_path pinli.
-- ---------------------------------------------------------------------------
select 4 as sorgu,
       p.proname                                  as ad,
       (p.prorettype = 'event_trigger'::regtype)  as returns_event_trigger,
       p.prosecdef                                as security_definer,
       (p.proconfig is not null
        and exists (select 1 from unnest(p.proconfig) k
                     where k like 'search_path=%'))as search_path_pinli,
       exists (select 1 from pg_event_trigger e
                where e.evtfoid = p.oid)          as zaten_bagli
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
 where n.nspname = 'public' and p.proname = 'rls_auto_enable';


-- ---------------------------------------------------------------------------
-- 5) AĞIN KAPATACAĞI BOŞLUK — şu an RLS'i kapalı tablo var mı?
--    Beklenen: 0. Sıfır değilse, event trigger bağlansa bile GEÇMİŞ
--    tabloları düzeltmez; onlar ayrıca ele alınmalıdır.
-- ---------------------------------------------------------------------------
select 5 as sorgu,
       count(*) filter (where not c.relrowsecurity)  as rls_kapali_tablo,
       count(*)                                      as toplam_tablo
  from pg_class c
  join pg_namespace n on n.oid = c.relnamespace
 where n.nspname = 'public' and c.relkind in ('r', 'p');


-- ============================================================================
-- KARAR
-- ----------------------------------------------------------------------------
-- Sorgu 1'de `postgres` için superuser = true
--   -> Migration doğrudan uygulanabilir.
--
-- Sorgu 1'de false AMA sorgu 2'de `uye_oldugu_rol_superuser = true` satırı var
--   -> Migration `set role <o rol>;` ile uygulanabilir. Migration dosyası bu
--      durumu destekleyecek biçimde güncellenir.
--
-- İkisi de yoksa
--   -> PLATFORM SINIRI. Event trigger kurulamaz. Bu bir hata değildir.
--      Güvenlik ağı ÖNLEME'den TESPİT'e taşınır: `rls_kapali_tablo` sayacı
--      ACL uyarı kontrolüne ve yayın öncesi parmak izine kalıcı kontrol
--      olarak eklenir. Supabase desteğine gidecek maddeye eklenir.
--
-- Sorgu 4'te `zaten_bagli = true` çıkarsa: iş zaten yapılmış, migration
-- gereksizdir. Repo ile üretim arasında bir sapma var demektir — araştır.
-- ============================================================================
