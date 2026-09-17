# Uygulama içi wiki

Bu klasördeki sayfalar uygulamanın **Yardım · Wiki** penceresinde gösterilir
(Windows: kontrol paneli, Mac: Yardım sekmesi). Bu README uygulamada görünmez.

## Sayfa biçimi

Her sayfa bir ön bilgi bloğuyla başlar:

```
---
baslik: Hatırlatmalar
turler: bireysel, ozel
platformlar: hepsi
sira: 50
---
```

| Alan | Değerler | Anlamı |
|---|---|---|
| `baslik` | metin | Listede ve sayfa başında görünen ad |
| `turler` | `hepsi` ya da `bireysel`, `sirket`, `ozel` | Sayfanın gösterildiği kurulum türleri |
| `platformlar` | `hepsi` ya da `windows`, `mac` | Sayfanın gösterildiği platformlar |
| `sira` | sayı | Listedeki sıra (küçük önce) |

Sayfanın bir bölümü yalnızca bazı türlerde ya da platformlarda gösterilecekse:

```
<!-- yalniz: bireysel ozel -->
Bu paragraf şirket kurulumunda görünmez.
<!-- /yalniz -->
```

Etiketlerde tür ve platform birlikte kullanılabilir (`<!-- yalniz: windows bireysel -->`):
platform etiketi varsa platform, tür etiketi varsa tür eşleşmelidir. Bloklar iç içe
kullanılabilir: içteki blok yalnızca dıştaki de görünüyorsa görünür. GitHub bu yorumları
göstermez; dosya düz Markdown olarak da okunur.

Desteklenen Markdown: `#`–`###` başlıklar, paragraflar, `-` ve `1.` listeler, `>` not
blokları, tablolar, ``` kod blokları, `**kalın**`, `` `kod` `` ve başka bir sayfaya
bağlantı: `[metin](sayfa-adi)`. Gizli sayfaya giden bağlantı düz metin olarak görünür.

## Mac

Mac uygulaması sayfaları derleme sırasında okuyamaz; içerik
`macos/Sources/TakipCore/WikiIcerik.swift` dosyasına üretilir. Bir sayfayı değiştirince:

```
powershell -NoProfile -ExecutionPolicy Bypass -File macos\scripts\generate-wiki.ps1
```

`hatirlatici\test-ozellikler.ps1` üretilmiş dosyanın güncel olduğunu denetler.
