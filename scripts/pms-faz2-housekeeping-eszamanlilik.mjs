// ============================================================================
// PMS FAZ 2 — KAT HİZMETLERİ EŞ ZAMANLILIK TESTLERİ (GERÇEK ÇOK OTURUM)
// ----------------------------------------------------------------------------
// YALNIZ ATILABILIR YEREL DOCKER STAGING'DE ÇALIŞIR.
//   node scripts/pms-faz2-housekeeping-eszamanlilik.mjs [konteyner] [veritabani]
//
// ---------------------------------------------------------------------------
// YÖNTEM — UYKU DEĞİL, GERÇEK KİLİT BARİYERİ
// ---------------------------------------------------------------------------
// İki AYRI psql oturumu açılır. Oturum A bir transaction içinde komutu
// çalıştırır ama COMMIT ETMEZ; böylece görev/oda satır kilidini TUTAR.
// Oturum B aynı işi denediğinde GERÇEKTEN BLOKE OLUR — bu bloke oluş
// bariyerdir ve zamanlamaya değil kilide dayanır.
//
// Bloke oluş, B'nin belirlenen süre içinde yanıt vermemesiyle ÖLÇÜLÜR; sonra
// A commit edilir ve B'nin çözülüp hangi sonucu verdiği okunur.
//
// "sleep koydum, herhalde çakıştı" bir kanıt değildir; bu dosya öyle
// çalışmaz. Bloke olmayan bir senaryo AÇIKÇA raporlanır.
// ============================================================================

import { spawn } from 'node:child_process';

const KONTEYNER = process.argv[2] || 'hk';
const VT         = process.argv[3] || 'hkdb';
const NOKTA      = '<<<BITTI>>>';

let ok = 0, fail = 0;
const rapor = [];

function oturum(ad) {
  // stderr, KONTEYNER ICINDE stdout'a birlestirilir. Iki ayri boru
  // kullanildiginda hata metni ile `\echo` isaretcisi Node'a FARKLI SIRADA
  // ulasabiliyor; isaretci once gelirse okunan parca BOS oluyor ve B'nin
  // gercek hatasi "basarili" gibi gorunuyordu. Birlestirme sirayi garanti eder.
  const p = spawn('docker',
    ['exec', '-i', KONTEYNER, 'sh', '-c',
     `psql -X -U postgres -d ${VT} -q -A -t -P pager=off 2>&1`],
    { stdio: ['pipe', 'pipe', 'pipe'] });
  // KUYRUK: zaman asimina ugrayan bir cagrinin ciktisi KAYBOLMAZ. Bloke olan
  // oturum cozuldugunde uretilen metin sirada bekler ve sonraki okuma onu
  // alir. Onceki surum yalnizca "son tampon"a bakiyordu; bu yuzden B'nin
  // gercek hata metni yerine bos dize okunabiliyordu (EZ-A yanlis FAIL).
  const o = { ad, p, tampon: '', kuyruk: [], bekleyen: null };
  const dagit = () => {
    if (o.bekleyen && o.kuyruk.length) {
      const b = o.bekleyen; o.bekleyen = null;
      b.coz(o.kuyruk.shift());
    }
  };
  o.dagit = dagit;
  const yut = (d) => {
    o.tampon += d.toString();
    let i;
    while ((i = o.tampon.indexOf(NOKTA)) !== -1) {
      o.kuyruk.push(o.tampon.slice(0, i).trim());
      o.tampon = o.tampon.slice(i + NOKTA.length);
    }
    dagit();
  };
  p.stdout.on('data', yut);
  p.stderr.on('data', yut);
  return o;
}

// SQL gonderir ve NOKTA gelene kadar bekler. `msSinir` icinde gelmezse
// BLOKE kabul edilir ve `null` doner (bu bir hata degil, olcumdur).
function gonder(o, sql, msSinir = 4000) {
  return new Promise((coz) => {
    let bitti = false;
    o.p.stdin.write(sql + `\n\\echo ${NOKTA}\n`);
    o.bekleyen = { coz: (c) => { if (!bitti) { bitti = true; coz(c); } } };
    o.dagit();                       // sirada bekleyen ciktiyi hemen ver
    setTimeout(() => {
      if (!bitti) { bitti = true; o.bekleyen = null; coz(null); }
    }, msSinir);
  });
}

const kapat = (o) => { try { o.p.stdin.end(); } catch {} };

async function tekSorgu(sql) {
  const o = oturum('tek');
  const r = await gonder(o, sql, 15000);
  kapat(o);
  return (r || '').trim();
}

// Bir senaryonun on kosulu tutmazsa test HICBIR SEY olcmez; yesil gorunen
// ama bos calisan senaryo kabul edilemez. Bu sarmalayici kurulumu DURDURUR.
async function kurulum(etiket, sql) {
  const r = await tekSorgu(sql);
  if (!r || /ERROR|HATA/i.test(r)) {
    console.error('KURULUM BASARISIZ (' + etiket + '): [' + r + ']');
    process.exit(1);
  }
  return r;
}

const kisalt = (x) => String(x === null ? '<BLOKE/YANIT YOK>' : x)
  .replace(/\s+/g, ' ').trim().slice(0, 110);

function sonuc(kod, gecti, satir) {
  if (gecti) { ok++; console.log(`${kod}  OK    ${satir}`); }
  else { fail++; console.log(`${kod}  FAIL  ${satir}`); }
}

// ---------------------------------------------------------------------------
// FİKSTÜR — commit edilir (ayri oturumlar gorebilsin), sonunda temizlenir
// ---------------------------------------------------------------------------
const FIKSTUR = `
begin;
update public.moduller set aktif = true where kod = 'pms_housekeeping';
insert into public.moduller (kod, ad, kategori, sira, aktif)
values ('pms_oda','On Buro - Odalar','onburo',44,true)
on conflict (kod) do update set aktif = true;

drop table if exists public.ez_fikstur;
create table public.ez_fikstur (ad text primary key, deger uuid);

do $f$
declare
  v_rol uuid; v_rolw uuid;
  v_a1 uuid := gen_random_uuid(); v_a2 uuid := gen_random_uuid(); v_as uuid := gen_random_uuid();
  v_w1 uuid; v_w2 uuid; v_sup uuid;
  v_tip uuid; v_oda uuid; v_oda2 uuid; v_g uuid; v_r jsonb;
  -- Dosya ayni atilabilir veritabaninda birden cok kez calisabilmeli:
  -- oda_no ve tip kodu otel icinde benzersiz, bu yuzden her kosuya ozgu ek.
  v_ek text := substr(md5(random()::text || clock_timestamp()::text), 1, 6);
begin
  insert into public.roller (ad, seviye) values ('EZ Sup '||v_ek,'otel')    returning id into v_rol;
  insert into public.roller (ad, seviye) values ('EZ Worker '||v_ek,'otel') returning id into v_rolw;
  insert into public.yetki_matrisi (rol_id, modul_id, yetki)
  select v_rol, id, 'tam' from public.moduller where kod in ('pms_housekeeping','pms_oda');
  insert into public.yetki_matrisi (rol_id, modul_id, yetki)
  select v_rolw, id, 'kayit' from public.moduller where kod = 'pms_housekeeping';

  insert into auth.users (id) values (v_a1), (v_a2), (v_as);
  insert into public.kullanicilar (ad, rol, rol_id, otel_id, aktif, auth_user_id)
  values ('EZ W1','depo', v_rolw,'810', true, v_a1) returning id into v_w1;
  insert into public.kullanicilar (ad, rol, rol_id, otel_id, aktif, auth_user_id)
  values ('EZ W2','depo', v_rolw,'810', true, v_a2) returning id into v_w2;
  insert into public.kullanicilar (ad, rol, rol_id, otel_id, aktif, auth_user_id)
  values ('EZ Sup','yonetici', v_rol,'810', true, v_as) returning id into v_sup;

  insert into public.pms_oda_tipleri (otel_id,kod,ad,azami_kisi,azami_yetiskin,azami_cocuk)
  values ('810','ez'||v_ek,'EZ '||v_ek,2,2,1) returning id into v_tip;
  insert into public.pms_odalar (otel_id,oda_tipi_id,oda_no)
  values ('810',v_tip,'EZ1-'||v_ek) returning id into v_oda;
  insert into public.pms_odalar (otel_id,oda_tipi_id,oda_no)
  values ('810',v_tip,'EZ2-'||v_ek) returning id into v_oda2;

  perform set_config('request.jwt.claim.role','authenticated',true);
  perform set_config('request.jwt.claim.sub', v_as::text, true);
  v_r := public.pms_housekeeping_gorev_olustur(v_oda,'ekstra_temizlik','bos',gen_random_uuid());
  v_g := (v_r->>'gorev_id')::uuid;

  insert into public.ez_fikstur values
    ('a1',v_a1),('a2',v_a2),('as',v_as),
    ('w1',v_w1),('w2',v_w2),('sup',v_sup),
    ('oda',v_oda),('oda2',v_oda2),('gorev',v_g);
end
$f$;
commit;
`;

// JWT ayari SESSIZ olmalidir. `select set_config(...)` bir SATIR dondurur;
// tekSorgu tum ciktiyi geri verdigi icin bu satirlar sonuca karisiyor ve
// arkasindan gelen degeri (ornegin bir gorev kimligini) kullanilamaz hale
// getiriyordu. DO blogu hicbir satir dondurmez.
const JWT = (auth) => `
reset role;
do $j$ begin
  perform set_config('request.jwt.claim.role','authenticated',false);
  perform set_config('request.jwt.claim.sub',
    (select deger from public.ez_fikstur where ad='${auth}')::text, false);
end $j$;
`;

async function calis() {
  console.log('=== FIKSTUR ===');
  const f = await tekSorgu(FIKSTUR);
  if (f === null || /ERROR/i.test(f)) { console.error('Fikstur kurulamadi:\n' + f); process.exit(1); }
  console.log('fikstur hazir');

  // =====================================================================
  // EZ-A  İKİ ÇALIŞAN AYNI GÖREVİ SAHİPLENİYOR
  // =====================================================================
  {
    const A = oturum('A'), B = oturum('B');
    await gonder(A, JWT('a1'));
    await gonder(B, JWT('a2'));

    await gonder(A, `begin;`);
    const ra = await gonder(A, `select public.pms_housekeeping_sahiplen(
      (select deger from public.ez_fikstur where ad='gorev'),
      (select surum from public.pms_housekeeping_gorevleri
        where id=(select deger from public.ez_fikstur where ad='gorev')),
      gen_random_uuid())->>'atanan';`);

    // B ayni gorevi dener: A gorev satirini KILITLI tuttugu icin BLOKE olmali
    const bloke = await gonder(B, `begin;
      select public.pms_housekeeping_sahiplen(
        (select deger from public.ez_fikstur where ad='gorev'),
        (select surum from public.pms_housekeeping_gorevleri
          where id=(select deger from public.ez_fikstur where ad='gorev')),
        gen_random_uuid())->>'atanan';`, 3000);

    const blokeOldu = (bloke === null);
    await gonder(A, `commit;`);
    const rb = await gonder(B, ``, 8000);      // A commit etti; B cozulmeli
    await gonder(B, `rollback;`, 5000);

    const kazanan = await tekSorgu(`select k.ad from public.pms_housekeeping_gorevleri g
      join public.kullanicilar k on k.id=g.atanan_kullanici_id
      where g.id=(select deger from public.ez_fikstur where ad='gorev');`);

    const bKaybetti = rb === null || /ERROR|CAKISMASI|zaten atanmis/i.test(rb || '');
    sonuc('EZ-A', blokeOldu && bKaybetti && kazanan === 'EZ W1',
      `A sahiplendi, B ${blokeOldu ? 'KILITTE BLOKE OLDU' : 'bloke OLMADI'}, ` +
      `B sonucu: ${bKaybetti ? 'catisma' : 'BASARILI(!)'} ham=[${kisalt(rb)}], kazanan: ${kazanan}`);
    rapor.push({ test:'EZ-A', a:'sahiplen', b:'sahiplen', bariyer:'gorev satir kilidi',
      kazanan:'A (EZ W1)', kaybeden:'B (catisma)', oda:'kirli', gorev:'bekliyor+atanmis' });
    kapat(A); kapat(B);
  }

  // =====================================================================
  // EZ-B  AYNI ODAYA İKİ GÖREV OLUŞTURMA
  // =====================================================================
  {
    const A = oturum('A'), B = oturum('B');
    await gonder(A, JWT('as'));
    await gonder(B, JWT('as'));

    await gonder(A, `begin;`);
    await gonder(A, `select public.pms_housekeeping_gorev_olustur(
      (select deger from public.ez_fikstur where ad='oda2'),'ekstra_temizlik','bos',gen_random_uuid())->>'gorev_id';`);

    const bloke = await gonder(B, `begin;
      select public.pms_housekeeping_gorev_olustur(
        (select deger from public.ez_fikstur where ad='oda2'),'ekstra_temizlik','bos',gen_random_uuid())->>'gorev_id';`, 3000);
    const blokeOldu = (bloke === null);

    await gonder(A, `commit;`);
    const rb = await gonder(B, ``, 8000);
    await gonder(B, `rollback;`, 5000);

    const adet = await tekSorgu(`select count(*)::text from public.pms_housekeeping_gorevleri
      where oda_id=(select deger from public.ez_fikstur where ad='oda2')
        and durum in ('bekliyor','temizleniyor');`);

    sonuc('EZ-B', blokeOldu && adet === '1',
      `A olusturdu, B ${blokeOldu ? 'BLOKE OLDU' : 'bloke olmadi'}, ` +
      `bitmemis gorev sayisi: ${adet} (1 olmali)`);
    rapor.push({ test:'EZ-B', a:'gorev_olustur', b:'gorev_olustur', bariyer:'oda satir kilidi + aktif_oda_uniq',
      kazanan:'A', kaybeden:'B (benzersizlik/catisma)', oda:'kirli', gorev:'tek bitmemis' });
    kapat(A); kapat(B);
  }

  // =====================================================================
  // EZ-C  TAMAMLAMA vs İPTAL
  // =====================================================================
  {
    // once gorevi calisir hale getir
    await tekSorgu(`${JWT('a1')}
      select public.pms_housekeeping_baslat(
        (select deger from public.ez_fikstur where ad='gorev'),
        (select surum from public.pms_housekeeping_gorevleri
          where id=(select deger from public.ez_fikstur where ad='gorev')),
        gen_random_uuid())->>'durum';`);

    const A = oturum('A'), B = oturum('B');
    await gonder(A, JWT('a1'));    // isi yapan: tamamla
    await gonder(B, JWT('as'));    // supervisor: iptal

    await gonder(A, `begin;`);
    await gonder(A, `select public.pms_housekeeping_tamamla(
      (select deger from public.ez_fikstur where ad='gorev'),
      (select surum from public.pms_housekeeping_gorevleri
        where id=(select deger from public.ez_fikstur where ad='gorev')),
      gen_random_uuid())->>'durum';`);

    const bloke = await gonder(B, `begin;
      select public.pms_housekeeping_iptal(
        (select deger from public.ez_fikstur where ad='gorev'),'iptal denemesi',
        (select surum from public.pms_housekeeping_gorevleri
          where id=(select deger from public.ez_fikstur where ad='gorev')),
        gen_random_uuid())->>'durum';`, 3000);
    const blokeOldu = (bloke === null);

    await gonder(A, `commit;`);
    const rb = await gonder(B, ``, 8000);
    await gonder(B, `rollback;`, 5000);

    const son = await tekSorgu(`select g.durum || '|' || o.temizlik_durumu::text
      from public.pms_housekeeping_gorevleri g
      join public.pms_odalar o on o.id=g.oda_id
      where g.id=(select deger from public.ez_fikstur where ad='gorev');`);

    sonuc('EZ-C', blokeOldu && son === 'tamamlandi|temiz',
      `A tamamladi, B ${blokeOldu ? 'BLOKE OLDU' : 'bloke olmadi'} ve kaybetti; ` +
      `son durum: ${son}`);
    rapor.push({ test:'EZ-C', a:'tamamla', b:'iptal', bariyer:'gorev satir kilidi',
      kazanan:'A (tamamla)', kaybeden:'B (terminal/catisma)', oda:'temiz', gorev:'tamamlandi' });
    kapat(A); kapat(B);
  }

  // =====================================================================
  // EZ-D  TAMAMLAMA vs CHECK-IN  (oda satiri seri hale getirir)
  // =====================================================================
  {
    // oda2 icin yeni gorev + calisan hale getir
    const g2 = await kurulum('EZ-D gorev bul', `${JWT('a1')}
      select g.id::text from public.pms_housekeeping_gorevleri g
      where g.oda_id=(select deger from public.ez_fikstur where ad='oda2')
        and g.durum='bekliyor' limit 1;`);
    if (!/^[0-9a-f-]{36}$/.test(g2)) {
      console.error('KURULUM BASARISIZ (EZ-D): gorev kimligi okunamadi: [' + g2 + ']');
      process.exit(1);
    }
    await kurulum('EZ-D sahiplen', `${JWT('a1')}
      select public.pms_housekeeping_sahiplen('${g2}'::uuid,
        (select surum from public.pms_housekeeping_gorevleri where id='${g2}'), gen_random_uuid());`);
    await kurulum('EZ-D baslat', `${JWT('a1')}
      select public.pms_housekeeping_baslat('${g2}'::uuid,
        (select surum from public.pms_housekeeping_gorevleri where id='${g2}'), gen_random_uuid());`);
    // On kosul KANITLANIR: oda gercekten temizleniyor durumunda mi?
    const onKosul = await tekSorgu(`select o.temizlik_durumu::text
      from public.pms_odalar o where o.id=(select deger from public.ez_fikstur where ad='oda2');`);
    if (onKosul !== 'temizleniyor') {
      console.error('KURULUM BASARISIZ (EZ-D): on kosul tutmadi, oda temizlik=' + onKosul);
      process.exit(1);
    }

    const A = oturum('A'), B = oturum('B');
    await gonder(A, JWT('a1'));
    await gonder(B, JWT('as'));

    await gonder(A, `begin;`);
    await gonder(A, `select public.pms_housekeeping_tamamla('${g2}'::uuid,
      (select surum from public.pms_housekeeping_gorevleri where id='${g2}'), gen_random_uuid())->>'oda_temizlik';`);

    // B: odayi dolu yapmaya calisir (check-in benzeri dogrudan gecis) — oda
    // kilidinde BLOKE olmali
    const bloke = await gonder(B, `begin;
      set local role authenticated;
      update public.pms_odalar set kullanim_durumu='dolu'
       where id=(select deger from public.ez_fikstur where ad='oda2');`, 3000);
    const blokeOldu = (bloke === null);

    await gonder(A, `commit;`);
    const rb = await gonder(B, ``, 8000);
    await gonder(B, `rollback;`, 5000);

    const son = await tekSorgu(`select o.kullanim_durumu::text || '|' || o.temizlik_durumu::text
      from public.pms_odalar o where o.id=(select deger from public.ez_fikstur where ad='oda2');`);

    sonuc('EZ-D', blokeOldu && son === 'bos|temiz',
      `A tamamladi (oda temiz), B ${blokeOldu ? 'ODA KILIDINDE BLOKE OLDU' : 'bloke olmadi'}; ` +
      `son oda: ${son}, B ham=[${kisalt(rb)}]`);
    rapor.push({ test:'EZ-D', a:'tamamla', b:'oda dolu yaz', bariyer:'oda satir kilidi',
      kazanan:'A (tamamla)', kaybeden:'B (bekledi, sonra RLS/bekci)', oda:'bos|temiz', gorev:'tamamlandi' });
    kapat(A); kapat(B);
  }

  // =====================================================================
  // EZ-E  MODÜL DEVRE DIŞI vs UÇUŞTAKİ KOMUT (tahliye bariyeri)
  // =====================================================================
  {
    // EZ-E kendi gorevini URETIR: onceki senaryolar gorevleri tuketiyor ve
    // "uygun gorev yok" diye ATLANMAK bir kanit degil, olcum kaybidir.
    const g3 = await kurulum('EZ-E gorev uret', `${JWT('as')}
      select (public.pms_housekeeping_gorev_olustur(
        (select deger from public.ez_fikstur where ad='oda'),
        'ekstra_temizlik','bos',gen_random_uuid())->>'gorev_id')::text;`);
    if (!/^[0-9a-f-]{36}$/.test(g3)) {
      console.error('KURULUM BASARISIZ (EZ-E): gorev kimligi okunamadi: [' + g3 + ']');
      process.exit(1);
    }
    {
      const A = oturum('A'), B = oturum('B');
      await gonder(A, JWT('a1'));
      await gonder(B, JWT('as'));

      await gonder(A, `begin;`);
      await gonder(A, `select public.pms_housekeeping_sahiplen('${g3}'::uuid,
        (select surum from public.pms_housekeeping_gorevleri where id='${g3}'), gen_random_uuid())->>'atanan';`);

      // B modulu kapatmaya calisir: A modul satirini FOR SHARE tutuyor
      const bloke = await gonder(B, `begin;
        update public.moduller set aktif=false where kod='pms_housekeeping';`, 3000);
      const blokeOldu = (bloke === null);

      await gonder(A, `commit;`);
      const rb = await gonder(B, ``, 8000);
      await gonder(B, `rollback;`, 5000);

      sonuc('EZ-E', blokeOldu,
        `A komutu ucusta, B devre disi birakma ${blokeOldu ? 'TAHLIYE BARIYERINDE BEKLEDI' : 'BEKLEMEDI'}`);
      rapor.push({ test:'EZ-E', a:'sahiplen (ucusta)', b:'modul aktif=false',
        bariyer:'moduller satiri FOR SHARE', kazanan:'A once biter',
        kaybeden:'B bekler (tahliye)', oda:'degismedi', gorev:'atanmis' });
      kapat(A); kapat(B);
    }
  }

  // =====================================================================
  // TEMİZLİK
  // =====================================================================
  await tekSorgu(`drop table if exists public.ez_fikstur;`);

  console.log('\n=== SENARYO RAPORU ===');
  for (const r of rapor) {
    console.log(`${r.test}: A=${r.a} | B=${r.b} | bariyer=${r.bariyer}`);
    console.log(`        kazanan=${r.kazanan} | kaybeden=${r.kaybeden} | oda=${r.oda} | gorev=${r.gorev}`);
  }
  console.log(`\nES ZAMANLILIK SONUC: ${ok} OK / ${fail} FAIL`);
  process.exit(fail > 0 ? 1 : 0);
}

calis().catch((e) => { console.error(e); process.exit(1); });
