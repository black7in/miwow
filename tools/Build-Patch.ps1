<#
.SYNOPSIS
  Genera la carpeta del parche (formato "carpeta como MPQ") a partir de client\src.
  Anade los DBC con filas propias de MiWow (Build-Dbc.ps1: lee la BD world, que debe estar arrancada) y los
  mapas propios (tools\mapgen desde Maps\maps.json: World\Maps del cliente + .map del servidor en ServerDataDir;
  necesita Python con numpy, lanzador "py"). Las mmaps se generan aparte: mmaps_generator <id> (docs\mapas.md).
  El resultado se copia manualmente a Data\ del cliente.
  Ademas lo empaqueta como MPQ de verdad (tools\mpqpack.py) en client\patches\web\<Name>: el cliente web solo lee MPQ
  empaquetados y server.js lo sirve desde ahi (extraFiles en web\servidor\config.json). -NoPack para saltarlo.

.EXAMPLE
  .\tools\Build-Patch.ps1
  .\tools\Build-Patch.ps1 -Name patch-5.MPQ
  .\tools\Build-Patch.ps1 -SkipDbc     # solo client\src (sin BD)
#>
param(
    [string]$Name = "patch-4.MPQ",
    [string]$Locale = "esES",
    [switch]$SkipDbc,
    [switch]$SkipMaps,
    [switch]$NoPack,
    [string]$ServerDataDir = "",
    # Data\ del cliente (MPQ originales): colision de los modelos de muro para los vmaps del servidor
    [string]$WowDataDir = "D:\Clientes de Wow\Wow - copia\Data"
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$src  = Join-Path $root "client\src"
$out  = Join-Path $root "client\patches\$Name"

if (Test-Path $out) { Remove-Item -Recurse -Force $out }
New-Item -ItemType Directory -Force -Path $out | Out-Null

robocopy $src $out /E /NFL /NDL /NJH /NJS /NP | Out-Null
if ($LASTEXITCODE -ge 8) { throw "robocopy fallo (codigo $LASTEXITCODE)" }

if (-not $SkipDbc)
{
    & (Join-Path $PSScriptRoot "Build-Dbc.ps1") -OutDir (Join-Path $out "DBFilesClient") -Locale $Locale
}
else
{
    Write-Warning "Sin DBC (-SkipDbc): los objetos/hechizos propios no tendran sus datos en el cliente"
}

if (-not $SkipMaps)
{
    if (-not $ServerDataDir) { $ServerDataDir = Join-Path $root "server\bin\RelWithDebInfo\data" }
    $mapArgs = @((Join-Path $PSScriptRoot "mapgen\mapgen.py"), "--client", $out,
                 "--preview", (Join-Path $PSScriptRoot "mapgen\_work"))
    # Data\ del cliente: colision de los modelos (vmaps) y decoracion de los circuitos (obligatorio para ellos)
    if (Test-Path $WowDataDir) { $mapArgs += @("--wow-data", $WowDataDir) }
    else { Write-Warning "No existe $WowDataDir (parametro -WowDataDir): sin vmaps ni circuitos" }
    if (Test-Path $ServerDataDir) { $mapArgs += @("--server", $ServerDataDir) }
    else { Write-Warning "No existe $ServerDataDir (parametro -ServerDataDir): solo se generan los mapas del cliente" }
    # Minimapas: necesitan el md5translate.trs original del cliente (no versionado, ver docs/mapas.md)
    $trs = Join-Path $root "client\Minimap\md5translate.trs"
    if (Test-Path $trs) { $mapArgs += @("--minimap-trs", $trs) }
    else { Write-Warning "No existe ${trs}: sin minimapas (extraerlo de patch-3.MPQ, ver docs/mapas.md)" }
    & py -I -B @mapArgs
    if ($LASTEXITCODE -ne 0) { throw "mapgen fallo (codigo $LASTEXITCODE)" }
}

if (-not $NoPack)
{
    $webDir = Join-Path $root "client\patches\web"
    New-Item -ItemType Directory -Force -Path $webDir | Out-Null
    & py -I -B (Join-Path $PSScriptRoot "mpqpack.py") $out (Join-Path $webDir $Name)
    if ($LASTEXITCODE -ne 0) { throw "mpqpack fallo (codigo $LASTEXITCODE)" }
}

$files = Get-ChildItem -Path $out -Recurse -File
Write-Host "Parche generado: $out"
Write-Host "Archivos: $($files.Count)"
$files | ForEach-Object { "  " + $_.FullName.Substring($out.Length + 1) }
