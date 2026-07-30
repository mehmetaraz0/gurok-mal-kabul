# Sayım — Koli QR ile Otomatik Sayım Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `stok-takip.html`'in Sayım sekmesine, mevcut koli QR (`KOLI:<uuid>` → `koli_etiketleri`) altyapısını yeniden kullanan bir "Koli QR ile Say" modu eklemek — koli okutulunca ilgili ürünün Sayılan Miktar'ı otomatik artar, elle giriş etiketsiz ürünler için aynen kalır.

**Architecture:** Yeni Supabase tablosu/kolonu yok. `depo-siparis.html`'deki `depoQrOkundu()`'nun (debounce + çift-okutma engeli + `koli_etiketleri` lookup) birebir aynı deseni, farklı bir hedefe (Sayım'ın `sayimSatirlari`/DOM input'u) uygulanır. QR ile biriken toplamlar (`_sayimQrToplam`) filtre değişikliğinden etkilenmeyen ayrı bir state'te tutulur, her `renderSayimYeni()` çağrısında görünür satırlara yeniden uygulanır.

**Tech Stack:** Vanilla JS, `Html5Qrcode` (zaten CDN'den yükleniyor), mevcut `koli_etiketleri` REST endpoint'i.

## Global Constraints

- Sadece `stok-takip.html` değişir — başka hiçbir dosyaya dokunulmaz.
- Yeni Supabase tablosu/kolonu yok — sadece mevcut `koli_etiketleri`
  okunuyor, `sayim_oturumlari`/`sayim_detaylari`'ya yazım şekli değişmiyor.
- Debounce: aynı karenin 1.5 saniye içinde tekrar tetiklenmesi yok sayılır
  (`depoQrOkundu()` ile aynı değer).
- Çift-okutma engeli: aynı koli id, aktif sayım oturumunda ikinci kez
  okutulursa reddedilir (state sıfırlanana kadar kalıcı).
- Kabul kriterleri: `koli.durum==='depoda'` VE `koli.depo_kodu===aktifDepoId`
  — ikisinden biri sağlanmazsa reddedilir.
- FEFO kontrolü YOK — kapsam dışı, sayım stok hareketi değil (design doc'ta
  gerekçesi var).
- `_sayimQrToplam`/`_sayimOkutulanKoliler` sadece `renderSayimTab()`'da
  (yeni oturum) sıfırlanır — `filterSayimKat()` ile SIFIRLANMAZ (mevcut
  `sayimSatirlari={}` davranışı `filterSayimKat()`'ta aynen kalır,
  değiştirilmez).
- Her task sonunda `git commit` (doğrudan `main`'e, bu depoda feature
  branch kullanılmıyor).

---

### Task 1: Sayım sekmesine Koli QR okutma ekle

**Files:**
- Modify: `stok-takip.html`

**Interfaces:**
- Produces: `sayimQrOkutmaBaslat()`, `sayimQrOkutmaDurdur()`,
  `sayimQrOkundu(text)`, `_sayimQrToplam` (`{lnKod:{miktar,koliSayisi}}`),
  `_sayimOkutulanKoliler` (dizi) — bu isimler Task 2'nin doğrulama
  adımlarında referans alınır.
- Consumes: mevcut `aktifDepoId`, `sayimFarkGuncelle(lnKod,val)`,
  `showToast(msg)`, `round2(n)`, `SB_URL`, `SB_HEADERS`, `Html5Qrcode`
  (CDN'den zaten yükleniyor).

- [ ] **Step 1: HTML — düğme ve kamera kutusu ekle**

Mevcut (Sayım sekmesi arama kutusunun hemen altı):
```html
    <div id="sayim-yeni-alani">
      <div class="search-box">
        <input type="text" id="sayim-search" placeholder="Ürün adı veya LN kodu ara..." oninput="renderSayimYeni()">
      </div>
```

Yeni (arama kutusundan hemen sonra QR düğmesi + kamera kutusu eklendi):
```html
    <div id="sayim-yeni-alani">
      <div class="search-box">
        <input type="text" id="sayim-search" placeholder="Ürün adı veya LN kodu ara..." oninput="renderSayimYeni()">
      </div>
      <button class="btn" style="width:100%;background:#e8e5f0;color:#4a3f68;font-weight:700;margin:8px 0" onclick="sayimQrOkutmaBaslat()">📷 Koli QR ile Say</button>
      <div id="sayim-qr-okuyucu" style="display:none;margin-bottom:10px;border-radius:12px;overflow:hidden"></div>
```

(Not: mevcut `<div class="filter-tabs" id="sayim-kat-tabs"></div>` ve
`<div id="sayim-liste"></div>` satırları AYNEN kalır, bu iki elementten
sonra geliyor — yukarıdaki blok sadece arayla `sayim-kat-tabs`'ten önceki
kısmı gösteriyor.)

- [ ] **Step 2: Global state ekle**

Mevcut (`stok-takip.html`, sayım globallerinin olduğu blok):
```js
const SAYIM_ESIK_YUZDE=10;
let sayimSatirlari={}; // {lnKod:{sayilan,fark,farkYuzde,aciklama}}
let sayimKatFilter='tumu';
let sayimGorunum='yeni'; // 'yeni' | 'onay'
let _sayimSistemMiktar={},_sayimUrunAdi={},_sayimBirim={};
```

Yeni:
```js
const SAYIM_ESIK_YUZDE=10;
let sayimSatirlari={}; // {lnKod:{sayilan,fark,farkYuzde,aciklama}}
let sayimKatFilter='tumu';
let sayimGorunum='yeni'; // 'yeni' | 'onay'
let _sayimSistemMiktar={},_sayimUrunAdi={},_sayimBirim={};
let _sayimQrToplam={}; // {lnKod:{miktar,koliSayisi}} — filtre değişince silinmez, sadece yeni oturumda sıfırlanır
let _sayimOkutulanKoliler=[]; // bu sayım oturumunda okutulan koli id'leri — çift-okutma engeli
let _sayimQrScanner=null;
let _sayimSonOkumaZamani=0;
```

- [ ] **Step 3: Yeni oturumda QR state'ini sıfırla**

Mevcut:
```js
function renderSayimTab(){
  const costControlMi=currentUser?.rol==='cost_control';
  document.getElementById('sayim-gorunum-tabs').style.display=costControlMi?'flex':'none';
  if(!costControlMi){sayimGorunumDegistir('yeni',null);}
  sayimSatirlari={};
  renderSayimYeni();
  if(costControlMi)sayimOnayBekleyenSayisiGuncelle();
}
```

Yeni:
```js
function renderSayimTab(){
  const costControlMi=currentUser?.rol==='cost_control';
  document.getElementById('sayim-gorunum-tabs').style.display=costControlMi?'flex':'none';
  if(!costControlMi){sayimGorunumDegistir('yeni',null);}
  sayimSatirlari={};
  _sayimQrToplam={};
  _sayimOkutulanKoliler=[];
  renderSayimYeni();
  if(costControlMi)sayimOnayBekleyenSayisiGuncelle();
}
```

(`filterSayimKat()` fonksiyonuna DOKUNULMAZ — sadece `sayimSatirlari={}`
yapmaya devam eder, `_sayimQrToplam`/`_sayimOkutulanKoliler` orada
sıfırlanmaz.)

- [ ] **Step 4: Render döngüsüne QR toplamını uygula + input'a id ver**

Mevcut:
```js
  _sayimSistemMiktar={};_sayimUrunAdi={};_sayimBirim={};
  const c=document.getElementById('sayim-liste');
  if(!filtered.length){c.innerHTML='<div class="card" style="text-align:center;color:var(--gray-500)">Ürün bulunamadı</div>';return;}
  c.innerHTML=filtered.map(s=>{
    _sayimSistemMiktar[s.lnKod]=parseFloat(s.miktar)||0;
    _sayimUrunAdi[s.lnKod]=s.urunAd;
    _sayimBirim[s.lnKod]=s.birim;
    return `
    <div class="card" style="padding:10px 14px">
      <div style="display:flex;justify-content:space-between;align-items:center;margin-bottom:6px;gap:8px">
        <div><div style="font-weight:700;font-size:13px">${escapeHtml(s.urunAd)}</div><div style="font-size:10px;color:var(--gray-400)">${escapeHtml(s.lnKod)} • Sistem: ${s.miktar} ${escapeHtml(s.birim||'')}</div></div>
        <input type="number" step="any" placeholder="Sayılan" style="width:90px;padding:8px;border:1.5px solid var(--gray-300);border-radius:var(--radius-sm)" oninput="sayimFarkGuncelle('${s.lnKod}',this.value)">
      </div>
      <div id="sayim-fark-${s.lnKod}"></div>
      <div id="sayim-aciklama-alan-${s.lnKod}"></div>
    </div>`;
  }).join('');
}
```

Yeni (`input`'a `id` + QR toplamı varsa `value` eklendi, `c.innerHTML=...`
sonrasında görünen satırlar için `sayimFarkGuncelle()` tetikleyen bir blok
eklendi):
```js
  _sayimSistemMiktar={};_sayimUrunAdi={};_sayimBirim={};
  const c=document.getElementById('sayim-liste');
  if(!filtered.length){c.innerHTML='<div class="card" style="text-align:center;color:var(--gray-500)">Ürün bulunamadı</div>';return;}
  c.innerHTML=filtered.map(s=>{
    _sayimSistemMiktar[s.lnKod]=parseFloat(s.miktar)||0;
    _sayimUrunAdi[s.lnKod]=s.urunAd;
    _sayimBirim[s.lnKod]=s.birim;
    const qrToplam=_sayimQrToplam[s.lnKod];
    const baslangicDeger=qrToplam?qrToplam.miktar:'';
    return `
    <div class="card" style="padding:10px 14px">
      <div style="display:flex;justify-content:space-between;align-items:center;margin-bottom:6px;gap:8px">
        <div><div style="font-weight:700;font-size:13px">${escapeHtml(s.urunAd)}</div><div style="font-size:10px;color:var(--gray-400)">${escapeHtml(s.lnKod)} • Sistem: ${s.miktar} ${escapeHtml(s.birim||'')}</div></div>
        <input type="number" step="any" id="sayim-inp-${s.lnKod}" placeholder="Sayılan" style="width:90px;padding:8px;border:1.5px solid var(--gray-300);border-radius:var(--radius-sm)" value="${baslangicDeger}" oninput="sayimFarkGuncelle('${s.lnKod}',this.value)">
      </div>
      <div id="sayim-fark-${s.lnKod}"></div>
      <div id="sayim-aciklama-alan-${s.lnKod}"></div>
    </div>`;
  }).join('');
  Object.keys(_sayimQrToplam).forEach(lnKod=>{
    if(_sayimQrToplam[lnKod].miktar>0&&document.getElementById('sayim-inp-'+lnKod)){
      sayimFarkGuncelle(lnKod,String(_sayimQrToplam[lnKod].miktar));
    }
  });
}
```

- [ ] **Step 5: QR okutma fonksiyonlarını ekle**

`renderSayimYeni()` fonksiyonundan hemen sonra (yani `sayimFarkGuncelle()`
fonksiyonundan önce) ekle:

```js
function sayimQrOkutmaBaslat(){
  const kutu=document.getElementById('sayim-qr-okuyucu');
  if(_sayimQrScanner){sayimQrOkutmaDurdur();return;}
  kutu.style.display='block';
  const basla=()=>{
    _sayimQrScanner=new Html5Qrcode('sayim-qr-okuyucu');
    _sayimQrScanner.start(
      {facingMode:'environment'},
      {fps:10,qrbox:220},
      async(text)=>{await sayimQrOkundu(text);},
      ()=>{}
    ).catch(e=>{showToast('⚠️ Kamera açılamadı: '+e);kutu.style.display='none';_sayimQrScanner=null;});
  };
  if(typeof Html5Qrcode==='undefined'){
    const sc=document.createElement('script');
    sc.src='https://cdnjs.cloudflare.com/ajax/libs/html5-qrcode/2.3.8/html5-qrcode.min.js';
    sc.onload=basla;
    document.head.appendChild(sc);
  }else basla();
}

function sayimQrOkutmaDurdur(){
  if(_sayimQrScanner){_sayimQrScanner.stop().catch(()=>{});_sayimQrScanner=null;}
  document.getElementById('sayim-qr-okuyucu').style.display='none';
}

async function sayimQrOkundu(text){
  if(!text.startsWith('KOLI:'))return;
  if(Date.now()-_sayimSonOkumaZamani<1500)return;
  _sayimSonOkumaZamani=Date.now();

  const koliId=text.slice(5).trim();
  if(_sayimOkutulanKoliler.includes(koliId)){showToast('⚠️ Bu koli bu sayımda zaten okutuldu');return;}

  let koli=null;
  try{
    const r=await fetch(SB_URL+'/rest/v1/koli_etiketleri?id=eq.'+encodeURIComponent(koliId),{headers:SB_HEADERS});
    if(r.ok){const rows=await r.json();koli=rows[0]||null;}
  }catch(e){}
  if(!koli){showToast('❌ Koli bulunamadı — etiket geçersiz olabilir');return;}
  if(koli.durum!=='depoda'){showToast(`⚠️ Bu koli kullanılamaz (durum: ${koli.durum})`);return;}
  if(koli.depo_kodu!==aktifDepoId){showToast('⚠️ Bu koli farklı bir depoya ait, bu sayıma dahil edilemez');return;}

  _sayimOkutulanKoliler.push(koliId);
  const lnKod=koli.urun_kodu;
  const miktar=parseFloat(koli.miktar)||0;
  if(!_sayimQrToplam[lnKod])_sayimQrToplam[lnKod]={miktar:0,koliSayisi:0};
  _sayimQrToplam[lnKod].miktar=round2(_sayimQrToplam[lnKod].miktar+miktar);
  _sayimQrToplam[lnKod].koliSayisi++;

  const inp=document.getElementById('sayim-inp-'+lnKod);
  if(inp){
    inp.value=_sayimQrToplam[lnKod].miktar;
    sayimFarkGuncelle(lnKod,String(_sayimQrToplam[lnKod].miktar));
  }
  showToast(`✅ ${koli.urun_adi} +${miktar} ${koli.birim} (toplam: ${_sayimQrToplam[lnKod].miktar}, ${_sayimQrToplam[lnKod].koliSayisi} koli)`);
}
```

- [ ] **Step 6: Tarayıcıda doğrula**

`preview_start` ile statik sunucuyu aç, fabrik bir oturum yaz, Stok
Takip'i aç, bir depo seç, Sayım sekmesine geç. Konsoldan doğrudan test et
(gerçek kamera/QR gerekmeden):

```js
// Fabrik koli — aktifDepoId ile aynı depo_kodu kullan
window._testKoli = {id:'test-koli-1', urun_kodu: /* ekrandaki gerçek bir lnKod */, urun_adi:'Test Ürün', miktar:5, birim:'KG', depo_kodu:aktifDepoId, durum:'depoda'};
// fetch'i geçici olarak bu objeyi döndürecek şekilde mockla, ya da doğrudan sayimQrOkundu içindeki lookup'ı atlayıp mantığı elle tetikle:
```

Kontrol listesi:
- `sayimQrOkundu('KOLI:test-koli-1')` çağrısı (fetch mocklanmış veya
  gerçek bir test `koli_etiketleri` satırı ile) doğru üründe "Sayılan
  Miktar" input'unu günceller, fark/açıklama alanı doğru render olur.
- Aynı `KOLI:test-koli-1` ikinci kez çağrılınca "zaten okutuldu" toast'ı
  çıkar, miktar tekrar eklenmez.
- `durum:'cikti'` olan bir koli reddedilir.
- `depo_kodu` farklı bir koli reddedilir.
- Kategori filtresi değiştirilip geri dönülünce QR ile eklenen değer hâlâ
  input'ta görünür (silinmemiş).
- Konsolda hiç hata yok (`read_console_messages`, `onlyErrors:true`).

- [ ] **Step 7: Commit**

```bash
git add stok-takip.html
git commit -m "feat: sayim sekmesine koli QR ile otomatik sayim ekle"
```

---

### Task 2: Uçtan uca doğrulama

**Files:**
- Modify: yok (sadece doğrulama)

**Interfaces:**
- Consumes: Task 1'in tüm fonksiyonları.

- [ ] **Step 1: Tam akış testi**

1. Aynı ürüne ait 2 farklı koli (`miktar:3` ve `miktar:4`, `birim:'KG'`,
   aynı `urun_kodu`, `depo_kodu=aktifDepoId`, `durum:'depoda'`) art arda
   okut — Sayılan Miktar'ın `7` olduğunu, "2 koli" göründüğünü doğrula.
2. Elle bir üçüncü değer daha ekleyip (input'a manuel `+1` yazarak, input
   `8` olacak şekilde) `sayimFarkGuncelle`'in bunu da kabul ettiğini
   doğrula (QR ile elle giriş aynı input üzerinde sorunsuz birleşiyor).
3. "Sayımı Tamamla" akışının (`sayimTamamla()`) bu QR-kaynaklı satırı da
   normal bir satır gibi işlediğini doğrula (kod değişmedi ama gerçek
   veriyle tetiklendiğinde hata vermediğini teyit et).
4. Konsolda hiç JS hatası olmadığını doğrula.

- [ ] **Step 2: Obsidian vault güncelle**

`D:\ERP-Bilgi-Haritasi\02-Moduller\Stok-Depo.md`'ye (dosya yoksa
`D:\ERP-Bilgi-Haritasi\02-Moduller\` altında en yakın ilgili dosyaya) yeni
bir bölüm ekle:
```
## Sayım — Koli QR ile otomatik sayım (2026-07-30)
Sayım sekmesi artık koli QR'larını (`KOLI:<uuid>`, Mal Kabul'de basılan
aynı etiketler) okutarak otomatik toplama yapabiliyor — koli okutulunca
ilgili ürünün Sayılan Miktar'ı otomatik artıyor (debounce + çift-okutma
engeli, `depo-siparis.html`'deki `depoQrOkundu()` ile aynı desen).
Etiketsiz ürünler için elle giriş aynen kullanılabiliyor, ikisi aynı
input üzerinde birleşiyor. Yeni tablo/kolon yok. Detay:
`docs/superpowers/specs/2026-07-30-sayim-qr-okutma-design.md`.
```

- [ ] **Step 3: Commit**

```bash
cd D:\ERP-Bilgi-Haritasi
git add 02-Moduller/Stok-Depo.md
git commit -m "docs: sayimda koli QR ile otomatik toplamayi belgeledi"
cd D:\erp
```

(Not: `D:\ERP-Bilgi-Haritasi` ve `D:\erp` ayrı git repoları — iki ayrı
commit gerekir, `D:\erp` tarafında bu task için ek bir commit yok çünkü
Task 1 zaten kod değişikliğini commit'ledi.)
