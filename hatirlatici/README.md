# Aizen — Windows teknik belgesi

Bu alt klasör, bağımsız takip uygulamasının kodu ve yerel verisidir. Sistem herhangi bir ders planına, proje notuna veya belirli bir teknolojiye bağlı değildir.

## Bileşenler

| Dosya | İşlev |
|---|---|
| `izleyici.ps1` | 10 saniyede bir ön plan uygulamasını, başlığı ve etkinliği kaydeden kalıcı servis |
| `takip.ps1` | 5 dakikalık sayaç/uyarı turu; günlük görünümleri oluşturur |
| `gunluk-rapor.ps1` | Günlük uygulama ve isteğe bağlı tarayıcı özeti üretir |
| `api.ps1`, `mcp.ps1` | AI ve komut satırı için güvenli, kompakt arayüz |
| `baslangic.ps1` | Görev Zamanlayıcı ile izleyiciyi doğrular ve başlatır |
| `kontrol.ps1` | Yerel kontrol paneli |
| `ozellikler.ps1` | Kurulum türü (bireysel/şirket/özel), hatırlatma ve ekran kilidi anahtarları; alanları koruyan ayar yazımı |
| `ayarlar-penceresi.ps1`, `wiki-penceresi.ps1`, `wiki.ps1` | Ayarlar penceresi; türe göre süzülen uygulama içi yardım (`../wiki/*.md`) |
| `yedek-al.ps1`, `yedek-geri-yukle.ps1` | Haftalık veri yedeği; doğrulayıp önce güvenlik yedeği alarak geri yükleme |

## Sayma ve sınıflandırma

Bir örnek, son 5 dakikada klavye veya fare kullanılmışsa ve kural sonucu `calisma` ise sayılır. Günlük dakika, bu örneklerin toplam süresidir.

Kurallar `kurallar.json` dosyasındadır. Öncelik: AFK → çalışma başlığı veya alan adı → yasaklı süreç, başlık ya da alan adı → çalışma süreci → taze Markdown dosyası → belirsiz. Desteklenen tarayıcılarda adres çubuğu UI Automation ile okunabildiğinde alan adı kuralları canlı uygulanır; okunamadığında süreç ve başlık kuralları çalışmaya devam eder.

Çalışma periyodu isteğe bağlıdır. Yasaklı bir uygulamada tam ekran engel gösterir; ekran kilidi ayarı, `DUR` acil durdurma dosyası, periyot molası ve saatlik engel sınırı güvenlik kapılarıdır.

Hatırlatmalar (45 dakikalık uyarı, hedef mesajı) ve ekran kilidi kurulum türüne bağlıdır: `ayarlar.json` → `../dagitik/kurulum-bilgisi.json` → türün varsayılanı. Şirket kurulumunda hatırlatma yoktur; ekran kilidi kapalıyken uyarı normal, kapatılabilir bir penceredir ve periyot engeli çıkmaz.

## Çalıştırma ve test

Görev Zamanlayıcı adı `Calisma Takip Sistemi`dir. Startup kısayolu `Aizen.lnk` olarak oluşturulur (eski adı `Calisma Takip Sistemi.lnk`; kurulum temizler).

Takip çekirdeğinde değişiklikten sonra şu paketleri çalıştır:

```powershell
.\test.ps1
.\test-kapsamli.ps1
.\test-arkaplan.ps1
.\test-izole.ps1
.\test-api.ps1
```

Ön plan uygulaması açan testleri aktif oyun veya sunum sırasında çalıştırma. `CALISMATAKIP_TEST_SN` test pencerelerinin kendiliğinden kapanmasını sağlar; `test-temizlik.ps1` geçici süreçleri temizler.
