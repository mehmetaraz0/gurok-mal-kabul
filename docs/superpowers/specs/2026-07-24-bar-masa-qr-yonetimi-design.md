# Bar QR + Masa Token Yönetimi — Tasarım (v1)

**Tarih:** 2026-07-24
**Amaç:** Personelin ana ERP portalından (F&B Bar alanı) masa oluşturup her masa için opak token üretmesi, o masanın QR kodunu (müşteri menü sayfasına yönlendiren) ekranda görüp yazdırması, ve masayı kapatıp açabilmesi. Şu an tokenlar elle SQL ile ekleniyor.

## Kapsam (kullanıcı onaylı)

- **Teker teker (v1):** bir masa ekle → token otomatik → QR göster/yazdır → listele → kapat/aç. Toplu ekleme/toplu baskı kapsam DIŞI (ileride).
- **Erişim:** Ana portalda (index.html) mevcut soluk "F&B Bar" kartı canlandırılır; içinden "Masa/QR Yönetimi" (ve mevcut "Sipariş Kuyruğu") açılır.

## Kısıtlar / Bağlam

- Masa tokenları CUSTOMER projesinde (ref `udjpcsjifgdzvfflezaa`) `masa_tokenlari` tablosunda; anon'a KAPALI. Şema: token(pk)/otel_id/depo_id/masa_adi/aktif.
- Personel sayfası service_role tutamaz → token CRUD için Edge Function köprüsü.
- **Token gizli** (QR'ın kimlik bilgisi). Token listeleme/oluşturma endpoint'i AÇIK OLAMAZ → Edge Function personel girişini (JWT) doğrular.
- Giriş: ana projede gerçek Supabase Auth JWT üretiliyor; `oturumAccessTokenGetir()` (auth-guard.js) döndürür. Ana anon key = `SB_KEY` (supabase-config.js).
- Mevcut Edge Function'lar: `hyper-api` (sipariş), `smooth-service` (menü yayın). Secret'lar: MAIN_SB_URL, MAIN_SERVICE_KEY, CUSTOMER_SB_URL, CUSTOMER_SERVICE_KEY.
- QR client-side, kendi kütüphanemizle (token 3. tarafa gitmez).

## Bileşenler

### 1. Edge Function `masa-yonetim` (customer projesi, JWT korumalı)
- Girdi: `{ jwt, action, ... }`.
- **Yetki kontrolü (önce):** `createClient(MAIN_SB_URL, MAIN_ANON_KEY, {global headers Authorization: Bearer jwt}).rpc('auth_yetki_var', {p_modul_kod:'bar_siparis_yonetimi', p_min_seviye:'kayit'})` → `true` değilse `{ok:false, mesaj:'Yetki yok'}` (403 anlamı). Geçersiz/expired JWT → RPC false/hata → reddet.
- **Aksiyonlar (service_role, customer):**
  - `liste` → `masa_tokenlari` tüm satırlar (token dahil — yalnız yetkili personel görür).
  - `ekle` → `{otel_id, depo_id, masa_adi}`; token = `crypto.randomUUID()`; insert; dönüş yeni satır.
  - `durum` → `{token, aktif}`; ilgili masanın aktif alanını günceller.
- **Yeni secret:** `MAIN_ANON_KEY` (public, Dashboard'dan eklenir).
- Deploy: Dashboard → Via Editor (ad ne olursa olsun sabitlenir; endpoint controller'a bildirilir).

### 2. Sayfa `bar-masa-yonetimi.html` (ana proje)
- Script sırası diğer bar sayfaları gibi: auth-guard → supabase-config → nav-drawer → otel-config → ortak.js → theme.css → qr-mini.js.
- `requireRole(CU, ['mutfak','bar','yonetici'])`; `YETKI_HARITASI=await kullaniciYetkileriGetir()`; `yazabilir()` = `['kayit','tam'].includes(YETKI_HARITASI['bar_siparis_yonetimi'])`.
- **Ekle formu:** otel (810/811 açılır), depo (otelden ön-dolu, `merkeziDepoKodu` / düzenlenebilir), masa adı. "Ekle" → Edge Function `ekle`.
- **Liste:** masalar (ad, otel, aktif rozet). Her satır: "QR Göster" (modal: QR + Yazdır butonu) ve "Kapat"/"Aç" (durum).
- Tüm çağrılar `oturumAccessTokenGetir()` ile JWT'yi Edge Function'a gönderir. Tüm DB metni `escapeHtml()`.
- QR şunu kodlar: `https://mehmetaraz0.github.io/gurok-mal-kabul/bar-menu.html?t=<token>` (sabit BASE, ileride custom domain).

### 3. QR kütüphanesi `qr-mini.js` (repo kökü)
- Dışa bağımlılığı olmayan, gömülü pure-JS QR üreteci (MIT qrcode-generator). `qrUret(elId, metin)` benzeri basit API; canvas/table çıktısı.

### 4. Navigasyon (index.html + moduller)
- index.html portal kartlarında "F&B Bar" alanını canlandır: "Masa/QR Yönetimi" → `bar-masa-yonetimi.html`, "Sipariş Kuyruğu" → `bar-siparis-kuyrugu.html`. Yetki: `bar_siparis_yonetimi`.
- (Portal kart render'ı yetki/moduller'e bağlıysa ona uy; değilse mevcut kart desenini izle.)

## Hata Yönetimi
- JWT yok/expired → Edge Function reddeder; sayfa "Oturum doğrulanamadı, tekrar giriş yapın" gösterir.
- Edge Function hata → `{ok:false, mesaj}`; sayfa toast'ta gösterir.
- Depo boş / masa adı boş → sayfa client-side engeller.

## Test (uçtan uca)
1. Sayfadan masa ekle (810, Havuz Bar 1) → Edge Function `ekle` → müşteri `masa_tokenlari`'nda token belirir (`masa_oteli_getir(token)` → '810').
2. "QR Göster" → QR `bar-menu.html?t=<token>` URL'sini kodlar (dekode ile doğrula).
3. "Kapat" → `masa_oteli_getir(token)` artık null (aktif=false).
4. Yetkisiz/JWT'siz çağrı → Edge Function reddeder (403).
5. İzolasyon: sayfa ana proje ref'i içerir (ana proje sayfası — normal); Edge Function anon'a token sızdırmaz (JWT şart).

## Kapsam Dışı
- Toplu masa ekleme + toplu QR baskı sayfası.
- Masa düzenleme (ad değiştirme) — v1'de kapat+yeni ekle.
- QR'ın custom domain (menu.alibeyclub.com) — BASE sabit, DNS ayrı iş.
