// ===========================================================================
// PMS canliya gecis provasinin KENDI testi — YP-2 kalici negatif kontrolu
// ===========================================================================
// Bulgu: eksik sema dokumu "atlandi" sayilip ust sonuc yanlislikla GECTI
// olabiliyordu. Ozellikle `mevcut` taban makineye ozel bir yola bagli oldugu
// icin, baska makinede HIC SINANMAYAN taban yayin kaniti gibi gorunurdu.
//
// Bu test GERCEK dokum dosyalarina DOKUNMAZ: yalniz PROVA_DOKUM_* ortam
// degiskeniyle var olmayan bir yol enjekte eder. Docker baslatilmaz, cunku
// kosum dokum kontrolunde durur.
//
// Kullanim: node --test scripts/pms-canliya-gecis-provasi.test.mjs
// ===========================================================================
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { existsSync } from 'node:fs';

const KOK = new URL('..', import.meta.url).pathname.replace(/^\/([A-Za-z]:)/, '$1');
const PROVA = KOK + 'scripts/pms-canliya-gecis-provasi.mjs';
const YOK = 'C:/olmayan-dizin/olmayan-sema-dokumu.sql';
const kos = (ek) => spawnSync(process.execPath, [PROVA],
  { env: { ...process.env, ...ek }, encoding: 'utf8', timeout: 300000 });

test('N1: gercek dokum yolu var ve enjeksiyon onu DEGISTIRMIYOR', () => {
  assert.equal(existsSync(YOK), false, 'enjekte edilen yol gercekten yok olmali');
  const r = spawnSync(process.execPath, ['-e',
    "const s=require('fs').readFileSync(process.argv[1],'utf8');" +
    "process.stdout.write(String(/2026-09-07-post-pms-faz1-sema-dokumu\\.sql/.test(s)" +
    "&& /2026-09-13-post-faz2-sema-dokumu\\.sql/.test(s)));", PROVA], { encoding: 'utf8' });
  assert.equal(r.stdout.trim(), 'true', 'iki gercek dokum yolu dosyada durmali');
});

test('N2: ZORUNLU taban eksikse alt surec ATLAMA koduyla (70) cikar', () => {
  const r = kos({ PROVA_TABAN: 'mevcut', PROVA_DOKUM_MEVCUT: YOK });
  assert.equal(r.status, 70, 'alt surec 70 dondurmeli, 0 degil');
  assert.match(r.stdout, /BASARISIZ mevcut: ZORUNLU sema dokumu yok/);
  assert.match(r.stdout, /GECTI OLAMAZ/);
});

test('N3: iki taban da eksikse UST sonuc GECTI DEMEZ ve cikis 0 olmaz', () => {
  const r = kos({ PROVA_DOKUM_TEMIZ: YOK, PROVA_DOKUM_MEVCUT: YOK });
  assert.notEqual(r.status, 0, 'ust surec 0 ile cikmamali');
  assert.match(r.stdout, /SINANMADI — ZORUNLU TABAN EKSIK/);
  assert.match(r.stdout, /SINANMAYAN: temiz, mevcut/);
  assert.match(r.stdout, /PROVA GECMEDI/);
  assert.doesNotMatch(r.stdout, /^ {2}temiz {3}GECTI$/m, 'atlanmis taban GECTI yazmamali');
  assert.doesNotMatch(r.stdout, /PROVA GECTI/);
});

test('N4: TEK taban eksikse de ust sonuc GECTI DEMEZ (kismi kosum yeterli degil)', () => {
  // Yalniz `mevcut` eksik: `temiz` tabani gercekten kosar (Docker gerekir).
  // Kosum uzun surdugu icin burada yalniz UST karar dogrulanir.
  const r = kos({ PROVA_DOKUM_MEVCUT: YOK });
  assert.notEqual(r.status, 0, 'bir taban sinanmadiysa ust sonuc basari olmamali');
  assert.match(r.stdout, /SINANMAYAN: mevcut/);
  assert.match(r.stdout, /PROVA GECMEDI/);
  // Pozitif kontrol: atlanmayan taban gercekten olculdu. Sayi alt sinira
  // baglanir ki ilerde kosum sessizce kisalirsa test bunu yakalasin.
  const m = r.stdout.match(/temiz: (\d+) gecti, 0 kaldi/);
  assert.ok(m, 'temiz taban yine de olculmeli');
  assert.ok(Number(m[1]) >= 70, 'temiz tabanda en az 70 olcum beklenir, olculen: ' + m[1]);
});
