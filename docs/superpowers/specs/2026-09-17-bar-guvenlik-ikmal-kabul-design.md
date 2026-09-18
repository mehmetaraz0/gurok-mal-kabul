# Bar Güvenliği, Gün Sonu İkmal ve Teslim Kabulü — Tasarım

**Tarih:** 2026-09-17 · **Revizyon:** 5 (2026-09-18) · **Durum:** A1 kararları verildi (bölüm 15);
A1 yalnız yerel/izole ortamda uygulanıyor — push, deploy, canlı migration yok

## Revizyon 4'te değişenler (2026-09-18)

| Konu | Değişiklik |
|---|---|
| Stok tarih düzeltmesi | 2026-09-18'de üretime alındı (`stok_ekle`/`stok_transfer` UPDATE yollarında `guncelleme_tarihi = now()`). A1 bu iki fonksiyonu yeniden tanımlar ve sayım için yeni bir yazma yolu ekleyebilir; düzeltmenin korunması **gereksinim** olarak eklendi (Z9, bölüm 3.5.1) ve testle kanıtlanır. |
| Plan | Eski plan (`2026-09-17-bar-guvenlik-ikmal-kabul.md`) **tamamıyla** tarihsel ve uygulanamaz ilan edildi; yeni plan ayrı: `docs/superpowers/plans/2026-09-18-bar-a1-plan.md`. |
| Edge Function testi | Yerel araç envanteri ölçüldü (Z3 güncellendi); A1'in hangi fonksiyonu değiştirdiği, hangisini yalnız davranışça etkilediği ayrıldı (bölüm 5.1). Test açığını belgeye yazmak bileşeni **yayına hazır yapmaz** (bölüm 5.3). |
| Kararlar | Açık tercihler dört bağımlı gruba toplandı: önerilen seçenek, işletmeye etkisi, alternatif (bölüm 14). Servis kaydı soruları (S1–S4) yalnız Aşama 2'yi etkiler; A1'i bekletmez (bölüm 14.5). |
**Kapsam dışı ilkesi:** mevcut bar modülü **yeniden kurulmaz**; tablolar, sayfalar ve Edge
Function'lar yerinde genişletilir.
**Dayanak:** `docs/BAR-MODULU-ISLEYIS.md` (2026-09-16 bulguları) · üretim şeması
`2026-09-13-post-faz2-sema-dokumu.sql` (bar/stok fonksiyon ve politikaları 09-07 dökümüyle
birebir aynı — özetle doğrulandı) · Aşama 0 raporu `docs/superpowers/reports/2026-09-17-bar-asama0-rapor.md`.

## Revizyon 3'te değişenler

| Konu | Revizyon 2 | Revizyon 3 |
|---|---|---|
| Operasyon günü | Saate bağlı (06:00 kesimi), "yalnız varsayılan değişir" | Tüketim **açık servis kaydının** operasyon gününe bağlanır; saat kesimi yok (T16). Normal teslim tarihi **depo takvimine** bakar (T17). |
| Garson siparişi | Siparişi giren personel onaylamış sayılıyordu (Ö1) | **Kaldırıldı.** Personel oda kartı/misafir kontrolünü **açıkça** onaylar (T18). |
| "Hazırlanıyor" iptali | Tam reçete otomatik zayi | **Kaldırıldı.** Kullanılan malzeme ve miktarı belirlenir (T19). |
| Folyo kapalıyken teslim | Teslim reddedilir → iptal + zayi (Ö6) | **Kaldırıldı.** Fiziksel tüketim ile borçlandırma ayrı ele alınır; başka folyoya otomatik aktarım yok (T20). |
| Edge Function testi | Veritabanı yetki testi Edge Function'ı karşılıyor gibi yazılmıştı | Veritabanı testi uçtan uca test **değildir**; izole çalışma seçenekleri araştırıldı, hiçbiri çalıştırılmadı, **test açığı açık** (T21, bölüm 5). |
| Z başlığı | Gerçek ile seçilen çözüm aynı satırdaydı; sayım durdurma "zorunlu" yazılmıştı | Ölçülen gerçek, bilinme yolu ve tasarım karşılığı ayrıldı. Sayımı rezervasyonda durdurmak **tasarım tercihidir**, zorunluluk değil (T22, Ö10). |
| Aşama 1 kapsamı | Operasyon günü ve `bar_ayarlari` Aşama 1'deydi | Servis kaydı ve operasyon günü **Aşama 2'ye** taşındı; Aşama 1 tüketimi sipariş ve zamanla kaydeder. |

Plan (`docs/superpowers/plans/2026-09-17-bar-guvenlik-ikmal-kabul.md`) Aşama 1 görevleri bu
revizyonla **geçersizdir** ve kesinleşmeler sonrasında yeniden yazılacaktır.

---

## 1. Gereksinimler ve tercihlerin kaynağı

Dört tür madde vardır; birbirine karıştırılmaz: **T** kullanıcının yazılı talebi (kesin),
**V** seçim aracıyla işaretlenmiş ama kesinleşmemiş tercih, **Ö** tasarım önerisi (onay
bekliyor), **Z** ölçülen ya da koddan okunan gerçek. Ayrıca bölüm 1.5'te cevap bekleyen
**açık sorular (S)** listelenir.

### 1.1 T — Kullanıcının yazılı talebi (kesin)

| # | Talep | Kaynak |
|---|---|---|
| T1 | Ücretli üründe aktif konaklama ve açık folyo **sunucuda** doğrulanır; yalnız oda numarası bilmek borçlandırmaya yetmez. | 2026-09-17 talep |
| T2 | Onaylanan fiyat siparişe kaydedilir. | talep |
| T3 | Teslimde stok ve folyo işlemi tutarlı olur; tekrar çağrılarda tekildir. | talep |
| T4 | Rezervasyon yarışları, diğer stok çıkışlarıyla çakışma, otel izolasyonu ve pasif kullanıcı kontrolleri düzeltilir. | talep |
| T5 | Hazırlanan ürünün iptali tüketimi yok saymaz. | talep |
| T6 | Teslim edilmiş siparişlerin kayıtlı stok tüketiminden **bar ve operasyon günü** bazında tek talep taslağı üretilir. | talep |
| T7 | Kaptan miktarları değiştirebilir, ürün ekleyebilir. | talep |
| T8 | Günlük sayım ve ücretsiz her servise giriş zorunlu değildir. | talep |
| T9 | Talep düzeltmesi stok tüketimi sayılmaz. | talep |
| T10 | Cuma operasyonu gece yarısını geçse de Cumartesi teslimatına pazar ilavesi girilebilir; normal talep ve pazar ilavesi ayrı saklanır. | talep |
| T11 | Depo onayı bar stoğunu artırmaz; onay → sevk → kaptan kabulü ayrı aşamalardır; yalnız kabul edilen miktar kullanılabilir bar stoğuna girer; kısmi teslimatlar izlenir. | talep |
| T12 | Mevcut bar modülü yeniden kurulmaz. | talep |
| T13 | Her aşama izole ortamda test edilir ve ayrı raporlanır. | talep |
| T14 | İlk pilot tek barda olacaktır. | talep |
| T15 | Push, migration ya da canlı uygulama yok; ayrıca `CANLIYA UYGULA` onayı beklenir. | talep |
| T16 | Operasyon günü **otomatik saat kapanışı değildir**. Tüketim, **açık servis kaydının** operasyon gününe bağlanır; Cuma servisi Cumartesi 06:00'ı geçse de **bölünmez**. Bu yalnız varsayılan saat değişikliği değildir. | 2026-09-17 düzeltme 1 |
| T17 | Pazar depo kapalıdır; **normal teslim tarihleri depo takvimini** dikkate alır. | düzeltme 1 |
| T18 | Garsonun sipariş girmesi **tek başına doğrulama sayılmaz**; personel oda kartı/misafir kontrolünü yaptığını **açıkça onaylar**. Sunucu aktif konaklamayı ve açık folyoyu doğrular; **onaylayan kaydedilir**. | düzeltme 2 |
| T19 | "Hazırlanıyor" durumundaki iptal **otomatik olarak tam reçete zayisi oluşturmaz**; kullanılan malzeme ve miktarı belirlenir. | düzeltme 3 |
| T20 | Folyonun kapanması ürünü **kendiliğinden zayi yapmaz**; fiziksel tüketim ile borçlandırma sorunu **ayrı** ele alınır. Başka misafirin folyosuna **otomatik aktarım olmaz**. | düzeltme 3 |
| T21 | Veritabanı yetki testi Edge Function'ın **uçtan uca testi değildir**. İzole çalışma alternatifi araştırılır; çalıştırılamıyorsa **test açığı açık kalır**. | düzeltme 4 |
| T22 | Fiziksel sayım rezervasyondan düşük çıkarsa **gerçek gözlem kaydedilebilmelidir**. (Stok düzeltmesinin rezervasyon çelişkisi çözülene kadar bekletilmesi mümkün bir yol olarak belirtildi — bkz. Ö10.) | Z başlığı düzeltmesi |

### 1.2 V — Seçim aracıyla işaretlenmiş, kesinleşmemiş tercihler

| # | Konu | İşaretlenen | Farklı seçilirse |
|---|---|---|---|
| V1 | QR'dan gelen ücretli siparişte oda numarasına ek kanıt | **Personel doğrulaması.** Kullanıcı 2026-09-17 düzeltmesinde bunu "önerilen model" olarak ifade etti ve içeriğini T18'le netleştirdi; model seçimi kesin karar olarak yazılmadı. | *Oda PIN'i:* PMS check-in akışı ve şeması değişir. *Oda no + soyad:* PMS değişmez; eşleşme sunucuda yapılır. |
| V2 | Kaptanın sistemdeki karşılığı | Yeni rol `bar_kaptan` + bar ataması | *Mevcut rol + atama:* rol eklenmez. Etkisi Aşama 2. |
| V3 | Sevk edilip kabul edilmeyen miktar | Açık fark; depo "geri al" ya da "kayıp" ile kapatır | *Otomatik merkeze iade:* fark kapatma adımı kalkar. Etkisi Aşama 4. |

Revizyon 2'deki **V4 (06:00) kaldırıldı**: T16 ile saat kesimi modeli geçersiz.

### 1.3 Ö — Tasarım önerileri (onay bekliyor)

| # | Öneri | Gerekçe | Bağlı talep |
|---|---|---|---|
| Ö1 | **Açık doğrulama beyanı tek adımdır:** `bar_siparis_oda_dogrula(siparis_id, beyan)`. Beyan metni sabittir ("Misafirin oda kartını/kimliğini kontrol ettim"); `beyan=true` gönderilmeden çağrı reddedilir. Garson ücretli siparişi girerken **aynı adımı ayrıca** yapar (ekranda gönderimden sonra ayrı onay); sipariş girişi beyan yerine geçmez. | T18 "açıkça onaylar" diyor; beyanı sipariş girişine gömmek "girmek = onay" algısını geri getirir. Tek adım QR ve garson kanalını aynı kurala bağlar. | T18 |
| Ö2 | Aşama 1 güvenlik düzeltmeleri **tüm barlara** uygulanır; pilot (T14) yalnız Aşama 2–4 için. | T1–T5 güvenlik açığıdır. | T1–T5, T14 |
| Ö3 | Pazar ilavesi penceresi **saate değil teslim tarihine** bağlıdır: Cuma operasyon gününe ait talebin teslim tarihi geçmediği sürece girilebilir. | T10 "gece yarısını geçse de" diyor. | T10, T16, T17 |
| Ö4 | Taslak yalnız **satış** tüketiminden üretilir; zayi taslağa girmez, kaptan elle ekler. | T6 "teslim edilmiş siparişler" diyor. | T6 |
| Ö5 | Bar ikmali **ayrı** tablo ve ekranlarla yürür; diğer departmanların iç talep akışı değişmez. | Mevcut iç talep onayı anında transfer yapıyor (Z7) ve başka departmanlar ona bağlı. | T11 |
| Ö6 | **Borçlandırma istisnası.** Teslim anında bağlı folyo açık değilse teslim ilk denemede `FOLYO_KAPALI` ile durur (sessiz geçiş yok). Personel ürünün **fiziksel olarak servis edildiğini** açıkça onaylarsa teslim tamamlanır: stok **satış** tüketimi olarak düşer, **borç yazılmaz**, aynı işlemde bir `bar_borc_istisnalari` kaydı açılır (sipariş, tutar, oda, eski folyo, onaylayan, zaman). İstisna yetkili bir rolce çözülür: (a) misafir yeniden doğrulanarak **elle seçilen** açık bir folyoya borç, ya da (b) tahsil edilemedi olarak kapatma. Otomatik başka folyoya aktarım **yoktur**. | T20: tüketim ve borç ayrı; T3: ikisi de aynı işlemde **açıkça** kayda geçer, hiçbiri sessizce kaybolmaz. | T3, T20 |
| Ö7 | **İptalde kullanılan miktarın belirlenmesi.** `hazirlaniyor` siparişin iptal ekranı, siparişin rezerve bileşenlerini (stok kodu, rezerve miktar) listeler; personel **her bileşen için** kullanılan miktarı girer (`0 ≤ kullanılan ≤ rezerve`, boş bırakılamaz, 0 açıkça girilir). Kullanılan kadar `zayi` tüketimi yazılır, kalan rezervasyon serbest bırakılır. `yeni` siparişte giriş istenmez (hepsi serbest). | T19; varsayılan değer koymak otomatik tam zayiyi geri getirir. | T5, T19 |
| Ö8 | **Servis kaydı.** Yeni kavram `bar_servis_kayitlari` (bar, operasyon günü, açılış/kapanış zamanı ve kişisi, durum). Sipariş, oluşturulduğu anda barın **açık** servis kaydına bağlanır; tüketimin operasyon günü **siparişin servis kaydından** gelir, teslim ya da iptal saatinden gelmez. Barda aynı anda en fazla bir açık servis kaydı olur. Kayıt **elle kapatılır**; saat geçti diye kapanmaz. | T16; sistemde böyle bir kavram yok (Z5). Ayrıntılar açık sorulara bağlı (S1–S4). | T6, T16 |
| Ö9 | **Depo takvimi.** Kaynak depo için haftalık kapalı gün(ler) (başlangıç: Pazar) ve tarih bazlı istisnalar (tatil kapanışı / olağan dışı açık gün). Normal talebin teslim tarihi = operasyon gününden sonraki **ilk depo açık günü**. | T17; sistemde depo takvimi yok (Z6). | T17 |
| Ö10 | **Sayım gözlemi ve bekleyen düzeltme.** Sayım onayında bir kalemin fiziksel miktarı o depodaki aktif rezervasyonun altındaysa: sayılan miktar **gözlem olarak kaydedilir**; o kalemin stok düzeltmesi "rezervasyon çelişkisi — bekliyor" olarak işaretlenir ve uygulanmaz; diğer kalemler normal uygulanır. Çelişki, ilgili siparişler teslim/iptal edildiğinde ya da yetkili bir rol kararı verdiğinde çözülür ve bekleyen düzeltme o anki duruma göre yeniden hesaplanıp uygulanır. | T22; sayımı rezervasyon miktarında **reddetmek** gerçek gözlemi kaybettirir. Bu öneri 2026-09-15'te yayınlanan stok sayım akışına dokunur. | T4, T22 |

Revizyon 2'deki **Ö1 (garson siparişi onaylı sayılır) ve Ö6 (folyo kapalıysa iptal + zayi)
kaldırıldı**; T18 ve T20 ile çelişiyordu.

### 1.4 Z — Ölçülen ya da koddan okunan gerçekler

Bu tablo yalnız **gerçeği** ve **nasıl bilindiğini** yazar. Tasarımdaki karşılığı ayrı sütundadır
ve bir tercihtir; türü belirtilir.

| # | Gerçek | Nasıl bilindi | Tasarımdaki karşılığı |
|---|---|---|---|
| Z1 | Bar yetkisi olmayan kullanıcı `stok_rezervasyonlari` satırlarını RLS nedeniyle **göremez**. | **İzole ölçüm** (Aşama 0): aktif rezervasyon 1 iken depo kullanıcısı 0 satır görüyor. | **Seçilen çözüm:** stok çıkış koruması SECURITY DEFINER bir fonksiyonda toplamı okur (bölüm 3.5). Alternatif (depo rollerine rezervasyon okuma izni vermek) seçilmedi: rezervasyon satırları sipariş/oda bilgisine bağlı ve izin genişlemesi RLS sınırını değiştirir. |
| Z2 | Stok takipteki sayım onayı stoğu `stok_ekle` üzerinden **delta** olarak yazar. | **Koddan okundu:** `stok-takip.html` sayım onayı → `saveStok` → `rpc/stok_ekle`. İzole ortamda ölçülmedi. | Stok çıkış koruması `stok_ekle`'ye eklenirse sayım da onun altına girer. Sayımın **nasıl** davranacağı bir **tasarım tercihidir** (Ö10); rezervasyonda durdurmak teknik zorunluluk değildir. |
| Z3 | Bu makinede Deno, Supabase CLI ve Supabase Edge Runtime / GoTrue Docker imajları **yok**; yalnız `postgres:16/17` ve `postgrest/postgrest` imajları var. Node 24 ve Bun kurulu; yerel `strix-sandbox` imajında da Deno yok. Edge Function'lar `Deno.serve`/`Deno.env` kullanır, `supabase-js`'i çalışma anında `esm.sh`'tan içe aktarır, kimliği `/auth/v1/user` (GoTrue) ile doğrular. | **Komutla kontrol** (2026-09-17 ve 2026-09-18): `deno --version`, `supabase --version`, `npm ls -g`, `docker images`, yerel imaj içinde `command -v deno`; kaynak: `docs/kurulum/musteri-projesi/*/index.ts`. | Node/Bun Deno API'lerini çalıştırmaz; uçtan uca test **indirme gerektirir** (bölüm 14.4). **İzin alınmadan hiçbir şey indirilmedi.** |
| Z9 | 2026-09-18'den beri üretimde `stok_ekle`/`stok_transfer` her UPDATE yolunda `guncelleme_tarihi = now()` yazar; `stok-takip` ekranı tarihi yazmadan sonra sunucudan okur. Test tabanı üretim gövdelerini md5 ile doğrular (`scripts/stok-rpc-govde.mjs`). | **Üretim yayını ve duman testi** (runbook §13). | A1 bu fonksiyonları yeniden tanımladığı için düzeltmeyi **taşımak zorundadır** (bölüm 3.5.1). |
| Z4 | Şema dökümü yüklenirken `schema "public" already exists` hatası çıkar ve zararsızdır. | **İzole ölçüm** (Aşama 0 koşu 1) + döküm satır 33 (`CREATE SCHEMA public;`). | Test ortamı yalnız bu satırı tam eşleşmeyle istisna sayar ve sayısını raporlar (E-5 provası ve `dokum-dogrula.mjs` ile aynı kural). |
| Z5 | Sistemde bar için **servis/vardiya kaydı kavramı yok** (yalnız `sayim_oturumlari`). | **Şemadan okundu:** döküm tablo adları taraması. | Ö8 yeni kavram önerir. |
| Z6 | Sistemde **depo takvimi / çalışma günü / tatil** kavramı yok. | **Şema ve kod araması** (tablo adları; `takvim|tatil|kapali_gun` kod taraması yalnız tarih yardımcılarını buldu). | Ö9 yeni kavram önerir. |
| Z7 | Mevcut iç talep onayı, onay anında `stok_transfer` ile talep eden deponun stoğunu artırır. | **Koddan okundu:** `depo-siparis.html:784` civarı. | T11 bu davranışı bar ikmali için yasaklar; Ö5 bar ikmalini ayrı akışa alır. |
| Z8 | `auth_yetki_var` ve `auth_otel_erisim` `kullanicilar.aktif is true` şartı arar (fail-closed). | **Dökümden okundu** + **izole ölçüm** (Aşama 0: pasif kullanıcı `f`). | Ana projedeki RPC'lerde pasif kullanıcı ayrıca ele alınmaz; açık `rapid-handler`'dadır (bölüm 3.7). |

### 1.5 S — Açık sorular (cevap bekliyor)

| # | Soru | Neyi belirler |
|---|---|---|
| S1 | Servis kaydını **kim** açar ve kapatır (kaptan, bar personeli, otomatik ilk siparişte açılış)? | Ö8 yetkileri, kaptan ekranı |
| S2 | Barda **açık servis kaydı yokken** sipariş gelirse ne olur: reddedilir mi, otomatik mi açılır? | QR siparişinin davranışı; misafir deneyimi |
| S3 | Servis kaydı kapatılırken **açık sipariş** varsa: kapanış engellenir mi, siparişler o kayıtta mı kalır? | Operasyon günü ataması |
| S4 | Servis kaydı **kapatılmayı unutulursa** (ertesi gün hâlâ açık) ne olur: uyarı mı, yetkili kapatması mı? Saat kesimi olmayacağı kesin (T16). | Yanlış güne yazılan tüketim riski |
| S5 | `hazir` durumundaki sipariş iptal edilirse de kullanılan miktar belirlenir mi, yoksa tamamı tüketilmiş mi sayılır? (T19 yalnız "hazırlanıyor"u açıkça söylüyor.) | Ö7 kapsamı |
| S6 | Borç istisnasını (Ö6) **kim** çözer ve (a) seçeneğinde misafir yeniden doğrulaması nasıl kayda geçer? | İstisna yetkisi, ön büro/muhasebe rolü |
| S7 | Depo takviminin tatil ve istisna günlerini **kim** girer; takvim kaynak depo başına mı, otel başına mı? | Ö9 yetkisi ve kapsamı |
| S8 | Cumartesi operasyonunun normal talebi (Pazar kapalı → Pazartesi teslim) için ayrıca bir ilave gerekir mi, yoksa pazar ilavesi yalnız Cuma operasyonunda mı kalır? (T10 yalnız Cuma'yı söylüyor.) | Aşama 3 kapsamı |
| S9 | Sayım çelişkisini (Ö10) **kim** çözer ve bekleyen düzeltme ne kadar bekleyebilir? | Ö10 yetkisi |
| S10 | Edge Function uçtan uca testi için hangi izole seçenek denensin ve gerekli indirmelere izin var mı? (bölüm 5) | T21 test açığının kapanıp kapanmayacağı |

---

## 2. Temel ilkeler

1. **Karar sunucuda verilir.** Oda doğrulaması, fiyat, stok yeterliliği, otel/depo eşleşmesi,
   kullanıcı aktifliği ve durum geçişleri RPC içinde kontrol edilir. İstemci kontrolü yalnız
   kullanıcı deneyimidir.
2. **Fiziksel gerçek ile para ayrı kayıtlardır ama birlikte ve açıkça yazılır.** Stok tüketimi
   olduysa kayda geçer; borç yazılamıyorsa bu da aynı işlemde **istisna** olarak kayda geçer.
   Hiçbiri sessizce düşmez, hiçbiri kendiliğinden başka bir kayda dönüşmez.
3. **Her yazma tekrar çağrıya dayanıklıdır.** Aynı teslim, doğrulama, kabul ya da sevk iki kez
   işlenmez.
4. **Talep, stok değildir.** İkmal talebi oluşturmak, düzenlemek, onaylamak stok miktarını
   değiştirmez. Stok yalnız **sevkte** (merkezden çıkar) ve **kabulde** (bara girer) değişir.
5. **Gözlem kaybolmaz.** Sayılan, kullanılan ya da servis edilen miktar sistemin beklentisiyle
   çelişse bile kaydedilir; çelişki ayrıca çözülür.
6. **Operasyon günü takvimden değil servisten gelir.** Saat kesimi yoktur.

---

## 3. Aşama 1 — Bar ve PMS güvenliği (tüm barlar — Ö2)

### 3.1 Onaylanan fiyat siparişe kaydedilir (T2)

- `bar_siparis_kalemleri`'ne eklenir: `birim_fiyat numeric(12,2) not null`, `ucretli boolean not null`.
- İstemci her ücretli kalem için **gördüğü fiyatı** yollar: `{menu_urun_id, adet, gosterilen_fiyat}`.
- `bar_siparis_olustur` ürünün **o anki** ana fiyatını okur. Ücretli kalemde
  `gosterilen_fiyat ≠ fiyat` ise sipariş reddedilir: `FIYAT_DEGISTI`. Eşleşirse fiyat ve
  `ucretli` bayrağı kaleme **anlık görüntü** olarak yazılır.
- Borç tutarı **yalnız anlık görüntüden** hesaplanır: `SUM(adet × birim_fiyat) WHERE ucretli`.
- Geçiş: mevcut kalemlerde `birim_fiyat` = ürünün şu anki fiyatı (tarihsel fiyat bilinmez;
  geçiş raporunda sayılır).

### 3.2 Ücretli sipariş: sunucu doğrulaması ve açık personel beyanı (T1, T18; V1, Ö1)

**Yeni sütunlar (`bar_siparisleri`):**

| Sütun | Anlam |
|---|---|
| `kanal` | `qr` \| `personel` \| `gecis` |
| `oda_dogrulama_durumu` | `gerekmiyor` \| `bekliyor` \| `dogrulandi` \| `reddedildi` \| `gecis` |
| `rezervasyon_id`, `folio_id` | Doğrulamada çözülen konaklama ve folyo |
| `dogrulayan`, `dogrulama_zamani`, `dogrulama_beyani` | Beyanı veren personel (auth uid), zaman, beyan metni |

**Kurallar:**
- Sepette ücretli kalem varsa `oda_no` **sunucuda zorunludur** (`ODA_NO_GEREKLI`).
- Oluşturma anında oda için **güncel konaklama** aranır (aktif oda ataması + rezervasyon
  `giris_yapildi` + `acik` folyo). Bulunamazsa `KONAKLAMA_YOK`.
- **Her iki kanalda** ücretli sipariş `oda_dogrulama_durumu = 'bekliyor'` başlar. Garsonun
  siparişi girmesi durumu değiştirmez (T18).
- `bar_siparis_oda_dogrula(siparis_id, beyan boolean)` — `bar_siparis_yonetimi:kayit`, otel
  erişimi, aktif kullanıcı; `beyan` `true` değilse `DOGRULAMA_BEYANI_GEREKLI`. Konaklamayı
  **yeniden** çözer; bulunamazsa `KONAKLAMA_YOK`. Başarılıysa folyoyu bağlar ve doğrulayanı,
  zamanı, beyan metnini yazar. Tekrar çağrı: `zaten_dogrulandi`.
- `bar_siparis_oda_reddet(siparis_id, neden)` — yalnız `bekliyor` iken; sipariş iptal olur
  (iptal kuralları 3.6).
- `hazirlaniyor`'a geçiş, doğrulama `bekliyor` iken reddedilir (`ODA_DOGRULAMASI_BEKLIYOR`).
- Ücretsiz siparişler (`gerekmiyor`) bugünkü gibi akar.
- Geçiş: açık ve ücretli kalemi olan eski siparişler `bekliyor`; kapanmış siparişler `gecis`.

### 3.3 Teslim: stok, borç ve istisna tek işlem, tekrar çağrıda tekil (T3, T20; Ö6)

`bar_siparis_teslim_et(siparis_id, fiziksel_servis_beyani boolean default false)`:
1. Siparişi `SELECT … FOR UPDATE` ile kilitler.
2. Durum zaten `teslim_edildi` ise **hiçbir şey yazmadan** `{sonuc:'zaten_teslim'}` döner.
3. Yalnız `hazir`'dan teslim edilir (`GECERSIZ_DURUM`); ücretli kalem varsa doğrulama
   `dogrulandi` şart (`ODA_DOGRULAMASI_BEKLIYOR`).
4. Ücretli sipariş ve bağlı folyo **hâlâ açık ve konaklama sürüyor** mu kontrol edilir.
   - **Evet:** devam.
   - **Hayır ve `fiziksel_servis_beyani = false`:** `FOLYO_KAPALI` — hiçbir şey yazılmaz.
   - **Hayır ve `fiziksel_servis_beyani = true`:** devam, ama borç yerine istisna (6. adım).
5. Her aktif rezervasyon kilit altında tüketilir: stok ≥ miktar değilse `STOK_TUTARSIZ`
   (**sessiz 0'a kırpma yok**); rezervasyon `kullanildi`; stok düşer; `bar_stok_tuketimleri`'ne
   `tur='satis'` satırı; `stok_hareketleri`'ne `cikis`.
6. Durum `teslim_edildi`. Borç tutarı > 0 ise:
   - folyo açıksa `pms_folio_hareketleri`'ne borç (`kaynak_tip='bar'`, `kaynak_id=sipariş`);
   - folyo kapalıysa ve beyan verildiyse `bar_borc_istisnalari`'na kayıt; **borç yazılmaz,
     başka folyo aranmaz**.
7. Herhangi bir adım hata verirse 1–6 birlikte geri alınır.
8. Tekillik kısıtlarla da korunur: `bar_stok_tuketimleri(rezervasyon_id)`,
   `pms_folio_hareketleri(kaynak_tip, kaynak_id, ters_kayit)` (mevcut),
   `bar_borc_istisnalari(siparis_id)`.

**`bar_stok_tuketimleri`** (Aşama 2'nin kaynağı): `id, otel_id, bar_depo_id, siparis_id,
siparis_kalem_id, rezervasyon_id (tekil), stok_kodu, miktar, tur ('satis'|'zayi'), zaman,
personel`. **Operasyon günü bu aşamada yazılmaz**; Aşama 2'de siparişin servis kaydından türetilir.

**`bar_borc_istisnalari`**: `id, otel_id, siparis_id (tekil), oda_no, tutar, eski_folio_id,
eski_rezervasyon_id, beyan_veren, beyan_zamani, durum ('acik'|'folyoya_yazildi'|'tahsil_edilemedi'),
cozen, cozum_zamani, hedef_folio_id, cozum_notu`. Çözüm akışının yetkisi ve ekranı S6'ya bağlıdır;
Aşama 1'de yalnız kayıt açılır ve listelenir.

### 3.4 Rezervasyon yarışı (T4)

- Stok anahtarı başına işlem ölçekli danışma kilidi:
  `pg_advisory_xact_lock(hashtextextended('stok:' || depo_kodu || ':' || stok_kodu, 0))`.
- Sipariş, gereken tüm anahtarları **önce hesaplar, sıralar, sonra sırayla kilitler**, ardından
  yeterliliği kontrol edip rezerve eder.
- Aynı kilit teslim, iptal tüketimi ve **tüm stok çıkışlarında** (3.5) alınır.
- Kanıt: izole ortamda iki eşzamanlı işlem aynı son birimleri ister → yalnız biri geçer;
  kilit kaldırılmış **negatif kontrolde** ikisi de geçer.

### 3.5 Diğer stok çıkışlarıyla çakışma (T4; Z1, Z2; Ö10)

**Gerçek (Z1):** bar yetkisi olmayan kullanıcı rezervasyonları göremez.
**Seçilen çözüm:** koruma tek bir SECURITY DEFINER fonksiyondadır:
`stok_cikis_korumasi(depo, stok_kodu, cikis)`. `stok_ekle` (negatif delta) ve `stok_transfer`
(kaynak bacağı) çıkıştan önce onu çağırır.
- Aynı danışma kilidini alır.
- Aktif rezervasyon > 0 ve çıkış sonrası miktar < aktif rezervasyon ise `REZERVE_STOK`.
- Rezervasyon varken çağıranın o otele erişimi yoksa `OTEL_ERISIMI_YOK` (fonksiyon başka otelin
  rezervasyon miktarını açığa çıkarmasın).
- Aktif rezervasyon **yoksa davranış bugünküyle aynıdır**.
- Teslim ve iptal tüketimi kendi rezervasyonunu önce `kullanildi` yapar; korumaya takılmaz.

**Sayım (Z2 — gerçek; Ö10 — tercih):** sayım onayı da `stok_ekle`'den geçtiği için korumanın
sayımda **nasıl** davranacağı ayrıca tasarlanmalıdır. Rezervasyon miktarında **reddetmek bir
tercihtir** ve gerçek gözlemi kaybettirir (T22'ye aykırı). Önerilen davranış Ö10'dur: gözlem
kaydedilir, çelişkili kalemin düzeltmesi bekletilir. Bu, 2026-09-15'te yayınlanan stok sayım
akışına dokunur; sayım yolunun `stok_ekle` yerine ayrı bir RPC'ye alınmasını gerektirir. Ö10
kesinleşmeden Aşama 1'in stok koruması yayınlanmamalıdır (aksi halde bar depolarında sayım
fiilen reddedilir).

#### 3.5.1 Stok tarih düzeltmesinin korunması (Z9) — gereksinim

A1 `stok_ekle` ve `stok_transfer`'i yeniden tanımlar; Ö10 seçilirse sayım için yeni bir stok
yazma RPC'si de ekler. Son uygulanan gövde kazandığı için bu gereksinimler kesindir:

1. **Her stok yazma yolu tarihi yazar.** Yeniden tanımlanan `stok_ekle` (insert-on-conflict
   yolu), `stok_transfer` (kaynak ve hedef bacağı) ve A1'in eklediği her yeni stok yazma
   fonksiyonu (sayım, teslim tüketimi, iptal zayisi) güncellediği satırda `guncelleme_tarihi = now()`
   yazar. Rezervasyon **stok satırını değiştirmediği** için tarihi değiştirmez.
2. **Ön koşul, gövdeyi ölçerek korur.** A1 migration'ı yeniden tanımladığı her fonksiyonun
   mevcut gövdesinde `guncelleme_tarihi` bulunduğunu doğrular; bulunmazsa (tarih düzeltmesi
   geri alınmış ya da henüz uygulanmamışsa) hiçbir şey değiştirmeden durur.
3. **Geri alma, A1'e ait olmayanı geri almaz.** A1 geri alma dosyası eski gövdeleri yazmadan
   önce tarih düzeltmesinin canlı olup olmadığını ölçer; canlıysa eski gövdelerin üzerine yeniden
   uygular. Kaynak tek yerdir: `docs/kurulum/2026-09-17-stok-guncelleme-tarihi.sql`.
4. **Ekran kuralı sürer.** A1'in değiştirdiği ekranlar (sayım akışı dahil) stok satırının tarihini
   yerel saatle doldurmaz; yazma sonrası sunucudan okur, okuyamazsa "bilinmiyor" gösterir.
5. **Kanıt gerçek dosyayla.** Sıra testi (tarih migration'ı → A1) ve geri alma testi, plan
   metninden alıntıyı değil **gerçek A1 migration dosyasını** ve **gerçek geri alma dosyasını**
   çalıştırır; tarih güncellemesi, rezervasyon koruması ve geri almada tarihin korunması birlikte
   ve negatif kontrolle kanıtlanır.

### 3.6 İptal (T5, T19; Ö7, S5)

`bar_siparis_iptal(siparis_id, neden, kullanilanlar jsonb default null)` — `neden` zorunlu:
- `yeni` → tüm rezervasyonlar `serbest`; `kullanilanlar` verilirse reddedilir.
- `hazirlaniyor` → `kullanilanlar` **zorunlu**: `[{rezervasyon_id, kullanilan_miktar}]`, siparişin
  **her** aktif rezervasyonu için bir satır, `0 ≤ kullanilan ≤ rezerve`
  (`KULLANILAN_MIKTAR_GEREKLI`, `KULLANILAN_MIKTAR_GECERSIZ`). Kullanılan kadar `zayi` tüketimi
  yazılır ve stok düşer; kalan miktar serbest bırakılır. Tam tüketim **otomatik değildir**.
- `hazir` → S5 cevabına bağlı.
- `teslim_edildi` / `iptal` → değiştirilemez.
- Tekrar çağrı: zaten `iptal` ise `{sonuc:'zaten_iptal'}`.
- Bir rezervasyonun kısmen tüketilmesi için rezervasyon satırı kullanılan ve serbest kısımlara
  **bölünür** (tüketim kaydının `rezervasyon_id` tekilliği korunur).

### 3.7 Otel izolasyonu ve pasif kullanıcı (T4; Z8)

- **Depo ↔ otel:** `bar_siparis_olustur` her iki çağrı yolunda `p_depo_id` önekinin `p_otel_id`
  olduğunu doğrular (`DEPO_OTEL_UYUSMAZ`). ERP'de depo ana tablosu yok; önek sözleşmesi tek kaynak.
- Tüm durum/doğrulama/teslim/iptal RPC'leri siparişin oteline erişim ister; yetki fonksiyonları
  pasif kullanıcıyı zaten reddeder (Z8).
- **`rapid-handler` (masa/QR):** bugün kullanıcıyı e-postadan buluyor, `aktif`'e bakmıyor, otel
  kapsamı yok. Hedef davranış: kimlik `auth.getUser()`; yetkili mi ve hangi oteller sorusu
  **çağıranın JWT'siyle** bir veritabanı fonksiyonunda (`bar_masa_yetki_kapsami()`) cevaplanır;
  `liste` yalnız erişilebilen otellerin masalarını döner, `ekle`/`durum` başka otel için
  reddedilir, `ekle`'de depo öneki otelle eşleşmelidir.
- **Test ayrımı (T21):** `bar_masa_yetki_kapsami()` veritabanında izole test edilebilir. Bu,
  `rapid-handler`'ın **uçtan uca** testi **değildir**: HTTP gövdesi, `auth.getUser()` çağrısı,
  müşteri projesine yazma ve hata yanıtları sınanmamış olur. Bölüm 5.

### 3.8 Ekran değişiklikleri (yalnız gerekli olan)

| Ekran | Değişiklik |
|---|---|
| `bar-menu.html` (müşteri) | Ücretli kalemle `gosterilen_fiyat`; `FIYAT_DEGISTI`'de menüyü yeniler; ücretli siparişte "personel oda kartınızı kontrol edecek" bilgisi. |
| `bar-garson.html` | `gosterilen_fiyat`; ücretli sipariş gönderildikten sonra **ayrı** "Oda kartını/kimliği kontrol ettim" onay adımı (Ö1). |
| `bar-siparis-kuyrugu.html` | "Oda doğrulaması bekliyor" rozeti + **Doğrula (beyanla) / Reddet**; `hazirlaniyor` iptalinde bileşen bazında kullanılan miktar formu; `FOLYO_KAPALI`'da "ürün servis edildi mi?" açık beyanıyla istisnalı teslim; hata kodlarının Türkçe karşılığı. |
| Borç istisnaları listesi | Aşama 1'de salt görüntüleme; çözüm ekranı S6'ya bağlı. |

---

## 4. Aşama 2 — Servis kaydı ve gün sonu ikmal taslağı (pilot bar)

### 4.1 Servis kaydı ve operasyon günü (T16; Ö8; S1–S4)

- `bar_servis_kayitlari`: `id, otel_id, bar_depo_id, operasyon_gunu date, durum ('acik'|'kapali'),
  acan, acilis_zamani, kapatan, kapanis_zamani`. Barda aynı anda en fazla bir `acik` kayıt
  (kısmi tekil indeks).
- `operasyon_gunu` kayıt **açılırken** belirlenir (açan kişinin seçtiği/onayladığı gün); saat
  kesimiyle hesaplanmaz.
- `bar_siparisleri.servis_kaydi_id`: sipariş oluşturulurken barın açık kaydına bağlanır.
  Açık kayıt yokken davranış S2'ye bağlıdır.
- Tüketimin operasyon günü = `bar_stok_tuketimleri → bar_siparisleri → bar_servis_kayitlari.operasyon_gunu`.
  Cumartesi 07:00'de teslim edilen Cuma servisi siparişi **Cuma**'ya yazılır.
- Kapatma elle yapılır; açık sipariş ve unutulan kayıt davranışı S3, S4'e bağlıdır.
- Aşama 1 döneminde oluşan (servis kaydı olmayan) siparişler ikmal taslağına girmez; pilot bar
  Aşama 2 yayınından sonra temiz başlar.

### 4.2 Depo takvimi ve teslim tarihi (T17; Ö9; S7)

- `depo_takvimi_haftalik`: `kaynak_depo_id, isodow, acik boolean` (başlangıç: Pazar kapalı).
- `depo_takvimi_istisnalari`: `kaynak_depo_id, tarih, acik boolean, aciklama`.
- `depo_acik_mi(depo, tarih)` ve `sonraki_acik_gun(depo, tarih)` (istisna haftalık kuralı ezer).
- Normal talebin `teslim_tarihi = sonraki_acik_gun(kaynak_depo, operasyon_gunu + 1)`.
  Örnek: Cuma → Cumartesi; Cumartesi → (Pazar kapalı) → Pazartesi.

### 4.3 Kaptan, atama ve pilot

- `bar_ayarlari`: `bar_depo_id (pk), otel_id, ikmal_pilot boolean default false, kaynak_depo_id`.
- `bar_kaptan_atamalari`: `kullanici_id, bar_depo_id, otel_id, aktif`. Rol modeli V2'ye bağlı.
- Modüller: `bar_ikmal` (kaptan), `bar_ikmal_depo` (depo).

### 4.4 Tablolar

**`bar_ikmal_talepleri`**: `id, otel_id, bar_depo_id, kaynak_depo_id, operasyon_gunu,
tur ('normal'|'pazar_ilavesi'), teslim_tarihi, durum, olusturan, gonderen, gonderme_zamani,
onaylayan, onay_zamani, iptal_nedeni`. **Tekil:** `(bar_depo_id, operasyon_gunu, tur)`.

**`bar_ikmal_kalemleri`**: `id, talep_id, stok_kodu, urun_adi, birim, onerilen_miktar (tüketimden;
kaptan değiştiremez), talep_miktar, kaynak ('tuketim'|'elle'), elle_degisti, onaylanan_miktar`.
**Tekil:** `(talep_id, stok_kodu)`.

**Durum makinesi:** `taslak → gonderildi → onaylandi → kismi_sevk → sevk_edildi → kapandi`;
`taslak`/`gonderildi` iken `iptal`. Kaptan yalnız `taslak`'ı düzenler.

### 4.5 Taslak üretimi (T6, T8, T9; Ö4)

`bar_ikmal_taslak_uret(bar_depo_id, operasyon_gunu)`:
- Kaynak: o bar ve operasyon gününe ait servis kayıtlarındaki siparişlerin `tur='satis'`
  tüketimleri; `stok_kodu` başına toplanır.
- Yeniden üretim `onerilen_miktar`'ı günceller; kaptanın değiştirdiği ve elle eklediği kalemlere
  dokunmaz; `taslak` dışındaki talebe dokunmaz (`TALEP_KILITLI`).
- Zayi taslağa girmez (Ö4).
- **Günlük sayım ve ücretsiz servis girişi ön koşul değildir** (T8).

### 4.6 Kaptan işlemleri (T7, T9)

`bar_ikmal_kalem_guncelle`, `bar_ikmal_kalem_ekle`, `bar_ikmal_kalem_sil` (yalnız elle eklenen),
`bar_ikmal_gonder`. **Hiçbiri stok ya da stok hareketi yazmaz**; test satır sayılarıyla kanıtlar.

---

## 5. Edge Function uçtan uca testi — araştırma ve açık test açığı (T21; Z3; S10)

### 5.1 Neyin sınanması gerekiyor

| Edge Function (canlı ad) | Uçtan uca doğrulanacaklar |
|---|---|
| `hyper-api` (QR sipariş) | Token çözümü, 20 kalem / 30 adet sınırı, ana projede RPC çağrısı, `siparis_arsiv` kaydı, yeni hata kodlarının müşteriye dönüşü, ücretli siparişin `bekliyor` başlaması |
| `rapid-handler` (masa/QR) | `auth.getUser()` ile kimlik, pasif kullanıcı reddi, 810/811 otel kapsamı (`liste`/`ekle`/`durum`), depo-otel önek kontrolü, müşteri projesine yazma, HTTP durum kodları |
| `smooth-service` (menü yayını) | `x-staff-token` doğrulaması, yetkisiz 401/403, yetkili yayında `menu_yenile` |

Veritabanı fonksiyonu testleri (ör. `bar_masa_yetki_kapsami`) bu listenin yalnız **yetki
kararı** kısmını kapsar; HTTP katmanı, kimlik doğrulama çağrısı, iki proje arasındaki köprü ve
yanıt biçimi kapsam dışıdır.

**A1'in Edge Function etkisi (koddan okundu, 2026-09-18):**

| Fonksiyon | A1'de kodu değişir mi | Davranışı değişir mi | Neden |
|---|---|---|---|
| `rapid-handler` (`masa-yonetim/index.ts`) | **Evet** | Evet | Kimlik `auth.getUser()`, pasif kullanıcı reddi, otel kapsamı (3.7). |
| `hyper-api` (`siparis-gonder/index.ts`) | Hayır | **Evet** | Kalemleri olduğu gibi `bar_siparis_olustur`'a iletir ve hata mesajını müşteriye döndürür. A1 bu RPC'ye fiyat kontrolü, oda zorunluluğu ve `bekliyor` başlangıcını ekler; canlı QR sipariş yolu doğrudan etkilenir. |
| `smooth-service` (`menu-yayinla/index.ts`) | Hayır | Hayır (A1 menü yayınına dokunmaz) | Regresyon olarak bir kez koşulur. |

### 5.2 Araştırılan izole seçenekler

Hiçbiri **çalıştırılmadı**. Hepsi indirme gerektirir (Z3); boyutlar indirmeden ölçülmedi.

| # | Seçenek | Gerekenler | Kapsadığı | Sınırı |
|---|---|---|---|---|
| E1 | **Supabase CLI yerel yığını** (`supabase start` + `supabase functions serve`) | CLI kurulumu + yığının Docker imajları (Postgres, GoTrue, PostgREST, Kong, Edge Runtime) | Üretime en yakın çalışma zamanı; `auth.getUser()` gerçek GoTrue'ya gider | İki proje (ana + müşteri) için iki ayrı yerel yığın ya da tek yığında iki şema düzeni gerekir; en ağır seçenek |
| E2 | **Edge Runtime imajı + ayrı GoTrue ve PostgREST konteynerleri** | `supabase/edge-runtime` ve `supabase/gotrue` imajları (PostgREST imajı zaten var) | Supabase'in kendi çalışma zamanı; ortam değişkenleri elle bağlanır | Kong/ağ geçidi yok, yollar elle eşlenir; JWT sırrının GoTrue ve PostgREST'te aynı olması gerekir |
| E3 | **Deno imajı** ile `index.ts`'i çalıştırma + GoTrue ve PostgREST | `denoland/deno` + `supabase/gotrue` imajları | Fonksiyon kodu ve HTTP davranışı | Supabase Edge Runtime değil (davranış farkı olabilir); içe aktarmalar `esm.sh`'tan çalışma anında ağ ister |
| E4 | **Ayrı bir Supabase staging projesi** (bulut) | Kullanıcının oluşturacağı proje, dağıtım | Gerçek platform davranışı | Yerel/izole değil; proje oluşturma kullanıcı işidir |

Ortak not: `auth.getUser()` bir GoTrue ister; GoTrue yerine taklit (stub) kullanmak kimlik
katmanını sınamamış olur ve uçtan uca sayılmaz.

### 5.3 Durum

**Test açığı AÇIK.** Seçenek seçilip (S10) gerekli indirmelere izin verilene kadar her aşama
raporunda şu satır zorunludur: "Edge Function uçtan uca testi yapılmadı; yalnız veritabanı yetki
kararı izole test edildi." Yayın sırasında Edge Function değişiklikleri yalnız canlı duman
testiyle doğrulanmış olur ve bu da raporda ayrıca yazılır.

> **Revizyon 4 kuralı:** Test açığını belgeye yazmak o bileşeni **yayına hazır yapmaz.** Kodu
> değişen (`rapid-handler`) ya da davranışı değişen (`hyper-api`) bir Edge Function, uçtan uca
> testi izole ortamda geçmeden A1 yayınına **girmez**. `bar_siparis_olustur` değişikliği
> `hyper-api`'nin davranışını değiştirdiği için bu kural A1'in veritabanı değişikliğini de
> kapsar. Yöntem ve indirme kararı: bölüm 14.4.

---

## 6. Aşama 3 — Cuma istisnası: pazar ilavesi (pilot bar) (T10; Ö3; S8)

- Operasyon günü (servis kaydından) **Cuma** olan bar için ikinci talep açılabilir:
  `tur = 'pazar_ilavesi'`. Başka günlerde `PAZAR_ILAVESI_YALNIZ_CUMA`.
- Teslim tarihi: Cuma operasyonunun normal talebi ve pazar ilavesi **aynı teslim tarihine**
  bağlıdır (`sonraki_acik_gun`; Cumartesi açıksa Cumartesi).
- Giriş penceresi **teslim tarihine** bağlıdır (Ö3): o teslim tarihi geçmediği sürece girilebilir.
  Servis kaydı saat kesimiyle bölünmediği için Cuma servisi gece yarısını ya da 06:00'ı geçse de
  aynı operasyon gününde kalır.
- Pazar ilavesinin tüketim kaynağı yoktur; kalemleri elle girilir.
- **Ayrı saklanır:** ayrı talep satırı, ayrı kalemler, ayrı onay/sevk/kabul.

---

## 7. Aşama 4 — Teslim kabulü (pilot bar) (T11; V3; Ö5)

### 7.1 Aşamalar ve stok etkisi

| Aşama | Kim | RPC | Stok |
|---|---|---|---|
| Onay | Depo | `bar_ikmal_onayla(talep_id, [{kalem_id, onaylanan_miktar}])` | **Değişmez** |
| Sevk | Depo | `bar_ikmal_sevk_et(talep_id, [{kalem_id, sevk_miktar}])` | Merkez depodan **düşer** |
| Kabul | Kaptan | `bar_ikmal_kabul_et(sevk_id, [{sevk_kalem_id, kabul_miktar}])` | Bar stoğuna **yalnız kabul edilen** girer |
| Fark kapatma | Depo | `bar_ikmal_fark_kapat(sevk_kalem_id, 'geri_al'\|'kayip', not)` | V3'e bağlı: `geri_al` merkeze geri girer · `kayip` değişmez, kayıt |

### 7.2 Tablolar

**`bar_ikmal_sevkleri`**: `id, talep_id, otel_id, sevk_no, durum ('yolda'|'kabul_edildi'),
sevk_eden, sevk_zamani, kabul_eden, kabul_zamani`.

**`bar_ikmal_sevk_kalemleri`**: `id, sevk_id, talep_kalem_id, stok_kodu, sevk_miktar (>0),
kabul_miktar (null → bekliyor; 0 ≤ kabul ≤ sevk), fark_durumu ('yok'|'acik'|'geri_alindi'|'kayip'),
fark_kapatan, fark_zamani, fark_notu`.

### 7.3 Kurallar

- **Kısmi teslimat:** bir talebe birden çok sevk; kalem başına `Σ sevk ≤ onaylanan`
  (`SEVK_ONAYI_ASIYOR`). Talep durumu toplamlardan türetilir.
- **Sevk** kaynak depodan kilit altında ve katı düşer (`STOK_YETERSIZ`, 0'a kırpma yok).
  "Yolda" miktar hiçbir `stok` satırında durmaz.
- **Kabul** sevk başına bir kez (`ZATEN_KABUL`); bar stoğu yalnız kabul kadar artar;
  `sevk > kabul` → açık fark.
- Her stok değişimi `stok_hareketleri`'ne yazılır; belge no = sevk no.
- Talep ve sevk satırları `FOR UPDATE` ile kilitlenir; durum geçişleri tek yönlüdür.

### 7.4 Ekranlar

- `bar-ikmal.html` (kaptan): servis kaydı aç/kapat (S1), taslak üret/düzenle/gönder, Cuma'da
  pazar ilavesi, yoldaki sevkler ve kabul.
- `bar-ikmal-depo.html` (depo): gelen talepler (normal / pazar ilavesi ayrı), onay, sevk, kısmi
  teslimat görünümü, açık farklar, depo takvimi (S7).

---

## 8. Güvenlik özeti (yeni nesneler)

- Tüm yeni tablolar: RLS açık; `anon` erişimi yok; okuma
  `auth_yetki_var(modül,'goruntule') AND auth_otel_erisim(otel_id)`; **doğrudan yazma yok** —
  yazmalar SECURITY DEFINER RPC'lerle, fonksiyon içinde yetki + otel + (gerekiyorsa) atama kontrolü.
- Her yeni fonksiyon: `revoke all … from public, anon`; dışa açıklar `grant execute … to
  authenticated, service_role`; iç fonksiyonlar `authenticated` ve `service_role`'dan da revoke;
  `set search_path = pg_catalog, public, pg_temp`.
- Hata metinleri sabit kod önekiyle başlar (`KOD: açıklama`); ekran önekle çevirir.
- Bir tabloda iki permissive politika varsa otel şartı **ikisine birden** yazılır (pentest-4 dersi).

## 9. Hata kodları (taslak — açık sorulara göre değişebilir)

Aşama 1: `ODA_NO_GEREKLI`, `KONAKLAMA_YOK`, `FIYAT_DEGISTI`, `DEPO_OTEL_UYUSMAZ`,
`ODA_DOGRULAMASI_BEKLIYOR`, `DOGRULAMA_BEYANI_GEREKLI`, `FOLYO_KAPALI`, `GECERSIZ_DURUM`,
`STOK_TUTARSIZ`, `REZERVE_STOK`, `STOK_YETERSIZ`, `IPTAL_NEDENI_GEREKLI`,
`KULLANILAN_MIKTAR_GEREKLI`, `KULLANILAN_MIKTAR_GECERSIZ`, `MENU_URUNU_YOK`, `BOS_SIPARIS`,
`OTEL_GECERSIZ`, `SIPARIS_YOK`, `YETKI_YOK`, `OTEL_ERISIMI_YOK`.
Aşama 2–4: `SERVIS_KAYDI_YOK`, `SERVIS_KAYDI_ACIK`, `TALEP_KILITLI`, `PILOT_KAPALI`,
`KAPTAN_ATAMASI_YOK`, `PAZAR_ILAVESI_YALNIZ_CUMA`, `PAZAR_ILAVESI_SURESI_DOLDU`,
`SEVK_ONAYI_ASIYOR`, `ZATEN_KABUL`, `FARK_KAPALI`.

## 10. Test stratejisi

- **Taban (Aşama 0, tamamlandı — 8 OK / 0 FAIL):** rapor `docs/superpowers/reports/2026-09-17-bar-asama0-rapor.md`.
- **Önce ölçümü:** her aşama, düzelttiği kusuru önce mevcut üretim koduna karşı ölçer.
- **Negatif kontroller:** kritik korumalar (kilit, rezerve koruması, tekillik) kaldırıldığında
  testin düştüğü gösterilir.
- **Eşzamanlılık:** iki ayrı bağlantıda açık işlemlerle gerçek yarış.
- **Test açıkları her raporda ayrı başlıktır:** Edge Function uçtan uca (bölüm 5), gerçek
  PostgREST üzerinden HTTP akışı, üretim verisiyle geçiş.
- **Stok tarih düzeltmesi (3.5.1):** sıra testi ve geri alma testi gerçek A1 migration ve geri alma
  dosyalarını çalıştırır; test tabanı 2026-09-18 sonrası üretim gövdeleriyle (tarih düzeltmeli)
  kurulur ve gövdeler md5 ile doğrulanır.

| Aşama | Asgari senaryolar |
|---|---|
| 1 | önce: oda no'suz ücretli sipariş; rezerve stoğun başka çıkışla tüketilmesi · oda no'suz ücretli ret · konaklamasız oda ret · **garson ücretli siparişi `bekliyor` başlar** · beyansız doğrulama ret · beyanlı doğrulama: folyo bağlanır, doğrulayan/zaman/beyan kaydı · doğrulama beklerken hazırlık ret · fiyat değişti ret · anlık fiyat borca · teslim iki kez → tek tüketim + tek borç · **folyo kapalı + beyansız teslim → hiçbir şey yazılmaz** · **folyo kapalı + fiziksel servis beyanı → satış tüketimi + istisna kaydı, borç yok, başka folyoya yazılmadı** · **hazırlanıyor iptali: kullanılan miktar girilmeden ret; kısmi kullanım → kısmi zayi + kalan serbest; tam tüketim otomatik değil** · yeni iptal → serbest · eşzamanlı son birim → tek başarı (+ kilitsiz negatif kontrol) · bar yetkisi olmayan kullanıcının çıkışı rezerve stoğa inemez (+ korumasız negatif kontrol) · rezervasyonsuz depoda davranış değişmedi · **sayım: rezervasyon altı gözlem kaydedilir, düzeltme bekletilir, diğer kalemler uygulanır** (Ö10 kabul edilirse) · depo-otel uyuşmazlığı ret · başka otelin siparişi ret · pasif kullanıcı ret · `bar_masa_yetki_kapsami` kapsamı (**yetki kararı testi; uçtan uca değil**) · anon/iç fonksiyon erişimi kapalı |
| 2 | servis kaydı: aynı barda ikinci açık kayıt ret · **Cuma açılan kayıttaki sipariş Cumartesi 07:00'de teslim edilse Cuma'ya yazılır** · kayıt yokken sipariş (S2'ye göre) · taslak yalnız satış tüketimi · yeniden üretim elle değişikliği korur · kaptan düzenlemeleri stok ve stok hareketi yazmaz · teslim tarihi depo takviminden (Cumartesi → Pazartesi) · istisna günü haftalık kuralı ezer · gönderilen talep kilitli · başka barın kaptanı ve pilot kapalı bar ret |
| 3 | Cuma servisi gece yarısı ve 06:00'ı geçer, pazar ilavesi aynı operasyon gününe bağlanır · pazar ilavesi teslim tarihi geçmeden girilebilir, geçince ret · Cuma dışı ret · normal ve ilave ayrı satır, aynı teslim tarihi |
| 4 | onay stok değiştirmez · sevk kaynaktan düşer, bar değişmez · kabul yalnız kabul edileni ekler · kısmi sevk + kısmi kabul izlenir · onayı aşan sevk ret · kabul iki kez ret; eşzamanlı çift kabul tek sonuç (+ kilitsiz negatif kontrol) · fark kapatma · kaynak yetersiz → ret, 0'a kırpma yok · diğer departmanların iç talep akışı değişmedi (regresyon) |

## 11. Kapsam dışı

- Mevcut bar modülünün yeniden kurulması; müşteri projesinin şeması.
- `bar-masa-yonetimi.html` olası XSS (bulgu 8), `menu.alibeyclub.com`, hız sınırı, rezervasyon zaman
  aşımı, kuyruk ekranının sayfalanması — ayrı iş olarak önerilecek.
- Diğer departmanların iç talep akışı; reçeteli ürün yönetim ekranı.
- Borç istisnası **çözüm** ekranı (S6 cevaplanana kadar).
- Üretime uygulama: her aşama ayrı `CANLIYA UYGULA` onayına bağlıdır.

## 12. Açık riskler

1. **Depo ↔ otel eşleşmesi** önek sözleşmesine dayanır; ERP'de depo ana tablosu yok.
2. **Geçmiş kalemlerin fiyatı** bilinemez; geçişte güncel fiyatla doldurulur.
3. **Sayım akışı** (Ö10) 2026-09-15'te yayınlanan stok ekranını değiştirir; stok koruması Ö10
   kesinleşmeden yayınlanırsa bar depolarında sayım fiilen reddedilir.
4. **Edge Function'lar** Dashboard'dan elle dağıtılıyor; uçtan uca test açığı açık (bölüm 5).
5. **Servis kaydının kapatılmaması** yanlış operasyon gününe tüketim yazdırabilir (S4).
6. **Pilot bar** kodu henüz verilmedi.

## 13. Aşamalara geçmeden kesinleşmesi gerekenler

| Aşama | Kesinleşmesi gerekenler |
|---|---|
| **1** | V1 (doğrulama modeli) · Ö1 (açık beyan biçimi) · Ö2 (tüm barlar) · Ö6 + S6 (borç istisnası ve çözüm yetkisi — Aşama 1'de en az kayıt açılışı) · Ö7 + S5 (kullanılan miktar; `hazir` durumu) · Ö10 + S9 (sayım gözlemi ve bekleyen düzeltme) · S10 (Edge Function test seçeneği ve indirme izni — kapanmazsa açık kalır) |
| **2** | V2 · Ö4 · Ö5 · Ö8 + S1–S4 (servis kaydı) · Ö9 + S7 (depo takvimi) · pilot bar kodu |
| **3** | Ö3 · S8 |
| **4** | V3 |

Kararlar sade dille ve birbirine bağlı gruplar hâlinde bölüm 14'te sunulur.

---

## 14. Karar tablosu — A1 (2026-09-18)

Her grup birbirine bağlı kararları birlikte sunar. **Önerilen** bir tasarım önerisidir (Ö), kullanıcı
kararı değildir; seçilene kadar A1 planı o gruba bağlı görevlere geçmez.

### 14.1 Personelin oda/misafir doğrulaması (V1, Ö1, Ö2)

| | |
|---|---|
| **Önerilen** | Ücretli siparişte oda numarası sunucuda zorunlu; sunucu aktif konaklama ve açık folyo arar. Sipariş (QR ya da garson) **doğrulama bekliyor** başlar. Bar personeli ayrı bir adımda "Misafirin oda kartını/kimliğini kontrol ettim" beyanıyla **Doğrula**'ya basar; doğrulayan, zaman ve beyan kaydedilir. Beyan gelmeden sipariş hazırlanamaz. Kural **tüm barlara** uygulanır (güvenlik açığı; pilot yalnız ikmal için). |
| **İşletmeye etkisi** | Ücretli her siparişte personele bir ek dokunuş; beyansız sipariş kuyrukta bekler. İtirazda kimin doğruladığı bellidir. PMS ve check-in akışı değişmez. Ücretsiz siparişler bugünkü gibi akar. |
| **Alternatif A — Oda PIN'i** | Misafir QR'da oda PIN'i girer; personel yükü yok, QR siparişi hızlı. **Bedeli:** PMS check-in'e PIN üretimi/dağıtımı ve şema değişikliği; kayıp PIN süreci. |
| **Alternatif B — Oda no + soyad** | Sunucu soyadı eşleştirir; PMS değişmez, personel yükü yok. **Bedeli:** soyad tahmin edilebilir (zayıf kanıt), misafirden kişisel veri girişi istenir. |
| **Alternatif C — Yalnız pilot barda** | Diğer barlarda bugünkü açık (oda no bilmek borçlandırmaya yeter) sürer. Önerilmez. |

### 14.2 Hazırlanmış ürünün iptali ve folyo kapandığında yapılacak işlem (Ö7 + S5, Ö6 + S6)

Birlikte sunulur: ikisi de "fiziksel olarak kullanılan/servis edilen ürün kaydı ile parasal kayıt
ayrıdır" ilkesine dayanır (ilke 2).

| | |
|---|---|
| **Önerilen — iptal** | `hazirlaniyor` **ve** `hazir` durumunda iptal, siparişin her rezerve bileşeni için **kullanılan miktar** ister (varsayılan yok, 0 açıkça girilir). Kullanılan kadar zayi yazılır, kalan serbest bırakılır. `yeni` iptalde giriş istenmez. |
| **Önerilen — folyo kapalı** | Teslim ilk denemede `FOLYO_KAPALI` ile durur. Personel "ürün fiziksel olarak servis edildi" beyan ederse stok satış olarak düşer, **borç yazılmaz**, aynı işlemde bir **borç istisnası** kaydı açılır. İstisnayı **ön büro şefi ya da muhasebe** rolü çözer: misafir yeniden doğrulanarak elle seçilen açık folyoya borç, ya da "tahsil edilemedi". Başka folyoya otomatik aktarım yok. A1'de istisna yalnız kaydedilir ve listelenir; çözüm ekranı sonraki iş. |
| **İşletmeye etkisi** | İptalde personel bileşen başına bir miktar girer (birkaç saniye). Zayi raporu gerçek kullanımı gösterir. Kapanmış folyoda servis edilen ürün kaybolmaz; bir **tahsilat listesi** oluşur ve takip eden bir rol gerekir. |
| **Alternatif A — `hazir` iptali tam tüketim sayılır** | Daha hızlı; ama hazırlanıp servis edilmeyen ürün fazla zayi görünür. `hazirlaniyor` için T19 gereği uygulanamaz. |
| **Alternatif B — Folyo kapalıysa teslim tamamen engellenir** | Borç kaybı kaydı hiç oluşmaz; ama servis edilmiş ürün sistemde görünmez, stok ile gerçek ayrışır (T20'ye aykırı). |
| **Alternatif C — İstisnayı bar kaptanı çözer** | Bar tarafında hızlı; ama folyo seçimi ve tahsilat ön büro/muhasebe yetkisi gerektirir. |

### 14.3 Fiziksel sayımın rezervasyonlarla çelişmesi (Ö10 + S9)

| | |
|---|---|
| **Önerilen** | Sayılan miktar **her zaman** gözlem olarak kaydedilir. Bir kalemin sayılan miktarı o depodaki aktif rezervasyonun altındaysa o kalemin stok düzeltmesi "rezervasyon çelişkisi — bekliyor" olur; diğer kalemler normal uygulanır. İlgili siparişler teslim/iptal edildiğinde ya da **depo sorumlusu / maliyet kontrol** karar verdiğinde düzeltme o anki duruma göre yeniden hesaplanıp uygulanır. Sayım yazması `stok_ekle`'den ayrı bir RPC'ye alınır ve tarih düzeltmesini taşır (3.5.1). |
| **İşletmeye etkisi** | Sayım hiçbir zaman reddedilmez. Bar depolarında ara sıra "bekleyen düzeltme" listesi oluşur ve birinin kapatması gerekir. 2026-09-15'te yayınlanan sayım ekranı değişir (yeni test ve yayın). |
| **Alternatif A — Sayımı rezervasyon altında reddet** | Basit; ama gerçek gözlem kaybolur (T22'ye aykırı) ve bar depolarında sayım fiilen durur. |
| **Alternatif B — Sayım stoğu yazar, rezervasyon kendiliğinden kısılır** | Gözlem korunur; bekleyen siparişler sessizce karşılıksız kalır ve teslimde `STOK_TUTARSIZ` alır. |
| **Alternatif C — Stok koruması sayıma uygulanmaz** | Sayım bugünkü gibi; çelişki teslim anında ortaya çıkar. En az değişiklik, en geç fark edilen hata. |

**Bağımlılık:** A1'in stok çıkış koruması bu karar olmadan **yayınlanamaz** (3.5; risk 12.3).

### 14.4 Yayın kapsamı ve Edge Function test yöntemi (Ö2, S10)

| | |
|---|---|
| **Önerilen** | Önce yerel uçtan uca ortam kurulur; `hyper-api` ve `rapid-handler` orada test edilir; `smooth-service` regresyon olarak bir kez koşulur. Ortam: iki proje (ana + müşteri) için mevcut `postgres:17` ve `postgrest` imajları, **Supabase Edge Runtime** (üretimle aynı çalışma zamanı), **GoTrue** (`auth.getUser()` için gerçek kimlik servisi) ve yolları eşleyen küçük bir Node yönlendiricisi (mevcut Node). A1 **tek yayın**, tüm barlar; Edge testi geçmeden yayın yok (5.3). |
| **Gereken indirme (tek seferde)** | 1) `supabase/edge-runtime` Docker imajı — Edge Function'lar `Deno.serve`/`Deno.env` kullanır; makinede hiçbir Deno çalışma zamanı yok (Z3). 2) `supabase/gotrue` Docker imajı — `rapid-handler` ve `smooth-service` kimliği `/auth/v1/user` ile doğrular; taklit kimlik uçtan uca sayılmaz. 3) `@supabase/supabase-js@2` modülü — fonksiyonlar çalışma anında `esm.sh`'tan içe aktarır; bir kez indirilip test ortamına sabitlenir (sürüm kilidi). Boyutlar indirmeden ölçülmedi. |
| **İşletmeye etkisi** | A1 yayını ortam kurulup testler geçene kadar gecikir. Kazanç: canlı QR sipariş yolundaki kırılma (ör. eski menü sayfası fiyatsız sipariş yollarsa `FIYAT_DEGISTI`) yayından **önce** görülür. |
| **Alternatif A — Deno imajı (`denoland/deno`)** | Edge Runtime yerine düz Deno; muhtemelen daha küçük. **Bedeli:** üretim çalışma zamanı değil, davranış farkı olabilir. GoTrue yine gerekir. |
| **Alternatif B — Bulutta ayrı staging projesi** | Gerçek platform, yerel indirme yok. **Bedeli:** izole değil; proje oluşturma, dağıtım ve olası ücret kullanıcı işi. |
| **Alternatif C — A1'i böl: önce yalnız `rapid-handler` dışı** | Uygulanamaz: `bar_siparis_olustur` değişikliği `hyper-api`'nin davranışını değiştirir, yani QR yolu yine uçtan uca testsiz yayına girer (5.3 kuralı). |
| **Alternatif D — Yalnız pilot barda yayın** | Diğer barlarda güvenlik açıkları sürer (14.1 C ile aynı gerekçe). |

### 14.5 Servis açma/kapatma — A1'i bekletmez

| Karar | Etkilediği aşama | A1'e etkisi |
|---|---|---|
| S1 servisi kim açar/kapatır | Aşama 2 | Yok |
| S2 açık servis yokken gelen sipariş | Aşama 2 | Yok — A1'de siparişin servis kaydı alanı yok |
| S3 açık siparişle servis kapatma | Aşama 2 | Yok |
| S4 kapatılmayı unutulan servis | Aşama 2 | Yok |

**Neden:** A1 operasyon günü yazmaz; tüketimi sipariş ve zamanla kaydeder (3.3). Servis kaydı ve
operasyon günü Aşama 2'de eklenir; A1 döneminde oluşan siparişler ikmal taslağına girmez (4.1).
Tek koşul: Aşama 2 yayınlandığında pilot bar temiz başlar — bu, A1'e iş eklemez.

### 14.6 Özet — A1'e geçmek için gerekenler

| Grup | A1'de bağlı olduğu görevler |
|---|---|
| 14.1 doğrulama | sipariş oluşturma, doğrulama RPC'si, kuyruk/garson/menü ekranları |
| 14.2 iptal + folyo | teslim ve iptal RPC'leri, istisna tablosu, kuyruk ekranı |
| 14.3 sayım | stok çıkış koruması, sayım RPC'si, stok-takip sayım ekranı |
| 14.4 yayın + Edge | uçtan uca ortam (indirme izni), `rapid-handler`, yayın sırası |
| 14.5 servis | — (Aşama 2) |

---

## 15. Kararlar (2026-09-18) ve A1 uygulama tercihleri

### 15.1 Kullanıcı kararları (kesin — T)

| # | Karar |
|---|---|
| T23 | **Ücretli sipariş:** personelin açık oda/misafir doğrulaması zorunlu; doğrulayan kaydedilir. (14.1 önerileni; tüm barlar.) |
| T24 | **İptal:** kullanılan miktar kaydedilir, **otomatik zayi sayılmaz**; kullanım nedeni ayrı tutulur. **Kapalı folyo:** "servis edildi" istisnası yalnız **yetkili** personelce açılır; aynı siparişten **ikinci stok düşümü ya da ikinci borç oluşmaz**; istisna çözülmeden sipariş **tamamlanmış sayılmaz**. |
| T25 | **Sayım:** fiziksel gözlem saklanır; rezervasyonla çelişen düzeltme bekler. Bekleyen düzeltme uygulanırken **aradaki stok hareketleri dikkate alınır**; eski sayım miktarı güncel stoğun üzerine doğrudan **yazılmaz**. Kısmi uygulama ekranda **açık görünür**. |
| T26 | **Kapsam:** A1 tüm barları kapsayan yayın adayı; uçtan uca Edge testi geçmeden yayın yok. Yerel test bağımlılıkları indirilebilir; sürüm/imaj özetleri sabitlenir; üretim sırrı/verisi test ortamına taşınmaz; aynı çalışma zamanı ailesi **üretimle sürüm eşitliği diye raporlanmaz**. Push, deploy ve canlı migration yetkisi **yok**. |

### 15.2 Uygulama tercihleri (Ö — kararların A1'deki karşılığı; raporda ayrıca sorulur)

| # | Tercih | Dayandığı karar |
|---|---|---|
| Ö11 | İptalde kullanılan miktar `bar_stok_tuketimleri`'ne `tur = 'iptal_kullanimi'` olarak yazılır (**`zayi` değil**) ve `kullanim_nedeni` zorunludur (`hazirlandi_servis_edilmedi` · `dokuldu_kirildi` · `misafir_iade` · `diger` + açıklama). Kullanılan miktar fiziksel olarak tükendiği için **stoktan düşer**; kalan rezervasyon serbest bırakılır. `yeni` iptalde giriş yok; `hazirlaniyor` ve `hazir` iptalinde her rezerve bileşen için giriş zorunlu. | T19, T24 |
| Ö12 | "Servis edildi" istisnasını **açma** yetkisi: `bar_siparis_yonetimi` = `tam`. **Çözme** yetkisi (elle seçilen açık folyoya borç ya da tahsil edilemedi): `pms_folio` ≥ `kayit`. İkisi de siparişin oteline erişim ister. | T24 (S6'nın karşılığı) |
| Ö13 | İstisnalı teslimde sipariş `teslim_edildi` **olmaz**, yeni `istisna_bekliyor` durumuna geçer (stok düşmüştür, borç yoktur). Çözüm siparişi `teslim_edildi` yapar; folyo köprüsü istisnalı siparişte **çalışmaz** (borcu çözüm fonksiyonu seçilen folyoya bir kez yazar). Tekillik: `bar_stok_tuketimleri(rezervasyon_id)`, `bar_borc_istisnalari(siparis_id)`, `pms_folio_hareketleri(kaynak_tip, kaynak_id, ters_kayit)`. | T24 |
| Ö14 | Sayım onayı sunucuda tek RPC'dir (`stok_sayim_onayla`). Her kalem kilit altında: `fark = sayılan − onay anındaki stok`. Çıkış sonrası miktar aktif rezervasyonun altına inmiyorsa **fark** uygulanır; iniyorsa kalem `stok_sayim_bekleyenleri`'ne **fark** (delta) ile yazılır. Bekleyen uygulandığında **o anki** stoğa fark eklenir (aradaki hareketler korunur); sayılan miktar doğrudan yazılmaz. Oturum `kismi_uygulandi = true` işaretlenir ve RPC kalem bazında sonucu döner. | T22, T25 |
| Ö15 | Bekleyen düzeltmeyi **uygulama/iptal** yetkisi: `stok_takip` = `tam`, otel erişimi. Uygulama anında hâlâ çelişki varsa `REZERVE_STOK` ile reddedilir. | T25 (S9'un karşılığı) |
