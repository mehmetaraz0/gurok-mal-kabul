// ===========================================================================
// BAR A1 — DOLU TABLODA MIGRATION + GECIS KIMLIGI (izole; uretime BAGLANMAZ)
// ===========================================================================
// Olculen (kullanici talebi 2026-09-20):
//   1  Tabloda her durumdan siparis varken A1 tek islemde uygulanir ve gecis
//      alanlari dogru doldurulur.
//   2  Gecis guncellemesinin 'service_role' kimligi YALNIZ o islem kapsamindadir:
//      migration dosyasinin SONUNDA (ayni oturum, ayni islem) ayar bostur ve
//      migration'dan sonraki yeni oturumda da bostur.
//   3  Denetim izinde (erp_islem_audit) migration islemi AYIRT EDILIR: backfill
//      satirlari ve isaret satiri AYNI transaction_id'yi tasir; isaret satirinda
//      migration dosyasinin adi ve guncellenen satir sayisi yazar.
//   4  Migration ortasinda hata olursa (yapay hata) hicbir sey kalmaz: gecis
//      alanlari yok, denetim satiri yok, kimlik ayari kalmaz.
// ===========================================================================
import { readFileSync } from 'node:fs';
import { barOrtami, kok } from './bar-test-ortam.mjs';
import { K, BAR, M, EK_TOHUM } from './bar-a1-tohum.mjs';

const MIG = 'docs/kurulum/2026-09-18-bar-a1-guvenlik.sql';
const A1 = readFileSync(kok + MIG, 'utf8').replace(/\r\n/g, '\n');
let ok = 0, fail = 0;
const sonuc = (g, ad, ek) => { console.log((g ? 'OK   ' : 'FAIL ') + ad + (ek ? ' — ' + ek : '')); if (g) ok++; else fail++; };

// A1 ONCESI siparisler: her durumdan, ucretli ve ucretsiz.
function siparisleriKur(O) {
  const t = O.sql(EK_TOHUM); if (!t.ok) throw new Error('ek tohum: ' + t.err.slice(-200));
  const yeni = (durum, menu, masa) => O.sql(`set session_replication_role = replica;
    with s as (
      insert into public.bar_siparisleri (otel_id, depo_id, masa_token, oda_no, durum)
      values ('810','${BAR}','${masa}', ${durum === 'iptal' ? 'null' : `'101'`}, '${durum}') returning id)
    insert into public.bar_siparis_kalemleri (siparis_id, menu_urun_id, adet)
      select s.id, '${menu}', 1 from s;
    set session_replication_role = origin;`);
  yeni('yeni', M.VISKI, 'M-yeni');            // ucretli, acik
  yeni('hazirlaniyor', M.VISKI, 'M-hazirlaniyor');
  yeni('hazir', M.VISKI, 'M-hazir');
  yeni('teslim_edildi', M.VISKI, 'M-teslim');  // ucretli, kapanmis
  yeni('iptal', M.BIRA, 'M-iptal');            // ucretsiz
  yeni('yeni', M.BIRA, 'M-ucretsiz');          // ucretsiz, acik
}

const O = barOrtami({ ad: 'bar-a1-gecis' });
try {
  await O.kur();
  siparisleriKur(O);
  const oncekiSiparis = O.sql(`select count(*) from public.bar_siparisleri;`).out;

  // --- 1 + 2: migration dosyasinin SONUNA ayni islemde calisan kontrol eklenir ---
  const kontrolluA1 = A1 + `
\\echo '== ISLEM ICI KIMLIK KONTROLU =='
select 'islem_ici_rol=[' || coalesce(current_setting('request.jwt.claim.role', true), '') || ']'
       || ' claims=[' || coalesce(current_setting('request.jwt.claims', true), '') || ']' as kimlik;
`;
  const u = O.uygulaTekIslem(kontrolluA1, { metin: true });
  const islemIci = (u.out.match(/islem_ici_rol=\[[^\]]*\] claims=\[[^\]]*\]/) || [''])[0];
  sonuc(u.ok && islemIci === 'islem_ici_rol=[] claims=[]',
    'M1 dolu tabloda A1 tek islemde uygulandi ve gecis kimligi ISLEM ICINDE geri alinmis',
    u.ok ? islemIci : u.err.split('\n').slice(-4).join(' | '));

  const yeniOturum = O.sql(`select '[' || coalesce(current_setting('request.jwt.claim.role', true), '') || ']';`).out;
  sonuc(yeniOturum === '[]', 'M2 migration sonrasi YENI oturumda da gecis kimligi yok', yeniOturum);

  const gecis = O.sql(`select masa_token || '=' || kanal || '/' || oda_dogrulama_durumu
                         from public.bar_siparisleri order by masa_token;`).out.split('\n').join(' ');
  sonuc(/M-yeni=gecis\/bekliyor/.test(gecis) && /M-hazirlaniyor=gecis\/bekliyor/.test(gecis)
     && /M-hazir=gecis\/bekliyor/.test(gecis) && /M-teslim=gecis\/gecis/.test(gecis)
     && /M-iptal=gecis\/gerekmiyor/.test(gecis) && /M-ucretsiz=gecis\/gerekmiyor/.test(gecis),
    'M3 gecis alanlari: acik ucretli -> bekliyor, kapanmis ucretli -> gecis, ucretsiz -> gerekmiyor', gecis);
  sonuc(O.sql(`select count(*) from public.bar_siparis_kalemleri where birim_fiyat is null or ucretli is null;`).out === '0'
     && O.sql(`select count(*) from public.bar_siparis_kalemleri where ucretli;`).out === '4',
    'M4 kalemler guncel menu fiyatiyla dolduruldu; ucretli bayragi menuden geldi');

  // --- 3: denetim izi ---
  const izSatir = O.sql(`select actor_role || '|' || coalesce(actor_user_id::text, '-') || '|' || event_type || '|' || entity_type
                           || '|' || (islem_detayi ->> 'migration') || '|' || (islem_detayi ->> 'guncellenen_satir')
                           from public.erp_islem_audit where entity_id = 'A1-GECIS-ISARETI';`).out;
  const tekIslem = O.sql(`select count(distinct transaction_id) || '/' || count(*) from public.erp_islem_audit;`).out;
  const digerIslem = O.sql(`select count(*) from public.erp_islem_audit a
                             where a.transaction_id <> (select transaction_id from public.erp_islem_audit where entity_id='A1-GECIS-ISARETI');`).out;
  sonuc(izSatir === `service_role|-|UPDATE|bar_siparisleri|2026-09-18-bar-a1-guvenlik.sql|${oncekiSiparis}`
     && tekIslem === `1/${Number(oncekiSiparis) + 1}` && digerIslem === '0',
    'M5 denetim izi: backfill satirlari + ISARET satiri ayni transaction_id; isaret migration adini ve satir sayisini tasiyor',
    izSatir + ' | islem/satir ' + tekIslem);
} catch (e) {
  sonuc(false, 'beklenmeyen hata (ana)', e.stack || e.message);
} finally { O.temizle(); }

// --- 4: migration ortasinda hata -> hicbir sey kalmaz ---
const H = barOrtami({ ad: 'bar-a1-gecis-hata' });
try {
  await H.kur();
  siparisleriKur(H);
  const isaret = '-- 3) YENI TABLOLAR';
  if (!A1.includes(isaret)) throw new Error('hata enjeksiyonu icin isaret bulunamadi');
  const bozuk = A1.replace(isaret, `do $$ begin raise exception 'YAPAY HATA: gecis sonrasi'; end $$;\n` + isaret);
  const h = H.uygulaTekIslem(bozuk, { metin: true });
  const kalan = H.sql(`select count(*) from information_schema.columns
                        where table_name = 'bar_siparisleri' and column_name = 'kanal';`).out;
  sonuc(!h.ok && /YAPAY HATA/.test(h.err) && kalan === '0'
     && H.sql(`select count(*) from public.erp_islem_audit;`).out === '0'
     && H.sql(`select '[' || coalesce(current_setting('request.jwt.claim.role', true), '') || ']';`).out === '[]'
     && H.sql(`select count(*) from public.bar_siparisleri;`).out !== '0',
    'M6 migration ortasinda hata: gecis alanlari YOK, denetim satiri YOK, kimlik ayari kalmadi, siparisler duruyor',
    (h.err.match(/YAPAY HATA[^\n]*/) || [''])[0]);
} catch (e) {
  sonuc(false, 'beklenmeyen hata (hata senaryosu)', e.stack || e.message);
} finally { H.temizle(); }

console.log(`\nBAR A1 GECIS MIGRATION: ${ok} OK / ${fail} FAIL`);
process.exit(fail ? 1 : 0);
