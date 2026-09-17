# Bar Güvenliği, Gün Sonu İkmal ve Teslim Kabulü — Uygulama Planı

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Mevcut bar modülünü yeniden kurmadan; ücretli siparişte oda/folyo doğrulaması, fiyat anlık görüntüsü, tekil ve tutarlı teslim, rezervasyon yarışı ve stok çıkışı koruması, otel/pasif kullanıcı kontrolleri (Aşama 1); tüketimden gün sonu ikmal taslağı (Aşama 2); Cuma pazar ilavesi (Aşama 3); onay → sevk → kabul ayrımıyla teslim kabulü (Aşama 4).

**Architecture:** Tüm kararlar ana Supabase projesinde SECURITY DEFINER RPC'lerde verilir; istemci yalnız çağırır ve hata kodunu Türkçeye çevirir. Her aşama tek bir **aday** migration dosyası, bir geri alma dosyası, bir izole test dosyası ve bir rapordur. İzole test tabanı gerçek üretim şema dökümüdür; kritik korumalar negatif kontrolle kanıtlanır.

**Tech Stack:** PostgreSQL 17 (Supabase), plpgsql, statik HTML/JS (GitHub Pages), Supabase Edge Functions (Deno — yerelde çalışma zamanı YOK), Node 24 test betikleri, Docker `postgres:17`.

**Spec:** `docs/superpowers/specs/2026-09-17-bar-guvenlik-ikmal-kabul-design.md` (**revizyon 3** — bu plan revizyon 2'ye göre yazıldı)

> ## ⚠️ AŞAMA 1–4 BÖLÜMLERİ GEÇERSİZ (2026-09-17, tasarım revizyon 3)
>
> Tasarım revizyon 3 şu noktalarda bu planın kodunu geçersiz kılar: operasyon günü saat kesimi
> değil servis kaydına bağlı (T16) ve teslim tarihi depo takvimine bakar (T17); garson siparişi
> doğrulama sayılmaz, açık beyan gerekir (T18); "hazırlanıyor" iptali otomatik tam zayi değildir,
> kullanılan miktar belirlenir (T19); folyo kapanması zayi yapmaz, tüketim ve borç ayrı ele alınır
> (T20); veritabanı yetki testi Edge Function uçtan uca testi değildir (T21); sayımda gerçek gözlem
> kaydedilir (T22). **Task 1.1–1.8 ve Aşama 2–4 sözleşmeleri uygulanmaz.** Geçerli olan yalnız
> Aşama 0 (tamamlandı). Aşama 1 planı, spec bölüm 13'teki maddeler kesinleştikten sonra yeniden
> yazılacaktır. Aşağıdaki metin tarihsel kayıt olarak bırakıldı.

**Durum:** Aşama 0 tamamlandı (8 OK / 0 FAIL; rapor `docs/superpowers/reports/2026-09-17-bar-asama0-rapor.md`). Aşama 1 **başlamadı**; aşağıdaki Aşama 1–4 metni geçersizdir.

**Tercihlerin kaynağı:** Bu plandaki kod, spec'in "Gereksinimler ve tercihlerin kaynağı"
bölümüne dayanır. Kesin olan yalnız kullanıcının yazılı talepleridir (T1–T15). **V1–V4 çalışma
varsayımıdır, Ö1–Ö6 tasarım önerisidir; hiçbiri kesinleşmiş kullanıcı kararı değildir.** Z1–Z4
ölçüm sonucudur. Aşama 1 kodu V1, V4, Ö1, Ö2, Ö6 ve Z2'nin kabulüne dayanır; bunlar
kesinleşmeden Aşama 1'e geçilmez, farklı çıkarsa Task 1.2–1.6 o tercihe göre yeniden yazılır.

## Global Constraints

- Üretime **hiçbir** migration, `CREATE/ALTER/DROP`, `INSERT/UPDATE/DELETE`, `GRANT/REVOKE`, deploy ya da push yapılmaz; kullanıcı açıkça **`CANLIYA UYGULA`** demeden. Her aşama ayrı onaya bağlıdır.
- Kullanıcıdan DB parolası ya da tam bağlantı adresi istenmez; sır dosyaya/komut geçmişine yazılmaz.
- Kilitli hazırlık dosyaları (`node scripts/hazirlik-kilidi.mjs` listesindeki 11 dosya, `scripts/supabase-shim.sql` dahil) **değiştirilmez**.
- Eski tarihli SQL dosyaları değiştirilmez; her değişiklik yeni tarihli dosyadır ve başlığında `URETIME UYGULANMADI` bandı taşır.
- Her yeni fonksiyon: `set search_path to 'pg_catalog', 'public', 'pg_temp'`; `revoke all … from public, anon`; dışa açık olanlar `grant execute … to authenticated, service_role`; `_` ile başlayan iç fonksiyonlar **authenticated ve service_role'dan da** revoke edilir.
- Hata metinleri sabit bir **kod önekiyle** başlar: `KOD: açıklama` (kodlar spec'teki listeden).
- Operasyon günü: `((zaman AT TIME ZONE 'Europe/Istanbul') − gun_sonu_saati)::date`; varsayılan `06:00` **çalışma varsayımıdır (V4)** — değişirse yalnız `bar_ayarlari.gun_sonu_saati` varsayılanı değişir, mekanizma aynı kalır.
- İzole test tabanı: `scripts/supabase-shim.sql` → `scripts/bar-test-auth.sql` → `C:\Users\USER\ERP-Yedek\2026-09-13-post-faz2-sema-dokumu.sql` (gerçek hata **0**; tek istisna tam eşleşmeli `schema "public" already exists`, sayısı raporlanır — Z4) → `docs/kurulum/2026-09-14-stok-liste-ozet.sql` → `docs/kurulum/2026-09-17-stok-guncelleme-tarihi.sql` → aşama migration'ları.
- **A1, `stok_ekle`/`stok_transfer`'i yeniden tanımlar.** Bu iki fonksiyona ait, A1'e ait olmayan tek düzeltme `docs/kurulum/2026-09-17-stok-guncelleme-tarihi.sql`'dir (`guncelleme_tarihi = now()`). A1 gövdeleri onu İÇERİR, geri alma dosyası da onu korur; sıra `scripts/stok-guncelleme-tarihi-bar-sira.test.mjs` ile sınanır. Bu iki fonksiyonu yeniden tanımlayan her sonraki iş aynı kontrolü yapmak zorundadır: son uygulanan gövde kazanır.
- Stok çıkış koruması **SECURITY DEFINER** olmak zorundadır (Z1); testte bar yetkisi olmayan depo kullanıcısıyla, rezervasyonu göremediği önce kanıtlanarak sınanır.
- Edge Function çalışma zamanı yerelde sınanamaz (Z3); yetki kararı veritabanı fonksiyonuna taşınır ve raporda "sınanmadı" satırı zorunludur.
- Bir test ancak koruması kaldırıldığında **düşüyorsa** kanıt sayılır; kritik korumalarda negatif kontrol zorunludur.
- Test çıkış kodu ayrı okunur (`; kod=$?`); `| tail` zincirinin arkasına commit/push bağlanmaz.
- Commit yapılır, **push yapılmaz**.

---

## Dosya yapısı

| Dosya | Aşama | Sorumluluk |
|---|---|---|
| `scripts/bar-test-auth.sql` | 0 | Test katmanı: `auth.uid()`/`auth.role()` PostgREST v12 `request.jwt.claims` JSON'undan da okur. Üretime uygulanmaz. |
| `scripts/bar-test-ortam.mjs` | 0 | Atılabilir postgres; taban yükleme; `sql`, `kimlikle`, `paralel`, `uygula`, `hataKodu`. |
| `scripts/bar-test-tohum.sql` | 0 | Modül/rol/yetki, 5 kimlik, PMS konaklamaları, stok, menü. |
| `scripts/bar-test-taban.test.mjs` | 0 | Tabanın 0 hatayla kurulduğunu ve tohumun doğru olduğunu kanıtlar. |
| `docs/kurulum/2026-09-17-bar-a1-guvenlik.sql` | 1 | **Aday** migration. |
| `scripts/bar-a1-geri-al-uret.mjs` | 1 | Geri alma SQL'ini üretim dökümündeki eski gövdelerden deterministik üretir. |
| `docs/kurulum/2026-09-17-bar-a1-guvenlik-geri-al.sql` | 1 | Üretilmiş geri alma dosyası. |
| `scripts/bar-a1-guvenlik.test.mjs` | 1 | Aşama 1 veritabanı testleri. |
| `scripts/bar-a1-geri-al.test.mjs` | 1 | Geri almanın eski davranışı döndürdüğünü, A1 dışı tarih düzeltmesini ise KORUDUĞUNU kanıtlar. |
| `scripts/stok-guncelleme-tarihi-bar-sira.test.mjs` | 1 | Tarih düzeltmesi → A1 sırası: hem tarih güncellenir hem rezervasyon koruması çalışır. |
| `bar-hata.js` | 1 | Hata kodu → Türkçe metin (üç bar ekranı ortak). |
| `bar-menu.html`, `bar-garson.html`, `bar-siparis-kuyrugu.html` | 1 | Fiyat gönderimi, oda onayı, iptal nedeni, hata metinleri. |
| `docs/kurulum/musteri-projesi/masa-yonetim/index.ts` | 1 | `rapid-handler`: kimlik + otel kapsamı DB fonksiyonundan. |
| `scripts/bar-a1-ekran.test.mjs` | 1 | Ekran betiklerini Node'da çalıştırıp yük ve davranışı ölçer. |
| `docs/kurulum/2026-09-17-bar-a1-preflight.sql`, `…-dogrulama.sql` | 1 | Yayın anı salt-okuma sorguları. |
| `docs/superpowers/reports/2026-09-17-bar-asama1-rapor.md` | 1 | Aşama 1 raporu. |
| `docs/kurulum/2026-09-XX-bar-a2-ikmal-taslak.sql` + test + rapor | 2 | Bkz. Aşama 2. |
| `docs/kurulum/2026-09-XX-bar-a3-pazar-ilavesi.sql` + test + rapor | 3 | Bkz. Aşama 3. |
| `docs/kurulum/2026-09-XX-bar-a4-teslim-kabul.sql` + test + ekranlar + rapor | 4 | Bkz. Aşama 4. |

**Plan derinliği:** Aşama 0 ve 1 adım adım, tam kodla yazılmıştır. Aşama 2–4 için tablo şemaları, **kesin fonksiyon imzaları**, hata kodları ve kabul senaryoları burada sabitlenmiştir; her birinin adım adım görev dökümü, bir önceki aşamanın raporu onaylandıktan sonra `docs/superpowers/plans/2026-09-XX-bar-a{2,3,4}-*.md` olarak aynı biçimde yazılır (önceki aşamanın ölçümleri sonrakinin kodunu değiştirebilir).

---

## Aşama 0 — İzole test tabanı

### Task 0.1: Test kimlik katmanı ve ortam yardımcısı

**Files:**
- Create: `scripts/bar-test-auth.sql`
- Create: `scripts/bar-test-ortam.mjs`

**Interfaces:**
- Produces: `barOrtami({ad}) → { kur({onceki:string[]}), uygula(dosya) → Sonuc, sql(q) → Sonuc, kimlikle(kimlik, q) → Sonuc, paralel(kimlik, q) → Promise<Sonuc>, temizle() }`; `Sonuc = {ok:boolean, out:string, err:string}`; `hataKodu(Sonuc) → string|null`; `kimlik = {rol:'authenticated'|'service_role'|'anon', sub?:uuid}`.

- [ ] **Step 1: Kimlik katmanını yaz**

```sql
-- scripts/bar-test-auth.sql
-- ============================================================================
-- TEST KIMLIK KATMANI — URETIME UYGULANMAZ
-- ============================================================================
-- supabase-shim.sql auth.uid()'i eski 'request.jwt.claim.sub' ayarindan okur.
-- PostgREST v12 ve Supabase kimligi 'request.jwt.claims' JSON'unda tasir.
-- Supabase'in kendi auth.uid() tanimi IKISINE de bakar; burada ayni tanim
-- kurulur. Shim kilitli dosya oldugu icin degistirilmez, ustune yazilir.
-- ============================================================================
create or replace function auth.uid() returns uuid language sql stable as $$
  select nullif(coalesce(
    current_setting('request.jwt.claim.sub', true),
    (nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub')
  ), '')::uuid;
$$;

create or replace function auth.role() returns text language sql stable as $$
  select nullif(coalesce(
    current_setting('request.jwt.claim.role', true),
    (nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role')
  ), '');
$$;
```

- [ ] **Step 2: Ortam yardımcısını yaz**

```js
// scripts/bar-test-ortam.mjs
// ===========================================================================
// BAR IZOLE TEST ORTAMI — uretime BAGLANMAZ
// ===========================================================================
// Taban GERCEK uretim semasidir (dokum): bar/PMS fonksiyonlari, politikalari
// ve tetikleyicileri uretimdeki gibi calisir. Aday migration'lar bunun ustune
// uygulanir. Kimlik, PostgREST'in yaptigi gibi rol + request.jwt.claims ile
// kurulur; RLS ve yetki fonksiyonlari gercekten devreye girer.
// ===========================================================================
import { spawnSync, spawn } from 'node:child_process';
import { readFileSync, existsSync } from 'node:fs';
import { setTimeout as bekle } from 'node:timers/promises';

export const kok = new URL('..', import.meta.url).pathname.replace(/^\/([A-Za-z]:)/, '$1');
export const SEMA_DOKUMU = process.env.BAR_TEST_SEMA
  || 'C:/Users/USER/ERP-Yedek/2026-09-13-post-faz2-sema-dokumu.sql';

export function hataKodu(sonuc) {
  const m = String(sonuc && sonuc.err || '').match(/ERROR:\s+([A-Z][A-Z_]{3,}):/);
  return m ? m[1] : null;
}

export function barOrtami({ ad = 'bar-test' } = {}) {
  const K = ad + '-db';
  const d = (a, girdi) => spawnSync('docker', a,
    { input: girdi, encoding: 'utf8', timeout: 600000, maxBuffer: 256 * 1024 * 1024 });
  const psqlArg = (ek = []) => ['exec', '-i', K, 'psql', '-X', '-U', 'postgres', '-d', 'bar', ...ek];
  const sonucla = (r) => ({ ok: r.status === 0, out: (r.stdout || '').trim(), err: (r.stderr || '').trim() });

  const sql = (q) => sonucla(d(psqlArg(['-q', '-At', '-F', '|', '-v', 'ON_ERROR_STOP=1']), q));

  function kimlikGovdesi(kimlik, q) {
    const claims = JSON.stringify(kimlik.sub ? { sub: kimlik.sub, role: kimlik.rol } : { role: kimlik.rol });
    return `begin;\nset local role ${kimlik.rol};\nset local request.jwt.claims = '${claims}';\n${q}\ncommit;\n`;
  }
  const kimlikle = (kimlik, q) => sql(kimlikGovdesi(kimlik, q));

  function paralel(kimlik, q) {
    return new Promise((coz) => {
      const p = spawn('docker', psqlArg(['-q', '-At', '-F', '|', '-v', 'ON_ERROR_STOP=1']));
      let out = '', err = '';
      p.stdout.on('data', (x) => { out += x; });
      p.stderr.on('data', (x) => { err += x; });
      p.on('close', (c) => coz({ ok: c === 0, out: out.trim(), err: err.trim() }));
      p.stdin.end(kimlikGovdesi(kimlik, q));
    });
  }

  function temizle() { spawnSync('docker', ['rm', '-f', K]); }

  function zorunlu(r, adim) {
    if (!r.ok) throw new Error(adim + ' basarisiz:\n' + r.err.split('\n').slice(-8).join('\n'));
    return r;
  }

  const uygula = (dosya) => sql(readFileSync(kok + dosya, 'utf8'));

  // Kurulumun olculen ozeti: testler raporda gostersin diye.
  const kurulumBilgisi = { dokumHata: null, dokumZararsiz: null };

  async function kur({ onceki = [] } = {}) {
    if (!existsSync(SEMA_DOKUMU)) throw new Error('Sema dokumu yok: ' + SEMA_DOKUMU);
    temizle();
    zorunlu(sonucla(d(['run', '--detach', '--rm', '--name', K, '--tmpfs', '/var/lib/postgresql/data',
      '-e', 'POSTGRES_HOST_AUTH_METHOD=trust', 'postgres:17'])), 'konteyner');
    for (let i = 0; i < 60; i++) {
      if (spawnSync('docker', ['exec', K, 'pg_isready', '-U', 'postgres']).status === 0) break;
      await bekle(1000);
    }
    await bekle(1500);
    zorunlu(sonucla(d(['exec', K, 'createdb', '-U', 'postgres', 'bar'])), 'createdb');
    zorunlu(sql(readFileSync(kok + 'scripts/supabase-shim.sql', 'utf8')), 'shim');
    zorunlu(sql(readFileSync(kok + 'scripts/bar-test-auth.sql', 'utf8')), 'kimlik katmani');

    // Dokum ON_ERROR_STOP OLMADAN yuklenir ki TUM hatalar sayilabilsin.
    // TEK ISTISNA, tam eslesmeyle: pg_dump 'CREATE SCHEMA public;' yazar ve
    // public her bos veritabaninda zaten vardir. E-5 provasi ve
    // scripts/dokum-dogrula.mjs de yalniz bu satiri zararsiz sayar.
    const r = sonucla(d(psqlArg(['-q']), readFileSync(SEMA_DOKUMU, 'utf8')));
    const tumHatalar = r.err.split('\n').filter((l) => /ERROR:/.test(l));
    const zararsiz = tumHatalar.filter((l) => /ERROR:\s+schema "public" already exists$/.test(l.trim()));
    const hatalar = tumHatalar.filter((l) => !zararsiz.includes(l));
    kurulumBilgisi.dokumHata = hatalar.length;
    kurulumBilgisi.dokumZararsiz = zararsiz.length;
    if (hatalar.length) throw new Error('Sema dokumu ' + hatalar.length + ' hatayla yuklendi:\n' + hatalar.slice(0, 8).join('\n'));

    for (const m of onceki) zorunlu(uygula(m), m);
    zorunlu(sql(readFileSync(kok + 'scripts/bar-test-tohum.sql', 'utf8')), 'tohum');
  }

  return { kur, uygula, sql, kimlikle, paralel, temizle, kurulumBilgisi };
}
```

- [ ] **Step 3: Sözdizimini kontrol et**

Run: `node --check scripts/bar-test-ortam.mjs; echo "kod=$?"`
Expected: `kod=0`

- [ ] **Step 4: Commit**

```bash
git add scripts/bar-test-auth.sql scripts/bar-test-ortam.mjs
git commit -m "test(bar): izole test ortami ve PostgREST v12 kimlik katmani"
```

### Task 0.2: Tohum verisi ve taban testi

**Files:**
- Create: `scripts/bar-test-tohum.sql`
- Create: `scripts/bar-test-taban.test.mjs`

**Interfaces:**
- Consumes: `barOrtami`, `hataKodu` (Task 0.1).
- Produces: sabit kimlikler ve kayıt id'leri — tüm aşama testleri bunları kullanır:

| Anahtar | Değer |
|---|---|
| `BAR810` sub | `11111111-0000-0000-0000-000000000810` (rol `bar`, otel 810, `bar_siparis_yonetimi:kayit`, `stok_takip:kayit`) |
| `BAR811` sub | `11111111-0000-0000-0000-000000000811` (rol `bar`, otel 811) |
| `PASIF` sub | `11111111-0000-0000-0000-0000000000aa` (rol `bar`, otel 810, `aktif=false`) |
| `GORUNTU` sub | `11111111-0000-0000-0000-0000000000bb` (`bar_siparis_yonetimi:goruntule`) |
| `DEPO810` sub | `11111111-0000-0000-0000-0000000000cc` (rol `depo`, `stok_takip:kayit`) |
| Menü | `bira 22222222-0000-0000-0000-000000000001` (ücretsiz, BIRA×1) · `viski …0002` (ücretli 250, VISKI×1) · `limonata …0003` (ücretsiz, stoksuz) · `bira811 …0811` (otel 811) |
| Odalar 810 | `101` aktif konaklama + açık folyo `55555555-0000-0000-0000-000000000101` · `102` konaklama + **kapalı** folyo · `103` boş |
| Oda 811 | `101` aktif konaklama + açık folyo `55555555-0000-0000-0000-000000000811` |
| Stok | `810_CSM302`: BIRA 10, VISKI 2, LIMON 50 · `810_100`: BIRA 100 |

- [ ] **Step 1: Tohumu yaz**

```sql
-- scripts/bar-test-tohum.sql — IZOLE TEST VERISI, uretime uygulanmaz.
-- PMS tetikleyicileri tohumlama sirasinda devre disi: konaklama durumunu
-- dogrudan kurmak icin (check-in akisinin kendisi burada sinanmiyor).
set session_replication_role = replica;

insert into public.moduller (id, kod, ad, kategori, sira, aktif) values
  ('00000000-0000-0000-0000-00000000a001', 'bar_siparis_yonetimi', 'Bar / Restoran Siparis', 'fb', 43, true),
  ('00000000-0000-0000-0000-00000000a002', 'stok_takip', 'Stok Takip', 'depo', 10, true);

insert into public.roller (id, ad, seviye, kod, sira) values
  ('00000000-0000-0000-0000-00000000b001', 'Bar Sefi', 'otel', 'bar', 18),
  ('00000000-0000-0000-0000-00000000b002', 'Bar Goruntuleyici', 'otel', 'bar_goruntu', 98),
  ('00000000-0000-0000-0000-00000000b003', 'Depo Elemani', 'otel', 'depo', 14);

insert into public.yetki_matrisi (rol_id, modul_id, yetki) values
  ('00000000-0000-0000-0000-00000000b001', '00000000-0000-0000-0000-00000000a001', 'kayit'),
  ('00000000-0000-0000-0000-00000000b001', '00000000-0000-0000-0000-00000000a002', 'kayit'),
  ('00000000-0000-0000-0000-00000000b002', '00000000-0000-0000-0000-00000000a001', 'goruntule'),
  ('00000000-0000-0000-0000-00000000b003', '00000000-0000-0000-0000-00000000a002', 'kayit');

insert into auth.users (id, email) values
  ('11111111-0000-0000-0000-000000000810', 'bar810@test.local'),
  ('11111111-0000-0000-0000-000000000811', 'bar811@test.local'),
  ('11111111-0000-0000-0000-0000000000aa', 'pasif@test.local'),
  ('11111111-0000-0000-0000-0000000000bb', 'goruntu@test.local'),
  ('11111111-0000-0000-0000-0000000000cc', 'depo810@test.local');

insert into public.kullanicilar (id, auth_user_id, ad, rol, otel_id, aktif, rol_id) values
  ('33333333-0000-0000-0000-000000000810', '11111111-0000-0000-0000-000000000810', 'Bar 810', 'bar', '810', true,  '00000000-0000-0000-0000-00000000b001'),
  ('33333333-0000-0000-0000-000000000811', '11111111-0000-0000-0000-000000000811', 'Bar 811', 'bar', '811', true,  '00000000-0000-0000-0000-00000000b001'),
  ('33333333-0000-0000-0000-0000000000aa', '11111111-0000-0000-0000-0000000000aa', 'Pasif',   'bar', '810', false, '00000000-0000-0000-0000-00000000b001'),
  ('33333333-0000-0000-0000-0000000000bb', '11111111-0000-0000-0000-0000000000bb', 'Goruntu', 'bar', '810', true,  '00000000-0000-0000-0000-00000000b002'),
  ('33333333-0000-0000-0000-0000000000cc', '11111111-0000-0000-0000-0000000000cc', 'Depo 810','depo','810', true,  '00000000-0000-0000-0000-00000000b003');

-- PMS: 810 odalari 101 (acik folyo), 102 (kapali folyo), 103 (bos); 811 odasi 101
insert into public.pms_oda_tipleri (id, otel_id, kod, ad, azami_kisi, azami_yetiskin) values
  ('44444444-0000-0000-0000-000000000810', '810', 'STD', 'Standart', 3, 2),
  ('44444444-0000-0000-0000-000000000811', '811', 'STD', 'Standart', 3, 2);
insert into public.pms_odalar (id, otel_id, oda_tipi_id, oda_no, kullanim_durumu) values
  ('66666666-0000-0000-0000-000000000101', '810', '44444444-0000-0000-0000-000000000810', '101', 'dolu'),
  ('66666666-0000-0000-0000-000000000102', '810', '44444444-0000-0000-0000-000000000810', '102', 'dolu'),
  ('66666666-0000-0000-0000-000000000103', '810', '44444444-0000-0000-0000-000000000810', '103', 'bos'),
  ('66666666-0000-0000-0000-000000000811', '811', '44444444-0000-0000-0000-000000000811', '101', 'dolu');
insert into public.pms_misafirler (id, otel_id, ad, soyad) values
  ('77777777-0000-0000-0000-000000000101', '810', 'Test', 'Birinci'),
  ('77777777-0000-0000-0000-000000000102', '810', 'Test', 'Ikinci'),
  ('77777777-0000-0000-0000-000000000811', '811', 'Test', 'Resort');
insert into public.pms_rezervasyonlar (id, otel_id, rezervasyon_no, misafir_id, oda_tipi_id, giris_tarihi, cikis_tarihi, durum, giris_zamani) values
  ('88888888-0000-0000-0000-000000000101', '810', 'T-101', '77777777-0000-0000-0000-000000000101', '44444444-0000-0000-0000-000000000810', current_date - 1, current_date + 3, 'giris_yapildi', now()),
  ('88888888-0000-0000-0000-000000000102', '810', 'T-102', '77777777-0000-0000-0000-000000000102', '44444444-0000-0000-0000-000000000810', current_date - 1, current_date + 3, 'giris_yapildi', now()),
  ('88888888-0000-0000-0000-000000000811', '811', 'T-811', '77777777-0000-0000-0000-000000000811', '44444444-0000-0000-0000-000000000811', current_date - 1, current_date + 3, 'giris_yapildi', now());
insert into public.pms_oda_atamalari (otel_id, rezervasyon_id, oda_id, baslangic, bitis, aktif) values
  ('810', '88888888-0000-0000-0000-000000000101', '66666666-0000-0000-0000-000000000101', current_date - 1, current_date + 3, true),
  ('810', '88888888-0000-0000-0000-000000000102', '66666666-0000-0000-0000-000000000102', current_date - 1, current_date + 3, true),
  ('811', '88888888-0000-0000-0000-000000000811', '66666666-0000-0000-0000-000000000811', current_date - 1, current_date + 3, true);
insert into public.pms_folyolar (id, otel_id, rezervasyon_id, folio_no, durum, kapanis_zamani) values
  ('55555555-0000-0000-0000-000000000101', '810', '88888888-0000-0000-0000-000000000101', 'F-101', 'acik', null),
  ('55555555-0000-0000-0000-000000000102', '810', '88888888-0000-0000-0000-000000000102', 'F-102', 'kapali', now()),
  ('55555555-0000-0000-0000-000000000811', '811', '88888888-0000-0000-0000-000000000811', 'F-811', 'acik', null);

insert into public.urunler (kod, ad, birim) values
  ('BIRA', 'Bira', 'KTU'), ('VISKI', 'Viski', 'CL'), ('LIMON', 'Limon', 'ADET');
insert into public.stok (urun_kodu, depo_kodu, otel_id, miktar) values
  ('BIRA', '810_CSM302', '810', 10), ('VISKI', '810_CSM302', '810', 2),
  ('LIMON', '810_CSM302', '810', 50), ('BIRA', '810_100', '810', 100);
insert into public.menu_urunler (id, ad, kategori, otel_id, fiyat, aktif, ucretli, tip, stok_kodu, miktar_per_porsiyon) values
  ('22222222-0000-0000-0000-000000000001', 'Bira',     'icecek', '810', 0,   true, false, 'direkt', 'BIRA',  1),
  ('22222222-0000-0000-0000-000000000002', 'Viski',    'icecek', '810', 250, true, true,  'direkt', 'VISKI', 1),
  ('22222222-0000-0000-0000-000000000003', 'Limonata', 'icecek', '810', 0,   true, false, 'direkt', null,    null),
  ('22222222-0000-0000-0000-000000000811', 'Bira',     'icecek', '811', 0,   true, false, 'direkt', 'BIRA',  1);

set session_replication_role = origin;
```

- [ ] **Step 2: Taban testini yaz**

```js
// scripts/bar-test-taban.test.mjs — izole tabanin kendisini dogrular.
import { readFileSync } from 'node:fs';
import { barOrtami, SEMA_DOKUMU } from './bar-test-ortam.mjs';

const O = barOrtami({ ad: 'bar-taban' });
let ok = 0, fail = 0;
const sonuc = (g, ad, ek) => { console.log((g ? 'OK   ' : 'FAIL ') + ad + (ek ? ' — ' + ek : '')); if (g) ok++; else fail++; };

try {
  await O.kur({ onceki: ['docs/kurulum/2026-09-14-stok-liste-ozet.sql'] });
  const kb = O.kurulumBilgisi;
  sonuc(kb.dokumHata === 0 && kb.dokumZararsiz === 1,
    'taban kuruldu: shim + kimlik katmani + uretim dokumu + stok migration + tohum',
    `dokum: ${kb.dokumHata} hata, ${kb.dokumZararsiz} bilinen zararsiz (schema public already exists)`);

  // Beklenen sayilar TAHMIN edilmez: dokumun kendisinden sayilir ve yuklenen
  // katalogla karsilastirilir. Sessizce eksik yuklenen nesne burada gorunur.
  const dokum = readFileSync(SEMA_DOKUMU, 'utf8');
  const dokumSay = (re) => (dokum.match(re) || []).length;
  const bekFonk = dokumSay(/^CREATE FUNCTION public\.bar_[a-z_]+\(/gm);
  const bekPol = dokumSay(/^CREATE POLICY \S+ ON public\.(bar_siparisleri|bar_siparis_kalemleri|menu_urunler|recete_bilesenleri|stok_rezervasyonlari) /gm);
  const bekTet = dokumSay(/^CREATE TRIGGER \S+ (BEFORE|AFTER) [^\n]* ON public\.bar_siparisleri /gm);
  const nesne = O.sql(`select
      (select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace
        where n.nspname='public' and p.proname like 'bar\\_%'),
      (select count(*) from pg_policy where polrelid in ('public.bar_siparisleri'::regclass,'public.bar_siparis_kalemleri'::regclass,
         'public.menu_urunler'::regclass,'public.recete_bilesenleri'::regclass,'public.stok_rezervasyonlari'::regclass)),
      (select count(*) from pg_trigger where tgrelid='public.bar_siparisleri'::regclass and not tgisinternal);`);
  const bek = `${bekFonk}|${bekPol}|${bekTet}`;
  sonuc(nesne.ok && bekFonk > 0 && nesne.out === bek,
    'uretim bar nesneleri dokumdeki sayilarla birebir yuklendi (fonksiyon|politika|tetikleyici)',
    `katalog ${nesne.out || nesne.err} / dokum ${bek}`);

  const uid = O.kimlikle({ rol: 'authenticated', sub: '11111111-0000-0000-0000-000000000810' }, 'select auth.uid();');
  sonuc(uid.out === '11111111-0000-0000-0000-000000000810', 'auth.uid() request.jwt.claims JSONundan okunuyor', uid.out || uid.err);

  const y = O.kimlikle({ rol: 'authenticated', sub: '11111111-0000-0000-0000-000000000810' },
    "select public.auth_yetki_var('bar_siparis_yonetimi','kayit'), public.auth_otel_erisim('810'), public.auth_otel_erisim('811');");
  sonuc(y.out === 't|t|f', 'BAR810: bar kayit yetkisi var, 810 erisimi var, 811 yok', y.out || y.err);

  const p = O.kimlikle({ rol: 'authenticated', sub: '11111111-0000-0000-0000-0000000000aa' },
    "select public.auth_yetki_var('bar_siparis_yonetimi','kayit');");
  sonuc(p.out === 'f', 'PASIF kullanicinin yetkisi yok (fail-closed)', p.out || p.err);

  const s = O.sql(`select count(*) from public.bar_siparisleri;`);
  sonuc(s.out === '0', 'bar siparis tablosu bos basliyor', s.out);

  const r = O.kimlikle({ rol: 'authenticated', sub: '11111111-0000-0000-0000-000000000810' },
    `select public.bar_siparis_olustur('810','810_CSM302','Masa 1',null,'[{"menu_urun_id":"22222222-0000-0000-0000-000000000001","adet":2}]'::jsonb) is not null;`);
  sonuc(r.out === 't', 'mevcut (uretim) bar_siparis_olustur tabanda calisiyor', r.out || r.err.slice(-160));

  // TASARIM OLCUMU (Z1): bar yetkisi olmayan depo kullanicisi aktif rezervasyonu
  // GOREBILIYOR mu? Goremiyorsa, cagiranin haklariyla calisan bir stok cikis
  // korumasi rezervasyon toplamini 0 okur ve sessizce devre disi kalir.
  const gercek = O.sql(`select count(*) from public.stok_rezervasyonlari where durum='aktif';`).out;
  const depo = O.kimlikle({ rol: 'authenticated', sub: '11111111-0000-0000-0000-0000000000cc' },
    'select count(*) from public.stok_rezervasyonlari;');
  sonuc(gercek === '1' && depo.ok && depo.out === '0',
    'Z1 olcumu: aktif rezervasyon var ama depo kullanicisi onu RLS yuzunden GOREMIYOR',
    `gercek ${gercek}, depo kullanicisi goruyor ${depo.out || depo.err}`);
} catch (e) {
  sonuc(false, 'taban kurulumu', e.message);
} finally {
  O.temizle();
}
console.log('\nBAR TABAN SONUC: ' + ok + ' OK / ' + fail + ' FAIL');
process.exit(fail ? 1 : 0);
```

- [ ] **Step 3: Çalıştır**

Run: `node scripts/bar-test-taban.test.mjs; echo "kod=$?"`
Expected: `BAR TABAN SONUC: 8 OK / 0 FAIL` ve `kod=0`.

**Sonuç (2026-09-17, çalıştırıldı):** ilk koşu döküm yüklemesinde `schema "public" already exists` ile **düştü**. Neden ölçüldü: `pg_dump` `CREATE SCHEMA public;` yazar, `public` her boş veritabanında vardır; E-5 provası ve `scripts/dokum-dogrula.mjs` yalnız bu satırı zararsız sayar. Ortam aynı kuralı **tam eşleşmeyle** uygular ve sayısını raporlar. Ayrıca "bar nesneleri dökümdeki sayılarla birebir yüklendi" kontrolü eklendi (beklenen sayılar dökümden sayılır). İkinci koşu: 7 OK / 0 FAIL. Ardından Z1 (depo kullanıcısı rezervasyonu göremiyor) ölçüm olarak eklendi; üçüncü koşu: **8 OK / 0 FAIL, kod=0** — gerçek aktif rezervasyon 1, depo kullanıcısının gördüğü 0 — döküm 0 hata + 1 bilinen zararsız; katalog 5|13|5 = döküm 5|13|5. Döküm yükleme hatası varsa hatalar listelenir; **tohum ya da katman değiştirilerek değil, hatanın nedeni ölçülerek** çözülür.

- [ ] **Step 4: Commit**

```bash
git add scripts/bar-test-tohum.sql scripts/bar-test-taban.test.mjs
git commit -m "test(bar): uretim dokumu tabanli izole ortam ve tohum verisi"
```

---

## Aşama 1 — Bar ve PMS güvenliği  ·  ⚠️ GEÇERSİZ (tasarım revizyon 3) — uygulanmaz

### Task 1.1: Önce — kusurların mevcut kodda kanıtı (kırmızı testler)

**Files:**
- Create: `scripts/bar-a1-guvenlik.test.mjs` (bu görevde yalnız "ÖNCE" bölümü)

**Interfaces:**
- Consumes: `barOrtami`, `hataKodu`; Task 0.2 kimlikleri ve id'leri.

- [ ] **Step 1: Test iskeletini ve "ÖNCE" ölçümlerini yaz**

```js
// scripts/bar-a1-guvenlik.test.mjs
// ===========================================================================
// BAR ASAMA 1 — GUVENLIK TESTLERI (izole, uretime BAGLANMAZ)
// ===========================================================================
// Duzen: (0) aday migration UYGULANMADAN once kusurlar olculur ve gecis verisi
// eski fonksiyonlarla uretilir; (1) migration o verinin ustune uygulanir;
// (2) yeni davranis ve negatif kontroller.
// ===========================================================================
import { setTimeout as bekle } from 'node:timers/promises';
import { barOrtami, hataKodu } from './bar-test-ortam.mjs';

const O = barOrtami({ ad: 'bar-a1' });
let ok = 0, fail = 0;
const sonuc = (g, ad, ek) => { console.log((g ? 'OK   ' : 'FAIL ') + ad + (ek ? ' — ' + ek : '')); if (g) ok++; else fail++; };

const U = {
  BAR810:  { rol: 'authenticated', sub: '11111111-0000-0000-0000-000000000810' },
  BAR811:  { rol: 'authenticated', sub: '11111111-0000-0000-0000-000000000811' },
  PASIF:   { rol: 'authenticated', sub: '11111111-0000-0000-0000-0000000000aa' },
  GORUNTU: { rol: 'authenticated', sub: '11111111-0000-0000-0000-0000000000bb' },
  DEPO810: { rol: 'authenticated', sub: '11111111-0000-0000-0000-0000000000cc' },
  QR:      { rol: 'service_role' },
  ANON:    { rol: 'anon' },
};
const M = {
  bira: '22222222-0000-0000-0000-000000000001', viski: '22222222-0000-0000-0000-000000000002',
  limonata: '22222222-0000-0000-0000-000000000003', bira811: '22222222-0000-0000-0000-000000000811',
};
const DEPO = '810_CSM302';
const FOLYO_101 = '55555555-0000-0000-0000-000000000101';
const REZ_101 = '88888888-0000-0000-0000-000000000101';

const tek = (q) => O.sql(q).out;
const rpc = (k, cagri) => O.kimlikle(k, `select ${cagri};`);
function olustur(k, kalemler, oda = null, otel = '810', depo = DEPO) {
  const odaSql = oda === null ? 'null' : `'${oda}'`;
  return O.kimlikle(k, `select public.bar_siparis_olustur('${otel}','${depo}','Masa 1',${odaSql},'${JSON.stringify(kalemler)}'::jsonb);`);
}
const ilerlet = (k, id, durum) => rpc(k, `public.bar_siparis_durum_guncelle('${id}','${durum}')`);
function hazirla(k, id) { ilerlet(k, id, 'hazirlaniyor'); return ilerlet(k, id, 'hazir'); }

try {
  await O.kur({ onceki: ['docs/kurulum/2026-09-14-stok-liste-ozet.sql'] });

  // ---- 0) ONCE: kusurlarin mevcut uretim kodunda kaniti ---------------------
  {
    const a = olustur(U.BAR810, [{ menu_urun_id: M.viski, adet: 1 }], null);
    sonuc(a.ok, 'ONCE: oda no OLMADAN ucretli siparis olusuyordu (kusur kaniti)', a.ok ? 'olustu' : a.err.slice(-120));

    const b = olustur(U.BAR810, [{ menu_urun_id: M.bira, adet: 8 }]);
    const c = rpc(U.DEPO810, `public.stok_ekle('BIRA','${DEPO}','810',-5)`);
    sonuc(b.ok && c.ok, 'ONCE: rezerve edilmis stok baska cikisla tuketilebiliyordu (kusur kaniti)',
      'rezerve 8/10, stok_ekle -5 -> ' + (c.ok ? c.out : 'reddedildi'));

    const d = olustur(U.BAR810, [{ menu_urun_id: M.bira, adet: 1 }], null, '810', '811_RSM301');
    sonuc(d.ok || /Yetersiz stok/.test(d.err), 'ONCE: 810 siparisi 811 deposunu gosterebiliyordu (depo-otel kontrolu yok)',
      d.ok ? 'olustu' : 'yalniz stok yoklugundan reddedildi');
  }
} catch (e) {
  sonuc(false, 'beklenmeyen hata', e.stack || e.message);
} finally {
  O.temizle();
}
console.log('\nBAR ASAMA 1 SONUC: ' + ok + ' OK / ' + fail + ' FAIL');
process.exit(fail ? 1 : 0);
```

- [ ] **Step 2: Çalıştır — kusurlar ölçülmeli**

Run: `node scripts/bar-a1-guvenlik.test.mjs; echo "kod=$?"`
Expected: üç `OK ONCE: …` satırı. Herhangi biri FAIL ise kusur üretim kodunda **yoktur**; tasarımın ilgili maddesi durdurulur ve kullanıcıya raporlanır.

- [ ] **Step 3: Commit**

```bash
git add scripts/bar-a1-guvenlik.test.mjs
git commit -m "test(bar): asama 1 oncesi kusurlarin uretim kodunda olcumu"
```

### Task 1.2: Aday migration — şema, tüketim kaydı, kilit ve stok çıkış koruması

**Files:**
- Create: `docs/kurulum/2026-09-17-bar-a1-guvenlik.sql` (bu görevde 1–4. bölümler)

**Interfaces:**
- Produces:
  - `bar_siparis_kalemleri.birim_fiyat numeric(12,2) not null`, `.ucretli boolean not null`
  - `bar_siparisleri.kanal text` (`qr|personel|gecis`), `.oda_onay_durumu text` (`gerekmiyor|bekliyor|onaylandi|reddedildi|gecis`), `.rezervasyon_id uuid`, `.folio_id uuid`, `.oda_onaylayan uuid`, `.oda_onay_zamani timestamptz`, `.iptal_nedeni text`
  - tablo `bar_ayarlari(bar_depo_id text pk, otel_id otel_id, gun_sonu_saati time default '06:00')`
  - tablo `bar_stok_tuketimleri(...)` (spec 1.3)
  - `bar_operasyon_gunu(p_bar_depo_id text, p_zaman timestamptz) returns date`
  - `_stok_kilitle(p_depo_kodu text, p_stok_kodu text) returns void` (iç)
  - `stok_cikis_korumasi(p_depo_kodu text, p_stok_kodu text, p_cikis numeric) returns void`
  - `stok_ekle(...)`, `stok_transfer(...)` — imza aynı, koruma eklenmiş

- [ ] **Step 1: Migration dosyasının 1–4. bölümlerini yaz**

```sql
-- ============================================================================
-- BAR ASAMA 1 — GUVENLIK (fiyat, oda onayi, tekil teslim, kilit, otel, pasif)
-- Tarih: 2026-09-17
-- ============================================================================
-- ###########################################################################
-- # URETIME UYGULANMADI. `CANLIYA UYGULA` onayi olmadan calistirilmaz.      #
-- # ADAY migration; yalniz izole ortamda dogrulandi.                        #
-- ###########################################################################
-- Tasarim: docs/superpowers/specs/2026-09-17-bar-guvenlik-ikmal-kabul-design.md
-- Geri alma: docs/kurulum/2026-09-17-bar-a1-guvenlik-geri-al.sql
-- ============================================================================

begin;

-- ---------------------------------------------------------------------------
-- 1) FIYAT ANLIK GORUNTUSU (kalem)
-- ---------------------------------------------------------------------------
alter table public.bar_siparis_kalemleri
  add column if not exists birim_fiyat numeric(12,2),
  add column if not exists ucretli boolean;

-- Gecis: tarihsel fiyat bilinmez; urunun SU ANKI fiyati ve bayragi yazilir.
update public.bar_siparis_kalemleri k
   set birim_fiyat = coalesce(m.fiyat, 0),
       ucretli = m.ucretli
  from public.menu_urunler m
 where m.id = k.menu_urun_id
   and (k.birim_fiyat is null or k.ucretli is null);

alter table public.bar_siparis_kalemleri
  alter column birim_fiyat set not null,
  alter column ucretli set not null,
  add constraint bar_siparis_kalemleri_fiyat_negatif_degil check (birim_fiyat >= 0);

-- ---------------------------------------------------------------------------
-- 2) SIPARIS: kanal, oda onayi, bagli konaklama, iptal nedeni
-- ---------------------------------------------------------------------------
alter table public.bar_siparisleri
  add column if not exists kanal text,
  add column if not exists oda_onay_durumu text,
  add column if not exists rezervasyon_id uuid references public.pms_rezervasyonlar(id),
  add column if not exists folio_id uuid references public.pms_folyolar(id),
  add column if not exists oda_onaylayan uuid,
  add column if not exists oda_onay_zamani timestamptz,
  add column if not exists iptal_nedeni text;

-- Gecis: kanal bilinmez. Acik ve ucretli kalemi olan siparis ONAY BEKLER;
-- kapanmis siparisler 'gecis' olarak isaretlenir (folyoya yeniden dokunulmaz).
update public.bar_siparisleri s
   set kanal = 'gecis',
       oda_onay_durumu = case
         when s.durum in ('teslim_edildi', 'iptal') then 'gecis'
         when exists (select 1 from public.bar_siparis_kalemleri k
                       where k.siparis_id = s.id and k.ucretli) then 'bekliyor'
         else 'gerekmiyor'
       end
 where s.kanal is null;

alter table public.bar_siparisleri
  alter column kanal set not null,
  alter column oda_onay_durumu set not null,
  add constraint bar_siparisleri_kanal_chk
    check (kanal in ('qr', 'personel', 'gecis')),
  add constraint bar_siparisleri_oda_onay_chk
    check (oda_onay_durumu in ('gerekmiyor', 'bekliyor', 'onaylandi', 'reddedildi', 'gecis')),
  add constraint bar_siparisleri_onay_bag_chk
    check (oda_onay_durumu <> 'onaylandi'
           or (rezervasyon_id is not null and folio_id is not null
               and oda_onaylayan is not null and oda_onay_zamani is not null));

-- ---------------------------------------------------------------------------
-- 3) BAR AYARLARI, OPERASYON GUNU, TUKETIM KAYDI
-- ---------------------------------------------------------------------------
create table if not exists public.bar_ayarlari (
  bar_depo_id text primary key,
  otel_id public.otel_id not null,
  gun_sonu_saati time not null default '06:00',
  constraint bar_ayarlari_depo_otel check (split_part(bar_depo_id, '_', 1) = otel_id::text)
);
alter table public.bar_ayarlari enable row level security;
drop policy if exists bar_ayarlari_select on public.bar_ayarlari;
create policy bar_ayarlari_select on public.bar_ayarlari for select to authenticated
  using (public.auth_yetki_var('bar_siparis_yonetimi', 'goruntule')
         and public.auth_otel_erisim(otel_id::text));
revoke all on public.bar_ayarlari from public, anon;
grant select on public.bar_ayarlari to authenticated;
grant all on public.bar_ayarlari to service_role;

create or replace function public.bar_operasyon_gunu(p_bar_depo_id text, p_zaman timestamptz)
returns date
language sql stable security definer
set search_path to 'pg_catalog', 'public', 'pg_temp'
as $$
  select ((p_zaman at time zone 'Europe/Istanbul')
          - coalesce((select a.gun_sonu_saati from public.bar_ayarlari a
                       where a.bar_depo_id = p_bar_depo_id), time '06:00')::interval
         )::date;
$$;
revoke all on function public.bar_operasyon_gunu(text, timestamptz) from public, anon;
grant execute on function public.bar_operasyon_gunu(text, timestamptz) to authenticated, service_role;

create table if not exists public.bar_stok_tuketimleri (
  id uuid primary key default gen_random_uuid(),
  otel_id public.otel_id not null,
  bar_depo_id text not null,
  siparis_id uuid not null references public.bar_siparisleri(id),
  siparis_kalem_id uuid not null references public.bar_siparis_kalemleri(id),
  rezervasyon_id uuid not null unique references public.stok_rezervasyonlari(id),
  stok_kodu text not null,
  miktar numeric(12,3) not null check (miktar > 0),
  tur text not null check (tur in ('satis', 'zayi')),
  operasyon_gunu date not null,
  zaman timestamptz not null default now(),
  personel uuid
);
create index if not exists bar_stok_tuketimleri_gun_idx
  on public.bar_stok_tuketimleri (bar_depo_id, operasyon_gunu, tur);
alter table public.bar_stok_tuketimleri enable row level security;
drop policy if exists bar_tuketim_select on public.bar_stok_tuketimleri;
create policy bar_tuketim_select on public.bar_stok_tuketimleri for select to authenticated
  using (public.auth_yetki_var('bar_siparis_yonetimi', 'goruntule')
         and public.auth_otel_erisim(otel_id::text));
revoke all on public.bar_stok_tuketimleri from public, anon;
grant select on public.bar_stok_tuketimleri to authenticated;
grant all on public.bar_stok_tuketimleri to service_role;

-- ---------------------------------------------------------------------------
-- 4) KILIT VE STOK CIKIS KORUMASI
-- ---------------------------------------------------------------------------
-- Tek anahtar sozlesmesi: 'stok:<depo>:<stok_kodu>'. Rezervasyon, teslim,
-- iptal-tuketim ve TUM stok cikislari ayni kilidi alir.
create or replace function public._stok_kilitle(p_depo_kodu text, p_stok_kodu text)
returns void
language plpgsql security definer
set search_path to 'pg_catalog', 'public', 'pg_temp'
as $$
begin
  perform pg_advisory_xact_lock(hashtextextended('stok:' || p_depo_kodu || ':' || p_stok_kodu, 0));
end;
$$;
revoke all on function public._stok_kilitle(text, text) from public, anon, authenticated, service_role;

-- SECURITY DEFINER ZORUNLU: stok_rezervasyonlari bar yetkisi isteyen RLS'e
-- tabidir. Cagiranin haklariyla calisirsa depo kullanicisi rezervasyonlari
-- GOREMEZ, toplami 0 okur ve koruma sessizce devre disi kalir.
create or replace function public.stok_cikis_korumasi(p_depo_kodu text, p_stok_kodu text, p_cikis numeric)
returns void
language plpgsql security definer
set search_path to 'pg_catalog', 'public', 'pg_temp'
as $$
declare
  v_rezerve numeric;
  v_mevcut numeric;
begin
  if p_cikis is null or p_cikis <= 0 then
    return;
  end if;
  perform public._stok_kilitle(p_depo_kodu, p_stok_kodu);

  select coalesce(sum(r.miktar), 0) into v_rezerve
    from public.stok_rezervasyonlari r
   where r.depo_id = p_depo_kodu and r.stok_kodu = p_stok_kodu and r.durum = 'aktif';
  if v_rezerve = 0 then
    return;   -- rezervasyon yoksa davranis BUGUNKUYLE AYNI
  end if;

  if auth.uid() is not null and not public.auth_otel_erisim(split_part(p_depo_kodu, '_', 1)) then
    raise exception 'OTEL_ERISIMI_YOK: % deposuna erisiminiz yok', p_depo_kodu;
  end if;

  select s.miktar into v_mevcut
    from public.stok s
   where s.urun_kodu = p_stok_kodu and s.depo_kodu = p_depo_kodu;
  if coalesce(v_mevcut, 0) - p_cikis < v_rezerve then
    raise exception 'REZERVE_STOK: % / % icin % birim bekleyen bar siparislerine ayrilmis (mevcut %, cikis %)',
      p_depo_kodu, p_stok_kodu, v_rezerve, coalesce(v_mevcut, 0), p_cikis;
  end if;
end;
$$;
revoke all on function public.stok_cikis_korumasi(text, text, numeric) from public, anon;
grant execute on function public.stok_cikis_korumasi(text, text, numeric) to authenticated, service_role;

create or replace function public.stok_ekle(p_urun_kodu text, p_depo_kodu text, p_otel_id text, p_delta numeric)
returns numeric
language plpgsql
set search_path to 'pg_catalog', 'public', 'extensions', 'pg_temp'
as $$
declare
  v_yeni numeric;
begin
  if p_delta < 0 then
    perform public.stok_cikis_korumasi(p_depo_kodu, p_urun_kodu, -p_delta);
  end if;
  insert into stok (urun_kodu, depo_kodu, otel_id, miktar)
  values (p_urun_kodu, p_depo_kodu, p_otel_id::otel_id, greatest(0, p_delta))
  on conflict (urun_kodu, depo_kodu)
  do update set miktar = greatest(0, stok.miktar + p_delta),
                guncelleme_tarihi = now()
  returning miktar into v_yeni;
  return v_yeni;
end;
$$;

create or replace function public.stok_transfer(p_urun_kodu text, p_kaynak_depo text, p_hedef_depo text, p_hedef_otel text, p_miktar numeric)
returns void
language plpgsql
set search_path to 'pg_catalog', 'public', 'extensions', 'pg_temp'
as $$
begin
  perform public.stok_cikis_korumasi(p_kaynak_depo, p_urun_kodu, p_miktar);
  update stok set miktar = greatest(0, miktar - p_miktar),
                  guncelleme_tarihi = now()
    where urun_kodu = p_urun_kodu and depo_kodu = p_kaynak_depo;
  insert into stok (urun_kodu, depo_kodu, otel_id, miktar)
    values (p_urun_kodu, p_hedef_depo, p_hedef_otel::otel_id, p_miktar)
    on conflict (urun_kodu, depo_kodu)
    do update set miktar = greatest(0, stok.miktar + p_miktar),
                  guncelleme_tarihi = now();
end;
$$;
```

> **`guncelleme_tarihi = now()` neden burada:** 2026-09-17 ölçümü, üretimdeki
> `stok_ekle`/`stok_transfer`'in bu sütunu hiçbir UPDATE yolunda yazmadığını
> gösterdi (`docs/kurulum/2026-09-17-stok-guncelleme-tarihi.sql`, aynı tarihli
> teşhis dosyası). A1 bu iki fonksiyonu yeniden tanımladığı için, satır
> eklenmezse o düzeltmeyi **sessizce geri alır** — sırası ne olursa olsun, son
> uygulanan kazanır. Fonksiyonlar `SECURITY INVOKER`: çağıran rollerin
> `stok.guncelleme_tarihi` üzerinde UPDATE yetkisi olmalı (üretimde ölçüldü,
> var). Sıra testi: `scripts/stok-guncelleme-tarihi-bar-sira.test.mjs`.

- [ ] **Step 2: Dosyanın geçici olarak `commit;` ile kapanıp tabana uygulandığını doğrula**

Run:
```bash
node -e "
import('./scripts/bar-test-ortam.mjs').then(async ({barOrtami})=>{
  const fs=await import('node:fs');
  const O=barOrtami({ad:'bar-a1-sema'});
  try{
    await O.kur({onceki:['docs/kurulum/2026-09-14-stok-liste-ozet.sql']});
    const govde=fs.readFileSync('docs/kurulum/2026-09-17-bar-a1-guvenlik.sql','utf8')+'\ncommit;\n';
    const r=O.sql(govde);
    console.log(r.ok?'UYGULANDI':'HATA\n'+r.err.slice(-600));
    process.exitCode=r.ok?0:1;
  }finally{O.temizle();}
});"; echo "kod=$?"
```
Expected: `UYGULANDI`, `kod=0`.

- [ ] **Step 3: Commit**

```bash
git add docs/kurulum/2026-09-17-bar-a1-guvenlik.sql
git commit -m "feat(bar): A1 aday migration — fiyat anlik goruntusu, oda onayi sutunlari, tuketim kaydi, stok cikis korumasi"
```

### Task 1.3: Aday migration — sipariş, onay, teslim, iptal, folyo köprüsü, masa kapsamı

**Files:**
- Modify: `docs/kurulum/2026-09-17-bar-a1-guvenlik.sql` (5–9. bölümler ve doğrulama bloğu eklenir, dosya `commit;` ile biter)

**Interfaces:**
- Consumes: Task 1.2 nesneleri.
- Produces:
  - `_bar_guncel_konaklama(p_otel text, p_oda_no text) returns table(rezervasyon_id uuid, folio_id uuid)` (iç)
  - `bar_siparis_olustur(p_otel_id text, p_depo_id text, p_masa_token text, p_oda_no text, p_kalemler jsonb) returns uuid` — kalem: `{menu_urun_id, adet, gosterilen_fiyat?}`
  - `bar_siparis_durum_guncelle(p_siparis_id uuid, p_durum bar_durum) returns void`
  - `bar_siparis_oda_onayla(p_siparis_id uuid) returns jsonb` → `{sonuc:'onaylandi'|'zaten_onayli', folio_id}`
  - `bar_siparis_oda_reddet(p_siparis_id uuid, p_neden text) returns jsonb`
  - `_bar_rezervasyonlari_tuket(p_siparis_id uuid, p_tur text, p_gun date, p_simdi timestamptz) returns integer` (iç)
  - `_bar_siparis_teslim_uygula(p_siparis_id uuid, p_simdi timestamptz) returns jsonb` (iç)
  - `bar_siparis_teslim_et(p_siparis_id uuid) returns jsonb` → `{sonuc:'teslim_edildi'|'zaten_teslim'}`
  - `_bar_iptal_uygula(p_siparis_id uuid, p_neden text, p_oda_reddi boolean, p_simdi timestamptz) returns jsonb` (iç)
  - `bar_siparis_iptal(p_siparis_id uuid, p_neden text default null) returns jsonb` → `{sonuc:'iptal'|'zaten_iptal', stok:'serbest'|'zayi'}`
  - `pms_bar_folio_koprusu()` tetikleyici gövdesi
  - `bar_masa_yetki_kapsami() returns jsonb` → `{yetkili:boolean, oteller:text[]}`

- [ ] **Step 1: 5–9. bölümleri dosyanın sonuna ekle**

```sql
-- ---------------------------------------------------------------------------
-- 5) GUNCEL KONAKLAMA (tek tanim; siparis, onay ve kopru ayni sorguyu kullanir)
-- ---------------------------------------------------------------------------
-- Oda numarasindan doluluk bilgisi sizdirmamasi icin DISA KAPALI.
create or replace function public._bar_guncel_konaklama(p_otel text, p_oda_no text)
returns table (rezervasyon_id uuid, folio_id uuid)
language sql stable security definer
set search_path to 'pg_catalog', 'public', 'pg_temp'
as $$
  select r.id, f.id
    from public.pms_odalar o
    join public.pms_oda_atamalari a
      on a.oda_id = o.id and a.otel_id = o.otel_id and a.aktif
    join public.pms_rezervasyonlar r
      on r.id = a.rezervasyon_id and r.otel_id = a.otel_id and r.durum = 'giris_yapildi'
    join public.pms_folyolar f
      on f.rezervasyon_id = r.id and f.otel_id = r.otel_id and f.durum = 'acik'
   where o.otel_id::text = p_otel
     and upper(o.oda_no) = upper(btrim(p_oda_no))
   order by f.acilis_zamani
   limit 1;
$$;
revoke all on function public._bar_guncel_konaklama(text, text) from public, anon, authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 6) SIPARIS OLUSTUR — dogrulama, fiyat, oda, kilitli rezervasyon
-- ---------------------------------------------------------------------------
create or replace function public.bar_siparis_olustur(
  p_otel_id text, p_depo_id text, p_masa_token text, p_oda_no text, p_kalemler jsonb
) returns uuid
language plpgsql security definer
set search_path to 'pg_catalog', 'public', 'pg_temp'
as $$
declare
  v_personel boolean := auth.uid() is not null;
  v_siparis_id uuid;
  v_kalem jsonb;
  v_menu public.menu_urunler%rowtype;
  v_kalem_id uuid;
  v_bilesen record;
  v_adet numeric;
  v_gerekli numeric;
  v_musait numeric;
  v_ucretli_var boolean := false;
  v_anahtarlar text[] := array[]::text[];
  v_anahtar text;
  v_rez uuid;
  v_folio uuid;
begin
  -- Kimligi olan cagiran (personel) icin yetki; QR yolunda (service_role)
  -- kullanici yoktur, otel/depo masa token'indan gelir.
  if v_personel then
    if not public.auth_yetki_var('bar_siparis_yonetimi', 'kayit') then
      raise exception 'YETKI_YOK: bar_siparis_yonetimi kayit yetkisi gerekli';
    end if;
    if not public.auth_otel_erisim(p_otel_id) then
      raise exception 'OTEL_ERISIMI_YOK: % oteli icin siparis olusturamazsiniz', p_otel_id;
    end if;
  end if;

  if p_kalemler is null or jsonb_typeof(p_kalemler) <> 'array' or jsonb_array_length(p_kalemler) = 0 then
    raise exception 'BOS_SIPARIS: en az bir kalem gerekli';
  end if;
  if p_otel_id is null or not (p_otel_id = any (enum_range(null::public.otel_id)::text[])) then
    raise exception 'OTEL_GECERSIZ: %', p_otel_id;
  end if;
  if split_part(coalesce(p_depo_id, ''), '_', 1) <> p_otel_id then
    raise exception 'DEPO_OTEL_UYUSMAZ: % deposu % oteline ait degil', p_depo_id, p_otel_id;
  end if;

  -- (A) Dogrula, fiyati karsilastir, kilit anahtarlarini topla — henuz yazma yok.
  for v_kalem in select * from jsonb_array_elements(p_kalemler) loop
    select * into v_menu from public.menu_urunler
     where id = (v_kalem->>'menu_urun_id')::uuid
       and aktif and not silindi and otel_id = p_otel_id::public.otel_id;
    if not found then
      raise exception 'MENU_URUNU_YOK: %', v_kalem->>'menu_urun_id';
    end if;
    v_adet := (v_kalem->>'adet')::numeric;
    if v_adet is null or v_adet <= 0 then
      raise exception 'BOS_SIPARIS: gecersiz adet %', v_kalem->>'adet';
    end if;
    if v_menu.ucretli then
      v_ucretli_var := true;
      if (v_kalem->>'gosterilen_fiyat') is null
         or round((v_kalem->>'gosterilen_fiyat')::numeric, 2) <> coalesce(v_menu.fiyat, 0) then
        raise exception 'FIYAT_DEGISTI: % icin gosterilen % , guncel %',
          v_menu.ad, v_kalem->>'gosterilen_fiyat', coalesce(v_menu.fiyat, 0);
      end if;
    end if;
    if v_menu.tip = 'direkt' then
      if v_menu.stok_kodu is not null then
        v_anahtarlar := v_anahtarlar || v_menu.stok_kodu;
      end if;
    else
      v_anahtarlar := v_anahtarlar || array(
        select b.stok_kodu from public.recete_bilesenleri b where b.menu_urun_id = v_menu.id);
    end if;
  end loop;

  -- (B) Ucretli sepette oda + guncel konaklama SUNUCUDA zorunlu.
  if v_ucretli_var then
    if p_oda_no is null or btrim(p_oda_no) = '' then
      raise exception 'ODA_NO_GEREKLI: ucretli urun icin oda numarasi gerekli';
    end if;
    select k.rezervasyon_id, k.folio_id into v_rez, v_folio
      from public._bar_guncel_konaklama(p_otel_id, p_oda_no) k;
    if v_folio is null then
      raise exception 'KONAKLAMA_YOK: oda % icin aktif konaklama ve acik folyo yok', p_oda_no;
    end if;
  end if;

  -- (C) Kilitler — sirali, tekil (kilitlenme yok).
  for v_anahtar in select distinct x from unnest(v_anahtarlar) x order by 1 loop
    perform public._stok_kilitle(p_depo_id, v_anahtar);
  end loop;

  insert into public.bar_siparisleri
    (otel_id, depo_id, masa_token, oda_no, durum, kanal, oda_onay_durumu,
     rezervasyon_id, folio_id, oda_onaylayan, oda_onay_zamani)
  values
    (p_otel_id::public.otel_id, p_depo_id, p_masa_token,
     case when v_ucretli_var then btrim(p_oda_no) end,
     'yeni',
     case when v_personel then 'personel' else 'qr' end,
     case when not v_ucretli_var then 'gerekmiyor'
          when v_personel then 'onaylandi' else 'bekliyor' end,
     case when v_ucretli_var and v_personel then v_rez end,
     case when v_ucretli_var and v_personel then v_folio end,
     case when v_ucretli_var and v_personel then auth.uid() end,
     case when v_ucretli_var and v_personel then now() end)
  returning id into v_siparis_id;

  -- (D) Kalemler: fiyat anlik goruntusu + kilit altinda yeterlilik + rezervasyon.
  for v_kalem in select * from jsonb_array_elements(p_kalemler) loop
    select * into v_menu from public.menu_urunler
     where id = (v_kalem->>'menu_urun_id')::uuid
       and aktif and not silindi and otel_id = p_otel_id::public.otel_id;
    if not found then
      raise exception 'MENU_URUNU_YOK: %', v_kalem->>'menu_urun_id';
    end if;
    v_adet := (v_kalem->>'adet')::numeric;

    insert into public.bar_siparis_kalemleri
      (siparis_id, menu_urun_id, adet, rezerve_edildi, birim_fiyat, ucretli)
    values (v_siparis_id, v_menu.id, v_adet, false, coalesce(v_menu.fiyat, 0), v_menu.ucretli)
    returning id into v_kalem_id;

    if v_menu.tip = 'direkt' then
      if v_menu.stok_kodu is not null then
        v_gerekli := v_adet * coalesce(v_menu.miktar_per_porsiyon, 1);
        v_musait := public.bar_kullanilabilir_stok(v_menu.stok_kodu, p_depo_id);
        if v_musait < v_gerekli then
          raise exception 'STOK_YETERSIZ: % (gerekli %, musait %)', v_menu.stok_kodu, v_gerekli, v_musait;
        end if;
        insert into public.stok_rezervasyonlari (stok_kodu, otel_id, depo_id, miktar, siparis_kalem_id, durum)
        values (v_menu.stok_kodu, p_otel_id::public.otel_id, p_depo_id, v_gerekli, v_kalem_id, 'aktif');
        update public.bar_siparis_kalemleri set rezerve_edildi = true where id = v_kalem_id;
      end if;
    else
      for v_bilesen in select * from public.recete_bilesenleri
                        where menu_urun_id = v_menu.id order by stok_kodu loop
        v_gerekli := v_adet * v_bilesen.miktar_per_porsiyon;
        v_musait := public.bar_kullanilabilir_stok(v_bilesen.stok_kodu, p_depo_id);
        if v_musait < v_gerekli then
          raise exception 'STOK_YETERSIZ: % (gerekli %, musait %)', v_bilesen.stok_kodu, v_gerekli, v_musait;
        end if;
        insert into public.stok_rezervasyonlari (stok_kodu, otel_id, depo_id, miktar, siparis_kalem_id, durum)
        values (v_bilesen.stok_kodu, p_otel_id::public.otel_id, p_depo_id, v_gerekli, v_kalem_id, 'aktif');
        update public.bar_siparis_kalemleri set rezerve_edildi = true where id = v_kalem_id;
      end loop;
    end if;
  end loop;

  return v_siparis_id;
end;
$$;
revoke all on function public.bar_siparis_olustur(text, text, text, text, jsonb) from public, anon;
grant execute on function public.bar_siparis_olustur(text, text, text, text, jsonb) to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 7) DURUM ILERLETME ve ODA ONAYI
-- ---------------------------------------------------------------------------
create or replace function public.bar_siparis_durum_guncelle(p_siparis_id uuid, p_durum public.bar_durum)
returns void
language plpgsql security definer
set search_path to 'pg_catalog', 'public', 'pg_temp'
as $$
declare
  s public.bar_siparisleri%rowtype;
begin
  if not public.auth_yetki_var('bar_siparis_yonetimi', 'kayit') then
    raise exception 'YETKI_YOK: bar_siparis_yonetimi kayit yetkisi gerekli';
  end if;
  if p_durum not in ('hazirlaniyor', 'hazir') then
    raise exception 'GECERSIZ_DURUM: bu fonksiyon yalniz hazirlaniyor/hazir icin';
  end if;
  select * into s from public.bar_siparisleri where id = p_siparis_id for update;
  if not found then
    raise exception 'SIPARIS_YOK: %', p_siparis_id;
  end if;
  if not public.auth_otel_erisim(s.otel_id::text) then
    raise exception 'OTEL_ERISIMI_YOK: bu siparis sizin otelinize ait degil';
  end if;
  if s.durum = p_durum then
    return;   -- tekrar cagri
  end if;
  if not ((s.durum = 'yeni' and p_durum = 'hazirlaniyor')
       or (s.durum = 'hazirlaniyor' and p_durum = 'hazir')) then
    raise exception 'GECERSIZ_DURUM: % -> %', s.durum, p_durum;
  end if;
  if s.oda_onay_durumu = 'bekliyor' then
    raise exception 'ODA_ONAYI_BEKLIYOR: ucretli siparis oda onayi olmadan hazirlanamaz';
  end if;
  update public.bar_siparisleri set durum = p_durum where id = s.id;
end;
$$;
revoke all on function public.bar_siparis_durum_guncelle(uuid, public.bar_durum) from public, anon;
grant execute on function public.bar_siparis_durum_guncelle(uuid, public.bar_durum) to authenticated, service_role;

create or replace function public.bar_siparis_oda_onayla(p_siparis_id uuid)
returns jsonb
language plpgsql security definer
set search_path to 'pg_catalog', 'public', 'pg_temp'
as $$
declare
  s public.bar_siparisleri%rowtype;
  v_rez uuid;
  v_folio uuid;
begin
  if not public.auth_yetki_var('bar_siparis_yonetimi', 'kayit') then
    raise exception 'YETKI_YOK: bar_siparis_yonetimi kayit yetkisi gerekli';
  end if;
  select * into s from public.bar_siparisleri where id = p_siparis_id for update;
  if not found then
    raise exception 'SIPARIS_YOK: %', p_siparis_id;
  end if;
  if not public.auth_otel_erisim(s.otel_id::text) then
    raise exception 'OTEL_ERISIMI_YOK: bu siparis sizin otelinize ait degil';
  end if;
  if s.oda_onay_durumu = 'onaylandi' then
    return jsonb_build_object('sonuc', 'zaten_onayli', 'folio_id', s.folio_id);
  end if;
  if s.oda_onay_durumu <> 'bekliyor' or s.durum not in ('yeni', 'hazirlaniyor', 'hazir') then
    raise exception 'GECERSIZ_DURUM: oda onayi % / % durumunda verilemez', s.oda_onay_durumu, s.durum;
  end if;
  select k.rezervasyon_id, k.folio_id into v_rez, v_folio
    from public._bar_guncel_konaklama(s.otel_id::text, s.oda_no) k;
  if v_folio is null then
    raise exception 'KONAKLAMA_YOK: oda % icin aktif konaklama ve acik folyo yok', s.oda_no;
  end if;
  update public.bar_siparisleri
     set oda_onay_durumu = 'onaylandi', rezervasyon_id = v_rez, folio_id = v_folio,
         oda_onaylayan = auth.uid(), oda_onay_zamani = now()
   where id = s.id;
  return jsonb_build_object('sonuc', 'onaylandi', 'folio_id', v_folio);
end;
$$;
revoke all on function public.bar_siparis_oda_onayla(uuid) from public, anon;
grant execute on function public.bar_siparis_oda_onayla(uuid) to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 8) TUKETIM, TESLIM, IPTAL
-- ---------------------------------------------------------------------------
create or replace function public._bar_rezervasyonlari_tuket(
  p_siparis_id uuid, p_tur text, p_gun date, p_simdi timestamptz
) returns integer
language plpgsql security definer
set search_path to 'pg_catalog', 'public', 'pg_temp'
as $$
declare
  v_depo text;
  v_anahtar text;
  v_rez record;
  v_yeni numeric;
  v_sayi integer := 0;
begin
  select depo_id into v_depo from public.bar_siparisleri where id = p_siparis_id;
  for v_anahtar in
    select distinct r.stok_kodu
      from public.stok_rezervasyonlari r
      join public.bar_siparis_kalemleri k on k.id = r.siparis_kalem_id
     where k.siparis_id = p_siparis_id and r.durum = 'aktif'
     order by 1
  loop
    perform public._stok_kilitle(v_depo, v_anahtar);
  end loop;

  for v_rez in
    select r.*
      from public.stok_rezervasyonlari r
      join public.bar_siparis_kalemleri k on k.id = r.siparis_kalem_id
     where k.siparis_id = p_siparis_id and r.durum = 'aktif'
     order by r.stok_kodu, r.id
       for update of r
  loop
    update public.stok_rezervasyonlari set durum = 'kullanildi' where id = v_rez.id;

    -- SESSIZ 0'A KIRPMA YOK: rezerve edilen miktar stokta yoksa islem durur.
    update public.stok
       set miktar = miktar - v_rez.miktar, guncelleme_tarihi = p_simdi
     where urun_kodu = v_rez.stok_kodu and depo_kodu = v_rez.depo_id
       and miktar >= v_rez.miktar
    returning miktar into v_yeni;
    if not found then
      raise exception 'STOK_TUTARSIZ: % deposunda % icin % birim yok', v_rez.depo_id, v_rez.stok_kodu, v_rez.miktar;
    end if;

    insert into public.bar_stok_tuketimleri
      (otel_id, bar_depo_id, siparis_id, siparis_kalem_id, rezervasyon_id,
       stok_kodu, miktar, tur, operasyon_gunu, zaman, personel)
    values
      (v_rez.otel_id, v_rez.depo_id, p_siparis_id, v_rez.siparis_kalem_id, v_rez.id,
       v_rez.stok_kodu, v_rez.miktar, p_tur, p_gun, p_simdi, auth.uid());

    insert into public.stok_hareketleri
      (urun_kodu, depo_kodu, otel_id, tip, miktar, belge_no, tarih, aciklama)
    values
      (v_rez.stok_kodu, v_rez.depo_id, v_rez.otel_id, 'cikis', v_rez.miktar,
       'BAR-' || left(p_siparis_id::text, 8), p_simdi,
       case p_tur when 'satis' then 'bar_tuketim: ' else 'bar_zayi: ' end || p_siparis_id);

    v_sayi := v_sayi + 1;
  end loop;
  return v_sayi;
end;
$$;
revoke all on function public._bar_rezervasyonlari_tuket(uuid, text, date, timestamptz)
  from public, anon, authenticated, service_role;

create or replace function public._bar_siparis_teslim_uygula(p_siparis_id uuid, p_simdi timestamptz)
returns jsonb
language plpgsql security definer
set search_path to 'pg_catalog', 'public', 'pg_temp'
as $$
declare
  s public.bar_siparisleri%rowtype;
begin
  if not public.auth_yetki_var('bar_siparis_yonetimi', 'kayit') then
    raise exception 'YETKI_YOK: bar_siparis_yonetimi kayit yetkisi gerekli';
  end if;
  select * into s from public.bar_siparisleri where id = p_siparis_id for update;
  if not found then
    raise exception 'SIPARIS_YOK: %', p_siparis_id;
  end if;
  if not public.auth_otel_erisim(s.otel_id::text) then
    raise exception 'OTEL_ERISIMI_YOK: bu siparis sizin otelinize ait degil';
  end if;
  if s.durum = 'teslim_edildi' then
    return jsonb_build_object('sonuc', 'zaten_teslim');
  end if;
  if s.durum <> 'hazir' then
    raise exception 'GECERSIZ_DURUM: % durumundaki siparis teslim edilemez', s.durum;
  end if;
  if s.oda_onay_durumu = 'bekliyor' then
    raise exception 'ODA_ONAYI_BEKLIYOR: ucretli siparis oda onayi olmadan teslim edilemez';
  end if;

  perform public._bar_rezervasyonlari_tuket(s.id, 'satis', public.bar_operasyon_gunu(s.depo_id, p_simdi), p_simdi);
  update public.bar_siparis_kalemleri set teslim_edildi = true where siparis_id = s.id;
  -- Bu guncelleme folyo koprusunu tetikler; kopru hata verirse HER SEY geri alinir.
  update public.bar_siparisleri set durum = 'teslim_edildi', personel_id = auth.uid() where id = s.id;
  return jsonb_build_object('sonuc', 'teslim_edildi');
end;
$$;
revoke all on function public._bar_siparis_teslim_uygula(uuid, timestamptz)
  from public, anon, authenticated, service_role;

drop function if exists public.bar_siparis_teslim_et(uuid);
create function public.bar_siparis_teslim_et(p_siparis_id uuid)
returns jsonb
language plpgsql security definer
set search_path to 'pg_catalog', 'public', 'pg_temp'
as $$
begin
  return public._bar_siparis_teslim_uygula(p_siparis_id, now());
end;
$$;
revoke all on function public.bar_siparis_teslim_et(uuid) from public, anon;
grant execute on function public.bar_siparis_teslim_et(uuid) to authenticated, service_role;

create or replace function public._bar_iptal_uygula(
  p_siparis_id uuid, p_neden text, p_oda_reddi boolean, p_simdi timestamptz
) returns jsonb
language plpgsql security definer
set search_path to 'pg_catalog', 'public', 'pg_temp'
as $$
declare
  s public.bar_siparisleri%rowtype;
  v_stok text;
begin
  select * into s from public.bar_siparisleri where id = p_siparis_id;
  if s.durum = 'yeni' then
    update public.stok_rezervasyonlari r set durum = 'serbest'
      from public.bar_siparis_kalemleri k
     where k.id = r.siparis_kalem_id and k.siparis_id = s.id and r.durum = 'aktif';
    v_stok := 'serbest';
  elsif s.durum in ('hazirlaniyor', 'hazir') then
    -- Hazirlanan urun TUKETILMISTIR: stok geri verilmez, zayi olarak dusulur.
    perform public._bar_rezervasyonlari_tuket(s.id, 'zayi', public.bar_operasyon_gunu(s.depo_id, p_simdi), p_simdi);
    v_stok := 'zayi';
  else
    raise exception 'GECERSIZ_DURUM: % durumundaki siparis iptal edilemez', s.durum;
  end if;
  update public.bar_siparisleri
     set durum = 'iptal', iptal_nedeni = p_neden,
         oda_onay_durumu = case when p_oda_reddi then 'reddedildi' else oda_onay_durumu end
   where id = s.id;
  return jsonb_build_object('sonuc', 'iptal', 'stok', v_stok);
end;
$$;
revoke all on function public._bar_iptal_uygula(uuid, text, boolean, timestamptz)
  from public, anon, authenticated, service_role;

drop function if exists public.bar_siparis_iptal(uuid);
create function public.bar_siparis_iptal(p_siparis_id uuid, p_neden text default null)
returns jsonb
language plpgsql security definer
set search_path to 'pg_catalog', 'public', 'pg_temp'
as $$
declare
  s public.bar_siparisleri%rowtype;
begin
  if not public.auth_yetki_var('bar_siparis_yonetimi', 'kayit') then
    raise exception 'YETKI_YOK: bar_siparis_yonetimi kayit yetkisi gerekli';
  end if;
  select * into s from public.bar_siparisleri where id = p_siparis_id for update;
  if not found then
    raise exception 'SIPARIS_YOK: %', p_siparis_id;
  end if;
  if not public.auth_otel_erisim(s.otel_id::text) then
    raise exception 'OTEL_ERISIMI_YOK: bu siparis sizin otelinize ait degil';
  end if;
  if s.durum = 'iptal' then
    return jsonb_build_object('sonuc', 'zaten_iptal');
  end if;
  if btrim(coalesce(p_neden, '')) = '' then
    raise exception 'IPTAL_NEDENI_GEREKLI: iptal nedeni yazilmali';
  end if;
  return public._bar_iptal_uygula(s.id, btrim(p_neden), false, now());
end;
$$;
revoke all on function public.bar_siparis_iptal(uuid, text) from public, anon;
grant execute on function public.bar_siparis_iptal(uuid, text) to authenticated, service_role;

create or replace function public.bar_siparis_oda_reddet(p_siparis_id uuid, p_neden text)
returns jsonb
language plpgsql security definer
set search_path to 'pg_catalog', 'public', 'pg_temp'
as $$
declare
  s public.bar_siparisleri%rowtype;
begin
  if not public.auth_yetki_var('bar_siparis_yonetimi', 'kayit') then
    raise exception 'YETKI_YOK: bar_siparis_yonetimi kayit yetkisi gerekli';
  end if;
  select * into s from public.bar_siparisleri where id = p_siparis_id for update;
  if not found then
    raise exception 'SIPARIS_YOK: %', p_siparis_id;
  end if;
  if not public.auth_otel_erisim(s.otel_id::text) then
    raise exception 'OTEL_ERISIMI_YOK: bu siparis sizin otelinize ait degil';
  end if;
  if s.oda_onay_durumu = 'reddedildi' then
    return jsonb_build_object('sonuc', 'zaten_reddedildi');
  end if;
  if s.oda_onay_durumu <> 'bekliyor' then
    raise exception 'GECERSIZ_DURUM: oda onayi % durumunda reddedilemez', s.oda_onay_durumu;
  end if;
  if btrim(coalesce(p_neden, '')) = '' then
    raise exception 'IPTAL_NEDENI_GEREKLI: red nedeni yazilmali';
  end if;
  return public._bar_iptal_uygula(s.id, 'Oda onayi reddedildi: ' || btrim(p_neden), true, now());
end;
$$;
revoke all on function public.bar_siparis_oda_reddet(uuid, text) from public, anon;
grant execute on function public.bar_siparis_oda_reddet(uuid, text) to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 9) FOLYO KOPRUSU (anlik fiyat + onayla baglanan folyo) ve MASA KAPSAMI
-- ---------------------------------------------------------------------------
create or replace function public.pms_bar_folio_koprusu() returns trigger
language plpgsql security definer
set search_path to 'pg_catalog', 'public', 'pg_temp'
as $$
declare
  v_tutar numeric(12,2);
  v_folio public.pms_folyolar%rowtype;
begin
  if not (new.durum = 'teslim_edildi' and old.durum is distinct from 'teslim_edildi') then
    return null;
  end if;

  -- Tutar SIPARISTEKI anlik fiyattan; teslim anindaki menu fiyatindan DEGIL.
  select coalesce(sum(k.adet * k.birim_fiyat), 0) into v_tutar
    from public.bar_siparis_kalemleri k
   where k.siparis_id = new.id and k.ucretli;
  if v_tutar = 0 then
    return null;
  end if;

  if new.oda_onay_durumu <> 'onaylandi' or new.folio_id is null or new.rezervasyon_id is null then
    raise exception 'ODA_ONAYI_BEKLIYOR: ucretli siparis onaylanmis bir oda/folyoya bagli degil';
  end if;

  select f.* into v_folio
    from public.pms_folyolar f
    join public.pms_rezervasyonlar r on r.id = f.rezervasyon_id and r.otel_id = f.otel_id
   where f.id = new.folio_id and r.id = new.rezervasyon_id and f.otel_id = new.otel_id
     and f.durum = 'acik' and r.durum = 'giris_yapildi';
  if not found then
    raise exception 'FOLYO_KAPALI: oda % icin bagli folyo artik acik degil ya da misafir ayrildi', new.oda_no;
  end if;

  insert into public.pms_folio_hareketleri (otel_id, folio_id, tip, aciklama, tutar, kaynak_tip, kaynak_id)
  values (v_folio.otel_id, v_folio.id, 'bar',
          'Bar/restoran siparisi (oda ' || coalesce(new.oda_no, '-') || ')',
          v_tutar, 'bar', new.id)
  on conflict do nothing;   -- ayni siparis iki kez borclandirilamaz
  return null;
end;
$$;

-- rapid-handler (masa/QR) yetki karari: kimlik, AKTIFLIK ve otel kapsami
-- veritabaninda, cagiranin JWT'siyle verilir (Edge Function yerelde sinanamaz).
create or replace function public.bar_masa_yetki_kapsami()
returns jsonb
language sql stable security definer
set search_path to 'pg_catalog', 'public', 'pg_temp'
as $$
  select jsonb_build_object(
    'yetkili', coalesce(public.auth_yetki_var('bar_siparis_yonetimi', 'kayit'), false),
    'oteller', coalesce((
      select jsonb_agg(x.o order by x.o)
        from (select unnest(enum_range(null::public.otel_id))::text as o) x
       where public.auth_yetki_var('bar_siparis_yonetimi', 'kayit')
         and exists (select 1 from public.kullanicilar k
                      where k.auth_user_id = auth.uid() and k.aktif is true
                        and (k.tum_oteller is true or k.otel_id::text = x.o))
    ), '[]'::jsonb));
$$;
revoke all on function public.bar_masa_yetki_kapsami() from public, anon;
grant execute on function public.bar_masa_yetki_kapsami() to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 10) DOGRULAMA — sessiz basari yok
-- ---------------------------------------------------------------------------
do $dogrula$
declare
  v_ad text;
begin
  foreach v_ad in array array[
    'bar_siparis_olustur(text,text,text,text,jsonb)', 'bar_siparis_oda_onayla(uuid)',
    'bar_siparis_oda_reddet(uuid,text)', 'bar_siparis_teslim_et(uuid)',
    'bar_siparis_iptal(uuid,text)', 'bar_masa_yetki_kapsami()',
    'stok_cikis_korumasi(text,text,numeric)'
  ] loop
    if has_function_privilege('anon', 'public.' || v_ad, 'execute') then
      raise exception 'DOGRULAMA: anon % calistirabiliyor', v_ad;
    end if;
    if not has_function_privilege('authenticated', 'public.' || v_ad, 'execute') then
      raise exception 'DOGRULAMA: authenticated % calistiramiyor', v_ad;
    end if;
  end loop;

  foreach v_ad in array array[
    '_stok_kilitle(text,text)', '_bar_guncel_konaklama(text,text)',
    '_bar_rezervasyonlari_tuket(uuid,text,date,timestamptz)',
    '_bar_siparis_teslim_uygula(uuid,timestamptz)', '_bar_iptal_uygula(uuid,text,boolean,timestamptz)'
  ] loop
    if has_function_privilege('authenticated', 'public.' || v_ad, 'execute')
       or has_function_privilege('anon', 'public.' || v_ad, 'execute') then
      raise exception 'DOGRULAMA: ic fonksiyon % disa acik', v_ad;
    end if;
  end loop;

  if exists (select 1 from public.bar_siparis_kalemleri where birim_fiyat is null or ucretli is null) then
    raise exception 'DOGRULAMA: fiyat anlik goruntusu eksik kalem var';
  end if;

  raise notice 'DOGRULAMA (bar A1): tum kontroller gecti.';
end
$dogrula$;

-- Imzasi degisen fonksiyonlar (teslim_et donus tipi, iptal parametresi) icin
-- PostgREST sema onbellegi tazelenir.
notify pgrst, 'reload schema';

commit;
```

- [ ] **Step 2: Tüm dosyanın tabana hatasız uygulandığını doğrula**

Run: `node scripts/bar-test-taban.test.mjs; echo "kod=$?"` sonra Task 1.2 Step 2 komutunu **`+'\ncommit;\n'` eki olmadan** (dosya artık kendi `commit;`'iyle bitiyor) çalıştır.
Expected: `UYGULANDI`, çıktıda `DOGRULAMA (bar A1): tum kontroller gecti.`

- [ ] **Step 3: Commit**

```bash
git add docs/kurulum/2026-09-17-bar-a1-guvenlik.sql
git commit -m "feat(bar): A1 aday migration — dogrulamali siparis, oda onayi, tekil teslim, zayi iptal, folyo koprusu, masa kapsami"
```

### Task 1.4: Aşama 1 veritabanı testleri (geçiş + yeni davranış + negatif kontroller)

**Files:**
- Modify: `scripts/bar-a1-guvenlik.test.mjs` ("ÖNCE" bloğundan sonra, `catch`'ten önce eklenir)

**Interfaces:**
- Consumes: Task 1.3'teki tüm imzalar; Task 0.2 kimlikleri.

- [ ] **Step 1: Geçiş verisini eski fonksiyonlarla üret, migration'ı üstüne uygula**

"ÖNCE" bloğunun hemen ardına ekle:

```js
  // ---- 1) GECIS: eski fonksiyonlarla veri, sonra migration ------------------
  O.sql(`truncate public.stok_rezervasyonlari, public.bar_siparis_kalemleri, public.bar_siparisleri cascade;
         update public.stok set miktar = case urun_kodu when 'BIRA' then (case depo_kodu when '810_100' then 100 else 10 end)
                                                       when 'VISKI' then 2 when 'LIMON' then 50 end;`);
  const eskiAcikUcretli = olustur(U.BAR810, [{ menu_urun_id: M.viski, adet: 1 }], '101').out;
  const eskiTeslim = olustur(U.BAR810, [{ menu_urun_id: M.bira, adet: 1 }]).out;
  hazirla(U.BAR810, eskiTeslim);
  rpc(U.BAR810, `public.bar_siparis_teslim_et('${eskiTeslim}')`);

  const mig = O.uygula('docs/kurulum/2026-09-17-bar-a1-guvenlik.sql');
  sonuc(mig.ok && /tum kontroller gecti/.test(mig.err + mig.out), 'A1 migration MEVCUT veri uzerine uygulandi ve kendi dogrulamasi gecti',
    mig.ok ? '' : mig.err.slice(-300));
  if (!mig.ok) throw new Error('migration uygulanamadi');
  O.sql(`insert into public.bar_ayarlari (bar_depo_id, otel_id) values ('${DEPO}', '810');`);

  sonuc(tek(`select count(*) from public.bar_siparis_kalemleri where birim_fiyat is null or ucretli is null`) === '0',
    'gecis: tum kalemlerde fiyat anlik goruntusu dolu');
  sonuc(tek(`select kanal||'/'||oda_onay_durumu from public.bar_siparisleri where id='${eskiAcikUcretli}'`) === 'gecis/bekliyor',
    'gecis: acik ucretli eski siparis ODA ONAYI BEKLIYOR');
  sonuc(tek(`select kanal||'/'||oda_onay_durumu from public.bar_siparisleri where id='${eskiTeslim}'`) === 'gecis/gecis',
    'gecis: kapanmis eski siparis gecis olarak isaretli, folyoya dokunulmadi');

  const sifirla = () => {
    const r = O.sql(`truncate public.bar_stok_tuketimleri, public.pms_folio_hareketleri, public.stok_rezervasyonlari,
                              public.bar_siparis_kalemleri, public.bar_siparisleri cascade;
                     delete from public.stok_hareketleri;
                     update public.stok set miktar = case urun_kodu when 'BIRA' then (case depo_kodu when '810_100' then 100 else 10 end)
                                                                   when 'VISKI' then 2 when 'LIMON' then 50 end;
                     update public.menu_urunler set fiyat = 250 where id = '${M.viski}';
                     update public.pms_folyolar set durum = 'acik', kapanis_zamani = null where id = '${FOLYO_101}';`);
    if (!r.ok) throw new Error('sifirla: ' + r.err);
  };
  const stok = (kod, depo = DEPO) => tek(`select miktar from public.stok where urun_kodu='${kod}' and depo_kodu='${depo}'`);
  const say = (tablo, kosul = 'true') => tek(`select count(*) from public.${tablo} where ${kosul}`);
```

- [ ] **Step 2: Ücretli sipariş, fiyat, oda onayı ve teslim senaryolarını ekle**

```js
  // ---- 2) UCRETLI SIPARIS: oda, konaklama, fiyat ------------------------------
  {
    sifirla();
    const viski = (fiyat) => [{ menu_urun_id: M.viski, adet: 1, ...(fiyat === undefined ? {} : { gosterilen_fiyat: fiyat }) }];

    let r = olustur(U.QR, viski(250), null);
    sonuc(hataKodu(r) === 'ODA_NO_GEREKLI', 'QR: ucretli sipariste oda no SUNUCUDA zorunlu', hataKodu(r) || 'gecti');
    r = olustur(U.BAR810, viski(250), '  ');
    sonuc(hataKodu(r) === 'ODA_NO_GEREKLI', 'personel: bos oda no reddedildi', hataKodu(r) || 'gecti');
    r = olustur(U.QR, viski(250), '103');
    sonuc(hataKodu(r) === 'KONAKLAMA_YOK', 'bos oda (103) borclandirilamaz', hataKodu(r) || 'gecti');
    r = olustur(U.QR, viski(250), '102');
    sonuc(hataKodu(r) === 'KONAKLAMA_YOK', 'folyosu kapali oda (102) borclandirilamaz', hataKodu(r) || 'gecti');
    r = olustur(U.QR, viski(), '101');
    sonuc(hataKodu(r) === 'FIYAT_DEGISTI', 'gosterilen fiyat yoksa reddedildi', hataKodu(r) || 'gecti');
    r = olustur(U.QR, viski(199), '101');
    sonuc(hataKodu(r) === 'FIYAT_DEGISTI', 'gosterilen fiyat guncelle uyusmazsa reddedildi', hataKodu(r) || 'gecti');
    sonuc(say('bar_siparisleri') === '0' && say('stok_rezervasyonlari') === '0',
      'reddedilen siparisler hic satir ve rezervasyon BIRAKMADI');

    const qr = olustur(U.QR, viski(250), '101');
    const id = qr.out;
    sonuc(qr.ok && tek(`select kanal||'/'||oda_onay_durumu||'/'||coalesce(folio_id::text,'-') from public.bar_siparisleri where id='${id}'`) === 'qr/bekliyor/-',
      'QR ucretli siparis: oda onayi BEKLIYOR, folyo henuz BAGLANMADI');
    sonuc(tek(`select birim_fiyat||'/'||ucretli from public.bar_siparis_kalemleri where siparis_id='${id}'`) === '250.00/true',
      'kalemde onaylanan fiyat anlik goruntusu: 250.00');

    r = ilerlet(U.BAR810, id, 'hazirlaniyor');
    sonuc(hataKodu(r) === 'ODA_ONAYI_BEKLIYOR', 'oda onayi olmadan HAZIRLANAMAZ', hataKodu(r) || 'gecti');

    r = rpc(U.BAR811, `public.bar_siparis_oda_onayla('${id}')`);
    sonuc(hataKodu(r) === 'OTEL_ERISIMI_YOK', '811 personeli 810 siparisini onaylayamaz', hataKodu(r) || 'gecti');
    r = rpc(U.PASIF, `public.bar_siparis_oda_onayla('${id}')`);
    sonuc(hataKodu(r) === 'YETKI_YOK', 'pasif kullanici onaylayamaz', hataKodu(r) || 'gecti');
    r = rpc(U.GORUNTU, `public.bar_siparis_oda_onayla('${id}')`);
    sonuc(hataKodu(r) === 'YETKI_YOK', 'yalniz goruntule yetkisi onaylayamaz', hataKodu(r) || 'gecti');

    r = rpc(U.BAR810, `public.bar_siparis_oda_onayla('${id}')`);
    sonuc(r.ok && tek(`select oda_onay_durumu||'/'||folio_id||'/'||oda_onaylayan from public.bar_siparisleri where id='${id}'`)
      === `onaylandi/${FOLYO_101}/${U.BAR810.sub}`, 'personel onayi: folyo baglandi, onaylayan kaydedildi');
    r = rpc(U.BAR810, `public.bar_siparis_oda_onayla('${id}')`);
    sonuc(r.ok && /zaten_onayli/.test(r.out), 'onay tekrar cagrisi: zaten_onayli');

    // Onaydan sonra fiyat degisir; borc ANLIK fiyattan yazilmali.
    O.sql(`update public.menu_urunler set fiyat = 400 where id = '${M.viski}';`);
    hazirla(U.BAR810, id);
    r = rpc(U.BAR810, `public.bar_siparis_teslim_et('${id}')`);
    sonuc(r.ok && /teslim_edildi/.test(r.out), 'teslim edildi', r.ok ? '' : r.err.slice(-200));
    sonuc(tek(`select string_agg(tutar::text, ',') from public.pms_folio_hareketleri where kaynak_id='${id}'`) === '250.00',
      'folyoya ANLIK fiyat yazildi (250), teslim anindaki fiyat (400) DEGIL');
    sonuc(stok('VISKI') === '1.000' && say('bar_stok_tuketimleri', `siparis_id='${id}' and tur='satis'`) === '1',
      'stok dustu (2 -> 1) ve tek satis tuketimi kaydedildi');
    sonuc(say('stok_hareketleri', `aciklama like 'bar_tuketim:%'`) === '1', 'stok hareket gecmisine bar_tuketim yazildi');

    r = rpc(U.BAR810, `public.bar_siparis_teslim_et('${id}')`);
    sonuc(r.ok && /zaten_teslim/.test(r.out)
        && stok('VISKI') === '1.000'
        && say('bar_stok_tuketimleri', `siparis_id='${id}'`) === '1'
        && say('pms_folio_hareketleri', `kaynak_id='${id}'`) === '1',
      'teslim IKINCI kez: zaten_teslim; stok, tuketim ve borc TEKRARLANMADI');
  }

  // ---- 3) PERSONEL KANALI ve FOLYO KAPANMASI ---------------------------------
  {
    sifirla();
    const id = olustur(U.BAR810, [{ menu_urun_id: M.viski, adet: 1, gosterilen_fiyat: 250 }], '101').out;
    sonuc(tek(`select kanal||'/'||oda_onay_durumu||'/'||oda_onaylayan from public.bar_siparisleri where id='${id}'`)
      === `personel/onaylandi/${U.BAR810.sub}`, 'personel ucretli siparisi: siparisi giren personel onaylamis sayilir');

    hazirla(U.BAR810, id);
    O.sql(`update public.pms_folyolar set durum='kapali', kapanis_zamani=now() where id='${FOLYO_101}';`);
    let r = rpc(U.BAR810, `public.bar_siparis_teslim_et('${id}')`);
    sonuc(hataKodu(r) === 'FOLYO_KAPALI'
        && stok('VISKI') === '2.000'  // rezervasyon stoğu DÜŞÜRMEZ; teslim geri alındı
        && say('bar_stok_tuketimleri') === '0'
        && say('pms_folio_hareketleri') === '0'
        && tek(`select durum from public.bar_siparisleri where id='${id}'`) === 'hazir',
      'folyo kapaliyken teslim TUMDEN geri alindi: stok, tuketim, borc ve durum degismedi', hataKodu(r) || 'gecti');

    r = rpc(U.BAR810, `public.bar_siparis_iptal('${id}', null)`);
    sonuc(hataKodu(r) === 'IPTAL_NEDENI_GEREKLI', 'iptal nedeni zorunlu', hataKodu(r) || 'gecti');
    r = rpc(U.BAR810, `public.bar_siparis_iptal('${id}', 'misafir ayrildi')`);
    sonuc(r.ok && /zayi/.test(r.out)
        && stok('VISKI') === '1.000'
        && say('bar_stok_tuketimleri', `siparis_id='${id}' and tur='zayi'`) === '1'
        && say('pms_folio_hareketleri') === '0',
      'hazirlanmis siparisin iptali: stok ZAYI olarak dustu, borc yazilmadi', r.ok ? r.out : r.err.slice(-150));
    r = rpc(U.BAR810, `public.bar_siparis_iptal('${id}', null)`);
    sonuc(r.ok && /zaten_iptal/.test(r.out) && say('bar_stok_tuketimleri') === '1', 'iptal tekrar cagrisi: zaten_iptal, ikinci zayi yok');
  }

  // ---- 4) YENI SIPARIS IPTALI ve ODA REDDI ------------------------------------
  {
    sifirla();
    const a = olustur(U.BAR810, [{ menu_urun_id: M.bira, adet: 3 }]).out;
    let r = rpc(U.BAR810, `public.bar_siparis_iptal('${a}', 'yanlis masa')`);
    sonuc(r.ok && /serbest/.test(r.out) && stok('BIRA') === '10.000' && say('bar_stok_tuketimleri') === '0'
        && say('stok_rezervasyonlari', `durum='serbest'`) === '1',
      'hazirlanmamis siparis iptali: rezervasyon SERBEST, stok ve tuketim yok');

    const b = olustur(U.QR, [{ menu_urun_id: M.viski, adet: 1, gosterilen_fiyat: 250 }], '101').out;
    r = rpc(U.BAR810, `public.bar_siparis_oda_reddet('${b}', 'oda karti uyusmadi')`);
    sonuc(r.ok && tek(`select durum||'/'||oda_onay_durumu from public.bar_siparisleri where id='${b}'`) === 'iptal/reddedildi'
        && say('stok_rezervasyonlari', `durum='aktif'`) === '0',
      'oda reddi: siparis iptal, onay reddedildi, rezervasyon serbest');
  }

  // ---- 5) OTEL IZOLASYONU ve PASIF KULLANICI ---------------------------------
  {
    sifirla();
    let r = olustur(U.BAR810, [{ menu_urun_id: M.bira, adet: 1 }], null, '810', '811_RSM301');
    sonuc(hataKodu(r) === 'DEPO_OTEL_UYUSMAZ', 'personel: 810 siparisi 811 deposunu kullanamaz', hataKodu(r) || 'gecti');
    r = olustur(U.QR, [{ menu_urun_id: M.bira, adet: 1 }], null, '810', '811_RSM301');
    sonuc(hataKodu(r) === 'DEPO_OTEL_UYUSMAZ', 'QR: yanlis token verisi de depo-otel kontrolune takilir', hataKodu(r) || 'gecti');
    r = olustur(U.BAR811, [{ menu_urun_id: M.bira, adet: 1 }]);
    sonuc(hataKodu(r) === 'OTEL_ERISIMI_YOK', '811 personeli 810 adina siparis olusturamaz', hataKodu(r) || 'gecti');
    r = olustur(U.BAR810, [{ menu_urun_id: M.bira811, adet: 1 }]);
    sonuc(hataKodu(r) === 'MENU_URUNU_YOK', '810 siparisine 811 menu urunu girilemez', hataKodu(r) || 'gecti');

    const id = olustur(U.BAR810, [{ menu_urun_id: M.bira, adet: 1 }]).out;
    for (const [ad, cagri] of [
      ['durum', `public.bar_siparis_durum_guncelle('${id}','hazirlaniyor')`],
      ['teslim', `public.bar_siparis_teslim_et('${id}')`],
      ['iptal', `public.bar_siparis_iptal('${id}','x')`],
    ]) {
      r = rpc(U.BAR811, cagri);
      sonuc(hataKodu(r) === 'OTEL_ERISIMI_YOK', `811 personeli 810 siparisinde ${ad} yapamaz`, hataKodu(r) || 'gecti');
    }
    r = olustur(U.PASIF, [{ menu_urun_id: M.bira, adet: 1 }]);
    sonuc(hataKodu(r) === 'YETKI_YOK', 'pasif kullanici siparis olusturamaz', hataKodu(r) || 'gecti');
    r = rpc(U.PASIF, `public.bar_siparis_teslim_et('${id}')`);
    sonuc(hataKodu(r) === 'YETKI_YOK', 'pasif kullanici teslim edemez', hataKodu(r) || 'gecti');
    // Bos tabloda "0 goruyor" kanit degildir: ayni satiri 810 goruyor, 811 gormuyor olmali.
    sonuc(O.kimlikle(U.BAR810, `select count(*) from public.bar_ayarlari;`).out === '1'
        && O.kimlikle(U.BAR811, `select count(*) from public.bar_ayarlari;`).out === '0',
      'bar_ayarlari: 810 personeli kendi satirini goruyor, 811 personeli GORMUYOR');

    const kap = (k) => O.kimlikle(k, `select public.bar_masa_yetki_kapsami();`).out;
    sonuc(kap(U.BAR810) === '{"oteller": ["810"], "yetkili": true}', 'masa kapsami: BAR810 -> yalniz 810', kap(U.BAR810));
    sonuc(kap(U.BAR811) === '{"oteller": ["811"], "yetkili": true}', 'masa kapsami: BAR811 -> yalniz 811', kap(U.BAR811));
    sonuc(kap(U.PASIF) === '{"oteller": [], "yetkili": false}', 'masa kapsami: pasif kullanici -> yetkisiz, otel yok', kap(U.PASIF));
    sonuc(kap(U.GORUNTU) === '{"oteller": [], "yetkili": false}', 'masa kapsami: yalniz goruntule -> yetkisiz', kap(U.GORUNTU));
  }
```

- [ ] **Step 3: Stok çıkış koruması, yarış ve yetki sınırı senaryolarını negatif kontrollerle ekle**

```js
  // ---- 6) DIGER STOK CIKISLARIYLA CAKISMA ------------------------------------
  {
    sifirla();
    olustur(U.BAR810, [{ menu_urun_id: M.bira, adet: 8 }]);
    // Z1 on kosulu: rezervasyon GERCEKTEN var, ama depo kullanicisi (bar yetkisi yok)
    // onu RLS yuzunden GOREMIYOR. Koruma asagida yine calisiyorsa SECURITY DEFINER
    // gerekliligi kanitlanmis olur. Bu bolum ayni zamanda Z2'nin (sayim da stok_ekle
    // negatif delta ile yazar) olcumudur.
    const gercekRez = tek(`select count(*) from public.stok_rezervasyonlari where durum='aktif'`);
    const depoGorur = O.kimlikle(U.DEPO810, `select count(*) from public.stok_rezervasyonlari;`);
    sonuc(gercekRez === '1' && depoGorur.ok && depoGorur.out === '0',
      'on kosul (Z1): aktif rezervasyon var, depo kullanicisi onu GOREMIYOR', `gercek ${gercekRez}, depo goruyor ${depoGorur.out || depoGorur.err}`);
    let r = rpc(U.DEPO810, `public.stok_ekle('BIRA','${DEPO}','810',-5)`);
    sonuc(hataKodu(r) === 'REZERVE_STOK' && stok('BIRA') === '10.000',
      'stok takip cikisi rezerve stoga INEMIYOR (depo kullanicisi rezervasyonu goremese bile)', hataKodu(r) || 'gecti');
    r = rpc(U.DEPO810, `public.stok_ekle('BIRA','${DEPO}','810',-2)`);
    sonuc(r.ok && r.out === '8.000', 'rezervasyonu asmayan cikis serbest (10 -> 8, rezerve 8)', r.out || r.err.slice(-120));
    r = rpc(U.DEPO810, `public.stok_transfer('BIRA','${DEPO}','810_100','810',1)`);
    sonuc(hataKodu(r) === 'REZERVE_STOK', 'transfer de rezerve stoga inemiyor', hataKodu(r) || 'gecti');
    r = rpc(U.DEPO810, `public.stok_ekle('BIRA','810_100','810',-150)`);
    sonuc(r.ok && r.out === '0.000', 'rezervasyonsuz depoda davranis AYNI (0a kirpma korundu)', r.out || r.err.slice(-120));
    r = rpc(U.DEPO810, `public.stok_ekle('BIRA','${DEPO}','810',3)`);
    sonuc(r.ok && r.out === '11.000', 'giris (pozitif delta) korumaya takilmaz', r.out || r.err.slice(-120));

    const id = tek(`select id from public.bar_siparisleri limit 1`);
    hazirla(U.BAR810, id);
    r = rpc(U.BAR810, `public.bar_siparis_teslim_et('${id}')`);
    sonuc(r.ok && stok('BIRA') === '3.000', 'teslim KENDI rezervasyonunu tuketirken korumaya takilmaz (11 -> 3)', r.ok ? '' : r.err.slice(-150));

    // Negatif kontrol: koruma devre disi -> ayni cikis gecmeli (test gercekten korumayi olcuyor mu?)
    olustur(U.BAR810, [{ menu_urun_id: M.bira, adet: 3 }]);
    const orj = tek(`select pg_get_functiondef('public.stok_cikis_korumasi(text,text,numeric)'::regprocedure)`);
    O.sql(`create or replace function public.stok_cikis_korumasi(p_depo_kodu text, p_stok_kodu text, p_cikis numeric)
           returns void language plpgsql security definer as $f$ begin null; end $f$;`);
    r = rpc(U.DEPO810, `public.stok_ekle('BIRA','${DEPO}','810',-2)`);
    sonuc(r.ok, 'NEGATIF KONTROL: koruma kaldirilinca rezerve stok yine tuketilebiliyor', r.ok ? 'gecti (beklenen)' : hataKodu(r));
    O.sql(orj);
  }

  // ---- 7) REZERVASYON YARISI --------------------------------------------------
  {
    const yaris = async () => {
      sifirla();
      const govde = `select public.bar_siparis_olustur('810','${DEPO}','Masa Y',null,'[{"menu_urun_id":"${M.bira}","adet":6}]'::jsonb);\nselect pg_sleep(1.5);`;
      const a = O.paralel(U.BAR810, govde);
      await bekle(300);
      const b = O.paralel(U.BAR810, govde);
      const sonuclar = await Promise.all([a, b]);
      return {
        basarili: sonuclar.filter((x) => x.ok).length,
        rezerve: Number(tek(`select coalesce(sum(miktar),0) from public.stok_rezervasyonlari where stok_kodu='BIRA' and depo_id='${DEPO}' and durum='aktif'`)),
        kodlar: sonuclar.map((x) => hataKodu(x) || 'ok').join(','),
      };
    };
    const y = await yaris();
    sonuc(y.basarili === 1 && y.rezerve === 6, 'yaris: 10 birime ayni anda 6+6 -> YALNIZ BIRI gecti', `basarili ${y.basarili}, aktif rezerve ${y.rezerve}/10 (${y.kodlar})`);

    const orj = tek(`select pg_get_functiondef('public._stok_kilitle(text,text)'::regprocedure)`);
    O.sql(`create or replace function public._stok_kilitle(p_depo_kodu text, p_stok_kodu text)
           returns void language plpgsql security definer as $f$ begin null; end $f$;`);
    const n = await yaris();
    sonuc(n.basarili === 2 && n.rezerve === 12, 'NEGATIF KONTROL: kilit kaldirilinca IKISI de gecti (asiri rezervasyon)', `basarili ${n.basarili}, aktif rezerve ${n.rezerve}/10`);
    O.sql(orj);
    O.sql(`revoke all on function public._stok_kilitle(text,text) from public, anon, authenticated, service_role;`);
  }

  // ---- 8) YETKI SINIRI -------------------------------------------------------
  {
    const reddedildi = (r) => !r.ok && /permission denied/.test(r.err);
    sonuc(reddedildi(O.kimlikle(U.ANON, `select public.bar_siparis_oda_onayla('00000000-0000-0000-0000-000000000000');`))
        && reddedildi(O.kimlikle(U.ANON, `select public.bar_masa_yetki_kapsami();`))
        && reddedildi(O.kimlikle(U.ANON, `select public.stok_cikis_korumasi('${DEPO}','BIRA',1);`)),
      'anon yeni dis fonksiyonlara ERISEMIYOR');
    sonuc(reddedildi(O.kimlikle(U.BAR810, `select public._bar_siparis_teslim_uygula('00000000-0000-0000-0000-000000000000', now());`))
        && reddedildi(O.kimlikle(U.BAR810, `select public._stok_kilitle('${DEPO}','BIRA');`))
        && reddedildi(O.kimlikle(U.QR, `select public._bar_guncel_konaklama('810','101');`)),
      'authenticated ve service_role ic fonksiyonlara ERISEMIYOR (oda dolulugu sizmaz)');
  }
```

- [ ] **Step 4: Çalıştır**

Run: `node scripts/bar-a1-guvenlik.test.mjs; echo "kod=$?"`
Expected: son satır `BAR ASAMA 1 SONUC: N OK / 0 FAIL`, `kod=0`. FAIL varsa migration düzeltilir; **test beklentisi gevşetilmez**.

- [ ] **Step 5: Commit**

```bash
git add scripts/bar-a1-guvenlik.test.mjs
git commit -m "test(bar): asama 1 — gecis, oda onayi, anlik fiyat, tekil teslim, zayi, otel/pasif, rezerve korumasi, yaris + negatif kontroller"
```

### Task 1.5: Geri alma dosyası (üretilmiş) ve testi

**Files:**
- Create: `scripts/bar-a1-geri-al-uret.mjs`
- Create: `docs/kurulum/2026-09-17-bar-a1-guvenlik-geri-al.sql` (betik üretir)
- Create: `scripts/bar-a1-geri-al.test.mjs`

- [ ] **Step 1: Üretici betiği yaz**

```js
// scripts/bar-a1-geri-al-uret.mjs
// Geri alma SQL'ini URETIM DOKUMUNDEKI eski govdelerden birebir uretir.
// Elle kopyalanan eski kod zamanla yalan soyler; kaynak tek: dokum.
import { readFileSync, writeFileSync } from 'node:fs';
import { SEMA_DOKUMU, kok } from './bar-test-ortam.mjs';

const dokum = readFileSync(SEMA_DOKUMU, 'utf8');
function fonksiyon(ad) {
  const m = dokum.match(new RegExp(`^CREATE FUNCTION public\\.${ad}\\([\\s\\S]*?^\\$\\$;`, 'm'));
  if (!m) throw new Error(ad + ' dokumde yok');
  return m[0].replace(/^CREATE FUNCTION/, 'CREATE OR REPLACE FUNCTION');
}
function yetkiler(ad) {
  return dokum.split('\n').filter((l) => new RegExp(`^(GRANT|REVOKE) ALL ON FUNCTION public\\.${ad}\\(`).test(l)).join('\n');
}
const eskiler = ['stok_ekle', 'stok_transfer', 'bar_siparis_olustur', 'bar_siparis_durum_guncelle',
  'bar_siparis_teslim_et', 'bar_siparis_iptal', 'pms_bar_folio_koprusu'];

// GERI ALMA, ILGISIZ BIR DUZELTMEYI GERI ALMAZ.
// Dokumdeki stok_ekle/stok_transfer govdeleri, 2026-09-17 guncelleme_tarihi
// duzeltmesinden ONCEKI hal olabilir. A1 geri alinirken o govdeler aynen
// yazilirsa, A1 ile hicbir ilgisi olmayan tarih duzeltmesi de sessizce
// kaybolur. Cozum: geri alma dosyasi CALISMA ANINDA bakar — duzeltme
// canlidaysa, eski govdeler yazildiktan sonra yeniden uygulanir.
// Kaynak tek yerdir: duzeltmenin kendi migration dosyasi.
const tarihMig = readFileSync(kok + 'docs/kurulum/2026-09-17-stok-guncelleme-tarihi.sql', 'utf8');
const tarihGovdeleri = tarihMig.slice(
  tarihMig.indexOf('create or replace function public.stok_ekle'),
  tarihMig.indexOf('-- 2) ACL')).trim();
if (!/guncelleme_tarihi = now\(\)/.test(tarihGovdeleri)) {
  throw new Error('tarih duzeltmesi govdeleri okunamadi: 2026-09-17-stok-guncelleme-tarihi.sql degismis olabilir');
}
// EXECUTE tek ifade calistirir; iki fonksiyon ayri ayri verilir.
const tarihIfadeleri = tarihGovdeleri.split(/\$function\$;\s*/).filter((p) => p.trim())
  .map((p) => p.trim() + '$function$;');

// Olcum, eski govdeler YAZILMADAN ONCE alinmali: geri yazim sutunu gotururdu
// ve kontrol kendi sonucunu okurdu.
const tarihiOlc = `
-- Tarih duzeltmesi su an canli mi? (eski govdeler yazilmadan ONCE olculur)
create temp table _a1_geri_tarih on commit drop as
select coalesce(bool_and(prosrc ~* 'guncelleme_tarihi'), false) as vardi
  from pg_proc where pronamespace = 'public'::regnamespace
   and proname in ('stok_ekle', 'stok_transfer');
`;
const tarihiKoru = `
-- 2026-09-17 guncelleme_tarihi duzeltmesi canliysa KORUNUR (A1'e ait degildir).
do $tarih$
begin
  if (select vardi from _a1_geri_tarih) then
    raise notice 'Tarih duzeltmesi geri alinmiyor; eski govdelerin uzerine yeniden uygulaniyor.';
${tarihIfadeleri.map((s) => `    execute $ddl$${s}$ddl$;`).join('\n')}
  end if;
end
$tarih$;
`;

const govde = `-- ============================================================================
-- GERI AL: 2026-09-17-bar-a1-guvenlik.sql
-- ============================================================================
-- # URETIME UYGULANMADI. Yalniz A1 uygulanmis ve geri alinmasi gerekiyorsa. #
-- Uretilen dosya: node scripts/bar-a1-geri-al-uret.mjs (kaynak: ${SEMA_DOKUMU.split('/').pop()})
-- VERI KORUNUR: yeni sutunlar, bar_ayarlari ve bar_stok_tuketimleri SILINMEZ;
-- yalniz eski fonksiyonlarin calisabilmesi icin NOT NULL/CHECK gevsetilir.
-- A1 DISI DUZELTMELER KORUNUR: 2026-09-17 guncelleme_tarihi duzeltmesi canliysa
-- eski govdeler yazildiktan sonra yeniden uygulanir (asagida).
-- ============================================================================
begin;
${tarihiOlc}
drop function if exists public.bar_siparis_oda_onayla(uuid);
drop function if exists public.bar_siparis_oda_reddet(uuid, text);
drop function if exists public.bar_masa_yetki_kapsami();
drop function if exists public.bar_siparis_teslim_et(uuid);
drop function if exists public.bar_siparis_iptal(uuid, text);
drop function if exists public._bar_siparis_teslim_uygula(uuid, timestamptz);
drop function if exists public._bar_iptal_uygula(uuid, text, boolean, timestamptz);
drop function if exists public._bar_rezervasyonlari_tuket(uuid, text, date, timestamptz);
drop function if exists public._bar_guncel_konaklama(text, text);

alter table public.bar_siparis_kalemleri
  alter column birim_fiyat drop not null,
  alter column ucretli drop not null;
alter table public.bar_siparisleri
  drop constraint if exists bar_siparisleri_onay_bag_chk,
  alter column kanal drop not null,
  alter column oda_onay_durumu drop not null;

${eskiler.map((ad) => fonksiyon(ad) + '\n\n' + yetkiler(ad)).join('\n\n')}
${tarihiKoru}
drop function if exists public.stok_cikis_korumasi(text, text, numeric);
drop function if exists public._stok_kilitle(text, text);

commit;
`;
writeFileSync(kok + 'docs/kurulum/2026-09-17-bar-a1-guvenlik-geri-al.sql', govde);
console.log('uretildi: docs/kurulum/2026-09-17-bar-a1-guvenlik-geri-al.sql');
```

- [ ] **Step 2: Üret**

Run: `node scripts/bar-a1-geri-al-uret.mjs; echo "kod=$?"`
Expected: `uretildi: …`, `kod=0`; dosyada 7 `CREATE OR REPLACE FUNCTION` ve eşleşen GRANT/REVOKE satırları.

- [ ] **Step 3: Geri alma testini yaz**

```js
// scripts/bar-a1-geri-al.test.mjs — A1 uygulanip geri alininca ESKI davranis doner mi?
import { barOrtami, hataKodu } from './bar-test-ortam.mjs';

const O = barOrtami({ ad: 'bar-a1-geri' });
let ok = 0, fail = 0;
const sonuc = (g, ad, ek) => { console.log((g ? 'OK   ' : 'FAIL ') + ad + (ek ? ' — ' + ek : '')); if (g) ok++; else fail++; };
const BAR810 = { rol: 'authenticated', sub: '11111111-0000-0000-0000-000000000810' };
const DEPO810 = { rol: 'authenticated', sub: '11111111-0000-0000-0000-0000000000cc' };
const VISKI = '22222222-0000-0000-0000-000000000002', BIRA = '22222222-0000-0000-0000-000000000001';

try {
  // Uretimdeki sira: tarih duzeltmesi once, A1 sonra.
  await O.kur({ onceki: ['docs/kurulum/2026-09-14-stok-liste-ozet.sql',
    'docs/kurulum/2026-09-17-stok-guncelleme-tarihi.sql',
    'docs/kurulum/2026-09-17-bar-a1-guvenlik.sql'] });
  O.sql(`insert into public.bar_ayarlari (bar_depo_id, otel_id) values ('810_CSM302','810');`);
  const yeni = O.kimlikle(BAR810, `select public.bar_siparis_olustur('810','810_CSM302','M',null,'[{"menu_urun_id":"${BIRA}","adet":1}]'::jsonb);`).out;
  O.kimlikle(BAR810, `select public.bar_siparis_durum_guncelle('${yeni}','hazirlaniyor'); select public.bar_siparis_durum_guncelle('${yeni}','hazir'); select public.bar_siparis_teslim_et('${yeni}');`);
  const tuketimOnce = O.sql(`select count(*) from public.bar_stok_tuketimleri;`).out;

  const g = O.uygula('docs/kurulum/2026-09-17-bar-a1-guvenlik-geri-al.sql');
  sonuc(g.ok, 'geri alma dosyasi hatasiz uygulandi', g.ok ? '' : g.err.slice(-300));

  const eski = O.kimlikle(BAR810, `select public.bar_siparis_olustur('810','810_CSM302','M',null,'[{"menu_urun_id":"${VISKI}","adet":1}]'::jsonb);`);
  sonuc(eski.ok, 'eski davranis dondu: fiyat/oda olmadan ucretli siparis yine olusuyor', eski.ok ? '' : eski.err.slice(-150));

  const iptal = O.kimlikle(BAR810, `select public.bar_siparis_iptal('${eski.out}');`);
  sonuc(iptal.ok, 'eski bar_siparis_iptal(uuid) imzasi geri geldi', iptal.ok ? '' : iptal.err.slice(-150));

  O.kimlikle(BAR810, `select public.bar_siparis_olustur('810','810_CSM302','M',null,'[{"menu_urun_id":"${BIRA}","adet":8}]'::jsonb);`);
  O.sql(`update public.stok set guncelleme_tarihi = '2026-07-09 07:23:10+00';`);
  const cikis = O.kimlikle(DEPO810, `select public.stok_ekle('BIRA','810_CSM302','810',-5);`);
  sonuc(cikis.ok, 'eski stok_ekle geri geldi (rezerve korumasi yok)', cikis.ok ? cikis.out : hataKodu(cikis));

  // A1 geri alindi; A1'e AIT OLMAYAN tarih duzeltmesi geri ALINMAMALI.
  sonuc(O.sql(`select bool_and(prosrc ~* 'guncelleme_tarihi') from pg_proc
                where pronamespace = 'public'::regnamespace
                  and proname in ('stok_ekle','stok_transfer');`).out === 't',
    'geri alma 2026-09-17 tarih duzeltmesini KORUDU (govdelerde duruyor)');
  sonuc(O.sql(`select count(*) from public.stok
                where urun_kodu = 'BIRA' and depo_kodu = '810_CSM302'
                  and guncelleme_tarihi > '2026-07-10'::timestamptz;`).out === '1',
    'geri alma sonrasi stok_ekle tarihi hala guncelliyor (davranis olarak)');

  sonuc(O.sql(`select count(*) from public.bar_stok_tuketimleri;`).out === tuketimOnce && tuketimOnce === '1',
    'A1 doneminde yazilan tuketim kayitlari KORUNDU');
  sonuc(O.sql(`select count(*) from pg_proc where proname in ('stok_cikis_korumasi','_stok_kilitle','bar_siparis_oda_onayla');`).out === '0',
    'A1 fonksiyonlari kaldirildi');
} catch (e) {
  sonuc(false, 'beklenmeyen hata', e.stack || e.message);
} finally {
  O.temizle();
}
console.log('\nBAR A1 GERI ALMA SONUC: ' + ok + ' OK / ' + fail + ' FAIL');
process.exit(fail ? 1 : 0);
```

- [ ] **Step 4: Çalıştır**

Run: `node scripts/bar-a1-geri-al.test.mjs; echo "kod=$?"`
Expected: `BAR A1 GERI ALMA SONUC: 6 OK / 0 FAIL`, `kod=0`.

- [ ] **Step 5: Commit**

```bash
git add scripts/bar-a1-geri-al-uret.mjs docs/kurulum/2026-09-17-bar-a1-guvenlik-geri-al.sql scripts/bar-a1-geri-al.test.mjs
git commit -m "feat(bar): A1 geri alma dosyasi uretim dokumunden uretiliyor ve testle dogrulaniyor"
```

### Task 1.6: Ekranlar — hata metinleri, fiyat gönderimi, oda onayı, iptal nedeni

**Files:**
- Create: `bar-hata.js`
- Modify: `bar-menu.html` (script etiketleri, `degis`, `gonder`)
- Modify: `bar-garson.html` (script etiketi, `degis`, `gonder`)
- Modify: `bar-siparis-kuyrugu.html` (script etiketi, `render`, `aksiyonButonlari`, `rpcCagir`, `durumGuncelle`, `teslimEt`, `iptalEt`; yeni `odaOnayla`, `odaReddet`)
- Create: `scripts/bar-a1-ekran.test.mjs`

**Interfaces:**
- Produces: `barHataKodu(metin) → string|null`, `barHataMetni(metin) → string` (tarayıcıda global; Node'da `module.exports`).
- Consumes: Task 1.3 RPC imzaları ve hata kodları.

- [ ] **Step 1: Önce ekran testini yaz (kırmızı)**

```js
// scripts/bar-a1-ekran.test.mjs
// Bar ekranlarinin GERCEK betiklerini Node'da calistirir; sunucuya giden yuku
// ve hata davranisini olcer. DOM kasten asgari; olculen sey veri akisi.
import { readFileSync } from 'node:fs';
import vm from 'node:vm';
import { createRequire } from 'node:module';

const require = createRequire(import.meta.url);
const kok = new URL('..', import.meta.url).pathname.replace(/^\/([A-Za-z]:)/, '$1');
let ok = 0, fail = 0;
const sonuc = (g, ad, ek) => { console.log((g ? 'OK   ' : 'FAIL ') + ad + (ek ? ' — ' + ek : '')); if (g) ok++; else fail++; };

// ---- bar-hata.js ------------------------------------------------------------
{
  const { barHataKodu, barHataMetni, BAR_HATA_METINLERI } = require(kok + 'bar-hata.js');
  const pg = '{"code":"P0001","message":"FIYAT_DEGISTI: Viski icin gosterilen 199 , guncel 250"}';
  sonuc(barHataKodu(pg) === 'FIYAT_DEGISTI', 'PostgREST hata govdesinden kod cikiyor', barHataKodu(pg));
  sonuc(barHataMetni(pg) === BAR_HATA_METINLERI.FIYAT_DEGISTI, 'kod Turkce metne cevriliyor');
  sonuc(barHataMetni('beklenmeyen bir sey') === 'beklenmeyen bir sey', 'bilinmeyen hata oldugu gibi (kisaltilmis) gosteriliyor');
  const eksik = ['ODA_NO_GEREKLI', 'KONAKLAMA_YOK', 'FIYAT_DEGISTI', 'DEPO_OTEL_UYUSMAZ', 'ODA_ONAYI_BEKLIYOR', 'FOLYO_KAPALI',
    'GECERSIZ_DURUM', 'STOK_TUTARSIZ', 'STOK_YETERSIZ', 'REZERVE_STOK', 'IPTAL_NEDENI_GEREKLI', 'MENU_URUNU_YOK',
    'BOS_SIPARIS', 'OTEL_GECERSIZ', 'SIPARIS_YOK', 'YETKI_YOK', 'OTEL_ERISIMI_YOK'].filter((k) => !BAR_HATA_METINLERI[k]);
  sonuc(eksik.length === 0, 'A1 migrationindaki her hata kodunun metni var', eksik.join(',') || 'tam');
}

// ---- ortak sahte tarayici ---------------------------------------------------
function tarayici({ html, onYukle = [], arama = '', yanitlar, ek = {} }) {
  const el = new Map();
  const eleman = (id) => {
    if (!el.has(id)) el.set(id, { id, value: '', innerHTML: '', textContent: '', className: '', disabled: false, style: {}, classList: { add() {}, remove() {} } });
    return el.get(id);
  };
  const istekler = [];
  const b = {
    console, setTimeout, clearTimeout, setInterval: () => 0, clearInterval() {}, URLSearchParams, JSON, Promise, Object, Array, String, Number, Math,
    location: { search: arama },
    document: { getElementById: eleman, querySelectorAll: () => [] },
    fetch: async (url, secenek) => {
      istekler.push({ url: String(url), govde: secenek && secenek.body ? JSON.parse(secenek.body) : null });
      const y = yanitlar(String(url), secenek);
      return { ok: y.ok !== false, status: y.status || 200, json: async () => y.json, text: async () => (typeof y.text === 'string' ? y.text : JSON.stringify(y.json)) };
    },
    alert() {}, confirm: () => true, prompt: () => null,
    ...ek,
  };
  b.window = b;
  vm.createContext(b);
  for (const d of onYukle) vm.runInContext(readFileSync(kok + d, 'utf8'), b, { filename: d });
  const m = readFileSync(kok + html, 'utf8').match(/<script>([\s\S]*?)<\/script>\s*<\/body>/);
  vm.runInContext(m[1], b, { filename: html });
  return { b, eleman, istekler, calistir: (k) => vm.runInContext(k, b) };
}
const bekleBos = () => new Promise((r) => setTimeout(r, 20));

// ---- bar-menu.html (musteri) ------------------------------------------------
{
  const menu = [
    { id: 'u-viski', ad: 'Viski', kategori: 'icecek', fiyat: 250, ucretli: true },
    { id: 'u-bira', ad: 'Bira', kategori: 'icecek', fiyat: 0, ucretli: false },
  ];
  let siparisYaniti = { json: { ok: true, siparis_id: 's1' } };
  const t = tarayici({
    html: 'bar-menu.html', onYukle: ['bar-config.js', 'bar-hata.js'], arama: '?t=tok-1',
    yanitlar: (url) => url.includes('masa_oteli_getir') ? { json: '810' }
      : url.includes('menu_urunler') ? { json: menu }
      : siparisYaniti,
  });
  await bekleBos();
  t.calistir(`degis('u-viski',1); degis('u-bira',2);`);
  t.eleman('odaNo').value = '101';
  await t.calistir('gonder()');
  const g = t.istekler.at(-1).govde;
  sonuc(JSON.stringify(g.kalemler) === JSON.stringify([
    { menu_urun_id: 'u-viski', adet: 1, gosterilen_fiyat: 250 }, { menu_urun_id: 'u-bira', adet: 2 }]) && g.oda_no === '101',
    'musteri: ucretli kaleme GORULEN fiyat ekleniyor, ucretsize eklenmiyor', JSON.stringify(g));
  sonuc(/oda/i.test(t.eleman('mesaj').textContent), 'musteri: ucretli siparis sonrasi oda onayi mesaji', t.eleman('mesaj').textContent);

  siparisYaniti = { json: { ok: false, mesaj: 'FIYAT_DEGISTI: Viski icin gosterilen 250 , guncel 300' } };
  const menuIstekOnce = t.istekler.filter((x) => x.url.includes('menu_urunler')).length;
  t.calistir(`degis('u-viski',1);`);
  await t.calistir('gonder()');
  await bekleBos();
  sonuc(t.eleman('mesaj').textContent.includes('Fiyat değişti')
      && t.istekler.filter((x) => x.url.includes('menu_urunler')).length === menuIstekOnce + 1,
    'musteri: FIYAT_DEGISTI -> Turkce mesaj ve menu yeniden yuklendi', t.eleman('mesaj').textContent);
}

// ---- bar-garson.html --------------------------------------------------------
{
  const t = tarayici({
    html: 'bar-garson.html', onYukle: ['bar-config.js', 'bar-hata.js'],
    yanitlar: () => ({ json: 'uuid-1' }),
    ek: {
      SB_URL: 'http://sb', SB_KEY: 'k', requireLogin: () => null, requireRole: () => false, kullaniciYetkileriGetir: async () => ({}),
      oturumAccessTokenGetir: () => 'jwt', sLD() {}, hLD() {}, toast() {}, escapeHtml: (s) => String(s), depoAdi: (s) => s, otelFromDepoId: (s) => String(s).split('_')[0],
    },
  });
  t.calistir(`YETKI_HARITASI={bar_siparis_yonetimi:'kayit'};
    seciliMasa={otel_id:'810',depo_id:'810_CSM302',masa_adi:'Masa 1',token:'t'};
    MENU=[{id:'u-viski',ad:'Viski',fiyat:250,ucretli:true},{id:'u-bira',ad:'Bira',fiyat:0,ucretli:false}];
    render(); degis('u-viski',2); degis('u-bira',1);`);
  t.eleman('odaNo').value = '101';
  await t.calistir('gonder()');
  const g = t.istekler.at(-1).govde;
  sonuc(JSON.stringify(g.p_kalemler) === JSON.stringify([
    { menu_urun_id: 'u-viski', adet: 2, gosterilen_fiyat: 250 }, { menu_urun_id: 'u-bira', adet: 1 }]),
    'garson: ucretli kaleme gorulen fiyat ekleniyor', JSON.stringify(g.p_kalemler));
}

// ---- bar-siparis-kuyrugu.html -----------------------------------------------
{
  let sonMesaj = '';
  let promptYaniti = '';
  const t = tarayici({
    html: 'bar-siparis-kuyrugu.html', onYukle: ['bar-config.js', 'bar-hata.js'],
    yanitlar: (url) => url.includes('bar_siparis_teslim_et')
      ? { ok: false, status: 400, text: '{"message":"FOLYO_KAPALI: oda 101 icin bagli folyo artik acik degil"}' }
      : url.includes('/rest/v1/bar_siparisleri') ? { json: [] }   // islem sonrasi liste yenilemesi
      : { json: { sonuc: 'iptal', stok: 'zayi' } },
    ek: {
      SB_URL: 'http://sb', SB_HEADERS: {}, requireLogin: () => null, requireRole: () => false, kullaniciYetkileriGetir: async () => ({}),
      oturumAccessTokenGetir: () => 'jwt', sLD() {}, hLD() {}, toast: (m) => { sonMesaj = m; }, escapeHtml: (s) => String(s),
      prompt: () => promptYaniti,
    },
  });
  t.calistir(`YETKI_HARITASI={bar_siparis_yonetimi:'kayit'};`);
  const bekleyen = t.calistir(`aksiyonButonlari({id:'s1',durum:'yeni',oda_onay_durumu:'bekliyor'}, true)`);
  sonuc(/odaOnayla\('s1'\)/.test(bekleyen) && /odaReddet\('s1'\)/.test(bekleyen) && !/hazirlaniyor/.test(bekleyen),
    'kuyruk: oda onayi bekleyende Onayla/Reddet var, Hazirlaniyor YOK');
  const hazir = t.calistir(`aksiyonButonlari({id:'s2',durum:'hazir',oda_onay_durumu:'onaylandi'}, true)`);
  sonuc(/teslimEt\('s2'\)/.test(hazir), 'kuyruk: onaylanmis hazir sipariste Teslim Et var');

  promptYaniti = '   ';
  const once = t.istekler.length;
  await t.calistir(`iptalEt('s3','hazir')`);
  sonuc(t.istekler.length === once, 'kuyruk: bos iptal nedeninde sunucuya istek GITMEDI');

  promptYaniti = 'misafir vazgecti';
  await t.calistir(`iptalEt('s3','hazir')`);
  // Son istek liste yenilemesidir; iptal istegi URL'siyle bulunur.
  const iptal = t.istekler.filter((x) => x.url.endsWith('/rpc/bar_siparis_iptal')).at(-1);
  sonuc(iptal.url.endsWith('/rpc/bar_siparis_iptal') && iptal.govde.p_neden === 'misafir vazgecti',
    'kuyruk: iptal nedeni sunucuya gidiyor', JSON.stringify(iptal.govde));

  await t.calistir(`teslimEt('s2')`);
  sonuc(sonMesaj.includes('folyosu kapalı'), 'kuyruk: FOLYO_KAPALI Turkce ve yonlendirici gosteriliyor', sonMesaj);
}

console.log('\nBAR A1 EKRAN SONUC: ' + ok + ' OK / ' + fail + ' FAIL');
process.exit(fail ? 1 : 0);
```

- [ ] **Step 2: Çalıştır — düşmeli**

Run: `node scripts/bar-a1-ekran.test.mjs; echo "kod=$?"`
Expected: `bar-hata.js` bulunamadığı için hata, `kod` ≠ 0.

- [ ] **Step 3: `bar-hata.js` yaz**

```js
// bar-hata.js — Bar RPC ve Edge Function hata kodlarini kullaniciya anlasilir
// metne cevirir. Sunucu hatalari 'KOD: aciklama' bicimindedir (A1 migration).
const BAR_HATA_METINLERI = {
  ODA_NO_GEREKLI: 'Ücretli ürün için oda numarası gerekli.',
  KONAKLAMA_YOK: 'Bu odada şu an konaklayan misafir yok ya da folyosu kapalı. Oda numarasını kontrol edin.',
  FIYAT_DEGISTI: 'Fiyat değişti. Menü yenilendi, lütfen siparişi tekrar gönderin.',
  DEPO_OTEL_UYUSMAZ: 'Bar deposu seçilen otele ait değil.',
  ODA_ONAYI_BEKLIYOR: 'Oda onayı bekleniyor. Önce misafirin oda kartını görüp onaylayın.',
  FOLYO_KAPALI: 'Misafirin folyosu kapalı ya da misafir ayrılmış; ücret yazılamaz. Siparişi iptal edin — hazırlanan ürün zayi olarak düşülür.',
  GECERSIZ_DURUM: 'Sipariş bu durumda bu işleme uygun değil. Listeyi yenileyin.',
  STOK_TUTARSIZ: 'Stok kaydı rezervasyonla uyuşmuyor. Depo sorumlusuna bildirin.',
  STOK_YETERSIZ: 'Stok yetersiz.',
  REZERVE_STOK: 'Bu miktar bekleyen bar siparişlerine ayrılmış. Önce o siparişleri teslim edin ya da iptal edin.',
  IPTAL_NEDENI_GEREKLI: 'İptal nedenini yazın.',
  MENU_URUNU_YOK: 'Menüdeki bir ürün artık satışta değil. Menüyü yenileyin.',
  BOS_SIPARIS: 'Sepet boş ya da adet geçersiz.',
  OTEL_GECERSIZ: 'Otel bilgisi geçersiz.',
  SIPARIS_YOK: 'Sipariş bulunamadı. Listeyi yenileyin.',
  YETKI_YOK: 'Bu işlem için yetkiniz yok.',
  OTEL_ERISIMI_YOK: 'Bu otelin kayıtlarına erişiminiz yok.',
};
function barHataKodu(metin) {
  const m = String(metin || '').match(/\b([A-Z][A-Z_]{3,}):/);
  return m ? m[1] : null;
}
function barHataMetni(metin) {
  const kod = barHataKodu(metin);
  return (kod && BAR_HATA_METINLERI[kod]) || String(metin || 'Beklenmeyen hata').slice(0, 160);
}
if (typeof module !== 'undefined' && module.exports) {
  module.exports = { BAR_HATA_METINLERI, barHataKodu, barHataMetni };
}
```

- [ ] **Step 4: `bar-menu.html` değişiklikleri**

`<script src="bar-config.js"></script>` satırının altına:
```html
<script src="bar-hata.js"></script>
```

`degis` içinde sepet satırı fiyatı da taşır:
```js
  if(yeni === 0) delete SEPET[id]; else SEPET[id] = { adet: yeni, ucretli: u.ucretli, fiyat: u.fiyat };
```

`gonder` fonksiyonunun tamamı:
```js
async function gonder(){
  // Ucretli kaleme musterinin GORDUGU fiyat eklenir; sunucu guncel fiyatla
  // karsilastirir, uyusmazsa FIYAT_DEGISTI ile reddeder (onaylanan fiyat kaydi).
  const kalemler = Object.entries(SEPET).map(([menu_urun_id, v]) =>
    v.ucretli ? { menu_urun_id, adet: v.adet, gosterilen_fiyat: Number(v.fiyat) } : { menu_urun_id, adet: v.adet });
  const mesaj = document.getElementById('mesaj');
  if(!kalemler.length){ mesaj.className = 'mesaj err'; mesaj.textContent = 'Sepetiniz boş.'; return; }
  const ucretli = ucretliVar();
  const odaNo = document.getElementById('odaNo').value.trim();
  if(ucretli && !odaNo){ mesaj.className = 'mesaj err'; mesaj.textContent = 'Ücretli ürün için oda no zorunlu.'; return; }
  const btn = document.getElementById('gonderBtn'); btn.disabled = true; mesaj.className = 'mesaj'; mesaj.textContent = 'Gönderiliyor…';
  try{
    const r = await fetch(CUSTOMER_SB_URL + SIPARIS_FN, {
      method: 'POST', headers: H,
      body: JSON.stringify({ token, oda_no: ucretli ? odaNo : null, kalemler })
    });
    const d = await r.json();
    if(d.ok){
      mesaj.className = 'mesaj ok';
      mesaj.textContent = ucretli
        ? '✅ Siparişiniz alındı. Ücretli ürünler için personel oda kartınızı kontrol edecek.'
        : '✅ Siparişiniz alındı!';
      SEPET = {}; render();
    } else {
      mesaj.className = 'mesaj err';
      mesaj.textContent = '❌ ' + barHataMetni(d.mesaj);
      const kod = barHataKodu(d.mesaj);
      if(kod === 'FIYAT_DEGISTI' || kod === 'MENU_URUNU_YOK'){ SEPET = {}; await menuYukle(); }
    }
  }catch(e){ mesaj.className = 'mesaj err'; mesaj.textContent = '❌ Bağlantı hatası'; }
  btn.disabled = false;
}
```

- [ ] **Step 5: `bar-garson.html` değişiklikleri**

`<script src="bar-config.js"></script>` satırının altına `<script src="bar-hata.js"></script>`.

`degis` içinde:
```js
  if(yeni===0) delete SEPET[id]; else SEPET[id]={adet:yeni,ucretli:u.ucretli,fiyat:u.fiyat};
```

`gonder` içindeki `kalemler` ve hata satırı:
```js
  const kalemler=Object.entries(SEPET).map(([menu_urun_id,v])=>
    v.ucretli?{menu_urun_id,adet:v.adet,gosterilen_fiyat:Number(v.fiyat)}:{menu_urun_id,adet:v.adet});
```
```js
    if(!r.ok){
      const t=await r.text();
      toast('❌ '+barHataMetni(t));
      const kod=barHataKodu(t);
      if(kod==='FIYAT_DEGISTI'||kod==='MENU_URUNU_YOK'){ SEPET={}; await masaDegisti(); }
      return;
    }
```

- [ ] **Step 6: `bar-siparis-kuyrugu.html` değişiklikleri**

`<script src="bar-config.js"></script>` satırının altına `<script src="bar-hata.js"></script>`.

`render` içinde durum çipinin yanına onay rozeti:
```js
    const onayRozeti=s.oda_onay_durumu==='bekliyor'?'<span class="chip chip-yeni">Oda onayı bekliyor</span>':'';
```
ve `skart-ust` içindeki çipten sonra `${onayRozeti}` eklenir; oda satırı:
```js
    const odaSatiri=s.oda_no?`<div class="oda">🏨 Oda: ${escapeHtml(s.oda_no)}${s.oda_onay_durumu==='onaylandi'?' (onaylı)':''}</div>`:'';
```

`aksiyonButonlari` tamamı:
```js
function aksiyonButonlari(s, yzb){
  if(s.durum==='teslim_edildi'||s.durum==='iptal') return '';
  const dis = yzb?'':'disabled';
  let b='<div class="brow">';
  if(s.oda_onay_durumu==='bekliyor'){
    // Ucretli siparis: misafirin oda karti gorulmeden hazirlik ve teslim YOK.
    b+=`<button class="btn btn-success" ${dis} onclick="odaOnayla('${s.id}')">Odayı Onayla</button>`;
    b+=`<button class="btn btn-danger" ${dis} onclick="odaReddet('${s.id}')">Reddet</button>`;
    return b+'</div>';
  }
  if(s.durum==='yeni') b+=`<button class="btn btn-primary" ${dis} onclick="durumGuncelle('${s.id}','hazirlaniyor')">Hazırlanıyor</button>`;
  if(s.durum==='hazirlaniyor') b+=`<button class="btn btn-info" ${dis} onclick="durumGuncelle('${s.id}','hazir')">Hazır</button>`;
  if(s.durum==='hazir') b+=`<button class="btn btn-success" ${dis} onclick="teslimEt('${s.id}')">Teslim Et</button>`;
  b+=`<button class="btn btn-danger" ${dis} onclick="iptalEt('${s.id}','${s.durum}')">İptal</button>`;
  return b+'</div>';
}
```

`rpcCagir`, `durumGuncelle`, `teslimEt`, `iptalEt` yerine ve yeni iki fonksiyon:
```js
async function rpcCagir(fonksiyon, govde){
  sLD();
  try{
    const r=await fetch(SB_URL+'/rest/v1/rpc/'+fonksiyon,{method:'POST', headers:SB_HEADERS, body:JSON.stringify(govde)});
    const metin=await r.text();
    hLD();
    if(!r.ok){ toast('❌ '+barHataMetni(metin)); return null; }
    try{ return metin?JSON.parse(metin):{}; }catch(e){ return {}; }
  }catch(e){ hLD(); toast('❌ Bağlantı hatası'); return null; }
}

async function durumGuncelle(id, durum){
  if(!yazabilir()){ toast('⚠️ Yetkiniz yok'); return; }
  if(await rpcCagir('bar_siparis_durum_guncelle', {p_siparis_id:id, p_durum:durum})){ toast('✅ '+durum); await yukle(); }
}

async function teslimEt(id){
  if(!yazabilir()){ toast('⚠️ Yetkiniz yok'); return; }
  const d=await rpcCagir('bar_siparis_teslim_et', {p_siparis_id:id});
  if(!d) return;
  toast(d.sonuc==='zaten_teslim'?'ℹ️ Bu sipariş zaten teslim edilmiş':'✅ Teslim edildi — stok düşüldü');
  await yukle();
}

async function iptalEt(id, durum){
  if(!yazabilir()){ toast('⚠️ Yetkiniz yok'); return; }
  const hazirlanmis = durum==='hazirlaniyor'||durum==='hazir';
  const neden=(prompt(hazirlanmis
    ?'İptal nedeni (hazırlanan ürün stoktan ZAYİ olarak düşülecek):'
    :'İptal nedeni (ayrılan stok serbest bırakılacak):')||'').trim();
  if(!neden){ toast('İptal edilmedi — neden yazılmadı'); return; }
  const d=await rpcCagir('bar_siparis_iptal', {p_siparis_id:id, p_neden:neden});
  if(!d) return;
  toast(d.stok==='zayi'?'✅ İptal edildi — hazırlanan ürün zayi olarak düşüldü':'✅ İptal edildi');
  await yukle();
}

async function odaOnayla(id){
  if(!yazabilir()){ toast('⚠️ Yetkiniz yok'); return; }
  if(!confirm('Misafirin oda kartını gördünüz mü? Onaylanınca ücret bu odanın folyosuna yazılacak.')) return;
  const d=await rpcCagir('bar_siparis_oda_onayla', {p_siparis_id:id});
  if(!d) return;
  toast('✅ Oda onaylandı'); await yukle();
}

async function odaReddet(id){
  if(!yazabilir()){ toast('⚠️ Yetkiniz yok'); return; }
  const neden=(prompt('Red nedeni (sipariş iptal edilir, ayrılan stok serbest kalır):')||'').trim();
  if(!neden){ toast('Reddedilmedi — neden yazılmadı'); return; }
  const d=await rpcCagir('bar_siparis_oda_reddet', {p_siparis_id:id, p_neden:neden});
  if(!d) return;
  toast('✅ Oda onayı reddedildi, sipariş iptal edildi'); await yukle();
}
```

- [ ] **Step 7: Çalıştır**

Run: `node scripts/bar-a1-ekran.test.mjs; echo "kod=$?"; node scripts/check.mjs; echo "check=$?"`
Expected: `BAR A1 EKRAN SONUC: 13 OK / 0 FAIL`, `kod=0`, `check=0`.

- [ ] **Step 8: Commit**

```bash
git add bar-hata.js bar-menu.html bar-garson.html bar-siparis-kuyrugu.html scripts/bar-a1-ekran.test.mjs
git commit -m "feat(bar): ekranlar — gorulen fiyat gonderimi, oda onayi/reddi, zorunlu iptal nedeni, Turkce hata kodlari"
```

### Task 1.7: `rapid-handler` — kimlik, aktiflik ve otel kapsamı veritabanından

**Files:**
- Modify: `docs/kurulum/musteri-projesi/masa-yonetim/index.ts` (tamamı)

**Interfaces:**
- Consumes: `bar_masa_yetki_kapsami()` (Task 1.3). İstemci sözleşmesi değişmez: gövde `{jwt, action, …}`; yanıt `{ok, mesaj?, masalar?, masa?}`.
- Secret: `MAIN_ANON_KEY` (müşteri projesinde `smooth-service` için zaten tanımlı; yayında varlığı doğrulanır).

- [ ] **Step 1: Dosyanın tamamını yaz**

```ts
// Supabase Edge Function: masa-yonetim  (CANLI AD: "rapid-handler")
// Personel masa/QR token yonetimi.
//
// GUVENLIK (bar A1, 2026-09-17):
// ONCEKI SURUM kullaniciyi e-postadan bulup yetki_matrisi'ni elle okuyordu:
// kullanicilar.aktif'e bakmiyordu (pasif kullanicinin gecerli JWT'si yetiyordu)
// ve otel kapsami yoktu (bir otelin personeli digerinin masalarini listeleyip
// kapatabiliyordu).
// SIMDI: kimlik ANA projede auth.getUser() ile, yetki + aktiflik + otel kapsami
// bar_masa_yetki_kapsami() RPC'siyle CAGIRANIN JWT'siyle sorulur. Karar
// veritabanindadir ve orada izole testle dogrulanmistir.
//
// Secret: MAIN_SB_URL, MAIN_ANON_KEY, CUSTOMER_SB_URL, CUSTOMER_SERVICE_KEY.
// (MAIN_SERVICE_KEY bu fonksiyonda ARTIK KULLANILMAZ.)

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

Deno.serve(async (req) => {
  const cors = {
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Headers": "authorization, apikey, content-type, x-client-info",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
  };
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ ok: false, mesaj: "POST bekleniyor" }, 405, cors);

  try {
    let body: any;
    try { body = await req.json(); } catch { return json({ ok: false, mesaj: "Geçersiz JSON" }, 400, cors); }
    const { jwt, action } = body ?? {};
    if (action === "ping") return json({ ok: true, v: "a1" }, 200, cors);
    if (!jwt) return json({ ok: false, mesaj: "Oturum yok" }, 401, cors);

    const MAIN_URL = Deno.env.get("MAIN_SB_URL");
    const MAIN_ANON = Deno.env.get("MAIN_ANON_KEY");
    const CUST_URL = Deno.env.get("CUSTOMER_SB_URL");
    const CUST_KEY = Deno.env.get("CUSTOMER_SERVICE_KEY");
    if (!MAIN_URL || !MAIN_ANON || !CUST_URL || !CUST_KEY) {
      return json({ ok: false, mesaj: "Sunucu yapılandırması eksik" }, 500, cors);
    }

    // Cagiranin JWT'siyle calisan istemci: RPC'ler auth.uid() ile karar verir.
    const kullanici = createClient(MAIN_URL, MAIN_ANON, {
      global: { headers: { Authorization: "Bearer " + jwt } },
      auth: { autoRefreshToken: false, persistSession: false },
    });
    const { data: u, error: uErr } = await kullanici.auth.getUser();
    if (uErr || !u?.user) return json({ ok: false, mesaj: "Oturum geçersiz — tekrar giriş yapın" }, 401, cors);

    const { data: kapsam, error: kErr } = await kullanici.rpc("bar_masa_yetki_kapsami");
    if (kErr) return json({ ok: false, mesaj: "Yetki kontrolü başarısız" }, 403, cors);
    if (kapsam?.yetkili !== true) return json({ ok: false, mesaj: "Yetki yok" }, 403, cors);
    const oteller: string[] = Array.isArray(kapsam.oteller) ? kapsam.oteller.map(String) : [];
    if (!oteller.length) return json({ ok: false, mesaj: "Otel erişimi yok" }, 403, cors);

    const cust = createClient(CUST_URL, CUST_KEY);

    if (action === "liste") {
      const { data, error } = await cust.from("masa_tokenlari")
        .select("token,otel_id,depo_id,masa_adi,bolge,aktif")
        .in("otel_id", oteller)
        .order("bolge").order("masa_adi");
      if (error) return json({ ok: false, mesaj: error.message }, 200, cors);
      return json({ ok: true, masalar: data }, 200, cors);
    }

    if (action === "ekle") {
      const { otel_id, depo_id, masa_adi, bolge } = body;
      if (!otel_id || !depo_id || !masa_adi) return json({ ok: false, mesaj: "otel/depo/masa adı zorunlu" }, 400, cors);
      if (!oteller.includes(String(otel_id))) return json({ ok: false, mesaj: "Bu otel için masa ekleyemezsiniz" }, 403, cors);
      if (String(depo_id).split("_")[0] !== String(otel_id)) {
        return json({ ok: false, mesaj: "DEPO_OTEL_UYUSMAZ: depo seçilen otele ait değil" }, 400, cors);
      }
      const token = crypto.randomUUID();
      const { data, error } = await cust.from("masa_tokenlari")
        .insert({ token, otel_id, depo_id, masa_adi, bolge: bolge || null, aktif: true })
        .select().single();
      if (error) return json({ ok: false, mesaj: error.message }, 200, cors);
      return json({ ok: true, masa: data }, 200, cors);
    }

    if (action === "durum") {
      const { token, aktif } = body;
      if (!token || typeof aktif !== "boolean") return json({ ok: false, mesaj: "token/aktif zorunlu" }, 400, cors);
      const { data: masa, error: mErr } = await cust.from("masa_tokenlari").select("otel_id").eq("token", token).maybeSingle();
      if (mErr) return json({ ok: false, mesaj: mErr.message }, 200, cors);
      if (!masa) return json({ ok: false, mesaj: "Masa bulunamadı" }, 404, cors);
      if (!oteller.includes(String(masa.otel_id))) return json({ ok: false, mesaj: "Bu otelin masasını değiştiremezsiniz" }, 403, cors);
      const { error } = await cust.from("masa_tokenlari").update({ aktif }).eq("token", token);
      if (error) return json({ ok: false, mesaj: error.message }, 200, cors);
      return json({ ok: true }, 200, cors);
    }

    return json({ ok: false, mesaj: "Bilinmeyen aksiyon" }, 400, cors);
  } catch (_e) {
    return json({ ok: false, mesaj: "Sunucu hatası" }, 500, cors);
  }
});

function json(obj: unknown, status: number, cors: Record<string, string>) {
  return new Response(JSON.stringify(obj), { status, headers: { ...cors, "Content-Type": "application/json" } });
}
```

- [ ] **Step 2: Statik kontrol**

Run: `grep -c "yetki_matrisi\|MAIN_SERVICE_KEY\|email.split" docs/kurulum/musteri-projesi/masa-yonetim/index.ts; echo "(0 olmali)"`
Expected: `0`. (Deno yerelde yok; bu dosya çalışma zamanında **sınanmadı** — rapor bunu açıkça yazar. Karar mantığı Task 1.4 bölüm 5'te veritabanında sınandı.)

- [ ] **Step 3: Commit**

```bash
git add docs/kurulum/musteri-projesi/masa-yonetim/index.ts
git commit -m "security(bar): rapid-handler kimlik, aktiflik ve otel kapsamini veritabanindan aliyor"
```

### Task 1.8: Yayın anı sorguları ve Aşama 1 raporu

**Files:**
- Create: `docs/kurulum/2026-09-17-bar-a1-preflight.sql`
- Create: `docs/kurulum/2026-09-17-bar-a1-dogrulama.sql`
- Create: `docs/superpowers/reports/2026-09-17-bar-asama1-rapor.md`

- [ ] **Step 1: Preflight (salt okuma)**

```sql
-- BAR A1 — YAYIN ONCESI PREFLIGHT (SALT OKUMA). Hicbir sey yazmaz.
\echo '--- 1) Eklenecek isimler bos mu? (satir = CAKISMA) ---'
select proname from pg_proc p join pg_namespace n on n.oid = p.pronamespace
 where n.nspname = 'public' and proname in ('bar_siparis_oda_onayla','bar_siparis_oda_reddet','bar_masa_yetki_kapsami',
   'stok_cikis_korumasi','_stok_kilitle','_bar_guncel_konaklama','_bar_rezervasyonlari_tuket',
   '_bar_siparis_teslim_uygula','_bar_iptal_uygula','bar_operasyon_gunu');
select relname from pg_class c join pg_namespace n on n.oid = c.relnamespace
 where n.nspname = 'public' and relname in ('bar_ayarlari','bar_stok_tuketimleri');

\echo '--- 2) Gecis etkisi: acik siparisler ve ONAY BEKLEYECEK ucretliler ---'
select s.durum, count(*) as siparis,
       count(*) filter (where exists (select 1 from public.bar_siparis_kalemleri k
                                        join public.menu_urunler m on m.id = k.menu_urun_id
                                       where k.siparis_id = s.id and m.ucretli)) as ucretli
  from public.bar_siparisleri s group by 1 order by 1;

\echo '--- 3) Menusu silinmis kalem (fiyat doldurulamaz -> migration DURUR) ---'
select count(*) from public.bar_siparis_kalemleri k
 where not exists (select 1 from public.menu_urunler m where m.id = k.menu_urun_id);

\echo '--- 4) Aktif rezervasyonlar (koruma devreye girecek depolar) ---'
select depo_id, stok_kodu, sum(miktar) from public.stok_rezervasyonlari where durum = 'aktif' group by 1, 2 order by 1, 2;

\echo '--- 5) Aktif rezervasyonu stoktan fazla olan (teslimde STOK_TUTARSIZ verecek) ---'
select r.depo_id, r.stok_kodu, sum(r.miktar) as rezerve, coalesce(max(s.miktar), 0) as stok
  from public.stok_rezervasyonlari r
  left join public.stok s on s.urun_kodu = r.stok_kodu and s.depo_kodu = r.depo_id
 where r.durum = 'aktif' group by 1, 2 having sum(r.miktar) > coalesce(max(s.miktar), 0);

\echo '--- 6) Depo kodu otel onekiyle uyusmayan bar siparisi ---'
select count(*) from public.bar_siparisleri where split_part(depo_id, '_', 1) <> otel_id::text;
```

- [ ] **Step 2: Migration sonrası doğrulama (salt okuma)**

```sql
-- BAR A1 — MIGRATION SONRASI DOGRULAMA (SALT OKUMA)
\echo '--- 1) Fonksiyon guvenligi ---'
select p.proname, p.prosecdef as definer,
       has_function_privilege('anon', p.oid, 'execute') as anon,
       has_function_privilege('authenticated', p.oid, 'execute') as authenticated
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
 where n.nspname = 'public'
   and p.proname in ('bar_siparis_olustur','bar_siparis_durum_guncelle','bar_siparis_oda_onayla','bar_siparis_oda_reddet',
     'bar_siparis_teslim_et','bar_siparis_iptal','bar_masa_yetki_kapsami','stok_cikis_korumasi','stok_ekle','stok_transfer',
     '_stok_kilitle','_bar_guncel_konaklama','_bar_rezervasyonlari_tuket','_bar_siparis_teslim_uygula','_bar_iptal_uygula')
 order by 1;
\echo '--- 2) Gecis sonucu ---'
select kanal, oda_onay_durumu, durum, count(*) from public.bar_siparisleri group by 1, 2, 3 order by 1, 2, 3;
select count(*) as fiyatsiz_kalem from public.bar_siparis_kalemleri where birim_fiyat is null or ucretli is null;
\echo '--- 3) Stok ve rezervasyon sayaclari preflight ile ayni mi ---'
select count(*) as stok_satir, sum(miktar) as stok_toplam from public.stok;
select durum, count(*), sum(miktar) from public.stok_rezervasyonlari group by 1 order by 1;
```

- [ ] **Step 3: Tüm Aşama 1 testlerini çalıştır ve çıktıları rapora yaz**

Run (her biri ayrı, çıkış kodu ayrı):
```bash
node scripts/bar-test-taban.test.mjs > /tmp/a1-taban.log 2>&1; echo "taban=$?"
node scripts/bar-a1-guvenlik.test.mjs > /tmp/a1-guvenlik.log 2>&1; echo "guvenlik=$?"
node scripts/bar-a1-geri-al.test.mjs > /tmp/a1-geri.log 2>&1; echo "geri=$?"
node scripts/bar-a1-ekran.test.mjs > /tmp/a1-ekran.log 2>&1; echo "ekran=$?"
node scripts/check.mjs; echo "check=$?"
node scripts/hazirlik-kilidi.mjs | tail -1
```
Expected: dört dosya `0 FAIL`, tüm kodlar `0`, kilit `11 dosya AYNI`.

Rapor dosyası şu bölümleri içerir (her sayı log'lardan birebir kopyalanır):
1. **Kapsam** — spec'in 1.1–1.9 maddeleri ve hangi test bölümünün kanıtladığı.
2. **Önce/sonra** — "ÖNCE" ölçümleri ve karşılıkları.
3. **Negatif kontroller** — kilit ve rezerve koruması kaldırılınca ne oldu.
4. **Test sonuçları** — dört dosyanın tam OK/FAIL satırları.
5. **Sınanamayanlar** — `rapid-handler` çalışma zamanı (Deno yok); gerçek PostgREST üzerinden QR akışı; üretim verisiyle geçiş (preflight 2–6 yayın anında).
6. **Bilinen kısıtlar** — sayım rezervasyon altına inemez; geçiş fiyatları güncel fiyat; depo↔otel önek sözleşmesi.
7. **Yayın sırası** — yedek → preflight → A1 migration (`sql-uygula.ps1`, özet kaydı) → doğrulama → ekranları main'e alıp push → `rapid-handler`'ı Dashboard'dan güncelle (`MAIN_ANON_KEY` secret'ı var mı kontrol) → duman testi. **Migration ile ekran arası pencere:** eski ekran ücretli siparişte `FIYAT_DEGISTI`, iptalde `IPTAL_NEDENI_GEREKLI` alır; ekranlar migration'dan hemen sonra yayınlanır.
8. **Geri dönüş** — önce ekranlar (`git diff HEAD <yayın öncesi> -- bar-hata.js bar-menu.html bar-garson.html bar-siparis-kuyrugu.html | git apply --index`), sonra `2026-09-17-bar-a1-guvenlik-geri-al.sql`, sonra `rapid-handler` eski sürümü.

- [ ] **Step 4: Commit**

```bash
git add docs/kurulum/2026-09-17-bar-a1-preflight.sql docs/kurulum/2026-09-17-bar-a1-dogrulama.sql docs/superpowers/reports/2026-09-17-bar-asama1-rapor.md
git commit -m "docs(bar): asama 1 yayin sorgulari ve test raporu"
```

**Aşama 1 burada biter.** Rapor kullanıcıya sunulur; Aşama 2 ayrıntılı planı ancak ondan sonra yazılır.

---

## Aşama 2 — Gün sonu ikmal taslağı (pilot bar) · sabitlenmiş sözleşme

> Kaptan için yeni rol (`bar_kaptan`) **V2 çalışma varsayımıdır**; zayinin taslağa girmemesi
> **Ö4 önerisidir**. Bu aşamanın ayrıntılı planı yazılmadan önce ikisi kesinleşmelidir.

**Migration:** `docs/kurulum/2026-09-XX-bar-a2-ikmal-taslak.sql` (A1'e bağımlı) · **Geri alma:** üretici betikle · **Test:** `scripts/bar-a2-ikmal-taslak.test.mjs` · **Rapor:** `docs/superpowers/reports/2026-09-XX-bar-asama2-rapor.md`

**Veri:**
- `bar_ayarlari` + `ikmal_pilot boolean not null default false`, `kaynak_depo_id text` (check: `split_part(kaynak_depo_id,'_',1) = otel_id::text`).
- `roller`: `kod='bar_kaptan'`, ad `Bar Kaptanı`, seviye `otel` (yoksa eklenir). `moduller`: `bar_ikmal` (kaptan), `bar_ikmal_depo` (depo), kategori `fb` (yoksa eklenir). `yetki_matrisi`: `bar_kaptan → bar_ikmal:kayit, bar_siparis_yonetimi:kayit`; `depo_sef, depo → bar_ikmal_depo:kayit` (rol varsa). Kaptan kullanıcılarının `kullanicilar.rol` enum değeri `bar` kalır (sayfa girişi için); yetki `rol_id` üzerinden.
- `bar_kaptan_atamalari(id uuid pk, kullanici_id uuid → kullanicilar(id), bar_depo_id text → bar_ayarlari, otel_id otel_id, aktif boolean default true, unique(kullanici_id, bar_depo_id))`. Pilotta atama SQL ile yapılır (ekran yok).
- `bar_ikmal_talepleri(id uuid pk, otel_id, bar_depo_id, kaynak_depo_id, operasyon_gunu date, tur text check in ('normal','pazar_ilavesi'), teslim_tarihi date, durum text check in ('taslak','gonderildi','onaylandi','kismi_sevk','sevk_edildi','kapandi','iptal'), olusturan uuid, gonderen uuid, gonderme_zamani, onaylayan uuid, onay_zamani, iptal_nedeni text, olusturma_zamani default now(), unique(bar_depo_id, operasyon_gunu, tur))`.
- `bar_ikmal_kalemleri(id uuid pk, talep_id → talepler, stok_kodu, urun_adi, birim, onerilen_miktar numeric(12,3) not null default 0, talep_miktar numeric(12,3) not null check (>= 0), kaynak text check in ('tuketim','elle'), elle_degisti boolean default false, onaylanan_miktar numeric(12,3), unique(talep_id, stok_kodu))`.
- RLS: tek permissive SELECT politikası her tabloda: `(auth_yetki_var('bar_ikmal','goruntule') or auth_yetki_var('bar_ikmal_depo','goruntule')) and auth_otel_erisim(otel_id)`; kalemler üst talep üzerinden `exists`. Doğrudan yazma yok.

**Fonksiyonlar (kesin imzalar):**
- `_bar_kaptan_mi(p_bar_depo_id text) returns boolean` (iç) — aktif kullanıcı + `roller.kod='bar_kaptan'` + aktif atama + `auth_yetki_var('bar_ikmal','kayit')` + otel erişimi.
- `_bar_pilot_mi(p_bar_depo_id text) returns boolean` (iç).
- `bar_ikmal_taslak_uret(p_bar_depo_id text, p_operasyon_gunu date) returns uuid`
- `bar_ikmal_kalem_guncelle(p_kalem_id uuid, p_talep_miktar numeric) returns void`
- `bar_ikmal_kalem_ekle(p_talep_id uuid, p_stok_kodu text, p_talep_miktar numeric) returns uuid`
- `bar_ikmal_kalem_sil(p_kalem_id uuid) returns void`
- `bar_ikmal_gonder(p_talep_id uuid) returns void`
- `bar_ikmal_iptal(p_talep_id uuid, p_neden text) returns void` — kaptan (taslak/gonderildi) ya da `bar_ikmal_depo:kayit` (gonderildi).

**Yeni hata kodları:** `PILOT_KAPALI`, `KAPTAN_ATAMASI_YOK`, `TALEP_KILITLI`, `KALEM_VAR`, `URUN_YOK`, `BOS_TALEP`, `MIKTAR_GECERSIZ`.

**Kabul senaryoları (her biri ayrı OK satırı):**
1. 05:59 teslim önceki güne, 06:00 teslim o güne yazılır (`bar_operasyon_gunu`); `gun_sonu_saati='04:00'` olan barda sınır 04:00.
2. Taslak yalnız `tur='satis'` tüketimden; zayi ve başka barın tüketimi girmez.
3. Aynı gün için ikinci `taslak_uret` yeni talep açmaz; yeni tüketim `onerilen`'i günceller; kaptanın değiştirdiği `talep_miktar` ve `elle` kalemler korunur.
4. Kaptan miktar değiştirir, ürün ekler, elle kalemi siler; tüketim kalemi silinemez (0'a çekilir).
5. Taslak üretimi ve tüm kaptan düzenlemeleri **öncesi/sonrası** `stok`, `stok_hareketleri`, `stok_rezervasyonlari`, `bar_stok_tuketimleri` satır sayıları ve toplamları **aynı**.
6. `gonderildi` talepte düzenleme `TALEP_KILITLI`.
7. Başka barın kaptanı, atamasız `bar_kaptan`, pasif kaptan, 811 personeli → ret; pilotu kapalı bar → `PILOT_KAPALI`.
8. Günlük sayım yapılmamış ve ücretsiz stoksuz ürün servisi girilmemiş bir günde taslak üretimi **çalışır**.
9. Negatif kontrol: `_bar_kaptan_mi` her zaman `true` döndüğünde başka barın kaptanı düzenleyebiliyor.

**Ekran:** `bar-ikmal.html` (kaptan) — gün seçimi, taslak üret, kalem tablosu (önerilen salt-okunur, talep düzenlenebilir), ürün ekle (`urunler` sunucu araması), gönder. Ekran testi: yük biçimi ve kilitli talepte düzenleme alanlarının kapalı olması.

---

## Aşama 3 — Cuma pazar ilavesi (pilot bar) · sabitlenmiş sözleşme

> Giriş penceresinin teslim tarihine bağlanması **Ö3 önerisidir**, kesinleşmedi.

**Migration:** `docs/kurulum/2026-09-XX-bar-a3-pazar-ilavesi.sql` (A2'ye bağımlı) · **Test:** `scripts/bar-a3-pazar-ilavesi.test.mjs` · **Rapor:** `…-bar-asama3-rapor.md`

**Fonksiyonlar:**
- `_bar_ikmal_pazar_ilavesi_ac(p_bar_depo_id text, p_operasyon_gunu date, p_simdi timestamptz) returns uuid` (iç; testler zamanı buradan verir — üretimde zaman kancası YOK).
- `bar_ikmal_pazar_ilavesi_ac(p_bar_depo_id text, p_operasyon_gunu date) returns uuid` → `now()` ile iç fonksiyonu çağırır.
- Kurallar: `extract(isodow from p_operasyon_gunu) = 5` değilse `PAZAR_ILAVESI_YALNIZ_CUMA`; `(p_simdi at time zone 'Europe/Istanbul')::date > p_operasyon_gunu + 1` ise `PAZAR_ILAVESI_SURESI_DOLDU`; talep `tur='pazar_ilavesi'`, `teslim_tarihi = p_operasyon_gunu + 1`, kalemsiz açılır; varsa aynı id döner. Düzenleme/gönderme Aşama 2 fonksiyonlarıyla.
- `bar_ikmal_taslak_uret` normal talebin `teslim_tarihi`'ni `operasyon_gunu + 1` yazar (Cuma → Cumartesi).

**Yeni hata kodları:** `PAZAR_ILAVESI_YALNIZ_CUMA`, `PAZAR_ILAVESI_SURESI_DOLDU`.

**Kabul senaryoları:**
1. Cuma 23:30 ve Cumartesi 01:30 teslimleri Cuma normal talebinin taslağında; Cumartesi 06:30 teslimi Cumartesi'de.
2. Pazar ilavesi Cuma 23:00, Cumartesi 02:00 ve Cumartesi 09:00 zamanlarıyla açılabilir; Pazar 00:30'da `PAZAR_ILAVESI_SURESI_DOLDU`.
3. Perşembe operasyon günü için `PAZAR_ILAVESI_YALNIZ_CUMA`.
4. Normal talep ve pazar ilavesi ayrı satır, ayrı kalemler, ikisi de `teslim_tarihi` = Cumartesi; birini göndermek diğerini kilitlemez.
5. Pazar ilavesi taslak üretiminden kalem **almaz**; aynı gün ikinci açma çağrısı aynı id'yi döner.
6. Genel yetki senaryoları Aşama 2 ile aynı (başka bar kaptanı, pilot kapalı).

**Ekran:** `bar-ikmal.html` — Cuma operasyon gününde "Pazar ilavesi" sekmesi; normal ve ilave ayrı listelenir.

---

## Aşama 4 — Teslim kabulü (pilot bar) · sabitlenmiş sözleşme

> Açık farkın depoca "geri al / kayıp" ile kapatılması **V3 çalışma varsayımıdır**; ayrı ikmal
> tabloları **Ö5 önerisidir**. Bu aşamanın ayrıntılı planından önce kesinleşmelidir.

**Migration:** `docs/kurulum/2026-09-XX-bar-a4-teslim-kabul.sql` (A2–A3'e bağımlı) · **Test:** `scripts/bar-a4-teslim-kabul.test.mjs` · **Rapor:** `…-bar-asama4-rapor.md`

**Veri:**
- `create sequence bar_ikmal_sevk_no_seq`.
- `bar_ikmal_sevkleri(id uuid pk, talep_id → talepler, otel_id, sevk_no text unique default 'SVK-' || nextval, durum text check in ('yolda','kabul_edildi'), sevk_eden uuid, sevk_zamani default now(), kabul_eden uuid, kabul_zamani)`.
- `bar_ikmal_sevk_kalemleri(id uuid pk, sevk_id → sevkler, talep_kalem_id → kalemler, stok_kodu, sevk_miktar numeric(12,3) check (> 0), kabul_miktar numeric(12,3) check (kabul_miktar is null or kabul_miktar between 0 and sevk_miktar), fark_durumu text check in ('yok','acik','geri_alindi','kayip') default 'yok', fark_kapatan uuid, fark_zamani, fark_notu)`.
- RLS: Aşama 2 ile aynı kalıp; doğrudan yazma yok.

**Fonksiyonlar (kesin imzalar):**
- `_bar_ikmal_depo_yetkili(p_otel text) returns boolean` (iç) — `auth_yetki_var('bar_ikmal_depo','kayit') and auth_otel_erisim(p_otel)`.
- `_bar_ikmal_talep_durum_guncelle(p_talep_id uuid) returns text` (iç) — Σsevk=0 → `onaylandi`; Σsevk < Σonay → `kismi_sevk`; yolda sevk ya da açık fark varsa `sevk_edildi`; aksi `kapandi`.
- `bar_ikmal_onayla(p_talep_id uuid, p_kalemler jsonb) returns jsonb` — `[{kalem_id, onaylanan_miktar}]`; verilmeyen kalem `talep_miktar`; `0 ≤ onay ≤ talep`; yalnız `gonderildi`; `onaylandi` ise `zaten_onayli`. **Stok yazmaz.**
- `bar_ikmal_sevk_et(p_talep_id uuid, p_kalemler jsonb) returns uuid` — `[{kalem_id, sevk_miktar}]`; yalnız `onaylandi|kismi_sevk`; kalem başına `Σsevk ≤ onaylanan`; kaynak depo kilitli ve katı düşüş (`STOK_YETERSIZ`, 0'a kırpma yok; kaynak depodaki aktif rezervasyon da korunur); `stok_hareketleri` `cikis`, `aciklama 'bar_ikmal_sevk: <sevk_no> -> <bar>'`, `belge_no = sevk_no`.
- `bar_ikmal_kabul_et(p_sevk_id uuid, p_kalemler jsonb) returns jsonb` — `[{sevk_kalem_id, kabul_miktar}]`; **tüm** sevk kalemleri verilmeli (`KABUL_EKSIK`); `0 ≤ kabul ≤ sevk`; sevk `yolda` değilse `ZATEN_KABUL`; bar stoğu yalnız kabul kadar artar; `sevk > kabul` → `fark_durumu='acik'`; hareket `giris`, `kaynak_depo_kodu = kaynak depo`.
- `bar_ikmal_fark_kapat(p_sevk_kalem_id uuid, p_karar text, p_not text) returns void` — yalnız `acik` (`FARK_KAPALI`); `geri_al` → kaynak depoya `sevk − kabul` geri girer + hareket; `kayip` → stok değişmez; not zorunlu.

**Yeni hata kodları:** `ONAY_TALEBI_ASIYOR`, `SEVK_ONAYI_ASIYOR`, `BOS_SEVK`, `KABUL_EKSIK`, `KABUL_SEVKI_ASIYOR`, `ZATEN_KABUL`, `FARK_KAPALI`, `KARAR_GECERSIZ`.

**Kabul senaryoları:**
1. Onay öncesi/sonrası kaynak ve bar stoğu **aynı** (depo onayı bar stoğunu artırmaz).
2. Sevk: kaynak düşer, bar **değişmez**; `stok` toplamı sevk miktarı kadar azalır ("yolda").
3. Kabul: bar yalnız kabul kadar artar; kabul edilmeyen bar stoğuna **girmez**.
4. Kısmi teslimat: onay 10 → sevk 4 (`kismi_sevk`) → kabul 3 (fark 1 açık) → sevk 6 (`sevk_edildi`) → kabul 6 → fark `geri_al` → `kapandi`; her adımda kaynak/bar/yolda miktarları ölçülür.
5. Onayı aşan sevk `SEVK_ONAYI_ASIYOR`; kaynakta yetersiz stok `STOK_YETERSIZ` ve hiçbir satır yazılmaz.
6. Kabul iki kez: `ZATEN_KABUL`, bar stoğu bir kez arttı; **eşzamanlı** iki kabul (iki bağlantı) → tek başarı.
7. Fark `kayip`: stok değişmez; ikinci kapatma `FARK_KAPALI`.
8. Yetki: depo kullanıcısı kabul edemez; kaptan onay/sevk/fark kapatamaz; 811 depocusu 810 talebini onaylayamaz; pasif kullanıcı hiçbirini yapamaz.
9. Mevcut `depo-siparis.html` iç talep akışı değişmedi: diğer departman talebinin onayı hâlâ anında transfer yapıyor (regresyon ölçümü).
10. Negatif kontrol: `bar_ikmal_kabul_et` içindeki `FOR UPDATE` kaldırılınca eşzamanlı çift kabul **iki kez** stok ekliyor.

**Ekranlar:** `bar-ikmal.html` (kaptan: yoldaki sevkler + kabul formu), `bar-ikmal-depo.html` (depo: gelen talepler normal/pazar ilavesi ayrı, onay, sevk, kısmi teslimat görünümü, açık farklar). Ekran testleri: yük biçimi, kısmi kabulde fark gösterimi, eksik kalemle kabulün gönderilmemesi.

---

## Self-review (yazar kontrolü)

**Spec kapsamı:**
- 1.1 fiyat → Task 1.3 §6, §9; test §2. · 1.2 oda onayı → §6–§7; test §2–§4. · 1.3 tekil teslim → §8; test §2 (ikinci teslim), §3 (folyo kapalı geri alma). · 1.4 yarış → Task 1.2 §4, §6; test §7 + negatif. · 1.5 diğer çıkışlar → Task 1.2 §4; test §6 + negatif. · 1.6 zayi iptal → §8; test §3–§4. · 1.7 otel → §6, §9, Task 1.7; test §5. · 1.8 pasif → test §2, §5; Task 1.7. · 1.9 ekranlar → Task 1.6.
- Aşama 2–4 spec maddeleri sabitlenmiş sözleşme bölümlerinde imza + senaryo olarak karşılanıyor; adım dökümleri aşama başında.

**Tip tutarlılığı:** `bar_siparis_iptal(uuid, text)` → ekran `{p_siparis_id, p_neden}` ✓ · `bar_siparis_teslim_et` jsonb → ekran `d.sonuc` ✓ · `bar_siparis_oda_onayla(uuid)`/`oda_reddet(uuid,text)` → ekran ✓ · `bar_masa_yetki_kapsami()` → `rapid-handler` `kapsam.yetkili/oteller` ✓ · hata kodları migration ↔ `bar-hata.js` ↔ ekran testi listesi ✓.
