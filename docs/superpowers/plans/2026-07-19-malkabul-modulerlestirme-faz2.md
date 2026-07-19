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

### Task 2: İzleme → `mal-kabul-izleme.html`

- [ ] Taşı (en düşük risk, hiçbir yazma işlemi yok), `mkSbdenCamele()`
  kopyalandı, kendi 2-fetch `loadDB()`. `openDetay(id)` çağrıları
  `location.href='mal-kabul-liste.html?detay='+id` Bridge'ine çevrildi.
- [ ] Statik grep + tarayıcı testi.
- [ ] Commit.

### Task 3: Liste + Kalite → `mal-kabul-liste.html`

- [ ] Taşı (paylaşılan çekirdek bölünmeden birlikte), `?detay=<id>` ve
  `?tab=kalite` bridge alıcıları eklendi. `gTab()` liste/kalite'ye
  indirgendi. `initApp()`'teki hash-yönlendirme bloğu kaldırıldı.
- [ ] Statik grep + tarayıcı testi.
- [ ] Commit.

### Task 4: `mal-kabul-v2.html` → hub

- [ ] Tüm iş mantığı silinir, 7 kartlık statik hub (satin-alma.html
  deseni).
- [ ] Statik grep + tarayıcı testi.
- [ ] Commit.

### Task 5: `index.html` güncelle

- [ ] "Raporlar" kartının `url`'i `mal-kabul-izleme.html` olur.
- [ ] Tarayıcı testi.
- [ ] Commit.

### Task 6: Uçtan uca regresyon + rapor

- [ ] Liste, Kalite onay+reddet, İzleme→Liste detay bridge, hub
  kartlarının hepsi, index.html linki.
- [ ] Rapor.
