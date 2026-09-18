// Supabase Edge Function: masa-yonetim  (CANLI AD: "rapid-handler")
// Personel masa/token köprüsü: ANA projedeki personel kimliği + yetkisi → MÜŞTERİ
// projesindeki masa_tokenlari işlemi.
//
// A1 (tasarım 3.7, 2026-09-18) — ÖNCEKİ SÜRÜMÜN AÇIKLARI:
//   * kullanıcı e-posta önekinden bulunuyordu (kullanicilar.id = email.split('@')[0])
//   * kullanicilar.aktif'e bakılmıyordu (pasif personel masa yönetebiliyordu)
//   * otel kapsamı yoktu (810 personeli 811 masalarını görüp değiştirebiliyordu)
// ŞİMDİ:
//   * kimlik: auth.getUser() — personel JWT'si ANA projenin GoTrue'sunda doğrulanır
//   * yetki + otel kapsamı: bar_masa_yetki_kapsami() ÇAĞIRANIN JWT'siyle (service_role
//     ile DEĞİL). Pasif kullanıcı, yetki fonksiyonlarında zaten reddedilir.
//   * liste: yalnız erişilebilen otellerin masaları; ekle/durum: başka otel REDDEDİLİR;
//     ekle: depo_id öneki otel_id olmalı ('810_CSM302' → '810').
//   * HTTP kodları: 400 girdi, 401 oturum, 403 yetki/kapsam, 404 masa yok, 500 sunucu.
//     İstemci sözleşmesi aynı: gövde { jwt, anon, action, ... } → { ok, mesaj?, ... }.
//
// Secret: MAIN_SB_URL, CUSTOMER_SB_URL, CUSTOMER_SERVICE_KEY; MAIN_ANON_KEY önerilir.
// MAIN_SERVICE_KEY artık KULLANILMAZ (ana projeye yalnız çağıranın JWT'siyle gidilir).
// MAIN_ANON_KEY yoksa gövdedeki 'anon' (istemcide zaten açık olan public anahtar) kullanılır.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

Deno.serve(async (req) => {
  const cors = { "Access-Control-Allow-Origin":"*", "Access-Control-Allow-Headers":"authorization, apikey, content-type, x-client-info", "Access-Control-Allow-Methods":"POST, OPTIONS" };
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ ok:false, mesaj:"POST bekleniyor" }, 405, cors);

  try {
    let body:any; try { body = await req.json(); } catch { return json({ ok:false, mesaj:"Geçersiz JSON" }, 400, cors); }
    const { jwt, action } = body ?? {};
    // Sürüm kontrolü (jwt gerektirmez) — deploy'un tuttuğunu buradan doğrular
    if (action === "ping") return json({ ok:true, v:"a1-kapsam" }, 200, cors);
    if (!jwt || typeof jwt !== "string") return json({ ok:false, mesaj:"Oturum yok" }, 401, cors);

    const MAIN_URL = Deno.env.get("MAIN_SB_URL")!;
    const ANON = Deno.env.get("MAIN_ANON_KEY") || (body && body.anon ? String(body.anon) : "");
    if (!ANON) return json({ ok:false, mesaj:"Sunucu yapılandırması eksik" }, 500, cors);

    // 1) Kimlik: ANA projede gerçek oturum mu?
    const main = createClient(MAIN_URL, ANON, {
      global: { headers: { Authorization: "Bearer " + jwt } },
      auth: { autoRefreshToken: false, persistSession: false },
    });
    const { data: u, error: uErr } = await main.auth.getUser(jwt);
    if (uErr || !u?.user) return json({ ok:false, mesaj:"Oturum geçersiz — tekrar giriş yapın" }, 401, cors);

    // 2) Yetki + otel kapsamı: çağıranın JWT'siyle, veritabanı kararı
    const { data: kapsam, error: kErr } = await main.rpc("bar_masa_yetki_kapsami");
    if (kErr) return json({ ok:false, mesaj:"Yetki kontrolü başarısız" }, 403, cors);
    const oteller: string[] = Array.isArray(kapsam?.oteller) ? kapsam.oteller.map(String) : [];
    if (kapsam?.yetkili !== true || oteller.length === 0) return json({ ok:false, mesaj:"Yetki yok" }, 403, cors);

    const cust = createClient(Deno.env.get("CUSTOMER_SB_URL")!, Deno.env.get("CUSTOMER_SERVICE_KEY")!);

    if (action === "liste") {
      const { data, error } = await cust.from("masa_tokenlari")
        .select("token,otel_id,depo_id,masa_adi,bolge,aktif")
        .in("otel_id", oteller).order("bolge").order("masa_adi");
      if (error) return json({ ok:false, mesaj:error.message }, 500, cors);
      return json({ ok:true, masalar:data }, 200, cors);
    }
    if (action === "ekle") {
      const { otel_id, depo_id, masa_adi, bolge } = body;
      if (!otel_id || !depo_id || !masa_adi) return json({ ok:false, mesaj:"otel/depo/masa adı zorunlu" }, 400, cors);
      if (!oteller.includes(String(otel_id))) return json({ ok:false, mesaj:"Bu otel için yetkiniz yok" }, 403, cors);
      if (!String(depo_id).startsWith(String(otel_id) + "_"))
        return json({ ok:false, mesaj:"Depo bu otele ait değil" }, 400, cors);
      const token = crypto.randomUUID();
      const { data, error } = await cust.from("masa_tokenlari")
        .insert({ token, otel_id: String(otel_id), depo_id: String(depo_id), masa_adi, bolge: bolge || null, aktif:true })
        .select().single();
      if (error) return json({ ok:false, mesaj:error.message }, 500, cors);
      return json({ ok:true, masa:data }, 200, cors);
    }
    if (action === "durum") {
      const { token, aktif } = body;
      if (!token || typeof aktif !== "boolean") return json({ ok:false, mesaj:"token/aktif zorunlu" }, 400, cors);
      // Masanın oteli ÖNCE okunur; kapsam dışıysa yazılmaz (varlığı da sızdırılmaz).
      const { data: masa, error: mErr } = await cust.from("masa_tokenlari").select("otel_id").eq("token", token).maybeSingle();
      if (mErr) return json({ ok:false, mesaj:mErr.message }, 500, cors);
      if (!masa || !oteller.includes(String(masa.otel_id))) return json({ ok:false, mesaj:"Masa bulunamadı" }, 404, cors);
      const { error } = await cust.from("masa_tokenlari").update({ aktif }).eq("token", token).in("otel_id", oteller);
      if (error) return json({ ok:false, mesaj:error.message }, 500, cors);
      return json({ ok:true }, 200, cors);
    }
    return json({ ok:false, mesaj:"Bilinmeyen aksiyon" }, 400, cors);
  } catch (_e) {
    return json({ ok:false, mesaj:"Sunucu hatası" }, 500, cors);
  }
});

function json(obj:unknown, status:number, cors:Record<string,string>) {
  return new Response(JSON.stringify(obj), { status, headers:{ ...cors, "Content-Type":"application/json" } });
}
