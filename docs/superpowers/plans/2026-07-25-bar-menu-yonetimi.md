# Bar Menü Yönetimi Ekranı — Plan

**Goal:** Personel bar menüsünü ekrandan yönetsin (ekle/pasif/sil + stok kalemine bağla), sonra müşteriye yayınlasın.

**Mimari:** Yeni sayfa `bar-menu-yonetimi.html`. Menü ürünlerini ANA projeye personelin **giriş JWT'siyle doğrudan** okur/yazar (menu_urunler + urunler RLS auth_yetki_var'a bağlı; auth_yetki_var SECURITY DEFINER olduğu için authenticated JWT geçer). Edge Function YOK. Yayın için mevcut `smooth-service` (CORS düzeltmesiyle).

## Global Constraints
- MAIN `SB_URL`/`SB_KEY` (supabase-config.js). JWT: `oturumAccessTokenGetir()`. Yazma/okuma header: `{apikey:SB_KEY, Authorization:'Bearer '+jwt}` (SB_HEADERS DEĞİL — o anon).
- Yetki: `bar_siparis_yonetimi` (goruntule oku, kayit yaz). menu_urunler + urunler RLS bunu/benzerini ister; auth_yetki_var SECURITY DEFINER (masa maratonunda düzeltildi).
- Yayın: customer'a `smooth-service` (`/functions/v1/smooth-service`) — CORS allow-headers'a `authorization, apikey, content-type, x-client-info` eklenir (tek Edge Function dokunuşu, kullanıcı deploy).
- Commit `git -c user.name="mehmetaraz0" -c user.email="mehmetaraz868@gmail.com"`.

## Task 1: `bar-menu-yonetimi.html` (sayfa — controller push, kullanıcı deploy YOK)
- Head: auth-guard, supabase-config, nav-drawer, otel-config, ortak.js, theme.css.
- Sabit `JH = {apikey:SB_KEY, Authorization:'Bearer '+oturumAccessTokenGetir(), 'Content-Type':'application/json'}` (her çağrıda taze token al).
- init: `CU=requireLogin()`; `if(!requireRole(CU,['mutfak','bar','yonetici']))return`; `YETKI_HARITASI=await kullaniciYetkileriGetir()`; `yazabilir()`.
- **Ekle formu:** ad, kategori, otel(select 810/811), fiyat, ucretli(checkbox), miktar_per_porsiyon(default 1), + **stok arama**: input'a yazınca `GET urunler?or=(kod.ilike.*q*,ad.ilike.*q*)&limit=10` (JWT header) → sonuç listesi → tıkla → seçili stok_kodu+ad göster. tip='direkt' sabit (receteli v2).
- **Ekle:** `POST menu_urunler` (JWT) {ad,kategori,otel_id,fiyat,ucretli,tip:'direkt',stok_kodu,miktar_per_porsiyon,aktif:true}. Doğrulama: ad+stok_kodu zorunlu.
- **Liste:** `GET menu_urunler?select=*&silindi=eq.false&order=kategori` (JWT). Her satır: ad, kategori, otel, fiyat, Dahil/Ücretli rozet, bağlı stok_kodu + **Pasif/Aktif** (PATCH aktif) + **Sil** (PATCH silindi=true).
- **"Müşteriye Yayınla" butonu:** `POST smooth-service` (customer anon key ile) → toast "N ürün yayınlandı".
- Tüm DB metni escapeHtml. Yazma butonları yazabilir()'e bağlı.

## Task 2: `smooth-service` CORS düzeltmesi (kullanıcı deploy)
- `docs/kurulum/musteri-projesi/menu-yayinla/index.ts` CORS allow-headers'ı güncelle → kullanıcı smooth-service'i Code→yapıştır→Deploy updates (ya da yeni fonksiyon). Controller curl ile OPTIONS/çalışmayı doğrular.

## Task 3: Navigasyon — `bar.html` hub'a "Menü Yönetimi" kartı (controller push).

## Task 4: Uçtan uca — ürün ekle (stok bağla) → yayınla → QR'da gör → sipariş → stok düş → kuyrukta belir. Çift menü temizliği.
