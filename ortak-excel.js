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
