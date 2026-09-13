# Auth Yedeği — Tasarım

**Tarih:** 2026-09-13 · **Durum:** onaylandı (kullanıcı, 2026-09-13)

## Neden

PMS Faz 2 yayınında ölçüldü (runbook §8, yayın planı §1.8): elle alınan yedek
yalnız `public` + `phase0_private` **verisidir**. `auth` şeması kapsam
dışıdır, bu yüzden proje tümden kaybı senaryosunda iş verisi geri gelir ama
**kimse giriş yapamaz**. E-5 provası bu boşluğu sayıyla raporluyor: 13 kimlik
gerekiyor, yedekten 0 geliyor; prova kimlikleri kendisi üretiyor.

Bu tasarım o boşluğu kapatır ve kapandığını **ölçülebilir** hâle getirir.

## Ölçülen başlangıç durumu (2026-09-13, salt okuma)

`auth` şemasında 23 tablo var; `postgres` rolü **23'ünü de** okuyabiliyor.
Dolu olanlar:

| Tablo | Satır |
|---|---|
| `mfa_amr_claims` | 143 |
| `refresh_tokens` | 143 |
| `sessions` | 143 |
| `schema_migrations` | 77 |
| `identities` | 13 |
| `users` | 13 |

ERP tarafında 13 kullanıcının 13'ünün de `auth_user_id` karşılığı var
(12'si aktif).

## Kapsam kararı

Yedek **tüm `auth` şemasını** kapsar (kullanıcı kararı). Bunun bedeli kayda
geçer: dosya 143 canlı oturum ve yenileme token'ı taşır; sızması hâlinde
parola hash'i kırmaya gerek kalmadan oturum ele geçirilebilir. Daha dar bir
kapsam (`users` + `identities`) kurtarma amacını da karşılardı ve önerilmişti;
tüm şema bilinçli olarak seçildi.

Bu yüzden saklama kuralı dar tutulur: **yalnız en yeni auth yedeği durur.**

## Üretilen dosyalar

`yedek-ve-sayac-al.ps1` tek parola istemiyle, **veri yedeğiyle aynı
snapshot'tan** iki dosya daha üretir:

| Dosya | İçerik | Sır taşır mı |
|---|---|---|
| `<etiket>-auth-yedegi.sql` | `--schema=auth --data-only --no-owner` | **Evet** — parola hash'i, e-posta, oturum ve yenileme token'ları |
| `<etiket>-auth-sema.sql` | `--schema=auth --schema-only --no-owner --no-privileges` | Hayır — yalnız tablo yapısı |

Şema dosyası **prova içindir**: izole kopyanın gerçek auth tablolarını
kurabilmesi için gerekir. Gerçek kurtarmada hedef Supabase projesinin `auth`
şeması platform tarafından sağlandığı için bu dosya kullanılmaz.
`--no-privileges` bilinçlidir: `supabase_auth_admin` gibi platform rolleri
izole kopyada yoktur ve GRANT satırları hataya düşerdi.

Yol (A) snapshot başarısız olursa yol (B) doğrulanmış yazma duraklatmasında
da aynı iki dosya üretilir.

## Saklama ve işleme kuralları

- Dosyalar repo dışındaki kısıtlı klasöre yazılır (bugünkü `ERP-Yedek`;
  kalıtım kaldırılmış, yalnız kullanıcı ve SYSTEM).
- **Yeni yedek alındığında önceki `*-auth-yedegi.sql` ve `*-auth-sema.sql`
  silinir.** Veri yedekleri ve sayaçlar birikmeye devam eder; onlar sır
  taşımaz.
- `.gitignore`'a `docs/kurulum/*-auth-*.sql` eklenir — dosya yanlışlıkla repo
  klasörüne üretilse bile commit edilemez.
- Betik, üretilen auth dosyasının ne taşıdığını çıktısında **açıkça** yazar.
  Dosya içeriği hiçbir yere basılmaz, konuşmaya kopyalanmaz.
- Kapsam dışı: yedeğin şifrelenmesi ve token rotasyonu. Şifreleme istenirse
  ayrı bir karardır; bu tasarım dosyayı olduğu gibi saklar.

## Provaya eklenen yedinci aşama

Mevcut altı aşama (geri yükleme, auth kapsamı, FK bütünlüğü, satır sayıları,
veri tutarlılığı, uygulama erişimi) **aynen korunur**; auth yedeği verildiğinde
sonlarına bir aşama eklenir.

Sıra önemlidir: izole kopyadaki `auth` şeması bugün **bizim iskelemizdir**
(`auth.uid()` `request.jwt.claim.sub` okur). Gerçek auth şeması onun üstüne
yüklenirse kimlik sözleşmesi değişir ve ilk altı aşamanın kanıtı geçersizleşir.
Bu yüzden:

1. Altı aşama biter.
2. İskele kenara alınır: `alter schema auth rename to auth_iskele;` ardından
   `create schema auth;`
3. `<etiket>-auth-sema.sql` ve `<etiket>-auth-yedegi.sql` yüklenir.
4. Ölçüm yapılır:
   - `kullanicilar.auth_user_id` dolu satır sayısı (beklenen: 13),
   - bunların yedekten gelen `auth.users` satırlarıyla **eşleşen** sayısı,
   - eşleşmeyen sayısı — **kapanma ölçütü: 0**.
5. Süre ayrı raporlanır.

Auth yedeği verilmediğinde aşama atlanır ve çıktı bugünkü "auth kapsam dışı"
uyarısını verir. Verildiğinde uyarı yerine "kimlikler kapsamda: N/N" satırı
yazılır.

## Hata ve kenar durumlar

| Durum | Davranış |
|---|---|
| Auth yedeği verilmedi | Yedinci aşama atlanır; bugünkü kapsam uyarısı yazılır; çıkış kodu etkilenmez |
| Auth şema dosyası verilmedi ama veri dosyası verildi | Aşama **başarısız** sayılır: yapı olmadan veri yüklenemez; eksik dosya adı raporlanır |
| Auth şema dosyası yüklenirken hata | Hata sayısı raporlanır ve aşama başarısız olur |
| `auth.users` satırı eksik (eşleşmeyen > 0) | Aşama başarısız; eşleşmeyen sayısı ve örnek kullanıcı adları (kimlik değil, ERP adı) raporlanır |
| Eski auth dosyası silinemedi (kilitli dosya) | Betik uyarır ve devam eder; yeni dosya yine de üretilir |

## Yayın

Bu iş üretim veritabanına hiçbir şey yazmaz; migration yoktur. Değişen
dosyalar yerel betikler ve dokümanlardır. Yeni auth yedeği **kullanıcı
tarafından** alınır (parola yalnız onda) ve prova o dosyayla koşulur.
Hazırlık kilidi (`scripts/hazirlik-kilidi.mjs`) yenilenir, çünkü kilitli iki
dosya değişir: `yedek-ve-sayac-al.ps1` ve `pms-yedek-geri-yukleme-provasi.mjs`.
