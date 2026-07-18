# Excel Toplu Veri Yönetimi — Dalga 2 Yayılım Implementation Plan

> **For agentic workers:** Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `ortak-excel.js` motorunu `cariler`, `demirbaslar`,
`cek_senetler`'e yaymak ve RFQ'nun mevcut bespoke Excel akışını aynı
motöre yükseltmek.

**Architecture:** Detaylar için
`docs/superpowers/specs/2026-07-18-excel-dalga2-yayilim-design.md`.

---

### Task 0: SQL hazırlığı — cariler/demirbaslar/cek_senetler UNIQUE kısıt

- [ ] Kullanıcı Supabase SQL Editor'de tekrar-kontrol + kısıt-ekleme
  SQL'ini çalıştırır (design doc'ta / önceki sohbette verildi).
  **Durum: kullanıcıya iletildi, çalıştırılıp çalıştırılmadığı
  doğrulanmadı** — `on_conflict=kod` / `on_conflict=no,banka,yon`
  bu kısıtlar olmadan Postgres tarafından reddedilir.

### Task 1: `muhasebe-cariler.html` → `cariler` ✅

- [x] Spec + Aktar/Yükle/Uygula + buton + Faz B3 yetki gatingi.
- [x] Sınıflandırma testi (sahte oturumla, 1 yeni satır doğru tespit
  edildi).
- [x] Commit (b5dab90).
- [x] **Canlı yazma testi RLS nedeniyle yapılamadı** — bkz. design
  doc'taki "Beklenmeyen bulgu" bölümü.

### Task 2: `muhasebe-demirbas.html` → `demirbaslar` ✅

- [x] Spec (kategori-türetme mantığıyla) + Aktar/Yükle/Uygula + buton.
- [x] Sınıflandırma testi.
- [x] Commit (694a344).
- [x] Canlı yazma testi RLS nedeniyle yapılamadı (cariler ile aynı
  sebep).

### Task 3: `muhasebe-cek-senet.html` → `cek_senetler` ✅

- [x] Spec (bileşik anahtar no+banka+yon, cariAd auto-create) +
  Aktar/Yükle/Uygula + buton.
- [x] Sınıflandırma testi.
- [x] Commit (8d62cef).
- [x] Canlı yazma testi RLS nedeniyle yapılamadı (cariler ile aynı
  sebep).

### Task 4: RFQ `tedarikci_teklif_kalemleri` yükseltmesi ✅

- [x] `teklifleriExcelAktar`/`teklifExcelYukle`/`teklifExcelUygula`
  `ortak-excel.js` tabanlı versiyonla değiştirildi.
- [x] Uçtan uca canlı test: yeni satır yazma, upsert güncelleme, FK
  hatası, boş fiyat satırı atlama — hepsi doğrulandı, test verisi
  temizlendi.
- [x] Commit (3c9904b).

### Task 5: Rapor ✅

- [x] Kullanıcıya Dalga 2 durumu + RLS bulgusu raporlandı.
