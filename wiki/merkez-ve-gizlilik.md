---
baslik: Merkez ve gizlilik
turler: hepsi
platformlar: hepsi
sira: 70
---
# Merkez ve gizlilik

Bir **merkez**, izin vermiş bilgisayarların günlük özetlerini tek ekranda toplar. Merkez
kullanmak isteğe bağlıdır; bağlı olmayan bilgisayar hiçbir yere veri göndermez.

## Bağlanma

1. Yönetici merkezde bu bilgisayar için bir **eşleşme kodu** üretir. Kod tek kullanımlıktır
   ve varsayılan olarak bir saat geçerlidir.
2. Kod yüz yüze ya da telefonla söylenir. **E-postayla ya da ortak klasörle gönderilmez.**
3. Bilgisayarda kod girilir ve ne gönderileceğini gösteren **onay ekranı** kabul edilir.
   Onay verilmezse bağlantı kurulmaz.

## Ne gönderilir

| Gönderilir | Gönderilmez |
|---|---|
| Uygulama adı ve kategorisi (çalışma / diğer / boşta) | Tam adres, URL ve arama terimleri |
| Uygulama başına günlük süre toplamı | Tuş kaydı, pano, ekran görüntüsü, kamera, mikrofon |
| Takip sağlığı: izleyici çalışıyor mu, son ölçüm ne zaman | Dosya adları ve içerikleri |
| Senin verdiğin kural kararları (ortak kural senkronu) | Pencere başlıkları (yönetici ayrıca açıp onay ekranında göstermedikçe) |

Gönderim 5 dakikada bir yapılır. Merkez kapalıysa ya da ağ yoksa yerel takip durmaz;
özetler bekler ve bağlantı gelince gönderilir.

<!-- yalniz: windows -->
## Görmek ve kapatmak

- Ne gönderildiğini görmek: `dagitik\istemci-durum.ps1`
- Merkez bağlantısını kesmek (yerel takip kalır): `dagitik\kaldir.ps1 -YalnizMerkez`
<!-- /yalniz -->

<!-- yalniz: mac -->
## Görmek ve kapatmak

**Merkeze bağlan** sekmesi son gönderimi, bekleyen kararları ve hataları gösterir.
**Bağlantıyı kes** bağlantıyı kapatır ve cihaz anahtarını Anahtar Zinciri’nden siler.
<!-- /yalniz -->

<!-- yalniz: sirket -->
## Şirket kurulumunda

Şirket bilgisayarında hatırlatma ve varsayılan olarak ekran kilidi yoktur; merkez yalnızca
özetleri görür. Bu sistem yalnızca sahibi olunan ya da kullanıcısının açık rızası alınmış
bilgisayarlarda kullanılmalıdır.
<!-- /yalniz -->
