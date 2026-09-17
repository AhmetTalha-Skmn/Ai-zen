# Aizen — dağıtık katman

Bir **yönetici bilgisayarı** (merkez), izin vermiş **kullanıcı bilgisayarlarının**
günlük çalışma özetlerini toplar ve tek ekranda karşılaştırır. Her cihaz kendi
başına da çalışır: merkez kapalıysa ya da ağ yoksa yerel takip, uyarılar ve
raporlar durmaz; özetler kuyrukta bekler ve bağlantı gelince gönderilir.

Bu sistem yalnızca **sahibi olduğun ya da açık rıza verilmiş** cihazlarda
kullanılmalıdır. Hiçbir cihaz, kullanıcısı onay ekranını kabul etmeden merkeze
bağlanmaz.

## Kurulum

`dagitik\paket-olustur.ps1` iki çıktı üretir:

| Dosya | Ne |
|---|---|
| `Aizen-Kurulum.exe` | Tek dosya. Çalıştırılınca kendini açar ve **kurulum sihirbazını** başlatır. |
| `Aizen-Kurulum.zip` | Aynı içerik, elle açmak isteyenler için. İçinde `Kur.cmd` sihirbazı açar. |

Sihirbaz sırayla sorar: kurulum türü, kurulum klasörü, merkez olmayan kurulumda
isteğe bağlı merkez bağlantısı (adres + eşleşme kodu) ve bağlanılacaksa onay ekranı.

| Sihirbazdaki seçenek | Rol | Hatırlatmalar | Ekran kilidi |
|---|---|---|---|
| **Bireysel kullanım** | Kullanıcı | Açık | Açık |
| **Şirket · yönetici bilgisayarı** | Merkez | Yok | Kapalı |
| **Şirket · çalışan bilgisayarı** | Kullanıcı | Yok | Kapalı |
| **Özel kurulum** | İsteğe göre merkez | Seçilir | Seçilir |

Hatırlatmalar 45 dakikalık çalışma uyarıları ve hedef mesajıdır; şirket kurulumunda
hiç yoktur. Ekran kilidi uyarının tam ekran olup olmadığını ve çalışma periyodunda
izinsiz uygulamanın engellenip engellenmediğini belirler; her türde uygulamanın
**Ayarlar** penceresinden değişir. Tür `dagitik\kurulum-bilgisi.json`'a yazılır,
kullanıcının Ayarlar'daki seçimi (`hatirlatici\ayarlar.json`) bunun önüne geçer.
Uygulamanın **Yardım** penceresi yalnızca o türe ait sayfaları gösterir. Konsolu tercih edenler için
`Kurulum-Admin.cmd`, `Kurulum-Kullanici.cmd` ve sessiz kurulum parametreleri de
duruyor; ayrıntı `kurulum/README.md`'de.

Kurulum varsayılan olarak `%LOCALAPPDATA%\CalismaTakipSistemi` altına yapılır ve
yönetici yetkisi yalnızca merkez dinleyicisi için gerekir. Kurulum sonunda
masaüstü ve Başlat menüsü kısayolları oluşur, uygulama Windows'un **Ayarlar →
Uygulamalar** listesine kaydedilir (kaldırma oradan da yapılabilir).

Aynı paket yeniden kurulursa **kullanıcı dosyaları korunur**: kurallar, ayarlar,
ölçüm verisi, merkez kaydı ve onay kaydı üzerine yazılmaz; yalnızca uygulama
dosyaları yenilenir. EXE imzalı olmadığı için Windows "bilinmeyen yayımcı"
uyarısı gösterebilir; yanındaki `.sha256` ile doğrulanabilir.

## Eşleşme kodu ile bağlanma

Anahtar dosyası elden taşınmaz. Yönetici her cihaz için tek kullanımlık, süreli
bir kod üretir:

```powershell
cd $env:LOCALAPPDATA\CalismaTakipSistemi\dagitik
.\cihaz-ekle.ps1 -Ad 'Ofis-PC-01'
.\cihaz-ekle.ps1 -Adlar 'Ofis-1','Ofis-2','Ofis-3' -GecerlilikDakika 120   # toplu
.\cihaz-ekle.ps1 -Ad 'Ofis-PC-01' -KoduYenile                             # yeni kod
.\cihaz-ekle.ps1 -Ad 'Ofis-PC-01' -HedefDk 300                            # cihaza özel hedef
```

Kod kullanıcıya yüz yüze ya da telefonla söylenir. Kullanıcı `Kurulum-Kullanici.cmd`
çalıştırır, merkez adresini ve kodu girer, **ne gönderilip ne gönderilmeyeceğini
listeleyen onay ekranını** kabul eder. Ancak o zaman:

- Merkez cihaz anahtarını üretir ve **yalnızca kodu bilen tarafın çözebileceği
  biçimde şifreleyip imzalayarak** gönderir; anahtar ağda düz metin geçmez.
- Anahtar istemcide Windows DPAPI ile o kullanıcıya bağlı saklanır.
- Onay tarihi hem istemcide (`onay.json`) hem merkezde tutulur, panelde görünür.

Kod tek kullanımlıktır, süresi dolunca geçersizdir ve merkez kodun kendisini
değil PBKDF2 özetini saklar. Yanlış kod denemeleri 10 dakikalık pencerede
sınırlanır.

## Ne gönderilir, ne gönderilmez

Gönderilir: cihaz adı, son görülme, uygulama adı, kategori (çalışma/diğer/boşta),
uygulama başına günlük süre, günlük hedef ve takip sağlığı (izleyici çalışıyor mu).

Gönderilmez: pencere başlığı, tam adres/URL, arama terimi, tuş kaydı, pano,
ekran görüntüsü, dosya adı ve içerikleri. Pencere başlıkları yalnızca yönetici
`cihaz-ekle.ps1 -BasliklaraIzinVer` ile açıkça izin verirse gönderilir.

## Ortak sayaç (birden fazla bilgisayarda çalışma)

İki bilgisayarda çalışıldığında her ikisi de kendi başına 240 dakika sayıyor ve
ikisi de "hedefi tutturamadın" diyordu. Artık istemci, gönderim turunda merkeze
`GET /v1/toplam` ile sorup o günün **tüm cihazlardaki toplamını** alır ve
`hatirlatici/ortak-sayac.json` dosyasına yazar.

- Hedef, uyarı, seri, günlük rapor ve panel bu **toplam** üzerinden işler.
- `durum.json` içindeki `dakika` her zaman yalnızca o bilgisayarın ölçümüdür;
  `toplam` türetilmiş değerdir. Gün sonunda geçmişe iki değer de yazılır.
- Merkez kapalıysa, cihaz bağlı değilse ya da veri 30 dakikadan eskiyse toplam
  yalnızca yerel dakikaya düşer: sistem tek cihazdaki gibi çalışmaya devam eder.
- Uç nokta imzalıdır (HMAC) ve yalnızca sayı döndürür; ham aktivite, pencere
  başlığı ya da uygulama listesi gitmez. Cihaz kendi dakikasını iki kez saymasın
  diye merkez "diğer cihazlar" toplamından o cihazı düşer.

## Kural senkronu (bir kere karar ver, her cihazda geçerli olsun)

Bir uygulamayı "izinli" ya da "izinsiz" diye karara bağladığında bu karar
yalnızca o bilgisayarda kalıyordu; ikinci bilgisayarda aynı sorular baştan
geliyordu. Artık:

- Karar verildiğinde (`api.ps1 siniflandir` — yapay zeka da, rapor penceresindeki
  İncelenecek sekmesi de bunu kullanır) karar yerel kuyruğa yazılır.
- Gönderici kuyruğu merkeze iter (`POST /v1/kural`), sonra ortak kümeyi çeker
  (`GET /v1/kurallar`) ve yerel `kurallar.json` ile birleştirir.
- **Merkez kazanır:** her karar merkeze itildiği için merkezdeki değer en son
  karardır. Yerelde olup merkezde olmayan öğeler silinmez; yalnızca merkez
  panelinden silinen bir kural cihazlardan da kalkar.
- **`aslaEngelleme` taşınmaz.** O liste makineye özel güvenlik kapısıdır.

Yazma izni cihaz başınadır ve varsayılan olarak **kapalıdır**: kendi
bilgisayarların için `cihaz-ekle.ps1 -Ad 'Dizustu' -KuralYazabilir` ver, izlenen
başka birinin bilgisayarına verme (o cihaz yine kuralları okur, yazamaz).

Merkezdeki kümeyi ilk doldurmak için, yöneticinin kendi kurallarını bir kez aktar:

```powershell
.\kural-aktar.ps1                      # yerel hatirlatici\kurallar.json
.\kural-aktar.ps1 -Kaynak D:\kurallar.json
```

## Merkez paneli

Masaüstündeki **Aizen Merkez** kısayolu:

- Tüm cihazlar tek tabloda: durum, çalışma, hedef, yüzde, diğer, boşta, son veri,
  izleyici durumu, onay tarihi. Sessiz kalan cihaz kırmızı görünür.
- Gün seçici: bugün ya da arşivdeki herhangi bir gün.
- Seçili cihazın uygulama kırılımı ve son 14 günlük trendi.
- Üstte tüm cihazların ortak toplamı, ortak hedef ve kalan süre.
- Seçili cihaz için günlük hedef (0 = cihazın kendi hedefi), **aktif/pasif** ve
  **ortak kurallara yazabilir** izni; son gönderim ve bildirilen senkron hatası.
- **Ortak kurallar** sekmesi: kural ekle, kararını değiştir, sil. Değişiklik
  cihazlara bir sonraki gönderim turunda uygulanır (`-Sekme Kurallar` ile açılır).
- CSV dışa aktarım (masaüstüne `calisma-ozeti-<tarih>.csv`).

Panel ağ dinlemez ve uzaktan komut göndermez; yalnızca merkezde biriken
özet dosyalarını okur. Arayüzsüz kontrol için: `.\merkez-panel.ps1 -Kontrol`.

## Kaldırma

```powershell
.\kaldir.ps1 -YalnizMerkez    # merkez bağlantısını kes, yerel takip kalsın
.\kaldir.ps1                  # yerel takip + merkez bağlantısı
.\kaldir.ps1 -VeriyiDeSil     # ek olarak biriken ölçüm verisini de sil
.\kaldir.ps1 -Deneme          # hiçbir şey yapmadan ne yapacağını yaz
```

## Ağ sınırı ve güvenlik

Bu sürüm **özel LAN ya da VPN** içindir. Merkez portunu internete yönlendirme;
uzak cihazlar WireGuard, Tailscale veya kurum VPN'i üzerinden bağlanmalıdır.
Aktarım düz HTTP'dir; kimlik doğrulama ve bütünlük HMAC-SHA256 ile sağlanır,
fakat içerik şifreli değildir. İnternet üzerinde kullanım için HTTPS, sertifika
ve imzalı dağıtım ayrıca kurulmalıdır.

Merkez yalnızca imzalı `POST /v1/ozet` ve eşleşme kodlu `POST /v1/kayit`
isteklerini kabul eder. Geç kalmış paketler günün daha yeni özetini ezmez.
`saklamaGun` süresinden eski günlük arşiv otomatik silinir.

## Dosyalar

| Dosya | İşlev |
|---|---|
| `merkez-sunucu.ps1` | İmzalı özet ve kayıt isteklerini kabul eden dinleyici |
| `merkez-panel.ps1` | Yönetici paneli (karşılaştırma, trend, cihaz ayarları, ortak kurallar, dışa aktarım) |
| `Merkez-Ozet.ps1` | Özet/trend/gün toplamı/temizlik hesapları — panel ve testler aynı kodu kullanır |
| `Merkez-Kural.ps1` | Ortak kural kümesi (okuma, karar işleme, silme), cihaz ayarı, merkez dosya kilidi |
| `Senkron-Durum.ps1` | Cihazın senkron sağlığı; anahtar, adres ve kural içeriği döndürmez |
| `kural-aktar.ps1` | Mevcut bir `kurallar.json`'u ortak kümeye aktarır (ilk doldurma) |
| `cihaz-ekle.ps1` | Eşleşme kodu üretir (tekil ya da toplu) |
| `istemci-kayit.ps1` | Onay ekranı + kodla bağlanma, anahtarı DPAPI ile saklama |
| `istemci-kurulum.ps1` | Gönderim görevini kurar |
| `istemci-gonderici.ps1` | Kuyruk ve gönderim işçisi; gün kapanışını da yollar |
| `istemci-durum.ps1` | Bu cihazdan ne gönderildiğini gösterir |
| `kaldir.ps1` | Kaldırma (tamamı, yalnız merkez, deneme) |
| `kisayol.ps1` | Masaüstü ve Startup kısayolları |
| `paket-olustur.ps1` | Kişisel verisiz kurulum ZIP'i üretir |
| `test-dagitik.ps1` | İzole testler: kripto, kayıt akışı, sunucu, kurulum, kaldırma |


Paket kişisel kurallar içermez. İlk kurulumda boş çalışma/yasak listeleri ve
Windows süreçleri için engelleme istisnaları içeren nötr kurallar oluşturulur;
belirsiz süreler sayılır. Ayarlar da nötr başlar (günlük hedef 240 dk, duraklatma ve
periyot kapalı). Mevcut kurallar ve ayarlar güncellemede korunur. Merkeze bağlı
cihaz ortak kuralları gönderici turunda alır; bağımsız cihazda kararlar yerelden verilir.
