# Bar Güvenliği, Gün Sonu İkmal ve Teslim Kabulü — Tasarım

**Tarih:** 2026-09-17 · **Revizyon:** 2 (2026-09-17) · **Durum:** incelemede — açık tercihler
kesinleşmedi
**Kapsam dışı ilkesi:** mevcut bar modülü **yeniden kurulmaz**; tablolar, sayfalar ve Edge
Function'lar yerinde genişletilir.
**Dayanak:** `docs/BAR-MODULU-ISLEYIS.md` (2026-09-16 bulguları) · üretim şeması
`2026-09-13-post-faz2-sema-dokumu.sql` (bar/stok fonksiyon ve politikaları 09-07 dökümüyle
birebir aynı — özetle doğrulandı).

## Gereksinimler ve tercihlerin kaynağı

Bu belgede üç tür madde vardır; birbirine karıştırılmaz.

### A. Kullanıcının yazılı talebi (kesin)

Kullanıcının 2026-09-17 mesajından; tasarım bunlara uymak zorundadır.

| # | Talep |
|---|---|
| T1 | Ücretli üründe aktif konaklama ve açık folyo **sunucuda** doğrulanır; yalnız oda numarası bilmek borçlandırmaya yetmez. |
| T2 | Onaylanan fiyat siparişe kaydedilir. |
| T3 | Teslimde stok ve folyo işlemi tutarlı olur; tekrar çağrılarda tekildir. |
| T4 | Rezervasyon yarışları, diğer stok çıkışlarıyla çakışma, otel izolasyonu ve pasif kullanıcı kontrolleri düzeltilir. |
| T5 | Hazırlanan ürünün iptali tüketimi yok saymaz. |
| T6 | Teslim edilmiş siparişlerin kayıtlı stok tüketiminden **bar ve operasyon günü** bazında tek talep taslağı üretilir. |
| T7 | Kaptan miktarları değiştirebilir, ürün ekleyebilir. |
| T8 | Günlük sayım ve ücretsiz her servise giriş zorunlu değildir. |
| T9 | Talep düzeltmesi stok tüketimi sayılmaz. |
| T10 | Cuma operasyonu gece yarısını geçse de Cumartesi teslimatına pazar ilavesi girilebilir; normal talep ve pazar ilavesi ayrı saklanır. |
| T11 | Depo onayı bar stoğunu artırmaz; onay → sevk → kaptan kabulü ayrı aşamalardır; yalnız kabul edilen miktar kullanılabilir bar stoğuna girer; kısmi teslimatlar izlenir. |
| T12 | Mevcut bar modülü yeniden kurulmaz. |
| T13 | Her aşama izole ortamda test edilir ve ayrı raporlanır. |
| T14 | İlk pilot tek barda olacaktır. |
| T15 | Push, migration ya da canlı uygulama yok; ayrıca `CANLIYA UYGULA` onayı beklenir. |

### B. Açık tercihler — kesinleşmedi (çalışma varsayımı)

Aşağıdakiler bir seçim aracıyla işaretlendi ama **konuşmada kesinleşmiş karar değildir**.
Tasarım ve Aşama 0–1 kodu bunları **çalışma varsayımı** olarak kullanır; her biri
değişebilir. Sağ sütun, farklı bir tercihin neyi değiştireceğini gösterir.

| # | Konu | Çalışma varsayımı | Farklı seçilirse |
|---|---|---|---|
| V1 | QR'dan gelen ücretli siparişte oda numarasına ek kanıt | **Personel onayı:** sipariş "oda onayı bekliyor" olur; personel oda kartını görüp onaylar. | *Oda PIN'i:* PMS check-in akışı ve şeması değişir (A1 kapsamı büyür). *Oda no + soyad:* PMS değişmez; `bar_siparis_olustur` soyad eşleşmesi yapar, onay adımı kalkar. |
| V2 | Kaptanın sistemdeki karşılığı | **Yeni rol `bar_kaptan`** + bar ataması. | *Mevcut rol + atama:* rol eklenmez; yetki yalnız atama tablosundan. Etkisi Aşama 2'de, A1'e dokunmaz. |
| V3 | Sevk edilip kabul edilmeyen miktar | **Açık fark; depo "geri al" ya da "kayıp" ile kapatır.** | *Otomatik merkeze iade:* fark kapatma adımı kalkar, kayıp/kırılma ayrımı kaybolur. Etkisi yalnız Aşama 4. |
| V4 | Operasyon günü sınırı | **06:00**, bar bazında ayarlanabilir (`bar_ayarlari.gun_sonu_saati`). | Yalnız varsayılan değer değişir; mekanizma aynı. A1'de tüketim kayıtlarının `operasyon_gunu` alanını etkiler. |

### C. Tasarım önerileri — onay bekliyor

Talepten doğrudan çıkmayan, tasarımcının önerdiği yorumlar.

| # | Öneri | Gerekçe |
|---|---|---|
| Ö1 | Garson (personel) girdiği ücretli sipariş **onaylı** sayılır; siparişi giren personel onaylayan olarak kaydedilir. | Garson misafiri yüz yüze görüyor; ikinci onay aynı kişiden gelirdi. V1 değişirse bu da yeniden değerlendirilir. |
| Ö2 | Aşama 1 güvenlik düzeltmeleri **tüm barlara** uygulanır; pilot (T14) yalnız Aşama 2–4 için. | T1–T5 güvenlik açığı; tek barla sınırlamak diğer barlarda açığı bırakır. |
| Ö3 | Pazar ilavesi penceresi **saate değil teslim tarihine** bağlıdır: Cumartesi teslim tarihi geçmediği sürece girilebilir. | T10 "gece yarısını geçse de" diyor; bir saat sınırı kaptanın gün sonunu sabah yapmasını engellerdi. |
| Ö4 | Taslak yalnız **satış** tüketiminden üretilir; hazırlanıp iptal edilen (zayi) tüketim taslağa girmez, kaptan elle ekler. | T6 "teslim edilmiş siparişler" diyor. |
| Ö5 | Bar ikmali **ayrı** tablo ve ekranlarla yürür; diğer departmanların iç talep akışı (`depo-siparis.html`) değişmez. | T11 bar stoğu için; mevcut akış onayda anında transfer yapıyor ve başka departmanlar ona bağlı. |
| Ö6 | Folyo kapandıktan sonra teslim edilemeyen ücretli sipariş iptal edilir ve hazırlanan ürün **zayi** olarak düşülür. | T3 (tutarlılık) ve T5 birlikte: borç yazılamıyorsa teslim olmaz, ama tüketim kaybolmaz. |

### D. Ölçüm sonucu zorunlu hale gelenler

Tercih değil; mevcut sistemde ölçülen bir durumun sonucudur.

| # | Ölçüm | Tasarıma etkisi |
|---|---|---|
| Z1 | `stok_rezervasyonlari` bar yetkisi isteyen RLS'e tabidir. **İzole ölçüm (Aşama 0):** aktif rezervasyon 1 iken bar yetkisi olmayan depo kullanıcısı 0 satır görüyor. | Stok çıkış koruması **SECURITY DEFINER** olmak zorundadır. Çağıranın haklarıyla çalışsaydı depo kullanıcısı rezervasyonları göremez, toplamı 0 okur ve koruma sessizce devre dışı kalırdı (bkz. 1.5). |
| Z2 | Stok takipteki sayım onayı stoğu `stok_ekle` üzerinden yazar (`stok-takip.html` sayım onayı → `saveStok` → `rpc/stok_ekle`). | Koruma sayımı da kapsar: bar deposunda sayım bekleyen siparişlere ayrılmış miktarın altına inemez (bkz. 1.5 bilinen kısıt). **Bu sonucun operasyonel kabulü kullanıcı onayı bekler.** |
| Z3 | Deno bu makinede kurulu değil; Edge Function'lar yerelde çalıştırılamaz. | `rapid-handler`'ın yetki kararı (kimlik, aktiflik, otel kapsamı) test edilebilir bir veritabanı fonksiyonuna taşınır (`bar_masa_yetki_kapsami`, bkz. 1.7). Edge Function'ın kendi çalışma zamanı raporda **sınanmadı** olarak yazılır. |
| Z4 | Döküm yüklemesinde `schema "public" already exists` hatası çıkar (Aşama 0 ölçümü). | Zararsızdır: `pg_dump` `CREATE SCHEMA public;` yazar. Test ortamı yalnız bu satırı **tam eşleşmeyle** istisna sayar ve sayısını raporlar; E-5 provası ve `dokum-dogrula.mjs` ile aynı kural. |

## Temel ilkeler

1. **Karar sunucuda verilir.** Oda doğrulaması, fiyat, stok yeterliliği, otel/depo eşleşmesi,
   kullanıcı aktifliği ve durum geçişleri RPC içinde kontrol edilir. İstemci kontrolü yalnız
   kullanıcı deneyimidir.
2. **Para ve stok birlikte hareket eder.** Teslim, stok tüketimini ve folyo borcunu **aynı
   işlemde** yazar; biri olmazsa hiçbiri olmaz.
3. **Her yazma tekrar çağrıya dayanıklıdır.** Aynı teslim, kabul ya da sevk iki kez işlenmez.
4. **Talep, stok değildir.** İkmal talebi oluşturmak, düzenlemek, onaylamak stok miktarını
   değiştirmez. Stok yalnız **sevkte** (merkezden çıkar) ve **kabulde** (bara girer) değişir.
5. **Hazırlanan ürün tüketilmiştir.** Hazırlığa başlandıktan sonraki iptal stoğu geri vermez.

---

## Aşama 1 — Bar ve PMS güvenliği (tüm barlar — Ö2, onay bekliyor)

### 1.1 Onaylanan fiyat siparişe kaydedilir

**Sorun:** folyo tutarı teslim anındaki `menu_urunler.fiyat` ile hesaplanıyor; müşteriye
gösterilen fiyatla borç farklılaşabilir.

**Değişiklik:**
- `bar_siparis_kalemleri`'ne eklenir: `birim_fiyat numeric(12,2) not null`, `ucretli boolean not null`.
- İstemci her kalem için **gördüğü fiyatı** yollar: `{menu_urun_id, adet, gosterilen_fiyat}`.
- `bar_siparis_olustur` ürünün **o anki** ana fiyatını okur. Ücretli kalemde
  `gosterilen_fiyat ≠ fiyat` ise sipariş reddedilir: `FIYAT_DEGISTI` — müşteri menüyü yeniler.
  Eşleşirse fiyat ve `ucretli` bayrağı kaleme **anlık görüntü** olarak yazılır.
- Folyo köprüsü tutarı **yalnız anlık görüntüden** hesaplar: `SUM(adet × birim_fiyat) WHERE ucretli`.
- Mevcut kalemler için geçiş: `birim_fiyat` = ürünün şu anki fiyatı, `ucretli` = ürünün şu anki
  bayrağı (tarihsel fiyat bilinmediği için; geçiş raporunda sayılır).

### 1.2 Ücretli sipariş: aktif konaklama + açık folyo + personel onayı

> Sunucu doğrulaması (aktif konaklama + açık folyo) **T1 gereğidir**. "Personel onayı" ek kanıt
> yöntemi **V1 çalışma varsayımıdır**; garson siparişinin onaylı sayılması **Ö1 önerisidir**.
> İkisi de kesinleşmedi.

**Sorun:** oda numarasını bilmek borçlandırmaya yetiyor; ücretli siparişte oda no zorunluluğu
yalnız istemcide.

**Yeni sütunlar (`bar_siparisleri`):**

| Sütun | Anlam |
|---|---|
| `kanal` | `qr` \| `personel` |
| `oda_onay_durumu` | `gerekmiyor` \| `bekliyor` \| `onaylandi` \| `reddedildi` |
| `rezervasyon_id`, `folio_id` | Onayda çözülen konaklama ve folyo (anlık görüntü) |
| `oda_onaylayan`, `oda_onay_zamani` | Onayı veren personel (auth uid) |

**Kurallar:**
- Sepette ücretli kalem varsa `oda_no` **sunucuda zorunludur**; yoksa `ODA_NO_GEREKLI`.
- Oluşturma anında oda için **güncel konaklama** aranır (aktif oda ataması + rezervasyon
  `giris_yapildi` + `acik` folyo; bugünkü köprüyle aynı tanım). Bulunamazsa `KONAKLAMA_YOK`.
- **QR kanalı:** `oda_onay_durumu = 'bekliyor'`. Folyo **henüz bağlanmaz**.
- **Personel kanalı** (garson siparişi, personel JWT'si): siparişi giren personel misafiri
  görmüştür → `onaylandi`, `rezervasyon_id`/`folio_id` o anda bağlanır, onaylayan = çağıran.
- Yeni RPC `bar_siparis_oda_onayla(siparis_id)` — `bar_siparis_yonetimi:kayit` + otel erişimi.
  Konaklamayı **yeniden** çözer, bağlar. `bar_siparis_oda_reddet(siparis_id, neden)` →
  sipariş iptal olur (hazırlık başlamadığı için rezervasyon serbest kalır).
- `hazirlaniyor`'a geçiş, oda onayı `bekliyor` iken **reddedilir** (`ODA_ONAYI_BEKLIYOR`).
  Böylece onaysız ücretli ürün hazırlanmaz.
- Teslimde köprü, bağlı `folio_id`'nin hâlâ `acik` olduğunu ve rezervasyonun hâlâ
  `giris_yapildi` olduğunu doğrular. Değilse **teslim tümüyle reddedilir** (`FOLYO_KAPALI`);
  personel iptal eder ve hazırlanan ürün tüketim olarak kaydedilir (1.6). Tahsil edilemeyen
  ürün stoktan kaybolmaz.
- Ücretsiz siparişler (`gerekmiyor`) bugünkü gibi akar.

### 1.3 Teslim: stok ve folyo tek işlem, tekrar çağrıda tekil

`bar_siparis_teslim_et` yeniden yazılır:
1. Siparişi `SELECT … FOR UPDATE` ile kilitler.
2. Durum zaten `teslim_edildi` ise **hiçbir şey yazmadan** `{sonuc:'zaten_teslim'}` döner.
3. Yalnız `hazir`'dan teslim edilir (`GECERSIZ_DURUM`); ücretli kalem varsa `onaylandi` şart.
4. Her aktif rezervasyon için (deterministik sırada kilitlenmiş stok anahtarlarıyla, bkz. 1.4):
   stok ≥ miktar değilse `STOK_TUTARSIZ` — **sessiz 0'a kırpma yok**; rezervasyon
   `kullanildi`; stok düşer; `bar_stok_tuketimleri`'ne satır (tür `satis`).
5. Durum `teslim_edildi` → folyo köprüsü (anlık görüntü tutarı, bağlı folyo). Köprü hata
   verirse 1–5 birlikte geri alınır.
6. Tekillik ayrıca kısıtlarla korunur: `bar_stok_tuketimleri(rezervasyon_id)` tekil;
   `pms_folio_hareketleri(kaynak_tip, kaynak_id, ters_kayit)` tekil (mevcut).

**Yeni tablo `bar_stok_tuketimleri`** — Aşama 2'nin kaynağıdır:
`id, otel_id, bar_depo_id, siparis_id, siparis_kalem_id, rezervasyon_id (tekil), stok_kodu,
miktar, tur ('satis'|'zayi'), operasyon_gunu date, zaman, personel (auth uid)`.
Ayrıca genel stok geçmişi için `stok_hareketleri`'ne `cikis` satırı yazılır
(`aciklama = 'bar_tuketim: <sipariş>'` / `'bar_zayi: <sipariş>'`).

### 1.4 Rezervasyon yarışı

**Sorun:** kullanılabilir stok okunup sonra rezervasyon yazılıyor; arada kilit yok.

**Değişiklik:** stok anahtarı başına **işlem ölçekli danışma kilidi**:
`pg_advisory_xact_lock(hashtextextended('stok:' || depo_kodu || ':' || stok_kodu, 0))`.
- Sipariş, gereken tüm anahtarları **önce hesaplar, sıralar, sonra sırayla kilitler**
  (kilitlenme/deadlock yok), ardından yeterliliği kontrol edip rezerve eder.
- Aynı kilit teslim, iptal-tüketim ve **tüm stok çıkışlarında** (1.5) alınır.
- Kanıt: izole ortamda iki eşzamanlı işlem aynı son birimleri ister → **yalnız biri** geçer;
  kilit kaldırılmış negatif kontrolde ikisinin de geçtiği gösterilir.

### 1.5 Diğer stok çıkışlarıyla çakışma

**Sorun:** rezervasyonu yalnız bar biliyor; stok takipteki çıkış/transfer, günlük tüketim,
mal kabul iadesi ve iç talep transferi rezerve stoğu da tüketebiliyor.

**Değişiklik** (`stok_ekle` negatif delta ve `stok_transfer` kaynak bacağı):
- Koruma tek bir fonksiyondadır: `stok_cikis_korumasi(depo, stok_kodu, cikis)`. `stok_ekle` ve
  `stok_transfer` çıkıştan önce onu çağırır.
- **SECURITY DEFINER zorunludur (Z1).** `stok_rezervasyonlari` bar yetkisi isteyen RLS'e tabi;
  koruma çağıranın haklarıyla çalışsaydı depo kullanıcısı rezervasyonları göremez, toplamı 0
  okur ve **sessizce** devre dışı kalırdı. İzole testte bu, depo kullanıcısının (bar yetkisi
  olmayan) çıkışıyla ayrıca sınanır.
- Aynı danışma kilidini alır.
- O depo+ürün için **aktif rezervasyon > 0** ve çıkış sonrası miktar **< aktif rezervasyon**
  ise hata: `REZERVE_STOK` ("X birim bekleyen bar siparişlerine ayrılmış").
- Rezervasyon varken çağıranın o otele erişimi yoksa `OTEL_ERISIMI_YOK` (definer fonksiyon
  başka otelin rezervasyon miktarını açığa çıkarmasın diye).
- Aktif rezervasyon **yoksa davranış bugünküyle aynıdır** (0'a kırpma dahil). Rezervasyon
  yalnız bar depolarında oluştuğu için diğer depolar ve modüller etkilenmez.
- Teslim kendi rezervasyonunu **önce** `kullanildi` yapar, sonra düşer → kendi korumasına takılmaz.

**Sonuç — onay bekleyen kısıt (Z2):** bar deposunda sayım onayı da `stok_ekle` üzerinden yazar.
Bu yüzden sayım, bekleyen siparişlere ayrılmış miktarın altına indiremez; ekran "önce bekleyen
bar siparişlerini teslim/iptal edin" der. Operasyonel karşılığı: pilot barda sayım, açık sipariş
kalmadığında (servis sonrası) yapılır. **Kullanıcı bu sonucu henüz kabul etmedi.** Kabul
edilmezse alternatif: sayım onayı ayrı bir RPC'ye (`stok_sayim_uygula`) alınır, fiziki sayım
rezervasyonun altına inebilir ve açık rezervasyonlar "sayım açığı" olarak işaretlenir — bu,
2026-09-15'te yayınlanan stok ekranına da dokunur.

### 1.6 İptal: hazırlanan ürün tüketimdir

`bar_siparis_iptal(siparis_id, neden)` — `neden` zorunlu:
- `yeni` → rezervasyonlar `serbest`; stok değişmez.
- `hazirlaniyor` ya da `hazir` → rezervasyonlar **tüketilir** (stok düşer),
  `bar_stok_tuketimleri` türü **`zayi`**, folyoya borç yazılmaz.
- `teslim_edildi` / `iptal` → değiştirilemez (mevcut terminal-durum tetikleyicisi).
- Tekrar çağrı: zaten `iptal` ise hiçbir şey yazmadan `{sonuc:'zaten_iptal'}`.

### 1.7 Otel izolasyonu

- **Depo ↔ otel:** `bar_siparis_olustur` her iki çağrı yolunda da `p_depo_id`'nin
  `p_otel_id` önekini taşıdığını doğrular (`split_part(p_depo_id,'_',1) = p_otel_id`).
  ERP'de depo ana tablosu yok; önek sözleşmesi tek güvenilir kaynak. `DEPO_OTEL_UYUSMAZ`.
- **`rapid-handler` (masa/QR):** `liste` yalnız çağıranın erişebildiği otel(ler)in masalarını
  döner; `ekle` ve `durum` başka otelin masası için reddedilir; `ekle`'de depo öneki otelle
  eşleşmelidir. El ile `yetki_matrisi` okuması ve `MAIN_SERVICE_KEY` kullanımı kalkar.
- **Karar veritabanında (Z3):** Deno yerelde olmadığından Edge Function çalıştırılıp
  sınanamaz. Bu yüzden yetkili mi / hangi oteller sorusu `bar_masa_yetki_kapsami()`
  fonksiyonunda, **çağıranın JWT'siyle** cevaplanır: `{yetkili:boolean, oteller:text[]}`.
  Edge Function yalnız kimliği `auth.getUser()` ile doğrular, bu fonksiyonu çağırır ve sonucu
  uygular. Fonksiyon izole testte sınanır; Edge Function'ın ince yapıştırıcı kodu **sınanmadı**
  olarak raporlanır ve yayında duman testiyle doğrulanır.
- **Stok tüketimleri, ikmal talepleri, sevkler:** RLS'te `auth_yetki_var` **ve**
  `auth_otel_erisim`; iki permissive politika varsa **ikisine birden** otel şartı (bkz.
  pentest-4 dersi).

### 1.8 Pasif kullanıcı

- Ana projedeki RPC'ler zaten fail-closed: `auth_yetki_var` / `auth_otel_erisim`
  `kullanicilar.aktif is true` arar (dökümden doğrulandı).
- **`rapid-handler`** kullanıcıyı e-postadan buluyor ve `aktif`'e bakmıyor → düzeltilir:
  kimlik `auth.getUser()`, yetki ve aktiflik `bar_masa_yetki_kapsami()` (pasif kullanıcıda
  `{yetkili:false, oteller:[]}` — izole testte ölçülür).
- `smooth-service` zaten `auth_yetki_var` ile doğruluyor (değişmez).

### 1.9 Ekran değişiklikleri (yalnız gerekli olan)

| Ekran | Değişiklik |
|---|---|
| `bar-menu.html` (müşteri) | Kalemle `gosterilen_fiyat` yollar; `FIYAT_DEGISTI`'de menüyü yeniler; ücretli siparişte "Siparişiniz alındı, oda onayı için personel gelecek" der. |
| `bar-garson.html` | `gosterilen_fiyat` yollar; `KONAKLAMA_YOK` mesajını gösterir. |
| `bar-siparis-kuyrugu.html` | "Oda onayı bekliyor" rozeti + **Onayla / Reddet**; iptalde neden zorunlu ve hazırlanmış siparişte "stoktan düşecek (zayi)" uyarısı; hata kodlarının Türkçe karşılığı. |
| `hyper-api`, `rapid-handler` | Yukarıdaki sunucu kuralları. |

---

## Aşama 2 — Gün sonu ikmal taslağı (pilot bar)

### 2.1 Kavramlar

- **Operasyon günü:** `(zaman AT TIME ZONE 'Europe/Istanbul' − gün_sonu_saati)::date`.
  Çalışma varsayımı (V4, kesinleşmedi): varsayılan gün sonu 06:00 → Cumartesi 01:30'daki
  teslim **Cuma** operasyon gününe aittir.
- **Bar ayarı** `bar_ayarlari`: `bar_depo_id (pk), otel_id, gun_sonu_saati time default '06:00',
  ikmal_pilot boolean default false, kaynak_depo_id` (merkez depo: 810→`810_100`, 811→`811_300`).
- **Kaptan ataması** `bar_kaptan_atamalari`: `kullanici_id, bar_depo_id, otel_id, aktif`.
  Çalışma varsayımı (V2, kesinleşmedi): yeni rol `bar_kaptan` ("Bar Kaptanı") + yeni modül
  `bar_ikmal` yetki matrisinde. Mevcut rol seçilirse rol eklenmez, yetki yalnız atamadan gelir.

### 2.2 Tablolar

**`bar_ikmal_talepleri`**: `id, otel_id, bar_depo_id, kaynak_depo_id, operasyon_gunu,
tur ('normal'|'pazar_ilavesi'), teslim_tarihi, durum, olusturan, gonderen, gonderme_zamani,
onaylayan, onay_zamani, not`. **Tekil:** `(bar_depo_id, operasyon_gunu, tur)`.

**`bar_ikmal_kalemleri`**: `id, talep_id, stok_kodu, urun_adi, birim,
onerilen_miktar (tüketimden; kaptan değiştiremez), talep_miktar (kaptanın istediği),
kaynak ('tuketim'|'elle'), elle_degisti boolean, onaylanan_miktar`. **Tekil:** `(talep_id, stok_kodu)`.

**Durum makinesi (talep):**
`taslak → gonderildi → onaylandi → kismi_sevk → sevk_edildi → kapandi`; `taslak`/`gonderildi`
iken `iptal`. Kaptan yalnız `taslak`'ı düzenler.

### 2.3 Taslak üretimi

`bar_ikmal_taslak_uret(bar_depo_id, operasyon_gunu)`:
- Kaynak: o bar ve operasyon gününün `bar_stok_tuketimleri` satırları, **tür `satis`**
  (teslim edilmiş siparişler). `stok_kodu` başına toplanır.
- Talep yoksa oluşturur; varsa ve **`taslak`** ise yeniden hesaplar:
  - `onerilen_miktar` güncellenir;
  - kaptanın **elle değiştirmediği** kalemlerde `talep_miktar = onerilen_miktar`;
  - `elle_degisti` ya da `kaynak='elle'` kalemlere dokunulmaz.
- `taslak` dışındaki talebe dokunmaz (`TALEP_KILITLI`). Aynı çağrı tekrar edilirse sonuç aynıdır.
- **Zayi taslağa girmez** (Ö4 — onay bekliyor; talep metni T6 "teslim edilmiş siparişler" diyor);
  kaptan gerekirse elle ekler.

### 2.4 Kaptan işlemleri

- `bar_ikmal_kalem_guncelle(kalem_id, talep_miktar)` — `≥ 0`; `elle_degisti = true`.
- `bar_ikmal_kalem_ekle(talep_id, stok_kodu, talep_miktar)` — `kaynak = 'elle'`; ürün `urunler`'de olmalı.
- `bar_ikmal_kalem_sil(kalem_id)` — yalnız `kaynak='elle'` kalem silinir; tüketimden gelen 0'a çekilir.
- `bar_ikmal_gonder(talep_id)` → `gonderildi`; talep miktarı toplamı 0 ise reddedilir.
- **Hiçbiri stok ya da stok hareketi yazmaz.** Test bunu satır sayılarıyla kanıtlar.
- Yetki: `bar_ikmal:kayit` + rol `bar_kaptan` + o bara aktif atama + otel erişimi + `ikmal_pilot`.

### 2.5 Zorunlu olmayanlar

Günlük sayım ve ücretsiz her servisin girilmesi **ön koşul değildir**: taslak yalnız mevcut
tüketim kayıtlarından çıkar; stok kodu olmayan ücretsiz ürünler tüketim üretmez ve hiçbir şeyi
engellemez.

---

## Aşama 3 — Cuma istisnası: pazar ilavesi (pilot bar)

> Talep T10'dur. Aşağıdaki giriş penceresi yorumu **Ö3 önerisidir**, kesinleşmedi.

- Operasyon günü **Cuma** olan bar için ikinci talep açılabilir: `tur = 'pazar_ilavesi'`.
  Başka günlerde `PAZAR_ILAVESI_YALNIZ_CUMA`.
- Teslim tarihi: Cuma operasyonunun normal talebi ve pazar ilavesi **ikisi de Cumartesi**.
  Diğer günlerde normal talep teslimi `operasyon_gunu + 1`.
- Giriş penceresi **saate değil teslim tarihine** bağlıdır: pazar ilavesi, İstanbul takvim
  günü **Cumartesi teslim tarihini geçmediği sürece** açılabilir. Böylece Cuma servisi gece
  yarısını ya da 06:00 sınırını geçse, kaptan gün sonunu Cumartesi sabahı yapsa bile ilave
  girilebilir. Açıldıktan sonra kendi durum makinesiyle yaşar — kaptan `taslak` iken düzenler.
- Pazar ilavesinin tüketim kaynağı **yoktur**; kalemleri tamamen elle girilir.
- **Ayrı saklanır:** ayrı talep satırı, ayrı kalemler, ayrı onay/sevk/kabul. Raporlarda ve
  depo ekranında ayrı görünür.

---

## Aşama 4 — Teslim kabulü (pilot bar)

### 4.1 Aşamalar ve stok etkisi

> Onay → sevk → kabul ayrımı ve "yalnız kabul edilen bara girer" **T11 gereğidir**. Kabul
> edilmeyen miktarın açık fark olarak kalıp depoca kapatılması **V3 çalışma varsayımıdır**;
> bar ikmalinin ayrı tablolarla yürümesi **Ö5 önerisidir**.

| Aşama | Kim | RPC | Stok |
|---|---|---|---|
| Onay | Depo | `bar_ikmal_onayla(talep_id, [{kalem_id, onaylanan_miktar}])` | **Değişmez** |
| Sevk | Depo | `bar_ikmal_sevk_et(talep_id, [{kalem_id, sevk_miktar}])` | Merkez depodan **düşer** |
| Kabul | Kaptan | `bar_ikmal_kabul_et(sevk_id, [{sevk_kalem_id, kabul_miktar}])` | Bar stoğuna **yalnız kabul edilen** girer |
| Fark kapatma | Depo | `bar_ikmal_fark_kapat(sevk_kalem_id, 'geri_al'\|'kayip', not)` | `geri_al`: merkeze geri girer · `kayip`: değişmez, kayıt |

**Bugünkü iç talep akışı (diğer departmanlar) değişmez.** Onayda anında transfer yapan
`depo-siparis.html` yalnız bar ikmali için kullanılmaz; bar ikmali kendi tabloları ve
ekranlarıyla ilerler.

### 4.2 Tablolar

**`bar_ikmal_sevkleri`**: `id, talep_id, otel_id, sevk_no, sevk_eden, sevk_zamani,
durum ('yolda'|'kabul_edildi'), kabul_eden, kabul_zamani`.

**`bar_ikmal_sevk_kalemleri`**: `id, sevk_id, talep_kalem_id, stok_kodu, sevk_miktar (>0),
kabul_miktar (null → kabul bekliyor; 0 ≤ kabul ≤ sevk), fark_durumu ('yok'|'acik'|'geri_alindi'|'kayip'),
fark_kapatan, fark_zamani, fark_notu`.

### 4.3 Kurallar

- **Kısmi teslimat:** bir talebe birden çok sevk yapılabilir. Kalem başına
  `Σ sevk_miktar ≤ onaylanan_miktar` (`SEVK_ONAYI_ASIYOR`). Talep durumu toplamlardan türetilir:
  hiç sevk yok → `onaylandi`; bir kısmı → `kismi_sevk`; tamamı → `sevk_edildi`;
  tüm sevkler kabul edilmiş ve açık fark yok → `kapandi`.
- **Sevk** merkez depodan düşerken stok kilidini alır; yetersizse `STOK_YETERSIZ`
  (0'a kırpma yok). "Yolda" miktar hiçbir `stok` satırında durmaz; sevk kalemlerinden izlenir.
- **Kabul** sevk başına **bir kez** yapılır: sevk `yolda` değilse `ZATEN_KABUL`. Her kalem için
  bar stoğu `kabul_miktar` kadar artar; `sevk > kabul` ise `fark_durumu = 'acik'`.
- **Fark kapatma** yalnız `acik` farka bir kez uygulanır.
- Her stok değişimi `stok_hareketleri`'ne yazılır (`bar_ikmal_sevk`, `bar_ikmal_kabul`,
  `bar_ikmal_fark_geri_al`) — belge no = sevk no.
- Tekil: talep ve sevk satırları `FOR UPDATE` ile kilitlenir; durum geçişleri tek yönlüdür.

### 4.4 Ekranlar

- `bar-ikmal.html` (kaptan): operasyon günü seçimi, taslak üret/düzenle/gönder, Cuma'da
  pazar ilavesi sekmesi, **yoldaki sevkler ve kabul**.
- `bar-ikmal-depo.html` (depo): gelen talepler (normal / pazar ilavesi ayrı), onay, sevk,
  kısmi teslimat görünümü, açık farklar ve kapatma.

---

## Güvenlik özeti (yeni nesneler)

- Tüm yeni tablolar: RLS açık; `anon` erişimi yok; okuma
  `auth_yetki_var(modül,'goruntule') AND auth_otel_erisim(otel_id)`; **doğrudan yazma yok** —
  tüm yazmalar SECURITY DEFINER RPC'lerle, fonksiyon içinde yetki + otel + (kaptan için) atama
  kontrolü.
- Her yeni fonksiyon: `revoke all … from public, anon`; `grant execute … to authenticated,
  service_role`; `set search_path = pg_catalog, public, pg_temp`.
- Hata kodları sabit metin önekidir (`FIYAT_DEGISTI:` …); ekran önekle çevirir.

## Hata kodları

`ODA_NO_GEREKLI`, `KONAKLAMA_YOK`, `FIYAT_DEGISTI`, `DEPO_OTEL_UYUSMAZ`, `ODA_ONAYI_BEKLIYOR`,
`FOLYO_KAPALI`, `GECERSIZ_DURUM`, `STOK_TUTARSIZ`, `REZERVE_STOK`, `STOK_YETERSIZ`,
`TALEP_KILITLI`, `PAZAR_ILAVESI_YALNIZ_CUMA`, `SEVK_ONAYI_ASIYOR`, `ZATEN_KABUL`,
`FARK_KAPALI`, `PILOT_KAPALI`, `KAPTAN_ATAMASI_YOK`, `YETKI_YOK`, `OTEL_ERISIMI_YOK`.

## Test stratejisi

Her aşama **ayrı** izole test dosyası ve **ayrı** rapor:

- **Taban (Aşama 0, kuruldu ve doğrulandı — 8 OK / 0 FAIL):** atılabilir `postgres:17`;
  `scripts/supabase-shim.sql` → `scripts/bar-test-auth.sql` (PostgREST v12 kimlik JSON'u) →
  `2026-09-13-post-faz2-sema-dokumu.sql` (gerçek üretim fonksiyon, politika ve tetikleyicileri;
  0 hata + 1 bilinen zararsız satır, Z4) → `2026-09-14-stok-liste-ozet.sql` → aşamanın aday
  migration'ı. Bar nesneleri dökümle birebir sayılır (fonksiyon 5, politika 13, tetikleyici 5).
- **Kimlikler:** gerçek `kullanicilar` + `auth.users` satırları, rol + `request.jwt.claims` ile
  (PostgREST'in yaptığı gibi): 810 bar personeli, 811 bar personeli, pasif kullanıcı, yalnız
  görüntüleme yetkili kullanıcı, depo kullanıcısı (bar yetkisi yok); QR yolu için `service_role`.
- **Sınanamayanlar (her raporda ayrıca yazılır):** Edge Function çalışma zamanı (Z3); gerçek
  PostgREST üzerinden uçtan uca QR akışı; üretim verisiyle geçiş (yayın anı preflight'ı).
- **Negatif kontroller:** kritik korumalar (kilit, rezerve koruması, tekillik) kaldırıldığında
  testin **düştüğü** gösterilir — koruma olmadan da geçen test kanıt sayılmaz.
- **Eşzamanlılık:** iki ayrı bağlantıda açık işlemlerle gerçek yarış.

| Aşama | Test dosyası | Asgari senaryolar |
|---|---|---|
| 0 | `scripts/bar-test-taban.test.mjs` | döküm 0 hata · bar nesneleri dökümle birebir · `auth.uid()` JWT JSON'undan · 810/811 erişim ayrımı · pasif kullanıcı fail-closed · üretim `bar_siparis_olustur` tabanda çalışıyor · Z1 ölçümü |
| 1 | `scripts/bar-a1-guvenlik.test.mjs` | **önce:** oda no'suz ücretli sipariş ve rezerve stoğun başka çıkışla tüketilmesi mevcut kodda ölçülür · oda no'suz ücretli ret · konaklamasız oda ret · QR onay bekliyor → hazırlığa geçemez · onay/ret · fiyat değişti ret · fiyat anlık görüntüsü folyoya · teslim iki kez → tek tüketim + tek borç · folyo kapalıyken teslim tümden geri · eşzamanlı son birim → tek başarı (+ kilitsiz negatif kontrol) · **bar yetkisi olmayan depo kullanıcısının** çıkışı rezerve stoğa inemez (Z1; + korumasız negatif kontrol) · rezervasyonsuz depoda davranış değişmedi · hazırlanmış iptal → zayi · yeni iptal → serbest · depo-otel uyuşmazlığı ret · 811 personeli 810 siparişine dokunamaz · pasif kullanıcı ret · `bar_masa_yetki_kapsami` otel kapsamı ve pasif kullanıcı (Z3) · anon/iç fonksiyon erişimi kapalı |
| 2 | `scripts/bar-a2-ikmal-taslak.test.mjs` | gün sınırı (varsayılan V4 ve bar bazında farklı saat) · yalnız satış tüketimi (Ö4) · yeniden üretim elle değişikliği korur · kaptan miktar değiştirir/ekler/siler · düzenleme stok ve stok hareketi yazmaz · gönderilen talep kilitli · başka barın kaptanı reddedilir · pilot kapalı bar reddedilir |
| 3 | `scripts/bar-a3-pazar-ilavesi.test.mjs` | Cuma 23:30 ve Cumartesi 01:30 teslimleri Cuma talebinde · pazar ilavesi Cumartesi 09:00'da da girilebilir (Ö3) · Pazar günü girilemez · yalnız Cuma operasyonuna · ikisi ayrı satır ve ikisi de Cumartesi teslim · Perşembe'de pazar ilavesi ret |
| 4 | `scripts/bar-a4-teslim-kabul.test.mjs` | onay stok değiştirmez · sevk merkezden düşer, bar değişmez · kabul yalnız kabul edileni ekler · kısmi sevk + kısmi kabul izlenir · onayı aşan sevk ret · kabul iki kez ret · fark geri al / kayıp · depo yetersiz → ret, 0'a kırpma yok · eşzamanlı çift kabul tek sonuç |

## Kapsam dışı

- Mevcut bar modülünün yeniden kurulması; müşteri projesinin şeması (yalnız Edge Function değişir).
- `bar-masa-yonetimi.html` içindeki olası XSS (bulgu 8), `menu.alibeyclub.com`, hız sınırı,
  rezervasyon zaman aşımı, kuyruk ekranının sayfalanması — ayrı iş olarak önerilecek.
- Diğer departmanların iç talep akışı.
- Reçeteli ürün yönetim ekranı.
- Üretime uygulama: her aşama ayrı bir **`CANLIYA UYGULA`** onayına bağlıdır.

## Açık risk ve varsayımlar

1. **Depo ↔ otel eşleşmesi** önek sözleşmesine dayanır; ERP'de depo ana tablosu yok.
2. **Geçmiş kalemlerin fiyatı** bilinemez; geçişte güncel fiyatla doldurulur ve raporlanır.
3. **Sayım kısıtı** (1.5, Z2): kullanıcı kabulü bekliyor; kabul edilmezse A1 kapsamı değişir.
4. **Edge Function dağıtımı** Dashboard'dan elle yapılıyor (CLI yok); canlı adlar
   `hyper-api` / `rapid-handler` korunur. Çalışma zamanı yerelde sınanamaz (Z3).
5. **Pilot bar** kodu henüz verilmedi; Aşama 2'den önce gerekir, `bar_ayarlari.ikmal_pilot` ile açılır.

## Aşama 1'e geçmeden kesinleşmesi gerekenler

Aşama 1 kodunu doğrudan etkileyenler yalnız şunlardır; diğer açık tercihler (V2, V3, Ö3, Ö4,
Ö5) Aşama 2–4'ü etkiler ve o aşamalardan önce kesinleştirilebilir.

| # | Konu | Aşama 1'e etkisi |
|---|---|---|
| V1 | Oda numarasına ek kanıt | Onay adımı, `oda_onay_durumu` sütunu, kuyruk ekranı butonları. PIN seçilirse PMS de değişir. |
| Ö1 | Garson siparişinin onaylı sayılması | `bar_siparis_olustur` personel dalı. |
| Ö2 | Aşama 1'in tüm barlara uygulanması | Yayın kapsamı (kod değişmez). |
| Ö6 | Folyo kapalıysa iptal + zayi | Hata mesajı ve kuyruk akışı. |
| Z2 | Sayım kısıtının kabulü | Kabul edilmezse `stok_sayim_uygula` A1'e eklenir ve stok ekranı değişir. |
| V4 | 06:00 varsayılanı | Tüketim kayıtlarının `operasyon_gunu`'nu belirler; değer değişirse yalnız varsayılan değişir. |
