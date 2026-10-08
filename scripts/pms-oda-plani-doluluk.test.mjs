// ===========================================================================
// ODA PLANI DOLULUK COZUMLEYICISI — doluRez regresyonu (uretime BAGLANMAZ)
// ===========================================================================
// CANLIDA OLCULDU (2026-10-08, demo.otel.dornevi.com, oda 101): oda sunucuda
// `dolu` gorunurken oda planinda misafir satiri ve "Cikis" dugmesi HIC
// cizilmedi; resepsiyon check-out yapamadi.
//
// KOK NEDEN: doluRez() ILK aktif atamayi `.find()` ile aliyor ve aramayi
// orada bitiriyordu. Faz 1 karari geregi check-out'tan SONRA atama
// `aktif = true` KALIR (gecmis konaklama kaydi). Ayni odada eski bir
// cikis_yapildi atamasi listede once gelirse, fonksiyon o rezervasyonun
// durumuna bakip `null` donuyor ve oda BOS sayiliyordu.
//
// Bu dosya once KIRMIZI olcer (duzeltmesiz kodda D1/D2 kalir), sonra
// duzeltmeyle YESIL olur. Gercek ekran betigi, gercek PostgREST, izole
// Docker veritabani. Canli veriye DOKUNULMAZ.
//
// Kullanim: node scripts/pms-oda-plani-doluluk.test.mjs
// ===========================================================================
import { barOrtami, kok, yerelJwt } from './bar-test-ortam.mjs';
import { EK_TOHUM } from './bar-a1-tohum.mjs';
import { barEkranKur } from './bar-ekran-harness.mjs';
import { PMS, PMS_TOHUM, RESEPSIYON_YETKI } from './pms-akis-tohum.mjs';

const O = barOrtami({ ad: 'pms-doluluk', ag: 'pms-doluluk-net' });
let ok = 0, fail = 0;
const sonuc = (g, ad, ek) => {
  console.log((g ? 'OK   ' : 'FAIL ') + ad + (ek ? ' — ' + ek : ''));
  if (g) ok++; else fail++;
};
const es = (ad, bek, olc) => sonuc(String(bek) === String(olc), ad,
  String(bek) === String(olc) ? String(olc) : `beklenen=${bek} olculen=${olc}`);
const tek = (s) => O.sql(s).out.trim();
const bekle = (ms) => new Promise((r) => setTimeout(r, ms));
async function hazirOl(e) {
  for (let i = 0; i < 100 && !e.calistir('ODALAR.length'); i++) await bekle(50);
}
let REST;

// --- Sentetik kimlikler ----------------------------------------------------
const ESKI_REZ = '88888888-0000-0000-0000-00000000d001';   // cikis_yapildi
const YENI_REZ = '88888888-0000-0000-0000-00000000d002';   // giris_yapildi
const UCUNCU_REZ = '88888888-0000-0000-0000-00000000d003'; // ikinci iceride
const GECIKMIS_REZ = '88888888-0000-0000-0000-00000000d004';
const MIS_ESKI = '77777777-0000-0000-0000-00000000d001';
const MIS_YENI = '77777777-0000-0000-0000-00000000d002';
const MIS_UC = '77777777-0000-0000-0000-00000000d003';

function ekran() {
  return barEkranKur({
    html: 'pms-oda-plani.html',
    restUrl: REST,
    jwt: yerelJwt('authenticated', PMS.RESEPSIYON.sub),
    kullanici: {
      id: PMS.RESEPSIYON.sub, ad: 'Resepsiyon 810', rol: 'muhasebe_calisani',
      otel_id: '810', otelId: '810',
    },
    yetkiler: RESEPSIYON_YETKI,
  });
}

// Odanin atama kumesini bilinen bir duruma getirir. `sira` dizisi, ATAMALAR
// listesinde hangi atamanin ONCE gelecegini belirler: sunucu siralamasina
// bagimli olmadigimizi IKI yonde de olcebilmek icin.
function atamalariKur(odaId, kayitlar) {
  // Fikstur SESSIZCE basarisiz olmamali: pms_oda_atamalari uzerinde cakismayi
  // engelleyen bir EXCLUDE kisiti var ve `session_replication_role = replica`
  // KISITLARI devre disi birakmaz, yalniz tetikleyicileri. Ilk kurguda D5'in
  // ikinci atamasi bu yuzden hic yazilmamis ve test YANLIS sebeple kalmisti.
  const r = O.sql(`set session_replication_role = replica;
    delete from public.pms_oda_atamalari where oda_id='${odaId}';
    ${kayitlar.map((k) => `insert into public.pms_oda_atamalari
      (id, otel_id, rezervasyon_id, oda_id, baslangic, bitis, aktif)
      values ('${k.id}','810','${k.rez}','${odaId}',${k.bas},${k.bit},${k.aktif});`).join('\n')}
    set session_replication_role = origin;`);
  if (!r.ok) {
    throw new Error('atama fiksturu kurulamadi: '
      + (r.err.split('\n').filter((l) => /ERROR/.test(l))[0] || r.err.slice(-160)));
  }
  const say = Number(O.sql(`select count(*) from public.pms_oda_atamalari
    where oda_id='${odaId}';`).out.trim() || '0');
  if (say !== kayitlar.length) {
    throw new Error('atama fiksturu eksik: beklenen ' + kayitlar.length + ' olculen ' + say);
  }
}

try {
  await O.kur();
  const t1 = O.sql(EK_TOHUM);
  if (!t1.ok) throw new Error('A1 ek tohum: ' + t1.err.slice(-300));
  const t2 = O.sql(PMS_TOHUM);
  if (!t2.ok) throw new Error('PMS tohum: ' + t2.err.slice(-300));

  // --- Fikstur: iki misafir, dort rezervasyon ------------------------------
  const f = O.sql(`set session_replication_role = replica;
    insert into public.pms_misafirler (id, otel_id, ad, soyad) values
      ('${MIS_ESKI}','810','Eski','Konuk'),
      ('${MIS_YENI}','810','Yeni','Konuk'),
      ('${MIS_UC}','810','Ucuncu','Konuk') on conflict (id) do nothing;
    insert into public.pms_rezervasyonlar
      (id, otel_id, rezervasyon_no, misafir_id, oda_tipi_id, giris_tarihi, cikis_tarihi, durum)
    values
      ('${ESKI_REZ}','810','D-ESKI','${MIS_ESKI}','${PMS.TIP}', current_date - 20, current_date - 15, 'cikis_yapildi'),
      ('${YENI_REZ}','810','D-YENI','${MIS_YENI}','${PMS.TIP}', current_date, current_date + 2, 'giris_yapildi'),
      ('${UCUNCU_REZ}','810','D-UCUNCU','${MIS_UC}','${PMS.TIP}', current_date, current_date + 2, 'giris_yapildi'),
      ('${GECIKMIS_REZ}','810','D-GECIKMIS','${MIS_YENI}','${PMS.TIP}', current_date - 9, current_date - 3, 'giris_yapildi')
    on conflict (id) do nothing;
    update public.pms_odalar set kullanim_durumu='dolu' where id='${PMS.ODA201}';
    set session_replication_role = origin;`);
  sonuc(f.ok, 'F1 fikstur kuruldu (eski cikis_yapildi + yeni giris_yapildi)',
    f.ok ? '' : f.err.split('\n').filter((l) => /ERROR/.test(l))[0]);

  REST = await O.restBaslat({ port: 33061 });

  // =====================================================================
  // D1 — ESKI ATAMA ONCE: kanonik kusur. Duzeltmesiz kodda BURASI KIRILIR.
  // =====================================================================
  atamalariKur(PMS.ODA201, [
    { id: '99999999-0000-0000-0000-00000000d001', rez: ESKI_REZ, bas: 'current_date - 20', bit: 'current_date - 15', aktif: true },
    { id: '99999999-0000-0000-0000-00000000d002', rez: YENI_REZ, bas: 'current_date', bit: 'current_date + 2', aktif: true },
  ]);
  let e = ekran();
  await hazirOl(e);
  const sirala = (once) => e.calistir(
    `ATAMALAR.sort((a,b)=> (a.rezervasyon_id==='${once}'?-1:0) - (b.rezervasyon_id==='${once}'?-1:0)); ciz(); 'ok'`);

  sirala(ESKI_REZ);
  es('D1 ESKI atama once: oda DOLU cozumleniyor', YENI_REZ,
    e.calistir(`(doluRez(ODALAR.find(o=>o.id==='${PMS.ODA201}'))||{rez:{id:'YOK'}}).rez.id`));
  const kart1 = e.calistir(`odaKart(ODALAR.find(o=>o.id==='${PMS.ODA201}'))`);
  const ad1 = (kart1.match(/class="misafir">([^<]*)</) || ['', ''])[1];
  sonuc(/Yeni/.test(ad1) && !/Eski/.test(ad1),
    'D1b kartta DOGRU misafir yaziyor (eski konuk DEGIL)',
    ad1 || '(misafir satiri yok)');
  sonuc(/>Çıkış</.test(kart1), 'D1c kartta CIKIS dugmesi var',
    />Çıkış</.test(kart1) ? 'var' : 'YOK');
  sonuc(kart1.includes(`cikisAc('${PMS.ODA201}')`), 'D1d dugme dogru odayi cagiriyor');

  // =====================================================================
  // D2 — YENI ATAMA ONCE: ayni sonuc (siralamadan BAGIMSIZ olmali)
  // =====================================================================
  sirala(YENI_REZ);
  es('D2 YENI atama once: ayni sonuc', YENI_REZ,
    e.calistir(`(doluRez(ODALAR.find(o=>o.id==='${PMS.ODA201}'))||{rez:{id:'YOK'}}).rez.id`));
  const kart2 = e.calistir(`odaKart(ODALAR.find(o=>o.id==='${PMS.ODA201}'))`);
  sonuc(/>Çıkış</.test(kart2), 'D2b siralama degisince de CIKIS dugmesi var');

  // =====================================================================
  // D3 — ICERIDE MISAFIR YOK: yalniz eski/cikis_yapildi atama kaldi
  // =====================================================================
  atamalariKur(PMS.ODA201, [
    { id: '99999999-0000-0000-0000-00000000d001', rez: ESKI_REZ, bas: 'current_date - 20', bit: 'current_date - 15', aktif: true },
  ]);
  e = ekran();
  await hazirOl(e);
  es('D3 iceride misafir yok: doluRez null', 'null',
    e.calistir(`String(doluRez(ODALAR.find(o=>o.id==='${PMS.ODA201}'))===null)==='true'?'null':'DOLU'`));
  const kart3 = e.calistir(`odaKart(ODALAR.find(o=>o.id==='${PMS.ODA201}'))`);
  sonuc(!/>Çıkış</.test(kart3), 'D3b bos odada CIKIS dugmesi YOK');

  // =====================================================================
  // D4 — GECIKMIS KONAKLAMA: planlanan cikis GECMIS ama giris_yapildi
  // =====================================================================
  atamalariKur(PMS.ODA201, [
    { id: '99999999-0000-0000-0000-00000000d003', rez: GECIKMIS_REZ, bas: 'current_date - 9', bit: 'current_date - 3', aktif: true },
  ]);
  e = ekran();
  await hazirOl(e);
  es('D4 gecikmis konaklama DOLU sayiliyor', GECIKMIS_REZ,
    e.calistir(`(doluRez(ODALAR.find(o=>o.id==='${PMS.ODA201}'))||{rez:{id:'YOK'}}).rez.id`));
  sonuc(/>Çıkış</.test(e.calistir(`odaKart(ODALAR.find(o=>o.id==='${PMS.ODA201}'))`)),
    'D4b gecikmis konaklamada CIKIS dugmesi var');

  // =====================================================================
  // D5 — BIRDEN FAZLA ICERIDE KONAKLAMA: RASTGELE SECIM YAPILMAZ
  // Tutarsiz veri. Yanlis misafirin check-out'u sessizce yapilamamali.
  // =====================================================================
  atamalariKur(PMS.ODA201, [
    // Tarihler CAKISMIYOR (EXCLUDE kisiti) ama IKISI de `giris_yapildi`:
    // cikis yapilmamis eski bir konaklama + bugunku konaklama. Gercekte
    // gorulebilecek tutarsizlik bicimi budur.
    { id: '99999999-0000-0000-0000-00000000d004', rez: GECIKMIS_REZ, bas: 'current_date - 9', bit: 'current_date - 3', aktif: true },
    { id: '99999999-0000-0000-0000-00000000d005', rez: YENI_REZ, bas: 'current_date', bit: 'current_date + 2', aktif: true },
  ]);
  e = ekran();
  await hazirOl(e);
  es('D5 belirsizlik ISARETLENIYOR (sessiz secim yok)', 'true',
    e.calistir(`String(!!(doluRez(ODALAR.find(o=>o.id==='${PMS.ODA201}'))||{}).belirsiz)`));
  es('D5b aday sayisi 2 olarak raporlaniyor', 2,
    e.calistir(`((doluRez(ODALAR.find(o=>o.id==='${PMS.ODA201}'))||{adaylar:[]}).adaylar||[]).length`));
  const kart5 = e.calistir(`odaKart(ODALAR.find(o=>o.id==='${PMS.ODA201}'))`);
  sonuc(/disabled/.test(kart5) && />Çıkış</.test(kart5),
    'D5c CIKIS dugmesi gorunur ama PASIF (yanlis misafir cikarilamaz)');
  // Siralama degissin: hangi kayit once gelirse gelsin sonuc AYNI olmali.
  const once1 = e.calistir(`JSON.stringify(((doluRez(ODALAR.find(o=>o.id==='${PMS.ODA201}'))||{adaylar:[]}).adaylar||[]).map(x=>x.rez.id).sort())`);
  e.calistir(`ATAMALAR.reverse(); ciz(); 'ok'`);
  const once2 = e.calistir(`JSON.stringify(((doluRez(ODALAR.find(o=>o.id==='${PMS.ODA201}'))||{adaylar:[]}).adaylar||[]).map(x=>x.rez.id).sort())`);
  es('D5d siralama degisse de ayni aday kumesi (rastgelelik yok)', once1, once2);

  console.log('\n======================================================================');
  console.log(`SONUC: ${ok} gecti, ${fail} kaldi`);
  console.log('Yerel kanit; CANLI KABUL yerine GECMEZ.');
  console.log('======================================================================');
} catch (err) {
  console.error('\nDUR: ' + (err && err.message));
  fail++;
} finally {
  try { O.temizle(); } catch { /* yoksay */ }
}
process.exit(fail === 0 ? 0 : 1);
