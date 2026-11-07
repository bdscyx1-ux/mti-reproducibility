[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$ProjectPath,
    [Parameter(Mandatory = $true)][string]$SummaryPath,
    [Parameter(Mandatory = $true)][string]$AuditPath
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

if ([string]::IsNullOrWhiteSpace($ProjectPath) -or -not [IO.Path]::IsPathRooted($ProjectPath)) {
    throw 'An explicit absolute ProjectPath is required.'
}
$ProjectPath = [IO.Path]::GetFullPath($ProjectPath).TrimEnd('\', '/')
$SummaryPath = [IO.Path]::GetFullPath($SummaryPath)
$AuditPath = [IO.Path]::GetFullPath($AuditPath)
$formalRoot = [IO.Path]::GetFullPath((Join-Path $ProjectPath 'Research\FormalRuns\Gate13R_Serial_10pct\v1')).TrimEnd('\', '/')

function Get-LowerSha256([string]$Path) {
    return (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToLowerInvariant()
}

function Read-Json([string]$Path) {
    return [IO.File]::ReadAllText($Path, [Text.Encoding]::UTF8) | ConvertFrom-Json
}

function Write-AtomicJson([string]$Path, $Value) {
    $directory = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $directory -PathType Container)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }
    $temporary = $Path + '.tmp-' + [Guid]::NewGuid().ToString('N')
    $json = $Value | ConvertTo-Json -Depth 100
    [IO.File]::WriteAllText($temporary, $json + [Environment]::NewLine, (New-Object Text.UTF8Encoding($false)))
    Move-Item -LiteralPath $temporary -Destination $Path -Force
}

function Get-ProjectPath([string]$RelativePath) {
    return [IO.Path]::GetFullPath((Join-Path $ProjectPath $RelativePath.Replace('/', '\')))
}

function Get-ProjectRelative([string]$FullPath) {
    $resolved = [IO.Path]::GetFullPath($FullPath)
    $prefix = $ProjectPath + [IO.Path]::DirectorySeparatorChar
    if (-not $resolved.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Path is outside ProjectPath: $resolved"
    }
    return $resolved.Substring($prefix.Length).Replace('\', '/')
}

$errors = New-Object Collections.Generic.List[string]
$assertions = 0
function Assert-Condition([bool]$Condition, [string]$Id) {
    $script:assertions++
    if (-not $Condition) { $script:errors.Add($Id) }
}

Assert-Condition (-not $SummaryPath.StartsWith($formalRoot, [StringComparison]::OrdinalIgnoreCase)) 'summary-inside-formal-root'
Assert-Condition (-not $AuditPath.StartsWith($formalRoot, [StringComparison]::OrdinalIgnoreCase)) 'audit-inside-formal-root'
Assert-Condition (-not (Test-Path -LiteralPath $formalRoot)) 'reserved-formal-root-exists'
Assert-Condition (@(Get-Process -Name Unity -ErrorAction SilentlyContinue).Count -eq 0) 'unity-process-running'

$newFiles = [ordered]@{
    selection = 'Research/Gate13R_Serial_10pct_Selection.v1.json'
    specification = 'Research/Gate13R_Serial_10pct_Redesign_Specification.v1.md'
    testDesign = 'Research/Gate13R_Serial_10pct_Test_Design.v1.md'
    amendment = 'Research/Gate13R_Serial_10pct_Readiness_Amendment.v1.json'
    formalPlan = 'Research/Gate13R_Serial_10pct_Formal_Plan.v1.json'
}
foreach ($item in $newFiles.GetEnumerator()) {
    Assert-Condition (Test-Path -LiteralPath (Get-ProjectPath $item.Value) -PathType Leaf) ("new-file-missing-" + $item.Key)
}

$selection = Read-Json (Get-ProjectPath $newFiles.selection)
$amendment = Read-Json (Get-ProjectPath $newFiles.amendment)
$formalPlan = Read-Json (Get-ProjectPath $newFiles.formalPlan)
$expectedDirective = [string]::Concat([char[]]@(0x4E0D, 0x518D, 0x5E76, 0x884C, 0xFF0C, 0x76F4, 0x63A5, 0x4E32, 0x884C, 0x5B9E, 0x9A8C))
Assert-Condition ([string]$selection.userDirectiveExact -eq $expectedDirective) 'user-directive-mismatch'
Assert-Condition ([int]$selection.activeTopology.maximumConcurrentUnityEditorProcesses -eq 1) 'selection-concurrency-not-one'
Assert-Condition ([int]$selection.activeTopology.laneCount -eq 1) 'selection-lane-count-not-one'
Assert-Condition ($selection.activeTopology.parallelLaneFallbackAllowed -eq $false) 'selection-parallel-fallback-enabled'
Assert-Condition ($selection.activeTopology.mixedTopologyAllowed -eq $false) 'selection-mixed-topology-enabled'
Assert-Condition ($selection.authorizationBoundary.formalCampaignAuthorized -eq $false) 'selection-formal-authorized'
Assert-Condition ([int]$amendment.activeTopology.maximumConcurrentUnityEditorProcesses -eq 1) 'amendment-concurrency-not-one'
Assert-Condition ($amendment.activeTopology.parallelExecutionAllowed -eq $false) 'amendment-parallel-enabled'
Assert-Condition ($amendment.authorization.formalCampaignAuthorized -eq $false) 'amendment-formal-authorized'
Assert-Condition ([string]$amendment.formalOutput.reservedRelativePath -eq 'Research/FormalRuns/Gate13R_Serial_10pct/v1') 'amendment-formal-root-mismatch'
Assert-Condition ([int]$formalPlan.processSemantics.maximumConcurrentUnityEditorProcesses -eq 1) 'plan-concurrency-not-one'
Assert-Condition ($formalPlan.formalCampaignAuthorized -eq $false) 'plan-formal-authorized'
Assert-Condition ($formalPlan.formalRootCreated -eq $false) 'plan-formal-root-created'
Assert-Condition ($formalPlan.formalTimingExecuted -eq $false) 'plan-formal-timing-executed'

$upstreamExpected = [ordered]@{
    'Research/FormalScenarios/Gate11R_5pct/v1/bundle-manifest.json' = '5baaeec18344a9e99e55da38f3c4875b7e7e9f3bf0add9d5f2d2f1e821b5f7fc'
    'Research/PilotRuns/Gate12R_ProcessReuse_5pct/v4/execution-receipt.json' = 'b0541ccc851d65f9cf9fb277abef6484223c9847c9ea16104cdfa7d36a7fd735'
    'Research/PilotRuns/Gate12R_ProcessReuse_5pct/v4/pilot-execution-manifest.json' = 'fce4c7f9c7fe7df5f424c8a8ae888133942ed49dbede71d4499e502ba812ebd6'
    'Research/PilotRuns/Gate12R_ProcessReuse_5pct/v4/pilot-checkpoint.json' = 'ab2cd3a7d97e2097f4ed3dbc3a90607cb44390a0d2df40ffc83251ac0fb23e0f'
    'Research/PilotRuns/Gate12R_ProcessReuse_5pct/v4/partial-output-manifest.json' = '6323fa26829f4c7c340b8cad38f7611fcaed49ce22caca82908c08ac447bed27'
    'Research/PilotRuns/Gate12R_ProcessReuse_5pct/v4/candidate-n-formal.json' = '5e77d9b69c4c0e45dec204ca1943867453d29dcbdf1ebd24f0809af6d649c387'
    'Research/PilotRuns/Gate12R_ProcessReuse_5pct/v4/budget-storage-projection.json' = 'cca76d3206311119b3b81fd72d162f8425a2657f02d85a906a5fc91a35690e1f'
    'Research/PilotRuns/Gate12R_ProcessReuse_5pct/v4/correlation-diagnostics.json' = 'bc88d762da8e8440347f7ec35bd45f78b3b39d3426d5aa2e3b5313af6fcd82c1'
    'Research/PilotRuns/Gate12R_ProcessReuse_5pct/v4/block-aware-analysis.json' = '486b87776e9b4edc78d293977f6eda2f43b386bd4832838780e34558e731731c'
    'Research/PilotRuns/Gate12R_ProcessReuse_5pct/v4/pilot-manifest.json' = '5b0678518423816212ea27f6cbb0bea18c1d11110ed10aefa1a238c17e0a53b6'
    'Research/Gate12R_Readiness_Checkpoint.v1.json' = '93d1ffac30305ecbc3ff32820aa0eee016c7a2cc6824f41c491aac393cfd291d'
    'Research/Verification/Gate12R_ProcessReuse_5pct/v7/TelemetryProbe/v1.summary.json' = 'eab6848b56f795f2eaf90c45d6e8e08ae0242379868da1aacd75a5d24a7bcd72'
    'Research/Verification/Gate12R_ProcessReuse_5pct/v7/TelemetryProbe/v1/telemetry-probe-result.json' = 'd8b9a29f81cd147b8bfb6a94dde46eef1a8b7bca83248729a8f2b8e27824d31e'
}
$upstreamActual = New-Object Collections.Generic.List[object]
foreach ($item in $upstreamExpected.GetEnumerator()) {
    $path = Get-ProjectPath $item.Key
    Assert-Condition (Test-Path -LiteralPath $path -PathType Leaf) ("upstream-missing-" + $item.Key)
    if (Test-Path -LiteralPath $path -PathType Leaf) {
        $actual = Get-LowerSha256 $path
        Assert-Condition ($actual -eq $item.Value) ("upstream-hash-mismatch-" + $item.Key)
        $upstreamActual.Add([ordered]@{ relativePath = $item.Key; sha256 = $actual; rawBytes = (Get-Item -LiteralPath $path).Length })
    }
}

$gate11 = Read-Json (Get-ProjectPath 'Research/FormalScenarios/Gate11R_5pct/v1/bundle-manifest.json')
Assert-Condition ([int]$gate11.scenarioCount -eq 53) 'gate11-scenario-count'
Assert-Condition ([int]$gate11.campaignCount -eq 74) 'gate11-campaign-count'
Assert-Condition ([int]$gate11.sceneCount -eq 53) 'gate11-scene-count'
Assert-Condition ([int]$gate11.profileCount -eq 74) 'gate11-profile-count'
Assert-Condition ([int]$gate11.presetCount -eq 212) 'gate11-preset-count'
Assert-Condition ($gate11.visualizationOnly -eq $true) 'gate11-visualization-flag'
Assert-Condition ($gate11.timingEvidenceAllowed -eq $false) 'gate11-timing-evidence-flag'

$pilotRootRelative = 'Research/PilotRuns/Gate12R_ProcessReuse_5pct/v4'
$pilotRoot = Get-ProjectPath $pilotRootRelative
$execution = Read-Json (Join-Path $pilotRoot 'pilot-execution-manifest.json')
$partial = Read-Json (Join-Path $pilotRoot 'partial-output-manifest.json')
$checkpoint = Read-Json (Join-Path $pilotRoot 'pilot-checkpoint.json')
Assert-Condition ([string]$checkpoint.status -eq 'GATE12R-COMPLETE-GATE13R-NOT-AUTHORIZED') 'gate12-checkpoint-status'
Assert-Condition ([int]$execution.telemetryProbeProcessCount -eq 1) 'gate12-telemetry-process-count'
Assert-Condition ([int]$execution.warmupBlockProcessCount -eq 8) 'gate12-warmup-count'
Assert-Condition ([int]$execution.coldControlProcessCount -eq 36) 'gate12-cold-count'
Assert-Condition ([int]$execution.measuredBlockProcessCount -eq 384) 'gate12-measured-block-count'
Assert-Condition ([int]$execution.measuredSampleCount -eq 1152) 'gate12-measured-sample-count'
Assert-Condition ([int]$execution.totalUnityProcessCount -eq 429) 'gate12-total-process-count'
Assert-Condition ([int]$execution.totalSampleCount -eq 1212) 'gate12-total-sample-count'
Assert-Condition ([int]$execution.automaticRetryCount -eq 0) 'gate12-retry-count'
Assert-Condition ([int]$execution.automaticResumeCount -eq 0) 'gate12-resume-count'
Assert-Condition ($execution.completed -eq $true) 'gate12-execution-not-complete'
Assert-Condition ([int]$partial.fileCount -eq 8713) 'gate12-partial-file-count'
Assert-Condition ([long]$partial.rawBytes -eq 551128921) 'gate12-partial-byte-count'

$partialMap = @{}
foreach ($file in $partial.files) { $partialMap[[string]$file.relativePath] = [string]$file.sha256 }
$rows = New-Object Collections.Generic.List[object]
$identitySet = New-Object 'Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
$pidSet = New-Object 'Collections.Generic.HashSet[int]'
$summaryHashMismatches = 0
$logHashMismatches = 0
$manifestMismatches = 0
$passedSummaries = 0
$exitZeroSummaries = 0
$serialAssignments = 0
$accessTokenWarnings = 0
$noValidLicenseErrors = 0
$inactiveHeadlessErrors = 0
$duplicateProcessIdentities = 0

foreach ($entry in $execution.entries) {
    $summaryRelative = ([string]$entry.wrapperSummaryRelativePath).Replace('\', '/')
    $summaryPathEntry = Get-ProjectPath $summaryRelative
    $summary = Read-Json $summaryPathEntry
    $summarySha = Get-LowerSha256 $summaryPathEntry
    if ($summarySha -ne [string]$entry.wrapperSummarySha256) { $summaryHashMismatches++ }
    if ($summary.passed -eq $true) { $passedSummaries++ }
    if ([int]$summary.exitCode -eq 0) { $exitZeroSummaries++ }
    [void]$pidSet.Add([int]$summary.unityProcessId)

    if ([string]$entry.role -eq 'excluded-cold-structural-control') {
        $logRelative = $summaryRelative -replace '\.summary\.json$', '.Unity.log'
        $manifestRelative = ([string]$entry.outputRelativePath).Replace('\', '/').TrimEnd('/') + '/manifest.json'
        $expectedManifestSha = [string]$entry.manifestSha256
        $identityStart = ([DateTimeOffset]$summary.startedAt).UtcDateTime
        $logSha = Get-LowerSha256 (Get-ProjectPath $logRelative)
        if ($logSha -ne [string]$summary.unityLogSha256) { $logHashMismatches++ }
    }
    else {
        $logRelative = Get-ProjectRelative ([string]$summary.unityLogPath)
        $manifestRelative = ([string]$entry.outputRelativePath).Replace('\', '/').TrimEnd('/') + '/block-manifest.json'
        $expectedManifestSha = [string]$entry.blockManifestSha256
        $blockManifest = Read-Json (Get-ProjectPath $manifestRelative)
        if ($blockManifest.oneBlockPerUnityProcess -ne $true -or $blockManifest.allSamplesShareProcessId -ne $true -or $blockManifest.orderMatchesBlockPlan -ne $true) { $manifestMismatches++ }
        if ([int]$blockManifest.processId -ne [int]$summary.unityProcessId) { $manifestMismatches++ }
        $identityStart = ([DateTimeOffset]$blockManifest.processStartTimeUtc).UtcDateTime
        $logSha = Get-LowerSha256 (Get-ProjectPath $logRelative)
    }

    $manifestSha = Get-LowerSha256 (Get-ProjectPath $manifestRelative)
    if ($manifestSha -ne $expectedManifestSha) { $manifestMismatches++ }
    if (-not $partialMap.ContainsKey($logRelative) -or $partialMap[$logRelative] -ne $logSha) { $logHashMismatches++ }

    $logText = Get-Content -Raw -LiteralPath (Get-ProjectPath $logRelative)
    if ($logText.Contains('Serial number assigned to:')) { $serialAssignments++ }
    if ($logText.Contains('Access token is unavailable; failed to update')) { $accessTokenWarnings++ }
    if ($logText.Contains('No valid Unity Editor license found')) { $noValidLicenseErrors++ }
    if ($logText.Contains('License is not active (com.unity.editor.headless)')) { $inactiveHeadlessErrors++ }

    $identity = '{0}|{1:o}' -f [int]$summary.unityProcessId, $identityStart
    if (-not $identitySet.Add($identity)) { $duplicateProcessIdentities++ }
    $rows.Add([pscustomobject][ordered]@{
        ordinal = [int]$entry.ordinal
        role = [string]$entry.role
        processId = [int]$summary.unityProcessId
        startedAtUtc = ([DateTimeOffset]$summary.startedAt).UtcDateTime
        completedAtUtc = ([DateTimeOffset]$summary.completedAt).UtcDateTime
    })
}

$sortedRows = @($rows | Sort-Object startedAtUtc, ordinal)
$overlapCount = 0
$minimumGapSeconds = [double]::PositiveInfinity
$latestEnd = [DateTime]::MinValue
foreach ($row in $sortedRows) {
    if ($row.startedAtUtc -lt $latestEnd) { $overlapCount++ }
    if ($latestEnd -ne [DateTime]::MinValue) {
        $gap = ($row.startedAtUtc - $latestEnd).TotalSeconds
        if ($gap -lt $minimumGapSeconds) { $minimumGapSeconds = $gap }
    }
    if ($row.completedAtUtc -gt $latestEnd) { $latestEnd = $row.completedAtUtc }
}

Assert-Condition (@($execution.entries).Count -eq 428) 'gate12-entry-count'
Assert-Condition ($summaryHashMismatches -eq 0) 'wrapper-summary-hash-mismatch'
Assert-Condition ($logHashMismatches -eq 0) 'unity-log-hash-mismatch'
Assert-Condition ($manifestMismatches -eq 0) 'manifest-semantic-or-hash-mismatch'
Assert-Condition ($passedSummaries -eq 428) 'wrapper-summary-pass-count'
Assert-Condition ($exitZeroSummaries -eq 428) 'wrapper-summary-exit-count'
Assert-Condition ($serialAssignments -eq 428) 'serial-assignment-count'
Assert-Condition ($noValidLicenseErrors -eq 0) 'no-valid-license-error-count'
Assert-Condition ($inactiveHeadlessErrors -eq 0) 'inactive-headless-error-count'
Assert-Condition ($overlapCount -eq 0) 'serial-process-overlap-count'
Assert-Condition ($minimumGapSeconds -gt 0) 'serial-process-gap-nonpositive'
Assert-Condition ($identitySet.Count -eq 428) 'process-identity-count'
Assert-Condition ($duplicateProcessIdentities -eq 0) 'duplicate-process-identity-count'

$telemetryResultPath = Get-ProjectPath 'Research/Verification/Gate12R_ProcessReuse_5pct/v7/TelemetryProbe/v1/telemetry-probe-result.json'
$telemetrySummaryPath = Get-ProjectPath 'Research/Verification/Gate12R_ProcessReuse_5pct/v7/TelemetryProbe/v1.summary.json'
$telemetryLogPath = Get-ProjectPath 'Research/Verification/Gate12R_ProcessReuse_5pct/v7/TelemetryProbe/v1.Unity.log'
$telemetryResult = Read-Json $telemetryResultPath
$telemetrySummary = Read-Json $telemetrySummaryPath
$telemetryLog = Get-Content -Raw -LiteralPath $telemetryLogPath
$telemetryStartDifference = [math]::Abs((([DateTimeOffset]$telemetryResult.nativeBefore.processStartTimeUtc) - ([DateTimeOffset]$telemetryResult.externalQuery.creationDateUtc)).TotalSeconds)
Assert-Condition ($telemetryResult.passed -eq $true) 'telemetry-result-failed'
Assert-Condition ([int]$telemetrySummary.exitCode -eq 0) 'telemetry-exit-nonzero'
Assert-Condition ([long]$telemetryResult.nativeBefore.workingSetBytes -gt 0) 'telemetry-before-working-set-nonpositive'
Assert-Condition ([long]$telemetryResult.nativeBefore.privateMemoryBytes -gt 0) 'telemetry-before-private-nonpositive'
Assert-Condition ([long]$telemetryResult.nativeAfter.workingSetBytes -gt 0) 'telemetry-after-working-set-nonpositive'
Assert-Condition ([long]$telemetryResult.nativeAfter.privateMemoryBytes -gt 0) 'telemetry-after-private-nonpositive'
Assert-Condition ([int]$telemetryResult.nativeBefore.processId -eq [int]$telemetryResult.externalQuery.processId) 'telemetry-pid-mismatch'
Assert-Condition ($telemetryStartDifference -lt 0.001) 'telemetry-start-time-mismatch'
Assert-Condition ($telemetryResult.workingSetPassed -eq $true) 'telemetry-working-set-cross-check'
Assert-Condition ($telemetryResult.privateMemoryPassed -eq $true) 'telemetry-private-cross-check'
Assert-Condition ($telemetryLog.Contains('Serial number assigned to:')) 'telemetry-serial-assignment-missing'
Assert-Condition (-not $telemetryLog.Contains('No valid Unity Editor license found')) 'telemetry-no-valid-license-error'
Assert-Condition (([DateTimeOffset]$telemetrySummary.completedAtUtc).UtcDateTime -le $sortedRows[0].startedAtUtc) 'telemetry-overlaps-pilot'

$candidate = Read-Json (Join-Path $pilotRoot 'candidate-n-formal.json')
$budget = Read-Json (Join-Path $pilotRoot 'budget-storage-projection.json')
$campaignCounts = @{
    'four-algorithm-shared-goal-v1' = 32
    'per-agent-heterogeneous-goal-v1' = 21
    'grouped-field-heterogeneous-goal-v1' = 21
}
$algorithmCounts = @{
    'four-algorithm-shared-goal-v1' = 4
    'per-agent-heterogeneous-goal-v1' = 2
    'grouped-field-heterogeneous-goal-v1' = 2
}
$expectedN = @{
    'four-algorithm-shared-goal-v1' = 144
    'per-agent-heterogeneous-goal-v1' = 204
    'grouped-field-heterogeneous-goal-v1' = 108
}
$calculatedCohorts = New-Object Collections.Generic.List[object]
$totalBlocks = 0
$totalSamples = 0
$totalP50Seconds = 0.0
$totalP95Seconds = 0.0
$totalRawBytes = [long]0
foreach ($cohort in $candidate.cohorts) {
    $id = [string]$cohort.comparisonCohortId
    $rawN = [int][math]::Ceiling([math]::Pow((1.96 * [double]$cohort.sigmaUpper / [math]::Log(1.1)), 2))
    $nFormal = [int][math]::Max(32, [math]::Ceiling([double]$rawN / 4.0) * 4)
    $budgetRow = @($budget.rows | Where-Object { [string]$_.comparisonCohortId -eq $id })[0]
    $blocks = [int]$campaignCounts[$id] * $nFormal
    $samples = $blocks * [int]$algorithmCounts[$id]
    $p50Seconds = $blocks * [double]$budgetRow.p50BlockWallSeconds
    $p95Seconds = $blocks * [double]$budgetRow.p95BlockWallSeconds
    $rawBytes = [long][math]::Ceiling($blocks * [double]$budgetRow.p95BlockRawBytes * 1.5)
    Assert-Condition ($nFormal -eq [int]$expectedN[$id]) ("n-formal-mismatch-" + $id)
    $totalBlocks += $blocks
    $totalSamples += $samples
    $totalP50Seconds += $p50Seconds
    $totalP95Seconds += $p95Seconds
    $totalRawBytes += $rawBytes
    $calculatedCohorts.Add([ordered]@{
        comparisonCohortId = $id
        sigmaUpper = [double]$cohort.sigmaUpper
        rawN = $rawN
        candidateNFormal = $nFormal
        campaignCount = [int]$campaignCounts[$id]
        samplesPerBlock = [int]$algorithmCounts[$id]
        blockProcessCount = $blocks
        sampleCount = $samples
        projectedP50Seconds = $p50Seconds
        projectedP95Seconds = $p95Seconds
        projectedRawBytesWithSafety = $rawBytes
    })
}
$reserveBytes = [long](40GB)
$minimumLaunchFreeBytes = $totalRawBytes + $reserveBytes
$p50Hours = $totalP50Seconds / 3600.0
$p95Hours = $totalP95Seconds / 3600.0
Assert-Condition ($totalBlocks -eq 11160) 'total-formal-block-count'
Assert-Condition ($totalSamples -eq 31536) 'total-formal-sample-count'
Assert-Condition ([math]::Abs($p50Hours - 64.830802096) -lt 0.000000001) 'serial-p50-projection'
Assert-Condition ([math]::Abs($p95Hours - 83.904223147) -lt 0.000000001) 'serial-p95-projection'
Assert-Condition ($totalRawBytes -eq 43885575792) 'raw-byte-projection'
Assert-Condition ($minimumLaunchFreeBytes -eq 86835248752) 'launch-storage-requirement'
Assert-Condition ([int]$formalPlan.totals.blockProcessCount -eq $totalBlocks) 'plan-total-block-count'
Assert-Condition ([int]$formalPlan.totals.sampleCount -eq $totalSamples) 'plan-total-sample-count'
Assert-Condition ([long]$formalPlan.totals.minimumLaunchFreeBytes -eq $minimumLaunchFreeBytes) 'plan-storage-requirement'
Assert-Condition ([int]$amendment.candidateNFormal.'four-algorithm-shared-goal-v1' -eq 144) 'amendment-shared-n'
Assert-Condition ([int]$amendment.candidateNFormal.'per-agent-heterogeneous-goal-v1' -eq 204) 'amendment-per-agent-n'
Assert-Condition ([int]$amendment.candidateNFormal.'grouped-field-heterogeneous-goal-v1' -eq 108) 'amendment-grouped-n'
Assert-Condition ($amendment.precision.hardCap -eq $null) 'amendment-hard-cap-present'
Assert-Condition ($amendment.precision.earlyStoppingAllowed -eq $false) 'amendment-early-stopping-enabled'
Assert-Condition ($amendment.runtimeProjection.previous36HourGateFeasible -eq $false) 'serial-marked-36h-feasible'
Assert-Condition ($amendment.runtimeProjection.replacementHardWallClockLimit -eq $null) 'invented-wall-clock-limit'

$driveRoot = [IO.Path]::GetPathRoot($formalRoot)
$driveInfo = New-Object IO.DriveInfo($driveRoot)
$availableFreeBytes = [long]$driveInfo.AvailableFreeSpace

$audit = [ordered]@{
    schemaVersion = 1
    auditKind = 'gate13r-strict-serial-10pct-gate12r-v4-evidence-audit-v1'
    auditedAtUtc = [DateTime]::UtcNow.ToString('o')
    userDirective = [string]$selection.userDirectiveExact
    result = if ($errors.Count -eq 0) { 'passed' } else { 'failed' }
    exactTopologyMatch = $errors.Count -eq 0
    newArtifactHashes = @($newFiles.GetEnumerator() | ForEach-Object {
        [ordered]@{ role = $_.Key; relativePath = $_.Value; sha256 = Get-LowerSha256 (Get-ProjectPath $_.Value); rawBytes = (Get-Item -LiteralPath (Get-ProjectPath $_.Value)).Length }
    })
    frozenUpstream = $upstreamActual.ToArray()
    gate12SerialEvidence = [ordered]@{
        manifestEntryCount = @($execution.entries).Count
        wrapperSummaryPassCount = $passedSummaries
        exitZeroCount = $exitZeroSummaries
        wrapperSummaryHashMismatchCount = $summaryHashMismatches
        unityLogHashMismatchCount = $logHashMismatches
        manifestOrSemanticMismatchCount = $manifestMismatches
        serialAssignmentCount = $serialAssignments
        accessTokenWarningCount = $accessTokenWarnings
        noValidLicenseErrorCount = $noValidLicenseErrors
        inactiveHeadlessErrorCount = $inactiveHeadlessErrors
        strictSerialOverlapCount = $overlapCount
        minimumInterprocessGapSeconds = $minimumGapSeconds
        uniquePidCount = $pidSet.Count
        uniqueProcessIdentityCount = $identitySet.Count
        duplicateProcessIdentityCount = $duplicateProcessIdentities
        firstProcessStartUtc = $sortedRows[0].startedAtUtc.ToString('o')
        lastProcessEndUtc = $sortedRows[-1].completedAtUtc.ToString('o')
        telemetryProcessCount = [int]$execution.telemetryProbeProcessCount
        warmupBlockProcessCount = [int]$execution.warmupBlockProcessCount
        coldControlProcessCount = [int]$execution.coldControlProcessCount
        measuredBlockProcessCount = [int]$execution.measuredBlockProcessCount
        measuredSampleCount = [int]$execution.measuredSampleCount
        totalUnityProcessCount = [int]$execution.totalUnityProcessCount
        totalSampleCount = [int]$execution.totalSampleCount
        automaticRetryCount = [int]$execution.automaticRetryCount
        automaticResumeCount = [int]$execution.automaticResumeCount
    }
    telemetry = [ordered]@{
        resultSha256 = Get-LowerSha256 $telemetryResultPath
        passed = [bool]$telemetryResult.passed
        positiveWorkingSetAndPrivateMemory = ([long]$telemetryResult.nativeBefore.workingSetBytes -gt 0 -and [long]$telemetryResult.nativeBefore.privateMemoryBytes -gt 0 -and [long]$telemetryResult.nativeAfter.workingSetBytes -gt 0 -and [long]$telemetryResult.nativeAfter.privateMemoryBytes -gt 0)
        pidAndProcessStartCrossCheckPassed = ([int]$telemetryResult.nativeBefore.processId -eq [int]$telemetryResult.externalQuery.processId -and $telemetryStartDifference -lt 0.001)
        serialAssigned = $telemetryLog.Contains('Serial number assigned to:')
        completedBeforePilot = (([DateTimeOffset]$telemetrySummary.completedAtUtc).UtcDateTime -le $sortedRows[0].startedAtUtc)
    }
    precision = [ordered]@{
        targetRelativeHalfWidth = 0.1
        confidenceLevel = 0.95
        hardCap = $null
        cohorts = $calculatedCohorts.ToArray()
        totalBlockProcesses = $totalBlocks
        totalSamples = $totalSamples
    }
    resourceProjection = [ordered]@{
        serialP50Seconds = $totalP50Seconds
        serialP95Seconds = $totalP95Seconds
        serialP50Hours = $p50Hours
        serialP95Hours = $p95Hours
        projectedRawBytesWithSafety = $totalRawBytes
        reserveBytes = $reserveBytes
        minimumLaunchFreeBytes = $minimumLaunchFreeBytes
        observedAvailableFreeBytes = $availableFreeBytes
        observedStorageFeasible = $availableFreeBytes -ge $minimumLaunchFreeBytes
        observationCanAuthorizeLaunch = $false
    }
    authorizationBoundary = [ordered]@{
        formalRoot = Get-ProjectRelative $formalRoot
        formalRootExists = Test-Path -LiteralPath $formalRoot
        formalCampaignAuthorized = $false
        formalExecutionReceiptCreated = $false
        formalTimingSamplesCreated = $false
    }
    assertionCount = $assertions
    errors = $errors.ToArray()
}
Write-AtomicJson -Path $AuditPath -Value $audit

$summary = [ordered]@{
    schemaVersion = 1
    summaryKind = 'gate13r-strict-serial-10pct-readiness-validation-summary-v1'
    savedAtUtc = [DateTime]::UtcNow.ToString('o')
    assertionCount = $assertions
    failureCount = $errors.Count
    errors = $errors.ToArray()
    evidenceAuditRelativePath = Get-ProjectRelative $AuditPath
    evidenceAuditSha256 = Get-LowerSha256 $AuditPath
    maximumConcurrentUnityEditorProcesses = 1
    scheduleTopology = 'strict-serial-one-fresh-unity-editor-per-complete-williams-block'
    reusedSameTopologyPilot = $true
    newUnityProcessCount = 0
    formalRootExists = Test-Path -LiteralPath $formalRoot
    formalExecutionReceiptCreated = $false
    formalTimingSamplesCreated = $false
    status = if ($errors.Count -eq 0) { 'READINESS-VALIDATION-PASSED-FORMAL-NOT-AUTHORIZED' } else { 'READINESS-VALIDATION-FAILED' }
    passed = $errors.Count -eq 0
}
Write-AtomicJson -Path $SummaryPath -Value $summary

if ($errors.Count -gt 0) {
    Write-Error ('Gate13R serial readiness validation failed: ' + ($errors -join '; '))
    exit 1
}

Write-Host "Gate13R serial readiness validation passed: $assertions assertions; no Unity or formal output created." -ForegroundColor Green
exit 0
