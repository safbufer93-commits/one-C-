param(
    [string]$RootDir = (Split-Path -Parent $PSScriptRoot),
    [string]$SourceDumpDir = (Join-Path (Split-Path -Parent $PSScriptRoot) "_real_loadable_dump"),
    [string]$OutDir = (Join-Path (Split-Path -Parent $PSScriptRoot) "_probe_subsystem_content_dump"),
    [ValidateSet('Item', 'ContentItem', 'Value', 'Text', 'XrItem')]
    [string]$TagName = 'Item',
    [ValidateSet('short', 'full')]
    [string]$ReferenceMode = 'full'
)

$ErrorActionPreference = "Stop"

function Patch-SubsystemContent([string]$FilePath, [string[]]$Refs, [string]$CurrentTagName) {
    $content = [IO.File]::ReadAllText($FilePath, [Text.Encoding]::UTF8)
    if ($CurrentTagName -eq 'Text') {
        $replacement = "`t`t`t<Content>$($Refs -join ' ')</Content>"
    } else {
        $items = foreach ($ref in $Refs) {
            if ($CurrentTagName -eq 'Value') {
                "`t`t`t`t<v8:Value>$ref</v8:Value>"
            } elseif ($CurrentTagName -eq 'XrItem') {
                "`t`t`t`t<xr:Item xsi:type=""xr:MDObjectRef"">$ref</xr:Item>"
            } else {
                "`t`t`t`t<$CurrentTagName>$ref</$CurrentTagName>"
            }
        }
        $replacement = @(
            "`t`t`t<Content>"
            ($items -join "`r`n")
            "`t`t`t</Content>"
        ) -join "`r`n"
    }

    if ($content -match "<Content\s*/>") {
        $updated = [Text.RegularExpressions.Regex]::Replace(
            $content,
            "<Content\s*/>",
            $replacement,
            [Text.RegularExpressions.RegexOptions]::Singleline
        )
    } else {
        $updated = [Text.RegularExpressions.Regex]::Replace(
            $content,
            "<Comment\s*/>",
            "<Comment/>`r`n$replacement",
            [Text.RegularExpressions.RegexOptions]::Singleline
        )
    }
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

$ordersSubsystem = ([string][char]0x417) + ([string][char]0x430) + ([string][char]0x43A) + ([string][char]0x430) + ([string][char]0x437) + ([string][char]0x44B)
$nsiSubsystem = ([string][char]0x41D) + ([string][char]0x421) + ([string][char]0x418)
$orderName = ([string][char]0x417) + ([string][char]0x430) + ([string][char]0x43A) + ([string][char]0x430) + ([string][char]0x437)
$goodsName = ([string][char]0x422) + ([string][char]0x43E) + ([string][char]0x432) + ([string][char]0x430) + ([string][char]0x440) + ([string][char]0x44B)

$orderRef = if ($ReferenceMode -eq 'full') { "Document.$orderName" } else { $orderName }
$goodsRef = if ($ReferenceMode -eq 'full') { "Catalog.$goodsName" } else { $goodsName }

Patch-SubsystemContent -FilePath (Resolve-ObjectFile (Join-Path $OutDir "Subsystems") $ordersSubsystem) -Refs @($orderRef) -CurrentTagName $TagName
Patch-SubsystemContent -FilePath (Resolve-ObjectFile (Join-Path $OutDir "Subsystems") $nsiSubsystem) -Refs @($goodsRef) -CurrentTagName $TagName

[pscustomobject]@{
    OutDir = $OutDir
    TagName = $TagName
    ReferenceMode = $ReferenceMode
} | Format-List
