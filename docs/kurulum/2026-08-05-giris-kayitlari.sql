-- 2026-08-05 — Kullanıcı-bazlı BAŞARILI giriş kaydı (yönetici görüntüleme).
-- Not: Başarısız denemeler kimliksiz kalır (giris_denemeleri). Bu tablo yalnızca
-- başarılı girişleri kullanıcıya bağlı tutar; INSERT sadece pin-girisi Edge
-- Function tarafından (service_role, RLS bypass) yapılır. Client INSERT edemez.
-- SELECT yalnızca yönetici (kullanici_yonetimi modülü görüntüleme yetkisi).

begin;

create table if not exists public.giris_kayitlari (
  id           bigint generated always as identity primary key,
  kullanici_id uuid,
  ad           text,
  otel_id      public.otel_id,
  giris_tipi   text not null default 'pin',   -- 'pin' | 'microsoft'
  ip_hash      text,
  created_at   timestamptz not null default now()
);

create index if not exists giris_kayitlari_zaman_idx
  on public.giris_kayitlari (created_at desc);

alter table public.giris_kayitlari enable row level security;

-- Sadece yönetici (kullanici_yonetimi görüntüleme) okuyabilir.
drop policy if exists gk_select on public.giris_kayitlari;
create policy gk_select on public.giris_kayitlari
  for select to authenticated
  using (public.auth_yetki_var('kullanici_yonetimi','goruntule'));

-- SELECT yetkisi ver (satır erişimi yine RLS ile yöneticiye daralır).
-- INSERT/UPDATE/DELETE grant'i YOK → client yazamaz; yalnız service_role (EF).
grant select on public.giris_kayitlari to authenticated;

commit;

notify pgrst, 'reload schema';

-- Doğrulama (SQL Editor owner olarak çalışır, RLS'siz görür):
-- select count(*) from public.giris_kayitlari;
-- select * from public.giris_kayitlari order by created_at desc limit 20;
