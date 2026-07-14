# Güvenlik Stoğu Hesaplama — Tasarım

## Problem / Hedef

Minimum stok değerleri (`stok_minimumlar.min_miktar`) elle girilip sabit
kalıyor, talep dalgalanmasına (sezon, özel etkinlik) göre otomatik
ayarlanmıyor. Bu, depo modülü kıyaslama raporunda tespit edilen Önemli #07
eksiği.

## Kapsam

- `stok-takip.html`'e "🔄 Güvenlik Stoğunu Yeniden Hesapla" butonu +
  yanında tampon-gün sayı kutusu (varsayılan 7) eklenir.
- Tıklanınca her `urun_kodu` için son 7 günlük gerçek tüketim verisinden
  (`stok_hareketleri`) ortalama günlük tüketim hesaplanır, tampon gün
  sayısıyla çarpılarak yeni `min_miktar` bulunur ve doğrudan (kullanıcı
  onayı istemeden) `stok_minimumlar` tablosuna yazılır.
- Yeterli veri (en az 3 farklı günde tüketim kaydı) olmayan ürünler
  atlanır — mevcut minimum değerleri dokunulmadan kalır.

## Kapsam dışı

- Gerçek istatistiksel güvenlik stoğu formülü (Z-skoru × talep standart
  sapması × √tedarik süresi) — sistemde tedarik süresi (lead time) alanı
  hiç yok, tüketim geçmişi de sadece ~1 haftalık (gunluk-tuketim.html
  2026-07-08'de devreye girdi). Gerçek istatistik için hem yeni bir
  tedarik-süresi alanı hem de aylarca veri gerekir — ayrı bir iş.
- Ürün bazlı tampon gün sayısı — global tek sayı yeterli bulundu, ürün
  bazlı override eklenmedi (YAGNI).
- Kullanıcı onaylı öneri akışı (Sayım/Reorder özelliklerindeki gibi) —
  bilinçli olarak seçilmedi, hesaplama doğrudan `min_miktar`'ı günceller.
- Kalıcı ayar tablosu — tampon gün sayısı sadece buton yanındaki input'ta
  tutulur, veritabanında saklanmaz.

## Mimari

`stok-takip.html`'e yeni bir `guvenlikStoguHesapla(tamponGun)` fonksiyonu
eklenir (minimum stok yönetimi zaten bu dosyada, `minimumDuzenle`
fonksiyonunun yanında).

**Veri kaynağı:** `stok_hareketleri` tablosu — `tip=eq.cikis`,
`tarih=gte.<7 gün önce>`, ve `aciklama` alanı `gunluk_tuketim` veya
`recete_tuketim` içeren satırlar (Supabase `or=(aciklama.ilike.*gunluk_tuketim*,aciklama.ilike.*recete_tuketim*)`).
Diğer çıkış tipleri (transfer, iade, manuel düzeltme) tüketim sayılmaz —
gerçek talep sinyali değil.

**Hesaplama** (client-side, JS ile, tüm otel/depolar toplanarak — mevcut
`stok_minimumlar` şeması zaten global, `urun_kodu` başına tek satır):

```js
async function guvenlikStoguHesapla(tamponGun){
  const yediGunOnce=new Date(Date.now()-7*24*60*60*1000).toISOString();
  let hareketler=[];
  try{
    const r=await fetch(SB_URL+'/rest/v1/stok_hareketleri?tip=eq.cikis&tarih=gte.'+encodeURIComponent(yediGunOnce)+'&or=(aciklama.ilike.*gunluk_tuketim*,aciklama.ilike.*recete_tuketim*)&select=urun_kodu,miktar,tarih',{headers:SB_HEADERS});
    if(r.ok)hareketler=await r.json();
  }catch(e){showToast('❌ Tüketim verisi alınamadı');return;}

  // urun_kodu -> {toplam, gunler:Set}
  const grup={};
  hareketler.forEach(h=>{
    if(!h.urun_kodu)return;
    if(!grup[h.urun_kodu])grup[h.urun_kodu]={toplam:0,gunler:new Set()};
    grup[h.urun_kodu].toplam+=parseFloat(h.miktar)||0;
    grup[h.urun_kodu].gunler.add(h.tarih.slice(0,10));
  });

  let guncellenen=0,atlanan=0;
  for(const urunKodu in grup){
    const g=grup[urunKodu];
    if(g.gunler.size<3){atlanan++;continue;} // yetersiz veri
    const ortalamaGunluk=g.toplam/7;
    const yeniMin=Math.round(ortalamaGunluk*tamponGun*100)/100;
    try{
      const r=await fetch(SB_URL+'/rest/v1/stok_minimumlar?on_conflict=urun_kodu',{
        method:'POST',
        headers:{...SB_HEADERS,'Prefer':'resolution=merge-duplicates'},
        body:JSON.stringify({urun_kodu:urunKodu,min_miktar:yeniMin})
      });
      if(r.ok)guncellenen++;else atlanan++;
    }catch(e){atlanan++;}
  }
  showToast(`✅ ${guncellenen} ürün güncellendi, ${atlanan} ürün yeterli veri olmadığı için atlandı`);
  await loadDB(); // db.minimumlar'ı tazele
}
```

**UI:** Minimum stok yönetiminin bulunduğu alana (stok detay modalı veya
üst araç çubuğu — mevcut `minimumDuzenle` çağrısının yakınına) küçük bir
input (`#tamponGunInput`, varsayılan değer 7) + buton eklenir:

```html
<div style="display:flex;gap:8px;align-items:center;margin:8px 0">
  <label style="font-size:12px;color:var(--gray-400)">Tampon gün:</label>
  <input id="tamponGunInput" type="number" min="1" value="7" style="width:60px">
  <button class="btn btn-sm" onclick="guvenlikStoguHesapla(parseInt(document.getElementById('tamponGunInput').value)||7)">🔄 Güvenlik Stoğunu Yeniden Hesapla</button>
</div>
```

## Akış

1. Kullanıcı tampon gün sayısını (varsayılan 7) girer veya varsayılanı
   kabul eder, butona basar.
2. Son 7 günlük tüketim hareketleri tek sorguyla çekilir, `urun_kodu`
   bazında gruplanır.
3. En az 3 farklı günde kaydı olan her ürün için yeni minimum hesaplanır
   ve `stok_minimumlar`'a upsert edilir — kullanıcı onayı istenmez.
4. Yetersiz veri olan ürünler sessizce atlanır, mevcut minimumları
   korunur.
5. Sonuç toast'ı: kaç ürün güncellendi, kaç ürün atlandı.
6. `db.minimumlar` yeniden yüklenir ki ekrandaki stok durumu göstergeleri
   (`getStokDurum()`) hemen güncel minimumu yansıtsın.

## Test/doğrulama planı

Statik: `guvenlikStoguHesapla`'nın sorgu filtrelerinin (7 günlük pencere,
sadece `cikis`+tüketim etiketli satırlar, 3-gün eşiği) doğru kurulduğunu,
`stok_minimumlar` upsert'inin doğru `on_conflict` ile yapıldığını kod
okuyarak doğrulamak. Gerçek uçtan uca test (birkaç gün tüketim kaydı olan
bir ürün için butona bas → minimum değerinin beklenen formülle
güncellendiğini stok-takip.html'de gör, veri yetersiz bir ürünün
değişmediğini gör) kullanıcı tarafından yapılacak.
