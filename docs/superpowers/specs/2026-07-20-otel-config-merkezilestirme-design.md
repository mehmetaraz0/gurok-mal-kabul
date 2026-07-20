# Config Değerlerinin Merkezileştirilmesi (`otel-config.js`) — Tasarım

**Bağlam:** Satış stratejisi punch list'inin 3. maddesi — "tek-müşteri-tek-kurulum" modelinde yeni bir otel/turizm grubuna kurulum yaparken kod içinde dağınık müşteriye özel sabitleri değiştirmek gerekmesin.

## Problem

Kod tabanında sistematik bir tarama yapıldı (bkz. bu spec'i doğuran araştırma). Bulgular:

- Otel kodları `'810'`/`'811'` 27 farklı `.html`/`.js` dosyasında toplam 176 kez geçiyor.
- `OTEL_ISIMLERI`/`OTEL_KISA` sözlükleri en az 14 dosyada **ayrı ayrı, birebir kopyalanmış** — merkezi bir tanım yok.
- **Kanıtlanmış bir bug:** `kullanici-yonetimi.html:113`'teki kopya, diğerlerinden farklı değerlerle tanımlı (`'Club Manavgat'` vs. doğru `'Ali Bey Club Manavgat'`) — kopyala-yapıştır kaymasından kaynaklanan gerçek bir tutarsızlık.
- Merkezi depo kodu türetme mantığı (`otelId==='811'?'300':'100'`) en az 8 dosyada tekrar tekrar yazılmış.
- Tam ticari unvanlar (`"GUROK TUR MAD.A.Ş. (RESORT SORGUN)"` gibi) 2 yerde, `@gurok.internal` e-posta domaini 1 yerde hardcoded.

`gurok_veritabani.js` (ürün/tedarikçi kataloğu, 211KB) kapsam DIŞI — bu bir "sabit" değil, müşteriye özel VERİ; yeni müşteri kurulumunda zaten baştan doldurulacak (punch list madde 4'ün konusu, bu spec'in değil).

## Veri Modeli / Dosya Yapısı

Yeni dosya, `supabase-config.js`'nin YANINA, aynı desende:

```js
// otel-config.js — Gürok ERP müşteriye özel kurulum sabitleri.
// Yeni bir müşteri kurulumunda SADECE bu dosya düzenlenir.
const OTEL_ISIMLERI = {'810':'Ali Bey Club Manavgat','811':'Ali Bey Resort Sorgun'};
const OTEL_KISA = {'810':'Club','811':'Resort'};
const OTEL_TICARI_UNVAN = {'810':'GUROK TUR MAD.A.Ş. (CLUB MANAVGAT)','811':'GUROK TUR MAD.A.Ş. (RESORT SORGUN)'};
const GRUP_ADI = 'Gürok Turizm Grubu';
const DAHILI_EMAIL_DOMAIN = 'gurok.internal';
const MERKEZI_DEPO = {'810':'100','811':'300'};
function merkeziDepoKodu(otelId){ return MERKEZI_DEPO[otelId] || '100'; }
function otelFromDepoId(depoId){ const i=(depoId||'').indexOf('_'); return i>=0 ? depoId.slice(0,i) : '810'; }
```

Script yükleme sırası (tüm sayfalarda zorunlu, mevcut `auth-guard.js`→`supabase-config.js`→`ortak.js` sırasının arasına eklenir):
`auth-guard.js` → `supabase-config.js` → `otel-config.js` → `ortak.js` → (varsa diğer sayfa-özel script'ler) → `theme.css`.

`otel-config.js`, `SB_URL`/`SB_HEADERS` gibi başka hiçbir dosyaya bağımlı değil — bağımsız, saf veri + 2 saf fonksiyon.

## Migrasyon Kapsamı

Tespit edilen ~27 dosyanın her birinde üç değişiklik:
1. `<script src="otel-config.js">` doğru sırada eklenir.
2. O dosyadaki yerel `OTEL_ISIMLERI`/`OTEL_KISA`/tam unvan/e-posta tanımı **silinir** (merkezi olan kullanılır — global scope'ta aynı isim yeniden tanımlanmaz, `const` çakışması riskini önlemek için bu SİLME adımı zorunlu, opsiyonel değil).
3. `otelId==='811'?'300':'100'` (veya eşdeğer ternary/if-else) kalıpları `merkeziDepoKodu(otelId)` çağrısına çevrilir.

Migrasyon, önceki fazlarda (B3-B6) kanıtlanmış "dalga" (wave) deseniyle yapılır — her dalga ~5-6 dosya + dalga sonu doğrulama, tüm dosyalar bitince genel uçtan uca doğrulama.

`kullanici-yonetimi.html`'deki mevcut bug (yanlış otel adı sözlüğü), bu dosya migrasyona dahil olduğunda otomatik düzelir — ayrı bir düzeltme task'ı gerekmez.

## Hata Yönetimi / Kenar Durumlar

- Bir dosyada yerel tanım silinirken merkezi dosyanın `<script>` etiketi eklenmeyi unutulursa: `OTEL_ISIMLERI is not defined` gibi bir ReferenceError sayfa yüklenirken hemen ortaya çıkar (sessiz bir hata değil) — her dalga sonunda tarayıcı konsolu kontrolü bunu yakalar.
- `merkeziDepoKodu()`/`otelFromDepoId()` mevcut ternary'lerle AYNI davranışı (`'811'` için `'300'`, diğer her şey için `'100'`/`'810'` varsayılan) korur — yeni bir iş kuralı eklenmiyor, sadece taşınıyor.

## Test/Doğrulama Planı

- Her dalga sonunda: `grep` ile (a) yerel `OTEL_ISIMLERI`/`OTEL_KISA` tanımının o dosyalarda artık geçmediğini, (b) `<script src="otel-config.js">`'in doğru sırada eklendiğini doğrula.
- En az 2-3 kritik dosyada (örn. `mal-kabul-liste.html`, `stok-takip.html`, bir muhasebe sayfası) tarayıcıda otel adının/kısa adının hâlâ doğru göründüğünü, mal kabul/stok akışlarının bozulmadığını kontrol et.
- Son dalgada `kullanici-yonetimi.html`'in artık doğru ("Ali Bey Club Manavgat" öneki dahil) otel adını gösterdiğini özellikle doğrula (bilinen bug'ın düzeldiğinin kanıtı).
- Tüm migrasyon bitince repo genelinde `grep -rn "'810':'Ali Bey\|'811':'Ali Bey"` çalıştırılıp SIFIR sonuç döndüğü (tüm kopyaların silindiği) doğrulanır.
