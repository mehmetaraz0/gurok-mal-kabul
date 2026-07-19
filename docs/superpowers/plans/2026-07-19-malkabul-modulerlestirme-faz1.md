# Mal Kabul — Modülerleştirme Faz 1 Implementation Plan

> **For agentic workers:** Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `mal-kabul-v2.html`'in 4 bağımsız sekmesini (Sipariş Takip,
SKT Takip, LN Export, Uygunsuzluk) ayrı dosyalara taşımak; Liste/Kalite/
İzleme ile çalışır durumda kalan `mal-kabul-v2.html`'i küçültmek
(hub'a çevirmeden).

**Architecture:** Detaylar için
`docs/superpowers/specs/2026-07-19-malkabul-modulerlestirme-faz1-design.md`
ve plan dosyası (`C:\Users\mta-1\.claude\plans\flickering-giggling-koala.md`).

---

### Task 1: Design + plan docs ✅

- [x] Bu iki dosya.

### Task 2: Sipariş Takip → `mal-kabul-siparistakip.html`

- [ ] Taşı (en bağımsız, modal yok), `siparisSbdenCamele()` + `OTEL_KISA`
  kopyala, kendi `siparisler` sorgusu.
- [ ] Statik grep + tarayıcı testi. Liste'deki sipariş arama/otomatik-
  doldurma kodunun (siparisler cache kullanıyor) bozulmadığını doğrula.
- [ ] Commit.

### Task 3: SKT Takip → `mal-kabul-skt.html`

- [ ] Taşı, hafif `urunler?select=kod,ad` fetch.
- [ ] `mal-kabul-v2.html`: tabbtn (bskt rozeti dahil) → link, `initApp()`
  içindeki `renderSkt();` satırını sil.
- [ ] Statik grep + tarayıcı testi.
- [ ] Commit.

### Task 4: LN Export → `mal-kabul-lnexport.html`

- [ ] Taşı, `mkSbdenCamele()` + `OTEL_KISA` kopyala.
  `Object.values(malKabuller)` → kendi tarih-aralığı sorgusu
  (`mal_kabuller?durum=eq.onaylandi&tarih=gte...&tarih=lte...&select=
  *,mal_kabul_urunleri(*)`).
- [ ] `mal-kabul-v2.html`: `initApp()`'teki `exp-bas`/`exp-bit`
  varsayılan doldurma satırlarını sil.
- [ ] Statik grep + tarayıcı testi — CSV ve F.22 Excel export'u eski
  davranışla karşılaştır.
- [ ] Commit.

### Task 5: Uygunsuzluk → `mal-kabul-uygunsuzluk.html`

- [ ] Taşı, `OTEL_ISIMLERI` kopyala. `uygunsuzlukYazdir`'daki lazy
  mk-sorgusu `mal_kabuller?id=eq.<id>&select=firma_ad,otel_id,
  mal_kabul_urunleri(urun_kodu,miktar,birim)` + `mkSbdenCamele`
  şekline uydurma. `uygunsuzlukKaydet()`'teki `loadDB()` çağrısını
  kaldır (sadece `renderUygun()`).
- [ ] `mal-kabul-v2.html`: **`kaliteReddet()`'teki `renderUygun();`
  çağrısını sil** (kritik).
- [ ] Statik grep + tarayıcı testi + **Kalite Reddet canlı test**
  (kritik regresyon noktası).
- [ ] Commit.

### Task 6: Uçtan uca regresyon + rapor

- [ ] Liste (yeni form + geçmiş), Kalite (onay VE reddet), İzleme (3
  alt-sekme) gerçek tarayıcıda test.
- [ ] index.html "Raporlar" kartının `#izleme` hash'i doğru çalışıyor mu.
- [ ] `mal-kabul-v2.html`'in yeni satır sayısı ölçümü.
- [ ] Rapor + `gurok_mal_kabul.html` silme kararı için ayrı onay iste.
