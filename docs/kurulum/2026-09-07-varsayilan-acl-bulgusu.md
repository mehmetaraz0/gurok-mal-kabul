# Varsayılan ACL bulgusu — KNOWN PLATFORM RISK

**Durum:** P3 · Blocker değil · Kapatılamaz (platform kısıtı)
**Tarih:** 2026-09-07
**Ölçüm:** salt-okuma · üretimde hiçbir değişiklik yapılmadı
**Yeniden ölçüm:** [`2026-09-07-varsayilan-acl-uyari-kontrolu.sql`](2026-09-07-varsayilan-acl-uyari-kontrolu.sql)

---

## 1. Sorun tek cümlede

`supabase_admin` rolünün `public` şemasındaki varsayılan ayrıcalıkları, o rolün
oluşturacağı **yeni** tablo, sekans ve fonksiyonlara `anon` için hak veriyor; ve
bu varsayılanı SQL Editor'den değiştiremiyoruz, çünkü SQL Editor `postgres`
olarak çalışıyor ve `postgres` bu rolün üyesi değil.

## 2. Neden düzeltilemiyor

`pg_default_acl` kayıtları **nesneyi oluşturan role** göre tutulur. Bir rolün
varsayılanını yalnız o rolün kendisi — ya da o role üye olan biri —
değiştirebilir:

```sql
alter default privileges for role supabase_admin in schema public
  revoke all on tables from anon;
```

Bu komut `postgres` oturumunda `insufficient_privilege` verir. Phase 0
sertleştirmesi bunu zaten denemişti; migration'ı düşürmesin diye `exception`
dalına alınmıştı ve orada **sessizce** başarısız oldu:

```
-- 2026-09-05-phase0-hardening.sql, satır 567-579
exception when insufficient_privilege or invalid_grant_operation or undefined_object then
  raise notice 'supabase_admin varsayilani degistirilemedi (uyelik yok). ...';
```

Migration "başarılı" göründü; kayıt değişmedi. Bu dosyanın var olma sebebi de
budur: **`notice` bir kanıt değildir.** Ölçülmeyen bir düzeltme, yapılmamış
düzeltmedir.

## 3. Ölçüm

### 3.1 Ham ölçüm — 2026-09-05, sertleştirme ÖNCESİ

Kaynak: `2026-09-05-phase0-preflight-02-izinler.sql`, blok 4
(*VARSAYILAN ACL (yeni nesneler)*). Üretimde salt-okuma çalıştırıldı.

Toplam **24** kayıt. `anon`'a hak üreten **13** kayıt (aşağıda ⚠ ile işaretli):

| Şema | Oluşturan rol | Tür | ACL | anon? |
|---|---|---|---|---|
| auth | supabase_auth_admin | r | postgres, dashboard_user | — |
| auth | supabase_auth_admin | S | postgres, dashboard_user | — |
| auth | supabase_auth_admin | f | postgres, dashboard_user | — |
| extensions | supabase_admin | r | postgres (grant option) | — |
| extensions | supabase_admin | S | postgres (grant option) | — |
| extensions | supabase_admin | f | postgres (grant option) | — |
| graphql | supabase_admin | r | postgres, **anon**, authenticated, service_role | ⚠ |
| graphql | supabase_admin | S | postgres, **anon**, authenticated, service_role | ⚠ |
| graphql | supabase_admin | f | postgres, **anon**, authenticated, service_role | ⚠ |
| graphql_public | supabase_admin | r | postgres, **anon**, authenticated, service_role | ⚠ |
| graphql_public | supabase_admin | S | postgres, **anon**, authenticated, service_role | ⚠ |
| graphql_public | supabase_admin | f | postgres, **anon**, authenticated, service_role | ⚠ |
| **public** | **postgres** | **r** | postgres, authenticated, service_role | — |
| **public** | **postgres** | **S** | postgres, authenticated, service_role | — |
| **public** | **postgres** | **f** | postgres, **anon**, authenticated, service_role | ⚠ |
| **public** | **supabase_admin** | **r** | postgres, **anon**, authenticated, service_role | ⚠ |
| **public** | **supabase_admin** | **S** | postgres, **anon**, authenticated, service_role | ⚠ |
| **public** | **supabase_admin** | **f** | postgres, **anon**, authenticated, service_role | ⚠ |
| realtime | supabase_admin | r | postgres, dashboard_user | — |
| realtime | supabase_admin | S | postgres, dashboard_user | — |
| realtime | supabase_admin | f | postgres, dashboard_user | — |
| storage | postgres | r | postgres, **anon**, authenticated, service_role | ⚠ |
| storage | postgres | S | postgres, **anon**, authenticated, service_role | ⚠ |
| storage | postgres | f | postgres, **anon**, authenticated, service_role | ⚠ |

> `r` = tablo, `S` = sekans, `f` = fonksiyon.

### 3.2 Sertleştirme sonrası — 2026-09-07 doğrulaması

`2026-09-07-post-pms-faz1-uretim-parmakizi.sql` üretimde çalıştırıldı
(28/28 eşit). İki bilgi sayacı:

| Sayaç | Değer |
|---|---|
| **F1** — `anon` üreten varsayılan ACL kaydı | **12** |
| **F2** — toplam varsayılan ACL kaydı | **24** |

Sertleştirme öncesi 13 → sonrası **12**. Aradaki fark **tam olarak bir kayıt**,
ve hangi kayıt olduğu aritmetik olarak zorunlu:

```
graphql            3  (r, S, f)   — değişmedi
graphql_public     3  (r, S, f)   — değişmedi
public/supabase_admin 3 (r, S, f) — DEĞİŞTİRİLEMEDİ
storage/postgres   3  (r, S, f)   — değişmedi
                  ---
                   12  = F1  ✓

public/postgres/f  1                — KALDIRILDI
```

Kaldıran satır, sertleştirmenin 561–562. satırları:

```sql
alter default privileges for role postgres in schema public
  revoke execute on functions from anon;
```

**Sonuç:** F1'in 13 değil 12 olması, o revoke'un gerçekten uygulandığının
bağımsız kanıtıdır. Toplamın 24'te kalması da hiçbir kaydın eklenip
silinmediğini gösterir.

## 4. Bizim migration nesnelerimize neden uygulanmıyor

Migration'larımız Supabase SQL Editor üzerinden **`postgres`** rolü olarak
çalışır. Yarattığımız nesnelere `public`/`postgres` satırları uygulanır ve o
satırlarda — sertleştirmeden sonra — **hiçbir nesne türünde `anon` yok**:

| Nesne türü | `public` / `postgres` varsayılanı | anon |
|---|---|---|
| Tablo (`r`) | postgres, authenticated, service_role | **yok** |
| Sekans (`S`) | postgres, authenticated, service_role | **yok** |
| Fonksiyon (`f`) | postgres, authenticated, service_role | **yok** (2026-09-05'te kaldırıldı) |

Bunun üzerine, standart gereği her migration nesneyi doğduğu anda zaten
sıfırlıyor:

```sql
revoke all on table public.<tablo> from public, anon, authenticated;
```

Yani PMS Faz 1 nesneleri için **iki bağımsız katman** aynı yöne bakıyor.
Ölçülmüş etki:

| Fiili kontrol (2026-09-07, üretim) | Sonuç |
|---|---|
| B3 — `public` şemasında `anon` tablo hakkı | **0** |
| B4 — `public` şemasında `anon` sekans USAGE | **0** |

`anon`'un `public` şemasında tek bir tablo ya da sekans hakkı yok.

> **Not — `authenticated` neden revoke listesinde:** `public`/`postgres`
> varsayılanı tablolara `authenticated` için **ALL** veriyor. Yalnız
> `public, anon` revoke etmek, append-only bir tablonun UPDATE/DELETE
> yasağını **sessizce** etkisiz bırakırdı. PMS Adım 4 bu yüzden üç rolü de
> revoke eder; Adım 1–2 etmez (bkz. bölüm 7).

## 5. Kalan risk

Risk **yalnız `supabase_admin`'in `public` şemasında oluşturacağı yeni
nesneler** için geçerli. Somut olarak:

1. **Kapsam.** Platform bileşenleri (uzantı kurulumları, Supabase'in kendi
   bakım işleri) `public` şemasında bir tablo, sekans ya da fonksiyon
   yaratırsa, o nesne `anon` hakkıyla **doğar**. Bizim migration'larımız bu
   yoldan geçmez.
2. **RLS bir yedek katman, ama tam değil.** `anon` bir tabloya SELECT hakkıyla
   doğsa bile RLS açıksa ve politika yoksa 0 satır okur. Ancak
   `supabase_admin`'in yarattığı tabloda RLS'i **biz açmayız** — açık gelmezse
   koruma yoktur. Bu yüzden `rls_auto_enable` (henüz bağlı değil) ve
   D1/D2 fiili ölçümü birlikte önem taşır.
3. **Fonksiyonlar — ölçüldü ve kapatıldı (2026-09-08).** İlk çalıştırmada
   **D3 = 18** çıktı: `public` şemasında `anon`'un EXECUTE hakkı olan 18
   fonksiyon, hepsi bizim PMS fonksiyonlarımız.

   Sınıflandırma repodan doğrulandı: **17'si `returns trigger`** (doğrudan
   çağrılamaz — PostgreSQL tetikleyici bağlamı dışında reddeder, PostgREST
   RPC olarak yayınlamaz), **1'i `pms_bugun(otel_id)`** (`language sql
   stable`, hiçbir tabloya dokunmuyor, saat dilimine göre tarih döndürüyor).
   **Fiili sızıntı yoktu.**

   Asıl bulgu şuydu: 22 PMS fonksiyonundan yalnız 4'ü açık `revoke` almıştı.
   Açık revoke alan her fonksiyon kapalı, almayan her fonksiyon açıktı —
   standardın kuralının üretimde bire bir çalıştığının kanıtı.

   `2026-09-08-pms-fonksiyon-acl-temizligi.sql` ile **D3: 18 → 0**.
   Uygulama sonrası ölçüm: beş çağrılabilir RPC'de `authenticated = true`,
   `anon = false`; `pms_toplam = 22`. Akış etkilenmedi.
4. **Gerçekleşme sinyali.** Risk teorikten fiiliye dönerse önce D1/D2 kırmızıya
   döner. Karar kriteri **D1/D2**'dir; B1/C1 yalnız kaynağı gösterir.

**Kabul gerekçesi:** risk gerçekleşebilmesi için Supabase'in `public`
şemasında bizim adımıza nesne yaratması gerekir; bugüne kadar olmadı ve
olduğunda D1/D2 anında yakalar. Bu nedenle **blocker değil, izlenen risk.**

## 6. Supabase desteğine gönderilecek teknik açıklama

> **Konu:** Default privileges for role `supabase_admin` in schema `public`
> grant `anon` on new objects — cannot be revoked from SQL Editor
>
> Project ref: `xwytofysmgqtqjzkplfi` (region `ap-northeast-1`)
>
> **Observed.** `pg_default_acl` contains three records for
> `defaclrole = supabase_admin` in schema `public` — object types `r`
> (table), `S` (sequence) and `f` (function) — and all three include
> `anon` in the ACL. Any object `supabase_admin` creates in `public` is
> therefore born with privileges for the anonymous role.
>
> **Impact.** Our own migrations run as `postgres` and are not affected: the
> `public`/`postgres` defaults grant no `anon` privileges, and every
> migration additionally issues an explicit
> `REVOKE ALL ... FROM PUBLIC, anon, authenticated`. The residual exposure is
> limited to objects created in `public` by `supabase_admin` itself
> (extension installs, platform maintenance), which we neither create nor
> control, and for which we cannot guarantee RLS is enabled.
>
> **What we tried.** From the SQL Editor:
>
> ```sql
> alter default privileges for role supabase_admin in schema public
>   revoke all on tables from anon;
> ```
>
> This fails with `insufficient_privilege`, because the SQL Editor session
> runs as `postgres` and `postgres` is not a member of `supabase_admin`.
> `ALTER DEFAULT PRIVILEGES FOR ROLE` requires membership in the target role.
>
> **Questions.**
> 1. Is there a supported way for a project owner to remove `anon` from
>    `supabase_admin`'s default privileges in schema `public`?
> 2. If not, is this default intentional for `public` (as opposed to
>    `graphql` / `graphql_public`, where an `anon` default is expected)?
> 3. Which platform operations create objects in `public` as
>    `supabase_admin`, so that we can scope the residual risk precisely?
>
> **Not requested:** we are not asking for elevated roles or superuser
> access. A platform-side change, or a definitive "this is by design and
> here is why it is safe", both resolve the item for us.

## 7. İlgili — kapsam dışı ama aynı ailede

PMS Adım 1 ve Adım 2 migration'ları tabloları yalnız `public, anon`'dan
revoke eder; `authenticated` listede yoktur. Adım 4 üçünü de içerir.

Bu **açık bir delik değildir** — o tabloların hepsi zaten `authenticated`'a
CRUD verir ve otel kapsamını RLS tutar. Ama derinlemesine savunma boşluğudur
ve yeni standart bunu zorunlu kılar. Statik denetleyici bu iki dosyada
altı bulguyu bağımsız olarak yeniden keşfetti (`R2-REVOKE-EKSIK-ROL`).

**Geçmiş migration'lar yeniden yazılmaz.** Bkz.
[`MIGRATION-GUVENLIK-STANDARDI.md`](MIGRATION-GUVENLIK-STANDARDI.md),
"Geçmiş migration'lar".
