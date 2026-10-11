# Talep → Sipariş Bağı — Yayın Paketi (ÜRETİME UYGULANMADI)

**Tasarım:** `docs/superpowers/specs/2026-10-11-talep-siparis-bagi-design.md`
**Plan:** `docs/superpowers/plans/2026-10-11-talep-siparis-bagi.md`
**Dal:** `feat/talep-siparis-bagi` (push edilmedi)

Bu paket **üretime uygulanmadı**. Uygulama yalnız kullanıcı açıkça
`CANLIYA UYGULA` dediğinde yapılır.

## Ne çözülüyor

`satin_alma_talepleri.siparis_no` hiç doldurulmuyordu: `talep_siparise_donustur`
RPC'si yalnız `durum='siparis'` yazıyor, sipariş numarası sonra istemcide
üretiliyordu. Bir talep birden fazla siparişe bölünebildiği için tek metin
alanı zaten yetersizdi. Sonuç: talep "siparişe dönüştü" görünürken sipariş hiç
oluşmayabiliyordu ve o talep açık talep listesinden sessizce düşüyordu
(ölçülen 7 tutarsız kayıt).

Artık izlenebilir bir bağ tablosu var: **(talep kalemi, sipariş, miktar)** —
kısmi karşılama taneliliğinde. Açık talep = **kalan** miktar.

## Uygulama sırası (zorunlu)

| # | Dosya | Neden bu sırada |
|---|---|---|
| 1 | `2026-10-11-siparis-no-sayac.sql` | RPC ve istemciler buna bağımlı |
| 2 | `2026-10-11-talep-siparis-baglari.sql` | Kapılar ve RPC buna bağımlı |
| 3 | `2026-10-11-siparisler-islem-anahtari.sql` | RPC idempotency buna bağımlı |
| 4 | `2026-10-11-talep-siparis-inv-kapilari.sql` | Bağ tablosu var olmalı |
| 5 | `2026-10-11-siparis-olustur-talepten.sql` | 1–4'ün hepsine bağımlı |
| 6 | `2026-10-11-stok-acik-talep-kalan.sql` | Bağ tablosu var olmalı |
| 7 | **Arayüz push** (`satin-alma-talepler.html`, `satin-alma-siparisolustur.html`, `satin-alma-iade.html`, `stok-takip.html`, `onay-motoru.js`) | Görünümün `birim` kolonu ile **birlikte** gider |
| 8 | `2026-10-11-talep-siparis-bag-geri-yazma.sql` | Bağ tablosu ve INV kapıları kurulu olmalı; **geçiş kararının uygulaması** (aşağıya bak) |

**Kritik — 6 ve 7 birlikte gider.** Görünüm `birim` kolonu döndürmeye
başladığında eski ekran bütün satırları ürün kodunda toplar: ölçüldü,
10 KOL + 100 KG ekranda **110** görünür — kullanıcının hiçbir yerde karşılığı
olmayan bir sayı.

**Kritik — 1 ve 7 birlikte gider.** İstemciler numarayı artık
`siparis_no_uret` RPC'sinden alıyor; 1 uygulanmadan 7 yayınlanırsa dört
sipariş yolunun hepsi "Sipariş numarası alınamadı" diyerek **durur** (fail-closed,
sessiz uydurma yok).

## Geri alma sırası (ters)

7 arayüz revert → 6 eski görünüm (`2026-10-11-stok-acik-talep-durum-filtresi.sql`
yeniden koşulur; **o dosya değiştirilmez**) → 5 RPC drop → 4 kapılar drop →
3 kolonlar drop → 2 bağ tablosu **(bağ geçmişini siler — yalnız üretim verisi
yoksa)** → 1 sayaç drop.

**Uyarı:** 6 geri alınırsa kısmi karşılanan talebin **kalanı** ekranda hiç
görünmez. 1 geri alınırsa istemciler numara alamaz; 7 de geri alınmalıdır.

## Geçiş kararı — ÖLÇÜLDÜ ve VERİLDİ (2026-10-11)

Tasarım §10 kararı kullanıcıya bırakıyordu. Üretimde salt-okuma ile ölçüldü
(`...-gecis-olcumu-uygulama-oncesi.sql` ve `...-aday-eslesme-sondasi.sql`):

- Bağsız `siparis` talep: **7**, hepsi otel 810, 9 Tem – 12 Ağu 2026, 17 kalem.
  `siparise_donustu` etiketi: **0 kayıt** — tasarımın ölçmediği popülasyon boş.
- Kalemin birimi katalogla çevrilemeyen satır: **0** — yayından sonra hiçbir
  kalem `birim_cevrilemez` almayacak.
- Aday sipariş eşleşmesi: 17 kalemin **15**'inde aynı gün + tam miktar eşleşen
  sipariş var. `1f80e26a`'nın 10 kalemi **8 ayrı firmanın 8 ayrı siparişine**
  dağılmış — ekranın firma bazlı gruplama davranışının birebir izi. Yani eski
  akış çalışmış, sipariş yazılmış; kaydedilmeyen tek şey **bağ** olmuş.

**Karar: üç gruba ayrıldı, tek bir seçenek 7 talebin tamamına uygulanmadı.**

| Grup | Kalem | Ne yapılıyor |
|---|---|---|
| Aynı gün + tam miktar + tek güçlü aday | **12** | `...-bag-geri-yazma.sql` ile bağ **geriye yazılıyor** |
| Tek adayı **iptal** sipariş olan (PARMESAN TOZ 10 KG) | 1 | Dokunulmuyor — iptal siparişin bağı sayılmaz, kalem haklı olarak açık |
| İki talep **aynı** siparişi gösteriyor (CARTE DOR 11 + 10 KTU, sipariş 10 KTU) | 2 | Dokunulmuyor — hangi talebi karşıladığı insan bilgisi |
| Hiç adayı yok (dept 100, Ağustos) | 2 | Dokunulmuyor — sipariş edilmemiş, açık görünmesi doğru |

Geri yazma dosyası **otomatik eşleştirme yapmaz**: 12 satırın her biri sondadan
insan incelemesiyle seçildi ve dosyada açıkça listeli. Beş doğrulama kapısı var
ve tek bir uyuşmazlıkta **tüm işlem geri alınır**: liste 12 satır olmalı · her
satır tam olarak bir kaleme çözülmeli · miktar ve birim birebir tutmalı ·
sipariş var olmalı ve iptal olmamalı · aynı otel · o kalemlerde önceden bağ
olmamalı. Yazma sonrası ayrıca 12 bağ ve kalanın sıfır olduğu doğrulanır.

İzole kabul: `node scripts/talep-siparis-bag-geri-yazma.test.mjs` → **36 / 0**,
dört mutantla birlikte (ikinci koşum, bozuk miktar, iptal sipariş, mükerrer
kalem — dördü de reddedildi ve hiçbir satır kalmadı).

**Geri alma:** `delete from talep_siparis_baglari where olusturan_ad =
'geri-yazma-2026-10-11'`. Bağ geçmişini silmek normalde yasak (§7 K7), ancak bu
satırlar gerçek bir iş akışından değil geri yazmadan doğdu ve `olusturan_ad`
ile tekil işaretli.

## Uygulama öncesi ölçüm (salt okuma)

`2026-10-11-talep-siparis-gecis-olcumu.sql` salt-okuma ile koşulur. Çıktısı:

1. Bağsız `siparis` **ve** `siparise_donustu` talep listesi — yeni görünümde
   yeniden açık görünecek olanlar. **İki etiket birlikte ölçülür**: eski görünüm
   ikisini de dışlıyordu, tasarım §10 ise yalnız `siparis` olanları (7 kayıt)
   ölçmüştü.
2. Etiket başına bağsız talep sayısı.
3. Yeni görünümün birim bazında toplamı (etki büyüklüğü).
4. `hedef_birim` ayrışması denetimi — beklenen **0 satır**.
5. INV ihlali denetimi — beklenen **0 satır**.
6. Altı tetikleyici fonksiyonun `security definer` olduğu — beklenen **6×`t`**.

**Geçiş adımı migration'ın parçası değildir.** Bağsız talepler otomatik iptal
**edilmez**, otomatik **bağlanmaz**. Liste karar için kullanıcıya sunulur.

## Yerel kabul — ÖLÇÜLEN SONUÇLAR (2026-10-11, izole Docker, üretime bağlanmadan)

| Ölçüm | Ölçülen |
|---|---|
| `node scripts/siparis-no-uret.test.mjs` | **12 / 0** |
| `node scripts/talep-siparis-bagi-kapilari.test.mjs` | **45 / 0** |
| `node scripts/talep-siparis-kapi-kimlik.test.mjs` | **32 / 0** |
| `node scripts/siparis-olustur-talepten.test.mjs` | **49 / 0** |
| `node scripts/stok-acik-talep-kalan.test.mjs` | **23 / 0** |
| `node scripts/talepten-siparis-istemci.test.mjs` | **54 / 0** |
| `node scripts/istemci-siparis-no-rpc.test.mjs` | **51 / 0** |
| `node scripts/stok-ekran.test.mjs` | **30 OK / 0 FAIL** |
| `node scripts/talep-siparis-bag-geri-yazma.test.mjs` | **36 / 0** |
| `node scripts/migration-guvenlik-kontrol.mjs` | **0 HATA / 0 UYARI** |
| `node scripts/check.mjs` | **çıkış 0** |

Referans örnek uçtan uca ölçüldü: talep kalemi 10 KOL · sipariş satırı 72 KG ·
yazma anında 12 KG/KOL → bağ **6.000 KOL** (`hedef_birim='KOL'` donduruldu,
`kaynak_miktar=72.000 KG` korundu) → kalan **4.000 KOL**. Katalog çarpanı 24'e
çıkarılsa, katalog birimi LT yapılsa, dönüşüm pasifleştirilse veya satırı
silinse kalan **4.000 KOL** kalıyor.

**Üretim kabulü bu tablonun kapsamı dışındadır.** Bu sayılar izole Docker
ortamında, üretim şema dökümü tabanında ölçüldü; üretimde ölçülmüş değil.

## Bağımsız incelemede bulunan ve kapatılan üç kritik açık

Bu üç açık, kapı testlerinin tamamı `postgres` superuser olarak koştuğu için
45/45 ve 22/22 yeşillerine rağmen görünmüyordu. Üçü de izole ortamda ölçülüp
kapatıldı; testler artık **gerçek kimlikle** koşuyor (biri sipariş modülünde
yetkisiz).

| # | Açık | Ölçülen hata | Düzeltme |
|---|---|---|---|
| C1 | K5/K6 `security invoker` → bağlar RLS'le süzülüp kapı sessizce atlanıyor | `ic_talep:kayit` yetkili kullanıcı 10 KOL'luk kalemi, 6 KOL bağ varken **1.000**'e düşürdü; birimi de değiştirdi | tetikleyici fonksiyonları `security definer` |
| C2 | Görünüm `security_invoker` → sipariş yetkisi olmayana kalan değil **toplam** | kalan 4 yerine süzülmüş değer | bağ toplamı `talep_bag_toplam()` definer yardımcısına taşındı, otel kapsamı orada yeniden uygulandı |
| C3 | K3 invoker olup EXECUTE'u alınmış definer fonksiyon çağırıyor | meşru iptalden geri alma `permission denied for function talep_bag_inv_kontrol` | tetikleyici `security definer` |

## Yapılmayacaklar

- Üretime yazma `CANLIYA UYGULA` denmeden **yok**.
- Uygulanmış migration'lar yeniden yazılmaz
  (`2026-10-11-stok-acik-talep-durum-filtresi.sql` bilinçle **aşılıyor**,
  değiştirilmiyor).
- Bağsız talepler **otomatik** iptal/bağlanmaz. 12 bağ, insan incelemesiyle seçilmiş
  açık liste üzerinden geri yazılıyor (yukarıdaki geçiş kararı bölümü); kalan 5
  kalem bilinçle açık bırakılıyor.
- `satin_alma_talepleri.siparis_no` ölü kolonu düşürülmez (ayrı karar).
- `siparisler.durum` için enum/check eklenmez (ayrı karar).
- `talep_siparise_donustur` RPC'si sunucudan düşürülmez (ayrı karar); istemci
  artık çağırmıyor.

## Açık kalan maddeler (uygulama öncesi okunmalı)

- `carpan_gecersiz` ret kodu **uygulanmadı**: `urun_birim_donusum.carpan`
  kolonu `numeric NOT NULL CHECK (carpan > 0)` olduğu için geçersiz çarpan veri
  katmanında imkansız; o dal ölü kod olurdu. Kısıt kalkarsa kullanıcı
  "birim çevrilemez" mesajı görür.
- Tasarım §12'nin şart koştuğu mutantların bir kısmı yazılmadı (FK `cascade`,
  kısmi unique indeksin düşmesi, iptal süzgecinin kalkması). C1'i yakalayan
  mutant yazıldı.
- Talep satırında kullanıcı ürünü değiştirirse sunucu ürün kodunu **talep
  kaleminden** türetmeye devam eder (tasarım gereği); ekranda bu durum
  kullanıcıya ayrıca anlatılmıyor.
- Şema dökümünün ve eşitlik doğrulayıcısının iki yeni `siparisler` kolonu için
  yenilenmesi bu pakette **yok** (üretim parolası gerektirir).
