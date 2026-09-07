# Migration güvenlik standardı

**Kapsam:** PMS Faz 2 ve sonrasındaki **her** migration.
**Yürürlük:** 2026-09-08 ve sonrası tarihli dosyalar.
**Zorunlu:** evet. Denetleyici kırmızıysa migration üretime gitmez.

| | |
|---|---|
| Şablon | [`SABLON-yeni-migration.sql`](SABLON-yeni-migration.sql) |
| Denetleyici | `node scripts/migration-guvenlik-kontrol.mjs` |
| Sabotaj testleri | `node --test scripts/migration-guvenlik-kontrol.test.mjs` |
| ACL uyarı kontrolü | [`2026-09-07-varsayilan-acl-uyari-kontrolu.sql`](2026-09-07-varsayilan-acl-uyari-kontrolu.sql) |

---

## 0. Temel ilke

**"RLS var, grant önemli değil" yaklaşımı bu projede geçersizdir.**

İzin (`GRANT`) ve politika (`POLICY`) iki ayrı katmandır ve farklı şeylere
karşı korur:

| | GRANT | RLS politikası |
|---|---|---|
| Kimi durdurur | ayrıcalığı olmayan rolü | ayrıcalığı olan rolü, satır bazında |
| `service_role`'ü etkiler mi | **evet** | **hayır** — RLS'i baypas eder |
| Yanlışsa belirtisi | hata | **sessiz 0 satır** |

Üçüncü satır kritiktir: RLS bir engeli **hata olarak değil, boş sonuç olarak**
gösterir. "Yetkim yok" ile "veri yok" istemciden ayırt edilemez. Bu yüzden
ayrıcalık katmanı, RLS'in doğru olduğuna güvenerek gevşetilemez.

Finansal append-only tablolarda bir de üçüncü katman gerekir: **tetikleyici.**
`service_role` RLS'i baypas ettiği için, politika ve ayrıcalık doğru olsa bile
`service_role` ile açılan bir bağlantı geçmişi değiştirebilir.

---

## 1. Zorunlu ACL kalıbı

Her yeni nesne için sıra **değişmez**: önce hepsini al, sonra asgariyi ver.

```sql
REVOKE ALL ON TABLE public.<tablo> FROM PUBLIC;
REVOKE ALL ON TABLE public.<tablo> FROM anon;
REVOKE ALL ON TABLE public.<tablo> FROM authenticated;
```

ya da tek satırda (denetleyici ikisini de kabul eder):

```sql
REVOKE ALL ON TABLE public.<tablo> FROM PUBLIC, anon, authenticated;
```

### `authenticated` neden listede

`public`/`postgres` varsayılan ayrıcalıkları yeni tabloya `authenticated` için
**ALL** verir. Yalnız `PUBLIC, anon` revoke etmek, append-only bir tablonun
UPDATE/DELETE yasağını **sessizce** etkisiz bırakır: tablo "korunuyor" görünür,
ayrıcalık açıktır.

Bu ders 2026-09-06'da ödendi. Ayrıntı:
[`2026-09-07-varsayilan-acl-bulgusu.md`](2026-09-07-varsayilan-acl-bulgusu.md).

---

## 2. Nesne sınıfları

### Normal CRUD tablosu

```sql
REVOKE ALL ON TABLE public.x FROM PUBLIC, anon, authenticated;
GRANT SELECT, INSERT, UPDATE ON public.x TO authenticated;
-- DELETE yalnızca gerçekten gerekiyorsa; gerekiyorsa ayrıca yaz.
GRANT ALL ON public.x TO service_role;
```

`GRANT ALL ... TO authenticated` **yasaktır**. `ALL`, bugün var olmayan
ayrıcalıkları da kapsar: gelecekte eklenecek bir ayrıcalık türü sessizce
açılır. Hakları tek tek yazmak, kararın ne zaman verildiğini de kayda geçirir.

### Append-only finansal tablo

```sql
-- @append-only: x
REVOKE ALL ON TABLE public.x FROM PUBLIC, anon, authenticated;
GRANT SELECT, INSERT ON public.x TO authenticated;
GRANT ALL ON public.x TO service_role;
```

Üç katman birden gerekir:

1. **Ayrıcalık yok** — `UPDATE`/`DELETE` hiç verilmez.
2. **Politika yok** — `for update` / `for delete` politikası **oluşturulmaz**.
   Politikasız işlem RLS altında 0 satır eder.
3. **Tetikleyici var** — `before update or delete` bekçisi. Bu katman
   `service_role` içindir; ilk ikisini o baypas eder.

```sql
CREATE TRIGGER x_degismez BEFORE UPDATE OR DELETE ON public.x
  FOR EACH ROW EXECUTE FUNCTION public.x_degismez();
```

Düzeltme yolu **ters kayıt**tır, satır değiştirmek değil.

### Salt-okuma görünüm

```sql
CREATE OR REPLACE VIEW public.x_ozet
WITH (security_invoker = true) AS ...;

REVOKE ALL ON public.x_ozet FROM PUBLIC, anon;
GRANT SELECT ON public.x_ozet TO authenticated, service_role;
```

`security_invoker = true` **zorunludur**. Varsayılan yanlış taraftadır: onsuz
görünüm sahibinin haklarıyla çalışır ve alttaki tabloların RLS'ini tamamen
atlatır — otel izolasyonu dâhil.

### Sekans

```sql
REVOKE ALL ON SEQUENCE public.x_seq FROM PUBLIC, anon, authenticated;
GRANT USAGE ON SEQUENCE public.x_seq TO authenticated;
GRANT ALL   ON SEQUENCE public.x_seq TO service_role;
```

`USAGE`, `ALL` değil. `ALL`, `setval` ile sekansı geri sarmaya izin verir;
belge numaraları çakışır ve `unique` kısıt üretimde patlar.

### Fonksiyon

```sql
REVOKE ALL ON FUNCTION public.x(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.x(uuid) TO authenticated, service_role;
```

PostgreSQL yeni fonksiyona `PUBLIC` için EXECUTE verir — bu, dilin
varsayılanıdır ve unutulması kolaydır. Her **çağrılabilir** fonksiyon için
açıkça geri alınır.

**Tetikleyici fonksiyonları (`returns trigger`) istisnadır**: doğrudan
çağrılamazlar (`can only be called as a trigger`), ACL kararı gerekmez.
Denetleyici bunları ayırt eder.

### SECURITY DEFINER

```sql
CREATE OR REPLACE FUNCTION public.x(...)
RETURNS ... LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp AS $$
```

`SET search_path` **zorunludur**. Pinlenmemiş arama yolu, gövdedeki her
çağrıyı saldırganın şemasına yönlendirebilir — fonksiyon sahibinin
yetkisiyle.

Ayrıca `SECURITY DEFINER`, RLS'i çağıranın üstünden alır. Kontrolü geri
koymak gövdenin işidir:

```sql
if not (public.auth_yetki_var('modul','kayit') is true) then
  raise exception 'Yetki yok' using errcode = '42501';
end if;
```

`is true` gereklidir. `if not auth_yetki_var(...)` yazımı NULL karşısında
fail-open davranır; `is true` yalnız açık TRUE'yu geçirir.

İstemciden gelen `otel_id`'ye **güvenilmez**. İlgili satırın kendi `otel_id`
değeri okunur ve `auth_otel_erisim()` ona uygulanır.

---

## 3. Statik denetleyici

```bash
node scripts/migration-guvenlik-kontrol.mjs
```

Argümansız çalıştırma **yalnız 2026-09-08 ve sonrası** tarihli
`docs/kurulum/*.sql` dosyalarına bakar. Veritabanına bağlanmaz.

```bash
node scripts/migration-guvenlik-kontrol.mjs docs/kurulum/<dosya>.sql   # tek dosya
node scripts/migration-guvenlik-kontrol.mjs --tumu                     # tarihi dosyalar dahil (rapor)
node scripts/migration-guvenlik-kontrol.mjs --uyari-da-hata            # UYARI da bloke etsin
```

### Kurallar

| Kod | Seviye | Ne yakalar |
|---|---|---|
| `R1-TABLO-REVOKE-YOK` | HATA | Tablo oluşturuluyor, hiçbir REVOKE onu kapsamıyor |
| `R2-REVOKE-EKSIK-ROL` | HATA | REVOKE var ama PUBLIC / anon / authenticated'dan biri eksik |
| `R3-GRANT-KARARI-YOK` | UYARI | `authenticated` için açık GRANT yok (kasıtlıysa `@erisim-yok`) |
| `R4-AUTHENTICATED-ALL` | HATA | `GRANT ALL ... TO authenticated` |
| `R4-SEKANS-ALL` | HATA | Sekansta `authenticated` ALL alıyor |
| `R5-ACIK-GRANT` | HATA | `PUBLIC` ya da `anon`'a GRANT bırakılmış |
| `R6-APPEND-ONLY-YAZMA` | HATA | append-only tabloya UPDATE/DELETE ayrıcalığı |
| `R6-APPEND-ONLY-TETIKLEYICI-YOK` | HATA | append-only tabloda bekçi tetikleyici yok |
| `R7-RLS-YOK` | HATA | Tabloda `enable row level security` yok |
| `R8-SEKANS-REVOKE-YOK` / `-EKSIK` | HATA | Sekans ACL bloğu yok ya da eksik rol |
| `R9-DEFINER-PINSIZ` | HATA | `SECURITY DEFINER` ama `set search_path` yok |
| `R9-FONKSIYON-ACL-KARARI-YOK` | UYARI | Çağrılabilir fonksiyon için EXECUTE kararı yok |
| `R9-FONKSIYON-REVOKE-EKSIK` | HATA | EXECUTE, PUBLIC/anon için geri alınmamış |
| `R10-GORUNUM-ACL-KARARI-YOK` | UYARI | Görünüm için ACL kararı yok |
| `R10-GORUNUM-INVOKER-YOK` | HATA | Görünümde `security_invoker = true` yok |

**HATA** çıkış kodunu 1 yapar. **UYARI** yapmaz — `--uyari-da-hata` ile
yaptırılabilir.

### Yönergeler

Denetleyici yorum satırlarındaki üç yönergeyi okur:

```sql
-- @append-only: pms_folio_hareketleri, pms_folio_odemeler
-- @erisim-yok: sadece_servis_tablosu
-- @acl-istisna: nesne_adi -- gerekçe buraya yazılır
```

`@acl-istisna` bir kaçış kapısıdır ve **gerekçesiz kullanılmaz**; kod
incelemesinde gerekçe okunur.

### Yanlış alarm üretmemesi için

Bu repoda ACL ifadelerinin bir kısmı DO döngüsü içinde `execute format(...)`
ve `%I` ile üretilir:

```sql
execute format('revoke all on public.%I from public, anon, authenticated', v_tablo);
```

Düz metin araması bunu **göremez** ve her PMS migration'ını yanlışlıkla
kırmızı yapardı. Denetleyici bu yüzden DO bloklarını ayrıştırır, döngünün
hangi nesne adları üzerinde döndüğünü çıkarır ve `format` şablonlarını o
adlarla açar. Yorumlar temizlenirken dize ve dolar-tırnak gövdeleri korunur.

**Kalibrasyon kanıtı:** denetleyici PMS Adım 4'te (tam sertleştirilmiş dosya)
sıfır bulgu üretir; Adım 1–2'de altı `R2` ve Adım 3'te bir `R9` bulur — yani
elle bulunmuş bilinen boşlukların **tamamını ve yalnız onları** yeniden
keşfeder.

---

## 4. Sabotaj testleri

```bash
node --test scripts/migration-guvenlik-kontrol.test.mjs
```

Yöntem: sağlam şablonu al, **tek** bir güvenlik özelliğini boz, denetleyicinin
**tam olarak beklenen kural kodunu** bulmasını bekle.

"Kırmızı oldu" yeterli değildir — yanlış sebeple kırmızı olan test hiçbir şey
ölçmez. Her sabotaj önce metni gerçekten değiştirdiğini **sayarak** doğrular
(`boz()` yardımcısı eşleşme sayısını `assert` eder); şablon değişip sabotaj
hedefini bulamazsa test **kurulum hatası** verir, sessizce yeşile dönmez.

| Test | Sabotaj | Beklenen |
|---|---|---|
| — | *(bozulmamış şablon)* | **yeşil**, 0 HATA 0 UYARI |
| A | REVOKE bloğu silindi | `R1` |
| B | `authenticated`'a ALL | `R4` |
| C | `SECURITY DEFINER` search_path pini silindi | `R9-DEFINER-PINSIZ` |
| D | append-only tabloya DELETE grant | `R6-APPEND-ONLY-YAZMA` |
| E | append-only bekçi tetikleyici silindi | `R6-...-TETIKLEYICI-YOK` |
| F | `anon`'a GRANT | `R5` |
| G | `enable row level security` silindi | `R7` |
| H | `security_invoker` silindi | `R10-...-INVOKER-YOK` |
| I | REVOKE'tan `authenticated` düşürüldü | `R2` |
| J | fonksiyon EXECUTE kararı silindi | `R9` (UYARI) + `--uyari-da-hata` ile kırmızı |
| K | sekans REVOKE silindi | `R8` |
| L | argümansız çalıştırma | tarihî dosyalar **kırmızı yapmaz** |

I ve J gerçek olaylardır: I, PMS Adım 1–2'nin yaptığı şeydir; J, Adım 3'teki
`pms_bugun` fonksiyonudur.

---

## 5. Geçmiş migration'lar

**Adım 1–4 dâhil üretime uygulanmış hiçbir migration geriye dönük yeniden
yazılmaz.**

Gerekçe:

1. Dosya SHA256'ları yayın manifestinde sabitlenmiştir
   (`2026-09-07-pms-faz1-yayin-manifesti.md`). Dosyayı değiştirmek, üretimde
   çalışan şeyle repodaki kaydı ayırır.
2. Bu dosyalar artık **tarihsel kanıt**tır: üretimde ne olduğunu gösterirler,
   ne olması gerektiğini değil.
3. Yeniden yazmak hiçbir açığı kapatmaz — üretim çoktan uygulanmış durumdadır.
   Gerçek bir açık bulunursa **yeni** bir düzeltme migration'ı yazılır.

Denetleyicinin taban tarihi (`TABAN_TARIH = '2026-09-08'`) tam olarak bunun
için vardır: tarihî dosyalar varsayılan kapsamda değildir ve CI'ı kırmazlar.
`--tumu` ile raporlanabilirler; bu bir *inceleme* aracıdır, *kapı* değil.

**Bilinen sapmalar (kabul edilmiş, kapatılmayacak):**

| Dosya | Bulgu | Değerlendirme |
|---|---|---|
| Adım 1 (`oda-tipleri-odalar`) | 2 tablo · `R2` — revoke `authenticated` içermiyor | Derinlemesine savunma boşluğu. Tablolar zaten `authenticated`'a CRUD veriyor; açık delik değil. |
| Adım 2 (`misafir-rezervasyon`) | 4 tablo · `R2` — aynı | Aynı |
| Adım 3 (`checkin-checkout`) | `pms_bugun` · `R9` (UYARI) — EXECUTE kararı yok | Tarih döndüren yardımcı; `anon` çağırsa bile veri sızdırmaz. |
| Adım 4 (`folio`) | **yok** | Standarda tam uyumlu |

---

## 6. Yayın öncesi zincir

Yeni bir migration üretime çıkmadan önce, sırayla:

| # | Adım | Komut / dosya |
|---|---|---|
| 1 | Şablondan başla | `SABLON-yeni-migration.sql` kopyala |
| 2 | Statik denetim **yeşil** | `node scripts/migration-guvenlik-kontrol.mjs` |
| 3 | Sabotaj testleri **yeşil** | `node --test scripts/migration-guvenlik-kontrol.test.mjs` |
| 4 | Yerel staging'de uygula | `node scripts/yerel-staging.mjs` |
| 5 | Şema eşitliği | `node scripts/dokum-dogrula.mjs <döküm> <eşitlik>` |
| 6 | Üretim parmak izi (salt-okuma) | `2026-09-07-post-pms-faz1-uretim-parmakizi.sql` |
| 7 | **ACL uyarı kontrolü (salt-okuma)** | `2026-09-07-varsayilan-acl-uyari-kontrolu.sql` |
| 8 | Yedek + `CANLIYA UYGULA` onayı | runbook bölüm 1 |

Adım 7 bu standartla eklendi. Karar kriteri **D1/D2**'dir (`public`
şemasında `anon` tablo/sekans hakkı = 0). `B1`/`C1` bilinen platform riskini
izler: büyürlerse yayın durmaz ama **açıklanmadan geçilmez**.

Dosya türü karışıklığı için: **`.sql` → Supabase SQL Editor**,
**`.ps1` → yerel PowerShell**, **`.mjs` → yerel `node`**.

---

## 7. Üretimdeki mevcut ACL durumu nerede ölçülür

Bu standart **dosyaları** denetler. Üretimin fiili durumu ayrı ölçülür:

| Ne | Dosya | Çalıştığı yer |
|---|---|---|
| Şema/politika/fonksiyon parmak izi | `2026-09-07-post-pms-faz1-uretim-parmakizi.sql` | SQL Editor (salt-okuma) |
| Varsayılan ACL + fiili `anon` hakkı | `2026-09-07-varsayilan-acl-uyari-kontrolu.sql` | SQL Editor (salt-okuma) |
| Repo tabanı ↔ üretim eşitliği | `2026-09-07-post-pms-faz1-esitlik-dogrulama.sql` | `dokum-dogrula.mjs` |

İkisi birbirinin yerine geçmez: statik denetleyici **yazdığımızı**, parmak izi
**çalışanı** ölçer. Bir migration'ın doğru yazılmış olması uygulandığının
kanıtı değildir — 2026-09-05'te `supabase_admin` revoke'unun sessizce
başarısız olması tam olarak bu farktır.
