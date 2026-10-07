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

## 5. YEDEK — alma ve doğrulama

> **Proje Free planda ve Supabase proje yedeği ALMIYOR** (runbook §7,
> 2026-09-12'de panelden ölçüldü). Tek yedek elle alınandır. **"Dosya oluştu"
> yedek kanıtı değildir.**

### 5.1 Alma

```bash
cd C:/Users/USER/Projects/gurok-pms-yayin-b && powershell -File docs/kurulum/yedek-ve-sayac-al.ps1 -Etiket 2026-10-07-pre-pms-onburo
```

Snapshot dışarı verilemezse betik bunu söyler; o durumda `-Duraklatma` ile
yeniden koşulur (sayaçlar yedekten önce ve sonra okunur, farklıysa yedek
reddedilir). Üretilen dosyalar repo dışıdır
(`C:\Users\USER\ERP-Yedek\2026-10-07-pre-pms-onburo-*`). **Auth yedeği sır
taşır:** paylaşılmaz, repoya konmaz.

### 5.2 Doğrulama — bu geçmeden Adım 1 başlamaz

```bash
cd C:/Users/USER/Projects/gurok-pms-yayin-b && node scripts/pms-yedek-geri-yukleme-provasi.mjs C:/Users/USER/ERP-Yedek/2026-10-07-pre-pms-onburo-veri-yedegi.sql C:/Users/USER/ERP-Yedek/2026-10-07-pre-pms-onburo-sayaclar.json --sema docs/kurulum/2026-09-07-post-pms-faz1-sema-dokumu.sql --auth-veri C:/Users/USER/ERP-Yedek/2026-10-07-pre-pms-onburo-auth-yedegi.sql --auth-sema C:/Users/USER/ERP-Yedek/2026-10-07-pre-pms-onburo-auth-sema.sql
```

**Kabul ölçütleri (yedi aşama, süreleri ayrı raporlanır):**

| # | Ölçüt | Eşik |
|---|---|---|
| Y1 | Geri yükleme hata sayısı | **0** |
| Y2 | Auth kapsamı sayıyla raporlandı | rapor var |
| Y3 | Her yabancı anahtar yeniden doğrulandı | ihlal **0** |
| Y4 | Satır sayıları üretim sayaçlarıyla birebir | **tam eşleşme**; `pms_folio_odemeler` **3**, `pms_folio_hareketleri` **6** |
| Y5 | Üç veri tutarlılık kontrolü | hepsi **0** |
| Y6 | Temel uygulama erişimi (gerçek kimlikle `authenticated` okuma; `anon` kapalı) | geçti |
| Y7 | Auth kurtarma — `kullanicilar.auth_user_id` eşleşmesi | eksik **0** |

`--mekanik` kipi **kabul kanıtında kullanılmaz**.

**STOP:** Y1–Y7'den biri geçmezse yayın başlamaz. Kapsam dışı (her durumda):
storage, realtime, veritabanı rolleri ve uzantıları, proje ayarları.

---

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

### 7.1 Kalıcılık uyarısı — önce okunmalı

Mali satırlar **append-only**'dir: duman testinde yazılan borç ve tahsilat
**silinemez**. Faz 1 yayınında da bu yüzden üretimde kalıcı, net sıfır iki
konaklama kaldı. Aşağıdaki kapsam bunu bilerek **net sıfır** kurgular.

### 7.2 Yetki ve akış kontrolleri — mali kayıt ÜRETMEZ

| # | Kontrol | Beklenen |
|---|---|---|
| D1 | `onburo_personel` ile giriş | Ön Büro menüsü **görünür** |
| D2 | `it_admin` ve `sistem_admin` ile giriş | Menü **hâlâ görünür** (P2) |
| D3 | Ön Büro dışı bir rolle giriş | Menü **görünmez** |
| D4 | `onburo_personel`: misafir + rezervasyon kaydı | kabul |
| D5 | `onburo_personel`: **check-in** ve **check-out** | kabul (MY-4 kilidinin canlı kanıtı) |
| D6 | `onburo_personel`: oda **tipi** düzenleme denemesi | **ret** (yetki genişlemedi) |
| D7 | Yetki sayımı | 25 satır · 10'u damgasız · 15'i damgalı |

### 7.3 Mali kontroller — KALICI KAYIT ÜRETİR (karar sizde)

Sentetik misafir (**gerçek misafir verisi yok**) ve tek konaklama üzerinde:

| # | Kontrol | Beklenen | Kalıcı iz |
|---|---|---|---|
| M1 | `onburo_personel`: normal tahsilat, **gerekçesiz** | **kabul** | +1 ödeme |
| M2 | `onburo_personel`: negatif tutar (iade) | **ret** `MALI_TAM_YETKI_GEREKLI` | yok |
| M3 | `onburo_personel`: `duzeltme` satırı | **ret** | yok |
| M4 | `it_admin`: gerekçesiz iade | **ret** (açıklama zorunlu) | yok |
| M5 | `it_admin`: gerekçeli iade | **kabul** | +1 hareket |
| M6 | Mevcut mali satırı güncelleme/silme (admin kimliğiyle) | **ret** | yok |
| M7 | Denetim izi 119'dan arttı | evet | — |

**Kapanış ve düzeltme yöntemi:** M1 ve M5 kalıcıdır. Önerilen kurgu, folyoyu
**net sıfıra** getirip kapatmaktır: oda ücreti borcu → eşit tahsilat → bakiye 0
→ folyo kapanır. M5'in iadesi de aynı folyo içinde eşit bir hareketle
dengelenir. Böylece muhasebe etkisi **sıfır** olur ve hiçbir satır silinmez.
**Tutar ve bu kurgunun kabulü sizin kararınızdır** — sembolik bir tutar
(ör. 1,00) ya da Faz 1'deki gibi gerçekçi bir tutar seçilebilir.

**Giriş sonrası canlı akışlar kullanıcıya aittir:** üretim PIN'i ajanda yoktur
ve olmamalıdır.

---

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
