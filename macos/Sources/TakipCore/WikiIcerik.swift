// Bu dosya uretilmistir: macos/scripts/generate-wiki.ps1 (kaynak: wiki/*.md). Elle degistirme.
// Yalniz macOS'ta gorunen sayfalar; platform bloklari cozulmus, tur bloklari Wiki.suz ile suzulur.

public enum WikiIcerik {
    public static let sayfalar: [WikiSayfasi] = [
        WikiSayfasi(ad: "ayarlar", baslik: "Ayarlar", turler: [], sira: 40, govde: #"""
# Ayarlar

Ayarlar, paneldeki **Ayarlar ve yedek** sekmesindedir.

## Kurulum türü

Bu bilgisayarın türünü gösterir: Bireysel, Şirket ya da Özel. Ne anlama geldiği:
[Kurulum türleri](kurulum-turleri).

<!-- yalniz: bireysel ozel -->
## Hatırlatmalar

Açıkken, bugün hedefin altındaysan ve 45 dakikadır çalışma ölçülmüyorsa uyarı çıkar.
Kapatınca ölçüm ve rapor aynen sürer, yalnızca uyarılar çıkmaz. Ayrıntı:
[Hatırlatmalar](hatirlatmalar).
<!-- /yalniz -->
<!-- yalniz: sirket -->
## Hatırlatmalar

Şirket kurulumunda hatırlatma yoktur. Ölçüm, rapor ve günlük hedef çalışmaya devam eder.
<!-- /yalniz -->

## Ekran kilidi

Açıkken odak oturumunda izinsiz bir uygulama öne gelince ekranı kaplayan bir uyarı çıkar.
<!-- yalniz: bireysel ozel -->
Hatırlatma uyarıları da tam ekran olur.
<!-- /yalniz -->
Kapalıyken hiçbir pencere ekranı kaplamaz ve engelleme yapılmaz.
Ayrıntı: [Ekran kilidi ve odak](ekran-kilidi-ve-odak).

## Varsayılana dön

Hatırlatma ve ekran kilidi seçimlerini siler; kurulumda seçilen değerler ya da türün
varsayılanı geçerli olur. Günlük hedef ve diğer ayarlar değişmez.

## Günlük hedef ve duraklatma

- **Günlük hedef**: 1–1440 dakika arası.
- **Duraklat**: süre boyunca uyarı çıkmaz, sayaç ilerlemez, aktivite kaydı tutulmaz.
  Takip **Sürdür** ile hemen döner.
"""#),
        WikiSayfasi(ad: "baslarken", baslik: "Başlarken", turler: [], sira: 10, govde: #"""
# Başlarken

Aizen, bu bilgisayarda çalışmaya ayırdığın süreyi ölçer ve günlük hedefe
göre gösterir. Ölçüm yerel olarak yapılır; bilgisayar bir merkeze bağlı değilse hiçbir
veri dışarı gönderilmez.


## Nereden açılır

- Menü çubuğundaki zamanlayıcı simgesi bugünkü süreyi gösterir.
- **Aizen’i aç** paneli açar: rapor, kurallar, merkez bağlantısı,
  **Ayarlar ve yedek** ve bu wiki (**Yardım** sekmesi).

## Kurulum türü

Uygulama üç türde kurulabilir: **Bireysel**, **Şirket** ve **Özel**. Tür, hatırlatma ve
ekran kilidi gibi özelliklerin varsayılanını belirler. Bu wiki de türe göre sayfa
gösterir. Ayrıntı: [Kurulum türleri](kurulum-turleri).

## Sayfalar

- [Kurulum türleri](kurulum-turleri)
- [Ölçüm ve sınıflandırma](olcum-ve-siniflandirma)
- [Ayarlar](ayarlar)
<!-- yalniz: bireysel ozel -->
- [Hatırlatmalar](hatirlatmalar)
<!-- /yalniz -->
- [Ekran kilidi ve odak](ekran-kilidi-ve-odak)
- [Merkez ve gizlilik](merkez-ve-gizlilik)
- [Yedek](yedek)
- [Sorun giderme](sorun-giderme)
"""#),
        WikiSayfasi(ad: "ekran-kilidi-ve-odak", baslik: "Ekran kilidi ve odak", turler: [], sira: 60, govde: #"""
# Ekran kilidi ve odak

Ekran kilidi, bir uyarının ya da engelin **ekranı kaplayıp kaplamayacağını** belirler.
Bireysel kurulumda açık, şirket kurulumunda kapalı başlar; özel kurulumda kurulum
sırasında seçilir. Her türde [Ayarlar](ayarlar) bölümünden değişir.


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
"""#),
        WikiSayfasi(ad: "hatirlatmalar", baslik: "Hatırlatmalar", turler: ["bireysel", "ozel"], sira: 50, govde: #"""
# Hatırlatmalar

Hatırlatmalar bireysel ve özel kurulumlar içindir; şirket kurulumunda bulunmaz. Her
zaman [Ayarlar](ayarlar) bölümünden kapatılabilir.


## Uyarı ne zaman çıkar

Bugünkü toplam hedefin altındaysa ve **45 dakikadır** çalışma ölçülmüyorsa uyarı çıkar.
Uyarılar arasında en az 3 dakika bulunur, bir saatte en fazla 6 uyarı gösterilir ve her
uyarı en geç 3 dakikada kendiliğinden kapanır.

## Ekran kilidine göre görünüm

- **Ekran kilidi açık**: uyarı bütün ekranları kaplar; açıkken süre ölçülmez.
- **Ekran kilidi kapalı**: uyarı küçük bir pencerede çıkar; çalışmaya devam edebilirsin ve
  ölçüm sürer.

Her iki durumda da **Çalışmaya dön**, **5 dk mola** ve **Acil durdur** seçenekleri vardır.

## Kapatınca ne değişir

Yalnızca uyarılar çıkmaz. Ölçüm, rapor, günlük hedef ve seri aynen sürer.
"""#),
        WikiSayfasi(ad: "kurulum-turleri", baslik: "Kurulum türleri", turler: [], sira: 20, govde: #"""
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


## Tür nasıl seçilir ya da değiştirilir

Mac uygulamasının ayrı bir kurulum sihirbazı yoktur. Tür, **Ayarlar ve yedek** sekmesinin
**Kurulum türü** bölümünden seçilir. Tür değişince hatırlatma ve ekran kilidi o türün
varsayılanına döner; sonra istediğin gibi değiştirebilirsin.
"""#),
        WikiSayfasi(ad: "merkez-ve-gizlilik", baslik: "Merkez ve gizlilik", turler: [], sira: 70, govde: #"""
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

## Farklı ağdayken

Merkez adresi iki biçimde olabilir; yönetici hangisini kullanacağını söyler:

| Adres | Ne zaman |
|---|---|
| `http://192.168.1.20:8787` | Merkezle aynı ağdasın ya da merkez internete açılmış |
| `https://posta.firma.com/k/...` | Farklı ağdasın ve merkez bir **posta kutusu** kullanıyor |

- Aktarım **şifrelidir**: aradaki ağ ve posta kutusu sunucusu özetleri, kodu ve kuralları
  okuyamaz, değiştiremez. Eşleşme kodu ağa hiç gönderilmez.
- Posta kutusunda özetler merkez bilgisayarı açılana kadar bekler. Eşleşme sırasında ise
  merkez bilgisayarı açık olmalıdır.
- Kayıtta merkez diğer adreslerini de şifreli olarak bildirir: bilgisayar ofise dönünce
  doğrudan bağlanır, dışarıdayken posta kutusunu kullanır. Seçim kendiliğinden yapılır.


## Görmek ve kapatmak

**Merkeze bağlan** sekmesi son gönderimi, bekleyen kararları ve hataları gösterir.
**Bağlantıyı kes** bağlantıyı kapatır ve cihaz anahtarını Anahtar Zinciri’nden siler.

<!-- yalniz: sirket -->
## Şirket kurulumunda

Şirket bilgisayarında hatırlatma ve varsayılan olarak ekran kilidi yoktur; merkez yalnızca
özetleri görür. Bu sistem yalnızca sahibi olunan ya da kullanıcısının açık rızası alınmış
bilgisayarlarda kullanılmalıdır.
<!-- /yalniz -->
"""#),
        WikiSayfasi(ad: "olcum-ve-siniflandirma", baslik: "Ölçüm ve sınıflandırma", turler: [], sira: 30, govde: #"""
# Ölçüm ve sınıflandırma

## Nasıl ölçülür

- Her **10 saniyede** bir öndeki uygulama kaydedilir.
- Erişilebilirlik izni verilirse pencere başlığı ve tarayıcı alan adı da kaydedilir. İzin
  yoksa uygulama adıyla takip sürer.
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


## Karar nerede verilir

**Takip ve rapor** sekmesindeki **İncelenecek uygulamalar** listesinden ya da **Yerel
kurallar** sekmesinden.

## Günlük hedef ve seri

Günlük hedef varsayılan olarak **240 dakikadır** ve [Ayarlar](ayarlar) bölümünden
değişir. Hedefin tutulduğu art arda günler **seri** olarak gösterilir.

Bilgisayar bir merkeze bağlıysa aynı kişinin diğer cihazlarındaki süre de bugünkü toplama
eklenir (ortak sayaç).
"""#),
        WikiSayfasi(ad: "sorun-giderme", baslik: "Sorun giderme", turler: [], sira: 90, govde: #"""
# Sorun giderme


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
"""#),
        WikiSayfasi(ad: "yedek", baslik: "Yedek", turler: [], sira: 80, govde: #"""
# Yedek

Ölçüm verisi yalnızca bu bilgisayarda durduğu için düzenli yedek alınır.


## Otomatik yedek

Haftada bir yedek alınır; son 8 otomatik yedek saklanır. Kurallar, ayarlar, günlük
özetler ve aktivite CSV’leri dahildir. Cihaz anahtarları ve merkez sunucusunun verileri bu
yedeğe girmez.

## Geri yükleme

**Ayarlar ve yedek** sekmesinde **Yedekten geri yükle**. Yedek önce doğrulanır ve mevcut
verinin güvenlik yedeği alınır.
"""#),
    ]
}
