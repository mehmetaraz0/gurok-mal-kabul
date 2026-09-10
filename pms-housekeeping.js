// ============================================================================
// KAT HİZMETLERİ — ORTAK RPC ADAPTÖRÜ
// ----------------------------------------------------------------------------
// Bu dosya kat hizmetleri ekranlarının veritabanıyla konuştuğu TEK yerdir.
//
// SÖZLEŞME (docs/PMS-FAZ2-HOUSEKEEPING-ARCHITECTURE.md — DB dondurulmuştur):
//   * YALNIZ onaylı RPC yüzeyi kullanılır.
//   * `pms_housekeeping_gorevleri` tablosuna DOĞRUDAN yazma YOKTUR.
//   * `pms_odalar.temizlik_durumu` / `temizlik_gorevi_id` DOĞRUDAN
//     yazılmaz — bunlar görev motorunun izdüşümüdür.
//   * Aktör kimliği İSTEMCİDEN GÖNDERİLMEZ; sunucu `auth.uid()` okur.
//
// NEDEN AYRI BİR sbYaz YOK:
//   Depodaki `sbYaz()` HTTP hatasında THROW ETMEZ — kırmızı şerit gösterip
//   yanıtı döndürür. Kat hizmetleri komutları için bu YETERSİZDİR: çağıran
//   kod hatayı fark etmeyip "başarılı" diyebilir. Buradaki `komut()` yanıtı
//   AÇIKÇA doğrular ve başarısızlıkta HkHata FIRLATIR.
// ============================================================================

/* global SB_URL, SB_HEADERS */

const HK_DURUM_AD = {
  bekliyor: 'Bekliyor',
  temizleniyor: 'Temizleniyor',
  tamamlandi: 'Tamamlandı',
  kontrol_edildi: 'Kontrol edildi',
  iptal: 'İptal',
};

const HK_TIP_AD = {
  cikis_temizligi: 'Çıkış temizliği',
  konaklama_temizligi: 'Konaklama temizliği',
  ekstra_temizlik: 'Ekstra temizlik',
};

const HK_ONCELIK_AD = { 1: 'Yüksek', 2: 'Normal', 3: 'Düşük' };

// Mimari §24.2 — sistem iptali nedenleri (yalnız GÖSTERİM için).
const HK_IPTAL_AD = {
  cikis_ile_yenilendi: 'Çıkışla yenilendi',
  oda_bloke: 'Oda bloke edildi',
  oda_ariza: 'Oda arızalı',
  oda_pasif: 'Oda pasifleştirildi',
};

// ---------------------------------------------------------------------------
// HATA SINIFI — çağıran koda "ne oldu" bilgisini TÜR olarak taşır.
// ---------------------------------------------------------------------------
class HkHata extends Error {
  constructor(tur, mesaj, ek) {
    super(mesaj);
    this.name = 'HkHata';
    this.tur = tur;                 // 'yetki' | 'bayat' | 'tekrar' | 'catisma'
                                    // | 'bulunamadi' | 'ag' | 'sunucu'
    this.sqlstate = (ek && ek.sqlstate) || null;
    this.http = (ek && ek.http) || null;
    this.ham = (ek && ek.ham) || null;
  }
  // Bayat sürüm / durum çakışması: ekran TAZELEMELİ, otomatik yeniden
  // göndermemeli (mimari §12.4 — komut makbuzu tekrar sözleşmesi DEĞİLDİR).
  get tazelemeGerek() { return this.tur === 'bayat' || this.tur === 'catisma'; }
}

// ---------------------------------------------------------------------------
// SQLSTATE + gövde -> tür eşlemesi.
// PostgREST hata gövdesi {code, message, details, hint} taşır; `code`
// PostgreSQL SQLSTATE'idir ve HTTP kodundan DAHA GÜVENİLİR ayırt edicidir.
// ---------------------------------------------------------------------------
function hkHataTuru(sqlstate, mesaj, http) {
  const m = String(mesaj || '');
  if (sqlstate === '40001' || m.includes('HK_SURUM_CAKISMASI')) return 'bayat';
  if (m.includes('HK_ISTEK_CAKISMASI')) return 'tekrar';
  if (m.includes('HK_DURUM_CAKISMASI') || m.includes('HK_ODA_KULLANILAMAZ')) return 'catisma';
  if (sqlstate === '23505') return 'catisma';       // benzersizlik: iş çakışması
  if (sqlstate === 'P0002' || http === 404) return 'bulunamadi';
  if (sqlstate === '42501' || http === 403) return 'yetki';
  return 'sunucu';
}

async function hkGovdeOku(r) {
  try { return await r.clone().json(); }
  catch (e) { try { return { message: await r.clone().text() }; } catch (e2) { return {}; } }
}

// ---------------------------------------------------------------------------
// TEK ÇIKIŞ NOKTASI — her RPC buradan geçer.
// Yanıt AÇIKÇA doğrulanır: r.ok değilse HkHata fırlatılır.
// ---------------------------------------------------------------------------
async function hkRpc(ad, govde) {
  let r;
  try {
    r = await fetch(SB_URL + '/rest/v1/rpc/' + ad, {
      method: 'POST',
      headers: { ...SB_HEADERS, 'Content-Type': 'application/json' },
      body: JSON.stringify(govde || {}),
    });
  } catch (e) {
    // Ağ hatası: isteğin sunucuya ULAŞIP ULAŞMADIĞI BİLİNMEZ. Bu yüzden
    // çağıran AYNI işlem anahtarıyla tekrar denemelidir (idempotency).
    throw new HkHata('ag', 'Sunucuya ulaşılamadı: ' + ((e && e.message) || e), { ham: e });
  }
  if (!r.ok) {
    const g = await hkGovdeOku(r);
    const tur = hkHataTuru(g && g.code, g && g.message, r.status);
    throw new HkHata(tur, (g && g.message) || ('HTTP ' + r.status),
      { sqlstate: g && g.code, http: r.status, ham: g });
  }
  try { return await r.json(); }
  catch (e) { return null; }
}

// ---------------------------------------------------------------------------
// İŞLEM ANAHTARI DEPOSU (idempotency)
// ---------------------------------------------------------------------------
// KURAL: anahtar KULLANICI NİYETİ başına ÜRETİLİR, ağ denemesi başına DEĞİL.
// Zaman aşımı/ağ hatası sonrası AYNI anahtarla tekrar gönderilir; sunucu
// aynı komutu ikinci kez UYGULAMAZ, "tekrar makbuzu" döner.
// Yeni anahtar YALNIZ komut kesin olarak bittiğinde (başarı ya da iş
// kuralıyla ret) düşürülür.
// Çevrimdışı mutasyon kuyruğu YOKTUR: depo bellekte yaşar, sayfa
// yenilenince kaybolur (mimari §12.4 bunu bilerek böyle bırakır).
const HK_NIYET = new Map();

function hkYeniUuid() {
  return (typeof crypto !== 'undefined' && crypto.randomUUID)
    ? crypto.randomUUID()
    : 'hk-' + Date.now() + '-' + Math.random().toString(36).slice(2, 12);
}

// Aynı niyet için hep aynı anahtar. `niyetKimlik` çağıran tarafından
// belirlenir: ör. 'sahiplen:<gorev_id>:<surum>'.
function hkAnahtar(niyetKimlik) {
  if (!HK_NIYET.has(niyetKimlik)) HK_NIYET.set(niyetKimlik, hkYeniUuid());
  return HK_NIYET.get(niyetKimlik);
}
function hkAnahtarDusur(niyetKimlik) { HK_NIYET.delete(niyetKimlik); }

// ---------------------------------------------------------------------------
// KOMUT SARMALAYICISI
// ---------------------------------------------------------------------------
// Ağ hatasında anahtar KORUNUR (aynı niyet tekrar denenebilsin).
// Kesin sonuçta (başarı / iş reddi) anahtar düşürülür ki kullanıcının
// BİR SONRAKİ gerçek eylemi yeni bir anahtar alsın.
async function hkKomut(rpcAd, niyetKimlik, govdeUret) {
  const anahtar = hkAnahtar(niyetKimlik);
  try {
    const sonuc = await hkRpc(rpcAd, govdeUret(anahtar));
    hkAnahtarDusur(niyetKimlik);
    return sonuc;
  } catch (e) {
    if (e instanceof HkHata && e.tur === 'ag') throw e;   // anahtar KORUNUR
    hkAnahtarDusur(niyetKimlik);
    throw e;
  }
}

// ---------------------------------------------------------------------------
// OKUMA YÜZEYİ (sınırlı, sunucu tarafı)
// ---------------------------------------------------------------------------
const HK = {
  DURUM_AD: HK_DURUM_AD,
  TIP_AD: HK_TIP_AD,
  ONCELIK_AD: HK_ONCELIK_AD,
  IPTAL_AD: HK_IPTAL_AD,
  Hata: HkHata,
  yeniUuid: hkYeniUuid,
  anahtarDusur: hkAnahtarDusur,

  // Kuyruklar sunucuda tanımlıdır: 'tumu' | 'bitmemis' | 'kontrol'.
  // Limit sunucuda 1..100 arasına KIRPILIR; sınırsız indirme YOKTUR.
  listele(otel, kuyruk, limit) {
    return hkRpc('pms_housekeeping_listele', {
      p_otel: String(otel), p_kuyruk: kuyruk || 'tumu', p_limit: limit || 50,
    });
  },

  // Çalışan listesi YALNIZ bu RPC'den gelir: {kullanici_id, ad}.
  // ERP kullanıcı tablosu doğrudan sorgulanmaz.
  calisanlar(otel) {
    return hkRpc('pms_housekeeping_calisanlar', { p_otel: String(otel) });
  },

  // Oda planı için TEK toplu istek. Oda başına sorgu YOKTUR (N+1 yasak).
  // Sunucu en çok 500 oda kabul eder.
  odaOzet(otel, odaIdler) {
    return hkRpc('pms_housekeeping_oda_ozet', {
      p_otel: String(otel), p_oda_idler: odaIdler,
    });
  },

  // -------------------------------------------------------------------------
  // KOMUT YÜZEYİ — hepsi ince sarmalayıcı; genel amaçlı durum yazıcı YOKTUR.
  // `surum` iyimser kilittir: bayat sürüm sunucuda 40001 ile reddedilir.
  // -------------------------------------------------------------------------
  sahiplen: (g, surum) => hkKomut('pms_housekeeping_sahiplen', 'sahiplen:' + g + ':' + surum,
    (a) => ({ p_gorev_id: g, p_beklenen_surum: surum, p_islem_anahtari: a })),

  birak: (g, surum) => hkKomut('pms_housekeeping_birak', 'birak:' + g + ':' + surum,
    (a) => ({ p_gorev_id: g, p_beklenen_surum: surum, p_islem_anahtari: a })),

  baslat: (g, surum) => hkKomut('pms_housekeeping_baslat', 'baslat:' + g + ':' + surum,
    (a) => ({ p_gorev_id: g, p_beklenen_surum: surum, p_islem_anahtari: a })),

  tamamla: (g, surum) => hkKomut('pms_housekeeping_tamamla', 'tamamla:' + g + ':' + surum,
    (a) => ({ p_gorev_id: g, p_beklenen_surum: surum, p_islem_anahtari: a })),

  kontrolEt: (g, surum) => hkKomut('pms_housekeeping_kontrol_et', 'kontrol:' + g + ':' + surum,
    (a) => ({ p_gorev_id: g, p_beklenen_surum: surum, p_islem_anahtari: a })),

  ata: (g, hedefKullanici, surum) =>
    hkKomut('pms_housekeeping_ata', 'ata:' + g + ':' + surum + ':' + hedefKullanici,
      (a) => ({ p_gorev_id: g, p_hedef_kullanici: hedefKullanici,
                p_beklenen_surum: surum, p_islem_anahtari: a })),

  iptal: (g, aciklama, surum) =>
    hkKomut('pms_housekeeping_iptal', 'iptal:' + g + ':' + surum,
      (a) => ({ p_gorev_id: g, p_aciklama: aciklama,
                p_beklenen_surum: surum, p_islem_anahtari: a })),

  // yuk: {notlar?, oncelik?, hedef_zamani?}
  duzenle: (g, yuk, surum) =>
    hkKomut('pms_housekeeping_duzenle', 'duzenle:' + g + ':' + surum,
      (a) => ({ p_gorev_id: g, p_yuk: yuk || {},
                p_beklenen_surum: surum, p_islem_anahtari: a })),

  yenidenAc: (g, aciklama, surum) =>
    hkKomut('pms_housekeeping_yeniden_ac', 'yeniden_ac:' + g + ':' + surum,
      (a) => ({ p_gorev_id: g, p_aciklama: aciklama,
                p_beklenen_surum: surum, p_istek_anahtari: a })),

  devret: (g, aciklama, surum) =>
    hkKomut('pms_housekeeping_devret', 'devret:' + g + ':' + surum,
      (a) => ({ p_gorev_id: g, p_aciklama: aciklama,
                p_beklenen_surum: surum, p_istek_anahtari: a })),

  // Kullanıcı YALNIZ konaklama/ekstra temizlik açabilir; çıkış temizliği
  // check-out tetikleyicisinin işidir (mimari §8).
  // `beklenenKullanim` odanın kullanım durumu için iyimser kilittir.
  gorevOlustur: (odaId, tip, beklenenKullanim, yuk, niyetKimlik) =>
    hkKomut('pms_housekeeping_gorev_olustur',
      niyetKimlik || ('olustur:' + odaId + ':' + tip),
      (a) => ({ p_oda_id: odaId, p_tip: tip, p_beklenen_kullanim: beklenenKullanim,
                p_istek_anahtari: a, p_yuk: yuk || {} })),
};

// ---------------------------------------------------------------------------
// YETKİ YARDIMCILARI
// ---------------------------------------------------------------------------
// Bunlar YALNIZ EKRAN KOLAYLIĞIDIR. Güvenlik sunucudadır (RLS + RPC
// yetkilendirmesi). Burada bir düğmeyi gizlemek bir koruma DEĞİLDİR;
// amaç kullanıcıya baştan reddedilecek eylemi göstermemektir.
const HK_SEVIYE = { yok: 0, goruntule: 1, kayit: 2, tam: 3 };
function hkEnAz(seviye, gereken) {
  return (HK_SEVIYE[seviye] || 0) >= (HK_SEVIYE[gereken] || 0);
}

// Bir görev için o kullanıcının YAPABİLECEĞİ eylemler.
// Sunucu her hâlükârda son sözü söyler.
function hkEylemler(gorev, yetki, kullaniciId) {
  const e = [];
  if (!gorev) return e;
  const benim = gorev.atanan_kullanici_id && gorev.atanan_kullanici_id === kullaniciId;
  const guncel = gorev.guncel_dongu !== false;
  const kayit = hkEnAz(yetki, 'kayit');
  const tam = hkEnAz(yetki, 'tam');

  if (gorev.durum === 'bekliyor') {
    if (kayit && !gorev.atanan_kullanici_id) e.push('sahiplen');
    if (kayit && benim) { e.push('baslat'); e.push('birak'); }
    if (tam) { e.push('ata'); e.push('duzenle'); e.push('iptal'); }
  } else if (gorev.durum === 'temizleniyor') {
    if (kayit && benim) e.push('tamamla');
    if (tam) { e.push('devret'); e.push('iptal'); }
  } else if (gorev.durum === 'tamamlandi') {
    // Bayat (güncel olmayan) görev YENİ döngüyü sertifika edemez — H9.
    if (tam && guncel && !benim) e.push('kontrol_et');
    if (tam && guncel) e.push('yeniden_ac');
  } else if (gorev.durum === 'kontrol_edildi') {
    if (tam && guncel) e.push('yeniden_ac');
  }
  return e;
}

// Hata türünü kullanıcı diline çevirir. Yetki reddi ile bayat durum
// çakışması AYRI mesajlardır — ikisi farklı davranış gerektirir.
function hkHataMesaji(e) {
  if (!(e instanceof HkHata)) return 'Beklenmeyen hata: ' + ((e && e.message) || e);
  switch (e.tur) {
    case 'yetki':      return 'Bu işlem için yetkiniz yok.';
    case 'bayat':      return 'Görev bu sırada başkası tarafından değiştirildi. Liste tazelendi — güncel duruma bakıp tekrar deneyin.';
    case 'catisma':    return 'İşlem yapılamadı: ' + e.message;
    case 'tekrar':     return 'Aynı istek farklı içerikle gönderildi. Sayfayı tazeleyip tekrar deneyin.';
    case 'bulunamadi': return 'Görev bulunamadı ya da erişiminiz yok.';
    case 'ag':         return 'Sunucuya ulaşılamadı. Bağlantı gelince aynı işlemi tekrar deneyebilirsiniz.';
    default:           return 'Sunucu hatası: ' + e.message;
  }
}

// Geçen süre — "14:05'ten beri" yerine "2s 10dk" gibi operasyonel gösterim.
function hkGecenSure(baslangicIso, sunucuZamaniIso) {
  if (!baslangicIso) return '';
  const t0 = Date.parse(baslangicIso);
  const t1 = sunucuZamaniIso ? Date.parse(sunucuZamaniIso) : Date.now();
  if (!Number.isFinite(t0) || !Number.isFinite(t1)) return '';
  let dk = Math.floor((t1 - t0) / 60000);
  if (dk < 0) dk = 0;
  if (dk < 60) return dk + ' dk';
  const s = Math.floor(dk / 60);
  if (s < 24) return s + ' sa ' + (dk % 60) + ' dk';
  return Math.floor(s / 24) + ' gün';
}
