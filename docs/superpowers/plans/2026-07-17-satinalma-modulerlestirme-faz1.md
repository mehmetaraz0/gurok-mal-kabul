# Satın Alma — Muhasebe Deseninde Modülerleştirme (Faz 1) Implementation Plan

> **For agentic workers:** Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `satin-alma.html`'in 4 bağımsız sekmesini (LN Siparişler,
Firmalar, Fiyat Kontrolü, Tedarikçi Skor Kartı) `muhasebe.html` desenindeki
gibi ayrı, bağımsız `.html` dosyalarına taşımak — satin-alma.html geri
kalan 5 sekmeyle birlikte çalışır durumda kalır.

**Architecture:** Her yeni dosya `muhasebe-cariler.html` iskeletinin
kopyası (head sırası, guard, toast/ld, tam CSS kopyası). satin-alma.html'de
taşınan sekmenin buton'u `location.href`'e çevrilir, `.sc` div'i +
fonksiyonları + modalleri + `gTab()` dispatch satırı silinir.

**Tech Stack:** Vanilla HTML/JS, Supabase REST (fetch) — build aracı yok.

---

## Global Constraints

- `DB.firmalar`/`loadFirmalar()` satin-alma.html'de KALIYOR — Sipariş
  Oluştur/RFQ/Fiyat Kontrolü hâlâ kullanıyor (design). Sadece
  `renderFirmalar()` (görüntüleme) taşınıyor.
- `satin-alma-firmalar.html` `gurok_veritabani.js`'den `FIRMA_DB`/`URUN_DB`
  okur — satin-alma.html'in kendi gömülü kopyasına dokunulmuyor (design).
- Her adım sonunda satin-alma.html'in kalan 5 sekmesi (özellikle İç
  Talepler'in header'daki global "Yeni Talep" butonu ve
  `stokMinimumKontrolEt()`) tarayıcıda test edilir, bozulmadığı doğrulanır.

---

### Task 1: satin-alma-siparisler.html (LN Siparişler) ✅

**Files:**
- Create: `satin-alma-siparisler.html`
- Modify: `satin-alma.html`

- [x] **Step 1: Yeni dosyayı oluştur** — muhasebe-cariler.html iskeleti +
  satin-alma.html'in tam `<style>` kopyası. Taşınan içerik: `#tab-siparisler`
  markup (satır 120-134), `#mLNDetay`/`#mLNKolon` modalleri (satır 442-465),
  `filterLN`/`renderLN`/`openLNDetay`/`lnEksikleriAktar`/`parseLNExcel`/
  `applyLNKolon`/`saveLnSiparisler` fonksiyonları + `let lnRows=[]`/
  `let lnFilter='bekleyen'`/`let DB={lnSiparisler:{}}`. Init: `loadDB()`
  (sadece `ln_siparisler` fetch) → `renderLN()`. Header: geri butonu
  `satin-alma.html`'e döner.
- [x] **Step 2: satin-alma.html'i güncelle** — LN Siparişler tabbtn'i
  `location.href='satin-alma-siparisler.html'`e çevir; `#tab-siparisler`
  div'i, `#mLNDetay`/`#mLNKolon` modalleri, taşınan fonksiyonlar/state
  sil; `gTab()`'den `if(tab==='siparisler')renderLN();` sil;
  `loadDB()`'den `ln_siparisler` fetch'i + `DB.lnSiparisler={}` init'i +
  `lnSiparisler:{}` (DB objesi) sil (grep ile doğrulandı — başka hiçbir
  yerde okunmuyor).
- [x] **Step 3: Tarayıcıda test** — yeni sayfayı aç, filtre sekmelerini
  dene (boş liste doğru render edildi); satin-alma.html'de LN Siparişler
  butonunun yeni sayfaya yönlendirdiğini, İç Talepler + Sipariş Oluştur
  sekmelerinin (DB.firmalar dahil) bozulmadığını doğrula. Not: file://
  önizlemesi statik snapshot veriyor, gerçek test için `.claude/launch.json`
  "static" (python http.server) kullanıldı + geçici sessionStorage
  test-oturumu enjekte edildi (DB'ye hiç yazılmadı).
- [x] **Step 4: Commit** (5bd0c0d)

---

### Task 2: satin-alma-firmalar.html (Firmalar)

**Files:**
- Create: `satin-alma-firmalar.html`
- Modify: `satin-alma.html`

- [ ] **Step 1: Yeni dosyayı oluştur** — `<script src="gurok_veritabani.js">`
  ekle (kendi FIRMA_DB/URUN_DB kopyasını gömme). Taşınan içerik:
  `#tab-firmalar` markup (satır 182-188), `renderFirmalar()` fonksiyonu.
  Init: `renderFirmalar('')` (FIRMA_DB zaten senkron yüklü, fetch gerekmez).
- [ ] **Step 2: satin-alma.html'i güncelle** — Firmalar tabbtn'i
  `location.href='satin-alma-firmalar.html'`e çevir; `#tab-firmalar` div'i,
  `renderFirmalar()` fonksiyonu sil; `gTab()`'den
  `if(tab==='firmalar')renderFirmalar('');` sil. `loadFirmalar()`/
  `DB.firmalar`/`DB.urunler`/gömülü `FIRMA_DB`/`URUN_DB` const'larına
  DOKUNMA (Sipariş Oluştur/RFQ/Fiyat Kontrolü kullanıyor).
- [ ] **Step 3: Tarayıcıda test** — yeni sayfayı aç, arama yap, sonuç
  gördüğünü doğrula; satin-alma.html'de Sipariş Oluştur'daki firma
  otomatik-tamamlamanın hâlâ çalıştığını doğrula (regresyon kontrolü).
- [ ] **Step 4: Commit**

```bash
git -c user.name="mehmetaraz0" -c user.email="mehmetaraz868@gmail.com" add satin-alma-firmalar.html satin-alma.html
git -c user.name="mehmetaraz0" -c user.email="mehmetaraz868@gmail.com" commit -m "refactor: Firmalar sekmesini satin-alma-firmalar.html'e taşı"
```

---

### Task 3: satin-alma-fiyatkontrol.html (Fiyat Kontrolü)

**Files:**
- Create: `satin-alma-fiyatkontrol.html`
- Modify: `satin-alma.html`

- [ ] **Step 1: Yeni dosyayı oluştur** — Taşınan içerik: `#tab-fiyatKontrol`
  markup (satır 208-225), `#mFiyatKontrol` modal (satır 330-339),
  `loadFiyatKontrol`/`fkSbdenCamele`/`filterFiyatKontrol`/
  `renderFiyatKontrol`/`fkDetayAc`/`fkFiyatHesapla`/`fkGenelToplamHesapla`/
  `muhasebeGonder`/`grIrTahakkukFisiKes` fonksiyonları + `_fkFilter`/
  `_fkFormlar`/`_fkAktifId` state. Init: `loadFiyatKontrol()`.
- [ ] **Step 2: satin-alma.html'i güncelle** — Fiyat Kontrolü tabbtn'i
  (badge span dahil) `location.href='satin-alma-fiyatkontrol.html'`e
  çevir; `#tab-fiyatKontrol` div'i, `#mFiyatKontrol` modal, taşınan
  fonksiyonlar/state sil; `gTab()`'den
  `if(tab==='fiyatKontrol')loadFiyatKontrol();` sil.
- [ ] **Step 3: Tarayıcıda test** — yeni sayfayı aç, listeyi gör, bir
  kaydın detayını aç (Muhasebe'ye Gönder'e basmadan kapat — canlı veri
  bozulmasın); satin-alma.html'in kalan sekmelerinin bozulmadığını
  doğrula.
- [ ] **Step 4: Commit**

```bash
git -c user.name="mehmetaraz0" -c user.email="mehmetaraz868@gmail.com" add satin-alma-fiyatkontrol.html satin-alma.html
git -c user.name="mehmetaraz0" -c user.email="mehmetaraz868@gmail.com" commit -m "refactor: Fiyat Kontrolü'nü satin-alma-fiyatkontrol.html'e taşı"
```

---

### Task 4: satin-alma-skorkart.html (Tedarikçi Skor Kartı)

**Files:**
- Create: `satin-alma-skorkart.html`
- Modify: `satin-alma.html`

- [ ] **Step 1: Yeni dosyayı oluştur** — Taşınan içerik: `#tab-skorKart`
  markup (satır 286-316), `renderSkorKart()` fonksiyonu + `_skorKartVeri`
  state. Init: `renderSkorKart()`.
- [ ] **Step 2: satin-alma.html'i güncelle** — Skor Kartı tabbtn'i
  `location.href='satin-alma-skorkart.html'`e çevir; `#tab-skorKart` div'i,
  `renderSkorKart()` fonksiyonu, `_skorKartVeri` sil; `gTab()`'den
  `if(tab==='skorKart')renderSkorKart();` sil.
- [ ] **Step 3: Tarayıcıda test** — yeni sayfayı aç, hesaplanan skorların
  göründüğünü doğrula; satin-alma.html'in kalan sekmelerinin bozulmadığını
  doğrula.
- [ ] **Step 4: Commit**

```bash
git -c user.name="mehmetaraz0" -c user.email="mehmetaraz868@gmail.com" add satin-alma-skorkart.html satin-alma.html
git -c user.name="mehmetaraz0" -c user.email="mehmetaraz868@gmail.com" commit -m "refactor: Tedarikçi Skor Kartı'nı satin-alma-skorkart.html'e taşı"
```

---

### Task 5: Uçtan uca doğrulama + rapor ✅

- [x] **Step 1: satin-alma.html'in yeni satır sayısını ölç** — 3229 → 2463
  satır (%24 azalma).
- [x] **Step 2: Tam regresyon turu** — Sipariş Oluştur, Sipariş Takip,
  İade, Teklifler sekmeleri gerçek tarayıcıda test edildi, konsol hatası
  yok. 4 yeni sayfanın hepsinde geri butonu satin-alma.html'e dönüyor.
- [x] **Step 3: Kullanıcıya rapor**
