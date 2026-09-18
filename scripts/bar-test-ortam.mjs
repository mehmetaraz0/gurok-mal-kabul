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

// Dokumden (2026-09-13) SONRA uretime uygulanan migration'lar, uygulandiklari
// sirayla. Taban bunlari dokumun ustune kurar; boylece yeni bir uretim dokumu
// almadan (parola gerektirir) bugunku uretim temsil edilir.
export const URETIM_SONRASI = [
  'docs/kurulum/2026-09-14-stok-liste-ozet.sql',          // 2026-09-15 yayini
  'docs/kurulum/2026-09-17-stok-guncelleme-tarihi.sql',   // 2026-09-18 yayini
];

// 2026-09-18 uretim olcumu (yayin T1, sql-uygula ile): stok RPC govdelerinin
// md5(prosrc) degeri. Taban bunu tutturamazsa uretimi temsil etmiyor demektir
// ve kurulum DURUR. md5 satir sonuna duyarlidir: migration dosyasi Windows
// calisma kopyasinda CRLF'dir ve uretime de oyle uygulanmistir.
export const URETIM_STOK_MD5 = {
  stok_ekle: '43ec3cfcd28b9a8cb9e5d8b3ed03b47d',
  stok_transfer: '8dd27c19ac2da9629a53dae9861766ba',
};

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
  // Uretim kanaliyla ayni kip: sql-uygula.ps1 --single-transaction + ON_ERROR_STOP.
  // Enum'a deger ekleme gibi "ayni islemde kullanilamaz" kurallari yalniz bu
  // kipte dogru sinanir. Metin de dogrudan verilebilir (negatif kontroller icin).
  const uygulaTekIslem = (dosyaVeyaMetin, { metin = false } = {}) => sonucla(d(
    psqlArg(['-q', '-At', '--single-transaction', '-v', 'ON_ERROR_STOP=1']),
    metin ? dosyaVeyaMetin : readFileSync(kok + dosyaVeyaMetin, 'utf8')));

  // Kurulumun olculen ozeti: testler raporda gostersin diye.
  const kurulumBilgisi = { dokumHata: null, dokumZararsiz: null, stokMd5: null };

  async function kur({ onceki = [], uretimSonrasi = true } = {}) {
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

    if (uretimSonrasi) {
      for (const m of URETIM_SONRASI) zorunlu(uygula(m), m);
      const md5 = sql(`select proname || '=' || md5(prosrc) from pg_proc
        where pronamespace = 'public'::regnamespace and proname in ('stok_ekle','stok_transfer') order by 1;`).out;
      const beklenen = Object.entries(URETIM_STOK_MD5).map(([k, v]) => k + '=' + v).join('\n');
      kurulumBilgisi.stokMd5 = md5;
      if (md5 !== beklenen) {
        throw new Error('Taban uretimi temsil etmiyor — stok RPC md5 farkli:\n  kurulan : '
          + md5.replace(/\n/g, ' ') + '\n  beklenen: ' + beklenen.replace(/\n/g, ' '));
      }
    }
    // Uretim-sonrasi migration'lar zaten uygulandiysa tekrar uygulanmaz.
    for (const m of onceki) {
      if (uretimSonrasi && URETIM_SONRASI.includes(m)) continue;
      zorunlu(uygula(m), m);
    }
    zorunlu(sql(readFileSync(kok + 'scripts/bar-test-tohum.sql', 'utf8')), 'tohum');
  }

  return { kur, uygula, uygulaTekIslem, sql, kimlikle, paralel, temizle, kurulumBilgisi };
}
