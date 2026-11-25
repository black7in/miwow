# Publica el cliente web en el VPS de pruebas (ver docs/despliegue-vps-pruebas.md).
#   - servidor:    server.js, play.html, package*.json, game-index.txt, public/ y las plantillas de deploy/vps-pruebas
#                  (en servidor/deploy/). config.json SOLO se crea la primera vez (despues no se toca: tiene la clave real).
#   - cliente-web: Wow.js, Wow.wasm (el parcheado), game-manifest.txt
#   - -Parche:     sube tambien el patch-4.MPQ EMPAQUETADO a cliente/Data/ (escritura atomica: .tmp + mv)
#   - R2:          si el VPS tiene rclone (~/bin/rclone), sube a R2 lo publicado (Wow.js/wasm y patch-4) con
#                  deploy/subir-r2.sh (lo sirve el Worker; si R2 se queda atras, el Worker lo pide al VPS)
# Luego: npm ci y reinicio de miwow-juego (si el servicio ya esta instalado). Nunca toca userdata/ ni el cliente del juego.
# Uso:  powershell -ExecutionPolicy Bypass -File web\deploy\publicar-vps.ps1 [-Parche C:\ruta\patch-4.MPQ] [-SoloParche]
param(
  [string]$Servidor = 'MiWow',                 # alias de ~/.ssh/config
  [string]$Ruta     = '/opt/miwow-juego',
  [string]$Parche   = '',
  [switch]$SoloParche
)
$ErrorActionPreference = 'Stop'
$web = (Resolve-Path "$PSScriptRoot\..").Path   # web\
function Remoto([string]$cmd) { & ssh -o BatchMode=yes $Servidor $cmd; if ($LASTEXITCODE -ne 0) { throw "ssh fallo: $cmd" } }
function Subir([string[]]$src, [string]$dst) { & scp -q -o BatchMode=yes @src "${Servidor}:$dst"; if ($LASTEXITCODE -ne 0) { throw "scp fallo -> $dst" } }

# Carpetas (la primera vez necesita sudo)
Remoto "test -d $Ruta/servidor || (sudo -n mkdir -p $Ruta/servidor $Ruta/cliente-web $Ruta/cliente/Data $Ruta/userdata && sudo -n chown -R `$(id -un):`$(id -gn) $Ruta)"
Remoto "mkdir -p $Ruta/servidor/public/icons $Ruta/servidor/deploy $Ruta/cliente-web $Ruta/cliente/Data $Ruta/userdata"

if (-not $SoloParche) {
  $s = "$web\servidor"
  Subir @("$s\server.js", "$s\voice.js", "$s\play.html", "$s\package.json", "$s\package-lock.json", "$s\game-index.txt") "$Ruta/servidor/"
  Subir @("$s\public\manifest.webmanifest") "$Ruta/servidor/public/"
  Subir (Get-ChildItem "$s\public\icons" -File | ForEach-Object FullName) "$Ruta/servidor/public/icons/"
  foreach ($d in 'brand', 'fonts', 'voice') {   # logo y tipografias de play.html; voz (docs/voz.md)
    Remoto "mkdir -p $Ruta/servidor/public/$d"
    Subir (Get-ChildItem "$s\public\$d" -File | ForEach-Object FullName) "$Ruta/servidor/public/$d/"
  }
  Subir (Get-ChildItem "$web\deploy\vps-pruebas" -File | ForEach-Object FullName) "$Ruta/servidor/deploy/"
  Remoto "test -f $Ruta/servidor/config.json || (cp $Ruta/servidor/deploy/config.json $Ruta/servidor/config.json && echo 'config.json creado: CAMBIA basicAuth')"
  Remoto "grep -q CAMBIA-ESTA-CLAVE $Ruta/servidor/config.json && echo 'AVISO: config.json sigue con la clave de ejemplo' || true"

  $c = "$web\cliente"
  foreach ($f in 'Wow.js', 'Wow.wasm', 'game-manifest.txt') { if (-not (Test-Path "$c\$f")) { throw "Falta $c\$f" } }
  Subir @("$c\Wow.js", "$c\Wow.wasm", "$c\game-manifest.txt") "$Ruta/cliente-web/"
  Remoto "cd $Ruta/servidor && npm ci --omit=dev --no-audit --no-fund --loglevel=error"
  Remoto "if test -x ~/bin/rclone; then bash $Ruta/servidor/deploy/subir-r2.sh web; else echo 'sin rclone en el VPS: R2 no se actualiza'; fi"
}

if ($Parche) {
  $p = Get-Item $Parche
  if ($p.PSIsContainer) { throw "$Parche es una carpeta: el cliente web necesita el MPQ EMPAQUETADO" }
  # Avisar si el tamano coincide con el que ya hay (los jugadores seguirian con el viejo en cache)
  $viejo = & ssh -o BatchMode=yes $Servidor "stat -c %s $Ruta/cliente/Data/patch-4.MPQ 2>/dev/null || echo 0"
  if ([int64]$viejo -eq $p.Length) { throw "patch-4.MPQ tiene el MISMO tamano ($($p.Length)) que el publicado: cambia su tamano (docs/cliente-web.md seccion 5)" }
  Subir @($p.FullName) "$Ruta/cliente/Data/patch-4.MPQ.tmp"
  Remoto "mv -f $Ruta/cliente/Data/patch-4.MPQ.tmp $Ruta/cliente/Data/patch-4.MPQ"
  Remoto "if test -x ~/bin/rclone; then bash $Ruta/servidor/deploy/subir-r2.sh parche; else echo 'sin rclone en el VPS: R2 no se actualiza'; fi"
  Write-Host ("patch-4.MPQ publicado ({0:N0} bytes, antes {1:N0})" -f $p.Length, [int64]$viejo) -ForegroundColor Green
}

# Reinicio (el manifest relee los MPQ solo cada 30 s; server.js/play.html si necesitan reinicio)
Remoto "if systemctl list-unit-files miwow-juego.service >/dev/null 2>&1 && systemctl is-enabled miwow-juego >/dev/null 2>&1; then sudo -n systemctl restart miwow-juego && sleep 2 && systemctl is-active miwow-juego; else echo 'servicio miwow-juego aun no instalado (docs/despliegue-vps-pruebas.md paso 5)'; fi"
Write-Host 'Publicado.' -ForegroundColor Cyan
