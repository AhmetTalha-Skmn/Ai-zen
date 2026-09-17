# Aizen — Kurulum

## En kolay yol: tek dosya

**`Aizen-Kurulum.exe`** dosyasını çalıştır. Kendi kendine açılır, kurulum
sihirbazı gelir. Klasör açmana, dosya kopyalamana gerek yok.

Windows "bilinmeyen yayımcı" uyarısı gösterebilir; paket imzalı değildir.
**Daha fazla bilgi → Yine de çalıştır** ile devam edilir. Akıllı Uygulama Denetimi açık
Windows 11'de imzasız EXE hiç açılmayabilir; o zaman ZIP'i tamamen çıkartıp `Kur.cmd` ile kur. İndirdiğin dosyanın
bozulmadığını yanındaki `.sha256` dosyasıyla karşılaştırabilirsin:

```powershell
Get-FileHash .\Aizen-Kurulum.exe -Algorithm SHA256
```

## Sihirbaz ne soruyor

1. **Kurulum türü**
   - **Bireysel kullanım** — kendi çalışmanı ölçer; 45 dakikalık hatırlatmalar ve
     ekran kilidi açık, ikisi de Ayarlar'dan kapatılabilir.
   - **Şirket · yönetici bilgisayarı** — çalışan bilgisayarlarının günlük özetlerini
     bu bilgisayarda toplar ve panelde gösterir. Ağ dinleme izni için Windows
     yönetici onayı ister. Hatırlatma yok, ekran kilidi kapalı.
   - **Şirket · çalışan bilgisayarı** — bu bilgisayarın süresi ölçülür. Hatırlatma
     yok, ekran kilidi kapalı (Ayarlar'dan açılabilir).
   - **Özel kurulum** — hatırlatma, ekran kilidi ve "bu bilgisayar merkez olsun"
     seçimleri senin.
2. **Kurulum klasörü** — varsayılan `%LOCALAPPDATA%\CalismaTakipSistemi`.
   Yönetici yetkisi gerekmez.
3. **Merkez bağlantısı** — yalnızca merkez olmayan kurulumda ve **isteğe bağlı**.
   İşaretlemezsen bu bilgisayar tek başına çalışır, hiçbir yere veri göndermez.
   İşaretlersen merkez adresini ve yöneticinin verdiği tek kullanımlık kodu girersin.
4. **Onay ekranı** — bağlanacaksan ne gönderilip ne gönderilmeyeceği listelenir.
   Kabul etmezsen bağlantı kurulmaz.
5. **Kurulum** — ilerleme ve kayıtlar ekranda görünür.

## Kurulumdan sonra

| Nerede | Ne |
|---|---|
| Masaüstü | `Aizen` (günlük panel), yönetici kurulumunda ayrıca `Aizen Merkez` |
| Başlat menüsü | `Aizen` klasörü: panel, merkez, kaldırma |
| Ayarlar → Uygulamalar | `Aizen` kaydı; kaldırma oradan da yapılabilir |

Yönetici kurulumundan sonra izlenecek her bilgisayar için kod üret:

```powershell
cd "$env:LOCALAPPDATA\CalismaTakipSistemi\dagitik"
.\cihaz-ekle.ps1 -Ad 'Ofis-PC-01'
```

Kodu yüz yüze ya da telefonla söyle. Tek kullanımlıktır ve varsayılan olarak
60 dakika geçerlidir; e-postayla ya da ortak klasörde bırakma.

## ZIP ile kurulum

EXE yerine ZIP indirdiysen paketi **tamamen çıkart** ve şunlardan birini çalıştır:

| Dosya | Ne yapar |
|---|---|
| `Kur.cmd` | Kurulum sihirbazını açar (EXE ile aynı) |
| `Kurulum-Admin.cmd` | Doğrudan şirket yönetici kurulumu (konsol) |
| `Kurulum-Kullanici.cmd` | Doğrudan şirket çalışanı kurulumu (konsol) |
| `Kurulum.cmd` | Konsolda tür sorar (şirket · yönetici / şirket · çalışan / bireysel) |

## Kurulum türü

`-KurulumTuru Bireysel|Sirket|Ozel`: Bireysel'de hatırlatmalar ve ekran kilidi açık,
Şirket'te hatırlatma yok ve kilit kapalı, Özel'de `-Hatirlatmalar Acik|Kapali` ve
`-EkranKilidi Acik|Kapali` ile seçilir (Şirket'te de kilit bu parametreyle açılabilir).

Verilmezse: aynı klasördeki mevcut kurulumun türü (türü yazılmamış eski kurulum
Bireysel sayılır) → yeni kurulumda `CT_KURULUM_TURU` ortam değişkeni
(`Kurulum-Admin.cmd` ve `Kurulum-Kullanici.cmd` bunu `Sirket` yapar) → Bireysel.
Kurulum kullanıcının `ayarlar.json`'una dokunmaz.

## Sessiz kurulum (toplu dağıtım)

```powershell
# Şirket yönetici bilgisayarı
.\Kurulum.ps1 -Rol Admin -KurulumTuru Sirket -Sessiz

# Şirket çalışanı, merkeze bağlanmadan
.\Kurulum.ps1 -Rol Kullanici -KurulumTuru Sirket -Sessiz

# Bireysel kullanım
.\Kurulum.ps1 -Rol Kullanici -KurulumTuru Bireysel -Sessiz

# Özel: hatırlatma kapalı, ekran kilidi açık
.\Kurulum.ps1 -Rol Kullanici -KurulumTuru Ozel -Hatirlatmalar Kapali -EkranKilidi Acik -Sessiz

# Kullanıcı bilgisayarı, kodla bağlanarak (onay komut satırında verilir)
.\Kurulum.ps1 -Rol Kullanici -Sessiz -SunucuUrl http://192.168.1.20:8787 -Kod ABCD-EFGH-JKMN -Onayla

# Yalnızca dosyaları kopyala (görev, kısayol ve bağlantı kurulmaz)
.\Kurulum.ps1 -Rol Kullanici -Sessiz -YalnizKopyala -KurulumDizini D:\Deneme
```

## Güncelleme

Aynı paketi aynı klasöre yeniden kur. Kurallar, ayarlar, ölçüm verisi, merkez
kaydı ve onay kaydı korunur; yalnızca uygulama dosyaları yenilenir.

## Kaldırma

Ayarlar → Uygulamalar → Aizen → Kaldır. Ya da:

```powershell
cd "$env:LOCALAPPDATA\CalismaTakipSistemi\dagitik"
.\kaldir.ps1 -Deneme          # önce ne yapacağını göster
.\kaldir.ps1                  # görevleri, kısayolları, kaydı ve merkez bağlantısını kaldır
.\kaldir.ps1 -YalnizMerkez    # yalnızca merkez bağlantısını kes
.\kaldir.ps1 -VeriyiDeSil     # ölçüm verisini de sil
```


Paket kişisel kurallar içermez. İlk kurulumda boş çalışma/yasak listeleri ve
Windows süreçleri için engelleme istisnaları içeren nötr kurallar oluşturulur;
belirsiz süreler sayılır. Mevcut kurallar güncellemede korunur. Merkeze bağlı
cihaz ortak kuralları gönderici turunda alır; bağımsız cihazda kararlar yerelden verilir.
