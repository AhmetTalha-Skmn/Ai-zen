<#
Dagitik protokol icin sabit test vektorleri (capraz platform uyumu).

Baska bir platformdaki (ornegin macOS) istemci ya da merkez, protokol-vektorleri.json
icindeki degerleri birebir uretmeli / cozmelidir; yoksa Windows merkeziyle eslesemez,
imzali istekleri 401 alir. Bu betik ayni dosyayi Windows koduyla dogrular; boylece
Windows tarafinda protokol kazara degisirse test-dagitik.ps1 kirmizi yanar.

  .\uyumluluk\protokol-vektorleri.ps1          # dogrula (cikis 0 / 1)
  .\uyumluluk\protokol-vektorleri.ps1 -Uret    # json'u yeniden uret (yalniz protokol BILEREK degistiyse)
#>
param([switch]$Uret)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\dagitik\Ortak.ps1')
$jsonYolu = Join-Path $PSScriptRoot 'protokol-vektorleri.json'

function Get-SiraliBayt {
    param([int]$Bas, [int]$Adet)
    $b = New-Object byte[] $Adet
    for ($i = 0; $i -lt $Adet; $i++) { $b[$i] = [byte]($Bas + $i) }
    return ,$b
}

function ConvertTo-Hex {
    param([byte[]]$Bayt)
    return ([BitConverter]::ToString($Bayt)).Replace('-', '').ToLowerInvariant()
}

function New-V2Vektorleri {
    # Protokol v2 (PROTOKOL-V2.md): sabit anahtar, IV ve zamanla uretilen zarflar birebir tekrar uretilebilmeli.
    $anahtar = [Convert]::ToBase64String((Get-SiraliBayt 0 32))
    $k = Get-DagitikZarfAnahtarlari $anahtar
    $turkce = '{"ad":"' + [char]0x00C7 + 'al' + [char]0x0131 + [char]0x015F + 'ma","dakika":42}'
    $istek = New-DagitikZarf -Anahtarlar $k -Cihaz 'test-pc' -Tur 'ozet' -Yon 'istek' -Sayac 42 -Zaman 1757980800 -Metin $turkce -SabitIv (Get-SiraliBayt 64 16)
    $yanitMetni = '{"kod":200,"govde":{"ok":true},"adresler":{"sunucuUrl":"http://192.168.1.20:8787","ekAdresler":[],"postaUrl":""}}'
    $yanit = New-DagitikZarf -Anahtarlar $k -Cihaz 'test-pc' -Tur 'ozet' -Yon 'yanit' -Sayac 42 -Zaman 1757980805 -Metin $yanitMetni -SabitIv (Get-SiraliBayt 80 16)
    $kod = 'ABCD-EFGH-JKMN'
    $kayit = Get-DagitikKayitAnahtarlari -Kod $kod
    $kayitMetni = '{"schemaVersion":2,"onay":true,"cihazAdi":"Mac","kullanici":"test","surum":"mac-1.0"}'
    $kayitZarfi = New-DagitikZarf -Anahtarlar $kayit -Cihaz $kayit.kanal -Tur 'kayit' -Yon 'istek' -Sayac 1 -Zaman 1757980900 -Metin $kayitMetni -SabitIv (Get-SiraliBayt 96 16)
    return [ordered]@{
        zarfV2 = [ordered]@{
            aciklama = 'Alt anahtarlar: HMAC-SHA256(cihazAnahtari, UTF8(etiket)). Imza girdisi: UTF8("AIZEN-ZARF-2\n" + cihaz + "\n" + tur + "\n" + yon + "\n" + sayac + "\n" + zaman + "\n" + iv + "\n" + veri); etiket = HMAC-SHA256(imza, girdi). veri = AES-256-CBC/PKCS7(sifre, iv, UTF8(metin)).'
            cihazAnahtariBase64 = $anahtar
            sifreEtiketi = 'Aizen|v2|sifre'
            imzaEtiketi = 'Aizen|v2|imza'
            postaEtiketi = 'Aizen|v2|posta'
            sifreHex = (ConvertTo-Hex $k.sifre)
            imzaHex = (ConvertTo-Hex $k.imza)
            postaJetonu = $k.postaJetonu
            postaJetonuOzeti = (Get-DagitikMetinOzeti $k.postaJetonu)
            istekMetni = $turkce
            istek = $istek
            yanitMetni = $yanitMetni
            yanit = $yanit
        }
        kayitV2 = [ordered]@{
            aciklama = 'ana = PBKDF2-HMAC-SHA256(UTF8(normal kod), UTF8("Aizen|kayit|v2"), 120000, 32); alt anahtarlar HMAC-SHA256(ana, UTF8(etiket)); kanal = "k-" + ilk 24 hex(HMAC(ana, "Aizen|kayit|v2|kimlik")).'
            kod = $kod
            tur = 120000
            anaAnahtarBase64 = $kayit.anaAnahtar
            kanal = $kayit.kanal
            sifreHex = (ConvertTo-Hex $kayit.sifre)
            imzaHex = (ConvertTo-Hex $kayit.imza)
            postaJetonu = $kayit.postaJetonu
            istekMetni = $kayitMetni
            istek = $kayitZarfi
        }
    }
}

if ($Uret) {
    # v1 bolumleri mevcutsa korunur (anahtar zarfi rastgele IV'lidir; gereksiz fark uretmesin)
    $mevcut = $null
    if (Test-Path -LiteralPath $jsonYolu) { $mevcut = Get-Content -LiteralPath $jsonYolu -Raw -Encoding UTF8 | ConvertFrom-Json }
    $anahtar = [Convert]::ToBase64String((Get-SiraliBayt 0 32))
    $kayitTuzu = [Convert]::ToBase64String((Get-SiraliBayt 16 16))
    $sifreTuzu = [Convert]::ToBase64String((Get-SiraliBayt 32 16))
    $kod = 'ABCDEFGHJKMN'
    # ASCII disi govde: imza UTF-8 baytlari uzerinden alinir (Calisma, Turkce harflerle)
    $turkce = '{"ad":"' + [char]0x00C7 + 'al' + [char]0x0131 + [char]0x015F + 'ma"}'
    $hmacGirdileri = @(
        @('POST govdesi (gonderilen baytlarin aynisi)', '1757980800', '{"schemaVersion":1,"cihazId":"test-pc"}'),
        @('GET: govde yerine yol + sorgu', '1757980800', '/v1/toplam?tarih=2026-09-16'),
        @('ASCII disi govde (UTF-8)', '1757980801', $turkce)
    )
    $zarf = Protect-DagitikKodIle -Metin $anahtar -Kod $kod -Tuz $sifreTuzu
    if ($null -ne $mevcut -and $null -ne $mevcut.anahtarZarfi) { $zarf = $mevcut.anahtarZarfi }
    $vektorler = [ordered]@{
        surum = 1
        aciklama = 'Windows uygulamasinin urettigi degerler. Baytlar base64 ya da kucuk harf hex. Ayrintilar: MACOS-INCELEME.md.'
        anahtarBase64 = $anahtar
        hmac = @($hmacGirdileri | ForEach-Object {
            [ordered]@{
                ad = $_[0]
                zaman = $_[1]
                govde = $_[2]
                imzaGirdisi = 'UTF8(zaman + "\n" + govde)'
                imzaHex = (Get-DagitikHmac -Anahtar $anahtar -ZamanDamgasi $_[1] -Govde $_[2])
            }
        })
        kodNormallestirme = @('abcd-efgh-jkmn', ' O1IL-2345-6789 ', 'abcd efgh jkmn') | ForEach-Object {
            [ordered]@{ girdi = $_; cikti = (ConvertTo-DagitikKodNormal $_) }
        }
        kodOzeti = [ordered]@{
            aciklama = 'Merkezin kayitOzeti: PBKDF2-HMAC-SHA256(parola=UTF8(normal kod), tuz, tur) ilk 32 bayt'
            kod = $kod
            tuzBase64 = $kayitTuzu
            tur = 120000
            ozetBase64 = (Get-DagitikKodOzeti -Kod $kod -Tuz $kayitTuzu -Tur 120000)
        }
        turetilen64 = [ordered]@{
            aciklama = '64 bayt: ilk 32 AES-256 anahtari, son 32 HMAC anahtari'
            kod = $kod
            tuzBase64 = $sifreTuzu
            tur = 120000
            hex = (ConvertTo-Hex (Get-DagitikKodAnahtari -Kod $kod -Tuz $sifreTuzu -Tur 120000 -Uzunluk 64))
        }
        anahtarZarfi = [ordered]@{
            aciklama = 'POST /v1/kayit yanitindaki "anahtar". Once etiket = HMAC-SHA256(macAnahtari, iv + veri) sabit zamanli dogrulanir, sonra AES-256-CBC/PKCS7 cozulur.'
            kod = $kod
            tuz = $sifreTuzu
            iv = $zarf.iv
            veri = $zarf.veri
            etiket = $zarf.etiket
            beklenenAnahtar = $anahtar
            yanlisKod = 'ABCDEFGHJKMP'
        }
    }
    $v2 = New-V2Vektorleri
    foreach ($ad in $v2.Keys) { $vektorler[$ad] = $v2[$ad] }
    $json = ConvertTo-Json -InputObject $vektorler -Depth 6
    [IO.File]::WriteAllText($jsonYolu, $json, (New-Object Text.UTF8Encoding($false)))
    Write-Output "Uretildi: $jsonYolu"
}

$v = Get-Content -LiteralPath $jsonYolu -Raw -Encoding UTF8 | ConvertFrom-Json
$hatalar = @()
$kontrol = 0

foreach ($h in @($v.hmac)) {
    $kontrol++
    if ((Get-DagitikHmac -Anahtar $v.anahtarBase64 -ZamanDamgasi $h.zaman -Govde $h.govde) -cne $h.imzaHex) { $hatalar += "HMAC: $($h.ad)" }
}
foreach ($n in @($v.kodNormallestirme)) {
    $kontrol++
    if ((ConvertTo-DagitikKodNormal $n.girdi) -cne $n.cikti) { $hatalar += "Kod normallestirme: '$($n.girdi)'" }
}
$kontrol++
if ((Get-DagitikKodOzeti -Kod $v.kodOzeti.kod -Tuz $v.kodOzeti.tuzBase64 -Tur ([int]$v.kodOzeti.tur)) -cne $v.kodOzeti.ozetBase64) { $hatalar += 'Kod ozeti (PBKDF2 32 bayt)' }
$kontrol++
if ((ConvertTo-Hex (Get-DagitikKodAnahtari -Kod $v.turetilen64.kod -Tuz $v.turetilen64.tuzBase64 -Tur ([int]$v.turetilen64.tur) -Uzunluk 64)) -cne $v.turetilen64.hex) { $hatalar += 'PBKDF2 64 bayt' }

$z = $v.anahtarZarfi
$kontrol++
try {
    if ((Unprotect-DagitikKodIle -Paket $z -Kod $z.kod -Tuz $z.tuz) -cne $z.beklenenAnahtar) { $hatalar += 'Anahtar zarfi yanlis anahtara cozuldu' }
}
catch { $hatalar += "Anahtar zarfi cozulemedi: $($_.Exception.Message)" }
$kontrol++
$reddedildi = $false
try { [void](Unprotect-DagitikKodIle -Paket $z -Kod $z.yanlisKod -Tuz $z.tuz) } catch { $reddedildi = $true }
if (-not $reddedildi) { $hatalar += 'Yanlis kodla zarf reddedilmedi' }
$kontrol++
$kurcalanmis = [pscustomobject]@{ iv = $z.iv; veri = $z.veri; etiket = [Convert]::ToBase64String((New-Object byte[] 32)) }
$reddedildi = $false
try { [void](Unprotect-DagitikKodIle -Paket $kurcalanmis -Kod $z.kod -Tuz $z.tuz) } catch { $reddedildi = $true }
if (-not $reddedildi) { $hatalar += 'Kurcalanmis etiketli zarf reddedilmedi' }

# ---- protokol v2 ----
$z2 = $v.zarfV2
if ($null -eq $z2 -or $null -eq $v.kayitV2) { $hatalar += 'v2 vektorleri eksik (-Uret ile uretin)' }
else {
    $k2 = Get-DagitikZarfAnahtarlari $z2.cihazAnahtariBase64
    $kontrol++
    if ((ConvertTo-Hex $k2.sifre) -cne $z2.sifreHex -or (ConvertTo-Hex $k2.imza) -cne $z2.imzaHex -or $k2.postaJetonu -cne $z2.postaJetonu) { $hatalar += 'v2 alt anahtarlari' }
    $kontrol++
    if ((Get-DagitikMetinOzeti $z2.postaJetonu) -cne $z2.postaJetonuOzeti) { $hatalar += 'v2 posta jetonu ozeti' }
    foreach ($parca in @(@('istek', $z2.istek, $z2.istekMetni), @('yanit', $z2.yanit, $z2.yanitMetni))) {
        $beklenen = $parca[1]
        $kontrol++
        $uretilen = New-DagitikZarf -Anahtarlar $k2 -Cihaz $beklenen.cihaz -Tur $beklenen.tur -Yon $beklenen.yon -Sayac ([long]$beklenen.sayac) `
            -Zaman ([long]$beklenen.zaman) -Metin $parca[2] -SabitIv ([Convert]::FromBase64String($beklenen.iv))
        if ($uretilen.veri -cne $beklenen.veri -or $uretilen.etiket -cne $beklenen.etiket) { $hatalar += "v2 zarf uretimi ($($parca[0]))" }
        $kontrol++
        try { if ((Open-DagitikZarf -Anahtarlar $k2 -Zarf $beklenen) -cne $parca[2]) { $hatalar += "v2 zarf cozumu ($($parca[0]))" } }
        catch { $hatalar += "v2 zarf acilamadi ($($parca[0])): $($_.Exception.Message)" }
    }
    $kontrol++
    $kurcalanmis = $z2.istek | ConvertTo-Json -Compress | ConvertFrom-Json
    $kurcalanmis.sayac = 43
    $reddedildi = $false
    try { [void](Open-DagitikZarf -Anahtarlar $k2 -Zarf $kurcalanmis) } catch { $reddedildi = $true }
    if (-not $reddedildi) { $hatalar += 'v2 sayaci degistirilmis zarf reddedilmedi' }

    $kv = $v.kayitV2
    $kk = Get-DagitikKayitAnahtarlari -Kod $kv.kod -Tur ([int]$kv.tur)
    $kontrol++
    if ($kk.anaAnahtar -cne $kv.anaAnahtarBase64 -or $kk.kanal -cne $kv.kanal -or (ConvertTo-Hex $kk.sifre) -cne $kv.sifreHex -or
        (ConvertTo-Hex $kk.imza) -cne $kv.imzaHex -or $kk.postaJetonu -cne $kv.postaJetonu) { $hatalar += 'v2 kayit anahtarlari' }
    $kontrol++
    $kz = New-DagitikZarf -Anahtarlar $kk -Cihaz $kv.istek.cihaz -Tur 'kayit' -Yon 'istek' -Sayac ([long]$kv.istek.sayac) -Zaman ([long]$kv.istek.zaman) `
        -Metin $kv.istekMetni -SabitIv ([Convert]::FromBase64String($kv.istek.iv))
    if ($kz.veri -cne $kv.istek.veri -or $kz.etiket -cne $kv.istek.etiket) { $hatalar += 'v2 kayit zarfi' }
}

if ($hatalar.Count -gt 0) {
    Write-Output "Protokol vektorleri UYUMSUZ ($($hatalar.Count) / $kontrol):"
    $hatalar | ForEach-Object { Write-Output "  - $_" }
    exit 1
}
Write-Output "Protokol vektorleri Windows koduyla uyumlu ($kontrol kontrol)."
exit 0
