// Ortak siparis numarasi uretimi — izole kanit (uretime baglanmaz).
// Migration: docs/kurulum/2026-10-11-siparis-no-sayac.sql
import { readFileSync } from 'node:fs';
import { barOrtami } from './bar-test-ortam.mjs';

const KOK = new URL('..', import.meta.url).pathname.replace(/^\/([A-Za-z]:)/, '$1');
const M1 = 'docs/kurulum/2026-10-11-siparis-no-sayac.sql';
const O = barOrtami({ ad: 'sip-no', ag: 'sip-no-net' });
const U = '11111111-0000-0000-0000-0000000000a1';
const KIM = { rol: 'authenticated', sub: U };

let ok = 0, fail = 0;
const sonuc = (g, ad, ek) => { console.log((g ? 'OK   ' : 'FAIL ') + ad + (ek ? ' — ' + ek : '')); if (g) ok++; else fail++; };
const es = (ad, bek, olc) => sonuc(String(bek) === String(olc), ad, String(bek) === String(olc) ? String(olc) : `beklenen=${bek} olculen=${olc}`);
const tek = (q) => O.sql(q).out.trim();
const tekKimlik = (q) => O.kimlikle(KIM, q).out.trim();

try {
  await O.kur();

  // Yetki fiksturu: `siparis_olustur` modulu + kayit yetkili rol + kullanici.
  // Tetikleyiciler kapaliyken kurulur: phase0_islem_audit kimliksiz yazmayi
  // reddeder, fikstur ise kimlik kurmadan once calisir.
  O.sql(`set session_replication_role = replica;
    insert into public.moduller (kod, ad, kategori, sira, aktif)
      values ('siparis_olustur','Siparis Olustur','satinalma',10,true)
      on conflict (kod) do nothing;
    insert into public.roller (id, ad, seviye, kod, sira)
      values ('00000000-0000-0000-0000-00000000f001','Satinalma','otel','satinalma_test',30)
      on conflict do nothing;
    insert into public.yetki_matrisi (rol_id, modul_id, yetki)
    select r.id, m.id, 'kayit'::public.yetki_seviye
      from public.roller r, public.moduller m
     where r.kod='satinalma_test' and m.kod='siparis_olustur'
      on conflict (rol_id, modul_id) do nothing;
    insert into auth.users (id, email) values ('${U}','sip-no@test.local')
      on conflict (id) do nothing;
    insert into public.kullanicilar (id, auth_user_id, ad, rol, otel_id, aktif, rol_id)
    select gen_random_uuid(), '${U}'::uuid, 'Sip No Test', 'muhasebe_calisani', '810', true, r.id
      from public.roller r where r.kod='satinalma_test';
    set session_replication_role = origin;`);

  const m = O.uygulaTekIslem(M1);
  sonuc(m.ok, 'F1 migration uygulandi', m.ok ? '' : m.err.split('\n').filter(l => /ERROR/.test(l))[0]);

  // N-B1 (Review Focus 3): bos tabloda ilk numara tabandan uretilir
  O.sql("delete from public.siparisler where siparis_no ~ '^C[0-9]{8}$';");
  O.sql("update public.siparis_no_sayac set son_no = 91110 where prefix = 'C';");
  es('N-B1 bos tabloda ilk numara', 'C00091111',
    tekKimlik("select public.siparis_no_uret('C');"));

  // N1: ardisik iki cagri farkli ve artan
  const a = tekKimlik("select public.siparis_no_uret('C');");
  const b = tekKimlik("select public.siparis_no_uret('C');");
  sonuc(a !== b && b > a, 'N1 ardisik numaralar farkli ve artan', a + ' -> ' + b);

  // N2: bicim korunuyor
  sonuc(/^C[0-9]{8}$/.test(b), 'N2 bicim C + 8 hane', b);

  // N3: gecersiz onek reddedilir
  const r3 = O.kimlikle(KIM, "select public.siparis_no_uret('X');");
  sonuc(!r3.ok && /onek_gecersiz/.test(r3.err), 'N3 gecersiz onek reddedildi');

  // N4 (DUMAN): 6 ardisik-paralel cagri -> 6 farkli numara, bicim dogru.
  // DIKKAT: bu testin kilit kaniti olarak disi YOKTUR — olculdu, `for update`
  // kaldirildiginda da 6 farkli numara cikiyor, cunku 6 `docker exec` sureci
  // gercekte cakismiyor. Kilit kaniti N4d'dir.
  const kosum = await Promise.all(
    Array.from({ length: 6 }, () => O.paralel(KIM, "select public.siparis_no_uret('R');")));
  const numaralar = kosum.map(r => r.out.trim()).filter(Boolean);
  es('N4a alti cagri da basarili', 6, kosum.filter(r => r.ok).length);
  es('N4b alti numara da FARKLI', 6, new Set(numaralar).size);
  sonuc(numaralar.every(n => /^R[0-9]{8}$/.test(n)), 'N4c hepsi bicime uygun');

  // N4d KILIT KANITI (deterministik cakisma):
  //   A: numarayi alir, 2 sn bekler, SONRA commit eder -> kilidi tutar.
  //   B: 0.4 sn sonra baslar. `for update` varsa A'nin commit'ini BEKLER ve
  //      A'nin yazdigi son_no'yu gorur -> FARKLI numara.
  //      `for update` yoksa B bayat son_no'yu okur -> AYNI numarayi uretir.
  const noAyikla = (r) => (String(r.out).split('\n').map(x => x.trim())
    .find(x => /^C[0-9]{8}$/.test(x)) || '');
  const kilitKanit = async () => {
    const A = O.paralel(KIM, "select public.siparis_no_uret('C'); select pg_sleep(2);");
    await new Promise(r => setTimeout(r, 400));
    const B = O.paralel(KIM, "select public.siparis_no_uret('C');");
    const [ra, rb] = await Promise.all([A, B]);
    return { ra, rb, a: noAyikla(ra), b: noAyikla(rb) };
  };
  const k = await kilitKanit();
  sonuc(k.ra.ok && k.rb.ok, 'N4d-1 iki oturum da basarili',
    'A=' + k.a + ' B=' + k.b);
  sonuc(k.a !== '' && k.b !== '' && k.a !== k.b,
    'N4d-2 kilit altinda numaralar FARKLI', k.a + ' vs ' + k.b);

  // N5: sayac geride birakilirsa `greatest` toparliyor
  O.sql(`set session_replication_role = replica;
    delete from public.siparisler where siparis_no ~ '^R[0-9]{8}$';
    insert into public.siparisler (siparis_no, firma_ad, otel_id, tarih)
      values ('R00099999','Toparlama Test','810', current_date);
    set session_replication_role = origin;`);
  O.sql("update public.siparis_no_sayac set son_no = 1 where prefix = 'R';");
  es('N5 sayac geride ise maksimumdan devam', 'R00100000',
    tekKimlik("select public.siparis_no_uret('R');"));

  // N6 MUTANT: `for update` kaldirilirsa AYNI deterministik kurguda iki oturum
  // AYNI numarayi alir. N4d'nin disi budur.
  const asil = readFileSync(KOK + M1, 'utf8');
  const mutant = asil.replace('where prefix = p_prefix for update;', 'where prefix = p_prefix;');
  if (mutant === asil) throw new Error('N6 capasi tutmadi');
  O.uygulaTekIslem(mutant, { metin: true });
  const mk = await kilitKanit();
  sonuc(mk.a !== '' && mk.a === mk.b,
    'N6 MUTANT: kilit kalkinca IKI oturum ayni numarayi aliyor',
    mk.a + ' vs ' + mk.b);
  O.uygulaTekIslem(M1);   // orijinali geri kur

  console.log(`\nSONUC: ${ok} gecti, ${fail} kaldi`);
} catch (e) { console.error('DUR: ' + (e && e.message)); fail++; }
finally { try { O.temizle(); } catch { /* yoksay */ } }
process.exit(fail === 0 ? 0 : 1);
