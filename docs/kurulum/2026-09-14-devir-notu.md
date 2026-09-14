# Devir Notu — 13–14 Eylül 2026

Bu dosya, PMS Faz 2 yayını ve ardından gelen işler için **devir notudur**.
Amacı: bu oturumu görmemiş birinin (ajan ya da insan) durumu tek dosyadan
kavraması. Ayrıntılar `URETIM-YAYIN-RUNBOOK.md` §8–§11'de; bu not onların
haritasıdır.

## 1. Bugün ne oldu (sırayla)

### PMS Faz 2 — Kat Hizmetleri canlıya alındı (13 Eylül)

Onay: kullanıcı `CANLIYA UYGULA` dedi (ortam demo, aktif operasyon yok).
Sıra mimarinin §16'sıdır ve aynen uygulandı: **migration → rol yetkileri →
arayüz → modülü açma.**

| Adım | Sonuç |
|---|---|
| Kod dondurma | `45b162e`; LF yayın baytlarının SHA-256'ları plan §0.1 ile birebir |
| Yayın başlangıcı preflight | 50 GEÇTİ / **0 SAPMA** / E1 = 0 |
| Adım 1 migration | 36,7 sn; dosyanın kendi doğrulama blokları geçti (**T0 = 16:08**) |
| Adım 2 migration | 6,8 sn; `odalar=t`, `definer_pinli=2`, `anon_veya_service=0` |
| Uygulama sonrası preflight | **tam 19 SAPMA** (beklenen liste ile birebir) |
| Yetkiler | 9 rol satırı (4 `tam`, 1 `kayit`, 4 `goruntule`); modül kapalı kaldı |
| Arayüz | `origin/main` `d0bd734` → `45b162e`; altı dosyanın canlı SHA-256'sı yayın commit'iyle aynı |
| Modülü açma | `aktif = t` · **kesinti 16:08→16:53 = 45 dk** |

Duman testleri (üretimde gerçek kayıtlarla): **D1** denetim döngüsü — işi yapan
(Sistem Test) ile denetleyen (MEHMET ARAZ) farklı kullanıcı; **D2** check-out
sonrası `cikis_temizligi` görevi kendiliğinden doğdu; **D3** Faz 2 dışı
tabloların denetim satırları `islem_detayi` taşımıyor (regresyon yok); **D4**
`goruntule` kullanıcı listeyi görüyor ama komut düğmesi görmüyor.

### Otel seçici (13 Eylül, aynı gün yayınlandı)

Yayında bulunan kusur: kat hizmetleri ekranı otel kapsamını
`kullanicilar.otel_id`'den alıyordu ve otel seçicisi yoktu; `tum_oteller=true`
ama `otel_id` boş olan kullanıcı ekranı **hiç** kullanamıyordu.

Çözüm: çapraz otel hakkı `auth_tum_oteller()` RPC'siyle **sunucudan
fail-closed** okunuyor, hakkı olan kullanıcı oteli başlıktan seçiyor. Seçim
yalnız tarayıcıda (`hk-otel:<kullanici_id>`) durur; şema değişmedi. Oda
planındaki bağlantı artık `#otel=<id>&oda=<no>` taşıyor. Otel atamalı
kullanıcının davranışı **aynı kaldı**. Canlı: `e0b986e`.

### Yedekleme zinciri (13–14 Eylül)

Üç adımda kapandı:

1. **E-5 (13 Eylül):** üretim yedeği alındı ve izole kopyada doğrulandı —
   satır sayıları, FK bütünlüğü, tutarlılık, uygulama erişimi.
2. **Auth kapsamı (13 Eylül):** yedek `auth` şemasını da kapsıyor; provaya
   yedinci aşama eklendi ve **13/13 kimliğin yedekten geldiği** ölçüldü.
   Yani proje tümden kaybında giriş de kurtarılabilir.
3. **Şifreleme (14 Eylül):** veri ve auth yedekleri diskte artık şifreli
   (OpenSSL CMS, AES-256 + RSA-4096). Prova şifreli dosyayı çözerek koşuyor;
   anahtar yoksa **çıkış kodu 1** ile duruyor.

## 2. Şu anki durum

- `origin/main` = `abc6ab0` (ve sonrası). Faz 2, otel seçici, yedekleme
  araçları ve kayıtların tamamı main'de.
- Üretimde `pms_housekeeping` modülü **açık**, yetki matrisi kurulu.
- Yedekler: `C:\Users\USER\ERP-Yedek\` — `*-veri-yedegi.sql.enc` ve
  `*-auth-yedegi.sql.enc` **şifreli**; sayaçlar ve auth şema yapısı düz.
- Şifreleme sertifikası repoda: `docs/kurulum/yedek-anahtari.pem`
  (seri `565AEC4177F14F11D468BD27DFDB22F20C31DC7F`).
- **Gizli anahtar repoda ve yedek klasöründe DEĞİL**:
  `C:\Users\USER\OneDrive\Gurok-Yedek-Anahtari\`. Parolası ayrı yerde durur.
- Hazırlık kilidi (`scripts/hazirlik-kilidi.mjs`) 11 dosya için yeşil.

## 3. Açık maddeler

| Madde | Durum |
|---|---|
| Anahtar parolasının kağıda yazılması | **Kullanıcıda.** Anahtar OneDrive'da; parola yalnız akılda kalırsa zincir orada kopar |
| Aylık yedek + tatbikat ritmi | Önerildi, karara bağlanmadı |
| `otel_id = '810'` (MEHMET ARAZ, Sistem Test) | Kalıcı bırakıldı (kullanıcı kararı); seçici geldiği için artık gerekli değil |
| Çapraz otelli kullanıcının oda planını görmesi | İsteniyorsa ilgili role `pms_oda` yetkisi ayrıca verilmeli |
| Anahtar rotasyonu / eski yedeklerin yeniden şifrelenmesi | Kapsam dışı bırakıldı |

## 4. Bu ortamın tuzakları (tekrar yaşamayın)

1. **PowerShell ≠ Git Bash.** Git'in `gpg`'si MSYS yapısıdır ve PowerShell'den
   çalışmaz ("No Keybox daemon running"). Şifreleme bu yüzden OpenSSL'e taşındı.
2. **OpenSSL'in parola istemi bu terminalde okumuyor**
   (`UI routines:UI_process:processing error`). Parola `Read-Host
   -AsSecureString` ile alınıp `-passin/-passout env:` ile verilir.
3. **Bir sırrın tek kopyası `%TEMP%`'e konmaz.** İlk üretilen gizli anahtar
   orada durdu ve kayboldu; kayıp sıfırdı çünkü henüz şifrelenmiş yedek yoktu.
4. **Joker desenli temizlik kendi dosyasını silebilir.** `*-auth-*.sql` deseni,
   etiketi `auth` ile biten bir koşuda veri yedeğini sildi. Sonek eşleştirin.
5. **PowerShell'de parametre adı yerel değişkenle çakışır.** `dokum-al.ps1`'e
   eklenen `-Veri` anahtarı `$veri` değişkenini bozdu; kilitli bir betiğe
   anahtar eklendiğinde betik baştan sona bir kez koşturulmalı.
6. **Yayından sonra yeni taban dökümü alın.** Prova, eski şemaya yeni veriyi
   yüklemez ve doğru biçimde başarısız olur.
7. **Tarayıcı otomasyonu yayın kanalı değildir.** SQL Editor'e yapıştırma
   yöntemi pencere ortasında çöktü; migration'lar psql ile
   `--single-transaction` altında, dosya özeti doğrulanarak uygulandı.

## 5. Nereye bakmalı

| Konu | Dosya |
|---|---|
| Faz 2 yayın kaydı | `docs/kurulum/URETIM-YAYIN-RUNBOOK.md` §8 |
| Otel seçici yayını | §9 |
| Auth yedeği | §10 |
| Yedek şifreleme + tatbikat komutları | §11 |
| Yayın kararı belgesi (tarihsel) | `docs/kurulum/2026-09-11-pms-faz2-yayin-plani.md` |
| Tasarımlar | `docs/superpowers/specs/2026-09-13-*.md` |
| Uygulama planları | `docs/superpowers/plans/2026-09-13-*.md` |
| Yedek alma | `docs/kurulum/yedek-ve-sayac-al.ps1` |
| Geri yükleme provası | `scripts/pms-yedek-geri-yukleme-provasi.mjs` |
| Hazırlık kilidi | `scripts/hazirlik-kilidi.mjs` |

## 6. Değişmeyen kural

Üretime hiçbir şey, kullanıcı **`CANLIYA UYGULA`** demeden uygulanmaz:
migration, DDL, veri yazma, GRANT/REVOKE, deploy, push-to-production, Supabase
şema değişikliği. Yerel ve izole ortamlar bu kuralın dışındadır.
