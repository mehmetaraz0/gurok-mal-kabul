// scripts/bar-test-taban.test.mjs — izole tabanin kendisini dogrular.
import { readFileSync } from 'node:fs';
import { barOrtami, SEMA_DOKUMU } from './bar-test-ortam.mjs';

const O = barOrtami({ ad: 'bar-taban' });
let ok = 0, fail = 0;
const sonuc = (g, ad, ek) => { console.log((g ? 'OK   ' : 'FAIL ') + ad + (ek ? ' — ' + ek : '')); if (g) ok++; else fail++; };

try {
  // Taban, dokumden sonra uretime uygulanan migration'lari (URETIM_SONRASI) kendisi kurar.
  await O.kur();
  const kb = O.kurulumBilgisi;
  sonuc(kb.dokumHata === 0 && kb.dokumZararsiz === 1,
    'taban kuruldu: shim + kimlik katmani + uretim dokumu + uretim-sonrasi migrationlar + tohum',
    `dokum: ${kb.dokumHata} hata, ${kb.dokumZararsiz} bilinen zararsiz (schema public already exists)`);

  // Uretimi temsil ediyor mu: stok RPC govdeleri 2026-09-18 uretim olcumuyle ayni
  // (kur() zaten tutmazsa durur; burada rapora gecsin diye ayrica yazilir) ve
  // tarih duzeltmesini tasiyor.
  const tarih = O.sql(`select bool_and(prosrc ~* 'guncelleme_tarihi\\s*=\\s*now\\(\\)') from pg_proc
    where pronamespace = 'public'::regnamespace and proname in ('stok_ekle','stok_transfer');`);
  sonuc(tarih.out === 't' && /43ec3cfc/.test(kb.stokMd5) && /8dd27c19/.test(kb.stokMd5),
    'stok RPC govdeleri uretimle ayni (md5) ve tarih duzeltmesini tasiyor', kb.stokMd5.replace(/\n/g, ' '));

  // Beklenen sayilar TAHMIN edilmez: dokumun kendisinden sayilir ve yuklenen
  // katalogla karsilastirilir. Sessizce eksik yuklenen nesne burada gorunur.
  const dokum = readFileSync(SEMA_DOKUMU, 'utf8');
  const dokumSay = (re) => (dokum.match(re) || []).length;
  const bekFonk = dokumSay(/^CREATE FUNCTION public\.bar_[a-z_]+\(/gm);
  const bekPol = dokumSay(/^CREATE POLICY \S+ ON public\.(bar_siparisleri|bar_siparis_kalemleri|menu_urunler|recete_bilesenleri|stok_rezervasyonlari) /gm);
  const bekTet = dokumSay(/^CREATE TRIGGER \S+ (BEFORE|AFTER) [^\n]* ON public\.bar_siparisleri /gm);
  const nesne = O.sql(`select
      (select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace
        where n.nspname='public' and p.proname like 'bar\\_%'),
      (select count(*) from pg_policy where polrelid in ('public.bar_siparisleri'::regclass,'public.bar_siparis_kalemleri'::regclass,
         'public.menu_urunler'::regclass,'public.recete_bilesenleri'::regclass,'public.stok_rezervasyonlari'::regclass)),
      (select count(*) from pg_trigger where tgrelid='public.bar_siparisleri'::regclass and not tgisinternal);`);
  const bek = `${bekFonk}|${bekPol}|${bekTet}`;
  sonuc(nesne.ok && bekFonk > 0 && nesne.out === bek,
    'uretim bar nesneleri dokumdeki sayilarla birebir yuklendi (fonksiyon|politika|tetikleyici)',
    `katalog ${nesne.out || nesne.err} / dokum ${bek}`);

  const uid = O.kimlikle({ rol: 'authenticated', sub: '11111111-0000-0000-0000-000000000810' }, 'select auth.uid();');
  sonuc(uid.out === '11111111-0000-0000-0000-000000000810', 'auth.uid() request.jwt.claims JSONundan okunuyor', uid.out || uid.err);

  const y = O.kimlikle({ rol: 'authenticated', sub: '11111111-0000-0000-0000-000000000810' },
    "select public.auth_yetki_var('bar_siparis_yonetimi','kayit'), public.auth_otel_erisim('810'), public.auth_otel_erisim('811');");
  sonuc(y.out === 't|t|f', 'BAR810: bar kayit yetkisi var, 810 erisimi var, 811 yok', y.out || y.err);

  const p = O.kimlikle({ rol: 'authenticated', sub: '11111111-0000-0000-0000-0000000000aa' },
    "select public.auth_yetki_var('bar_siparis_yonetimi','kayit');");
  sonuc(p.out === 'f', 'PASIF kullanicinin yetkisi yok (fail-closed)', p.out || p.err);

  const s = O.sql(`select count(*) from public.bar_siparisleri;`);
  sonuc(s.out === '0', 'bar siparis tablosu bos basliyor', s.out);

  const r = O.kimlikle({ rol: 'authenticated', sub: '11111111-0000-0000-0000-000000000810' },
    `select public.bar_siparis_olustur('810','810_CSM302','Masa 1',null,'[{"menu_urun_id":"22222222-0000-0000-0000-000000000001","adet":2}]'::jsonb) is not null;`);
  sonuc(r.out === 't', 'mevcut (uretim) bar_siparis_olustur tabanda calisiyor', r.out || r.err.slice(-160));

  // TASARIM OLCUMU (Z1): bar yetkisi olmayan depo kullanicisi aktif rezervasyonu
  // GOREBILIYOR mu? Goremiyorsa, cagiranin haklariyla calisan bir stok cikis
  // korumasi rezervasyon toplamini 0 okur ve sessizce devre disi kalir.
  const gercek = O.sql(`select count(*) from public.stok_rezervasyonlari where durum='aktif';`).out;
  const depo = O.kimlikle({ rol: 'authenticated', sub: '11111111-0000-0000-0000-0000000000cc' },
    'select count(*) from public.stok_rezervasyonlari;');
  sonuc(gercek === '1' && depo.ok && depo.out === '0',
    'Z1 olcumu: aktif rezervasyon var ama depo kullanicisi onu RLS yuzunden GOREMIYOR',
    `gercek ${gercek}, depo kullanicisi goruyor ${depo.out || depo.err}`);
} catch (e) {
  sonuc(false, 'taban kurulumu', e.message);
} finally {
  O.temizle();
}
console.log('\nBAR TABAN SONUC: ' + ok + ' OK / ' + fail + ' FAIL');
process.exit(fail ? 1 : 0);
