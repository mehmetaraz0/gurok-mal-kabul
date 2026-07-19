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

### Task 2: Sipariş Takip → `satin-alma-siparistakip.html` ✅

- [x] Taşı (en bağımsız sekme), `siparisSbdenCamele()` kopyala.
- [x] Tarayıcı testi (31 sipariş doğru yüklendi).
- [x] Commit (d7c15ad).

### Task 3: İade → `satin-alma-iade.html` ✅

- [x] Taşı, `yeniSiparisNoUret()` + `siparisSbdenCamele()` + `fmt()`
  kopyala, `gurok_veritabani.js` referansı eklendi. Mevcut
  `siparis_olustur` yetki gatingi aynen taşındı.
- [x] Tarayıcı testi (firma/ürün arama, İade Takip listesi).
- [x] Commit (cc53b37).

### Task 4: Sipariş Oluştur → `satin-alma-siparisolustur.html` ✅

- [x] Taşı, `spSifirla`/`filterFirmaDD` ölü kodu atlandı. Mevcut
  `siparis_olustur` yetki gatingi aynen taşındı. Bridge A'nın alıcı
  tarafı yazıldı (sessionStorage `sp_devir_satirlar`).
- [x] Tarayıcı testi + Bridge A alıcı tarafı sentetik veriyle doğrulandı.
- [x] Commit (5eb9cb3) — ayrıca paralel oturumun hesap-plani/kur
  sayfalarına eklediği yetki gatingine Excel butonları da eklendi.

### Task 5: Teklifler → `satin-alma-teklifler.html` ✅

- [x] Taşı, `ortak-excel.js` + `yeniSiparisNoUret()` + `fmt()` kopyalandı.
  Bridge B'nin alıcı tarafı yazıldı (`?id=` query param).
  Yetki gatingi icat edilmedi (kaynak dosyada da yoktu).
- [x] Tarayıcı testi + Bridge B alıcı tarafı `?id=` ile doğrulandı.
- [x] Commit (dde46db).

### Task 6: İç Talepler → `satin-alma-talepler.html` ✅

- [x] Taşı, `onay-motoru.js` + `ortak-excel.js` + `gurok_veritabani.js`
  ile. Header "➕ Yeni Talep" butonu + `stokMinimumKontrolEt()`/
  `hesaplaYetkiliAsamalar()` birlikte taşındı. Mevcut `ic_talep` yetki
  gatingi aynen taşındı. Bridge A + B'nin gönderen tarafı yazıldı.
- [x] Gerçek Supabase verisiyle uçtan uca test: onaylanmış talep
  oluşturuldu, "Siparişe Dönüştür" ve "Teklif İste" ikisi de gerçek
  akışla doğrulandı, test verisi temizlendi (2 kayıt RLS DELETE
  engeli nedeniyle silinemedi, kapatılıp işaretlendi).
- [x] Commit (3d56283).

### Task 7: `satin-alma.html` → hub sayfası ✅

- [x] Tüm iş mantığı silindi, `muhasebe.html` deseninde 9 kart ile
  değiştirildi (3106 satırdan 89 satıra).
- [x] index.html'den uçtan uca test — 9 kart da doğru dosyaya gidiyor.
- [x] Commit (ca4ffc1).

### Task 8: Rapor ✅

- [x] Kullanıcıya dosya boyutu karşılaştırması + Faz 2 durumu raporu.
