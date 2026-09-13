# Kat Hizmetleri Otel Seçici — Uygulama Planı

> **Ajan çalışanlar için:** Bu plan görev görev uygulanır. Adımlar onay kutusu (`- [ ]`) biçimindedir.

**Amaç:** Çapraz otel yetkisi olan (`tum_oteller = true`, `otel_id` boş) kullanıcı kat hizmetleri ekranını kullanabilsin; otelini ekranın başlığından seçsin.

**Mimari:** Ekrandaki sabit `TEK_OTEL` değişkeni, seçiciyle değişebilen `AKTIF_OTEL` hâline gelir. Çapraz otel hakkı ön yüzde saklanmadığı için sunucudan `auth_tum_oteller()` RPC'siyle **fail-closed** okunur. Seçim yalnız tarayıcıda (`localStorage`) durur; hiçbir kullanıcı kaydı ve hiçbir şema değişmez.

**Teknoloji:** Statik HTML/JS + Supabase (PostgREST RPC). Birim test çerçevesi yoktur; doğrulama `scripts/yerel-staging.mjs` ile ayağa kalkan yerel izole ortamda gerçek tarayıcıyla ve `node scripts/check.mjs` ile yapılır.

**Spec:** `docs/superpowers/specs/2026-09-13-kat-hizmetleri-otel-secici-design.md`

## Global Constraints

- **Migration YOK.** Hiçbir SQL dosyası üretime uygulanmaz; `kullanicilar_genel` görünümü değişmez.
- **Fail-closed:** `auth_tum_oteller()` hata verirse sonuç `false` sayılır ve ekran bugünkü "Otel seçili değil" davranışına düşer.
- Otel kodları **yalnız** `otel-config.js` içindeki `OTEL_KISA` anahtarlarından gelir (`810`, `811`). Kod içine otel kodu gömülmez.
- Saklama anahtarı: `hk-otel:<kullanici_id>`. Geçersiz değer okunursa yok sayılır ve listedeki **ilk** otel kullanılır.
- `localStorage` erişimi her zaman `try/catch` içinde olur (özel pencere / depolama kapalı).
- Otel atamalı kullanıcının (`CU.otelId` dolu) davranışı **hiç değişmez**: seçici yok, rozet aynı.
- Uçuşta komut varken (`UCUSTA === true`) otel değiştirilemez.
- Türkçe kullanıcı metinleri mevcut ekranın üslubunu korur.
- Üretime yayın ayrı bir **`CANLIYA UYGULA`** onayına bağlıdır; plan bittiğinde push edilmez.

---

## Dosya yapısı

| Dosya | Sorumluluk | Değişiklik |
|---|---|---|
| `pms-housekeeping.html` | Ekranın durumu, başlık, kuyruk çizimi | `TEK_OTEL` → `AKTIF_OTEL`; seçici, hatırlama, sıfırlama, `#otel=` |
| `pms-oda-plani.html` | Oda planı; kat hizmetlerine derin bağlantı | `katHizmetleriAc()` bağlantıya `otel` ekler |
| `scripts/yerel-staging.mjs` | Yerel QA geçidi (PIN → kullanıcı) | Yeni QA kullanıcısı için PIN kaydı |
| `scripts/yerel-staging-housekeeping.sql` | Yerel QA verisi | `tum_oteller = true` kullanıcı |

Üretim SQL dosyalarına dokunulmaz.

---

### Task 1: Yerel QA ortamında hatayı üretilebilir hâle getir

Bugün `tum_oteller = true` olan bir QA kullanıcısı yok; hata yerelde gösterilemiyor. Önce onu ekliyoruz — düzeltmeden **önce** hatayı görmek için.

**Files:**
- Modify: `scripts/yerel-staging-housekeeping.sql` (dosya sonuna ekleme)
- Modify: `scripts/yerel-staging.mjs:53-61` (PIN haritası)

**Interfaces:**
- Produces: PIN `888888` → `QA Tüm Oteller` kullanıcısı (`otel_id` NULL, `tum_oteller` true, `pms_housekeeping` yetkisi `tam`). Task 2 ve Task 4 bu kullanıcıyla doğrulama yapar.

- [ ] **Step 1: QA kullanıcısını ekle**

`scripts/yerel-staging-housekeeping.sql` dosyasının **sonuna** ekleyin:

```sql
-- ---------------------------------------------------------------------------
-- ÇAPRAZ OTEL KULLANICISI — otel seçici QA'sı için.
-- otel_id BOŞ, tum_oteller TRUE: ekranın otel seçmesi gereken durum budur.
-- ---------------------------------------------------------------------------
insert into auth.users (id) values ('a0000000-0000-0000-0000-0000000000a8')
  on conflict (id) do nothing;

insert into public.kullanicilar (id, auth_user_id, rol, rol_id, otel_id, aktif, tum_oteller, ad) values
  ('a0000000-0000-0000-0000-0000000000a8', 'a0000000-0000-0000-0000-0000000000a8',
   'yonetici', 'b0000000-0000-0000-0000-0000000000a7', null, true, true, 'QA Tüm Oteller')
  on conflict (id) do nothing;
```

`b0000000-…a7` rolü, aynı dosyada `pms_housekeeping` için `tam` yetkisi verilen QA rolüdür (bkz. `QA Kat Sefi` kaydı).

- [ ] **Step 2: PIN'i tanıt**

`scripts/yerel-staging.mjs` içindeki `PINLER` haritasına son satır olarak ekleyin:

```js
  '888888': 'a0000000-0000-0000-0000-0000000000a8',  // QA Tum Oteller (otel_id YOK, tum_oteller)
```

- [ ] **Step 3: Ortamı ayağa kaldır**

```bash
node scripts/yerel-staging.mjs
```

Beklenen: kurulum hatasız biter ve `http://127.0.0.1:8791` adresini yazar.

- [ ] **Step 4: Hatayı gör (düzeltmeden önceki durum)**

Tarayıcıda `http://127.0.0.1:8791` → PIN `888888` ile gir → Kat Hizmetleri ekranını aç.

Beklenen (bugünkü hatalı davranış): başlıkta **"🏨 Otel seçili değil"**, sarı uyarı kutusu, hiçbir komut düğmesi yok, dört sekme de boş. Bu görülmeden Task 2'ye geçilmez.

- [ ] **Step 5: Commit**

```bash
git add scripts/yerel-staging-housekeeping.sql scripts/yerel-staging.mjs
git commit -m "test(pms): yerel QA'ya capraz otel kullanicisi ekle"
```

---

### Task 2: Kat hizmetleri ekranına otel seçici

**Files:**
- Modify: `pms-housekeeping.html:224` (durum değişkenleri), `:238-244` (init), `:246-262` (baslat), `:276`, `:324`, `:339`, `:633` (`TEK_OTEL` kullanımları)

**Interfaces:**
- Consumes: Task 1'in PIN `888888` kullanıcısı; `hkRpc(ad, govde)` (global, `pms-housekeeping.js`), `OTEL_KISA` (global, `otel-config.js`), `escapeHtml` (global), mevcut `UCUSTA`, `GOREVLER`, `CALISAN`, `ODA_SECENEK`, `pollBasla()`, `pollDurdur()`, `calisanlariYukle()`, `tazele(elle)`.
- Produces: `AKTIF_OTEL` (string|null) — kat hizmetleri RPC'lerine giden otel kapsamı; `SECILEBILIR` (boolean); `otelBasligiCiz()`; `otelDegistir(ev)`.

- [ ] **Step 1: Durum değişkenlerini değiştir**

`pms-housekeeping.html` satır 224'teki tek satırı:

```js
const TEK_OTEL = CU && CU.otelId ? String(CU.otelId) : null;
```

şununla değiştirin:

```js
// OTEL KAPSAMI. Atanmış oteli olan kullanıcı ona KİLİTLİDİR. Ataması olmayan
// kullanıcı, çapraz otel yetkisi VARSA (auth_tum_oteller) otelini seçer.
// Seçim yalnız tarayıcıda durur; kullanıcı kaydı DEĞİŞMEZ.
const SABIT_OTEL = CU && CU.otelId ? String(CU.otelId) : null;
const OTEL_KODLARI = Object.keys(OTEL_KISA);
const OTEL_ANAHTARI = CU && CU.id ? ('hk-otel:' + CU.id) : null;
let AKTIF_OTEL = SABIT_OTEL;   // RPC'lere giden otel
let SECILEBILIR = false;       // seçici gösterilecek mi
```

- [ ] **Step 2: Otel yardımcılarını ekle**

Aynı dosyada, `let POLL = null;` satırından **sonra**, `(function init(){` bloğundan **önce** ekleyin:

```js
function otelGecerli(k){ return !!k && OTEL_KODLARI.indexOf(String(k)) >= 0; }

// localStorage özel pencerede ya da depolama kapalıyken PATLAR; okumak da
// yazmak da try/catch içindedir ve hata sessizce yok sayılır.
function otelHatirla(){
  if(!OTEL_ANAHTARI) return null;
  try{
    const v = localStorage.getItem(OTEL_ANAHTARI);
    return otelGecerli(v) ? String(v) : null;
  }catch(e){ return null; }
}
function otelSakla(kod){
  if(!OTEL_ANAHTARI) return;
  try{ localStorage.setItem(OTEL_ANAHTARI, String(kod)); }catch(e){}
}

// Oda planından gelen derin bağlantı: #otel=811&oda=101
function otelBaglantidan(){
  const m = String(location.hash || '').match(/[#&]otel=([^&]+)/);
  let k = null;
  try{ k = m ? decodeURIComponent(m[1]) : null; }catch(e){ k = null; }
  return otelGecerli(k) ? String(k) : null;
}

function otelBasligiCiz(){
  const h = document.getElementById('hdrOtel');
  if(!SECILEBILIR){
    h.textContent = AKTIF_OTEL
      ? ('🏨 ' + (OTEL_KISA[AKTIF_OTEL] || AKTIF_OTEL))
      : '🏨 Otel seçili değil';
    return;
  }
  h.innerHTML = '🏨 <select id="otelSec" aria-label="Otel seçin" '
    + 'style="font:inherit;color:inherit;background:transparent;border:0;'
    + 'border-bottom:1px dotted currentColor;padding:0 2px;cursor:pointer">'
    + OTEL_KODLARI.map(function(k){
        return '<option value="' + escapeHtml(k) + '"'
          + (k === AKTIF_OTEL ? ' selected' : '') + '>'
          + escapeHtml(OTEL_KISA[k] || k) + '</option>';
      }).join('')
    + '</select>';
  document.getElementById('otelSec').addEventListener('change', otelDegistir);
}

// Otel değişince EKRANIN TAMAMI sıfırlanır: kuyruk, çalışan haritası ve oda
// seçici otel kapsamlıdır; eskisinden satır sızarsa kullanıcı yanlış otelin
// verisine bakar.
async function otelDegistir(ev){
  const yeni = String(ev.target.value || '');
  if(!otelGecerli(yeni) || yeni === AKTIF_OTEL) return;
  if(UCUSTA){ ev.target.value = AKTIF_OTEL; return; }  // uçuşta komut varken kilitli
  pollDurdur();
  AKTIF_OTEL = yeni;
  otelSakla(yeni);
  GOREVLER = [];
  CALISAN = new Map();
  ODA_SECENEK = [];
  await calisanlariYukle();
  await tazele(false);
  pollBasla();
}
```

- [ ] **Step 3: init'i seçiciyle uyumlu hâle getir**

`(function init(){ … })();` içindeki iki satırı:

```js
  document.getElementById('hdrOtel').textContent =
    TEK_OTEL ? ('🏨 ' + (OTEL_KISA[TEK_OTEL] || TEK_OTEL)) : '🏨 Otel seçili değil';
```

şununla değiştirin:

```js
  otelBasligiCiz();
```

- [ ] **Step 4: `baslat()` içinde otel hakkını sunucudan oku**

`baslat()` fonksiyonundaki şu bloğu:

```js
  if(!TEK_OTEL){
    uyariGoster(['Otel seçili değil — kat hizmetleri otel kapsamında çalışır.']);
    return;
  }
```

şununla değiştirin:

```js
  // Çapraz otel hakkı ön yüzde YOKTUR (kullanicilar_genel görünümünde
  // tum_oteller alanı yok). Sunucuya sorulur ve HATA DURUMUNDA 'yok' sayılır.
  if(!SABIT_OTEL){
    try{ SECILEBILIR = (await hkRpc('auth_tum_oteller', {})) === true; }
    catch(e){ SECILEBILIR = false; }
    if(SECILEBILIR){
      AKTIF_OTEL = otelBaglantidan() || otelHatirla() || OTEL_KODLARI[0];
      otelSakla(AKTIF_OTEL);
    }
    otelBasligiCiz();
  }

  if(!AKTIF_OTEL){
    uyariGoster(['Otel seçili değil — kat hizmetleri otel kapsamında çalışır.']);
    return;
  }
```

- [ ] **Step 5: Kalan dört `TEK_OTEL` kullanımını değiştir**

Şu dört satırda `TEK_OTEL` yerine `AKTIF_OTEL` yazın (satır numaraları Step 1–4'ten sonra kayar; arama ile bulun):

```js
    const liste = await HK.calisanlar(TEK_OTEL);                       // calisanlariYukle
    if(!TEK_OTEL || YETKI === 'yok') return;                           // tazele
    const satirlar = await HK.listele(TEK_OTEL, SEKME_KUYRUK[SEKME], 100);  // tazele
      const satirlar = await HK.odalar(TEK_OTEL, 500);                 // oda seçici
```

- [ ] **Step 6: Hiç `TEK_OTEL` kalmadığını doğrula**

```bash
grep -n "TEK_OTEL" pms-housekeeping.html
```

Beklenen: **hiç çıktı yok** (çıkış kodu 1).

- [ ] **Step 7: Statik kontrol**

```bash
node scripts/check.mjs
```

Beklenen: "Tüm statik kontroller geçti."

- [ ] **Step 8: Çapraz otel kullanıcısıyla doğrula**

Ortam açık değilse `node scripts/yerel-staging.mjs`. Tarayıcıda PIN `888888` → Kat Hizmetleri.

Beklenen:
1. Başlıkta **açılır liste** var ve **Club** seçili (`OTEL_KODLARI[0]` = `810`).
2. Uyarı kutusu **yok**; sekmeler doluyor; `tam` yetkili olduğu için **"+ Görev aç"** düğmesi görünüyor.
3. Listeden **Resort**'u seçin → kuyruk 811 otelinin görevleriyle yenilenir (yerel veride 811'de bir görev vardır), 810'un görevleri **kaybolur**.
4. "+ Görev aç" → oda seçici yalnız **811** odalarını gösterir.
5. Sayfayı yenileyin → **Resort** seçili gelir (hatırlama çalışıyor).

- [ ] **Step 9: Otel atamalı kullanıcıda hiçbir şeyin değişmediğini doğrula**

PIN `777777` (QA Kat Sefi, otel 810) ile girin.

Beklenen: başlıkta **açılır liste YOK**, düz "🏨 Club" rozeti; ekran bugünkü gibi çalışıyor.

- [ ] **Step 10: Fail-closed davranışını doğrula**

RPC'yi geçici olarak var olmayan bir ada çevirip hatayı gerçek yoldan üretin. `pms-housekeeping.html` içinde:

```js
    try{ SECILEBILIR = (await hkRpc('auth_tum_oteller', {})) === true; }
```

satırını geçici olarak şu hâle getirin, sayfayı PIN `888888` oturumunda yenileyin:

```js
    try{ SECILEBILIR = (await hkRpc('auth_tum_oteller_YOK', {})) === true; }
```

Beklenen: RPC 404 verir, `SECILEBILIR` **false** olur, seçici **çıkmaz** ve ekran "Otel seçili değil" uyarısına düşer — yani hata durumunda fazladan yetenek açılmaz.

Sonra satırı **eski hâline geri alın**, sayfayı yenileyin ve seçicinin döndüğünü görün. Bu adım hiçbir commit'e girmez; Step 11'den önce `git diff pms-housekeeping.html` çıktısında `auth_tum_oteller_YOK` **bulunmamalıdır**.

- [ ] **Step 11: Commit**

```bash
git add pms-housekeeping.html
git commit -m "feat(pms): kat hizmetleri ekranina otel secici"
```

---

### Task 3: Oda planından gelen bağlantı oteli taşısın

Oda planı iki oteli birden gösterir. Seçici geldikten sonra, Resort'taki bir odadan "Kat Hizmetlerinde Aç" denildiğinde ekranın Club kuyruğunda açılması gerçek bir yanlış yönlendirmedir.

**Files:**
- Modify: `pms-oda-plani.html:463-466` (`katHizmetleriAc`)

**Interfaces:**
- Consumes: Task 2'nin `otelBaglantidan()` okuması (`#otel=<kod>`).
- Produces: `#otel=<otel_id>&oda=<oda_no>` biçiminde bağlantı.

- [ ] **Step 1: Bağlantıya oteli ekle**

`katHizmetleriAc` fonksiyonunu:

```js
function katHizmetleriAc(odaId){
  const o = ODALAR.find(x=>x.id===odaId);
  location.href = 'pms-housekeeping.html' + (o ? '#oda=' + encodeURIComponent(o.oda_no) : '');
}
```

şununla değiştirin:

```js
function katHizmetleriAc(odaId){
  const o = ODALAR.find(x=>x.id===odaId);
  // Otel de taşınır: oda planı iki oteli birden gösterebilir, kat hizmetleri
  // ekranı ise TEK otele kilitlidir. Otel atamalı kullanıcıda yok sayılır.
  location.href = 'pms-housekeeping.html'
    + (o ? '#otel=' + encodeURIComponent(o.otel_id) + '&oda=' + encodeURIComponent(o.oda_no) : '');
}
```

- [ ] **Step 2: Statik kontrol**

```bash
node scripts/check.mjs
```

Beklenen: "Tüm statik kontroller geçti."

- [ ] **Step 3: Derin bağlantıyı doğrula**

PIN `888888` ile girin, Kat Hizmetleri ekranında **Club**'ı seçili bırakın. Oda Planı'na gidin → **811** otelindeki bir odanın kartında "Kat Hizmetlerinde Aç" düğmesine basın (kartta görev rozeti olmalı; yoksa 811 odasında bir görev oluşturun).

Beklenen: kat hizmetleri ekranı **Resort** seçili açılır; adres çubuğunda `#otel=811&oda=…` görünür.

- [ ] **Step 4: Otel atamalı kullanıcıda yok sayıldığını doğrula**

PIN `777777` (otel 810) ile aynı bağlantıyı elle açın: `http://127.0.0.1:8791/pms-housekeeping.html#otel=811&oda=101`.

Beklenen: ekran **Club**'da kalır, seçici yoktur, 811 verisi **görünmez**.

- [ ] **Step 5: Commit**

```bash
git add pms-oda-plani.html
git commit -m "fix(pms): oda plani baglantisi kat hizmetlerine oteli tasisin"
```

---

### Task 4: Kabul turu ve yayın kaydı

**Files:**
- Modify: `docs/kurulum/URETIM-YAYIN-RUNBOOK.md` (§8 açık maddesi)

**Interfaces:**
- Consumes: Task 1–3.

- [ ] **Step 1: Tam kabul turu**

Temiz ortamda tekrar: `node scripts/yerel-staging.mjs --durdur` sonra `node scripts/yerel-staging.mjs`.

Sırayla doğrulayın ve sonucu not edin:

| # | Kontrol | Beklenen |
|---|---|---|
| 1 | PIN `777777` (otel 810) | Seçici yok, rozet "Club", ekran çalışıyor |
| 2 | PIN `888888` (tüm oteller) | Seçici var, Club seçili, komut düğmeleri var |
| 3 | Resort'a geç | Kuyruk 811 verisiyle geliyor, 810 satırı kalmıyor |
| 4 | "+ Görev aç" | Oda seçici yalnız 811 odaları |
| 5 | Sayfayı yenile | Resort hatırlanıyor |
| 6 | `#otel=811` ile aç (PIN 888888) | Resort seçili açılıyor |
| 7 | `#otel=811` ile aç (PIN 777777) | Yok sayılıyor, Club kalıyor |
| 8 | PIN `555555` (kat hizmetleri yetkisi yok) | Kapalı ekran; seçici çıkmıyor |

- [ ] **Step 2: Statik kontrol ve kilit**

```bash
node scripts/check.mjs && node scripts/hazirlik-kilidi.mjs
```

Beklenen: statik kontroller geçti; hazırlık kilidi **11 dosya AYNI** (bu iş kilitli dosyalara dokunmaz).

- [ ] **Step 3: Runbook'taki açık maddeyi kapat**

`docs/kurulum/URETIM-YAYIN-RUNBOOK.md` §8 "Yayın sırasında öğrenilenler" 1. maddesinin sonundaki **Açık madde** cümlesinin ardına ekleyin:

```markdown
   **Çözüldü (2026-09-13):** ekrana otel seçici eklendi; çapraz otel hakkı
   `auth_tum_oteller()` ile sunucudan fail-closed okunuyor. Tasarım:
   `docs/superpowers/specs/2026-09-13-kat-hizmetleri-otel-secici-design.md`.
   Otel atamalı kullanıcının davranışı değişmedi.
```

- [ ] **Step 4: Commit**

```bash
git add docs/kurulum/URETIM-YAYIN-RUNBOOK.md
git commit -m "docs(pms): otel secici acik maddesini kapat"
```

- [ ] **Step 5: Yayın için DUR**

Push **yapılmaz**. Kullanıcıya şunlar sunulur: değişen dosyalar, kabul turu sonucu, `git log --oneline origin/main..HEAD`. Yayın ayrı bir **`CANLIYA UYGULA`** onayıyla `git push origin HEAD:main` ile yapılır; geri dönüş `git revert` + push.

---

## Plan öz denetimi

- **Spec kapsamı:** çapraz otel hakkının sunucudan okunması (T2/S4), karar tablosunun üç satırı (T2/S4, S8, S9, S10), saklama ve geçersiz değer (T2/S2), otel değişince sıfırlama sırası (T2/S2), uçuşta kilit (T2/S2), derin bağlantı (T3), hata durumları tablosu (T2/S10, T3/S4, T4/S1), test listesi (T4/S1), yayın kuralı (T4/S5). Karşılığı olmayan spec maddesi yok.
- **Yer tutucu taraması:** yok; her adımda çalıştırılacak komut ya da yapıştırılacak kod var.
- **Ad tutarlılığı:** `AKTIF_OTEL`, `SABIT_OTEL`, `SECILEBILIR`, `OTEL_KODLARI`, `OTEL_ANAHTARI`, `otelGecerli`, `otelHatirla`, `otelSakla`, `otelBaglantidan`, `otelBasligiCiz`, `otelDegistir` — tanımlandıkları Task 2 ile kullanıldıkları Task 3/4'te aynı yazılıyor.
