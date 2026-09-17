// ===========================================================================
// STOK RPC GOVDELERI — URETIMIN TEK KANONIK KOPYASI
// ===========================================================================
// NEDEN VAR: 2026-09-17'de stok.guncelleme_tarihi hatasi, test ortaminin
// URETIMDE OLMAYAN bir davranisi var saymasi yuzunden gorunmez kaldi.
// scripts/stok-test-ortam.mjs icindeki stok_ekle kopyasi sutunu guncelliyordu;
// uretimdeki fonksiyon guncellemiyordu. Testler yesildi, ekran yanlis tarih
// gosterdi.
//
// KURAL: test ortami stok RPC'lerini ELLE yazmaz. Uretim govdesi burada
// birebir durur (md5'i ile), degisiklik ise docs/kurulum altindaki GERCEK
// migration dosyasi uygulanarak gelir. Test ortami boylece canliya gidecek
// SQL'in aynisini kosar.
//
// Govdeler 2026-09-17 salt-okuma teshisinden alindi (pg_get_functiondef),
// satir sonlari dahil: uretimdeki govdeler CRLF tasir ve md5(prosrc) buna
// duyarlidir.
// ===========================================================================

// Uretimde olculen md5(prosrc) degerleri — DEGISTIRME. Tutmuyorsa uretim
// degismis demektir: once olc, sonra buraya yaz.
export const URETIM_MD5 = {
  stok_ekle: '24d255cc03df86bb4c9f6c978cadce81',
  stok_transfer: '4c6fe1217463841653bec7637f3bf259',
};

const CR = (satirlar) => '\r\n' + satirlar.join('\r\n') + '\r\n';

export const EKLE_GOVDE = CR([
  'declare',
  '  v_yeni numeric;',
  'begin',
  '  insert into stok (urun_kodu, depo_kodu, otel_id, miktar)',
  '  values (p_urun_kodu, p_depo_kodu, p_otel_id::otel_id, greatest(0, p_delta))',
  '  on conflict (urun_kodu, depo_kodu)',
  '  do update set miktar = greatest(0, stok.miktar + p_delta)',
  '  returning miktar into v_yeni;',
  '  return v_yeni;',
  'end;',
]);

export const TRANSFER_GOVDE = CR([
  'begin',
  '  update stok set miktar = greatest(0, miktar - p_miktar)',
  '    where urun_kodu = p_urun_kodu and depo_kodu = p_kaynak_depo;',
  '  insert into stok (urun_kodu, depo_kodu, otel_id, miktar)',
  '    values (p_urun_kodu, p_hedef_depo, p_hedef_otel::otel_id, p_miktar)',
  '    on conflict (urun_kodu, depo_kodu)',
  '    do update set miktar = greatest(0, stok.miktar + p_miktar);',
  'end;',
]);

// Uretimdeki imza + ayarlar + ACL. ACL onemli: migration'in onkosulu
// EXECUTE haklarini dogrular, yanlis ACL'li bir ortamda test yanlis yerden
// kirmis olurdu.
export const URETIM_RPC_SEMA = (ekleGovde = EKLE_GOVDE, transferGovde = TRANSFER_GOVDE) => `
  create or replace function public.stok_ekle(p_urun_kodu text, p_depo_kodu text, p_otel_id text, p_delta numeric)
    returns numeric language plpgsql
    set search_path to 'pg_catalog', 'public', 'extensions', 'pg_temp'
    as $function$${ekleGovde}$function$;
  create or replace function public.stok_transfer(p_urun_kodu text, p_kaynak_depo text, p_hedef_depo text, p_hedef_otel text, p_miktar numeric)
    returns void language plpgsql
    set search_path to 'pg_catalog', 'public', 'extensions', 'pg_temp'
    as $function$${transferGovde}$function$;
  revoke all on function public.stok_ekle(text,text,text,numeric) from public, anon;
  grant execute on function public.stok_ekle(text,text,text,numeric) to authenticated, service_role;
  revoke all on function public.stok_transfer(text,text,text,text,numeric) from public, anon;
  grant execute on function public.stok_transfer(text,text,text,text,numeric) to authenticated, service_role;
`;

// Uretim gibi: otel_id bir enum tipi, text degil. Cast'siz atama 42804 verir
// ve bu tam olarak 2026-07-17'de canlida yasanmisti.
export const OTEL_ID_TIPI = `
  do $t$ begin
    if to_regtype('public.otel_id') is null then
      create type public.otel_id as enum ('810', '811');
    end if;
  end $t$;
`;

// Stok RPC'lerine dokunan, uygulanmis/aday migration'lar — sirasiyla.
export const STOK_RPC_MIGRATIONLARI = [
  'docs/kurulum/2026-09-17-stok-guncelleme-tarihi.sql',
];

// Kurulan govdeler uretimle birebir mi? Test ortami her kosuda bunu dogrular;
// tutmuyorsa testler "uretimde olmayan davranisi" olcuyor demektir.
export const MD5_SORGUSU = `select string_agg(proname || '=' || md5(prosrc), ',' order by proname)
  from pg_proc where pronamespace = 'public'::regnamespace
   and proname in ('stok_ekle','stok_transfer')`;

export const MD5_BEKLENEN = Object.entries(URETIM_MD5)
  .sort(([a], [b]) => a.localeCompare(b)).map(([k, v]) => k + '=' + v).join(',');
