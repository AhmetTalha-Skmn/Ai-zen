# Sürekli test — GitHub Actions

Mac olmadan derleme ve test için. İş akışları depo kökündedir (`.github/workflows/`); GitHub alt
klasördeki iş akışlarını okumaz.

| İş akışı | Ne zaman | Adımlar |
| --- | --- | --- |
| `macos.yml` | `macos/` değişince | `swift build` → `swift test` → `bash scripts/build.sh` (Kur.command'ın yolu: release derleme, `plutil`, ad hoc imza) |
| `windows.yml` | `hatirlatici/`, `dagitik/`, `uyumluluk/`, `posta-sunucusu/` değişince | `dagitik\test-dagitik.ps1` (v2 zarf ve posta kutusu uçtan uca dahil), bir kez makinenin kültüründe, bir kez tr-TR kültüründe |
| `posta.yml` | `posta-sunucusu/` değişince | Ubuntu'da PowerShell 7 ile `posta-sunucusu/test-posta.ps1` (VPS'teki çalışma ortamı) |

Sonuç GitHub'da deponun **Actions** sekmesinde görünür. Elle çalıştırmak için iş akışı sayfasında
**Run workflow** var.

## Neyi yakalar, neyi yakalamaz

| Yakalar | Yakalamaz |
| --- | --- |
| Derleme hataları | Menü çubuğu ve arayüz |
| Birim testleri, kripto uyumu | Erişilebilirlik izni ve gerçek ölçüm |
| Windows istemcisinin gerçek istekleri Mac merkezinde | Boşta süresi (`CGEventSource`) |
| Windows merkezinin gerçek yanıtları Mac istemcisinde | Gerçek ağ, uyku, login item |
| Türkçe kültüre bağlı Windows hataları (tr-TR adımı) | Windows canlı kurulum testleri (`test.ps1`, `test-api`, `test-kapsamli`) |

Yakalamadıkları gerçek bir Mac'te (ve kurulu Windows'ta) elle sınanır.

## Windows uyumluluk testleri

`Tests/CalismaTakipTests/WindowsInteropTests.swift`, `Fixtures/windows-interop.json` ve
`Fixtures/windows-vectors.json` dosyalarını okur. Bu dosyalar elle yazılmaz; gerçek Windows
kodundan üretilir (Windows deposu varsayılan olarak `macos/`'un üst klasörüdür):

    powershell.exe -NoProfile -ExecutionPolicy Bypass -File macos/scripts/generate-windows-interop.ps1

Üretici Windows dosyalarına yazmaz. `New-GunlukOzet`, kural kuyruğu, merkez kural kütüphanesi,
`Merge-YerelKurallar` ve `Protect-DagitikKodIle` olduğu gibi çalışır. Windows betiklerinde satır
içi duran birkaç istek/yanıt ifadesi üreticide kopyalıdır; bu satırlar Windows'ta değişirse üretici
çalışmayı reddeder.

`windows-vectors.json`, `uyumluluk/protokol-vektorleri.json`'un satır sonu LF yapılmış kopyasıdır
(v1 imza/kod vektörleri ve protokol v2 `zarfV2`/`kayitV2`). Yalnızca vektörler değiştiyse üreticinin
son adımı yeterlidir; dosyayı elle düzenleme.

Kayıt yanıtı rastgele IV taşır: her yeniden üretim bu alanı ve `windowsCommit`'i değiştirir.
Yalnızca Windows istek/yanıt biçimi değiştiğinde yeniden üret ve commit et.

Testler Windows'un davranışını bekler. Bir test kırmızıysa ya Mac kodu Windows'tan ayrılmıştır ya
da Windows bilerek değişmiştir; ikincisinde fixture yeniden üretilir.

## Durum (16.09)

- İncelemede öngörülen üç derleme hatası düzeltildi: `App.swift` içinde `StateObject` kapanışında
  `try`; SwiftUI `@State` ile çakışan `State` model adı (`TrackerState` oldu, JSON değişmedi);
  `Engine.init` içinde tüm alanlar atanmadan `state` okunması.
- Önleyici düzeltmeler: `Wire.body` açık tipli parçalara bölündü (tür çıkarımı zaman aşımı riski),
  `label.contains` açık kapanış oldu (aşırı yükleme belirsizliği), görünümler `@MainActor` (Xcode 15
  SDK), `Storage` saf yardımcıları `nonisolated`, `Binding(set:)` yöntem referansı kapanış oldu.
- İlk CI çalışması henüz yapılmadı; derleyici başka hata da bulabilir.
- Derleme geçince kırmızı kalması beklenen iki Windows testi (bilinen Mac hataları, düzeltilmedi):
  `testWindowsDailySummaryWithDotNetTimestampIsAccepted` (yedi basamaklı saniye kesri) ve
  `testClockSkewToleranceMatchesWindowsCenter` (Windows ±900 sn, Mac merkezi ±300 sn).

## GitHub'a gönderme

Tek depo gönderilir. `araclar/github-disa-aktar.ps1` kişisel dosyaları çıkarılmış anlık görüntüyü
iş akışlarıyla birlikte üretir; görüntü klasöründen `git push` yapılır. Eski ayrı klasör
(`Documents/ChatGPT/New project`) ve oradaki `github-macos` dalı artık kullanılmaz.

Gizli depoda macOS dakikaları ücretsiz kotadan Linux'a göre çok daha hızlı düşer. Aynı dala art
arda gönderimde eski çalışma iptal edilir; iş akışları yalnız ilgili klasör değişince tetiklenir.
