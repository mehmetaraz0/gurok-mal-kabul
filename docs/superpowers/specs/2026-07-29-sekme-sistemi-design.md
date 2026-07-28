# Uygulama İçi Sekme Sistemi — Tasarım

## Context

Birden fazla göreve/departmana bakan kullanıcılar (örn. hem Depo hem Muhasebe işine bakan biri) bugün bir modülden diğerine geçerken tam sayfa navigasyonu (`location.href`) kullanmak zorunda — önceki modülün durumu (doldurulmuş form, kaydırma konumu) kaybolur. Kullanıcı, tarayıcı sekmelerine benzeyen ama **uygulamanın kendi içinde çizilen** bir sekme çubuğu istiyor: Ana Sayfa sabit/kapatılamaz bir sekme, seçilen her modül yeni bir sekme olarak açılır, sekmeler arasında geçiş yapılırken hiçbiri sıfırlanmaz.

Proje build sistemi yok, ~60 bağımsız statik HTML dosyası var, her biri kendi `<script>` bloğunu ve global değişkenlerini (`CU`, `YETKI_HARITASI`, `#toast`/`#ld` id'leri vb.) taşıyor — bunlar dosyalar arası **isim çakışması riski** taşıyor. Bu proje, [[Genel-Bakis|Obsidian bilgi tabanındaki]] "her sayfa kendi HTML/CSS/JS'ini taşır" normunu koruyor; sekme sistemi bu 60 dosyanın hiçbirini değiştirmeden çalışmalı.

## Kapsam

### 0) Sekme çubuğu taşması

Sekme sayısı çubuğu doldurursa, sekmeler küçülmez — çubuk yatayda kaydırılabilir olur (`overflow-x:auto`, her sekme sabit min-genişlikte). "+" düğmesi çubuğun **dışında, her zaman sabit** kalır (kaydırmadan etkilenmez).

### 1) `index.html` — kabuğa dönüşüm

Mevcut hub içeriği (KPI şeridi + modül kart grid'i) değişmeden kalır, ama artık **"Ana Sayfa" sekmesinin içeriği** olarak konumlanır — sabit, kapatılamaz, her zaman ilk sekme. `.topbar`'ın altına yeni bir `.tab-bar-app` şeridi eklenir:

- Her açık sekme için bir buton: modül adı + (Ana Sayfa hariç) bir "×" kapat ikonu.
- Aktif sekme `--accent` renkli alt çizgiyle vurgulu.
- Sağ uçta sabit bir "+" düğmesi — `ND_MODULLER` listesini (yetkiye göre filtrelenmiş, `nav-drawer.js` ile aynı veri kaynağı) gösteren bir açılır panel açar; seçilen modül yeni sekme olarak eklenir.

Modül içerikleri `<iframe src="modul.html">` olarak render edilir; aktif olmayan sekmelerin iframe'i DOM'dan kaldırılmaz, sadece `display:none` olur (arka plandaki sekmenin form/scroll durumu korunur).

### 2) Sekme durumu — sadece bellekte

```js
let SEKMELER = [{ id:'home', ad:'Ana Sayfa', url:null, kapatilabilir:false, aktif:true }];
// yeni modül: { id: crypto.randomUUID(), ad, url, kapatilabilir:true, aktif:false }
```

`sessionStorage`'a **kasıtlı olarak yazılmıyor** — kullanıcı kararı: sayfa yenilenince sekmeler sıfırlanır, sadece Ana Sayfa ile başlanır (aşağıdaki `beforeunload` uyarısı bu senaryoyu zaten önceden haber veriyor).

Aynı modül birden fazla kez açılabilir (her tıklama yeni bir sekme oluşturur, mevcut sekmeye atlanmaz) — kullanıcı kararı.

### 3) `beforeunload` uyarısı

En az bir kapatılabilir (Ana Sayfa dışı) sekme açıkken, sayfa yenileme/kapatma/başka adrese gitme girişiminde tarayıcının kendi onay diyaloğu tetiklenir:

```js
window.addEventListener('beforeunload', e => {
  if (SEKMELER.some(s => s.kapatilabilir)) { e.preventDefault(); e.returnValue = ''; }
});
```

**Önemli sınırlama**: Chrome/Firefox güvenlik gereği özel mesaj metnine artık izin vermiyor — tarayıcının kendi genel metni gösterilir, `e.returnValue`'ya atanan değer içerik olarak kullanılmaz (sadece diyaloğu tetiklemek için boş olmayan bir değer gerekir). Davranış (Tamam/İptal seçenekli onay) isteneni karşılıyor, metin özelleştirilemez.

### 4) `nav-drawer.js` — iframe tespiti

`ndKur()` fonksiyonunun başına bir kontrol eklenir:

```js
if (window.self !== window.top) return; // kabuğun içinde (bir sekmede) çalışıyor — kendi hamburger'ini enjekte etme
```

Bağımsız açılan (URL'den direkt girilen, veya kabuk henüz uygulanmamışken açılan) sayfalarda davranış aynen korunur — `window.self === window.top` olduğu için hamburger + drawer eskisi gibi enjekte edilir.

### 5) Bilinen sınırlama (kasıtlı, v1 kapsamı)

Bir modül sekmesinin kendi "eve dön" ok butonuna (`location.href='index.html'` veya `='mal-kabul-v2.html'` gibi) basılırsa, sekme **kapanmaz** — o sekmenin iframe'i kendi içinde hedef sayfaya gider (o sekmenin içeriği artık hub veya başka bir hub sayfası olur). Sekmeyi gerçekten kapatmak için sekme çubuğundaki "×" kullanılmalı. 60 dosyanın her birinin "eve dön" butonunu `postMessage` ile kabuğa haber verecek şekilde değiştirmek bu fazın kapsamı dışında — ileride gerçek bir sorun olursa ayrı bir iş olarak ele alınır.

## Mimari kararı: neden iframe (SPA yeniden yazımı değil)

Alternatif — her modülün HTML'ini `fetch()` ile çekip bir `<div>` içine enjekte etmek ve `<script>` bloklarını elle yeniden çalıştırmak — **reddedildi**: bu, global değişken çakışması (birçok dosya `CU`, `YETKI_HARITASI` gibi aynı isimleri kullanıyor), `#toast`/`#ld`/modal id çakışması ve olay dinleyicisi sızıntısı riski taşıyan, çerçevesiz bir SPA router'ı sıfırdan inşa etmek anlamına gelir — projenin "framework yok, build aracı yok" ilkesiyle çelişir.

iframe her sekmeye **tam DOM/JS izolasyonu** verir (id/global çakışması imkansız), aynı-origin olduğu için `sessionStorage` (giriş oturumu) sekmeler arasında otomatik paylaşılır — kullanıcı sekme başına tekrar giriş yapmaz. En önemlisi: **60 modül dosyasının hiçbiri değişmiyor** (sadece `index.html` ve `nav-drawer.js`).

## Kapsam dışı (v1)

- Sekme durumunun `sessionStorage`'a yazılıp sayfa yenilemede geri yüklenmesi — kullanıcı kararıyla reddedildi.
- Modül sayfalarının kendi "eve dön" butonlarının sekme-kapatma ile entegrasyonu (`postMessage` köprüsü) — bilinen sınırlama olarak bırakıldı.
- URL çubuğunun aktif sekmeyi yansıtması (History API push-state) — "tek sayfa/tek URL" felsefesiyle çelişir, istenmedi.
- Arka plandaki (görünmeyen) sekmelerin kendi polling/canlı-güncelleme döngülerinin (örn. `bar-siparis-kuyrugu.html`'in 8sn polling'i) duraklatılması — iframe DOM'dan kaldırılmadığı için bu döngüler arka planda çalışmaya devam eder; birkaç açık sekme için kabul edilebilir performans maliyeti, onlarca sekme için sorun olur ama bu kullanım senaryosunda beklenmiyor.

## Test/Doğrulama Planı

Statik: `nav-drawer.js`'in iframe-tespit dalının hem bağımsız hem gömülü modda doğru davrandığını kod okuyarak doğrulamak.

Tarayıcıda: Ana Sayfa'dan 2-3 farklı modülü sekme olarak aç → aralarında geçiş yap → birindeki forma veri gir, başka sekmeye geçip geri dön, verinin durduğunu doğrula → bir sekmeyi "×" ile kapat → Ana Sayfa'da kapat düğmesi olmadığını doğrula → en az 1 modül sekmesi açıkken sayfa yenilemeyi dene, tarayıcı onay diyaloğunun çıktığını doğrula (sadece Ana Sayfa açıkken çıkmadığını da doğrula) → aynı modülü iki kez aç, iki ayrı sekme oluştuğunu doğrula → bir modül sekmesinin kendi "eve dön" butonuna bas, sekmenin kapanmadığını ama içeriğinin değiştiğini doğrula (bilinen sınırlama, regresyon değil).

## İlgili

`nav-drawer.js`, `index.html`, `theme.css`.
