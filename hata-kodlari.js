// ===========================================================================
// hata-kodlari.js — sunucu hata kodlarinin Turkce karsiligi (bar + stok, A1)
// ===========================================================================
// Sunucu (RPC) hatalari "KOD: aciklama" bicimindedir (tasarim bolum 9).
// hataKodunuBul(metin)  -> 'FIYAT_DEGISTI' | null
// hataMetni(metin)      -> kullaniciya gosterilecek Turkce cumle
// Metin: PostgREST hata govdesi (JSON ya da duz), Edge Function 'mesaj' alani
// ya da Error.message olabilir.
// ===========================================================================
(function (kok) {
  const METIN = {
    BOS_SIPARIS: 'Sepet boş — en az bir ürün seçin.',
    GECERSIZ_ADET: 'Geçersiz adet.',
    MENU_URUNU_YOK: 'Ürün menüde yok ya da pasif.',
    FIYAT_DEGISTI: 'Fiyat değişti — menü yenilendi, lütfen kontrol edip tekrar gönderin.',
    ODA_NO_GEREKLI: 'Ücretli ürün için oda numarası zorunlu.',
    KONAKLAMA_YOK: 'Bu odada şu an konaklayan ya da açık folyo yok.',
    YETERSIZ_STOK: 'Stok yetersiz.',
    DEPO_OTEL_UYUSMAZ: 'Depo bu otele ait değil.',
    YETKI_YOK: 'Bu işlem için yetkiniz yok.',
    OTEL_ERISIMI_YOK: 'Bu otel için yetkiniz yok.',
    KIMLIK_GEREKLI: 'Bu işlemi yalnız giriş yapmış personel yapabilir.',
    SIPARIS_YOK: 'Sipariş bulunamadı.',
    DOGRULAMA_BEYANI_GEREKLI: 'Misafirin oda kartını/kimliğini kontrol ettiğinizi onaylayın.',
    DOGRULAMA_GEREKMIYOR: 'Bu sipariş oda doğrulaması gerektirmiyor.',
    ODA_DOGRULAMASI_BEKLIYOR: 'Ücretli sipariş: önce personel oda doğrulaması yapılmalı.',
    GECERSIZ_DURUM: 'Siparişin durumu bu işleme uygun değil.',
    FOLYO_KAPALI: 'Misafirin folyosu kapalı.',
    STOK_TUTARSIZ: 'Kayıtlı stok yetersiz — sayım gerekli.',
    IPTAL_NEDENI_GEREKLI: 'Neden yazılması zorunlu.',
    KULLANILAN_MIKTAR_GEREKLI: 'Hazırlanan siparişin her bileşeni için kullanılan miktarı girin (kullanılmadıysa 0).',
    KULLANILAN_MIKTAR_GECERSIZ: 'Kullanılan miktar 0 ile ayrılan miktar arasında olmalı.',
    KULLANIM_NEDENI_GEREKLI: 'Kullanılan miktar için neden seçin ("Diğer" ise açıklama yazın).',
    ISTISNA_YOK: 'İstisna kaydı bulunamadı.',
    COZUM_NOTU_GEREKLI: 'Tahsil edilemedi kararı için gerekçe zorunlu.',
    GECERSIZ_COZUM: 'Geçersiz çözüm seçimi.',
    REZERVE_STOK: 'Bu miktar bekleyen bar siparişlerine ayrılmış; stoktan düşülemez (sipariş teslim ya da iptal edilince tekrar deneyin).',
    SAYIM_YOK: 'Sayım bulunamadı.',
    SAYIM_EKSIK: 'Sayım eksik kaydedilmiş — yeniden kaydedilmeli.',
    BEKLEYEN_YOK: 'Bekleyen düzeltme bulunamadı.',
    SAYIM_ONAYI_SUNUCUDA: 'Bu ekran eski sürüm — sayfayı yenileyip sayımı yeniden onaylayın.',
    FOLYO_BASKA_KONAKLAMA: 'Seçilen folyo, siparişi doğrulanan konaklamaya ait değil. Borç başka misafire yazılamaz.',
    KONAKLAMA_BAGI_YOK: 'Bu istisnanın doğrulanmış konaklama bağı yok; borç folyoya yazılamaz.',
  };

  function govdeMesaji(metin) {
    if (metin == null) return '';
    const s = String(metin);
    try { const j = JSON.parse(s); return String(j.message || j.mesaj || j.hint || s); } catch (e) { return s; }
  }

  function hataKodunuBul(metin) {
    const m = govdeMesaji(metin).match(/\b([A-Z][A-Z_]{3,}):/);
    return m && METIN[m[1]] ? m[1] : null;
  }

  function hataMetni(metin, varsayilan) {
    const kod = hataKodunuBul(metin);
    if (kod) return METIN[kod];
    const g = govdeMesaji(metin);
    return g ? g.slice(0, 200) : (varsayilan || 'İşlem tamamlanamadı.');
  }

  kok.HATA_KODLARI = METIN;
  kok.hataKodunuBul = hataKodunuBul;
  kok.hataMetni = hataMetni;
  if (typeof module !== 'undefined' && module.exports) module.exports = { hataKodunuBul, hataMetni, HATA_KODLARI: METIN };
})(typeof window !== 'undefined' ? window : globalThis);
