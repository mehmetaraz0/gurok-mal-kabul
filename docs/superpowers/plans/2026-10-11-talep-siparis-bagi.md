# Talep → Sipariş Bağı Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Bir talebin hangi siparişlere hangi kalemden ne kadar dönüştüğünü kalıcı olarak tutmak, açık talebi "kalan miktar" olarak doğru hesaplamak, talep kaynaklı siparişi tek transaction'da yazmak ve sipariş numarasını dört yolun tamamı için tek seri sunucu kaynağından üretmek.

**Architecture:** Altı bağımsız migration (sayaç+üreteç → bağ tablosu → `siparisler` kolonları → INV kapıları → RPC → görünüm), her biri kendi izole testiyle. Değişmez (INV) tek cümlede tanımlı ve yedi kapıyla (K1–K7) korunuyor; kapıların hepsi aynı talep kalemi satır kilidi altında aynı yardımcı fonksiyonu çağırıyor. Görünüm katalog tablolarına hiç katılmıyor — birim bağ yazılırken donduruluyor.

**Tech Stack:** PostgreSQL 15 (Supabase), PL/pgSQL `security definer` RPC, PostgREST, saf tarayıcı JS (framework yok), Node test koşucusu + izole Docker Postgres (`scripts/bar-test-ortam.mjs`).

**Spec:** `docs/superpowers/specs/2026-10-11-talep-siparis-bagi-design.md` (commit `8f9675b`)

## Global Constraints

- **Üretime yazma YOK.** `CANLIYA UYGULA` denmedikçe hiçbir migration üretimde koşulmaz. Tüm doğrulama izole Docker'da.
- **Uygulanmış migration yeniden yazılmaz** (`docs/kurulum/MIGRATION-GUVENLIK-STANDARDI.md` bölüm 5). Düzeltme her zaman yeni dosyayla.
- **Migration güvenlik denetleyicisi 0 HATA / 0 UYARI** zorunlu: `node scripts/migration-guvenlik-kontrol.mjs docs/kurulum/<dosya>.sql`. Her yeni tablo için RLS + `revoke`/`grant` kararı; her yeni fonksiyon için `service_role` kararı (R11); her görünüm için ACL kararı (R10); `security definer` fonksiyonlarda `set search_path` (R9).
- **`node scripts/check.mjs` çıkış 0** olmadan hiçbir task tamamlanmış sayılmaz.
- Her migration **idempotent**: ikinci koşumda hata vermez, son durumu değiştirmez.
- Her migration dosyası `begin;` … `commit;` içerir ve `sql-uygula.ps1` kanalıyla (`--single-transaction`) koşulabilir olmalıdır — testlerde `O.uygulaTekIslem(...)` ile bu kanal taklit edilir.
- **INV (değişmez):** her talep kalemi için, **iptal olmayan** siparişlere ait bağların toplamı kalemin miktarını aşamaz; tüm miktarlar kalemin kendi biriminde.
- **Birim dondurma:** kalan hesabı **hiçbir zaman** güncel katalog dönüşümünü kullanmaz. `hedef_birim` bağ yazılırken dondurulur.
- Tarih damgası: dosya adlarında `2026-10-11`.
- Testler `scripts/*.test.mjs`, harness `barOrtami({ad, ag})`; `ad`/`ag` her test dosyasında **benzersiz** olmalı (paralel koşumda konteyner çakışmasın).

## Review Focus

Spec'in ima ettiği ama hiçbir task'ın testi doğal olarak kapsamadığı, kullanıcıyı en çok ısıracak beş girdi sınıfı. Her biri sahibi olan task'a test olarak eklendi:

1. **Bozuk `p_satirlar` JSON** — eksik anahtar, `null` `talep_kalem_id`, metin olarak gelen `miktar`. RPC temiz ret vermeli, cast hatasıyla çökmemeli. → Task 5, test `R-J1..R-J3`.
2. **Çapraz otel kaçakçılığı** — `p_otel_id` çağıranın kapsamında ama `p_talep_id` başka otelin. Reddedilmeli. → Task 5, test `R-O1`.
3. **Boş `siparisler` tablosu** — bir önek için hiç sipariş yokken numara üretimi. `max(...)` null olur; taban 91110'dan ilk numara üretilmeli, `null` dönmemeli. → Task 1, test `N-B1`.
4. **`termin < tarih` ve `null` tarih** — spec sessiz. Sipariş yazılmalı ama `termin < tarih` reddedilmeli (sessiz kabul, teslim akışında anlamsız kayıt üretir). → Task 5, test `R-T1..R-T2`.
5. **`islem_anahtari` sınır değerleri** — 7 karakter (CHECK altı), 101 karakter (CHECK üstü), boş metin. RPC anlaşılır ret vermeli, CHECK ihlalini ham bırakmamalı. → Task 3, test `A-S1..A-S3`.

---

## Dosya Yapısı

**Migration'lar** (hepsi `docs/kurulum/`):

| Dosya | Sorumluluk |
|---|---|
| `2026-10-11-siparis-no-sayac.sql` | `siparis_no_sayac` tablosu + tohumlama + `siparis_no_uret(text)` |
| `2026-10-11-talep-siparis-baglari.sql` | `talep_siparis_baglari` tablosu + RLS + ACL + indeksler |
| `2026-10-11-siparisler-islem-anahtari.sql` | `siparisler.islem_anahtari` + `islem_parmak_izi` + kısmi unique |
| `2026-10-11-talep-siparis-inv-kapilari.sql` | `talep_bag_inv_kontrol()` + K1–K7 tetikleyicileri |
| `2026-10-11-siparis-olustur-talepten.sql` | `siparis_olustur_talepten(...)` RPC |
| `2026-10-11-stok-acik-talep-kalan.sql` | `stok_acik_talep` görünümünün yeniden yazımı |

**Testler** (hepsi `scripts/`):

| Dosya | Kapsam |
|---|---|
| `talep-siparis-fikstur.mjs` | Paylaşılan fikstür kurucu (tablo değil, modül) |
| `siparis-no-uret.test.mjs` | Numara üretimi, eşzamanlılık, boş tablo, tohumlama |
| `talep-siparis-bagi-kapilari.test.mjs` | Tablo + RLS + K1–K7 + mutantlar |
| `siparis-olustur-talepten.test.mjs` | RPC: transaction, idempotency, birim, INV, girdi doğrulama |
| `stok-acik-talep-kalan.test.mjs` | Görünüm + birim dondurma (B1–B6) |

**İstemci:** `satin-alma-iade.html` · `stok-takip.html` · `satin-alma-talepler.html` · `satin-alma-siparisolustur.html`

**Belge:** `docs/kurulum/2026-10-11-talep-siparis-yayin-paketi.md` (sıra, geri alma, geçiş ölçümü)

---

### Task 1: Ortak sipariş numarası üretimi

**Files:**
- Create: `docs/kurulum/2026-10-11-siparis-no-sayac.sql`
- Create: `scripts/siparis-no-uret.test.mjs`

**Interfaces:**
- Consumes: `public.auth_yetki_var(text,text)` (mevcut)
- Produces: `public.siparis_no_uret(p_prefix text) returns text` — `C`/`R` dışında `onek_gecersiz` (22023), yetkisizde `yetkisiz` (42501); `public.siparis_no_sayac(prefix text pk, son_no bigint, guncelleme timestamptz)`

- [ ] **Step 1: Testi yaz (kırmızı olacak)**

`scripts/siparis-no-uret.test.mjs`:

```javascript
// Ortak siparis numarasi uretimi — izole kanit (uretime baglanmaz).
// Migration: docs/kurulum/2026-10-11-siparis-no-sayac.sql
import { readFileSync } from 'node:fs';
import { barOrtami } from './bar-test-ortam.mjs';

const KOK = new URL('..', import.meta.url).pathname.replace(/^\/([A-Za-z]:)/, '$1');
const M1 = 'docs/kurulum/2026-10-11-siparis-no-sayac.sql';
const O = barOrtami({ ad: 'sip-no', ag: 'sip-no-net' });
const KIM = { rol: 'authenticated', sub: null };   // yetki fikstürü Step 3'te

let ok = 0, fail = 0;
const sonuc = (g, ad, ek) => { console.log((g ? 'OK   ' : 'FAIL ') + ad + (ek ? ' — ' + ek : '')); if (g) ok++; else fail++; };
const es = (ad, bek, olc) => sonuc(String(bek) === String(olc), ad, String(bek) === String(olc) ? String(olc) : `beklenen=${bek} olculen=${olc}`);
const tek = (q) => O.sql(q).out.trim();

try {
  await O.kur();
  const m = O.uygulaTekIslem(M1);
  sonuc(m.ok, 'F1 migration uygulandi', m.ok ? '' : m.err.split('\n').filter(l => /ERROR/.test(l))[0]);

  // N-B1 (Review Focus 3): bos tabloda ilk numara tabandan uretilir
  O.sql("delete from public.siparisler where siparis_no ~ '^C[0-9]{8}$';");
  O.sql("update public.siparis_no_sayac set son_no = 91110 where prefix = 'C';");
  es('N-B1 bos tabloda ilk numara', 'C00091111',
    tek("select public.siparis_no_uret('C');"));

  // N1: ardisik iki cagri farkli ve artan
  const a = tek("select public.siparis_no_uret('C');");
  const b = tek("select public.siparis_no_uret('C');");
  sonuc(a !== b && b > a, 'N1 ardisik numaralar farkli ve artan', a + ' -> ' + b);

  // N2: bicim korunuyor
  sonuc(/^C[0-9]{8}$/.test(b), 'N2 bicim C + 8 hane', b);

  // N3: gecersiz onek reddedilir
  const r3 = O.sql("select public.siparis_no_uret('X');");
  sonuc(!r3.ok && /onek_gecersiz/.test(r3.err), 'N3 gecersiz onek reddedildi');

  console.log(`\nSONUC: ${ok} gecti, ${fail} kaldi`);
} catch (e) { console.error('DUR: ' + (e && e.message)); fail++; }
finally { try { O.temizle(); } catch { /* yoksay */ } }
process.exit(fail === 0 ? 0 : 1);
```

- [ ] **Step 2: Testi koş, kırmızı olduğunu gör**

Run: `node scripts/siparis-no-uret.test.mjs`
Expected: `F1 migration uygulandi` FAIL — dosya yok (`ENOENT`) ya da `DUR:` satırı.

- [ ] **Step 3: Migration'ı yaz**

`docs/kurulum/2026-10-11-siparis-no-sayac.sql`:

```sql
-- ============================================================================
-- ORTAK SIPARIS NUMARASI URETECI
-- Standart : docs/kurulum/MIGRATION-GUVENLIK-STANDARDI.md
-- Tasarim  : docs/superpowers/specs/2026-10-11-talep-siparis-bagi-design.md §4
--
-- NEDEN: siparis numarasi bugun UC ayri istemci kopyasinda `max+1` ile
-- uretiliyor (satin-alma-siparisolustur / satin-alma-iade / stok-takip).
-- Iki kullanici ayni anda ayni maksimumu okuyabiliyor; `siparis_no` PK oldugu
-- icin sonuc sessiz mukerrer degil, gorunur hata — ama sipariş yazilmiyor.
-- Bu dosya tek SERI kaynak kurar; dort yol da bunu kullanacak.
--
-- BU DOSYA YAZILDI, URETIME UYGULANMADI.
-- ============================================================================

-- 0) ONKOSULLAR
do $$
begin
  if to_regclass('public.siparisler') is null then
    raise exception 'ONKOSUL: siparisler tablosu yok.';
  end if;
  if to_regprocedure('public.auth_yetki_var(text, text)') is null then
    raise exception 'ONKOSUL: auth_yetki_var yok (Phase 0 gerekli).';
  end if;
end;
$$;

begin;

-- 1) SAYAC TABLOSU
create table if not exists public.siparis_no_sayac (
  prefix     text        primary key,
  son_no     bigint      not null,
  guncelleme timestamptz not null default now(),
  constraint siparis_no_sayac_onek   check (prefix in ('C','R')),
  constraint siparis_no_sayac_pozitif check (son_no >= 0)
);

-- 2) RLS: politika YOK — tabloya kimse dogrudan erisemez, yalniz
--    `siparis_no_uret` (security definer) yazar. Bos RLS = fail-closed.
alter table public.siparis_no_sayac enable row level security;
revoke all on table public.siparis_no_sayac from public, anon, authenticated, service_role;

-- 3) TOHUMLAMA: mevcut maksimumdan basla (yoksa taban 91110)
insert into public.siparis_no_sayac (prefix, son_no) values
  ('C', coalesce((select max(substring(siparis_no from 2)::bigint)
                    from public.siparisler where siparis_no ~ '^C[0-9]{8}$'), 91110)),
  ('R', coalesce((select max(substring(siparis_no from 2)::bigint)
                    from public.siparisler where siparis_no ~ '^R[0-9]{8}$'), 91110))
on conflict (prefix) do nothing;

-- 4) URETEC
create or replace function public.siparis_no_uret(p_prefix text)
returns text
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $fn$
declare
  v_son  bigint;
  v_max  bigint;
  v_yeni bigint;
begin
  if p_prefix is null or p_prefix not in ('C','R') then
    raise exception 'onek_gecersiz: % (C veya R olmali)', coalesce(p_prefix,'<null>')
      using errcode = '22023';
  end if;

  -- SECURITY DEFINER RLS'i atlar; atlanan yetki kontrolu BURADA yeniden uygulanir.
  if public.auth_yetki_var('siparis_olustur','kayit') is not true then
    raise exception 'yetkisiz: siparis_olustur kayit yetkisi gerekir'
      using errcode = '42501';
  end if;

  -- Satir kilidi: eszamanlı cagrilar SIRAYA girer, ayni numarayi almazlar.
  select son_no into v_son from public.siparis_no_sayac
   where prefix = p_prefix for update;
  if not found then
    raise exception 'sayac_yok: % oneki icin sayac satiri yok', p_prefix
      using errcode = '23503';
  end if;

  -- Sayac geride kalirsa (elle yazilmis kayit, eski veri) kendini toparlar.
  select coalesce(max(substring(siparis_no from 2)::bigint), 0) into v_max
    from public.siparisler
   where siparis_no ~ ('^' || p_prefix || '[0-9]{8}$');

  v_yeni := greatest(v_son, v_max) + 1;

  update public.siparis_no_sayac
     set son_no = v_yeni, guncelleme = now()
   where prefix = p_prefix;

  return p_prefix || lpad(v_yeni::text, 8, '0');
end;
$fn$;

-- 5) FONKSIYON ACL (standart R9 + R11)
revoke all on function public.siparis_no_uret(text) from public, anon;
revoke all on function public.siparis_no_uret(text) from service_role;
grant execute on function public.siparis_no_uret(text) to authenticated;

commit;

notify pgrst, 'reload schema';

-- ============================================================================
-- GERI ALMA
--   begin;
--   drop function if exists public.siparis_no_uret(text);
--   drop table if exists public.siparis_no_sayac;
--   commit;
-- Istemciler bu fonksiyona gectikten SONRA geri alinirsa siparis olusturma
-- kirilir; geri alma ancak istemci degisikligi de geri alinirsa anlamlidir.
-- ============================================================================
```

- [ ] **Step 4: Yetki fikstürünü teste ekle**

`scripts/siparis-no-uret.test.mjs` içinde `await O.kur();` satırından **sonra**, migration uygulamasından **önce** ekle:

```javascript
  // Yetki fiksturu: `siparis_olustur` modulu + kayit yetkili rol + kullanici.
  const U = '11111111-0000-0000-0000-0000000000a1';
  O.sql(`set session_replication_role = replica;
    insert into public.moduller (kod, ad, kategori, sira, aktif)
      values ('siparis_olustur','Siparis Olustur','satinalma',10,true)
      on conflict (kod) do nothing;
    insert into public.roller (id, ad, seviye, kod, sira)
      values ('00000000-0000-0000-0000-00000000f001','Satinalma','otel','satinalma_test',30)
      on conflict do nothing;
    insert into public.yetki_matrisi (rol_id, modul_id, yetki)
    select r.id, m.id, 'kayit'::public.yetki_seviye
      from public.roller r, public.moduller m
     where r.kod='satinalma_test' and m.kod='siparis_olustur'
      on conflict (rol_id, modul_id) do nothing;
    insert into auth.users (id, email) values ('${U}','sip-no@test.local')
      on conflict (id) do nothing;
    insert into public.kullanicilar (id, auth_user_id, ad, rol, otel_id, aktif, rol_id)
    select gen_random_uuid(), '${U}'::uuid, 'Sip No Test', 'muhasebe_calisani', '810', true, r.id
      from public.roller r where r.kod='satinalma_test';
    set session_replication_role = origin;`);
  KIM.sub = U;
```

Ve `tek(...)` yerine yetki gerektiren çağrılarda `O.kimlikle(KIM, ...)` kullan:

```javascript
const tekKimlik = (q) => O.kimlikle(KIM, q).out.trim();
```

`N-B1`, `N1`, `N2` çağrılarını `tekKimlik` ile yap; `N3`'te `O.kimlikle(KIM, "select public.siparis_no_uret('X');")` kullan.

- [ ] **Step 5: Testi koş, yeşil olduğunu gör**

Run: `node scripts/siparis-no-uret.test.mjs`
Expected: `SONUC: 5 gecti, 0 kaldi`

- [ ] **Step 6: Eşzamanlılık testini ekle**

Aynı dosyada, `N3`'ten sonra:

```javascript
  // N4: ESZAMANLI 6 cagri -> 6 FARKLI numara (satir kilidi kaniti)
  const kosum = await Promise.all(
    Array.from({ length: 6 }, () => O.paralel(KIM, "select public.siparis_no_uret('R');")));
  const numaralar = kosum.map(r => r.out.trim()).filter(Boolean);
  es('N4a alti cagri da basarili', 6, kosum.filter(r => r.ok).length);
  es('N4b alti numara da FARKLI', 6, new Set(numaralar).size);
  sonuc(numaralar.every(n => /^R[0-9]{8}$/.test(n)), 'N4c hepsi bicime uygun');

  // N5: sayac geride birakilirsa `greatest` toparliyor
  O.sql("update public.siparis_no_sayac set son_no = 1 where prefix = 'R';");
  O.sql(`set session_replication_role = replica;
    insert into public.siparisler (siparis_no, firma_ad, otel_id, tarih)
      values ('R00099999','Toparlama Test','810', current_date)
      on conflict (siparis_no) do nothing;
    set session_replication_role = origin;`);
  es('N5 sayac geride ise maksimumdan devam', 'R00100000',
    tekKimlik("select public.siparis_no_uret('R');"));
```

- [ ] **Step 7: Mutant testi ekle (kilit gerçekten gerekli mi)**

Aynı dosyada, `N5`'ten sonra:

```javascript
  // N6 MUTANT: `for update` kaldirilirsa eszamanlı cagrilar AYNI numarayi alir.
  const mutant = readFileSync(KOK + M1, 'utf8')
    .replace('where prefix = p_prefix for update;', 'where prefix = p_prefix;');
  if (mutant === readFileSync(KOK + M1, 'utf8')) throw new Error('N6 capasi tutmadi');
  O.uygulaTekIslem(mutant, { metin: true });
  const mKosum = await Promise.all(
    Array.from({ length: 6 }, () => O.paralel(KIM, "select public.siparis_no_uret('C');")));
  const mNumara = mKosum.map(r => r.out.trim()).filter(Boolean);
  sonuc(new Set(mNumara).size < mNumara.length,
    'N6 MUTANT: kilit kalkinca mukerrer numara uretiliyor',
    mNumara.length + ' cagri -> ' + new Set(mNumara).size + ' farkli');
  O.uygulaTekIslem(M1);   // orijinali geri kur
```

- [ ] **Step 8: Testi koş**

Run: `node scripts/siparis-no-uret.test.mjs`
Expected: `SONUC: 10 gecti, 0 kaldi`

- [ ] **Step 9: Denetleyici ve statik kapı**

Run: `node scripts/migration-guvenlik-kontrol.mjs docs/kurulum/2026-10-11-siparis-no-sayac.sql`
Expected: `0 HATA | 0 UYARI` + `STANDARDA UYGUN`

Run: `node scripts/check.mjs`
Expected: `Tüm statik kontroller geçti.` (çıkış 0)

- [ ] **Step 10: Commit**

```bash
git add docs/kurulum/2026-10-11-siparis-no-sayac.sql scripts/siparis-no-uret.test.mjs
git commit -m "feat(siparis): ortak sunucu numara ureteci + izole kanit 10/0"
```

---

### Task 2: Bağ tablosu, RLS ve paylaşılan fikstür

**Files:**
- Create: `docs/kurulum/2026-10-11-talep-siparis-baglari.sql`
- Create: `scripts/talep-siparis-fikstur.mjs`
- Create: `scripts/talep-siparis-bagi-kapilari.test.mjs`

**Interfaces:**
- Consumes: Task 1'in `siparis_no_uret` (fikstürde sipariş numarası üretmek için)
- Produces: `public.talep_siparis_baglari` tablosu; `kurFikstur(O, { otel, talepDurum })` → `{ talepId, kalemId, kalemId2, urunKodu, siparisNo, siparisNo2, kimlik }`

- [ ] **Step 1: Fikstür modülünü yaz**

`scripts/talep-siparis-fikstur.mjs`:

```javascript
// Talep -> siparis testleri icin PAYLASILAN fikstur.
// Tetikleyiciler kapaliyken kurulur: phase0_islem_audit kimliksiz yazmayi
// reddeder, fikstur ise kimlik kurmadan once calisir.
export const U_TEST = '11111111-0000-0000-0000-00000000b001';

export function kurFikstur(O, { otel = '810', talepDurum = 'onaylandi' } = {}) {
  const TALEP = 'bbbbbbbb-0000-0000-0000-00000000b001';
  const KALEM = 'bbbbbbbb-0000-0000-0000-00000000b011';
  const KALEM2 = 'bbbbbbbb-0000-0000-0000-00000000b012';
  const URUN = 'TEST-BAG-001';

  const r = O.sql(`set session_replication_role = replica;
    insert into public.moduller (kod, ad, kategori, sira, aktif) values
      ('siparis_olustur','Siparis Olustur','satinalma',10,true),
      ('siparis_takip','Siparis Takip','satinalma',11,true)
      on conflict (kod) do nothing;
    insert into public.roller (id, ad, seviye, kod, sira)
      values ('00000000-0000-0000-0000-00000000f001','Satinalma','otel','satinalma_test',30)
      on conflict do nothing;
    insert into public.yetki_matrisi (rol_id, modul_id, yetki)
    select r.id, m.id, 'kayit'::public.yetki_seviye
      from public.roller r join public.moduller m on m.kod in ('siparis_olustur','siparis_takip')
     where r.kod='satinalma_test'
      on conflict (rol_id, modul_id) do nothing;
    insert into auth.users (id, email) values ('${U_TEST}','bag@test.local')
      on conflict (id) do nothing;
    insert into public.kullanicilar (id, auth_user_id, ad, rol, otel_id, aktif, rol_id)
    select gen_random_uuid(), '${U_TEST}'::uuid, 'Bag Test', 'muhasebe_calisani', '${otel}', true, r.id
      from public.roller r where r.kod='satinalma_test'
      on conflict do nothing;

    insert into public.urunler (kod, ad, birim) values ('${URUN}','Bag Test Urunu','KG')
      on conflict (kod) do nothing;
    insert into public.urun_birim_donusum (urun_kodu, buyuk_birim, carpan, silindi)
      values ('${URUN}','KOL',12,false) on conflict do nothing;

    insert into public.satin_alma_talepleri (id, departman, otel_id, durum, siparis_no)
      values ('${TALEP}'::uuid,'TEST','${otel}','${talepDurum}',null)
      on conflict (id) do nothing;
    insert into public.satin_alma_talep_kalemleri (id, talep_id, urun_adi, urun_kodu, miktar, birim) values
      ('${KALEM}'::uuid,  '${TALEP}'::uuid, 'Bag Test Urunu', '${URUN}', 10, 'KOL'),
      ('${KALEM2}'::uuid, '${TALEP}'::uuid, 'Bag Test Urunu', '${URUN}', 100, 'KG')
      on conflict (id) do nothing;

    insert into public.siparisler (siparis_no, firma_ad, otel_id, tarih, durum) values
      ('C00000001','Test Firma','${otel}', current_date, 'bekleyen'),
      ('C00000002','Test Firma 2','${otel}', current_date, 'bekleyen')
      on conflict (siparis_no) do nothing;
    set session_replication_role = origin;`);
  if (!r.ok) throw new Error('fikstur kurulamadi:\n' + r.err.split('\n').slice(-6).join('\n'));

  return {
    talepId: TALEP, kalemId: KALEM, kalemId2: KALEM2, urunKodu: URUN,
    siparisNo: 'C00000001', siparisNo2: 'C00000002',
    kimlik: { rol: 'authenticated', sub: U_TEST },
  };
}

// Bag satirini DOGRUDAN yazar (tetikleyicileri test etmek icin; RPC'yi atlar).
export function bagYaz(O, f, { kalemId, siparisNo, miktar, hedefBirim = 'KOL',
                               kaynakMiktar = null, kaynakBirim = null, carpan = null } = {}) {
  return O.sql(`insert into public.talep_siparis_baglari
      (otel_id, talep_id, talep_kalem_id, siparis_no, urun_kodu,
       miktar, hedef_birim, kaynak_miktar, kaynak_birim, carpan, olusturan_ad)
    values ('810','${f.talepId}'::uuid,'${kalemId}'::uuid,'${siparisNo}','${f.urunKodu}',
            ${miktar}, '${hedefBirim}', ${kaynakMiktar ?? miktar},
            '${kaynakBirim ?? hedefBirim}', ${carpan === null ? 'null' : carpan}, 'test');`);
}
```

- [ ] **Step 2: Tablo testini yaz (kırmızı olacak)**

`scripts/talep-siparis-bagi-kapilari.test.mjs`:

```javascript
// talep_siparis_baglari: tablo + RLS + INV kapilari (K1-K7) — izole kanit.
import { readFileSync } from 'node:fs';
import { barOrtami } from './bar-test-ortam.mjs';
import { kurFikstur, bagYaz } from './talep-siparis-fikstur.mjs';

const KOK = new URL('..', import.meta.url).pathname.replace(/^\/([A-Za-z]:)/, '$1');
const M1 = 'docs/kurulum/2026-10-11-siparis-no-sayac.sql';
const M2 = 'docs/kurulum/2026-10-11-talep-siparis-baglari.sql';
const M4 = 'docs/kurulum/2026-10-11-talep-siparis-inv-kapilari.sql';
const O = barOrtami({ ad: 'bag-kapi', ag: 'bag-kapi-net' });

let ok = 0, fail = 0;
const sonuc = (g, ad, ek) => { console.log((g ? 'OK   ' : 'FAIL ') + ad + (ek ? ' — ' + ek : '')); if (g) ok++; else fail++; };
const es = (ad, bek, olc) => sonuc(Number(bek) === Number(olc), ad, Number(bek) === Number(olc) ? String(olc) : `beklenen=${bek} olculen=${olc}`);
const tek = (q) => O.sql(q).out.trim();
const hata = (r) => (String(r.err).split('\n').filter(l => /ERROR|HATA/.test(l))[0] || '(mesaj yok)').slice(0, 110);
let f;

try {
  await O.kur();
  for (const m of [M1, M2]) {
    const r = O.uygulaTekIslem(m);
    sonuc(r.ok, 'F ' + m.split('/').pop(), r.ok ? '' : hata(r));
  }
  f = kurFikstur(O);
  sonuc(true, 'F2 fikstur kuruldu');

  // Y1: tablo var ve RLS acik
  es('Y1 RLS acik', 1, tek(`select count(*) from pg_class
    where relname='talep_siparis_baglari' and relrowsecurity;`));

  // Y2: authenticated DOGRUDAN yazamaz (politika yok + ayricalik yok)
  const y2 = O.kimlikle(f.kimlik, `insert into public.talep_siparis_baglari
    (otel_id, talep_id, talep_kalem_id, siparis_no, miktar, hedef_birim,
     kaynak_miktar, kaynak_birim)
    values ('810','${f.talepId}'::uuid,'${f.kalemId}'::uuid,'${f.siparisNo}',
            1,'KOL',1,'KOL');`);
  sonuc(!y2.ok, 'Y2 authenticated dogrudan YAZAMIYOR', hata(y2));

  // Y3: authenticated kendi otelinin bagini OKUYABILIR
  bagYaz(O, f, { kalemId: f.kalemId, siparisNo: f.siparisNo, miktar: 1 });
  es('Y3 authenticated okuyabiliyor', 1,
    O.kimlikle(f.kimlik, 'select count(*) from public.talep_siparis_baglari;').out.trim());

  // Y4: BASKA otelin bagini okuyamaz
  O.sql(`update public.talep_siparis_baglari set otel_id='811';`);
  es('Y4 baska otelin bagi gorunmuyor', 0,
    O.kimlikle(f.kimlik, 'select count(*) from public.talep_siparis_baglari;').out.trim());
  O.sql(`update public.talep_siparis_baglari set otel_id='810';`);

  // Y5: ayni kalem + ayni siparis iki kez baglanamaz
  const y5 = bagYaz(O, f, { kalemId: f.kalemId, siparisNo: f.siparisNo, miktar: 1 });
  sonuc(!y5.ok && /talep_siparis_baglari_talep_kalem_id_siparis_no_key|duplicate key/.test(y5.err),
    'Y5 (kalem, siparis) cifti tekrarlanamaz', hata(y5));

  console.log(`\nSONUC: ${ok} gecti, ${fail} kaldi`);
} catch (e) { console.error('DUR: ' + (e && e.message)); fail++; }
finally { try { O.temizle(); } catch { /* yoksay */ } }
process.exit(fail === 0 ? 0 : 1);
```

- [ ] **Step 3: Testi koş, kırmızı olduğunu gör**

Run: `node scripts/talep-siparis-bagi-kapilari.test.mjs`
Expected: `F 2026-10-11-talep-siparis-baglari.sql` FAIL (dosya yok)

- [ ] **Step 4: Tablo migration'ını yaz**

`docs/kurulum/2026-10-11-talep-siparis-baglari.sql`:

```sql
-- ============================================================================
-- TALEP -> SIPARIS BAG TABLOSU
-- Tasarim: docs/superpowers/specs/2026-10-11-talep-siparis-bagi-design.md §3.1
--
-- NEDEN: `satin_alma_talepleri.siparis_no` hic doldurulmuyor ve tek metin alani
-- bir talebin N siparise bolunmesini temsil edemiyor. Bu tablo (talep kalemi,
-- siparis, miktar) tanesinde kalici bag tutar.
--
-- BIRIM DONDURMA: `miktar` daima `hedef_birim` cinsindendir ve `hedef_birim`
-- bag yazildigi anda talep kaleminin birimidir. Kalan hesabi guncel katalog
-- donusumunu ASLA kullanmaz (spec §1.1).
--
-- BU DOSYA YAZILDI, URETIME UYGULANMADI.
-- ============================================================================

do $$
begin
  if to_regclass('public.satin_alma_talep_kalemleri') is null
     or to_regclass('public.siparisler') is null then
    raise exception 'ONKOSUL: talep kalemleri / siparisler tablosu yok.';
  end if;
  if to_regprocedure('public.auth_otel_erisim(text)') is null then
    raise exception 'ONKOSUL: auth_otel_erisim yok (Phase 0 gerekli).';
  end if;
end;
$$;

begin;

create table if not exists public.talep_siparis_baglari (
  id               uuid primary key default gen_random_uuid(),
  otel_id          public.otel_id not null,
  talep_id         uuid not null references public.satin_alma_talepleri(id),
  talep_kalem_id   uuid not null references public.satin_alma_talep_kalemleri(id),
  -- ON DELETE RESTRICT: bagi olan siparis SILINEMEZ (spec §7 K7).
  -- Duzeltme yolu `durum='iptal'`; bag gecmisi korunur.
  siparis_no       text not null references public.siparisler(siparis_no) on delete restrict,
  urun_kodu        text,
  miktar           numeric(12,3) not null,
  hedef_birim      text not null,
  kaynak_miktar    numeric(12,3) not null,
  kaynak_birim     text not null,
  carpan           numeric,
  olusturan_ad     text,
  olusturma_tarihi timestamptz not null default now(),
  constraint talep_siparis_baglari_miktar        check (miktar > 0),
  constraint talep_siparis_baglari_kaynak_miktar check (kaynak_miktar > 0),
  constraint talep_siparis_baglari_carpan        check (carpan is null or carpan > 0),
  constraint talep_siparis_baglari_birim         check (btrim(hedef_birim) <> '' and btrim(kaynak_birim) <> ''),
  constraint talep_siparis_baglari_tekil         unique (talep_kalem_id, siparis_no)
);

create index if not exists idx_tsb_kalem   on public.talep_siparis_baglari (talep_kalem_id);
create index if not exists idx_tsb_siparis on public.talep_siparis_baglari (siparis_no);
create index if not exists idx_tsb_otel    on public.talep_siparis_baglari (otel_id, talep_id);

-- RLS: yalniz OKUMA politikasi var. insert/update/delete politikasi YOK ve
-- ayricalik da verilmez -> yazma yalniz `security definer` RPC'den.
alter table public.talep_siparis_baglari enable row level security;

drop policy if exists tsb_select on public.talep_siparis_baglari;
create policy tsb_select on public.talep_siparis_baglari
  for select to authenticated
  using ((public.auth_yetki_var('siparis_olustur','goruntule')
          or public.auth_yetki_var('siparis_takip','goruntule'))
         and public.auth_otel_erisim(otel_id::text) is true);

-- Otel kapsamini kisitlayici katmanla da kilitle (diger tablolarla ayni desen).
drop policy if exists tsb_otel_kisit on public.talep_siparis_baglari;
create policy tsb_otel_kisit on public.talep_siparis_baglari
  as restrictive to authenticated
  using (public.auth_otel_erisim(otel_id::text) is true);

-- TABLO IZINLERI: okuma var, yazma YOK.
revoke all on table public.talep_siparis_baglari from public, anon;
revoke all on table public.talep_siparis_baglari from authenticated;
grant select on table public.talep_siparis_baglari to authenticated;
-- service_role KASITLI: sunucu tarafi raporlama okuyabilsin.
revoke all on table public.talep_siparis_baglari from service_role;
grant select on table public.talep_siparis_baglari to service_role;

commit;

notify pgrst, 'reload schema';

-- ============================================================================
-- GERI ALMA
--   begin;
--   drop table if exists public.talep_siparis_baglari;   -- BAG GECMISINI SILER
--   commit;
-- UYARI: bu tabloyu dusurmek izlenebilirlik kaydini yok eder. Yalniz hic
-- uretim verisi yazilmamisken yapilir.
-- ============================================================================
```

- [ ] **Step 5: Testi koş, yeşil olduğunu gör**

Run: `node scripts/talep-siparis-bagi-kapilari.test.mjs`
Expected: `SONUC: 8 gecti, 0 kaldi`

- [ ] **Step 6: Denetleyici**

Run: `node scripts/migration-guvenlik-kontrol.mjs docs/kurulum/2026-10-11-talep-siparis-baglari.sql`
Expected: `0 HATA | 0 UYARI`

- [ ] **Step 7: Commit**

```bash
git add docs/kurulum/2026-10-11-talep-siparis-baglari.sql \
        scripts/talep-siparis-fikstur.mjs \
        scripts/talep-siparis-bagi-kapilari.test.mjs
git commit -m "feat(talep): bag tablosu + RLS + paylasilan fikstur, izole kanit 8/0"
```

---

### Task 3: `siparisler` idempotency kolonları

**Files:**
- Create: `docs/kurulum/2026-10-11-siparisler-islem-anahtari.sql`
- Modify: `scripts/talep-siparis-bagi-kapilari.test.mjs` (A-S testleri)

**Interfaces:**
- Produces: `siparisler.islem_anahtari text` (kısmi unique, CHECK 8–100), `siparisler.islem_parmak_izi text`

- [ ] **Step 1: Testleri yaz (kırmızı olacak)**

`scripts/talep-siparis-bagi-kapilari.test.mjs` içinde `Y5`'ten sonra:

```javascript
  // --- Task 3: idempotency kolonlari ---
  const m3 = O.uygulaTekIslem('docs/kurulum/2026-10-11-siparisler-islem-anahtari.sql');
  sonuc(m3.ok, 'F3 islem_anahtari migration', m3.ok ? '' : hata(m3));

  const anahtarYaz = (no, anahtar) => O.sql(
    `update public.siparisler set islem_anahtari = ${anahtar === null ? 'null' : `'${anahtar}'`}
      where siparis_no = '${no}';`);

  // A-S1 (Review Focus 5): 7 karakter CHECK altinda
  sonuc(!anahtarYaz(f.siparisNo, '1234567').ok, 'A-S1 7 karakterli anahtar reddedildi');
  // A-S2: 101 karakter CHECK ustunde
  sonuc(!anahtarYaz(f.siparisNo, 'x'.repeat(101)).ok, 'A-S2 101 karakterli anahtar reddedildi');
  // A-S3: bos metin reddedildi
  sonuc(!anahtarYaz(f.siparisNo, '').ok, 'A-S3 bos anahtar reddedildi');
  // A1: gecerli anahtar kabul
  sonuc(anahtarYaz(f.siparisNo, 'anahtar-0001').ok, 'A1 gecerli anahtar kabul');
  // A2: ayni anahtar ikinci siparise YAZILAMAZ (kismi unique)
  sonuc(!anahtarYaz(f.siparisNo2, 'anahtar-0001').ok, 'A2 ayni anahtar iki siparise yazilamaz');
  // A3: null anahtar birden fazla siparise yazilabilir (kismi indeks)
  anahtarYaz(f.siparisNo, null); anahtarYaz(f.siparisNo2, null);
  es('A3 null anahtar kisitlanmiyor', 0,
    tek("select count(*) from public.siparisler where islem_anahtari is not null;"));
```

- [ ] **Step 2: Testi koş, kırmızı olduğunu gör**

Run: `node scripts/talep-siparis-bagi-kapilari.test.mjs`
Expected: `F3 islem_anahtari migration` FAIL (dosya yok)

- [ ] **Step 3: Migration'ı yaz**

`docs/kurulum/2026-10-11-siparisler-islem-anahtari.sql`:

```sql
-- ============================================================================
-- SIPARISLER: IDEMPOTENCY KOLONLARI
-- Tasarim: docs/superpowers/specs/2026-10-11-talep-siparis-bagi-design.md §3.3
--
-- NEDEN: kullanici "Olustur"a iki kez basarsa iki siparis olusmamali. Anahtar
-- + icerik parmak izi birlikte tutulur: ayni anahtar + ayni icerik mevcut
-- sonucu dondurur, ayni anahtar + FARKLI icerik REDDEDILIR.
--
-- Her iki kolon da nullable; mevcut uc siparis yolu bunlari yazmaz ve
-- davranislari DEGISMEZ. Paylasilan tabloya kolon eklendigi icin sema dokumu
-- ve esitlik dogrulayicisi guncellenmelidir.
--
-- BU DOSYA YAZILDI, URETIME UYGULANMADI.
-- ============================================================================

do $$
begin
  if to_regclass('public.siparisler') is null then
    raise exception 'ONKOSUL: siparisler tablosu yok.';
  end if;
end;
$$;

begin;

alter table public.siparisler add column if not exists islem_anahtari   text;
alter table public.siparisler add column if not exists islem_parmak_izi text;

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'siparisler_islem_anahtari_bicim') then
    alter table public.siparisler add constraint siparisler_islem_anahtari_bicim
      check (islem_anahtari is null
             or (islem_anahtari = btrim(islem_anahtari)
                 and length(islem_anahtari) between 8 and 100));
  end if;
end;
$$;

-- Kismi unique: yalniz dolu anahtarlar tekil. `null` serbest kalir ki
-- mevcut uc yol etkilenmesin.
create unique index if not exists siparisler_islem_anahtari_key
  on public.siparisler (islem_anahtari) where islem_anahtari is not null;

commit;

notify pgrst, 'reload schema';

-- ============================================================================
-- GERI ALMA
--   begin;
--   drop index if exists public.siparisler_islem_anahtari_key;
--   alter table public.siparisler drop constraint if exists siparisler_islem_anahtari_bicim;
--   alter table public.siparisler drop column if exists islem_parmak_izi;
--   alter table public.siparisler drop column if exists islem_anahtari;
--   commit;
-- Kolonlar dusurulurse idempotency kaybolur; RPC de geri alinmalidir.
-- ============================================================================
```

- [ ] **Step 4: Testi koş, yeşil olduğunu gör**

Run: `node scripts/talep-siparis-bagi-kapilari.test.mjs`
Expected: `SONUC: 15 gecti, 0 kaldi`

- [ ] **Step 5: Denetleyici**

Run: `node scripts/migration-guvenlik-kontrol.mjs docs/kurulum/2026-10-11-siparisler-islem-anahtari.sql`
Expected: `0 HATA | 0 UYARI`

- [ ] **Step 6: Commit**

```bash
git add docs/kurulum/2026-10-11-siparisler-islem-anahtari.sql scripts/talep-siparis-bagi-kapilari.test.mjs
git commit -m "feat(siparis): islem_anahtari + parmak izi kolonlari, sinir testleri"
```

---

### Task 4: INV kapıları (K1–K7)

**Files:**
- Create: `docs/kurulum/2026-10-11-talep-siparis-inv-kapilari.sql`
- Modify: `scripts/talep-siparis-bagi-kapilari.test.mjs` (K testleri + mutantlar)

**Interfaces:**
- Consumes: Task 2'nin `talep_siparis_baglari`
- Produces: `public.talep_bag_inv_kontrol(p_talep_kalem_id uuid, p_eklenecek numeric, p_haric_bag_id uuid default null) returns void`; tetikleyiciler `tsb_inv_ekle`, `tsb_inv_guncelle`, `sip_iptal_geri_al_inv`, `sipk_miktar_inv`, `talep_kalem_miktar_inv`, `talep_kalem_birim_kilidi`, `sip_bagli_silinemez`

**Uygulama notu (spec'in K4 maddesinin sıkılaştırılması):** K4, sipariş kalemi miktarını bağ toplamıyla karşılaştırır. Bağ `hedef_birim` cinsinden, sipariş kalemi kendi birimi cinsindendir; bu yüzden karşılaştırma **`kaynak_miktar`/`kaynak_birim`** üzerinden yapılır — sipariş satırına **girilen** değerle aynı birimdedir, dönüşüm gerekmez. Bu, §1.1'in "canlı dönüşüm kullanma" kuralına uyar.

- [ ] **Step 1: K1/K2 testlerini yaz**

`scripts/talep-siparis-bagi-kapilari.test.mjs` içinde `A3`'ten sonra:

```javascript
  // --- Task 4: INV kapilari ---
  const m4 = O.uygulaTekIslem(M4);
  sonuc(m4.ok, 'F4 INV kapilari migration', m4.ok ? '' : hata(m4));
  O.sql('delete from public.talep_siparis_baglari;');

  // K1: kalem 10 KOL. 6 KOL baglanir, sonra 5 KOL daha -> ASIM
  sonuc(bagYaz(O, f, { kalemId: f.kalemId, siparisNo: f.siparisNo, miktar: 6 }).ok,
    'K1a 6 KOL baglandi');
  const k1 = bagYaz(O, f, { kalemId: f.kalemId, siparisNo: f.siparisNo2, miktar: 5 });
  sonuc(!k1.ok && /miktar_asimi/.test(k1.err), 'K1b 5 KOL daha ASIM ile reddedildi', hata(k1));
  es('K1c asimda satir kalmadi', 1, tek('select count(*) from public.talep_siparis_baglari;'));

  // K2: UPDATE'te eski satir iki kez sayilmamali -> 6 KOL'u 9 KOL'a cikarmak GECERLI
  const k2 = O.sql(`update public.talep_siparis_baglari set miktar = 9
                     where talep_kalem_id = '${f.kalemId}'::uuid;`);
  sonuc(k2.ok, 'K2a 6 -> 9 guncellemesi kabul (old.id iki kez sayilmadi)', hata(k2));
  const k2b = O.sql(`update public.talep_siparis_baglari set miktar = 11
                      where talep_kalem_id = '${f.kalemId}'::uuid;`);
  sonuc(!k2b.ok && /miktar_asimi/.test(k2b.err), 'K2b 11 KOL guncellemesi reddedildi', hata(k2b));
  es('K2c miktar 9 olarak kaldi', 9,
    tek(`select miktar from public.talep_siparis_baglari where talep_kalem_id='${f.kalemId}'::uuid;`));
```

- [ ] **Step 2: Testi koş, kırmızı olduğunu gör**

Run: `node scripts/talep-siparis-bagi-kapilari.test.mjs`
Expected: `F4 INV kapilari migration` FAIL (dosya yok); `K1b` de FAIL (aşım geçiyor)

- [ ] **Step 3: Migration'ı yaz**

`docs/kurulum/2026-10-11-talep-siparis-inv-kapilari.sql`:

```sql
-- ============================================================================
-- INV KAPILARI (K1-K7)
-- Tasarim: docs/superpowers/specs/2026-10-11-talep-siparis-bagi-design.md §7
--
-- INV: her talep kalemi icin, IPTAL OLMAYAN siparislere ait baglarin toplami
-- kalemin miktarini asamaz; tum miktarlar kalemin kendi biriminde.
--
-- RPC'deki kontrol kullaniciya anlasilir mesaj icin; BU TETIKLEYICILER
-- degismez guvence icin. Bag hangi yoldan gelirse gelsin INV bozulamaz.
--
-- BU DOSYA YAZILDI, URETIME UYGULANMADI.
-- ============================================================================

do $$
begin
  if to_regclass('public.talep_siparis_baglari') is null then
    raise exception 'ONKOSUL: talep_siparis_baglari yok. Once bag tablosu migration''i.';
  end if;
end;
$$;

begin;

-- ---------------------------------------------------------------------------
-- Paylasilan hesap: AYNI talep kalemi satir kilidi altinda toplar.
-- `p_haric_bag_id`: UPDATE'te eski satirin iki kez sayilmamasi icin.
-- ---------------------------------------------------------------------------
create or replace function public.talep_bag_inv_kontrol(
  p_talep_kalem_id uuid,
  p_eklenecek      numeric,
  p_haric_bag_id   uuid default null)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $fn$
declare
  v_kalem numeric;
  v_birim text;
  v_bagli numeric;
begin
  -- Kilit: eszamanlı iki islem ayni kalemde sirayla hesaplar.
  select miktar, birim into v_kalem, v_birim
    from public.satin_alma_talep_kalemleri
   where id = p_talep_kalem_id
   for update;
  if not found then
    raise exception 'kalem_yok: talep kalemi % bulunamadi', p_talep_kalem_id
      using errcode = '23503';
  end if;

  select coalesce(sum(b.miktar), 0) into v_bagli
    from public.talep_siparis_baglari b
    join public.siparisler s on s.siparis_no = b.siparis_no
   where b.talep_kalem_id = p_talep_kalem_id
     and s.durum <> 'iptal'
     and b.hedef_birim = v_birim
     and (p_haric_bag_id is null or b.id <> p_haric_bag_id);

  if v_bagli + coalesce(p_eklenecek, 0) > v_kalem then
    raise exception 'miktar_asimi: kalem % (miktar % %), bagli %, eklenecek %, kalan %',
      p_talep_kalem_id, v_kalem, v_birim, v_bagli, p_eklenecek, v_kalem - v_bagli
      using errcode = '23514';
  end if;
end;
$fn$;

revoke all on function public.talep_bag_inv_kontrol(uuid, numeric, uuid) from public, anon;
revoke all on function public.talep_bag_inv_kontrol(uuid, numeric, uuid) from authenticated;
revoke all on function public.talep_bag_inv_kontrol(uuid, numeric, uuid) from service_role;

-- ---------------------------------------------------------------------------
-- K1/K2: bag insert / update
-- ---------------------------------------------------------------------------
create or replace function public.tsb_inv_tetik()
returns trigger
language plpgsql
set search_path = pg_catalog, public, pg_temp
as $fn$
begin
  if tg_op = 'INSERT' then
    perform public.talep_bag_inv_kontrol(new.talep_kalem_id, new.miktar, null);
  else
    perform public.talep_bag_inv_kontrol(new.talep_kalem_id, new.miktar, old.id);
  end if;
  return new;
end;
$fn$;

drop trigger if exists tsb_inv_ekle on public.talep_siparis_baglari;
create trigger tsb_inv_ekle before insert on public.talep_siparis_baglari
  for each row execute function public.tsb_inv_tetik();

drop trigger if exists tsb_inv_guncelle on public.talep_siparis_baglari;
create trigger tsb_inv_guncelle before update of miktar, talep_kalem_id
  on public.talep_siparis_baglari
  for each row execute function public.tsb_inv_tetik();

-- ---------------------------------------------------------------------------
-- K3: siparisi IPTALDEN GERI ALMA
-- Iptal edilmis siparisin baglari sayilmiyordu; geri alinirsa sayilacak.
-- ---------------------------------------------------------------------------
create or replace function public.sip_iptal_geri_al_inv_tetik()
returns trigger
language plpgsql
set search_path = pg_catalog, public, pg_temp
as $fn$
declare r record;
begin
  if old.durum = 'iptal' and new.durum <> 'iptal' then
    for r in select b.talep_kalem_id, sum(b.miktar) as m
               from public.talep_siparis_baglari b
              where b.siparis_no = new.siparis_no
              group by b.talep_kalem_id loop
      perform public.talep_bag_inv_kontrol(r.talep_kalem_id, r.m, null);
    end loop;
  end if;
  return new;
end;
$fn$;

drop trigger if exists sip_iptal_geri_al_inv on public.siparisler;
create trigger sip_iptal_geri_al_inv before update of durum on public.siparisler
  for each row execute function public.sip_iptal_geri_al_inv_tetik();

-- ---------------------------------------------------------------------------
-- K4: siparis kalemi miktarini DUSURME
-- Karsilastirma `kaynak_miktar`/`kaynak_birim` uzerinden: siparis satirina
-- GIRILEN deger ile ayni birimde, donusum gerekmez (spec §1.1).
-- ---------------------------------------------------------------------------
create or replace function public.sipk_miktar_inv_tetik()
returns trigger
language plpgsql
set search_path = pg_catalog, public, pg_temp
as $fn$
declare v_bagli numeric;
begin
  if new.miktar >= old.miktar then
    return new;                      -- artirma INV'i bozmaz
  end if;

  select coalesce(sum(b.kaynak_miktar), 0) into v_bagli
    from public.talep_siparis_baglari b
   where b.siparis_no = new.siparis_no
     and b.kaynak_birim = new.birim
     and coalesce(b.urun_kodu,'') = coalesce(new.urun_kodu,'');

  if new.miktar < v_bagli then
    raise exception 'bagli_miktar_altina_dusurulemez: siparis %, urun %, bagli % %, istenen %',
      new.siparis_no, coalesce(new.urun_kodu,'<kodsuz>'), v_bagli, new.birim, new.miktar
      using errcode = '23514';
  end if;
  return new;
end;
$fn$;

drop trigger if exists sipk_miktar_inv on public.siparis_kalemleri;
create trigger sipk_miktar_inv before update of miktar on public.siparis_kalemleri
  for each row execute function public.sipk_miktar_inv_tetik();

-- ---------------------------------------------------------------------------
-- K5/K6: talep kalemi miktarini dusurme + bagli kalemin birim/urun degisimi
-- ---------------------------------------------------------------------------
create or replace function public.talep_kalem_inv_tetik()
returns trigger
language plpgsql
set search_path = pg_catalog, public, pg_temp
as $fn$
declare v_bagli numeric; v_var boolean;
begin
  select exists (select 1 from public.talep_siparis_baglari
                  where talep_kalem_id = new.id) into v_var;
  if not v_var then
    return new;
  end if;

  -- K6: bagli kalemde birim/urun DEGISTIRILEMEZ (hedef_birim tutarliligi).
  if new.birim is distinct from old.birim
     or new.urun_kodu is distinct from old.urun_kodu then
    raise exception 'bagli_kalem_degistirilemez: kalem % bagli; birim/urun kodu degistirilemez', new.id
      using errcode = '23514';
  end if;

  -- K5: miktar, mevcut bag toplaminin altina dusurulemez.
  if new.miktar < old.miktar then
    select coalesce(sum(b.miktar), 0) into v_bagli
      from public.talep_siparis_baglari b
      join public.siparisler s on s.siparis_no = b.siparis_no
     where b.talep_kalem_id = new.id
       and s.durum <> 'iptal'
       and b.hedef_birim = new.birim;
    if new.miktar < v_bagli then
      raise exception 'bagli_miktar_altina_dusurulemez: kalem %, bagli % %, istenen %',
        new.id, v_bagli, new.birim, new.miktar
        using errcode = '23514';
    end if;
  end if;
  return new;
end;
$fn$;

drop trigger if exists talep_kalem_miktar_inv on public.satin_alma_talep_kalemleri;
create trigger talep_kalem_miktar_inv
  before update of miktar, birim, urun_kodu on public.satin_alma_talep_kalemleri
  for each row execute function public.talep_kalem_inv_tetik();

-- ---------------------------------------------------------------------------
-- K7: bagi olan siparis SILINEMEZ (FK restrict'in okunur mesajli esi)
-- ---------------------------------------------------------------------------
create or replace function public.sip_bagli_silinemez_tetik()
returns trigger
language plpgsql
set search_path = pg_catalog, public, pg_temp
as $fn$
begin
  if exists (select 1 from public.talep_siparis_baglari
              where siparis_no = old.siparis_no) then
    raise exception 'bagli_siparis_silinemez: % talep bagi tasiyor. Silmek yerine '
      'durum=''iptal'' yapin; bag gecmisi korunur.', old.siparis_no
      using errcode = '23503';
  end if;
  return old;
end;
$fn$;

drop trigger if exists sip_bagli_silinemez on public.siparisler;
create trigger sip_bagli_silinemez before delete on public.siparisler
  for each row execute function public.sip_bagli_silinemez_tetik();

commit;

notify pgrst, 'reload schema';

-- ============================================================================
-- GERI ALMA  (INV korumasi kalkar — bilincli yapilmadikca onerilmez)
--   begin;
--   drop trigger if exists sip_bagli_silinemez on public.siparisler;
--   drop trigger if exists talep_kalem_miktar_inv on public.satin_alma_talep_kalemleri;
--   drop trigger if exists sipk_miktar_inv on public.siparis_kalemleri;
--   drop trigger if exists sip_iptal_geri_al_inv on public.siparisler;
--   drop trigger if exists tsb_inv_guncelle on public.talep_siparis_baglari;
--   drop trigger if exists tsb_inv_ekle on public.talep_siparis_baglari;
--   drop function if exists public.sip_bagli_silinemez_tetik();
--   drop function if exists public.talep_kalem_inv_tetik();
--   drop function if exists public.sipk_miktar_inv_tetik();
--   drop function if exists public.sip_iptal_geri_al_inv_tetik();
--   drop function if exists public.tsb_inv_tetik();
--   drop function if exists public.talep_bag_inv_kontrol(uuid, numeric, uuid);
--   commit;
-- ============================================================================
```

- [ ] **Step 4: Testi koş, K1/K2 yeşil olduğunu gör**

Run: `node scripts/talep-siparis-bagi-kapilari.test.mjs`
Expected: `SONUC: 22 gecti, 0 kaldi`

- [ ] **Step 5: K3–K7 testlerini ekle**

Aynı dosyada `K2c`'den sonra:

```javascript
  // K3 KRITIK SENARYO: A iptal -> serbest miktar B'ye baglanir -> A geri acilamaz
  O.sql('delete from public.talep_siparis_baglari;');
  bagYaz(O, f, { kalemId: f.kalemId, siparisNo: f.siparisNo, miktar: 10 });   // A: tamami
  O.sql(`update public.siparisler set durum='iptal' where siparis_no='${f.siparisNo}';`);
  sonuc(bagYaz(O, f, { kalemId: f.kalemId, siparisNo: f.siparisNo2, miktar: 10 }).ok,
    'K3a iptal sonrasi serbest miktar B siparisine baglandi');
  const k3 = O.sql(`update public.siparisler set durum='bekleyen'
                     where siparis_no='${f.siparisNo}';`);
  sonuc(!k3.ok && /miktar_asimi/.test(k3.err),
    'K3b A siparisini iptalden GERI ALMA reddedildi', hata(k3));
  es('K3c A siparisinin bagi yerinde kaldi', 1,
    tek(`select count(*) from public.talep_siparis_baglari where siparis_no='${f.siparisNo}';`));

  // K7: bagi olan siparis silinemez; bagsiz silinebilir
  const k7 = O.sql(`delete from public.siparisler where siparis_no='${f.siparisNo}';`);
  sonuc(!k7.ok && /bagli_siparis_silinemez|violates foreign key/.test(k7.err),
    'K7a bagli siparis SILINEMIYOR', hata(k7));
  O.sql(`set session_replication_role = replica;
    insert into public.siparisler (siparis_no, firma_ad, otel_id, tarih, durum)
      values ('C00000003','Bagsiz','810',current_date,'bekleyen')
      on conflict (siparis_no) do nothing;
    set session_replication_role = origin;`);
  sonuc(O.sql("delete from public.siparisler where siparis_no='C00000003';").ok,
    'K7b bagsiz siparis silinebiliyor');

  // K5: talep kalemi miktarini bag toplaminin altina dusurme reddedilir
  const k5 = O.sql(`update public.satin_alma_talep_kalemleri set miktar = 5
                     where id = '${f.kalemId}'::uuid;`);
  sonuc(!k5.ok && /bagli_miktar_altina_dusurulemez/.test(k5.err),
    'K5a talep miktarini dusurme reddedildi', hata(k5));
  sonuc(O.sql(`update public.satin_alma_talep_kalemleri set miktar = 20
                where id = '${f.kalemId}'::uuid;`).ok,
    'K5b talep miktarini ARTIRMA serbest');
  O.sql(`update public.satin_alma_talep_kalemleri set miktar = 10
          where id = '${f.kalemId}'::uuid;`);

  // K6: bagli kalemin birim/urun kodu degistirilemez
  const k6 = O.sql(`update public.satin_alma_talep_kalemleri set birim = 'KG'
                     where id = '${f.kalemId}'::uuid;`);
  sonuc(!k6.ok && /bagli_kalem_degistirilemez/.test(k6.err),
    'K6a bagli kalemin birimi degistirilemez', hata(k6));
  const k6b = O.sql(`update public.satin_alma_talep_kalemleri set urun_kodu = 'BASKA'
                      where id = '${f.kalemId}'::uuid;`);
  sonuc(!k6b.ok && /bagli_kalem_degistirilemez/.test(k6b.err),
    'K6b bagli kalemin urun kodu degistirilemez', hata(k6b));

  // K4: siparis kalemi miktarini bag kaynak toplaminin altina dusurme
  O.sql(`set session_replication_role = replica;
    insert into public.siparis_kalemleri (siparis_no, urun_kodu, urun_adi, birim,
      miktar, gelen_miktar, kalan_miktar)
      values ('${f.siparisNo2}','${f.urunKodu}','Bag Test Urunu','KOL',10,0,10);
    set session_replication_role = origin;`);
  const k4 = O.sql(`update public.siparis_kalemleri set miktar = 4
                     where siparis_no='${f.siparisNo2}' and urun_kodu='${f.urunKodu}';`);
  sonuc(!k4.ok && /bagli_miktar_altina_dusurulemez/.test(k4.err),
    'K4a siparis kalemi miktarini dusurme reddedildi', hata(k4));
  sonuc(O.sql(`update public.siparis_kalemleri set miktar = 15
                where siparis_no='${f.siparisNo2}' and urun_kodu='${f.urunKodu}';`).ok,
    'K4b siparis kalemi miktarini ARTIRMA serbest');
```

- [ ] **Step 6: Testi koş**

Run: `node scripts/talep-siparis-bagi-kapilari.test.mjs`
Expected: `SONUC: 34 gecti, 0 kaldi`

- [ ] **Step 7: Eşzamanlılık ve mutant testlerini ekle**

Aynı dosyada `K4b`'den sonra:

```javascript
  // E1 ESZAMANLILIK: iki oturum ayni kaleme es zamanli bag kurar.
  // Birinci oturum kalemi kilitleyip 2 saniye bekler; ikincisi kilidi bekler
  // ve commit edilmis toplami gorur -> asim.
  O.sql('delete from public.talep_siparis_baglari;');
  const bagSql = (siparisNo, miktar) => `insert into public.talep_siparis_baglari
      (otel_id, talep_id, talep_kalem_id, siparis_no, urun_kodu, miktar, hedef_birim,
       kaynak_miktar, kaynak_birim, olusturan_ad)
    values ('810','${f.talepId}'::uuid,'${f.kalemId}'::uuid,'${siparisNo}','${f.urunKodu}',
            ${miktar},'KOL',${miktar},'KOL','es');`;
  const birinci = O.paralel({ rol: 'postgres' },
    `select miktar from public.satin_alma_talep_kalemleri
      where id='${f.kalemId}'::uuid for update;
     select pg_sleep(2);
     ${bagSql(f.siparisNo, 6)}`);
  await new Promise(r => setTimeout(r, 400));
  const ikinci = O.paralel({ rol: 'postgres' }, bagSql(f.siparisNo2, 6));
  const [r1, r2] = await Promise.all([birinci, ikinci]);
  sonuc(r1.ok && !r2.ok, 'E1a birinci gecti, ikinci reddedildi',
    'birinci=' + r1.ok + ' ikinci=' + r2.ok);
  sonuc(/miktar_asimi/.test(r2.err), 'E1b ikincinin reddi miktar_asimi');
  es('E1c toplam bagli kalem miktarini asmadi', 6,
    tek(`select coalesce(sum(miktar),0) from public.talep_siparis_baglari
          where talep_kalem_id='${f.kalemId}'::uuid;`));

  // E2 DEADLOCK YOK: iki oturum TERS sirada iki kaleme baglanir
  O.sql('delete from public.talep_siparis_baglari;');
  const ileri = O.paralel({ rol: 'postgres' },
    bagSql(f.siparisNo, 1) + `
     select pg_sleep(1);
     insert into public.talep_siparis_baglari
       (otel_id, talep_id, talep_kalem_id, siparis_no, urun_kodu, miktar, hedef_birim,
        kaynak_miktar, kaynak_birim, olusturan_ad)
     values ('810','${f.talepId}'::uuid,'${f.kalemId2}'::uuid,'${f.siparisNo}','${f.urunKodu}',
             1,'KG',1,'KG','es');`);
  const geri = O.paralel({ rol: 'postgres' },
    `insert into public.talep_siparis_baglari
       (otel_id, talep_id, talep_kalem_id, siparis_no, urun_kodu, miktar, hedef_birim,
        kaynak_miktar, kaynak_birim, olusturan_ad)
     values ('810','${f.talepId}'::uuid,'${f.kalemId2}'::uuid,'${f.siparisNo2}','${f.urunKodu}',
             1,'KG',1,'KG','es');
     select pg_sleep(1);
     ${bagSql(f.siparisNo2, 1)}`);
  const [i1, i2] = await Promise.all([ileri, geri]);
  sonuc(!/deadlock/i.test(i1.err + i2.err), 'E2 ters sirada eszamanlı kosumda DEADLOCK yok',
    (i1.ok ? 'ok' : 'hata') + '/' + (i2.ok ? 'ok' : 'hata'));

  // M1 MUTANT: kalem kilidi kalkarsa eszamanlı asim GECIYOR
  O.sql('delete from public.talep_siparis_baglari;');
  const mutant4 = readFileSync(KOK + M4, 'utf8')
    .replace('   where id = p_talep_kalem_id\n   for update;', '   where id = p_talep_kalem_id;');
  if (mutant4 === readFileSync(KOK + M4, 'utf8')) throw new Error('M1 capasi tutmadi');
  O.uygulaTekIslem(mutant4, { metin: true });
  const mb1 = O.paralel({ rol: 'postgres' },
    `select pg_sleep(0.2); ${bagSql(f.siparisNo, 6)}`);
  const mb2 = O.paralel({ rol: 'postgres' },
    `select pg_sleep(0.2); ${bagSql(f.siparisNo2, 6)}`);
  const [mr1, mr2] = await Promise.all([mb1, mb2]);
  const mToplam = Number(tek(`select coalesce(sum(miktar),0) from public.talep_siparis_baglari
                               where talep_kalem_id='${f.kalemId}'::uuid;`));
  sonuc(mr1.ok && mr2.ok && mToplam > 10,
    'M1 MUTANT: kilit kalkinca asim geciyor', 'toplam=' + mToplam);
  O.uygulaTekIslem(M4);
  O.sql('delete from public.talep_siparis_baglari;');

  // M2 MUTANT: UPDATE'te old.id cikarilmazsa gecerli guncelleme yanlis reddedilir
  bagYaz(O, f, { kalemId: f.kalemId, siparisNo: f.siparisNo, miktar: 6 });
  const mutant4b = readFileSync(KOK + M4, 'utf8')
    .replace('perform public.talep_bag_inv_kontrol(new.talep_kalem_id, new.miktar, old.id);',
             'perform public.talep_bag_inv_kontrol(new.talep_kalem_id, new.miktar, null);');
  if (mutant4b === readFileSync(KOK + M4, 'utf8')) throw new Error('M2 capasi tutmadi');
  O.uygulaTekIslem(mutant4b, { metin: true });
  const m2r = O.sql(`update public.talep_siparis_baglari set miktar = 7
                      where talep_kalem_id='${f.kalemId}'::uuid;`);
  sonuc(!m2r.ok && /miktar_asimi/.test(m2r.err),
    'M2 MUTANT: old.id cikarilmazsa gecerli guncelleme reddediliyor', hata(m2r));
  O.uygulaTekIslem(M4);
  sonuc(O.sql(`update public.talep_siparis_baglari set miktar = 7
                where talep_kalem_id='${f.kalemId}'::uuid;`).ok,
    'M2b orijinalde ayni guncelleme KABUL');
```

- [ ] **Step 8: Testi koş**

Run: `node scripts/talep-siparis-bagi-kapilari.test.mjs`
Expected: `SONUC: 43 gecti, 0 kaldi`

- [ ] **Step 9: Denetleyici ve statik kapı**

Run: `node scripts/migration-guvenlik-kontrol.mjs docs/kurulum/2026-10-11-talep-siparis-inv-kapilari.sql`
Expected: `0 HATA | 0 UYARI`

Run: `node scripts/check.mjs`
Expected: çıkış 0

- [ ] **Step 10: Commit**

```bash
git add docs/kurulum/2026-10-11-talep-siparis-inv-kapilari.sql scripts/talep-siparis-bagi-kapilari.test.mjs
git commit -m "feat(talep): INV kapilari K1-K7 + eszamanlilik ve mutant kanitlari 43/0"
```

---

### Task 5: `siparis_olustur_talepten` RPC

**Files:**
- Create: `docs/kurulum/2026-10-11-siparis-olustur-talepten.sql`
- Create: `scripts/siparis-olustur-talepten.test.mjs`

**Interfaces:**
- Consumes: `siparis_no_uret(text)` (Task 1), `talep_siparis_baglari` (Task 2), `islem_anahtari`/`islem_parmak_izi` (Task 3), `talep_bag_inv_kontrol` ve K1–K7 (Task 4), `kurFikstur` (Task 2)
- Produces: `public.siparis_olustur_talepten(p_islem_anahtari text, p_talep_id uuid, p_otel_id text, p_firma_ad text, p_cari_id uuid, p_tarih date, p_termin date, p_satirlar jsonb) returns jsonb`

- [ ] **Step 1: Testi yaz (kırmızı olacak)**

`scripts/siparis-olustur-talepten.test.mjs`:

```javascript
// siparis_olustur_talepten: tek transaction + idempotency + birim + INV.
import { readFileSync } from 'node:fs';
import { barOrtami } from './bar-test-ortam.mjs';
import { kurFikstur } from './talep-siparis-fikstur.mjs';

const KOK = new URL('..', import.meta.url).pathname.replace(/^\/([A-Za-z]:)/, '$1');
const MIG = [
  'docs/kurulum/2026-10-11-siparis-no-sayac.sql',
  'docs/kurulum/2026-10-11-talep-siparis-baglari.sql',
  'docs/kurulum/2026-10-11-siparisler-islem-anahtari.sql',
  'docs/kurulum/2026-10-11-talep-siparis-inv-kapilari.sql',
  'docs/kurulum/2026-10-11-siparis-olustur-talepten.sql',
];
const O = barOrtami({ ad: 'sip-talep', ag: 'sip-talep-net' });

let ok = 0, fail = 0;
const sonuc = (g, ad, ek) => { console.log((g ? 'OK   ' : 'FAIL ') + ad + (ek ? ' — ' + ek : '')); if (g) ok++; else fail++; };
const es = (ad, bek, olc) => sonuc(Number(bek) === Number(olc), ad, Number(bek) === Number(olc) ? String(olc) : `beklenen=${bek} olculen=${olc}`);
const tek = (q) => O.sql(q).out.trim();
const hata = (r) => (String(r.err).split('\n').filter(l => /ERROR|HATA/.test(l))[0] || '(mesaj yok)').slice(0, 120);
let f;

// RPC cagrisi — gercek uygulama kimligiyle.
const cagir = (ozel = {}) => {
  const p = {
    anahtar: 'anahtar-' + Math.random().toString(36).slice(2, 10),
    otel: '810', firma: 'Test Firma', cari: null,
    tarih: 'current_date', termin: 'null',
    satirlar: [{ talep_kalem_id: f.kalemId, miktar: 6, birim: 'KOL', tahmini_fiyat: 10 }],
    ...ozel,
  };
  return O.kimlikle(f.kimlik, `select public.siparis_olustur_talepten(
      '${p.anahtar}', '${f.talepId}'::uuid, '${p.otel}', '${p.firma}',
      ${p.cari ? `'${p.cari}'::uuid` : 'null'}, ${p.tarih}, ${p.termin},
      '${JSON.stringify(p.satirlar)}'::jsonb)::text;`);
};

const sayac = () => ({
  siparis: Number(tek('select count(*) from public.siparisler;')),
  kalem: Number(tek('select count(*) from public.siparis_kalemleri;')),
  bag: Number(tek('select count(*) from public.talep_siparis_baglari;')),
});
const esSayac = (ad, once) => {
  const s = sayac();
  sonuc(s.siparis === once.siparis && s.kalem === once.kalem && s.bag === once.bag,
    ad, JSON.stringify(s) + ' <- ' + JSON.stringify(once));
};

try {
  await O.kur();
  for (const m of MIG) {
    const r = O.uygulaTekIslem(m);
    sonuc(r.ok, 'F ' + m.split('/').pop(), r.ok ? '' : hata(r));
  }
  f = kurFikstur(O);

  // S1: MUTLU YOL — 6 KOL baglanir, kismi oldugu icin durum 'onaylandi' kalir
  const s1 = cagir();
  sonuc(s1.ok && /"ok"\s*:\s*true/.test(s1.out), 'S1a RPC basarili', hata(s1) || s1.out.slice(0, 90));
  es('S1b bir siparis yazildi', 1, tek("select count(*) from public.siparisler where islem_anahtari is not null;"));
  es('S1c bir bag yazildi', 1, tek('select count(*) from public.talep_siparis_baglari;'));
  es('S1d bag miktari 6 KOL', 6, tek('select miktar from public.talep_siparis_baglari;'));
  es('S1e hedef_birim KOL olarak donduruldu', 1,
    tek("select count(*) from public.talep_siparis_baglari where hedef_birim='KOL';"));
  sonuc(tek(`select durum from public.satin_alma_talepleri where id='${f.talepId}'::uuid;`) === 'onaylandi',
    'S1f kismi karsilamada talep durumu KORUNDU');
  es('S1g urun_kodu sunucuda turetildi', 1,
    tek(`select count(*) from public.talep_siparis_baglari where urun_kodu='${f.urunKodu}';`));

  console.log(`\nSONUC: ${ok} gecti, ${fail} kaldi`);
} catch (e) { console.error('DUR: ' + (e && e.message)); fail++; }
finally { try { O.temizle(); } catch { /* yoksay */ } }
process.exit(fail === 0 ? 0 : 1);
```

- [ ] **Step 2: Testi koş, kırmızı olduğunu gör**

Run: `node scripts/siparis-olustur-talepten.test.mjs`
Expected: `F 2026-10-11-siparis-olustur-talepten.sql` FAIL (dosya yok)

- [ ] **Step 3: RPC migration'ını yaz**

`docs/kurulum/2026-10-11-siparis-olustur-talepten.sql`:

```sql
-- ============================================================================
-- TALEPTEN SIPARIS OLUSTURMA — TEK TRANSACTION
-- Tasarim: docs/superpowers/specs/2026-10-11-talep-siparis-bagi-design.md §6
--
-- Siparis basligi + kalemleri + talep baglari AYNI transaction'da yazilir.
-- Yetki, otel, birim veya miktar kontrolu basarisizsa TAMAMI geri alinir:
-- bu yuzden her ret `raise exception` ile verilir. `return` ile ret VERILMEZ —
-- `return` transaction'i geri almaz ve o ana kadar yazilanlari birakir.
--
-- BU DOSYA YAZILDI, URETIME UYGULANMADI.
-- ============================================================================

do $$
begin
  if to_regprocedure('public.siparis_no_uret(text)') is null then
    raise exception 'ONKOSUL: siparis_no_uret yok.';
  end if;
  if to_regclass('public.talep_siparis_baglari') is null then
    raise exception 'ONKOSUL: talep_siparis_baglari yok.';
  end if;
  if not exists (select 1 from information_schema.columns
                  where table_schema='public' and table_name='siparisler'
                    and column_name='islem_anahtari') then
    raise exception 'ONKOSUL: siparisler.islem_anahtari yok.';
  end if;
end;
$$;

begin;

-- Birim katsayisi: hedef = talep kaleminin birimi. Cevrilemiyorsa NULL.
create or replace function public.talep_bag_birim_kat(
  p_urun_kodu text, p_hedef_birim text, p_kaynak_birim text)
returns numeric
language plpgsql
stable
security definer
set search_path = pg_catalog, public, pg_temp
as $fn$
declare v_katalog text; v_buyuk text; v_carpan numeric;
begin
  if p_kaynak_birim is null or btrim(p_kaynak_birim) = '' then
    return null;
  end if;
  if p_kaynak_birim = p_hedef_birim then
    return 1;
  end if;
  if p_urun_kodu is null then
    return null;                        -- katalog yok -> yalniz ayni birim
  end if;

  select u.birim into v_katalog from public.urunler u where u.kod = p_urun_kodu;
  select d.buyuk_birim, d.carpan into v_buyuk, v_carpan
    from public.urun_birim_donusum d
   where d.urun_kodu = p_urun_kodu and d.silindi = false
   limit 1;
  if v_carpan is null or v_carpan <= 0 then
    return null;
  end if;

  if p_kaynak_birim = v_buyuk and p_hedef_birim = v_katalog then
    return v_carpan;                    -- KOL -> KG
  end if;
  if p_kaynak_birim = v_katalog and p_hedef_birim = v_buyuk then
    return 1 / v_carpan;                -- KG -> KOL
  end if;
  return null;
end;
$fn$;

revoke all on function public.talep_bag_birim_kat(text, text, text) from public, anon, authenticated, service_role;

create or replace function public.siparis_olustur_talepten(
  p_islem_anahtari text,
  p_talep_id       uuid,
  p_otel_id        text,
  p_firma_ad       text,
  p_cari_id        uuid,
  p_tarih          date,
  p_termin         date,
  p_satirlar       jsonb)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $fn$
declare
  v_talep      record;
  v_kalem      record;
  v_satir      jsonb;
  v_parmak     text;
  v_mevcut     record;
  v_siparis_no text;
  v_onek       text;
  v_kat        numeric;
  v_hedef      numeric;
  v_sayi       int := 0;
  v_tam        boolean;
  v_kalan      numeric;
begin
  -- 1) YETKI — SECURITY DEFINER RLS'i atlar, kontrol burada yeniden uygulanir.
  if public.auth_yetki_var('siparis_olustur','kayit') is not true then
    raise exception 'yetkisiz: siparis_olustur kayit yetkisi gerekir' using errcode='42501';
  end if;

  -- 2) OTEL KAPSAMI
  if public.auth_otel_erisim(p_otel_id) is not true then
    raise exception 'otel_kapsami_disi: %', p_otel_id using errcode='42501';
  end if;

  -- 3) GIRDI DOGRULAMA (Review Focus 1, 4, 5)
  if p_islem_anahtari is null or length(btrim(p_islem_anahtari)) < 8
     or length(p_islem_anahtari) > 100 then
    raise exception 'anahtar_gecersiz: islem anahtari 8-100 karakter olmali'
      using errcode='22023';
  end if;
  if p_tarih is null then
    raise exception 'tarih_gecersiz: siparis tarihi zorunlu' using errcode='23514';
  end if;
  if p_termin is not null and p_termin < p_tarih then
    raise exception 'termin_gecersiz: termin (%) siparis tarihinden (%) once olamaz',
      p_termin, p_tarih using errcode='23514';
  end if;
  if p_satirlar is null or jsonb_typeof(p_satirlar) <> 'array'
     or jsonb_array_length(p_satirlar) = 0 then
    raise exception 'satir_yok: en az bir satir gerekir' using errcode='23514';
  end if;
  if exists (select 1 from jsonb_array_elements(p_satirlar) e
              where e->>'talep_kalem_id' is null
                 or (e->>'talep_kalem_id') !~ '^[0-9a-fA-F-]{36}$') then
    raise exception 'kalem_kimligi_gecersiz: her satirda gecerli talep_kalem_id olmali'
      using errcode='22023';
  end if;
  if exists (select 1 from jsonb_array_elements(p_satirlar) e
              where (e->>'miktar') is null
                 or (e->>'miktar') !~ '^[0-9]+(\.[0-9]+)?$') then
    raise exception 'miktar_gecersiz: miktar pozitif sayi olmali' using errcode='22023';
  end if;
  if (select count(*) from (select distinct e->>'talep_kalem_id' k
                              from jsonb_array_elements(p_satirlar) e) d)
     <> jsonb_array_length(p_satirlar) then
    raise exception 'tekrarli_kalem: ayni talep kalemi birden fazla satirda'
      using errcode='23514';
  end if;

  -- 4) ICERIK PARMAK IZI (tekrar gonderme sozlesmesi)
  select md5(
    coalesce(p_talep_id::text,'') || '|' || coalesce(p_otel_id,'') || '|' ||
    coalesce(p_firma_ad,'') || '|' || coalesce(p_cari_id::text,'') || '|' ||
    coalesce(p_tarih::text,'') || '|' || coalesce(p_termin::text,'') || '|' ||
    coalesce(string_agg(x.k || ':' || x.m || ':' || x.b || ':' || x.f, ','
                        order by x.k), ''))
    into v_parmak
  from (select e->>'talep_kalem_id' k, (e->>'miktar')::numeric m,
               coalesce(e->>'birim','') b, coalesce(e->>'tahmini_fiyat','') f
          from jsonb_array_elements(p_satirlar) e) x;

  -- 5) MUKERRER GONDERIM
  select siparis_no, otel_id::text as otel_id, islem_parmak_izi, olusturan_ad
    into v_mevcut
    from public.siparisler
   where islem_anahtari = p_islem_anahtari;
  if found then
    if v_mevcut.islem_parmak_izi is distinct from v_parmak then
      raise exception 'anahtar_celiskili: ayni anahtar farkli icerikle kullanilamaz'
        using errcode='23505';
    end if;
    if public.auth_otel_erisim(v_mevcut.otel_id) is not true then
      raise exception 'anahtar_celiskili: anahtar kapsam disinda' using errcode='23505';
    end if;
    return jsonb_build_object('ok', true, 'mukerrer', true,
                              'siparis_no', v_mevcut.siparis_no);
  end if;

  -- 6) TALEP — kilitle
  select t.id, t.otel_id::text as otel_id, t.durum::text as durum
    into v_talep
    from public.satin_alma_talepleri t
   where t.id = p_talep_id
   for update;
  if not found then
    raise exception 'talep_yok: %', p_talep_id using errcode='23503';
  end if;
  if v_talep.otel_id <> p_otel_id then
    raise exception 'otel_uyusmaz: talep oteli % , istek oteli %',
      v_talep.otel_id, p_otel_id using errcode='23514';
  end if;
  if v_talep.durum not in ('onaylandi','siparis') then
    raise exception 'onaylanmamis: talep durumu %', v_talep.durum using errcode='23514';
  end if;

  -- 7) NUMARA — otel onekinden (Club/Resort). Otel kodu '8xx' ise C, degilse R.
  v_onek := case when p_otel_id = '810' then 'C' else 'R' end;
  v_siparis_no := public.siparis_no_uret(v_onek);

  -- 8) BASLIK
  insert into public.siparisler
    (siparis_no, cari_id, firma_ad, otel_id, tarih, termin_tarihi, durum, tip,
     kaynak, olusturan_ad, islem_anahtari, islem_parmak_izi)
  values (v_siparis_no, p_cari_id, coalesce(p_firma_ad,''), p_otel_id::public.otel_id,
          p_tarih, p_termin, 'bekleyen', 'normal', 'talep',
          coalesce(current_setting('request.jwt.claims', true)::jsonb->>'sub','rpc'),
          p_islem_anahtari, v_parmak);

  -- 9) KALEMLER + BAGLAR
  for v_satir in select e from jsonb_array_elements(p_satirlar) e loop
    select tk.id, tk.miktar, tk.birim, tk.urun_kodu, tk.urun_adi
      into v_kalem
      from public.satin_alma_talep_kalemleri tk
     where tk.id = (v_satir->>'talep_kalem_id')::uuid
       and tk.talep_id = p_talep_id
     for update;
    if not found then
      raise exception 'kalem_yok: % bu talebe ait degil', v_satir->>'talep_kalem_id'
        using errcode='23503';
    end if;

    -- BIRIM: hedef daima talep kaleminin birimi (dondurulur).
    v_kat := public.talep_bag_birim_kat(v_kalem.urun_kodu, v_kalem.birim,
                                        coalesce(v_satir->>'birim', v_kalem.birim));
    if v_kat is null then
      raise exception 'birim_cevrilemez: kalem % (%), siparis birimi %',
        v_kalem.id, v_kalem.birim, coalesce(v_satir->>'birim','<bos>')
        using errcode='23514';
    end if;

    v_hedef := round((v_satir->>'miktar')::numeric * v_kat, 3);
    if v_hedef <= 0 then
      raise exception 'miktar_gecersiz: yuvarlama sonrasi miktar sifir (kalem %)',
        v_kalem.id using errcode='23514';
    end if;

    -- INV (kullaniciya anlasilir mesaj; tetikleyici de ayrica korur)
    select v_kalem.miktar - coalesce(sum(b.miktar), 0) into v_kalan
      from public.talep_siparis_baglari b
      join public.siparisler s on s.siparis_no = b.siparis_no
     where b.talep_kalem_id = v_kalem.id and s.durum <> 'iptal'
       and b.hedef_birim = v_kalem.birim;
    if v_hedef > v_kalan then
      raise exception 'miktar_asimi: kalem %, kalan % %, istenen % %',
        v_kalem.id, v_kalan, v_kalem.birim, v_hedef, v_kalem.birim
        using errcode='23514';
    end if;

    insert into public.siparis_kalemleri
      (siparis_no, urun_kodu, urun_adi, birim, miktar, gelen_miktar, kalan_miktar,
       tahmini_fiyat)
    values (v_siparis_no, v_kalem.urun_kodu, v_kalem.urun_adi,
            coalesce(v_satir->>'birim', v_kalem.birim),
            (v_satir->>'miktar')::numeric, 0, (v_satir->>'miktar')::numeric,
            nullif(v_satir->>'tahmini_fiyat','')::numeric);

    insert into public.talep_siparis_baglari
      (otel_id, talep_id, talep_kalem_id, siparis_no, urun_kodu, miktar, hedef_birim,
       kaynak_miktar, kaynak_birim, carpan, olusturan_ad)
    values (p_otel_id::public.otel_id, p_talep_id, v_kalem.id, v_siparis_no,
            v_kalem.urun_kodu, v_hedef, v_kalem.birim,
            (v_satir->>'miktar')::numeric, coalesce(v_satir->>'birim', v_kalem.birim),
            nullif(v_kat, 1),
            coalesce(current_setting('request.jwt.claims', true)::jsonb->>'sub','rpc'));

    v_sayi := v_sayi + 1;
  end loop;

  -- 10) TAM KARSILAMA -> talep durumu
  select not exists (
    select 1 from public.satin_alma_talep_kalemleri tk
     where tk.talep_id = p_talep_id
       and tk.miktar > coalesce((select sum(b.miktar) from public.talep_siparis_baglari b
                                   join public.siparisler s on s.siparis_no = b.siparis_no
                                  where b.talep_kalem_id = tk.id and s.durum <> 'iptal'
                                    and b.hedef_birim = tk.birim), 0))
    into v_tam;
  if v_tam then
    update public.satin_alma_talepleri set durum = 'siparis' where id = p_talep_id;
  end if;

  return jsonb_build_object('ok', true, 'mukerrer', false,
    'siparis_no', v_siparis_no, 'yazilan_kalem', v_sayi,
    'baglanan_kalem', v_sayi, 'tam_karsilandi', v_tam);
end;
$fn$;

revoke all on function public.siparis_olustur_talepten(text, uuid, text, text, uuid, date, date, jsonb) from public, anon;
revoke all on function public.siparis_olustur_talepten(text, uuid, text, text, uuid, date, date, jsonb) from service_role;
grant execute on function public.siparis_olustur_talepten(text, uuid, text, text, uuid, date, date, jsonb) to authenticated;

commit;

notify pgrst, 'reload schema';

-- ============================================================================
-- GERI ALMA
--   begin;
--   drop function if exists public.siparis_olustur_talepten(text, uuid, text, text, uuid, date, date, jsonb);
--   drop function if exists public.talep_bag_birim_kat(text, text, text);
--   commit;
-- Istemci bu RPC'ye gectikten sonra geri alinirsa talepten siparis olusturma
-- kirilir; istemci degisikligi de geri alinmalidir.
-- ============================================================================
```

- [ ] **Step 4: Testi koş, S1 yeşil olduğunu gör**

Run: `node scripts/siparis-olustur-talepten.test.mjs`
Expected: `SONUC: 12 gecti, 0 kaldi`

- [ ] **Step 5: Transaction bütünlüğü ve girdi doğrulama testlerini ekle**

Aynı dosyada `S1g`'den sonra:

```javascript
  // S2: TEK TRANSACTION — her ret yolunda HIC satir kalmiyor
  const once = sayac();
  const retler = [
    ['R-J1 eksik talep_kalem_id', { satirlar: [{ miktar: 1, birim: 'KOL' }] }],
    ['R-J2 null talep_kalem_id', { satirlar: [{ talep_kalem_id: null, miktar: 1, birim: 'KOL' }] }],
    ['R-J3 metin miktar', { satirlar: [{ talep_kalem_id: f.kalemId, miktar: 'bir', birim: 'KOL' }] }],
    ['R-T1 null tarih', { tarih: 'null' }],
    ['R-T2 termin tarihten once', { tarih: 'current_date', termin: "current_date - 1" }],
    ['R-D1 tekrarli kalem', { satirlar: [
      { talep_kalem_id: f.kalemId, miktar: 1, birim: 'KOL' },
      { talep_kalem_id: f.kalemId, miktar: 1, birim: 'KOL' }] }],
    ['R-B1 cevrilemez birim', { satirlar: [{ talep_kalem_id: f.kalemId, miktar: 1, birim: 'LT' }] }],
    ['R-M1 asim', { satirlar: [{ talep_kalem_id: f.kalemId, miktar: 99, birim: 'KOL' }] }],
    ['R-A1 kisa anahtar', { anahtar: 'abc' }],
  ];
  for (const [ad, ozel] of retler) {
    const r = cagir(ozel);
    sonuc(!r.ok, ad + ' reddedildi', hata(r));
  }
  esSayac('S2 tum retlerden sonra satir sayilari DEGISMEDI', once);

  // R-O1 (Review Focus 2): capraz otel — talep baska otelin
  O.sql(`update public.satin_alma_talepleri set otel_id='811' where id='${f.talepId}'::uuid;`);
  const ro1 = cagir();
  sonuc(!ro1.ok && /otel_uyusmaz|otel_kapsami_disi/.test(ro1.err),
    'R-O1 capraz otel reddedildi', hata(ro1));
  O.sql(`update public.satin_alma_talepleri set otel_id='810' where id='${f.talepId}'::uuid;`);
```

- [ ] **Step 6: İdempotency testlerini ekle**

```javascript
  // I1: ayni anahtar + ayni icerik -> tek siparis, mukerrer:true
  const anahtar = 'idem-anahtar-001';
  const satirlar = [{ talep_kalem_id: f.kalemId2, miktar: 10, birim: 'KG' }];
  const i1 = cagir({ anahtar, satirlar });
  sonuc(i1.ok, 'I1a ilk cagri basarili', hata(i1));
  const i2 = cagir({ anahtar, satirlar });
  sonuc(i2.ok && /"mukerrer"\s*:\s*true/.test(i2.out), 'I1b ikinci cagri mukerrer:true');
  es('I1c yalniz bir siparis yazildi', 1,
    tek(`select count(*) from public.siparisler where islem_anahtari='${anahtar}';`));

  // I2: ayni anahtar + FARKLI icerik -> anahtar_celiskili
  const i3 = cagir({ anahtar, satirlar: [{ talep_kalem_id: f.kalemId2, miktar: 5, birim: 'KG' }] });
  sonuc(!i3.ok && /anahtar_celiskili/.test(i3.err), 'I2 farkli icerik reddedildi', hata(i3));

  // I3: ESZAMANLI ayni anahtar -> tek siparis
  const anahtar2 = 'idem-anahtar-002';
  const govde = (a) => `select public.siparis_olustur_talepten(
      '${a}', '${f.talepId}'::uuid, '810', 'Es Firma', null, current_date, null,
      '${JSON.stringify([{ talep_kalem_id: f.kalemId, miktar: 1, birim: 'KOL' }])}'::jsonb)::text;`;
  const [e1, e2] = await Promise.all([
    O.paralel(f.kimlik, govde(anahtar2)),
    O.paralel(f.kimlik, govde(anahtar2)),
  ]);
  es('I3 eszamanlı ayni anahtar -> tek siparis', 1,
    tek(`select count(*) from public.siparisler where islem_anahtari='${anahtar2}';`));
  sonuc(e1.ok || e2.ok, 'I3b en az biri basarili');

  // I4 MUTANT: kismi unique indeks dusurulurse mukerrer geciyor
  O.sql('drop index if exists public.siparisler_islem_anahtari_key;');
  const i4 = cagir({ anahtar: 'mutant-anahtar-01', satirlar: [{ talep_kalem_id: f.kalemId, miktar: 1, birim: 'KOL' }] });
  O.sql(`update public.siparisler set islem_parmak_izi = 'bozuk'
          where islem_anahtari = 'mutant-anahtar-01';`);
  const i4b = cagir({ anahtar: 'mutant-anahtar-01', satirlar: [{ talep_kalem_id: f.kalemId, miktar: 1, birim: 'KOL' }] });
  sonuc(i4.ok && !i4b.ok, 'I4 MUTANT: parmak izi bozulunca celiski yakalaniyor');
  O.uygulaTekIslem('docs/kurulum/2026-10-11-siparisler-islem-anahtari.sql');
```

- [ ] **Step 7: Birim ve tam karşılama testlerini ekle**

```javascript
  // B1: KG siparis satiri KOL talebe cevrilir (carpan 12 -> 1/12)
  O.sql('delete from public.talep_siparis_baglari; delete from public.siparis_kalemleri;');
  O.sql(`delete from public.siparisler where islem_anahtari is not null;`);
  const b1 = cagir({ satirlar: [{ talep_kalem_id: f.kalemId, miktar: 24, birim: 'KG' }] });
  sonuc(b1.ok, 'B1a KG -> KOL cevrildi', hata(b1));
  es('B1b 24 KG = 2 KOL', 2, tek(`select miktar from public.talep_siparis_baglari;`));
  es('B1c carpan kaydedildi', 1,
    tek('select count(*) from public.talep_siparis_baglari where carpan is not null;'));
  es('B1d kaynak_miktar/birim korundu', 1,
    tek("select count(*) from public.talep_siparis_baglari where kaynak_miktar=24 and kaynak_birim='KG';"));

  // B2: donusum pasiflestirilirse artik cevrilemez
  O.sql(`update public.urun_birim_donusum set silindi = true where urun_kodu='${f.urunKodu}';`);
  const b2 = cagir({ satirlar: [{ talep_kalem_id: f.kalemId, miktar: 12, birim: 'KG' }] });
  sonuc(!b2.ok && /birim_cevrilemez/.test(b2.err), 'B2 pasif donusum kullanilmiyor', hata(b2));
  O.sql(`update public.urun_birim_donusum set silindi = false where urun_kodu='${f.urunKodu}';`);

  // T1: TAM karsilamada talep durumu 'siparis' olur
  O.sql('delete from public.talep_siparis_baglari;');
  O.sql(`update public.satin_alma_talepleri set durum='onaylandi' where id='${f.talepId}'::uuid;`);
  O.sql(`delete from public.satin_alma_talep_kalemleri where id='${f.kalemId2}'::uuid;`);
  const t1 = cagir({ satirlar: [{ talep_kalem_id: f.kalemId, miktar: 10, birim: 'KOL' }] });
  sonuc(t1.ok && /"tam_karsilandi"\s*:\s*true/.test(t1.out), 'T1a tam karsilandi bildirildi', hata(t1));
  sonuc(tek(`select durum from public.satin_alma_talepleri where id='${f.talepId}'::uuid;`) === 'siparis',
    'T1b talep durumu siparis oldu');
```

- [ ] **Step 8: Testi koş**

Run: `node scripts/siparis-olustur-talepten.test.mjs`
Expected: `SONUC: 38 gecti, 0 kaldi`

- [ ] **Step 9: Denetleyici ve commit**

Run: `node scripts/migration-guvenlik-kontrol.mjs docs/kurulum/2026-10-11-siparis-olustur-talepten.sql`
Expected: `0 HATA | 0 UYARI`

Run: `node scripts/check.mjs` → çıkış 0

```bash
git add docs/kurulum/2026-10-11-siparis-olustur-talepten.sql scripts/siparis-olustur-talepten.test.mjs
git commit -m "feat(siparis): talepten tek transaction'li siparis RPC'si, izole kanit 38/0"
```

---

### Task 6: `stok_acik_talep` görünümü — kalan miktar

**Files:**
- Create: `docs/kurulum/2026-10-11-stok-acik-talep-kalan.sql`
- Create: `scripts/stok-acik-talep-kalan.test.mjs`

**Interfaces:**
- Consumes: `talep_siparis_baglari` (Task 2), `kurFikstur` (Task 2)
- Produces: `public.stok_acik_talep(otel_id, urun_kodu, birim, talep_miktar)` — **`birim` kolonu yeni**

- [ ] **Step 1: Testi yaz — B1–B6 (birim dondurma kanıtı)**

`scripts/stok-acik-talep-kalan.test.mjs`:

```javascript
// stok_acik_talep: kalan miktar + BIRIM DONDURMA kaniti.
// Kritik iddia: carpan/katalog birimi/donusum degisirse ESKI KALAN DEGISMEZ.
import { readFileSync } from 'node:fs';
import { barOrtami } from './bar-test-ortam.mjs';
import { kurFikstur, bagYaz } from './talep-siparis-fikstur.mjs';

const KOK = new URL('..', import.meta.url).pathname.replace(/^\/([A-Za-z]:)/, '$1');
const MIG = [
  'docs/kurulum/2026-10-11-siparis-no-sayac.sql',
  'docs/kurulum/2026-10-11-talep-siparis-baglari.sql',
  'docs/kurulum/2026-10-11-talep-siparis-inv-kapilari.sql',
  'docs/kurulum/2026-10-11-stok-acik-talep-kalan.sql',
];
const O = barOrtami({ ad: 'acik-talep', ag: 'acik-talep-net' });

let ok = 0, fail = 0;
const sonuc = (g, ad, ek) => { console.log((g ? 'OK   ' : 'FAIL ') + ad + (ek ? ' — ' + ek : '')); if (g) ok++; else fail++; };
const es = (ad, bek, olc) => sonuc(Number(bek) === Number(olc), ad, Number(bek) === Number(olc) ? String(olc) : `beklenen=${bek} olculen=${olc}`);
const tek = (q) => O.sql(q).out.trim();
const hata = (r) => (String(r.err).split('\n').filter(l => /ERROR/.test(l))[0] || '(mesaj yok)').slice(0, 110);
let f;
const kalan = (birim) => tek(`select coalesce(sum(talep_miktar),0) from public.stok_acik_talep
  where urun_kodu='${f.urunKodu}' and birim='${birim}';`);

try {
  await O.kur();
  for (const m of MIG) {
    const r = O.uygulaTekIslem(m);
    sonuc(r.ok, 'F ' + m.split('/').pop(), r.ok ? '' : hata(r));
  }
  f = kurFikstur(O);
  // Kalem1: 10 KOL. Kalem2: 100 KG. 6 KOL baglanir -> KOL kalan 4, KG kalan 100.
  bagYaz(O, f, { kalemId: f.kalemId, siparisNo: f.siparisNo, miktar: 6, hedefBirim: 'KOL' });

  // B1 TABAN
  es('B1a KOL kalan 4', 4, kalan('KOL'));
  es('B1b KG kalan 100 (ayri satir)', 100, kalan('KG'));
  es('B1c birim bazinda IKI satir var', 2,
    tek(`select count(*) from public.stok_acik_talep where urun_kodu='${f.urunKodu}';`));

  // B2 CARPAN DEGISTI 12 -> 24: eski kalan DEGISMEZ
  O.sql(`update public.urun_birim_donusum set carpan = 24 where urun_kodu='${f.urunKodu}';`);
  es('B2 carpan 24 olunca KOL kalan hala 4', 4, kalan('KOL'));

  // B3 KATALOG BIRIMI DEGISTI KG -> LT
  O.sql(`update public.urunler set birim='LT' where kod='${f.urunKodu}';`);
  es('B3 katalog birimi LT olunca KOL kalan hala 4', 4, kalan('KOL'));
  O.sql(`update public.urunler set birim='KG' where kod='${f.urunKodu}';`);

  // B4 DONUSUM PASIFLESTI
  O.sql(`update public.urun_birim_donusum set silindi = true where urun_kodu='${f.urunKodu}';`);
  es('B4 donusum pasif olunca KOL kalan hala 4', 4, kalan('KOL'));

  // B5 DONUSUM SATIRI SILINDI
  O.sql(`delete from public.urun_birim_donusum where urun_kodu='${f.urunKodu}';`);
  es('B5 donusum silinince KOL kalan hala 4', 4, kalan('KOL'));

  // B6 MUTANT: gorunum guncel carpanla yeniden hesaplarsa B2 bozulur
  O.sql(`insert into public.urun_birim_donusum (urun_kodu, buyuk_birim, carpan, silindi)
          values ('${f.urunKodu}','KOL',24,false);`);
  const mutant = `create or replace view public.stok_acik_talep with (security_invoker=true) as
    select t.otel_id, tk.urun_kodu, u.birim as birim,
           sum(tk.miktar * coalesce(d.carpan,1) - coalesce(b.bagli,0)) as talep_miktar
      from public.satin_alma_talep_kalemleri tk
      join public.satin_alma_talepleri t on t.id = tk.talep_id
      left join public.urunler u on u.kod = tk.urun_kodu
      left join public.urun_birim_donusum d on d.urun_kodu = tk.urun_kodu and d.silindi = false
      left join (select talep_kalem_id, sum(miktar) bagli
                   from public.talep_siparis_baglari group by talep_kalem_id) b
             on b.talep_kalem_id = tk.id
     where t.durum not in ('iptal','reddedildi')
     group by t.otel_id, tk.urun_kodu, u.birim;`;
  O.sql(mutant);
  const mutantKalan = Number(tek(`select coalesce(sum(talep_miktar),0)
    from public.stok_acik_talep where urun_kodu='${f.urunKodu}';`));
  sonuc(mutantKalan !== 4, 'B6 MUTANT: guncel carpanla hesap eski kalani BOZUYOR',
    'mutant kalan=' + mutantKalan);
  O.uygulaTekIslem('docs/kurulum/2026-10-11-stok-acik-talep-kalan.sql');
  es('B6b orijinal gorunum geri geldi, kalan 4', 4, kalan('KOL'));

  console.log(`\nSONUC: ${ok} gecti, ${fail} kaldi`);
} catch (e) { console.error('DUR: ' + (e && e.message)); fail++; }
finally { try { O.temizle(); } catch { /* yoksay */ } }
process.exit(fail === 0 ? 0 : 1);
```

- [ ] **Step 2: Testi koş, kırmızı olduğunu gör**

Run: `node scripts/stok-acik-talep-kalan.test.mjs`
Expected: `F 2026-10-11-stok-acik-talep-kalan.sql` FAIL (dosya yok)

- [ ] **Step 3: Görünüm migration'ını yaz**

`docs/kurulum/2026-10-11-stok-acik-talep-kalan.sql`:

```sql
-- ============================================================================
-- stok_acik_talep: ACIK TALEP = KALAN MIKTAR
-- Tasarim: docs/superpowers/specs/2026-10-11-talep-siparis-bagi-design.md §8
--
-- BU GORUNUM KATALOG TABLOLARINA KATILMAZ. Sebebi olculdu: talep miktarini
-- GUNCEL carpanla yeniden hesaplayan bir formul eski kalani bozar.
--   10 KOL talep · 12 KG/KOL · 72 KG bag -> kalan 48 KG
--   carpan 24 olunca "miktar × guncel carpan − bagli" = 240 − 72 = 168 (YANLIS)
-- Bag yazilirken `hedef_birim` DONDURULUR; burada yalniz ayni birimdeki bag
-- toplami cikarilir ve sonuclar birime gore gruplanir.
--
-- SOZLESME DEGISIKLIGI: gorunum artik `birim` kolonu dondurur. stok-takip.html
-- bununla BIRLIKTE yayinlanmalidir, yoksa farkli birimler toplanir.
--
-- 2026-10-11-stok-acik-talep-durum-filtresi.sql BILINCLE asiliyor; o dosya
-- yeniden yazilmaz (standart bolum 5).
--
-- BU DOSYA YAZILDI, URETIME UYGULANMADI.
-- ============================================================================

do $$
begin
  if to_regclass('public.stok_acik_talep') is null then
    raise exception 'ONKOSUL: stok_acik_talep gorunumu yok.';
  end if;
  if to_regclass('public.talep_siparis_baglari') is null then
    raise exception 'ONKOSUL: talep_siparis_baglari yok.';
  end if;
end;
$$;

begin;

create or replace view public.stok_acik_talep with (security_invoker=true) as
select t.otel_id,
       tk.urun_kodu,
       tk.birim,
       sum(tk.miktar - coalesce(b.bagli, 0)) as talep_miktar
  from public.satin_alma_talep_kalemleri tk
  join public.satin_alma_talepleri t on t.id = tk.talep_id
  left join (
    select b.talep_kalem_id, b.hedef_birim, sum(b.miktar) as bagli
      from public.talep_siparis_baglari b
      join public.siparisler s on s.siparis_no = b.siparis_no
     where s.durum <> 'iptal'
     group by b.talep_kalem_id, b.hedef_birim
  ) b on b.talep_kalem_id = tk.id and b.hedef_birim = tk.birim
 where t.durum not in ('iptal', 'reddedildi')
 group by t.otel_id, tk.urun_kodu, tk.birim
having sum(tk.miktar - coalesce(b.bagli, 0)) > 0;

-- ACL KARARI ACIKCA (standart R10): cagiran yalniz authenticated.
revoke all on public.stok_acik_talep from public, anon;
grant select on public.stok_acik_talep to authenticated;

commit;

notify pgrst, 'reload schema';

-- ============================================================================
-- DENETIM SORGUSU (kapi degil, gorunurluk) — beklenen 0 satir:
--   select b.id, b.hedef_birim, tk.birim
--     from public.talep_siparis_baglari b
--     join public.satin_alma_talep_kalemleri tk on tk.id = b.talep_kalem_id
--    where b.hedef_birim <> tk.birim;
--
-- GERI ALMA: 2026-10-11-stok-acik-talep-durum-filtresi.sql dosyasindaki
-- gorunum tanimi yeniden uygulanir (o dosya degistirilmez, yeniden kosulur).
-- UYARI: geri alinirsa kismi karsilanan talebin KALANI ekranda gorunmez.
-- ============================================================================
```

- [ ] **Step 4: Testi koş, yeşil olduğunu gör**

Run: `node scripts/stok-acik-talep-kalan.test.mjs`
Expected: `SONUC: 14 gecti, 0 kaldi`

- [ ] **Step 5: İptal ve denetim testlerini ekle**

Aynı dosyada `B6b`'den sonra:

```javascript
  // IP1: siparis iptal edilince kalan GERI DONER, bag satiri KALIR
  O.sql(`update public.siparisler set durum='iptal' where siparis_no='${f.siparisNo}';`);
  es('IP1a iptal sonrasi KOL kalan 10', 10, kalan('KOL'));
  es('IP1b bag satiri korundu', 1,
    tek(`select count(*) from public.talep_siparis_baglari where siparis_no='${f.siparisNo}';`));
  O.sql(`update public.siparisler set durum='bekleyen' where siparis_no='${f.siparisNo}';`);
  es('IP1c iptal geri alinca kalan yine 4', 4, kalan('KOL'));

  // IP2: talep iptal/reddedildi ise gorunumde yok
  O.sql(`update public.satin_alma_talepleri set durum='iptal' where id='${f.talepId}'::uuid;`);
  es('IP2 iptal talep gorunumde yok', 0,
    tek(`select count(*) from public.stok_acik_talep where urun_kodu='${f.urunKodu}';`));
  O.sql(`update public.satin_alma_talepleri set durum='onaylandi' where id='${f.talepId}'::uuid;`);

  // D1: denetim sorgusu temiz tabanda 0 satir
  es('D1 hedef_birim ayrismasi yok', 0, tek(`select count(*) from public.talep_siparis_baglari b
    join public.satin_alma_talep_kalemleri tk on tk.id = b.talep_kalem_id
   where b.hedef_birim <> tk.birim;`));

  // S1: kalan sifirsa satir yok
  bagYaz(O, f, { kalemId: f.kalemId, siparisNo: f.siparisNo2, miktar: 4, hedefBirim: 'KOL' });
  es('S1 kalan sifir olunca KOL satiri yok', 0,
    tek(`select count(*) from public.stok_acik_talep
          where urun_kodu='${f.urunKodu}' and birim='KOL';`));
```

- [ ] **Step 6: Testi koş**

Run: `node scripts/stok-acik-talep-kalan.test.mjs`
Expected: `SONUC: 21 gecti, 0 kaldi`

- [ ] **Step 7: Denetleyici ve commit**

Run: `node scripts/migration-guvenlik-kontrol.mjs docs/kurulum/2026-10-11-stok-acik-talep-kalan.sql`
Expected: `0 HATA | 0 UYARI`

```bash
git add docs/kurulum/2026-10-11-stok-acik-talep-kalan.sql scripts/stok-acik-talep-kalan.test.mjs
git commit -m "feat(stok): acik talep = kalan miktar, birim dondurma kaniti 21/0"
```

---

### Task 7: İstemci — ortak numara üreteci (iade + stok-takip)

**Files:**
- Modify: `satin-alma-iade.html:160-178` (`yeniSiparisNoUret`)
- Modify: `stok-takip.html:1974-1992` (`yeniSiparisNoUret`)

**Interfaces:**
- Consumes: `public.siparis_no_uret(text)` (Task 1)
- Produces: her iki dosyada `yeniSiparisNoUret(prefix)` artık RPC çağırır; başarısızlıkta `null` döner

- [ ] **Step 1: `satin-alma-iade.html` içindeki üreteci değiştir**

`satin-alma-iade.html` içindeki `async function yeniSiparisNoUret(prefix){ ... }` gövdesinin tamamını şununla değiştir:

```javascript
// Numara artik SUNUCUDA, tek seri kaynaktan uretilir (siparis_no_sayac).
// Istemcide `max+1` YOK: iki kullanici ayni maksimumu okuyup ayni numarayi
// alabiliyordu. Hata halinde NULL doner ve cagiran siparis YAZMAZ —
// eskiden `catch` icinde rastgele numara uretiliyordu, o sessiz uydurma
// kaldirildi.
async function yeniSiparisNoUret(prefix){
  const p = prefix === 'R' ? 'R' : 'C';
  try{
    const r = await fetch(SB_URL+'/rest/v1/rpc/siparis_no_uret',{
      method:'POST', headers:SB_HEADERS, body:JSON.stringify({p_prefix:p})
    });
    if(!r.ok){ console.error('siparis_no_uret basarisiz:', r.status, await r.text().catch(()=>'')); return null; }
    const no = await r.json();
    return (typeof no === 'string' && /^[CR][0-9]{8}$/.test(no)) ? no : null;
  }catch(e){ console.warn('siparis_no_uret', e); return null; }
}
```

- [ ] **Step 2: Çağıran yeri fail-closed yap**

`satin-alma-iade.html` içinde `const siparisNo=await yeniSiparisNoUret(prefix);` satırının **hemen altına** ekle:

```javascript
  if(!siparisNo){ toast('❌ Sipariş numarası alınamadı, iade kaydedilmedi'); return; }
```

- [ ] **Step 3: Aynı iki değişikliği `stok-takip.html` için yap**

`stok-takip.html` içindeki `yeniSiparisNoUret` gövdesini Step 1'deki kodla değiştir; `const siparisNo=await yeniSiparisNoUret(prefix);` satırının altına Step 2'deki kontrolü ekle (mesajı `siparis kaydedilmedi` olarak yaz).

- [ ] **Step 4: Statik kapı**

Run: `node scripts/check.mjs`
Expected: `Tüm statik kontroller geçti.` (çıkış 0)

Run: `grep -c "max+1\|maxNo" satin-alma-iade.html stok-takip.html`
Expected: her iki dosyada `0`

- [ ] **Step 5: Commit**

```bash
git add satin-alma-iade.html stok-takip.html
git commit -m "refactor(siparis): iade ve stok-takip ortak numara ureteci RPC'sine gecti"
```

---

### Task 8: İstemci — talepten sipariş yolu

**Files:**
- Modify: `satin-alma-talepler.html:903-925` (`talepSipariseDonustur`)
- Modify: `satin-alma-siparisolustur.html:148-200` (submit yolu)

**Interfaces:**
- Consumes: `siparis_olustur_talepten(...)` (Task 5)
- Produces: `sp_devir_satirlar` artık `{ad, kod, miktar, birim, not, talepKalemId}` taşır; `sessionStorage.sp_devir_talep` = talep id

- [ ] **Step 1: `satin-alma-talepler.html` — talep kimliklerini taşı, erken RPC'yi kaldır**

`talepSipariseDonustur(id)` gövdesinde:

```javascript
async function talepSipariseDonustur(id){
  if(!['kayit','tam'].includes(YETKI_HARITASI['siparis_olustur'])){toast('⚠️ Bu işlem için yetkiniz yok');return;}
  const t=DB.talepler[id];if(!t)return;
  kModal('mTalepDetay');
  // Kalem KIMLIGI de tasiniyor: bag tablosu (talep kalemi, siparis, miktar)
  // tanesinde tutuluyor ve sunucu urun kodunu kalemden turetiyor.
  const satirlar=(t.satirlar||[]).map(u=>({
    ad:u.ad, kod:u.kod||'', miktar:u.miktar||'', birim:u.birim||'KG', not:'',
    talepKalemId:u.id||null
  }));
  sessionStorage.setItem('sp_devir_satirlar',JSON.stringify(satirlar));
  sessionStorage.setItem('sp_devir_talep', id);
  // ERKEN DURUM DAMGASI KALDIRILDI: eskiden burada talep_siparise_donustur
  // cagriliyor ve siparis olusmasa bile talep 'siparis' oluyordu. Artik durum
  // siparis yazilirken, ayni transaction'da guncelleniyor.
  location.href='satin-alma-siparisolustur.html';
}
```

- [ ] **Step 2: `t.satirlar` içinde kalem id'si var mı doğrula**

Run: `grep -n "satirlar" satin-alma-talepler.html | grep -i "id" | head -5`
Expected: talep kalemlerinin `id` alanıyla yüklendiği görülmeli. Görünmüyorsa, talep yükleme `fetch`'ine `select=...,satin_alma_talep_kalemleri(id,urun_adi,urun_kodu,miktar,birim)` eklenerek `id` taşınır ve `u.id` dolu olur.

- [ ] **Step 3: `satin-alma-siparisolustur.html` — talep yolunda tek RPC**

Devir okuma bloğuna (`const devir=sessionStorage.getItem('sp_devir_satirlar');`) talep id'sini de ekle:

```javascript
  const devirTalep = sessionStorage.getItem('sp_devir_talep');
  if(devirTalep) sessionStorage.removeItem('sp_devir_talep');
  SP_TALEP_ID = devirTalep || null;
  SP_ISLEM_ANAHTARI = (crypto.randomUUID ? crypto.randomUUID() : String(Date.now())+Math.random());
```

Dosyanın üstünde `let SP_TALEP_ID=null, SP_ISLEM_ANAHTARI=null;` tanımla.

Sipariş yazma bloğunda, `siparisler` POST'unun yerine talep yolu için şunu kullan:

```javascript
    if(SP_TALEP_ID){
      // TALEP KAYNAKLI YOL: baslik + kalemler + baglar TEK transaction.
      const r = await fetch(SB_URL+'/rest/v1/rpc/siparis_olustur_talepten',{
        method:'POST', headers:SB_HEADERS,
        body:JSON.stringify({
          p_islem_anahtari: SP_ISLEM_ANAHTARI,
          p_talep_id: SP_TALEP_ID,
          p_otel_id: otelId,
          p_firma_ad: g.firmaAd||'',
          p_cari_id: g.firmaId||null,
          p_tarih: tarih||bugunTarih(),
          p_termin: termin||null,
          p_satirlar: kalemler.map(k=>({
            talep_kalem_id: k.talepKalemId,
            miktar: k.miktar,
            birim: k.birim,
            tahmini_fiyat: k.tahminiFiyat
          }))
        })
      });
      const govde = await r.json().catch(()=>null);
      if(!r.ok || !govde || govde.ok!==true){
        toast('❌ '+siparisRetMesaji(r.status, govde));
        return;                       // TRANSACTION geri alindi; hicbir satir yok
      }
      g.siparisNo = govde.siparis_no;
      SP_ISLEM_ANAHTARI = (crypto.randomUUID ? crypto.randomUUID() : String(Date.now())+Math.random());
      if(govde.mukerrer) toast('ℹ️ Bu sipariş daha önce oluşturulmuş: '+govde.siparis_no);
    } else {
      // TALEPSIZ YOL: bu blok DEGISMEZ. Mevcut `siparisler` POST'u,
      // `siparis_kalemleri` POST'u ve PATCH'i aynen kalir; yalniz numara
      // `yeniSiparisNoUret` uzerinden RPC'den gelir (Step 5).
    }
```

- [ ] **Step 4: Ret mesajı eşleyicisini ekle**

`satin-alma-siparisolustur.html` içine ekle:

```javascript
// Sunucu ret kodlarini kullaniciya anlasilir cumleye cevirir. Sessiz yutma YOK.
function siparisRetMesaji(durum, govde){
  const m = (govde && (govde.message || govde.hata)) || '';
  if(/birim_cevrilemez/.test(m))  return 'Birim çevrilemiyor: ürünün birim dönüşümü tanımlı değil';
  if(/miktar_asimi/.test(m))      return 'Talep miktarı aşılıyor: kalan miktardan fazlasını sipariş edemezsiniz';
  if(/anahtar_celiskili/.test(m)) return 'Bu işlem anahtarı farklı bir içerikle kullanılmış; sayfayı yenileyin';
  if(/tekrarli_kalem/.test(m))    return 'Aynı talep kalemi iki satırda görünüyor';
  if(/termin_gecersiz/.test(m))   return 'Termin tarihi sipariş tarihinden önce olamaz';
  if(/onaylanmamis/.test(m))      return 'Talep onay zincirini tamamlamamış';
  if(/yetkisiz/.test(m))          return 'Sipariş oluşturma yetkiniz yok';
  if(/otel_/.test(m))             return 'Otel kapsamı dışında';
  return 'Sipariş oluşturulamadı ('+durum+')';
}
```

- [ ] **Step 5: Talepsiz akışta numarayı RPC'den al**

`satin-alma-siparisolustur.html` içindeki `yeniSiparisNoUret` gövdesini Task 7 Step 1'deki kodla değiştir ve `g.siparisNo = await yeniSiparisNoUret(sipPrefix);` satırının altına ekle:

```javascript
      if(!g.siparisNo){ toast('❌ Sipariş numarası alınamadı, sipariş kaydedilmedi'); return; }
```

- [ ] **Step 6: Statik kapı**

Run: `node scripts/check.mjs`
Expected: çıkış 0

Run: `grep -c "talep_siparise_donustur" satin-alma-talepler.html`
Expected: `0`

- [ ] **Step 7: Commit**

```bash
git add satin-alma-talepler.html satin-alma-siparisolustur.html
git commit -m "feat(talep): talepten siparis tek RPC ile; erken durum damgasi kaldirildi"
```

---

### Task 9: İstemci — görünümün yeni sözleşmesi

**Files:**
- Modify: `stok-takip.html:813-826` (`stokEkVeriYukle`) ve Talep sütunu tanımı

**Interfaces:**
- Consumes: `stok_acik_talep(otel_id, urun_kodu, birim, talep_miktar)` (Task 6)

- [ ] **Step 1: Talep verisini birimle oku**

`stokEkVeriYukle()` içindeki talep `fetch`'ini ve birikimini değiştir:

```javascript
      fetch(SB_URL+'/rest/v1/stok_acik_talep?select=otel_id,urun_kodu,birim,talep_miktar',{headers:SB_HEADERS}),
```

ve birikim satırını:

```javascript
    // Gorunum artik BIRIM bazinda satir donuyor. Farkli birimler TOPLANMAZ:
    // 10 KOL + 100 KG'yi toplamak anlamsiz bir sayi uretir.
    if(rt.ok)(await rt.json()).forEach(r=>{
      if(otel && String(r.otel_id)!==String(otel)) return;
      const k = r.urun_kodu;
      if(!talepMap[k]) talepMap[k] = {};
      talepMap[k][r.birim] = (talepMap[k][r.birim]||0) + (parseFloat(r.talep_miktar)||0);
    });
```

- [ ] **Step 2: Talep sütununu birimli göster**

Talep sütunu tanımını değiştir:

```javascript
  { key:'talep', label:'Talep', type:'text', get:s=>talepBirimliMetin(talepMap[s.lnKod]) },
```

ve yardımcıyı ekle:

```javascript
// Birim bazinda talep: "10 KOL + 100 KG" gibi gosterir. Toplama YAPMAZ.
function talepBirimliMetin(birimler){
  if(!birimler) return '';
  const p = Object.entries(birimler).filter(([,m])=>m>0)
    .map(([b,m])=>`${(Math.round(m*1000)/1000)} ${b}`);
  return p.length ? p.join(' + ') : '';
}
```

- [ ] **Step 3: Statik kapı**

Run: `node scripts/check.mjs`
Expected: çıkış 0

- [ ] **Step 4: Commit**

```bash
git add stok-takip.html
git commit -m "feat(stok): Talep sutunu birim bazinda, farkli birimler toplanmiyor"
```

---

### Task 10: Yayın paketi ve geçiş ölçümü

**Files:**
- Create: `docs/kurulum/2026-10-11-talep-siparis-yayin-paketi.md`
- Create: `docs/kurulum/2026-10-11-talep-siparis-gecis-olcumu.sql`

**Interfaces:**
- Consumes: Task 1–9'un dosyaları
- Produces: uygulama sırası, geri alma sırası, geçiş ölçüm sorgusu

- [ ] **Step 1: Geçiş ölçümü dosyasını yaz (SALT OKUMA)**

`docs/kurulum/2026-10-11-talep-siparis-gecis-olcumu.sql`:

```sql
-- ============================================================================
-- GECIS OLCUMU — SALT OKUMA (hicbir sey yazmaz, islem acmaz)
-- Tasarim §10: bagi olmayan eski talepler OTOMATIK IPTAL EDILMEZ, OTOMATIK
-- BAGLANMAZ. Bu dosya yalniz karar icin LISTE cikarir.
--
-- Calistirma:
--   .\docs\kurulum\sql-uygula.ps1 -Dosya docs\kurulum\2026-10-11-talep-siparis-gecis-olcumu.sql -SaltOkuma
-- ============================================================================

-- 1) durum='siparis' olup HIC bagi olmayan talepler (yeni gorunumde yeniden
--    acik gorunecek olanlar)
select t.id, t.otel_id, t.talep_no, t.durum::text, t.olusturma_tarihi,
       count(tk.id) as kalem_sayisi
  from public.satin_alma_talepleri t
  join public.satin_alma_talep_kalemleri tk on tk.talep_id = t.id
 where t.durum::text = 'siparis'
   and not exists (select 1 from public.talep_siparis_baglari b
                    where b.talep_id = t.id)
 group by t.id, t.otel_id, t.talep_no, t.durum, t.olusturma_tarihi
 order by t.olusturma_tarihi;

-- 2) Ozet sayi
select count(*) as bagsiz_siparis_talep_sayisi
  from public.satin_alma_talepleri t
 where t.durum::text = 'siparis'
   and not exists (select 1 from public.talep_siparis_baglari b
                    where b.talep_id = t.id);

-- 3) Gorunumun yeni ve eski halinin karsilastirmasi (etki buyuklugu)
select coalesce(sum(talep_miktar), 0) as yeni_gorunum_toplami
  from public.stok_acik_talep;

-- 4) hedef_birim ayrismasi denetimi — beklenen 0 satir
select b.id, b.hedef_birim, tk.birim as kalem_birim
  from public.talep_siparis_baglari b
  join public.satin_alma_talep_kalemleri tk on tk.id = b.talep_kalem_id
 where b.hedef_birim <> tk.birim;
```

- [ ] **Step 2: Yayın paketini yaz**

`docs/kurulum/2026-10-11-talep-siparis-yayin-paketi.md`:

```markdown
# Talep → Sipariş Bağı — Yayın Paketi (UYGULANMADI)

**Tasarım:** `docs/superpowers/specs/2026-10-11-talep-siparis-bagi-design.md`
**Plan:** `docs/superpowers/plans/2026-10-11-talep-siparis-bagi.md`

## Uygulama sırası (zorunlu)

| # | Dosya | Neden bu sırada |
|---|---|---|
| 1 | `2026-10-11-siparis-no-sayac.sql` | RPC buna bağımlı |
| 2 | `2026-10-11-talep-siparis-baglari.sql` | Kapılar ve RPC buna bağımlı |
| 3 | `2026-10-11-siparisler-islem-anahtari.sql` | RPC idempotency buna bağımlı |
| 4 | `2026-10-11-talep-siparis-inv-kapilari.sql` | Bağ tablosu var olmalı |
| 5 | `2026-10-11-siparis-olustur-talepten.sql` | 1–4'ün hepsine bağımlı |
| 6 | `2026-10-11-stok-acik-talep-kalan.sql` | Bağ tablosu var olmalı |
| 7 | **Arayüz push** (`satin-alma-talepler`, `satin-alma-siparisolustur`, `satin-alma-iade`, `stok-takip`) | Görünümün `birim` kolonu ile **birlikte** yayınlanmalı |

**Kritik:** 6 ve 7 birlikte gider. Görünüm `birim` kolonu döndürmeye başladığında
eski ekran farklı birimleri toplar ve yanlış sayı gösterir.

## Geri alma sırası (ters)

7 arayüz revert → 6 eski görünüm (`2026-10-11-stok-acik-talep-durum-filtresi.sql`
yeniden koşulur) → 5 RPC drop → 4 kapılar drop → 3 kolonlar drop → 2 bağ tablosu
**(bağ geçmişini siler — yalnız üretim verisi yoksa)** → 1 sayaç drop.

**Uyarı:** 1 geri alınırsa istemciler numara alamaz; 7 de geri alınmalıdır.

## Uygulama öncesi ölçüm

`2026-10-11-talep-siparis-gecis-olcumu.sql` salt-okuma ile koşulur. Çıktıdaki
**bağsız `siparis` talep listesi** karar için kullanıcıya sunulur. Bu talepler
yeni görünümde yeniden açık görünecektir.

**Geçiş adımı migration'ın parçası değildir.** Otomatik iptal ve otomatik
bağlama **yapılmaz**.

## Kabul ölçütleri

| Ölçüm | Beklenen |
|---|---|
| `node scripts/siparis-no-uret.test.mjs` | 10/0 |
| `node scripts/talep-siparis-bagi-kapilari.test.mjs` | 43/0 |
| `node scripts/siparis-olustur-talepten.test.mjs` | 38/0 |
| `node scripts/stok-acik-talep-kalan.test.mjs` | 21/0 |
| `node scripts/migration-guvenlik-kontrol.mjs` (varsayılan kapsam) | 0 HATA / 0 UYARI |
| `node scripts/check.mjs` | çıkış 0 |
| Geçiş ölçümü madde 4 (`hedef_birim` ayrışması) | 0 satır |

## Yapılmayacaklar

- Üretime yazma `CANLIYA UYGULA` denmeden **yok**.
- Uygulanmış migration'lar yeniden yazılmaz.
- Bağsız talepler otomatik iptal/bağlanmaz.
- `satin_alma_talepleri.siparis_no` ölü kolonu düşürülmez (ayrı karar).
- `siparisler.durum` için enum/check eklenmez (ayrı karar).
```

- [ ] **Step 3: Denetleyici (yeni SQL dosyası salt okuma olsa da kapsamda)**

Run: `node scripts/migration-guvenlik-kontrol.mjs docs/kurulum/2026-10-11-talep-siparis-gecis-olcumu.sql`
Expected: `0 HATA | 0 UYARI`

Run: `node scripts/migration-guvenlik-kontrol.mjs`
Expected: varsayılan kapsamda `0 HATA | 0 UYARI`

- [ ] **Step 4: Tüm testleri sırayla koş**

```bash
node scripts/siparis-no-uret.test.mjs
node scripts/talep-siparis-bagi-kapilari.test.mjs
node scripts/siparis-olustur-talepten.test.mjs
node scripts/stok-acik-talep-kalan.test.mjs
node scripts/check.mjs
```

Expected: 10/0 · 43/0 · 38/0 · 21/0 · çıkış 0

- [ ] **Step 5: Commit**

```bash
git add docs/kurulum/2026-10-11-talep-siparis-yayin-paketi.md \
        docs/kurulum/2026-10-11-talep-siparis-gecis-olcumu.sql
git commit -m "docs(talep): yayin paketi + salt-okuma gecis olcumu"
```
