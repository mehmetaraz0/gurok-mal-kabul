# Ön Büro — Bar Borç İstisnası Çözüm Akışı (TASARIM, ONAY BEKLİYOR)

**Tarih:** 2026-09-19 · **Bağlam:** Bar A1, karar 2 ("servis edildi" istisnası çözülmeden sipariş
tamamlanmış sayılmaz). Sunucu tarafı A1'de var (`bar_borc_istisnasi_coz`); **ekran yok**.
**Durum:** Yalnız tasarım. Kod yazılmadı. Aşağıdaki K-maddeleri kullanıcı kararı bekliyor.

## 1. Sorun

Folyosu kapanmış misafire bar ürünü fiziksel olarak servis edildiyse yetkili bar personeli
istisna açar: stok düşer, **borç yazılmaz**, sipariş `istisna_bekliyor` durumunda bekler. Bugün
bu istisnayı çözecek bir ekran yok. Çözüm yalnız veritabanı fonksiyonuyla yapılabiliyor.

## 2. Önerilen yer: `pms-folio.html` içinde küçük bir bölüm (yeni sayfa değil)

Ön büro borcu zaten bu ekranda yönetiyor. Yeni sayfa ve menü girişi gerekmez.

```
┌ Misafir Hesabı (Folio) ─────────────────────────────────────────┐
│ ⚠️ 2 bar istisnası çözüm bekliyor                     [Göster ▾] │  ← yalnız açık istisna varsa
├─────────────────────────────────────────────────────────────────┤
│ Oda 101 · 300,00 ₺ · Viski ×1 · CARDAK                           │
│ Folyo kapandıktan sonra servis edildi — beyan: Şef 810, 18:21    │
│ Eski folyo: F-000123 (kapalı)                                    │
│                                   [Folyoya yaz]  [Tahsil edilemedi]│
└─────────────────────────────────────────────────────────────────┘
```

**Folyoya yaz** penceresi:

```
Hedef folyo  [ Açık folyolar (bu otel) — oda / misafir / açılış ▾ ]   (varsayılan SEÇİLİ DEĞİL)
  ⚠ Seçilen folyo eski misafirin rezervasyonuna ait değil — başka misafire borç yazılıyor olabilir.
☐ Misafiri yeniden doğruladım (zorunlu)
Not (isteğe bağlı) [__________]
                                        [Vazgeç]  [Borcu yaz]
```

**Tahsil edilemedi** penceresi: gerekçe (zorunlu) → [Kaydet].

## 3. Davranış

| Adım | Ne olur | Sunucu kontrolü (A1'de var) |
|---|---|---|
| Liste | `bar_borc_istisnalari` `durum='acik'`, otel kapsamlı; sipariş kalemleri ve beyan veren adıyla | Okuma: `pms_folio` ya da `bar_siparis_yonetimi` ≥ görüntüle + otel erişimi |
| Folyoya yaz | Yalnız **açık** ve **aynı otel** folyoları listelenir; varsayılan seçim yok | `FOLYO_KAPALI`, `DOGRULAMA_BEYANI_GEREKLI` |
| Farklı misafir uyarısı | Seçilen folyonun rezervasyonu `eski_rezervasyon_id`'den farklıysa kırmızı uyarı ve ek onay | Ekran kontrolü (sunucu engellemez — bkz. K3) |
| Tahsil edilemedi | Gerekçe zorunlu | `COZUM_NOTU_GEREKLI` |
| Sonuç | Sipariş `teslim_edildi` olur; istisna kaydında çözen, zaman, hedef folyo, not saklanır | Tek işlem, satır kilidi; ikinci çözüm `zaten_cozuldu` |

Borç tutarı **istisna anındaki tutardır** (sipariş anındaki fiyat), ekranda değiştirilemez.

## 4. Karar gerektiren noktalar

- **K1 Yer:** `pms-folio.html` içinde bölüm (öneri) mi, ayrı `bar-istisnalari.html` sayfası mı?
- **K2 Yetki:** Çözme bugün `pms_folio ≥ kayit` (benim Ö12 yorumum). "Tahsil edilemedi" gelir
  kaybı demek; bu karar `tam` (yönetici) seviyesine mi kısıtlansın?
- **K3 Başka misafire yazma:** Yalnız ekranda uyarı mı (öneri), yoksa sunucu da
  `eski_rezervasyon_id` dışındaki folyoya yazmayı `tam` yetkisine mi bağlasın?
- **K4 Bekleme süresi:** Açık istisna için süre sınırı / günlük hatırlatma olsun mu? (A1'de yok.)
- **K5 Bar ekranına geri bildirim:** Çözülen istisna kuyrukta "Teslim" sekmesinde görünür;
  ayrıca bildirim gerekmez (öneri).

## 5. Test planı (onaydan sonra)

Ekran testi (gerçek betik + PostgREST): liste otel kapsamı; folyoya yaz — doğrulama kutusu
olmadan istek gitmez; kapalı folyo seçilemez; farklı misafir uyarısı; tahsil edilemedi gerekçesiz
gitmez; ikinci çözüm denemesi `zaten_cozuldu`; `bar_siparis_yonetimi` yetkilisi listeyi görür
ama çözemez (düğme yok + sunucu `YETKI_YOK`). Gerçek tarayıcıda bir tur.
