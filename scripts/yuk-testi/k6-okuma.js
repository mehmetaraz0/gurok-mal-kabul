// scripts/yuk-testi/k6-okuma.js — Dornevi okuma yükü testi (k6)
//
// ⚠️ SALT-OKUMA. Bu betik hiçbir veri YAZMAZ, DEĞİŞTİRMEZ, SİLMEZ.
//    Yazma senaryoları bilerek dahil edilmemiştir; üretim veritabanında
//    yük testi amacıyla kayıt üretmek, gerçek iş verisini kirletir ve
//    stok/onay gibi durum makinelerini tutarsız bırakabilir.
//    Yazma performansı ölçülecekse AYRI bir kopya proje üzerinde yapılmalı.
//
// ⚠️ OTURUM: Betik PIN ile giriş YAPMAZ. Sebebi kasıtlı:
//    giriş akışı sunucu tarafında hız sınırlamasına tabidir (IP başına
//    15 dk'da 10 başarısız + IP'den bağımsız genel tavan) ve her giriş
//    denemesi giris_denemeleri / giris_kayitlari tablolarına satır yazar.
//    Yük testi bunları hem tetikler hem kirletir. Bunun yerine ELDE
//    HAZIR bir JWT dışarıdan verilir — gerçek kullanıcı davranışı da
//    budur: bir kez giriş yapılır, oturum boyunca aynı jeton kullanılır.
//
// KULLANIM
//   1) Uygulamada giriş yap, tarayıcı konsolunda:
//        JSON.parse(sessionStorage.getItem('araz_portal_session')).accessToken
//   2) k6 run -e JWT="<jeton>" scripts/yuk-testi/k6-okuma.js
//
//   Seçenekler:
//     -e SB_URL=...        (varsayılan: supabase-config.js'teki proje)
//     -e VU=10             eşzamanlı sanal kullanıcı (varsayılan 5)
//     -e SURE=2m           yük süresi (varsayılan 1m)
//
// ⚠️ JETON KISA ÖMÜRLÜDÜR (uygulama oturumu 30 dk). Uzun koşularda
//    süre dolarsa istekler 401 döner ve sonuç ANLAMSIZ olur — hata
//    oranı eşiği bunu yakalar, ama koşu öncesi taze jeton al.

import http from 'k6/http';
import { check, group, sleep } from 'k6';
import { Trend, Rate } from 'k6/metrics';

const SB_URL = __ENV.SB_URL || 'https://xwytofysmgqtqjzkplfi.supabase.co';
const JWT = __ENV.JWT;
const VU = parseInt(__ENV.VU || '5', 10);
const SURE = __ENV.SURE || '1m';

// Anon anahtarı apikey başlığı için gerekir (tasarım gereği public).
// Yetkiyi apikey değil JWT belirler.
const ANON = __ENV.ANON || 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Inh3eXRvZnlzbWdxdHFqemtwbGZpIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODMyMjg5ODMsImV4cCI6MjA5ODgwNDk4M30.E7cRcOAvCmUFXWs45t4HE-igpmqWmSN2J66dOuvCHjA';

// Akış bazlı metrikler — tek bir "http_req_duration" ortalaması yanıltıcıdır;
// hangi ekranın yavaş olduğunu ayrı ayrı görmek gerekir.
const mPortal = new Trend('akis_portal_acilis', true);
const mStok = new Trend('akis_stok_listesi', true);
const mMalKabul = new Trend('akis_mal_kabul_listesi', true);
const mSiparis = new Trend('akis_siparis_takip', true);
const mMuhasebe = new Trend('akis_muhasebe_yevmiye', true);
const bosYanit = new Rate('bos_yanit_orani');

export const options = {
  scenarios: {
    kademeli: {
      executor: 'ramping-vus',
      startVUs: 1,
      stages: [
        { duration: '20s', target: VU },   // ısınma
        { duration: SURE, target: VU },    // sabit yük — ölçüm burası
        { duration: '15s', target: 0 },    // soğuma
      ],
      gracefulRampDown: '15s',
    },
  },
  // Eşikler = geçti/kaldı kararı. Bir zincire sunulacak raporun
  // "iyi görünüyor" değil, tanımlı bir kabul kriterine göre
  // değerlendirilmiş olması gerekir.
  thresholds: {
    'http_req_failed': ['rate<0.01'],                 // %1'den az hata
    'http_req_duration': ['p(95)<1500', 'p(99)<3000'],
    'akis_portal_acilis': ['p(95)<2000'],
    'akis_stok_listesi': ['p(95)<2500'],
    'akis_mal_kabul_listesi': ['p(95)<2500'],
    'akis_siparis_takip': ['p(95)<2500'],
    'akis_muhasebe_yevmiye': ['p(95)<3000'],
    'bos_yanit_orani': ['rate<0.05'],                 // bkz. setup notu
  },
};

const H = () => ({
  headers: {
    apikey: ANON,
    Authorization: 'Bearer ' + JWT,
    'Content-Type': 'application/json',
    Accept: 'application/json',
  },
});

export function setup() {
  if (!JWT) {
    throw new Error(
      'JWT verilmedi. Uygulamada giris yapip konsoldan alin:\n' +
      "  JSON.parse(sessionStorage.getItem('araz_portal_session')).accessToken\n" +
      '  k6 run -e JWT="<jeton>" scripts/yuk-testi/k6-okuma.js'
    );
  }
  // Jeton gerçekten geçerli mi? Geçersiz jetonla koşmak, "hızlı ama
  // hepsi 401" gibi sahte-iyi bir sonuç üretir — koşu öncesi doğrula.
  const r = http.get(`${SB_URL}/rest/v1/moduller?select=kod&limit=1`, H());
  if (r.status !== 200) {
    throw new Error(`JWT gecersiz veya suresi dolmus (HTTP ${r.status}): ${r.body}`);
  }
  return { baslangic: new Date().toISOString() };
}

// Sorgular uygulamanın GERÇEKTE yaptığı isteklerden alınmıştır
// (kaynak taraması, en sık çağrılan okuma sorguları).
function olc(trend, ad, url) {
  const r = http.get(url, Object.assign({ tags: { akis: ad } }, H()));
  trend.add(r.timings.duration);
  const ok = check(r, {
    [`${ad}: HTTP 200`]: (x) => x.status === 200,
    [`${ad}: JSON dizi`]: (x) => {
      try { return Array.isArray(x.json()); } catch (e) { return false; }
    },
  });
  // RLS doğru çalışırken bile boş dönebilir; ama TOPLU boşluk,
  // yetkinin çözülemediğine (bayat jeton, kopuk politika) işarettir.
  if (ok) {
    try { bosYanit.add(r.json().length === 0); } catch (e) { bosYanit.add(true); }
  }
  return r;
}

export default function () {
  group('Portal açılışı', () => {
    olc(mPortal, 'yetki_matrisi', `${SB_URL}/rest/v1/moduller?select=kod,ad,aktif&aktif=eq.true`);
    olc(mPortal, 'bekleyen_talep', `${SB_URL}/rest/v1/satin_alma_talepleri?durum=eq.bekleyen&select=id`);
    olc(mPortal, 'skt_uyari', `${SB_URL}/rest/v1/skt_kayitlari?durum=eq.aktif&select=skt_tarihi&limit=100`);
  });
  sleep(1);

  group('Stok Takip', () => {
    olc(mStok, 'stok_listesi', `${SB_URL}/rest/v1/stok?select=*&limit=500`);
    olc(mStok, 'urun_fiyat', `${SB_URL}/rest/v1/urun_guncel_fiyat?select=urun_kodu,birim_fiyat,birim&limit=500`);
    olc(mStok, 'birim_donusum', `${SB_URL}/rest/v1/urun_birim_donusum?select=urun_kodu,buyuk_birim,carpan&silindi=eq.false`);
  });
  sleep(1);

  group('Mal Kabul Listesi', () => {
    // İç içe seçim (nested select) — en pahalı okuma deseni, ayrı ölçülmeli
    olc(mMalKabul, 'mal_kabul_nested', `${SB_URL}/rest/v1/mal_kabuller?select=*,mal_kabul_urunleri(*)&order=tarih.desc&limit=50`);
    olc(mMalKabul, 'cariler', `${SB_URL}/rest/v1/cariler?select=*&silindi=eq.false&limit=300`);
  });
  sleep(1);

  group('Sipariş Takip', () => {
    olc(mSiparis, 'siparis_nested', `${SB_URL}/rest/v1/siparisler?select=*,siparis_kalemleri(*)&limit=50`);
  });
  sleep(1);

  group('Muhasebe — Yevmiye', () => {
    olc(mMuhasebe, 'yevmiye_nested', `${SB_URL}/rest/v1/yevmiye_fisler?select=id,tarih,otel_id,yevmiye_kalemleri(hesap_kodu,borc,alacak)&silindi=eq.false&limit=100`);
    olc(mMuhasebe, 'mali_donem', `${SB_URL}/rest/v1/mali_donemler?select=*`);
  });
  sleep(2); // kullanıcı düşünme süresi
}

export function handleSummary(data) {
  const m = data.metrics;
  const p = (ad, q) => {
    const v = m[ad] && m[ad].values ? m[ad].values[q] : null;
    return v == null ? '—' : Math.round(v) + ' ms';
  };
  const satir = (ad, etiket) =>
    `| ${etiket} | ${p(ad, 'p(95)')} | ${p(ad, 'p(99)')} | ${p(ad, 'med')} |`;

  const rapor = [
    '# Dornevi — Yük Testi Sonucu',
    '',
    `Tarih: ${new Date().toISOString()}`,
    `Eşzamanlı kullanıcı (VU): ${VU} · Sabit yük süresi: ${SURE}`,
    `Hedef: ${SB_URL}`,
    '',
    '## Akış bazlı yanıt süreleri',
    '',
    '| Akış | p95 | p99 | medyan |',
    '|---|---|---|---|',
    satir('akis_portal_acilis', 'Portal açılışı'),
    satir('akis_stok_listesi', 'Stok Takip'),
    satir('akis_mal_kabul_listesi', 'Mal Kabul Listesi'),
    satir('akis_siparis_takip', 'Sipariş Takip'),
    satir('akis_muhasebe_yevmiye', 'Muhasebe — Yevmiye'),
    '',
    '## Genel',
    '',
    `- Toplam istek: ${m.http_reqs ? m.http_reqs.values.count : '—'}`,
    `- Hata oranı: ${m.http_req_failed ? (m.http_req_failed.values.rate * 100).toFixed(2) + ' %' : '—'}`,
    `- Tüm istekler p95: ${p('http_req_duration', 'p(95)')} · p99: ${p('http_req_duration', 'p(99)')}`,
    `- Boş yanıt oranı: ${m.bos_yanit_orani ? (m.bos_yanit_orani.values.rate * 100).toFixed(2) + ' %' : '—'}`,
    '',
    '## Yorum notları',
    '',
    '- Bu koşu **salt-okumadır**; yazma performansını temsil etmez.',
    '- Ölçüm, uygulamanın gerçekte yaptığı sorgularla yapılmıştır.',
    '- Coğrafi gecikme sonucun parçasıdır: yükün üretildiği yer ile',
    '  veritabanı bölgesi arasındaki mesafe p95/p99 değerlerine doğrudan',
    '  yansır. Rapor sunulurken her ikisi de belirtilmelidir.',
    '- Barındırma planı kapasite tavanını belirler; plan değişirse bu',
    '  sonuçlar geçersizdir ve koşu tekrarlanmalıdır.',
    '',
  ].join('\n');

  return {
    'stdout': '\n' + rapor + '\n',
    'scripts/yuk-testi/sonuc-ozet.md': rapor,
    'scripts/yuk-testi/sonuc-ham.json': JSON.stringify(data, null, 2),
  };
}
