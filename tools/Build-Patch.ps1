<#
.SYNOPSIS
  Genera la carpeta del parche (formato "carpeta como MPQ") a partir de client\src.
  El resultado se copia manualmente a Data\ del cliente.

.EXAMPLE
  .\tools\Build-Patch.ps1
  .\tools\Build-Patch.ps1 -Name patch-5.MPQ
#>
param(
    [string]$Name = "patch-4.MPQ"
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$src  = Join-Path $root "client\src"
$out  = Join-Path $root "client\patches\$Name"

if (Test-Path $out) { Remove-Item -Recurse -Force $out }
New-Item -ItemType Directory -Force -Path $out | Out-Null

robocopy $src $out /E /NFL /NDL /NJH /NJS /NP | Out-Null
if ($LASTEXITCODE -ge 8) { throw "robocopy fallo (codigo $LASTEXITCODE)" }

$files = Get-ChildItem -Path $out -Recurse -File
Write-Host "Parche generado: $out"
Write-Host "Archivos: $($files.Count)"
$files | ForEach-Object { "  " + $_.FullName.Substring($out.Length + 1) }
