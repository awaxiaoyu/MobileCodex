param([string]$Address = '127.0.0.1', [int]$MobilePort = 37842, [string]$PublicUrl, [switch]$ReadOnly)
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$python = Join-Path $env:USERPROFILE '.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe'
if (-not $env:MOBILE_CODEX_FRIDA_PYTHON) {
    if (-not (Test-Path -LiteralPath $python)) { throw 'Set MOBILE_CODEX_FRIDA_PYTHON to a Windows Python 3.12+ executable.' }
    $env:MOBILE_CODEX_FRIDA_PYTHON = $python
}
if (-not $env:MOBILE_CODEX_FRIDA_DEPS) { $env:MOBILE_CODEX_FRIDA_DEPS = Join-Path $repo '.local/frida' }
if (-not (Test-Path -LiteralPath (Join-Path $env:MOBILE_CODEX_FRIDA_DEPS 'frida'))) { throw 'Install Frida 17.23.3 into .local/frida; see README.' }
$certificate = Join-Path $repo '.local/tls/cert.pem'
$key = Join-Path $repo '.local/tls/key.pem'
$pairUrl = if ($PublicUrl) { $PublicUrl } else { "wss://${Address}:${MobilePort}/ws" }
$arguments = @('src/cli.ts', 'serve', '--frida', '--tls-cert', $certificate, '--tls-key', $key, '--mobile-port', "$MobilePort", '--pair-url', $pairUrl)
if (-not $ReadOnly) { $arguments += '--allow-control' }
Push-Location $repo
try {
    if (-not (Test-Path -LiteralPath $certificate)) { & (Join-Path $PSScriptRoot 'create-certificate.ps1') }
    & node @arguments
} finally { Pop-Location }
