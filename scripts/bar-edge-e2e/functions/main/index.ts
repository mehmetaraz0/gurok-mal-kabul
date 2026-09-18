// Edge Runtime ana servisi (YALNIZ TEST) — canlı ad → kaynak dizin eşlemesi.
// Her istek için ilgili fonksiyonun kullanıcı işçisi (user worker) açılır; ortam
// değişkenleri test ortamının YEREL adres/anahtarlarıdır (üretim sırrı yok).
const ESLEME: Record<string, string> = {
  "hyper-api": "/home/deno/functions/src/siparis-gonder",
  "rapid-handler": "/home/deno/functions/src/masa-yonetim",
  "smooth-service": "/home/deno/functions/src/menu-yayinla",
  // Negatif kontrol: testin bozdugu kopya (yalniz test bagladiysa vardir).
  "rapid-handler-negatif": "/home/deno/functions/neg/masa-yonetim",
};

Deno.serve(async (req: Request) => {
  const ad = new URL(req.url).pathname.split("/").filter(Boolean)[0] ?? "";
  const servicePath = ESLEME[ad];
  if (!servicePath) return new Response(JSON.stringify({ ok: false, mesaj: "fonksiyon yok: " + ad }), { status: 404 });
  const disla = new Set(["HOSTNAME", "HOME", "PATH"]);
  const envVars = Object.entries(Deno.env.toObject()).filter(([k]) => !disla.has(k));
  try {
    // deno-lint-ignore no-explicit-any
    const worker = await (globalThis as any).EdgeRuntime.userWorkers.create({
      servicePath,
      memoryLimitMb: 256,
      workerTimeoutMs: 60_000,
      noModuleCache: false,
      importMapPath: "/home/deno/functions/main/import_map.json",
      envVars,
    });
    return await worker.fetch(req);
  } catch (e) {
    return new Response(JSON.stringify({ ok: false, mesaj: "isci hatasi: " + String(e) }), { status: 500 });
  }
});
