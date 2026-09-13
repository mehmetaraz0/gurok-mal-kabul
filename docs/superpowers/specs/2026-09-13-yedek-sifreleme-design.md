# Yedek Şifreleme — Tasarım

**Tarih:** 2026-09-13 · **Durum:** onaylandı (kullanıcı, 2026-09-13)

## Neden

Elle alınan yedek 2026-09-13'ten beri `auth` şemasını da kapsıyor
(runbook §10). Dosya artık parola hash'leri, e-postalar ve **143 canlı oturum
/ yenileme token'ı** taşıyor; veri yedeği de misafir adı, telefon ve folyo
gibi kişisel veri içeriyor. Bugün ikisi de tek bir makinede **düz metin**
duruyor. Klasör erişimi kısıtlı olsa bile dosya kopyalanır, yanlışlıkla
paylaşılır ya da makine kaybolursa koruma kalmıyor.

## Kararlar

| Konu | Karar | Gerekçe |
|---|---|---|
| Yöntem | **Genel anahtarla şifreleme** (OpenSSL CMS, asimetrik) | Yedek alırken ikinci parola sorulmaz; makinede çözme anahtarı bulunmaz |
| Gizli anahtar nerede | **Parola yöneticisinde** (anahtar dosyası + kendi parolası) | Makine kaybında da erişilebilir; makinede kalıcı kopya yok |
| Prova | **Şifreli dosyayı çözerek koşar** | Her prova aynı zamanda anahtar tatbikatı olur |
| Araç | **OpenSSL 3.5.7** (CMS/S-MIME), Git for Windows ile gelen native Windows yapısı | Kurulum gerekmez, daemon yok, PowerShell ve Node'dan aynı şekilde çalışır |

**Araç kararı 2026-09-13'te düzeltildi.** Önce GnuPG seçilmişti; Git for
Windows'un GPG'si MSYS yapısıdır ve içeride `/c/...`, `/usr/lib/gnupg/keyboxd`
gibi POSIX yolları kullanır. Git Bash içinde çalışır, **PowerShell'den
çalışmaz** ("No Keybox daemon running"). Yedek betiği PowerShell olduğu için
GPG bu iş için kullanılamaz. OpenSSL aynı güvenlik modelini (genel anahtarla
hibrit şifreleme: AES-256 + RSA-4096) daemon'suz ve dosya tabanlı sağlar.

Reddedilen: Windows DPAPI / makineye bağlı anahtar — makine ölürse yedek de
ölür, korunmak istenen senaryoda işe yaramaz. Reddedilen: simetrik parola —
her yedekte ikinci parola istemi ve unutulma riski.

## Anahtar

Bir kez üretilir, kullanıcı tarafından (PowerShell):

```
openssl req -x509 -newkey rsa:4096 -keyout <gizli.pem> -out <sertifika.pem> -days 36500 -subj "/CN=Gurok ERP Yedek"
```

`-nodes` **kullanılmaz**: OpenSSL gizli anahtar için bir parola sorar, böylece
parola yöneticisindeki dosya kendi başına da şifreli olur.

Gizli anahtar (`gizli.pem`) ve parolası **parola yöneticisine** konur;
makinedeki kopya silinir.

Sertifika (genel anahtar) **repoya** girer: `docs/kurulum/yedek-anahtari.pem`.
Sır değildir; sürüm kontrolünde durması onu her makinede kullanılabilir kılar
ve hangi anahtarla şifrelendiğinin kaydını tutar.

**Alıcı doğrulaması:** sertifikanın serisi (`openssl x509 -noout -serial` →
`serial=58AC…`) ile şifreli dosyadaki alıcı serisi (`openssl cms -cmsout
-print` → `serialNumber: 0x58AC…`) karşılaştırılır.

## Ne şifrelenir

| Dosya | Karar | Gerekçe |
|---|---|---|
| `<etiket>-auth-yedegi.sql` | **Şifrelenir** → `.sql.enc` | Parola hash'i, e-posta, oturum ve yenileme token'ları |
| `<etiket>-veri-yedegi.sql` | **Şifrelenir** → `.sql.enc` | Misafir adı, telefon, folyo: kişisel veri |
| `<etiket>-auth-sema.sql` | Düz kalır | Yalnız tablo yapısı |
| `<etiket>-sayaclar.json` | Düz kalır | Yalnız sayılar; anahtarsız incelenebilmesi işe yarar |

## Akış — yedek alma

1. Dökümler bugünkü gibi alınır (aynı snapshot, tek parola istemi).
2. İki dosya genel anahtarla şifrelenir.
3. Şifreli dosya **doğrulanır**: boyutu sıfırdan büyük olmalı ve
   `openssl cms -cmsout -print` çıktısında beklenen alıcı anahtar kimliği görünmeli.
4. Doğrulama geçerse **düz kopyalar silinir**.
5. Saklama kuralı `.enc` adları üzerinden işler: yalnız **en yeni** auth
   yedeği durur.
6. Özette şifreli dosyaların yolu, boyutu ve SHA-256'sı yazılır.

**OpenSSL bulunamazsa ya da şifreleme başarısız olursa betik hata verip durur ve
düz kopyaları siler.** Sessizce düz metin yedek bırakmak, şifrelemenin hiç
olmamasından daha kötüdür: kullanıcı korunduğunu sanır.

## Akış — prova

Girdi dosyası `.enc` ile bitiyorsa prova onu **işletim sistemi geçici
klasörüne** çözer, kullanır ve `finally` içinde siler. Düz kopya ne repoya ne
de yedek klasörüne düşer.

Gizli anahtar ya da parolası yoksa çözme başarısız olur ve prova **açık bir
mesajla durur**: gizli anahtarın parola yöneticisinden içe aktarılması
gerektiği söylenir. Bu bilinçlidir — yedeğin açılabilirliği ancak
denendiğinde bilinir.

Çıktıya ayrı bir **çözme süresi** satırı eklenir.

## Hata ve kenar durumlar

| Durum | Davranış |
|---|---|
| `openssl` bulunamıyor (yedek alma) | Betik durur; düz kopyalar silinir; dosya üretilmez |
| Şifreleme hata verir | Aynı: durur, düz kopya bırakmaz |
| Genel anahtar dosyası yok / içe aktarılmamış | Betik durur ve anahtarın nasıl içe aktarılacağını yazar |
| Şifreli dosya beklenen alıcıyı taşımıyor | Şifreleme başarısız sayılır, düz kopya silinir, betik durur |
| Gizli anahtar ya da parolasi yok (prova) | Prova durur: "gizli anahtarı içe aktarın"; çıkış kodu 1 |
| Çözülen geçici dosya silinemedi | Uyarı yazılır ve yol raporlanır; kullanıcı elle silebilsin |
| `.enc` olmayan dosya verilir | Bugünkü davranış: doğrudan kullanılır (eski yedekler çalışmaya devam eder) |

## Tatbikat

Runbook'a yazılır: parola yöneticisinden gizli anahtarı içe aktarma, provayı
koşma, ardından gizli anahtar dosyasını makineden silme. Her prova bu
üç adımı içerir; böylece anahtarın çalıştığı düzenli olarak kanıtlanır.

## Kapsam dışı

- `dokum-al.ps1`'in ürettiği şema ve referans veri dökümleri (sır taşımazlar).
- Yedeklerin ikinci bir kopyaya ya da uzak depoya taşınması.
- Anahtar rotasyonu ve eski yedeklerin yeniden şifrelenmesi.
