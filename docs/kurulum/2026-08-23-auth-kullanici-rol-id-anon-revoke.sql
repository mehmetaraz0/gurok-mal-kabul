-- ============================================================================
-- 2026-08-23 BULGU DÜZELTMESİ: auth_kullanici_rol_id — anon EXECUTE kapatma
-- ============================================================================
-- Bulgu kaynağı: davranışsal RLS sondajı (anon key, salt-okunur).
-- Belirti: GET /rest/v1/rpc/auth_kullanici_rol_id → 42501 hatası FONKSİYON
-- İÇİNDEN geliyor (içerdeki kullanicilar okumasında) = fonksiyon anon tarafından
-- ÇAĞRILABİLİYOR. Kardeşleri auth_erp_kullanicisi / giris_kaydi_ekle bilinçli
-- revoke edilmişken bu fonksiyonda PUBLIC/anon EXECUTE kalmış.
--
-- Risk: düşük (auth.uid() boşken veri dönmüyor) ama tutarsızlık + bilgi ifşası
-- yüzeyi. Aşağıdaki blok SQL Editor'de (postgres rolüyle) çalıştırılır.
--
-- GERİ DÖNÜŞ: grant'lar idempotent değildir; geri almak için
--   GRANT EXECUTE ON FUNCTION public.auth_kullanici_rol_id() TO PUBLIC;
-- (önerilmez — bulgunun tekrar açılmasına neden olur)
-- ============================================================================

-- [1] ÖNCE MEVCUT DURUMU KAYDET (çalıştırmadan önce ayrıca çalıştırın ve çıktıyı saklayın)
select p.proname, p.prosecdef as security_definer,
       coalesce(array_to_string(p.proacl::text[], ', '), 'NULL (= varsayılan PUBLIC)') as acl
from pg_proc p join pg_namespace n on n.oid = p.pronamespace
where n.nspname='public' and p.proname = 'auth_kullanici_rol_id';

-- [2] DÜZELTME
REVOKE EXECUTE ON FUNCTION public.auth_kullanici_rol_id() FROM anon;
REVOKE EXECUTE ON FUNCTION public.auth_kullanici_rol_id() FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION public.auth_kullanici_rol_id() TO authenticated;

-- NOT: Fonksiyon RLS politikaları içinde çağrılıyorsa authenticated grant'ı
-- zorunludur (politika gövdesi sorgulayan kullanıcının yetkileriyle çalışır).
-- SECURITY DEFINER ise ve SADECE politika içinden çağrılıyorsa authenticated
-- grant satırı kaldırılabilir; önce şu ile kullanım yerlerini görün:
--   select polname, polrelid::regclass from pg_policy
--   where pg_get_expr(polqual, polrelid) like '%auth_kullanici_rol_id%'
--      or pg_get_expr(polwithcheck, polrelid) like '%auth_kullanici_rol_id%';

-- [3] POSTGREST SCHEMA CACHE TAZELE (grant değişiklikleri anında yansımasa da garanti olsun)
notify pgrst, 'reload schema';

-- ============================================================================
-- DOĞRULAMA (düzeltmeden SONRA çalıştırılacak kontroller)
-- ============================================================================

-- [4] ACL kontrolü — beklenen: acl'de anon/PUBLIC yok, authenticated var
select p.proname,
       coalesce(array_to_string(p.proacl::text[], ', '), 'NULL (= varsayılan PUBLIC)') as acl
from pg_proc p join pg_namespace n on n.oid = p.pronamespace
where n.nspname='public' and p.proname = 'auth_kullanici_rol_id';

-- [5] Davranışsal teyit — ANON key ile (SQL Editor DEĞİL, terminalden):
--   curl -s "https://xwytofysmgqtqjzkplfi.supabase.co/rest/v1/rpc/auth_kullanici_rol_id" \
--     -H "apikey: <ANON_KEY>" -H "Authorization: Bearer <ANON_KEY>"
-- BEKLENEN: {"code":"PGRST202", ... "no matches were found in the schema cache"}
-- (42501 DEĞİL — 42501 hâlâ geliyorsa revoke tutmamıştır, [2]'yi tekrarlayın)

-- [6] Regresyon teyidi — oturum açmış bir ERP kullanıcısıyla portalda bir modül
-- açın; modül listesi ve yetki matrisi normal yükleniyorsa authenticated yolu
-- sağlam demektir.
