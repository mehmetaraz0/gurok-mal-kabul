# Satın Alma — Modülerleştirme Faz 2 — Tasarım

## Problem / Hedef

Faz 1'de `satin-alma.html`'in 9 sekmesinden 4'ü (LN Siparişler,
Firmalar, Fiyat Kontrolü, Tedarikçi Skor Kartı) bağımsız dosyalara
taşındı. Kalan 5 sekme (İç Talepler, Teklifler, Sipariş Oluştur,
Sipariş Takip, İade) sayfa-içi canlı state paylaşımı ve `gTab()`
köprüleri yüzünden ayrı bir işe bırakılmıştı. Faz 2 bu 5 sekmeyi de
taşıyor ve `satin-alma.html`'i `muhasebe.html` deseninde saf bir hub
sayfasına çeviriyor.

## Kapsam

Detaylı mimari, sıralama ve cross-page köprü tasarımı
`C:\Users\mta-1\.claude\plans\flickering-giggling-koala.md`'de
(Satın Alma — Modülerleştirme Faz 2 bölümü) — bu belge onun kalıcı
kopyası + implementasyon sırasında netleşen ek bir bulgu:

**Faz B3 (paralel oturum) satin-alma.html'e planlamadan SONRA,
implementasyondan ÖNCE gerçek yetki-tabanlı buton görünürlüğü ekledi**
(commit `82992e2`): `YETKI_HARITASI` + `kullaniciYetkileriGetir()`
(auth-guard.js'ten) artık İç Talepler (`ic_talep` modül kodu:
talep-excel-yukle-btn, yt-kaydet-btn, yeniden-siparis-btn) ve Sipariş
Oluştur+İade'yi (ikisi de `siparis_olustur` modül kodu: sp-grupla-btn,
iade-olustur-btn, iade-muhasebe-btn) kapsıyor. Teklifler ve Sipariş
Takip'e HENÜZ bu gating eklenmemiş.

**Karar**: taşıma sırasında her sekmenin BUGÜN sahip olduğu gating
aynen korunur (İç Talepler ve Sipariş Oluştur/İade dosyaları
`YETKI_HARITASI` mantığını taşır) — Teklifler ve Sipariş Takip için
YENİ bir gating İCAT EDİLMEZ (hangi modül kodunu kullanacakları
paralel oturumun kararı, tahmin edilip yanlış kod yazılırsa ileride
onların işini bozar). Bu, Dalga 2'de zaten uygulanan "sadece var olan
deseni taşı, yeni yetki kodu icat etme" kuralıyla tutarlı.

## Kapsam dışı

`docs/superpowers/plans/2026-07-19-satinalma-modulerlestirme-faz2.md`
ve plan dosyasındaki "Kapsam dışı" bölümüyle aynı.

## Doğrulama

Plan dosyasındaki "Doğrulama" bölümüyle aynı — her adımdan sonra statik
grep + tarayıcı testi, Bridge A/B adımlarında uçtan uca köprü testi,
son adımda hub'ın index.html'den doğrulanması.
