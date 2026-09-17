# SADECE bos Windows test makinesi/VM. EXE sihirbazi elle tamamlanir.
[CmdletBinding()]
param(
 [Parameter(Mandatory=$true)][string]$PaketExe,
 [Parameter(Mandatory=$true)][string]$PaketZip,
 [switch]$IzoleMakine,
 [string]$KurulumDizini = (Join-Path $env:LOCALAPPDATA 'CalismaTakipSistemi')
)
$ErrorActionPreference='Stop'
if (-not $IzoleMakine) { throw 'Yalnız boş test makinesinde -IzoleMakine ile çalıştırın.' }
$kimlik=[Security.Principal.WindowsIdentity]::GetCurrent()
if (-not (New-Object Security.Principal.WindowsPrincipal($kimlik)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { throw 'Test makinesinde yönetici PowerShell açın.' }
if (Test-Path -LiteralPath $KurulumDizini) { throw 'Temiz test için kurulum dizini mevcut olmamalı.' }
if (@(Get-ScheduledTask | Where-Object { $_.TaskName -like 'Calisma Takip*' }).Count -gt 0) { throw 'Mevcut takip görevleri var; test durduruldu.' }
$arp='HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\CalismaTakipSistemi'
if (Test-Path $arp) { throw 'Mevcut uygulama kaydı var; test durduruldu.' }
$PaketExe=(Resolve-Path -LiteralPath $PaketExe).Path
$PaketZip=(Resolve-Path -LiteralPath $PaketZip).Path
$calisma=Join-Path $env:TEMP ('ct-gercek-'+[guid]::NewGuid().ToString('N').Substring(0,8))
[void][IO.Directory]::CreateDirectory($calisma)
$rapor=Join-Path $calisma 'SONUC.txt'
$psExe="$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
$sunucu=$null
function Dogrula([string]$Ad,[bool]$Kosul) {
 if (-not $Kosul) { throw "BAŞARISIZ: $Ad" }
 Add-Content -LiteralPath $rapor -Encoding UTF8 -Value "GEÇTİ: $Ad"
 Write-Output "GEÇTİ: $Ad"
}
function Calistir([string]$Betik,[string[]]$Ek) {
 $argumanlar=@('-NoProfile','-ExecutionPolicy','Bypass','-File',$Betik)+$Ek
 & $psExe $argumanlar | Out-Host
 if ($LASTEXITCODE -ne 0) { throw "Betik başarısız: $Betik (kod $LASTEXITCODE)" }
}
try {
 Write-Output "EXE sihirbazında Kullanıcı rolü, bağlantısız kurulum ve şu dizini seçin: $KurulumDizini"
 Write-Output 'Kurulum tamamlanınca sihirbazı kapatın.'
 $sihirbaz=Start-Process -FilePath $PaketExe -PassThru
 $sihirbaz.WaitForExit()
 $h=Join-Path $KurulumDizini 'hatirlatici'; $d=Join-Path $KurulumDizini 'dagitik'
 Dogrula 'EXE sihirbazı kurdu' (Test-Path (Join-Path $h 'kurallar.json'))
 Dogrula 'Takip görevi kuruldu' ($null -ne (Get-ScheduledTask -TaskName 'Calisma Takip Sistemi' -ErrorAction SilentlyContinue))
 Dogrula 'Windows kaydı oluştu' (Test-Path $arp)
 . (Join-Path $d 'Ortak.ps1')
 $merkezAyar=Join-Path $calisma 'merkez-ayarlari.json'
 $url='http://127.0.0.1:'+(Get-Random -Minimum 30000 -Maximum 39000)
 $kodSatirlari=@(& $psExe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $d 'cihaz-ekle.ps1') -Ad 'Test cihazı' -CihazKimligi 'gercek-test-pc' -SunucuUrl $url -YapilandirmaYolu $merkezAyar -KuralYazabilir)
 Dogrula 'Eşleşme kodu üretildi' ($LASTEXITCODE -eq 0)
 $kod=[regex]::Match(($kodSatirlari -join ' '),'[0-9A-HJKMNP-TV-Z]{4}-[0-9A-HJKMNP-TV-Z]{4}-[0-9A-HJKMNP-TV-Z]{4}')
 if (-not $kod.Success) { throw 'Eşleşme kodu ayrıştırılamadı.' }
 $sunucuArg=@('-NoProfile','-ExecutionPolicy','Bypass','-File',('"'+(Join-Path $d 'merkez-sunucu.ps1')+'"'),'-YapilandirmaYolu',('"'+$merkezAyar+'"'),'-VeriKlasoru',('"'+(Join-Path $calisma 'veri')+'"'),'-DinlemeOnEki',("$url/"))
 $sunucu=Start-Process $psExe -ArgumentList $sunucuArg -WindowStyle Hidden -PassThru
 $hazir=$false
 for($i=0;$i -lt 20;$i++) {
  try { [void](Invoke-WebRequest "$url/health" -UseBasicParsing -TimeoutSec 1);$hazir=$true;break } catch { Start-Sleep -Milliseconds 500 }
 }
 Dogrula 'Merkez hazır' $hazir
 Calistir (Join-Path $d 'istemci-kayit.ps1') @('-SunucuUrl',$url,'-Kod',$kod.Value,'-HatirlaticiKlasoru',$h,'-Onayla','-Sessiz')
 Dogrula 'Onay kaydı yazıldı' (Test-Path (Join-Path $h 'onay.json'))
 Dogrula 'Gönderici görevi kuruldu' ($null -ne (Get-ScheduledTask -TaskName 'Calisma Takip Gonderici' -ErrorAction SilentlyContinue))
 Calistir (Join-Path $d 'istemci-gonderici.ps1') @('-HatirlaticiKlasoru',$h)
 Dogrula 'Merkez özeti aldı' (Test-Path (Join-Path $calisma 'veri\guncel\gercek-test-pc.json'))
 $once=(Get-FileHash (Join-Path $h 'kurallar.json')).Hash
 $paket=Join-Path $calisma 'paket'
 Expand-Archive -LiteralPath $PaketZip -DestinationPath $paket
 Calistir (Join-Path $paket 'Kurulum.ps1') @('-Rol','Kullanici','-Sessiz','-KurulumDizini',$KurulumDizini)
 Dogrula 'Güncelleme kuralları korudu' ($once -eq (Get-FileHash (Join-Path $h 'kurallar.json')).Hash)
 Dogrula 'Güncelleme merkez kaydını korudu' (Test-Path (Join-Path $h 'merkez.json'))
 Calistir (Join-Path $d 'kaldir.ps1') @('-UygulamaKok',$KurulumDizini,'-Onayla','-VeriyiDeSil')
 Dogrula 'Görevler kaldırıldı' (@(Get-ScheduledTask | Where-Object { $_.TaskName -like 'Calisma Takip*' }).Count -eq 0)
 Dogrula 'Windows kaydı kaldırıldı' (-not (Test-Path $arp))
 Dogrula 'Ölçüm verisi silindi' (-not (Test-Path (Join-Path $h 'aktivite')))
 Write-Output "Test tamamlandı. Kanıt: $rapor"
}
catch { Add-Content -LiteralPath $rapor -Encoding UTF8 -Value ("BAŞARISIZ: "+$_.Exception.Message); throw }
finally {
 if ($null -ne $sunucu -and -not $sunucu.HasExited) { $sunucu.Kill(); $sunucu.WaitForExit() }
 Write-Output "Test dosyaları ve rapor korundu: $calisma"
}