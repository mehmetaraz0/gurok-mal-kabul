# RFQ + Onay Geçmişi — Beklenmeyen RLS Yazma Engeli — Bulgu ve Düzeltme

## Bulgu

Gerçek uçtan uca test sırasında (17 Temmuz), `teklif_talepleri` ve
`talep_onay_gecmisi` tablolarına anon key ile INSERT yapılamadığı
keşfedildi (`42501: new row violates row-level security policy`).
SELECT çalışıyor, INSERT/UPDATE engelleniyor.

**Bu, paralel oturumun "RLS Faz 1" işiyle ilgisi yok** — doğruladım:
`cariler` tablosunda DELETE hâlâ serbest (HTTP 204), yani faz1 SQL'i
henüz çalıştırılmamış, sadece tasarım/plan dokümanı olarak duruyor. Ayrıca
faz1'in kapsamı zaten sadece 11 belirli tabloyu hedefliyor (`cariler`,
`faturalar`, `demirbaslar`, `cek_senetler`, `banka_kasa_hesaplari`,
`butce_kayitlari`, `kullanicilar`, `stok`, `stok_hareketleri`,
`cari_hareketler`, `banka_kasa_hareketleri`) — `teklif_talepleri`/
`talep_onay_gecmisi` bu listede hiç yok.

Kaynağı belirsiz — muhtemelen Supabase'in yeni oluşturulan tablolar için
varsayılan bir güvenlik davranışı (RLS otomatik açık, politika yok →
varsayılan red). Etki: **RFQ özelliği şu an tamamen kullanılamaz**
(yeni teklif talebi oluşturulamıyor), onay akışının **aşama geçmişi**
(denetim izi) sessizce kaydedilmiyor (onay işleminin kendisi çalışıyor).

## Düzeltme

Aşağıdaki SQL, paralel oturumun RLS Faz 1 şablonuyla birebir aynı deseni
(SELECT/INSERT/UPDATE serbest, DELETE politikasız → varsayılan red)
4 tabloya uygular:

```sql
begin;

alter table teklif_talepleri enable row level security;
create policy "allow_select" on teklif_talepleri for select using (true);
create policy "allow_insert" on teklif_talepleri for insert with check (true);
create policy "allow_update" on teklif_talepleri for update using (true) with check (true);

alter table teklif_talep_kalemleri enable row level security;
create policy "allow_select" on teklif_talep_kalemleri for select using (true);
create policy "allow_insert" on teklif_talep_kalemleri for insert with check (true);
create policy "allow_update" on teklif_talep_kalemleri for update using (true) with check (true);

alter table tedarikci_teklifler enable row level security;
create policy "allow_select" on tedarikci_teklifler for select using (true);
create policy "allow_insert" on tedarikci_teklifler for insert with check (true);
create policy "allow_update" on tedarikci_teklifler for update using (true) with check (true);

alter table tedarikci_teklif_kalemleri enable row level security;
create policy "allow_select" on tedarikci_teklif_kalemleri for select using (true);
create policy "allow_insert" on tedarikci_teklif_kalemleri for insert with check (true);
create policy "allow_update" on tedarikci_teklif_kalemleri for update using (true) with check (true);

alter table talep_onay_gecmisi enable row level security;
create policy "allow_select" on talep_onay_gecmisi for select using (true);
create policy "allow_insert" on talep_onay_gecmisi for insert with check (true);
create policy "allow_update" on talep_onay_gecmisi for update using (true) with check (true);

commit;
```

Not: `alter table ... enable row level security` zaten etkinse hata
vermez (Postgres bunu idempotent olarak kabul eder), yani tablo zaten
RLS'liyse bu satır zararsızca no-op olur — sadece politikalar eksikse
onları ekler.

## Doğrulama

SQL çalıştırıldıktan sonra:
```bash
curl -s "https://xwytofysmgqtqjzkplfi.supabase.co/rest/v1/teklif_talepleri" \
  -X POST -H "apikey: <SB_KEY>" -H "Authorization: Bearer <SB_KEY>" \
  -H "Content-Type: application/json" -d '{"otel_id":"810","olusturan_ad":"test"}'
```
Expected: `201 Created` (ya da en azından `42501` DEĞİL) — sonra bu test
satırını elle sil.
