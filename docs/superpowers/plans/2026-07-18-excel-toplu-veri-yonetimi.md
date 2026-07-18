# Excel Toplu Veri Yönetimi Modülü — Pilot: İç Talepler Kalemleri Implementation Plan

> **For agentic workers:** Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** ERP genelinde yeniden kullanılabilir bir Excel toplu içe/dışa
aktarma altyapısı (`ortak-excel.js`) kurmak ve bunu, İç Talepler'in ürün
kalemlerini (satin-alma.html) toplu Excel ile oluşturma/güncelleme
yeteneğiyle uçtan uca pilot olarak kanıtlamak — önizleme/diff sınıflandırma
ekranı, denetim kaydı ve hata raporu dahil.

**Architecture:** Tablo-agnostik `spec` dizisiyle çalışan 5 paylaşılan
fonksiyon grubu (export, oku, sınıflandır, önizleme modalı, toplu-yaz+
denetim+hata-raporu) + 2 yeni Supabase tablosu (`excel_import_gecmisi`,
`excel_import_satirlari`). Pilot, satin-alma.html'e `satin_alma_talep_
kalemleri` için 4 yeni fonksiyon ekler; `onay-motoru.js`'e dokunmaz.

**Tech Stack:** Vanilla HTML/JS, Supabase REST (fetch), XLSX
(`xlsx-js-style`, `ortak.js`'in `loadXlsxLib()`'i ile lazy-load) — build
aracı/test çerçevesi yok.

---

## Global Constraints

- `ortak-excel.js` tablo-agnostik kalır — İç Talepler'e özel hiçbir alan
  adı modül içine gömülmez, hepsi `spec` parametresiyle gelir (design).
- ID eşleştirme: kilitli ID sütunu doluysa gerçek `id` (UUID) ile, boşsa
  doğal anahtar ile (`urun_kodu`→`urun_adi` fallback) — ID'ler her zaman
  sunucuda üretilir, hiçbir zaman istemciden gönderilmez (design, mevcut
  `saveCari()` deseniyle tutarlı).
- Toplu yazma `saveLnSiparisler` deseninin AYNISI: tek dizi-body POST,
  `on_conflict=<doğal_anahtar>`, `Prefer: resolution=merge-duplicates`,
  500 satırlık gruplar halinde (design).
- Kalem toplu düzenleme SADECE `durum==='bekleyen'&&asama==='depo'`
  iken izinli; Uygula anında bir canlı GET ile bu koşul yeniden
  doğrulanır, koşul bozulmuşsa TÜM aktarım (satır bazlı değil) iptal
  edilir (design — onay denetim izini korumak için).
- `urun_kodu` FK doğrulaması canlı `urunler` tablosuna karşı yapılır
  (`select=kod,ad,birim`), statik `gurok_veritabani.js`'e değil — repoda
  4 sayfanın zaten kullandığı sorgu (design).
- Mevcut `talepleriExcelAktar`/`talepExcelUygula` (onay-kararı Excel'i,
  satin-alma.html) DOKUNULMAZ — farklı özellik, karıştırılmaz.

---

### Task 1: Supabase şema değişikliği (kullanıcı tarafından çalıştırılır)

**Files:**
- Modify: Supabase SQL Editor (kod tabanında dosya yok)

**Interfaces:**
- Produces: `excel_import_gecmisi`, `excel_import_satirlari` tabloları —
  Task 5'in yazma işlemleri bunlara.

- [x] **Step 1: Kullanıcıya SQL'i ver, Supabase SQL Editor'de çalıştırmasını iste**

```sql
CREATE TABLE IF NOT EXISTS excel_import_gecmisi (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tablo_adi text NOT NULL,
  ilgili_id uuid,
  dosya_adi text,
  kullanici_ad text,
  tarih timestamptz DEFAULT now(),
  mod text,
  toplam_satir integer DEFAULT 0,
  yeni_sayisi integer DEFAULT 0,
  guncelleme_sayisi integer DEFAULT 0,
  hata_sayisi integer DEFAULT 0,
  atlanan_sayisi integer DEFAULT 0
);

CREATE TABLE IF NOT EXISTS excel_import_satirlari (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  import_id uuid REFERENCES excel_import_gecmisi(id),
  satir_no integer,
  kayit_id uuid,
  durum text NOT NULL,
  eski_deger jsonb,
  yeni_deger jsonb,
  hata_mesaji text
);
```

- [x] **Step 2: Doğrula** — tablolar oluşturuldu; anon key ile INSERT
  denemesi RLS tarafından reddedildi (`42501`, bu projede yeni tablolarda
  görülen bilinen kalıp). Ayrı düzeltme SQL'i hazırlandı ve raporlandı
  (bkz. `docs/superpowers/specs/2026-07-18-excel-import-gecmisi-rls-fix.md`)
  — kod bu hatayı sessizce loglayıp ana veri yazmasını engellemeden devam
  edecek şekilde tasarlandığı için pilotu bloklamadı.

---

### Task 2: `ortak-excel.js` — export + sütun stil

**Files:**
- Create: `D:\erp\ortak-excel.js`

**Interfaces:**
- Produces: `excelSablonIndir(spec, veriler, dosyaAdi)` — Task 6'nın
  `kalemExcelAktar()`'ı bunu çağırır.

- [x] **Step 1: `excelSablonIndir` yaz** — `loadXlsxLib()` çağırır,
  `spec`'e göre başlık satırı üretir (gizli alanlar hariç), `veriler`i
  satırlara döker, `XLSX.utils.aoa_to_sheet` + hücre stilleri
  (`mal-kabul-v2.html`'in `buildMkFormuXlsx`/`setRangeStyle` deseni:
  kilitli sütun gri dolgu, zorunlu sütun başlığı sarı dolgu,
  `izinliDegerler` varsa başlık hücresine not/comment), `XLSX.writeFile`.
- [x] **Step 2: Commit** (93b818b)

---

### Task 3: `ortak-excel.js` — oku + sınıflandır

**Files:**
- Modify: `D:\erp\ortak-excel.js`

**Interfaces:**
- Produces: `excelDosyaOku(file)`, `excelSatirlariSiniflandir(spec,
  satirlar, mevcutKayitlar, opts)` — Task 6'nın `kalemExcelYukle()`'i
  bunları sırayla çağırır.

- [x] **Step 1: `excelDosyaOku` yaz** — `header:1` (ham dizi-dizi) modu
  kullanıldı, `object-row` yerine — modülün kendi `excelSablonIndir`'i hep
  aynı sütun sırasıyla yazdığı için pozisyonel okuma daha sağlam
  (kolon-eşleştirme gerekmiyor, Faz 2 kapsamına bırakıldı).
- [x] **Step 2: `excelSatirlariSiniflandir` yaz** — planlanan mantığın
  aynısı, `opts.fkAlan`+`opts.fkSet` olarak uygulandı (`fkKontrol` yerine).
  Gerçek uçtan uca testte 6 sınıfın (yeni/güncelleme/değişiklik_yok/hata/
  bulunamadı/mükerrer) hepsi doğru üretildiği doğrulandı.
- [x] **Step 3: Commit** (309314d)

---

### Task 4: `ortak-excel.js` — önizleme/diff modalı

**Files:**
- Modify: `D:\erp\ortak-excel.js`

**Interfaces:**
- Produces: `ensureExcelOnizlemeModal()`, `excelOnizlemeGoster(siniflandirma,
  opts)` — Task 6'nın `kalemExcelYukle()`'i sınıflandırmadan sonra çağırır.

- [x] **Step 1: `ensureExcelOnizlemeModal` yaz** — planlanan gibi idempotent
  DOM enjeksiyonu, AMA `.mo`/`.mbox` yerine kendi izole `.oe-*` sınıfları
  ve kendi `<style>` bloğu kullanıldı (revize gerekçe: `.mo`/`.mbox` gibi
  sınıflar `theme.css`'te DEĞİL, her sayfanın kendi `<style>`'ında ayrı
  ayrı tanımlı — modülün Faz 2'de her sayfaya taşınabilmesi için sayfa
  CSS'ine bağımlı olmaması gerekiyordu).
- [x] **Step 2: `excelOnizlemeGoster` yaz** — planlandığı gibi, gerçek
  tarayıcı testinde sayaçlar/diff/mod seçimi/disabled-buton mantığının
  hepsi doğrulandı.
- [x] **Step 3: Commit** (19eb997)

---

### Task 5: `ortak-excel.js` — toplu yaz + denetim + hata raporu

**Files:**
- Modify: `D:\erp\ortak-excel.js`

**Interfaces:**
- Produces: `excelTopluYaz(tabloAdi, satirlar, {onConflict, batchSize})`,
  `excelImportGecmisiYaz(...)`, `excelHataRaporuIndir(spec, hatalilar,
  dosyaAdi)` — Task 6'nın `kalemExcelUygula()`'i bunları sırayla çağırır.

- [x] **Step 1: `excelTopluYaz` yaz** — `satirlar`'ı `batchSize` (varsayılan
  500) gruplara böler, her grubu tek dizi-body POST ile
  `SB_URL+'/rest/v1/'+tabloAdi+'?on_conflict='+onConflict` +
  `Prefer: resolution=merge-duplicates` ile yazar (`saveLnSiparisler`
  deseni). Her grup için ayrı try/catch, `{basariliGrup,hataliGrup,
  toplamYazilan}` döner — grup içi atomik, gruplar arası DEĞİL (bu
  fonksiyonun dokümantasyon yorumunda açıkça belirtilir).
- [x] **Step 2: `excelImportGecmisiYaz` yaz** — `excel_import_gecmisi`'ye
  bir header POST'u (`Prefer: return=representation` ile id al), sonra
  `excel_import_satirlari`'na tüm satırları TEK dizi-body POST'u ile yaz
  (`talep_onay_gecmisi` yazma deseniyle tutarlı try/catch + `console.error`
  ile başarısızlığı yüzeye çıkar — sessizce yutma).
- [x] **Step 3: `excelHataRaporuIndir` yaz** — `excelSablonIndir`
  makinesini yeniden kullanır, `spec`'e `Hata Açıklaması` sütunu ekler,
  sadece `hata`/`bulunamadi`/`mukerrer` satırlarını içerir.
- [x] **Step 4: Commit** (bf2a11f)

---

### Task 6: satin-alma.html pilot entegrasyonu

**Files:**
- Modify: `D:\erp\satin-alma.html`

- [x] **Step 1: `<head>`'e ekle** — `<script src="ortak-excel.js"></script>`,
  `ortak.js`'den hemen sonra.
- [x] **Step 2: `openTalepDetay()`'e yeni buton** (satır ~926-978) —
  `t.durum==='bekleyen'&&t.asama==='depo'` koşullu, mevcut
  `t.durum==='onaylandi'` bloğundan (971-975) AYRI yeni bir blok: "📊 Excel
  ile Kalem Yönetimi" butonu → `kalemExcelAktar(id)`.
- [x] **Step 3: `kalemExcelSablonSpec` const'ı tanımla** — alan adları
  `t.satirlar`'ın kendi camelCase-benzeri şeklini (`id,kod,ad,miktar,birim`
  — `loadDB()`'nin snake_case'ten çevirdiği hali) kullanacak şekilde revize
  edildi (planın `urun_kodu`/`urun_adi` varsayımı yerine) — böylece talep
  satırları hiç ekstra eşleme katmanı olmadan doğrudan `spec`'e uyuyor;
  `birim` alanına `izinliDegerler:['KG','LT','AD','KOLI']` eklendi.
- [x] **Step 4: `kalemExcelAktar(talepId)` yaz** — `DB.talepler[talepId].
  satirlar`'ı `spec` alanlarına döker, `excelSablonIndir(kalemExcelSablonSpec,
  veriler, 'talep-kalemleri-'+talepId.slice(0,8)+'-'+tarih+'.xlsx')` çağırır.
- [x] **Step 5: `kalemExcelYukle(event,talepId)` yaz** — planlandığı gibi
  (`opts.fkAlan:'kod',fkSet` olarak), gerçek `urunler` tablosuna karşı FK
  kontrolü doğrulandı (bozuk kod → `hata`).
- [x] **Step 6: `kalemExcelUygula(talepId,mod,satirlar)` yaz** — planlandığı
  gibi, operasyon-seviyesi canlı-durum kilidi gerçek testte doğrulandı
  (asama='cost' iken tüm aktarım engellendi, hiçbir satır yazılmadı).
- [x] **Step 7: Tarayıcıda test** — gerçek Supabase ile uçtan uca: güncelleme
  (miktar 9→20) + yeni kayıt oluşturma + FK hatası tespiti + mükerrer
  tespiti + bulunamadı tespiti + kilit testi, hepsi doğrulandı; test
  verisi temizlendi.
- [x] **Step 8: Commit** (2494b16) — ayrıca `talepKaydet()`'teki önceden
  var olan bir hatayı düzeltti (iyimser `DB.talepler` nesnesi `asama`
  alanını set etmiyordu).

---

### Task 7: Uçtan uca doğrulama + rapor

- [x] **Step 1: Tam senaryo** — gerçekten çalıştırıldı: gerçek bir
  `bekleyen`+`depo` talebi (2 kalem) UI üzerinden oluşturuldu, Excel'e
  aktarıldı (dosya yapısı/stil doğrulandı), bir gerçek `.xlsx` dosyası
  içeriden inşa edilip gerçek dosya-yükleme yolundan (`kalemExcelYukle`)
  geçirildi: 1 güncelleme + 1 değişiklik-yok + 1 yeni satır doğru
  sınıflandırıldı, "Güncelleme + Yeni Kayıt" modunda gerçekten uygulandı
  — Supabase'de doğrudan sorgulanarak miktar güncellemesi VE yeni kaydın
  oluşumu doğrulandı. Ayrı bir sınıflandırma testinde hata/mükerrer/
  bulunamadı sınıfları da doğrulandı, hata raporu indirme doğru
  sütun/satırları üretti. `excel_import_gecmisi` RLS nedeniyle yazılamadı
  (bilinen kalıp, ayrı SQL hazırlandı) — kod bunu doğru şekilde
  loglayıp devam etti.
- [x] **Step 2: Kilit testi** — ayrı bir `asama='cost'` talebiyle
  doğrulandı: `kalemExcelUygula` çağrıldığında hiçbir satır yazılmadı
  (miktar değişmeden kaldı).
- [x] **Step 3: Temizlik** — tüm test talepleri/kalemleri Supabase'den
  silindi, 0 kayıt kaldığı doğrulandı.
- [x] **Step 4: Kullanıcıya rapor** — bkz. oturum sonu özeti.
