# Faz 0 — Parolasız JWT üretiminin doğrulanması (izole test)

**Amaç:** [3] planının (düz metin PIN → hash + Edge Function ile JWT üretimi) dayandığı
tek teknik varsayımı — Supabase Admin API ile, bir kullanıcının parolasını hiç bilmeden,
gerçek ve geçerli bir Auth session (access_token + refresh_token) üretilebildiğini —
gerçek kullanıcılara veya `kullanicilar` tablosuna dokunmadan, **tek bir atılabilir test
kullanıcısıyla** doğrulamak.

**Bu doğrulama geçmeden Faz 1 (SQL) canlıya alınmaz, Faz 2/3/4'e hiç geçilmez.**

Bu rehber sizin (kullanıcı) Supabase Dashboard'da/CLI'de takip edeceğiniz adımları
içerir — ben (Claude) bu adımları sizin adınıza çalıştırmıyorum; service-role key ve
Supabase CLI oturumu gerektirdiği için bunlar sizin elinizde kalmalı.

---

## Ön koşullar

- Supabase Dashboard'a ana proje (`xwytofysmgqtqjzkplfi.supabase.co`) için erişim.
- Supabase CLI kurulu ve bu projeye login/link olmuş (`supabase login`, `supabase link --project-ref xwytofysmgqtqjzkplfi`).
- Ana projenin **service_role key**'i elinizde (Dashboard → Settings → API → `service_role` — bu anahtarı hiçbir dosyaya/commit'e yazmayın, yalnızca Supabase secret olarak saklanacak).

## 0) Ön kontrol — pgcrypto hangi şemada?

Faz 1 SQL'i `crypt()`/`gen_salt()` (pgcrypto) kullanıyor. Supabase projelerinde bu
extension bazen `public` yerine `extensions` şemasına kurulu olabilir — bu, Faz 1'deki
`pin_dogrula()` fonksiyonunun `search_path` ayarını etkiler. Şimdi kontrol edin (SQL
Editor'de çalıştırın, hiçbir şeyi değiştirmez):

```sql
select extname, extnamespace::regnamespace as sema
from pg_extension
where extname = 'pgcrypto';
```

- Sonuç boşsa: pgcrypto hiç kurulu değil — Faz 1 SQL'i `create extension if not exists pgcrypto;` ile kuracak (varsayılan olarak `public`'e kurulur, ekstra bir şey yapmanıza gerek yok).
- Sonuç `sema = public` ise: Faz 1 SQL'deki `set search_path = public` yeterli, değişiklik gerekmez.
- Sonuç `sema = extensions` (veya başka bir şema) ise: **bana bildirin** — Faz 1 SQL'indeki `pin_dogrula()` fonksiyonunun `search_path`'ini `public, extensions` (veya ilgili şema) olacak şekilde güncelleyeceğim, aksi halde fonksiyon `crypt`'i bulamaz ve hata verir.

## 1) İzole test Edge Function'ını deploy edin

Kod hazır: `docs/kurulum/ana-proje/pin-girisi-test-faz0/index.ts`

Bu fonksiyon **gerçek `kullanicilar` tablosuna hiç dokunmaz** — yalnızca verdiğiniz
e-posta adresine Admin API ile magic-link üretip session'a çevirir ve sonucu JSON
olarak döner.

```bash
supabase functions deploy pin-girisi-test-faz0 \
  --project-ref xwytofysmgqtqjzkplfi \
  --no-verify-jwt
```

(`--no-verify-jwt`: bu fonksiyon kendi içinde yetkilendirme yapmıyor, test amaçlı;
gerçek [3] fonksiyonunda bu bayrak KULLANILMAYACAK.)

Secret'ları ayarlayın:

```bash
supabase secrets set TEST_SB_URL=https://xwytofysmgqtqjzkplfi.supabase.co --project-ref xwytofysmgqtqjzkplfi
supabase secrets set TEST_SERVICE_KEY=<service_role_key> --project-ref xwytofysmgqtqjzkplfi
```

## 2) Atılabilir test kullanıcısı oluşturun

**Gerçek bir kullanıcı/hesap KULLANMAYIN.** Supabase Dashboard → Authentication →
Users → "Add user" ile, gerçek verilerle çakışmayan bir e-posta ile yeni bir kullanıcı
oluşturun, örn:

```
faz0-test-XXXX@gurok.internal      (XXXX yerine rastgele bir sayı, herhangi bir parola)
```

`public.kullanicilar` tablosunda bu e-postaya karşılık gelen bir satır **oluşturmanıza
gerek yok** — test fonksiyonu doğrudan Supabase Auth üzerinde çalışıyor, ERP tablosuyla
hiç etkileşmiyor.

## 3) Test fonksiyonunu çağırın

```bash
curl -X POST "https://xwytofysmgqtqjzkplfi.supabase.co/functions/v1/pin-girisi-test-faz0" \
  -H "Content-Type: application/json" \
  -d '{"email":"faz0-test-XXXX@gurok.internal"}'
```

### Beklenen BAŞARILI yanıt:

```json
{
  "ok": true,
  "access_token_var_mi": true,
  "refresh_token_var_mi": true,
  "expires_in": 3600,
  "auth_user_dogrulama_status": 200,
  "dogrulanan_kullanici_email": "faz0-test-XXXX@gurok.internal",
  "dogrulanan_kullanici_id": "<test kullanıcısının auth uid'i>"
}
```

`ok:true` **ve** `dogrulanan_kullanici_email`'in gönderdiğiniz e-postayla eşleştiğini
görmelisiniz — bu, üretilen `access_token`'ın gerçekten geçerli, gerçek bir Supabase
Auth session'ı olduğunun kanıtı (parola hiç kullanılmadan).

### Başarısız/eksik yanıt durumunda:

Fonksiyon her adımda (`generateLink`, `verifyOtp`) hata veya beklenmeyen alan adı
durumunda `ok:false` + `adim` + `mesaj` + (varsa) `raw` (ham SDK yanıtı) döner. Bu
durumda:
1. `raw` alanını inceleyin — `hashed_token` yerine farklı bir alan adı (ör. `token_hash`
   veya `action_link` içinden parse edilmesi gereken bir token) kullanıyor olabilir.
   Bana `raw` çıktısını iletin, kodu buna göre düzeltirim.
2. `mesaj` "insufficient_scope" veya benzeri bir yetki hatasıysa: kullandığınız key'in
   gerçekten `service_role` olduğunu (anon key değil) teyit edin.

## 4) Sonuç ne olursa olsun temizlik

- Test Edge Function'ını Dashboard'dan **silin**: `supabase functions delete pin-girisi-test-faz0 --project-ref xwytofysmgqtqjzkplfi`
- `TEST_SB_URL` / `TEST_SERVICE_KEY` secret'larını silin.
- Test kullanıcısını (`faz0-test-XXXX@gurok.internal`) Authentication → Users'tan silin.

## 5) Bana bildirin

- ✅ Başarılı oldu, `dogrulanan_kullanici_email` doğru geldi → Faz 0 GEÇTİ, Faz 1 SQL'i
  canlıya almanız için onay verebilirim (siz çalıştıracaksınız), sonra Faz 2/3/4
  tasarımının somut kod/SQL'ini yazmaya başlarım.
- ⚠️ `pgcrypto` `extensions` şemasında çıktıysa → Faz 1 SQL'i güncellerim.
- ❌ Başarısız oldu → `raw`/`mesaj` çıktısını paylaşın, ya kodu düzeltir ya da (magic-link
  yaklaşımı bu Supabase sürümünde çalışmıyorsa) [3] planındaki Seçenek 2/3'e döneriz.
