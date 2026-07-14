# ABC Analizi / Stok Sınıflandırması — Tasarım

## Problem / Hedef

Yüksek değerli/sık hareket eden ürünlerle düşük değerli ürünler aynı
titizlikte (ya da aynı gevşeklikte) takip ediliyor — hangi ürünlerin sıkı
takip gerektirdiği sisteme yansımıyor. Bu, depo modülü kıyaslama
raporunda tespit edilen Önemli #04 eksiği.

## Kapsam

- `stok-takip.html`'in Stok sekmesine, her ürünü **A/B/C** sınıfına
  ayıran anlık (client-side) bir hesaplama eklenir.
- Sınıf, ürünün **mevcut stok değeri** ve **son 7 günlük tüketim
  değeri**nin ağırlıklı toplamından (skor) klasik Pareto (80/15/5)
  yöntemiyle belirlenir.
- Her ürün satırında mevcut 🔴/🟡/✅ durum rozetinin yanına bir A/B/C
  rozeti eklenir; ayrıca mevcut kategori sekmeleri (`#kat-tabs`) ile aynı
  desende yeni bir "Tümü/A/B/C" filtre sekmesi (`#abc-tabs`) eklenir.

## Kapsam dışı

- Kalıcı saklama — yeni bir tablo/kolon eklenmez, sınıflandırma sayfa
  her açıldığında/yenilendiğinde mevcut veriden anlık hesaplanır. Başka
  ekranlar (örn. satın almada A ürünlere öncelik) şu an bu veriyi
  kullanmıyor — YAGNI.
- Ürün bazlı ağırlık/eşik ayarı — tüm ürünler aynı formülle (skor =
  stok_değeri + tüketim_değeri×4) ve aynı Pareto eşikleriyle
  sınıflandırılır, kullanıcı ayarlayamaz.
- Depo/otel bazlı ayrı sınıflandırma — `stok_minimumlar` ve önceki
  Güvenlik Stoğu özelliğiyle tutarlı olarak, sınıflandırma tüm
  depo/otelleri tek `urun_kodu` altında toplar (global model).
- Gerçek yıllık kullanım değeri — tüketim geçmişi hâlâ ~1 haftalık
  (bkz. `2026-07-14-guvenlik-stogu-design.md`'deki aynı veri kısıtı);
  bu yüzden skor, tarihsel derinlik gerektirmeyen "mevcut stok değeri"ni
  ana bileşen olarak kullanır, tüketimi ek bir sinyal olarak ağırlıklı
  ekler.

## Mimari

**Fiyat verisi:** `stok-takip.html`'e, `gunluk-tuketim.html`'deki
`loadFiyatMap()` fonksiyonunun aynısı (aynı iki view, aynı öncelik
sırası — FIFO fiyat varsa o, yoksa son fatura fiyatı) kopyalanır:

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
```

`loadDB()`'nin çağrıldığı her yerin hemen ardından `loadFiyatMap()` da
çağrılır (init akışında).

**Tüketim verisi:** Yeni bir fetch gerekmez — `db.hareketler` (`loadDB()`
ile zaten tüm `stok_hareketleri` geçmişini yüklüyor, bkz.
`stok-takip.html:682`) client-side filtrelenir: son 7 gün, `tip==='cikis'`,
`aciklama` `gunluk_tuketim` veya `recete_tuketim` içeriyor (Güvenlik
Stoğu özelliğiyle aynı tüketim tanımı).

**Skor hesaplama** (`hesaplaAbcSiniflari()`, `db.stok` + `db.hareketler` +
`db.fiyatMap` hazır olduktan sonra, her `loadDB()`+`loadFiyatMap()`
tamamlandığında bir kez çağrılır, sonucu `db.abcSiniflari={urun_kodu:'A'|'B'|'C'}`
içine yazar):

```js
function hesaplaAbcSiniflari(){
  db.abcSiniflari={};
  // 1. Ürün başına toplam stok miktarı (tüm depo/oteller)
  const stokMiktar={};
  Object.values(db.stok).forEach(depoStok=>{
    Object.values(depoStok).forEach(s=>{
      stokMiktar[s.lnKod]=(stokMiktar[s.lnKod]||0)+(parseFloat(s.miktar)||0);
    });
  });
  // 2. Ürün başına son 7 günlük tüketim miktarı
  const yediGunOnce=Date.now()-7*24*60*60*1000;
  const tuketimMiktar={};
  Object.values(db.hareketler).forEach(h=>{
    if(h.tip!=='cikis'||h.tarih<yediGunOnce)return;
    if(!/gunluk_tuketim|recete_tuketim/.test(h.aciklama||''))return;
    tuketimMiktar[h.lnKod]=(tuketimMiktar[h.lnKod]||0)+h.miktar;
  });
  // 3. Skor
  const tumUrunKodlari=new Set([...Object.keys(stokMiktar),...Object.keys(tuketimMiktar)]);
  const skorlar=[...tumUrunKodlari].map(kod=>{
    const fiyat=db.fiyatMap[kod]?.fiyat||0;
    const stokDegeri=(stokMiktar[kod]||0)*fiyat;
    const tuketimDegeri=(tuketimMiktar[kod]||0)*fiyat;
    return{kod,skor:stokDegeri+(tuketimDegeri*4)};
  });
  // 4. Pareto 80/15/5
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

## UI

**Rozet:** Ürün listesindeki her satırda mevcut durum rozetinin yanına:

```js
const abcSinif=db.abcSiniflari[s.lnKod]||'C';
const abcRenk={A:'#dc2626',B:'#d97706',C:'#6b7280'};
`<span style="background:${abcRenk[abcSinif]};color:#fff;font-size:10px;font-weight:700;padding:1px 5px;border-radius:4px;margin-left:4px">${abcSinif}</span>`
```

**Filtre sekmesi:** `#kat-tabs` ile birebir aynı desende, `renderStok()`
içinde dinamik üretilen yeni bir `#abc-tabs` div'i (mevcut `#kat-tabs`
div'inin hemen altına, `stok-takip.html:159` civarı):

```html
<div class="filter-tabs" id="abc-tabs"></div>
```

```js
document.getElementById('abc-tabs').innerHTML=
  `<button class="filter-tab ${abcFilter==='tumu'?'active':''}" onclick="filterAbc('tumu',this)">Tümü</button>`+
  ['A','B','C'].map(s=>`<button class="filter-tab ${abcFilter===s?'active':''}" onclick="filterAbc('${s}',this)">${s} Sınıfı</button>`).join('');
```

`filterAbc(sinif,el)` = `abcFilter=sinif;renderStok();` (`filterKat`ile
birebir aynı desen). `renderStok()`'un `filtered=items.filter(...)`
bloğuna mevcut `katFilter` kontrolünün yanına eklenir:

```js
if(abcFilter!=='tumu'&&(db.abcSiniflari[s.lnKod]||'C')!==abcFilter)return false;
```

Global state: `let abcFilter='tumu';` (mevcut `let katFilter='tumu';`
satırının yanına).

## Akış

1. Sayfa açılır/yenilenir → `loadDB()` + `loadFiyatMap()` tamamlanır →
   `hesaplaAbcSiniflari()` çağrılır → `db.abcSiniflari` doldurulur.
2. `renderStok()` her çağrıldığında her satıra `db.abcSiniflari[lnKod]`
   rozeti eklenir, `#abc-tabs` güncel `abcFilter` durumuna göre yeniden
   çizilir.
3. Kullanıcı "A Sınıfı" sekmesine tıklarsa sadece A sınıfı ürünler
   listelenir (mevcut kategori/durum filtreleriyle birlikte AND
   mantığıyla çalışır — `#kat-tabs`'ın zaten çalıştığı gibi).

## Test/doğrulama planı

Statik: `hesaplaAbcSiniflari()`'nin skor formülünün (stok_değeri +
tüketim_değeri×4), Pareto eşiklerinin (80/15/5) ve toplam skor 0 olma
durumunun (hepsi C) doğru kurulduğunu kod okuyarak doğrulamak. Gerçek
uçtan uca test (birkaç ürün için farklı stok/tüketim/fiyat kombinasyonları
oluştur → A/B/C dağılımının beklenen sırayla eşleştiğini stok-takip.html'de
gör, filtre sekmesinin doğru filtrelediğini gör) kullanıcı tarafından
yapılacak.
