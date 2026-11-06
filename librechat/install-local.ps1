# Sets up LibreChat + Kape Lumen on this PC. Safe to run more than once.
# Usage (from the project root, in PowerShell):   .\librechat\install-local.ps1
# Needs: Git and Docker Desktop (running).

$ErrorActionPreference = 'Stop'
$root     = Split-Path -Parent $PSScriptRoot
$vendor   = Join-Path $root 'vendor\LibreChat'
$envFile  = Join-Path $vendor '.env'

if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
  throw 'Docker is not installed or not on PATH. Install Docker Desktop first (docs/SETUP-LOCAL.md, step 1).'
}

# 1. Get LibreChat (kept in vendor/, which is gitignored)
if (-not (Test-Path $vendor)) {
  Write-Host '==> Cloning LibreChat into vendor/LibreChat'
  git clone https://github.com/danny-avila/LibreChat.git $vendor
}
$version = git -C $vendor describe --tags --always
Write-Host "==> LibreChat version: $version   (record this in CREDITS.md)"

# 2. Our compose override
Copy-Item (Join-Path $PSScriptRoot 'docker-compose.override.yml') (Join-Path $vendor 'docker-compose.override.yml') -Force
Write-Host '==> Copied docker-compose.override.yml'

# 3. .env: start from LibreChat's example, then add our settings once
if (-not (Test-Path $envFile)) {
  Copy-Item (Join-Path $vendor '.env.example') $envFile
  Write-Host '==> Created vendor/LibreChat/.env from .env.example'
}
$envText = Get-Content $envFile -Raw -Encoding utf8
if ($envText -notmatch 'KAPE-LUMEN-SETTINGS') {
  # Comment out any lines in LibreChat's .env that we set ourselves, so ours win.
  $ours = Get-Content (Join-Path $PSScriptRoot 'env.additions.example') -Encoding utf8 |
    Where-Object { $_ -match '^[A-Z_]+=' } | ForEach-Object { ($_ -split '=')[0] }
  $lines = Get-Content $envFile -Encoding utf8 | ForEach-Object {
    $name = ($_ -split '=')[0]
    if ($ours -contains $name) { "# (overridden by Kape Lumen below) $_" } else { $_ }
  }
  $lines + '' + (Get-Content (Join-Path $PSScriptRoot 'env.additions.example') -Encoding utf8) |
    Set-Content $envFile -Encoding utf8
  Write-Host '==> Added Kape Lumen settings to .env'
}

# 4. Gateway token (random) and Gemini key
$envText = Get-Content $envFile -Raw -Encoding utf8
if ($envText -match '(?m)^GATEWAY_TOKEN=[ \t]*(?=\r?$)') {
  $bytes = New-Object byte[] 24
  [Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
  $token = -join ($bytes | ForEach-Object { $_.ToString('x2') })
  $envText = $envText -replace '(?m)^GATEWAY_TOKEN=[ \t]*(?=\r?$)', "GATEWAY_TOKEN=$token"
  Set-Content $envFile $envText -Encoding utf8 -NoNewline
  Write-Host '==> Generated GATEWAY_TOKEN'
}
if ($envText -match '(?m)^GEMINI_API_KEY=[ \t]*(?=\r?$)') {
  $secure = Read-Host 'Paste your Gemini API key (input hidden)' -AsSecureString
  $key = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure))
  if ($key) {
    $envText = (Get-Content $envFile -Raw -Encoding utf8) -replace '(?m)^GEMINI_API_KEY=[ \t]*(?=\r?$)', "GEMINI_API_KEY=$key"
    Set-Content $envFile $envText -Encoding utf8 -NoNewline
    Write-Host '==> Saved Gemini key to vendor/LibreChat/.env (gitignored)'
  } else {
    Write-Warning 'No key entered. Add GEMINI_API_KEY to vendor/LibreChat/.env before chatting.'
  }
}

# 5. Start everything
Write-Host '==> Starting containers (the first run downloads images, ~5-10 min)'
Push-Location $vendor
try {
  docker compose up -d --build
  docker compose ps
} finally { Pop-Location }

Write-Host ''
Write-Host 'Open http://localhost:3080 and register a test account (invented name/email).'
Write-Host 'Gateway health:  docker exec brew-gateway wget -qO- http://127.0.0.1:8080/health'
