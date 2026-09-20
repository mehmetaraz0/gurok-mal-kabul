# Bar A1 — Güncel Yayın Adayı (A yolu hazırlığı)

**Tarih:** 2026-09-20 (dördüncü tur) · **Dal:** `bar-a1` (yerel) · **Üretim:** push, deploy ve
canlı migration **yapılmadı**. Bu turdaki tek canlı temas **salt okuma sondalarıdır** (müşteri
projesinin public anon anahtarıyla, yazmayan yollar). Sır repoya konmadı.

| # | İş | Durum |
|---|---|---|
| 1 | Canlı `rapid-handler` kaynağını salt okumayla al | **ALINAMADI — sizde** (araç/belirteç yok); davranış sözleşmesi yerine ölçüldü |
| 2 | `bolge1` davranışını koruyarak birleştir | **YAPILDI** — tek gerçek fark bulundu ve canlı davranış korundu |
| 3 | Birleşik sürümü izole ortamda test et | **YAPILDI — Edge E2E 22/22** |
| 4 | Engel 1: sayım düzeltmesi **A1 paketinde**, yetkiler ikiye ayrıldı | **YAPILDI — 22/22; yetki onayı bekliyor** |
| 5 | Engel 2: kesinti uzlaştırma prosedürü + prova | **YAPILDI — 20/20** (dört alanlı eşleşme, EVET sınırı, A1 öncesi veri) |
| 6 | `authenticated → TRUNCATE` ayrı yüksek öncelikli iş | **KAYDEDİLDİ** — `task_7fcfaa3c`, ölçüm 13/13, ayrı rapor (döküm tabanlı, canlı değil) |
| 7 | Güncel yayın adayı | **AŞAĞIDA — onay bekliyor** |

### Bu turda koşan testler (A1 migration değiştiği için hepsi yeniden)

| Takım | Sonuç |
|---|---|
| `bar-a1-guvenlik` (veritabanı) | **72/72** |
| `bar-a1-negatif` | **12/12** |
| `bar-a1-ekran` | **38/38** (+1 yeni: S0b) |
| `stok-guncelleme-tarihi-bar-sira` (sıra + geri alma) | **17/17** |
| `bar-a1-gecis-migration` | **6/6** |
| `stok-ekle-cagri` | **9/9** |
| `bar-a1-yayin-kilidi` | **7/7** |
| `bar-a1-yayin-kontrol-sorgu` | **4/4** |
| `bar-edge-e2e/gecis-provasi` (geçiş provası) | **16/16** |
| `bar-edge-e2e` (Edge uçtan uca) | **22/22** |
| `sayim-rls-duzeltme` (15c, yeni) | **22/22** |
| `kesinti-uzlastirma` (yeni) | **20/20** (dört alanlı eşleşme dahil) |
| `truncate-yetki` (yeni) | **13/13** (sayı tutarlılığı + tablo listesi dahil) |
| migration denetleyicisi | 0 hata |

---

## 1. Canlı `rapid-handler` kaynağı — alınamadı, nedeni ve yerine ne yapıldı

Makinede Supabase CLI yok ve kayıtlı bir erişim belirteci de yok (`~/.supabase`,
`%APPDATA%\supabase`, ortam değişkenleri — üçü de boş). Kaynak kodu okumak Dashboard girişi ya da
kişisel erişim belirteci gerektiriyor; ikisini de ben yapamam. **Bu madde açık kalıyor ve sizde.**

Kaynak olmadan da ölçülebilecek her şeyi ölçtüm: **davranış sözleşmesi**. Yeni sonda betiği
`scripts/rapid-handler-sonda.mjs` yalnız **yazmayan** yolları dener (sürüm `ping`, JWT yok, JWT
geçersiz, bozuk JSON, yanlış metot, OPTIONS); `ekle`/`durum` gibi yazan eylemler bilerek
denenmez. Çıktı parmak izi olarak kaydedildi:

- canlı: `docs/kurulum/2026-09-20-rapid-handler-canli-parmak-izi.json`
- izole (birleşik A1 sürümü): `docs/kurulum/2026-09-20-rapid-handler-izole-a1-parmak-izi.json`

## 2. `bolge1` ile birleştirme — bulunan tek gerçek fark

| Sonda | Canlı (`bolge1`) | A1 taslağı | Sonuç |
|---|---|---|---|
| `ping` | 200 `{"ok":true,"v":"bolge1"}` | 200 `{"ok":true,"v":"a1-kapsam"}` | **kasıtlı** — deploy'un tuttuğunu bundan anlarız |
| JWT yok | 401 `Oturum yok` | 401 aynı | aynı |
| **JWT geçersiz** | **200** `{ok:false, mesaj:"Oturum geçersiz — tekrar giriş yapın"}` | **401** aynı gövde | **FARK → canlı davranış korundu** |
| Bilinmeyen eylem + geçersiz JWT | 200 aynı | 401 aynı gövde | aynı sebep, birlikte düzeldi |
| Bozuk JSON | 400 `Geçersiz JSON` | 400 aynı | aynı |
| GET | 405 `POST bekleniyor` | 405 aynı | aynı |
| OPTIONS | 200 `ok` + CORS `*` | aynı | aynı |

**Karar ve gerekçesi:** geçersiz oturumda HTTP kodunu 401'e çevirmek A1 taslağımın kendi tercihiydi
(kullanıcı kararı değil) ve **güvenlikle ilgisi yok** — gövde aynı, veri dönmüyor. İstemciler de
HTTP koduna değil gövdedeki `ok` alanına bakıyor (`bar-garson.html`, `bar-masa-yonetimi.html`
ikisi de `const d = await r.json(); if(!d.ok) …`). Bu yüzden **canlı davranış korundu**: birleşik
sürüm geçersiz oturumda yine **200** dönüyor. Güvenlik kriteri HTTP kodu değil, veri dönmemesidir;
test de artık bunu ölçüyor.

**SINIR — açıkça (kullanıcı kuralı 2026-09-20):** yazmayan sondaların eşleşmesi **kaynak eşitliği
sayılmaz.** Ölçülen şey yalnız kimlik doğrulaması gerektirmeyen yolların gözlenebilir davranışıdır;
`liste` / `ekle` / `durum` dalları (asıl iş mantığı) bu yolla görülemez, çünkü üretim personel
JWT'si üretmedim ve üretmem de doğru olmaz. **Bu nedenle deploy yok.** Dashboard'a girdiğinizde
kaynağı salt okumayla alıp satır satır karşılaştıracağım; fark varsa A1 sürümüne taşıyıp testleri
yeniden koşacağım.

**Ek şema bulgusu:** canlı `masa_tokenlari` tablosunda `bolge` kolonu **var** (anon sondasıyla
kolon kolon doğrulandı: `token, otel_id, depo_id, masa_adi, bolge, aktif`), ama repodaki kurulum
dosyasında (`musteri-projesi/01-musteri-sema.sql`) yoktu. Dosya düzeltildi. Bu, "canlı sürüm
repodan ileri" sanısını da yumuşatıyor: `bolge` desteği hem canlıda hem repodaki iki sürümde var;
ölçülebilen tek fark ping yükü. **Yine de kaynak görülmeden deploy edilmemeli** — ölçemediğimiz
tek alan kimlik doğrulaması geçen yollardır (`liste`/`ekle`/`durum`), çünkü üretim personel JWT'si
üretmedim.

## 3. Birleşik sürümün testi

`scripts/bar-edge-e2e/bar-edge-e2e.test.mjs` → **22 OK / 0 FAIL** (gerçek GoTrue + iki PostgREST +
Edge Runtime). R1 kontrolü yeniden yazıldı: artık "hepsi 401" değil, **"JWT yoksa 401; JWT geçersizse
200 + `ok:false`, ve hiçbirinde `masalar` dönmüyor"** ölçülüyor — yani canlı sözleşme testle
kilitlendi.

## 4. Engel 1 — Sayım: A1 PAKETİNE DAHİL EDİLDİ, yetkiler ikiye ayrıldı

Kararınız uygulandı: düzeltme artık ayrı dosya değil, **A1 migration'ının 15c bölümü**
(`docs/kurulum/2026-09-18-bar-a1-guvenlik.sql`). Geri alma da A1'in kendi geri alma dosyasında.
Ölçüm: `scripts/sayim-rls-duzeltme.test.mjs` → **22 OK / 0 FAIL**.

**İki AYRI kapı:**

| İşlem | Kapı | Kim geçer |
|---|---|---|
| **Oluşturma + listeleme** | `auth_yetki_var('stok_takip','kayit')` + `auth_otel_erisim()` | Stok yazabilen personel (depo, depo şefi, cost control, yönetici) — stokun bugün kullandığı kapının **aynısı** |
| **Onay + ret** | `auth_sayim_onaycisi()` = aktif `rol='cost_control'` **ve** `stok_takip:kayit` | Yalnız cost control |

`auth_sayim_onaycisi()`, bugünkü ekran kapısının (`stok-takip.html`: `currentUser.rol === 'cost_control'`)
**birebir sunucu eşidir**; kapsam genişletilmedi. `cost_control_mdr` bilerek dışarıda — bugünkü
ekran onu da kabul etmiyor, eklenmesi ayrı bir karar.

**Onay kapısı RPC'ye de eklendi.** Aksi hâlde `stok_takip:kayit` olan herkes API'den sayım
onaylayabilirdi; bu, bugünkü cost-control sınırını genişletirdi. `stok_sayim_onayla()` artık
`auth_sayim_onaycisi()` istiyor.

**İstediğiniz test — `stok_takip:kayit` sahibi ama cost control olmayan kullanıcı (rol=depo):**

| İşlem | Sonuç |
|---|---|
| Sayım oluşturma (oturum + detay) | **YAPABİLİYOR** (Y1) |
| Kendi otelinin sayımlarını listeleme | **YAPABİLİYOR** (Y2) |
| Reddetme | **YAPAMIYOR** — politika 0 satır yazıyor (Y4) |
| Onaylama (API yolundan) | **YAPAMIYOR** — `YETKI_YOK` (Y5) |
| Cost control aynı işlemleri | onaylıyor (Y6) ve reddediyor (Y7) |

Korunan sınırlar: `sayim_detaylari`ya SELECT politikası **eklenmedi** (detaylar
`stok_sayim_detaylari()` RPC'siyle okunur); doğrudan `onaylandi` yazma cost control için bile
**reddediliyor** (N1); yetkisiz/pasif/başka otel reddediliyor (N2–N6); TRUNCATE ve DELETE
reddediliyor (N9, N10); kısmen uygulanmış oturum reddedilemiyor (N11). Geri almada 15c kalkıyor ve
akış yine kapanıyor (G2), ama **TRUNCATE hakkı geri verilmiyor** (G3 — ayrı güvenlik düzeltmesi).

**Onayınıza sunulan yetki değişiklikleri — tamamı bu:**

| Değişiklik | İçerik |
|---|---|
| 1 yeni fonksiyon | `auth_sayim_onaycisi()` (STABLE, SECURITY DEFINER; anon'a kapalı) |
| 4 permissive RLS politikası | oturum SELECT / INSERT / UPDATE(yalnız ret) + detay INSERT |
| REVOKE `delete, truncate, references, trigger` | yalnız iki sayım tablosu |
| **Yeni tablo GRANT'i yok** | mevcut select/insert/update hakları zaten vardı |

## 5. Engel 2 — Kesilen işlemler: uzlaştırma prosedürü ve provası

- Prosedür: `docs/kurulum/2026-09-20-kesinti-uzlastirma.sql` (salt okuma, sonda `rollback`)
- Prova: `scripts/kesinti-uzlastirma.test.mjs` → **12 OK / 0 FAIL**

Prosedür, kesinti penceresinde **stok / rezervasyon / hareket** üçgenini belge ve kalem bazında
karşılaştırır, her satırı `KESIN` ya da `BELIRSIZ` olarak sınıflar ve sonunda **tek bir karar
satırı** basar: `YENIDEN ACMA: EVET` / `HAYIR (n belirsiz satır)`.

| Kontrol | Ne arar | Provada |
|---|---|---|
| U1 mal kabul | kalem bazında hareket + stok son değişim + onay zamanı | (mevcut ölçüm 4/4) |
| U2 stok/hareket | stok pencerede değişmiş ama eşleşen hareket yok | **K1 yakalandı**, hareket yazılınca **K2 temizlendi** |
| U3a rezervasyon | kapanmış siparişin rezervasyonu hâlâ aktif | **K3** |
| U3b rezervasyon | `kullanildi` rezervasyonun tüketim kaydı yok | **K4** |
| U3c sipariş | teslim edilmiş kalemin tüketimi yok | **K5** |
| U4 rezerve/stok | aktif rezerve > stok (tüm yazmalar reddedilir) | **K6** |
| U5 sayım | detaysız oturum / onaylanmışta kararsız detay / kısmi (bilgi) | **K7** |
| U6 negatif stok | miktar < 0 | **K8** |

Ayrıca ölçüldü: temiz durumda karar **EVET** (K0), tüm belirsizlikler çözülünce yine **EVET** (K9),
ve prosedür **hiçbir şey yazmıyor** (K10).

### 5b. "EVET"in anlamı daraltıldı ve yanlış alarm riski kapatıldı (2026-09-20 kararınız)

| Uyarınız | Yapılan | Kanıt |
|---|---|---|
| "EVET yalnız ölçülen kuralların geçtiği anlamına gelsin" | Karar satırı artık şunu yazıyor: *"YENIDEN ACMA: EVET — 0 belirsiz satir (YALNIZ OLCULEN KURALLAR; kapsam disi: A1 oncesi bar tuketim kayitlari, hic kayit birakmamis islemler, veritabani disi sistemler)"*. Ayrıca karar, satırlarla **aynı sorgudan** üretiliyor — ayrı bir kopya yok, ikisi ayrışamaz | **K15** |
| "A1 öncesi tamamlanmış siparişler yeni tüketim kaydına sahip olmayabilir; temiz eski veriyi bozuk sayma" | U3b/U3c artık yalnız **A1 uygulandıktan sonra** oluşmuş sipariş/rezervasyonlara bakıyor (sınır, denetim izindeki `A1-GECIS-ISARETI` zamanı). A1 işareti yoksa iki kontrol hiç satır üretmiyor ve kapsam dışı sayılıyor | **K11** (30 günlük eski sipariş alarm üretmiyor) + **K12** (aynı desen A1 sonrası oluşunca yakalanıyor — kontrol ölü değil) |
| "Belge/kalemle ilişkilendirilemeyen stok değişikliklerini otomatik temiz kabul etme" | U2 artık dört sınıf üretiyor (aşağıdaki tablo) | **K13**, **K14** |

**`belge_no` dolu olması tek başına KESİN yapmaz (kararınız — uygulandı).** U2 artık **dört alanın
birden** eşleşmesini arıyor: **belge/kalem + ürün + depo + miktar**. Eşleştirilen kaynaklar: mal
kabul kalemi (belge no + ürün + otel + miktar), bar stok tüketimi (sipariş + ürün + depo + miktar),
sayım bekleyen düzeltmesi (ürün + depo + fark miktarı). Başka bir kaynaktan gelen hareket (elle
giriş, harici düzeltme) **KESİN sayılmaz**, insan incelemesine kalır.

| U2 sınıfı | Koşul |
|---|---|
| **KESİN** | belge/kalem + ürün + depo + **miktar** eşleşen hareket var |
| BELİRSİZ | belge numarası var ama **kalem/miktar eşleşmiyor** |
| BELİRSİZ | hareket var ama belge/kalemle ilişkilendirilemiyor (`belge_no` boş) |
| BELİRSİZ | stok değişmiş, hiç hareket yok |

Ölçüldü: **K2a** belge numarası dolu ama karşılığı yok → hâlâ BELİRSİZ · **K2b** dördü eşleşince
KESİN · **K2c** aynı belgede **miktar tutmayınca** yine BELİRSİZ · **K2d** miktar düzeltilince yine
KESİN. Prova toplamı **20/20**.

**Plana işlenen kural:** yazma hakları geri verilmeden önce bu prosedür çalıştırılır;
**"YENİDEN AÇMA: HAYIR" ise sürdürme dosyası çalıştırılmaz.** Prosedür çalıştırılamıyorsa karar
alınamaz, bu da "HAYIR" sayılır.

## 6. Güncel yayın adayı

### 6.1 Kapsam

| Öğe | Değer |
|---|---|
| Dal / uç | `bar-a1` — uç commit yayın anında `git rev-parse bar-a1` ile sabitlenir |
| Taban | `origin/main` = `9c06661` (bugün `git fetch` ile doğrulandı: hâlâ ata) |
| Ekranlar | `bar-siparis-kuyrugu.html`, `bar-garson.html`, `bar-menu.html`, `stok-takip.html`, `pms-folio.html`, `gunluk-tuketim.html`, `mal-kabul-liste.html`, `ortak.js`, `stok-veri.js`, `hata-kodlari.js` |
| Migration | `2026-09-18-bar-a1-guvenlik.sql` (+ geri alma dosyası) — **sayım düzeltmesi artık bunun 15c bölümü; 15c yetkileri 2026-09-20'de yayın adayına dahil edilmek üzere onaylandı (canlı uygulama onayı değil)** |
| Edge | `rapid-handler` — **yalnız canlı kaynak görüldükten sonra** |

### 6.2 Adımlar

| # | Adım | Not |
|---|---|---|
| 0 | Salt okuma ön kontroller | `git fetch` + ata; A1 ön koşul md5'leri; T0; uzlaştırma taban ölçümü |
| 1 | **YEDEK** | İlk üretim değişikliğinden önce — **ekran push'undan da önce** |
| 2 | Yazma duraklatma | `2026-09-20-yayin-yazma-duraklat.sql` (denetim: `A1-YAYIN-DURAKLATMA`) |
| 3 | İşlem kapısı | `2026-09-20-yayin-oncesi-islem-kontrol.sql` |
| 4 | Ekranlar | `main` → sabitlenen uç commit |
| 5 | Migration | A1 (sayım 15c dahil) |
| 6 | Edge | `rapid-handler` — ön koşul sağlandıysa |
| 7 | **YENİDEN AÇMA KAPISI** | `2026-09-20-kesinti-uzlastirma.sql` → **HAYIR ise durulur** |
| 8 | Yazma sürdürme | `…-yayin-yazma-surdur.sql` (kapı EVET dediyse) |
| 9 | Duman testleri + eşleştirme | Sayım duman testi artık **yapılır**: depo kullanıcısı sayım açar/listeler, cost control onaylar |

### 6.2a Geri dönüş — artık yetkileri birebir geri getirmiyor (kararınız)

`docs/kurulum/2026-09-18-bar-a1-guvenlik-geri-al.sql` başına **"KORUNAN DARALTMALAR"** bloğu
eklendi; geri alma sonrası yetki denetimi yapan biri farkı orada görür. Tablo tablo:

| Tablo | Geri verilmeyen | Geri verilen |
|---|---|---|
| `sayim_oturumlari` | DELETE, TRUNCATE, REFERENCES, TRIGGER | SELECT, INSERT, UPDATE |
| `sayim_detaylari` | DELETE, TRUNCATE, REFERENCES, TRIGGER | SELECT (15b geri alınır), INSERT, UPDATE |
| `bar_siparisleri` | tüm tablo hakları (doğrudan yazma kapalı kalır) | — |
| `bar_siparis_kalemleri` | aynı | — |
| `stok_rezervasyonlari` | aynı | — |

Gerekçe dosyada yazılı; geri vermek için gereken açık komut da orada. Bunun dışındaki her şey
(fonksiyon gövdeleri, `search_path`, etkin fonksiyon yetkileri, tetikleyiciler) A1 öncesiyle
**birebir aynı** olmalı — `stok-guncelleme-tarihi-bar-sira` 4b/4b2/4b3 bunu ölçüyor.

### 6.2b Yan iş: `authenticated → TRUNCATE` bulgusu (A1 dışı, yüksek öncelikli)

Ayrı rapor: [`2026-09-20-truncate-bulgusu.md`](2026-09-20-truncate-bulgusu.md) · ayrı iş kaydı:
`task_7fcfaa3c`. İki boyut **ayrı** raporlandı:

| Boyut | Sonuç (izole ölçüm, `scripts/truncate-yetki.test.mjs` 11/11) |
|---|---|
| **(A) Veritabanı yetkisi** | **VAR ve etkili** — `authenticated` için **80 tabloda** TRUNCATE hakkı; **68'inde RLS açık**. İzole kopyada TRUNCATE komutu **kabul edildi**. ⚠️ Bu sayılar **2026-09-13 şema dökümünden kurulan kopyada** ölçüldü; **canlı doğrulama yapılmadı** |
| **(B) Bugünkü API yüzeyi** | **Ulaşılamıyor** — PostgREST TRUNCATE metodunu tanımıyor (**HTTP 405**), genel SQL çalıştırma ucu yok (**404**), `anon`/`authenticated` rolleri **LOGIN'e kapalı**, dışa açık ve dinamik SQL çalıştıran fonksiyon **0** |

A1 toplam **5 tabloda** kaldırıyor — ikisi 15c kararı (`sayim_oturumlari`, `sayim_detaylari`), üçü
A1'in sipariş tablolarına doğrudan yazmayı kapatmasının yan etkisi (`bar_siparisleri`,
`bar_siparis_kalemleri`, `stok_rezervasyonlari`). Aritmetik tek sorguyla ölçülüyor:
**80 − 5 = 75** (C3/C4/C5). Kalan **75 tablo** ayrı işin konusu. Üretimde **hiçbir TRUNCATE denemesi yapılmadı ve yapılmayacak**; canlı doğrulama için salt
okuma dosyası hazır: `docs/kurulum/2026-09-20-truncate-yetki-kontrol.sql`.

### 6.3 Açık kalan iki engel

1. **Canlı `rapid-handler` kaynağı** — Dashboard'dan indirilip repodaki sürümle karşılaştırılmadan
   6. adım yapılmaz. Bu olmadan geri dönüş kaynağı da yoktur.
2. **Sayım yetki değişikliklerinin onayı** — 4. bölümdeki değişiklikler (1 fonksiyon + 4 politika + REVOKE)
   onaylanmadan A1 yayınlanamaz, çünkü artık paketin içindeler.

Bunlar çözülene kadar öneri değişmedi: **A yolu**, ekranlar → migration → Edge sırası. Push,
deploy ve canlı migration için talimat beklenmektedir.
