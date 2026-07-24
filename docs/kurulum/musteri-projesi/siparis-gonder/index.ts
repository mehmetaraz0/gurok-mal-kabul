// Supabase Edge Function: siparis-gonder
// Müşteri sayfasından POST alır, ana ERP projesindeki bar_siparis_olustur RPC'sini
// service_role ile çağırır, sonucu senkron döner. Arşive yazar.
// Deploy: supabase functions deploy siparis-gonder --project-ref <CUSTOMER_PROJECT_REF> --no-verify-jwt
// Secrets: MAIN_SB_URL, MAIN_SERVICE_KEY (ana proje service_role), CUSTOMER_SB_URL, CUSTOMER_SERVICE_KEY

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const MAX_KALEM = 20;        // sipariş başına max farklı kalem
const MAX_ADET = 30;         // kalem başına max adet

Deno.serve(async (req) => {
  const cors = {
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Headers": "content-type",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
  };
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ ok: false, mesaj: "POST bekleniyor" }, 405, cors);

  let body: any;
  try { body = await req.json(); } catch { return json({ ok: false, mesaj: "Geçersiz JSON" }, 400, cors); }
  const { token, kalemler, oda_no } = body ?? {};

  if (!token || !Array.isArray(kalemler) || kalemler.length === 0)
    return json({ ok: false, mesaj: "token ve kalemler zorunlu" }, 400, cors);
  if (kalemler.length > MAX_KALEM)
    return json({ ok: false, mesaj: "Çok fazla kalem" }, 400, cors);
  for (const k of kalemler) {
    const adet = Number(k?.adet);
    if (!k?.menu_urun_id || !(adet > 0) || adet > MAX_ADET)
      return json({ ok: false, mesaj: "Geçersiz kalem/adet" }, 400, cors);
  }

  const custUrl = Deno.env.get("CUSTOMER_SB_URL")!;
  const custKey = Deno.env.get("CUSTOMER_SERVICE_KEY")!;
  const mainUrl = Deno.env.get("MAIN_SB_URL")!;
  const mainKey = Deno.env.get("MAIN_SERVICE_KEY")!;

  // 1) Token'ı çöz (service_role, RLS bypass)
  const cust = createClient(custUrl, custKey);
  const { data: masa, error: mErr } = await cust
    .from("masa_tokenlari").select("otel_id,depo_id,masa_adi,aktif")
    .eq("token", token).eq("aktif", true).maybeSingle();
  if (mErr || !masa) return json({ ok: false, mesaj: "Geçersiz masa" }, 400, cors);

  // 2) Ana projede sipariş oluştur (service_role, hard-block orada işler)
  const main = createClient(mainUrl, mainKey);
  const { data: siparisId, error: rErr } = await main.rpc("bar_siparis_olustur", {
    p_otel_id: masa.otel_id,
    p_depo_id: masa.depo_id,
    p_masa_token: masa.masa_adi,
    p_oda_no: oda_no ?? null,
    p_kalemler: kalemler,
  });

  // 3) Arşivle
  const basarili = !rErr && !!siparisId;
  await cust.from("siparis_arsiv").insert({
    token, oda_no: oda_no ?? null, kalemler,
    ana_siparis_id: basarili ? siparisId : null,
    sonuc: basarili ? "basarili" : "hata",
    hata_mesaji: rErr?.message ?? null,
  });

  if (!basarili)
    return json({ ok: false, mesaj: rErr?.message ?? "Sipariş oluşturulamadı" }, 200, cors);
  return json({ ok: true, siparis_id: siparisId }, 200, cors);
});

function json(obj: unknown, status: number, cors: Record<string, string>) {
  return new Response(JSON.stringify(obj), {
    status, headers: { ...cors, "Content-Type": "application/json" },
  });
}
