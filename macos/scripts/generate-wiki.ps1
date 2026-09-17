# ============================================================
#  Mac uygulamasi wiki sayfalarini calisirken okumaz: <kok>\wiki\*.md -> Sources/TakipCore/WikiIcerik.swift
#  Yalnizca macOS'ta gorunen sayfalar alinir; platform bloklari burada cozulur, tur bloklari
#  (<!-- yalniz: bireysel ozel -->) uygulamada kurulum turune gore suzulur (Wiki.swift).
#  -Kontrol: dosyaya yazmaz; uretilen icerik mevcut dosyayla ayni degilse 1 ile cikar.
#  Kullanim: powershell -NoProfile -ExecutionPolicy Bypass -File macos\scripts\generate-wiki.ps1 [-Kontrol]
#  ASCII tutulur (BOM gerekmez).
# ============================================================
param([switch]$Kontrol, [string]$WikiKlasoru = '', [string]$Cikti = '')
$ErrorActionPreference = 'Stop'
$betikDir = $PSScriptRoot; if (-not $betikDir) { $betikDir = Split-Path $MyInvocation.MyCommand.Path -Parent }
$macKok = Split-Path $betikDir -Parent
$depoKok = Split-Path $macKok -Parent
if (-not $WikiKlasoru) { $WikiKlasoru = Join-Path $depoKok 'wiki' }
if (-not $Cikti) { $Cikti = Join-Path $macKok 'Sources\TakipCore\WikiIcerik.swift' }
. (Join-Path $depoKok 'hatirlatici\wiki.ps1')

# Platform etiketlerini cozer: baska platformun blogu atilir, bu platformun etiketi silinir,
# yalnizca tur etiketi kalan blok korunur, etiketsiz kalan blogun isaretleri kaldirilir.
function Platforma-Indir { param([string]$Govde, [string]$Platform)
    $cikti = New-Object System.Collections.Generic.List[string]
    $yigin = New-Object System.Collections.Generic.List[object]
    foreach ($satir in $Govde.Replace("`r`n", "`n").Split("`n")) {
        $t = $satir.Trim()
        $gizli = @($yigin | Where-Object { $_.gizli }).Count -gt 0
        $m = [regex]::Match($t, '^<!--\s*yalniz\s*:\s*(.*?)\s*-->$')
        if ($m.Success) {
            $etiketler = @(Wiki-Liste $m.Groups[1].Value)
            $pl = @($etiketler | Where-Object { $script:WIKI_PLATFORMLAR -contains $_ })
            $tr = @($etiketler | Where-Object { $script:WIKI_TURLER -contains $_ })
            $bilinmeyen = @($etiketler | Where-Object { $script:WIKI_PLATFORMLAR -notcontains $_ -and $script:WIKI_TURLER -notcontains $_ })
            if ($bilinmeyen.Count) { throw "Bilinmeyen wiki etiketi: $($bilinmeyen -join ', ')" }
            if ($gizli -or ($pl.Count -gt 0 -and $pl -notcontains $Platform)) { $yigin.Add(@{ gizli = $true; yazildi = $false }); continue }
            if ($tr.Count -gt 0) { $cikti.Add("<!-- yalniz: $($tr -join ' ') -->"); $yigin.Add(@{ gizli = $false; yazildi = $true }); continue }
            $yigin.Add(@{ gizli = $false; yazildi = $false }); continue
        }
        if ([regex]::IsMatch($t, '^<!--\s*/yalniz\s*-->$')) {
            if ($yigin.Count -eq 0) { throw 'Eslesmeyen <!-- /yalniz --> isareti' }
            $ust = $yigin[$yigin.Count - 1]; $yigin.RemoveAt($yigin.Count - 1)
            if ($ust.yazildi) { $cikti.Add('<!-- /yalniz -->') }
            continue
        }
        if (-not $gizli) { $cikti.Add($satir) }
    }
    if ($yigin.Count) { throw 'Kapatilmamis <!-- yalniz --> blogu' }
    return ($cikti -join "`n").Trim("`n") }

function Swift-Metin { param([string]$Metin) return '"' + $Metin.Replace('\', '\\').Replace('"', '\"') + '"' }

$satirlar = New-Object System.Collections.Generic.List[string]
$satirlar.Add('// Bu dosya uretilmistir: macos/scripts/generate-wiki.ps1 (kaynak: wiki/*.md). Elle degistirme.')
$satirlar.Add('// Yalniz macOS''ta gorunen sayfalar; platform bloklari cozulmus, tur bloklari Wiki.suz ile suzulur.')
$satirlar.Add('')
$satirlar.Add('public enum WikiIcerik {')
$satirlar.Add('    public static let sayfalar: [WikiSayfasi] = [')
$dosyalar = @(Get-ChildItem -LiteralPath $WikiKlasoru -Filter '*.md' -File | Where-Object { $_.Name -ne 'README.md' } | Sort-Object Name)
foreach ($d in $dosyalar) {
    $s = Wiki-SayfaOku $d.FullName
    if ($s.platformlar.Count -gt 0 -and $s.platformlar -notcontains 'mac') { continue }
    $govde = Platforma-Indir $s.govde 'mac'
    if ($govde.Contains('"""#') -or $govde.Contains('\#')) { throw "$($d.Name): Swift ham metnini bozan karakter dizisi var" }
    $turler = '[' + ((@($s.turler) | ForEach-Object { Swift-Metin $_ }) -join ', ') + ']'
    $satirlar.Add(('        WikiSayfasi(ad: {0}, baslik: {1}, turler: {2}, sira: {3}, govde: #"""' -f (Swift-Metin $s.ad), (Swift-Metin $s.baslik), $turler, $s.sira))
    foreach ($g in $govde.Split("`n")) { $satirlar.Add($g) }
    $satirlar.Add('"""#),')
}
$satirlar.Add('    ]')
$satirlar.Add('}')
$icerik = ($satirlar -join "`n") + "`n"

if ($Kontrol) {
    $mevcut = ''
    if (Test-Path -LiteralPath $Cikti) { $mevcut = [IO.File]::ReadAllText($Cikti, [Text.Encoding]::UTF8).Replace("`r`n", "`n") }
    if ($mevcut -ne $icerik) { Write-Output "GUNCEL DEGIL: $Cikti -- generate-wiki.ps1 calistir"; exit 1 }
    Write-Output "guncel: $($dosyalar.Count) sayfa"
    exit 0
}
[IO.File]::WriteAllText($Cikti, $icerik, (New-Object Text.UTF8Encoding($false)))
Write-Output "yazildi: $Cikti"
