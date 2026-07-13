// efatura-adapter.js
// GİB onaylı entegratör (Paraşüt/Logo/Foriba/İzibiz/Uyumsoft vb.) API'sine bağlanana
// kadar simülasyon modunda çalışır. Gerçek API geldiğinde EFATURA_SIMULASYON=false
// yapılıp iki fonksiyonun gövdesi gerçek fetch() çağrılarıyla değiştirilir — çağıran
// taraf (muhasebe-faturalar.html) değişmez, çünkü dönüş şekli sabit kalıyor.
const EFATURA_SIMULASYON = true;

function _efaturaGecikme(ms) {
  return new Promise(r => setTimeout(r, ms));
}

function _efaturaSahteNo(prefix) {
  const yil = new Date().getFullYear();
  const sira = String(Math.floor(Math.random() * 999999999999)).padStart(12, '0');
  return `${prefix}${yil}${sira}`;
}

// fatura: camelCase fatura nesnesi ({tur, no, kalemler, ...}), cari: camelCase cari nesnesi ({efatura, ...})
async function eFaturaGonder(fatura, cari) {
  if (EFATURA_SIMULASYON) {
    await _efaturaGecikme(1500);
    if (Math.random() < 0.1) {
      return { basarili: false, hataMesaji: 'Simüle hata: entegratör yanıt vermedi', ettn: null, gibFaturaNo: null, pdfUrl: null, tip: null };
    }
    const tip = cari?.efatura === 'evet' ? 'e-fatura' : 'e-arsiv';
    return {
      basarili: true,
      ettn: crypto.randomUUID(),
      gibFaturaNo: _efaturaSahteNo(fatura.tur === 'satis' ? 'SAT' : 'ALI'),
      pdfUrl: `https://simulasyon.local/efatura/${crypto.randomUUID()}.pdf`,
      hataMesaji: null,
      tip
    };
  }
  throw new Error('Gerçek entegratör API entegrasyonu henüz yapılmadı');
}

// sonCekimTarihi: ms epoch veya null — simülasyonda kullanılmıyor, gerçek API'de "bu tarihten sonrakileri getir" için kullanılacak
async function eFaturaGelenleriCek(sonCekimTarihi) {
  if (EFATURA_SIMULASYON) {
    await _efaturaGecikme(1500);
    const adet = Math.floor(Math.random() * 3); // 0, 1 veya 2 sahte fatura
    const sonuc = [];
    for (let i = 0; i < adet; i++) {
      const birimFiyat = Math.round((Math.random() * 900 + 100) * 100) / 100;
      const miktar = Math.floor(Math.random() * 10) + 1;
      const kdvOran = 20;
      const araToplam = Math.round(birimFiyat * miktar * 100) / 100;
      const kdvToplam = Math.round(araToplam * kdvOran / 100 * 100) / 100;
      sonuc.push({
        ettn: crypto.randomUUID(),
        gibFaturaNo: _efaturaSahteNo('SIM'),
        gonderenVkn: String(Math.floor(1000000000 + Math.random() * 8999999999)),
        gonderenAd: 'Simülasyon Tedarikçi ' + (i + 1),
        tarih: new Date().toISOString().split('T')[0],
        kalemler: [{
          kod: '', ad: 'Simüle Ürün ' + (i + 1), miktar, birim: 'Adet',
          birimFiyat, kdvOran, toplam: araToplam + kdvToplam
        }],
        araToplam, kdvToplam, genelToplam: araToplam + kdvToplam
      });
    }
    return sonuc;
  }
  throw new Error('Gerçek entegratör API entegrasyonu henüz yapılmadı');
}
