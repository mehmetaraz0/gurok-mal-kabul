# Yeni Müşteri Kurulum Rehberi

Bu rehber, sistemi yeni bir otel/turizm grubuna sıfırdan kurmak için izlenecek
sıralı adımları tanımlar. Her adım bir öncekine bağımlıdır — sırayı bozmayın.

## Ön Koşullar
- Yeni bir Supabase hesabı/organizasyonu
- Bu reponun bir kopyası (fork veya klon)
- Statik hosting (GitHub Pages veya eşdeğeri)

## Adımlar

1. **Supabase projesi oluştur.** [supabase.com](https://supabase.com) → New Project.
   Bölge ve güçlü bir DB şifresi seçin.

2. **Şemayı kur.** Supabase SQL Editor'de `docs/kurulum/01-sema-dokumu.sql`
   dosyasının tamamını çalıştırın (tablolar, RLS policy'leri, fonksiyonlar).

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
