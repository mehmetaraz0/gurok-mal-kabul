# Modül Aç/Kapa Kataloğu Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Bir modülü `moduller` tablosunda pasif işaretlemek, kullanıcının rolü ne olursa olsun o modülü hem RLS seviyesinde hem UI seviyesinde tamamen kapatsın — "her müşteri kendi satın aldığı modülleri çalıştırır" satış stratejisinin altyapısı.

**Architecture:** `moduller` tablosuna tek bir `aktif boolean` sütunu eklenir. Bu bilgi, sistemin zaten dayandığı İKİ merkezi kontrol noktasına (`auth_yetki_var()` SQL fonksiyonu ve `kullaniciYetkileriGetir()` JS fonksiyonu) gömülür — böylece portal filtrelemesi, tüm sayfalardaki buton gösterme mantığı ve tüm RLS policy'leri hiçbir başka dosyaya dokunmadan otomatik olarak yeni kısıtlamayı devralır.

**Tech Stack:** Vanilla HTML/JS, Supabase REST (`fetch`), PostgreSQL RLS.

## Global Constraints

- Mevcut canlı kurulumda (Gürok'un kendi kullanımı) HİÇBİR davranış değişmemeli — yeni sütun `default true` olmalı.
- Değişiklik SADECE iki choke-point'e (`auth_yetki_var()`, `kullaniciYetkileriGetir()`) gömülür — `index.html`, `muhasebe-*.html`, `satin-alma-*.html` gibi 40+ dosyaya HİÇ dokunulmaz.
- Kontrol granülaritesi: 41 ince-taneli `moduller` satırı (kart seviyesi değil).
- Bu proje repoda `.sql` dosyası tutmuyor — şema değişiklikleri kullanıcıya fenced SQL bloğu olarak verilir, Supabase SQL editöründe çalıştırılır, onay sonrası curl ile doğrulanır.
- `SB_URL='https://xwytofysmgqtqjzkplfi.supabase.co'`, anon key oturumda mevcut.

---

## Task 1: Supabase Şeması — `moduller.aktif` Sütunu + `auth_yetki_var()` Güncellemesi

**Bu task CONTROLLER tarafından yapılır, bir implementer subagent'a DEVREDİLMEZ** — `auth_yetki_var()` fonksiyonunun mevcut gövdesi repoda tutulmuyor (hiç `.sql` dosyası yok), bu yüzden önce kullanıcıdan canlı fonksiyon tanımını çekmesi istenmeli, sonra ona göre kesin `CREATE OR REPLACE FUNCTION` yazılmalı. Bu, kullanıcı etkileşimi gerektiren, önceden tam metni yazılamayacak tek adım.

**Files:**
- Kullanıcıya verilecek: SQL blokları (repo dosyası değil)
- Modify: `.superpowers/sdd/progress.md` (ilerleme kaydı)

**Interfaces:**
- Produces: `moduller.aktif` sütunu (boolean, default true), güncellenmiş `auth_yetki_var(p_modul_kod text, p_min_seviye text default 'goruntule') returns boolean`. Task 2 ve Task 3 bunu tüketir.

- [ ] **Step 1: Sütunu ekle**

Kullanıcıya ver:

```sql
alter table moduller add column aktif boolean not null default true;
```

Onay sonrası curl ile doğrula:

```bash
SB_URL='https://xwytofysmgqtqjzkplfi.supabase.co'
SB_KEY='eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Inh3eXRvZnlzbWdxdHFqemtwbGZpIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODMyMjg5ODMsImV4cCI6MjA5ODgwNDk4M30.E7cRcOAvCmUFXWs45t4HE-igpmqWmSN2J66dOuvCHjA'
curl -s "$SB_URL/rest/v1/moduller?select=kod,aktif&limit=5" -H "apikey: $SB_KEY" -H "Authorization: Bearer $SB_KEY"
```

Beklenen: her satırda `"aktif":true`.

- [ ] **Step 2: `auth_yetki_var()`'ın canlı tanımını iste**

Kullanıcıya ver:

```sql
select pg_get_functiondef('auth_yetki_var'::regproc);
```

(Not: `auth_yetki_var` iki parametreli — eğer bu sorgu "function name is not unique" hatası verirse, kullanıcıya şunu ver: `select pg_get_functiondef(oid) from pg_proc where proname='auth_yetki_var';` ve dönen tüm satırları iste.)

- [ ] **Step 3: Sonuca göre `CREATE OR REPLACE FUNCTION` oluştur**

Kullanıcının yapıştırdığı fonksiyon gövdesini al. Bu, `language sql stable` bir fonksiyon ve gövdesi tek bir boolean ifadesi (muhtemelen `yetki_matrisi`/`roller` join'i içeren bir `exists(...)` veya `case` ifadesi) — önceki oturumlarda kurulmuş, `rol_id` ve `p_modul_kod`/`p_min_seviye` parametrelerini kullanan bir mantık.

Dönüşüm kuralı (MEKANİK, kelimesi kelimesine uygula): fonksiyonun `CREATE OR REPLACE FUNCTION ... AS $$ <gövde> $$` bloğundaki `<gövde>`'yi (tam olarak neyse) şu şekilde sar:

```sql
(
  <mevcut gövde, aynen kopyala>
)
and exists (
  select 1 from moduller where kod = p_modul_kod and aktif = true
)
```

Yani fonksiyonun DÖNÜŞ değeri artık `(eski mantık) AND (modül aktif mi)` olacak — modül pasifse, eski mantık ne olursa olsun `false` döner. Parametre imzası (`p_modul_kod text, p_min_seviye text default 'goruntule'`), dönüş tipi (`boolean`), ve `language`/`stable` niteleyicileri AYNEN korunur — sadece gövde ifadesi sarmalanır.

Tam `CREATE OR REPLACE FUNCTION` ifadesini kullanıcıya ver, çalıştırmasını iste.

- [ ] **Step 4: Fonksiyonun hâlâ doğru çalıştığını doğrula**

```bash
# Mevcut, aktif bir modülde daha önce zaten çalışan bir RLS engelleme testi tekrarlanır
# (anon key zaten hiçbir role sahip değil, bu yüzden HER ZAMAN false dönmeli — regresyon kontrolü)
curl -s "$SB_URL/rest/v1/stok_hareketleri?select=id&limit=1" -H "apikey: $SB_KEY" -H "Authorization: Bearer $SB_KEY"
```

Beklenen: `[]` (anon her zaman engellenir — bu, fonksiyonun bozulmadığının dolaylı kanıtı; gerçek pozitif/negatif test kullanıcının tarayıcıda gerçek bir JWT ile yapması gereken bir sonraki adımda, Task 4'te yapılacak).

- [ ] **Step 5: İlerleme kaydı**

`.superpowers/sdd/progress.md` sonuna ekle:

```
Modül Aç/Kapa Task 1 (şema): complete — moduller.aktif sütunu (default true) + auth_yetki_var() güncellendi (eski mantık AND moduller.aktif=true). curl ile doğrulandı.
```

---

## Task 2: `auth-guard.js` — `kullaniciYetkileriGetir()` Güncellemesi

**Files:**
- Modify: `auth-guard.js:44,48` (implementasyon anında `Read` ile güncel satır numaralarını teyit et — bu plan yazılırken dosya 97 satırdı, paralel oturum bu dosyayı henüz hiç değiştirmemiş görünüyor ama yine de kontrol et)

**Interfaces:**
- Consumes: Task 1'in `moduller.aktif` sütunu.
- Produces: `kullaniciYetkileriGetir()` artık pasif modülleri haritaya HİÇ eklemiyor. `index.html`'in portal filtrelemesi VE her sayfadaki `YETKI_HARITASI[...]` tabanlı buton mantığı bunu otomatik tüketir — bu iki tüketici için AYRI bir task YOK, mevcut kodları zaten bu fonksiyonun çıktısına güveniyor.

- [ ] **Step 1: Mevcut kodu doğrula**

`auth-guard.js`'i oku, şu 2 satırı bul (plan yazılırken satır 44 ve 48'deydi):

```js
    const r = await fetch(SB_URL + '/rest/v1/yetki_matrisi?select=yetki,moduller(kod)&rol_id=eq.' + user.rol_id, { headers: SB_HEADERS });
```
```js
    rows.forEach(row => { if (row.moduller) harita[row.moduller.kod] = row.yetki; });
```

- [ ] **Step 2: İki satırı güncelle**

Birinci satırı şuna değiştir (embedded `moduller` seçimine `aktif` ekle):

```js
    const r = await fetch(SB_URL + '/rest/v1/yetki_matrisi?select=yetki,moduller(kod,aktif)&rol_id=eq.' + user.rol_id, { headers: SB_HEADERS });
```

İkinci satırı şuna değiştir (pasif modülü haritaya hiç ekleme):

```js
    rows.forEach(row => { if (row.moduller && row.moduller.aktif) harita[row.moduller.kod] = row.yetki; });
```

Dosyanın geri kalanına (yorum satırları dahil) dokunma.

- [ ] **Step 3: Statik doğrulama**

Dosyanın sözdizimsel olarak geçerli kaldığını (parantez/süslü parantez dengesi) kontrol et. Tarayıcı testi bu ortamda yapılamaz — Task 4'te kullanıcı tarafından yapılacak.

- [ ] **Step 4: Commit**

```bash
git add auth-guard.js
git -c user.name="mehmetaraz0" -c user.email="mehmetaraz868@gmail.com" commit -m "feat: kullaniciYetkileriGetir() artık pasif modülleri hariç tutuyor"
```

---

## Task 3: `yetki-yonetimi.html` — Modül "Aktif" Toggle

**Files:**
- Modify: `yetki-yonetimi.html` (implementasyon anında `Read` ile güncel içeriği teyit et — bu plan yazılırken tam 169 satırdı, en son paralel-oturum sweep'inde 1 satırı değişmişti ama yapısı aynıydı)

**Interfaces:**
- Consumes: Task 1'in `moduller.aktif` sütunu. Bu sayfa modülleri SÜTUN (tablo başlığı `<th>`) olarak render ediyor — `render()` fonksiyonu (satır 89-112), `moduller.forEach(m=>{thead1+=...})` (satır 97).
- Produces: Yönetici bir modül başlığına tıklayınca o modülün `aktif` durumu değişir. Başka hiçbir task buna bağımlı değil.

- [ ] **Step 1: CSS ekle**

`<style>` bloğunun sonuna (plan yazılırken satır 38'deki `#toast.show{...}` kuralından hemen sonra) ekle:

```css
th.modul-pasif{opacity:.45;text-decoration:line-through;cursor:pointer}
th.modul-th{cursor:pointer}
```

- [ ] **Step 2: `render()` fonksiyonundaki modül başlık satırını güncelle**

Mevcut (plan yazılırken satır 97):

```js
  moduller.forEach(m=>{thead1+=`<th class="kat-${m.kategori}">${m.ad}</th>`;});
```

Yeni:

```js
  moduller.forEach(m=>{thead1+=`<th class="kat-${m.kategori} modul-th${m.aktif===false?' modul-pasif':''}" onclick="modulAktifDegistir('${m.id}')" title="Tıkla: modülü aktif/pasif yap">${m.aktif===false?'🔒 ':''}${m.ad}</th>`;});
```

- [ ] **Step 3: `modulAktifDegistir()` fonksiyonunu ekle**

`hucreDegistir()` fonksiyonunun (plan yazılırken satır 118-149) hemen SONRASINA ekle:

```js
async function modulAktifDegistir(modulId){
  const m=moduller.find(x=>x.id===modulId);
  if(!m)return;
  const yeniDeger=m.aktif===false?true:false;
  try{
    await fetch(SB_URL+'/rest/v1/moduller?id=eq.'+modulId,{
      method:'PATCH',headers:SB_HEADERS,
      body:JSON.stringify({aktif:yeniDeger})
    });
    m.aktif=yeniDeger;
    render();
    toast(yeniDeger?'✅ Modül aktif edildi':'✅ Modül pasif edildi');
  }catch(e){
    toast('⚠️ Kaydedilemedi, tekrar dene');
    console.warn(e);
  }
}
```

- [ ] **Step 4: Tarayıcıda manuel doğrula**

`yetki-yonetimi.html`'i aç (yönetici rolüyle). Herhangi bir modül başlığına tıkla — kırmızı çizgili/soluk hâle geldiğini, 🔒 ikonu göründüğünü doğrula. Sayfayı yenile, durumun kalıcı olduğunu (pasif kalmaya devam ettiğini) doğrula. Tekrar tıklayıp aktif hâle getir.

**Eğer PATCH isteği RLS tarafından reddedilirse** (`moduller` tablosunda beklenmedik bir UPDATE policy varsa): bu, Task 1'de öngörülmemiş bir durum — kullanıcıya durumu bildir, `moduller` tablosunun RLS policy'lerini (`select policyname,cmd,qual from pg_policies where tablename='moduller';`) sorgulat, sonucu controller'a ilet.

- [ ] **Step 5: Commit**

```bash
git add yetki-yonetimi.html
git -c user.name="mehmetaraz0" -c user.email="mehmetaraz868@gmail.com" commit -m "feat: yetki-yonetimi.html'e modül aktif/pasif toggle eklendi"
```

---

## Task 4: Uçtan Uca Doğrulama

**Files:**
- Modify: `.superpowers/sdd/progress.md`

**Interfaces:**
- Consumes: Task 1-3'ün tüm çıktıları.

- [ ] **Step 1: Repo genelinde grep taraması**

```bash
cd "C:\Users\USER\Projects\gurok-mal-kabul"
grep -n "moduller(kod,aktif)\|row.moduller.aktif" auth-guard.js
grep -n "modulAktifDegistir" yetki-yonetimi.html
```

Beklenen: her iki komut da eşleşme döndürsün.

- [ ] **Step 2: Kullanıcıdan gerçek oturumla uçtan uca test iste**

Kullanıcıya şunu iste: gerçek bir kullanıcıyla giriş yap, `yetki-yonetimi.html`'den az önce eklediğin `urun_yonetimi` modülünü (Birim Dönüşüm fazından) PASİF yap. Portala dön — "Ürün Yönetimi" linkinin bulunduğu `stok-takip.html`'e git, `urun-yonetimi.html`'e tıkla: sayfa açılmalı (requireRole kaba kontrolü hâlâ geçer) ama liste BOŞ gelmeli (RLS artık `auth_yetki_var('urun_yonetimi',...)`'de `moduller.aktif=false` yüzünden engelliyor). Sonra modülü tekrar AKTİF yap, sayfayı yenile, verinin geri geldiğini doğrula.

Bu test, Task 1'in `auth_yetki_var()` güncellemesinin RLS'de gerçekten çalıştığının TEK kesin kanıtı (anon key ile ayırt edilemiyordu, gerçek JWT gerekiyor).

- [ ] **Step 3: `git fetch origin` ile paralel oturum kontrolü**

```bash
cd "C:\Users\USER\Projects\gurok-mal-kabul"
git fetch origin
git rev-list --left-right --count HEAD...origin/main
```

İlerlemişse `git diff --name-only $(git merge-base HEAD origin/main) origin/main` ile kontrol et, `git merge origin/main` ile birleştir (Task 2/3'ün dokunduğu `auth-guard.js`/`yetki-yonetimi.html` çakışmışsa, merge sonrası `grep` ile Step 1'i TEKRAR çalıştır).

- [ ] **Step 4: İlerleme kaydı ve push**

`.superpowers/sdd/progress.md` sonuna ekle:

```
Modül Aç/Kapa Task 4 (uçtan uca doğrulama): complete — grep taraması geçti, kullanıcı gerçek oturumla urun_yonetimi modülünü pasif/aktif yaparak RLS'nin gerçekten çalıştığını doğruladı.
Modül Aç/Kapa Kataloğu: TAMAMLANDI. moduller.aktif sütunu + auth_yetki_var() + kullaniciYetkileriGetir() + yetki-yonetimi.html toggle — hiçbir başka dosyaya dokunulmadı (tasarımın amacı buydu).
```

```bash
git push origin main
```

---

## Self-Review Notu

- **Spec kapsaması:** Spec'in 3 bölümü (veri modeli, uygulama noktası, yönetim ekranı) sırasıyla Task 1, Task 2, Task 3'e karşılık geliyor. Hata yönetimi/kenar durumlar bölümü ayrı bir task gerektirmiyor — zaten mevcut fail-safe davranışlara (`kullaniciYetkileriGetir()`'in hata durumunda boş obje dönmesi, RLS'nin sessiz boş liste göstermesi) dayanıyor, bunlar değişmiyor.
- **Placeholder taraması:** Yok — Task 1'in Step 3'ü istisna: kesin SQL metni runtime'da (kullanıcının canlı fonksiyon tanımını paylaşmasından sonra) belirleniyor, ama DÖNÜŞÜM KURALI kelimesi kelimesine, mekanik ve belirsizlik içermeyecek şekilde yazıldı (bu, B6 fazındaki "önce şemayı öğren sonra tamamla" desenine benzer, meşru bir istisna).
- **Tip/isim tutarlılığı:** `moduller.aktif` (Task 1), `row.moduller.aktif` (Task 2), `m.aktif` (Task 3) — hepsi aynı boolean sütuna işaret ediyor, tutarlı.
