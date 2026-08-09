// Supabase Edge Function: menu-yayinla  (CANLI AD: "smooth-service")
// Ana ERP projesindeki aktif menüyü okur (service_role), müşteri projesindeki
// menu_yenile RPC'siyle atomik tam-değiştirme yapar.
//
// ⚠️ GÜVENLİK (pentest bulgusu [4] — 2026-08-09):
// ÖNCEKİ SÜRÜM yalnızca "geçerli bir proje JWT'si" arıyordu. Ama o JWT,
// istemciye dağıtılan HERKESE AÇIK anon token'dı → internetteki herkes bu
// ayrıcalıklı (service_role destekli) menü yayın akışını tetikleyebiliyordu.
//
// ŞİMDİ: personel JWT'si AYRI bir başlıkta (x-staff-token) gelir; ANA projede
// gerçek kullanıcı oturumu olarak doğrulanır (auth.getUser) ve o kullanıcının
// 'bar_siparis_yonetimi' modülünde en az 'kayit' yetkisi olduğu kontrol edilir.
// Authorization başlığı müşteri projesinin platform JWT kapısı için müşteri anon
// key'ini taşımaya devam eder (ANA proje JWT'sini o kapı kabul etmez).
// Sadece anon key ile çağrı artık 401 döner.
//
// Deploy: Dashboard → Edge Functions → "smooth-service" → Via Editor.
// "Enforce JWT Verification" AÇIK kalabilir; asıl kontrol aşağıdadır.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

Deno.serve(async (req) => {
  const cors = {
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Headers": "authorization, apikey, content-type, x-client-info, x-staff-token",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
  };
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ ok: false, mesaj: "POST bekleniyor" }, 405, cors);

  const mainUrl = Deno.env.get("MAIN_SB_URL")!;
  const mainKey = Deno.env.get("MAIN_SERVICE_KEY")!;
  const mainAnon = Deno.env.get("MAIN_ANON_KEY")!;   // YENİ secret — aşağıdaki nota bak
  const custUrl = Deno.env.get("CUSTOMER_SB_URL")!;
  const custKey = Deno.env.get("CUSTOMER_SERVICE_KEY")!;

  // ---------- 0) YETKİLENDİRME ----------
  // Personel token'ı AYRI başlıkta gelir: Authorization, müşteri projesinin
  // platform JWT kapısı için müşteri anon key'i taşımaya devam eder; gerçek
  // kimlik denetimi aşağıdaki x-staff-token ile ANA projede yapılır.
  const token = (req.headers.get("x-staff-token") ?? "").replace(/^Bearer\s+/i, "").trim();
  if (!token) return json({ ok: false, mesaj: "Yetkisiz: personel oturumu gerekli" }, 401, cors);

  // Token'ı ANA projede gerçek kullanıcı oturumu olarak doğrula.
  // anon key gönderilirse getUser() kullanıcı DÖNDÜRMEZ → 401.
  const authClient = createClient(mainUrl, mainAnon, {
    global: { headers: { Authorization: "Bearer " + token } },
    auth: { autoRefreshToken: false, persistSession: false },
  });
  const { data: userData, error: uErr } = await authClient.auth.getUser();
  if (uErr || !userData?.user) return json({ ok: false, mesaj: "Yetkisiz: geçersiz oturum" }, 401, cors);

  // Uygulama seviyesi yetki: ANA projedeki bar sipariş/menü yönetimi yetkisi.
  // auth_yetki_var çağıranın JWT'siyle çalışır — service_role ile DEĞİL.
  const { data: yetkili, error: yErr } = await authClient
    .rpc("auth_yetki_var", { p_modul_kod: "bar_siparis_yonetimi", p_min_seviye: "kayit" });
  if (yErr) return json({ ok: false, mesaj: "Yetki kontrolü başarısız" }, 403, cors);
  if (yetkili !== true) return json({ ok: false, mesaj: "Bu işlem için yetkiniz yok" }, 403, cors);

  // ---------- 1) Ana projeden aktif menüyü oku (service_role) ----------
  const main = createClient(mainUrl, mainKey);
  const { data: menu, error: mErr } = await main
    .from("menu_urunler")
    .select("id,ad,kategori,fiyat,ucretli,aktif,otel_id")
    .eq("aktif", true).eq("silindi", false);
  if (mErr) return json({ ok: false, mesaj: "Ana menü okunamadı: " + mErr.message }, 200, cors);

  // ---------- 2) Müşteri projesinde atomik değiştir ----------
  const cust = createClient(custUrl, custKey);
  const { data: sayi, error: rErr } = await cust.rpc("menu_yenile", { p_menu: menu ?? [] });
  if (rErr) return json({ ok: false, mesaj: "Yayın hatası: " + rErr.message }, 200, cors);

  return json({ ok: true, sayi, yayinlayan: userData.user.email ?? userData.user.id }, 200, cors);
});

function json(obj: unknown, status: number, cors: Record<string, string>) {
  return new Response(JSON.stringify(obj), {
    status, headers: { ...cors, "Content-Type": "application/json" },
  });
}

// ============================================================
// DEPLOY NOTU — YENİ SECRET GEREKLİ
// ============================================================
// Müşteri projesi (smooth-service) → Settings → Edge Functions → Secrets:
//   MAIN_ANON_KEY = ANA projenin (xwytofysmgqtqjzkplfi) anon/public key'i
// Bu anahtar zaten istemcide açık olan public anon key'dir — gizli değildir;
// yalnızca "kullanıcı JWT'sini doğrula" istemcisini kurmak için gerekir.
// MAIN_SERVICE_KEY ve CUSTOMER_SERVICE_KEY dokunulmadan kalır.
//
// İSTEMCİ SÖZLEŞMESİ (bar-menu-yonetimi.html / bar-siparis-kuyrugu.html):
//   headers: {
//     apikey: CUSTOMER_ANON_KEY,
//     Authorization: 'Bearer ' + CUSTOMER_ANON_KEY,   // platform JWT kapısı
//     'x-staff-token': oturumAccessTokenGetir(),      // ★ gerçek personel JWT'si
//   }
//
// TEST:
//  1) x-staff-token YOK / anon key ile → 401 (ÖNCEDEN 200 dönüyordu)
//  2) yetkisiz personel JWT'si ile     → 403 "Bu işlem için yetkiniz yok"
//  3) yetkili personel JWT'si ile      → 200 { ok:true, sayi:N }
