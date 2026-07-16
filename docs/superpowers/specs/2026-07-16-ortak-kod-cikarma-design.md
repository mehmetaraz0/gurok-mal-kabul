# Teknik Borç — Ortak Kod Çıkarma (Pilot) — Tasarım

## Problem / Hedef

Ürün denetim raporunun P2 maddesi: iş mantığının devasa HTML dosyalarında
olması bakımı zorlaştırıyor. Kod taraması gerçek boyutu ölçtü: `sLD`, `hLD`,
`toast`, `escapeHtml`, `round2`, `kModal`/`aModal` yardımcı fonksiyonları
~20 dosyada birebir aynı kopyalanmış; XLSX kütüphane yükleme bloğu 13 yerde
tekrarlanmış; ortak CSS paleti 21 dosyada aynı.

## Kapsam

- Yeni `ortak.js`: `sLD`, `hLD`, `toast`, `escapeHtml`, `round2`, `kModal`,
  `aModal`, `loadXlsxLib()`.
- Yeni `theme.css`: paylaşılan `:root` değişkenleri.
- Pilot uygulama: `satin-alma.html`, `depo-siparis.html`,
  `muhasebe-cariler.html` — üçünde de yukarıdaki fonksiyonlar byte-byte
  doğrulandı (bkz. Doğrulama).

## Kapsam dışı

- `fmt()` — dosyalar arası ondalık basamak sayısı uyuşmuyor (11 dosya 2
  ondalık, 2 dosya 0 ondalık, 1 dosya 4 ondalık kur hassasiyeti), bir
  dosyada aynı isim tarih formatlayıcısı için kullanılmış — birleştirmek
  muhasebe sayfalarında tutar gösterimini sessizce bozabilir.
- `toast()`'un 3 farklı-imzalı dosyası (gunluk-tuketim.html,
  trend-raporlama.html, yetki-yonetimi.html) — gövdeleri farklı.
- `auditLogYaz` (9 dosya) — biri (`mal-kabul-v2.html`) farklı oturum
  değişkeni (`currentUser` vs `OTURUM_KULLANICI`) kullanıyor.
- `gTab()` tab-switcher — sayfaya özel callback'ler nedeniyle ortak
  çekirdek çıkarmak ayrı bir tasarım işi.
- Kalan ~26 dosyanın rollout'u — pilot onaylandıktan sonra.
- `gurok_mal_kabul.html` (5609 satır, index.html navigasyonunda hiç
  linklenmiyor ama 4 gün önce hâlâ bug fix almış) ve `index.html.html`
  (1723 satır, hiçbir yerden linklenmiyor, tek commit'i "Add files via
  upload") — şüpheli ölü kod, silme kararı kullanıcıya bırakılıyor, bu
  işte dokunulmuyor.

## Mimari

`ortak.js` (repo kökü, `<head>`'de `auth-guard.js`'den hemen sonra, sayfa
script'inden önce senkron yüklenir): 6 fonksiyonun mevcut dosyalardan
byte-byte doğrulanmış gövdesi + yeni `loadXlsxLib()` (13 yerde tekrarlanan
`if(typeof XLSX==='undefined'){...}` bloğunun tek hali).

`theme.css`: sadece paylaşılan `:root` değişkenleri —
`--primary, --primary-light, --success, --warning, --danger, --info,
--gray-100..700, --radius, --radius-sm, --shadow` (satin-alma.html'in
kendine özel `--accent` değişkeni page-local `:root`'ta kalır).

## Doğrulama / Bayat Veri

Taşınacak 6 fonksiyonun `satin-alma.html`, `depo-siparis.html`,
`muhasebe-cariler.html`'deki gövdeleri `grep`/diff ile karşılaştırıldı —
`sLD`, `hLD`, `toast`, `kModal`, `aModal` üçünde de birebir aynı;
`escapeHtml`/`round2` sadece `muhasebe-cariler.html`'de tanımlı,
`depo-siparis.html` bu ikisini hiç çağırmıyor (zararsız — kullanılmayan
ekstra global). `:root` paletinin ortak alt kümesi üçünde de birebir aynı.

## Test/doğrulama planı

Statik: pilot 3 dosyada taşınan fonksiyonların yerel tanımlarının
tamamen silindiğini (`grep -c` sıfır dönmeli), `<script src="ortak.js">`/
`<link ... theme.css>`'in `<head>`'de doğru sırada olduğunu doğrulamak.

Tarayıcı (her pilot dosya için): gerçek kullanıcıyla login, en az 2 sekme
geçişi, bir toast tetikleyen aksiyon, bir modal aç/kapa, konsolda hata
olmadığını doğrulamak.
