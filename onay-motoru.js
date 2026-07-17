// onay-motoru.js — Gürok ERP paylaşılan çok aşamalı onay motoru.
// Onay akışı olan sayfalar bunu <head> içinde, auth-guard.js'den SONRA,
// senkron olarak yükler (<script src="onay-motoru.js"></script>).
//
// Aşama sırası: depo -> cost -> (tutara göre) mdr | direktor | gm | ust_yonetim.
// depo ve cost limitsiz geçiş aşamaları (ürün/bütçe kontrolü); mdr/direktor/gm/
// ust_yonetim tutar eşiğine göre TEK bir katmana yönlendirilir, sıralı çoklu
// imza değildir.

const ONAY_KATMANLARI = {
  depo:        { roller: ['depo'],           tip: 'kontrol' },
  cost:        { roller: ['cost_control'],   tip: 'tutar_gir' },
  mdr:         { roller: ['satinalma_mdr'],  tip: 'onay', limit: 200000 },
  direktor:    { roller: ['grup_satinalma'], tip: 'onay', limit: 500000 },
  gm:          { roller: ['gm'],             tip: 'onay', limit: 750000 },
  ust_yonetim: { roller: ['grup_direktor'],  tip: 'onay', limit: null }
};

// Cost aşaması onaylandığında tutara göre hangi katmana düşeceğini belirler.
function tutaraGoreKatmanSec(tutar){
  const t = parseFloat(tutar) || 0;
  if (t <= 200000) return 'mdr';
  if (t <= 500000) return 'direktor';
  if (t <= 750000) return 'gm';
  return 'ust_yonetim';
}

// mevcutAsama + (varsa) tutar verildiğinde bir sonraki asamayı döner.
// null dönerse: süreç biter, durum='onaylandi' yazılır.
function sonrakiAsamaBelirle(mevcutAsama, tutar){
  if (mevcutAsama === 'depo') return 'cost';
  if (mevcutAsama === 'cost') return tutaraGoreKatmanSec(tutar);
  return null; // mdr/direktor/gm/ust_yonetim onayladıysa süreç biter
}

// depo/cost aşamaları legacy CU.rol üzerinden ayırt edilebiliyor (depo_sef+depo -> 'depo',
// cost_control_mdr+cost_control -> 'cost_control'). mdr/direktor/gm/ust_yonetim için
// legacy rol hepsini 'satinalma'/'yonetici'ye düşürüyor (bkz. kullanici-yonetimi.html
// ROL_KODU_ESKI_ENUM) — bu dördü SADECE rol_id->kod çözümlemesiyle ayırt edilir.
let _rollerKodCache = null; // {rolId: kod}
async function rollerKodHaritasiYukle(){
  if (_rollerKodCache) return _rollerKodCache;
  _rollerKodCache = {};
  try{
    const r = await fetch(SB_URL+'/rest/v1/roller?select=id,kod', {headers: SB_HEADERS});
    if (r.ok) (await r.json()).forEach(x => { _rollerKodCache[x.id] = x.kod; });
  }catch(e){ console.warn(e); }
  return _rollerKodCache;
}

async function kullaniciAsamaYetkiliMi(kullanici, asama){
  const katman = ONAY_KATMANLARI[asama];
  if (!katman || !kullanici) return false;
  if (asama === 'depo' || asama === 'cost'){
    return katman.roller.includes(kullanici.rol);
  }
  const harita = await rollerKodHaritasiYukle();
  const kod = harita[kullanici.rol_id];
  return katman.roller.includes(kod);
}

// Bir talebin PATCH'ten önce güncel asama/durum'unu canlı okur ve beklenenle
// karşılaştırır — stok-takip.html'deki sayimOnayla ile aynı stale-state guard
// deseni: iki kişinin aynı talebi aynı anda farklı kararlarla ilerletmesini önler.
let _talepAsamaIsleniyor = false;

async function talepAsamaIlerlet(talepId, kullanici, karar, opts){
  opts = opts || {};
  const tutar = opts.tutar;
  const not = opts.not;
  if (_talepAsamaIsleniyor) return {ok:false, hata:'islemde'};
  _talepAsamaIsleniyor = true;
  try{
    const guncelR = await fetch(SB_URL+'/rest/v1/satin_alma_talepleri?id=eq.'+talepId+'&select=asama,durum', {headers: SB_HEADERS});
    if (!guncelR.ok) return {ok:false, hata:'canli_okuma_basarisiz'};
    const guncelListe = await guncelR.json();
    const guncel = guncelListe[0];
    if (!guncel || guncel.durum !== 'bekleyen') return {ok:false, hata:'zaten_karar_verilmis'};

    const asama = guncel.asama;
    if (!(await kullaniciAsamaYetkiliMi(kullanici, asama))) return {ok:false, hata:'yetkisiz'};

    if (karar === 'red'){
      const gecmisR = await fetch(SB_URL+'/rest/v1/talep_onay_gecmisi', {method:'POST', headers: SB_HEADERS,
        body: JSON.stringify({talep_id: talepId, asama, rol_kodu: kullanici.rol, kullanici_ad: kullanici.ad, karar: 'red', not_metni: not || null})});
      if (!gecmisR.ok) console.error('talep_onay_gecmisi yazılamadı (red) — denetim izi eksik kalabilir:', await gecmisR.text());
      await fetch(SB_URL+'/rest/v1/satin_alma_talepleri?id=eq.'+talepId, {method:'PATCH', headers: SB_HEADERS,
        body: JSON.stringify({durum:'reddedildi', onaylayan_ad: kullanici.ad, onay_tarihi: new Date().toISOString()})});
      return {ok:true, sonuc:'reddedildi', gecmisYazildi: gecmisR.ok};
    }

    // Cost aşamasında tutar zorunlu — sonraki katman bu değere göre belirlenir.
    if (asama === 'cost' && (tutar === undefined || tutar === null || isNaN(parseFloat(tutar)))) {
      return {ok:false, hata:'tutar_gerekli'};
    }

    const gecmisR = await fetch(SB_URL+'/rest/v1/talep_onay_gecmisi', {method:'POST', headers: SB_HEADERS,
      body: JSON.stringify({talep_id: talepId, asama, rol_kodu: kullanici.rol, kullanici_ad: kullanici.ad, karar: 'onay', not_metni: not || null})});
    if (!gecmisR.ok) console.error('talep_onay_gecmisi yazılamadı (onay, asama='+asama+') — denetim izi eksik kalabilir:', await gecmisR.text());

    const sonrakiAsama = sonrakiAsamaBelirle(asama, tutar);
    const patchBody = {};
    if (asama === 'cost') patchBody.tutar = parseFloat(tutar);

    if (sonrakiAsama){
      patchBody.asama = sonrakiAsama;
    } else {
      patchBody.durum = 'onaylandi';
      patchBody.onaylayan_ad = kullanici.ad;
      patchBody.onay_tarihi = new Date().toISOString();
    }
    await fetch(SB_URL+'/rest/v1/satin_alma_talepleri?id=eq.'+talepId, {method:'PATCH', headers: SB_HEADERS, body: JSON.stringify(patchBody)});
    return {ok:true, sonuc: sonrakiAsama || 'onaylandi', gecmisYazildi: gecmisR.ok};
  } catch(e) {
    console.warn(e);
    return {ok:false, hata:'istisna'};
  } finally {
    _talepAsamaIsleniyor = false;
  }
}
