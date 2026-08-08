# Stok Tablo (Grid) Görünümü — Uygulama Planı

> **Ajan işçiler için:** GEREKLİ ALT-SKILL: superpowers:executing-plans. Adımlar checkbox (`- [ ]`).

**Hedef:** Stok-takip'e Kart/Tablo geçişli, sütunlu tablo görünümü + sipariş/talep/son-hareket sütunları + sütun sıralama/filtre; mevcut kart görünümü ve özellikler bozulmadan.

**Mimari:** 3 agregat view (security_invoker, RLS otel-scope) → istemcide 3 ürün-bazlı map. `renderStok()` içinde `stokGorunum` state'ine göre kart veya tablo render. Filtre state ortak (`aktifStokFiltreleri` + genişletilmiş `STOK_FILTRE_ALANLARI`).

**Teknoloji:** Statik HTML/JS + Supabase. Test çerçevesi YOK → SQL Editor + uygulamada elle.

## Global Constraints
- SQL dosya olarak verilir, kullanıcı çalıştırır. Client push→GitHub Pages.
- Mevcut kart görünümü + kritik/ABC/kategori sekmeleri + stok işlemleri BOZULMAZ.
- View'lar `security_invoker=true` → RLS otel-scope otomatik (siparisler/talepler/hareketler parent RLS'i).
- filtre.js CANLI; `aktifStokFiltreleri` + `STOK_FILTRE_ALANLARI` mevcut (bu plan genişletir).
- Commit yazarı: `git -c user.name="mehmetaraz0" -c user.email="mehmetaraz868@gmail.com"`.

---

### Task 1: SQL — 3 agregat view

**Files:** Create `docs/kurulum/2026-08-04-stok-tablo-viewlar.sql`

**Interfaces:** Produces view'lar:
- `stok_acik_siparis(otel_id, urun_kodu, bekleyen_miktar)`
- `stok_acik_talep(otel_id, urun_kodu, talep_miktar)`
- `stok_son_hareket(otel_id, depo_kodu, urun_kodu, son_tarih)`

- [ ] **Adım 1: SQL yaz**
```sql
begin;

-- Açık siparişlerde ürün bazlı gelmemiş (kalan) miktar
create or replace view public.stok_acik_siparis with (security_invoker=true) as
  select s.otel_id, sk.urun_kodu, sum(sk.kalan_miktar) as bekleyen_miktar
  from public.siparis_kalemleri sk
  join public.siparisler s on s.siparis_no = sk.siparis_no
  where s.durum not in ('tamamlandi','iptal') and sk.kalan_miktar > 0
  group by s.otel_id, sk.urun_kodu;

-- Siparişe dönüşmemiş taleplerde ürün bazlı miktar (siparis_no is null = henüz siparişe dönmemiş)
create or replace view public.stok_acik_talep with (security_invoker=true) as
  select t.otel_id, tk.urun_kodu, sum(tk.miktar) as talep_miktar
  from public.satin_alma_talep_kalemleri tk
  join public.satin_alma_talepleri t on t.id = tk.talep_id
  where t.siparis_no is null and t.durum::text not in ('reddedildi','iptal','tamamlandi')
  group by t.otel_id, tk.urun_kodu;

-- Ürün+depo bazlı son hareket tarihi
create or replace view public.stok_son_hareket with (security_invoker=true) as
  select otel_id, depo_kodu, urun_kodu, max(tarih) as son_tarih
  from public.stok_hareketleri
  group by otel_id, depo_kodu, urun_kodu;

grant select on public.stok_acik_siparis, public.stok_acik_talep, public.stok_son_hareket to authenticated;

commit;
notify pgrst, 'reload schema';
```

- [ ] **Adım 2: Kullanıcı çalıştırır + doğrular**
```sql
select count(*) from public.stok_acik_siparis;
select count(*) from public.stok_acik_talep;
select count(*) from public.stok_son_hareket;
```
Hata olmamalı (SQL Editor'de auth.uid null → security_invoker RLS'siz = tüm veri; sayı dönmesi yeter).

- [ ] **Adım 3: Commit**
```bash
git add docs/kurulum/2026-08-04-stok-tablo-viewlar.sql
git commit -m "feat(stok): tablo gorunumu icin 3 agregat view (acik siparis/talep/son hareket)"
```

---

### Task 2: Stok-takip — Kart/Tablo toggle + map yükleme + tablo render + sütun sıralama/filtre

**Files:** Modify `stok-takip.html`

**Interfaces:**
- Consumes: `Filtre.*`, `db.stok[aktifDepoId]`, `getStokDurum`, `db.abcSiniflari`, `db.minimumlar`,
  `aktifDepoId`, `otelFromDepoId` (otel-config.js), `SB_URL`, `SB_HEADERS`, `openDetay`, `renderStok`,
  `aktifStokFiltreleri`, `STOK_FILTRE_ALANLARI` (mevcut).
- Produces: `stokGorunum`, `siparisMap/talepMap/sonHareketMap`, `stokEkVeriYukle()`, `renderStokTablo(rows)`,
  `stokTabloSirala(key)`, `stokSutunFiltre(key)`.

- [ ] **Adım 1: Toggle butonu HTML** — "🔎 Gelişmiş Filtre" butonunun yanına ekle:
```html
      <button onclick="stokGorunumDegistir()" id="stok-gorunum-btn" style="margin-top:6px;margin-left:6px;background:#fff;border:1.5px solid var(--gray-300);border-radius:8px;padding:8px 12px;font-size:12px;font-weight:700;cursor:pointer">📊 Tablo Görünümü</button>
```

- [ ] **Adım 2: State + kolon config + STOK_FILTRE_ALANLARI genişlet** — `let aktifStokFiltreleri=[];` satırının altına:
```javascript
let stokGorunum='kart';
let siparisMap={}, talepMap={}, sonHareketMap={};
let stokTabloSir={key:null,yon:1};
// Hesaplanan alanları filtreye de ekle (sütun filtresi için)
STOK_FILTRE_ALANLARI.push(
  { field:'siparis', label:'Sipariş (bekleyen)', type:'number', getValue:s=>siparisMap[s.lnKod]||0 },
  { field:'talep', label:'Talep (bekleyen)', type:'number', getValue:s=>talepMap[s.lnKod]||0 },
  { field:'sonHareket', label:'Son Hareket', type:'date', getValue:s=>sonHareketMap[s.lnKod]||null },
);
const STOK_TABLO_KOLONLARI=[
  {key:'lnKod',label:'Kalem Kodu',type:'text',get:s=>s.lnKod||''},
  {key:'urunAd',label:'Kalem Adı',type:'text',get:s=>s.urunAd||''},
  {key:'miktar',label:'Miktar',type:'number',get:s=>s.miktar||0},
  {key:'birim',label:'Birim',type:'text',get:s=>s.birim||''},
  {key:'min',label:'Min',type:'number',get:s=>db.minimumlar[s.lnKod]||0},
  {key:'kategori',label:'Kategori',type:'text',get:s=>(s.lnKod||'').slice(0,5)},
  {key:'abc',label:'ABC',type:'text',get:s=>db.abcSiniflari[s.lnKod]||'C'},
  {key:'durum',label:'Durum',type:'text',get:s=>getStokDurum(s.lnKod,s.miktar)},
  {key:'siparis',label:'Sipariş',type:'number',get:s=>siparisMap[s.lnKod]||0},
  {key:'talep',label:'Talep',type:'number',get:s=>talepMap[s.lnKod]||0},
  {key:'sonHareket',label:'Son Hareket',type:'date',get:s=>sonHareketMap[s.lnKod]||''},
];
```

- [ ] **Adım 3: Ek veri (3 map) yükleme** — script'e ekle; init'te ve depo değişince çağrılır:
```javascript
async function stokEkVeriYukle(){
  const otel = (typeof otelFromDepoId==='function') ? otelFromDepoId(aktifDepoId) : null;
  siparisMap={}; talepMap={}; sonHareketMap={};
  try{
    const [rs,rt,rh]=await Promise.all([
      fetch(SB_URL+'/rest/v1/stok_acik_siparis?select=otel_id,urun_kodu,bekleyen_miktar',{headers:SB_HEADERS}),
      fetch(SB_URL+'/rest/v1/stok_acik_talep?select=otel_id,urun_kodu,talep_miktar',{headers:SB_HEADERS}),
      fetch(SB_URL+'/rest/v1/stok_son_hareket?select=depo_kodu,urun_kodu,son_tarih',{headers:SB_HEADERS}),
    ]);
    if(rs.ok)(await rs.json()).forEach(r=>{ if(!otel||String(r.otel_id)===String(otel)) siparisMap[r.urun_kodu]=(siparisMap[r.urun_kodu]||0)+(parseFloat(r.bekleyen_miktar)||0); });
    if(rt.ok)(await rt.json()).forEach(r=>{ if(!otel||String(r.otel_id)===String(otel)) talepMap[r.urun_kodu]=(talepMap[r.urun_kodu]||0)+(parseFloat(r.talep_miktar)||0); });
    if(rh.ok)(await rh.json()).forEach(r=>{ if(!sonHareketMap[r.urun_kodu] || r.son_tarih>sonHareketMap[r.urun_kodu]) sonHareketMap[r.urun_kodu]=r.son_tarih; });
  }catch(e){ console.warn('stokEkVeriYukle',e); }
}
```
(NOT — execution'da doğrula: stok_son_hareket.depo_kodu formatı aktifDepoId ile eşleşiyor mu; eşleşmiyorsa depo filtresi eklenir. Şimdilik ürün bazlı en son tarih tüm depolardan alınır — kabul edilebilir.)

- [ ] **Adım 4: Görünüm değiştir + tablo render** — script'e ekle:
```javascript
function stokGorunumDegistir(){
  stokGorunum = stokGorunum==='kart' ? 'tablo' : 'kart';
  const b=document.getElementById('stok-gorunum-btn'); if(b) b.textContent = stokGorunum==='kart' ? '📊 Tablo Görünümü' : '🗂️ Kart Görünümü';
  renderStok();
}
function _hucreBicim(type,v){ if(v==null||v==='')return '—'; if(type==='date'){const d=new Date(v);return isNaN(d)?'—':d.toLocaleDateString('tr-TR');} if(type==='number')return (Math.round((parseFloat(v)||0)*100)/100).toLocaleString('tr-TR'); return String(v); }
function renderStokTablo(rows){
  const c=document.getElementById('stok-liste');
  if(!rows.length){ c.innerHTML='<div class="empty-state"><div class="empty-icon">📦</div><div class="empty-text">Sonuç bulunamadı</div></div>'; return; }
  if(stokTabloSir.key){ const kol=STOK_TABLO_KOLONLARI.find(k=>k.key===stokTabloSir.key);
    rows=rows.slice().sort((a,b)=>{ let x=kol.get(a),y=kol.get(b);
      if(kol.type==='number'){x=parseFloat(x)||0;y=parseFloat(y)||0;return (x-y)*stokTabloSir.yon;}
      if(kol.type==='date'){x=x?new Date(x).getTime():0;y=y?new Date(y).getTime():0;return (x-y)*stokTabloSir.yon;}
      return String(x).localeCompare(String(y),'tr')*stokTabloSir.yon; });
  }
  const bas=STOK_TABLO_KOLONLARI.map(k=>{
    const ok = stokTabloSir.key===k.key ? (stokTabloSir.yon>0?' ▲':' ▼') : '';
    return `<th style="position:sticky;top:0;background:var(--primary);color:#fff;padding:6px 8px;font-size:11px;white-space:nowrap;cursor:pointer" onclick="stokTabloSirala('${k.key}')">${escapeHtml(k.label)}${ok} <span onclick="event.stopPropagation();stokSutunFiltre('${k.key}')" style="cursor:pointer">🔽</span></th>`;
  }).join('');
  const satirlar=rows.map(s=>`<tr onclick="openDetay('${aktifDepoId}','${s.lnKod}')" style="cursor:pointer">`+
    STOK_TABLO_KOLONLARI.map(k=>`<td style="padding:6px 8px;border-top:1px solid var(--gray-200);font-size:11.5px;white-space:nowrap">${escapeHtml(_hucreBicim(k.type,k.get(s)))}</td>`).join('')+`</tr>`).join('');
  c.innerHTML=`<div style="overflow-x:auto"><table style="width:100%;border-collapse:collapse"><thead><tr>${bas}</tr></thead><tbody>${satirlar}</tbody></table></div>`;
}
function stokTabloSirala(key){ if(stokTabloSir.key===key) stokTabloSir.yon*=-1; else stokTabloSir={key,yon:1}; renderStok(); }
function stokSutunFiltre(key){
  const alan=STOK_FILTRE_ALANLARI.find(a=>a.field===key); if(!alan)return;
  const p=document.getElementById('stok-filtre-panel');
  if(p){ p.style.display='block'; Filtre.panelOlustur(p, STOK_FILTRE_ALANLARI, aktifStokFiltreleri, ()=>{ stokFiltreYenidenCiz(); renderStok(); });
    const sel=p.querySelector('.f-alan'); if(sel){ sel.value=key; sel.dispatchEvent(new Event('change')); } }
}
```

- [ ] **Adım 5: renderStok'u tablo-farkında yap** — `renderStok` içinde, `filtered = Filtre.filtreleUygula(...)` + `filtered.sort(...)` sonrasında, kart `container.innerHTML=filtered.map(...)` bloğundan ÖNCE:
```javascript
  if(stokGorunum==='tablo'){ renderStokTablo(filtered); return; }
```
(Bu satır, stats/etiket render'ından SONRA, kart listesi üretiminden ÖNCE olmalı — kartlar üretilmez, tablo basılır.)

- [ ] **Adım 6: init'te ek veri yükle** — `currentUser = requireLogin();` sonrası init akışında (loadDB'den sonra) `await stokEkVeriYukle();` ekle; depo değiştiren fonksiyona da `stokEkVeriYukle().then(renderStok)` ekle.

- [ ] **Adım 7: Uygulamada elle test** (Ctrl+Shift+R)
- "📊 Tablo Görünümü" → tablo; başlığa tıkla → sıralama (▲/▼); "🗂️ Kart Görünümü" → geri kart.
- Sipariş/Talep/Son Hareket sütunları bilinen bir üründe doğru (SQL'le karşılaştır).
- Başlık 🔽 → gelişmiş filtre paneli o sütunla açılır; filtre uygulanınca hem tablo hem kart aynı.
- Mevcut arama/sekmeler/işlemler bozulmadan çalışır.

- [ ] **Adım 8: Commit + push**
```bash
git add stok-takip.html
git commit -m "feat(stok): kart/tablo gorunum toggle + siparis/talep/son-hareket sutunlari + sutun sirala/filtre"
git push origin main
```

---

### Task 3: Uçtan uca doğrulama
- [ ] Toggle + kart regresyon; sütun sıralama (3 tip); sütun filtre = panel; otel izolasyonu (view security_invoker); boş veri (hareketsiz ürün → Son Hareket "—"). Memory'ye işle.

---

## Self-Review
- Spec kapsamı: toggle (Adım1,4), 3 view (Task1), map yükleme (Adım3), tablo+sütunlar (Adım4), sıralama (stokTabloSirala), sütun filtre (stokSutunFiltre→panel), son-hareket (view3+kolon) — hepsi var. Raf/konum + sunucu-sayfalama bilerek kapsam dışı.
- Placeholder yok: SQL + JS somut. DİKKAT (execution): siparisler.durum açık-değer seti ('tamamlandi'/'iptal' hariç) canlı doğrula; talep_durum terminal etiketleri (::text karşılaştırma güvenli); stok_son_hareket.depo_kodu formatı aktifDepoId ile eşleşiyor mu; renderStok'ta tablo-return satırının tam yeri (stats sonrası, kart map öncesi); escapeHtml/openDetay/otelFromDepoId varlığı.
- Tip tutarlılığı: STOK_TABLO_KOLONLARI.key ↔ STOK_FILTRE_ALANLARI.field (siparis/talep/sonHareket) aynı; map adları (siparisMap/talepMap/sonHareketMap) her yerde aynı.
