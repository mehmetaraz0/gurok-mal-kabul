-- ============================================================
-- 2026-08-09 — ANON ROLÜ TABLO GRANT TEMİZLİĞİ (ikinci kilit)
-- ============================================================
-- DURUM: Anon anahtarıyla yapılan taramada ANA projede 56 tablo 200 dönüyor.
-- Hepsi 0 satır — yani RLS görevini yapıyor, veri sızmıyor. Ama tek savunma
-- katmanı RLS: ileride bir tabloya yanlış politika yazılırsa ya da RLS açık
-- kalmayı unutursa, anon anahtarı (istemci kodunda AÇIK) doğrudan okur.
--
-- ÇÖZÜM: anon'un tablo GRANT'lerini kaldır. Bundan sonra yanlış bir RLS
-- politikası bile veriyi açamaz — çünkü rolün tabloya izni yok.
--
-- ÖNCE DOĞRULANDI (bu yüzden güvenli):
--   • SB_HEADERS oturum varsa JWT taşır (supabase-config.js:11-14) → tüm
--     uygulama istekleri 'authenticated' rolüyle gider, anon ile değil.
--   • Giriş öncesi tablo okuması YOK: index.html PIN girişi Edge Function
--     üzerinden (service_role), giriş logu RPC ile (authenticated).
--   • bar-menu.html (girişsiz QR müşteri sayfası) SADECE MÜŞTERİ projesine
--     istek atar (CUSTOMER_SB_URL) — bu dosya ana projeyi etkilemez.
--   • bar-garson / bar-menu-yonetimi / bar-siparis-kuyrugu personel
--     sayfalarıdır, JH()/SB_HEADERS ile JWT taşırlar.
--
-- ⚠️ BU DOSYA SADECE ANA PROJEDE (erp / xwytofysmgqtqjzkplfi) ÇALIŞTIRILIR.
--    Müşteri projesinde (udjpcsjifgdzvfflezaa) ÇALIŞTIRMA — orada QR menü
--    akışı anon rolüyle çalışır, bu revoke müşteri menüsünü KIRAR.
-- ============================================================

begin;

-- 1) Mevcut tabloların/view'ların anon izinlerini kaldır
revoke all on all tables in schema public from anon;

-- 2) Bundan sonra oluşturulacak tablolar da anon'a açılmasın.
--    (Supabase varsayılanı yeni tabloya anon GRANT verir — asıl sorun bu.)
alter default privileges in schema public revoke all on tables from anon;

-- 3) Sıra (sequence) izinleri de gitsin — id üretimi anon'a lazım değil
revoke all on all sequences in schema public from anon;
alter default privileges in schema public revoke all on sequences from anon;

commit;

notify pgrst, 'reload schema';

-- ============================================================
-- DOĞRULAMA 1 — anon'a açık tablo KALMAMALI (boş liste beklenir)
-- ============================================================
-- select table_name, privilege_type
-- from information_schema.role_table_grants
-- where grantee = 'anon' and table_schema = 'public'
-- order by table_name;

-- ============================================================
-- DOĞRULAMA 2 — authenticated ERİŞİMİ BOZULMAMALI (dolu liste beklenir)
-- ============================================================
-- select count(*) as authenticated_tablo_sayisi
-- from information_schema.role_table_grants
-- where grantee = 'authenticated' and table_schema = 'public';

-- ============================================================
-- DOĞRULAMA 3 — stok tablo görünümünün 3 view'ı duruyor mu?
-- (Anon taramasında 404 döndüler; bu BEKLENEN durum — anon'un yetkisi yok.
--  Yine de gerçekten var olduklarını teyit et. 3 satır dönmeli.)
-- ============================================================
-- select table_name from information_schema.views
-- where table_schema='public'
--   and table_name in ('stok_acik_siparis','stok_acik_talep','stok_son_hareket');

-- ============================================================
-- GERİ ALMA — bir şey kırılırsa
-- ============================================================
-- grant select on all tables in schema public to anon;
-- alter default privileges in schema public grant select on tables to anon;
-- notify pgrst, 'reload schema';
--
-- NOT: Geri alman gerekirse ÖNCE hangi sayfanın kırıldığını söyle —
-- büyük ihtimalle o sayfa JWT yerine anon anahtarı kullanıyordur ve
-- doğru düzeltme grant değil, o sayfanın oturum başlığını düzeltmektir.

-- ============================================================
-- ÇALIŞTIRDIKTAN SONRA UYGULAMADA TEST
-- ============================================================
-- 1) PIN ile giriş yap                          → çalışmalı
-- 2) Stok Takip aç (kart + tablo görünümü)      → veri gelmeli
-- 3) Satın alma talepleri, mal kabul listesi    → veri gelmeli
-- 4) Muhasebe faturalar                         → veri gelmeli
-- 5) Bar garson ekranı (menü yükleniyor mu)     → çalışmalı
-- 6) QR müşteri menüsü (bar-menu.html)          → çalışmalı (müşteri projesi)
-- Boş liste görürsen o sayfa anon anahtarı kullanıyordur — bana söyle.
