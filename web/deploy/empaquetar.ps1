# Arma web\paquete (no versionado) con SOLO lo que va al VPS Linux. Ver docs/cliente-web.md.
# Uso:  powershell -ExecutionPolicy Bypass -File web\deploy\empaquetar.ps1
# (Antes: subir-r2.ps1 -SoloIndice, para que game-index.txt este al dia)
param([string]$Salida = (Join-Path (Resolve-Path "$PSScriptRoot\..").Path 'paquete'))
$ErrorActionPreference = 'Stop'
$raiz = (Resolve-Path "$PSScriptRoot\..").Path        # web
$srv  = "$raiz\servidor"
$dep  = "$raiz\deploy"
$cli  = "$raiz\cliente"

if (Test-Path $Salida) { Remove-Item $Salida -Recurse -Force }
$d = @{ s = "$Salida\servidor"; w = "$Salida\web"; p = "$Salida\deploy" }
$d.Values | ForEach-Object { New-Item -ItemType Directory -Force $_ | Out-Null }

# servidor/
foreach ($f in 'server.js', 'package.json', 'package-lock.json', 'play.html', 'game-index.txt') { Copy-Item "$srv\$f" $d.s }
Copy-Item "$srv\public" $d.s -Recurse
Copy-Item "$dep\vps\config.json" $d.s
# web/
foreach ($f in 'Wow.js', 'Wow.wasm', 'game-manifest.txt') { Copy-Item "$cli\$f" $d.w }
# deploy/
Copy-Item "$dep\Caddyfile", "$dep\wow-web.service" $d.p
New-Item -ItemType Directory -Force "$($d.p)\worker" | Out-Null
Copy-Item "$dep\worker\src" "$($d.p)\worker" -Recurse
Copy-Item "$dep\worker\wrangler.toml" "$($d.p)\worker"
Copy-Item "$dep\vps\LEEME.md" $Salida

# Pasar a finales de linea Unix (LF) los archivos de texto que se usan en Linux
Get-ChildItem $Salida -Recurse -File -Include *.js, *.json, *.html, *.txt, *.md, *.toml, *.service, Caddyfile, *.webmanifest, *.svg |
  Where-Object { $_.Name -ne 'Wow.js' } | ForEach-Object {
    $t = [IO.File]::ReadAllText($_.FullName)
    if ($t.Contains("`r`n")) { [IO.File]::WriteAllText($_.FullName, $t.Replace("`r`n", "`n"), (New-Object Text.UTF8Encoding $false)) }
  }

# Comprobaciones
$idx = Get-Content "$($d.s)\game-index.txt"
if ($idx.Count -lt 100) { Write-Host "AVISO: game-index.txt tiene solo $($idx.Count) lineas" -ForegroundColor Red }
if ((Get-Item "$($d.w)\Wow.wasm").Length -ne (Get-Item "$cli\Wow.wasm").Length) { throw 'Wow.wasm no coincide' }

Write-Host "Paquete listo: $Salida" -ForegroundColor Green
Get-ChildItem $Salida -Recurse -File | ForEach-Object {
  "{0,9:N0} KB  {1}" -f ($_.Length / 1KB), $_.FullName.Substring($Salida.Length + 1)
}
"Total: {0:N1} MB" -f ((Get-ChildItem $Salida -Recurse -File | Measure-Object Length -Sum).Sum / 1MB)
