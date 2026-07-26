# Satın Alma Teklif Yönetimi (RFQ) — Tasarım

## Problem / Hedef

Şu an "teklif" süreci sistemin dışında yürüyor: `spYazdir()` boş bir
"Teklif Fiyatı" sütunu olan sipariş formu basıyor, `spMail()` firmaya
`mailto:` ile bir taslak açıyor — ikisi de tek yönlü. Firmadan gelen fiyat
telefon/mail ile geri geliyor ve personel bunu tek bir `tahminiFiyat`
alanına elle yazıyor. Birden fazla firmadan teklif alıp karşılaştırmak,
en uygun olanı seçmek için hiçbir ekran yok — bu, depo/satın alma
kıyaslama bulgularında tespit edilen bir eksiklik.

Hedef: İç Talep'ten seçilen kalemler için birden fazla firmadan alınan
fiyatları sisteme kaydedip yan yana karşılaştırabilmek, kalem bazında en
uygun firmayı seçip mevcut sipariş oluşturma akışına (`SP_SATIRLAR` →
`spKaydet()`/grup listesi) sorunsuz aktarabilmek.

## Kullanıcı kararları (bu oturumda alındı)

- **Teklif girişi manuel**: Firma sisteme login olup kendi teklifini
  girmiyor (tedarikçi portalı yok). Personel, telefon/mail ile aldığı
  fiyatı elle giriyor — `spMail()`'deki gibi mailto taslağı teklif isteği
  için kullanılabilir ama yanıt toplama otomatik değil.
- **Karşılaştırma kalem bazında**: Tek bir teklif talebindeki farklı
  ürünler, farklı firmalara bölünebilir (örn. domates A firmasından, et B
  firmasından) — "tüm kalemler tek firmaya" zorunluluğu yok.
- **Minimum teklif sayısı: açık/ertelendi.** Kaç firmadan teklif alınması
  gerektiğine dair bir kural (örn. "en az 2 teklif olmadan sipariş
  oluşturulamaz") bu tasarımın kapsamında DEĞİL — kullanıcı henüz karar
  vermedi. Şimdilik 0 teklifle de devam edilebilir; ileride ayrı bir
  iyileştirme olarak eklenebilir.

## Kapsam

- Yeni bir "🗂️ Teklif Toplama" sekmesi, `satin-alma.html`'ye eklenir.
- Onaylanmış İç Talep kalemlerinden (mevcut `YT_SATIRLAR`/talep verisi)
  veya serbest ürün seçiminden, bir "Teklif Talebi" oluşturulur
  (`teklif_talepleri` + `teklif_kalemleri`).
- Her teklif kalemi için, personel istediği kadar firma fiyatı ekler
  (`teklif_fiyatlari`) — firma, birim fiyat, opsiyonel not (vade, min.
  sipariş miktarı vb.).
- Karşılaştırma görünümünde her kalem için girilen tüm fiyatlar yan yana
  listelenir, en düşük fiyat otomatik vurgulanır ve varsayılan seçili
  gelir — kullanıcı isterse başka bir firmayı seçebilir (en ucuz her
  zaman doğru seçim olmayabilir: teslim süresi, geçmiş kalite notu vb.).
- "Seçilenlerden Sipariş Hazırla": her kalem için seçilen (firma, fiyat)
  çifti, mevcut `SP_SATIRLAR`'a firma/fiyat önceden doldurulmuş satırlar
  olarak yazılır — kullanıcı doğrudan var olan sipariş oluşturma/PDF/mail
  akışına (`spKaydet()`, `spPDF()`, `spMail()`) geçer. **Yeni bir sipariş
  oluşturma yolu icat edilmiyor, mevcut akışa bir üst kademe ekleniyor.**

## Kapsam dışı

- Tedarikçi portalı / firmaların kendi teklifini girmesi.
- Teklif isteği e-postalarının otomatik gönderimi ve yanıtların otomatik
  toplanması (OCR/e-posta ayrıştırma vb.) — bu proje henüz bir sunucu/cron
  altyapısına sahip değil.
- Minimum teklif sayısı zorunluluğu (yukarıda açıklandı, kullanıcı kararı
  bekleniyor).
- `FIRMA_DB`'nin (statik `gurok_veritabani.js` içindeki firma listesi)
  Supabase'e taşınması — mevcut referans şekli korunuyor: `teklif_fiyatlari.firma_id`
  `FIRMA_DB[].id`'ye işaret eder (DB seviyesinde foreign key DEĞİL, tıpkı
  `siparisler.firma_ad`'ın bugün yaptığı gibi serbest metin/id eşleşmesi).

## Veri Modeli (yeni tablolar — Supabase SQL Editor'de elle oluşturulmalı)

Bu proje build/migration aracı kullanmıyor; anon anahtarla `CREATE TABLE`
çalıştırılamaz. Aşağıdaki SQL, kullanıcı tarafından Supabase SQL Editor'e
yapıştırılıp çalıştırılmalı (Task 1'in bir parçası olarak ayrı bir dosyada
teslim edilecek):

```sql
create table teklif_talepleri (
  id uuid primary key default gen_random_uuid(),
  olusturma_tarihi timestamptz not null default now(),
  olusturan text not null,
  otel_id text,
  durum text not null default 'acik', -- acik | tamamlandi
  not_alani text
);

create table teklif_kalemleri (
  id uuid primary key default gen_random_uuid(),
  teklif_talebi_id uuid not null references teklif_talepleri(id),
  urun_kodu text,
  urun_adi text not null,
  miktar numeric not null,
  birim text not null,
  kaynak_ic_talep_kalemi_id uuid, -- ic_talep_kalemleri.id, nullable
  secilen_teklif_id uuid -- teklif_fiyatlari.id, kullanıcı seçimini tutar
);

create table teklif_fiyatlari (
  id uuid primary key default gen_random_uuid(),
  teklif_kalemi_id uuid not null references teklif_kalemleri(id),
  firma_id integer, -- FIRMA_DB[].id (DB FK değil)
  firma_ad text not null,
  birim_fiyat numeric not null,
  giris_tarihi timestamptz not null default now(),
  giren_kullanici text not null,
  not_alani text
);
```

## Mimari

`satin-alma.html`'de yeni bir sekme (`gTab('teklif',this)` deseniyle,
mevcut `fiyatKontrol` sekmesiyle aynı iskelet). Yeni fonksiyonlar:

- `loadTeklifTalepleri()` — `teklif_talepleri?select=*,teklif_kalemleri(*,teklif_fiyatlari(*))`
  ile hepsini tek sorguda çeker (mevcut `loadFiyatKontrol()`'deki iç içe
  `select` deseniyle aynı).
- `teklifTalebiOlustur(secilenIcTalepKalemleri)` — seçilen kalemlerden
  `teklif_talepleri` + `teklif_kalemleri` satırları yazar.
- `teklifFiyatiEkle(teklifKalemiId, firmaId, firmaAd, fiyat, not)` —
  `teklif_fiyatlari`'na bir satır ekler, UI'ı yeniden çizer.
- `enUcuzTeklifiSec(kalem)` — kalemin `teklif_fiyatlari` dizisinden
  `birim_fiyat` en düşük olanı bulur, varsayılan seçili işaretler
  (kullanıcı değiştirebilir, `teklif_kalemleri.secilen_teklif_id` PATCH'lenir).
- `teklifSiparisHazirla(teklifTalebiId)` — her kalemin seçili teklifini
  `SP_SATIRLAR`'a `{ad,kod,miktar,birim,firmaId,firmaAd,tahminiFiyat}`
  olarak dönüştürür (bugün `spEkle()`'nin elle doldurduğu alanların
  aynısı), sonra mevcut `renderSPSatirlar()`/sipariş sekmesine geçirir.

## Test/doğrulama planı

Statik: yeni fonksiyonların mevcut `SP_SATIRLAR` şemasıyla (firmaId,
firmaAd, tahminiFiyat alan adları) birebir uyduğunu, `spKaydet()`'in
değişiklik gerektirmediğini kod okuyarak doğrulamak. Gerçek uçtan uca
test (teklif talebi oluştur → 2-3 firma fiyatı gir → en ucuzu farklı bir
firmayla değiştir → sipariş hazırla → PDF/mail'in doğru firmaya gittiğini
gör) kullanıcı tarafından yapılacak — bu ortamda test çerçevesi yok.

---
**NOT (2026-07-26):** Bu tasarım, eski `satin-alma-teklifler.html` (4 tablolu,
doğrudan sipariş oluşturan RFQ) sürümünün YERİNE geçer. Eski sayfa + 4 tablo
(`teklif_talep_kalemleri`, `tedarikci_teklifler`, `tedarikci_teklif_kalemleri`
ve eski `teklif_talepleri`) emekliye ayrılıp yenisi temiz kurulacak (kullanıcı
onayı alındı).
