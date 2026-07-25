// Supabase Edge Function: masa-yonetim
// Personel masa/token CRUD köprüsü. JWT'yi GoTrue ile doğrular (apikey = MAIN_SERVICE_KEY,
// bilinen-çalışan) → email'den kullanıcı id → rolü service_role ile okur → bar_siparis_yonetimi
// kayıt yetkisi → customer masa_tokenlari işlem. Not: MAIN_ANON_KEY GEREKMEZ.
// Secret: MAIN_SB_URL, MAIN_SERVICE_KEY, CUSTOMER_SB_URL, CUSTOMER_SERVICE_KEY.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

Deno.serve(async (req) => {
  const cors = { "Access-Control-Allow-Origin":"*", "Access-Control-Allow-Headers":"authorization, apikey, content-type, x-client-info", "Access-Control-Allow-Methods":"POST, OPTIONS" };
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ ok:false, mesaj:"POST bekleniyor" }, 405, cors);

  try {
    let body:any; try { body = await req.json(); } catch { return json({ ok:false, mesaj:"Geçersiz JSON" }, 400, cors); }
    const { jwt, action } = body ?? {};
    if (!jwt) return json({ ok:false, mesaj:"Oturum yok" }, 401, cors);

    const MAIN_URL = Deno.env.get("MAIN_SB_URL")!;
    const MAIN_SVC = Deno.env.get("MAIN_SERVICE_KEY")!;

    // JWT'yi doğrula → email. apikey: sayfadan gelen anon (public, doğrulanmış çalışan);
    // yoksa secret'lara düş. getUser kimliği Bearer token'dan belirler, apikey sadece geçit.
    const ANON = (body && body.anon) ? String(body.anon) : (Deno.env.get("MAIN_ANON_KEY") || MAIN_SVC);
    let email = "";
    try {
      const uRes = await fetch(MAIN_URL + "/auth/v1/user", { headers: { apikey: ANON, Authorization: "Bearer " + jwt } });
      if (uRes.ok) { const u = await uRes.json(); email = (u && u.email) ? u.email : ""; }
    } catch {}
    if (!email) return json({ ok:false, mesaj:"Oturum geçersiz — tekrar giriş yapın" }, 200, cors);

    // Rolü service_role ile bul + yetki kontrolü
    const main = createClient(MAIN_URL, MAIN_SVC);
    const { data: kul } = await main.from("kullanicilar").select("rol_id").eq("id", email.split("@")[0]).maybeSingle();
    if (!kul || !kul.rol_id) return json({ ok:false, mesaj:"Kullanıcı/rol bulunamadı" }, 200, cors);
    const { data: modul } = await main.from("moduller").select("id").eq("kod","bar_siparis_yonetimi").eq("aktif",true).maybeSingle();
    if (!modul || !modul.id) return json({ ok:false, mesaj:"Bar modülü kapalı" }, 200, cors);
    const { data: yrow } = await main.from("yetki_matrisi").select("yetki").eq("rol_id", kul.rol_id).eq("modul_id", modul.id).maybeSingle();
    if (!yrow || !["kayit","tam"].includes(yrow.yetki)) return json({ ok:false, mesaj:"Yetki yok" }, 200, cors);

    // Yetki tamam → customer service_role ile işlem
    const cust = createClient(Deno.env.get("CUSTOMER_SB_URL")!, Deno.env.get("CUSTOMER_SERVICE_KEY")!);

    if (action === "liste") {
      const { data, error } = await cust.from("masa_tokenlari").select("token,otel_id,depo_id,masa_adi,aktif").order("masa_adi");
      if (error) return json({ ok:false, mesaj:error.message }, 200, cors);
      return json({ ok:true, masalar:data }, 200, cors);
    }
    if (action === "ekle") {
      const { otel_id, depo_id, masa_adi } = body;
      if (!otel_id || !depo_id || !masa_adi) return json({ ok:false, mesaj:"otel/depo/masa adı zorunlu" }, 400, cors);
      const token = crypto.randomUUID();
      const { data, error } = await cust.from("masa_tokenlari").insert({ token, otel_id, depo_id, masa_adi, aktif:true }).select().single();
      if (error) return json({ ok:false, mesaj:error.message }, 200, cors);
      return json({ ok:true, masa:data }, 200, cors);
    }
    if (action === "durum") {
      const { token, aktif } = body;
      if (!token || typeof aktif !== "boolean") return json({ ok:false, mesaj:"token/aktif zorunlu" }, 400, cors);
      const { error } = await cust.from("masa_tokenlari").update({ aktif }).eq("token", token);
      if (error) return json({ ok:false, mesaj:error.message }, 200, cors);
      return json({ ok:true }, 200, cors);
    }
    return json({ ok:false, mesaj:"Bilinmeyen aksiyon" }, 400, cors);
  } catch (e) {
    return json({ ok:false, mesaj:"Sunucu hatası" }, 200, cors);
  }
});

function json(obj:unknown, status:number, cors:Record<string,string>) {
  return new Response(JSON.stringify(obj), { status, headers:{ ...cors, "Content-Type":"application/json" } });
}
