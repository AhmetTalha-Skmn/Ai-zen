---
baslik: Ekran kilidi ve odak
turler: hepsi
platformlar: hepsi
sira: 60
---
# Ekran kilidi ve odak

Ekran kilidi, bir uyarının ya da engelin **ekranı kaplayıp kaplamayacağını** belirler.
Bireysel kurulumda açık, şirket kurulumunda kapalı başlar; özel kurulumda kurulum
sırasında seçilir. Her türde [Ayarlar](ayarlar) bölümünden değişir.

<!-- yalniz: windows -->
## Çalışma periyodu

Kontrol panelindeki **Çalışma periyodu** (25, 50, 90 ya da 120 dakika) başlatılınca:

- Ekran kilidi **açıksa**, izinsiz bir uygulama öne geldiğinde yaklaşık 10 saniye içinde
  ekranı kaplayan bir engel çıkar: **Çalışmaya dön**, **5 dk mola** ya da **Periyodu
  bitir**.
- Ekran kilidi **kapalıysa** periyot başlatılamaz; engel çıkmaz.

<!-- yalniz: bireysel ozel -->
Hatırlatma uyarılarının tam ekran ya da normal pencere olması da bu ayara bağlıdır:
[Hatırlatmalar](hatirlatmalar).
<!-- /yalniz -->

## Güvenlik sınırları

Ekran kilidi açıkken bile:

- Engel en geç **180 saniyede** kendiliğinden kapanır.
- İki engel arasında en az 60 saniye bulunur; bir saatte en fazla **6** engel gösterilir.
- Toplantı, kurulum ve sistem uygulamaları `kurallar.json` içindeki `aslaEngelleme`
  listesindedir ve hiç engellenmez.
- **ACİL DURDUR** düğmesi bütün engelleri kapatır ve periyodu bitirir. Aynı düğmeyle
  geri açılır.
<!-- /yalniz -->

<!-- yalniz: mac -->
## Odak oturumu

**Takip ve rapor** sekmesindeki **45 dk odak** bir odak oturumu başlatır.

- Ekran kilidi **açıksa**, izinsiz bir uygulama öne geldiğinde ekranı kaplayan bir uyarı
  çıkar: **Çalışmaya dön**, **5 dk mola**, **Acil durdur** ya da **Kapat**.
- Ekran kilidi **kapalıysa** odak oturumu başlatılamaz; engel uyarısı çıkmaz.

<!-- yalniz: bireysel ozel -->
Hatırlatma uyarısının tam ekran ya da küçük pencere olması da bu ayara bağlıdır:
[Hatırlatmalar](hatirlatmalar).
<!-- /yalniz -->

## Güvenlik sınırları

- Her uyarı en geç **3 dakikada** kendiliğinden kapanır.
- Bir saatte en fazla **6** uyarı gösterilir.
- Finder, Dock ve kritik macOS süreçleri hiç engellenmez.
- **Acil durdur** menü çubuğundan da her zaman kullanılabilir.
<!-- /yalniz -->
