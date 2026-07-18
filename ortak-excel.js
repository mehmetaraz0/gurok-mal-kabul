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
    return (val===undefined||val===null) ? '' : val;
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

// spec: excelSablonIndir ile aynı. satirlar: excelDosyaOku'nun döndürdüğü
// ham diziler (satirlar[0]=başlık). mevcutKayitlar: sistemdeki güncel
// kayıtlar (id + doğal anahtar alanlarını içeren nesneler dizisi).
// opts: {dogalAnahtarlar:['urun_kodu','urun_adi'], fkAlan:'urun_kodu',
// fkSet:Set<string>}.
// Döner: {satirNo, alanlar, sinif, hatalar[], eskiDeger, yeniDeger, kayitId}[]
// sinif ∈ 'yeni'|'guncelleme'|'degisiklik_yok'|'hata'|'bulunamadi'|'mukerrer'
function excelSatirlariSiniflandir(spec, satirlar, mevcutKayitlar, opts){
  opts = opts || {};
  const gorunur = _excelGorunurAlanlar(spec);
  const idSpec = spec.find(s => s.kilitli);
  const dogalAnahtarlar = opts.dogalAnahtarlar || ['urun_kodu', 'urun_adi'];

  const mevcutById = {};
  const mevcutByDogal = {};
  (mevcutKayitlar || []).forEach(k => {
    if (k.id) mevcutById[String(k.id)] = k;
    for (const alan of dogalAnahtarlar) {
      if (k[alan]) { mevcutByDogal[alan + ':' + String(k[alan]).trim().toLowerCase()] = k; break; }
    }
  });

  const gorulenDogalAnahtar = new Set();
  const sonuc = [];
  const dataRows = (satirlar || []).slice(1);

  dataRows.forEach((row, i) => {
    const satirNo = i + 2; // Excel'deki gerçek satır no (1 = başlık)
    if (!row || row.every(c => c===undefined || c===null || String(c).trim()==='')) return;

    const alanlar = {};
    gorunur.forEach((s, c) => {
      alanlar[s.alan] = (row[c] !== undefined && row[c] !== null) ? String(row[c]).trim() : '';
    });

    const hatalar = [];
    gorunur.forEach(s => { if (s.zorunlu && !alanlar[s.alan]) hatalar.push(s.baslik + ' zorunlu, boş bırakılamaz'); });
    gorunur.forEach(s => {
      if (s.tip === 'number' && alanlar[s.alan]) {
        const n = parseFloat(String(alanlar[s.alan]).replace(',', '.'));
        if (isNaN(n)) hatalar.push(s.baslik + ' sayısal olmalı');
        else if (n <= 0) hatalar.push(s.baslik + " 0'dan büyük olmalı");
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
      let dogalKey = null;
      for (const alan of dogalAnahtarlar) {
        if (alanlar[alan]) { dogalKey = alan + ':' + String(alanlar[alan]).trim().toLowerCase(); break; }
      }
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
