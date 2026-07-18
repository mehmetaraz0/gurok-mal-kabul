# Faz B0 — RLS Bağlantı Katmanı — Tasarım

## Problem / Hedef

Faz A/A2 (2026-07-17/18) PIN girişini Supabase Auth'a bağladı ve gerçek
isteklerde kullanıcının `access_token`'ının kullanılmasını sağladı —
ama Postgres RLS politikaları hâlâ herkese açık (`using(true)`), yani
`auth.uid()` hiçbir yerde gerçek bir erişim kararı vermiyor. Bu faz,
RLS politikalarının ileride kullanacağı temel sorgu katmanını
hazırlıyor: "`auth.uid()` olan kullanıcının hangi modülde ne yetkisi
var?"

## Kapsam

İki salt-okunur (`stable`) SQL fonksiyonu:

1. `auth_kullanici_rol_id()` — `auth.uid()`'yi `kullanicilar.auth_user_id`
   üzerinden eşleştirip `rol_id`'yi döner.
2. `auth_yetki_var(p_modul_kod text, p_min_seviye text default 'goruntule')`
   — çağıran kullanıcının, verilen modül kodunda en az istenen seviyede
   (`goruntule` < `kayit` < `tam`) yetkisi olup olmadığını `boolean`
   olarak döner. `yetki_matrisi.yetki` kolonunun özel enum tipi
   (`yetki_seviye`) olması nedeniyle karşılaştırmada `::text` cast'i
   gerekti (curl ile tespit edildi, `otel_id` enum sorunuyla aynı desen).

**Bu fazda hiçbir tabloya, hiçbir RLS politikasına bağlanmıyor** —
fonksiyonlar var ama henüz kimse çağırmıyor, davranış değişmiyor.

## Kapsam dışı

- Otel bazlı kısıtlama (`kullanicilar.otel_id` ile eşleştirme) — ayrı,
  sonraki bir alt-faz.
- Gerçek tablolara RLS politikası eklenmesi (Faz B1+).
- İstemci tarafı UI'da sayfa/buton görünürlüğünün bu yetkiye bağlanması
  (Faz B3, ayrı — kozmetik, gerçek güvenlik değil).

## Mimari

```sql
create or replace function auth_kullanici_rol_id() returns uuid
language sql stable
as $$
  select rol_id from kullanicilar where auth_user_id = auth.uid() limit 1;
$$;

create or replace function auth_yetki_var(p_modul_kod text, p_min_seviye text default 'goruntule') returns boolean
language sql stable
as $$
  select exists (
    select 1 from yetki_matrisi ym
    join moduller m on m.id = ym.modul_id
    where ym.rol_id = auth_kullanici_rol_id()
      and m.kod = p_modul_kod
      and ym.yetki::text = any(
        case p_min_seviye
          when 'goruntule' then array['goruntule','kayit','tam']
          when 'kayit' then array['kayit','tam']
          when 'tam' then array['tam']
          else array[]::text[]
        end
      )
  );
$$;
```

`security invoker` (varsayılan) kullanılıyor — `kullanicilar` ve
`yetki_matrisi` tablolarının mevcut RLS politikaları (`using(true)`,
hem `anon` hem `authenticated` role) zaten SELECT'e izin veriyor, ekstra
ayrıcalık yükseltmeye gerek yok.

## Test / doğrulama planı (gerçekleştirildi)

Gerçek bir kullanıcının (rol: `grup_direktor`) token'ıyla curl ile
doğrudan test edildi:
- `auth_kullanici_rol_id()` → doğru rol UUID'sini döndü.
- `auth_yetki_var('cari_hesaplar','goruntule')` → `true` (yetki_matrisi'nde
  bu rol için `goruntule` var).
- `auth_yetki_var('cari_hesaplar','kayit')` → `false` (seviye ayrımı
  doğru — sadece `goruntule` var, `kayit` değil).
- `auth_yetki_var('guvenlik_stogu','goruntule')` → `false` (bu role hiç
  tanımlanmamış yeni modül — eksik satır doğru şekilde "yok" sayıldı).
- Anon key (giriş yapmamış istek) ile → `false` (güvenli varsayılan,
  `auth.uid()` null olduğunda hiçbir eşleşme bulunamıyor).

Tüm senaryolar beklenen sonucu verdi.
