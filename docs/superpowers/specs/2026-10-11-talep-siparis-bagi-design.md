# Talep → Sipariş: tek transaction'lı oluşturma, izlenebilir bağ, ortak numara

**Tarih:** 2026-10-11
**Durum:** TASARIM. Kod yazılmadı, migration uygulanmadı, push yapılmadı.
**Kaynak karar:** `satin_alma_talepleri.siparis_no` hiç doldurulmuyor
(`talep_siparise_donustur` yalnız `durum='siparis'` yazıyor; sipariş numarası
sonra, istemcide üretiliyor). Bir talep birden fazla siparişe bölünebildiği
için tek metin alanı yetersiz.

---

## 1. Merkezi değişmez (INV)

> Her talep kalemi için: **iptal olmayan** siparişlere ait bağların toplamı,
> kalemin miktarını aşamaz. Tüm miktarlar **kalemin kendi biriminde** tutulur.

Tasarımın geri kalanı bu cümlenin her değişiklik yolundan korunmasıdır.

### 1.1 Birim dondurma kuralı (en kritik kural)

Bağ yazıldığı anda sipariş satırının miktarı, **talep kaleminin o andaki
birimine** çevrilir ve öyle saklanır. Kalan hesabı **hiçbir zaman** güncel
katalog dönüşümünü kullanmaz.

**Neden:** katalog çarpanı sonradan değişirse, talep miktarını güncel çarpanla
yeniden hesaplayan bir formül eski kalanı bozar. Ölçülmüş örnek: 10 KOL talep ·
12 KG/KOL · 72 KG bağ → kalan 48 KG. Çarpan 24'e çıktığında "miktar × güncel
çarpan − bağlı" formülü 240 − 72 = **168 KG** verir; doğrusu **48 KG**'dir.
Bu yüzden görünüm katalog tablolarına **hiç katılmaz**.

---

## 2. Ölçülen zemin

Tasarım tahmine değil, repodan ve üretim şema dökümünden okunan şu gerçeklere
dayanır:

| Gerçek | Tasarıma etkisi |
|---|---|
| `siparisler.siparis_no` **PRIMARY KEY** | Mükerrer numara fiziksel olarak yazılamaz; son güvence |
| Numara biçimi `C`/`R` + 8 hane, taban 91110 | Biçim korunur; 8 hane ⇒ sözlük sırası = sayı sırası (kayıtlı bağımlılık) |
| `yeniSiparisNoUret` **üç ayrı kopya** (siparişoluştur · iade · stok-takip), hepsi istemcide `max+1` | Üçü de ortak sunucu üretecine taşınır |
| `sip_insert` RLS: `siparis_olustur:kayit` + `auth_otel_erisim` | RPC bu iki kontrolü gövdede yeniden uygular |
| `siparisler` üzerinde `phase0_islem_audit` | RPC gerçek ERP kimliğiyle koşar; kimliksiz yazma reddedilir |
| `satin_alma_talep_kalemleri`: `id` var, `otel_id` **yok**, `miktar numeric(12,3)`, `urun_kodu` **nullable** | Bağ anahtarı kalem `id`'si; kapsam talep üzerinden; hassasiyet sınırı 3 hane |
| `urunler.birim` NOT NULL (vars. `KG`) | Ürünün taban birimi |
| `urun_birim_donusum`: `buyuk_birim` + `carpan` (CHECK `> 0`) + `silindi` | `1 buyuk_birim = carpan × urunler.birim`; ürün başına **tek** çift |
| `siparisler.durum` serbest metin; `'iptal'` kullanımda | İptal semantiği bu dizgiye dayanır (bkz. §11 risk 6) |
| `satin_alma_talepleri.siparis_no` hiç yazılmıyor | Ölü kolon; bağ tablosu yerini alır, kolona dokunulmaz |

---

## 3. Veri modeli

### 3.1 `public.talep_siparis_baglari` (yeni)

```
id               uuid pk default gen_random_uuid()
otel_id          otel_id       not null                  -- RLS kapsamı (denormalize)
talep_id         uuid          not null → satin_alma_talepleri(id)
talep_kalem_id   uuid          not null → satin_alma_talep_kalemleri(id)
siparis_no       text          not null → siparisler(siparis_no) ON DELETE RESTRICT
urun_kodu        text                                    -- SUNUCUDA kalemden türetildi
miktar           numeric(12,3) not null check (miktar > 0)
hedef_birim      text          not null                  -- TALEP KALEMİNİN birimi, yazıldığı andaki hâli
kaynak_miktar    numeric(12,3) not null check (kaynak_miktar > 0)
kaynak_birim     text          not null
carpan           numeric       check (carpan is null or carpan > 0)
olusturan_ad     text
olusturma_tarihi timestamptz   not null default now()
unique (talep_kalem_id, siparis_no)
```

- `miktar` **`hedef_birim`** cinsindendir (§1.1).
- `hedef_birim` = bağ yazıldığı anda talep kaleminin `birim` değeri. Katalog
  birimi **değil**; katalog sonradan değişse hesap bozulmaz.
- `kaynak_miktar` / `kaynak_birim` / `carpan`: denetim izi — "bu 6 KOL nasıl
  72 KG oldu" sorusunu cevaplar.
- `urun_kodu` istemciden **alınmaz**, talep kaleminden türetilir.
- FK `ON DELETE RESTRICT`: bağ geçmişi silinemez (§7).

**RLS:** `select` → (`siparis_olustur` | `siparis_takip`):`goruntule` **ve**
`auth_otel_erisim(otel_id)`; ayrıca diğer tablolarla aynı restrictive
`phase0_otel_kisit` deseni. `insert`/`update`/`delete` **politikası yok** ve
`authenticated`'a yazma ayrıcalığı **verilmez** — yazma yalnız
`security definer` RPC üzerinden. Tablo mantıksal olarak append-only.

**İndeksler:** `(talep_kalem_id)` · `(siparis_no)` · `(otel_id, talep_id)`.

### 3.2 `public.siparis_no_sayac` (yeni)

```
prefix     text pk check (prefix in ('C','R'))
son_no     bigint not null
guncelleme timestamptz not null default now()
```

Migration'da mevcut maksimumdan tohumlanır (`C` ve `R` ayrı). `authenticated`'a
doğrudan hak verilmez; yalnız üretici fonksiyon yazar.

### 3.3 `public.siparisler` eklentileri

| Kolon | Tanım |
|---|---|
| `islem_anahtari` | `text`, nullable, `check` uzunluk 8–100, **kısmi unique** indeks (`where islem_anahtari is not null`) |
| `islem_parmak_izi` | `text`, nullable — normalize edilmiş istek içeriğinin özeti |

İkisi de nullable; diğer üç sipariş yolu bu kolonları yazmaz, davranışları
değişmez. Paylaşılan tabloya kolon eklendiği için şema dökümü ve eşitlik
doğrulayıcısı güncellenir (§11 risk 4).

---

## 4. Ortak sipariş numarası üretimi

```
public.siparis_no_uret(p_prefix text) returns text   -- security definer
  1. siparis_no_sayac satırını `for update` ile kilitle          (SERİ)
  2. v := greatest(sayac.son_no,
                   max(siparis_no'nun sayısal kısmı, aynı önek))
  3. sayac.son_no := v + 1
  4. return p_prefix || lpad((v+1)::text, 8, '0')
```

| Katman | Rolü |
|---|---|
| Satır kilidi | Eşzamanlı çağrılar sıraya girer; iki çağrı **asla** aynı numarayı almaz |
| `greatest(...)` | Sayaç geride kalırsa (elle yazılmış kayıt, eski veri) kendini toparlar |
| `siparis_no` PK | Her şeye rağmen son güvence |

**Dört yol da bunu kullanır:** talep RPC'si içeriden (aynı transaction), diğer
üç istemci yolu RPC çağrısıyla. İstemci insert'lerine dokunulmaz.

**Zorunlu etkiler:**

1. Numara yarışı **kapanır**: tek seri kaynak.
2. **Boşluk olabilir** — numarayı alıp siparişi yazmayan çağrı numarayı tüketir.
   Diziler gibi; kabul edilmiş davranış.
3. **Fail-closed:** numara üretilemezse sipariş yazılmaz, kullanıcı görünür hata
   alır. İstemcideki `catch` içi **rastgele numara üretimi kaldırılır** —
   sessizce uydurma numara bu tasarımın reddettiği şeydir.
4. İade yolu aynı `C`/`R` havuzunu `tip='iade'` ile kullanır; üretici önek
   bazlıdır, iade numaraları atlanmaz.
5. Biçim değişmez. `99999999` aşılırsa sözlük sıralaması bozulur — bugünkü
   istemci kodu da aynı varsayıma dayanıyor; kayıtlı sınır.

---

## 5. Birim doğrulaması (yazma anında)

Bağ yazılırken sipariş satırının miktarı talep kaleminin birimine çevrilir.
**Doğrulanmış** dönüşüm yalnız şu hâllerde vardır:

| Sipariş satırının birimi | Katsayı | Sonuç |
|---|---|---|
| Talep kaleminin birimine eşit | `1` | doğrudan |
| `urun_birim_donusum.buyuk_birim`'e eşit (`silindi=false`) ve talep kaleminin birimi `urunler.birim`'e eşit | `carpan` | `kaynak_miktar × carpan` |
| Talep kaleminin birimi `buyuk_birim`, sipariş satırı `urunler.birim` | `1/carpan` | `kaynak_miktar / carpan` |
| Başka her durum | **yok** | **RET** `birim_cevrilemez` |

`urun_kodu` boş olan kalemde katalog yoktur → yalnız aynı birim kabul edilir.
`carpan` null ya da `≤ 0` ise `carpan_gecersiz`.

Hesaplanan `miktar` `numeric(12,3)`'e yuvarlanır; yuvarlama sonucu `0` olursa
`miktar_gecersiz` ile reddedilir (sessiz sıfır bağ yazılmaz).

---

## 6. RPC `siparis_olustur_talepten`

```
siparis_olustur_talepten(
  p_islem_anahtari text,
  p_talep_id       uuid,
  p_otel_id        text,
  p_firma_ad       text,
  p_cari_id        uuid,
  p_tarih          date,
  p_termin         date,
  p_satirlar       jsonb   -- [{talep_kalem_id, miktar, birim, tahmini_fiyat}]
) returns jsonb
```

`security definer` · `set search_path = pg_catalog, public, pg_temp` · **tek
transaction**. `urun_kodu` / `urun_adi` **istemciden alınmaz**.

Her ret `raise exception ... using errcode` ile verilir; **`return` ile ret
verilmez**, çünkü `return` transaction'ı geri almaz ve o ana kadar yazılmış
satırları bırakır.

| # | Kontrol | Ret kodu |
|---|---|---|
| 1 | `auth_yetki_var('siparis_olustur','kayit')` | `yetkisiz` (42501) |
| 2 | `auth_otel_erisim(p_otel_id)` | `otel_kapsami_disi` (42501) |
| 3 | Tekrar gönderme sözleşmesi (§6.1) | `anahtar_celiskili` (23505) |
| 4 | Talep: var · `otel_id` eşleşir · `durum ∈ (onaylandi, siparis)` · **`for update`** | `talep_yok` · `otel_uyusmaz` · `onaylanmamis` |
| 5 | Payload: boş değil · `talep_kalem_id` **tekrarsız** · `miktar > 0` · ölçek ≤ 3 hane | `satir_yok` · `tekrarli_kalem` · `miktar_gecersiz` · `hassasiyet_asimi` |
| 6 | Kalemler bu talebe ait · **`for update`**, `order by id` (sabit kilit sırası ⇒ deadlock yok) | `kalem_yok` |
| 7 | `urun_kodu`/`urun_adi` kalemden türetilir; `hedef_birim` = kalemin birimi; katsayı §5 ile | `birim_cevrilemez` · `carpan_gecersiz` |
| 8 | **INV:** kalem kilidi altında, iptal olmayan bağ toplamı + bu istek ≤ kalem miktarı | `miktar_asimi` (yanıtta kalan miktar) |
| 9 | `siparis_no_uret(prefix)` → `siparisler` (anahtar + parmak izi) → `siparis_kalemleri` → `talep_siparis_baglari` | — |
| 10 | Talebin **tüm** kalemleri tam bağlandıysa `durum='siparis'`; kısmi ise `onaylandi` **korunur** | — |

**Yanıt:** `{ok:true, siparis_no, yazilan_kalem, baglanan_kalem, tam_karsilandi}`.
Aşımda **kırpma yok**: ret verilir ve kalan miktar bildirilir ki arayüz
"kalanı bağla" diyebilsin. Sessiz kırpma kullanıcının bilmediği bir sayı
üretirdi.

### 6.1 Tekrar gönderme sözleşmesi

`islem_parmak_izi` = normalize edilmiş istek özeti: talep · otel · firma ·
cari · tarih · termin · satırlar (`talep_kalem_id` sırasına dizili: miktar,
birim, fiyat).

| Durum | Sonuç |
|---|---|
| Anahtar yok | Normal akış; başarıda anahtar + parmak izi yazılır |
| Anahtar var **+ parmak izi aynı** + `auth_otel_erisim(mevcut.otel_id)` + aynı oluşturan kimlik | Mevcut `siparis_no` → `{ok:true, mukerrer:true}`; **yeni sipariş yazılmaz** |
| Anahtar var **+ parmak izi farklı** | **RET** `anahtar_celiskili` |
| Anahtar var + otel/kullanıcı kapsamı dışı | **RET** `anahtar_celiskili` — başkasının siparişi sızdırılmaz |
| Eşzamanlı aynı anahtar | `unique_violation` yakalanır — **yalnız** `siparisler_islem_anahtari_key` ihlali mükerrer sayılır; `siparisler_pkey` veya başka kısıt ihlali mükerrer **değildir**, olduğu gibi yükselir |

Başarıdan sonra **yeni sipariş yeni anahtar** gerektirir: istemci başarı
yanıtında anahtarı yeniler; aynı anahtarla farklı içerik zaten reddedilir.

---

## 7. INV'i koruyan kapılar

Hepsi aynı hesabı kullanır: **ilgili talep kaleminin satırını `for update` ile
kilitle**, sonra **iptal olmayan** siparişlerin bağlarını topla.

| # | Değişiklik yolu | Kapı | Özel kural |
|---|---|---|---|
| K1 | Bağ `insert` | `before insert` tetikleyici | kalem kilidi → toplam + `new.miktar` ≤ kalem miktarı |
| K2 | Bağ `update` | `before update` tetikleyici | toplamdan **`old.id` çıkarılır** — eski satır iki kez sayılmaz |
| K3 | Siparişi **iptalden geri alma** | `before update of durum` on `siparisler` | `'iptal'` → değil geçişinde o siparişin **her** bağı için INV yeniden sınanır; aşıyorsa ret |
| K4 | **Sipariş kalemi miktarını düşürme** | `before update of miktar` on `siparis_kalemleri` | o siparişin aynı ürüne ait bağ toplamının altına düşürülemez |
| K5 | **Talep kalemi miktarını düşürme** | `before update of miktar` on `satin_alma_talep_kalemleri` | mevcut bağ toplamının altına düşürülemez |
| K6 | **Bağlı talep kaleminin `birim`/`urun_kodu` değişimi** | `before update of birim, urun_kodu` on `satin_alma_talep_kalemleri` | bağı olan kalemde **değiştirilemez** — `hedef_birim` ile tutarlılık korunur (§1.1) |
| K7 | Siparişi **silme** | FK `ON DELETE RESTRICT` + `before delete` tetikleyici (okunur mesaj) | bağı olan sipariş silinemez; düzeltme yolu `durum='iptal'` |

RPC'deki 8. kontrol kullanıcıya anlaşılır mesaj için; tetikleyiciler
**değişmez güvence** için. Bağ hangi yoldan gelirse gelsin INV bozulamaz.

**Asimetri (bilinçli):** sipariş kalemi miktarını **artırmak** INV'i bozmaz,
bu yüzden engellenmez. Yalnız düşürme kapılıdır.

---

## 8. Görünüm: açık talep = kalan miktar

Görünüm **katalog tablolarına katılmaz** (§1.1). Talep miktarından, aynı
birimdeki bağ toplamı çıkarılır; sonuç birime göre gruplanır.

```sql
create or replace view public.stok_acik_talep with (security_invoker=true) as
select t.otel_id,
       tk.urun_kodu,
       tk.birim,
       sum(tk.miktar - coalesce(b.bagli, 0)) as talep_miktar
  from public.satin_alma_talep_kalemleri tk
  join public.satin_alma_talepleri t on t.id = tk.talep_id
  left join (
    select b.talep_kalem_id, b.hedef_birim, sum(b.miktar) as bagli
      from public.talep_siparis_baglari b
      join public.siparisler s on s.siparis_no = b.siparis_no
     where s.durum <> 'iptal'
     group by b.talep_kalem_id, b.hedef_birim
  ) b on b.talep_kalem_id = tk.id and b.hedef_birim = tk.birim
 where t.durum not in ('iptal', 'reddedildi')
 group by t.otel_id, tk.urun_kodu, tk.birim
having sum(tk.miktar - coalesce(b.bagli, 0)) > 0;
```

- `urunler` ve `urun_birim_donusum` **hiç kullanılmıyor** → çarpan değişikliği,
  katalog birimi değişikliği ve dönüşümün pasifleştirilmesi eski kalanı
  **etkilemez**.
- `b.hedef_birim = tk.birim` eşleşmesi aritmetiği sağlam tutar; K6 bu ikisinin
  ayrışmasını zaten engeller. Yine de ayrışma olursa sessiz kalmasın diye
  §8.1'deki denetim sorgusu var.
- Çıktı tanesi `(otel_id, urun_kodu, birim)` — farklı birimler **toplanmaz**.

### 8.1 Denetim sorgusu (kapı değil, görünürlük)

```sql
-- Beklenen sonuç: 0 satır. Varsa K6 aşılmış demektir.
select b.id, b.talep_kalem_id, b.hedef_birim, tk.birim as kalem_birim
  from public.talep_siparis_baglari b
  join public.satin_alma_talep_kalemleri tk on tk.id = b.talep_kalem_id
 where b.hedef_birim <> tk.birim;
```

### 8.2 Sözleşme değişikliği

Görünüm artık `birim` kolonu döndürür. `stok-takip.html` **değişmek
zorundadır**: bugün `urun_kodu` bazında topluyor, artık `(urun_kodu, birim)`
bazında toplayıp birimi göstermelidir. Görünüm ve ekran **birlikte**
yayınlanmalı (§11 risk 5).

---

## 9. İstemci entegrasyonu

| Dosya | Değişiklik |
|---|---|
| `satin-alma-talepler.html` | `sp_devir_satirlar` artık `talepId` + `talepKalemId` taşır; erken `talepSiparisRpc` çağrısı **bu yoldan kalkar** (erken `durum` damgası yok) |
| `satin-alma-siparisolustur.html` | Talep kaynaklı submit → **tek RPC**; istemci numara üretmez, üç ayrı yazma yapmaz. Talepsiz akış sihirbazıyla aynen kalır, yalnız numarayı `siparis_no_uret`'ten alır. `islem_anahtari` sayfa açılışında üretilir (`crypto.randomUUID`), başarıda yenilenir |
| `satin-alma-iade.html` | Yerel `yeniSiparisNoUret` → `siparis_no_uret`; `catch` içi rastgele numara kaldırılır |
| `stok-takip.html` (sipariş oluşturma) | aynı |
| `stok-takip.html` (tablo görünümü) | Talep sütunu `(urun_kodu, birim)` bazında toplar ve birimi gösterir |

Ret kodları kullanıcıya anlaşılır gösterilir; `birim_cevrilemez`,
`miktar_asimi`, `anahtar_celiskili` **sessizce yutulmaz**.

---

## 10. Geçiş kararı — ayrı ve kullanıcıda

**Hiçbir eski kayıt otomatik iptal edilmez, otomatik bağlanmaz.**
`durum='siparis'` olup bağı olmayan **7 talep** ölçüldü (2026-10-11); bağ
hiçbir yerde kayıtlı olmadığı için geriye dönük kurulamaz. Yeni görünümle bu
kayıtlar **yeniden açık talep olarak görünür**.

| Seçenek | Sonucu |
|---|---|
| Olduğu gibi bırak | Ekranda açık görünür; gerçekten sipariş edildilerse sütun şişik kalır |
| Elle `iptal` işaretle | Ekran temizlenir; gerçekten karşılandılarsa kayıt yanlış olur |
| Elle bağ gir (ayrı RPC, kapsam dışı) | En doğru; hangi talebin hangi siparişe gittiği **insan bilgisi** |

Uygulama öncesi güncel liste salt-okuma ile ölçülür ve karar o listeye
bakılarak verilir. **Geçiş adımı migration'ın parçası değildir.**

---

## 11. Riskler ve kayıtlı varsayımlar

1. `security definer` RLS'i atlar → atlanan iki kontrol (`auth_yetki_var`,
   `auth_otel_erisim`) gövdede **açıkça** yeniden uygulanır (MY-4 dersi).
2. Numara biçimi 8 hane / sözlük sırası varsayımı; `99999999` sınırı.
3. Numara boşlukları kabul edilmiş davranıştır.
4. `siparisler`'e iki nullable kolon eklenir → şema dökümü ve eşitlik
   doğrulayıcısı güncellenmelidir.
5. Görünümün **kolon sözleşmesi değişir** (`birim`); görünüm ve
   `stok-takip.html` birlikte yayınlanmalıdır, yoksa sütun yanlış toplar.
6. **`iptal` serbest metindir.** Tüm iptal semantiği `durum = 'iptal'`
   dizgisine dayanır; `'IPTAL'` veya `'iptali'` yazılırsa bağ kalan hesabından
   düşmez. Kesin çözüm `check` kısıtı ya da enum olurdu; bu `siparisler`'in
   paylaşılan durum alanını değiştirmek demektir ve **ayrı karardır**.
7. K4/K5/K6 kapıları `siparis_kalemleri` ve `satin_alma_talep_kalemleri`
   üzerine kapı koyar: bu tablolara yazan **mevcut** akışlar (sipariş
   düzenleme, talep düzenleme) INV'i bozan bir işlem denerse artık hata alır —
   bilinçli davranış değişikliği.
8. Migration güvenlik standardı: iki yeni tablo için RLS + `revoke`/`grant`
   kararı + append-only bekçi; denetleyici **0 HATA / 0 UYARI** olmadan teslim
   edilmez.
9. Üretime yazma yok; `CANLIYA UYGULA` denmedikçe uygulanmaz.

---

## 12. Test matrisi

İzole Docker + üretim şema dökümü. **Her ret yolunda "satır sayıları
değişmedi" kontrolü zorunludur.** Her kapının ayrıca mutant testi vardır:
kapıyı kaldırınca ihlalin **geçtiği** gösterilir.

### 12.1 Tek transaction ve geri alma
Yedi ret kodunun her birinde başlık + kalem + bağ sayıları sabit · mutant:
`return`'lü ret deseni transaction'ı geri almıyor.

### 12.2 Bağ geçmişi (K7)
Bağı olan sipariş **silinemiyor** (FK + tetikleyici, okunur mesaj) · bağsız
sipariş silinebiliyor · `durum='iptal'` bağ satırını **koruyor** ama kalan
hesabından düşüyor · mutant: FK `cascade`'e çevrilirse bağ geçmişi siliniyor.

### 12.3 Birim dondurma — **çarpan/katalog değişikliği eski kalanı bozmuyor**
Kurulum: 10 KOL talep kalemi · `urun_birim_donusum` 12 KG/KOL · 72 KG bağ ·
beklenen kalan **48**.

| Test | Değişiklik | Beklenen kalan |
|---|---|---|
| B1 | — (taban ölçüm) | **48** |
| B2 | `carpan` 12 → **24** | **48** (değişmedi) |
| B3 | `urunler.birim` KG → **LT** | **48** (değişmedi) |
| B4 | Dönüşüm `silindi = true` | **48** (değişmedi) |
| B5 | Dönüşüm satırı **silindi** | **48** (değişmedi) |
| B6 | mutant: görünüm katalog çarpanıyla yeniden hesaplarsa | B2'de **168** çıkar → test kırmızı |

### 12.4 Birim doğrulaması (yazma anı)
Aynı birim → katsayı 1 · `buyuk_birim` → `carpan` ile normalize, `carpan` ve
`hedef_birim` kayıtlı · ters yön (`1/carpan`) · doğrulanmamış çift →
`birim_cevrilemez`, hiç satır kalmıyor · `silindi=true` dönüşüm
**kullanılmıyor** · `urun_kodu` boş + farklı birim → ret · `carpan ≤ 0`/null →
`carpan_gecersiz` · yuvarlamada sıfırlanan miktar → `miktar_gecersiz` ·
istemci farklı `urun_kodu` gönderse bile **kalemden türetilen** yazılıyor ·
4 ondalıklı miktar → `hassasiyet_asimi` · aynı `talep_kalem_id` iki kez →
`tekrarli_kalem`.

### 12.5 Görünüm
Aynı ürünün KG ve KOL kalemleri **ayrı satır**, toplanmıyor · kalan sıfırsa
satır yok · iptal edilmiş siparişin bağı sayılmıyor · talep `iptal`/`reddedildi`
ise dışlanıyor · §8.1 denetim sorgusu temiz tabanda **0 satır**.

### 12.6 İdempotency
Aynı anahtar + aynı içerik → tek sipariş, `mukerrer:true` · aynı anahtar +
**farklı içerik** → `anahtar_celiskili`, yeni sipariş yok · başka
otel/kullanıcının anahtarı → `anahtar_celiskili`, sipariş **sızmıyor** ·
eşzamanlı aynı anahtar → tek sipariş · **`siparis_no` PK ihlali mükerrer
sayılmıyor** (yükseliyor) · başarı sonrası aynı anahtar → ret · farklı anahtar
→ iki sipariş · mutant: kısmi unique indeks düşerse mükerrer geçiyor · mutant:
parmak izi kontrolü kalkarsa farklı içerik mevcut siparişi dönüyor.

### 12.7 Aşım — bütün yollar
K1 insert aşımı · K2 update aşımı **ve** `old.id`'nin iki kez sayılmadığı ·
iki eşzamanlı oturum → ikincisi `miktar_asimi`, toplam asla aşmıyor · ters
sırada eşzamanlı deneme → **deadlock yok** · K4 sipariş kalemi miktarını bağ
toplamının altına düşürme → ret · K4 artırma → **serbest** · K5 talep kalemi
miktarını düşürme → ret · K6 bağlı kalemin `birim`/`urun_kodu` değişimi → ret.

**Kritik senaryo (zorunlu):** sipariş A iptal edilir → serbest kalan miktar
sipariş B'ye bağlanır → **A'yı iptalden geri alma reddedilir** (K3) ve A'nın
bağları yerinde kalır.

Mutantlar: kalem kilidi kalkarsa eşzamanlı aşım geçiyor · `old.id`
çıkarılmazsa K2 yanlış reddediyor · iptal süzgeci kalkarsa iptal edilmiş
sipariş talebi kilitli tutuyor · K6 kalkarsa `hedef_birim` ayrışıyor ve §8.1
sorgusu satır veriyor.

### 12.8 Numara üretimi
Eşzamanlı N çağrı → **N farklı** numara · sayaç geride bırakılırsa `greatest`
toparlıyor · tohumlama mevcut maksimumdan doğru başlıyor · iade öneki havuzu
paylaşıyor · biçim `C`/`R` + 8 hane korunuyor · boşluk oluşabiliyor ama numara
**tekrar etmiyor** · mutant: satır kilidi kalkarsa eşzamanlı çağrılar aynı
numarayı alıyor.

---

## 13. Kapsam dışı

- **Mevcut siparişe sonradan bağ kurma** → ayrı RPC (`talep_siparis_bagi_ekle`).
- Teslim akışı iş mantığı (`gelen_miktar` / `kalan_miktar`) — yalnız numara
  çağrısı değişir.
- `satin_alma_talepleri.siparis_no` ölü kolonunun düşürülmesi.
- `talep_siparise_donustur` eski RPC'sinin kaldırılması (yerinde kalır; yeni
  yol kullanmaz).
- `siparisler.durum` için `check`/enum kısıtı (§11 risk 6).
