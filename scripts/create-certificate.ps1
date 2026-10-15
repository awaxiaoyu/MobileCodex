param([string]$Directory = '.local/tls')
$ErrorActionPreference = 'Stop'
$target = [System.IO.Path]::GetFullPath($Directory)
New-Item -ItemType Directory -Force -Path $target | Out-Null
$certificate = Join-Path $target 'cert.pem'
$key = Join-Path $target 'key.pem'
if ((Test-Path -LiteralPath $certificate) -or (Test-Path -LiteralPath $key)) { throw 'Certificate already exists; select a different directory to generate a new identity.' }
& openssl req -x509 -newkey rsa:3072 -sha256 -nodes -keyout $key -out $certificate -days 365 -subj '/CN=MobileCodex Bridge' -addext "subjectAltName=DNS:localhost,IP:127.0.0.1"
if ($LASTEXITCODE -ne 0) { throw 'OpenSSL certificate generation failed' }
Write-Output "Generated $certificate"
