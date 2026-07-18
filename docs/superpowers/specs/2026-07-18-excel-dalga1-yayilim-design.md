# Excel Toplu Veri Yönetimi — Dalga 1 Yayılım (4 Tablo) — Tasarım

## Problem / Hedef

Pilot (İç Talepler kalemleri, satin-alma.html) onaylanıp canlıda çalıştı.
Kullanıcı bunu "tüm modüller, her sayfa" için istedi. İki paralel Explore
taraması tüm ERP'yi tarayıp her sayfanın yönettiği tabloyu, mevcut doğal
anahtar/`on_conflict` emsalini, ekle/düzenle giriş noktasını ve FK
ilişkilerini çıkardı.

Bulgu: "her sayfa" literal olarak yapılırsa bazı sayfalar mimari olarak
uygun değil ya da güvenlik riski taşıyor — `kullanici-yonetimi.html`
(`kullanicilar.pin` düz metin giriş şifresi), tüm salt-okunur rapor
sayfaları, `satin-alma-firmalar.html` (canlı tablo yok), karmaşık/
oto-numaralı/çok-tablolu iş akışları (`mal-kabul-v2.html`, `muhasebe-
yevmiye.html` — borç=alacak dengesi kısıtı). Kullanıcıya bulgu sunuldu,
**Dalga 1** (en güçlü, en düşük riskli 4 aday — hepsinde zaten
`on_conflict` emsali var) onaylandı: `stok_minimumlar`, `hesap_plani`,
`doviz_kurlari`, `butce_kayitlari`.

## Kapsam

**`ortak-excel.js` uzantısı** (tüm 4 tablo buna bağımlı):
1. Bileşik doğal anahtar desteği — `opts.dogalAnahtarKombinasyonu` (alan
   dizisi), tüm alanlar BİRLİKTE tek anahtar (`doviz_kurlari`'nin
   tarih+para_birimi, `butce_kayitlari`'nin yil+otel_id+hesap_kodu için).
2. `spec.pozitifOlmali` bayrağı — varsayılan sayısal alanlarda artık 0
   geçerli (negatif hata), sadece `pozitifOlmali:true` işaretli alanlarda
   0 hata (bütçe ay sütunları meşru şekilde 0 olabilir).

**4 sayfa entegrasyonu** (her biri: spec + Aktar/Yükle/Uygula 3
fonksiyon + buton):
- `stok-takip.html` → `stok_minimumlar` (`on_conflict=urun_kodu`)
- `muhasebe-hesap-plani.html` → `hesap_plani` (`on_conflict=kod`)
- `muhasebe-kur.html` → `doviz_kurlari` (`on_conflict=tarih,para_birimi`, bileşik)
- `muhasebe-butce.html` → `butce_kayitlari` (`on_conflict=yil,otel_id,hesap_kodu`, bileşik + 12 ay sütunu)

Detaylı spec tasarımları için bkz. plan dokümanı.

## Kapsam dışı

- **Dalga 2**: `cariler`, `demirbaslar`, `cek_senetler`, RFQ
  `tedarikci_teklif_kalemleri`, yeni bir `urunler` sayfası.
- Güvenlik/uygunsuzluk nedeniyle kapsam dışı: `kullanici-yonetimi.html`
  (PIN), salt-okunur rapor sayfaları, `satin-alma-firmalar.html`,
  karmaşık iş akışları (`mal-kabul-v2.html`, `muhasebe-yevmiye.html`,
  `muhasebe-banka.html`), `ln_siparisler` (zaten farklı bir çözümü var).
- Undo UI'ı, kolon-eşleştirme modalı, 10.000+ satır ilerleme çubuğu.

## Doğrulama / Bayat Veri

Onay-akışı benzeri ara-durum riski yok (4 tablo referans/config verisi)
— operasyon-seviyesi kilit gerekmiyor, sadece standart oku→sınıflandır→
önizle→onayla→yaz akışı.

## Test/doğrulama planı ve gerçek bulgular

Her tablo canlı Supabase'e karşı gerçek dışa aktar → düzenle → geri
yükle → önizleme → uygula → doğrudan sorgu ile doğrulama → temizlik
deseniyle test edildi. Test sırasında keşfedilen, plan yazılırken
bilinmeyen gerçek şema detayları:

- **`stok_minimumlar`**: `depo_kodu`+`otel_id` NOT NULL kısıtları var
  (plan bunları bilmiyordu). Mevcut tekli `minimumDuzenle()` fonksiyonu
  bunları hiç göndermiyordu VE `response.ok` hiç kontrol etmiyordu —
  yani bu özellik sessizce hiçbir zaman Supabase'e yazmıyordu, sadece
  bellekte güncelleniyordu. Düzeltildi (`aktifDepoId`/`otelFromDepoId()`
  ile).
- **`hesap_plani`**: `ust_kod` sütununda `hesap_plani.kod`'a kendine-
  referans FOREIGN KEY var — bir alt hesabın üst kodu önce var olmalı.
  Beklenen/doğru davranış, kod tarafında ekstra işlem gerekmedi.
- **`butce_kayitlari`**: `silindi` (soft-delete) sütunu var, RLS gerçek
  DELETE'i engelliyor (bu projenin RLS Faz 1 kapsamındaki 7 tablodan
  biri) — test temizliği `silindi:true` PATCH ile yapıldı, hard DELETE
  değil.

Tüm 4 tablo için: yeni/güncelleme/değişiklik-yok/hata/bulunamadı/
mükerrer sınıfları (bileşik anahtarlılar dahil) gerçek tarayıcıda
doğrulandı, gerçek yazmalar Supabase'den sorgulanarak teyit edildi, tüm
test verisi temizlendi.
