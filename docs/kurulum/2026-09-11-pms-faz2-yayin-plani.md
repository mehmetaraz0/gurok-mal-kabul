# PMS Faz 2 — Kat Hizmetleri: Yayın Öncesi İnceleme ve Yayın Planı

**Tarih:** 2026-09-11. Canlı salt okuma ölçümleri 2026-09-11 23:20–23:35 İstanbul saatinde alındı.
**Durum:** HAZIRLIK TAMAM — canlı uygulama için `CANLIYA UYGULA` bekleniyor. Üretime hiçbir şey uygulanmadı; merge, push, deploy yapılmadı; modül ayarı değişmedi.
**Kapsam:** `docs/kurulum/2026-09-09-pms-faz2-adim1-housekeeping.sql`, `docs/kurulum/2026-09-10-pms-faz2-adim2-housekeeping-ui-destek.sql` ve `pms-faz2-housekeeping-ui` dalındaki arayüz.
**Salt okuma preflight:** `docs/kurulum/2026-09-11-pms-faz2-yayin-oncesi-preflight.sql`
**Yetkili şartname:** `docs/PMS-FAZ2-HOUSEKEEPING-ARCHITECTURE.md` (§16 yetki ve etkinleştirme sırası, §24 geri alma). Bu plan onunla çelişirse şartname geçerlidir.

> **Salt okuma inceleme, migration'ın başarıyla uygulanacağını tek başına kanıtlamaz.** Uygulanabilirlik izole provada gösterildi (1.4). Prova, 09-07 dökümü üzerinde yapıldı; bu döküm bugün canlıya karşı yeniden doğrulandı ama bayt bayt güncel değildir (bkz. 1.5, E-3).

---

## 0. Kesin yayın commit'leri

Yerel dal: `pms-faz2-housekeeping-ui`, worktree `C:\Users\USER\Projects\gurok-mal-kabul-faz2-yayin`. **Push edilmedi.**

| Commit | İçerik | Yayındaki rolü |
|---|---|---|
| `4e321f3` | Kat hizmetleri mobil çalışma ekranı | Arayüz |
| `b9ae778` | Oda planı entegrasyonu | Arayüz |
| `0644bb5` | Yerel staging QA katmanı | Test (yayına etkisi yok) |
| `af3cb1d` | Adım 2 migration (arayüz destek sözleşmesi) | Veritabanı |
| `2cc3f24` | Arayüz kabul düzeltmeleri | Arayüz |
| `2851bc5` | Odalar formunda temizlik salt okunur | Arayüz |
| `e10a806` | **Adım 2'nin SQL Editor uyumu** (psql meta komutu kaldırıldı) | Veritabanı |
| `7b84da2` | Salt okuma yayın öncesi preflight | Doküman |
| bu belgenin commit'i | Yayın planı | Doküman |

- **Taban:** `origin/main` = `d0bd734`. Dal onun üzerine hızlı ileri alınabilir; `git merge-base --is-ancestor origin/main HEAD` doğrulandı.
- **Uygulanacak veritabanı dosyaları:**
  - Adım 1: `docs/kurulum/2026-09-09-pms-faz2-adim1-housekeeping.sql`, SHA256 `e5a560cd5ed30536813817a4effe1768adc3d240c38bd912918190c874111e8f`. `d0bd734`'ten beri değişmedi.
  - Adım 2: `docs/kurulum/2026-09-10-pms-faz2-adim2-housekeeping-ui-destek.sql`, SHA256 `7d987dd99c43554c6bd14f95d957db18726b01090ce3220147e3e2ff33a88380` (`e10a806`).
- **Ön yüz yayını:** dalın son commit'i. Arayüz dosyaları `2851bc5` ile aynıdır; sonraki üç commit yalnız SQL ve doküman değiştirir.
- **Yayında KULLANILMAYACAKLAR:**
  - yerel `main` (`a8881ea`): `origin/main`'in 7 commit önünde, dal geçmişinden ayrışmış;
  - `codex/hk-ui-clean-a8881ea` worktree'si;
  - R11 commit'i `3d7c895`: yalnız yerel `main`'de duruyor, Faz 2'den bağımsız bir güvenlik aracı değişikliği, ayrı karar gerektirir.

---

## 1. Bulgular

### 1.1 Dal durumu

- `origin/pms-faz2-housekeeping-ui` saat 20:50'de `a8881ea` iken 22:24'te zorla `2851bc5`'e güncellendi. Güncelleme bu makinedeki ayrı bir worktree'den yapıldı (`gurok-mal-kabul-hk-clean`, dal `codex/hk-ui-clean-a8881ea`).
- İçerik doğrulandı: `diff(2cc3f24..2851bc5)` ile `diff(3d7c895..a8881ea)` birebir aynı. Yani `2851bc5`, `a8881ea`'dan R11 commit'inin çıkarılmış hâlidir; arayüz ve migration dosyaları değişmedi.
- Yeniden yazımın bilinçli yapıldığını kullanıcı teyit etmelidir (E-4).

### 1.2 Canlıda sunulan arayüz (ölçüldü)

- `origin/main` kökündeki 76 html/js/json/css dosyasının 76'sı canlıdakiyle aynı SHA256'ya sahip.
- `pms-housekeeping.html` ve `pms-housekeeping.js` HTTP 404 dönüyor.
- GitHub Pages yanıtında `Cache-Control: max-age=600` var.
- `sw.js` network-first çalışıyor; yalnız `index.html`, `manifest.json` ve `icon.png` önbelleğe alınıyor.

### 1.3 Canlı veritabanı — salt okuma ölçüldü (2026-09-11)

**Yöntem:**
- Kullanıcının oturumu açık Supabase panelinde SQL Editor kullanıldı: rol `postgres`, ortam "main PRODUCTION".
- Hiçbir dosya elle yazılmadı. Dosyalar yalnız 127.0.0.1'e bağlı geçici bir sunucudan panoya kopyalanıp editöre yapıştırıldı.
- Her çalıştırmadan önce editördeki metnin SHA256'sı repo dosyasıyla birebir eşleştirildi. Yorumlar ve metin sabitleri çıkarıldıktan sonra yazma anahtar kelimesi kalmadığı doğrulandı.
- Panel iki dosyada (preflight ve parmak izi) "destructive operations" uyarısı gösterdi. Bu yanlış alarmdı: sorgular tek SELECT'ti; uyarıyı `'DELETE,…,UPDATE'` gibi metin sabitleri tetikledi.
- Otomatik kayıt, çalıştırılan metni geçici olarak kullanıcının "Untitled query" listesine ekledi. Sekme kapatılınca kaydedilmemiş sorgu listeden düştü (292 kayıt). Hiçbir kayıtlı sorgu silinmedi.

| Dosya | Sonuç |
|---|---|
| `2026-09-11-pms-faz2-yayin-oncesi-preflight.sql` | **60 satır: 50 GECTI, 0 SAPMA, 10 BILGI** |
| `2026-09-07-post-pms-faz1-esitlik-dogrulama.sql` | **SAPMA yok.** 28/28 fonksiyon eşleşti; 234 politika / 75 tablo; 40 kısıtlayıcı |
| `2026-09-07-post-pms-faz1-uretim-parmakizi.sql` | 36 satır; `esit` türündeki satırların hepsi tabanda. Bilgi satırları: 27 definer fonksiyon, 22 pms fonksiyonu, 22 denetim satırı |
| `2026-09-07-varsayilan-acl-uyari-kontrolu.sql` | D1/D2/D3 (anon tablo / sekans / EXECUTE) **0**. B1=3 ve C1=12 bilinen platform riski, değişmedi |
| `2026-09-08-event-trigger-tabani.sql` | 7/7 beklenen, 0 devre dışı; `ensure_rls → rls_auto_enable()` bağlı |
| `2026-09-09-veritabani-duzeyi-tabani.sql` | 22 satırın tamamı ESIT; E2=7 ve E3=1 bilinen |

Parmak izi dosyasındaki taban değerlerinin tamamı:

| Ölçüm | Değer |
|---|---|
| Tablo / politika / kısıtlayıcı politika | 75 / 234 / 40 |
| RLS kapalı tablo | 0 |
| search_path pinsiz definer fonksiyon | 0 |
| anon tablo hakkı / anon sekans hakkı | 0 / 0 |
| PMS tablo / politika / kısıtlayıcı / modül | 9 / 41 / 9 / 6 |
| Otel değişmezi tetikleyicisi | 34 |
| Denetim tetikleyicisi | 5 |
| Idempotency indeksi / EXCLUDE kısıtı | 3 / 1 |

**Preflight BILGI satırları ve ek salt okuma sorgusu** (kişi adı içermez):

| Ölçüm | Değer |
|---|---|
| Oda dağılımı (E6) | Otel 810'da 2 oda: `101` boş/temiz, `102` dolu/kontrol_edildi. Kirli, bloke/arıza ve pasif oda yok. |
| Devam eden konaklama | 1: oda `102`, giriş 2026-09-07, **planlı çıkış 2026-09-13** |
| Onaylı (gelecek) rezervasyon | 0; son rezervasyon 2026-09-07 |
| Bugün veya geçmiş tarihli planlı çıkış (E8) | 0 |
| `erp_islem_audit` (E9) | 22 satır; son kayıt 2026-09-08 19:24 UTC |
| `pms_rezervasyon` kayit/tam rolleri | Yalnız `IT / Sistem Yöneticisi` ve `Sistem Yöneticisi` (tam); bu yetkiye sahip aktif kullanıcı **3** |
| Aktif ERP kullanıcısı (F4) | Otel atamalı 4, tüm oteller 7, otelsiz 1 |
| Kat hizmetleri modülü / rolü | Yok (A5 = 0) |
| PostgreSQL sürümü | 17.6 (prova konteyneri 17.11) |

**Yorum:** Üretimdeki PMS verisi Faz 1 duman testi ölçeğinde. Temizlik yolunun kapalı kalacağı sürenin bugünkü tek iş etkisi, 102 numaralı odanın 13 Eylül'deki çıkışıdır.

### 1.4 İzole prova ve testler

**Taban:** 09-07 POST-FAZ1 dökümü + referans veri + 09-08 ACL temizliği. Tek kullanımlık, ağsız bir PostgreSQL 17 konteynerinde kuruldu. Migration'lar, SQL Editor'ün yaptığı gibi **tek sorgu metni** olarak uygulandı.

| Prova / paket | Sonuç |
|---|---|
| Adım 1 (tek sorgu metni) | Başarılı. Yapısal, tetikleyici sırası, artım 2 ve artım 3 doğrulamaları geçti. |
| Adım 2, düzeltmeden önce (`2851bc5`) | **Başarısız:** `syntax error at or near "\"`; hiçbir şey uygulanmadı |
| Adım 2, düzeltmeden sonra (`e10a806`) | Başarılı |
| İkinci kez uygulama | İkisi de başarılı (idempotent) |
| Preflight: tabanda / migration sonrası | 50 GECTI, 0 SAPMA / tam olarak beklenen 19 SAPMA |
| `check.mjs`, `migration-guvenlik-kontrol.mjs` | Yeşil, 0 HATA (`7b84da2`) |
| Denetleyici birim testleri (commit'lenmiş bayt) | 14/14 |
| housekeeping / artım 2 / artım 3 | 13/0 · 31/0 · 14/0 |
| son kabul / REST baypas / UI destek | 24/0 · 17/0 · 14/0 |
| Faz 1 regresyon | 14/0 |
| Eşzamanlılık (iki oturum) / sabotaj | 13/0 · 9/0 |

**Uygulama sonrası beklenen değerler (provada ölçüldü):**
- 76 tablo, 236 politika, 41 kısıtlayıcı politika;
- 44 `pms_*` fonksiyonu, bunların 22'si `pms_housekeeping_*`; 8 `phase0_private.hk_*` fonksiyonu;
- 90 tetikleyici; anon EXECUTE 0;
- `pms_odalar` üzerinde authenticated hakları `INSERT,SELECT,UPDATE`;
- modül `sira=49 aktif=false`.

### 1.5 Prova kopyasının güncelliği

09-07 dökümü bugün canlıya karşı üç açıdan yeniden doğrulandı:
- 28/28 SECURITY DEFINER fonksiyon gövdesi (eşitlik dosyası);
- migration'ın yerine yazdığı `islem_audit` gövdesi ile dayandığı `pms_check_in`, `pms_check_out`, oda geçiş ve tutarlılık gövdeleri (preflight C1–C10);
- tüm taban sayıları.

Ölçülmeyenler: PMS dışındaki SECURITY INVOKER fonksiyon gövdeleri, politika ifadelerinin metni (yalnız sayıları ölçüldü), PMS dışı tabloların kolon ve varsayılan değerleri. Migration bunların hiçbirine dokunmuyor. Yine de runbook §2.5 "üretimin doğrulanmış kopyası" şartını bayt düzeyinde güncel tutmak için pencere günü yeni döküm alınacak (Aşama 0.3).

### 1.6 Canlıdaki eski arayüzün temizlik ve oda yazma yolları

Yazmaları yargılayan bekçi fonksiyonu `public.pms_housekeeping_oda_koruma()` (Adım 1 §12, satır 732–810): `BEFORE INSERT OR UPDATE ON pms_odalar`, SECURITY INVOKER. **Modül bayrağına bakmaz.**

| Canlı dosya:satır | İşlem | Migration sonrası (modül açık **veya** kapalı) |
|---|---|---|
| `pms-oda-plani.html:296-300`, `:390-400` `temizlikDegistir()` | `PATCH {temizlik_durumu}`: kirli→temizleniyor, temizleniyor→temiz, kontrol_edildi→temiz | **Hepsi reddedilir** (42501; §12 satır 797–800). Eski arayüzde odayı temize çekmenin tek yolu budur. |
| `pms-odalar.html:316-323` + `:375` POST | Yeni oda (temizlik seçicisinin varsayılanı `kirli`) | `kirli` kabul edilir; başka değer **reddedilir** (§12 satır 756–760) |
| `pms-odalar.html:348-372` PATCH | Gövde, sayfa açılırken okunan temizlik değerini her zaman gönderir | Değer aynıysa kabul, değiştirildiyse **red**. Sayfa açıkken oda kirlendiyse ilgisiz bir düzenleme de reddedilir; sayfanın yenilenmesi gerekir. |
| `pms-odalar.html` kullanım seçici | bos↔bloke/ariza, aktif↔pasif | Faz 1 kuralları sürer. **Yeni:** `ariza` odayı kirletir ve göstergeyi temizler (§24 satır 2054–2062); pasifleştirme çalışan işi iptal eder. |
| `pms-oda-plani.html:342-357` → `rpc/pms_check_in` | INVOKER, `pms_rezervasyon kayit` gerekir | Davranış aynı. Bekçi kilitli eski değeri denetler, göstergeyi emekliye ayırır; kullanım değişikliği için yeni bir denetim satırı yazılır. |
| `pms-oda-plani.html:373-384` → `rpc/pms_check_out` | INVOKER, `pms_rezervasyon kayit` gerekir | Davranış aynı. `pms_housekeeping_cikis_uret` **aynı izni** ister, yeni izin gerekmez. Modül kapalıysa görev üretmez; açıksa `cikis_temizligi` görevi açar. |
| DELETE `pms_odalar` | Arayüzde çağrı yok | Hak geri alınır (§27) |

**Sonuç:** Adım 1 commit edildiği anda eski arayüzden kirli bir oda temize çekilemez. Temiz odalarda check-in ve tüm odalarda check-out çalışmaya devam eder.

### 1.7 Diğer bulgular

1. **Modülü kapatmak engeli kaldırmaz.** Mimari §24.1: *"Disabling is not a complete restoration of the old Phase 1 cleaning UI."* Yerel kanıt: son kabul testlerinden M1, M2–M4, M5 ve M7, `authenticated` rolüyle koşuldu.
2. **`service_role` yedi tetikleyici fonksiyonunda EXECUTE hakkı taşıyor.** Canlı varsayılan ACL (`public/postgres`) bunu doğruluyor. Bu fonksiyonlar `returns trigger` olduğu için RPC olarak çağrılamaz; 2026-09-08 bulgusuyla aynı sınıftır. Arayüz ve RPC yüzeyinde `service_role` EXECUTE sayısı 0 (X16). Kayda geçer, yayın engeli değildir.
3. **Yayından sonra 09-07 eşitlik dosyası beklenen SAPMA satırları verecek:**
   - 20 `pms_housekeeping_*` fazla fonksiyon;
   - `phase0_private` fonksiyon sayısı 11;
   - `audit=21`, `otel_degismez=35`;
   - `phase0_otel_kisit` 37;
   - PMS tablo sayısı 10;
   - 236 politika / 76 tablo; 41 kısıtlayıcı.

   Bu liste dışındaki her SAPMA gerçek bir sapmadır.
4. **Yetki ekranında modül başlığına tıklamak modülü açıp kapatır** (`yetki-yonetimi.html:103, 163-173`).
5. **Yeni arayüz modül kapalıyken bozulmaz:** `hkOzetYukle()` hatayı yakalar ve kat hizmetleri satırını gizler.
6. **SQL Editor migration'larda da "destructive operations" onayı isteyecek.** Bu kez gerçek DDL olduğu için bu beklenen davranıştır; yayın sahibi onayı bilerek verir.

---

## 2. Kalan engeller ve kararlar

| # | Tür | Konu | Durum / kapanma ölçütü |
|---|---|---|---|
| E-1 | Engel | Adım 2 SQL Editor'de çalışmıyordu | ✅ **Kapandı:** `e10a806`, tüm test paketleri yeşil |
| E-2 | Engel | Canlı veritabanı ölçülmemişti | ✅ **Kapandı:** 6 salt okuma dosyası çalıştı, 0 SAPMA (1.3) |
| E-3 | Önkoşul | Bayt düzeyinde güncel döküm yok | ⏳ Pencere günü kullanıcı `.\docs\kurulum\dokum-al.ps1 -Etiket 2026-09-XX-pre-faz2` komutunu çalıştırır; parola istemle alınır, paylaşılmaz. Prova o dökümle tekrarlanır (0.3). Bugünkü canlı doğrulama sapma göstermediği için sonucun değişmesi beklenmiyor. |
| E-4 | Karar | Dal yeniden yazımı ve push | ⏳ `2851bc5` yeniden yazımının bilinçli olduğu teyit edilmeli. Yerel daldaki `e10a806`, `7b84da2` ve plan commit'inin uzak dala push'u ayrı onay ister. R11 (`3d7c895`) ayrıca değerlendirilir. Yerel `main` yayında kullanılmaz. |
| E-5 | Karar | Kat hizmetleri rolleri ve test kullanıcıları | ⏳ Üretimde kat hizmetleri rolü ya da yetkisi yok; `pms_rezervasyon` yetkisi yalnız iki yönetici rolünde (3 kullanıcı). Karar gereken: `goruntule` / `kayit` / `tam` hangi rollere verilecek. En az **iki farklı** aktif kullanıcı gerekir (şef çalışandan farklı olmalı; her ikisinin otel ataması ya da tüm oteller yetkisi olmalı). |
| E-6 | Risk kabulü | Adım 1 commit'inden sonra eski temizlik akışına dönüş yok | ⏳ Kullanıcı kabul etmeli (§5). Bugünkü etkisi yalnız oda 102'nin çıkışı. |
| E-7 | Operasyon | Pencerede `temizleniyor` durumunda oda olmamalı | ✅ Bugün 0 (E1). Pencere başında preflight ile yeniden ölçülür. |

---

## 3. Önerilen yayın penceresi

**Öneri: 12 Eylül 2026 Cumartesi, 10:00–12:00 (İstanbul).** En geç 13 Eylül sabahı, oda 102'nin çıkışından **önce**.

- **Neden bu aralık:** bekleyen varış yok, bugün veya geçmiş tarihli planlı çıkış yok, tek dolu oda (102) 13 Eylül'de çıkacak. Pencere o çıkıştan önce tamamlanırsa bu çıkış, modül açıkken **ilk gerçek çıkış üreticisi olayı** olur. Otomatik `cikis_temizligi` görevi açılır ve ayrı test konaklaması kurmadan doğal bir kanıt elde edilir.
- **Çıkış pencerenin içine düşerse:** oda görevsiz kirli kalır (birikim). Modül açıldıktan sonra şef `ekstra_temizlik` görevi açar (mimari §24.3). Kalıcı zarar oluşmaz.
- **Pencereden önce hazır olması gerekenler:**
  - E-4 ve E-5 kararları;
  - iki test kullanıcısı;
  - `yetki_yonetimi tam` yetkili bir kullanıcı;
  - güncel döküm (E-3).
- **Süre:** Aşama 1 adımları 60–90 dakika sürer. Temizlik yolunun kapalı kalacağı süre (1.3'ten 1.8'e) için hedef en fazla 30 dakikadır; en uzun kalem Pages yayını ve 10 dakikalık önbellektir.
- **Ertelenirse:** 13 Eylül çıkışından sonraki herhangi bir düşük hareketli saat de uygundur. Tek fark, oda 102'nin birikim olarak ele alınmasıdır.

---

### GÜNCELLEME — 2026-09-12 17:55 (İstanbul)

Yukarıdaki "12 Eylül 10:00–12:00" aralığı geçti. Güncel iki seçenek:

- **Seçenek A — bugün akşam (12 Eylül, ~19:00–21:00).** Oda 102'nin planlı çıkışından (13 Eylül) önce biter; o çıkış modül açıkken ilk gerçek çıkış üreticisi olayı olur. Koşul: E-3 (güncel döküm ve prova) ile E-4/E-5 kararlarının aynı akşam tamamlanması. Prova yaklaşık 15 dakika sürer.
- **Seçenek B — 13 Eylül, oda 102'nin çıkışından sonra (önerilen).** Çıkış eski akışla tamamlanır; oda kirli kalır ve yayından sonra şef tek bir `ekstra_temizlik` görevi açar (§1.9). Pencerede hiç dolu oda kalmadığı için temizlik yolu kapalı süresinin iş etkisi sıfırdır. Hazırlık kararlarına da bir gün daha tanır.

Her iki seçenekte de 1.2'deki "öncesi" fotoğrafı pencere başında yeniden alınır: bu belgedeki canlı değerler 11 Eylül 23:30 ölçümüdür.

## 4. Yayın planı

Sıra mimari §16'yı izler: **migration → roller → uyumlu arayüz → modülü açma.**

### Aşama 0 — Pencere öncesi (üretime YAZMA YOK)

| Adım | Durum |
|---|---|
| 0.1 Adım 2 düzeltmesi ve tüm test paketleri | ✅ `e10a806` (1.4) |
| 0.2 Yayın commit'lerinin sabitlenmesi | ✅ §0. Push kararı E-4'e bağlı. |
| 0.3 Güncel döküm ve prova | ⏳ E-3. Kullanıcı `dokum-al.ps1` çalıştırır. Ajan önce `node scripts/dokum-dogrula.mjs <döküm> docs/kurulum/2026-09-07-post-pms-faz1-esitlik-dogrulama.sql` ile SAPMA olmadığını doğrular. Ardından iki migration'ı tek sorgu metni olarak uygular, preflight'ı öncesi ve sonrası için çalıştırır, test paketlerini koşar, §5'teki değişmez raporunu sınar. **Durdurma koşulları:** açıklanamayan fark (sayı zorla eşitlenmez), migration hatası, beklenmeyen preflight satırı. |
| 0.4 Canlı preflight #1 | ✅ 1.3 |
| 0.5 Rol ve kullanıcı kararı | ⏳ E-5. Mimari §16: çalışan `kayit`, şef `tam`, resepsiyon `goruntule`. |
| 0.6 Operasyon hazırlığı | Oda 102'nin çıkış saati resepsiyonla netleştirilir. Test odası `101` boş ve temiz (bugün doğrulandı). |
| 0.7 Yedek | Pencere başında Supabase panelindeki son otomatik yedeğin saati kayda geçer. |

### Aşama 1 — Yayın penceresi (`CANLIYA UYGULA` şart; runbook §1'in 12 alanı doldurulur)

**1.1 Kod dondurma**
- **Önkoşul:** `CANLIYA UYGULA` mesajı.
- **Yapılan:**
  - Yayın worktree'sinde `git status --short` boş olmalı; `git rev-parse HEAD` kayda geçer.
  - İki migration dosyasının SHA256'sı §0'daki değerlerle karşılaştırılır.
  - SQL Editor'e yapıştırılan metin, 1.3'teki yöntemle SHA256 eşleştirilerek doğrulanır.
- **Durdurma:** herhangi bir fark.

**1.2 "Öncesi" fotoğrafı (salt okuma)**
- **Yapılan:** 1.3'teki 6 dosya çalıştırılır.
- **Başarı:** değerler bugünküyle aynı, preflight `SAPMA` = 0, E1 = 0. E9 (denetim satırı sayısı) kaydedilir.
- **Durdurma:** bugünden bu yana herhangi bir fark.

**1.3 Adım 1 migration** (SQL Editor, dosyanın tamamı, tek çalıştırma)
- **Önkoşul:** 1.2 temiz.
- **Başarı:** hata yok **ve** aşağıdaki ara kontrol beklenen değerleri döndürür. "Success. No rows returned" çıktısı kanıt sayılmaz.

  ```sql
  select
    to_regclass('public.pms_housekeeping_gorevleri') is not null as gorev_tablosu,        -- true
    (select aktif from public.moduller where kod = 'pms_housekeeping') as modul_aktif,   -- false
    (select count(*) from information_schema.columns
      where table_name = 'erp_islem_audit' and column_name = 'islem_detayi') as islem_detayi, -- 1
    (select string_agg(tgname, ',' order by tgname) from pg_trigger
      where tgrelid = 'public.pms_odalar'::regclass and not tgisinternal and (tgtype & 2) <> 0) as oda_before,
      -- phase0_otel_degismez,pms_housekeeping_oda_koruma,pms_oda_envanter_kontrol,pms_oda_gecis,pms_odalar_guncelleme
    (select string_agg(privilege_type, ',' order by privilege_type) from information_schema.role_table_grants
      where table_schema = 'public' and table_name = 'pms_odalar' and grantee = 'authenticated') as oda_haklari; -- INSERT,SELECT,UPDATE
  ```

- **Durdurma:** `ERROR` alınırsa transaction kendiliğinden geri döner. Preflight'ta **A1–A9 = 0** olmalı. Analiz yapılmadan yeniden denenmez.
- **Geri dönüş (commit sonrası):** ileri yönlü düzeltme (§5).
- ⏱ Temizlik yolunun kapalı kaldığı süre burada başlar.

**1.4 Adım 2 migration** (SQL Editor, `e10a806` baytı)
- **Önkoşul:** 1.3 başarılı.
- **Başarı:**

  ```sql
  select
    to_regprocedure('public.pms_housekeeping_odalar(text,integer)') is not null as odalar,          -- true
    (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'public' and p.proname in ('pms_housekeeping_listele','pms_housekeeping_odalar')
        and p.prosecdef and exists (select 1 from unnest(p.proconfig) c where c like 'search_path=%')) as definer_pinli, -- 2
    (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'public' and p.proname in ('pms_housekeeping_listele','pms_housekeeping_odalar')
        and (has_function_privilege('anon', p.oid, 'EXECUTE')
             or has_function_privilege('service_role', p.oid, 'EXECUTE'))) as anon_veya_service; -- 0
  ```

- **Durdurma:** `ERROR` alınırsa Adım 2 geri döner, Adım 1 yerinde kalır. **Arayüz yayınlanmaz.**
- **Geri dönüş:** dosya sonundaki blok; veri etkilenmez.

**1.5 Uygulama sonrası doğrulama (salt okuma)**
- **Yapılan:** preflight ve 1.3'teki taban dosyaları yeniden çalıştırılır.
- **Başarı:**
  - Preflight'taki SAPMA satırları yalnız provadaki 19 satırdan ibaret. C1 için ölçüt "tabandan farklı" olmasıdır; yeni md5 değerine bağlanmaz, çünkü yapıştırılan metnin satır sonları farklı olabilir.
  - Sayılar 1.4'teki beklenen değerlerle aynı.
  - Eşitlik dosyasında yalnız 1.7/3'teki liste çıkar.
- **Durdurma:** liste dışında herhangi bir fark.

**1.6 Rol yetkileri** (uygulama üzerinden veri yazımı)
- **Önkoşul:** 1.5 temiz; E-5 kararı verilmiş.
- **Yapılan:** `yetki-yonetimi.html` ekranında `pms_housekeeping` sütununda rol hücreleri ayarlanır. ⚠ Modül başlığına tıklanmaz.
- **Başarı:**

  ```sql
  select r.ad, ym.yetki from public.yetki_matrisi ym
    join public.roller r on r.id = ym.rol_id join public.moduller m on m.id = ym.modul_id
   where m.kod = 'pms_housekeeping' order by r.ad;
  select aktif from public.moduller where kod = 'pms_housekeeping';   -- hâlâ false
  ```

- **Durdurma:** modül yanlışlıkla açılırsa hemen kapatılır (yalnız bayrak).
- **Geri dönüş:** hücreler `yok` yapılır.

**1.7 Arayüz yayını**
- **Önkoşul:** 1.4 ve 1.5 temiz; ön yüz push'u için **ayrı onay** alınmış.
- **Yapılan:** yayın worktree'sinden `git push origin <yayın SHA>:main`. Hızlı ileri alma; zorla push yok; yerel `main` kullanılmaz.
- **Başarı:**
  - değişen 6 arayüz dosyasının canlı SHA256'sı yayın commit'iyle aynı;
  - `pms-housekeeping.html` ve `.js` HTTP 200 dönüyor;
  - diğer dosyalar değişmemiş;
  - konsolda hata yok;
  - 10 dakikalık `max-age` beklenmiş ya da cihazlarda sayfa yenilenmiş.
- **Durdurma:** 15 dakika içinde yayına çıkmaması, hash uyuşmazlığı, beyaz sayfa.
- **Geri dönüş:** `git revert` + push. Bu temizlik yolunu geri getirmez; yalnız bozuk sayfa durumu içindir.

**1.8 Modülün etkinleştirilmesi** (ayrı adım, yalnız bayrak)
- **Önkoşul:** 1.6 ve 1.7 doğrulanmış; şef ve çalışan hazır.
- **Yapılan:** yetki ekranında modül başlığına tıklanır **ya da** SQL Editor'de tek başına şu komut çalıştırılır:

  ```sql
  update public.moduller set aktif = true where kod = 'pms_housekeeping';
  ```

  Aynı transaction'da başka değişiklik yapılmaz (mimari §24.1).
- **Başarı:**
  - `aktif = true`;
  - şef, Kat Hizmetleri ekranında listeleri görüyor;
  - Oda Planı'nda kat hizmetleri satırı görünüyor;
  - görevsiz kirli oda sayısı beklenenle tutarlı (bugün 0).
- **Durdurma:** yetkili şef için 42501 hatası, ekran hatası.
- **Geri dönüş:** `aktif = false` (§5).
- ⏱ Temizlik yolunun kapalı kaldığı süre burada biter ve kayda geçer.

**1.9 Birikim**
- Görevsiz kirli odalar için şef `ekstra_temizlik` görevi açar (§24.3). Bugünkü değer 0.

### Aşama 2 — Canlıda veri değiştiren duman testleri

`CANLIYA UYGULA` kapsamındadır. Runbook 2.7 gereği her madde gerçek bir yazma gerektirir.

**Test kayıtları:**
- Oda: `101` (boş/temiz, otel 810)
- Misafir: Faz 1 test misafiri
- Kullanıcılar: şef (`pms_housekeeping tam`), çalışan (`kayit`, şeften farklı kişi), resepsiyon (`pms_rezervasyon kayit/tam`; bugün yalnız yönetici rollerinde var)

| # | Test | Adımlar | Kanıt | Kalıcı iz | Temizleme |
|---|---|---|---|---|---|
| D1 | Ekstra temizlik, tam döngü | Şef `101` için görev açar → çalışan sahiplenir → başlatır → tamamlar → şef kontrol eder | Görev `kontrol_edildi`, `surum` her adımda +1. Oda sırasıyla kirli → temizleniyor → temiz → kontrol_edildi. `erp_islem_audit`'in yeni satırlarında `islem_detayi` alanında `eski_durum`/`yeni_durum` var, not içeriği yok. | 1 terminal görev + denetim satırları | Gerekmez, yapılamaz da: görev geçmişi kanıttır. Oda satılabilir durumda kalır. |
| D2 | Çıkış üreticisi | **Tercih:** oda 102'nin 13 Eylül'deki gerçek çıkışı (pencere çıkıştan önce tamamlandıysa). **Alternatif:** `101` için bugün→yarın test rezervasyonu açılır, onaylanır (folyo açılır), check-in, hemen check-out. | Oda `bos+kirli`. `cikis_temizligi` görevi `bekliyor` durumunda, `olusturma_kaynagi='checkout'`, `kaynak_atama_id` bu konaklamanın ataması. Oda göstergesi bu görevi gösteriyor. | Gerçek çıkışta yalnız görev. Alternatifte rezervasyon, folyo (bakiye 0), atama, görev ve denetim satırları | Görev D1 döngüsüyle kapatılır. Alternatifte folyo kapatılır; rezervasyon ve folyo silinmez, runbook'taki "üretimde kalıcı test verisi" bölümüne yazılır. |
| D3 | Faz 2 dışı denetim regresyonu (C1) | Günün **gerçek** bir işlemi (mal kabul, stok veya bar). Sahte kayıt açılmaz. | İşlem hatasız tamamlanır; yeni `erp_islem_audit` satırında `islem_detayi` NULL. | Gerçek iş kaydı | Yok |
| D4 | Yetki sınırı (veri değişmez) | `goruntule` yetkili kullanıcı komut düğmesi görmez; başka otelin kullanıcısı bu otelin görevlerini görmez | Ekran gözlemi | Yok | Yok |
| — | Eski yolun negatif testi | **Üretimde yapılmaz.** Yerelde M7 ve REST baypas testleri bunu kanıtlıyor; beklenmedik bir başarı gerçek veriyi bozar. | — | — | — |

**Toplam kanıt:** `erp_islem_audit` satır sayısı 1.2'de kaydedilen değere göre **artmış olmalı**.

### Aşama 3 — Kayıt

- Runbook §4 geçmişi ve §1'in 12 alanı doldurulur.
- Temizlik yolunun kapalı kaldığı süre ile D1 ve D2 görev kimlikleri kaydedilir.
- **Yeni taban POST-FAZ2:** `dokum-al.ps1 -Etiket <tarih>-post-pms-faz2` ile döküm alınır ve yeni eşitlik dosyası hazırlanır. 09-07 dosyaları tarihsel kanıt olarak korunur.
- Bilgi haritası güncellenir.

---

## 5. Geri dönüş sınırları (mimari §24 ile hizalı)

| Nokta | Geri dönüş | Eski temizlik akışı geri gelir mi? |
|---|---|---|
| 1.3 / 1.4 transaction içinde hata | Otomatik geri alma | Evet (değişiklik olmaz) |
| 1.3 commit sonrası | İleri yönlü düzeltme migration'ı | **Hayır** |
| 1.6 | Rol hücreleri `yok` yapılır | — |
| 1.7 | `git revert` + push | **Hayır** (veritabanı engeller) |
| 1.8 ve sonrası | **§24.1 olağan kapatma** (aşağıda) | **Hayır** |
| Üretici hatalıysa | **§24.2 onaylı acil yalıtım** (aşağıda) | Hayır |
| Yeniden açma (§24.3) | Açmadan önce aşağıdaki değişmez raporu çalıştırılır; üretici tanımları ve ACL'ler doğrulanır; ardından yalnız bayrak transaction'ı yapılır | — |
| Herhangi bir aşama | Yedekten dönüş | Evet, ama yedekten sonraki **tüm** rezervasyon, folyo ve ödeme yazmaları kaybolur. Özellik geri alma yöntemi değildir. |

**§24.1 olağan kapatma:**
- Transaction yalnız `moduller.aktif=false` içerir. Uçuştaki komutların bitmesini bekler; oda veya görev kilidi almaz.
- Kapatmadan sonra okuma ve komutlar kapanır; check-out çalışır ama görev üretmez; geçmiş korunur.
- İş etkisi: kirli ve çalışan odalar hazır hale getirilemez. Onarılmış modül yeniden açılana kadar oda devri yapılamaz.

**§24.2 onaylı acil yalıtım:**
1. Modülü kapat ve uçuştaki komutların bitmesini bekle.
2. **Yalnız** görev üreten tetikleyicileri devre dışı bırak: `pms_rezervasyonlar` üzerindeki `pms_housekeeping_cikis_uret` ve `pms_odalar` üzerindeki `pms_housekeeping_serbest_uret`. Bütünlük, denetim ve yaşam döngüsü tetikleyicilerine dokunulmaz.
3. Yaşam döngüsü geçersizleştiricisi, çıkışta bitmemiş işi iptal etmeye devam eder; iptal edilmiş görev göstergesi H7 ile tutarlıdır.
4. Bu yol kullanılmadan **önce staging'de** modül kapalıyken check-out, bloke, arıza ve check-in davranışıyla doğrulanır.
5. Onarım ileri yönlü migration ile yapılır; üreticiler modülden **önce** yeniden açılır.

**Yasak (§24.2):** `DISABLE TRIGGER ALL`, `ensure_rls`'i kapatmak, FK düşürmek, denetimi düşürmek, doğrudan görev veya temizlik DML hakkı vermek. Bekçiyi düşürerek eski akışı açmak bu planın dışındadır; ayrı tasarım ve onay gerektirir. Görev tablosunda satır varsa Adım 1'in yıkıcı geri alma bloğu çalıştırılmaz.

**§24.3 yeniden açma öncesi değişmez raporu** (salt okuma; 0.3 provasında sınanır):

```sql
select
  (select count(*) from public.pms_odalar o
    where o.temizlik_durumu = 'temizleniyor'
      and not exists (select 1 from public.pms_housekeeping_gorevleri g
                       where g.id = o.temizlik_gorevi_id and g.durum = 'temizleniyor')) as sahipsiz_calisan_oda,
  (select count(*) from public.pms_housekeeping_gorevleri g
     join public.pms_odalar o on o.id = g.oda_id and o.otel_id = g.otel_id
    where g.durum in ('bekliyor','temizleniyor') and o.temizlik_gorevi_id is distinct from g.id) as gostergesiz_bitmemis_gorev,
  (select count(*) from public.pms_housekeeping_gorevleri g
    where g.durum in ('bekliyor','temizleniyor') and g.atanan_kullanici_id is not null
      and phase0_private.hk_calisan_uygun(g.atanan_kullanici_id, g.otel_id) is not true) as gecersiz_calisan_atamasi,
  (select count(*) from public.pms_odalar o
    where o.aktif and o.kullanim_durumu = 'bos' and o.temizlik_durumu = 'kirli'
      and o.temizlik_gorevi_id is null) as gorevsiz_kirli_oda;
```

İlk üç değer 0 olmalı. Dördüncüsü birikimdir; şef bu odalar için `ekstra_temizlik` görevi açar.

## 6. Açık kararlar (özet)

1. **E-4:** dal yeniden yazımının teyidi, yerel dalın push'u, R11'in ayrıca ele alınması.
2. **E-5:** kat hizmetleri rol eşlemesi ve iki test kullanıcısı.
3. **E-6:** 1.3 commit'inden sonra eski akışa dönüş olmadığının kabulü.
4. **Pencere:** önerilen 12 Eylül 10:00–12:00 ya da başka bir tarih.
5. **E-3:** pencere günü güncel dökümün alınması.
