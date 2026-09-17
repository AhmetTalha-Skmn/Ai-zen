# Aizen posta kutusu sunucusu

Merkez bilgisayarı ile çalışan bilgisayarlar **farklı ağlardaysa** ve merkezin modeminde port
yönlendirme yapılamıyorsa (CGNAT, mobil hat, modeme erişim yok) bu sunucu aradaki posta kutusudur:

```
çalışan bilgisayar ──(şifreli zarf)──▶ posta kutusu ◀──(yoklar, 1 dk)── merkez bilgisayarı
                   ◀──(yanıtı alır)───              ──(yanıt bırakır)──▶
```

- Çalışan bilgisayarlar 5 dakikada bir özetlerini bırakır. Merkez kapalıysa zarflar bekler;
  merkez açılınca hepsini alır. Aynı günün eski özeti kutuda yenisiyle değişir, birikmez.
- Sunucu **zarfları açamaz**: cihaz anahtarını bilmez, yalnızca erişim jetonlarının SHA-256
  özetlerini saklar. Sunucuyu ele geçiren biri özetleri, kodları, kuralları okuyamaz ve
  değiştiremez; en fazla iletimi durdurabilir. Protokol: `uyumluluk/PROTOKOL-V2.md`.
- Modemde port açabiliyorsan bu sunucuya gerek yok: merkezde
  `.\ana-kurulum.ps1 -Kur -InternetUrl http://alanadi:8787` yeterli.

## Ne gerekir

| | |
|---|---|
| Kiralık sunucu (VPS) | 1 vCPU, 1 GB RAM, Ubuntu 24.04 LTS yeterli |
| Alan adı | `posta.firma.com` gibi bir ad; DNS **A** kaydı sunucunun IP adresini göstermeli |
| Açık portlar | 22 (SSH), 80 ve 443 (HTTPS sertifikası ve bağlantı) |

HTTPS zorunludur: istemci ve merkez posta kutusuna `http://` ile bağlanmayı reddeder.

## Kurulum (Ubuntu 24.04)

Komutları sunucuya SSH ile bağlanıp sırayla çalıştır.

### 1. Sistem ve güvenlik duvarı

```bash
sudo apt update && sudo apt upgrade -y
sudo ufw allow OpenSSH
sudo ufw allow 80,443/tcp
sudo ufw enable
```

### 2. PowerShell 7

```bash
sudo snap install powershell --classic
command -v pwsh
```

Çıkan yol (`/snap/bin/pwsh` ya da `/usr/bin/pwsh`) 5. adımda gerekir.

### 3. Kullanıcı, klasörler ve betik

```bash
sudo useradd --system --home /var/lib/aizen-posta --shell /usr/sbin/nologin aizen-posta
sudo install -d -o aizen-posta -g aizen-posta -m 700 /var/lib/aizen-posta
sudo install -d -m 755 /opt/aizen-posta
sudo curl -fsSL -o /opt/aizen-posta/posta-sunucu.ps1 \
  https://raw.githubusercontent.com/AhmetTalha-Skmn/Ai-zen/main/posta-sunucusu/posta-sunucu.ps1
sudo chmod 644 /opt/aizen-posta/posta-sunucu.ps1
```

İnternetten indirmek istemezsen dosyayı kendi bilgisayarından kopyala:
`scp posta-sunucusu/posta-sunucu.ps1 kullanici@sunucu:/tmp/` ve
`sudo install -m 644 /tmp/posta-sunucu.ps1 /opt/aizen-posta/`.

### 4. Yönetim jetonu (bir kez)

```bash
sudo -u aizen-posta env HOME=/var/lib/aizen-posta pwsh -NoProfile -File /opt/aizen-posta/posta-sunucu.ps1 \
  -VeriKlasoru /var/lib/aizen-posta -YonetimJetonuUret
```

Çıkan jetonu bir parola gibi sakla; merkez bilgisayarını bağlarken bir kez istenir. Sunucu
jetonun kendisini değil özetini saklar; kaybolursa aynı komutla yenisi üretilir (eski geçersiz olur,
kurulu kutular çalışmaya devam eder).

### 5. Hizmet

```bash
sudo curl -fsSL -o /etc/systemd/system/aizen-posta.service \
  https://raw.githubusercontent.com/AhmetTalha-Skmn/Ai-zen/main/posta-sunucusu/aizen-posta.service
# pwsh yolu /usr/bin/pwsh değilse ExecStart satırını düzelt:
sudo nano /etc/systemd/system/aizen-posta.service
sudo systemctl daemon-reload
sudo systemctl enable --now aizen-posta
sudo systemctl status aizen-posta
curl -s http://127.0.0.1:8790/saglik
```

Snap ile kurulan `pwsh` sıkı sertleştirmeyle açılmazsa (`status` hata gösterir) önce
`ProtectSystem=strict` satırını `ProtectSystem=full` yap, `daemon-reload` ve `restart`.

### 6. HTTPS (Caddy)

```bash
sudo apt install -y caddy
sudo curl -fsSL -o /etc/caddy/Caddyfile \
  https://raw.githubusercontent.com/AhmetTalha-Skmn/Ai-zen/main/posta-sunucusu/Caddyfile.ornek
sudo nano /etc/caddy/Caddyfile          # posta.firma.com yerine kendi alan adın
sudo systemctl reload caddy
curl -s https://posta.firma.com/saglik
```

Son komut `{"ok":true,"hizmet":"aizen-posta",...}` döndürmeli. Caddy sertifikayı kendisi alır ve
yeniler. Örnek dosyada erişim günlüğü bilerek kapalıdır (Caddy istek başlıklarını, yani jetonları
yazardı).

## Merkez bilgisayarını bağlama

Merkez bilgisayarında (Aizen kurulum klasöründe):

```powershell
cd dagitik
.\posta-baglan.ps1 -PostaUrl https://posta.firma.com
```

Yönetim jetonunu sorar (yazarken görünmez). Çıktıdaki adres çalışanların gireceği adrestir:

```
Farkli agdaki cihazlar icin adres: https://posta.firma.com/k/3f9a...
```

- `cihaz-ekle.ps1` bundan sonra kodla birlikte bu adresi de gösterir.
- Daha önce kayıtlı (v2) cihazlar adresi merkeze bir sonraki doğrudan bağlantılarında şifreli
  yanıtla öğrenir; yeniden eşleştirmek gerekmez.
- Durum: `.\posta-baglan.ps1 -Durum` · Kapatmak: `.\posta-baglan.ps1 -Kapat`
- Merkez sunucusu (Görev Zamanlayıcı: *Calisma Takip Merkezi*) çalıştığı sürece kutuyu dakikada
  bir yoklar; kayıt bekleyen kod varken 5 saniyede bir.

## Çalışan bilgisayar

Kurulum sihirbazında **Merkez adresi** alanına posta kutusu adresi, **Eşleşme kodu** alanına
yöneticinin verdiği kod girilir. Kayıt sırasında merkez bilgisayarı açık olmalıdır (en çok 2,5
dakika beklenir). Sonrasında merkez kapalı da olsa özetler kutuda bekler.

Aynı bilgisayar ofise dönünce merkezin yerel adresine doğrudan bağlanır; dışarıdayken kutuyu
kullanır. Seçim her 5 dakikalık turda kendiliğinden yapılır.

## Bakım

| İş | Komut |
|---|---|
| Günlük | `sudo journalctl -u aizen-posta -n 100` ve `/var/lib/aizen-posta/posta.log` |
| Güncelleme | 3. adımdaki `curl` ile betiği yenile, `sudo systemctl restart aizen-posta` |
| Yedek | Gerekmez: kutudaki zarflar geçicidir. `ayar.json` ve `kutular/*/kutu.json` kaybolursa yönetim jetonunu yeniden üret, merkezde `posta-baglan.ps1`'i tekrar çalıştır. |
| Saklama | 30 günden eski, alınmamış mesajlar kendiliğinden silinir |

Sınırlar: istek gövdesi 1,5 MB, cihaz başına bekleyen 200 mesaj, adres başına 10 dakikada 60
hatalı kimlik denemesi (sonra 10 dakika 429).

## Test

```powershell
pwsh posta-sunucusu/test-posta.ps1          # Linux / PowerShell 7
powershell -File posta-sunucusu\test-posta.ps1   # Windows PowerShell 5.1
```

GitHub Actions'ta Ubuntu üzerinde her değişiklikte çalışır (`.github/workflows/posta.yml`).
Uçtan uca akış (Windows merkez + istemci + bu sunucu) `dagitik/test-kanal.ps1` içindedir.
