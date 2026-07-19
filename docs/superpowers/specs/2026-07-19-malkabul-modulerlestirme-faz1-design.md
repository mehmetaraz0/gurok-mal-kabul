# Mal Kabul — Modülerleştirme Faz 1 — Tasarım

## Problem / Hedef

`mal-kabul-v2.html` (2370 satır, 7 sekme) `satin-alma.html`'in Faz 1
öncesi haliyle aynı desende: `.tab-bar` + `gTab()` ile canlı DOM-içi
sekme geçişi. Kullanıcı, `satin-alma.html`'e uygulanan modülerleştirmeyi
burada da istiyor. Faz 1, gerçekten bağımsız 4 sekmeyi ayrı dosyalara
taşır; kalan 3 sekme (Liste, Kalite Onayı, İzleme) paylaşılan bir
çekirdek nedeniyle sonraki bir faza bırakılır.

## Kapsam

Detaylı mimari, sıralama ve doğrulanmış kritik bağımlılıklar (kod
okunarak teyit edildi) `C:\Users\mta-1\.claude\plans\flickering-
giggling-koala.md`'de (Mal Kabul — Modülerleştirme Faz 1 bölümü). Özet:

- **4 hedef**: Sipariş Takip, SKT Takip, LN Export, Uygunsuzluk.
- **2 doğrulanmış kritik düzeltme**:
  1. `kaliteReddet()` (mal-kabul-v2.html:1396) `renderUygun()` çağırıyor
     — Uygunsuzluk taşınırken bu satır silinmezse Kalite Reddet akışı
     kırılır.
  2. `lnExportYap()`/`mkFormuIndir()` (2153, 2180) `Object.values(
     malKabuller)` okuyor — LN Export taşınırken kendi tarih-aralığı
     Supabase sorgusuna çevrilmesi taşımanın önkoşulu.
  3. `uygunsuzlukYazdir()` (1782-1783, 1838-1840) `malKabuller[r.mk_id]`
     üzerinden firma/otel/miktar/birim okuyor — Uygunsuzluk'un lazy
     mk-sorgusu bunları da içermeli ve `mkSbdenCamele()`'nin şekline
     uydurulmalı.
- **Kapsam dışı**: Liste+Kalite+İzleme (paylaşılan ~450 satırlık
  çekirdek + gerçek stok yazma işlemleri), `gurok_mal_kabul.html` kararı
  (dosya gerçekten ölü — head'de koşulsuz `location.replace(
  'mal-kabul-v2.html')` var — ama silme kararı kullanıcıya ait), ölü kod
  (`ROL_INDIRGEME`, `siparisAramaTemizle`).

## Doğrulama

Her adımdan sonra statik grep + tarayıcı testi. Uygunsuzluk adımından
sonra Kalite'nin Reddet butonu mutlaka canlı test edilir (kritik
regresyon noktası — `kaliteReddet()` düzeltmesi doğru yapılmazsa
`ReferenceError` fırlatır). Son adımda index.html'in "Raporlar"
kartının `#izleme` hash yönlendirmesi ve `satin-alma-siparisler.html`
→ `mal-kabul-v2.html` sessionStorage handoff'u (Liste hâlâ ana dosyada
kaldığı için etkilenmemeli) doğrulanır.
