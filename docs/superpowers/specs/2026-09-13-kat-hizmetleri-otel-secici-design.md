# Kat Hizmetleri Otel Seçici — Tasarım

**Tarih:** 2026-09-13 · **Durum:** onaylandı (kullanıcı, 2026-09-13)

## Neden

PMS Faz 2 yayınında (runbook §8) ölçülen bulgu: kat hizmetleri ekranı otel
kapsamını `kullanicilar.otel_id` alanından alır ve otel seçicisi yoktur.
`tum_oteller = true` ama `otel_id` boş olan kullanıcı ekranı **hiç
kullanamaz** — "Otel seçili değil" uyarısıyla karşılaşır ve hiçbir komut
düğmesi görmez. Veritabanı tarafındaki `hk_calisan_uygun` "tüm oteller"
yetkisini kabul ettiği için bu yalnızca bir arayüz kısıtıdır.

Yayın gününde üretimde bu durumdaki kullanıcı sayısı: **7** (otel atamalı 4,
otelsiz 1). Testleri yürütebilmek için iki kullanıcıya elle `otel_id`
verilmişti; bu kalıcı bir çözüm değildir.

## Kapsam

Kat hizmetleri ekranına (`pms-housekeeping.html`) otel seçici eklenir.
Seçici **yalnız çapraz otel yetkisi olan kullanıcıda** görünür; otel atamalı
kullanıcının davranışı değişmez.

Kapsam dışı:

- Ortak/paylaşılan otel seçici bileşeni — diğer ekranlar kendi desenlerini
  kullanır, onlara dokunulmaz.
- `#oda=` derin bağlantısının oda filtresine dönüşmesi.
- `kullanicilar_genel` görünümüne `tum_oteller` eklenmesi (migration yok).
- Oda planının (`pms-oda-plani.html`) "tüm oteller" davranışı.

## Mimari

Oteller `otel-config.js` içinde sabittir (`810` Club, `811` Resort); veri
tabanında otel listesi okuyan bir ekran yoktur ve bu tasarım da okumaz.

Kat hizmetleri RPC'lerinin tamamı (`pms_housekeeping_listele`,
`pms_housekeeping_odalar`, `pms_housekeeping_gorev_olustur`) `p_otel`
parametresi ister. Bu yüzden ekran her zaman **tek bir otele** kilitlidir;
oda planındaki gibi "hepsini göster" seçeneği burada anlamlı değildir.

### Çapraz otel hakkı sunucudan okunur

Ön yüz `tum_oteller` alanını göremez (`kullanicilar_genel` görünümünde yok).
Bunun yerine ekran açılışta `public.auth_tum_oteller()` RPC'sini çağırır:

- `authenticated` rolünde EXECUTE yetkisi **vardır** (şema dökümüyle
  doğrulandı), yani ek bir DDL gerekmez.
- Çağrı hata verirse sonuç **`false`** sayılır. Yetki okumasındaki
  fail-closed deseninin aynısıdır: belirsizlikte ekran bugünkü davranışına
  düşer, fazladan yetenek açılmaz.

### Karar tablosu

| `CU.otelId` | `auth_tum_oteller()` | Ekranın davranışı |
|---|---|---|
| dolu | (sorulmaz) | Bugünkü sabit otel rozeti; seçici **yok** |
| boş | `true` | Otel seçici; hatırlanan seçim, yoksa `810` |
| boş | `false` | Bugünkü "Otel seçili değil" uyarısı; **değişiklik yok** |

### Seçimin saklanması

Anahtar: `hk-otel:<kullanici_id>` (localStorage). Değer `810` veya `811`.
Başka bir değer okunursa yok sayılır ve `810` kullanılır. Seçim sunucuya
yazılmaz; hiçbir kullanıcı kaydı değişmez.

### Otel değişince ne olur

Sıra önemlidir, çünkü ekranda üç ayrı otel-kapsamlı durum vardır:

1. Yoklama (`POLL`) durdurulur.
2. Görev listesi, çalışan haritası ve oda seçici listesi **temizlenir**.
3. Seçim saklanır ve başlıktaki rozet güncellenir.
4. Yeni otelle `calisanlariYukle()` ve `tazele()` çalışır.
5. Yoklama yeniden başlatılır.

Uçuşta bir komut varken (`UCUSTA` doğruyken) seçici **kilitlidir**. Yarım
kalan bir komutun yanıtı, kullanıcı otel değiştirdikten sonra dönerse yanlış
kapsamda ekrana yazılmamalıdır.

### Derin bağlantı

`pms-oda-plani.html` içindeki `katHizmetleriAc()` bağlantıya odanın otelini
de ekler: `#otel=<otel_id>&oda=<oda_no>`. Kat hizmetleri ekranı `otel`
parametresini **yalnız seçim hakkı olan kullanıcıda** dikkate alır ve
hatırlanan seçimin yerine geçirir. Otel atamalı kullanıcıda parametre yok
sayılır — kullanıcı kendi oteline kilitli kalır.

`oda` parametresi bugün olduğu gibi kullanılmaz.

## Hata ve kenar durumlar

| Durum | Davranış |
|---|---|
| `auth_tum_oteller()` hata verir / ağ yok | `false` sayılır; otel atamasız kullanıcı bugünkü uyarıyı görür |
| localStorage okunamaz (özel pencere, kapalı depolama) | Hatırlama yok sayılır; `810` ile açılır, ekran çalışır |
| Saklanan değer geçersiz (`812`, boş, bozuk) | Yok sayılır; `810` |
| `#otel=` geçersiz bir değer taşır | Yok sayılır; hatırlanan seçim geçerli kalır |
| Seçilen otelde görev yok | Boş kuyruk gösterilir; başlıktaki otel rozeti hangi otele bakıldığını söyler |
| Komut uçuştayken seçici denenirse | Seçici kilitli; değişiklik uygulanmaz |

## Test

Yerel izole kopyada (ağsız konteyner, mevcut staging betikleri), iki otel ve
iki kullanıcı ile:

1. Otel atamalı kullanıcı → seçici **yok**, ekran bugünkü gibi çalışır.
2. `tum_oteller` kullanıcı → seçici **var**, `810` ile açılır.
3. Otel değiştir → kuyruk ve oda seçici yeni otelin verisiyle gelir,
   eskisinden satır sızmaz.
4. Sayfayı yeniden aç → son seçilen otel hatırlanır.
5. `auth_tum_oteller()` hata verecek şekilde kısıtlanırsa → ekran bugünkü
   "Otel seçili değil" uyarısına düşer.
6. `#otel=811` ile açılış → seçim 811 olur; otel atamalı kullanıcıda yok
   sayılır.
7. `node scripts/check.mjs` yeşil.

## Yayın

Migration yok, yetki değişikliği yok, kesinti yok. Değişen dosyalar:
`pms-housekeeping.html` ve `pms-oda-plani.html` (bir satır).

Yayın, ayrı bir **`CANLIYA UYGULA`** onayıyla `main`'e push edilerek yapılır
(GitHub Pages). Geri dönüş: `git revert` + push; veritabanında iz bırakmadığı
için başka bir geri alma adımı yoktur.
