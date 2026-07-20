# Birim Dönüşüm Sistemi — Tasarım

**Bağlam:** Güvenilirlik boşlukları çalışmasının ikinci yarısı (birincisi: soft-delete tamamlama, Faz B6, tamamlandı). Tek-müşteri-tek-kurulum satış modeli için ürün deposu/tüketim takibini daha okunaklı hale getirmek.

## Problem

`URUN_DB` (statik `gurok_veritabani.js`, ~1290 ürün) ve buna karşılık gelen Supabase `urunler` tablosunda her ürünün tek, sabit bir `birim` alanı var (KG/AD/KOL/KTU/PK/TRB/TNK/BDN/BOT/TKM). Bazı ürünler pratikte hem büyük birim (koli) hem küçük birim (kg) cinsinden düşünülüyor — örnek: "1 koli = 10 kg", 2.5 kg tüketim = 0.25 koli. Bugün bu dönüşüm hiçbir yerde tutulmuyor; `gunluk-tuketim.html` kullanıcıyı elle dönüştürmeye zorluyor ("Miktarı satın alma birimiyle aynı cinsten gir" uyarısı), diğer sayfalarda da miktarlar sadece tek birimde (kg) gösteriliyor.

## Kapsam Dışı (YAGNI)

- Depo siparişi/yeniden sipariş önerisi, güvenlik stoğu gibi otomatik hesaplamalara dönüşüm entegre edilmeyecek (bu fazda gerekmiyor).
- Mal kabulde gerçek ağırlık girişi değişmiyor — kullanıcı hep tartıp kg olarak giriyor. Dönüşüm oranı mal kabul girişini otomatikleştirmek için kullanılmıyor, sadece raporlama/gösterim amaçlı.
- Mevcut `URUN_DB` / `urunler` tablosu şeması ve ~1290 satırlık katalog değişmiyor.

## Veri Modeli

Yeni, küçük ve opsiyonel bir Supabase tablosu — sadece ihtiyacı olan ürünler için satır içerir:

```sql
create table urun_birim_donusum (
  id uuid primary key default gen_random_uuid(),
  urun_kodu text not null unique references urunler(kod),
  buyuk_birim text not null,                    -- örn. 'KOLİ'
  carpan numeric not null check (carpan > 0),   -- 1 buyuk_birim = carpan × birim (örn. 10)
  silindi boolean not null default false,
  guncelleme_tarihi timestamptz default now()
);
```

RLS: `auth_yetki_var('urun_yonetimi', 'goruntule')` ile SELECT, `auth_yetki_var('urun_yonetimi', 'kayit')` ile INSERT/UPDATE. Gerçek DELETE yok — soft-delete deseni (`silindi` sütunu), diğer tüm tablolarla tutarlı. Yeni `urun_yonetimi` modülü `yetki_matrisi`'ne eklenecek ve rollere dağıtılacak (sadece `sistem_admin` değil — daha önce 4 kez yakalanan seed-eksikliği tuzağına düşülmeyecek).

## Yeni Ekran: `urun-yonetimi.html`

- Ürün listesi `URUN_DB`'den (client-side, mevcut katalog — değişmiyor), arama/filtre ile.
- Her satırda iki opsiyonel giriş alanı: "Büyük Birim" (serbest metin, örn. "KOLİ") ve "Çarpan" (pozitif sayı, örn. 10).
- Kaydet → `urun_birim_donusum` tablosuna `on_conflict=urun_kodu` upsert (`Prefer: resolution=merge-duplicates`, `silindi:false` payload'a dahil — mevcut upsert deseniyle tutarlı, soft-delete'li bir satırın sessizce "canlanıp gizli kalması" riskini önler).
- Yetki: `requireRole` ile sayfa seviyesinde erişim, `auth_yetki_var('urun_yonetimi', ...)` ile buton/kayıt seviyesinde — mevcut Faz B3/B4 desenine (YETKI_HARITASI + disabled buton) uyumlu.
- Diğer yönetim ekranlarıyla (kullanici-yonetimi.html, yetki-yonetimi.html) aynı görsel/yapısal desen.

## Gösterim Entegrasyonu

`ortak.js`'e yeni bir ortak yardımcı: sayfa init'inde `urun_birim_donusum?select=urun_kodu,buyuk_birim,carpan&silindi=eq.false` bir kere çekilir, `{urun_kodu: {buyuk_birim, carpan}}` haritasına dönüştürülür (örn. `BIRIM_DONUSUM_HARITASI`). Bir yardımcı fonksiyon `birimDonusumEtiketi(urunKodu, miktarKg)`:
- Haritada kayıt yoksa `''` (boş) döner — hiçbir ek gösterim olmaz, mevcut davranış aynen korunur.
- Kayıt varsa `≈${(miktarKg/carpan).toFixed(2)} ${buyuk_birim}` döner.

**Dokunulacak sayfalar** (miktar gösterilen yerlerde bu etiket eklenecek, giriş alanları değişmeyecek):
1. `gunluk-tuketim.html` — tüketim miktarı yanında.
2. `stok-takip.html` — mevcut stok miktarı yanında.
3. `trend-raporlama.html` — tüketim/stok grafik ve tablolarında.
4. `satin-alma-siparisolustur.html` — sipariş miktarı yanında (bilgi amaçlı).
5. `mal-kabul-liste.html` — mal kabul miktarı yanında (bilgi amaçlı).

## Hata Yönetimi

`urun_birim_donusum` çekilemezse (ağ hatası, boş sonuç) harita boş kalır, `birimDonusumEtiketi` her zaman `''` döner — sayfa hiçbir işlevini kaybetmeden normal çalışmaya devam eder. Bu, kritik olmayan, tamamen katmanlı (additive) bir özellik; başarısızlığı sessiz ve zararsız olmalı.

## Test/Doğrulama Planı

- Şema: `urun_birim_donusum` tablosu + RLS policy'leri kullanıcı tarafından Supabase SQL editöründe çalıştırılacak, curl ile anon-SELECT-boş + anon-INSERT-reddedilir doğrulanacak (mevcut oturum deseni).
- `urun-yonetimi.html`: manuel UI testi — ürün ara, büyük birim + çarpan gir, kaydet, sayfayı yenile, değerin kalıcı olduğunu doğrula; yetkisiz kullanıcı için buton disabled/gizli olduğunu doğrula.
- 5 dokunulan sayfanın her birinde: çarpanı olan bir ürün için `≈X KOLİ` etiketinin doğru hesaplandığını, çarpanı olmayan ürünler için hiçbir ek metin çıkmadığını doğrula.
- `git show` ile her task'ın diff'i controller tarafından doğrudan incelenecek (düşük riskli, mekanik değişiklikler için — B6 fazındaki gibi), sadece yeni tablo şeması ve `urun-yonetimi.html` ekranı için tam implementer+reviewer iki aşamalı süreç kullanılacak.
