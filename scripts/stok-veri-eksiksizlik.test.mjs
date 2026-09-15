// ===========================================================================
// STOK VERI EKSIKSIZLIK TESTLERI — izole, uretime BAGLANMAZ
// ===========================================================================
// Ne kanitlar:
//   1. 999 / 1.000 / 1.001 / 5.000 satirda liste EKSIKSIZ toplanir
//   2. Sunucu satir tavani 100 iken de ayni sonuc cikar
//   3. Ara sayfa hata verirse fonksiyon FIRLATIR (yarim/bos liste DONMEZ)
//   4. Son sayfadaki urun, sunucu aramasiyla bulunur
//   5. Sayim detaylari eksikse onay ENGELLENIR ve stok DEGISMEZ
//
// Ortam: tek kullanimlik postgres:17 + postgrest, ag disariya kapali degil
// (postgrest ile konusmasi gerekiyor) ama URETIME hicbir baglanti yoktur.
// PGRST_DB_MAX_ROWS=100 bilerek dusuk verilir: istemci sayfalamasi sunucu
// tavanindan BAGIMSIZ calismali.
// ===========================================================================
import { spawnSync } from 'node:child_process';
import { readFileSync } from 'node:fs';
import { setTimeout as bekle } from 'node:timers/promises';
import { createRequire } from 'node:module';

const require = createRequire(import.meta.url);
const kok = new URL('..', import.meta.url).pathname.replace(/^\/([A-Za-z]:)/, '$1');
const { kur, StokVeriHatasi } = require(kok + 'stok-veri.js');

const AG = 'stok-test-net';
const PG = 'stok-test-db';
const PR = 'stok-test-rest';
const REST_PORT = 3099;
const SIR = 'stok-testi-icin-yerel-sir-en-az-32-karakter-olmali';
const MAX_ROWS = 100;

let ok = 0;
let fail = 0;
function sonuc(gecti, ad, ek) {
  console.log((gecti ? 'OK   ' : 'FAIL ') + ad + (ek ? ' — ' + ek : ''));
  if (gecti) ok++; else fail++;
}

const d = (a, girdi) => spawnSync('docker', a, { input: girdi, encoding: 'utf8', timeout: 600000, maxBuffer: 64 * 1024 * 1024 });
const psql = (sql) => d(['exec', '-i', PG, 'psql', '-X', '-U', 'postgres', '-d', 'stoktest', '-v', 'ON_ERROR_STOP=1', '-q'], sql);
const psqlTek = (sql) => d(['exec', '-i', PG, 'psql', '-X', '-U', 'postgres', '-d', 'stoktest', '-At', '-v', 'ON_ERROR_STOP=1'], sql).stdout.trim();

function temizle() {
  for (const k of [PR, PG]) spawnSync('docker', ['rm', '-f', k]);
  spawnSync('docker', ['network', 'rm', AG]);
}

// --- JWT (yerel; uretimdeki hicbir sirla ilgisi yok) ------------------------
function jwt(rol) {
  const b64 = (o) => Buffer.from(JSON.stringify(o)).toString('base64url');
  const bas = b64({ alg: 'HS256', typ: 'JWT' });
  const govde = b64({ role: rol, exp: Math.floor(Date.now() / 1000) + 3600 });
  const imza = require('node:crypto').createHmac('sha256', SIR).update(bas + '.' + govde).digest('base64url');
  return bas + '.' + govde + '.' + imza;
}

async function kur_ortam() {
  temizle();
  spawnSync('docker', ['network', 'create', AG]);
  d(['run', '--detach', '--rm', '--name', PG, '--network', AG, '--tmpfs', '/var/lib/postgresql/data',
    '-e', 'POSTGRES_HOST_AUTH_METHOD=trust', 'postgres:17']);
  for (let i = 0; i < 60; i++) {
    if (spawnSync('docker', ['exec', PG, 'pg_isready', '-U', 'postgres']).status === 0) break;
    await bekle(1000);
  }
  await bekle(1500);
  d(['exec', PG, 'createdb', '-U', 'postgres', 'stoktest']);

  // Asgari sema: testin konusu sayfalama ve eksiksizlik; RLS ayrica sinanir.
  psql(`
    create role anon nologin;
    create role authenticated nologin;
    create role service_role nologin;
    grant usage on schema public to anon, authenticated, service_role;

    create table public.urunler (kod text primary key, ad text, birim text);
    create table public.stok (
      id uuid primary key default gen_random_uuid(),
      urun_kodu text not null, depo_kodu text not null, otel_id text not null,
      miktar numeric(12,3) not null default 0,
      guncelleme_tarihi timestamptz not null default now());
    create table public.stok_minimumlar (
      id uuid primary key default gen_random_uuid(),
      urun_kodu text not null, depo_kodu text not null, otel_id text not null,
      min_miktar numeric(12,3) not null default 0);
    create table public.stok_hareketleri (
      id uuid primary key default gen_random_uuid(),
      urun_kodu text, depo_kodu text, tip text, miktar numeric(12,3),
      tarih timestamptz default now(), belge_no text, aciklama text);
    create table public.sayim_oturumlari (
      id uuid primary key default gen_random_uuid(),
      depo_kodu text not null, durum text default 'onay_bekliyor',
      toplam_urun_sayisi integer default 0, farkli_urun_sayisi integer default 0);
    create table public.sayim_detaylari (
      id uuid primary key default gen_random_uuid(),
      oturum_id uuid not null, urun_kodu text not null, urun_adi text,
      sistem_miktar numeric(12,3), sayilan_miktar numeric(12,3),
      fark numeric(12,3), fark_yuzde numeric(12,3), birim text, aciklama text);

    grant select on all tables in schema public to authenticated, service_role;
  `);

  // Aday migration AYNEN uygulanir (gorunum + ozet fonksiyonu).
  const mig = readFileSync(kok + 'docs/kurulum/2026-09-14-stok-liste-ozet.sql', 'utf8');
  const r = psql(mig);
  if (r.status !== 0) {
    console.error('Migration uygulanamadi:\n' + (r.stderr || '').split('\n').slice(-6).join('\n'));
    temizle();
    process.exit(1);
  }

  d(['run', '--detach', '--rm', '--name', PR, '--network', AG, '-p', REST_PORT + ':3000',
    '-e', 'PGRST_DB_URI=postgres://postgres@' + PG + ':5432/stoktest',
    '-e', 'PGRST_DB_SCHEMAS=public',
    '-e', 'PGRST_DB_ANON_ROLE=anon',
    '-e', 'PGRST_JWT_SECRET=' + SIR,
    '-e', 'PGRST_DB_MAX_ROWS=' + MAX_ROWS,
    'postgrest/postgrest:v12.2.3']);
  for (let i = 0; i < 60; i++) {
    try {
      const c = await fetch('http://127.0.0.1:' + REST_PORT + '/', { headers: { Authorization: 'Bearer ' + jwt('authenticated') } });
      if (c.status < 500) break;
    } catch (e) { /* henuz ayakta degil */ }
    await bekle(1000);
  }
}

function urunYaz(adet) {
  psql(`truncate public.stok, public.urunler, public.stok_minimumlar;
    insert into public.urunler (kod, ad, birim)
      select 'K' || lpad(g::text, 6, '0'), 'Urun ' || g, 'KG' from generate_series(1, ${adet}) g;
    insert into public.stok (urun_kodu, depo_kodu, otel_id, miktar)
      select 'K' || lpad(g::text, 6, '0'), 'D1', '810', g from generate_series(1, ${adet}) g;`);
}

function veri(ekFetch) {
  return kur({
    url: 'http://127.0.0.1:' + REST_PORT,
    headers: { Authorization: 'Bearer ' + jwt('authenticated'), Accept: 'application/json' },
    fetch: ekFetch || fetch,
    onek: '',           // ciplak PostgREST: kok dizinde sunuyor (Supabase'de /rest/v1)
    sayfaBoyutu: 500,   // sunucu tavani 100: istemci istegi BUYUK, sunucu kirpar
  });
}

// ===========================================================================
await kur_ortam();
console.log('ortam hazir — postgrest satir tavani: ' + MAX_ROWS + '\n');

// --- 1) 999 / 1000 / 1001 / 5000 -------------------------------------------
for (const adet of [999, 1000, 1001, 5000]) {
  urunYaz(adet);
  const v = veri();
  let hata = null;
  let satirlar = [];
  try { ({ satirlar } = await v.stokTumunuGetir({ depo: 'D1' })); }
  catch (e) { hata = e; }
  sonuc(!hata && satirlar.length === adet, adet + ' satir eksiksiz toplandi',
    hata ? hata.message : satirlar.length + ' satir');

  // Ozet SUNUCUDAN: sayfadan degil.
  let ozet = null;
  try { ozet = await v.stokOzetGetir('D1'); } catch (e) { hata = e; }
  sonuc(!!ozet && ozet.toplam === adet, adet + ' icin sunucu ozeti dogru',
    ozet ? 'toplam=' + ozet.toplam : (hata && hata.message));
}

// --- 2) Ara sayfa hatasi ---------------------------------------------------
{
  urunYaz(5000);
  let cagri = 0;
  const bozukFetch = async (u, o) => {
    cagri++;
    if (cagri === 3) return new Response('sunucu hatasi', { status: 500 });
    return fetch(u, o);
  };
  const v = veri(bozukFetch);
  let hata = null;
  let satirlar = null;
  try { ({ satirlar } = await v.stokTumunuGetir({ depo: 'D1' })); }
  catch (e) { hata = e; }
  sonuc(hata instanceof StokVeriHatasi && satirlar === null,
    'ara sayfa hatasinda FIRLATIR (yarim liste donmez)',
    hata ? 'durum=' + hata.durum : 'hata firlatilmadi');
}

// --- 3) Son sayfadaki urunu arama ------------------------------------------
{
  urunYaz(5000);
  const v = veri();
  let bulunan = null;
  let hata = null;
  try { const r = await v.urunAra('Urun 5000'); bulunan = r.satirlar; }
  catch (e) { hata = e; }
  const dogru = !hata && bulunan && bulunan.some((u) => u.kod === 'K005000');
  sonuc(dogru, 'son sayfadaki urun sunucu aramasiyla bulundu',
    hata ? hata.message : (bulunan ? bulunan.length + ' sonuc' : 'sonuc yok'));

  // Ayni urun, YALNIZ ilk sayfa indirilmis olsaydi bulunamazdi: kaniti da olcelim.
  const ilkSayfa = (await v.stokSayfasiGetir({ depo: 'D1', adet: 100 })).satirlar;
  sonuc(!ilkSayfa.some((s) => s.urun_kodu === 'K005000'),
    'ayni urun ilk sayfada YOK (arama gercekten sunucudan geliyor)');
}

// --- 4) Sayfa sayaci ve dahaVar --------------------------------------------
{
  urunYaz(1001);
  const v = veri();
  const s1 = await v.stokSayfasiGetir({ depo: 'D1', ofset: 0, adet: 100 });
  const sSon = await v.stokSayfasiGetir({ depo: 'D1', ofset: 1000, adet: 100 });
  sonuc(s1.toplam === 1001 && s1.dahaVar === true, 'ilk sayfa: toplam sunucudan, dahaVar dogru',
    'toplam=' + s1.toplam + ' dahaVar=' + s1.dahaVar);
  sonuc(sSon.satirlar.length === 1 && sSon.dahaVar === false, 'son sayfa: 1 satir, dahaVar false',
    sSon.satirlar.length + ' satir, dahaVar=' + sSon.dahaVar);
}

// --- 5) Sayim detaylari: eksiksizlik ve onay engeli -------------------------
{
  psql(`truncate public.sayim_oturumlari, public.sayim_detaylari;
    insert into public.sayim_oturumlari (id, depo_kodu, toplam_urun_sayisi)
      values ('11111111-1111-1111-1111-111111111111', 'D1', 1500);
    insert into public.sayim_detaylari (oturum_id, urun_kodu, urun_adi, sistem_miktar, sayilan_miktar, fark)
      select '11111111-1111-1111-1111-111111111111', 'K' || lpad(g::text, 6, '0'), 'Urun ' || g, g, g, 0
        from generate_series(1, 1500) g;`);

  const v = veri();
  // 5a: tavan 100 olmasina ragmen 1500 satirin tamami gelir
  let detaylar = null;
  let hata = null;
  try { detaylar = await v.sayimDetaylariniGetir('11111111-1111-1111-1111-111111111111', 1500); }
  catch (e) { hata = e; }
  sonuc(!hata && detaylar && detaylar.length === 1500,
    'sayim detaylari eksiksiz (1500/1500, sunucu tavani 100)',
    hata ? hata.message : (detaylar ? detaylar.length + ' satir' : '-'));

  // 5b: beklenen adet tutmuyorsa FIRLAT (oturum 1501 diyor, 1500 satir var)
  hata = null;
  try { await v.sayimDetaylariniGetir('11111111-1111-1111-1111-111111111111', 1501); }
  catch (e) { hata = e; }
  sonuc(hata instanceof StokVeriHatasi && hata.tur === 'eksik',
    'adet uyusmazliginda FIRLATIR (onay baslamaz)', hata ? hata.message : 'hata yok');

  // 5c: HTTP hatasinda bos liste DEGIL, hata
  const bozuk = veri(async () => new Response('bozuk', { status: 503 }));
  hata = null;
  let sonucListe = null;
  try { sonucListe = await bozuk.sayimDetaylariniGetir('11111111-1111-1111-1111-111111111111', 1500); }
  catch (e) { hata = e; }
  sonuc(hata instanceof StokVeriHatasi && hata.durum === 503 && sonucListe === null,
    'HTTP hatasi bos listeye CEVRILMEZ', hata ? 'durum=' + hata.durum : 'hata firlatilmadi');

  // 5d: onay akisinin engellendigi — stok tablosuna hic dokunulmadigi
  const oncekiStok = psqlTek("select coalesce(sum(miktar),0)::text from public.stok");
  let onayBasladi = false;
  try {
    await bozuk.sayimDetaylariniGetir('11111111-1111-1111-1111-111111111111', 1500);
    onayBasladi = true;           // buraya DUSMEMELI
  } catch (e) { /* beklenen */ }
  const sonrakiStok = psqlTek("select coalesce(sum(miktar),0)::text from public.stok");
  sonuc(!onayBasladi && oncekiStok === sonrakiStok,
    'eksik detayla onay ENGELLENDI, stok degismedi',
    'stok toplami ' + oncekiStok + ' -> ' + sonrakiStok);
}

// --- 6) Hareket gecmisi acilista degil, sayfali -----------------------------
{
  psql(`truncate public.stok_hareketleri;
    insert into public.stok_hareketleri (urun_kodu, depo_kodu, tip, miktar, tarih)
      select 'K000001', 'D1', 'giris', 1, now() - (g || ' minutes')::interval from generate_series(1, 300) g;`);
  const v = veri();
  const s = await v.hareketSayfasiGetir({ depo: 'D1', urun: 'K000001', ofset: 0, adet: 50 });
  sonuc(s.satirlar.length === 50 && s.toplam === 300 && s.dahaVar === true,
    'hareket gecmisi sayfali geliyor (50/300)',
    s.satirlar.length + ' satir, toplam=' + s.toplam);
}

// --- 7) OZET ESIKLERI: istemcideki getStokDurum ile BIREBIR ----------------
// Toplamin dogru olmasi yetmez; kritik/uyari/normal kirilimi ekranin bugunku
// mantigiyla ayni olmali. Beklenen sayilar elle YAZILMAZ, ayni kuralin JS
// karsiligindan uretilir — sapma olursa test bunu gosterir.
{
  // (kod, miktar, [depo/min ciftleri]) — min satiri yoksa minimum yok demektir.
  const kume = [
    { kod: 'E00001', miktar: 50, min: [] },                          // minimum yok
    { kod: 'E00002', miktar: 50, min: [['D1', 0]] },                 // minimum 0
    { kod: 'E00003', miktar: 0, min: [['D1', 10]] },                 // miktar 0
    { kod: 'E00004', miktar: -5, min: [['D1', 10]] },                // negatif
    { kod: 'E00005', miktar: 5, min: [['D1', 10]] },                 // tam min/2
    { kod: 'E00006', miktar: 6, min: [['D1', 10]] },
    { kod: 'E00007', miktar: 10, min: [['D1', 10]] },                // tam min
    { kod: 'E00008', miktar: 11, min: [['D1', 10]] },
    { kod: 'E00009', miktar: 10, min: [['D1', 4], ['D2', 20]] },     // depolar arasi EN YUKSEK
  ];
  psql(`truncate public.stok, public.urunler, public.stok_minimumlar;
    insert into public.urunler (kod, ad, birim) values
      ${kume.map(k => `('${k.kod}', 'Urun ${k.kod}', 'KG')`).join(',')};
    insert into public.stok (urun_kodu, depo_kodu, otel_id, miktar) values
      ${kume.map(k => `('${k.kod}', 'D1', '810', ${k.miktar})`).join(',')};
    insert into public.stok_minimumlar (urun_kodu, depo_kodu, otel_id, min_miktar) values
      ${kume.flatMap(k => k.min.map(([d, m]) => `('${k.kod}', '${d}', '810', ${m})`)).join(',')};`);

  // stok-takip.html getStokDurum'un BIREBIR kopyasi (minimum = depolar arasi max).
  const getStokDurum = (min, miktar) => {
    if (!min || min <= 0) return 'normal';
    if (miktar <= 0 || miktar <= min * 0.5) return 'kritik';
    if (miktar <= min) return 'uyari';
    return 'normal';
  };
  const bek = { toplam: kume.length, kritik: 0, uyari: 0, normal: 0 };
  for (const k of kume) {
    const min = k.min.length ? Math.max(...k.min.map(m => m[1])) : 0;
    bek[getStokDurum(min, k.miktar)]++;
  }

  const ozet = await veri().stokOzetGetir('D1');
  const esit = ozet.toplam === bek.toplam && ozet.kritik === bek.kritik
    && ozet.uyari === bek.uyari && ozet.normal === bek.normal;
  sonuc(esit, 'stok_ozet kirilimi istemci esikleriyle BIREBIR',
    `sunucu ${ozet.kritik}/${ozet.uyari}/${ozet.normal} — istemci ${bek.kritik}/${bek.uyari}/${bek.normal} (kritik/uyari/normal)`);

  // Depolar arasi en yuksek minimum korunuyor mu: E00009 tek basina sinanir.
  const tek = psqlTek("select min_miktar::text from public.stok_liste where urun_kodu='E00009'");
  sonuc(Number(tek) === 20, 'minimum depolar arasi EN YUKSEK olarak geliyor', 'min=' + tek);
}

// --- 8) KATEGORI LISTESI: sayfadan degil tum kayitlardan -------------------
// Sunucu tavani 100. Kategori sayisi tavanin USTUNDE secilir: duz okuma
// kirpilir, sayfali okuma kirpilmaz. Ikisi de olculur.
{
  const KAT = 250, KAT_BASINA = 3;
  psql(`truncate public.stok, public.urunler, public.stok_minimumlar;
    insert into public.urunler (kod, ad, birim)
      select 'C' || lpad(k::text, 4, '0') || lpad(i::text, 2, '0'), 'Urun', 'KG'
        from generate_series(1, ${KAT}) k, generate_series(1, ${KAT_BASINA}) i;
    insert into public.stok (urun_kodu, depo_kodu, otel_id, miktar)
      select kod, 'D1', '810', 5 from public.urunler;`);
  const bas = { Authorization: 'Bearer ' + jwt('authenticated'), Accept: 'application/json' };

  // (a) Sayfalamasiz okuma: sunucu tavani kadar kirpar.
  const duz = await fetch('http://127.0.0.1:' + REST_PORT + '/rpc/stok_kategoriler',
    { method: 'POST', headers: { ...bas, 'Content-Type': 'application/json' }, body: JSON.stringify({ p_depo: 'D1' }) });
  const duzSatir = await duz.json();
  sonuc(duzSatir.length === MAX_ROWS, 'sayfalamasiz RPC okumasi KIRPILIYOR (kanit)',
    duzSatir.length + '/' + KAT + ' kategori');

  // (b) Sayfali okuma: eksiksiz ve her kategorinin adedi dogru.
  let kat = [], hata = null;
  try { ({ satirlar: kat } = await veri().tumSayfalariCek('/rpc/stok_kategoriler?p_depo=D1')); }
  catch (e) { hata = e; }
  const adetDogru = kat.length ? kat.every(k => Number(k.adet) === KAT_BASINA) : false;
  const tekil = new Set(kat.map(k => k.kategori)).size;   // mukerrer sayfa satiri da kusurdur
  sonuc(!hata && kat.length === KAT && tekil === KAT && adetDogru,
    'stok_kategoriler sayfali okumada EKSIKSIZ ve MUKERRERSIZ',
    hata ? hata.message : kat.length + '/' + KAT + ' kategori, tekil ' + tekil + ', her biri ' + KAT_BASINA);
}

// --- 9) ABC GIRDILERI: depolar arasi toplam + tuketim penceresi ------------
{
  psql(`truncate public.stok, public.urunler, public.stok_minimumlar, public.stok_hareketleri;
    insert into public.urunler (kod, ad, birim) values ('A00001', 'ABC urunu', 'KG');
    insert into public.stok (urun_kodu, depo_kodu, otel_id, miktar) values
      ('A00001', 'D1', '810', 30), ('A00001', 'D2', '810', 12);
    insert into public.stok_hareketleri (urun_kodu, depo_kodu, tip, miktar, tarih, aciklama) values
      ('A00001', 'D1', 'cikis', 5,   now() - interval '1 day',  'gunluk_tuketim'),
      ('A00001', 'D1', 'cikis', 3,   now() - interval '2 days', 'recete_tuketim: pilav'),
      ('A00001', 'D1', 'cikis', 100, now() - interval '30 days','gunluk_tuketim'),
      ('A00001', 'D1', 'cikis', 50,  now() - interval '1 day',  'depo transferi'),
      ('A00001', 'D1', 'giris', 70,  now() - interval '1 day',  'gunluk_tuketim');`);
  const { satirlar } = await veri().tumSayfalariCek('/rpc/stok_abc_girdi?p_gun=7');
  const s = satirlar.find(r => r.urun_kodu === 'A00001') || {};
  sonuc(Number(s.stok_miktar) === 42 && Number(s.tuketim_miktar) === 8,
    'stok_abc_girdi: stok depolar arasi toplam, tuketim yalniz pencere ici',
    'stok=' + s.stok_miktar + ' (bekl. 42), tuketim=' + s.tuketim_miktar + ' (bekl. 8)');

  // Tavanin ustunde urun: duz okuma kirpilir, sayfali okuma kirpilmaz.
  psql(`truncate public.stok, public.urunler, public.stok_hareketleri;
    insert into public.urunler (kod, ad, birim)
      select 'K' || lpad(g::text, 6, '0'), 'Urun', 'KG' from generate_series(1, 5000) g;
    insert into public.stok (urun_kodu, depo_kodu, otel_id, miktar)
      select kod, 'D1', '810', 1 from public.urunler;`);
  const bas = { Authorization: 'Bearer ' + jwt('authenticated'), Accept: 'application/json' };
  const duz = await fetch('http://127.0.0.1:' + REST_PORT + '/rpc/stok_abc_girdi',
    { method: 'POST', headers: { ...bas, 'Content-Type': 'application/json' }, body: JSON.stringify({ p_gun: 7 }) });
  const duzSatir = await duz.json();
  sonuc(duzSatir.length === MAX_ROWS, 'sayfalamasiz ABC okumasi KIRPILIYOR (kanit)',
    duzSatir.length + '/5000 urun');

  let hepsi = [], hata = null;
  try { ({ satirlar: hepsi } = await veri().tumSayfalariCek('/rpc/stok_abc_girdi?p_gun=7')); }
  catch (e) { hata = e; }
  // Uzunluk esitligi tek basina kanit degil: sirasiz sonucta bir urun iki kez
  // gelip bir baskasi hic gelmeyebilir. Tekil kod sayisi da 5000 olmali.
  const tekilKod = new Set(hepsi.map(r => r.urun_kodu)).size;
  sonuc(!hata && hepsi.length === 5000 && tekilKod === 5000,
    'stok_abc_girdi sayfali okumada EKSIKSIZ ve MUKERRERSIZ',
    hata ? hata.message : hepsi.length + '/5000 satir, tekil urun ' + tekilKod);
}

// --- 10) RLS/yetki siniri korunuyor mu -------------------------------------
{
  // anon gorunumu de UC fonksiyonu da GOREMEMELI (migration ACL'i).
  const anonBaslik = { Authorization: 'Bearer ' + jwt('anon'), Accept: 'application/json' };
  const rpcAnon = (ad, govde) => fetch('http://127.0.0.1:' + REST_PORT + '/rpc/' + ad, {
    method: 'POST', headers: { ...anonBaslik, 'Content-Type': 'application/json' }, body: JSON.stringify(govde) });
  const rv = await fetch('http://127.0.0.1:' + REST_PORT + '/stok_liste?select=urun_kodu&limit=1', { headers: anonBaslik });
  const rOzet = await rpcAnon('stok_ozet', { p_depo: 'D1' });
  const rKat = await rpcAnon('stok_kategoriler', { p_depo: 'D1' });
  const rAbc = await rpcAnon('stok_abc_girdi', { p_gun: 7 });
  sonuc(!rv.ok && !rOzet.ok && !rKat.ok && !rAbc.ok,
    'anon: stok_liste ve UC fonksiyon da KAPALI',
    'view ' + rv.status + ', ozet ' + rOzet.status + ', kategori ' + rKat.status + ', abc ' + rAbc.status);

  // authenticated UCUNU de calistirabilmeli (kapatirken fazla kapatilmadi).
  const authBaslik = { Authorization: 'Bearer ' + jwt('authenticated'), Accept: 'application/json' };
  const rpcAuth = (ad, govde) => fetch('http://127.0.0.1:' + REST_PORT + '/rpc/' + ad, {
    method: 'POST', headers: { ...authBaslik, 'Content-Type': 'application/json' }, body: JSON.stringify(govde) });
  const aOzet = await rpcAuth('stok_ozet', { p_depo: 'D1' });
  const aKat = await rpcAuth('stok_kategoriler', { p_depo: 'D1' });
  const aAbc = await rpcAuth('stok_abc_girdi', { p_gun: 7 });
  sonuc(aOzet.ok && aKat.ok && aAbc.ok, 'authenticated UC fonksiyonu da calistirabiliyor',
    'ozet ' + aOzet.status + ', kategori ' + aKat.status + ', abc ' + aAbc.status);
}

console.log('\nSTOK VERI EKSIKSIZLIK SONUC: ' + ok + ' OK / ' + fail + ' FAIL');
temizle();
process.exit(fail ? 1 : 0);
