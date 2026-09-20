# Güvenlik bulgusu — `authenticated` rolünde TRUNCATE hakkı (A1 dışı, yüksek öncelikli)

**Tarih:** 2026-09-20 · **Durum:** AÇIK, ayrı iş (`task_7fcfaa3c`) · **Üretimde hiçbir deneme
yapılmadı.** Aşağıdaki "gerçekten çalışıyor" ölçümü **izole kopyada** yapıldı; üretimde yalnız
salt okuma öngörülüyor.

## Özet

`TRUNCATE`, satır düzeyi güvenliği (RLS) **dinlemez**. Üretim şemasında çok sayıda tablo
`authenticated` rolüne `GRANT ALL` vermiş; bu da TRUNCATE'i kapsıyor. Sonuç: **RLS ile korunduğu
varsayılan tablolar, TRUNCATE hakkı duran bir rol için tek komutla boşaltılabilir durumda.**

İki soru ayrı ayrı yanıtlanmalı ve karıştırılmamalı:

| Boyut | Durum |
|---|---|
| **(A) Veritabanı yetkisi** | **VAR ve etkili** — izole kopyada RLS açık bir tabloda TRUNCATE komutu kabul edildi |
| **(B) Bugünkü API yüzeyinden ulaşılabilirlik** | **YOK** — PostgREST'te TRUNCATE yolu yok, roller doğrudan bağlanamıyor, dinamik SQL çalıştıran açık RPC yok |

(B)'nin "yok" olması bulguyu kapatmaz: yetki durdukça, ileride eklenecek bir RPC, bir uzantı ya da
rolün başka bir yoldan üstlenilmesi riski gerçekleştirir. Savunma katmanı **yetkinin kendisi**
olmalıdır.

## Ölçümler (izole ortam — üretim şema dökümünden kurulmuş kopya)

`scripts/truncate-yetki.test.mjs`:

| Ölçüm | Sonuç |
|---|---|
| A1 `authenticated` için TRUNCATE hakkı olan tablo | **80** |
| A2 bunların RLS'i **açık** olanları | **68** |
| A3 RLS açık bir tabloda TRUNCATE denemesi (izole) | **komut kabul edildi — RLS durdurmadı** |
| A5 aynı tabloda DELETE (karşılaştırma) | RLS'e tabi (politika yoksa reddedilir) |
| B1 `anon` / `authenticated` rolleri LOGIN | **kapalı** — hak yalnız API geçidiyle üstlenilir |
| B2 API üzerinden TRUNCATE | **HTTP 405** — PostgREST böyle bir metot tanımıyor |
| B3 genel SQL çalıştırma RPC ucu | **yok (404)** |
| (bilgi) dışa açık ve gövdesinde `EXECUTE` geçen fonksiyon | **0** |
| C2 A1 (15c) sonrası sayım tablolarında hak | **kaldırıldı** |
| C3 geriye kalan tablolarda hak | **75 tabloda duruyor** — A1 kapsamı dışı |

Şema dökümünden bağımsız sayım: `GRANT ALL ON TABLE public.* TO authenticated` satırı **77**
tabloda geçiyor (`2026-09-13-post-faz2-sema-dokumu.sql`).

## Canlı doğrulama — salt okuma (üretimde TRUNCATE denenmez)

`docs/kurulum/2026-09-20-truncate-yetki-kontrol.sql` hazır. Yalnız ölçer; hiçbir DDL/DML yoktur,
işlem `read only` ve sonda `rollback`. Bölümleri:

- (A1) rol bazında TRUNCATE hakkı olan tablo sayısı
- (A2) tablolar + RLS durumu + politika sayısı + yaklaşık satır sayısı (önem sırası için)
- (A3) DELETE hakkı olup izin veren DELETE politikası olmayanlar
- (A4) şema/sekans haklarında `GRANT ALL` süpürgesinin başka ne bıraktığı
- (B1) rollerin LOGIN bayrağı
- (B2) dışa açık ve dinamik SQL çalıştıran fonksiyonlar
- (B3) TRUNCATE üzerindeki koruyucu event trigger / tetikleyiciler

Çalıştırma:

```bash
cd C:\Users\USER\Projects\gurok-bar-a1; .\docs\kurulum\sql-uygula.ps1 -Dosya docs\kurulum\2026-09-20-truncate-yetki-kontrol.sql -SaltOkuma
```

## A1 ile ilişkisi

A1 paketi bu hakkı **yalnızca iki sayım tablosunda** geri alıyor (bölüm 15c), çünkü o iki tabloya
zaten dokunuyor ve politika eklemek tek başına yetmezdi. **Kalan 75 tablo A1'in kapsamı dışında**
ve bu raporun konusu. A1'in geri alma dosyası da TRUNCATE hakkını **geri vermez**: bu, A1'in
getirdiği bir kısıt değil, ayrı bir güvenlik düzeltmesidir.

## Önerilen iş (ayrı oturum — `task_7fcfaa3c`)

1. Canlı salt okuma denetimini çalıştır, tablo listesini önem sırasına koy (RLS açık + satır sayısı).
2. Tablo tablo karar: `authenticated` gerçekten hangi tabloda INSERT/UPDATE/DELETE istiyor?
   `GRANT ALL` yerine açık haklar yazılmalı.
3. `REVOKE TRUNCATE` (ve gereksizse DELETE/REFERENCES/TRIGGER) migration'ı + geri alma + izole test;
   özellikle silme yapan ekranların bozulmadığı kanıtlanmalı.
4. Denetleyiciden (`scripts/migration-guvenlik-kontrol.mjs`) temiz geçiş.
