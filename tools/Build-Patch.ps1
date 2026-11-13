<#
.SYNOPSIS
  Genera la carpeta del parche (formato "carpeta como MPQ") a partir de client\src.
  Anade los DBC con filas propias de EventWow (Build-Dbc.ps1: lee la BD world, que debe estar arrancada).
  El resultado se copia manualmente a Data\ del cliente.

.EXAMPLE
  .\tools\Build-Patch.ps1
  .\tools\Build-Patch.ps1 -Name patch-5.MPQ
  .\tools\Build-Patch.ps1 -SkipDbc     # solo client\src (sin BD)
#>
param(
    [string]$Name = "patch-4.MPQ",
    [string]$Locale = "esES",
    [switch]$SkipDbc
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

$files = Get-ChildItem -Path $out -Recurse -File
Write-Host "Parche generado: $out"
Write-Host "Archivos: $($files.Count)"
$files | ForEach-Object { "  " + $_.FullName.Substring($out.Length + 1) }
