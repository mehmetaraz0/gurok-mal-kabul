#!/usr/bin/env node
// ===========================================================================
// BAR A1 GERI ALMA URETICISI — deterministik
// ===========================================================================
// Kaynaklar (elle yazilmaz):
//   * eski bar fonksiyonlari + yetki satirlari: uretim sema dokumu
//     (bar/stok fonksiyonlari 2026-09-13'ten beri degismedi)
//   * stok_ekle / stok_transfer: A1 ONCESI uretim hali = tarih duzeltmeli
//     govdeler; kaynagi duzeltmenin KENDI migration dosyasi (tasarim 3.5.1(3))
// Cikti: docs/kurulum/2026-09-18-bar-a1-guvenlik-geri-al.sql
//
//   node scripts/bar-a1-geri-al-uret.mjs [--stdout]
// ===========================================================================
import { readFileSync, writeFileSync } from 'node:fs';
import { SEMA_DOKUMU, kok } from './bar-test-ortam.mjs';

const dokum = readFileSync(SEMA_DOKUMU, 'utf8');

export function dokumFonksiyonu(ad, imzaBasi = '') {
  const re = new RegExp(`^CREATE FUNCTION public\\.${ad}\\(${imzaBasi}[\\s\\S]*?^\\$\\$;`, 'm');
  const m = dokum.match(re);
  if (!m) throw new Error(ad + ' dokumde yok');
  return m[0].replace(/^CREATE FUNCTION/, 'CREATE OR REPLACE FUNCTION');
}
function dokumYetkileri(ad) {
  return dokum.split('\n').map((l) => l.replace(/\r$/, ''))
    .filter((l) => new RegExp(`^(GRANT|REVOKE) ALL ON FUNCTION public\\.${ad}\\(`).test(l))
    // Standart bicim (migration-guvenlik-kontrol R4/R9); ETKIN yetki ayni kalir:
    //  * fonksiyonda tek hak EXECUTE'tur -> GRANT ALL == GRANT EXECUTE
    //  * dokumde anon'a GRANT yok -> anon'dan REVOKE A1 oncesi hali degistirmez
    // Sira testi geri alma sonrasi ACL'yi A1 oncesiyle birebir karsilastirir.
    .map((l) => l.replace(/^GRANT ALL ON FUNCTION/, 'GRANT EXECUTE ON FUNCTION')
                 .replace(/^(REVOKE ALL ON FUNCTION .*) FROM PUBLIC;$/, '$1 FROM PUBLIC, anon;'))
    .join('\n');
}

// A1 oncesi stok govdeleri: tarih duzeltmesi migration'inin fonksiyon bolumu.
export function tarihDuzeltmesiGovdeleri() {
  const mig = readFileSync(kok + 'docs/kurulum/2026-09-17-stok-guncelleme-tarihi.sql', 'utf8');
  const bas = mig.indexOf('create or replace function public.stok_ekle');
  const bit = mig.indexOf('-- 2) ACL');
  if (bas < 0 || bit < 0) throw new Error('tarih duzeltmesi migration dosyasinda fonksiyon bolumu bulunamadi');
  const govde = mig.slice(bas, bit).replace(/[-=\s]*$/, '').replace(/\r?\n-- =+\s*$/, '');
  if ((govde.match(/guncelleme_tarihi = now\(\)/g) || []).length !== 3) {
    throw new Error('tarih duzeltmesi govdeleri beklenen 3 satiri tasimiyor');
  }
  return govde.trimEnd();
}

const ESKI = [
  ['bar_siparis_olustur'],
  ['bar_siparis_durum_guncelle'],
  ['bar_siparis_teslim_et', 'p_siparis_id uuid\\)'],
  ['bar_siparis_iptal', 'p_siparis_id uuid\\)'],
  ['pms_bar_folio_koprusu'],
  ['pms_bar_durum_kilit'],
];

export function uret() {
  const eskiler = ESKI.map(([ad, imza]) => {
    const yetki = dokumYetkileri(ad);
    // 'SET search_path TO' ile '=' ayni ayardir (proconfig); '=' denetleyicinin
    // tanidigi bicimdir. Govde (prosrc) degismez.
    const tanim = dokumFonksiyonu(ad, imza || '').replace(/^    SET search_path TO /m, '    SET search_path = ');
    return tanim + (yetki ? '\n\n' + yetki : '');
  }).join('\n\n');

  return `-- ============================================================================
-- GERI AL: 2026-09-18-bar-a1-guvenlik.sql
-- ============================================================================
-- # URETIME UYGULANMADI. Yalniz A1 uygulanmis ve geri alinmasi gerekiyorsa. #
-- URETILMIS DOSYA — elle degistirme: node scripts/bar-a1-geri-al-uret.mjs
-- Kaynaklar: ${SEMA_DOKUMU.split(/[\\/]/).pop()} (eski bar fonksiyonlari) +
--            2026-09-17-stok-guncelleme-tarihi.sql (A1 oncesi stok govdeleri)
-- Tek islem olarak uygulanir (sql-uygula.ps1 --single-transaction).
--
-- KORUNUR (geri alinmaz):
--  * Veri: bar_stok_tuketimleri, bar_borc_istisnalari, stok_sayim_bekleyenleri,
--    yeni sutunlar. Eski fonksiyonlar calissin diye yalniz NOT NULL gevsetilir.
--  * Siparis/kalem/rezervasyon tablolarina DOGRUDAN YAZMANIN KAPALI olmasi
--    (runbook §3: ekranlar calissin diye bilinen acik izinler geri acilmaz;
--    hicbir ekran dogrudan yazmiyor).
--  * bar_durum enum'undaki 'istisna_bekliyor' degeri (PostgreSQL enum degeri
--    silinemez; onkosul hic kullanilmadigini dogrular).
--  * 2026-09-17 stok TARIH DUZELTMESI: A1'e ait degildir; stok govdeleri
--    tarih duzeltmeli A1-oncesi haline doner (tasarim 3.5.1(3)).
-- ============================================================================

-- 0) ONKOSULLAR — geri alma veri kaybettirmemeli
do $$
begin
  if to_regprocedure('public.stok_cikis_korumasi(text,text,numeric)') is null then
    raise exception 'ONKOSUL: A1 uygulanmis gorunmuyor; geri alinacak bir sey yok.';
  end if;
  if exists (select 1 from public.bar_borc_istisnalari where durum = 'acik') then
    raise exception 'ONKOSUL: acik borc istisnasi var; once cozulmeli (eski fonksiyonlar istisnayi bilmez).';
  end if;
  if exists (select 1 from public.bar_siparisleri where durum::text = 'istisna_bekliyor') then
    raise exception 'ONKOSUL: istisna bekleyen siparis var; once cozulmeli.';
  end if;
  if exists (select 1 from public.stok_sayim_bekleyenleri where durum = 'bekliyor') then
    raise exception 'ONKOSUL: bekleyen sayim duzeltmesi var; once uygulanmali ya da iptal edilmeli.';
  end if;
end;
$$;

-- Tarih duzeltmesi su an canli mi? Eski govdeler yazilmadan ONCE olculur.
create temp table _a1_geri_tarih on commit drop as
select coalesce(bool_and(prosrc ~* 'guncelleme_tarihi'), false) as vardi
  from pg_proc where pronamespace = 'public'::regnamespace and proname in ('stok_ekle', 'stok_transfer');

-- 1) A1'IN YENI FONKSIYONLARI
drop function if exists public.bar_siparis_teslim_et(uuid, boolean);
drop function if exists public.bar_siparis_iptal(uuid, text, jsonb);
drop function if exists public.bar_siparis_oda_dogrula(uuid, boolean);
drop function if exists public.bar_siparis_oda_reddet(uuid, text);
drop function if exists public.bar_borc_istisnasi_coz(uuid, text, uuid, boolean, text);
drop function if exists public.bar_istisna_listesi();
drop function if exists public.stok_sayim_onayla(uuid);
drop function if exists public.stok_sayim_bekleyen_uygula(uuid);
drop function if exists public.stok_sayim_bekleyen_iptal(uuid, text);
drop function if exists public.bar_masa_yetki_kapsami();
drop function if exists public._bar_konaklama_bul(text, text);
drop function if exists public._bar_folyo_gecerli(uuid, uuid);
-- 15b: eski sayim istemcisi durdurmasi geri alinir (eski istemci detaylari dogrudan okur)
drop trigger if exists stok_sayim_oturum_koruma on public.sayim_oturumlari;
drop function if exists public._stok_sayim_oturum_koruma();
drop function if exists public.stok_sayim_detaylari(uuid);
grant select on table public.sayim_detaylari to authenticated;

-- 2) ESKI FONKSIYONLAR CALISSIN DIYE GEVSETILEN KISITLAR (veri korunur)
alter table public.bar_siparis_kalemleri
  alter column birim_fiyat drop not null,
  alter column ucretli drop not null;
alter table public.bar_siparisleri
  alter column kanal drop not null,
  alter column oda_dogrulama_durumu drop not null;

-- 3) ESKI BAR FONKSIYONLARI (uretim dokumunden) + yetkileri
${eskiler}

-- 4) STOK RPC'LERI — A1 oncesi (TARIH DUZELTMELI) hal
do $$
begin
  if not (select vardi from _a1_geri_tarih) then
    raise exception 'ONKOSUL: A1 govdeleri tarih duzeltmesini tasimiyordu; beklenmeyen durum, dur.';
  end if;
end;
$$;
-- <<STOK_GOVDELERI>>
${tarihDuzeltmesiGovdeleri()}
-- <</STOK_GOVDELERI>>
revoke all on function public.stok_ekle(text, text, text, numeric) from public, anon;
grant execute on function public.stok_ekle(text, text, text, numeric) to authenticated, service_role;
revoke all on function public.stok_transfer(text, text, text, text, numeric) from public, anon;
grant execute on function public.stok_transfer(text, text, text, text, numeric) to authenticated, service_role;

-- 5) A1 IC YARDIMCILARI (artik cagiran yok)
drop function if exists public.stok_cikis_korumasi(text, text, numeric);
drop function if exists public._bar_stok_dus(public.otel_id, text, text, numeric, text);
drop function if exists public._stok_delta_uygula(public.otel_id, text, text, numeric, text, text);
drop function if exists public._stok_kilitle(text, text);

-- 6) SON KOSULLAR
do $$
begin
  if not (select bool_and(prosrc ~* 'guncelleme_tarihi\\s*=\\s*now\\(\\)') from pg_proc
           where pronamespace = 'public'::regnamespace and proname in ('stok_ekle', 'stok_transfer')) then
    raise exception 'SON KOSUL: geri alma tarih duzeltmesini kaybettirdi.';
  end if;
  if exists (select 1 from pg_proc where pronamespace = 'public'::regnamespace
              and prosrc ~* 'stok_cikis_korumasi' and proname in ('stok_ekle', 'stok_transfer')) then
    raise exception 'SON KOSUL: stok RPCleri hala A1 korumasini cagiriyor.';
  end if;
  if to_regprocedure('public.bar_siparis_teslim_et(uuid)') is null
     or to_regprocedure('public.bar_siparis_iptal(uuid)') is null then
    raise exception 'SON KOSUL: eski teslim/iptal imzasi geri gelmedi.';
  end if;
  if has_table_privilege('authenticated', 'public.bar_siparisleri', 'UPDATE') then
    raise exception 'SON KOSUL: dogrudan yazma yeniden acilmis — acilmamaliydi.';
  end if;
end;
$$;
`;
}

if (process.argv[1] && process.argv[1].endsWith('bar-a1-geri-al-uret.mjs')) {
  const metin = uret();
  if (process.argv.includes('--stdout')) process.stdout.write(metin);
  else {
    writeFileSync(kok + 'docs/kurulum/2026-09-18-bar-a1-guvenlik-geri-al.sql', metin);
    console.log('uretildi: docs/kurulum/2026-09-18-bar-a1-guvenlik-geri-al.sql');
  }
}
