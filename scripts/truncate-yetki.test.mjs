// ===========================================================================
// TRUNCATE YETKI BULGUSU — OLCUM (IZOLE; uretime BAGLANMAZ)
// ===========================================================================
// Bulgu: uretim sema dokumunde cok sayida tablo 'GRANT ALL ... TO authenticated'
// almis. GRANT ALL TRUNCATE'i kapsar ve **TRUNCATE RLS'i DINLEMEZ** — yani RLS
// ile korundugu varsayilan tablo tek komutla bosaltilabilir.
//
// BU TEST IKI SORUYU AYRI OLCER (kullanici karari 2026-09-20):
//   (A) VERITABANI YETKISI  : rolde hak var mi ve gercekten ise yariyor mu?
//   (B) API ULASILABILIRLIGI: bugunku API yuzeyinden (PostgREST) kullanilabilir mi?
//
// Uretimde HICBIR DENEME YAPILMAZ; butun denemeler bu izole kopyadadir.
// ===========================================================================
import { barOrtami, yerelJwt } from './bar-test-ortam.mjs';
import { K } from './bar-a1-tohum.mjs';

const A1 = 'docs/kurulum/2026-09-18-bar-a1-guvenlik.sql';
const PORT = 3241;

const O = barOrtami({ ad: 'truncate-yetki', ag: 'truncate-yetki-net' });
let ok = 0, fail = 0;
const sonuc = (g, ad, ek) => { console.log((g ? 'OK   ' : 'FAIL ') + ad + (ek ? ' — ' + ek : '')); if (g) ok++; else fail++; };
const tek = (sql) => O.sql(sql).out;
const q = (kimlik, sql) => O.kimlikle(kimlik, sql);

try {
  await O.kur();

  // ---------------- (A) VERITABANI YETKISI ----------------
  const truncTablo = tek(`select count(*) from information_schema.role_table_grants
                           where table_schema='public' and privilege_type='TRUNCATE' and grantee='authenticated';`);
  sonuc(Number(truncTablo) > 0,
    'A1 authenticated rolunde TRUNCATE hakki olan tablolar VAR', truncTablo + ' tablo');

  const rlsli = tek(`select count(*) from information_schema.role_table_grants g
                      join pg_class c on c.oid = ('public.' || quote_ident(g.table_name))::regclass
                     where g.table_schema='public' and g.privilege_type='TRUNCATE'
                       and g.grantee='authenticated' and c.relrowsecurity;`);
  sonuc(Number(rlsli) > 0,
    'A2 bunlarin bir kismi RLS ILE KORUNUYOR sanilan tablolar', rlsli + ' tablo RLS acik');

  // Gercekten ise yariyor mu? IZOLE kopyada olculur.
  const hedef = tek(`select g.table_name from information_schema.role_table_grants g
                      join pg_class c on c.oid = ('public.' || quote_ident(g.table_name))::regclass
                     where g.table_schema='public' and g.privilege_type='TRUNCATE'
                       and g.grantee='authenticated' and c.relrowsecurity
                     order by g.table_name limit 1;`);
  const secDeneme = q(K.DEPO810, `select count(*) from public.${hedef};`);
  const truncDeneme = q(K.DEPO810, `truncate table public.${hedef};`);
  sonuc(truncDeneme.ok,
    `A3 RLS acik bir tabloda (${hedef}) TRUNCATE GERCEKTEN CALISIYOR — RLS durdurmuyor`,
    truncDeneme.ok ? 'komut kabul edildi' : (truncDeneme.err || '').split('\n').pop());
  sonuc(!secDeneme.ok || true, 'A4 (bilgi) ayni kullanicinin okuma sonucu', secDeneme.ok ? secDeneme.out + ' satir' : 'okuma kapali');

  // Karsilastirma: DELETE RLS'e TABIDIR (politika yoksa reddedilir)
  const delDeneme = q(K.DEPO810, `delete from public.${hedef};`);
  sonuc(true, 'A5 (karsilastirma) ayni tabloda DELETE',
    delDeneme.ok ? 'RLS politikasi izin verdiyse gecti' : (delDeneme.err || '').split('\n').pop());

  // ---------------- (B) API ULASILABILIRLIGI ----------------
  const rolBilgi = tek(`select rolname||'='||rolcanlogin::text from pg_roles
                         where rolname in ('anon','authenticated') order by rolname;`);
  sonuc(/anon=f/.test(rolBilgi) && /authenticated=f/.test(rolBilgi),
    'B1 anon/authenticated rolleri DOGRUDAN BAGLANAMAZ (LOGIN yok) — hak yalniz API gecidiyle ustlenilir',
    rolBilgi.replace(/\n/g, ' '));

  const dinamik = tek(`select count(*) from pg_proc p
                        where p.pronamespace='public'::regnamespace and p.prosrc ~* '(^|\\s)execute\\s'
                          and (has_function_privilege('anon', p.oid, 'EXECUTE')
                               or has_function_privilege('authenticated', p.oid, 'EXECUTE'));`);
  console.log('     (bilgi) disa acik ve govdesinde EXECUTE gecen fonksiyon: ' + dinamik);

  const url = await O.restBaslat({ port: PORT });
  const jwt = yerelJwt('authenticated', K.DEPO810.sub);
  const bas = { apikey: 'x', Authorization: 'Bearer ' + jwt, 'Content-Type': 'application/json' };

  // PostgREST'te TRUNCATE icin HTTP yolu yoktur; TRUNCATE HTTP metodu da yoktur.
  const truncMetot = await fetch(url + '/' + hedef, { method: 'TRUNCATE', headers: bas }).catch((e) => ({ status: -1, hata: String(e.message) }));
  sonuc(truncMetot.status !== 200,
    'B2 API uzerinden TRUNCATE icin yol YOK (PostgREST TRUNCATE metodunu tanimiyor)',
    'http ' + truncMetot.status);

  // RPC ile de cagrilamaz: SQL calistiran genel bir uc yok.
  const rpc = await fetch(url + '/rpc/truncate', { method: 'POST', headers: bas, body: '{}' });
  sonuc(rpc.status === 404, 'B3 genel bir SQL calistirma RPC ucu yok', 'http ' + rpc.status);

  // ---------------- A1 sonrasi: sayim tablolari kapaniyor ----------------
  const a = O.uygulaTekIslem(A1);
  sonuc(a.ok, 'C1 A1 uygulandi', a.ok ? '' : (a.err || '').split('\n').slice(-3).join(' | '));
  if (a.ok) {
    const sonra = tek(`select (has_table_privilege('authenticated','public.sayim_oturumlari','truncate')
                            or has_table_privilege('authenticated','public.sayim_detaylari','truncate'))::text;`);
    sonuc(sonra === 'false' || sonra === 'f',
      'C2 A1 (15c) sayim tablolarinda TRUNCATE hakkini kaldiriyor', 'kalan hak: ' + sonra);
    const kalan = tek(`select count(*) from information_schema.role_table_grants
                        where table_schema='public' and privilege_type='TRUNCATE' and grantee='authenticated';`);
    sonuc(Number(kalan) > 0,
      'C3 GERIYE KALAN tablolarda hak DURUYOR — A1 kapsami disi, ayri is', kalan + ' tablo');
  }
} catch (e) {
  sonuc(false, 'beklenmeyen hata', String(e && e.message || e));
} finally {
  O.temizle();
}
console.log(`\nTRUNCATE YETKI OLCUMU: ${ok} OK / ${fail} FAIL`);
process.exit(fail ? 1 : 0);
