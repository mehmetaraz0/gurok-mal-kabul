# Bar Aşama 0 — İzole Test Tabanı — Rapor

**Tarih:** 2026-09-17 · **Sonuç:** GEÇTİ — `BAR TABAN SONUC: 8 OK / 0 FAIL`, çıkış kodu 0
**Commit:** `7586522` (dosyalar) · üretime hiçbir şey uygulanmadı, push yok
**Tasarım:** `docs/superpowers/specs/2026-09-17-bar-guvenlik-ikmal-kabul-design.md`

## Amaç

Aşama 1–4'ün tüm testlerinin üzerinde çalışacağı izole veritabanını kurmak ve bu tabanın
**gerçek üretim şemasını** doğru yansıttığını kanıtlamak. Aşama 0 hiçbir iş kuralı değiştirmez.

## Kurulan dosyalar

| Dosya | Görev |
|---|---|
| `scripts/bar-test-auth.sql` | Test katmanı: `auth.uid()` / `auth.role()` PostgREST v12'nin `request.jwt.claims` JSON'undan da okur. Kilitli `supabase-shim.sql` değiştirilmedi, üstüne yazıldı. |
| `scripts/bar-test-ortam.mjs` | Atılabilir `postgres:17`; taban yükleme; `sql`, `kimlikle`, `paralel`, `uygula`, `hataKodu`, `kurulumBilgisi`. |
| `scripts/bar-test-tohum.sql` | Modül/rol/yetki, 5 kimlik, 810 ve 811 PMS konaklamaları, stok, menü. |
| `scripts/bar-test-taban.test.mjs` | Tabanı doğrulayan test. |

## Taban sırası

`supabase-shim.sql` → `bar-test-auth.sql` → `C:\Users\USER\ERP-Yedek\2026-09-13-post-faz2-sema-dokumu.sql`
→ `docs/kurulum/2026-09-14-stok-liste-ozet.sql` → `bar-test-tohum.sql`

## Koşular

| Koşu | Sonuç | Açıklama |
|---|---|---|
| 1 | **0 OK / 1 FAIL** | Döküm yüklemesi `ERROR: schema "public" already exists` ile düştü. |
| 2 | 7 OK / 0 FAIL | Neden ölçüldü ve dar istisna eklendi (aşağıda); nesne sayısı kontrolü eklendi. |
| 3 | **8 OK / 0 FAIL** | Rezervasyon görünürlüğü ölçümü eklendi. |

### Koşu 1'in nedeni

`pg_dump` şema dökümünün başına `CREATE SCHEMA public;` yazar (dökümün 33. satırı); `public`
her boş PostgreSQL veritabanında zaten vardır. Projenin kilitli E-5 geri yükleme provası
(`scripts/pms-yedek-geri-yukleme-provasi.mjs`, `yukHatalari`) ve `scripts/dokum-dogrula.mjs`
yalnız bu satırı zararsız sayar. Test ortamı aynı kuralı **tam eşleşmeyle** uygular; başka her
hata kurulumu durdurur ve istisnaya düşen satır sayısı raporlanır.

## Son koşunun çıktısı (birebir)

```
OK   taban kuruldu: shim + kimlik katmani + uretim dokumu + stok migration + tohum — dokum: 0 hata, 1 bilinen zararsiz (schema public already exists)
OK   uretim bar nesneleri dokumdeki sayilarla birebir yuklendi (fonksiyon|politika|tetikleyici) — katalog 5|13|5 / dokum 5|13|5
OK   auth.uid() request.jwt.claims JSONundan okunuyor — 11111111-0000-0000-0000-000000000810
OK   BAR810: bar kayit yetkisi var, 810 erisimi var, 811 yok — t|t|f
OK   PASIF kullanicinin yetkisi yok (fail-closed) — f
OK   bar siparis tablosu bos basliyor — 0
OK   mevcut (uretim) bar_siparis_olustur tabanda calisiyor — t
OK   Z1 olcumu: aktif rezervasyon var ama depo kullanicisi onu RLS yuzunden GOREMIYOR — gercek 1, depo kullanicisi goruyor 0

BAR TABAN SONUC: 8 OK / 0 FAIL
taban_kod=0
```

## Ne kanıtlandı

1. Üretim şema dökümü izole ortama **0 gerçek hatayla** yükleniyor.
2. Bar nesneleri eksiksiz: fonksiyon, politika ve tetikleyici sayıları **dökümden sayılan**
   değerlerle birebir (5 / 13 / 5). Beklenen sayılar elle yazılmadı.
3. Kimlik, PostgREST'in yaptığı gibi rol + `request.jwt.claims` ile kuruluyor ve üretimdeki
   yetki fonksiyonları buna doğru tepki veriyor: 810 kullanıcısı 811'e erişemiyor, pasif
   kullanıcının yetkisi yok.
4. Üretimdeki `bar_siparis_olustur` bu tabanda olduğu gibi çalışıyor — Aşama 1'in "önce"
   ölçümleri gerçek koda karşı yapılabilir.
5. **Ölçülen gerçek:** `stok_ekle` / `stok_takip` yetkisi olan ama bar yetkisi olmayan depo
   kullanıcısı, aktif bir rezervasyon varken `stok_rezervasyonlari`'nda **0 satır** görüyor.

## Ne kanıtlanmadı / kapsam dışı

- Hiçbir iş kuralı değişikliği (Aşama 1 başlamadı).
- Edge Function'lar: bu tabanda çalışmaz; Deno, Supabase CLI ve Edge Runtime imajı yerelde yok
  (2026-09-17'de kontrol edildi). Uçtan uca Edge Function testi **açık test açığıdır**.
- Gerçek PostgREST üzerinden HTTP akışı (bu taban doğrudan psql ile rol + JWT iddiası kurar).
- Üretim verisiyle geçiş davranışı (tohum yapay veridir).

## Tekrar çalıştırma

```bash
node scripts/bar-test-taban.test.mjs; echo "kod=$?"
```

Ön koşullar: Docker Desktop açık; `C:\Users\USER\ERP-Yedek\2026-09-13-post-faz2-sema-dokumu.sql`
mevcut (başka döküm için `BAR_TEST_SEMA` ortam değişkeni).
