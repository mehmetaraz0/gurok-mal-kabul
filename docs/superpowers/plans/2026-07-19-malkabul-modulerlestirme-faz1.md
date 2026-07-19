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

### Task 2: Sipariş Takip → `mal-kabul-siparistakip.html` ✅

- [x] Taşı (en bağımsız, modal yok), `siparisSbdenCamele()` + `OTEL_KISA`
  kopyalandı, kendi `siparisler` sorgusu.
- [x] Statik grep + tarayıcı testi.
- [x] Commit (c956c8a).
- Not: canlı test sırasında `siparisler`/`mal_kabuller` tablolarının
  artık anon-key SELECT'i engellediği görüldü (paralel oturumun RLS
  çalışması genişlemiş) — kalan tüm Faz 1 görevleri bu kısıtlama
  altında statik doğrulama + konsol-hatasız yükleme ile ilerledi.

### Task 3: SKT Takip → `mal-kabul-skt.html` ✅

- [x] Taşı, hafif `urunler?select=kod,ad` fetch.
- [x] `mal-kabul-v2.html`: tabbtn (bskt rozeti dahil) → link, `initApp()`
  içindeki `renderSkt();` satırı silindi.
- [x] Statik grep + tarayıcı testi.
- [x] Commit (3d72eb3).

### Task 4: LN Export → `mal-kabul-lnexport.html` ✅

- [x] Taşı, `mkSbdenCamele()` + `OTEL_KISA` kopyalandı.
  `Object.values(malKabuller)` → kendi tarih-aralığı sorgusu
  (`malKabulleriGetir()` helper).
- [x] `mal-kabul-v2.html`: `initApp()`'teki `exp-bas`/`exp-bit`
  varsayılan doldurma satırları silindi.
- [x] Statik grep + tarayıcı testi.
- [x] Commit (7bc2df6).

### Task 5: Uygunsuzluk → `mal-kabul-uygunsuzluk.html` ✅

- [x] Taşı, `OTEL_ISIMLERI` kopyalandı. `uygunsuzlukYazdir`'daki lazy
  mk-sorgusu (`mkHafifBilgiGetir()`) `mkSbdenCamele` şekline uyduruldu.
  `uygunsuzlukKaydet()`'teki `loadDB()` çağrısı kaldırıldı.
- [x] `mal-kabul-v2.html`: **`kaliteReddet()`'teki `renderUygun();`
  çağrısı silindi** (kritik).
- [x] Statik grep + **Kalite Reddet canlı regresyon testi**:
  `kaliteReddet.toString()` artık `renderUygun` içermiyor, fabrike
  edilmiş bir `malKabuller` kaydıyla gerçek çağrı hatasız tamamlandı.
- [x] Commit (70c2b42).

### Task 6: Uçtan uca regresyon + rapor ✅

- [x] Liste, Kalite, İzleme (3 alt-sekme) gerçek tarayıcıda test edildi
  — konsol hatası yok.
- [x] index.html "Raporlar" kartının `#izleme` hash'i doğrulandı
  (`tab-esleme` doğru açılıyor).
- [x] `sessionStorage` handoff'u (`gurok_malkabul_siparisNo`) doğrulandı
  — anahtar doğru okunup temizleniyor.
- [x] `mal-kabul-v2.html`: 2370 → 1754 satır.
- [x] Rapor + `gurok_mal_kabul.html` silme kararı için ayrı onay istendi.
