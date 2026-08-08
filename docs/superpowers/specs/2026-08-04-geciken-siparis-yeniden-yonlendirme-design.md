# Geciken Sipariş Yeniden Yönlendirme — Tasarım Dokümanı

**Tarih:** 2026-08-04
**Durum:** Tasarım onaylandı (kullanıcı, Yaklaşım A). Uygulama writing-plans → SDD ile.

## Amaç
Teslim tarihi (termin) geçmiş ve hâlâ (tam) gelmemiş siparişler için: (1) görünür **gecikme
uyarısı**, (2) tek tıkla **yeniden yönlendirme** — eski sipariş iptal edilir, gelmeyen kalemler
için yeni bir teklif talebi (RFQ) açılır; kullanıcı yeni tekliflerden başka firmaya sipariş verir.
Mevcut `satin-alma-siparistakip.html` durum takibi yapıyor ama gecikme uyarısı ve yeniden-yönlendirme
aksiyonu yok. **Sistem tek kullanıcılı** (yarış-durumu endişesi yok).

## Alınan Kararlar (kullanıcı onaylı, 2026-08-04)
1. **Aksiyon:** Yeniden teklife çık (yeni RFQ) + eski siparişi kapat → yeni tekliflerden BAŞKA firmaya sipariş.
2. **Kısmi teslimat:** Yalnızca **gelmeyen (kalan_miktar > 0) kısım** için yeni teklif. Gelen kısım korunur.
3. **Eski sipariş:** **İptal** edilir (`durum='iptal'`), kayıt SİLİNMEZ — geçmiş/denetim ve kısmi
   gelen mal kaydı korunur.
4. **Yaklaşım A:** Atomik RPC + UI butonu (istemci-tarafı iki-adımlı değil — TIER 1 atomiklik disiplini).

## Mimari + Veri Akışı
```
Sipariş Takip (gecikmiş sekme) ──"🔄 Yeniden Yönlendir"──▶ onay diyaloğu
  ──▶ RPC siparis_yeniden_yonlendir(p_siparis_no)  [TEK transaction]
        1) yetki + otel erişim kontrolü
        2) eski sipariş durum='iptal' + iptal notu (kim/ne zaman)
        3) kalan_miktar>0 kalemlerle yeni teklif_talebi + teklif_kalemleri
        4) yeni RFQ id döner
  ──▶ toast + Teklif Toplama ekranına git
  ──▶ (mevcut akış) yeni teklifler toplanır → başka firma seçilir → yeni sipariş
```
Yeni bir satın-alma akışı icat edilmez — mevcut **RFQ → teklif toplama → sipariş** makinesi tekrar kullanılır.

## Bileşenler

### 1) SQL — `siparis_yeniden_yonlendir(p_siparis_no text, p_olusturan text)` (yeni RPC)
`security definer`, `set search_path = public`. Adımlar (atomik, `raise exception` = rollback):
- Yetki: `auth_yetki_var('siparis_olustur','kayit')` yoksa exception.
- Siparişi bul (siparis_no ile); yoksa exception. `auth_otel_erisim(otel_id)` yoksa exception.
- Zaten 'iptal'/'tamamlandi' ise exception ("bu sipariş yeniden yönlendirilemez").
- Kalan kalemler = `siparis_kalemleri` where `siparis_no = p_siparis_no and kalan_miktar > 0`.
  Boşsa exception ("gelmeyen kalem yok").
- `update siparisler set durum='iptal', ... (iptal notu/aciklama) where siparis_no=p_siparis_no`.
- `insert into teklif_talepleri (olusturan, otel_id, durum) values (p_olusturan, <otel>, 'acik')` → yeni talep id.
  (İstemci CU.ad'ı p_olusturan olarak geçer — teklif_talebi_olustur deseniyle birebir aynı.)
- Her kalan kalem için `insert into teklif_kalemleri (teklif_talebi_id, urun_kodu, urun_adi, miktar, birim)`
  — miktar = **kalan_miktar** (gelmeyen kısım).
- `return` yeni teklif_talebi id (uuid).
- `revoke all from public; grant execute to authenticated`.

**Veri notları (uygulamadan önce CANLI şema doğrula):**
- `siparisler.durum`'un 'iptal' değerini kabul ettiği doğrulanmalı (enum ise label var mı; text ise sorun yok).
  UI'da 'iptal' rozeti zaten render ediliyor → büyük olasılıkla geçerli, yine de doğrula.
- İptal notu için `siparisler`'de uygun bir sütun (ör. `aciklama`/`iptal_notu`) var mı bak; yoksa
  sadece durum='iptal' yeter (not opsiyonel, YAGNI).
- `siparis_kalemleri.kalan_miktar` mal kabul kalite onayında güncelleniyor (mevcut davranış) — kaynak bu.
- `caller` (olusturan) adı: RPC içinde `auth.uid()`'den kullanıcı adı türetilemiyorsa, p parametresi
  olarak da alınabilir; ama teklif_talebi_olustur deseniyle tutarlı olması için olusturan'ı parametre
  yapmak yerine mevcut RPC'nin yaptığı gibi handle et (implementasyonda netleşir).

### 2) UI — `satin-alma-siparistakip.html`
- **Gecikmiş sekmesi:** "⏰ Gecikmiş" filtre sekmesi = `termin_tarihi` dolu VE `< bugün` VE
  `durum in ('bekleyen','kismi')`. Sayısı sekmede rozet olarak gösterilir.
- **Gecikti rozeti:** gecikmiş kartlarda kırmızı "⏰ X gün gecikti" etiketi.
- **"🔄 Yeniden Yönlendir" butonu:** `bekleyen`/`kismi` kartlarda (termin olmasa da elle erişilebilir).
  Tıkla → `confirm()` ("«X» siparişi iptal edilecek, kalan Z kalem için yeni teklif açılacak. Emin misin?")
  → RPC çağrısı → başarıda toast + `satin-alma-teklif-toplama.html`'e yönlendir (yeni RFQ görünür).
- Termin'siz (null) siparişler gecikmiş sekmesinde ÇIKMAZ ama butonları vardır (elle yönlendirme).

### 3) Yetki
Yeni ekran/modül yok — mevcut `siparis_olustur`/`siparis_takip` yetkileri kullanılır. RPC kendi
`auth_yetki_var` kontrolünü yapar (kozmetik UI kontrolü + gerçek RPC kontrolü iki katman).

## Kapsam Dışı (YAGNI)
Otomatik e-posta/SMS hatırlatma · termin-öncesi (proaktif) uyarı · otomatik firma seçimi/sipariş
· çoklu sipariş toplu yeniden yönlendirme · tedarikçi performans/gecikme skoru (ileride skorkart'a bağlanabilir).

## Test / Doğrulama Planı
1. **Gecikmiş sekmesi:** termin'i geçmiş bekleyen sipariş → sekmede görünür + "gecikti" rozeti;
   termin'i gelecek olan görünmez; tamamlanmış görünmez.
2. **Tam gelmeyen sipariş:** Yeniden Yönlendir → eski sipariş 'iptal' olur, yeni RFQ tüm kalemlerle açılır.
3. **Kısmi teslimat:** 60/100 gelmiş → Yeniden Yönlendir → yeni RFQ SADECE kalan 40 için; gelen 60 kaydı durur.
4. **Rollback:** RPC içinde kasıtlı hata (ör. geçersiz kalem) → eski sipariş 'iptal' OLMAMALI, RFQ oluşmamalı (atomik).
5. **Yetki:** siparis_olustur yetkisi olmayan kullanıcı → RPC 403/exception.
6. **Otel izolasyonu:** tek-otel kullanıcı başka otelin siparişini yönlendiremez.
7. **Uçtan uca:** yönlendir → Teklif Toplama'da yeni RFQ → başka firmadan teklif → yeni sipariş oluştur.

## Uygulama Devri
writing-plans → subagent-driven-development. Faz sırası: (1) SQL RPC (kullanıcı çalıştırır + SQL Editor'de
doğrular) → (2) UI (gecikmiş sekme + rozet + buton + RPC çağrısı) → (3) uçtan uca test. Her faz kullanıcı testi.
