---
baslik: Yedek
turler: hepsi
platformlar: hepsi
sira: 80
---
# Yedek

Ölçüm verisi yalnızca bu bilgisayarda durduğu için düzenli yedek alınır.

<!-- yalniz: windows -->
## Otomatik yedek

- **Her pazar 20:00'de** "Calisma Takip Yedek" görevi çalışır. Bilgisayar o saatte
  kapalıysa ilk açılışta çalışır.
- Hedef klasör varsayılan olarak `Belgeler\CalismaTakipYedek` klasörüdür.
  `hatirlatici\ayarlar.json` içindeki `yedekKlasoru` ile değiştirilebilir. Bulut eşitleme
  klasörü önerilmez.
- Son **8** yedek saklanır, eskiler silinir.
- Kurallar, ayarlar, günlük toplamlar ve aktivite kayıtları yedeğe girer.

## Geri yükleme

Başlat menüsündeki **Yedekten geri yukle** kısayolu yedeği seçtirir, doğrular ve geri
yüklemeden önce mevcut verinin bir kopyasını alır.
<!-- /yalniz -->

<!-- yalniz: mac -->
## Otomatik yedek

Haftada bir yedek alınır; son 8 otomatik yedek saklanır. Kurallar, ayarlar, günlük
özetler ve aktivite CSV’leri dahildir. Cihaz anahtarları ve merkez sunucusunun verileri bu
yedeğe girmez.

## Geri yükleme

**Ayarlar ve yedek** sekmesinde **Yedekten geri yükle**. Yedek önce doğrulanır ve mevcut
verinin güvenlik yedeği alınır.
<!-- /yalniz -->
