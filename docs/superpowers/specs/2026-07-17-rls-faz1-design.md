# RLS Faz 1 — DB Seviyesinde DELETE Engeli — Tasarım

## Problem / Hedef

Güvenlik/bütünlük denetim raporunun en yüksek severity maddesi (P0):
Supabase'de hiçbir Row Level Security (RLS) politikası yok, anon key
istemci kodunda açık — teknik bir kullanıcı devtools'tan doğrudan
`fetch()` çağrısı yaparak herhangi bir tabloyu okuyup yazabilir/silebilir.
Bu projede soft-delete işiyle (7 tablo) DELETE'i istemci tarafında
PATCH'e çevirdik, ama bu sadece UI seviyesinde bir koruma — devtools'tan
gönderilen ham bir `DELETE` isteği hâlâ çalışır ve soft-delete korumasını
komple atlar.

**Tam RLS (per-kullanıcı yetkilendirme) Supabase Auth'a geçiş gerektirir**
— bu, giriş akışının, `auth-guard.js`'in ve düzinelerce dosyanın header
mantığının yeniden yazılmasını gerektiren, ayrı ve büyük bir proje. Bu
tasarım SADECE dar kapsamlı, Auth gerektirmeyen bir ilk adımı (Faz 1)
kapsar: veritabanı seviyesinde TÜM DELETE'leri engellemek.

## Kapsam

**11 tablo, iki grup:**

1. Soft-delete'e geçirilen 7 tablo: `cariler`, `faturalar`, `demirbaslar`,
   `cek_senetler`, `banka_kasa_hesaplari`, `butce_kayitlari`, `kullanicilar`.
2. Hiç hard-delete edilmeyen, güvenlik ağı olarak eklenen 4 tablo: `stok`,
   `stok_hareketleri`, `cari_hareketler`, `banka_kasa_hareketleri` (soft-delete
   işinde bu ikisinin cascade-DELETE çağrıları zaten kaldırılmıştı).

Her tabloda RLS açılır; `SELECT`/`INSERT`/`UPDATE` **serbest bırakılır**
(`using(true)`/`with check(true)`) — bugünkü davranış birebir korunur.
**DELETE için hiç politika tanımlanmaz** — Postgres RLS kuralı gereği,
politikasız işlem varsayılan olarak reddedilir. Bu, API üzerinden (anon
key ile, devtools dahil) kalıcı silmeyi veritabanı seviyesinde tamamen
kapatır.

## Kapsam dışı

- `yevmiye_kalemleri`/`fatura_kalemleri`/`recete_kalemleri`/`siparis_kalemleri`
  gibi "sil-yeniden-yaz" satır-kalemi tabloları — bunlara RLS
  uygulanmaz, düzenleme akışları hâlâ DELETE'e ihtiyaç duyuyor.
- Kolon/satır seviyesinde okuma kısıtı (örn. kullanıcı PIN'lerinin kim
  tarafından görülebileceği) — bu, tam Auth migrasyonu gerektiren ayrı
  ve daha büyük bir konu; bu faz sadece DELETE'i kapatıyor, okuma/yazma
  yetkilendirmesine dokunmuyor.
- Tam per-kullanıcı RLS (gerçek yetkilendirme) — Supabase Auth'a geçiş
  gerektirir, ayrı bir proje olarak ele alınacak.
- `stok_ekle`/`stok_transfer` RPC'lerinin değiştirilmesi — gerek yok,
  `stok` tablosunda UPDATE serbest kaldığı için bu RPC'ler sorunsuz
  çalışmaya devam eder (RPC'ler `SECURITY INVOKER`, anon rolünün UPDATE
  izniyle çalışıyorlar).

## Mimari

Tüm 11 tablo için aynı 4 satırlık şablon, TEK bir SQL transaction'ı
(`begin`/`commit`) içinde uygulanır — biri bile hata verirse hiçbiri
uygulanmaz, hiçbir tablo yarım-korumalı/bozuk durumda kalmaz:

```sql
alter table <tablo> enable row level security;
create policy "allow_select" on <tablo> for select using (true);
create policy "allow_insert" on <tablo> for insert with check (true);
create policy "allow_update" on <tablo> for update using (true) with check (true);
-- DELETE politikası YOK — varsayılan olarak reddedilir.
```

Bu şablon 11 tabloya (yukarıdaki liste) tek tek uygulanır, hepsi
`begin;`/`commit;` arasında.

## Test/doğrulama planı

Statik: SQL'in `begin`/`commit` içinde olduğunu, her tabloda tam olarak
3 politika (`select`/`insert`/`update`) tanımlandığını, hiçbir tabloda
`delete` politikası olmadığını kod okuyarak doğrulamak.

Gerçek doğrulama (SQL çalıştırıldıktan hemen sonra): Claude, `curl` ile
bu 11 tablodan birine doğrudan bir `DELETE` isteği göndererek reddedildiğini
(HTTP 403, Postgres hata kodu `42501`) teyit eder. Kullanıcı ayrıca normal
uygulama akışında (bir cari/bütçe/fatura kaydı oluştur, düzenle) hiçbir
şeyin bozulmadığını doğrular — `SELECT`/`INSERT`/`UPDATE` tamamen
serbest kaldığı için regresyon beklenmiyor.
