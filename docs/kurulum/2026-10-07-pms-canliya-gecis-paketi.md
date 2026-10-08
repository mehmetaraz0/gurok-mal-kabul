# PMS Ön Büro — canlıya geçiş paketi (hazırlık)

> **BU BELGE YAYIN İZNİ DEĞİLDİR.** Hiçbir SQL üretime koşulmadı; push, merge,
> deploy yapılmadı; canlı yetki değiştirilmedi. Amaç, `CANLIYA UYGULA` onayı
> geldiğinde hangi dosyanın hangi sırayla uygulanacağını tereddütsüz
> sabitlemek. Üretim yazma dondurması yürürlüktedir
> (`URETIM-YAYIN-RUNBOOK.md` §0).

- **Tarih:** 2026-10-07
- **Aday dal:** `pms/akis-tamamlama`
- **Canlı referans:** `origin/main` = `a77e6e1` (2026-09-26)
- **Sapma:** aday 79 commit **ileri**, 0 commit **geri** → hızlı ileri alınabilir
  (ölçüldü; rebase gerekmiyor)

---

## 1. Canlı sürüm ile adayın farkı

### 1.1 Canlıda ne var, ne yok

Üretim kütüğünden (`URETIM-YAYIN-RUNBOOK.md`) ölçüldü:

| Paket | Üretimde | Kayıt |
|---|---|---|
| PMS Faz 1 (oda tipleri, odalar, misafir, rezervasyon, check-in/out, folyo) | **VAR** — 2026-09-07 | §5 |
| PMS fonksiyon ACL temizliği | **VAR** — 2026-09-08 | §6 |
| PMS Faz 2 (kat hizmetleri) | **VAR** — 2026-09-13, kesinti 16:08–16:53 | §8 |
| Kat hizmetleri otel seçici (arayüz) | **VAR** — 2026-09-13 | §9 |
| Stok (liste özeti, güncelleme tarihi) | **VAR** — 2026-09-15 / 09-18 | §12, §13 |
| **Ön Büro modül ve rol yetkileri** | **YOK** | bu paket |
| **Mali işlem yetki ayrımı** | **YOK** | bu paket |
| **MY-4 rol entegrasyon kilidi** | **YOK** | bu paket |

Yani **şema canlıda, yetkiler değil.** 2026-09-07 manifestindeki
"Üretime uygulandı mı: HAYIR" satırı o günün durumudur ve tarihsel kayıttır;
Faz 1 aynı gün uygulandı.

### 1.2 Aday dalın 79 commit'i — konu ayrımı

| Konu | Commit | Bu yayına dahil |
|---|---|---|
| **PMS** | 21 | **EVET** |
| İP-7 otonom koşucu / izole inceleme VM'i | 55 | hayır |
| Kurulum rehberi ön-kontrol süiti | 1 | hayır |
| R11+B4 entegrasyon adayı (`ip1/*`) | 2 | hayır |

PMS commit'leri (eski → yeni):
`ee4f600` `35263dd` `20638b6` `21a4277` `536e5dd` `59245d6` `552547f`
`6c8014a` `440e9e1` `a2e66a4` `792d31c` `5ad176f` `61599dd` `892bc88`
`b71eaae` `a0f1c10` `36c7def` `4ca95db` `05d9d77` `2705363` `e2be660`

### 1.3 Canlıya gerçekten ne gidiyor — ölçüldü

Aday, `origin/main`'e göre **149 dosya** değiştiriyor. Bunların **25'i** PMS
commit'lerinden gelir, **124'ü** gelmez. Kritik ölçüm:

> **PMS dışı 124 dosyanın içinde kökte sunulan tek bir `.html`, `.js`, `.css`,
> `.json` veya `.webmanifest` dosyası YOKTUR.** Hepsi `docs/inceleme/` (116),
> `scripts/` (7 adet İP-7/kurulum betiği), `docs/KURULUM-REHBERI.md`,
> `CLAUDE.md` ve `AGENTS.md`'dir.

Sonuç: dalın tamamı birleştirilse bile **canlı sitede değişen dosya sayısı
2'dir**. İP-7 dosyaları servis edilmez ve üretim veritabanına uygulanmaz.
Bu yüzden iki seçenek de teknik olarak güvenlidir:

**Dosya listesi "25" sayısına bağlanmaz.** Bu paket dört dosya daha ekledi
(§2.3 ve §4); B seçeneği uygulanacaksa taşınacak kesin liste
`git diff --name-only origin/main..HEAD` çıktısından, PMS commit'leri süzülerek
**yayın anında** yeniden üretilir.

| Seçenek | İçerik | Not |
|---|---|---|
| **A** — dalın tamamını birleştir | 79 commit, 149 dosya, canlıda 2 dosya | Tek push; kayıt karışık görünür |
| **B** — yalnız PMS dosyalarını taşı | PMS commit'lerinin dosyaları + bu paketin dört yeni dosyası | Yayın kaydı temiz; ek dal gerekir |

**Bu bir karar noktasıdır (K-Y1) ve kullanıcıya bırakılmıştır.** Hiçbiri
uygulanmadı.

> **İnceleme önerisi (Ö — karar değildir):** 2026-10-07 bağımsız incelemesi
> **B**'yi öneriyor; gerekçe, dalın tamamında yalnız iki kök arayüz dosyasının
> değişmesinin ilgisiz 55 İP-7 commit'ini yayına katmayı gerektirmemesi.
> **Kullanıcı kararı henüz verilmedi**; bu satır öneriyi kaydeder, seçimi değil.

PMS dosya kümesindeki tek istisna:
`docs/inceleme/vm-betikleri/vm-32-pms-inceleme.sh` — PMS commit'lerinden
geliyor ama İP-7 inceleme VM'ine ait, yayına dahil değil, uygulanmaz.

---

## 2. Uygulanacak dosyalar ve yayın baytları

**Yayın baytı = commit'lenmiş bayt (LF).** Depo `core.autocrlf=true` ile
kullanıldığından çalışma ağacındaki kopyalar CRLF'tir ve başka özet verir.
Doğrulama (iki yol da aynı sonucu verir, ölçüldü):

```bash
git show HEAD:docs/kurulum/<dosya> | sha256sum
tr -d '\r' < docs/kurulum/<dosya> | sha256sum
```

> **Dikkat — `sql-uygula.ps1` BAŞKA bir özet yazar.** Betik `Get-FileHash` ile
> **çalışma kopyasını** (CRLF) özetler, yayın baytını (LF) değil. İkisi
> farklıdır ve bu, projenin daha önce tökezlediği tuzaktır. Preflight için
> ekranda görmeniz gereken değer:
>
> | Ne | Değer |
> |---|---|
> | Yayın baytı (commit'lenmiş, LF) | `4f6964aa5216bb72f44233bdc796e9b7f78e1bfcb473be161b23092c277de304` |
> | `sql-uygula.ps1`'in yazacağı (çalışma kopyası, CRLF) | `8FBE6BC5375417C09CEA8BFDDE41B6C93497698043DF9AECFA004A53DEF8C58D` |
>
> İkisi de ölçüldü; aynı dosyanın iki gösterimidir. Betik CRLF değerini
> yazarsa bu **doğru** dosyadır.

### 2.1 Veritabanına uygulanacak (sırayla)

| # | Dosya | SHA-256 (LF) |
|---|---|---|
| 1 | `2026-10-06-pms-folio-mali-yetki-ayrimi.sql` | `49141ac405dc4bc1f4123c8ba3556a382aeba2b571cbe2c2ecae6a139b0efe2a` |
| 2 | `2026-10-06-pms-rol-entegrasyon-kilit.sql` | `59e9d14af996b5f027f261f66aeb97bf00533dfcf3a94e0ccdef4a34ec98fa1e` |
| 3 | `2026-10-05-pms-onburo-modul-tohumlama.sql` | `9fa9741bbbbfbd4c2ac75b1435e8542f62de5854e16615a27e808d11033c4642` |

### 2.2 Canlıya gidecek arayüz dosyaları

| Dosya | SHA-256 (LF) | Ne değişti |
|---|---|---|
| `pms-folio.html` | `bae4da41a3c5394e7b52152193c919ad10dff1c50175e8520656fe90ea7031be` | Mali ayrımı ekrana yansıtma (`maliArayuzuUyarla`), yetkiye göre kurulan tip listesi, rozet ve yardım metinleri |
| `pms-oda-plani.html` | `89942b6cc525c90fb304297a78c523c7a6b9d106a209f70880f2cdfb551e000a` | Check-in listesi sunucunun kuralını aynalıyor (atanmış rezervasyon da listelenir); modal yardım metni düzeltildi |

İkisi de **salt istemci** değişikliğidir; yeni bir sunucu sözleşmesine
bağlı değildir. Ters sırada yayınlanmaları veri bozmaz, yalnız geçici
uyumsuz görünüm üretir.

### 2.3 Uygulanmaz — doğrulama ve geri alma içindir

| Dosya | SHA-256 (LF) | Rol |
|---|---|---|
| `2026-10-07-pms-onburo-yayin-oncesi-preflight.sql` | `4f6964aa5216bb72f44233bdc796e9b7f78e1bfcb473be161b23092c277de304` | **Salt-okuma** yayın öncesi ölçüm (13 blok). **psql meta komutu içermez** → `psql -f` ve Supabase SQL Editor ile **aynen** çalışır; ayrı sürüm gerekmez (ölçüldü) |
| `2026-10-06-pms-folio-mali-yetki-ayrimi-geri-al.sql` | `fbdeb17f53d5fb3853d518c37bf4fd9432841b7ac3364d618f3f0efcbff0a07a` | Adım 1 geri alma |
| `2026-10-06-pms-rol-entegrasyon-kilit-geri-al.sql` | `d504593e7a6d80ed55c8b983b4a5def9d2816142c36ef60a04fcdc2c466a95ee` | Adım 2 geri alma — **bu pakette YENİ yazıldı** |
| `2026-10-05-pms-onburo-modul-tohumlama-geri-al.sql` | `dd22dd3d10776976d5be37720b28dfa7c6ea0f7e4ebf099ef9e6b3f5466cd63b` | Adım 3 geri alma |

> **Kapanan boşluk:** `2026-10-06-pms-rol-entegrasyon-kilit.sql`'in geri alma
> dosyası **yoktu**. Yazıldı. Üç fonksiyon gövdesi elle kopyalanmadı; Faz 1
> dosyalarından satır aralığıyla çıkarıldı (adım2 357–414, adım3 494–597 ve
> 600–684) ve çıkarma sırasında "security definer içermiyor" diye ölçüldü.

---

## 3. KESİN SIRA

Genel kural: **bir adımın post-check'i geçmeden sonraki adım başlamaz.** Tüm
adımlar aynı pencerede, aynı kişi tarafından, runbook §1'deki 12 zorunlu alan
doldurularak yapılır. **Birincil kanal `psql --single-transaction`**; SQL
Editor yedek kanaldır (09-13 dersi: tarayıcı otomasyonu pencere ortasında
çöktü).

### Adım 0 — Yayın öncesi (tek sefer)

1. Kullanıcının açık `CANLIYA UYGULA` onayı alınır ve kaydedilir.
2. Kod donduruldu: HEAD hash'i kaydedilir, çalışma ağacı **temiz** olmalı,
   §2'deki altı SHA-256 doğrulanır.
3. `node scripts/migration-guvenlik-kontrol.mjs` + `node --test
   scripts/migration-guvenlik-kontrol.test.mjs` (runbook §2.2b, zorunlu).
4. **Yedek alınır ve DOĞRULANIR.** Yedek doğrulanmadan hiçbir migration başlamaz.
5. `2026-10-07-pms-onburo-yayin-oncesi-preflight.sql` çalıştırılır (salt-okuma),
   çıktının tamamı kayda yapıştırılır.
6. Parola `-YalnizBaglanti` ile bir kez sınanır (09-13 dersi: iki başarısız
   deneme kesintiye ~6 dakika ekledi).

**STOP:** preflight'ta tek bir `SAPMA`; yedeğin doğrulanamaması; §6'daki üç
gövde özetinin beklenen değerlerle tutmaması.

### Adım 1 — Mali işlem yetki ayrımı

| | |
|---|---|
| Dosya | `2026-10-06-pms-folio-mali-yetki-ayrimi.sql` (`49141ac4…0efe2a`) |
| Niçin önce | Adım 3, folyoya **yazma** yetkisi açıyor; dosya bu kuralı ön koşul olarak **zorluyor** ve kural yoksa `MALI_AYRIM_KURALI_YOK` ile durup hiçbir satır yazmıyor (ölçüldü) |
| Post-check | Kendi doğrulama bloğu hatasız bitti; `pms_folio_hassas_kapi` **iki** mali tabloda da var; `pms_folio_hassas_mi` tanımlı |
| Duman testi | Normal (pozitif, gerekçesiz) tahsilat **kabul**; negatif tutar `tam` yetkisiz **ret**; `tam` ile gerekçesiz **ret**; `tam` + gerekçe **kabul** |
| STOP | Doğrulama bloğu hata verirse; iki tetikleyiciden biri yoksa; normal tahsilat reddedilirse |
| Geri alma | `…-geri-al.sql` — **Adım 3 ayaktayken HARD GATE ile engellenir** (ölçüldü) |

> **Operasyonel etki — önceden bilinmeli.** Bu adım uygulandığı anda, folyoda
> `kayit` seviyesindeki **herkes** için iade / indirim / düzeltme reddedilmeye
> başlar. Kimin etkileneceğini preflight §9 listeler.

### Adım 2 — MY-4 rol entegrasyon kilidi

| | |
|---|---|
| Dosya | `2026-10-06-pms-rol-entegrasyon-kilit.sql` (`59e9d14a…98fa1e`) |
| Niçin burada | Adım 3 rolleri yetkilendirdiği **anda** check-in/check-out çalışmalı. Kilit olmadan `pms_oda`/`pms_oda_tipi` için yalnız `goruntule` hakkı olan roller zinciri yürütemez: RLS'te `FOR UPDATE`, satırın **UPDATE** politikasını da ister |
| Post-check | Kendi doğrulama bloğu hatasız; `pms_rezervasyon_kontrol`, `pms_check_in`, `pms_check_out`, `pms_oda_tipi_kilitle` → **4 fonksiyon `prosecdef`**; `pms_oda_konaklama_isaretle` **yok** (MY4-T3) |
| STOP | Dört fonksiyondan biri definer değilse; preflight §6 gövde özetleri yayın öncesi beklenen değerlerden farklıysa (o durumda kilit, **başkasının değişikliğini sessizce geri alır**) |
| Geri alma | `…-kilit-geri-al.sql` — **bedeli:** kilit kalkınca Ön Büro akışı kapanır |

### Adım 3 — Arayüz yayını

| | |
|---|---|
| Dosya | `pms-folio.html`, `pms-oda-plani.html` |
| Kanal | `origin/main`'e push. Ölçülen gecikme: 09-13'te push 16:50:57 → canlı 16:51:33 (~36 sn) |
| Niçin tohumlamadan önce | Ön Büro menüsünü **açan** adım tohumlamadır. Roller erişimi kazandığında ekran zaten doğru olmalı |
| Post-check | İki dosyanın canlı SHA-256'sı §2.2 ile **birebir aynı**; HTTP 200; oturumsuz erişim giriş ekranına yönleniyor; 404 ve konsol hatası yok |
| STOP | Canlı özet commit'teki özetle tutmazsa |
| Geri alma | Önceki commit'i yeniden yayınlamak (veri etkisi yok) |

### Adım 4 — Ön Büro modül ve yetki tohumlaması

| | |
|---|---|
| Dosya | `2026-10-05-pms-onburo-modul-tohumlama.sql` (`9fa9741b…33c4642`) |
| **Elle açılacak satır** | `  set local app.pms_k1 = 'kayit';` — K1 = **A** kararı (2026-10-06). Sessiz varsayılan yoktur; satır açılmazsa dosya hata verir ve hiçbir şey yazmaz |
| Niçin en son | Bu adım menüyü ve RLS'i **açar**. Daha önce koşulursa kullanıcılar eksik sunucu kuralı veya eski ekranla karşılaşır |
| Post-check | **(a)** Son durumda **15 hedef çift doğru seviyede**. **(b)** Bu uygulamanın eklediği **damgalı** satır sayısı = preflight §3'teki **EKSİK** sayısı — 15 değil, *eksik kadar*. Dosya bunu kendisi de bildirir (`eklenen_yetki_satiri=N/15`). **(c)** Önceden var olan satırların seviyesi ve üstverisi (`guncelleyen`) **değişmemiş**. **(d)** Beş Ön Büro modülü var ve **aktif**. **(e)** `onburo_personel / pms_folio = kayit`. **(f)** Yeni `pms_misafir_kimlik` satırı **eklenmemiş** *ve* önceden var olanlar **silinmemiş** (iki ayrı ölçüt) |
| Duman testi | Menüyü gören rol kümesi **önce/sonra delta** olarak alınır: önce gören hiçbir rol **kapanmamış**, yeni gören roller **yalnız** üç Ön Büro rolü. Personel rezervasyon + check-in + check-out + normal tahsilat yapabiliyor; personelin iadesi reddediliyor |
| STOP | `PASIF MODUL`, `EKSIK REFERANS` veya `CELISEN MEVCUT YETKI` hatası (hiçbir şey yazılmaz — karar gerekir); son durumda 15 hedef çiftten biri doğru seviyede değilse; eklenen damgalı satır sayısı preflight'taki EKSİK sayısına eşit değilse; önceden var olan bir satırın seviyesi veya `guncelleyen`'i değiştiyse |
| Geri alma | `…-tohumlama-geri-al.sql` — **uygulama kimliği elle verilir** (`app.pms_uygulama_id`); kimlik, Adım 4 çıktısındaki damgadan alınır |

### Adım 5 — Yayın sonrası

1. Yayın sonrası parmak izi: preflight §7 yeniden koşulur ve **yeni taban**
   olarak kayda yazılır (aşağıdaki E-1'i kapatır).
2. Denetim izi sayacının arttığı doğrulanır (duman testinin bağımsız kanıtı).
3. Runbook'a yayın kaydı yazılır (12 zorunlu alan, duman testi kanıtı dahil).

---

## 4. Doğrulama — iki izole tabanda

`node scripts/pms-canliya-gecis-provasi.mjs` — **üretime bağlanmaz, üretim
verisi kopyalanmaz.**

| Taban | İçerik | Sonuç |
|---|---|---|
| **temiz** | `2026-09-07-post-pms-faz1-sema-dokumu.sql` + `02-referans-veri.sql` (yeni kurulum tabanı; Faz 2 nesneleri yok) | **86 geçti / 0 kaldı** |
| **mevcut** | `2026-09-13-post-faz2-sema-dokumu.sql` + üretim sonrası stok migration'ları + `2026-09-18-bar-a1-guvenlik.sql` + 09-13 kat hizmetleri izinin temsili | **89 geçti / 0 kaldı** |

> **İki taban da ZORUNLUDUR.** Şema dökümü bulunamazsa o koşum "atlandı"
> sayılmaz, **başarısız** olur (alt süreç çıkış **70**), üst sonuç `SINANMADI —
> ZORUNLU TABAN EKSIK` yazar ve `PROVA GECMEDI` ile çıkar. Sıfır ölçümlü koşum
> da başarısızdır. Bu davranış kalıcı testle korunuyor:
> `scripts/pms-canliya-gecis-provasi.test.mjs` (**4 / 0**) — gerçek döküm
> dosyalarına dokunmadan olmayan yol enjekte eder. Özellikle `mevcut` taban
> makineye özel bir yola bağlı olduğundan, başka bir makinede hiç sınanmayan
> taban artık yayın kanıtı gibi görünemez.

Ölçülenler (her iki tabanda):

| Konu | Ölçüm |
|---|---|
| Temiz kurulumda Ön Büro | PMS modül satırı **0**, üç Ön Büro rolü referans veriden geliyor |
| Sıra kapısı | Tohumlama önce koşulursa `MALI_AYRIM_KURALI_YOK` ile **durdu**; yetki satırı sayısı ve modül satırı **değişmedi** |
| Adım 1 | Kendi doğrulama bloğu geçti; iki tetikleyici kuruldu; gerekçe kuralı tek kaynakta |
| Adım 2 | Kendi doğrulama bloğu geçti; 4 fonksiyon definer; `pms_oda_konaklama_isaretle` yok; gövdeler gerçekten değişti |
| Adım 4 (tohumlama) | Son durumda **15 hedef çift doğru seviyede**; eklenen damgalı satır = önceden **eksik** olan sayı; beş modül aktif; damga biçimi doğru; **önceden var olan satırlara dokunulmadı** (09-13 kat hizmetleri izi dahil) |
| **Önceden var olan yetkiler** (YP-1) | **1 uyumlu mevcut → 14 yeni** satır (15 değil), mevcut satır damgalanmadı · **15'i de mevcut → 0 yeni** ve koşum **başarılı** · **1 çelişen mevcut → `CELISEN MEVCUT YETKI` ile durdu**, 0 satır yazıldı, çelişen satır değişmedi · her senaryoda son durum **15/15** · dosyanın kendi bildirdiği sayı (`eklenen_yetki_satiri=N/15`) ölçümle **aynı** |
| Menü ve KVKK deltası | Önce menüyü gören **hiçbir rol kapanmadı**; yeni görenler **yalnız** üç Ön Büro rolü; `pms_misafir_kimlik` için yeni satır **0** *ve* mevcut sayı **sabit** (iki ayrı ölçüt) |
| Onaylı kapsam | personel normal tahsilat **kabul** · personel iade **ret** · personel düzeltme **ret** · şef gerekçesiz iade **ret** · şef gerekçeli iade **kabul** |
| Değişmezlik | Şef dahil kimse mevcut mali satırı **update/delete edemedi**; satır ve değeri yerinde |
| Idempotenslik | Üç dosya da ikinci kez uygulanabildi; ikinci tohumlama **yeni satır üretmedi**, bunu kendisi de `0/15` diye bildirdi ve ilk koşumun damgasını **ezmedi** |
| **Geri alma, belgedeki sırayla** (YP-3) | Yanlış sıra negatif kontrolü: tohumlama ayaktayken mali kural geri alması **engellendi** · kimlik verilmeden tohumlama geri alması **durdu** · sonra **belgedeki veritabanı sırası** koşuldu: **tohumlama → MY-4 kilidi → mali kural** · 15 satır kalktı, referans veri ve 09-13 izi **dokunulmadı** · kilit geri almasında yalnız invoker sayısı değil **üç gövdenin `md5` değeri Faz 1 özetlerine birebir döndü**, **ACL** Faz 1 beklentisine döndü (`anon` kapalı) ve `search_path` pinsiz kalan yok · mali satırlar **silinmedi**, folyo satır sayısı korundu |
| Preflight | **Yalnız okuma** (yazma anahtar sözcüğü 0) ve **psql meta komutu içermiyor** → SQL Editor ile de çalışır · §3 sınıflandırması `uyumlu 0 / eksik 15 / çelişen 0` dedi · §6 gövde kapısı üç fonksiyonda da `UYGUN` dedi · çelişen satır kurulduğunda **yayın öncesi yakaladı** (`Adim 4 KOSULMAZ`) |

### Yayın öncesi beklenen gövde özetleri (preflight §6)

09-07 ve 09-13 dökümlerinde **birebir aynı** ölçüldü; yani Faz 2 bu üç gövdeye
dokunmamıştır. Yayın penceresinde üretimden okunan değerler bunlarla
karşılaştırılır:

| Fonksiyon | `md5(prosrc)` |
|---|---|
| `pms_rezervasyon_kontrol` | `83da45a3c84f8e64cd414b78817e5ed2` |
| `pms_check_in` | `3798c9461390f18f97e537bd9be07612` |
| `pms_check_out` | `6d6bb0ecbef41ff1a13fc437857f49fa` |

### Aynı kapsamdaki diğer koşumlar (bu paketle birlikte yeşil)

| Süit | Sonuç |
|---|---|
| `pms-rol-entegrasyon` | 53 / 0 |
| `pms-folio-mali-yetki` | 109 / 0 |
| `pms-bar-borc-istisnasi` | 17 / 0 |
| `pms-modul-tohum` | 68 / 0 |
| Dört PMS süiti (iki migration uygulanmış tabanda) | 59 / 0 |
| `pms-cikis-dialog` | 31 / 0 |
| `scripts/check.mjs` | 18 JS + 59 HTML, çıkış 0 |
| `migration-guvenlik-kontrol` | 36 dosya, **0 HATA**, 3 uyarı |
| `migration-guvenlik-kontrol.test` | 15 / 0 |
| `kurulum-onkontrol.test` | 6 / 0 |
| `pms-canliya-gecis-provasi.test` (provanın kendi testi) | 4 / 0 |

**Fikstür itirafı:** izole tabanı kurarken `bar-test-tohum.sql`'in yazdığı
modül/rol satırları kaldırılıp gerçek `02-referans-veri.sql` kuruluyor. Sebep
ölçüldü: `moduller_kod_key` (`stok_takip`) ve `roller_kod_key` (`depo`)
çakışması. Silinen satırlar iki adım önce test tarafından yazıldı; kurulumun
içeriği değil.

---

## 5. Yedek, geri alma, kabul ve durma koşulları

### 5.1 Yedek

Runbook §2.4 + §11 (şifreli yedek) geçerlidir. **Yedek doğrulanmadan hiçbir
migration başlamaz.** Yedeğin kurtarma kapsamı **auth'u içermez** (§7, §10);
bu sınır yayın kaydına yazılır.

### 5.2 Geri alma — tercih sırası

1. **Özellik kapatma (en hızlı, veri kaybı yok).** `moduller` tablosunda ilgili
   PMS modülünün `aktif = false` yapılması. `auth_yetki_var()` modül aktifliğini
   şart koştuğu için RLS politikaları anında kapanır, ekranlar menüden düşer.
   - **Uyarı (Faz 1'de doğrulandı):** `pms_folio` modülünü kapatmak **bar
     köprüsünü durdurmaz** (`pms_bar_folio_koprusu` SECURITY DEFINER'dır ve
     `auth_yetki_var` çağırmaz). Modül kapalıyken bar teslimatları borç
     yazmaya devam eder ama kimse folyoyu göremez — **görünmez borç birikir.**
     Gerçekten durdurmak gerekirse önce köprü tetikleyicisi düşürülür.
   - Mali ayrım kuralı modül kapatmadan **etkilenmez** ve zararsızdır; kalabilir.
2. **Adım bazlı geri alma — TERS SIRA ZORUNLU.** **Adım 4 → 3 → 2 → 1**, yani:

   | Sıra | Geri alınan | Kanal |
   |---|---|---|
   | 1. | **Adım 4** — tohumlama (`…-tohumlama-geri-al.sql`, uygulama kimliği elle) | veritabanı |
   | 2. | **Adım 3** — arayüz: önceki commit yeniden yayınlanır | git/push — **SQL değil** |
   | 3. | **Adım 2** — MY-4 kilidi (`…-kilit-geri-al.sql`) | veritabanı |
   | 4. | **Adım 1** — mali kural (`…-mali-yetki-ayrimi-geri-al.sql`) | veritabanı |

   **Veritabanı sırası: tohumlama → MY-4 kilidi → mali kural.** Prova tam
   **bu** sırayı koşar (S11 → S12 → S13). Arayüz geri alması ayrı kanaldır ve
   **SQL provasının kapsamında değildir**; bu sınır açık bırakılmıştır.

   Sıra ölçüldü ve dosyalar tarafından **zorlanıyor**: tohumlama ayaktayken
   mali kuralın geri alınması `GUVENLI GERI DONUS ENGELI` ile reddediliyor
   (atlayan bayrak yoktur) — provada yanlış sıra negatif kontrolü olarak
   koşuluyor (S10).
3. **Yedekten dönüş.** Yalnız 1 ve 2 yetmezse.

**Finansal veri sınırı (Faz 1 kuralı, korunur):**
`select count(*) from public.pms_folio_odemeler` > 0 ise **geri alma yapılmaz**,
özellik kapatma tercih edilir. Bu paketin üç dosyası da mali satır **silmez**
(S13c/S13d'de ölçüldü), ama sınır yayın kaydına yazılır.

### 5.3 Başarısızlıkta durma koşulları — tek liste

| # | Koşul | Davranış |
|---|---|---|
| D1 | Preflight'ta tek bir `SAPMA` | Adım 1 başlamaz |
| D2 | Yedek doğrulanamadı | Yayın başlamaz |
| D3 | Preflight §6 gövde özetleri beklenenden farklı | Adım 2 **koşulmaz** (kilit, başkasının değişikliğini sessizce geri alırdı) |
| D4 | Preflight §1'de pasif PMS modülü | Adım 4 koşulmaz; pasife alma kararı araştırılır |
| D5 | Preflight §2'de Ön Büro rolü eksik | Adım 4 koşulmaz |
| D6 | Herhangi bir migration'ın kendi doğrulama bloğu hata verdi | İşlem kendini geri alır; sonraki adım başlamaz |
| D7 | Adım 1 sonrası normal tahsilat reddediliyor | Adım 1 geri alınır (henüz tohumlama yok, hard gate devrede değil) |
| D8 | Adım 2 sonrası 4 fonksiyondan biri definer değil | Adım 2 geri alınır |
| D9 | Adım 4 sonrası **15 hedef çiftten biri doğru seviyede değil**, ya da eklenen damgalı satır sayısı preflight §3'teki **EKSİK** sayısına eşit değil, ya da önceden var olan bir satır değişmiş | Adım 4 geri alınır (kimlik damgadan okunur). *Önceden uyumlu satır varsa 15'ten az eklenmesi **doğru** davranıştır; geri alma gerektirmez* |
| D9b | Preflight §3 **CELISEN** satır gösteriyor (mevcut seviye hedefle uyuşmuyor) | Adım 4 **koşulmaz**. Dosya zaten `CELISEN MEVCUT YETKI` ile durur ve hiçbir satır yazmaz; mevcut hak bu paketle değiştirilmez |
| D10 | Adım 4 sonrası `pms_misafir_kimlik` satırı oluşmuş | Adım 4 geri alınır — KVKK kapsamı, ayrı karar |
| D11 | Duman testinde personel check-in yapamıyor | Adım 4 geri alınır; MY-4 kapsamı yeniden açılır |
| D12 | Kesinti plandaki eşiği aşıyor | İleri yönlü düzeltme bırakılır, geri alma veya özellik kapatma |

### 5.4 Yayın sonrası kabul adımları

| # | Kabul | Nasıl kanıtlanır |
|---|---|---|
| K1 | Menü **delta**: önce menüyü gören hiçbir rol kapanmamış; **yeni** gören roller yalnız üç Ön Büro rolü | Preflight §3b önce/sonra karşılaştırması + iki rolle giriş |
| K2 | Personel rezervasyon → check-in → check-out yapabiliyor | Gerçek kayıt, ekrandan |
| K3 | Personel normal tahsilatı gerekçesiz girebiliyor | Gerçek kayıt |
| K4 | Personelin iadesi / indirimi / düzeltmesi reddediliyor | Hata mesajı `MALI_TAM_YETKI_GEREKLI` |
| K5 | Şef gerekçesiz iade yapamıyor, gerekçeliyi yapabiliyor | İki deneme |
| K6 | Mevcut mali satır update/delete edilemiyor | İki deneme (şef kimliğiyle) |
| K7 | Son durumda **15 hedef çift doğru seviyede**; eklenen damgalı satır = preflight §3 **EKSİK** sayısı; önceden var olan satırların seviye ve `guncelleyen`'i değişmemiş | Preflight §3'ün önce/sonra koşumu + sayım sorgusu |
| K7b | `pms_misafir_kimlik`: yeni satır **0** *ve* önceden var olan satır sayısı **sabit** | İki ayrı sayım (preflight §3c önce/sonra) |
| K8 | Denetim izi sayacı arttı | Önce/sonra sayım |
| K9 | Yeni taban parmak izi kaydedildi | Preflight §7 çıktısı runbook'a |
| K10 | Canlı iki arayüz dosyasının SHA-256'sı commit'tekiyle aynı | Canlı indirme + özet |

> Giriş sonrası canlı akışlar **kullanıcıya aittir**: üretim PIN'i ajanda
> yoktur ve olmamalıdır.

---

## 6. Gerçek engeller

| # | Seviye | Engel | Kimde |
|---|---|---|---|
| **E-1** | **Yayını durdurur** | **Güncel taban parmak izi YOK.** Depodaki en güncel ölçüm 2026-09-07 (post-Faz 1: 75 tablo / 234 politika / 40 kısıtlayıcı). Üretim o günden sonra Faz 2, stok, Bar A1 ve sayım onay kapısını aldı. Runbook §2.3'ün istediği "sıfır sapma" bu hâliyle **iddia edilemez**. Preflight §7 bu tabanı üretir ama **salt-okuma canlı erişim gerektirir** | Kullanıcı (§7'deki kapsamı onaylaması) |
| **E-2** | **Yayını durdurur** | **Üretimin bugünkü modül/yetki durumu bilinmiyor.** Tohumlamanın 15 satır mı yoksa daha az mı yazacağı, pasif modül olup olmadığı, bugün folyoya kimin yazabildiği repodan **okunamaz** | Kullanıcı (aynı salt-okuma kontrolü) |
| **E-3** | Karar | **K-Y1:** dalın tamamı mı (A) yalnız PMS dosyaları mı (B) birleştirilecek | Kullanıcı |
| **E-4** | Karar | **Kesinti penceresi.** Adım 1 uygulandığı anda `kayit` seviyesindeki herkes için iade/indirim/düzeltme reddedilmeye başlar. Pencere, aktif tahsilat saatlerinin dışında seçilmeli | Kullanıcı |
| **E-5** | Risk kabulü | Adım 2 uygulandıktan sonra geri dönüş **Ön Büro akışını kapatır**. Geri alma sessiz bir iyileştirme değildir | Kullanıcı |
| **E-6** | P3 | `rol-entegrasyon-kilit.sql`, `pms_check_in`/`pms_check_out`'u yeniden tanımlarken **EXECUTE revoke/grant kararı yazmıyor** (statik denetleyici R9 uyarısı). `create or replace` mevcut ACL'i koruduğu için üretimde zararsızdır; yeni yazılan geri alma dosyası ACL'i açıkça yeniden kuruyor. İleri yönlü dosyaya da eklenmesi **ayrı karardır**; bu pakette değiştirilmedi | Kullanıcı |
| **E-7** | P3 | **PMS süitleri CI'da koşmuyor** (`statik-kontroller.yml` yalnız `check.mjs`). Docker gerektirdikleri için CI'ya eklenmesi ayrı karar | Kullanıcı |
| **E-8** | Kapsam dışı | **D1 — açık bakiyeyle check-out.** `pms_check_out` folyo bakiyesine bakmaz; belgelenmiş Faz 1 kararıdır ve bu pakette **değiştirilmedi** | — |
| **E-9** | Kapsam dışı | `pms_misafir_kimlik` (KVKK) ve kat rolleri (`kat_*`) **ikinci pakete** ait; bu pakette yetki verilmez | — |
| **E-10** | **Temiz kurulumu etkiler** | **Yeni bulgu (2026-10-07, ACL ölçümünden çıktı).** `2026-09-07-post-pms-faz1-sema-dokumu.sql` içinde `pms_bar_folio_koprusu` için `REVOKE ALL … FROM PUBLIC` **yok**; `anon`, EXECUTE hakkını PUBLIC üzerinden **devralıyor**. `2026-09-13` dökümünde revoke **var**. Yani 2026-09-08 ACL temizliği taban dökümüne **girmemiş**. Sonuç: `KURULUM-REHBERI`nin tarif ettiği temiz kurulum, `2026-09-08-pms-fonksiyon-acl-temizligi.sql` da uygulanmadıkça `anon` EXECUTE'u **açık** bırakır. **Bu paketin ürettiği bir gerileme değil**, kurulum sırasında önceden var olan bir boşluktur; üretim bu temizliği 08 Eyl'de almıştır. Çare provada kanıtlandı: dosya uygulanınca boşluk kapanıyor (P3f/P3g). Rehberin güncellenmesi **ayrı karardır**; bu pakette değiştirilmedi | Kullanıcı |

---

## 7. Canlı erişim gerekirse — salt-okuma kontrolünün KAPSAMI

E-1 ve E-2 ancak üretimden okumakla kapanır. Aşağıdaki kontrol
`2026-10-07-pms-onburo-yayin-oncesi-preflight.sql` dosyasıdır ve
**ONAY BEKLİYOR — çalıştırılmadı.**

**Yapılacaklar (yalnız `SELECT`):**

| # | Ne okunur | Niçin |
|---|---|---|
| 1 | `moduller`: beş PMS kodu, `aktif`, `sira` | Tohumlama ekleyecek mi, atlayacak mı; pasif modül D4'ü tetikler |
| 2 | `roller`: üç Ön Büro rolünün varlığı | Eksikse D5 |
| 3 | **Onaylı 15 hedef çift ile mevcut durumun karşılaştırması:** her çift `UYUMLU MEVCUT` / `EKSIK` / `CELISEN` olarak sınıflanır + özet sayım | **Beklenen yeni satır = EKSİK sayısı** (15 değil). `CELISEN` varsa Adım 4 koşulmaz (D9b) |
| 3b | Beş modül için **tüm** yetki satırları (hedef dışı roller dahil) | Menü kabulü **önce/sonra delta** olarak yapılabilsin; mevcut yetkili roller kapatılmasın (K1) |
| 3c | `pms_misafir_kimlik` için mevcut satırlar | Yeni satır 0 **ve** mevcutlar silinmemiş — iki ayrı ölçüt (K7b) |
| 4 | `pg_trigger`: `pms_folio_hassas_kapi` sayısı | Kısmi uygulama var mı |
| 5 | `pg_proc`: üç fonksiyonun `prosecdef`'i + `pms_oda_tipi_kilitle` | Kilit zaten uygulanmış mı |
| 6 | `pg_proc`: üç fonksiyonun `md5(prosrc)` ve uzunluğu | **En kritik.** §4'teki beklenen değerlerle tutmazsa D3 |
| 6b | **Kesin fonksiyon imzaları** (`oid::regprocedure`), `anon` / `authenticated` / `service_role` için **efektif EXECUTE**, `prosecdef` ve `proconfig` (`search_path`) — `pms_check_in`, `pms_check_out`, `pms_oda_tipi_kilitle`, `pms_folio_hassas_mi`, `pms_bar_folio_koprusu` | `create or replace` ACL'yi korur ama ACL'nin **doğru olduğunu kanıtlamaz**. Beklenen: `anon` kapalı, `authenticated`+`service_role` açık, definer ise `search_path` pinli. Sapma **yalnız raporlanır**; otomatik `GRANT/REVOKE` **yapılmaz**, karar kullanıcınındır. E-10 bu blokla bulundu |
| 7 | Tablo / politika / kısıtlayıcı sayıları, RLS kapalı tablo, pinsiz SECURITY DEFINER, `anon` tablo hakkı | **Eksik olan güncel tabanı üretir (E-1)** |
| 8 | `pms_folio_odemeler`, `pms_folio_hareketleri`, açık folyo sayıları | Geri alma sınırı |
| 9 | `pms_folio` yetkisi olan roller + aktif kullanıcı sayısı | Adım 1'in operasyonel etkisi (E-4) |
| 10 | `erp_islem_audit` satır sayısı | Duman testi tabanı |

**Yapılmayacaklar:** hiçbir `INSERT/UPDATE/DELETE/TRUNCATE`, hiçbir DDL,
hiçbir `GRANT/REVOKE`, hiçbir fonksiyon çağrısı, hiçbir `SET`. Yazma anahtar
sözcüğü içermediği statik taramayla ölçüldü (prova P1); psql meta komutu da
içermediği ölçüldü (P1b), yani **SQL Editor'a olduğu gibi yapıştırılabilir**.
Kimlik bilgisi ajanda yoktur; sorguları kullanıcı çalıştırır ve çıktıyı
paylaşır.

**Operasyonel kabul penceresi ve gerçek mali kayıt üretecek duman testinin
kapsamı, tutarı, kaydı ve düzeltme yöntemi kullanıcı kararıdır.** Yerel
testler canlı mali işlem yetkisi vermez.

---

## 7b. Bağımsız inceleme kapanışı — 2026-10-07

İnceleme: `2026-10-07-f144033-PMS-yayin-paketi-inceleme.md` (taban `f144033`).
Üçü de **yalnız belge ve prova** düzeltmesiyle kapandı; SQL, yetki matrisi ve
kapanmış ürün kuralları **değişmedi**.

| # | Bulgu | Kapanış |
|---|---|---|
| **YP-1** | Kabul kuralları "tam 15 yeni satır" istiyordu; önceden uyumlu satır varsa doğru kurulum daha az ekler ve belge gereksiz geri alma isterdi. Menü ve KVKK ölçütleri de koruma sözleşmesiyle karıştırılmıştı | Sözleşme **deltaya** çevrildi: son durumda 15 hedef çift doğru seviyede + eklenen damgalı satır = preflight'taki **EKSİK** sayısı. Preflight 15 hedefi `UYUMLU MEVCUT / EKSIK / CELISEN` olarak sınıflıyor; `CELISEN`'de durulur (dosya zaten `CELISEN MEVCUT YETKI` ile duruyor — **ölçüldü, SQL değişmedi**). Menü ve KVKK **önce/sonra delta** oldu. Prova dört hali ölçüyor: 14 yeni, 0 yeni, çelişen → ret, ve her halde son durum 15/15 |
| **YP-2** | Şema dökümü yoksa koşum "atlandı" sayılıp üst sonuç `GECTI` diyebiliyordu; `mevcut` taban makineye özel yola bağlı | İki taban **zorunlu**. Eksik döküm artık **başarısız** (alt süreç çıkış **70**), üst sonuç `SINANMADI — ZORUNLU TABAN EKSIK` + `PROVA GECMEDI`. Sıfır ölçümlü koşum da başarısız. Kalıcı negatif test eklendi (`pms-canliya-gecis-provasi.test.mjs`, 4/0): gerçek döküme dokunmadan olmayan yol enjekte ediyor, kısmi koşumun da `GECTI` demediğini ve atlanmayan tabanın gerçekten ≥70 ölçüm yaptığını doğruluyor |
| **YP-3** | Belgedeki geri alma sırası (tohum → arayüz → MY-4 → mali) ile provanın koştuğu sıra (tohum → mali → MY-4) farklıydı | **Belgedeki sıra esas alındı.** Prova artık veritabanı sırasını aynen koşuyor: **tohumlama → MY-4 kilidi → mali kural**. Kilit geri almasında yalnız invoker sayısı değil, **üç gövdenin `md5`'i Faz 1 özetlerine birebir döndü**, **ACL** Faz 1 beklentisine döndü ve `search_path` pinsiz kalan olmadığı ölçüldü; mali veri korunması ölçümü duruyor. Yanlış sıra negatif kontrolü ve mali hard gate korundu. **Arayüz geri alması bu SQL provasının kapsamında değildir** — sınır açıkça yazıldı |

İncelemenin ürün bulgusu olmayan notlarından kapatılanlar: dosya listesi "25"
sayısına bağlanmaktan çıkarıldı; preflight tek sürümle iki kanalda çalışacak
hâle getirildi (`\echo` kaldırıldı); ACL ölçümü salt-okuma kapsamına eklendi ve
**E-10'u buldu**; entegrasyon önerisi **öneri olarak** kaydedildi, karar
kullanıcıda bırakıldı.

**Çıktısı ne üretir:** yayın kaydına yazılacak güncel taban parmak izi,
tohumlamanın beklenen satır deltası, D3/D4/D5 kapılarının kararı ve Adım 1'in
etkileyeceği rollerin listesi.

---

## 8. İlgili

- `docs/kurulum/URETIM-YAYIN-RUNBOOK.md` — yayın disiplini, §0 yazma dondurması
- `docs/inceleme/PMS-MY4-ROL-ENTEGRASYON-KAPSAMI.md` — Adım 2'nin kapsamı
- `docs/inceleme/PMS-MALI-MY-KAPANIS.md` — Adım 1'in kapanış kaydı
- `docs/inceleme/PMS-MODUL-TOHUMLAMA-ONERISI.md` — Adım 4'ün karar tablosu
- `docs/inceleme/PMS-AKIS-PAKETI.md` — arayüz düzeltmelerinin kaydı
- `scripts/pms-canliya-gecis-provasi.mjs` — bu paketin provası

---

## 12. Mali kural — fonksiyon ACL kararı (2026-10-08, kullanıcı talimatı)

`2026-10-06-pms-folio-mali-yetki-ayrimi.sql` dosyasına
`pms_folio_hassas_mi(text,numeric,text,boolean)` için açık ACL kararı eklendi.
**Üretime dokunulmadı.** Yayın baytı değişti; §2.1 ve son onay paketi §3
güncellendi: yeni SHA-256 `49141ac405dc4bc1f4123c8ba3556a382aeba2b571cbe2c2ecae6a139b0efe2a`.

### Niçin — kırmızı ölçüm

İzole tabanda, migration uygulandıktan **sonra** ölçüldü:

```
proacl = =X/postgres,postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres
anon=true  authenticated=true  service_role=true  PUBLIC=true
```

Baştaki `=X/postgres` **PUBLIC** hakkıdır; `anon` EXECUTE yetkisini PUBLIC
üzerinden **devralıyordu**. Statik denetleyici bunu
`R9-FONKSIYON-ACL-KARARI-YOK` uyarısıyla gösteriyordu.

### Eklenen

```sql
REVOKE ALL ON FUNCTION public.pms_folio_hassas_mi(text,numeric,text,boolean)
FROM PUBLIC, anon;

GRANT EXECUTE ON FUNCTION public.pms_folio_hassas_mi(text,numeric,text,boolean)
TO authenticated, service_role;
```

### Yeşil ölçüm

```
proacl = postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres
anon=false  authenticated=true  service_role=true  PUBLIC=false
```

### Kalıcı regresyon — `pms-folio-mali-yetki.test.mjs`

| # | Ölçüm | Sonuç |
|---|---|---|
| **M9** | `anon=false authenticated=true service_role=true` | OK |
| M9b | `PUBLIC` EXECUTE hakkı kalmadı | OK (`false`) |
| M9c | `proacl` içinde PUBLIC girdisi (`=X/`) yok | OK (0) |
| M9d | `authenticated` fonksiyonu **çağırabiliyor** (işlev bozulmadı) | OK (`true`) |

Blok bilerek **M1'den önce**, yani kural yürürlükteyken koşar: ilk denemede
geri alma fazından sonraya konmuştu ve fonksiyon o noktada düşürülmüş olduğu
için ölçüm boş dönüyordu.

### Denetleyici

`migration-guvenlik-kontrol`: mali dosya artık **TEMİZ**; toplam uyarı
**3 → 2**. Kalan ikisi kilit dosyasının `pms_check_in` / `pms_check_out`
uyarılarıdır (**E-6**) ve bu talimatın kapsamında **değildi** — dokunulmadı.

### Koşumlar

`pms-folio-mali-yetki` **113/0** (önceki 109/0) · `pms-bar-borc-istisnasi`
17/0 · `pms-rol-entegrasyon` 53/0 · `pms-modul-tohum` 68/0 · dört PMS süiti
59/0 · `pms-cikis-dialog` 31/0 · prova temiz **132/0** / mevcut **135/0** ·
`migration-guvenlik-kontrol.test` 15/0 · `check.mjs` 18 JS + 59 HTML çıkış 0.

---

## 13. `doluRez` düzeltmesi — canlıda ölçülen check-out tıkanması (2026-10-08)

Canlı sentetik QA testinde (BOZO / Ön Büro Personeli, oda 101) ölçüldü: oda
sunucuda **dolu** görünürken oda planında **misafir satırı ve "Çıkış" düğmesi
hiç çizilmedi**; resepsiyon check-out yapamadı.

### Kök neden

```js
const atama = ATAMALAR.find(a=>a.oda_id===o.id && a.aktif);   // İLK aktif atama
```

Faz 1 kararı gereği check-out'tan sonra atama `aktif = true` **kalır** (geçmiş
konaklama kaydı). Aynı odada eski bir `cikis_yapildi` ataması listede önce
gelirse fonksiyon o rezervasyonun durumuna bakıp `null` döner. `cikisAc()` de
aynı fonksiyonu kullandığı için check-out yolu tamamen kapanır.

### Düzeltme

Bütün aktif atamalar taranır; atama **ve bağlı rezervasyon durumu birlikte**
değerlendirilir, ilk eşleşmede durulmaz. Aynı odada birden fazla *içeride*
konaklama görünürse **rastgele ya da sıraya bağlı seçim yapılmaz**: durum
`belirsiz` olarak işaretlenir, kart "TUTARSIZ: n içeride konaklama" yazar,
Çıkış düğmesi **görünür ama pasif** olur ve `cikisAc()` açıklayıcı bir uyarıyla
reddeder. Düğmeyi gizlemek, canlıda yaşanan tıkanmayı sessizce tekrar üretirdi.

### Regresyon — `scripts/pms-oda-plani-doluluk.test.mjs` (**15 / 0**)

| # | Ölçüm |
|---|---|
| **D1** | Eski (`cikis_yapildi`) atama **önce**: oda doğru rezervasyonla dolu çözümleniyor |
| D1b | Kartta **doğru** misafir yazıyor (eski konuk değil) |
| D1c / D1d | Çıkış düğmesi var ve doğru odayı çağırıyor |
| **D2** | Yeni atama önce: **aynı sonuç** — sıralamadan bağımsız |
| D3 / D3b | İçeride misafir yok: `null`, Çıkış düğmesi yok |
| **D4** | **Gecikmiş konaklama** (planlanan çıkış geçmiş, `giris_yapildi`): dolu sayılıyor, Çıkış var |
| **D5** | Birden fazla içeride konaklama: belirsizlik işaretleniyor, aday sayısı raporlanıyor |
| D5c | Çıkış **görünür ama pasif** |
| D5d | Sıralama değişse de **aynı aday kümesi** — rastgelelik yok |

**Kırmızı→yeşil:** düzeltmesiz kodda **8 geçti / 7 kaldı**; düzeltmeyle 15/0.
**Diş kanıtı:** eski `.find()` mantığı mutant olarak geri konulduğunda test
yine **8/7**'ye düşüyor.

Test kurgusunda bulunan iki kendi kusurum da düzeltildi: fikstür hataları
sessizce yutuluyordu ve D5 kurgusu `pms_oda_atamalari` üzerindeki **EXCLUDE**
kısıtına takılıyordu (`session_replication_role = replica` kısıtları devre dışı
bırakmaz, yalnız tetikleyicileri). D5 artık çakışmayan tarihlerle kuruluyor.

### Yayın baytı değişti

| Dosya | Eski | Yeni |
|---|---|---|
| `pms-oda-plani.html` | `c99f766f…d053faf` | `89942b6c…1e000a` |

**Canlı karşılaştırması (2026-10-08, ölçüldü):**

| Dosya | Canlı | Aday | Yayın adımı |
|---|---|---|---|
| `pms-folio.html` | `bae4da41…7031be` | `bae4da41…7031be` | **aynı — yayınlanacak bir şey yok** |
| `pms-oda-plani.html` | `c99f766f…d053faf` | `89942b6c…1e000a` | **farklı — Adım 3'te yayınlanmalı** |

Yani paketin Adım 3'ü artık **tek dosyalık** gerçek bir adımdır.

### Koşumlar

`pms-oda-plani-doluluk` **15/0** · `pms-akis-ekran` 13/0 · `pms-uctan-uca` 21/0 ·
`pms-hata-durumlari` 13/0 · `pms-rezervasyon-misafir` 12/0 ·
`pms-cikis-dialog` **31/0** · prova 2/2 **PROVA GEÇTİ** · `check.mjs` çıkış 0.

Canlıdaki `R-2026-000005` ve geçmiş atamalara **dokunulmadı**.
