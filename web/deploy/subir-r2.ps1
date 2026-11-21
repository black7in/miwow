# Sube el cliente a R2 con claves en minuscula:
#   game/<ruta en minuscula>   (Data/*.mpq, Data/<locale>/**, Interface/AddOns/Blizzard_*/**)
#   web/Wow.js, web/Wow.wasm
# Re-ejecutable: rclone se salta los archivos ya subidos con el mismo tamano/fecha.
# Uso:  powershell -ExecutionPolicy Bypass -File subir-r2.ps1 [-BwLimit 2M] [-Solo patch.mpq] [-Simular]
param(
  [string]$ClientDir = 'D:\Wow',
  [string]$Locale    = 'esES',
  [string]$WebDir    = (Resolve-Path "$PSScriptRoot\..\cliente").Path,     # web\cliente (Wow.js, Wow.wasm)
  [string]$Remote    = 'r2:wotlk-cliente',
  [string]$BwLimit   = '',          # p.ej. '2M' para no saturar tu conexion (MB/s)
  [string]$Solo      = '',          # subir solo los archivos cuya ruta contenga este texto
  [switch]$Simular,                 # solo muestra la lista, no sube nada
  [switch]$SoloIndice,              # solo escribe game-index.txt, no sube nada
  [string]$Indice    = (Join-Path (Resolve-Path "$PSScriptRoot\..\servidor").Path 'game-index.txt')   # web\servidor
)
$ErrorActionPreference = 'Stop'
$rclone = "$env:LOCALAPPDATA\rclone\rclone.exe"
$flags = @('--s3-chunk-size', '64M', '--s3-upload-concurrency', '4', '--retries', '10', '--retries-sleep', '20s', '--low-level-retries', '20', '--progress')
if ($BwLimit) { $flags += @('--bwlimit', $BwLimit) }

$items = New-Object System.Collections.Generic.List[object]
Get-ChildItem (Join-Path $ClientDir 'Data') -File | Where-Object { $_.Extension -ieq '.mpq' } | ForEach-Object { $items.Add($_) }
$loc = Join-Path $ClientDir "Data\$Locale"
Get-ChildItem $loc -File -Recurse | ForEach-Object { $items.Add($_) }
$addons = Join-Path $ClientDir 'Interface\AddOns'
if (Test-Path $addons) {
  Get-ChildItem $addons -Directory -Filter 'Blizzard_*' | ForEach-Object { Get-ChildItem $_.FullName -File -Recurse } | ForEach-Object { $items.Add($_) }
}

$jobs = foreach ($f in $items) {
  $rel = $f.FullName.Substring($ClientDir.TrimEnd('\').Length).TrimStart('\').Replace('\', '/')
  if ($rel -ieq "Data/$Locale/realmlist.wtf") { continue }   # el realmlist es por usuario (lo sirve server.js)
  [pscustomobject]@{ Src = $f.FullName; Key = 'game/' + $rel.ToLowerInvariant(); Size = $f.Length; Rel = $rel }
}

# game-index.txt: lista "tamano<TAB>ruta" que usa server.js (gameIndex) para el manifest sin tener los MPQ
if (-not $Solo) {
  $lineas = $jobs | Sort-Object Rel | ForEach-Object { "{0}`t{1}" -f $_.Size, $_.Rel }
  [IO.File]::WriteAllText($Indice, (($lineas -join "`n") + "`n"), (New-Object Text.UTF8Encoding $false))
  Write-Host ("indice: {0} ({1} archivos)" -f $Indice, @($lineas).Count) -ForegroundColor Cyan
}
if ($SoloIndice) { return }
foreach ($w in 'Wow.js', 'Wow.wasm') {
  $p = Join-Path $WebDir $w
  $jobs = @($jobs) + [pscustomobject]@{ Src = $p; Key = "web/$w"; Size = (Get-Item $p).Length }
}
if ($Solo) { $jobs = $jobs | Where-Object { $_.Key -like "*$($Solo.ToLowerInvariant())*" } }
$jobs = @($jobs | Sort-Object Size)     # pequenos primero

$total = ($jobs | Measure-Object Size -Sum).Sum
Write-Host ("{0} archivos, {1:N2} GB  ({2})  ->  {3}" -f $jobs.Count, ($total / 1GB), $ClientDir, $Remote) -ForegroundColor Cyan
if ($Simular) { $jobs | ForEach-Object { "{0,10:N1} MB  {1}" -f ($_.Size / 1MB), $_.Key }; return }

$n = 0; $fallos = 0; $hecho = 0
foreach ($j in $jobs) {
  $n++
  Write-Host ("[{0}/{1}] {2} ({3:N1} MB)  -  total {4:N1}%" -f $n, $jobs.Count, $j.Key, ($j.Size / 1MB), (100 * $hecho / $total)) -ForegroundColor Yellow
  & $rclone copyto $j.Src "$Remote/$($j.Key)" @flags
  if ($LASTEXITCODE -ne 0) { $fallos++; Write-Host "  FALLO: $($j.Key)" -ForegroundColor Red }
  $hecho += $j.Size
}
if ($fallos) { Write-Host "Terminado con $fallos fallos: vuelve a ejecutar el script para reintentar." -ForegroundColor Red }
else { Write-Host 'Terminado sin errores.' -ForegroundColor Green }
