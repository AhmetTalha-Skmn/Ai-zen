# Yedek paketi veri tasir; calistirilabilir dosya ve merkez anahtari tasimaz.
function Get-CtYedekHedefi {
    param([string]$Kok, [string]$Ad)
    $adNormal = $Ad.Replace('\','/')
    if ($adNormal -cmatch '^(durum|gecmis|kurallar|ayarlar|periyot)\.json$') { return (Join-Path (Join-Path $Kok 'hatirlatici') $adNormal) }
    if ($adNormal -cmatch '^(aktivite/[^/:\\]+\.(csv|bak)|rapor/[^/:\\]+\.(json|bak)|Gunluk/[^/:\\]+\.(md|txt|bak))$') {
        if ($adNormal.StartsWith('Gunluk/')) { return (Join-Path $Kok $adNormal) }
        return (Join-Path (Join-Path $Kok 'hatirlatici') $adNormal)
    }
    throw "Yedekte izin verilmeyen yol: $Ad"
}

function Assert-CtNormalYol {
    param([string]$Yol)
    $tam = [IO.Path]::GetFullPath($Yol)
    $gezen = $tam
    while ($gezen) {
        if (Test-Path -LiteralPath $gezen) {
            if ((Get-Item -LiteralPath $gezen -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw "Bağlantılı klasör/dosya desteklenmiyor: $gezen" }
        }
        $ust = Split-Path -Parent $gezen
        if ($ust -eq $gezen) { break }
        $gezen = $ust
    }
    return $tam
}

function Test-CtVeriYedegi {
    param([string]$ZipYolu, [string]$Sahne)
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $arsiv = [IO.Compression.ZipFile]::OpenRead($ZipYolu)
    $dosyalar = New-Object System.Collections.Generic.List[object]
    $gorulen = @{}
    $manifest = $null
    [long]$toplam = 0
    try {
        if ($arsiv.Entries.Count -gt 100000) { throw 'Yedekte çok fazla dosya var.' }
        foreach ($girdi in $arsiv.Entries) {
            $ad = $girdi.FullName.Replace('\','/')
            if ($ad -match '(^|/)\.\.?(/|$)|[:]' -or $ad.StartsWith('/')) { throw 'Yedekte geçersiz yol var.' }
            if ($ad.EndsWith('/')) {
                if (@('aktivite/','rapor/','Gunluk/') -notcontains $ad) { throw 'Yedekte tanınmayan klasör var.' }
                continue
            }
            if ($gorulen.ContainsKey($ad)) { throw 'Yedekte yinelenen dosya yolu var.' }
            $gorulen[$ad] = $true
            $toplam += $girdi.Length
            if ($girdi.Length -gt 256MB -or $toplam -gt 2GB) { throw 'Yedek boyut sınırını aşıyor (dosya 256 MB, toplam 2 GB).' }
            if ($ad -in @('YEDEK-BILGISI.txt','YEDEK-MANIFEST.json')) {
                $okuyucu = New-Object IO.StreamReader($girdi.Open(), [Text.Encoding]::UTF8)
                try { $metin = $okuyucu.ReadToEnd() } finally { $okuyucu.Dispose() }
                if ($ad -eq 'YEDEK-MANIFEST.json') { $manifest = ConvertFrom-Json $metin }
                continue
            }
            [void](Get-CtYedekHedefi 'C:\ct-kontrol' $ad)
            $akim = $girdi.Open()
            $sha = [Security.Cryptography.SHA256]::Create()
            try { $hash = [BitConverter]::ToString($sha.ComputeHash($akim)).Replace('-','').ToLowerInvariant() }
            finally { $akim.Dispose(); $sha.Dispose() }
            if ($ad.EndsWith('.json')) {
                $okuyucu = New-Object IO.StreamReader($girdi.Open(), [Text.Encoding]::UTF8)
                try { $metin = $okuyucu.ReadToEnd() } finally { $okuyucu.Dispose() }
                try { $json = ConvertFrom-Json $metin -ErrorAction Stop; if ($null -eq $json) { throw 'bos' } }
                catch { throw "Yedekte bozuk JSON: $ad" }
                if ($ad -eq 'kurallar.json') {
                    if ($null -eq $json.calisma -or $null -eq $json.yasakli -or $null -eq $json.belirsizSayilsin) { throw 'Kural şeması eksik.' }
                }
            }
            if ($Sahne) {
                $hedef = Join-Path $Sahne $ad
                [void][IO.Directory]::CreateDirectory((Split-Path -Parent $hedef))
                [IO.Compression.ZipFileExtensions]::ExtractToFile($girdi,$hedef,$false)
            }
            $dosyalar.Add([pscustomobject]@{ yol=$ad; boyut=$girdi.Length; sha256=$hash })
        }
        if ($null -ne $manifest) {
            if ($manifest.surum -ne 1 -or @($manifest.dosyalar).Count -ne $dosyalar.Count) { throw 'Yedek manifesti tutarsız.' }
            $manifestYollari = @{}
            foreach ($d in @($manifest.dosyalar)) {
                if ($manifestYollari.ContainsKey([string]$d.yol)) { throw 'Manifestte yinelenen yol var.' }
                $manifestYollari[[string]$d.yol] = $true
                $gercek = @($dosyalar | Where-Object { $_.yol -ceq $d.yol })
                if ($gercek.Count -ne 1 -or $gercek[0].sha256 -cne $d.sha256 -or $gercek[0].boyut -ne $d.boyut) { throw 'Yedek bütünlük kontrolü başarısız.' }
            }
        }
        return [pscustomobject]@{ dosyalar=@($dosyalar.ToArray()); dosyaSayisi=$dosyalar.Count; bayt=$toplam; manifestli=($null -ne $manifest) }
    } finally { $arsiv.Dispose() }
}

function Write-CtYedekManifesti {
    param([string]$Sahne)
    $liste = @()
    foreach ($f in @(Get-ChildItem -LiteralPath $Sahne -Recurse -File)) {
        $ad = $f.FullName.Substring($Sahne.TrimEnd('\').Length+1).Replace('\','/')
        if ($ad -eq 'YEDEK-BILGISI.txt') { continue }
        [void](Get-CtYedekHedefi 'C:\ct-kontrol' $ad)
        $liste += [ordered]@{ yol=$ad; boyut=$f.Length; sha256=(Get-FileHash -LiteralPath $f.FullName -Algorithm SHA256).Hash.ToLowerInvariant() }
    }
    $json = [ordered]@{surum=1;olusturmaUtc=[DateTime]::UtcNow.ToString('o');dosyalar=@($liste)} | ConvertTo-Json -Depth 5
    [IO.File]::WriteAllText((Join-Path $Sahne 'YEDEK-MANIFEST.json'),$json,(New-Object Text.UTF8Encoding($true)))
}
