# MY-4 — Ön Büro rolleriyle rezervasyon/check-in kilidi: ayrı kapsam önerisi

**Durum: YALNIZ YERELDE UYGULANDI ve DOĞRULANDI.** Üretime, staging'e veya
herhangi bir gerçek projeye hiçbir SQL koşulmadı; push/deploy yok. Canlı rol
erişimi hâlâ verilmedi.

Uygulama dosyası: `docs/kurulum/2026-10-06-pms-rol-entegrasyon-kilit.sql`
Doğrulama: `scripts/pms-rol-entegrasyon.test.mjs` — **53 geçti / 0 kaldı**
(kırmızı faz + yeşil faz aynı dosyada kalıcı).

Giriş/çıkış akışının **davranışı** değişmedi: aynı kontroller, aynı kilit sırası,
aynı hata mesajları. Değişen tek şey, kilit ve dar güncellemenin hangi haklarla
koştuğudur.

Kaynak bulgu: `2026-10-06-a0f1c10-PMS-mali-inceleme.md` → **MY-4 (P1)**.
Tarih: 2026-10-06. K1=A kararı değişmiyor.

---

## 1. Sorun (ölçülmüş)

Onaylı 15 satırlık matris `onburo_vardiya` ve `onburo_personel`'e oda tipi
`goruntule`, personele ayrıca oda `goruntule` veriyor. Ancak:

| Yol | Kod | Ne yapıyor |
|---|---|---|
| Rezervasyon kontrolü | `2026-09-06-...-adim2-misafir-rezervasyon.sql:372–376` | `pms_oda_tipleri` satırını **FOR UPDATE** ile kilitliyor |
| Check-in | `2026-09-06-...-adim3-checkin-checkout.sql:557–563` | `pms_odalar` satırını **FOR UPDATE** ile kilitleyip güncelliyor |
| **Check-out** | `2026-09-06-...-adim3-checkin-checkout.sql:659–673` | **Aynı engel:** `pms_odalar` **FOR UPDATE** + `kullanim_durumu='bos'`, `temizlik_durumu='kirli'` UPDATE (ölçüldü) |

Check-out yolu önceki sürümde envanterde eksikti; eklendi. Personel/vardiyanın
bu yolda **aynı yetki engeline takılmadığı** ayrıca ölçülecek.

Her ikisi de çağıranın RLS bağlamında yürüyor. PostgreSQL'de `FOR UPDATE`,
satırın **UPDATE politikasını** da geçmesini ister; `goruntule` yalnız SELECT
politikasını açar. Ölçülen sonuç: aynı hedefte `SELECT` 1 satır, `FOR UPDATE`
**0 satır**.

| Rol | Rezervasyon güncelleme/onay | Check-in |
|---|---|---|
| `onburo_vardiya` | "Oda tipi bulunamadi veya baska otele ait" | aynı hata |
| `onburo_personel` | "Oda tipi bulunamadi veya baska otele ait" | "Oda bulunamadi veya baska otele ait" |
| `onburo_sef` | çalışıyor | çalışıyor |

**Bu bir regresyon değildir:** mali INSERT değişikliğinin yan etkisi değil,
gerçek role geçişte ortaya çıkan entegrasyon engelidir. Mevcut yeşil süitler
hazırlığı **şefle** yaptığı, eski PMS akış süitleri ise sentetik `resepsiyon`
rolüne oda/oda tipi `kayit` verdiği için bunu göstermiyordu.

## 2. Değerlendirilen üç yol

| Yol | Ne yapar | Karar |
|---|---|---|
| **A — dar sistem yolu** | Kilidi ve güncellemeyi, gerekli kontrolleri **kendi içinde yeniden yapan** `SECURITY DEFINER` yardımcılarına taşı | **Önerilen** |
| B — dar RLS politikası | `pms_odalar`/`pms_oda_tipleri` için "yalnız kilit" politikası | **Olmaz:** RLS sütun bazlı kısıtlayamaz; UPDATE politikası açmak satırın tamamını düzenlenebilir yapar |
| C — matrisi genişlet | Personel/vardiyaya `pms_oda = kayit` | **Olmaz:** genel oda tanımı düzenleme hakkı verir; onaylı ayrımı genişletir |

## 3. Önerilen dar çözüm (A)

Genel oda/oda tipi düzenleme yetkisi **verilmez**. İki yeni, dar kapsamlı
`SECURITY DEFINER` yardımcısı, yalnız ihtiyaç duyulan işlemi yapar ve
atladığı RLS kontrollerini **kendi içinde açıkça yeniden uygular**:

### 3.1 İşlem sözleşmesi — sütun değil, İŞ İŞLEMİ sınırı (MY4-T1)

Önceki taslak yardımcıyı yalnız **yazdığı sütunlarla** sınırlıyordu. Bu yetersiz:
iki sütun yazabilmek, "yalnız check-in/out yapabilmek" demek değildir. Çağıran
yardımcıyı check-in/out dışından da çağırabilir ve ana RPC'nin kontrollerini
yardımcının her çağrısında var saymak yanlış olur.

Düzeltilmiş sözleşme: **oda, otel ve hedef durum istemciden ALINMAZ; doğrulanmış
rezervasyon işleminden TÜRETİLİR.**

```
pms_oda_tipi_kilitle(p_rezervasyon_id)
  - auth_yetki_var('pms_rezervasyon','kayit')          ZORUNLU
  - rezervasyon OKUNUR; otel ve oda tipi ONDAN turetilir
  - auth_otel_erisim(rezervasyon.otel_id)              ZORUNLU
  - yalniz SELECT ... FOR UPDATE; SATIRI DEGISTIRMEZ
  - istemci oda tipi kimligi VEREMEZ

pms_oda_konaklama_isaretle(p_rezervasyon_id, p_islem)
  - p_islem yalnizca 'giris' | 'cikis'  (serbest durum metni YOK)
  - auth_yetki_var('pms_rezervasyon','kayit')          ZORUNLU
  - oda, AKTIF ATAMADAN turetilir; istemci oda kimligi VEREMEZ
  - auth_otel_erisim(rezervasyon.otel_id)              ZORUNLU
  - gecis kurallari yardimcinin ICINDE dogrulanir:
      'giris' : rezervasyon 'onaylandi', oda 'bos' + 'temiz', tarih kapsiyor
      'cikis' : rezervasyon 'giris_yapildi', oda 'dolu'
  - yazilan degerler SABIT: giris -> dolu; cikis -> bos/kirli
    (temizlik durumu KEYFI SECILEMEZ)
  - oda tanimi alanlarina (oda_no, oda_tipi_id, otel_id) DOKUNAMAZ
```

Böylece yardımcı **doğrudan** çağrılsa bile konaklama ve temizlik kuralları
aşılamaz: yanlış rezervasyon, yanlış oda, geçersiz tarih/durum veya keyfi
temizlik durumu seçimi mümkün değildir. Yardımcı dışarı açık kalır (invoker
çağrı zinciri kırılmaz) ama **tam kontrolleri kendi içinde** yapar; güvenlik
"yalnız ana RPC'den çağrılır" varsayımına dayanmaz.

Mevcut `pms_rezervasyon_kontrol()` ve `pms_check_in()` bu yardımcıları çağırır;
doğrudan `FOR UPDATE` yapmaz. `EXECUTE` hakkı yalnız `authenticated`'a verilir;
yetki ve otel kapsamı yardımcının içinde kalır.

**Neden `SECURITY DEFINER`:** kilit ve dar güncelleme için RLS'in UPDATE
politikasını geçmek gerekiyor; alternatifi satırın tamamını düzenlenebilir
yapmak. Definer yolu, yetkiyi genişletmek yerine **tek bir dar işleme**
hapseder. Not: bu paketin MY-3 dersi, "definer bağlamını kanıt saymak"
yanlışıydı — burada definer bir **kanıt** değil, dar bir **yoldur**; yetki ve
otel kontrolleri yardımcının içinde yeniden yapılır.

## 3.2 UYGULANAN çözüm — ölçülen sonuç

Uygulamada **oda durumunu tek başına yazan dış yardımcı YAZILMADI** (MY4-T3):
yazma, tam geçişi tek işlemde yapan `pms_check_in`/`pms_check_out` içinde
kaldı; bu iki RPC ve rezervasyon kontrol tetikleyicisi tanımlayıcı haklarıyla
koşar ve atladıkları RLS kontrollerini (`auth_yetki_var('pms_rezervasyon','kayit')`
+ `auth_otel_erisim`) kendi içlerinde açıkça yeniden uygular.

Yalnız **kilit alan** ve hiçbir satırı değiştirmeyen dar yardımcı eklendi:
`pms_oda_tipi_kilitle(p_oda_tipi_id, p_otel_id)`. Hedef çağırandan (NEW
değerlerinden) gelir — MY4-T2'nin istediği gibi; yardımcı yetkiyi ve oda
tipi–otel eşleşmesini kendi içinde doğrular. Satır yazmadığı için doğrudan
çağrılsa bile yarım durum üretemez.

Migration sonunda ölçülen: dört fonksiyonun `prosecdef` olduğu, oda durumunu
yazan dış yardımcının **bulunmadığı** ve oda/oda tipi yetkilerinin
**değişmediği** (`ENVANTER` satırı çıktıya yazılır).

### Kırmızı → yeşil kanıt (aynı test dosyasında kalıcı)

| Faz | Ölçüm |
|---|---|
| **Kırmızı** (düzeltme yok) | `K1` personel ve vardiya rezervasyon yazamıyor (`Oda tipi bulunamadi`); `K2` check-in yapamıyor; `K2b/K2c` oda ve rezervasyon **değişmedi**; `K3/K3b` şef aynı işlemi yapabiliyor |
| **Yeşil** (düzeltme var) | `Y1` rezervasyon yazılıyor; `Y2` check-in; `Y2b` oda `dolu/temiz`; `Y2c` `giris_yapildi`; `Y2d` aktif atama 1; `Y3` check-out; `Y3b` oda `bos/kirli`; `Y3c` `cikis_yapildi` — **her ikisi de hem personel hem vardiya için** |

### Korunan davranışlar (ölçüldü)

`P1` atanmamış rezervasyonda `pms_check_in(rez, oda)` yolu korundu (atama
oluşturuldu) · `P2` temizlik kabulü `kontrol_edildi` için de geçerli · `P2b`
kirli oda hâlâ reddediliyor · `P3` kapasite kontrolü NEW hedefinden korundu ·
`P4` geçersiz yeni oda tipine UPDATE reddedildi · `N8` mali ayrım hâlâ
yürürlükte.

Kat hizmetleri tutarlılık kuralı (`pms_housekeeping_tutarlilik_oda`,
`pms_housekeeping_oda_koruma`) **gevşetilmedi**; test fikstürü bekleyen görevleri
temizleyerek odayı kuralla tutarlı hâle getirir.

## 4. Kabul ölçütleri — ROL BAZINDA ayrılmış

Onaylı matris **vardiyaya `pms_oda = kayit`**, **personele `pms_oda = goruntule` veriyor. Beklentiler bu farka göre ayrılır; bu düzeltme vardiyanın mevcut
hakkını **kaldırmaz**, personele yeni hak **eklemez**.

### Olumlu (her iki rol için ayrı ayrı)
Rezervasyon oluşturma/onaylama · **check-in** · **check-out**. Üçü de hem
`onburo_personel` hem `onburo_vardiya` kimliğiyle ölçülür.

### Olumsuz — her iki rol için ortak
- Yardımcıların **doğrudan** çağrılmasıyla kural aşma: yanlış rezervasyon,
  başka otelin rezervasyonu, geçersiz tarih, uygun olmayan rezervasyon/oda
  durumu → ret
- `p_islem` dışında bir değer veya keyfi temizlik durumu → ret
- `pms_rezervasyon` yetkisi olmayan rolle yardımcı çağrısı → ret
- `pms_oda_tipleri` üzerinde doğrudan UPDATE/DELETE → **her iki rolde de ret**

### Olumsuz — ROLE GÖRE AYRI
| Deneme | `onburo_personel` | `onburo_vardiya` |
|---|---|---|
| `pms_odalar` doğrudan UPDATE (`kullanim_durumu`) | **ret** (`goruntule`) | **kabul** (zaten `kayit`) — mevcut hak korunur |
| `pms_odalar` doğrudan UPDATE (`oda_no`/`oda_tipi_id`) | ret | **ret olmalı mı? KARAR** — bugün `kayit` buna da izin veriyor; daraltmak bu kapsamın dışıdır, ayrıca değerlendirilmeli |
| `pms_odalar` DELETE | ret | ret (`tam` değil) |

Vardiyanin mevcut kayit hakkini daraltmak **bu paketin sessiz parçası
olamaz**; yukarıdaki KARAR satırı ayrı onay ister.

### Korunacak
Mali ayrım (MY-1…MY-3 kapalı), değişmezlik, otel kapsamı, açık bakiye kuralı,
atanmış-rezervasyon listeleme ve check-out dialog davranışı.

## 5. Kapsam dışı

Housekeeping/kat rolleri, `pms_misafir_kimlik`, üst rollere yeni yetki, açık
bakiyeyle check-out iş kuralı, İP-7, canlı uygulama ve push/deploy.

## 6. Regresyon durumu

| İş | Durum |
|---|---|
| Dört PMS süiti + dialog süiti, **mali + rol** migration uygulanmış tabanda | **TAMAM** — 59/0 ve 31/0 |
| Gerçek bar köprüsü olumlu kontrolü (09-13 tabanı, gerçek fonksiyon) | **TAMAM** — MY3e1…MY3e7 |
| Gerçek sipariş/teslim RPC zinciri (A1 tabanı) + açık folyoya pozitif borç | **TAMAM** — MY3f0…MY3f6 (250,00) |
| Mali kuralın A1 tabanında da yürürlükte olması | **TAMAM** — MY3f8 |
| Kapalı folyo → borç istisnası → `bar_borc_istisnasi_coz` olumlu kontrolü | **TAMAM** — ayrı ve temiz fikstürlü kalıcı testte: `scripts/pms-bar-borc-istisnasi.test.mjs` (B4…B8), **17/0** |

Kapanış kaydı: `docs/inceleme/PMS-MALI-MY-KAPANIS.md`.

## MY4-R1 / MY4-R2 kanıt boşlukları — KAPANDI (2026-10-07)

İnceleme: `2026-10-07-2705363-PMS-bagimsiz-inceleme.md`. **Yalnız test**
düzeltildi; SQL, yetki matrisi ve kapanmış paketler değişmedi.

| # | Boşluk | Düzeltme ve ölçüm |
|---|---|---|
| **MY4-R1** | P4 geçersiz UUID kullanıyordu; `::text::uuid` hatası oda tipi kontrolüne ulaşmadan dönüyor, test yalnız `!ok` aradığı için kontrol bozulsa bile yeşil kalabiliyordu | Üç karşılaştırma gerçek hedeflerle kalıcılaştı: **P4a** geçerli UUID + olmayan tip → `Oda tipi bulunamadi`; **P4b** `azami_kisi=1` olan gerçek yeni tipe 2 yetişkinle → kapasite reddi; **P4c** aynı tipe 1 yetişkinle → KABUL. Her üçünde rezervasyonun oda tipi DEĞERİ ayrıca ölçülüyor (P4a2/P4b2/P4c2) |
| **MY4-R2** | `(vardOda.ok && çıktı!=="") || !vardOda.ok` her hatayı yetkinin korunduğu kanıtı sayıyordu | **N4** iş kuralına takılmayan `oda_no` alanında GERÇEKTEN başarılı UPDATE (RETURNING + DB değeri `CX731`), fikstür geri alınıyor; **N4b** temizlik reddini yalnız `pms_housekeeping_*` / `H<n>:` iş kuralı deseniyle kabul ediyor, ilgisiz hata testi KIRIYOR |

### Diş kanıtı (mutant koşumları)

Düzeltilmiş testin gerçekten koruduğu, ürün/test bozulduğunda kırılmasıyla ölçüldü:

| Mutant | Beklenen | Ölçülen |
|---|---|---|
| P4 fikstüründe yeni tipten oda yok | P4c kırılır | `FAIL P4c … secilen tarihlerde 0 rezervasyon dolu` + `FAIL P4c2` |
| `TIP_YOK` geçersiz UUID (eski kusurun kendisi) | P4a kırılır | `FAIL P4a … BEKLENMEYEN: invalid input syntax for type uuid` |
| N4 UPDATE ilgisiz SQL hatasına düşer | N4 kırılır | `FAIL N4 … BEKLENMEYEN HATA: … does not exist` |
| N4b reddi iş kuralı değil, ilgisiz SQL hatası | N4b kırılır | `FAIL N4b … BEKLENMEYEN HATA (basari sayilmaz)` |

Kapasite/aşırı satış kontrolü **gevşetilmedi**; eksik olan yalnız fikstürdü:
`TIP_TEK` tipinden bir oda (`T01`) eklendi.
