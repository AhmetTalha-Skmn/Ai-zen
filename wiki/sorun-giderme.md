---
baslik: Sorun giderme
turler: hepsi
platformlar: hepsi
sira: 90
---
# Sorun giderme

<!-- yalniz: windows -->
## İlk bakılacak yer

Kontrol panelindeki **Takip sistemi** kartı:

| Satır | Normal görünüm |
|---|---|
| Görev | `hazır` ya da `çalışıyor`, sonraki çalışma saati dolu |
| İzleyici | `canlı · son örnek … sn önce` |
| Duraklatma | `kapalı` |

Kart **Sorun var** diyorsa **Şimdi kontrol et** takibi hemen bir kez çalıştırır.

## Süre artmıyor

- Takip duraklatılmış olabilir: **Sürdür**.
- Uygulama izinsiz sayılıyor olabilir: raporun **İncelenecek** sekmesi ve kurallar.
- İzleyici çalışmıyorsa takip onu 5 dakika içinde yeniden başlatır; **Şimdi kontrol et**
  bunu hemen yapar.

<!-- yalniz: bireysel ozel -->
## Uyarı çıkmıyor

Sırayla bak: [Ayarlar](ayarlar) bölümünde hatırlatmalar açık mı, takip duraklatılmış mı,
bugün **Vazgeçtim** seçilmiş mi, erteleme süresi dolmuş mu, hedef zaten tutulmuş mu.
<!-- /yalniz -->

## Engel çıkmıyor

Ekran kilidi açık mı, çalışma periyodu başlatılmış mı, **ACİL DURDUR** açık mı, uygulama
gerçekten izinsiz mi, son bir saatte 6 engel gösterilmiş mi.

## Kayıtlar

- `hatirlatici\log.txt`: takip turları, uyarılar, seçimler
- `hatirlatici\izleyici.log`: izleyici başlangıçları ve engeller
- `hatirlatici\aktivite\YYYY-MM-DD.csv`: 10 saniyelik ham ölçüm
<!-- /yalniz -->

<!-- yalniz: mac -->
## Pencere başlığı ya da alan adı boş

Erişilebilirlik izni yok. Paneldeki **İzin ver** düğmesi Sistem Ayarları’nı açar. İzin
olmadan da uygulama adıyla takip sürer.

## Süre artmıyor

- Takip duraklatılmış olabilir: menü çubuğundan **Takibi sürdür**.
- Tam ekran bir uyarı açıkken süre ölçülmez.
- Uygulama izinsiz sayılıyor olabilir: **Yerel kurallar** sekmesi.

<!-- yalniz: bireysel ozel -->
## Uyarı çıkmıyor

[Ayarlar](ayarlar) bölümünde hatırlatmaların açık olduğuna, takibin duraklatılmadığına ve
acil durdurmanın kapalı olduğuna bak. Bir saatte en fazla 6 uyarı gösterilir.
<!-- /yalniz -->

## Veri klasörü

**Ayarlar ve yedek** sekmesindeki **Veri klasörünü aç** ölçüm dosyalarını gösterir.
<!-- /yalniz -->
