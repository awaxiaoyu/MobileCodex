[CmdletBinding()]
param(
    [string]$Address = '127.0.0.1',
    [int]$MobilePort = 37842,
    [string]$Workspace = (Get-Location).Path,
    [string]$PublicUrl,
    [switch]$ReadOnly
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$dataRoot = if ($env:LOCALAPPDATA) { Join-Path $env:LOCALAPPDATA 'MobileCodexBridge' } else { Join-Path $root 'data' }
$tlsRoot = Join-Path $dataRoot '.local/tls'
$certificate = Join-Path $tlsRoot 'cert.pem'
$key = Join-Path $tlsRoot 'key.pem'
$exe = Join-Path $root 'MobileCodexBridge.exe'

if (-not (Test-Path -LiteralPath $exe)) { throw "MobileCodexBridge.exe not found beside this script: $root" }
if (-not (Test-Path -LiteralPath $certificate) -or -not (Test-Path -LiteralPath $key)) {
    New-Item -ItemType Directory -Force -Path $tlsRoot | Out-Null
    & openssl req -x509 -newkey rsa:3072 -sha256 -nodes -keyout $key -out $certificate -days 365 -subj '/CN=MobileCodex Bridge' -addext "subjectAltName=DNS:localhost,IP:127.0.0.1"
    if ($LASTEXITCODE -ne 0) { throw 'OpenSSL certificate generation failed. Install OpenSSL or provide cert.pem/key.pem manually.' }
}

$env:MOBILE_CODEX_DATA_DIR = $dataRoot
$pairUrl = if ($PublicUrl) { $PublicUrl } else { "wss://${Address}:${MobilePort}/ws" }
$arguments = @('serve', '--frida', '--workspace', $Workspace, '--tls-cert', $certificate, '--tls-key', $key, '--mobile-bind', $Address, '--mobile-port', "$MobilePort", '--pair-url', $pairUrl)
if (-not $ReadOnly) { $arguments += '--allow-control' }
Push-Location $root
try { & $exe @arguments } finally { Pop-Location }
