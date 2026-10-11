// Talep -> siparis testleri icin PAYLASILAN fikstur.
// Tetikleyiciler kapaliyken kurulur: phase0_islem_audit kimliksiz yazmayi
// reddeder, fikstur ise kimlik kurmadan once calisir.
//
// Siparis numaralari SABIT ('C00000001'/'C00000002'): fikstur determinist
// olmali ve `siparis_no_uret` davranisina bagimli hale gelmemeli.
export const U_TEST = '11111111-0000-0000-0000-00000000b001';
// IKINCI KIMLIK: yalniz `ic_talep:kayit`. Siparis modulunde HIC yetkisi yok.
// Varlik sebebi olculdu: kapi testleri postgres superuser olarak kostugu icin
// RLS'i atliyordu ve RLS altinda SESSIZCE atlanan kapilar gorunmuyordu.
export const U_TALEP = '11111111-0000-0000-0000-00000000b002';

export function kurFikstur(O, { otel = '810', talepDurum = 'onaylandi' } = {}) {
  const TALEP = 'bbbbbbbb-0000-0000-0000-00000000b001';
  const KALEM = 'bbbbbbbb-0000-0000-0000-00000000b011';
  const KALEM2 = 'bbbbbbbb-0000-0000-0000-00000000b012';
  const URUN = 'TEST-BAG-001';

  const r = O.sql(`set session_replication_role = replica;
    insert into public.moduller (kod, ad, kategori, sira, aktif) values
      ('siparis_olustur','Siparis Olustur','satinalma',10,true),
      ('siparis_takip','Siparis Takip','satinalma',11,true),
      ('ic_talep','Ic Talepler','satinalma',12,true),
      ('stok_takip','Stok Takip','depo',13,true)
      on conflict (kod) do nothing;
    insert into public.roller (id, ad, seviye, kod, sira)
      values ('00000000-0000-0000-0000-00000000f001','Satinalma','otel','satinalma_test',30)
      on conflict do nothing;
    insert into public.yetki_matrisi (rol_id, modul_id, yetki)
    select r.id, m.id, 'kayit'::public.yetki_seviye
      from public.roller r join public.moduller m on m.kod in ('siparis_olustur','siparis_takip')
     where r.kod='satinalma_test'
      on conflict (rol_id, modul_id) do nothing;
    insert into auth.users (id, email) values ('${U_TEST}','bag@test.local')
      on conflict (id) do nothing;
    insert into public.kullanicilar (id, auth_user_id, ad, rol, otel_id, aktif, rol_id)
    select gen_random_uuid(), '${U_TEST}'::uuid, 'Bag Test', 'muhasebe_calisani', '${otel}', true, r.id
      from public.roller r where r.kod='satinalma_test'
      on conflict do nothing;

    insert into public.roller (id, ad, seviye, kod, sira)
      values ('00000000-0000-0000-0000-00000000f002','Talep Only','otel','talep_test',31)
      on conflict do nothing;
    insert into public.yetki_matrisi (rol_id, modul_id, yetki)
    select r.id, m.id, 'kayit'::public.yetki_seviye
      from public.roller r join public.moduller m on m.kod in ('ic_talep','stok_takip')
     where r.kod='talep_test'
      on conflict (rol_id, modul_id) do nothing;
    insert into auth.users (id, email) values ('${U_TALEP}','talep@test.local')
      on conflict (id) do nothing;
    insert into public.kullanicilar (id, auth_user_id, ad, rol, otel_id, aktif, rol_id)
    select gen_random_uuid(), '${U_TALEP}'::uuid, 'Talep Test', 'depo', '${otel}', true, r.id
      from public.roller r where r.kod='talep_test'
      on conflict do nothing;

    insert into public.urunler (kod, ad, birim) values ('${URUN}','Bag Test Urunu','KG')
      on conflict (kod) do nothing;
    insert into public.urun_birim_donusum (urun_kodu, buyuk_birim, carpan, silindi)
      values ('${URUN}','KOL',12,false) on conflict do nothing;

    insert into public.satin_alma_talepleri (id, departman, otel_id, durum, siparis_no)
      values ('${TALEP}'::uuid,'TEST','${otel}','${talepDurum}',null)
      on conflict (id) do nothing;
    insert into public.satin_alma_talep_kalemleri (id, talep_id, urun_adi, urun_kodu, miktar, birim) values
      ('${KALEM}'::uuid,  '${TALEP}'::uuid, 'Bag Test Urunu', '${URUN}', 10, 'KOL'),
      ('${KALEM2}'::uuid, '${TALEP}'::uuid, 'Bag Test Urunu', '${URUN}', 100, 'KG')
      on conflict (id) do nothing;

    insert into public.siparisler (siparis_no, firma_ad, otel_id, tarih, durum) values
      ('C00000001','Test Firma','${otel}', current_date, 'bekleyen'),
      ('C00000002','Test Firma 2','${otel}', current_date, 'bekleyen')
      on conflict (siparis_no) do nothing;
    set session_replication_role = origin;`);
  if (!r.ok) throw new Error('fikstur kurulamadi:\n' + r.err.split('\n').slice(-6).join('\n'));

  return {
    talepId: TALEP, kalemId: KALEM, kalemId2: KALEM2, urunKodu: URUN,
    siparisNo: 'C00000001', siparisNo2: 'C00000002',
    kimlik: { rol: 'authenticated', sub: U_TEST },
    kimlikTalep: { rol: 'authenticated', sub: U_TALEP },
  };
}

// Bag satirini DOGRUDAN yazar (tetikleyicileri test etmek icin; RPC'yi atlar).
export function bagYaz(O, f, { kalemId, siparisNo, miktar, hedefBirim = 'KOL',
                               kaynakMiktar = null, kaynakBirim = null, carpan = null } = {}) {
  return O.sql(`insert into public.talep_siparis_baglari
      (otel_id, talep_id, talep_kalem_id, siparis_no, urun_kodu,
       miktar, hedef_birim, kaynak_miktar, kaynak_birim, carpan, olusturan_ad)
    values ('810','${f.talepId}'::uuid,'${kalemId}'::uuid,'${siparisNo}','${f.urunKodu}',
            ${miktar}, '${hedefBirim}', ${kaynakMiktar ?? miktar},
            '${kaynakBirim ?? hedefBirim}', ${carpan === null ? 'null' : carpan}, 'test');`);
}
