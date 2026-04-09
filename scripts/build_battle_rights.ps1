param(
    [string]$RootDir = (Split-Path -Parent $PSScriptRoot),
    [string]$OutDir = (Join-Path (Split-Path -Parent $PSScriptRoot) "_battle_rights")
)

$ErrorActionPreference = "Stop"

function Ensure-Dir([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -ItemType Directory -Path $Path | Out-Null
    }
}

function Write-Utf8([string]$Path, [string]$Text) {
    Ensure-Dir (Split-Path -Parent $Path)
    [IO.File]::WriteAllText($Path, $Text.Trim() + "`r`n", (New-Object Text.UTF8Encoding($true)))
}

$rightsProbeDir = Join-Path $RootDir "_dump_rights_probe"
if (-not (Test-Path -LiteralPath $rightsProbeDir)) {
    throw "Rights probe directory not found: $rightsProbeDir"
}

$fullRightsName = ([string][char]0x41F) + ([string][char]0x43E) + ([string][char]0x43B) + ([string][char]0x43D) + ([string][char]0x44B) + ([string][char]0x435) + ([string][char]0x41F) + ([string][char]0x440) + ([string][char]0x430) + ([string][char]0x432) + ([string][char]0x430)
$roleWord = ([string][char]0x420) + ([string][char]0x43E) + ([string][char]0x43B) + ([string][char]0x44C)
$rightsWord = ([string][char]0x41F) + ([string][char]0x440) + ([string][char]0x430) + ([string][char]0x432) + ([string][char]0x430)
$template = Get-ChildItem -Path $rightsProbeDir -Filter '*.xml' -File |
    Where-Object { $_.Name.Contains($fullRightsName) } |
    Select-Object -First 1

if (-not $template) {
    throw "Full rights template not found in: $rightsProbeDir"
}

$content = [IO.File]::ReadAllText($template.FullName, [Text.Encoding]::UTF8)
$content = $content.Replace("<setForNewObjects>false</setForNewObjects>", "<setForNewObjects>true</setForNewObjects>")
$content = $content.Replace("<value>false</value>", "<value>true</value>")

if (Test-Path -LiteralPath $OutDir) {
    Remove-Item -LiteralPath $OutDir -Recurse -Force
}
Ensure-Dir $OutDir

$roleNames = Get-ChildItem -Path (Join-Path $RootDir "Roles") -Directory | Sort-Object Name | Select-Object -ExpandProperty Name
foreach ($roleName in $roleNames) {
    Write-Utf8 (Join-Path $OutDir "$roleWord.$roleName.$rightsWord.xml") $content
}

[pscustomobject]@{
    OutDir = $OutDir
    Template = $template.FullName
    Roles = $roleNames.Count
} | Format-List
