<#
.SYNOPSIS
  Genera los DBC del cliente con las filas propias de MiWow (las llama Build-Patch.ps1).

.DESCRIPTION
  Fuente de verdad = BD world: las tablas *_dbc de AzerothCore (item_dbc, spell_dbc...), que el servidor ya fusiona
  con sus DBC al arrancar (DBCStores.cpp LOAD_DBC). El servidor NO necesita archivos DBC modificados.
  Este script copia al parche los DBC del cliente que tengan filas de MiWow (ID >= MinId, rango reservado
  9500000+) en su tabla, con esas filas anadidas (o sustituidas si el ID ya existia):

    client\DBCs\DBC<Locale>\<Archivo>.dbc  +  filas de <archivo>_dbc  ->  <OutDir>\<Archivo>.dbc

  Rangos propios por tabla ($ExtraRanges): Map.dbc usa IDs 750-799 (el cliente y el core dimensionan tablas por el
  ID mas alto de mapa y TC9Sidecar.h limita a 800; ver docs/mapas.md).
  Solo exporta nuestro rango: el resto de filas de las tablas *_dbc son correcciones del servidor de AzerothCore
  (p. ej. hechizos de servidor en spell_dbc) que no deben llegar al cliente.
  Columnas de la tabla = campos del DBC, en orden: enteros -> int32, float -> float, texto -> cadena.
  Conexion: WorldDatabaseInfo de worldserver.conf (la misma BD que usa el servidor).

.EXAMPLE
  .\tools\Build-Dbc.ps1 -OutDir client\patches\patch-4.MPQ\DBFilesClient
#>
param(
    [Parameter(Mandatory = $true)]
    [string]$OutDir,
    [string]$Locale = "esES",
    [uint32]$MinId = 9500000,
    [string]$WorldServerConf = "",
    [string]$MySql = "C:\Program Files\MySQL\MySQL Server 8.0\bin\mysql.exe"
)

$ErrorActionPreference = "Stop"

# Tablas con un rango de IDs propio ademas de MinId+ (condicion SQL sobre la primera columna)
$ExtraRanges = @{
    "map_dbc" = "BETWEEN 750 AND 799"
    "areatable_dbc" = "BETWEEN 5000 AND 5099"     # zonas de los mapas propios (ver SQL *_miwow_map_areas)
    "light_dbc" = "BETWEEN 2600 AND 2699"          # cielo de los mapas propios (Light.dbc llega a 2538)
}

function Get-IdFilter([string]$table, [string]$id)
{
    $filter = "``$id`` >= $MinId"
    if ($ExtraRanges.ContainsKey($table)) { $filter = "($filter OR ``$id`` $($ExtraRanges[$table]))" }
    return $filter
}

$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$dbcDir = Join-Path $root "client\DBCs\DBC$Locale"
if (-not $WorldServerConf) { $WorldServerConf = Join-Path $root "server\bin\RelWithDebInfo\configs\worldserver.conf" }

if (-not (Test-Path $dbcDir)) { throw "No existe $dbcDir (DBC originales del cliente $Locale)" }
if (-not (Test-Path $MySql)) { throw "No se encuentra mysql.exe: $MySql (parametro -MySql)" }
if (-not (Test-Path $WorldServerConf)) { throw "No se encuentra $WorldServerConf (parametro -WorldServerConf)" }

# --- Conexion ----------------------------------------------------------------------------------------------

$line = Select-String -Path $WorldServerConf -Pattern '^\s*WorldDatabaseInfo\s*=\s*"([^"]*)"' | Select-Object -First 1
if (-not $line) { throw "WorldDatabaseInfo no encontrado en $WorldServerConf" }
$db = $line.Matches[0].Groups[1].Value.Split(';')
if ($db.Count -lt 5) { throw "WorldDatabaseInfo con formato inesperado (host;puerto;usuario;contrasena;bd)" }

function Invoke-MySqlXml([string]$sql)
{
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $MySql
    $psi.Arguments = "--xml --default-character-set=utf8mb4 -h $($db[0]) -P $($db[1]) -u $($db[2]) $($db[4]) -e `"$sql`""
    $psi.EnvironmentVariables["MYSQL_PWD"] = $db[3]
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.StandardOutputEncoding = [System.Text.Encoding]::UTF8
    $process = [System.Diagnostics.Process]::Start($psi)
    $stdout = $process.StandardOutput.ReadToEndAsync()
    $stderr = $process.StandardError.ReadToEnd()
    $process.WaitForExit()
    if ($process.ExitCode -ne 0) { throw "mysql fallo: $stderr" }
    return [xml]$stdout.Result
}

$xsi = "http://www.w3.org/2001/XMLSchema-instance"

function Get-Rows([xml]$xml)
{
    $result = @()
    foreach ($row in $xml.resultset.ChildNodes)
    {
        if ($row.LocalName -ne "row") { continue }
        $values = @()
        foreach ($field in $row.ChildNodes)
        {
            if ($field.LocalName -ne "field") { continue }
            if ($field.GetAttribute("nil", $xsi) -eq "true") { $values += , $null } else { $values += , $field.InnerText }
        }
        $result += , $values
    }
    return , $result
}

# --- Tablas *_dbc con filas de MiWow ---------------------------------------------------------------------

$columnsXml = Invoke-MySqlXml ("SELECT TABLE_NAME, COLUMN_NAME, DATA_TYPE FROM information_schema.COLUMNS " +
    "WHERE TABLE_SCHEMA = '$($db[4])' AND TABLE_NAME LIKE '%\\_dbc' ORDER BY TABLE_NAME, ORDINAL_POSITION")
$tables = [ordered]@{}
foreach ($r in (Get-Rows $columnsXml))
{
    if (-not $tables.Contains($r[0])) { $tables[$r[0]] = New-Object System.Collections.ArrayList }
    [void]$tables[$r[0]].Add(@{ Name = $r[1]; Type = $r[2] })
}

$counts = @()
foreach ($table in $tables.Keys)
{
    $id = $tables[$table][0].Name
    $counts += "SELECT '$table', COUNT(*) FROM ``$table`` WHERE $(Get-IdFilter $table $id)"
}
$used = @()
foreach ($r in (Get-Rows (Invoke-MySqlXml ($counts -join " UNION ALL "))))
{
    if ([int64]$r[1] -gt 0) { $used += $r[0] }
}

New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
if ($used.Count -eq 0)
{
    Write-Host "DBC: ninguna tabla *_dbc tiene filas de MiWow (ID >= $MinId)"
    return
}

$intTypes = @("tinyint", "smallint", "mediumint", "int", "bigint")
$floatTypes = @("float", "double", "decimal")
$utf8 = New-Object System.Text.UTF8Encoding($false)

foreach ($table in $used)
{
    $columns = $tables[$table]
    $baseName = $table.Substring(0, $table.Length - 4)  # sin "_dbc"
    $file = Get-ChildItem -Path $dbcDir -Filter "*.dbc" | Where-Object { $_.BaseName.ToLowerInvariant() -eq $baseName } |
        Select-Object -First 1
    if (-not $file) { throw "${table}: no hay $baseName.dbc en $dbcDir (DBC solo de servidor?)" }

    $bytes = [System.IO.File]::ReadAllBytes($file.FullName)
    if ([System.Text.Encoding]::ASCII.GetString($bytes, 0, 4) -ne "WDBC") { throw "$($file.Name): no es un WDBC" }
    $recordCount = [BitConverter]::ToUInt32($bytes, 4)
    $fieldCount = [BitConverter]::ToUInt32($bytes, 8)
    $recordSize = [BitConverter]::ToUInt32($bytes, 12)
    $stringSize = [BitConverter]::ToUInt32($bytes, 16)
    if ($recordSize -ne $fieldCount * 4) { throw "$($file.Name): campos de tamano distinto de 4 bytes (no soportado)" }
    if ($columns.Count -ne $fieldCount) { throw "${table}: $($columns.Count) columnas, $($file.Name) tiene $fieldCount campos" }

    # Registros originales (por ID, para sustituir) y bloque de cadenas (se anaden las nuevas al final)
    $records = New-Object System.Collections.Generic.List[byte[]]
    $index = @{}
    for ($i = 0; $i -lt $recordCount; $i++)
    {
        $record = New-Object byte[] $recordSize
        [Array]::Copy($bytes, 20 + $i * $recordSize, $record, 0, $recordSize)
        $index[[BitConverter]::ToUInt32($record, 0)] = $records.Count
        $records.Add($record)
    }
    $strings = New-Object System.IO.MemoryStream
    $strings.Write($bytes, 20 + $recordCount * $recordSize, $stringSize)
    $stringOffsets = @{ "" = 0 }

    $rows = Get-Rows (Invoke-MySqlXml "SELECT * FROM ``$table`` WHERE $(Get-IdFilter $table $columns[0].Name) ORDER BY 1")
    $added = 0; $replaced = 0
    foreach ($row in $rows)
    {
        $record = New-Object byte[] $recordSize
        for ($f = 0; $f -lt $fieldCount; $f++)
        {
            $value = $row[$f]
            $type = $columns[$f].Type
            if ($intTypes -contains $type)
            {
                $number = if ($null -eq $value) { [int64]0 } else { [int64]$value }
                $field = [BitConverter]::GetBytes([uint32]($number -band [int64]4294967295))
            }
            elseif ($floatTypes -contains $type)
            {
                $number = if ($null -eq $value) { 0.0 } else { [double]::Parse($value, [Globalization.CultureInfo]::InvariantCulture) }
                $field = [BitConverter]::GetBytes([single]$number)
            }
            else
            {
                $text = if ($null -eq $value) { "" } else { [string]$value }
                if (-not $stringOffsets.ContainsKey($text))
                {
                    $stringOffsets[$text] = [uint32]$strings.Length
                    $encoded = $utf8.GetBytes($text)
                    $strings.Write($encoded, 0, $encoded.Length)
                    $strings.WriteByte(0)
                }
                $field = [BitConverter]::GetBytes([uint32]$stringOffsets[$text])
            }
            [Array]::Copy($field, 0, $record, $f * 4, 4)
        }

        $id = [BitConverter]::ToUInt32($record, 0)
        if ($index.ContainsKey($id)) { $records[$index[$id]] = $record; $replaced++ }
        else { $index[$id] = $records.Count; $records.Add($record); $added++ }
    }

    $out = New-Object System.IO.MemoryStream
    $writer = New-Object System.IO.BinaryWriter($out)
    $writer.Write([System.Text.Encoding]::ASCII.GetBytes("WDBC"))
    $writer.Write([uint32]$records.Count)
    $writer.Write([uint32]$fieldCount)
    $writer.Write([uint32]$recordSize)
    $writer.Write([uint32]$strings.Length)
    foreach ($record in $records) { $writer.Write($record) }
    $writer.Write($strings.ToArray())
    $writer.Flush()
    [System.IO.File]::WriteAllBytes((Join-Path $OutDir $file.Name), $out.ToArray())

    Write-Host "DBC: $($file.Name) <- $table ($added nuevas, $replaced sustituidas)"
}
