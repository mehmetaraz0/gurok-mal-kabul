# Soft-Delete Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `cariler`, `faturalar`, `demirbaslar`, `cek_senetler`, `banka_kasa_hesaplari`, `butce_kayitlari` tablolarına `silindi` bayrağı ekleyip kalıcı `DELETE`'leri `PATCH {silindi:true}`'a çevirmek, `kullanicilar`'ın mevcut `aktif` bayrağını aynı desene bağlamak, ve tüm okuma noktalarına `&silindi=eq.false` filtresi eklemek.

**Architecture:** Her tablo kendi görevi — SQL kolonu (Task 1, kullanıcı çalıştırır) + o tablonun silme fonksiyonu + o tablonun TÜM okuma noktaları (kendi yönetim ekranı dahil) tek pakette. Alt-kayıt DELETE'leri (cari_hareketler, banka_kasa_hareketleri) kaldırılır — üst kayıt artık silinmediği için gereksiz.

**Tech Stack:** Vanilla JS, ham `fetch()` + Supabase REST. Build/test aracı yok — doğrulama grep + kod okuma + kullanıcı testi.

## Global Constraints

- `hesap_plani` bu planın KAPSAMI DIŞINDA — `satin-alma.html`'de de okunuyor, o dosya paralel bir oturumda aktif değişiyor, çakışma riski.
- `yevmiye_kalemleri`/`fatura_kalemleri`/`recete_kalemleri` reinsert DELETE'leri, `doviz_kurlari`, `sene_sonu_kapanislar`/`yevmiye_fisler` (sene-sonu geri-alma) — bunlara DOKUNULMAZ, gerçek "kayıt silme" değiller.
- Rozet/restore arayüzü YOK — her okuma noktasına (kendi yönetim ekranı dahil) aynı `&silindi=eq.false` filtresi eklenir, mevcut kullanıcı deneyimi birebir korunur.
- Her silme fonksiyonunda `confirm()` metni, buton, `auditLogYaz` çağrısı DEĞİŞMEZ — sadece alttaki `fetch` çağrısı `DELETE`'ten `PATCH {silindi:true}`'a döner.
- `cari_hareketler`/`banka_kasa_hareketleri` alt-kayıt DELETE'leri tamamen KALDIRILIR (satır silinmez, denetim izi olarak kalır) — bu tablolara `silindi` kolonu EKLENMEZ, kendi okuma noktaları da değişmez.
- `kullanicilar` zaten `aktif` kolonuna sahip ve tüm okuma noktaları zaten `&aktif=eq.true` filtreli (`kullanici-yonetimi.html`'in kendi yönetim listesi hariç, ki o zaten kasıtlı olarak tümünü gösteriyor) — bu tabloda SADECE silme fonksiyonu değişir, yeni filtre eklenmez.

---

### Task 1: Supabase şema değişikliği

**Files:** (yok — SQL, kullanıcı Supabase SQL editöründe çalıştırır)

- [ ] **Step 1: SQL'i kullanıcıya ver**

```sql
alter table cariler add column if not exists silindi boolean default false;
alter table faturalar add column if not exists silindi boolean default false;
alter table demirbaslar add column if not exists silindi boolean default false;
alter table cek_senetler add column if not exists silindi boolean default false;
alter table banka_kasa_hesaplari add column if not exists silindi boolean default false;
alter table butce_kayitlari add column if not exists silindi boolean default false;
```

- [ ] **Step 2: Kullanıcıdan onay al**

"Çalıştı" onayını bekle. Onaysız Task 2'ye geçme.

---

### Task 2: `cariler` — silme + 8 okuma noktası

**Files:**
- Modify: `muhasebe-cariler.html` (silme fonksiyonu ~satır 610-623, kendi okuma noktası ~337)
- Modify: `mal-kabul-v2.html` (~402), `stok-takip.html` (~687), `muhasebe.html` (~137), `muhasebe-cek-senet.html` (~225), `muhasebe-raporlar.html` (~181), `muhasebe-asistan.html` (~137), `muhasebe-faturalar.html` (~432)

**Interfaces:** (yok — bağımsız, self-contained)

- [ ] **Step 1: Silme fonksiyonunu değiştir**

`muhasebe-cariler.html`'de cari silme fonksiyonundaki şu bloğu:

```js
  if(!confirm(`"${c.ad}" silinsin mi? Hareketler de silinecek!`))return;
  sLD();
  // Foreign key kısıtı (RESTRICT) nedeniyle önce hareketler, sonra cari silinmeli
  try{await fetch(SB_URL+'/rest/v1/cari_hareketler?cari_id=eq.'+id,{method:'DELETE',headers:SB_HEADERS});}catch(e){console.warn(e);}
  for(const hk of Object.keys(hareketler)){
    if(hareketler[hk]?.cariId===id)delete hareketler[hk];
  }
  try{await fetch(SB_URL+'/rest/v1/cariler?id=eq.'+id,{method:'DELETE',headers:SB_HEADERS});}catch(e){console.warn(e);}
  delete cariler[id];
```

şununla değiştir:

```js
  if(!confirm(`"${c.ad}" silinsin mi?`))return;
  sLD();
  // Soft-delete: hareketler artık silinmiyor, denetim izi olarak kalıyor.
  try{await fetch(SB_URL+'/rest/v1/cariler?id=eq.'+id,{method:'PATCH',headers:SB_HEADERS,body:JSON.stringify({silindi:true})});}catch(e){console.warn(e);}
  delete cariler[id];
```

(Not: `for(const hk of Object.keys(hareketler))` döngüsü de kaldırıldı — hareketler artık silinmediği için o döngünün amacı kalmadı.)

- [ ] **Step 2: 8 okuma noktasına filtre ekle**

Her dosyada, `cariler?` ile başlayan query string'in sonuna `&silindi=eq.false` ekle:

`muhasebe-cariler.html` — mevcut:
```js
      fetch(SB_URL+'/rest/v1/cariler?select=*',{headers:SB_HEADERS}),
```
yeni:
```js
      fetch(SB_URL+'/rest/v1/cariler?select=*&silindi=eq.false',{headers:SB_HEADERS}),
```

`mal-kabul-v2.html` — mevcut:
```js
      fetch(SB_URL+'/rest/v1/cariler?select=id,kod,ad,tip&tip=in.(tedarikci,her_ikisi)',{headers:SB_HEADERS}),
```
yeni:
```js
      fetch(SB_URL+'/rest/v1/cariler?select=id,kod,ad,tip&tip=in.(tedarikci,her_ikisi)&silindi=eq.false',{headers:SB_HEADERS}),
```

`stok-takip.html` — mevcut:
```js
      fetch(SB_URL+'/rest/v1/cariler?select=id,kod,ad,tip&tip=in.(tedarikci,her_ikisi)',{headers:SB_HEADERS}),
```
yeni:
```js
      fetch(SB_URL+'/rest/v1/cariler?select=id,kod,ad,tip&tip=in.(tedarikci,her_ikisi)&silindi=eq.false',{headers:SB_HEADERS}),
```

`muhasebe.html` — mevcut:
```js
      fetch(SB_URL+'/rest/v1/cariler?select=id',{headers:SB_HEADERS}),
```
yeni:
```js
      fetch(SB_URL+'/rest/v1/cariler?select=id&silindi=eq.false',{headers:SB_HEADERS}),
```

`muhasebe-cek-senet.html` — mevcut:
```js
      fetch(SB_URL+'/rest/v1/cariler?select=id,kod,ad,tip',{headers:SB_HEADERS}),
```
yeni:
```js
      fetch(SB_URL+'/rest/v1/cariler?select=id,kod,ad,tip&silindi=eq.false',{headers:SB_HEADERS}),
```

`muhasebe-raporlar.html` — mevcut:
```js
      fetch(SB_URL+'/rest/v1/cariler?select=id,kod,ad,tip',{headers:SB_HEADERS}),
```
yeni:
```js
      fetch(SB_URL+'/rest/v1/cariler?select=id,kod,ad,tip&silindi=eq.false',{headers:SB_HEADERS}),
```

`muhasebe-asistan.html` — mevcut:
```js
      fetch(SB_URL+'/rest/v1/cariler?select=*',{headers:SB_HEADERS}),
```
yeni:
```js
      fetch(SB_URL+'/rest/v1/cariler?select=*&silindi=eq.false',{headers:SB_HEADERS}),
```

`muhasebe-faturalar.html` — mevcut:
```js
      fetch(SB_URL+'/rest/v1/cariler?select=*',{headers:SB_HEADERS}),
```
yeni:
```js
      fetch(SB_URL+'/rest/v1/cariler?select=*&silindi=eq.false',{headers:SB_HEADERS}),
```

- [ ] **Step 3: Doğrulama**

```bash
grep -rn "rest/v1/cariler?select" muhasebe-cariler.html mal-kabul-v2.html stok-takip.html muhasebe.html muhasebe-cek-senet.html muhasebe-raporlar.html muhasebe-asistan.html muhasebe-faturalar.html | grep -v "silindi=eq.false"
```
Expected: **0 satır** (yani `cariler?select` içeren her satırda artık `silindi=eq.false` var). Ayrıca:
```bash
grep -n "cari_hareketler.*method:'DELETE'" muhasebe-cariler.html
```
Expected: 0 eşleşme (kaldırıldı).

- [ ] **Step 4: Commit**

```bash
git add muhasebe-cariler.html mal-kabul-v2.html stok-takip.html muhasebe.html muhasebe-cek-senet.html muhasebe-raporlar.html muhasebe-asistan.html muhasebe-faturalar.html
git commit -m "feat: soft-delete cariler (silindi bayrağı, DELETE→PATCH, tüm okumalar filtrelendi)"
```

---

### Task 3: `faturalar` — silme + 4 okuma noktası

**Files:**
- Modify: `muhasebe-faturalar.html` (silme fonksiyonu ~1013-1022, kendi okuma noktası ~431)
- Modify: `muhasebe-asistan.html` (~139), `muhasebe-raporlar.html` (~183), `muhasebe-cariler.html` (~339)

- [ ] **Step 1: Silme fonksiyonunu değiştir**

`muhasebe-faturalar.html`'deki `faturaSil` fonksiyonunda şu satırı:

```js
  try{await fetch(SB_URL+'/rest/v1/faturalar?id=eq.'+id,{method:'DELETE',headers:SB_HEADERS});}catch(e){console.warn(e);}
```

şununla değiştir:

```js
  try{await fetch(SB_URL+'/rest/v1/faturalar?id=eq.'+id,{method:'PATCH',headers:SB_HEADERS,body:JSON.stringify({silindi:true})});}catch(e){console.warn(e);}
```

- [ ] **Step 2: 4 okuma noktasına filtre ekle**

`muhasebe-faturalar.html` — mevcut:
```js
      fetch(SB_URL+'/rest/v1/faturalar?select=*,fatura_kalemleri(*)',{headers:SB_HEADERS}),
```
yeni:
```js
      fetch(SB_URL+'/rest/v1/faturalar?select=*,fatura_kalemleri(*)&silindi=eq.false',{headers:SB_HEADERS}),
```

`muhasebe-asistan.html` — mevcut:
```js
      fetch(SB_URL+'/rest/v1/faturalar?select=*',{headers:SB_HEADERS}),
```
yeni:
```js
      fetch(SB_URL+'/rest/v1/faturalar?select=*&silindi=eq.false',{headers:SB_HEADERS}),
```

`muhasebe-raporlar.html` — mevcut:
```js
      fetch(SB_URL+'/rest/v1/faturalar?select=id,olusturma_tarihi,genel_toplam',{headers:SB_HEADERS}),
```
yeni:
```js
      fetch(SB_URL+'/rest/v1/faturalar?select=id,olusturma_tarihi,genel_toplam&silindi=eq.false',{headers:SB_HEADERS}),
```

`muhasebe-cariler.html` — mevcut:
```js
      fetch(SB_URL+'/rest/v1/faturalar?select=id,no,cari_id,durum,genel_toplam,odeme_tutari',{headers:SB_HEADERS}),
```
yeni:
```js
      fetch(SB_URL+'/rest/v1/faturalar?select=id,no,cari_id,durum,genel_toplam,odeme_tutari&silindi=eq.false',{headers:SB_HEADERS}),
```

- [ ] **Step 3: Doğrulama**

```bash
grep -rn "rest/v1/faturalar?select" muhasebe-faturalar.html muhasebe-asistan.html muhasebe-raporlar.html muhasebe-cariler.html | grep -v "silindi=eq.false"
```
Expected: 0 satır.

- [ ] **Step 4: Commit**

```bash
git add muhasebe-faturalar.html muhasebe-asistan.html muhasebe-raporlar.html muhasebe-cariler.html
git commit -m "feat: soft-delete faturalar (silindi bayrağı, DELETE→PATCH, tüm okumalar filtrelendi)"
```

---

### Task 4: `demirbaslar` — silme + 2 okuma noktası

**Files:**
- Modify: `muhasebe-demirbas.html` (silme fonksiyonu ~476-485, kendi okuma noktası ~233)
- Modify: `muhasebe-raporlar.html` (~184)

- [ ] **Step 1: Silme fonksiyonunu değiştir**

`muhasebe-demirbas.html`'de demirbaş silme fonksiyonundaki şu satırı:

```js
  try{await fetch(SB_URL+'/rest/v1/demirbaslar?id=eq.'+id,{method:'DELETE',headers:SB_HEADERS});}catch(e){console.warn(e);}
```

şununla değiştir:

```js
  try{await fetch(SB_URL+'/rest/v1/demirbaslar?id=eq.'+id,{method:'PATCH',headers:SB_HEADERS,body:JSON.stringify({silindi:true})});}catch(e){console.warn(e);}
```

- [ ] **Step 2: 2 okuma noktasına filtre ekle**

`muhasebe-demirbas.html` — mevcut:
```js
      fetch(SB_URL+'/rest/v1/demirbaslar?select=*',{headers:SB_HEADERS}),
```
yeni:
```js
      fetch(SB_URL+'/rest/v1/demirbaslar?select=*&silindi=eq.false',{headers:SB_HEADERS}),
```

`muhasebe-raporlar.html` — mevcut:
```js
      fetch(SB_URL+'/rest/v1/demirbaslar?select=id,durum,alim_tutari,birikmis_amortisman',{headers:SB_HEADERS}),
```
yeni:
```js
      fetch(SB_URL+'/rest/v1/demirbaslar?select=id,durum,alim_tutari,birikmis_amortisman&silindi=eq.false',{headers:SB_HEADERS}),
```

- [ ] **Step 3: Doğrulama**

```bash
grep -rn "rest/v1/demirbaslar?select" muhasebe-demirbas.html muhasebe-raporlar.html | grep -v "silindi=eq.false"
```
Expected: 0 satır.

- [ ] **Step 4: Commit**

```bash
git add muhasebe-demirbas.html muhasebe-raporlar.html
git commit -m "feat: soft-delete demirbaslar (silindi bayrağı, DELETE→PATCH, tüm okumalar filtrelendi)"
```

---

### Task 5: `cek_senetler` — silme + 2 okuma noktası

**Files:**
- Modify: `muhasebe-cek-senet.html` (silme fonksiyonu ~483-492, kendi okuma noktası ~224)
- Modify: `muhasebe-raporlar.html` (~185)

- [ ] **Step 1: Silme fonksiyonunu değiştir**

`muhasebe-cek-senet.html`'de kayıt silme fonksiyonundaki şu satırı:

```js
  try{await fetch(SB_URL+'/rest/v1/cek_senetler?id=eq.'+id,{method:'DELETE',headers:SB_HEADERS});}catch(e){console.warn(e);}
```

şununla değiştir:

```js
  try{await fetch(SB_URL+'/rest/v1/cek_senetler?id=eq.'+id,{method:'PATCH',headers:SB_HEADERS,body:JSON.stringify({silindi:true})});}catch(e){console.warn(e);}
```

- [ ] **Step 2: 2 okuma noktasına filtre ekle**

`muhasebe-cek-senet.html` — mevcut:
```js
      fetch(SB_URL+'/rest/v1/cek_senetler?select=*',{headers:SB_HEADERS}),
```
yeni:
```js
      fetch(SB_URL+'/rest/v1/cek_senetler?select=*&silindi=eq.false',{headers:SB_HEADERS}),
```

`muhasebe-raporlar.html` — mevcut:
```js
      fetch(SB_URL+'/rest/v1/cek_senetler?select=id,durum,yon,tutar',{headers:SB_HEADERS}),
```
yeni:
```js
      fetch(SB_URL+'/rest/v1/cek_senetler?select=id,durum,yon,tutar&silindi=eq.false',{headers:SB_HEADERS}),
```

- [ ] **Step 3: Doğrulama**

```bash
grep -rn "rest/v1/cek_senetler?select" muhasebe-cek-senet.html muhasebe-raporlar.html | grep -v "silindi=eq.false"
```
Expected: 0 satır.

- [ ] **Step 4: Commit**

```bash
git add muhasebe-cek-senet.html muhasebe-raporlar.html
git commit -m "feat: soft-delete cek_senetler (silindi bayrağı, DELETE→PATCH, tüm okumalar filtrelendi)"
```

---

### Task 6: `banka_kasa_hesaplari` — silme + 2 okuma noktası

**Files:**
- Modify: `muhasebe-banka.html` (silme fonksiyonu ~435-446, kendi okuma noktası ~272)
- Modify: `muhasebe-asistan.html` (~141)

- [ ] **Step 1: Silme fonksiyonunu değiştir**

`muhasebe-banka.html`'de `hesapSil` fonksiyonundaki şu bloğu:

```js
  if(!confirm(`"${h.ad}" silinsin mi? Hareketler de silinecek!`))return;
  sLD();delete hesaplar[id];
  try{await fetch(SB_URL+'/rest/v1/banka_kasa_hareketleri?hesap_id=eq.'+id,{method:'DELETE',headers:SB_HEADERS});}catch(e){console.warn(e);}
  for(const hk of Object.keys(hareketler)){
    if(hareketler[hk]?.hesapId===id)delete hareketler[hk];
  }
  try{await fetch(SB_URL+'/rest/v1/banka_kasa_hesaplari?id=eq.'+id,{method:'DELETE',headers:SB_HEADERS});}catch(e){console.warn(e);}
```

şununla değiştir:

```js
  if(!confirm(`"${h.ad}" silinsin mi?`))return;
  sLD();delete hesaplar[id];
  // Soft-delete: hareketler artık silinmiyor, denetim izi olarak kalıyor.
  try{await fetch(SB_URL+'/rest/v1/banka_kasa_hesaplari?id=eq.'+id,{method:'PATCH',headers:SB_HEADERS,body:JSON.stringify({silindi:true})});}catch(e){console.warn(e);}
```

(Not: `for(const hk of Object.keys(hareketler))` döngüsü kaldırıldı — hareketler artık silinmediği için amacı kalmadı.)

- [ ] **Step 2: 2 okuma noktasına filtre ekle**

`muhasebe-banka.html` — mevcut:
```js
      fetch(SB_URL+'/rest/v1/banka_kasa_hesaplari?select=*',{headers:SB_HEADERS}),
```
yeni:
```js
      fetch(SB_URL+'/rest/v1/banka_kasa_hesaplari?select=*&silindi=eq.false',{headers:SB_HEADERS}),
```

`muhasebe-asistan.html` — mevcut:
```js
      fetch(SB_URL+'/rest/v1/banka_kasa_hesaplari?select=*',{headers:SB_HEADERS}),
```
yeni:
```js
      fetch(SB_URL+'/rest/v1/banka_kasa_hesaplari?select=*&silindi=eq.false',{headers:SB_HEADERS}),
```

- [ ] **Step 3: Doğrulama**

```bash
grep -rn "rest/v1/banka_kasa_hesaplari?select" muhasebe-banka.html muhasebe-asistan.html | grep -v "silindi=eq.false"
```
Expected: 0 satır.
```bash
grep -n "banka_kasa_hareketleri.*method:'DELETE'" muhasebe-banka.html
```
Expected: 0 eşleşme (kaldırıldı).

- [ ] **Step 4: Commit**

```bash
git add muhasebe-banka.html muhasebe-asistan.html
git commit -m "feat: soft-delete banka_kasa_hesaplari (silindi bayrağı, DELETE→PATCH, tüm okumalar filtrelendi)"
```

---

### Task 7: `butce_kayitlari` + `kullanicilar` — silme dönüşümleri

**Files:**
- Modify: `muhasebe-butce.html` (silme fonksiyonu ~358-367)
- Modify: `kullanici-yonetimi.html` (silme fonksiyonu ~235-244)

**Interfaces:** (yok — iki bağımsız, trivial tek-fonksiyon değişikliği)

- [ ] **Step 1: `butce_kayitlari` silme fonksiyonunu değiştir**

`muhasebe-butce.html`'de `butceSil` fonksiyonundaki şu satırı:

```js
  try{await fetch(SB_URL+'/rest/v1/butce_kayitlari?id=eq.'+id,{method:'DELETE',headers:SB_HEADERS});}catch(e){console.warn(e);}
```

şununla değiştir:

```js
  try{await fetch(SB_URL+'/rest/v1/butce_kayitlari?id=eq.'+id,{method:'PATCH',headers:SB_HEADERS,body:JSON.stringify({silindi:true})});}catch(e){console.warn(e);}
```

`muhasebe-butce.html`'de tek okuma noktasını (satır ~179) da güncelle — mevcut:
```js
      fetch(SB_URL+'/rest/v1/butce_kayitlari?select=*',{headers:SB_HEADERS}),
```
yeni:
```js
      fetch(SB_URL+'/rest/v1/butce_kayitlari?select=*&silindi=eq.false',{headers:SB_HEADERS}),
```

- [ ] **Step 2: `kullanicilar` silme fonksiyonunu değiştir**

`kullanici-yonetimi.html`'de kullanıcı silme fonksiyonundaki şu satırı:

```js
    await fetch(SB_URL+'/rest/v1/kullanicilar?id=eq.'+id,{method:'DELETE',headers:SB_HEADERS});
```

şununla değiştir:

```js
    await fetch(SB_URL+'/rest/v1/kullanicilar?id=eq.'+id,{method:'PATCH',headers:SB_HEADERS,body:JSON.stringify({aktif:false})});
```

(Not: `kullanicilar` zaten `aktif` kolonuna sahip, yeni SQL gerekmez. Diğer tüm okuma noktaları zaten `&aktif=eq.true` filtreli — dokunulmaz. `kullanici-yonetimi.html`'in kendi listesi kasıtlı olarak tümünü gösteriyor, o da dokunulmaz.)

- [ ] **Step 3: Doğrulama**

```bash
grep -n "rest/v1/butce_kayitlari?select" muhasebe-butce.html | grep -v "silindi=eq.false"
grep -n "kullanicilar?id=eq.'+id,{method:'DELETE'" kullanici-yonetimi.html
```
Expected: ilk komut 0 satır; ikinci komut 0 eşleşme (artık PATCH).

- [ ] **Step 4: Commit**

```bash
git add muhasebe-butce.html kullanici-yonetimi.html
git commit -m "feat: soft-delete butce_kayitlari, kullanicilar silme→PATCH aktif:false"
```

---

### Task 8: Uçtan uca doğrulama

**Files:** (yok — sadece doğrulama)

- [ ] **Step 1: Tüm kod tabanında tutarlılık kontrolü**

```bash
grep -rn "rest/v1/cariler?select\|rest/v1/faturalar?select\|rest/v1/demirbaslar?select\|rest/v1/cek_senetler?select\|rest/v1/banka_kasa_hesaplari?select\|rest/v1/butce_kayitlari?select" *.html | grep -v "silindi=eq.false"
```
Expected: 0 satır — 6 tablonun HİÇBİR okuma noktasında filtre eksik kalmamalı.

```bash
grep -n "cariler?id=eq.*method:'DELETE'\|faturalar?id=eq.*method:'DELETE'\|demirbaslar?id=eq.*method:'DELETE'\|cek_senetler?id=eq.*method:'DELETE'\|banka_kasa_hesaplari?id=eq.*method:'DELETE'\|butce_kayitlari?id=eq.*method:'DELETE'\|kullanicilar?id=eq.*method:'DELETE'" *.html
```
Expected: 0 eşleşme (hepsi PATCH'e döndü).

- [ ] **Step 2: Kullanıcıya manuel test adımlarını bildir**

Node/Python yok. Kullanıcının tarayıcıda doğrulaması gereken akış:
1. Bir test carisi/fatura/demirbaş/çek-senet/banka hesabı/bütçe kaydı/kullanıcı oluştur, sonra sil → eskisi gibi listeden kaybolduğunu doğrula (davranış değişmemeli).
2. Supabase tablosunda o satırın hâlâ durduğunu, sadece `silindi=true` (veya kullanıcı için `aktif=false`) olduğunu doğrula.
3. Silinen bir carinin geçmiş hareketlerinin (`cari_hareketler`) hâlâ Supabase'de durduğunu doğrula (artık silinmiyor).
4. Silinen kayıtların diğer ekranlarda (raporlar, seçim listeleri, ilişkili modüller — örn. silinen bir tedarikçi mal-kabul'ün tedarikçi listesinde) hiç görünmediğini doğrula.

- [ ] **Step 3: Kullanıcıdan onay al, sonra push**

```bash
git fetch
git log --oneline main..origin/main
```
Expected: paralel oturumdan gelen değişiklik var mı kontrol et (özellikle `hesap_plani`/`satin-alma.html` dışındaki dosyalara paralel dokunma olup olmadığına dikkat et), varsa kullanıcıya bildir ve gerekirse merge et. Yoksa kullanıcı onayıyla `git push`.
