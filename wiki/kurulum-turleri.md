---
baslik: Kurulum türleri
turler: hepsi
platformlar: hepsi
sira: 20
---
# Kurulum türleri

| Tür | Hatırlatmalar | Ekran kilidi | Kimin için |
|---|---|---|---|
| **Bireysel** | Açık, kapatılabilir | Açık, kapatılabilir | Kendi çalışmasını takip eden kişi |
| **Şirket** | Yok | Kapalı, açılabilir | Şirket bilgisayarları: yönetici ve çalışan |
| **Özel** | Kurulumda seçilir | Kurulumda seçilir | İkisinin arasında bir düzen isteyenler |

- **Ölçüm, rapor ve günlük hedef** her türde aynıdır.
- **Hatırlatmalar** 45 dakikalık çalışma uyarıları ve hedef mesajıdır. Şirket kurulumunda
  bulunmaz; ayarlardan da açılmaz.
- **Ekran kilidi** uyarının ve çalışma periyodu engelinin ekranı kaplayıp kaplamayacağını
  belirler. Her türde [Ayarlar](ayarlar) bölümünden açılıp kapanır.

## Tür ve merkez rolü ayrıdır

Kurulum türü bir bilgisayarın merkeze bağlanıp bağlanmayacağını belirlemez. Bireysel bir
kullanıcı da kendi bilgisayarlarını bir merkezde toplayabilir; şirket bilgisayarı da
merkeze bağlanmadan çalışabilir. Ayrıntı: [Merkez ve gizlilik](merkez-ve-gizlilik).

<!-- yalniz: windows -->
## Tür nasıl seçilir ya da değiştirilir

Kurulum sihirbazının ilk sayfasında seçilir: **Bireysel**, **Şirket · yönetici**,
**Şirket · çalışan** ya da **Özel**. Türü değiştirmek için sihirbazı yeniden çalıştırıp
aynı klasöre kur: kurallar, ayarlar ve ölçüm verisi korunur.

Seçim `dagitik\kurulum-bilgisi.json` dosyasına yazılır. Ayarlar penceresinde yaptığın
seçimler (`hatirlatici\ayarlar.json`) kurulumdaki seçimin önüne geçer.

Kurulum türü yazılmamış eski kurulumlar **Bireysel** sayılır; davranışları değişmez.
<!-- /yalniz -->

<!-- yalniz: mac -->
## Tür nasıl seçilir ya da değiştirilir

Mac uygulamasının ayrı bir kurulum sihirbazı yoktur. Tür, **Ayarlar ve yedek** sekmesinin
**Kurulum türü** bölümünden seçilir. Tür değişince hatırlatma ve ekran kilidi o türün
varsayılanına döner; sonra istediğin gibi değiştirebilirsin.
<!-- /yalniz -->
