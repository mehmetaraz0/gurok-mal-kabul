# Modül Aç/Kapa Kataloğu — Tasarım

**Bağlam:** "Tek-müşteri-tek-kurulum, esnek modüler" satış stratejisinin temel altyapısı. Amaç: her müşteri kurulumu, satın aldığı modülleri çalıştırabilsin — satın almadığı modüller kullanıcı rolünden bağımsız olarak tamamen kapalı kalsın.

## Problem

Portal (`index.html`) bugün sadece **kullanıcı bazlı** yetkiyi kontrol ediyor (`kullaniciYetkileriGetir()` → `yetki_matrisi`, rol_id'ye bağlı). **Kurulum bazlı** bir "bu müşteri bu modülü hiç satın aldı mı" kavramı hiçbir yerde yok — bir yöneticinin `yetki_matrisi`'ne satın alınmamış bir modül için satır eklemesini engelleyen hiçbir mekanizma yok. Repo genelinde `lisans`/`paket`/`abonelik`/`subscription`/`license` için grep sıfır sonuç döndü.

## Kapsam

Kontrol granülaritesi: mevcut `yetki_matrisi`/`moduller` ile AYNI ince-taneli seviye (41 modül) — kart seviyesinde (10 portal kartı) değil.

## Veri Modeli

`moduller` tablosuna tek yeni sütun:

```sql
alter table moduller add column aktif boolean not null default true;
```

`default true` — mevcut canlı kurulum (Gürok'un kendi kullanımı) hiçbir davranış değişikliği yaşamadan çalışmaya devam eder. Anahtar sadece yeni müşteri kurulumlarında bilinçli olarak `false`'a çekilen modüller için anlam kazanır. Yeni tablo YOK — `moduller` zaten doğru granülaritede 41 satır içeriyor.

## Uygulama Noktası — Merkezi, İki Choke-Point

Prensip: yeni bir gate her yere eklemek yerine, sistemin zaten dayandığı iki merkezi kontrol noktasına gömülür — böylece 40+ dosyaya dokunmadan tüm sistem otomatik kapsanır.

1. **RLS (sunucu tarafı):** `auth_yetki_var(p_modul_kod text, p_min_seviye text default 'goruntule') returns boolean` fonksiyonu, mevcut `yetki_matrisi` kontrolüne ek olarak `moduller.aktif = true` şartını arar. Bu fonksiyon halihazırda 40+ tablonun RLS policy'sinde kullanıldığı için, fonksiyonun kendisini bir kere değiştirmek hiçbir policy'ye dokunmadan tüm veritabanını kapsar.

2. **İstemci (UI):** `kullaniciYetkileriGetir()` (`auth-guard.js`), `yetki_matrisi?select=yetki,moduller(kod)` sorgusunu `moduller.aktif`'i de içerecek şekilde genişletir; pasif bir modül döndürülen haritada hiç yer almaz (kullanıcının gerçek `yetki_matrisi` satırı ne olursa olsun). Bu fonksiyon zaten `index.html`'in portal kart filtrelemesinin VE her sayfadaki `YETKI_HARITASI[...]` tabanlı buton/kaydet-gösterme mantığının TEK kaynağı — yani portal kartları ve tüm sayfa-içi buton gizleme otomatik güncellenir, `muhasebe-*.html`/`satin-alma-*.html`/vb. hiçbirine dokunulmaz.

**Portal kart davranışı:** Bir kart birden fazla alt-modülü kapsıyorsa (örn. Muhasebe → 20 alt-modül), kart en az bir alt-modülü hem yetkili hem aktifse görünür kalır (mevcut `.some(...)` mantığı otomatik olarak yeni haritayı kullanır). Kartın İÇİNDEKİ pasif alt-modüllere ait butonlar, zaten var olan `YETKI_HARITASI` tabanlı disabled-buton deseniyle kapalı kalır — ek bir UI değişikliği gerekmez.

## Yönetim Ekranı

`yetki-yonetimi.html` (zaten 41 modülü `moduller?select=*&order=sira` ile listeleyen sayfa) bir "Aktif" toggle sütunu kazanır. `yonetici` rolü bir modülü tek tıkla açıp kapatabilir — `moduller` tablosuna `PATCH`. Yeni sayfa yok.

## Hata Yönetimi / Kenar Durumlar

- Bir kullanıcı, kartı portal'da gizlenmiş bir sayfaya DOĞRUDAN URL ile giderse: sayfanın kendi `requireRole()` (kaba, `user.rol` tabanlı) kontrolü hâlâ geçebilir, ama o sayfadaki tüm veri sorguları RLS tarafından engellenir (auth_yetki_var artık false döner) — kullanıcı boş listeler görür. Bu, sistemin zaten yetkisiz erişimde gösterdiği mevcut davranışla tutarlı (sessiz boş durum) — yeni bir "bu modül satın alınmamış" mesajı bu fazın kapsamı dışında (YAGNI, mevcut UX deseniyle tutarlı).
- `moduller.aktif` sorgulanamazsa (ağ hatası): `kullaniciYetkileriGetir()` zaten hata durumunda boş obje döner (`{}` — en güvenli varsayım, hiç yetki yokmuş gibi davranır) — yeni sütun bu fail-safe davranışı bozmaz.

## Test/Doğrulama Planı

- Şema: `alter table` kullanıcı tarafından Supabase SQL editöründe çalıştırılır, curl ile `moduller.aktif` sütununun varlığı ve varsayılan `true` değeri doğrulanır.
- `auth_yetki_var()` güncellemesi: curl ile önce bir modülü `aktif=false` yap, o modüle bağlı bir tabloya (örn. `stok_takip` → `stok_hareketleri` gibi) gerçek bir kullanıcı JWT'siyle erişimin reddedildiğini doğrula (bu oturumda gerçek JWT olmadığı için bu adım kullanıcının tarayıcıda manuel testine bırakılabilir — anon key zaten tüm tabloları reddediyor, bu test farkı göstermez).
- `kullaniciYetkileriGetir()` güncellemesi: tarayıcı konsolunda bir modülü pasif yapıp haritada göründüğünü/görünmediğini kontrol et.
- `yetki-yonetimi.html`: manuel UI testi — bir modülü kapat, portal'a dön, ilgili kartın (veya kart içindeki ilgili alt-modülün buton/erişiminin) beklenen şekilde değiştiğini doğrula, sonra tekrar aç.
