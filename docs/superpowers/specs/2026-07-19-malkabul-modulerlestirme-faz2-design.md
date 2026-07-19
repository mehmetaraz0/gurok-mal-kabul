# Mal Kabul — Modülerleştirme Faz 2 Design

## Context

Faz 1'de Sipariş Takip, SKT Takip, LN Export, Uygunsuzluk ayrı dosyalara
taşındı; `mal-kabul-v2.html` 2370→1754 satıra indi ama Liste (Mal Kabul
girişi), Kalite Onayı ve İzleme paylaşılan bir çekirdek nedeniyle bir
arada bırakılmıştı. Bu faz, son 3 parçayı da ayırıp `mal-kabul-v2.html`'i
`satin-alma.html` gibi saf bir hub sayfasına çevirir.

## Mimari karar

Liste + Kalite arasında gerçek bir transaction-benzeri çekirdek var:
`mDetay`/`mKabulOzet`/`mKoli`/`mUrunDuzelt`/`mSecEkrani` modalleri,
`openDetay()`, `duzeltmeModuAc()`, `stoktanGeriAl()`,
`siparisMiktarUygula()`, `urunDuzeltAc/Kaydet()`, `kabulOzetAc()`→
`koliEtiketYazdir()`, `stokaIsle()` — hem Liste'nin detay modalından hem
Kalite'nin onay akışından çağrılıyor, gerçek stok/mal_kabul/sipariş
yazma işlemleri içeriyor. Bu çekirdek bölünmeden **tek dosyada**
(`mal-kabul-liste.html`) taşınır.

İzleme mimarî olarak temiz ayrılır (`mal-kabul-izleme.html`) — Liste'ye
özel hiçbir state'e bağımlı değil, sadece `malKabuller`+
`uygunsuzluklarAcik`'i okuyor. Tek bağımlılığı `openDetay(id)` çağrıları
— bunlar `location.href='mal-kabul-liste.html?detay='+id` Bridge'ine
çevrilir.

## Kapsam

1. `mal-kabul-izleme.html` — tab-esleme (3 alt-sekme), kendi `loadDB`'i
   (sadece `mal_kabuller`+`uygunsuzluklar acik`), `mkSbdenCamele` kopyası,
   `openDetay` çağrıları Bridge'e çevrilir.
2. `mal-kabul-liste.html` — tab-liste + tab-kalite + 5 modal + paylaşılan
   çekirdek, aynen taşınır. `?detay=<id>` ve `?tab=kalite` query param
   alıcıları eklenir. `gTab()` sadece liste/kalite arasında toggle olur.
3. `mal-kabul-v2.html` → 7 kartlık hub (satin-alma.html deseni).
4. `index.html`'in "Raporlar" kartı `mal-kabul-v2.html#izleme` →
   `mal-kabul-izleme.html`.

## Doğrulama

Faz 1'deki desenin aynısı: statik grep + tarayıcı testi her adımdan
sonra. `siparisler`/`mal_kabuller` RLS SELECT kısıtı (Faz 1'de
keşfedildi) hâlâ geçerliyse canlı veri testi sınırlı kalabilir.
