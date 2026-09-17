# Aizen — Kurulum rehberi

Aizen bilgisayarda çalışmaya ayırdığın süreyi ölçer, günlük hedefe göre gösterir ve
rapor üretir. Ölçüm bu bilgisayarda kalır; bir merkeze bağlanmak isteğe bağlıdır.
Ekranların ne işe yaradığı: [Aizen-Ekranlar](Aizen-Ekranlar/README.md).

| Platform | Gereksinim | Durum |
|---|---|---|
| Windows 10 / 11 | Ek bir şey gerekmez (Windows PowerShell 5.1 yerleşik) | Kullanımda |
| macOS 13+ | Xcode 15+ ya da Command Line Tools | Kod yazıldı, **henüz bir Mac'te derlenip denenmedi** |

---

## Windows

### 1. Depoyu al

- **GitHub Desktop:** File → Clone repository → `aizen` → Clone.
- **Komut satırı:** `git clone https://github.com/<kullanici>/aizen.git`
- Git kullanmadan: GitHub sayfasında **Code → Download ZIP**, sonra ZIP'e sağ tıkla →
  **Özellikler → Engellemeyi kaldır** → tamamen çıkart.

### 2. Kurulum paketini üret

Depo kaynak kodu içerir; kurulum dosyası tek komutla üretilir. Depo klasöründe PowerShell aç:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File dagitik\paket-olustur.ps1
```

Çıktılar `dagitik\cikti\` altına yazılır:

| Dosya | Ne |
|---|---|
| `Aizen-Kurulum.exe` | Tek dosya; çalıştırınca kurulum sihirbazı açılır |
| `Aizen-Kurulum.zip` | Aynı içerik; elle açıp `Kur.cmd` ile kurmak için |
| `*.sha256` | Dosyaların doğrulama özeti |

Paket kişisel veri taşımaz: kurallar, ayarlar ve ölçümler yerine boş şablonlar girer.
Yalnızca ZIP istersen `-ExeAtla` ekle.

### 3. Kur

**`Aizen-Kurulum.exe`** dosyasını çalıştır. EXE imzalı olmadığı için:

- SmartScreen "bilinmeyen yayımcı" derse **Daha fazla bilgi → Yine de çalıştır**.
- **Akıllı Uygulama Denetimi** açık Windows 11'de imzasız EXE hiç açılmayabilir. O zaman
  `Aizen-Kurulum.zip`'i tamamen çıkart ve içindeki **`Kur.cmd`** dosyasını çalıştır.

Sihirbaz dört adımdır ([görüntüler](Aizen-Ekranlar/README.md#7-kurulum-sihirbazı)):

1. **Kurulum türü**

   | Seçenek | Kimin için | Hatırlatmalar | Ekran kilidi |
   |---|---|---|---|
   | **Bireysel kullanım** | Kendi çalışmasını takip eden kişi | Açık | Açık |
   | **Şirket · yönetici bilgisayarı** | Çalışanların özetlerini toplayacak merkez | Yok | Kapalı |
   | **Şirket · çalışan bilgisayarı** | Merkeze bağlanacak şirket bilgisayarı | Yok | Kapalı |
   | **Özel kurulum** | Kendi seçimin (istersen bu bilgisayar merkez olur) | Seçilir | Seçilir |

   *Hatırlatmalar:* hedefin altındayken ve çalışma ölçülmüyorken 45 dakikada bir çıkan
   uyarı ve hedef mesajı. *Ekran kilidi:* uyarının ekranı kaplaması ve çalışma periyodunda
   izinsiz uygulamanın engellenmesi. İkisi de kurulumdan sonra **Ayarlar**'dan değişir
   (şirket kurulumunda hatırlatma açılamaz).

2. **Kurulum klasörü:** varsayılan `%LOCALAPPDATA%\CalismaTakipSistemi`. Yönetici yetkisi
   gerekmez. Merkez olmayan kurulumda isteğe bağlı **merkeze bağlan**: merkez adresi
   (ör. `http://192.168.1.20:8787`) ve yöneticinin verdiği eşleşme kodu.
3. **Onay:** merkeze bağlanılacaksa ne gönderilip ne gönderilmeyeceği gösterilir; kabul
   edilmezse bağlantı kurulmaz.
4. **Kurulum:** ilerleme ekranda akar; bitince **Bitir**.

### 4. Kurulumdan sonra

| Nerede | Ne |
|---|---|
| Masaüstü | **Aizen** kısayolu: kontrol paneli. Merkez kurulumunda ayrıca **Aizen Merkez** |
| Başlat menüsü | **Aizen** klasörü: panel, merkez, yedekten geri yükleme, kaldırma |
| Ayarlar → Uygulamalar | **Aizen** kaydı; kaldırma buradan da yapılır |
| Arka plan | 5 dakikalık zamanlanmış görev ve 10 saniyelik ölçüm; oturum açılınca kendiliğinden başlar |

İlk günler için:

- Yeni kurulumda hiç kural yoktur; her uygulama **belirsiz** sayılır (varsayılan olarak
  çalışmaya eklenir). **Günlük raporu aç → İncelenecek** sekmesinden uygulama ve siteleri
  **İzinli**, **İzinsiz** ya da **Belirsiz kalsın** olarak işaretle.
- Günlük hedef varsayılan 240 dakikadır; kontrol panelinden ya da **Ayarlar**'dan değişir.
- Her ekranın açıklaması uygulamanın içinde de var: kontrol paneli → **Yardım**.

### Merkez kurulumu (isteğe bağlı)

1. Yönetici bilgisayarına **Şirket · yönetici** (ya da **Özel** + "Bu bilgisayar merkez
   olsun") ile kur. Ağ dinleme izni için Windows yönetici onayı ister.
2. İzlenecek her bilgisayar için kod üret:

   ```powershell
   cd "$env:LOCALAPPDATA\CalismaTakipSistemi\dagitik"
   .\cihaz-ekle.ps1 -Ad 'Ofis-PC-01'
   ```

3. Kodu **yüz yüze ya da telefonla** söyle; e-postayla ya da ortak klasörle gönderme. Kod
   tek kullanımlıktır ve varsayılan olarak bir saat geçerlidir.
4. Çalışan bilgisayarında sihirbazın 2. adımında merkez adresini ve kodu gir, onay
   ekranını kabul et. Sonradan bağlanmak için:

   ```powershell
   cd "$env:LOCALAPPDATA\CalismaTakipSistemi"
   .\dagitik\istemci-kayit.ps1 -SunucuUrl http://192.168.1.20:8787 -Kod ABCD-EFGH-JKMN
   ```

5. Özetler **Aizen Merkez** kısayolundan izlenir. Bağlantı düz HTTP'dir: yalnızca aynı
   yerel ağda ya da VPN üzerinden kullan, modemden port yönlendirme yapma.

Merkeze giden: uygulama adı ve kategorisi, uygulama başına günlük süre, takip sağlığı.
Gitmeyen: pencere başlıkları (yönetici ayrıca açmadıkça), tam adres, arama terimleri,
tuş kaydı, ekran görüntüsü, dosyalar.

### Konsoldan ve sessiz kurulum

ZIP'in içinden:

| Dosya | Ne yapar |
|---|---|
| `Kur.cmd` | Sihirbaz (EXE ile aynı) |
| `Kurulum.cmd` | Konsolda türü sorar |
| `Kurulum-Admin.cmd` | Şirket yönetici kurulumu |
| `Kurulum-Kullanici.cmd` | Şirket çalışanı kurulumu |

Toplu dağıtım için:

```powershell
.\Kurulum.ps1 -Rol Kullanici -KurulumTuru Bireysel -Sessiz
.\Kurulum.ps1 -Rol Admin -KurulumTuru Sirket -Sessiz
.\Kurulum.ps1 -Rol Kullanici -KurulumTuru Sirket -Sessiz -SunucuUrl http://192.168.1.20:8787 -Kod ABCD-EFGH-JKMN -Onayla
.\Kurulum.ps1 -Rol Kullanici -KurulumTuru Ozel -Hatirlatmalar Kapali -EkranKilidi Acik -Sessiz
```

`-Onayla`, onay metnini kullanıcıyla önceden paylaştıysan verilir. Ayrıntılar:
[dagitik/kurulum/README.md](dagitik/kurulum/README.md).

### Güncelleme

Yeni paketi üretip **aynı klasöre** yeniden kur. Kurallar, ayarlar, ölçüm verisi, merkez
kaydı ve kurulum türü korunur; yalnızca uygulama dosyaları yenilenir. Eski adla
("Calisma Takibi") oluşmuş kısayollar güncellemede silinip **Aizen** adıyla yeniden oluşur.

### Yedek

Her pazar 20:00'de `Belgeler\CalismaTakipYedek` klasörüne otomatik yedek alınır, son 8
yedek saklanır. Geri yüklemek için Başlat menüsü → **Aizen → Yedekten geri yukle**.

### Kaldırma

- **Ayarlar → Uygulamalar → Aizen → Kaldır** ya da Başlat menüsü → **Aizen → Kaldir**.
- Görevler, kısayollar ve kayıt kaldırılır; **ölçüm verisi silinmez**. Onu da silmek için:

  ```powershell
  cd "$env:LOCALAPPDATA\CalismaTakipSistemi"
  .\dagitik\kaldir.ps1 -VeriyiDeSil
  ```

- Yalnızca merkez bağlantısını kesmek (yerel takip kalır): `.\dagitik\kaldir.ps1 -YalnizMerkez`

### Sorun giderme

| Belirti | Bak |
|---|---|
| Süre artmıyor | Kontrol paneli → **Takip sistemi** kartı: Görev ve İzleyici satırları. **Şimdi kontrol et** takibi ve izleyiciyi hemen çalıştırır. Duraklatma açık mı? |
| Uyarı çıkmıyor | Kurulum türü şirket mi, **Ayarlar**'da hatırlatmalar kapalı mı, bugün Vazgeçtim seçildi mi, hedef tutuldu mu? |
| Engel çıkmıyor | Ekran kilidi açık mı, çalışma periyodu başlatıldı mı, ACİL DURDUR açık mı? |
| Kayıtlar | Kurulum klasöründe `hatirlatici\log.txt`, `hatirlatici\izleyici.log`, `hatirlatici\aktivite\` |

---

## macOS

> Mac kodu Windows'ta yazıldı; **henüz bir Mac'te derlenip denenmedi**. Kurulum betiği
> önce testleri çalıştırır, başarısız olursa kurmaz.

1. Terminal'de geliştirici araçlarını kur (yoksa): `xcode-select --install`
2. Depoyu al (GitHub Desktop, `git clone` ya da Download ZIP).
3. `macos` klasöründeki **`Kur.command`** dosyasını aç. Finder açmazsa Terminal'de:

   ```bash
   cd aizen/macos
   bash Kur.command
   ```

4. Uygulama `~/Applications/Aizen.app` olarak kurulur ve menü çubuğunda açılır.
5. **Sistem Ayarları → Gizlilik ve Güvenlik → Erişilebilirlik** bölümünden Aizen'e izin
   ver (pencere başlığı ve tarayıcı alan adı için; izin yoksa uygulama adıyla takip sürer).
6. Panelde **Ayarlar ve yedek → Kurulum türü** ile Bireysel / Şirket / Özel seç; oturum
   açınca başlatmayı buradan aç.

Kaldırma: `macos/Kaldir.command`. Veriler (`~/Library/Application Support/CalismaTakip`)
ve Anahtar Zinciri kayıtları korunur. Ayrıntı: [macos/README.md](macos/README.md).

---

## Geliştirenler için

| Komut | Ne sınar |
|---|---|
| `hatirlatici\test-ozellikler.ps1` | Kurulum türü, ayar yazımı, wiki (geçici klasörde) |
| `dagitik\test-dagitik.ps1` | Merkez protokolü, kurulum paketi, kurulum türleri (geçici klasörde) |
| `hatirlatici\test.ps1`, `test-api.ps1`, `test-kapsamli.ps1` | Çalışan bir kurulumu gerektirir |
| `macos` içinde `swift test` | Mac çekirdeği (yalnız macOS) |

GitHub Actions (`.github/workflows/`) ilgili dosyalar değişince Windows testlerini ve Mac derlemesini çalıştırır.
Proje yapısı ve teknik ayrıntılar: [README.md](README.md).
