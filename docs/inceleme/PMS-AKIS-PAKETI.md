# PMS akış paketi — durum raporu

**Tarih:** 2026-09-29 · **Dal:** `pms/akis-tamamlama` (yerel, **push YOK**)
**Commit'ler:** `ee4f600` · `35263dd` · `20638b6` · `21a4277` · `536e5dd` · `d786cc7`
**Model çağrısı:** 0 / 30 · **Düzeltme turu:** paket başına 1 (sınır 3)
**Push / deploy / üretim erişimi / gerçek misafir verisi:** YOK
**R11+B4 adayı (`ip1/r11-b4-entegrasyon-adayi` @ `cdc00e6`):** dokunulmadı

---

## 1. Yerelde tamamlandı ve test edildi — bağımsız inceleme bekliyor

> **Bağımsız inceleme BEKLİYOR.** Paket hazırlandı, sır taramasından geçti ve
> `536e5dd` özetlerine sabitlendi; VM'de tek adımlık hazırlık betiği root ile
> çalıştırılmayı bekliyor (§2, D3). Bu adım tamamlanmadan paket **"doğrulandı"
> sayılmaz**. Check-in bulgusunun kaydı: **yerelde düzeltildi ve test edildi;
> bağımsız inceleme ve yayın bekliyor.**

### P1 — Check-in çıkmazı düzeltildi (`ee4f600`, ürün kodu değişti)

09-25 tarihli açık bulgu doğrulandı ve **yerelde düzeltildi**; bağımsız inceleme ve yayın bekliyor. Rezervasyon ekranı oda
atamaya izin veriyordu, ama oda planı check-in listesine yalnız **aktif ataması
olmayan** rezervasyonları alıyordu ve check-in başka ekranda yoktu: "önce ata,
sonra giriş yap" yolu çıkmazdı.

Sunucu bu durumu **zaten kabul ediyordu** — `pms_check_in` güncel atama varsa
odayı ondan alır, aynı oda verilirse itiraz etmez, farklı oda verilirse
reddeder. Düzeltme **yalnızca ekranda**; şema, RPC, yetki ve RLS'e dokunulmadı.

`uygunRezervasyonlar` artık sunucunun kuralını aynalıyor:

| Durum | Ekran davranışı |
|---|---|
| Tek aktif atama, bugünü kapsıyor | yalnız **o** odada listelenir |
| Aktif atama yok | oda tipi tutan boş odalarda listelenir (eski davranış korundu) |
| Birden fazla aktif atama (tutarsız) | giriş yolu **açılmaz** |
| Atama var ama bitişi geçmiş | listelenmez (ikinci atama üretmemek için) |

**Ölçüm:** `scripts/pms-akis-ekran.test.mjs` — gerçek ekran betiği, gerçek
PostgREST, izole Docker veritabanı. Düzeltme **öncesi 6 geçti / 3 kaldı**
(A2, A4 kırmızı; A5–A8 "ölçülemedi"), **sonrası 12/12**.

Testin dürüstlüğü: tıklama yalnız modalin **sunduğu** kimlikle yapılır. İlk
kurguda `checkInYap` doğrudan çağrılmıştı ve sunucu isteği kabul ettiği için
ekran kusuru **yanlış yeşile** boyanıyordu; bu düzeltildi.

### P2 — Uçtan uca akış testi (`35263dd`, ürün kodu değişmedi)

Kullanıcının tarif ettiği zincirin tamamı tek testte, ürünün kendi yollarından:

```
misafir kaydı → rezervasyon (taslak→onaylandı; folyo OTOMATİK açıldı)
→ oda müsaitliği → ekrandan CHECK-IN → oda ücretinin folyoya işlenmesi
→ bakiye ≠ 0 iken folyo kapatma REDDİ → tahsilat → mükerrer tahsilat koruması
→ bakiye 0 → folyo kapanışı → ekrandan CHECK-OUT → oda boş/kirli
→ KİRLİ oda check-in kabul etmiyor → çıkış görevi OTOMATİK açıldı
→ sahiplen/başlat/tamamla → oda temiz → aynı oda yeni rezervasyona satılabiliyor
```

**21 ölçüm, 21 geçti.**

### P3 — Hata durumları (`20638b6`, ürün kodu değişmedi)

| Sınıf | Ölçülen ret |
|---|---|
| Çifte rezervasyon | aynı odaya çakışan ikinci atama `pms_oda_atamalari_cakisma` ile reddedildi; **çakışmayan** atama kabul edildi (kural aşırı geniş değil) |
| Mükerrer işlem | aynı rezervasyona ikinci check-in reddi; kapalı folyonun ikinci kez kapatılamaması; aynı işlem anahtarıyla ikinci tahsilatın çoğalmaması (409) |
| Yanlış oda / misafir | dolu odaya ikinci check-in reddi; ataması başka odada olan rezervasyonun **boş** başka odaya girememesi; **başka otelin** rezervasyonunun bu otelin odasına girememesi; ekranın dolu odaya yol açmaması |
| Bakiye tutarsızlığı | onayda **tek** folyo; sıfır tutarlı tahsilat reddi; kapalı folyoya yazma reddi; bakiye ≠ 0 iken kapatma reddi |

**13 ölçüm, 13 geçti.**

### P4 — Gerçek tarayıcı doğrulaması (`536e5dd`, ürün kodu değişti)

Ekranlar izole ortamda **gerçek tarayıcıda** açıldı
(`scripts/pms-tarayici-ortami.mjs`: Docker veritabanı + PostgREST + aynı
kökenden servis eden küçük sunucu). Ürün dosyaları değiştirilmedi; yalnız
`auth-guard.js` ve `supabase-config.js` test sürümüyle servis edildi.

| Ölçüm | Sonuç |
|---|---|
| Oda planı render | 6 oda doğru çizildi, durum/temizlik rozetleri doğru |
| **Atanmış rezervasyon listede mi** | Oda 201 **"Giriş (2)"** — atanmış + atamasız (düzeltme öncesi 1 olurdu) |
| Modal içeriği | "Atanmis Deneme" (atanmış) ve "Atamasiz Deneme" birlikte sunuldu |
| **Doğru odayla işlem** | Tıklamayla check-in → DB: `giris_yapildi`, oda **201** (atandığı oda), aktif atama **1** (mükerrer atama yok) |
| Check-out | Tarayıcıdan yapıldı → oda **boş/kirli**, çıkış temizliği görevi otomatik açıldı, kirli oda artık giriş sunmuyor |
| Folyo ekranı | Açıldı, folyo listesini getirdi |

**Tarayıcıda bulunan kusur (düzeltildi):** check-in modalindeki yardım metni
hâlâ eski kuralı ("odası atanmamış") anlatıyordu — ekran, artık uygulamadığı bir
kuralı kullanıcıya söylüyordu. DOM taklidi testi bunu göremezdi. Metin
düzeltildi; **A9** testi sürüklenmeyi kalıcı olarak yakalıyor (negatif kontrol:
eski metinle 12 geçti/1 kaldı, düzeltilmişle 13/0).

**Onay penceresi (`confirm`) — AÇIK KABUL MADDESİ.** Yerleşik tarayıcı
`confirm()` çağrısını bastırıp `false` döndürüyor: düğmeye basıldığında ekranda
hiçbir pencere görünmüyor (ekran görüntüsüyle doğrulandı), veritabanı değişmiyor
(`T-101 -> giris_yapildi` kaldı) ve `Return` tuşu da etkisiz. Pencereyi bastıran
tarayıcıda tıklama istemek doğrulama sayılmaz.

- İlk turda check-out akışını görebilmek için o sekmede `window.confirm`
  geçici olarak "evet" döndürecek şekilde ayarlanmıştı. **Ürün kodu
  değiştirilmedi** ve bu, onay kapısının sınandığı anlamına GELMEZ.
- **Kapanış yolu:** diyalog olaylarını destekleyen bir test tarayıcısı
  (ör. Playwright/Puppeteer) ile `dialog` olayını yakalayıp **kabul ederek**
  check-out yapmak. Depoda böyle bir sürücü yok ve yeni bağımlılık eklemek
  ayrı bir karardır; bu yüzden madde **açık** bırakıldı.
- Kapsam: yalnız `confirm` kapısı. Check-out'un kendisi hem sunucu
  sözleşmesiyle (Faz 1 Adım 3 süiti) hem uçtan uca testle hem de tarayıcıda
  (onay geçildikten sonra) doğrulanmış durumda.
### Regresyon (mevcut kabul süitleri, hiçbiri gevşetilmedi)

| Süit | Sonuç |
|---|---|
| `pms-faz1-testleri` | geçti |
| `pms-faz1-adim2-testleri` | geçti |
| `pms-faz1-adim3-testleri` (check-in/out + eşzamanlılık) | geçti |
| `pms-faz1-adim4-testleri` (folyo) | geçti |
| `pms-faz2-housekeeping-eszamanlilik` | **13 OK / 0 FAIL** |
| `scripts/check.mjs` | tüm statik kontroller geçti |

> Kat hizmetleri eşzamanlılık süiti ilk koşuda kırmızıydı. Sebep **ürün değil**,
> testin ön koşuluydu: süit `hk` adlı yerel staging konteynerini kendisi
> kurmuyor ve konteyner iki haftadır durmuştu. Konteyner başlatıldıktan sonra
> 13/13 geçti. Bu, benim değişikliğimle ilgisizdir (süit ekran dosyalarını ve
> yeni tohumu hiç kullanmıyor).

### Test kurgusunda çıkan kırmızılar — ürün kusuru değildi

Dürüstlük kaydı: koşumlar sırasında çıkan kırmızıların çoğu **testin kendi
kusuruydu** ve düzeltildi: PostgREST yol önekinin çevrilmemesi (18 sahte
kırmızı), boş dizeyi sıfır bakiye sayan yanlış yeşil, eksik gecelik fiyat,
silinen bir sorgu satırı, ve **iki ölçümün yanlış nedenle geçmesi** (sunucu
başka bir kural yüzünden reddediyordu). Süitin gerçekten ölçtüğünün kanıtı,
bu hataları yakalamış olmasıdır.

---

## 2. Karar veya değişiklik bekliyor — hiçbiri uygulanmadı

**D1 — Check-out açık bakiyeyle bloke edilmiyor.** `pms_check_out` folyo
bakiyesine bakmaz; kalan bakiyeyle çıkış mümkündür. Bu **belgelenmiş bir
tasarım kararıdır** (Adım 4, `pms_check_out`'a kasten dokunulmadı). Seçenekler:
(a) olduğu gibi kalsın; (b) ekran çıkışta bakiyeyi **uyarsın**; (c) sunucu
bloke etsin. (b) ve (c) davranış değişikliğidir ve yeni iş kuralı gerektirir →
**ayrı onay.** Bu pakette değiştirilmedi.

**D2 — Altı PMS modülü tohum verisinde yok.** `02-referans-veri.sql` 42 modül
tohumluyor; `pms_oda_tipi, pms_oda, pms_misafir, pms_rezervasyon, pms_folio,
pms_housekeeping` bu listede değil ve depodaki hiçbir `.sql` `moduller`
tablosuna satır eklemiyor. Temiz kurulumda **Ön Büro menüde hiç görünmez**.
Başlangıç verisi değişikliği → ayrı onay. **En küçük değişiklik önerisi
hazırlandı ve UYGULANMADI:** `docs/inceleme/PMS-MODUL-TOHUMLAMA-ONERISI.md`
(6 modül satırı + 26 yetki satırı, ayrı kurulum dosyası olarak; seviyeler ve
dört karar noktası orada listeli). İlk tespit:
`docs/inceleme/KURULUM-HAZIRLIK-KONTROLU.md` §3.2.

**D3 — Bağımsız Codex incelemesi: TEK ADIM BEKLİYOR.** Yetkili yol araştırıldı:
dar sudoers kuralı `kosucu ALL=(incelemeci) NOPASSWD: /usr/local/bin/kosum-incelemeci`
ajanı **parolasız** başlatır; parolayı isteyen tek şey `yonetici → kosucu`
geçişidir. B4 koşumunda bu geçiş, kimliği doğrulanmış interaktif `sudo` ile
yapılmıştı — tek fark budur. Ajanı `yonetici` (sudo grubunda) veya root altında
çalıştırmak izolasyonu zayıflatacağı için **yapılmadı**; genel parolasız sudo
**eklenmedi**.

Hazırlık paketi hazır: 8 dosya, sır taraması 0 bulgu, `2afdb99` özetlerine
sabitlendi, VM'e aktarıldı ve özet VM tarafında doğrulandı.

**Tek kullanımlık onay (2026-09-29).** Onay kimliği artık çalıştırma sırasında
üretilmiyor; bu onaya ait sabit kimlik kullanılıyor: `ONAY-PMS-2afdb99-01`.
Betik, herhangi bir durumu değiştirmeden **ilk adımda** biletin varlığına bakar;
bilet varsa `66` ile durur — **bütçe artırılmaz, çağrı yapılmaz**. İkinci
bağımsız kapı: tur dizini de aynı kimliğe bağlı olduğu için "dizin zaten var"
kontrolüne takılır. Üçüncü kapı koşucunun kendi `O_EXCL` bilet tüketimidir.

**Bütçe semantiği — ölçüldü, önceki ifadem yanlıştı.** `ip7_cagri_say`
`mevcut >= b` karşılaştırması yapar; bütçe, **izin verilen toplam çağrı**
sayısıdır. Sayaç 5 ve bütçe 6 iken: **6. toplam çağrı KABUL** (sayaç 5→6),
**7. toplam çağrı RET** (çıkış 79). Daha önce "6. çağrı reddedilir" demiştim;
bu yanlıştı ve düzeltildi.

**Sahte süreçle doğrulandı — model çağrısı yapılmadan** 
(`scripts/ip7-pms-tek-kullanim-testi.sh`, 15/15):

| Ölçüm | Sonuç |
|---|---|
| İlk koşum: çağrı tam 1 kez, bütçe 6, sayaç dokunulmadı, bilet tüketildi | A1–A5 |
| İş dosyası sabit kimliği kullandı (üretmedi) | A6 |
| İkinci koşum: çıkış 66, **çağrı yok**, **bütçe artmadı**, sayaç aynı | A7–A10 |
| Ret gerekçesi yazıldı ve ret **bütçe adımına varmadan** oldu | A11–A12 |
| Gerçek `ip7_cagri_say`: 6. kabul (sayaç 5→6), 7. ret (79) | B1–B3 |

Test, gerçek çağrı satırını yalnız `IP7_PROVA=1` modunda sahte bir süreçle
değiştirir; sahte süreç gerçek koşucu gibi bileti `O_EXCL` ile tüketir. Üretim
yolu değişmedi. VM'in gerçek durumu testten sonra doğrulandı: sayaç **5**,
bütçe **0**, PMS bileti **yok**, `/srv/is/pms` **yok**.

Gereken tek insan adımı (VM'de):

    sudo bash /home/yonetici/ip7-pms/vm-32-pms-inceleme.sh

Betik root'u yalnız hazırlık için kullanır; çağrının kendisi yine `incelemeci`
kullanıcısıyla, sandbox içinde, salt okunur kopyada çalışır. Özet uyuşmazsa çağrı
**başlatılmaz**. Sonuç `/srv/teslim/cikti`'ya konur, ana bilgisayar SFTP ile çeker.
**D4 — PMS süitleri CI'da koşmuyor.** `.github/workflows/statik-kontroller.yml`
yalnız `node scripts/check.mjs` çalıştırıyor. Yeni üç süit Docker gerektirdiği
için CI'ya eklenmesi ayrı bir karardır.

**D5 — Ana projeye aktarılmadı.** Üç commit yalnız `pms/akis-tamamlama`
dalında; `origin/main` (`a77e6e1`) değişmedi, **push yapılmadı**, birleştirme
yapılmadı.

---

## 3. Gerçek ortamda doğrulanması gerekiyor

Yerel testlerin geçmesi canlı kabul yerine **geçmez**. Aşağıdakiler bu pakette
ölçülmedi:

1. ~~Ekranın tarayıcıda gerçek render'ı~~ — **2026-09-29'da yapıldı** (§1 P4).
   Kalan: `confirm()` onay kutusunun insan tıklamasıyla sınanması ve ekranın
   farklı ekran boyutlarında/gerçek personel makinesinde davranışı.
2. **Üretim verisiyle davranış:** çok sayıda oda/rezervasyon, satır tavanı
   (5000) sınırına yakın listeler, birden çok otel kapsamı.
3. **Gerçek resepsiyon akışında kullanılabilirlik:** düzeltilen check-in yolunun
   personelin gerçekten kullandığı sırayla uyumu.
4. **Kat hizmetleri eşzamanlılığı** yerel staging'de doğrulandı; üretimde
   yeniden ölçülmedi.
5. **D2 kararı verilip modüller tohumlandıktan sonra** Ön Büro menüsünün
   gerçekten görünür olması.
6. **Gecikmiş check-out ve erken çıkış** senaryoları gerçek takvimle.

---

## 4. Değişen dosyalar

| Dosya | Tür |
|---|---|
| `pms-oda-plani.html` | **ürün kodu** (+36 / −9, yalnız `uygunRezervasyonlar`) |
| `scripts/pms-akis-ekran.test.mjs` | yeni test |
| `scripts/pms-uctan-uca.test.mjs` | yeni test |
| `scripts/pms-hata-durumlari.test.mjs` | yeni test |
| `scripts/pms-akis-tohum.mjs` | yeni **yapay** tohum |
| `scripts/pms-tarayici-ortami.mjs` | yeni tarayıcı doğrulama ortamı |
| `docs/inceleme/vm-betikleri/vm-32-pms-inceleme.sh` | yeni inceleme hazırlık betiği (tek kullanımlık onay) |
| `scripts/ip7-pms-tek-kullanim-testi.sh` | yeni sahte-süreç testi (15/15, model çağrısı yok) |
| `docs/inceleme/PMS-MODUL-TOHUMLAMA-ONERISI.md` | yeni öneri raporu (uygulanmadı) |

Tohumdaki modül/rol/yetki satırları **izole test verisidir**; ürünün rol, yetki
ve RLS tanımlarına dokunulmadı. Gerçek misafir verisi kullanılmadı.
