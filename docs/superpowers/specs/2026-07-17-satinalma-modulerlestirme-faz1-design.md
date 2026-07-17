# Satın Alma — Muhasebe Deseninde Modülerleştirme (Faz 1) — Tasarım

## Problem / Hedef

`satin-alma.html` 3250+ satır, 9 sekme tek dosyada. Kullanıcı, bunu
`muhasebe.html` desenindeki gibi bölmek istiyor: her modülün kendi
bağımsız `.html` dosyası olsun, `muhasebe.html`'in `muhasebe-cariler.html`
vb. sayfalara linklediği gibi.

`muhasebe.html` deseninde sayfalar arası hiç canlı bellek paylaşımı yok —
her alt sayfa bağlamsız açılır, kendi `loadDB()`'ini çalıştırır.
`satin-alma.html` farklı: 9 sekme aynı sayfada `gTab()` ile canlı JS
state paylaşarak geçiş yapıyor, İç Talepler'in "Teklif İste"/"Siparişe
Dönüştür" butonları Teklifler/Sipariş Oluştur sekmelerine sayfa-içi
atlıyor. Bu yüzden tüm 9 sekmeyi tek seferde bölmek yerine, önce
**bağımsız 4 sekme** ayrı dosyalara taşınıyor (strangler fig deseni).

## Kapsam

Kod incelemesi (grep ile doğrulandı) 4 sekmenin tamamen bağımsız
olduğunu gösterdi — aralarında veya diğer sekmelerle hiç sayfa-içi
atlama/canlı state paylaşımı yok:

- **LN Siparişler** (`filterLN`, `renderLN`, `openLNDetay`,
  `lnEksikleriAktar`, `parseLNExcel`, `applyLNKolon`, `saveLnSiparisler`,
  satır 1602-1720 + modaller `#mLNDetay`/`#mLNKolon`) — `DB.lnSiparisler`
  sadece bu sekmeye özel, başka hiçbir yerde okunmuyor (grep ile
  doğrulandı).
- **Firmalar** (`renderFirmalar`, satır 3086-3100, salt-okunur) —
  `DB.firmalar`/`loadFirmalar()` satin-alma.html'de KALIYOR (Sipariş
  Oluştur, RFQ, Fiyat Kontrolü'nün firma-eşleştirme mantığı hâlâ
  kullanıyor — grep ile 10+ kullanım yeri doğrulandı), sadece görüntüleme
  fonksiyonu taşınıyor.
- **Fiyat Kontrolü** (`loadFiyatKontrol`, `fkSbdenCamele`,
  `filterFiyatKontrol`, `renderFiyatKontrol`, `fkDetayAc`,
  `fkFiyatHesapla`, `fkGenelToplamHesapla`, `muhasebeGonder`,
  `grIrTahakkukFisiKes`, satır 1930-2304 + modal `#mFiyatKontrol`) —
  tamamen kendi Supabase sorgularını yapıyor (`mal_kabuller`,
  `faturalar`, `hesap_plani`, `yevmiye_fisler`), `DB.*`'ye bağımlı değil.
- **Tedarikçi Skor Kartı** (`renderSkorKart`, satır 3105-3210) —
  tamamen kendi Supabase sorgularını yapıyor, salt-okunur, modal yok.

Kalan 5 sekme (İç Talepler, Teklifler, Sipariş Oluştur, Sipariş Takip,
İade) — canlı sayfa-içi atlama veya iç içe geçmiş kod bloğu içeriyor,
bu fazın kapsamı dışında.

## Kapsam dışı

- Kalan 5 sekme.
- `satin-alma.html`'i tam hub sayfasına çevirmek (tüm 9 sekme taşınana
  kadar).
- satin-alma.html'in kendi gömülü `FIRMA_DB`/`URUN_DB` kopyasını
  `gurok_veritabani.js`'e taşımak (satin-alma.html'in kalan sekmeleri
  hâlâ kendi kopyasını kullanıyor).
- `spSifirla()`/`filterFirmaDD()` (ölü/bozuk kod, taşınmıyor).

## Mimari

Her yeni dosya `muhasebe-cariler.html` iskeletinin birebir kopyası:
`auth-guard.js`→`supabase-config.js`→`ortak.js`→`theme.css` head sırası,
head-level `requireLogin()`/`requireRole()` guard, `<div id="toast">`/
`<div id="ld">`, satin-alma.html'in TÜM `<style>` bloğunun kopyası
(sadece kullanılan sınıflara indirgemek yerine — muhasebe-cariler.html
da aynı şekilde tam kopya kullanıyor, dosyalar arası hiç CSS paylaşımı
`theme.css` dışında yok).

`satin-alma-firmalar.html` ek olarak `<script src="gurok_veritabani.js">`
yükler ve doğrudan `FIRMA_DB`/`URUN_DB` global'lerini kullanır (kendi
DB objesi yerine) — `stok-takip.html`'in zaten kullandığı dosya.

`satin-alma.html`'de değişecekler: 4 sekmenin `tabbtn`'leri
`location.href='satin-alma-X.html'`e çevrilir; `.sc` div'leri, ilgili
fonksiyonlar, modaller silinir; `gTab()` içindeki 4 dispatch satırı
silinir; `loadDB()`'den `ln_siparisler` fetch'i ve `DB.lnSiparisler`
init'i kaldırılır (artık hiçbir yerde okunmuyor); `loadFirmalar()`/
`DB.firmalar` AYNEN kalır.

## Doğrulama / Bayat Veri

Bu fazda bayat-veri riski yok — 4 sekme salt-okunur veya kendi
Supabase sorgularını canlı yapıyor, çoklu-kullanıcı çakışma senaryosu
mevcut davranıştan farklı değil.

## Test/doğrulama planı

Statik: her yeni dosyada taşınan fonksiyonların tam olarak bulunduğunu,
satin-alma.html'de artık bulunmadığını grep ile doğrulamak;
`DB.firmalar`/`loadFirmalar()`'ın satin-alma.html'de kaldığını
doğrulamak.

Tarayıcı: her yeni dosyayı gerçek kullanıcı ile aç, konsol hatası
kontrolü, temel işlem dene. satin-alma.html'in kalan 5 sekmesinin
(özellikle İç Talepler — global "Yeni Talep" butonu, `stokMinimumKontrolEt()`)
hiç bozulmadığını doğrula.
