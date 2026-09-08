#!/usr/bin/env node
// ============================================================================
// migration-guvenlik-kontrol.mjs
// Yeni migration dosyalarinin ACL/grant standardina uydugunu STATIK olarak
// denetler. Veritabanina BAGLANMAZ; yalniz dosya metnini okur.
//
// Kullanim:
//   node scripts/migration-guvenlik-kontrol.mjs                 # taban tarihten yeni dosyalar
//   node scripts/migration-guvenlik-kontrol.mjs <dosya> [...]   # yalniz verilen dosyalar
//   node scripts/migration-guvenlik-kontrol.mjs --tumu          # tarihi dosyalar dahil (rapor)
//   node scripts/migration-guvenlik-kontrol.mjs --uyari-da-hata # UYARI da cikis kodunu bozar
//
// Cikis kodu: 0 = HATA yok, 1 = en az bir HATA.
//
// Standart: docs/kurulum/MIGRATION-GUVENLIK-STANDARDI.md
// Sablon  : docs/kurulum/SABLON-yeni-migration.sql
// ============================================================================

import fs from 'node:fs';
import path from 'node:path';

// Bu tarihten ONCEKI dosyalar TARIHSEL kabul edilir ve denetlenmez.
// PMS Adim 1-4 dahil canliya uygulanmis her sey bu sinirin altindadir;
// geriye donuk yeniden yazilmazlar (standart, "Gecmis migrationlar").
const TABAN_TARIH = '2026-09-08';

const KURULUM_DIZINI = 'docs/kurulum';

// ---------------------------------------------------------------------------
// 1) SQL metnini yorumlardan arindir (dize ve dolar-tirnak icini KORUYARAK)
// ---------------------------------------------------------------------------
function yorumlariSil(sql) {
  let cikti = '';
  let i = 0;
  while (i < sql.length) {
    const c = sql[i];

    // Dolar tirnakli govde: $$ ... $$ veya $etiket$ ... $etiket$
    if (c === '$') {
      const m = /^\$[A-Za-z_][A-Za-z0-9_]*\$|^\$\$/.exec(sql.slice(i));
      if (m) {
        const etiket = m[0];
        const son = sql.indexOf(etiket, i + etiket.length);
        const bitis = son === -1 ? sql.length : son + etiket.length;
        cikti += sql.slice(i, bitis);
        i = bitis;
        continue;
      }
    }

    // Tek tirnakli dize ('' kacisi dahil)
    if (c === "'") {
      let j = i + 1;
      while (j < sql.length) {
        if (sql[j] === "'" && sql[j + 1] === "'") { j += 2; continue; }
        if (sql[j] === "'") { j++; break; }
        j++;
      }
      cikti += sql.slice(i, j);
      i = j;
      continue;
    }

    // Satir yorumu
    if (c === '-' && sql[i + 1] === '-') {
      const nl = sql.indexOf('\n', i);
      i = nl === -1 ? sql.length : nl;
      continue;
    }

    // Blok yorumu (ic ice olabilir)
    if (c === '/' && sql[i + 1] === '*') {
      let derinlik = 1;
      let j = i + 2;
      while (j < sql.length && derinlik > 0) {
        if (sql[j] === '/' && sql[j + 1] === '*') { derinlik++; j += 2; continue; }
        if (sql[j] === '*' && sql[j + 1] === '/') { derinlik--; j += 2; continue; }
        j++;
      }
      i = j;
      cikti += ' ';
      continue;
    }

    cikti += c;
    i++;
  }
  return cikti;
}

// ---------------------------------------------------------------------------
// 2) Yonergeler — yorum satirlarindan okunur (yorumlar SILINMEDEN once)
// ---------------------------------------------------------------------------
function yonergeleriOku(hamSql) {
  const y = { appendOnly: new Set(), erisimYok: new Set(), istisna: new Map() };
  for (const s of hamSql.split('\n')) {
    let m;
    if ((m = /--\s*@append-only\s*:\s*(.+)$/i.exec(s))) {
      m[1].split(',').forEach(a => { const t = a.trim(); if (t) y.appendOnly.add(t.toLowerCase()); });
    }
    if ((m = /--\s*@erisim-yok\s*:\s*(.+)$/i.exec(s))) {
      m[1].split(',').forEach(a => { const t = a.trim(); if (t) y.erisimYok.add(t.toLowerCase()); });
    }
    if ((m = /--\s*@acl-istisna\s*:\s*([A-Za-z0-9_]+)\s*(?:--\s*(.*))?$/i.exec(s))) {
      y.istisna.set(m[1].trim().toLowerCase(), (m[2] || '').trim() || '(gerekce yazilmamis)');
    }
  }
  return y;
}

// ---------------------------------------------------------------------------
// 3) Olusturulan nesneler
//
// ONEMLI: nesne kesfi, dize ve dolar-tirnak GOVDELERI BOSALTILMIS metin
// uzerinde yapilir. Aksi halde SQL icindeki bir metin sabiti sahte nesne
// uretir. Gercek ornek:
//
//   when tag in ('CREATE TABLE', 'CREATE TABLE AS', 'SELECT INTO')
//
// Bu satir bir event trigger tanimidir, tablo yaratmaz; ama duz arama
// "CREATE TABLE AS" icinden "as" adli bir tablo uydurur ve dosyayi haksiz
// yere kirmizi yapar. 2026-09-08'de tam olarak bu oldu.
//
// Bosaltma satir sonlarini KORUR, boylece fonksiyon satir numaralari kaymaz.
// Nesne ADLARI her zaman govdenin DISINDA oldugu icin bu kayipsizdir.
// ---------------------------------------------------------------------------
function govdeleriBosalt(sql) {
  const bosluk = t => t.replace(/[^\n]/g, ' ');
  let cikti = '';
  let i = 0;
  while (i < sql.length) {
    const c = sql[i];

    if (c === '$') {
      const m = /^\$[A-Za-z_][A-Za-z0-9_]*\$|^\$\$/.exec(sql.slice(i));
      if (m) {
        const etiket = m[0];
        const son = sql.indexOf(etiket, i + etiket.length);
        if (son === -1) { cikti += sql.slice(i); break; }
        cikti += etiket + bosluk(sql.slice(i + etiket.length, son)) + etiket;
        i = son + etiket.length;
        continue;
      }
    }

    if (c === "'") {
      let j = i + 1;
      while (j < sql.length) {
        if (sql[j] === "'" && sql[j + 1] === "'") { j += 2; continue; }
        if (sql[j] === "'") { j++; break; }
        j++;
      }
      const kapali = sql[j - 1] === "'";
      cikti += "'" + bosluk(sql.slice(i + 1, kapali ? j - 1 : j)) + (kapali ? "'" : '');
      i = j;
      continue;
    }

    cikti += c;
    i++;
  }
  return cikti;
}

function nesneleriBul(sql) {
  const tablolar = new Set();
  const sekanslar = new Set();
  const gorunumler = new Set();
  const fonksiyonlar = [];

  let m;
  const reTablo = /\bcreate\s+table\s+(?:if\s+not\s+exists\s+)?(?:public\.)?"?([a-z0-9_]+)"?/gi;
  while ((m = reTablo.exec(sql))) tablolar.add(m[1].toLowerCase());

  const reSekans = /\bcreate\s+sequence\s+(?:if\s+not\s+exists\s+)?(?:public\.)?"?([a-z0-9_]+)"?/gi;
  while ((m = reSekans.exec(sql))) sekanslar.add(m[1].toLowerCase());

  const reGorunum = /\bcreate\s+(?:or\s+replace\s+)?(?:materialized\s+)?view\s+(?:if\s+not\s+exists\s+)?(?:public\.)?"?([a-z0-9_]+)"?/gi;
  while ((m = reGorunum.exec(sql))) gorunumler.add(m[1].toLowerCase());

  const reFn = /\bcreate\s+(?:or\s+replace\s+)?function\s+(?:public\.)?"?([a-z0-9_]+)"?\s*\(/gi;
  while ((m = reFn.exec(sql))) {
    const ad = m[1].toLowerCase();
    // Imza: acilis parantezinden dengeli kapanisa kadar
    let derinlik = 1, j = reFn.lastIndex;
    while (j < sql.length && derinlik > 0) {
      if (sql[j] === '(') derinlik++;
      else if (sql[j] === ')') derinlik--;
      j++;
    }
    const imza = sql.slice(reFn.lastIndex, j - 1);
    // Baslik: imzadan govde acilisina ($$ / $etiket$) kadar
    const kalan = sql.slice(j);
    const gov = /\$[A-Za-z_][A-Za-z0-9_]*\$|\$\$/.exec(kalan);
    const baslik = kalan.slice(0, gov ? gov.index : Math.min(kalan.length, 400));
    fonksiyonlar.push({
      ad,
      imza: imza.replace(/\s+/g, ' ').trim(),
      tetikleyici: /\breturns\s+trigger\b/i.test(baslik),
      definer: /\bsecurity\s+definer\b/i.test(baslik),
      pinli: /\bset\s+search_path\s*=/i.test(baslik),
      satir: sql.slice(0, m.index).split('\n').length,
    });
  }

  return { tablolar, sekanslar, gorunumler, fonksiyonlar };
}

// ---------------------------------------------------------------------------
// 4) Calistirilacak ifadeler — DO bloklarindaki execute format(...) DAHIL.
//    Bu repoda ACL ifadelerinin bir kismi DO dongusu icinde %I ile uretilir.
//    Duz metin regex'i bunlari GOREMEZ ve yanlis alarm uretirdi; bu yuzden
//    format sablonlari, donguden okunan nesne adlariyla acilir.
// ---------------------------------------------------------------------------
function ifadeleriTopla(sql, nesneAdlari) {
  const ifadeler = [];

  function dizeIciniAl(kaynak, idx) {
    const c = kaynak[idx];
    if (c === "'") {
      let j = idx + 1, out = '';
      while (j < kaynak.length) {
        if (kaynak[j] === "'" && kaynak[j + 1] === "'") { out += "'"; j += 2; continue; }
        if (kaynak[j] === "'") { j++; break; }
        out += kaynak[j++];
      }
      return { metin: out, son: j };
    }
    const m = /^\$[A-Za-z_][A-Za-z0-9_]*\$|^\$\$/.exec(kaynak.slice(idx));
    if (m) {
      const etiket = m[0];
      const son = kaynak.indexOf(etiket, idx + etiket.length);
      const bitis = son === -1 ? kaynak.length : son;
      return { metin: kaynak.slice(idx + etiket.length, bitis), son: bitis + etiket.length };
    }
    return null;
  }

  // DO bloklarini ayikla
  const doBloklari = [];
  const reDo = /\bdo\s*(\$[A-Za-z_][A-Za-z0-9_]*\$|\$\$)/gi;
  let m;
  while ((m = reDo.exec(sql))) {
    const etiket = m[1];
    const bas = m.index + m[0].length;
    const son = sql.indexOf(etiket, bas);
    const bitis = son === -1 ? sql.length : son;
    doBloklari.push({ bas: m.index, bitis, govde: sql.slice(bas, bitis) });
    reDo.lastIndex = bitis;
  }

  for (const blok of doBloklari) {
    // Blok icinde gecen ve gercekten olusturulan nesne adlari: dongu
    // bu adlar uzerinde donuyor demektir.
    const donguAdlari = [];
    const reLit = /'([a-z0-9_]+)'/gi;
    let lm;
    while ((lm = reLit.exec(blok.govde))) {
      const ad = lm[1].toLowerCase();
      if (nesneAdlari.has(ad) && !donguAdlari.includes(ad)) donguAdlari.push(ad);
    }

    // execute [format]( '<sablon>' ... )  ve  execute '<sablon>'
    const reExec = /\bexecute\s+(?:format\s*\(\s*)?/gi;
    let em;
    while ((em = reExec.exec(blok.govde))) {
      const idx = em.index + em[0].length;
      const ch = blok.govde[idx];
      if (ch !== "'" && ch !== '$') continue;
      const d = dizeIciniAl(blok.govde, idx);
      if (!d) continue;
      const sablon = d.metin;
      if (/%I|%s/.test(sablon)) {
        for (const ad of donguAdlari) {
          ifadeler.push({ metin: sablon.replace(/%I|%s/g, ad) });
        }
      } else {
        ifadeler.push({ metin: sablon });
      }
      reExec.lastIndex = d.son;
    }
  }

  // DO bloklari disindaki duz ifadeler
  let kalan = '';
  let onceki = 0;
  for (const blok of doBloklari) {
    kalan += sql.slice(onceki, blok.bas) + ' ; ';
    onceki = blok.bitis;
  }
  kalan += sql.slice(onceki);
  for (const parca of kalan.split(';')) {
    const t = parca.trim();
    if (t) ifadeler.push({ metin: t });
  }

  return ifadeler;
}

// ---------------------------------------------------------------------------
// 5) ACL ifadelerini coz
// ---------------------------------------------------------------------------
function aclCoz(ifadeler) {
  const revokes = [];
  const grants = [];
  for (const { metin } of ifadeler) {
    const t = metin.replace(/\s+/g, ' ').trim();

    let m = /^revoke\s+(?:grant\s+option\s+for\s+)?(.+?)\s+on\s+(.+?)\s+from\s+(.+)$/i.exec(t);
    if (m) {
      revokes.push({ haklar: m[1].toLowerCase(), nesne: m[2].toLowerCase(), roller: m[3].toLowerCase(), ham: t });
      continue;
    }
    m = /^grant\s+(.+?)\s+on\s+(.+?)\s+to\s+(.+)$/i.exec(t);
    if (m) {
      grants.push({ haklar: m[1].toLowerCase(), nesne: m[2].toLowerCase(), roller: m[3].toLowerCase(), ham: t });
    }
  }
  return { revokes, grants };
}

function nesneEslesir(nesneMetni, ad) {
  // "table public.x", "public.x", "sequence public.x", "function public.x(uuid)"
  return new RegExp('(^|[\\s.,(])' + ad + '($|[\\s,(])')
    .test(nesneMetni.replace(/\(/g, ' ('));
}

function rolIcerir(roller, rol) {
  return new RegExp('(^|[\\s,])' + rol + '($|[\\s,])').test(roller);
}

// ---------------------------------------------------------------------------
// 6) Kurallar
// ---------------------------------------------------------------------------
function dosyayiDenetle(yol) {
  const ham = fs.readFileSync(yol, 'utf8');
  const yonerge = yonergeleriOku(ham);
  const sql = yorumlariSil(ham);
  const { tablolar, sekanslar, gorunumler, fonksiyonlar } = nesneleriBul(govdeleriBosalt(sql));

  const tumAdlar = new Set([...tablolar, ...sekanslar, ...gorunumler, ...fonksiyonlar.map(f => f.ad)]);
  const ifadeler = ifadeleriTopla(sql, tumAdlar);
  const { revokes, grants } = aclCoz(ifadeler);
  const duzMetin = ifadeler.map(i => i.metin.replace(/\s+/g, ' ')).join(' ; ').toLowerCase();

  const bulgular = [];
  const ekle = (seviye, kural, nesne, mesaj) => bulgular.push({ seviye, kural, nesne, mesaj });
  const atlanir = ad => yonerge.istisna.has(ad);

  // --- R1 / R2: tablo REVOKE ---
  for (const t of tablolar) {
    if (atlanir(t)) continue;
    const ilgili = revokes.filter(r => nesneEslesir(r.nesne, t) && !/^execute\b/.test(r.haklar));
    if (ilgili.length === 0) {
      ekle('HATA', 'R1-TABLO-REVOKE-YOK', t,
        'Tablo olusturuluyor ama hicbir REVOKE onu kapsamiyor. Varsayilan ayricaliklar tabloyu acik dogurabilir.');
      continue;
    }
    for (const rol of ['public', 'anon', 'authenticated']) {
      if (!ilgili.some(r => rolIcerir(r.roller, rol))) {
        ekle('HATA', 'R2-REVOKE-EKSIK-ROL', t,
          'REVOKE var ama "' + rol + '" kapsanmiyor. Standart: REVOKE ALL ... FROM PUBLIC, anon, authenticated.');
      }
    }
  }

  // --- R3: tablo GRANT karari ---
  for (const t of tablolar) {
    if (atlanir(t) || yonerge.erisimYok.has(t)) continue;
    if (!grants.some(g => nesneEslesir(g.nesne, t) && rolIcerir(g.roller, 'authenticated'))) {
      ekle('UYARI', 'R3-GRANT-KARARI-YOK', t,
        'authenticated icin acik GRANT yok. Kasitliysa "-- @erisim-yok: ' + t + '" yonergesini ekleyin.');
    }
  }

  // --- R4: authenticated'a ALL ---
  for (const g of grants) {
    if (!rolIcerir(g.roller, 'authenticated')) continue;
    if (!/^all\b/.test(g.haklar)) continue;
    if (/\bsequence\b/.test(g.nesne)) {
      ekle('HATA', 'R4-SEKANS-ALL', g.nesne, 'Sekansta authenticated ALL aliyor; USAGE yeterli.');
    } else {
      ekle('HATA', 'R4-AUTHENTICATED-ALL', g.nesne,
        'authenticated ALL aliyor. Asgari hak ilkesi: SELECT/INSERT/UPDATE ayri ayri verilir.');
    }
  }

  // --- R5: PUBLIC / anon'a GRANT ---
  for (const g of grants) {
    for (const rol of ['public', 'anon']) {
      if (rolIcerir(g.roller, rol)) {
        ekle('HATA', 'R5-ACIK-GRANT', g.nesne,
          '"' + rol + '" rolune GRANT veriliyor: ' + g.ham.slice(0, 120));
      }
    }
  }

  // --- R6: append-only tablolar ---
  for (const t of yonerge.appendOnly) {
    if (!tablolar.has(t)) {
      ekle('UYARI', 'R6-APPEND-ONLY-BILINMEYEN', t,
        '@append-only isaretli ama bu dosyada boyle bir tablo olusturulmuyor.');
      continue;
    }
    for (const g of grants.filter(x => nesneEslesir(x.nesne, t))) {
      if (rolIcerir(g.roller, 'service_role')) continue;   // servis rolu kapsam disi
      if (/\ball\b/.test(g.haklar) || /\bupdate\b/.test(g.haklar) || /\bdelete\b/.test(g.haklar)) {
        ekle('HATA', 'R6-APPEND-ONLY-YAZMA', t,
          'append-only tabloya UPDATE/DELETE ayricaligi veriliyor: ' + g.ham.slice(0, 120));
      }
    }
    // Ucuncu katman: ayricalik + politika yetmez; service_role RLS'i baypas eder.
    const tetik = new RegExp('before\\s+update\\s+or\\s+delete[\\s\\S]{0,160}?on\\s+(?:public\\.)?' + t + '\\b', 'i');
    if (!tetik.test(duzMetin)) {
      ekle('HATA', 'R6-APPEND-ONLY-TETIKLEYICI-YOK', t,
        'append-only tabloda "before update or delete" tetikleyicisi yok. service_role RLS ve politikayi baypas eder.');
    }
  }

  // --- R7: RLS ---
  for (const t of tablolar) {
    if (atlanir(t)) continue;
    const re = new RegExp('alter\\s+table\\s+(?:public\\.)?' + t + '\\s+enable\\s+row\\s+level\\s+security', 'i');
    if (!re.test(duzMetin)) {
      ekle('HATA', 'R7-RLS-YOK', t, 'Tabloda ENABLE ROW LEVEL SECURITY bulunamadi.');
    }
  }

  // --- R8: sekans ACL ---
  for (const s of sekanslar) {
    if (atlanir(s)) continue;
    const ilgili = revokes.filter(r => nesneEslesir(r.nesne, s));
    if (ilgili.length === 0) {
      ekle('HATA', 'R8-SEKANS-REVOKE-YOK', s, 'Sekans olusturuluyor ama REVOKE blogu yok.');
      continue;
    }
    for (const rol of ['public', 'anon', 'authenticated']) {
      if (!ilgili.some(r => rolIcerir(r.roller, rol))) {
        ekle('HATA', 'R8-SEKANS-REVOKE-EKSIK', s, 'Sekans REVOKE "' + rol + '" rolunu kapsamiyor.');
      }
    }
  }

  // --- R9: fonksiyon ACL + SECURITY DEFINER pini ---
  for (const f of fonksiyonlar) {
    if (f.definer && !f.pinli) {
      ekle('HATA', 'R9-DEFINER-PINSIZ', f.ad,
        'SECURITY DEFINER ama "set search_path" pini yok (satir ' + f.satir + ').');
    }
    if (f.tetikleyici) continue;              // tetikleyici fonksiyonu dogrudan cagrilamaz
    if (atlanir(f.ad)) continue;
    const rev = revokes.filter(r => nesneEslesir(r.nesne, f.ad));
    const gra = grants.filter(g => nesneEslesir(g.nesne, f.ad));
    if (rev.length === 0 && gra.length === 0) {
      ekle('UYARI', 'R9-FONKSIYON-ACL-KARARI-YOK', f.ad,
        'Cagrilabilir fonksiyon icin EXECUTE revoke/grant karari yok (satir ' + f.satir + ').');
    } else if (!rev.some(r => rolIcerir(r.roller, 'public')) || !rev.some(r => rolIcerir(r.roller, 'anon'))) {
      ekle('HATA', 'R9-FONKSIYON-REVOKE-EKSIK', f.ad,
        'EXECUTE, PUBLIC ve anon icin acikca geri alinmamis.');
    }
  }

  // --- R10: gorunum ACL + security_invoker ---
  for (const v of gorunumler) {
    if (atlanir(v)) continue;
    const rev = revokes.filter(r => nesneEslesir(r.nesne, v));
    const gra = grants.filter(g => nesneEslesir(g.nesne, v));
    if (rev.length === 0 && gra.length === 0) {
      ekle('UYARI', 'R10-GORUNUM-ACL-KARARI-YOK', v, 'Gorunum icin ACL karari yok.');
    }
    const re = new RegExp('view\\s+(?:public\\.)?' + v + '[\\s\\S]{0,240}?security_invoker\\s*=\\s*(?:true|on)', 'i');
    if (!re.test(sql)) {
      ekle('HATA', 'R10-GORUNUM-INVOKER-YOK', v,
        'Gorunumde security_invoker=true yok: RLS gorunum sahibine gore degerlendirilir, cagirana gore DEGIL.');
    }
  }

  return {
    yol,
    bulgular,
    ozet: {
      tablolar: tablolar.size, sekanslar: sekanslar.size,
      gorunumler: gorunumler.size, fonksiyonlar: fonksiyonlar.length,
    },
  };
}

// ---------------------------------------------------------------------------
// 7) Dosya secimi
// ---------------------------------------------------------------------------
function tarihPrefix(dosyaAdi) {
  const m = /^(\d{4}-\d{2}-\d{2})-/.exec(dosyaAdi);
  return m ? m[1] : null;
}

function hedefDosyalar(argv) {
  const acikYollar = argv.filter(a => !a.startsWith('--'));
  if (acikYollar.length) return acikYollar;

  const tumu = argv.includes('--tumu');
  if (!fs.existsSync(KURULUM_DIZINI)) return [];
  return fs.readdirSync(KURULUM_DIZINI)
    .filter(f => f.endsWith('.sql'))
    .filter(f => {
      const t = tarihPrefix(f);
      if (!t) return false;               // 01-sema-dokumu.sql gibi taban dosyalari
      return tumu || t >= TABAN_TARIH;
    })
    .map(f => path.join(KURULUM_DIZINI, f));
}

// ---------------------------------------------------------------------------
// 8) Ana akis
// ---------------------------------------------------------------------------
const argv = process.argv.slice(2);
const uyariDaHata = argv.includes('--uyari-da-hata');
const dosyalar = hedefDosyalar(argv);

if (dosyalar.length === 0) {
  console.log('Denetlenecek yeni migration yok (taban tarih: ' + TABAN_TARIH + ').');
  console.log('Tarihi dosyalari da gormek icin: --tumu');
  process.exit(0);
}

let hata = 0, uyari = 0;
for (const yol of dosyalar) {
  const r = dosyayiDenetle(yol);
  const h = r.bulgular.filter(b => b.seviye === 'HATA').length;
  const u = r.bulgular.filter(b => b.seviye === 'UYARI').length;
  hata += h; uyari += u;

  const durum = h ? 'HATA ' : (u ? 'UYARI' : 'TEMIZ');
  console.log('');
  console.log('[' + durum + '] ' + r.yol);
  console.log('         tablo ' + r.ozet.tablolar + ' | sekans ' + r.ozet.sekanslar +
              ' | gorunum ' + r.ozet.gorunumler + ' | fonksiyon ' + r.ozet.fonksiyonlar);
  for (const b of r.bulgular) {
    console.log('  ' + b.seviye.padEnd(5) + '  ' + b.kural.padEnd(30) + ' ' + b.nesne);
    console.log('         ' + b.mesaj);
  }
}

console.log('');
console.log('==> ' + dosyalar.length + ' dosya | ' + hata + ' HATA | ' + uyari + ' UYARI');
if (hata === 0 && uyari === 0) console.log('==> STANDARDA UYGUN');
process.exit((hata > 0 || (uyariDaHata && uyari > 0)) ? 1 : 0);
