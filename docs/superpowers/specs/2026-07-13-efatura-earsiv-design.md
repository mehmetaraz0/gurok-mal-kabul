# e-Fatura / e-Arşiv Entegrasyonu — Tasarım

## Problem / Hedef

GİB onaylı bir entegratör olmadan kesilen fatura yasal geçerliliğe sahip
değil. `muhasebe-faturalar.html`'de şu an tamamen dahili, GİB'e hiç
bağlanmayan bir fatura kayıt sistemi var (`faturalar` + `fatura_kalemleri`
tabloları, sadece muhasebe takibi amaçlı). Bu tasarım, gerçek bir GİB
onaylı entegratör (Paraşüt/Logo/Foriba/İzibiz/Uyumsoft vb.) API'si henüz
temin edilmediği için **simülasyon modunda çalışan, ama gerçek API
geldiğinde tek dosya değişikliğiyle devreye alınabilecek** bir e-Fatura/
e-Arşiv gönderim ve alım katmanı kurar.

## Kapsam

- **Giden (satış):** Bizim kestiğimiz satış faturalarının entegratöre
  gönderilmesi, ETTN/GİB fatura no takibi, e-Fatura/e-Arşiv ayrımı.
- **Gelen (alış):** Tedarikçilerden gelen e-faturaların entegratör
  API'sinden çekilip sisteme otomatik alış faturası taslağı olarak
  düşürülmesi.
- **Simülasyon modu:** Gerçek API anahtarı olmadığı için adapter katmanı
  şu an sahte veriler üretir; ekranda açıkça "SİMÜLASYON MODU" etiketiyle
  belirtilir.

## Kapsam dışı

- Gerçek entegratör API'sine bağlanma — API anahtarı/hesabı temin
  edildiğinde ayrı bir iş olarak `efatura-adapter.js` içi değiştirilecek.
- e-Defter (Yevmiye/Kebir XML, berat) — ayrı bir tasarım/spec konusu.
- Mali mühür/e-imza entegrasyonu — entegratör API'si üzerinden hallediliyor
  varsayılıyor, bizim tarafımızda kriptografik imzalama yok.
- Fatura PDF'inin bizim tarafımızda üretilmesi — PDF entegratörden gelir
  (`gib_pdf_url`), biz üretmiyoruz.

## Mimari

Yeni, paylaşılan bir modül: **`efatura-adapter.js`** (repo kökü,
`auth-guard.js` ile aynı yükleme deseni — `<script src="efatura-adapter.js"></script>`).
Dış dünyaya iki fonksiyon sunar:

```js
// fatura: camelCase fatura nesnesi (kalemler dahil), cari: camelCase cari nesnesi
// Döner: {basarili:bool, ettn, gibFaturaNo, pdfUrl, hataMesaji}
async function eFaturaGonder(fatura, cari)

// sonCekimTarihi: ms epoch veya null (ilk çekim)
// Döner: [{ettn, gibFaturaNo, gonderenVkn, gonderenAd, tarih, kalemler:[{kod,ad,miktar,birim,birimFiyat,kdvOran,toplam}], araToplam, kdvToplam, genelToplam}]
async function eFaturaGelenleriCek(sonCekimTarihi)
```

Dosyanın en üstünde: `const EFATURA_SIMULASYON=true;`. Bu `true` olduğu
sürece her iki fonksiyon da gerçek ağ çağrısı yapmaz, `setTimeout` ile
1.5sn gecikme simüle eder ve sahte veri üretir (`eFaturaGonder`: `crypto.randomUUID()`
ile ETTN, `%10` ihtimalle `{basarili:false,hataMesaji:'Simüle hata: ...'}`;
`eFaturaGelenleriCek`: rastgele 0-2 sahte gelen fatura üretir). Gerçek API
entegre edildiğinde `EFATURA_SIMULASYON=false` yapılır ve fonksiyon
gövdeleri gerçek `fetch()` çağrılarıyla değiştirilir — **çağıran taraf
(`muhasebe-faturalar.html`) hiç değişmez**, çünkü arayüz (giriş/çıkış
şekli) sabit kalıyor.

## Veri modeli (Supabase)

`faturalar` tablosuna yeni kolonlar (hepsi TEXT/nullable, mevcut `durum`
enum'ına dokunulmuyor — `durum` ödeme/onay durumunu, yeni kolonlar GİB
gönderim durumunu tutar, iki kavram birbirine karışmıyor):

| Kolon | Tip | Açıklama |
|---|---|---|
| `efatura_durum` | text, null | `taslak / gonderiliyor / gonderildi / onaylandi / reddedildi / iptal` — null = süreç hiç başlamadı (eski kayıtlar, alış faturaları) |
| `efatura_tip` | text, null | `e-fatura` veya `e-arsiv` |
| `ettn` | text, null | Entegratörden dönen ETTN |
| `gib_fatura_no` | text, null | Entegratörden dönen resmi fatura no |
| `gib_pdf_url` | text, null | Entegratörden dönen PDF linki |
| `efatura_gonderim_tarihi` | timestamptz, null | Gönderim anı |
| `efatura_hata_mesaji` | text, null | Son hata mesajı (varsa) |

Yeni tablo **`gelen_efaturalar`**:

| Kolon | Tip |
|---|---|
| `id` | uuid, PK, default gen_random_uuid() |
| `ettn` | text |
| `gonderen_vkn` | text |
| `gonderen_ad` | text |
| `tarih` | date |
| `kalemler` | jsonb |
| `ara_toplam`, `kdv_toplam`, `genel_toplam` | numeric |
| `durum` | text — `yeni` / `islendi` |
| `alis_fatura_id` | uuid, null — otomatik oluşturulan taslak alış faturasına referans |
| `olusturma_tarihi` | timestamptz, default now() |

Bu iki şema değişikliği (`ALTER TABLE faturalar ADD COLUMN ...` ve
`CREATE TABLE gelen_efaturalar ...`) kullanıcı tarafından Supabase SQL
Editor'de çalıştırılacak — uygulama planı bu SQL'i tam metin olarak
içerecek.

## Satış akışı (giden e-Fatura/e-Arşiv)

Satış faturası detay ekranında (`openFaturaDetay`, `muhasebe-faturalar.html:551`
civarı), mevcut ödeme durumu chip'inin altına yeni bir blok eklenir:

- **"⚠️ SİMÜLASYON MODU — gerçek GİB gönderimi yok"** şeridi (sabit,
  `EFATURA_SIMULASYON===true` iken görünür).
- Cari `efatura_mukellefi==='evet'` ise **"📤 e-Fatura Gönder"**, değilse
  **"📤 e-Arşiv Gönder"** butonu (etiket otomatik, `cari.efatura` alanına
  göre).
- Buton sadece `tur==='satis'` faturalarında görünür (alış faturalarında
  hiç gösterilmez — biz onları kesmiyoruz, sadece kaydediyoruz).
- Tıklanınca: `efatura_durum='gonderiliyor'` PATCH edilir → `eFaturaGonder()`
  çağrılır → başarılıysa `efatura_durum='gonderildi'`, `ettn`,
  `gib_fatura_no`, `gib_pdf_url`, `efatura_gonderim_tarihi` yazılır ve
  `showToast('✅ e-Fatura gönderildi (simülasyon)')`; başarısızsa
  `efatura_durum='reddedildi'`, `efatura_hata_mesaji` yazılır ve hata
  toast'ı gösterilir.
- Durum chip'i: 📝 Taslak / ⏳ Gönderiliyor / ✅ Gönderildi / ✔️ Onaylandı /
  ❌ Reddedildi / 🚫 İptal.
- `efatura_durum==='gonderiliyor'` durumu 2 dakikadan eskiyse (`efatura_gonderim_tarihi`
  ile karşılaştırılarak), ekranda "Gönderim takıldı mı? Tekrar Dene"
  butonu gösterilir — sayfa kapanıp yarıda kalan gönderimlerin kilitlenmesini
  önler.
- `onaylandi` ve `iptal` durumları bu iterasyonda UI'dan set edilmez —
  entegratörün alıcı onayı/iptal bildirimini geri bildirmesi (webhook veya
  polling) gerektirir, bu gerçek API entegrasyonu aşamasında ele alınacak.
  Şimdilik enum'da yer tutuyorlar ki gerçek API bağlanınca kolon şeması
  değişmesin.

## Alış akışı (gelen e-fatura kutusu)

`muhasebe-faturalar.html`'e yeni bir sekme: **"📥 Gelen e-Fatura Kutusu"**.

- **"🔄 Yeni e-Fatura Kontrol Et"** butonu `eFaturaGelenleriCek(sonCekimTarihi)`
  çağırır (`sonCekimTarihi`: `gelen_efaturalar`'daki en son `olusturma_tarihi`,
  localStorage'da da tutulur ki farklı cihazlardan tutarlı davransın).
- Dönen her kayıt `gelen_efaturalar`'a `durum='yeni'` olarak yazılır, AYNI
  ANDA otomatik olarak `faturalar`+`fatura_kalemleri`'ye `tur='alis'`,
  `durum='taslak'` bir kayıt oluşturulur:
  - Cari eşleştirme: `gonderen_vkn` ile `cariler.vkn` aranır. Eşleşme
    varsa `cari_id`/`cari_ad` doldurulur. Eşleşme yoksa `cari_id=null`,
    `cari_ad=gonderenAd`, ve `not_alani='⚠️ Cari eşleşmedi, VKN: '+gonderenVkn`
    yazılır.
  - `gelen_efaturalar.alis_fatura_id` yeni oluşan `faturalar.id`'ye
    işaretlenir, `gelen_efaturalar.durum='islendi'` yapılır.
- Kullanıcı bu taslakları **mevcut** "Alış Faturaları" sekmesinde
  `durum==='taslak'` filtresiyle görür ve var olan 3-way-match/onay
  akışıyla işler — ayrı bir onay ekranı YOK, mevcut akış aynen kullanılır.
- Gelen kutusu sekmesi sadece referans/log amaçlı: hangi ETTN'in hangi
  alış faturasına dönüştüğünü gösterir, tekrar işlem yapılmaz.

## Hata yönetimi

- Adapter `{basarili:false, hataMesaji}` dönerse: fatura `reddedildi`
  durumuna geçer, kullanıcı hata mesajını görür, aynı butona tekrar
  basarak yeniden deneyebilir (idempotent — her deneme yeni bir
  `efatura_durum='gonderiliyor'` PATCH'iyle başlar).
- Ağ hatası (fetch reddi) da aynı şekilde `hataMesaji` alanına yazılıp
  `reddedildi` yapılır — try/catch ile adapter içinde yakalanır, çağıran
  tarafa hep `{basarili:false,...}` şeklinde düz bir sonuç döner (asla
  exception fırlatmaz).
- Gelen kutusu çekiminde bir kalemde cari eşleşmesi başarısız olsa bile
  diğer kalemlerin işlenmesi durdurulmaz (her gelen fatura bağımsız işlenir).

## Test/doğrulama planı

Statik: `efatura-adapter.js`'in iki fonksiyonunun da belirtilen dönüş
şeklini ürettiğini, `EFATURA_SIMULASYON` bayrağının doğru yerde
kontrol edildiğini kod okuyarak doğrulamak. Fonksiyonel: kullanıcı
tarafından — bir satış faturasında "e-Fatura Gönder" butonuna basıp
simüle ETTN/GİB no'nun ekrana yazıldığını, "Yeni e-Fatura Kontrol Et"
butonuna basıp sahte gelen faturanın Alış Faturaları > Taslak filtresinde
göründüğünü doğrulamak. Node/Python bu ortamda yok, otomatik test yazılamıyor.
