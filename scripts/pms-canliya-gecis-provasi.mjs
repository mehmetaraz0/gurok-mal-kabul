// ===========================================================================
// PMS CANLIYA GECIS PROVASI — migration + tohumlama SIRASI iki tabanda
// ===========================================================================
// Paket belgesi: docs/kurulum/2026-10-07-pms-canliya-gecis-paketi.md
//
// NE OLCER: uc dosyanin canliya uygulanacak SIRASINI, her birinin kendi
// dogrulama blogunu, onayli kapsamin davranisini (personel normal tahsilat
// yapar; iade/indirim/duzeltme `tam` + gerekce ister), idempotensligi ve
// TERS SIRA geri almayi. Iki tabanda ayri ayri kosar:
//
//   temiz  : 2026-09-07-post-pms-faz1-sema-dokumu.sql + 02-referans-veri.sql
//            (Faz 2 nesneleri YOK, PMS modul satiri YOK — KURULUM-REHBERI'nin
//             yeni kurulum tabani)
//   mevcut : 2026-09-13-post-faz2-sema-dokumu.sql + uretim sonrasi stok
//            migration'lari + 2026-09-18-bar-a1-guvenlik.sql + 09-13 yayininin
//            urettigi kat hizmetleri izinin TEMSILI
//
// SINIR: taban semayi ve referans veriyi temsil eder, URETIM VERISINI DEGIL.
// Uretime baglanmaz, uretim verisi kopyalanmaz. Yerel kanit canli kabul
// YERINE GECMEZ.
//
// Kullanim: node scripts/pms-canliya-gecis-provasi.mjs
// ===========================================================================
import { spawnSync } from 'node:child_process';
import { degismezlikKarari } from './yayin-kabul-kurallari.mjs';
import { readFileSync, writeFileSync, unlinkSync, existsSync } from 'node:fs';

const KOK = new URL('..', import.meta.url).pathname.replace(/^\/([A-Za-z]:)/, '$1');

const TABANLAR = {
  temiz: {
    dokum: KOK + 'docs/kurulum/2026-09-07-post-pms-faz1-sema-dokumu.sql',
    uretimSonrasi: false,
    onceki: [],
    faz2: false,
  },
  mevcut: {
    dokum: 'C:/Users/USER/ERP-Yedek/2026-09-13-post-faz2-sema-dokumu.sql',
    uretimSonrasi: true,
    onceki: ['docs/kurulum/2026-09-18-bar-a1-guvenlik.sql'],
    faz2: true,
  },
};

// YP-2 negatif kontrolu icin TEK kanca: taban dokumunun yolu ortam
// degiskeniyle degistirilebilir. Yalniz `scripts/pms-canliya-gecis-provasi.test.mjs`
// kullanir ve GERCEK dokum dosyalarina dokunmaz. Degisken verilmezse davranis
// aynen korunur.
for (const ad of Object.keys(TABANLAR)) {
  const ek = process.env['PROVA_DOKUM_' + ad.toUpperCase()];
  if (ek) TABANLAR[ad].dokum = ek;
}

const MALI       = 'docs/kurulum/2026-10-06-pms-folio-mali-yetki-ayrimi.sql';
const MALI_GERI  = 'docs/kurulum/2026-10-06-pms-folio-mali-yetki-ayrimi-geri-al.sql';
const KILIT      = 'docs/kurulum/2026-10-06-pms-rol-entegrasyon-kilit.sql';
const KILIT_GERI = 'docs/kurulum/2026-10-06-pms-rol-entegrasyon-kilit-geri-al.sql';
const TOHUM      = 'docs/kurulum/2026-10-05-pms-onburo-modul-tohumlama.sql';
const TOHUM_GERI = 'docs/kurulum/2026-10-05-pms-onburo-modul-tohumlama-geri-al.sql';
const PREFLIGHT  = 'docs/kurulum/2026-10-07-pms-onburo-yayin-oncesi-preflight.sql';

// --- Yayin kopyasi: K1 = A (kayit) satiri ELLE acilmis hali ----------------
// Dosya sessiz varsayilan tanimaz; yayin penceresinde de bu satir acilacak.
// Prova, pencerede uygulanacak METNIN AYNISINI kullanir.
export function yayinKopyasi(ham) {
  const hedef = "--   set local app.pms_k1 = 'kayit';";
  if (!ham.includes(hedef)) throw new Error('K1 satiri bulunamadi: dosya degismis');
  const acik = ham.replace(hedef, "  set local app.pms_k1 = 'kayit';");
  if (acik === ham) throw new Error('K1 satiri acilamadi');
  // Satirin sonunda aciklama yorumu vardir ve dosya CRLF'tir; yalniz satirin
  // ETKIN kismi dogrulanir. Ikinci kapi: 'yok' satiri hala KAPALI olmali.
  if (!/^\s{2}set local app\.pms_k1 = 'kayit';/m.test(acik)) throw new Error('K1 satiri beklenen bicimde degil');
  if (/^\s*set local app\.pms_k1 = 'yok';/m.test(acik)) throw new Error('K1 B secenegi de acik kalmis');
  return acik;
}

// --- Geri alma kopyasi: uygulama kimligi ELLE acilmis hali -----------------
// Geri alma da sessiz varsayilan tanimaz; kaldirilacak kurulumun kimligi
// acikca verilir. Kimlik, ileri kosumun yazdigi damgadan okunur.
export function geriAlKopyasi(ham, uygulamaId) {
  if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/.test(uygulamaId)) {
    throw new Error('uygulama kimligi UUID degil: ' + uygulamaId);
  }
  const hedef = "--   set local app.pms_uygulama_id = '00000000-0000-0000-0000-000000000000';";
  if (!ham.includes(hedef)) throw new Error('uygulama kimligi satiri bulunamadi: dosya degismis');
  const acik = ham.replace(hedef, "  set local app.pms_uygulama_id = '" + uygulamaId + "';");
  if (!acik.includes("  set local app.pms_uygulama_id = '" + uygulamaId + "';")) {
    throw new Error('uygulama kimligi satiri acilamadi');
  }
  return acik;
}

// ===========================================================================
// Alt kosum: tek taban
// ===========================================================================
async function tabanProvasi(tabanAdi) {
  const T = TABANLAR[tabanAdi];
  // YP-2: eksik taban BASARI SAYILMAZ. Her iki taban ZORUNLUDUR; dokum yoksa
  // bu kosum "atlandi" degil BASARISIZ olur ve alt surec ozel bir cikis kodu
  // (ATLAMA_CIKIS) dondurur. Aksi halde, ozellikle makineye ozel yoldaki
  // `mevcut` taban baska bir makinede hic sinanmadigi halde "GECTI" gorunurdu.
  if (!existsSync(T.dokum)) {
    console.log('  BASARISIZ ' + tabanAdi + ': ZORUNLU sema dokumu yok — ' + T.dokum);
    console.log('  Bu taban sinanmadi; prova sonucu GECTI OLAMAZ.');
    return { ok: 0, fail: 1, atlandi: true };
  }
  process.env.BAR_TEST_SEMA = T.dokum;
  const { barOrtami } = await import('./bar-test-ortam.mjs');
  const O = barOrtami({ ad: 'pms-gecis-' + tabanAdi, ag: 'pms-gecis-' + tabanAdi + '-net' });

  let ok = 0, fail = 0;
  const sonuc = (g, ad, ek) => {
    console.log('  ' + (g ? 'OK   ' : 'FAIL ') + ad + (ek ? ' — ' + ek : ''));
    if (g) ok++; else fail++;
  };
  const es = (ad, bek, olc) => sonuc(String(bek) === String(olc), ad,
    String(bek) === String(olc) ? String(olc) : 'beklenen=' + bek + ' olculen=' + olc);
  const tek = (q) => O.sql(q).out.trim();
  const say = (q) => Number(tek(q) || '0');
  const metinUygula = (yol) => O.sql(readFileSync(KOK + yol, 'utf8'));

  const U = {
    sef:      '11111111-0000-0000-0000-0000000000c1',
    vardiya:  '11111111-0000-0000-0000-0000000000c2',
    personel: '11111111-0000-0000-0000-0000000000c3',
  };
  const olarak = (kim, q) => O.kimlikle({ rol: 'authenticated', sub: U[kim] }, q);

  const TIP   = '44444444-0000-0000-0000-0000000009a1';
  const ODA   = '66666666-0000-0000-0000-0000000009a1';
  const MIS   = '77777777-0000-0000-0000-0000000009a1';
  const REZ   = '88888888-0000-0000-0000-0000000009a1';
  const FOLYO = '55555555-0000-0000-0000-0000000009a1';

  try {
    console.log('\n' + '='.repeat(74));
    console.log('TABAN: ' + tabanAdi + '  (' + T.dokum.split('/').pop() + ')');
    console.log('='.repeat(74));

    await O.kur({ uretimSonrasi: T.uretimSonrasi, onceki: T.onceki });

    // --- F0 FIKSTUR: test tohumunun modul/rol satirlari yerine GERCEK
    // referans veri. Silinen satirlar iki adim once bar-test-tohum.sql
    // tarafindan yazildi; kurulumun icerigi DEGIL. Cakisma olcuduk:
    // moduller_kod_key (stok_takip) ve roller_kod_key (depo).
    O.sql(`set session_replication_role = replica;
      update public.kullanicilar set rol_id = null;
      delete from public.yetki_matrisi;
      delete from public.moduller;
      delete from public.roller;
      set session_replication_role = origin;`);
    const refOk = O.uygulaTekIslem('docs/kurulum/02-referans-veri.sql');
    sonuc(refOk.ok, 'F0 gercek referans veri kuruldu (42 modul / 37 rol)',
      refOk.ok ? '' : refOk.err.split('\n').filter((l) => /ERROR/.test(l))[0]);
    es('F0b taban kurulurken PMS On Buro modul satiri YOK', 0,
      say(`select count(*) from public.moduller where kod like 'pms%';`));
    es('F0c uc On Buro rolu referans veriden geldi', 3,
      say(`select count(*) from public.roller where kod like 'onburo\\_%';`));
    const refYetki = say('select count(*) from public.yetki_matrisi;');
    sonuc(refYetki > 500, 'F0d referans yetki satiri sayisi kaydedildi', String(refYetki));

    // Faz 2 nesnesinin varligi tabani ayirt eder (bilgi + kapi).
    const hkVar = say(`select count(*) from information_schema.tables
      where table_schema='public' and table_name='pms_housekeeping_gorevleri';`);
    es('F0e Faz 2 kat hizmetleri tablosu (tabana gore)', T.faz2 ? 1 : 0, hkVar);

    // --- F1 Mevcut tabanda 09-13 yayininin urettigi iz TEMSIL edilir.
    // Bayt-bayt uretim verisi DEGIL; amaci, tohumlamanin ONCEDEN VAR OLAN
    // satirlari bozmadigini olcmek.
    let hkYetki = 0;
    if (T.faz2) {
      O.sql(`set session_replication_role = replica;
        insert into public.moduller (kod, ad, kategori, sira, aktif)
        values ('pms_housekeeping','On Buro — Kat Hizmetleri','onburo',46,true)
        on conflict (kod) do nothing;
        insert into public.yetki_matrisi (rol_id, modul_id, yetki)
        select r.id, m.id, v.y::public.yetki_seviye
          from (values ('kat_sef','tam'),('kat_vardiya','kayit'),('kat_personel','goruntule')) v(rk,y)
          join public.roller r on r.kod = v.rk
          join public.moduller m on m.kod = 'pms_housekeeping'
        on conflict do nothing;
        set session_replication_role = origin;`);
      hkYetki = say(`select count(*) from public.yetki_matrisi y
        join public.moduller m on m.id = y.modul_id where m.kod = 'pms_housekeeping';`);
      sonuc(hkYetki === 3, 'F1 09-13 kat hizmetleri izi temsil edildi (3 satir)', String(hkYetki));
    }

    // --- F2 Uc On Buro kullanicisi GERCEK rol kimliklerine baglanir.
    O.sql(`set session_replication_role = replica;
      insert into auth.users (id, email) values
        ('${U.sef}','gecis-sef@test.local'),
        ('${U.vardiya}','gecis-vardiya@test.local'),
        ('${U.personel}','gecis-personel@test.local')
      on conflict (id) do nothing;
      insert into public.kullanicilar (id, auth_user_id, ad, rol, otel_id, aktif, rol_id)
      select gen_random_uuid(), v.au, v.ad, 'muhasebe_calisani', '810', true, r.id
        from (values ('${U.sef}'::uuid,'Gecis Sef','onburo_sef'),
                     ('${U.vardiya}'::uuid,'Gecis Vardiya','onburo_vardiya'),
                     ('${U.personel}'::uuid,'Gecis Personel','onburo_personel')) v(au,ad,rk)
        join public.roller r on r.kod = v.rk;
      set session_replication_role = origin;`);
    es('F2 uc kullanici gercek On Buro rollerine baglandi', 3,
      say(`select count(*) from public.kullanicilar k join public.roller r on r.id = k.rol_id
           where r.kod like 'onburo\\_%' and k.auth_user_id in
             ('${U.sef}','${U.vardiya}','${U.personel}');`));

    // --- F3 PMS veri fiksturu: oda tipi / oda / misafir / rezervasyon / folyo
    const f3 = O.sql(`set session_replication_role = replica;
      insert into public.pms_oda_tipleri (id, otel_id, kod, ad, azami_kisi, azami_yetiskin, azami_cocuk, aktif)
        values ('${TIP}','810','GECIS','Gecis Provasi',2,2,0,true) on conflict (id) do nothing;
      insert into public.pms_odalar (id, otel_id, oda_tipi_id, oda_no, kullanim_durumu, temizlik_durumu)
        values ('${ODA}','810','${TIP}','G01','bos','temiz') on conflict (id) do nothing;
      insert into public.pms_misafirler (id, otel_id, ad, soyad)
        values ('${MIS}','810','Gecis','Provasi') on conflict (id) do nothing;
      insert into public.pms_rezervasyonlar
        (id, otel_id, rezervasyon_no, misafir_id, oda_tipi_id, giris_tarihi, cikis_tarihi, durum)
        values ('${REZ}','810','G-9A1','${MIS}','${TIP}', current_date, current_date + 2, 'onaylandi')
        on conflict (id) do nothing;
      insert into public.pms_folyolar (id, otel_id, rezervasyon_id, folio_no, durum)
        values ('${FOLYO}','810','${REZ}','FG-9A1','acik') on conflict (id) do nothing;
      insert into public.pms_folio_hareketleri
        (otel_id, folio_id, tip, aciklama, tutar, konaklama_gecesi)
        values ('810','${FOLYO}','oda_ucreti','Gecis provasi oda ucreti',1000.00, current_date);
      set session_replication_role = origin;`);
    sonuc(f3.ok && say(`select count(*) from public.pms_folyolar where id='${FOLYO}';`) === 1,
      'F3 PMS veri fiksturu kuruldu (acik folyo + 1000,00 borc)',
      f3.ok ? '' : f3.err.split('\n').filter((l) => /ERROR/.test(l))[0]);

    // --- MALI VERI DEGISMEZLIK TABANI -------------------------------------
    // Canli olcumde 3 odeme + 6 hareket var ve KORUNMASI sart. Burada, uc
    // migration ve UC GERI ALMA boyunca hicbir mali satirin SILINMEDIGI
    // olculur: baslangictaki kimliklerin tamami sonda da bulunmali.
    O.sql(`create table if not exists pms_mali_taban (tablo text, id uuid);
      delete from pms_mali_taban;
      insert into pms_mali_taban
        select 'hareket', id from public.pms_folio_hareketleri
        union all
        select 'odeme', id from public.pms_folio_odemeler;`);
    const maliTabanOnce = say('select count(*) from pms_mali_taban;');
    const maliKayip = () => say(`select count(*) from pms_mali_taban t
      where (t.tablo='hareket' and not exists
               (select 1 from public.pms_folio_hareketleri h where h.id=t.id))
         or (t.tablo='odeme' and not exists
               (select 1 from public.pms_folio_odemeler o where o.id=t.id));`);
    sonuc(maliTabanOnce >= 1, 'F4 mali veri degismezlik tabani alindi (kimlik listesi)',
      maliTabanOnce + ' satir');

    // =====================================================================
    // P1–P4 — YAYIN ONCESI SALT-OKUMA PREFLIGHT
    // =====================================================================
    const pfHam = readFileSync(KOK + PREFLIGHT, 'utf8');
    // Yorumlar ve \echo cikarilir; kalan metinde yazma anahtar sozcugu olmamali.
    const pfEtkin = pfHam.split('\n').filter((l) => !/^\s*--/.test(l)).join('\n');
    const yazmaIzi = (pfEtkin.match(/\b(insert|update|delete|truncate|alter|drop|create|grant|revoke|set\s+local|set\s+session)\b/gi) || []);
    sonuc(yazmaIzi.length === 0, 'P1 preflight YALNIZ okuma (yazma anahtar sozcugu yok)',
      yazmaIzi.length ? 'BULUNDU: ' + yazmaIzi.join(',') : 'temiz');
    // Kanal tasinabilirligi: psql'e ozgu meta komut (\echo, \set, \d ...) olmamali,
    // yoksa Supabase SQL Editor'a yapistirilamaz ve ayri bir surum gerekir.
    const metaKomut = pfHam.split('\n')
      .filter((l) => /^\s*\\/.test(l)).map((l) => l.trim().split(/\s/)[0]);
    sonuc(metaKomut.length === 0,
      'P1b preflight psql meta komutu ICERMIYOR (SQL Editor ile de calisir)',
      metaKomut.length ? 'BULUNDU: ' + [...new Set(metaKomut)].join(',') : 'temiz');

    // Govde ozetleri: kilit UYGULANMADAN once olculur. Yayin penceresinde
    // uretimdeki degerler bunlarla karsilastirilir; farkliysa kilit, baskasinin
    // degisikligini SESSIZCE geri alirdi (preflight 6. bolum).
    const md5Once = tek(`select string_agg(proname || '=' || md5(prosrc), ' ' order by proname)
      from pg_proc where pronamespace='public'::regnamespace
        and proname in ('pms_rezervasyon_kontrol','pms_check_in','pms_check_out');`);
    sonuc(/pms_check_in=[0-9a-f]{32}/.test(md5Once),
      'P2 Faz 1 govde ozetleri olculdu (yayin oncesi BEKLENEN degerler)');
    console.log('       ' + md5Once.replace(/ /g, '\n       '));

    // ACL ozeti: anon / authenticated / service_role icin EFEKTIF execute.
    // Faz 1 sozlesmesi: anon KAPALI, authenticated ve service_role ACIK.
    // YP-3: kilit geri almasi yalniz "invoker oldu" demekle yetinmez; ACL'nin
    // de Faz 1 beklentisine dondugu olculur.
    const aclOzeti = () => tek(`select string_agg(ad || '=' || izin, ' ' order by ad) from (
      select 'check_in' as ad,
        (case when has_function_privilege('anon','public.pms_check_in(uuid,uuid)','execute') then 'a' else '-' end) ||
        (case when has_function_privilege('authenticated','public.pms_check_in(uuid,uuid)','execute') then 'A' else '-' end) ||
        (case when has_function_privilege('service_role','public.pms_check_in(uuid,uuid)','execute') then 'S' else '-' end) as izin
      union all
      select 'check_out',
        (case when has_function_privilege('anon','public.pms_check_out(uuid)','execute') then 'a' else '-' end) ||
        (case when has_function_privilege('authenticated','public.pms_check_out(uuid)','execute') then 'A' else '-' end) ||
        (case when has_function_privilege('service_role','public.pms_check_out(uuid)','execute') then 'S' else '-' end)
    ) s;`);
    const aclOnce = aclOzeti();
    es('P2b Faz 1 ACL beklentisi (anon kapali, authenticated+service_role acik)',
      'check_in=-AS check_out=-AS', aclOnce);

    const pf1 = O.sql(pfHam);
    sonuc(pf1.ok, 'P3 preflight kilit ONCESI tabanda hatasiz kostu',
      pf1.ok ? '' : pf1.err.split('\n').filter((l) => /ERROR/.test(l))[0]);
    sonuc(/kilit UYGULANMAMIS/.test(pf1.out), 'P3b preflight "kilit UYGULANMAMIS" dedi');
    // §3 ozet satiri: uyumlu_mevcut|eksik|celisen|karar
    sonuc(/(^|\n)0\|15\|0\|UYGUN(\r?\n|$)/.test(pf1.out),
      'P3c preflight siniflandirmasi: uyumlu 0 / eksik 15 / celisen 0',
      (pf1.out.match(/(^|\n)(\d+\|\d+\|\d+\|[A-Z].*)/) || ['', '', 'bulunamadi'])[2]);
    // §6: preflight'taki SABIT beklenen ozetler gercek govdelerle TUTUYOR mu.
    es('P3d preflight govde kapisi uc fonksiyonda da UYGUN dedi', 3,
      (pf1.out.match(/UYGUN \(Faz 1 govdesi\)/g) || []).length);
    // --- P3e/P3f: ACL kapisi GERCEK bir bosluk buldu ----------------------
    // OLCULDU: 2026-09-07 post-Faz1 dokumunde `pms_bar_folio_koprusu` icin
    // `REVOKE ALL ... FROM PUBLIC` YOKTUR; anon EXECUTE'u PUBLIC uzerinden
    // devralir. 2026-09-13 dokumunde revoke VARDIR. Yani 2026-09-08 ACL
    // temizligi, temiz kurulumun taban dokumune GIRMEMISTIR.
    // Sonuc: KURULUM-REHBERI'nin tarif ettigi temiz kurulum (post-Faz1 dokumu
    // + referans veri), `2026-09-08-pms-fonksiyon-acl-temizligi.sql`
    // uygulanmadikca anon EXECUTE'u ACIK birakir. Bu, bu paketin urettigi bir
    // gerileme DEGIL, kurulum sirasinda ONCEDEN var olan bir bosluktur ve
    // yeni ACL olcumu sayesinde goruldu.
    const anonAcik = /SAPMA: anon EXECUTE acik/.test(pf1.out);
    es('P3e ACL kapisi tabanin gercek durumunu raporladi (temiz tabanda anon ACIK)',
      T.faz2 ? false : true, anonAcik);
    // Care kaniti: 09-08 ACL temizligi uygulanirsa bosluk kapaniyor mu?
    const aclTemizlik = metinUygula('docs/kurulum/2026-09-08-pms-fonksiyon-acl-temizligi.sql');
    const pf1b = O.sql(pfHam);
    sonuc(aclTemizlik.ok && pf1b.ok && !/SAPMA: anon EXECUTE acik/.test(pf1b.out),
      'P3f 2026-09-08 ACL temizligi uygulaninca anon EXECUTE boslugu KAPANDI',
      aclTemizlik.ok ? (pf1b.out.match(/pms_bar_folio_koprusu[^\n]*/) || [''])[0].slice(-40)
                     : 'ACL temizligi uygulanamadi');
    sonuc(!/SAPMA/.test(pf1b.out), 'P3g ACL temizligi sonrasi preflight hic SAPMA raporlamiyor',
      /SAPMA/.test(pf1b.out) ? pf1b.out.split('\n').filter((l) => /SAPMA/.test(l))[0].slice(0, 80) : 'sapma yok');

    // =====================================================================
    // S1 — SIRA KAPISI: tohumlama ONCE calistirilirsa DURMALI
    // =====================================================================
    const tohumMetni = yayinKopyasi(readFileSync(KOK + TOHUM, 'utf8'));
    const yetkiOnce = say('select count(*) from public.yetki_matrisi;');
    const ilkTohum = O.sql(tohumMetni);
    sonuc(!ilkTohum.ok && /MALI_AYRIM_KURALI_YOK/.test(ilkTohum.err),
      'S1 mali kural YOKKEN tohumlama DURDU (beklenen ret sinifi)',
      ilkTohum.ok ? 'KABUL (kusur)' :
        (ilkTohum.err.match(/MALI_AYRIM_KURALI_YOK/) ||
          ['BEKLENMEYEN: ' + ilkTohum.err.replace(/\s+/g, ' ').slice(-90)])[0]);
    es('S1b ret aninda HICBIR yetki satiri yazilmadi', yetkiOnce,
      say('select count(*) from public.yetki_matrisi;'));
    es('S1c PMS modul satiri da yazilmadi', 0,
      say(`select count(*) from public.moduller where kod like 'pms\\_oda%' or kod='pms_misafir'
           or kod='pms_rezervasyon' or kod='pms_folio';`));

    // =====================================================================
    // S2 — ADIM 1: mali islem yetki ayrimi
    // =====================================================================
    const r2 = metinUygula(MALI);
    sonuc(r2.ok, 'S2 Adim 1 mali yetki ayrimi uygulandi (kendi dogrulama blogu gecti)',
      r2.ok ? '' : r2.err.split('\n').filter((l) => /ERROR/.test(l))[0]);
    es('S2b hassas kapi tetikleyicisi iki mali tabloda da var', 2,
      say(`select count(*) from pg_trigger t join pg_class c on c.oid = t.tgrelid
           where t.tgname='pms_folio_hassas_kapi' and not t.tgisinternal
             and c.relname in ('pms_folio_hareketleri','pms_folio_odemeler');`));
    es('S2c gerekce kurali tek kaynakta tanimli', 1,
      say(`select count(*) from pg_proc where pronamespace='public'::regnamespace
             and proname='pms_folio_hassas_mi';`));

    // =====================================================================
    // S3 — ADIM 2: rol entegrasyon kilidi (MY-4)
    // =====================================================================
    const r3 = metinUygula(KILIT);
    sonuc(r3.ok, 'S3 Adim 2 rol entegrasyon kilidi uygulandi (kendi dogrulama blogu gecti)',
      r3.ok ? '' : r3.err.split('\n').filter((l) => /ERROR/.test(l))[0]);
    es('S3b dort fonksiyon SECURITY DEFINER', 4,
      say(`select count(*) from pg_proc where pronamespace='public'::regnamespace and prosecdef
             and proname in ('pms_rezervasyon_kontrol','pms_check_in','pms_check_out','pms_oda_tipi_kilitle');`));
    es('S3c oda durumunu tek basina yazan dis yardimci YOK (MY4-T3)', 0,
      say(`select count(*) from pg_proc where pronamespace='public'::regnamespace
             and proname='pms_oda_konaklama_isaretle';`));
    // Kilit govdeleri GERCEKTEN degistiriyor; bu yuzden preflight'in 6. bolumu
    // (uretim govdeleri 09-06 govdeleri mi) anlamli bir kapidir.
    const md5Sonra = tek(`select string_agg(proname || '=' || md5(prosrc), ' ' order by proname)
      from pg_proc where pronamespace='public'::regnamespace
        and proname in ('pms_rezervasyon_kontrol','pms_check_in','pms_check_out');`);
    sonuc(md5Sonra !== md5Once && /pms_check_in=[0-9a-f]{32}/.test(md5Sonra),
      'S3d kilit govdeleri gercekten degistirdi (preflight 6. bolum anlamli)');
    const pf2 = O.sql(readFileSync(KOK + PREFLIGHT, 'utf8'));
    sonuc(pf2.ok && /kilit UYGULANMIS/.test(pf2.out),
      'S3e preflight kilit SONRASI "kilit UYGULANMIS" dedi',
      pf2.ok ? '' : 'preflight hata');

    // =====================================================================
    // S4 — ADIM 3: On Buro modul ve yetki tohumlamasi (K1 = A)
    // =====================================================================
    // --- Onayli 15 HEDEF cift. YP-1: sozlesme "15 YENI satir" DEGIL,
    // "son durumda 15 hedef cift dogru seviyede" + "eklenen damgali satir
    // sayisi = onceden EKSIK olan sayi"dir. Onceden uyumlu satir varsa daha az
    // eklenmesi DOGRU davranistir.
    const HEDEF = [
      ['onburo_sef', 'pms_oda_tipi', 'tam'], ['onburo_sef', 'pms_oda', 'tam'],
      ['onburo_sef', 'pms_misafir', 'tam'], ['onburo_sef', 'pms_rezervasyon', 'tam'],
      ['onburo_sef', 'pms_folio', 'tam'],
      ['onburo_vardiya', 'pms_oda_tipi', 'goruntule'], ['onburo_vardiya', 'pms_oda', 'kayit'],
      ['onburo_vardiya', 'pms_misafir', 'kayit'], ['onburo_vardiya', 'pms_rezervasyon', 'kayit'],
      ['onburo_vardiya', 'pms_folio', 'kayit'],
      ['onburo_personel', 'pms_oda_tipi', 'goruntule'], ['onburo_personel', 'pms_oda', 'goruntule'],
      ['onburo_personel', 'pms_misafir', 'kayit'], ['onburo_personel', 'pms_rezervasyon', 'kayit'],
      ['onburo_personel', 'pms_folio', 'kayit'],   // K1 = A
    ];
    const hedefSql = HEDEF.map(([r, m, y]) => `('${r}','${m}','${y}')`).join(',');
    // Son durumda dogru seviyede bulunan hedef cift sayisi.
    const hedefTutan = () => say(`select count(*) from (values ${hedefSql}) v(rk,mk,y)
      join public.roller r on r.kod = v.rk
      join public.moduller m on m.kod = v.mk
      join public.yetki_matrisi ym on ym.rol_id = r.id and ym.modul_id = m.id
      where ym.yetki::text = v.y;`);
    const damgali = () => say(`select count(*) from public.yetki_matrisi
      where guncelleyen like 'tohum:pms-onburo:%';`);
    // Dosyanin kendi raporladigi eklenen satir sayisi (NOTICE).
    const eklenenBildirim = (r) => {
      const m = String(r.err || '').match(/eklenen_yetki_satiri=(\d+)\/15/);
      return m ? Number(m[1]) : null;
    };

    const eksikOnce = 15 - hedefTutan();
    es('S4-hazirlik bu tabanda onceden EKSIK olan hedef cift sayisi', 15, eksikOnce);
    // Menu ve kapsam disi yetkiler ONCE/SONRA delta olarak olculur (YP-1).
    const kvkkOnce = say(`select count(*) from public.yetki_matrisi y
      join public.moduller m on m.id = y.modul_id where m.kod='pms_misafir_kimlik';`);
    // Menuyu goren rol kumesi: en az bir AKTIF On Buro modulunde yetkisi olan
    // her rol. "Yalniz uc rol" bir koruma sozlesmesi DEGILDIR; olcut, mevcut
    // yetkili rollerin KAPATILMAMASI ve yeni gorenlerin yalniz hedef roller
    // olmasidir.
    const menuRolleri = () => tek(`select coalesce(string_agg(distinct r.kod, ',' order by r.kod),'')
      from public.yetki_matrisi y
      join public.roller r on r.id = y.rol_id
      join public.moduller m on m.id = y.modul_id
      where m.aktif is true and m.kod in
        ('pms_oda_tipi','pms_oda','pms_misafir','pms_rezervasyon','pms_folio');`);
    const menuOnce = menuRolleri();

    const r4 = O.sql(tohumMetni);
    sonuc(r4.ok, 'S4 Adim 3 tohumlama uygulandi (K1 = A / kayit)',
      r4.ok ? '' : r4.err.split('\n').filter((l) => /ERROR/.test(l))[0]);
    es('S4b SON DURUM: 15 hedef cift dogru seviyede', 15, hedefTutan());
    es('S4b2 eklenen damgali satir = onceden EKSIK olan sayi', eksikOnce, damgali());
    es('S4b3 dosyanin kendi bildirdigi eklenen sayi da ayni', eksikOnce, eklenenBildirim(r4));
    es('S4c bes On Buro modulu var ve AKTIF', 5,
      say(`select count(*) from public.moduller where aktif is true and kod in
             ('pms_oda_tipi','pms_oda','pms_misafir','pms_rezervasyon','pms_folio');`));
    es('S4d damga bicimi dogru (tohum:pms-onburo:<uuid>@<iso>#<yetki>)', eksikOnce,
      say(`select count(*) from public.yetki_matrisi where guncelleyen ~
           '^tohum:pms-onburo:[0-9a-f-]{36}@[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:.]+[+-][0-9]{2}';`));
    es('S4e personel folyo seviyesi K1=A geregi kayit', 'kayit',
      tek(`select y.yetki::text from public.yetki_matrisi y
           join public.roller r on r.id=y.rol_id join public.moduller m on m.id=y.modul_id
           where r.kod='onburo_personel' and m.kod='pms_folio';`));
    // YP-1: KVKK icin IKI AYRI olcut. (a) bu paket YENI kimlik yetkisi eklemez,
    // (b) ONCEDEN var olan kimlik yetkileri silinmez/degistirilmez. Tabanda
    // mevcut satir yoksa (a) ve (b) ayni sayiyi verir; sozlesme yine ayridir.
    es('S4f1 bu paket YENI pms_misafir_kimlik yetkisi EKLEMEDI', 0,
      say(`select count(*) from public.yetki_matrisi y join public.moduller m on m.id=y.modul_id
           where m.kod='pms_misafir_kimlik' and y.guncelleyen like 'tohum:pms-onburo:%';`));
    es('S4f2 ONCEDEN var olan pms_misafir_kimlik yetkileri DEGISMEDI', kvkkOnce,
      say(`select count(*) from public.yetki_matrisi y join public.moduller m on m.id=y.modul_id
           where m.kod='pms_misafir_kimlik';`));
    // Damgasiz (yani ONCEDEN VAR OLAN) satirlarin sayisi degismemeli.
    // Mevcut tabanda bunlar referans veri + 09-13 kat hizmetleri izidir.
    es('S4g onceden var olan yetki satirlari DEGISMEDI', refYetki + (T.faz2 ? hkYetki : 0),
      say(`select count(*) from public.yetki_matrisi where guncelleyen is null
             or guncelleyen not like 'tohum:pms-onburo:%';`));
    if (T.faz2) {
      es('S4h 09-13 kat hizmetleri izi DOKUNULMADI', hkYetki,
        say(`select count(*) from public.yetki_matrisi y join public.moduller m on m.id=y.modul_id
             where m.kod='pms_housekeeping';`));
    }
    // Menu delta: ONCE goren roller korunmus olmali, YENI gorenler yalniz
    // uc hedef rol olmali.
    const menuSonra = menuRolleri();
    const oncekiKume = menuOnce ? menuOnce.split(',') : [];
    const sonrakiKume = menuSonra ? menuSonra.split(',') : [];
    const kaybeden = oncekiKume.filter((x) => !sonrakiKume.includes(x));
    const yeniGoren = sonrakiKume.filter((x) => !oncekiKume.includes(x));
    sonuc(kaybeden.length === 0, 'S4i ONCE menuyu goren hicbir rol KAPATILMADI',
      kaybeden.length ? 'KAYBEDEN: ' + kaybeden.join(',') : 'once=[' + menuOnce + ']');
    sonuc(yeniGoren.length === 3 && yeniGoren.every((x) => x.startsWith('onburo_')),
      'S4j YENI menu goren roller YALNIZ uc On Buro rolu', yeniGoren.join(','));

    // =====================================================================
    // S5–S8 — ONAYLI KAPSAM DAVRANISI (gercek rol baglaminda)
    // =====================================================================
    const tahsilat = (kim, tutar, aciklama) => olarak(kim,
      `insert into public.pms_folio_odemeler (otel_id, folio_id, yontem, tutar, aciklama)
       values ('810','${FOLYO}','nakit',${tutar},${aciklama === null ? 'null' : `'${aciklama}'`});`);

    const s5 = tahsilat('personel', '250.00', null);
    sonuc(s5.ok, 'S5 OLUMLU: personel NORMAL tahsilati gerekcesiz yapabildi (kayit yeter)',
      s5.ok ? '+250,00' : 'RET: ' + s5.err.replace(/\s+/g, ' ').slice(-90));

    const s6 = tahsilat('personel', '-100.00', 'iade denemesi');
    sonuc(!s6.ok && /MALI_TAM_YETKI_GEREKLI/.test(s6.err),
      'S6 OLUMSUZ: personelin IADESI reddedildi (tam yetki gerekir)',
      s6.ok ? 'KABUL (kusur)' : (s6.err.match(/MALI_TAM_YETKI_GEREKLI/) ||
        ['BEKLENMEYEN: ' + s6.err.replace(/\s+/g, ' ').slice(-90)])[0]);

    const s6b = olarak('personel', `insert into public.pms_folio_hareketleri
      (otel_id, folio_id, tip, aciklama, tutar)
      values ('810','${FOLYO}','duzeltme','duzeltme denemesi',50.00);`);
    sonuc(!s6b.ok && /MALI_TAM_YETKI_GEREKLI/.test(s6b.err),
      'S6b OLUMSUZ: personelin DUZELTME satiri reddedildi',
      s6b.ok ? 'KABUL (kusur)' : (s6b.err.match(/MALI_TAM_YETKI_GEREKLI/) ||
        ['BEKLENMEYEN: ' + s6b.err.replace(/\s+/g, ' ').slice(-90)])[0]);

    const s7 = tahsilat('sef', '-100.00', null);
    sonuc(!s7.ok && /gerekce|aciklama/i.test(s7.err),
      'S7 OLUMSUZ: tam yetkili sef bile GEREKCESIZ iade yapamadi',
      s7.ok ? 'KABUL (kusur)' : (s7.err.replace(/\s+/g, ' ').match(/aciklama[^.]{0,48}/) ||
        ['BEKLENMEYEN: ' + s7.err.replace(/\s+/g, ' ').slice(-90)])[0]);

    const s7b = tahsilat('sef', '-100.00', 'Misafir sikayeti uzerine iade');
    sonuc(s7b.ok, 'S7b OLUMLU: tam yetkili sef GEREKCELI iadeyi yapabildi',
      s7b.ok ? '-100,00 + gerekce' : 'RET: ' + s7b.err.replace(/\s+/g, ' ').slice(-90));

    // SO-2t: `!update || !delete` kosulu TEK tarafin reddiyle de gecerdi.
    // Artik IKI deneme de reddedilmeli VE satirin kimlik+icerigi korunmali;
    // karar mantigi karsi orneklerle sinaniyor (yayin-kabul-kurallari.test).
    const hId = tek(`select id::text from public.pms_folio_hareketleri
      where folio_id='${FOLYO}' order by olusturma_tarihi limit 1;`);
    const satirOzeti = (id) => tek(`select coalesce(id::text || '|' || tutar::text || '|'
      || tip::text || '|' || aciklama, '') from public.pms_folio_hareketleri where id='${id}';`);
    const s8Once = satirOzeti(hId);
    const s8u = olarak('sef', `update public.pms_folio_hareketleri set tutar=1 where id='${hId}';`);
    const s8d = olarak('sef', `delete from public.pms_folio_hareketleri where id='${hId}';`);
    const s8karar = degismezlikKarari({
      updateOk: s8u.ok, deleteOk: s8d.ok,
      oncekiIcerik: s8Once, sonrakiIcerik: satirOzeti(hId),
    });
    sonuc(s8karar.gecti, 'S8 sef dahil kimse MEVCUT mali satiri degistiremedi/silemedi',
      s8karar.ozet + (s8karar.neden ? ' — ' + s8karar.neden : ''));
    sonuc(/MALI_DEGISMEZ|degistirilemez|permission denied|RLS|policy/i.test(
      String(s8u.err) + String(s8d.err)),
      'S8a ret nedeni mali degismezlik/yetki sinifinda',
      (String(s8u.err || s8d.err).replace(/\s+/g, ' ').match(
        /(MALI_DEGISMEZ[A-Z_]*|permission denied[^.]{0,30}|[A-Z][A-Z_]{6,})/) || ['?'])[0].slice(0, 46));
    es('S8b satir hala yerinde ve degeri 1000,00', '1000.00',
      tek(`select tutar::text from public.pms_folio_hareketleri where id='${hId}';`));
    // Geri alma fazinda veri kaybi olmadigini olcmek icin taban sayim.
    const folyoSatirOnce =
      say(`select count(*) from public.pms_folio_hareketleri where folio_id='${FOLYO}';`)
      + say(`select count(*) from public.pms_folio_odemeler where folio_id='${FOLYO}';`);

    // =====================================================================
    // S16 — CANLI DUMAN TESTININ TAM SIRASI (SO-2)
    // Onay belgesi §7.3'teki sira, SENTETIK veriyle ve URUNUN KENDI
    // yollariyla burada kosulur. Olculen sozlesme:
    //   bakiye = borc (pms_folio_hareketleri) - odeme (pms_folio_odemeler)
    //   IADE = NEGATIF TAHSILAT -> pms_folio_odemeler (hareketler DEGIL)
    //   DUZELTME -> pms_folio_hareketleri
    //   Butun mali islemler KAPANISTAN ONCE; kapali folyo yazma kabul etmez.
    // Tutar X = 1,00 (sembolik). Son bakiye 0 ve folyo kapali olmali.
    // =====================================================================
    const X = '1.00';
    const MIS2 = '77777777-0000-0000-0000-0000000009b1';
    const REZ2 = '88888888-0000-0000-0000-0000000009b1';
    const ODA2 = '66666666-0000-0000-0000-0000000009b1';
    const U_IT = '11111111-0000-0000-0000-0000000000c4';
    // it_admin kimligi: §7.3'te gerekceli iadeyi yapan rol.
    O.sql(`set session_replication_role = replica;
      insert into auth.users (id, email) values ('${U_IT}','gecis-itadmin@test.local')
        on conflict (id) do nothing;
      insert into public.kullanicilar (id, auth_user_id, ad, rol, otel_id, aktif, rol_id)
      select gen_random_uuid(), '${U_IT}', 'Gecis IT', 'muhasebe_calisani', '810', true, r.id
        from public.roller r where r.kod = 'it_admin'
      on conflict do nothing;
      insert into public.yetki_matrisi (rol_id, modul_id, yetki)
      select r.id, m.id, 'tam'::public.yetki_seviye
        from public.roller r cross join public.moduller m
       where r.kod = 'it_admin'
         and m.kod in ('pms_oda_tipi','pms_oda','pms_misafir','pms_rezervasyon','pms_folio')
      on conflict (rol_id, modul_id) do nothing;
      insert into public.pms_odalar (id, otel_id, oda_tipi_id, oda_no, kullanim_durumu, temizlik_durumu)
        values ('${ODA2}','810','${TIP}','G02','bos','temiz') on conflict (id) do nothing;
      insert into public.pms_misafirler (id, otel_id, ad, soyad)
        values ('${MIS2}','810','Duman','Testi') on conflict (id) do nothing;
      set session_replication_role = origin;`);
    const U2 = { ...U, itadmin: U_IT };
    const olarak2 = (kim, q) => O.kimlikle({ rol: 'authenticated', sub: U2[kim] }, q);

    // Taban sayimlar: YENI satirlar ESKI satirlardan AYRI olculur (SO-2).
    const harSay = () => say('select count(*) from public.pms_folio_hareketleri;');
    const odeSay = () => say('select count(*) from public.pms_folio_odemeler;');
    const harOnce = harSay(), odeOnce = odeSay();
    const FOLYO2 = () => tek(`select id::text from public.pms_folyolar where rezervasyon_id='${REZ2}';`);
    const bakiye = () => tek(`select (coalesce((select sum(tutar) from public.pms_folio_hareketleri
        where folio_id=(select id from public.pms_folyolar where rezervasyon_id='${REZ2}')),0)
      - coalesce((select sum(tutar) from public.pms_folio_odemeler
        where folio_id=(select id from public.pms_folyolar where rezervasyon_id='${REZ2}')),0))::text;`);

    // --- D-adimlari: rezervasyon -> folyo (otomatik) ---------------------
    const d1 = olarak2('personel', `insert into public.pms_rezervasyonlar
      (id, otel_id, rezervasyon_no, misafir_id, oda_tipi_id, giris_tarihi, cikis_tarihi,
       durum, yetiskin_sayisi, cocuk_sayisi, gecelik_fiyat)
      values ('${REZ2}','810','DUMAN-1','${MIS2}','${TIP}', current_date, current_date + 1,
              'onaylandi', 1, 0, ${X});`);
    sonuc(d1.ok, 'S16-1 personel: rezervasyon kaydi (onaylandi) KABUL',
      d1.ok ? '' : d1.err.replace(/\s+/g, ' ').slice(-90));
    es('S16-2 folyo OTOMATIK acildi', 1,
      say(`select count(*) from public.pms_folyolar where rezervasyon_id='${REZ2}' and durum='acik';`));
    es('S16-3 baslangic bakiyesi 0', '0.00', bakiye() === '0' ? '0.00' : bakiye());

    const d2 = olarak2('personel', `select public.pms_check_in('${REZ2}','${ODA2}');`);
    sonuc(d2.ok, 'S16-4 personel: CHECK-IN KABUL (MY-4 kilidinin kaniti)',
      d2.ok ? '' : d2.err.replace(/\s+/g, ' ').slice(-90));

    const d3 = olarak2('personel', `select public.pms_folio_oda_ucreti_isle('${REZ2}');`);
    sonuc(d3.ok, 'S16-5 personel: ODA UCRETI islendi -> hareketler +1',
      d3.ok ? '' : d3.err.replace(/\s+/g, ' ').slice(-90));
    es('S16-6 hareket deltasi 1', 1, harSay() - harOnce);
    es('S16-7 ara bakiye = +1,00 (borc)', '1.00', bakiye());

    // --- Olumsuzlar: hicbir satir uretmemeli ----------------------------
    const d4 = olarak2('personel', `insert into public.pms_folio_odemeler
      (otel_id, folio_id, yontem, tutar, aciklama)
      values ('810','${FOLYO2()}','nakit',-${X},'iade denemesi');`);
    sonuc(!d4.ok && /MALI_TAM_YETKI_GEREKLI/.test(d4.err),
      'S16-8 personel: IADE (negatif TAHSILAT) REDDEDILDI',
      d4.ok ? 'KABUL (kusur)' : 'MALI_TAM_YETKI_GEREKLI');
    const d5 = olarak2('personel', `insert into public.pms_folio_hareketleri
      (otel_id, folio_id, tip, aciklama, tutar)
      values ('810','${FOLYO2()}','duzeltme','duzeltme denemesi',${X});`);
    sonuc(!d5.ok && /MALI_TAM_YETKI_GEREKLI/.test(d5.err),
      'S16-9 personel: DUZELTME hareketi REDDEDILDI',
      d5.ok ? 'KABUL (kusur)' : 'MALI_TAM_YETKI_GEREKLI');
    es('S16-10 iki ret HIC satir uretmedi', 0,
      (harSay() - harOnce - 1) + (odeSay() - odeOnce));

    // --- Normal tahsilat: gerekcesiz, KABUL -----------------------------
    const d6 = olarak2('personel', `insert into public.pms_folio_odemeler
      (otel_id, folio_id, yontem, tutar) values ('810','${FOLYO2()}','nakit',${X});`);
    sonuc(d6.ok, 'S16-11 personel: NORMAL tahsilat (+1,00, gerekcesiz) KABUL -> odemeler +1',
      d6.ok ? '' : d6.err.replace(/\s+/g, ' ').slice(-90));
    es('S16-12 ara bakiye 0,00', '0.00', bakiye());

    // --- it_admin: gerekcesiz iade RET, gerekceli iade KABUL ------------
    const d7 = olarak2('itadmin', `insert into public.pms_folio_odemeler
      (otel_id, folio_id, yontem, tutar) values ('810','${FOLYO2()}','nakit',-${X});`);
    sonuc(!d7.ok && /aciklama|gerekce/i.test(d7.err),
      'S16-13 it_admin: GEREKCESIZ iade REDDEDILDI',
      d7.ok ? 'KABUL (kusur)' : 'aciklama zorunlu');
    const d8 = olarak2('itadmin', `insert into public.pms_folio_odemeler
      (otel_id, folio_id, yontem, tutar, aciklama)
      values ('810','${FOLYO2()}','nakit',-${X},'Duman testi: gerekceli iade');`);
    sonuc(d8.ok, 'S16-14 it_admin: GEREKCELI iade KABUL -> odemeler +1 (NEGATIF)',
      d8.ok ? '' : d8.err.replace(/\s+/g, ' ').slice(-90));
    es('S16-15 ara bakiye yeniden +1,00 (iade borcu geri actti)', '1.00', bakiye());

    // --- Kapanistan ONCE dengeleme --------------------------------------
    const d9 = olarak2('personel', `insert into public.pms_folio_odemeler
      (otel_id, folio_id, yontem, tutar) values ('810','${FOLYO2()}','nakit',${X});`);
    sonuc(d9.ok, 'S16-16 personel: dengeleme tahsilati KABUL -> odemeler +1',
      d9.ok ? '' : d9.err.replace(/\s+/g, ' ').slice(-90));
    es('S16-17 bakiye 0,00 — kapanisa hazir', '0.00', bakiye());

    // --- Degismezlik: mevcut satir update/delete edilemez ---------------
    const hId2 = tek(`select id::text from public.pms_folio_hareketleri
      where folio_id='${FOLYO2()}' limit 1;`);
    const d10Once = satirOzeti(hId2);
    const d10u = olarak2('itadmin', `update public.pms_folio_hareketleri set tutar=9 where id='${hId2}';`);
    const d10d = olarak2('itadmin', `delete from public.pms_folio_hareketleri where id='${hId2}';`);
    // SO-2t: IKI deneme de reddedilmeli VE satir kimlik+icerik olarak korunmali.
    const d10karar = degismezlikKarari({
      updateOk: d10u.ok, deleteOk: d10d.ok,
      oncekiIcerik: d10Once, sonrakiIcerik: satirOzeti(hId2),
    });
    sonuc(d10karar.gecti, 'S16-18 it_admin MEVCUT mali satiri degistiremedi/silemedi',
      d10karar.ozet + (d10karar.neden ? ' — ' + d10karar.neden : ''));
    sonuc(/MALI_DEGISMEZ|degistirilemez|permission denied|RLS|policy/i.test(
      String(d10u.err) + String(d10d.err)),
      'S16-18a ret nedeni mali degismezlik/yetki sinifinda',
      (String(d10u.err || d10d.err).replace(/\s+/g, ' ').match(
        /(MALI_DEGISMEZ[A-Z_]*|permission denied[^.]{0,30}|[A-Z][A-Z_]{6,})/) || ['?'])[0].slice(0, 46));

    // --- Kapanis ve kapali folyoya yazma reddi --------------------------
    const d11 = olarak2('personel', `select public.pms_folio_kapat('${FOLYO2()}');`);
    sonuc(d11.ok, 'S16-19 personel: FOLYO KAPATILDI (bakiye 0)',
      d11.ok ? '' : d11.err.replace(/\s+/g, ' ').slice(-90));
    es('S16-20 folyo durumu kapali', 'kapali',
      tek(`select durum::text from public.pms_folyolar where rezervasyon_id='${REZ2}';`));
    const d12 = olarak2('personel', `insert into public.pms_folio_odemeler
      (otel_id, folio_id, yontem, tutar) values ('810','${FOLYO2()}','nakit',${X});`);
    sonuc(!d12.ok, 'S16-21 KAPALI folyoya yazma REDDEDILDI',
      d12.ok ? 'KABUL (kusur)' : 'RET');

    const d13 = olarak2('personel', `select public.pms_check_out('${REZ2}');`);
    sonuc(d13.ok, 'S16-22 personel: CHECK-OUT KABUL',
      d13.ok ? '' : d13.err.replace(/\s+/g, ' ').slice(-90));

    // --- SON DELTA: eski satirlar korundu, yeniler AYRI sayildi --------
    es('S16-23 YENI hareket deltasi tam 1', 1, harSay() - harOnce);
    es('S16-24 YENI odeme deltasi tam 3 (+1,00 / -1,00 / +1,00)', 3, odeSay() - odeOnce);
    es('S16-25 bu folyonun son bakiyesi 0,00', '0.00', bakiye());
    es('S16-26 baslangictaki mali satirlarin hicbiri silinmedi', 0, maliKayip());
    sonuc(true, 'S16-27 SIRA OZETI (canlida beklenen delta)',
      'hareketler +' + (harSay() - harOnce) + ' · odemeler +' + (odeSay() - odeOnce)
      + ' · son bakiye ' + bakiye() + ' · folyo kapali');

    // =====================================================================
    // S9 — IDEMPOTENSLIK: ayni dosyalar ikinci kez
    // =====================================================================
    const i1 = metinUygula(MALI);
    const i2 = metinUygula(KILIT);
    const damgaOnce = tek(`select distinct split_part(guncelleyen,'@',1) from public.yetki_matrisi
      where guncelleyen like 'tohum:pms-onburo:%';`);
    const i3 = O.sql(tohumMetni);
    sonuc(i1.ok && i2.ok && i3.ok, 'S9 uc dosya da ikinci kez uygulanabildi',
      'mali=' + (i1.ok ? 'ok' : 'HATA') + ' kilit=' + (i2.ok ? 'ok' : 'HATA') + ' tohum=' + (i3.ok ? 'ok' : 'HATA'));
    es('S9b ikinci tohumlama YENI satir uretmedi', eksikOnce, damgali());
    es('S9b2 ikinci kosum 0 satir ekledigini kendisi bildirdi', 0, eklenenBildirim(i3));
    es('S9c ilk kosumun damgasi korundu (ikinci kosum ustune yazmadi)', damgaOnce,
      tek(`select distinct split_part(guncelleyen,'@',1) from public.yetki_matrisi
           where guncelleyen like 'tohum:pms-onburo:%';`));

    // =====================================================================
    // S14 — YP-1: ONCEDEN VAR OLAN HEDEF YETKILER
    // Sozlesme: son durumda 15 hedef cift dogru seviyede olmali ve EKLENEN
    // damgali satir sayisi, onceden EKSIK olan sayiya esit olmali. "Her zaman
    // 15 yeni satir" YANLIS bir beklentidir.
    // =====================================================================
    // Fikstur yardimcisi: damgali satirlari kaldirir (gercek geri alma S11'de
    // ayrica olculuyor; burada amac senaryo kurmak).
    const damgalariSil = () => O.sql(`set session_replication_role = replica;
      delete from public.yetki_matrisi where guncelleyen like 'tohum:pms-onburo:%';
      set session_replication_role = origin;`);
    // Hedef cifti ONCEDEN, damgasiz olarak yazar (baska birinin daha once
    // vermis olmasini taklit eder).
    const onceVar = (rol, modul, yetki) => O.sql(`set session_replication_role = replica;
      insert into public.yetki_matrisi (rol_id, modul_id, yetki)
      select r.id, m.id, '${yetki}'::public.yetki_seviye
        from public.roller r, public.moduller m
       where r.kod='${rol}' and m.kod='${modul}'
      on conflict (rol_id, modul_id) do nothing;
      set session_replication_role = origin;`);

    // --- S14a: BIR hedef cift onceden UYUMLU -> 14 yeni satir
    damgalariSil();
    onceVar('onburo_sef', 'pms_misafir', 'tam');
    es('S14a-hazirlik onceden uyumlu 1 hedef cift var', 14, 15 - hedefTutan());
    const a1r = O.sql(tohumMetni);
    sonuc(a1r.ok, 'S14a onceden 1 uyumlu satir varken tohumlama BASARILI',
      a1r.ok ? '' : a1r.err.split('\n').filter((l) => /ERROR/.test(l))[0]);
    es('S14a2 eklenen damgali satir 14 (15 DEGIL)', 14, damgali());
    es('S14a3 dosya da 14/15 bildirdi', 14, eklenenBildirim(a1r));
    es('S14a4 SON DURUM yine 15 hedef cift dogru seviyede', 15, hedefTutan());
    es('S14a5 onceden var olan satir DAMGALANMADI (ustverisi korundu)', 1,
      say(`select count(*) from public.yetki_matrisi y
             join public.roller r on r.id=y.rol_id
             join public.moduller m on m.id=y.modul_id
            where r.kod='onburo_sef' and m.kod='pms_misafir' and y.guncelleyen is null;`));

    // --- S14b: TUM hedef ciftler onceden UYUMLU -> 0 yeni satir, yine basarili
    damgalariSil();
    for (const [r, m, y] of HEDEF) onceVar(r, m, y);
    es('S14b-hazirlik onceden eksik hedef cift YOK', 0, 15 - hedefTutan());
    const b1r = O.sql(tohumMetni);
    sonuc(b1r.ok, 'S14b tum hedefler onceden varken tohumlama BASARILI (hata degil)',
      b1r.ok ? '' : b1r.err.split('\n').filter((l) => /ERROR/.test(l))[0]);
    es('S14b2 eklenen damgali satir 0 — ve bu MESRU', 0, damgali());
    es('S14b3 dosya da 0/15 bildirdi', 0, eklenenBildirim(b1r));
    es('S14b4 SON DURUM 15 hedef cift dogru seviyede', 15, hedefTutan());

    // --- S14c: BIR hedef cift onceden CELISIK -> DURMALI, 0 satir yazmali
    damgalariSil();
    O.sql(`set session_replication_role = replica;
      delete from public.yetki_matrisi y using public.roller r, public.moduller m
       where y.rol_id=r.id and y.modul_id=m.id
         and r.kod='onburo_personel' and m.kod='pms_folio';
      set session_replication_role = origin;`);
    onceVar('onburo_personel', 'pms_folio', 'goruntule');   // hedef: kayit
    const c1r = O.sql(tohumMetni);
    sonuc(!c1r.ok && /CELISEN MEVCUT YETKI/.test(c1r.err),
      'S14c CELISIK mevcut yetkide tohumlama DURDU (mevcut hak degistirilmiyor)',
      c1r.ok ? 'KABUL (kusur)' : (c1r.err.match(/CELISEN MEVCUT YETKI/) ||
        ['BEKLENMEYEN: ' + c1r.err.replace(/\s+/g, ' ').slice(-90)])[0]);
    es('S14c2 ret aninda HICBIR damgali satir yazilmadi', 0, damgali());
    es('S14c3 celisik mevcut satir DEGISTIRILMEDI', 'goruntule',
      tek(`select y.yetki::text from public.yetki_matrisi y
             join public.roller r on r.id=y.rol_id
             join public.moduller m on m.id=y.modul_id
            where r.kod='onburo_personel' and m.kod='pms_folio';`));
    // Preflight AYNI celiskiyi yayin oncesi gorebiliyor mu — kapinin degeri bu.
    const pf3 = O.sql(readFileSync(KOK + PREFLIGHT, 'utf8'));
    sonuc(pf3.ok && /CELISEN/.test(pf3.out) && /SAPMA: Adim 4 KOSULMAZ/.test(pf3.out),
      'S14c4 preflight celiskiyi YAYIN ONCESI yakaladi (Adim 4 KOSULMAZ)',
      pf3.ok ? (pf3.out.match(/onburo_personel\|pms_folio\|[^\n]*/) || ['bulunamadi'])[0].slice(0, 70)
             : 'preflight hata');

    // =====================================================================
    // S15 — CANLI OLCUMUN AYNASI (2026-10-07 salt-okuma preflight ciktisi)
    // Uretimde olculen durum: bes hedef modul VAR ve AKTIF; uc On Buro rolu
    // VAR; 15 hedef ciftin tamami EKSIK; buna karsin `it_admin` ve
    // `sistem_admin` bes modulu `tam` ile ZATEN kullaniyor = 10 mevcut yetki.
    // Beklenen son durum: 10 korunmus + 15 yeni = 25 satir.
    // Bu blok kabul listesinin DAYANAGINI olcer; geri alma fazi da bu
    // uretim-bicimli durum uzerinde kosar.
    // =====================================================================
    damgalariSil();
    O.sql(`set session_replication_role = replica;
      delete from public.yetki_matrisi y using public.roller r, public.moduller m
       where y.rol_id=r.id and y.modul_id=m.id and r.kod like 'onburo\\_%'
         and m.kod in ('pms_oda_tipi','pms_oda','pms_misafir','pms_rezervasyon','pms_folio');
      set session_replication_role = origin;`);
    // Yonetici yetkileri DAMGASIZ yazilir: canlida da bu paket tarafindan
    // yazilmadilar, baska bir kurulumdan geliyorlar.
    O.sql(`set session_replication_role = replica;
      insert into public.yetki_matrisi (rol_id, modul_id, yetki)
      select r.id, m.id, 'tam'::public.yetki_seviye
        from public.roller r
        cross join public.moduller m
       where r.kod in ('it_admin','sistem_admin')
         and m.kod in ('pms_oda_tipi','pms_oda','pms_misafir','pms_rezervasyon','pms_folio')
      on conflict (rol_id, modul_id) do nothing;
      set session_replication_role = origin;`);
    const yoneticiSay = () => say(`select count(*) from public.yetki_matrisi y
      join public.roller r on r.id = y.rol_id
      join public.moduller m on m.id = y.modul_id
      where r.kod in ('it_admin','sistem_admin') and y.yetki::text = 'tam'
        and m.kod in ('pms_oda_tipi','pms_oda','pms_misafir','pms_rezervasyon','pms_folio');`);
    const besModulSatir = () => say(`select count(*) from public.yetki_matrisi y
      join public.moduller m on m.id = y.modul_id
      where m.kod in ('pms_oda_tipi','pms_oda','pms_misafir','pms_rezervasyon','pms_folio');`);
    const yoneticiDamgasiz = () => say(`select count(*) from public.yetki_matrisi y
      join public.roller r on r.id = y.rol_id
      join public.moduller m on m.id = y.modul_id
      where r.kod in ('it_admin','sistem_admin') and y.guncelleyen is null
        and m.kod in ('pms_oda_tipi','pms_oda','pms_misafir','pms_rezervasyon','pms_folio');`);
    es('S15-hazirlik 10 yonetici yetkisi kuruldu (it_admin + sistem_admin x5 tam)', 10, yoneticiSay());
    es('S15-hazirlik2 15 hedef cift EKSIK (canli olcumle ayni)', 15, 15 - hedefTutan());
    const menuOnce15 = menuRolleri();

    const s15 = O.sql(tohumMetni);
    sonuc(s15.ok, 'S15 canli aynasinda tohumlama BASARILI',
      s15.ok ? '' : s15.err.split('\n').filter((l) => /ERROR/.test(l))[0]);
    es('S15b 15 YENI damgali satir yazildi', 15, damgali());
    es('S15c dosya da 15/15 bildirdi', 15, eklenenBildirim(s15));
    es('S15d 10 YONETICI yetkisi KORUNDU (seviye tam)', 10, yoneticiSay());
    es('S15e yonetici satirlari DAMGALANMADI (ustverileri bozulmadi)', 10, yoneticiDamgasiz());
    es('S15f bes modul icin SON DURUM 25 satir (10 korunmus + 15 yeni)', 25, besModulSatir());
    es('S15g bes modul hala AKTIF (tohumlama modul satirini EKLEMEDI/DEGISTIRMEDI)', 5,
      say(`select count(*) from public.moduller where aktif is true and kod in
             ('pms_oda_tipi','pms_oda','pms_misafir','pms_rezervasyon','pms_folio');`));
    const menuSonra15 = menuRolleri();
    const kayip15 = (menuOnce15 ? menuOnce15.split(',') : [])
      .filter((x) => !(menuSonra15 ? menuSonra15.split(',') : []).includes(x));
    sonuc(kayip15.length === 0 && /it_admin/.test(menuSonra15) && /sistem_admin/.test(menuSonra15),
      'S15h menuyu ONCE goren yoneticiler hala goruyor',
      'once=[' + menuOnce15 + ']' + (kayip15.length ? ' KAYIP: ' + kayip15.join(',') : ''));
    // Geri alma fazi bu durumdan baslar; damgasiz satir sayisi sabit kalmali.
    const damgasizOnce = say(`select count(*) from public.yetki_matrisi
      where guncelleyen is null or guncelleyen not like 'tohum:pms-onburo:%';`);
    sonuc(damgasizOnce >= refYetki + 10, 'S15i damgasiz satir tabani kaydedildi',
      String(damgasizOnce));

    // =====================================================================
    // S10–S13 — GERI ALMA, BELGEDEKI SIRAYLA
    // Paket §5.2: Adim 4 -> 3 -> 2 -> 1 (tohumlama -> arayuz -> MY-4 -> mali).
    // Arayuz geri almasi bu SQL provasinin KAPSAMINDA DEGILDIR (ayri kanal:
    // onceki commit'in yeniden yayinlanmasi); bu sinir acik birakilir.
    // Veritabani sirasi: TOHUMLAMA -> MY-4 KILIDI -> MALI KURAL.
    // =====================================================================
    const g1 = metinUygula(MALI_GERI);
    sonuc(!g1.ok, 'S10 tohumlama ayaktayken mali kuralin geri alinmasi ENGELLENDI',
      g1.ok ? 'KABUL (kusur)' : (g1.err.replace(/\s+/g, ' ').match(/GUVENLI GERI DONUS ENGELI[^:]*:[^.]{0,52}/) ||
        ['RET: ' + g1.err.replace(/\s+/g, ' ').slice(0, 70)])[0]);
    es('S10b engel aninda 15 satir yerinde kaldi', 15,
      say(`select count(*) from public.yetki_matrisi where guncelleyen like 'tohum:pms-onburo:%';`));

    // Geri alma, kaldirilacak kurulumun kimligini acikca ister (sessiz
    // varsayilan yok). Kimlik ileri kosumun yazdigi damgadan okunur.
    const uygulamaId = tek(`select distinct split_part(split_part(guncelleyen,'@',1), ':', 3)
      from public.yetki_matrisi where guncelleyen like 'tohum:pms-onburo:%';`);
    sonuc(/^[0-9a-f-]{36}$/.test(uygulamaId),
      'S10c kaldirilacak kurulumun kimligi damgadan okundu', uygulamaId);
    const g2kimliksiz = metinUygula(TOHUM_GERI);
    sonuc(!g2kimliksiz.ok && /UYGULAMA KIMLIGI VERILMEDI/.test(g2kimliksiz.err),
      'S10d kimlik verilmeden geri alma DURDU (sessiz varsayilan yok)',
      g2kimliksiz.ok ? 'KABUL (kusur)' : 'RET');
    const g2 = O.sql(geriAlKopyasi(readFileSync(KOK + TOHUM_GERI, 'utf8'), uygulamaId));
    sonuc(g2.ok, 'S11 tohumlama geri alindi (kimlik verilerek)',
      g2.ok ? '' : g2.err.split('\n').filter((l) => /ERROR/.test(l))[0]);
    es('S11b damgali 15 satirin hepsi kalkti', 0,
      say(`select count(*) from public.yetki_matrisi where guncelleyen like 'tohum:pms-onburo:%';`));
    // Geri alma, DAMGASIZ hicbir satira dokunmamali: referans veri, 09-13 kat
    // hizmetleri izi ve 10 YONETICI yetkisi aynen kalmali.
    es('S11c damgasiz satirlarin tamami DOKUNULMADI', damgasizOnce,
      say(`select count(*) from public.yetki_matrisi
             where guncelleyen is null or guncelleyen not like 'tohum:pms-onburo:%';`));
    es('S11c2 10 YONETICI yetkisi geri almadan SAG CIKTI', 10, yoneticiSay());
    es('S11c3 yonetici satirlari hala damgasiz (ustverileri bozulmadi)', 10, yoneticiDamgasiz());
    es('S11c4 bes modul satiri hala AKTIF (geri alma modulu dusurmedi)', 5,
      say(`select count(*) from public.moduller where aktif is true and kod in
             ('pms_oda_tipi','pms_oda','pms_misafir','pms_rezervasyon','pms_folio');`));
    es('S11c5 bes modul icin son durum 10 satir (yalniz yonetici yetkileri)', 10, besModulSatir());
    if (T.faz2) {
      es('S11d 09-13 kat hizmetleri izi DOKUNULMADI', hkYetki,
        say(`select count(*) from public.yetki_matrisi y join public.moduller m on m.id=y.modul_id
             where m.kod='pms_housekeeping';`));
    }

    // --- 2. GERI ALMA ADIMI: MY-4 KILIDI (belgedeki Adim 2) ---------------
    const g3 = metinUygula(KILIT_GERI);
    sonuc(g3.ok, 'S12 MY-4 kilidi geri alindi (G1-G4 gecti) — sirada IKINCI',
      g3.ok ? '' : g3.err.split('\n').filter((l) => /ERROR/.test(l))[0]);
    es('S12b uc fonksiyon yeniden INVOKER (definer kalmadi)', 0,
      say(`select count(*) from pg_proc where pronamespace='public'::regnamespace and prosecdef
             and proname in ('pms_rezervasyon_kontrol','pms_check_in','pms_check_out');`));
    es('S12c dar kilit yardimcisi dusuruldu', 0,
      say(`select count(*) from pg_proc where pronamespace='public'::regnamespace
             and proname='pms_oda_tipi_kilitle';`));
    // YP-3: yalniz "invoker oldu" yetmez — govdeler ve ACL de Faz 1'e donmeli.
    es('S12d uc GOVDE Faz 1 ozetlerine BIREBIR dondu', md5Once,
      tek(`select string_agg(proname || '=' || md5(prosrc), ' ' order by proname)
           from pg_proc where pronamespace='public'::regnamespace
             and proname in ('pms_rezervasyon_kontrol','pms_check_in','pms_check_out');`));
    es('S12e ACL Faz 1 beklentisine dondu (anon kapali)', aclOnce, aclOzeti());
    es('S12f search_path pinsiz kalan fonksiyon yok', 0,
      say(`select count(*) from pg_proc p where p.pronamespace='public'::regnamespace
             and p.proname in ('pms_rezervasyon_kontrol','pms_check_in','pms_check_out')
             and not exists (select 1 from unnest(coalesce(p.proconfig,'{}'::text[])) c
                              where c like 'search\\_path=%');`));

    // --- 3. GERI ALMA ADIMI: MALI KURAL (belgedeki Adim 1) ----------------
    const g4 = metinUygula(MALI_GERI);
    sonuc(g4.ok, 'S13 mali kural geri alindi — sirada UCUNCU (en son)',
      g4.ok ? '' : g4.err.split('\n').filter((l) => /ERROR/.test(l))[0]);
    es('S13b hassas kapi tetikleyicisi kalmadi', 0,
      say(`select count(*) from pg_trigger t join pg_class c on c.oid=t.tgrelid
           where t.tgname='pms_folio_hassas_kapi' and not t.tgisinternal;`));
    es('S13c mali satirlar SILINMEDI (geri alma veri kaybetmedi)', 1,
      say(`select count(*) from public.pms_folio_hareketleri where id='${hId}';`));
    es('S13d folyo satir sayisi korundu', folyoSatirOnce,
      say(`select count(*) from public.pms_folio_hareketleri where folio_id='${FOLYO}';`)
      + say(`select count(*) from public.pms_folio_odemeler where folio_id='${FOLYO}';`));
    // Uc migration + UC GERI ALMA boyunca hicbir mali satir SILINMEDI.
    // Canlidaki 3 odeme + 6 hareket icin istenen koruma sartinin dayanagi.
    es('S13e baslangictaki mali satirlarin HICBIRI silinmedi', 0, maliKayip());
    sonuc(say(`select count(*) from public.pms_folio_hareketleri;`)
        + say(`select count(*) from public.pms_folio_odemeler;`) >= maliTabanOnce,
      'S13f mali satir sayisi hic azalmadi (yalniz artti)',
      maliTabanOnce + ' -> ' + (say(`select count(*) from public.pms_folio_hareketleri;`)
        + say(`select count(*) from public.pms_folio_odemeler;`)));

    console.log('  ' + '-'.repeat(70));
    console.log('  ' + tabanAdi + ': ' + ok + ' gecti, ' + fail + ' kaldi');
    return { ok, fail, atlandi: false };
  } finally {
    O.temizle();
  }
}

// ===========================================================================
// Ust kosum: iki tabani AYRI SURECLERDE kosar (sema dokumu modul duzeyinde
// sabitlendigi icin tek surecte iki taban kurulamaz).
// ===========================================================================
// YP-2: alt sonuc ve ust sonuc AYRI dogrulanir. Alt surecte hem basarisizlik
// hem "hic olcum yapilmadi" hali basarisizliktir; atlanmis taban kendi cikis
// koduyla ayirt edilir ki ust surec onu GECTI yazamasin.
const ATLAMA_CIKIS = 70;

if (process.env.PROVA_TABAN) {
  const r = await tabanProvasi(process.env.PROVA_TABAN);
  if (r.atlandi) process.exit(ATLAMA_CIKIS);
  // Sifir olcum de basarisizliktir: kurulum sessizce yarida kalmis olabilir.
  if (r.ok === 0) {
    console.log('  BASARISIZ: hic olcum yapilmadi (ok=0) — kosum gecerli sayilmaz');
    process.exit(1);
  }
  process.exit(r.fail > 0 ? 1 : 0);
} else {
  console.log('='.repeat(74));
  console.log('PMS CANLIYA GECIS PROVASI — iki taban');
  console.log('Yerel izole kanit. CANLI KABUL ve canli yetki degisikligi YERINE GECMEZ.');
  console.log('='.repeat(74));
  let toplamOk = 0, toplamFail = 0;
  const ozet = [];
  for (const ad of Object.keys(TABANLAR)) {
    const r = spawnSync(process.execPath, [new URL(import.meta.url).pathname.replace(/^\/([A-Za-z]:)/, '$1')],
      { env: { ...process.env, PROVA_TABAN: ad }, encoding: 'utf8', stdio: 'inherit', timeout: 1800000 });
    ozet.push({ ad, kod: r.status });
    if (r.status !== 0) toplamFail++;
    else toplamOk++;
  }
  console.log('\n' + '='.repeat(74));
  for (const o of ozet) {
    console.log('  ' + o.ad.padEnd(8) + (o.kod === 0 ? 'GECTI'
      : o.kod === ATLAMA_CIKIS ? 'SINANMADI — ZORUNLU TABAN EKSIK (cikis ' + o.kod + ')'
      : 'KALDI (cikis ' + o.kod + ')'));
  }
  const zorunlu = Object.keys(TABANLAR).length;
  const sinanmayan = ozet.filter((o) => o.kod === ATLAMA_CIKIS).map((o) => o.ad);
  // Ust sonuc, ZORUNLU taban sayisina gore verilir: atlanmis taban varsa
  // "gecti" yazilmaz.
  const gecti = toplamFail === 0 && toplamOk === zorunlu;
  console.log('SONUC: ' + toplamOk + '/' + zorunlu + ' taban gecti, ' + toplamFail + ' taban kaldi'
    + (sinanmayan.length ? ' — SINANMAYAN: ' + sinanmayan.join(', ') : ''));
  console.log(gecti ? 'PROVA GECTI (iki taban da olculdu).'
    : 'PROVA GECMEDI — her iki taban olculmeden yayin kaniti sayilmaz.');
  console.log('='.repeat(74));
  process.exit(gecti ? 0 : 1);
}
