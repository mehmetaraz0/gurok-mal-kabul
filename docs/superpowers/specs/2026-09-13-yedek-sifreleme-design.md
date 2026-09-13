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
| Yöntem | **Genel anahtarla şifreleme** (GnuPG, asimetrik) | Yedek alırken ikinci parola sorulmaz; makinede çözme anahtarı bulunmaz |
| Gizli anahtar nerede | **Parola yöneticisinde** (anahtar dosyası + kendi parolası) | Makine kaybında da erişilebilir; makinede kalıcı kopya yok |
| Prova | **Şifreli dosyayı çözerek koşar** | Her prova aynı zamanda anahtar tatbikatı olur |
| Araç | Git for Windows ile gelen **GnuPG 2.4.9** | Kurulum gerekmez; OpenSSL 3.5.7 de var ama GPG alıcı yönetimini kendi yapar |

Reddedilen: Windows DPAPI / makineye bağlı anahtar — makine ölürse yedek de
ölür, korunmak istenen senaryoda işe yaramaz. Reddedilen: simetrik parola —
her yedekte ikinci parola istemi ve unutulma riski.

## Anahtar

Bir kez üretilir, kullanıcı tarafından:

```
gpg --quick-generate-key "Gurok ERP Yedek <yedek@dornevi.local>" default default never
```

Gizli anahtarın kendisi de parolayla korunur. Gizli anahtar ve parolası
**parola yöneticisine** konur; makinedeki kopya silinir.

Genel anahtar **repoya** girer: `docs/kurulum/yedek-anahtari.pub.asc`. Sır
değildir; sürüm kontrolünde durması onu her makinede kullanılabilir kılar ve
hangi anahtarla şifrelendiğinin kaydını tutar.

## Ne şifrelenir

| Dosya | Karar | Gerekçe |
|---|---|---|
| `<etiket>-auth-yedegi.sql` | **Şifrelenir** → `.sql.gpg` | Parola hash'i, e-posta, oturum ve yenileme token'ları |
| `<etiket>-veri-yedegi.sql` | **Şifrelenir** → `.sql.gpg` | Misafir adı, telefon, folyo: kişisel veri |
| `<etiket>-auth-sema.sql` | Düz kalır | Yalnız tablo yapısı |
| `<etiket>-sayaclar.json` | Düz kalır | Yalnız sayılar; anahtarsız incelenebilmesi işe yarar |

## Akış — yedek alma

1. Dökümler bugünkü gibi alınır (aynı snapshot, tek parola istemi).
2. İki dosya genel anahtarla şifrelenir.
3. Şifreli dosya **doğrulanır**: boyutu sıfırdan büyük olmalı ve
   `gpg --list-packets` çıktısında beklenen alıcı anahtar kimliği görünmeli.
4. Doğrulama geçerse **düz kopyalar silinir**.
5. Saklama kuralı `.gpg` adları üzerinden işler: yalnız **en yeni** auth
   yedeği durur.
6. Özette şifreli dosyaların yolu, boyutu ve SHA-256'sı yazılır.

**GPG bulunamazsa ya da şifreleme başarısız olursa betik hata verip durur ve
düz kopyaları siler.** Sessizce düz metin yedek bırakmak, şifrelemenin hiç
olmamasından daha kötüdür: kullanıcı korunduğunu sanır.

## Akış — prova

Girdi dosyası `.gpg` ile bitiyorsa prova onu **işletim sistemi geçici
klasörüne** çözer, kullanır ve `finally` içinde siler. Düz kopya ne repoya ne
de yedek klasörüne düşer.

Gizli anahtar makinede yoksa çözme başarısız olur ve prova **açık bir
mesajla durur**: gizli anahtarın parola yöneticisinden içe aktarılması
gerektiği söylenir. Bu bilinçlidir — yedeğin açılabilirliği ancak
denendiğinde bilinir.

Çıktıya ayrı bir **çözme süresi** satırı eklenir.

## Hata ve kenar durumlar

| Durum | Davranış |
|---|---|
| `gpg` bulunamıyor (yedek alma) | Betik durur; düz kopyalar silinir; dosya üretilmez |
| Şifreleme hata verir | Aynı: durur, düz kopya bırakmaz |
| Genel anahtar dosyası yok / içe aktarılmamış | Betik durur ve anahtarın nasıl içe aktarılacağını yazar |
| Şifreli dosya beklenen alıcıyı taşımıyor | Şifreleme başarısız sayılır, düz kopya silinir, betik durur |
| Gizli anahtar yok (prova) | Prova durur: "gizli anahtarı içe aktarın"; çıkış kodu 1 |
| Çözülen geçici dosya silinemedi | Uyarı yazılır ve yol raporlanır; kullanıcı elle silebilsin |
| `.gpg` olmayan dosya verilir | Bugünkü davranış: doğrudan kullanılır (eski yedekler çalışmaya devam eder) |

## Tatbikat

Runbook'a yazılır: parola yöneticisinden gizli anahtarı içe aktarma, provayı
koşma, ardından `gpg --delete-secret-keys` ile makineden silme. Her prova bu
üç adımı içerir; böylece anahtarın çalıştığı düzenli olarak kanıtlanır.

## Kapsam dışı

- `dokum-al.ps1`'in ürettiği şema ve referans veri dökümleri (sır taşımazlar).
- Yedeklerin ikinci bir kopyaya ya da uzak depoya taşınması.
- Anahtar rotasyonu ve eski yedeklerin yeniden şifrelenmesi.
