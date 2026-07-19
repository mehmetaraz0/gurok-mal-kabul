# Faz B3 Dalga 4 — Kalan Muhasebe Sayfaları Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `muhasebe-cariler.html` pilotunda kanıtlanmış buton-seviyesi yetki desenini, Dalga 1'de kapsanmayan 9 muhasebe sayfasından statik (dinamik/şablon-render edilmemiş) yazma butonu içeren 4'üne uygulamak: `muhasebe-hesap-plani.html`, `muhasebe-yevmiye.html`, `muhasebe-denetim.html`, `muhasebe-kur.html`.

**Architecture:** Kapsam belirleme taraması yapıldı (9 dosya). Sonuç:
- **Salt-okunur, gate edilecek bir şey yok:** `muhasebe-asistan.html`, `muhasebe-raporlar.html`, `muhasebe.html` (hub) — bu 3 dosya bu dalgada DEĞİŞMEZ.
- **Tamamen dinamik + yüksek riskli, bu dalganın kapsamı dışında:** `muhasebe-sene-sonu.html` (yıl kapama/geri alma) — HER İKİ yazma butonu da (`donemiKapat()`, `kapanmisYiliGeriAl()`) JS şablon literalleri içinde render ediliyor, statik HTML'de değil. Statik-buton deseni bu dosyaya UYGULANAMAZ — ayrı bir tasarım/uygulama kararı gerektiriyor, bu dalgaya dahil edilmedi.
- **Yetki satırı eksik, gate edilirse gerçek kullanıcıları kilitler, bu dalganın kapsamı dışında:** `muhasebe-edefter.html` — `yetki_matrisi`'de `e_defter` modülü için SADECE `sistem_admin=tam` satırı var, başka HİÇBİR rol için satır yok (curl ile doğrulandı). Bu sayfa şimdi gate edilirse, bugün bu özelliği (Kurum Bilgileri Kaydet) serbestçe kullanan gerçek muhasebe personeli (muhasebe_mdr, mali_isler_mdr, grup_finans vb.) tamamen kilitlenir — Faz B2'de `demirbaslar`/`cek_senetler`/`butce_kayitlari` için yakalanan AYNI tuzak. Önce yetki satırları seed edilmeli, bu dalgaya dahil edilmedi.
- **Bu dalganın gerçek kapsamı — 4 dosya, hepsi statik buton + pilotla aynı gösterme/gizleme deseni ya da tek-Kaydet deseni:**
  - `muhasebe-hesap-plani.html` — Kaydet + Sil (pilotla BİREBİR aynı yapı: `h-sil-btn` zaten var, `style="display:none"`, gösterme satırı `document.getElementById('h-sil-btn').style.display='inline-flex'` şeklinde koşulsuz).
  - `muhasebe-yevmiye.html` — Taslak + Onayla (AYNI `yevmiyeKaydet()` fonksiyonu, farklı boolean argüman — muhasebe-faturalar.html'deki Taslak/Kaydet ikilisiyle AYNI desen) + Sil (`y-sil-btn` zaten var).
  - `muhasebe-denetim.html` — tek Kaydet butonu (Dönem Oluştur). NOT: bu dosyadaki `donemDurumDegistir()` (dönem açma/kapama) dinamik render ediliyor — kapsam dışı.
  - `muhasebe-kur.html` — tek Kaydet butonu (Manuel Kur). NOT: bu dosyadaki `bugunuSifirla()` dinamik render ediliyor — kapsam dışı.

**Tech Stack:** Vanilla JS, raw `fetch()`. Build aracı/test çerçevesi yok — doğrulama grep + manuel kod okuma + kullanıcının tarayıcıda uçtan uca testi.

## Global Constraints

- Gate edilen TÜM butonlar HTML'de `disabled` ile başlar (fail-closed default).
- Sil butonlarının MEVCUT gizleme mantığı (yeni kayıt formunda `style.display='none'`) DEĞİŞMEZ — sadece "düzenle" modundaki GÖSTERME satırı yetkiye bağlanır (pilotla aynı desen).
- Modül eşlemesi: `muhasebe-hesap-plani.html`→`hesap_plani` (Kaydet+Sil aynı modül). `muhasebe-yevmiye.html`→Taslak ve Sil→`yevmiye_fis_giris`, Onayla→`yevmiye_fis_onay` (Dalga 1'deki `muhasebe-faturalar.html` deseniyle AYNI mantık: Sil, "temel giriş" modülüyle eşleşir, "özel aksiyon" modülüyle değil). `muhasebe-denetim.html`→`donem_kilitleme`. `muhasebe-kur.html`→`doviz_manuel`.
- `yetki_matrisi` seed kontrolü yapıldı (curl ile) — `hesap_plani`/`yevmiye_fis_giris`/`yevmiye_fis_onay`/`donem_kilitleme`/`doviz_manuel` modüllerinde gerçek satırlar mevcut (`muhasebe`/`muhasebe_mdr`/`mali_isler_mdr`/`grup_finans`/`cost_control_mdr`/`sistem_admin` gibi roller için), kilitlenme riski yok. `muhasebe-edefter.html` bu kontrolü GEÇEMEDİĞİ için kapsam dışı bırakıldı (yukarıda açıklandı).
- Dinamik (şablon-render edilmiş) butonlara dokunulmaz: `muhasebe-denetim.html`'deki `donemDurumDegistir()`, `muhasebe-kur.html`'deki `bugunuSifirla()`.
- Şema/RLS değişikliği yok — sadece 4 dosya.

---

### Task 1: `muhasebe-hesap-plani.html`

**Files:**
- Modify: `muhasebe-hesap-plani.html:267-268` (Sil/Kaydet butonları)
- Modify: `muhasebe-hesap-plani.html:278` (state değişkeni)
- Modify: `muhasebe-hesap-plani.html:1065` (Sil butonu gösterme satırı)
- Modify: `muhasebe-hesap-plani.html:1159-1168` (init IIFE)

**Interfaces:**
- Consumes: `kullaniciYetkileriGetir()` (`auth-guard.js`, zaten mevcut, değiştirilmez).
- Produces: (yok)

- [ ] **Step 1: Kaydet butonuna id ekle**

`muhasebe-hesap-plani.html:265-269`'daki mevcut kod:

```html
    <div class="brow">
      <button class="btn btn-gray" onclick="kModal('mHesap')">İptal</button>
      <button class="btn btn-danger" id="h-sil-btn" onclick="hesapSilModal()" style="display:none">🗑️ Sil</button>
      <button class="btn btn-primary" onclick="hesapKaydet()">💾 Kaydet</button>
    </div>
```

Şununla değiştir:

```html
    <div class="brow">
      <button class="btn btn-gray" onclick="kModal('mHesap')">İptal</button>
      <button class="btn btn-danger" id="h-sil-btn" onclick="hesapSilModal()" style="display:none">🗑️ Sil</button>
      <button class="btn btn-primary" id="h-kaydet-btn" onclick="hesapKaydet()" disabled>💾 Kaydet</button>
    </div>
```

- [ ] **Step 2: State değişkeni ekle**

`muhasebe-hesap-plani.html:278`'deki mevcut satır:

```js
let hesaplar={};
```

Şununla değiştir:

```js
let hesaplar={};
let YETKI_HARITASI = {};
```

- [ ] **Step 3: Sil butonu gösterme satırını yetkiye bağla**

`muhasebe-hesap-plani.html:1065`'teki mevcut satır:

```js
  document.getElementById('h-sil-btn').style.display='inline-flex';
```

Şununla değiştir:

```js
  document.getElementById('h-sil-btn').style.display=['kayit','tam'].includes(YETKI_HARITASI['hesap_plani'])?'inline-flex':'none';
```

- [ ] **Step 4: Init'te Kaydet butonunu yetkiye göre aç**

`muhasebe-hesap-plani.html:1159-1168`'deki mevcut kod:

```js
(async function(){
  await loadDB();
  if(Object.keys(hesaplar).length===0){
    toast('📥 Standart THP yükleniyor...',4000);
    await thpYukle(true);
    await gurokYukle(true);
  } else {
    renderTablo();
  }
})();
```

Şununla değiştir:

```js
(async function(){
  await loadDB();
  if(Object.keys(hesaplar).length===0){
    toast('📥 Standart THP yükleniyor...',4000);
    await thpYukle(true);
    await gurokYukle(true);
  } else {
    renderTablo();
  }
  YETKI_HARITASI = await kullaniciYetkileriGetir();
  document.getElementById('h-kaydet-btn').disabled = !['kayit','tam'].includes(YETKI_HARITASI['hesap_plani']);
})();
```

- [ ] **Step 5: Grep ile doğrula**

```bash
grep -n 'id="h-kaydet-btn"\|YETKI_HARITASI' muhasebe-hesap-plani.html
```

Expected: id bulunmalı, `YETKI_HARITASI` en az 4 yerde geçmeli.

- [ ] **Step 6: Commit**

```bash
cd "C:\Users\USER\Projects\gurok-mal-kabul"
git add muhasebe-hesap-plani.html
git -c user.name="mehmetaraz0" -c user.email="mehmetaraz868@gmail.com" commit -m "feat: muhasebe-hesap-plani.html buton görünürlüğü gerçek yetkiye bağlandı (Faz B3 Dalga 4)"
```

---

### Task 2: `muhasebe-yevmiye.html`

**Files:**
- Modify: `muhasebe-yevmiye.html:196-200` (Sil/Taslak/Onayla butonları)
- Modify: `muhasebe-yevmiye.html:216` (state değişkeni)
- Modify: `muhasebe-yevmiye.html:437` (Sil butonu gösterme satırı)
- Modify: `muhasebe-yevmiye.html:813-825` (init IIFE)

**Interfaces:**
- Consumes: `kullaniciYetkileriGetir()` (`auth-guard.js`, zaten mevcut, değiştirilmez).
- Produces: (yok)

- [ ] **Step 1: Taslak/Onayla/Sil butonlarına id ekle**

`muhasebe-yevmiye.html:195-200`'deki mevcut kod:

```html
    <div class="brow" style="margin-top:10px">
      <button class="btn btn-gray" onclick="kModal('mYevmiye')">İptal</button>
      <button class="btn btn-danger btn-sm" id="y-sil-btn" onclick="yevmiyeSil()" style="display:none">🗑️</button>
      <button class="btn btn-gray btn-sm" onclick="yevmiyeKaydet(false)">📝 Taslak</button>
      <button class="btn btn-primary" onclick="yevmiyeKaydet(true)">✅ Onayla</button>
    </div>
```

Şununla değiştir:

```html
    <div class="brow" style="margin-top:10px">
      <button class="btn btn-gray" onclick="kModal('mYevmiye')">İptal</button>
      <button class="btn btn-danger btn-sm" id="y-sil-btn" onclick="yevmiyeSil()" style="display:none">🗑️</button>
      <button class="btn btn-gray btn-sm" id="y-taslak-btn" onclick="yevmiyeKaydet(false)" disabled>📝 Taslak</button>
      <button class="btn btn-primary" id="y-onayla-btn" onclick="yevmiyeKaydet(true)" disabled>✅ Onayla</button>
    </div>
```

- [ ] **Step 2: State değişkeni ekle**

`muhasebe-yevmiye.html:216`'daki mevcut satır:

```js
let yevmiyeler={},hesapPlani={};
```

Şununla değiştir:

```js
let yevmiyeler={},hesapPlani={};
let YETKI_HARITASI = {};
```

- [ ] **Step 3: Sil butonu gösterme satırını yetkiye bağla**

`muhasebe-yevmiye.html:437`'deki mevcut satır:

```js
  document.getElementById('y-sil-btn').style.display='flex';
```

Şununla değiştir:

```js
  document.getElementById('y-sil-btn').style.display=['kayit','tam'].includes(YETKI_HARITASI['yevmiye_fis_giris'])?'flex':'none';
```

Sil, Taslak ile AYNI temel giriş modülüne (`yevmiye_fis_giris`) bağlanır — `yevmiye_fis_onay` DEĞİL (Dalga 1'deki `muhasebe-faturalar.html`'de Sil'in `fatura_giris`'e bağlanıp `odeme_yapma`'ya bağlanmamasıyla aynı mantık).

- [ ] **Step 4: Init'te Taslak/Onayla butonlarını farklı modüllerle yetkiye göre aç**

`muhasebe-yevmiye.html:813-825`'teki mevcut kod:

```js
(async function(){
  await loadDB();
  const today=new Date().toISOString().split('T')[0];
  const ayBasi=new Date();ayBasi.setDate(1);
  const ayBasiStr=ayBasi.toISOString().split('T')[0];
  document.getElementById('yev-bas').value=ayBasiStr;
  document.getElementById('yev-bit').value=today;
  document.getElementById('kebir-bas').value=ayBasiStr;
  document.getElementById('kebir-bit').value=today;
  document.getElementById('mizan-bas').value=ayBasiStr;
  document.getElementById('mizan-bit').value=today;
  renderYevmiye();
})();
```

Şununla değiştir:

```js
(async function(){
  await loadDB();
  const today=new Date().toISOString().split('T')[0];
  const ayBasi=new Date();ayBasi.setDate(1);
  const ayBasiStr=ayBasi.toISOString().split('T')[0];
  document.getElementById('yev-bas').value=ayBasiStr;
  document.getElementById('yev-bit').value=today;
  document.getElementById('kebir-bas').value=ayBasiStr;
  document.getElementById('kebir-bit').value=today;
  document.getElementById('mizan-bas').value=ayBasiStr;
  document.getElementById('mizan-bit').value=today;
  renderYevmiye();
  YETKI_HARITASI = await kullaniciYetkileriGetir();
  document.getElementById('y-taslak-btn').disabled = !['kayit','tam'].includes(YETKI_HARITASI['yevmiye_fis_giris']);
  document.getElementById('y-onayla-btn').disabled = !['kayit','tam'].includes(YETKI_HARITASI['yevmiye_fis_onay']);
})();
```

- [ ] **Step 5: Grep ile doğrula**

```bash
grep -n 'id="y-taslak-btn"\|id="y-onayla-btn"\|YETKI_HARITASI' muhasebe-yevmiye.html
```

Expected: her iki id de bulunmalı, `YETKI_HARITASI` en az 5 yerde geçmeli.

- [ ] **Step 6: Commit**

```bash
cd "C:\Users\USER\Projects\gurok-mal-kabul"
git add muhasebe-yevmiye.html
git -c user.name="mehmetaraz0" -c user.email="mehmetaraz868@gmail.com" commit -m "feat: muhasebe-yevmiye.html buton görünürlüğü gerçek yetkiye bağlandı (Faz B3 Dalga 4)"
```

---

### Task 3: `muhasebe-denetim.html`

**Files:**
- Modify: `muhasebe-denetim.html:111` (Dönem Oluştur butonu)
- Modify: `muhasebe-denetim.html:122` (state değişkeni)
- Modify: `muhasebe-denetim.html:308-311` (init IIFE)

**Interfaces:**
- Consumes: `kullaniciYetkileriGetir()` (`auth-guard.js`, zaten mevcut, değiştirilmez).
- Produces: (yok)

Bu dosyada bir Sil-butonu göster/gizle mantığı YOK. `donemDurumDegistir()` (dönem açma/kapama, dinamik render) kapsam DIŞINDA — dokunulmaz.

- [ ] **Step 1: Dönem Oluştur butonuna id ekle**

`muhasebe-denetim.html:111`'deki mevcut satır:

```html
      <button class="btn btn-primary btn-block" style="margin-top:10px" onclick="donemOlustur()">💾 Dönem Oluştur</button>
```

Şununla değiştir:

```html
      <button class="btn btn-primary btn-block" id="donem-olustur-btn" style="margin-top:10px" onclick="donemOlustur()" disabled>💾 Dönem Oluştur</button>
```

- [ ] **Step 2: State değişkeni ekle**

`muhasebe-denetim.html:122`'deki mevcut satır:

```js
let auditLogs={},donemler={};
```

Şununla değiştir:

```js
let auditLogs={},donemler={};
let YETKI_HARITASI = {};
```

- [ ] **Step 3: Init'te butonu yetkiye göre aç**

`muhasebe-denetim.html:308-311`'deki mevcut kod:

```js
(async function(){
  await loadDB();
  renderLog();
})();
```

Şununla değiştir:

```js
(async function(){
  await loadDB();
  renderLog();
  YETKI_HARITASI = await kullaniciYetkileriGetir();
  document.getElementById('donem-olustur-btn').disabled = !['kayit','tam'].includes(YETKI_HARITASI['donem_kilitleme']);
})();
```

- [ ] **Step 4: Grep ile doğrula**

```bash
grep -n 'id="donem-olustur-btn"\|YETKI_HARITASI' muhasebe-denetim.html
```

Expected: id bulunmalı, `YETKI_HARITASI` en az 3 yerde geçmeli.

- [ ] **Step 5: Commit**

```bash
cd "C:\Users\USER\Projects\gurok-mal-kabul"
git add muhasebe-denetim.html
git -c user.name="mehmetaraz0" -c user.email="mehmetaraz868@gmail.com" commit -m "feat: muhasebe-denetim.html buton görünürlüğü gerçek yetkiye bağlandı (Faz B3 Dalga 4)"
```

---

### Task 4: `muhasebe-kur.html`

**Files:**
- Modify: `muhasebe-kur.html:99` (Manuel Kur Kaydet butonu)
- Modify: `muhasebe-kur.html:121` (state değişkeni)
- Modify: `muhasebe-kur.html:403-406` (init IIFE)

**Interfaces:**
- Consumes: `kullaniciYetkileriGetir()` (`auth-guard.js`, zaten mevcut, değiştirilmez).
- Produces: (yok)

Bu dosyada bir Sil-butonu göster/gizle mantığı YOK. `bugunuSifirla()` (dinamik render) kapsam DIŞINDA — dokunulmaz.

- [ ] **Step 1: Kaydet butonuna id ekle**

`muhasebe-kur.html:99`'daki mevcut satır:

```html
        <button class="btn btn-primary btn-block" style="margin-top:6px" onclick="manuelKurKaydet()">💾 Kaydet</button>
```

Şununla değiştir:

```html
        <button class="btn btn-primary btn-block" id="mk-kaydet-btn" style="margin-top:6px" onclick="manuelKurKaydet()" disabled>💾 Kaydet</button>
```

- [ ] **Step 2: State değişkeni ekle**

`muhasebe-kur.html:121`'deki mevcut satır:

```js
let gunlukKurlar={};
```

Şununla değiştir:

```js
let gunlukKurlar={};
let YETKI_HARITASI = {};
```

- [ ] **Step 3: Init'te butonu yetkiye göre aç**

`muhasebe-kur.html:403-406`'daki mevcut kod:

```js
(async function(){
  await loadDB();
  render();
})();
```

Şununla değiştir:

```js
(async function(){
  await loadDB();
  render();
  YETKI_HARITASI = await kullaniciYetkileriGetir();
  document.getElementById('mk-kaydet-btn').disabled = !['kayit','tam'].includes(YETKI_HARITASI['doviz_manuel']);
})();
```

- [ ] **Step 4: Grep ile doğrula**

```bash
grep -n 'id="mk-kaydet-btn"\|YETKI_HARITASI' muhasebe-kur.html
```

Expected: id bulunmalı, `YETKI_HARITASI` en az 3 yerde geçmeli.

- [ ] **Step 5: Commit**

```bash
cd "C:\Users\USER\Projects\gurok-mal-kabul"
git add muhasebe-kur.html
git -c user.name="mehmetaraz0" -c user.email="mehmetaraz868@gmail.com" commit -m "feat: muhasebe-kur.html buton görünürlüğü gerçek yetkiye bağlandı (Faz B3 Dalga 4)"
```

---

### Task 5: Uçtan uca doğrulama

**Files:** (yok — sadece doğrulama)

- [ ] **Step 1: Statik doğrulama**

Task 1-4'ün grep adımlarının temiz geçtiğini teyit et. `git diff` ile SADECE belirtilen bölgelerin değiştiğini doğrula. `muhasebe-yevmiye.html`'de Sil'in `yevmiye_fis_giris`'e (Onayla'nın `yevmiye_fis_onay`'ına DEĞİL) bağlandığını özellikle tekrar kontrol et.

- [ ] **Step 2: Kullanıcıya manuel test adımlarını bildir**

Kullanıcının tarayıcıda doğrulaması gereken akış:
1. `muhasebe` rolüyle (çoğu modülde kayıt yetkisi) → hesap-plani Kaydet, yevmiye Taslak, denetim Dönem Oluştur, kur Kaydet AKTİF olmalı; yevmiye Onayla PASİF olmalı (muhasebe rolünün `yevmiye_fis_onay` yetkisi yok).
2. `muhasebe_mdr` rolüyle (tam yetki çoğu modülde) → yevmiye Onayla dahil TÜM butonlar aktif olmalı.
3. Sadece görüntüle yetkili biriyle → tüm butonlar pasif, Sil butonları (hesap-plani, yevmiye) hiç görünmemeli.
4. Herhangi bir hata/kırılma olursa bildir.

- [ ] **Step 3: Kullanıcıdan onay al**

"Test ettim, çalışıyor" onayını bekle, ardından push kararını sor.
