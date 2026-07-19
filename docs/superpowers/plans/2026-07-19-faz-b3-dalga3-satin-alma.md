# Faz B3 Dalga 3 — Satın Alma Sayfaları Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `muhasebe-cariler.html` pilotunda kanıtlanmış buton-seviyesi yetki desenini satın alma sayfalarındaki STATİK (dinamik/şablon-render edilmemiş) yazma butonlarına uygulamak.

**Architecture:** Bu dalga Dalga 1/2'den ÖNEMLİ bir şekilde farklı: satın alma sayfalarındaki tablolar (`satin_alma_talepleri`, `teklif_talepleri`, `tedarikci_teklifler` vb.) henüz RLS ile korunmuyor (curl ile anon key kullanılarak doğrulandı — kimliksiz erişimle bile okunabiliyorlar). Yani bu dalga TAMAMEN KOZMETİK: buton gizleme/pasifleştirme gerçek bir güvenlik garantisi SAĞLAMIYOR, sadece yetkisiz kullanıcıya "zaten kullanamayacağın bir butonu gösterme" deneyimini sağlıyor. Kullanıcı bunu bilerek onayladı.

İkinci önemli fark: `satin-alma.html`'deki birçok yazma butonu (Onayla/Reddet, Teklif İste, Siparişe Dönüştür, Tedarikçi Teklif Kaydet, dinamik firma-ekle butonu, dinamik Excel-yükle butonları) STATİK HTML değil — JS fonksiyonları içinde `innerHTML` şablon literalleriyle (`` `...${id}...` ``) her modal açılışında YENİDEN üretiliyor. Dalga 1'de de aynı sebeple dinamik `onayla()` fatura-onay butonları kapsam dışı bırakılmıştı ("farklı bir uygulama deseni gerektirir, henüz inşa edilmedi"). Bu dalga da AYNI kısıtı uyguluyor: SADECE statik HTML'de yaşayan butonlar gate edilir. Dinamik şablon butonları bu dalganın kapsamı DIŞINDA kalır (ayrı bir gelecek iş).

Üçüncü fark: iki dosyada (`satin-alma-fiyatkontrol.html`, `satin-alma.html`) "Muhasebe'ye Gönder" butonları zaten var olan bir ID'ye ve modal-açılışında ÇALIŞAN bir `disabled` SIFIRLAMA mantığına sahip (`fkDetayAc()` / `iadeDetayAc()` içinde, kayıt zaten gönderilmiş mi kontrolüne göre `btn.disabled` YENİDEN atanıyor). Bu satırlar DEĞİŞTİRİLMEZSE, init'te yaptığım yetki-bazlı gating, kullanıcı ilgili detay modalını her açtığında SIFIRLANIR (yetkisi olmayan biri modalı açar açmaz buton yeniden aktif olur) — Dalga 1'de bulunan "fail-open" regresyonuyla AYNI kökten bir risk. Bu yüzden bu iki dosyada, buton HTML'ine `disabled` eklemenin YANINDA, bu iki fonksiyondaki mevcut `disabled` atama satırı da yetki kontrolünü içerecek şekilde DEĞİŞTİRİLİYOR.

**Tech Stack:** Vanilla JS, raw `fetch()`. Build aracı/test çerçevesi yok — doğrulama grep + manuel kod okuma + kullanıcının tarayıcıda uçtan uca testi.

## Global Constraints

- Gate edilen TÜM statik butonlar HTML'de `disabled` ile başlar (fail-closed default).
- `satin-alma-firmalar.html` ve `satin-alma-skorkart.html` bu dalgada DEĞİŞMEZ — ikisi de tamamen salt-okunur sayfalar, hiç yazma butonu içermiyor (araştırmayla doğrulandı).
- Modül eşlemesi (kullanıcı onayıyla, varsayılan seçenek): İade ve Teklif (RFQ) özellikleri için ayrı bir `yetki_matrisi` modül kodu YOK — bu yüzden İade'nin statik butonu `siparis_olustur` modulune dahil edildi (yeni şema/SQL değişikliği gerektirmiyor).
- Modül eşlemesi (net): `satin-alma-fiyatkontrol.html`→`fiyat_kontrol`, `satin-alma-siparisler.html`→`siparis_takip`, `satin-alma.html`'in İç Talepler statik butonları→`ic_talep`, Sipariş Oluştur + İade statik butonları→`siparis_olustur`.
- Dinamik (şablon-render edilmiş, `${...}` interpolasyonlu) butonlar bu dalganın KAPSAMI DIŞINDA — dokunulmaz, gate edilmez. Bunlar: Talep Onayla/Reddet, Teklif İste, Siparişe Dönüştür (talep detayından), kalem-bazlı Excel Yükle (talep detayı içinde), Tedarikçi Teklif Kaydet, Seçilenleri Siparişe Dönüştür (teklif karşılaştırma), teklif Excel Yükle, dinamik firma-ekle butonu.
- `yetki_matrisi` seed kontrolü yapıldı (curl ile) — `ic_talep`/`siparis_olustur`/`siparis_takip`/`fiyat_kontrol` modüllerinde `satinalma`=kayıt, `satinalma_mdr`/`cost_control_mdr`/`sistem_admin`=tam gibi gerçek satırlar mevcut, kilitlenme riski yok.
- Şema/RLS değişikliği yok — sadece 3 dosya (`satin-alma-fiyatkontrol.html`, `satin-alma-siparisler.html`, `satin-alma.html`).

---

### Task 1: `satin-alma-fiyatkontrol.html`

**Files:**
- Modify: `satin-alma-fiyatkontrol.html:91` (Muhasebe'ye Gönder butonu)
- Modify: `satin-alma-fiyatkontrol.html:107-109` (state değişkenleri)
- Modify: `satin-alma-fiyatkontrol.html:308` (fkDetayAc() içindeki disabled sıfırlama satırı — KRİTİK düzeltme)
- Modify: `satin-alma-fiyatkontrol.html:476-480` (init IIFE)

**Interfaces:**
- Consumes: `kullaniciYetkileriGetir()` (`auth-guard.js`, zaten mevcut, değiştirilmez).
- Produces: (yok)

- [ ] **Step 1: Muhasebe'ye Gönder butonuna disabled ekle (id zaten var)**

`satin-alma-fiyatkontrol.html:91`'deki mevcut satır:

```html
      <button class="btn btn-success" style="flex:1" id="fk-muhasebe-btn" onclick="muhasebeGonder()">📤 Muhasebe'ye Gönder</button>
```

Şununla değiştir:

```html
      <button class="btn btn-success" style="flex:1" id="fk-muhasebe-btn" onclick="muhasebeGonder()" disabled>📤 Muhasebe'ye Gönder</button>
```

- [ ] **Step 2: State değişkeni ekle**

`satin-alma-fiyatkontrol.html:107-109`'daki mevcut kod:

```js
let _fkFilter='bekleyen';
let _fkFormlar=[];
let _fkAktifId=null;
```

Şununla değiştir:

```js
let _fkFilter='bekleyen';
let _fkFormlar=[];
let _fkAktifId=null;
let YETKI_HARITASI = {};
```

- [ ] **Step 3: fkDetayAc()'teki disabled sıfırlama satırını yetkiye bağla (KRİTİK)**

`satin-alma-fiyatkontrol.html:307-309`'daki mevcut kod:

```js
  const muhasebeGonderildi=f.fiyatKontrolDurum==='muhasebe';
  document.getElementById('fk-muhasebe-btn').disabled=muhasebeGonderildi;
  document.getElementById('fk-muhasebe-btn').textContent=muhasebeGonderildi?'✅ Muhasebe\'ye Gönderildi':'📤 Muhasebe\'ye Gönder';
```

Şununla değiştir:

```js
  const muhasebeGonderildi=f.fiyatKontrolDurum==='muhasebe';
  document.getElementById('fk-muhasebe-btn').disabled=muhasebeGonderildi || !['kayit','tam'].includes(YETKI_HARITASI['fiyat_kontrol']);
  document.getElementById('fk-muhasebe-btn').textContent=muhasebeGonderildi?'✅ Muhasebe\'ye Gönderildi':'📤 Muhasebe\'ye Gönder';
```

Bu değişiklik olmadan, HTML'deki `disabled` attribute'u kullanıcı herhangi bir fiyat kontrol kaydını her açtığında (`fkDetayAc()` her çalıştığında) SIFIRLANIR ve buton yetkisiz kullanıcı için de aktif hale gelir — bu satır bu riski ortadan kaldırıyor.

- [ ] **Step 4: Init'te YETKI_HARITASI'yı doldur**

`satin-alma-fiyatkontrol.html:476-480`'deki mevcut kod:

```js
(async function(){
  if(!CU) return;
  document.getElementById('hsub').textContent=CU.ad;
  await loadFiyatKontrol();
})();
```

Şununla değiştir:

```js
(async function(){
  if(!CU) return;
  document.getElementById('hsub').textContent=CU.ad;
  YETKI_HARITASI = await kullaniciYetkileriGetir();
  await loadFiyatKontrol();
})();
```

`fk-muhasebe-btn`'in gerçek aktif/pasif durumu her zaman `fkDetayAc()` (Step 3) tarafından belirlendiği için burada ayrıca `.disabled` ataması YAPILMIYOR — HTML'deki statik `disabled` (Step 1) zaten fail-closed varsayılanı sağlıyor, `YETKI_HARITASI`'nın burada doldurulması ise `fkDetayAc()`'in her çalıştığında güncel veriyi okuyabilmesi için yeterli.

- [ ] **Step 5: Grep ile doğrula**

```bash
grep -n 'YETKI_HARITASI\|fk-muhasebe-btn' satin-alma-fiyatkontrol.html
```

Expected: `YETKI_HARITASI` en az 3 yerde (tanım, atama, kullanım), `fk-muhasebe-btn` en az 2 yerde (HTML tanımı `disabled` ile, ve `fkDetayAc()` içindeki güncellenmiş satır).

- [ ] **Step 6: Commit**

```bash
cd "C:\Users\USER\Projects\gurok-mal-kabul"
git add satin-alma-fiyatkontrol.html
git -c user.name="mehmetaraz0" -c user.email="mehmetaraz868@gmail.com" commit -m "feat: satin-alma-fiyatkontrol.html buton görünürlüğü gerçek yetkiye bağlandı (Faz B3 Dalga 3)"
```

---

### Task 2: `satin-alma-siparisler.html`

**Files:**
- Modify: `satin-alma-siparisler.html:107` (Uygula butonu)
- Modify: `satin-alma-siparisler.html:119-121` (state değişkenleri)
- Modify: `satin-alma-siparisler.html:278-283` (init IIFE)

**Interfaces:**
- Consumes: `kullaniciYetkileriGetir()` (`auth-guard.js`, zaten mevcut, değiştirilmez).
- Produces: (yok)

Bu dosyada `fkDetayAc()`/`iadeDetayAc()` tarzı bir disabled-sıfırlama sorunu YOK — "✅ Uygula" butonu statik ve modal her açıldığında yeniden yazılmıyor, bu yüzden Task 1'deki gibi ek bir "kritik düzeltme" adımı gerekmiyor.

- [ ] **Step 1: Uygula butonuna id ekle**

`satin-alma-siparisler.html:107`'deki mevcut satır:

```html
      <button class="btn btn-primary" onclick="applyLNKolon()">✅ Uygula</button>
```

Şununla değiştir:

```html
      <button class="btn btn-primary" id="ln-uygula-btn" onclick="applyLNKolon()" disabled>✅ Uygula</button>
```

- [ ] **Step 2: State değişkeni ekle**

`satin-alma-siparisler.html:119-121`'deki mevcut kod:

```js
let DB={lnSiparisler:{}};
let lnRows=[];
let lnFilter='bekleyen';
```

Şununla değiştir:

```js
let DB={lnSiparisler:{}};
let lnRows=[];
let lnFilter='bekleyen';
let YETKI_HARITASI = {};
```

- [ ] **Step 3: Init'te butonu yetkiye göre aç**

`satin-alma-siparisler.html:278-283`'teki mevcut kod:

```js
(async function(){
  if(!CU) return;
  document.getElementById('hsub').textContent=CU.ad;
  await loadDB();
  renderLN();
})();
```

Şununla değiştir:

```js
(async function(){
  if(!CU) return;
  document.getElementById('hsub').textContent=CU.ad;
  YETKI_HARITASI = await kullaniciYetkileriGetir();
  document.getElementById('ln-uygula-btn').disabled = !['kayit','tam'].includes(YETKI_HARITASI['siparis_takip']);
  await loadDB();
  renderLN();
})();
```

- [ ] **Step 4: Grep ile doğrula**

```bash
grep -n 'ln-uygula-btn\|YETKI_HARITASI' satin-alma-siparisler.html
```

Expected: `ln-uygula-btn` 2 yerde (HTML `disabled` ile + init'teki `.disabled` ataması), `YETKI_HARITASI` en az 3 yerde.

- [ ] **Step 5: Commit**

```bash
cd "C:\Users\USER\Projects\gurok-mal-kabul"
git add satin-alma-siparisler.html
git -c user.name="mehmetaraz0" -c user.email="mehmetaraz868@gmail.com" commit -m "feat: satin-alma-siparisler.html buton görünürlüğü gerçek yetkiye bağlandı (Faz B3 Dalga 3)"
```

---

### Task 3: `satin-alma.html`

**Files:**
- Modify: `satin-alma.html:114` (Talep Excel'den Yükle butonu)
- Modify: `satin-alma.html:151` (Firma Bazlı Grupla butonu)
- Modify: `satin-alma.html:227` (İade Siparişi Oluştur butonu)
- Modify: `satin-alma.html:263` (İade Muhasebe'ye Gönder butonu — id zaten var)
- Modify: `satin-alma.html:306` (Talep Gönder butonu)
- Modify: `satin-alma.html:318` (Seçilenlerden Talep Oluştur butonu)
- Modify: `satin-alma.html:379` (state değişkeni)
- Modify: `satin-alma.html:2333` (iadeDetayAc() içindeki disabled sıfırlama satırı — KRİTİK düzeltme)
- Modify: `satin-alma.html:2552-2559` (init IIFE)

**Interfaces:**
- Consumes: `kullaniciYetkileriGetir()` (`auth-guard.js`, zaten mevcut, değiştirilmez).
- Produces: (yok)

**Bu görevin kapsamı DIŞINDA kalanlar (dinamik şablon butonları, dokunulmaz):** `talepKararVer()` (Onayla/Reddet, satır ~971-972), `teklifIste()`/`talepSipariseDonustur()` (satır ~976-977), kalem-bazlı Excel Yükle (satır ~982), `tedarikciTeklifKaydet()` (satır ~1307), `teklifSecilenleriSiparisDonustur()` (satır ~1508), teklif Excel Yükle (satır ~1242), dinamik firma-ekle butonu (satır ~1248). Bunların hepsi JS `innerHTML` şablon literalleri içinde üretiliyor, statik HTML değil — farklı bir uygulama deseni gerektiriyorlar (Dalga 1'deki dinamik `onayla()` faturası onay butonlarıyla aynı sebep).

- [ ] **Step 1: Talep Excel'den Yükle butonuna id ekle**

`satin-alma.html:112-116`'daki mevcut kod:

```html
    <div class="brow" style="margin-bottom:10px">
      <button class="btn btn-sm btn-gray" onclick="talepleriExcelAktar()">📤 Excel'e Aktar</button>
      <button class="btn btn-sm btn-gray" onclick="document.getElementById('talep-excel-input').click()">📥 Excel'den Yükle</button>
      <input type="file" id="talep-excel-input" accept=".xlsx,.xls" style="display:none" onchange="talepExcelYukle(event)">
    </div>
```

Şununla değiştir:

```html
    <div class="brow" style="margin-bottom:10px">
      <button class="btn btn-sm btn-gray" onclick="talepleriExcelAktar()">📤 Excel'e Aktar</button>
      <button class="btn btn-sm btn-gray" id="talep-excel-yukle-btn" onclick="document.getElementById('talep-excel-input').click()" disabled>📥 Excel'den Yükle</button>
      <input type="file" id="talep-excel-input" accept=".xlsx,.xls" style="display:none" onchange="talepExcelYukle(event)">
    </div>
```

- [ ] **Step 2: Firma Bazlı Grupla butonuna id ekle**

`satin-alma.html:149-152`'deki mevcut kod:

```html
      <div class="brow" style="margin-bottom:16px">
        <button class="btn btn-gray" onclick="spSifirla()">🗑️ Temizle</button>
        <button class="btn btn-primary" onclick="spGrupla()">📦 Firma Bazlı Grupla →</button>
      </div>
```

Şununla değiştir:

```html
      <div class="brow" style="margin-bottom:16px">
        <button class="btn btn-gray" onclick="spSifirla()">🗑️ Temizle</button>
        <button class="btn btn-primary" id="sp-grupla-btn" onclick="spGrupla()" disabled>📦 Firma Bazlı Grupla →</button>
      </div>
```

- [ ] **Step 3: İade Siparişi Oluştur butonuna id ekle**

`satin-alma.html:225-228`'deki mevcut kod:

```html
    <div class="brow" style="margin-bottom:16px">
      <button class="btn btn-gray" onclick="iadeSifirla()">🗑️ Temizle</button>
      <button class="btn btn-danger" onclick="iadeOlustur()">↩️ İade Siparişi Oluştur</button>
    </div>
```

Şununla değiştir:

```html
    <div class="brow" style="margin-bottom:16px">
      <button class="btn btn-gray" onclick="iadeSifirla()">🗑️ Temizle</button>
      <button class="btn btn-danger" id="iade-olustur-btn" onclick="iadeOlustur()" disabled>↩️ İade Siparişi Oluştur</button>
    </div>
```

- [ ] **Step 4: İade Muhasebe'ye Gönder butonuna disabled ekle (id zaten var)**

`satin-alma.html:263`'teki mevcut satır:

```html
      <button class="btn btn-success" style="flex:1" id="iade-muhasebe-btn" onclick="iadeMuhasebeGonder()">📤 Muhasebe'ye Gönder</button>
```

Şununla değiştir:

```html
      <button class="btn btn-success" style="flex:1" id="iade-muhasebe-btn" onclick="iadeMuhasebeGonder()" disabled>📤 Muhasebe'ye Gönder</button>
```

- [ ] **Step 5: Talep Gönder butonuna id ekle**

`satin-alma.html:304-307`'deki mevcut kod:

```html
    <div class="brow" style="margin-top:8px">
      <button class="btn btn-gray" onclick="kModal('mYeniTalep')">İptal</button>
      <button class="btn btn-primary" onclick="ytKaydet()">📤 Talep Gönder</button>
    </div>
```

Şununla değiştir:

```html
    <div class="brow" style="margin-top:8px">
      <button class="btn btn-gray" onclick="kModal('mYeniTalep')">İptal</button>
      <button class="btn btn-primary" id="yt-kaydet-btn" onclick="ytKaydet()" disabled>📤 Talep Gönder</button>
    </div>
```

- [ ] **Step 6: Seçilenlerden Talep Oluştur butonuna id ekle**

`satin-alma.html:316-319`'daki mevcut kod:

```html
    <div class="brow" style="margin-top:10px">
      <button class="btn btn-gray" onclick="kModal('mYenidenSiparis')">Kapat</button>
      <button class="btn btn-primary" onclick="yenidenSiparisOlustur()">📤 Seçilenlerden Talep Oluştur</button>
    </div>
```

Şununla değiştir:

```html
    <div class="brow" style="margin-top:10px">
      <button class="btn btn-gray" onclick="kModal('mYenidenSiparis')">Kapat</button>
      <button class="btn btn-primary" id="yeniden-siparis-btn" onclick="yenidenSiparisOlustur()" disabled>📤 Seçilenlerden Talep Oluştur</button>
    </div>
```

- [ ] **Step 7: State değişkeni ekle**

`satin-alma.html:378-379`'daki mevcut kod:

```js
let CU=null;
let DB={talepler:{},siparisler:{},kullanicilar:[...TUSERS],firmalar:[],teklifler:{}};
```

Şununla değiştir:

```js
let CU=null;
let DB={talepler:{},siparisler:{},kullanicilar:[...TUSERS],firmalar:[],teklifler:{}};
let YETKI_HARITASI = {};
```

- [ ] **Step 8: iadeDetayAc()'teki disabled sıfırlama satırını yetkiye bağla (KRİTİK)**

`satin-alma.html:2331-2334`'teki mevcut kod:

```js
  const gonderildi=!!s.gonderildiMuhasebe;
  const btn=document.getElementById('iade-muhasebe-btn');
  btn.disabled=false;
  btn.textContent=gonderildi?'🔁 Tekrar Gönder (zaten gönderilmişti)':'📤 Muhasebe\'ye Gönder';
```

Şununla değiştir:

```js
  const gonderildi=!!s.gonderildiMuhasebe;
  const btn=document.getElementById('iade-muhasebe-btn');
  btn.disabled=!['kayit','tam'].includes(YETKI_HARITASI['siparis_olustur']);
  btn.textContent=gonderildi?'🔁 Tekrar Gönder (zaten gönderilmişti)':'📤 Muhasebe\'ye Gönder';
```

Bu değişiklik olmadan, `iadeDetayAc()` her çalıştığında (kullanıcı herhangi bir iade kaydını her açtığında) buton koşulsuz `disabled=false` yapılıyordu — yetkisiz kullanıcı için de aktif hale geliyordu. Bu satır bu riski ortadan kaldırıyor.

- [ ] **Step 9: Init'te 5 statik butonu yetkiye göre aç**

`satin-alma.html:2551-2560`'daki mevcut kod:

```js
// ====== INIT ======
(async function(){
  CU = requireLogin();
  if(!CU) return;
  if(!requireRole(CU, ['yonetici','satinalma','depo','cost_control'])) return;
  await loadDB();
  await hesaplaYetkiliAsamalar();
  basla();
  stokMinimumKontrolEt();
})();
```

Şununla değiştir:

```js
// ====== INIT ======
(async function(){
  CU = requireLogin();
  if(!CU) return;
  if(!requireRole(CU, ['yonetici','satinalma','depo','cost_control'])) return;
  YETKI_HARITASI = await kullaniciYetkileriGetir();
  const icTalepYaziYetkisi = ['kayit','tam'].includes(YETKI_HARITASI['ic_talep']);
  const siparisOlusturYaziYetkisi = ['kayit','tam'].includes(YETKI_HARITASI['siparis_olustur']);
  document.getElementById('talep-excel-yukle-btn').disabled = !icTalepYaziYetkisi;
  document.getElementById('yt-kaydet-btn').disabled = !icTalepYaziYetkisi;
  document.getElementById('yeniden-siparis-btn').disabled = !icTalepYaziYetkisi;
  document.getElementById('sp-grupla-btn').disabled = !siparisOlusturYaziYetkisi;
  document.getElementById('iade-olustur-btn').disabled = !siparisOlusturYaziYetkisi;
  await loadDB();
  await hesaplaYetkiliAsamalar();
  basla();
  stokMinimumKontrolEt();
})();
```

`iade-muhasebe-btn`'in gerçek durumu her zaman `iadeDetayAc()` (Step 8) tarafından belirlendiği için burada ayrıca ele alınmıyor — aynı `muhasebe-fiyatkontrol.html` deseninde olduğu gibi.

- [ ] **Step 10: Grep ile doğrula**

```bash
grep -n 'id="talep-excel-yukle-btn"\|id="sp-grupla-btn"\|id="iade-olustur-btn"\|id="yt-kaydet-btn"\|id="yeniden-siparis-btn"\|iade-muhasebe-btn\|YETKI_HARITASI' satin-alma.html
```

Expected: her 5 yeni id de bulunmalı (`disabled` ile birlikte), `iade-muhasebe-btn` 2 yerde (HTML + `iadeDetayAc()`), `YETKI_HARITASI` en az 6 yerde.

- [ ] **Step 11: Commit**

```bash
cd "C:\Users\USER\Projects\gurok-mal-kabul"
git add satin-alma.html
git -c user.name="mehmetaraz0" -c user.email="mehmetaraz868@gmail.com" commit -m "feat: satin-alma.html statik buton görünürlüğü gerçek yetkiye bağlandı (Faz B3 Dalga 3)"
```

---

### Task 4: Uçtan uca doğrulama

**Files:** (yok — sadece doğrulama)

- [ ] **Step 1: Statik doğrulama**

Task 1-3'ün grep adımlarının temiz geçtiğini teyit et. `git diff` ile SADECE belirtilen bölgelerin değiştiğini doğrula. Özellikle Step 3 (Task 1) ve Step 8 (Task 3)'teki "kritik düzeltme" satırlarının doğru uygulandığını — yani `disabled=...` atamasının artık koşulsuz bir değer DEĞİL, `YETKI_HARITASI` okuyan bir ifade olduğunu — tek tek kontrol et.

- [ ] **Step 2: Kullanıcıya manuel test adımlarını bildir**

Kullanıcının tarayıcıda doğrulaması gereken akış:
1. `satinalma` rolüyle (kayıt yetkisi çoğu modülde) → Talep Gönder, Seçilenlerden Talep Oluştur, Talep Excel Yükle, Firma Bazlı Grupla, İade Oluştur butonları AKTİF olmalı.
2. `satin-alma-fiyatkontrol.html`'de bir kayıt aç, Muhasebe'ye Gönder butonunun `satinalma`/`cost_control` gibi kayıt-yetkili biri için aktif, sadece görüntüle yetkili biri için PASİF olduğunu doğrula — özellikle modalı KAPATIP TEKRAR AÇARAK pasif durumun kalıcı olduğunu (sıfırlanmadığını) doğrula.
3. `satin-alma.html`'de bir İade kaydı aç, aynı şekilde Muhasebe'ye Gönder butonunun modal her açılışında doğru yetkiye göre kaldığını (kalıcı, sıfırlanmıyor) doğrula.
4. `satin-alma-siparisler.html`'de Uygula butonunun `siparis_takip` yetkisine göre doğru açılıp kapandığını doğrula.
5. Sadece görüntüle yetkili biriyle → tüm 6+1 buton (fiyatkontrol + siparisler + satin-alma'daki 5) PASİF olmalı.
6. Herhangi bir hata/kırılma olursa bildir.

- [ ] **Step 3: Kullanıcıdan onay al**

"Test ettim, çalışıyor" onayını bekle, ardından push kararını sor.
