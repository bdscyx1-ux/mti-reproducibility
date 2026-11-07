[CmdletBinding()]
param(
    [string]$ProjectPath,
    [string]$PlanPath,
    [string]$PilotRoot
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0
$scriptDirectory = Split-Path -Parent $MyInvocation.MyCommand.Path
if ([string]::IsNullOrWhiteSpace($ProjectPath)) { $ProjectPath = [System.IO.Path]::GetFullPath((Join-Path $scriptDirectory '..')) }
else { $ProjectPath = [System.IO.Path]::GetFullPath($ProjectPath) }
if ([string]::IsNullOrWhiteSpace($PlanPath)) { $PlanPath = Join-Path $ProjectPath 'Research\Gate12_Pilot_Plan.v1.json' }
elseif (-not [System.IO.Path]::IsPathRooted($PlanPath)) { $PlanPath = Join-Path $ProjectPath $PlanPath }
$PlanPath = [System.IO.Path]::GetFullPath($PlanPath)

$modulePath = Join-Path $ProjectPath 'Research\Gate12PilotAnalysis.psm1'
$preAuditPath = Join-Path $ProjectPath 'Research\Verification\Gate12_PreImplementationAudit.summary.json'
Import-Module $modulePath -Force
$plan = Get-Content -LiteralPath $PlanPath -Raw -Encoding UTF8 | ConvertFrom-Json
$preAudit = Get-Content -LiteralPath $preAuditPath -Raw -Encoding UTF8 | ConvertFrom-Json

if ([string]::IsNullOrWhiteSpace($PilotRoot)) { $PilotRoot = Join-Path $ProjectPath $plan.output.rootRelativePath.Replace('/', '\') }
elseif (-not [System.IO.Path]::IsPathRooted($PilotRoot)) { $PilotRoot = Join-Path $ProjectPath $PilotRoot }
$PilotRoot = [System.IO.Path]::GetFullPath($PilotRoot)
$plannedRoot = [System.IO.Path]::GetFullPath((Join-Path $ProjectPath $plan.output.rootRelativePath.Replace('/', '\')))
if (-not [string]::Equals($PilotRoot, $plannedRoot, [System.StringComparison]::OrdinalIgnoreCase)) { throw "Pilot root differs from frozen plan: $plannedRoot" }
if (-not (Test-Path -LiteralPath $PilotRoot -PathType Container)) { throw "Pilot root not found: $PilotRoot" }

function Write-Utf8NoBomJson([string]$Path, $Value, [int]$Depth = 24) {
    $json = $Value | ConvertTo-Json -Depth $Depth
    $json = $json.Replace("`r`n", "`n").Replace("`r", "`n")
    if (-not $json.EndsWith("`n", [System.StringComparison]::Ordinal)) { $json += "`n" }
    $encoding = New-Object System.Text.UTF8Encoding($false, $true)
    [System.IO.File]::WriteAllText($Path, $json, $encoding)
}

function Write-Utf8NoBomText([string]$Path, [string]$Value) {
    $normalized = $Value.Replace("`r`n", "`n").Replace("`r", "`n")
    if (-not $normalized.EndsWith("`n", [System.StringComparison]::Ordinal)) { $normalized += "`n" }
    $encoding = New-Object System.Text.UTF8Encoding($false, $true)
    [System.IO.File]::WriteAllText($Path, $normalized, $encoding)
}

function Get-ProjectRelativePath([string]$FullPath) {
    $root = $ProjectPath.TrimEnd('\', '/') + [System.IO.Path]::DirectorySeparatorChar
    $full = [System.IO.Path]::GetFullPath($FullPath)
    if (-not $full.StartsWith($root, [System.StringComparison]::OrdinalIgnoreCase)) { throw "Path is outside project root: $full" }
    return $full.Substring($root.Length).Replace('\', '/')
}

function Get-MetricValue($Object, [string]$Name) {
    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) { throw "Metric is missing: $Name" }
    $value = [double]$property.Value
    if (-not (Test-Gate12FiniteNumber $value)) { throw "Metric is non-finite: $Name" }
    return $value
}

$analysisPaths = [ordered]@{
    noise = Join-Path $PilotRoot 'noise-analysis.json'
    candidates = Join-Path $PilotRoot 'candidate-sample-sizes.json'
    budget = Join-Path $PilotRoot 'budget-feasibility.json'
    report = Join-Path $PilotRoot 'Gate12_Pilot_Validation_Report.md'
    manifest = Join-Path $PilotRoot 'analysis-manifest.json'
}
foreach ($path in $analysisPaths.Values) { if (Test-Path -LiteralPath $path) { throw "Analysis output already exists; refusing to overwrite: $path" } }

if ($preAudit.passed -ne $true -or $preAudit.auditMode -ne 'pre-implementation-freeze') { throw 'Pre-implementation audit is not passing.' }
if ((Get-Gate12LowerSha256 $PlanPath) -ne $preAudit.frozenFiles.pilotPlan.sha256 -or
    (Get-Gate12LowerSha256 (Join-Path $ProjectPath 'Research\Gate12_Pilot_Noise_and_Sample_Size_Specification.md')) -ne $preAudit.frozenFiles.specification.sha256 -or
    (Get-Gate12LowerSha256 (Join-Path $ProjectPath 'Research\Gate12_Pilot_Test_Design.md')) -ne $preAudit.frozenFiles.testDesign.sha256) {
    throw 'A frozen Gate 12 planning artifact changed after pre-implementation audit.'
}

$pilotManifestPath = Join-Path $PilotRoot 'pilot-manifest.json'
if (-not (Test-Path -LiteralPath $pilotManifestPath -PathType Leaf)) { throw "Pilot manifest not found: $pilotManifestPath" }
$pilotManifest = Get-Content -LiteralPath $pilotManifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
if ($pilotManifest.completed -ne $true -or $pilotManifest.formalCampaign -ne $false -or $pilotManifest.gate13ExecutionAuthorized -ne $false -or $pilotManifest.gate13ResultsPermitted -ne $false -or $pilotManifest.pilotPlanId -ne $plan.pilotPlanId) { throw 'Pilot manifest identity/completion/formal boundary is invalid.' }
if ($pilotManifest.measuredCampaignCount -ne 12 -or $pilotManifest.measuredUnityProcessCount -ne 256 -or $pilotManifest.warmupUnityProcessCount -ne 16 -or $pilotManifest.totalUnityProcessCount -ne 272 -or $pilotManifest.technicalInvalidityCount -ne 0 -or $pilotManifest.autoRetryCount -ne 0) { throw 'Pilot manifest frozen counts or invalidity/retry state is invalid.' }
if ($pilotManifest.analysisModuleSha256 -ne (Get-Gate12LowerSha256 $modulePath)) { throw 'Analysis module changed after pilot execution.' }

foreach ($environmentField in @(
    [ordered]@{ file = $pilotManifest.environmentStartFile; hash = $pilotManifest.environmentStartSha256 },
    [ordered]@{ file = $pilotManifest.environmentPostWarmupFile; hash = $pilotManifest.environmentPostWarmupSha256 },
    [ordered]@{ file = $pilotManifest.environmentEndFile; hash = $pilotManifest.environmentEndSha256 }
)) {
    $path = Join-Path $PilotRoot ([string]$environmentField.file)
    if ((Get-Gate12LowerSha256 $path) -ne $environmentField.hash) { throw "Environment snapshot hash mismatch: $path" }
}
$environmentStart = Get-Content -LiteralPath (Join-Path $PilotRoot $pilotManifest.environmentStartFile) -Raw -Encoding UTF8 | ConvertFrom-Json
$environmentPostWarmup = Get-Content -LiteralPath (Join-Path $PilotRoot $pilotManifest.environmentPostWarmupFile) -Raw -Encoding UTF8 | ConvertFrom-Json
$environmentEnd = Get-Content -LiteralPath (Join-Path $PilotRoot $pilotManifest.environmentEndFile) -Raw -Encoding UTF8 | ConvertFrom-Json
foreach ($environment in @($environmentStart, $environmentPostWarmup, $environmentEnd)) {
    if ($environment.preflightVerdict.passed -ne $true -or $environment.frozenHashesMatch -ne $true -or $environment.unityProcessCount -ne 0 -or $environment.unityLockfilePresent -ne $false) { throw "Environment snapshot failed: $($environment.phase)" }
}
if ($environmentStart.activePowerSchemeGuid -ne $environmentPostWarmup.activePowerSchemeGuid -or $environmentStart.activePowerSchemeGuid -ne $environmentEnd.activePowerSchemeGuid -or $environmentStart.acLineStatus -ne 1 -or $environmentPostWarmup.acLineStatus -ne 1 -or $environmentEnd.acLineStatus -ne 1) { throw 'Power state changed across pilot.' }
if ($pilotManifest.bundleBefore.passed -ne $true -or $pilotManifest.bundleAfter.passed -ne $true -or $pilotManifest.bundleBefore.manifestSha256 -ne $pilotManifest.bundleAfter.manifestSha256 -or $pilotManifest.bundleBefore.orderedAggregateSha256 -ne $pilotManifest.bundleAfter.orderedAggregateSha256) { throw 'Retained bundle before/after identity differs.' }

$warmupManifestPath = Join-Path $ProjectPath $pilotManifest.warmup.campaignManifestRelativePath.Replace('/', '\')
if ((Get-Gate12LowerSha256 $warmupManifestPath) -ne $pilotManifest.warmup.campaignManifestSha256) { throw 'Warm-up manifest hash mismatch.' }
$warmupManifest = Get-Content -LiteralPath $warmupManifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
if ($pilotManifest.warmup.analysisExcluded -ne $true -or $warmupManifest.sampleCount -ne 16 -or $warmupManifest.formalCampaign -ne $false -or $warmupManifest.completed -ne $true) { throw 'Warm-up exclusion or identity is invalid.' }
$warmupRunIds = @($warmupManifest.schedule | ForEach-Object { [string]$_.runId })

$samples = New-Object System.Collections.Generic.List[object]
$measuredRunIds = New-Object System.Collections.Generic.List[string]
$campaignCostRows = @()
$campaignErrors = New-Object System.Collections.Generic.List[string]
foreach ($campaignEntry in @($pilotManifest.measuredCampaigns | Sort-Object ordinal)) {
    $campaignDirectory = Join-Path $ProjectPath $campaignEntry.campaignDirectory.Replace('/', '\')
    $campaignManifestPath = Join-Path $ProjectPath $campaignEntry.campaignManifestRelativePath.Replace('/', '\')
    if ((Get-Gate12LowerSha256 $campaignManifestPath) -ne $campaignEntry.campaignManifestSha256) { $campaignErrors.Add("Campaign manifest hash mismatch: $($campaignEntry.campaignId)"); continue }
    $campaign = Get-Content -LiteralPath $campaignManifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($campaign.completed -ne $true -or $campaign.formalCampaign -ne $false -or $campaign.campaignId -ne $campaignEntry.campaignId -or $campaign.scenarioId -ne $campaignEntry.scenarioId -or $campaign.comparisonCohortId -ne $campaignEntry.comparisonCohortId -or $campaign.sampleCount -ne $campaignEntry.sampleCount -or $campaign.positionBalanced -ne $true -or $campaign.orderedPredecessorBalanced -ne $true) {
        $campaignErrors.Add("Campaign identity/balance mismatch: $($campaignEntry.campaignId)")
        continue
    }
    if ($campaign.schedule.Count -ne $campaign.sampleCount) { $campaignErrors.Add("Campaign schedule count mismatch: $($campaignEntry.campaignId)"); continue }
    $campaignCostRows += [ordered]@{
        campaignId = [string]$campaignEntry.campaignId
        comparisonCohortId = [string]$campaignEntry.comparisonCohortId
        scenarioId = [string]$campaignEntry.scenarioId
        sampleCount = [int]$campaignEntry.sampleCount
        wallSeconds = [double]$campaignEntry.wallSeconds
        wallSecondsPerSample = [double]$campaignEntry.wallSeconds / [int]$campaignEntry.sampleCount
        outputBytes = [long]$campaignEntry.outputBytes
        outputBytesPerSample = [double]$campaignEntry.outputBytes / [int]$campaignEntry.sampleCount
    }
    foreach ($scheduleEntry in @($campaign.schedule | Sort-Object block, position)) {
        $childManifestPath = Join-Path $campaignDirectory ([string]$scheduleEntry.manifestFile).Replace('/', '\')
        $resultPath = Join-Path $campaignDirectory ([string]$scheduleEntry.workloadResultFile).Replace('/', '\')
        if (-not (Test-Path -LiteralPath $childManifestPath -PathType Leaf) -or -not (Test-Path -LiteralPath $resultPath -PathType Leaf)) { $campaignErrors.Add("Child artifact missing: $($scheduleEntry.runId)"); continue }
        if ((Get-Gate12LowerSha256 $childManifestPath) -ne $scheduleEntry.manifestSha256 -or (Get-Gate12LowerSha256 $resultPath) -ne $scheduleEntry.workloadResultSha256) { $campaignErrors.Add("Child artifact hash mismatch: $($scheduleEntry.runId)"); continue }
        $childManifest = Get-Content -LiteralPath $childManifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $result = Get-Content -LiteralPath $resultPath -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($childManifest.completed -ne $true -or $result.completed -ne $true -or $childManifest.runId -ne $scheduleEntry.runId -or $result.runId -ne $scheduleEntry.runId -or $result.algorithmId -ne $scheduleEntry.algorithmId -or $result.scenarioId -ne $campaign.scenarioId -or $result.comparisonCohortId -ne $campaign.comparisonCohortId -or $result.dynamicCostIncludesAllRepairsAndPostEventPlans -ne $true -or $result.fairnessSchemaVersion -ne 1) {
            $campaignErrors.Add("Child identity/provenance mismatch: $($scheduleEntry.runId)")
            continue
        }
        $primary = Get-MetricValue -Object $result -Name 'dynamicHandlingMillisecondsPerScheduledEvent'
        if ($primary -le 0.0) { $campaignErrors.Add("Primary endpoint is non-positive: $($scheduleEntry.runId)"); continue }
        $measuredRunIds.Add([string]$scheduleEntry.runId)
        $samples.Add([pscustomobject]@{
            campaignOrdinal = [int]$campaignEntry.ordinal
            campaignId = [string]$campaignEntry.campaignId
            comparisonCohortId = [string]$campaign.comparisonCohortId
            scenarioId = [string]$campaign.scenarioId
            algorithmId = [string]$result.algorithmId
            block = [int]$scheduleEntry.block
            position = [int]$scheduleEntry.position
            runId = [string]$scheduleEntry.runId
            workloadResultRelativePath = Get-ProjectRelativePath $resultPath
            primaryEndpoint = $primary
            initializationMilliseconds = Get-MetricValue $result 'initializationMilliseconds'
            initialPlanningMilliseconds = Get-MetricValue $result 'initialPlanningMilliseconds'
            totalPlannerElapsedMillisecondsPerAgent = Get-MetricValue $result 'totalPlannerElapsedMillisecondsPerAgent'
            managedAllocatedBytes = Get-MetricValue $result 'managedAllocatedBytes'
            dynamicManagedAllocatedBytes = Get-MetricValue $result 'dynamicManagedAllocatedBytes'
            processedNodesOrCellsPerAgent = Get-MetricValue $result 'processedNodesOrCellsPerAgent'
            dynamicProcessedNodesOrCellsPerScheduledEvent = Get-MetricValue $result 'dynamicProcessedNodesOrCellsPerScheduledEvent'
            planSuccessRate = Get-MetricValue $result 'planSuccessRate'
            budgetOverrunRate = Get-MetricValue $result 'budgetOverrunRate'
            planOperationCount = [int]$result.planOperationCount
            repairOperationCount = [int]$result.repairOperationCount
            succeededPlanCount = [int]$result.succeededPlanCount
            noPathPlanCount = [int]$result.noPathPlanCount
            budgetExceededPlanCount = [int]$result.budgetExceededPlanCount
            invalidPlanCount = [int]$result.invalidPlanCount
            failedPlanCount = [int]$result.failedPlanCount
            budgetExceededOperationCount = [int]$result.budgetExceededOperationCount
        })
    }
}
if ($campaignErrors.Count -ne 0) { throw "Measured campaign validation failed: $($campaignErrors -join '; ')" }
if ($samples.Count -ne 256 -or $measuredRunIds.Count -ne 256 -or @($measuredRunIds | Sort-Object -Unique).Count -ne 256) { throw "Measured sample identity count mismatch: samples=$($samples.Count), unique=$(@($measuredRunIds | Sort-Object -Unique).Count)" }
if (@($measuredRunIds | Where-Object { $_ -in $warmupRunIds }).Count -ne 0) { throw 'Warm-up run leaked into measured run identities.' }

$sharedScenarioIds = @($plan.pilotSubset.scenarios | Where-Object goalStructureId -eq 'shared-single-v1' | Sort-Object structuralRow | ForEach-Object { [string]$_.scenarioId })
$heterogeneousScenarioIds = @($plan.pilotSubset.scenarios | Where-Object goalStructureId -eq 'heterogeneous-v1' | Sort-Object structuralRow | ForEach-Object { [string]$_.scenarioId })
$familyResults = @()
foreach ($familyDefinition in @($plan.analysis.families)) {
    $expectedScenarios = if ($familyDefinition.goalStructureId -eq 'shared-single-v1') { $sharedScenarioIds } else { $heterogeneousScenarioIds }
    $familyResults += Get-Gate12FamilyAnalysis -Samples ($samples.ToArray()) -FamilyDefinition $familyDefinition -ExpectedScenarioIds $expectedScenarios -ExpectedRepetitionsPerCell ([int]$plan.analysis.minimumMeasuredRepetitionsPerCell)
}
if ($familyResults.Count -ne 4) { throw 'Four family analyses were not produced.' }

$descriptiveMetricNames = @(
    'initializationMilliseconds',
    'initialPlanningMilliseconds',
    'primaryEndpoint',
    'totalPlannerElapsedMillisecondsPerAgent',
    'managedAllocatedBytes',
    'dynamicManagedAllocatedBytes',
    'processedNodesOrCellsPerAgent',
    'dynamicProcessedNodesOrCellsPerScheduledEvent',
    'planSuccessRate',
    'budgetOverrunRate'
)
$cellKeys = @($samples | ForEach-Object { "$($_.comparisonCohortId)|$($_.scenarioId)|$($_.algorithmId)" } | Sort-Object -Unique)
$descriptiveCells = @()
foreach ($key in $cellKeys) {
    $parts = $key.Split('|')
    $cellSamples = @($samples | Where-Object { $_.comparisonCohortId -eq $parts[0] -and $_.scenarioId -eq $parts[1] -and $_.algorithmId -eq $parts[2] })
    $metrics = [ordered]@{}
    foreach ($metricName in $descriptiveMetricNames) {
        $values = @($cellSamples | ForEach-Object { [double]($_.PSObject.Properties[$metricName].Value) })
        $metrics[$metricName] = Get-Gate12CellStatistics -Values $values
    }
    $descriptiveCells += [ordered]@{ comparisonCohortId = $parts[0]; scenarioId = $parts[1]; algorithmId = $parts[2]; repetitionCount = $cellSamples.Count; metrics = $metrics }
}

$noiseAnalysis = [ordered]@{
    schemaVersion = 1
    analysisId = 'gate12-noise-analysis-v1'
    analyzedAt = (Get-Date).ToString('o')
    pilotManifestSha256 = Get-Gate12LowerSha256 $pilotManifestPath
    primaryEndpointId = $plan.analysis.primaryEndpointId
    transform = $plan.analysis.transform
    cellSigmaEstimator = $plan.analysis.cellSigmaEstimator
    familySigmaEstimator = $plan.analysis.familySigmaEstimator
    warmupExcluded = $true
    measuredSampleCount = $samples.Count
    familyResults = $familyResults
    descriptiveMetricCells = $descriptiveCells
    timingOutliersRetained = $true
    algorithmicFailuresRetained = $true
    technicalInvalidityCount = 0
    completed = $true
}
Write-Utf8NoBomJson -Path $analysisPaths.noise -Value $noiseAnalysis -Depth 28

$candidateRows = @($familyResults | ForEach-Object {
    [ordered]@{
        familyId = $_.familyId
        sigmaLog = $_.sigmaLog
        governingCellId = $_.governingCellId
        nRaw = $_.sampleSize.nRaw
        requiredNFormal = $_.sampleSize.requiredNFormal
        candidateNFormal = $_.sampleSize.candidateNFormal
        precisionStatus = $_.sampleSize.precisionStatus
        overCap = $_.sampleSize.overCap
    }
})
$precisionBlocked = @($candidateRows | Where-Object overCap -eq $true).Count -gt 0
$candidateSampleSizes = [ordered]@{
    schemaVersion = 1
    analysisId = 'gate12-candidate-sample-sizes-v1'
    generatedAt = (Get-Date).ToString('o')
    sourceNoiseAnalysisSha256 = Get-Gate12LowerSha256 $analysisPaths.noise
    formula = $plan.analysis.precisionFormula
    minimumPerAlgorithm = $plan.analysis.minimumPerAlgorithm
    cycleMultiple = $plan.analysis.cycleMultiple
    maximumPerAlgorithm = $plan.analysis.maximumPerAlgorithm
    families = $candidateRows
    anyFamilyOverCap = $precisionBlocked
    gate13PrecisionReadiness = if ($precisionBlocked) { 'blocked-versioned-amendment-required' } else { 'candidate-fixed-n-available-separate-authorization-required' }
    significanceEarlyStoppingAllowed = $false
    trendEarlyStoppingAllowed = $false
    formalCampaignStarted = $false
    completed = $true
}
Write-Utf8NoBomJson -Path $analysisPaths.candidates -Value $candidateSampleSizes -Depth 14

$candidateByFamily = @{}
$requiredByFamily = @{}
foreach ($row in $candidateRows) { $candidateByFamily[$row.familyId] = [long]$row.candidateNFormal; $requiredByFamily[$row.familyId] = [long]$row.requiredNFormal }
$candidateProcessCount = Get-Gate12ProjectedProcessCount -P1 $candidateByFamily['P1-DL-vs-A-shared'] -P2 $candidateByFamily['P2-DL-vs-A-hetero'] -P3 $candidateByFamily['P3-IDFF-vs-CFF-shared'] -P4 $candidateByFamily['P4-IDFF-vs-CFF-grouped']
$requiredProcessCount = Get-Gate12ProjectedProcessCount -P1 $requiredByFamily['P1-DL-vs-A-shared'] -P2 $requiredByFamily['P2-DL-vs-A-hetero'] -P3 $requiredByFamily['P3-IDFF-vs-CFF-shared'] -P4 $requiredByFamily['P4-IDFF-vs-CFF-grouped']
$wallPerSample = [double[]]@($campaignCostRows | ForEach-Object { [double]$_.wallSecondsPerSample })
$bytesPerSample = [double[]]@($campaignCostRows | ForEach-Object { [double]$_.outputBytesPerSample })
$medianWallSeconds = Get-Gate12Median -Values $wallPerSample
$p95WallSeconds = Get-Gate12NearestRankPercentile -Values $wallPerSample -Probability 0.95
$medianBytes = Get-Gate12Median -Values $bytesPerSample
$p95Bytes = Get-Gate12NearestRankPercentile -Values $bytesPerSample -Probability 0.95
$candidateMedianHours = $candidateProcessCount * $medianWallSeconds / 3600.0
$candidateP95Hours = $candidateProcessCount * $p95WallSeconds / 3600.0
$requiredP95Hours = $requiredProcessCount * $p95WallSeconds / 3600.0
$candidateMedianGiB = $candidateProcessCount * $medianBytes / 1GB
$candidateP95GiB = $candidateProcessCount * $p95Bytes / 1GB
$requiredP95GiB = $requiredProcessCount * $p95Bytes / 1GB
$candidateHeadroomGiB = [double]$environmentEnd.freeOutputDriveGiB - $candidateP95GiB
$wallFeasible = $candidateP95Hours -le [double]$plan.budgetFeasibility.maximumTechnicalWallClockHours
$storageFeasible = $candidateHeadroomGiB -ge [double]$plan.budgetFeasibility.minimumOutputDriveHeadroomAfterProjectionGiB
$totalPlanOperations = [long](($samples | Measure-Object -Property planOperationCount -Sum).Sum)
$totalRepairOperations = [long](($samples | Measure-Object -Property repairOperationCount -Sum).Sum)
$totalBudgetExceededOperations = [long](($samples | Measure-Object -Property budgetExceededOperationCount -Sum).Sum)
$totalNoPathPlans = [long](($samples | Measure-Object -Property noPathPlanCount -Sum).Sum)
$totalBudgetExceededPlans = [long](($samples | Measure-Object -Property budgetExceededPlanCount -Sum).Sum)
$totalInvalidPlans = [long](($samples | Measure-Object -Property invalidPlanCount -Sum).Sum)
$totalFailedPlans = [long](($samples | Measure-Object -Property failedPlanCount -Sum).Sum)
$budgetAmendmentDecisionRequired = $totalBudgetExceededOperations -gt 0
$technicalBudgetFeasible = $wallFeasible -and $storageFeasible -and $pilotManifest.technicalInvalidityCount -eq 0 -and @($pilotManifest.measuredCampaigns | Where-Object hardTimedOut -eq $true).Count -eq 0
$budgetFeasibility = [ordered]@{
    schemaVersion = 1
    analysisId = 'gate12-budget-feasibility-v1'
    generatedAt = (Get-Date).ToString('o')
    projectionMethod = $plan.budgetFeasibility.projectionMethod
    campaignCostRows = $campaignCostRows
    observed = [ordered]@{
        measuredCampaignCount = $campaignCostRows.Count
        measuredUnityProcessCount = $samples.Count
        medianWallSecondsPerProcess = $medianWallSeconds
        p95WallSecondsPerProcess = $p95WallSeconds
        medianBytesPerProcess = $medianBytes
        p95BytesPerProcess = $p95Bytes
    }
    candidateProjection = [ordered]@{
        unityProcessCount = $candidateProcessCount
        medianWallHours = $candidateMedianHours
        p95WallHours = $candidateP95Hours
        medianOutputGiB = $candidateMedianGiB
        p95OutputGiB = $candidateP95GiB
        outputDriveFreeGiBBeforeAnalysis = [double]$environmentEnd.freeOutputDriveGiB
        p95ProjectedHeadroomGiB = $candidateHeadroomGiB
    }
    uncappedRequiredProjection = [ordered]@{
        unityProcessCount = $requiredProcessCount
        p95WallHours = $requiredP95Hours
        p95OutputGiB = $requiredP95GiB
    }
    thresholds = [ordered]@{
        maximumTechnicalWallClockHours = $plan.budgetFeasibility.maximumTechnicalWallClockHours
        minimumOutputDriveHeadroomAfterProjectionGiB = $plan.budgetFeasibility.minimumOutputDriveHeadroomAfterProjectionGiB
    }
    operationalResults = [ordered]@{
        totalPlanOperations = $totalPlanOperations
        totalRepairOperations = $totalRepairOperations
        totalBudgetExceededOperations = $totalBudgetExceededOperations
        budgetExceededOperationRate = if (($totalPlanOperations + $totalRepairOperations) -eq 0) { 0.0 } else { $totalBudgetExceededOperations / [double]($totalPlanOperations + $totalRepairOperations) }
        totalNoPathPlans = $totalNoPathPlans
        totalBudgetExceededPlans = $totalBudgetExceededPlans
        totalInvalidPlans = $totalInvalidPlans
        totalFailedPlans = $totalFailedPlans
        budgetAmendmentDecisionRequired = $budgetAmendmentDecisionRequired
    }
    checks = [ordered]@{
        candidateP95WallWithin168Hours = $wallFeasible
        candidateStorageLeaves20GiB = $storageFeasible
        noCampaignHardTimeout = @($pilotManifest.measuredCampaigns | Where-Object hardTimedOut -eq $true).Count -eq 0
        noTechnicalInvalidity = $pilotManifest.technicalInvalidityCount -eq 0
    }
    technicalBudgetFeasible = $technicalBudgetFeasible
    userTimeOrFinancialBudgetStatus = $plan.budgetFeasibility.userTimeOrFinancialBudgetStatus
    formalCampaignStarted = $false
    completed = $true
}
Write-Utf8NoBomJson -Path $analysisPaths.budget -Value $budgetFeasibility -Depth 20

$overallReadiness = if ($precisionBlocked) { 'blocked-precision-cap-versioned-amendment-required' } elseif (-not $technicalBudgetFeasible) { 'blocked-technical-budget' } elseif ($budgetAmendmentDecisionRequired) { 'blocked-budget-outcome-review' } else { 'candidate-ready-but-gate13-not-authorized' }
$reportBuilder = New-Object System.Text.StringBuilder
[void]$reportBuilder.AppendLine('# Gate 12 Pilot Validation Report')
[void]$reportBuilder.AppendLine()
[void]$reportBuilder.AppendLine('## Material Passport')
[void]$reportBuilder.AppendLine()
[void]$reportBuilder.AppendLine('- Origin Skill: experiment-agent')
[void]$reportBuilder.AppendLine('- Origin Mode: validate')
[void]$reportBuilder.AppendLine(('- Origin Date: {0}' -f (Get-Date).ToString('o')))
[void]$reportBuilder.AppendLine('- Verification Status: ANALYZED')
[void]$reportBuilder.AppendLine('- Version Label: gate12_validation_v1')
[void]$reportBuilder.AppendLine()
[void]$reportBuilder.AppendLine('## Validation Result')
[void]$reportBuilder.AppendLine()
[void]$reportBuilder.AppendLine(('- Pilot samples: {0} measured + {1} excluded warm-up Unity processes.' -f $samples.Count, $pilotManifest.warmupUnityProcessCount))
[void]$reportBuilder.AppendLine(('- Technical invalidities: {0}; auto retries: {1}; formal samples: 0.' -f $pilotManifest.technicalInvalidityCount, $pilotManifest.autoRetryCount))
[void]$reportBuilder.AppendLine(('- Retained bundle before/after aggregate: `{0}` / `{1}`.' -f $pilotManifest.bundleBefore.orderedAggregateSha256, $pilotManifest.bundleAfter.orderedAggregateSha256))
[void]$reportBuilder.AppendLine(('- Gate 13 readiness: `{0}`; authorization remains absent.' -f $overallReadiness))
[void]$reportBuilder.AppendLine()
[void]$reportBuilder.AppendLine('## Candidate n_formal')
[void]$reportBuilder.AppendLine()
[void]$reportBuilder.AppendLine('| Family | sigma_log | Governing cell | n_raw | Required n | Candidate n | Status |')
[void]$reportBuilder.AppendLine('|---|---:|---|---:|---:|---:|---|')
foreach ($row in $candidateRows) {
    [void]$reportBuilder.AppendLine(('| {0} | {1:G17} | `{2}` | {3} | {4} | {5} | {6} |' -f $row.familyId, [double]$row.sigmaLog, $row.governingCellId, $row.nRaw, $row.requiredNFormal, $row.candidateNFormal, $row.precisionStatus))
}
[void]$reportBuilder.AppendLine()
[void]$reportBuilder.AppendLine('## Runtime, Storage, and Algorithmic Outcomes')
[void]$reportBuilder.AppendLine()
[void]$reportBuilder.AppendLine(('- Candidate process projection: {0:N0} Unity processes; p95 wall projection {1:N2} h; p95 storage projection {2:N3} GiB; projected free-space headroom {3:N2} GiB.' -f $candidateProcessCount, $candidateP95Hours, $candidateP95GiB, $candidateHeadroomGiB))
[void]$reportBuilder.AppendLine(('- Uncapped precision projection: {0:N0} processes, {1:N2} h at pilot p95 process cost.' -f $requiredProcessCount, $requiredP95Hours))
[void]$reportBuilder.AppendLine(('- Budget-exceeded operations: {0}; NoPath plans: {1}; budget-exceeded plans: {2}; invalid plans: {3}; failed plans: {4}.' -f $totalBudgetExceededOperations, $totalNoPathPlans, $totalBudgetExceededPlans, $totalInvalidPlans, $totalFailedPlans))
[void]$reportBuilder.AppendLine()
[void]$reportBuilder.AppendLine('## Statistical Fallacy Scan')
[void]$reportBuilder.AppendLine()
[void]$reportBuilder.AppendLine('- Coverage: 11/11 types checked.')
[void]$reportBuilder.AppendLine('- Simpson paradox: NOTE — no aggregate factor-effect inference is made; noise remains cell-stratified.')
[void]$reportBuilder.AppendLine('- Ecological fallacy: NOTE — process samples are not used for claims about agents as independent experimental units.')
[void]$reportBuilder.AppendLine('- Berkson/selection bias: CAUTION — the four-row pilot is purposive and supports noise/cost estimation only, not population-wide performance effects.')
[void]$reportBuilder.AppendLine('- Collider bias: NOTE — no covariate-adjusted causal model is fitted.')
[void]$reportBuilder.AppendLine('- Base-rate neglect: NOTE — no diagnostic classification claim is made.')
[void]$reportBuilder.AppendLine('- Regression to the mean: NOTE — rows were frozen before timing observations and were not selected for extreme pilot timing.')
[void]$reportBuilder.AppendLine('- Survivorship bias: NOTE — all algorithmic failures remain in denominators; technical invalidities are separately reported.')
[void]$reportBuilder.AppendLine('- Look-elsewhere effect: NOTE — P1–P4 and the precision endpoint were frozen before implementation.')
[void]$reportBuilder.AppendLine('- Garden of forking paths: NOTE — subset, transform, worst-cell estimator, cap, and stopping rules were pre-audited and hash-frozen.')
[void]$reportBuilder.AppendLine('- Correlation-versus-causation: NOTE — no causal conclusion is drawn from pilot timing.')
[void]$reportBuilder.AppendLine('- Reverse causality: NOTE — not applicable to the fixed execution protocol; no directional observational claim is made.')
[void]$reportBuilder.AppendLine()
[void]$reportBuilder.AppendLine('## Reproducibility Boundary')
[void]$reportBuilder.AppendLine()
[void]$reportBuilder.AppendLine('Timing is environment-sensitive and is therefore not judged by exact timing replay. Structural identities, hashes, Williams balance, process isolation, sample counts, formula vectors, and retained-bundle preservation are deterministically verified. A separate Gate 13 authorization is still required; this report does not launch it.')
Write-Utf8NoBomText -Path $analysisPaths.report -Value $reportBuilder.ToString()

$analysisManifest = [ordered]@{
    schemaVersion = 1
    analysisManifestId = 'gate12-analysis-manifest-v1'
    generatedAt = (Get-Date).ToString('o')
    pilotManifestRelativePath = Get-ProjectRelativePath $pilotManifestPath
    pilotManifestSha256 = Get-Gate12LowerSha256 $pilotManifestPath
    analyzerRelativePath = Get-ProjectRelativePath $MyInvocation.MyCommand.Path
    analyzerSha256 = Get-Gate12LowerSha256 $MyInvocation.MyCommand.Path
    analysisModuleRelativePath = Get-ProjectRelativePath $modulePath
    analysisModuleSha256 = Get-Gate12LowerSha256 $modulePath
    measuredSampleCount = $samples.Count
    warmupSampleCount = $warmupManifest.sampleCount
    warmupExcluded = $true
    technicalInvalidityCount = 0
    noiseAnalysisFile = 'noise-analysis.json'
    noiseAnalysisSha256 = Get-Gate12LowerSha256 $analysisPaths.noise
    candidateSampleSizesFile = 'candidate-sample-sizes.json'
    candidateSampleSizesSha256 = Get-Gate12LowerSha256 $analysisPaths.candidates
    budgetFeasibilityFile = 'budget-feasibility.json'
    budgetFeasibilitySha256 = Get-Gate12LowerSha256 $analysisPaths.budget
    validationReportFile = 'Gate12_Pilot_Validation_Report.md'
    validationReportSha256 = Get-Gate12LowerSha256 $analysisPaths.report
    gate13Readiness = $overallReadiness
    gate13Authorized = $false
    formalCampaignStarted = $false
    completed = $true
}
Write-Utf8NoBomJson -Path $analysisPaths.manifest -Value $analysisManifest -Depth 16

$result = [ordered]@{
    passed = $true
    pilotRoot = $PilotRoot
    measuredSampleCount = $samples.Count
    familyCandidates = $candidateRows
    candidateFormalProcessCount = $candidateProcessCount
    candidateP95WallHours = $candidateP95Hours
    candidateP95OutputGiB = $candidateP95GiB
    gate13Readiness = $overallReadiness
    gate13Authorized = $false
    formalCampaignStarted = $false
    analysisManifestPath = $analysisPaths.manifest
    analysisManifestSha256 = Get-Gate12LowerSha256 $analysisPaths.manifest
}
$result | ConvertTo-Json -Depth 10
Write-Host 'Gate 12 pilot analysis completed; Gate 13 remains unstarted and unauthorized.' -ForegroundColor Green
exit 0
