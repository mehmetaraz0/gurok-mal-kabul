// scripts/check.mjs — Araz ERP statik doğrulama (framework'süz, sadece Node).
// CI ve yerel çalıştırma için: node scripts/check.mjs
// Kontroller:
//   1) Tüm kök .js dosyaları node --check ile sözdizimi denetimi
//   2) Modül sayfalarında paylaşılan script yükleme sırası
//      (auth-guard -> supabase-config -> otel-config -> ortak/onay-motoru)
//   3) UTC tarih tuzağı regülasyonu: toISOString() üzerinden gün damgası yasak
//   4) Bar müşteri-proje sabitlerinin sayfalara geri kopyalanmaması (tek kaynak bar-config.js)

import { execFileSync } from 'node:child_process';
import { readdirSync, readFileSync } from 'node:fs';
import { join } from 'node:path';

const root = new URL('..', import.meta.url).pathname.replace(/^\/([A-Za-z]:)/, '$1');
const errors = [];
const warn = [];

// ---- 1) Sözdizimi denetimi -------------------------------------------------
for (const f of readdirSync(root).filter(f => f.endsWith('.js'))) {
  try {
    execFileSync(process.execPath, ['--check', join(root, f)], { stdio: 'pipe' });
  } catch (e) {
    errors.push(`SÖZDIZIMI HATASI ${f}: ${String(e.stderr).slice(0, 300)}`);
  }
}

// ---- 2) HTML script yükleme sırası -----------------------------------------
const htmls = readdirSync(root).filter(f => f.endsWith('.html'));
const GROUPS = [['auth-guard.js'], ['supabase-config.js'], ['otel-config.js'], ['ortak.js', 'onay-motoru.js']];
for (const f of htmls) {
  const src = readFileSync(join(root, f), 'utf8');
  const head = src.slice(0, src.indexOf('</head>') > -1 ? src.indexOf('</head>') : src.length);
  const ranks = GROUPS
    .map(g => g.map(s => head.indexOf(`<script src="${s}"`)).filter(i => i > -1))
    .filter(g => g.length)
    .map(g => Math.min(...g));
  if (ranks.length < 2) continue;
  if (JSON.stringify(ranks) !== JSON.stringify([...ranks].sort((a, b) => a - b))) {
    errors.push(`YÜKLEME SIRASI BOZUK ${f}: beklenen ${GROUPS.map(g => g.join('|')).join(' -> ')}`);
  }
  if (!src.includes('requireLogin') && !src.includes('bar-config.js') && f !== 'index.html') {
    warn.push(`requireLogin yok: ${f} (oturum koruması olmadan açılıyor — kasıtlıysa yok sayın)`);
  }
}

// ---- 3) UTC tarih tuzağı ---------------------------------------------------
const UTC_PATTERNS = [/toISOString\(\)\.split\('T'\)\[0\]/g, /toISOString\(\)\.slice\(0,\s*10\)/g];
for (const f of [...htmls, ...readdirSync(root).filter(f => f.endsWith('.js') && f !== 'check.mjs')]) {
  const lines = readFileSync(join(root, f), 'utf8').split('\n');
  lines.forEach((line, i) => {
    if (line.trim().startsWith('//')) return;
    for (const p of UTC_PATTERNS) {
      if (p.test(line)) errors.push(`UTC TARİH TUZAĞI ${f}:${i + 1} — yerelTarihStr()/bugunYerelStr() kullanın: ${line.trim().slice(0, 120)}`);
      p.lastIndex = 0;
    }
  });
}

// ---- 4) Bar sabit tek kaynağı ---------------------------------------------
for (const f of htmls) {
  const src = readFileSync(join(root, f), 'utf8');
  if (/const\s+CUSTOMER_SB_URL|const\s+CUSTOMER_ANON_KEY/.test(src)) {
    errors.push(`BAR SABİT İKİLEMESİ ${f}: CUSTOMER_* sabitleri bar-config.js'ten yüklenmeli, sayfada tanımlanmamalı`);
  }
  if (src.includes('CUSTOMER_SB_URL') && !src.includes('bar-config.js') && f !== 'docs') {
    // bar-config yüklenmeden CUSTOMER_* kullanan sayfa
  }
}

console.log(`Taranan: ${readdirSync(root).filter(f => f.endsWith('.js')).length} .js + ${htmls.length} .html`);
for (const w of warn) console.log('UYARI: ' + w);
if (errors.length) {
  for (const e of errors) console.error('HATA: ' + e);
  console.error(`\n${errors.length} hata — düzeltin.`);
  process.exit(1);
}
console.log('Tüm statik kontroller geçti.');
