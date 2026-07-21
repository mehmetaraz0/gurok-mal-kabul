// nav-drawer.js — Gürok ERP paylaşılan uygulama-içi hızlı geçiş menüsü.
// index.html DIŞINDAKİ her modül sayfası bunu <head> içinde auth-guard.js
// ve supabase-config.js'den SONRA yükler. Her sayfanın header'ına bir
// hamburger düğmesi ekleyip, tüm modülleri listeleyen kaydırmalı bir
// yan panel açar — kullanıcı başka bir modüle geçmek için önce
// index.html'e dönmek zorunda kalmaz.

const ND_MODULLER = [
  {
    id: 'malkabul', ad: 'Mal Kabul', url: 'mal-kabul-v2.html',
    moduller: ['mal_kabul_form', 'mal_kabul_kalite'], durum: 'aktif',
    svg: '<path d="M9 3h6v3H9z"/><rect x="4" y="6" width="16" height="15" rx="1"/><path d="M8 12h8M8 16h5"/>',
    eslesir: f => f.startsWith('mal-kabul-') && f !== 'mal-kabul-izleme.html'
  },
  {
    id: 'stok', ad: 'Stok Takip', url: 'stok-takip.html',
    moduller: ['stok_takip'], durum: 'aktif',
    svg: '<path d="M21 8l-9-5-9 5v8l9 5 9-5V8z"/><path d="M3 8l9 5 9-5M12 13v8"/>',
    eslesir: f => f === 'stok-takip.html'
  },
  {
    id: 'depo-siparis', ad: 'Depo Siparişleri', url: 'depo-siparis.html',
    moduller: ['depo_siparis'], durum: 'aktif',
    svg: '<rect x="3" y="7" width="18" height="14" rx="1"/><path d="M8 7V5a2 2 0 012-2h4a2 2 0 012 2v2"/>',
    eslesir: f => f === 'depo-siparis.html'
  },
  {
    id: 'satinalma', ad: 'Satın Alma', url: 'satin-alma.html',
    moduller: ['ic_talep', 'siparis_olustur', 'siparis_takip', 'fiyat_kontrol', 'tedarikci_skorkart', 'firma_yonetimi'], durum: 'aktif',
    svg: '<circle cx="9" cy="20" r="1.4"/><circle cx="17" cy="20" r="1.4"/><path d="M3 4h2l2.2 11.4a2 2 0 002 1.6h7.6a2 2 0 002-1.6L21 8H6"/>',
    eslesir: f => f.startsWith('satin-alma')
  },
  {
    id: 'raporlar', ad: 'Raporlar', url: 'mal-kabul-izleme.html',
    moduller: ['mal_kabul_kalite'], durum: 'aktif',
    svg: '<path d="M4 20V10M12 20V4M20 20v-7"/>',
    eslesir: f => f === 'mal-kabul-izleme.html'
  },
  {
    id: 'yonetim', ad: 'Yönetim', url: 'kullanici-yonetimi.html',
    moduller: ['kullanici_yonetimi'], durum: 'aktif',
    svg: '<circle cx="12" cy="12" r="3"/><path d="M19.4 15a1.7 1.7 0 00.34 1.87l.06.06a2 2 0 11-2.83 2.83l-.06-.06a1.7 1.7 0 00-1.87-.34 1.7 1.7 0 00-1 1.55V21a2 2 0 01-4 0v-.09A1.7 1.7 0 008 19.4a1.7 1.7 0 00-1.87.34l-.06.06a2 2 0 11-2.83-2.83l.06-.06A1.7 1.7 0 004.6 15a1.7 1.7 0 00-1.55-1H3a2 2 0 010-4h.09A1.7 1.7 0 004.6 9a1.7 1.7 0 00-.34-1.87l-.06-.06a2 2 0 112.83-2.83l.06.06A1.7 1.7 0 008 4.6a1.7 1.7 0 001-1.55V3a2 2 0 014 0v.09a1.7 1.7 0 001 1.55 1.7 1.7 0 001.87-.34l.06-.06a2 2 0 112.83 2.83l-.06.06A1.7 1.7 0 0019.4 9c.14.36.55 1 1.55 1H21a2 2 0 010 4h-.09a1.7 1.7 0 00-1.51 1z"/>',
    eslesir: f => f === 'kullanici-yonetimi.html' || f === 'yetki-yonetimi.html'
  },
  {
    id: 'muhasebe', ad: 'Muhasebe', url: 'muhasebe.html',
    moduller: ['hesap_plani', 'cari_hesaplar', 'fatura_giris', 'fatura_onay', 'odeme_yapma', 'uc_yollu_eslestirme', 'yevmiye_fis_giris', 'yevmiye_fis_onay', 'banka_kasa', 'doviz_manuel', 'mizan_raporlar', 'denetim_izi', 'donem_kilitleme', 'demirbas_yonetimi', 'cek_senet_yonetimi', 'butce_yonetimi', 'sene_sonu_kapama', 'e_fatura', 'e_defter', 'muhasebe_asistan'], durum: 'aktif',
    svg: '<path d="M3 3v18h18"/><path d="M7 15l4-5 3 3 5-7"/>',
    eslesir: f => f.startsWith('muhasebe')
  },
  {
    id: 'gunlukTuketim', ad: 'Günlük Tüketim', url: 'gunluk-tuketim.html',
    moduller: ['gunluk_tuketim'], durum: 'aktif',
    svg: '<circle cx="12" cy="12" r="8.5"/><path d="M12 7.5V12l3 2.2"/>',
    eslesir: f => f === 'gunluk-tuketim.html'
  },
  {
    id: 'trendler', ad: 'Trendler', url: 'trend-raporlama.html',
    moduller: ['trend_raporlama'], durum: 'aktif',
    svg: '<path d="M3 17l5-5 4 4 8-9"/><path d="M15 7h5v5"/>',
    eslesir: f => f === 'trend-raporlama.html'
  },
  {
    id: 'urunYonetimi', ad: 'Ürün Yönetimi', url: 'urun-yonetimi.html',
    moduller: ['stok_takip'], durum: 'aktif',
    svg: '<path d="M20.5 7.5 12 3 3.5 7.5 12 12l8.5-4.5Z"/><path d="M3.5 7.5v9L12 21l8.5-4.5v-9"/><path d="M12 12v9"/>',
    eslesir: f => f === 'urun-yonetimi.html'
  }
];

function ndIkon(pathData) {
  return `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round">${pathData}</svg>`;
}

async function ndKur() {
  if (document.getElementById('nd-drawer')) return; // zaten kurulu
  const header = document.querySelector('.header');
  if (!header) return;
  const oturum = (typeof oturumGetir === 'function') ? oturumGetir() : null;
  if (!oturum) return; // requireLogin() zaten yönlendirmiş olacak

  // ---- CSS ----
  const style = document.createElement('style');
  style.textContent = `
#nd-overlay{display:none;position:fixed;inset:0;background:rgba(0,0,0,.5);z-index:10000}
#nd-overlay.open{display:block}
#nd-drawer{position:fixed;top:0;left:0;bottom:0;width:250px;max-width:82vw;background:var(--primary);z-index:10001;transform:translateX(-100%);transition:transform .22s ease;display:flex;flex-direction:column;box-shadow:2px 0 24px rgba(0,0,0,.35)}
#nd-drawer.open{transform:translateX(0)}
.nd-brand{display:flex;align-items:center;gap:10px;padding:20px 18px;border-bottom:1px solid rgba(255,255,255,.08);flex-shrink:0}
.nd-brand-mark{width:30px;height:30px;border-radius:7px;border:1px solid rgba(255,255,255,.3);display:flex;align-items:center;justify-content:center;font:700 13px -apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif;color:#fff;flex:none}
.nd-brand-txt{min-width:0}
.nd-brand-name{font-size:13px;font-weight:700;color:#fff;letter-spacing:.4px}
.nd-brand-sub{font-size:9.5px;font-weight:500;color:rgba(255,255,255,.45);margin-top:2px;text-transform:uppercase}
.nd-nav{flex:1;padding:12px 10px;display:flex;flex-direction:column;gap:2px;overflow-y:auto}
.nd-item{display:flex;align-items:center;gap:11px;padding:9px 12px;border-radius:6px;font-size:13px;font-weight:500;color:rgba(255,255,255,.72);text-decoration:none;border-left:2px solid transparent;background:none;border-top:none;border-right:none;border-bottom:none;cursor:pointer;width:100%;text-align:left;font-family:inherit}
.nd-item svg{width:15px;height:15px;flex:none;opacity:.85}
.nd-item:active,.nd-item:hover{background:rgba(255,255,255,.06);color:#fff}
.nd-item.active{background:rgba(255,255,255,.08);color:#fff;border-left-color:var(--accent)}
.nd-item.disabled{opacity:.4;pointer-events:none}
.nd-footer{padding:10px 18px 16px;font-size:10px;color:rgba(255,255,255,.35);flex-shrink:0}
.nd-hamburger{background:rgba(255,255,255,.15);border:none;color:inherit;width:34px;height:34px;border-radius:50%;cursor:pointer;display:flex;align-items:center;justify-content:center;flex-shrink:0}
.nd-hamburger svg{width:17px;height:17px}
.nd-hamburger:active{background:rgba(255,255,255,.3)}
`;
  document.head.appendChild(style);

  // ---- Hamburger düğmesi (header'ın en başına) ----
  const hbtn = document.createElement('button');
  hbtn.className = 'nd-hamburger';
  hbtn.title = 'Menü';
  hbtn.innerHTML = ndIkon('<path d="M4 7h16M4 12h16M4 17h16"/>');
  hbtn.onclick = ndAc;
  header.insertBefore(hbtn, header.firstChild);

  // ---- Overlay + panel ----
  const overlay = document.createElement('div');
  overlay.id = 'nd-overlay';
  overlay.onclick = ndKapat;

  const drawer = document.createElement('div');
  drawer.id = 'nd-drawer';
  drawer.innerHTML = `
    <div class="nd-brand">
      <div class="nd-brand-mark">G</div>
      <div class="nd-brand-txt"><div class="nd-brand-name">GÜROK</div><div class="nd-brand-sub">Depo Yönetimi</div></div>
    </div>
    <nav class="nd-nav" id="nd-nav"></nav>
    <div class="nd-footer">v1.0 · Gürok Turizm Grubu</div>`;

  document.body.appendChild(overlay);
  document.body.appendChild(drawer);

  document.addEventListener('keydown', e => { if (e.key === 'Escape') ndKapat(); });

  // ---- Modül listesi (yetkiye göre filtreli) ----
  const yetkiHaritasi = (typeof kullaniciYetkileriGetir === 'function') ? await kullaniciYetkileriGetir() : {};
  const izinliSeviyeler = ['goruntule', 'kayit', 'tam'];
  const gorunur = ND_MODULLER.filter(m => m.moduller.some(kod => izinliSeviyeler.includes(yetkiHaritasi[kod])));

  const dosyaAdi = location.pathname.split('/').pop().toLowerCase();
  const nav = document.getElementById('nd-nav');
  nav.innerHTML = `<a class="nd-item" href="index.html">${ndIkon('<path d="M3 11l9-7 9 7v9a1 1 0 01-1 1h-5v-6H9v6H4a1 1 0 01-1-1z"/>')}Ana Sayfa</a>` +
    gorunur.map(m => {
      const aktifMi = m.durum === 'aktif';
      const suankiMi = aktifMi && m.eslesir(dosyaAdi);
      if (!aktifMi) return `<span class="nd-item disabled">${ndIkon(m.svg)}${m.ad}</span>`;
      return `<a class="nd-item${suankiMi ? ' active' : ''}" href="${m.url}">${ndIkon(m.svg)}${m.ad}</a>`;
    }).join('');
}

function ndAc() {
  document.getElementById('nd-overlay').classList.add('open');
  document.getElementById('nd-drawer').classList.add('open');
}
function ndKapat() {
  document.getElementById('nd-overlay').classList.remove('open');
  document.getElementById('nd-drawer').classList.remove('open');
}

if (document.readyState === 'loading') {
  document.addEventListener('DOMContentLoaded', ndKur);
} else {
  ndKur();
}
