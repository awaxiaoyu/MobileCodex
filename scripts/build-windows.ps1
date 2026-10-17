[CmdletBinding()]
param(
    [string]$OutputDirectory = 'dist/MobileCodexBridge',
    [switch]$SkipPythonRuntime
)

$ErrorActionPreference = 'Stop'
$repo = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$output = [System.IO.Path]::GetFullPath((Join-Path $repo $OutputDirectory))
$app = Join-Path $output 'app'
$appNodeModules = Join-Path $app 'node_modules'
$runtime = Join-Path $output 'runtime'
$temp = Join-Path $repo '.local/pack-windows'
$node = (Get-Command node -ErrorAction Stop).Source
$nodeExe = [System.IO.Path]::GetFullPath($node)
$python = if ($env:MOBILE_CODEX_FRIDA_PYTHON) { $env:MOBILE_CODEX_FRIDA_PYTHON } else { Join-Path $env:USERPROFILE '.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe' }
$fridaDeps = if ($env:MOBILE_CODEX_FRIDA_DEPS) { $env:MOBILE_CODEX_FRIDA_DEPS } else { Join-Path $repo '.local/frida' }

if (-not $SkipPythonRuntime) {
    if (-not (Test-Path -LiteralPath $python)) { throw "Python runtime not found: $python. Set MOBILE_CODEX_FRIDA_PYTHON or use -SkipPythonRuntime." }
    if (-not (Test-Path -LiteralPath (Join-Path $fridaDeps 'frida'))) { throw "Frida package not found: $fridaDeps. Set MOBILE_CODEX_FRIDA_DEPS." }
}

New-Item -ItemType Directory -Force -Path $temp, $app, $runtime | Out-Null
Remove-Item -LiteralPath $output -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path $app, $runtime | Out-Null

Push-Location $repo
try {
    & pnpm exec esbuild src/cli.ts --bundle --platform=node --format=esm --target=node24 --external:ws --external:qrcode ("--outfile=" + (Join-Path $app 'bridge.mjs'))
    if ($LASTEXITCODE -ne 0) { throw 'esbuild failed.' }

    # FridaBackend resolves the helper relative to MOBILE_CODEX_APP_ROOT/scripts.
    # Keep the packaged layout identical to the source checkout.
    $appScripts = Join-Path $app 'scripts'
    New-Item -ItemType Directory -Force -Path $appScripts | Out-Null
    Copy-Item -LiteralPath (Join-Path $repo 'scripts/frida-bridge.py') -Destination $appScripts -Force
    Copy-Item -LiteralPath (Join-Path $repo 'scripts/start-portable.ps1') -Destination (Join-Path $output 'Start-MobileCodexBridge.ps1') -Force
    Copy-Item -LiteralPath (Join-Path $repo 'adapters') -Destination $app -Recurse -Force
    Copy-Item -LiteralPath (Join-Path $repo 'schemas') -Destination $app -Recurse -Force
    New-Item -ItemType Directory -Force -Path $appNodeModules | Out-Null
    Copy-Item -LiteralPath (Join-Path $repo 'node_modules/.pnpm/ws@8.22.0/node_modules/ws') -Destination $appNodeModules -Recurse -Force
    Copy-Item -LiteralPath (Join-Path $repo 'node_modules/.pnpm/qrcode@1.5.4/node_modules/qrcode') -Destination $appNodeModules -Recurse -Force
    Copy-Item -LiteralPath (Join-Path $repo 'node_modules/.pnpm/dijkstrajs@1.0.3/node_modules/dijkstrajs') -Destination $appNodeModules -Recurse -Force
    Copy-Item -LiteralPath (Join-Path $repo 'node_modules/.pnpm/pngjs@5.0.0/node_modules/pngjs') -Destination $appNodeModules -Recurse -Force

    $launcher = Join-Path $temp 'portable-launcher.cjs'
    Copy-Item -LiteralPath (Join-Path $repo 'scripts/portable-launcher.cjs') -Destination $launcher -Force
    $seaConfig = Join-Path $temp 'sea-config.json'
    $blob = Join-Path $temp 'bridge.blob'
    $config = [ordered]@{
        main = $launcher
        output = $blob
        disableExperimentalSEAWarning = $true
        useSnapshot = $false
        useCodeCache = $false
    }
    $config | ConvertTo-Json | Set-Content -LiteralPath $seaConfig -Encoding utf8
    & $node --experimental-sea-config=$seaConfig
    if ($LASTEXITCODE -ne 0) { throw 'Node SEA blob generation failed.' }

    $exe = Join-Path $output 'MobileCodexBridge.exe'
    Copy-Item -LiteralPath $nodeExe -Destination $exe -Force
    & pnpm exec postject $exe NODE_SEA_BLOB $blob --sentinel-fuse NODE_SEA_FUSE_fce680ab2cc467b6e072b8b5df1996b2
    if ($LASTEXITCODE -ne 0) { throw 'SEA resource injection failed.' }

    if (-not $SkipPythonRuntime) {
        $pythonDestination = Join-Path $runtime 'python'
        New-Item -ItemType Directory -Force -Path $pythonDestination | Out-Null
        $pythonRoot = Split-Path -Parent $python
        Copy-Item -Path (Join-Path $pythonRoot '*') -Destination $pythonDestination -Recurse -Force
        Copy-Item -LiteralPath $fridaDeps -Destination (Join-Path $runtime 'frida') -Recurse -Force
    }

    $manifest = [ordered]@{
        product = 'MobileCodexBridge'
        version = (Get-Content (Join-Path $repo 'package.json') -Raw | ConvertFrom-Json).version
        node = (& $node --version).Trim()
        frida = if ($SkipPythonRuntime) { 'external' } else { '17.23.3' }
        executable = 'MobileCodexBridge.exe'
        runtime = if ($SkipPythonRuntime) { 'Set MOBILE_CODEX_FRIDA_PYTHON and MOBILE_CODEX_FRIDA_DEPS before starting.' } else { 'bundled-python-frida' }
    }
    $manifest | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $output 'manifest.json') -Encoding utf8
    Write-Output "Built $exe"
} finally {
    Pop-Location
}
