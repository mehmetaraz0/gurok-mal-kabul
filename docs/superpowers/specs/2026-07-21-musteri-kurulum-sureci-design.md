# Tekrarlanabilir Müşteri Kurulum Süreci — Tasarım

**Bağlam:** Satış stratejisi punch list'inin 4. ve son maddesi. Önceki 3 madde (güvenilirlik boşlukları, modül aç/kapa kataloğu, config merkezileştirme) tamamlandı — bu madde onları birleştirip "yeni bir otel/turizm grubuna nasıl kurulum yaparım" sorusunu gerçekten cevaplanabilir hale getiriyor.

## Problem

Proje boyunca tüm şema değişiklikleri (54+ tablo, RLS policy'leri, SQL fonksiyonları) Supabase SQL editöründe tek tek, oturum oturum çalıştırıldı — repoda hiçbir `.sql` dosyası tutulmuyor. Bu yüzden şu anda sıfırdan bir kurulum yapmak için tek kaynak, canlı Gürok Supabase veritabanının kendisi. Ayrıca `otel-config.js` (Faz 3'te merkezileştirildi) ve `moduller.aktif` (Faz 2'de eklendi) gibi mekanizmalar var ama bunların YENİ bir müşteri için nasıl bir sırayla kullanılacağı hiçbir yerde belgelenmemiş.

## Kapsam Dışı (YAGNI)

- Ürün/tedarikçi kataloğu (`gurok_veritabani.js`, ~1290 ürün) doldurma süreci — her müşterinin kendi verisi tamamen farklı olur, bu ayrı bir "veri girişi" konusu. Rehberde sadece mevcut Excel import özelliğine bir yönlendirme notu bırakılır.
- Şema DDL'inin (tablo/RLS/fonksiyon oluşturma) otomasyonu — bu proje "build aracı yok, saf tarayıcı" felsefesine sahip; DDL çalıştırmak Supabase SQL editöründe manuel bir adım olarak KALIR. Otomasyon sadece REST üzerinden yapılabilecek kısımları (referans veri seed'i, config üretimi) kapsar.

## 1. Şema Dökümü

Kullanıcıdan canlı Supabase veritabanının tam şema dökümünü (Supabase Dashboard → Database → Backups, ya da SQL editöründe bir dışa aktarma sorgusu ile) alması istenir. İki dosya olarak repoya commit edilir:

- `docs/kurulum/01-sema-dokumu.sql` — tüm tablolar, RLS policy'leri, SQL fonksiyonları (`auth_yetki_var`, `auth_kullanici_rol_id`, `stok_ekle`, `stok_transfer` vb.), sequence'lar. Sıfırdan bir Supabase projesinde tek seferde çalıştırılabilir olmalı.
- `docs/kurulum/02-referans-veri.sql` — SADECE `roller`, `moduller`, `yetki_matrisi` tablolarının veri dökümü (gerçek müşteri verisi — `cariler`, `faturalar`, `urunler` vb. — KESİNLİKLE dahil edilmez). Yeni kurulum aynı 38 rol/41 modül/yetki dağılımıyla başlar, müşteri daha sonra `yetki-yonetimi.html`'den özelleştirir.

## 2. Yeni Ekran: `yeni-musteri-kurulum.html`

`migrate-to-supabase.html` ile aynı desende (service-role key giren, tek seferlik kullanım aracı, yönetici-korumalı) ama farklı amaçlı — 01/02 SQL'leri zaten elle çalıştırılmış BOŞ bir Supabase projesine bağlanır:

- **Otel-config üretici formu:** otel adları, kısa adları, ticari unvanları, kodları, merkezi depo kodları, dahili e-posta domaini girilir → `otel-config.js` dosyasının TAM içeriği (mevcut `otel-config.js`'in şablonunu kullanarak) ekranda gösterilir, kopyala-yapıştır ile alınır. Tarayıcı sandbox kısıtı nedeniyle dosyaya doğrudan yazılamaz — kullanıcı bunu repo köküne kendisi kaydeder.
- **İlk yönetici kullanıcısı formu:** ad, PIN, rol (`sistem_admin`) girilir → `kullanicilar` tablosuna REST üzerinden INSERT edilir (bu, seed edilmiş `roller` tablosundaki `sistem_admin` rol_id'sini kullanır).

## 3. Kurulum Rehberi: `docs/KURULUM-REHBERI.md`

Sıralı checklist:
1. Yeni bir Supabase projesi oluştur.
2. `01-sema-dokumu.sql`'i SQL editöründe çalıştır.
3. `02-referans-veri.sql`'i SQL editöründe çalıştır.
4. Repoyu (ya da bir fork'unu) klonla.
5. `supabase-config.js`'i yeni projenin URL/anon key'iyle güncelle.
6. `yeni-musteri-kurulum.html`'i tarayıcıda aç, service-role key'i geçici olarak gir, otel-config formunu doldur, üretilen içeriği `otel-config.js`'e kopyala-yapıştır ve commit et.
7. Aynı ekrandan ilk yönetici kullanıcısını oluştur.
8. GitHub Pages'e (veya eşdeğeri statik hosting) deploy et.
9. `yetki-yonetimi.html`'den bu müşteri için hangi modüllerin aktif kalacağını ayarla (Faz 2'nin `moduller.aktif` toggle'ı).
10. Ürün/tedarikçi kataloğunu doldur — bkz. mevcut Excel toplu veri yönetimi özelliği (kapsam dışı, sadece yönlendirme).

## Hata Yönetimi / Kenar Durumlar

- `yeni-musteri-kurulum.html`'deki service-role key formu, `migrate-to-supabase.html`'deki AYNI güvenlik notunu taşır: anahtar kalıcı depoya yazılmaz, sadece sayfa açıkken bellekte tutulur (RLS'yi bypass eden bir anahtar olduğu için).
- Otel-config üretici formunda hiçbir alan doldurulmadan "üret" denirse, boş/placeholder değerlerle bir şablon üretilmez — form kullanıcıyı zorunlu alanları doldurmaya yönlendirir (`required` HTML validasyonu yeterli, ekstra JS mantığı gerekmez).
- İlk yönetici kullanıcısı formu, aynı PIN'in birden fazla kullanıcıya atanmasını engellemez (mevcut `kullanicilar` tablosunun genel davranışıyla tutarlı — bu proje PIN'i unique constraint ile korumuyor, tek kullanıcılık bir kurulum adımında bu risk kabul edilebilir).

## Test/Doğrulama Planı

- `01-sema-dokumu.sql`/`02-referans-veri.sql`: kullanıcıdan gerçek bir BOŞ Supabase projesinde (ya da mevcut projede ayrı bir şema/test ortamında, eğer varsa) çalıştırıp hatasız tamamlandığını doğrulaması istenir — bu oturumda ikinci bir Supabase projesi oluşturma erişimi yok, bu adım kullanıcının kendi yapması gereken bir doğrulama.
- `yeni-musteri-kurulum.html`: otel-config formu doldurulup üretilen içeriğin mevcut `otel-config.js`'in gerçek yapısıyla (aynı sabit/fonksiyon isimleri) birebir eşleştiği kontrol edilir. İlk kullanıcı formu, `kullanicilar` tablosuna gerçek bir INSERT yapıp yapmadığı curl ile doğrulanır (mevcut oturumdaki Gürok projesinde TEST amaçlı bir satır eklenip silinerek, ya da sadece kod incelemesiyle — gerçek bir DELETE riski varsa sadece statik inceleme tercih edilir).
- `docs/KURULUM-REHBERI.md`: kendi içinde tutarlılık kontrolü — her adımın önceki adıma bağımlılığı doğru sırada mı, atlanan bir adım var mı.
