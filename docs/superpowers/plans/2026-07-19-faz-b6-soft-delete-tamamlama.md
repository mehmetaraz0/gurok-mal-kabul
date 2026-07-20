# Faz B6 — Soft-Delete Tamamlama (hesap_plani/doviz_kurlari/yevmiye_fisler/sene_sonu_kapanislar) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Yönetici denetim raporunda P1 olarak işaretlenen "Mantıksal Silme Eksikliği" bulgusunu tamamlamak — `hesap_plani`, `doviz_kurlari`, `yevmiye_fisler`, `sene_sonu_kapanislar` tablolarını, projede zaten kurulu olan `silindi` boolean deseniyle (cariler/faturalar/demirbaslar/cek_senetler/banka_kasa_hesaplari/butce_kayitlari/kullanicilar'da kullanılan AYNI desen) gerçek DELETE yerine soft-delete'e geçirmek.

**Architecture:** `silindi` kolonu şemaya eklendi, ilgili DELETE RLS politikaları kaldırıldı (SQL zaten çalıştırıldı — kullanıcı onayladı). Bu plan sadece UYGULAMA (HTML/JS) tarafını kapsıyor: (1) bu 4 tabloyu okuyan HER sorguya `&silindi=eq.false` eklemek, (2) 4 gerçek DELETE çağrısını `PATCH {silindi:true}` ile değiştirmek, (3) `on_conflict` tabanlı 4 upsert'e `silindi:false` eklemek (aksi halde daha önce soft-delete edilmiş bir kaydın "yeniden eklenmesi", kaydı görünmez halde güncelleyip gizli bırakır), (4) `yevmiye_fisler`'in "mevcut fiş var mı" (tip+belge_no) arama sorgularına da filtre eklemek (aksi halde soft-delete edilmiş bir fiş sessizce eşleşip PATCH'lenir ama gizli kalır). Fiş-numarası üretim sorguları (`no=like...order=no.desc`) BİLEREK filtrelenmiyor — silinen fiş numaraları yeniden kullanılmasın diye.

**Tech Stack:** Vanilla JS, raw `fetch()`. Build aracı/test çerçevesi yok — doğrulama grep + manuel kod okuma + kullanıcının tarayıcıda uçtan uca testi.

## Global Constraints

- `silindi` kolonu ve DELETE RLS politikalarının kaldırılması ZATEN yapıldı (kullanıcı SQL'i çalıştırdı) — bu plan sadece HTML/JS değişikliklerini kapsıyor.
- Okuma sorgularına eklenecek filtre: `&silindi=eq.false` (var olan query string'in sonuna, mevcut `?select=...` parametresinden sonra).
- Silme aksiyonları artık `method:'DELETE'` yerine `method:'PATCH', body:JSON.stringify({silindi:true})` kullanır — URL (hangi satırı hedeflediği) DEĞİŞMEZ, sadece method ve body değişir.
- Upsert'lere (`on_conflict=...` + `Prefer: resolution=merge-duplicates` içeren POST'lar) payload'a `silindi:false` eklenir — böylece daha önce silinmiş bir kayıt "yeniden eklenirse" görünür hale gelir.
- `yevmiye_fisler`'in tip+belge_no arama sorgularına da `&silindi=eq.false` eklenir (soft-delete edilmiş bir fişin sessizce eşleşip güncellenmesini engellemek için).
- Fiş-numarası üretim sorguları (`no=like.YEV-...&order=no.desc&limit=1`) BİLEREK dokunulmaz — numara tekrar kullanılmasın.
- Dosyalarda SADECE bu planda belirtilen satırlar değişir.

---

### Task 1: `muhasebe-hesap-plani.html`

**Files:**
- Modify: `muhasebe-hesap-plani.html:702` (ana liste okuma sorgusu)
- Modify: `muhasebe-hesap-plani.html:722` (upsert — silindi:false eklenir)
- Modify: `muhasebe-hesap-plani.html:1135` (hesapSilModal — DELETE→PATCH)

- [ ] **Step 1: Ana okuma sorgusuna filtre ekle**

`muhasebe-hesap-plani.html:702`'deki mevcut satır:

```js
  const r=await fetch(SB_URL+'/rest/v1/hesap_plani?select=*&order=kod',{headers:SB_HEADERS});
```

Şununla değiştir:

```js
  const r=await fetch(SB_URL+'/rest/v1/hesap_plani?select=*&order=kod&silindi=eq.false',{headers:SB_HEADERS});
```

- [ ] **Step 2: Upsert'e silindi:false ekle**

`muhasebe-hesap-plani.html:722` civarındaki `saveHesap()` fonksiyonu içinde, `hesap_plani` tablosuna yapılan `on_conflict=kod` upsert'inin `body:JSON.stringify(satir)` kısmındaki `satir` nesnesini oluşturan koda bak (bu satırın hemen öncesinde `const satir={...}` şeklinde tanımlanır). O nesneye `silindi:false` alanını ekle. Örnek (gerçek alan adları dosyadaki `satir` tanımına göre uyarlanmalı — mevcut alanları KORU, sadece `silindi:false` ekle):

```js
const satir={
  kod: ...,
  ad: ...,
  // ...mevcut diğer alanlar...
  silindi:false
};
```

- [ ] **Step 3: hesapSilModal'ı DELETE'ten PATCH'e çevir**

`muhasebe-hesap-plani.html:1135`'teki mevcut satır:

```js
  try{await fetch(SB_URL+'/rest/v1/hesap_plani?kod=eq.'+encodeURIComponent(kod),{method:'DELETE',headers:SB_HEADERS});}catch(e){console.warn(e);}
```

Şununla değiştir:

```js
  try{await fetch(SB_URL+'/rest/v1/hesap_plani?kod=eq.'+encodeURIComponent(kod),{method:'PATCH',headers:SB_HEADERS,body:JSON.stringify({silindi:true})});}catch(e){console.warn(e);}
```

- [ ] **Step 4: Grep ile doğrula**

```bash
grep -n "silindi" muhasebe-hesap-plani.html
```

Expected: en az 3 satırda geçmeli (okuma filtresi, upsert, PATCH).

- [ ] **Step 5: Commit**

```bash
cd "C:\Users\USER\Projects\gurok-mal-kabul"
git add muhasebe-hesap-plani.html
git -c user.name="mehmetaraz0" -c user.email="mehmetaraz868@gmail.com" commit -m "feat: hesap_plani soft-delete'e geçirildi (Faz B6)"
```

---

### Task 2: `satin-alma-fiyatkontrol.html`

**Files:**
- Modify: `satin-alma-fiyatkontrol.html:442` (hesap_plani upsert — silindi:false eklenir)

- [ ] **Step 1: hesap_plani upsert'ine silindi:false ekle**

`satin-alma-fiyatkontrol.html:442`'deki mevcut satır:

```js
fetch(SB_URL+'/rest/v1/hesap_plani?on_conflict=kod',{method:'POST',headers:{...SB_HEADERS,'Prefer':'resolution=merge-duplicates'},body:JSON.stringify({kod:'320.90',ad:'Faturası Beklenen Alımlar (GR/IR)',tip:'Bilanço',ust_kod:'320'})})
```

Şununla değiştir:

```js
fetch(SB_URL+'/rest/v1/hesap_plani?on_conflict=kod',{method:'POST',headers:{...SB_HEADERS,'Prefer':'resolution=merge-duplicates'},body:JSON.stringify({kod:'320.90',ad:'Faturası Beklenen Alımlar (GR/IR)',tip:'Bilanço',ust_kod:'320',silindi:false})})
```

- [ ] **Step 2: Grep ile doğrula**

```bash
grep -n "silindi" satin-alma-fiyatkontrol.html
```

Expected: 1 satırda geçmeli.

- [ ] **Step 3: Commit**

```bash
cd "C:\Users\USER\Projects\gurok-mal-kabul"
git add satin-alma-fiyatkontrol.html
git -c user.name="mehmetaraz0" -c user.email="mehmetaraz868@gmail.com" commit -m "fix: satin-alma-fiyatkontrol.html hesap_plani upsert'i silindi alanını ayarlıyor (Faz B6)"
```

---

### Task 3: `muhasebe-butce.html`

**Files:**
- Modify: `muhasebe-butce.html:187` (hesap_plani okuma)
- Modify: `muhasebe-butce.html:188` (yevmiye_fisler okuma)

- [ ] **Step 1: hesap_plani okuma filtresi**

`muhasebe-butce.html:187`'deki mevcut satır:

```js
fetch(SB_URL+'/rest/v1/hesap_plani?select=kod,ad,yon,tip',{headers:SB_HEADERS}),
```

Şununla değiştir:

```js
fetch(SB_URL+'/rest/v1/hesap_plani?select=kod,ad,yon,tip&silindi=eq.false',{headers:SB_HEADERS}),
```

- [ ] **Step 2: yevmiye_fisler okuma filtresi**

`muhasebe-butce.html:188`'deki mevcut satır:

```js
fetch(SB_URL+'/rest/v1/yevmiye_fisler?select=id,tarih,otel_id,yevmiye_kalemleri(hesap_kodu,borc,alacak)',{headers:SB_HEADERS}),
```

Şununla değiştir:

```js
fetch(SB_URL+'/rest/v1/yevmiye_fisler?select=id,tarih,otel_id,yevmiye_kalemleri(hesap_kodu,borc,alacak)&silindi=eq.false',{headers:SB_HEADERS}),
```

- [ ] **Step 3: Grep ile doğrula**

```bash
grep -c "silindi" muhasebe-butce.html
```

Expected: 2.

- [ ] **Step 4: Commit**

```bash
cd "C:\Users\USER\Projects\gurok-mal-kabul"
git add muhasebe-butce.html
git -c user.name="mehmetaraz0" -c user.email="mehmetaraz868@gmail.com" commit -m "fix: muhasebe-butce.html hesap_plani/yevmiye_fisler okumaları silindi filtresi alıyor (Faz B6)"
```

---

### Task 4: `muhasebe-edefter.html`

**Files:**
- Modify: `muhasebe-edefter.html:387` (yevmiye_fisler okuma)
- Modify: `muhasebe-edefter.html:388` (hesap_plani okuma)

- [ ] **Step 1: yevmiye_fisler okuma filtresi**

`muhasebe-edefter.html:387`'deki mevcut satır:

```js
fetch(SB_URL+'/rest/v1/yevmiye_fisler?select=*,yevmiye_kalemleri(*)',{headers:SB_HEADERS}),
```

Şununla değiştir:

```js
fetch(SB_URL+'/rest/v1/yevmiye_fisler?select=*,yevmiye_kalemleri(*)&silindi=eq.false',{headers:SB_HEADERS}),
```

- [ ] **Step 2: hesap_plani okuma filtresi**

`muhasebe-edefter.html:388`'deki mevcut satır:

```js
fetch(SB_URL+'/rest/v1/hesap_plani?select=kod,ad',{headers:SB_HEADERS}),
```

Şununla değiştir:

```js
fetch(SB_URL+'/rest/v1/hesap_plani?select=kod,ad&silindi=eq.false',{headers:SB_HEADERS}),
```

- [ ] **Step 3: Grep ile doğrula**

```bash
grep -c "silindi" muhasebe-edefter.html
```

Expected: 2.

- [ ] **Step 4: Commit**

```bash
cd "C:\Users\USER\Projects\gurok-mal-kabul"
git add muhasebe-edefter.html
git -c user.name="mehmetaraz0" -c user.email="mehmetaraz868@gmail.com" commit -m "fix: muhasebe-edefter.html yevmiye_fisler/hesap_plani okumaları silindi filtresi alıyor (Faz B6)"
```

---

### Task 5: `muhasebe-yevmiye.html`

**Files:**
- Modify: `muhasebe-yevmiye.html:265` (yevmiye_fisler okuma)
- Modify: `muhasebe-yevmiye.html:266` (hesap_plani okuma)
- Modify: `muhasebe-yevmiye.html:603` (yevmiyeSil — DELETE→PATCH)

- [ ] **Step 1: yevmiye_fisler okuma filtresi**

`muhasebe-yevmiye.html:265`'teki mevcut satır:

```js
fetch(SB_URL+'/rest/v1/yevmiye_fisler?select=*,yevmiye_kalemleri(*)',{headers:SB_HEADERS}),
```

Şununla değiştir:

```js
fetch(SB_URL+'/rest/v1/yevmiye_fisler?select=*,yevmiye_kalemleri(*)&silindi=eq.false',{headers:SB_HEADERS}),
```

- [ ] **Step 2: hesap_plani okuma filtresi**

`muhasebe-yevmiye.html:266`'daki mevcut satır:

```js
fetch(SB_URL+'/rest/v1/hesap_plani?select=kod,ad',{headers:SB_HEADERS}),
```

Şununla değiştir:

```js
fetch(SB_URL+'/rest/v1/hesap_plani?select=kod,ad&silindi=eq.false',{headers:SB_HEADERS}),
```

- [ ] **Step 3: yevmiyeSil'i DELETE'ten PATCH'e çevir**

`muhasebe-yevmiye.html:603`'teki mevcut satır:

```js
  try{await fetch(SB_URL+'/rest/v1/yevmiye_fisler?id=eq.'+id,{method:'DELETE',headers:SB_HEADERS});}catch(e){console.warn(e);}
```

Şununla değiştir:

```js
  try{await fetch(SB_URL+'/rest/v1/yevmiye_fisler?id=eq.'+id,{method:'PATCH',headers:SB_HEADERS,body:JSON.stringify({silindi:true})});}catch(e){console.warn(e);}
```

- [ ] **Step 4: Grep ile doğrula**

```bash
grep -c "silindi" muhasebe-yevmiye.html
```

Expected: 3.

- [ ] **Step 5: Commit**

```bash
cd "C:\Users\USER\Projects\gurok-mal-kabul"
git add muhasebe-yevmiye.html
git -c user.name="mehmetaraz0" -c user.email="mehmetaraz868@gmail.com" commit -m "feat: yevmiye_fisler soft-delete'e geçirildi, muhasebe-yevmiye.html (Faz B6)"
```

---

### Task 6: `muhasebe-raporlar.html`

**Files:**
- Modify: `muhasebe-raporlar.html:179` (hesap_plani okuma)
- Modify: `muhasebe-raporlar.html:180` (yevmiye_fisler okuma)

- [ ] **Step 1: hesap_plani okuma filtresi**

`muhasebe-raporlar.html:179`'daki mevcut satır:

```js
fetch(SB_URL+'/rest/v1/hesap_plani?select=kod,ad,tip,yon',{headers:SB_HEADERS}),
```

Şununla değiştir:

```js
fetch(SB_URL+'/rest/v1/hesap_plani?select=kod,ad,tip,yon&silindi=eq.false',{headers:SB_HEADERS}),
```

- [ ] **Step 2: yevmiye_fisler okuma filtresi**

`muhasebe-raporlar.html:180`'deki mevcut satır:

```js
fetch(SB_URL+'/rest/v1/yevmiye_fisler?select=id,tarih,otel_id,yevmiye_kalemleri(hesap_kodu,borc,alacak)',{headers:SB_HEADERS}),
```

Şununla değiştir:

```js
fetch(SB_URL+'/rest/v1/yevmiye_fisler?select=id,tarih,otel_id,yevmiye_kalemleri(hesap_kodu,borc,alacak)&silindi=eq.false',{headers:SB_HEADERS}),
```

- [ ] **Step 3: Grep ile doğrula**

```bash
grep -c "silindi" muhasebe-raporlar.html
```

Expected: 2.

- [ ] **Step 4: Commit**

```bash
cd "C:\Users\USER\Projects\gurok-mal-kabul"
git add muhasebe-raporlar.html
git -c user.name="mehmetaraz0" -c user.email="mehmetaraz868@gmail.com" commit -m "fix: muhasebe-raporlar.html hesap_plani/yevmiye_fisler okumaları silindi filtresi alıyor (Faz B6)"
```

---

### Task 7: `muhasebe-asistan.html`

**Files:**
- Modify: `muhasebe-asistan.html:140` (yevmiye_fisler okuma)

- [ ] **Step 1: yevmiye_fisler okuma filtresi**

`muhasebe-asistan.html:140`'daki mevcut satır:

```js
fetch(SB_URL+'/rest/v1/yevmiye_fisler?select=*',{headers:SB_HEADERS}),
```

Şununla değiştir:

```js
fetch(SB_URL+'/rest/v1/yevmiye_fisler?select=*&silindi=eq.false',{headers:SB_HEADERS}),
```

- [ ] **Step 2: Grep ile doğrula**

```bash
grep -c "silindi" muhasebe-asistan.html
```

Expected: 1.

- [ ] **Step 3: Commit**

```bash
cd "C:\Users\USER\Projects\gurok-mal-kabul"
git add muhasebe-asistan.html
git -c user.name="mehmetaraz0" -c user.email="mehmetaraz868@gmail.com" commit -m "fix: muhasebe-asistan.html yevmiye_fisler okuması silindi filtresi alıyor (Faz B6)"
```

---

### Task 8: `muhasebe-cek-senet.html`

**Files:**
- Modify: `muhasebe-cek-senet.html:357` (yevmiye_fisler tip+belge_no araması)

**NOT:** `muhasebe-cek-senet.html:337`'deki fiş-numarası üretim sorgusuna (`no=like.YEV-${yil}-*...`) BİLEREK dokunulmaz.

- [ ] **Step 1: tip+belge_no arama sorgusuna filtre ekle**

`muhasebe-cek-senet.html:357`'deki mevcut satır:

```js
    const r=await fetch(SB_URL+`/rest/v1/yevmiye_fisler?tip=eq.${encodeURIComponent(tip)}&belge_no=eq.${encodeURIComponent(belge)}&select=id,no`,{headers:SB_HEADERS});
```

Şununla değiştir:

```js
    const r=await fetch(SB_URL+`/rest/v1/yevmiye_fisler?tip=eq.${encodeURIComponent(tip)}&belge_no=eq.${encodeURIComponent(belge)}&select=id,no&silindi=eq.false`,{headers:SB_HEADERS});
```

- [ ] **Step 2: Grep ile doğrula**

```bash
grep -n "silindi" muhasebe-cek-senet.html
```

Expected: 1 satırda geçmeli, satır 337'deki fiş-numarası sorgusunda GEÇMEMELİ.

- [ ] **Step 3: Commit**

```bash
cd "C:\Users\USER\Projects\gurok-mal-kabul"
git add muhasebe-cek-senet.html
git -c user.name="mehmetaraz0" -c user.email="mehmetaraz868@gmail.com" commit -m "fix: muhasebe-cek-senet.html yevmiye_fisler arama sorgusu silindi filtresi alıyor (Faz B6)"
```

---

### Task 9: `muhasebe-demirbas.html`

**Files:**
- Modify: `muhasebe-demirbas.html:357` (yevmiye_fisler tip+belge_no araması)

**NOT:** `muhasebe-demirbas.html:337`'deki fiş-numarası üretim sorgusuna BİLEREK dokunulmaz.

- [ ] **Step 1: tip+belge_no arama sorgusuna filtre ekle**

`muhasebe-demirbas.html:357`'deki mevcut satır:

```js
    const r=await fetch(SB_URL+`/rest/v1/yevmiye_fisler?tip=eq.${encodeURIComponent(tip)}&belge_no=eq.${encodeURIComponent(belge)}&select=id,no`,{headers:SB_HEADERS});
```

Şununla değiştir:

```js
    const r=await fetch(SB_URL+`/rest/v1/yevmiye_fisler?tip=eq.${encodeURIComponent(tip)}&belge_no=eq.${encodeURIComponent(belge)}&select=id,no&silindi=eq.false`,{headers:SB_HEADERS});
```

- [ ] **Step 2: Grep ile doğrula**

```bash
grep -n "silindi" muhasebe-demirbas.html
```

Expected: 1 satırda geçmeli, satır 337'deki fiş-numarası sorgusunda GEÇMEMELİ.

- [ ] **Step 3: Commit**

```bash
cd "C:\Users\USER\Projects\gurok-mal-kabul"
git add muhasebe-demirbas.html
git -c user.name="mehmetaraz0" -c user.email="mehmetaraz868@gmail.com" commit -m "fix: muhasebe-demirbas.html yevmiye_fisler arama sorgusu silindi filtresi alıyor (Faz B6)"
```

---

### Task 10: `muhasebe-faturalar.html`

**Files:**
- Modify: `muhasebe-faturalar.html:351` (yevmiye_fisler tip+belge_no araması)

**NOT:** `muhasebe-faturalar.html:328`'deki fiş-numarası üretim sorgusuna BİLEREK dokunulmaz.

- [ ] **Step 1: tip+belge_no arama sorgusuna filtre ekle**

`muhasebe-faturalar.html:351`'deki mevcut satır:

```js
    const r=await fetch(SB_URL+`/rest/v1/yevmiye_fisler?tip=eq.${encodeURIComponent(tip)}&belge_no=eq.${encodeURIComponent(belge)}&select=id,no`,{headers:SB_HEADERS});
```

Şununla değiştir:

```js
    const r=await fetch(SB_URL+`/rest/v1/yevmiye_fisler?tip=eq.${encodeURIComponent(tip)}&belge_no=eq.${encodeURIComponent(belge)}&select=id,no&silindi=eq.false`,{headers:SB_HEADERS});
```

- [ ] **Step 2: Grep ile doğrula**

```bash
grep -n "silindi" muhasebe-faturalar.html
```

Expected: 1 satırda geçmeli, satır 328'deki fiş-numarası sorgusunda GEÇMEMELİ.

- [ ] **Step 3: Commit**

```bash
cd "C:\Users\USER\Projects\gurok-mal-kabul"
git add muhasebe-faturalar.html
git -c user.name="mehmetaraz0" -c user.email="mehmetaraz868@gmail.com" commit -m "fix: muhasebe-faturalar.html yevmiye_fisler arama sorgusu silindi filtresi alıyor (Faz B6)"
```

---

### Task 11: `muhasebe-kur.html`

**Files:**
- Modify: `muhasebe-kur.html:136` (doviz_kurlari okuma)
- Modify: `muhasebe-kur.html:245` (bugunuSifirla — DELETE→PATCH)
- Modify: `muhasebe-kur.html:308` (upsert — silindi:false eklenir)

- [ ] **Step 1: Ana okuma sorgusuna filtre ekle**

`muhasebe-kur.html:136`'daki mevcut satır:

```js
  const r=await fetch(SB_URL+'/rest/v1/doviz_kurlari?select=*&order=tarih.asc',{headers:SB_HEADERS});
```

Şununla değiştir:

```js
  const r=await fetch(SB_URL+'/rest/v1/doviz_kurlari?select=*&order=tarih.asc&silindi=eq.false',{headers:SB_HEADERS});
```

- [ ] **Step 2: bugunuSifirla'yı DELETE'ten PATCH'e çevir**

`muhasebe-kur.html:245`'teki mevcut satır:

```js
    await fetch(SB_URL+'/rest/v1/doviz_kurlari?tarih=eq.'+tarihKey,{method:'DELETE',headers:SB_HEADERS});
```

Şununla değiştir:

```js
    await fetch(SB_URL+'/rest/v1/doviz_kurlari?tarih=eq.'+tarihKey,{method:'PATCH',headers:SB_HEADERS,body:JSON.stringify({silindi:true})});
```

- [ ] **Step 3: Upsert'e silindi:false ekle**

`muhasebe-kur.html:308`'deki mevcut satır:

```js
fetch(SB_URL+'/rest/v1/doviz_kurlari?on_conflict=tarih,para_birimi',{method:'POST',headers:{...SB_HEADERS,'Prefer':'resolution=merge-duplicates'},body:JSON.stringify({tarih:tarihKey,para_birimi:kod,doviz_alis:alis,doviz_satis:satis,kaynak:'Manuel'})})
```

Şununla değiştir:

```js
fetch(SB_URL+'/rest/v1/doviz_kurlari?on_conflict=tarih,para_birimi',{method:'POST',headers:{...SB_HEADERS,'Prefer':'resolution=merge-duplicates'},body:JSON.stringify({tarih:tarihKey,para_birimi:kod,doviz_alis:alis,doviz_satis:satis,kaynak:'Manuel',silindi:false})})
```

- [ ] **Step 4: Grep ile doğrula**

```bash
grep -c "silindi" muhasebe-kur.html
```

Expected: 3.

- [ ] **Step 5: Commit**

```bash
cd "C:\Users\USER\Projects\gurok-mal-kabul"
git add muhasebe-kur.html
git -c user.name="mehmetaraz0" -c user.email="mehmetaraz868@gmail.com" commit -m "feat: doviz_kurlari soft-delete'e geçirildi (Faz B6)"
```

---

### Task 12: `muhasebe-sene-sonu.html`

**Files:**
- Modify: `muhasebe-sene-sonu.html:113` (hesap_plani okuma)
- Modify: `muhasebe-sene-sonu.html:114` (yevmiye_fisler okuma)
- Modify: `muhasebe-sene-sonu.html:115` (sene_sonu_kapanislar okuma)
- Modify: `muhasebe-sene-sonu.html:151` (yevmiye_fisler tip+belge_no araması, dönem kapama akışında)
- Modify: `muhasebe-sene-sonu.html:342` (sene_sonu_kapanislar upsert — silindi:false eklenir)
- Modify: `muhasebe-sene-sonu.html:389` (yevmiye_fisler arama, kapanmisYiliGeriAl içinde)
- Modify: `muhasebe-sene-sonu.html:395` (kapanmisYiliGeriAl — yevmiye_fisler DELETE→PATCH)
- Modify: `muhasebe-sene-sonu.html:401` (kapanmisYiliGeriAl — sene_sonu_kapanislar DELETE→PATCH)

**NOT:** `muhasebe-sene-sonu.html:131`'deki fiş-numarası üretim sorgusuna BİLEREK dokunulmaz.

- [ ] **Step 1: hesap_plani okuma filtresi**

`muhasebe-sene-sonu.html:113`'teki mevcut satır:

```js
fetch(SB_URL+'/rest/v1/hesap_plani?select=kod,ad,tip,yon',{headers:SB_HEADERS}),
```

Şununla değiştir:

```js
fetch(SB_URL+'/rest/v1/hesap_plani?select=kod,ad,tip,yon&silindi=eq.false',{headers:SB_HEADERS}),
```

- [ ] **Step 2: yevmiye_fisler okuma filtresi**

`muhasebe-sene-sonu.html:114`'teki mevcut satır:

```js
fetch(SB_URL+'/rest/v1/yevmiye_fisler?select=id,no,tarih,otel_id,yevmiye_kalemleri(hesap_kodu,borc,alacak)',{headers:SB_HEADERS}),
```

Şununla değiştir:

```js
fetch(SB_URL+'/rest/v1/yevmiye_fisler?select=id,no,tarih,otel_id,yevmiye_kalemleri(hesap_kodu,borc,alacak)&silindi=eq.false',{headers:SB_HEADERS}),
```

- [ ] **Step 3: sene_sonu_kapanislar okuma filtresi**

`muhasebe-sene-sonu.html:115`'teki mevcut satır:

```js
fetch(SB_URL+'/rest/v1/sene_sonu_kapanislar?select=*',{headers:SB_HEADERS}),
```

Şununla değiştir:

```js
fetch(SB_URL+'/rest/v1/sene_sonu_kapanislar?select=*&silindi=eq.false',{headers:SB_HEADERS}),
```

- [ ] **Step 4: Dönem kapama akışındaki yevmiye_fisler arama sorgusuna filtre ekle**

`muhasebe-sene-sonu.html:151`'deki mevcut satır:

```js
    const r=await fetch(SB_URL+`/rest/v1/yevmiye_fisler?tip=eq.${encodeURIComponent(tip)}&belge_no=eq.${encodeURIComponent(belge)}&select=id,no`,{headers:SB_HEADERS});
```

Şununla değiştir:

```js
    const r=await fetch(SB_URL+`/rest/v1/yevmiye_fisler?tip=eq.${encodeURIComponent(tip)}&belge_no=eq.${encodeURIComponent(belge)}&select=id,no&silindi=eq.false`,{headers:SB_HEADERS});
```

- [ ] **Step 5: sene_sonu_kapanislar upsert'ine silindi:false ekle**

`muhasebe-sene-sonu.html:342`'deki mevcut satır:

```js
fetch(SB_URL+'/rest/v1/sene_sonu_kapanislar?on_conflict=yil',{method:'POST',headers:{...SB_HEADERS,'Prefer':'resolution=merge-duplicates'},body:JSON.stringify({yil:onizleme.yil,brut_kar_zarar:onizleme.brutKarZarar,vergi,net_sonuc:netSonuc,kullanan:kayit.kullanan})})
```

Şununla değiştir:

```js
fetch(SB_URL+'/rest/v1/sene_sonu_kapanislar?on_conflict=yil',{method:'POST',headers:{...SB_HEADERS,'Prefer':'resolution=merge-duplicates'},body:JSON.stringify({yil:onizleme.yil,brut_kar_zarar:onizleme.brutKarZarar,vergi,net_sonuc:netSonuc,kullanan:kayit.kullanan,silindi:false})})
```

- [ ] **Step 6: kapanmisYiliGeriAl içindeki yevmiye_fisler arama sorgusuna filtre ekle**

`muhasebe-sene-sonu.html:389`'daki mevcut satır:

```js
        const r=await fetch(SB_URL+`/rest/v1/yevmiye_fisler?tip=eq.donem_kapanis&belge_no=eq.${encodeURIComponent(belge)}&select=id`,{headers:SB_HEADERS});
```

Şununla değiştir:

```js
        const r=await fetch(SB_URL+`/rest/v1/yevmiye_fisler?tip=eq.donem_kapanis&belge_no=eq.${encodeURIComponent(belge)}&select=id&silindi=eq.false`,{headers:SB_HEADERS});
```

- [ ] **Step 7: kapanmisYiliGeriAl'daki yevmiye_fisler DELETE'ini PATCH'e çevir**

`muhasebe-sene-sonu.html:395`'teki mevcut satır:

```js
          await fetch(SB_URL+'/rest/v1/yevmiye_fisler?id=eq.'+row.id,{method:'DELETE',headers:SB_HEADERS});
```

Şununla değiştir:

```js
          await fetch(SB_URL+'/rest/v1/yevmiye_fisler?id=eq.'+row.id,{method:'PATCH',headers:SB_HEADERS,body:JSON.stringify({silindi:true})});
```

- [ ] **Step 8: kapanmisYiliGeriAl'daki sene_sonu_kapanislar DELETE'ini PATCH'e çevir**

`muhasebe-sene-sonu.html:401`'deki mevcut satır:

```js
  try{await fetch(SB_URL+'/rest/v1/sene_sonu_kapanislar?yil=eq.'+yil,{method:'DELETE',headers:SB_HEADERS});}catch(e){console.warn(e);}
```

Şununla değiştir:

```js
  try{await fetch(SB_URL+'/rest/v1/sene_sonu_kapanislar?yil=eq.'+yil,{method:'PATCH',headers:SB_HEADERS,body:JSON.stringify({silindi:true})});}catch(e){console.warn(e);}
```

- [ ] **Step 9: Grep ile doğrula**

```bash
grep -c "silindi" muhasebe-sene-sonu.html
```

Expected: 8 (satır 131'deki fiş-numarası sorgusu HARİÇ tüm diğer 8 nokta).

- [ ] **Step 10: Commit**

```bash
cd "C:\Users\USER\Projects\gurok-mal-kabul"
git add muhasebe-sene-sonu.html
git -c user.name="mehmetaraz0" -c user.email="mehmetaraz868@gmail.com" commit -m "feat: sene_sonu_kapanislar soft-delete'e geçirildi, muhasebe-sene-sonu.html'deki tüm ilgili sorgular güncellendi (Faz B6)"
```

---

### Task 13: Uçtan uca doğrulama

**Files:** (yok — sadece doğrulama)

- [ ] **Step 1: Statik doğrulama**

Task 1-12'nin grep adımlarının temiz geçtiğini teyit et. `git diff` ile fiş-numarası üretim sorgularının (satır ~131/328/337/357/449 civarındaki `no=like...order=no.desc` desenleri) HİÇBİRİNE `silindi` filtresi eklenmediğini doğrula — bu bilinçli bir istisna.

- [ ] **Step 2: curl ile canlı doğrulama**

```bash
SB_URL='https://xwytofysmgqtqjzkplfi.supabase.co'
SB_KEY='eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Inh3eXRvZnlzbWdxdHFqemtwbGZpIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODMyMjg5ODMsImV4cCI6MjA5ODgwNDk4M30.E7cRcOAvCmUFXWs45t4HE-igpmqWmSN2J66dOuvCHjA'
curl -s "$SB_URL/rest/v1/hesap_plani?select=silindi&limit=1" -H "apikey: $SB_KEY" -H "Authorization: Bearer $SB_KEY"
curl -s "$SB_URL/rest/v1/doviz_kurlari?select=silindi&limit=1" -H "apikey: $SB_KEY" -H "Authorization: Bearer $SB_KEY"
```

Expected: `silindi` kolonunun var olduğunu doğrulayan (boş dizi de olsa hata vermeyen) bir yanıt — sütun yoksa PostgREST hata döner.

- [ ] **Step 3: Kullanıcıya manuel test adımlarını bildir**

Kullanıcının tarayıcıda doğrulaması gereken akış:
1. `muhasebe-hesap-plani.html`'de bir hesap sil → listeden kaybolmalı, ama veritabanında hâlâ olmalı (silindi=true ile).
2. `muhasebe-kur.html`'de bugünkü kaydı sıfırla → listeden kaybolmalı.
3. `muhasebe-yevmiye.html`'de bir fiş sil → listeden kaybolmalı, ilgili raporlarda (muhasebe-raporlar, muhasebe-butce, muhasebe-asistan) da görünmemeli.
4. `muhasebe-sene-sonu.html`'de (varsa test verisiyle) bir dönemi kapat, sonra geri al → kapanış listeden kaybolmalı, yevmiye fişleri de raporlarda görünmemeli.
5. Aynı kod/tarih/fiş numarasıyla yeniden kayıt oluşturmayı dene (örn. silinen bir hesap kodunu tekrar ekle) → kaydın YENİDEN GÖRÜNÜR hale geldiğini doğrula (upsert silindi:false düzeltmesi çalışıyor mu).
6. Herhangi bir hata/kırılma olursa bildir.

- [ ] **Step 4: Kullanıcıdan onay al**

"Test ettim, çalışıyor" onayını bekle, ardından push kararını sor.
