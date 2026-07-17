# Supabase Bağlantı Sabitleri — Ortak Dosyaya Çıkarma — Tasarım

## Problem / Hedef

`SB_URL`, `SB_KEY`, `SB_HEADERS` sabitleri 23 dosyada birebir aynı
kopyalanmış (aynı Supabase proje URL'i, aynı anon key). Denetim raporunda
işaretlenen bir bulgu — anahtar rotasyonu gerekirse 23 dosyanın elle
güncellenmesi gerekir. `ortak.js`/`theme.css` deseninin doğrudan devamı.

## Kapsam

- Yeni `supabase-config.js`: `SB_URL`, `SB_KEY`, `SB_HEADERS`.
- 23 dosyada (`gurok_mal_kabul.html`/`index.html.html` hariç — önceki
  "şüpheli ölü kod" kararı gereği dokunulmuyor) yerel 3 satırlık tanım
  silinip `<script src="supabase-config.js">` ile değiştirilir.

## Kapsam dışı

- `OTEL_ISIMLERI` gibi başka küçük tekrarlanan sabitler — ayrı bir bulgu,
  bu işin kapsamında değil.
- `gurok_mal_kabul.html`/`index.html.html` — önceki karar gereği hâlâ
  dokunulmuyor.

## Mimari

`supabase-config.js`, `auth-guard.js`'den hemen sonra, `ortak.js`/
`onay-motoru.js`/`efatura-adapter.js`'den ÖNCE yüklenir (onlar `SB_URL`/
`SB_HEADERS`'ın zaten tanımlı olduğunu varsayıyor). `const` kullanıldığı
için — `ortak.js`'teki fonksiyonların aksine — yerel tanım MUTLAKA
silinmeli; aksi halde "Identifier already declared" hatası oluşur (bu
fonksiyonlardan farklı olarak burada sayfa-özel override senaryosu yok,
hepsi aynı değeri taşıyor).

## Doğrulama

Silinecek 3 satırın 23 dosyanın hepsinde byte-byte aynı olduğu grep ile
doğrulandı. Her dosyada silme sonrası `SB_URL`/`SB_KEY`/`SB_HEADERS` hâlâ
tanımlı olmalı (artık `supabase-config.js`'ten) — tarayıcıda örnekleme
testiyle doğrulanacak.
