// GEÇİCİ TEST FONKSİYONU — yalnızca Faz 0 doğrulaması için.
// Faz 0 başarıyla tamamlanıp Faz 3'e (gerçek pin-girisi Edge Function'ı) geçildikten
// sonra bu fonksiyon Supabase Dashboard'dan SİLİNMELİ — kalıcı bir bileşen değildir.
//
// Amaç: Admin API ile PAROLASIZ, gerçek bir Supabase Auth session (access_token +
// refresh_token) üretilebildiğini TEK bir atılabilir test kullanıcısıyla doğrulamak.
// public.kullanicilar tablosuna HİÇ dokunmaz, gerçek kullanıcı verisiyle etkileşmez.
//
// Akış: generateLink('magiclink') → hashed_token al → verifyOtp(token_hash) ile
// gerçek bir session'a çevir → üretilen access_token'ı /auth/v1/user'a göndererek
// GERÇEKTEN geçerli bir JWT olduğunu (doğru kullanıcıya çözüldüğünü) teyit et.
//
// Secret (deploy öncesi ayarlanmalı):
//   TEST_SB_URL      → ana proje Supabase URL'i (supabase-config.js'deki SB_URL ile aynı)
//   TEST_SERVICE_KEY → ana projenin service_role key'i (Supabase Dashboard → Settings → API)
//
// NOT: generateLink/verifyOtp'ın döndürdüğü alan adları (ör. hashed_token) kullanılan
// @supabase/supabase-js sürümüne göre değişebilir. Bu fonksiyon bu yüzden her adımda
// ham yanıtı (`raw`) da döndürür — beklenen alan bulunamazsa ham yanıtı inceleyip
// gerçek alan adına göre kodu güncelleyin. Bu fonksiyonun "ilk denemede hatasız
// çalışacağı" varsayılmamalı; asıl amacı budur.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

Deno.serve(async (req) => {
  const cors = {
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Headers": "authorization, apikey, content-type",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
  };
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ ok: false, adim: "istek", mesaj: "POST bekleniyor" }, 405, cors);

  try {
    let body: any;
    try { body = await req.json(); } catch { return json({ ok: false, adim: "istek", mesaj: "Geçersiz JSON" }, 400, cors); }

    const { email } = body ?? {};
    if (!email) return json({ ok: false, adim: "istek", mesaj: "email zorunlu (test kullanıcısının e-postası)" }, 400, cors);

    const TEST_SB_URL = Deno.env.get("TEST_SB_URL")!;
    const TEST_SERVICE_KEY = Deno.env.get("TEST_SERVICE_KEY")!;

    const admin = createClient(TEST_SB_URL, TEST_SERVICE_KEY, {
      auth: { autoRefreshToken: false, persistSession: false },
    });

    // 1) Admin API ile magic-link üret — kullanıcının parolasını hiç bilmeden.
    const { data: linkData, error: linkErr } = await admin.auth.admin.generateLink({
      type: "magiclink",
      email,
    });
    if (linkErr) {
      return json({ ok: false, adim: "generateLink", mesaj: linkErr.message }, 200, cors);
    }

    const tokenHash = (linkData as any)?.properties?.hashed_token;
    if (!tokenHash) {
      return json({
        ok: false,
        adim: "generateLink",
        mesaj: "properties.hashed_token bulunamadı — ham yanıtı incele, alan adı farklı olabilir",
        raw: linkData,
      }, 200, cors);
    }

    // 2) token_hash'i gerçek bir session'a çevir.
    const { data: verifyData, error: verifyErr } = await admin.auth.verifyOtp({
      type: "magiclink",
      token_hash: tokenHash,
    });
    if (verifyErr) {
      return json({ ok: false, adim: "verifyOtp", mesaj: verifyErr.message }, 200, cors);
    }

    const session = (verifyData as any)?.session;
    if (!session?.access_token) {
      return json({
        ok: false,
        adim: "verifyOtp",
        mesaj: "session/access_token yok — ham yanıtı incele",
        raw: verifyData,
      }, 200, cors);
    }

    // 3) Üretilen access_token GERÇEKTEN geçerli mi? /auth/v1/user ile teyit et.
    const userRes = await fetch(TEST_SB_URL + "/auth/v1/user", {
      headers: { apikey: TEST_SERVICE_KEY, Authorization: "Bearer " + session.access_token },
    });
    const userCheck = await userRes.json();

    return json({
      ok: true,
      access_token_var_mi: !!session.access_token,
      refresh_token_var_mi: !!session.refresh_token,
      expires_in: session.expires_in ?? null,
      auth_user_dogrulama_status: userRes.status,
      dogrulanan_kullanici_email: userCheck?.email || null,
      dogrulanan_kullanici_id: userCheck?.id || null,
    }, 200, cors);
  } catch (e) {
    return json({ ok: false, adim: "beklenmeyen", mesaj: String(e) }, 200, cors);
  }
});

function json(obj: unknown, status: number, cors: Record<string, string>) {
  return new Response(JSON.stringify(obj), { status, headers: { ...cors, "Content-Type": "application/json" } });
}
