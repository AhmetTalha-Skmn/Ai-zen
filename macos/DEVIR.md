# Mac ek paket devir defteri

> **Tarihçe.** 16.09'dan beri Mac kodu ana deponun `macos/` klasöründedir; güncel devir kaydı ve açık işler kökteki `DEVIR.md`'dedir. Bu dosyaya yeni kayıt eklenmez.

## 2026-09-16 (2) — Claude: GitHub Actions ve Windows uyumluluk testleri

- Kullanıcı isteği: Mac olmadan test için birinci katman. Codex'in mevcut kaynak, test ve betik dosyalarına dokunulmadı; yalnız yeni dosya eklendi.
- `.github/workflows/macos.yml`: macOS 15 makinesinde `swift build`, `swift test`, `bash scripts/build.sh`.
- `scripts/generate-windows-interop.ps1`: fixture'ları gerçek Windows kodundan üretir (Windows deposuna yazmaz; satır içi Windows ifadeleri değişirse durur). Üretilen: `Fixtures/windows-interop.json` (Windows commit b83a466), `Fixtures/windows-vectors.json`.
- `Tests/CalismaTakipTests/WindowsInteropTests.swift`: Windows istemcisinin gerçek kayıt/özet/kural istekleri Mac merkezine; Windows merkezinin kural/kayıt/toplam yanıtları Mac istemcisine; Windows protokol vektörleri. Beklenen sonuç Windows davranışıdır.
- `SUREKLI-TEST.md`: kullanım, GitHub'a gönderme, ilk çalıştırmada beklenen kırmızılar.
- Doğrulama: üretici Windows'ta çalıştı, fikstürler çözülüp elle incelendi. Swift testleri burada derlenemedi; ilk hakem CI.
- İncelemede bulunanlar (düzeltilmedi, kullanıcı kararı bekliyor): olası 3 derleme hatası (`App.swift:17` autoclosure içinde `try`, `State` adının SwiftUI ile çakışması, `Engine.swift:25`), Mac merkezinin .NET yedi basamaklı zaman damgasını reddetme riski (`Center.swift:173-174`), ±300/±900 sn farkı (`Center.swift:121`), 45 dk hatırlatmanın çalışırken de çıkması (`Engine.swift:126`; Windows yalnız aktif değilken uyarır), boşta süresi için `.null` olay türü (`Activity.swift:56`; `kCGAnyInputEventType` beklenir), yazma izni yokken karar kuyruğunun hiç boşalmaması ve 200'de kilitlenmesi (`Engine.swift:70`, `170-181`), her 10 sn tüm `state.json`'un yeniden yazılması (`Engine.swift:112`).
- `PAKET-MANIFEST.json` yeni test dosyalarını içermiyor; `node scripts/package.mjs` yeniden çalışınca güncellenir (bu ortamda Node yok).

## 2026-09-16 — Codex: bağımsız Mac kaynak paketi

- Kullanıcının son yönlendirmesiyle Mac’e yerel takip, istemci ve merkez sunucu rolleri birlikte eklendi.
- SwiftUI menü/panel, Erişilebilirlik ölçümü, nötr kurallar, odak uyarısı, rapor/CSV, yerel yedek/geri yükleme, Keychain, cihaz kaydı/yetkisi ve ortak kurallar yazıldı.
- Kurulum/güncelleme/kaldırma tek Mac betiğinde; kullanıcı verileri uygulama paketinin dışında korunur.
- 14 çalışan Windows/protokol kontrolü geçti; Swift sözdizimi ve betik kontrolleri geçti. 22 Swift test metodu eklendi ama macOS ortamı olmadığı için henüz çalıştırılmadı.
- Windows ana projesi ve ana DEVIR.md değiştirilmedi. Kaynak kaydı bu ayrı çalışma alanında [codex] önekli commit ile tutulur.
- Sıradaki iş: gerçek Mac’te swift test, release derlemesi, arayüz/izin/kurulum ve Windows-Mac ağ kabulü. Ayrıntılar DOGRULAMA.md ve GELISTIRICI-NOTLARI.md içinde.
