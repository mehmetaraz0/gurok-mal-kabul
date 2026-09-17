# Bar Güvenliği, Gün Sonu İkmal ve Teslim Kabulü — Tasarım

**Tarih:** 2026-09-17 · **Durum:** kararlar kullanıcı tarafından verildi, belge incelemede
**Kapsam dışı ilkesi:** mevcut bar modülü **yeniden kurulmaz**; tablolar, sayfalar ve Edge
Function'lar yerinde genişletilir.
**Dayanak:** `docs/BAR-MODULU-ISLEYIS.md` (2026-09-16 bulguları) · üretim şeması
`2026-09-13-post-faz2-sema-dokumu.sql` (bar/stok fonksiyon ve politikaları 09-07 dökümüyle
birebir aynı — özetle doğrulandı).

## Kullanıcı kararları

| # | Soru | Karar |
|---|---|---|
| K1 | QR'dan gelen ücretli siparişte misafir kanıtı | **Personel onayı.** Sipariş "oda onayı bekliyor" olur; kaptan/garson oda kartını görüp onaylar. Sunucu yine aktif konaklama + açık folyo arar. |
| K2 | Kaptan kimdir | **Yeni rol: Bar Kaptanı** (`bar_kaptan`). Hangi barın kaptanı olduğu ayrıca atama tablosunda tutulur. |
| K3 | Sevk edilip kabul edilmeyen miktar | **Açık fark; depo kapatır** — "geri al" (merkeze iade) ya da "kayıp olarak kapat". |
| K4 | Operasyon günü sınırı | **06:00**, bar bazında ayarlanabilir. |
| K5 | Pilot | İkmal ve kabul (Aşama 2–4) **tek barda** açılır. Aşama 1 güvenlik düzeltmesidir, tüm barlara uygulanır. |

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

## Aşama 1 — Bar ve PMS güvenliği (tüm barlar)

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
- Aynı danışma kilidini alır.
- O depo+ürün için **aktif rezervasyon > 0** ve çıkış sonrası miktar **< aktif rezervasyon**
  ise hata: `REZERVE_STOK` ("X birim bekleyen bar siparişlerine ayrılmış").
- Aktif rezervasyon **yoksa davranış bugünküyle aynıdır** (0'a kırpma dahil). Rezervasyon
  yalnız bar depolarında oluştuğu için diğer depolar ve modüller etkilenmez.
- Teslim kendi rezervasyonunu **önce** `kullanildi` yapar, sonra düşer → kendi korumasına takılmaz.

**Bilinen kısıt (bilerek kabul):** bar deposunda sayım onayı da `stok_ekle` üzerinden yazar.
Sayım, bekleyen siparişlere ayrılmış miktarın altına indiremez; ekran "önce bekleyen bar
siparişlerini teslim/iptal edin" der. Pilot operasyonunda sayım servis sonrasına alınır.

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
  döner; `ekle` ve `durum` başka otelin masası için reddedilir. Yetki `auth_yetki_var` ile,
  **çağıranın JWT'siyle** sorulur (el ile `yetki_matrisi` okuması kalkar).
- **Stok tüketimleri, ikmal talepleri, sevkler:** RLS'te `auth_yetki_var` **ve**
  `auth_otel_erisim`; iki permissive politika varsa **ikisine birden** otel şartı (bkz.
  pentest-4 dersi).

### 1.8 Pasif kullanıcı

- Ana projedeki RPC'ler zaten fail-closed: `auth_yetki_var` / `auth_otel_erisim`
  `kullanicilar.aktif is true` arar (dökümden doğrulandı).
- **`rapid-handler`** kullanıcıyı e-postadan buluyor ve `aktif`'e bakmıyor → düzeltilir:
  kimlik `auth.getUser()` + `auth_yetki_var(... 'kayit')` (pasif kullanıcıda `false`).
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
  Varsayılan gün sonu 06:00 → Cumartesi 01:30'daki teslim **Cuma** operasyon gününe aittir.
- **Bar ayarı** `bar_ayarlari`: `bar_depo_id (pk), otel_id, gun_sonu_saati time default '06:00',
  ikmal_pilot boolean default false, kaynak_depo_id` (merkez depo: 810→`810_100`, 811→`811_300`).
- **Kaptan ataması** `bar_kaptan_atamalari`: `kullanici_id, bar_depo_id, otel_id, aktif`.
  Yeni rol `bar_kaptan` ("Bar Kaptanı") + yeni modül `bar_ikmal` yetki matrisinde.

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
- **Zayi taslağa girmez** (karar metni "teslim edilmiş siparişler" diyor); kaptan gerekirse elle ekler.

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

- **Taban:** atılabilir `postgres:17` + `postgrest`; `scripts/supabase-shim.sql` +
  `2026-09-13-post-faz2-sema-dokumu.sql` (gerçek üretim fonksiyon ve politikaları) +
  sonrasında uygulanan `2026-09-14-stok-liste-ozet.sql` + aşamanın aday migration'ı.
- **Kimlikler:** gerçek `kullanicilar` satırları + `auth.users` + JWT (`sub`); otel 810 kaptanı,
  811 personeli, pasif kullanıcı, yetkisiz kullanıcı.
- **Negatif kontroller:** kritik korumalar (kilit, rezerve koruması, tekillik) kaldırıldığında
  testin **düştüğü** gösterilir — koruma olmadan da geçen test kanıt sayılmaz.
- **Eşzamanlılık:** iki ayrı bağlantıda açık işlemlerle gerçek yarış.

| Aşama | Test dosyası | Asgari senaryolar |
|---|---|---|
| 1 | `scripts/bar-guvenlik.test.mjs` | oda no'suz ücretli ret · konaklamasız oda ret · QR onay bekliyor → hazırlığa geçemez · onay/ret · fiyat değişti ret · fiyat anlık görüntüsü folyoya · teslim iki kez → tek tüketim + tek borç · folyo kapalıyken teslim tümden geri · eşzamanlı son birim → tek başarı (+ kilitsiz negatif kontrol) · stok takip çıkışı rezerve stoğa inemez · rezervasyonsuz depoda davranış değişmedi · hazırlanmış iptal → zayi tüketim · yeni iptal → serbest · depo-otel uyuşmazlığı ret · 810 personeli 811 siparişine dokunamaz · pasif kullanıcı ret · rapid-handler otel kapsamı ve pasif kullanıcı |
| 2 | `scripts/bar-ikmal-taslak.test.mjs` | 06:00 sınırı · yalnız teslim tüketimi · yeniden üretim elle değişikliği korur · kaptan miktar değiştirir/ekler/siler · düzenleme stok ve stok hareketi yazmaz · gönderilen talep kilitli · başka barın kaptanı reddedilir · pilot kapalı bar reddedilir |
| 3 | `scripts/bar-ikmal-cuma.test.mjs` | Cuma 23:30 ve Cumartesi 01:30 teslimleri Cuma talebinde · pazar ilavesi Cumartesi 09:00'da da girilebilir · Pazar günü girilemez · yalnız Cuma operasyonuna · ikisi ayrı satır ve ikisi de Cumartesi teslim · Perşembe'de pazar ilavesi ret |
| 4 | `scripts/bar-ikmal-kabul.test.mjs` | onay stok değiştirmez · sevk merkezden düşer, bar değişmez · kabul yalnız kabul edileni ekler · kısmi sevk + kısmi kabul izlenir · onayı aşan sevk ret · kabul iki kez ret · fark geri al / kayıp · depo yetersiz → ret, 0'a kırpma yok · eşzamanlı çift kabul tek sonuç |

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
3. **Sayım kısıtı** (1.5): pilot barda sayım bekleyen siparişlerden sonra yapılmalı.
4. **Edge Function dağıtımı** Dashboard'dan elle yapılıyor (CLI yok); canlı adlar
   `hyper-api` / `rapid-handler` korunur.
5. **Pilot bar** kodu uygulama öncesi kullanıcıdan alınacak; `bar_ayarlari.ikmal_pilot` ile açılır.
