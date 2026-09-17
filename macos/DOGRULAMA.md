# Doğrulama — 2026-09-16

Bu kayıt Windows üzerinde yapılan kontrolleri macOS’ta henüz yapılmayan kontrollerden ayırır.

| Kontrol | Sonuç |
| --- | --- |
| Deterministik .NET test vektörü üretimi | Geçti; gerçek kullanıcı verisi kullanılmadı |
| Bağımsız Node ile PBKDF2, AES, HMAC ve negatif kontroller | 8/8 geçti |
| Gerçek Windows Ortak.ps1 içindeki saf fonksiyonlarla karşılaştırma | 6/6 geçti; dosyalara veya kullanıcı verisine yazılmadı |
| Swift sözdizimi ağacı | 14 Swift dosyası, sıfır hata; derleme/tür denetimi değildir |
| Mac kabuk betikleri | 5 dosya bash -n ile geçti |
| PowerShell geliştirme betikleri | 2 dosya Parser::ParseFile ile geçti; ikisi de ASCII |
| Info.plist XML | Windows XML ayrıştırıcısıyla geçti; Mac plutil ayrıca derlemede zorunlu |
| ZIP | 34 girdi; geri açma, CRC32, manifest SHA-256 ve Unix izinleri geçti. Bağımsız .NET ZIP okuyucusu 33 kaynak girdisinin SHA-256 değerini doğruladı |
| swift test | Çalıştırılmadı: bu ortamda macOS SDK/Swift derleyicisi yok |
| Swift release derlemesi / codesign | Çalıştırılmadı: Mac gerekiyor |
| macOS arayüzü, izinler, ölçüm, login item | Çalıştırılmadı: gerçek Mac gerekiyor |
| Canlı Windows ↔ Mac istemci/merkez | Çalıştırılmadı: gerçek Mac gerekiyor |

Sözdizimi taramasında web-tree-sitter 0.20.8 ve tree-sitter-wasms 0.1.13 kullanıldı; arşivler npm SHA-512 bütünlük değerleriyle doğrulandı. Node’un varsayılan WebAssembly derleme işçileri bellek hatası verdi; liftoff-only, no-wasm-async-compilation ve wasm-num-compilation-tasks=1 ile tekrar çalışma başarıyla ve sıfır çıkış koduyla tamamlandı. Bu araçlar dağıtım paketinin bağımlılığı değildir.

## Tekrarlanabilir kontroller

Windows geliştirme kontrolleri:

    powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts/generate-fixture.ps1
    node scripts/verify-protocol.mjs
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts/verify-windows.ps1 -OrtakPath "WINDOWS-DEPOSU/dagitik/Ortak.ps1"

Son komut yalnız adı açıkça listelenen 6 saf fonksiyon tanımını alır; ana Windows betiğinin üst düzey kodunu çalıştırmaz. Mevcut Windows test paketleri bu Mac çalışmasında çalıştırılmadı; ana proje başka oturumda geliştiriliyor ve bu paket bağımsız.

Mac üzerinde:

    swift test
    bash scripts/build.sh

22 Swift test metodu vardır. Kripto testleri Windows vektörünü doğrudan Mac uygulamasının gerçek Crypto kodundan geçirir. Merkez testi doğrudan uygulamanın gerçek yönlendiricisini kullanır; soket/HTTP taşıma testi değildir.

Mac kabulü ayrıca şunları kapsamalı: gerçek ağda kayıt ve tekrar kayıt, iki taraflı özet, yazma yetkisi reddi/kabulü, ortak kural silme, imza/zaman hatası, çevrimdışı kuyruk, gerçek Erişilebilirlik verisi, uyku/gece yarısı sayacı, acil durdurma, açılış kaydı, yedek geri yükleme ve güncellemede/kaldırmada veri koruma.

Arşivi yeniden üretmek için:

    node scripts/package.mjs

Üretici yalnız izin verilen kaynak/test/betik/belge yollarını alır. Kullanıcı verisi, .build, dist ve Git dizinlerini almaz. PAKET-MANIFEST.json içerik özetidir; Mac’te testlerin geçtiği veya noter onaylı uygulama bulunduğu anlamına gelmez.
