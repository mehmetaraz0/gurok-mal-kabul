# Faz B3 Dalga 2 — stok-takip.html Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `muhasebe-cariler.html` pilotunda kanıtlanmış buton-seviyesi yetki desenini (disabled varsayılan + `YETKI_HARITASI` state + init'te `kullaniciYetkileriGetir()` çağrısı), Dalga 1'den farklı bir sayfa yapısına — `stok-takip.html` — uygulamak.

**Architecture:** `stok-takip.html`, muhasebe sayfalarından farklı olarak TEK bir modüle bağlı (`stok_takip` — `index.html`'deki portal tanımına göre), ve CRUD-liste + Kaydet/Sil ikilisi yerine 6 farklı YAZMA aksiyonuna sahip: Manuel Çıkış Kaydet, Transfer Et, Sayımı Tamamla, LN Raporu Uygula, İade Siparişi Oluştur, ve Sayım Onayla/Reddet (cost_control onay adımı). İlk 5 aksiyon `['kayit','tam']` ile; onay/red ikilisi (Sayım Onayla/Reddet) SADECE `'tam'` ile açılır — bu, `yetki-yonetimi.html`'deki mevcut "Tam (onay/silme dahil)" etiketiyle tutarlıdır ve orijinal Sayım fazının (Sayım Task 5) cost_control-only onay tasarımını buton görünürlüğüne yansıtır.

**Tech Stack:** Vanilla JS, raw `fetch()`. Build aracı/test çerçevesi yok — doğrulama grep + manuel kod okuma + kullanıcının tarayıcıda uçtan uca testi.

## Global Constraints

- Tüm 7 buton HTML'de `disabled` ile başlar (fail-closed — Dalga 1 pilotunda zorunlu kılınan desen).
- Bu sayfada Dalga 1'deki gibi bir "Sil butonu göster/gizle" mantığı YOK — stok-takip.html'de silinebilir bir kayıt listesi yok, sadece yazma aksiyonları var. Bu yüzden hiçbir gösterme/gizleme satırı değişmiyor, sadece butonların `disabled` durumu değişiyor.
- Dosyada SADECE bu planda belirtilen satırlar değişir — dosyanın geri kalanına (özellikle `malKabulOnayKontrolEt` güvenlik ağı, ABC/FEFO/güvenlik-stoğu mantığı) dokunulmaz.
- Şema/RLS değişikliği yok — sadece `stok-takip.html`.
- Modül eşlemesi: TÜM 7 buton `stok_takip` modülüne bağlanır (farklı modüllere BÖLÜNMEZ — muhasebe-faturalar.html'deki iki-modül deseninin AKSİNE, burada `index.html`'in portal tanımında bu sayfa için tek modül var: `moduller: ['stok_takip']`).
- Seviye ayrımı: Manuel Çıkış / Transfer / Sayımı Tamamla / LN Uygula / İade Oluştur → `['kayit','tam'].includes(...)`. Sayım Onayla / Sayım Reddet → `['tam'].includes(...)` (SADECE tam yetki, kayıt yetkisi yetmez).

---

### Task 1: `stok-takip.html`

**Files:**
- Modify: `stok-takip.html:238` (İade Siparişi Oluştur butonu)
- Modify: `stok-takip.html:270` (Sayımı Tamamla butonu)
- Modify: `stok-takip.html:333` (Manuel Çıkış Kaydet butonu)
- Modify: `stok-takip.html:361` (Transfer Et butonu)
- Modify: `stok-takip.html:380-381` (Sayım Reddet/Onayla butonları)
- Modify: `stok-takip.html:397` (LN Uygula butonu)
- Modify: `stok-takip.html:641` (state değişkeni)
- Modify: `stok-takip.html:2192` (init IIFE)

**Interfaces:**
- Consumes: `kullaniciYetkileriGetir()` (`auth-guard.js`, zaten mevcut, değiştirilmez).
- Produces: (yok)

- [ ] **Step 1: İade Siparişi Oluştur butonuna id ekle**

`stok-takip.html:238`'deki mevcut satır:

```html
    <button class="btn btn-danger btn-block" style="margin:4px 0 20px;" onclick="iadeSiparisiOlustur()">↩️ İade Siparişi Oluştur</button>
```

Şununla değiştir:

```html
    <button class="btn btn-danger btn-block" id="iade-olustur-btn" style="margin:4px 0 20px;" onclick="iadeSiparisiOlustur()" disabled>↩️ İade Siparişi Oluştur</button>
```

- [ ] **Step 2: Sayımı Tamamla butonuna id ekle**

`stok-takip.html:270`'deki mevcut satır:

```html
      <button class="btn btn-primary btn-block" style="margin-top:10px" onclick="sayimTamamla()">✅ Sayımı Tamamla</button>
```

Şununla değiştir:

```html
      <button class="btn btn-primary btn-block" id="sayim-tamamla-btn" style="margin-top:10px" onclick="sayimTamamla()" disabled>✅ Sayımı Tamamla</button>
```

- [ ] **Step 3: Manuel Çıkış Kaydet butonuna id ekle**

`stok-takip.html:331-334`'teki mevcut kod:

```html
    <div class="btn-row">
      <button class="btn btn-gray" onclick="closeModal('modal-cikis')">İptal</button>
      <button class="btn btn-danger" onclick="saveCikis()">➖ Kaydet</button>
    </div>
```

Şununla değiştir:

```html
    <div class="btn-row">
      <button class="btn btn-gray" onclick="closeModal('modal-cikis')">İptal</button>
      <button class="btn btn-danger" id="cikis-kaydet-btn" onclick="saveCikis()" disabled>➖ Kaydet</button>
    </div>
```

- [ ] **Step 4: Transfer Et butonuna id ekle**

`stok-takip.html:359-362`'deki mevcut kod:

```html
    <div class="btn-row">
      <button class="btn btn-gray" onclick="closeModal('modal-transfer')">İptal</button>
      <button class="btn btn-info" onclick="saveTransfer()">🔄 Transfer Et</button>
    </div>
```

Şununla değiştir:

```html
    <div class="btn-row">
      <button class="btn btn-gray" onclick="closeModal('modal-transfer')">İptal</button>
      <button class="btn btn-info" id="transfer-kaydet-btn" onclick="saveTransfer()" disabled>🔄 Transfer Et</button>
    </div>
```

- [ ] **Step 5: Sayım Onayla/Reddet butonlarına id ekle**

`stok-takip.html:379-382`'deki mevcut kod:

```html
    <div class="btn-row" style="margin-top:12px">
      <button class="btn btn-danger" onclick="sayimReddet(_sayimAktifOturumId)">❌ Reddet</button>
      <button class="btn btn-success" onclick="sayimOnayla(_sayimAktifOturumId)">✅ Onayla</button>
    </div>
```

Şununla değiştir:

```html
    <div class="btn-row" style="margin-top:12px">
      <button class="btn btn-danger" id="sayim-reddet-btn" onclick="sayimReddet(_sayimAktifOturumId)" disabled>❌ Reddet</button>
      <button class="btn btn-success" id="sayim-onayla-btn" onclick="sayimOnayla(_sayimAktifOturumId)" disabled>✅ Onayla</button>
    </div>
```

- [ ] **Step 6: LN Uygula butonuna id ekle**

`stok-takip.html:395-398`'deki mevcut kod:

```html
    <div class="btn-row">
      <button class="btn btn-gray" onclick="closeModal('modal-ln-kolon')">İptal</button>
      <button class="btn btn-primary" onclick="applyLNRapor()">✅ Uygula</button>
    </div>
```

Şununla değiştir:

```html
    <div class="btn-row">
      <button class="btn btn-gray" onclick="closeModal('modal-ln-kolon')">İptal</button>
      <button class="btn btn-primary" id="ln-uygula-btn" onclick="applyLNRapor()" disabled>✅ Uygula</button>
    </div>
```

- [ ] **Step 7: State değişkeni ekle**

`stok-takip.html:639-641`'deki mevcut kod:

```js
let currentUser  = null;
let aktifDepoId  = 'ANA_DEPO';
let aktifOtelId  = '810';
```

Şununla değiştir:

```js
let currentUser  = null;
let aktifDepoId  = 'ANA_DEPO';
let aktifOtelId  = '810';
let YETKI_HARITASI = {};
```

- [ ] **Step 8: Init'te tüm butonları yetkiye göre aç**

`stok-takip.html:2191-2192`'deki mevcut kod:

```js
  document.getElementById('header-depo-label').textContent=depoAdi(aktifDepoId);
  renderStok();
```

Şununla değiştir:

```js
  document.getElementById('header-depo-label').textContent=depoAdi(aktifDepoId);
  renderStok();

  YETKI_HARITASI = await kullaniciYetkileriGetir();
  const stokYaziYetkisi = ['kayit','tam'].includes(YETKI_HARITASI['stok_takip']);
  const stokTamYetki = YETKI_HARITASI['stok_takip'] === 'tam';
  document.getElementById('iade-olustur-btn').disabled = !stokYaziYetkisi;
  document.getElementById('sayim-tamamla-btn').disabled = !stokYaziYetkisi;
  document.getElementById('cikis-kaydet-btn').disabled = !stokYaziYetkisi;
  document.getElementById('transfer-kaydet-btn').disabled = !stokYaziYetkisi;
  document.getElementById('ln-uygula-btn').disabled = !stokYaziYetkisi;
  document.getElementById('sayim-onayla-btn').disabled = !stokTamYetki;
  document.getElementById('sayim-reddet-btn').disabled = !stokTamYetki;
```

- [ ] **Step 9: Grep ile doğrula**

```bash
grep -n 'id="iade-olustur-btn"\|id="sayim-tamamla-btn"\|id="cikis-kaydet-btn"\|id="transfer-kaydet-btn"\|id="sayim-onayla-btn"\|id="sayim-reddet-btn"\|id="ln-uygula-btn"\|YETKI_HARITASI' stok-takip.html
```

Expected: her 7 id de bulunmalı (her biri `disabled` ile birlikte HTML'de), `YETKI_HARITASI` en az 9 yerde geçmeli (1 tanım + 1 atama + 7 kullanım, `stokTamYetki` ayrıca `YETKI_HARITASI` okur).

- [ ] **Step 10: Commit**

```bash
cd "C:\Users\USER\Projects\gurok-mal-kabul"
git add stok-takip.html
git -c user.name="mehmetaraz0" -c user.email="mehmetaraz868@gmail.com" commit -m "feat: stok-takip.html buton görünürlüğü gerçek yetkiye bağlandı (Faz B3 Dalga 2)"
```

---

### Task 2: Uçtan uca doğrulama

**Files:** (yok — sadece doğrulama)

- [ ] **Step 1: Statik doğrulama**

Task 1'in grep adımının temiz geçtiğini teyit et. `git diff` ile SADECE 8 belirtilen bölgenin değiştiğini, `malKabulOnayKontrolEt`, ABC/FEFO/güvenlik-stoğu ve diğer mantığın dokunulmadığını doğrula.

- [ ] **Step 2: Kullanıcıya manuel test adımlarını bildir**

Kullanıcının tarayıcıda doğrulaması gereken akış:
1. `stok_takip` yetkisi "kayıt" olan biriyle (ör. `depo` rolü) → Manuel Çıkış, Transfer, Sayımı Tamamla, LN Uygula, İade Oluştur butonları AKTİF; Sayım Onayla/Reddet PASİF olmalı.
2. `stok_takip` yetkisi "tam" olan biriyle (ör. `cost_control`) → tüm 7 buton AKTİF olmalı.
3. Sadece "görüntüle" yetkisi olan biriyle → tüm 7 buton PASİF olmalı.
4. Herhangi bir hata/kırılma olursa bildir.

- [ ] **Step 3: Kullanıcıdan onay al**

"Test ettim, çalışıyor" onayını bekle, ardından push kararını sor.
