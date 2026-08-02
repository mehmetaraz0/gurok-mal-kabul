// Supabase Edge Function: ai-analiz-sorgula
// AI Analiz Merkezi v1 — beyni. Akış:
//   1) jwt doğrula (/auth/v1/user) → kullanıcı kimliği
//   2) auth_yetki_var('ai_analiz_merkezi','goruntule') KULLANICI JWT'siyle → yoksa 403
//   3) GLM classify: serbest soru → 6 sabit niyetten biri + parametre
//   4) whitelist + sanitize (otel/gun/esik)
//   5) ilgili ai_q_* RPC'yi KULLANICI JWT'siyle çağır → RLS + otel izolasyonu OTOMATİK
//   6) GLM interpret: agregat → Türkçe yönetici özeti (GLM düşerse ham agregat yine döner)
//
// Model ASLA: SQL üretmez, ham/kişisel satır görmez (yalnızca küçük agregat), yetki kararı vermez.
// Secret: AI_API_URL, AI_API_KEY, AI_MODEL. Veri için service_role YOK (RLS + kullanıcı JWT yeter).
// SUPABASE_URL / SUPABASE_ANON_KEY otomatik enjekte edilir. "Verify JWT" KAPALI olabilir
// (jwt gövdede geliyor, EF kendi doğruluyor) — masa-yonetim deseniyle aynı.

const VERSION = "ai-analiz-sorgula-v1";

// 6 sabit niyet (whitelist). params: hangi parametreleri kabul ettiği.
const NIYETLER: Record<string, { rpc: string; params: string[]; aciklama: string }> = {
  tuketim_artan: { rpc: "ai_q_tuketim_artan", params: ["otel", "gun"], aciklama: "Son dönem vs önceki dönem tüketimi en çok artan ürünler" },
  skt_yaklasan:  { rpc: "ai_q_skt_yaklasan",  params: ["otel", "gun"], aciklama: "N gün içinde son kullanma tarihi dolacak ürünler" },
  stok_anomali:  { rpc: "ai_q_stok_anomali",  params: ["otel", "esik"], aciklama: "İstatistiksel olağandışı stok hareketi (ortalama ± eşik·sapma)" },
  yavas_donen:   { rpc: "ai_q_yavas_donen",   params: ["otel", "gun"], aciklama: "Stokta olan ama N gündür hiç çıkışı olmayan ürünler" },
  min_alti_stok: { rpc: "ai_q_min_alti",      params: ["otel"], aciklama: "Minimum stok seviyesinin altındaki ürünler" },
  gunluk_ozet:   { rpc: "ai_q_gunluk_ozet",   params: ["otel"], aciklama: "Otel bazlı bekleyen mal kabul + kritik SKT + minimum altı özet" },
};

Deno.serve(async (req) => {
  const cors = {
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Headers": "authorization, apikey, content-type, x-client-info",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
  };
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ ok: false, mesaj: "POST bekleniyor" }, 405, cors);

  try {
    let body: any;
    try { body = await req.json(); } catch { return json({ ok: false, mesaj: "Geçersiz JSON" }, 400, cors); }

    const { soru, jwt, action } = body ?? {};
    if (action === "ping") return json({ ok: true, v: VERSION }, 200, cors);

    if (!jwt) return json({ ok: false, mesaj: "Oturum yok" }, 401, cors);
    if (!soru || typeof soru !== "string") return json({ ok: false, mesaj: "soru zorunlu" }, 400, cors);

    const SB_URL = Deno.env.get("SUPABASE_URL")!;
    const ANON = (body && body.anon) ? String(body.anon) : Deno.env.get("SUPABASE_ANON_KEY")!;

    // ---- 1) JWT doğrula → kullanıcı ----
    let email = "";
    try {
      const uRes = await fetch(SB_URL + "/auth/v1/user", { headers: { apikey: ANON, Authorization: "Bearer " + jwt } });
      if (uRes.ok) { const u = await uRes.json(); email = (u && u.email) ? u.email : ""; }
    } catch { /* aşağıda yakalanır */ }
    if (!email) return json({ ok: false, mesaj: "Oturum geçersiz — tekrar giriş yapın" }, 401, cors);

    // ---- 2) Yetki: auth_yetki_var KULLANICI JWT'siyle (service_role yok) ----
    const yetkiOk = await rpcCagir(SB_URL, ANON, jwt, "auth_yetki_var",
      { p_modul_kod: "ai_analiz_merkezi", p_min_seviye: "goruntule" });
    if (yetkiOk?.hata || yetkiOk?.data !== true) {
      return json({ ok: false, mesaj: "Bu modül için yetkiniz yok" }, 403, cors);
    }

    // ---- 3) GLM classify ----
    const AI_URL = (Deno.env.get("AI_API_URL") || "").replace(/\/+$/, "");
    const AI_KEY = Deno.env.get("AI_API_KEY") || "";
    const AI_MODEL = Deno.env.get("AI_MODEL") || "";
    if (!AI_URL || !AI_KEY || !AI_MODEL) {
      return json({ ok: false, mesaj: "AI yapılandırması eksik (AI_API_URL/AI_API_KEY/AI_MODEL)" }, 500, cors);
    }

    const niyetMenu = Object.entries(NIYETLER).map(([k, v]) => `- ${k}: ${v.aciklama} (parametreler: ${v.params.join(", ")})`).join("\n");
    const sysClassify =
      "Sen bir ERP analiz yönlendiricisisin. Kullanıcının Türkçe sorusunu AŞAĞIDAKİ SABİT NİYET " +
      "listesinden EN UYGUN olanına eşle ve parametreleri çıkar. Yalnızca GEÇERLİ JSON döndür, " +
      "başka metin yazma.\n\nNİYETLER:\n" + niyetMenu + "\n\n" +
      "Parametre kuralları: otel = '810' veya '811' (belirtilmemişse null), gun = tam sayı (gün), " +
      "esik = ondalık sayı (varsayılan 2). Soruyu hiçbir niyete eşleyemezsen intent='yok' döndür.\n" +
      'Çıktı formatı: {"intent":"<niyet_veya_yok>","params":{"otel":null,"gun":null,"esik":null}}';

    let clsRaw: string;
    try {
      clsRaw = await glmChat(AI_URL, AI_KEY, AI_MODEL, [
        { role: "system", content: sysClassify },
        { role: "user", content: String(soru).slice(0, 500) },
      ]);
    } catch (e) {
      return json({ ok: false, mesaj: "AI şu an yanıt veremedi, lütfen tekrar deneyin", detay: String(e).slice(0, 200) }, 200, cors);
    }

    const cls = jsonAyikla(clsRaw);
    const intent = cls?.intent;
    if (!intent || intent === "yok" || !NIYETLER[intent]) {
      return json({ ok: true, yanitlanamadi: true, mesaj: "Bu soruyu şu an yanıtlayamıyorum. Örnek: 'yaklaşan son kullanma tarihleri', 'minimum altı stoklar', 'günlük özet'." }, 200, cors);
    }

    // ---- 4) Whitelist + sanitize ----
    const meta = NIYETLER[intent];
    const p = cls.params || {};
    const rpcParams: Record<string, unknown> = {};
    if (meta.params.includes("otel")) rpcParams["p_otel"] = (p.otel === "810" || p.otel === "811") ? p.otel : null;
    if (meta.params.includes("gun")) rpcParams["p_gun"] = kisitla(intToNum(p.gun, intent === "skt_yaklasan" ? 14 : 30), 1, 365);
    if (meta.params.includes("esik")) rpcParams["p_esik"] = kisitla(numToNum(p.esik, 2), 0.5, 5);

    // ---- 5) RPC'yi kullanıcı JWT'siyle çalıştır (RLS + otel izolasyonu otomatik) ----
    const rpcSonuc = await rpcCagir(SB_URL, ANON, jwt, meta.rpc, rpcParams);
    if (rpcSonuc?.hata) {
      return json({ ok: false, mesaj: "Veri alınamadı", detay: String(rpcSonuc.hata).slice(0, 200) }, 200, cors);
    }
    let agregat = rpcSonuc.data;

    // min_alti özel: minimum tanımlı değilse yanıltıcı "0 eksik" gösterme
    let ozelNot: string | null = null;
    if (intent === "min_alti_stok") {
      const tanimli = agregat?.minimum_tanimli === true;
      agregat = agregat?.satirlar ?? [];
      if (!tanimli) ozelNot = "Henüz minimum stok seviyesi tanımlı değil — bu yüzden 'eksik yok' sonucu yanıltıcı olabilir. Minimum tanımlandıkça bu analiz otomatik çalışır.";
    }

    const satirSayisi = Array.isArray(agregat) ? agregat.length : 0;

    // ---- 6) GLM interpret (düşerse ham agregat yine döner) ----
    let ozet = "";
    let aiYorumHata = false;
    try {
      const sysYorum =
        "Sen bir F&B/depo yöneticisi asistanısın. Sana verilen KÜÇÜK AGREGAT VERİYİ Türkçe, kısa ve " +
        "eyleme dönük yorumla. Sadece verideki sayılara dayan, VERİDE OLMAYAN hiçbir şey uydurma. " +
        "En fazla 5 madde. Sonunda gerekiyorsa tek cümlelik öneri ver. Veri boşsa bunu açıkça söyle." +
        (ozelNot ? "\n\nÖNEMLİ NOT (mutlaka aktar): " + ozelNot : "");
      const kullaniciYorum =
        "Soru: " + String(soru).slice(0, 300) + "\n" +
        "Niyet: " + intent + " (" + meta.aciklama + ")\n" +
        "Parametreler: " + JSON.stringify(rpcParams) + "\n" +
        "Veri (agregat, " + satirSayisi + " satır): " + JSON.stringify(agregat).slice(0, 6000);
      ozet = await glmChat(AI_URL, AI_KEY, AI_MODEL, [
        { role: "system", content: sysYorum },
        { role: "user", content: kullaniciYorum },
      ]);
    } catch {
      aiYorumHata = true;
      ozet = ozelNot ? ozelNot : "AI yorumu şu an üretilemedi; ham veri aşağıda.";
    }

    return json({
      ok: true,
      intent,
      kullanilan_rpc: meta.rpc,
      parametreler: rpcParams,
      satir_sayisi: satirSayisi,
      ozet,
      ai_yorum_hata: aiYorumHata,
      not: ozelNot,
      kaynak: agregat,
    }, 200, cors);

  } catch (e) {
    return json({ ok: false, mesaj: "Sunucu hatası", detay: String(e).slice(0, 200) }, 200, cors);
  }
});

// ---- Yardımcılar ----

// PostgREST RPC'yi kullanıcı JWT'siyle çağır. Dönüş: { data } | { hata }
async function rpcCagir(sbUrl: string, anon: string, jwt: string, fn: string, params: Record<string, unknown>) {
  try {
    const res = await fetch(sbUrl + "/rest/v1/rpc/" + fn, {
      method: "POST",
      headers: { apikey: anon, Authorization: "Bearer " + jwt, "Content-Type": "application/json" },
      body: JSON.stringify(params),
    });
    const txt = await res.text();
    if (!res.ok) return { hata: "RPC " + fn + " " + res.status + ": " + txt.slice(0, 200) };
    let data: unknown = null;
    try { data = txt ? JSON.parse(txt) : null; } catch { data = txt; }
    return { data };
  } catch (e) {
    return { hata: String(e) };
  }
}

// OpenAI-uyumlu chat completions (GLM/Z.AI). content string döner.
async function glmChat(baseUrl: string, key: string, model: string, messages: any[]): Promise<string> {
  const res = await fetch(baseUrl + "/chat/completions", {
    method: "POST",
    headers: { Authorization: "Bearer " + key, "Content-Type": "application/json" },
    body: JSON.stringify({ model, messages, temperature: 0.2, max_tokens: 1200 }),
  });
  const txt = await res.text();
  if (!res.ok) throw new Error("AI " + res.status + ": " + txt.slice(0, 200));
  let j: any; try { j = JSON.parse(txt); } catch { throw new Error("AI yanıtı JSON değil"); }
  const content = j?.choices?.[0]?.message?.content;
  if (typeof content !== "string" || !content) throw new Error("AI boş yanıt");
  return content;
}

// Metnin içinden ilk {...} JSON bloğunu ayıkla ve parse et (model bazen kod bloğuyla sarar).
function jsonAyikla(s: string): any {
  if (!s) return null;
  let t = s.trim().replace(/^```(?:json)?/i, "").replace(/```$/i, "").trim();
  const ilk = t.indexOf("{"); const son = t.lastIndexOf("}");
  if (ilk >= 0 && son > ilk) t = t.slice(ilk, son + 1);
  try { return JSON.parse(t); } catch { return null; }
}

function intToNum(v: unknown, def: number): number {
  const n = typeof v === "number" ? v : parseInt(String(v ?? ""), 10);
  return Number.isFinite(n) ? Math.round(n) : def;
}
function numToNum(v: unknown, def: number): number {
  const n = typeof v === "number" ? v : parseFloat(String(v ?? ""));
  return Number.isFinite(n) ? n : def;
}
function kisitla(n: number, lo: number, hi: number): number {
  return Math.min(hi, Math.max(lo, n));
}

function json(obj: unknown, status: number, cors: Record<string, string>) {
  return new Response(JSON.stringify(obj), { status, headers: { ...cors, "Content-Type": "application/json" } });
}
