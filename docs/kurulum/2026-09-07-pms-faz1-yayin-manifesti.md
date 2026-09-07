# PMS Faz 1 — Yayın Manifesti (Release Candidate)

> **Bu belge yayın izni DEĞİLDİR.** Amacı, canlıya çıkarken **hangi dosyanın hangi
> sürümünün** uygulanacağını tereddütsüz sabitlemektir. Uygulama yalnızca
> kullanıcının açık `CANLIYA UYGULA` onayı ile başlar
> ([[URETIM-YAYIN-RUNBOOK]] bölüm 0 — üretim yazma dondurması).

- **Manifest tarihi:** 2026-09-07 (final)
- **Karar:** `PMS RELEASE CANDIDATE: GO`
- **Git HEAD:** `d9e8bc5` — *chore(pms): yerel staging ve tarayici qa altyapisi*
- **origin/main:** `0740cfb` — HEAD 17 commit önde, 0 geride. **Push yapılmadı.**
- **Üretime uygulandı mı:** **HAYIR.** Dört migration da aday olarak repoda duruyor.
  Uygulama yalnız açık `CANLIYA UYGULA` onayıyla başlar.

### Kapılar

| Kapı | Durum | Kanıt |
|---|---|---|
| Otomatik regresyon | ✅ | bölüm 6 |
| Sabotaj koşumu | ✅ 6/6 | bölüm 6 |
| **PMS BROWSER QA** | ✅ **PASSED** | bölüm 8 |
| **PRODUCTION PREFLIGHT** | ✅ **PASSED** 19/19 | bölüm 3 |
| Migration sürümü sabitlendi | ✅ | bölüm 1–2 (SHA256) |
| Geri alma planı | ✅ | bölüm 5 |

## 1. Adayın sabitlenmesi

Aday, **bu manifesti içeren commit** ile sabitlenmiştir
(`chore(pms): faz 1 release candidate dogrulama altyapisi`). O commit'ten önceki
HEAD `1e97e2f` idi; manifestle birlikte gelen değişiklikler şunlardır:

| Dosya | Durum |
|---|---|
| `docs/kurulum/2026-09-06-pms-faz1-adim4-folio.sql` | değiştirildi (P2 kapanışı — bar terminal durum kilidi) |
| `scripts/pms-faz1-adim4-testleri.sql` | değiştirildi (T3 yeniden yazıldı) |
| `docs/kurulum/2026-09-07-pms-yayin-oncesi-preflight.sql` | yeni |
| `scripts/pms-faz1-yayin-dogrulama.mjs` | yeni |
| `docs/kurulum/2026-09-07-pms-faz1-yayin-manifesti.md` | yeni (bu dosya) |

> **Sabitleme neyle yapılır:** commit hash'i ile değil, **bölüm 2'deki SHA256
> değerleriyle**. Bir manifest kendi commit hash'ini içeremez (hash'i yazmak
> hash'i değiştirir). Bu yüzden yayın anında doğrulanacak şey dosya içerik
> hash'leridir; commit yalnızca bu manifestin hangi ağaçta üretildiğini söyler.
> Yayın kaydına **her ikisi de** yazılır — 6 Eylül'deki sahipsiz Phase 0
> uygulamasının tekrarlanmaması için.

## 2. Uygulanacak dosyalar ve SHA256

Sıra **bağlayıcıdır**. Her dosya, uygulamadan hemen önce hash'i ile doğrulanır:

```bash
sha256sum docs/kurulum/2026-09-06-pms-faz1-*.sql
```

| # | Dosya | SHA256 |
|---|---|---|
| 1 | `2026-09-06-pms-faz1-oda-tipleri-odalar.sql` | `9c30126139a4d42213ccc40acb949c4f9f40a434e070d797a8ef33c298975047` |
| 2 | `2026-09-06-pms-faz1-adim2-misafir-rezervasyon.sql` | `ba4f9ad026f73fa0c619ddc1aa23550e82865885344478133bd36065445df2cd` |
| 3 | `2026-09-06-pms-faz1-adim3-checkin-checkout.sql` | `3954dcd1f94d6f3d5b918bad18aa93366a67c4355ac66139475fae15c931e74f` |
| 4 | `2026-09-06-pms-faz1-adim4-folio.sql` | `bc9b320359bfaea4eaccb7c49d6ebb80b0fce2820de0b1473955fa91b11c71ea` |

Yardımcı dosyalar (uygulanmaz, doğrulama içindir):

| Dosya | SHA256 | Rol |
|---|---|---|
| `2026-09-06-sema-dokumu.sql` | `93810ba662d5517365273e0b36a59b5f9c53b283b4d314b6146d319f154a9956` | Üretim taban kopyası |
| `2026-09-07-pms-yayin-oncesi-preflight.sql` | `3bb9b326e4a2f52037f44c19dfbe4ce28f07782db7643a59bca180186e17e5e7` | Yayın öncesi salt-okuma preflight |

> **Hash doğrulaması (2026-09-07, final):** dört migration da manifest ilk
> yazıldığından beri **değişmedi**; SHA256'lar yeniden hesaplandı ve yukarıdaki
> değerlerle birebir aynı çıktı. Sonraki commit'ler (`7f15e8c`, `d9e8bc5`)
> yalnız ekran dosyalarına ve QA altyapısına dokundu.
>
> **Adım 4 için `81f71db` sürümü GEÇERSİZDİR.** O sürümde finansal append-only,
> ödeme idempotency anahtarı, kapanış kilidi ve bar terminal durum kilidi yoktur.
> Geçerli içerik yukarıdaki hash'tir.

## 3. Üretim taban parmak izi

Aday, aşağıdaki taban üzerinde test edilmiştir. Yayın anında üretim bu tabandan
saparsa **yayın durdurulur**:

| Ölçü | Beklenen |
|---|---|
| `public` tablo sayısı | 66 |
| `public` politika sayısı | 193 |
| Kısıtlayıcı politika | 31 |
| Phase 0 fonksiyon gövdesi (`md5(prosrc)`) | 26/26 eşleşme |
| `phase0_private` şeması + `islem_audit()` | var |
| `anon` tablo hakkı | 0 |
| `search_path` pinsiz SECURITY DEFINER | 0 |

Sayı doğrulaması: `2026-09-07-pms-yayin-oncesi-preflight.sql`
Gövde doğrulaması: `2026-09-06-staging-esitlik-dogrulama.sql`

### Preflight sonucu — 2026-09-07, ÜRETİMDE ÇALIŞTIRILDI (salt-okuma)

**19/19 kontrol geçti. Sıfır drift.**

| Grup | Sonuç |
|---|---|
| 1.1–1.7 PMS nesneleri üretimde yok | hepsi 0 ✅ — **sahipsiz uygulama yok**, isim/kolon/tetikleyici çakışması yok |
| 2.1–2.6 Adım 1 önkoşulları | 4 / 4 / 1 / 1 / 2 / 3 ✅ |
| 3.1 tablo · 3.2 politika · 3.3 kısıtlayıcı | 66 / 193 / 31 ✅ — üretim, testlerin koştuğu şemayla **aynı** |
| 3.4 RLS kapalı tablo · 3.5 pinsiz SECURITY DEFINER · 3.6 anon hakkı | hepsi 0 ✅ |

**Bilgi (karar kriteri değil):** `erp_islem_audit` satır sayısı **0**. Denetim izi
üretimde hâlâ hiç kayıt üretmedi. Bu, yayın için ölçüm avantajıdır: sayaç 0'dan
başladığı için her adımın smoke testinde artması, denetim izinin canlıda
çalıştığının **ilk somut kanıtı** olacaktır (runbook 2.7).

**Sürüm farkı, sapma değil:** üretim PostgreSQL **17.6**, test konteyneri 17.11.
Bilinen ve zararsız; fonksiyon karşılaştırması zaten sürümden bağımsız
`md5(prosrc)` ile yapılır (`md5(pg_get_functiondef())` sürüme duyarlıdır).

## 4. Yayın sırası ve her adımın kapıları

Genel kural: **bir adımın post-check'i geçmeden sonraki adım başlamaz.**
Tüm adımlar aynı yayın penceresinde, aynı kişi tarafından, runbook bölüm 1'deki
12 zorunlu alan doldurularak yapılır.

### Adım 0 — Yayın öncesi (tek sefer)

1. Kullanıcının açık `CANLIYA UYGULA` onayı alınır ve kaydedilir.
2. Kod donduruldu: HEAD hash'i kaydedilir, çalışma ağacı temiz olmalı.
3. **Yedek alınır** (runbook 2.4). Yedek **doğrulanmadan** hiçbir migration başlamaz.
4. `2026-09-07-pms-yayin-oncesi-preflight.sql` çalıştırılır; çıktı kayda yapıştırılır.
5. `2026-09-06-staging-esitlik-dogrulama.sql` çalıştırılır; SAPMA olmamalı.

**STOP kriteri:** preflight'ta tek bir SAPMA, ya da yedeğin doğrulanamaması.

### Adım 1 — Oda tipleri + odalar

| | |
|---|---|
| Dosya | `2026-09-06-pms-faz1-oda-tipleri-odalar.sql` |
| Hash | `9c30126…975047` |
| Pre-check | preflight 1.1–1.7 hepsi 0; 2.1–2.6 beklenen |
| Post-check | Migration'ın kendi doğrulama bloğu hatasız bitti; `pms_oda_tipleri` + `pms_odalar` var; her ikisinde RLS açık ve kısıtlayıcı otel tabanı var |
| Smoke test | `pms-oda-tipleri.html`: bir oda tipi **kaydet**, listede gör — kayıt yazıldı VE RLS altında geri okunabiliyor demektir. *Ekranın açılması smoke test değildir.* **DÜZELTME (2026-09-07): denetim izi sayacı bu adımda ARTMAZ** ve artması beklenmemelidir — Adım 1 `phase0_islem_audit` tetikleyicisi bağlamaz; oda tipleri/odalar bilinçli olarak kapsam dışıdır. |
| STOP | Doğrulama bloğu hata verirse; smoke test'te kayıt yazılamazsa |
| Geri alma | `2026-09-06-pms-faz1-oda-tipleri-odalar.sql` içindeki geri alma bloğu (dosya sonu, yorumlu) |

### Adım 2 — Misafir, kimlik, rezervasyon, oda ataması

| | |
|---|---|
| Dosya | `2026-09-06-pms-faz1-adim2-misafir-rezervasyon.sql` |
| Hash | `ba4f9ad…5df2cd` |
| Pre-check | Adım 1 post-check geçti |
| Post-check | Doğrulama bloğu hatasız; `pms_rezervasyon_no_seq` üzerinde `authenticated` yalnız USAGE; EXCLUDE kısıtı kurulu |
| Smoke test | Bir misafir kaydet ve listede gör. **DÜZELTME (2026-09-07): denetim izi sayacı bu adımda da ARTMAZ** — kişisel veri tabloları KVKK gereği kapsam dışıdır; rezervasyon/atama Adım 3 ile kapsama girer. Çakışma reddi yapısal olarak `exclude_kisit` ile doğrulanır. **Rezervasyon kaydı bu adımda YAPILAMAZ:** ekran `gecelik_fiyat` alanını gönderir, o kolon Adım 4 ile eklenir. Rezervasyon akışı Adım 4 sonrasına aittir. |
| STOP | Çakışma reddedilmiyorsa (aşırı satış koruması çalışmıyor demektir) |
| Geri alma | Dosya sonundaki geri alma bloğu |

### Adım 3 — Oda planı, check-in / check-out

| | |
|---|---|
| Dosya | `2026-09-06-pms-faz1-adim3-checkin-checkout.sql` |
| Hash | `3954dcd…31e74f` |
| Pre-check | Adım 2 post-check geçti |
| Post-check | Doğrulama bloğu hatasız; `pms_check_in`/`pms_check_out` var; tutarlılık tetikleyicileri kurulu |
| Smoke test | Temiz odaya check-in → oda `dolu`; check-out → oda `bos`+`kirli`; **kirli odaya check-in reddediliyor** |
| STOP | Kirli odaya check-in kabul edilirse; oda durumu beklenen geçişi yapmazsa |
| Geri alma | Dosya sonundaki geri alma bloğu |

### Adım 4 — Folyo

| | |
|---|---|
| Dosya | `2026-09-06-pms-faz1-adim4-folio.sql` |
| Hash | `bc9b320…c71ea` |
| Pre-check | Adım 3 post-check geçti |
| Post-check | Doğrulama bloğu hatasız — 3 idempotency index'i **benzersiz**; append-only tetikleyicileri var; finansal tablolarda `authenticated` için update/delete ayrıcalığı **yok**; denetim izi DELETE'i kapsıyor; bar durum kilidi var |
| Smoke test | Rezervasyona gecelik fiyat gir → check-in → **oda ücretini işle** → ikinci kez işle ve **0 gece eklendiğini** gör → tahsilat gir → bakiye sıfırlanınca folyoyu kapat → kapalı folyoya yazmanın reddedildiğini gör; audit sayacı arttı |
| STOP | İkinci işleme mükerrer borç üretirse; kapalı folyoya yazma kabul edilirse |
| Geri alma | Dosya sonundaki geri alma bloğu |

### Adım 5 — Yayın sonrası

1. Yayın sonrası parmak izi (runbook 2.8): tablo/politika sayıları yeni taban olarak kaydedilir.
2. `2026-09-06-staging-esitlik-dogrulama.sql` **bayatlar** — PMS nesneleri eklendiği için yeni taban çıkarılmalı.
3. Runbook bölüm 4'e yayın kaydı yazılır (12 zorunlu alan, smoke test kanıtı dahil).

## 5. Geri alma / özellik kapatma

**Tercih sırası:**

1. **Özellik kapatma (en hızlı, veri kaybı yok).** `moduller` tablosunda ilgili
   PMS modülü satırının `aktif = false` yapılması. `auth_yetki_var()` modülün
   aktif olmasını şart koştuğu için **tüm** RLS politikaları anında kapanır;
   ekranlar da menüden düşer. Şema ve veri yerinde kalır.
   *Bu, kısmi başarısızlıkta ilk hamledir.*

   > **Adım 4'e özel uyarı — doğrulandı, varsayım değil:** `pms_folio` modülünü
   > kapatmak **bar köprüsünü durdurmaz.** `pms_bar_folio_koprusu()` SECURITY
   > DEFINER'dır ve `auth_yetki_var()` çağırmaz; RLS'i de atlar. Modül kapalıyken
   > bar teslimatları folyolara borç yazmaya **devam eder**, ama kimse folyoyu
   > göremez — görünmez borç birikir. Adım 4'ü gerçekten durdurmak gerekiyorsa
   > modülü kapatmak yetmez, önce köprü tetikleyicisi düşürülür:
   > `drop trigger if exists pms_bar_folio_koprusu on public.bar_siparisleri;`
   > (`pms_bar_durum_kilit` bırakılabilir; o yalnız durum makinesini korur.)
2. **Adım bazlı geri alma.** Her migration dosyasının sonunda yorumlu geri alma
   bloğu vardır. **Ters sırada** uygulanır: Adım 4 → 3 → 2 → 1.
   Adım 4'ün geri alması bar köprüsü ve durum kilidi tetikleyicilerini de düşürür.
3. **Yedekten dönüş.** Yalnız 1 ve 2 yetmezse. Adım 0'daki yedek kullanılır.

> **Finansal veri uyarısı:** Adım 4 uygulandıktan sonra folyoya **gerçek para
> hareketi** girildiyse, Adım 4'ün geri alınması bu kayıtları siler. O noktadan
> sonra geri alma değil, **özellik kapatma** tercih edilir. Karar sınırı:
> `select count(*) from public.pms_folio_odemeler` > 0 ise geri alma yapılmaz.

## 6. Test sonuçları (2026-09-07, yerel)

| Koşum | Sonuç |
|---|---|
| `check.mjs` | geçti (15 .js + 58 .html) |
| `pms-faz1-testleri.mjs` | geçti |
| `pms-faz1-adim2-testleri.mjs` | geçti |
| `pms-faz1-adim3-testleri.mjs` | geçti |
| `pms-faz1-adim4-testleri.mjs` | geçti (T1–T11 + 2 eşzamanlılık aşaması) |
| `pms-faz1-yayin-dogrulama.mjs` | geçti (zincir sırası + idempotency + uçtan uca) |
| `phase0-database-tests.mjs` | geçti |
| `phase0-security.test.mjs` | 6/6 |
| `git diff --check` | temiz |
| Sabotaj koşumu | **6/6 yakalandı** |
| Tarayıcı QA (yerel staging) | **PASSED** (bölüm 8) |
| Üretim salt-okuma preflight | **PASSED** 19/19 (bölüm 3) |

Tüm veritabanı testleri, tek kullanımlık PostgreSQL 17 konteynerinde
**doğrulanmış üretim şema dökümü** üzerinde koşar; üretime bağlanmaz.

## 7. Bilinen açıklar

**Blocker kalmadı.** Üçü de kapandı:

| # | Eski seviye | Durum |
|---|---|---|
| 1 | Blocker | ✅ **Kapandı** — tarayıcı QA yerel staging'de koşuldu, PASSED (bölüm 8) |
| 2 | Blocker | ✅ **Kapandı** — üretim preflight'ı çalıştırıldı, 19/19 (bölüm 3) |
| 3 | Blocker | ✅ **Kapandı** — aday commit edildi ve SHA256 ile sabitlendi (bölüm 1–2) |

Kalan riskler yalnız **P3**; hiçbiri yayını durdurmaz:

| # | Seviye | Konu |
|---|---|---|
| 4 | P3 | Teslim sonrası düzeltme, folyoya elle `duzeltme` satırı gerektirir (bar siparişinin durumu geri alınamaz — bilinçli karar) |
| 5 | P3 | `erp_islem_audit` üretimde 0; denetim izi canlıda hiç kanıtlanmadı. **Yayın smoke testleri bunu kanıtlayacak** |
| 6 | P3 | `supabase_admin` varsayılan ACL'i yeni nesnelerde `anon`'a hak veriyor (Supabase destek konusu). Migration'lar bunu tablo bazında geri alıyor; doğrulama blokları sınıyor |
| 7 | P3 | Yayın sonrası eşitlik tabanı bayatlayacak; PMS nesneleri eklendiği için yeni taban çıkarılmalı (Adım 5) |
| 8 | P3 | Gerçek PIN akışı ve diğer Edge Function'lar yerel staging'de sınanmadı (stub); üretimde ilk girişte doğrulanmalı |
| 9 | P3 | **Ön yüz, Adım 1–4'ün TAMAMINA bağlıdır.** Rezervasyon ekranı `gecelik_fiyat` gönderir (Adım 4). Ön yüzü dört adım tamamlanmadan yayınlamak rezervasyon kaydını kırar — 2026-09-07 yayınında ölçüldü. |

## 8. Tarayıcı QA durumu

**PMS BROWSER QA: PASSED** — 2026-09-07, `scripts/yerel-staging.mjs` ile kurulan
yerel ortamda (Docker PostgreSQL 17 + PostgREST + doğrulanmış üretim şema dökümü
+ Adım 1–4). Ayrıntılı liste: [[2026-09-07-tarayici-qa-kontrol-listesi]].

**Ağ güvenliği:** koşum boyunca `supabase.co`'ya **0 istek**; tüm trafik
`127.0.0.1`. Üretim PIN'i kullanılmadı, üretime giriş kaydı yazılmadı.

Doğrulanan kritik akışlar: giriş + otel kapsamı · oda tipleri (ekleme/düzenleme/
aktif-pasif/arama/filtre/doğrulama) · odalar (mükerrer oda no reddi HTTP 409
dahil) · misafir · rezervasyon · check-in · room rack · folyo (oda ücreti,
**ikinci basışta mükerrer yok**, ekstra, **tahsilat çift tıklamasında tek kayıt**,
bakiyeli kapanış reddi, sıfır bakiyeli kapanış, kapalı folyoya yazma reddi) ·
bar devri (boş oda reddi, **terminal durum reddi**, çapraz otel reddi) ·
bakiye kalmışken check-out · dar ekran (375×812, yatay taşma yok).

### İlk koşumda bulunan 4 sorun — hepsi düzeltildi (`7f15e8c`)

| Bulgu | Kök neden | Durum |
|---|---|---|
| Oda tipleri ve odalar ekranları açılışta boş, "Sunucuya ulaşılamadı" | `SATIR_TAVANI` sabiti onu kullanan `yukle()` çağrısından sonra tanımlıydı (temporal dead zone) | ✅ |
| Folyo modali tazelemeden sonra bozuluyor, oda ücreti düğmesi kalıcı pasif | `yukle()` `ACIK`'ı ham özet satırıyla değiştirip `rez` bağlamını düşürüyordu | ✅ |
| Yetkisiz kullanıcı yanıltıcı "kayıt yok" görüyor | RLS hata değil 0 satır döndürür; ekran yalnız HTTP hatasına bakıyordu | ✅ mevcut yetki motoruna soruluyor, fail-closed |
| Doğrulama mesajları hiç görünmüyor + hiçbir ekran işlem sonrası tazelenmiyor | **Altı PMS ekranında da `#toast` elementi yoktu**; her `toast()` `TypeError` fırlatıyor, `try/catch` yutuyor ve hemen ardındaki `await yukle()` çalışmıyordu | ✅ element + stil eklendi |

Son madde P3 "otomatik tazeleme" maddesinin de kök nedeniydi; ekran başına yama
gerekmeden kapandı.

**Service worker:** panelde kayıt başarısızdı; **gerçek Chrome penceresinde
başarılı** olduğu doğrulandı. Panel sandbox'ı kaynaklı, **ürün hatası değil**.

## 9. İlgili

- [[URETIM-YAYIN-RUNBOOK]] — yayın disiplini, 12 zorunlu kayıt alanı
- `docs/kurulum/2026-09-07-pms-yayin-oncesi-preflight.sql`
- `docs/kurulum/2026-09-06-staging-esitlik-dogrulama.sql`
- `scripts/pms-faz1-yayin-dogrulama.mjs`
