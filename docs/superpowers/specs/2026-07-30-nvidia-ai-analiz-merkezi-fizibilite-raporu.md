# NVIDIA Yapay Zekâ Destekli "Akıllı Veri Analiz Merkezi" — Fizibilite ve Uygulama Planı Raporu

> **Durum:** Salt okunur analiz. Hiçbir dosya/DB/migration değiştirilmedi. Uygulama öncesi kullanıcı onayı bekleniyor.
> **Kapsam:** Ana Araz ERP Supabase projesi (`D:\erp`). Bar modülünün ayrı "müşteri" Supabase projesi (`musteri-projesi/`) bu analizin kapsamı dışında bırakıldı — orası kimlik doğrulamasız QR sipariş verisi tutuyor, analiz merkezinin veri kaynağı olarak uygun değil.
> **Sınıflandırma anahtarı:** 🟢 Doğrulanmış (dosyada/kodda doğrudan görüldü) · 🟡 Güçlü olasılık (kanıt var ama canlı DB'de teyit edilmedi) · 🔴 İnceleme gerekli (varsayım, doğrulanmamış)

---

## 1. Yönetici Özeti

Araz ERP, 51 bağımsız HTML sayfası ve ~50 Supabase tablosu üzerine kurulu, iki oteli (810/811) tek merkezden yöneten bir depo/muhasebe sistemi. Mevcut "analiz" tamamen **istemci tarafında JavaScript ile** yapılıyor (7 dosyada 36+ yerde `select=*` çekip JS'te toplama) — sunucu tarafında hiçbir analitik SQL view/RPC yok. Bu, NVIDIA destekli bir analiz merkezi için hem fırsat hem risk demek: **fırsat**, çünkü sıfırdan temiz bir SQL-view katmanı kurmak mevcut hiçbir şeyi bozmaz (üstüne ekleme); **risk**, çünkü mimari kurallarınızın gerektirdiği "hesaplamalar SQL'de yapılsın, AI sadece yorumlasın" ilkesi bu tabana göre büyük bir sapma, sıfırdan bir view/RPC katmanı inşa etmek gerekiyor.

İki **kritik, konu dışı ama önemli** güvenlik bulgusu ortaya çıktı (bkz. Bölüm 8) — analiz merkezini kurmadan önce bile ele alınması gereken, mevcut sistemin kendi açıkları:
- `kullanicilar` tablosu `USING(true)` ile herkese açık SELECT veriyor — düz metin PIN alanı dahil.
- Yeni RFQ tabloları (`teklif_talepleri/kalemleri/fiyatlari`) `authenticated` rolüne yetki kontrolsüz tam CRUD veriyor.
- `sayim_oturumlari`/`sayim_detaylari`/`urun_birim_donusum` RLS açık ama **hiç politika yok** — şu an kimse (service_role hariç) bu tablolara REST'ten erişemiyor.

Yapay zekâ mimarisi açısından en büyük yapısal engel: **`auth_yetki_var()` fonksiyonu otel/depo bazlı bir kapsam kontrolü yapmıyor** — tüm yetki modeli "modül + seviye" bazlı, "hangi otel" hiç sorulmuyor. Bu, hem mevcut sistemin hem de kurulacak AI view/RPC katmanının aynı yapısal sınırlamayı miras almasına yol açar; AI özellikleri için otel bazlı veri izolasyonu **view seviyesinde elle** eklenmeli (aşağıda önerilen).

Önerilen ilk sürüm (Bölüm 18-19'da detaylı): **3 özellik** — stok anomalisi/israf tespiti, doğal dilde yönetici sorgulama, otomatik yönetici raporu — sadece **okuma amaçlı 6-8 yeni SQL view + 2-3 RPC + 1 kesinlik/güvenlik katmanlı NVIDIA çağrı köprüsü** ile, mevcut hiçbir tabloyu/dosyayı değiştirmeden kurulabilir.

---

## 2. İncelenen Dosyalar

| Kategori | Dosyalar |
|---|---|
| Kural/kapsam | `CLAUDE.md`, `D:\ERP-Bilgi-Haritasi\99-AI\Calisma-Kurallari.md` |
| Ana şema | `docs/kurulum/01-sema-dokumu.sql` (3600+ satır), `docs/kurulum/02-referans-veri.sql` |
| Migration/yama | `2026-07-22-bar-01-sema.sql`, `2026-07-22-bar-02-rpc.sql`, `2026-07-26-guvenlik-siki-rls.sql`, `2026-07-26-teklif-toplama-tablolar.sql`, `2026-07-26-urun-siniflandirma-sema.sql`, `2026-07-26-urun-sistem-fiyat.sql`, `2026-07-26-urunler-yazma-rls.sql`, `2026-07-27-pin-hash-faz1-hazirlik.sql`, `2026-07-27-pin-tam-eslesme.sql`, `2026-07-30-koli-etiketleri-rls-duzelt.sql` |
| Mevcut analiz ekranları | `trend-raporlama.html`, `muhasebe-raporlar.html`, `mal-kabul-izleme.html`, `satin-alma-skorkart.html`, `index.html` (`loadKpiler()`) |
| Referans veri | `otel-config.js` (otel/depo sabitleri) |
| Kapsam dışı bırakılan | `docs/kurulum/musteri-projesi/*` (ayrı Supabase projesi, Bar müşteri tarafı) |

---

## 3. Mevcut Veri Mimarisi

- **Backend:** Supabase (Postgres + PostgREST + Auth). Build sistemi yok — her HTML sayfası kendi `fetch()` çağrılarını doğrudan REST endpoint'lerine yapıyor.
- **Yetki modeli:** İki katmanlı — `kullanicilar.rol` (basit enum, sayfa erişimi) + `kullanicilar.rol_id → yetki_matrisi` (modül×seviye, ince taneli). 🟢
- **Analitik desen:** Sunucu tarafı agregasyon **yok**. `muhasebe-raporlar.html` 7 tabloyu `Promise.all` ile tam çekip istemcide `hesapBakiyesi()`/`anaSinifToplami()` ile topluyor; `satin-alma-skorkart.html` 3 tabloyu tam çekip JS'te skor hesaplıyor. RPC kullanımı sadece 7 dosyada ve hepsi **transactional yazma** (`stok_ekle`, `stok_transfer`, `bar_siparis_*`) — hiç analitik RPC/view yok. 🟢
- **Otel/depo referansı:** Veritabanında yok. `otel_id` sadece bir ENUM tipi (`'810'|'811'`). Depo kodları, isimler, bar depoları tamamı `otel-config.js`'de JS sabiti. 🟢
- **Çoklu-Supabase-proje mimarisi:** Bar modülü ayrı bir "müşteri" projesine sahip (QR ile kimlik doğrulamasız erişim) — analiz merkezi bu projeye dokunmamalı.
- **PWA + service worker** (`sw.js`, network-first) — analiz ekranının da bu şemsiyeye gireceği varsayılıyor.

---

## 4. İlgili Tablolar ve Aralarındaki İlişkiler

### 4.1 Stok/Mal Kabul/Sipariş kümesi
```
urunler (kod PK)
  ├─ stok (urun_kodu, depo_kodu) UNIQUE — anlık miktar
  ├─ stok_hareketleri (urun_kodu, depo_kodu, tip, miktar, tarih) — hareket log
  ├─ stok_minimumlar (urun_kodu, depo_kodu) UNIQUE — min seviye
  ├─ urun_birim_donusum (urun_kodu) UNIQUE — büyük birim çarpanı
  └─ urun_siniflandirma (urun_kodu) UNIQUE → urun_alt_gruplari → urun_ana_gruplari

mal_kabuller (id PK, mk_no UNIQUE)
  ├─ mal_kabul_urunleri (mk_id FK, CASCADE)
  ├─ koli_etiketleri (mk_id FK, mk_urun_id FK, CASCADE) — QR/koli bazlı iz sürme
  ├─ skt_kayitlari (mk_id FK, SET NULL)
  └─ uygunsuzluklar (mk_id FK, SET NULL)

siparisler (siparis_no PK — iş anahtarı, uuid değil)
  └─ siparis_kalemleri (siparis_no FK, CASCADE)

ic_talepler (id bigint) ──┐
satin_alma_talepleri (id uuid) ──┴─→ İKİ PARALEL, BAĞIMSIZ talep akışı (bkz. Bölüm 7)

sayim_oturumlari (id) ─→ sayim_detaylari (oturum_id FK, ON DELETE davranışı belirtilmemiş)
```

### 4.2 Fiyat/Fatura/Muhasebe kümesi
```
cariler (id, kod UNIQUE, tip: tedarikci|musteri|her_ikisi) — tedarikçi VE müşteri TEK tabloda
  ├─ cari_hareketler (cari_id FK, RESTRICT)
  ├─ faturalar (cari_id FK) → fatura_kalemleri (fatura_id FK, CASCADE)
  ├─ cek_senetler (cari_id FK)
  └─ tedarikci_urun_eslesme (cari_id FK NULLABLE, urun_kodu FK) — cari kaydı olmayan tedarikçi de mümkün

hesap_plani (kod PK, ust_kod self-FK)
  ├─ cariler.hesap_kodu FK
  └─ yevmiye_kalemleri (fis_id FK → yevmiye_fisler, CASCADE) — borç=alacak CHECK, tek yön CHECK

Fiyat kaynakları (tek bir "ürün fiyatı" alanı YOK, 5 farklı yerde):
  urunler.sistem_fiyat (manuel referans)
  VIEW urun_fifo_fiyat (koli_etiketleri üzerinden, en son giren FIFO)
  VIEW urun_guncel_fiyat (fatura_kalemleri üzerinden, en son alış faturası)
  siparis_kalemleri.tahmini_fiyat / birim_fiyat
  teklif_fiyatlari.birim_fiyat (RFQ)
```

### 4.3 RFQ — ESKİ vs YENİ şema çakışması (Bölüm 6'da detay)
`01-sema-dokumu.sql`'deki 4 tablolu eski RFQ şeması (`teklif_talepleri` eski hali + `teklif_talep_kalemleri` + `tedarikci_teklifler` + `tedarikci_teklif_kalemleri`), `2026-07-26-teklif-toplama-tablolar.sql` tarafından `DROP TABLE CASCADE` ile silinip 3 tablolu yeni şemayla (`teklif_talepleri` yeniden tanımlı + `teklif_kalemleri` + `teklif_fiyatlari`) değiştiriliyor. **Analiz merkezi tasarımı YENİ şemayı esas almalı.** 🟡 (migration dosyasının canlıda gerçekten uygulandığı doğrulanmadı)

### 4.4 Otel/Depo — DB'de tablo yok
`otel_id` her yerde ENUM (`'810'|'811'`), depo kodları serbest `text`. AI view'ları otel/depo **isimlerini** göstermek için `otel-config.js`'deki `OTEL_ISIMLERI`/`MERKEZI_DEPO` eşlemesini SQL'de tekrar üretmek zorunda (CASE WHEN ile) — tek doğruluk kaynağı JS'te, DB'de değil. 🟢

---

## 5. Kullanılabilir Veri Alanları

AI özellikleri için doğrudan kullanılabilir, güvenilir alanlar:

| Alan grubu | Kaynak | Not |
|---|---|---|
| Stok anlık durumu | `stok.miktar`, `stok_minimumlar.min_miktar` | Güncel, `guncelleme_tarihi` var |
| Stok hareket geçmişi | `stok_hareketleri` (tip, miktar, tarih, kaynak_depo_kodu) | Zaman serisi analiz için ana kaynak |
| Koli bazlı iz sürme | `koli_etiketleri` (durum, skt_tarihi, olusturma_tarihi, cikis_tarihi) | FEFO/israf analizi için zengin, taze veri (bu oturumda RLS düzeltildi) |
| SKT takibi | `skt_kayitlari` (skt_tarihi, durum) | Doğrudan "yaklaşan SKT" sorgusu için hazır |
| Mal kabul→fatura→sipariş zinciri | `mal_kabuller`↔`siparisler`↔`faturalar` (serbest metin/no bazlı, çoğu FK değil) | Karşılaştırma mümkün ama FK'siz JOIN gerekiyor (bkz. Bölüm 6) |
| Tedarikçi performans girdisi | `mal_kabuller.tarih` − `siparisler.tarih`, `uygunsuzluklar` oranı | `satin-alma-skorkart.html` zaten bu deseni kullanıyor, referans alınabilir |
| Reçete/food-cost | `receteler`, `recete_tuketimleri.food_cost_yuzde` | Zaten `trend-raporlama.html`'de kullanılıyor |
| Onay geçmişi | `talep_onay_gecmisi`, `sayim_oturumlari.durum` | Süreç/gecikme analizi için |

---

## 6. Eksik veya Güvenilmez Veri Alanları

1. **🟢 Şema dökümü güncel değil**: `01-sema-dokumu.sql`, 3 adet 2026-07-26 migration'ının (ürün sınıflandırma, sistem fiyat, RFQ yeniden tasarımı) uygulanmadığı bir durumu yansıtıyor. AI view'ları tasarlarken hangi şemanın canlıda geçerli olduğu **doğrulanmalı** — aksi halde view'lar var olmayan/silinmiş tablolara referans verebilir.
2. **🟢 `stok_ekle()`/`stok_transfer()` RPC'leri `stok_hareketleri` yazmıyor**: stok miktarı değişirken hareket log'u AYRI (muhtemelen JS tarafında) yazılıyor. Bu iki yazımın senkron kalacağının garantisi yok — bir hata/kesinti durumunda `stok.miktar` ile `stok_hareketleri` toplamı arasında sessiz sapma oluşabilir. **Stok anomalisi tespiti bu sapmayı normal veri sanabilir.** 🟡
3. **🟢 `stok_transfer()` yetersiz-bakiye kontrolü yok**: kaynak depoda `greatest(0, miktar - p_miktar)` — bakiye yetersizse sessizce 0'a çeker, hedefe yine tam miktar geçer. Kaynak+hedef toplamı bozulabilir. Anomali tespiti bunu ayrıca kontrol etmeli.
4. **🟢 İki paralel talep akışı**: `ic_talepler`/`ic_talep_kalemleri` (bigint PK, departman bazlı) ve `satin_alma_talepleri`/`satin_alma_talep_kalemleri` (uuid PK, `ic_talep` yetki modülü farklı) — birbirinden bağımsız iki tablo seti. "Hangi outlet normalden fazla sipariş verdi" gibi bir soru için HANGİ tablonun kullanılacağı net değil, muhtemelen ikisi de kısmi veri taşıyor. 🔴 İnceleme gerekli — hangi modülün hangi tabloyu kullandığı JS koduna bakılmadan kesinleşmiyor (bu analiz JS dosyalarını taramadı, sadece SQL şemasını).
5. **🟡 Mal Kabul ↔ Fatura ↔ Sipariş bağı FK'siz**: `mal_kabuller.muhasebe_fatura_id` **bigint** ama `faturalar.id` **uuid** — tip uyuşmazlığı, gerçek bir FK değil, muhtemelen eski/hatalı alan. `siparisler.muhasebe_fatura_id uuid` da FK tanımlı değil. "Sipariş-fatura-mal kabul miktar farkı" özelliği bu üçlü eşleştirmeyi **serbest metin alanlarla (fatura_no, siparis_no, ln_siparis_no)** yapmak zorunda — kırılgan.
6. **🟢 `ln_siparisler.tarih` text tipinde** (date değil) — zaman serisi/tarih aralığı sorgularında ekstra parse/cast gerektirir, hatalı formatlı veri sessizce sıralamayı bozabilir.
7. **🟢 Otel/depo isim eşlemesi DB'de yok**: SQL view'ları "Ali Bey Club Manavgat" gibi okunur isimler üretmek için JS sabitini SQL'e CASE WHEN olarak kopyalamak zorunda — `otel-config.js` değişirse view senkronsuz kalır.
8. **🟡 `sayim_oturumlari.otel_id` text, enum değil** — diğer tablolardaki `otel_id` ENUM'uyla tip tutarsızlığı, JOIN'lerde örtük cast riski.

---

## 7. Veri Kalitesi Problemleri

- **Soft-delete tutarsız**: bazı tablolarda `silindi boolean`, bazılarında böyle bir alan yok, fiziksel silme muhtemelen bazı yollarla mümkün (DELETE politikası olmayan tablolarda REST üzerinden imkansız ama RPC/service_role üzerinden mümkün olabilir).
- **Denormalize kopyalar senkron riski**: `faturalar.cari_ad` (cariler.ad'ın kopyası), `mal_kabuller.firma_ad` (cariler'e FK değil, tamamen serbest metin) — cari adı değişirse geçmiş kayıtlar eski adı taşımaya devam eder, bu ANOMALİ DEĞİL ama AI'nın "aynı tedarikçi" eşleştirmesi bunu yanlış yorumlayabilir (isim varyasyonları nedeniyle iki farklı tedarikçi sanabilir).
- **`urunler.grup` FK'siz**: `urun_ana_gruplari.ana_grup_kod`'a serbest metin eşleşme, referans bütünlüğü DB seviyesinde yok.
- **Fiyat kaynağı çoğulluğu**: aynı ürün için 3-4 farklı fiyat alanı (sistem_fiyat, FIFO view, güncel-alış view, sipariş tahmini) — "gerçek fiyat" sorgusu hangi kaynağı kullanacağını açıkça belirtmezse tutarsız cevap riski taşır (Bölüm 12'de SQL view önerisiyle çözülüyor).

---

## 8. Güvenlik ve RLS Riskleri

Bu bölüm, AI analiz merkezinin kapsamı dışında ama araştırma sırasında ortaya çıktı; Calisma-Kurallari.md'nin "kod ile çelişen/riskli bulgu sessizce geçilmez" ilkesi gereği raporlanıyor.

| # | Öncelik | Bulgu | Kanıt |
|---|---|---|---|
| S1 | **P0** | `kullanicilar` SELECT `USING(true)`, TO kısıtı yok — düz metin `pin` + `pin_hash` dahil tüm personel kaydı herkese açık okunabilir. PIN, Supabase Auth şifresi olarak da kullanılıyor → **hesap ele geçirme riski**. | `01-sema-dokumu.sql:2861` |
| S2 | **P0** | `ln_siparisler` üzerinde `anon_all_ln_siparisler` FOR ALL `USING(true) WITH CHECK(true)` — potansiyel olarak giriş yapmamış kullanıcılar bile tam CRUD yapabilir. | RLS envanteri (agent 3) |
| S3 | **P1** | Yeni RFQ tabloları (`teklif_talepleri/kalemleri/fiyatlari`) `authenticated` rolüne yetki kontrolsüz tam CRUD veriyor — herhangi bir modülde yetkisi olmayan herhangi bir giriş yapmış kullanıcı tedarikçi fiyat tekliflerini okuyup değiştirebilir/silebilir. | `2026-07-26-teklif-toplama-tablolar.sql` + `2026-07-26-guvenlik-siki-rls.sql` (sadece anon revoke edilmiş) |
| S4 | **P1 (operasyonel kırıcı)** | `sayim_oturumlari`, `sayim_detaylari`, `urun_birim_donusum` — RLS açık, **hiç politika yok**. Şu an service_role dışında hiçbir rol bu tablolara REST'ten erişemiyor. **Bu oturumda eklenen Sayım QR özelliği de doğrudan etkileniyor.** | Bağımsız doğrulandı (grep, bu rapor) |
| S5 | **P2** | `pin_ile_kullanici_ara()` hâlâ anon+authenticated execute yetkili, sunucu tarafı rate-limit yok (Faz 1 hazırlığı var ama devrede değil). | `2026-07-27-pin-tam-eslesme.sql` |
| S6 | **SİSTEMİK, P0 (AI mimarisini doğrudan etkiler)** | `auth_yetki_var()` **otel_id/depo_kodu kontrolü yapmıyor** — sadece modül+seviye. 810 nolu otelde `stok_takip:kayit` yetkisi olan biri 811'in tüm stok/fatura/cari/personel verisini görüp değiştirebilir. | `01-sema-dokumu.sql:262-280`, bağımsız doğrulandı |

**S6, bu raporun asıl konusuyla doğrudan kesişiyor**: AI view/RPC katmanı, DB'nin kendisinde olmayan otel izolasyonunu **view seviyesinde elle eklemek zorunda** kalacak — yoksa "Park Otel'de tüketim neden yükseldi" sorusuna cevap veren bir view, aynı zamanda yetkisi olmayan bir kullanıcının diğer otelin verisini de görmesine kapı aralar.

---

## 9-13. Uygulanabilir Yapay Zekâ Özellikleri — Detaylı Analiz

Her özellik için: uygulanabilirlik, gerekli tablo/alan, örnek giriş/çıktı, SQL'in yapacağı hesaplama, NVIDIA modelinin yapacağı yorumlama.

### 9.1 Doğal dilde ERP sorgulama — 🟢 Uygulanabilir (v1 kapsamında)

**Gerekli tablolar/alanlar:** `stok`, `stok_hareketleri`, `urunler`, `skt_kayitlari`, `siparisler`/`siparis_kalemleri`, otel/depo eşlemesi (view'da CASE WHEN).

**Örnek giriş/çıktı:**
- Giriş: *"Bu ay en çok tüketimi artan ürünler hangileri?"*
- SQL katmanı üretir: geçen ay vs bu ay `stok_hareketleri` (tip=çıkış) toplamı, ürün bazlı, % artış sıralı, ilk 10.
- NVIDIA modeline giden veri: **sadece bu hesaplanmış 10 satırlık tablo** (ürün adı, geçen ay miktar, bu ay miktar, % artış) — ham hareket satırları değil.
- Model çıktısı: bu tabloyu doğal dilde özetler + varsa dikkat çeken desenleri işaret eder ("Peynir Kaşar tüketimi %340 arttı, bu diğer ürünlerden belirgin şekilde yüksek").

**SQL'in yapacağı:** Tüm agregasyon, filtreleme, sıralama, % hesaplama, eşik uygulama.
**NVIDIA'nın yapacağı:** Sadece SQL'in ürettiği küçük, sınırlı, sayısal tabloyu doğal dile çevirme + yüzeysel örüntü belirtme. **Hiçbir sayıyı kendi hesaplamıyor.**

**Mimari kısıtlama:** Kullanıcının doğal dil sorusunu hangi SQL view/RPC'ye eşleyeceği ayrı bir sorun — 2 yaklaşım: (a) sabit bir soru-kalıp kütüphanesi (güvenli, öngörülebilir, ama esnek değil), (b) NVIDIA modeline "bu view'lardan hangisini + hangi parametrelerle çağırmalıyım" kararını verdirip sonra SQL'i BUNLAR çalıştırsın (fonksiyon çağırma / tool-use deseni — daha esnek ama modelin yanlış view/parametre seçme riski var, mutlaka **izin verilen view listesiyle sınırlı, whitelist bazlı** olmalı). v1 için (a) önerilir.

### 9.2 Stok anomalisi ve kaçak tespiti — 🟢 Uygulanabilir (v1 kapsamında), kısmen 🟡

| Alt özellik | Uygulanabilirlik | Not |
|---|---|---|
| Olağan dışı tüketim | 🟢 | `stok_hareketleri` üzerinden istatistiksel (ör. son 30 gün ortalama+std sapma) — mevcut hiçbir yerde yok, SQL'de kurulmalı |
| Negatif stok | 🟢 | `stok.miktar < 0` doğrudan sorgulanabilir — ama `stok_ekle()`/`stok_transfer()` zaten `greatest(0,...)` ile negatife düşmeyi engelliyor, bu yüzden **negatif stok DB'de muhtemelen hiç oluşmaz**; asıl değerli olan "sessizce 0'a çekilen" transferleri yakalamak (Bölüm 6, madde 3) |
| Satış/siparişle uyuşmayan çıkış | 🔴 İnceleme gerekli | `stok_hareketleri.tip`'in olası değerleri ve hangi işlemin hangi tip'i yazdığı JS koduna bakmadan netleşmiyor |
| Yanlış koli/adet/kg/litre dönüşümü | 🟡 | `urun_birim_donusum.carpan` ile beklenen değerden sapan koli girişleri tespit edilebilir — ama bu tablo RLS'siz kilitli (S4), önce açılmalı |
| Yinelenen hareket | 🟢 | aynı urun+depo+miktar+kısa zaman aralığında tekrar eden `stok_hareketleri` satırları — SQL window function ile kolay |
| Kullanıcı/outlet bazlı şüpheli işlem | 🔴 İnceleme gerekli | `stok_hareketleri`'nde işlemi yapan kullanıcı alanı şemada görülmedi (agent taramasında yoktu) — JS/audit_log'a bakmadan doğrulanamaz |
| İki otel arası açıklanamayan fark | 🟡 | Mümkün ama S6 (otel izolasyonu yok) nedeniyle view'ın kendisi dikkatli yazılmalı |

### 9.3 İsraf ve SKT analizi — 🟢 Uygulanabilir (v1 kapsamında)

`skt_kayitlari` + `koli_etiketleri` zaten bu amaç için tasarlanmış zengin veri taşıyor (durum, skt_tarihi, olusturma_tarihi, cikis_tarihi). FEFO'ya aykırı çıkış tespiti zaten `stok-takip.html`'nin `fefoKontrolEt()` fonksiyonunda MANTIK olarak var (giriş anında uyarıyor) — ama bu bir **RAPOR/analiz** değil, **giriş anı kontrolü**; geçmişe dönük "kaç kez FEFO'ya aykırı çıkış yapıldı" sorgusu için SQL view yok, kurulmalı.

### 9.4 Akıllı sipariş tahmini — 🟡 Kısmen uygulanabilir, dikkatli sınırlanmalı

Geçmiş tüketim + güncel stok + açık siparişler hep var. Ama "sezon" ve "haftanın günü" bazlı gerçek bir tahmin modeli, basit SQL agregasyonunun ötesinde — bu, mimari kuralınızdaki "sayısal hesaplamalar SQL/RPC'de yapılmalı" ilkesiyle gerilim yaratıyor: gerçek bir tahmin modeli (mevsimsellik, trend) saf SQL'de zayıf kalır. Önerilen yaklaşım: SQL basit bir hareketli ortalama + güvenli stok hesaplasın, NVIDIA modeli bunu **yorumlasın ve gerekçelendirsin** ama "önerilen miktar" rakamının kendisi SQL'den gelsin, model bunu değiştirmesin — sadece açıklasın. **v1 kapsamı dışında bırakılması önerilir** (kullanıcının kendi öncelik listesinde de yok).

### 9.5 Fatura/teklif/mal kabul karşılaştırması — 🟡 Kısmen uygulanabilir

Veri var ama Bölüm 6 madde 5'teki FK'siz bağlantı sorunu nedeniyle güvenilirliği düşük — serbest metin eşleştirme (fatura_no/siparis_no) yanlış eşleştirme riski taşır. **v1 kapsamı dışında** (kullanıcı önceliğinde de yok), v2'de FK bütünlüğü önce düzeltilmeli.

### 9.6 Otomatik yönetici raporu — 🟢 Uygulanabilir (v1 kapsamında)

Diğer 2 v1 özelliğinin (anomali tespiti + doğal dil sorgulama) ürettiği view'ların bir araya getirilmiş, zamanlanmış (günlük/haftalık) halinden ibaret — ayrı bir veri ihtiyacı yok, sadece orkestrasyon.

---

## 14. Gerekli View, RPC ve Edge Function Önerileri (v1 — 3 öncelikli özellik için)

Hepsi **salt okunur** (SELECT-only view/RPC, hiçbir yazma yapmaz — mimari kuralla tam uyumlu).

```sql
-- 1) Otel/depo isim eşlemesi (JS sabitinin SQL yansıması — tek yerde tanımlı, diğer view'lar bunu kullanır)
CREATE VIEW ai_otel_depo_ref AS
SELECT '810' AS otel_id, 'Ali Bey Club Manavgat' AS otel_ad, '100' AS merkezi_depo
UNION ALL SELECT '811', 'Ali Bey Resort Sorgun', '300';

-- 2) Ürün bazlı tüketim trendi (dönem karşılaştırmalı) — "en çok artan ürünler" sorgusu için
CREATE VIEW ai_urun_tuketim_trend AS
SELECT urun_kodu, otel_id, depo_kodu,
       date_trunc('week', tarih) AS hafta,
       sum(miktar) FILTER (WHERE tip = 'cikis') AS toplam_cikis
FROM stok_hareketleri
GROUP BY urun_kodu, otel_id, depo_kodu, date_trunc('week', tarih);

-- 3) Stok anomali adayları (istatistiksel sapma)
CREATE VIEW ai_stok_anomali_adaylari AS
SELECT urun_kodu, depo_kodu, tarih, miktar,
       avg(miktar) OVER w AS ort_30gun, stddev(miktar) OVER w AS sapma_30gun
FROM stok_hareketleri
WINDOW w AS (PARTITION BY urun_kodu, depo_kodu ORDER BY tarih
             ROWS BETWEEN 30 PRECEDING AND 1 PRECEDING);
-- |miktar - ort_30gun| > 2*sapma_30gun olan satırlar "aday" — eşik RPC parametresi olmalı

-- 4) Yaklaşan SKT + FEFO ihlali geçmişi
CREATE VIEW ai_skt_risk AS
SELECT s.*, u.ad AS urun_adi, (s.skt_tarihi - CURRENT_DATE) AS kalan_gun
FROM skt_kayitlari s JOIN urunler u ON u.kod = s.urun_kodu
WHERE s.durum = 'aktif';

-- 5) Tedarikçi/mal kabul teslim performansı (satin-alma-skorkart.html'in SQL karşılığı)
CREATE VIEW ai_tedarikci_performans AS
SELECT c.ad AS tedarikci, mk.otel_id,
       count(*) AS toplam_kabul,
       avg(mk.tarih - s.tarih) FILTER (WHERE s.tarih IS NOT NULL) AS ort_teslimat_gun,
       count(uy.id)::numeric / NULLIF(count(*),0) AS uygunsuzluk_orani
FROM mal_kabuller mk
LEFT JOIN cariler c ON c.ad = mk.firma_ad
LEFT JOIN siparisler s ON s.siparis_no = mk.ln_siparis_no
LEFT JOIN uygunsuzluklar uy ON uy.mk_id = mk.id
GROUP BY c.ad, mk.otel_id;

-- 6) Otel karşılaştırmalı günlük özet (yönetici raporu ana kaynağı)
CREATE VIEW ai_gunluk_ozet AS
SELECT otel_id, CURRENT_DATE AS rapor_tarihi,
       (SELECT count(*) FROM mal_kabuller WHERE durum='bekleyen' AND otel_id = o.otel_id) AS bekleyen_mal_kabul,
       (SELECT count(*) FROM skt_kayitlari WHERE durum='aktif' AND otel_id = o.otel_id
          AND skt_tarihi BETWEEN CURRENT_DATE AND CURRENT_DATE + 14) AS skt_kritik
FROM (SELECT DISTINCT otel_id FROM mal_kabuller) o;
```

**RPC'ler (parametreli, güvenlik sınırlı):**
```sql
-- Otel izolasyonu view SEVİYESİNDE değil, RPC parametresi + auth_yetki_var kontrolüyle sağlanır:
CREATE FUNCTION ai_rapor_getir(p_otel_id text, p_baslangic date, p_bitis date)
RETURNS TABLE(...) SECURITY DEFINER AS $$
  -- içeride: IF NOT auth_yetki_var('trend_raporlama','goruntule') THEN RAISE EXCEPTION 'yetkisiz'; END IF;
  -- + çağıranın kendi otel yetkisiyle p_otel_id eşleşmesi elle kontrol edilmeli (S6 nedeniyle)
$$ LANGUAGE plpgsql;
```

**Edge Function (NVIDIA köprüsü):** Yeni bir `ai-analiz-sorgula` Edge Function — mevcut Bar modülünün JWT-relay desenini (`siparis-gonder` fonksiyonundaki gibi) birebir tekrar kullanır: gelen isteğin JWT'sini `auth_yetki_var()` ile doğrular, izin verilen view/RPC'lerden SADECE whitelist'teki birini çağırır, sonucu NVIDIA API'sine gönderir, **service role anahtarı Edge Function içinde kalır, istemciye asla gitmez**.

---

## 15. Önerilen Ekran ve Kullanıcı Akışı

Yeni bir modül: `analiz-merkezi.html` (mevcut desene uygun, bağımsız dosya, `nav-drawer.js`/sekme sistemine dahil edilir).

1. **Sohbet kutusu** (doğal dil sorgulama) — üstte, ChatGPT-tarzı basit arayüz, "Doğrulanmış bulgu" etiketli cevaplar.
2. **Günlük özet kartı** — sayfa açılışında otomatik yüklenir (view #6'dan), otel karşılaştırmalı.
3. **Anomali/İsraf listesi** — filtrelenebilir, her satırda "kaynak kayda git" linki (mevcut mal-kabul-izleme.html'deki desene benzer).
4. Yetki: yeni `ai_analiz_merkezi` modül kodu, `yetki_matrisi`'ne eklenir — sadece bu yetkiye sahip roller görür.

---

## 16. P0/P1/P2 Öncelikli Riskler

| Öncelik | Risk |
|---|---|
| **P0** | S1 — `kullanicilar` herkese açık okunabiliyor (PIN dahil) |
| **P0** | S2 — `ln_siparisler` anon'a tam açık |
| **P0** | S6 — otel izolasyonu hiçbir yerde yok; AI view'ları bunu miras almamalı, elle eklenmeli |
| **P1** | S3 — yeni RFQ tabloları authenticated'e tam açık |
| **P1** | S4 — sayim_oturumlari/detaylari/urun_birim_donusum tamamen erişilemez (operasyonel kırık) |
| **P1** | Bölüm 6 madde 2-3 — stok_ekle/transfer'in hareket-log senkron riski, anomali tespitini yanıltabilir |
| **P2** | S5 — PIN arama fonksiyonunda rate-limit yok |
| **P2** | Bölüm 6 madde 5 — mal kabul/fatura/sipariş FK'siz bağ, karşılaştırma özelliğini v1 dışına iten neden |

---

## 17. Etkilenecek Dosyaların Tam Listesi (v1 uygulaması onaylanırsa)

**Yeni dosyalar (mevcut hiçbiri değişmez):**
- `docs/kurulum/2026-0X-XX-ai-analiz-views.sql` (Bölüm 14'teki view'lar)
- `docs/kurulum/2026-0X-XX-ai-analiz-rpc.sql` (RPC'ler + yetki kontrolleri)
- `docs/kurulum/ana-proje/ai-analiz-sorgula/index.ts` (yeni Edge Function)
- `analiz-merkezi.html` (yeni modül sayfası)
- `nav-drawer.js` — `ND_MODULLER`'e 1 yeni satır (mevcut desene uygun ekleme, mevcut satırlar değişmez)
- `index.html` — `MODULLER`'e 1 yeni satır (aynı desen)

**Değiştirilmesi TARTIŞMALI/opsiyonel (bu raporun kapsamı dışında, ayrı onay gerekir):**
- S1/S2/S3/S4 güvenlik düzeltmeleri (Bölüm 8) — AI özelliğiyle doğrudan ilgisiz ama aynı DB üzerinde çalışacağından önce ele alınması önerilir.

---

## 18. Aşamalı Uygulama Planı

**Faz 0 — Güvenlik ön koşulu (AI'dan bağımsız, önerilir):** S1, S2, S4'ü düzelt (S3 zaten kısmen ele alınmış). Bu olmadan AI view'ları da aynı açık üzerine inşa edilmiş olur.

**Faz 1 — SQL temel katmanı:** Bölüm 14'teki 6 view + otel-izolasyonlu RPC'ler. Hiçbir UI değişikliği yok, sadece Supabase'de test edilir (SQL Editor'de elle sorgulanarak doğrulanır).

**Faz 2 — Edge Function köprüsü:** `ai-analiz-sorgula` fonksiyonu, JWT-relay + whitelist deseniyle (Bar modülündeki kanıtlanmış desenin tekrarı).

**Faz 3 — NVIDIA entegrasyonu:** Sabit soru-kalıp kütüphanesiyle başla (esnek olmayan ama güvenli), view sonuçlarını NVIDIA'ya gönderip doğal dil özet al.

**Faz 4 — UI:** `analiz-merkezi.html` + navigasyon entegrasyonu.

**Faz 5 — Genişletme:** Doğal dil→view eşleştirmeyi model tabanlı tool-use'a geçirme (whitelist korunarak), diğer 3 özelliğin (tahmin, karşılaştırma, RFQ analizi) FK/veri kalitesi önkoşulları netleştikten sonra eklenmesi.

---

## 19. Test ve Doğrulama Planı

- Her yeni view: gerçek verideki bilinen bir örnekle (örn. bilinen bir SKT kritik ürün) elle doğrulama.
- Otel izolasyonu: 810 yetkili bir test kullanıcısıyla 811 verisinin view/RPC üzerinden GÖRÜNMEDİĞİNİ doğrulama (bu, mevcut sistemde hiç test edilmemiş bir senaryo — S6 nedeniyle özellikle kritik).
- NVIDIA'ya giden payload'ın gerçekten SADECE hesaplanmış/sınırlı veri içerdiğini, ham satır/kişisel veri içermediğini manuel inceleme.
- Yanlış/eksik veri senaryosu: `stok_hareketleri` boş bir ürün için anomali view'ının hata vermeden boş/nötr sonuç döndürmesi.
- Yük: view'ların `EXPLAIN ANALYZE` ile makul sürede döndüğü (index eksikliği varsa Bölüm 14'teki view'lara uygun index önerisi ayrıca çıkarılmalı).

---

## 20. Tahmini Geliştirme Zorluğu ve Bağımlılıklar

| Bileşen | Zorluk | Bağımlılık |
|---|---|---|
| 6 SQL view | Düşük-Orta | Şemanın canlıda 2026-07-26 migration'larıyla güncel olduğunun teyidi (Bölüm 6/madde 1) |
| Otel-izolasyonlu RPC | Orta | S6'nın nasıl ele alınacağına dair karar (view seviyesi mi, RPC parametresi mi) |
| Edge Function köprüsü | Orta | NVIDIA API entegrasyonu (bu oturumda ayrıca çalışılan LiteLLM/NVIDIA bağlantı kurulumu tamamlanmalı) |
| Sabit soru-kalıp kütüphanesi | Düşük | — |
| UI (analiz-merkezi.html) | Düşük | Mevcut sekme sistemi + nav-drawer deseni zaten var, tekrar kullanılır |
| Faz 0 güvenlik düzeltmeleri | Düşük (teknik), Yüksek (karar) | Kullanıcı onayı — ERP'nin geri kalanını etkileyebilir, bu raporun ana konusu değil ama önerilir |

**En büyük tekil risk:** S6 (otel izolasyonu yok) — bu, AI özelliklerinin "hangi otelin verisi kime gösteriliyor" sorusunu DB'nin kendisi çözmediği için, her yeni view/RPC'de **elle, tutarlı bir şekilde** yeniden çözülmesi gerekiyor. Bir view'da unutulursa, o view sessizce çapraz-otel veri sızdırır.

---

## Minimum Uygulanabilir Mimari (v1 — 3 öncelikli özellik)

```
Kullanıcı (analiz-merkezi.html)
    │  JWT ile istek
    ▼
Edge Function: ai-analiz-sorgula
    │  1) JWT doğrula + auth_yetki_var('ai_analiz_merkezi','goruntule') kontrol et
    │  2) Kullanıcının otel yetkisini çıkar (mevcut yetki_matrisi'nden)
    │  3) Sabit soru-kalıbına göre İLGİLİ VIEW'ı, kullanıcının otel_id'siyle SINIRLANDIRARAK çağır
    │     (service_role ile, ama WHERE otel_id = <kullanıcının yetkili olduğu otel> HER ZAMAN eklenir)
    │  4) Sonucu (küçük, sınırlı tablo) NVIDIA API'sine gönder
    ▼
NVIDIA (z-ai/glm-5.2) — SADECE yorumlama, hiçbir yazma/hesaplama yok
    │
    ▼
Doğal dil cevap + kaynak view/satır referansı → kullanıcıya
```

Stok/sipariş/ödeme hiçbir noktada AI tarafından değiştirilmiyor — mimari kural tam uyumlu. Tüm sayısal doğruluk SQL view'larında, AI sadece son adımda devreye giriyor.

---

## Genel Sınıflandırma Özeti

- **🟢 Doğrulanmış (dosyada doğrudan görüldü):** Şema envanteri (Bölüm 4), mevcut analiz ekranı desenleri (Bölüm 3), RLS bulguları S1/S2/S4/S6, otel-depo referansının DB'de olmadığı.
- **🟡 Güçlü olasılık (kanıt var, canlı DB teyidi yok):** Migration'ların canlıya uygulanma durumu (Bölüm 6/1), stok_ekle/transfer senkron riskinin gerçek etkisi, S3'ün gerçek istismar edilebilirliği (grant/policy kombinasyonuna bağlı).
- **🔴 İnceleme gerekli:** İki paralel talep tablosunun (ic_talepler/satin_alma_talepleri) hangisinin hangi ekranda kullanıldığı, `stok_hareketleri.tip` değerlerinin tam listesi, kullanıcı/outlet bazlı şüpheli işlem tespiti için gereken "işlemi yapan kullanıcı" alanının nerede tutulduğu — bunların hepsi JS dosyalarının okunmasını gerektiriyor, bu analiz sadece SQL şemasını taradı.
