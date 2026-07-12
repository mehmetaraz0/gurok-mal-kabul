// auth-guard.js — Gürok ERP paylaşılan oturum/erişim kontrolü.
// index.html DIŞINDAKİ her modül sayfası bunu <head> içinde en üstte,
// senkron olarak yükler (<script src="auth-guard.js"></script> — defer/async YOK,
// sayfa gövdesi render edilmeden önce çalışmalı).

const SESSION_KEY = 'gurok_portal_session';
const SESSION_SURESI_MS = 30 * 60 * 1000;
const PIN_KILIT_ANAHTAR = 'gurok_pin_kilit';

function oturumGetir() {
  try {
    const s = sessionStorage.getItem(SESSION_KEY);
    if (!s) return null;
    const { user, expiry } = JSON.parse(s);
    if (!user || Date.now() >= expiry) return null;
    return user;
  } catch (e) { return null; }
}

function oturumKaydet(user) {
  sessionStorage.setItem(SESSION_KEY, JSON.stringify({ user, expiry: Date.now() + SESSION_SURESI_MS }));
}

// index.html DIŞINDAKİ sayfalar bunu çağırır. Oturum geçerliyse kullanıcıyı döner.
// Değilse index.html'e (geri dönüş adresiyle) yönlendirir ve null döner — çağıran
// kod null aldığında HİÇBİR ŞEY YAPMADAN durmalı (yönlendirme zaten gerçekleşti).
function requireLogin() {
  const user = oturumGetir();
  if (user) return user;
  const donusUrl = location.pathname.split('/').pop() + location.search + location.hash;
  location.replace('index.html?returnTo=' + encodeURIComponent(donusUrl));
  return null;
}

// Geçerli oturumu olan ama rolü yetersiz kullanıcı için — YÖNLENDİRME YAPMAZ
// (zaten giriş yapmış, index.html'e göndermek sonsuz döngü yaratır). Sadece
// erişimi reddeder ve body'yi bir "kapalı" mesajıyla değiştirir.
function requireRole(user, izinliRoller) {
  if (izinliRoller.includes(user.rol)) return true;
  document.body.innerHTML = `
    <div style="min-height:100vh;display:flex;align-items:center;justify-content:center;background:#f1f3f5;font-family:-apple-system,'Segoe UI',sans-serif;padding:20px">
      <div style="background:white;border-radius:16px;padding:32px 28px;max-width:340px;text-align:center;box-shadow:0 8px 40px rgba(0,0,0,.15)">
        <div style="font-size:40px;margin-bottom:12px">🔒</div>
        <div style="font-weight:700;color:#1a2744;margin-bottom:8px">Bu modül sana kapalı</div>
        <div style="font-size:13px;color:#6c757d;margin-bottom:20px">Hesabının rolü (${user.rol}) bu sayfayı açmaya yetmiyor.</div>
        <a href="index.html" style="display:inline-block;background:#1a2744;color:white;padding:10px 20px;border-radius:8px;text-decoration:none;font-size:13px;font-weight:600">Portala Dön</a>
      </div>
    </div>`;
  return false;
}

// PIN deneme sınırlaması — 5 hatalı denemeden sonra artan sürelerle (30sn, 60sn,
// ... en fazla 5dk) kilitlenir. Sadece index.html'in PIN ekranı kullanır.
function pinKilitliMi() {
  try {
    const s = JSON.parse(localStorage.getItem(PIN_KILIT_ANAHTAR) || '{}');
    if (s.kilitSonu && Date.now() < s.kilitSonu) return Math.ceil((s.kilitSonu - Date.now()) / 1000);
  } catch (e) {}
  return 0;
}
function pinBasarisizKaydet() {
  let s = {};
  try { s = JSON.parse(localStorage.getItem(PIN_KILIT_ANAHTAR) || '{}'); } catch (e) {}
  s.deneme = (s.deneme || 0) + 1;
  if (s.deneme >= 5) s.kilitSonu = Date.now() + Math.min(300000, 30000 * Math.pow(2, s.deneme - 5));
  localStorage.setItem(PIN_KILIT_ANAHTAR, JSON.stringify(s));
}
function pinBasariliTemizle() { localStorage.removeItem(PIN_KILIT_ANAHTAR); }
