-- ============================================================================
-- SIPARISLER: IDEMPOTENCY KOLONLARI
-- Tasarim: docs/superpowers/specs/2026-10-11-talep-siparis-bagi-design.md §3.3
--
-- NEDEN: kullanici "Olustur"a iki kez basarsa iki siparis olusmamali. Anahtar
-- + icerik parmak izi birlikte tutulur: ayni anahtar + ayni icerik mevcut
-- sonucu dondurur, ayni anahtar + FARKLI icerik REDDEDILIR.
--
-- Her iki kolon da nullable; mevcut uc siparis yolu bunlari yazmaz ve
-- davranislari DEGISMEZ. Paylasilan tabloya kolon eklendigi icin sema dokumu
-- ve esitlik dogrulayicisi guncellenmelidir.
--
-- BU DOSYA YAZILDI, URETIME UYGULANMADI.
-- ============================================================================

do $$
begin
  if to_regclass('public.siparisler') is null then
    raise exception 'ONKOSUL: siparisler tablosu yok.';
  end if;
end;
$$;

begin;

alter table public.siparisler add column if not exists islem_anahtari   text;
alter table public.siparisler add column if not exists islem_parmak_izi text;

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'siparisler_islem_anahtari_bicim') then
    alter table public.siparisler add constraint siparisler_islem_anahtari_bicim
      check (islem_anahtari is null
             or (islem_anahtari = btrim(islem_anahtari)
                 and length(islem_anahtari) between 8 and 100));
  end if;
end;
$$;

-- Kismi unique: yalniz dolu anahtarlar tekil. `null` serbest kalir ki
-- mevcut uc yol etkilenmesin.
create unique index if not exists siparisler_islem_anahtari_key
  on public.siparisler (islem_anahtari) where islem_anahtari is not null;

commit;

notify pgrst, 'reload schema';

-- ============================================================================
-- GERI ALMA
--   begin;
--   drop index if exists public.siparisler_islem_anahtari_key;
--   alter table public.siparisler drop constraint if exists siparisler_islem_anahtari_bicim;
--   alter table public.siparisler drop column if exists islem_parmak_izi;
--   alter table public.siparisler drop column if exists islem_anahtari;
--   commit;
-- Kolonlar dusurulurse idempotency kaybolur; RPC de geri alinmalidir.
-- ============================================================================
