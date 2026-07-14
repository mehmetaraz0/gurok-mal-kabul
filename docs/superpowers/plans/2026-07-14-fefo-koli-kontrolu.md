# FEFO Koli Kontrolü Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Koli QR okutma noktalarında (manuel çıkış + depo teslim), aynı üründen daha eski SKT'li bir koli varsa kullanıcıyı uyarmak.

**Architecture:** `koli_etiketleri` tablosu zaten her kolinin kendi SKT tarihini/depo/durum bilgisini tutuyor — yeni şema gerekmiyor. Her iki dosyaya (`stok-takip.html`, `depo-siparis.html`) aynı `fefoKontrolEt(koli)` yardımcı fonksiyonu eklenir (kod tabanının mevcut "küçük yardımcılar dosya başına tekrarlanır" deseniyle tutarlı), koli okutma fonksiyonlarının içine tek bir `confirm()` tabanlı yumuşak uyarı eklenir.

**Tech Stack:** Vanilla HTML/JS, Supabase REST (fetch) — build aracı/test çerçevesi yok.

## Global Constraints

- Uyarı yumuşak bir kapı (`confirm()`) — sert engelleme yok, kullanıcı isterse devam edebilir (spec).
- SKT tarihi olmayan kolilerde kontrol hiç çalıştırılmaz (spec).
- Reçete bazlı tüketim (`gunluk-tuketim.html`) kapsam dışı (spec).
- Yeni şema/tablo/kolon YOK — mevcut `koli_etiketleri` alanları yeterli (spec).

---

### Task 1: `stok-takip.html` — manuel çıkışta FEFO kontrolü

**Files:**
- Modify: `stok-takip.html:1196-1225` (`qrOkundu`)

**Interfaces:**
- Produces: `fefoKontrolEt(koli)` → `Promise<{koli_no,skt_tarihi}|null>` — Task 2'nin `depo-siparis.html`'deki kendi kopyası aynı imzayı taşıyacak (paylaşılan bir modül değil, ayrı dosyada aynı fonksiyon).

- [ ] **Step 1: `fefoKontrolEt()` fonksiyonunu ekle**

`qrOkundu` fonksiyonunun hemen ÖNÜNE ekle:

```js
// koli: okutulan koli nesnesi ({id,urun_kodu,depo_kodu,skt_tarihi,...}).
// Döner: aynı üründen/depodan, hâlâ depoda olan ve okutulandan daha eski
// SKT'li bir koli varsa {koli_no,skt_tarihi}, yoksa null.
async function fefoKontrolEt(koli){
  if(!koli.skt_tarihi)return null;
  try{
    const r=await fetch(SB_URL+'/rest/v1/koli_etiketleri?urun_kodu=eq.'+encodeURIComponent(koli.urun_kodu)+'&depo_kodu=eq.'+encodeURIComponent(koli.depo_kodu)+'&durum=eq.depoda&skt_tarihi=not.is.null&id=neq.'+koli.id+'&select=koli_no,skt_tarihi&order=skt_tarihi.asc&limit=1',{headers:SB_HEADERS});
    if(!r.ok)return null;
    const rows=await r.json();
    if(!rows.length)return null;
    const enEski=rows[0];
    if(new Date(enEski.skt_tarihi)<new Date(koli.skt_tarihi))return enEski;
    return null;
  }catch(e){return null;}
}
```

- [ ] **Step 2: `qrOkundu()`'ya FEFO kontrolünü ekle**

Mevcut (satır 1196-1213 civarı):
```js
async function qrOkundu(text){
  if(!text.startsWith('KOLI:'))return; // başka QR'ları yok say
  qrOkutmaDurdur();
  const koliId=text.slice(5).trim();
  showLoading();
  let koli=null;
  try{
    const r=await fetch(SB_URL+'/rest/v1/koli_etiketleri?id=eq.'+encodeURIComponent(koliId),{headers:SB_HEADERS});
    if(r.ok){const rows=await r.json();koli=rows[0]||null;}
  }catch(e){}
  hideLoading();
  if(!koli){showToast('❌ Koli bulunamadı — etiket geçersiz olabilir');return;}
  if(koli.durum==='cikti'){
    showToast(`⚠️ Bu koli ZATEN ÇIKMIŞ (${koli.cikis_tarihi?new Date(koli.cikis_tarihi).toLocaleString('tr-TR'):''}${koli.cikis_depo?' → '+koli.cikis_depo:''})`);
    return;
  }
  _okunanKoli=koli;
```
şuna çevir:
```js
async function qrOkundu(text){
  if(!text.startsWith('KOLI:'))return; // başka QR'ları yok say
  qrOkutmaDurdur();
  const koliId=text.slice(5).trim();
  showLoading();
  let koli=null;
  try{
    const r=await fetch(SB_URL+'/rest/v1/koli_etiketleri?id=eq.'+encodeURIComponent(koliId),{headers:SB_HEADERS});
    if(r.ok){const rows=await r.json();koli=rows[0]||null;}
  }catch(e){}
  hideLoading();
  if(!koli){showToast('❌ Koli bulunamadı — etiket geçersiz olabilir');return;}
  if(koli.durum==='cikti'){
    showToast(`⚠️ Bu koli ZATEN ÇIKMIŞ (${koli.cikis_tarihi?new Date(koli.cikis_tarihi).toLocaleString('tr-TR'):''}${koli.cikis_depo?' → '+koli.cikis_depo:''})`);
    return;
  }
  const eskiKoli=await fefoKontrolEt(koli);
  if(eskiKoli){
    const devam=confirm(`⚠️ FEFO Uyarısı: Bu üründen daha eski SKT'li bir koli var (Koli No: ${eskiKoli.koli_no||'?'}, SKT: ${new Date(eskiKoli.skt_tarihi).toLocaleDateString('tr-TR')}).\n\nÖnce o koli çıkarılmalı. Yine de bu koliyle devam etmek istiyor musunuz?`);
    if(!devam)return;
  }
  _okunanKoli=koli;
```

- [ ] **Step 3: Doğrula**

```bash
grep -n "function fefoKontrolEt\|FEFO Uyarısı" stok-takip.html
```
Expected: 2 satır (fonksiyon tanımı + uyarı mesajı içindeki metin).

- [ ] **Step 4: Kod okuyarak izleme**

`fefoKontrolEt`'in `qrOkundu` içinde `koli.durum==='cikti'` kontrolünden SONRA ama `_okunanKoli=koli;` atamasından ÖNCE çağrıldığını doğrula — böylece zaten çıkmış bir koli için FEFO uyarısı hiç tetiklenmez (gereksiz sorgu), ve kullanıcı "Hayır" derse form hiç doldurulmamış olur (`_okunanKoli` set edilmeden fonksiyondan çıkılır).

- [ ] **Step 5: Commit**

```bash
git add stok-takip.html
git -c user.name="mehmetaraz0" -c user.email="mehmetaraz868@gmail.com" commit -m "feat: add FEFO warning to manual cikis koli scan in stok-takip.html"
```

---

### Task 2: `depo-siparis.html` — teslim akışında FEFO kontrolü

**Files:**
- Modify: `depo-siparis.html:797-830` (`depoQrOkundu`)

**Interfaces:**
- Produces: `fefoKontrolEt(koli)` — Task 1'deki ile birebir aynı fonksiyon, bu dosyanın kendi kopyası olarak eklenir.

- [ ] **Step 1: `fefoKontrolEt()` fonksiyonunu ekle**

`depoQrOkundu` fonksiyonunun hemen ÖNÜNE ekle (Task 1'deki ile birebir aynı kod):

```js
// koli: okutulan koli nesnesi ({id,urun_kodu,depo_kodu,skt_tarihi,...}).
// Döner: aynı üründen/depodan, hâlâ depoda olan ve okutulandan daha eski
// SKT'li bir koli varsa {koli_no,skt_tarihi}, yoksa null.
async function fefoKontrolEt(koli){
  if(!koli.skt_tarihi)return null;
  try{
    const r=await fetch(SB_URL+'/rest/v1/koli_etiketleri?urun_kodu=eq.'+encodeURIComponent(koli.urun_kodu)+'&depo_kodu=eq.'+encodeURIComponent(koli.depo_kodu)+'&durum=eq.depoda&skt_tarihi=not.is.null&id=neq.'+koli.id+'&select=koli_no,skt_tarihi&order=skt_tarihi.asc&limit=1',{headers:SB_HEADERS});
    if(!r.ok)return null;
    const rows=await r.json();
    if(!rows.length)return null;
    const enEski=rows[0];
    if(new Date(enEski.skt_tarihi)<new Date(koli.skt_tarihi))return enEski;
    return null;
  }catch(e){return null;}
}
```

- [ ] **Step 2: `depoQrOkundu()`'ya FEFO kontrolünü ekle**

Mevcut (satır 797-819 civarı):
```js
async function depoQrOkundu(text,sipId){
  if(!text.startsWith('KOLI:'))return;
  // Aynı kodun art arda tekrar tetiklenmesini engelle (kamera saniyede 10 kare okur)
  if(Date.now()-_sonOkumaZamani<1500)return;
  _sonOkumaZamani=Date.now();

  const koliId=text.slice(5).trim();
  if(_onayKolileri.some(k=>k.id===koliId)){toast('⚠️ Bu koli bu talepte zaten okutuldu');return;}

  let koli=null;
  try{
    const r=await fetch(SB_URL+'/rest/v1/koli_etiketleri?id=eq.'+encodeURIComponent(koliId),{headers:SB_HEADERS});
    if(r.ok){const rows=await r.json();koli=rows[0]||null;}
  }catch(e){}
  if(!koli){toast('❌ Koli bulunamadı — etiket geçersiz');return;}
  if(koli.durum!=='depoda'){toast(`⚠️ Bu koli kullanılamaz (durum: ${koli.durum})`);return;}

  const s=DB.siparisler[sipId];if(!s)return;
```
şuna çevir:
```js
async function depoQrOkundu(text,sipId){
  if(!text.startsWith('KOLI:'))return;
  // Aynı kodun art arda tekrar tetiklenmesini engelle (kamera saniyede 10 kare okur)
  if(Date.now()-_sonOkumaZamani<1500)return;
  _sonOkumaZamani=Date.now();

  const koliId=text.slice(5).trim();
  if(_onayKolileri.some(k=>k.id===koliId)){toast('⚠️ Bu koli bu talepte zaten okutuldu');return;}

  let koli=null;
  try{
    const r=await fetch(SB_URL+'/rest/v1/koli_etiketleri?id=eq.'+encodeURIComponent(koliId),{headers:SB_HEADERS});
    if(r.ok){const rows=await r.json();koli=rows[0]||null;}
  }catch(e){}
  if(!koli){toast('❌ Koli bulunamadı — etiket geçersiz');return;}
  if(koli.durum!=='depoda'){toast(`⚠️ Bu koli kullanılamaz (durum: ${koli.durum})`);return;}

  const eskiKoli=await fefoKontrolEt(koli);
  if(eskiKoli){
    const devam=confirm(`⚠️ FEFO Uyarısı: Bu üründen daha eski SKT'li bir koli var (Koli No: ${eskiKoli.koli_no||'?'}, SKT: ${new Date(eskiKoli.skt_tarihi).toLocaleDateString('tr-TR')}).\n\nÖnce o koli çıkarılmalı. Yine de bu koliyle devam etmek istiyor musunuz?`);
    if(!devam)return;
  }

  const s=DB.siparisler[sipId];if(!s)return;
```

- [ ] **Step 3: Doğrula**

```bash
grep -n "function fefoKontrolEt\|FEFO Uyarısı" depo-siparis.html
```
Expected: 2 satır.

- [ ] **Step 4: Kod okuyarak izleme**

`fefoKontrolEt`'in bu dosyada `_onayKolileri.some(...)` (aynı koli bu talepte zaten okutulmuş mu) ve `koli.durum!=='depoda'` kontrollerinden SONRA, ama `_onayKolileri.push(...)` ve form güncellemesinden ÖNCE çağrıldığını doğrula — kullanıcı "Hayır" derse koli listeye hiç eklenmez, önceden okutulan kolileri etkilemez (`_onayKolileri`'ye sadece "Evet" ya da uyarısız durumlarda ekleme yapılır).

- [ ] **Step 5: Commit**

```bash
git add depo-siparis.html
git -c user.name="mehmetaraz0" -c user.email="mehmetaraz868@gmail.com" commit -m "feat: add FEFO warning to depo teslim koli scan in depo-siparis.html"
```

---

### Task 3: Uçtan uca doğrulama

**Files:** (yok — sadece doğrulama)

- [ ] **Step 1: Tutarlılık kontrolü**

```bash
grep -n "function fefoKontrolEt" stok-takip.html depo-siparis.html
```
Expected: her iki dosyada da tam olarak 1'er tane, birebir aynı kod (Task 1/2'nin kod bloğu identik).

- [ ] **Step 2: Kullanıcıya manuel test adımlarını bildir**

Kullanıcının tarayıcıda doğrulaması gereken akış (Node/Python bu ortamda yok, otomatik test yazılamıyor):
1. `mal-kabul-v2.html`'de aynı ürün için iki ayrı koli oluştur, farklı SKT tarihleri gir (biri daha eski, biri daha yeni) — koli etiketlerini yazdır/kaydet.
2. `stok-takip.html` → çıkış modalı → QR okut → önce YENİ tarihli koliyi okut → "⚠️ FEFO Uyarısı" mesajının çıktığını, eski kolinin koli no/SKT'sini doğru gösterdiğini doğrula.
3. "Hayır" de → formun doldurulmadığını doğrula. Tekrar okut, bu sefer "Evet" de → formun normal şekilde dolduğunu doğrula.
4. Önce ESKİ tarihli koliyi okut → hiçbir uyarı çıkmadığını doğrula (bu zaten doğru sıradaki koli).
5. `depo-siparis.html`'de bir talebi onaylarken aynı senaryoyu (yeni koliyi önce okutma) tekrarla, aynı uyarının çıktığını doğrula.
6. SKT tarihi girilmemiş bir koliyi okut → hiçbir FEFO kontrolü/uyarısı tetiklenmediğini doğrula.

- [ ] **Step 3: Kullanıcıdan onay al, sonra push**

```bash
git fetch
git log --oneline main..origin/main
```
Expected: paralel oturumdan gelen değişiklik var mı kontrol et, varsa kullanıcıya bildir. Yoksa kullanıcı onayıyla `git push`.
