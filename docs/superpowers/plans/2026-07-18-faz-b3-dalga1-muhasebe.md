# Faz B3 Dalga 1 — Muhasebe Sayfaları Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `muhasebe-cariler.html` pilotunda kanıtlanmış buton-seviyesi yetki desenini, kendi tabloları zaten Faz B1/B2'de gerçek RLS'e bağlanmış 5 muhasebe sayfasına (faturalar, demirbaş, çek-senet, banka, bütçe) yaymak.

**Architecture:** Her sayfada aynı desen: modül-yazma butonları (`disabled` HTML attribute'iyle varsayılan pasif) + `YETKI_HARITASI` state değişkeni + init'te `kullaniciYetkileriGetir()` çağrısı + Sil butonunun gösterme satırının yetkiye bağlanması. `muhasebe-faturalar.html` iki ayrı modüle bağlanıyor (Kaydet/Taslak/Sil → `fatura_giris`, Ödeme Kaydet → `odeme_yapma`) çünkü bunlar `yetki_matrisi`'nde gerçekten ayrı modüller.

**Tech Stack:** Vanilla JS, raw `fetch()`. Build aracı/test çerçevesi yok — doğrulama grep + manuel kod okuma + kullanıcının tarayıcıda uçtan uca testi.

## Global Constraints

- Kaydet/Taslak/Ödeme Kaydet butonları HTML'de `disabled` ile başlar (fail-closed — `muhasebe-cariler.html` pilotunda bulunan gerçek regresyondan sonra zorunlu kılındı: JS hiç çalışmasa bile buton pasif kalmalı).
- Sil butonlarının MEVCUT gizleme mantığı (yeni kayıt formunda `style.display='none'`) DEĞİŞMEZ — sadece "düzenle" modunda GÖSTERME satırı yetkiye bağlanır.
- Her dosyada SADECE brief'te belirtilen satırlar değişir — dosyanın geri kalanına dokunulmaz.
- Şema/RLS değişikliği yok — sadece 5 HTML dosyası.

---

### Task 1: `muhasebe-faturalar.html`

**Files:**
- Modify: `muhasebe-faturalar.html:223-228` (Taslak/Kaydet/Sil butonları)
- Modify: `muhasebe-faturalar.html:259-262` (Ödeme Kaydet butonu)
- Modify: `muhasebe-faturalar.html:273` (state değişkeni)
- Modify: `muhasebe-faturalar.html:771` (Sil butonu gösterme satırı)
- Modify: `muhasebe-faturalar.html:1317-1320` (init IIFE)

**Interfaces:**
- Consumes: `kullaniciYetkileriGetir()` (`auth-guard.js`, zaten mevcut).
- Produces: (yok)

- [ ] **Step 1: Taslak/Kaydet/Sil butonlarına id ekle**

`muhasebe-faturalar.html:223-228`'deki mevcut kod:

```html
    <div class="brow" style="margin-top:8px">
      <button class="btn btn-gray" onclick="kModal('mFatura')">İptal</button>
      <button class="btn btn-danger btn-sm" id="f-sil-btn" onclick="faturaSil()" style="display:none">🗑️</button>
      <button class="btn btn-gray btn-sm" onclick="faturaKaydet('taslak')">📝 Taslak</button>
      <button class="btn btn-primary" onclick="faturaKaydet('bekliyor')">✅ Kaydet</button>
    </div>
```

Şununla değiştir:

```html
    <div class="brow" style="margin-top:8px">
      <button class="btn btn-gray" onclick="kModal('mFatura')">İptal</button>
      <button class="btn btn-danger btn-sm" id="f-sil-btn" onclick="faturaSil()" style="display:none">🗑️</button>
      <button class="btn btn-gray btn-sm" id="f-taslak-btn" onclick="faturaKaydet('taslak')" disabled>📝 Taslak</button>
      <button class="btn btn-primary" id="f-kaydet-btn" onclick="faturaKaydet('bekliyor')" disabled>✅ Kaydet</button>
    </div>
```

- [ ] **Step 2: Ödeme Kaydet butonuna id ekle**

`muhasebe-faturalar.html:259-262`'deki mevcut kod:

```html
    <div class="brow">
      <button class="btn btn-gray" onclick="kModal('mOdeme')">İptal</button>
      <button class="btn btn-success" onclick="odemeKaydet()">💳 Ödeme Kaydet</button>
    </div>
```

Şununla değiştir:

```html
    <div class="brow">
      <button class="btn btn-gray" onclick="kModal('mOdeme')">İptal</button>
      <button class="btn btn-success" id="od-kaydet-btn" onclick="odemeKaydet()" disabled>💳 Ödeme Kaydet</button>
    </div>
```

- [ ] **Step 3: State değişkeni ekle**

`muhasebe-faturalar.html:273`'teki mevcut satır:

```js
let alisFilter='tumu',satisFilter='tumu';
```

Şununla değiştir:

```js
let alisFilter='tumu',satisFilter='tumu';
let YETKI_HARITASI = {};
```

- [ ] **Step 4: Sil butonu gösterme satırını yetkiye bağla**

`muhasebe-faturalar.html:771`'deki mevcut satır:

```js
  document.getElementById('f-sil-btn').style.display='flex';
```

Şununla değiştir:

```js
  document.getElementById('f-sil-btn').style.display=['kayit','tam'].includes(YETKI_HARITASI['fatura_giris'])?'flex':'none';
```

- [ ] **Step 5: Init'te butonları yetkiye göre aç**

`muhasebe-faturalar.html:1317-1320`'deki mevcut kod:

```js
(async function(){
  await loadDB();
  renderFaturalar('alis');
})();
```

Şununla değiştir:

```js
(async function(){
  await loadDB();
  renderFaturalar('alis');
  YETKI_HARITASI = await kullaniciYetkileriGetir();
  const faturaYaziYetkisi = ['kayit','tam'].includes(YETKI_HARITASI['fatura_giris']);
  document.getElementById('f-taslak-btn').disabled = !faturaYaziYetkisi;
  document.getElementById('f-kaydet-btn').disabled = !faturaYaziYetkisi;
  document.getElementById('od-kaydet-btn').disabled = !['kayit','tam'].includes(YETKI_HARITASI['odeme_yapma']);
})();
```

- [ ] **Step 6: Grep ile doğrula**

```bash
grep -n 'id="f-taslak-btn"\|id="f-kaydet-btn"\|id="od-kaydet-btn"\|YETKI_HARITASI' muhasebe-faturalar.html
```

Expected: her üç id de bulunmalı, `YETKI_HARITASI` en az 5 yerde geçmeli.

- [ ] **Step 7: Commit**

```bash
cd "C:\Users\USER\Projects\gurok-mal-kabul"
git add muhasebe-faturalar.html
git -c user.name="mehmetaraz0" -c user.email="mehmetaraz868@gmail.com" commit -m "feat: muhasebe-faturalar.html buton görünürlüğü gerçek yetkiye bağlandı (Faz B3 Dalga 1)"
```

---

### Task 2: `muhasebe-demirbas.html`

**Files:**
- Modify: `muhasebe-demirbas.html:162-163` (Sil/Kaydet butonları)
- Modify: `muhasebe-demirbas.html:182` (state değişkeni)
- Modify: `muhasebe-demirbas.html:434` (Sil butonu gösterme satırı)
- Modify: `muhasebe-demirbas.html:697-700` (init IIFE)

**Interfaces:**
- Consumes: `kullaniciYetkileriGetir()` (`auth-guard.js`).
- Produces: (yok)

- [ ] **Step 1: Kaydet butonuna id ekle**

`muhasebe-demirbas.html:162-163`'teki mevcut kod:

```html
      <button class="btn btn-danger btn-sm" id="d-sil-btn" onclick="demirbasSil()" style="display:none">🗑️</button>
      <button class="btn btn-primary" onclick="demirbasKaydet()">💾 Kaydet</button>
```

Şununla değiştir:

```html
      <button class="btn btn-danger btn-sm" id="d-sil-btn" onclick="demirbasSil()" style="display:none">🗑️</button>
      <button class="btn btn-primary" id="d-kaydet-btn" onclick="demirbasKaydet()" disabled>💾 Kaydet</button>
```

- [ ] **Step 2: State değişkeni ekle**

`muhasebe-demirbas.html:182`'deki mevcut satır:

```js
let dbFilter='tumu';
```

Şununla değiştir:

```js
let dbFilter='tumu';
let YETKI_HARITASI = {};
```

- [ ] **Step 3: Sil butonu gösterme satırını yetkiye bağla**

`muhasebe-demirbas.html:434`'teki mevcut satır:

```js
  document.getElementById('d-sil-btn').style.display='flex';
```

Şununla değiştir:

```js
  document.getElementById('d-sil-btn').style.display=['kayit','tam'].includes(YETKI_HARITASI['demirbas_yonetimi'])?'flex':'none';
```

- [ ] **Step 4: Init'te butonu yetkiye göre aç**

`muhasebe-demirbas.html:697-700`'deki mevcut kod:

```js
(async function(){
  await loadDB();
  renderDemirbaslar();
})();
```

Şununla değiştir:

```js
(async function(){
  await loadDB();
  renderDemirbaslar();
  YETKI_HARITASI = await kullaniciYetkileriGetir();
  document.getElementById('d-kaydet-btn').disabled = !['kayit','tam'].includes(YETKI_HARITASI['demirbas_yonetimi']);
})();
```

- [ ] **Step 5: Grep ile doğrula**

```bash
grep -n 'id="d-kaydet-btn"\|YETKI_HARITASI' muhasebe-demirbas.html
```

Expected: id bulunmalı, `YETKI_HARITASI` en az 3 yerde geçmeli.

- [ ] **Step 6: Commit**

```bash
cd "C:\Users\USER\Projects\gurok-mal-kabul"
git add muhasebe-demirbas.html
git -c user.name="mehmetaraz0" -c user.email="mehmetaraz868@gmail.com" commit -m "feat: muhasebe-demirbas.html buton görünürlüğü gerçek yetkiye bağlandı (Faz B3 Dalga 1)"
```

---

### Task 3: `muhasebe-cek-senet.html`

**Files:**
- Modify: `muhasebe-cek-senet.html:169-170` (Sil/Kaydet butonları)
- Modify: `muhasebe-cek-senet.html:189` (state değişkeni)
- Modify: `muhasebe-cek-senet.html:430` (Sil butonu gösterme satırı)
- Modify: `muhasebe-cek-senet.html:619-622` (init IIFE)

**Interfaces:**
- Consumes: `kullaniciYetkileriGetir()` (`auth-guard.js`).
- Produces: (yok)

- [ ] **Step 1: Kaydet butonuna id ekle**

`muhasebe-cek-senet.html:169-170`'deki mevcut kod:

```html
      <button class="btn btn-danger btn-sm" id="k-sil-btn" onclick="kayitSil()" style="display:none">🗑️</button>
      <button class="btn btn-primary" onclick="kayitKaydet()">💾 Kaydet</button>
```

Şununla değiştir:

```html
      <button class="btn btn-danger btn-sm" id="k-sil-btn" onclick="kayitSil()" style="display:none">🗑️</button>
      <button class="btn btn-primary" id="k-kaydet-btn" onclick="kayitKaydet()" disabled>💾 Kaydet</button>
```

- [ ] **Step 2: State değişkeni ekle**

`muhasebe-cek-senet.html:189`'daki mevcut satır:

```js
let alinanFilter='tumu',verilenFilter='tumu';
```

Şununla değiştir:

```js
let alinanFilter='tumu',verilenFilter='tumu';
let YETKI_HARITASI = {};
```

- [ ] **Step 3: Sil butonu gösterme satırını yetkiye bağla**

`muhasebe-cek-senet.html:430`'daki mevcut satır:

```js
  document.getElementById('k-sil-btn').style.display='flex';
```

Şununla değiştir:

```js
  document.getElementById('k-sil-btn').style.display=['kayit','tam'].includes(YETKI_HARITASI['cek_senet_yonetimi'])?'flex':'none';
```

- [ ] **Step 4: Init'te butonu yetkiye göre aç**

`muhasebe-cek-senet.html:619-622`'deki mevcut kod:

```js
(async function(){
  await loadDB();
  renderListe('alinan');
})();
```

Şununla değiştir:

```js
(async function(){
  await loadDB();
  renderListe('alinan');
  YETKI_HARITASI = await kullaniciYetkileriGetir();
  document.getElementById('k-kaydet-btn').disabled = !['kayit','tam'].includes(YETKI_HARITASI['cek_senet_yonetimi']);
})();
```

- [ ] **Step 5: Grep ile doğrula**

```bash
grep -n 'id="k-kaydet-btn"\|YETKI_HARITASI' muhasebe-cek-senet.html
```

Expected: id bulunmalı, `YETKI_HARITASI` en az 3 yerde geçmeli.

- [ ] **Step 6: Commit**

```bash
cd "C:\Users\USER\Projects\gurok-mal-kabul"
git add muhasebe-cek-senet.html
git -c user.name="mehmetaraz0" -c user.email="mehmetaraz868@gmail.com" commit -m "feat: muhasebe-cek-senet.html buton görünürlüğü gerçek yetkiye bağlandı (Faz B3 Dalga 1)"
```

---

### Task 4: `muhasebe-banka.html`

**Files:**
- Modify: `muhasebe-banka.html:194-198` (Hesap Sil/Kaydet butonları)
- Modify: `muhasebe-banka.html:230-233` (Hareket Kaydet butonu)
- Modify: `muhasebe-banka.html:242` (state değişkeni)
- Modify: `muhasebe-banka.html:408` (Sil butonu gösterme satırı)
- Modify: `muhasebe-banka.html:651-659` (init IIFE)

**Interfaces:**
- Consumes: `kullaniciYetkileriGetir()` (`auth-guard.js`).
- Produces: (yok)

- [ ] **Step 1: Hesap Kaydet butonuna id ekle**

`muhasebe-banka.html:194-198`'deki mevcut kod:

```html
    <div class="brow">
      <button class="btn btn-gray" onclick="kModal('mHesap')">İptal</button>
      <button class="btn btn-danger btn-sm" id="h-sil-btn" onclick="hesapSil()" style="display:none">🗑️</button>
      <button class="btn btn-primary" onclick="hesapKaydet()">💾 Kaydet</button>
    </div>
```

Şununla değiştir:

```html
    <div class="brow">
      <button class="btn btn-gray" onclick="kModal('mHesap')">İptal</button>
      <button class="btn btn-danger btn-sm" id="h-sil-btn" onclick="hesapSil()" style="display:none">🗑️</button>
      <button class="btn btn-primary" id="h-kaydet-btn" onclick="hesapKaydet()" disabled>💾 Kaydet</button>
    </div>
```

- [ ] **Step 2: Hareket Kaydet butonuna id ekle**

`muhasebe-banka.html:230-233`'teki mevcut kod:

```html
    <div class="brow">
      <button class="btn btn-gray" onclick="kModal('mHareket')">İptal</button>
      <button class="btn btn-primary" onclick="hareketKaydet()">💾 Kaydet</button>
    </div>
```

Şununla değiştir:

```html
    <div class="brow">
      <button class="btn btn-gray" onclick="kModal('mHareket')">İptal</button>
      <button class="btn btn-primary" id="hr-kaydet-btn" onclick="hareketKaydet()" disabled>💾 Kaydet</button>
    </div>
```

- [ ] **Step 3: State değişkeni ekle**

`muhasebe-banka.html:242`'deki mevcut satır:

```js
let hesaplar={},hareketler={},virmanlar={};
```

Şununla değiştir:

```js
let hesaplar={},hareketler={},virmanlar={};
let YETKI_HARITASI = {};
```

- [ ] **Step 4: Sil butonu gösterme satırını yetkiye bağla**

`muhasebe-banka.html:408`'deki mevcut satır:

```js
  document.getElementById('h-sil-btn').style.display='flex';
```

Şununla değiştir:

```js
  document.getElementById('h-sil-btn').style.display=['kayit','tam'].includes(YETKI_HARITASI['banka_kasa'])?'flex':'none';
```

- [ ] **Step 5: Init'te butonları yetkiye göre aç**

`muhasebe-banka.html:651-659`'daki mevcut kod:

```js
(async function(){
  await loadDB();
  const today=new Date().toISOString().split('T')[0];
  const ayBasi=new Date();ayBasi.setDate(1);
  document.getElementById('har-bas').value=ayBasi.toISOString().split('T')[0];
  document.getElementById('har-bit').value=today;
  document.getElementById('vir-tarih').value=today;
  renderHesaplar();
})();
```

Şununla değiştir:

```js
(async function(){
  await loadDB();
  const today=new Date().toISOString().split('T')[0];
  const ayBasi=new Date();ayBasi.setDate(1);
  document.getElementById('har-bas').value=ayBasi.toISOString().split('T')[0];
  document.getElementById('har-bit').value=today;
  document.getElementById('vir-tarih').value=today;
  renderHesaplar();
  YETKI_HARITASI = await kullaniciYetkileriGetir();
  const bankaYaziYetkisi = ['kayit','tam'].includes(YETKI_HARITASI['banka_kasa']);
  document.getElementById('h-kaydet-btn').disabled = !bankaYaziYetkisi;
  document.getElementById('hr-kaydet-btn').disabled = !bankaYaziYetkisi;
})();
```

- [ ] **Step 6: Grep ile doğrula**

```bash
grep -n 'id="h-kaydet-btn"\|id="hr-kaydet-btn"\|YETKI_HARITASI' muhasebe-banka.html
```

Expected: her iki id de bulunmalı, `YETKI_HARITASI` en az 4 yerde geçmeli.

- [ ] **Step 7: Commit**

```bash
cd "C:\Users\USER\Projects\gurok-mal-kabul"
git add muhasebe-banka.html
git -c user.name="mehmetaraz0" -c user.email="mehmetaraz868@gmail.com" commit -m "feat: muhasebe-banka.html buton görünürlüğü gerçek yetkiye bağlandı (Faz B3 Dalga 1)"
```

---

### Task 5: `muhasebe-butce.html`

**Files:**
- Modify: `muhasebe-butce.html:143-144` (Sil/Kaydet butonları)
- Modify: `muhasebe-butce.html:154` (state değişkeni)
- Modify: `muhasebe-butce.html:409` (Sil butonu gösterme satırı)
- Modify: `muhasebe-butce.html:495-500` (init IIFE)

**Interfaces:**
- Consumes: `kullaniciYetkileriGetir()` (`auth-guard.js`).
- Produces: (yok)

- [ ] **Step 1: Kaydet butonuna id ekle**

`muhasebe-butce.html:143-144`'teki mevcut kod:

```html
      <button class="btn btn-danger btn-sm" id="b-sil-btn" onclick="butceSil()" style="display:none">🗑️</button>
      <button class="btn btn-primary" onclick="butceKaydet()">💾 Kaydet</button>
```

Şununla değiştir:

```html
      <button class="btn btn-danger btn-sm" id="b-sil-btn" onclick="butceSil()" style="display:none">🗑️</button>
      <button class="btn btn-primary" id="b-kaydet-btn" onclick="butceKaydet()" disabled>💾 Kaydet</button>
```

- [ ] **Step 2: State değişkeni ekle**

`muhasebe-butce.html:154`'teki mevcut satır:

```js
let butceler={},hesaplar={},yevmiyeler={};
```

Şununla değiştir:

```js
let butceler={},hesaplar={},yevmiyeler={};
let YETKI_HARITASI = {};
```

- [ ] **Step 3: Sil butonu gösterme satırını yetkiye bağla**

`muhasebe-butce.html:409`'daki mevcut satır:

```js
  document.getElementById('b-sil-btn').style.display='flex';
```

Şununla değiştir:

```js
  document.getElementById('b-sil-btn').style.display=['kayit','tam'].includes(YETKI_HARITASI['butce_yonetimi'])?'flex':'none';
```

- [ ] **Step 4: Init'te butonu yetkiye göre aç**

`muhasebe-butce.html:495-500`'deki mevcut kod:

```js
(async function(){
  await loadDB();
  document.getElementById('rp-yil').value=new Date().getFullYear();
  document.getElementById('rp-ay').value=new Date().getMonth()+1;
  renderRapor();
})();
```

Şununla değiştir:

```js
(async function(){
  await loadDB();
  document.getElementById('rp-yil').value=new Date().getFullYear();
  document.getElementById('rp-ay').value=new Date().getMonth()+1;
  renderRapor();
  YETKI_HARITASI = await kullaniciYetkileriGetir();
  document.getElementById('b-kaydet-btn').disabled = !['kayit','tam'].includes(YETKI_HARITASI['butce_yonetimi']);
})();
```

- [ ] **Step 5: Grep ile doğrula**

```bash
grep -n 'id="b-kaydet-btn"\|YETKI_HARITASI' muhasebe-butce.html
```

Expected: id bulunmalı, `YETKI_HARITASI` en az 3 yerde geçmeli.

- [ ] **Step 6: Commit**

```bash
cd "C:\Users\USER\Projects\gurok-mal-kabul"
git add muhasebe-butce.html
git -c user.name="mehmetaraz0" -c user.email="mehmetaraz868@gmail.com" commit -m "feat: muhasebe-butce.html buton görünürlüğü gerçek yetkiye bağlandı (Faz B3 Dalga 1)"
```

---

### Task 6: Uçtan uca doğrulama

**Files:** (yok — sadece doğrulama)

- [ ] **Step 1: Statik doğrulama**

Task 1-5'in grep adımlarının temiz geçtiğini teyit et. Her dosyada Sil butonunun YENİ kayıt formundaki (`display='none'`) gizleme satırının DEĞİŞMEDİĞİNİ `git diff` ile doğrula — sadece "düzenle" modundaki gösterme satırı değişmeli.

- [ ] **Step 2: Kullanıcıya manuel test adımlarını bildir**

Kullanıcının tarayıcıda doğrulaması gereken akış (5 sayfanın her biri için):
1. `fatura_giris`/`demirbas_yonetimi`/`cek_senet_yonetimi`/`banka_kasa`/`butce_yonetimi` yetkisi "kayıt"/"tam" olan biriyle → Kaydet butonları aktif olmalı.
2. Sadece "görüntüle" yetkisi olan biriyle → Kaydet butonları pasif, Sil hiç görünmemeli.
3. `muhasebe-faturalar.html`'de ayrıca: `odeme_yapma` yetkisi farklı bir kullanıcıyla test edilmeli (Ödeme Kaydet, fatura_giris'ten BAĞIMSIZ çalışmalı).
4. Herhangi bir hata/kırılma olursa bildir.

- [ ] **Step 3: Kullanıcıdan onay al**

"Test ettim, çalışıyor" onayını bekle, ardından push kararını sor.
