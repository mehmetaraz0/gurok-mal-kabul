// ============================================================================
// migration-guvenlik-kontrol.test.mjs — SABOTAJ TESTLERI
//
// Calistir:  node --test scripts/migration-guvenlik-kontrol.test.mjs
//
// Yontem: saglam sablonu al, TEK bir guvenlik ozelligini boz, denetleyicinin
// TAM OLARAK beklenen kurali bulmasini bekle.
//
// Neden "kirmizi oldu" yetmez: yanlis sebeple kirmizi olan bir test hicbir
// sey olcmez. Bu yuzden her sabotaj (a) metni gercekten degistirdigini
// SAYARAK dogrular, (b) beklenen KURAL KODUNU arar.
// ============================================================================

import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const buDizin = path.dirname(fileURLToPath(import.meta.url));
const kok = path.resolve(buDizin, '..');
const SABLON = path.join(kok, 'docs', 'kurulum', 'SABLON-yeni-migration.sql');
const KONTROL = path.join(buDizin, 'migration-guvenlik-kontrol.mjs');

const gecici = fs.mkdtempSync(path.join(os.tmpdir(), 'mig-guv-'));

function tekKipDenetle(sqlMetni, ad) {
  const yol = path.join(gecici, ad + '.sql');
  fs.writeFileSync(yol, sqlMetni, 'utf8');
  const r = spawnSync(process.execPath, [KONTROL, yol], { encoding: 'utf8', cwd: kok });
  return { kod: r.status, cikti: (r.stdout || '') + (r.stderr || '') };
}

// Bulgular ve ozet; dosya yolu haric (iki kipte dosya adi farkli).
const bulguOzeti = (cikti) => cikti.split(/\r?\n/)
  .filter((s) => /^\s+(HATA|UYARI)\s/.test(s) || /^==> /.test(s))
  .map((s) => s.trim()).join('\n');

// HER metin iki kez denetlenir: LF ve CRLF. Iki kip AYNI bulgulari
// vermezse test burada duser. Neden: Windows'ta calisma kopyasindaki
// migration dosyalari CRLF'dir (core.autocrlf=true). 2026-09-18'e kadar
// denetleyici CRLF dosyada "@append-only" yonergesini okuyamiyor ve R6'yi
// TAMAMEN atliyordu; append-only tabloya DELETE grant'i "TEMIZ" geciyordu.
// Boylece her sabotaj testi ayni zamanda satir sonu esitligini kanitlar.
function denetle(sqlMetni, ad) {
  const lf = sqlMetni.replace(/\r\n?/g, '\n');
  const rLf = tekKipDenetle(lf, ad + '-lf');
  const rCrlf = tekKipDenetle(lf.replace(/\n/g, '\r\n'), ad + '-crlf');
  assert.equal(rCrlf.kod, rLf.kod,
    'LF ve CRLF farkli cikis kodu verdi (' + rLf.kod + ' / ' + rCrlf.kod + ')\n--- LF:\n' +
    rLf.cikti + '\n--- CRLF:\n' + rCrlf.cikti);
  assert.equal(bulguOzeti(rCrlf.cikti), bulguOzeti(rLf.cikti),
    'LF ve CRLF farkli bulgu verdi\n--- LF:\n' + rLf.cikti + '\n--- CRLF:\n' + rCrlf.cikti);
  return rLf;
}

// Metni degistirir ve degisikligin GERCEKTEN oldugunu dogrular.
function boz(metin, eski, yeni, beklenenAdet = 1) {
  const adet = metin.split(eski).length - 1;
  assert.equal(adet, beklenenAdet,
    'SABOTAJ KURULAMADI: "' + eski.slice(0, 60) + '" ' + adet + ' kez bulundu, ' +
    beklenenAdet + ' bekleniyordu. Sablon degistiyse testi guncelle.');
  return metin.split(eski).join(yeni);
}

// Sablon repoda CRLF ile commit edilmis olabilir; sabotaj metinleri (cok
// satirli olanlar dahil) "\n" ile yazildigi icin sablon LF'e cevrilir.
// Denetleyicinin CRLF davranisi ayrica denetle() icinde sinanir.
const sablon = fs.readFileSync(SABLON, 'utf8').replace(/\r\n?/g, '\n');

// ---------------------------------------------------------------------------
// NEGATIF KONTROL — bozulmamis sablon YESIL olmali.
// Bu test kirmizi ise digerlerinin hicbiri bir sey kanitlamaz.
// ---------------------------------------------------------------------------
test('bozulmamis sablon: YESIL', () => {
  const r = denetle(sablon, 'temiz');
  assert.equal(r.kod, 0, r.cikti);
  assert.match(r.cikti, /STANDARDA UYGUN/);
  assert.match(r.cikti, /0 HATA \| 0 UYARI/);
});

// ---------------------------------------------------------------------------
// A) REVOKE blogu kaldirildi
// ---------------------------------------------------------------------------
test('A: REVOKE blogu yok -> R1', () => {
  const bozuk = boz(sablon,
    'revoke all on table public.ornek_baslik  from public, anon, authenticated;',
    '-- (sabotaj: revoke silindi)');
  const r = denetle(bozuk, 'a-revoke-yok');
  assert.equal(r.kod, 1, r.cikti);
  assert.match(r.cikti, /R1-TABLO-REVOKE-YOK\s+ornek_baslik/);
});

// ---------------------------------------------------------------------------
// B) authenticated'a ALL
// ---------------------------------------------------------------------------
test('B: authenticated ALL -> R4', () => {
  const bozuk = boz(sablon,
    'grant select, insert, update, delete on public.ornek_baslik to authenticated;',
    'grant all on public.ornek_baslik to authenticated;');
  const r = denetle(bozuk, 'b-all');
  assert.equal(r.kod, 1, r.cikti);
  assert.match(r.cikti, /R4-AUTHENTICATED-ALL/);
});

// ---------------------------------------------------------------------------
// C) SECURITY DEFINER search_path pini kaldirildi
// ---------------------------------------------------------------------------
test('C: DEFINER pinsiz -> R9', () => {
  const bozuk = boz(sablon,
    `returns void language plpgsql security definer
set search_path = pg_catalog, public, pg_temp as $$`,
    `returns void language plpgsql security definer
as $$`);
  const r = denetle(bozuk, 'c-pinsiz');
  assert.equal(r.kod, 1, r.cikti);
  assert.match(r.cikti, /R9-DEFINER-PINSIZ\s+ornek_kapat/);
});

// ---------------------------------------------------------------------------
// D) Append-only tabloya DELETE grant
// ---------------------------------------------------------------------------
test('D: append-only tabloya DELETE -> R6', () => {
  const bozuk = boz(sablon,
    'grant select, insert on public.ornek_hareket to authenticated;',
    'grant select, insert, delete on public.ornek_hareket to authenticated;');
  const r = denetle(bozuk, 'd-append-delete');
  assert.equal(r.kod, 1, r.cikti);
  assert.match(r.cikti, /R6-APPEND-ONLY-YAZMA\s+ornek_hareket/);
});

// ---------------------------------------------------------------------------
// E) Append-only bekci tetikleyicisi kaldirildi
//    (ayricalik dogru olsa bile service_role RLS'i baypas eder)
// ---------------------------------------------------------------------------
test('E: append-only tetikleyicisi yok -> R6', () => {
  const bozuk = boz(sablon,
    `create trigger ornek_degismez before update or delete
  on public.ornek_hareket
  for each row execute function public.ornek_degismez();`,
    '-- (sabotaj: bekci tetikleyici silindi)');
  const r = denetle(bozuk, 'e-tetikleyici-yok');
  assert.equal(r.kod, 1, r.cikti);
  assert.match(r.cikti, /R6-APPEND-ONLY-TETIKLEYICI-YOK\s+ornek_hareket/);
});

// ---------------------------------------------------------------------------
// F) anon'a acik GRANT
// ---------------------------------------------------------------------------
test('F: anon GRANT -> R5', () => {
  const bozuk = boz(sablon,
    'grant select on public.ornek_ozet to authenticated, service_role;',
    'grant select on public.ornek_ozet to authenticated, anon, service_role;');
  const r = denetle(bozuk, 'f-anon-grant');
  assert.equal(r.kod, 1, r.cikti);
  assert.match(r.cikti, /R5-ACIK-GRANT/);
});

// ---------------------------------------------------------------------------
// G) RLS acilmamis
// ---------------------------------------------------------------------------
test('G: RLS yok -> R7', () => {
  const bozuk = boz(sablon,
    'alter table public.ornek_hareket enable row level security;',
    '-- (sabotaj: RLS acilmadi)');
  const r = denetle(bozuk, 'g-rls-yok');
  assert.equal(r.kod, 1, r.cikti);
  assert.match(r.cikti, /R7-RLS-YOK\s+ornek_hareket/);
});

// ---------------------------------------------------------------------------
// H) Gorunumde security_invoker yok (RLS sahibe gore degerlendirilir)
// ---------------------------------------------------------------------------
test('H: security_invoker yok -> R10', () => {
  const bozuk = boz(sablon,
    `create or replace view public.ornek_ozet
with (security_invoker = true) as`,
    `create or replace view public.ornek_ozet as`);
  const r = denetle(bozuk, 'h-invoker-yok');
  assert.equal(r.kod, 1, r.cikti);
  assert.match(r.cikti, /R10-GORUNUM-INVOKER-YOK\s+ornek_ozet/);
});

// ---------------------------------------------------------------------------
// I) REVOKE'tan authenticated dusuruldu
//    Gercek olay: PMS Adim 1-2 tam olarak bunu yapiyordu.
// ---------------------------------------------------------------------------
test('I: REVOKE authenticated icermiyor -> R2', () => {
  const bozuk = boz(sablon,
    'revoke all on table public.ornek_hareket from public, anon, authenticated;',
    'revoke all on table public.ornek_hareket from public, anon;');
  const r = denetle(bozuk, 'i-revoke-eksik');
  assert.equal(r.kod, 1, r.cikti);
  assert.match(r.cikti, /R2-REVOKE-EKSIK-ROL\s+ornek_hareket/);
});

// ---------------------------------------------------------------------------
// J) Cagrilabilir fonksiyonun EXECUTE karari yok
//    Gercek olay: PMS Adim 3'te pms_bugun.  Bu bir UYARI'dir; --uyari-da-hata
//    ile CI'da bloke edilebilir.
// ---------------------------------------------------------------------------
test('J: fonksiyon EXECUTE karari yok -> R9 (UYARI)', () => {
  let bozuk = boz(sablon,
    'revoke all on function public.ornek_kapat(uuid) from public, anon, authenticated, service_role;',
    '-- (sabotaj: revoke silindi)');
  bozuk = boz(bozuk,
    'grant execute on function public.ornek_kapat(uuid) to authenticated;',
    '-- (sabotaj: grant silindi)');
  const r = denetle(bozuk, 'j-fonksiyon-acl-yok');
  assert.equal(r.kod, 0, 'UYARI varsayilan olarak cikis kodunu bozmamali');
  assert.match(r.cikti, /R9-FONKSIYON-ACL-KARARI-YOK\s+ornek_kapat/);

  // --uyari-da-hata ile bloke edilebilmeli
  const yol = path.join(gecici, 'j-fonksiyon-acl-yok-lf.sql');
  const s = spawnSync(process.execPath, [KONTROL, yol, '--uyari-da-hata'],
    { encoding: 'utf8', cwd: kok });
  assert.equal(s.status, 1, s.stdout);
});

// ---------------------------------------------------------------------------
// K) Sekans ACL'i kaldirildi
// ---------------------------------------------------------------------------
test('K: sekans REVOKE yok -> R8', () => {
  const bozuk = boz(sablon,
    'revoke all on sequence public.ornek_no_seq from public, anon, authenticated;',
    '-- (sabotaj: sekans revoke silindi)');
  const r = denetle(bozuk, 'k-sekans');
  assert.equal(r.kod, 1, r.cikti);
  assert.match(r.cikti, /R8-SEKANS-REVOKE-YOK\s+ornek_no_seq/);
});

// ---------------------------------------------------------------------------
// N) YONERGELER her satir sonunda okunur
//    Gercek olay (2026-09-18): yonergeler satir satir "\n" ile bolunuyordu;
//    CRLF dosyada her satir "\r" ile bitiyor ve "(.+)$" deseni eslesmiyordu
//    (JS'te "." \r yutmaz). Sonuc: @append-only okunmuyor ve R6 TAMAMEN
//    atlaniyordu; @erisim-yok ve gerekceli @acl-istisna da yok sayiliyordu.
//    denetle() iki kipi zaten karsilastirir; burada her yonergenin GERCEKTEN
//    etki ettigi (yok sayilmadigi) ayrica olculur.
// ---------------------------------------------------------------------------
test('N: @append-only, @erisim-yok ve gerekceli @acl-istisna okunur', () => {
  const sql = [
    '-- @append-only: n_kayit',
    '-- @erisim-yok: n_ic',
    '-- @acl-istisna: n_eski -- tarihsel tablo, ayri migrationda duzeltilecek',
    'create table public.n_kayit (id int);',
    'alter table public.n_kayit enable row level security;',
    'revoke all on table public.n_kayit from public, anon, authenticated;',
    'grant select, insert, delete on public.n_kayit to authenticated;',
    'create table public.n_ic (id int);',
    'alter table public.n_ic enable row level security;',
    'revoke all on table public.n_ic from public, anon, authenticated;',
    'create table public.n_eski (id int);',
    'alter table public.n_eski enable row level security;',
  ].join('\n');
  const r = denetle(sql, 'n-yonergeler');
  // @append-only okundu: DELETE grant'i ve eksik tetikleyici yakalanmali
  assert.match(r.cikti, /R6-APPEND-ONLY-YAZMA\s+n_kayit/);
  assert.match(r.cikti, /R6-APPEND-ONLY-TETIKLEYICI-YOK\s+n_kayit/);
  // @erisim-yok okundu: n_ic icin GRANT karari istenmemeli
  assert.doesNotMatch(r.cikti, /R3-GRANT-KARARI-YOK\s+n_ic/);
  // gerekceli @acl-istisna okundu: n_eski hic denetlenmemeli
  assert.doesNotMatch(r.cikti, /n_eski/);
});

// ---------------------------------------------------------------------------
// O) YENI FONKSIYON service_role EXECUTE'unu VARSAYILAN ACL'DEN MIRAS ALIR
//
//    Gercek olay (2026-09-10): adim 2 migration'i YENI bir fonksiyon
//    (pms_housekeeping_odalar) yaratti ve yalniz public/anon'dan revoke etti.
//    public/postgres varsayilan ACL'si (P3) yeni fonksiyona service_role
//    EXECUTE verdi. Denetleyici 0 HATA 0 UYARI dedi; yalniz REST baypas
//    testi X16 yakaladi. Mevcut fonksiyonun CREATE OR REPLACE'i ACL'yi
//    korudugu icin listele etkilenmedi.
//
//    Sabotaj, duzeltilmis dosyadan olayin ORIJINAL halini geri uretir.
// ---------------------------------------------------------------------------
const ADIM1 = path.join(kok, 'docs', 'kurulum', '2026-09-09-pms-faz2-adim1-housekeeping.sql');
const ADIM2 = path.join(kok, 'docs', 'kurulum', '2026-09-10-pms-faz2-adim2-housekeeping-ui-destek.sql');

function denetleYol(yol, ...ekArgumanlar) {
  const r = spawnSync(process.execPath, [KONTROL, yol, ...ekArgumanlar], { encoding: 'utf8', cwd: kok });
  return { kod: r.status, cikti: (r.stdout || '') + (r.stderr || '') };
}

const r11Adedi = cikti => (cikti.match(/R11-SERVICE-ROLE-KARARI-YOK/g) || []).length;

function adim2OlayOncesi() {
  let m = fs.readFileSync(ADIM2, 'utf8');
  m = boz(m, 'revoke all on function public.pms_housekeeping_odalar(text, integer) from authenticated;\n', '');
  m = boz(m, 'revoke all on function public.pms_housekeeping_odalar(text, integer) from service_role;\n', '');
  m = boz(m,
    "execute format('revoke all on function %s from public, anon, authenticated, service_role', r.imza);",
    "execute format('revoke all on function %s from public, anon', r.imza);");
  return m;
}

test('O-a: yeni fonksiyon service_role revoke etmiyor -> R11 (2026-09-10 olayi)', () => {
  const r = denetle(adim2OlayOncesi(), 'o-a-service-role-miras');
  assert.equal(r.kod, 1, r.cikti);
  assert.match(r.cikti, /R11-SERVICE-ROLE-KARARI-YOK\s+pms_housekeeping_odalar/);
  assert.doesNotMatch(r.cikti, /R11-SERVICE-ROLE-KARARI-YOK\s+pms_housekeeping_listele/,
    'listele service_role icin acik revoke tasiyor; bulgu uretmemeli');
  assert.equal(r11Adedi(r.cikti), 1, r.cikti);
  assert.match(r.cikti, /1 HATA \| 0 UYARI/, 'yalniz R11 beklenir, baska kural degil');
});

test('O-b: duzeltilmis 2026-09-10 migration TEMIZ (--uyari-da-hata)', () => {
  const r = denetleYol(ADIM2, '--uyari-da-hata');
  assert.equal(r.kod, 0, r.cikti);
  assert.match(r.cikti, /0 HATA \| 0 UYARI/);
  assert.equal(r11Adedi(r.cikti), 0, r.cikti);
});

// NEGATIF KONTROL: service_role'a ACIK grant bir karardir, miras degildir.
test('O-c: service_role icin acik GRANT karari -> R11 YOK', () => {
  const bozuk = boz(adim2OlayOncesi(),
    'grant execute on function public.pms_housekeeping_odalar(text, integer) to authenticated;\n',
    'grant execute on function public.pms_housekeeping_odalar(text, integer) to authenticated;\n' +
    '-- Kasitli: servis koprusu cagirir.\n' +
    'grant execute on function public.pms_housekeeping_odalar(text, integer) to service_role;\n');
  const r = denetle(bozuk, 'o-c-acik-grant');
  assert.equal(r.kod, 0, r.cikti);
  assert.equal(r11Adedi(r.cikti), 0, r.cikti);
  assert.match(r.cikti, /0 HATA \| 0 UYARI/);
});

// ---------------------------------------------------------------------------
// P) LIKE SUPURGESI service_role'u adiyla anarsa kapsar
//    Adim 1'in acik revoke'lari yalniz public/anon'dur; service_role
//    "proname like 'pms\_housekeeping\_%'" supurgesiyle dusurulur.
// ---------------------------------------------------------------------------
test('P: adim 1 LIKE supurgesi service_role icermezse -> R11 (yalniz cagrilabilirler)', () => {
  const temiz = denetleYol(ADIM1, '--uyari-da-hata');
  assert.equal(temiz.kod, 0, temiz.cikti);
  assert.equal(r11Adedi(temiz.cikti), 0, temiz.cikti);

  const bozuk = boz(fs.readFileSync(ADIM1, 'utf8'),
    "    execute format('revoke all on function %s from public, anon, authenticated, service_role', v.f);\n" +
    "    execute format('grant execute on function %s to authenticated', v.f);",
    "    execute format('revoke all on function %s from public, anon, authenticated', v.f);\n" +
    "    execute format('grant execute on function %s to authenticated', v.f);");
  const r = denetle(bozuk, 'o-like-supurge');
  assert.equal(r.kod, 1, r.cikti);
  assert.match(r.cikti, /R11-SERVICE-ROLE-KARARI-YOK\s+pms_housekeeping_listele/);
  // 14 cagrilabilir genel RPC; 7 tetikleyici fonksiyonu kapsam disi.
  assert.equal(r11Adedi(r.cikti), 14, r.cikti);
  assert.doesNotMatch(r.cikti, /R11-SERVICE-ROLE-KARARI-YOK\s+pms_housekeeping_gorev_koruma/);
  assert.match(r.cikti, /14 HATA \| 0 UYARI/, 'yalniz R11 beklenir, baska kural degil');
});

// ---------------------------------------------------------------------------
// Q) Supurge kapsami DAR yorumlanir: baska semanin supurgesi ya da yorum
//    satirindaki execute, genel fonksiyonun service_role kararini VERMEZ.
// ---------------------------------------------------------------------------
test('Q: supurge semasi ve yorum satiri service_role kararini vermez', () => {
  const sql = String.raw`
create or replace function public.hk_deneme(p int)
returns int language sql as $$ select p $$;

revoke all on function public.hk_deneme(int) from public, anon;
grant execute on function public.hk_deneme(int) to authenticated;

do $$
declare v record;
begin
  for v in select p.oid::regprocedure as f
             from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
            where ns.nspname = 'phase0_private' and p.proname like 'hk\_%'
  loop
    execute format('revoke all on function %s from public, anon, authenticated, service_role', v.f);
  end loop;
end;
$$;
`;
  const baskaSema = denetle(sql, 'p-baska-sema');
  assert.equal(baskaSema.kod, 1, baskaSema.cikti);
  assert.match(baskaSema.cikti, /R11-SERVICE-ROLE-KARARI-YOK\s+hk_deneme/);

  const genelSema = boz(sql, "ns.nspname = 'phase0_private'", "ns.nspname = 'public'");
  const r = denetle(genelSema, 'p-genel-sema');
  assert.equal(r.kod, 0, r.cikti);
  assert.match(r.cikti, /0 HATA \| 0 UYARI/);

  const yorumda = boz(genelSema,
    "    execute format('revoke all on function %s from public, anon, authenticated, service_role', v.f);",
    "    -- execute format('revoke all on function %s from public, anon, authenticated, service_role', v.f);\n" +
    "    execute format('revoke all on function %s from public, anon', v.f);");
  const y = denetle(yorumda, 'p-yorumda');
  assert.equal(y.kod, 1, y.cikti);
  assert.match(y.cikti, /R11-SERVICE-ROLE-KARARI-YOK\s+hk_deneme/);
});

// ---------------------------------------------------------------------------
// M) YANLIS ALARM: DIZE ICINDEKI DDL ANAHTAR KELIMESI
//
//    Gercek olay (2026-09-08): event trigger tanimindaki
//      when tag in ('CREATE TABLE', 'CREATE TABLE AS', 'SELECT INTO')
//    satirindan denetleyici "as" adli bir tablo uydurdu ve dosyayi haksiz
//    yere kirmizi yapti. Bir denetleyici yanlis alarm verdiginde artik
//    okunmaz; bu yuzden regresyon testi.
// ---------------------------------------------------------------------------
test('M: dize icindeki CREATE TABLE sahte nesne uretmemeli', () => {
  const sql = [
    'create event trigger ornek_trg',
    "  on ddl_command_end",
    "  when tag in ('CREATE TABLE', 'CREATE TABLE AS', 'SELECT INTO')",
    '  execute function public.ornek_ag();',
    '',
    "-- Dolar-tirnak govdesi icinde de sayilmamali:",
    'do $$',
    'begin',
    "  raise notice 'create table public.hayalet_tablo (id int)';",
    'end;',
    '$$;',
  ].join('\n');

  const r = denetle(sql, 'm-dize-icinde-ddl');
  assert.equal(r.kod, 0, r.cikti);
  assert.match(r.cikti, /tablo 0/);
  assert.doesNotMatch(r.cikti, /\bas\b/,
    'dize icindeki "CREATE TABLE AS" tablo olarak sayilmamali');
  assert.doesNotMatch(r.cikti, /hayalet_tablo/,
    'dolar-tirnak govdesindeki DDL metni tablo olarak sayilmamali');
});

// ---------------------------------------------------------------------------
// L) TARIHSEL DOSYALAR FAIL ETMEMELI
//    Argumansiz calistirma yalniz taban tarihten YENI dosyalari denetler.
//    Canliya uygulanmis Adim 1-4 bu kapsamin disindadir.
// ---------------------------------------------------------------------------
test('L: argumansiz calistirma tarihi dosyalari kirmizi yapmaz', () => {
  const r = spawnSync(process.execPath, [KONTROL], { encoding: 'utf8', cwd: kok });
  assert.equal(r.status, 0, r.stdout + r.stderr);
  assert.doesNotMatch(r.stdout, /2026-09-06-pms-faz1/,
    'Tarihi PMS migrationlari varsayilan kapsamda olmamali');
});
