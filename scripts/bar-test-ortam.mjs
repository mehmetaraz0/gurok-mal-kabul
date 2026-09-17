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
