# Config Değerlerinin Merkezileştirilmesi (otel-config.js) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Otel/depo sabitlerini (`OTEL_ISIMLERI`, `OTEL_KISA`, ticari unvan, e-posta domaini, merkezi depo kodu türetme mantığı) 16 dosyaya dağılmış kopyalardan tek bir `otel-config.js` dosyasına taşımak — yeni bir müşteri kurulumunda sadece bu dosya düzenlensin.

**Architecture:** `supabase-config.js`'nin yanına, aynı yükleme deseninde yeni bir statik JS dosyası eklenir. Her hedef dosyada üç mekanik adım: script include eklenir, yerel `const` tanımı silinir, varsa `otelId==='811'?'300':'100'` ternary'si `merkeziDepoKodu(otelId)` çağrısına çevrilir.

**Tech Stack:** Vanilla HTML/JS.

## Global Constraints

- `otel-config.js`, `SB_URL`/`SB_HEADERS` dahil başka HİÇBİR dosyaya bağımlı olmamalı — saf sabitler + 2 saf fonksiyon.
- Script sırası her dosyada: `auth-guard.js` → `supabase-config.js` → **`otel-config.js`** → `ortak.js` → (varsa diğer script'ler) → `theme.css`.
- Yerel `const OTEL_ISIMLERI=...` / `const OTEL_KISA=...` tanımları SİLİNMELİDİR (yorum olarak bırakılmaz) — aksi halde `const` yeniden tanımlama hatası (SyntaxError) oluşur.
- `kullanici-yonetimi.html`'deki mevcut YANLIŞ değer (`{'810':'Club Manavgat','811':'Resort Sorgun'}`, "Ali Bey" ön eki eksik) düzeltilerek merkezi (doğru) değere geçilir — bu bilinen bir bug, bilinçli olarak düzeltiliyor.
- `gurok_veritabani.js`'e (ürün/tedarikçi kataloğu) HİÇ dokunulmaz — kapsam dışı.
- Bu proje repoda paralel bir oturumun sürekli push yaptığı ortak bir repo — her task'tan önce implementer `git fetch origin` + gerekirse `git pull --ff-only` yapmalı, sonra dosyayı `Read`/`Grep` ile GÜNCEL haliyle açmalı. Bu planda verilen satır numaraları YOKTUR (bilinçli olarak) — sadece arama kalıpları (`OTEL_ISIMLERI=`, `OTEL_KISA=` vb.) verilmiştir, implementer gerçek konumu kendisi bulmalı.

---

## Task 1: `otel-config.js` Dosyasını Oluştur

**Files:**
- Create: `otel-config.js`

**Interfaces:**
- Produces: `OTEL_ISIMLERI`, `OTEL_KISA`, `OTEL_TICARI_UNVAN`, `GRUP_ADI`, `DAHILI_EMAIL_DOMAIN`, `MERKEZI_DEPO`, `merkeziDepoKodu(otelId)`, `otelFromDepoId(depoId)`. Task 2-13'ün tamamı bunu tüketir.

- [ ] **Step 1: Dosyayı oluştur**

```js
// otel-config.js — Gürok ERP müşteriye özel kurulum sabitleri.
// Yeni bir müşteri kurulumunda SADECE bu dosya düzenlenir, başka hiçbir
// dosyaya dokunulmaz. auth-guard.js -> supabase-config.js -> otel-config.js
// -> ortak.js sırasında, senkron olarak yüklenir.

const OTEL_ISIMLERI = {'810':'Ali Bey Club Manavgat','811':'Ali Bey Resort Sorgun'};
const OTEL_KISA = {'810':'Club','811':'Resort'};
const OTEL_TICARI_UNVAN = {'810':'GUROK TUR MAD.A.S. (CLUB MANAVGAT)','811':'GUROK TUR MAD.A.S. (RESORT SORGUN)'};
const GRUP_ADI = 'Gürok Turizm Grubu';
const DAHILI_EMAIL_DOMAIN = 'gurok.internal';
const MERKEZI_DEPO = {'810':'100','811':'300'};

function merkeziDepoKodu(otelId){ return MERKEZI_DEPO[otelId] || '100'; }
function otelFromDepoId(depoId){ const i=(depoId||'').indexOf('_'); return i>=0 ? depoId.slice(0,i) : '810'; }
```

- [ ] **Step 2: Statik doğrulama**

Dosyanın sözdizimsel olarak geçerli olduğunu (parantez/süslü parantez dengesi) kontrol et.

- [ ] **Step 3: Commit**

```bash
git add otel-config.js
git -c user.name="mehmetaraz0" -c user.email="mehmetaraz868@gmail.com" commit -m "feat: otel-config.js oluşturuldu — merkezi otel/depo sabitleri"
```

---

## Task 2: `mal-kabul-liste.html` Migrasyonu

**Files:**
- Modify: `mal-kabul-liste.html`

**Interfaces:**
- Consumes: Task 1'in `OTEL_ISIMLERI`, `OTEL_KISA`, `merkeziDepoKodu(otelId)`.

Bu dosya en karmaşık migrasyon — hem `OTEL_ISIMLERI` hem `OTEL_KISA` tanımlıyor HEM de depo kodu ternary'sini (`otelId==='811'?'300':'100'`) EN AZ 4 farklı yerde tekrarlıyor (bazıları `bareDepoKodu` değişken adıyla, biri satır içinde hem depoKodu hem "Resort"/"Club" mantığını birlikte içeriyor).

- [ ] **Step 1: Güncel dosyayı oku, script include satırını bul**

`Grep "supabase-config.js"` ile bul, hemen altına ekle:

```html
<script src="otel-config.js"></script>
```

- [ ] **Step 2: Yerel `OTEL_ISIMLERI`/`OTEL_KISA` tanımlarını sil**

`Grep "OTEL_ISIMLERI="` ve `Grep "OTEL_KISA="` ile bul, her iki `const` satırını TAMAMEN sil (merkezi dosyadakiler kullanılacak).

- [ ] **Step 3: Depo kodu ternary'lerini `merkeziDepoKodu()` çağrısına çevir**

`Grep "otelId==='811'?'300':'100'"` ile TÜM eşleşmeleri bul (en az 3-4 tane olmalı, bazıları `depoKodu`, bazıları `bareDepoKodu` değişkenine atanıyor). Her birinde:

Kalıp: `otelId==='811'?'300':'100'` → değiştir: `merkeziDepoKodu(otelId)`

Örnek (bulunan satırlardan biri, aynı mantıkla diğerlerini de çevir):
```js
// Eski: const depoKodu=otelId==='811'?'300':'100';
// Yeni:
const depoKodu=merkeziDepoKodu(otelId);
```

**Dikkat:** bir satırda hem depo kodu HEM `'Resort'`/`'Club'` mantığı birlikte geçiyor. Bu satırda SADECE depo-kodu kısmını `merkeziDepoKodu(f.otelId)`'ye çevir, `'Resort'`/`'Club'` kısmını `OTEL_KISA[f.otelId]`'ye çevir (ikisi de artık merkezi kaynaktan geliyor):

```js
// Eski: `${f.depoKodu||(f.otelId==='811'?'300':'100')} — ${(f.otelId==='811'?'Resort':'Club')} İşletme Depo`
// Yeni:
`${f.depoKodu||merkeziDepoKodu(f.otelId)} — ${OTEL_KISA[f.otelId]} İşletme Depo`
```

- [ ] **Step 4: Statik doğrulama**

`grep -c "OTEL_ISIMLERI=\|OTEL_KISA=" mal-kabul-liste.html` → `0` dönmeli (tanımlar silindi, sadece KULLANIMLAR kalmalı). `grep -c "otelId==='811'?'300':'100'"` → `0` dönmeli.

- [ ] **Step 5: Commit**

```bash
git add mal-kabul-liste.html
git -c user.name="mehmetaraz0" -c user.email="mehmetaraz868@gmail.com" commit -m "refactor: mal-kabul-liste.html otel-config.js'e geçirildi"
```

---

## Task 3: `mal-kabul-uygunsuzluk.html` Migrasyonu

**Files:**
- Modify: `mal-kabul-uygunsuzluk.html`

**Interfaces:**
- Consumes: Task 1'in `OTEL_ISIMLERI`, `OTEL_KISA`.

- [ ] **Step 1: Script include ekle**

`Grep "supabase-config.js"` ile bul, hemen altına `<script src="otel-config.js"></script>` ekle.

- [ ] **Step 2: Yerel tanımları sil**

`Grep "OTEL_ISIMLERI="` ve `Grep "OTEL_KISA="` ile bul, ikisini de sil.

- [ ] **Step 3: Statik doğrulama**

`grep -c "OTEL_ISIMLERI=\|OTEL_KISA=" mal-kabul-uygunsuzluk.html` → `0`.

- [ ] **Step 4: Commit**

```bash
git add mal-kabul-uygunsuzluk.html
git -c user.name="mehmetaraz0" -c user.email="mehmetaraz868@gmail.com" commit -m "refactor: mal-kabul-uygunsuzluk.html otel-config.js'e geçirildi"
```

---

## Task 4: 5 Dosyalık OTEL_KISA-Sadece Toplu Migrasyon

**Files:**
- Modify: `mal-kabul-izleme.html`, `mal-kabul-lnexport.html`, `mal-kabul-siparistakip.html`, `mal-kabul-skt.html`, `muhasebe-butce.html`

**Interfaces:**
- Consumes: Task 1'in `OTEL_KISA`.

Bu 5 dosya SADECE `OTEL_KISA` tanımlıyor (OTEL_ISIMLERI yok) — birebir aynı mekanik değişiklik, bu yüzden tek task'ta birleştirildi.

- [ ] **Step 1: Her dosyada aynı 2 değişikliği yap**

Her dosya için: `Grep "supabase-config.js"` ile bul, hemen altına `<script src="otel-config.js"></script>` ekle. Sonra `Grep "OTEL_KISA="` ile bul, `const OTEL_KISA={'810':'Club','811':'Resort'};` satırını SİL.

Bunu şu 5 dosyanın HER BİRİNDE tekrarla: `mal-kabul-izleme.html`, `mal-kabul-lnexport.html`, `mal-kabul-siparistakip.html`, `mal-kabul-skt.html`, `muhasebe-butce.html`.

- [ ] **Step 2: Statik doğrulama**

```bash
grep -c "OTEL_KISA=" mal-kabul-izleme.html mal-kabul-lnexport.html mal-kabul-siparistakip.html mal-kabul-skt.html muhasebe-butce.html
```

Her dosya için `0` dönmeli. `grep -c "otel-config.js" <aynı-5-dosya>` her biri için `1` dönmeli.

- [ ] **Step 3: Commit**

```bash
git add mal-kabul-izleme.html mal-kabul-lnexport.html mal-kabul-siparistakip.html mal-kabul-skt.html muhasebe-butce.html
git -c user.name="mehmetaraz0" -c user.email="mehmetaraz868@gmail.com" commit -m "refactor: 5 dosya (mal-kabul-izleme/lnexport/siparistakip/skt, muhasebe-butce) otel-config.js'e geçirildi"
```

---

## Task 5: `muhasebe-cek-senet.html` Migrasyonu

**Files:**
- Modify: `muhasebe-cek-senet.html`

**Interfaces:**
- Consumes: Task 1'in `OTEL_ISIMLERI`, `OTEL_KISA`.

- [ ] **Step 1: Script include ekle**

`Grep "supabase-config.js"` ile bul, hemen altına `<script src="otel-config.js"></script>` ekle.

- [ ] **Step 2: Yerel tanımları sil**

`Grep "OTEL_ISIMLERI="` ve `Grep "OTEL_KISA="` ile bul, ikisini de sil.

- [ ] **Step 3: Statik doğrulama**

`grep -c "OTEL_ISIMLERI=\|OTEL_KISA=" muhasebe-cek-senet.html` → `0`.

- [ ] **Step 4: Commit**

```bash
git add muhasebe-cek-senet.html
git -c user.name="mehmetaraz0" -c user.email="mehmetaraz868@gmail.com" commit -m "refactor: muhasebe-cek-senet.html otel-config.js'e geçirildi"
```

---

## Task 6: `muhasebe-demirbas.html` Migrasyonu

**Files:**
- Modify: `muhasebe-demirbas.html`

**Interfaces:**
- Consumes: Task 1'in `OTEL_ISIMLERI`, `OTEL_KISA`.

- [ ] **Step 1: Script include ekle**

`Grep "supabase-config.js"` ile bul, hemen altına `<script src="otel-config.js"></script>` ekle.

- [ ] **Step 2: Yerel tanımları sil**

`Grep "OTEL_ISIMLERI="` ve `Grep "OTEL_KISA="` ile bul, ikisini de sil.

- [ ] **Step 3: Statik doğrulama**

`grep -c "OTEL_ISIMLERI=\|OTEL_KISA=" muhasebe-demirbas.html` → `0`.

- [ ] **Step 4: Commit**

```bash
git add muhasebe-demirbas.html
git -c user.name="mehmetaraz0" -c user.email="mehmetaraz868@gmail.com" commit -m "refactor: muhasebe-demirbas.html otel-config.js'e geçirildi"
```

---

## Task 7: `muhasebe-edefter.html` Migrasyonu

**Files:**
- Modify: `muhasebe-edefter.html`

**Interfaces:**
- Consumes: Task 1'in `OTEL_ISIMLERI`.

**Dikkat:** Bu dosya `OTEL_KISA` tanımlamıyor, sadece `OTEL_ISIMLERI`. Ayrıca `Object.keys(OTEL_ISIMLERI)` deseniyle EN AZ 4 farklı yerde döngü/select doldurma için kullanılıyor — bu kullanımlar DEĞİŞMEDEN kalmalı (merkezi `OTEL_ISIMLERI` de aynı 2 anahtara — `'810'`/`'811'` — sahip olduğu için `Object.keys(...)` çağrıları sorunsuz çalışmaya devam eder).

- [ ] **Step 1: Script include ekle**

`Grep "supabase-config.js"` ile bul, hemen altına `<script src="otel-config.js"></script>` ekle.

- [ ] **Step 2: Yerel tanımı sil**

`Grep "OTEL_ISIMLERI="` ile bul, `const OTEL_ISIMLERI=...` satırını SİL. `Object.keys(OTEL_ISIMLERI)` geçen 4 satıra DOKUNMA (onlar artık merkezi tanımı kullanacak).

- [ ] **Step 3: Statik doğrulama**

```bash
grep -c "OTEL_ISIMLERI=" muhasebe-edefter.html
```
`0` dönmeli (tanım silindi). Ayrıca:
```bash
grep -c "Object.keys(OTEL_ISIMLERI)" muhasebe-edefter.html
```
`4` (veya implementasyon anındaki gerçek sayı — en az 1) dönmeli, bu kullanımların KORUNDUĞUNU doğrular.

- [ ] **Step 4: Commit**

```bash
git add muhasebe-edefter.html
git -c user.name="mehmetaraz0" -c user.email="mehmetaraz868@gmail.com" commit -m "refactor: muhasebe-edefter.html otel-config.js'e geçirildi"
```

---

## Task 8: `muhasebe-faturalar.html` Migrasyonu

**Files:**
- Modify: `muhasebe-faturalar.html`

**Interfaces:**
- Consumes: Task 1'in `OTEL_ISIMLERI`, `OTEL_KISA`.

- [ ] **Step 1: Script include ekle**

`Grep "supabase-config.js"` ile bul, hemen altına `<script src="otel-config.js"></script>` ekle.

- [ ] **Step 2: Yerel tanımları sil**

`Grep "OTEL_ISIMLERI="` ve `Grep "OTEL_KISA="` ile bul, ikisini de sil.

- [ ] **Step 3: Statik doğrulama**

`grep -c "OTEL_ISIMLERI=\|OTEL_KISA=" muhasebe-faturalar.html` → `0`.

- [ ] **Step 4: Commit**

```bash
git add muhasebe-faturalar.html
git -c user.name="mehmetaraz0" -c user.email="mehmetaraz868@gmail.com" commit -m "refactor: muhasebe-faturalar.html otel-config.js'e geçirildi"
```

---

## Task 9: `kullanici-yonetimi.html` Migrasyonu (Bug Düzeltmesi Dahil)

**Files:**
- Modify: `kullanici-yonetimi.html`

**Interfaces:**
- Consumes: Task 1'in `OTEL_ISIMLERI`.

**ÖNEMLİ:** Bu dosyadaki mevcut `OTEL_ISIMLERI` değeri YANLIŞ/eksik: `{'810':'Club Manavgat','811':'Resort Sorgun'}` — diğer 6 dosyadaki doğru değerden ("Ali Bey" ön eki) farklı. Bu task, dosyayı merkezi (DOĞRU) tanıma geçirerek bu bilinen bug'ı düzeltiyor. Bu BİLİNÇLİ bir davranış değişikliği — implementer bunu bir "hata" sanıp geri almasın.

- [ ] **Step 1: Script include ekle**

`Grep "supabase-config.js"` ile bul, hemen altına `<script src="otel-config.js"></script>` ekle.

- [ ] **Step 2: Yerel (yanlış) tanımı sil**

`Grep "OTEL_ISIMLERI="` ile bul (değeri `{'810':'Club Manavgat','811':'Resort Sorgun'}` olmalı — bu, doğru değer OLMAYAN, düzeltilecek satır). Satırı TAMAMEN sil.

- [ ] **Step 3: Statik doğrulama**

`grep -c "OTEL_ISIMLERI=" kullanici-yonetimi.html` → `0`. Ayrıca `grep -n "Club Manavgat'\|Resort Sorgun'" kullanici-yonetimi.html` çalıştırıp "Ali Bey" ön eki OLMADAN bu string'lerin dosyada artık HİÇ geçmediğini doğrula (yanlış kopyanın tamamen silindiğinin kanıtı).

- [ ] **Step 4: Tarayıcıda manuel doğrula**

`kullanici-yonetimi.html`'i aç, kullanıcı listesinde otel adının artık "Ali Bey Club Manavgat" / "Ali Bey Resort Sorgun" (tam, doğru biçimde) göründüğünü kontrol et — önceden eksik/yanlış görünüyordu.

- [ ] **Step 5: Commit**

```bash
git add kullanici-yonetimi.html
git -c user.name="mehmetaraz0" -c user.email="mehmetaraz868@gmail.com" commit -m "fix: kullanici-yonetimi.html'deki yanlış otel adı sözlüğü otel-config.js ile düzeltildi"
```

---

## Task 10: `depo-siparis.html` Migrasyonu (Fonksiyon Konsolidasyonu)

**Files:**
- Modify: `depo-siparis.html`

**Interfaces:**
- Consumes: Task 1'in `merkeziDepoKodu(otelId)`.

**ÖNEMLİ:** Bu dosya `merkeziDepoKodu` adında YEREL BİR FONKSİYON tanımlıyor (`function merkeziDepoKodu(otelId){return otelId==='811'?'300':'100';}`) — bu, Task 1'de merkezi dosyaya eklenen fonksiyonla AYNI İSİMDE. Bu yerel fonksiyon SİLİNMELİ (merkezi olan aynı isimle, aynı davranışla zaten kullanılabilir olacak — dosyanın geri kalanındaki `merkeziDepoKodu(...)` çağrıları hiç değişmeden merkezi fonksiyonu kullanmaya devam eder).

- [ ] **Step 1: Script include ekle**

`Grep "supabase-config.js"` ile bul, hemen altına `<script src="otel-config.js"></script>` ekle.

- [ ] **Step 2: Yerel fonksiyon tanımını sil**

`Grep "function merkeziDepoKodu"` ile bul, TÜM fonksiyon gövdesini (`function merkeziDepoKodu(otelId){return otelId==='811'?'300':'100';}` — tek satırlık bir fonksiyon) sil. Dosyadaki `merkeziDepoKodu(...)` ÇAĞRILARINA dokunma — onlar artık merkezi tanımı kullanacak.

- [ ] **Step 3: Statik doğrulama**

```bash
grep -c "function merkeziDepoKodu" depo-siparis.html
```
`0` dönmeli (yerel tanım silindi).
```bash
grep -c "merkeziDepoKodu(" depo-siparis.html
```
`0`'dan BÜYÜK olmalı (çağrılar hâlâ var, sadece tanım merkezi dosyaya taşındı).

- [ ] **Step 4: Commit**

```bash
git add depo-siparis.html
git -c user.name="mehmetaraz0" -c user.email="mehmetaraz868@gmail.com" commit -m "refactor: depo-siparis.html'deki yerel merkeziDepoKodu() tanımı otel-config.js'e taşındı"
```

---

## Task 11: `stok-takip.html` Migrasyonu

**Files:**
- Modify: `stok-takip.html`

**Interfaces:**
- Consumes: Task 1'in `merkeziDepoKodu(otelId)`.

Bu dosya `merkeziDepoKodu` ve `bareDepoKodu` adlı İKİ AYRI yerde `otelId==='811'?'300':'100'` ternary'sini kullanıyor (fonksiyon tanımı DEĞİL, doğrudan değişkene atama).

- [ ] **Step 1: Script include ekle**

`Grep "supabase-config.js"` ile bul, hemen altına `<script src="otel-config.js"></script>` ekle. (Not: bu dosyada `ortak-excel.js` ve `gurok_veritabani.js` de yükleniyor — `otel-config.js`'i `supabase-config.js`'den hemen sonra, diğer script'lerden ÖNCE ekle.)

- [ ] **Step 2: İki ternary'yi de çevir**

`Grep "otelId==='811'?'300':'100'"` ile TÜM eşleşmeleri bul (en az 2 tane — biri `merkeziDepoKodu` değişkenine, biri `bareDepoKodu` değişkenine atanıyor).

**DİKKAT — isim çakışması riski:** Bu dosyada YEREL DEĞİŞKEN adı da `merkeziDepoKodu` — bu, Task 1'deki GLOBAL FONKSİYON adıyla AYNI. Bu satırı şu şekilde çevir (global fonksiyonu `window.merkeziDepoKodu` üzerinden çağır, adı gölgeleyen yerel `const` ile çakışmasın):

```js
// Eski: const merkeziDepoKodu=otelId==='811'?'300':'100';
// Yeni:
const merkeziDepoKodu=(window.merkeziDepoKodu||function(o){return o==='811'?'300':'100';})(otelId);
```

İkinci eşleşme (`bareDepoKodu` değişkenine atanan) için AYNI değişim, sadece değişken adı farklı olduğu için (yerel-global isim çakışması YOK) daha basit:

```js
// Eski: const bareDepoKodu=otelId==='811'?'300':'100';
// Yeni:
const bareDepoKodu=merkeziDepoKodu(otelId);
```

(Not: eğer implementasyon anında `merkeziDepoKodu` yerel değişkeni artık tanımlı değilse — yani Step 2'nin ilk kısmı bu ikinci kullanımdan ÖNCE bir yerdeyse — bu çağrı doğrudan global fonksiyonu kullanır, sorun yok.)

- [ ] **Step 3: Statik doğrulama**

```bash
grep -c "otelId==='811'?'300':'100'" stok-takip.html
```
Sadece Step 2'deki fallback ifadelerinin İÇİNDE (yeni kodun kendisi) kalmalı — implementer gerçek sayıyı kendi yaptığı değişikliğe göre yorumlamalı, sıfır olması ZORUNLU değil (fallback olarak bilinçli bırakıldı), ama YENİ bir bağımsız ternary eklenmediğinden emin ol.

- [ ] **Step 4: Tarayıcı konsolunda syntax hatası olmadığını doğrula**

Bu ortamda tarayıcı testi yapılamıyorsa, dosyanın parantez/süslü parantez dengesini statik olarak kontrol et ve raporda belirt.

- [ ] **Step 5: Commit**

```bash
git add stok-takip.html
git -c user.name="mehmetaraz0" -c user.email="mehmetaraz868@gmail.com" commit -m "refactor: stok-takip.html otel-config.js'e geçirildi"
```

---

## Task 12: `satin-alma-iade.html` Migrasyonu

**Files:**
- Modify: `satin-alma-iade.html`

**Interfaces:**
- Consumes: Task 1'in `OTEL_TICARI_UNVAN`.

- [ ] **Step 1: Script include ekle**

`Grep "supabase-config.js"` ile bul, hemen altına `<script src="otel-config.js"></script>` ekle.

- [ ] **Step 2: Ticari unvan ternary'sini çevir**

`Grep "GUROK TUR MAD"` ile bul (kalıp: `const otelAd=s.otelId==='811'?'GUROK TUR MAD.A.S. (RESORT SORGUN)':'GUROK TUR MAD.A.S. (CLUB MANAVGAT)';`):

```js
// Eski: const otelAd=s.otelId==='811'?'GUROK TUR MAD.A.S. (RESORT SORGUN)':'GUROK TUR MAD.A.S. (CLUB MANAVGAT)';
// Yeni:
const otelAd=OTEL_TICARI_UNVAN[s.otelId]||OTEL_TICARI_UNVAN['810'];
```

- [ ] **Step 3: Statik doğrulama**

`grep -c "GUROK TUR MAD" satin-alma-iade.html` → `0` dönmeli (artık merkezi dosyada).

- [ ] **Step 4: Commit**

```bash
git add satin-alma-iade.html
git -c user.name="mehmetaraz0" -c user.email="mehmetaraz868@gmail.com" commit -m "refactor: satin-alma-iade.html otel-config.js'e geçirildi"
```

---

## Task 13: `index.html` Migrasyonu

**Files:**
- Modify: `index.html`

**Interfaces:**
- Consumes: Task 1'in `DAHILI_EMAIL_DOMAIN`.

**ÖNEMLİ:** `index.html` diğer sayfalardan FARKLI bir script sırasına sahip — `ortak.js` kullanmıyor, sadece `auth-guard.js` → `supabase-config.js` → (doğrudan inline script). `otel-config.js`'i `supabase-config.js`'den hemen sonra ekle.

- [ ] **Step 1: Script include ekle**

`Grep "supabase-config.js"` ile bul, hemen altına `<script src="otel-config.js"></script>` ekle.

- [ ] **Step 2: E-posta domainini çevir**

`Grep "gurok.internal"` ile bul (kalıp: `const email = user.id + '@gurok.internal';`):

```js
// Eski: const email = user.id + '@gurok.internal';
// Yeni:
const email = user.id + '@' + DAHILI_EMAIL_DOMAIN;
```

- [ ] **Step 3: Statik doğrulama**

`grep -c "'@gurok.internal'" index.html` → `0` dönmeli (artık `DAHILI_EMAIL_DOMAIN` değişkeni kullanılıyor, ham string kalmamalı).

- [ ] **Step 4: Commit**

```bash
git add index.html
git -c user.name="mehmetaraz0" -c user.email="mehmetaraz868@gmail.com" commit -m "refactor: index.html otel-config.js'e geçirildi"
```

---

## Task 14: Uçtan Uca Doğrulama

**Files:**
- Modify: `.superpowers/sdd/progress.md`

**Interfaces:**
- Consumes: Task 1-13'ün tüm çıktıları.

- [ ] **Step 1: Repo genelinde sıfır-kalan-kopya kontrolü**

```bash
cd "C:\Users\USER\Projects\gurok-mal-kabul"
grep -rln "OTEL_ISIMLERI=\|OTEL_KISA=" --include="*.html" . | grep -v "otel-config.js"
```

Beklenen: BOŞ (hiçbir dosyada yerel tanım kalmamalı).

```bash
grep -c "OTEL_ISIMLERI\|OTEL_KISA\|MERKEZI_DEPO\|merkeziDepoKodu\|OTEL_TICARI_UNVAN\|DAHILI_EMAIL_DOMAIN" otel-config.js
```

Beklenen: `0`'dan büyük (tanımların merkezi dosyada gerçekten var olduğunu doğrular).

- [ ] **Step 2: Script include kontrolü — 16 dosyanın hepsinde otel-config.js var mı**

```bash
grep -L "otel-config.js" mal-kabul-liste.html mal-kabul-uygunsuzluk.html mal-kabul-izleme.html mal-kabul-lnexport.html mal-kabul-siparistakip.html mal-kabul-skt.html muhasebe-cek-senet.html muhasebe-demirbas.html muhasebe-edefter.html muhasebe-faturalar.html muhasebe-butce.html kullanici-yonetimi.html depo-siparis.html stok-takip.html satin-alma-iade.html index.html
```

Beklenen: BOŞ çıktı (`-L` = eşleşmeyen dosyaları listeler; boş çıktı = hepsinde `otel-config.js` var).

- [ ] **Step 3: Kullanıcıdan tarayıcıda manuel test iste**

Kullanıcıya şunu iste: en az 3 farklı sayfada (örn. `stok-takip.html`, `muhasebe-faturalar.html`, `kullanici-yonetimi.html`) otel adının/kısa adının doğru göründüğünü, `mal-kabul-liste.html`'de mal kabul akışının (özellikle depo kodu türetmenin) bozulmadığını, `depo-siparis.html`'de sipariş akışının çalıştığını, `satin-alma-iade.html`'de iade faturası ticari unvanının doğru göründüğünü doğrula. Özellikle `kullanici-yonetimi.html`'de artık "Ali Bey Club Manavgat"/"Ali Bey Resort Sorgun" (tam biçimde) göründüğünü teyit et — bu, düzeltilen bug'ın kanıtı.

- [ ] **Step 4: `git fetch origin` ile paralel oturum kontrolü**

```bash
cd "C:\Users\USER\Projects\gurok-mal-kabul"
git fetch origin
git rev-list --left-right --count HEAD...origin/main
```

İlerlemişse `git diff --name-only $(git merge-base HEAD origin/main) origin/main` ile kontrol et, `git merge origin/main` ile birleştir, merge sonrası Step 1-2'yi TEKRAR çalıştır (16 dosyanın hiçbiri çakışmaya bağlı olarak eski hâline dönmediğini doğrulamak için).

- [ ] **Step 5: İlerleme kaydı ve push**

`.superpowers/sdd/progress.md` sonuna ekle:

```
Config Merkezileştirme Task 14 (uçtan uca doğrulama): complete — 16 dosyanın hepsinde otel-config.js include doğrulandı, repo genelinde sıfır kalan OTEL_ISIMLERI/OTEL_KISA kopyası kaldı. kullanici-yonetimi.html'deki bilinen bug (yanlış otel adı) düzeltildi. Kullanıcı tarayıcıda manuel test onayladı.
Config Değerlerinin Merkezileştirilmesi: TAMAMLANDI. otel-config.js oluşturuldu, 16 dosya migrasyonu tamamlandı. Satış stratejisi punch list'inin 3. maddesi bitti — sırada madde 4 (tekrarlanabilir müşteri kurulum süreci) var.
```

```bash
git push origin main
```

---

## Self-Review Notu

- **Spec kapsaması:** Spec'in tüm maddeleri (a: isim/unvan sözlükleri, b: depo kodu türetme, c: ticari unvan, d: e-posta domaini) Task 1-13'e dağıtıldı. `gurok_veritabani.js` bilinçli olarak hiçbir task'a dahil edilmedi (spec kapsam dışı bıraktı).
- **Placeholder taraması:** Yok — her task'ta tam kod/grep komutu var. Task 11'deki isim-çakışması senaryosu istisna görünebilir ama MEKANİK bir kural (window.* üzerinden çağırma) olarak tam yazıldı, belirsizlik yok.
- **Tip/isim tutarlılığı:** `OTEL_ISIMLERI`, `OTEL_KISA`, `OTEL_TICARI_UNVAN`, `MERKEZI_DEPO`, `merkeziDepoKodu()`, `otelFromDepoId()`, `DAHILI_EMAIL_DOMAIN` — Task 1'de tanımlanan isimler Task 2-13'ün hepsinde birebir aynı kullanılıyor.
- **Dosya sayısı doğrulama:** Spec'teki araştırmada "27 dosya" denmişti (ham `810`/`811` string arama sonucu) ama bu plan yazılırken yapılan hassas grep taraması sadece **16 dosyada** GERÇEK YEREL TANIM/TEKRAR olduğunu gösterdi (kalan ~11 dosyadaki `810`/`811` geçişleri muhtemelen sadece `otelId==='811'` gibi normal karşılaştırmalar, KOPYALANMIŞ bir sabit/sözlük tanımı değil — bu plan sadece GERÇEK TEKRAR eden tanımları hedefliyor, her `810`/`811` referansını "config" saymak kapsam dışı taşması olurdu).
