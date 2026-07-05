// TCMB günlük döviz kurlarını çeker ve Supabase'e yazar.
// Bu script GitHub Actions üzerinde (sunucu tarafında) çalışır — tarayıcıda
// CORS engeline takılan TCMB isteği burada sorunsuz çalışır.

const SB_URL = 'https://xwytofysmgqtqjzkplfi.supabase.co';
const SB_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Inh3eXRvZnlzbWdxdHFqemtwbGZpIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODMyMjg5ODMsImV4cCI6MjA5ODgwNDk4M30.E7cRcOAvCmUFXWs45t4HE-igpmqWmSN2J66dOuvCHjA';
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

  const satirlar = [];
  for (const kod of PARA_BIRIMLERI) {
    const blockRegex = new RegExp(`<Currency[^>]*Kod="${kod}"[^>]*>([\\s\\S]*?)</Currency>`);
    const blockMatch = xml.match(blockRegex);
    if (!blockMatch) {
      console.warn(`⚠️ ${kod} için kur bulunamadı, atlanıyor`);
      continue;
    }
    const block = blockMatch[1];
    const dovizAlis = get(block, 'ForexBuying');
    if (dovizAlis === null) {
      console.warn(`⚠️ ${kod} için ForexBuying ayrıştırılamadı, atlanıyor`);
      continue;
    }
    satirlar.push({
      tarih: tarihKey,
      para_birimi: kod,
      doviz_alis: dovizAlis,
      doviz_satis: get(block, 'ForexSelling'),
      efektif_alis: get(block, 'BanknoteBuying'),
      efektif_satis: get(block, 'BanknoteSelling'),
      kaynak: 'TCMB',
    });
  }

  if (satirlar.length === 0) {
    throw new Error('Hiçbir para birimi ayrıştırılamadı — TCMB XML formatı değişmiş olabilir');
  }

  const r = await fetch(`${SB_URL}/rest/v1/doviz_kurlari?on_conflict=tarih,para_birimi`, {
    method: 'POST',
    headers: {
      'apikey': SB_KEY,
      'Authorization': 'Bearer ' + SB_KEY,
      'Content-Type': 'application/json',
      'Prefer': 'resolution=merge-duplicates',
    },
    body: JSON.stringify(satirlar),
  });
  if (!r.ok) {
    const t = await r.text();
    throw new Error(`Supabase yazma hatası: HTTP ${r.status} — ${t.slice(0, 300)}`);
  }

  console.log(`✅ Kur güncellendi: ${tarihKey}`);
  console.log(JSON.stringify(satirlar, null, 2));
}

main().catch((e) => {
  console.error('❌ Hata:', e.message);
  process.exit(1);
});
