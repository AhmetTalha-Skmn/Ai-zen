# Development-only, deterministic public test vectors. Never uses real device data.
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$destination = Join-Path $root 'Tests\CalismaTakipTests\Fixtures\windows-protocol.json'
[void][IO.Directory]::CreateDirectory((Split-Path -Parent $destination))
$code = 'ABCD1234EFGH'
[byte[]]$salt = 16..31
[byte[]]$iv = 32..47
[byte[]]$key = 0..31
$derive = [Security.Cryptography.Rfc2898DeriveBytes]::new($code, $salt, 120000, [Security.Cryptography.HashAlgorithmName]::SHA256)
try { [byte[]]$derived = $derive.GetBytes(64) } finally { $derive.Dispose() }
$aes = [Security.Cryptography.Aes]::Create()
$aes.Mode = [Security.Cryptography.CipherMode]::CBC
$aes.Padding = [Security.Cryptography.PaddingMode]::PKCS7
$aes.Key = [byte[]]$derived[0..31]
$aes.IV = $iv
$plain = [Text.Encoding]::UTF8.GetBytes([Convert]::ToBase64String($key))
try {
    $transform = $aes.CreateEncryptor()
    try { $cipher = $transform.TransformFinalBlock($plain, 0, $plain.Length) }
    finally { $transform.Dispose() }
} finally { $aes.Dispose() }
function Get-Mac([byte[]]$Data, [byte[]]$KeyBytes) {
    $h = [Security.Cryptography.HMACSHA256]::new()
    $h.Key = $KeyBytes
    try { return ,$h.ComputeHash($Data) } finally { $h.Dispose() }
}
$tag = Get-Mac -Data ([byte[]]($iv + $cipher)) -KeyBytes ([byte[]]$derived[32..63])
$timestamp = '1789552800'
$body = '{"cihazAdi":"Mac ' + [char]0x00c7 + 'al' + [char]0x0131 + [char]0x015f + 'ma","sira":7}'
$signature = Get-Mac -Data ([Text.Encoding]::UTF8.GetBytes($timestamp + [char]10 + $body)) -KeyBytes $key
$path = '/v1/toplam?tarih=2026-09-16'
$getSignature = Get-Mac -Data ([Text.Encoding]::UTF8.GetBytes($timestamp + [char]10 + $path)) -KeyBytes $key
$fixture = [ordered]@{
    generator = 'Windows .NET PBKDF2-SHA256 / AES-256-CBC / HMAC-SHA256'
    code = $code
    key = [Convert]::ToBase64String($key)
    derived = [Convert]::ToBase64String($derived)
    packet = [ordered]@{
        tuz = [Convert]::ToBase64String($salt)
        iv = [Convert]::ToBase64String($iv)
        veri = [Convert]::ToBase64String($cipher)
        etiket = [Convert]::ToBase64String($tag)
    }
    timestamp = $timestamp
    body = $body
    signature = ([BitConverter]::ToString($signature)).Replace('-', '').ToLowerInvariant()
    path = $path
    getSignature = ([BitConverter]::ToString($getSignature)).Replace('-', '').ToLowerInvariant()
}
$json = ($fixture | ConvertTo-Json -Depth 8).Replace([string][char]13, '') + [char]10
[IO.File]::WriteAllText($destination, $json, [Text.UTF8Encoding]::new($false))
Write-Output 'Deterministic Windows protocol fixture generated.'
