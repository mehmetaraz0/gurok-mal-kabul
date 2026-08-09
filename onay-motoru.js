// onay-motoru.js — Araz ERP paylaşılan çok aşamalı onay motoru.
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

// ⚠️ ARTIK KARAR VERMEZ — pentest-2 [2] sonrası sonraki aşamayı SUNUCU belirler
// (talep_karar_ver RPC'si). Bu fonksiyon yalnız arayüzde önizleme/etiket amaçlı
// kalmıştır; buradan dönen değere göre HİÇBİR yazma yapılmamalıdır.
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
  // Süperuser: yönetici (admin) rolü HER aşamayı onaylayabilir — küçük işletme/tek
  // kullanıcılı işleyiş için (görevler ayrılığı bilinçli olarak gevşetildi).
  if (kullanici.rol === 'yonetici') return true;
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

// GÜVENLİK (pentest-2 bulgu [2] — 2026-08-09): kararın TAMAMI artık sunucuda.
// ÖNCEKİ HAL: yetki kontrolü burada (JS'te) yapılıyor, onay geçmişi istemci
// POST'uyla yazılıyor, durum/asama istemci PATCH'iyle değiştiriliyordu. Üç açık:
//   • aşama atlama (doğrudan durum yazılabiliyordu)
//   • sahte onay geçmişi kaydı
//   • "canlı oku → PATCH" arası atomik değil → bayat yazma / yarış
// ŞİMDİ: talep_karar_ver RPC'si çağıranı JWT'den çözer, satırı FOR UPDATE ile
// kilitler, durumu+yetkiyi doğrular, geçmişi kendi yazar — hepsi tek transaction.
// Buradaki _talepAsamaIsleniyor yalnız ÇİFT TIKLAMA içindir; güvenlik değil.
async function talepAsamaIlerlet(talepId, kullanici, karar, opts){
  opts = opts || {};
  const tutar = opts.tutar;
  const not = opts.not;
  if (_talepAsamaIsleniyor) return {ok:false, hata:'islemde'};
  _talepAsamaIsleniyor = true;
  try{
    // Tutar ön-kontrolü ÇAĞIRAN sayfada yapılır (cost aşamasını orada biliyor);
    // sunucu da bağımsızca doğrular ve gerekirse {hata:'tutar_gerekli'} döner.
    const r = await fetch(SB_URL+'/rest/v1/rpc/talep_karar_ver', {
      method:'POST', headers: SB_HEADERS,
      body: JSON.stringify({
        p_talep_id: talepId,
        p_karar: karar,
        p_not: not || null,
        p_tutar: (tutar === undefined || tutar === null || tutar === '') ? null : parseFloat(tutar)
      })
    });
    if (!r.ok){
      const govde = await r.text().catch(()=> '');
      console.error('talep_karar_ver başarısız:', r.status, govde);
      return {ok:false, hata:'sunucu_hatasi'};
    }
    const sonuc = await r.json();   // {ok, sonuc} | {ok:false, hata}
    return sonuc || {ok:false, hata:'bos_yanit'};
  } catch(e) {
    console.warn(e);
    return {ok:false, hata:'istisna'};
  } finally {
    _talepAsamaIsleniyor = false;
  }
}

// Onaylı talebi siparişe dönüştür — istemci PATCH'inin yerine (sunucu doğrular:
// yetki + durum='onaylandi' + atomik geçiş).
async function talepSiparisRpc(talepId){
  try{
    const r = await fetch(SB_URL+'/rest/v1/rpc/talep_siparise_donustur', {
      method:'POST', headers: SB_HEADERS,
      body: JSON.stringify({p_talep_id: talepId})
    });
    if (!r.ok){
      const govde = await r.text().catch(()=> '');
      console.error('talep_siparise_donustur başarısız:', r.status, govde);
      return {ok:false, hata:'sunucu_hatasi'};
    }
    return (await r.json()) || {ok:false, hata:'bos_yanit'};
  }catch(e){
    console.warn(e);
    return {ok:false, hata:'istisna'};
  }
}
