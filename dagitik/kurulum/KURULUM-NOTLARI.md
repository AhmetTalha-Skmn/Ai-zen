# Kurulum akışı — Codex için devir notu

Bu dosya kurulumun nasıl çalıştığını ve neye dokunulmaması gerektiğini anlatır.
Son kullanıcı belgesi değil (o `README.md`), pakete de girmez.

## İki çıktı, tek kaynak

`dagitik\paket-olustur.ps1` çalışınca `dagitik\cikti\` altında iki dosya oluşur:

| Çıktı | İçi | Kime |
|---|---|---|
| `Aizen-Kurulum.exe` | ZIP + `Baslat.cmd` (IExpress SFX) | Tek dosya indirip kuracak olan |
| `Aizen-Kurulum.zip` | Kurulum dosyaları + `uygulama\` yükü | Elle açmak / toplu dağıtım |

İkisi de aynı ZIP'ten üretilir; EXE yalnızca onu saran bir kabuktur.

## Çağrı zinciri

```
Aizen-Kurulum.exe (içindeki ZIP adı sabit: Calisma-Takip-Dagitik-Kurulum.zip)
  └─ Baslat.cmd            ZIP'i %TEMP%'e açar, Unblock-File, sihirbazı başlatır
      └─ Kur.ps1           SİHİRBAZ — arayüz, hiç kurulum mantığı yok
          └─ Kurulum.ps1   TÜM MANTIK burada (-Sessiz ile, ayrı süreçte)
              ├─ hatirlatici\baslangic.ps1     görev + izleyici (her iki rolde)
              ├─ kisayol.ps1                   masaüstü/Startup/Başlat menüsü + ARP kaydı
              ├─ dagitik\ana-kurulum.ps1       (Admin) dinleyici, urlacl, güvenlik duvarı
              └─ dagitik\istemci-kayit.ps1     (Kullanici + kod) onay, kayıt, DPAPI
                  └─ istemci-kurulum.ps1 -HazirAyar   gönderim görevi
```

ZIP'i elle açanlar `Kur.cmd` (sihirbaz), `Kurulum-Admin.cmd`,
`Kurulum-Kullanici.cmd` veya `Kurulum.cmd` (konsolda tür sorar) kullanabilir.
Hepsi aynı `Kurulum.ps1`'e gider. İki `.cmd` sarmalayıcı `CT_KURULUM_TURU=Sirket`
verir; parametre çakışması olmasın diye `-KurulumTuru` yerine ortam değişkeni.

## Kurulum.ps1 ne yapar

1. Rolü normalize eder (`AnaYonetici`→`Admin`, `Istemci`→`Kullanici`).
2. Hedef yolu doğrular (sürücü kökü olamaz, paketin içi/üstü olamaz). Kurulum
   türünü çözer: `-KurulumTuru` → mevcut `kurulum-bilgisi.json` (tür yoksa
   bireysel) → `CT_KURULUM_TURU` → bireysel. Özellikler türün varsayılanıdır;
   aynı türde güncellemede önceki seçim korunur, `-Hatirlatmalar`/`-EkranKilidi`
   en son uygulanır, şirkette hatırlatma her zaman kapalıdır.
3. **Koruyarak kopyalar** — aşağıya bak.
4. İndirilen dosyalarda kalan MOTW işaretini `Unblock-File` ile temizler.
5. `-YalnizKopyala` verilmişse burada durur (yan etkisiz prova).
6. Yerel takibi kurar, kısayolları ve Windows kaydını oluşturur.
7. Role göre: Admin → `ana-kurulum.ps1 -Kur`; Kullanici → kod varsa
   `istemci-kayit.ps1`, yoksa bağlanmadan bitirir.
8. `dagitik\kurulum-bilgisi.json` yazar (rol, `kurulumTuru`, `ozellikler`, paket
   sürümü, tarih, cihaz kimliği). `ayarlar.json`'a hiç yazmaz: kullanıcının
   Ayarlar'daki seçimi `hatirlatici\ozellikler.ps1`'de kurulumun önüne geçer.

## Bozulmaması gerekenler

- **Kullanıcı verisi ezilmez.** `Kurulum.ps1` başındaki `$KorunanDosyalar` ve
  `$KorunanKlasorler` listeleri güncellemede korunacakları belirler. Yeni bir
  ayar/veri dosyası eklersen **listeye de ekle**, yoksa ilk güncellemede silinir.
- **Sihirbaz mantık taşımaz.** Yeni bir kurulum davranışı gerekiyorsa
  `Kurulum.ps1`'e parametre ekle, sihirbaz onu geçsin. Böylece sessiz kurulum,
  konsol kurulumu ve sihirbaz aynı yoldan gider.
- **Onaysız bağlanma yok.** `-Onayla` yalnızca kullanıcı onay ekranını kabul
  ettiğinde geçilir. `istemci-kayit.ps1` onay yoksa hiçbir şey yazmaz (çıkış 2).
  Onay metni tek kaynakta: `istemci-kayit.ps1 -YalnizOnayMetni`.
- **Pakete yeni dosya eklemek** iki yer ister: `paket-olustur.ps1` içindeki
  kurulum kökü sabit listesi ve `Test-PaketIcerigi`'deki zorunlu dosya listesi.
  `uygulama\` yükü desenle kopyalanır, oraya eklemek yeterlidir.
- **IExpress klasör taşıyamaz.** SFX düz dosya listesi alır; bu yüzden içine
  ZIP + `Baslat.cmd` koyuyoruz. EXE'yi değiştireceksen bu kısıtı unutma.
- **Kodlama:** Türkçe içeren `.ps1` UTF-8 BOM ile (`Kur.ps1`, `Kurulum.ps1`),
  BOM'suz olanlar tamamen ASCII (`kisayol.ps1`, `kaldir.ps1`, `Baslat.cmd`).
  `test.ps1` bunu denetler.
- **Switch/değişken çakışması:** PowerShell'de `-OnayMetni` parametresi ile
  `$onayMetni` değişkeni aynı şeydir. Parametre `-YalnizOnayMetni` adını bu
  yüzden taşıyor.
- **Geri yükleme kalıntıları korunur.** `GERI-YUKLEME` işareti ve
  `geri-yukleme-yedekleri/` koruma listelerindedir: güncelleme süren bir geri
  yüklemenin işaretini silmez, güvenlik yedeklerini götürmez.

## Windows kaydı

`kisayol.ps1` üç şey yapar: masaüstü + Startup kısayolları, Başlat menüsünde
`Aizen` klasörü (`Aizen`, yöneticide `Aizen Merkez`,
`Yedekten geri yukle`, `Kaldir`; eski `Calisma Takip Sistemi` klasörü silinir), ve `HKCU\...\Uninstall\CalismaTakipSistemi`
kaydı (Ayarlar → Uygulamalar listesi). Kayıt HKCU altındadır, yönetici
gerektirmez. `kaldir.ps1` üçünü de geri alır.

## Yan etkisiz test yolları

| Ne | Nasıl |
|---|---|
| Kopyalama + güncelleme koruması | `Kurulum.ps1 -Rol Kullanici -Sessiz -YalnizKopyala -KurulumDizini <temp>` |
| Kaldırma | `kaldir.ps1 -Deneme -Onayla -UygulamaKok <temp>` |
| Sihirbaz ekranları | `$env:ARAYUZ_ONIZLEME=<png>; .\Kur.ps1 -Sayfa 1..4` |
| EXE içeriği | `Aizen-Kurulum.exe /T:<klasör> /C` (çalıştırmadan açar) |
| Kayıt/kaldırma kaydı | `test-dagitik.ps1` içindeki geçici `HKCU:\Software\CalismaTakipSistemiTest` bloğu |
| Geri yükleme | `yedek-geri-yukle.ps1 -Yedek <zip> -Kontrol` veri yazmaz; uygulama `test-gelistirme.ps1` içinde geçici kökte, sahte izleyici/panel süreçleriyle |

**Gerçek kurulumu geliştirme makinesinde çalıştırma.** Kurulum, "Calisma Takip
Sistemi" zamanlanmış görevini ve kısayolları kendi klasörüne bağlar; kullanıcının
`Desktop\Calisma-Takip-Sistemi` altındaki canlı kurulumu devre dışı kalır.
Uçtan uca denemek gerekirse ikinci bir makine ya da sanal makine kullan.

## Bilinen açıklar

1. EXE imzasız → SmartScreen "bilinmeyen yayımcı" uyarısı. Daha ağırı: Akıllı
   Uygulama Denetimi açık Windows 11'de imzasız EXE uyarısız engellenir, "yine de
   çalıştır" seçeneği yoktur (16.09'da geliştirme makinesinde yeni üretilen EXE
   böyle engellendi; Code Integrity olay 3077). Aynı içerik ZIP + `Kurulum.cmd` ile
   kurulabilir, fakat bu yol da Akıllı Uygulama Denetimi altında denenmedi. Kalıcı
   çözüm kod imzalama sertifikası: `paket-olustur.ps1` sonunda `signtool` adımı.
   Doğrulama için EXE'yi çalıştırma; içeriği kaynak olarak oku (`CABINET` RCDATA
   kaynağı → `expand.exe`).
2. Uçtan uca tıklama akışı (EXE → sihirbaz → kurulum → bitiş) hiç
   çalıştırılmadı; yalnızca parçaları sınandı.
3. `kaldir.ps1` gerçek silme kipiyle denenmedi (yalnız `-Deneme`).
4. 2 ve 3 için `test-gercek-kurulum.ps1` hazır (yalnız boş VM, yönetici,
   `-IzoleMakine`); henüz çalıştırılmadı. Geri yükleme de yalnız geçici kökte
   sınandı, canlı bir kurulumda denenmedi.

Paket kişisel `kurallar.json`, `ayarlar.json` ve `periyot.json` yerine nötr `*.varsayilan.json` şablonlarını taşır (paketi üreten makine duraklatılmış ya da periyot açıkken bu durum yeni kurulumlara gitmesin). Kurulum.ps1 hedefte dosya yoksa şablonu kopyalar; mevcut dosyayı değiştirmez. Yeni bir kullanıcı ayar dosyası eklersen aynı deseni kullan: şablon + `paket-olustur.ps1` zorunlu/yasak listeleri + `Kurulum.ps1` döngüsü. Ortak sayaç, kural kuyruğu ve merkez kuralları koruma listesine dahildir.
