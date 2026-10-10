# PMS — MALİ SUNUCU RETLERİ DOĞRULAMA PLANI (ÇALIŞTIRILMADI)

**Tarih:** 2026-10-09
**Dal:** `pms/akis-tamamlama`
**Durum:** PLAN. Canlıda **uygulanmadı**. Bu belge, çalıştırma izni verildiğinde
izlenecek adımları ve kabul ölçütlerini önceden sabitler.

---

## 1. Neden bu plan var

PMS canlı kabul testinde üç kontrol **yalnız arayüzde** engellendi; istek sunucuya
hiç ulaşmadı. Kapanış kaydında bunlar açık bırakıldı:

| Kontrol | Canlıda ölçülen | Eksik olan |
|---------|-----------------|------------|
| Personelin **negatif ödeme** yazması | Arayüz engelledi | Sunucunun kendisi reddediyor mu |
| Yöneticinin **gerekçesiz iade**si | Arayüz engelledi | Sunucunun kendisi reddediyor mu |
| Mevcut mali satırın **UPDATE/DELETE**'i | Hiç denenmedi | Append-only gerçekten sunucuda mı |

Arayüz engeli bir kanıt değildir: arayüz atlanabilir (doğrudan PostgREST çağrısı,
başka bir istemci, hata sonucu açılan bir yol). Üç kontrolün **sunucu tarafında**
reddedildiği ölçülmeden mali bütünlük doğrulanmış sayılamaz.

## 2. Ölçüm aracı ve altı deneme

**Sonda:** `docs/kurulum/2026-10-09-pms-mali-sunucu-retleri-sondasi.sql`
**İzole kanıt:** `scripts/pms-mali-sunucu-sonda.test.mjs`

Değişmezlik **iki tabloda** da kuruludur (`pms_folio_degismez` tetikleyicisi hem
`pms_folio_hareketleri` hem `pms_folio_odemeler` üzerinde —
`docs/kurulum/2026-09-06-pms-faz1-adim4-folio.sql`), bu yüzden ödemeler tablosu da
ayrıca sınanır. **Altı deneme:**

| # | Deneme | Kimlik | Beklenen mesaj | Beklenen SQLSTATE |
|---|--------|--------|----------------|-------------------|
| 1 | K1 personel negatif ödeme | personel (`kayit`) | `MALI_TAM_YETKI_GEREKLI…` | `42501` |
| 2 | K2 yönetici gerekçesiz iade | yönetici (`tam`) | `MALI_GEREKCE_ZORUNLU…` | `23514` |
| 3 | K3a **hareket** satırı UPDATE | yönetici (`tam`) | `Finansal kayit degistirilemez…` | `42501` |
| 4 | K3b **hareket** satırı DELETE | yönetici (`tam`) | `Finansal kayit degistirilemez…` | `42501` |
| 5 | K4a **ödeme** satırı UPDATE | yönetici (`tam`) | `Finansal kayit degistirilemez…` | `42501` |
| 6 | K4b **ödeme** satırı DELETE | yönetici (`tam`) | `Finansal kayit degistirilemez…` | `42501` |

Beklenen çiftlerin kaynağı migration'ların kendisidir:
`2026-10-06-pms-folio-mali-yetki-ayrimi.sql:110` (42501) ve `:117` (23514),
`2026-09-06-pms-faz1-adim4-folio.sql:599` (42501).

## 3. Hedef açık seçimle sabitlenir

Sondanın başındaki dört satır **elle doldurulur**; "ilk bulunanı al" mantığı
yoktur:

```sql
set local sonda.hedef_otel     = 'DOLDUR';   -- otel kodu, örn. '810'
set local sonda.hedef_personel = 'DOLDUR';   -- auth.users.id, pms_folio = kayit
set local sonda.hedef_yonetici = 'DOLDUR';   -- auth.users.id, pms_folio = tam
set local sonda.hedef_misafir  = 'DOLDUR';   -- SENTETİK QA misafirinin soyadı
```

Doldurulmamış tek alan bile sondayı **durdurur**. Ayrıca şunlar doğrulanır ve
tutmazsa sonda kurulum aşamasında durur:

| Kapı | Neden |
|------|-------|
| Hedef otelde aktif kullanıcı var mı | Kullanımda olmayan otel kodunda ölçüm anlamsız |
| Personel kimliği hedef otelde **tam olarak bir** aktif kullanıcıya eşleşiyor mu | Çoklu/eksik eşleşmede hangi kimlikle ölçüldüğü belirsiz olur |
| Personelin `pms_folio` yetkisi **`kayit`** mi | `tam` yetkili kimlikle K1 ölçülemez; ret hiç doğmaz |
| Yönetici kimliği hedef otelde **tam olarak bir** aktif kullanıcıya eşleşiyor mu | aynı |
| Yöneticinin `pms_folio` yetkisi **`tam`** mı | `kayit` ile K2 yerine K1 reddi doğar, gerekçe kontrolü ölçülmez |
| Personel ≠ yönetici | İki ayrı yetki seviyesi sınanıyor |

**Yalnız sentetik misafir.** Hedef misafir, soyadı açık seçimle verilen sentetik
QA kaydıdır ve işarette **`QA` geçmek zorundadır**. Eşleşme **yoksa** veya
**birden fazlaysa** sonda durur — gerçek bir misafirin üzerine sentetik
rezervasyon yazılmaz, belirsiz eşleşmede rastgele seçim yapılmaz.

**Oda tipi** hedefin kendisi değil, rezervasyonun zorunlu alanıdır: seçim
deterministiktir (en küçük `kod`) ve çıktıda raporlanır. Çıktının ilk tablosu
hangi otel, hangi iki kimlik, hangi misafir ve hangi oda tipiyle koşulduğunu
yazar; kayda bu tablo geçirilir.

## 4. Bu sonda geçici olarak yazar — ve dizilerde iz bırakır

Bu **açıkça belirtilmelidir**, çünkü hedef canlı veritabanıdır.

**Geçici yazma (hepsi geri alınır):** hedef otelde 1 rezervasyon
(`SONDA-<zaman damgası>`) + 1 folyo (tetikleyici otomatik açar) + 1 oda ücreti
hareketi (+100,00) + 1 pozitif nakit ödeme (+10,00). Ödeme borçtan **küçük**
tutulur ki bakiye sıfırlanmasın ve folyo açık kalsın. Dosyanın tamamı tek
işlemdir ve `rollback` ile biter; beklenmedik bir **kabul** çıksa o satır da
geri alınır.

**Kalıcı iz — diziler geri alınmaz.** Her koşum şunları kalıcı olarak ilerletir:

| Dizi | Etki |
|------|------|
| `pms_rezervasyon_no_seq` | +1 → rezervasyon numarasında bir boşluk |
| `pms_folio_no_seq` | +1 → folyo numarasında bir boşluk |

`pms_folio_hareketleri` ve `pms_folio_odemeler` kimlikleri `gen_random_uuid()`
olduğu için başka dizi izi yoktur. Yani koşumdan sonra üretimde bir rezervasyon
ve bir folyo **numarası atlanmış** görünür. Başka kalıcı etki yoktur ve sonda
çıktısının son satırı bunu ayrıca yazar.

## 5. Diğer tasarım kuralları ve gerekçeleri

Her kural, bu doğrulamayı **yanlış-yeşil** verebilecek somut bir yoldan türedi.

### 5.1 Gerçek uygulama rolü — `postgres` sonucu personel testi sayılmaz

Her deneme `set local role authenticated` + `set local request.jwt.claims` ile,
seçilen gerçek ERP kullanıcısının kimliğiyle koşar. Her denemenin yanına
`current_user`, `rolsuper`, `rolbypassrls` yazılır. Dosyanın sonundaki
**kimlik kapısı**, bir tek deneme bile `authenticated` dışında veya
`rolsuper`/`rolbypassrls` ile koşmuşsa koşumu **GEÇERSİZ** ilan eder:

```
GECERSIZ: en az bir deneme gercek uygulama rolu disinda kostu
```

G4'te mutant testle kanıtlandı (§7).

### 5.2 Fikstür de kimlikle kurulur

`phase0_islem_audit` tetikleyicisi kimliksiz (doğrudan superuser) yazmayı
`Aktif ERP personeli gerekli` ile **reddediyor** — izole ortamda ölçüldü. Bu
nedenle hedef rezervasyon, hareket ve ödeme satırları da **personel kimliğiyle**
yazılır.

### 5.3 Mesaj **ve** SQLSTATE birlikte doğrulanır

Beklenen metin tuttuğu halde SQLSTATE farklıysa sonuç
`SQLSTATE YANLIS (GECERSIZ): bek=… olc=…` olur ve kabul kapısından **geçmez**.
Doğru mesajı yanlış kodla üretmek bir regresyondur: istemci ve PostgREST
davranışı koda bağlıdır. G10'da mutant testle kanıtlandı.

### 5.4 Kalıcı değişiklik yok — beklenmedik KABUL'de bile

Her deneme kendi `exception` bloğunda koşar, böylece bir hata işlemi abort etmez
ve sonraki denemeler ölçülebilir. Bir reddin olmadığı, yani kusurun bulunduğu
durumda bile satır kalmaz: yazma gerçekleşir, `KABUL (KUSUR)` olarak raporlanır
ve `rollback` ile geri alınır. Planın en kritik güvenlik özelliğidir; G2'de
kanıtlandı.

### 5.5 `SET TRANSACTION READ ONLY` kullanılmaz

Kullanılsaydı her yazma `read-only transaction` ile reddedilirdi ve **asıl yetki
hatasını maskelerdi**: altı kontrol "reddedildi" görünür, hiçbiri ölçülmemiş
olurdu. Bu mesaj sondada `MASKELENDI (GECERSIZ)` sınıfına konmuştur.

### 5.6 Kapalı folyo maskelemesi engellenir

`Kapali folyoya kayit eklenemez` hatası, yetki kontrolünden **önce** vurur. Hedef
folyo kapalı olsaydı K1/K2 bu mesajla reddedilir ve yetki katmanı hiç
sınanmadığı halde test yeşil görünürdü. İki önlem:

1. Hedef folyo **işlem içinde** oluşturulur ve `acik` olmak **zorundadır**;
   değilse sonda kurulum aşamasında durur:
   `SONDA KURULAMADI: hedef folyo ACIK degil (%) — kapali folyo asil yetki hatasini MASKELER`
2. `Kapali folyoya%` mesajı **BEKLENEN RET sayılmaz**, `MASKELENDI (GECERSIZ)` olur.

G3'te kanıtlandı.

### 5.7 Beklenmeyen hata başarı sayılmaz

"Hata aldı, demek ki reddedildi" mantığı yoktur:

| Sınıf | Anlamı |
|-------|--------|
| `BEKLENEN RET` | Hedeflenen kural, **beklenen SQLSTATE ile** reddetti |
| `BEKLENEN RET (tetikleyici / ayricalik / RLS)` | K3/K4: üç katmandan biri reddetti; hangisi olduğu raporlanır |
| `SQLSTATE YANLIS (GECERSIZ)` | Mesaj doğru, kod yanlış — regresyon |
| `MASKELENDI (GECERSIZ)` | Ret var ama yanlış sebepten (kapalı folyo, read-only) |
| `FARKLI KATMAN (…)` | Beklenenden başka bir katman reddetti |
| `KIMLIK YANLIS (tam yetki yok)` | Yönetici aslında tam yetkili değil |
| `BEKLENMEYEN (GECERSIZ)` | Tanınmayan hata |
| `KABUL (KUSUR)` | **Reddedilmedi — gerçek bulgu** |

K3/K4'te üç katman (ayrıcalık yok + politika yok + `pms_folio_degismez`)
bilinçle eşdeğer kabul edilir: hangisi önce vurursa ret meşrudur, ama **hangi
katmanın vurduğu rapora yazılır**.

## 6. Kabul ölçütü — tek metin

Koşum, kimlik kapısı **tam olarak** şunu derse geçmiş sayılır:

```
UYGUN: alti denemenin altisi da BEKLENEN RET
```

Başka her çıktı (`GECERSIZ: …`, `INCELE: …`) **geçmemiş** sayılır. Altı denemeden
azı ölçüldüyse de geçmez (`GECERSIZ: beklenen 6 deneme, olculen N`).

## 7. İzole kanıt — ÇALIŞTIRILDI ve GEÇTİ

**Komut:** `node scripts/pms-mali-sunucu-sonda.test.mjs`
**Sonuç:** **34 geçti, 0 kaldı** (2026-10-09, kendi ölçümüm; izole Docker,
sentetik veri, üretime bağlantı yok)

| Kanıt | Ne gösterir |
|-------|-------------|
| G0 / G0b | Hedef seçimi doldurulmamışsa sonda **durur** ve satır yazmaz |
| G1–G1d | Sonda hatasız koşuyor; **altı** deneme de `BEKLENEN RET`; kapı `UYGUN` diyor; rol `authenticated` |
| G1e | Çıktıda K4a/K4b var — **ödemeler tablosu da** sınanıyor |
| G1f | Seçilen otel, iki kimlik ve sentetik misafir çıktıda raporlanıyor |
| G2–G2d2 | Hareket, ödeme, rezervasyon, folyo ve misafir sayıları **değişmedi** |
| **G2e–G2h** | **Kabul taklidinde** (deneme kabul edilecek bir yazmaya çevrildi) sonda `KABUL (KUSUR)` raporladı, kapı `UYGUN` **demedi**, satır sayıları yine **değişmedi** |
| G3 / G3b | Folyo anında kapatıldığında sonda **kurulum aşamasında durdu**; satır kalmadı |
| G4–G4c | Rol değiştirme etkisizleştirilince kapı **GEÇERSİZ** dedi, `UYGUN` demedi |
| G5 / G5b | Tek kalıcı iz dizi boşluğu; geçici yazma ve dizi etkisi çıktıda **açıkça** yazıyor |
| G6 / G7 / G8 | Sentetik misafir **yoksa**, **çoklu** eşleşiyorsa veya işaret **sentetik görünmüyorsa** sonda durdu |
| G9 | Personel `tam` yetkiliyken sonda durdu (K1 ölçümü anlamsız olurdu) |
| G10–G10c | Mesaj doğru + SQLSTATE yanlış → `SQLSTATE YANLIS`; kapı `UYGUN` demedi; satır kalmadı |

Bu izole kanıttır; **canlı koşum yerine geçmez**.

## 8. Canlı koşum adımları (henüz YAPILMAYACAK)

1. **Önkoşul:** üretimde `2026-10-06-pms-folio-mali-yetki-ayrimi.sql` ve
   `2026-10-06-pms-rol-entegrasyon-kilit.sql` uygulanmış olmalı (yayın sonrası
   salt-okuma ölçümü bunu doğruladı: 15 uyumlu / 0 eksik / 0 çelişen; mali
   tetikleyici 2, `hassas_mi` 1 — kaynak: kullanıcının diğer koordinasyon
   oturumunda paylaştığı komut çıktısı).
2. **Hedef seçimi doldurulur** (§3): otel kodu, personel ve yönetici
   `auth.users.id`, sentetik QA misafirinin soyadı. Doldurulmadan koşmaz.
   Bu dört değeri okumak için **salt-okuma** yardımcısı vardır — yalnız `SELECT`
   içerir, işlem açmaz, hiçbir satırı değiştirmez:

```bash
powershell -File docs/kurulum/sql-uygula.ps1 -Dosya docs/kurulum/2026-10-09-pms-sonda-hedef-bul.sql -SaltOkuma
```

   Çıktı üç şey verir: `pms_folio` yetkisi `kayit` ve `tam` olan aktif
   kullanıcıların `auth_user_id`'leri (otel koduyla birlikte), sentetik QA
   misafirlerinin soyadları ve kaç kez eşleştikleri, ve önkoşul sayıları
   (hassas kapı tetikleyicisi 2, değişmezlik tetikleyicisi 2, `hassas_mi` 1).
   Aynı soyad birden fazla kez eşleşiyorsa sonda zaten durur (§3).
3. **Tek oturum, salt-sonda kipi.** Dosyanın tamamı tek seferde verilir:

```bash
powershell -File docs/kurulum/sql-uygula.ps1 -Dosya docs/kurulum/2026-10-09-pms-mali-sunucu-retleri-sondasi.sql -SaltOkuma
```

   `-SaltOkuma` kipi `--single-transaction` sarmalayıcısı **eklemez**
   (`sql-uygula.ps1:75`); işlem sınırını dosyanın kendi `begin;`/`rollback;`
   çifti kurar. Bu zorunludur: iki işlem sınırı `set local` etkisini bozar.
4. Çıktıdaki **hedef tablosu**, altı sonuç satırı, kimlik kapısı metni ve dizi
   etkisi satırı **birebir** kayda geçirilir.
5. Sonuç `URETIM-YAYIN-RUNBOOK.md` §15.6 ve kapanış kaydındaki "açık" maddeye
   işlenir.

## 9. Durma koşulları

Aşağıdakilerden biri olursa **devam edilmez**, durum bildirilir:

- Kapı `GECERSIZ` derse → ölçüm kimlik açısından geçersiz; sebep bulunmadan tekrar yok.
- `SONDA KURULAMADI` ile durursa → hedef seçimi veya fikstür kurulamadı (§3'teki
  kapılardan biri tutmadı); seçim düzeltilmeden tekrar koşulmaz.
- Herhangi bir deneme `KABUL (KUSUR)` çıkarsa → **gerçek bulgu**. İşlem zaten geri
  alınmış olur; kalıcı satır aranmaz çünkü yoktur. Düzeltme ayrı bir iş olarak açılır.
- `SQLSTATE YANLIS` veya `MASKELENDI (GECERSIZ)` çıkarsa → ölçüm yapılmamış sayılır.

## 10. Yapılmayacaklar

- Yetki **genişletme** yok. Hiçbir `GRANT`, hiçbir politika değişikliği yok —
  özellikle K3/K4'ün tetikleyici katmanını görmek için `UPDATE` ayrıcalığı verilmez.
- `postgres`/service-role ile "test" yok; böyle bir sonuç personel testi sayılmaz.
- Mevcut canlı kayıtlara (R-2026-000005, R-2026-000006, F-2026-000005, bekleyen
  temizlik görevleri) dokunulmaz. Sonda yalnız kendi oluşturduğu satırlara yazar
  ve onları da geri alır.
- Gerçek misafir kullanılmaz; yalnız sentetik QA kaydı.
- `commit` yok. Dosyada `commit` ifadesi geçmez.

## 11. Bu planın ölçmediği şeyler

- **K3/K4'te hangi katmanın reddettiği belirlenir ama hepsi ölçülmez.** İzole
  tabanda ret `BEKLENEN RET (ayricalik)` geldi: uygulama rolünde tablo
  `UPDATE`/`DELETE` ayrıcalığı olmadığı için istek `pms_folio_degismez`
  tetikleyicisine **hiç ulaşmıyor**. Tetikleyici katmanı uygulama rolüyle
  sınanamaz; sınamak ayrıcalık vermeyi gerektirir, bu da yapılmaz. Üç katmandan
  en dıştakinin tuttuğu ölçülür.
- **PostgREST üzerinden HTTP davranışı.** Sonda veritabanı oturumunda koşar;
  PostgREST'in aynı reddi 4xx'e çevirdiği ayrıca ölçülmedi.
- **Arayüz davranışı.** Zaten canlı duman testinde ölçüldü ve bu planın konusu değil.
- **İzole tabanda yan gözlem:** tetikleyicinin gerekçe kapısı devre dışı
  bırakıldığında negatif ödemeyi **RLS** reddetti. Yani K1/K2 yolunda tetikleyici
  tek koruma değil. Bu bir izole ortam gözlemidir; canlıda ayrıca ölçülmedi.

---

## Kaynak sınıfları

- §7, §5.2 ve §11'in son maddesindeki ölçümler: **kendi ölçümüm** (izole Docker,
  2026-10-09).
- §2'deki beklenen mesaj/SQLSTATE çiftleri: **migration dosyalarının kendisi**
  (satır numaraları verildi).
- §8.1'deki yayın sonrası salt-okuma sayıları: **kullanıcının diğer koordinasyon
  oturumunda paylaştığı komut çıktısı** — kendi ölçümüm değil.
- §1'deki "arayüz engelledi" tespitleri: **kullanıcının bildirdiği tarayıcı ölçümleri**.
