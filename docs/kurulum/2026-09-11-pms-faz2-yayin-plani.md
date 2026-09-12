# PMS Faz 2 — Kat Hizmetleri: Yayın Öncesi İnceleme ve Yayın Planı

**Belge tarihi:** 2026-09-11, **güncelleme:** 2026-09-12.
**Durum:** Hazırlık tamam. Canlı uygulama `CANLIYA UYGULA` talimatını bekliyor. Üretime hiçbir şey uygulanmadı; merge, push, deploy yapılmadı; modül ayarı değişmedi.
**Kapsam:** `docs/kurulum/2026-09-09-pms-faz2-adim1-housekeeping.sql`, `docs/kurulum/2026-09-10-pms-faz2-adim2-housekeeping-ui-destek.sql` ve `pms-faz2-housekeeping-ui` dalındaki arayüz.
**Salt okuma preflight:** `docs/kurulum/2026-09-11-pms-faz2-yayin-oncesi-preflight.sql`
**Yetkili şartname:** `docs/PMS-FAZ2-HOUSEKEEPING-ARCHITECTURE.md` (§16 yetki ve etkinleştirme sırası, §24 geri alma). Bu plan onunla çelişirse şartname geçerlidir.

---

## 0. Kesin yayın commit'leri ve dosya hash'leri

Yerel dal `pms-faz2-housekeeping-ui`, worktree `C:\Users\USER\Projects\gurok-mal-kabul-faz2-yayin`. **Push edilmedi.** Taban `origin/main` = `d0bd734`; dal onun üzerine hızlı ileri alınabilir (doğrulandı).

### 0.1 Veritabanı: uygulanacak iki dosya

| Dosya | Kaynak commit'ler | Son hâlini veren commit | SHA-256 (commit'lenmiş bayt) |
|---|---|---|---|
| `docs/kurulum/2026-09-09-pms-faz2-adim1-housekeeping.sql` | `d82f5b9` (artım 1) → `2c0bb17` (artım 2) → **`90b2a28`** (artım 3) | `90b2a28` | `e5a560cd5ed30536813817a4effe1768adc3d240c38bd912918190c874111e8f` |
| `docs/kurulum/2026-09-10-pms-faz2-adim2-housekeeping-ui-destek.sql` | `af3cb1d` (ilk hâli) → **`e10a806`** (SQL Editor uyumu) | `e10a806` | `7d987dd99c43554c6bd14f95d957db18726b01090ce3220147e3e2ff33a88380` |

Adım 1 dosyası `d0bd734`'ten (yani `origin/main`'den) beri değişmedi; üç artımın tamamı tek dosyada birleşiktir ve `90b2a28` ile son hâlini almıştır.

### 0.2 Satır sonu kuralı — yayın baytı hangisidir

- **Yayın baytı = commit'lenmiş bayt (LF).** Yukarıdaki SHA-256 değerleri bunlardır.
- Depo `core.autocrlf=true` ile kullanıldığı için **çalışma ağacındaki kopyalar CRLF'tir** ve farklı hash verir (Adım 1 `58156b5e…`, Adım 2 `f5112323…`). Bu kopyalar yayın kaynağı **değildir**.
- Yayın baytı şu komutla çıkarılır ve doğrulanır:

  ```bash
  git -c core.autocrlf=false archive HEAD | tar -x -C <hedef>
  sha256sum <hedef>/docs/kurulum/2026-09-09-pms-faz2-adim1-housekeeping.sql
  sha256sum <hedef>/docs/kurulum/2026-09-10-pms-faz2-adim2-housekeeping-ui-destek.sql
  ```

- **Prova ile yayın dosyalarının aynılığı doğrulandı:** 2026-09-12 provası bu LF kopyayla koşuldu; kopyadaki hash'ler yukarıdaki commit hash'leriyle birebir eşleşti.
- SQL Editor'e yapıştırılan metin de pencerede aynı hash ile doğrulanır (1.3 yöntemi). Tarayıcı satır sonlarını LF'e çevirdiği için beklenen değer commit hash'idir.

### 0.3 Yayın commit'leri

| Commit | İçerik | Yayındaki rolü |
|---|---|---|
| `4e321f3` `b9ae778` `2cc3f24` `2851bc5` | Kat hizmetleri ekranı, oda planı entegrasyonu, kabul düzeltmeleri, odalar formu | Arayüz |
| `0644bb5` | Yerel staging QA katmanı | Test (yayına etkisi yok) |
| `af3cb1d` → `e10a806` | Adım 2 migration ve SQL Editor uyumu | Veritabanı |
| `7b84da2` | Salt okuma preflight | Doküman |
| `cc95528` `68192b1` + bu güncelleme | Yayın planı | Doküman |

**Ön yüz yayını:** dalın son commit'i. Arayüz dosyaları `2851bc5` ile aynıdır; sonraki commit'ler yalnız SQL ve doküman değiştirir.

**Kapsam dışı (karar verildi):** dalın `2851bc5` olarak yeniden düzenlenmesi bilinçliydi ve önceden onaylandı. R11 commit'i `3d7c895` bu yayının dışındadır ve yalnız yerel `main`'de kalır. Yayın yerel `main`'den yapılmaz.

---

## 1. Bulgular

### 1.1 Canlıda sunulan arayüz (ölçüldü)

- `origin/main` kökündeki 76 html/js/json/css dosyasının 76'sı canlıdakiyle aynı SHA-256'ya sahip.
- `pms-housekeeping.html` ve `pms-housekeeping.js` HTTP 404 dönüyor.
- GitHub Pages yanıtında `Cache-Control: max-age=600`.
- `sw.js` network-first; yalnız `index.html`, `manifest.json`, `icon.png` önbelleğe alınıyor.

### 1.2 Canlı veritabanı — salt okuma ölçüldü (2026-09-11 23:30)

**Yöntem:** SQL Editor, rol `postgres`, "main PRODUCTION". Dosyalar elle yazılmadı; yalnız 127.0.0.1'e bağlı geçici sunucudan panoya alınıp yapıştırıldı ve **çalıştırmadan önce editördeki metnin SHA-256'sı repo dosyasıyla eşleştirildi**. Panel iki dosyada "destructive operations" uyarısı verdi; yanlış alarmdı (sorgular tek SELECT; uyarıyı metin sabitleri tetikledi).

| Dosya | Sonuç |
|---|---|
| Yayın öncesi preflight | **60 satır: 50 GECTI, 0 SAPMA, 10 BILGI** |
| POST-FAZ1 eşitlik doğrulaması | **SAPMA yok.** 28/28 gövde; 234 politika / 75 tablo; 40 kısıtlayıcı |
| POST-FAZ1 üretim parmak izi | 36 satır; `esit` satırların tamamı tabanda |
| Varsayılan ACL uyarı kontrolü | D1/D2/D3 = 0; B1=3, C1=12 bilinen platform riski |
| Event trigger tabanı | 7/7; 0 devre dışı; `ensure_rls` bağlı |
| Veritabanı düzeyi taban | 22/22 ESIT |

**Ölçülen üretim durumu (11 Eylül):** otel 810'da iki oda — `101` boş/temiz, `102` dolu/kontrol_edildi; oda 102'de 07→13 Eylül konaklaması; onaylı gelecek rezervasyon 0; `erp_islem_audit` 22 satır (son kayıt 09-08); PMS yetkisi yalnız `IT / Sistem Yöneticisi` ve `Sistem Yöneticisi` rollerinde (beş PMS modülünde `tam`, 3 aktif kullanıcı); kat hizmetleri modülü ve yetkisi yok; PostgreSQL 17.6.

### 1.3 İzole prova ve testler (yayın baytlarıyla, 2026-09-12)

**Taban:** 09-07 POST-FAZ1 dökümü + referans veri + 09-08 ACL temizliği; tek kullanımlık, ağsız PostgreSQL 17 konteyneri. Migration'lar SQL Editor'ün yaptığı gibi **tek sorgu metni** olarak uygulandı.

| Prova / paket | Sonuç |
|---|---|
| Adım 1 (tek sorgu metni) | Başarılı; dört doğrulama bloğu geçti |
| Adım 2, `e10a806` öncesi | **Başarısız:** `syntax error at or near "\"`, hiçbir şey uygulanmadı |
| Adım 2, `e10a806` | Başarılı |
| İkisini ikinci kez uygulama | Başarılı (idempotent) |
| Preflight: tabanda / migration sonrası | 50 GECTI, 0 SAPMA / tam olarak beklenen 19 SAPMA |
| `check.mjs` · `migration-guvenlik-kontrol.mjs` · denetleyici birim testleri | Yeşil · 0 HATA · 14/14 |
| housekeeping · artım 2 · artım 3 | 13/0 · 31/0 · 14/0 |
| son kabul · REST baypas · UI destek | 24/0 · 17/0 · 14/0 |
| Faz 1 regresyon | 14/0 |
| Eşzamanlılık · sabotaj | 13/0 · 9/0 |

**Uygulama sonrası beklenen değerler:** 76 tablo · 236 politika · 41 kısıtlayıcı · `pms_*` 44 (22'si `pms_housekeeping_*`) · `phase0_private.hk_*` 8 · tetikleyici 90 · anon EXECUTE 0 · `pms_odalar` authenticated `INSERT,SELECT,UPDATE` · modül `sira=49 aktif=false`.

**Prova kopyasının güncelliği:** 09-07 dökümü 11 Eylül'de canlıya karşı yeniden doğrulandı (28/28 definer gövdesi, preflight C1–C10 gövdeleri, tüm taban sayıları). Ölçülmeyenler: PMS dışı invoker gövdeleri, politika ifadelerinin metni, PMS dışı kolon varsayılanları — migration bunlara dokunmuyor. Bayt düzeyinde güncel döküm pencere günü alınacak (E-1).

### 1.4 Eski arayüzün yazma yolları (migration sonrası)

Bekçi `public.pms_housekeeping_oda_koruma()` (Adım 1 §12): `BEFORE INSERT OR UPDATE ON pms_odalar`, SECURITY INVOKER, **modül bayrağına bakmaz**.

| Canlı dosya:satır | Migration sonrası |
|---|---|
| `pms-oda-plani.html:296-300`, `:390-400` temizlik düğmeleri | **Üç geçiş de reddedilir** (42501). Eski arayüzde odayı temize çekmenin tek yolu budur. |
| `pms-odalar.html:316-323`, `:375` yeni oda | Yalnız `kirli` kabul; başka değer reddedilir |
| `pms-odalar.html:348-372` düzenleme | Değer aynıysa kabul; değişiklik red. Sayfa açıkken oda kirlendiyse ilgisiz düzenleme de red (yenileme gerekir) |
| `pms-odalar.html` kullanım seçici | Faz 1 kuralları sürer; **yeni:** `ariza` odayı kirletir, pasifleştirme çalışan işi iptal eder |
| `rpc/pms_check_in`, `rpc/pms_check_out` | Aynı yetki (`pms_rezervasyon kayit`), yeni izin gerekmez. Çıkış üreticisi modül kapalıyken görev üretmez, açıkken `cikis_temizligi` açar |

### 1.5 Kesinti sırasında veritabanından düzeltme — ÖLÇÜLDÜ (2026-09-12)

Migration uygulanmış izole kopyada, bir odayı `kirli → temiz` yazma denemeleri:

| Yol | Sonuç |
|---|---|
| S1 sahip rolü (`postgres`), kimlik ayarı yok — **SQL Editor'ün gerçek durumu** | **Yazamadı.** Denetim tetikleyicisi: `Aktif ERP personeli gerekli` |
| S2 `authenticated`, kimlik yok | Yazamadı (RLS satırı göstermiyor; hata değil, 0 satır) |
| S3 `authenticated` + gerçek ERP kimliği (kat hizmetleri yetkili) | Yazamadı (oda tablosu RLS'i `pms_oda` yetkisi ister) |
| S4 sahip rolü + gerçek bir ERP kullanıcısının kimliği ayarlanmış | **Yazdı** |
| Kat hizmetleri komutu, modül kapalı | Reddedildi: `Yetki yok` |
| Kat hizmetleri komutu, modül açık | Çalıştı; görev oluştu |

**Sonuç:** Kesinti sırasında "SQL Editor'den hızlıca düzeltiriz" seçeneği **yoktur**. Tek veritabanı yolu S4'tür; denetim kaydı, kimliği ayarlanan kullanıcının üstüne yazılır. Bu nedenle S4 yalnız §4.4'teki koşullarla kullanılır.

### 1.6 Diğer bulgular

1. Modülü kapatmak engeli kaldırmaz (§24.1; yerel kanıt M1/M2–M4/M5/M7 ve yukarıdaki S1–S3).
2. `service_role` yedi tetikleyici fonksiyonunda EXECUTE taşıyor (varsayılan ACL mirası). `returns trigger` oldukları için RPC yüzeyi 0; 09-08 bulgusuyla aynı sınıf. Kayda geçer.
3. Yayından sonra 09-07 eşitlik dosyası şu beklenen SAPMA'ları verecek: 20 `pms_housekeeping_*` fonksiyon; `phase0_private` 11; `audit=21 otel_degismez=35`; `phase0_otel_kisit` 37; PMS tablo 10; 236/76; 41. Liste dışı her SAPMA gerçek sapmadır.
4. Yetki ekranında modül başlığına tıklamak modülü açar/kapatır (`yetki-yonetimi.html:103, 163-173`).
5. Yeni arayüz modül kapalıyken bozulmaz (`hkOzetYukle()` hatayı yakalar).
6. SQL Editor migration'larda da "destructive operations" onayı isteyecek; gerçek DDL olduğu için beklenen davranıştır.

---

## 2. Kalan engeller

| # | Tür | Konu | Kapanma ölçütü |
|---|---|---|---|
| E-1 | Önkoşul | Bayt düzeyinde güncel döküm yok | Kullanıcı `.\docs\kurulum\dokum-al.ps1 -Etiket <tarih>-pre-faz2` çalıştırır (parola istemle alınır, paylaşılmaz). Ajan `dokum-dogrula.mjs` ile SAPMA olmadığını doğrular, iki migration'ı LF baytlarıyla uygular, preflight'ı öncesi/sonrası çalıştırır, paketleri koşar. |
| E-2 | Karar | Kat hizmetleri yetki matrisi ve iki test kullanıcısı | §3'teki matris onaylanır; şef ve çalışan rolündeki **iki farklı aktif kullanıcı** adıyla belirlenir. |
| E-3 | Onay | Operasyon, pencereyi ve kesinti üst sınırını onaylar | §4.1'deki pencere ve §4.2'deki 45 dakikalık üst sınır, operasyondan sorumlu kişi tarafından adıyla onaylanır. |
| E-4 | Risk kabulü | Adım 1 commit'inden sonra eski temizlik akışına dönüş yok | Kullanıcı kabul eder (§4.4, §5). |

Kapanan engeller: Adım 2'nin SQL Editor uyumu (`e10a806`), canlı veritabanı ölçümü (1.2), dal/commit kapsamı kararı (0.3), prova ile yayın baytlarının aynılığı (0.2).

---

## 3. Yetki matrisi (kesinleştirildi — E-2 onayına tabi)

Mimari §16: çalışan `kayit`, şef `tam`, resepsiyon `goruntule`. Üretimde bu roller **tanımlı ve boş**; PMS erişimi bugün yalnız iki yönetici rolünde.

| Rol | `pms_housekeeping` | Gerekçe |
|---|---|---|
| Kat Hizmetleri Şefi | `tam` | Görev açar, atar, iptal eder, denetler |
| Kat Hizmetleri Vardiya Sorumlusu | `tam` | Vardiyada şefin yerine geçer |
| Kat Hizmetleri Personeli | `kayit` | Sahiplenir, başlatır, tamamlar; denetleyemez |
| Genel Müdür (GM) | `goruntule` | Durum takibi; komut yok |
| Ön Büro Şefi | `goruntule` | Oda hazır mı görür; temizlik komutu vermez |
| Ön Büro Vardiya Sorumlusu | `goruntule` | Aynı |
| Ön Büro Personeli | `goruntule` | Aynı |
| IT / Sistem Yöneticisi | `tam` | Yayın ve duman testi; diğer PMS modüllerinde de `tam` |
| Sistem Yöneticisi | `tam` | Aynı |
| Diğer tüm roller | `yok` (satır açılmaz) | Fail-closed varsayılan |

**Uygulama notları:**
- Bir rolde kullanıcı yoksa satır etkisizdir; matris yine de kurulur ki personel tanımlandığında ek işlem gerekmesin.
- Kat hizmetleri çalışanı olacak kullanıcıların `otel_id` ataması ya da `tum_oteller` yetkisi olmalı (`hk_calisan_uygun`). Pencerede doğrulanır.
- **Denetim bağımsızlığı kullanıcı düzeyindedir:** aynı kişi hem tamamlayıp hem denetleyemez. Duman testi için `tam` yetkili **iki ayrı kullanıcı** gerekir; bugün bunlar yönetici rolündeki kullanıcılardan seçilecektir.
- Check-in/check-out `pms_rezervasyon kayit` ister; bu yetki bugün yalnız iki yönetici rolünde. Ön büro rollerine rezervasyon yetkisi vermek **Faz 1 kapsamıdır**, bu yayının parçası değildir.

---

## 4. Yayın penceresi, kesinti sınırı ve başarısızlık adımları

### 4.1 Pencere

| Alan | Değer |
|---|---|
| Önerilen | **13 Eylül 2026 Pazar, oda 102'nin çıkışı tamamlandıktan sonra, 12:00–14:00 arası** |
| Alternatif | 12 Eylül akşamı (E-1 ve E-2 aynı akşam tamamlanırsa) ya da 14 Eylül sabahı |
| Operasyon onayı | **Gerekli** — ad, rol ve saat runbook kaydına yazılır (E-3) |
| Pencere sahibi | Yayını yürüten kişi + hazır iki test kullanıcısı |

**Etki beyanı (varsayım yok):** Pencere boyunca hiçbir oda sistemde temiz işaretlenemez. Bu, o an dolu oda olup olmamasından bağımsızdır: pencere içinde çıkış yapılan, arızadan dönen ya da herhangi bir şekilde kirlenen her oda, modül açılana kadar satılamaz. Operasyon bu riski kabul etmeden pencere başlamaz. Oda 102'nin çıkışı pencere içine düşerse o oda görevsiz kirli kalır ve modül açıldıktan sonra şef `ekstra_temizlik` açar.

### 4.2 Azami kesinti süresi

- **T0** = Adım 1 migration'ının commit'lendiği an.
- **Hedef:** T+30 dakikada modül açık (1.8 tamam).
- **Azami:** **T+45 dakika.** Bu aşılırsa §4.4 devreye girer.
- Ara kontroller: **T+10** Adım 2 doğrulanmış; **T+25** arayüz canlıda doğrulanmış; **T+35** modül açık.
- Süre ölçümü ve her ara kontrolün saati runbook kaydına yazılır.

### 4.3 Adım adım başarısızlık davranışı

| Adım | Başarısızlık | Yapılacak |
|---|---|---|
| 1.3 Adım 1 | `ERROR` | Transaction kendiliğinden geri döner. Preflight ile **A1–A9 = 0** doğrulanır (yarım uygulama yok). Yayın iptal edilir, pencere kapatılır, sebep raporlanır. Kesinti başlamamıştır. |
| 1.4 Adım 2 | `ERROR` | Adım 1 yerinde kalır; kesinti işlemektedir. 10 dakika içinde ileri yönlü düzeltme mümkünse uygulanır. Değilse arayüz **yayınlanmaz**, modül **açılmaz** ve §4.4'e geçilir. |
| 1.5 Doğrulama | Beklenen 19 SAPMA dışında fark | Durulur, fark raporlanır. Modül kapalı kalır; arayüz yayınlanmaz. §4.4 zaman sınırına tabidir. |
| 1.6 Yetkiler | Yanlış seviye | Hücre düzeltilir. Modül yanlışlıkla açıldıysa aynı dakika kapatılır ve kayda geçer. |
| 1.7 Arayüz | Pages 15 dakikada yayına çıkmadı, hash uyuşmadı ya da beyaz sayfa | `git revert` **çözüm değildir** (eski temizlik yolunu geri getirmez). Doğrudan §4.4/C1'e geçilir: arayüz yetkili bir makinede yerelden çalıştırılır ve modül açılır. |
| 1.8 Modül | Yetkili şefe 42501 | Yetki matrisi ve `hk_calisan_uygun` koşulları (otel ataması) kontrol edilir. 10 dakikada çözülmezse §4.4. |

### 4.4 Kesinti üst sınırı aşılırsa

Geri dönüş yoktur; yalnız ileri yol vardır. Sırayla:

1. **C1 — arayüzü yerelden çalıştır (tercih edilen).** Yayın commit'indeki `pms-housekeeping.html`, `pms-housekeeping.js` ve bağımlılıkları yetkili bir makinede yerel olarak açılır; üretim yapılandırmasıyla çalışır. Kat hizmetleri komutları normal yoldan, gerçek kullanıcı kimliğiyle işler. Modül açık olmalıdır. Pages düzelince bu köprü kapatılır. Kayda geçer.
2. **C2 — sahip rolüyle tek oda düzeltmesi (son çare, ayrı onay).** Ölçülen tek veritabanı yolu (1.5/S4). Koşullar:
   - Kullanıcının o anda verdiği açık onay;
   - kimlik ayarı, işlemi fiilen yapan kişinin `auth_user_id` değeri olur — **başkasının kimliği kullanılmaz**, çünkü denetim kaydı o kişinin üstüne yazılır;
   - tek seferde tek oda; gösterge (`temizlik_gorevi_id`) NULL bırakılır;
   - her satır, gerekçesi ve saatiyle runbook'a yazılır;
   - modül ve bekçiler kapatılmaz, ACL değiştirilmez, yetki verilmez.
3. **C3 — operasyonel duraklatma.** C1 ve C2 uygulanamıyorsa etkilenen odalar satışa kapatılır ve düzeltme bir sonraki pencereye bırakılır.

---

## 5. Yayın adımları

Sıra mimari §16'dır: **migration → roller → uyumlu arayüz → modülü açma.**

### Aşama 0 — Pencere öncesi (üretime yazma yok)

| Adım | Durum |
|---|---|
| 0.1 Adım 2 düzeltmesi ve tüm paketler | ✅ `e10a806` (1.3) |
| 0.2 Yayın commit'leri ve hash'ler | ✅ §0 |
| 0.3 Güncel döküm ve prova | ⏳ E-1 |
| 0.4 Canlı preflight | ✅ 1.2 |
| 0.5 Yetki matrisi ve test kullanıcıları | ⏳ E-2 (§3) |
| 0.6 Pencere ve kesinti sınırı onayı | ⏳ E-3 (§4.1, §4.2) |
| 0.7 Yedek | Pencere başında son otomatik yedeğin saati kayda geçer |

### Aşama 1 — Pencere (`CANLIYA UYGULA` şart; runbook §1'in 12 alanı doldurulur)

**1.1 Kod dondurma.** `git status --short` boş; `git rev-parse HEAD`; LF baytlarının SHA-256'sı §0.1 ile karşılaştırılır; SQL Editor'e yapıştırılan metin de aynı hash ile doğrulanır. Fark varsa durulur.

**1.2 "Öncesi" fotoğrafı.** 1.2'deki altı dosya. Beklenen: preflight `SAPMA` = 0, E1 = 0. `erp_islem_audit` satır sayısı kaydedilir.

**1.3 Adım 1 migration.** SQL Editor, dosyanın tamamı, tek çalıştırma. **T0 burada başlar.** "Success. No rows returned" kanıt değildir; ara kontrol:

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

**1.4 Adım 2 migration.** Ara kontrol:

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

**1.5 Uygulama sonrası doğrulama.** Preflight ve taban dosyaları yeniden. Beklenen SAPMA listesi 1.3 ve 1.6/3'tedir. C1 ölçütü "tabandan farklı"dır; yeni md5 değerine bağlanmaz.

**1.6 Yetkiler.** `yetki-yonetimi.html` ekranında §3'teki matris uygulanır. Modül başlığına tıklanmaz. Doğrulama:

```sql
select r.ad, ym.yetki from public.yetki_matrisi ym
  join public.roller r on r.id = ym.rol_id join public.moduller m on m.id = ym.modul_id
 where m.kod = 'pms_housekeeping' order by r.ad;
select aktif from public.moduller where kod = 'pms_housekeeping';   -- hâlâ false
```

**1.7 Arayüz yayını.** Ayrı ön yüz onayıyla `git push origin <yayın SHA>:main` (hızlı ileri alma). Başarı: değişen 6 dosyanın canlı SHA-256'sı yayın commit'iyle aynı; iki yeni dosya HTTP 200; konsolda hata yok; 10 dakikalık önbellek beklendi.

**1.8 Modülü açma.** Tek başına:

```sql
update public.moduller set aktif = true where kod = 'pms_housekeeping';
```

Başarı: `aktif = true`; şef ekranda listeleri görüyor; oda planında kat hizmetleri satırı var. **Kesinti burada biter.**

**1.9 Birikim.** Görevsiz kirli odalar için şef `ekstra_temizlik` açar.

### Aşama 2 — Veri değiştiren duman testleri

| # | Test | Kanıt | Kalıcı iz |
|---|---|---|---|
| D1 | Şef görev açar → çalışan sahiplenir, başlatır, tamamlar → **ikinci** kullanıcı (şef) kontrol eder | Görev `kontrol_edildi`, `surum` +1'er; oda kirli → temizleniyor → temiz → kontrol_edildi; denetim satırlarında `islem_detayi` durum geçişini taşıyor, not içeriğini taşımıyor | 1 terminal görev + denetim satırları |
| D2 | Çıkış üreticisi: tercihen oda 102'nin gerçek çıkışı; olmazsa `101` için test rezervasyonu → check-in → check-out | Oda `bos+kirli`; `cikis_temizligi` görevi `bekliyor`, `olusturma_kaynagi='checkout'`, gösterge bu görevi işaret ediyor | Gerçek çıkışta yalnız görev; alternatifte rezervasyon + folyo (bakiye 0, kapatılır) |
| D3 | Faz 2 dışı denetim regresyonu: günün gerçek bir işlemi (mal kabul/stok/bar) | Yeni `erp_islem_audit` satırı, `islem_detayi` NULL | Gerçek iş kaydı |
| D4 | Yetki sınırı (yazma yok): `goruntule` kullanıcı komut düğmesi görmez | Ekran gözlemi | Yok |

Eski yolun negatif testi üretimde yapılmaz; yerelde M7, REST baypas ve 1.5/S1–S3 kanıtlıyor. Toplam kanıt: `erp_islem_audit` sayısı 1.2 değerine göre artmalı.

### Aşama 3 — Kayıt

Runbook §4 geçmişi ve §1'in 12 alanı; kesinti süresi ve ara kontrol saatleri; D1/D2 görev kimlikleri; yeni taban POST-FAZ2 dökümü ve eşitlik dosyası; bilgi haritası.

---

## 6. Geri dönüş sınırları (mimari §24)

| Nokta | Geri dönüş | Eski temizlik akışı geri gelir mi? |
|---|---|---|
| 1.3 / 1.4 transaction içinde hata | Otomatik geri alma | Evet (değişiklik olmaz) |
| 1.3 commit sonrası | İleri yönlü düzeltme | **Hayır** |
| 1.6 | Rol hücreleri `yok` | — |
| 1.7 | `git revert` + push | **Hayır** (veritabanı engeller) |
| 1.8 sonrası | §24.1 olağan kapatma: yalnız `moduller.aktif=false` içeren transaction; uçuştaki komutları bekler, oda/görev kilidi almaz. Sonrasında komutlar kapanır, check-out sürer ama görev üretmez, geçmiş korunur. | **Hayır.** Kirli odalar hazır hâle getirilemez. |
| Üretici hatalıysa | §24.2: modülü kapat, uçuşu boşalt, **yalnız** `pms_housekeeping_cikis_uret` ve `pms_housekeeping_serbest_uret` tetikleyicilerini devre dışı bırak; bütünlük/denetim/yaşam döngüsü tetikleyicilerine dokunma; önce staging'de doğrula; ileri yönlü migration ile onar; üreticileri modülden önce aç. | Hayır |
| Yeniden açma | §24.3 değişmez raporu (aşağıda) temiz olmalı | — |
| Her aşama | Yedekten dönüş | Evet, ama yedekten sonraki tüm rezervasyon, folyo ve ödeme yazmaları kaybolur. Özellik geri alma yöntemi değildir. |

**Yasak (§24.2):** `DISABLE TRIGGER ALL`, `ensure_rls`'i kapatmak, FK düşürmek, denetimi düşürmek, uygulama rollerine doğrudan görev/temizlik DML hakkı vermek. Görev tablosunda satır varsa Adım 1'in yıkıcı geri alma bloğu çalıştırılmaz.

**§24.3 yeniden açma öncesi değişmez raporu (salt okuma):**

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

İlk üç değer 0 olmalı; dördüncüsü birikimdir.
