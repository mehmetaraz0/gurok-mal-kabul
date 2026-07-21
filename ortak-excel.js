// ortak-excel.js — Gürok ERP paylaşılan Excel toplu veri yönetimi motoru.
// <head> içinde ortak.js'den SONRA, senkron olarak yüklenir
// (<script src="ortak-excel.js"></script>) — loadXlsxLib()'e (ortak.js)
// ve SB_URL/SB_HEADERS'a (supabase-config.js) bağımlı.
//
// Tablo-agnostik: her fonksiyon bir "spec" dizisiyle çalışır —
// {alan, baslik, tip, zorunlu, kilitli, gizli, genislik, izinliDegerler}.
// alan: satır nesnesindeki anahtar (örn. 'urun_kodu'). baslik: Excel
// sütun başlığı. tip: 'text'|'number'. zorunlu: boş bırakılamaz.
// kilitli: sistem tarafından üretilir (örn. id) — düzenlenmesi beklenmez,
// sadece görsel olarak işaretlenir (gerçek hücre koruması yok, xlsx-js-style
// sayfa koruması yazmayı desteklemiyor). gizli: dışa aktarımda hiç
// görünmez. izinliDegerler: varsa başlığa "(izin verilenler: ...)" olarak
// eklenir — gerçek Excel açılır-liste (native data validation) burada
// KULLANILAN xlsx-js-style kütüphanesinde desteklenmiyor, bu bilinçli bir
// sınırlama; yerine başlıkta metin ipucu kullanılıyor.

// ============================================================
// 1) DIŞA AKTARMA
// ============================================================

function _excelGorunurAlanlar(spec){
  return spec.filter(s=>!s.gizli);
}

function _excelBaslikMetni(s){
  return s.baslik + (s.izinliDegerler&&s.izinliDegerler.length ? ' (izin verilenler: '+s.izinliDegerler.join(', ')+')' : '');
}

// Görünür sütunlara stil uygular: kilitli -> gri dolgu, zorunlu -> sarı
// başlık dolgusu, diğerleri -> mevcut mal-kabul-v2.html buildMkFormuXlsx
// desenindeki açık mavi başlık dolgusu.
function excelSutunStilUygula(ws, spec, satirSayisi){
  const gorunur = _excelGorunurAlanlar(spec);
  const hdrKilitli = {font:{bold:true,sz:10,name:'Arial'},fill:{fgColor:{rgb:'D9D9D9'},patternType:'solid'},alignment:{horizontal:'center',vertical:'center',wrapText:true},border:{top:{style:'thin'},bottom:{style:'thin'},left:{style:'thin'},right:{style:'thin'}}};
  const hdrZorunlu = {font:{bold:true,sz:10,name:'Arial'},fill:{fgColor:{rgb:'FFF3CD'},patternType:'solid'},alignment:{horizontal:'center',vertical:'center',wrapText:true},border:{top:{style:'thin'},bottom:{style:'thin'},left:{style:'thin'},right:{style:'thin'}}};
  const hdrNormal = {font:{bold:true,sz:10,name:'Arial'},fill:{fgColor:{rgb:'DDEBF7'},patternType:'solid'},alignment:{horizontal:'center',vertical:'center',wrapText:true},border:{top:{style:'thin'},bottom:{style:'thin'},left:{style:'thin'},right:{style:'thin'}}};
  const dataKilitli = {font:{sz:10,name:'Arial',color:{rgb:'808080'}},fill:{fgColor:{rgb:'F2F2F2'},patternType:'solid'}};

  gorunur.forEach((s,c)=>{
    const hAddr = XLSX.utils.encode_cell({r:0,c});
    if(!ws[hAddr]) ws[hAddr] = {t:'s',v:_excelBaslikMetni(s)};
    ws[hAddr].s = s.kilitli ? hdrKilitli : (s.zorunlu ? hdrZorunlu : hdrNormal);
    if(s.kilitli){
      for(let r=1;r<=satirSayisi;r++){
        const addr = XLSX.utils.encode_cell({r,c});
        if(!ws[addr]) ws[addr] = {t:'z',v:''};
        ws[addr].s = dataKilitli;
      }
    }
  });

  ws['!cols'] = gorunur.map(s=>({wch: s.genislik || (s.baslik.length+4)}));
}

// spec: yukarıdaki şekilde. veriler: satır nesneleri dizisi (alan adları
// spec.alan ile eşleşir). dosyaAdi: örn. 'talep-kalemleri-abcd1234.xlsx'.
async function excelSablonIndir(spec, veriler, dosyaAdi){
  await loadXlsxLib();
  const gorunur = _excelGorunurAlanlar(spec);
  const basliklar = gorunur.map(_excelBaslikMetni);
  const satirlar = (veriler||[]).map(v => gorunur.map(s => {
    const val = v[s.alan];
    if(val===undefined||val===null) return '';
    // Formül enjeksiyonu koruması: '=', '+', '-', '@' ile başlayan string bir
    // hücre Excel'de formül olarak çalışır (örn. ürün adı '=cmd|...' ise).
    // Başına tek tırnak ekleyerek düz metne zorluyoruz (Excel'in kendi kaçış kuralı).
    if(typeof val==='string' && /^[=+\-@]/.test(val)) return "'"+val;
    return val;
  }));
  const ws = XLSX.utils.aoa_to_sheet([basliklar, ...satirlar]);
  excelSutunStilUygula(ws, spec, satirlar.length);
  const wb = XLSX.utils.book_new();
  XLSX.utils.book_append_sheet(wb, ws, 'Veri');
  XLSX.writeFile(wb, dosyaAdi);
}

// ============================================================
// 2) İÇE AKTARMA — OKUMA + SINIFLANDIRMA
// ============================================================

// Ham satırları (dizi-dizi, header:1) döner — spec'in görünür sütun
// SIRASINA göre pozisyonel okunur (bu modülün kendi excelSablonIndir'i
// hep aynı sırayla yazdığı için kolon-eşleştirme gerekmiyor; keyfi/
// yabancı dosya desteği Faz 2 kapsamında, bkz. design doc).
async function excelDosyaOku(file){
  await loadXlsxLib();
  return new Promise((resolve, reject) => {
    const reader = new FileReader();
    reader.onload = e => {
      try{
        const wb = XLSX.read(e.target.result, {type:'array', raw:false});
        const ws = wb.Sheets[wb.SheetNames[0]];
        resolve(XLSX.utils.sheet_to_json(ws, {header:1, raw:false}));
      }catch(err){ reject(err); }
    };
    reader.onerror = () => reject(reader.error);
    reader.readAsArrayBuffer(file);
  });
}

// Bir kayıt/satır nesnesinden doğal anahtar string'i üretir. İki mod:
// - opts.dogalAnahtarKombinasyonu (alan adları dizisi) verilmişse: TÜM
//   alanların değerleri BİRLEŞTİRİLİP tek bileşik anahtar olur (örn.
//   tarih+para_birimi, yil+otel_id+hesap_kodu) — hiçbiri "öncelik sırası"
//   değil, hepsi anahtarın parçası.
// - Verilmemişse opts.dogalAnahtarlar (öncelik sıralı liste, ilk dolu
//   alan kazanır — tek alanlı doğal anahtarlar için, pilotun kullandığı
//   mod) kullanılır. İkisi de yoksa null döner (doğal anahtar yok demek).
function _excelDogalAnahtarUret(nesne, opts){
  if (opts.dogalAnahtarKombinasyonu){
    const parcalar = opts.dogalAnahtarKombinasyonu.map(alan => String(nesne[alan] ?? '').trim().toLowerCase());
    if (parcalar.every(p => p === '')) return null;
    return opts.dogalAnahtarKombinasyonu.join('+') + ':' + parcalar.join('|');
  }
  const dogalAnahtarlar = opts.dogalAnahtarlar || ['urun_kodu', 'urun_adi'];
  for (const alan of dogalAnahtarlar){
    if (nesne[alan]) return alan + ':' + String(nesne[alan]).trim().toLowerCase();
  }
  return null;
}

// spec: excelSablonIndir ile aynı. satirlar: excelDosyaOku'nun döndürdüğü
// ham diziler (satirlar[0]=başlık). mevcutKayitlar: sistemdeki güncel
// kayıtlar (id + doğal anahtar alanlarını içeren nesneler dizisi).
// opts: {dogalAnahtarlar:['urun_kodu','urun_adi']} TEK alan (öncelik
// sıralı fallback) VEYA {dogalAnahtarKombinasyonu:['tarih','para_birimi']}
// BİLEŞİK (tüm alanlar birlikte) — ikisi birbirini dışlar, kombinasyon
// verilmişse o kullanılır. Ayrıca {fkAlan:'urun_kodu', fkSet:Set<string>}.
// Döner: {satirNo, alanlar, sinif, hatalar[], eskiDeger, yeniDeger, kayitId}[]
// sinif ∈ 'yeni'|'guncelleme'|'degisiklik_yok'|'hata'|'bulunamadi'|'mukerrer'
function excelSatirlariSiniflandir(spec, satirlar, mevcutKayitlar, opts){
  opts = opts || {};
  const gorunur = _excelGorunurAlanlar(spec);
  const idSpec = spec.find(s => s.kilitli);

  const mevcutById = {};
  const mevcutByDogal = {};
  (mevcutKayitlar || []).forEach(k => {
    if (k.id) mevcutById[String(k.id)] = k;
    const dogalKey = _excelDogalAnahtarUret(k, opts);
    if (dogalKey) mevcutByDogal[dogalKey] = k;
  });

  const gorulenDogalAnahtar = new Set();
  const sonuc = [];
  const dataRows = (satirlar || []).slice(1);

  dataRows.forEach((row, i) => {
    const satirNo = i + 2; // Excel'deki gerçek satır no (1 = başlık)
    if (!row || row.every(c => c===undefined || c===null || String(c).trim()==='')) return;

    const alanlar = {};
    gorunur.forEach((s, c) => {
      let ham = (row[c] !== undefined && row[c] !== null) ? String(row[c]).trim() : '';
      // excelSablonIndir'in formül-enjeksiyon kaçışını geri al (yalnızca bizim
      // eklediğimiz desen: ' + [=+-@] ile başlayan) — round-trip verisi bozulmasın.
      if (/^'[=+\-@]/.test(ham)) ham = ham.slice(1);
      alanlar[s.alan] = ham;
    });

    const hatalar = [];
    gorunur.forEach(s => { if (s.zorunlu && !alanlar[s.alan]) hatalar.push(s.baslik + ' zorunlu, boş bırakılamaz'); });
    gorunur.forEach(s => {
      if (s.tip === 'number' && alanlar[s.alan]) {
        const n = parseFloat(String(alanlar[s.alan]).replace(',', '.'));
        if (isNaN(n)) hatalar.push(s.baslik + ' sayısal olmalı');
        else if (s.pozitifOlmali && n <= 0) hatalar.push(s.baslik + " 0'dan büyük olmalı");
        else if (!s.pozitifOlmali && n < 0) hatalar.push(s.baslik + ' negatif olamaz');
        else alanlar[s.alan] = n;
      }
    });
    if (opts.fkAlan && opts.fkSet && alanlar[opts.fkAlan] && !opts.fkSet.has(alanlar[opts.fkAlan])) {
      hatalar.push(opts.fkAlan + ' sistemde bulunamadı: ' + alanlar[opts.fkAlan]);
    }

    let mevcut = null, sinif;
    const idDeger = idSpec ? alanlar[idSpec.alan] : '';
    if (idDeger) {
      mevcut = mevcutById[idDeger];
      if (!mevcut) { sinif = 'bulunamadi'; hatalar.push('Sistem ID sistemde bulunamadı: ' + idDeger); }
    } else {
      const dogalKey = _excelDogalAnahtarUret(alanlar, opts);
      if (dogalKey) {
        if (gorulenDogalAnahtar.has(dogalKey)) { sinif = 'mukerrer'; hatalar.push('Bu kayıt dosyada birden fazla kez var'); }
        else { gorulenDogalAnahtar.add(dogalKey); mevcut = mevcutByDogal[dogalKey]; }
      }
    }

    if (!sinif) {
      if (hatalar.length) sinif = 'hata';
      else if (mevcut) {
        const degisti = gorunur.some(s => !s.kilitli && String(mevcut[s.alan] ?? '') !== String(alanlar[s.alan] ?? ''));
        sinif = degisti ? 'guncelleme' : 'degisiklik_yok';
      } else sinif = 'yeni';
    }

    sonuc.push({ satirNo, alanlar, sinif, hatalar, eskiDeger: mevcut ? {...mevcut} : null, yeniDeger: alanlar, kayitId: mevcut ? mevcut.id : null });
  });

  return sonuc;
}

// ============================================================
// 3) ÖNİZLEME / DİFF MODALI
// ============================================================
// Repodaki her modal statik HTML (sayfaya gömülü) — bu, bilinçli bir
// sapmayla, ilk kez runtime'da JS'den DOM'a enjekte edilen bir modal.
// Kendi <style>'ını da beraberinde getirir (sayfanın .mo/.mbox gibi
// kendi sınıflarına bağımlı DEĞİL) — böylece herhangi bir sayfaya (sadece
// theme.css yüklüyse, ki paylaşılan dosya kuralı gereği hepsi yüklüyor)
// sorunsuz taşınabilir. Bkz. design doc "bilinçli mimari sapma".

const OE_SINIF_META = {
  yeni:            { renk: '#27ae60', etiket: 'Yeni' },
  guncelleme:      { renk: '#0284c7', etiket: 'Güncelleme' },
  degisiklik_yok:  { renk: '#adb5bd', etiket: 'Değişiklik Yok' },
  hata:            { renk: '#e74c3c', etiket: 'Hata' },
  bulunamadi:      { renk: '#e74c3c', etiket: 'Bulunamadı' },
  mukerrer:        { renk: '#f39c12', etiket: 'Yinelenen' }
};

const OE_MODLAR = [
  { id: 'sadece_guncelle',   etiket: 'Sadece Güncelleme',                    dahil: ['guncelleme'] },
  { id: 'sadece_yeni',       etiket: 'Sadece Yeni Kayıt',                    dahil: ['yeni'] },
  { id: 'guncelle_ve_yeni',  etiket: 'Güncelleme + Yeni Kayıt',              dahil: ['guncelleme', 'yeni'] },
  { id: 'hatali_atla',       etiket: 'Hatalıları Atla, Kalanını Uygula',     dahil: ['guncelleme', 'yeni'], onaySor: true },
  { id: 'hata_varsa_iptal',  etiket: 'Herhangi Bir Hatada Tümünü İptal Et',  dahil: ['guncelleme', 'yeni'], hataVarsaEngelle: true }
];

let _oeSiniflandirma = null;
let _oeSpec = null;
let _oeOnUygula = null;
let _oeDosyaAdiOnek = 'hata-raporu';

function ensureExcelOnizlemeModal(){
  if (document.getElementById('mExcelOnizleme')) return;

  const style = document.createElement('style');
  style.id = 'oeStil';
  style.textContent = `
    #mExcelOnizleme{display:none;position:fixed;inset:0;background:rgba(0,0,0,.5);z-index:5000;align-items:center;justify-content:center;padding:16px}
    #mExcelOnizleme.oe-open{display:flex}
    .oe-box{background:#fff;border-radius:16px;padding:20px;width:100%;max-width:720px;max-height:90vh;overflow-y:auto;box-shadow:0 8px 40px rgba(0,0,0,.25);font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif}
    .oe-title{font-size:16px;font-weight:700;color:var(--primary);margin-bottom:12px;display:flex;align-items:center;gap:8px}
    .oe-close{margin-left:auto;background:none;border:none;font-size:20px;cursor:pointer;color:var(--gray-600)}
    .oe-stats{display:flex;gap:6px;flex-wrap:wrap;margin-bottom:12px}
    .oe-chip{padding:4px 10px;border-radius:14px;font-size:11px;font-weight:600}
    .oe-field{margin-bottom:12px}
    .oe-field label{display:block;font-size:11px;font-weight:600;color:var(--gray-600);margin-bottom:4px;text-transform:uppercase}
    .oe-field select{width:100%;padding:9px 10px;border:1.5px solid var(--gray-300);border-radius:8px;font-size:13px}
    .oe-table-wrap{max-height:38vh;overflow-y:auto;border:1px solid var(--gray-200);border-radius:8px;margin-bottom:14px}
    .oe-table{width:100%;border-collapse:collapse;font-size:12px}
    .oe-actions{display:flex;gap:8px}
    .oe-btn{padding:10px 16px;border:none;border-radius:8px;font-size:13px;font-weight:600;cursor:pointer}
    .oe-btn:disabled{opacity:.5;cursor:not-allowed}
  `;
  document.head.appendChild(style);

  const div = document.createElement('div');
  div.id = 'mExcelOnizleme';
  div.innerHTML = `
    <div class="oe-box">
      <div class="oe-title">📊 Excel Önizleme <button class="oe-close" onclick="_oeKapat()">✕</button></div>
      <div class="oe-stats" id="oe-stats"></div>
      <div class="oe-field">
        <label>Aktarım Modu</label>
        <select id="oe-mod" onchange="_oeModDegisti()"></select>
      </div>
      <div class="oe-table-wrap"><table class="oe-table" id="oe-tablo"></table></div>
      <div class="oe-actions">
        <button class="oe-btn" style="background:var(--gray-200);color:var(--gray-700)" onclick="_oeKapat()">İptal</button>
        <button class="oe-btn" style="background:var(--warning);color:#fff" onclick="_oeHataRaporuIndir()">📥 Hata Raporu İndir</button>
        <button class="oe-btn" id="oe-uygula-btn" style="flex:1;background:var(--primary);color:#fff" onclick="_oeUygulaTikla()">✅ Uygula</button>
      </div>
    </div>`;
  document.body.appendChild(div);
  div.addEventListener('click', e => { if (e.target === div) _oeKapat(); });
}

function _oeKapat(){
  const el = document.getElementById('mExcelOnizleme');
  if (el) el.classList.remove('oe-open');
}

// siniflandirma: excelSatirlariSiniflandir'ın döndürdüğü dizi.
// opts: {spec, onUygula(modId, yazilacakSatirlar), dosyaAdiOnek}
function excelOnizlemeGoster(siniflandirma, opts){
  ensureExcelOnizlemeModal();
  opts = opts || {};
  _oeSiniflandirma = siniflandirma;
  _oeSpec = opts.spec;
  _oeOnUygula = opts.onUygula;
  _oeDosyaAdiOnek = opts.dosyaAdiOnek || 'hata-raporu';

  const sayilar = {};
  Object.keys(OE_SINIF_META).forEach(k => sayilar[k] = 0);
  siniflandirma.forEach(s => sayilar[s.sinif]++);

  document.getElementById('oe-stats').innerHTML = Object.keys(OE_SINIF_META).map(k =>
    `<span class="oe-chip" style="background:${OE_SINIF_META[k].renk}22;color:${OE_SINIF_META[k].renk}">${OE_SINIF_META[k].etiket}: ${sayilar[k]}</span>`
  ).join('');

  document.getElementById('oe-mod').innerHTML = OE_MODLAR.map(m => `<option value="${m.id}">${m.etiket}</option>`).join('');

  document.getElementById('oe-tablo').innerHTML = siniflandirma.map(s => _oeSatirHtml(s, opts.spec)).join('')
    || '<tr><td style="padding:12px;text-align:center;color:var(--gray-500)">Dosyada satır bulunamadı</td></tr>';

  _oeModDegisti();
  document.getElementById('mExcelOnizleme').classList.add('oe-open');
}

function _oeSatirHtml(s, spec){
  const meta = OE_SINIF_META[s.sinif];
  const gorunur = _excelGorunurAlanlar(spec).filter(x => !x.kilitli);
  let detay;
  if (s.sinif === 'guncelleme') {
    const farkli = gorunur.filter(x => String(s.eskiDeger?.[x.alan] ?? '') !== String(s.yeniDeger?.[x.alan] ?? ''));
    detay = farkli.length
      ? farkli.map(x => `<div><b>${escapeHtml(x.baslik)}:</b> <span style="color:var(--gray-500);text-decoration:line-through">${escapeHtml(String(s.eskiDeger?.[x.alan] ?? ''))}</span> → <span style="color:${meta.renk};font-weight:700">${escapeHtml(String(s.yeniDeger?.[x.alan] ?? ''))}</span></div>`).join('')
      : '<div style="color:var(--gray-500)">(fark bulunamadı)</div>';
  } else if (s.sinif === 'degisiklik_yok') {
    detay = '<div style="color:var(--gray-500)">Değişiklik yok</div>';
  } else if (s.sinif === 'yeni') {
    detay = gorunur.map(x => `<div><b>${escapeHtml(x.baslik)}:</b> ${escapeHtml(String(s.yeniDeger?.[x.alan] ?? ''))}</div>`).join('');
  } else {
    detay = s.hatalar.map(h => `<div style="color:var(--danger)">⚠️ ${escapeHtml(h)}</div>`).join('');
  }
  return `<tr style="border-bottom:1px solid var(--gray-200)">
    <td style="padding:6px;font-size:11px;color:var(--gray-500);vertical-align:top">${s.satirNo}</td>
    <td style="padding:6px;vertical-align:top"><span style="display:inline-block;padding:2px 8px;border-radius:10px;font-size:11px;font-weight:600;background:${meta.renk}22;color:${meta.renk}">${meta.etiket}</span></td>
    <td style="padding:6px">${detay}</td>
  </tr>`;
}

function _oeModDegisti(){
  const modId = document.getElementById('oe-mod').value;
  const mod = OE_MODLAR.find(m => m.id === modId);
  const hataSayisi = (_oeSiniflandirma || []).filter(s => s.sinif === 'hata').length;
  document.getElementById('oe-uygula-btn').disabled = !!(mod.hataVarsaEngelle && hataSayisi > 0);
}

function _oeUygulaTikla(){
  const modId = document.getElementById('oe-mod').value;
  const mod = OE_MODLAR.find(m => m.id === modId);
  const hataSayisi = (_oeSiniflandirma || []).filter(s => s.sinif === 'hata').length;
  if (mod.hataVarsaEngelle && hataSayisi > 0) { toast('❌ Dosyada hata var, bu modda hiçbir satır yazılamaz'); return; }
  if (mod.onaySor && hataSayisi > 0 && !confirm(hataSayisi + " satır hata nedeniyle atlanacak, devam edilsin mi?")) return;
  const yazilacaklar = (_oeSiniflandirma || []).filter(s => mod.dahil.includes(s.sinif));
  _oeKapat();
  if (_oeOnUygula) _oeOnUygula(modId, yazilacaklar);
}

function _oeHataRaporuIndir(){
  const hatalilar = (_oeSiniflandirma || []).filter(s => ['hata', 'bulunamadi', 'mukerrer'].includes(s.sinif));
  if (!hatalilar.length) { toast('✅ Hatalı satır yok'); return; }
  excelHataRaporuIndir(_oeSpec, hatalilar, _oeDosyaAdiOnek + '-hatalar-' + new Date().toISOString().split('T')[0] + '.xlsx');
}

// ============================================================
// 4) TOPLU YAZMA + DENETİM KAYDI + HATA RAPORU
// ============================================================

// satirlar: Supabase'e POST edilecek şekilde HAZIRLANMIŞ (snake_case,
// tablo sütunlarıyla birebir) nesneler dizisi — spec eşlemesi çağıranın
// sorumluluğunda (bkz. satin-alma.html kalemExcelUygula). batchSize'lık
// gruplar halinde tek dizi-body POST atılır (saveLnSiparisler deseni):
// grup İÇİ atomik (Postgres tek bir çoklu-satır INSERT ifadesi olarak
// çalıştırır), gruplar ARASI DEĞİL — bir grup başarısız olursa önceki
// gruplar DB'de kalır, bu açıkça sonuç nesnesinde raporlanır.
async function excelTopluYaz(tabloAdi, satirlar, opts){
  opts = opts || {};
  const batchSize = opts.batchSize || 500;
  const sonuc = { toplamYazilan: 0, basariliGrup: 0, hataliGrup: 0, hatalar: [] };
  if (!satirlar || !satirlar.length) return sonuc;

  for (let i = 0; i < satirlar.length; i += batchSize) {
    const grup = satirlar.slice(i, i + batchSize);
    const url = SB_URL + '/rest/v1/' + tabloAdi + (opts.onConflict ? '?on_conflict=' + opts.onConflict : '');
    const headers = opts.onConflict
      ? { ...SB_HEADERS, 'Prefer': 'resolution=merge-duplicates,return=representation' }
      : { ...SB_HEADERS, 'Prefer': 'return=representation' };
    try {
      const r = await fetch(url, { method: 'POST', headers, body: JSON.stringify(grup) });
      if (!r.ok) {
        const metin = await r.text();
        sonuc.hataliGrup++;
        sonuc.hatalar.push({ grupBaslangic: i, mesaj: metin });
        console.error('excelTopluYaz grup hatası (' + i + '-' + (i + grup.length) + '):', metin);
      } else {
        sonuc.basariliGrup++;
        sonuc.toplamYazilan += grup.length;
      }
    } catch (e) {
      sonuc.hataliGrup++;
      sonuc.hatalar.push({ grupBaslangic: i, mesaj: String(e) });
      console.error('excelTopluYaz istisna:', e);
    }
  }
  return sonuc;
}

// bilgi: {tabloAdi, ilgiliId, dosyaAdi, kullaniciAd, mod, toplamSatir,
// yeniSayisi, guncellemeSayisi, hataSayisi, atlananSayisi}
// satirlar: excelSatirlariSiniflandir çıktısı (denetim detayı için).
async function excelImportGecmisiYaz(bilgi, satirlar){
  let importId = null;
  try {
    const r = await fetch(SB_URL + '/rest/v1/excel_import_gecmisi', {
      method: 'POST', headers: { ...SB_HEADERS, 'Prefer': 'return=representation' },
      body: JSON.stringify({
        tablo_adi: bilgi.tabloAdi, ilgili_id: bilgi.ilgiliId || null, dosya_adi: bilgi.dosyaAdi || null,
        kullanici_ad: bilgi.kullaniciAd || null, mod: bilgi.mod || null,
        toplam_satir: bilgi.toplamSatir || 0, yeni_sayisi: bilgi.yeniSayisi || 0,
        guncelleme_sayisi: bilgi.guncellemeSayisi || 0, hata_sayisi: bilgi.hataSayisi || 0,
        atlanan_sayisi: bilgi.atlananSayisi || 0
      })
    });
    if (!r.ok) { console.error('excel_import_gecmisi yazılamadı — denetim izi eksik kalabilir:', await r.text()); return null; }
    importId = (await r.json())[0]?.id || null;
  } catch (e) { console.error('excel_import_gecmisi yazılamadı:', e); return null; }

  if (importId && satirlar && satirlar.length) {
    const satirBody = satirlar.map(s => ({
      import_id: importId, satir_no: s.satirNo, kayit_id: s.kayitId || null,
      durum: s.sinif, eski_deger: s.eskiDeger || null, yeni_deger: s.yeniDeger || null,
      hata_mesaji: (s.hatalar && s.hatalar.length) ? s.hatalar.join('; ') : null
    }));
    try {
      const r2 = await fetch(SB_URL + '/rest/v1/excel_import_satirlari', { method: 'POST', headers: SB_HEADERS, body: JSON.stringify(satirBody) });
      if (!r2.ok) console.error('excel_import_satirlari yazılamadı — satır detayları eksik kalabilir:', await r2.text());
    } catch (e) { console.error('excel_import_satirlari yazılamadı:', e); }
  }
  return importId;
}

// hatalilar: excelSatirlariSiniflandir çıktısından hata/bulunamadi/mukerrer
// satırları. spec'e "Hata Açıklaması" sütunu eklenmiş haliyle excelSablonIndir'i
// yeniden kullanır.
async function excelHataRaporuIndir(spec, hatalilar, dosyaAdi){
  const hataSpec = [..._excelGorunurAlanlar(spec), { alan: '_hata', baslik: 'Hata Açıklaması', tip: 'text' }];
  const veriler = (hatalilar || []).map(s => ({ ...s.alanlar, _hata: (s.hatalar || []).join('; ') }));
  await excelSablonIndir(hataSpec, veriler, dosyaAdi || ('hata-raporu-' + new Date().toISOString().split('T')[0] + '.xlsx'));
}
