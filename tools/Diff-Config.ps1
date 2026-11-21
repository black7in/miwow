<#
.SYNOPSIS
  Audita un .conf de AzerothCore contra su .conf.dist: lista las claves cambiadas o anadidas a mano.
  Sirve para detectar cambios que deberian estar en mod_miwow.conf (juego) o en docs/despliegue.md
  (infraestructura) antes de pasar a produccion.

.EXAMPLE
  .\tools\Diff-Config.ps1 -Conf "D:\...\configs\worldserver.conf" -Dist "D:\...\configs\worldserver.conf.dist"
  .\tools\Diff-Config.ps1 -Conf ... -Dist ... -Overrides .\modules\mod-miwow\conf\mod_miwow.conf.dist
#>
param(
    [Parameter(Mandatory = $true)][string]$Conf,
    [Parameter(Mandatory = $true)][string]$Dist,
    [string]$Overrides
)

$ErrorActionPreference = "Stop"

function Read-Conf([string]$path) {
    $map = [ordered]@{}
    foreach ($line in Get-Content -Path $path -Encoding UTF8) {
        $l = $line.Trim()
        if ($l -eq "" -or $l.StartsWith("#") -or $l.StartsWith("[")) { continue }
        $i = $l.IndexOf("=")
        if ($i -lt 1) { continue }
        $key = $l.Substring(0, $i).Trim()
        $value = $l.Substring($i + 1).Trim().Replace('"', '')
        $map[$key] = $value
    }
    return $map
}

$confMap = Read-Conf $Conf
$distMap = Read-Conf $Dist
$overMap = @{}
if ($Overrides) { $overMap = Read-Conf $Overrides }

$rows = foreach ($key in $confMap.Keys) {
    $estado = $null
    if (-not $distMap.Contains($key)) { $estado = "ANADIDA" }
    elseif ($distMap[$key] -ne $confMap[$key]) { $estado = "CAMBIADA" }
    if (-not $estado) { continue }

    $nota = ""
    if ($overMap.Contains($key)) { $nota = "pisada por modulo (= $($overMap[$key]))" }

    [pscustomobject]@{
        Estado = $estado
        Clave  = $key
        Dist   = if ($distMap.Contains($key)) { $distMap[$key] } else { "" }
        Conf   = $confMap[$key]
        Nota   = $nota
    }
}

$missing = foreach ($key in $distMap.Keys) { if (-not $confMap.Contains($key)) { $key } }

if ($rows) { $rows | Format-Table -AutoSize -Wrap } else { Write-Host "Sin diferencias de valores." }
if ($missing) {
    Write-Host ""
    Write-Host "Claves del .dist que faltan en el .conf (se usara el valor por defecto del core):"
    $missing | ForEach-Object { Write-Host "  $_" }
}
