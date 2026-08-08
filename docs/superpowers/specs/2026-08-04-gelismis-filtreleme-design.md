# Gelişmiş Filtreleme Altyapısı — Tasarım Dokümanı

**Tarih:** 2026-08-04
**Durum:** Tasarım onaylandı (kullanıcı). Uygulama writing-plans → SDD.

## Amaç
ERP'deki tüm listeleme ekranlarında kullanılabilecek **merkezi, genişletilebilir, güvenli** bir
gelişmiş filtreleme altyapısı. Her sütun kendi veri tipine (metin/sayı/tarih/çoklu-seçim/boolean)
uygun operatörlerle filtrelenebilir; çoklu filtre (v1: VE), aktif filtre etiketleri, kayıtlı filtreler.
Önce **stok-takip pilotu**, sonra diğer ekranlara yayılım.

## Mevcut Sistem (2026-08-04 tespit)
- `stok-takip.html` tüm stok satırlarını tek seferde çeker (`/stok?select=*`, sayfalama yok) → bellekte.
- Veri **aktif depo bazlı** (`db.stok[aktifDepoId]`), liste **mobil-öncelikli KART** (klasik tablo/sütun-başlık YOK).
- Filtreleme tamamen istemci-taraflı: tek arama kutusu (ad/LN kod) + durum sekmeleri (Kritik/Uyarı/Normal)
  + kategori + ABC sekmeleri. Hepsi `renderStok()` içinde yüklü diziyi süzer.
- **Eksikler:** operatör yok, veri-tipine özel filtre yok, VE/VEYA/grup yok, aktif filtre etiketi yok,
  kayıtlı filtre yok, sütun-başı filtre yok, merkezi/tekrar-kullanılabilir yapı yok.

## Alınan Kararlar (kullanıcı onaylı)
1. **Yürütme (pilot):** İstemci-taraflı (client predicate) — mevcut kritik/ABC/kategori özellikleri bozulmaz.
   Filtre modeli yürütmeden AYRI → aynı model ileride PostgREST'e "derlenip" büyük ekranlarda sunucu-taraflı.
2. **Kombinatör (v1):** Tüm filtreler **VE**. VEYA + gruplar KAPSAM DIŞI (model ileride genişler).
3. **Kayıtlı filtreler:** **DB tablosu** (`kayitli_filtreler`) + RLS — kullanıcıya özel + yönetici ortak şablon.
4. **Sütun-başı filtre ikonları:** Kart UI'da başlık olmadığı için v1 DIŞI; merkezi "Gelişmiş Filtre" paneli kullanılır.
5. **Türkçe metin:** `toLocaleLowerCase('tr-TR')` (i/İ/ı/I doğru); ş/ç/ğ/ö/ü KORUNUR (diakritik silinmez).

## Mimari + Bileşenler

### 1) `filtre.js` (yeni paylaşımlı dosya — merkez)
Ekrandan bağımsız, saf yardımcı. Sorumluluklar ve **arayüz (interface)**:

- **`FILTRE_OPERATORLERI`** — `{text:[...], number:[...], date:[...], multi_select:[...], boolean:[...]}`.
  Her operatör: `{op, label, girisSayisi}` (girisSayisi: 0=değer yok [boş/bugün], 1=tek değer, 2=aralık).
- **`filtreleUygula(rows, filtreler)` → Array** — filtreler `[{field,type,operator,value}]`; her satır TÜM
  filtreleri (VE) geçmeli. Type'a göre karşılaştırma:
  - text: `metinKarsilastir(hucre, operator, value)` — normalize `toLocaleLowerCase('tr-TR')`.
  - number: parseFloat; between→`value:{min,max}`.
  - date: `Date`; presetler (bugün/bu hafta/son 7 gün/süresi geçmiş vb.) fonksiyonla üretilir; between→`{start,end}`.
  - multi_select: `value:[...]`, `in`/`not_in`/`equals`.
  - boolean: `value:true/false` (Tümü = filtre yok).
- **`filtrePaneliOlustur(container, filtreAlanlari, aktifFiltreler, onDegisim)`** — paneli render eder:
  alan seçici (select) → operatör seçici (type'a göre otomatik) → değer giriş(ler)i (type+operator'a göre),
  "+ Filtre Ekle" / satır "🗑️". `onDegisim(aktifFiltreler)` callback.
- **`aktifFiltreEtiketleri(container, aktifFiltreler, onKaldir)`** — her filtre için etiket
  (`Kalem Adı: SU içerir ✕`), tek tek kaldırma + "Tümünü temizle".
- **`kayitliFiltreleriGetir(ekran)` / `kayitliFiltreKaydet(ekran, ad, filtreler, paylasimli)` /
  `kayitliFiltreSil(id)`** — `kayitli_filtreler` tablosuna PostgREST (SB_HEADERS, RLS'li).
- **`filtreyiPostgresteDerle(filtreler)` (İSKELE, v1'de çağrılmaz)** — model→PostgREST query; ileride büyük
  ekranlar için. v1'de sadece imza + `throw 'v1 dışı'` ya da boş; genişletilebilirlik kanıtı.

### 2) `kayitli_filtreler` tablosu + RLS (yeni SQL)
```
create table public.kayitli_filtreler (
  id uuid primary key default gen_random_uuid(),
  kullanici_id text,             -- sahibi (kullanicilar.id); null = sistem şablonu
  ekran text not null,           -- 'stok-takip' vb — filtreler ekran-kapsamlı
  ad text not null,
  filtreler jsonb not null,      -- [{field,type,operator,value}]
  paylasimli boolean not null default false,  -- yönetici ortak şablonu
  olusturma_tarihi timestamptz not null default now()
);
```
RLS (authenticated):
- SELECT: `kullanici_id = auth_kullanici_id() OR paylasimli = true` (kendi + ortak şablonlar).
- INSERT/UPDATE/DELETE: `kullanici_id = auth_kullanici_id()` (yalnız kendininki). Paylaşımlı şablon
  oluşturma: yönetici yetkisi (`auth_yetki_var('kullanici_yonetimi','kayit')` veya benzeri) — implementasyonda netleşir.
- `auth_kullanici_id()`: auth.uid()→kullanicilar.id döndüren SECURITY DEFINER helper (yoksa eklenir;
  mevcut auth_otel_id deseniyle aynı).

### 3) Stok-takip pilot entegrasyonu (`stok-takip.html`)
- `<head>`'e `<script src="filtre.js"></script>`.
- **`STOK_FILTRE_ALANLARI`** config: kalem_kodu(text), kalem_adi(text), miktar(number), kategori(multi_select),
  abc(multi_select), skt/son_kullanma(date, varsa), durum(multi_select: kritik/uyari/normal). (Alanlar canlı
  veri modeline göre implementasyonda kesinleşir.)
- **"🔎 Gelişmiş Filtre" butonu** (mevcut arama kutusunun yanına) → panel aç/kapa.
- `renderStok()`: mevcut arama + sekme süzmesinden SONRA `filtreleUygula(items, aktifStokFiltreleri)` uygulanır
  (gelişmiş filtre, mevcutların ÜSTÜNE biner — hiçbiri kaldırılmaz).
- Aktif filtre etiketleri liste üstünde; kaydet/yükle kayitli_filtreler'e.

## UI Akışı
1. "Gelişmiş Filtre" → panel açılır.
2. Alan seç → operatör (type'a göre) → değer(ler).
3. "+ Filtre Ekle" ile çoklu (VE).
4. "Uygula" → liste süzülür + etiketler görünür.
5. Etiketten tek tek kaldır / "Tümünü temizle".
6. "Kaydet" (ad ver) / "Yükle" (kayıtlı/ortak şablon).
7. Genel arama kutusu KORUNUR (hızlı arama); gelişmiş filtre onunla birlikte çalışır.

## Güvenlik
- Client-predicate, RLS ile gelen (kullanıcının görebildiği) veri üzerinde çalışır → RLS aşılamaz.
- Değerler asla SQL metnine gömülmez (predicate JS) → SQL injection yok.
- Metin aramada debounce (300ms) — her tuşta yeniden-render'ı sınırla.
- Çok büyük çoklu-seçim listeleri: aramalı seçim (tümünü tek seferde DOM'a basma).
- Kayıtlı filtre yazımı RLS'li; ortak şablon yalnız yetkili.

## Kapsam DIŞI (v1)
VEYA + filtre grupları · sütun-başlığı filtre ikonları · klasik data-grid'e geçiş · sunucu-taraflı yürütme
(iskele hazır) · gelişmiş çoklu-sıralama önceliği (v1'de mevcut basit sıralama korunur).

## Test / Doğrulama Planı
1. Metin: "içerir/başlar/biter/boş" + Türkçe (İ/ı) doğru eşleşir; ş/ç korunur (şeker ≠ seker).
2. Sayı: >, arasında (min/max), sıfır; between iki değer alır.
3. Tarih (varsa): süresi geçmiş / son 7 gün / arasında doğru süzer.
4. Çoklu-seçim: kategori "listede biri" doğru; boolean Evet/Hayır/Tümü.
5. Çoklu filtre VE: "ad SU içerir VE miktar>10" birlikte.
6. Etiketler: her filtre etiketi + kaldırma + tümünü temizle.
7. Kayıtlı filtre: kaydet→yükle→uygula; RLS (başka kullanıcının filtresi görünmez); ortak şablon görünür.
8. Regresyon: mevcut arama kutusu + kritik/ABC/kategori sekmeleri + stok işlemleri BOZULMAZ.
9. Debounce: hızlı yazımda tek render.

## Uygulama Devri
writing-plans → SDD. Faz sırası: (1) filtre.js + kayitli_filtreler SQL (kullanıcı çalıştırır) →
(2) stok-takip pilot → (3) diğer ekranlar (ayrı, pilot kanıtlanınca). Her faz kullanıcı testi.
