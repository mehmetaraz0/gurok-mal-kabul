// Supabase Edge Function: masa-yonetim
// Personel masa/token CRUD köprüsü. ÖNCE ana projede JWT + bar_siparis_yonetimi kayıt
// yetkisi doğrular, SONRA customer masa_tokenlari üzerinde işlem yapar (service_role).
// Deploy: Dashboard → Via Editor, JWT verify ON. Secret: MAIN_ANON_KEY (yeni) + mevcut 4.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

Deno.serve(async (req) => {
  const cors = { "Access-Control-Allow-Origin":"*", "Access-Control-Allow-Headers":"content-type", "Access-Control-Allow-Methods":"POST, OPTIONS" };
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ ok:false, mesaj:"POST bekleniyor" }, 405, cors);

  try {
    let body:any; try { body = await req.json(); } catch { return json({ ok:false, mesaj:"Geçersiz JSON" }, 400, cors); }
    const { jwt, action } = body ?? {};
    if (!jwt) return json({ ok:false, mesaj:"Oturum yok" }, 401, cors);

    // Yetki kontrolü: JWT'yi ana projede doğrula + bar_siparis_yonetimi kayıt yetkisi.
    // Herhangi bir hata (bozuk/expired JWT vb.) => yetkisiz say (fail-safe).
    let yetkili = false;
    try {
      const asUser = createClient(Deno.env.get("MAIN_SB_URL")!, Deno.env.get("MAIN_ANON_KEY")!, {
        global: { headers: { Authorization: "Bearer " + jwt } },
      });
      const { data } = await asUser.rpc("auth_yetki_var", { p_modul_kod:"bar_siparis_yonetimi", p_min_seviye:"kayit" });
      yetkili = (data === true);
    } catch { yetkili = false; }
    if (!yetkili) return json({ ok:false, mesaj:"Yetki yok" }, 403, cors);

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
