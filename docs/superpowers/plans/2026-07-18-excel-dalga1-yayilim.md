# Excel Toplu Veri Yönetimi — Dalga 1 Yayılım Implementation Plan

> **For agentic workers:** Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Pilotta kurulan `ortak-excel.js` motorunu 4 yeni tabloya
yaymak: `stok_minimumlar`, `hesap_plani`, `doviz_kurlari`,
`butce_kayitlari` — bileşik doğal anahtar ve sıfır-izinli sayısal alan
desteği eklenerek.

**Architecture:** Modül uzantısı (bileşik anahtar + `pozitifOlmali`) +
her tablo için spec + 3 fonksiyon (Aktar/Yükle/Uygula) + buton, pilotla
birebir aynı desen.

**Tech Stack:** Vanilla HTML/JS, Supabase REST (fetch), XLSX — build
aracı yok.

---

## Global Constraints

- Operasyon-seviyesi canlı-durum kilidi YOK (pilottan farklı) — bu 4
  tablo referans/config verisi, onay-akışı riski taşımıyor.
- FK/referans kontrollerinde sayfanın zaten yüklediği in-memory veri
  kullanılır (`db.urunler`, `hesaplar`) — ekstra sorgu açılmaz.
- Her tablo kendi doğal anahtarıyla upsert edilir (`saveLnSiparisler`
  deseni), id sütunu/kilitli alan yok (pilottan farklı — bu tablolarda
  görünür/düzenlenemez bir "Sistem ID" sütunu kullanıcıya gösterilmiyor).

---

### Task 1: `ortak-excel.js` uzantısı ✅

- [x] **Step 1: Bileşik doğal anahtar** — `_excelDogalAnahtarUret()`
  yardımcı fonksiyonu + `opts.dogalAnahtarKombinasyonu` desteği.
- [x] **Step 2: `pozitifOlmali` bayrağı** — sayısal alan doğrulaması
  artık varsayılan 0 kabul ediyor, negatif reddediyor; `pozitifOlmali:
  true` işaretli alanlarda (pilotun `miktar`'ı) eski davranış korundu.
- [x] **Step 3: Gerçek tarayıcı testi** — tekil-alan/bileşik-alan/sıfır-
  izni senaryoları + pilotun geriye dönük davranışı doğrulandı.
- [x] **Step 4: Commit** (582df8d)

---

### Task 2: `stok-takip.html` → `stok_minimumlar` ✅

- [x] **Step 1-3: Spec + Aktar/Yükle/Uygula + buton** — STOK sekmesi
  araç çubuğuna eklendi.
- [x] **Step 4: Gerçek bulgu + düzeltme** — `depo_kodu`/`otel_id` NOT
  NULL kısıtları keşfedildi; mevcut `minimumDuzenle()` bunları hiç
  göndermiyordu ve `response.ok` kontrol etmiyordu (sessiz hata) —
  düzeltildi.
- [x] **Step 5: Uçtan uca test** — yeni minimum yazıldı, doğrulandı,
  temizlendi.
- [x] **Step 6: Commit** (b6d7c73)

---

### Task 3: `muhasebe-hesap-plani.html` → `hesap_plani` ✅

- [x] **Step 1-3: Spec + Aktar/Yükle/Uygula + buton** — toolbar'a ayrı
  "Toplu Düzenle" butonları (mevcut sahte-XLSX `exportExcel()`'e
  dokunulmadı).
- [x] **Step 4: Kod format doğrulaması** — `hesapKaydet()`'teki regex
  sınıflandırma sonrası enjekte edildi.
- [x] **Step 5: Uçtan uca test** — 390 hesap dışa aktarıldı; `ust_kod`
  self-FK kısıtı keşfedildi (üst hesap önce var olmalı) ve doğru test
  edildi; bozuk kod reddedildi; yeni hesap yazıldı, temizlendi.
- [x] **Step 6: Commit** (011b810)

---

### Task 4: `muhasebe-kur.html` → `doviz_kurlari` ✅

- [x] **Step 1-3: Spec (bileşik anahtar) + Aktar/Yükle/Uygula + buton**
  — "Son 14 Gün" kartına eklendi, export TÜM geçmişi indiriyor.
- [x] **Step 4: Para birimi enum doğrulaması** — mevcut FK mekanizması
  (fkAlan/fkSet) enum kontrolü için yeniden kullanıldı.
- [x] **Step 5: Uçtan uca test** — bileşik anahtar mükerrer tespiti,
  FK-dışı/tarih-format hataları, gerçek yazma doğrulandı, temizlendi.
- [x] **Step 6: Commit** (2e649c1)

---

### Task 5: `muhasebe-butce.html` → `butce_kayitlari` ✅

- [x] **Step 1-3: Spec (bileşik anahtar + 12 ay sütunu) + Aktar/Yükle/
  Uygula + buton** — "Bütçe Girişleri" sekmesine eklendi.
- [x] **Step 4: Uçtan uca test** — sıfır aylık değer doğru 'yeni'
  sınıflandı (hata değil), FK-dışı hesap kodu reddedildi, `hesap_ad`
  otomatik dolduruldu, gerçek yazma doğrulandı. `silindi` (soft-delete)
  keşfedildi — RLS hard-DELETE'i engelliyor, temizlik `silindi:true`
  PATCH ile yapıldı.
- [x] **Step 5: Commit** (cf6c467)

---

### Task 6: Rapor ✅

- [x] Kullanıcıya 4 tablonun durumu + Dalga 2 önerisi raporlandı.
