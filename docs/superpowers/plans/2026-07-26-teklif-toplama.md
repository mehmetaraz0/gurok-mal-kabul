# Teklif Toplama (RFQ) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Onaylı İç Talep kalemleri için birden fazla firmadan fiyat girip karşılaştıran, en ucuzu otomatik seçen ve seçimi mevcut Sipariş Oluştur akışına (SP_SATIRLAR köprüsü) aktaran yeni "Teklif Toplama" sayfası.

**Architecture:** Yeni bağımsız sayfa `satin-alma-teklif-toplama.html` (satin-alma.html kart-hub'ına kart olarak eklenir). Veri 3 yeni Supabase tablosunda (`teklif_talepleri`, `teklif_kalemleri`, `teklif_fiyatlari`). "Sipariş Hazırla" yeni sipariş yolu icat etmez — seçilen (firma, fiyat) satırlarını `sessionStorage['sp_devir_satirlar']`'a yazıp `satin-alma-siparisolustur.html`'e yönlendirir (mevcut "Bridge A" alıcısı zaten var). Eski `satin-alma-teklifler.html` (4 tablolu, doğrudan sipariş yazan RFQ) emekliye ayrılır.

**Tech Stack:** Statik HTML/JS (build/test aracı YOK), Supabase REST (anon key + JWT header `SB_HEADERS`), GitHub Pages deploy (main branch). Firma listesi statik `gurok_veritabani.js` → `FIRMA_DB`.

## Global Constraints

- Tablo oluşturma/silme anon key'le YAPILAMAZ → tüm DDL ayrı `.sql` dosyası olarak teslim edilir, kullanıcı Supabase SQL Editor'e yapıştırır (Task 1).
- Sipariş oluşturmaya YENİ yol eklenmez; mevcut akışa üst kademe eklenir — çıkış noktası `sessionStorage['sp_devir_satirlar']` + `location.href='satin-alma-siparisolustur.html'`.
- SP satır formatı birebir: `{ad, kod, miktar, birim, firmaId, firmaAd, tahminiFiyat}` (kaynak: satin-alma-siparisolustur.html:318 `addSPSatir` varsayılanı; alıcı satin-alma-siparisolustur.html:443-448).
- Yetki: `YETKI_HARITASI['siparis_olustur']` ∈ {`kayit`,`tam`} — yazma işlemleri bununla gate'lenir (kaynak: satin-alma-teklifler.html, satin-alma-talepler.html:807). `YETKI_HARITASI = await kullaniciYetkileriGetir()`.
- Sayfa iskeleti/başlık/stil ve liste+detay-modal deseni mevcut `satin-alma-teklifler.html` ve `satin-alma-talepler.html` ile aynı olmalı (header, `SB_URL`/`SB_HEADERS`, `requireLogin`/`requireRole`, `nav-drawer.js`, `escapeHtml`, `toast`, `sLD/hLD` yükleniyor göstergesi).
- Tarih yazımında `bugunTarih()` kullan (UTC kayması yasak — proje kuralı).
- Min. teklif sayısı zorunluluğu YOK (0 teklifle sipariş hazırlanabilir) — spec kararı.

**Kaynak tablolar (canlı, doğrulanmış):**
- `satin_alma_talepleri`: id(uuid), olusturma_tarihi, departman, talep_eden, aciliyet, not_alani, otel_id, durum, asama, tutar, onaylayan_ad, onay_tarihi. Onaylı = `durum='onaylandi'`.
- `satin_alma_talep_kalemleri`: id(uuid), talep_id(uuid), urun_adi, urun_kodu, miktar(numeric), birim(text). Nested select: `satin_alma_talepleri?select=*,satin_alma_talep_kalemleri(*)`.
- `FIRMA_DB` satır şekli: `{id:int, ad:string, kod:string, urunler:[urun_kodu...]}`.

---

## Spec'ten sapmalar (kullanıcıya bildirilecek — onaylı)

1. **"satin-alma.html'e sekme" → ayrı sayfa + hub kartı.** satin-alma.html artık gTab'lı monolit değil, kart-hub (modülerleştirme Faz 1/2). Davranış aynı, yalnız konum sayfa.
2. **"SP_SATIRLAR'a push" → sessionStorage köprüsü.** SP_SATIRLAR başka sayfanın (satin-alma-siparisolustur.html) belleğinde; sayfalar arası aktarım `sp_devir_satirlar` ile (mevcut Bridge A). Sonuç ve satır formatı spec'le aynı.
3. **Eski RFQ emekliye:** `satin-alma-teklifler.html` + 4 eski tablo (`teklif_talepleri` eski şema, `teklif_talep_kalemleri`, `tedarikci_teklifler`, `tedarikci_teklif_kalemleri`) silinir; yeni 3 tablo kurulur (kullanıcı onayı alındı).
4. `teklif_kalemleri.kaynak_ic_talep_kalemi_id` → `satin_alma_talep_kalemleri.id` (uuid) referansı; spec'teki "ic_talep_kalemleri" legacy tabloya değil canlı tabloya bağlanır (tip uuid, uyumlu).

---

## File Structure

- **Create** `docs/kurulum/2026-07-26-teklif-toplama-tablolar.sql` — eski 4 tabloyu düşür + 3 yeni tabloyu kur (kullanıcı çalıştırır).
- **Create** `satin-alma-teklif-toplama.html` — yeni sayfa (liste + teklif talebi oluştur + fiyat gir + karşılaştır + Sipariş Hazırla).
- **Delete** `satin-alma-teklifler.html` — eski RFQ.
- **Modify** `satin-alma.html:84-88` — "Teklifler" kartı → "Teklif Toplama", href yeni sayfaya.
- **Modify** `satin-alma-talepler.html:929,931` — eski teklifler linklerini kaldır/yönlendir.

---

### Task 1: SQL — eski tabloları düşür + 3 yeni tabloyu kur

**Files:**
- Create: `docs/kurulum/2026-07-26-teklif-toplama-tablolar.sql`

**Interfaces:**
- Produces (canlı DB'de): `teklif_talepleri(id uuid, olusturma_tarihi timestamptz, olusturan text, otel_id text, durum text, not_alani text)`, `teklif_kalemleri(id uuid, teklif_talebi_id uuid, urun_kodu text, urun_adi text, miktar numeric, birim text, kaynak_ic_talep_kalemi_id uuid, secilen_teklif_id uuid)`, `teklif_fiyatlari(id uuid, teklif_kalemi_id uuid, firma_id integer, firma_ad text, birim_fiyat numeric, giris_tarihi timestamptz, giren_kullanici text, not_alani text)`.

- [ ] **Step 1: SQL dosyasını yaz**

`docs/kurulum/2026-07-26-teklif-toplama-tablolar.sql`:

```sql
-- Teklif Toplama (RFQ) — eski 4 tablolu RFQ'yu düşür, 3 yeni tabloyu kur.
-- Supabase SQL Editor'e tamamını yapıştır → Run. Geri alınamaz (eski RFQ verisi silinir).
begin;

-- 1) Eski RFQ tablolarını düşür (FK sırasına göre: önce çocuklar)
drop table if exists public.tedarikci_teklif_kalemleri cascade;
drop table if exists public.tedarikci_teklifler cascade;
drop table if exists public.teklif_talep_kalemleri cascade;
drop table if exists public.teklif_talepleri cascade;

-- 2) Yeni tablolar
create table public.teklif_talepleri (
  id uuid primary key default gen_random_uuid(),
  olusturma_tarihi timestamptz not null default now(),
  olusturan text not null,
  otel_id text,
  durum text not null default 'acik',   -- acik | tamamlandi
  not_alani text
);

create table public.teklif_kalemleri (
  id uuid primary key default gen_random_uuid(),
  teklif_talebi_id uuid not null references public.teklif_talepleri(id) on delete cascade,
  urun_kodu text,
  urun_adi text not null,
  miktar numeric not null,
  birim text not null,
  kaynak_ic_talep_kalemi_id uuid,  -- satin_alma_talep_kalemleri.id (FK değil), nullable
  secilen_teklif_id uuid           -- teklif_fiyatlari.id (kullanıcı seçimi), nullable
);

create table public.teklif_fiyatlari (
  id uuid primary key default gen_random_uuid(),
  teklif_kalemi_id uuid not null references public.teklif_kalemleri(id) on delete cascade,
  firma_id integer,                -- FIRMA_DB[].id (FK değil)
  firma_ad text not null,
  birim_fiyat numeric not null,
  giris_tarihi timestamptz not null default now(),
  giren_kullanici text not null,
  not_alani text
);

-- 3) RLS — projenin geri kalanıyla aynı desen: RLS açık, authenticated'a tam izin
alter table public.teklif_talepleri enable row level security;
alter table public.teklif_kalemleri enable row level security;
alter table public.teklif_fiyatlari enable row level security;
create policy tt_hepsi on public.teklif_talepleri for all using(true) with check(true);
create policy tk_hepsi on public.teklif_kalemleri for all using(true) with check(true);
create policy tf_hepsi on public.teklif_fiyatlari for all using(true) with check(true);
grant all on public.teklif_talepleri, public.teklif_kalemleri, public.teklif_fiyatlari to anon, authenticated;

commit;
notify pgrst, 'reload schema';
```

- [ ] **Step 2: Kullanıcı çalıştırır + doğrula**

Kullanıcı SQL'i Supabase SQL Editor'de çalıştırır. Doğrulama (controller, anon key ile REST):
```bash
SBURL=https://xwytofysmgqtqjzkplfi.supabase.co; KEY=<anon>
for t in teklif_talepleri teklif_kalemleri teklif_fiyatlari; do curl -s -o /dev/null -w "$t %{http_code}\n" "$SBURL/rest/v1/$t?select=id&limit=1" -H "apikey: $KEY" -H "Authorization: Bearer $KEY"; done
for t in teklif_talep_kalemleri tedarikci_teklifler tedarikci_teklif_kalemleri; do curl -s -o /dev/null -w "ESKI $t %{http_code}\n" "$SBURL/rest/v1/$t?select=id&limit=1" -H "apikey: $KEY" -H "Authorization: Bearer $KEY"; done
```
Beklenen: 3 yeni tablo `200`; 3 eski tablo `404` (veya `... does not exist`). `teklif_talepleri` yeni şemada `olusturan` kolonuyla döner.

- [ ] **Step 3: Commit**
```bash
git add docs/kurulum/2026-07-26-teklif-toplama-tablolar.sql
git commit -m "feat(teklif): eski RFQ tablolarini dusur + 3 yeni teklif tablosu (SQL)"
```

---

### Task 2: Eski RFQ sayfasını emekliye ayır + hub kartını yeni sayfaya yönlendir

**Files:**
- Delete: `satin-alma-teklifler.html`
- Modify: `satin-alma.html:84-88` (Teklifler kartı)
- Modify: `satin-alma-talepler.html:929,931` (eski teklifler linkleri)

**Interfaces:**
- Consumes: Task 3'te oluşturulacak `satin-alma-teklif-toplama.html` (henüz yok — bu task sadece linki hazırlar; sayfa Task 3'te gelir).
- Produces: hub'da tek "Teklif Toplama" kartı → `satin-alma-teklif-toplama.html`.

- [ ] **Step 1: Eski sayfayı sil**
```bash
git rm satin-alma-teklifler.html
```

- [ ] **Step 2: Hub kartını güncelle (satin-alma.html:84-88)**

`href="satin-alma-teklifler.html"` → `href="satin-alma-teklif-toplama.html"`, `modul-ad` "Teklifler" → "Teklif Toplama", `modul-desc` "RFQ, karşılaştırma" → "Firma teklifleri, karşılaştır, sipariş". SVG ikon aynı kalabilir.

- [ ] **Step 3: satin-alma-talepler.html eski linkleri kaldır**

`satin-alma-talepler.html:929` ve `:931` satırlarındaki `satin-alma-teklifler` referanslarını oku ve bağlamına göre kaldır (buton/link ise sil; navigasyon ise yeni sayfaya yönlendir). Değişiklikten sonra tüm repoda `satin-alma-teklifler` referansı KALMAMALI.

- [ ] **Step 4: Doğrula — hiç eski referans kalmadı**
```bash
grep -rn "satin-alma-teklifler" . --include=*.html --include=*.js || echo "TEMIZ: eski referans yok"
```
Beklenen: `TEMIZ` (0 eşleşme).

- [ ] **Step 5: Commit**
```bash
git add -A
git commit -m "chore(teklif): eski satin-alma-teklifler.html emekliye + hub karti Teklif Toplama'ya yonlendi"
```

---

### Task 3: Yeni sayfa iskeleti + veri yükleme (teklif talepleri listesi + onaylı talepler + FIRMA_DB)

**Files:**
- Create: `satin-alma-teklif-toplama.html`

**Interfaces:**
- Produces: global `TT` (teklif talepleri map), `ONAYLI_TALEPLER` (dizi), `YETKI_HARITASI`; fonksiyonlar `loadTeklifTalepleri()`, `loadOnayliTalepler()`, `renderTeklifTalepleri()`, `yazabilir()`. Satır tipi: `teklif_talepleri` + iç içe `teklif_kalemleri(*,teklif_fiyatlari(*))`.

- [ ] **Step 1: Sayfa iskeletini oluştur (mevcut deseni birebir kopyala)**

`satin-alma-teklif-toplama.html` — `satin-alma-teklifler.html`'in (silinmeden önce `git show HEAD~1:satin-alma-teklifler.html` ile alınabilir) head/stil/header/`requireLogin`+`requireRole(['yonetici','satinalma','depo','cost_control'])`/`nav-drawer.js`/`escapeHtml`/`toast`/`sLD`/`hLD` iskeletini kullan. Başlık: "Teklif Toplama". `<script src="gurok_veritabani.js"></script>` ekle (FIRMA_DB için).

- [ ] **Step 2: Veri yükleme fonksiyonları**

```javascript
let TT={}, ONAYLI_TALEPLER=[], YETKI_HARITASI={};
function yazabilir(){ return ['kayit','tam'].includes(YETKI_HARITASI['siparis_olustur']); }

async function loadTeklifTalepleri(){
  const r=await fetch(SB_URL+'/rest/v1/teklif_talepleri?select=*,teklif_kalemleri(*,teklif_fiyatlari(*))&order=olusturma_tarihi.desc',{headers:SB_HEADERS});
  TT={}; if(r.ok){(await r.json()).forEach(t=>{ TT[t.id]=t; });}
}
async function loadOnayliTalepler(){
  const r=await fetch(SB_URL+'/rest/v1/satin_alma_talepleri?durum=eq.onaylandi&select=id,departman,otel_id,satin_alma_talep_kalemleri(id,urun_adi,urun_kodu,miktar,birim)&order=olusturma_tarihi.desc',{headers:SB_HEADERS});
  ONAYLI_TALEPLER = r.ok ? await r.json() : [];
}
```

- [ ] **Step 3: Liste render + init**

`renderTeklifTalepleri()` — `TT` değerlerini kart/satır listesi olarak çizer (durum rozeti `acik`/`tamamlandi`, kalem sayısı, tarih; satıra tıklayınca `openTeklifDetay(id)` — Task 4/5'te). Boşsa "Henüz teklif talebi yok" göster. Init (IIFE): `YETKI_HARITASI=await kullaniciYetkileriGetir(); sLD(); await Promise.all([loadTeklifTalepleri(),loadOnayliTalepler()]); hLD(); renderTeklifTalepleri();`.

- [ ] **Step 4: Doğrula (statik)**

`grep -n "loadTeklifTalepleri\|loadOnayliTalepler\|YETKI_HARITASI\['siparis_olustur'\]\|teklif_talepleri?select=\*,teklif_kalemleri" satin-alma-teklif-toplama.html` — hepsi mevcut olmalı. Sayfa canlıda (Task 7'de deploy sonrası) hatasız açılmalı, boş liste göstermeli.

- [ ] **Step 5: Commit**
```bash
git add satin-alma-teklif-toplama.html
git commit -m "feat(teklif): Teklif Toplama sayfasi iskeleti + veri yukleme (liste, onayli talepler, yetki)"
```

---

### Task 4: Teklif talebi oluştur (onaylı talep kaleminden veya serbest ürün)

**Files:**
- Modify: `satin-alma-teklif-toplama.html`

**Interfaces:**
- Consumes: `ONAYLI_TALEPLER`, `yazabilir()`, `loadTeklifTalepleri()`, `renderTeklifTalepleri()`.
- Produces: `teklifTalebiOlustur(secilenKalemler)` — `secilenKalemler`: dizi `{urun_kodu, urun_adi, miktar, birim, kaynak_ic_talep_kalemi_id|null}`; `teklif_talepleri`(1) + `teklif_kalemleri`(N) POST eder, döndürdüğü `teklif_talebi.id` ile detayı açar.

- [ ] **Step 1: "Yeni Teklif Talebi" modalı + kalem seçimi**

Buton "➕ Yeni Teklif Talebi" → modal: onaylı talep seçici (`ONAYLI_TALEPLER`) → seçilen talebin `satin_alma_talep_kalemleri` kalemleri checkbox listesi (ad/kod/miktar/birim). Serbest ürün eklemek için (opsiyonel) ürün-adı + miktar + birim satırı da eklenebilir (`kaynak_ic_talep_kalemi_id=null`). "Oluştur" → seçili kalemleri toplar.

- [ ] **Step 2: teklifTalebiOlustur()**

```javascript
async function teklifTalebiOlustur(secilenKalemler, otelId){
  if(!yazabilir()){toast('⚠️ Yetkiniz yok');return;}
  if(!secilenKalemler.length){toast('⚠️ En az bir kalem seçin');return;}
  const tr=await fetch(SB_URL+'/rest/v1/teklif_talepleri',{method:'POST',
    headers:{...SB_HEADERS,'Prefer':'return=representation'},
    body:JSON.stringify({olusturan:CU.ad, otel_id:otelId||'810', durum:'acik'})});
  const talep=(await tr.json())[0];
  const kalemler=secilenKalemler.map(k=>({
    teklif_talebi_id:talep.id, urun_kodu:k.urun_kodu||null, urun_adi:k.urun_adi,
    miktar:k.miktar, birim:k.birim||'KG', kaynak_ic_talep_kalemi_id:k.kaynak_ic_talep_kalemi_id||null
  }));
  await fetch(SB_URL+'/rest/v1/teklif_kalemleri',{method:'POST',headers:SB_HEADERS,body:JSON.stringify(kalemler)});
  await loadTeklifTalepleri(); renderTeklifTalepleri();
  toast('✅ Teklif talebi oluşturuldu'); openTeklifDetay(talep.id);
}
```
Not: `Prefer: return=representation` header'ı POST'un oluşturulan satırı döndürmesini sağlar (proje genelinde kullanılan desen).

- [ ] **Step 3: Doğrula**

Statik: `grep -n "teklifTalebiOlustur\|return=representation" satin-alma-teklif-toplama.html`. Canlı (Task 7): bir onaylı talepten 2 kalem seç → oluştur → listede yeni "açık" talep + DB'de `teklif_kalemleri` 2 satır.

- [ ] **Step 4: Commit**
```bash
git add satin-alma-teklif-toplama.html
git commit -m "feat(teklif): onayli talepten teklif talebi + kalemleri olusturma"
```

---

### Task 5: Firma fiyatı gir + karşılaştırma tablosu + en ucuz otomatik seçim

**Files:**
- Modify: `satin-alma-teklif-toplama.html`

**Interfaces:**
- Consumes: `TT`, `FIRMA_DB`, `yazabilir()`, `loadTeklifTalepleri()`.
- Produces: `openTeklifDetay(id)`, `teklifFiyatiEkle(teklifKalemiId, firmaId, firmaAd, fiyat, notu)`, `renderKarsilastirma(teklifTalebiId)`, `secimGuncelle(teklifKalemiId, teklifFiyatiId)`. Kural: her kalem için en düşük `birim_fiyat` varsayılan seçili; `secilen_teklif_id` NULL ise en ucuz varsayılır.

- [ ] **Step 1: Detay modalı + kalem başına fiyat listesi**

`openTeklifDetay(id)` — `TT[id].teklif_kalemleri` her kalemi başlık; altında `teklif_fiyatlari` satırları (firma_ad, birim_fiyat, not). "➕ Firma Fiyatı Ekle" → firma seçici (`FIRMA_DB`, ürün koduna göre öneri `FIRMA_DB.filter(f=>f.urunler?.includes(kalem.urun_kodu))` + manuel arama) + fiyat + not → `teklifFiyatiEkle`.

- [ ] **Step 2: teklifFiyatiEkle()**
```javascript
async function teklifFiyatiEkle(teklifKalemiId, firmaId, firmaAd, fiyat, notu){
  if(!yazabilir()){toast('⚠️ Yetkiniz yok');return;}
  await fetch(SB_URL+'/rest/v1/teklif_fiyatlari',{method:'POST',headers:SB_HEADERS,body:JSON.stringify({
    teklif_kalemi_id:teklifKalemiId, firma_id:firmaId||null, firma_ad:firmaAd,
    birim_fiyat:parseFloat(fiyat), giren_kullanici:CU.ad, not_alani:notu||null
  })});
  await loadTeklifTalepleri(); openTeklifDetay(document.querySelector('[data-teklif-id]')?.dataset.teklifId);
}
```

- [ ] **Step 3: Karşılaştırma tablosu + en ucuz vurgu/seçim**

`renderKarsilastirma(teklifTalebiId)` — her kalem satırı için o kalemin tüm `teklif_fiyatlari`'nı yan yana radio olarak gösterir; en düşük `birim_fiyat` yeşil vurgulu ve (kalem.`secilen_teklif_id` yoksa) varsayılan `checked`. En ucuz seçimi:
```javascript
function enUcuzTeklifId(kalem){
  const f=(kalem.teklif_fiyatlari||[]).slice().sort((a,b)=>a.birim_fiyat-b.birim_fiyat);
  return f.length?f[0].id:null;
}
async function secimGuncelle(teklifKalemiId, teklifFiyatiId){
  await fetch(SB_URL+'/rest/v1/teklif_kalemleri?id=eq.'+teklifKalemiId,{method:'PATCH',headers:SB_HEADERS,body:JSON.stringify({secilen_teklif_id:teklifFiyatiId})});
  await loadTeklifTalepleri();
}
```
Kullanıcı radio değiştirince `secimGuncelle` çağrılır (PATCH `secilen_teklif_id`).

- [ ] **Step 4: Doğrula**

Statik: `grep -n "teklifFiyatiEkle\|enUcuzTeklifId\|secimGuncelle\|renderKarsilastirma" satin-alma-teklif-toplama.html`. Canlı (Task 7): bir kaleme 3 firma fiyatı gir → en düşük yeşil+seçili → başka firmayı seç → PATCH sonrası kalıcı (yeniden aç, seçim korunur).

- [ ] **Step 5: Commit**
```bash
git add satin-alma-teklif-toplama.html
git commit -m "feat(teklif): firma fiyati girisi + karsilastirma + en ucuz otomatik secim"
```

---

### Task 6: "Sipariş Hazırla" → SP_SATIRLAR köprüsü (sessionStorage)

**Files:**
- Modify: `satin-alma-teklif-toplama.html`

**Interfaces:**
- Consumes: `TT`, `FIRMA_DB`, `yazabilir()`, `enUcuzTeklifId()`.
- Produces: `teklifSiparisHazirla(teklifTalebiId)` — her kalemin seçili (yoksa en ucuz) teklifinden `{ad, kod, miktar, birim, firmaId, firmaAd, tahminiFiyat}` satırı üretir, `sessionStorage['sp_devir_satirlar']`'a yazar, `teklif_talepleri.durum='tamamlandi'` PATCH eder, `location.href='satin-alma-siparisolustur.html'`.

- [ ] **Step 1: teklifSiparisHazirla()**
```javascript
async function teklifSiparisHazirla(teklifTalebiId){
  if(!yazabilir()){toast('⚠️ Yetkiniz yok');return;}
  const t=TT[teklifTalebiId]; if(!t)return;
  const satirlar=[];
  (t.teklif_kalemleri||[]).forEach(k=>{
    const secId=k.secilen_teklif_id||enUcuzTeklifId(k);
    const fy=(k.teklif_fiyatlari||[]).find(f=>f.id===secId);
    satirlar.push({
      ad:k.urun_adi, kod:k.urun_kodu||'', miktar:k.miktar, birim:k.birim||'KG',
      firmaId: fy?(fy.firma_id||''):'', firmaAd: fy?fy.firma_ad:'', tahminiFiyat: fy?fy.birim_fiyat:''
    });
  });
  if(!satirlar.length){toast('⚠️ Aktarılacak kalem yok');return;}
  sessionStorage.setItem('sp_devir_satirlar', JSON.stringify(satirlar));
  try{ await fetch(SB_URL+'/rest/v1/teklif_talepleri?id=eq.'+teklifTalebiId,{method:'PATCH',headers:SB_HEADERS,body:JSON.stringify({durum:'tamamlandi'})}); }catch(e){console.warn(e);}
  location.href='satin-alma-siparisolustur.html';
}
```
Detay/karşılaştırma modalında "🧾 Sipariş Hazırla" butonu bu fonksiyonu çağırır.

- [ ] **Step 2: Doğrula — satır formatı alıcıyla birebir**

`satin-alma-siparisolustur.html:443-448` alıcısı `SP_SATIRLAR=JSON.parse(sessionStorage['sp_devir_satirlar'])` yapıyor; `renderSPSatirlar` (satır 332+) `u.ad,u.kod,u.miktar,u.birim,u.tahminiFiyat` + firma alanlarını okuyor. Statik doğrulama: üretilen anahtarlar (`ad,kod,miktar,birim,firmaId,firmaAd,tahminiFiyat`) satin-alma-siparisolustur.html:318 varsayılan satır anahtarlarıyla aynı mı `grep` ile karşılaştır.

- [ ] **Step 3: Commit**
```bash
git add satin-alma-teklif-toplama.html
git commit -m "feat(teklif): Siparis Hazirla — secili teklifleri SP_SATIRLAR kopruusune (sessionStorage) aktar"
```

---

### Task 7: Uçtan uca doğrulama (deploy + canlı test)

**Files:** (yok — doğrulama)

- [ ] **Step 1: Push + deploy**
```bash
git push origin main
```
GitHub Pages ~1 dk yeniden yayınlar. Canlı dosyada kod doğrula:
```bash
curl -s "https://mehmetaraz0.github.io/gurok-mal-kabul/satin-alma-teklif-toplama.html" | grep -c "teklifSiparisHazirla"
```
Beklenen: ≥1.

- [ ] **Step 2: Kullanıcı uçtan uca test (SQL sonrası)**

1. Task 1 SQL'i çalıştırıldı mı doğrula (3 yeni tablo 200).
2. Satın Alma → Teklif Toplama → Yeni Teklif Talebi → onaylı bir talepten 2 kalem seç → oluştur.
3. Her kaleme 2-3 firma fiyatı gir → en ucuz yeşil/seçili görünüyor mu.
4. Bir kalemde en ucuz yerine başka firmayı seç (kalıcı mı — yeniden aç).
5. "Sipariş Hazırla" → `satin-alma-siparisolustur.html` açılıyor, satırlar firma+fiyat önceden dolu mu.
6. Sipariş oluştur akışı normal tamamlanıyor mu; teklif talebi "tamamlandı" oldu mu.

- [ ] **Step 3: Hafıza + kapanış notu**

Bu özelliğin CANLI olduğunu ve eski RFQ'nun emekliye ayrıldığını proje hafızasına yaz (yeni `gurok-teklif-toplama` memory + MEMORY.md pointer).

---

## Self-Review

**1. Spec coverage:** Yeni sekme→Task 2/3 (sayfa+kart). 3 tablo→Task 1. İç Talep'ten kalem→Task 4. Firma fiyatı→Task 5. En ucuz otomatik+değiştirilebilir→Task 5. Sipariş Hazırla→SP_SATIRLAR→Task 6. Min. teklif kuralı kapsam dışı→Global Constraints. FIRMA_DB serbest metin/id→Task 5 (firma_id nullable). Kapsandı.

**2. Placeholder taraması:** SQL tam; fonksiyon gövdeleri gerçek kod; bulk UI iskeleti mevcut dosya desenine (`satin-alma-teklifler.html`/`-talepler.html`) referansla — bu projede test çerçevesi yok, doğrulama statik grep + canlı manuel (projenin yerleşik "Uçtan uca doğrulama" deseni).

**3. Tip tutarlılığı:** SP satır anahtarları (`ad,kod,miktar,birim,firmaId,firmaAd,tahminiFiyat`) Task 6'da üretilen = alıcı (siparisolustur:318) ile aynı. `secilen_teklif_id`/`enUcuzTeklifId` isimleri Task 5↔6 tutarlı. `teklif_talebi_id` FK adı tabloda ve POST'larda aynı.
