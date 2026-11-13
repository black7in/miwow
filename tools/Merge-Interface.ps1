<#
.SYNOPSIS
  Consolida la carpeta Interface de los MPQ extraidos del cliente 3.3.5a
  respetando el orden de carga del cliente (el ultimo gana).

.EXAMPLE
  .\tools\Merge-Interface.ps1 -Source "D:\Clientes de Wow\Wow - copia\Data\esES\extracted_clean" -Locale esES
#>
param(
    [Parameter(Mandatory = $true)][string]$Source,
    [string]$Locale = "esES",
    [string]$Dest
)

$ErrorActionPreference = "Stop"
if (-not $Dest) { $Dest = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) "..\client\interface-original" }

# Orden de carga de menor a mayor prioridad (solo MPQ de locale; los de Data\ raiz no traen Interface)
$order = @(
    "locale-$Locale.MPQ",
    "speech-$Locale.MPQ",
    "expansion-locale-$Locale.MPQ",
    "lichking-locale-$Locale.MPQ",
    "expansion-speech-$Locale.MPQ",
    "lichking-speech-$Locale.MPQ",
    "patch-$Locale.MPQ",
    "patch-$Locale-2.MPQ",
    "patch-$Locale-3.MPQ"
)

if (Test-Path $Dest) {
    Write-Host "Borrando salida anterior: $Dest"
    Remove-Item -Recurse -Force $Dest
}
New-Item -ItemType Directory -Force -Path $Dest | Out-Null
$Dest = (Resolve-Path $Dest).Path
$destInterface = Join-Path $Dest "Interface"

# Clave en minusculas: el cliente no distingue mayusculas (GLUES == Glues)
$manifest = @{}
$overrides = New-Object System.Collections.Generic.List[object]

foreach ($mpq in $order) {
    $srcInterface = Join-Path (Join-Path $Source $mpq) "Interface"
    if (-not (Test-Path $srcInterface)) {
        Write-Host ("[--] {0,-32} sin Interface, se omite" -f $mpq)
        continue
    }

    $files = Get-ChildItem -Path $srcInterface -Recurse -File
    $count = 0; $over = 0
    foreach ($f in $files) {
        $rel = $f.FullName.Substring($srcInterface.Length + 1)
        $key = $rel.ToLowerInvariant()
        if ($manifest.ContainsKey($key)) {
            $overrides.Add([pscustomobject]@{ Path = $rel; From = $manifest[$key].Source; To = $mpq })
            $over++
        }
        $manifest[$key] = [pscustomobject]@{ Path = $rel; Source = $mpq }
        $count++
    }

    # /E subcarpetas, /IS /IT fuerza sobrescritura aunque parezcan iguales
    robocopy $srcInterface $destInterface /E /IS /IT /NFL /NDL /NJH /NJS /NP | Out-Null
    if ($LASTEXITCODE -ge 8) { throw "robocopy fallo en $mpq (codigo $LASTEXITCODE)" }

    Write-Host ("[OK] {0,-32} {1,6} archivos ({2} sobrescriben)" -f $mpq, $count, $over)
}

$manifest.Values | Sort-Object Path | Export-Csv -NoTypeInformation -Encoding UTF8 (Join-Path $Dest "manifest.csv")
$overrides | Sort-Object Path | Export-Csv -NoTypeInformation -Encoding UTF8 (Join-Path $Dest "overrides.csv")

Write-Host ""
Write-Host "Total archivos finales: $($manifest.Count)"
Write-Host "Sobrescrituras:         $($overrides.Count)"
Write-Host "Salida:                 $destInterface"
Write-Host "manifest.csv  -> de que MPQ sale cada archivo final"
Write-Host "overrides.csv -> que archivos fueron reemplazados y por cual parche"
