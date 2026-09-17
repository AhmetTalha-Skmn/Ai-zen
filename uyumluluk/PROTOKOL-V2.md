# Protokol v2 — şifreli zarf, internet ve posta kutusu

> **Durum (17.09):** Windows merkez, Windows istemci ve posta kutusu sunucusu uygulandı ve
> test edildi (`dagitik/test-kanal.ps1`, `posta-sunucusu/test-posta.ps1`). Mac merkez ve istemci
> yazıldı (§8); yalnızca GitHub Actions'ta derlenip sınanır. Bayt bayt uyum için sabit değerler
> `protokol-vektorleri.json` içindeki `zarfV2` ve `kayitV2` bölümlerinde.

## 1. Neden

v1 (`/v1/*`) yerel ağ için tasarlandı: istekler HMAC ile imzalı ama **şifresiz**, kayıtta eşleşme
kodu ağa **düz** gider. İnternete açılırsa kod ve özetler yolda okunur. v2 bunu kapatır ve üç
bağlantı yolunu aynı zarfla destekler:

| Yol | Ne zaman | Merkez nasıl ulaşılır |
|---|---|---|
| Doğrudan, yerel ağ | Aynı ofis / VPN | `http://192.168.1.20:8787` |
| Doğrudan, internet | Modemde port yönlendirme yapılabiliyorsa | `http://alanadi:8787` (dinamik DNS) |
| Posta kutusu | Port açılamıyorsa (CGNAT, mobil hat, yetki yok) | `https://posta.firma.com/k/<kutu>` |

Posta kutusu kiralık bir Linux sunucuda çalışan küçük bir aracıdır (`posta-sunucusu/`). Cihazlar
zarflarını bırakır, merkez bilgisayarı açıldığında alır, yanıtları bırakır. **Zarfları açamaz**:
elinde cihaz anahtarı yoktur, yalnızca erişim jetonlarının SHA-256 özetlerini saklar.

## 2. Anahtarlar

### 2.1 Kayıtlı cihaz

Cihaz anahtarı `K` (32 bayt) kayıtta merkezde üretilir, iki tarafta da işletim sisteminin anahtar
deposunda durur (Windows DPAPI, macOS Anahtar Zinciri).

```
sifre       = HMAC-SHA256(K, UTF8("Aizen|v2|sifre"))
imza        = HMAC-SHA256(K, UTF8("Aizen|v2|imza"))
postaJetonu = hex(HMAC-SHA256(K, UTF8("Aizen|v2|posta")))      küçük harf, 64 karakter
```

### 2.2 Kayıt (eşleşme kodu)

```
normal   = kod normalleştirmesi (v1 ile aynı: büyük harf, 0-9A-Z dışı silinir, I/L→1, O→0)
ana      = PBKDF2-HMAC-SHA256(UTF8(normal), UTF8("Aizen|kayit|v2"), 120000, 32 bayt)
kanal    = "k-" + ilk 24 hex(HMAC-SHA256(ana, UTF8("Aizen|kayit|v2|kimlik")))
sifre    = HMAC-SHA256(ana, UTF8("Aizen|kayit|v2|sifre"))
imza     = HMAC-SHA256(ana, UTF8("Aizen|kayit|v2|imza"))
postaJetonu = hex(HMAC-SHA256(ana, UTF8("Aizen|kayit|v2|posta")))
```

- Merkez kod üretilirken `kanal`, DPAPI ile korunmuş `ana` ve `SHA256(postaJetonu)` saklar; kodun
  kendisini saklamaz. Kayıt tamamlanınca `ana` silinir (tek kullanımlık). v1 alanları
  (`kayitTuzu`, `kayitOzeti`) aynı anda silinir: kod iki protokolde birden tükenir.
- 12 karakterlik kod 60 bit; yakalanan bir kayıt zarfından kodu çıkarmak için 2^60 × 120000
  PBKDF2 turu gerekir.
- `k-` + 24 hex biçimi cihaz kimliklerine kapalıdır (`cihaz-ekle.ps1` reddeder).

## 3. Zarf

```json
{"v":2,"cihaz":"test-pc","tur":"ozet","yon":"istek","sayac":42,"zaman":1757980800,
 "iv":"<base64 16 bayt>","veri":"<base64>","etiket":"<base64 32 bayt>"}
```

| Alan | Kural |
|---|---|
| `v` | tam sayı 2 |
| `cihaz` | `^[A-Za-z0-9_-]{3,64}$` (kayıtta `kanal`) |
| `tur` | `^[a-z]{2,16}$`: `kayit`, `ozet`, `kural`, `kurallar`, `toplam` |
| `yon` | `istek` ya da `yanit` |
| `sayac`, `zaman` | JSON **tam sayı** (metin ya da ondalık geçersiz), 0–15 hane; `zaman` Unix saniye |
| `iv`, `veri`, `etiket` | standart base64 |

```
veri   = AES-256-CBC-PKCS7(sifre, iv, UTF8(metin))
girdi  = UTF8("AIZEN-ZARF-2\n" + cihaz + "\n" + tur + "\n" + yon + "\n" + sayac + "\n" + zaman + "\n" + iv + "\n" + veri)
etiket = HMAC-SHA256(imza, girdi)
```

- `sayac` ve `zaman` girdiye ondalık metin olarak (kültürden bağımsız, baştaki sıfırsız) yazılır;
  `iv` ve `veri` ağa giden base64 metnin **aynısıdır**.
- Açarken önce `etiket` sabit zamanlı doğrulanır; tutmazsa çözme **denenmez**.
- Başlık alanları imzanın içindedir: sayacı, türü, yönü ya da cihazı değiştirilmiş zarf reddedilir;
  istek zarfı yanıt diye geri yansıtılamaz.

### 3.1 İçerik

| `tur` | İstek metni | Yanıt metni (`govde`) |
|---|---|---|
| `ozet` | v1 özet paketi (şema 1) | v1 `/v1/ozet` yanıtı |
| `kural` | `{schemaVersion:1, cihazId, kararlar}` | v1 `/v1/kural` yanıtı |
| `kurallar` | `{}` | v1 `/v1/kurallar` yanıtı |
| `toplam` | `{tarih:"yyyy-MM-dd"}` | v1 `/v1/toplam` yanıtı |
| `kayit` | `{schemaVersion:2, onay:true, cihazAdi, kullanici, surum}` | aşağıda |

Yanıt metni her zaman `{"kod": <HTTP benzeri durum>, "govde": {...}, "adresler": {...}}`.
`kod` v1'in HTTP durumudur (ör. izinsiz kural yazımı 403); zarfın kendisi 200 ile döner.
`adresler = {sunucuUrl, ekAdresler[], postaUrl}`: merkezin güncel adresleri. İstemci bunlarla
adres listesini günceller; posta kutusu sonradan eklense de cihazlar yeniden eşleşmeden öğrenir.
Merkezin döngü adresi (`127.*`, `localhost`) başka bilgisayarda anlamsız olduğu için alınmaz.

Kayıt yanıtının `govde`si: `{ok, cihazId, cihazAdi, anahtar (base64 K), sunucuUrl, ekAdresler,
postaUrl, gonderimDakikasi, ayrintiDuzeyi, veriAciklamasi}`. Cihaz anahtarı yalnızca bu şifreli
yanıtın içinde yol alır.

Yanıt zarfı isteğin `cihaz`, `tur` ve `sayac` değerlerini taşır, `yon = yanit`. Doğrudan bağlantıda
istemci bu üçünün isteğiyle aynı olduğunu denetler.

## 4. Tekrar ve zaman

- **Zaman:** merkez `zaman > şimdi + 900` ya da `zaman < şimdi − 30 gün` olan zarfı reddeder (401).
  Posta kutusunda günlerce bekleyen zarf geçerlidir; v1'in ±900 sn kuralı v2'de yalnız gelecek yönünde.
- **Sayaç:** istemci her zarfta bir artırır ve **göndermeden önce diske yazar**. Kayıtta 0'dan başlar.
- **`kural` (durum değiştiren):** merkez cihaz başına kayan pencere tutar (1024). Pencerenin
  gerisindeki ya da daha önce görülmüş sayaç 409 alır. Pencere içinde geç gelen zarf kabul edilir
  (doğrudan ve posta kutusu karışık kullanıldığında sıra bozulabilir).
- **`ozet`, `kurallar`, `toplam`:** tekrarı zararsızdır; yinelenen özet v1'deki bayat paket
  kuralıyla atlanır, okuma yanıtı yalnızca cihazın açabileceği biçimde şifrelidir.
- **Posta kutusundan gelen yanıtlar:** istemci tür başına işlediği en büyük sayacı tutar; eski
  yanıt yenisinin etkisini (ör. eski kural kümesi) geri alamaz.

## 5. Doğrudan bağlantı (merkez)

| Uç | Açıklama |
|---|---|
| `GET /health` | `{ok, zamanUtc, protokol:2}`. İstemci v2 desteğini buradan anlar. |
| `POST /v2/zarf` | Gövde zarf (en çok 1 MB). 200 → yanıt zarfı. Hata gövdesi düz `{ok:false, hata}`. |

Durumlar: 400 biçim, 401 zaman/kimlik/imza, 403 kayıt kodu geçersiz/kullanılmış, 409 tekrar,
413 boyut, 429 adres başına 10 dakikada 30 hatalı deneme.

**v1 uçları yalnızca yerel adreslerden** (loopback, 10/8, 172.16/12, 192.168/16, 169.254/16,
100.64/10, IPv6 ULA ve link-local) kabul edilir; diğerlerine 403. Eski istemciler yerel ağda ve
VPN'de çalışmaya devam eder, internete açılan merkez kodu düz metin kabul etmez.

Eski merkezle uyum: istemci önce `/v2/zarf` dener; doğrudan adreste 404 alırsa (yalnızca v1 bilen
merkez) v1 kaydına düşer ve `merkez.json`'a `protokol` yazmaz.

## 6. Posta kutusu sunucusu (`/r1`)

Başlıklar: `X-Aizen-Kutu` (16–64 hex), merkez için `X-Aizen-Jeton` (64 hex), cihaz için ayrıca
`X-Aizen-Cihaz`. Sunucu `SHA256(jeton)` ile sabit zamanlı karşılaştırır.

| Uç | Kim | Açıklama |
|---|---|---|
| `GET /saglik` | herkes | `{ok, hizmet:"aizen-posta", surum:1}` |
| `POST /r1/kutu` | yönetim jetonu (`X-Aizen-Yonetim`) | `{kutu, merkezJetonOzeti}`: kutu oluştur ya da merkez jetonunu yenile (cihaz listesi korunur) |
| `POST /r1/merkez/cihazlar` | merkez | `{cihazlar:[{cihaz, jetonOzeti, bitis}]}` listeyi değiştirir; `bitis` Unix sn, 0 = süresiz |
| `GET /r1/merkez/gelen?en=N` | merkez | en eski N (1–100) mesaj: `{no, cihaz, anahtar, alindi, zarf}` |
| `POST /r1/merkez/onay` | merkez | `{nolar:[...]}` işlenenleri siler |
| `POST /r1/merkez/gonder` | merkez | `{mesajlar:[{cihaz, anahtar, zarf}]}` yanıtları cihaz kutularına koyar |
| `POST /r1/cihaz/gonder` | cihaz | `{anahtar, zarf}`; `zarf.cihaz` başlıktakiyle aynı, `yon = istek` olmalı |
| `GET /r1/cihaz/gelen` | cihaz | yalnızca kendi yanıtları (en çok 50) |
| `POST /r1/cihaz/onay` | cihaz | `{nolar}` kendi yanıtlarını siler |

- **Birleştirme anahtarı** (`^[a-z0-9-]{0,40}$`): aynı cihazdan aynı anahtarlı bekleyen mesaj
  yenisiyle değişir. İstemci özette `ozet-<gün>`, okumalarda `kurallar` / `toplam` kullanır; kural
  kararları ve kayıt birleştirilmez. Merkez kapalıyken kutu, cihaz başına birkaç mesajla sınırlı kalır.
- **Sınırlar:** gövde 1,5 MB; cihaz başına bekleyen 200 mesaj (429); kutu başına 20 000;
  30 günden eski mesaj silinir; adres başına 10 dakikada 60 hatalı kimlik (429; ters vekil
  arkasında `X-Forwarded-For`'un son öğesi).
- **Kayıt:** merkez bekleyen kodun `kanal`ını ve `SHA256(postaJetonu)`'nu kod süresince listeye
  koyar; kayıt tamamlanınca kanal yanıt alınabilsin diye 30 dakika daha tanımlı kalır. Merkez
  kayıt beklerken kutuyu 5 saniyede bir yoklar.
- Jetonlar ağda yalnızca HTTPS ile gider: istemci ve merkez `http://` posta adresini yalnızca
  bu bilgisayar (`127.0.0.1`, `localhost`, `[::1]`) için kabul eder.

## 7. İstemci davranışı (her 5 dakikalık tur)

1. `sunucuUrl` ve `ekAdresler` sırayla `GET /health` (4 sn) ile denenir; `protokol ≥ 2` yanıt veren
   ilk adres kullanılır.
2. Doğrudan: kuyruktaki özetler, bekleyen kural kararları, `kurallar`, `toplam`. Tur ortasında ağ
   hatası olursa kalanlar posta kutusuna gider.
3. Posta kutusu: önce önceki turların yanıtları alınır ve onaylanır; sonra özetler (`ozet-<gün>`),
   kararlar, `kurallar` ve `toplam` istekleri bırakılır. Kuyruktaki özet ancak kutu kabul edince silinir.
4. `ortak-sayac.json` tazeliği merkezin yanıt zarfındaki `zaman`dan ölçülür (posta gecikmesi
   bayat toplamı taze göstermesin).

`merkez.json` (v2): `protokol:2`, `sunucuUrl` (boş olabilir), `ekAdresler[]`, `postaUrl`, `sayac`,
`sonKanal` (`dogrudan`/`posta`), `postaSonYanit {tur: sayac}`, `postaYanitBekleniyor`.

## 8. Mac

| Parça | Dosya |
|---|---|
| Adres ayrıştırma ve adres birleştirme | `macos/Sources/TakipCore/Address.swift` (`CenterAddress`) |
| Alt anahtarlar, kayıt anahtarları, zarf | `Crypto.swift` (`Zarf`, `ZarfKeys`) |
| v2 kayıt (doğrudan / posta kutusu, eski merkezde v1), gönderim yardımcıları | `Client.swift` |
| Kanal seçimi, doğrudan ve posta kutusu turu | `Engine.swift` (`syncV2`) |
| `/v2/zarf`, v1 yerel adres kısıtı, sayaç penceresi, posta kutusu yoklaması | `Center.swift`, `HTTPServer.swift` (karşı adres) |
| Arayüz: aktarım durumu, merkezde "Farklı ağlardaki cihazlar" | `App.swift` |

Mac merkezi v2 kayıt anahtarını Anahtar Zinciri'nde `center-enroll:<cihaz>`, posta kutusu
merkez jetonunu `center-mailbox` hesabında tutar. Mac merkezinin istemcilere bildirdiği yerel adres
LAN açıkken makinenin ilk özel IPv4 adresidir.

Testler: `WindowsInteropTests.testWindowsProtocolV2EnvelopeVectors` (vektörleri birebir üretir),
`AppTests.testCenterV2EnvelopeFlowAndLocalOnlyV1` (kayıt, özet, izin, tekrar, eski zaman, v1 kısıtı),
`CoreTests` adres ayrıştırma. Mac istemcisinin gerçek ağ trafiği (doğrudan ve posta kutusu) CI'da
sınanmaz; protokol uyumu vektörlerle, uçtan uca akış Windows tarafında `test-kanal.ps1` ile sınanır.
