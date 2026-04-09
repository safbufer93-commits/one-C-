param(
    [string]$RootDir = (Split-Path -Parent $PSScriptRoot),
    [string]$DumpDir = (Join-Path (Split-Path -Parent $PSScriptRoot) "_real_loadable_dump"),
    [string]$TemplateDbDir = (Join-Path (Split-Path -Parent $PSScriptRoot) "_probe_db"),
    [string]$TestDbDir = (Join-Path (Split-Path -Parent $PSScriptRoot) "_verify_real_dump_db"),
    [string]$LogFile = (Join-Path (Split-Path -Parent $PSScriptRoot) "_verify_real_dump.log"),
    [string]$OneCExe = 'C:\Program Files (x86)\1cv8\8.3.27.1936\bin\1cv8.exe'
)

$ErrorActionPreference = 'Stop'

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

Assert-InsideRoot $RootDir $DumpDir
Assert-InsideRoot $RootDir $TemplateDbDir
Assert-InsideRoot $RootDir $TestDbDir
Assert-InsideRoot $RootDir $LogFile

Ensure-Exists $OneCExe '1C executable'
Ensure-Exists $DumpDir 'Dump directory'
Ensure-Exists $TemplateDbDir 'Template database'

if (Test-Path -LiteralPath $TestDbDir) {
    Remove-Item -LiteralPath $TestDbDir -Recurse -Force
}

Copy-Item -LiteralPath $TemplateDbDir -Destination $TestDbDir -Recurse -Force

if (Test-Path -LiteralPath $LogFile) {
    Remove-Item -LiteralPath $LogFile -Force
}

$arguments = @(
    'DESIGNER',
    '/F', $TestDbDir,
    '/LoadConfigFromFiles', $DumpDir,
    '/Out', $LogFile,
    '/DisableStartupMessages'
)

$process = Start-Process -FilePath $OneCExe -ArgumentList $arguments -PassThru -Wait

[pscustomobject]@{
    ExitCode = $process.ExitCode
    TestDbDir = $TestDbDir
    DumpDir = $DumpDir
    LogFile = $LogFile
} | Format-List

if (Test-Path -LiteralPath $LogFile) {
    Get-Content -LiteralPath $LogFile
}
