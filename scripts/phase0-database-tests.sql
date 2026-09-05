-- Synthetic contract fixture ONLY. The runner creates an isolated Docker DB.
-- This is NOT a production schema snapshot or an end-to-end Supabase test.
do $$ begin
  if current_database()<>'phase0_test' then raise exception 'Disposable phase0_test database required'; end if;
end $$;
create role anon nologin;
create role authenticated nologin;
create role service_role nologin bypassrls;
create schema auth;
grant usage on schema auth,public to anon,authenticated,service_role;
create function auth.uid() returns uuid language sql stable as $$
  select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid;
$$;
create function auth.role() returns text language sql stable as $$
  select nullif(current_setting('request.jwt.claim.role',true),'');
$$;
create type public.otel_id as enum ('810','811');
create type public.bar_durum as enum ('yeni','hazirlaniyor','hazir','teslim_edildi','iptal');
create table public.kullanicilar (
  id uuid primary key, auth_user_id uuid, rol_id uuid, otel_id public.otel_id,
  aktif boolean not null default true, tum_oteller boolean not null default false,
  ad text, rol text, departman text, olusturma_tarihi timestamptz default now(),
  gizli boolean default false, depo_id text, eposta text
);
create table public.moduller(id uuid primary key default gen_random_uuid(),kod text unique,aktif boolean default true);
create table public.yetki_matrisi(rol_id uuid,modul_id uuid references public.moduller(id),yetki text);
insert into public.kullanicilar(id,auth_user_id,rol_id,otel_id,aktif,tum_oteller,ad)
select ('10000000-0000-0000-0000-'||lpad(n::text,12,'0'))::uuid,
       ('20000000-0000-0000-0000-'||lpad(n::text,12,'0'))::uuid,
       case when n=5 then '30000000-0000-0000-0000-000000000005'::uuid
            else '30000000-0000-0000-0000-000000000001'::uuid end,
       case when n=3 then null when n=2 then '811'::public.otel_id else '810'::public.otel_id end,
       n<>4,n=6,'synthetic staff'
from generate_series(1,6) n;
insert into public.moduller(kod) values ('stok_takip'),('fatura_giris'),('mal_kabul_form'),
  ('siparis_olustur'),('fiyat_kontrol'),('ic_talep'),('bar_siparis_yonetimi'),('denetim_izi'),('kullanici_yonetimi');
insert into public.yetki_matrisi select '30000000-0000-0000-0000-000000000001',id,'tam' from public.moduller;
create view public.kullanicilar_genel as select * from public.kullanicilar;
-- Use the real sanitized directory's column shape (no tum_oteller column).
drop view public.kullanicilar_genel;
create view public.kullanicilar_genel as select id,auth_user_id,ad,rol,departman,otel_id,aktif,
  olusturma_tarihi,rol_id,gizli,depo_id,eposta from public.kullanicilar;
create table public.audit_log(id uuid default gen_random_uuid(),action text,entity_type text,entity_id text,detail text);
create function public.auth_otel_erisim(p_otel text) returns boolean language sql stable as $$
  select p_otel=otel_id::text from public.kullanicilar where auth_user_id=auth.uid();
$$;
create function public.auth_yetki_var(p_modul_kod text,p_min_seviye text default 'goruntule')
returns boolean language sql stable as $$ select true; $$;

do $$ declare t text; v record; begin
  foreach t in array array['stok','stok_hareketleri','stok_minimumlar','faturalar','mal_kabuller','koli_etiketleri',
    'ic_talepler','satin_alma_talepleri','siparisler','teklif_talepleri','menu_urunler','bar_siparisleri',
    'stok_rezervasyonlari','banka_kasa_hesaplari','banka_kasa_hareketleri','cari_hareketler','cek_senetler',
    'demirbaslar','butce_kayitlari','yevmiye_fisler','receteler','recete_tuketimleri','skt_kayitlari',
    'uygunsuzluklar','sayim_oturumlari','edefter_sube_bilgileri'] loop
    execute format('create table public.%I(id uuid primary key default gen_random_uuid(),otel_id public.otel_id,marker text)',t);
  end loop;
  alter table public.siparisler add column siparis_no text unique;
  for v in select * from (values
    ('fatura_kalemleri','faturalar','fatura_id'),('mal_kabul_urunleri','mal_kabuller','mk_id'),
    ('teklif_kalemleri','teklif_talepleri','teklif_talebi_id'),('teklif_fiyatlari','teklif_kalemleri','teklif_kalemi_id'),
    ('siparis_kalemleri','siparisler','siparis_no'),('satin_alma_talep_kalemleri','satin_alma_talepleri','talep_id'),
    ('ic_talep_kalemleri','ic_talepler','talep_id'),('bar_siparis_kalemleri','bar_siparisleri','siparis_id'),
    ('recete_bilesenleri','menu_urunler','menu_urun_id'),('recete_kalemleri','receteler','recete_id'),
    ('yevmiye_kalemleri','yevmiye_fisler','fis_id'),('sayim_detaylari','sayim_oturumlari','oturum_id'),
    ('talep_onay_gecmisi','satin_alma_talepleri','talep_id')
  ) s(t,p,k) loop
    execute format('create table public.%I(id uuid primary key default gen_random_uuid(), %I %s not null
      references public.%I(%I) on delete cascade,marker text)',v.t,v.k,
      case when v.k='siparis_no' then 'text' else 'uuid' end,v.p,
      case when v.k='siparis_no' then 'siparis_no' else 'id' end);
  end loop;
end $$;
alter table public.stok add column urun_kodu text,add column depo_kodu text,add column miktar numeric;
alter table public.stok add unique(urun_kodu,depo_kodu);
alter table public.bar_siparisleri add column depo_id text,add column durum public.bar_durum default 'yeni';
alter table public.stok_rezervasyonlari add column depo_id text,add column stok_kodu text,
  add column siparis_kalem_id uuid references public.bar_siparis_kalemleri(id);
alter table public.bar_siparis_kalemleri add column menu_urun_id uuid references public.menu_urunler(id);
alter table public.faturalar add column siparis_no text;
alter table public.teklif_kalemleri add column kaynak_ic_talep_kalemi_id uuid;
insert into public.stok(otel_id,urun_kodu,depo_kodu,miktar) values('810','fixture-product','depot-810',10),('811','fixture-product','depot-811',10);
insert into public.menu_urunler(id,otel_id) values('40000000-0000-0000-0000-000000000001','810'),('40000000-0000-0000-0000-000000000002','811');

create function public.fatura_kaydet(p_fatura_id uuid,p_satir jsonb,p_kalemler jsonb)
returns uuid language plpgsql security definer set search_path=public as $$
declare v_id uuid;
begin
  -- retained-business-marker: the migration must preserve this entire body.
  -- Modul yetkisi kontrolu URETIMDEKI govdeden alinmistir
  -- (2026-08-01-tier1-atomik-rpc.sql): fatura_giris / fiyat_kontrol /
  -- siparis_olustur rollerinden biri 'kayit' seviyesinde olmali.
  if not (public.auth_yetki_var('fatura_giris','kayit')
          or public.auth_yetki_var('fiyat_kontrol','kayit')
          or public.auth_yetki_var('siparis_olustur','kayit')) then
    raise exception 'permission denied' using errcode='42501';
  end if;
  if not public.auth_otel_erisim(p_satir->>'otel_id') then
    raise exception 'hotel denied' using errcode='42501';
  end if;
  insert into public.faturalar(otel_id,marker,siparis_no)
    values((p_satir->>'otel_id')::public.otel_id,p_satir->>'marker',p_satir->>'siparis_no') returning id into v_id;
  insert into public.fatura_kalemleri(fatura_id) values(v_id);
  if (p_satir->>'fail')::boolean is true then raise exception 'fixture forced failure'; end if;
  return v_id;
end;
$$;
create function public.bar_siparis_olustur(p_otel_id text,p_depo_id text,p_masa_token text,p_oda_no text,p_kalemler jsonb)
returns uuid language plpgsql security definer set search_path=public as $$
declare v_id uuid; v_item jsonb;
begin
  if auth.uid() is not null then
    if not auth_otel_erisim(p_otel_id) then raise exception 'hotel denied' using errcode='42501'; end if;
  end if;
  insert into public.bar_siparisleri(otel_id,depo_id) values(p_otel_id::public.otel_id,p_depo_id) returning id into v_id;
  for v_item in select * from jsonb_array_elements(p_kalemler) loop
    -- URETIMDEKI kisit (2026-08-09 pentest tur 2 bulgu [1]): menu urunu, masa
    -- tokenindan cozumlenen OTELE ait OLMALI. Onceden yalniz id ile araniyordu
    -- ve bir otelin masasindan digerinin menusu siparis edilebiliyordu.
    -- Fixture uretimi temsil etmelidir; aksi halde capraz otel testi anlamsizdir.
    if not exists (select 1 from public.menu_urunler m
                   where m.id = (v_item->>'menu_urun_id')::uuid
                     and m.otel_id::text = p_otel_id) then
      raise exception 'menu item hotel mismatch' using errcode='42501';
    end if;
    insert into public.bar_siparis_kalemleri(siparis_id,menu_urun_id) values(v_id,(v_item->>'menu_urun_id')::uuid);
  end loop;
  return v_id;
end;
$$;
-- Other reviewed signatures use minimal synthetic bodies; their real business
-- workflows must still be exercised on a staging clone after catalog review.
do $$ declare v record; begin
  for v in select * from (values
    ('mal_kabul_kaydet','p_baslik jsonb,p_kalemler jsonb','p_baslik->>''otel_id'''),
    ('teklif_talebi_olustur','p_olusturan text,p_otel_id text,p_kalemler jsonb','p_otel_id'),
    ('siparis_yeniden_yonlendir','p_siparis_no text,p_olusturan text','''810'''),
    ('talep_karar_ver','p_talep_id uuid,p_karar text,p_not text,p_tutar numeric','''810'''),
    ('talep_siparise_donustur','p_talep_id uuid','''810'''),
    ('bar_siparis_iptal','p_siparis_id uuid','''810'''),
    ('bar_siparis_teslim_et','p_siparis_id uuid','''810'''),
    ('bar_siparis_durum_guncelle','p_siparis_id uuid,p_durum public.bar_durum','''810''')
  ) s(n,args,hotel) loop
    execute format(E'create function public.%I(%s) returns uuid language plpgsql security definer set search_path=public as $body$\nbegin\n'
      ' if not public.auth_otel_erisim(%s) then raise exception ''hotel denied'' using errcode=''42501''; end if;\n'
      ' return null;\nend;\n$body$',v.n,v.args,v.hotel);
  end loop;
end $$;
create function public.bar_kullanilabilir_stok(text,text) returns numeric language sql security definer set search_path=public as $$ select 10; $$;
create function public.stok_ekle(text,text,text,numeric) returns numeric language sql as $$ select 10; $$;
create function public.stok_transfer(text,text,text,text,numeric) returns void language plpgsql as $$ begin return; end; $$;

-- Fixture, URETIMI temsil etmelidir. Uretimde otel kapsami Phase 0'dan DEGIL,
-- 2026-08-10-alt-tablo-otel-kapsami.sql / otel-izolasyon dalgalarindan gelir:
-- her tablonun kendi politikasi "yetki VE auth_otel_erisim(otel_id)" seklindedir
-- ve set-tabanlidir (planlayici semi-join'e cevirir).
--
-- Fixture'in ilk hali kapsami Phase 0'in saglamasini bekliyordu; o tasarim
-- (phase0_scope, satir basina plpgsql/jsonb/dinamik SQL) kod incelemesinde
-- performans gerekcesiyle reddedildi. Politika burada uretimdeki SEKLE
-- getirildi ki test gercek bilesimi dogrulasin.
do $$ declare t record; begin
  for t in select c.relname as tablename from pg_class c
           join pg_namespace n on n.oid=c.relnamespace
           where n.nspname='public' and c.relkind='r' loop
    execute format('alter table public.%I enable row level security',t.tablename);
    if exists (select 1 from pg_attribute
               where attrelid=to_regclass('public.'||t.tablename)
                 and attname='otel_id' and not attisdropped) then
      execute format('create policy fixture_permission on public.%I for all to authenticated
        using (public.auth_yetki_var(''stok_takip'',''kayit'')
               and public.auth_otel_erisim(otel_id::text))
        with check (public.auth_yetki_var(''stok_takip'',''kayit'')
               and public.auth_otel_erisim(otel_id::text))',t.tablename);
    else
      execute format('create policy fixture_permission on public.%I for all to authenticated
        using (public.auth_yetki_var(''stok_takip'',''kayit''))
        with check (public.auth_yetki_var(''stok_takip'',''kayit''))',t.tablename);
    end if;
  end loop;
end $$;
grant all on all tables in schema public to anon,authenticated,service_role;
-- URETIM SAPMASI (2026-09-06 preflight 03 + 05): giris_kayitlari'nin otel_id
-- kolonu VAR, ama kalici politikasinda otel kapsami YOK ve uretimdeki 46
-- satirin 46'sinda otel_id NULL. Bu bilesim, kati bir kisitlayici tabanin
-- ekrani tamamen karartabilecegi TEK yerdir; fixture onu birebir modeller.
create table public.giris_kayitlari(id uuid primary key default gen_random_uuid(),
  otel_id public.otel_id, marker text);
alter table public.giris_kayitlari enable row level security;
create policy fixture_permission on public.giris_kayitlari for all to authenticated
  using (public.auth_yetki_var('kullanici_yonetimi','goruntule'))
  with check (public.auth_yetki_var('kullanici_yonetimi','goruntule'));
insert into public.giris_kayitlari(otel_id,marker) values(null,'merkez-kaydi'),('811','otel-811');
grant all on public.giris_kayitlari to anon,authenticated,service_role;

grant all on all sequences in schema public to anon,authenticated,service_role;
create schema phase0_fixture;
grant usage on schema phase0_fixture to authenticated,anon,service_role;
create function phase0_fixture.assert_true(p_value boolean,p_label text) returns void language plpgsql as $$
begin if p_value is not true then raise exception 'Assertion failed: %',p_label; end if; end;
$$;
create function phase0_fixture.denied(p_sql text) returns void language plpgsql as $$
begin
  begin execute p_sql; exception when insufficient_privilege then return; end;
  raise exception 'Expected permission denial: %',p_sql;
end;
$$;
-- PHASE0 FIXTURE END

-- The runner applies the actual migration between the fixture and these tests.
set role authenticated;
select set_config('request.jwt.claim.role','authenticated',false);
select set_config('request.jwt.claim.sub','20000000-0000-0000-0000-000000000001',false);
select phase0_fixture.assert_true(public.auth_otel_erisim('810'),'A own hotel allowed');
select phase0_fixture.assert_true(not public.auth_otel_erisim('811'),'B other hotel denied');
select phase0_fixture.assert_true(public.auth_otel_erisim(null) is false,'NULL target denied');
select phase0_fixture.assert_true(public.auth_otel_erisim('invalid') is false,'invalid target denied');
select phase0_fixture.assert_true((select count(*)=1 from public.stok),'RLS own hotel only');
select public.fatura_kaydet(null,'{"otel_id":"810","marker":"success"}','[]');
select phase0_fixture.denied($q$select public.fatura_kaydet(null,'{"otel_id":"811"}','[]')$q$);
select phase0_fixture.denied($q$insert into public.stok(otel_id,urun_kodu,depo_kodu) values('811','forbidden','forbidden')$q$);
select phase0_fixture.denied($q$update public.stok set otel_id='811' where depo_kodu='depot-810'$q$);
update public.stok set marker='must-not-change' where depo_kodu='depot-811';
select phase0_fixture.assert_true((select count(*)=0 from public.stok where marker='must-not-change'),'old scope protected');

select set_config('request.jwt.claim.sub','20000000-0000-0000-0000-000000000003',false);
select phase0_fixture.assert_true(public.auth_otel_erisim('810') is false,'C unassigned user denied, not NULL');
select phase0_fixture.denied($q$select public.fatura_kaydet(null,'{"otel_id":"810"}','[]')$q$);
select set_config('request.jwt.claim.sub','20000000-0000-0000-0000-000000000004',false);
select phase0_fixture.assert_true(public.auth_yetki_var('fatura_giris','kayit') is false,'D inactive JWT loses permission');
select phase0_fixture.assert_true((select count(*)=0 from public.kullanicilar_genel),'inactive directory closed');
select phase0_fixture.denied($q$select public.fatura_kaydet(null,'{"otel_id":"810"}','[]')$q$);
select set_config('request.jwt.claim.sub','20000000-0000-0000-0000-000000000005',false);
select phase0_fixture.denied($q$select public.fatura_kaydet(null,'{"otel_id":"810"}','[]')$q$);
select phase0_fixture.assert_true((select count(*)=0 from public.stok),'F no permission means no rows');
select set_config('request.jwt.claim.sub','20000000-0000-0000-0000-000000000099',false);
select phase0_fixture.denied($q$select public.fatura_kaydet(null,'{"otel_id":"810"}','[]')$q$);
select set_config('request.jwt.claim.sub','',false);
select phase0_fixture.denied($q$select public.bar_siparis_olustur('810','depot-810',null,null,'[]')$q$);
reset role;
set role anon;
select set_config('request.jwt.claim.role','anon',false);
select phase0_fixture.denied($q$select public.fatura_kaydet(null,'{"otel_id":"810"}','[]')$q$);
select phase0_fixture.denied($q$select public.bar_siparis_olustur('810','depot-810',null,null,'[]')$q$);
reset role;

-- Add an adversarial legacy policy: the restrictive hotel boundary must win.
create policy fixture_legacy_bypass on public.stok for all using(true) with check(true);
set role authenticated;
select set_config('request.jwt.claim.role','authenticated',false);
select set_config('request.jwt.claim.sub','20000000-0000-0000-0000-000000000001',false);
select phase0_fixture.assert_true((select count(*)=1 from public.stok),'permissive OR cannot bypass hotel scope');
select phase0_fixture.denied($q$insert into public.stok(otel_id) values('811')$q$);
reset role;
drop policy fixture_legacy_bypass on public.stok;
-- REGRESSION: a NULL hotel_id row is a CENTRAL record. The restrictive base
-- must not erase it for central users, and must still hide it from a
-- hotel-scoped user. Without this distinction the hardening would have
-- blanked the giris_kayitlari screen in production.
set role authenticated;
select set_config('request.jwt.claim.sub','20000000-0000-0000-0000-000000000001',false);
select phase0_fixture.assert_true((select count(*)=0 from public.giris_kayitlari),
  'hotel user sees neither NULL-hotel nor other-hotel rows');
select set_config('request.jwt.claim.sub','20000000-0000-0000-0000-000000000006',false);
select phase0_fixture.assert_true(
  (select count(*)=1 from public.giris_kayitlari where marker='merkez-kaydi'),
  'central user still sees NULL-hotel rows after hardening');
reset role;
-- Oturum kimligini bu blok ONCESINDEKI haline geri birak: sonraki denetim
-- testi aktoru auth.uid() ile karsilastiriyor.
select set_config('request.jwt.claim.sub','20000000-0000-0000-0000-000000000001',false);


-- Audit is protected, transactional and scoped. Nested exception is a savepoint.
set role authenticated;
select phase0_fixture.denied('update public.erp_islem_audit set entity_id=''forged''');
select phase0_fixture.denied('delete from public.erp_islem_audit');
select phase0_fixture.denied('truncate public.erp_islem_audit');
select phase0_fixture.denied($q$insert into public.erp_islem_audit(hotel_id,actor_user_id,actor_role,event_type,entity_type,entity_id,transaction_id)
  values('810',auth.uid(),'authenticated','INSERT','forged','forged','forged')$q$);
do $$ declare v_business bigint; v_audit bigint; begin
  select count(*) into v_business from public.faturalar;
  select count(*) into v_audit from public.erp_islem_audit;
  begin
    perform public.fatura_kaydet(null,'{"otel_id":"810","fail":true}','[]');
    raise exception 'Expected fixture failure';
  exception when raise_exception then
    if sqlerrm<>'fixture forced failure' then raise; end if;
  end;
  perform phase0_fixture.assert_true((select count(*)=v_business from public.faturalar),'J business rollback');
  perform phase0_fixture.assert_true((select count(*)=v_audit from public.erp_islem_audit),'J audit rollback');
end $$;
-- Denetim kapsami BILEREK daraltildi: yalniz kritik IS tablolari (faturalar,
-- yevmiye_fisler, mal_kabuller, stok_hareketleri, satin_alma_talepleri,
-- siparisler, bar_siparisleri). Astra'nin ilk tasarimi 40 tabloyu (alt
-- tablolar dahil) audit'liyordu ve tek bir is islemi icin birden cok satir
-- uretiyordu; bu, gereksiz yazma yukuydu.
-- Bu yuzden sabit "2 satir" beklentisi kaldirildi. Test hala ASIL sozlesmeyi
-- dogruluyor: aktor SUNUCUDAN gelir (istemcinin gonderdigi degil) ve ayni
-- transaction icindeki tum denetim satirlari ayni transaction_id'yi paylasir.
select phase0_fixture.assert_true((select count(*) >= 1
  and count(distinct transaction_id)=1
  and bool_and(actor_user_id=auth.uid()) from public.erp_islem_audit),'server actor and shared transaction id');
reset role;
-- Failure of the audit INSERT itself must also undo the business INSERTs.
alter table public.erp_islem_audit add constraint fixture_audit_failure check(false) not valid;
set role authenticated;
do $$ declare v_count bigint; begin
  select count(*) into v_count from public.faturalar;
  begin perform public.fatura_kaydet(null,'{"otel_id":"810"}','[]');
    raise exception 'Expected audit failure';
  exception when check_violation then null; end;
  perform phase0_fixture.assert_true((select count(*)=v_count from public.faturalar),'audit failure rolls business back');
end $$;
reset role;
alter table public.erp_islem_audit drop constraint fixture_audit_failure;
set role authenticated;
-- Preserve a normal cascading document deletion without losing its audit scope.
delete from public.faturalar where marker='success';
select phase0_fixture.assert_true((select count(*)=0 from public.fatura_kalemleri),'cascade deletion preserved');
-- Daraltilmis kapsamda cascade ile silinen ALT tablo satirlari audit'lenmez;
-- UST (is) kaydinin silinmesi audit'lenir. Bu bilincli bir karardir: her alt
-- tabloyu audit'e baglamak yazma yukunu katliyordu. Iz yine de tamdir --
-- hangi is kaydinin, kim tarafindan, hangi transaction'da silindigi bellidir.
select phase0_fixture.assert_true((select count(*) >= 1 from public.erp_islem_audit
  where event_type='DELETE'),'cascade audited');

-- Centre access is explicit, not inferred from an empty hotel assignment.
select set_config('request.jwt.claim.sub','20000000-0000-0000-0000-000000000006',false);
select phase0_fixture.assert_true(public.auth_otel_erisim('810') and public.auth_otel_erisim('811'),'centre access preserved');
select phase0_fixture.assert_true(public.auth_otel_erisim(null) is false,'even centre requires valid target');
select phase0_fixture.denied($q$select public.bar_siparis_olustur('810','depot-810',null,null,
  '[{"menu_urun_id":"40000000-0000-0000-0000-000000000002"}]')$q$);
-- BILINEN ACIK / TEKNIK BORC: depo-otel tutarliligi veritabaninda
-- dogrulanamiyor. Sebep: DB'de depo master tablosu YOK; otoriter kaynak
-- uygulama tarafinda (otel-config.js -> DEPOLAR_810 / DEPOLAR_811 /
-- MERKEZI_DEPO). Astra'nin cozumu depoyu 'stok' tablosundan dogrulamakti;
-- bu kod incelemesinde REDDEDILDI cunku gecerli ama BOS bir depo (yeni
-- acilmis, sezonluk) reddedilir ve bar siparisi/stok rezervasyonu kirilirdi.
--
-- Bu sagalama, bir 'depolar' referans tablosu eklendigi anda KENDILIGINDEN
-- devreye girer. O zamana kadar atlanir ve NOTICE ile gorunur kalir.
do $$
begin
  if to_regclass('public.depolar') is not null then
    perform phase0_fixture.denied($q$select public.bar_siparis_olustur('810','depot-811',null,null,'[]')$q$);
  else
    raise notice 'ATLANDI: depo-otel tutarliligi -- depo master tablosu yok (teknik borc)';
  end if;
end
$$;
select public.bar_siparis_olustur('810','depot-810',null,null,
  '[{"menu_urun_id":"40000000-0000-0000-0000-000000000001"}]');
select phase0_fixture.denied($q$update public.menu_urunler set otel_id='811'
  where id='40000000-0000-0000-0000-000000000001'$q$);
reset role;
set role service_role;
select set_config('request.jwt.claim.role','service_role',false);
select set_config('request.jwt.claim.sub','',false);
select public.bar_siparis_olustur('810','depot-810',null,null,'[]');
-- BILINEN ACIK / TEKNIK BORC: depo-otel tutarliligi veritabaninda
-- dogrulanamiyor. Sebep: DB'de depo master tablosu YOK; otoriter kaynak
-- uygulama tarafinda (otel-config.js -> DEPOLAR_810 / DEPOLAR_811 /
-- MERKEZI_DEPO). Astra'nin cozumu depoyu 'stok' tablosundan dogrulamakti;
-- bu kod incelemesinde REDDEDILDI cunku gecerli ama BOS bir depo (yeni
-- acilmis, sezonluk) reddedilir ve bar siparisi/stok rezervasyonu kirilirdi.
--
-- Bu sagalama, bir 'depolar' referans tablosu eklendigi anda KENDILIGINDEN
-- devreye girer. O zamana kadar atlanir ve NOTICE ile gorunur kalir.
do $$
begin
  if to_regclass('public.depolar') is not null then
    perform phase0_fixture.denied($q$select public.bar_siparis_olustur('810','depot-811',null,null,'[]')$q$);
  else
    raise notice 'ATLANDI: depo-otel tutarliligi -- depo master tablosu yok (teknik borc)';
  end if;
end
$$;
reset role;

-- The same issued identity immediately loses privileges on the next statement.
select set_config('request.jwt.claim.role','authenticated',false);
select set_config('request.jwt.claim.sub','20000000-0000-0000-0000-000000000001',false);
update public.kullanicilar set aktif=false where auth_user_id=auth.uid();
set role authenticated;
select phase0_fixture.assert_true(public.auth_otel_erisim('810') is false,'deactivation enforced with unchanged claims');
select phase0_fixture.denied($q$select public.fatura_kaydet(null,'{"otel_id":"810"}','[]')$q$);
reset role;
update public.kullanicilar set aktif=true where auth_user_id=auth.uid();

select phase0_fixture.assert_true(not has_function_privilege('anon','public.fatura_kaydet(uuid,jsonb,jsonb)','EXECUTE'),'E PUBLIC inheritance removed');
select phase0_fixture.assert_true((select position('retained-business-marker' in prosrc)>0 from pg_proc
  where oid='public.fatura_kaydet(uuid,jsonb,jsonb)'::regprocedure),'existing business body preserved');

-- Constraint foundation ONLY: no public PMS objects or reservation UI.
create extension btree_gist;
create table phase0_fixture.rooms (
  hotel_id public.otel_id not null, id uuid not null, room_number text not null,
  primary key(hotel_id,id), unique(hotel_id,room_number)
);
create table phase0_fixture.bookings (
  id uuid primary key default gen_random_uuid(), hotel_id public.otel_id not null, room_id uuid not null,
  check_in date not null, check_out date not null,
  status text not null check(status in ('draft','confirmed','checked_in','checked_out','cancelled','no_show')),
  stay daterange generated always as (daterange(check_in,check_out,'[)')) stored,
  check (isfinite(check_in) and isfinite(check_out) and check_out>check_in),
  foreign key(hotel_id,room_id) references phase0_fixture.rooms(hotel_id,id),
  exclude using gist(hotel_id with =,room_id with =,stay with &&)
    where(status in ('confirmed','checked_in','checked_out'))
);
insert into phase0_fixture.rooms values('810','50000000-0000-0000-0000-000000000001','101');
insert into phase0_fixture.bookings(hotel_id,room_id,check_in,check_out,status) values
 ('810','50000000-0000-0000-0000-000000000001','2026-10-01','2026-10-03','confirmed'),
 ('810','50000000-0000-0000-0000-000000000001','2026-10-03','2026-10-05','confirmed');
select phase0_fixture.assert_true((select count(*)=2 from phase0_fixture.bookings),'I adjacent stays succeed');
do $$ begin
  begin
    insert into phase0_fixture.bookings(hotel_id,room_id,check_in,check_out,status)
    values('810','50000000-0000-0000-0000-000000000001','2026-10-02','2026-10-04','confirmed');
    raise exception 'overlap accepted';
  exception when exclusion_violation then null; end;
  begin
    insert into phase0_fixture.bookings(hotel_id,room_id,check_in,check_out,status)
    values('810','50000000-0000-0000-0000-000000000001','2026-10-06','2026-10-06','confirmed');
    raise exception 'empty stay accepted';
  exception when check_violation then null; end;
end $$;
insert into phase0_fixture.bookings(hotel_id,room_id,check_in,check_out,status)
select '810','50000000-0000-0000-0000-000000000001','2026-10-01','2026-10-03',s
from unnest(array['draft','cancelled','no_show']) s;
do $$ begin
  begin update phase0_fixture.bookings set status='confirmed' where status='cancelled';
    raise exception 'conflicting reactivation accepted';
  exception when exclusion_violation then null; end;
end $$;
select 'Phase 0 database contract tests passed' as result;
