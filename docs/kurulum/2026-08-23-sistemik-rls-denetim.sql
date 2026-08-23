-- ============================================================================
-- 2026-08-23 Sistemik RLS/Güvenlik Denetimi (SALT-OKUMA)
-- ============================================================================
-- Amaç: Pentest 1–4 serisinde tekrarlayan bulgu sınıflarını tek script ile
-- yakalamak. Supabase SQL Editor'de service_role/postgres bağlantısıyla
-- çalıştırın. HİÇBİR yazma işlemi içermez; yalnızca rapor üretir.
--
-- Yorum kuralı: her sorgunun altındaki "BEKLENEN" satırı geçerli durumu tanımlar.
-- Sapma = aksiyon gerektirir. Sonuçları kaydedip trend olarak saklayın.
-- ============================================================================

-- [1] RLS KAPALI TABLOLAR — public şemadaki tüm tablolarda RLS açık olmalı.
select c.relname as tablo, c.relrowsecurity as rls_acik
from pg_class c join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public' and c.relkind = 'r'
order by c.relname;
-- BEKLENEN: rls_acik = true (istisna yok; "RLS aç ama politika yok" da aşağıda yakalanır)

-- [2] POLİTİKASIZ TABLOLAR — RLS açık ama hiç politikası olmayan tablolar
-- service_role dışında HERKES için boş döner (sessiz özellik kaybı).
select c.relname as tablo
from pg_class c join pg_namespace n on n.oid = c.relnamespace
where n.nspname='public' and c.relkind='r' and c.relrowsecurity
  and not exists (select 1 from pg_policy p where p.polrelid = c.oid)
order by c.relname;
-- BEKLENEN: 0 satır

-- [3] ANON ERİŞİMİ OLAN TABLOLAR — anon role GRANT verilmiş tablolar.
-- Pentest sonrası hedef: anon'a tablo GRANT verilmemiş olması (RPC'ler hariç);
-- RLS tek savunma kalmasın diye ikinci kilit GRANT temizliğiyle kuruldu.
select table_name, privilege_type
from information_schema.role_table_grants
where grantee = 'anon' and table_schema = 'public'
order by table_name;
-- BEKLENEN: 0 satır (bar/müşteri tarafı ayrı projededir; burada görünmez)

-- [4] KONTROLSÜZ SECURITY DEFINER FONKSİYONLARI — search_path sabitlenmemiş
-- SD fonksiyonlar schema-trapdoor riski taşır (commit bb28b48 denetiminin devamı).
select p.proname,
       p.proconfig is null as search_path_sabitsiz
from pg_proc p join pg_namespace n on n.oid = p.pronamespace
where n.nspname='public' and p.prosecdef
order by p.proname;
-- BEKLENEN: tüm satırlarda search_path_sabitsiz = false
-- (proconfig: {search_path=...} set edilmeli)

-- [5] ANON/AUTHENTICATED ÇAĞRILABİLİR RPC'LER — execute izni olan fonksiyonlar.
select p.proname, a.privilege_type, g.rolname as grantee
from pg_proc p
join pg_namespace ns on ns.oid = p.pronamespace,
aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
join pg_roles g on g.oid = a.grantee
where ns.nspname='public' and g.rolname in ('anon','authenticated')
order by p.proname, g.rolname;
-- BEKLENEN: anon satırları yalnızca bilinçli açık uçlarda (örn. pin-girisi ile
-- ilgili RPC, masa_oteli_getir gibi token-doğrulayan fonksiyonlar). Liste dışı
-- her anon RPC = pentest bulgusu.

-- [6] OTOTATÖR/SAHİPLİK TUTARSIZLIĞI — tablo sahibi postgres değilse RLS
-- bypass edilmiş olabilir (owner zaten tam erişir, politika işlemez).
select c.relname, pg_get_userbyid(c.relowner) as sahip
from pg_class c join pg_namespace n on n.oid = c.relnamespace
where n.nspname='public' and c.relkind='r' and pg_get_userbyid(c.relowner) <> 'postgres';
-- BEKLENEN: 0 satır

-- [7] auth_uId() ÇÖZÜMLEYEN FONKSİYONLARDA AKTİFLİK KONTROLÜ —
-- pentest3 [1]+[2]: 'giriş yapmış' yetmez, 'aktif ERP kullanıcısı' olmalı.
-- (Manuel kontrol: auth_erp_kullanicisi()/auth_yetki_var() gövdesinde
--  aktif=true şartı ve otel_id kısıtı var mı — gövde metni:)
select p.proname, pg_get_functiondef(p.oid) as govde
from pg_proc p join pg_namespace n on n.oid = p.pronamespace
where n.nspname='public' and p.proname like 'auth_%';
-- BEKLENEN: her gövdede aktiflik + (gerektiğinde) otel_id kapsamı mevcut

-- [8] SON DURUM ÖZETİ (tek bakışta)
select
  (select count(*) from pg_class c join pg_namespace n on n.oid=c.relnamespace
    where n.nspname='public' and c.relkind='r') as toplam_tablo,
  (select count(*) from pg_class c join pg_namespace n on n.oid=c.relnamespace
    where n.nspname='public' and c.relkind='r' and not c.relrowsecurity) as rls_kapali,
  (select count(*) from pg_policy p join pg_class c on c.oid=p.polrelid
    join pg_namespace n on n.oid=c.relnamespace where n.nspname='public') as toplam_politika;
