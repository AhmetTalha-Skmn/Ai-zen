# Aizen — macOS ek paketi

Aizen'in (eski adı Çalışma Takip Sistemi) Mac sürümü; ana projenin `macos/` klasörü. Swift/SwiftUI kaynak paketidir. **Yerel takip, Windows/Mac merkezine bağlanan istemci ve Mac merkez sunucusu** aynı uygulamadadır. Windows sürümüyle aynı protokolü konuşur; Windows dosyaları veya kullanıcı verileri bu pakete girmez.

**Durum:** Kaynak kod, kurulum betikleri ve testler hazırlandı. Kod Windows üzerinde yazıldı; derleme ve testler GitHub Actions'ta (`.github/workflows/macos.yml`) çalışır, gerçek Mac kullanım testi henüz yapılmadı. Derlenmiş/noter onaylı bir uygulama içermez. Kullanımdan önce aşağıdaki Mac doğrulaması gerekir. CI ve Windows uyumluluk testleri: [SUREKLI-TEST.md](SUREKLI-TEST.md).

## Gereksinimler ve kurulum

- macOS 13 Ventura veya üzeri.
- Swift 5.9 veya üzerini sağlayan Xcode/Command Line Tools (Xcode 15 veya üzeri).
- Intel ve Apple Silicon desteklenecek şekilde kaynak yazıldı; derleme hangi Mac’te yapılırsa o mimarinin uygulamasını üretir. Paket evrensel hazır binary değildir.
- Haricî Swift paketi, Homebrew, Python veya Node kurmak gerekmez.

1. ZIP’i Mac’te aç.
2. Geliştirici araçları yoksa Terminal’de **xcode-select --install** çalıştır ve kurulumun bitmesini bekle.
3. **Kur.command** dosyasını aç. Betik önce Swift testlerini, sonra release derlemesini çalıştırır; başarısız olursa kuruluma geçmez.
4. Uygulama kullanıcı hesabının **~/Applications/Aizen.app** konumuna kurulur ve menü çubuğunda açılır. Menüden “Aizen’i aç” ile panele ulaş. Önceki sürüm (`Calisma Takip.app`) kurulumda kaldırılır; veriler korunur. Oturum açınca başlatma açıksa Aizen’de yeniden açılmalıdır.
5. Sistem Ayarları → Gizlilik ve Güvenlik → Erişilebilirlik bölümünden uygulamaya izin ver. İzin olmadan uygulama adıyla takip sürer; başlık/alan adı boş kalabilir.
6. İstenirse Ayarlar ve yedek → “Oturum açınca başlat” seçeneğini aç. macOS ayrıca Giriş Öğeleri onayı isteyebilir.

Finder çalıştırma izni nedeniyle betiği açamıyorsa Terminal’de paket klasörüne geçip **bash Kur.command** çalıştır. Kod yerel olarak ad hoc imzalanır; Apple Developer ID/noter onayı yoktur. Betikler Gatekeeper’ı kapatmaz. macOS izin değişikliği isterse Sistem Ayarları’ndan değerlendir; güncellemeden sonra Erişilebilirlik iznini yeniden vermek gerekebilir.

Güncellemek için menüden uygulamadan çıkıp yeni paketin Kur.command dosyasını çalıştır. Kullanıcı verileri uygulama paketinin dışında kaldığı için korunur.

## Tek Mac ile takip

- Ön plandaki uygulama, pencere başlığı ve erişilebilen tarayıcı alan adı yaklaşık 10 saniyede bir ölçülür.
- 5 dakika girdisizlik boşta sayılır. Uyku/askıya alma ve büyük saat sıçramaları çalışma süresi üretmez.
- Varsayılan hedef 240 dakikadır; ayarlardan değiştirilebilir.
- Paket **nötr kurallarla** başlar. Kişisel uygulama/site listesi içermez. Belirsiz süreler başlangıçta çalışma sayılır ve inceleme listesinde görünür; bu ayar kapatılabilir.
- İncelenecekler’den uygulama kararı verilebilir; Yerel kurallar’dan uygulama, tam başlık veya alan adı eklenebilir.
- Öncelik: boşta → izinli başlık/alan adı → yasaklı kural → izinli uygulama → belirsiz.
- Kararlar geçmiş ölçümleri yeniden hesaplamaz.
- **Kurulum türü** (Ayarlar ve yedek → Kurulum türü ve özellikler): Bireysel (hatırlatma ve ekran kilidi açık), Şirket (hatırlatma yok, kilit kapalı), Özel (hatırlatma açık, kilit kapalı başlar). Tür değişince iki anahtar o türün varsayılanına döner; sonra ayrı ayrı değişir. Eski `state.json` bireysel sayılır. Windows'taki anlamın aynısıdır.
- Ekran kilidi açıkken 45 dakikalık odak oturumunda yasaklı kullanım tam ekran uyarı açar; kilit kapalıyken odak başlatılamaz. Hatırlatmalar açıksa ve hedef dolmadıysa 45 dakikalık hatırlatma vardır: kilit açıkken tam ekran, kapalıyken küçük, kapatılabilir pencere.
- Uyarı en fazla 3 dakika açık kalır; saatte en fazla 6 kez gösterilir. Mola, kapat ve acil durdurma kullanılabilir. Tam ekran uyarı açıkken süre yazılmaz; küçük pencere ölçümü durdurmaz.
- **Yardım** sekmesi uygulama içi wiki'dir; türe göre sayfa gösterir. İçerik depodaki `wiki/*.md` dosyalarından `Sources/TakipCore/WikiIcerik.swift`'e üretilir (`scripts/generate-wiki.ps1`, Windows'ta çalışır); elle düzenleme.
- Acil durdurma **uyarıları** kapatır; ölçüm sürer. Ölçümü kapatmak için duraklat veya uygulamadan çık.
- Günlük uygulama/kategori dağılımı ve CSV dışa aktarma paneldedir.

Bu sürüm uygulamaları zorla sonlandırmaz ve sistem çapında ağ engeli kurmaz. Uyarılar kullanıcı tarafından kapatılabilir.

## Mac’i merkez sunucu olarak kullan

1. **Mac merkez** sekmesinde portu belirle (varsayılan 8787).
2. Yalnız bu Mac için LAN seçeneğini kapalı tut. Diğer bilgisayarlar bağlanacaksa **LAN’a aç** seçeneğini açıp “Merkezi başlat” seç.
3. macOS sorarsa yerel ağ/gelen bağlantı iznini ver. Merkezi yalnız güvenilen özel ağ/VPN üzerinden kullan; modemden bu portu internete yönlendirme.
4. Yeni cihaz adı yaz ve bir saatlik eşleşme kodu üret. Her cihaz için ayrı kod kullan.
5. İstemcide adres olarak **http://MAC-IP-ADRESI:8787** ve o cihazın kodunu gir.
6. Cihaz listesinden aktifliği ve “Kural yazabilir” yetkisini yönet. Yeni cihazın kural yazma yetkisi başlangıçta kapalıdır.
7. Ortak kurallar sekmesinden kural ekle/değiştir/sil. Güncel istemciler ortak silme kayıtlarını da alır.

Mac’in kendi ölçümlerinin merkez toplamına katılması için merkezde bu Mac adına da kod üret, ardından **Merkeze bağlan** sekmesinden **http://127.0.0.1:8787** adresine kaydol. Aynı uygulama eşzamanlı olarak sunucu ve istemci olabilir.

Merkez uygulama açıkken ve kullanıcı oturumu sürerken çalışır. Mac uyuduğunda veya uygulamadan çıkıldığında hizmet durur. Sunucu modu bir sistem daemon’u değildir. Açılışta çalışması için uygulamanın otomatik başlatmasını etkinleştir. Port/LAN/ortak hedef değişikliği için merkezi kapatıp yeni ayarlarla başlat.

Ortak hedef ve cihaz hedefleri merkez panelindeki karşılaştırma hedefleridir; cihazların yerel ayarını uzaktan değiştirmez. Günlük toplam cihaz sürelerinin toplamıdır; eşzamanlı iki cihaz kullanımı otomatik olarak tek süreye indirgenmez. Farklı saat dilimlerinde rapor günü istemcinin yerel günüdür.

## Mac’i Windows merkezine bağla

Windows merkez panelinden cihaz ve kod üret. Mac’in **Merkeze bağlan** sekmesinde Windows merkez adresini ve kodu gir, veri kapsamını okuyup onayla. Ana Windows projesinde değişiklik yapmak gerekmez.

Windows istemciyi Mac merkezine bağlarken mevcut Windows istemcisinin kayıt ekranında Mac’in LAN adresini ve Mac merkezinde üretilen kodu kullan.

Kod biçimi, kayıt anahtarı zarfı ve istek imzası Windows v1 protokolüne göre uygulandı. **Gerçek Windows ↔ Mac ağ testi henüz yapılmadı.** Sabit şifreleme örneklerinin Windows/.NET ve Node karşılaştırması geçti; bu, canlı entegrasyon testinin yerine geçmez.

Senkron 5 dakikada bir çalışır. Özet gönderimi, kullanıcı karar kuyruğu, ortak kurallar ve ortak sayaç ayrı hata durumlarıyla izlenir. Ağ kesilince yerel takip sürer; bekleyen günler bağlantı gelince sırayla gönderilir. Diğer cihazların toplamı 30 dakika eskiyse hedef hesabında kullanılmaz. Kural yazma yetkisi reddedilirse karar kuyruğu görünür şekilde korunur; yetkiyi merkezden açıp tekrar senkronla.

Merkezdeki karar aynı yerel öğeyi değiştirir. Henüz gönderilememiş açık kullanıcı kararları gönderim tamamlanana kadar Mac’te korunur. Yerelden silme ortak silme değildir; merkezdeki kural sonraki turda geri gelebilir.

## Veri, yedek ve kaldırma

Veri klasörü: **~/Library/Application Support/CalismaTakip/**

| Konum | İçerik |
| --- | --- |
| state.json | Yerel kurallar, ayarlar, günler, bağlantı bilgisi ve bekleyen kararlar |
| center-state.json | Merkez cihazları, ortak kurallar, silme kayıtları ve cihaz özetleri |
| aktivite/ | Yerel başlık/alan adı içerebilen günlük CSV |
| yedekler/ | Yerel takip yedekleri |
| DUR | Acil uyarı durdurma işareti |
| macOS Anahtar Zinciri | İstemci ve merkez cihaz anahtarları; JSON’da bulunmaz |

Merkeze uygulama/süre/kategori özeti ve senkron sağlığı gönderilir. Ham ölçüm başlıkları, alan adları, tam URL, dosya içeriği, ekran görüntüsü veya tuş kaydı gönderilmez. **Kural olarak karar verilen başlık/alan adı ortak kural içeriği olarak paylaşılır.** Tarayıcı geçmişi okunmaz.

Uygulama haftada bir yerel yedek alır, son 8 yedeği ve 90 günlük ölçümü saklar. Elle “Şimdi yedek al” aynı arşive yazar. Uzun süre saklanacak yedekleri buradan ayrı bir konuma kopyala. Yedekler şifreli değildir; paylaşırken içeriklerini dikkate al.

Yedek geri yüklemede SHA-256 ve izinli dosya yolları doğrulanır; mevcut verinin güvenlik yedeği alınır, yeni aktivite dosyaları hazırlanır, yazma hatasında geri alınır. Bu bütünlük özeti gizli anahtarlı bir imza değildir; güvenmediğin kaynaktan yedek yükleme.

**Yerel yedek merkez sunucusu verisini ve Anahtar Zinciri anahtarlarını kapsamaz.** Merkez için uygulama kapalıyken veri klasörünü ayrıca koru veya Mac sistem yedeğini kullan. Başka Mac’e veri klasörü kopyalamak cihaz anahtarlarını taşımaz; yeni eşleşme koduyla cihazları yeniden kaydetmek gerekir. Windows DPAPI anahtarları da Mac’e taşınamaz.

Kaldırmak için uygulamadan çıkıp **Kaldir.command** çalıştır. Otomatik başlatma kapatılır ve yalnız kurulu uygulama kaldırılır. **Kurallar, ayarlar, yerel kayıtlar, merkez kayıtları, yedekler, DUR ve Anahtar Zinciri girdileri korunur.** Yeniden kurulum nötr ayarlarla mevcut veriyi ezmez.

## Test ve mevcut sınırlar

Mac’te **Test.command** veya paket klasöründe **swift test** çalıştır. Kurulum da bu testleri zorunlu çalıştırır. Ayrıntılı yürütme durumu DOGRULAMA.md dosyasındadır.

31 Swift test metodu. 22'si sınıflandırma önceliği, alan adı sınırları, saat/uyku, veri kapsamı, ortak kurallar, anahtar zarfı, imza, bozuk yedek, yol geçişi, tek örnek kilidi ve merkez yetkilerini kapsar. 9'u Windows uyumluluk testidir (`WindowsInteropTests.swift`): gerçek Windows kodunun ürettiği istek ve yanıtlarla Mac merkezini ve istemcisini sınar. Testler geçici klasör ve bellek içi anahtar deposu kullanır; gerçek kullanıcı Anahtar Zinciri’ne yazmaz.

Windows sürümündeki tarayıcı geçmişi analizi, taze Markdown dosyası sezgisi, PowerShell API/MCP, sistem görevi onarımı ve Windows kurulum EXE’si bu ilk Mac paketine taşınmadı. Mac’te takip/kurallar/rapor/uyarı/yerel yedek/istemci/merkez akışları yeniden yazıldı. Tarayıcı alan adı okuması tarayıcı sürümü ve Erişilebilirlik ağacına bağlıdır; algılanamazsa boş bırakılır.

Kritik Mac kabul adımları: derleme ve Swift testleri; Erişilebilirlik/yerel ağ izinleri; gerçek ön plan/uyku/gece yarısı ölçümü; Safari/Chrome alan adı; uyarıdan çıkış; login item; iki yönlü Windows-Mac kayıt/özet/kural/toplam; güncelleme ve kaldırmada veri koruma.
