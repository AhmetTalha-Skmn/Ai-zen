<#
GitHub'a yuklenecek temiz anlik goruntuyu hazirlar (ornegin bir hocanin incelemesi icin).

- Yalniz commit edilmis kod alinir (git archive HEAD): kaydedilmemis is (baska bir ajanin
  suren isi dahil), calisma zamani verisi ve .gitignore'daki dosyalar hic girmez.
- Kisisel dosyalar cikar: kurallar.json yerine notr sablon konur (testler ve dogrudan
  calistirma bu dosyayi bekler), .mcp.json (bu makineye ozel yol) alinmaz.
  AGENTS.md, CLAUDE.md ve DEVIR.md (ajan calisma notlari) varsayilan olarak alinmaz;
  -AjanBelgeleri ile eklenir.
- Goruntude kullanici profil yolu, kullanici adi ya da git e-postasi kalirsa hedefe
  hicbir sey yazmadan durur.
- Hedef ayri bir git deposudur; kaynak deponun gecmisi tasinmaz (eski kisisel kural
  surumleri gecmiste kalir). Her calistirmada degisiklik varsa yeni commit eklenir.
  Push kullanicidadir.

Kullanim:
  .\araclar\github-disa-aktar.ps1
  .\araclar\github-disa-aktar.ps1 -AjanBelgeleri
  .\araclar\github-disa-aktar.ps1 -Eposta 12345+kullanici@users.noreply.github.com
#>
param(
    # Varsayilan: kaynak klasorun yaninda <ad>-GitHub
    [string]$Hedef,
    [switch]$AjanBelgeleri,
    # Verilirse hedef depoda commit kimligi olarak ayarlanir (GitHub noreply adresi gibi)
    [string]$Eposta,
    [string]$Ad
)

$ErrorActionPreference = 'Stop'
$kaynak = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot)).TrimEnd('\')
if ([string]::IsNullOrWhiteSpace($Hedef)) {
    $Hedef = Join-Path (Split-Path -Parent $kaynak) ((Split-Path -Leaf $kaynak) + '-GitHub')
}
$Hedef = [IO.Path]::GetFullPath($Hedef).TrimEnd('\')
if ($Hedef -ieq $kaynak -or $Hedef.StartsWith($kaynak + '\', [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Hedef kaynak deponun kendisi ya da icinde olamaz.'
}

function Invoke-Git {
    # git uyarilarini stderr'e yazar; PS 5.1'de EAP Stop iken bu betigi dusurmesin
    param([string]$Klasor, [string[]]$Arguman, [switch]$HataOlabilir)
    $ErrorActionPreference = 'Continue'
    $cikti = @(& git -C $Klasor -c core.safecrlf=false @Arguman 2>$null)
    if ($LASTEXITCODE -ne 0 -and -not $HataOlabilir) {
        throw ('git {0} basarisiz (kod {1})' -f ($Arguman -join ' '), $LASTEXITCODE)
    }
    return @($cikti | ForEach-Object { [string]$_ })
}

$kirli = @(Invoke-Git $kaynak @('status', '--porcelain'))
$sha = @(Invoke-Git $kaynak @('rev-parse', '--short', 'HEAD'))[0]
$tarih = (Get-Date).ToString('yyyy-MM-dd')

$gecici = Join-Path $env:TEMP ('ct-gh-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
[void][IO.Directory]::CreateDirectory($gecici)
try {
    $arsiv = Join-Path $gecici 'head.zip'
    [void](Invoke-Git $kaynak @('archive', '--format=zip', '-o', $arsiv, 'HEAD'))
    $sahne = Join-Path $gecici 'sahne'
    Expand-Archive -LiteralPath $arsiv -DestinationPath $sahne

    $cikan = @('.mcp.json')
    if (-not $AjanBelgeleri) { $cikan += @('AGENTS.md', 'CLAUDE.md', 'DEVIR.md') }
    foreach ($goreli in $cikan) {
        $yol = Join-Path $sahne $goreli
        if (Test-Path -LiteralPath $yol) { [IO.File]::Delete($yol) }
    }
    Copy-Item -LiteralPath (Join-Path $sahne 'hatirlatici\kurallar.varsayilan.json') -Destination (Join-Path $sahne 'hatirlatici\kurallar.json') -Force

    # Kisisel iz denetimi: profil yolu (C:\Users\<ad>), kullanici adi, git e-postasi
    $desenler = @('[A-Za-z]:[\\/]Users[\\/][^\\/''"\s<>]+')
    if ($env:USERNAME) { $desenler += ('(?<![A-Za-z0-9])' + [regex]::Escape($env:USERNAME) + '(?![A-Za-z0-9])') }
    $gitEposta = @(Invoke-Git $kaynak @('config', 'user.email') -HataOlabilir) | Select-Object -First 1
    foreach ($adres in @($Eposta, $gitEposta)) {
        if (-not [string]::IsNullOrWhiteSpace($adres)) { $desenler += [regex]::Escape($adres.Trim()) }
    }
    $bulgular = @()
    foreach ($dosya in Get-ChildItem -LiteralPath $sahne -Recurse -File) {
        $metin = [IO.File]::ReadAllText($dosya.FullName)
        foreach ($desen in $desenler) {
            if ([regex]::IsMatch($metin, $desen, 'IgnoreCase, CultureInvariant')) {
                $bulgular += $dosya.FullName.Substring($sahne.Length + 1)
                break
            }
        }
    }
    if ($bulgular.Count -gt 0) {
        throw ("Goruntude kisisel iz var; hedefe hicbir sey yazilmadi:`n  " + (($bulgular | Sort-Object -Unique) -join "`n  "))
    }

    # Hedef yalniz bu aracin olusturdugu depo olabilir; baska bir klasorun ustune yazilmaz
    $isaret = Join-Path $Hedef '.git\ct-disa-aktarim'
    if (Test-Path -LiteralPath $Hedef) {
        if (-not (Test-Path -LiteralPath $isaret)) { throw "Hedef klasor var ve bu aracin deposu degil: $Hedef" }
        foreach ($oge in @(Get-ChildItem -LiteralPath $Hedef -Force | Where-Object { $_.Name -ne '.git' })) {
            if ($oge.PSIsContainer) { [IO.Directory]::Delete($oge.FullName, $true) } else { [IO.File]::Delete($oge.FullName) }
        }
    }
    else {
        [void][IO.Directory]::CreateDirectory($Hedef)
        [void](Invoke-Git $Hedef @('init', '-b', 'main'))
        [IO.File]::WriteAllText($isaret, "Aizen GitHub disa aktarimi`n")
    }
    foreach ($oge in @(Get-ChildItem -LiteralPath $sahne -Force)) {
        Copy-Item -LiteralPath $oge.FullName -Destination $Hedef -Recurse -Force
    }

    # Commit kimligi: -Eposta/-Ad > hedefte zaten gecerli olan > kaynak deponun kimligi
    # (kimlik yalniz kaynak deponun yerel ayarinda olabilir; yeni depo onu gormez)
    if ([string]::IsNullOrWhiteSpace($Eposta) -and -not (@(Invoke-Git $Hedef @('config', 'user.email') -HataOlabilir) | Select-Object -First 1)) {
        $Eposta = $gitEposta
    }
    if ([string]::IsNullOrWhiteSpace($Ad) -and -not (@(Invoke-Git $Hedef @('config', 'user.name') -HataOlabilir) | Select-Object -First 1)) {
        $Ad = @(Invoke-Git $kaynak @('config', 'user.name') -HataOlabilir) | Select-Object -First 1
    }
    if (-not [string]::IsNullOrWhiteSpace($Eposta)) { [void](Invoke-Git $Hedef @('config', 'user.email', $Eposta)) }
    if (-not [string]::IsNullOrWhiteSpace($Ad)) { [void](Invoke-Git $Hedef @('config', 'user.name', $Ad)) }
    if (-not (@(Invoke-Git $Hedef @('config', 'user.email') -HataOlabilir) | Select-Object -First 1)) {
        throw 'Git kimligi yok; -Eposta ve -Ad verin.'
    }
    [void](Invoke-Git $Hedef @('add', '-A'))
    $degisen = @(Invoke-Git $Hedef @('status', '--porcelain'))
    if ($degisen.Count -gt 0) {
        [void](Invoke-Git $Hedef @('commit', '-q', '-m', "Aizen anlik goruntusu ($tarih, kaynak $sha)"))
    }
    $kimlik = @(Invoke-Git $Hedef @('log', '-1', '--format=%an <%ae>'))[0]

    Write-Output "Goruntu hazir : $Hedef"
    Write-Output "Kaynak commit : $sha"
    if ($degisen.Count -eq 0) { Write-Output 'Degisiklik yok : yeni commit olusmadi.' }
    if ($kirli.Count -gt 0) { Write-Output "UYARI         : kaynakta $($kirli.Count) kaydedilmemis degisiklik var; goruntuye girmedi." }
    Write-Output ('Cikarilan     : ' + ($cikan -join ', ') + '; kurallar.json notr sablonla degisti.')
    Write-Output "Commit kimligi: $kimlik (depo herkese aciksa bu e-posta gorunur)"
    Write-Output ''
    Write-Output 'GitHub: README eklemeden bos bir depo ac, sonra:'
    Write-Output "  git -C `"$Hedef`" remote add origin https://github.com/<kullanici>/<depo>.git"
    Write-Output "  git -C `"$Hedef`" push -u origin main"
}
finally {
    if (Test-Path -LiteralPath $gecici) { [IO.Directory]::Delete($gecici, $true) }
}
