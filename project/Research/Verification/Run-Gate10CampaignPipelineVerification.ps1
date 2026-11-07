[CmdletBinding()]
param(
    [string]$FixtureDirectory,
    [string]$ScenarioPath
)

$ErrorActionPreference = 'Stop'
$scriptDirectory = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectPath = [System.IO.Path]::GetFullPath((Join-Path $scriptDirectory '..\..'))
if ([string]::IsNullOrWhiteSpace($FixtureDirectory)) { $FixtureDirectory = Join-Path $scriptDirectory 'Gate10_FairCampaignFixture_Final' }
if ([string]::IsNullOrWhiteSpace($ScenarioPath)) { $ScenarioPath = Join-Path $scriptDirectory 'Gate10_SharedGoal.scenario.json' }
$FixtureDirectory = [System.IO.Path]::GetFullPath($FixtureDirectory)
$ScenarioPath = [System.IO.Path]::GetFullPath($ScenarioPath)
$summaryPath = Join-Path $scriptDirectory 'Gate10_FairCampaignPipeline.summary.json'
$campaignScript = Join-Path $projectPath 'Research\Run-FairPlanningCampaign.ps1'
$manifestPath = Join-Path $FixtureDirectory 'campaign-manifest.json'

function Get-LowerSha256([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Test-Near([double]$Actual, [double]$Expected, [double]$Tolerance = 0.000000001) {
    return [Math]::Abs($Actual - $Expected) -le $Tolerance
}

if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) { throw "Gate 10 campaign manifest not found: $manifestPath" }
if (-not (Test-Path -LiteralPath $ScenarioPath -PathType Leaf)) { throw "Gate 10 scenario not found: $ScenarioPath" }

$manifestHashBeforeGuards = Get-LowerSha256 $manifestPath
$manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
$scenarioHash = Get-LowerSha256 $ScenarioPath
$expectedRows = @(
    @('A*-R', 'D*L', 'IDFF', 'C-FF'),
    @('D*L', 'C-FF', 'A*-R', 'IDFF'),
    @('C-FF', 'IDFF', 'D*L', 'A*-R'),
    @('IDFF', 'A*-R', 'C-FF', 'D*L')
)
$expectedProfiles = [ordered]@{
    'A*-R' = [ordered]@{
        specificationId = 'a-star-repeated-v1'
        specificationSha256 = '0fe75b470bb0b1f256278ddf8089b86660a80a5c20c99006a140ff7c3ec8c5eb'
        implementationSha256 = 'a54bb43ed906c856e3d45493c4d3d10ff1b6f1e0ccda1a9f25ea774908b9c778'
        plannerStateModelId = 'stateless-per-request-v1'
        processedWorkUnit = 'nodes'
        nativeMetricsSemanticsId = 'astar-expanded-relaxed-v1'
        persistentStateInstanceCount = 0
        sharedFieldInstanceCount = 0
    }
    'D*L' = [ordered]@{
        specificationId = 'd-star-lite-v1'
        specificationSha256 = '65f03f4827c0bd2edceb967311451cace2a34642235457277cbbaaba222b01c3'
        implementationSha256 = 'ae9f1bdc2a30f924239145d8a165ed31d68f05b595916dbed21414fd1c69427f'
        plannerStateModelId = 'persistent-per-agent-v1'
        processedWorkUnit = 'nodes'
        nativeMetricsSemanticsId = 'dstar-expanded-relaxed-repaired-v1'
        persistentStateInstanceCount = 2
        sharedFieldInstanceCount = 0
    }
    'C-FF' = [ordered]@{
        specificationId = 'corrected-full-recompute-flow-field-v1'
        specificationSha256 = '6f29c7545c2f9d68ad0bfd2b707cb7f7798fd80b39816eb22010f278a6978223'
        implementationSha256 = 'bdaa52bc93950ea6a1737a7629ec6ceda60370f6ebc489deb166e2eddc51f3e1'
        plannerStateModelId = 'single-shared-multisource-field-v1'
        processedWorkUnit = 'cells'
        nativeMetricsSemanticsId = 'cff-expanded-relaxed-full-rebuild-v1'
        persistentStateInstanceCount = 1
        sharedFieldInstanceCount = 1
    }
    'IDFF' = [ordered]@{
        specificationId = 'incremental-dynamic-flow-field-v1'
        specificationSha256 = '8a7895c0daa38810a5b1087348be11b427cfeb1f6f0ed2f27730578ac84e70ef'
        implementationSha256 = '63aa0792bd0935d1e98158278580cf2ece5980cf3e52ef7e9adb16bbcddc7638'
        plannerStateModelId = 'single-shared-incremental-multisource-field-v1'
        processedWorkUnit = 'cells'
        nativeMetricsSemanticsId = 'idff-expanded-relaxed-incremental-repair-v1'
        persistentStateInstanceCount = 1
        sharedFieldInstanceCount = 1
    }
}

$errors = New-Object System.Collections.Generic.List[string]
$algorithmCounts = [ordered]@{ 'A*-R' = 0; 'D*L' = 0; 'C-FF' = 0; 'IDFF' = 0 }
$positionCounts = [ordered]@{}
foreach ($algorithmId in $algorithmCounts.Keys) { $positionCounts[$algorithmId] = [ordered]@{ p1 = 0; p2 = 0; p3 = 0; p4 = 0 } }
$predecessorCounts = [ordered]@{}
$runIds = New-Object System.Collections.Generic.HashSet[string]([System.StringComparer]::Ordinal)
$totalJsonlRecords = 0
$totalPlannerRecords = 0
$totalLifecycleRecords = 0
$totalWorkloadRecords = 0
$totalPlanOperations = 0
$totalRepairOperations = 0
$totalSucceededPlans = 0
$totalBudgetExceededOperations = 0
$ordinal = 0

if ($manifest.schemaVersion -ne 1) { $errors.Add('Campaign schemaVersion must be 1.') }
if ($manifest.campaignKind -ne 'gate10-pipeline-validation' -or $manifest.formalCampaign -ne $false) { $errors.Add('Fixture must be a non-formal Gate 10 pipeline validation campaign.') }
if ($manifest.campaignId -ne 'gate10-four-algorithm-fairness-final') { $errors.Add('Campaign id mismatch.') }
if ($manifest.comparisonCohortId -ne 'four-algorithm-shared-goal-v1') { $errors.Add('Comparison cohort mismatch.') }
if ($manifest.fairnessProtocolId -ne 'four-algorithm-fairness-v1' -or $manifest.fairnessProtocolSha256 -ne '42a4a8439c3d7b46b7644bed14b8f91d87bae4c6f8b2183a73609ee5461e82dd') { $errors.Add('Fairness protocol identity mismatch.') }
if ($manifest.workloadSpecificationSha256 -ne '2af12d33c4a010b14511f86d11d2f45634cac794b6763ea1cc36e8f1940a8ea1') { $errors.Add('Workload specification hash mismatch.') }
if ($manifest.scenarioSourceSha256 -ne $scenarioHash -or $manifest.canonicalScenarioSha256 -ne $scenarioHash) { $errors.Add('Campaign scenario/canonical hash mismatch.') }
if ($manifest.scenarioFingerprintSha256 -ne 'cad9ece799dc0b854647be6fe44c3a5cb59caaf3bf23c704505aed164ccc94ef') { $errors.Add('Scenario semantic fingerprint mismatch.') }
if ($manifest.blockCount -ne 4 -or $manifest.algorithmCount -ne 4 -or $manifest.sampleCount -ne 16 -or $manifest.completeBalanceCycleCount -ne 1) { $errors.Add('Campaign dimensions do not describe one complete four-algorithm Williams cycle.') }
if ($manifest.orderDesign -ne 'williams-balanced-v1' -or $manifest.positionBalanced -ne $true -or $manifest.orderedPredecessorBalanced -ne $true -or $manifest.completed -ne $true) { $errors.Add('Campaign balance/completion flags are invalid.') }

foreach ($profileProperty in $manifest.algorithmProfiles.psobject.Properties) {
    $algorithmId = $profileProperty.Name
    if (-not $expectedProfiles.Contains($algorithmId)) { $errors.Add("Unexpected campaign algorithm profile: $algorithmId"); continue }
    $actual = $profileProperty.Value
    $expected = $expectedProfiles[$algorithmId]
    foreach ($field in @('specificationId', 'specificationSha256', 'implementationSha256', 'plannerStateModelId', 'processedWorkUnit', 'nativeMetricsSemanticsId')) {
        if ([string]$actual.$field -ne [string]$expected[$field]) { $errors.Add("Campaign profile mismatch for $algorithmId.$field") }
    }
}

foreach ($entry in @($manifest.schedule)) {
    $ordinal++
    $block = [int]$entry.block
    $position = [int]$entry.position
    if ($block -lt 1 -or $block -gt 4 -or $position -lt 1 -or $position -gt 4) { $errors.Add("Invalid schedule coordinate at entry $ordinal."); continue }
    $expectedAlgorithm = $expectedRows[$block - 1][$position - 1]
    $algorithmId = [string]$entry.algorithmId
    if ($algorithmId -ne $expectedAlgorithm) { $errors.Add("Williams order mismatch at block $block position ${position}: expected $expectedAlgorithm, found $algorithmId.") }
    if (-not $algorithmCounts.Contains($algorithmId)) { $errors.Add("Unexpected algorithm at schedule entry ${ordinal}: $algorithmId"); continue }
    $algorithmCounts[$algorithmId]++
    $positionCounts[$algorithmId]["p$position"]++
    if ($position -gt 1) {
        $previous = [string]$expectedRows[$block - 1][$position - 2]
        $key = "$previous>$algorithmId"
        if (-not $predecessorCounts.Contains($key)) { $predecessorCounts[$key] = 0 }
        $predecessorCounts[$key]++
    }
    if (-not $runIds.Add([string]$entry.runId)) { $errors.Add("Duplicate run id: $($entry.runId)") }

    $runDirectory = Join-Path $FixtureDirectory $entry.directory
    $childManifestPath = Join-Path $FixtureDirectory $entry.manifestFile
    $resultPath = Join-Path $FixtureDirectory $entry.workloadResultFile
    $operationsPath = Join-Path $runDirectory 'operations.jsonl'
    $canonicalPath = Join-Path $runDirectory 'scenario.canonical.json'
    $unityLogPath = $runDirectory + '.Unity.log'
    $wrapperSummaryPath = $runDirectory + '.summary.json'
    foreach ($requiredPath in @($childManifestPath, $resultPath, $operationsPath, $canonicalPath, $unityLogPath, $wrapperSummaryPath)) {
        if (-not (Test-Path -LiteralPath $requiredPath -PathType Leaf)) { $errors.Add("Missing child artifact: $requiredPath") }
    }
    if (-not (Test-Path -LiteralPath $childManifestPath -PathType Leaf) -or -not (Test-Path -LiteralPath $resultPath -PathType Leaf) -or -not (Test-Path -LiteralPath $operationsPath -PathType Leaf)) { continue }
    if ((Get-LowerSha256 $childManifestPath) -ne $entry.manifestSha256) { $errors.Add("Child manifest hash mismatch: $childManifestPath") }
    if ((Get-LowerSha256 $resultPath) -ne $entry.workloadResultSha256) { $errors.Add("Workload result hash mismatch: $resultPath") }
    if ((Get-LowerSha256 $operationsPath) -ne $entry.operationsJsonlSha256) { $errors.Add("Operations JSONL hash mismatch: $operationsPath") }
    if ((Get-LowerSha256 $canonicalPath) -ne $manifest.canonicalScenarioSha256) { $errors.Add("Canonical scenario hash mismatch: $canonicalPath") }

    $childManifest = Get-Content -LiteralPath $childManifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $result = Get-Content -LiteralPath $resultPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $wrapperSummary = Get-Content -LiteralPath $wrapperSummaryPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $profile = $expectedProfiles[$algorithmId]
    if ($childManifest.schemaVersion -ne 2 -or $childManifest.completed -ne $true -or $wrapperSummary.passed -ne $true -or $wrapperSummary.exitCode -ne 0 -or $wrapperSummary.compilerErrorMatchCount -ne 0) { $errors.Add("Child wrapper/manifest failed: $($entry.runId)") }
    if ($childManifest.runId -ne $entry.runId -or $childManifest.algorithmId -ne $algorithmId -or $result.runId -ne $entry.runId -or $result.algorithmId -ne $algorithmId) { $errors.Add("Child run/algorithm identity mismatch: $($entry.runId)") }
    foreach ($object in @($childManifest, $result)) {
        if ($object.fairnessSchemaVersion -ne 1 -or $object.fairnessProtocolId -ne $manifest.fairnessProtocolId -or $object.fairnessProtocolSha256 -ne $manifest.fairnessProtocolSha256) { $errors.Add("Fairness identity mismatch: $($entry.runId)") }
        if ($object.workloadSpecificationSha256 -ne $manifest.workloadSpecificationSha256 -or $object.algorithmSpecificationId -ne $profile.specificationId -or $object.algorithmSpecificationSha256 -ne $profile.specificationSha256 -or $object.algorithmImplementationSha256 -ne $profile.implementationSha256) { $errors.Add("Specification/implementation identity mismatch: $($entry.runId)") }
        if ($object.goalCohortId -ne 'single-shared-goal-v1' -or $object.comparisonCohortId -ne $manifest.comparisonCohortId -or $object.distinctGoalCount -ne 1 -or $object.plannerInstanceCount -ne 1) { $errors.Add("Goal cohort/state identity mismatch: $($entry.runId)") }
        if ($object.persistentStateInstanceCount -ne $profile.persistentStateInstanceCount -or $object.sharedFieldInstanceCount -ne $profile.sharedFieldInstanceCount -or $object.plannerStateModelId -ne $profile.plannerStateModelId -or $object.processedWorkUnit -ne $profile.processedWorkUnit -or $object.nativeMetricsSemanticsId -ne $profile.nativeMetricsSemanticsId) { $errors.Add("Algorithm state/native metrics identity mismatch: $($entry.runId)") }
        if ($object.dynamicCostIncludesAllRepairsAndPostEventPlans -ne $true) { $errors.Add("Dynamic-cost completeness flag is false: $($entry.runId)") }
    }
    if ($result.scenarioFingerprintSha256 -ne $manifest.scenarioFingerprintSha256 -or $result.agentCount -ne 2 -or $result.scheduledEventCount -ne 4 -or $result.dynamicPlanningPhaseCount -ne 3) { $errors.Add("Workload dimensions mismatch: $($entry.runId)") }
    if ($result.planOperationCount -ne 8 -or $result.repairOperationCount -ne 4 -or $result.succeededPlanCount -ne 8 -or $result.noPathPlanCount -ne 0 -or $result.invalidPlanCount -ne 0 -or $result.failedPlanCount -ne 0 -or $result.budgetExceededOperationCount -ne 0 -or $result.completed -ne $true) { $errors.Add("Workload outcome mismatch: $($entry.runId)") }
    if ($result.processedNodesOrCells -ne ($result.initializationProcessedNodesOrCells + $result.initialPlanningProcessedNodesOrCells + $result.dynamicProcessedNodesOrCells)) { $errors.Add("Processed-work decomposition mismatch: $($entry.runId)") }
    if (-not (Test-Near $result.totalPlannerElapsedMilliseconds ($result.initializationMilliseconds + $result.initialPlanningMilliseconds + $result.dynamicHandlingTotalMilliseconds))) { $errors.Add("Elapsed-time decomposition mismatch: $($entry.runId)") }
    if (-not (Test-Near $result.totalPlannerElapsedMillisecondsPerAgent ($result.totalPlannerElapsedMilliseconds / 2.0)) -or -not (Test-Near $result.processedNodesOrCellsPerAgent ($result.processedNodesOrCells / 2.0))) { $errors.Add("Per-agent normalization mismatch: $($entry.runId)") }
    if (-not (Test-Near $result.dynamicHandlingMillisecondsPerScheduledEvent ($result.dynamicHandlingTotalMilliseconds / 4.0)) -or -not (Test-Near $result.dynamicProcessedNodesOrCellsPerScheduledEvent ($result.dynamicProcessedNodesOrCells / 4.0))) { $errors.Add("Per-event normalization mismatch: $($entry.runId)") }
    if (@($result.dynamicPhases).Count -ne 3 -or (@($result.dynamicPhases | Measure-Object -Property processedNodesOrCells -Sum).Sum) -ne $result.dynamicProcessedNodesOrCells -or -not (Test-Near (@($result.dynamicPhases | Measure-Object -Property combinedElapsedMilliseconds -Sum).Sum) $result.dynamicHandlingTotalMilliseconds)) { $errors.Add("Dynamic-phase accounting mismatch: $($entry.runId)") }

    $records = @(Get-Content -LiteralPath $operationsPath -Encoding UTF8 | ForEach-Object { $_ | ConvertFrom-Json })
    $totalJsonlRecords += $records.Count
    $plannerRecords = @($records | Where-Object { $_.recordType -eq 'planner_operation' })
    $lifecycleRecords = @($records | Where-Object { $_.recordType -eq 'runner_lifecycle' })
    $workloadRecords = @($records | Where-Object { $_.recordType -eq 'planning_workload_result' })
    $totalPlannerRecords += $plannerRecords.Count
    $totalLifecycleRecords += $lifecycleRecords.Count
    $totalWorkloadRecords += $workloadRecords.Count
    if ($records.Count -ne 17 -or $plannerRecords.Count -ne 13 -or $lifecycleRecords.Count -ne 3 -or $workloadRecords.Count -ne 1) { $errors.Add("JSONL record type counts mismatch: $($entry.runId)") }
    for ($sequence = 0; $sequence -lt $records.Count; $sequence++) {
        if ($records[$sequence].sequence -ne $sequence -or $records[$sequence].runId -ne $entry.runId) { $errors.Add("JSONL sequence/run identity mismatch: $($entry.runId) at $sequence"); break }
    }
    if ($workloadRecords.Count -eq 1) {
        $payload = $workloadRecords[0].payload
        if ($payload.fairnessProtocolSha256 -ne $manifest.fairnessProtocolSha256 -or $payload.algorithmSpecificationSha256 -ne $profile.specificationSha256 -or $payload.algorithmImplementationSha256 -ne $profile.implementationSha256 -or $payload.workloadSpecificationSha256 -ne $manifest.workloadSpecificationSha256 -or $payload.comparisonCohortId -ne $manifest.comparisonCohortId) { $errors.Add("JSONL workload provenance mismatch: $($entry.runId)") }
    }
    $compilerMatches = @(Select-String -LiteralPath $unityLogPath -Pattern @('error CS\d{4}', 'Scripts have compiler errors', 'Compilation failed', 'executeMethod.+could not be found') -AllMatches)
    if ($compilerMatches.Count -ne 0 -or @(Select-String -LiteralPath $unityLogPath -SimpleMatch 'DDM planning batch completed. Manifest:').Count -eq 0) { $errors.Add("Unity log did not complete cleanly: $unityLogPath") }

    $totalPlanOperations += [int]$result.planOperationCount
    $totalRepairOperations += [int]$result.repairOperationCount
    $totalSucceededPlans += [int]$result.succeededPlanCount
    $totalBudgetExceededOperations += [int]$result.budgetExceededOperationCount
}

foreach ($algorithmId in $algorithmCounts.Keys) {
    if ($algorithmCounts[$algorithmId] -ne 4) { $errors.Add("Algorithm $algorithmId does not have exactly four samples.") }
    foreach ($position in 1..4) { if ($positionCounts[$algorithmId]["p$position"] -ne 1) { $errors.Add("Algorithm $algorithmId position $position is not represented exactly once.") } }
}
foreach ($left in $algorithmCounts.Keys) {
    foreach ($right in $algorithmCounts.Keys) {
        if ($left -eq $right) { continue }
        $key = "$left>$right"
        if (-not $predecessorCounts.Contains($key) -or $predecessorCounts[$key] -ne 1) { $errors.Add("Ordered predecessor pair $key is not represented exactly once.") }
    }
}
if ($ordinal -ne 16 -or $runIds.Count -ne 16) { $errors.Add('Campaign does not contain 16 unique scheduled runs.') }
if ($totalJsonlRecords -ne 272 -or $totalPlannerRecords -ne 208 -or $totalLifecycleRecords -ne 48 -or $totalWorkloadRecords -ne 16) { $errors.Add('Campaign-wide JSONL counts are incorrect.') }
if ($totalPlanOperations -ne 128 -or $totalRepairOperations -ne 64 -or $totalSucceededPlans -ne 128 -or $totalBudgetExceededOperations -ne 0) { $errors.Add('Campaign-wide workload totals are incorrect.') }

# Guard 1: the retained fixture must be create-new and therefore refuse an overwrite.
$savedErrorActionPreference = $ErrorActionPreference
try {
    $ErrorActionPreference = 'Continue'
    $overwriteOutput = & powershell -NoProfile -ExecutionPolicy Bypass -File $campaignScript -ScenarioPath $ScenarioPath -ComparisonCohortId 'four-algorithm-shared-goal-v1' -Blocks 4 -CampaignId 'gate10-four-algorithm-fairness-final' -OutputDirectory $FixtureDirectory 2>&1 | Out-String
    $overwriteExitCode = $LASTEXITCODE
} finally {
    $ErrorActionPreference = $savedErrorActionPreference
}
$manifestHashAfterOverwriteGuard = Get-LowerSha256 $manifestPath
$overwriteGuardPassed = $overwriteExitCode -ne 0 -and $manifestHashAfterOverwriteGuard -eq $manifestHashBeforeGuards
if (-not $overwriteGuardPassed) { $errors.Add('Campaign no-overwrite guard failed or changed the retained manifest.') }

# Guard 2: a block count that is not a complete balance cycle must fail before output creation.
$invalidBlockOutputDirectory = Join-Path ([System.IO.Path]::GetTempPath()) ('ddm-gate10-invalid-blocks-' + [Guid]::NewGuid().ToString('N'))
try {
    $ErrorActionPreference = 'Continue'
    $invalidBlockOutput = & powershell -NoProfile -ExecutionPolicy Bypass -File $campaignScript -ScenarioPath $ScenarioPath -ComparisonCohortId 'four-algorithm-shared-goal-v1' -Blocks 2 -CampaignId 'gate10-invalid-blocks' -OutputDirectory $invalidBlockOutputDirectory 2>&1 | Out-String
    $invalidBlockExitCode = $LASTEXITCODE
} finally {
    $ErrorActionPreference = $savedErrorActionPreference
}
$invalidBlockGuardPassed = $invalidBlockExitCode -ne 0 -and -not (Test-Path -LiteralPath $invalidBlockOutputDirectory)
if (-not $invalidBlockGuardPassed) { $errors.Add('Invalid-block-count guard failed or created output.') }

$checks = [ordered]@{
    fixedCampaignManifestHash = $manifestHashBeforeGuards -eq '4d9d61b15f2e375909c541f6070bd405624e90ae516e6ecb7d7b4ebb7585e987'
    nonFormalPipelineFixture = $manifest.campaignKind -eq 'gate10-pipeline-validation' -and $manifest.formalCampaign -eq $false
    frozenProtocolAndWorkloadIdentity = $manifest.fairnessProtocolSha256 -eq '42a4a8439c3d7b46b7644bed14b8f91d87bae4c6f8b2183a73609ee5461e82dd' -and $manifest.workloadSpecificationSha256 -eq '2af12d33c4a010b14511f86d11d2f45634cac794b6763ea1cc36e8f1940a8ea1'
    exactWilliamsSchedule = $ordinal -eq 16 -and $errors.Count -eq 0
    positionBalance = @($positionCounts.GetEnumerator() | ForEach-Object { $_.Value.Values } | Where-Object { $_ -ne 1 }).Count -eq 0
    orderedPredecessorBalance = $predecessorCounts.Count -eq 12 -and @($predecessorCounts.Values | Where-Object { $_ -ne 1 }).Count -eq 0
    childArtifactsAndHashes = $errors.Count -eq 0
    provenanceAndCohortIdentity = $errors.Count -eq 0
    workloadAccounting = $totalPlanOperations -eq 128 -and $totalRepairOperations -eq 64 -and $totalSucceededPlans -eq 128 -and $totalBudgetExceededOperations -eq 0
    jsonlCompleteness = $totalJsonlRecords -eq 272 -and $totalPlannerRecords -eq 208 -and $totalLifecycleRecords -eq 48 -and $totalWorkloadRecords -eq 16
    noOverwriteGuard = $overwriteGuardPassed
    invalidBlockCountGuard = $invalidBlockGuardPassed
}
if (-not $checks.fixedCampaignManifestHash) { $errors.Add('Retained campaign manifest hash differs from the frozen fixture hash.') }
$failedChecks = @($checks.GetEnumerator() | Where-Object { -not $_.Value } | ForEach-Object { $_.Key })
$passed = $errors.Count -eq 0 -and $failedChecks.Count -eq 0
$summary = [ordered]@{
    savedAt = (Get-Date).ToString('o')
    fixtureDirectory = $FixtureDirectory
    campaignManifestPath = $manifestPath
    campaignManifestSha256 = $manifestHashBeforeGuards
    scenarioSourceSha256 = $scenarioHash
    sampleCount = $ordinal
    algorithmCounts = $algorithmCounts
    positionCounts = $positionCounts
    orderedPredecessorCounts = $predecessorCounts
    totalJsonlRecords = $totalJsonlRecords
    totalPlannerRecords = $totalPlannerRecords
    totalLifecycleRecords = $totalLifecycleRecords
    totalWorkloadRecords = $totalWorkloadRecords
    totalPlanOperations = $totalPlanOperations
    totalRepairOperations = $totalRepairOperations
    totalSucceededPlans = $totalSucceededPlans
    totalBudgetExceededOperations = $totalBudgetExceededOperations
    overwriteGuard = [ordered]@{ exitCode = $overwriteExitCode; manifestUnchanged = $manifestHashAfterOverwriteGuard -eq $manifestHashBeforeGuards; output = $overwriteOutput.Trim() }
    invalidBlockCountGuard = [ordered]@{ exitCode = $invalidBlockExitCode; outputDirectoryCreated = Test-Path -LiteralPath $invalidBlockOutputDirectory; output = $invalidBlockOutput.Trim() }
    validationErrors = @($errors)
    checks = $checks
    failedChecks = $failedChecks
    passed = $passed
}
$summary | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $summaryPath -Encoding UTF8
$summary | ConvertTo-Json -Depth 12
if (-not $passed) { Write-Error "Gate 10 campaign pipeline verification failed. Review $summaryPath."; exit 1 }
Write-Host 'Gate 10 campaign pipeline verification passed.' -ForegroundColor Green
exit 0
