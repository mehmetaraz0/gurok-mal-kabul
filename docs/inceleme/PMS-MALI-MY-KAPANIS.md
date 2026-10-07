# PMS mali paket — MY-1/MY-2/MY-3 kapanış kaydı

Tarih: 2026-10-06. Kapanış incelemesi:
`2026-10-06-36c7def-PMS-MY-kapanis-ve-MY4-kapsam.md` (incelemeci: Codex).
Düzeltme commit'i: `36c7def`. Taban: `a0f1c10`.

**Bu üç bulgu KAPALIDIR ve yeniden açılmaz.** Kapanış, bütün mali paketin yayın
kabulü değildir; canlı uygulama yetkisi verilmemiştir.

| # | Bulgu | Kapanış kanıtı (bağımsız koşum) |
|---|---|---|
| **MY-1** | Yayın bağımlılığı yalnız `K1='kayit'` iken çalışıyordu; `onburo_vardiya` her iki seçenekte de `pms_folio=kayit` alıyor | Kapı artık `pms_hedef` içindeki folyo yazma yetkisine bağlı. T0a/T0c iki seçeneği de `MALI_AYRIM_KURALI_YOK` ile reddetti, T0b/T0c2 sıfır satır ölçtü, T0e/T0e2 kural kurulunca 15 satır yazıldığını doğruladı |
| **MY-2** | `app.pms_mali_geri_zorla` bayrağı güvenli geri dönüş şartını atlıyordu | Bayrak dosyadan tamamen kaldırıldı. M8c2'de bayrak oturum düzeyinde verildi, geri alma `GUVENLI GERI DONUS ENGELI` ile durdu; M8c3'te vardiyanın negatif ödemesi hâlâ reddedildi; M8d/M8e/M8f korundu |
| **MY-3** | `current_user <> session_user` + `kaynak_tip='bar'` istisnası taklit edilebiliyordu | İstisna kaldırıldı. `service_role` bağlamında bar etiketli negatif hareket `MALI_TAM_YETKI_GEREKLI` ile reddedildi; normal yol da reddetti; negatif bar satırı oluşmadı |

İstisnanın **gereksiz** olduğu kısıtlarla ölçüldü: `bar_siparis_kalemleri.adet > 0`,
`menu_urunler.fiyat >= 0`, `tutar = 0` durumunda erken dönüş ve
`bar_borc_istisnalari.tutar > 0` → bar köprüsünün tutarı negatif olamaz.

## Kapanıştan sonra tamamlananlar

- **Gerçek bar köprüsü olumlu kontrolü:** bar kimliğiyle sipariş → kalem →
  teslim; folyoya **tek pozitif** hareket yazıldı (0 → 500,00), tip `bar`,
  negatif bar satırı yok. (MY3e1…MY3e7)
- **Mali migration uygulanmış tabanda regresyon:** dört PMS süiti **59/0**,
  dialog süiti **31/0**. Opt-in `PMS_EK_MIGRASYON` kancasıyla; kancanın gerçekten
  çalıştığı, geçersiz yol verildiğinde süitin durmasıyla ölçüldü.

## Borç istisnası yolu — KAPANDI

Önceki sürümde SINANMADI idi. Artık ayrı ve temiz fikstürlü kalıcı testte
ölçülüyor: `scripts/pms-bar-borc-istisnasi.test.mjs` — **17 geçti / 0 kaldı**.
Migration sırası referans sondayla aynı: A1 güvenlik → mali kural → A1 tohumu.

| Ölçüm | Sonuç |
|---|---|
| Normal teslim, açık folyoya tam bir +250,00 borç | B2 / B2b |
| Mükerrer teslim borcu çoğaltmıyor | B3 |
| Kapalı folyoda teslim +250,00 borç istisnası üretiyor, kapalı folyoya yazmıyor | B4 / B4b |
| Çözen kimlik `pms_folio=kayit`, `tam=false` (yetki genişletilmedi) | B5 |
| Gerçek `bar_borc_istisnasi_coz`: **aynı konaklamanın açık folyosuna** tam bir +250,00 | B6 / B6b / B6c |
| İkinci çağrı mükerrer borç oluşturmuyor | B7 / B7b |
| Mali yetki koruması sürüyor (RLS atlayan ve normal bağlamda taklit negatif ret) | B8 / B8b / B8c |

## Açık kalan

MY-4 **yalnız yerelde uygulandı ve doğrulandı** (46/0):
`docs/inceleme/PMS-MY4-ROL-ENTEGRASYON-KAPSAMI.md`. Canlı rol erişimi hâlâ verilmedi.
