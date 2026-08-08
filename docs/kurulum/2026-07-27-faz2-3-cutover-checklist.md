# Faz 2-3 Cutover — sıra ve kontrol listesi

## Önemli düzeltme: sıra "3 sonra 2" olmalı, "2 sonra 3" DEĞİL

`pin-girisi` Edge Function'ı (Faz 3) kullanıcının **mevcut Auth parolasına hiç
bakmıyor** — eşleşmeyi `pin_dogrula` RPC'siyle (bcrypt/`pin_hash`) yapıp, Admin
API `generateLink`+`verifyOtp` ile parolasız bir session üretiyor. Yani:

- **Önce `index.html` cutover'ı canlıya alınırsa:** giriş hiç kesintiye
  uğramaz — yeni yol zaten parolayı kullanmıyor.
- **Önce Faz 2 (parola randomize) çalıştırılırsa** ve `index.html` hâlâ eski
  yolu (`supabaseAuthKoprusu` → PIN'i Auth parolası olarak gönderme)
  kullanıyorsa: parolalar değişir değişmez **TÜM kullanıcılar için giriş anında
  kırılır** — index.html cutover'ı devreye girene kadar gerçek bir kesinti
  yaşanır.

**Bu yüzden doğru sıra: önce `index.html` cutover (main'e merge+push), hemen
ardından (aynı oturumda) Faz 2 (parola randomize).** Aradaki birkaç dakikalık
pencerede eski "PIN = Auth parolası" açığı teknik olarak hâlâ (Auth'un kendi
`/auth/v1/token?grant_type=password` uç noktası üzerinden) sömürülebilir durumda
kalır — bu yüzden bu iki adım arka arkaya, ara vermeden yapılmalı.

## Sıra (siz "pencere uygun, şimdi" deyince)

**0) [TAMAMLANDI — cutover penceresinin DIŞINDA, önceden yapıldı/yapılıyor]**
`docs/kurulum/ana-proje/faz3-auth-link-backfill.html` ile tüm aktif
kullanıcıların `auth_user_id`'si önceden bağlandı (self-heal'e/pencere içi
sürprize bırakılmadı). `select ad, auth_user_id from public.kullanicilar
where aktif=true` ile `auth_user_id` boş satır kalmadığını teyit edin —
bağlantısız 0 olmadan 3. adıma geçmeyin.

1. **`pin-girisi` Edge Function'ı zaten deploy edilmiş ve bağımsız test edilmiş
   olmalı** (kendi PIN'inizle gerçek session döndüğü doğrulanmış) — bu adım
   index.html'e dokunmadığı için ayrıca, ÖNCEDEN yapılabilir/yapılmış olabilir.
   Backfill'den (0. adım) sonra en az bir eskiden-bağlantısız kullanıcıyla
   (İSMAİL KUZU/FATİH ATEŞ/WEWEEW) tekrar test edip artık `saglamaAdimlari`
   olmadan (zaten bağlı olduğu için self-heal hiç tetiklenmeden) `ok:true`
   döndüğünü görün.
2. Bu branch'teki (`security/pin-hash-faz2-faz3-prep`) `index.html` diff'ini
   gözden geçirip onaylayın.
3. Branch main'e merge + push edilir (canlıya alınır). **Bu andan itibaren
   giriş `pin-girisi` üzerinden çalışır**, eski parola-tabanlı yol artık
   kullanılmıyor (ama Auth'ta hâlâ eski parola değerleri duruyor).
4. **Hemen ardından**, `docs/kurulum/ana-proje/faz2-parola-randomize.html`
   dosyasını bilgisayarınızda açıp (deploy etmeden, doğrudan dosya olarak)
   çalıştırın: önce "Listele" (salt-okunur), sonra onay metnini yazıp
   parolaları randomize edin.
5. 2-3 gerçek kullanıcıyla (farklı roller) canlıda giriş testi yapın.
6. Sorun yoksa `faz2-parola-randomize.html` ve `faz3-auth-link-backfill.html`
   dosyalarını repodan/branch'ten silin (ikisi de bir daha gerekmeyecek, tek
   seferlik araçlar).
7. **2 hafta burn-in** — sorunsuz geçerse Faz 4 (`kullanicilar.pin` sütununu
   silme SQL'i) hazırlanır, siz onaylayınca çalıştırılır.

## Geri dönüş (cutover sonrası, burn-in içinde)

`index.html`'i bu commit'ten önceki sürüme `git revert` edin **ve** Faz 2
script'ini "ters" çalıştırın — yani her kullanıcının Auth parolasını tekrar
kendi `pin` (düz metin, hâlâ mevcut) değerine `PUT /auth/v1/admin/users/{id}`
ile geri yazın. Bunun için ayrı bir "geri yükleme" script'i hazır değil — Faz 2
aracının `rastgeleParola()` fonksiyonu yerine `pin` sütununun okunup
gönderildiği bir kopyası birkaç dakikada uyarlanabilir; ihtiyaç olursa yazarım.
