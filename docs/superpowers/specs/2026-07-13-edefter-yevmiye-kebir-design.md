# e-Defter (Yevmiye + Kebir XML) — Tasarım

## Problem / Hedef

Yevmiye ve Kebir defterinin GİB formatında elektronik (XML) tutulması
yasal bir zorunluluk. `muhasebe-yevmiye.html`'de zaten tam bir manuel
Yevmiye Fişi + Defteri Kebir + Mizan sistemi var (`yevmiye_fisler`,
`yevmiye_kalemleri`, `hesap_plani` tabloları), ama bu veri hiçbir zaman
GİB'in beklediği XBRL-GL tabanlı XML formatına dönüştürülmüyor.

## Araştırma bulguları (gerçek kaynaklardan doğrulanmış)

GİB e-Defter, XBRL Global Ledger (XBRL-GL) taksonomisi üzerine kurulu.
Gerçek Schematron doğrulama kurallarını (resmi hata kodlarıyla, örn.
11601-11635) inceleyerek şu kesin yapıyı doğruladık:

```
edefter:defter                          (kök eleman, namespace http://www.edefter.gov.tr)
  ds:Signature                          (ZORUNLU — XML dijital imza, mali mühür/e-imza ile atılır)
  xbrli:xbrl
    xbrli:context/xbrli:entity/xbrli:identifier   (VKN, 10 haneli)
    xbrli:unit                          (en az 1)
    gl-cor:accountingEntries
      gl-cor:documentInfo
        gl-cor:entriesType              ('journal' yevmiye / 'ledger' kebir)
        gl-cor:uniqueID                 ('YEV'/'KEB' ile başlar, 11 veya 13 karakter)
        gl-cor:creationDate
        gl-cor:periodCoveredStart / periodCoveredEnd
        gl-bus:sourceApplication
      gl-cor:entityInformation
        gl-bus:entityPhoneNumber/phoneNumber
        gl-bus:entityEmailAddressStructure/entityEmailAddress
        gl-bus:organizationIdentifiers  (Kurum Unvanı VEYA Adı Soyadı; opsiyonel Şube No+Şube Adı çifti)
        gl-bus:organizationAddress      (bina no, sokak, şehir, posta kodu, ülke)
        gl-bus:entityWebSite/webSiteURL
        gl-bus:businessDescription
        gl-bus:fiscalYearStart / fiscalYearEnd
        gl-bus:accountantInformation/accountantName, accountantEngagementTypeDescription
      gl-cor:entryHeader  (× N — her muhasebe fişi/hesap için tekrarlanır)
        gl-cor:entryNumber              (fiş no, örn. "YEV-2026-00001")
        gl-cor:entryNumberCounter       (1'den başlayan ardışık tam sayı)
        gl-cor:enteredBy / enteredDate
        gl-bus:totalDebit / totalCredit (birbirine eşit olmalı)
        gl-cor:entryDetail  (× M, en az 2 tane)
          gl-cor:lineNumber / lineNumberCounter
          gl-cor:account/accountMainID (3-4 karakter), accountMainDescription
          gl-cor:amount (>0), debitCreditCode, postingDate
          gl-cor:documentType, documentNumber, documentDate, documentReference (=entryNumber)
```

**Kritik kısıt:** `ds:Signature` bloğu dosyanın kendi içinde olmak
zorunda ve mali mühür/e-imza özel anahtarıyla imzalanıyor (XML-DSig +
XAdES). Bu, tarayıcı JS'inde yapılamaz — donanım/sertifika erişimi
gerektirir. Bu nedenle bu özellik **imzasız içerik üretir**, imzalama
adımı harici bir araca (lisanslı e-Defter yazılımı / mali müşavir)
bırakılır — `docs/superpowers/specs/2026-07-13-efatura-earsiv-design.md`'deki
mali mühür kısıtıyla aynı mantık.

## Kapsam

- Yevmiye XML üretimi (seçilen ay + otel).
- Kebir XML üretimi (seçilen ay + otel), hesap bazında borç/alacak
  toplamlarıyla.
- Kurum Bilgileri paneli (VKN, unvan, adres, iletişim, mali yıl,
  muhasebeci — bir kere girilir; otel bazında Şube No/Şube Adı).
- Dışa aktarmadan önce GİB'in gerçek Schematron kurallarının JS
  karşılığıyla veri doğrulama.

## Kapsam dışı

- `ds:Signature` üretimi/imzalama — mali mühür/e-imza donanımı
  gerektirir, bu ortamda yapılamaz. Çıktı açıkça "imzasız taslak"
  olarak işaretlenir.
- Beratın GİB'e fiilen yüklenmesi/gönderilmesi — kullanıcının/mali
  müşavirin sorumluluğunda.
- Gerçek bir Schematron/XSD validatörüyle doğrulama — böyle bir araç bu
  ortamda yok; sadece incelenen kuralların JS karşılığı uygulanır,
  "sertifikalı uyum" iddiası yapılmaz.
- Alt hesap (`accountSub`) desteği — mevcut sistemde hiç kullanılmıyor
  (tüm `hesap_kodu` değerleri düz 3 haneli), GİB şeması da bunu
  opsiyonel kabul ediyor, bu yüzden hiç üretilmiyor.
- Otel/şirket ayrımı: tek şirket, iki şube (810 Manavgat, 811 Sorgun) —
  ayrı VKN yok, kullanıcı onayıyla netleşti.

## Veri modeli (Supabase)

Yeni tablo **`edefter_kurum_bilgileri`** (tek satır, şirket geneli):

| Kolon | Tip |
|---|---|
| `id` | uuid, PK |
| `vkn` | text (10 haneli) |
| `unvan` | text (Kurum Unvanı) |
| `adres_bina_no`, `adres_sokak`, `adres_sehir`, `adres_posta_kodu`, `adres_ulke` | text |
| `telefon`, `eposta`, `website` | text |
| `is_tanimi` | text (businessDescription) |
| `mali_yil_baslangic`, `mali_yil_bitis` | date |
| `muhasebeci_ad`, `muhasebeci_unvan` | text (accountantName, accountantEngagementTypeDescription) |

Yeni tablo **`edefter_sube_bilgileri`** (otel başına bir satır):

| Kolon | Tip |
|---|---|
| `otel_id` | text, PK ('810'/'811') |
| `sube_no`, `sube_adi` | text |

## XML Üretim Mantığı

**Ortak alanlar** (hem Yevmiye hem Kebir için): `entityInformation`
bloğu `edefter_kurum_bilgileri` + seçilen otelin `edefter_sube_bilgileri`
satırından doldurulur. `uniqueID` = `'YEV'`/`'KEB'` + VKN (13 karakter).
`periodCoveredStart`/`End` = seçilen ayın ilk/son günü.

**Yevmiye:** Seçilen ay+otele ait, `onaylandi=true` olan
`yevmiye_fisler` `enteredDate`'e göre sıralanır, her biri bir
`entryHeader` olur (1'den başlayan ardışık `entryNumberCounter`).
Fişin `kalemler`i (en az 2 tane olmalı — dengeli kayıt) `entryDetail`
olur; `account/accountMainID` = `hesap_kodu` (zaten 3 haneli),
`accountMainDescription` = `hesap_plani`'ndan karşılığı.

**Kebir:** Aynı ay+otel kapsamındaki tüm kalemler `hesap_kodu`'na göre
gruplanır; her hesap bir `entryHeader` olur, o hesabın ay içindeki her
hareketi bir `entryDetail` olarak eklenir (borç/alacak toplamları
`entryHeader` seviyesinde hesaplanır). Kebir'de `entryHeader` bir fişi
değil bir hesabı temsil ettiği için: `entryNumber` = hesap kodu (örn.
"320"), `entryNumberCounter` = hesapların sıralamadaki ardışık numarası.
Her `entryDetail`'in `documentReference`'ı kendi kaynak fişinin no'suna
(`entryHeader.entryNumber`'a değil, hareketin geldiği yevmiye fişinin
no'suna) işaret eder — bu durumda 11634 kuralı ("documentReference =
parent entryNumber") Kebir bağlamında uygulanamaz, çünkü Kebir'in
entryHeader'ı zaten bir fiş değil; bu satırlarda `documentReference`
alanı bilgi amaçlı bırakılır, kural sadece Yevmiye'de zorunlu tutulur.

## Doğrulama (dışa aktarmadan önce)

İncelenen gerçek Schematron kurallarının doğrudan karşılığı olarak, JS
tarafında şu kontroller yapılır — biri bile başarısız olursa üretim
durdurulur ve hangi fişte/hesapta sorun olduğu listelenir:

- Her fişte `toplamBorc === toplamAlacak` (kuruşa kadar, `round2` ile).
- Her fişte en az 2 kalem var.
- Yevmiye tarihleri seçilen ay aralığında.
- `hesap_kodu` 3-4 karakter uzunluğunda.
- Kurum Bilgileri panelindeki zorunlu alanlar (VKN, unvan, adres, mali
  yıl, muhasebeci) doldurulmuş.
- Seçilen ay için `onaylandi=false` (taslak) fiş varsa, bunlar XML'e
  dahil edilmez ama kullanıcıya "N taslak fiş XML'e dahil edilmedi"
  uyarısı gösterilir (durdurmaz, sadece bilgilendirir).
- Seçilen ayın `mali_donemler` durumu 'kapali' değilse, kullanıcıya
  uyarı gösterilir (durdurmaz — dönem kapatma bu özelliğin kapsamı
  dışında, sadece bilgilendirme amaçlı).

## Dosya adlandırma ve indirme

`yevmiye-<VKN>-<YYYYAA>-imzasiz.xml` / `kebir-<VKN>-<YYYYAA>-imzasiz.xml`
— dosya adında açıkça "imzasiz" ibaresi bulunur.

## Test/doğrulama planı

Statik: XML alan eşlemelerinin yukarıdaki şemayla birebir eştiğini kod
okuyarak doğrulamak; JS doğrulama kurallarının incelenen Schematron
kurallarıyla (11601-11635 aralığındakiler) tutarlı olduğunu karşılaştırmak.
Gerçek GİB Schematron/XSD validatörüyle test edilemiyor (bu ortamda yok)
— kullanıcıya bu sınır açıkça bildirilir, üretilen XML mutlaka bir mali
müşavir veya lisanslı e-Defter yazılımı ile son kontrolden geçmelidir.
