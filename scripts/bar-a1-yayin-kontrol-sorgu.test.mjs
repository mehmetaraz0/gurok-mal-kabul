// ===========================================================================
// YAYIN ONCESI/SONRASI KONTROL SORGUSU — IZOLE PROVA (uretime BAGLANMAZ)
// ===========================================================================
// Kullanici siniri 2026-09-20: "yalniz kalem/hareket SAYISINA bakarak tamamlama;
// miktar ve hareket ayri yazildigi icin hareket kaydi olmayan stok degismis
// olabilir." Sorgu bunu satir bazinda ayirt etmeli:
//   S1  Hareketi olan kalem              -> 'hareket VAR'
//   S2  Hareketi YOK, stok onaydan SONRA degismis -> 'SUPHELI ... yeniden yazma!'
//   S3  Hareketi YOK, stok degismemis    -> 'islenmemis gorunuyor'
//   S4  Sorgu salt okumadir: calistiktan sonra veri degismez.
// ===========================================================================
import { readFileSync } from 'node:fs';
import { barOrtami, kok } from './bar-test-ortam.mjs';

const SORGU = 'docs/kurulum/2026-09-20-yayin-oncesi-islem-kontrol.sql';
const O = barOrtami({ ad: 'bar-a1-kontrol' });
let ok = 0, fail = 0;
const sonuc = (g, ad, ek) => { console.log((g ? 'OK   ' : 'FAIL ') + ad + (ek ? ' — ' + ek : '')); if (g) ok++; else fail++; };

try {
  await O.kur();
  // Yarim kalmis mal kabul: 3 kalem. A islendi (hareket + stok), B stok degisti ama
  // hareket YAZILMADI (asil tehlike), C hic islenmedi.
  O.sql(`set session_replication_role = replica;
    insert into public.urunler (kod, ad, birim) values ('MKA','A urun','KG'), ('MKB','B urun','KG'), ('MKC','C urun','KG')
      on conflict do nothing;
    insert into public.mal_kabuller (id, mk_no, form_tarihi, firma_ad, otel_id, depo_kodu, durum, stok_islendi)
      values ('77777777-0000-0000-0000-000000000001','MK-TEST-1', current_date, 'Test Firma', '810', '100', 'onaylandi', false);
    insert into public.mal_kabul_urunleri (mk_id, urun_kodu, urun_adi, miktar) values
      ('77777777-0000-0000-0000-000000000001','MKA','A urun',5),
      ('77777777-0000-0000-0000-000000000001','MKB','B urun',7),
      ('77777777-0000-0000-0000-000000000001','MKC','C urun',9);
    -- Onay zamani denetim izinden okunur:
    insert into public.erp_islem_audit (hotel_id, actor_user_id, actor_role, event_type, entity_type, entity_id, transaction_id)
      values ('810', null, 'service_role', 'UPDATE', 'mal_kabuller', '77777777-0000-0000-0000-000000000001', '0');
    -- A: stok + hareket
    insert into public.stok (urun_kodu, depo_kodu, otel_id, miktar, guncelleme_tarihi)
      values ('MKA','810_100','810',5, now());
    insert into public.stok_hareketleri (urun_kodu, depo_kodu, otel_id, tip, miktar, belge_no, aciklama, tarih)
      values ('MKA','810_100','810','giris',5,'MK-TEST-1','Mal kabul: MK-TEST-1', now());
    -- B: YALNIZ stok (hareket yok) — sayim temelli karsilastirmanin kacirdigi durum
    insert into public.stok (urun_kodu, depo_kodu, otel_id, miktar, guncelleme_tarihi)
      values ('MKB','810_100','810',7, now());
    -- C: hic islenmedi (stok satiri yok)
    set session_replication_role = origin;`);

  const r = O.uygula(SORGU);
  const satir = (kod) => (r.out.split('\n').find((l) => l.includes('|' + kod + '|')) || '');
  sonuc(r.ok && /hareket VAR/.test(satir('MKA')), 'S1 hareketi olan kalem "hareket VAR" olarak isaretlendi',
    (r.ok ? '' : 'HATA: ' + r.err.split('\n').slice(-3).join(' | ')) + satir('MKA').slice(0, 120));
  sonuc(/SUPHELI/.test(satir('MKB')) && /yeniden yazma/.test(satir('MKB')),
    'S2 hareket YOK ama stok onaydan sonra degismis kalem SUPHELI (korlemesine yeniden yazma uyarisi)', satir('MKB').slice(0, 170));
  sonuc(/islenmemis gorunuyor/.test(satir('MKC')), 'S3 hic islenmemis kalem ayirt edildi', satir('MKC').slice(0, 150));
  sonuc(O.sql(`select count(*) from public.stok_hareketleri where belge_no='MK-TEST-1';`).out === '1'
     && O.sql(`select count(*) from public.stok where urun_kodu in ('MKA','MKB','MKC');`).out === '2',
    'S4 kontrol sorgusu salt okuma: veri degismedi');
} catch (e) {
  sonuc(false, 'beklenmeyen hata', e.stack || e.message);
} finally { O.temizle(); }

console.log(`\nYAYIN KONTROL SORGUSU: ${ok} OK / ${fail} FAIL`);
process.exit(fail ? 1 : 0);
