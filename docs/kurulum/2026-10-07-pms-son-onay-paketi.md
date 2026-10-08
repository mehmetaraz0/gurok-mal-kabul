# PMS Ön Büro — SON ONAY PAKETİ

> **BU BELGE YAYIN İZNİ DEĞİL, ONAY TALEBİDİR.** Üretime hiçbir şey
> uygulanmadı; push, merge, deploy ve canlı SQL yazımı yapılmadı. Canlı yayın
> yalnız açık `CANLIYA UYGULA` onayıyla başlar (`URETIM-YAYIN-RUNBOOK.md` §0).

- **Tarih:** 2026-10-07
- **Yayın adayı (B seçeneği):** dal `pms/yayin-adayi-b`, worktree
  `C:/Users/USER/Projects/gurok-pms-yayin-b`, taban `origin/main` = `a77e6e1`
- **Yayın öncesi canlı taban:** `URETIM-YAYIN-RUNBOOK.md` **§14** (salt-okuma,
  çıkış 0, SAPMA yok)
- **Sıra, geri alma ve durma koşulları:**
  `docs/kurulum/2026-10-07-pms-canliya-gecis-paketi.md`

---

## 1. Ne onaylanıyor, ne onaylanmıyor

| Onay isteniyor | Onay İSTENMİYOR (bu pakette yok) |
|---|---|
| Üç migration'ın §3'teki sırayla üretime uygulanması | `pms_misafir_kimlik` (KVKK) yetkisi |
| İki arayüz dosyasının `origin/main`'e push'u | Kat rolleri (`kat_*`) ve `pms_housekeeping` ikinci paketi |
| §5'teki yedek alma ve doğrulama | Açık bakiyeyle check-out iş kuralının değişmesi (D1) |
| §7'deki canlı kabul (duman) testi — **kalıcı mali kayıt üretir** | Temiz kurulum rehberinin E-10 düzeltmesi |
| §6'daki pencere | Otomatik ACL düzeltmesi (gerekmedi; canlı ACL temiz) |

**Hâlâ karar bekleyen:** yayın penceresi tarihi/saati (§6), duman testinin tutarı
ve düzeltme yöntemi (§7.3).

---

## 2. Kesin yayın adayı

29 dosya; kaynağı `pms/akis-tamamlama` ve **29/29 sha256 birebir** (ölçüldü).
İP-7'nin 55 commit'i, kurulum/R11-B4'ün 3 commit'i ve onların 124 dosyası
adayda **yok**. `docs/inceleme/vm-betikleri/vm-32-pms-inceleme.sh` bilinçle
dışarıda.

**Pencerede yeniden doğrulanacak:** `git rev-parse HEAD` ve §3'teki beş
SHA-256. Çalışma ağacı temiz olmalı.

---

## 3. Uygulama sırası ve yayın baytları

| Adım | İşlem | SHA-256 (commit, LF) |
|---|---|---|
| 0 | Onay · kod dondurma · **yedek + doğrulama (§5)** · preflight'ı yeniden koş | — |
| 1 | `2026-10-06-pms-folio-mali-yetki-ayrimi.sql` | `9b687b8b…c89cc8` |
| 2 | `2026-10-06-pms-rol-entegrasyon-kilit.sql` | `59e9d14a…98fa1e` |
| 3 | Arayüz push: `pms-folio.html` · `pms-oda-plani.html` | `bae4da41…7031be` · `c99f766f…d053faf` |
| 4 | `2026-10-05-pms-onburo-modul-tohumlama.sql` — **`set local app.pms_k1 = 'kayit';` satırı elle açılır** | `9fa9741b…33c4642` |
| 5 | Yayın sonrası parmak izi + kabul (§8) | — |

Kanal: **`psql --single-transaction`** (birincil). SQL Editor yedek kanal.
Preflight artık her iki kanalda da çalışıyor.

> **`sql-uygula.ps1` çalışma kopyasını (CRLF) özetler, yayın baytını (LF)
> değil.** Preflight için ekranda beklenen:
> `8FBE6BC5375417C09CEA8BFDDE41B6C93497698043DF9AECFA004A53DEF8C58D`.

---

## 4. KABUL LİSTESİ — korunacak sayılar

Canlı ölçüm (runbook §14) bu sayıları sabitledi. **Her biri yayın sonrası
tek tek doğrulanır.**

### 4.1 Korunacak mevcut durum

| # | Korunacak | Değer | Nasıl doğrulanır |
|---|---|---|---|
| **P1** | `it_admin` + `sistem_admin` yetkileri | beş modülde `tam`, **10 satır** | Sayım + `guncelleyen` hâlâ damgasız |
| **P2** | Bu iki rolün Ön Büro menüsü | **bugün de görünüyor, görünmeye devam edecek** | İki rolle giriş, önce/sonra |
| **P3** | `pms_folio_odemeler` | **3 satır** | Sayım **ve** toplam tutar aynı |
| **P4** | `pms_folio_hareketleri` | **6 satır** | Sayım **ve** toplam tutar aynı |
| **P5** | Beş modül satırı | **var ve AKTİF (5)** | Tohumlama modül satırı eklemez/değiştirmez |
| **P6** | `pms_misafir_kimlik` | **0 satır** | Yeni satır 0 **ve** mevcut sayı 0 |
| **P7** | Açık folyo | **0** | Yayın anında yeniden okunur |

### 4.2 Beklenen değişiklik

| # | Beklenen | Değer |
|---|---|---|
| **B1** | Tohumlamanın ekleyeceği **damgalı** satır | **15** (preflight'ta eksik = 15) |
| **B2** | Beş modül için son durum | **10 korunmuş + 15 yeni = 25** |
| **B3** | Menüyü **yeni** görecek roller | yalnız `onburo_sef`, `onburo_vardiya`, `onburo_personel` |
| **B4** | `onburo_personel / pms_folio` | `kayit` (K1 = A) |
| **B5** | Hassas kapı tetikleyicisi | 0 → **2** |
| **B6** | Üç fonksiyon + kilit yardımcısı | `prosecdef` **4** |
| **B7** | Denetim izi | **119'dan artmış** olmalı |

### 4.3 Bu sayıların dayanağı — izole provada ölçüldü

`node scripts/pms-canliya-gecis-provasi.mjs` — **temiz 103/0 · mevcut 106/0 ·
2/2 PROVA GEÇTİ**. Üretime bağlanmaz.

`S15` bloğu **canlı ölçümün aynasıdır**: beş modül aktif, üç Ön Büro rolü var,
15 hedef çift eksik, `it_admin` + `sistem_admin` beş modülde `tam`.

| Ölçüm | Sonuç |
|---|---|
| S15b / S15c | 15 yeni damgalı satır; dosya da `15/15` bildirdi |
| **S15d / S15e** | **10 yönetici yetkisi korundu**, satırları damgalanmadı |
| **S15f** | Beş modül için son durum **25** (10 + 15) |
| S15g | Beş modül hâlâ aktif — tohumlama `moduller`'a dokunmadı |
| **S15h** | Menüyü önce gören `it_admin`, `sistem_admin` **hâlâ görüyor** |
| **S11c2 / S11c3** | Tohumlama **geri alındıktan sonra** bile 10 yönetici yetkisi sağ, damgasız |
| S11c4 / S11c5 | Geri alma modül satırını düşürmedi; beş modülde yalnız 10 yönetici satırı kaldı |
| **S13e / S13f** | Üç migration + **üç geri alma** boyunca başlangıçtaki mali satırların **hiçbiri silinmedi**; sayı hiç azalmadı |

---

## 5. YEDEK — bileşenler, alma ve doğrulama

> **Proje Free planda ve Supabase proje yedeği ALMIYOR** (runbook §7,
> 2026-09-12 panel ölçümü). Tek yedek elle alınandır. **"Dosya oluştu" yedek
> kanıtı değildir.**

### 5.1 Yedek SETİ — beş bileşen birlikte tanımlanır

Bir yedek, bu beşinin **aynı sürümü** temsil eden takımıdır. Eksik veya
uyuşmayan bileşen doğrulamayı **başarısız** yapar.

| # | Bileşen | Üreten | Dosya |
|---|---|---|---|
| 1 | **Uygulama şeması** (tablolar, RLS, politikalar, fonksiyonlar) | `dokum-al.ps1` | `<Etiket>-sema-dokumu.sql` |
| 2 | **Veri** (`public` + `phase0_private`) — **şifreli** | `yedek-ve-sayac-al.ps1` | `<Etiket>-veri-yedegi.sql.enc` |
| 3 | **Sayaçlar** (aynı durumu temsil eden satır sayıları) | `yedek-ve-sayac-al.ps1` | `<Etiket>-sayaclar.json` |
| 4 | **Auth** — veri **şifreli** (sır taşır) + şema yapısı | `yedek-ve-sayac-al.ps1` | `<Etiket>-auth-yedegi.sql.enc` · `<Etiket>-auth-sema.sql` |
| 5 | **Beklenen şema parmak izi** | elle, preflight §7 çıktısından | `<Etiket>-parmakizi.json` |

> **Neden şema da gerekiyor:** `yedek-ve-sayac-al.ps1` yalnız **veri** çıkarır.
> Veriyi eski bir şema dökümünün üstüne geri yüklemek, satır sayıları tutsa
> bile *güncel* veritabanını geri kurduğunu **kanıtlamaz**. Bu paketin canlı
> ölçümü **79/240/41**; depodaki 2026-09-07 dökümü **75/234/40**. Bu yüzden
> yedek penceresinde **taze şema dökümü** alınır.

5. bileşen, preflight §7 çıktısından yazılır:

```json
{"tablo":79,"politika":240,"kisitlayici":41,"rls_kapali":0,"pinsiz_definer":0,"anon_tablo_hakki":0}
```

### 5.2 Alma — komutlar ayrı ayrı

> Kullanıcının PowerShell sürümü `&&` kabul etmiyor. Komutlar **ayrı** verilir;
> dizin değişimi başarısızsa sonrakine geçilmez.

```bash
cd C:/Users/USER/Projects/gurok-pms-yayin-b
```

```bash
powershell -File docs/kurulum/dokum-al.ps1 -Etiket 2026-10-07-pre-pms-onburo
```

```bash
powershell -File docs/kurulum/yedek-ve-sayac-al.ps1 -Etiket 2026-10-07-pre-pms-onburo
```

Snapshot dışarı verilemezse betik bunu söyler; o durumda aynı komut
`-Duraklatma` ile yeniden koşulur (sayaçlar yedekten önce ve sonra okunur,
farklıysa yedek **reddedilir**). Çıktılar repo dışındadır
(`C:\Users\USER\ERP-Yedek\`). **Şifreleme kaldırılmaz:** betik `.sql.enc`
üretir ve düz kopyayı siler; alıcı sertifikası doğrulanmazsa ikisini de siler.

**Auth yedeği sır taşır** (parola hash'leri, e-postalar, canlı oturum
token'ları): paylaşılmaz, repoya konmaz, e-postayla gönderilmez, sohbete
yazılmaz.

### 5.3 Doğrulama — bu geçmeden Adım 1 başlamaz

Şifreli yedeği açmak için gizli anahtar gerekir; anahtar **bu makinede
durmaz**, parola yöneticisinden gelir. Bu yüzden her prova aynı zamanda bir
**anahtar tatbikatıdır**.

> **Önceki sürümdeki iki adımlı talimat ÇALIŞMIYORDU (SO-1a, ölçüldü).** Alt
> bir PowerShell'de kurulan ortam değişkeni **ebeveyne geri taşınmaz**, bu
> yüzden ardından çalıştırılan `node` aynı parola ortamını hiç görmezdi.
> Ayrıca çift tırnak içindeki `$` değişkenleri dış kabukta genişliyordu.
> **"Provanın kendi istemi" diye bir alternatif de YOK:** prova OpenSSL'i
> `spawnSync` ile çağırır, `-passin env:YEDEK_ANAHTAR_PAROLA` verir ve
> etkileşimli istem göstermez.

Bu yüzden parola alma, ortam kurma, Node'u başlatma ve temizlik **tek
süreçte** yapılır — `docs/kurulum/yedek-prova-kos.ps1`:

```bash
powershell -File docs/kurulum/yedek-prova-kos.ps1 -Yedek C:\Users\USER\ERP-Yedek\2026-10-07-pre-pms-onburo-veri-yedegi.sql.enc -Sayaclar C:\Users\USER\ERP-Yedek\2026-10-07-pre-pms-onburo-sayaclar.json -Sema C:\Users\USER\ERP-Yedek\2026-10-07-pre-pms-onburo-sema-dokumu.sql -ParmakIzi C:\Users\USER\ERP-Yedek\2026-10-07-pre-pms-onburo-parmakizi.json -AuthVeri C:\Users\USER\ERP-Yedek\2026-10-07-pre-pms-onburo-auth-yedegi.sql.enc -AuthSema C:\Users\USER\ERP-Yedek\2026-10-07-pre-pms-onburo-auth-sema.sql -GizliAnahtar C:\gecici\anahtar-kopyasi.pem -GeciciAnahtariSil
```

Betik parolayı `Read-Host -AsSecureString` ile sorar; parola **komut satırına,
PowerShell geçmişine ve hiçbir dosyaya yazılmaz**. `finally` bloğunda BSTR
belleği `ZeroFreeBSTR` ile sıfırlanır, `YEDEK_ANAHTAR_PAROLA` silinir.

> **`-GizliAnahtar` bir GEÇİCİ KOPYA olmalıdır.** `-GeciciAnahtariSil` yalnız
> o kopyayı siler; **asıl kurtarma anahtarına dokunmaz** (parola
> yöneticisinde kalır). Her prova aynı zamanda bir **anahtar tatbikatıdır**.

> **Parmak izi JSON'u BOM'lu olabilir.** PowerShell 5.1'in
> `Set-Content -Encoding utf8` komutu dosyaya BOM yazar; ölçüldü ki bu
> `JSON.parse`'ı kırıyordu. Okuyucu artık BOM'u soyuyor, yani PS 5.1'in
> varsayılan çıktısı **geçerli** sayılıyor.

**Kabul ölçütleri (sekiz aşama, süreleri ayrı raporlanır):**

| # | Ölçüt | Eşik |
|---|---|---|
| Y1 | Geri yükleme hata sayısı | **0** |
| Y2 | Auth kapsamı sayıyla raporlandı | rapor var |
| Y3 | Her yabancı anahtar yeniden doğrulandı | ihlal **0** |
| Y4 | Satır sayıları üretim sayaçlarıyla birebir | **tam eşleşme**; `pms_folio_odemeler` **3**, `pms_folio_hareketleri` **6** |
| Y5 | Üç veri tutarlılık kontrolü | hepsi **0** |
| Y6 | Temel uygulama erişimi (gerçek kimlikle `authenticated` okuma; `anon` kapalı) | geçti |
| Y7 | Auth kurtarma — `kullanicilar.auth_user_id` eşleşmesi | eksik **0** |
| **Y8** | **Şema parmak izi** — geri yüklenen şema, yedeğin alındığı sürümle eşleşiyor | **altı alanın TAMAMI** karşılaştırıldı (`karsilastirilan 6/6`) ve **sapma 0**. Eksik, `null`, yanlış tür, negatif değer ve tanınmayan alan **RET**'tir |

**Y8 yeni eklendi ve dişi ölçüldü** (SO-1 kapanışı):

| Deneme | Sonuç |
|---|---|
| 09-07 dökümü + altı alan tam | `karsilastirilan 6/6 · sapma 0 · GECTI` |
| 09-07 dökümü + **güncel** `79/240/41` beklentisi | `sapma 3 · BASARISIZ` → tablo 75≠79, politika 234≠240, kısıtlayıcı 40≠41 |
| **SO-1b karşı örneği:** yalnız `{"tablo":75}` | `karsilastirilan 1/6 · sapma 5 · BASARISIZ` — beş zorunlu alan "ZORUNLU alan eksik — kabul edilemez" |
| Her alanın tek tek eksikliği, `null`, yanlış tür, negatif değer, tanınmayan alan | hepsi **BASARISIZ** (`yayin-kabul-kurallari.test.mjs`) |
| `--parmakizi` **verilmezse** | `SINANMADI` yazılır ve **kabul kanıtı sayılmaz** |

`--mekanik` kipi **kabul kanıtında kullanılmaz**.

**STOP:** Y1–Y8'den biri geçmezse yayın başlamaz. Kapsam dışı (her durumda):
storage, realtime, veritabanı rolleri ve uzantıları, proje ayarları.

> **Yedekten dönüşün kendi riski:** eski bir yedeğe dönmek, yedekten SONRA
> yazılmış **yeni** veriyi kaybettirir. Bu, "bu paketin geri alma dosyaları
> mali satır silmiyor" ölçümünden **ayrı** bir risktir ve §8'de son çare
> olarak durur.

## 6. YAYIN PENCERESİ — öneri (Ö), karar sizde

Ölçüm pencereyi rahatlatıyor: **açık folyo 0**, folyoya `kayit` seviyesinde
**kimse yok**, etkilenen yalnız **3 aktif kullanıcı** (`it_admin` 2,
`sistem_admin` 1 — ikisi de `tam`).

| Konu | Öneri |
|---|---|
| Süre | **45–60 dakika.** Migration'ların kendisi saniyeler sürer; süreyi doğrulamalar ve adım araları alır (09-13'te 44 saniyelik migration 45 dakikalık pencereye oturdu) |
| Zamanlama | Resepsiyon tahsilat saatlerinin **dışında**; demo ortamda aktif operasyon yokken |
| Kesinti var mı | **Tam kesinti yok.** Adım 1'den sonra iade/indirim/düzeltme **gerekçe** ister; normal tahsilat kesintisiz çalışır |
| Önceden duyurulacak | `it_admin` ve `sistem_admin` kullanıcılarına: iade/indirim/düzeltmede **açıklama alanı zorunlu olacak** |
| Hazırlık | Parola pencere başında `-YalnizBaglanti` ile **bir kez** sınanır (09-13: iki hatalı deneme ~6 dakika ekledi) |
| Kanal | **psql birincil.** Tarayıcı otomasyonu yayın kanalı olarak kullanılmaz |
| Kim | Komutları kullanıcı çalıştırır; **ajanın üretim erişimi yok** |

**Pencerede yeniden alınacak kontroller** (ölçüm bayatlamasın diye):
preflight §1 (modül aktifliği) · §3 özet (uyumlu/eksik/çelişen) · §6 gövde
özetleri · §8 mali sayımlar · aday HEAD ve beş SHA-256.

---

## 7. CANLI KABUL (DUMAN) TESTİ — kapsam önerisi

### 7.1 Kalıcılık — ne iddia edilebilir, ne edilemez

Mali satırlar **append-only**: yazılan borç ve tahsilat **silinemez**; denetim
kayıtları da kalır. Bu yüzden:

- **İddia EDİLMEZ:** "muhasebe etkisi sıfır". Sıfır bakiye, tahsilat/iade/borç
  satırlarını ve denetim izini ortadan **kaldırmaz**.
- **İddia EDİLİR ve doğrulanabilir:** "testin folyosunun **son bakiyesi 0**,
  folyo **kapalı**, ve aşağıdaki kalıcı satırlar **mevcut**".

**Koruma ile delta ayrı ölçütlerdir.** Mevcut 3 ödeme ve 6 hareketin korunması,
test sonrası toplamların hâlâ 3 ve 6 olması **değildir**. Eski satırlar
**kimlik ve içerik** bazında korunur; testin yazdıkları **ayrı bir delta**
olarak sayılır. Önerilen kurguda toplamlar **6→7** ve **3→6** olur.

### 7.2 Yetki ve akış kontrolleri — mali kayıt ÜRETMEZ

| # | Rol | Kontrol | Beklenen |
|---|---|---|---|
| D1 | `onburo_personel` | giriş | Ön Büro menüsü **görünür** |
| D2 | `it_admin`, `sistem_admin` | giriş | Menü **hâlâ görünür** (P2) |
| D3 | Ön Büro dışı bir rol | giriş | Menü **görünmez** |
| D4 | `onburo_personel` | oda **tipi** düzenleme denemesi | **ret** (yetki genişlemedi) |
| D5 | — | yetki sayımı | **25** satır · **10** damgasız · **15** damgalı |

### 7.3 Mali sıra — KALICI KAYIT ÜRETİR (tutar kararı sizde)

Sentetik misafir (**gerçek misafir verisi yok**), tek gecelik konaklama,
sembolik tutar **X = 1,00**. Bakiye tanımı:
**bakiye = borç (`pms_folio_hareketleri`) − ödeme (`pms_folio_odemeler`)**.

> **Tablo yönlendirmesi ölçüldü:** ekranda **iade = negatif TAHSİLAT** ve
> `pms_folio_odemeler`'e yazılır (`pms-folio.html` tahsilat yolu).
> **Düzeltme** ise `pms_folio_hareketleri`'ne yazılır. İkisi ayrı kontroldür.

**Bütün mali işlemler kapanıştan ÖNCE sıralanır** — kapalı folyonun yazma
formları kapalıdır ve sunucu da reddeder.

| # | Rol | Hedef tablo | İşaret / tutar | Beklenen satır artışı | Ara bakiye | Sonuç |
|---|---|---|---|---|---|---|
| M1 | `onburo_personel` | `pms_rezervasyonlar` | `gecelik_fiyat` = +1,00 | — (folyo **otomatik** açılır) | 0,00 | kabul |
| M2 | `onburo_personel` | RPC `pms_check_in` | — | — | 0,00 | kabul (MY-4 kanıtı) |
| M3 | `onburo_personel` | `pms_folio_hareketleri` (RPC oda ücreti) | **+1,00** | **hareket +1** | **+1,00** | kabul |
| M4 | `onburo_personel` | `pms_folio_odemeler` | **−1,00** (iade) | **0** | +1,00 | **ret** `MALI_TAM_YETKI_GEREKLI` |
| M5 | `onburo_personel` | `pms_folio_hareketleri` | `duzeltme` +1,00 | **0** | +1,00 | **ret** `MALI_TAM_YETKI_GEREKLI` |
| M6 | `onburo_personel` | `pms_folio_odemeler` | **+1,00**, gerekçesiz | **ödeme +1** | **0,00** | kabul |
| M7 | `it_admin` | `pms_folio_odemeler` | **−1,00**, gerekçe **yok** | **0** | 0,00 | **ret** (açıklama zorunlu) |
| M8 | `it_admin` | `pms_folio_odemeler` | **−1,00**, gerekçe **var** | **ödeme +1** | **+1,00** | kabul |
| M9 | `onburo_personel` | `pms_folio_odemeler` | **+1,00** (dengeleme) | **ödeme +1** | **0,00** | kabul |
| M10 | `it_admin` | mevcut hareket satırı | UPDATE / DELETE | **0** | 0,00 | **ret** (ikisi de) |
| M11 | `onburo_personel` | RPC `pms_folio_kapat` | — | — | 0,00 | kabul → folyo **kapalı** |
| M12 | `onburo_personel` | `pms_folio_odemeler` (kapalı folyo) | +1,00 | **0** | — | **ret** |
| M13 | `onburo_personel` | RPC `pms_check_out` | — | — | — | kabul |

**Toplam kalıcı delta: `pms_folio_hareketleri` +1 · `pms_folio_odemeler` +3**
(+1,00 / −1,00 / +1,00). Son bakiye **0,00**, folyo **kapalı**.
Beklenen toplamlar: hareketler **6 → 7**, ödemeler **3 → 6**.
Denetim izi **119'dan artar**.

### 7.4 Bu sıra izole ortamda SINANDI

`node scripts/pms-canliya-gecis-provasi.mjs` içindeki **S16** bloğu tam bu
sırayı, ürünün kendi yollarıyla ve sentetik veriyle koşar:

| Ölçüm | Sonuç |
|---|---|
| S16-1…S16-5 | rezervasyon → folyo otomatik → check-in → oda ücreti |
| S16-7 / S16-12 / S16-15 / S16-17 | ara bakiyeler **+1,00 → 0,00 → +1,00 → 0,00** |
| S16-8 / S16-9 / S16-10 | personelin iadesi ve düzeltmesi **ret**, **hiç satır üretmedi** |
| S16-13 / S16-14 | `it_admin` gerekçesiz **ret**, gerekçeli **kabul** |
| S16-18 | mevcut mali satır update/delete **ret** |
| S16-19…S16-22 | folyo **kapandı**, kapalı folyoya yazma **ret**, check-out kabul |
| **S16-23 / S16-24** | **hareket deltası tam 1 · ödeme deltası tam 3** |
| S16-25 / S16-26 | son bakiye **0,00**; başlangıçtaki mali satırların hiçbiri silinmedi |

Prova sonucu: **temiz 130/0 · mevcut 133/0 · 2/2 PROVA GEÇTİ.**

### 7.5 Karar sizde

- **Tutar:** X = 1,00 (sembolik) veya Faz 1'deki gibi gerçekçi bir tutar.
- **Gerçek tahsilat/iade varsayılmaz:** M6/M8/M9 kasa hareketi değil, sistem
  kaydıdır; nakit akışı gerekip gerekmediği sizin kararınız.
- **Kalıcı kayıt üretimi ayrıca kabul edilmeden uygulanmaz.**
- Giriş sonrası canlı akışlar **kullanıcıya aittir**: üretim PIN'i ajanda
  yoktur ve olmamalıdır.

## 8. ÖDEME > 0 — geri dönüş planı (kesinleştirildi)

Ayrıntı: runbook **§14.1**. Özet:

**Ölçüm 3 ödeme olduğu için şema geri alma yolu seçilmez.** Ama kritik ayrım
kayda geçti: **bu paketin üç geri alma dosyası da mali satır silmez**
(S13e/S13f'de ölçüldü). Yasak olan, Faz 1 Adım 4'ün folyo tablolarını düşüren
şema geri almasıdır ve **bu paketin kapsamında değildir.**

| Olay | İlk hamle | Veri etkisi |
|---|---|---|
| Ön Büro rolleri yanlış erişim aldı | Tohumlama geri alma (damgalı 15 satır) | Yalnız damgalı yetki satırları. `moduller`'a **dokunmaz**; 10 yönetici yetkisi ve mali veri **aynen kalır** |
| Check-in/out bozuldu | MY-4 kilidi geri alma | Veri yok. **Bedeli:** Ön Büro akışı kapanır |
| Gerekçe zorunluluğu operasyonu kilitledi | Mali kural geri alma — **yalnız tohumlama geri alındıktan sonra** (hard gate) | Ödeme/hareket **silinmez** |
| Hepsi yetmedi | Modül `aktif = false` | Veri kalır, ama **`it_admin` ve `sistem_admin` de PMS'yi kaybeder**. `pms_folio` kapatmak **bar köprüsünü durdurmaz** → görünmez borç; önce `pms_bar_folio_koprusu` tetikleyicisi düşürülür |
| Son çare | Yedekten dönüş (§5) | Yalnız yukarıdakiler yetmezse, kullanıcı kararıyla |

**Hata olduğu için kendiliğinden YAPILMAYACAKLAR:** tetikleyici düşürme, yetki
silme, yedek yükleme, ödeme/hareket silme, otomatik ACL düzeltmesi. Her biri
ayrı kullanıcı kararıdır.

### 8.1 İKİ AYRI RİSK — karıştırılmamalı

Tablodaki son iki satır **otomatik devam adımı değildir**; her biri ayrı onay
kapısıdır.

| Risk | Nedir | Ölçüm |
|---|---|---|
| **A — bu paketin geri almaları** | Yetki satırı silme (damgalı), fonksiyon gövdesi değiştirme, tetikleyici düşürme | **Mali satır silmez** (S13e/S13f: başlangıçtaki satırların hiçbiri silinmedi, sayı hiç azalmadı) |
| **B — eski yedeğe dönüş** | Yedeğin alındığı andan **sonra** yazılmış veriyi kaybettirir | Prova bu riski **ölçmez**; yedekten dönüş son çaredir ve veri kaybı penceresi yayın saatiyle yedek saati arasındaki farktır |

A'nın güvenli olması B'yi güvenli yapmaz. Faz 1 Adım 4'ün folyo tablolarını
düşüren şema geri alması ise bu paketin kapsamında **hiç yok**.

---

## 9. Açık kalanlar

| # | Konu |
|---|---|
| **E-3** | Entegrasyon: **B hazırlandı.** A seçeneği (dalın tamamı) hâlâ mümkün; karar sizde |
| **E-10** | Temiz kurulum rehberinin `2026-09-08-pms-fonksiyon-acl-temizligi.sql` açığı — canlı ölçüm bunu **kapatmaz**, ayrı karar |
| **E-7** | PMS süitleri CI'da koşmuyor (Docker gerekir), ayrı karar |
| **E-6** | Kilit dosyasının R9 ACL uyarısı — canlı ACL temiz olduğu için yayını durdurmaz |
| **E-8** | Açık bakiyeyle check-out (D1) — belgelenmiş Faz 1 kararı, değişmedi |

**Sayısal parmak izi tek başına tam şema eşitliği kanıtı değildir;** bu paket
canlı kabulün tamamlandığını iddia etmez.

---

## 10. Bağımsız inceleme kapanışı — 2026-10-08

İnceleme: `2026-10-08-5e2a280-PMS-son-onay-inceleme.md`. İkisi de **yalnız
operasyonel talimat ve doğrulama aracı** düzeltmesiyle kapandı; ürün kodu, SQL
ve yetki matrisi **değişmedi**.

| # | Bulgu | Kapanış |
|---|---|---|
| **SO-1** | Yedek doğrulama komutu üretilen yedeğe ve güncel şemaya uymuyordu: `&&` kullanıyordu, şifreli `.sql.enc` yerine düz `.sql` yolları veriyordu, `--gizli-anahtar` arayüzünü anlatmıyordu, ve `--sema` olarak **eski** 09-07 dökümünü (75/234/40) veriyordu — oysa canlı 79/240/41 | §5 yeniden yazıldı: **beş bileşenli yedek seti** tanımlandı (taze şema dökümü + şifreli veri + sayaçlar + auth + **beklenen parmak izi JSON'u**), komutlar **ayrı ayrı** verildi, `.sql.enc` yolları ve parolayı geçmişe yazmayan `--gizli-anahtar` kullanımı yazıldı, şifreleme **korundu**. Provaya **Y8 şema parmak izi aşaması** eklendi: bayrak verilmezse `SINANMADI` yazar ve kabul kanıtı sayılmaz. Dişi ölçüldü — eski şema + güncel beklenti `sapma 3 · BASARISIZ` |
| **SO-2** | Mali duman testi sırası ve beklenen kayıtlar tutarsızdı: iade `+1 hareket` deniyordu (oysa **negatif tahsilat → `pms_folio_odemeler`**), dengeleme **kapanıştan sonra** anlatılıyordu (kapalı folyo yazma kabul etmez), "muhasebe etkisi sıfır" garantisi veriliyordu, ve mevcut 3/6 satırın korunması test sonrası toplamların 3/6 kalmasıyla karışıyordu | §7 yeniden yazıldı: her adım için **rol · hedef tablo · işaret/tutar · beklenen satır artışı · ara bakiye · sonuç** tablosu (M1–M13); bütün mali işlemler **kapanıştan önce**; "muhasebe etkisi sıfır" **kaldırıldı**, yerine doğrulanabilir iddia; **koruma ile delta ayrıldı** (toplamlar 6→7 ve 3→6). Tam bu sıra provaya **S16** olarak eklendi ve sentetik veriyle **geçti** |

**Geri alma ayrımı** incelemenin düzeltmesiyle §8.1'e yazıldı: bu paketin
geri almalarının mali satır silmemesi ile **eski yedeğe dönüşün yeni veriyi
kaybettirmesi** ayrı risklerdir; modül kapatma ve yedekten dönüş **otomatik
devam adımı değildir**.

**Prova:** temiz **130/0** · mevcut **133/0** · 2/2 **PROVA GEÇTİ**
(önceki 103/106).

---

## 11. SO kapanış incelemesi — 2026-10-08 · **KABUL EDİLDİ**

> **Bağımsız kapanış kaydı:** `2026-10-08-cede709-SO-kapanis.md` (B adayı
> `cede709`). **SO-1a / SO-1b / SO-2t KAPALIDIR ve yeniden açılmaz.** Kapanış,
> gerçek yedek geri yükleme kabulü **değildir** ve canlı yayın onayı
> **değildir**.

İnceleme: `2026-10-08-0d074078-SO-kapanis-inceleme.md`. Üçü de **yalnız
operasyonel talimat ve kabul kuralı** düzeltmesiyle kapandı; ürün kodu, SQL ve
yetki matrisi **değişmedi**.

| # | Bulgu | Kapanış |
|---|---|---|
| **SO-1a** | Parola hazırlığı sonraki komuta ulaşmıyordu: alt PowerShell'in ortam değişkeni ebeveyne taşınmaz, çift tırnak içindeki `$` dış kabukta genişler, ve "provanın kendi istemi" diye bir alternatif yok (prova OpenSSL'i `spawnSync` + `-passin env:` ile çağırır) | `docs/kurulum/yedek-prova-kos.ps1` yazıldı: parola alma → ortam kurma → Node → **`finally` temizlik** hepsi **tek süreçte**. `ZeroFreeBSTR` ile BSTR sıfırlanır, `YEDEK_ANAHTAR_PAROLA` silinir, `-GeciciAnahtariSil` yalnız **geçici kopyayı** siler (asıl kurtarma anahtarına dokunmaz). Parola komut satırına/geçmişe/dosyaya **yazılmaz** |
| **SO-1b** | Altı alanlık Y8 kabulü tek alanla geçilebiliyordu (`continue` ile atlanıyordu) | Karar mantığı `scripts/yayin-kabul-kurallari.mjs`'e taşındı: **altı alanın tamamı zorunlu**, her biri sonlu + negatif olmayan **tamsayı**; eksik / `null` / yanlış tür / negatif / **tanınmayan alan** RET. 15 karşı örnek testi kalıcı |
| **SO-2t** | S16-18 `\|\|` kullanıyordu; tek tarafın reddi yetiyordu | `degismezlikKarari()` ile **VE** mantığı: iki deneme de reddedilmeli **ve** satırın kimlik+içeriği korunmalı. Ret nedeni ayrıca ölçülüyor (`S16-18a`). Aynı kusuru taşıyan **S8** de düzeltildi (inceleme yalnız S16-18'i göstermişti) |

### Talimat uçtan uca sınandı — gerçek parola/yedek okunmadan

Sentetik anahtar çifti + sentetik parola + sentetik şifreli dosya üretildi
(gerçek `yedek-anahtari.pem` ve gerçek yedekler **okunmadı**):

| Ölçüm | Sonuç |
|---|---|
| Parola Node'a ulaştı mı | **evet** — çözme başarılı, `COZME BASARISIZ` yok |
| Y8 (altı alan tam) | `karsilastirilan 6/6 · sapma 0 · GECTI` |
| Y8 (yalnız `{"tablo":75}`) | `karsilastirilan 1/6 · sapma 5 · BASARISIZ` |
| Koşum sonrası `YEDEK_ANAHTAR_PAROLA` | **boş** (ebeveynde de boş) |
| Geçici anahtar kopyası | **silindi** |
| Asıl (sentetik) anahtar | **korundu** |

**Yan bulgu — kapatıldı:** PowerShell 5.1'in `Set-Content -Encoding utf8`
komutu parmak izi JSON'una **BOM** yazıyor ve bu `JSON.parse`'ı kırıyordu
(ölçüldü). Fail-closed yönde bir hataydı ama meşru bir yayını bloke ederdi;
okuyucu artık BOM'u soyuyor.

**Koşumlar:** `yayin-kabul-kurallari.test` **15/0** · prova temiz **132/0** ·
mevcut **135/0** · 2/2 **PROVA GEÇTİ** · provanın kendi testi **4/0**.

Gerçek güncel yedek seti + geri yükleme kabulü, yayın penceresi ve canlı kalıcı
test kayıtları **hâlâ ayrı onay kapılarıdır**.

### 11.1 Bağımsız kapanış ölçümleri (2026-10-08)

İncelemecinin kendi koştukları:

| Kontrol | Sonuç |
|---|---|
| `yayin-kabul-kurallari.test` | 15 geçti / 0 başarısız / 0 atlandı |
| Prova — temiz | 132 geçti / 0 |
| Prova — mevcut | 135 geçti / 0 |
| Üst prova | 2/2 taban, çıkış 0 |
| Gerçek `yedek-prova-kos.ps1` + sentetik Node, **başarı** yolu | parola ulaştı · çıkış 0 · env temiz · geçici kopya silindi · asıl dosya korundu |
| Aynı sarmalayıcı, **hata** yolu | parola ulaştı · **çıkış 23 korundu** · aynı temizlik kontrolleri geçti |

### 11.2 Kanıt sınırı — iki ayrı doğrulama, iki ayrı kapsam

| Konu | İncelemecinin kapsamı | Bu paketin kapsamı |
|---|---|---|
| `yedek-prova-kos.ps1` akışı | **Gerçek** betik çağrıldı, altındaki Node **yapay bir süreçle** temsil edildi → bu sondadan **OpenSSL çözmesi geçti sonucu çıkarılmaz**. Ek olarak **hata yolunda çıkış kodunun korunduğu** ölçüldü (bizim turda ölçülmemişti) | **Gerçek** betik + **gerçek** `pms-yedek-geri-yukleme-provasi.mjs` + **gerçek OpenSSL**, **sentetik** anahtar/parola/şifreli dosyayla → çözme başarılı |
| Y8 | Karşı örnekler testlerde; modülün gerçek geri yükleme betiğinden çağrıldığı ve BOM soyulduğu **kaynak farkından** doğrulandı | Gerçek hat üzerinden koşuldu: `6/6 · sapma 0 · GECTI` ve `1/6 · sapma 5 · BASARISIZ` |
| **Y1–Y8 gerçek güncel yedekle** | **koşulmadı** | **koşulmadı** |

İkisi birlikte okunur: sarmalayıcının süreç/temizlik/çıkış-kodu sözleşmesi
bağımsız olarak, OpenSSL çözme yolu ise bu paketin sentetik anahtarlı
koşumuyla ölçülmüştür. **Gerçek anahtar ve gerçek yedek hiçbir turda
okunmadı.**

### 11.3 SIRADAKİ KAPI — kullanıcıda

Bu kayıt hiçbirini kendiliğinden yetkilendirmez:

1. **Gerçek güncel yedek setini al** (§5.1–5.2, beş bileşen) ve izole ortamda
   **Y1–Y8 kabulünü tamamla** (§5.3). Parola ve anahtar yalnız kullanıcıdadır.
2. Ardından **yayın penceresi** (§6) kararı.
3. Ardından **canlı duman testinin tutarı ve kalıcı kayıt üretiminin kabulü**
   (§7.3, §7.5).

Üçü tamamlanmadan `CANLIYA UYGULA` istenmez.
