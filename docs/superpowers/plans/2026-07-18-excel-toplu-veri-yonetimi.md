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

- [ ] **Step 1: Kullanıcıya SQL'i ver, Supabase SQL Editor'de çalıştırmasını iste**

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

- [ ] **Step 2: Doğrula** — kullanıcı çalıştırdıktan sonra, iki tabloya
  basit bir test POST'u ile (curl) yazılabildiğini doğrula, sonra test
  satırlarını sil.

---

### Task 2: `ortak-excel.js` — export + sütun stil

**Files:**
- Create: `D:\erp\ortak-excel.js`

**Interfaces:**
- Produces: `excelSablonIndir(spec, veriler, dosyaAdi)` — Task 6'nın
  `kalemExcelAktar()`'ı bunu çağırır.

- [ ] **Step 1: `excelSablonIndir` yaz** — `loadXlsxLib()` çağırır,
  `spec`'e göre başlık satırı üretir (gizli alanlar hariç), `veriler`i
  satırlara döker, `XLSX.utils.aoa_to_sheet` + hücre stilleri
  (`mal-kabul-v2.html`'in `buildMkFormuXlsx`/`setRangeStyle` deseni:
  kilitli sütun gri dolgu, zorunlu sütun başlığı sarı dolgu,
  `izinliDegerler` varsa başlık hücresine not/comment), `XLSX.writeFile`.
- [ ] **Step 2: Commit**

```bash
git -c user.name="mehmetaraz0" -c user.email="mehmetaraz868@gmail.com" add ortak-excel.js
git -c user.name="mehmetaraz0" -c user.email="mehmetaraz868@gmail.com" commit -m "feat: ortak-excel.js — Excel şablon dışa aktarma (excelSablonIndir)"
```

---

### Task 3: `ortak-excel.js` — oku + sınıflandır

**Files:**
- Modify: `D:\erp\ortak-excel.js`

**Interfaces:**
- Produces: `excelDosyaOku(file)`, `excelSatirlariSiniflandir(spec,
  satirlar, mevcutKayitlar, opts)` — Task 6'nın `kalemExcelYukle()`'i
  bunları sırayla çağırır.

- [ ] **Step 1: `excelDosyaOku` yaz** — `talepExcelYukle` ile aynı
  `FileReader.readAsArrayBuffer`+`XLSX.read(...,{type:'array',raw:false})`+
  `XLSX.utils.sheet_to_json(ws,{raw:false})` deseni, Promise döner.
- [ ] **Step 2: `excelSatirlariSiniflandir` yaz** — her satır için:
  gizli ID sütunu doluysa `mevcutKayitlar` içinde id ile ara (yoksa
  `bulunamadi`); boşsa doğal anahtar (`urun_kodu`||`urun_adi`) ile ara
  (bulunursa `guncelleme` — alan alan karşılaştırıp hiç fark yoksa
  `degisiklik_yok`; bulunamazsa `yeni`); dosya içinde aynı doğal anahtar
  ikinci kez görülürse `mukerrer`. Zorunlu alan boşsa / `miktar`
  `parseFloat`+`isNaN` başarısızsa `hata`. `opts.fkKontrol` (caller'ın
  verdiği `Set<urun_kodu>`) varsa ve `urun_kodu` sette değilse `hata`.
  Her satır için `{satirNo,ham,alanlar,sinif,hatalar[],eskiDeger,
  yeniDeger}` döner.
- [ ] **Step 3: Commit**

```bash
git -c user.name="mehmetaraz0" -c user.email="mehmetaraz868@gmail.com" add ortak-excel.js
git -c user.name="mehmetaraz0" -c user.email="mehmetaraz868@gmail.com" commit -m "feat: ortak-excel.js — Excel okuma ve satır sınıflandırma"
```

---

### Task 4: `ortak-excel.js` — önizleme/diff modalı

**Files:**
- Modify: `D:\erp\ortak-excel.js`

**Interfaces:**
- Produces: `ensureExcelOnizlemeModal()`, `excelOnizlemeGoster(siniflandirma,
  opts)` — Task 6'nın `kalemExcelYukle()`'i sınıflandırmadan sonra çağırır.

- [ ] **Step 1: `ensureExcelOnizlemeModal` yaz** — `#mExcelOnizleme` DOM'da
  yoksa, `theme.css`'in `.mo`/`.mbox`/`.mtitle`/`.chip`/`.btn` sınıflarını
  kullanan bir `<div>` bloğunu `document.body`'ye ekler (idempotent — ikinci
  çağrıda no-op).
- [ ] **Step 2: `excelOnizlemeGoster` yaz** — sınıf başına sayaç (chip'lerle),
  satır satır tablo (sınıf rengi + eski/yeni değer yan yana, `hata` satırları
  için `hatalar[]` metni), mod `<select>` (5 seçenek), "Herhangi Bir Hatada
  Tümünü İptal Et" seçiliyken ve en az 1 `hata` satırı varsa Uygula butonu
  `disabled`; "Hatalıları Atla" seçiliyken Uygula'ya basılınca
  `confirm('N satır hata nedeniyle atlanacak, devam?')`. Uygula, caller'ın
  verdiği `opts.onUygula(mod, satirlar)` callback'ini çağırır.
- [ ] **Step 3: Commit**

```bash
git -c user.name="mehmetaraz0" -c user.email="mehmetaraz868@gmail.com" add ortak-excel.js
git -c user.name="mehmetaraz0" -c user.email="mehmetaraz868@gmail.com" commit -m "feat: ortak-excel.js — önizleme/diff modalı"
```

---

### Task 5: `ortak-excel.js` — toplu yaz + denetim + hata raporu

**Files:**
- Modify: `D:\erp\ortak-excel.js`

**Interfaces:**
- Produces: `excelTopluYaz(tabloAdi, satirlar, {onConflict, batchSize})`,
  `excelImportGecmisiYaz(...)`, `excelHataRaporuIndir(spec, hatalilar,
  dosyaAdi)` — Task 6'nın `kalemExcelUygula()`'i bunları sırayla çağırır.

- [ ] **Step 1: `excelTopluYaz` yaz** — `satirlar`'ı `batchSize` (varsayılan
  500) gruplara böler, her grubu tek dizi-body POST ile
  `SB_URL+'/rest/v1/'+tabloAdi+'?on_conflict='+onConflict` +
  `Prefer: resolution=merge-duplicates` ile yazar (`saveLnSiparisler`
  deseni). Her grup için ayrı try/catch, `{basariliGrup,hataliGrup,
  toplamYazilan}` döner — grup içi atomik, gruplar arası DEĞİL (bu
  fonksiyonun dokümantasyon yorumunda açıkça belirtilir).
- [ ] **Step 2: `excelImportGecmisiYaz` yaz** — `excel_import_gecmisi`'ye
  bir header POST'u (`Prefer: return=representation` ile id al), sonra
  `excel_import_satirlari`'na tüm satırları TEK dizi-body POST'u ile yaz
  (`talep_onay_gecmisi` yazma deseniyle tutarlı try/catch + `console.error`
  ile başarısızlığı yüzeye çıkar — sessizce yutma).
- [ ] **Step 3: `excelHataRaporuIndir` yaz** — `excelSablonIndir`
  makinesini yeniden kullanır, `spec`'e `Hata Açıklaması` sütunu ekler,
  sadece `hata`/`bulunamadi`/`mukerrer` satırlarını içerir.
- [ ] **Step 4: Commit**

```bash
git -c user.name="mehmetaraz0" -c user.email="mehmetaraz868@gmail.com" add ortak-excel.js
git -c user.name="mehmetaraz0" -c user.email="mehmetaraz868@gmail.com" commit -m "feat: ortak-excel.js — toplu yazma, denetim kaydı, hata raporu"
```

---

### Task 6: satin-alma.html pilot entegrasyonu

**Files:**
- Modify: `D:\erp\satin-alma.html`

- [ ] **Step 1: `<head>`'e ekle** — `<script src="ortak-excel.js"></script>`,
  `ortak.js`'den hemen sonra.
- [ ] **Step 2: `openTalepDetay()`'e yeni buton** (satır ~926-978) —
  `t.durum==='bekleyen'&&t.asama==='depo'` koşullu, mevcut
  `t.durum==='onaylandi'` bloğundan (971-975) AYRI yeni bir blok: "📊 Excel
  ile Kalem Yönetimi" butonu → `kalemExcelAktar(id)`.
- [ ] **Step 3: `kalemExcelSablonSpec` const'ı tanımla** — `[{alan:'id',
  baslik:'Sistem ID',tip:'text',kilitli:true,gizli:false},{alan:'urun_kodu',
  baslik:'Ürün Kodu',tip:'text',zorunlu:false},{alan:'urun_adi',
  baslik:'Ürün Adı',tip:'text',zorunlu:true},{alan:'miktar',
  baslik:'Miktar',tip:'number',zorunlu:true},{alan:'birim',
  baslik:'Birim',tip:'text',zorunlu:true}]` (id gizli değil ama kilitli —
  kullanıcı görür, düzenleyemez biçimde renklenir).
- [ ] **Step 4: `kalemExcelAktar(talepId)` yaz** — `DB.talepler[talepId].
  satirlar`'ı `spec` alanlarına döker, `excelSablonIndir(kalemExcelSablonSpec,
  veriler, 'talep-kalemleri-'+talepId.slice(0,8)+'-'+tarih+'.xlsx')` çağırır.
- [ ] **Step 5: `kalemExcelYukle(event,talepId)` yaz** — `excelDosyaOku`,
  ardından canlı `urunler` tablosunu çek (`select=kod,ad,birim`), bir
  `Set(kod)` oluştur, `excelSatirlariSiniflandir(spec, satirlar,
  DB.talepler[talepId].satirlar, {fkKontrol:kodSet})` çağırır,
  `ensureExcelOnizlemeModal()`+`excelOnizlemeGoster(sonuc,
  {onUygula:(mod,satirlar)=>kalemExcelUygula(talepId,mod,satirlar)})`.
- [ ] **Step 6: `kalemExcelUygula(talepId,mod,satirlar)` yaz** — mod'a
  göre filtrelenmiş satırları hazırlamadan ÖNCE canlı GET
  (`satin_alma_talepleri?id=eq.<talepId>&select=durum,asama`); `bekleyen`+
  `depo` değilse `toast('⚠️ Talep artık düzenlenebilir durumda değil,
  aktarım iptal edildi')` + return (hiçbir satır yazılmaz). Geçtiyse
  `excelTopluYaz('satin_alma_talep_kalemleri', ..., {onConflict:'id'})`
  (id'si olan satırlar için) + ayrı bir POST (id'si olmayan yeni satırlar
  için, `talep_id` eklenerek) — `excelImportGecmisiYaz(...)` — sonunda
  `await loadDB(); openTalepDetay(talepId);` (mevcut `talepKararVer`'in
  yenileme deseniyle tutarlı).
- [ ] **Step 7: Tarayıcıda test** — Uçtan uca doğrulama planındaki
  senaryoyu çalıştır (bkz. design doc Test/doğrulama planı).
- [ ] **Step 8: Commit**

```bash
git -c user.name="mehmetaraz0" -c user.email="mehmetaraz868@gmail.com" add satin-alma.html
git -c user.name="mehmetaraz0" -c user.email="mehmetaraz868@gmail.com" commit -m "feat: İç Talepler kalemleri için Excel toplu düzenleme pilotu"
```

---

### Task 7: Uçtan uca doğrulama + rapor

- [ ] **Step 1: Tam senaryo** — `bekleyen`+`depo` bir talep aç → kalemleri
  Excel'e aktar → Excel'de bir satırın miktarını değiştir, yeni bir satır
  ekle, bir satırın ürün kodunu boz, bir satırı çoğalt → geri yükle →
  önizlemede 4 sınıfın (güncelleme/yeni/hata/mükerrer) doğru göründüğünü
  kontrol et → "Güncelleme + Yeni Kayıt" modunda uygula →
  `satin_alma_talep_kalemleri`'nin doğru güncellendiğini, `excel_import_
  gecmisi`/`satirlari`'nın dolduğunu curl ile doğrula, hata raporunu indir.
- [ ] **Step 2: Kilit testi** — talebi cost aşamasına ilerlet, kalem-Excel
  butonunun kaybolduğunu doğrula; eski indirilmiş bir dosyayı tekrar
  yüklemeyi dene, tüm aktarımın iptal edildiğini (hiçbir satırın
  yazılmadığını) doğrula.
- [ ] **Step 3: Temizlik** — test için oluşturulan talep/kalem/import-
  geçmişi kayıtlarını sil.
- [ ] **Step 4: Kullanıcıya rapor** — Faz 2 önerisi (hangi tablolar
  sırada, undo UI, büyük dosya sertleştirmesi, kolon-eşleştirme modalının
  çıkarılması).
