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

function denetle(sqlMetni, ad) {
  const yol = path.join(gecici, ad + '.sql');
  fs.writeFileSync(yol, sqlMetni, 'utf8');
  const r = spawnSync(process.execPath, [KONTROL, yol], { encoding: 'utf8', cwd: kok });
  return { kod: r.status, cikti: (r.stdout || '') + (r.stderr || '') };
}

// Metni degistirir ve degisikligin GERCEKTEN oldugunu dogrular.
function boz(metin, eski, yeni, beklenenAdet = 1) {
  const adet = metin.split(eski).length - 1;
  assert.equal(adet, beklenenAdet,
    'SABOTAJ KURULAMADI: "' + eski.slice(0, 60) + '" ' + adet + ' kez bulundu, ' +
    beklenenAdet + ' bekleniyordu. Sablon degistiyse testi guncelle.');
  return metin.split(eski).join(yeni);
}

const sablon = fs.readFileSync(SABLON, 'utf8');

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
    'revoke all on function public.ornek_kapat(uuid) from public, anon;',
    '-- (sabotaj: revoke silindi)');
  bozuk = boz(bozuk,
    'grant execute on function public.ornek_kapat(uuid) to authenticated, service_role;',
    '-- (sabotaj: grant silindi)');
  const r = denetle(bozuk, 'j-fonksiyon-acl-yok');
  assert.equal(r.kod, 0, 'UYARI varsayilan olarak cikis kodunu bozmamali');
  assert.match(r.cikti, /R9-FONKSIYON-ACL-KARARI-YOK\s+ornek_kapat/);

  // --uyari-da-hata ile bloke edilebilmeli
  const yol = path.join(gecici, 'j-fonksiyon-acl-yok.sql');
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
