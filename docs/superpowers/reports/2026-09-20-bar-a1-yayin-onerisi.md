# Bar A1 — Yayın Önerisi (tek talimat) + iki açık konunun netleştirilmesi

**Tarih:** 2026-09-20 (üçüncü tur) · **Dal:** `bar-a1` (yerel, push yok) · **Üretim:** bu turda da
yazma yapılmadı. Aşağıdaki canlı ölçümlerin **hepsi salt okumadır** (anon anahtarla HTTP sondası,
`git fetch`). Yayın talimatı hâlâ yok; 5. bölüm bir **öneridir**.

| # | Konu | Durum |
|---|---|---|
| 1 | Chrome manuel turu → kabul raporuna işlendi | **TAMAM** |
| 2 | Canlı sayım tabloları + oluşturma/listeleme akışı | **AÇIK — ölçüldü: bugünkü yetki düzeninde çalışmıyor** |
| 3 | Yayında yazma durdurma + başlamış işlemler / işlem kapısı | **KONTROL HAZIR, CANLI SONUÇ YOK** (yayın penceresi açılmadı) |
| 4 | Canlı Edge kodu ve müşteri şeması karşılaştırması | **YAPILDI — 1 FARK BULUNDU** (`rapid-handler`) |
| 5 | Tek yayın önerisi | **ONAY BEKLİYOR** |

---

## 1. Chrome sonuçları kabul raporunda

Manuel turun sonuçları kabul raporuna (`2026-09-18-bar-a1-rapor.md`, "Gerçek tarayıcı kabul turu"
bölümü) ve ayrıntılı tablo hâlinde `2026-09-20-bar-a1-yayin-kapisi-raporu.md` 4. bölüme işlendi.
Betiğin altına da uygulama kaydı eklendi (`docs/kurulum/2026-09-20-manuel-tarayici-testi.md`).

Kısaca gerçek Chrome'da, gerçek yerel pencerelerle ve gerçek tıklamayla kanıtlananlar: doğrulama
(doğrulayan kaydıyla), nedenli ret, kapalı folyoda yetkisiz teslimin **reddi**, yetkilinin istisna
açması (stok düşer, **borç yazılmaz**), sayım onayında kısmi uygulama (Limon 80 → 70) ve bekleyen
düzeltmenin uygulanması (Bira 80 → 70). Her adımın sonucu veritabanından okunarak doğrulandı.
**Kapanmayan alt madde:** her pencerede "Tamam" seçildi; "İptal"/boş bırakma dalları gerçek
tıklamayla ayrıca sınanmadı (otomatik ekran testlerinde var).

## 2. Canlı sayım tabloları ve oluşturma/listeleme akışı — AÇIK

Haklısınız: **Onay/Uygula testleri bu maddeyi karşılamıyor.** Onay ve detay okuma A1'in
`SECURITY DEFINER` RPC'lerinden geçer; oluşturma, listeleme ve reddetme ise ekrandan **doğrudan
tabloya** gider ve RLS'e tabidir. Bugün ölçtüm.

**Ölçüm A — izole ortam, A1 uygulanmış, gerçek `authenticated` cost_control kimliği** (PostgREST'in
kullandığı yolun aynısı: `set role authenticated` + `request.jwt.claims`):

| İşlem | Nasıl gider | Sonuç |
|---|---|---|
| Oturum listeleme (SELECT) | doğrudan tablo | 1 satır — **ama yalnız test ortamına konmuş `test_yalniz_okuma` permissive politikası sayesinde** |
| Oturum oluşturma (INSERT) | doğrudan tablo | **RLS reddi** ("new row violates row-level security policy") |
| Oturum reddetme (UPDATE) | doğrudan tablo | **0 satır** (sessiz; yazma yok) |
| Detay doğrudan okuma | doğrudan tablo | **permission denied** — A1'in bilinçli kısıtı |
| Detay okuma (RPC) | `stok_sayim_detaylari()` | 2 satır ✔ |
| Onay / bekleyen düzeltme | `stok_sayim_onayla()`, `…_bekleyen_uygula()` | çalışıyor (manuel turda da kanıtlı) |

**Ölçüm B — üretim, salt okuma (2026-09-20, sizin çalıştırdığınız sorgu):** `sayim_oturumlari`nda
yalnız RESTRICTIVE politika, `sayim_detaylari`nda **hiç politika yok**; iki tablo da **0 satır**.
Yani üretimde permissive politika olmadığı için listeleme 0 satır döner, oluşturma reddedilir.

**Sonuç:** sayım **oluşturma/listeleme/reddetme akışı gerçek yetki düzeniyle doğrulanamadı, çünkü
bugünkü şemada hiçbir ortamda çalışmıyor.** İzole ortamda listeleme yalnız test amaçlı eklenen bir
politikayla göründü; oturumlar SQL ile tohumlandı. Bu **A1'in getirdiği bir kusur değil** (üretimde
özellik bugüne kadar hiç kullanılmamış, veri yok) ve A1 bunu düzeltmiyor da.

**Yayına etkisi:** A1 canlıya alınsa bile sayım özelliği **kullanılamaz durumda kalır**; "sayım
akışı çalışıyor" denemez. Düzeltme ayrı iştir (`task_fb7dee02`) ve orada **`sayim_detaylari`ya
doğrudan `SELECT` grant'i geri verilmemeli**, yalnız permissive politika eklenmelidir.

## 3. Yazma durdurma ve başlamış işlemler — işlem kapısının durumu

Üç parça var; ikisi hazır ve ölçülü, biri ancak yayın anında sonuç verir.

1. **Yeni yazmaların durdurulması — sunucu tarafı, asıl kontrol.**
   `docs/kurulum/2026-09-20-yayin-yazma-duraklat.sql` `authenticated` rolünden stok yazma
   haklarını alır (`stok_ekle` iki imza, `stok_transfer`, `stok_hareketleri` INSERT, `stok`
   INSERT/UPDATE); okuma açık kalır; `…-surdur.sql` geri verir. İkisi de denetim izine satır
   düşer. **Ölçüldü:** `scripts/bar-a1-yayin-kilidi.test.mjs` 7/7 (D1–D7).

2. **İşlem kapısı sorgusu — `docs/kurulum/2026-09-20-yayin-oncesi-islem-kontrol.sql`.**
   Salt okuma; açık mal kabul belgelerini, son hareketliliği ve kalem bazlı eşleştirmeyi basar.
   **İzole ölçümü 4/4** (`scripts/bar-a1-yayin-kontrol-sorgu.test.mjs`): "stok değişmiş ama
   hareket yok" durumu **ŞÜPHELİ** olarak işaretleniyor, "eksik" olarak değil.
   **Canlı sonucu yoktur:** yayın penceresi açılmadığı için üretimde çalıştırılmadı. Anlamlı
   çıktıyı ancak duraklatmanın hemen ardından verir (o anki açık belgeler). İsterseniz bugün de
   salt okuma olarak çalıştırabilirsiniz; o çıktı yalnız bir **taban ölçüsü** olur, yayın kapısı
   yerine geçmez.

3. **Başlamış işlemlerin tamamlanması — GÜVENCE ALTINA ALINAMIYOR (değişmedi).**
   Ekranlar çok satırlı işlemi satır satır, ayrı HTTP istekleriyle yazar; sunucuda bir "işlem
   kimliği" yoktur. Duraklatma başlamış işlemi **tamamlamaz, sonraki satırında keser** (D4 ile
   ölçüldü). Bu yüzden: hareketsizlik sorgusu **yalnız yardımcı kanıttır**, "ekranlar kapalı
   doğrulandı" denmez; risk azaltma personele duyuru + hareketsizlik beklemesi + duraklatma
   sonrası "hata alan işlem oldu mu" sorusudur; **risk sıfırlanmaz.** Yayından sonra eksik
   görünen kalem **körlemesine yeniden yazılmaz**: önce kalem bazında stok etkisi + hareket +
   onay zamanı eşleştirilir; ŞÜPHELİ satırlar iz ve gerekirse fiziksel sayımla doğrulanır.

## 4. Canlı Edge kodu ve müşteri şeması — karşılaştırma sonucu

Yöntem: müşteri projesinin **public anon anahtarıyla** salt okuma sondaları (yazma yapmayan
yollar: sürüm `ping`, bozuk JSON, JWT'siz istek) + `origin/main` ile kod karşılaştırması.

| Canlı uç | Canlı yanıt | Repo (`origin/main`) | Sonuç |
|---|---|---|---|
| `rapid-handler` (masa-yonetim) | `{"ok":true,"v":"bolge1"}` | ping sürümü `"anon3"` (+`anonLen` alanı) | **FARK VAR** |
| `hyper-api` (siparis-gonder) | 400 `{"mesaj":"Geçersiz JSON"}` | aynı davranış (JSON ayrıştırma önce) | eşleşiyor |
| `smooth-service` (menu-yayinla) | 401 `{"mesaj":"Yetkisiz: personel oturumu gerekli"}` | aynı — yetki kontrolü JSON'dan **önce** | eşleşiyor |

| Müşteri şeması (anon ile görülebilen) | Beklenen | Sonuç |
|---|---|---|
| `menu_urunler` | anon okur, `otel_id` kolonu var (03-menu-yayin uygulanmış) | ✔ (`id, ad, kategori, fiyat, ucretli, aktif, otel_id`) |
| `masa_tokenlari` | anon **hiçbir şey** görmemeli | ✔ boş döndü |
| `siparis_arsiv` | anon **hiçbir şey** görmemeli | ✔ boş döndü |

**Bulgu (yayını doğrudan etkiler):** canlı `rapid-handler`, repodaki temel sürüm **değil**. Sürüm
etiketi `bolge1`; repoda böyle bir etiket yok (`origin/main` = `anon3`). Yani müşteri projesine
repo dışından bir sürüm deploy edilmiş. A1 tam da bu fonksiyonu değiştiriyor; **canlı kaynağı
görmeden üzerine deploy edilirse repoda bulunmayan bir değişiklik sessizce silinir.**
Zorunlu ön koşul: Supabase Dashboard → müşteri projesi → Functions → `rapid-handler` kaynağı
indirilip repodaki sürümle karşılaştırılmalı; fark A1 sürümüne taşınmalı. Bu, Dashboard girişi
gerektirdiği için sizde.

Politika/fonksiyon düzeyinde **derin** karşılaştırma için salt okuma dosyası hazır:
`docs/kurulum/2026-09-20-musteri-projesi-karsilastirma.sql` (müşteri projesinin kendi parolasıyla,
`-SaltOkuma` ile çalışır). Zorunlu değil; yukarıdaki yüzeysel kontrol izolasyonun durduğunu
gösteriyor.

## 5. Tek yayın önerisi (onaylanırsa tek talimat yeterlidir)

### 5.1 Kesin kapsam

| Öğe | Değer |
|---|---|
| Kaynak dal | `bar-a1` — uç commit yayın anında `git rev-parse bar-a1` ile sabitlenir (bu rapor yazılırken `e03d3c0`) |
| Taban | `origin/main` = **`9c06661`** (bugün `git fetch` ile doğrulandı: hâlâ ata) |
| Commit sayısı | 35 (`9c06661..e03d3c0`) |
| Değişen ekran dosyaları | `bar-siparis-kuyrugu.html`, `bar-garson.html`, `bar-menu.html`, `stok-takip.html`, `pms-folio.html`, `gunluk-tuketim.html`, `mal-kabul-liste.html`, `ortak.js`, `stok-veri.js`, `hata-kodlari.js` |
| Migration | `docs/kurulum/2026-09-18-bar-a1-guvenlik.sql` |
| Geri alma | `docs/kurulum/2026-09-18-bar-a1-guvenlik-geri-al.sql` |
| Edge | `rapid-handler` (yalnız bu; diğer iki fonksiyon A1'de **değişmedi**) |

Yayın anında commit yeniden doğrulanır: başka bir oturum `main`e commit atmış olabilir. `git fetch`
sonrası `origin/main` hâlâ ata değilse **durulur**, rebase edilir ve birleşme sonrası mükerrer
`const` taraması yapılır (beyaz sayfa sebebi).

### 5.2 Sıra ve gerekçesi (ölçüme dayalı)

1. **Ekranlar önce.** Yeni ekranlar A1 **öncesi** veritabanıyla çalışır (yeni `stok_ekle` imzası
   yoksa yalnız `PGRST202`de eski imzaya düşer — 9/9 ölçüldü). Tersi doğru değil: **eski**
   stok-takip + A1 veritabanı sayımı yanlış yazardı; A1 bunu sunucuda engelliyor ama kullanıcı
   hata alır. Bu yüzden ekranlar migration'dan önce gider.
2. **Migration sonra.**
3. **Edge en son.** Yeni `rapid-handler` migration'dan **önce çalışmaz** (403 — E2E'de ölçüldü).

### 5.3 Adımlar

| # | Adım | Not |
|---|---|---|
| 0 | **Salt okuma ön kontroller** | `git fetch` + ata kontrolü; A1 ön koşul md5'leri; T0 anlık görüntü; işlem kapısı sorgusu (taban) |
| 1 | **YEDEK** — ilk üretim değişikliğinden önce | Ekran push'u da üretim değişikliğidir: yedek **push'tan da önce**. Dosya var + boyut > 0 + geri yükleme komutu yazılı olmadan 2. adıma geçilmez |
| 2 | **Yazma duraklatma** | `2026-09-20-yayin-yazma-duraklat.sql`; denetim satırı `A1-YAYIN-DURAKLATMA` görülür |
| 3 | **İşlem kapısı** | `2026-09-20-yayin-oncesi-islem-kontrol.sql`; açık belge/hareketlilik listelenir. Yarım kalan şüphesi varsa **durulur** |
| 4 | **Ekranlar** | `main` → sabitlenen uç commit (fast-forward); ardından sayfa açılış duman testi |
| 5 | **Migration** | `sql-uygula.ps1 -Dosya docs\kurulum\2026-09-18-bar-a1-guvenlik.sql`; dosya son koşullarını kendi içinde doğrular |
| 6 | **Edge** | `rapid-handler` deploy — **yalnız 4. bölümdeki fark çözülmüşse** |
| 7 | **Yazma sürdürme** | `2026-09-20-yayin-yazma-surdur.sql` — **migration başarısız olsa bile çalıştırılır**, yoksa stok yazmaları kapalı kalır |
| 8 | **Yeniden açma kontrolleri** | aşağıdaki liste |
| 9 | **Eşleştirme** | işlem kapısı sorgusu tekrar; ŞÜPHELİ satır **yeniden yazılmaz**, incelenir |

### 5.4 Yeniden açma (duman) kontrolleri — 8. adım

1. Stok-takip: bir ürüne **+1 / −1** hareket → yazıyor mu (duraklatma gerçekten kalktı mı).
2. Mal kabul: açık bir belgede tek kalem onayı → stok **ve** hareket birlikte yazıldı mı.
3. Bar: QR menüden ücretli sipariş → kuyrukta "oda doğrulaması bekliyor" çıkıyor mu; doğrula →
   teslim → folyoya borç yazıldı mı.
4. Bar masa yönetimi (yalnız 6. adım yapıldıysa): masa listesi geliyor mu, **başka otelin masası
   görünmüyor** mu.
5. Ön büro: `pms-folio` istisna bölümü açılıyor mu (açık istisna yoksa boş liste beklenir).
6. Denetim izi: `A1-YAYIN-DURAKLATMA`, `A1-GECIS-ISARETI`, `A1-YAYIN-SURDURME` satırları var mı.
7. **Sayım: kontrol edilmez** — 2. bölümdeki nedenle üretimde zaten çalışmıyor.

### 5.5 Geri dönüş

| Katman | Geri dönüş |
|---|---|
| Migration | `2026-09-18-bar-a1-guvenlik-geri-al.sql` (ön koşul: açık istisna ve bekleyen sayım yok) |
| Ekranlar | `main`i önceki commit'e (`9c06661`) döndürmek |
| Edge | önceki kodun yeniden deploy'u — **canlı kaynak elde değilse bu geri dönüş yoktur**; 4. bölümdeki fark bu yüzden deploy'un ön koşuludur |
| Yazma hakları | `…-surdur.sql` her hâlükârda |

### 5.6 Durma kuralları

Onaylanan kapsam ve sıradan **herhangi bir beklenmeyen farkta durulur** ve size dönülür: ön koşul
tutmazsa, `origin/main` ata değilse, işlem kapısında yarım kalan şüphesi varsa, migration son
koşulu hata verirse, duman testi başarısızsa veya `rapid-handler` canlı kaynağı repodan farklıysa.

### 5.7 Karar gereken tek şey

| Seçenek | İçerik |
|---|---|
| **A** | Tam yayın: canlı `rapid-handler` kaynağı önce Dashboard'dan indirilir, fark A1 sürümüne taşınır, sonra 0–9 adımları uygulanır |
| **B** | Bölünmüş yayın: şimdi yalnız ekranlar + migration (6. adım atlanır); `rapid-handler` ayrı bir yayında. Bu durumda masa yönetimindeki otel kapsamı açığı **açık kalır** |

Öneri: **A** — Edge açığı A1'in gerekçelerinden biri; ama Dashboard girişi sizde olduğu için
sırayı siz belirlersiniz. Yayın talimatı verilene kadar üretimde hiçbir şey yapılmaz.
