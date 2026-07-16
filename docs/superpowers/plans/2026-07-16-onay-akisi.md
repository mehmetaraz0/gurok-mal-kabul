# Satın Alma Talepleri — Çok Aşamalı Onay Akışı Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `satin-alma.html`'deki tek aşamalı, kayıt eksiği olan onay mekanizmasını (`talepOnayla`/`talepReddet`), gerçek iş sürecini modelleyen çok aşamalı bir onay motoruyla değiştirmek: Depo → Cost Control → (tutara göre) Satınalma Müdürü / Grup Satınalma Direktörü / GM / Grup Direktörü.

**Architecture:** Yeni paylaşılan `onay-motoru.js` dosyası (repo kökü, `auth-guard.js` gibi `<head>`'den senkron yüklenir) aşama tanımlarını (`ONAY_KATMANLARI`), yönlendirme mantığını (`sonrakiAsamaBelirle`) ve güvenli geçiş fonksiyonunu (`talepAsamaIlerlet`) taşır — `stok-takip.html`'deki `sayimOnayla`'nın stale-state-guard deseniyle. `satin-alma.html` bu dosyayı yükler, eski `talepOnayla`/`talepReddet`'i kaldırır, listeyi `asama` alanına göre filtreler.

**Tech Stack:** Vanilla HTML/JS, Supabase REST (fetch) — build aracı/test çerçevesi yok.

---

## Global Constraints

- Depo ve Cost aşamaları limitsiz — onay yetkisi değil "ürün/bütçe kontrolü" geçişi (spec).
- Tutara göre yönlendirme **tek katmana düşer** — sıralı çoklu imza değil; 300.000 ₺'lik talep `satinalma_mdr`'a hiç görünmeden doğrudan `grup_satinalma`'ya gider (spec).
- Tutar sadece Cost aşamasında girilir, talep oluşturulurken bilinmez (spec).
- Her aşama geçişi `talep_onay_gecmisi`'ne yazılır — kim, hangi karar, ne zaman, hangi not (spec).
- `talepAsamaIlerlet` PATCH'ten önce talebin güncel `asama`/`durum`'unu canlı GET ile tazeler; beklenmedik durumda işlemi durdurur (sayım deseniyle aynı, spec).
- Katman rolleri (`satinalma_mdr`,`grup_satinalma`,`gm`,`grup_direktor`) `kullanicilar.rol` (legacy flatten) üzerinden AYIRT EDİLEMEZ — hepsi `satinalma`/`yonetici`'ye düşüyor (bkz. `kullanici-yonetimi.html:106-110`). Bu dört katman için asıl kaynak `kullanicilar.rol_id` → `roller.kod` çözümlemesi olmalı; `depo`/`cost_control` aşamaları için mevcut flatten `CU.rol` yeterli (ayrım gerekmiyor).

---

### Task 1: Supabase şema değişikliği (kullanıcı tarafından çalıştırılır)

**Files:**
- Modify: Supabase SQL Editor (kod tabanında dosya yok)

**Interfaces:**
- Produces: `satin_alma_talepleri.asama/tutar/onaylayan_ad/onay_tarihi` kolonları, `talep_onay_gecmisi` tablosu — Task 2/3'ün okuma/yazma işlemleri bunlara.

- [ ] **Step 1: Kullanıcıya SQL'i ver, Supabase SQL Editor'de çalıştırmasını iste**

```sql
ALTER TABLE satin_alma_talepleri
  ADD COLUMN IF NOT EXISTS asama text DEFAULT 'depo',
  ADD COLUMN IF NOT EXISTS tutar numeric,
  ADD COLUMN IF NOT EXISTS onaylayan_ad text,
  ADD COLUMN IF NOT EXISTS onay_tarihi timestamptz;

UPDATE satin_alma_talepleri SET asama='depo' WHERE asama IS NULL AND durum='bekleyen';

CREATE TABLE IF NOT EXISTS talep_onay_gecmisi (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  talep_id uuid REFERENCES satin_alma_talepleri(id),
  asama text NOT NULL,
  rol_kodu text,
  kullanici_ad text,
  karar text NOT NULL,
  not_metni text,
  created_at timestamptz DEFAULT now()
);
```

- [ ] **Step 2: Kullanıcı çalıştırdıktan sonra doğrula**

```bash
curl -s --ssl-no-revoke "https://xwytofysmgqtqjzkplfi.supabase.co/rest/v1/satin_alma_talepleri?select=id,asama,tutar,onaylayan_ad,onay_tarihi&limit=1" -H "apikey: <SB_KEY>" -H "Authorization: Bearer <SB_KEY>"
curl -s --ssl-no-revoke "https://xwytofysmgqtqjzkplfi.supabase.co/rest/v1/talep_onay_gecmisi?select=id&limit=1" -H "apikey: <SB_KEY>" -H "Authorization: Bearer <SB_KEY>"
```
Expected: İkisi de `200`; ilki mevcut talep satırlarını yeni kolonlarla (asama dolu, diğerleri null) döner, ikincisi `[]` döner.

---

### Task 2: `onay-motoru.js` — paylaşılan onay motoru

**Files:**
- Create: `onay-motoru.js`

**Interfaces:**
- Produces: `ONAY_KATMANLARI`, `sonrakiAsamaBelirle(mevcutAsama, tutar)`, `kullaniciAsamaYetkiliMi(kullanici, asama)`, `talepAsamaIlerlet(talepId, kullanici, karar, {tutar, not})` — Task 3'ün `satin-alma.html` entegrasyonu bunları çağırır.

- [ ] **Step 1: Aşama tanımları ve saf yönlendirme fonksiyonu**

```js
// onay-motoru.js — Gürok ERP paylaşılan çok aşamalı onay motoru.
// satin-alma.html gibi onay akışı olan sayfalar bunu <head> içinde
// auth-guard.js'den SONRA, senkron olarak yükler.

const ONAY_KATMANLARI = {
  depo:        { sonraki: 'cost',        roller: ['depo'],          tip: 'kontrol' },
  cost:        { sonraki: null,          roller: ['cost_control'],  tip: 'tutar_gir' },
  mdr:         { sonraki: null,          roller: ['satinalma_mdr'], tip: 'onay', limit: 200000 },
  direktor:    { sonraki: null,          roller: ['grup_satinalma'],tip: 'onay', limit: 500000 },
  gm:          { sonraki: null,          roller: ['gm'],            tip: 'onay', limit: 750000 },
  ust_yonetim: { sonraki: null,          roller: ['grup_direktor'], tip: 'onay', limit: null }
};

// Cost aşaması onaylandığında tutara göre hangi katmana düşeceğini belirler.
function tutaraGoreKatmanSec(tutar){
  const t = parseFloat(tutar) || 0;
  if (t <= 200000) return 'mdr';
  if (t <= 500000) return 'direktor';
  if (t <= 750000) return 'gm';
  return 'ust_yonetim';
}

// mevcutAsama + (varsa) tutar verildiğinde bir sonraki asamayı döner.
// null dönerse: süreç biter, durum='onaylandi' yazılır.
function sonrakiAsamaBelirle(mevcutAsama, tutar){
  if (mevcutAsama === 'depo') return 'cost';
  if (mevcutAsama === 'cost') return tutaraGoreKatmanSec(tutar);
  return null; // mdr/direktor/gm/ust_yonetim onayladıysa süreç biter
}
```

- [ ] **Step 2: Rol çözümleme — `kullanicilar.rol_id` → `roller.kod`**

```js
let _rollerKodCache = null; // {rolId: kod}
async function rollerKodHaritasiYukle(){
  if (_rollerKodCache) return _rollerKodCache;
  _rollerKodCache = {};
  try{
    const r = await fetch(SB_URL+'/rest/v1/roller?select=id,kod', {headers: SB_HEADERS});
    if (r.ok) (await r.json()).forEach(x => { _rollerKodCache[x.id] = x.kod; });
  }catch(e){ console.warn(e); }
  return _rollerKodCache;
}

// depo/cost aşamaları legacy CU.rol üzerinden ayırt edilebiliyor (depo_sef+depo -> 'depo',
// cost_control_mdr+cost_control -> 'cost_control'). mdr/direktor/gm/ust_yonetim için
// legacy rol hepsini 'satinalma'/'yonetici'ye düşürüyor — bu dördü SADECE rol_id->kod ile ayırt edilir.
async function kullaniciAsamaYetkiliMi(kullanici, asama){
  const katman = ONAY_KATMANLARI[asama];
  if (!katman) return false;
  if (asama === 'depo' || asama === 'cost'){
    return katman.roller.includes(kullanici.rol);
  }
  const harita = await rollerKodHaritasiYukle();
  const kod = harita[kullanici.rol_id];
  return katman.roller.includes(kod);
}
```

- [ ] **Step 3: Güvenli aşama ilerletme (stale-state guard, `sayimOnayla` deseni)**

```js
let _talepAsamaIsleniyor = false;

async function talepAsamaIlerlet(talepId, kullanici, karar, {tutar, not} = {}){
  if (_talepAsamaIsleniyor) return {ok:false, hata:'islemde'};
  _talepAsamaIsleniyor = true;
  try{
    // 1) Canlı durumu tazele — başka biri az önce bu talebi ilerletmiş olabilir.
    const guncelR = await fetch(SB_URL+'/rest/v1/satin_alma_talepleri?id=eq.'+talepId+'&select=asama,durum', {headers: SB_HEADERS});
    if (!guncelR.ok) return {ok:false, hata:'canli_okuma_basarisiz'};
    const guncelListe = await guncelR.json();
    const guncel = guncelListe[0];
    if (!guncel || guncel.durum !== 'bekleyen') return {ok:false, hata:'zaten_karar_verilmis'};

    const asama = guncel.asama;
    if (!await kullaniciAsamaYetkiliMi(kullanici, asama)) return {ok:false, hata:'yetkisiz'};

    if (karar === 'red'){
      await fetch(SB_URL+'/rest/v1/talep_onay_gecmisi', {method:'POST', headers: SB_HEADERS,
        body: JSON.stringify({talep_id: talepId, asama, rol_kodu: kullanici.rol, kullanici_ad: kullanici.ad, karar: 'red', not_metni: not||null})});
      await fetch(SB_URL+'/rest/v1/satin_alma_talepleri?id=eq.'+talepId, {method:'PATCH', headers: SB_HEADERS,
        body: JSON.stringify({durum:'reddedildi', onaylayan_ad: kullanici.ad, onay_tarihi: new Date().toISOString()})});
      return {ok:true, sonuc:'reddedildi'};
    }

    // Cost aşamasında tutar zorunlu — sonraki katman bu değere göre belirlenir.
    if (asama === 'cost' && (tutar===undefined || tutar===null || isNaN(parseFloat(tutar)))) {
      return {ok:false, hata:'tutar_gerekli'};
    }

    await fetch(SB_URL+'/rest/v1/talep_onay_gecmisi', {method:'POST', headers: SB_HEADERS,
      body: JSON.stringify({talep_id: talepId, asama, rol_kodu: kullanici.rol, kullanici_ad: kullanici.ad, karar: 'onay', not_metni: not||null})});

    const sonrakiAsama = sonrakiAsamaBelirle(asama, tutar);
    const patchBody = {};
    if (asama === 'cost') patchBody.tutar = parseFloat(tutar);

    if (sonrakiAsama){
      patchBody.asama = sonrakiAsama;
    } else {
      patchBody.durum = 'onaylandi';
      patchBody.onaylayan_ad = kullanici.ad;
      patchBody.onay_tarihi = new Date().toISOString();
    }
    await fetch(SB_URL+'/rest/v1/satin_alma_talepleri?id=eq.'+talepId, {method:'PATCH', headers: SB_HEADERS, body: JSON.stringify(patchBody)});
    return {ok:true, sonuc: sonrakiAsama || 'onaylandi'};
  } catch(e) {
    console.warn(e);
    return {ok:false, hata:'istisna'};
  } finally {
    _talepAsamaIsleniyor = false;
  }
}
```

- [ ] **Step 4: Doğrula**

```bash
grep -n "ONAY_KATMANLARI\|function sonrakiAsamaBelirle\|function kullaniciAsamaYetkiliMi\|function talepAsamaIlerlet" onay-motoru.js
```
Expected: 4 tanım da görünmeli.

- [ ] **Step 5: Commit**

```bash
git add onay-motoru.js
git -c user.name="mehmetaraz0" -c user.email="mehmetaraz868@gmail.com" commit -m "feat: add onay-motoru.js shared multi-stage approval engine"
```

---

### Task 3: `satin-alma.html` entegrasyonu

**Files:**
- Modify: `satin-alma.html:5` (`<head>`, script include)
- Modify: `satin-alma.html:495-501` (`loadDB` — yeni kolonları `DB.talepler`'e map et)
- Modify: `satin-alma.html:870-894` (`renderTalepler` — `asama`'ya göre filtrele)
- Modify: `satin-alma.html:1008-1041` (`openTalepDetay` — aşama geçmişi + tutar girişi UI)
- Modify: `satin-alma.html:1043-1055` (`talepOnayla`/`talepReddet` kaldır, yeni akışla değiştir)

**Interfaces:**
- Consumes: `onay-motoru.js`'in `talepAsamaIlerlet`, `kullaniciAsamaYetkiliMi`.
- Produces: kullanıcıya rolüne uyan aşamadaki talepleri gösteren liste, Cost aşamasında tutar girişi modalı, talep detayında aşama geçmişi zaman çizelgesi.

- [ ] **Step 1: Script include**

Mevcut (satır 5):
```html
<script src="auth-guard.js"></script>
```
şuna çevir:
```html
<script src="auth-guard.js"></script>
<script src="onay-motoru.js"></script>
```

- [ ] **Step 2: `loadDB` — yeni kolonları map et**

Mevcut (satır 495-501):
```js
        DB.talepler[r.id]={
          id:r.id,tarih:r.olusturma_tarihi?new Date(r.olusturma_tarihi).toISOString().split('T')[0]:'',
          olusturmaTarih:r.olusturma_tarihi?new Date(r.olusturma_tarihi).getTime():Date.now(),
          departman:r.departman,personel:r.talep_eden||'',aciliyet:r.aciliyet,not:r.not_alani||'',
          durum:r.durum,
          satirlar:(r.satin_alma_talep_kalemleri||[]).map(k=>({id:k.id,ad:k.urun_adi,kod:k.urun_kodu||'',miktar:k.miktar,birim:k.birim}))
        };
```
şuna çevir (yeni alanlar eklenir, mevcutlar korunur):
```js
        DB.talepler[r.id]={
          id:r.id,tarih:r.olusturma_tarihi?new Date(r.olusturma_tarihi).toISOString().split('T')[0]:'',
          olusturmaTarih:r.olusturma_tarihi?new Date(r.olusturma_tarihi).getTime():Date.now(),
          departman:r.departman,personel:r.talep_eden||'',aciliyet:r.aciliyet,not:r.not_alani||'',
          durum:r.durum,asama:r.asama||'depo',tutar:r.tutar,onaylayanAd:r.onaylayan_ad||'',onayTarih:r.onay_tarihi||null,
          satirlar:(r.satin_alma_talep_kalemleri||[]).map(k=>({id:k.id,ad:k.urun_adi,kod:k.urun_kodu||'',miktar:k.miktar,birim:k.birim}))
        };
```

- [ ] **Step 3: `renderTalepler` — aşama+rol filtresi**

`talepFilter!=='tumu'` durum filtresinin YANINA (onu değiştirmeden, ek bir filtre olarak), `bekleyen` durumundaki talepler için kullanıcının o talebin `asama`'sında yetkili olup olmadığını kontrol eden bir filtre eklenir — `kullaniciAsamaYetkiliMi` async olduğu için, `renderTalepler` her bekleyen talep için önceden hesaplanmış bir `_yetkiliAsamalar` set'i kullanır (sayfa yüklenirken / kullanıcı değiştiğinde bir kez hesaplanır, senkron filtreleme için). Yani `renderTalepler` senkron kalır; `_yetkiliAsamalar` her `loadDB()` sonrası `hesaplaYetkiliAsamalar()` ile dolduran ayrı bir async fonksiyon eklenir. `bekleyen` olmayan (onaylandı/reddedildi/siparis) talepler filtre olmadan herkese görünür (geçmiş kayıt).

- [ ] **Step 4: `openTalepDetay` — aşama geçmişi + tutar girişi + eylem butonları**

`t.durum==='bekleyen'` bloğu, mevcut sabit "Reddet/Onayla/Siparişe Dönüştür" yerine: kullanıcı o talebin `asama`'sında yetkiliyse "Reddet"/"Onayla" gösterilir (asama `'cost'` ise Onayla'dan önce bir tutar `<input>` alanı sorulur — boşsa engellenir); yetkili değilse sadece "Kapat" gösterilir. Ayrıca `talep_onay_gecmisi` bu talep için GET edilip (`?talep_id=eq.<id>&order=created_at.asc`) kronolojik bir liste olarak modalın altına eklenir (aşama, kullanıcı, karar, not, tarih).

- [ ] **Step 5: `talepOnayla`/`talepReddet` kaldır, yeni akışla değiştir**

Mevcut (satır 1043-1055) SİLİNİR. Yerine `openTalepDetay`'deki butonların çağırdığı tek bir fonksiyon gelir:

```js
async function talepKararVer(id, karar, opts){
  const t=DB.talepler[id];if(!t)return;
  const sonuc = await talepAsamaIlerlet(id, CU, karar, opts||{});
  if (!sonuc.ok){
    const mesajlar = {zaten_karar_verilmis:'⚠️ Bu talep az önce başka biri tarafından ilerletildi',
      yetkisiz:'❌ Bu işlem için yetkiniz yok', tutar_gerekli:'⚠️ Tutar girilmeli'};
    toast(mesajlar[sonuc.hata] || '❌ İşlem başarısız, tekrar deneyin');
    return;
  }
  kModal('mTalepDetay');
  toast(karar==='red' ? '❌ Talep reddedildi' : '✅ Talep ilerletildi');
  await loadDB();
  renderTalepler();
}
```

- [ ] **Step 6: Doğrula**

```bash
grep -n "onay-motoru.js\|talepAsamaIlerlet\|talepKararVer\|function talepOnayla\|function talepReddet" satin-alma.html
```
Expected: script include, `talepAsamaIlerlet`/`talepKararVer` çağrıları görünmeli; `function talepOnayla`/`function talepReddet` artık HİÇ görünmemeli (kaldırıldı).

- [ ] **Step 7: Kod okuyarak izleme**

`talepAsamaIlerlet`'in PATCH'ten önce gerçekten canlı GET yaptığını ve `durum!=='bekleyen'` durumunda işlemi durdurduğunu doğrula. `kullaniciAsamaYetkiliMi`'nin UI'daki buton gizlemesinden BAĞIMSIZ, `talepAsamaIlerlet` içinde de çağrıldığını doğrula (UI gizlemesi tek başına yetki kontrolü değildir — `sayimOnayla`'daki aynı ilke).

- [ ] **Step 8: Commit**

```bash
git add satin-alma.html
git -c user.name="mehmetaraz0" -c user.email="mehmetaraz868@gmail.com" commit -m "feat: replace single-stage talep approval with multi-stage onay-motoru flow"
```

---

### Task 4: Uçtan uca doğrulama

**Files:** (yok — sadece doğrulama)

- [ ] **Step 1: Tüm yeni tanımların tutarlılığını kontrol et**

```bash
grep -n "talep_onay_gecmisi\|ONAY_KATMANLARI" satin-alma.html onay-motoru.js
```
Expected: tablo/sabit adları her iki dosyada tutarlı yazılmalı.

- [ ] **Step 2: Kullanıcıya manuel test adımlarını bildir**

1. Task 1'deki SQL'i Supabase SQL Editor'de çalıştır.
2. `depo` rolüyle giriş yap, yeni bir talep oluştur → Bekleyen Talepler'de görünmeli, `asama='depo'`.
3. Aynı talebi `depo` onaylar → `cost` aşamasına geçmeli; `depo` kullanıcısının listesinden kaybolmalı.
4. `cost_control` rolüyle: talebe tutar gir (ör. 300.000 ₺), onayla → `satinalma_mdr` DEĞİL, doğrudan `grup_satinalma` rolüne düşmeli (kullanici-yonetimi.html'de bu role bir kullanıcı ata, yoksa test için geçici ata).
5. `satinalma_mdr` rolüyle giriş yapıp bu talebi GÖRMEDİĞİNİ doğrula (yanlış katmana yönlendirilmediğinin kanıtı).
6. `grup_satinalma` onaylar → `durum='onaylandi'`, `onaylayan_ad`/`onay_tarihi` dolu, talep geçmişinde 3 satır (`depo`,`cost`,`direktor`) görünmeli.
7. Farklı bir talebi bir aşamada reddet, not gir → `talep_onay_gecmisi`'nde `karar='red'` ve not kalıcı olmalı (mevcut kodda hiç kaydedilmiyordu — regresyon testi).
8. Aynı talebi iki sekmede aç, ikisinden de aynı anda ilerletmeyi dene → ikinci sekme "az önce ilerletildi" uyarısı almalı.
9. Küçük tutarlı (≤200.000 ₺) bir talebin `satinalma_mdr` katmanında durduğunu, üst katmanlara hiç gitmediğini doğrula.

- [ ] **Step 3: Kullanıcıdan onay al, sonra push**

```bash
git fetch
git log --oneline main..origin/main
```
Expected: paralel oturumdan gelen değişiklik var mı kontrol et, varsa kullanıcıya bildir. Yoksa kullanıcı onayıyla `git push`.
