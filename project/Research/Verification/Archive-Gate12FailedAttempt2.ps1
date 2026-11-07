[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$projectRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
$archiveBase = (Resolve-Path -LiteralPath (Join-Path $projectRoot 'Research\PilotRuns\Gate12')).Path
$sourcePath = (Resolve-Path -LiteralPath (Join-Path $archiveBase 'v1')).Path
$destinationPath = [System.IO.Path]::GetFullPath((Join-Path $archiveBase 'v1-failed-warmup-attempt2'))
$receiptPath = [System.IO.Path]::GetFullPath((Join-Path $archiveBase 'Gate12_Attempt2_MoveReceipt.json'))
$expectedFileCount = 103
$expectedByteCount = [int64]14187382
$expectedAggregateSha256 = 'b52ee8f13c9b96edd2f0ab83f4969161ef5b257d1543588ec9608877086dc500'
$expectedCampaignManifestSha256 = 'de900f8d91b544ff290c1329d55fb893c243efe620925f655ee0714f8f8101d8'
$expectedWrapperSummarySha256 = 'a04bd2047b1c56f273acd40783931efabf9a65a09da09b1ff0cd069158588da0'

function Get-LowerSha256([string]$Path) {
    return (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToLowerInvariant()
}

function Get-AttemptIdentity([string]$Root) {
    $files = @(Get-ChildItem -LiteralPath $Root -File -Recurse | Sort-Object { $_.FullName.Substring($Root.Length + 1).Replace('\', '/') })
    $builder = New-Object System.Text.StringBuilder
    foreach ($file in $files) {
        $relativePath = $file.FullName.Substring($Root.Length + 1).Replace('\', '/')
        [void]$builder.Append($relativePath).Append("`n").Append($file.Length).Append("`n").Append((Get-LowerSha256 $file.FullName)).Append("`n")
    }
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $aggregate = ([System.BitConverter]::ToString($sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($builder.ToString())))).Replace('-', '').ToLowerInvariant()
    }
    finally {
        $sha.Dispose()
    }
    $byteCount = if ($files.Count -eq 0) { [int64]0 } else { [int64](($files | Measure-Object -Property Length -Sum).Sum) }
    return [pscustomobject]@{
        FileCount = $files.Count
        ByteCount = $byteCount
        AggregateSha256 = $aggregate
    }
}

function Assert-ImmediateChildPath([string]$Candidate, [string]$Parent, [string]$Label) {
    $candidateParent = [System.IO.Directory]::GetParent($Candidate)
    if ($null -eq $candidateParent -or -not [string]::Equals($candidateParent.FullName, $Parent, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "$Label is not an immediate child of the Gate 12 archive base: $Candidate"
    }
}

Assert-ImmediateChildPath -Candidate $sourcePath -Parent $archiveBase -Label 'Source'
Assert-ImmediateChildPath -Candidate $destinationPath -Parent $archiveBase -Label 'Destination'
if (Test-Path -LiteralPath $destinationPath) { throw "Archive destination already exists: $destinationPath" }
if (Test-Path -LiteralPath $receiptPath) { throw "Move receipt already exists: $receiptPath" }

$identityBefore = Get-AttemptIdentity -Root $sourcePath
if ($identityBefore.FileCount -ne $expectedFileCount -or $identityBefore.ByteCount -ne $expectedByteCount -or $identityBefore.AggregateSha256 -ne $expectedAggregateSha256) {
    throw "Attempt identity mismatch before move: files=$($identityBefore.FileCount), bytes=$($identityBefore.ByteCount), aggregate=$($identityBefore.AggregateSha256)"
}

$checkpointPath = Join-Path $sourcePath 'pilot-checkpoint.json'
$failurePath = Join-Path $sourcePath 'pilot-failure.json'
$campaignRoot = Join-Path $sourcePath 'warmup\g12p-warmup-r01-shared'
$campaignManifestPath = Join-Path $campaignRoot 'campaign-manifest.json'
$wrapperSummaryPath = $campaignRoot + '.summary.json'
foreach ($requiredPath in @($checkpointPath, $failurePath, $campaignManifestPath, $wrapperSummaryPath)) {
    if (-not (Test-Path -LiteralPath $requiredPath -PathType Leaf)) { throw "Required failed-attempt evidence is missing: $requiredPath" }
}
if ((Get-LowerSha256 $campaignManifestPath) -ne $expectedCampaignManifestSha256) { throw 'Warm-up campaign manifest hash mismatch.' }
if ((Get-LowerSha256 $wrapperSummaryPath) -ne $expectedWrapperSummarySha256) { throw 'Warm-up wrapper summary hash mismatch.' }

$checkpoint = [System.IO.File]::ReadAllText($checkpointPath, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
$campaign = [System.IO.File]::ReadAllText($campaignManifestPath, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
$wrapper = [System.IO.File]::ReadAllText($wrapperSummaryPath, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
if ($checkpoint.status -ne 'failed-no-auto-retry' -or [int]$checkpoint.completedMeasuredCampaignCount -ne 0 -or [int]$checkpoint.completedMeasuredUnityProcessCount -ne 0) {
    throw 'Failed-attempt checkpoint state is not the expected zero-measured state.'
}
if (Test-Path -LiteralPath (Join-Path $sourcePath 'measured')) { throw 'A measured directory unexpectedly exists in the failed attempt.' }
if ($wrapper.passed -ne $true -or $campaign.completed -ne $true -or $campaign.formalCampaign -ne $false -or [int]$campaign.sampleCount -ne 16 -or [int]$campaign.blockCount -ne 4 -or $campaign.positionBalanced -ne $true -or $campaign.orderedPredecessorBalanced -ne $true -or @($campaign.schedule).Count -ne 16) {
    throw 'Warm-up campaign evidence does not match the expected successful, balanced, non-formal 16-process state.'
}

$runErrors = New-Object System.Collections.Generic.List[string]
foreach ($entry in @($campaign.schedule)) {
    $runRoot = Join-Path $campaignRoot ([string]$entry.directory).Replace('/', '\')
    $runSummaryPath = $runRoot + '.summary.json'
    $runManifestPath = Join-Path $runRoot 'manifest.json'
    $workloadResultPath = Join-Path $runRoot 'workload-result.json'
    $operationsPath = Join-Path $runRoot 'operations.jsonl'
    foreach ($path in @($runSummaryPath, $runManifestPath, $workloadResultPath, $operationsPath)) {
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { $runErrors.Add("Missing run artifact: $path") }
    }
    if (Test-Path -LiteralPath $runSummaryPath) {
        $runSummary = [System.IO.File]::ReadAllText($runSummaryPath, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
        if ($runSummary.passed -ne $true -or [int]$runSummary.exitCode -ne 0) { $runErrors.Add("Run summary failed: $($entry.runId)") }
    }
    if (Test-Path -LiteralPath $runManifestPath) {
        if ((Get-LowerSha256 $runManifestPath) -ne [string]$entry.manifestSha256) { $runErrors.Add("Run manifest hash mismatch: $($entry.runId)") }
    }
    if (Test-Path -LiteralPath $workloadResultPath) {
        if ((Get-LowerSha256 $workloadResultPath) -ne [string]$entry.workloadResultSha256) { $runErrors.Add("Workload-result hash mismatch: $($entry.runId)") }
    }
    if (Test-Path -LiteralPath $operationsPath) {
        if ((Get-LowerSha256 $operationsPath) -ne [string]$entry.operationsJsonlSha256) { $runErrors.Add("Operations hash mismatch: $($entry.runId)") }
    }
}
if ($runErrors.Count -ne 0) { throw ($runErrors -join [Environment]::NewLine) }

$unityProcesses = @(Get-Process -Name Unity -ErrorAction SilentlyContinue)
$unityLockPath = Join-Path $projectRoot 'Temp\UnityLockfile'
if ($unityProcesses.Count -ne 0) { throw "Unity is running ($($unityProcesses.Count) process(es)); refusing to move the attempt directory." }
if (Test-Path -LiteralPath $unityLockPath) { throw "Unity lockfile exists; refusing to move the attempt directory: $unityLockPath" }
$gate13Candidates = @(
    (Join-Path $projectRoot 'Research\FormalRuns\Gate13'),
    (Join-Path $projectRoot 'Research\CampaignRuns\Gate13'),
    (Join-Path $projectRoot 'Research\PilotRuns\Gate13')
)
if (@($gate13Candidates | Where-Object { Test-Path -LiteralPath $_ }).Count -ne 0) { throw 'A Gate 13 output root exists; refusing to archive for retry.' }

Move-Item -LiteralPath $sourcePath -Destination $destinationPath
if (Test-Path -LiteralPath $sourcePath) { throw 'Source still exists after the archive move.' }

$identityAfter = Get-AttemptIdentity -Root $destinationPath
if ($identityAfter.FileCount -ne $identityBefore.FileCount -or $identityAfter.ByteCount -ne $identityBefore.ByteCount -or $identityAfter.AggregateSha256 -ne $identityBefore.AggregateSha256) {
    throw 'Attempt identity changed during the archive move.'
}

$authorizationText = (-join @(
    [char]0x6388, [char]0x6743, [char]0x518d, [char]0x6b21,
    [char]0x91cd, [char]0x8bd5, [char]0x20,
    [char]0x47, [char]0x61, [char]0x74, [char]0x65,
    [char]0x20, [char]0x31, [char]0x32
))
$receipt = [ordered]@{
    schemaVersion = 1
    receiptId = 'gate12-attempt2-warmup-archive-v1'
    movedAt = (Get-Date).ToString('o')
    authorization = [ordered]@{
        source = 'direct-user-message'
        text = $authorizationText
        checkpoint = 'Research/Gate12_Retry_Warmup_Failure_Checkpoint.md'
        scope = 'Verify and archive the intact second attempt, rerun 63 assertions and validation-only preflight, then run one frozen non-formal Gate 12 pilot and stop before Gate 13.'
    }
    sourcePath = $sourcePath
    destinationPath = $destinationPath
    operation = 'Move-Item -LiteralPath within Research/PilotRuns/Gate12'
    failedAttemptClassification = 'successful-warmup-outer-exit-code-false-negative'
    completedWarmupProcessCount = 16
    completedMeasuredCampaignCount = 0
    completedMeasuredProcessCount = 0
    formalCampaign = $false
    gate13StartedAtMove = $false
    unityProcessCountAtMove = 0
    unityLockfilePresentAtMove = $false
    identityBefore = [ordered]@{
        fileCount = $identityBefore.FileCount
        byteCount = $identityBefore.ByteCount
        aggregateSha256 = $identityBefore.AggregateSha256
    }
    identityAfter = [ordered]@{
        fileCount = $identityAfter.FileCount
        byteCount = $identityAfter.ByteCount
        aggregateSha256 = $identityAfter.AggregateSha256
    }
    warmup = [ordered]@{
        campaignId = [string]$campaign.campaignId
        sampleCount = [int]$campaign.sampleCount
        scheduleEntryCount = @($campaign.schedule).Count
        wrapperPassed = [bool]$wrapper.passed
        completed = [bool]$campaign.completed
        positionBalanced = [bool]$campaign.positionBalanced
        orderedPredecessorBalanced = [bool]$campaign.orderedPredecessorBalanced
        campaignManifestSha256 = Get-LowerSha256 (Join-Path $destinationPath 'warmup\g12p-warmup-r01-shared\campaign-manifest.json')
        wrapperSummarySha256 = Get-LowerSha256 (Join-Path $destinationPath 'warmup\g12p-warmup-r01-shared.summary.json')
    }
    preservedIntact = $true
}

$receiptJson = $receipt | ConvertTo-Json -Depth 10
[System.IO.File]::WriteAllText($receiptPath, $receiptJson + [Environment]::NewLine, (New-Object System.Text.UTF8Encoding($false, $true)))
$receipt
