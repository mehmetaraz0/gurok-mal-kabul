# Satın Alma — Modülerleştirme Faz 2 Implementation Plan

> **For agentic workers:** Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `satin-alma.html`'in kalan 5 sekmesini (İç Talepler, Teklifler,
Sipariş Oluştur, Sipariş Takip, İade) ayrı dosyalara taşımak ve
`satin-alma.html`'i hub sayfasına çevirmek.

**Architecture:** Detaylar için
`docs/superpowers/specs/2026-07-19-satinalma-modulerlestirme-faz2-design.md`
ve plan dosyası (`C:\Users\mta-1\.claude\plans\flickering-giggling-koala.md`).

---

### Task 1: Design + plan docs ✅

- [x] Bu iki dosya + Faz B3 gating bulgusunun dokümantasyonu.

### Task 2: Sipariş Takip → `satin-alma-siparistakip.html`

- [ ] Taşı (en bağımsız sekme), `siparisSbdenCamele()` kopyala,
  `gurok_veritabani.js` referansı ekle.
- [ ] Statik grep + tarayıcı testi.
- [ ] Commit.

### Task 3: İade → `satin-alma-iade.html`

- [ ] Taşı, `yeniSiparisNoUret()` + `siparisSbdenCamele()` kopyala.
  Mevcut `siparis_olustur` yetki gatingini (iade-olustur-btn,
  iade-muhasebe-btn) aynen taşı.
- [ ] Statik grep + tarayıcı testi.
- [ ] Commit.

### Task 4: Sipariş Oluştur → `satin-alma-siparisolustur.html`

- [ ] Taşı, `spSifirla`/`filterFirmaDD` ölü kodunu ATLA (taşıma).
  Mevcut `siparis_olustur` yetki gatingini (sp-grupla-btn) aynen taşı.
  Bridge A'nın alıcı tarafını yaz (sessionStorage `sp_devir_satirlar`
  okuma).
- [ ] Statik grep + tarayıcı testi.
- [ ] Commit.

### Task 5: Teklifler → `satin-alma-teklifler.html`

- [ ] Taşı, `ortak-excel.js` ekle, `yeniSiparisNoUret()` kopyala.
  Bridge B'nin alıcı tarafını yaz (`?id=` query param okuma).
  Yetki gatingi İCAT ETME (henüz yok).
- [ ] Statik grep + tarayıcı testi.
- [ ] Commit.

### Task 6: İç Talepler → `satin-alma-talepler.html`

- [ ] Taşı, `onay-motoru.js` + `ortak-excel.js` ekle. Header "➕ Yeni
  Talep" butonu + `stokMinimumKontrolEt()`/`hesaplaYetkiliAsamalar()`
  birlikte taşınır. Mevcut `ic_talep` yetki gatingini aynen taşı.
  Bridge A + B'nin GÖNDEREN tarafını yaz (`talepSipariseDonustur`,
  `teklifIste`).
- [ ] Statik grep + tarayıcı testi + Bridge A/B uçtan uca test.
- [ ] Commit.

### Task 7: `satin-alma.html` → hub sayfası

- [ ] Tüm iş mantığını sil, `muhasebe.html` deseninde 9 kart ile
  değiştir.
- [ ] index.html'den uçtan uca test.
- [ ] Commit.

### Task 8: Rapor

- [ ] Kullanıcıya dosya boyutu karşılaştırması + Faz 2 durumu raporu.
