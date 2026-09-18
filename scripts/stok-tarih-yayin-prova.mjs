// ===========================================================================
// STOK TARIH YAYINI — URETIM DOKUMU UZERINDE PROVA  ·  uretime BAGLANMAZ
// ===========================================================================
// Yayin gunu uretimde calisacak SQL dosyalarini, uretimin sema dokumu
// yuklenmis tek kullanimlik bir postgres'te AYNI SIRAYLA calistirir:
//
//   T0 anlik goruntu -> duman hazirligi -> MIGRATION -> T1 anlik goruntu
//
// Kanitlar:
//   1. Salt-okuma dosyalarinin hepsi hatasiz calisiyor (sutun/tablo adi
//      yanlissa ON_ERROR_STOP yayin anini yarida keserdi)
//   2. Migration, dokumdeki GERCEK uretim govdeleri uzerinde onkosullarini
//      gecip uygulaniyor (md5 / ACL / sutun yetkisi)
//   3. Migration hicbir satira dokunmuyor (T0 ve T1 parmak izi ayni)
//   4. T1 fonksiyon durumu: tarih_duzeltmesi=t, bar_a1_izi=f
//
// Kullanim: node scripts/stok-tarih-yayin-prova.mjs [dokum.sql]
// Varsayilan dokum: C:\Users\USER\ERP-Yedek\2026-09-13-post-faz2-sema-dokumu.sql
// Dokum SEMA icindir (veri yok); tablolar bos, sorgular yine de tam calisir.
// ===========================================================================
import { spawnSync } from 'node:child_process';
import { readFileSync, existsSync } from 'node:fs';
import { setTimeout as bekle } from 'node:timers/promises';
import { goruntuOku, karsilastir } from './stok-tarih-yayin-karsilastir.mjs';

const kok = new URL('..', import.meta.url).pathname.replace(/^\/([A-Za-z]:)/, '$1');
const DOKUM = process.argv[2] || 'C:/Users/USER/ERP-Yedek/2026-09-13-post-faz2-sema-dokumu.sql';
const PG = 'stok-tarih-prova-db';
const DB = 'prova';

let ok = 0, fail = 0;
function sonuc(gecti, ad, ek) {
  console.log((gecti ? 'OK   ' : 'FAIL ') + ad + (ek ? ' — ' + ek : ''));
  if (gecti) ok++; else fail++;
}
const d = (a, girdi) => spawnSync('docker', a, { input: girdi, encoding: 'utf8', timeout: 600000, maxBuffer: 64 * 1024 * 1024 });
const psql = (sql, ekArg = []) => d(['exec', '-i', PG, 'psql', '-X', '-U', 'postgres', '-d', DB, ...ekArg], sql);
const dosya = (yol) => readFileSync(kok + yol, 'utf8');
const temizle = () => spawnSync('docker', ['rm', '-f', PG]);

// sql-uygula.ps1 -SaltOkuma ile ayni: ON_ERROR_STOP, tek islem sarmalayicisi YOK.
const saltOku = (yol) => psql(dosya(yol), ['-v', 'ON_ERROR_STOP=1']);
// sql-uygula.ps1 (uygulama kipi) ile ayni: --single-transaction + ON_ERROR_STOP.
const uygula = (yol) => psql(dosya(yol), ['--single-transaction', '-v', 'ON_ERROR_STOP=1']);

const parmakIzi = (cikti) => (cikti.match(/\n\s*(\d+)\s*\|\s*([0-9a-f]{32}|)\s*\|/) || [])[0] || '';

async function main() {
  if (!existsSync(DOKUM)) { console.error('Dokum yok: ' + DOKUM); process.exit(1); }
  temizle();
  d(['run', '--detach', '--rm', '--name', PG, '--network', 'none', '--tmpfs', '/var/lib/postgresql/data',
    '-e', 'POSTGRES_HOST_AUTH_METHOD=trust', 'postgres:17']);
  for (let i = 0; i < 60; i++) {
    if (spawnSync('docker', ['exec', PG, 'pg_isready', '-U', 'postgres']).status === 0) break;
    await bekle(1000);
  }
  await bekle(1500);

  try {
    d(['exec', PG, 'createdb', '-U', 'postgres', DB]);
    const shim = psql(dosya('scripts/supabase-shim.sql'), ['-v', 'ON_ERROR_STOP=1']);
    if (shim.status !== 0) throw new Error('shim yuklenemedi: ' + shim.stderr.slice(-400));
    const dk = psql(readFileSync(DOKUM, 'utf8'));
    // dokum-dogrula.mjs ile ayni kural: tek zararsiz hata "schema public already exists"
    const hatalar = (dk.stderr || '').split('\n').filter((s) => /ERROR/.test(s))
      .filter((s) => !/schema "public" already exists/.test(s));
    sonuc(hatalar.length === 0, '0. uretim sema dokumu yuklendi', hatalar.length ? hatalar.slice(0, 3).join(' | ') : DOKUM.split(/[\\/]/).pop());

    // Dokum bos tablo getirir; bos tabloda "T0 = T1" bir sey kanitlamaz.
    // Eski tarihli birkac satir: migration bunlara DOKUNMAMALI.
    // stok.urun_kodu -> urunler(kod) yabanci anahtari var: once urunler.
    const tohum = psql(`insert into public.urunler (kod, ad, birim) values
      ('PROVA1', 'Prova urunu 1', 'KG'), ('PROVA2', 'Prova urunu 2', 'ADET');
    insert into public.stok (urun_kodu, depo_kodu, otel_id, miktar, guncelleme_tarihi) values
      ('PROVA1', '810_100', '810', 60, '2026-07-09 07:23:10+00'),
      ('PROVA1', '810_CMM201', '810', 165, '2026-07-17 17:31:58+00'),
      ('PROVA2', '811_300', '811', 5, '2026-07-31 18:57:18+00');`, ['-v', 'ON_ERROR_STOP=1']);
    sonuc(tohum.status === 0, '0b. prova satirlari eklendi (izole veritabani)', tohum.status ? tohum.stderr.slice(-200) : '3 satir');

    const t0 = saltOku('docs/kurulum/2026-09-18-stok-tarih-yayin-anlik.sql');
    sonuc(t0.status === 0, '1a. T0 anlik goruntu hatasiz', t0.status ? t0.stderr.slice(-300) : '');
    sonuc(/\|\s*t\s*\|\s*f\s*\|\s*f\s*\|/.test(t0.stdout),
      '1b. T0: govdeler olcumle ayni, tarih duzeltmesi yok, bar A1 izi yok');

    const hz = saltOku('docs/kurulum/2026-09-18-stok-tarih-duman-hazirlik.sql');
    sonuc(hz.status === 0, '1c. duman hazirlik sorgusu hatasiz', hz.status ? hz.stderr.slice(-300) : '');

    for (const yol of ['docs/kurulum/2026-09-17-stok-guncelleme-tarihi-onkosul.sql']) {
      const r = saltOku(yol);
      sonuc(r.status === 0, '1d. ' + yol.split('/').pop() + ' hatasiz', r.status ? r.stderr.slice(-300) : '');
    }

    const m = uygula('docs/kurulum/2026-09-17-stok-guncelleme-tarihi.sql');
    sonuc(m.status === 0, '2. migration GERCEK uretim govdeleri uzerinde uygulandi',
      m.status ? m.stderr.slice(-400) : '');

    const t1 = saltOku('docs/kurulum/2026-09-18-stok-tarih-yayin-anlik.sql');
    sonuc(t1.status === 0, '3a. T1 anlik goruntu hatasiz', t1.status ? t1.stderr.slice(-300) : '');
    sonuc(/\b3\s*\|\s*[0-9a-f]{32}/.test(parmakIzi(t0.stdout)) && parmakIzi(t0.stdout) === parmakIzi(t1.stdout),
      '3b. migration hicbir satira dokunmadi (T0 = T1 parmak izi)', parmakIzi(t1.stdout).trim());
    const satirlar = (t1.stdout.match(/^\s*stok_(ekle|transfer)\s*\|.*$/gm) || []);
    sonuc(satirlar.length === 2 && satirlar.every((s) => /\|\s*f\s*\|\s*t\s*\|\s*f\s*\|/.test(s)),
      '4. T1: olcumle_ayni=f, tarih_duzeltmesi=t, bar_a1_izi=f (iki fonksiyon)', satirlar.length + ' satir');

    // Gercek SQL ciktisi karsilastiricinin ayristiricisiyla uyusuyor mu?
    const k = karsilastir([goruntuOku(t0.stdout, 'T0'), goruntuOku(t1.stdout, 'T1')],
      { adimlar: [{ ad: 'T0' }, { ad: 'T1', tur: 'migration' }] });
    const t0g = goruntuOku(t0.stdout, 'T0');
    sonuc(t0g.satir.size === 3 && ['GECTI', 'BILGI'].includes(k.genel),
      '3c. karsilastirici gercek T0/T1 ciktisini okudu, karar: ' + k.genel,
      t0g.satir.size + ' satir, ' + Object.keys(t0g.fonk).length + ' fonksiyon');

    const ikinci = uygula('docs/kurulum/2026-09-17-stok-guncelleme-tarihi.sql');
    sonuc(ikinci.status === 0 && /zaten guncelleme_tarihi/.test(ikinci.stderr),
      '5. migration ikinci kez uygulanirsa zararsiz (idempotent)');
  } catch (e) {
    sonuc(false, 'beklenmeyen hata', e.message);
  } finally {
    temizle();
  }
  console.log(`\nYAYIN PROVASI SONUC: ${ok} OK / ${fail} FAIL`);
  process.exitCode = fail ? 1 : 0;
}
main();
