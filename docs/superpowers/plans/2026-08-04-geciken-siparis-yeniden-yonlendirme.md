# Geciken Sipariş Yeniden Yönlendirme — Uygulama Planı

> **Ajan işçiler için:** GEREKLİ ALT-SKILL: Bu planı görev-görev uygulamak için superpowers:executing-plans (bu oturumda). Adımlar checkbox (`- [ ]`) ile takip edilir.

**Hedef:** Termin'i geçmiş ve gelmemiş siparişleri görünür kılıp, tek tıkla eski siparişi iptal edip gelmeyen kalemler için yeni teklif talebi (RFQ) açan bir yeniden-yönlendirme akışı eklemek.

**Mimari:** Yeni atomik RPC `siparis_yeniden_yonlendir` (eski siparişi iptal + kalan kalemlerle yeni RFQ, tek transaction) + `satin-alma-siparistakip.html`'e "Gecikmiş" sekmesi/rozeti + "Yeniden Yönlendir" butonu. Mevcut RFQ→teklif→sipariş makinesi tekrar kullanılır.

**Teknoloji:** Statik HTML/JS + Supabase (Postgres/PostgREST). Test çerçevesi YOK → doğrulama SQL Editor'de + uygulamada elle. Deploy: main → GitHub Pages.

## Global Constraints
- SQL dosya olarak verilir, kullanıcı Supabase SQL Editor'de çalıştırır (biz çalıştırmayız).
- Client değişikliği `main`'e commit+push → GitHub Pages otomatik yayınlar.
- RPC `security definer` + `auth_yetki_var('siparis_olustur','kayit')` + `auth_otel_erisim` (mevcut desen).
- `siparisler.durum` = text ('iptal' geçerli). `siparis_kalemleri`: urun_kodu/urun_adi/birim/kalan_miktar mevcut.
- teklif_talepleri.otel_id = text; teklif_kalemleri = (teklif_talebi_id, urun_kodu, urun_adi, miktar, birim).
- Commit yazarı: `git -c user.name="mehmetaraz0" -c user.email="mehmetaraz868@gmail.com"`.

---

### Task 1: SQL RPC — `siparis_yeniden_yonlendir`

**Files:**
- Create: `docs/kurulum/2026-08-04-siparis-yeniden-yonlendir-rpc.sql`

**Interfaces:**
- Produces: `siparis_yeniden_yonlendir(p_siparis_no text, p_olusturan text) returns uuid`
  (yeni teklif_talebi id döner). İstemci `{p_siparis_no, p_olusturan:CU.ad}` gönderir.

- [ ] **Adım 1: SQL dosyasını yaz**

```sql
-- 2026-08-04 — Geciken sipariş yeniden yönlendirme (atomik RPC)
-- Eski siparişi 'iptal' yapar + kalan_miktar>0 kalemlerle yeni teklif talebi açar. TEK transaction.
begin;

create or replace function public.siparis_yeniden_yonlendir(p_siparis_no text, p_olusturan text)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_otel public.otel_id;
  v_durum text;
  v_talep_id uuid;
  v_kalan_sayi int;
  v_kalem record;
begin
  if not public.auth_yetki_var('siparis_olustur','kayit') then
    raise exception 'Yetki yok: sipariş yeniden yönlendirme için siparis_olustur kayıt yetkisi gerekli';
  end if;

  select otel_id, durum into v_otel, v_durum
  from public.siparisler where siparis_no = p_siparis_no;
  if not found then
    raise exception 'Sipariş bulunamadı: %', p_siparis_no;
  end if;
  if not public.auth_otel_erisim(v_otel::text) then
    raise exception 'Yetki yok: bu siparişin oteline erişiminiz yok';
  end if;
  if v_durum in ('iptal','tamamlandi') then
    raise exception 'Bu sipariş yeniden yönlendirilemez (durum: %)', v_durum;
  end if;

  select count(*) into v_kalan_sayi
  from public.siparis_kalemleri
  where siparis_no = p_siparis_no and kalan_miktar > 0;
  if v_kalan_sayi = 0 then
    raise exception 'Gelmeyen (kalan) kalem yok — yeniden yönlendirmeye gerek yok';
  end if;

  update public.siparisler
    set durum = 'iptal',
        not_alani = coalesce(not_alani || ' | ', '') ||
          'Gecikme nedeniyle iptal + yeniden yönlendirildi (' || to_char(now(),'YYYY-MM-DD') || ')',
        son_guncelleme = now()
  where siparis_no = p_siparis_no;

  insert into public.teklif_talepleri (olusturan, otel_id, durum)
  values (p_olusturan, v_otel::text, 'acik')
  returning id into v_talep_id;

  for v_kalem in
    select urun_kodu, urun_adi, birim, kalan_miktar
    from public.siparis_kalemleri
    where siparis_no = p_siparis_no and kalan_miktar > 0
  loop
    insert into public.teklif_kalemleri (teklif_talebi_id, urun_kodu, urun_adi, miktar, birim)
    values (v_talep_id, v_kalem.urun_kodu, v_kalem.urun_adi, v_kalem.kalan_miktar, v_kalem.birim);
  end loop;

  return v_talep_id;
end;
$$;

revoke all on function public.siparis_yeniden_yonlendir(text, text) from public;
grant execute on function public.siparis_yeniden_yonlendir(text, text) to authenticated;

commit;
notify pgrst, 'reload schema';
```

- [ ] **Adım 2: Kullanıcı SQL Editor'de çalıştırır**

Beklenen: hata yok, "Success". Doğrulama sorgusu:
```sql
select proname, prosecdef from pg_proc where proname = 'siparis_yeniden_yonlendir';
```
Beklenen: 1 satır, `prosecdef = true`.

- [ ] **Adım 3: Commit (SQL dosyası)**

```bash
git add docs/kurulum/2026-08-04-siparis-yeniden-yonlendir-rpc.sql
git commit -m "feat(satinalma): siparis_yeniden_yonlendir atomik RPC (iptal + kalan kalemlerle yeni RFQ)"
```

---

### Task 2: UI — Gecikmiş sekmesi + rozet + sayım

**Files:**
- Modify: `satin-alma-siparistakip.html` (tab HTML ~satır 57-61; `renderSiparisTakip` ~117-140; kart render ~159-195)

**Interfaces:**
- Consumes: `_siparisHavuzuData` (her sipariş: `.durum`, `.termin` (YYYY-MM-DD veya ''), `.siparisNo`, `.kalemler`).
- Produces: `siparisGecikti(s)` yardımcı fonksiyonu (bool); `_stFilter==='gecikmis'` filtre dalı.

- [ ] **Adım 1: Gecikme yardımcı fonksiyonunu ekle** (script içinde, `filterSiparisTakip`'ten önce)

```javascript
// Termin geçmiş + hâlâ tam gelmemiş (bekleyen/kismi) = gecikmiş
function siparisGecikti(s){
  if(!s || !s.termin) return false;
  if(!['bekleyen','kismi'].includes(s.durum)) return false;
  const bugun=new Date(); bugun.setHours(0,0,0,0);
  const t=new Date(s.termin+'T00:00:00');
  return t < bugun;
}
```

- [ ] **Adım 2: "Gecikmiş" sekme butonunu ekle** (~satır 58-61 sekmelerin arasına, "Bekleyen"den sonra)

```html
      <button class="ftab" id="st-tab-gecikmis" onclick="filterSiparisTakip('gecikmis',this)">⏰ Gecikmiş</button>
```

- [ ] **Adım 3: Filtre dalını ekle** (`renderSiparisTakip` içinde, `if(_stFilter!=='tumu')...` satırını değiştir — satır 138-139)

Eski:
```javascript
  let liste=tumSiparisler;
  if(_stFilter!=='tumu')liste=tumSiparisler.filter(s=>s.durum===_stFilter);
```
Yeni:
```javascript
  let liste=tumSiparisler;
  if(_stFilter==='gecikmis') liste=tumSiparisler.filter(siparisGecikti);
  else if(_stFilter!=='tumu') liste=tumSiparisler.filter(s=>s.durum===_stFilter);
```

- [ ] **Adım 4: Gecikmiş sayacını stats'a ekle** (`renderSiparisTakip` stats bloğu ~satır 121-136; `const tam=...` satırından sonra ekle + yeni stat kutusu)

`const tam=...` satırından hemen sonra:
```javascript
  const gec=tumSiparisler.filter(siparisGecikti).length;
```
Stats innerHTML'inde "TAMAM" kutusundan sonra (kapanış backtick'ten önce) yeni kutu:
```javascript
    <div style="background:white;border-radius:8px;padding:10px;text-align:center;box-shadow:0 1px 4px rgba(0,0,0,.08)">
      <div style="font-size:18px;font-weight:800;color:var(--danger)">${gec}</div>
      <div style="font-size:10px;color:var(--gray-500)">GECİKMİŞ</div>
    </div>
```

- [ ] **Adım 5: Kartta "gecikti" rozeti** (kart render'da durumChip'in yanına; `${durumChip[s.durum]||''}` satırını değiştir)

Eski: `${durumChip[s.durum]||''}`
Yeni:
```javascript
        <div style="text-align:right">
          ${durumChip[s.durum]||''}
          ${siparisGecikti(s)?`<div style="margin-top:4px"><span style="background:#fde8e8;color:#9b1c1c;padding:2px 8px;border-radius:10px;font-size:10px;font-weight:700">⏰ ${Math.ceil((Date.now()-new Date(s.termin+'T00:00:00'))/86400000)} gün gecikti</span></div>`:''}
        </div>
```

- [ ] **Adım 6: Uygulamada elle test**

GitHub Pages ~2 dk sonra, Ctrl+Shift+R:
- Termin'i **geçmiş** bekleyen bir sipariş → "⏰ Gecikmiş" sekmesinde görünmeli + kartta "X gün gecikti" rozeti.
- Termin'i **gelecekte** olan → sekmede görünmemeli.
- Tamamlanmış → gecikmiş sayılmamalı.
- Stats'ta "GECİKMİŞ" sayısı doğru.

- [ ] **Adım 7: Commit**

```bash
git add satin-alma-siparistakip.html
git commit -m "feat(satinalma): siparis takip gecikmis sekmesi + gecikti rozeti"
git push origin main
```

---

### Task 3: UI — "Yeniden Yönlendir" butonu + RPC entegrasyonu

**Files:**
- Modify: `satin-alma-siparistakip.html` (kart render — buton; yeni `siparisYenidenYonlendir` fonksiyonu)

**Interfaces:**
- Consumes: Task 1 RPC `siparis_yeniden_yonlendir(p_siparis_no, p_olusturan)`; `SB_URL`, `SB_HEADERS`, `CU.ad`, `toast`, `sLD/hLD`.

- [ ] **Adım 1: Kartın altına "Yeniden Yönlendir" butonu** (kart HTML'inde, "Bekleyen kalemler" bloğundan sonra, kart div'i kapanmadan). Buton sadece `bekleyen`/`kismi` siparişlerde ve `event.stopPropagation` ile (kart onclick detay açıyor):

```javascript
      ${['bekleyen','kismi'].includes(s.durum)?`
        <button onclick="event.stopPropagation();siparisYenidenYonlendir('${s.siparisNo}')"
          style="margin-top:8px;width:100%;padding:9px;border:1.5px solid var(--danger);background:#fff5f5;color:var(--danger);border-radius:8px;font-size:12px;font-weight:700;cursor:pointer">
          🔄 Yeniden Yönlendir (iptal + yeni teklif)
        </button>`:''}
```

- [ ] **Adım 2: `siparisYenidenYonlendir` fonksiyonunu ekle** (script içinde)

```javascript
async function siparisYenidenYonlendir(siparisNo){
  const s=_siparisHavuzuData[siparisNo];
  if(!s){toast('Sipariş bulunamadı');return;}
  const kalan=(s.kalemler||[]).filter(k=>k.kalanMiktar>0.001);
  if(!kalan.length){toast('Gelmeyen kalem yok');return;}
  if(!confirm(`"${siparisNo}" siparişi İPTAL edilecek ve gelmeyen ${kalan.length} kalem için YENİ teklif talebi açılacak.\n\nDevam edilsin mi?`))return;
  sLD();
  try{
    const r=await fetch(SB_URL+'/rest/v1/rpc/siparis_yeniden_yonlendir',{method:'POST',headers:SB_HEADERS,
      body:JSON.stringify({p_siparis_no:siparisNo,p_olusturan:CU.ad})});
    if(!r.ok){const t=await r.text().catch(()=>'');console.error('siparis_yeniden_yonlendir',t);hLD();toast('❌ Yönlendirilemedi: '+t.slice(0,120));return;}
    hLD();
    toast('✅ Sipariş iptal edildi, yeni teklif talebi açıldı');
    setTimeout(()=>{location.href='satin-alma-teklif-toplama.html';},900);
  }catch(e){hLD();console.warn(e);toast('❌ Bağlantı hatası');}
}
```

- [ ] **Adım 3: Uygulamada elle test (uçtan uca çekirdek)**

Ctrl+Shift+R:
- Gecikmiş (veya bekleyen) bir siparişte "🔄 Yeniden Yönlendir" → onay → onayla.
- Beklenen: toast "iptal edildi, yeni teklif açıldı" → Teklif Toplama ekranına gider, orada yeni RFQ (kalan kalemlerle) görünür.
- Eski sipariş: Sipariş Takip'te durumu "❌ İptal" olmalı (gecikmiş sekmesinden düşer).

- [ ] **Adım 4: Commit**

```bash
git add satin-alma-siparistakip.html
git commit -m "feat(satinalma): Yeniden Yonlendir butonu + siparis_yeniden_yonlendir RPC cagrisi"
git push origin main
```

---

### Task 4: Uçtan uca doğrulama (spec test planı)

**Files:** (yok — sadece test)

- [ ] **Adım 1: Kısmi teslimat senaryosu**
Kısmen gelmiş (kismi) bir siparişi yeniden yönlendir → yeni RFQ'da SADECE kalan (gelmeyen) miktar olmalı; gelen kısım etkilenmemeli. Doğrula (SQL):
```sql
select tt.id, tk.urun_adi, tk.miktar from teklif_talepleri tt
join teklif_kalemleri tk on tk.teklif_talebi_id=tt.id
order by tt.olusturma_tarihi desc limit 10;
```
Miktarların kalan_miktar ile eşleştiğini gör.

- [ ] **Adım 2: Rollback (atomiklik)**
Zaten 'iptal'/'tamamlandi' bir siparişi yönlendirmeyi dene → "yeniden yönlendirilemez" hatası, hiçbir şey değişmemeli (yeni RFQ oluşmamalı).

- [ ] **Adım 3: Otel izolasyonu**
(Faz 4 deseniyle, istenirse) tek-otel kullanıcı başka otelin siparişini yönlendirmeyi deneyince "Yetki yok" almalı.

- [ ] **Adım 4: Kapanış**
Üç senaryo da geçince özellik tamam. Memory'ye işle.

---

## Self-Review Notları
- Spec kapsamı: gecikmiş tespiti (Task 2), atomik iptal+RFQ (Task 1+3), kısmi=kalan (RPC kalan_miktar>0), iptal-not-sil (durum='iptal'), test planı (Task 4) — hepsi karşılanıyor.
- Placeholder yok: tüm SQL + JS kodu somut.
- Tip tutarlılığı: RPC imzası `(text,text)` istemci `{p_siparis_no,p_olusturan}` ile eşleşiyor; `siparisGecikti` hem filtre hem sayaç hem rozette aynı.
- DİKKAT (execution'da doğrula): `_siparisHavuzuData` kart render'ında sipariş nesnesinin `.termin`/`.kalemler[].kalanMiktar` alan adları (load ~satır 80-90: termin, kalanMiktar). Execution'da bu alan adlarını teyit et.
