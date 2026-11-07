[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$ProjectPath,
    [Parameter(Mandatory = $true)][string]$ConfigPath,
    [Parameter(Mandatory = $true)][string]$ProvenancePath,
    [Parameter(Mandatory = $true)][string]$SchedulePath,
    [Parameter(Mandatory = $true)][string]$ScheduleManifestPath,
    [Parameter(Mandatory = $true)][string]$SummaryPath,
    [switch]$BindingSmokeOnly
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if ([string]::IsNullOrWhiteSpace($ProjectPath) -or -not [IO.Path]::IsPathRooted($ProjectPath)) { throw 'Gate13R serial 10pct schedule validator requires an explicit absolute ProjectPath.' }
$ProjectPath = [IO.Path]::GetFullPath($ProjectPath)
if ($BindingSmokeOnly) { Write-Output "BINDING-SMOKE-PASSED|Test-Gate13RSerial10pctFormalScheduleV1|$ProjectPath"; exit 0 }
Import-Module (Join-Path $ProjectPath 'Research\Gate13RFormalPreparationV1.psm1') -Force

$ConfigPath = [IO.Path]::GetFullPath($ConfigPath)
$ProvenancePath = [IO.Path]::GetFullPath($ProvenancePath)
$SchedulePath = [IO.Path]::GetFullPath($SchedulePath)
$ScheduleManifestPath = [IO.Path]::GetFullPath($ScheduleManifestPath)
$SummaryPath = [IO.Path]::GetFullPath($SummaryPath)
$formalRoot = [IO.Path]::GetFullPath((Join-Path $ProjectPath 'Research\FormalRuns\Gate13R_Serial_10pct\v1')).TrimEnd('\', '/')
if (Test-Path -LiteralPath $formalRoot) { throw 'Gate13R schedule validation refuses to run while the reserved formal root exists.' }
foreach ($path in @($ConfigPath, $ProvenancePath, $SchedulePath, $ScheduleManifestPath)) { if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Required Gate13R artifact missing: $path" } }
if (Test-G13RPathWithin -BasePath $formalRoot -CandidatePath $SummaryPath -AllowBase) { throw 'Validation summary cannot be written into the reserved formal root.' }

$config = Read-G13RJson $ConfigPath
$provenance = Read-G13RJson $ProvenancePath
$manifest = Read-G13RJson $ScheduleManifestPath
$errors = New-Object Collections.Generic.List[string]
$assertions = 0
function Assert-G13RValidation([bool]$Condition, [string]$Message) {
    $script:assertions++
    if (-not $Condition) { $script:errors.Add($Message) }
}

Assert-G13RValidation ([string]$config.configKind -eq 'gate13r-strict-serial-10pct-formal-campaign-config-v1') 'config-kind-invalid'
Assert-G13RValidation ($config.formalCampaignConfigured -eq $true) 'formal-campaign-not-configured'
Assert-G13RValidation ($config.formalExecutionAuthorized -eq $false) 'formal-execution-must-remain-unauthorized'
Assert-G13RValidation ($config.formalRootCreated -eq $false) 'formal-root-created-flag-invalid'
Assert-G13RValidation ([string]$config.executionDesignId -eq 'gate10r-one-fresh-unity-process-per-williams-block-5pct-v1') 'execution-design-invalid'
Assert-G13RValidation ([int]$config.totals.scenarioCount -eq 53) 'scenario-count-invalid'
Assert-G13RValidation ([int]$config.totals.campaignCount -eq 74) 'campaign-count-invalid'
Assert-G13RValidation ([int]$config.totals.eligibleCellCount -eq 212) 'eligible-cell-count-invalid'
Assert-G13RValidation ([int]$config.totals.blockProcessCount -eq 11160) 'block-count-invalid'
Assert-G13RValidation ([int]$config.totals.sampleCount -eq 31536) 'sample-count-invalid'
Assert-G13RValidation ($null -eq $config.precision.hardCap) 'hard-cap-must-be-null'
Assert-G13RValidation ([double]$config.precision.relativeHalfWidth -eq 0.10) 'precision-invalid'
Assert-G13RValidation ([long]$config.storage.minimumLaunchFreeBytes -eq 86835248752) 'storage-threshold-invalid'
Assert-G13RValidation ([long]$config.memory.maximumSampleRetainedManagedGrowthBytes -eq 134217728) 'sample-memory-limit-invalid'
Assert-G13RValidation ([long]$config.memory.twoSampleBlockRetainedManagedGrowthLimitBytes -eq 268435456) 'two-sample-memory-limit-invalid'
Assert-G13RValidation ([long]$config.memory.fourSampleBlockRetainedManagedGrowthLimitBytes -eq 536870912) 'four-sample-memory-limit-invalid'
Assert-G13RValidation ([long]$config.memory.maximumBlockWorkingSetGrowthBytes -eq 536870912) 'working-set-limit-invalid'
Assert-G13RValidation ([long]$config.memory.maximumBlockPrivateMemoryGrowthBytes -eq 536870912) 'private-memory-limit-invalid'
Assert-G13RValidation ([int]$config.processSemantics.maximumConcurrentUnityEditorProcesses -eq 1) 'concurrency-invalid'
Assert-G13RValidation ([int]$config.processSemantics.laneCount -eq 1) 'lane-count-invalid'
Assert-G13RValidation ($config.processSemantics.parallelFallbackAllowed -eq $false) 'parallel-fallback-invalid'
Assert-G13RValidation ($config.processSemantics.mixedTopologyAllowed -eq $false) 'mixed-topology-invalid'
Assert-G13RValidation ($config.licensing.serialAssignmentRequired -eq $true) 'licensing-serial-assignment-invalid'
Assert-G13RValidation ([string]$config.schedule.relativePath -eq 'Research/Gate13R_Serial_10pct_Formal_Williams_Block_Schedule.v1.jsonl') 'schedule-path-invalid'
Assert-G13RValidation ([string]$config.schedule.sha256 -eq (Get-G13RLowerSha256 $SchedulePath)) 'schedule-hash-invalid'
Assert-G13RValidation ([string]$config.schedule.manifestSha256 -eq (Get-G13RLowerSha256 $ScheduleManifestPath)) 'schedule-manifest-hash-invalid'
Assert-G13RValidation ([string]$provenance.formalConfig.sha256 -eq (Get-G13RLowerSha256 $ConfigPath)) 'provenance-config-hash-invalid'
Assert-G13RValidation ([string]$provenance.schedule.sha256 -eq (Get-G13RLowerSha256 $SchedulePath)) 'provenance-schedule-hash-invalid'
Assert-G13RValidation ([string]$manifest.scheduleSha256 -eq (Get-G13RLowerSha256 $SchedulePath)) 'manifest-schedule-hash-invalid'
Assert-G13RValidation ([string]$manifest.manifestKind -eq 'gate13r-serial-10pct-formal-williams-block-schedule-manifest-v1') 'manifest-kind-invalid'
Assert-G13RValidation ([int]$manifest.blockRecordCount -eq 11160) 'manifest-block-count-invalid'
Assert-G13RValidation ([int]$manifest.sampleIdentityCount -eq 31536) 'manifest-sample-count-invalid'

$campaigns = @($config.campaigns)
Assert-G13RValidation ($campaigns.Count -eq 74) 'config-campaign-array-count-invalid'
$blockIds = New-Object 'Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
$runIds = New-Object 'Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
$outputPaths = New-Object 'Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
$campaignBlockCounts = New-Object 'Collections.Generic.Dictionary[string,int]' ([StringComparer]::Ordinal)
$positionCounts = New-Object 'Collections.Generic.Dictionary[string,int]' ([StringComparer]::Ordinal)
$globalBlockOrdinal = 0
$sampleCount = 0

foreach ($line in [IO.File]::ReadLines($SchedulePath, [Text.Encoding]::UTF8)) {
    if ([string]::IsNullOrWhiteSpace($line)) { $errors.Add('blank-schedule-line'); continue }
    $globalBlockOrdinal++
    try { $record = $line | ConvertFrom-Json }
    catch { $errors.Add("invalid-json-line-$globalBlockOrdinal"); continue }
    if ([string]$record.scheduleKind -ne 'gate13r-serial-10pct-formal-williams-block-schedule-record-v1') { $errors.Add("schedule-kind-invalid-$globalBlockOrdinal") }
    if ([int]$record.globalBlockOrdinal -ne $globalBlockOrdinal) { $errors.Add("global-ordinal-mismatch-$globalBlockOrdinal") }
    $campaignOrdinal = [int]$record.campaignOrdinal
    if ($campaignOrdinal -lt 1 -or $campaignOrdinal -gt $campaigns.Count) { $errors.Add("campaign-ordinal-invalid-$globalBlockOrdinal"); continue }
    $campaign = $campaigns[$campaignOrdinal - 1]
    if ([string]$record.campaignId -ne [string]$campaign.campaignId -or [string]$record.scenarioId -ne [string]$campaign.scenarioId -or [string]$record.comparisonCohortId -ne [string]$campaign.comparisonCohortId) { $errors.Add("campaign-identity-mismatch-$globalBlockOrdinal") }
    $campaignBlockOrdinal = [int]$record.campaignBlockOrdinal
    if ($campaignBlockOrdinal -lt 1 -or $campaignBlockOrdinal -gt [int]$campaign.blockCount) { $errors.Add("campaign-block-ordinal-invalid-$globalBlockOrdinal") }
    $expectedRowIndex = ($campaignBlockOrdinal - 1) % @($campaign.williamsRows).Count
    if ([int]$record.williamsRowIndex -ne $expectedRowIndex) { $errors.Add("williams-row-index-invalid-$globalBlockOrdinal") }
    if (-not $blockIds.Add([string]$record.blockId) -or -not (Test-G13RSafeId ([string]$record.blockId))) { $errors.Add("block-id-invalid-or-duplicate-$globalBlockOrdinal") }
    if ([IO.Path]::IsPathRooted([string]$record.outputRelativePath)) { $errors.Add("block-output-absolute-$globalBlockOrdinal") }
    else {
        $blockOutputFull = [IO.Path]::GetFullPath((Join-Path $formalRoot ([string]$record.outputRelativePath).Replace('/', '\')))
        if (-not (Test-G13RPathWithin -BasePath $formalRoot -CandidatePath $blockOutputFull)) { $errors.Add("block-output-escape-$globalBlockOrdinal") }
        if (-not $outputPaths.Add($blockOutputFull)) { $errors.Add("block-output-duplicate-$globalBlockOrdinal") }
    }
    $expectedAlgorithms = @($campaign.williamsRows[$expectedRowIndex].algorithms)
    $entries = @($record.entries)
    if ($entries.Count -ne $expectedAlgorithms.Count -or [int]$record.expectedSampleCount -ne $expectedAlgorithms.Count) { $errors.Add("sample-cardinality-invalid-$globalBlockOrdinal") }
    for ($index = 0; $index -lt $entries.Count; $index++) {
        $entry = $entries[$index]
        $expectedPosition = $index + 1
        $expectedPredecessor = if ($index -eq 0) { 'NONE' } else { [string]$expectedAlgorithms[$index - 1] }
        if ([int]$entry.position -ne $expectedPosition -or [string]$entry.algorithmId -ne [string]$expectedAlgorithms[$index] -or [string]$entry.predecessorAlgorithmId -ne $expectedPredecessor) { $errors.Add("sample-order-predecessor-invalid-$globalBlockOrdinal-$expectedPosition") }
        if (-not $runIds.Add([string]$entry.runId) -or -not (Test-G13RSafeId ([string]$entry.runId))) { $errors.Add("run-id-invalid-or-duplicate-$globalBlockOrdinal-$expectedPosition") }
        if ([IO.Path]::IsPathRooted([string]$entry.childDirectory) -or ([string]$entry.childDirectory).Contains('..')) { $errors.Add("child-directory-invalid-$globalBlockOrdinal-$expectedPosition") }
        $positionKey = "{0}|{1}|{2}" -f [string]$record.comparisonCohortId, [string]$entry.algorithmId, $expectedPosition
        if (-not $positionCounts.ContainsKey($positionKey)) { $positionCounts[$positionKey] = 0 }
        $positionCounts[$positionKey]++
        $sampleCount++
    }
    $campaignKey = [string]$record.campaignId
    if (-not $campaignBlockCounts.ContainsKey($campaignKey)) { $campaignBlockCounts[$campaignKey] = 0 }
    $campaignBlockCounts[$campaignKey]++
}

Assert-G13RValidation ($globalBlockOrdinal -eq 11160) 'streamed-block-count-invalid'
Assert-G13RValidation ($sampleCount -eq 31536) 'streamed-sample-count-invalid'
Assert-G13RValidation ($blockIds.Count -eq 11160) 'unique-block-id-count-invalid'
Assert-G13RValidation ($runIds.Count -eq 31536) 'unique-run-id-count-invalid'
Assert-G13RValidation ($outputPaths.Count -eq 11160) 'unique-output-path-count-invalid'
foreach ($campaign in $campaigns) {
    $actual = if ($campaignBlockCounts.ContainsKey([string]$campaign.campaignId)) { $campaignBlockCounts[[string]$campaign.campaignId] } else { 0 }
    if ($actual -ne [int]$campaign.blockCount) { $errors.Add("campaign-block-count-invalid-$($campaign.campaignId)") }
}
foreach ($cohort in @('four-algorithm-shared-goal-v1', 'per-agent-heterogeneous-goal-v1', 'grouped-field-heterogeneous-goal-v1')) {
    $cohortCampaignCount = @($campaigns | Where-Object { [string]$_.comparisonCohortId -eq $cohort }).Count
    $blocksPerCampaign = if ($cohort -eq 'four-algorithm-shared-goal-v1') { 144 } elseif ($cohort -eq 'per-agent-heterogeneous-goal-v1') { 204 } else { 108 }
    $algorithms = @(Get-G13RExpectedAlgorithms $cohort)
    $expectedPerAlgorithmPosition = [int](($cohortCampaignCount * $blocksPerCampaign) / $algorithms.Count)
    for ($position = 1; $position -le $algorithms.Count; $position++) {
        foreach ($algorithm in $algorithms) {
            $key = "$cohort|$algorithm|$position"
            $actual = if ($positionCounts.ContainsKey($key)) { $positionCounts[$key] } else { 0 }
            if ($actual -ne $expectedPerAlgorithmPosition) { $errors.Add("position-balance-invalid-$key-$actual-$expectedPerAlgorithmPosition") }
        }
    }
}

$summary = [ordered]@{
    schemaVersion = 1
    summaryKind = 'gate13r-serial-10pct-formal-schedule-validation-summary-v1'
    savedAtUtc = [DateTime]::UtcNow.ToString('o')
    configSha256 = Get-G13RLowerSha256 $ConfigPath
    provenanceSha256 = Get-G13RLowerSha256 $ProvenancePath
    scheduleSha256 = Get-G13RLowerSha256 $SchedulePath
    scheduleManifestSha256 = Get-G13RLowerSha256 $ScheduleManifestPath
    blockRecordCount = $globalBlockOrdinal
    sampleIdentityCount = $sampleCount
    uniqueBlockIdCount = $blockIds.Count
    uniqueRunIdCount = $runIds.Count
    uniqueOutputPathCount = $outputPaths.Count
    assertionCount = $assertions
    errorCount = $errors.Count
    errors = $errors.ToArray()
    formalRootExists = Test-Path -LiteralPath $formalRoot
    formalExecutionReceiptCreated = $false
    formalCampaignExecuted = $false
    passed = $errors.Count -eq 0
}
Write-G13RAtomicUtf8NoBomJson -Path $SummaryPath -Value $summary -Depth 30
if ($errors.Count -gt 0) { Write-Error ('Gate13R serial 10pct formal schedule validation failed: ' + ($errors -join '; ')); exit 1 }
Write-Host "Gate13R serial 10pct formal schedule validation passed: $globalBlockOrdinal blocks / $sampleCount samples." -ForegroundColor Green
exit 0
