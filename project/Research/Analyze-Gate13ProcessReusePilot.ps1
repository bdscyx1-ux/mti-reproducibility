[CmdletBinding()]
param(
    [string]$ProjectPath = (Split-Path -Parent $PSScriptRoot),
    [string]$PilotRoot,
    [string]$PilotPlanPath,
    [string]$ProvenancePath
)

$ErrorActionPreference = 'Stop'
$ProjectPath = [System.IO.Path]::GetFullPath($ProjectPath)
if ([string]::IsNullOrWhiteSpace($PilotRoot)) { $PilotRoot = Join-Path $ProjectPath 'Research\PilotRuns\Gate13_ProcessReuse\v1' }
if ([string]::IsNullOrWhiteSpace($PilotPlanPath)) { $PilotPlanPath = Join-Path $ProjectPath 'Research\Gate13_ProcessReuse_Pilot_Plan.v1.json' }
if ([string]::IsNullOrWhiteSpace($ProvenancePath)) { $ProvenancePath = Join-Path $ProjectPath 'Research\Gate13_ProcessReuse_Provenance.v4.json' }
$PilotRoot = [System.IO.Path]::GetFullPath($PilotRoot)
$modulePath = Join-Path $PSScriptRoot 'Gate13ProcessReusePreparation.psm1'
Import-Module $modulePath -Force
$plan = Read-G13R2Json -Path $PilotPlanPath
$provenance = Read-G13R2Json -Path $ProvenancePath
$reservedFormalRoot = Join-Path $ProjectPath 'Research\FormalRuns\Gate13_ProcessReuse\v1'
if (Test-Path -LiteralPath $reservedFormalRoot) { throw 'Reserved process-reuse formal root exists during pilot analysis.' }

function Get-SampleStandardDeviation([double[]]$Values) {
    if ($Values.Count -lt 2) { throw 'Sample standard deviation requires at least two values.' }
    $mean = [double](($Values | Measure-Object -Average).Average)
    $sum = 0.0
    foreach ($value in $Values) { $sum += [math]::Pow($value - $mean, 2.0) }
    return [math]::Sqrt($sum / ($Values.Count - 1))
}

function Get-Median([double[]]$Values) {
    if ($Values.Count -eq 0) { throw 'Median requires values.' }
    $sorted = @($Values | Sort-Object)
    $middle = [int][math]::Floor($sorted.Count / 2)
    if ($sorted.Count % 2 -eq 1) { return [double]$sorted[$middle] }
    return ([double]$sorted[$middle - 1] + [double]$sorted[$middle]) / 2.0
}

function Get-P95([double[]]$Values) {
    if ($Values.Count -eq 0) { throw 'P95 requires values.' }
    $sorted = @($Values | Sort-Object)
    $index = [math]::Max(0, [int][math]::Ceiling($sorted.Count * 0.95) - 1)
    return [double]$sorted[$index]
}

function Get-PearsonCorrelation([double[]]$X, [double[]]$Y) {
    if ($X.Count -ne $Y.Count -or $X.Count -lt 2) { throw 'Correlation requires equal vectors with at least two values.' }
    $meanX = [double](($X | Measure-Object -Average).Average)
    $meanY = [double](($Y | Measure-Object -Average).Average)
    $cross = 0.0
    $sumX = 0.0
    $sumY = 0.0
    for ($index = 0; $index -lt $X.Count; $index++) {
        $dx = [double]$X[$index] - $meanX
        $dy = [double]$Y[$index] - $meanY
        $cross += $dx * $dy
        $sumX += $dx * $dx
        $sumY += $dy * $dy
    }
    if ($sumX -le 0.0 -or $sumY -le 0.0) { return $null }
    return [double]($cross / [math]::Sqrt($sumX * $sumY))
}

function Get-AverageRanks([double[]]$Values) {
    $ranks = New-Object 'double[]' $Values.Count
    $rankItems = @(for ($index = 0; $index -lt $Values.Count; $index++) { [pscustomobject]@{ index = $index; value = [double]$Values[$index] } })
    $ordered = @($rankItems | Sort-Object value, index)
    $start = 0
    while ($start -lt $ordered.Count) {
        $end = $start
        while ($end + 1 -lt $ordered.Count -and [double]$ordered[$end + 1].value -eq [double]$ordered[$start].value) { $end++ }
        $averageRank = (($start + 1) + ($end + 1)) / 2.0
        for ($cursor = $start; $cursor -le $end; $cursor++) { $ranks[[int]$ordered[$cursor].index] = $averageRank }
        $start = $end + 1
    }
    return [double[]]$ranks
}

function Get-SpearmanCorrelation([double[]]$X, [double[]]$Y) {
    return Get-PearsonCorrelation -X (Get-AverageRanks -Values $X) -Y (Get-AverageRanks -Values $Y)
}

function Get-DirectoryBytes([string]$Path) {
    $measurement = Get-ChildItem -LiteralPath $Path -Recurse -File -Force | Measure-Object -Property Length -Sum
    if ($null -eq $measurement.Sum) { return [int64]0 }
    return [int64]$measurement.Sum
}

function Convert-AlgorithmSlug([string]$Algorithm) { return Get-G13R2AlgorithmSlug -AlgorithmId $Algorithm }

$coldReferenceMap = @{}
$coldReferenceFiles = @(Get-ChildItem -LiteralPath (Join-Path $PilotRoot 'cold-reference') -Recurse -Filter 'workload-result.json' -File)
foreach ($file in $coldReferenceFiles) {
    $result = Read-G13R2Json -Path $file.FullName
    $key = '{0}|{1}' -f [string]$result.scenarioId, [string]$result.algorithmId
    if ($coldReferenceMap.ContainsKey($key)) { throw "Duplicate fresh cold reference: $key" }
    $coldReferenceMap[$key] = [pscustomobject][ordered]@{ path = $file.FullName; result = $result; sha256 = Get-G13R2LowerSha256 -Path $file.FullName }
}
if ($coldReferenceMap.Count -ne 8) { throw "Fresh cold reference count is $($coldReferenceMap.Count); expected 8." }

$blockManifestFiles = @(Get-ChildItem -LiteralPath (Join-Path $PilotRoot 'measured') -Recurse -Filter 'block-manifest.json' -File | Sort-Object FullName)
if ($blockManifestFiles.Count -ne 36) { throw "Measured block manifest count is $($blockManifestFiles.Count); expected 36." }
$samples = New-Object System.Collections.Generic.List[object]
$blocks = New-Object System.Collections.Generic.List[object]
$structuralComparisons = New-Object System.Collections.Generic.List[object]
$hardErrors = New-Object System.Collections.Generic.List[string]
$processIds = New-Object System.Collections.Generic.HashSet[int]
$processIdentities = New-Object System.Collections.Generic.HashSet[string]

foreach ($blockFile in $blockManifestFiles) {
    $blockDirectory = Split-Path -Parent $blockFile.FullName
    $block = Read-G13R2Json -Path $blockFile.FullName
    if ($block.completed -ne $true -or $block.formalCampaign -ne $false -or $block.oneBlockPerUnityProcess -ne $true -or $block.oneSamplePerAlgorithmPerProcess -ne $true -or $block.allSamplesShareProcessId -ne $true -or $block.orderMatchesBlockPlan -ne $true) { $hardErrors.Add("Invalid block manifest: $($blockFile.FullName)") }
    if ([int]$block.completedSampleCount -ne @($block.samples).Count -or [int]$block.expectedSampleCount -ne @($block.samples).Count) { $hardErrors.Add("Incomplete block: $($block.blockId)") }
    [void]$processIds.Add([int]$block.processId)
    [void]$processIdentities.Add(('{0}|{1}' -f [int]$block.processId, [string]$block.processStartTimeUtc))
    $first = @($block.samples | Sort-Object position | Select-Object -First 1)[0]
    $last = @($block.samples | Sort-Object position | Select-Object -Last 1)[0]
    $workingGrowth = [int64]$last.workingSetAfterBytes - [int64]$first.workingSetBeforeBytes
    $managedGrowth = [int64]$last.managedMemoryAfterBytes - [int64]$first.managedMemoryBeforeBytes
    if ($workingGrowth -gt [int64]$plan.hardMemoryLimits.maximumWorkingSetGrowthBytesPerBlock) { $hardErrors.Add("Working-set hard limit exceeded: $($block.blockId), growth=$workingGrowth") }
    if ($managedGrowth -gt [int64]$plan.hardMemoryLimits.maximumManagedMemoryGrowthBytesPerBlock) { $hardErrors.Add("Managed-memory hard limit exceeded: $($block.blockId), growth=$managedGrowth") }
    $blocks.Add([pscustomobject][ordered]@{
        blockId = [string]$block.blockId
        campaignId = [string]$block.campaignId
        comparisonCohortId = [string]$block.comparisonCohortId
        block = [int]$block.block
        processId = [int]$block.processId
        processStartTimeUtc = [string]$block.processStartTimeUtc
        sampleCount = @($block.samples).Count
        workingSetGrowthBytes = $workingGrowth
        managedMemoryGrowthBytes = $managedGrowth
        manifestRelativePath = Get-G13R2ProjectRelativePath -ProjectPath $ProjectPath -FullPath $blockFile.FullName
        manifestSha256 = Get-G13R2LowerSha256 -Path $blockFile.FullName
    })
    foreach ($child in @($block.samples | Sort-Object position)) {
        $resultPath = Join-Path $blockDirectory ([string]$child.workloadResultRelativePath).Replace('/', '\')
        $manifestPath = Join-Path $blockDirectory ([string]$child.manifestRelativePath).Replace('/', '\')
        $sampleSummaryPath = Join-Path $blockDirectory ([string]$child.summaryRelativePath).Replace('/', '\')
        if (-not (Test-Path -LiteralPath $resultPath -PathType Leaf) -or -not (Test-Path -LiteralPath $manifestPath -PathType Leaf) -or -not (Test-Path -LiteralPath $sampleSummaryPath -PathType Leaf)) { $hardErrors.Add("Missing child artifact: $($child.runId)"); continue }
        if ((Get-G13R2LowerSha256 -Path $resultPath) -ne [string]$child.workloadResultSha256 -or (Get-G13R2LowerSha256 -Path $manifestPath) -ne [string]$child.manifestSha256 -or (Get-G13R2LowerSha256 -Path $sampleSummaryPath) -ne [string]$child.summarySha256) { $hardErrors.Add("Child hash mismatch: $($child.runId)") }
        $result = Read-G13R2Json -Path $resultPath
        $manifest = Read-G13R2Json -Path $manifestPath
        $sampleSummary = Read-G13R2Json -Path $sampleSummaryPath
        if ($sampleSummary.completed -ne $true -or $sampleSummary.formalCampaign -ne $false -or [string]$sampleSummary.runId -ne [string]$child.runId -or [string]$sampleSummary.manifestSha256 -ne [string]$child.manifestSha256 -or [string]$sampleSummary.workloadResultSha256 -ne [string]$child.workloadResultSha256) { $hardErrors.Add("Invalid sample completion summary: $($child.runId)") }
        if ([int]$manifest.schemaVersion -ne 3 -or $manifest.executionDesignId -ne 'one-fresh-unity-process-per-williams-block-v1' -or $manifest.completed -ne $true -or $manifest.formalCampaign -ne $false -or $manifest.forcedGcBoundaryCompleted -ne $true -or $manifest.plannerResetCompleted -ne $true -or $manifest.loggerDisposed -ne $true) { $hardErrors.Add("Invalid process-reuse sample manifest: $($child.runId)") }
        if ([int]$manifest.telemetryBefore.processId -ne [int]$block.processId -or [int]$manifest.telemetryAfter.processId -ne [int]$block.processId) { $hardErrors.Add("Mixed process ID: $($child.runId)") }
        if ([double]$manifest.telemetryAfter.processAgeMilliseconds -lt [double]$manifest.telemetryBefore.processAgeMilliseconds) { $hardErrors.Add("Process age reversed: $($child.runId)") }
        foreach ($name in @('workingSetBytes', 'privateMemoryBytes', 'managedMemoryBytes')) {
            if ([int64]$manifest.telemetryBefore.$name -le 0 -or [int64]$manifest.telemetryAfter.$name -le 0) { $hardErrors.Add("Non-positive telemetry ${name}: $($child.runId)") }
        }
        foreach ($generation in 0..2) {
            $beforeCount = [int]$manifest.telemetryBefore.("gcCollectionCount$generation")
            $afterCount = [int]$manifest.telemetryAfter.("gcCollectionCount$generation")
            if ($afterCount -lt $beforeCount) { $hardErrors.Add("GC counter reversed: $($child.runId), generation=$generation") }
        }
        $operationsPath = Join-Path (Split-Path -Parent $manifestPath) ([string]$manifest.operationsJsonlFile)
        $lineCount = if (Test-Path -LiteralPath $operationsPath -PathType Leaf) { @(Get-Content -LiteralPath $operationsPath).Count } else { -1 }
        if ([long]$manifest.enqueuedLogRecords -ne [long]$manifest.writtenLogRecords -or [long]$manifest.writtenLogRecords -ne $lineCount) { $hardErrors.Add("Logger count mismatch: $($child.runId)") }
        $referenceKey = '{0}|{1}' -f [string]$result.scenarioId, [string]$result.algorithmId
        if (-not $coldReferenceMap.ContainsKey($referenceKey)) { $hardErrors.Add("Missing structural reference: $referenceKey"); continue }
        $comparison = Compare-G13R2StructuralResults -Reference $coldReferenceMap[$referenceKey].result -Candidate $result
        if (-not $comparison.passed) { $hardErrors.Add("Structural mismatch: $($child.runId)") }
        $structuralComparisons.Add([pscustomobject][ordered]@{
            runId = [string]$child.runId
            referenceKey = $referenceKey
            referenceResultRelativePath = Get-G13R2ProjectRelativePath -ProjectPath $ProjectPath -FullPath $coldReferenceMap[$referenceKey].path
            referenceProjectionSha256 = [string]$comparison.referenceProjectionSha256
            candidateProjectionSha256 = [string]$comparison.candidateProjectionSha256
            passed = [bool]$comparison.passed
        })
        $endpoint = [double]$result.dynamicHandlingMillisecondsPerScheduledEvent
        if ([double]::IsNaN($endpoint) -or [double]::IsInfinity($endpoint) -or $endpoint -le 0) { $hardErrors.Add("Primary endpoint is non-positive/non-finite: $($child.runId)") }
        $plannerElapsed = [double]$result.totalPlannerElapsedMilliseconds
        if ([double]::IsNaN($plannerElapsed) -or [double]::IsInfinity($plannerElapsed) -or $plannerElapsed -lt 0) { $hardErrors.Add("Planner elapsed time is negative/non-finite: $($child.runId)") }
        $samples.Add([pscustomobject][ordered]@{
            blockId = [string]$block.blockId
            campaignId = [string]$block.campaignId
            scenarioId = [string]$result.scenarioId
            comparisonCohortId = [string]$result.comparisonCohortId
            algorithmId = [string]$result.algorithmId
            position = [int]$child.position
            predecessorAlgorithmId = [string]$child.predecessorAlgorithmId
            processId = [int]$child.processId
            processAgeBeforeMilliseconds = [double]$child.processAgeBeforeMilliseconds
            processAgeAfterMilliseconds = [double]$child.processAgeAfterMilliseconds
            workingSetDeltaBytes = [int64]$child.workingSetAfterBytes - [int64]$child.workingSetBeforeBytes
            privateMemoryDeltaBytes = [int64]$child.privateMemoryAfterBytes - [int64]$child.privateMemoryBeforeBytes
            managedMemoryDeltaBytes = [int64]$child.managedMemoryAfterBytes - [int64]$child.managedMemoryBeforeBytes
            gcCollectionDelta0 = [int]$child.gcCollectionDelta0
            gcCollectionDelta1 = [int]$child.gcCollectionDelta1
            gcCollectionDelta2 = [int]$child.gcCollectionDelta2
            totalPlannerElapsedMilliseconds = $plannerElapsed
            dynamicHandlingMillisecondsPerScheduledEvent = $endpoint
            logPrimaryEndpoint = [math]::Log($endpoint)
            resultRelativePath = Get-G13R2ProjectRelativePath -ProjectPath $ProjectPath -FullPath $resultPath
            resultSha256 = Get-G13R2LowerSha256 -Path $resultPath
        })
    }
}

if ($processIds.Count -ne 36 -or $processIdentities.Count -ne 36) { $hardErrors.Add("Measured block process identity count mismatch: PID=$($processIds.Count), identity=$($processIdentities.Count), expected=36") }
if ($samples.Count -ne 96) { $hardErrors.Add("Measured sample count is $($samples.Count); expected 96.") }
if ($structuralComparisons.Count -ne 96) { $hardErrors.Add("Structural comparison count is $($structuralComparisons.Count); expected 96.") }

$balanceRows = New-Object System.Collections.Generic.List[object]
foreach ($group in @($samples | Group-Object campaignId, algorithmId, position)) {
    $first = $group.Group[0]
    $balanceRows.Add([pscustomobject][ordered]@{ campaignId = $first.campaignId; algorithmId = $first.algorithmId; position = $first.position; count = $group.Count })
}
foreach ($campaign in @($plan.measuredCampaigns)) {
    $algorithmCount = @($campaign.algorithms).Count
    $expectedPerPosition = [int]$campaign.blocks / $algorithmCount
    foreach ($algorithm in @($campaign.algorithms)) {
        foreach ($position in 1..$algorithmCount) {
            $count = @($samples | Where-Object { $_.campaignId -eq $campaign.campaignId -and $_.algorithmId -eq $algorithm -and $_.position -eq $position }).Count
            if ($count -ne $expectedPerPosition) { $hardErrors.Add("Position balance mismatch: $($campaign.campaignId)/$algorithm/p$position=$count expected=$expectedPerPosition") }
        }
    }
    $predecessorCounts = @($samples | Where-Object { $_.campaignId -eq $campaign.campaignId -and $_.predecessorAlgorithmId -ne 'NONE' } | Group-Object predecessorAlgorithmId, algorithmId)
    foreach ($pair in $predecessorCounts) {
        if ($pair.Count -ne $expectedPerPosition) { $hardErrors.Add("Predecessor balance mismatch: $($campaign.campaignId)/$($pair.Name)=$($pair.Count) expected=$expectedPerPosition") }
    }
}

$predecessorDiagnostics = New-Object System.Collections.Generic.List[object]
foreach ($group in @($samples | Group-Object comparisonCohortId, algorithmId, predecessorAlgorithmId)) {
    $first = $group.Group[0]
    $values = [double[]]@($group.Group | ForEach-Object { [double]$_.dynamicHandlingMillisecondsPerScheduledEvent })
    $logValues = [double[]]@($group.Group | ForEach-Object { [double]$_.logPrimaryEndpoint })
    $predecessorDiagnostics.Add([pscustomobject][ordered]@{
        comparisonCohortId = [string]$first.comparisonCohortId
        algorithmId = [string]$first.algorithmId
        predecessorAlgorithmId = [string]$first.predecessorAlgorithmId
        n = $values.Count
        mean = [double](($values | Measure-Object -Average).Average)
        median = Get-Median -Values $values
        p95 = Get-P95 -Values $values
        meanLogEndpoint = [double](($logValues | Measure-Object -Average).Average)
    })
}

$associationDiagnostics = New-Object System.Collections.Generic.List[object]
foreach ($group in @($samples | Group-Object comparisonCohortId, algorithmId)) {
    $first = $group.Group[0]
    $position = [double[]]@($group.Group | ForEach-Object { [double]$_.position })
    $age = [double[]]@($group.Group | ForEach-Object { [double]$_.processAgeBeforeMilliseconds })
    $endpoint = [double[]]@($group.Group | ForEach-Object { [double]$_.logPrimaryEndpoint })
    $associationDiagnostics.Add([pscustomobject][ordered]@{
        comparisonCohortId = [string]$first.comparisonCohortId
        algorithmId = [string]$first.algorithmId
        n = $endpoint.Count
        endpointScale = 'natural-log-primary-endpoint'
        positionPearson = Get-PearsonCorrelation -X $position -Y $endpoint
        positionSpearman = Get-SpearmanCorrelation -X $position -Y $endpoint
        processAgePearson = Get-PearsonCorrelation -X $age -Y $endpoint
        processAgeSpearman = Get-SpearmanCorrelation -X $age -Y $endpoint
    })
}

$resourceDiagnostics = New-Object System.Collections.Generic.List[object]
foreach ($group in @($samples | Group-Object comparisonCohortId, algorithmId, position)) {
    $first = $group.Group[0]
    $working = [double[]]@($group.Group | ForEach-Object { [double]$_.workingSetDeltaBytes })
    $private = [double[]]@($group.Group | ForEach-Object { [double]$_.privateMemoryDeltaBytes })
    $managed = [double[]]@($group.Group | ForEach-Object { [double]$_.managedMemoryDeltaBytes })
    $resourceDiagnostics.Add([pscustomobject][ordered]@{
        comparisonCohortId = [string]$first.comparisonCohortId
        algorithmId = [string]$first.algorithmId
        position = [int]$first.position
        n = $group.Count
        workingSetDeltaMeanBytes = [double](($working | Measure-Object -Average).Average)
        workingSetDeltaMedianBytes = Get-Median -Values $working
        privateMemoryDeltaMeanBytes = [double](($private | Measure-Object -Average).Average)
        privateMemoryDeltaMedianBytes = Get-Median -Values $private
        managedMemoryDeltaMeanBytes = [double](($managed | Measure-Object -Average).Average)
        managedMemoryDeltaMedianBytes = Get-Median -Values $managed
        gcCollectionDelta0Total = [int](($group.Group | Measure-Object -Property gcCollectionDelta0 -Sum).Sum)
        gcCollectionDelta1Total = [int](($group.Group | Measure-Object -Property gcCollectionDelta1 -Sum).Sum)
        gcCollectionDelta2Total = [int](($group.Group | Measure-Object -Property gcCollectionDelta2 -Sum).Sum)
    })
}

$familyDefinitions = @(
    [pscustomobject][ordered]@{ familyId = 'P1-DL-vs-A-shared'; comparisonCohortId = 'four-algorithm-shared-goal-v1'; first = 'A*-R'; second = 'D*L' },
    [pscustomobject][ordered]@{ familyId = 'P2-DL-vs-A-hetero'; comparisonCohortId = 'per-agent-heterogeneous-goal-v1'; first = 'A*-R'; second = 'D*L' },
    [pscustomobject][ordered]@{ familyId = 'P3-IDFF-vs-CFF-shared'; comparisonCohortId = 'four-algorithm-shared-goal-v1'; first = 'C-FF'; second = 'IDFF' },
    [pscustomobject][ordered]@{ familyId = 'P4-IDFF-vs-CFF-grouped'; comparisonCohortId = 'grouped-field-heterogeneous-goal-v1'; first = 'C-FF'; second = 'IDFF' }
)
$familyRows = New-Object System.Collections.Generic.List[object]
$pairedCarryoverDiagnostics = New-Object System.Collections.Generic.List[object]
foreach ($family in $familyDefinitions) {
    $familySamples = @($samples | Where-Object { $_.comparisonCohortId -eq $family.comparisonCohortId -and $_.algorithmId -in @($family.first, $family.second) })
    $marginalSigmas = @()
    foreach ($algorithm in @($family.first, $family.second)) {
        $values = [double[]]@($familySamples | Where-Object algorithmId -eq $algorithm | ForEach-Object { [double]$_.logPrimaryEndpoint })
        $marginalSigmas += Get-SampleStandardDeviation -Values $values
    }
    $marginalSigma = [double]($marginalSigmas | Measure-Object -Maximum).Maximum
    $pairedDifferences = New-Object System.Collections.Generic.List[double]
    $pairedRecords = New-Object System.Collections.Generic.List[object]
    foreach ($blockGroup in @($familySamples | Group-Object blockId)) {
        $firstSample = @($blockGroup.Group | Where-Object algorithmId -eq $family.first)
        $secondSample = @($blockGroup.Group | Where-Object algorithmId -eq $family.second)
        if ($firstSample.Count -ne 1 -or $secondSample.Count -ne 1) { throw "Incomplete within-block pair: $($family.familyId)/$($blockGroup.Name)" }
        $difference = [double]$secondSample[0].logPrimaryEndpoint - [double]$firstSample[0].logPrimaryEndpoint
        $pairedDifferences.Add($difference)
        $pairedRecords.Add([pscustomobject][ordered]@{
            blockId = [string]$blockGroup.Name
            predecessorPattern = ('{0}>{1}|{2}>{3}' -f [string]$firstSample[0].predecessorAlgorithmId, [string]$family.first, [string]$secondSample[0].predecessorAlgorithmId, [string]$family.second)
            logDifference = $difference
        })
    }
    foreach ($carryoverGroup in @($pairedRecords | Group-Object predecessorPattern)) {
        $contrastValues = [double[]]@($carryoverGroup.Group | ForEach-Object { [double]$_.logDifference })
        $pairedCarryoverDiagnostics.Add([pscustomobject][ordered]@{
            familyId = [string]$family.familyId
            predecessorPattern = [string]$carryoverGroup.Name
            n = $contrastValues.Count
            meanPairedLogDifference = [double](($contrastValues | Measure-Object -Average).Average)
            standardDeviation = if ($contrastValues.Count -ge 2) { Get-SampleStandardDeviation -Values $contrastValues } else { $null }
            estimable = $contrastValues.Count -ge 2
        })
    }
    $pairedSigma = Get-SampleStandardDeviation -Values ([double[]]$pairedDifferences.ToArray())
    $marginalCandidate = Get-G13R2SampleSizeCandidate -SigmaLog $marginalSigma
    $pairedCandidate = Get-G13R2SampleSizeCandidate -SigmaLog $pairedSigma
    $required = [long][math]::Max([long]$marginalCandidate.requiredNFormal, [long]$pairedCandidate.requiredNFormal)
    $candidate = [long][math]::Min(148, $required)
    $familyRows.Add([pscustomobject][ordered]@{
        familyId = [string]$family.familyId
        comparisonCohortId = [string]$family.comparisonCohortId
        contrast = "$($family.second)-vs-$($family.first)"
        independentBlockCount = $pairedDifferences.Count
        marginalSigmaLog = $marginalSigma
        marginal = $marginalCandidate
        pairedLogDifferenceSigma = $pairedSigma
        paired = $pairedCandidate
        conservativeRequiredNFormal = $required
        candidateNFormal = $candidate
        overCap = $required -gt 148
        scheduledNFormal = $candidate
        harmonizationReason = 'none'
    })
}
$p1 = @($familyRows | Where-Object familyId -eq 'P1-DL-vs-A-shared')[0]
$p3 = @($familyRows | Where-Object familyId -eq 'P3-IDFF-vs-CFF-shared')[0]
$sharedScheduled = [long][math]::Max([long]$p1.candidateNFormal, [long]$p3.candidateNFormal)
$p1.scheduledNFormal = $sharedScheduled
$p3.scheduledNFormal = $sharedScheduled
$p1.harmonizationReason = 'shared-four-algorithm-cohort-max-p1-p3-complete-williams-cycles-v1'
$p3.harmonizationReason = 'shared-four-algorithm-cohort-max-p1-p3-complete-williams-cycles-v1'
if (@($familyRows | Where-Object overCap).Count -gt 0) { $hardErrors.Add('At least one conservative process-reuse sample-size requirement exceeds cap 148.') }

$positionDiagnostics = New-Object System.Collections.Generic.List[object]
foreach ($group in @($samples | Group-Object comparisonCohortId, algorithmId, position)) {
    $first = $group.Group[0]
    $values = [double[]]@($group.Group | ForEach-Object dynamicHandlingMillisecondsPerScheduledEvent)
    $positionDiagnostics.Add([pscustomobject][ordered]@{
        comparisonCohortId = $first.comparisonCohortId
        algorithmId = $first.algorithmId
        position = $first.position
        n = $values.Count
        mean = [double](($values | Measure-Object -Average).Average)
        median = Get-Median -Values $values
        p95 = Get-P95 -Values $values
    })
}

$blockSummaryFiles = @(Get-ChildItem -LiteralPath (Join-Path $PilotRoot 'measured') -Recurse -Filter '*.summary.json' -File | Where-Object { $_.Name -like 'b*.summary.json' })
$blockPerformance = New-Object System.Collections.Generic.List[object]
foreach ($file in $blockSummaryFiles) {
    $summary = Read-G13R2Json -Path $file.FullName
    $blockRecord = @($blocks | Where-Object blockId -eq ([string]$summary.blockId))
    if ($blockRecord.Count -ne 1) { $hardErrors.Add("Block wrapper summary cannot be joined uniquely: $($summary.blockId)"); continue }
    $blockSamples = @($samples | Where-Object blockId -eq ([string]$summary.blockId))
    $plannerMilliseconds = [double](($blockSamples | Measure-Object -Property totalPlannerElapsedMilliseconds -Sum).Sum)
    $wallMilliseconds = 1000.0 * [double]$summary.wallSeconds
    $outputDirectory = [System.IO.Path]::GetFullPath([string]$summary.outputDirectory)
    $pilotPrefix = $PilotRoot.TrimEnd('\') + '\'
    if (-not $outputDirectory.StartsWith($pilotPrefix, [System.StringComparison]::OrdinalIgnoreCase)) { $hardErrors.Add("Block summary output escapes pilot root: $($summary.blockId)"); continue }
    $blockPerformance.Add([pscustomobject][ordered]@{
        blockId = [string]$summary.blockId
        comparisonCohortId = [string]$blockRecord[0].comparisonCohortId
        wallSeconds = [double]$summary.wallSeconds
        plannerMilliseconds = $plannerMilliseconds
        nonPlannerOverheadMilliseconds = $wallMilliseconds - $plannerMilliseconds
        startupAmortizationRatioWallToPlanner = if ($plannerMilliseconds -gt 0) { $wallMilliseconds / $plannerMilliseconds } else { $null }
        rawBytes = [int64](Get-DirectoryBytes -Path $outputDirectory)
    })
}
if ($blockPerformance.Count -ne 36) { $hardErrors.Add("Measured block wrapper summary count is $($blockPerformance.Count); expected 36.") }
$wallSeconds = [double[]]@($blockPerformance | ForEach-Object { [double]$_.wallSeconds })
$blockBytes = [double[]]@($blockPerformance | ForEach-Object { [double]$_.rawBytes })
$medianWall = Get-Median -Values $wallSeconds
$p95Wall = Get-P95 -Values $wallSeconds
$medianBytes = Get-Median -Values $blockBytes
$p95Bytes = Get-P95 -Values $blockBytes
$candidateSchedule = @(
    [pscustomobject][ordered]@{ comparisonCohortId = 'four-algorithm-shared-goal-v1'; campaignCount = 32; blockCountPerCampaign = [int]$sharedScheduled; algorithmCount = 4 },
    [pscustomobject][ordered]@{ comparisonCohortId = 'per-agent-heterogeneous-goal-v1'; campaignCount = 21; blockCountPerCampaign = [int](@($familyRows | Where-Object familyId -eq 'P2-DL-vs-A-hetero')[0].scheduledNFormal); algorithmCount = 2 },
    [pscustomobject][ordered]@{ comparisonCohortId = 'grouped-field-heterogeneous-goal-v1'; campaignCount = 21; blockCountPerCampaign = [int](@($familyRows | Where-Object familyId -eq 'P4-IDFF-vs-CFF-grouped')[0].scheduledNFormal); algorithmCount = 2 }
)
$cohortBudgetRows = New-Object System.Collections.Generic.List[object]
$candidateBlockProcessCount = 0L
$candidateAlgorithmSampleCount = 0L
$candidateMedianWallSeconds = 0.0
$candidateP95WallSeconds = 0.0
$candidateMedianRawBytes = 0L
$candidateP95RawBytes = 0L
foreach ($cohort in $candidateSchedule) {
    $performance = @($blockPerformance | Where-Object comparisonCohortId -eq $cohort.comparisonCohortId)
    $cohortWalls = [double[]]@($performance | ForEach-Object { [double]$_.wallSeconds })
    $cohortBytes = [double[]]@($performance | ForEach-Object { [double]$_.rawBytes })
    $processCount = [long]$cohort.campaignCount * [long]$cohort.blockCountPerCampaign
    $sampleCount = $processCount * [long]$cohort.algorithmCount
    $cohortMedianWall = Get-Median -Values $cohortWalls
    $cohortP95Wall = Get-P95 -Values $cohortWalls
    $cohortMedianBytes = Get-Median -Values $cohortBytes
    $cohortP95Bytes = Get-P95 -Values $cohortBytes
    $candidateBlockProcessCount += $processCount
    $candidateAlgorithmSampleCount += $sampleCount
    $candidateMedianWallSeconds += $processCount * $cohortMedianWall
    $candidateP95WallSeconds += $processCount * $cohortP95Wall
    $candidateMedianRawBytes += [long][math]::Ceiling($processCount * $cohortMedianBytes)
    $candidateP95RawBytes += [long][math]::Ceiling($processCount * $cohortP95Bytes)
    $cohortBudgetRows.Add([pscustomobject][ordered]@{
        comparisonCohortId = [string]$cohort.comparisonCohortId
        pilotBlockCount = $performance.Count
        formalCampaignCount = [int]$cohort.campaignCount
        candidateBlocksPerCampaign = [int]$cohort.blockCountPerCampaign
        candidateBlockProcessCount = $processCount
        candidateAlgorithmSampleCount = $sampleCount
        medianBlockWallSeconds = $cohortMedianWall
        p95BlockWallSeconds = $cohortP95Wall
        medianBlockRawBytes = $cohortMedianBytes
        p95BlockRawBytes = $cohortP95Bytes
    })
}
$budget = [ordered]@{
    projectionKind = 'process-reuse-block-process-observed-pilot-projection-v1'
    measuredBlockProcessCount = 36
    cohortProjections = $cohortBudgetRows.ToArray()
    candidateFormalBlockProcessCount = $candidateBlockProcessCount
    candidateFormalAlgorithmSampleCount = $candidateAlgorithmSampleCount
    candidateProjectedMedianWallHours = $candidateMedianWallSeconds / 3600.0
    candidateProjectedP95WallHours = $candidateP95WallSeconds / 3600.0
    candidateProjectedMedianRawBytes = $candidateMedianRawBytes
    candidateProjectedP95RawBytes = $candidateP95RawBytes
    projectedFormalBlockProcessCountHistoricalCap148Schedule = 5864
    projectedFormalAlgorithmSampleCountHistoricalCap148Schedule = 15056
    medianBlockWallSeconds = $medianWall
    p95BlockWallSeconds = $p95Wall
    medianBlockRawBytes = $medianBytes
    p95BlockRawBytes = $p95Bytes
    projectedMedianWallHours = 5864.0 * $medianWall / 3600.0
    projectedP95WallHours = 5864.0 * $p95Wall / 3600.0
    projectedMedianRawBytes = [int64][math]::Ceiling(5864.0 * $medianBytes)
    projectedP95RawBytes = [int64][math]::Ceiling(5864.0 * $p95Bytes)
    executionAuthorizationConferred = $false
}

$structuralOutput = [ordered]@{
    schemaVersion = 1
    comparisonCount = $structuralComparisons.Count
    mismatchCount = @($structuralComparisons | Where-Object { -not $_.passed }).Count
    exactStructuralFieldPolicy = 'gate13-r2-process-reuse-specification-v1-section-7'
    freshColdReferenceCount = $coldReferenceMap.Count
    comparisons = $structuralComparisons.ToArray()
    passed = @($structuralComparisons | Where-Object { -not $_.passed }).Count -eq 0
}
$runtimeDiagnostics = [ordered]@{
    schemaVersion = 1
    measuredBlockProcessCount = $blocks.Count
    distinctProcessIdCount = $processIds.Count
    distinctProcessIdentityCount = $processIdentities.Count
    measuredSampleCount = $samples.Count
    positionBalance = $balanceRows.ToArray()
    positionEndpointDiagnostics = $positionDiagnostics.ToArray()
    predecessorEndpointDiagnostics = $predecessorDiagnostics.ToArray()
    pairedCarryoverDiagnostics = $pairedCarryoverDiagnostics.ToArray()
    positionAndProcessAgeAssociations = $associationDiagnostics.ToArray()
    gcAndMemoryDiagnosticsByAlgorithmPosition = $resourceDiagnostics.ToArray()
    blockWallAndStartupAmortization = $blockPerformance.ToArray()
    blocks = $blocks.ToArray()
    hardManagedGrowthLimitBytes = [int64]$plan.hardMemoryLimits.maximumManagedMemoryGrowthBytesPerBlock
    hardWorkingSetGrowthLimitBytes = [int64]$plan.hardMemoryLimits.maximumWorkingSetGrowthBytesPerBlock
    hardErrorCount = $hardErrors.Count
    hardErrors = $hardErrors.ToArray()
    passed = $hardErrors.Count -eq 0
}
$candidateOutput = [ordered]@{
    schemaVersion = 1
    precisionRelativeHalfWidthTarget = 0.10
    independentUnit = 'williams-block-unity-process-v1'
    withinProcessSamplesCorrelated = $true
    formula = 'max-of-marginal-and-within-block-paired-requirements-v1'
    minimumIndependentBlocks = 30
    cycleMultiple = 4
    maximumIndependentBlocks = 148
    families = $familyRows.ToArray()
    anyOverCap = @($familyRows | Where-Object overCap).Count -gt 0
    formalExecutionAuthorizationConferred = $false
}

$structuralPath = Join-Path $PilotRoot 'structural-equivalence.json'
$runtimePath = Join-Path $PilotRoot 'runtime-diagnostics.json'
$candidatePath = Join-Path $PilotRoot 'candidate-sample-sizes.json'
$budgetPath = Join-Path $PilotRoot 'budget-feasibility.json'
foreach ($path in @($structuralPath, $runtimePath, $candidatePath, $budgetPath)) { if (Test-Path -LiteralPath $path) { throw "Create-new analysis output exists: $path" } }
Write-G13R2Utf8NoBomJson -Path $structuralPath -Value $structuralOutput -Depth 30
Write-G13R2Utf8NoBomJson -Path $runtimePath -Value $runtimeDiagnostics -Depth 30
Write-G13R2Utf8NoBomJson -Path $candidatePath -Value $candidateOutput -Depth 30
Write-G13R2Utf8NoBomJson -Path $budgetPath -Value $budget -Depth 20

$executionManifestPath = Join-Path $PilotRoot 'pilot-execution-manifest.json'
if (-not (Test-Path -LiteralPath $executionManifestPath -PathType Leaf)) { throw 'Pilot execution manifest is missing.' }
$analysisManifest = [ordered]@{
    schemaVersion = 1
    manifestKind = 'gate13-r2-process-reuse-pilot-analysis-manifest-v1'
    savedAt = (Get-Date).ToString('o')
    pilotPlan = [ordered]@{ relativePath = 'Research/Gate13_ProcessReuse_Pilot_Plan.v1.json'; sha256 = Get-G13R2LowerSha256 -Path $PilotPlanPath }
    provenance = [ordered]@{ relativePath = Get-G13R2ProjectRelativePath -ProjectPath $ProjectPath -FullPath $ProvenancePath; sha256 = Get-G13R2LowerSha256 -Path $ProvenancePath }
    executionManifest = [ordered]@{ relativePath = 'pilot-execution-manifest.json'; sha256 = Get-G13R2LowerSha256 -Path $executionManifestPath }
    outputs = @(
        [ordered]@{ relativePath = 'structural-equivalence.json'; sha256 = Get-G13R2LowerSha256 -Path $structuralPath },
        [ordered]@{ relativePath = 'runtime-diagnostics.json'; sha256 = Get-G13R2LowerSha256 -Path $runtimePath },
        [ordered]@{ relativePath = 'candidate-sample-sizes.json'; sha256 = Get-G13R2LowerSha256 -Path $candidatePath },
        [ordered]@{ relativePath = 'budget-feasibility.json'; sha256 = Get-G13R2LowerSha256 -Path $budgetPath }
    )
    formalCampaign = $false
    excludedFromFormalAnalysis = $true
    processReuseFormalExecutionAuthorized = $false
    passed = $hardErrors.Count -eq 0
}
$analysisManifestPath = Join-Path $PilotRoot 'analysis-manifest.json'
Write-G13R2Utf8NoBomJson -Path $analysisManifestPath -Value $analysisManifest -Depth 20

$pilotManifest = [ordered]@{
    schemaVersion = 1
    manifestKind = 'gate13-r2-process-reuse-non-formal-pilot-manifest-v1'
    completedAt = (Get-Date).ToString('o')
    designId = 'one-fresh-unity-process-per-williams-block-v1'
    pilotPlanSha256 = Get-G13R2LowerSha256 -Path $PilotPlanPath
    provenanceSha256 = Get-G13R2LowerSha256 -Path $ProvenancePath
    executionManifestSha256 = Get-G13R2LowerSha256 -Path $executionManifestPath
    analysisManifestSha256 = Get-G13R2LowerSha256 -Path $analysisManifestPath
    measuredBlockProcessCount = $blocks.Count
    measuredSampleCount = $samples.Count
    freshColdReferenceProcessCount = $coldReferenceMap.Count
    structuralMismatchCount = [int]$structuralOutput.mismatchCount
    distinctMeasuredProcessIdCount = $processIds.Count
    candidateSampleSizes = @($familyRows | Select-Object familyId, conservativeRequiredNFormal, candidateNFormal, scheduledNFormal, overCap, harmonizationReason)
    budgetProjection = $budget
    formalCampaign = $false
    excludedFromFormalAnalysis = $true
    formalExecutionAuthorized = $false
    reservedFormalRootCreated = Test-Path -LiteralPath $reservedFormalRoot
    hardErrorCount = $hardErrors.Count
    hardErrors = $hardErrors.ToArray()
    completed = $hardErrors.Count -eq 0
}
$pilotManifestPath = Join-Path $PilotRoot 'pilot-manifest.json'
Write-G13R2Utf8NoBomJson -Path $pilotManifestPath -Value $pilotManifest -Depth 30

$reportLines = @(
    '# Gate 13-R2 Process-Reuse Pilot Validation Report',
    '',
    '## Material Passport',
    '',
    '- Origin Skill: experiment-agent',
    '- Origin Mode: validate',
    '- Origin Date: 2026-10-06',
    ('- Verification Status: ' + $(if ($hardErrors.Count -eq 0) { 'VERIFIED-NON-FORMAL-PILOT' } else { 'FAILED-NO-AUTO-RETRY' })),
    '- Version Label: `gate13_process_reuse_pilot_validation_v1`',
    '',
    '## Result',
    '',
    ('- Measured block processes: ' + $blocks.Count + ' / 36'),
    ('- Measured samples: ' + $samples.Count + ' / 96'),
    ('- Fresh cold structural controls: ' + $coldReferenceMap.Count + ' / 8'),
    ('- Structural mismatches: ' + $structuralOutput.mismatchCount),
    ('- Distinct measured process IDs: ' + $processIds.Count + ' / 36'),
    ('- Hard errors: ' + $hardErrors.Count),
    '- Formal campaign: false',
    '- Formal execution authorized: false',
    '',
    '## Candidate independent Williams blocks',
    '',
    '| Family | Marginal sigma | Paired sigma | Required | Candidate | Scheduled | Cap status |',
    '|---|---:|---:|---:|---:|---:|---|'
)
foreach ($family in $familyRows) {
    $reportLines += ('| {0} | {1:F6} | {2:F6} | {3} | {4} | {5} | {6} |' -f $family.familyId, $family.marginalSigmaLog, $family.pairedLogDifferenceSigma, $family.conservativeRequiredNFormal, $family.candidateNFormal, $family.scheduledNFormal, $(if ($family.overCap) { 'OVER CAP' } else { 'within cap' }))
}
$reportLines += @('', '## Budget projection', '', ('- Median block wall time: {0:F3} s' -f $medianWall), ('- P95 block wall time: {0:F3} s' -f $p95Wall), ('- Candidate schedule: {0} block processes / {1} algorithm samples' -f $budget.candidateFormalBlockProcessCount, $budget.candidateFormalAlgorithmSampleCount), ('- Candidate schedule projected median: {0:F3} h' -f $budget.candidateProjectedMedianWallHours), ('- Candidate schedule projected P95: {0:F3} h' -f $budget.candidateProjectedP95WallHours), ('- Historical cap-148 schedule projected median: {0:F3} h' -f $budget.projectedMedianWallHours), ('- Historical cap-148 schedule projected P95: {0:F3} h' -f $budget.projectedP95WallHours), '', 'This pilot is permanently excluded from formal analysis and does not authorize the reserved formal root or campaign.')
$reportPath = Join-Path $PilotRoot 'Gate13_ProcessReuse_Pilot_Validation_Report.md'
[System.IO.File]::WriteAllLines($reportPath, $reportLines, (New-Object System.Text.UTF8Encoding($false)))

[pscustomobject][ordered]@{
    passed = $hardErrors.Count -eq 0
    pilotManifestPath = $pilotManifestPath
    pilotManifestSha256 = Get-G13R2LowerSha256 -Path $pilotManifestPath
    measuredBlockProcessCount = $blocks.Count
    measuredSampleCount = $samples.Count
    structuralMismatchCount = [int]$structuralOutput.mismatchCount
    hardErrorCount = $hardErrors.Count
    hardErrors = $hardErrors.ToArray()
    formalCampaign = $false
    formalExecutionAuthorized = $false
} | ConvertTo-Json -Depth 12
if ($hardErrors.Count -gt 0) { exit 1 }
