# Stok Takip — Veri Eksiksizliği — Uygulama ve Yayın Planı

**Tarih:** 2026-09-14 · **Spec:** `docs/superpowers/specs/2026-09-14-stok-veri-eksiksizligi-design.md`
**Durum:** kod tamam, izole testler geçti · **ÜRETİME UYGULANMADI**

> Not: bu belge uygulamadan sonra yazıldı; sıra spec → kod → belge oldu. Kayıt
> olarak tutuluyor, çünkü asıl işi yayın anında görecek: migration sırası,
> duman testleri ve geri dönüş yolu burada.

**Amaç:** Stok ekranının sunucudan dönen veriyi eksiksiz sanmasını bitirmek.
Her okuma ya eksiksiz veri döner ya da görünür hata verir; yazan hiçbir akış
kanıtlanmamış veriyle ilerlemez.

**Mimari:** DOM bilmeyen bir veri katmanı (`stok-veri.js`) tüm okumaları
`Range` + `Prefer: count=exact` ile sayfalar ve `Content-Range`'den gerçek
toplamı okur. Toplamlar ve kategoriler ekrandaki listeden değil, `security_invoker`
görünüm/fonksiyonlardan gelir. Ekran yalnız sunum yapar.

**Teknoloji:** statik HTML/JS + Supabase (PostgREST) · testler için atılabilir
postgres:17 + postgrest v12.2.3 konteynerleri.

## Global kısıtlar

- RLS, rol ve yetki satırı **değişmez**. Yeni nesneler `security_invoker` /
  SECURITY INVOKER; `anon`'a kapalı, `authenticated` + `service_role`'a açık.
- Eşik semantiği bugünkü `getStokDurum` ile **birebir** aynı; minimum ürün
  başına depolar arası en yüksek değer olarak korunur.
- HTTP hatası **boş liste sayılmaz**.
- Genel toplamlar **mevcut sayfadan hesaplanmaz**.
- Migration ve arayüz üretime ancak ayrı bir `CANLIYA UYGULA` onayıyla çıkar.

## Dosya yapısı

| Dosya | Sorumluluk |
|---|---|
| `stok-veri.js` (yeni) | Sayfalama, eksiksizlik kanıtı, `StokVeriHatasi`. Ekran ve testler aynı modülü çağırır. |
| `docs/kurulum/2026-09-14-stok-liste-ozet.sql` (yeni, **aday**) | `stok_liste` görünümü + `stok_ozet` / `stok_kategoriler` / `stok_abc_girdi`; sonunda kendi kendini doğrulayan `do` bloğu. |
| `stok-takip.html` | Yalnız sunum + çağrı. Sayım onayında eksiksizlik kapısı. |
| `scripts/stok-veri-eksiksizlik.test.mjs` (yeni) | İzole ortam; sunucu satır tavanı 100. |

## Tamamlanan görevler

- [x] **1. Veri katmanı** — `stok-veri.js`; `tumSayfalariCek` toplam elde
      edilene kadar döner, ara sayfa hatasında **fırlatır**, toplam
      bilinmiyor + sayfa doluysa kırpılma varsayar. (`1d8293f`)
- [x] **2. Aday migration** — görünüm + üç fonksiyon + ACL + doğrulama bloğu.
      (`1d8293f`, `db91ff2`)
- [x] **3. Sayım onayı kapısı** — `sayimDetaylariniGetir(oturumId,
      toplam_urun_sayisi)`; hata ya da adet uyuşmazlığında onay **hiç
      başlamaz**, tek stok satırına dokunulmaz. (`cf8849c`)
- [x] **4. Açılışta toplu indirme yok** — `stok` ve `stok_hareketleri`
      artık `loadDB` içinde çekilmiyor. (`cf8849c`)
- [x] **5. Sunucu sayfalı liste** — `STOK_SAYFA=100`, sonsuz kaydırma, depo
      ve arama filtreleri sunucuda; hata görünür. (`db91ff2`)
- [x] **6. Sunucudan toplamlar/kategoriler/ABC** — okunamazsa sayı yerine
      `—`, ABC sınıflandırması girdiyi alamazsa sınıflandırmaz. (`db91ff2`)
- [x] **7. Sunucu tarafı ürün araması** — iki açılır listede de; katalog
      yalnız ad/birim süslemesi. (`db91ff2`)
- [x] **8. Sayfalı hareket geçmişi** — `HAREKET_SAYFA=100`, istek üzerine.
      (`db91ff2`)
- [x] **9. Kalan fail-open okumalar** — onay bekleyen sayım listesi ve
      rozeti; hata artık "0 bekleyen" gibi görünmüyor. (`db91ff2`)

## Doğrulama (çalıştırıldı)

```bash
node scripts/check.mjs
node scripts/stok-veri-eksiksizlik.test.mjs
node scripts/hazirlik-kilidi.mjs
```

Sonuç: `JS OK` · `Tüm statik kontroller geçti` · **19 OK / 0 FAIL** ·
`11 dosya AYNI`. Kapsanan senaryolar: 999 / 1.000 / 1.001 / 5.000 satır,
sunucu tavanı 100, ara sayfa hatası, son sayfadaki ürünü arama, eksik
detayla sayım onayının engellenmesi (stok toplamı değişmedi:
`501501.000 -> 501501.000`), `anon` erişiminin kapalı olması.

## Yayın sırası (`CANLIYA UYGULA` geldiğinde)

1. **Yedek + sayaçlar:** `docs/kurulum/yedek-ve-sayac-al.ps1` (şifreli,
   auth dahil). Yedeksiz migration yok.
2. **Preflight (salt okuma):** `stok`, `urunler`, `stok_minimumlar` satır
   sayıları; `stok_liste` / `stok_ozet` adlarının çakışmadığının kontrolü.
3. **Migration:** `psql --single-transaction -f
   docs/kurulum/2026-09-14-stok-liste-ozet.sql`. Dosyanın SHA-256'sı
   uygulanmadan önce ve sonra kayda geçer. Sonundaki `do $dogrula$` bloğu
   RLS/ACL/SECURITY INVOKER kontrollerini kendisi yapar; hata verirse işlem
   geri alınır.
4. **Migration sonrası kanıt:** `select count(*) from stok_liste;` ile
   `select count(*) from stok;` eşit olmalı; `select * from stok_ozet(null);`
   toplamı aynı sayıyı vermeli.
5. **Arayüz:** `stok-veri.js` + `stok-takip.html` main'e alınır, push edilir.
6. **Duman testleri (gerçek kullanıcıyla):**
   - Stok listesi açılıyor, aşağı kaydırınca sonraki dilim geliyor.
   - Üstteki toplam/kritik/uyarı sayıları `stok_ozet` sonucuyla aynı.
   - Katalogda aşağılarda kalan bir ürün aramayla bulunuyor.
   - Hareketler sekmesi açılınca geçmiş geliyor, tarih filtresi çalışıyor.
   - Onay bekleyen bir sayım açılıp onaylanıyor; stok gerçekten değişiyor.
   - Cost control dışı bir kullanıcı sayım onayı ekranını göremiyor.
7. **Geri dönüş:** arayüz için önceki commit'e dönmek yeterli. Migration
   yalnız ekleme yapar (yeni görünüm + üç fonksiyon); gerekirse
   `drop function`/`drop view` ile geri alınır, mevcut tablolara dokunulmaz.

## Kapsam dışı / kayda geçen bulgu

- `stok` tablosunda `birim` sütunu yok; birim yalnız `urunler`'den geliyor.
- Minimumun depo bazında ele alınması **ayrı bir karar**; bu iş bugünkü
  "depolar arası en yüksek" davranışı birebir koruyor.
