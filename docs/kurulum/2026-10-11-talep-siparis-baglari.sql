-- ============================================================================
-- TALEP -> SIPARIS BAG TABLOSU
-- Tasarim: docs/superpowers/specs/2026-10-11-talep-siparis-bagi-design.md §3.1
--
-- NEDEN: `satin_alma_talepleri.siparis_no` hic doldurulmuyor ve tek metin alani
-- bir talebin N siparise bolunmesini temsil edemiyor. Bu tablo (talep kalemi,
-- siparis, miktar) tanesinde kalici bag tutar.
--
-- BIRIM DONDURMA: `miktar` daima `hedef_birim` cinsindendir ve `hedef_birim`
-- bag yazildigi anda talep kaleminin birimidir. Kalan hesabi guncel katalog
-- donusumunu ASLA kullanmaz (spec §1.1).
--   Referans ornek: 10 KOL talep · siparis satiri 72 KG · yazma aninda
--   12 KG/KOL -> bag 6 KOL -> kalan 4 KOL.
--
-- BU DOSYA YAZILDI, URETIME UYGULANMADI.
-- ============================================================================

do $$
begin
  if to_regclass('public.satin_alma_talep_kalemleri') is null
     or to_regclass('public.siparisler') is null then
    raise exception 'ONKOSUL: talep kalemleri / siparisler tablosu yok.';
  end if;
  if to_regprocedure('public.auth_otel_erisim(text)') is null then
    raise exception 'ONKOSUL: auth_otel_erisim yok (Phase 0 gerekli).';
  end if;
end;
$$;

begin;

create table if not exists public.talep_siparis_baglari (
  id               uuid primary key default gen_random_uuid(),
  otel_id          public.otel_id not null,
  talep_id         uuid not null references public.satin_alma_talepleri(id),
  talep_kalem_id   uuid not null references public.satin_alma_talep_kalemleri(id),
  -- ON DELETE RESTRICT: bagi olan siparis SILINEMEZ (spec §7 K7).
  -- Duzeltme yolu `durum='iptal'`; bag gecmisi korunur.
  siparis_no       text not null references public.siparisler(siparis_no) on delete restrict,
  urun_kodu        text,
  miktar           numeric(12,3) not null,
  hedef_birim      text not null,
  kaynak_miktar    numeric(12,3) not null,
  kaynak_birim     text not null,
  carpan           numeric,
  olusturan_ad     text,
  olusturma_tarihi timestamptz not null default now(),
  constraint talep_siparis_baglari_miktar        check (miktar > 0),
  constraint talep_siparis_baglari_kaynak_miktar check (kaynak_miktar > 0),
  constraint talep_siparis_baglari_carpan        check (carpan is null or carpan > 0),
  constraint talep_siparis_baglari_birim         check (btrim(hedef_birim) <> '' and btrim(kaynak_birim) <> ''),
  constraint talep_siparis_baglari_tekil         unique (talep_kalem_id, siparis_no)
);

create index if not exists idx_tsb_kalem   on public.talep_siparis_baglari (talep_kalem_id);
create index if not exists idx_tsb_siparis on public.talep_siparis_baglari (siparis_no);
create index if not exists idx_tsb_otel    on public.talep_siparis_baglari (otel_id, talep_id);

-- RLS: yalniz OKUMA politikasi var. insert/update/delete politikasi YOK ve
-- ayricalik da verilmez -> yazma yalniz `security definer` RPC'den.
-- Tablo mantiksal olarak append-only; duzeltme siparisi iptal ederek yapilir.
alter table public.talep_siparis_baglari enable row level security;

drop policy if exists tsb_select on public.talep_siparis_baglari;
create policy tsb_select on public.talep_siparis_baglari
  for select to authenticated
  using ((public.auth_yetki_var('siparis_olustur','goruntule')
          or public.auth_yetki_var('siparis_takip','goruntule'))
         and public.auth_otel_erisim(otel_id::text) is true);

-- Otel kapsamini kisitlayici katmanla da kilitle (diger tablolarla ayni desen).
drop policy if exists tsb_otel_kisit on public.talep_siparis_baglari;
create policy tsb_otel_kisit on public.talep_siparis_baglari
  as restrictive to authenticated
  using (public.auth_otel_erisim(otel_id::text) is true);

-- TABLO IZINLERI: okuma var, yazma YOK.
revoke all on table public.talep_siparis_baglari from public, anon;
revoke all on table public.talep_siparis_baglari from authenticated;
grant select on table public.talep_siparis_baglari to authenticated;
-- service_role KASITLI: sunucu tarafi raporlama okuyabilsin, yazamaz.
revoke all on table public.talep_siparis_baglari from service_role;
grant select on table public.talep_siparis_baglari to service_role;

commit;

notify pgrst, 'reload schema';

-- ============================================================================
-- GERI ALMA
--   begin;
--   drop table if exists public.talep_siparis_baglari;   -- BAG GECMISINI SILER
--   commit;
-- UYARI: bu tabloyu dusurmek izlenebilirlik kaydini yok eder. Yalniz hic
-- uretim verisi yazilmamisken yapilir.
-- ============================================================================
