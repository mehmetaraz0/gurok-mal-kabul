// ============================================================================
// HAZIRLIK KILIDI — yayin oncesi betikleri SABITLER
// ============================================================================
// NEDEN: Yayin karari, belirli dosyalarin belirli icerigi uzerinde verildi.
// Provalar, negatif yetki testleri ve preflight o baytlarla calistirildi. Bu
// betik o baytlari kayit altina alir ve sonra degistiklerinde GORUNUR yapar.
//
// Ozet, dosyanin LF'e normalize edilmis icerigi uzerinden alinir (depo
// core.autocrlf=true ile calistigi icin calisma kopyasi CRLF olabilir; yayin
// bayti commit edilen LF bayttir — yayin plani §0).
//
// KULLANIM:
//   node scripts/hazirlik-kilidi.mjs          -> dogrula (fark varsa cikis 1)
//   node scripts/hazirlik-kilidi.mjs --yaz    -> kilit dosyasini uret/guncelle
//
// Kilit dosyasi: docs/kurulum/2026-09-13-hazirlik-kilidi.json
// ============================================================================
import { readFileSync, writeFileSync, existsSync } from 'node:fs';
import { createHash } from 'node:crypto';

const kok = new URL('..', import.meta.url).pathname.replace(/^\/([A-Za-z]:)/, '$1');
const kilitYolu = kok + 'docs/kurulum/2026-09-13-hazirlik-kilidi.json';
const yaz = process.argv.includes('--yaz');

// Yayin penceresinde CALISTIRILACAK ya da yayin kararina KANIT ureten dosyalar.
// Yayin plani (md) canli belgedir; bilerek bu listede yoktur.
const DOSYALAR = [
  ['docs/kurulum/2026-09-09-pms-faz2-adim1-housekeeping.sql', 'Adim 1 migration (yayinda calisir)'],
  ['docs/kurulum/2026-09-10-pms-faz2-adim2-housekeeping-ui-destek.sql', 'Adim 2 migration (yayinda calisir)'],
  ['docs/kurulum/2026-09-11-pms-faz2-yayin-oncesi-preflight.sql', 'Yayin baslangici preflight (salt okuma)'],
  ['docs/kurulum/2026-09-13-yedek-dogrulama-sayaclari.sql', 'Yedek dogrulama sayaclari (salt okuma)'],
  ['docs/kurulum/yedek-snapshot-surucu.sql', 'Yedek + sayac surucusu (ayni snapshot)'],
  ['docs/kurulum/yedek-ve-sayac-al.ps1', 'Yedek alma otomasyonu'],
  ['docs/kurulum/dokum-al.ps1', 'Sema/referans dokumu alma'],
  ['scripts/supabase-shim.sql', 'Izole kopya iskelesi (provalarin tabani)'],
  ['scripts/pms-yedek-geri-yukleme-provasi.mjs', 'E-5 geri yukleme provasi'],
  ['scripts/pms-faz2-yetki-negatif.mjs', 'Negatif yetki testleri (K-9)'],
  ['scripts/pms-faz2-dogrudan-yazma-sondasi.mjs', 'Dogrudan yazma sondasi (§1.5, §5.5)'],
];

const ozet = (yol) => createHash('sha256')
  .update(Buffer.from(readFileSync(kok + yol, 'utf8').replace(/\r\n/g, '\n'), 'utf8'))
  .digest('hex');

if (yaz) {
  const kayit = {
    aciklama: 'PMS Faz 2 yayin hazirlik betikleri — LF icerik uzerinden SHA-256',
    olusturma: new Date().toISOString().slice(0, 10),
    dosyalar: DOSYALAR.map(([yol, ne]) => ({ yol, ne, sha256: ozet(yol) })),
  };
  writeFileSync(kilitYolu, JSON.stringify(kayit, null, 2) + '\n');
  console.log('Kilit yazildi: ' + kilitYolu + ' (' + kayit.dosyalar.length + ' dosya)');
  for (const d of kayit.dosyalar) console.log('  ' + d.sha256.slice(0, 16) + '…  ' + d.yol);
  process.exit(0);
}

if (!existsSync(kilitYolu)) {
  console.error('Kilit dosyasi yok. Once: node scripts/hazirlik-kilidi.mjs --yaz');
  process.exit(2);
}
const kilit = JSON.parse(readFileSync(kilitYolu, 'utf8'));
let sapma = 0;
const kilitliYollar = new Set(kilit.dosyalar.map((d) => d.yol));
for (const d of kilit.dosyalar) {
  if (!existsSync(kok + d.yol)) { console.log('EKSIK  ' + d.yol); sapma++; continue; }
  const simdi = ozet(d.yol);
  if (simdi === d.sha256) { console.log('AYNI   ' + d.yol); continue; }
  console.log('DEGISTI ' + d.yol);
  console.log('        kilit: ' + d.sha256);
  console.log('        simdi: ' + simdi);
  sapma++;
}
for (const [yol] of DOSYALAR) {
  if (!kilitliYollar.has(yol)) { console.log('KILITSIZ ' + yol + ' (listede var, kilitte yok)'); sapma++; }
}
console.log('\nHAZIRLIK KILIDI: ' + (sapma === 0
  ? kilit.dosyalar.length + ' dosya AYNI — yayin adayi sabit.'
  : sapma + ' sapma — degisiklik bilincli ise kilidi --yaz ile yenileyin ve provalari TEKRARLAYIN.'));
process.exit(sapma === 0 ? 0 : 1);
