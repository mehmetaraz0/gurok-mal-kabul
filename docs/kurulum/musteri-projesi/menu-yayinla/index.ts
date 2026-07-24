// Supabase Edge Function: menu-yayinla
// Ana ERP projesindeki aktif menüyü okur (service_role), müşteri projesindeki
// menu_yenile RPC'siyle atomik tam-değiştirme yapar. Yeni secret gerekmez.
// Deploy: Dashboard → Edge Functions → Via Editor, ad "menu-yayinla", JWT verify ON.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

Deno.serve(async (req) => {
  const cors = {
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Headers": "content-type",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
  };
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ ok: false, mesaj: "POST bekleniyor" }, 405, cors);

  const mainUrl = Deno.env.get("MAIN_SB_URL")!;
  const mainKey = Deno.env.get("MAIN_SERVICE_KEY")!;
  const custUrl = Deno.env.get("CUSTOMER_SB_URL")!;
  const custKey = Deno.env.get("CUSTOMER_SERVICE_KEY")!;

  // 1) Ana projeden aktif menüyü oku
  const main = createClient(mainUrl, mainKey);
  const { data: menu, error: mErr } = await main
    .from("menu_urunler")
    .select("id,ad,kategori,fiyat,ucretli,aktif,otel_id")
    .eq("aktif", true).eq("silindi", false);
  if (mErr) return json({ ok: false, mesaj: "Ana menü okunamadı: " + mErr.message }, 200, cors);

  // 2) Müşteri projesinde atomik değiştir
  const cust = createClient(custUrl, custKey);
  const { data: sayi, error: rErr } = await cust.rpc("menu_yenile", { p_menu: menu ?? [] });
  if (rErr) return json({ ok: false, mesaj: "Yayın hatası: " + rErr.message }, 200, cors);

  return json({ ok: true, sayi }, 200, cors);
});

function json(obj: unknown, status: number, cors: Record<string, string>) {
  return new Response(JSON.stringify(obj), {
    status, headers: { ...cors, "Content-Type": "application/json" },
  });
}
