param(
    [string]$SourceDir = (Split-Path -Parent $PSScriptRoot),
    [string]$DestinationDir = (Join-Path (Split-Path -Parent $PSScriptRoot) "_fixed_dump")
)

$ErrorActionPreference = "Stop"

function Ensure-Directory {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -ItemType Directory -Path $Path | Out-Null
    }
}

function Write-Utf8NoBom {
    param(
        [string]$Path,
        [string]$Content
    )

    $encoding = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path, $Content, $encoding)
}

function Get-RelativePathCompat {
    param(
        [string]$BasePath,
        [string]$TargetPath
    )

    $baseUri = New-Object System.Uri(($BasePath.TrimEnd('\') + '\'))
    $targetUri = New-Object System.Uri($TargetPath)
    return [System.Uri]::UnescapeDataString($baseUri.MakeRelativeUri($targetUri).ToString()).Replace('/', '\')
}

function Convert-MdClassXml {
    param([string]$Content)

    $updated = $Content
    $updated = $updated -replace 'xmlns:mdclass="http://v8\.1c\.ru/8\.3/MDClasses"', 'xmlns="http://v8.1c.ru/8.3/MDClasses"'
    $updated = $updated -replace '\s+xmlns:xsi="http://www\.w3\.org/2001/XMLSchema-instance"', ""
    $updated = $updated -replace '\s+xsi:type="mdclass:[^"]+"', ""
    $updated = $updated -replace '<(/?)mdclass:', '<$1'
    return $updated
}

function Get-ChildObjectsBlock {
    param([string]$BaseDir)

    $groups = @(
        @{ Folder = "Enums"; Type = "Enum" },
        @{ Folder = "Catalogs"; Type = "Catalog" },
        @{ Folder = "Documents"; Type = "Document" },
        @{ Folder = "InformationRegisters"; Type = "InformationRegister" },
        @{ Folder = "AccumulationRegisters"; Type = "AccumulationRegister" },
        @{ Folder = "Roles"; Type = "Role" },
        @{ Folder = "CommonModules"; Type = "CommonModule" }
    )

    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add("`t<ChildObjects>")

    foreach ($group in $groups) {
        $folderPath = Join-Path $BaseDir $group.Folder
        if (-not (Test-Path -LiteralPath $folderPath)) {
            continue
        }

        Get-ChildItem -LiteralPath $folderPath -Directory |
            Sort-Object Name |
            ForEach-Object {
                $lines.Add("`t`t<$($group.Type)>$($group.Type).$($_.Name)</$($group.Type)>")
            }
    }

    $lines.Add("`t</ChildObjects>")
    return [string]::Join("`r`n", $lines)
}

function Update-ConfigurationXml {
    param([string]$FilePath)

    $content = [System.IO.File]::ReadAllText($FilePath, [System.Text.Encoding]::UTF8)

    $content = [System.Text.RegularExpressions.Regex]::Replace(
        $content,
        '<ChildObjects>[\s\S]*?</ChildObjects>',
        (Get-ChildObjectsBlock -BaseDir (Split-Path -Parent $FilePath)),
        [System.Text.RegularExpressions.RegexOptions]::Singleline
    )

    if ($content -notmatch '<DefaultRoles>') {
        $defaultRolesBlock = @"
	<DefaultRoles>
		<Role>Role.ПолныеПрава</Role>
	</DefaultRoles>
"@
        $content = $content -replace '(\s*<ChildObjects>)', "`r`n$defaultRolesBlock`r`n`t<ChildObjects>"
    }

    Write-Utf8NoBom -Path $FilePath -Content $content
}

$sourcePath = (Resolve-Path -LiteralPath $SourceDir).Path

if (Test-Path -LiteralPath $DestinationDir) {
    Remove-Item -LiteralPath $DestinationDir -Recurse -Force
}

Ensure-Directory -Path $DestinationDir

Get-ChildItem -LiteralPath $sourcePath -Recurse -File | ForEach-Object {
    $relativePath = Get-RelativePathCompat -BasePath $sourcePath -TargetPath $_.FullName

    if ($relativePath -like "_fixed_dump*" -or $relativePath -like "scripts\*") {
        return
    }

    $destinationPath = Join-Path $DestinationDir $relativePath
    Ensure-Directory -Path (Split-Path -Parent $destinationPath)

    if ($_.Extension -ieq ".xml") {
        $content = [System.IO.File]::ReadAllText($_.FullName, [System.Text.Encoding]::UTF8)
        $content = Convert-MdClassXml -Content $content
        Write-Utf8NoBom -Path $destinationPath -Content $content
    } else {
        Copy-Item -LiteralPath $_.FullName -Destination $destinationPath -Force
    }
}

Update-ConfigurationXml -FilePath (Join-Path $DestinationDir "Configuration.xml")

$xmlFiles = Get-ChildItem -LiteralPath $DestinationDir -Recurse -File -Filter *.xml
$leftoverPrefixes = $xmlFiles | Select-String -SimpleMatch "mdclass:" -List
$leftoverXsiTypes = $xmlFiles | Select-String -Pattern 'xsi:type=' -List

[pscustomobject]@{
    SourceDir = $sourcePath
    DestinationDir = (Resolve-Path -LiteralPath $DestinationDir).Path
    XmlFiles = $xmlFiles.Count
    HasMdclassPrefixes = [bool]$leftoverPrefixes
    HasXsiTypes = [bool]$leftoverXsiTypes
} | Format-List
