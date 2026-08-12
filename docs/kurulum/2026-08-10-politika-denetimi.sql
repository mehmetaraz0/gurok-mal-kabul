-- ============================================================
-- 2026-08-10 — POLİTİKA DENETİMİ (salt-okuma, hiçbir şeyi değiştirmez)
-- ============================================================
-- AMAÇ: "yetkilendirme katmanı kurşun geçirmez mi?" sorusunu tahminle değil
-- ÖLÇÜMLE cevaplamak. Şimdiye kadarki tüm düzeltmeler REAKTİFTİ: sızma testi
-- bir yer gösterdi, orayı kapattık. Bu dosya SİSTEMATİK bakar — testin
-- göstermediği yerleri de tarar.
--
-- Neden repodan bakılamıyor: fonksiyonlar 20+ ayrı SQL dosyasına dağılmış ve
-- şema dökümü 2026-07-30'dan bayat. Tek yetkili kaynak canlı veritabanıdır.
--
-- 8 sorgu var. Her birini ayrı ayrı çalıştırıp sonucu paylaş; hangilerinin
-- BOŞ dönmesi gerektiği başlıklarda yazıyor.
-- ============================================================


-- ============================================================
-- 1) RLS KAPALI TABLOLAR  → BOŞ DÖNMELİ
-- ------------------------------------------------------------
-- RLS kapalıysa politika ne olursa olsun GRANT'i olan herkes okur/yazar.
-- Bu listede bir şey çıkarsa en ağır bulgu odur.
-- ============================================================
select c.relname as tablo
from pg_class c
join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public' and c.relkind = 'r' and c.relrowsecurity = false
order by 1;


-- ============================================================
-- 2) RLS AÇIK AMA HİÇ POLİTİKASI OLMAYAN TABLOLAR
-- ------------------------------------------------------------
-- Bunlar "varsayılan reddet" demektir = güvenli, AMA erişim yalnızca
-- SECURITY DEFINER RPC üzerinden olur. Beklenen liste:
--   sayim_oturumlari, edefter_sube_bilgileri, edefter_kurum_bilgileri,
--   gelen_efaturalar, sayim_detaylari, urun_birim_donusum
-- Bunların DIŞINDA bir şey çıkarsa muhtemelen BOZUK/erişilemez bir modüldür.
-- ⚠️ Bu tablolara RLS otel-politikası EKLEME — kapalı yolu açar.
-- ============================================================
select c.relname as tablo
from pg_class c
join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public' and c.relkind = 'r' and c.relrowsecurity = true
  and not exists (select 1 from pg_policies p
                  where p.schemaname = 'public' and p.tablename = c.relname)
order by 1;


-- ============================================================
-- 3) HİÇBİR KORUMA İÇERMEYEN POLİTİKALAR  → BOŞ DÖNMELİ
-- ------------------------------------------------------------
-- Üç yardımcıdan hiçbirini kullanmayan politika = sadece "giriş yapmış mı"
-- ya da tamamen açık demektir.
-- ============================================================
select tablename, policyname, cmd, roles,
       coalesce(qual,'(yok)') as using_ifadesi,
       coalesce(with_check,'(yok)') as with_check_ifadesi
from pg_policies
where schemaname = 'public'
  and coalesce(qual,'')       !~* 'auth_yetki_var|auth_otel_erisim|auth_erp_kullanicisi|auth_kullanici_id'
  and coalesce(with_check,'') !~* 'auth_yetki_var|auth_otel_erisim|auth_erp_kullanicisi|auth_kullanici_id'
order by tablename, policyname;


-- ============================================================
-- 4) OTEL KOLONU OLUP OTEL KONTROLÜ OLMAYAN POLİTİKALAR  → BOŞ DÖNMELİ
-- ------------------------------------------------------------
-- Tabloda otel_id kolonu VAR ama politika otel kapsamına bakmıyorsa,
-- bir otelin kullanıcısı diğerinin satırlarını görebiliyor demektir.
-- Bu, pentest tur 4 [2] ve [3]'ün bulduğu sınıfın TAMAMINI tarar.
-- ============================================================
select p.tablename, p.policyname, p.cmd
from pg_policies p
where p.schemaname = 'public'
  and exists (
    select 1 from information_schema.columns c
    where c.table_schema = 'public' and c.table_name = p.tablename
      and c.column_name = 'otel_id'
  )
  and coalesce(p.qual,'')       !~* 'auth_otel_erisim'
  and coalesce(p.with_check,'') !~* 'auth_otel_erisim'
order by p.tablename, p.policyname;


-- ============================================================
-- 5) ALT TABLOLAR — otel_id YOK, üst tabloya bağlı olması gerekenler
-- ------------------------------------------------------------
-- BOŞ DÖNMESİ BEKLENMİYOR — bu bir İNCELEME listesidir.
-- Her satır için soru: bu tablonun politikası üst tablonun oteline
-- bağlanıyor mu (exists(...) ile), yoksa yalnız modül yetkisine mi bakıyor?
-- Bar tarafında bu düzeltildi (bar_siparis_kalemleri, recete_bilesenleri);
-- satın alma ve muhasebe alt tabloları HENÜZ İNCELENMEDİ.
-- ============================================================
select p.tablename, p.policyname, p.cmd,
       (coalesce(p.qual,'') ~* 'exists') as ust_tabloya_bagli_gorunuyor,
       coalesce(p.qual,'(yok)') as using_ifadesi
from pg_policies p
where p.schemaname = 'public'
  and p.tablename in (
    'satin_alma_talep_kalemleri','ic_talep_kalemleri','teklif_kalemleri',
    'teklif_fiyatlari','siparis_kalemleri','fatura_kalemleri',
    'yevmiye_kalemleri','mal_kabul_urunleri','sayim_detaylari',
    'recete_kalemleri','koli_etiketleri','cari_hareketler',
    'banka_kasa_hareketleri','amortisman_kosustu','stok_rezervasyonlari'
  )
order by p.tablename, p.policyname;


-- ============================================================
-- 6) SECURITY DEFINER FONKSİYONLAR — hangileri kontrolsüz?
-- ------------------------------------------------------------
-- SECURITY DEFINER = RLS'i BAYPAS EDER. Kontrol fonksiyonun İÇİNDE olmak
-- zorundadır. yetki_var=false olan her satır incelenmeli.
-- Beklenen istisnalar (bilinçli, kontrolü başka yerde):
--   auth_* yardımcıları, pin_dogrula (service_role-only),
--   bar_siparis_olustur + bar_kullanilabilir_stok (masa token'ı doğrular),
--   audit_log_damgala + pin_hash_senkronize (tetikleyici),
--   talep_asama_yetkili_mi (talep_karar_ver içinden çağrılır)
-- ============================================================
select p.proname as fonksiyon,
       pg_get_function_identity_arguments(p.oid) as argumanlar,
       (pg_get_functiondef(p.oid) ~* 'auth_yetki_var')      as yetki_var,
       (pg_get_functiondef(p.oid) ~* 'auth_otel_erisim')    as otel_var,
       has_function_privilege('authenticated', p.oid, 'EXECUTE') as authenticated_cagirabilir,
       has_function_privilege('anon', p.oid, 'EXECUTE')          as anon_cagirabilir
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public' and p.prosecdef = true
order by yetki_var, p.proname;


-- ============================================================
-- 7) ANON HÂLÂ BİR ŞEYE ERİŞEBİLİYOR MU?  → BOŞ DÖNMELİ
-- ------------------------------------------------------------
-- 2026-08-09'da tüm tablo GRANT'leri anon'dan alındı (56 → 0).
-- Yeni bir tablo eklendiyse ve default privileges çalışmadıysa burada çıkar.
-- ============================================================
select table_name, privilege_type
from information_schema.role_table_grants
where grantee = 'anon' and table_schema = 'public'
order by table_name, privilege_type;


-- ============================================================
-- 8) ANON'A AÇIK FONKSİYONLAR
-- ------------------------------------------------------------
-- Yalnızca şunlar OLMALI: auth_* yardımcıları (RLS içinden çağrılır,
-- anon'a false/null döner) ve masa-token doğrulayan bar fonksiyonları
-- (bunlar da service_role üzerinden çağrılıyorsa listede olmamalı).
-- Bunların dışında bir şey çıkarsa PUBLIC-grant sızıntısıdır.
-- ============================================================
select p.proname, p.prosecdef as security_definer
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and has_function_privilege('anon', p.oid, 'EXECUTE')
order by p.prosecdef desc, p.proname;


-- ============================================================
-- SONUÇ NASIL OKUNUR
-- ============================================================
-- 1,3,4,7 BOŞ + 6'da beklenen istisnalar dışında yetki_var=false yok
--   → yetkilendirme katmanı sistematik olarak kapalı demektir.
-- 5 bir inceleme listesidir; her satırın üst tabloya bağlı olduğu
--   TEK TEK doğrulanmalı (otomatik karar verilemez).
-- 2'de beklenen liste dışında tablo varsa o modül muhtemelen bozuktur.
