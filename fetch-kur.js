// TCMB günlük döviz kurlarını çeker ve Supabase'e yazar.
// Bu script GitHub Actions üzerinde (sunucu tarafında) çalışır — tarayıcıda
// CORS engeline takılan TCMB isteği burada sorunsuz çalışır.

const SB_URL = 'https://xwytofysmgqtqjzkplfi.supabase.co';
// Service-role anahtarı GitHub Secret'tan (SUPABASE_SERVICE_ROLE_KEY) gelir — koda
// ASLA yazılmaz. RLS'i baypas ederek doviz_kurlari'na yazar. (Anon anahtar RLS'e
// takıldığı için kullanılamaz; anon'un yazamaması güvenlik açısından İSTENEN durum.)
const SERVICE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
if (!SERVICE_KEY) {
  console.error('❌ SUPABASE_SERVICE_ROLE_KEY ortam değişkeni yok. GitHub → Settings → '
    + 'Secrets and variables → Actions → New repository secret ile ekleyin.');
  process.exit(1);
}
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
      'apikey': SERVICE_KEY,
      'Authorization': 'Bearer ' + SERVICE_KEY,
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
