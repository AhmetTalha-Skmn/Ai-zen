# Tek uygulama raporu

16.09. Soru: Windows ve Mac sürümlerini "tek bir uygulama altında toplamak".

"Tek uygulama" iki anlama gelir:

| Anlam | Durum |
| --- | --- |
| **A. Tek proje / tek ürün:** iki platform aynı depoda, aynı belgeler, aynı sözleşme, aynı CI, tek GitHub deposu | **Yapıldı** (16.09): `macos/` ana depoda, iş akışları kökte, README tek ürün anlatıyor |
| **B. Tek kod tabanı:** iki platformda aynı kaynak koddan derlenen tek uygulama | **Başlanmadı.** Bu rapor seçenekleri ve planı verir |

B şimdi yapılmadı. Engel iş miktarı değil:

1. **Teknoloji seçimi senin kararın.** Her seçenek kurulum, imza ve bakım yükünü değiştirir.
2. **Doğrulanamaz.** Mac olmadan yeniden yazılan bir istemci ancak CI ile derlenir. Ölçüm, izin ve
   uyarı davranışı gerçek Mac ister.
3. **Çalışan Windows sürümünü riske atar.** Canlı takip bu depodan çalışıyor. Yeniden yazım bitene
   kadar eski ve yeni sürüm yan yana yaşamalı.

## Bugünkü yapı

```
Windows istemci + merkez (PowerShell 5.1)   ─┐
                                             ├─ aynı protokol (uyumluluk/) ─ aynı merkeze bağlanır
Mac istemci + merkez (Swift)                ─┘
```

İki uygulama aynı kuralları, aynı sayacı ve aynı merkezi paylaşır. Uyum testlerle korunur:
`uyumluluk/protokol-vektorleri.json` (Windows'ta `test-dagitik`, Mac'te `swift test`) ve Windows
kodundan üretilen `macos/Tests/.../windows-interop.json`.

## Neyi paylaşmak mümkün

| Platformdan bağımsız (tek kodda yazılabilir) | İşletim sistemine bağlı (her platformda ayrı katman) |
| --- | --- |
| Sınıflandırma önceliği, kural eşleşmesi | Ön plan uygulaması: `GetForegroundWindow` / `NSWorkspace` |
| Kurallar, karar kuyruğu, merkez birleştirmesi | Pencere başlığı ve tarayıcı adresi: UI Automation / Erişilebilirlik (AX) |
| Gün, hedef, seri, ortak sayaç hesabı | Boşta süresi: `GetLastInputInfo` / `CGEventSource` |
| Merkez protokolü: imza, eşleşme kodu, anahtar zarfı | Anahtar saklama: DPAPI / Anahtar Zinciri |
| Merkez sunucusu, özet şeması, panel verisi | Arka planda çalışma, açılışta başlama: Görev Zamanlayıcı / LaunchAgent |
| Yedek biçimi ve doğrulaması | Tam ekran uyarı penceresi, menü çubuğu / bildirim alanı |
| Rapor ve CSV | Kurulum, imza: EXE + Akıllı Uygulama Denetimi / .app + Gatekeeper |

Kabaca kodun yarısından fazlası platformdan bağımsız. Zor ve riskli kısım ise sağ sütun: ölçümün
doğruluğu orada.

## Seçenekler

| Seçenek | Artı | Eksi |
| --- | --- | --- |
| **0. İki yerel istemci + ortak sözleşme** (bugünkü) | Çalışıyor; her platform en doğal API'yi kullanır; risk yok | Her özellik iki kez yazılır; iki dil |
| **1. .NET (C#) + Avalonia** | Windows kodu zaten .NET sınıfları kullanıyor (AES, PBKDF2, HMAC, DPAPI, HttpListener, WinForms): mantık neredeyse satır satır taşınır. macOS C API'leri (AX, `CGEventSource`, Keychain `SecItem*`) P/Invoke ile çağrılır. Tek dosya, çalışma zamanı gömülü yayın. | İkili dosya büyük; Avalonia'da menü çubuğu ve tam ekran uyarı ek iş; Mac `.app` paketleme ve noter onayı elle kurulur |
| **2. Tauri 2 (Rust çekirdek + web arayüz)** | Küçük ikili; bildirim alanı / menü çubuğu, açılışta başlatma, güncelleme eklentileri hazır; arayüz HTML/JS (web geçmişine yakın) | Tüm mantık Rust'a yeniden yazılır; iki dil (Rust + JS); Windows UI Automation ile adres okuma Rust'ta zahmetli |
| 3. Electron | Olgun, çok örnek | Ağır; yerel API'ler için Node eklentileri gerekir |
| 4. Swift'i Windows'a taşımak | Mac kodu korunur | Windows'ta arayüz ve sistem API'leri zayıf; önerilmez |
| 5. Flutter masaüstü | Tek arayüz kodu | Arka plan servisi, bildirim alanı ve erişilebilirlik okuması eklentiye bağlı ve zayıf |

**Öneri:**

- **Kısa vadede 0'da kal.** Önce Mac sürümünü gerçek Mac'te doğrula, bilinen hataları kapat.
- **Tek kod tabanı istenirse 1 (.NET + Avalonia).** Windows mantığı en az dönüşümle taşınır, testler (vektörler, uyumluluk verileri) olduğu gibi kullanılır. Mac API'lerinin gereken kısmı C seviyesinde, ObjC köprüsü gerekmez.
- **Arayüzü web teknolojisiyle yazmak öncelikse 2 (Tauri).**

## Plan (seçenek 1 için; 2'de fazlar aynı)

| Faz | İş | Bitti sayılır |
| --- | --- | --- |
| 0. Karar | Teknoloji; imza (kod imzalama sertifikası, Apple Developer ID) alınacak mı; test Mac'i nereden | Kararlar `DEVIR.md`'de |
| 1. Çekirdek | Sınıflandırma, kurallar, sayaç, protokol, merkez mantığı; platform yok | `protokol-vektorleri.json` ve `windows-interop.json` senaryoları yeni çekirdekte yeşil; CI Windows + macOS |
| 2. Platform katmanı | Windows: ön plan, UI Automation adres, boşta, DPAPI, görev. Mac: AX, `CGEventSource`, Keychain, LaunchAgent | Windows'ta mevcut `test-kapsamli` davranışları; Mac kontrol listesi (boşta süresi, başlık, alan adı) |
| 3. Arayüz | Panel, rapor, İncelenecek, merkez paneli, uyarı ekranı ve güvenlik kapıları (3 dk, `DUR`, saatte 6, belirsiz asla engellenmez) | Kapılar için otomatik test + elle deneme |
| 4. Veri ve API | Mevcut `hatirlatici/*.json`, `aktivite/*.csv` ve Mac `state.json` içe aktarımı; `api.ps1` / `mcp.ps1` eşdeğeri (Claude günaydın akışı buna bağlı) | Gerçek verinin **kopyası** üzerinde içe aktarma; MCP araçları aynı yanıtı veriyor |
| 5. Kurulum ve geçiş | Tek dosya kurulum, güncelleme, kaldırma; eski istemciler aynı merkeze bağlı kalırken cihaz cihaz geçiş | Eski ve yeni istemci aynı merkezde birlikte çalışıyor; eski kod `legacy/`e taşınır |

Kaba büyüklük: faz 1-3 her biri birkaç ajan oturumu, faz 4-5 birer iki oturum, artı her fazda gerçek
Mac/Windows deneme günü. Takvim, test Mac'ine erişime bağlı.

## Riskler

- **Ölçüm doğruluğu:** yeni platform katmanı eskisinden farklı sayarsa seri ve hedef geçmişi
  bozulur. Geçişte iki sürüm bir süre aynı makinede paralel ölçülüp karşılaştırılmalı.
- **İmza:** imzasız tek dosya Windows'ta Akıllı Uygulama Denetimi'ne, Mac'te Gatekeeper'a takılır.
  Bugünkü EXE için de geçerli.
- **İzinler:** Mac'te Erişilebilirlik izni her imza değişikliğinde yeniden istenebilir.
- **Canlı sistem:** geçiş bitene kadar `hatirlatici/` ve Görev Zamanlayıcı düzeni bozulmamalı.

## Kısa vadeli sıradaki işler (seçenek 0)

1. CI'ı çalıştır: GitHub'a gönder, `macos.yml` ve `windows.yml` sonucunu gör; derleyicinin
   bulduklarını düzelt.
2. Bilinen Mac hataları (`DEVIR.md`): .NET zaman damgası, ±900 sn, 45 dk hatırlatma, boşta süresi olay
   türü, yazma izni yokken karar kuyruğu, `state.json`'un her 10 sn yeniden yazılması.
3. Gerçek Mac günü: kurulum, izin, ölçüm, uyarı, Windows ↔ Mac canlı eşleşme.
