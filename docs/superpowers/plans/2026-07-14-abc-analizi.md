# ABC Analizi / Stok Sınıflandırması Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `stok-takip.html`'de her ürünü mevcut stok değeri + son 7 günlük tüketim değerine göre A/B/C sınıfına ayırıp (Pareto 80/15/5), stok listesinde rozet + filtre sekmesi olarak göstermek.

**Architecture:** İki katman: (1) veri katmanı — `loadFiyatMap()` (fiyat view'larını çeker) ve `hesaplaAbcSiniflari()` (skor hesaplayıp `db.abcSiniflari`'ı doldurur), sayfa `init()`'inde `loadDB()`'den hemen sonra çalıştırılır; (2) UI katmanı — `renderStok()`'a ABC rozeti + yeni `#abc-tabs` filtre sekmesi + `abcFilter` durumuna göre filtreleme eklenir. Hiçbir yeni tablo/kolon yok, her şey anlık hesaplanır.

**Tech Stack:** Vanilla JS, doğrudan `fetch()` ile Supabase REST API (`SB_URL`/`SB_HEADERS`, dosyada zaten tanımlı). Build aracı yok, test çerçevesi yok (Node/Python bu ortamda mevcut değil) — doğrulama grep + manuel kod okuma + kullanıcının tarayıcıda elle test etmesiyle yapılır.

## Global Constraints

- Skor formülü: `skor = stok_degeri + (tuketim_degeri × 4)`, `stok_degeri = toplam_miktar(urun_kodu, tüm depo/oteller) × fiyat`, `tuketim_degeri = son_7_gun_tuketim_miktari(urun_kodu) × fiyat`.
- Fiyat kaynağı: `urun_guncel_fiyat` view (son fatura fiyatı) taban, `urun_fifo_fiyat` view (FIFO fiyat) varsa onu ezer — `gunluk-tuketim.html`'in `loadFiyatMap()` fonksiyonuyla birebir aynı öncelik sırası ve query şekli.
- Tüketim tanımı: `db.hareketler`'den (zaten `loadDB()` ile tüm geçmiş yüklü, yeni fetch YOK) `tip==='cikis'`, `tarih >= (şimdi - 7 gün)`, `aciklama` alanı `gunluk_tuketim` veya `recete_tuketim` içeren satırlar. Güvenlik Stoğu özelliğiyle aynı tanım.
- Sınıflandırma: skora göre büyükten küçüğe sıralı ürünlerin kümülatif skorunun ilk %80'i A, sonraki %15'i (yani %95'e kadar) B, kalanı C. Toplam skor ≤0 ise TÜM ürünler C.
- Kalıcı saklama YOK — her `loadDB()` sonrası yeniden hesaplanır, veritabanına yazılmaz.
- `db.abcSiniflari` sadece `urun_kodu` anahtarlı global bir map (`{urun_kodu: 'A'|'B'|'C'}`), depo/otel ayrımı yok.
- ABC filtre sekmesi mevcut arama/kategori/durum filtreleriyle AND mantığıyla birlikte çalışır (kategori filtresinin zaten çalıştığı gibi).

---

### Task 1: Veri katmanı — `loadFiyatMap()` + `hesaplaAbcSiniflari()`

**Files:**
- Modify: `stok-takip.html:650-651` (state değişkeni), `stok-takip.html:677` civarı (`loadDB()`'nin hemen sonrasına yeni fonksiyonlar), `stok-takip.html` init akışı (satır ~2044 civarı, `await loadDB();` çağrısının hemen sonrası)

**Interfaces:**
- Consumes: mevcut `SB_URL`, `SB_HEADERS`; `db.stok[depoKodu][urunKodu]={lnKod,miktar,...}`; `db.hareketler[id]={lnKod,tip,miktar,tarih,aciklama,...}` (tümü `loadDB()`'nin zaten doldurduğu state, satır 672-719).
- Produces: `async function loadFiyatMap()` → `db.fiyatMap={urun_kodu:{fiyat,birim,kaynak}}`. `function hesaplaAbcSiniflari()` → `db.abcSiniflari={urun_kodu:'A'|'B'|'C'}`. Task 2 bu ikisini (özellikle `db.abcSiniflari`) tüketir.

- [ ] **Step 1: `abcFilter` state değişkenini ekle**

`stok-takip.html`'de satır 650-651'deki şu iki satırı:

```js
let stokFilter   = 'tumu';
let katFilter    = 'tumu';
```

şununla değiştir:

```js
let stokFilter   = 'tumu';
let katFilter    = 'tumu';
let abcFilter    = 'tumu';
```

- [ ] **Step 2: `loadFiyatMap()` fonksiyonunu ekle**

`stok-takip.html`'de `async function loadDB(){` fonksiyonunun kapanış satırından (satır 677'den başlayan fonksiyonun `}` ile bittiği satır — dosyada satır 719, `hideLoading();\n}` bloğunun hemen sonrası) hemen sonra, yeni bir satıra şunu ekle:

```js
async function loadFiyatMap(){
  db.fiyatMap={};
  try{
    const rSon=await fetch(SB_URL+'/rest/v1/urun_guncel_fiyat?select=urun_kodu,birim_fiyat,birim',{headers:SB_HEADERS});
    if(rSon.ok){(await rSon.json()).forEach(row=>{db.fiyatMap[row.urun_kodu]={fiyat:parseFloat(row.birim_fiyat)||0,birim:row.birim,kaynak:'son_fatura'};});}
  }catch(e){console.warn(e);}
  try{
    const rFifo=await fetch(SB_URL+'/rest/v1/urun_fifo_fiyat?select=urun_kodu,birim_fiyat,birim,fiyat_kaynagi',{headers:SB_HEADERS});
    if(rFifo.ok){(await rFifo.json()).forEach(row=>{db.fiyatMap[row.urun_kodu]={fiyat:parseFloat(row.birim_fiyat)||0,birim:row.birim,kaynak:row.fiyat_kaynagi==='tahmini'?'fifo_tahmini':'fifo'};});}
  }catch(e){console.warn(e);}
}

function hesaplaAbcSiniflari(){
  db.abcSiniflari={};
  const stokMiktar={};
  Object.values(db.stok).forEach(depoStok=>{
    Object.values(depoStok).forEach(s=>{
      stokMiktar[s.lnKod]=(stokMiktar[s.lnKod]||0)+(parseFloat(s.miktar)||0);
    });
  });
  const yediGunOnce=Date.now()-7*24*60*60*1000;
  const tuketimMiktar={};
  Object.values(db.hareketler).forEach(h=>{
    if(h.tip!=='cikis'||h.tarih<yediGunOnce)return;
    if(!/gunluk_tuketim|recete_tuketim/.test(h.aciklama||''))return;
    tuketimMiktar[h.lnKod]=(tuketimMiktar[h.lnKod]||0)+h.miktar;
  });
  const tumUrunKodlari=new Set([...Object.keys(stokMiktar),...Object.keys(tuketimMiktar)]);
  const skorlar=[...tumUrunKodlari].map(kod=>{
    const fiyat=db.fiyatMap[kod]?.fiyat||0;
    const stokDegeri=(stokMiktar[kod]||0)*fiyat;
    const tuketimDegeri=(tuketimMiktar[kod]||0)*fiyat;
    return{kod,skor:stokDegeri+(tuketimDegeri*4)};
  });
  const toplamSkor=skorlar.reduce((t,s)=>t+s.skor,0);
  if(toplamSkor<=0){
    skorlar.forEach(s=>db.abcSiniflari[s.kod]='C');
    return;
  }
  skorlar.sort((a,b)=>b.skor-a.skor);
  let kumulatif=0;
  skorlar.forEach(s=>{
    kumulatif+=s.skor;
    const yuzde=kumulatif/toplamSkor;
    db.abcSiniflari[s.kod]=yuzde<=0.80?'A':yuzde<=0.95?'B':'C';
  });
}
```

- [ ] **Step 3: Init akışına bağla**

`stok-takip.html`'de init IIFE içindeki şu satırı bul (`await loadDB();` — `buildIadeFirmaSelector()` çağrısından hemen önce):

```js
  await loadDB();
  buildIadeFirmaSelector(); // db.cariler loadDB() içinde dolduğu için ondan sonra çağrılmalı
```

şununla değiştir:

```js
  await loadDB();
  await loadFiyatMap();
  hesaplaAbcSiniflari();
  buildIadeFirmaSelector(); // db.cariler loadDB() içinde dolduğu için ondan sonra çağrılmalı
```

- [ ] **Step 4: Doğrulama**

Bu dosyada test çerçevesi yok. Doğrulama için:

```bash
grep -n "function loadFiyatMap\|function hesaplaAbcSiniflari\|let abcFilter\|await loadFiyatMap()\|hesaplaAbcSiniflari()" stok-takip.html
```

Expected: `loadFiyatMap` tanımı (1), `hesaplaAbcSiniflari` tanımı (1), `abcFilter` state satırı (1), init'teki `loadFiyatMap()` çağrısı (1), init'teki `hesaplaAbcSiniflari()` çağrısı (1) — toplam 5 eşleşme.

- [ ] **Step 5: Commit**

```bash
git add stok-takip.html
git commit -m "feat: add ABC classification data layer (loadFiyatMap, hesaplaAbcSiniflari)"
```

---

### Task 2: UI katmanı — rozet + filtre sekmesi

**Files:**
- Modify: `stok-takip.html:159` civarı (yeni `#abc-tabs` div), `stok-takip.html:833-896` (`renderStok()` fonksiyonu — kategori tabs bloğu, filtrele bloğu, satır şablonu), `stok-takip.html:937` civarı (`filterKat`'ın yanına `filterAbc`)

**Interfaces:**
- Consumes: Task 1'in ürettiği `db.abcSiniflari={urun_kodu:'A'|'B'|'C'}` ve `let abcFilter='tumu';` state değişkeni.
- Produces: `function filterAbc(sinif,el)` — başka hiçbir task tüketmiyor, sadece UI'dan `onclick` ile çağrılıyor.

- [ ] **Step 1: `#abc-tabs` div'ini ekle**

`stok-takip.html`'de satır 159'daki şu satırı:

```html
    <div class="filter-tabs" id="kat-tabs"></div>
```

şununla değiştir:

```html
    <div class="filter-tabs" id="kat-tabs"></div>
    <div class="filter-tabs" id="abc-tabs"></div>
```

- [ ] **Step 2: `renderStok()`'a ABC sekmesi üretimini ekle**

`stok-takip.html`'de satır 841-843'teki şu bloğu:

```js
  document.getElementById('kat-tabs').innerHTML=
    `<button class="filter-tab ${katFilter==='tumu'?'active':''}" onclick="filterKat('tumu',this)">Tümü</button>`+
    [...katSet].sort().map(k=>`<button class="filter-tab ${katFilter===k?'active':''}" onclick="filterKat('${k}',this)">${k}</button>`).join('');
```

şununla değiştir (mevcut 3 satırı koru, hemen altına yeni blok ekle):

```js
  document.getElementById('kat-tabs').innerHTML=
    `<button class="filter-tab ${katFilter==='tumu'?'active':''}" onclick="filterKat('tumu',this)">Tümü</button>`+
    [...katSet].sort().map(k=>`<button class="filter-tab ${katFilter===k?'active':''}" onclick="filterKat('${k}',this)">${k}</button>`).join('');

  document.getElementById('abc-tabs').innerHTML=
    `<button class="filter-tab ${abcFilter==='tumu'?'active':''}" onclick="filterAbc('tumu',this)">Tümü</button>`+
    ['A','B','C'].map(sn=>`<button class="filter-tab ${abcFilter===sn?'active':''}" onclick="filterAbc('${sn}',this)">${sn} Sınıfı</button>`).join('');
```

- [ ] **Step 3: Filtrele bloğuna ABC kontrolü ekle**

`stok-takip.html`'de satır 846-848'deki şu bloğu:

```js
  let filtered=items.filter(s=>{
    if(search&&!s.urunAd?.toLowerCase().includes(search)&&!s.lnKod?.toLowerCase().includes(search))return false;
    if(katFilter!=='tumu'&&!s.lnKod?.startsWith(katFilter))return false;
```

şununla değiştir:

```js
  let filtered=items.filter(s=>{
    if(search&&!s.urunAd?.toLowerCase().includes(search)&&!s.lnKod?.toLowerCase().includes(search))return false;
    if(katFilter!=='tumu'&&!s.lnKod?.startsWith(katFilter))return false;
    if(abcFilter!=='tumu'&&(db.abcSiniflari[s.lnKod]||'C')!==abcFilter)return false;
```

- [ ] **Step 4: Satır şablonuna ABC rozetini ekle**

`stok-takip.html`'de satır 885'teki şu satırı:

```js
          <div style="font-size:10px;color:var(--gray-400);font-family:monospace;">${s.lnKod} <span class="kat-badge">${s.lnKod?.slice(0,5)||''}</span></div>
```

şununla değiştir:

```js
          <div style="font-size:10px;color:var(--gray-400);font-family:monospace;">${s.lnKod} <span class="kat-badge">${s.lnKod?.slice(0,5)||''}</span> <span style="background:${{A:'#dc2626',B:'#d97706',C:'#6b7280'}[db.abcSiniflari[s.lnKod]||'C']};color:#fff;font-size:10px;font-weight:700;padding:1px 5px;border-radius:4px;">${db.abcSiniflari[s.lnKod]||'C'}</span></div>
```

- [ ] **Step 5: `filterAbc` fonksiyonunu ekle**

`stok-takip.html`'de satır 937'deki şu satırı:

```js
function filterKat(k,el){katFilter=k;renderStok();}
```

şununla değiştir (mevcut satırı koru, hemen altına ekle):

```js
function filterKat(k,el){katFilter=k;renderStok();}
function filterAbc(sinif,el){abcFilter=sinif;renderStok();}
```

- [ ] **Step 6: Doğrulama**

```bash
grep -n "id=\"abc-tabs\"\|function filterAbc\|abcFilter\|db.abcSiniflari\[s.lnKod\]" stok-takip.html
```

Expected: en az 6 eşleşme (div tanımı, fonksiyon tanımı, `renderStok()` içindeki üretim bloğu + filtrele kontrolü + rozet kullanımı, `filterAbc` çağrısı).

- [ ] **Step 7: Commit**

```bash
git add stok-takip.html
git commit -m "feat: add ABC classification badge and filter tab to stok-takip.html"
```

---

### Task 3: Uçtan uca doğrulama

**Files:** (yok — sadece doğrulama)

- [ ] **Step 1: Tutarlılık kontrolü**

```bash
grep -n "function loadFiyatMap\|function hesaplaAbcSiniflari\|function filterAbc\|id=\"abc-tabs\"" stok-takip.html
```
Expected: 4 fonksiyon/element tanımı, hepsi `stok-takip.html` içinde, tekrarsız.

- [ ] **Step 2: Kullanıcıya manuel test adımlarını bildir**

Kullanıcının tarayıcıda doğrulaması gereken akış (Node/Python bu ortamda yok, otomatik test yazılamıyor):
1. `stok-takip.html`'i aç, sayfa yüklendikten sonra stok listesindeki ürün satırlarında ürün kodu yanında bir A/B/C rozeti göründüğünü doğrula.
2. Stok değeri yüksek veya son 7 günde çok tüketilen bir ürünün "A" ya da "B" rozeti aldığını, az/hiç hareket görmeyen bir ürünün "C" aldığını doğrula.
3. `#abc-tabs`'taki "A Sınıfı" sekmesine tıkla → sadece A rozetli ürünlerin listelendiğini doğrula. Aynı anda bir kategori sekmesi de seçiliyse (örn. belirli bir ürün grubu), iki filtrenin birlikte (AND) çalıştığını doğrula.
4. Hiç fiyat verisi olmayan bir ürünün (varsa) "C" rozeti aldığını doğrula.
5. "Tümü" sekmesine dönüp tüm ürünlerin tekrar göründüğünü doğrula.

- [ ] **Step 3: Kullanıcıdan onay al, sonra push**

```bash
git fetch
git log --oneline main..origin/main
```
Expected: paralel oturumdan gelen değişiklik var mı kontrol et, varsa kullanıcıya bildir. Yoksa kullanıcı onayıyla `git push`.
