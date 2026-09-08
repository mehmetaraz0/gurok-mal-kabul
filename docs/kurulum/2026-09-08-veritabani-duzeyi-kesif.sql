-- ============================================================================
-- VERİTABANI DÜZEYİ NESNELER — KEŞİF (FAZ 1)
-- Tarih: 2026-09-08 · SALT OKUMA · Tek `select`
--
-- BU DOSYA HİÇBİR ŞEY DEĞİŞTİRMEZ ve HİÇBİR BEKLENTİ İÇERMEZ.
-- Supabase SQL Editor'e yapıştırılır.
--
-- ---------------------------------------------------------------------------
-- NEDEN VAR
-- ---------------------------------------------------------------------------
-- Taban şema dökümümüz:
--
--   pg_dump --schema=public --schema=phase0_private --schema-only --no-owner
--
-- `--schema` filtresi verildiğinde pg_dump **veritabanı düzeyindeki
-- nesneleri dökmez**. 2026-09-08'de bunun bedeli ödendi: `ensure_rls` event
-- trigger'ı üretimde altı hafta çalıştı ve biz onu "hiç bağlanmamış"
-- sandık — çünkü hiçbir ölçüm aracımız o sınıfa bakmıyordu.
--
-- Event trigger'lar `2026-09-08-event-trigger-tabani.sql` ile kapatıldı.
-- Bu dosya KALAN sınıfları ölçer.
--
-- Ayrıca pg_dump ROLLERİ hiç dökmez (o `pg_dumpall --roles-only` işidir) ve
-- dökümümüz yalnız iki şemayı kapsar — başka bir şemada bizim verimiz varsa
-- taban onu da görmez. Bu dosya ikisini de kontrol eder.
--
-- ---------------------------------------------------------------------------
-- NEDEN BEKLENTİ YOK — FAZ 1 / FAZ 2
-- ---------------------------------------------------------------------------
-- Bugün iki kez öğrenildi: ölçülmemiş bir sayıya beklenti yazmak, kontrolü
-- kontrol olmaktan çıkarır. Bu yüzden:
--
--   FAZ 1 (bu dosya)  : yalnız KEŞİF. Her satır bilgi. Beklenen değer yok.
--   FAZ 2 (sonraki)   : bu çıktıdan taban sabitlenir, tıpkı event trigger
--                       tabanında yapıldığı gibi.
--
-- ---------------------------------------------------------------------------
-- YEREL DOĞRULAMA — 2026-09-08, atılabilir PostgreSQL 17.11 konteynerinde
-- ---------------------------------------------------------------------------
-- Bu dosya üretime verilmeden ÖNCE gerçek bir PostgreSQL'de çalıştırıldı.
-- "Ayrıştırıldı" yetmez: boş bir veritabanında beş blok hiç satır döndürür
-- ve sorgu yine de "çalıştı" görünür. Bu yüzden her blok, yakalaması
-- gereken durum KASITLI olarak kurularak sınandı:
--
--   kurulan durum                          -> beklenen bulgu          sonuc
--   ------------------------------------------------------------------ ----
--   `gizli` şeması + içinde tablo          -> KAPSAM "DOKUMDE YOK"      ✓
--   grant ... with admin option            -> "uyeligi baskasina..."    ✓
--   grant <superuser rol>                  -> "DIKKAT: superuser..."    ✓
--   alter role ... set search_path         -> ROL-AYAR satırı           ✓
--   alter database ... set statement_...   -> DB-AYAR satırı            ✓
--   publication + RLS'siz tablo            -> "RLS KAPALI - ...akabilir"✓
--   publication + RLS'li tablo + politika  -> "RLS acik"                ✓
--   grant usage on schema ... to anon      -> "anon ERISEBILIR"         ✓
--   cron.job tablosu oluşturuldu           -> VARLIK "VAR"              ✓
--
-- Sınanamayan tek yol: güvensiz dil (`lanpltrusted=false`) — konteynerde
-- plpython3u yoktu. Mantık tek satırlık bir `case`tir.
--
-- ---------------------------------------------------------------------------
-- GÜVENLİK YÜZEYİ SIRALAMASI — çıktı bu sıraya göre gelir
-- ---------------------------------------------------------------------------
--   0  KAPSAM     : dökümün görmediği şemalarda tablo var mı  (EN KRİTİK)
--   1  ROL        : superuser / bypassrls / login yetkileri
--   2  UYELIK     : kim kime üye — yetki yükseltme yolları
--   3  ROL-AYAR   : role sabitlenmiş search_path vb.
--   4  DB-AYAR    : ALTER DATABASE ... SET
--   5  YAYIN      : realtime hangi tabloları yayınlıyor
--   6  SEMA       : şema sahipleri ve PUBLIC/anon erişimi
--   7  UZANTI     : kurulu uzantılar ve şemaları
--   8  DIL        : güvensiz (untrusted) diller — keyfi kod yüzeyi
--   9  DIS-KAYNAK : FDW sunucuları ve kullanıcı eşlemeleri
--  10  VARLIK     : cron / webhook / net tabloları var mı
-- ============================================================================

with

-- ---------------------------------------------------------------------------
-- 0) KAPSAM — dökümün GÖRMEDİĞİ şemalarda tablo var mı?
--    `public` ve `phase0_private` dışında bizim verimiz varsa taban eksiktir.
--    Supabase'in kendi şemaları (auth, storage, realtime...) beklenendir.
-- ---------------------------------------------------------------------------
b0 as (
  select 0 as oncelik,
         'KAPSAM' as sinif,
         n.nspname as ad,
         count(*) filter (where c.relkind in ('r','p'))::text || ' tablo' as deger1,
         count(*) filter (where c.relkind = 'v')::text || ' view' as deger2,
         case when n.nspname in ('public','phase0_private')
              then 'DOKUMDE VAR'
              else 'DOKUMDE YOK - icerigi taban disinda' end as aciklama
    from pg_namespace n
    join pg_class c on c.relnamespace = n.oid
   where n.nspname not like 'pg\_%'
     and n.nspname <> 'information_schema'
     and c.relkind in ('r','p','v')
   group by n.nspname
),

-- ---------------------------------------------------------------------------
-- 1) ROL NİTELİKLERİ
--    `pg_` ile başlayanlar PostgreSQL'in yerleşik rolleridir; nitelikleri
--    sabittir, gürültü yapmasınlar diye dışarıda. Üyelikleri blok 2'de.
-- ---------------------------------------------------------------------------
b1 as (
  select 1, 'ROL', r.rolname,
         'super=' || r.rolsuper::text ||
         ' bypassrls=' || r.rolbypassrls::text ||
         ' login=' || r.rolcanlogin::text,
         'createrole=' || r.rolcreaterole::text ||
         ' createdb=' || r.rolcreatedb::text ||
         ' replication=' || r.rolreplication::text,
         case when r.rolsuper then 'SUPERUSER'
              when r.rolbypassrls then 'RLS BAYPAS EDER'
              when r.rolcanlogin then 'giris yapabilir'
              else '' end
    from pg_roles r
   where r.rolname not like 'pg\_%'
),

-- ---------------------------------------------------------------------------
-- 2) ROL ÜYELİKLERİ — yetki yükseltme grafiği
--    `admin_option = true` üyeyi, üyeliği BAŞKASINA VERME yetkisiyle
--    donatır: tek başına bir yayılma yoludur.
-- ---------------------------------------------------------------------------
b2 as (
  select 2, 'UYELIK', uye.rolname || ' -> ' || grup.rolname,
         'grup_super=' || grup.rolsuper::text,
         'admin_option=' || m.admin_option::text,
         case when grup.rolsuper then 'DIKKAT: superuser role uyelik'
              when m.admin_option then 'uyeligi baskasina verebilir'
              else '' end
    from pg_auth_members m
    join pg_roles uye  on uye.oid  = m.member
    join pg_roles grup on grup.oid = m.roleid
   where uye.rolname not like 'pg\_%'
),

-- ---------------------------------------------------------------------------
-- 3) ROLE SABİTLENMİŞ AYARLAR
--    Bir role sabitlenmiş `search_path`, o rolün açtığı her oturumu etkiler.
--    SECURITY DEFINER fonksiyonlarındaki pinden BAĞIMSIZDIR ve gözden kaçar.
-- ---------------------------------------------------------------------------
b3 as (
  select 3, 'ROL-AYAR', r.rolname,
         coalesce(d.datname, '(tum veritabanlari)'),
         array_to_string(s.setconfig, ' | '),
         'bu rolun her oturumunda gecerli'
    from pg_db_role_setting s
    join pg_roles r on r.oid = s.setrole
    left join pg_database d on d.oid = s.setdatabase
   where s.setrole <> 0
),

-- ---------------------------------------------------------------------------
-- 4) VERİTABANI AYARLARI — ALTER DATABASE ... SET
-- ---------------------------------------------------------------------------
b4 as (
  select 4, 'DB-AYAR', coalesce(d.datname, '(global)'),
         'tum roller',
         array_to_string(s.setconfig, ' | '),
         'her baglantida gecerli'
    from pg_db_role_setting s
    left join pg_database d on d.oid = s.setdatabase
   where s.setrole = 0
),

-- ---------------------------------------------------------------------------
-- 5) YAYINLAR (realtime) — hangi tablolar istemciye akıyor?
--    Bir tabloyu `supabase_realtime` yayınına eklemek, satır
--    değişikliklerini abone istemcilere gönderir. Bu bir OKUMA yüzeyidir ve
--    RLS'ten AYRI yapılandırılır.
-- ---------------------------------------------------------------------------
b5_yayin as (
  select 5, 'YAYIN', p.pubname,
         'tum_tablolar=' || p.puballtables::text,
         'ins/upd/del/trunc=' || p.pubinsert::text || '/' || p.pubupdate::text
           || '/' || p.pubdelete::text || '/' || p.pubtruncate::text,
         case when p.puballtables
              then 'DIKKAT: TUM tablolar yayinda'
              else (select count(*)::text from pg_publication_tables t
                     where t.pubname = p.pubname) || ' tablo' end
    from pg_publication p
),
-- Tablo, ADI ile değil (ad şemalar arasında tekrar edebilir) şema+ad
-- çiftiyle eşleştirilir; aksi halde her mükerrer ad için sahte satır çıkardı.
b5_tablo as (
  select 5, 'YAYIN-TABLO', t.pubname || ': ' || t.schemaname || '.' || t.tablename,
         'rls=' || coalesce(c.relrowsecurity::text, '?'),
         'politika=' || coalesce(
           (select count(*)::text from pg_policy p where p.polrelid = c.oid), '?'),
         case when c.oid is null then 'tablo katalogda bulunamadi'
              when not c.relrowsecurity then 'RLS KAPALI - degisiklikler filtresiz akabilir'
              when not exists (select 1 from pg_policy p where p.polrelid = c.oid)
                   then 'RLS acik ama POLITIKA YOK'
              else 'RLS acik' end
    from pg_publication_tables t
    left join pg_namespace n on n.nspname = t.schemaname
    left join pg_class c on c.relnamespace = n.oid and c.relname = t.tablename
),

-- ---------------------------------------------------------------------------
-- 6) ŞEMALAR — sahibi kim, PUBLIC/anon girebiliyor mu?
--    Bir şemada USAGE olmadan içindeki hiçbir nesneye erişilemez; USAGE
--    varsa nesne bazlı ACL tek savunma kalır.
-- ---------------------------------------------------------------------------
b6 as (
  select 6, 'SEMA', n.nspname,
         'sahip=' || n.nspowner::regrole::text,
         coalesce(array_to_string(n.nspacl::text[], ', '), '(varsayilan)'),
         case
           when n.nspacl::text like '%anon=%'   then 'anon ERISEBILIR'
           when n.nspacl::text like '%=UC/%'    then 'PUBLIC erisebilir'
           when n.nspacl is null                then 'ACL yok - sahibe ozel'
           else '' end
    from pg_namespace n
   where n.nspname not like 'pg\_%'
     and n.nspname <> 'information_schema'
),

-- ---------------------------------------------------------------------------
-- 7) UZANTILAR
--    Uzantı, kendi şemasında fonksiyon getirir ve o fonksiyonlar varsayılan
--    olarak PUBLIC'e açıktır. Hangi uzantı hangi şemada, bilinmesi gerekir.
-- ---------------------------------------------------------------------------
b7 as (
  select 7, 'UZANTI', e.extname,
         'surum=' || e.extversion,
         'sema=' || e.extnamespace::regnamespace::text,
         case when e.extname in ('pg_cron','pg_net','http','plpython3u','dblink','postgres_fdw')
              then 'DIS ETKI / KOD CALISTIRMA yuzeyi' else '' end
    from pg_extension e
),

-- ---------------------------------------------------------------------------
-- 8) GÜVENSİZ DİLLER
--    `lanpltrusted = false` bir dil, sunucuda keyfi kod çalıştırabilir
--    (dosya sistemi, ağ). Yalnız superuser fonksiyon yazabilir, ama dilin
--    KURULU olması bile kayda değer.
-- ---------------------------------------------------------------------------
b8 as (
  select 8, 'DIL', l.lanname,
         'guvenli=' || l.lanpltrusted::text,
         'sahip=' || l.lanowner::regrole::text,
         case when not l.lanpltrusted then 'GUVENSIZ - keyfi kod' else '' end
    from pg_language l
   where l.lanispl
),

-- ---------------------------------------------------------------------------
-- 9) DIŞ KAYNAKLAR — FDW sunucusu ve kullanıcı eşlemeleri
--    Bir foreign server + user mapping, veritabanının DIŞARIYA bağlanma
--    yoludur ve eşlemede kimlik bilgisi saklanabilir.
-- ---------------------------------------------------------------------------
b9 as (
  select 9, 'DIS-KAYNAK', s.srvname,
         'fdw=' || w.fdwname,
         'sahip=' || s.srvowner::regrole::text,
         (select count(*)::text from pg_user_mapping u where u.umserver = s.oid)
           || ' kullanici eslemesi'
    from pg_foreign_server s
    join pg_foreign_data_wrapper w on w.oid = s.srvfdw
  union all
  select 9, 'DIS-KAYNAK', '(FDW sunucusu yok)', '-', '-', 'temiz'
   where not exists (select 1 from pg_foreign_server)
),

-- ---------------------------------------------------------------------------
-- 10) VARLIK KONTROLÜ — zamanlanmış iş / webhook / ağ tabloları
--     İÇERİK okunmuyor: bu tablolar yoksa doğrudan sorgulamak dosyayı
--     ayrıştırma hatasıyla düşürürdü. Yalnız KATALOG üzerinden varlık
--     sorulur; varsa içerik ikinci adımda okunur (aşağıya bakınız).
--
--     Neden önemli: bir cron işi ya da webhook, kimsenin oturumu olmadan,
--     periyodik olarak veri okuyup DIŞARIYA gönderebilir.
-- ---------------------------------------------------------------------------
b10 as (
  select 10, 'VARLIK', hedef.ad,
         case when exists (
                select 1 from pg_class c join pg_namespace n on n.oid = c.relnamespace
                 where n.nspname = hedef.sema and c.relname = hedef.tablo
              ) then 'VAR' else 'yok' end,
         hedef.sema || '.' || hedef.tablo,
         hedef.aciklama
    from (values
      ('zamanlanmis isler',   'cron',               'job',
       'Periyodik SQL calistirir - icerigi okunmali'),
      ('veritabani webhooklari','supabase_functions','hooks',
       'DDL/DML olayinda DISARIYA HTTP atar - icerigi okunmali'),
      ('net istek kuyrugu',   'net',                'http_request_queue',
       'pg_net giden istek kuyrugu'),
      ('net yanit',           'net',                '_http_response',
       'pg_net yanit tamponu')
    ) as hedef(ad, sema, tablo, aciklama)
)

select oncelik, sinif, ad, deger1, deger2, aciklama from b0
union all select * from b1
union all select * from b2
union all select * from b3
union all select * from b4
union all select * from b5_yayin
union all select * from b5_tablo
union all select * from b6
union all select * from b7
union all select * from b8
union all select * from b9
union all select * from b10
order by 1, 2, 3;

-- ============================================================================
-- İKİNCİ ADIM — yalnız blok 10 "VAR" derse çalıştır
-- ----------------------------------------------------------------------------
-- Bu sorgular, ilgili tablo YOKSA hata verir. Bu yüzden ayrı tutuldular ve
-- yukarıdaki keşfin içine konmadılar.
--
-- cron.job VAR ise:
--   select jobid, jobname, schedule, username, active,
--          left(command, 120) as komut
--     from cron.job order by jobid;
--
-- supabase_functions.hooks VAR ise:
--   select id, hook_table_id, hook_name, created_at
--     from supabase_functions.hooks order by id;
--   -- ve tanimlari:
--   select tgname, tgrelid::regclass::text as tablo,
--          left(pg_get_triggerdef(oid), 200) as tanim
--     from pg_trigger
--    where tgname like 'supabase_functions%' and not tgisinternal;
--
-- ============================================================================
-- OKUMA REHBERİ — çıktıda öncelikle şunlara bak
-- ----------------------------------------------------------------------------
-- 1. KAPSAM: "DOKUMDE YOK" satırlarında tablo sayısı. Supabase'in kendi
--    şemaları beklenendir (auth, storage, realtime, vault, extensions,
--    graphql, net, cron, supabase_functions). Bunların DIŞINDA bir şema
--    varsa ve içinde tablo varsa: tabanımız bizim verimizi görmüyor demektir.
--
-- 2. ROL: `super=true` ya da `bypassrls=true` olan HER rol. `bypassrls`
--    RLS'i tamamen atlar — kimde olduğu bilinmeli.
--
-- 3. UYELIK: "DIKKAT: superuser role uyelik" satırı. Böyle bir satır varsa
--    o rol `set role` ile superuser olabilir.
--
-- 4. YAYIN-TABLO: "RLS KAPALI" satırı. Yayındaki bir tabloda RLS kapalıysa
--    satır değişiklikleri abone istemcilere filtresiz akıyor olabilir.
--
-- 5. SEMA: "anon ERISEBILIR". `public` dışında anon'a açık şema beklenmez.
--
-- 6. VARLIK: cron / webhook "VAR" ise ikinci adım sorguları çalıştırılır.
--
-- Çıktı geldiğinde FAZ 2 yazılır: ölçülen değerler taban olarak sabitlenir
-- ve bu dosya beklentili bir kontrole dönüşür.
-- ============================================================================
