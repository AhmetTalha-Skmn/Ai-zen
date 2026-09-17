<#
Bir bilgisayarin kurallar.json dosyasini merkezin ortak kural kumesine katar.
Ilk doldurma icindir: merkez kurulduktan sonra yoneticinin kendi kurallarini
bir kere aktarir, sonrasinda cihazlar kararlari kendileri iter.

Yalnizca ekler; merkezdeki hicbir karar silinmez. aslaEngelleme tasinmaz.

Kullanim:
  .\kural-aktar.ps1                                   yerel hatirlatici\kurallar.json
  .\kural-aktar.ps1 -Kaynak D:\yedek\kurallar.json
#>
param(
    [string]$Kaynak,
    [string]$KuralYolu
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Ortak.ps1')
. (Join-Path $PSScriptRoot 'Merkez-Kural.ps1')

if ([string]::IsNullOrWhiteSpace($KuralYolu)) { $KuralYolu = Join-Path $PSScriptRoot 'merkez-kurallar.json' }
if ([string]::IsNullOrWhiteSpace($Kaynak)) {
    $Kaynak = Join-Path (Join-Path (Get-DagitikUygulamaKok $PSScriptRoot) 'hatirlatici') 'kurallar.json'
}
if (-not (Test-Path -LiteralPath $Kaynak)) { throw "Kaynak kural dosyasi bulunamadi: $Kaynak" }

$kaynakKural = Read-DagitikJson $Kaynak
if ($null -eq $kaynakKural) { throw 'Kaynak kural dosyasi okunamadi.' }

Invoke-MerkezDosyaKilidi $KuralYolu {
$merkezKural = Get-MerkezKurallari -Yol $KuralYolu
$onceki = Get-MerkezKuralOzeti $merkezKural
$eklenen = Merge-MerkezKurallari -Kurallar $merkezKural -Kaynak $kaynakKural
Write-DagitikJsonAtomik -Nesne $merkezKural -Yol $KuralYolu

Write-Output "Kaynak     : $Kaynak"
Write-Output "Ortak kume : $KuralYolu"
Write-Output "Eklenen    : $eklenen kural (onceki $onceki, simdi $(Get-MerkezKuralOzeti $merkezKural))"
Write-Output 'Cihazlar bir sonraki gonderim turunda bu kurallari alir.'

}
