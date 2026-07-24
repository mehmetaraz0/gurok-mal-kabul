-- F&B Bar modülü — rezervasyon mantığı RPC'leri (2026-07-22)
-- Çalıştırma: Supabase Dashboard → SQL Editor → tamamını yapıştır → Run.
begin;

-- Kullanılabilir stok = fiziksel stok − aktif rezervasyonlar
create or replace function public.bar_kullanilabilir_stok(p_stok_kodu text, p_depo_kodu text)
returns numeric
language sql stable
security definer set search_path = public
as $$
  select coalesce((select miktar from stok where urun_kodu = p_stok_kodu and depo_kodu = p_depo_kodu), 0)
       - coalesce((select sum(miktar) from stok_rezervasyonlari
                   where stok_kodu = p_stok_kodu and depo_id = p_depo_kodu and durum = 'aktif'), 0);
$$;

-- Sipariş oluştur — atomik, hard-block. Herhangi bir kalem/bileşen yetersizse
-- TÜM sipariş reddedilir (kısmi rezervasyon yok). p_kalemler formatı:
--   [{"menu_urun_id":"<uuid>","adet":2}, ...]
create or replace function public.bar_siparis_olustur(
  p_otel_id text, p_depo_id text, p_masa_token text, p_oda_no text, p_kalemler jsonb
) returns uuid
language plpgsql
security definer set search_path = public
as $$
declare
  v_siparis_id uuid;
  v_kalem jsonb;
  v_menu menu_urunler%rowtype;
  v_kalem_id uuid;
  v_bilesen record;
  v_gerekli numeric;
  v_musait numeric;
begin
  -- GUARD: boş sepet reddedilir (sipariş satırı bile oluşmaz)
  if p_kalemler is null or jsonb_array_length(p_kalemler) = 0 then
    raise exception 'Boş sipariş: en az bir kalem gerekli';
  end if;

  insert into bar_siparisleri (otel_id, depo_id, masa_token, oda_no, durum)
  values (p_otel_id::otel_id, p_depo_id, p_masa_token, p_oda_no, 'yeni')
  returning id into v_siparis_id;

  for v_kalem in select * from jsonb_array_elements(p_kalemler)
  loop
    select * into v_menu from menu_urunler
      where id = (v_kalem->>'menu_urun_id')::uuid and aktif = true and silindi = false;
    if not found then
      raise exception 'Menü ürünü bulunamadı/pasif: %', v_kalem->>'menu_urun_id';
    end if;

    insert into bar_siparis_kalemleri (siparis_id, menu_urun_id, adet, rezerve_edildi)
    values (v_siparis_id, v_menu.id, (v_kalem->>'adet')::numeric, true)
    returning id into v_kalem_id;

    if v_menu.tip = 'direkt' then
      v_gerekli := (v_kalem->>'adet')::numeric * coalesce(v_menu.miktar_per_porsiyon, 1);
      v_musait := bar_kullanilabilir_stok(v_menu.stok_kodu, p_depo_id);
      if v_musait < v_gerekli then
        raise exception 'Yetersiz stok: % (gerekli %, müsait %)', v_menu.stok_kodu, v_gerekli, v_musait;
      end if;
      insert into stok_rezervasyonlari (stok_kodu, otel_id, depo_id, miktar, siparis_kalem_id, durum)
      values (v_menu.stok_kodu, p_otel_id::otel_id, p_depo_id, v_gerekli, v_kalem_id, 'aktif');
    else
      for v_bilesen in select * from recete_bilesenleri where menu_urun_id = v_menu.id
      loop
        v_gerekli := (v_kalem->>'adet')::numeric * v_bilesen.miktar_per_porsiyon;
        v_musait := bar_kullanilabilir_stok(v_bilesen.stok_kodu, p_depo_id);
        if v_musait < v_gerekli then
          raise exception 'Yetersiz stok (reçete): % (gerekli %, müsait %)', v_bilesen.stok_kodu, v_gerekli, v_musait;
        end if;
        insert into stok_rezervasyonlari (stok_kodu, otel_id, depo_id, miktar, siparis_kalem_id, durum)
        values (v_bilesen.stok_kodu, p_otel_id::otel_id, p_depo_id, v_gerekli, v_kalem_id, 'aktif');
      end loop;
    end if;
  end loop;

  return v_siparis_id;
end;
$$;

-- Teslim et: aktif rezervasyonları kesin stok düşümüne çevir
create or replace function public.bar_siparis_teslim_et(p_siparis_id uuid)
returns void
language plpgsql
security definer set search_path = public
as $$
declare
  v_rez record;
begin
  if not auth_yetki_var('bar_siparis_yonetimi','kayit') then
    raise exception 'Yetki yok: bar_siparis_yonetimi kayıt gerekli';
  end if;
  for v_rez in
    select r.* from stok_rezervasyonlari r
    join bar_siparis_kalemleri k on k.id = r.siparis_kalem_id
    where k.siparis_id = p_siparis_id and r.durum = 'aktif'
  loop
    perform stok_ekle(v_rez.stok_kodu, v_rez.depo_id, v_rez.otel_id::text, -v_rez.miktar);
    update stok_rezervasyonlari set durum = 'kullanildi' where id = v_rez.id;
  end loop;
  update bar_siparis_kalemleri set teslim_edildi = true where siparis_id = p_siparis_id;
  update bar_siparisleri set durum = 'teslim_edildi' where id = p_siparis_id;
end;
$$;

-- İptal: aktif rezervasyonları serbest bırak (stok düşmez)
create or replace function public.bar_siparis_iptal(p_siparis_id uuid)
returns void
language plpgsql
security definer set search_path = public
as $$
begin
  if not auth_yetki_var('bar_siparis_yonetimi','kayit') then
    raise exception 'Yetki yok: bar_siparis_yonetimi kayıt gerekli';
  end if;
  update stok_rezervasyonlari r set durum = 'serbest'
    from bar_siparis_kalemleri k
    where k.id = r.siparis_kalem_id and k.siparis_id = p_siparis_id and r.durum = 'aktif';
  update bar_siparisleri set durum = 'iptal' where id = p_siparis_id;
end;
$$;

-- Durum güncelle: yeni→hazirlaniyor→hazir (stok etkisi yok)
create or replace function public.bar_siparis_durum_guncelle(p_siparis_id uuid, p_durum public.bar_durum)
returns void
language plpgsql
security definer set search_path = public
as $$
begin
  if not auth_yetki_var('bar_siparis_yonetimi','kayit') then
    raise exception 'Yetki yok: bar_siparis_yonetimi kayıt gerekli';
  end if;
  if p_durum not in ('hazirlaniyor','hazir') then
    raise exception 'Bu fonksiyon yalnız hazirlaniyor/hazir için — teslim/iptal ayrı RPC';
  end if;
  update bar_siparisleri set durum = p_durum where id = p_siparis_id;
end;
$$;

-- İzinler
revoke all on function public.bar_siparis_olustur(text,text,text,text,jsonb) from public;
grant execute on function public.bar_siparis_olustur(text,text,text,text,jsonb) to anon, authenticated;
grant execute on function public.bar_kullanilabilir_stok(text,text) to anon, authenticated;
grant execute on function public.bar_siparis_teslim_et(uuid) to authenticated;
grant execute on function public.bar_siparis_iptal(uuid) to authenticated;
grant execute on function public.bar_siparis_durum_guncelle(uuid, public.bar_durum) to authenticated;

commit;
