// pin-girisi — [3] Faz 3 kalıcı Edge Function (Faz 0 test EF'inin canlı hali).
//
// Amaç: index.html'deki PIN giriş ekranının, PIN'i hiçbir zaman Supabase Auth
// parolası olarak GÖNDERMEDEN, sunucu tarafında doğrulanmış bir PIN karşılığında
// gerçek bir Auth session (access_token + refresh_token) alabilmesini sağlamak.
//
// Akış:
//   1) İstemciden { pin } al (6 haneli).
//   2) İsteğin IP'sini al, SHA-256 ile hashle (ip_hash) -- ham IP hiçbir yerde
//      saklanmaz, yalnızca giris_denemeleri tablosunda hash'i tutulur.
//   3) service_role client ile public.pin_dogrula(p_giris, p_ip_hash) RPC'sini
//      çağır (docs/kurulum/2026-07-27-pin-hash-faz1-hazirlik.sql). Bu RPC:
//        - TAM 6 hane + bcrypt karşılaştırması yapar,
//        - sunucu taraflı rate-limit'i (15 dk'da 10 başarısız deneme) uygular,
//        - yalnızca service_role çağırabilir (anon/authenticated'e execute YOK).
//   4) Eşleşme varsa: kullanıcının auth_user_id'sine karşılık gelen e-posta için
//      Admin API generateLink('magiclink') + verifyOtp ile GERÇEK bir session
//      üret (Faz 0'da izole test kullanıcısıyla doğrulanan aynı mekanizma).
//      auth_user_id BOŞSA (canlı akışta lazy-signUp hiç tetiklenmemiş VEYA
//      tetiklenmiş ama eski kod PATCH sonucunu kontrol etmediği için DB'ye
//      linklenmemiş -- kanıtlanmış bir bug): önce admin.createUser ile YENİ
//      bir Auth hesabı açmayı dene; e-posta zaten kayıtlıysa (orphan durum)
//      mevcut Auth hesabını e-postadan bulup kullan. Hangi yol işlerse işlesin
//      kullanicilar.auth_user_id bu sefer SERVICE-ROLE ile (RLS'e takılmadan)
//      yazılır -- bu da eski bug'ı kalıcı olarak kendi kendine onarır.
//   5) { ok:true, kullanici, access_token, refresh_token, expires_in } dön.
//      Eşleşme yoksa VEYA rate-limit'e takılırsa -- ayırt ETTİRMEDEN -- aynı
//      genel { ok:false, mesaj:'Hatalı PIN' } dönülür (oracle oluşturmamak için).
//
// Secret GEREKMİYOR: SUPABASE_URL ve SUPABASE_SERVICE_ROLE_KEY Supabase
// tarafından her Edge Function'a otomatik enjekte edilir (Faz 0'da doğrulandı).
//
// DAHILI_EMAIL_DOMAIN burada bilerek sabit yazılı -- otel-config.js'deki
// DAHILI_EMAIL_DOMAIN ile AYNI olmalı (şu an: 'gurok.internal'). Bu proje
// tek kiracılı (tek otel grubu) olduğu için sabit tutuldu; ileride birden
// fazla müşteri/domain olursa bu bir secret'a taşınmalı.
//
// Deploy: "Enforce JWT Verification" KAPALI olmalı -- bu fonksiyon henüz giriş
// yapmamış (anonim) kullanıcılar tarafından çağrılacak, platform seviyesinde
// bir JWT şartı koyulursa hiç çağrılamaz.
//
// Test sırasında { pin, debug:true } gönderirseniz, hata durumunda hangi
// adımda (adim) ve ham SDK yanıtıyla (raw) birlikte ayrıntılı sonuç
// döner -- index.html asla debug:true GÖNDERMEZ (Faz 3 entegrasyonunda).

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const DAHILI_EMAIL_DOMAIN = "gurok.internal";

// Bu fonksiyonun ÇALIŞAN sürümü. Kaynağı her değiştirdiğinde BUNU DA değiştir.
// Neden var: 2026-08-05'te Dashboard "deploy başarılı" dediği halde çalışan kod
// iki kez ESKİ sürümde kaldı ve bunu ancak beklenen davranış gelmeyince fark
// ettik. Artık deploy sonrası GET ile sürüm sorulabiliyor (aşağıya bak).
const SURUM = "2026-08-09-xff-en-sag";

Deno.serve(async (req) => {
  const cors = {
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Headers": "authorization, apikey, content-type",
    "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
  };
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });

  // DEPLOY DOĞRULAMA UCU — kimlik doğrulaması gerektirmez, veritabanına
  // DOKUNMAZ, başarısız giriş denemesi ÜRETMEZ (yani throttle'ı tetiklemez).
  // Sadece hangi kaynak sürümünün çalıştığını söyler.
  if (req.method === "GET") return json({ ok: true, surum: SURUM }, 200, cors);

  if (req.method !== "POST") return json({ ok: false, mesaj: "POST bekleniyor" }, 405, cors);

  try {
    let body: any;
    try { body = await req.json(); } catch { return json({ ok: false, mesaj: "Geçersiz JSON" }, 400, cors); }

    const pin = String(body?.pin ?? "");
    const debug = body?.debug === true;
    if (!/^\d{6}$/.test(pin)) {
      return json(fail("PIN 6 haneli sayısal olmalı", "istek", debug), 400, cors);
    }

    const SB_URL = Deno.env.get("SUPABASE_URL")!;
    const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

    const ipHash = await sha256Hex(clientIp(req));

    const admin = createClient(SB_URL, SERVICE_KEY, {
      auth: { autoRefreshToken: false, persistSession: false },
    });

    // 1) pin_dogrula RPC'si (SECURITY DEFINER, yalnızca service_role çağırabilir)
    const { data: adaylar, error: rpcErr } = await admin.rpc("pin_dogrula", {
      p_giris: pin,
      p_ip_hash: ipHash,
    });
    if (rpcErr) {
      return json(fail("Sunucu hatası", "pin_dogrula", debug, rpcErr.message), 200, cors);
    }
    const kullanici = Array.isArray(adaylar) ? adaylar[0] : null;
    if (!kullanici) {
      // Eşleşme yok VEYA rate-limit'e takıldı -- istemciye AYNI genel mesaj.
      return json(fail("Hatalı PIN", "pin_dogrula", debug), 200, cors);
    }
    // 2) auth_user_id yoksa: yeni Auth hesabı aç, yoksa (orphan) mevcut
    // hesabı e-postadan bulup bağla. İkisi de olmazsa hata dön.
    const email = kullanici.id + "@" + DAHILI_EMAIL_DOMAIN;
    let authUserId: string | null = kullanici.auth_user_id || null;
    let saglamaAdimlari: any = undefined;

    if (!authUserId) {
      const { data: created, error: createErr } = await admin.auth.admin.createUser({
        email,
        email_confirm: true,
      });
      if (created?.user?.id) {
        authUserId = created.user.id;
        saglamaAdimlari = { yol: "yeni-hesap-olusturuldu" };
      } else {
        // Muhtemelen bu e-posta icin Auth hesabi ZATEN var (eski canli
        // akistaki PATCH bug'i yuzunden DB'ye linklenmemis). E-postadan bul.
        const mevcutId = await mevcutAuthUserIdEmailIle(SB_URL, SERVICE_KEY, email);
        if (mevcutId) {
          authUserId = mevcutId;
          saglamaAdimlari = { yol: "mevcut-hesap-linklendi", createUserHatasi: createErr?.message };
        } else {
          return json(
            fail("Sunucu hatası", "auth_user_id_saglama", debug, createErr?.message, { email }),
            200, cors
          );
        }
      }
      // Self-heal: DB'yi service-role ile guncelle (RLS'e takilmaz, eski
      // koddaki gibi sonucu kontrolsuz birakmiyoruz -- debug'da goruluyor).
      const patchRes = await fetch(SB_URL + "/rest/v1/kullanicilar?id=eq." + kullanici.id, {
        method: "PATCH",
        headers: { apikey: SERVICE_KEY, Authorization: "Bearer " + SERVICE_KEY, "Content-Type": "application/json" },
        body: JSON.stringify({ auth_user_id: authUserId }),
      });
      if (saglamaAdimlari) saglamaAdimlari.patchOk = patchRes.ok;
    }

    // 3) Admin API ile parolasız, gerçek bir session üret.
    const { data: linkData, error: linkErr } = await admin.auth.admin.generateLink({
      type: "magiclink",
      email,
    });
    if (linkErr) {
      return json(fail("Sunucu hatası", "generateLink", debug, linkErr.message, linkData), 200, cors);
    }
    const tokenHash = (linkData as any)?.properties?.hashed_token;
    if (!tokenHash) {
      return json(fail("Sunucu hatası", "generateLink", debug, "hashed_token yok", linkData), 200, cors);
    }

    const { data: verifyData, error: verifyErr } = await admin.auth.verifyOtp({
      type: "magiclink",
      token_hash: tokenHash,
    });
    if (verifyErr) {
      return json(fail("Sunucu hatası", "verifyOtp", debug, verifyErr.message, verifyData), 200, cors);
    }
    const session = (verifyData as any)?.session;
    if (!session?.access_token) {
      return json(fail("Sunucu hatası", "verifyOtp", debug, "session/access_token yok", verifyData), 200, cors);
    }

    // NOT: Başarılı giriş kaydı (giris_kayitlari) artık istemci tarafında
    // giris_kaydi_ekle() RPC'si ile yazılır (docs/kurulum/2026-08-05-giris-
    // kayitlari-rpc.sql) — EF deploy'una bağımlı olmasın diye. Burada YAZILMAZ.

    // index.html'deki mevcut kullanıcı nesnesiyle (rol/depoId/otelId normalizasyonu
    // dahil) AYNI şekli koru -- checkPin() bunu değişiklik yapmadan kullanabilsin.
    // auth_user_id'yi BİLEREK üzerine yazıyoruz: pin_dogrula'dan gelen satır
    // self-heal'den ÖNCEKİ (boş olabilen) değeri taşıyor; dönen nesnede artık
    // çözülmüş/bağlanmış gerçek authUserId olmalı.
    return json({
      ok: true,
      kullanici: {
        ...kullanici,
        auth_user_id: authUserId,
        rol: kullanici.rol === "personel" ? "depo" : kullanici.rol,
        depoId: kullanici.depo_id || null,
        otelId: kullanici.otel_id || null,
      },
      access_token: session.access_token,
      refresh_token: session.refresh_token,
      expires_in: session.expires_in ?? null,
      ...(debug && saglamaAdimlari ? { saglamaAdimlari } : {}),
    }, 200, cors);
  } catch (e) {
    return json({ ok: false, mesaj: "Sunucu hatası", adim: "beklenmeyen", hata: String(e) }, 200, cors);
  }
});

function fail(mesaj: string, adim: string, debug: boolean, hata?: string, raw?: unknown) {
  if (!debug) return { ok: false, mesaj };
  return { ok: false, mesaj, adim, hata, raw };
}

// admin.auth.admin.createUser() "email zaten kayıtlı" hatasıyla başarısız
// olduğunda (orphan senaryo: Auth hesabı var ama kullanicilar.auth_user_id
// linklenmemiş), mevcut hesabı e-postadan bulmak için ham REST çağrısı.
// supabase-js SDK'sının listUsers() sürümden sürüme email filtresini
// desteklemeyebileceği için filtreyi hem query param'da deniyoruz hem de
// -- filtre sunucuda yok sayılsa bile doğru sonucu bulmak için -- istemci
// tarafında e-postaya göre elle süzüyoruz.
async function mevcutAuthUserIdEmailIle(SB_URL: string, SERVICE_KEY: string, email: string): Promise<string | null> {
  for (let page = 1; page <= 5; page++) {
    const r = await fetch(
      `${SB_URL}/auth/v1/admin/users?page=${page}&per_page=200&email=${encodeURIComponent(email)}`,
      { headers: { apikey: SERVICE_KEY, Authorization: "Bearer " + SERVICE_KEY } }
    );
    if (!r.ok) return null;
    const data = await r.json();
    const users = data?.users || [];
    const found = users.find((u: any) => u.email === email);
    if (found) return found.id;
    if (users.length < 200) break;
  }
  return null;
}

// GÜVENLİK (pentest-2 bulgu [4]): rate-limit kimliği İSTEMCİDEN türetilmemeli.
// ÖNCEKİ HALİ x-forwarded-for'un EN SOLDAKİ değerini alıyordu — o değeri saldırgan
// kendi isteğine yazar; her denemede farklı IP hash'i üretip 15dk/10 deneme
// limitini tamamen atlatıyordu.
//
// DOĞRUSU: zincirin EN SAĞINDAKİ değer, güvendiğimiz son proxy (Supabase edge)
// tarafından eklenir; saldırgan kendi eklediği değerleri ancak SOLA yazabilir.
// Supabase'in kendi başlığı (x-real-ip / cf-connecting-ip) varsa o tercih edilir.
function clientIp(req: Request): string {
  const guvenilir = req.headers.get("cf-connecting-ip") || req.headers.get("x-real-ip");
  if (guvenilir) return guvenilir.trim();
  const fwd = req.headers.get("x-forwarded-for");
  if (fwd) {
    const parcalar = fwd.split(",").map((x) => x.trim()).filter(Boolean);
    if (parcalar.length) return parcalar[parcalar.length - 1];   // ★ EN SAĞDAKİ
  }
  return "bilinmeyen-ip";
}

async function sha256Hex(input: string): Promise<string> {
  const data = new TextEncoder().encode(input);
  const digest = await crypto.subtle.digest("SHA-256", data);
  return Array.from(new Uint8Array(digest)).map((b) => b.toString(16).padStart(2, "0")).join("");
}

function json(obj: unknown, status: number, cors: Record<string, string>) {
  return new Response(JSON.stringify(obj), { status, headers: { ...cors, "Content-Type": "application/json" } });
}
