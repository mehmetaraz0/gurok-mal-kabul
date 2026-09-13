# PMS Faz 2 — Kat Hizmetleri: Yayın Öncesi İnceleme ve Yayın Planı

**Belge tarihi:** 2026-09-11 · **Güncelleme:** 2026-09-12 (kabul koşulları, zaman çizelgesi, acil müdahale ayrımı).
**Durum:** Teknik değerlendirme olumlu; canlı uygulama onayı **yok**. Üretime hiçbir şey uygulanmadı; merge, push, deploy yapılmadı; modül ayarı değişmedi.
**Kapsam:** `docs/kurulum/2026-09-09-pms-faz2-adim1-housekeeping.sql`, `docs/kurulum/2026-09-10-pms-faz2-adim2-housekeeping-ui-destek.sql` ve `pms-faz2-housekeeping-ui` dalındaki arayüz.
**Salt okuma preflight:** `docs/kurulum/2026-09-11-pms-faz2-yayin-oncesi-preflight.sql`
**Yetkili şartname:** `docs/PMS-FAZ2-HOUSEKEEPING-ARCHITECTURE.md` (§16 yetki ve etkinleştirme sırası, §24 geri alma). Bu plan onunla çelişirse şartname geçerlidir.

---

## 0. Kesin yayın commit'leri ve dosya hash'leri

Yerel dal `pms-faz2-housekeeping-ui`, worktree `C:\Users\USER\Projects\gurok-mal-kabul-faz2-yayin`. **Push edilmedi.** Taban `origin/main` = `d0bd734`; dal onun üzerine hızlı ileri alınabilir (doğrulandı).

### 0.1 Uygulanacak iki veritabanı dosyası

| Dosya | Kaynak commit'ler | Son hâlini veren | SHA-256 (commit'lenmiş bayt) |
|---|---|---|---|
| `2026-09-09-pms-faz2-adim1-housekeeping.sql` | `d82f5b9` (artım 1) → `2c0bb17` (artım 2) → `90b2a28` (artım 3) | **`90b2a28`** | `e5a560cd5ed30536813817a4effe1768adc3d240c38bd912918190c874111e8f` |
| `2026-09-10-pms-faz2-adim2-housekeeping-ui-destek.sql` | `af3cb1d` (ilk hâli) → `e10a806` (SQL Editor uyumu) | **`e10a806`** | `7d987dd99c43554c6bd14f95d957db18726b01090ce3220147e3e2ff33a88380` |

Adım 1 dosyası `origin/main`'den (`d0bd734`) beri değişmedi; üç artım tek dosyada birleşiktir.

### 0.2 Yayın baytı tanımı

- **Yayın baytı = commit'lenmiş bayt (LF).** Yukarıdaki hash'ler bunlardır.
- Depo `core.autocrlf=true` ile kullanıldığından **çalışma ağacındaki kopyalar CRLF'tir** ve başka hash verir (Adım 1 `58156b5e…`, Adım 2 `f5112323…`). Bunlar yayın kaynağı değildir.
- Çıkarma ve doğrulama:

  ```bash
  git -c core.autocrlf=false archive HEAD | tar -x -C <hedef>
  sha256sum <hedef>/docs/kurulum/2026-09-09-pms-faz2-adim1-housekeeping.sql
  sha256sum <hedef>/docs/kurulum/2026-09-10-pms-faz2-adim2-housekeeping-ui-destek.sql
  ```

- **Prova edilen dosyalar = yayın dosyaları:** 2026-09-12 provaları bu LF kopyayla koşuldu ve kopyanın hash'leri commit hash'leriyle birebir eşleşti.
- SQL Editor'e yapıştırılan metin pencerede aynı yöntemle doğrulanır; tarayıcı satır sonlarını LF'e çevirdiği için beklenen değer commit hash'idir.

### 0.3 Yayın commit'leri

| Commit | İçerik | Rol |
|---|---|---|
| `4e321f3` `b9ae778` `2cc3f24` `2851bc5` | Kat hizmetleri ekranı, oda planı entegrasyonu, kabul düzeltmeleri, odalar formu | Arayüz |
| `0644bb5` | Yerel staging QA katmanı | Test |
| `af3cb1d` → `e10a806` | Adım 2 migration ve SQL Editor uyumu | Veritabanı |
| `7b84da2` | Salt okuma preflight | Doküman |
| `cc95528` `68192b1` `85e305f` + bu güncelleme | Yayın planı | Doküman |

**Kapsam dışı (karara bağlandı):** dalın `2851bc5` olarak yeniden düzenlenmesi bilinçliydi ve önceden onaylandı; R11 commit'i `3d7c895` bu yayının dışındadır ve yalnız yerel `main`'de kalır. Yayın yerel `main`'den yapılmaz.

---

## 1. Bulgular

### 1.1 Canlıda sunulan arayüz (ölçüldü)

`origin/main` kökündeki 76 dosyanın 76'sı canlıdakiyle aynı SHA-256'ya sahip. `pms-housekeeping.html` ve `.js` HTTP 404. GitHub Pages `Cache-Control: max-age=600`. `sw.js` network-first; yalnız `index.html`, `manifest.json`, `icon.png` önbelleğe alınıyor.

### 1.2 Canlı veritabanı — salt okuma (2026-09-11 23:30)

SQL Editor, rol `postgres`, "main PRODUCTION". Dosyalar elle yazılmadı; yerel sunucudan panoya alınıp yapıştırıldı ve **çalıştırmadan önce editördeki metnin SHA-256'sı repo dosyasıyla eşleştirildi**.

| Dosya | Sonuç |
|---|---|
| Yayın öncesi preflight | **60 satır: 50 GECTI, 0 SAPMA, 10 BILGI** |
| POST-FAZ1 eşitlik doğrulaması | SAPMA yok; 28/28 gövde; 234 politika / 75 tablo; 40 kısıtlayıcı |
| POST-FAZ1 üretim parmak izi | 36 satır; `esit` satırların tamamı tabanda |
| Varsayılan ACL uyarı kontrolü | D1/D2/D3 = 0; B1=3, C1=12 bilinen platform riski |
| Event trigger tabanı | 7/7, 0 devre dışı, `ensure_rls` bağlı |
| Veritabanı düzeyi taban | 22/22 ESIT |

**Üretim durumu:** otel 810'da iki oda (`101` boş/temiz, `102` dolu/kontrol_edildi); oda 102'de 07→13 Eylül konaklaması; onaylı gelecek rezervasyon 0; `erp_islem_audit` 22 satır; PMS yetkisi yalnız `IT / Sistem Yöneticisi` ve `Sistem Yöneticisi` rollerinde; kat hizmetleri modülü ve yetkisi yok; PostgreSQL 17.6.

### 1.3 İzole prova ve test paketleri (yayın baytları + güncel döküm, 2026-09-12)

**Güncel döküm alındı (E-1 kapandı).** Dökümler **repo dışında** tutulur: `C:/Users/USER/ERP-Yedek` (erişim yalnız kullanıcı ve SYSTEM; kalıtım kaldırıldı). `2026-09-12-pre-faz2-sema-dokumu.sql` (340.833 bayt, sha256 `5cdef40e…`) ve `2026-09-12-pre-faz2-referans-veri.sql` (110.508 bayt, sha256 `12919335…`). Depo herkese açık olduğu için döküm **commit edilmez**; `.gitignore` yeni dökümleri engeller ve `dokum-al.ps1` varsayılan olarak repo dışına yazar (`-Hedef`, `GUROK_YEDEK`). Döküm doğrulaması: hatasız yüklendi, **28/28 fonksiyon gövdesi eşleşti**, 234 politika / 75 tablo, 40 kısıtlayıcı → 09-07 tabanına göre **sapma yok**. Referans veri de değişmemiş (37 rol, 675 yetki satırı, aynı PMS yetkileri).

Taban: **2026-09-12 dökümü** + referans veri + 09-08 ACL temizliği; ağsız, tek kullanımlık PostgreSQL 17. Migration'lar SQL Editor'ün yaptığı gibi tek sorgu metni olarak uygulandı. Aynı zincir 09-07 dökümüyle de koşuldu ve sonuçlar birebir aynı çıktı.

| Prova / paket | Sonuç |
|---|---|
| Adım 1 (tek sorgu metni) | Başarılı; dört doğrulama bloğu geçti |
| Adım 2, `e10a806` öncesi (09-07 dökümünde ölçüldü) | Başarısız: `syntax error at or near "\"`, hiçbir şey uygulanmadı |
| Adım 2, `e10a806` | Başarılı |
| İkinci kez uygulama | Başarılı (idempotent) |
| Preflight: tabanda / migration sonrası | 50 GECTI, 0 SAPMA / tam olarak beklenen 19 SAPMA |
| `check.mjs` · denetleyici · birim testleri | Yeşil · 0 HATA · 14/14 |
| housekeeping · artım 2 · artım 3 | 13/0 · 31/0 · 14/0 |
| son kabul · REST baypas · UI destek | 24/0 · 17/0 · 14/0 |
| Faz 1 regresyon · eşzamanlılık · sabotaj | 14/0 · 13/0 · 9/0 |

**Uygulama sonrası beklenen değerler:** 76 tablo · 236 politika · 41 kısıtlayıcı · `pms_*` 44 (22'si `pms_housekeeping_*`) · `hk_*` 8 · tetikleyici 90 · anon EXECUTE 0 · `pms_odalar` authenticated `INSERT,SELECT,UPDATE` · modül `sira=49 aktif=false`.

**Prova kopyasının güncelliği:** Prova, 2026-09-12 tarihli üretim dökümüyle koşuldu. Aynı döküm canlıya karşı doğrulandı (28/28 gövde, 234/75, 40). 09-07 dökümüyle yapılan ilk koşunun sonuçları birebir aynıdır; bu, aradaki beş günde şemanın değişmediğini ikinci kez gösterir.

### 1.4 Eski arayüzün yazma yolları (migration sonrası)

Bekçi `public.pms_housekeeping_oda_koruma()`: `BEFORE INSERT OR UPDATE ON pms_odalar`, SECURITY INVOKER, **modül bayrağına bakmaz**.

| Canlı dosya:satır | Migration sonrası |
|---|---|
| `pms-oda-plani.html:296-300`, `:390-400` | Üç temizlik geçişi de reddedilir (42501) |
| `pms-odalar.html:316-323`, `:375` | Yeni oda yalnız `kirli` doğar |
| `pms-odalar.html:348-372` | Aynı değer kabul; değişiklik red; bayat anlık görüntüde ilgisiz düzenleme de red |
| `pms-odalar.html` kullanım seçici | Faz 1 kuralları sürer; `ariza` odayı kirletir; pasifleştirme çalışan işi iptal eder |
| `rpc/pms_check_in` · `rpc/pms_check_out` | Aynı yetki; yeni izin gerekmez. Çıkış üreticisi modül kapalıyken üretmez, açıkken `cikis_temizligi` açar |

### 1.5 Kesinti sırasında veritabanından düzeltme — ölçüldü (2026-09-12)

Migration uygulanmış izole kopyada, bir odayı `kirli → temiz` yazma denemeleri:

| Yol | Sonuç |
|---|---|
| S1 sahip rolü (`postgres`), kimlik ayarı yok — **SQL Editor'ün gerçek durumu** | Yazamadı: `Aktif ERP personeli gerekli` |
| S2 `authenticated`, kimlik yok | Yazamadı (RLS satırı göstermiyor) |
| S3 `authenticated` + gerçek kat hizmetleri kimliği | Yazamadı (oda tablosu RLS'i `pms_oda` yetkisi ister) |
| S4 sahip rolü + gerçek bir ERP kullanıcısının kimliği ayarlanmış | **Yazdı** |
| Kat hizmetleri komutu, modül kapalı / açık | Red (`Yetki yok`) / Çalıştı, görev oluştu |

**Sonuç:** Kesinti sırasında "SQL Editor'den hızlıca düzeltiriz" seçeneği yoktur. Tek veritabanı yolu S4'tür ve denetim kaydı, kimliği ayarlanan kullanıcının üstüne yazılır. Bu yüzden S4 olağan kurtarma adımı **değildir**; §5.5'teki ayrı, kontrollü acil müdahaledir.

### 1.6 Negatif yetki testleri — gerçek rol seviyeleriyle (2026-09-12)

§4'teki matris, **üretimdeki gerçek rol adlarıyla** izole kopyaya kuruldu ve her rol için kullanıcı açıldı. Sonuç: **32 OK / 0 FAIL.**

| Grup | Ölçülen |
|---|---|
| `goruntule` (Ön Büro Personeli) | Kuyruğu okur; görev **açamaz** (`Yetki yok`) |
| Matriste satırı olmayan rol (Bar Personeli) | Kuyruğu **okuyamaz**, görev açamaz |
| Pasif kullanıcı (`aktif=false`, rolü `kayit`) | Okuyamaz, komut veremez (`Aktif ERP personeli gerekli`) |
| `kayit` (Kat Hizmetleri Personeli) | Sahiplenir, başlatır, tamamlar; görev **açamaz**, başkasını **atayamaz**, **iptal edemez**, kendi işini **denetleyemez** |
| `tam` (Şef / Vardiya Sorumlusu) | Açar, atar (atama kalıcı doğrulandı), başkasının işini denetler; atanmış görevi **sahiplenemez**; **kendi tamamladığı işi denetleyemez** — ikinci `tam` kullanıcı denetler |
| Otel izolasyonu (811 şefi) | 810 kuyruğunu, odasını ve görevini **göremez** |
| Oda seçici (dar izdüşüm) | Yalnız `tam` okur; `kayit`, `goruntule` ve diğer otel **okuyamaz** |

Test kurgusuna dair not: hedef kullanıcı kimliği ilk denemede uygulama rolüyle alt sorgudan çözülmüştü; RLS o satırı gizlediği için NULL geçti ve `ata` "atamayı kaldır" olarak çalıştı. Kimlik sahip rolünde çözülerek düzeltildi. **Ders:** istemciden gelen alt sorgu, RLS altında sessizce NULL dönebilir.

### 1.7 Yerel arayüz kurtarma provası (2026-09-12)

C1 müdahalesi (arayüzü GitHub Pages yerine yerel bir kaynaktan sunmak) provada uçtan uca çalıştırıldı:

- Yayın baytları yerel staging üzerinden `http://127.0.0.1:8791` adresinden sunuldu.
- Oturumsuz erişim giriş ekranına yönlendi (fail-closed).
- PIN ile giriş → `pms-housekeeping.html` açıldı; İşlerim / Bekleyen / Kontrol / Tümü sekmeleri ve sayaçlar çalıştı.
- `tam` yetkili kullanıcıda "+ Görev aç" göründü; **oda seçici doldu** (`pms_housekeeping_odalar` RPC'si) ve oda 101 için **gerçek bir görev açıldı**; kart listeye düştü.
- Tek konsol hatası: service worker kaydı bu ortamda başarısız oldu. Uygulama etkilenmedi (network-first tasarım); C1 için engel değildir, kayda geçer.

### 1.8 Yedek gerçeği — ölçüldü (2026-09-12)

Supabase panelinden okundu:

- Proje **Free plan**da: *"Free Plan does not include project backups."* **Zamanlanmış proje yedeği yok**; point-in-time kurtarma da yok.
- Veritabanı parolası oluşturulduktan sonra **görüntülenemiyor**, yalnız sıfırlanabiliyor ("Resetting it will break any existing connections").

Bu, runbook §5'teki "Otomatik günlük yedek (Supabase Pro)" ifadesiyle çelişiyor. Tarihsel kayıt silinmedi; runbook'a tarihli DÜZELTME (§7) eklendi.

**Kapsam ve görünürlük eşitlendi:** sayaç sorgusu, yedeğin kapsadığı iki şemayı (`public` + `phase0_private`) sayar ve çıktısına sayımın yapıldığı rolü, `bypassrls` bayrağını ve FORCE RLS tablo sayısını yazar; geri yükleme provası aynı sorguyu aynı kapsamla çalıştırır. Bugün `phase0_private` şemasında tablo yoktur (yalnız fonksiyon), üretimde FORCE RLS tablo 0'dır ve her iki taraf da `postgres` rolüyle sayar.

**Yedeğin kurtarma kapsamı — ölçüldü (2026-09-13).** Yedek `--schema=public --schema=phase0_private` ile alınır; 2026-09-12 şema dökümünde bu iki şemadan başkası yoktur. Kapsam dışında kalanlar: **`auth` şeması** (`auth.users`, kimlikler, oturumlar), `storage`, `realtime`, veritabanı rolleri, uzantılar ve proje ayarları. Ölçülebilir sonucu: şema dökümünün 6349. satırındaki `kullanicilar_auth_user_id_fkey` `auth.users(id)`'ye bakar, veri yedeğinde o satırların karşılığı **yoktur**.

| Senaryo | Bu yedek ne sağlar |
|---|---|
| **Aynı projede veri kaybı** (yanlış silme, bozulan tablo) | Tam: `public` + `phase0_private` verisi geri yüklenir; `auth` yerinde durduğu için **girişler çalışır**. Geçerli kurtarma senaryosu budur. |
| **Proje/veritabanı tümden kaybı** | Kısmi: iş verisi geri gelir, **kimse giriş yapamaz**. Kimliklerin yeniden oluşturulması ve `kullanicilar.auth_user_id` eşlemesinin elle kurulması gerekir. Bu yedek **felaket kurtarma yedeği değildir**. |

Sayaç dosyası bu boşluğu sayıya çevirir (`kurtarma_kapsami`): kaç ayrı kimlik gerekiyor, kaçı aktif kullanıcıya ait, `auth` şemasında bugün kaç tablo var. Prova aynı ölçümü geri yüklenen kopyada tekrarlar ve **yedekten kaç kimlik geldiğini** (beklenen: 0) yazar; eksik kimlikleri yalnız provayı yürütebilmek için üretir ve ürettiğini raporlar.

**Yedek alma otomatikleştirildi (2026-09-13).** `docs/kurulum/yedek-ve-sayac-al.ps1` veri yedeğini ve sayaçları **tek parola istemiyle** üretir; parola komut satırına ve PowerShell geçmişine yazılmaz. Varsayılan yol (A) `yedek-snapshot-surucu.sql` ile aynı snapshot'tır: `begin isolation level repeatable read` → `pg_export_snapshot()` → işlem AÇIKKEN `pg_dump --snapshot=<kimlik>` → sayaçlar aynı işlemden. `-Duraklatma` ile yol (B) sayaçları yedekten önce ve sonra okur ve **eşit değillerse yedeği reddeder**. Mekanizma yerel bir PostgreSQL 17 kopyasına karşı uçtan uca doğrulandı (snapshot dışa aktarımı, `--snapshot` ile pg_dump, aynı işlemden sayaç okuma, `commit`). Pooler snapshot dışa aktarımını desteklemezse (A) hata verir; betik bunu söyler ve (B)'yi önerir — tahmin etmez.

**Geri yükleme provası iki yeni ölçüm kazandı (2026-09-13).** Yerel denemeler iki gerçek sorunu ortaya çıkardı:

1. `--data-only` yedek FK sırasına uymaz (pg_dump'ın kendi uyarısı: `hesap_plani` üzerinde dairesel FK) ve `kullanicilar` satırları `auth.users` boş olduğu için reddedilirdi. Yükleme artık `session_replication_role = replica` ile yapılır.
2. Tetikleyiciler açık kalsaydı yükleme **denetim izine satır yazardı**; satır sayıları üretimle tutmazdı.

Bütünlük bu yüzden varsayılmaz, **sonradan kanıtlanır**: prova `public` + `phase0_private` şemalarındaki her yabancı anahtarı düşürür, `not valid` olarak geri ekler ve `validate constraint` çalıştırır. Yerel denemede **61 FK doğrulandı, ihlal 0**.

**Mekanizma denemesi (2026-09-13, yerel sentetik veri):** şema dökümü + referans veri + iki sentetik kullanıcı içeren yerel kopyadan yukarıdaki otomasyonla yedek alındı ve prova tam koştu. 75 tablo → fark 0; auth kapsamı → 2 kimlik gerekiyor, yedekten 0 geldi; 61 FK → ihlal 0; üç tutarlılık kontrolü → 0; uygulama erişimi → 5/5 geçti (`anon` kapalı). Süreler: hazırlık 0,8 sn · geri yükleme 0,2 sn · auth kapsamı 0,6 sn · FK bütünlüğü 0,3 sn · satır sayıları 0,2 sn · tutarlılık 0,6 sn · uygulama erişimi 1,2 sn. **Bu bir kabul kanıtı değildir**: veri üretimden gelmemiştir. Çıktı hangi sayaç dosyasından beslendiğini (`alinma_zamani`, sunucu sürümü, rol) kendi içinde yazar ki yerel deneme ile üretim provası karıştırılmasın.

**E-5 provası — ÜRETİM YEDEĞİYLE, 2026-09-13.** Yedek `yedek-ve-sayac-al.ps1` ile aynı snapshot yolundan alındı (`aws-0-ap-northeast-1`, tek parola istemi, 54,7 sn). Üretilenler repo dışında: `C:\Users\USER\ERP-Yedek\2026-09-13-pre-faz2-veri-yedegi.sql` (757.033 bayt, SHA-256 `7D3AFF78B5F1807460157A2766AE59BF019981EE4E973D32D60555B3B77456DA`) ve `2026-09-13-pre-faz2-sayaclar.json`. Sayaçların okuduğu an: **2026-09-13T07:40:53Z** (sunucu 17.6, rol `postgres`, `bypassrls` true, FORCE RLS tablo 0). Üretim büyüklüğü: 75 tablonun 57'si dolu, toplam 6.512 satır; denetim izi 22 satır (son kayıt 2026-09-08T19:24:44Z); PMS özeti oda 2 / dolu oda 1 / devam eden konaklama 1 / aktif atama 2 / açık folyo 0.

İzole kopyada **hiçbir kontrol atlanmadı**:

| Aşama | Süre | Sonuç |
|---|---|---|
| Hazırlık (iskele + 2026-09-12 şema dökümü) | 0,7 sn | 0 hata |
| **Geri yükleme** (veri yedeği) | **0,3 sn** | 0 hata |
| Auth kapsamı | 0,6 sn | 13 kimlik gerekiyor, **yedekten 0 geldi** (prova için üretildi) |
| FK bütünlüğü | 0,3 sn | 61 FK `validate constraint`, **ihlal 0** |
| Satır sayıları | 0,2 sn | 75 tablo, **fark 0** |
| Veri tutarlılığı | 0,6 sn | üç kontrol de 0 |
| Uygulama erişimi | 1,3 sn | 5/5 — kimlik çözüldü, modüller okundu, `anon` kapalı |

Uygulama erişiminde seçilen aktör (`tum_oteller=true`) `auth_yetki_var('pms_oda','goruntule')` için **false** aldığı için oda listesini 0 satır gördü; bu tutarlıdır (yetkisi yok), sessiz RLS hatası değildir.

**Girdi bütünlüğü (2026-09-13'te yeniden doğrulandı).** Prova, kilitli betikle (`scripts/pms-yedek-geri-yukleme-provasi.mjs`, kilit: 11 dosya AYNI) ve ağı kapalı, geçici belleğe kurulan tek kullanımlık bir konteynerde (`--network none`, `--tmpfs`) çalıştırıldı; üretime bağlanmadı. Girdi dosyalarının SHA-256'ları:

| Dosya | Bayt | SHA-256 |
|---|---|---|
| `2026-09-13-pre-faz2-veri-yedegi.sql` | 757.033 | `7D3AFF78B5F1807460157A2766AE59BF019981EE4E973D32D60555B3B77456DA` |
| `2026-09-13-pre-faz2-sayaclar.json` | 3.785 | `286D2B3447DC92AFE4FF1FF32695DA9F0F6C9F5AC396DCEF227C8370F7432125` |
| `2026-09-12-pre-faz2-sema-dokumu.sql` | 340.833 | `5CDEF40EE6BCE7AD7F25BEE589974CCDCFB5D932D9277300C5EABC6A2F49671D` |

Veri yedeğinin özeti, yedek alınırken `yedek-ve-sayac-al.ps1`'in yazdırdığı değerle aynıdır; şema dökümünün özeti 2026-09-12'de kaydedilenle aynıdır. Yani prova, üretimden alınan dosyaların **değişmemiş** hâliyle koştu.

**Auth kimliklerinin kaynağı — ve bunun sınırı.** Erişim kontrolündeki 13 kimlik **yedekten gelmedi**; `auth.users` boş geldiği için provanın kendisi, geri yüklenen `kullanicilar.auth_user_id` değerlerinden **sentetik** olarak üretti (yalnız izole kopyada; parola, e-posta ya da oturum verisi yoktur). Bunun anlamı açıktır:

- **Kanıtlanan:** veri geri yüklendikten sonra RLS, yetki motoru ve `anon` kapalılığı doğru çalışıyor — yani *veri katmanı* sağlam geri geliyor.
- **Kanıtlanmayan:** gerçek kullanıcıların **giriş yapabilmesi**. Sentetik kimlikle geçen erişim testi giriş kurtarma kanıtı **değildir** ve bu yedekle böyle bir kanıt üretilemez; `auth` şeması kapsam dışıdır. Giriş kurtarma, ancak `auth` şemasını da kapsayan ayrı bir yedekle (hassas veri içerdiği için ayrı karar) ya da kimliklerin elle yeniden kurulmasıyla ele alınabilir. Bugün **açık risktir**, §7'de kayıtlıdır.

**Olası veri kaybı aralığı (bu yedek için):** yedeğin okuduğu an **2026-09-13T07:40:53Z**'den sonra üretime yazılan her şey. Yayın penceresi bu yedekten belirgin biçimde sonra açılırsa, pencere başında yedek **yenilenir**; aksi hâlde aradaki tüm yazmalar kayıp aralığındadır.

**Hazırlık betikleri sabitlendi (2026-09-13).** Yayın penceresinde çalışacak ve kanıt üreten 11 dosyanın LF içeriği üzerinden SHA-256'ları `docs/kurulum/2026-09-13-hazirlik-kilidi.json` dosyasına yazıldı; `node scripts/hazirlik-kilidi.mjs` sapmayı gösterir. Kilitteki Adım 1 ve Adım 2 özetleri §0'daki yayın özetleriyle aynıdır. Bir dosya bilinçli değişirse kilit yenilenir ve **ilgili provalar tekrarlanır**.

**Geri yükleme ölçümü (2026-09-13, izole konteyner):** şema dökümü 0,5 sn, referans veri 0,2 sn, Supabase iskelesi 0,2 sn → **toplam ~0,9 sn**, 75 tablo. Bu, *şema* geri yüklemesidir. **Veri yedeğinin** geri yükleme süresi ancak yedek alındıktan sonra ölçülebilir; üretimdeki veri hacmi bugün çok küçük olduğu için saniyeler mertebesinde beklenir ve E-5 provasında gerçek değer ölçülüp rapora yazılır.

**Olası veri kaybı (RPO):** otomatik yedek olmadığı için kayıp aralığı = **yedeğin okuduğu an ile olay anı arasında yapılan tüm yazmalar**. Sabit bir üst sınır yoktur ve yayın penceresinin zaman çizelgesinden türetilemez: pencere hedefleri kesinti süresini yönetir, yedeğin yaşını değil. Aralığı küçültmenin tek yolu yedeği olaya yakın bir zamanda almaktır; alınan yedeğin okuduğu an, sayaç dosyasındaki `alinma_zamani` ile kayda geçer.

**Plana etkisi:** yayın öncesi yedek, **kullanıcının elle aldığı dökümdür** (şema + referans veri için `dokum-al.ps1`, veri için `pg_dump --data-only`). Elde böyle bir yedek yoksa "yedekten dönüş" seçeneği **yoktur** (§7).

### 1.9 Diğer bulgular

1. Modülü kapatmak engeli kaldırmaz (§24.1; kanıt M1/M2–M4/M5/M7 ve 1.5/S1–S3).
2. `service_role` yedi tetikleyici fonksiyonunda EXECUTE taşıyor (varsayılan ACL mirası); `returns trigger` oldukları için RPC yüzeyi 0. Kayda geçer.
3. Yayından sonra 09-07 eşitlik dosyası şu beklenen SAPMA'ları verecek: 20 `pms_housekeeping_*` fonksiyon; `phase0_private` 11; `audit=21 otel_degismez=35`; `phase0_otel_kisit` 37; PMS tablo 10; 236/76; 41.
4. Yetki ekranında modül başlığına tıklamak modülü açar/kapatır.
5. Yeni arayüz modül kapalıyken bozulmaz.
6. SQL Editor migration'larda "destructive operations" onayı isteyecek; gerçek DDL olduğu için beklenen davranıştır.

---

## 2. Kabul koşulları ve kanıtları

Yayın penceresinin **başlayabilmesi** için aşağıdakilerin tamamı sağlanmış olmalıdır.

| # | Koşul | Durum / kanıt |
|---|---|---|
| K-1 | Adım 2, yayın kanalında (SQL Editor eşdeğeri tek sorgu metni) uygulanabiliyor | ✅ `e10a806`; prova 1.3 |
| K-2 | Tüm Faz 2 test paketleri, **yayın baytlarıyla** yeşil | ✅ 1.3 (dokuz paket, 0 FAIL) |
| K-3 | Prova edilen dosyalar ile yayın dosyaları aynı | ✅ 0.2 (LF kopya hash'leri = commit hash'leri) |
| K-4 | Canlı veritabanı salt okuma incelemesi sapmasız | ✅ 1.2 (altı dosya, 0 SAPMA) |
| K-5 | **Gerçek rol seviyeleriyle negatif yetki testleri** | ✅ 1.6 (32 OK / 0 FAIL) |
| K-6 | **Yerel arayüz kurtarma provası** | ✅ 1.7 (görev açma dahil uçtan uca) |
| K-7 | **Yayın başlangıcı preflight'ı**: pencere başında, Adım 1'den hemen önce preflight yeniden çalıştırılır ve `SAPMA` = 0 ile `E1 = 0` görülür | ⏳ Pencerede yapılacak (6.1.2). Sonucu görülmeden Adım 1 çalıştırılmaz. |
| K-8 | Güncel dökümle prova | ✅ 1.3 (2026-09-12 dökümü; döküm doğrulaması sapmasız, dokuz paket yeşil, preflight öncesi/sonrası beklenen) |
| K-9 | Yetki matrisi ve iki ayrı test kullanıcısı onayı | ⏳ E-2 |
| K-10 | Operasyonun pencere ve zaman çizelgesi onayı | ⏳ E-3 |
| K-11 | "Adım 1 commit'inden sonra eski akışa dönüş yok" riskinin kabulü | ⏳ E-4 |
| K-12 | **Yedek, geri yükleme provasıyla kanıtlanır**: veri yedeği izole kopyaya geri yüklenir; satır sayıları üretim sayaçlarıyla (aynı kapsam ve görünürlük) birebir tutar; **her yabancı anahtar yeniden doğrulanır (ihlal 0)**; üç tutarlılık kontrolü 0 verir; temel uygulama erişimi çalışır; **yedeğin kurtarma kapsamı (auth dahil değil) sayıyla raporlanır**; süreler ayrı ayrı raporlanır. Dosyanın var olması yeterli değildir. | ✅ 1.8 (2026-09-13, üretim yedeğiyle; **giriş kurtarma hariç**) |

---

## 2b. Kalıcı testler (repoda)

Kabul koşullarını üreten sondalar tek kullanımlık betik olmaktan çıkarıldı; repoda çalıştırılabilir testlerdir. Dökümler repo dışında olduğu için yol dışarıdan verilir.

| Betik | Ne kanıtlar | Çalıştırma |
|---|---|---|
| `scripts/pms-faz2-yetki-negatif.mjs` | Gerçek rol adlarıyla yetki matrisinin sınırları (K-5) | `PMS_DOKUM=… PMS_REFERANS=… node scripts/pms-faz2-yetki-negatif.mjs` → 32 OK / 0 FAIL |
| `scripts/pms-faz2-dogrudan-yazma-sondasi.mjs` | Migration sonrası doğrudan temizlik yazmanın hangi yolla mümkün olduğu (1.5, §5.5) | Aynı değişkenlerle → 6 OK / 0 FAIL |
| `scripts/pms-yedek-geri-yukleme-provasi.mjs` | Yedeğin gerçekten geri yüklenebildiği, verinin ve FK bütünlüğünün tuttuğu (E-5) | `node scripts/pms-yedek-geri-yukleme-provasi.mjs <yedek> <sayaclar.json> --sema <sema.sql>` |
| `scripts/hazirlik-kilidi.mjs` | Yayın penceresinde çalışacak 11 dosyanın kanıt üretildiği andan beri değişmediği | `node scripts/hazirlik-kilidi.mjs` |
| `docs/kurulum/2026-09-13-yedek-dogrulama-sayaclari.sql` | Üretim tarafı beklenen sayaçlar (salt okuma) | SQL Editor |

---

## 3. Kalan engeller

| # | Tür | Konu | Kapanma ölçütü |
|---|---|---|---|
| E-1 | ~~Önkoşul~~ | Bayt düzeyinde güncel dökümle prova | ✅ **Kapandı** (2026-09-12): döküm alındı, doğrulandı ve tüm zincir onunla tekrarlandı — 1.3 |
| E-5 | ~~Önkoşul~~ | **Yedek + geri yükleme provası** — otomatik yedek yok (1.8) | ✅ **Kapandı — VERİ kurtarma için** (2026-09-13): yedek `yedek-ve-sayac-al.ps1` ile **aynı snapshot** yolundan alındı; kilitli betikle, ağı kapalı izole kopyada, **hiçbir kontrol atlanmadan** doğrulandı — yükleme hatası 0, 75 tabloda satır farkı 0, 61 FK doğrulandı (ihlal 0), üç tutarlılık kontrolü 0, erişim 5/5; girdi dosyalarının SHA-256'ları doğrulandı. **Giriş (auth) kurtarma kapsam dışıdır ve kanıtlanmamıştır**: erişim testindeki 13 kimlik yedekten değil, provanın kendisinden gelir (1.8). |
| E-2 | Karar | Yetki matrisi ve iki ayrı test kullanıcısı | §4 matrisi onaylanır; şef ve çalışan rolünde **iki farklı aktif kullanıcı** adıyla belirlenir. |
| E-3 | Onay | Operasyon onayı | §5.1 penceresi ve §5.2 zaman çizelgesi, operasyondan sorumlu kişi tarafından adı ve saatiyle onaylanır. |
| E-4 | Risk kabulü | Adım 1 commit'inden sonra eski temizlik akışına dönüş yok | Kullanıcı kabul eder (§5, §7). |

---

## 4. Yetki matrisi (kesinleştirildi — E-2 onayına tabi)

Mimari §16: çalışan `kayit`, şef `tam`, resepsiyon `goruntule`. Üretimde bu roller tanımlı ve boş; PMS erişimi bugün yalnız iki yönetici rolünde.

| Rol | `pms_housekeeping` | Gerekçe |
|---|---|---|
| Kat Hizmetleri Şefi | `tam` | Görev açar, atar, iptal eder, denetler |
| Kat Hizmetleri Vardiya Sorumlusu | `tam` | Vardiyada şefin yerine geçer |
| Kat Hizmetleri Personeli | `kayit` | Sahiplenir, başlatır, tamamlar; denetleyemez |
| Genel Müdür (GM) | `goruntule` | Durum takibi |
| Ön Büro Şefi / Vardiya Sorumlusu / Personeli | `goruntule` | Oda hazır mı görür; temizlik komutu vermez |
| IT / Sistem Yöneticisi · Sistem Yöneticisi | `tam` | Yayın ve duman testi |
| Diğer tüm roller | satır açılmaz (`yok`) | Fail-closed varsayılan |

Her seviyenin sınırları 1.6'da davranışsal olarak ölçüldü. Ek notlar:
- Rolde kullanıcı yoksa satır etkisizdir; matris yine de kurulur.
- Kat hizmetleri çalışanlarının `otel_id` ataması veya `tum_oteller` yetkisi olmalıdır (`hk_calisan_uygun`); pencerede doğrulanır.
- Denetim bağımsızlığı **kullanıcı düzeyindedir**: duman testi için `tam` yetkili iki ayrı kullanıcı gerekir.
- Check-in/check-out `pms_rezervasyon kayit` ister; ön büro rollerine bu yetkinin verilmesi Faz 1 kapsamıdır, bu yayının parçası değildir.

---

## 5. Pencere, zaman çizelgesi ve başarısızlık davranışı

### 5.1 Pencere

| Alan | Değer |
|---|---|
| Önerilen | **13 Eylül 2026, oda 102'nin çıkışı tamamlandıktan sonra, 12:00–14:00** |
| Alternatif | 14 Eylül sabahı |
| Operasyon onayı | **Gerekli** (E-3): ad, rol, saat runbook kaydına yazılır |
| Hazır bulunacaklar | Yayını yürüten kişi, `tam` yetkili iki test kullanıcısı, `yetki_yonetimi tam` yetkili kullanıcı |

**Etki beyanı (varsayımsız):** Pencere boyunca hiçbir oda sistemde temiz işaretlenemez. Bu, o an dolu oda bulunup bulunmamasından bağımsızdır: pencere içinde çıkış yapılan, arızadan dönen veya herhangi bir sebeple kirlenen her oda, modül açılana kadar satılamaz. Operasyon bu riski kabul etmeden pencere başlamaz.

### 5.2 Zaman çizelgesi ve müdahale eşiği

**T0 = Adım 1 migration'ının commit'lendiği an.** Kesinti T0'da başlar, modül açıldığında (6.1.8) biter.

| An | Beklenen durum | Sapma hâlinde |
|---|---|---|
| T+10 | Adım 2 uygulandı ve doğrulandı | 10 dakika ek süre; T+20'de hâlâ bitmediyse T+45 eşiğine kadar ileri yönlü düzeltme sürer |
| T+25 | Arayüz canlıda doğrulandı (hash + HTTP 200) | Pages 15 dakikada yayına çıkmadıysa doğrudan C1 (§5.4) |
| T+35 | Modül açık, şef ekranı çalışıyor | Yetki/kullanıcı kontrolü; 10 dakika |
| **T+45** | **Müdahale eşiği** | Kesinti sürüyorsa §5.4 müdahale merdiveni **başlatılır**. Eşik bir "azami süre" değil, karar anıdır: yayın durdurulmaz, kat hizmetleri yeteneği başka yoldan ayağa kaldırılır. |

Hedef, kesintiyi T+35'te bitirmektir. T+45 aşılırsa iş, yayının tamamlanmasını beklemek yerine C1'e geçer. Her ara kontrolün gerçek saati runbook kaydına yazılır.

### 5.3 Adım adım başarısızlık davranışı

| Adım | Başarısızlık | Yapılacak |
|---|---|---|
| 6.1.3 Adım 1 | `ERROR` | Transaction kendiliğinden geri döner. Preflight ile **A1–A9 = 0** doğrulanır. Yayın iptal, pencere kapanır, sebep raporlanır. Kesinti başlamamıştır. |
| 6.1.4 Adım 2 | `ERROR` | Adım 1 yerinde kalır, kesinti işler. İleri yönlü düzeltme denenir; arayüz yayınlanmaz, modül açılmaz. T+45'te §5.4. |
| 6.1.5 Doğrulama | Beklenen 19 SAPMA dışında fark | Durulur ve raporlanır; modül kapalı kalır. T+45'te §5.4. |
| 6.1.6 Yetkiler | Yanlış seviye | Hücre düzeltilir; modül yanlışlıkla açıldıysa aynı dakika kapatılır ve kayda geçer. |
| 6.1.7 Arayüz | Pages gecikti, hash uyuşmadı, beyaz sayfa | `git revert` çözüm değildir (eski temizlik yolunu geri getirmez). C1'e geçilir. |
| 6.1.8 Modül | Yetkili şefe 42501 | Matris ve `hk_calisan_uygun` koşulları kontrol edilir; 10 dakikada çözülmezse C1. |

### 5.4 Müdahale merdiveni (olağan)

1. **C1 — arayüzü yerel kaynaktan sun.** Yayın commit'indeki arayüz dosyaları yetkili bir makinede yerel olarak sunulur; kat hizmetleri komutları normal yoldan, gerçek kullanıcı kimliğiyle işler. Modül açık olmalıdır. **Provası yapıldı (1.7).** Pages düzelince köprü kapatılır; kayda geçer.
2. **C2 — operasyonel duraklatma.** C1 uygulanamıyorsa etkilenen odalar satışa kapatılır; düzeltme bir sonraki pencereye bırakılır.

Bu merdivende veritabanına doğrudan temizlik yazımı **yoktur**.

### 5.5 Kontrollü acil müdahale (olağan merdivenin dışında, ayrı onay)

1.5/S4 ile ölçülen sahip rolü yolu, yalnız aşağıdaki koşulların tamamı sağlandığında kullanılır. Olağan kurtarma adımı değildir ve planın akışında yer almaz.

| Koşul | Ayrıntı |
|---|---|
| Tetikleyen durum | C1 uygulanamıyor **ve** satılması zorunlu bir oda kilitli kalmış |
| Onay | Kullanıcının o an verdiği açık onay; "CANLIYA UYGULA" kapsamına otomatik girmez |
| Kimlik | Kimlik ayarı, işlemi fiilen yapan kişinin `auth_user_id` değeri olur. Başkasının kimliği kullanılmaz: denetim kaydı o kişinin üstüne yazılır |
| Kapsam | Tek seferde tek oda; gösterge (`temizlik_gorevi_id`) NULL bırakılır |
| Yasak | Modül, bekçi ve tetikleyiciler kapatılmaz; ACL değiştirilmez; uygulama rollerine yazma hakkı verilmez |
| Kayıt | Her satır, gerekçesi, saati ve uygulayanla runbook'a yazılır; yayın sonrası incelemede ele alınır |

---

## 6. Yayın adımları

Sıra mimari §16'dır: **migration → roller → uyumlu arayüz → modülü açma.**

### 6.0 Pencere öncesi (üretime yazma yok)

| Adım | Durum |
|---|---|
| Adım 2 düzeltmesi ve paketler | ✅ K-1, K-2 |
| Yayın commit'leri ve hash'ler | ✅ K-3 |
| Canlı preflight | ✅ K-4 |
| Negatif yetki testleri | ✅ K-5 |
| Yerel arayüz kurtarma provası | ✅ K-6 |
| Güncel dökümle prova | ⏳ E-1 |
| Yetki matrisi ve kullanıcılar | ⏳ E-2 |
| Pencere ve zaman çizelgesi onayı | ⏳ E-3 |
| Yedek (E-5) | **Otomatik yedek yok** (1.8). Elde 2026-09-13T07:40:53Z yedeği var ve provası geçti. Pencere bu tarihten sonraya kalırsa yedek **pencere başında yenilenir** (`yedek-ve-sayac-al.ps1`) ve yeni dosyanın yolu, SHA-256'sı, `alinma_zamani`'si kayda geçer |

### 6.1 Pencere (`CANLIYA UYGULA` şart)

**6.1.1 Kod dondurma.** `git status --short` boş; `git rev-parse HEAD`; LF baytlarının SHA-256'sı §0.1 ile karşılaştırılır; SQL Editor'e yapıştırılan metin de aynı hash ile doğrulanır.

**6.1.2 Yayın başlangıcı preflight'ı (K-7).** Preflight ve §1.2'deki taban dosyaları yeniden çalıştırılır. **Geçme ölçütü: `SAPMA` = 0 ve E1 = 0.** `erp_islem_audit` satır sayısı kaydedilir. Bu sonuç görülmeden Adım 1 çalıştırılmaz.

**6.1.3 Adım 1 migration.** SQL Editor, dosyanın tamamı, tek çalıştırma. **T0 burada başlar.** Ara kontrol:

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

**6.1.4 Adım 2 migration.** Ara kontrol:

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

**6.1.5 Uygulama sonrası doğrulama.** Preflight ve taban dosyaları; beklenen SAPMA listesi 1.3 ve 1.8/3'tedir. C1 ölçütü "tabandan farklı"dır; yeni md5 değerine bağlanmaz.

**6.1.6 Yetkiler.** §4 matrisi `yetki-yonetimi.html` ekranından uygulanır; modül başlığına tıklanmaz. Doğrulama:

```sql
select r.ad, ym.yetki from public.yetki_matrisi ym
  join public.roller r on r.id = ym.rol_id join public.moduller m on m.id = ym.modul_id
 where m.kod = 'pms_housekeeping' order by r.ad;
select aktif from public.moduller where kod = 'pms_housekeeping';   -- hâlâ false
```

**6.1.7 Arayüz yayını.** Ayrı ön yüz onayıyla `git push origin <yayın SHA>:main`. Başarı: değişen altı dosyanın canlı SHA-256'sı yayın commit'iyle aynı; iki yeni dosya HTTP 200; konsolda hata yok; 10 dakikalık önbellek beklendi.

**6.1.8 Modülü açma.** Tek başına:

```sql
update public.moduller set aktif = true where kod = 'pms_housekeeping';
```

Başarı: `aktif = true`; şef listeleri görüyor; oda planında kat hizmetleri satırı var. **Kesinti burada biter.**

**6.1.9 Birikim.** Görevsiz kirli odalar için şef `ekstra_temizlik` açar.

### 6.2 Veri değiştiren duman testleri

| # | Test | Kanıt | Kalıcı iz |
|---|---|---|---|
| D1 | Şef görev açar → çalışan sahiplenir, başlatır, tamamlar → **ikinci** `tam` kullanıcı denetler | Görev `kontrol_edildi`, `surum` +1'er; oda kirli → temizleniyor → temiz → kontrol_edildi; denetim satırlarında `islem_detayi` durum geçişini taşıyor | 1 terminal görev + denetim satırları |
| D2 | Çıkış üreticisi: tercihen oda 102'nin gerçek çıkışı; olmazsa `101` için test rezervasyonu → check-in → check-out | Oda `bos+kirli`; `cikis_temizligi` görevi `bekliyor`, `olusturma_kaynagi='checkout'` | Gerçek çıkışta yalnız görev; alternatifte rezervasyon + folyo (bakiye 0, kapatılır) |
| D3 | Faz 2 dışı denetim regresyonu: günün gerçek bir işlemi | Yeni `erp_islem_audit` satırı, `islem_detayi` NULL | Gerçek iş kaydı |
| D4 | Yetki sınırı (yazma yok): `goruntule` kullanıcı komut düğmesi görmez | Ekran gözlemi | Yok |

Eski yolun negatif testi üretimde yapılmaz; 1.5 ve 1.6 bunu izole kopyada kanıtlıyor. Toplam kanıt: `erp_islem_audit` sayısı 6.1.2'deki değere göre artmalı.

### 6.3 Kayıt

Runbook §4 geçmişi ve §1'in 12 alanı; kesinti süresi ve ara kontrol saatleri; D1/D2 görev kimlikleri; varsa §5.5 kayıtları; yeni taban POST-FAZ2 dökümü ve eşitlik dosyası; bilgi haritası.

---

## 7. Geri dönüş sınırları (mimari §24)

| Nokta | Geri dönüş | Eski temizlik akışı geri gelir mi? |
|---|---|---|
| 6.1.3 / 6.1.4 transaction içinde hata | Otomatik geri alma | Evet (değişiklik olmaz) |
| 6.1.3 commit sonrası | İleri yönlü düzeltme | **Hayır** |
| 6.1.6 | Rol hücreleri `yok` | — |
| 6.1.7 | `git revert` + push | **Hayır** |
| 6.1.8 sonrası | §24.1 olağan kapatma: yalnız `moduller.aktif=false` içeren transaction; uçuştaki komutları bekler. Komutlar kapanır, check-out sürer ama görev üretmez, geçmiş korunur. | **Hayır.** Kirli odalar hazır hâle getirilemez. |
| Üretici hatalıysa | §24.2: modülü kapat, uçuşu boşalt, **yalnız** `pms_housekeeping_cikis_uret` ve `pms_housekeeping_serbest_uret` tetikleyicilerini devre dışı bırak; bütünlük, denetim ve yaşam döngüsü tetikleyicilerine dokunma; önce staging'de doğrula; ileri yönlü migration ile onar; üreticileri modülden önce aç. | Hayır |
| Yeniden açma | §24.3 değişmez raporu temiz olmalı (aşağıda) | — |
| Her aşama | Yedekten dönüş — 2026-09-13T07:40:53Z yedeği var ve provası geçti (1.8) | Evet, ama yedekten sonraki tüm rezervasyon, folyo ve ödeme yazmaları kaybolur; özellik geri alma yöntemi değildir. Kapsam `public` + `phase0_private` **verisidir**: aynı projede veri kaybını geri alır. `auth` kapsam dışı olduğu için **proje tümden kaybında giriş sağlamaz** ve bu senaryo **prova edilmemiştir** — açık risk (1.8) |

**Yasak (§24.2):** `DISABLE TRIGGER ALL`, `ensure_rls`'i kapatmak, FK düşürmek, denetimi düşürmek, uygulama rollerine doğrudan görev/temizlik DML hakkı vermek.

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
