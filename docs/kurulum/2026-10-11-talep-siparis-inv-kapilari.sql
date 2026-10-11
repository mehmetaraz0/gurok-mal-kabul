-- ============================================================================
-- INV KAPILARI (K1-K7)
-- Tasarim: docs/superpowers/specs/2026-10-11-talep-siparis-bagi-design.md §7
--
-- INV: her talep kalemi icin, IPTAL OLMAYAN siparislere ait baglarin toplami
-- kalemin miktarini asamaz; tum miktarlar kalemin kendi biriminde.
--
-- RPC'deki kontrol kullaniciya anlasilir mesaj icin; BU TETIKLEYICILER
-- degismez guvence icin. Bag hangi yoldan gelirse gelsin INV bozulamaz.
--
-- BU DOSYA YAZILDI, URETIME UYGULANMADI.
-- ============================================================================

do $$
begin
  if to_regclass('public.talep_siparis_baglari') is null then
    raise exception 'ONKOSUL: talep_siparis_baglari yok. Once bag tablosu migration''i.';
  end if;
end;
$$;

begin;

-- ---------------------------------------------------------------------------
-- Paylasilan hesap: AYNI talep kalemi satir kilidi altinda toplar.
-- `p_haric_bag_id`: UPDATE'te eski satirin iki kez sayilmamasi icin.
-- ---------------------------------------------------------------------------
create or replace function public.talep_bag_inv_kontrol(
  p_talep_kalem_id uuid,
  p_eklenecek      numeric,
  p_haric_bag_id   uuid default null)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $fn$
declare
  v_kalem numeric;
  v_birim text;
  v_bagli numeric;
begin
  -- Kilit: eszamanli iki islem ayni kalemde sirayla hesaplar.
  select miktar, birim into v_kalem, v_birim
    from public.satin_alma_talep_kalemleri
   where id = p_talep_kalem_id
   for update;
  if not found then
    raise exception 'kalem_yok: talep kalemi % bulunamadi', p_talep_kalem_id
      using errcode = '23503';
  end if;

  select coalesce(sum(b.miktar), 0) into v_bagli
    from public.talep_siparis_baglari b
    join public.siparisler s on s.siparis_no = b.siparis_no
   where b.talep_kalem_id = p_talep_kalem_id
     and s.durum <> 'iptal'
     and b.hedef_birim = v_birim
     and (p_haric_bag_id is null or b.id <> p_haric_bag_id);

  if v_bagli + coalesce(p_eklenecek, 0) > v_kalem then
    raise exception 'miktar_asimi: kalem % (miktar % %), bagli %, eklenecek %, kalan %',
      p_talep_kalem_id, v_kalem, v_birim, v_bagli, p_eklenecek, v_kalem - v_bagli
      using errcode = '23514';
  end if;
end;
$fn$;

revoke all on function public.talep_bag_inv_kontrol(uuid, numeric, uuid) from public, anon;
revoke all on function public.talep_bag_inv_kontrol(uuid, numeric, uuid) from authenticated;
revoke all on function public.talep_bag_inv_kontrol(uuid, numeric, uuid) from service_role;

-- ---------------------------------------------------------------------------
-- K1/K2: bag insert / update
-- ---------------------------------------------------------------------------
create or replace function public.tsb_inv_tetik()
returns trigger
language plpgsql
set search_path = pg_catalog, public, pg_temp
as $fn$
begin
  if tg_op = 'INSERT' then
    perform public.talep_bag_inv_kontrol(new.talep_kalem_id, new.miktar, null);
  else
    perform public.talep_bag_inv_kontrol(new.talep_kalem_id, new.miktar, old.id);
  end if;
  return new;
end;
$fn$;

drop trigger if exists tsb_inv_ekle on public.talep_siparis_baglari;
create trigger tsb_inv_ekle before insert on public.talep_siparis_baglari
  for each row execute function public.tsb_inv_tetik();

drop trigger if exists tsb_inv_guncelle on public.talep_siparis_baglari;
create trigger tsb_inv_guncelle before update of miktar, talep_kalem_id
  on public.talep_siparis_baglari
  for each row execute function public.tsb_inv_tetik();

-- ---------------------------------------------------------------------------
-- K3: siparisi IPTALDEN GERI ALMA
-- Iptal edilmis siparisin baglari sayilmiyordu; geri alinirsa sayilacak.
-- ---------------------------------------------------------------------------
create or replace function public.sip_iptal_geri_al_inv_tetik()
returns trigger
language plpgsql
set search_path = pg_catalog, public, pg_temp
as $fn$
declare r record;
begin
  if old.durum = 'iptal' and new.durum <> 'iptal' then
    for r in select b.talep_kalem_id, sum(b.miktar) as m
               from public.talep_siparis_baglari b
              where b.siparis_no = new.siparis_no
              group by b.talep_kalem_id loop
      perform public.talep_bag_inv_kontrol(r.talep_kalem_id, r.m, null);
    end loop;
  end if;
  return new;
end;
$fn$;

drop trigger if exists sip_iptal_geri_al_inv on public.siparisler;
create trigger sip_iptal_geri_al_inv before update of durum on public.siparisler
  for each row execute function public.sip_iptal_geri_al_inv_tetik();

-- ---------------------------------------------------------------------------
-- K4: siparis kalemi miktarini DUSURME
-- Karsilastirma `kaynak_miktar`/`kaynak_birim` uzerinden: siparis satirina
-- GIRILEN deger ile ayni birimde, donusum gerekmez (spec §1.1).
-- ---------------------------------------------------------------------------
create or replace function public.sipk_miktar_inv_tetik()
returns trigger
language plpgsql
set search_path = pg_catalog, public, pg_temp
as $fn$
declare v_bagli numeric;
begin
  if new.miktar >= old.miktar then
    return new;                      -- artirma INV'i bozmaz
  end if;

  select coalesce(sum(b.kaynak_miktar), 0) into v_bagli
    from public.talep_siparis_baglari b
   where b.siparis_no = new.siparis_no
     and b.kaynak_birim = new.birim
     and coalesce(b.urun_kodu,'') = coalesce(new.urun_kodu,'');

  if new.miktar < v_bagli then
    raise exception 'bagli_miktar_altina_dusurulemez: siparis %, urun %, bagli % %, istenen %',
      new.siparis_no, coalesce(new.urun_kodu,'<kodsuz>'), v_bagli, new.birim, new.miktar
      using errcode = '23514';
  end if;
  return new;
end;
$fn$;

drop trigger if exists sipk_miktar_inv on public.siparis_kalemleri;
create trigger sipk_miktar_inv before update of miktar on public.siparis_kalemleri
  for each row execute function public.sipk_miktar_inv_tetik();

-- ---------------------------------------------------------------------------
-- K5/K6: talep kalemi miktarini dusurme + bagli kalemin birim/urun degisimi
-- ---------------------------------------------------------------------------
create or replace function public.talep_kalem_inv_tetik()
returns trigger
language plpgsql
set search_path = pg_catalog, public, pg_temp
as $fn$
declare v_bagli numeric; v_var boolean;
begin
  select exists (select 1 from public.talep_siparis_baglari
                  where talep_kalem_id = new.id) into v_var;
  if not v_var then
    return new;
  end if;

  -- K6: bagli kalemde birim/urun DEGISTIRILEMEZ (hedef_birim tutarliligi).
  if new.birim is distinct from old.birim
     or new.urun_kodu is distinct from old.urun_kodu then
    raise exception 'bagli_kalem_degistirilemez: kalem % bagli; birim/urun kodu degistirilemez', new.id
      using errcode = '23514';
  end if;

  -- K5: miktar, mevcut bag toplaminin altina dusurulemez.
  if new.miktar < old.miktar then
    select coalesce(sum(b.miktar), 0) into v_bagli
      from public.talep_siparis_baglari b
      join public.siparisler s on s.siparis_no = b.siparis_no
     where b.talep_kalem_id = new.id
       and s.durum <> 'iptal'
       and b.hedef_birim = new.birim;
    if new.miktar < v_bagli then
      raise exception 'bagli_miktar_altina_dusurulemez: kalem %, bagli % %, istenen %',
        new.id, v_bagli, new.birim, new.miktar
        using errcode = '23514';
    end if;
  end if;
  return new;
end;
$fn$;

drop trigger if exists talep_kalem_miktar_inv on public.satin_alma_talep_kalemleri;
create trigger talep_kalem_miktar_inv
  before update of miktar, birim, urun_kodu on public.satin_alma_talep_kalemleri
  for each row execute function public.talep_kalem_inv_tetik();

-- ---------------------------------------------------------------------------
-- K7: bagi olan siparis SILINEMEZ (FK restrict'in okunur mesajli esi)
-- ---------------------------------------------------------------------------
create or replace function public.sip_bagli_silinemez_tetik()
returns trigger
language plpgsql
set search_path = pg_catalog, public, pg_temp
as $fn$
begin
  if exists (select 1 from public.talep_siparis_baglari
              where siparis_no = old.siparis_no) then
    raise exception 'bagli_siparis_silinemez: % talep bagi tasiyor. Silmek yerine '
      'durum=''iptal'' yapin; bag gecmisi korunur.', old.siparis_no
      using errcode = '23503';
  end if;
  return old;
end;
$fn$;

drop trigger if exists sip_bagli_silinemez on public.siparisler;
create trigger sip_bagli_silinemez before delete on public.siparisler
  for each row execute function public.sip_bagli_silinemez_tetik();

-- ---------------------------------------------------------------------------
-- INV TETIKLEYICILERI "ENABLE ALWAYS"
--
-- `session_replication_role = replica` TETIKLEYICILERI susturur ama KISITLARI
-- (check/fk/unique) susturmaz. INV bir DEGISMEZ oldugu icin kisit semantigine
-- yaklastirilir: `enable always` sayesinde replica kipinde de calisir.
-- Boylece tohumlama/fikstur yollari (denetim tetikleyicisini susturmak icin
-- replica kipi kullanirlar) INV'i ATLAYAMAZ.
-- ---------------------------------------------------------------------------
alter table public.talep_siparis_baglari       enable always trigger tsb_inv_ekle;
alter table public.talep_siparis_baglari       enable always trigger tsb_inv_guncelle;
alter table public.siparisler                  enable always trigger sip_iptal_geri_al_inv;
alter table public.siparisler                  enable always trigger sip_bagli_silinemez;
alter table public.siparis_kalemleri           enable always trigger sipk_miktar_inv;
alter table public.satin_alma_talep_kalemleri  enable always trigger talep_kalem_miktar_inv;

commit;

notify pgrst, 'reload schema';

-- ============================================================================
-- GERI ALMA  (INV korumasi kalkar — bilincli yapilmadikca onerilmez)
--   begin;
--   drop trigger if exists sip_bagli_silinemez on public.siparisler;
--   drop trigger if exists talep_kalem_miktar_inv on public.satin_alma_talep_kalemleri;
--   drop trigger if exists sipk_miktar_inv on public.siparis_kalemleri;
--   drop trigger if exists sip_iptal_geri_al_inv on public.siparisler;
--   drop trigger if exists tsb_inv_guncelle on public.talep_siparis_baglari;
--   drop trigger if exists tsb_inv_ekle on public.talep_siparis_baglari;
--   drop function if exists public.sip_bagli_silinemez_tetik();
--   drop function if exists public.talep_kalem_inv_tetik();
--   drop function if exists public.sipk_miktar_inv_tetik();
--   drop function if exists public.sip_iptal_geri_al_inv_tetik();
--   drop function if exists public.tsb_inv_tetik();
--   drop function if exists public.talep_bag_inv_kontrol(uuid, numeric, uuid);
--   commit;
-- ============================================================================
