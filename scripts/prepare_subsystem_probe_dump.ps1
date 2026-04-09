param(
    [string]$RootDir = (Split-Path -Parent $PSScriptRoot),
    [string]$SourceDumpDir = (Join-Path (Split-Path -Parent $PSScriptRoot) "_real_loadable_dump"),
    [string]$OutDir = (Join-Path (Split-Path -Parent $PSScriptRoot) "_probe_subsystems_dump"),
    [ValidateSet('name', 'full')]
    [string]$Variant = 'full'
)

$ErrorActionPreference = "Stop"

function Insert-SubsystemsProperty([string]$FilePath, [string[]]$SubsystemNames, [string]$VariantName) {
    $content = [IO.File]::ReadAllText($FilePath, [Text.Encoding]::UTF8)
    $values = foreach ($subsystemName in $SubsystemNames) {
        $ref = if ($VariantName -eq 'full') { "Subsystem.$subsystemName" } else { $subsystemName }
        "`t`t`t<Subsystem>$ref</Subsystem>"
    }
    $snippet = @(
        "`t`t`t<Subsystems>"
        ($values -join "`r`n")
        "`t`t`t</Subsystems>"
    ) -join "`r`n"

    if ($content -match '<Subsystems>') {
        return
    }

    $updated = [Text.RegularExpressions.Regex]::Replace(
        $content,
        "<UseStandardCommands>true</UseStandardCommands>",
        "<UseStandardCommands>true</UseStandardCommands>`r`n$snippet",
        [Text.RegularExpressions.RegexOptions]::Singleline
    )
    [IO.File]::WriteAllText($FilePath, $updated, (New-Object Text.UTF8Encoding($false)))
}

function Resolve-ObjectFile([string]$DirPath, [string]$BaseName) {
    $file = Get-ChildItem -Path $DirPath -File | Where-Object { $_.BaseName -eq $BaseName } | Select-Object -First 1
    if (-not $file) {
        throw "Object file not found in $DirPath for $BaseName"
    }
    return $file.FullName
}

if (Test-Path -LiteralPath $OutDir) {
    Remove-Item -LiteralPath $OutDir -Recurse -Force
}

Copy-Item -LiteralPath $SourceDumpDir -Destination $OutDir -Recurse

$orderName = ([string][char]0x417) + ([string][char]0x430) + ([string][char]0x43A) + ([string][char]0x430) + ([string][char]0x437)
$goodsName = ([string][char]0x422) + ([string][char]0x43E) + ([string][char]0x432) + ([string][char]0x430) + ([string][char]0x440) + ([string][char]0x44B)
$ordersSubsystem = ([string][char]0x417) + ([string][char]0x430) + ([string][char]0x43A) + ([string][char]0x430) + ([string][char]0x437) + ([string][char]0x44B)
$nsiSubsystem = ([string][char]0x41D) + ([string][char]0x421) + ([string][char]0x418)

Insert-SubsystemsProperty -FilePath (Resolve-ObjectFile (Join-Path $OutDir "Documents") $orderName) -SubsystemNames @($ordersSubsystem) -VariantName $Variant
Insert-SubsystemsProperty -FilePath (Resolve-ObjectFile (Join-Path $OutDir "Catalogs") $goodsName) -SubsystemNames @($nsiSubsystem) -VariantName $Variant

[pscustomobject]@{
    OutDir = $OutDir
    Variant = $Variant
    PatchedFiles = 2
} | Format-List
