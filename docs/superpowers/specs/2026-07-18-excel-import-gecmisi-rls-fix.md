# Excel Import Geçmişi — Beklenmeyen RLS Yazma Engeli — Bulgu ve Düzeltme

## Bulgu

Excel toplu veri yönetimi pilotunun gerçek uçtan uca testinde (18 Temmuz),
`excel_import_gecmisi` tablosuna anon key ile INSERT yapılamadığı
keşfedildi (`42501: new row violates row-level security policy`). Bu,
`teklif_talepleri`/`talep_onay_gecmisi` ile daha önce görülen aynı
kalıp — Supabase'in yeni oluşturulan tablolar için varsayılan güvenlik
davranışı (RLS otomatik açık, politika yok → varsayılan red).

Etki sınırlı: `excelImportGecmisiYaz()` (ortak-excel.js) bu hatayı
`console.error` ile loglayıp sessizce devam edecek şekilde tasarlandı
(tıpkı `talep_onay_gecmisi` yazımındaki gibi) — asıl veri yazması
(`satin_alma_talep_kalemleri`) etkilenmedi, sadece **denetim izi
kaydedilmiyor**.

## Düzeltme

Aşağıdaki SQL, aynı projedeki RLS Faz 1 / RFQ düzeltme şablonuyla birebir
aynı deseni (SELECT/INSERT/UPDATE serbest, DELETE politikasız → varsayılan
red) 2 tabloya uygular, idempotent (`drop policy if exists` önce):

```sql
begin;

alter table excel_import_gecmisi enable row level security;
drop policy if exists "allow_select" on excel_import_gecmisi;
drop policy if exists "allow_insert" on excel_import_gecmisi;
drop policy if exists "allow_update" on excel_import_gecmisi;
create policy "allow_select" on excel_import_gecmisi for select using (true);
create policy "allow_insert" on excel_import_gecmisi for insert with check (true);
create policy "allow_update" on excel_import_gecmisi for update using (true) with check (true);

alter table excel_import_satirlari enable row level security;
drop policy if exists "allow_select" on excel_import_satirlari;
drop policy if exists "allow_insert" on excel_import_satirlari;
drop policy if exists "allow_update" on excel_import_satirlari;
create policy "allow_select" on excel_import_satirlari for select using (true);
create policy "allow_insert" on excel_import_satirlari for insert with check (true);
create policy "allow_update" on excel_import_satirlari for update using (true) with check (true);

commit;
```

## Doğrulama

SQL çalıştırıldıktan sonra:
```bash
curl -s "https://xwytofysmgqtqjzkplfi.supabase.co/rest/v1/excel_import_gecmisi" \
  -X POST -H "apikey: <SB_KEY>" -H "Authorization: Bearer <SB_KEY>" \
  -H "Content-Type: application/json" -d '{"tablo_adi":"test","dosya_adi":"rls-check"}'
```
Expected: `201 Created` (ya da en azından `42501` DEĞİL) — sonra bu test
satırını elle sil.
