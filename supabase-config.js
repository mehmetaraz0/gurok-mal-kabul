// supabase-config.js — Araz ERP paylaşılan Supabase bağlantı sabitleri.
// Sayfalar bunu <head> içinde auth-guard.js'den SONRA, senkron olarak yükler
// (ortak.js/onay-motoru.js/efatura-adapter.js gibi SB_URL/SB_HEADERS'a
// bağımlı diğer paylaşılan dosyalardan ÖNCE gelmeli).
//
// SB_KEY, Supabase anon (public) anahtarı — tasarım gereği istemci tarafında
// açık; güvenlik bu anahtarı gizlemekle değil RLS politikalarıyla sağlanır.

const SB_URL='https://xwytofysmgqtqjzkplfi.supabase.co';
const SB_KEY='eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Inh3eXRvZnlzbWdxdHFqemtwbGZpIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODMyMjg5ODMsImV4cCI6MjA5ODgwNDk4M30.E7cRcOAvCmUFXWs45t4HE-igpmqWmSN2J66dOuvCHjA';
// Authorization bir GETTER'dır: her fetch'te oturumAccessTokenGetir() yeniden
// okunur. Eski IIFE sürümü header'ı sayfa yüklenirken BİR KEZ hesaplıyordu;
// PIN girişi aynı sayfada tamamlandığında (returnTo yoksa) bayat anon-key'li
// değer kalıyor ve auth.uid() gerektiren RLS'li tablolar sessizce boş dönüyordu.
// Getter ile bu hata sınıfı kökten ortadan kalkar — çağıran kod değişmez.
const SB_HEADERS = {
  'apikey': SB_KEY,
  get Authorization() {
    const token = (typeof oturumAccessTokenGetir === 'function') ? oturumAccessTokenGetir() : null;
    return 'Bearer ' + (token || SB_KEY);
  },
  'Content-Type': 'application/json'
};

// Geriye dönük uyumluluk için korunmuş no-op: getter sayesinde Authorization
// zaten her istekte günceldir; mevcut çağrılar (index.html checkPin) kırılmasın.
function sbHeaderlarYenile(accessToken) { /* no-op */ }
