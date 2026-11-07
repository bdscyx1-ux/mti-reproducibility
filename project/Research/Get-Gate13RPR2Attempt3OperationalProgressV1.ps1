[CmdletBinding()]
param(
    [Parameter()]
    [string]$ProjectPath,

    [Parameter()]
    [string]$PythonPath,

    [Parameter()]
    [string]$ConfigPath,

    [Parameter()]
    [string]$NowUtc,

    [Parameter()]
    [string]$PreviousSnapshotPath,

    [Parameter()]
    [string]$OsFixturePath,

    [Parameter()]
    [string]$StatusSchemaPath,

    [Parameter()]
    [switch]$SkipOsQuery,

    [Parameter()]
    [switch]$WriteSnapshot,

    [Parameter()]
    [string]$SnapshotRoot,

    [Parameter()]
    [string]$OutputPath,

    [Parameter()]
    [switch]$RenderReport,

    [Parameter()]
    [switch]$CommandPreviewOnly
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

if ([string]::IsNullOrWhiteSpace($ProjectPath)) {
    $ProjectPath = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
}
else {
    $ProjectPath = [IO.Path]::GetFullPath($ProjectPath)
}
if ([string]::IsNullOrWhiteSpace($PythonPath)) {
    $PythonPath = 'C:\Users\bdscy\AppData\Local\Python\bin\python.exe'
}
if ([string]::IsNullOrWhiteSpace($ConfigPath)) {
    $ConfigPath = Join-Path $ProjectPath 'Research\Gate13R_PR2_Attempt3_Monitoring_Config.v1.json'
}

$monitorPath = Join-Path $ProjectPath 'Research\Gate13RPR2Attempt3MonitoringRecoveryV1.py'
foreach ($requiredPath in @($ProjectPath, $PythonPath, $ConfigPath, $monitorPath)) {
    if (-not (Test-Path -LiteralPath $requiredPath)) {
        throw "Required path does not exist: $requiredPath"
    }
}

$arguments = New-Object System.Collections.Generic.List[string]
$arguments.Add($monitorPath)
$arguments.Add('snapshot')
$arguments.Add('--config')
$arguments.Add([IO.Path]::GetFullPath($ConfigPath))
if (-not [string]::IsNullOrWhiteSpace($NowUtc)) {
    $arguments.Add('--now-utc')
    $arguments.Add($NowUtc)
}
if (-not [string]::IsNullOrWhiteSpace($PreviousSnapshotPath)) {
    $arguments.Add('--previous-snapshot')
    $arguments.Add([IO.Path]::GetFullPath($PreviousSnapshotPath))
}
if (-not [string]::IsNullOrWhiteSpace($OsFixturePath)) {
    $arguments.Add('--os-fixture')
    $arguments.Add([IO.Path]::GetFullPath($OsFixturePath))
}
if (-not [string]::IsNullOrWhiteSpace($StatusSchemaPath)) {
    $arguments.Add('--status-schema')
    $arguments.Add([IO.Path]::GetFullPath($StatusSchemaPath))
}
if ($SkipOsQuery) { $arguments.Add('--skip-os-query') }
if ($WriteSnapshot) { $arguments.Add('--write') }
if (-not [string]::IsNullOrWhiteSpace($SnapshotRoot)) {
    $arguments.Add('--snapshot-root')
    $arguments.Add([IO.Path]::GetFullPath($SnapshotRoot))
}
if (-not [string]::IsNullOrWhiteSpace($OutputPath)) {
    $arguments.Add('--output')
    $arguments.Add([IO.Path]::GetFullPath($OutputPath))
}
if ($RenderReport) { $arguments.Add('--render-report') }

if ($CommandPreviewOnly) {
    [pscustomobject]@{
        schemaVersion = 1
        previewKind = 'gate13r-pr2-attempt3-monitor-command-preview-v1'
        pythonPath = [IO.Path]::GetFullPath($PythonPath)
        argumentCount = $arguments.Count
        arguments = @($arguments)
        unityCommandPresent = $false
        experimentMutationAuthorized = $false
    } | ConvertTo-Json -Depth 8
    exit 0
}

& $PythonPath @arguments
if ($LASTEXITCODE -ne 0) {
    throw "Operational monitor exited with code $LASTEXITCODE."
}
