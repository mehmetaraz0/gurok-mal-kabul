# PMS Faz 1 — Manuel Tarayıcı QA Kontrol Listesi

> **Üretim kullanılmaz.** Bu liste `scripts/yerel-staging.mjs` ile kurulan
> **yerel** ortamda yürütülür. Üretim PIN'i girilmez, üretime giriş kaydı
> yazılmaz, üretim verisi değişmez.

Bu liste, [[2026-09-07-pms-faz1-yayin-manifesti]] bölüm 8'deki
**MANUEL TARAYICI QA BEKLIYOR** blocker'ını kapatmak içindir.

## 1. Ortamı başlat

```bash
node scripts/yerel-staging.mjs
```

Kurulum ~1–2 dakika sürer ve şunları yapar: Docker'da PostgreSQL 17 + PostgREST
ayağa kalkar, üzerine **doğrulanmış üretim şema dökümü** ve **PMS Adım 1–4
migration'ları** uygulanır, ardından demo veri yüklenir. Ekranda şu görünmeli:

```
YEREL STAGING HAZIR  ->  http://127.0.0.1:8791
```

Tarayıcıda `http://127.0.0.1:8791` açın.

**Demo PIN kodları** (yalnız yerel — üretim PIN'i değildir):

| PIN | Kullanıcı | Otel | Yetki |
|---|---|---|---|
| `111111` | QA Tam Yetki | 810 | Tüm PMS + bar + stok |
| `222222` | QA Kısıtlı | 810 | Yalnız görüntüleme, **folyo yetkisi YOK** |
| `333333` | QA 811 Otel | 811 | Tüm PMS (çapraz otel testi için) |

Bitirince:

```bash
node scripts/yerel-staging.mjs --durdur
```

> Ortam **kalıcı değildir** (`--tmpfs`). Durdurunca tüm veri gider; yeniden
> başlatmak temiz bir kurulum verir. QA'yı yarıda bırakıp devam edecekseniz
> ortamı açık bırakın.

## 2. Kontrol listesi — 2026-09-07 İKİNCİ KOŞUM (düzeltmeler sonrası)

İlk koşumda 4 madde başarısızdı; kök neden bulunup düzeltildikten sonra
tüm liste yeniden koşuldu. `[x]` geçti · `[~]` not var.

### 2.1 Giriş ve gezinme
- [x] Yanlış PIN reddedildi · 111111 giriş · portal · Ön Büro · altı kart
- [x] Oturumsuz `pms-folio.html` giriş ekranına yönlendirdi (fail-closed)

### 2.2 Yetki
- [x] **222222 → açık uyarı:** *"Bu modülü görüntüleme yetkiniz yok…"* şeridi ve
      boş durum metni *"Görüntüleme yetkiniz yok. Burada veri olup olmadığı bu
      hesapla anlaşılamaz."* Yanıltıcı "kayıt yok" mesajı kalktı.
- [x] Yetkili kullanıcıda yanlış uyarı **çıkmıyor** (FOLIO_YETKI = tam, 2 folyo)
- [x] 333333 → yalnız 811 verisi

### 2.3 Oda tipleri
- [x] Liste yükleniyor (uyarı yok)
- [x] Boş form → **"Kod ve ad zorunlu"** mesajı görünür, modal açık kalır
- [x] Ekleme → "Eklendi", liste **anında** tazelendi
- [x] Düzenleme → "Güncellendi", ad güncellendi
- [x] Aktif/pasif → pasife alındı; Aktif filtresi gizliyor, Pasif gösteriyor
- [x] Arama ("suit") yalnız SUIT döndürdü

### 2.4 Odalar
- [x] Liste yükleniyor; durum rozetleri (Boş/Temiz, Boş/Kirli) doğru
- [x] Oda oluşturma → "Eklendi", liste tazelendi
- [x] **Mükerrer oda no reddi** → HTTP 409 `23505`, kırmızı kalıcı hata şeridi
- [x] Oda tipi seçimi (yeni DLX tipi listede)
- [x] Filtreler: temizlik, kat, oda tipi
- [x] Düzenleme (kat/temizlik) ve aktif/pasif + filtre yansıması

### 2.5 Misafir ve rezervasyon
- [x] Otel kapsamı doğru, çapraz otel seçeneği yok, gecelik fiyat okunuyor

### 2.6 Oda planı, check-in / check-out
- [x] Check-in → "Check-in yapıldı", **rack anında** "Dolu", özet "dolu 1"
- [x] Check-out → oda **boş + kirli**, geçmiş atama korundu
- [x] Yeniden yükleme **gerekmiyor** (P3 kapandı)

### 2.7 Folyo — para
- [x] Otomatik folyo, misafir adı doğru
- [x] Oda ücreti → "2 gece işlendi", bakiye **2.400,00 ₺** canlı
- [x] İkinci basış → **"İşlenecek yeni gece yok"**, bakiye değişmedi
- [x] **Tazeleme sonrası rezervasyon bilgisi duruyor, düğme pasifleşmiyor** (P2-3)
- [x] Ekstra hareket → 2.500,00 ₺
- [x] **Tahsilat çift tıklaması → TEK kayıt** (1000 ₺, aynı anahtar), bakiye 1.500,00 ₺
- [x] Bakiyeli folyoda kapat düğmesi pasif
- [x] Sıfır bakiye → kapandı, uyarı göründü, **üç form da gizlendi**

### 2.8 Bar oda devri
- [x] Dolu odaya devir → 300,00 ₺, tek hareket
- [x] Boş odaya devir → `400` reddedildi
- [x] Terminal durum: teslim → iptal `403` reddedildi (P2)
- [x] Çapraz otel sipariş oluşturma `403`

### 2.9 Ekran ve hata davranışı
- [x] 375×812: odalar, oda tipleri ve folyoda yatay taşma yok
- [x] Modal dar ekranda okunur, düğmeler erişilir
- [x] Sunucu reddi kırmızı kalıcı şeritle görünür
- [x] Temiz koşumda **yeni JS hatası yok** (0 error, 0 unhandled rejection)
- [x] Service worker: **gerçek Chrome'da kayıt BAŞARILI** — bkz. bölüm 5

## 3. Sonuç

**PMS BROWSER QA: PASSED.** İlk koşumun 4 bulgusu da kapandı; kalan P0/P1/P2
tarayıcı sorunu yok.

## 4. Ortamın sınırları — neyi kanıtlamaz

Bu ortam gerçek uygulamayı gerçek şema ve gerçek RLS ile çalıştırır, ama:

- **PIN doğrulaması gerçek değildir.** `/functions/v1/pin-girisi` yerel bir
  stub'dır; PIN karması, deneme sınırı ve gerçek Edge Function davranışı
  **sınanmaz**. Üretim PIN akışı ayrıca doğrulanmalıdır.
- **Diğer Edge Function'lar yoktur** (menü yayınlama, QR sipariş köprüsü).
- **Supabase Auth (GoTrue) yoktur**; JWT yerel sır ile imzalanır. Token
  yenileme ve oturum süresi davranışı üretimdekiyle birebir değildir.
- Veri geçicidir; performans ve gerçek veri hacmi hakkında bilgi vermez.

## İlgili

- [[2026-09-07-pms-faz1-yayin-manifesti]]
- [[URETIM-YAYIN-RUNBOOK]]
- `scripts/yerel-staging.mjs` · `scripts/yerel-staging-overlay.sql`

## 5. Service worker bulgusu (kanıt)

**ÇÖZÜLDÜ — ürün hatası değil.** Tarayıcı panelinde kayıt
`TypeError: Failed to register a ServiceWorker` ile başarısız oluyordu.
**Gerçek Chrome penceresinde aynı sayfada kayıt BAŞARILI oldu**
(`navigator.serviceWorker.register('sw.js')` → başarılı, `isSecureContext=true`).
Yani bulgu tamamen tarayıcı panelinin sandbox'ından kaynaklanıyor.
Panelde ölçülen destekleyici kanıtlar:

| Kontrol | Sonuç |
|---|---|
| `GET /sw.js` | **200 OK** |
| MIME tipi | `text/javascript; charset=utf-8` (doğru) |
| `window.isSecureContext` | **true** (127.0.0.1 güvenli bağlam sayılır) |
| Kapsam | `/` — `sw.js` kök dizinde, kapsam sorunu yok |

Gerçek Chrome doğrulaması yapıldığı için madde **kapandı**; ürün tarafında
service worker sorunu yoktur.
