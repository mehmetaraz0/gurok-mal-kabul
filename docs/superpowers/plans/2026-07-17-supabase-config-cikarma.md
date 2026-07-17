# Supabase Bağlantı Sabitleri — Ortak Dosyaya Çıkarma Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task.

**Goal:** `SB_URL`/`SB_KEY`/`SB_HEADERS`'ı 23 dosyadan tek bir
`supabase-config.js`'e taşımak.

**Architecture:** `ortak.js` deseninin aynısı — `auth-guard.js`'den hemen
sonra, `ortak.js`/`onay-motoru.js`/`efatura-adapter.js`'den ÖNCE yüklenen
yeni bir paylaşılan dosya.

**Tech Stack:** Vanilla HTML/JS — build aracı yok.

## Global Constraints

- `const` olduğu için yerel tanım MUTLAKA silinmeli, aksi halde
  "Identifier has already been declared" hatası oluşur (spec).
- `gurok_mal_kabul.html`/`index.html.html`'e dokunulmaz (spec).

## Task 1: `supabase-config.js` oluştur

- [x] Oluşturuldu (bkz. design doc).
- [ ] Commit.

## Task 2: 23 dosyada rollout

Her dosyada: `<script src="auth-guard.js">`'den sonra, `ortak.js`/
`onay-motoru.js`/`efatura-adapter.js`'den önce
`<script src="supabase-config.js"></script>` eklenir; yerel `const SB_URL/
SB_KEY/SB_HEADERS` 3 satırı silinir. Dosyalar: depo-siparis, gunluk-tuketim,
kullanici-yonetimi, mal-kabul-v2, muhasebe-asistan, muhasebe-banka,
muhasebe-butce, muhasebe-cariler, muhasebe-cek-senet, muhasebe-demirbas,
muhasebe-denetim, muhasebe-edefter, muhasebe-faturalar, muhasebe-hesap-plani,
muhasebe-kur, muhasebe-raporlar, muhasebe-sene-sonu, muhasebe-yevmiye,
muhasebe, satin-alma, stok-takip, trend-raporlama, yetki-yonetimi, index.

- [ ] Her dosyada: ekle + sil + denge kontrolü + commit.

## Task 3: Doğrulama

- [ ] Statik: `grep -c "^const SB_URL="` her dosyada 0 dönmeli.
- [ ] Tarayıcıda 2-3 örnek dosyada login + konsol hatası kontrolü.
- [ ] `git fetch` + rebase + push.
