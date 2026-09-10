// ============================================================================
// PMS FAZ 2 — KAT HİZMETLERİ SABOTAJ (MUTASYON) TESTLERİ
// ----------------------------------------------------------------------------
// YALNIZ ATILABILIR YEREL DOCKER STAGING'DE ÇALIŞIR. Her mutant KENDİ
// veritabanında yaşar (`create database ... template <kaynak>`) ve sonunda
// düşürülür. Üretime hiçbir şey uygulanmaz.
//
//   node scripts/pms-faz2-housekeeping-sabotaj.mjs [konteyner] [kaynak_vt]
//
// ---------------------------------------------------------------------------
// YÖNTEM (mimari §23)
// ---------------------------------------------------------------------------
// Her mutant için SIRAYLA:
//   1) HEDEF DOĞRULAMA — sabotajın vuracağı nesne tam olarak beklenen sayıda
//      ve beklenen tanımda mı? Hedef yoksa bu bir KURULUM HATASIDIR, yeşil
//      test değildir.
//   2) SAĞLAM ÖLÇÜM — korumaya özgü sonda, sistem bozulmadan çalıştırılır ve
//      `KORUNDU` vermek ZORUNDADIR. Vermezse sonda yanlıştır; mutasyona
//      geçilmez.
//   3) MUTASYON — tek bir katman kaldırılır.
//   4) BOZUK ÖLÇÜM — aynı sonda `IHLAL` vermek ZORUNDADIR. Hâlâ `KORUNDU`
//      diyorsa test o katmanı hiç sınamıyordur; alakasız bir hata da
//      (bağlantı, eksik tablo, yetki) kabul edilmez.
//
// Sonda sonucu NOTICE ile değil, tablodan SELECT ile okunur; hata metni ve
// SQLSTATE rapora aynen basılır.
// ============================================================================

import { spawn } from 'node:child_process';

const KONTEYNER = process.argv[2] || 'hk';
const KAYNAK    = process.argv[3] || 'hkdb';

let ok = 0, fail = 0;
const rapor = [];

function psql(vt, sql, durdur = true) {
  return new Promise((coz) => {
    // stderr konteyner icinde stdout'a birlestirilir: iki ayri boru
    // kullanildiginda hata metni ile normal cikti karisik sirada gelebilir.
    const bayrak = durdur ? '-v ON_ERROR_STOP=1' : '';
    const p = spawn('docker',
      ['exec', '-i', KONTEYNER, 'sh', '-c',
       `psql -X -U postgres -d ${vt} -q -A -t -P pager=off ${bayrak} 2>&1`],
      { stdio: ['pipe', 'pipe', 'pipe'] });
    let cikti = '';
    p.stdout.on('data', (d) => { cikti += d.toString(); });
    p.stderr.on('data', (d) => { cikti += d.toString(); });
    p.on('close', (kod) => coz({ kod, cikti: cikti.trim() }));
    p.stdin.end(sql);
  });
}

const tekSatir = async (vt, sql) => (await psql(vt, sql)).cikti.trim();

// ---------------------------------------------------------------------------
// ORTAK FİKSTÜR — iki otel, yetkili/yetkisiz aktörler, odalar, görevler
// ---------------------------------------------------------------------------
const FIKSTUR = `
update public.moduller set aktif = true where kod = 'pms_housekeeping';
insert into public.moduller (kod, ad, kategori, sira, aktif)
values ('pms_oda','On Buro - Odalar','onburo',44,true)
on conflict (kod) do update set aktif = true;

drop table if exists public.sb_fikstur;
create table public.sb_fikstur (ad text primary key, deger uuid);
drop table if exists public.sb_sonuc;
create table public.sb_sonuc (deger text);

do $f$
declare
  v_tam uuid; v_kayit uuid; v_bos uuid;
  v_a_sup uuid := gen_random_uuid();   -- 810 yetkili (tam)
  v_a_isci uuid := gen_random_uuid();  -- 810 calisan (kayit)
  v_a_yok uuid := gen_random_uuid();   -- 810 aktif AMA hk yetkisi YOK
  v_a_811 uuid := gen_random_uuid();   -- 811 yetkili
  v_sup uuid; v_isci uuid; v_yok uuid; v_s811 uuid;
  v_t810 uuid; v_t811 uuid;
  v_o1 uuid; v_o2 uuid; v_o811 uuid;
  v_g810 uuid; v_g811 uuid;
begin
  insert into public.roller (ad, seviye) values ('SB Tam','otel')   returning id into v_tam;
  insert into public.roller (ad, seviye) values ('SB Kayit','otel') returning id into v_kayit;
  insert into public.roller (ad, seviye) values ('SB Bos','otel')   returning id into v_bos;

  insert into public.yetki_matrisi (rol_id, modul_id, yetki)
  select v_tam, id, 'tam' from public.moduller where kod in ('pms_housekeeping','pms_oda');
  insert into public.yetki_matrisi (rol_id, modul_id, yetki)
  select v_kayit, id, 'kayit' from public.moduller where kod = 'pms_housekeeping';
  -- v_bos: KASITLI olarak hicbir kat hizmetleri yetkisi yok; ama pms_oda
  -- yetkisi VAR ki gorunurluk/RLS gecirgenligi ayri olarak kanitlanabilsin.
  insert into public.yetki_matrisi (rol_id, modul_id, yetki)
  select v_bos, id, 'tam' from public.moduller where kod = 'pms_oda';

  insert into auth.users (id) values (v_a_sup), (v_a_isci), (v_a_yok), (v_a_811);
  insert into public.kullanicilar (ad, rol, rol_id, otel_id, aktif, auth_user_id)
  values ('SB Sup','yonetici', v_tam,'810', true, v_a_sup) returning id into v_sup;
  insert into public.kullanicilar (ad, rol, rol_id, otel_id, aktif, auth_user_id)
  values ('SB Isci','depo', v_kayit,'810', true, v_a_isci) returning id into v_isci;
  insert into public.kullanicilar (ad, rol, rol_id, otel_id, aktif, auth_user_id)
  values ('SB Yok','depo', v_bos,'810', true, v_a_yok) returning id into v_yok;
  insert into public.kullanicilar (ad, rol, rol_id, otel_id, aktif, auth_user_id)
  values ('SB S811','yonetici', v_tam,'811', true, v_a_811) returning id into v_s811;

  insert into public.pms_oda_tipleri (otel_id,kod,ad,azami_kisi,azami_yetiskin,azami_cocuk)
  values ('810','sb','SB 810',2,2,1) returning id into v_t810;
  insert into public.pms_oda_tipleri (otel_id,kod,ad,azami_kisi,azami_yetiskin,azami_cocuk)
  values ('811','sb','SB 811',2,2,1) returning id into v_t811;

  insert into public.pms_odalar (otel_id,oda_tipi_id,oda_no) values ('810',v_t810,'SB01') returning id into v_o1;
  insert into public.pms_odalar (otel_id,oda_tipi_id,oda_no) values ('810',v_t810,'SB02') returning id into v_o2;
  insert into public.pms_odalar (otel_id,oda_tipi_id,oda_no) values ('811',v_t811,'SB81') returning id into v_o811;

  perform set_config('request.jwt.claim.role','authenticated',true);
  perform set_config('request.jwt.claim.sub', v_a_sup::text, true);
  v_g810 := (public.pms_housekeeping_gorev_olustur(v_o1,'ekstra_temizlik','bos',gen_random_uuid())->>'gorev_id')::uuid;

  perform set_config('request.jwt.claim.sub', v_a_811::text, true);
  v_g811 := (public.pms_housekeeping_gorev_olustur(v_o811,'ekstra_temizlik','bos',gen_random_uuid())->>'gorev_id')::uuid;

  insert into public.sb_fikstur values
    ('a_sup',v_a_sup),('a_isci',v_a_isci),('a_yok',v_a_yok),('a_811',v_a_811),
    ('sup',v_sup),('isci',v_isci),('yok',v_yok),('s811',v_s811),
    ('o1',v_o1),('o2',v_o2),('o811',v_o811),
    ('g810',v_g810),('g811',v_g811);
end
$f$;
`;

// Sondaların ortak sarmalayıcısı: sonucu TABLOYA yazar, sonra SELECT ile okunur.
const sonda = (govde) => `
truncate public.sb_sonuc;
do $s$
declare v_kod text; v_msg text; v_kis text;
begin
${govde}
exception when others then
  get stacked diagnostics v_kod = returned_sqlstate, v_msg = message_text,
                          v_kis = constraint_name;
  insert into public.sb_sonuc values ('HATA|' || v_kod || '|' ||
    coalesce(v_kis,'-') || '|' || replace(coalesce(v_msg,''), '|', '/'));
end
$s$;
select coalesce((select deger from public.sb_sonuc limit 1), 'SONUC-YOK');
`;

const jwt = (ad) =>
  `  perform set_config('request.jwt.claim.role','authenticated',false);
  perform set_config('request.jwt.claim.sub',
    (select deger from public.sb_fikstur where ad='${ad}')::text, false);`;

// Layer izolasyonu: SAĞLAM ve BOZUK tarafta AYNI dışlamalar kullanılır.
const kapat = (t) => t.map((x) => `alter table ${x[0]} disable trigger ${x[1]};`).join('\n');
const ac    = (t) => t.map((x) => `alter table ${x[0]} enable trigger ${x[1]};`).join('\n');

const GOREV = 'public.pms_housekeeping_gorevleri';
const ODA   = 'public.pms_odalar';

// ---------------------------------------------------------------------------
// MUTANTLAR
// ---------------------------------------------------------------------------
const MUTANTLAR = [
  // ---- 1 ------------------------------------------------------------------
  {
    kod: 'S1', ad: 'pms_housekeeping_aktif_oda_uniq kaldirildi',
    hedef: `select count(*)::text from pg_indexes
            where schemaname='public' and indexname='pms_housekeeping_aktif_oda_uniq'
              and indexdef like '%(otel_id, oda_id)%'
              and indexdef like '%bekliyor%' and indexdef like '%temizleniyor%';`,
    hedefBeklenen: '1',
    mutasyon: `drop index public.pms_housekeeping_aktif_oda_uniq;`,
    dislama: [[GOREV, 'pms_housekeeping_gorev_koruma'],
              [GOREV, 'pms_housekeeping_tutarlilik_gorev'],
              [GOREV, 'phase0_islem_audit'],
              [ODA,   'pms_housekeeping_tutarlilik_oda']],
    // Guvenilir fikstur yazicisi ayni odaya IKINCI bitmemis gorev satiri koyar.
    sonda: `
  create temp table sb_kopya on commit drop as
    select * from ${GOREV} where id=(select deger from public.sb_fikstur where ad='g810');
  update sb_kopya set id = gen_random_uuid(), son_islem_anahtari = gen_random_uuid(),
         istek_anahtari = gen_random_uuid();
  insert into ${GOREV} select * from sb_kopya;
  insert into public.sb_sonuc values ('IHLAL');`,
    korunduKosul: (r) => r.startsWith('HATA|23505|pms_housekeeping_aktif_oda_uniq|')
  },

  // ---- 2 ------------------------------------------------------------------
  {
    kod: 'S2', ad: 'gorev gecis bekcisi (trigger) kaldirildi',
    hedef: `select count(*)::text from pg_trigger
            where tgrelid='${GOREV}'::regclass and not tgisinternal
              and tgname='pms_housekeeping_gorev_koruma';`,
    hedefBeklenen: '1',
    mutasyon: `drop trigger pms_housekeeping_gorev_koruma on ${GOREV};`,
    dislama: [[GOREV, 'pms_housekeeping_tutarlilik_gorev'],
              [GOREV, 'phase0_islem_audit'],
              [ODA,   'pms_housekeeping_tutarlilik_oda']],
    // bekliyor -> tamamlandi DOGRUDAN: matriste olmayan gecis.
    sonda: `
  update ${GOREV}
     set durum='tamamlandi', baslama_zamani=now(), bitis_zamani=now(),
         atanan_kullanici_id=(select deger from public.sb_fikstur where ad='isci'),
         surum = surum + 1
   where id=(select deger from public.sb_fikstur where ad='g810');
  insert into public.sb_sonuc values ('IHLAL');`,
    korunduKosul: (r) => /^HATA\|/.test(r) && /GECIS|gecis/i.test(r)
  },

  // ---- 3 ------------------------------------------------------------------
  {
    kod: 'S3', ad: 'kisitlayici otel kapsami politikasi kaldirildi',
    hedef: `select count(*)::text from pg_policies
            where schemaname='public' and tablename='pms_housekeeping_gorevleri'
              and policyname='phase0_otel_kisit' and permissive='RESTRICTIVE';`,
    hedefBeklenen: '1',
    // KASITLI olarak her seyi acan bir PERMISSIVE okuma politikasi eklenir;
    // otel kapsamini AYAKTA tutan tek sey kisitlayici politikadir.
    hazirlik: `create policy sb_hepsi on ${GOREV} for select to authenticated using (true);`,
    mutasyon: `drop policy phase0_otel_kisit on ${GOREV};`,
    sonda: `
${jwt('a_sup')}
  set local role authenticated;
  if (select count(*) from ${GOREV}
        where id=(select deger from public.sb_fikstur where ad='g811')) > 0 then
    insert into public.sb_sonuc values ('IHLAL');
  else
    insert into public.sb_sonuc values ('KORUNDU');
  end if;`,
    korunduKosul: (r) => r === 'KORUNDU',
    // Sondanin gercekten okuyabildigini kanitla: kendi otelinin satirini
    // GORMELI. Aksi halde 'KORUNDU' yalnizca RLS sessizligi olurdu.
    gecirgenlik: `
${jwt('a_sup')}
  set local role authenticated;
  if (select count(*) from ${GOREV}
        where id=(select deger from public.sb_fikstur where ad='g810')) = 1 then
    insert into public.sb_sonuc values ('GECIRGEN');
  else
    insert into public.sb_sonuc values ('KOR');
  end if;`
  },

  // ---- 4 ------------------------------------------------------------------
  {
    kod: 'S4', ad: 'RPC otel kapsami kontrolu (hk_komut) kaldirildi',
    hedef: `select count(*)::text from pg_proc p join pg_namespace n on n.oid=p.pronamespace
            where n.nspname='phase0_private' and p.proname='hk_komut'
              and pg_get_functiondef(p.oid) like '%auth_otel_erisim%';`,
    hedefBeklenen: '1',
    govdeMutasyonu: {
      fonksiyonlar: `select p.oid::text from pg_proc p join pg_namespace n on n.oid=p.pronamespace
                     where n.nspname='phase0_private' and p.proname='hk_komut';`,
      sil: /if\s+public\.auth_otel_erisim\([\s\S]*?end if;/gis,
      enAz: 1
    },
    // 810 yetkilisi 811 otelinin gorevini iptal etmeye calisir.
    sonda: `
${jwt('a_sup')}
  perform public.pms_housekeeping_iptal(
    (select deger from public.sb_fikstur where ad='g811'),
    'sabotaj sondasi',
    (select surum from ${GOREV} where id=(select deger from public.sb_fikstur where ad='g811')),
    gen_random_uuid());
  insert into public.sb_sonuc values ('IHLAL');`,
    korunduKosul: (r) => r.startsWith('HATA|P0002|')
  },

  // ---- 5 ------------------------------------------------------------------
  {
    kod: 'S5', ad: 'bilesik oda/otel yabanci anahtari kaldirildi',
    hedef: `select count(*)::text from pg_constraint
            where conrelid='${GOREV}'::regclass and conname='pms_housekeeping_oda_fk'
              and contype='f'
              and pg_get_constraintdef(oid) like 'FOREIGN KEY (oda_id, otel_id) REFERENCES pms_odalar(id, otel_id)%';`,
    hedefBeklenen: '1',
    mutasyon: `alter table ${GOREV} drop constraint pms_housekeeping_oda_fk;`,
    dislama: [[GOREV, 'pms_housekeeping_gorev_koruma'],
              [GOREV, 'pms_housekeeping_tutarlilik_gorev'],
              [GOREV, 'phase0_islem_audit'],
              [ODA,   'pms_housekeeping_tutarlilik_oda']],
    // otel_id 810, oda_id ise 811 otelinin odasi: yapisal olarak IMKANSIZ olmali.
    sonda: `
  create temp table sb_kopya on commit drop as
    select * from ${GOREV} where id=(select deger from public.sb_fikstur where ad='g810');
  update sb_kopya set id = gen_random_uuid(), son_islem_anahtari = gen_random_uuid(),
         istek_anahtari = gen_random_uuid(),
         oda_id = (select deger from public.sb_fikstur where ad='o811');
  insert into ${GOREV} select * from sb_kopya;
  insert into public.sb_sonuc values ('IHLAL');`,
    korunduKosul: (r) => r.startsWith('HATA|23503|pms_housekeeping_oda_fk|')
  },

  // ---- 6 ------------------------------------------------------------------
  {
    kod: 'S6', ad: 'komut yetkilendirmesi (auth_yetki_var) kaldirildi',
    hedef: `select count(*)::text from pg_proc p join pg_namespace n on n.oid=p.pronamespace
            where n.nspname in ('public','phase0_private')
              and (p.proname like 'pms_housekeeping%' or p.proname like 'hk_%')
              and pg_get_functiondef(p.oid) like '%auth_yetki_var(''pms_housekeeping''%';`,
    hedefBeklenenEnAz: 1,
    govdeMutasyonu: {
      fonksiyonlar: `select p.oid::text from pg_proc p join pg_namespace n on n.oid=p.pronamespace
                     where n.nspname in ('public','phase0_private')
                       and (p.proname like 'pms_housekeeping%' or p.proname like 'hk_%')
                       and pg_get_functiondef(p.oid) like '%auth_yetki_var(''pms_housekeeping''%';`,
      sil: /if\s+public\.auth_yetki_var\('pms_housekeeping'[\s\S]*?end if;/gis,
      enAz: 1
    },
    // Aktif, ayni otelde, AMA kat hizmetleri yetkisi olmayan kullanici
    // yonetici islemini kendi RPC girisinden dener.
    sonda: `
${jwt('a_yok')}
  perform public.pms_housekeeping_ata(
    (select deger from public.sb_fikstur where ad='g810'),
    (select deger from public.sb_fikstur where ad='isci'),
    (select surum from ${GOREV} where id=(select deger from public.sb_fikstur where ad='g810')),
    gen_random_uuid());
  insert into public.sb_sonuc values ('IHLAL');`,
    korunduKosul: (r) => r.startsWith('HATA|42501|')
  },

  // ---- 7 ------------------------------------------------------------------
  {
    kod: 'S7', ad: 'oda/gorev tutarlilik denetleyicisi (H) kaldirildi',
    hedef: `select count(*)::text from pg_trigger
            where tgrelid='${GOREV}'::regclass and not tgisinternal
              and tgname='pms_housekeeping_tutarlilik_gorev' and tgdeferrable and tginitdeferred;`,
    hedefBeklenen: '1',
    mutasyon: `drop trigger pms_housekeeping_tutarlilik_gorev on ${GOREV};`,
    dislama: [[GOREV, 'pms_housekeeping_gorev_koruma'],
              [GOREV, 'phase0_islem_audit']],
    // Gorev tamamlandi; oda izdusumu KASITLI olarak yapilmadi (oda 'kirli').
    // Ihlal ile `set constraints` AYNI blokta olmali: PL/pgSQL alt-transaction.
    sonda: `
  update ${GOREV}
     set durum='temizleniyor', baslama_zamani=now(),
         atanan_kullanici_id=(select deger from public.sb_fikstur where ad='isci'),
         surum = surum + 1
   where id=(select deger from public.sb_fikstur where ad='g810');
  update ${GOREV}
     set durum='tamamlandi', bitis_zamani=now(), surum = surum + 1
   where id=(select deger from public.sb_fikstur where ad='g810');
  set constraints all immediate;
  insert into public.sb_sonuc values ('IHLAL');`,
    korunduKosul: (r) => /^HATA\|/.test(r) && /H5|temiz|tutarl/i.test(r)
  },

  // ---- 8 ------------------------------------------------------------------
  {
    kod: 'S8', ad: 'oda bekcisi / gecerli gosterge korumasi kaldirildi',
    hedef: `select count(*)::text from pg_trigger
            where tgrelid='${ODA}'::regclass and not tgisinternal
              and tgname='pms_housekeeping_oda_koruma';`,
    hedefBeklenen: '1',
    mutasyon: `drop trigger pms_housekeeping_oda_koruma on ${ODA};`,
    dislama: [[ODA, 'pms_housekeeping_tutarlilik_oda']],
    // Gosterge KATMANINI yalitir. Baska bir goreve isaret etmek bilesik FK'ye
    // takilirdi ve mutant BASKA bir katman tarafindan yakalanirdi — bu §23'e
    // gore gecerli tespit sayilmaz. Gostergeyi NULL yapmak FK'yi tumuyle
    // devre disi birakir; ayakta kalan tek koruma oda bekcisidir.
    sonda: `
${jwt('a_sup')}
  set local role authenticated;
  update ${ODA} set temizlik_gorevi_id = null
   where id=(select deger from public.sb_fikstur where ad='o1');
  insert into public.sb_sonuc values ('IHLAL');`,
    korunduKosul: (r) => /^HATA\|/.test(r),
    // RLS sessizligi tuzagi: ayni rol ayni satiri BASKA bir kolonda
    // GERCEKTEN guncelleyebiliyor mu?
    gecirgenlik: `
${jwt('a_sup')}
  set local role authenticated;
  update ${ODA} set oda_no = oda_no
   where id=(select deger from public.sb_fikstur where ad='o1');
  if found then insert into public.sb_sonuc values ('GECIRGEN');
  else insert into public.sb_sonuc values ('KOR'); end if;`
  },

  // ---- 9 ------------------------------------------------------------------
  {
    kod: 'S9', ad: 'denetim izi tetikleyicisi kaldirildi',
    hedef: `select count(*)::text from pg_trigger
            where tgrelid='${GOREV}'::regclass and not tgisinternal
              and tgname='phase0_islem_audit';`,
    hedefBeklenen: '1',
    mutasyon: `drop trigger phase0_islem_audit on ${GOREV};`,
    // Is basarili olurken denetim satiri OLUSMAZSA bu tespit edilmelidir.
    sonda: `
${jwt('a_isci')}
  create temp table sb_once on commit drop as
    select count(*) as n from public.erp_islem_audit;
  perform public.pms_housekeeping_sahiplen(
    (select deger from public.sb_fikstur where ad='g810'),
    (select surum from ${GOREV} where id=(select deger from public.sb_fikstur where ad='g810')),
    gen_random_uuid());
  if (select count(*) from public.erp_islem_audit) > (select n from sb_once) then
    insert into public.sb_sonuc values ('KORUNDU');
  else
    insert into public.sb_sonuc values ('IHLAL');
  end if;`,
    korunduKosul: (r) => r === 'KORUNDU'
  }
];

// ---------------------------------------------------------------------------
async function govdeMutasyonuUygula(vt, m) {
  const oidler = (await tekSatir(vt, m.govdeMutasyonu.fonksiyonlar))
    .split('\n').map((x) => x.trim()).filter(Boolean);
  if (oidler.length < 1) return { hata: 'mutasyon hedefi bulunamadi' };
  let toplam = 0;
  for (const oid of oidler) {
    const tanim = (await psql(vt, `select pg_get_functiondef(${oid});`)).cikti;
    const eslesme = tanim.match(m.govdeMutasyonu.sil);
    if (!eslesme) continue;
    toplam += eslesme.length;
    const yeni = tanim.replace(m.govdeMutasyonu.sil, '');
    const r = await psql(vt, yeni);
    if (r.kod !== 0) return { hata: 'mutant fonksiyon kurulamadi: ' + r.cikti };
  }
  if (toplam < m.govdeMutasyonu.enAz) {
    return { hata: `mutasyon hicbir yeri degistirmedi (${toplam})` };
  }
  return { sayi: toplam };
}

// Her olcum KENDI taze veritabaninda yapilir. Ayni veritabaninda fiksturu
// ikinci kez kurmak benzersizlik ihlaliyle duser ve `sb_fikstur` BOS kalir;
// o durumda sonda hicbir sey olcmeden 'KORUNDU' der. Bu tuzak boylece yapisal
// olarak imkansiz hale gelir.
async function vtHazirla(m, ad) {
  await psql('postgres', `drop database if exists ${ad} with (force);`);
  const y = await psql('postgres', `create database ${ad} template ${KAYNAK};`);
  if (y.kod !== 0) return { hata: 'veritabani olusturulamadi: ' + y.cikti };
  const f = await psql(ad, FIKSTUR);
  if (f.kod !== 0) return { hata: 'fikstur: ' + f.cikti };
  if (m.hazirlik) {
    const h = await psql(ad, m.hazirlik);
    if (h.kod !== 0) return { hata: 'hazirlik: ' + h.cikti };
  }
  const n = await tekSatir(ad, `select count(*)::text from public.sb_fikstur;`);
  if (n !== '13') return { hata: `fikstur eksik: ${n}/13 satir` };
  return {};
}

async function mutantiKos(m, i) {
  const vt  = `sb_m${i}_saglam`;
  const vtm = `sb_m${i}_bozuk`;
  const h1 = await vtHazirla(m, vt);
  if (h1.hata) { fail++; console.log(`${m.kod}  FAIL  SAGLAM ${h1.hata}`); return; }
  const h2 = await vtHazirla(m, vtm);
  if (h2.hata) { fail++; console.log(`${m.kod}  FAIL  BOZUK ${h2.hata}`); return; }
  try {
    // 1) HEDEF DOGRULAMA
    const hedef = await tekSatir(vt, m.hedef);
    const hedefTamam = m.hedefBeklenenEnAz !== undefined
      ? (Number(hedef) >= m.hedefBeklenenEnAz)
      : (hedef === m.hedefBeklenen);
    if (!hedefTamam) {
      fail++;
      console.log(`${m.kod}  FAIL  HEDEF YOK — beklenen ` +
        `${m.hedefBeklenenEnAz !== undefined ? '>=' + m.hedefBeklenenEnAz : m.hedefBeklenen}` +
        `, olculen ${hedef} (KURULUM HATASI, yesil test degil)`);
      return;
    }

    // 1b) GECIRGENLIK — sondanin RLS sessizligiyle yanilmadigini kanitla
    let gec = '-';
    if (m.gecirgenlik) {
      gec = await tekSatir(vt, sonda(m.gecirgenlik));
      if (gec !== 'GECIRGEN') {
        fail++;
        console.log(`${m.kod}  FAIL  GECIRGENLIK YOK — sonda satiri hic goremiyor/yazamiyor: ${gec}`);
        return;
      }
    }

    // 2) SAGLAM OLCUM
    const dis = m.dislama ? kapat(m.dislama) : '';
    const dis2 = m.dislama ? ac(m.dislama) : '';
    const saglam = await tekSatir(vt, `${dis}\n${sonda(m.sonda)}\n${dis2}`);
    if (!m.korunduKosul(saglam)) {
      fail++;
      console.log(`${m.kod}  FAIL  SAGLAM sistem korumadi — sonda yanlis. sonuc=[${saglam}]`);
      return;
    }

    // 3) MUTASYON — DOKUNULMAMIS ikinci veritabaninda
    let mutBilgi = '';
    if (m.govdeMutasyonu) {
      const g = await govdeMutasyonuUygula(vtm, m);
      if (g.hata) { fail++; console.log(`${m.kod}  FAIL  ${g.hata}`); return; }
      mutBilgi = `${g.sayi} govde blogu silindi`;
    } else {
      const mm = await psql(vtm, m.mutasyon);
      if (mm.kod !== 0) { fail++; console.log(`${m.kod}  FAIL  mutasyon: ${mm.cikti}`); return; }
      mutBilgi = m.mutasyon.replace(/\s+/g, ' ').trim();
    }

    // 4) BOZUK OLCUM
    const bozuk = await tekSatir(vtm, `${dis}\n${sonda(m.sonda)}\n${dis2}`);
    const tespit = !m.korunduKosul(bozuk);

    if (tespit) {
      ok++;
      console.log(`${m.kod}  OK    ${m.ad}`);
    } else {
      fail++;
      console.log(`${m.kod}  FAIL  MUTANT HAYATTA — koruma kaldirildi ama sonda hala ` +
        `KORUNDU diyor. Bu test o katmani SINAMIYOR. sonuc=[${bozuk}]`);
    }
    rapor.push({
      kod: m.kod, ad: m.ad, mutasyon: mutBilgi, gecirgenlik: gec,
      saglam: saglam.slice(0, 120), bozuk: bozuk.slice(0, 120), tespit
    });
  } finally {
    await psql('postgres', `drop database if exists ${vt} with (force);`);
    await psql('postgres', `drop database if exists ${vtm} with (force);`);
  }
}

async function calis() {
  console.log(`=== SABOTAJ (kaynak: ${KONTEYNER}/${KAYNAK}) ===`);
  for (let i = 0; i < MUTANTLAR.length; i++) await mutantiKos(MUTANTLAR[i], i + 1);

  console.log('\n=== MUTANT RAPORU ===');
  for (const r of rapor) {
    console.log(`${r.kod}  ${r.ad}`);
    console.log(`      mutasyon : ${r.mutasyon}`);
    if (r.gecirgenlik !== '-') console.log(`      gecirgen : ${r.gecirgenlik}`);
    console.log(`      saglam   : ${r.saglam}`);
    console.log(`      bozuk    : ${r.bozuk}`);
  }
  console.log(`\nSABOTAJ SONUC: ${ok} OK / ${fail} FAIL`);
  process.exit(fail > 0 ? 1 : 0);
}

calis().catch((e) => { console.error(e); process.exit(1); });
