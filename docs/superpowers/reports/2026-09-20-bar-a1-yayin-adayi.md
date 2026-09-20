# Bar A1 — Güncel Yayın Adayı (A yolu hazırlığı)

**Tarih:** 2026-09-20 (dördüncü tur) · **Dal:** `bar-a1` (yerel) · **Üretim:** push, deploy ve
canlı migration **yapılmadı**. Bu turdaki tek canlı temas **salt okuma sondalarıdır** (müşteri
projesinin public anon anahtarıyla, yazmayan yollar). Sır repoya konmadı.

| # | İş | Durum |
|---|---|---|
| 1 | Canlı `rapid-handler` kaynağını salt okumayla al | **ALINAMADI — sizde** (araç/belirteç yok); davranış sözleşmesi yerine ölçüldü |
| 2 | `bolge1` davranışını koruyarak birleştir | **YAPILDI** — tek gerçek fark bulundu ve canlı davranış korundu |
| 3 | Birleşik sürümü izole ortamda test et | **YAPILDI — Edge E2E 22/22** |
| 4 | Engel 1: sayım dar kapsamlı düzeltme + yetki onayı | **TASARLANDI, ADAY HAZIR, ÖLÇÜLDÜ 21/21 — onay bekliyor** |
| 5 | Engel 2: kesinti uzlaştırma prosedürü + prova | **YAPILDI — 12/12** |
| 6 | Güncel yayın adayı | **AŞAĞIDA — onay bekliyor** |

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

## 4. Engel 1 — Sayım: dar kapsamlı düzeltme (onaya sunuluyor)

Haklıydınız: A1 sayım akışını değiştiriyor, dolayısıyla akışın çalışmadığını bilip duman testinden
çıkarmak yeterli değil. Dar kapsamlı düzeltme hazırlandı:

- Aday: `docs/kurulum/2026-09-20-sayim-rls-dar-duzeltme.sql`
- Geri alma: `docs/kurulum/2026-09-20-sayim-rls-dar-duzeltme-geri-al.sql`
- Ölçüm: `scripts/sayim-rls-duzeltme.test.mjs` → **21 OK / 0 FAIL**

**Onayınıza sunulan yetki değişiklikleri — tamamı bu, başkası yok:**

| Değişiklik | İçerik | Neden dar |
|---|---|---|
| 4 permissive RLS politikası | oturum SELECT / INSERT / UPDATE(yalnız ret) + detay INSERT | Kapı, stokun bugün kullandığı kapının aynısı: `auth_yetki_var('stok_takip','kayit')` + `auth_otel_erisim()`. Yeni yetki seviyesi icat edilmedi |
| REVOKE `delete, truncate, references, trigger` | yalnız iki sayım tablosu | Fazla hakların geri alınması; kimse yetki kazanmıyor |
| **Yeni GRANT yok** | mevcut select/insert/update hakları zaten vardı | — |

**Korunan sınırlar:** `sayim_detaylari`ya SELECT politikası **eklenmedi** (detaylar A1'in
`stok_sayim_detaylari()` RPC'siyle okunur — eski sekme korumasının katmanı); UPDATE yalnız
`onay_bekliyor → reddedildi` geçişine izin verir, **doğrudan `onaylandi` yazılamaz** (onay yalnız
`stok_sayim_onayla()` RPC'sinden geçer); kısmen uygulanmış oturum reddedilemez.

Ölçülen davranış (önce/sonra):

| Kontrol | Düzeltmeden önce | Sonra |
|---|---|---|
| Sayım oluşturma | **RLS reddi** | çalışıyor |
| Listeleme | 0 satır | kendi otelinin sayımları |
| Reddetme | sessizce 0 satır | çalışıyor |
| Doğrudan "onaylandı" yazma | — | **reddediliyor** |
| Yetkisiz / pasif / başka otel | — | **reddediliyor** (N2–N6) |
| `sayim_detaylari` doğrudan okuma | permission denied | **hâlâ** permission denied |
| TRUNCATE | **mümkündü** | **reddediliyor** |

**Yan bulgu (A1 dışı, ayrı iş):** üretim şema dökümünde **77 tablo** `authenticated` rolüne
`GRANT ALL` almış; bu **TRUNCATE**'i de kapsıyor ve **TRUNCATE RLS'i dinlemez**. Yani herhangi bir
ERP kullanıcısı bu tabloları boşaltabilir. Bu düzeltme yalnız iki sayım tablosunu kapatıyor;
kalan tablolar ayrı bir iş olarak ele alınmalı.

**Yayın kapsamı sorusu:** bu düzeltme A1 yayınına **dahil edilsin mi, ayrı mı gitsin?** İkisi de
mümkün; A1 ile birlikte giderse sayım özelliği ilk kez çalışır hâle gelir. Karar sizde (5.7).

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
| Migration | `2026-09-18-bar-a1-guvenlik.sql` (+ geri alma dosyası) |
| Sayım düzeltmesi | `2026-09-20-sayim-rls-dar-duzeltme.sql` — **dahil mi? kararınız** |
| Edge | `rapid-handler` — **yalnız canlı kaynak görüldükten sonra** |

### 6.2 Adımlar

| # | Adım | Not |
|---|---|---|
| 0 | Salt okuma ön kontroller | `git fetch` + ata; A1 ön koşul md5'leri; T0; uzlaştırma taban ölçümü |
| 1 | **YEDEK** | İlk üretim değişikliğinden önce — **ekran push'undan da önce** |
| 2 | Yazma duraklatma | `2026-09-20-yayin-yazma-duraklat.sql` (denetim: `A1-YAYIN-DURAKLATMA`) |
| 3 | İşlem kapısı | `2026-09-20-yayin-oncesi-islem-kontrol.sql` |
| 4 | Ekranlar | `main` → sabitlenen uç commit |
| 5 | Migration | A1 (+ onaylanırsa sayım düzeltmesi) |
| 6 | Edge | `rapid-handler` — ön koşul sağlandıysa |
| 7 | **YENİDEN AÇMA KAPISI** | `2026-09-20-kesinti-uzlastirma.sql` → **HAYIR ise durulur** |
| 8 | Yazma sürdürme | `…-yayin-yazma-surdur.sql` (kapı EVET dediyse) |
| 9 | Duman testleri + eşleştirme | Sayım kontrolü ancak sayım düzeltmesi yayına dahilse yapılır |

### 6.3 Açık kalan iki engel

1. **Canlı `rapid-handler` kaynağı** — Dashboard'dan indirilip repodaki sürümle karşılaştırılmadan
   6. adım yapılmaz. Bu olmadan geri dönüş kaynağı da yoktur.
2. **Sayım düzeltmesinin yayın kapsamı ve yetki onayı** — 4. bölümdeki iki değişiklik (4 politika
   + REVOKE) onaylanmadan sayım akışı üretimde çalışmaz.

Bunlar çözülene kadar öneri değişmedi: **A yolu**, ekranlar → migration → Edge sırası. Push,
deploy ve canlı migration için talimat beklenmektedir.
