// ===========================================================================
// STOK VERI ERISIM KATMANI
// ===========================================================================
// TEMEL ILKE: eksik veri, "veri yok" demek DEGILDIR.
//
// Bu modulden once stok-takip.html su deseni kullaniyordu:
//     const liste = r.ok ? await r.json() : [];
// Bu desen HTTP hatasini bos listeye cevirir. Sayim onayinda sonucu agirdi:
// detaylar okunamadiginda dongu hic donmuyor, hicbir stok yazilmiyor ve oturum
// "onaylandi" olarak isaretleniyordu. Burada BOYLE BIR YOL YOKTUR: her okuma
// ya eksiksiz veri doner ya da StokVeriHatasi firlatir.
//
// SAYFALAMA: PostgREST'in satir tavani (db-max-rows) BILINMEZ kabul edilir.
// Her sayfali okuma Content-Range basligindan gercek toplami okur ve toplam
// elde edilene kadar devam eder. Toplam okunamiyorsa ve sayfa tam dolduysa
// kirpilma varsayilir ve hata firlatilir.
//
// RLS: bu modul hicbir otel/yetki filtresi UYDURMAZ. Otel kapsami sunucudaki
// RLS'in isidir; istemci yalnizca depo ve arama gibi operasyonel filtreler
// verir.
// ===========================================================================

class StokVeriHatasi extends Error {
  constructor(mesaj, ayrinti) {
    super(mesaj);
    this.name = 'StokVeriHatasi';
    this.durum = (ayrinti && ayrinti.durum) || 0;   // HTTP durum kodu (0 = ag hatasi)
    this.yol = (ayrinti && ayrinti.yol) || '';
    this.tur = (ayrinti && ayrinti.tur) || 'okuma'; // okuma | kirpilma | eksik
  }
}

const SAYFA_BOYUTU = 500;

// Content-Range: "0-99/5000" -> {bas:0, son:99, toplam:5000}
// Toplam "*" olabilir (sayim istenmediyse) -> toplam null doner.
function _araligiCoz(baslik) {
  if (!baslik) return null;
  const m = String(baslik).match(/(\d+)-(\d+)\/(\d+|\*)/);
  if (!m) return null;
  return {
    bas: Number(m[1]),
    son: Number(m[2]),
    toplam: m[3] === '*' ? null : Number(m[3]),
  };
}

function _stokVeriKur(secenekler) {
  const ayar = secenekler || {};
  const SB_URL = ayar.url;
  const SB_HEADERS = ayar.headers || {};
  const getir = ayar.fetch;
  const sayfaBoyutu = ayar.sayfaBoyutu || SAYFA_BOYUTU;
  // Supabase ag gecidinde REST onegi /rest/v1; ciplak bir PostgREST'te kok dizindir.
  const onek = ayar.onek === undefined ? '/rest/v1' : ayar.onek;

  async function _iste(yol, ekBaslik) {
    let cevap;
    try {
      cevap = await getir(SB_URL + yol, { headers: { ...SB_HEADERS, ...(ekBaslik || {}) } });
    } catch (e) {
      // Ag hatasi: istegin sunucuya ULASIP ULASMADIGI bilinmez. Bos liste DEGIL.
      throw new StokVeriHatasi('Sunucuya ulasilamadi: ' + ((e && e.message) || e), { durum: 0, yol });
    }
    if (!cevap.ok) {
      throw new StokVeriHatasi('Sunucu hatasi (HTTP ' + cevap.status + ')', { durum: cevap.status, yol });
    }
    return cevap;
  }

  // Tek sayfa okur; {satirlar, aralik} doner.
  async function sayfaCek(yol, ofset, adet) {
    const son = ofset + adet - 1;
    const cevap = await _iste(yol, { Range: ofset + '-' + son, 'Range-Unit': 'items', Prefer: 'count=exact' });
    const satirlar = await cevap.json();
    const aralik = _araligiCoz(cevap.headers && cevap.headers.get && cevap.headers.get('content-range'));
    return { satirlar: Array.isArray(satirlar) ? satirlar : [], aralik };
  }

  // Butun sayfalari toplar. Ara sayfada hata olursa FIRLATIR: yarim liste donmez.
  async function tumSayfalariCek(yol, secenek) {
    const s = secenek || {};
    const adet = s.sayfaBoyutu || sayfaBoyutu;
    const azami = s.azamiSayfa || 200;               // sonsuz donguye karsi emniyet
    const hepsi = [];
    let ofset = 0;
    let toplam = null;

    for (let i = 0; i < azami; i++) {
      const { satirlar, aralik } = await sayfaCek(yol, ofset, adet);
      hepsi.push(...satirlar);

      if (aralik && aralik.toplam !== null) {
        toplam = aralik.toplam;
        if (hepsi.length >= toplam) return { satirlar: hepsi, toplam };
        if (!satirlar.length) {
          // Toplam soyluyor ama sunucu satir vermiyor: eksik kaldi.
          throw new StokVeriHatasi(
            'Liste eksik kaldi: ' + hepsi.length + '/' + toplam + ' satir alinabildi', { yol, tur: 'eksik' });
        }
        ofset += satirlar.length;
        continue;
      }

      // Toplam bilinmiyor. Sayfa tam dolduysa daha fazlasi OLABILIR ve bunu
      // kanitlayamayiz -> kirpilma varsay, sessizce eksik liste dondurme.
      if (satirlar.length >= adet) {
        throw new StokVeriHatasi(
          'Sunucu toplam satir sayisini bildirmedi; liste kirpilmis olabilir', { yol, tur: 'kirpilma' });
      }
      return { satirlar: hepsi, toplam: hepsi.length };
    }
    throw new StokVeriHatasi('Sayfa siniri asildi (' + azami + '); liste tamamlanamadi', { yol, tur: 'eksik' });
  }

  // --- Sayim ---------------------------------------------------------------
  // beklenenAdet: sayim_oturumlari.toplam_urun_sayisi. Verilirse IKINCI bir
  // eksiksizlik kaniti olur: sayfalama tamam dese bile adet tutmuyorsa firlat.
  async function sayimDetaylariniGetir(oturumId, beklenenAdet) {
    const yol = onek + '/sayim_detaylari?oturum_id=eq.' + encodeURIComponent(oturumId)
      + '&select=*&order=urun_kodu.asc';
    const { satirlar } = await tumSayfalariCek(yol);
    if (beklenenAdet !== null && beklenenAdet !== undefined && Number(beklenenAdet) > 0
        && satirlar.length !== Number(beklenenAdet)) {
      throw new StokVeriHatasi(
        'Sayim detaylari eksik: ' + Number(beklenenAdet) + ' satir bekleniyordu, ' + satirlar.length + ' geldi',
        { yol, tur: 'eksik' });
    }
    return satirlar;
  }

  // --- Stok listesi --------------------------------------------------------
  function _stokYolu(sec) {
    const s = sec || {};
    // guncelleme_tarihi de istenir: karttaki "Son guncelleme" satiri bunu
    // gosterir. Eski toplu okuma (stok?select=*) tasiyordu; sayfali okumanin
    // alan listesinde olmayinca her kart "—" gosteriyordu (olculdu 2026-09-15).
    let yol = onek + '/stok_liste?select=otel_id,depo_kodu,urun_kodu,urun_adi,birim,miktar,min_miktar,guncelleme_tarihi';
    if (s.depo) yol += '&depo_kodu=eq.' + encodeURIComponent(s.depo);
    if (s.arama && String(s.arama).trim()) {
      const t = String(s.arama).trim().replace(/[(),*]/g, ' ');
      yol += '&or=(urun_kodu.ilike.*' + encodeURIComponent(t) + '*,urun_adi.ilike.*' + encodeURIComponent(t) + '*)';
    }
    yol += '&order=urun_kodu.asc';
    return yol;
  }

  // Tek sayfa (sonsuz kaydirma icin). {satirlar, toplam, dahaVar} doner.
  async function stokSayfasiGetir(sec) {
    const s = sec || {};
    const adet = s.adet || 100;
    const ofset = s.ofset || 0;
    const { satirlar, aralik } = await sayfaCek(_stokYolu(s), ofset, adet);
    const toplam = aralik && aralik.toplam !== null ? aralik.toplam : null;
    const dahaVar = toplam === null ? satirlar.length >= adet : (ofset + satirlar.length) < toplam;
    return { satirlar, toplam, dahaVar };
  }

  async function stokTumunuGetir(sec) {
    return tumSayfalariCek(_stokYolu(sec || {}));
  }

  // --- Urun aramasi --------------------------------------------------------
  // SUNUCUDA arar: indirilmis katalogla sinirli DEGILDIR.
  async function urunAra(terim, adet) {
    const t = String(terim || '').trim().replace(/[(),*]/g, ' ');
    if (t.length < 2) return { satirlar: [], dahaVar: false };
    const sinir = adet || 20;
    const yol = onek + '/urunler?select=kod,ad,birim'
      + '&or=(kod.ilike.*' + encodeURIComponent(t) + '*,ad.ilike.*' + encodeURIComponent(t) + '*)'
      + '&order=ad.asc';
    const { satirlar, aralik } = await sayfaCek(yol, 0, sinir);
    const toplam = aralik && aralik.toplam !== null ? aralik.toplam : null;
    return { satirlar, toplam, dahaVar: toplam === null ? satirlar.length >= sinir : toplam > sinir };
  }

  // --- Hareket gecmisi -----------------------------------------------------
  // Acilista DEGIL, istek uzerine ve sayfali.
  async function hareketSayfasiGetir(sec) {
    const s = sec || {};
    const adet = s.adet || 50;
    const ofset = s.ofset || 0;
    let yol = onek + '/stok_hareketleri?select=*';
    if (s.depo) yol += '&depo_kodu=eq.' + encodeURIComponent(s.depo);
    if (s.urun) yol += '&urun_kodu=eq.' + encodeURIComponent(s.urun);
    yol += '&order=tarih.desc';
    const { satirlar, aralik } = await sayfaCek(yol, ofset, adet);
    const toplam = aralik && aralik.toplam !== null ? aralik.toplam : null;
    const dahaVar = toplam === null ? satirlar.length >= adet : (ofset + satirlar.length) < toplam;
    return { satirlar, toplam, dahaVar };
  }

  // --- Ozet (toplamlar) ----------------------------------------------------
  // Sayfadan DEGIL, sunucudan. RLS cagiranin haklariyla uygulanir.
  async function stokOzetGetir(depo) {
    const yol = onek + '/rpc/stok_ozet';
    let cevap;
    try {
      cevap = await getir(SB_URL + yol, {
        method: 'POST',
        headers: { ...SB_HEADERS, 'Content-Type': 'application/json' },
        body: JSON.stringify({ p_depo: depo || null }),
      });
    } catch (e) {
      throw new StokVeriHatasi('Ozet okunamadi: ' + ((e && e.message) || e), { durum: 0, yol });
    }
    if (!cevap.ok) throw new StokVeriHatasi('Ozet okunamadi (HTTP ' + cevap.status + ')', { durum: cevap.status, yol });
    const d = await cevap.json();
    const satir = Array.isArray(d) ? d[0] : d;
    if (!satir) throw new StokVeriHatasi('Ozet bos dondu', { yol, tur: 'eksik' });
    return {
      toplam: Number(satir.toplam) || 0,
      kritik: Number(satir.kritik) || 0,
      uyari: Number(satir.uyari) || 0,
      normal: Number(satir.normal) || 0,
    };
  }

  return {
    sayfaCek,
    tumSayfalariCek,
    sayimDetaylariniGetir,
    stokSayfasiGetir,
    stokTumunuGetir,
    urunAra,
    hareketSayfasiGetir,
    stokOzetGetir,
  };
}

// Tarayici: global; Node (testler): module.exports.
if (typeof window !== 'undefined') {
  window.StokVeri = { kur: _stokVeriKur, Hata: StokVeriHatasi };
}
if (typeof module !== 'undefined' && module.exports) {
  module.exports = { kur: _stokVeriKur, StokVeriHatasi, _araligiCoz };
}
