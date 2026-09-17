# Read-only compatibility check. Imports ONLY named pure crypto functions from source.
param([Parameter(Mandatory = $true)][string]$OrtakPath)
$ErrorActionPreference = 'Stop'
$tokens = $null
$parseErrors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile($OrtakPath, [ref]$tokens, [ref]$parseErrors)
if ($parseErrors.Count) { throw 'Windows source has parse errors.' }
$names = @('Get-DagitikDeger', 'Get-DagitikHmac', 'ConvertTo-DagitikKodNormal', 'Get-DagitikKodAnahtari', 'Test-DagitikBaytEsitlik', 'Unprotect-DagitikKodIle')
foreach ($name in $names) {
    $function = $ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $name }, $true)
    if (@($function).Count -ne 1) { throw "Function absent or ambiguous: $name" }
    . ([scriptblock]::Create($function.Extent.Text))
}
$fixturePath = Join-Path (Split-Path -Parent $PSScriptRoot) 'Tests\CalismaTakipTests\Fixtures\windows-protocol.json'
$f = Get-Content -LiteralPath $fixturePath -Raw -Encoding UTF8 | ConvertFrom-Json
if ((ConvertTo-DagitikKodNormal ' abci-l0o1-2345 ') -cne 'ABC110012345') { throw 'Normalization mismatch.' }
$derived = [Convert]::ToBase64String([byte[]](Get-DagitikKodAnahtari -Kod $f.code -Tuz $f.packet.tuz -Uzunluk 64))
if ($derived -cne $f.derived) { throw 'Derivation mismatch.' }
if ((Get-DagitikHmac -Anahtar $f.key -ZamanDamgasi $f.timestamp -Govde $f.body) -cne $f.signature) { throw 'POST signature mismatch.' }
if ((Get-DagitikHmac -Anahtar $f.key -ZamanDamgasi $f.timestamp -Govde $f.path) -cne $f.getSignature) { throw 'GET signature mismatch.' }
if ((Unprotect-DagitikKodIle -Paket $f.packet -Kod $f.code -Tuz $f.packet.tuz) -cne $f.key) { throw 'Envelope mismatch.' }
$rejected = $false
try { [void](Unprotect-DagitikKodIle -Paket $f.packet -Kod 'WRONGCODE123' -Tuz $f.packet.tuz) }
catch { $rejected = $true }
if (-not $rejected) { throw 'Wrong code accepted.' }
Write-Output 'PASS: 6 checks against real Windows pure functions. No source or user data modified.'
