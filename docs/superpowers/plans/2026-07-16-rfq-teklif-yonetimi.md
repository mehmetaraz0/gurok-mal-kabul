# Satın Alma — RFQ / Teklif Yönetimi Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Onaylanmış bir satın alma talebinden tedarikçilere teklif isteme,
elle veya Excel toplu yükleme ile yanıt toplama, ürün×tedarikçi
karşılaştırma tablosu üzerinden en iyi teklifi seçme ve seçileni siparişe
dönüştürme akışı eklemek.

**Architecture:** Dört yeni Supabase tablosu (`teklif_talepleri`,
`teklif_talep_kalemleri`, `tedarikci_teklifler`, `tedarikci_teklif_kalemleri`).
`satin-alma.html`'e yeni bir "Teklifler" sekmesi + `openTalepDetay`'e "Teklif
İste" butonu eklenir. Her yeni fonksiyon, aynı dosyada zaten var olan bir
desenin doğrudan uyarlamasıdır (bkz. Global Constraints) — yeni bir mimari
kalıp icat edilmez.

**Tech Stack:** Vanilla HTML/JS, Supabase REST (fetch), XLSX (xlsx-js-style,
CDN'den lazım anında yükleniyor — mevcut desen) — build aracı/test
çerçevesi yok.

---

## Global Constraints

- Tedarikçi kimliği her yerde `firma_ad` (serbest metin) — yeni bir "firma
  id" mimarisi icat edilmez, `siparisler`/`mal_kabuller`/`faturalar` ile
  tutarlı (spec).
- RFQ sadece onaylanmış (`durum='onaylandi'`) bir talepten başlar — bağımsız
  RFQ v1 kapsamında yok (spec).
- Stok/miktar yazılmaz — bu tamamen fiyat toplama + karşılaştırma akışı,
  siparişe dönüşene kadar hiçbir stok/mal kabul etkisi yok (spec).
- Excel import, her satır uygulanmadan önce RFQ'nun güncel `durum`'unu canlı
  GET ile tazeler — `kapandi` ise atlanır (spec, `talepExcelUygula`
  desenindeki "canlı durum tazele" ile aynı).
- Siparişe dönüştürme, `spGrupla()`'daki firma bazlı gruplama +
  `siparisler`/`siparis_kalemleri` insert desenini AYNEN kullanır — yeni bir
  sipariş oluşturma yolu icat edilmez (spec).

---

### Task 1: Supabase şema değişikliği (kullanıcı tarafından çalıştırılır)

**Files:**
- Modify: Supabase SQL Editor (kod tabanında dosya yok)

**Interfaces:**
- Produces: `teklif_talepleri`, `teklif_talep_kalemleri`,
  `tedarikci_teklifler`, `tedarikci_teklif_kalemleri` tabloları — Task 2-5'in
  okuma/yazma işlemleri bunlara.

- [ ] **Step 1: Kullanıcıya SQL'i ver, Supabase SQL Editor'de çalıştırmasını iste**

```sql
CREATE TABLE IF NOT EXISTS teklif_talepleri (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  talep_id uuid REFERENCES satin_alma_talepleri(id),
  otel_id text,
  olusturan_ad text,
  olusturma_tarihi timestamptz DEFAULT now(),
  durum text DEFAULT 'acik',
  not_alani text
);

CREATE TABLE IF NOT EXISTS teklif_talep_kalemleri (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  teklif_talep_id uuid REFERENCES teklif_talepleri(id),
  urun_kodu text, urun_adi text, miktar numeric, birim text
);

CREATE TABLE IF NOT EXISTS tedarikci_teklifler (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  teklif_talep_id uuid REFERENCES teklif_talepleri(id),
  firma_ad text NOT NULL, firma_kodu text,
  durum text DEFAULT 'bekleniyor',
  teklif_tarihi timestamptz, not_alani text
);

CREATE TABLE IF NOT EXISTS tedarikci_teklif_kalemleri (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tedarikci_teklif_id uuid REFERENCES tedarikci_teklifler(id),
  teklif_talep_kalem_id uuid REFERENCES teklif_talep_kalemleri(id),
  birim_fiyat numeric, not_alani text
);
```

- [ ] **Step 2: Kullanıcı çalıştırdıktan sonra doğrula**

```bash
curl -s --ssl-no-revoke "https://xwytofysmgqtqjzkplfi.supabase.co/rest/v1/teklif_talepleri?select=id&limit=1" -H "apikey: <SB_KEY>" -H "Authorization: Bearer <SB_KEY>"
curl -s --ssl-no-revoke "https://xwytofysmgqtqjzkplfi.supabase.co/rest/v1/tedarikci_teklifler?select=id&limit=1" -H "apikey: <SB_KEY>" -H "Authorization: Bearer <SB_KEY>"
```
Expected: İkisi de `200` ve `[]` döner.

---

### Task 2: RFQ oluşturma + liste/detay iskeleti + tedarikçi ekleme

**Files:**
- Modify: `satin-alma.html` — `openTalepDetay` (yetkili/onaylandı butonları
  alanı), yeni sekme (`gTab` dispatcher'a `teklifler` case'i, nav butonu,
  `#tab-teklifler` div), yeni fonksiyonlar.

**Interfaces:**
- Produces: `teklifIste(talepId)`, `renderTeklifler()`,
  `openTeklifDetay(id)`, `teklifTedarikciEkle(teklifTalepId, firmaAd)`,
  `teklifTedarikciOnerileriGetir(kalemler)` — Task 3/4/5 bunları kullanır.

- [ ] **Step 1: Yeni sekme iskeleti**

Nav'a yeni buton (mevcut sekme butonlarının yanına, `satin-alma.html`'deki
`gTab('firmalar',this)` benzeri): `<button ... onclick="gTab('teklifler',this)">📨 Teklifler</button>`.
`gTab()` dispatcher'ına `if(tab==='teklifler')renderTeklifler();` eklenir
(mevcut `if(tab==='skorKart')renderSkorKart();` satırının yanına). Yeni
`#tab-teklifler` div: liste container + `ftabs` alt-filtre (Tümü/Açık/Kapandı,
`renderTalepler`'daki `talepFilter` desenine birebir aynı).

- [ ] **Step 2: `teklifIste(talepId)` — RFQ oluşturma**

`openTalepDetay`'deki `t.durum==='onaylandi'` bloğuna "📨 Teklif İste" butonu
eklenir (mevcut "📦 Siparişe Dönüştür"ün yanına). `talepSipariseDonustur`
(satır ~1081) ile aynı POST deseni:

```js
async function teklifIste(talepId){
  const t=DB.talepler[talepId];if(!t)return;
  sLD();
  try{
    const r=await fetch(SB_URL+'/rest/v1/teklif_talepleri',{method:'POST',headers:{...SB_HEADERS,'Prefer':'return=representation'},
      body:JSON.stringify({talep_id:talepId,otel_id:t.otelId||'810',olusturan_ad:CU.ad})});
    if(!r.ok){hLD();toast('❌ Teklif talebi oluşturulamadı');return;}
    const d=await r.json();const teklifTalepId=d[0].id;
    const kalemSatirlar=(t.satirlar||[]).map(u=>({teklif_talep_id:teklifTalepId,urun_kodu:u.kod||null,urun_adi:u.ad,miktar:u.miktar,birim:u.birim}));
    await fetch(SB_URL+'/rest/v1/teklif_talep_kalemleri',{method:'POST',headers:SB_HEADERS,body:JSON.stringify(kalemSatirlar)});
    hLD();kModal('mTalepDetay');toast('📨 Teklif talebi oluşturuldu');
    await loadTeklifler();gTab('teklifler',document.querySelector('[onclick*="teklifler"]'));
    openTeklifDetay(teklifTalepId);
  }catch(e){console.warn(e);hLD();toast('❌ İşlem başarısız');}
}
```

- [ ] **Step 3: `loadTeklifler()`/`renderTeklifler()`/`openTeklifDetay()`**

`loadDB()`'deki `satin_alma_talepleri?select=*,satin_alma_talep_kalemleri(*)`
çağrısıyla aynı embed deseni: `teklif_talepleri?select=*,teklif_talep_kalemleri(*),tedarikci_teklifler(*,tedarikci_teklif_kalemleri(*))`
— tek istekte tüm RFQ ağacı gelir, `DB.teklifler={}` içine map'lenir.
`renderTeklifler()`/`openTeklifDetay()`, `renderTalepler()`/
`openTalepDetay()` ile birebir aynı liste-kart + detay-modal iskeleti
(durum chip'leri: `acik`→⏳, `kapandi`→✅).

- [ ] **Step 4: `teklifTedarikciEkle` + otomatik öneri**

```js
function teklifTedarikciOnerileriGetir(kalemler){
  const kodlar=[...new Set((kalemler||[]).map(k=>k.urun_kodu).filter(Boolean))];
  const eslesenler=new Map(); // firmaAd -> firma
  kodlar.forEach(kod=>{
    (DB.firmalar||[]).forEach(f=>{
      if(f.urunler&&f.urunler.includes(kod))eslesenler.set(f.ad,f);
    });
  });
  return [...eslesenler.values()];
}
async function teklifTedarikciEkle(teklifTalepId,firmaAd,firmaKodu){
  if(!firmaAd)return;
  try{
    await fetch(SB_URL+'/rest/v1/tedarikci_teklifler',{method:'POST',headers:SB_HEADERS,
      body:JSON.stringify({teklif_talep_id:teklifTalepId,firma_ad:firmaAd,firma_kodu:firmaKodu||null})});
    await loadTeklifler();openTeklifDetay(teklifTalepId);
  }catch(e){console.warn(e);toast('❌ Tedarikçi eklenemedi');}
}
```

`autoFirma` (satır ~1990) sadece ilk eşleşen firmayı döner — burada TÜMÜ
toplanıp tekilleştiriliyor, bu yüzden ayrı bir fonksiyon (`autoFirma`'yı
değiştirmiyoruz, o Sipariş Oluştur'da hâlâ tek-eşleşme davranışıyla
kullanılıyor).

- [ ] **Step 5: Doğrula**

```bash
grep -n "function teklifIste\|function renderTeklifler\|function openTeklifDetay\|function teklifTedarikciEkle\|id=\"tab-teklifler\"" satin-alma.html
```
Expected: hepsi tanımlı, yeni sekme div'i mevcut.

- [ ] **Step 6: Commit**

```bash
git add satin-alma.html
git -c user.name="mehmetaraz0" -c user.email="mehmetaraz868@gmail.com" commit -m "feat: add RFQ creation, list/detail skeleton and supplier suggestions"
```

---

### Task 3: Elle fiyat girişi modalı

**Files:**
- Modify: `satin-alma.html` — yeni `tedarikciTeklifGirModalAc`/
  `tedarikciTeklifKaydet` fonksiyonları + modal div.

**Interfaces:**
- Consumes: `DB.teklifler[teklifTalepId].tedarikci_teklifler` (Task 2'nin
  `loadTeklifler()`'ı).
- Produces: `tedarikci_teklif_kalemleri` satırları, `tedarikci_teklifler.durum='geldi'`.

- [ ] **Step 1: `tedarikciTeklifGirModalAc(tedarikciTeklifId)`**

`fkDetayAc` (satır ~1592) deseniyle: RFQ'nun `teklif_talep_kalemleri`'ni
satır satır, her biri için bir `<input type="number" id="tf-fiyat-${i}">`
göstererek listeler (mevcut kayıtlı `birim_fiyat` varsa önceden doldurulmuş).

- [ ] **Step 2: `tedarikciTeklifKaydet(tedarikciTeklifId)`**

Her kalem için `tedarikci_teklif_kalemleri` upsert (kalem daha önce
girilmişse PATCH, değilse POST — `teklif_talep_kalem_id`+`tedarikci_teklif_id`
ile eşleştirilir), sonunda `tedarikci_teklifler` PATCH
(`durum:'geldi',teklif_tarihi:new Date().toISOString()`). `fkFiyatHesapla`
(satır ~1680) deseniyle canlı toplam gösterimi.

- [ ] **Step 3: Doğrula**

```bash
grep -n "function tedarikciTeklifGirModalAc\|function tedarikciTeklifKaydet" satin-alma.html
```

- [ ] **Step 4: Commit**

```bash
git add satin-alma.html
git -c user.name="mehmetaraz0" -c user.email="mehmetaraz868@gmail.com" commit -m "feat: add manual price entry modal for supplier quotes"
```

---

### Task 4: Excel export/import

**Files:**
- Modify: `satin-alma.html` — yeni `teklifleriExcelAktar`/
  `teklifExcelYukle`/`teklifExcelUygula` fonksiyonları.

**Interfaces:**
- Consumes: `talepleriExcelAktar`/`talepExcelUygula` (satır ~912, ~959) —
  birebir aynı XLSX yükleme/okuma iskeleti.
- Produces: `tedarikci_teklifler` (yoksa oluşturur) + `tedarikci_teklif_kalemleri`.

- [ ] **Step 1: `teklifleriExcelAktar(teklifTalepId)`**

`talepleriExcelAktar` (satır 912) deseniyle, kolonlar: `Teklif Talep ID,
Ürün Kodu, Ürün Adı, Miktar, Birim, Firma, Birim Fiyat`. Her satır = (ürün ×
o RFQ'ya eklenmiş her tedarikçi) kombinasyonu — yani N ürün × M tedarikçi =
N×M satır, `Birim Fiyat` zaten girilmişse dolu, değilse boş.

- [ ] **Step 2: `teklifExcelYukle(event)` / `teklifExcelUygula(rows)`**

`talepExcelUygula` (satır 959) deseniyle: satırları `Teklif Talep ID`'ye
göre grupla → **canlı durum tazele** (RFQ hâlâ `acik` mı, `talepExcelUygula`
satır ~962-968'deki desenle) → `kapandi` ise o RFQ'nun tüm satırlarını atla
→ satırları `Firma`'ya göre grupla → her firma için `tedarikci_teklifler`
satırı yoksa oluştur (varsa mevcut id'yi kullan) → dolu `Birim Fiyat`
hücreleri için `tedarikci_teklif_kalemleri` upsert + `tedarikci_teklifler.
durum='geldi'`. Boş `Birim Fiyat` hücreleri atlanır (o ürün için henüz
fiyat gelmemiş demektir).

- [ ] **Step 3: Doğrula**

```bash
grep -n "function teklifleriExcelAktar\|function teklifExcelYukle\|function teklifExcelUygula" satin-alma.html
```

- [ ] **Step 4: Kod okuyarak izleme**

`teklifExcelUygula`'nın PATCH/POST'tan önce RFQ'nun güncel `durum`'unu canlı
GET ile tazelediğini ve `kapandi` durumdaki RFQ'lar için hiçbir yazma
yapmadığını doğrula — `talepExcelUygula`'daki aynı korumanın burada da
var olduğundan emin ol.

- [ ] **Step 5: Commit**

```bash
git add satin-alma.html
git -c user.name="mehmetaraz0" -c user.email="mehmetaraz868@gmail.com" commit -m "feat: add Excel export/import for bulk supplier quote entry"
```

---

### Task 5: Karşılaştırma tablosu + siparişe dönüştürme

**Files:**
- Modify: `satin-alma.html` — yeni `renderTeklifKarsilastirma`/
  `teklifSecilenleriSiparisDonustur` fonksiyonları.

**Interfaces:**
- Consumes: `spGrupla()` (satır ~1310) — firma bazlı gruplama +
  `siparisler`/`siparis_kalemleri` insert deseni.
- Produces: yeni `siparisler`/`siparis_kalemleri` satırları,
  `teklif_talepleri.durum='kapandi'`.

- [ ] **Step 1: `renderTeklifKarsilastirma(teklifTalepId)`**

Tablo: satırlar = `teklif_talep_kalemleri` (ürünler), sütunlar =
`tedarikci_teklifler` (tedarikçiler). Her hücre = o tedarikçinin o ürün
için `tedarikci_teklif_kalemleri.birim_fiyat`'ı (yoksa "—"). Her satırda en
düşük dolu fiyat yeşil arka planla vurgulanır ve varsayılan seçili radio
olur (`<input type="radio" name="secim-${urunKodu}" value="${tedarikciTeklifId}">`).
Kullanıcı başka bir hücreyi seçebilir (sadece dolu hücreler seçilebilir).

- [ ] **Step 2: `teklifSecilenleriSiparisDonustur(teklifTalepId)`**

Seçili radio'ları topla → her (ürün, tedarikçi, fiyat) üçlüsünü
`tedarikci_teklifler.firma_ad`'a göre grupla → `spGrupla()`'daki (satır
1331-1391) `siparisler`+`siparis_kalemleri` insert desenini tekrar kullan:
`tahmini_fiyat` = seçilen `birim_fiyat`. Son olarak
`teklif_talepleri?id=eq.${teklifTalepId}` PATCH `durum:'kapandi'`.

- [ ] **Step 3: Doğrula**

```bash
grep -n "function renderTeklifKarsilastirma\|function teklifSecilenleriSiparisDonustur" satin-alma.html
```

- [ ] **Step 4: Commit**

```bash
git add satin-alma.html
git -c user.name="mehmetaraz0" -c user.email="mehmetaraz868@gmail.com" commit -m "feat: add quote comparison table and convert-to-order flow"
```

---

### Task 6: Uçtan uca doğrulama

**Files:** (yok — sadece doğrulama)

- [ ] **Step 1: Tüm yeni tanımların tutarlılığını kontrol et**

```bash
grep -n "teklif_talepleri\|teklif_talep_kalemleri\|tedarikci_teklifler\|tedarikci_teklif_kalemleri" satin-alma.html
```
Expected: dört tablo adı da tutarlı yazımla, her ilgili fonksiyonda geçmeli.

- [ ] **Step 2: Kullanıcıya manuel test adımlarını bildir**

1. Task 1'deki SQL'i Supabase SQL Editor'de çalıştır.
2. Onaylanmış bir talep bul (yoksa onay akışından bir tane onaylat) → detayında
   "📨 Teklif İste"e bas → Teklifler sekmesine yönlendiğini doğrula.
3. RFQ detayında 2-3 tedarikçi ekle (öneri listesinden veya arama ile).
4. Birine elle fiyat gir, diğer ikisi için "Excel'e Aktar" → dosyayı doldur
   → "Excel'den Yükle" ile geri yükle → fiyatların doğru işlendiğini
   doğrula.
5. Karşılaştırma tablosunda en düşük fiyatın vurgulandığını, varsayılan
   seçili olduğunu doğrula; bir üründe bilerek başka tedarikçiyi seç.
6. "Seçilenleri Siparişe Dönüştür"e bas → Sipariş Takip'te doğru firma(lar)a
   bölünmüş siparişlerin, doğru fiyatlarla (`tahmini_fiyat`) oluştuğunu
   doğrula. RFQ'nun `kapandi` olduğunu doğrula.
7. Kapanmış bir RFQ için Excel yüklemeyi tekrar dene → satırların
   "zaten kapanmış" diye atlandığını doğrula (bayat veri koruması).

- [ ] **Step 3: Kullanıcıdan onay al, sonra push**

```bash
git fetch
git log --oneline main..origin/main
```
Expected: paralel oturumdan gelen değişiklik var mı kontrol et, varsa
kullanıcıya bildir. Yoksa kullanıcı onayıyla `git push`.
