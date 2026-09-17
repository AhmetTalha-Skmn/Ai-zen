# ============================================================
#  Uygulama ici wiki: <kok>\wiki\*.md sayfalarini okur, kurulum turune ve platforma gore
#  suzer, sade HTML'e cevirir. Pencere: wiki-penceresi.ps1. Bicim: wiki\README.md
#
#  Sayfa: on bilgi (baslik, turler, platformlar, sira) + Markdown govde.
#  Blok: <!-- yalniz: bireysel ozel windows --> ... <!-- /yalniz -->  (ic ice olabilir)
#  ASCII tutulur (BOM gerekmez); Turkce metin yalnizca .md dosyalarindadir.
# ============================================================
$script:WIKI_TURLER = @('bireysel', 'sirket', 'ozel')
$script:WIKI_PLATFORMLAR = @('windows', 'mac')
$script:WIKI_YER = [string][char]0xE000   # satir ici kod yer tutucusu (ozel kullanim alani)

function Wiki-Liste { param([string]$Metin)
    $m = ([string]$Metin).Trim().ToLowerInvariant()
    if ($m -eq '' -or $m -eq 'hepsi') { return @() }
    return @($m -split '[,\s]+' | Where-Object { $_ }) }

# On bilgi + govde. On bilgi yoksa baslik dosya adindan, gorunurluk "hepsi".
function Wiki-SayfaOku { param([string]$Yol)
    $ham = [System.IO.File]::ReadAllText($Yol, [System.Text.Encoding]::UTF8).Replace("`r`n", "`n")
    $ad = [System.IO.Path]::GetFileNameWithoutExtension($Yol).ToLowerInvariant()
    $s = [ordered]@{ ad = $ad; baslik = $ad; turler = @(); platformlar = @(); sira = 1000; govde = $ham }
    if ($ham.StartsWith("---`n")) {
        $son = $ham.IndexOf("`n---", 4)
        if ($son -gt 0) {
            foreach ($satir in $ham.Substring(4, $son - 4).Split("`n")) {
                $i = $satir.IndexOf(':'); if ($i -lt 1) { continue }
                $k = $satir.Substring(0, $i).Trim(); $v = $satir.Substring($i + 1).Trim()
                switch ($k) {
                    'baslik'      { $s.baslik = $v }
                    'turler'      { $s.turler = @(Wiki-Liste $v) }
                    'platformlar' { $s.platformlar = @(Wiki-Liste $v) }
                    'sira'        { $n = 0; if ([int]::TryParse($v, [ref]$n)) { $s.sira = $n } }
                }
            }
            $govdeBas = $ham.IndexOf("`n", $son + 1)
            if ($govdeBas -lt 0) { $s.govde = '' } else { $s.govde = $ham.Substring($govdeBas + 1) }
        }
    }
    return [pscustomobject]$s }

# Etiket listesi bu tur/platformda gorunur mu: platform etiketi varsa platform, tur etiketi varsa tur eslesmeli
function Wiki-Gorunur { param([string[]]$Etiketler, [string]$Tur, [string]$Platform)
    $e = @($Etiketler | Where-Object { $_ })
    $pl = @($e | Where-Object { $script:WIKI_PLATFORMLAR -contains $_ })
    $tr = @($e | Where-Object { $script:WIKI_TURLER -contains $_ })
    if ($pl.Count -gt 0 -and $pl -notcontains $Platform) { return $false }
    if ($tr.Count -gt 0 -and $tr -notcontains $Tur) { return $false }
    return $true }

# <!-- yalniz: ... --> bloklarini uygular; isaret satirlari tamamen cikar (listeler bolunmez)
function Wiki-Suz { param([string]$Govde, [string]$Tur, [string]$Platform)
    $cikti = New-Object System.Collections.Generic.List[string]
    $yigin = New-Object System.Collections.Generic.List[bool]
    foreach ($satir in $Govde.Replace("`r`n", "`n").Split("`n")) {
        $t = $satir.Trim()
        $m = [regex]::Match($t, '^<!--\s*yalniz\s*:\s*(.*?)\s*-->$')
        if ($m.Success) { $yigin.Add((Wiki-Gorunur (Wiki-Liste $m.Groups[1].Value) $Tur $Platform)); continue }
        if ([regex]::IsMatch($t, '^<!--\s*/yalniz\s*-->$')) { if ($yigin.Count) { $yigin.RemoveAt($yigin.Count - 1) }; continue }
        if ($yigin.Contains($false)) { continue }
        $cikti.Add($satir)
    }
    return ($cikti -join "`n") }

# Gorunen sayfalar, siraya gore. -Tur: bireysel|sirket|ozel, -Platform: windows|mac
function Wiki-Sayfalar { param([string]$Klasor, [string]$Tur = 'bireysel', [string]$Platform = 'windows')
    if (-not (Test-Path -LiteralPath $Klasor -PathType Container)) { return @() }
    $liste = @()
    foreach ($d in @(Get-ChildItem -LiteralPath $Klasor -Filter '*.md' -File | Sort-Object Name)) {
        if ($d.Name -ieq 'README.md') { continue }
        $s = Wiki-SayfaOku $d.FullName
        if ($s.turler.Count -gt 0 -and $s.turler -notcontains $Tur) { continue }
        if ($s.platformlar.Count -gt 0 -and $s.platformlar -notcontains $Platform) { continue }
        $s.govde = Wiki-Suz $s.govde $Tur $Platform
        $liste += $s
    }
    return @($liste | Sort-Object @{ Expression = { $_.sira } }, @{ Expression = { $_.ad } }) }

function Wiki-Kacis { param([string]$Metin) return [System.Net.WebUtility]::HtmlEncode($Metin) }

# Satir ici: kod, kalin, sayfa baglantisi. Gorunmeyen sayfaya baglanti duz metin olur.
function Wiki-SatirIci { param([string]$Metin, [string[]]$Adlar)
    $kodlar = New-Object System.Collections.Generic.List[string]
    $s = [regex]::Replace($Metin, '`([^`]+)`', [System.Text.RegularExpressions.MatchEvaluator]{ param($m)
        $kodlar.Add($m.Groups[1].Value); return ($script:WIKI_YER + ($kodlar.Count - 1) + $script:WIKI_YER) })
    $s = Wiki-Kacis $s
    $s = [regex]::Replace($s, '\*\*(.+?)\*\*', '<strong>$1</strong>')
    $s = [regex]::Replace($s, '\[([^\]]+)\]\(([^)\s]+)\)', [System.Text.RegularExpressions.MatchEvaluator]{ param($m)
        $hedef = $m.Groups[2].Value.ToLowerInvariant()
        if ($Adlar -contains $hedef) { return ('<a href="wiki:' + $hedef + '">' + $m.Groups[1].Value + '</a>') }
        return $m.Groups[1].Value })
    $s = [regex]::Replace($s, [regex]::Escape($script:WIKI_YER) + '(\d+)' + [regex]::Escape($script:WIKI_YER), [System.Text.RegularExpressions.MatchEvaluator]{ param($m)
        return ('<code>' + (Wiki-Kacis $kodlar[[int]$m.Groups[1].Value]) + '</code>') })
    return $s }

function Wiki-TabloHucreleri { param([string]$Satir)
    $t = $Satir.Trim(); if ($t.StartsWith('|')) { $t = $t.Substring(1) }; if ($t.EndsWith('|')) { $t = $t.Substring(0, $t.Length - 1) }
    return @($t.Split('|') | ForEach-Object { $_.Trim() }) }

# Markdown govdesini HTML parcasina cevirir (desteklenen alt kume: wiki\README.md)
function Wiki-Html { param([string]$Markdown, [string[]]$Adlar = @())
    $h = New-Object System.Text.StringBuilder
    $satirlar = $Markdown.Replace("`r`n", "`n").Split("`n")
    $paragraf = New-Object System.Collections.Generic.List[string]
    $liste = ''; $listeOgesi = $null; $alinti = New-Object System.Collections.Generic.List[string]
    $kapat = {
        if ($paragraf.Count) { [void]$h.Append('<p>' + (Wiki-SatirIci ($paragraf -join ' ') $Adlar) + "</p>`n"); $paragraf.Clear() }
        if ($null -ne $listeOgesi) { [void]$h.Append('<li>' + (Wiki-SatirIci $listeOgesi $Adlar) + "</li>`n"); $listeOgesi = $null }
        if ($liste) { [void]$h.Append("</$liste>`n"); $liste = '' }
        if ($alinti.Count) { [void]$h.Append('<blockquote>' + (Wiki-SatirIci ($alinti -join ' ') $Adlar) + "</blockquote>`n"); $alinti.Clear() }
    }
    $i = 0
    while ($i -lt $satirlar.Length) {
        $satir = $satirlar[$i]; $t = $satir.Trim()
        if ($t.StartsWith('```')) {
            . $kapat
            $kod = New-Object System.Collections.Generic.List[string]; $i++
            while ($i -lt $satirlar.Length -and -not $satirlar[$i].Trim().StartsWith('```')) { $kod.Add($satirlar[$i]); $i++ }
            [void]$h.Append('<pre>' + (Wiki-Kacis ($kod -join "`n")) + "</pre>`n"); $i++; continue
        }
        if ($t -eq '') { . $kapat; $i++; continue }
        $mb = [regex]::Match($t, '^(#{1,3})\s+(.+)$')
        if ($mb.Success) {
            . $kapat
            $n = $mb.Groups[1].Value.Length
            [void]$h.Append("<h$n>" + (Wiki-SatirIci $mb.Groups[2].Value $Adlar) + "</h$n>`n"); $i++; continue
        }
        if ($t.StartsWith('|') -and $t.EndsWith('|')) {
            . $kapat
            [void]$h.Append("<table>`n")
            $ilk = $true
            while ($i -lt $satirlar.Length -and $satirlar[$i].Trim().StartsWith('|')) {
                $tt = $satirlar[$i].Trim()
                if ([regex]::IsMatch($tt, '^\|[\s:|-]+\|$')) { $i++; continue }
                $etiket = 'td'; if ($ilk) { $etiket = 'th' }
                [void]$h.Append('<tr>')
                foreach ($hucre in (Wiki-TabloHucreleri $tt)) { [void]$h.Append("<$etiket>" + (Wiki-SatirIci $hucre $Adlar) + "</$etiket>") }
                [void]$h.Append("</tr>`n"); $ilk = $false; $i++
            }
            [void]$h.Append("</table>`n"); continue
        }
        $ml = [regex]::Match($t, '^(?:([-*])|(\d+)\.)\s+(.+)$')
        if ($ml.Success) {
            $tur = 'ol'; if ($ml.Groups[1].Success) { $tur = 'ul' }
            if ($paragraf.Count -or $alinti.Count -or ($liste -and $liste -ne $tur)) { . $kapat }
            if (-not $liste) { $liste = $tur; [void]$h.Append("<$tur>`n") }
            if ($null -ne $listeOgesi) { [void]$h.Append('<li>' + (Wiki-SatirIci $listeOgesi $Adlar) + "</li>`n") }
            $listeOgesi = $ml.Groups[3].Value; $i++; continue
        }
        if ($liste -and $null -ne $listeOgesi -and $satir.StartsWith('  ')) { $listeOgesi = $listeOgesi + ' ' + $t; $i++; continue }
        if ($t.StartsWith('>')) {
            if ($paragraf.Count -or $liste) { . $kapat }
            $alinti.Add($t.Substring(1).Trim()); $i++; continue
        }
        if ($liste -or $alinti.Count) { . $kapat }
        $paragraf.Add($t); $i++
    }
    . $kapat
    return $h.ToString() }

$script:WIKI_CSS = @'
body { font-family: "Segoe UI", -apple-system, sans-serif; font-size: 14px; line-height: 1.55; color: #111827; background: #FFFFFF; margin: 22px 28px; }
h1 { font-size: 22px; margin: 0 0 14px; } h2 { font-size: 16px; margin: 22px 0 8px; } h3 { font-size: 14px; margin: 18px 0 6px; }
p, ul, ol, table, pre, blockquote { margin: 0 0 12px; } ul, ol { padding-left: 22px; } li { margin: 3px 0; }
code { font-family: Consolas, Menlo, monospace; font-size: 12.5px; background: #F3F4F6; padding: 1px 4px; border-radius: 3px; }
pre { font-family: Consolas, Menlo, monospace; font-size: 12.5px; background: #F3F4F6; padding: 10px 12px; white-space: pre-wrap; }
table { border-collapse: collapse; width: 100%; } th, td { border: 1px solid #E5E7EB; padding: 6px 9px; text-align: left; vertical-align: top; }
th { background: #F9FAFB; font-weight: 600; }
blockquote { border-left: 3px solid #2563EB; background: #EFF6FF; padding: 8px 12px; margin-left: 0; }
a { color: #2563EB; text-decoration: none; } a:hover { text-decoration: underline; }
'@

# WebBrowser icin tam belge
function Wiki-Belge { param($Sayfa, [string[]]$Adlar = @())
    return ('<!DOCTYPE html><html><head><meta charset="utf-8"><meta http-equiv="X-UA-Compatible" content="IE=edge">' +
        '<style>' + $script:WIKI_CSS + '</style></head><body>' + (Wiki-Html $Sayfa.govde $Adlar) + '</body></html>') }
