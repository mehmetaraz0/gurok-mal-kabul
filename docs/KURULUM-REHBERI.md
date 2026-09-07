# Yeni Müşteri Kurulum Rehberi

Bu rehber, sistemi yeni bir otel/turizm grubuna sıfırdan kurmak için izlenecek
sıralı adımları tanımlar. Her adım bir öncekine bağımlıdır — sırayı bozmayın.

## Ön Koşullar
- Yeni bir Supabase hesabı/organizasyonu
- Bu reponun bir kopyası (fork veya klon)
- Statik hosting (GitHub Pages veya eşdeğeri)

## Phase 0 Security Gate (2026-09-05)

`01-sema-dokumu.sql` is a historical bootstrap dump (31 Jul 2026), NOT the
current security baseline. Do not deploy it alone or replay dated SQL files in
filename order.

### Taban dökümleri — hangisi ne zaman

İki taban vardır ve **ikisi de korunur**. Yeni kurulumlar POST-PMS tabanı
kullanır; eski dosya tarihsel kanıttır, silinmez.

| Taban | Dosya | Ölçüler | Ne zaman |
|---|---|---|---|
| **POST-PMS-FAZ1** (güncel) | `2026-09-07-post-pms-faz1-sema-dokumu.sql` | **75 tablo · 234 politika · 40 kısıtlayıcı · 28 kapsam fonksiyonu** | Yeni kurulum, staging, drift kontrolü |
| PMS öncesi (tarihsel) | `2026-09-06-sema-dokumu.sql` | 66 tablo · 193 politika · 31 kısıtlayıcı · 26 fonksiyon | Yalnız arşiv/karşılaştırma |

Her tabanın kendi eşitlik doğrulayıcısı vardır ve **eşleştirilerek** kullanılır:

| Taban | Eşitlik doğrulayıcısı |
|---|---|
| POST-PMS-FAZ1 | `2026-09-07-post-pms-faz1-esitlik-dogrulama.sql` |
| PMS öncesi | `2026-09-06-staging-esitlik-dogrulama.sql` |

> **Yanlış eşleştirme sessiz alarm üretir.** PMS sonrası bir veritabanını PMS
> öncesi doğrulayıcıyla sınarsanız SAPMA raporlanır — bu gerçek bir sorun
> değil, tabanın bayat olmasıdır. `dokum-dogrula.mjs` ikinci argüman
> verilmezse **eski** dosyayı kullanır; yeni taban için argümanı vermek
> zorunludur.

Her iki döküm de üretim parmak iziyle doğrulandı: sıfır sapma. POST-PMS tabanı
2026-09-07'de üretimde çalıştırılan 28 kontrollük salt-okuma parmak iziyle
(`2026-09-07-post-pms-faz1-uretim-parmakizi.sql`) 28/28 eşleşti.

Eski dökümün neden kullanılamayacağı ölçülerek belgelendi
(`2026-09-06-staging-branch-kurulum.md`, bölüm 2): 26 fonksiyonun yalnız 2'si
eşleşiyordu, sıfır `GRANT` satırı vardı ve 5 tabloda RLS kapalıydı.

Her yeni döküm, kullanılmadan önce doğrulanmalıdır:

```bash
# POST-PMS-FAZ1 taban (guncel):
node scripts/dokum-dogrula.mjs \\
  docs/kurulum/2026-09-07-post-pms-faz1-sema-dokumu.sql \\
  docs/kurulum/2026-09-07-post-pms-faz1-esitlik-dogrulama.sql

# PMS oncesi taban (tarihsel):
node scripts/dokum-dogrula.mjs docs/kurulum/2026-09-06-sema-dokumu.sql
```

For an existing MAIN ERP project only:

1. Run `docs/kurulum/2026-09-05-phase0-preflight.sql` as the database owner.
   It is read-only. Retain definitions, owners, policies, grants, views and
   fingerprints privately for comparison/recovery. Do not commit credentials,
   PINs, JWTs or production records. Inspect any DDL literals before sharing.
2. Compare the effective catalog with the Phase 0 scope and prerequisites.
   Later active-user and grant remediation supersedes the original dump;
   a file's date is not proof that it was applied. Resolve unknown policies,
   overloads, declaration shapes, missing tables/keys, legacy relationships,
   and unregistered/ambiguous bar depots BEFORE applying the migration.
3. In a staging clone, apply `docs/kurulum/2026-09-05-phase0-hardening.sql` as
   one transaction. It establishes canonical authorization helpers, restrictive
   hotel boundaries and protected server audit without replacing business RPC
   bodies with old versions. Unsupported definitions abort; do not remove the
   gates simply to force deployment.
4. Run the local contract tests and the real ERP staging checklist documented
   in `D:\ERP-Bilgi-Haritasi\PHASE0-HARDENING.md` ([[PHASE0-HARDENING]]).
   Synthetic tests do NOT certify hosted Supabase or actual ERP workflows.
5. Production application is a separate, explicit approval in a maintenance
   window. No script in Phase 0 deploys to Supabase automatically.

Local verification (Docker Desktop must be running for database tests):

```powershell
node scripts/check.mjs
node --test scripts/phase0-security.test.mjs
node scripts/phase0-database-tests.mjs
```

The database runner accepts no connection URL. It creates and removes its own
network-isolated PostgreSQL 17 container with synthetic data. Reservation
constraint tables exist only inside that disposable fixture, not in public PMS.

Rollback: failed application rolls back the transaction. After a successful
application, stop writes, preserve `erp_islem_audit`, and review the captured
pre-change DDL/ACLs before restoring anything. Do not restore broad anonymous
grants or permissive `USING(true)` policies on a live application. If safe
recovery cannot be established, keep affected writes disabled and forward-fix.

## Adımlar

1. **Supabase projesi oluştur.** [supabase.com](https://supabase.com) → New Project.
   Bölge ve güçlü bir DB şifresi seçin.

2. **Şemayı kur.** Supabase SQL Editor'de
   `docs/kurulum/2026-09-06-sema-dokumu.sql` dosyasının tamamını çalıştırın
   (tablolar, RLS politikaları, fonksiyonlar, izinler, Phase 0 sertleştirmesi).
   Eski `01-sema-dokumu.sql` dosyasını KULLANMAYIN — bayat ve güvenlik
   açısından eksiktir; yukarıdaki Phase 0 Security Gate bölümüne bakın.

3. **Referans veriyi yükle.** Aynı editörde `docs/kurulum/02-referans-veri.sql`
   dosyasını çalıştırın (roller, modüller, yetki matrisi — müşteri verisi içermez).

4. **Repoyu klonlayın** (veya fork'layın) ve yerel bir kopyada çalışın.

5. **`supabase-config.js`'i güncelleyin.** Yeni projenin URL'i ve anon (public)
   anahtarı ile (Settings → API). Service-role anahtarını ASLA bu dosyaya yazmayın.

6. **`otel-config.js`'i üretin.** `yeni-musteri-kurulum.html`'i tarayıcıda açın,
   bölüm 2'deki formu müşterinin otel bilgileriyle doldurun, üretilen içeriği
   repo kökündeki `otel-config.js`'e yapıştırıp kaydedin ve commit edin.

7. **İlk yöneticiyi oluşturun.** Aynı sayfada bölüm 1'e yeni projenin URL'i +
   service-role anahtarını girin (yalnız bellekte tutulur), bölüm 3'ten ilk
   yönetici kullanıcısını ekleyin. PIN tam 6 hane olmalıdır (giriş ekranı
   6 haneli PIN bekler).

8. **Deploy edin.** GitHub Pages (veya eşdeğeri) üzerinden yayınlayın; ilk
   yöneticiyle giriş yapıp portalın açıldığını doğrulayın.

9. **Modülleri ayarlayın.** `yetki-yonetimi.html`'de, müşterinin satın almadığı
   modüllerin başlığına tıklayarak pasif yapın (🔒). Pasif modül hem menülerden
   kalkar hem RLS seviyesinde kapanır.

10. **Ürün/tedarikçi kataloğunu doldurun.** Müşterinin kendi verisiyle —
    ilgili sayfalardaki Excel toplu içe aktarma özelliğini kullanın
    (`gurok_veritabani.js` içeriği de müşteri kataloğuyla değiştirilmelidir).

## Kurulum Sonrası Güvenlik (zorunlu)

- `migrate-to-supabase.html` ve `yeni-musteri-kurulum.html` dosyalarını
  production deploy'undan KALDIRIN (2026-07-21 güvenlik denetimi önerisi) —
  ikisi de service-role anahtarı kabul eden tek seferlik araçlardır.
- Service-role anahtarını hiçbir dosyaya/nota yazmadığınızı doğrulayın.

### Yeni migration yazacaksanız

2026-09-08'den itibaren yeni migration'lar bir ACL/grant standardına tabidir:

| | |
|---|---|
| Standart | `docs/kurulum/MIGRATION-GUVENLIK-STANDARDI.md` |
| Şablon | `docs/kurulum/SABLON-yeni-migration.sql` |
| Denetim | `node scripts/migration-guvenlik-kontrol.mjs` |

Denetim `node scripts/check.mjs` zincirine bağlıdır. Canlıya uygulanmış
tarihî migration'lar (PMS Adım 1–4 dâhil) **yeniden yazılmaz** ve varsayılan
kapsamda değildir.

Üretimin fiili ACL durumu ayrı ölçülür:
`docs/kurulum/2026-09-07-varsayilan-acl-uyari-kontrolu.sql` (salt-okuma).
