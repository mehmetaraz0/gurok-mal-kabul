// scripts/canli-sonda.mjs — Araz ERP canlı güvenlik sondası (salt-okunur).
//
// NEDEN VAR (N-5 / drift):
// 2026-09-01 bağımsız denetiminde iki "bulgu" çıktı, ikisi de yanlış alarmdı;
// sebep aynıydı: repo SQL'leri canlının gerisinde. Repo bir NİYET kaydıdır
// ("şu grant'i ver"), canlı DB ise GERÇEĞİN kaynağı. Bir dosyada
// `grant ... to anon` durması o grant'in hâlâ geçerli olduğunu göstermez.
// Tersi de yaşandı: yorum satırında bırakılmış bir revoke haftalarca
// uygulanmadı ve onay motorunu atlanabilir bıraktı.
// Bu script repoya değil CANLIYA sorar.
//
// SIR GEREKTİRMEZ: kullandığı anon anahtarı tasarım gereği publictir
// (supabase-config.js her tarayıcıya gidiyor). Anahtar TEK KAYNAKTAN okunur.
//
// ⚠️ KAPSAM SINIRI — DÜRÜSTÇE:
// Bu sonda her şeyi doğrulayamaz. GET ile bir RPC'yi sondalarken üç farklı
// davranış var ve yalnız ikisi yorumlanabilir:
//   • argümansız fonksiyon  → 42501 "for function" = KAPALI, 200 = AÇIK  ✅
//   • STABLE + argüman verilir → 200 = AÇIK, 42501 = KAPALI              ✅
//   • VOLATILE + argümanlı (yazma RPC'leri) → argümansız GET her zaman
//     PGRST202 "imza bulunamadı" döner; bu izin hakkında HİÇBİR ŞEY
//     söylemez. Bunları POST ile denemek fonksiyonu ÇALIŞTIRIR (yan etki).  ❌
// Yani `mal_kabul_kaydet`, `talep_karar_ver` gibi yazma RPC'lerinin izinleri
// BURADAN doğrulanamaz — onlar için `docs/kurulum/2026-08-23-sistemik-rls-
// denetim.sql` içindeki has_function_privilege sorgusu (SQL Editor) gerekir.
// Bu script o sorgunun yerine GEÇMEZ, onun tamamlayıcısıdır.
//
// Çalıştırma: node scripts/canli-sonda.mjs   ·   Çıkış: 0 sağlam / 1 gerileme

import { readFileSync } from 'node:fs';

const root = new URL('..', import.meta.url).pathname.replace(/^\/([A-Za-z]:)/, '$1');
const cfg = readFileSync(root + 'supabase-config.js', 'utf8');
const URL_ = cfg.match(/const SB_URL\s*=\s*'([^']+)'/)?.[1];
const KEY = cfg.match(/const SB_KEY\s*=\s*'([^']+)'/)?.[1];
if (!URL_ || !KEY) { console.error('supabase-config.js icinden SB_URL/SB_KEY okunamadi'); process.exit(1); }

const H = { apikey: KEY, Authorization: 'Bearer ' + KEY };
const hata = [], degisim = [];

const gov = async (yol) => {
  const r = await fetch(URL_ + yol, { headers: H });
  return { s: r.status, t: await r.text().catch(() => '') };
};
// 42501 iki ayri sey olabilir: "for function" = EXECUTE yok (kapali);
// "for table/relation" = fonksiyon CALISTI, icerde takildi (yani ACIK).
const kapaliMi = ({ s, t }) => s !== 200 && /permission denied for function/i.test(t);

// --- 1) Hicbir tablo anon'a okunabilir olmamali -----------------------------
// 2026-08-09'da 56 tablonun tamami anon'dan alindi + alter default privileges.
// Buradaki bir 200: ya o ayar tutmadi ya yeni bir tablo acik geldi.
const TABLOLAR = ['urunler','stok','stok_hareketleri','satin_alma_talepleri','siparisler','siparis_kalemleri',
  'faturalar','fatura_kalemleri','yevmiye_fisler','yevmiye_kalemleri','cariler','cari_hareketler','kullanicilar',
  'kullanicilar_genel','yetki_matrisi','roller','moduller','mal_kabuller','mal_kabul_urunleri','bar_siparisleri',
  'menu_urunler','stok_rezervasyonlari','audit_log','giris_kayitlari','kayitli_filtreler','urun_birim_donusum'];
for (const t of TABLOLAR) {
  const r = await fetch(`${URL_}/rest/v1/${t}?select=*&limit=1`, { headers: H });
  if (r.status === 200) hata.push(`TABLO ANON'A ACIK: ${t}`);
}

// --- 2) Argümansız fonksiyonlar: KAPALI olmali ------------------------------
for (const fn of ['auth_erp_kullanicisi', 'auth_kullanici_rol_id', 'rls_auto_enable']) {
  const r = await gov(`/rest/v1/rpc/${fn}`);
  if (r.t.includes('PGRST202')) continue;            // anon'a hic gorunmuyor
  if (!kapaliMi(r)) hata.push(`RPC ANON'A ACIK: ${fn} (HTTP ${r.s}) ${r.t.slice(0, 80)}`);
}

// --- 3) Bilinçli açık bırakılanlar: DEĞİŞTİ Mİ? -----------------------------
// Bu yardimcilar RLS politikalarinin ICINDEN cagriliyor ve anon'a false/null
// donuyorlar; acik olmalari bilincli karardir. Burasi hata degil DEGISIM
// detektorudur — biri kapanirsa bir politika sessizce kirilmis olabilir.
const ACIK_BEKLENEN = [
  ['auth_yetki_var', '?p_modul_kod=stok_takip'],
  ['auth_otel_erisim', '?p_otel=810'],
  ['auth_kullanici_id', ''], ['auth_otel_id', ''], ['auth_tum_oteller', ''],
];
for (const [fn, q] of ACIK_BEKLENEN) {
  const r = await gov(`/rest/v1/rpc/${fn}${q}`);
  if (r.s !== 200) degisim.push(`${fn} artik anon'a KAPALI (beklenen: acik) — HTTP ${r.s}`);
}

// --- 4) Self-signup kapali olmali -------------------------------------------
// 2026-08-09'da acikti + otomatik onay vardi: herkes saniyeler icinde
// dogrulanmis bir 'authenticated' JWT alabiliyordu.
try {
  const s = await (await fetch(`${URL_}/auth/v1/settings`, { headers: { apikey: KEY } })).json();
  if (s.disable_signup !== true) hata.push('SELF-SIGNUP ACIK (disable_signup !== true)');
  if (s.mailer_autoconfirm === true && s.disable_signup !== true) hata.push('E-POSTA DOGRULAMASI KAPALI + kayit acik');
} catch (e) { degisim.push('auth ayarlari okunamadi: ' + e.message); }

// ---------------------------------------------------------------------------
console.log(`Sondalandi: ${TABLOLAR.length} tablo, 8 RPC, auth ayarlari`);
console.log('NOT: yazma RPC\'lerinin (VOLATILE) izinleri GET ile dogrulanamaz —');
console.log('     bunlar icin docs/kurulum/2026-08-23-sistemik-rls-denetim.sql calistirilmali.');
degisim.forEach(d => console.log('  DEGISIM: ' + d));
if (hata.length) {
  console.error(`\n${hata.length} GERILEME:`);
  hata.forEach(h => console.error('  - ' + h));
  process.exit(1);
}
console.log('Sondalanabilen tum degismezler saglam.');
