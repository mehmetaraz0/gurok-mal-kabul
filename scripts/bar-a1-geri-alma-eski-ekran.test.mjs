// ===========================================================================
// GERI ALMA SONRASI ESKI BAR EKRANI — GERCEK PERSONEL KIMLIGIYLE (IZOLE)
// ===========================================================================
// SORU (kullanici karari 2026-09-20): A1 geri alindiginda eski bar akisi
// GERCEKTEN calisiyor mu? A1, uc bar tablosunda yazma haklarini ve yazma
// politikalarini kaldiriyor; geri alma bunlari bilerek geri VERMIYOR. Eger bu
// yuzden eski ekran listeleyemiyor ya da gerekli islemi yapamiyorsa, geri donus
// "tamam" sayilamaz.
//
// YONTEM: uretim dokumu -> A1 -> GERI ALMA -> ardindan ORIGIN/MAIN'deki ESKI
// ekran kaynagi, GERCEK personel JWT'siyle, gercek PostgREST uzerinden kosulur.
// Olculen: listeleme (dogrudan tablo okumasi), siparis olusturma, durum
// guncelleme, teslim, iptal. Ayrica gereksiz haklarin (TRUNCATE/DELETE) ACIK
// OLMADIGI dogrulanir.
// ===========================================================================
import { execSync } from 'node:child_process';
import { mkdtempSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { barOrtami, yerelJwt, kok } from './bar-test-ortam.mjs';
import { barEkranKur } from './bar-ekran-harness.mjs';
import { K, M, BAR, EK_TOHUM } from './bar-a1-tohum.mjs';

const A1 = 'docs/kurulum/2026-09-18-bar-a1-guvenlik.sql';
const GERI_AL = 'docs/kurulum/2026-09-18-bar-a1-guvenlik-geri-al.sql';
const PORT = 3251;

// origin/main'deki ESKI ekran kaynagi
const ESKI = mkdtempSync(path.join(tmpdir(), 'bar-geri-eski-')).replace(/\\/g, '/') + '/';
execSync(`git -C "${kok}" archive origin/main -- "*.html" "*.js" | tar -x -C "${ESKI}"`, { shell: 'bash' });

const O = barOrtami({ ad: 'bar-geri-eski', ag: 'bar-geri-eski-net' });
let ok = 0, fail = 0;
const sonuc = (g, ad, ek) => { console.log((g ? 'OK   ' : 'FAIL ') + ad + (ek ? ' — ' + ek : '')); if (g) ok++; else fail++; };
const tek = (s) => O.sql(s).out;
const bekle = (ms) => new Promise((r) => setTimeout(r, ms));
const hak = (t, h) => tek(`select has_table_privilege('authenticated','public.${t}','${h}')::text;`);

try {
  await O.kur();
  const t = O.sql(EK_TOHUM); if (!t.ok) throw new Error('ek tohum: ' + t.err.slice(-200));

  const a = O.uygulaTekIslem(A1);
  sonuc(a.ok, 'H0 A1 uygulandi', a.ok ? '' : (a.err || '').split('\n').slice(-3).join(' | '));
  if (!a.ok) throw new Error('A1 uygulanamadi');

  // A1 doneminde birkac siparis olussun (geri alma sonrasi listede gorunmeli)
  const s1 = O.kimlikle(K.BAR810,
    `select public.bar_siparis_olustur('810','${BAR}','M1',null,'[{"menu_urun_id":"${M.BIRA}","adet":2}]'::jsonb);`).out;

  const g = O.uygulaTekIslem(GERI_AL);
  sonuc(g.ok, 'H1 geri alma uygulandi', g.ok ? '' : (g.err || '').split('\n').slice(-3).join(' | '));
  if (!g.ok) throw new Error('geri alma uygulanamadi');

  // ---- Geri alma sonrasi ETKIN HAKLAR (olcum, iddia degil) ----
  const haklar = ['bar_siparisleri', 'bar_siparis_kalemleri', 'stok_rezervasyonlari']
    .map((x) => `${x}: select=${hak(x, 'select')} insert=${hak(x, 'insert')} update=${hak(x, 'update')} delete=${hak(x, 'delete')} truncate=${hak(x, 'truncate')}`);
  console.log('     ' + haklar.join('\n     '));

  const url = await O.restBaslat({ port: PORT });
  const jwt = yerelJwt('authenticated', K.BAR810.sub);
  const kullanici = { id: '33333333-0000-0000-0000-000000000810', ad: 'Bar 810', rol: 'bar', otel_id: '810' };
  const yetkiler = { bar_siparis_yonetimi: 'kayit' };
  const eskiEkran = (html) => barEkranKur({ html, restUrl: url, jwt, kullanici, yetkiler, kaynakKok: ESKI });

  // ---- 1) ESKI KUYRUK EKRANI: listeleme (DOGRUDAN tablo okumasi) ----
  const kuyruk = eskiEkran('bar-siparis-kuyrugu.html');
  await bekle(800);
  await kuyruk.calistir('yukle()');
  await bekle(400);
  // Teshis: ayni sorgu once SQL kimligiyle, sonra ham REST ile.
  const sqlSayi = O.kimlikle(K.BAR810, `select count(*) from public.bar_siparisleri;`);
  const hamYol = '/bar_siparisleri?select=*,bar_siparis_kalemleri(adet,menu_urunler(ad))&order=olusturma_zamani.desc';
  const ham = await fetch(url + hamYol, { headers: { apikey: 'x', Authorization: 'Bearer ' + jwt } });
  const hamGovde = (await ham.text()).slice(0, 220);
  console.log(`     TESHIS: sql kimlikle ${sqlSayi.ok ? sqlSayi.out + ' satir' : (sqlSayi.err || '').split('\n').pop()}`
    + ` | rest http ${ham.status} govde ${hamGovde}`);
  // NOT: ekran degiskenleri `let` ile tanimli; vm baglaminda ozellik olarak
  // gorunmezler. Degeri EKRANIN KENDI baglaminda calistirarak okuyoruz.
  const liste = JSON.parse(kuyruk.calistir('JSON.stringify(SIPARISLER)') || '[]');
  sonuc(Array.isArray(liste) && liste.length >= 1 && liste.some((x) => x.id === s1),
    'H2 ESKI kuyruk ekrani gercek personel kimligiyle siparisleri LISTELIYOR (dogrudan tablo okumasi)',
    'satir ' + (liste.length || 0) + ' | son toast: ' + kuyruk.sonToast());
  const kalemVar = liste.some((x) => Array.isArray(x.bar_siparis_kalemleri) && x.bar_siparis_kalemleri.length > 0);
  sonuc(kalemVar, 'H3 gomulu KALEM okumasi da calisiyor (bar_siparis_kalemleri)',
    JSON.stringify(liste[0] || {}).slice(0, 160));
  // Ekran gercekten cizdi mi (bos liste uyarisi degil)?
  const cizim = kuyruk.el('liste').innerHTML || '';
  sonuc(cizim.length > 0 && !/Sipariş yok/i.test(cizim),
    'H3b ekran kartlari CIZIYOR (bos liste mesaji degil)', cizim.slice(0, 120));

  // ---- 2) ESKI GARSON EKRANI: siparis olusturma (RPC yolu) ----
  const garson = eskiEkran('bar-garson.html');
  await bekle(600);
  const oncekiSayi = Number(tek(`select count(*) from public.bar_siparisleri;`));
  garson.calistir(`seciliMasa={token:'tok-810-a',otel_id:'810',depo_id:'${BAR}',masa_adi:'M1'};
                   SEPET={'${M.BIRA}':{adet:1,ad:'Bira',fiyat:0,ucretli:false}};`);
  await garson.calistir('gonder()');
  await bekle(400);
  sonuc(Number(tek(`select count(*) from public.bar_siparisleri;`)) === oncekiSayi + 1,
    'H4 ESKI garson ekrani siparis OLUSTURUYOR (SECURITY DEFINER RPC yolu)', garson.sonToast());

  // ---- 3) ESKI KUYRUK: durum guncelleme / teslim / iptal (RPC yolu) ----
  const d1 = O.kimlikle(K.BAR810, `select public.bar_siparis_durum_guncelle('${s1}','hazirlaniyor');`);
  const d2 = O.kimlikle(K.BAR810, `select public.bar_siparis_durum_guncelle('${s1}','hazir');`);
  const d3 = O.kimlikle(K.BAR810, `select public.bar_siparis_teslim_et('${s1}');`);
  sonuc(d1.ok && d2.ok && d3.ok
     && tek(`select durum::text from public.bar_siparisleri where id='${s1}';`) === 'teslim_edildi',
    'H5 ESKI akis: hazirlaniyor -> hazir -> TESLIM calisiyor',
    [d1, d2, d3].map((x) => x.ok ? 'ok' : (x.err || '').split('\n').pop()).join(' | '));

  const s2 = O.kimlikle(K.BAR810,
    `select public.bar_siparis_olustur('810','${BAR}','M1',null,'[{"menu_urun_id":"${M.BIRA}","adet":1}]'::jsonb);`).out;
  const ip = O.kimlikle(K.BAR810, `select public.bar_siparis_iptal('${s2}');`);
  sonuc(ip.ok && tek(`select durum::text from public.bar_siparisleri where id='${s2}';`) === 'iptal',
    'H6 ESKI akis: IPTAL calisiyor', ip.ok ? '' : (ip.err || '').split('\n').pop());

  // ---- 4) GEREKSIZ HAKLAR ACILMADI ----
  sonuc(hak('bar_siparisleri', 'truncate') === 'false' && hak('bar_siparis_kalemleri', 'truncate') === 'false'
     && hak('stok_rezervasyonlari', 'truncate') === 'false',
    'H7 TRUNCATE hakki ACILMADI (uc tabloda da kapali)');
  sonuc(hak('bar_siparisleri', 'insert') === 'false' && hak('bar_siparisleri', 'update') === 'false'
     && hak('bar_siparisleri', 'delete') === 'false',
    'H8 dogrudan YAZMA hakki acilmadi (yazma yalniz SECURITY DEFINER fonksiyonlardan)');
  const dogrudanYazma = O.kimlikle(K.BAR810,
    `update public.bar_siparisleri set durum='teslim_edildi' where id='${s2}';`);
  sonuc(!dogrudanYazma.ok && /permission denied/i.test(dogrudanYazma.err),
    'H9 personel tabloya DOGRUDAN yazamiyor (geri alma sonrasi da)', (dogrudanYazma.err || '').split('\n').pop());
} catch (e) {
  sonuc(false, 'beklenmeyen hata', String(e && e.stack || e));
} finally {
  O.temizle();
}
console.log(`\nGERI ALMA SONRASI ESKI EKRAN: ${ok} OK / ${fail} FAIL`);
process.exit(fail ? 1 : 0);
