# Staging (Supabase Branch) kurulumu ve Phase 0 doğrulaması

**Durum:** hazırlık. Üretime hiçbir yazma yapılmadı ve yapılmayacak.

Bu belge, Phase 0 sertleştirmesini üretime dokunmadan doğrulamak için
kurulacak staging ortamının önkoşullarını, kurulumunu ve kabul ölçütünü
tanımlar.

---

## 1. Neden basit bir "branch aç" yetmiyor

Supabase preview branch'leri şemayı **`supabase/migrations` dosyalarını
sırayla çalıştırarak** kurar; üretim veritabanının canlı bir kopyasını
almazlar. Supabase'in kendi dökümantasyonu bunu açıkça söylüyor: migration
geçmişi yoksa branching şemayı tam yakalayamaz.

Bu repoda:

| | |
|---|---|
| `supabase/` dizini | **yok** |
| `supabase/migrations/` | **yok** |
| `config.toml` | **yok** |

Dolayısıyla bugün açılacak bir branch'in üretimle aynı çıkacağı
**varsayılamaz**. Bu, teknik bir ayrıntı değil: staging üretimi temsil
etmiyorsa oradaki "Phase 0 geçti" sonucu hiçbir şey kanıtlamaz — daha
kötüsü, yanlış güven verir.

Kaynak: [Branching](https://supabase.com/docs/guides/deployment/branching) ·
[Why are my Supabase branches empty?](https://supabase.com/docs/guides/troubleshooting/new-branch-doesnt-copy-database)

---

## 2. Mevcut şema dökümü kullanılamaz — ölçüldü

`docs/kurulum/01-sema-dokumu.sql` (31 Tem 2026) tek kullanımlık bir
PostgreSQL 17 konteynerine yüklenip üretim parmak iziyle karşılaştırıldı
(`node scripts/dokum-dogrula.mjs docs/kurulum/01-sema-dokumu.sql`):

| Ölçüm | Üretim | Döküm |
|---|---|---|
| Birebir eşleşen fonksiyon | 26 | **2** |
| Eksik fonksiyon | — | **21** |
| Gövdesi farklı fonksiyon | — | 3 |
| `GRANT` / `REVOKE` satırı | var | **0** |
| `ALTER DEFAULT PRIVILEGES` | var | **0** |
| `CREATE TRIGGER` | var | **0** |
| RLS kapalı tablo | 0 | **5** |
| Politika | ~170 | 118 |
| `public` tablo | 43 | 55 |

Eksik olan 21 fonksiyon arasında `auth_otel_erisim`, `auth_erp_kullanicisi`,
`auth_otel_id`, `auth_tum_oteller`, `fatura_kaydet`, `mal_kabul_kaydet` ve
tüm ayrıcalıklı RPC'ler var — yani **Phase 0'ın konusu olan her şey**.

RLS kapalı 5 tablo: `fatura_kalemleri`, `moduller`, `roller`,
`yetki_matrisi`, `yevmiye_kalemleri`. Bu dökümden kurulan bir staging'de
yetki matrisi herkese açık olurdu.

Sıfır `GRANT` satırının sebebi dökümün `--no-privileges` ile alınmış
olması. Phase 0'ın yarısı izinlerle ilgili olduğu için bu tek başına
dökümü kullanılamaz kılıyor.

**Sonuç: döküm onarılamaz, yeniden alınmalıdır.** İçeriği yalnızca
üretimden gelebilir.

---

## 3. Adım adım

### 3.1 Hangi yolda olduğumuzu belirle (üretimde, SALT-OKUMA)

Supabase, üretimde migration geçmişi **yoksa** branch kurarken bir şema
dökümü alıp onu migration olarak çalıştırıyor. Geçmiş **varsa** yalnızca o
dosyaları çalıştırıyor. Hangi durumda olduğumuz sonucu değiştirir:

```sql
-- to_regclass DISINDA tabloya referans YOK: PostgreSQL, WHERE korumasi ne
-- olursa olsun ifadenin TAMAMINI planlar ve var olmayan tabloda 42P01 verir.
do $$
declare v_sayi bigint;
begin
  if to_regclass('supabase_migrations.schema_migrations') is null then
    raise notice 'supabase_migrations.schema_migrations TABLOSU YOK';
  else
    execute 'select count(*) from supabase_migrations.schema_migrations' into v_sayi;
    raise notice 'migration kaydi: %', v_sayi;
  end if;
end $$;
```

**2026-09-06 sonucu: tablo YOK.** Üretimde migration geçmişi yok; şema SQL
Editor üzerinden kurulmuş. Aşağıdaki ilk dal geçerli.

- **Tablo yok / 0 kayıt** → şema SQL Editor'den kurulmuş. Branch açarken
  Supabase döküm alma yoluna girer, ama buna güvenmek yerine 3.2'deki
  baseline'ı kendimiz üretiriz.
- **Kayıt var** → repodaki `supabase/migrations` ile üretim arasında bir
  uyuşmazlık riski var; önce ikisini hizalamak gerekir.

### 3.2 Dökümü yeniden al (izinlerle birlikte)

Bunu **sen** çalıştırırsın; bağlantı dizesi parola içerir ve bana
gönderilmemelidir. Sohbete yapıştırma.

Bağlantı dizesi: Supabase Dashboard → Project Settings → Database →
Connection string → **URI** (Session pooler).

```bash
docker run --rm -i postgres:17 pg_dump "BAGLANTI_DIZESI" --schema-only --schema=public --no-owner > docs/kurulum/01-sema-dokumu.sql
```

Kritik nokta: **`--no-privileges` KULLANMA.** Önceki dökümün asıl kusuru
oydu. `--no-owner` sahiplik satırlarını atar ama `GRANT`'leri korur —
istediğimiz tam olarak bu.

### 3.3 Dökümü doğrula (yerelde, ücretsiz)

```bash
node scripts/dokum-dogrula.mjs docs/kurulum/01-sema-dokumu.sql
```

Bu betik dökümü tek kullanımlık bir konteynere yükler ve üretim parmak
iziyle karşılaştırır. **Tek bir `SAPMA` satırı bile çıkmamalı.** Çıkarsa
döküm hâlâ eksiktir ve branch açmanın anlamı yoktur.

Bu adım branch açmadan ve para harcamadan yapılır. Kabul ölçütü budur.

### 3.4 Branch'i aç

`supabase init` ile proje iskeletini kur, doğrulanmış dökümü
`supabase/migrations/` altına ilk migration olarak koy, GitHub entegrasyonunu
bağla ve preview branch'i aç.

### 3.5 Branch'te eşitliği tekrar doğrula

Branch'in SQL Editor'ünde çalıştır:

```
docs/kurulum/2026-09-06-staging-esitlik-dogrulama.sql
```

Yine **sıfır `SAPMA`** bekliyoruz. Bu, branch'in gerçekten üretimi temsil
ettiğinin kanıtıdır ve Phase 0'ı orada test etmenin ön şartıdır.

### 3.6 Phase 0'ı branch'te uygula ve test et

1. `docs/kurulum/2026-09-05-phase0-hardening.sql`
2. `docs/kurulum/2026-09-05-phase0-preflight-0{1..5}.sql` — sertleştirme
   sonrası durumu görmek için
3. ERP regresyonu: giriş, navigasyon, otel seçimi, kullanıcı yönetimi, mal
   kabul, satın alma, stok, depo, bar/sipariş, QR akışı
4. Özellikle **giriş kayıtları ekranı** — 46 satırın 46'sında `otel_id`
   NULL; merkez kullanıcısında dolu görünmeli, otel kullanıcısında boş

---

## 4. Bilinen sınırlar

- **Parmak izi bayatlar.** `2026-09-06-staging-esitlik-dogrulama.sql`
  içindeki md5'ler 6 Eylül 2026 üretim durumudur. Üretimde bir fonksiyon
  değişirse dosya yanlış alarm verir; preflight 01 yeniden alınıp
  güncellenmelidir.
- **Eşitlik dosyası Phase 0'DAN ÖNCE çalıştırılır.** Migration `auth_*`
  fonksiyonlarını yeniden yazar ve parmak izlerini bilerek değiştirir.
- **`scripts/supabase-shim.sql` üretime asla uygulanmaz.** Yalnızca düz
  PostgreSQL konteynerinde döküm yüklemek için iskele kurar.
- Döküm `--schema=public` ile alınır. `auth`, `storage`, `realtime`
  şemaları Supabase tarafından sağlanır; shim yalnızca doğrulama için
  minimal karşılıklarını kurar.
