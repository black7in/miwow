# Arranca las pruebas online:
#   1) server.js (tu PC) con el cliente de D:\Wow
#   2) tunel rapido de Cloudflare hacia localhost:8080
#   3) despliega el Worker con la URL nueva del tunel (ORIGIN)
# Requisitos: AzerothCore encendido; haber hecho una vez  "npx wrangler login"  y  "npx wrangler secret put BASIC_AUTH"
# Uso:  powershell -ExecutionPolicy Bypass -File arrancar-online.ps1 -Auth "usuario:clave"
param(
  [Parameter(Mandatory = $true)][string]$Auth,     # el mismo usuario:clave que pusiste en el secreto BASIC_AUTH del Worker
  [string]$ClientDir = 'D:\Wow',
  [int]$Port = 8080
)
$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
$srv = Resolve-Path "$here\..\servidor"   # web\servidor
$cf = "$env:LOCALAPPDATA\cloudflared\cloudflared.exe"
$logs = Join-Path $here 'logs'; New-Item -ItemType Directory -Force $logs | Out-Null

# 1) server.js en otra ventana
$cmd = "`$env:WOW_CLIENTDIR='$ClientDir'; `$env:WOW_BASICAUTH='$Auth'; `$env:WOW_TRUSTPROXY='true'; `$env:WOW_MAXWSPERIP='30'; `$env:WOW_GAMEINDEX='$srv\game-index.txt'; `$env:WOW_PORT='$Port'; Set-Location '$srv'; node server.js"
Start-Process powershell -ArgumentList '-NoExit', '-Command', $cmd -WindowStyle Normal
Write-Host 'server.js arrancado (ventana aparte)' -ForegroundColor Green

# 2) tunel en otra ventana, con log para leer la URL
$tlog = Join-Path $logs 'tunel.log'; Remove-Item $tlog -ErrorAction SilentlyContinue
Start-Process powershell -ArgumentList '-NoExit', '-Command', "& '$cf' tunnel --no-autoupdate --url http://localhost:$Port --logfile '$tlog'" -WindowStyle Normal
Write-Host 'esperando la URL del tunel...' -ForegroundColor Yellow
$url = $null
for ($i = 0; $i -lt 60 -and -not $url; $i++) {
  Start-Sleep 1
  if (Test-Path $tlog) { $m = Select-String -Path $tlog -Pattern 'https://[a-z0-9-]+\.trycloudflare\.com' | Select-Object -First 1; if ($m) { $url = $m.Matches[0].Value } }
}
if (-not $url) { throw 'No salio la URL del tunel; mira la ventana de cloudflared.' }
Write-Host "tunel: $url" -ForegroundColor Green

# 3) Worker con ORIGIN = URL del tunel
Push-Location (Join-Path $here 'worker')
try { npx --yes wrangler@4 deploy --var "ORIGIN:$url" } finally { Pop-Location }
Write-Host ''
Write-Host 'Listo. Abre la URL *.workers.dev que salio arriba + /play' -ForegroundColor Cyan
Write-Host '(la URL del tunel NO se comparte: los testers entran por workers.dev)' -ForegroundColor DarkGray
