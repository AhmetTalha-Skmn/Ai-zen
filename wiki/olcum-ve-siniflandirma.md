---
baslik: Ölçüm ve sınıflandırma
turler: hepsi
platformlar: hepsi
sira: 30
---
# Ölçüm ve sınıflandırma

## Nasıl ölçülür

- Her **10 saniyede** bir öndeki uygulama kaydedilir.
<!-- yalniz: windows -->
- Pencere başlığı ve tarayıcılarda görünen adres çubuğundaki alan adı da kaydedilir.
<!-- /yalniz -->
<!-- yalniz: mac -->
- Erişilebilirlik izni verilirse pencere başlığı ve tarayıcı alan adı da kaydedilir. İzin
  yoksa uygulama adıyla takip sürer.
<!-- /yalniz -->
- **5 dakika** klavye ya da fare kullanılmazsa süre **boşta** sayılır.
- Ölçüm bu bilgisayarda tutulur. Tuş vuruşu, ekran görüntüsü, pano ve dosya içeriği
  kaydedilmez.

## Üç karar

Her uygulama, pencere başlığı ya da alan adı için bir karar verilebilir:

| Karar | Süre | Çalışma periyodunda |
|---|---|---|
| **İzinli** | Çalışma sayılır | Serbest |
| **İzinsiz** | Çalışma sayılmaz | Ekran kilidi açıksa engellenir |
| **Belirsiz** | Ayara göre sayılır ya da sayılmaz | Engellenmez |

Yeni kurulumda hiç kural yoktur; her şey belirsizdir. **Belirsiz süreler çalışma
sayılsın** ayarı açıkken (varsayılan) belirsiz süre de çalışmaya eklenir.

İzinli başlık kuralı izinsiz uygulamanın önüne geçer: örneğin tarayıcı izinsizken belirli
bir ders sayfasının tam başlığı izinli olabilir. İzinsiz alan adı ise izinli uygulamanın
önüne geçer.

<!-- yalniz: windows -->
## Karar nerede verilir

**Günlük raporu aç** penceresinin **İncelenecek** sekmesinde henüz karar verilmemiş
öğeler listelenir: **İzinli**, **İzinsiz** ya da **Belirsiz kalsın** seçilir. Kurallar
`hatirlatici\kurallar.json` dosyasında durur.
<!-- /yalniz -->

<!-- yalniz: mac -->
## Karar nerede verilir

**Takip ve rapor** sekmesindeki **İncelenecek uygulamalar** listesinden ya da **Yerel
kurallar** sekmesinden.
<!-- /yalniz -->

## Günlük hedef ve seri

Günlük hedef varsayılan olarak **240 dakikadır** ve [Ayarlar](ayarlar) bölümünden
değişir. Hedefin tutulduğu art arda günler **seri** olarak gösterilir.

Bilgisayar bir merkeze bağlıysa aynı kişinin diğer cihazlarındaki süre de bugünkü toplama
eklenir (ortak sayaç).
