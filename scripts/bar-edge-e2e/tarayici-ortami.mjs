#!/usr/bin/env node
// ===========================================================================
// BAR A1 — GERCEK TARAYICI ICIN IZOLE ORTAM (uretime BAGLANMAZ)
// ===========================================================================
// e2eOrtami (A1'li ana DB + GoTrue + PostgREST + musteri DB + Edge Runtime)
// kurulur, ardindan bu calisma kopyasi 127.0.0.1:3300'den sunulur. Yalniz iki
// yapilandirma dosyasi DEGISTIRILIR (uretim adresi/anahtari tarayiciya gitmez):
//   supabase-config.js -> /__ana (ana gecit vekili) + yerel anon JWT
//   bar-config.js      -> /__musteri (musteri gecidi vekili) + yerel anon JWT
// /__giris?kisi=<ad>&hedef=<sayfa> : GoTrue'da gercek parola girisiyle alinan
// erisim anahtarini ve kullanici satirini sessionStorage'a yazar (PIN ekraninin
// yaptigi kayit). PIN ekraninin kendisi A1 kapsaminda degildir, sinanmaz.
// Surec Ctrl+C / kill ile durdurulana kadar calisir; cikista her sey silinir.
// ===========================================================================
import http from 'node:http';
import { readFileSync, existsSync, statSync } from 'node:fs';
import path from 'node:path';
import { e2eOrtami } from './ortam.mjs';
import { kok } from '../bar-test-ortam.mjs';
import { K, M, BAR } from '../bar-a1-tohum.mjs';

const PORT = 3300;
const E = e2eOrtami({ ad: 'bar-tarayici', a1: true });
let kapaniyor = false;
const kapat = () => { if (kapaniyor) return; kapaniyor = true; console.log('temizleniyor...'); E.temizle(); process.exit(0); };
process.on('SIGINT', kapat); process.on('SIGTERM', kapat);

await E.kur();
const sql = (q) => { const r = E.ana.sql(q); if (!r.ok) throw new Error(r.err.slice(-300)); return r.out; };

// Sayim ekrani icin cost_control kullanicisi (stok tam rolu). Test verisi replica rolde.
sql(`set session_replication_role = replica;
  insert into auth.users (id, email) values ('11111111-0000-0000-0000-0000000000c1', 'cc810@test.local');
  insert into public.kullanicilar (id, auth_user_id, ad, rol, otel_id, aktif, rol_id) values
    ('33333333-0000-0000-0000-0000000000c1', '11111111-0000-0000-0000-0000000000c1', 'Cost 810', 'cost_control', '810', true,
     '00000000-0000-0000-0000-00000000b013');
  set session_replication_role = origin;`);
// YALNIZ BU ORTAMDA: sayim tablolarina okuma politikasi. Uretim dokumunde bu
// tablolar authenticated'a kapali (ayri bulgu); politika olmadan sayim ekrani
// hic calismaz ve A1 akisi tarayicida gorulemez.
sql(`create policy test_yalniz_okuma on public.sayim_oturumlari for select to authenticated using (true);
     create policy test_yalniz_okuma on public.sayim_detaylari for select to authenticated using (true);`);

const KISILER = {
  bar810: [K.BAR810.sub, 'bar810@test.local'],
  sef810: [K.SEF810.sub, 'sef810@test.local'],
  cc810: ['11111111-0000-0000-0000-0000000000c1', 'cc810@test.local'],
  depo810: [K.DEPO810.sub, 'depo810@test.local'],
  onburo810: [K.ONBURO810.sub, 'onburo810@test.local'],
  onburomud810: [K.ONBUROMUD810.sub, 'onburomud810@test.local'],
};
for (const [id, email] of Object.values(KISILER)) await E.kullaniciOlustur(id, email);
const yayin = await E.fonksiyon('smooth-service', {}, { 'x-staff-token': await E.girisYap('bar810@test.local') });
if (!yayin.json?.ok) throw new Error('menu yayini: ' + yayin.metin);

const DEGISEN = {
  '/supabase-config.js': `// TEST — yerel izole ana proje (uretim DEGIL)
const SB_URL=location.origin + '/__ana';
const SB_KEY=${JSON.stringify(E.anon)};
const SB_HEADERS = { 'apikey': SB_KEY,
  get Authorization() { const t = (typeof oturumAccessTokenGetir === 'function') ? oturumAccessTokenGetir() : null; return 'Bearer ' + (t || SB_KEY); },
  'Content-Type': 'application/json' };
function sbHeaderlarYenile() {}
`,
  '/bar-config.js': `// TEST — yerel izole musteri projesi (uretim DEGIL)
const CUSTOMER_SB_URL = location.origin + '/__musteri';
const CUSTOMER_ANON_KEY = ${JSON.stringify(E.anon)};
`,
};
const TUR = { '.html': 'text/html; charset=utf-8', '.js': 'text/javascript; charset=utf-8', '.css': 'text/css', '.json': 'application/json',
  '.png': 'image/png', '.svg': 'image/svg+xml', '.ico': 'image/x-icon', '.webmanifest': 'application/manifest+json' };

async function girisSayfasi(kisi, hedef) {
  const k = KISILER[kisi];
  if (!k) return `<p>bilinmeyen kisi: ${kisi}</p>`;
  const token = await E.girisYap(k[1]);
  const kullanici = JSON.parse(sql(`select row_to_json(k) from public.kullanicilar k where k.auth_user_id = '${k[0]}';`));
  return `<!doctype html><meta charset="utf-8"><title>Test girisi</title><script>
sessionStorage.setItem('araz_portal_session', JSON.stringify({ user: ${JSON.stringify(kullanici)},
  accessToken: ${JSON.stringify(token)}, expiry: Date.now() + 30 * 60 * 1000 }));
location.replace(${JSON.stringify(hedef)});
</script>`;
}

http.createServer(async (istek, yanit) => {
  try {
    const u = new URL(istek.url, 'http://127.0.0.1');
    if (u.pathname === '/__giris') {
      yanit.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8', 'Cache-Control': 'no-store' });
      yanit.end(await girisSayfasi(u.searchParams.get('kisi'), u.searchParams.get('hedef') || 'bar-siparis-kuyrugu.html'));
      return;
    }
    // Tarayici bolmesi yalniz bu porta ulasir: iki gecit ayni kaynaktan vekillenir.
    const vekil = [['/__ana', E.P.anaGecit], ['/__musteri', E.P.musGecit]].find(([o]) => u.pathname.startsWith(o + '/'));
    if (vekil) {
      const ileri = http.request({ host: '127.0.0.1', port: vekil[1], method: istek.method,
        path: istek.url.slice(vekil[0].length), headers: { ...istek.headers, host: '127.0.0.1:' + vekil[1] } }, (h) => {
        yanit.writeHead(h.statusCode, h.headers); h.pipe(yanit); });
      ileri.on('error', (e) => { yanit.writeHead(502); yanit.end('vekil: ' + e.message); });
      istek.pipe(ileri); return;
    }
    if (DEGISEN[u.pathname]) {
      yanit.writeHead(200, { 'Content-Type': TUR['.js'], 'Cache-Control': 'no-store' });
      yanit.end(DEGISEN[u.pathname]); return;
    }
    const dosya = path.join(kok, decodeURIComponent(u.pathname === '/' ? '/index.html' : u.pathname));
    if (!dosya.startsWith(path.normalize(kok)) || !existsSync(dosya) || statSync(dosya).isDirectory()) {
      yanit.writeHead(404); yanit.end('yok'); return;
    }
    yanit.writeHead(200, { 'Content-Type': TUR[path.extname(dosya)] || 'application/octet-stream', 'Cache-Control': 'no-store' });
    yanit.end(readFileSync(dosya));
  } catch (e) { yanit.writeHead(500); yanit.end(String(e.message)); }
}).listen(PORT, '127.0.0.1', () => {
  console.log(`HAZIR http://127.0.0.1:${PORT}  (menu: /bar-menu.html?t=tok-810-a)  giris: /__giris?kisi=bar810|sef810|cc810|depo810&hedef=<sayfa>`);
  console.log(`BAR ${BAR}; VISKI ${M.VISKI}`);
});
