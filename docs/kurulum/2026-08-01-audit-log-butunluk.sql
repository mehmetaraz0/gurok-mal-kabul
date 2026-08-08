-- 2026-08-01 — #2: audit_log bütünlüğü (kim-yaptı taklidini engelle)
--
-- SORUN: audit_log.kullanici_ad istemciden geliyor (auditLogYaz -> currentUser.ad).
-- Giriş yapmış herhangi biri POST'ta kullanici_ad'ı istediği isimle gönderip sahte
-- denetim kaydı yazabilir (başkasını suçlama dahil).
--
-- ÇÖZÜM: BEFORE INSERT trigger her satırda gerçek kullanıcıyı auth.uid()'den damgalar:
--   - auth_user_id (yeni kolon) = auth.uid() (trusted aktör kimliği, taklit edilemez)
--   - kullanici_ad = gerçek kullanıcının adı (istemcinin gönderdiği DEĞER EZİLİR)
-- İstemci kodu (auditLogYaz) DEĞİŞMEZ — gönderdiği kullanici_ad sunucuda düzeltilir.
-- Trigger SECURITY DEFINER: kullanicilar RLS'ine takılmadan gerçek adı okuyabilsin.
--
-- Mevcut satırlara dokunmaz (yalnızca yeni insert'ler damgalanır).
-- Çalıştırma: SQL Editor -> Run. Rollback: en altta.

begin;

-- 1) Trusted aktör kimliği kolonu (nullable, trigger dolduracak)
alter table public.audit_log add column if not exists auth_user_id uuid;

-- 2) Damgalama fonksiyonu
create or replace function public.audit_log_damgala()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  -- Gerçek aktör: JWT'deki auth.uid() (istemci bunu değiştiremez)
  new.auth_user_id := auth.uid();
  -- kullanici_ad'ı gerçek kullanıcının adıyla EZ (istemcinin iddiasını yok say).
  -- Kullanıcı bulunamazsa (nadir) istemcinin gönderdiği değeri koru.
  new.kullanici_ad := coalesce(
    (select ad from public.kullanicilar where auth_user_id = auth.uid() limit 1),
    new.kullanici_ad
  );
  return new;
end;
$$;

-- 3) Trigger
drop trigger if exists tg_audit_log_damgala on public.audit_log;
create trigger tg_audit_log_damgala
before insert on public.audit_log
for each row
execute function public.audit_log_damgala();

commit;

-- ============================================================
-- TEST:
-- 1) Uygulamada bir işlem yap (ör. bir kayıt güncelle) -> audit_log'a satır düşsün.
--    Denetim İzi ekranında kullanici_ad'ın SENİN gerçek adın olduğunu gör.
-- 2) SQL ile son kayıtlar (kullanici_ad + auth_user_id dolu mu):
--    select zaman, action, kullanici_ad, auth_user_id from public.audit_log
--    order by zaman desc limit 5;
--    -> kullanici_ad gerçek ad, auth_user_id DOLU olmalı.
-- 3) (İsteğe bağlı taklit testi) Geçerli bir JWT ile curl'den kullanici_ad:"SAHTE"
--    gönder -> kayıtta kullanici_ad yine GERÇEK ad olmalı (SAHTE değil).
-- ============================================================
-- ROLLBACK:
-- begin;
-- drop trigger if exists tg_audit_log_damgala on public.audit_log;
-- drop function if exists public.audit_log_damgala();
-- -- (auth_user_id kolonu kalabilir; istersen: alter table public.audit_log drop column auth_user_id;)
-- commit;
