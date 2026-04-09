param(
    [string]$RootDir = (Split-Path -Parent $PSScriptRoot),
    [string]$RightsDir = (Join-Path (Split-Path -Parent $PSScriptRoot) "_battle_rights"),
    [string]$DbDir = (Join-Path (Split-Path -Parent $PSScriptRoot) "_verify_real_dump_db"),
    [string]$LogFile = (Join-Path (Split-Path -Parent $PSScriptRoot) "_apply_rights_to_db.log"),
    [string]$OneCExe = 'C:\Program Files (x86)\1cv8\8.3.27.1936\bin\1cv8.exe'
)

$ErrorActionPreference = "Stop"

function Assert-InsideRoot([string]$RootPath, [string]$TargetPath) {
    $root = [IO.Path]::GetFullPath($RootPath)
    $target = [IO.Path]::GetFullPath($TargetPath)
    if (-not $target.StartsWith($root, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Path is outside workspace: $target"
    }
}

function Ensure-Exists([string]$Path, [string]$Label) {
    if (-not (Test-Path -LiteralPath $Path)) {
        throw "$Label not found: $Path"
    }
}

Assert-InsideRoot $RootDir $RightsDir
Assert-InsideRoot $RootDir $DbDir
Assert-InsideRoot $RootDir $LogFile

Ensure-Exists $OneCExe '1C executable'
Ensure-Exists $RightsDir 'Rights directory'
Ensure-Exists $DbDir 'Database directory'

$rightsFiles = Get-ChildItem -Path $RightsDir -Filter '*.xml' -File -ErrorAction Stop
if ($rightsFiles.Count -eq 0) {
    throw "Rights files not found in $RightsDir"
}

if (Test-Path -LiteralPath $LogFile) {
    Remove-Item -LiteralPath $LogFile -Force
}

$arguments = @(
    'DESIGNER',
    '/F', $DbDir,
    '/LoadConfigFiles', $RightsDir,
    '-Right',
    '/Out', $LogFile,
    '/DisableStartupMessages'
)

$process = Start-Process -FilePath $OneCExe -ArgumentList $arguments -PassThru -Wait

[pscustomobject]@{
    ExitCode = $process.ExitCode
    RightsDir = $RightsDir
    DbDir = $DbDir
    RightsFiles = $rightsFiles.Count
    LogFile = $LogFile
} | Format-List

if (Test-Path -LiteralPath $LogFile) {
    Get-Content -LiteralPath $LogFile
}
