# Atomik Stok Güncelleme (RPC) — Tasarım

## Problem / Hedef

Sistemdeki tüm stok güncellemeleri "mevcut değeri GET et → JS'te hesapla →
mutlak değeri POST et" desenini kullanıyor. İki kullanıcı aynı anda aynı
ürünün stoğunu değiştirdiğinde, son yazan öncekini ezer (race condition) —
mal kabul, çıkış, transfer, tüketim ve iade akışlarında sistematik stok
hatalarına yol açar. Bu, satın alma/güvenlik denetim raporunda ve bu
projenin daha önceki Sayım düzeltmesinde tespit edilen P0 seviyesinde bir
veri bütünlüğü riski.

## Kapsam

- Yeni bir Supabase RPC fonksiyonu `stok_ekle(...)` — stok satırını
  sunucu tarafında **atomik** olarak `miktar = miktar + delta` ile
  günceller, yeni gerçek miktarı döndürür.
- Yeni bir Supabase RPC fonksiyonu `stok_transfer(...)` — depo transferinin
  iki bacağını (kaynaktan düş + hedefe ekle) **tek transaction** içinde
  yapar; hem race condition'ı hem "transaction eksikliği" (iki bacaktan
  biri başarısız olursa tutarsızlık) riskini transfer için birlikte çözer.
- Kod tabanındaki **7 stok-yazma noktasını** (`stok` tablosuna yapılan
  tüm `POST /rest/v1/stok?on_conflict=...` çağrıları) bu RPC'lere geçirmek:
  - `mal-kabul-v2.html`: `stokaIsle()` (giriş), `stoktanGeriAl()` (düzeltme geri alma)
  - `stok-takip.html`: `saveStok()` (giriş/çıkış), `transfer` akışı, `malKabulOnayKontrolEt()` güvenlik ağı
  - `depo-siparis.html`: `saveStok()`, transfer `onayla()`
  - `gunluk-tuketim.html`: `tuketimKaydet()` (günlük tüketim), `tuketKaydet()` (reçete tüketimi)

## Kapsam dışı

- `stok` tablosunun okuma noktaları (`loadDB`, `satin-alma.html` vb.) —
  sadece yazma noktaları değişir.
- Negatif stok davranışının değiştirilmesi — mevcut "0'ın altına düşme"
  davranışı (`Math.max(0, ...)`) korunur; RPC de `GREATEST(0, ...)`
  kullanır. Negatif stoğa izin verme veya "yetersiz stok" hatası fırlatma
  ayrı bir iş kararı, bu düzeltmenin kapsamında değil.
- `stok_hareketleri` (hareket geçmişi) yazımları — bunlar zaten INSERT
  (append-only), race'e tabi değil, dokunulmaz.
- Diğer denetim raporu maddeleri (RLS/Auth, soft-delete, hata yönetimi,
  para/sayı güvenliği) — ayrı, sonraki adımlarda ele alınacak.

## Mimari

### RPC 1: `stok_ekle`

```sql
create or replace function stok_ekle(
  p_urun_kodu text,
  p_depo_kodu text,
  p_otel_id text,
  p_delta numeric
) returns numeric
language plpgsql
as $$
declare
  v_yeni numeric;
begin
  insert into stok (urun_kodu, depo_kodu, otel_id, miktar)
  values (p_urun_kodu, p_depo_kodu, p_otel_id::otel_id, greatest(0, p_delta))
  on conflict (urun_kodu, depo_kodu)
  do update set miktar = greatest(0, stok.miktar + p_delta)
  returning miktar into v_yeni;
  return v_yeni;
end;
$$;
```

> **2026-07-17 düzeltme:** `stok.otel_id` kolonu `text` değil, özel bir enum tipi
> (`otel_id`) — plpgsql içinde text parametreyi cast'siz atamak Postgres
> hatası `42804` verir ("column is of type otel_id but expression is of
> type text"). Bu, fonksiyon deploy edildiği günden beri HER `stok_ekle`/
> `stok_transfer` çağrısının sessizce (veya Hata Yönetimi işinden sonra
> görünür şekilde) başarısız olmasına sebep oldu — atomik olduğu için hiç
> veri kaybı olmadı (her çağrı tamamen geri alındı), ama giriş/çıkış/
> transfer hiçbiri gerçekte kaydolmadı. Yukarıdaki ve aşağıdaki SQL bloğu
> `::otel_id` cast'ini İÇERİYOR (düzeltilmiş hal) — canlıda çalışan güncel
> hali budur.

- `p_delta` pozitif = giriş, negatif = çıkış.
- `on conflict (urun_kodu, depo_kodu)` — mevcut upsert anahtarıyla aynı.
- Yeni miktarı döndürür → client önbelleği doğru değere güncellenir.

### RPC 2: `stok_transfer`

```sql
create or replace function stok_transfer(
  p_urun_kodu text,
  p_kaynak_depo text,
  p_hedef_depo text,
  p_hedef_otel text,
  p_miktar numeric
) returns void
language plpgsql
as $$
begin
  update stok set miktar = greatest(0, miktar - p_miktar)
    where urun_kodu = p_urun_kodu and depo_kodu = p_kaynak_depo;
  insert into stok (urun_kodu, depo_kodu, otel_id, miktar)
    values (p_urun_kodu, p_hedef_depo, p_hedef_otel::otel_id, p_miktar)
    on conflict (urun_kodu, depo_kodu)
    do update set miktar = greatest(0, stok.miktar + p_miktar);
end;
$$;
```

- Tek plpgsql fonksiyonu = tek transaction; iki bacak ya birlikte başarılı
  olur ya birlikte geri alınır.
- `p_hedef_otel` hedef deponun oteli (cross-hotel transferde kaynaktan
  farklı olabilir — stok-takip.html 810↔811 transferi).

### İstemci çağrısı

RPC çağrısı standart Supabase REST deseniyle:
`POST /rest/v1/rpc/stok_ekle` body `{p_urun_kodu, p_depo_kodu, p_otel_id, p_delta}`.
Dönen değer (yeni miktar) client önbelleğine (`db.stok[depo][urun].miktar`)
yazılır.

Her dosyaya, mevcut `giris()`/`cikis()`+`saveStok()` iki-adımlı deseninin
yerine geçen bir yardımcı eklenir (kod tabanının mevcut deseni gereği
helper her dosyaya ayrı kopyalanır — paylaşılan modül yok):

```js
// depoId: kompozit depo kodu (örn '810_100'), delta: +giriş / -çıkış
async function stokDelta(depoId, urunKodu, otelId, delta){
  const r = await fetch(SB_URL+'/rest/v1/rpc/stok_ekle', {
    method:'POST', headers:SB_HEADERS,
    body: JSON.stringify({p_urun_kodu:urunKodu, p_depo_kodu:depoId, p_otel_id:otelId, p_delta:delta})
  });
  if(!r.ok) throw new Error('Stok güncellenemedi');
  const yeni = await r.json(); // yeni miktar (numeric)
  // client önbelleğini gerçek değere güncelle
  if(db.stok[depoId] && db.stok[depoId][urunKodu]) db.stok[depoId][urunKodu].miktar = yeni;
  return yeni;
}
```

(Not: `depo-siparis.html`/`gunluk-tuketim.html`'de önbellek adı `DB.stok`
ve yapısı farklı — helper her dosyada o dosyanın önbellek yapısına
uyarlanır.)

## Hata yönetimi

Bu tasarımın önemli bir yan faydası: RPC çağrısı `!r.ok` durumunda hata
fırlatır, böylece çağıran akış (mal kabul onayı, transfer vb.) başarısızlığı
yakalayıp kullanıcıya bildirebilir — mevcut "sessiz `console.warn`" deseninin
aksine. Her migrasyon edilen çağrı noktası, RPC hatasında kullanıcıya
görünür bir uyarı (`alert`/`toast`) gösterecek ve işlemi başarılı gibi
göstermeyecek şekilde güncellenir.

## Test/doğrulama planı

Statik: Her 7 yazma noktasının artık `rpc/stok_ekle` veya `rpc/stok_transfer`
çağırdığını, hiçbir yerde eski `POST /rest/v1/stok?on_conflict` mutlak-değer
yazımının kalmadığını grep ile doğrulamak; delta yönünün (giriş +, çıkış -)
her akışta doğru olduğunu kod okuyarak doğrulamak.

Gerçek uçtan uca test (kullanıcı tarafından): SQL fonksiyonları Supabase'de
oluşturulduktan sonra — bir ürünün mal kabulü, çıkışı, transferi ve günlük
tüketimi yapılıp stok miktarının her adımda doğru değiştiğini; bir transferde
kaynak ve hedefin birlikte güncellendiğini; aynı üründe arka arkaya iki
işlemin birbirini ezmediğini tarayıcıda doğrulamak.
