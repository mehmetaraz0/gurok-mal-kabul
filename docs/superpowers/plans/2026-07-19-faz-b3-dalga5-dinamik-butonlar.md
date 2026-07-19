# Faz B3 Dalga 5 — Dinamik Şablon Butonlarının Yetkiye Bağlanması Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Dalga 1-4'te "kapsam dışı" bırakılan, JS `innerHTML` şablon literalleri içinde dinamik render edilen yazma butonlarını (statik `disabled` HTML deseni bunlara uygulanamıyordu) gerçek yetkiye bağlamak.

**Architecture:** İki katmanlı savunma: (1) her hedef JS fonksiyonunun EN BAŞINA bir yetki bekçisi (`if(!['kayit','tam'].includes(YETKI_HARITASI['modul'])){toast(...);return;}`) eklenir — bu, butonun kaç farklı yerden tetiklendiğine bakmaksızın (bazı aksiyonlar birden fazla şablon konumundan çağrılıyor) TEK ve güvenilir bir kapı sağlar. (2) Mümkün olan her yerde (buton basit bir `<button>` etiketiyse, iç içe `.map()` render'ı içindeki dinamik `<div onclick>` DEĞİLSE) şablon string'ine `${['kayit','tam'].includes(YETKI_HARITASI['modul'])?'':'disabled'}` eklenerek görsel geri bildirim de sağlanır. Fonksiyon-seviyesi bekçi HER ZAMAN uygulanır (birincil savunma); buton-seviyesi `disabled` ek bir UX katmanıdır, atlanabilir (örn. bir arama sonucu dropdown'ındaki `<div onclick>` — div'ler `disabled` desteklemez, bu yüzden sadece fonksiyon bekçisiyle korunur).

Gerçek güvenlik zaten RLS ile sağlanıyor (Faz B0-B4) — bu dalga da öncekiler gibi UI tutarlılığı katmanı, ama fonksiyon-bekçisi deseni saf `disabled`'dan daha sağlam çünkü render zamanlamasından bağımsız çalışır.

`muhasebe-sene-sonu.html` bu dalgada YETKI_HARITASI'yı İLK KEZ alıyor (Dalga 4'te kapsam dışı bırakılmıştı, `sene_sonu_kapama` modülü artık seed edildi) — bu dosyada state değişkeni + init'te `kullaniciYetkileriGetir()` çağrısı da eklenir.

**Tech Stack:** Vanilla JS, raw `fetch()`. Build aracı/test çerçevesi yok — doğrulama grep + manuel kod okuma + kullanıcının tarayıcıda uçtan uca testi.

## Global Constraints

- Her hedef fonksiyonun EN BAŞINA (ilk satır olarak) yetki bekçisi eklenir — fonksiyonun mevcut ilk satırından ÖNCE, yeni bir satır olarak.
- Bekçi mesajı tutarlı: `toast('⚠️ Bu işlem için yetkiniz yok');return;`
- Basit, tekil `<button>` şablonlarına `disabled` ternary'si de eklenir. İç içe `.map()` render'ı içindeki `<div onclick>` gibi `disabled` DESTEKLEMEYEN elemanlar SADECE fonksiyon bekçisiyle korunur, dokunulmaz.
- `satin-alma.html`, `muhasebe-denetim.html`, `muhasebe-kur.html` zaten `YETKI_HARITASI` state değişkenine ve init'te dolduran koda sahip (Dalga 3/4) — YENİDEN eklenmez, sadece kullanılır.
- `muhasebe-sene-sonu.html` YETKI_HARITASI'ya sahip DEĞİL — bu dosyada state değişkeni + init'te `kullaniciYetkileriGetir()` çağrısı eklenir (Dalga 1-4'teki standart desen).
- Modül eşlemesi: `talepSipariseDonustur`/`teklifIste`/`teklifTedarikciEkle`/`tedarikciTeklifKaydet`/`teklifExcelYukle`/`teklifSecilenleriSiparisDonustur` → `siparis_olustur`. `kalemExcelYukle` → `ic_talep`. `donemDurumDegistir` → `donem_kilitleme`. `bugunuSifirla` → `doviz_manuel`. `donemiKapat`/`kapanmisYiliGeriAl` → `sene_sonu_kapama`.
- `talepKararVer` (Onayla/Reddet) BİLEREK bu dalganın KAPSAMI DIŞINDA — zaten kendi başına daha ayrıntılı bir yetki mekanizmasına (`kullaniciAsamaYetkiliMi()`/`yetkili` değişkeni, onay-aşaması bazlı) sahip; buna genel modül kontrolü eklemek gereksiz/çakışmalı olur.
- Şema/RLS değişikliği yok — sadece 4 dosya.

---

### Task 1: `satin-alma.html`

**Files:**
- Modify: `satin-alma.html:883-884` (Teklif İste / Siparişe Dönüştür butonları)
- Modify: `satin-alma.html:889` (kalem Excel Yükle butonu)
- Modify: `satin-alma.html:919-920` (talepSipariseDonustur bekçisi)
- Modify: `satin-alma.html:954-955` (kalemExcelYukle bekçisi)
- Modify: `satin-alma.html:1028-1029` (teklifIste bekçisi)
- Modify: `satin-alma.html:1111-1112` (teklifTedarikciEkle bekçisi)
- Modify: `satin-alma.html:1149` (teklif Excel Yükle butonu)
- Modify: `satin-alma.html:1155` (dinamik firma-ekle butonu, .map() içinde)
- Modify: `satin-alma.html:1213` (tedarikciTeklifKaydet Kaydet butonu)
- Modify: `satin-alma.html:1232-1233` (tedarikciTeklifKaydet bekçisi)
- Modify: `satin-alma.html:1288-1289` (teklifExcelYukle bekçisi)
- Modify: `satin-alma.html:1415` (teklifSecilenleriSiparisDonustur butonu)
- Modify: `satin-alma.html:1420-1421` (teklifSecilenleriSiparisDonustur bekçisi)

**Interfaces:**
- Consumes: `YETKI_HARITASI` (zaten satin-alma.html'de global state olarak mevcut, Dalga 3'te eklendi — YENİDEN tanımlanmaz).
- Produces: (yok)

**Bu görevin kapsamı DIŞINDA kalanlar (dokunulmaz):** `talepKararVer` (Onayla/Reddet, satır ~878-879) — kendi `yetkili` mekanizması var. Satır 1178'deki arama-dropdown'ı (`<div onclick="teklifTedarikciEkle(...)">`) — `disabled` desteklemiyor, `teklifTedarikciEkle`'nin kendi bekçisi (Step 5) zaten koruyor, ayrıca dokunulmaz.

- [ ] **Step 1: Teklif İste / Siparişe Dönüştür butonlarına disabled ternary ekle**

`satin-alma.html:883-884`'teki mevcut kod:

```html
        <button class="btn btn-gray btn-sm" onclick="teklifIste('${id}')">📨 Teklif İste</button>
        <button class="btn btn-info btn-sm" onclick="talepSipariseDonustur('${id}')">📦 Siparişe Dönüştür</button>
```

Şununla değiştir:

```html
        <button class="btn btn-gray btn-sm" onclick="teklifIste('${id}')" ${['kayit','tam'].includes(YETKI_HARITASI['siparis_olustur'])?'':'disabled'}>📨 Teklif İste</button>
        <button class="btn btn-info btn-sm" onclick="talepSipariseDonustur('${id}')" ${['kayit','tam'].includes(YETKI_HARITASI['siparis_olustur'])?'':'disabled'}>📦 Siparişe Dönüştür</button>
```

- [ ] **Step 2: kalem Excel Yükle butonuna disabled ternary ekle**

`satin-alma.html:889`'daki mevcut satır:

```html
        <button class="btn btn-gray btn-sm" onclick="_kalemExcelAktifTalepId='${id}';document.getElementById('kalem-excel-input').click()">📥 Excel'den Yükle</button>
```

Şununla değiştir:

```html
        <button class="btn btn-gray btn-sm" onclick="_kalemExcelAktifTalepId='${id}';document.getElementById('kalem-excel-input').click()" ${['kayit','tam'].includes(YETKI_HARITASI['ic_talep'])?'':'disabled'}>📥 Excel'den Yükle</button>
```

- [ ] **Step 3: talepSipariseDonustur fonksiyonuna yetki bekçisi ekle**

`satin-alma.html:919-920`'deki mevcut kod:

```js
async function talepSipariseDonustur(id){
  const t=DB.talepler[id];if(!t)return;
```

Şununla değiştir:

```js
async function talepSipariseDonustur(id){
  if(!['kayit','tam'].includes(YETKI_HARITASI['siparis_olustur'])){toast('⚠️ Bu işlem için yetkiniz yok');return;}
  const t=DB.talepler[id];if(!t)return;
```

- [ ] **Step 4: kalemExcelYukle fonksiyonuna yetki bekçisi ekle**

`satin-alma.html:954-955`'teki mevcut kod:

```js
async function kalemExcelYukle(event,talepId){
  const file=event.target.files[0];if(!file)return;event.target.value='';
```

Şununla değiştir:

```js
async function kalemExcelYukle(event,talepId){
  if(!['kayit','tam'].includes(YETKI_HARITASI['ic_talep'])){toast('⚠️ Bu işlem için yetkiniz yok');return;}
  const file=event.target.files[0];if(!file)return;event.target.value='';
```

- [ ] **Step 5: teklifIste fonksiyonuna yetki bekçisi ekle**

`satin-alma.html:1028-1029`'daki mevcut kod:

```js
async function teklifIste(talepId){
  const t=DB.talepler[talepId];if(!t)return;
```

Şununla değiştir:

```js
async function teklifIste(talepId){
  if(!['kayit','tam'].includes(YETKI_HARITASI['siparis_olustur'])){toast('⚠️ Bu işlem için yetkiniz yok');return;}
  const t=DB.talepler[talepId];if(!t)return;
```

- [ ] **Step 6: teklifTedarikciEkle fonksiyonuna yetki bekçisi ekle**

`satin-alma.html:1111-1112`'deki mevcut kod:

```js
async function teklifTedarikciEkle(teklifTalepId,firmaAd,firmaKodu){
  if(!firmaAd)return;
```

Şununla değiştir:

```js
async function teklifTedarikciEkle(teklifTalepId,firmaAd,firmaKodu){
  if(!['kayit','tam'].includes(YETKI_HARITASI['siparis_olustur'])){toast('⚠️ Bu işlem için yetkiniz yok');return;}
  if(!firmaAd)return;
```

- [ ] **Step 7: teklif Excel Yükle butonuna disabled ternary ekle**

`satin-alma.html:1149`'daki mevcut satır:

```html
      <button class="btn btn-sm btn-gray" onclick="document.getElementById('teklif-excel-input').click()">📥 Excel'den Yükle</button>
```

Şununla değiştir:

```html
      <button class="btn btn-sm btn-gray" onclick="document.getElementById('teklif-excel-input').click()" ${['kayit','tam'].includes(YETKI_HARITASI['siparis_olustur'])?'':'disabled'}>📥 Excel'den Yükle</button>
```

- [ ] **Step 8: dinamik firma-ekle butonuna (oneriler.map() içinde) disabled ternary ekle**

`satin-alma.html:1155`'teki mevcut satır:

```js
      ${oneriler.length?`<div style="display:flex;flex-wrap:wrap;gap:6px;margin-bottom:8px">${oneriler.map(f=>`<button class="btn btn-sm btn-gray" onclick="teklifTedarikciEkle('${id}','${escapeHtml(f.ad).replace(/'/g,"\\'")}','${f.kod||''}')">➕ ${escapeHtml(f.ad)}</button>`).join('')}</div>`:''}
```

Şununla değiştir:

```js
      ${oneriler.length?`<div style="display:flex;flex-wrap:wrap;gap:6px;margin-bottom:8px">${oneriler.map(f=>`<button class="btn btn-sm btn-gray" onclick="teklifTedarikciEkle('${id}','${escapeHtml(f.ad).replace(/'/g,"\\'")}','${f.kod||''}')" ${['kayit','tam'].includes(YETKI_HARITASI['siparis_olustur'])?'':'disabled'}>➕ ${escapeHtml(f.ad)}</button>`).join('')}</div>`:''}
```

- [ ] **Step 9: tedarikciTeklifKaydet Kaydet butonuna disabled ternary ekle**

`satin-alma.html:1212-1215`'teki mevcut kod:

```js
    <div class="brow">
      <button class="btn btn-gray" onclick="kModal('mTedarikciTeklif')">İptal</button>
      <button class="btn btn-success" onclick="tedarikciTeklifKaydet('${tedarikciTeklifId}')">💾 Kaydet</button>
    </div>`;
```

Şununla değiştir:

```js
    <div class="brow">
      <button class="btn btn-gray" onclick="kModal('mTedarikciTeklif')">İptal</button>
      <button class="btn btn-success" onclick="tedarikciTeklifKaydet('${tedarikciTeklifId}')" ${['kayit','tam'].includes(YETKI_HARITASI['siparis_olustur'])?'':'disabled'}>💾 Kaydet</button>
    </div>`;
```

- [ ] **Step 10: tedarikciTeklifKaydet fonksiyonuna yetki bekçisi ekle**

`satin-alma.html:1232-1233`'teki mevcut kod:

```js
async function tedarikciTeklifKaydet(tedarikciTeklifId){
  const bulunan=teklifBulByTedarikciId(tedarikciTeklifId);if(!bulunan)return;
```

Şununla değiştir:

```js
async function tedarikciTeklifKaydet(tedarikciTeklifId){
  if(!['kayit','tam'].includes(YETKI_HARITASI['siparis_olustur'])){toast('⚠️ Bu işlem için yetkiniz yok');return;}
  const bulunan=teklifBulByTedarikciId(tedarikciTeklifId);if(!bulunan)return;
```

- [ ] **Step 11: teklifExcelYukle fonksiyonuna yetki bekçisi ekle**

`satin-alma.html:1288-1289`'daki mevcut kod:

```js
async function teklifExcelYukle(event,teklifTalepId){
  const file=event.target.files[0];if(!file)return;event.target.value='';
```

Şununla değiştir:

```js
async function teklifExcelYukle(event,teklifTalepId){
  if(!['kayit','tam'].includes(YETKI_HARITASI['siparis_olustur'])){toast('⚠️ Bu işlem için yetkiniz yok');return;}
  const file=event.target.files[0];if(!file)return;event.target.value='';
```

- [ ] **Step 12: teklifSecilenleriSiparisDonustur butonuna disabled ternary ekle**

`satin-alma.html:1415`'teki mevcut satır:

```js
    ${tk.durum==='acik'?`<button class="btn btn-success btn-block" onclick="teklifSecilenleriSiparisDonustur('${teklifTalepId}')">📦 Seçilenleri Siparişe Dönüştür</button>`:''}
```

Şununla değiştir:

```js
    ${tk.durum==='acik'?`<button class="btn btn-success btn-block" onclick="teklifSecilenleriSiparisDonustur('${teklifTalepId}')" ${['kayit','tam'].includes(YETKI_HARITASI['siparis_olustur'])?'':'disabled'}>📦 Seçilenleri Siparişe Dönüştür</button>`:''}
```

- [ ] **Step 13: teklifSecilenleriSiparisDonustur fonksiyonuna yetki bekçisi ekle**

`satin-alma.html:1420-1421`'deki mevcut kod:

```js
async function teklifSecilenleriSiparisDonustur(teklifTalepId){
  const tk=DB.teklifler[teklifTalepId];if(!tk)return;
```

Şununla değiştir:

```js
async function teklifSecilenleriSiparisDonustur(teklifTalepId){
  if(!['kayit','tam'].includes(YETKI_HARITASI['siparis_olustur'])){toast('⚠️ Bu işlem için yetkiniz yok');return;}
  const tk=DB.teklifler[teklifTalepId];if(!tk)return;
```

- [ ] **Step 14: Grep ile doğrula**

```bash
grep -c "Bu işlem için yetkiniz yok" satin-alma.html
```

Expected: 7 (7 fonksiyon bekçisi: talepSipariseDonustur, kalemExcelYukle, teklifIste, teklifTedarikciEkle, tedarikciTeklifKaydet, teklifExcelYukle, teklifSecilenleriSiparisDonustur).

- [ ] **Step 15: Commit**

```bash
cd "C:\Users\USER\Projects\gurok-mal-kabul"
git add satin-alma.html
git -c user.name="mehmetaraz0" -c user.email="mehmetaraz868@gmail.com" commit -m "feat: satin-alma.html dinamik butonlar gerçek yetkiye bağlandı (Faz B3 Dalga 5)"
```

---

### Task 2: `muhasebe-denetim.html`

**Files:**
- Modify: `muhasebe-denetim.html:245-247` (dönem Aç/Kapat butonu)
- Modify: `muhasebe-denetim.html:277-278` (donemDurumDegistir bekçisi)

**Interfaces:**
- Consumes: `YETKI_HARITASI` (zaten mevcut, Dalga 4'te eklendi — YENİDEN tanımlanmaz).
- Produces: (yok)

- [ ] **Step 1: Dönem Aç/Kapat butonuna disabled ternary ekle**

`muhasebe-denetim.html:245-247`'deki mevcut kod:

```js
        <button class="btn btn-sm ${d.durum==='kapali'?'btn-success':'btn-warning'}" onclick="donemDurumDegistir('${d.id}','${d.durum==='kapali'?'acik':'kapali'}')">
          ${d.durum==='kapali'?'Aç':'Kapat'}
        </button>
```

Şununla değiştir:

```js
        <button class="btn btn-sm ${d.durum==='kapali'?'btn-success':'btn-warning'}" onclick="donemDurumDegistir('${d.id}','${d.durum==='kapali'?'acik':'kapali'}')" ${['kayit','tam'].includes(YETKI_HARITASI['donem_kilitleme'])?'':'disabled'}>
          ${d.durum==='kapali'?'Aç':'Kapat'}
        </button>
```

- [ ] **Step 2: donemDurumDegistir fonksiyonuna yetki bekçisi ekle**

`muhasebe-denetim.html:277-278`'deki mevcut kod:

```js
async function donemDurumDegistir(id,yeniDurum){
  const d=donemler[id];if(!d)return;
```

Şununla değiştir:

```js
async function donemDurumDegistir(id,yeniDurum){
  if(!['kayit','tam'].includes(YETKI_HARITASI['donem_kilitleme'])){toast('⚠️ Bu işlem için yetkiniz yok');return;}
  const d=donemler[id];if(!d)return;
```

- [ ] **Step 3: Grep ile doğrula**

```bash
grep -c "Bu işlem için yetkiniz yok" muhasebe-denetim.html
```

Expected: 1.

- [ ] **Step 4: Commit**

```bash
cd "C:\Users\USER\Projects\gurok-mal-kabul"
git add muhasebe-denetim.html
git -c user.name="mehmetaraz0" -c user.email="mehmetaraz868@gmail.com" commit -m "feat: muhasebe-denetim.html dinamik buton gerçek yetkiye bağlandı (Faz B3 Dalga 5)"
```

---

### Task 3: `muhasebe-kur.html`

**Files:**
- Modify: `muhasebe-kur.html:179` (Bugünkü kaydı sıfırla butonu)
- Modify: `muhasebe-kur.html:231-232` (bugunuSifirla bekçisi)

**Interfaces:**
- Consumes: `YETKI_HARITASI` (zaten mevcut, Dalga 4'te eklendi — YENİDEN tanımlanmaz).
- Produces: (yok)

- [ ] **Step 1: Bugünkü kaydı sıfırla butonuna disabled ternary ekle**

`muhasebe-kur.html:179`'daki mevcut satır:

```js
    const sifirlaBtn=`<button onclick="bugunuSifirla()" style="background:none;border:1px solid currentColor;color:inherit;border-radius:14px;padding:3px 10px;font-size:11px;font-weight:600;cursor:pointer;margin-left:8px">🗑️ Bugünkü kaydı sıfırla</button>`;
```

Şununla değiştir:

```js
    const sifirlaBtn=`<button onclick="bugunuSifirla()" style="background:none;border:1px solid currentColor;color:inherit;border-radius:14px;padding:3px 10px;font-size:11px;font-weight:600;cursor:pointer;margin-left:8px" ${['kayit','tam'].includes(YETKI_HARITASI['doviz_manuel'])?'':'disabled'}>🗑️ Bugünkü kaydı sıfırla</button>`;
```

- [ ] **Step 2: bugunuSifirla fonksiyonuna yetki bekçisi ekle**

`muhasebe-kur.html:231-232`'deki mevcut kod:

```js
async function bugunuSifirla(){
  const today=new Date();
```

Şununla değiştir:

```js
async function bugunuSifirla(){
  if(!['kayit','tam'].includes(YETKI_HARITASI['doviz_manuel'])){toast('⚠️ Bu işlem için yetkiniz yok');return;}
  const today=new Date();
```

- [ ] **Step 3: Grep ile doğrula**

```bash
grep -c "Bu işlem için yetkiniz yok" muhasebe-kur.html
```

Expected: 1.

- [ ] **Step 4: Commit**

```bash
cd "C:\Users\USER\Projects\gurok-mal-kabul"
git add muhasebe-kur.html
git -c user.name="mehmetaraz0" -c user.email="mehmetaraz868@gmail.com" commit -m "feat: muhasebe-kur.html dinamik buton gerçek yetkiye bağlandı (Faz B3 Dalga 5)"
```

---

### Task 4: `muhasebe-sene-sonu.html`

**Files:**
- Modify: `muhasebe-sene-sonu.html:81` (state değişkeni)
- Modify: `muhasebe-sene-sonu.html:272` (Onayla ve Dönemi Kapat butonu)
- Modify: `muhasebe-sene-sonu.html:287-289` (donemiKapat bekçisi)
- Modify: `muhasebe-sene-sonu.html:367` (Geri Al butonu)
- Modify: `muhasebe-sene-sonu.html:373-375` (kapanmisYiliGeriAl bekçisi)
- Modify: `muhasebe-sene-sonu.html:419-423` (init IIFE)

**Interfaces:**
- Consumes: `kullaniciYetkileriGetir()` (`auth-guard.js`, zaten mevcut, değiştirilmez).
- Produces: (yok)

Bu dosya Dalga 4'te YÜKSEK RİSKLİ (yıl kapama) + TAMAMEN DİNAMİK olduğu için kapsam dışı bırakılmıştı. `sene_sonu_kapama` modülü artık `yetki_matrisi`'nde seed edildi (grup_finans/mali_isler_mdr/muhasebe_mdr=tam, grup_direktor/gm/it_admin=goruntule) — bu dosya İLK KEZ YETKI_HARITASI alıyor.

- [ ] **Step 1: State değişkeni ekle**

`muhasebe-sene-sonu.html:81`'deki mevcut satır:

```js
let hesaplar={},yevmiyeler={},kapanmisYillar={};
```

Şununla değiştir:

```js
let hesaplar={},yevmiyeler={},kapanmisYillar={};
let YETKI_HARITASI = {};
```

- [ ] **Step 2: Onayla ve Dönemi Kapat butonuna disabled ternary ekle**

`muhasebe-sene-sonu.html:272`'deki mevcut satır:

```js
      <button class="btn btn-danger btn-block" onclick="donemiKapat()">🔒 Onayla ve Dönemi Kapat</button>
```

Şununla değiştir:

```js
      <button class="btn btn-danger btn-block" onclick="donemiKapat()" ${['kayit','tam'].includes(YETKI_HARITASI['sene_sonu_kapama'])?'':'disabled'}>🔒 Onayla ve Dönemi Kapat</button>
```

- [ ] **Step 3: donemiKapat fonksiyonuna yetki bekçisi ekle**

`muhasebe-sene-sonu.html:287-289`'daki mevcut kod:

```js
async function donemiKapat(){
  const onizleme=window._kapanisOnizleme;
  if(!onizleme)return;
```

Şununla değiştir:

```js
async function donemiKapat(){
  if(!['kayit','tam'].includes(YETKI_HARITASI['sene_sonu_kapama'])){toast('⚠️ Bu işlem için yetkiniz yok');return;}
  const onizleme=window._kapanisOnizleme;
  if(!onizleme)return;
```

- [ ] **Step 4: Geri Al butonuna disabled ternary ekle**

`muhasebe-sene-sonu.html:367`'deki mevcut satır:

```js
      <button class="btn btn-gray" style="padding:4px 10px;font-size:11px;min-height:28px" onclick="kapanmisYiliGeriAl(${k.yil})">↩️ Geri Al</button>
```

Şununla değiştir:

```js
      <button class="btn btn-gray" style="padding:4px 10px;font-size:11px;min-height:28px" onclick="kapanmisYiliGeriAl(${k.yil})" ${['kayit','tam'].includes(YETKI_HARITASI['sene_sonu_kapama'])?'':'disabled'}>↩️ Geri Al</button>
```

- [ ] **Step 5: kapanmisYiliGeriAl fonksiyonuna yetki bekçisi ekle**

`muhasebe-sene-sonu.html:373-375`'teki mevcut kod:

```js
async function kapanmisYiliGeriAl(yil){
  if(_geriAliniyor){toast('⏳ Zaten işleniyor, bekleyin...');return;}
  const mesaj=`${yil} yılının kapanışı GERİ ALINACAK.\n\nBu işlem:\n• ${yil} dönem sonu kapanış fişini siler\n• Vergi karşılığı fişini (varsa) siler\n• Net sonuç aktarım fişini siler\n• Dönemi tekrar "açık" duruma getirir\n\nHesap bakiyeleri kapanış öncesi haline döner. Devam edilsin mi?`;
```

Şununla değiştir:

```js
async function kapanmisYiliGeriAl(yil){
  if(!['kayit','tam'].includes(YETKI_HARITASI['sene_sonu_kapama'])){toast('⚠️ Bu işlem için yetkiniz yok');return;}
  if(_geriAliniyor){toast('⏳ Zaten işleniyor, bekleyin...');return;}
  const mesaj=`${yil} yılının kapanışı GERİ ALINACAK.\n\nBu işlem:\n• ${yil} dönem sonu kapanış fişini siler\n• Vergi karşılığı fişini (varsa) siler\n• Net sonuç aktarım fişini siler\n• Dönemi tekrar "açık" duruma getirir\n\nHesap bakiyeleri kapanış öncesi haline döner. Devam edilsin mi?`;
```

- [ ] **Step 6: Init'te YETKI_HARITASI'yı doldur**

`muhasebe-sene-sonu.html:419-423`'teki mevcut kod:

```js
(async function(){
  await loadDB();
  document.getElementById('ss-yil').value=new Date().getFullYear()-1;
  donemDurumGoster();
  renderGecmisKapanislar();
```

Şununla değiştir:

```js
(async function(){
  await loadDB();
  YETKI_HARITASI = await kullaniciYetkileriGetir();
  document.getElementById('ss-yil').value=new Date().getFullYear()-1;
  donemDurumGoster();
  renderGecmisKapanislar();
```

- [ ] **Step 7: Grep ile doğrula**

```bash
grep -c "Bu işlem için yetkiniz yok" muhasebe-sene-sonu.html
grep -n "YETKI_HARITASI" muhasebe-sene-sonu.html
```

Expected: ilk komut 2, ikinci komut en az 5 satır (tanım + init ataması + 4 kullanım).

- [ ] **Step 8: Commit**

```bash
cd "C:\Users\USER\Projects\gurok-mal-kabul"
git add muhasebe-sene-sonu.html
git -c user.name="mehmetaraz0" -c user.email="mehmetaraz868@gmail.com" commit -m "feat: muhasebe-sene-sonu.html dinamik butonlar gerçek yetkiye bağlandı (Faz B3 Dalga 5)"
```

---

### Task 5: Uçtan uca doğrulama

**Files:** (yok — sadece doğrulama)

- [ ] **Step 1: Statik doğrulama**

Task 1-4'ün grep adımlarının temiz geçtiğini teyit et. `git diff` ile `talepKararVer`'e (kasıtlı olarak kapsam dışı) hiç dokunulmadığını doğrula.

- [ ] **Step 2: Kullanıcıya manuel test adımlarını bildir**

Kullanıcının tarayıcıda doğrulaması gereken akış:
1. `satinalma` rolüyle (siparis_olustur=kayit) → Teklif İste, Siparişe Dönüştür, Tedarikçi Teklif Kaydet, Seçilenleri Siparişe Dönüştür, firma-ekle butonları aktif olmalı.
2. Sadece görüntüle yetkili biriyle → aynı butonlar pasif olmalı VE tıklanırsa (devtools'tan zorla aktifleştirilse bile) "Bu işlem için yetkiniz yok" toast'ı çıkıp işlem durmalı.
3. `muhasebe_mdr` ile → Dönem Aç/Kapat, Bugünkü Kaydı Sıfırla, Onayla ve Dönemi Kapat, Geri Al aktif olmalı.
4. `muhasebe` (sadece goruntule sene_sonu_kapama'da yok) ile → Onayla ve Dönemi Kapat / Geri Al pasif olmalı.
5. Herhangi bir hata/kırılma olursa bildir.

- [ ] **Step 3: Kullanıcıdan onay al**

"Test ettim, çalışıyor" onayını bekle, ardından push kararını sor.
