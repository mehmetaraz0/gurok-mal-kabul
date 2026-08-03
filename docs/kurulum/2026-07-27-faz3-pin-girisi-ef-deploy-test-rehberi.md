# Faz 3 / Adım 1 — Kalıcı `pin-girisi` Edge Function'ını deploy edip bağımsız test etme

**REVİZE (v2):** İlk testte "Kullanıcının Auth hesabı yok" hatası çıktı — 10 aktif
kullanıcıdan 4'ünün (İSMAİL KUZU, FATİH ATEŞ, WEWEEW, WWWWWW) `auth_user_id`'si boş.
Kod tarafında doğrulandı: canlı akış (`supabaseAuthKoprusu`, main'deki `index.html`)
`auth_user_id` boşsa lazy-signUp yapıyor ama sonrasındaki `PATCH` sonucunu HİÇ
kontrol etmiyor — yani bu 4 kullanıcı için bir Auth hesabı zaten var olabilir
(özellikle aktif kullanılan WWWWWW için çok olası) ama DB'ye linklenmemiş. EF artık
bunu ele alıyor: `auth_user_id` boşsa önce yeni hesap açmayı dener, "zaten kayıtlı"
hatası alırsa mevcut hesabı e-postadan bulup **service-role ile** (RLS'e takılmadan)
linkler. **Fonksiyonu yeniden deploy edip aşağıdaki 2. adımı bu 4 kullanıcıdan
en az ikisiyle (özellikle WWWWWW) tekrar test edin.**

**Bu adım index.html'e DOKUNMAZ.** Fonksiyonu canlıya alıp yalnızca kendi başına
(Dashboard/PowerShell'den) test edeceksiniz — giriş ekranı hâlâ eski yolu (
`pin_ile_kullanici_ara` + `supabaseAuthKoprusu`) kullanmaya devam ediyor. Cutover
(index.html'in bu fonksiyonu kullanmaya başlaması) ayrı, siz onay verince yapılacak.

Kod: `docs/kurulum/ana-proje/pin-girisi/index.ts` — Faz 0'da doğruladığınız
`generateLink`→`verifyOtp` mekanizmasının, gerçek `pin_dogrula` RPC'sine bağlı
kalıcı hali.

## 1) (Yeniden) Deploy — "Via Editor" (Faz 0 ile aynı akış)

Fonksiyon zaten bir kere deploy edildiyse: Dashboard → **Edge Functions** →
`pin-girisi`'e tıklayın → kod düzenleme ekranına girin (genelde "Edit function"
veya doğrudan kod sekmesi) → kutunun içini tamamen silip güncel kodu yapıştırın →
tekrar **Deploy**. İlk kez deploy ediyorsanız:

1. Dashboard → **Edge Functions** → **"Deploy a new function"** → **"Via Editor"**.
2. İsim: `pin-girisi` (aynen bu şekilde).
3. Kod kutusundaki örneği tamamen silip `docs/kurulum/ana-proje/pin-girisi/index.ts`
   dosyasının **tüm içeriğini** yapıştırın. **Kutuya SADECE bu kodu yapıştırın** —
   Faz 0'da yaşadığınız bundle hatası riskine karşı, bu rehberdeki hiçbir metni
   koda karıştırmayın.
4. **"Enforce JWT Verification" seçeneğini KAPALI bırakın.** Bu kritik — bu
   fonksiyon henüz giriş yapmamış (anonim) kullanıcılar tarafından çağrılacak;
   platform seviyesinde JWT şartı konursa hiç çağrılamaz.
5. **Deploy.**

**Secret eklemenize gerek yok** — kod `SUPABASE_URL`/`SUPABASE_SERVICE_ROLE_KEY`'i
otomatik okuyor (Faz 0'daki gibi).

## 2) Bağımsız test edin (index.html'den TAMAMEN ayrı)

**Önemli güvenlik notu:** Bu testi **kendi hesabınızın (yönetici) gerçek 6 haneli
PIN'i ile** yapın, rastgele bir kullanıcıyla değil — çünkü başarılı bir çağrı o
kullanıcı için **gerçek, geçerli bir oturum** üretir. Dönen `access_token`/
`refresh_token` değerlerini ekran görüntüsü/chat'te tam olarak paylaşmayın (hassas).

PowerShell (Başlat → "powershell"):

```powershell
$body = @{ pin = "<KENDI_GERCEK_6_HANELI_PININIZ>" } | ConvertTo-Json
Invoke-RestMethod -Method Post -Uri "https://xwytofysmgqtqjzkplfi.supabase.co/functions/v1/pin-girisi" -ContentType "application/json" -Body $body
```

### Beklenen BAŞARILI yanıt (özet, gerçek token'ları paylaşmayın):

```json
{
  "ok": true,
  "kullanici": { "ad": "...", "rol": "yonetici", ... },
  "access_token": "<uzun bir JWT>",
  "refresh_token": "<uzun bir metin>",
  "expires_in": 3600
}
```

`kullanici.ad` alanının gerçekten sizin adınız olduğunu görün — bu, doğru
kullanıcı için doğru session üretildiğinin kanıtı.

### Yanlış PIN testi:

```powershell
$body = @{ pin = "000000" } | ConvertTo-Json
Invoke-RestMethod -Method Post -Uri "https://xwytofysmgqtqjzkplfi.supabase.co/functions/v1/pin-girisi" -ContentType "application/json" -Body $body
```
Beklenen: `{"ok": false, "mesaj": "Hatalı PIN"}` — başka hiçbir bilgi yok.

### Bir hata/eksik alan görürseniz — `debug:true` ile ayrıntı isteyin:

```powershell
$body = @{ pin = "<PIN>"; debug = $true } | ConvertTo-Json
Invoke-RestMethod -Method Post -Uri "https://xwytofysmgqtqjzkplfi.supabase.co/functions/v1/pin-girisi" -ContentType "application/json" -Body $body
```
Bu, `mesaj` + `adim` (hangi aşamada) + `hata`/`raw` (ham SDK yanıtı) döner.
Sonucu bana iletin, gerekirse kodu düzeltirim. **`index.html` hiçbir zaman
`debug:true` göndermeyecek** — bu yalnızca sizin elle test etmeniz için.

### Rate-limit testi (opsiyonel, Faz 1'de zaten SQL üzerinden test edildi):

Yanlış PIN ile arka arkaya 11 kez çağırırsanız, 11. çağrıda da aynı genel
`{"ok":false,"mesaj":"Hatalı PIN"}` dönmeli (rate-limit'e takılmış olsa da
yanlış-PIN'den ayırt edilemiyor — bu kasıtlı, oracle oluşturmamak için).

### `auth_user_id` boş olan kullanıcılarla test (kritik — bu revizyonun asıl amacı):

Aynı testi (`pin` + isteğe bağlı `debug:true`) İSMAİL KUZU, FATİH ATEŞ, WEWEEW,
**özellikle WWWWWW** için tekrarlayın (her biri kendi gerçek PIN'iyle). `debug:true`
gönderirseniz başarılı yanıtta artık bir `saglamaAdimlari` alanı da göreceksiniz:

```json
{ "ok": true, "kullanici": {...}, "access_token": "...", "...": "...",
  "saglamaAdimlari": { "yol": "yeni-hesap-olusturuldu", "patchOk": true } }
```
veya
```json
"saglamaAdimlari": { "yol": "mevcut-hesap-linklendi", "createUserHatasi": "...", "patchOk": true }
```

- `yol: "yeni-hesap-olusturuldu"` → bu kullanıcı için gerçekten hiç Auth hesabı
  yokmuş, yeni açıldı.
- `yol: "mevcut-hesap-linklendi"` → tahmin doğruydu: Auth hesabı zaten varmış
  (eski PATCH bug'ı yüzünden linksizmiş), şimdi bulunup bağlandı.
- `patchOk: false` görürseniz → `kullanicilar.auth_user_id` DB'ye yazılamadı
  (session yine de üretilmiş olabilir ama bir sonraki girişte aynı işlem tekrar
  çalışır) — bana bildirin, sebebini araştırırım.

Test sonrası, WWWWWW gibi gerçek/aktif hesaplarda `auth_user_id`'nin artık dolu
olduğunu SQL ile de doğrulayabilirsiniz:
```sql
select ad, auth_user_id from public.kullanicilar where aktif = true order by ad;
```

## 3) Sonucu bana bildirin

- ✅ Doğru PIN → doğru kullanıcı + gerçek token'lar (hem bağlı hem daha önce
  bağlı OLMAYAN kullanıcılarda), yanlış PIN → genel hata: Faz 3/Adım 1 GEÇTİ.
  index.html cutover diff'i zaten hazır (ayrı olarak sunuyorum) — siz "pencere
  uygun, şimdi" demeden **merge/deploy edilmeyecek**.
- ❌ Hata → `debug:true` çıktısını paylaşın.
- ℹ️ WEWEEW/WWWWWW'nin gerçek mi test hesabı mı olduğu ayrı bir karar — şimdilik
  dokunmuyoruz, yalnızca giriş üretebildiklerini doğruluyoruz.
