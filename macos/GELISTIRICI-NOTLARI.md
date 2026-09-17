# Mac ek paket devir kaydı — 2026-09-16

Kullanıcı isteği: Windows ana projesine dokunmadan bağımsız Mac ek paketi; Mac hem takip istemcisi hem merkez sunucu olmalı.

16.09'dan beri bu klasör ana deponun `macos/` klasörüdür (git subtree ile, Codex geçmişi korunarak alındı). Windows paketi (`dagitik/paket-olustur.ps1`) ve Windows testleri (`hatirlatici/test.ps1`) bu klasörü okumaz; Mac dosyası `hatirlatici/` ya da `dagitik/` altına konmaz. Kurallar kökteki `AGENTS.md`, güncel devir kaydı kökteki `DEVIR.md`'dedir.

## Yapı ve bakım kuralları

- TakipCore: Foundation üzerinde sınıflandırma, nötr varsayılanlar, sayaç, kural birleştirme ve aktarım şeması.
- CalismaTakip: SwiftUI/AppKit menü çubuğu, Erişilebilirlik örnekleme, yerel dosyalar, Keychain, istemci ve Network.framework sunucusu.
- CTLegacyCrypto: Windows v1 ile uyumluluk için CommonCrypto PBKDF2/AES köprüsü; HMAC CryptoKit kullanır.
- Kurulum/güncelleme/kaldırma yalnız scripts/kurulum.sh içindedir. .command dosyaları ince çağırıcılardır; build.sh yalnız test/derleme/uygulama paketi üretir.
- Kullanıcı verisi koruma kapsamı README’deki tablodur. Yeni veri yolu eklenirse tablo ve paket izin listesi güncellenir.
- .ps1 yardımcı betiği yalnız ASCII içerir; Türkçe eklenecekse UTF-8 BOM kullanılmalıdır. Mac .sh/.command/Swift dosyaları UTF-8 ve LF’dir.
- Tek süreç dosya kilidi; state/center-state atomik dosya değişimi; sunucu durum işlemleri MainActor üzerinde sıralıdır.
- Hassas anahtarlar Keychain’de bu cihaza bağlıdır. Test anahtar deposu gerçek Keychain’den bağımsızdır.
- Nötr kurallar Models.swift içinden oluşturulur; gerçek Windows kurallar.json okunup pakete alınmaz.

## Windows v1 uyumu

İstek imzası: base64 cihaz anahtarının ham baytlarıyla HMAC-SHA256; UTF-8 olarak Unix saniyesi + LF + tam JSON gövdesi. GET’te gövde yerine yol ve sorgu imzalanır. Başlıklar X-CT-Cihaz, X-CT-Zaman, X-CT-Imza; kabul edilen saat sapması ±300 saniye.

Eşleşme: büyük harf ASCII kod, I/L → 1 ve O → 0. PBKDF2-HMAC-SHA256, 120000 tur, 16 bayt tuz, 64 bayt çıktı. İlk 32 bayt AES-256-CBC/PKCS7; sonraki 32 bayt IV+ciphertext HMAC anahtarı. Düz metin cihaz anahtarının base64 dizgesidir. Etiket çözmeden önce doğrulanır.

Uçlar: GET /health, POST /v1/kayit, POST /v1/ozet, GET /v1/kurallar, POST /v1/kural, GET /v1/toplam?tarih=YYYY-MM-DD.

Merkez yalnız Content-Length içeren HTTP/1.1 istekleri işler; gövde 512 KiB, başlık 32 KiB, bağlantı 20 saniye, eşzamanlı bağlantı 32 sınırı vardır. 100-continue desteklenir; chunked/HTTP2 uygulanmadı. Anahtarlar yönlendirmeye gönderilmez. TLS sunucusu dahil değildir; LAN/VPN veya ayrı güvenilir HTTPS sonlandırması gerekir. HTTP, taşıma gizliliği sağlamaz.

Tek kullanımlık kod 1 saat geçerli, kayıt denemesi sunucu genelinde 10 dakikada 20 ile sınırlıdır. Yeniden eşleştirme anahtarı döndürür ve yeni sıra numarası dönemini başlatır. Eski anahtar geçersiz olur. Rapor gününün eski sıra numarası yeni özeti ezmez.

## Devam işi

Önce bir Mac üzerinde swift test ve release derlemesini çalıştır; DOGRULAMA.md sonucunu güncelle. Apple SDK tür denetimi ve gerçek platform API davranışı Windows’ta doğrulanamadı. Canlı cihaz çiftinde kayıt, özet, kural, silme ve toplam uçlarını iki yönde dene. Mac olmadan “üretimde doğrulandı” etiketi verme.

Dağıtılabilir hazır uygulama için Apple Developer ID imzası ve noter onayı ayrıca gerekir; mevcut betik yalnız yerel ad hoc imza üretir.

Platform başvuruları:
- https://developer.apple.com/documentation/swiftui/menubarextra
- https://developer.apple.com/documentation/servicemanagement/smappservice
- https://developer.apple.com/documentation/applicationservices/1459186-axisprocesstrustedwithoptions
- https://docs.swift.org/package-manager/PackageDescription/PackageDescription.html
