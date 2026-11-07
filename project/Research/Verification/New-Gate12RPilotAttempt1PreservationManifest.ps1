[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ProjectPath,

    [Parameter(Mandatory = $true)]
    [string]$OutputPath
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Get-LowerSha256 {
    param([Parameter(Mandatory = $true)][string]$LiteralPath)
    return (Get-FileHash -LiteralPath $LiteralPath -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Write-AtomicUtf8NoBomJson {
    param(
        [Parameter(Mandatory = $true)][string]$LiteralPath,
        [Parameter(Mandatory = $true)]$Value
    )

    $parent = Split-Path -Parent $LiteralPath
    if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }

    $temporary = Join-Path $parent (([IO.Path]::GetFileName($LiteralPath)) + '.tmp-' + [Guid]::NewGuid().ToString('N'))
    $json = ($Value | ConvertTo-Json -Depth 20).Replace("`r`n", "`n").Replace("`r", "`n") + "`n"
    [IO.File]::WriteAllText($temporary, $json, (New-Object Text.UTF8Encoding($false, $true)))
    Move-Item -LiteralPath $temporary -Destination $LiteralPath
}

if ([string]::IsNullOrWhiteSpace($ProjectPath) -or -not [IO.Path]::IsPathRooted($ProjectPath)) {
    throw 'ProjectPath must be an explicit absolute path.'
}
if ([string]::IsNullOrWhiteSpace($OutputPath) -or -not [IO.Path]::IsPathRooted($OutputPath)) {
    throw 'OutputPath must be an explicit absolute path.'
}

$ProjectPath = [IO.Path]::GetFullPath($ProjectPath)
$OutputPath = [IO.Path]::GetFullPath($OutputPath)
$pilotRoot = [IO.Path]::GetFullPath((Join-Path $ProjectPath 'Research\PilotRuns\Gate12R_ProcessReuse_5pct\v1'))
$partialManifestPath = Join-Path $pilotRoot 'partial-output-manifest.json'
$failureReceiptPath = Join-Path $pilotRoot 'failure-receipt.json'
$checkpointPath = Join-Path $pilotRoot 'pilot-checkpoint.json'
$executionReceiptPath = Join-Path $pilotRoot 'execution-receipt.json'
$failedBlockRoot = Join-Path $pilotRoot 'measured\07-core-r01-s1-hetero--per-agent\b017'
$failedBlockCheckpointPath = Join-Path $failedBlockRoot 'block-checkpoint.json'
$failedBlockFailurePath = Join-Path $failedBlockRoot 'block-failure.json'
$formalRoot = [IO.Path]::GetFullPath((Join-Path $ProjectPath 'Research\FormalRuns\Gate13R_ProcessReuse_5pct\v1'))

if (-not (Test-Path -LiteralPath $pilotRoot -PathType Container)) { throw "Pilot v1 root is missing: $pilotRoot" }
if ($OutputPath.StartsWith($pilotRoot.TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase)) {
    throw 'The preservation manifest must be written outside the frozen pilot v1 root.'
}
if (Test-Path -LiteralPath $OutputPath) { throw "Create-new output already exists: $OutputPath" }
if (Test-Path -LiteralPath $formalRoot) { throw 'Reserved Gate13R formal root must remain absent.' }

$expectedTerminalHashes = [ordered]@{
    'partial-output-manifest.json' = 'bc3cae1882de95e33ef0ea6004da9bcc4b6696a44d7493d7d5eacde362b8af5c'
    'failure-receipt.json'         = 'c47582f963bcd858675a63cde44a313ba86b7007659b3d05174660fa40b9e096'
    'pilot-checkpoint.json'        = '7ae759c80cf0e6a2dabb246c85e24967c2cbe1d6a66574303670a72387254a14'
    'execution-receipt.json'       = '91fd16ae85197c265fb076f48a695c07f7816b66b00df835bcaa1d240b1134b0'
}

foreach ($name in $expectedTerminalHashes.Keys) {
    $path = Join-Path $pilotRoot $name
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Terminal evidence is missing: $path" }
    $actual = Get-LowerSha256 -LiteralPath $path
    if ($actual -ne $expectedTerminalHashes[$name]) { throw "Terminal evidence changed: $name expected=$($expectedTerminalHashes[$name]) actual=$actual" }
}

$partialManifest = Get-Content -LiteralPath $partialManifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
$failureReceipt = Get-Content -LiteralPath $failureReceiptPath -Raw -Encoding UTF8 | ConvertFrom-Json
$checkpoint = Get-Content -LiteralPath $checkpointPath -Raw -Encoding UTF8 | ConvertFrom-Json
$failedBlockCheckpoint = Get-Content -LiteralPath $failedBlockCheckpointPath -Raw -Encoding UTF8 | ConvertFrom-Json
$failedBlockFailure = Get-Content -LiteralPath $failedBlockFailurePath -Raw -Encoding UTF8 | ConvertFrom-Json

if ([string]$partialManifest.status -ne 'failed-no-resume-no-merge' -or $partialManifest.formalCampaign -ne $false -or $partialManifest.excludedFromFormalAnalysis -ne $true) {
    throw 'Partial-output manifest terminal claims are not the frozen failed/excluded claims.'
}
if ([int]$partialManifest.fileCount -ne 5330 -or [long]$partialManifest.rawBytes -ne 2391606830L) {
    throw 'Partial-output manifest cardinality or byte count changed.'
}
if ([string]$failureReceipt.status -ne 'FAILED-NO-RESUME-NO-MERGE' -or $failureReceipt.measuredBlockStarted -ne $true -or [int]$failureReceipt.completedEntryCount -ne 246) {
    throw 'Failure receipt terminal claims changed.'
}
if ([string]$checkpoint.status -ne 'failed-no-resume-no-merge' -or [int]$checkpoint.completedEntryCount -ne 246 -or $checkpoint.automaticResumeAuthorized -ne $false) {
    throw 'Pilot checkpoint terminal claims changed.'
}
if ([string]$failedBlockCheckpoint.status -ne 'failed-no-auto-retry' -or [string]$failedBlockCheckpoint.error -ne 'Block retained managed-memory growth exceeded the frozen 128 MiB limit.') {
    throw 'Failed block checkpoint no longer records the frozen managed-memory hard failure.'
}

$declared = @{}
$verifiedBytes = 0L
$verifiedCount = 0
foreach ($entry in @($partialManifest.files)) {
    $relative = ([string]$entry.relativePath).Replace('/', '\')
    if ([string]::IsNullOrWhiteSpace($relative) -or $declared.ContainsKey($relative)) { throw "Invalid or duplicate manifest path: $relative" }
    $absolute = [IO.Path]::GetFullPath((Join-Path $ProjectPath $relative))
    if (-not $absolute.StartsWith($pilotRoot.TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase)) { throw "Manifest path escapes pilot v1: $relative" }
    if (-not (Test-Path -LiteralPath $absolute -PathType Leaf)) { throw "Frozen pilot file is missing: $relative" }
    $item = Get-Item -LiteralPath $absolute
    if ([long]$item.Length -ne [long]$entry.rawBytes) { throw "Frozen pilot byte count changed: $relative" }
    $actualSha = Get-LowerSha256 -LiteralPath $absolute
    if ($actualSha -ne [string]$entry.sha256) { throw "Frozen pilot hash changed: $relative" }
    $declared[$relative] = $true
    $verifiedBytes += [long]$item.Length
    $verifiedCount++
}

$actualFiles = @(Get-ChildItem -LiteralPath $pilotRoot -Recurse -File)
$partialRelative = 'Research\PilotRuns\Gate12R_ProcessReuse_5pct\v1\partial-output-manifest.json'
$unexpected = New-Object Collections.Generic.List[string]
foreach ($file in $actualFiles) {
    $relative = $file.FullName.Substring($ProjectPath.TrimEnd('\').Length + 1)
    if ($relative -ne $partialRelative -and -not $declared.ContainsKey($relative)) { $unexpected.Add($relative) }
}
if ($unexpected.Count -gt 0) { throw ('Unexpected file(s) appeared in frozen pilot v1: ' + ($unexpected -join '; ')) }
if ($actualFiles.Count -ne 5331) { throw "Frozen pilot v1 root file count changed: $($actualFiles.Count)" }
$actualRootBytes = [long](($actualFiles | Measure-Object -Property Length -Sum).Sum)
if ($actualRootBytes -ne 2393492252L) { throw "Frozen pilot v1 root raw bytes changed: $actualRootBytes" }
if ($verifiedCount -ne 5330 -or $verifiedBytes -ne 2391606830L) { throw 'Independent file verification totals do not match the frozen partial manifest.' }

$output = [ordered]@{
    schemaVersion = 1
    manifestKind = 'gate12r-pilot-attempt1-terminal-preservation-manifest-v1'
    savedAtUtc = [DateTime]::UtcNow.ToString('o')
    pilotRoot = $pilotRoot
    status = 'FAILED-NO-RESUME-NO-MERGE'
    formalCampaign = $false
    excludedFromFormalAnalysis = $true
    eligibleForSampleSizeEstimation = $false
    eligibleForGate13R = $false
    automaticRetryAuthorizedForThisRoot = $false
    automaticResumeAuthorizedForThisRoot = $false
    partialAttemptMergeAuthorized = $false
    completedEntryCount = 246
    warmupBlockCount = 8
    coldControlCount = 36
    completedMeasuredBlockCount = 202
    completedMeasuredSampleCount = 608
    failedMeasuredOrdinal = 247
    failedCampaignId = 'core-r01-s1-hetero--per-agent'
    failedBlock = 17
    primaryHardFailure = [ordered]@{
        message = [string]$failedBlockCheckpoint.error
        blockManagedGrowthBytes = 134512640L
        frozenLimitBytes = 134217728L
        excessBytes = 294912L
    }
    terminalEvidence = @($expectedTerminalHashes.Keys | ForEach-Object {
        $path = Join-Path $pilotRoot $_
        [ordered]@{ name = $_; rawBytes = [long](Get-Item -LiteralPath $path).Length; sha256 = $expectedTerminalHashes[$_] }
    })
    failedBlockCheckpointSha256 = Get-LowerSha256 -LiteralPath $failedBlockCheckpointPath
    failedBlockFailureSha256 = Get-LowerSha256 -LiteralPath $failedBlockFailurePath
    failedBlockExceptionType = [string]$failedBlockFailure.exceptionType
    verifiedFileCountFromPartialManifest = $verifiedCount
    verifiedRawBytesFromPartialManifest = $verifiedBytes
    rootFileCountIncludingPartialManifest = $actualFiles.Count
    rootRawBytesIncludingPartialManifest = $actualRootBytes
    unexpectedFileCount = 0
    independentFullHashAuditPassed = $true
    reservedGate13RFormalRootAbsent = $true
}

Write-AtomicUtf8NoBomJson -LiteralPath $OutputPath -Value $output
Write-Host "Gate12R pilot attempt 1 preservation manifest passed: $OutputPath" -ForegroundColor Green

