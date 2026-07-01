// TCMB günlük döviz kurlarını çeker ve Firebase'e yazar.
// Bu script GitHub Actions üzerinde (sunucu tarafında) çalışır — tarayıcıda
// CORS engeline takılan TCMB isteği burada sorunsuz çalışır.

const FB = 'https://gurok-mal-kabul-default-rtdb.europe-west1.firebasedatabase.app';
const PARA_BIRIMLERI = ['USD', 'EUR', 'GBP'];

function get(block, tag) {
  const m = block.match(new RegExp(`<${tag}>([^<]*)</${tag}>`));
  if (!m) return null;
  const v = parseFloat(m[1].replace(',', '.'));
  return isNaN(v) ? null : v;
}

async function main() {
  const res = await fetch('https://www.tcmb.gov.tr/kurlar/today.xml');
  if (!res.ok) {
    throw new Error(`TCMB isteği başarısız: HTTP ${res.status}`);
  }
  // TCMB XML'i ISO-8859-9 (Windows-1254) kodlamasında; sayısal alanlar ASCII
  // olduğu için varsayılan utf-8 çözümlemesi rakamları etkilemez.
  const xml = await res.text();

  const tarihMatch = xml.match(/Tarih="([^"]+)"/);
  if (!tarihMatch) throw new Error('XML içinde Tarih bulunamadı — TCMB format değiştirmiş olabilir');
  const tarihStr = tarihMatch[1]; // "01.07.2026"
  const [gg, aa, yyyy] = tarihStr.split('.');
  const tarihKey = `${yyyy}-${aa}-${gg}`; // "2026-07-01"

  const kurlar = {};
  for (const kod of PARA_BIRIMLERI) {
    const blockRegex = new RegExp(`<Currency[^>]*Kod="${kod}"[^>]*>([\\s\\S]*?)</Currency>`);
    const blockMatch = xml.match(blockRegex);
    if (!blockMatch) {
      console.warn(`⚠️ ${kod} için kur bulunamadı, atlanıyor`);
      continue;
    }
    const block = blockMatch[1];
    kurlar[kod] = {
      dovizAlis: get(block, 'ForexBuying'),
      dovizSatis: get(block, 'ForexSelling'),
      efektifAlis: get(block, 'BanknoteBuying'),
      efektifSatis: get(block, 'BanknoteSelling'),
    };
  }

  if (Object.keys(kurlar).length === 0) {
    throw new Error('Hiçbir para birimi ayrıştırılamadı — TCMB XML formatı değişmiş olabilir');
  }

  const payload = {
    tarih: tarihKey,
    tarihStr,
    kurlar,
    kaynak: 'TCMB',
    guncellemeTarih: Date.now(),
  };

  const put = async (path) => {
    const r = await fetch(`${FB}${path}.json`, {
      method: 'PUT',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(payload),
    });
    if (!r.ok) throw new Error(`Firebase yazma hatası (${path}): HTTP ${r.status}`);
  };

  // Günlük arşiv kaydı + her zaman en güncel kur olarak okunacak tekil kayıt
  await put(`/muhasebe/kurlar/gunluk/${tarihKey}`);
  await put('/muhasebe/kurlar/guncel');

  console.log(`✅ Kur güncellendi: ${tarihKey}`);
  console.log(JSON.stringify(kurlar, null, 2));
}

main().catch((e) => {
  console.error('❌ Hata:', e.message);
  process.exit(1);
});
