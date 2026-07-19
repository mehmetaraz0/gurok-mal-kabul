# Mal Kabul — Modülerleştirme Faz 2 Implementation Plan

> **For agentic workers:** Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `mal-kabul-v2.html`'in son 3 parçasını (Liste+Kalite birlikte,
İzleme ayrı) taşımak ve `mal-kabul-v2.html`'i hub sayfasına çevirmek.

**Architecture:** Detaylar için
`docs/superpowers/specs/2026-07-19-malkabul-modulerlestirme-faz2-design.md`
ve plan dosyası (`C:\Users\mta-1\.claude\plans\flickering-giggling-koala.md`).

---

### Task 1: Design + plan docs ✅

- [x] Bu iki dosya.

### Task 2: İzleme → `mal-kabul-izleme.html` ✅

- [x] Taşı (en düşük risk, hiçbir yazma işlemi yok), `mkSbdenCamele()`
  kopyalandı, kendi 2-fetch `loadDB()`. `openDetay(id)` çağrıları
  `location.href='mal-kabul-liste.html?detay='+id` Bridge'ine çevrildi.
- [x] Statik grep + tarayıcı testi.
- [x] Commit (47e7a54).

### Task 3: Liste + Kalite → `mal-kabul-liste.html` ✅

- [x] Taşı (paylaşılan çekirdek bölünmeden birlikte), `?detay=<id>` ve
  `?tab=kalite` bridge alıcıları eklendi. `gTab()` liste/kalite'ye
  indirgendi. `initApp()`'teki hash-yönlendirme bloğu kaldırıldı.
- [x] Statik grep + tarayıcı testi (fabrike kayıtla `openDetay`,
  `?tab=kalite`, `?detay=` bridge'i canlı doğrulandı).
- [x] Commit (4f74b02).

### Task 4: `mal-kabul-v2.html` → hub ✅

- [x] Tüm iş mantığı silinir, 7 kartlık statik hub (satin-alma.html
  deseni).
- [x] Statik grep + tarayıcı testi.
- [x] Commit (713613b).

### Task 5: `index.html` güncelle ✅

- [x] "Raporlar" kartının `url`'i `mal-kabul-izleme.html` olur.
- [x] Tarayıcı testi.
- [x] Commit (ac2a3b5).

### Task 6: Uçtan uca regresyon + rapor ✅

- [x] Liste, Kalite onay+reddet (fonksiyon gövdesinde İzleme referansı
  kalmadığı doğrulandı), İzleme→Liste detay bridge (fabrike kayıtla
  gerçek tıklama + URL doğrulandı), hub kartlarının hepsi (7/7 doğru
  href), index.html linki, 4 dokunulmamış Faz 1 dosyası (SKT/
  Uygunsuzluk/Sipariş Takip/LN Export) konsol hatasız yüklendi.
- [x] Rapor.
