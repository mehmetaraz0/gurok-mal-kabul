# F&B Bar/Restoran Modülü — Tasarım (v2, kararlar netleşti)

**Bağlam:** Otel bar/restoran noktalarında verilen siparişlerin, mutfak/depo günlük tüketim mantığına benzer şekilde otomatik olarak stoktan düşmesini sağlayan, mevcut Depo Sipariş / Günlük Tüketim / Mal Kabul modüllerinden tamamen ayrı bir sistem. Önceki tartışmalar: 01.07.2026, 16.07.2026, 22.07.2026 (v1→v2 mimari değişikliği: güvenlik gerekçesiyle tek Supabase projesinden iki izole projeye geçildi). Bu belge, v2 notlarındaki 3 açık soru + 1 ek netleştirme netleşince yazıldı.

## Problem

Bar/restoran siparişleri şu an elle takip ediliyor; stok düşümü otomatik değil. Ayrıca müşteri tarafına (QR/telefon) bir sipariş arayüzü açmak, mevcut ERP'nin anon key'ini (ve dolayısıyla RLS'in kapsadığı tüm tabloları) müşterinin telefonuna kadar taşıma riski içeriyor. Projede geçmişte RLS sorun çıkardığında `ALTER TABLE x DISABLE ROW LEVEL SECURITY` ile tamamen kapatma refleksi gözlemlendiği için (bkz. [[RLS-Denetimi]] — bu refleksin somut kanıtı, 2026-07-22 tarihli denetimde 5 tabloda RLS'in hiç açılmadığı bulundu), tek proje + RLS'e güvenmek yerine fiziksel izolasyon tercih edildi.

## Kapsam Dışı (YAGNI)

- Gerçek zamanlı PMS (otel ön büro/misafir faturalama) entegrasyonu — sistemde şu an misafir/oda bazlı bir hesap kavramı yok. Ücretli siparişler sadece oda no ile etiketlenip kaydedilir, personel gün sonunda manuel olarak PMS'e işler. Otomatik entegrasyon ileride ayrı bir faz.
- Supabase Realtime / WebSocket abonelikleri — mevcut mimaride hiç kullanılmıyor, polling yeterli.
- Oda no doğrulama/misafir kimlik kontrolü — v1 kapsamında serbest metin, sistemde karşılaştırılacak bir misafir tablosu yok.

## 1. Genel Mimari

```
┌─────────────────────────────┐         ┌─────────────────────────────┐
│   MÜŞTERİ PROJESİ (yeni)     │         │   ANA ERP PROJESİ (mevcut)   │
│   Supabase — izole           │         │   Supabase — 55 tablo        │
│                               │         │                               │
│   menu_urunler (salt okunur) │  ──────▶│   Personel menü yönetimi     │
│   bar_siparisleri (INSERT)   │◀──────  │   (tek yönlü: admin→müşteri) │
│   bar_siparis_kalemleri      │         │                               │
│                               │  ──────▶│   Edge Function / webhook    │
│   Anon key SADECE bu 3 tablo │         │   ile sipariş ana sisteme    │
│   için RLS ile açık          │         │   aktarılır, stok rezervas-  │
│                               │         │   yonu orada işlenir         │
└───────────▲───────────────────┘         └─────────────────────────────┘
            │
      menu.alibeyclub.com (GitHub Pages, kendi kontrolümüzde)
            │
      QR kod ─── müşteri telefonu
            │
      Otel WordPress sitesi (dış ajans) — sadece bir <a href> linki/QR görseli barındırır
```

**Neden iki izole proje:** Anon key tarayıcı JS'inde herkese açıktır; güvenlik RLS politikalarında yaşar. Tek proje + sıkı RLS yerine fiziksel izolasyon seçildi çünkü RLS'in ileride yanlışlıkla kapatılması ihtimaline karşı (gözlemlenmiş bir davranış kalıbı — bkz. [[RLS-Denetimi]]), en kötü senaryo müşteri projesinde menü okunur/sahte sipariş yazılır düzeyinde kalsın, muhasebe/cari/personel verisine fiziksel yol olmasın.

**Kabul edilen ek maliyet:** Menü ve sipariş verisi için tek yönlü, seyrek senkronizasyon köprüsü (bkz. Bölüm 6).

## 2. Ödeme ve Ücretlendirme Modeli

Karma model: bazı ürünler all-inclusive kapsamında ücretsiz, bazıları (premium kokteyl, özel şişe içki vb.) ücretli ve oda hesabına yansır.

- `menu_urunler.ucretli` (bool) — ürün bazında sabit, personel menü tanımlarken belirler.
- Sipariş kalemi oluşturulurken `ucretli=true` olan en az bir kalem varsa oda no zorunlu; sepette sadece `ucretli=false` kalemler varsa oda no istenmez.
- Aynı siparişte ücretli+ücretsiz kalem karışık olabilir; oda no bir kez girilir ve sipariş üstü tek bir alanda tutulur (`bar_siparisleri.oda_no` — bkz. Bölüm 7 Veri Modeli).

## 3. Masa/Oda Tanımlama ve QR Token

- QR kod ham masa ID'si taşımaz — imzalı/opak token (`?t=a8f3c9...`) taşır; token→masa eşleşmesi INSERT sırasında sunucu tarafı fonksiyonda (Edge Function/RPC) çözülür.
- Oda no, misafir tarafından sipariş formunda **serbest metin** olarak girilir (yalnızca sepette ücretli kalem varsa formda görünür). Sistemde gerçek bir misafir/oda tablosu olmadığından bu alan karşı doğrulanmaz — sadece kayıt/etiket amaçlıdır.
- Personel gün sonunda ücretli siparişleri (oda no + tutar listesi) görüp otelin ayrı PMS sistemine manuel işler; bu v1'de otomatik değildir.

## 4. Personel Arayüzü — Gelen Siparişler Ekranı

Yeni, bağımsız bir modül (örn. `bar-siparis-kuyrugu.html`), mevcut Depo Sipariş modülünün mimarisiyle tutarlı: vanilla JS + Supabase REST, `auth-guard.js` + yetki matrisi ile korunur (yeni modül: `bar_siparis_yonetimi`).

- Durum akışı: `yeni → hazirlaniyor → hazir → teslim_edildi | iptal`.
- Güncelleme: `setInterval` ile 5-10 saniyede bir `bar_siparisleri` sorgusu — mevcut REST-fetch deseniyle tutarlı, yeni bağımlılık (Supabase Realtime) eklenmiyor.
- **Önkoşul:** Bu modülün yetki matrisine güvenli eklenebilmesi için, [[RLS-Denetimi]]'nde bulunan `yetki_matrisi`/`roller`/`moduller` RLS açıklarının önce kapatılmış olması gerekir — aksi halde yeni modül yetkisi de aynı anon-yazma açığından etkilenir.

## 5. Sipariş Yaşam Döngüsü (ana projede işler)

```
Sipariş oluşturulur (müşteri projesinden webhook ile gelir)
        ↓
Müsaitlik kontrolü (stok − rezerve ≥ gerekli miktar)
   ├── Yetersiz → sipariş engellenir (hard block)
   └── Yeterli ↓
Miktar rezerve edilir
        ↓
Bar/mutfak kuyruğu  ── İptal → rezervasyon serbest bırakılır
        ↓
Hazırlandı / teslim edildi
        ↓
Stok kesin düşer, rezervasyon kapanır
```

Rezervasyon katmanı gerekçesi: sipariş anında hard-block yapıp düşümü teslimat anına ertelemek, aradaki boşlukta çakışma riski yaratır (iki masa aynı son 2 birimi aynı anda sipariş edip ikisi de "stok var" onayı alabilir). Bu yüzden miktar sipariş anında rezerve edilir:

```
kullanılabilir_miktar = stok.miktar − SUM(stok_rezervasyonlari WHERE durum = 'aktif')
```

## 6. Senkronizasyon Köprüsü (tek yönlü, seyrek)

| Yön | İçerik | Sıklık |
|---|---|---|
| Ana proje → Müşteri projesi | Menü ürünleri (ad, fiyat, kategori, ucretli, aktif/pasif) | Personel "yayınla" dediğinde, ya da elle |
| Müşteri projesi → Ana proje | Yeni siparişler | Anlık, Edge Function / webhook ile |

Müşteri projesi sadece "sipariş talebi" taşır; stok mantığına hiç dokunmaz.

## 7. Veri Modeli

### Ana ERP projesi (mevcut Supabase)

**`menu_urunler`**: id, ad, kategori, otel_id, fiyat, aktif, ucretli (bool, yeni), tip (`direkt`|`receteli`), stok_kodu, miktar_per_porsiyon.

**`recete_bilesenleri`**: id, menu_urun_id (FK), stok_kodu (FK), miktar_per_porsiyon, birim.

**`bar_siparisleri`** (webhook ile beslenir): id, otel_id, depo_id, masa_token, oda_no (nullable, sadece ücretli kalem varsa dolu), durum, olusturma_zamani, personel_id (nullable — kim hazırladı/teslim etti).

**`bar_siparis_kalemleri`**: id, siparis_id (FK), menu_urun_id (FK), adet, rezerve_edildi (bool), teslim_edildi (bool).

**`stok_rezervasyonlari`**: id, stok_kodu, otel_id, depo_id, miktar, siparis_kalem_id (FK), durum (`aktif`|`serbest`|`kullanildi`).

### Müşteri projesi (yeni, izole Supabase)

**`menu_urunler`** — ana projeden tek yönlü kopyalanan salt-okunur önizleme (id, ad, kategori, fiyat, ucretli, aktif).
**`bar_siparisleri`** / **`bar_siparis_kalemleri`** — müşteri INSERT eder, webhook ile ana projeye iletilir; iletildikten sonra bu projedeki kopya arşiv amaçlı kalabilir ya da temizlenebilir.

## 8. Güvenlik (müşteri projesi RLS)

- `menu_urunler`: yalnızca `SELECT`, `USING (aktif = true)`.
- `bar_siparisleri` / `bar_siparis_kalemleri`: yalnızca `INSERT`; `SELECT`/`UPDATE`/`DELETE` yok (müşteri başka masaların siparişini göremez).
- Diğer hiçbir tabloya anon erişimi tanımlanmaz (bu projede zaten sadece bu tablolar var).
- INSERT'te basit rate-limit / miktar üst sınırı — aynı token'dan anormal sıklıkta sipariş engellensin (sahte rezervasyonla stok kilitleme riskine karşı).
- **Bağımlılık:** Ana projede `yetki_matrisi`/`roller`/`moduller` RLS düzeltmesi ([[RLS-Denetimi]]) bu modülün implementasyonundan ÖNCE tamamlanmalı.

## Hata Yönetimi / Kenar Durumlar

- Webhook ana projeye ulaşamazsa (ağ hatası): sipariş müşteri projesinde `iletildi=false` olarak kalır, ana projeye erişim geri geldiğinde retry mekanizmasıyla (basit polling job veya webhook yeniden deneme) iletilir — bu bir veri kaybı senaryosu değil, gecikme senaryosu.
- Rezervasyon süresi dolan/hiç teslim edilmeyen siparişler (masa siparişi verip gelmeyen misafir): kapsam dışı bırakıldı, personelin manuel iptal etmesi bekleniyor — otomatik zaman aşımı v1'de yok.
- Oda no formatı doğrulanmaz (serbest metin) — yanlış girilen oda no'nun sorumluluğu operasyonel, sistem seviyesinde engellenmiyor.

## Test Planı

1. Müşteri projesinde RLS izolasyonu — anon key ile başka masa/sipariş sorgulanamadığını doğrula (`SELECT`/`UPDATE`/`DELETE` denemesi 403/boş dönmeli).
2. Rezervasyon yarış senaryosu — aynı ürünün son 1-2 birimine iki eşzamanlı sipariş gönderip sadece birinin geçtiğini doğrula.
3. Ücretli/ücretsiz karışık sepet — oda no doğru şekilde sadece ücretli kalemlere etiketleniyor mu.
4. Kuyruk ekranı polling — yeni sipariş 5-10 sn içinde ekranda görünüyor mu.
5. Webhook kesintisi — ana proje geçici olarak erişilemez durumdayken sipariş kaybolmadan retry ile iletiliyor mu.

## Geri Dönüş (Rollback)

Bu modül mevcut ERP'den tamamen izole (ayrı Supabase projesi, ayrı hosting) olduğu için geri alma riski düşük — sorun çıkarsa QR/link devre dışı bırakılır, ana ERP'ye hiçbir etkisi olmaz. Webhook köprüsü devre dışı bırakılırsa müşteri projesindeki siparişler sadece o projede birikir, ana projeye ulaşmaz (veri kaybı olmaz, gecikme olur).

## Öncelik Sırası

1. **Önkoşul:** Ana projede `yetki_matrisi`/`roller`/`moduller`/`fatura_kalemleri`/`yevmiye_kalemleri` RLS düzeltmesi ([[RLS-Denetimi]]).
2. Müşteri Supabase projesi kurulumu + RLS politikaları.
3. `menu.alibeyclub.com` alt alan adı DNS ayarı (ajanstan tek bir CNAME kaydı istenecek).
4. Edge Function / webhook köprüsü (sipariş: müşteri → ana proje).
5. Ana projede veri modeli (`menu_urunler.ucretli`, `bar_siparisleri.oda_no`, `stok_rezervasyonlari` vb.) ve rezervasyon mantığı.
6. Personel tarafı kuyruk ekranı (`bar-siparis-kuyrugu.html`) ve rol/yetki matrisine yeni modülün eklenmesi.

## İlgili

[[RLS-Denetimi]] · [[Guvenlik-Performans]] · [[Auth-Yetki-Modeli]]
