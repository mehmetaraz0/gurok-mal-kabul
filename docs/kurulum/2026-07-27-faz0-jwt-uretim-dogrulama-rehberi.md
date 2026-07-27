# Faz 0 — Parolasız JWT üretiminin doğrulanması (izole test)

**Amaç:** [3] planının (düz metin PIN → hash + Edge Function ile JWT üretimi) dayandığı
tek teknik varsayımı — Supabase Admin API ile, bir kullanıcının parolasını hiç bilmeden,
gerçek ve geçerli bir Auth session (access_token + refresh_token) üretilebildiğini —
gerçek kullanıcılara veya `kullanicilar` tablosuna dokunmadan, **tek bir atılabilir test
kullanıcısıyla** doğrulamak.

**Bu doğrulama geçmeden Faz 1 (SQL) canlıya alınmaz, Faz 2/3/4'e hiç geçilmez.**

Bu rehber sizin (kullanıcı) Supabase Dashboard'da (tarayıcıda, fare ile) takip
edeceğiniz adımları içerir — ben (Claude) bu adımları sizin adınıza çalıştırmıyorum;
service-role key gerektirdiği için bu adımlar sizin elinizde kalmalı.

---

## Ön koşullar

- Supabase Dashboard'a (https://supabase.com/dashboard) tarayıcıdan giriş, ana proje seçili.
- **Supabase CLI KULLANILMIYOR.** Bar fonksiyonlarında (hyper-api/smooth-service/
  rapid-handler) kullandığınız **aynı "Via Editor" akışı** — Dashboard'da kod kutusuna
  yapıştır, deploy et.
- **Secret eklemenize gerek YOK** (bu, önceki sürümden fark — aşağıda açıklandı):
  Supabase her Edge Function'a `SUPABASE_URL` ve `SUPABASE_SERVICE_ROLE_KEY`'i zaten
  otomatik olarak veriyor, bu fonksiyon doğrudan onları okuyor.
- **ÇOK ÖNEMLİ (daha önce yaşadığınız sorun):** "Via Editor" kutusuna **YALNIZCA**
  `index.ts` dosyasının kod içeriğini yapıştırın. Bu rehberdeki açıklama/talimat
  metinlerini, başlıkları vb. **asla** koda karıştırmayın — karışırsa bundle hatası
  verir ve deploy eski sürümde takılı kalır.

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

## 1) İzole test Edge Function'ını "Via Editor" ile oluşturun (bar fonksiyonlarıyla aynı akış)

1. Dashboard → sol menü **Edge Functions**.
2. **"Deploy a new function"** → **"Via Editor"** seçeneğini seçin (bar fonksiyonlarında
   kullandığınızın aynısı).
3. Fonksiyon adı: `pin-girisi-test-faz0` (aynen bu şekilde yazın, tire ile).
4. Açılan kod kutusundaki hazır örnek kodu **tamamen silin**, yerine bilgisayarınızdaki
   `docs/kurulum/ana-proje/pin-girisi-test-faz0/index.ts` dosyasını bir metin editöründe
   açıp **tüm içeriğini** kopyalayıp yapıştırın.
   **Kutuya SADECE bu kodu yapıştırın — bu rehberdeki hiçbir açıklama/başlık metnini
   koda karıştırmayın** (karışırsa bundle hatası verip eski sürümde takılı kalır).
5. "Enforce JWT Verification" (veya "Verify JWT") gibi bir seçenek/anahtar görürseniz
   **KAPALI** bırakın — bu test fonksiyonu yetkilendirmeyi kendi içinde yapıyor, dışarıdan
   ayrıca bir giriş JWT'si gerektirmemeli.
6. **Deploy** butonuna basın. Birkaç saniye sürer, "Deployed"/yeşil onay göreceksiniz.

**Secret eklemenize gerek YOK** — Supabase bu fonksiyona `SUPABASE_URL` ve
`SUPABASE_SERVICE_ROLE_KEY`'i kendiliğinden veriyor, kod bunları doğrudan okuyor.
(Bir önceki sürümde `TEST_SB_URL`/`TEST_SERVICE_KEY` secret'ı eklemenizi istemiştim —
buna artık gerek yok, kodu buna göre güncelledim.)

## 2) Atılabilir test kullanıcısı oluşturun

**Gerçek bir kullanıcı/hesap KULLANMAYIN.** Soldaki menüden **Authentication → Users**'a
gidin, **"Add user"** (sağ üstte) → **"Create new user"** ile, gerçek verilerle
çakışmayan bir e-posta ile yeni bir kullanıcı oluşturun, örn:

```
faz0-test-1234@gurok.internal
```

(Parola alanına ne yazarsanız yazın, önemi yok — hatta rastgele bir şey yazın, biz bu
parolayı hiç kullanmayacağız zaten, tam da bunu test ediyoruz.)

`public.kullanicilar` tablosunda bu e-postaya karşılık gelen bir satır **oluşturmanıza
gerek yok** — test fonksiyonu doğrudan Supabase Auth üzerinde çalışıyor, ERP tablosuyla
hiç etkileşmiyor.

## 3) Test fonksiyonunu çağırın

**A) Önce Dashboard'da deneyin (varsa en kolay yol):** Edge Functions → az önce
oluşturduğunuz `pin-girisi-test-faz0` fonksiyonuna tıklayın. Sayfada genelde bir
**"Invoke"/"Test"** alanı bulunur; burada bir JSON kutusuna şunu yazıp gönder/send
tuşuna basabilirsiniz:
```json
{"email":"faz0-test-1234@gurok.internal"}
```
(`faz0-test-1234` kısmını 2. adımda oluşturduğunuz gerçek test e-postasıyla değiştirin.)

**B) Böyle bir test alanı göremezseniz — Windows'ta PowerShell ile (kurulum gerekmez):**
Başlat menüsüne "powershell" yazıp Enter'a basın, açılan pencereye aşağıdaki **3 satırı
olduğu gibi kopyalayıp yapıştırın**, yalnızca `faz0-test-1234@gurok.internal` kısmını
kendi test e-postanızla değiştirin, sonra Enter'a basın:

```powershell
$body = @{ email = "faz0-test-1234@gurok.internal" } | ConvertTo-Json
Invoke-RestMethod -Method Post -Uri "https://xwytofysmgqtqjzkplfi.supabase.co/functions/v1/pin-girisi-test-faz0" -ContentType "application/json" -Body $body
```

Ekrana dökülen sonucu (yukarıdaki JSON) aynen bana gönderin.

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

## 4) Sonuç ne olursa olsun temizlik (Dashboard'da)

- **Edge Functions** → `pin-girisi-test-faz0` fonksiyonunun yanındaki menüden (üç nokta
  `⋯` veya çöp kutusu ikonu) **Delete/Sil**. (Secret eklemediğimiz için silinecek başka
  bir şey yok.)
- **Authentication → Users** → `faz0-test-1234@gurok.internal` test kullanıcısını
  bulup silin.

## 5) Bana bildirin

- ✅ Başarılı oldu, `dogrulanan_kullanici_email` doğru geldi → Faz 0 GEÇTİ, Faz 1 SQL'i
  canlıya almanız için onay verebilirim (siz çalıştıracaksınız), sonra Faz 2/3/4
  tasarımının somut kod/SQL'ini yazmaya başlarım.
- ⚠️ `pgcrypto` `extensions` şemasında çıktıysa → Faz 1 SQL'i güncellerim.
- ❌ Başarısız oldu → `raw`/`mesaj` çıktısını paylaşın, ya kodu düzeltir ya da (magic-link
  yaklaşımı bu Supabase sürümünde çalışmıyorsa) [3] planındaki Seçenek 2/3'e döneriz.
