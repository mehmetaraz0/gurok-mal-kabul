# Güvenlik Stoğu Hesaplama Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `stok-takip.html`'e, son 7 günlük gerçek tüketim verisinden her ürünün minimum stok seviyesini otomatik hesaplayıp güncelleyen bir "Güvenlik Stoğunu Yeniden Hesapla" butonu eklemek.

**Architecture:** Tek dosyalık (`stok-takip.html`) bir özellik. Yeni `guvenlikStoguHesapla(tamponGun)` fonksiyonu `stok_hareketleri`'nden son 7 günlük tüketim hareketlerini çeker, `urun_kodu` bazında gruplar, yeterli veri (≥3 farklı gün) olan ürünler için `ortalama_gunluk_tuketim × tamponGun` formülüyle yeni minimum hesaplar ve `stok_minimumlar`'a upsert eder. Buton + tampon-gün input'u mevcut "Stok" sekmesinin araç çubuğuna eklenir.

**Tech Stack:** Vanilla JS, doğrudan `fetch()` ile Supabase REST API (bu dosyanın zaten kullandığı `SB_URL`/`SB_HEADERS` sabitleri). Build aracı yok, test çerçevesi yok (Node/Python bu ortamda mevcut değil) — doğrulama grep + manuel kod okuma + kullanıcının tarayıcıda elle test etmesiyle yapılır.

## Global Constraints

- Hesaplama penceresi: son 7 gün (takvim günü, veri olmayan günler de dahil — toplam/7).
- Yeterli veri eşiği: en az 3 farklı günde tüketim kaydı olmalı; altındaki ürünler atlanır, mevcut `min_miktar` değiştirilmez.
- Tüketim sayılan kayıtlar: `stok_hareketleri` tablosunda `tip=eq.cikis` VE `aciklama` alanı `gunluk_tuketim` veya `recete_tuketim` içeren satırlar. Diğer çıkış tipleri (transfer, iade, manuel düzeltme) sayılmaz.
- `stok_minimumlar` global bir tablodur (tek satır per `urun_kodu`, depo/otel ayrımı yok) — hesaplama tüm otel/depoları birlikte toplar.
- Tampon gün sayısı kalıcı saklanmaz; her hesaplamada UI'daki input'tan okunur, varsayılan 7.
- Güncelleme kullanıcı onayı istemeden doğrudan `stok_minimumlar`'a yazılır (bilinçli tasarım kararı — bkz. spec "Kapsam dışı").
- Sonuç bir toast ile bildirilir: kaç ürün güncellendi, kaç ürün atlandı.

---

### Task 1: `guvenlikStoguHesapla()` fonksiyonu + UI

**Files:**
- Modify: `stok-takip.html` (fonksiyon: `minimumDuzenle`'nin hemen sonrasına, satır ~1004 civarı; UI: `#tab-stok` araç çubuğu, satır ~160 civarı)

**Interfaces:**
- Consumes: mevcut `SB_URL`, `SB_HEADERS` sabitleri (satır 408-410); `showLoading()`/`hideLoading()`; `showToast(msg,dur=2500)` (satır 1980); `loadDB()` (satır 672, tüm `db.*` state'ini yeniden yükler, `db.minimumlar` dahil); `renderStok()` (mevcut stok listesini yeniden çizer).
- Produces: global `async function guvenlikStoguHesapla(tamponGun)` — başka hiçbir task bu fonksiyonu tüketmiyor, sadece UI'dan `onclick` ile çağrılıyor.

- [ ] **Step 1: `guvenlikStoguHesapla` fonksiyonunu ekle**

`stok-takip.html`'de satır 1004'teki `minimumDuzenle` fonksiyonunun kapanışından (`}`) hemen sonra, yeni satıra şunu ekle:

```js
async function guvenlikStoguHesapla(tamponGun){
  if(!tamponGun||tamponGun<1)tamponGun=7;
  showLoading();
  const yediGunOnce=new Date(Date.now()-7*24*60*60*1000).toISOString();
  let hareketler=[];
  try{
    const r=await fetch(SB_URL+'/rest/v1/stok_hareketleri?tip=eq.cikis&tarih=gte.'+encodeURIComponent(yediGunOnce)+'&or=(aciklama.ilike.*gunluk_tuketim*,aciklama.ilike.*recete_tuketim*)&select=urun_kodu,miktar,tarih',{headers:SB_HEADERS});
    if(r.ok)hareketler=await r.json();
    else{hideLoading();showToast('❌ Tüketim verisi alınamadı');return;}
  }catch(e){hideLoading();showToast('❌ Tüketim verisi alınamadı');return;}

  const grup={};
  hareketler.forEach(h=>{
    if(!h.urun_kodu)return;
    if(!grup[h.urun_kodu])grup[h.urun_kodu]={toplam:0,gunler:new Set()};
    grup[h.urun_kodu].toplam+=parseFloat(h.miktar)||0;
    grup[h.urun_kodu].gunler.add(String(h.tarih).slice(0,10));
  });

  let guncellenen=0,atlanan=0;
  for(const urunKodu in grup){
    const g=grup[urunKodu];
    if(g.gunler.size<3){atlanan++;continue;}
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
  await loadDB();
  renderStok();
  hideLoading();
  showToast(`✅ ${guncellenen} ürün güncellendi, ${atlanan} ürün yeterli veri olmadığı için atlandı`);
}
```

- [ ] **Step 2: Buton ve tampon-gün input'unu ekle**

`stok-takip.html`'de satır 160'taki şu satırı:

```html
    <button class="btn btn-gray btn-block" style="margin-bottom:8px" onclick="stokExcelAktar()">📤 Excel'e Aktar</button>
```

şununla değiştir (mevcut satırı koru, hemen altına yeni blok ekle):

```html
    <button class="btn btn-gray btn-block" style="margin-bottom:8px" onclick="stokExcelAktar()">📤 Excel'e Aktar</button>
    <div style="display:flex;gap:8px;align-items:center;margin-bottom:8px">
      <label style="font-size:12px;color:var(--gray-400);white-space:nowrap">Tampon gün:</label>
      <input id="tamponGunInput" type="number" min="1" value="7" style="width:60px">
      <button class="btn btn-sm" style="flex:1" onclick="guvenlikStoguHesapla(parseInt(document.getElementById('tamponGunInput').value)||7)">🔄 Güvenlik Stoğunu Yeniden Hesapla</button>
    </div>
```

- [ ] **Step 3: Tarayıcıda syntax kontrolü**

Bu dosyada test çerçevesi yok. Doğrulama için:

```bash
grep -n "function guvenlikStoguHesapla" stok-takip.html
grep -n "tamponGunInput" stok-takip.html
```

Expected: ilk komut 1 satır (fonksiyon tanımı), ikinci komut 2 satır (input tanımı + onclick içindeki `getElementById` çağrısı) döndürmeli.

- [ ] **Step 4: Commit**

```bash
git add stok-takip.html
git commit -m "feat: add automatic safety stock calculation to stok-takip.html"
```

---

### Task 2: Uçtan uca doğrulama

**Files:** (yok — sadece doğrulama)

- [ ] **Step 1: Tutarlılık kontrolü**

```bash
grep -n "function guvenlikStoguHesapla\|tamponGunInput\|guvenlikStoguHesapla(" stok-takip.html
```
Expected: fonksiyon tanımı (1), input elementi (1), buton `onclick` çağrısı (1) — toplam 3 eşleşme, hepsi `stok-takip.html` içinde.

- [ ] **Step 2: Kullanıcıya manuel test adımlarını bildir**

Kullanıcının tarayıcıda doğrulaması gereken akış (Node/Python bu ortamda yok, otomatik test yazılamıyor):
1. `gunluk-tuketim.html`'de en az 3 farklı günde aynı ürün için tüketim kaydı gir (veya son birkaç gündür girilmiş gerçek kayıtları kullan).
2. `stok-takip.html` → Stok sekmesi → "🔄 Güvenlik Stoğunu Yeniden Hesapla" butonuna bas (varsayılan tampon gün: 7).
3. Toast'ta "N ürün güncellendi, M ürün atlandı" mesajının çıktığını doğrula.
4. Güncellenen bir ürünün minimum değerini stok detay modalından kontrol et — `(son 7 günün toplam tüketimi / 7) × 7` formülüyle uyuştuğunu doğrula.
5. Hiç tüketim kaydı olmayan bir ürünün minimum değerinin DEĞİŞMEDİĞİNİ doğrula.
6. Tampon gün kutusuna farklı bir değer (örn. 14) gir, tekrar hesapla, minimumların buna göre değiştiğini doğrula.

- [ ] **Step 3: Kullanıcıdan onay al, sonra push**

```bash
git fetch
git log --oneline main..origin/main
```
Expected: paralel oturumdan gelen değişiklik var mı kontrol et, varsa kullanıcıya bildir. Yoksa kullanıcı onayıyla `git push`.
