# ============================================================
#  API + MCP oz-testi. Gercek veriye dokunmaz: gecici bir kasada calisir.
#  Kosturma: powershell -NoProfile -ExecutionPolicy Bypass -File hatirlatici/test-api.ps1
#  Cikis kodu = hata sayisi.
# ============================================================
$ErrorActionPreference = 'Continue'
$hDir = $PSScriptRoot; if (-not $hDir) { $hDir = Split-Path $MyInvocation.MyCommand.Path -Parent }
$gecti = 0; $kaldi = 0
function T { param($ad, $sonuc, $detay)
    if ($sonuc) { $script:gecti++; Write-Host ("  [OK]   {0,-46} {1}" -f $ad, $detay) -ForegroundColor Green }
    else        { $script:kaldi++; Write-Host ("  [HATA] {0,-46} {1}" -f $ad, $detay) -ForegroundColor Red } }
[Console]::OutputEncoding = [Text.Encoding]::UTF8; $OutputEncoding = [Text.Encoding]::UTF8

# ---------- gecici kasa ----------
$kok = Join-Path $env:TEMP ('tapi' + [guid]::NewGuid().ToString('N').Substring(0, 6))
$kasa = Join-Path $kok 'hatirlatici'
$bugun = (Get-Date).ToString('yyyy-MM-dd'); $dun = (Get-Date).Date.AddDays(-1).ToString('yyyy-MM-dd')
foreach ($d in 'aktivite', 'rapor') { [void][IO.Directory]::CreateDirectory((Join-Path $kasa $d)) }
[void][IO.Directory]::CreateDirectory((Join-Path $kok 'Gunluk'))
# gecmis-okuyucu bilerek kopyalanmaz: test gercek tarayici gecmisini okumasin
foreach ($f in 'api.ps1', 'mcp.ps1', 'gunluk-rapor.ps1', 'kurallar.json', 'ayarlar.json', 'durum.json', 'gecmis.json', 'periyot.json', 'log.txt') { Copy-Item (Join-Path $hDir $f) $kasa }
foreach ($f in "aktivite\$dun.csv", "rapor\$dun.json") { if (Test-Path (Join-Path $hDir $f)) { Copy-Item (Join-Path $hDir $f) (Join-Path $kasa $f) } }
$env:TAKIP_KASA = $kasa
$api = Join-Path $kasa 'api.ps1'
function Api { $j = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $api @args; $script:kod = $LASTEXITCODE; try { return ($j | ConvertFrom-Json) } catch { return $null } }

Write-Host "`n=== 1. DOSYA ===" -ForegroundColor Cyan
foreach ($f in 'api.ps1', 'mcp.ps1') {
    $p = Join-Path $hDir $f; $e = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($p, [ref]$null, [ref]$e)
    T "$f sozdizimi" ($e.Count -eq 0) "$($e.Count) hata"
    $b = [IO.File]::ReadAllBytes($p); T "$f UTF-8 BOM" ($b[0] -eq 0xEF -and $b[1] -eq 0xBB -and $b[2] -eq 0xBF) 'Turkce metin icin gerekli'
}

Write-Host "`n=== 2. KOMUT SATIRI ===" -ForegroundColor Cyan
$o = Api durum
T 'durum: JSON + cikis 0' ($o -and $kod -eq 0) "dakika=$($o.dakika) hedef=$($o.hedef) seri=$($o.seri)"
T 'durum: saglik alani' ($null -ne $o.saglik.durum) "$($o.saglik.durum)"
$o = Api yok
T 'bilinmeyen komut: hata + cikis 1' ($o.hata -and $kod -eq 1) "$($o.hata)"
$o = Api rapor -Tarih $dun
T 'rapor (dun)' ($o -and $kod -eq 0) "var=$($o.var) bekleyen=$(@($o.bekleyen).Count)"
$o = Api brifing
T 'brifing: metin' ($o.metin -match 'Takip:') "$($o.metin.Length) karakter"
T 'brifing: -Kaydet olmadan gunluge yazmaz' (-not (Test-Path (Join-Path $kok "Gunluk\$bugun.md"))) ''

Write-Host "`n=== 3. GUNLUK BLOKLARI ===" -ForegroundColor Cyan
$gb = Join-Path $kok "Gunluk\$bugun.md"
$null = Api brifing -Kaydet; $o = Api brifing -Kaydet
T 'bugunun gunlugu olustu' (Test-Path $gb) "$($o.gunluk.bugun)"
T 'iki kez calisinca tek blok' (([regex]::Matches([IO.File]::ReadAllText($gb), '<!-- otomatik:sabah -->')).Count -eq 1) ''
if ($null -ne $o.dun.dakika) { T 'dunun gunlugune gun sonu blogu' ([IO.File]::ReadAllText((Join-Path $kok "Gunluk\$dun.md")).Contains('<!-- otomatik:gun-sonu -->')) '' }
[IO.File]::WriteAllText($gb, "# elle`r`n`r`n## Sabah kontrol" + [char]0x00FC + "`r`n`r`nelle yazildi`r`n")
$once = [IO.File]::ReadAllText($gb); $o = Api brifing -Kaydet
T 'elle yazilmis bolume dokunmaz' ([IO.File]::ReadAllText($gb) -eq $once) "$($o.gunluk.bugun)"

Write-Host "`n=== 4. SINIFLANDIR ===" -ForegroundColor Cyan
$kj = Join-Path $kasa 'kurallar.json'
function K { Get-Content $kj -Raw -Encoding UTF8 | ConvertFrom-Json }
$o = Api siniflandir -Oge 'testuyg' -Karar yasakli
T 'yasakli eklendi' ($o.tamam -and (@((K).yasakli.surec) -contains 'testuyg')) ''
$null = Api siniflandir -Oge 'testuyg' -Karar calisma; $k = K
T 'karar degisince tasindi' ((@($k.calisma.surec) -contains 'testuyg') -and -not (@($k.yasakli.surec) -contains 'testuyg')) ''
T 'tekrar eklenmez' (@(@($k.calisma.surec) | Where-Object { $_ -eq 'testuyg' }).Count -eq 1) ''
$null = Api siniflandir -Oge 'testuyg' -Karar belirsiz; $k = K
T 'bilerek belirsiz' ((@($k.bilerekBelirsiz) -contains 'testuyg') -and -not (@($k.calisma.surec) -contains 'testuyg')) ''
T 'yedek alindi' (Test-Path "$kj.bak") ''
T 'log satiri yazildi' ((Get-Content (Join-Path $kasa 'log.txt') -Tail 1) -match 'kural \(api\)') ''
$o = Api siniflandir -Oge 'x' -Karar hepsi
T 'gecersiz karar reddedilir' ($o.hata -and $kod -eq 1) "$($o.hata)"
$r = Api rapor -Tarih $dun
if (@($r.bekleyen).Count) {
    $ilk = @($r.bekleyen)[0]; $tur = 'surec'; if ($ilk.tur -eq 'alanadi') { $tur = 'alanadi' }
    $null = Api siniflandir -Oge $ilk.ad -Karar belirsiz -Tur $tur
    $r2 = Api rapor -Tarih $dun
    T 'karara baglanan oge bir daha sorulmaz' (-not (@(@($r2.bekleyen) | ForEach-Object { $_.ad }) -contains $ilk.ad)) "$($ilk.ad)"
}
# Veriye bagli olmayan alan adi testi: ustteki test gercek rapordaki ilk soruya bakip 'belirsiz'
# karari verir; calisma/yasakli alan adi kararinin suzulmedigini bu yuzden kacirmisti.
$sahteT = '2000-01-01'
[IO.File]::WriteAllText((Join-Path $kasa "rapor\$sahteT.json"), '{"tarih":"2000-01-01","calismaDk":0,"digerDk":0,"bostaDk":0,"hedefDk":240,"uygulamalar":[],"incelenecekUygulamalar":[{"ad":"kisa-test-uyg","dakika":2,"ornekBaslik":"Kisa test"}],"incelenecekAlanlar":[{"alan":"ornek-test.example","ziyaret":99},{"alan":"alt.ornek-test.example","ziyaret":99},{"alan":"yasak-test.example","ziyaret":99}],"enCokBakilan":[],"alanlar":[],"aramalar":[]}')
$r = Api rapor -Tarih $sahteT
T 'sahte rapor: 3 alan adi sorusu' (@(@($r.bekleyen) | Where-Object { $_.tur -eq 'alanadi' }).Count -eq 3) "$(@($r.bekleyen).Count) soru"
$null = Api siniflandir -Oge 'ornek-test.example' -Karar calisma -Tur alanadi
$null = Api siniflandir -Oge 'yasak-test.example' -Karar yasakli -Tur alanadi
$r = Api rapor -Tarih $sahteT
T 'alan adi karari sorulmaz (alt alan dahil)' (@($r.bekleyen).Count -eq 0) "$(@(@($r.bekleyen) | ForEach-Object { $_.ad }) -join ', ')"
# Rapor penceresinin Incelenecek sekmesi ayni suzmeyi kullanir ve esik altindaki ogeleri de gosterir
$yolS = Join-Path $kasa "rapor\$sahteT.json"
$j = (& powershell.exe -NoProfile -ExecutionPolicy Bypass -Command ". '$api'; ConvertTo-Json -InputObject @(Tk-Incelenecekler (Tk-Json '$yolS')) -Compress") | Out-String
$ti = @((ConvertFrom-Json $j) | Where-Object { $_ })
T 'incelenecek sekmesi: esik alti oge + tur' ($ti.Count -eq 1 -and $ti[0].tur -eq 'surec' -and $ti[0].ad -eq 'kisa-test-uyg' -and $ti[0].dk -eq 2) "$($ti.Count) oge"

Write-Host "`n=== 5. MCP ===" -ForegroundColor Cyan
$mesajlar = @(
    '{"jsonrpc":"2.0","id":0,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"test","version":"0"}}}'
    '{"jsonrpc":"2.0","method":"notifications/initialized"}'
    '{"jsonrpc":"2.0","id":1,"method":"tools/list"}'
    '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"takip_durum","arguments":{}}}'
    '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"sabah_brifingi","arguments":{"kaydet":false}}}'
    '{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"yok_boyle","arguments":{}}}'
    '{"jsonrpc":"2.0","id":5,"method":"bilinmeyen/metot"}'
    '{"jsonrpc":"2.0","id":"s6","method":"ping"}'
)
$sw = [Diagnostics.Stopwatch]::StartNew()
$satirlar = @($mesajlar | & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $kasa 'mcp.ps1'))
$sw.Stop()
T 'istek basina tek satir, bildirime cevap yok' ($satirlar.Count -eq 7) "$($satirlar.Count) satir, $([math]::Round($sw.Elapsed.TotalSeconds, 1)) sn"
$c = @{}; $bozuk = 0
foreach ($s in $satirlar) { try { $x = $s | ConvertFrom-Json -ErrorAction Stop; $c[[string]$x.id] = $x } catch { $bozuk++ } }
T 'tum satirlar gecerli JSON' ($bozuk -eq 0) "$bozuk bozuk"
T 'initialize: surum eslesmesi' ($c['0'].result.protocolVersion -eq '2025-06-18') "$($c['0'].result.serverInfo.name)"
T 'tools/list: 4 arac' (@($c['1'].result.tools).Count -eq 4) ((@($c['1'].result.tools) | ForEach-Object { $_.name }) -join ', ')
$d = $null; try { $d = $c['2'].result.content[0].text | ConvertFrom-Json } catch { }
T 'takip_durum: JSON dondu' ($null -ne $d.dakika) "dakika=$($d.dakika)"
T 'sabah_brifingi: metin + JSON' (@($c['3'].result.content).Count -eq 2 -and $c['3'].result.content[0].text -match 'Takip:') ''
T 'bilinmeyen arac: -32602' ($c['4'].error.code -eq -32602) ''
T 'bilinmeyen metot: -32601' ($c['5'].error.code -eq -32601) ''
T 'metin id korunur (ping)' ($null -ne $c['s6'].result) ''

Write-Host "`n=== 6. GUNAYDIN HOOK (gunaydin.ps1) ===" -ForegroundColor Cyan
Copy-Item (Join-Path $hDir 'gunaydin.ps1') $kasa
$hk = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $kasa 'gunaydin.ps1')
$hj = $null; try { $hj = $hk | ConvertFrom-Json } catch { }
T 'hook: gecerli JSON' ($null -ne $hj) ''
$bg = [string]$hj.hookSpecificOutput.additionalContext
T 'hook: UserPromptSubmit + hazir ozet' ($hj.hookSpecificOutput.hookEventName -eq 'UserPromptSubmit' -and $bg -match 'GUNLUK CALISMA' -and $bg -match 'Takip:') "$($hj.systemMessage)"

Write-Host "`n=== 7. ARAYUZ ===" -ForegroundColor Cyan
foreach ($f in 'tema.ps1', 'kontrol.ps1', 'rapor-penceresi.ps1', 'engel.ps1', 'onizleme.ps1', 'takip.ps1', 'ozellikler.ps1', 'wiki.ps1', 'ayarlar-penceresi.ps1', 'wiki-penceresi.ps1') {
    $p = Join-Path $hDir $f; $e = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($p, [ref]$null, [ref]$e)
    $b = [IO.File]::ReadAllBytes($p); $bom = ($b[0] -eq 0xEF -and $b[1] -eq 0xBB -and $b[2] -eq 0xBF)
    $turkce = @($b | Where-Object { $_ -gt 127 }).Count -gt 3
    T "$f sozdizimi + kodlama" ($e.Count -eq 0 -and ($bom -or -not $turkce)) "hata=$($e.Count) BOM=$bom"
}
$oz = Join-Path $kok 'onizleme'
$null = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $hDir 'onizleme.ps1') -Klasor $oz
foreach ($png in 'kontrol', 'rapor-penceresi', 'rapor-incelenecek', 'uyari', 'uyari-pencere', 'engel', 'ayarlar-penceresi', 'wiki-penceresi') {
    $pp = Join-Path $oz "$png.png"; $var = Test-Path $pp; $kb = 0; if ($var) { $kb = [math]::Round((Get-Item $pp).Length / 1KB) }
    T "onizleme: $png.png" ($var -and $kb -gt 5) "$kb KB"
}

Remove-Item Env:TAKIP_KASA
Remove-Item $kok -Recurse -Force
$renk = 'Green'; if ($kaldi) { $renk = 'Red' }
Write-Host ("`n{0} gecti, {1} hata" -f $gecti, $kaldi) -ForegroundColor $renk
exit $kaldi
