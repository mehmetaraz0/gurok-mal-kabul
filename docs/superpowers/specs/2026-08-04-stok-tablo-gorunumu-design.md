# Stok Tablo (Grid) Görünümü — Tasarım Dokümanı

**Tarih:** 2026-08-04
**Durum:** Tasarım onaylandı (kullanıcı). Uygulama writing-plans → SDD.

## Amaç
Stok-takip ekranına, mevcut mobil kart listesine DOKUNMADAN, Excel-benzeri **sütunlu tablo (grid)**
görünümü eklemek. "Kart / Tablo" geçiş düğmesi; tablo görünümünde sütun başlıklarında filtre
(mevcut filtre.js) + sıralama; stok yanında bekleyen sipariş/talep ve son hareket tarihi sütunları.

## Alınan Kararlar (kullanıcı onaylı, 2026-08-04)
1. **Görünüm geçişi (kart ⬌ tablo)** — kart görünümü aynen kalır; tablo YENİ seçenek. Filtreler
   her ikisinde ORTAK (`aktifStokFiltreleri`). Mevcut kritik/ABC/kategori sekmeleri + stok işlemleri BOZULMAZ.
2. **Raf/Konum v1 DIŞI** — sistemde veri yok (stok tablosunda alan yok); ileride ayrı özellik.
3. **Hesaplanan sütun tanımları:**
   - **Sipariş (bekleyen)** = açık satın alma siparişlerinde bu üründen gelmemiş (kalan) miktar toplamı.
   - **Talep (bekleyen)** = siparişe dönüşmemiş satın alma taleplerinde bu üründen miktar toplamı.
   - **Son Hareket Tarihi** = bu üründe (aktif depoda) en son stok hareketinin tarihi.

## Mevcut Sistem (referans)
- stok-takip verisi bellekte `db.stok[aktifDepoId]` (per-depo), kart listesi. Filtreleme istemci-taraflı.
- Gelişmiş filtre altyapısı (filtre.js + kayitli_filtreler) CANLI (2026-08-04). `renderStok()` süzülmüş
  `filtered` diziyi kartlara basıyor; `Filtre.filtreleUygula` zaten burada uygulanıyor.
- `stok` tablosu: {urun_kodu, depo_kodu, otel_id, miktar}. Raf/konum YOK.

## Mimari + Bileşenler

### 1) Toplam-map için 3 agregat VIEW (yeni SQL, security_invoker → RLS+otel otomatik)
PostgREST tek satır/ürün toplamı için view en temiz yol. Hepsi `security_invoker=true`:
- `stok_acik_siparis(urun_kodu, bekleyen_miktar)` — açık siparişlerdeki (siparisler.durum bekleyen/kismi)
  `siparis_kalemleri.kalan_miktar` toplamı, ürün bazlı. Otel-scope: siparisler'e join (RLS'li parent).
- `stok_acik_talep(urun_kodu, talep_miktar)` — siparişe dönüşmemiş taleplerdeki (satin_alma_talepleri
  uygun durum) `satin_alma_talep_kalemleri.miktar` toplamı, ürün bazlı.
- `stok_son_hareket(urun_kodu, depo_kodu, son_tarih)` — `max(stok_hareketleri.tarih)` ürün+depo bazlı.
- NOT: kolon/durum adları CANLI şemaya göre implementasyonda kesinleşir (siparisler.durum değerleri,
  satin_alma_talepleri.durum, siparis_kalemleri.kalan_miktar, stok_hareketleri.tarih doğrulanır).
- İzin: authenticated select (RLS otel-scope zaten parent tablolardan gelir).

### 2) İstemci veri katmanı (stok-takip.html)
- Görünüm/depo yüklenince 3 view'dan çek → `Map(urun_kodu → değer)` üç harita: `siparisMap`, `talepMap`,
  `sonHareketMap` (aktif depo için). Hafif sorgular (ürün başına tek satır), RLS otomatik.
- Stok item'ına hesaplanan alanlar OKUMA anında bağlanır (item'ı kirletmeden `getValue` ile), veya
  render öncesi map'ten okunur.

### 3) Görünüm geçişi + tablo render (stok-takip.html)
- **"Kart / Tablo" toggle** (arama kutusu bölgesinde). `stokGorunum = 'kart' | 'tablo'` state.
- `renderStok()` mevcut süzme+sıralamadan sonra: `stokGorunum==='tablo'` ise `renderStokTablo(filtered)`,
  değilse mevcut kart render. Süzme/sekme/gelişmiş filtre AYNI (tek `filtered`).
- `renderStokTablo(rows)`: `<div style="overflow-x:auto"><table>` — başlıklar + satırlar.
  Sütunlar: Kalem Kodu, Kalem Adı, Miktar, Birim, Min, Kategori, ABC, Durum, Sipariş(bekleyen),
  Talep(bekleyen), Son Hareket. Satıra tıkla → `openDetay(aktifDepoId, lnKod)` (kartla aynı).

### 4) Sütun başlığı: sıralama + filtre
- Başlığa tıkla → sıralama (metin A→Z/Z→A, sayı/tarih artan/azalan; aktif sütun+yön ok işaretiyle).
  `tabloSirala = {alan, yon}` state; render'da uygulanır.
- Başlıktaki **🔽** → o sütunun tipine uygun filtre girişi (filtre.js `OPS` + küçük popover) →
  `aktifStokFiltreleri`'ye ekler → renderStok. Merkezi "Gelişmiş Filtre" paneli de aynı state ile çalışır.
- Sütun→alan eşlemesi `STOK_TABLO_KOLONLARI` config: `{key,label,type,getValue}` (filtre.js alan configiyle uyumlu).

## Güvenlik / Performans
- View'lar security_invoker → yalnız kullanıcının otelinin verisi (RLS). İstemci ekstra sorgu 3 hafif view.
- Tablo `overflow-x:auto` (mobilde yatay kaydırma). Büyük depo için mevcut "hepsini belleğe yükle" deseni
  korunur (v1); ileride sunucu-taraflı sayfalama (filtre.js PostgREST iskelesiyle) ayrı iş.
- Değerler SQL'e gömülmez; filtre client-predicate.

## Kapsam DIŞI (v1)
Raf/Konum · sütun gizle/göster/yeniden-sırala özelleştirme · sabit (sticky) sütun zorunlu değil ·
tablo→Excel ayrı export (mevcut export korunur) · inline düzenleme · sunucu-taraflı sayfalama · çoklu-sütun sıralama.

## Test / Doğrulama Planı
1. Toggle: Kart↔Tablo geçişi; kart görünümü ve tüm mevcut özellikler (kritik/ABC/kategori/işlemler) bozulmadan çalışır.
2. Tablo sütunları doğru veri: kod/ad/miktar + Sipariş/Talep/Son Hareket (bilinen bir ürünle elle doğrula).
3. Sütun sıralama: ada göre A→Z, miktara göre azalan, son hareket tarihine göre.
4. Sütun filtre: Miktar başlığından ">10"; Son Hareket'ten "son 7 gün" → hem tablo hem kart aynı süzme.
5. Gelişmiş filtre paneli + sütun filtresi aynı state (biri diğerini bozmaz).
6. Otel izolasyonu: Sipariş/Talep/Son Hareket sadece kullanıcının otelinin verisi (view security_invoker).
7. Boş veri: hareketsiz ürün → Son Hareket boş; siparişsiz ürün → Sipariş 0/boş.

## Uygulama Devri
writing-plans → SDD. Faz: (1) 3 agregat view SQL (kullanıcı çalıştırır) → (2) istemci: toggle + 3 map yükleme +
renderStokTablo + sütun sıralama/filtre → (3) uçtan uca test. Her faz kullanıcı testi.
