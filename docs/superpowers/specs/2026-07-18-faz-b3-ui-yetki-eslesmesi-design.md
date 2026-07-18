# Faz B3 — İstemci Tarafı UI Yetki Eşlemesi — Tasarım

## Problem / Hedef

Faz B0-B2, `yetki_matrisi` tabanlı gerçek RLS kısıtlamasını 11 tabloya
uyguladı — bu, veri seviyesinde gerçek güvenlik sağlıyor (devtools'tan
atlatılamaz). Ama arayüz bundan habersiz: portal menüsü hâlâ **eski,
ayrı bir yetki sistemini** (`kullanicilar.rol` metin alanı + her modül
kutucuğuna gömülü sabit `roller: [...]` listesi, `index.html`'deki
`MODULLER` dizisi) kullanıyor — yeni `rol_id` → `yetki_matrisi`
sistemiyle hiç bağlantısı yok. Sayfa içindeki butonlar (Kaydet, Sil)
hiçbir yetki kontrolü yapmıyor; yetkisi olmayan biri butona basınca
RLS onu sessizce reddediyor ama arayüz bunu önceden söylemiyor.

Bu faz, portal menüsünü ve bir pilot sayfanın butonlarını **gerçek**
`yetki_matrisi` verisiyle eşleştiriyor. Kozmetik bir katman — gerçek
güvenlik zaten B1/B2'den geliyor, bu sadece arayüzü o gerçekle tutarlı
hale getiriyor.

## Önemli bulgu (investigation sırasında tespit edildi)

`index.html`'in portal menüsü (`MODULLER` dizisi, 10 kutucuk: Mal
Kabul, Stok Takip, Depo Siparişleri, Satın Alma, Raporlar, Yönetim,
Muhasebe, F&B Bar, Günlük Tüketim, Trendler) her kutucukta sabit bir
`roller: ['yonetici','depo',...]` (eski metin rol) listesi taşıyor.
`kullanicilar.rol` (eski metin) ile `kullanicilar.rol_id` (yeni FK)
bazı kullanıcılarda tutarsız (örn. Şeyma Yılmaz: `rol`="muhasebe_muduru"
ama `rol_id` "grup_finans"a işaret ediyor — curl ile doğrulandı). Bu
yüzden eski sistemi kullanmaya devam etmek, B3'ün "gerçek yetkiyle
tutarlı" hedefini boşa çıkarır. Kullanıcı onayıyla: eski `roller: [...]`
listesi tamamen kaldırılıyor, portal `rol_id` → `yetki_matrisi`
üzerinden çalışacak.

## Kapsam

1. **Paylaşılan yetki önbelleği** (`auth-guard.js`'e eklenecek yeni
   fonksiyon): Giriş yapmış kullanıcının `rol_id`'sine ait TÜM
   `yetki_matrisi` satırlarını TEK bir REST sorgusuyla çekip
   `{modul_kod: yetki_seviye}` şeklinde bir nesneye dönüştürür ve
   döner. Her sayfa kendi başına bir kez çağırır (buton/kutucuk başına
   ayrı sorgu YOK).
2. **Portal menüsü** (`index.html`): Her `MODULLER` kutucuğuna, hangi
   gerçek modül kod(lar)ına karşılık geldiğini belirten yeni bir
   `moduller: [...]` alanı eklenir. Kutucuk, o modüllerden HERHANGİ
   birinde en az "görüntüle" yetkisi varsa gösterilir. Eski `roller`
   alanı ve `rol` bazlı filtre kaldırılır.
3. **Pilot sayfa** (`muhasebe-cariler.html`): `cari_hesaplar`
   modülündeki yetki seviyesi "görüntüle" ise Kaydet (`cariKaydet`,
   `hareketKaydet`) ve Sil (`cariSil`, id=`c-sil-btn`) butonları
   gizlenir/pasif olur; "kayıt"/"tam" ise aktif kalır. "Yok" ise zaten
   sayfaya hiç girilemiyor olmalı (mevcut `requireRole` bunu büyük
   ölçüde zaten engelliyor — bu fazda pilot sayfanın kendi
   `requireRole` listesini değiştirmiyoruz, sadece buton görünürlüğünü
   ekliyoruz).

## Kapsam dışı

- Kalan ~27 sayfanın buton seviyesi güncellenmesi — pilotta desen
  kanıtlandıktan sonra, B1→B2 deseniyle aynı şekilde ayrı bir sonraki
  iş olarak yayılır.
- `kullanicilar.rol` metin alanının veritabanından tamamen kaldırılması
  — hâlâ başka yerlerde (ROL_AD/ROL_IKON, requireRole listeleri)
  kullanılıyor, bu fazın kapsamı sadece portal menüsü filtresi.
- Eski `rol`/yeni `rol_id` tutarsızlığının (Şeyma örneği) veri
  düzeltmesi — ayrı, kullanıcı kararı gerektiren bir konu.

## Mimari

`auth-guard.js`'e eklenen yeni fonksiyon:

```js
async function kullaniciYetkileriGetir() {
  const user = oturumGetir();
  if (!user || !user.rol_id) return {};
  try {
    const r = await fetch(SB_URL + '/rest/v1/yetki_matrisi?select=yetki,moduller(kod)&rol_id=eq.' + user.rol_id, { headers: SB_HEADERS });
    if (!r.ok) return {};
    const rows = await r.json();
    const harita = {};
    rows.forEach(row => { if (row.moduller) harita[row.moduller.kod] = row.yetki; });
    return harita;
  } catch (e) { return {}; }
}
```

`index.html`'deki `MODULLER` dizisindeki her girdiye `moduller: [...]`
eklenir (örn. `muhasebe` kutucuğu → `['hesap_plani','cari_hesaplar',
'fatura_giris','fatura_onay','odeme_yapma','uc_yollu_eslestirme',
'yevmiye_fis_giris','yevmiye_fis_onay','banka_kasa','doviz_manuel',
'mizan_raporlar','denetim_izi','donem_kilitleme','demirbas_yonetimi',
'cek_senet_yonetimi','butce_yonetimi','sene_sonu_kapama','e_fatura',
'e_defter','muhasebe_asistan']`). `renderModuller()` artık `rol`
parametresi yerine önbelleğe alınmış yetki haritasını kullanır; bir
kutucuk `m.moduller.some(kod => ['goruntule','kayit','tam'].includes(harita[kod]))`
ise gösterilir.

`muhasebe-cariler.html`'de sayfa yüklendiğinde
`kullaniciYetkileriGetir()` çağrılır, `cari_hesaplar` seviyesi
kontrol edilir; `goruntule` ise Kaydet/Sil butonlarına `disabled` /
`style="display:none"` uygulanır.

## Hata yönetimi

`kullaniciYetkileriGetir()` her hata durumunda boş nesne (`{}`) döner
— hiçbir modülde yetki yokmuş gibi davranır (en güvenli varsayım:
gösterme/pasif bırak, asla "her şeyi göster" yönünde hataya düşme).
Portal tarafında bu, ağ hatası olursa hiçbir kutucuğun görünmemesi
riski taşır — kabul edilebilir (RLS zaten arka planda korunuyor,
sadece kozmetik bir gecikme/boşluk olur, güvenlik açığı değil).

## Test / doğrulama planı

Statik: Yeni fonksiyonun hata-toleranslı olduğunu, portal kutucuk
görünürlük mantığının doğru modül kodlarına referans verdiğini kod
okuyarak doğrulamak.

Gerçek (controller tarafından curl ile): Şeyma'nın (grup_finans, çoğu
muhasebe modülünde "tam") token'ıyla `yetki_matrisi` sorgusunun doğru
haritayı döndürdüğünü doğrulamak.

Gerçek uçtan uca (kullanıcı tarafından tarayıcıda): Şeyma ile giriş
yapıp portalda Muhasebe kutucuğunun göründüğünü, `muhasebe-cariler.html`
sayfasında Kaydet/Sil butonlarının aktif olduğunu doğrulamak; sadece
"görüntüle" yetkisi olan bir rolle (örn. grup_direktor, cari_hesaplar=
goruntule) aynı sayfada butonların gizli/pasif olduğunu doğrulamak.
