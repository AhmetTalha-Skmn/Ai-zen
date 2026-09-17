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

if ($Uret) {
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

if ($hatalar.Count -gt 0) {
    Write-Output "Protokol vektorleri UYUMSUZ ($($hatalar.Count) / $kontrol):"
    $hatalar | ForEach-Object { Write-Output "  - $_" }
    exit 1
}
Write-Output "Protokol vektorleri Windows koduyla uyumlu ($kontrol kontrol)."
exit 0
