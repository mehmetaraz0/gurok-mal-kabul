// ===========================================================================
// STOK GUNCELLEME TARIHI TESTLERI — izole, uretime BAGLANMAZ
// ===========================================================================
// Ne kanitlar:
//   0. Izole ortamdaki fonksiyonlar URETIM govdesiyle birebir ayni
//      (md5(prosrc) 2026-09-17 teshisindeki degerlere esit)
//   1. Uretim govdesiyle hata yeniden uretilir: UPDATE yollari tarihi yazmaz
//   2. Migration AYNEN uygulanir (--single-transaction, uretim kanalinin kipi)
//   3. Sonra: her UPDATE yolu tarihi now() yapar; dokunulmayan satir eski
//      tarihini korur; hata veren cagri tarihi de geri alir
//   4. Is mantigi degismez: ayni senaryonun miktar sonuclari oncesiyle AYNI
//   5. imza / donus tipi / SECURITY / search_path / ACL degismez
//   6. Ikinci uygulama idempotent
//   7. Govde olcumden farkliysa (or. baska bir migration degistirdiyse),
//      ACL beklenmedikse ya da sutunda UPDATE yetkisi yoksa migration DURUR
//      ve hicbir seyi EZMEZ; son durumun neden gerekli oldugu da gosterilir
//
// Ortam: tek kullanimlik postgres:17 konteyneri, veri tmpfs'te, ag yok.
// ===========================================================================
import { spawnSync } from 'node:child_process';
import { readFileSync } from 'node:fs';
import { setTimeout as bekle } from 'node:timers/promises';
// Govdeler uretimin tek kanonik kopyasindan gelir; burada YENIDEN YAZILMAZ.
import { EKLE_GOVDE, URETIM_RPC_SEMA, OTEL_ID_TIPI, MD5_BEKLENEN } from './stok-rpc-govde.mjs';

const kok = new URL('..', import.meta.url).pathname.replace(/^\/([A-Za-z]:)/, '$1');
const MIG = readFileSync(kok + 'docs/kurulum/2026-09-17-stok-guncelleme-tarihi.sql', 'utf8');
const PG = 'stok-gt-test-db';
const ESKI = '2026-07-09 07:23:10+00';

let ok = 0;
let fail = 0;
function sonuc(gecti, ad, ek) {
  console.log((gecti ? 'OK   ' : 'FAIL ') + ad + (ek ? ' — ' + ek : ''));
  if (gecti) ok++; else fail++;
}

const d = (a, girdi) => spawnSync('docker', a, { input: girdi, encoding: 'utf8', timeout: 600000, maxBuffer: 64 * 1024 * 1024 });
const psql = (db, sql, ekArg = []) => d(['exec', '-i', PG, 'psql', '-X', '-U', 'postgres', '-d', db,
  '-v', 'ON_ERROR_STOP=1', '-q', ...ekArg], sql);
const tek = (db, sql) => {
  const r = d(['exec', '-i', PG, 'psql', '-X', '-U', 'postgres', '-d', db, '-At', '-v', 'ON_ERROR_STOP=1'], sql);
  if (r.status !== 0) throw new Error(r.stderr);
  return r.stdout.trim();
};
const temizle = () => spawnSync('docker', ['rm', '-f', PG]);

const SEMA = (ekleGovde = EKLE_GOVDE) => `
  do $r$ begin
    if not exists (select 1 from pg_roles where rolname = 'anon') then create role anon nologin; end if;
    if not exists (select 1 from pg_roles where rolname = 'authenticated') then create role authenticated nologin; end if;
    if not exists (select 1 from pg_roles where rolname = 'service_role') then create role service_role nologin; end if;
  end $r$;
  create schema if not exists extensions;
  ${OTEL_ID_TIPI}
  create table public.stok (
    id uuid primary key default gen_random_uuid(),
    urun_kodu text not null, depo_kodu text not null, otel_id public.otel_id not null,
    miktar numeric(12,3) not null default 0,
    guncelleme_tarihi timestamptz not null default now(),
    unique (urun_kodu, depo_kodu));
${URETIM_RPC_SEMA(ekleGovde)}
  grant select, insert, update on public.stok to authenticated, service_role;
`;

const TOHUM = `
  truncate public.stok;
  insert into public.stok (urun_kodu, depo_kodu, otel_id, miktar, guncelleme_tarihi) values
    ('YIY01000002', '810_100',    '810',  60,  '${ESKI}'),
    ('YIY01000002', '810_CMM201', '810', 165,  '${ESKI}'),
    ('A', '810_100', '810', 5,   '${ESKI}'),
    ('B', '810_100', '810', 50,  '${ESKI}'),
    ('C', '810_100', '810', 7,   '${ESKI}'),
    ('DOKUNULMAZ', '810_100', '810', 9, '${ESKI}');
`;

// Her adim ayri islem (ayri psql cagrisi) — now() islem basi zamani oldugu icin.
// Adimlar authenticated rolüyle kosar: fonksiyonlar SECURITY INVOKER, istemci
// uretimde bu rolle cagirir. Superuser ile kosmak sutun yetkisi sorununu gizlerdi.
const SENARYO = [
  ["ekle +10 (update yolu)",           "select public.stok_ekle('A', '810_100', '810', 10)"],
  ["ekle -999 (update yolu, 0'a kirp)", "select public.stok_ekle('B', '810_100', '810', -999)"],
  ["ekle yeni satir (insert yolu)",     "select public.stok_ekle('YENI', '810_100', '810', 4)"],
  ["transfer 60 (duman testi)",         "select public.stok_transfer('YIY01000002', '810_100', '810_CMM201', '810', 60)"],
  ["transfer yeni hedef (insert yolu)", "select public.stok_transfer('C', '810_100', '811_100', '811', 3)"],
];

function senaryoKos(db) {
  psql(db, TOHUM);
  const baslangic = tek(db, 'select now()');
  for (const [ad, sql] of SENARYO) {
    const r = psql(db, 'set role authenticated;\n' + sql);
    if (r.status !== 0) throw new Error(ad + ': ' + r.stderr);
  }
  // Hata veren transfer: gecersiz otel enum'u — tamami geri alinmali.
  const hata = psql(db, "set role authenticated;\nselect public.stok_transfer('DOKUNULMAZ', '810_100', '810_YOK', 'GECERSIZ', 1)");
  const satirlar = tek(db, `select urun_kodu || '|' || depo_kodu || '|' || miktar || '|' ||
      case when guncelleme_tarihi >= '${baslangic}'::timestamptz then 'YENI' else 'ESKI' end
    from public.stok order by urun_kodu, depo_kodu`).split('\n');
  const m = {}; const t = {};
  for (const s of satirlar) { const [u, dp, mk, tr] = s.split('|'); m[u + '@' + dp] = mk; t[u + '@' + dp] = tr; }
  return { m, t, hataReddedildi: hata.status !== 0 };
}

const kimlik = (db) => tek(db, `select string_agg(format('%s|%s|%s|%s|%s', oid::regprocedure,
    prorettype::regtype, prosecdef, proconfig, proacl), E'\\n' order by proname)
  from pg_proc where pronamespace = 'public'::regnamespace and proname in ('stok_ekle','stok_transfer')`);

const md5ler = (db) => tek(db, `select string_agg(proname || '=' || md5(prosrc), ',' order by proname)
  from pg_proc where pronamespace = 'public'::regnamespace and proname in ('stok_ekle','stok_transfer')`);

const migUygula = (db) => psql(db, MIG, ['--single-transaction']);

async function main() {
  temizle();
  d(['run', '--detach', '--rm', '--name', PG, '--network', 'none', '--tmpfs', '/var/lib/postgresql/data',
    '-e', 'POSTGRES_HOST_AUTH_METHOD=trust', 'postgres:17']);
  for (let i = 0; i < 60; i++) {
    if (spawnSync('docker', ['exec', PG, 'pg_isready', '-U', 'postgres']).status === 0) break;
    await bekle(1000);
  }
  await bekle(1500);

  try {
    // ---------------- ana veritabani ----------------
    d(['exec', PG, 'createdb', '-U', 'postgres', 'ana']);
    const kurR = psql('ana', SEMA());
    if (kurR.status !== 0) throw new Error('Sema kurulamadi: ' + kurR.stderr);

    const olculen = MD5_BEKLENEN;
    sonuc(md5ler('ana') === olculen, '0. izole govdeler uretimle birebir (md5)', md5ler('ana'));

    const once = senaryoKos('ana');
    const kimlikOnce = kimlik('ana');
    sonuc(once.t['A@810_100'] === 'ESKI' && once.t['B@810_100'] === 'ESKI'
      && once.t['YIY01000002@810_100'] === 'ESKI' && once.t['YIY01000002@810_CMM201'] === 'ESKI',
      '1. HATA YENIDEN URETILDI: uretim govdesinde update yollari tarihi yazmiyor',
      JSON.stringify(once.t));

    const u1 = migUygula('ana');
    sonuc(u1.status === 0, '2. migration aynen uygulandi', u1.status === 0 ? '' : u1.stderr.slice(-400));

    const sonra = senaryoKos('ana');
    const guncellenmeli = ['A@810_100', 'B@810_100', 'YENI@810_100', 'YIY01000002@810_100',
      'YIY01000002@810_CMM201', 'C@810_100', 'C@811_100'];
    const eksik = guncellenmeli.filter(k => sonra.t[k] !== 'YENI');
    sonuc(eksik.length === 0, '3a. tum yazilan satirlarda guncelleme_tarihi = now()', eksik.join(',') || 'hepsi YENI');
    sonuc(sonra.t['DOKUNULMAZ@810_100'] === 'ESKI', '3b. dokunulmayan satir eski tarihini korur');
    sonuc(sonra.hataReddedildi && !('DOKUNULMAZ@810_YOK' in sonra.m) && sonra.m['DOKUNULMAZ@810_100'] === '9.000',
      '3c. hata veren transfer reddedildi ve tamamen geri alindi (tarih dahil)');

    sonuc(JSON.stringify(once.m) === JSON.stringify(sonra.m), '4. miktar sonuclari oncesiyle AYNI',
      JSON.stringify(sonra.m));
    sonuc(sonra.m['YIY01000002@810_100'] === '0.000' && sonra.m['YIY01000002@810_CMM201'] === '225.000',
      '4b. duman testi degerleri: 60->0, 165->225');

    sonuc(kimlik('ana') === kimlikOnce, '5. imza/donus/SECURITY/search_path/ACL degismedi', kimlik('ana').replace(/\n/g, ' ;; '));

    const u2 = migUygula('ana');
    sonuc(u2.status === 0 && /zaten guncelleme_tarihi/.test(u2.stderr), '6. ikinci uygulama idempotent',
      u2.stderr.trim().slice(-200));
    console.log('     yeni govde md5: ' + md5ler('ana'));

    // ---------------- sabotaj: govde olcumden farkli ----------------
    d(['exec', PG, 'createdb', '-U', 'postgres', 'sabotaj_govde']);
    const baskaGovde = EKLE_GOVDE.replace('begin\r\n', 'begin\r\n  perform 1; -- baska migration degisikligi\r\n');
    psql('sabotaj_govde', SEMA(baskaGovde));
    const md5Once = md5ler('sabotaj_govde');
    const s1 = migUygula('sabotaj_govde');
    sonuc(s1.status !== 0 && /olcumunden farkli/.test(s1.stderr) && md5ler('sabotaj_govde') === md5Once,
      '7a. degismis govde: migration DURDU, govde EZILMEDI');

    // ---------------- sabotaj: ACL beklenmedik ----------------
    d(['exec', PG, 'createdb', '-U', 'postgres', 'sabotaj_acl']);
    psql('sabotaj_acl', SEMA() + 'grant execute on function public.stok_transfer(text,text,text,text,numeric) to anon;');
    const s2 = migUygula('sabotaj_acl');
    sonuc(s2.status !== 0 && /EXECUTE ACL beklenen halde degil/.test(s2.stderr)
      && md5ler('sabotaj_acl') === olculen, '7b. beklenmedik ACL: migration DURDU, hicbir sey degismedi');

    // ---------------- sabotaj: sutun bazli UPDATE yetkisi ----------------
    // Risk gercek mi? Once onkosulun durdurdugunu, sonra onkosul olmasaydi
    // yeni govdenin authenticated cagrisini kiracagini goster.
    d(['exec', PG, 'createdb', '-U', 'postgres', 'sabotaj_kolon']);
    psql('sabotaj_kolon', SEMA() + `
      revoke update on public.stok from authenticated;
      grant update (miktar) on public.stok to authenticated;
      insert into public.stok (urun_kodu, depo_kodu, otel_id, miktar) values ('A', '810_100', '810', 5);`);
    const s3 = migUygula('sabotaj_kolon');
    sonuc(s3.status !== 0 && /UPDATE yetkisine sahip degil/.test(s3.stderr) && md5ler('sabotaj_kolon') === olculen,
      '7c. sutun yetkisi kisitli: migration DURDU, hicbir sey degismedi');
    const fonksiyonBolumu = MIG.slice(MIG.indexOf('create or replace function public.stok_ekle'),
      MIG.indexOf('-- 2) ACL'));
    psql('sabotaj_kolon', fonksiyonBolumu);
    const kirik = psql('sabotaj_kolon', "set role authenticated;\nselect public.stok_ekle('A', '810_100', '810', 1)");
    sonuc(kirik.status !== 0 && /permission denied/.test(kirik.stderr),
      '7d. (onkosulun gerekcesi) onkosulsuz yeni govde bu yetkide stok_ekle yi kirardi',
      kirik.stderr.trim().split('\n')[0]);
  } finally {
    temizle();
  }

  console.log(`\n${ok} OK / ${fail} FAIL`);
  process.exitCode = fail ? 1 : 0;
}

main().catch((e) => { console.error(e); temizle(); process.exitCode = 1; });
