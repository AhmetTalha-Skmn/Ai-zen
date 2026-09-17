---
baslik: Ayarlar
turler: hepsi
platformlar: hepsi
sira: 40
---
# Ayarlar

<!-- yalniz: windows -->
Kontrol panelindeki **Ayarlar** düğmesi ayarlar penceresini açar. Günlük hedef ve
duraklatma kontrol panelinden de değişir.
<!-- /yalniz -->
<!-- yalniz: mac -->
Ayarlar, paneldeki **Ayarlar ve yedek** sekmesindedir.
<!-- /yalniz -->

## Kurulum türü

Bu bilgisayarın türünü gösterir: Bireysel, Şirket ya da Özel. Ne anlama geldiği:
[Kurulum türleri](kurulum-turleri).

<!-- yalniz: bireysel ozel -->
## Hatırlatmalar

Açıkken, bugün hedefin altındaysan ve 45 dakikadır çalışma ölçülmüyorsa uyarı çıkar.
<!-- yalniz: windows -->
Hedef tutulunca bir kez mesaj gösterilir.
<!-- /yalniz -->
Kapatınca ölçüm ve rapor aynen sürer, yalnızca uyarılar çıkmaz. Ayrıntı:
[Hatırlatmalar](hatirlatmalar).
<!-- /yalniz -->
<!-- yalniz: sirket -->
## Hatırlatmalar

Şirket kurulumunda hatırlatma yoktur. Ölçüm, rapor ve günlük hedef çalışmaya devam eder.
<!-- /yalniz -->

## Ekran kilidi

<!-- yalniz: windows -->
Açıkken çalışma periyodunda izinsiz bir uygulama açılınca ekranı kaplayan bir engel
çıkar.
<!-- /yalniz -->
<!-- yalniz: mac -->
Açıkken odak oturumunda izinsiz bir uygulama öne gelince ekranı kaplayan bir uyarı çıkar.
<!-- /yalniz -->
<!-- yalniz: bireysel ozel -->
Hatırlatma uyarıları da tam ekran olur.
<!-- /yalniz -->
Kapalıyken hiçbir pencere ekranı kaplamaz ve engelleme yapılmaz.
Ayrıntı: [Ekran kilidi ve odak](ekran-kilidi-ve-odak).

## Varsayılana dön

Hatırlatma ve ekran kilidi seçimlerini siler; kurulumda seçilen değerler ya da türün
varsayılanı geçerli olur. Günlük hedef ve diğer ayarlar değişmez.

## Günlük hedef ve duraklatma

<!-- yalniz: windows -->
- **Günlük hedef**: 15–720 dakika arası.
<!-- /yalniz -->
<!-- yalniz: mac -->
- **Günlük hedef**: 1–1440 dakika arası.
<!-- /yalniz -->
- **Duraklat**: süre boyunca uyarı çıkmaz, sayaç ilerlemez, aktivite kaydı tutulmaz.
  Takip **Sürdür** ile hemen döner.

<!-- yalniz: windows -->
## Ayarlar nerede saklanır

`hatirlatici\ayarlar.json`:

| Anahtar | Anlamı |
|---|---|
| `hedef` | Günlük hedef (dakika) |
| `duraklat` | Duraklatma bitişi, `sonsuz` ya da boş |
| `hatirlatmalar` | `true` / `false`; yoksa kurulumdaki seçim |
| `ekranKilidi` | `true` / `false`; yoksa kurulumdaki seçim |
| `yedekKlasoru` | İsteğe bağlı yedek hedefi |

Öncelik sırası: `ayarlar.json` → `dagitik\kurulum-bilgisi.json` → türün varsayılanı.
Ayar penceresi dosyadaki tanımadığı alanları korur.
<!-- /yalniz -->
