param(
    [string]$RootDir = (Split-Path -Parent $PSScriptRoot),
    [string]$ExtractPath = (Join-Path (Split-Path -Parent $PSScriptRoot) "docs\source_extract\workbook_extract.json"),
    [string]$VerifiedDumpDir = (Join-Path (Split-Path -Parent $PSScriptRoot) "_verify_after_load_dump"),
    [string]$OutPath = (Join-Path (Split-Path -Parent $PSScriptRoot) "docs\source_extract\coverage_report.md")
)

$ErrorActionPreference = "Stop"

function Normalize([string]$Value) {
    if ([string]::IsNullOrWhiteSpace($Value)) { return "" }
    return ($Value -replace "\s+", "").Trim()
}

function Load-Json([string]$Path) {
    Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
}

function Load-Xml([string]$Path) {
    $xml = New-Object Xml.XmlDocument
    $xml.LoadXml([IO.File]::ReadAllText($Path, [Text.Encoding]::UTF8))
    $xml
}

function Get-TabularSectionsFromModel([string]$BaseDir) {
    $result = @()

    foreach ($kind in @("Documents", "Catalogs")) {
        $dir = Join-Path $BaseDir $kind
        if (-not (Test-Path -LiteralPath $dir)) { continue }

        $xmlFiles = @()
        $xmlFiles += Get-ChildItem -LiteralPath $dir -Directory | ForEach-Object {
            $candidate = Join-Path $_.FullName ($_.Name + ".xml")
            if (Test-Path -LiteralPath $candidate) {
                Get-Item -LiteralPath $candidate
            }
        }
        $xmlFiles += Get-ChildItem -LiteralPath $dir -File -Filter *.xml

        foreach ($xmlFile in $xmlFiles) {
            $xml = Load-Xml $xmlFile.FullName
            $sections = $xml.SelectNodes('/*/*[local-name()="TabularSection"]')
            foreach ($section in $sections) {
                $nameNode = $section.SelectSingleNode('./*[local-name()="n"]')
                if ($null -eq $nameNode) {
                    $nameNode = $section.SelectSingleNode('./*[local-name()="Properties"]/*[local-name()="Name"]')
                }
                if ($null -eq $nameNode) { continue }
                $ownerName = [IO.Path]::GetFileNameWithoutExtension($xmlFile.Name)
                $result += "$($kind.Substring(0, $kind.Length - 1)).$ownerName.$($nameNode.InnerText)"
            }
        }
    }

    return $result
}

function Get-TopLevelObjects([string]$BaseDir) {
    $map = [ordered]@{
        "Catalog" = "Catalogs"
        "Document" = "Documents"
        "InformationRegister" = "InformationRegisters"
        "AccumulationRegister" = "AccumulationRegisters"
    }

    $result = @()
    foreach ($key in $map.Keys) {
        $dir = Join-Path $BaseDir $map[$key]
        if (-not (Test-Path -LiteralPath $dir)) { continue }
        foreach ($objDir in Get-ChildItem -LiteralPath $dir -Directory) {
            $result += "$key.$($objDir.Name)"
        }
        foreach ($xmlFile in Get-ChildItem -LiteralPath $dir -File -Filter *.xml) {
            $result += "$key.$([IO.Path]::GetFileNameWithoutExtension($xmlFile.Name))"
        }
    }
    return $result
}

function Expand-List($Items) {
    if ($null -eq $Items -or $Items.Count -eq 0) {
        return @("- none")
    }
    return @($Items | Sort-Object -Unique | ForEach-Object { "- $_" })
}

$extract = Load-Json $ExtractPath

$entitySheet = $extract.sheets[4]
$tableSheet = $extract.sheets[7]
$registerSheet = $extract.sheets[8]

$sourceEntities = @()
foreach ($row in $entitySheet.rows | Select-Object -Skip 1) {
    if ($row.Count -lt 3) { continue }
    $type = Normalize $row[1]
    $name = Normalize $row[2]
    if (-not $type -or -not $name) { continue }
    $sourceEntities += [pscustomobject]@{
        Key  = "$type.$name"
        Type = $row[1]
        Name = $row[2]
    }
}

$sourceTableParts = @()
foreach ($row in $tableSheet.rows | Select-Object -Skip 1) {
    if ($row.Count -lt 3) { continue }
    $owner = Normalize $row[1]
    $part = Normalize $row[2]
    if (-not $owner -or -not $part) { continue }
    $sourceTableParts += [pscustomobject]@{
        Key = "$owner.$part"
        Owner = $row[1]
        Part = $row[2]
    }
}

$sourceRegisters = @()
foreach ($row in $registerSheet.rows | Select-Object -Skip 1) {
    if ($row.Count -lt 2) { continue }
    $name = Normalize $row[1]
    if (-not $name) { continue }
    $sourceRegisters += [pscustomobject]@{
        Key = $name
        Name = $row[1]
        Kind = $row[2]
    }
}

$projectObjects = Get-TopLevelObjects $RootDir
$projectParts = Get-TabularSectionsFromModel $RootDir
$verifiedObjects = Get-TopLevelObjects $VerifiedDumpDir
$verifiedParts = Get-TabularSectionsFromModel $VerifiedDumpDir

$projectObjectSet = @{}
foreach ($item in $projectObjects) { $projectObjectSet[(Normalize $item)] = $true }

$verifiedObjectSet = @{}
foreach ($item in $verifiedObjects) { $verifiedObjectSet[(Normalize $item)] = $true }

$projectPartSet = @{}
foreach ($item in $projectParts) { $projectPartSet[(Normalize $item)] = $true }

$verifiedPartSet = @{}
foreach ($item in $verifiedParts) { $verifiedPartSet[(Normalize $item)] = $true }

$missingInProject = @()
$missingInVerified = @()

foreach ($src in $sourceEntities) {
    $normalized = Normalize $src.Key
    if (-not $projectObjectSet.ContainsKey($normalized)) {
        $missingInProject += $src.Key
    }
    if (-not $verifiedObjectSet.ContainsKey($normalized)) {
        $missingInVerified += $src.Key
    }
}

$missingPartsInProject = @()
$missingPartsInVerified = @()

foreach ($src in $sourceTableParts) {
    $normalized = Normalize $src.Key
    if (-not $projectPartSet.ContainsKey($normalized)) {
        $missingPartsInProject += $src.Key
    }
    if (-not $verifiedPartSet.ContainsKey($normalized)) {
        $missingPartsInVerified += $src.Key
    }
}

$lines = @()
$lines += "# Coverage Report"
$lines += ""
$lines += "Source entities: $($sourceEntities.Count)"
$lines += "Source table parts: $($sourceTableParts.Count)"
$lines += "Source registers rows: $($sourceRegisters.Count)"
$lines += ""
$lines += "## Current Project"
$lines += ""
$lines += "Top-level objects found: $($projectObjects.Count)"
$lines += "Tabular sections found: $($projectParts.Count)"
$lines += ""
$lines += "Missing top-level objects from source:"
$lines += Expand-List $missingInProject
$lines += ""
$lines += "Missing tabular sections from source:"
$lines += Expand-List $missingPartsInProject
$lines += ""
$lines += "## Verified Loadable Dump"
$lines += ""
$lines += "Top-level objects found: $($verifiedObjects.Count)"
$lines += "Tabular sections found: $($verifiedParts.Count)"
$lines += ""
$lines += "Missing top-level objects from source:"
$lines += Expand-List $missingInVerified
$lines += ""
$lines += "Missing tabular sections from source:"
$lines += Expand-List $missingPartsInVerified

$parent = Split-Path -Parent $OutPath
if (-not (Test-Path -LiteralPath $parent)) {
    New-Item -ItemType Directory -Path $parent | Out-Null
}

[IO.File]::WriteAllText($OutPath, ($lines -join "`r`n") + "`r`n", [Text.UTF8Encoding]::new($false))
Write-Output $OutPath
