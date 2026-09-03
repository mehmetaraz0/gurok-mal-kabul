# Yük Testi

## Ne yapar

Uygulamanın **gerçekte yaptığı** okuma sorgularıyla, beş ekran akışını
eşzamanlı kullanıcı altında ölçer ve akış bazlı p95/p99 üretir.

Sorgular uydurma değildir — kaynak taramasıyla, sayfaların açılışta attığı
en sık isteklerden alınmıştır (portal açılışı, stok takip, mal kabul
listesi, sipariş takip, muhasebe yevmiye).

## Kurulum

k6 gerekir: <https://k6.io/docs/get-started/installation/>

Windows'ta: `winget install k6 --source winget`

## Çalıştırma

Önce uygulamada giriş yap, tarayıcı konsolunda jetonu al:

```js
JSON.parse(sessionStorage.getItem('araz_portal_session')).accessToken
```

Sonra:

```bash
k6 run -e JWT="<jeton>" scripts/yuk-testi/k6-okuma.js
```

Seçenekler:

```bash
k6 run -e JWT="<jeton>" -e VU=20 -e SURE=3m scripts/yuk-testi/k6-okuma.js
```

Koşu sonunda `sonuc-ozet.md` (rapora yapıştırılabilir) ve `sonuc-ham.json`
üretilir.

---

## Neden PIN ile giriş yapmıyor

Giriş akışı sunucu tarafında hız sınırlamasına tabidir ve her deneme
`giris_denemeleri` / `giris_kayitlari` tablolarına satır yazar. Yük testi
bunları hem tetikler hem kirletir — üstelik genel deneme tavanı devreye
girerse **gerçek kullanıcıların girişi engellenir**.

Elde hazır jeton kullanmak ayrıca daha gerçekçidir: kullanıcı bir kez
giriş yapar, oturum boyunca aynı jetonu kullanır.

⚠️ Jeton uygulama oturumuyla aynı ömre sahiptir (30 dk). Uzun koşularda
süresi dolarsa istekler 401 döner; hata oranı eşiği bunu yakalar ama
koşudan hemen önce taze jeton almak en iyisi.

---

## Neden yazma senaryosu yok

Bilerek. Üretim veritabanında yük testi amacıyla kayıt üretmek:

- gerçek iş verisini kirletir (sahte mal kabuller, sahte talepler),
- stok ve onay gibi **durum makinelerini** tutarsız bırakabilir,
- geri temizlemesi el işidir ve hata yapmaya açıktır.

Yazma performansı ölçülecekse ayrı bir kopya proje üzerinde yapılmalıdır.

---

## Sonuçları yorumlarken

**Ortalamaya bakma.** Ortalama, birkaç yavaş isteği gizler. Bir zincire
sunulacak raporda p95 ve p99 istenir; bu betik ikisini de üretir.

**Coğrafi gecikme sonucun parçasıdır.** Yükün üretildiği yer ile
veritabanı bölgesi arasındaki mesafe p95/p99'a doğrudan yansır. Rapor
sunulurken **her ikisi de** belirtilmelidir, yoksa rakamlar
karşılaştırılamaz.

**Plan kapasiteyi belirler.** Barındırma planı değişirse bu sonuçlar
geçersizdir ve koşu tekrarlanmalıdır. Küçük bir planda ölçülen rakamı
kurumsal bir taahhüde çevirmek, tutulamayacak bir söz vermektir.

**Eşikler kabul kriteridir.** Betikteki `thresholds` bloğu geçti/kaldı
kararı üretir. Bir raporun "iyi görünüyor" değil, tanımlı bir kritere
göre değerlendirilmiş olması gerekir. Eşikler işletmenin beklentisine
göre değiştirilmelidir — şu anki değerler makul başlangıçlardır, taahhüt
değildir.

---

## İlk koşu için öneri

Küçük başla ve tavanı ara:

```bash
k6 run -e JWT="..." -e VU=5  -e SURE=1m  scripts/yuk-testi/k6-okuma.js
k6 run -e JWT="..." -e VU=20 -e SURE=2m  scripts/yuk-testi/k6-okuma.js
k6 run -e JWT="..." -e VU=50 -e SURE=2m  scripts/yuk-testi/k6-okuma.js
```

Hata oranının yükseldiği veya p95'in eşiği aştığı nokta, o plandaki
**kapasite tavanıdır** — raporda asıl değerli sayı budur.
