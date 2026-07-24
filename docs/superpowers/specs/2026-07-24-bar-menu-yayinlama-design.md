# Bar Menü Yayınlama Otomasyonu — Tasarım

**Tarih:** 2026-07-24
**Amaç:** Personelin ana ERP projesinde (`erp`, ref `xwytofysmgqtqjzkplfi`) düzenlediği bar menüsünü tek tıkla müşteri projesine (`gurok-bar-musteri`, ref `udjpcsjifgdzvfflezaa`) tek yönlü senkronlaması.

## Bağlam / Mevcut Durum

- Bar müşteri tarafı kurulu: müşteri projesinde `menu_urunler`/`masa_tokenlari`/`siparis_arsiv` + Edge Function `hyper-api` (sipariş köprüsü). Secret'lar tanımlı: `MAIN_SB_URL`, `MAIN_SERVICE_KEY`, `CUSTOMER_SB_URL`, `CUSTOMER_SERVICE_KEY`.
- Menü şu an **elle** iki projeye giriliyor (SQL). Bu tasarım o senkronu otomatikleştirir.
- Ana `menu_urunler`: id, ad, kategori, otel_id, fiyat, aktif, ucretli, tip, stok_kodu, miktar_per_porsiyon, silindi.
- Müşteri `menu_urunler` (bu tasarımdan ÖNCE): id, ad, kategori, fiyat, ucretli, aktif.

## Kararlar (kullanıcı onaylı)

- **Tetikleyici:** Mevcut `bar-siparis-kuyrugu.html` kuyruk ekranına "Menüyü Yayınla" butonu. Menü SQL ile düzenlenmeye devam eder; buton yalnız senkronu tetikler.
- **Otel kapsamı:** Menü otele göre AYRI. Müşteri `menu_urunler`'e `otel_id` eklenir; müşteri sayfası masanın oteline göre filtreler.
- **Mekanizma:** Müşteri projesinde yeni Edge Function `menu-yayinla` (yaklaşım ①). Ana projeden okur, müşteriye yazar. `hyper-api`'den ayrı endpoint (müşteri-sipariş ile personel-yayın ayrımı korunur).
- **Senkron semantiği:** Tam değiştirme (full replace), atomik — müşteri `menu_yenile(jsonb)` RPC'si tek transaction'da tüm satırları silip ana projenin aktif (aktif=true, silindi=false) menüsüyle yeniden yazar. Pasif/silinen ürünler otomatik kaybolur; yayın sırasında boş-menü penceresi olmaz.

## Bileşenler

### 1. Müşteri projesi şema eklemeleri (`docs/kurulum/musteri-projesi/03-menu-yayin.sql`)

```sql
alter table public.menu_urunler add column otel_id text;

-- Masa→otel çözümü: yalnız BİLİNEN token için otel_id döner (token listesi sızdırmaz).
-- View kullanılmaz çünkü view'a anon select vermek tüm token listesini enumerable yapardı.
create or replace function public.masa_oteli_getir(p_token text)
returns text language sql stable security definer set search_path = public
as $$ select otel_id from public.masa_tokenlari where token = p_token and aktif = true $$;
grant execute on function public.masa_oteli_getir(text) to anon;

-- Atomik menü değiştirme (yalnız Edge Function service_role çağırır, anon'a AÇILMAZ)
create or replace function public.menu_yenile(p_menu jsonb)
returns integer language plpgsql security definer set search_path = public
as $$
declare v_sayi integer;
begin
  delete from public.menu_urunler;
  insert into public.menu_urunler (id, ad, kategori, fiyat, ucretli, aktif, otel_id)
  select (x->>'id')::uuid, x->>'ad', x->>'kategori', (x->>'fiyat')::numeric,
         (x->>'ucretli')::boolean, (x->>'aktif')::boolean, x->>'otel_id'
  from jsonb_array_elements(p_menu) x;
  get diagnostics v_sayi = row_count;
  return v_sayi;
end $$;
```

### 2. Edge Function `menu-yayinla` (`docs/kurulum/musteri-projesi/menu-yayinla/index.ts`)

- Müşteri projesinde deploy (Dashboard → Via Editor, JWT verify ON — anon key ile çağrılır).
- Akış: `MAIN_SERVICE_KEY` ile ana `menu_urunler?select=id,ad,kategori,fiyat,ucretli,aktif,otel_id&aktif=eq.true&silindi=eq.false` okur → dizi olarak `CUSTOMER_SERVICE_KEY` ile müşteri `menu_yenile(p_menu)` RPC'sine geçer → `{ok:true, sayi:N}` döner. Hata → `{ok:false, mesaj}`.
- Yeni secret gerekmez (mevcut 4 secret yeterli).

### 3. Kuyruk ekranı butonu (`bar-siparis-kuyrugu.html` değişiklik)

- "📢 Menüyü Yayınla" butonu, `yazabilir()` (bar_siparis_yonetimi kayıt) ile gösterilir/etkinleşir.
- onclick: onay ("Müşteri menüsü ana projedeki güncel menüyle değiştirilecek. Devam?") → `CUSTOMER_SB_URL/functions/v1/menu-yayinla`'ya POST (anon key) → sonuç mesajı ("✅ N ürün yayınlandı" / "❌ hata").
- `CUSTOMER_SB_URL` + müşteri anon key bu sayfada sabit tanımlanır (anon key public, sorun değil; sayfa personel-içi ama zaten müşteri anon key hyper-api için de kullanılıyor).

### 4. Müşteri sayfası otel filtresi (`bar-menu.html` değişiklik)

- Token alındıktan sonra `rpc/masa_oteli_getir` ({p_token: token}) → otel_id.
- otel_id null → "Geçersiz masa" (mevcut davranışa benzer).
- Menü fetch'i `menu_urunler?otel_id=eq.<X>&aktif=eq.true&order=kategori` olarak filtrelenir.

## Hata Yönetimi

- Edge Function: ana okuma veya müşteri RPC hatası → `{ok:false, mesaj}`, buton mesajda gösterir.
- `menu_yenile` atomik: insert sırasında hata olursa delete de geri alınır (eski menü korunur).
- Sayfa: `masa_oteli_getir` başarısız/null → sipariş engellenir ("Geçersiz masa").

## Test (uçtan uca)

1. Ana projeye 810 + 811 için birer `menu_urunler` satırı ekle (+ gerekli urunler/stok).
2. Kuyruk ekranından "Menüyü Yayınla" → müşteride 2 satır, doğru `otel_id`'lerle.
3. `bar-menu.html?t=<810-token>` → yalnız 810 menüsü görünür.
4. Ana projede 811 ürününü `aktif=false` yap → tekrar yayınla → müşteriden kaybolur.
5. İzolasyon: buton/sayfa ana proje ref'i içermez (grep=0); `menu_yenile` anon'a kapalı (42501).

## Kapsam Dışı

- Menü yönetim ekranı (menü hâlâ SQL ile düzenlenir — ayrı iş).
- İki yönlü senkron (yalnız ana→müşteri).
- Reçeteli ürünlerin bileşen detayının müşteriye taşınması (müşteri yalnız görüntü menüsü görür; reçete ana projede kalır).
