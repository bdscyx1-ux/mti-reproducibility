[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$ProjectPath,
    [Parameter(Mandatory = $true)][string]$OutputPath,
    [switch]$BindingSmokeOnly
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

if ([string]::IsNullOrWhiteSpace($ProjectPath) -or -not [IO.Path]::IsPathRooted($ProjectPath)) {
    throw 'Gate12R failed-pilot preservation audit v3 requires an explicit absolute ProjectPath.'
}
$ProjectPath = [IO.Path]::GetFullPath($ProjectPath)
if ($BindingSmokeOnly) {
    Write-Output "BINDING-SMOKE-PASSED|Test-Gate12RFailedPilotPreservationV3|$ProjectPath"
    exit 0
}
$OutputPath = [IO.Path]::GetFullPath($OutputPath)
$priorAudit = $OutputPath + '.attempts1-2.json'
foreach ($path in @($OutputPath, $priorAudit, $priorAudit + '.attempt1.json')) {
    if (Test-Path -LiteralPath $path) {
        throw "Create-new preservation audit output exists: $path"
    }
}

function Get-LowerSha256([string]$Path) {
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

$windowsPowerShell = 'C:\WINDOWS\System32\WindowsPowerShell\v1.0\powershell.exe'
$priorScript = Join-Path $ProjectPath 'Research\Verification\Test-Gate12RFailedPilotPreservationV2.ps1'
& $windowsPowerShell -NoProfile -ExecutionPolicy Bypass -File $priorScript -ProjectPath $ProjectPath -OutputPath $priorAudit
if ($LASTEXITCODE -ne 0) {
    throw "Attempts 1-2 preservation re-audit failed: $LASTEXITCODE"
}
$prior = Get-Content -LiteralPath $priorAudit -Raw -Encoding UTF8 | ConvertFrom-Json
if ($prior.passed -ne $true) {
    throw 'Attempts 1-2 preservation re-audit did not pass.'
}

$attempt3Root = Join-Path $ProjectPath 'Research\PilotRuns\Gate12R_ProcessReuse_5pct\v3'
$partialPath = Join-Path $attempt3Root 'partial-output-manifest.json'
$partial = Get-Content -LiteralPath $partialPath -Raw -Encoding UTF8 | ConvertFrom-Json
$bad = New-Object Collections.Generic.List[object]
foreach ($row in @($partial.files)) {
    $path = Join-Path $ProjectPath ([string]$row.relativePath).Replace('/', '\')
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        $bad.Add([pscustomobject]@{ relativePath = $row.relativePath; reason = 'missing' })
        continue
    }
    $file = Get-Item -LiteralPath $path
    if ([long]$file.Length -ne [long]$row.rawBytes) {
        $bad.Add([pscustomobject]@{ relativePath = $row.relativePath; reason = 'length' })
        continue
    }
    if ((Get-LowerSha256 $path) -ne [string]$row.sha256) {
        $bad.Add([pscustomobject]@{ relativePath = $row.relativePath; reason = 'sha256' })
    }
}

$rootFiles = @(Get-ChildItem -LiteralPath $attempt3Root -Recurse -File -Force)
$rootRawBytes = [long](($rootFiles | Measure-Object Length -Sum).Sum)
$preservationPath = Join-Path $ProjectPath 'Research\Gate12R_PilotAttempt3_Terminal_Preservation.v1.json'
$checkpointPath = Join-Path $attempt3Root 'pilot-checkpoint.json'
$failurePath = Join-Path $attempt3Root 'failure-receipt.json'
$executionReceiptPath = Join-Path $attempt3Root 'execution-receipt.json'
$passed = $prior.passed -eq $true -and
    $bad.Count -eq 0 -and
    @($partial.files).Count -eq 7554 -and
    [long]$partial.rawBytes -eq 493784387 -and
    $rootFiles.Count -eq 7555 -and
    $rootRawBytes -eq 496451579 -and
    (Get-LowerSha256 $partialPath) -eq 'd42366ef313834ade6ae4c3cdcfe356eb9b58a8155808a56e7bebf83862b2039' -and
    (Get-LowerSha256 $checkpointPath) -eq 'ad2d2152780b60f6bed68f19ea5df68d14ce9f265b1b89b15c28f7e11d24d5a0' -and
    (Get-LowerSha256 $failurePath) -eq '9118dd4a383526a5361169e8d2bd896c15986e0b4e5158b8f7dd294b1309f509' -and
    (Get-LowerSha256 $executionReceiptPath) -eq '3c71438bfdd858f16dafae0170a006e4e7780256845eebda7f2674d3587bb6f9' -and
    (Get-LowerSha256 $preservationPath) -eq 'ceb2562c6f3918f5e68fe32ce52c7b334af028e56ce974aab7feb6e2b91fc511'

$result = [ordered]@{
    schemaVersion = 1
    auditKind = 'gate12r-failed-pilot-attempts-1-through-3-preservation-audit-v3'
    completedAtUtc = [DateTime]::UtcNow.ToString('o')
    attempts1And2AuditRelativePath = $priorAudit.Substring($ProjectPath.TrimEnd('\').Length + 1).Replace('\', '/')
    attempts1And2AuditSha256 = Get-LowerSha256 $priorAudit
    attempts1And2Passed = $prior.passed
    attempt3Root = 'Research/PilotRuns/Gate12R_ProcessReuse_5pct/v3'
    attempt3ListedFileCount = @($partial.files).Count
    attempt3ListedRawBytes = [long]$partial.rawBytes
    attempt3RootFileCount = $rootFiles.Count
    attempt3RootRawBytes = $rootRawBytes
    attempt3BadFileCount = $bad.Count
    attempt3BadFiles = @($bad | Select-Object -First 20)
    attempt3PartialManifestSha256 = Get-LowerSha256 $partialPath
    attempt3CheckpointSha256 = Get-LowerSha256 $checkpointPath
    attempt3FailureReceiptSha256 = Get-LowerSha256 $failurePath
    attempt3ExecutionReceiptSha256 = Get-LowerSha256 $executionReceiptPath
    attempt3PreservationReceiptSha256 = Get-LowerSha256 $preservationPath
    attempts1Through3ResumeAuthorized = $false
    attempts1Through3MergeAuthorized = $false
    gate13rRootAbsent = -not (Test-Path -LiteralPath (Join-Path $ProjectPath 'Research\FormalRuns\Gate13R_ProcessReuse_5pct\v1'))
    passed = $passed
}
$parent = Split-Path -Parent $OutputPath
if (-not (Test-Path -LiteralPath $parent)) {
    New-Item -ItemType Directory -Path $parent -Force | Out-Null
}
$json = ($result | ConvertTo-Json -Depth 20).Replace("`r`n", "`n").Replace("`r", "`n") + "`n"
[IO.File]::WriteAllText($OutputPath, $json, (New-Object Text.UTF8Encoding($false, $true)))
if (-not $passed) {
    throw 'Failed-pilot attempts 1-3 preservation audit did not pass.'
}
$result | ConvertTo-Json -Depth 20
