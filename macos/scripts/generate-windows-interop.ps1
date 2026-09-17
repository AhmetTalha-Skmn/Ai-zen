# Development only: Windows-origin interoperability fixtures for the Mac package.
#
# Built by the REAL Windows sources (read-only): New-GunlukOzet, the rule queue, the central
# rule library, Merge-YerelKurallar and Protect-DagitikKodIle are executed as-is. A few request
# and response expressions live inline in Windows scripts; they are mirrored below and the
# script refuses to run if those exact source lines changed, so the fixture cannot drift silently.
#
# Writes only Tests/CalismaTakipTests/Fixtures/windows-interop.json and windows-vectors.json.
#
#   powershell.exe -NoProfile -ExecutionPolicy Bypass -File macos/scripts/generate-windows-interop.ps1
# Default Windows repository: the parent of macos/ (single project). -WindowsRepo overrides it.
param([string]$WindowsRepo)

$ErrorActionPreference = 'Stop'
$macRoot = Split-Path -Parent $PSScriptRoot
$fixtures = Join-Path $macRoot 'Tests\CalismaTakipTests\Fixtures'
# Filled in the body: $PSScriptRoot is empty inside param defaults of advanced scripts.
if ([string]::IsNullOrWhiteSpace($WindowsRepo)) { $WindowsRepo = Split-Path -Parent $macRoot }
$WindowsRepo = [IO.Path]::GetFullPath($WindowsRepo)
$dagitik = Join-Path $WindowsRepo 'dagitik'
$hatirlatici = Join-Path $WindowsRepo 'hatirlatici'
$utf8 = New-Object Text.UTF8Encoding($false)

function Read-WindowsSource([string]$Relative) {
    $path = Join-Path $WindowsRepo $Relative
    if (-not (Test-Path -LiteralPath $path)) { throw "Windows source missing: $Relative" }
    return [IO.File]::ReadAllText($path)
}
function ConvertTo-Base64Utf8([string]$Text) { return [Convert]::ToBase64String($utf8.GetBytes($Text)) }
function Get-SequenceBytes([int]$Start, [int]$Count) {
    $bytes = New-Object byte[] $Count
    for ($i = 0; $i -lt $Count; $i++) { $bytes[$i] = [byte]($Start + $i) }
    return ,$bytes
}

# Inline Windows expressions mirrored in this file. Any change there must be reviewed here first.
$mirrored = @(
    @('dagitik\istemci-kayit.ps1', 'kod = $kodNormal'),
    @('dagitik\istemci-kayit.ps1', 'onay = $true'),
    @('dagitik\istemci-kayit.ps1', '} | ConvertTo-Json -Depth 4 -Compress'),
    @('dagitik\istemci-gonderici.ps1', '$paket = Read-DagitikJson $dosya.FullName'),
    @('dagitik\istemci-gonderici.ps1', '$govde = $paket | ConvertTo-Json -Depth 10 -Compress'),
    @('dagitik\istemci-gonderici.ps1', 'kararlar = @($bekleyen | ForEach-Object {'),
    @('dagitik\istemci-gonderici.ps1', '[ordered]@{ oge = [string]$_.oge; tur = [string]$_.tur; karar = [string]$_.karar }'),
    @('dagitik\istemci-gonderici.ps1', '} | ConvertTo-Json -Depth 5 -Compress'),
    @('dagitik\merkez-sunucu.ps1', '$json = $Nesne | ConvertTo-Json -Depth 6 -Compress'),
    @('dagitik\merkez-sunucu.ps1', 'silinenKurallar = @(Get-DagitikDeger $kurallar ''silinenKurallar'' @())'),
    @('dagitik\merkez-sunucu.ps1', 'anahtar = [ordered]@{ tuz = $sifreTuzu; iv = $sarmal.iv; veri = $sarmal.veri; etiket = $sarmal.etiket }'),
    @('dagitik\merkez-sunucu.ps1', 'digerCihazDk = $toplam.digerCihazDk')
)
foreach ($item in $mirrored) {
    if (-not (Read-WindowsSource $item[0]).Contains($item[1])) {
        throw "Windows source changed; review this generator before regenerating: $($item[0]) -> $($item[1])"
    }
}

. (Join-Path $dagitik 'Ortak.ps1')
. (Join-Path $dagitik 'Senkron-Durum.ps1')
. (Join-Path $dagitik 'Merkez-Kural.ps1')
. (Join-Path $dagitik 'Merkez-Ozet.ps1')
. (Join-Path $hatirlatici 'kural-senkron.ps1')

# istemci-gonderici.ps1 has top-level code: import only its named summary functions.
$tokens = $null
$parseErrors = $null
$senderAst = [Management.Automation.Language.Parser]::ParseFile((Join-Path $dagitik 'istemci-gonderici.ps1'), [ref]$tokens, [ref]$parseErrors)
if ($parseErrors.Count) { throw 'istemci-gonderici.ps1 has parse errors.' }
foreach ($name in @('GondericiLog', 'Get-Saniye', 'Get-SureToplami', 'Get-BaskinAlan', 'New-GunlukOzet')) {
    $definitions = @($senderAst.FindAll({ param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $name }, $true))
    if ($definitions.Count -ne 1) { throw "Function absent or ambiguous: $name" }
    . ([scriptblock]::Create($definitions[0].Extent.Text))
}

# Fixed values. .NET 'o' format carries seven fractional second digits.
$dotNetTime = (New-Object DateTime 2026, 9, 16, 9, 37, 51, ([DateTimeKind]::Utc)).AddTicks(3815769).ToString('o')
$turkishApp = [string][char]0x00C7 + 'al' + [char]0x0131 + [char]0x015F + 'ma Notlar' + [char]0x0131
$turkishTitle = 'Ders Notlar' + [char]0x0131 + ' - Hafta 3'

$work = Join-Path ([IO.Path]::GetTempPath()) ('ct-interop-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
try {
    # ---- Windows client: daily summary exactly as istemci-gonderici.ps1 sends it ----
    $HatirlaticiKlasoru = Join-Path $work 'hatirlatici'
    [void][IO.Directory]::CreateDirectory((Join-Path $HatirlaticiKlasoru 'aktivite'))
    $hedefYolu = Join-Path $HatirlaticiKlasoru 'ayarlar.json'
    $logYolu = Join-Path $HatirlaticiKlasoru 'merkez-gonderici.log'
    [IO.File]::WriteAllText($hedefYolu, '{"hedef":240,"duraklat":""}')
    $csv = @(
        'zaman;uygulama;baslik;bosta;kategori;sure;kaynak',
        '09:00:00;Code;proje.ps1;0;calisma;1500;kural',
        ('09:25:00;' + $turkishApp + ';Hafta 3;0;calisma;300;kural'),
        '09:30:00;Microsoft Edge;Haberler;0;diger;600;kural',
        '09:40:00;Code;proje.ps1;1;bosta;120;bosta'
    ) -join "`r`n"
    [IO.File]::WriteAllText((Join-Path $HatirlaticiKlasoru 'aktivite\@@TARIH@@.csv'), $csv, (New-Object Text.UTF8Encoding($true)))
    $ayar = [pscustomobject][ordered]@{ aktif = $true; cihazId = '@@CIHAZ@@'; cihazAdi = 'Windows Test PC'; ayrintiDuzeyi = 'ozet'; sira = 7; sonBasariliSenkronUtc = $dotNetTime }
    $ozet = New-GunlukOzet -Tarih '@@TARIH@@' -Ayar $ayar
    $ozet['gonderildiUtc'] = $dotNetTime
    $ozet['zamanDilimiOfsetDk'] = 180
    $ozet['health']['sonOrnekUtc'] = $dotNetTime
    $ozet['health']['senkron']['bildirimUtc'] = $dotNetTime
    # The sender queues the summary as a file, reads it back and serializes that object.
    $outbox = Join-Path $HatirlaticiKlasoru 'merkez-outbox'
    [void][IO.Directory]::CreateDirectory($outbox)
    $queued = Join-Path $outbox 'ozet.json'
    Write-DagitikJsonAtomik -Nesne $ozet -Yol $queued
    $paket = Read-DagitikJson $queued
    $govde = $paket | ConvertTo-Json -Depth 10 -Compress
    if ($govde -notmatch '"gonderildiUtc":"\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{7}Z"') { throw 'Summary does not carry the .NET timestamp format.' }
    [IO.Directory]::Delete($outbox, $true)

    # ---- Windows client: rule pushes (multiple and single decision) ----
    [void](Add-KuralKuyruk -Klasor $HatirlaticiKlasoru -Oge 'example.edu' -Tur 'alanadi' -Karar 'calisma')
    [void](Add-KuralKuyruk -Klasor $HatirlaticiKlasoru -Oge 'GameLauncher' -Tur 'surec' -Karar 'yasakli')
    [void](Add-KuralKuyruk -Klasor $HatirlaticiKlasoru -Oge $turkishTitle -Tur 'baslik' -Karar 'calisma')
    $bekleyen = @(Get-KuralKuyruk -Klasor $HatirlaticiKlasoru)
    $kuralCoklu = [ordered]@{
        schemaVersion = 1
        cihazId = [string]$ayar.cihazId
        kararlar = @($bekleyen | ForEach-Object {
            [ordered]@{ oge = [string]$_.oge; tur = [string]$_.tur; karar = [string]$_.karar }
        })
    } | ConvertTo-Json -Depth 5 -Compress
    Clear-KuralKuyruk -Klasor $HatirlaticiKlasoru
    [void](Add-KuralKuyruk -Klasor $HatirlaticiKlasoru -Oge 'NoteApp' -Tur 'surec' -Karar 'belirsiz')
    $bekleyen = @(Get-KuralKuyruk -Klasor $HatirlaticiKlasoru)
    $kuralTek = [ordered]@{
        schemaVersion = 1
        cihazId = [string]$ayar.cihazId
        kararlar = @($bekleyen | ForEach-Object {
            [ordered]@{ oge = [string]$_.oge; tur = [string]$_.tur; karar = [string]$_.karar }
        })
    } | ConvertTo-Json -Depth 5 -Compress

    # ---- Windows client: enrollment request (istemci-kayit.ps1) ----
    $kodNormal = '@@KOD@@'
    $CihazAdi = 'Windows Test PC'
    $surum = '1'
    $kayitIstegi = [ordered]@{
        schemaVersion = 1
        kod = $kodNormal
        cihazAdi = $CihazAdi
        kullanici = ConvertTo-DagitikSinirliMetin 'test-kullanici' 80
        surum = $surum
        onay = $true
    } | ConvertTo-Json -Depth 4 -Compress

    # ---- Windows center: shared rules response and the Windows client's merge result ----
    $kuralYolu = Join-Path $work 'merkez-kurallar.json'
    foreach ($decision in @(
        @('Editor', 'surec', 'calisma'),
        @('example.edu', 'alanadi', 'calisma'),
        @($turkishTitle, 'baslik', 'calisma'),
        @('GameLauncher', 'surec', 'yasakli'),
        @('video.example', 'alanadi', 'yasakli'),
        @('MusicPlayer', 'surec', 'belirsiz'),
        @('ChatApp', 'surec', 'yasakli')
    )) { Save-MerkezKuralKarari $kuralYolu $decision[0] $decision[1] $decision[2] }
    Save-MerkezKuralKarari $kuralYolu 'ChatApp' 'surec' 'yasakli' -Sil
    $kurallar = Get-MerkezKurallari -Yol $kuralYolu
    Set-DagitikDeger $kurallar 'sonDegisiklikUtc' $dotNetTime
    $kurallarYaniti = [ordered]@{
        ok = $true
        sonDegisiklikUtc = [string](Get-DagitikDeger $kurallar 'sonDegisiklikUtc' '')
        kuralSayisi = (Get-MerkezKuralOzeti $kurallar)
        calisma = (Get-DagitikDeger $kurallar 'calisma' $null)
        yasakli = (Get-DagitikDeger $kurallar 'yasakli' $null)
        bilerekBelirsiz = @(Get-DagitikDeger $kurallar 'bilerekBelirsiz' @())
        silinenKurallar = @(Get-DagitikDeger $kurallar 'silinenKurallar' @())
    } | ConvertTo-Json -Depth 6 -Compress

    $yerel = Join-Path $work 'yerel'
    [void][IO.Directory]::CreateDirectory($yerel)
    $once = Read-DagitikJson (Join-Path $hatirlatici 'kurallar.varsayilan.json')
    $once.calisma.surec = @('LocalTool', 'MusicPlayer')
    $once.calisma.alanadi = @('video.example')
    $once.yasakli.surec = @('ChatApp')
    $onceJson = ConvertTo-Json -InputObject $once -Depth 6
    [IO.File]::WriteAllText((Join-Path $yerel 'kurallar.json'), $onceJson, (New-Object Text.UTF8Encoding($true)))
    [void](Merge-YerelKurallar -Klasor $yerel -Merkez ($kurallarYaniti | ConvertFrom-Json))
    $sonraJson = [IO.File]::ReadAllText((Join-Path $yerel 'kurallar.json'))

    # ---- Windows center: enrollment response (merkez-sunucu.ps1 Invoke-KayitIstek fields) ----
    $kayitKodu = 'ABCDEFGHJKMN'
    $kayitAnahtari = [Convert]::ToBase64String((Get-SequenceBytes 0 32))
    $sifreTuzu = [Convert]::ToBase64String((Get-SequenceBytes 32 16))
    $sarmal = Protect-DagitikKodIle -Metin $kayitAnahtari -Kod $kayitKodu -Tuz $sifreTuzu
    $kayitYaniti = [ordered]@{
        ok = $true
        cihazId = 'windows-test-pc-1a2b3c4d'
        cihazAdi = 'Mac Test'
        sunucuUrl = 'http://192.0.2.10:8787'
        gonderimDakikasi = 5
        ayrintiDuzeyi = 'ozet'
        anahtar = [ordered]@{ tuz = $sifreTuzu; iv = $sarmal.iv; veri = $sarmal.veri; etiket = $sarmal.etiket }
        veriAciklamasi = 'Uygulama adi, kategori ve gunluk sure ozeti gonderilir.'
    } | ConvertTo-Json -Depth 6 -Compress

    # ---- Windows center: shared counter response (Get-MerkezGunToplami) ----
    $veri = Join-Path $work 'veri'
    $bugun = (Get-Date).ToString('yyyy-MM-dd')
    foreach ($device in @(@('windows-pc', 45), @('mac-istemci', 20))) {
        Write-DagitikJsonAtomik -Yol (Join-Path $veri ('guncel\' + $device[0] + '.json')) -Nesne ([ordered]@{ cihazId = $device[0]; clientTarih = $bugun; ozet = [ordered]@{ calismaDk = $device[1] } })
    }
    $toplam = Get-MerkezGunToplami -VeriKlasoru $veri -Tarih $bugun -HaricCihazId 'mac-istemci'
    $toplamYaniti = [ordered]@{
        ok = $true
        tarih = $toplam.tarih
        toplamDk = $toplam.toplamDk
        buCihazDk = $toplam.buCihazDk
        digerCihazDk = $toplam.digerCihazDk
        cihazSayisi = $toplam.cihazSayisi
        cihazlar = @($toplam.cihazlar)
    } | ConvertTo-Json -Depth 6 -Compress

    $commit = ''
    try { $commit = [string](@(& git -C $WindowsRepo rev-parse --short HEAD 2>$null)[0]) } catch { $commit = '' }

    $interop = [ordered]@{
        aciklama = 'Gercek Windows kaynaklarindan uretildi: scripts/generate-windows-interop.ps1. Yer tutucular: @@KOD@@, @@CIHAZ@@, @@TARIH@@.'
        windowsCommit = $commit
        kayitIstegiBase64 = ConvertTo-Base64Utf8 $kayitIstegi
        ozetBase64 = ConvertTo-Base64Utf8 $govde
        ozetCalismaDk = [int]$paket.ozet.calismaDk
        kuralItmeCokluBase64 = ConvertTo-Base64Utf8 $kuralCoklu
        kuralItmeTekBase64 = ConvertTo-Base64Utf8 $kuralTek
        turkceBaslik = $turkishTitle
        kurallarYanitiBase64 = ConvertTo-Base64Utf8 $kurallarYaniti
        yerelKurallarOnceBase64 = ConvertTo-Base64Utf8 $onceJson
        yerelKurallarSonraBase64 = ConvertTo-Base64Utf8 $sonraJson
        kayitYanitiBase64 = ConvertTo-Base64Utf8 $kayitYaniti
        kayitYanitiKod = $kayitKodu
        kayitYanitiAnahtar = $kayitAnahtari
        toplamYanitiBase64 = ConvertTo-Base64Utf8 $toplamYaniti
    }
    [void][IO.Directory]::CreateDirectory($fixtures)
    $interopJson = (ConvertTo-Json -InputObject $interop -Depth 4).Replace([string][char]13, '') + [char]10
    [IO.File]::WriteAllText((Join-Path $fixtures 'windows-interop.json'), $interopJson, $utf8)

    $vectorsSource = Join-Path $WindowsRepo 'uyumluluk\protokol-vektorleri.json'
    if (-not (Test-Path -LiteralPath $vectorsSource)) { throw 'Windows protocol vectors missing: uyumluluk\protokol-vektorleri.json' }
    $vectors = [IO.File]::ReadAllText($vectorsSource).Replace([string][char]13, '')
    [IO.File]::WriteAllText((Join-Path $fixtures 'windows-vectors.json'), $vectors, $utf8)

    Write-Output "Windows interop fixtures generated from Windows commit $commit."
}
finally {
    if (Test-Path -LiteralPath $work) { [IO.Directory]::Delete($work, $true) }
}
