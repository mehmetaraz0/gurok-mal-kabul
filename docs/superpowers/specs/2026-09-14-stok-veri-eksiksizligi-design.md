# Stok Takip — Veri Eksiksizliği — Tasarım

**Tarih:** 2026-09-14 · **Durum:** onaylandı (kullanıcı, 2026-09-14)

## Neden

`stok-takip.html` bugün sunucudan dönen verinin **eksiksiz olduğunu
varsayıyor**. Altı yerde ölçüldü:

| # | Kusur | Yer | Sonucu |
|---|---|---|---|
| 1 | HTTP hatası boş listeye çevriliyor: `detR.ok ? json : []` | `:2079` | Sayım **onaylanıyor**, hiçbir stok güncellenmeden ("0 üründe güncellendi") |
| 2 | Sayım detayları sayfalanmıyor | `:2052`, `:2079` | Sunucu limiti üstündeki satırlar sessizce düşer; oturum "tamam" sayılır |
| 3 | `stok?select=*` — filtresiz, sayfalamasız | `:491` | Depoda limit üstü ürün varsa liste sessizce kırpılır |
| 4 | `stok_hareketleri?select=*` açılışta | `:492` | Tüm geçmiş indirilir; büyüdükçe hem yavaşlar hem kırpılır |
| 5 | Ürün araması yalnız `db.urunler` içinde | `:1292` | Katalog kırpılmışsa aranan ürün "yok" görünür |
| 6 | Toplamlar bellekteki listeden sayılıyor | `:874-900` | Sayfalama gelince sayfa toplamı "genel toplam" gibi görünür |

Ortak kök: `if (r.ok) { ... }` deseni ve `catch(e){console.warn(e)}`. İkisi de
**başarısızlığı boşlukla** karıştırıyor.

## Temel ilke

**Eksik veri, "veri yok" demek değildir.** Bir okuma başarısız olduysa ya da
tamamlandığı kanıtlanamıyorsa, çağıran bunu **hata** olarak görmeli; boş liste
gibi davranmamalı. Yazma yapan hiçbir akış (özellikle sayım onayı) eksiksizliği
kanıtlanmamış veriyle ilerlemez.

## Değişiklikler

### 1. Veri erişim katmanı ayrılıyor — `stok-veri.js`

DOM bilmeyen, saf veri modülü. Ekran onu çağırır; testler de aynı modülü
çağırır. Sözleşme:

| Fonksiyon | Döner | Hata |
|---|---|---|
| `tumSayfalariCek(yol, sec)` | Tüm satırlar (sayfa sayfa toplanmış) | HTTP başarısızsa ve kırpılma saptanırsa **fırlatır** |
| `sayimDetaylariniGetir(oturumId, beklenenAdet)` | Eksiksiz detay listesi | Hata ya da adet uyuşmazlığında **fırlatır** |
| `stokSayfasiGetir({depo, arama, ofset, adet})` | `{satirlar, toplam, dahaVar}` | HTTP hatasında **fırlatır** |
| `urunAra(terim, adet)` | Sunucudan eşleşen ürünler | HTTP hatasında **fırlatır** |
| `hareketSayfasiGetir({urun, depo, ofset, adet})` | `{satirlar, dahaVar}` | HTTP hatasında **fırlatır** |
| `stokOzetGetir(depo)` | `{toplam, kritik, uyari, normal}` | HTTP hatasında **fırlatır** |

Hatalar `StokVeriHatasi` tipiyle fırlatılır ve `{durum, yol, mesaj}` taşır;
çağıran kullanıcıya ne olduğunu söyleyebilsin.

### 2. Sayfalama sözleşmesi

PostgREST'in satır tavanı (`db-max-rows`) **bilinmez kabul edilir**. Her
sayfalı okuma:

1. `Range` başlığıyla sayfa ister (`Prefer: count=exact`).
2. Yanıttaki `Content-Range: 0-999/5000` başlığından **gerçek toplamı** okur.
3. Toplam elde edilene kadar sonraki sayfayı ister.
4. Bir sayfa başarısız olursa **tamamı fırlatılır** — yarım liste dönmez.
5. Toplam okunamıyorsa (`*` ya da başlık yok) ve dönen satır sayısı istenen
   sayfa boyutuna eşitse, **kırpılma ihtimali** kabul edilir ve hata fırlatılır.

Böylece sunucu limiti 100 de olsa 1000 de olsa sonuç aynıdır: ya eksiksiz
liste, ya hata.

### 3. Sayım onayı — eksiksizlik kanıtı

`sayimOnayla` artık **stok yazmadan önce** şunu yapar:

- Detayları `sayimDetaylariniGetir(oturumId, oturum.toplam_urun_sayisi)` ile
  alır. Bu fonksiyon HTTP hatasında fırlatır ve **oturum satırındaki
  `toplam_urun_sayisi` ile dönen satır sayısını karşılaştırır**; eşit değilse
  fırlatır.
- Fırlatma hâlinde onay **hiç başlamaz**: tek bir stok satırına dokunulmaz,
  oturum durumu değişmez, kullanıcıya neden engellendiği yazılır.

Mevcut satır-bazlı fail-closed davranışlar (canlı `guncelR` okuması, yazma
sonrası doğrulama, `kismi_uygulandi` kontrolü) **aynen korunur**.

### 4. Stok listesi — sunucu tarafı filtre + sonsuz kaydırma

Liste artık `stok_liste` görünümünden sayfalı okunur:

- **Depo/otel:** `depo_kodu=eq.<aktif depo>`; otel kapsamı RLS'in işidir,
  istemci ek bir otel filtresi uydurmaz.
- **Arama:** `or=(urun_kodu.ilike.*t*,urun_adi.ilike.*t*)` — sunucuda.
- **Sayfa:** 100'lük dilimler, aşağı kaydırıldıkça sonraki dilim.
- Kaydırma sırasında hata olursa liste **"eksik" olarak işaretlenir** ve
  tekrar dene düğmesi çıkar; sessizce durmaz.

### 5. Ürün araması

`urunler` tablosunda sunucu tarafı `ilike` araması, en fazla 20 sonuç. İndirilmiş
katalog artık yalnız **ad/birim süslemesi** için kullanılır; aramanın kapsamını
belirlemez.

### 6. Hareket geçmişi

Açılışta indirilmez. Ürün/depo seçildiğinde, tarihe göre tersten, 50'lik
sayfalarla istenir.

### 7. Toplamlar — sunucudan

Yeni görünüm ve fonksiyon (migration):

```sql
create or replace view public.stok_liste
with (security_invoker = true) as
  select s.otel_id, s.depo_kodu, s.urun_kodu,
         u.ad as urun_adi, u.birim,
         s.miktar,
         (select max(m.min_miktar) from public.stok_minimumlar m
           where m.urun_kodu = s.urun_kodu) as min_miktar
    from public.stok s
    left join public.urunler u on u.kod = s.urun_kodu;

create or replace function public.stok_ozet(p_depo text)
returns table (toplam bigint, kritik bigint, uyari bigint, normal bigint)
language sql stable security invoker set search_path = public as $$ ... $$;
```

**İki ölçülmüş ayrıntı, tasarımı bağlar:**

- `stok` tablosunda **`birim` sütunu yoktur**; birim yalnız `urunler`'den gelir.
  (Bugünkü istemci `r.birim` okuyor, o alan hiç dolmuyor.)
- `stok_minimumlar` **depo ve otel kırılımlıdır**, ama bugünkü ekran ürün başına
  **depolar arası en yüksek** minimumu kullanıyor (`Math.max`, Firebase
  mirası; `:523` civarında yorumla belirtilmiş). Görünüm bu davranışı
  **birebir korur** — bu iş veri eksiksizliği içindir, eşik semantiğini
  değiştirmez. Minimumun depo bazında ele alınması ayrı bir karardır ve
  bulgu olarak kayda geçer.

`security_invoker = true` ve fonksiyonun **SECURITY INVOKER** olması zorunlu:
RLS ve otel izolasyonu olduğu gibi kalır. ACL evin standardına göre:
`revoke all ... from public, anon` + `grant ... to authenticated, service_role`.

Durum eşikleri bugünkü istemci mantığıyla **birebir aynı** tanımlanır
(`miktar <= 0 or miktar <= min*0.5` → kritik; `miktar <= min` → uyarı).

## RLS ve yetki

Hiçbir politika, rol ya da yetki satırı değişmez. Görünüm `security_invoker`
olduğu için `stok` üzerindeki mevcut RLS aynen uygulanır; fonksiyon da
çağıranın haklarıyla çalışır. Yeni nesneler `anon`'a kapalıdır.

## Hata ve kenar durumlar

| Durum | Davranış |
|---|---|
| Sayım detayları HTTP hatası | Onay **başlamaz**; "detaylar okunamadı" mesajı; oturum değişmez |
| Detay adedi `toplam_urun_sayisi` ile uyuşmuyor | Onay **başlamaz**; kaç satır beklenip kaç geldiği yazılır |
| `toplam_urun_sayisi` alanı boş | Sayfalama kendi içinde eksiksizlik kanıtı üretir (Content-Range); yine de onay yalnız tam liste ile ilerler |
| Liste sayfasında ara hata | O ana kadarki satırlar korunur, liste "eksik" işaretlenir, tekrar dene çıkar; toplam sayaç yanıltmaz |
| Sunucu limiti sayfa boyutundan küçük | Content-Range'deki gerçek toplam kullanılır; döngü limitle uyumlu ilerler |
| Toplam okunamıyor ve sayfa tam dolu | Kırpılma varsayılır, hata fırlatılır |
| Arama sonucu 20'den fazla | "Daraltın" uyarısı; sessizce kırpılmaz |

## Test

İzole ortamda (`yerel-staging.mjs` iskeleti; PostgREST satır tavanı **100**'e
düşürülerek):

1. **999 / 1.000 / 1.001 / 5.000** stok satırı — her birinde liste eksiksiz
   sayılır, toplam sunucudan gelen sayıyla birebir eşleşir.
2. **Düşük sunucu limiti** (100) — 5.000 satır yine eksiksiz toplanır.
3. **Ara sayfa hatası** — üçüncü sayfa 500 dönerse fonksiyon **fırlatır**;
   çağıran boş/yarım liste görmez.
4. **Son sayfadaki ürünü arama** — 5.000'inci ürün, sunucu araması sayesinde
   bulunur (indirilmiş katalogda olmasa bile).
5. **Eksik detayla sayım onayı** — detay okuması hata verdiğinde ve adet
   uyuşmadığında onay **engellenir**; stok tablosunda hiçbir satır değişmez,
   oturum `onay_bekliyor` kalır.

## Kapsam dışı

- Stok ekranının görsel tasarımı ve mevcut kart/tablo özellikleri.
- Diğer ekranların veri erişimi (mal kabul, sipariş vb.).
- Fiyat haritası ve ABC sınıflandırmasının kaynağı.
- Üretime uygulama: migration ve arayüz ayrı bir `CANLIYA UYGULA` onayına
  bağlıdır; bu iş yalnız yerelde doğrulanır.
