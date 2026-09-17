# macOS sürümü — uyumluluk sözleşmesi ve inceleme listesi

> **Durum (16.09):** Mac sürümü yazıldı ve incelendi; kod ana deponun `macos/` klasöründe.
> Bu listedeki maddelerin otomatik sınanabilenleri `macos/Tests/CalismaTakipTests/WindowsInteropTests.swift`
> içinde; bulgular ve açık işler kökteki `DEVIR.md`'de.

Codex macOS'a özel sürümü yazarken, **bittiğinde inceleme** için hazırlandı. Kaynak: Windows
kodunun kendisi (`dagitik/Ortak.ps1`, `merkez-sunucu.ps1`, `istemci-*.ps1`,
`hatirlatici/`). Windows tarafı değişirse bu belge ve `protokol-vektorleri.json` da
güncellenmeli; `test-dagitik.ps1` vektörleri her çalıştırmada doğrular.

## 1. Mac istemci Windows merkeziyle konuşacaksa — bayt bayt aynı olmalı

### 1.1 Uçlar

| Yöntem ve yol | Kimlik | İmzalanan metin |
|---|---|---|
| `POST /v1/kayit` | eşleşme kodu (imza yok) | — |
| `POST /v1/ozet` | HMAC | gönderilen gövde baytları |
| `POST /v1/kural` | HMAC + `kuralYazabilir` izni | gönderilen gövde baytları |
| `GET /v1/kurallar` | HMAC | `/v1/kurallar` |
| `GET /v1/toplam?tarih=YYYY-MM-DD` | HMAC | yol + sorgu, ör. `/v1/toplam?tarih=2026-09-16` |
| `GET /health` | yok | — |

### 1.2 İstek imzası

- Başlıklar: `X-CT-Cihaz` (cihaz kimliği), `X-CT-Zaman` (Unix saniye, tam sayı metni),
  `X-CT-Imza` (küçük harf hex).
- `imza = HMAC-SHA256(base64çöz(cihazAnahtarı), UTF8(zaman + "\n" + imzalananMetin))`.
- İmzalanan gövde **gönderilen baytların aynısı** olmalı: imzadan sonra JSON yeniden
  biçimlendirilmez, alan sırası değiştirilmez.
- Merkez saat farkını ±900 sn kabul eder; fazlası 401.
- Cihaz kimliği `^[A-Za-z0-9_-]{3,64}$`, **büyük/küçük harf duyarlı**. (16.09'a kadar Türkçe
  Windows `I` içeren kimliği reddediyordu; düzeltildi, `test-dagitik` sınar.)

### 1.3 Eşleşme (kayıt)

- Kod: Crockford base32, 12 karakter, `XXXX-XXXX-XXXX`, alfabe
  `0123456789ABCDEFGHJKMNPQRSTVWXYZ`.
- Normalleştirme (iki taraf da yapar): büyük harfe çevir (kültürden bağımsız), `0-9A-Z`
  dışını sil, `I`→`1`, `L`→`1`, `O`→`0`.
- İstek gövdesi: `{schemaVersion:1, kod:<normal kod>, cihazAdi, kullanici, surum, onay:true}`.
  **Onay ekranı gösterilip kabul edilmeden istek gönderilmez**; Windows'ta onay yoksa hiçbir
  şey yazılmaz (çıkış 2).
- Merkez doğrulaması: `kayitOzeti = base64(PBKDF2-HMAC-SHA256(UTF8(kod), kayitTuzu, 120000, 32 bayt))`,
  sabit zamanlı karşılaştırma, 10 dakikada 10 deneme sınırı (429), kod tek kullanımlık.
- Yanıttaki `anahtar = {tuz, iv, veri, etiket}` (kayıt tuzundan **farklı** bir tuz):
  1. `k = PBKDF2-HMAC-SHA256(UTF8(kod), tuz, 120000, 64 bayt)`; AES anahtarı `k[0..31]`,
     MAC anahtarı `k[32..63]`.
  2. `etiket == HMAC-SHA256(macAnahtarı, iv ‖ veri)` sabit zamanlı doğrulanır; tutmazsa **çözme
     denenmez** ("kod yanlış veya paket değiştirilmiş").
  3. `AES-256-CBC`, PKCS7, `iv` ile çözülür → UTF-8 → base64 cihaz anahtarı (32 bayt).
- Dikkat: Windows merkezi .NET 4.7.2'den eskiyse PBKDF2 SHA1'e düşer (`Get-DagitikKodAnahtari`);
  o zaman SHA256 kullanan Mac eşleşemez. Windows 10/11'de .NET 4.8 var, sorun yok.

### 1.4 Günlük özet (`POST /v1/ozet`, şema 1)

`schemaVersion`, `cihazId` (başlıktakiyle aynı), `cihazAdi`, `gonderildiUtc` (ISO 8601),
`clientTarih` (yerel gün `yyyy-MM-dd`), `zamanDilimiOfsetDk`, `sira` (her gönderimde artar),
`veriKapsami`, `ozet {calismaDk, digerDk, bostaDk, kayitDk, hedefDk}`,
`uygulamalar [{ad, dakika, kategori, kaynak}]` (en çok 100), `basliklar` (yalnız cihaz başlık
izniyle), `alanlar` (hep boş), `health {senkron, kayitSatiri, sonOrnekUtc, yerelIzleyiciCalisiyor}`.

`veriKapsami` içinde `alanAdlari`, `tamUrl`, `aramaTerimleri`, `ekranGoruntusu`, `tusKaydi`
**her zaman false**. Mac sürümü bunlardan birini göndermeye başlarsa bu, kullanıcının onay
ekranında kabul ettiği şeyin dışına çıkmak demektir.

Gün dönümünde dünün kesin özeti bir kez kuyruğa alınır; merkez kapalıyken özetler kuyrukta bekler.

### 1.5 Kural senkronu

- İtme: `POST /v1/kural {schemaVersion:1, kararlar:[{oge, tur, karar}]}`;
  `tur ∈ surec|baslik|alanadi`, `karar ∈ calisma|yasakli|belirsiz`. 403 gelirse kuyruk
  temizlenir, birikmez.
- Çekme: `GET /v1/kurallar` → `calisma`, `yasakli`, `bilerekBelirsiz`, `silinenKurallar`,
  `sonDegisiklikUtc`. Birleştirme yalnızca `sonDegisiklikUtc` değişince yapılır.
- Birleştirme kuralları (`hatirlatici/kural-senkron.ps1`): merkez kazanır; yerelde olup merkezde
  olmayan öğe silinmez; tek istisna `silinenKurallar` (merkezde açıkça silinen, cihazdan da
  kalkar); `aslaEngelleme` hiç taşınmaz; aynı küme ikinci kez uygulanınca değişiklik üretmez.

### 1.6 Ortak sayaç

`GET /v1/toplam` → `digerCihazDk`. Veri 30 dakikadan eskiyse diğer = 0; hedef, uyarı ve seri
`yerel + diğer` üzerinden işler, `durum.json`'daki `dakika` her zaman yereldir.

## 2. En olası mantık hatası: süreç adları

Windows kuralları süreç adıyla yazılır (`chrome`, `Code`, `explorer`). macOS'ta aynı uygulama
`Google Chrome` / `com.google.Chrome`, `Code` / `com.microsoft.VSCode` olarak görünür. Ortak
kümede iki platformun adları yan yana durur; bir Windows kararı Mac'te **kendiliğinden geçerli
olmaz**. İncelemede bakılacaklar:

- Mac `surec` alanına ne yazıyor (uygulama adı mı, paket kimliği mi), her yerde tutarlı mı?
- Bu sınırlama kullanıcıya görünür mü (İncelenecek listesinde aynı uygulama iki kez sorulacak)?
- `alanadi` ve tam `baslik` kuralları platformdan bağımsız: gerçekten ortak paylaşılan kısım bu.
- `aslaEngelleme` Mac karşılığı var mı (öneri: `Finder`, `loginwindow`, `WindowServer`, `Dock`,
  `SystemUIServer`, `System Settings`, `Activity Monitor`, `Terminal`)? Yoksa engel ekranı
  kullanıcıyı sistemin dışına kilitleyebilir.

## 3. Aynı kalması gereken davranış

- Sınıflandırma önceliği: AFK > `calisma.baslik` / `calisma.alanadi` > yasaklı (süreç, başlık,
  alan adı) > `calisma.surec` > taze `.md` (7 dk) > belirsiz (sayılır, işaretlenir).
- Engel ekranı güvenlikleri: en fazla 3 dk, `DUR` dosyası her şeyi kapatır, `aslaEngelleme`,
  saatte en fazla 6 engel, duraklatma kapatır, **belirsiz asla engellenmez**. Mac'te tam ekran
  pencere Force Quit / Mission Control ile kapatılabilir kalmalı.
- `kurallar.json` yalnızca kullanıcının açık kararıyla değişir.
- Veri bilgisayarda kalır; tarayıcı geçmişi yalnız yerel rapor içindir.
- Paket kişisel dosya taşımaz: `kurallar/ayarlar/periyot.varsayilan.json` nötr şablonları.

## 4. macOS'a özgü riskler

| Konu | Bakılacak |
|---|---|
| İzinler (TCC) | Pencere başlığı için Erişilebilirlik, `CGWindowList` başlıkları için Ekran Kaydı (10.15+), tarayıcı adresi için tarayıcı başına Otomasyon izni. İzin yoksa durum **görünür** mü, yoksa süreler sessizce yanlış mı sınıflanıyor? |
| Boşta süresi | `ioreg -c IOHIDSystem` → `HIDIdleTime` nanosaniye; saniyeye doğru çevriliyor mu? |
| Arka plan | `~/Library/LaunchAgents` plist: `RunAtLoad`, `KeepAlive` / `StartInterval 300`. Uyku ve uyanma sonrası devam. |
| Tek örnek | İsimli mutex yok: kilit dosyası + süreç doğrulaması. Çöken sürecin kilidi takibi kalıcı susturmamalı (Windows'taki `GERI-YUKLEME` dersi). |
| Anahtar saklama | DPAPI karşılığı Keychain (`security add-generic-password`). Anahtar düz dosyada, logda, durum JSON'unda yok. |
| Veri klasörü | `~/Library/Application Support/...`. Masaüstü ve Belgeler iCloud'a eşitlenebilir; ölçüm verisi varsayılan olarak bulut klasörüne gitmemeli (Windows'ta yedek hedefinin bulut olmaması kuralı). |
| Çalışma zamanı | macOS'ta PowerShell yok; Python 3 de varsayılan gelmez. Hangi çalışma zamanı seçildi, kurulumda nasıl sağlanıyor, belgelenmiş mi? |
| Dağıtım | Gatekeeper, `com.apple.quarantine`, imza/notarization. Windows'ta imzasız EXE'nin Akıllı Uygulama Denetimi'ne takılmasının karşılığı. |
| Tarih | Yerel gün sınırı, ISO 8601; BSD `date` (GNU `date -d` yok). |
| Metin | UTF-8. Windows bazı JSON/CSV'leri BOM'lu yazar; Mac okuyucu BOM'u tolere etmeli, Windows'a gidecek dosyada BOM'suz UTF-8 sorun değil. |
| Kaldırma | LaunchAgent, Keychain girdisi ve (istenirse) veri siliniyor mu? |

## 5. Depo ve paket hijyeni

- `dagitik/paket-olustur.ps1` `hatirlatici/` altındaki tüm `.ps1`/`.vbs` dosyalarını ve `dagitik/`
  altındaki `.ps1/.cmd/.vbs/.md` dosyalarını **Windows paketine** koyar. Mac dosyaları bu iki
  klasöre girerse Windows kurulumuna sızar.
- `hatirlatici/test.ps1` bu iki klasördeki her `.ps1`'i **PowerShell 5.1** ile ayrıştırır.
  Mac için PowerShell 7 sözdizimiyle (`??`, `?.`, üçlü `?:`) yazılmış bir `.ps1` oraya konursa
  Windows testleri kırılır. Mac kodu ayrı bir kök klasörde olmalı.
- Windows dosyalarına dokunulduysa nedeni DEVIR'de yazmalı; dört Windows test paketi yeşil kalmalı.

## 6. Kabul testleri (incelemede istenecek)

1. `uyumluluk/protokol-vektorleri.json`: Mac kodu HMAC imzalarını ve PBKDF2 çıktılarını aynen
   üretmeli, kod normalleştirmesini aynen yapmalı, `anahtarZarfi`'nı `beklenenAnahtar`'a çözmeli,
   `yanlisKod` ile ve bozuk etiketle reddetmeli.
2. Mac istemci → Windows merkez: eşleşme; imzalı özet 200; yanlış imza, eski zaman damgası ve
   pasif cihaz 401; kural itme (izinli 200, izinsiz 403) ve çekme; toplam.
3. Merkez Mac'te de çalışacaksa tersi: Windows istemci Mac merkezle eşleşip gönderebilmeli; Mac
   merkezin ürettiği zarfı `Unprotect-DagitikKodIle` çözebilmeli.
4. Odak çalan / pencere açan testler varsayılan olarak kapalı.
5. İzin verilmemiş (TCC) durumda davranış testi.
