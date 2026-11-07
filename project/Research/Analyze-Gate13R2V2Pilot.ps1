[CmdletBinding()]
param(
    [string]$ProjectPath = (Split-Path -Parent $PSScriptRoot),
    [string]$PilotRoot,
    [string]$PilotPlanPath,
    [string]$ProvenancePath
)

$ErrorActionPreference = 'Stop'
$ProjectPath = [System.IO.Path]::GetFullPath($ProjectPath)
if ([string]::IsNullOrWhiteSpace($PilotRoot)) { $PilotRoot = Join-Path $ProjectPath 'Research\PilotRuns\Gate13_ProcessReuse\v2' }
if ([string]::IsNullOrWhiteSpace($PilotPlanPath)) { $PilotPlanPath = Join-Path $ProjectPath 'Research\Gate13R2_v2_Pilot_Plan.v1.json' }
if ([string]::IsNullOrWhiteSpace($ProvenancePath)) { $ProvenancePath = Join-Path $ProjectPath 'Research\Gate13R2_v2_Provenance.v1.json' }
$PilotRoot = [System.IO.Path]::GetFullPath($PilotRoot)
$PilotPlanPath = [System.IO.Path]::GetFullPath($PilotPlanPath)
$ProvenancePath = [System.IO.Path]::GetFullPath($ProvenancePath)
$v2ModulePath = Join-Path $PSScriptRoot 'Gate13R2V2Preparation.psm1'
$v1ModulePath = Join-Path $PSScriptRoot 'Gate13ProcessReusePreparation.psm1'
Import-Module $v2ModulePath -Force
Import-Module $v1ModulePath -Force
$plan = Read-G13R2V2Json -Path $PilotPlanPath
$provenance = Read-G13R2V2Json -Path $ProvenancePath
$reservedFormalRoot = Join-Path $ProjectPath 'Research\FormalRuns\Gate13_ProcessReuse\v1'
if (Test-Path -LiteralPath $reservedFormalRoot) { throw 'Reserved process-reuse formal root must remain absent.' }
$planCheck = Test-G13R2V2PilotPlan -ProjectPath $ProjectPath -Plan $plan -PlanPath $PilotPlanPath
if (-not $planCheck.passed) { throw "V2 pilot plan validation failed: $($planCheck.errors -join '; ')" }
if (-not (Test-Path -LiteralPath $PilotRoot -PathType Container)) { throw 'V2 pilot root is missing.' }

function Get-SampleStandardDeviation([double[]]$Values) {
    if ($Values.Count -lt 2) { throw 'At least two observations are required for sample standard deviation.' }
    $mean = [double](($Values | Measure-Object -Average).Average)
    $sum = 0.0
    foreach ($value in $Values) { $sum += [math]::Pow($value - $mean, 2.0) }
    return [math]::Sqrt($sum / ($Values.Count - 1.0))
}

function Get-Median([double[]]$Values) {
    if ($Values.Count -eq 0) { return $null }
    $ordered = @($Values | Sort-Object)
    if ($ordered.Count % 2 -eq 1) { return [double]$ordered[[int][math]::Floor($ordered.Count / 2.0)] }
    return ([double]$ordered[$ordered.Count / 2 - 1] + [double]$ordered[$ordered.Count / 2]) / 2.0
}

function Get-P95([double[]]$Values) {
    if ($Values.Count -eq 0) { return $null }
    $ordered = @($Values | Sort-Object)
    $index = [int][math]::Ceiling(0.95 * $ordered.Count) - 1
    return [double]$ordered[[math]::Max(0, [math]::Min($ordered.Count - 1, $index))]
}

function Get-PearsonCorrelation([double[]]$X, [double[]]$Y) {
    if ($X.Count -ne $Y.Count -or $X.Count -lt 2) { return $null }
    $mx = [double](($X | Measure-Object -Average).Average)
    $my = [double](($Y | Measure-Object -Average).Average)
    $num = 0.0; $dx = 0.0; $dy = 0.0
    for ($index = 0; $index -lt $X.Count; $index++) { $a = $X[$index] - $mx; $b = $Y[$index] - $my; $num += $a * $b; $dx += $a * $a; $dy += $b * $b }
    if ($dx -le 0 -or $dy -le 0) { return $null }
    return $num / [math]::Sqrt($dx * $dy)
}

function Get-AverageRanks([double[]]$Values) {
    $indexed = for ($index = 0; $index -lt $Values.Count; $index++) { [pscustomobject]@{ index = $index; value = $Values[$index] } }
    $ordered = @($indexed | Sort-Object value, index)
    $ranks = New-Object double[] $Values.Count
    $cursor = 0
    while ($cursor -lt $ordered.Count) {
        $end = $cursor
        while ($end + 1 -lt $ordered.Count -and [double]$ordered[$end + 1].value -eq [double]$ordered[$cursor].value) { $end++ }
        $rank = (($cursor + 1.0) + ($end + 1.0)) / 2.0
        for ($i = $cursor; $i -le $end; $i++) { $ranks[[int]$ordered[$i].index] = $rank }
        $cursor = $end + 1
    }
    return $ranks
}

function Get-SpearmanCorrelation([double[]]$X, [double[]]$Y) { return Get-PearsonCorrelation -X (Get-AverageRanks -Values $X) -Y (Get-AverageRanks -Values $Y) }
function Get-DirectoryBytes([string]$Path) { return [int64](Get-ChildItem -LiteralPath $Path -File -Recurse | Measure-Object -Property Length -Sum).Sum }

$coldReferenceMap = @{}
$coldReferenceFiles = @(Get-ChildItem -LiteralPath (Join-Path $PilotRoot 'cold-reference') -Recurse -Filter 'workload-result.json' -File)
foreach ($file in $coldReferenceFiles) {
    $result = Read-G13R2V2Json -Path $file.FullName
    $key = '{0}|{1}' -f [string]$result.scenarioId, [string]$result.algorithmId
    if ($coldReferenceMap.ContainsKey($key)) { throw "Duplicate v2 fresh cold reference: $key" }
    $coldReferenceMap[$key] = [pscustomobject][ordered]@{ path = $file.FullName; result = $result; sha256 = Get-G13R2V2LowerSha256 -Path $file.FullName }
}
if ($coldReferenceMap.Count -ne 8) { throw "V2 fresh cold reference count is $($coldReferenceMap.Count); expected 8." }

$blockManifestFiles = @(Get-ChildItem -LiteralPath (Join-Path $PilotRoot 'measured') -Recurse -Filter 'block-manifest.json' -File | Sort-Object FullName)
if ($blockManifestFiles.Count -ne 36) { throw "V2 measured block manifest count is $($blockManifestFiles.Count); expected 36." }
$samples = New-Object System.Collections.Generic.List[object]
$blocks = New-Object System.Collections.Generic.List[object]
$structuralComparisons = New-Object System.Collections.Generic.List[object]
$hardErrors = New-Object System.Collections.Generic.List[string]
$processIds = New-Object System.Collections.Generic.HashSet[int]
$processIdentities = New-Object System.Collections.Generic.HashSet[string]

foreach ($blockFile in $blockManifestFiles) {
    $blockDirectory = Split-Path -Parent $blockFile.FullName
    $block = Read-G13R2V2Json -Path $blockFile.FullName
    if ($block.completed -ne $true -or $block.formalCampaign -ne $false -or $block.hardMemoryRulesPassed -ne $true -or [string]$block.executionDesignId -ne 'one-fresh-unity-process-per-williams-block-v2-native-telemetry') { $hardErrors.Add("Invalid v2 block manifest: $($blockFile.FullName)") }
    if ([int]$block.completedSampleCount -ne @($block.samples).Count -or [int]$block.expectedSampleCount -ne @($block.samples).Count) { $hardErrors.Add("Incomplete v2 block: $($block.blockId)") }
    if ([long]$block.blockRetainedManagedGrowthBytes -gt 134217728 -or [long]$block.blockWorkingSetGrowthBytes -gt 536870912 -or [long]$block.blockPrivateMemoryGrowthBytes -gt 536870912) { $hardErrors.Add("V2 block memory rule exceeded: $($block.blockId)") }
    [void]$processIds.Add([int]$block.processId)
    [void]$processIdentities.Add(('{0}|{1}' -f [int]$block.processId, [string]$block.processStartTimeUtc))
    $blocks.Add([pscustomobject][ordered]@{
        blockId = [string]$block.blockId
        campaignId = [string]$block.campaignId
        comparisonCohortId = [string]$block.comparisonCohortId
        block = [int]$block.block
        processId = [int]$block.processId
        processStartTimeUtc = [string]$block.processStartTimeUtc
        sampleCount = @($block.samples).Count
        retainedManagedGrowthBytes = [long]$block.blockRetainedManagedGrowthBytes
        workingSetGrowthBytes = [long]$block.blockWorkingSetGrowthBytes
        privateMemoryGrowthBytes = [long]$block.blockPrivateMemoryGrowthBytes
        manifestRelativePath = Get-G13R2V2ProjectRelativePath -ProjectPath $ProjectPath -FullPath $blockFile.FullName
        manifestSha256 = Get-G13R2V2LowerSha256 -Path $blockFile.FullName
    })
    foreach ($child in @($block.samples | Sort-Object position)) {
        $resultPath = Join-Path $blockDirectory ([string]$child.workloadResultRelativePath).Replace('/', '\')
        $manifestPath = Join-Path $blockDirectory ([string]$child.manifestRelativePath).Replace('/', '\')
        $summaryPath = Join-Path $blockDirectory ([string]$child.summaryRelativePath).Replace('/', '\')
        if (-not (Test-Path -LiteralPath $resultPath -PathType Leaf) -or -not (Test-Path -LiteralPath $manifestPath -PathType Leaf) -or -not (Test-Path -LiteralPath $summaryPath -PathType Leaf)) { $hardErrors.Add("Missing v2 child artifact: $($child.runId)"); continue }
        if ((Get-G13R2V2LowerSha256 -Path $resultPath) -ne [string]$child.workloadResultSha256 -or (Get-G13R2V2LowerSha256 -Path $manifestPath) -ne [string]$child.manifestSha256 -or (Get-G13R2V2LowerSha256 -Path $summaryPath) -ne [string]$child.summarySha256) { $hardErrors.Add("V2 child hash mismatch: $($child.runId)") }
        $result = Read-G13R2V2Json -Path $resultPath
        $manifest = Read-G13R2V2Json -Path $manifestPath
        $sampleSummary = Read-G13R2V2Json -Path $summaryPath
        if ($sampleSummary.completed -ne $true -or $sampleSummary.formalCampaign -ne $false -or [string]$sampleSummary.runId -ne [string]$child.runId -or [string]$sampleSummary.manifestSha256 -ne [string]$child.manifestSha256 -or [string]$sampleSummary.workloadResultSha256 -ne [string]$child.workloadResultSha256) { $hardErrors.Add("Invalid v2 sample summary: $($child.runId)") }
        if ([int]$manifest.schemaVersion -ne 4 -or [string]$manifest.executionDesignId -ne 'one-fresh-unity-process-per-williams-block-v2-native-telemetry' -or $manifest.completed -ne $true -or $manifest.formalCampaign -ne $false -or $manifest.forcedGcBeforeCompleted -ne $true -or $manifest.forcedGcAfterCompleted -ne $true -or $manifest.sampleStateCreatedFresh -ne $true -or $manifest.heavySampleReferencesReturned -ne $false -or $manifest.plannerResetCompleted -ne $true -or $manifest.loggerDisposed -ne $true) { $hardErrors.Add("Invalid v2 sample reset/cleanup manifest: $($child.runId)") }
        $telemetry = @($manifest.telemetryBeforeSample, $manifest.telemetryRawAfterWorkload, $manifest.telemetryAfterCleanup)
        if (@($telemetry | Where-Object { [int]$_.processId -ne [int]$block.processId }).Count -gt 0) { $hardErrors.Add("Mixed v2 process ID: $($child.runId)") }
        if ([double]$telemetry[0].processAgeMilliseconds -gt [double]$telemetry[1].processAgeMilliseconds -or [double]$telemetry[1].processAgeMilliseconds -gt [double]$telemetry[2].processAgeMilliseconds) { $hardErrors.Add("V2 process age reversed: $($child.runId)") }
        foreach ($capture in $telemetry) { foreach ($name in @('workingSetBytes', 'privateMemoryBytes', 'managedMemoryBytes')) { if ([long]$capture.$name -le 0) { $hardErrors.Add("Non-positive v2 telemetry ${name}: $($child.runId)") } } }
        if ([long]$manifest.sampleRetainedManagedGrowthBytes -gt 134217728 -or $manifest.retainedManagedGrowthWithinLimit -ne $true) { $hardErrors.Add("V2 sample retained managed-memory rule failed: $($child.runId)") }
        foreach ($generation in 0..2) { if ([int]$telemetry[2].("gcCollectionCount$generation") -lt [int]$telemetry[0].("gcCollectionCount$generation")) { $hardErrors.Add("V2 GC counter reversed: $($child.runId), generation=$generation") } }
        $operationsPath = Join-Path (Split-Path -Parent $manifestPath) ([string]$manifest.operationsJsonlFile)
        $lineCount = if (Test-Path -LiteralPath $operationsPath -PathType Leaf) { @(Get-Content -LiteralPath $operationsPath).Count } else { -1 }
        if ([long]$manifest.enqueuedLogRecords -ne [long]$manifest.writtenLogRecords -or [long]$manifest.writtenLogRecords -ne $lineCount) { $hardErrors.Add("V2 logger count mismatch: $($child.runId)") }
        $referenceKey = '{0}|{1}' -f [string]$result.scenarioId, [string]$result.algorithmId
        if (-not $coldReferenceMap.ContainsKey($referenceKey)) { $hardErrors.Add("Missing v2 structural reference: $referenceKey"); continue }
        $comparison = Compare-G13R2StructuralResults -Reference $coldReferenceMap[$referenceKey].result -Candidate $result
        if (-not $comparison.passed) { $hardErrors.Add("V2 structural mismatch: $($child.runId)") }
        $structuralComparisons.Add([pscustomobject][ordered]@{
            runId = [string]$child.runId
            referenceKey = $referenceKey
            referenceResultRelativePath = Get-G13R2V2ProjectRelativePath -ProjectPath $ProjectPath -FullPath $coldReferenceMap[$referenceKey].path
            referenceProjectionSha256 = [string]$comparison.referenceProjectionSha256
            candidateProjectionSha256 = [string]$comparison.candidateProjectionSha256
            passed = [bool]$comparison.passed
        })
        $endpoint = [double]$result.dynamicHandlingMillisecondsPerScheduledEvent
        if ([double]::IsNaN($endpoint) -or [double]::IsInfinity($endpoint) -or $endpoint -le 0) { $hardErrors.Add("V2 primary endpoint is non-positive/non-finite: $($child.runId)") }
        $plannerElapsed = [double]$result.totalPlannerElapsedMilliseconds
        if ([double]::IsNaN($plannerElapsed) -or [double]::IsInfinity($plannerElapsed) -or $plannerElapsed -lt 0) { $hardErrors.Add("V2 planner elapsed is negative/non-finite: $($child.runId)") }
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
            processAgeAfterCleanupMilliseconds = [double]$child.processAgeAfterCleanupMilliseconds
            workingSetCleanupDeltaBytes = [long]$child.workingSetAfterCleanupBytes - [long]$child.workingSetBeforeBytes
            privateMemoryCleanupDeltaBytes = [long]$child.privateMemoryAfterCleanupBytes - [long]$child.privateMemoryBeforeBytes
            managedMemoryRawGrowthBytes = [long]$child.managedMemoryRawAfterBytes - [long]$child.managedMemoryBeforeBytes
            managedMemoryRetainedGrowthBytes = [long]$child.managedMemoryAfterCleanupBytes - [long]$child.managedMemoryBeforeBytes
            gcCollectionDelta0 = [int]$child.gcCollectionDelta0
            gcCollectionDelta1 = [int]$child.gcCollectionDelta1
            gcCollectionDelta2 = [int]$child.gcCollectionDelta2
            totalPlannerElapsedMilliseconds = $plannerElapsed
            dynamicHandlingMillisecondsPerScheduledEvent = $endpoint
            logPrimaryEndpoint = if ($endpoint -gt 0) { [math]::Log($endpoint) } else { [double]::NaN }
            resultRelativePath = Get-G13R2V2ProjectRelativePath -ProjectPath $ProjectPath -FullPath $resultPath
            resultSha256 = Get-G13R2V2LowerSha256 -Path $resultPath
        })
    }
}

if ($processIds.Count -ne 36 -or $processIdentities.Count -ne 36) { $hardErrors.Add("V2 measured process identity mismatch: PID=$($processIds.Count), identity=$($processIdentities.Count), expected=36") }
if ($samples.Count -ne 96) { $hardErrors.Add("V2 measured sample count is $($samples.Count); expected 96.") }
if ($structuralComparisons.Count -ne 96) { $hardErrors.Add("V2 structural comparison count is $($structuralComparisons.Count); expected 96.") }

$balanceRows = New-Object System.Collections.Generic.List[object]
foreach ($group in @($samples | Group-Object campaignId, algorithmId, position)) { $first = $group.Group[0]; $balanceRows.Add([pscustomobject][ordered]@{ campaignId = $first.campaignId; algorithmId = $first.algorithmId; position = $first.position; count = $group.Count }) }
foreach ($campaign in @($plan.measuredCampaigns)) {
    $algorithmCount = @($campaign.algorithms).Count
    $expectedPerPosition = [int]$campaign.blocks / $algorithmCount
    foreach ($algorithm in @($campaign.algorithms)) { foreach ($position in 1..$algorithmCount) { $count = @($samples | Where-Object { $_.campaignId -eq $campaign.campaignId -and $_.algorithmId -eq $algorithm -and $_.position -eq $position }).Count; if ($count -ne $expectedPerPosition) { $hardErrors.Add("V2 position balance mismatch: $($campaign.campaignId)/$algorithm/p$position=$count expected=$expectedPerPosition") } } }
    foreach ($pair in @($samples | Where-Object { $_.campaignId -eq $campaign.campaignId -and $_.predecessorAlgorithmId -ne 'NONE' } | Group-Object predecessorAlgorithmId, algorithmId)) { if ($pair.Count -ne $expectedPerPosition) { $hardErrors.Add("V2 predecessor balance mismatch: $($campaign.campaignId)/$($pair.Name)=$($pair.Count) expected=$expectedPerPosition") } }
}

$associationDiagnostics = New-Object System.Collections.Generic.List[object]
$resourceDiagnostics = New-Object System.Collections.Generic.List[object]
foreach ($group in @($samples | Group-Object comparisonCohortId, algorithmId)) {
    $first = $group.Group[0]
    $position = [double[]]@($group.Group | ForEach-Object { [double]$_.position })
    $age = [double[]]@($group.Group | ForEach-Object { [double]$_.processAgeBeforeMilliseconds })
    $endpoint = [double[]]@($group.Group | ForEach-Object { [double]$_.logPrimaryEndpoint })
    $associationDiagnostics.Add([pscustomobject][ordered]@{ comparisonCohortId = $first.comparisonCohortId; algorithmId = $first.algorithmId; n = $endpoint.Count; positionPearson = Get-PearsonCorrelation $position $endpoint; positionSpearman = Get-SpearmanCorrelation $position $endpoint; processAgePearson = Get-PearsonCorrelation $age $endpoint; processAgeSpearman = Get-SpearmanCorrelation $age $endpoint })
}
foreach ($group in @($samples | Group-Object comparisonCohortId, algorithmId, position)) {
    $first = $group.Group[0]
    $resourceDiagnostics.Add([pscustomobject][ordered]@{
        comparisonCohortId = $first.comparisonCohortId; algorithmId = $first.algorithmId; position = $first.position; n = $group.Count
        workingSetCleanupDeltaMeanBytes = [double](($group.Group | Measure-Object workingSetCleanupDeltaBytes -Average).Average)
        privateMemoryCleanupDeltaMeanBytes = [double](($group.Group | Measure-Object privateMemoryCleanupDeltaBytes -Average).Average)
        managedMemoryRawGrowthMeanBytes = [double](($group.Group | Measure-Object managedMemoryRawGrowthBytes -Average).Average)
        managedMemoryRetainedGrowthMeanBytes = [double](($group.Group | Measure-Object managedMemoryRetainedGrowthBytes -Average).Average)
        gcCollectionDelta0Total = [int](($group.Group | Measure-Object gcCollectionDelta0 -Sum).Sum)
        gcCollectionDelta1Total = [int](($group.Group | Measure-Object gcCollectionDelta1 -Sum).Sum)
        gcCollectionDelta2Total = [int](($group.Group | Measure-Object gcCollectionDelta2 -Sum).Sum)
    })
}

$familyDefinitions = @(
    [pscustomobject][ordered]@{ familyId = 'P1-DL-vs-A-shared'; comparisonCohortId = 'four-algorithm-shared-goal-v1'; first = 'A*-R'; second = 'D*L' },
    [pscustomobject][ordered]@{ familyId = 'P2-DL-vs-A-hetero'; comparisonCohortId = 'per-agent-heterogeneous-goal-v1'; first = 'A*-R'; second = 'D*L' },
    [pscustomobject][ordered]@{ familyId = 'P3-IDFF-vs-CFF-shared'; comparisonCohortId = 'four-algorithm-shared-goal-v1'; first = 'C-FF'; second = 'IDFF' },
    [pscustomobject][ordered]@{ familyId = 'P4-IDFF-vs-CFF-grouped'; comparisonCohortId = 'grouped-field-heterogeneous-goal-v1'; first = 'C-FF'; second = 'IDFF' }
)
$familyRows = New-Object System.Collections.Generic.List[object]
foreach ($family in $familyDefinitions) {
    $familySamples = @($samples | Where-Object { $_.comparisonCohortId -eq $family.comparisonCohortId -and $_.algorithmId -in @($family.first, $family.second) })
    $marginalSigmas = foreach ($algorithm in @($family.first, $family.second)) { Get-SampleStandardDeviation -Values ([double[]]@($familySamples | Where-Object algorithmId -eq $algorithm | ForEach-Object logPrimaryEndpoint)) }
    $marginalSigma = [double]($marginalSigmas | Measure-Object -Maximum).Maximum
    $pairedDifferences = New-Object System.Collections.Generic.List[double]
    $firstValues = New-Object System.Collections.Generic.List[double]
    $secondValues = New-Object System.Collections.Generic.List[double]
    foreach ($blockGroup in @($familySamples | Group-Object blockId)) {
        $firstSample = @($blockGroup.Group | Where-Object algorithmId -eq $family.first)
        $secondSample = @($blockGroup.Group | Where-Object algorithmId -eq $family.second)
        if ($firstSample.Count -ne 1 -or $secondSample.Count -ne 1) { throw "Incomplete v2 within-block pair: $($family.familyId)/$($blockGroup.Name)" }
        $firstValues.Add([double]$firstSample[0].logPrimaryEndpoint); $secondValues.Add([double]$secondSample[0].logPrimaryEndpoint)
        $pairedDifferences.Add([double]$secondSample[0].logPrimaryEndpoint - [double]$firstSample[0].logPrimaryEndpoint)
    }
    $pairedSigma = Get-SampleStandardDeviation -Values ([double[]]$pairedDifferences.ToArray())
    $marginalCandidate = Get-G13R2V2SampleSizeCandidate -SigmaLog $marginalSigma
    $pairedCandidate = Get-G13R2V2SampleSizeCandidate -SigmaLog $pairedSigma
    $required = [long][math]::Max([long]$marginalCandidate.requiredNFormal, [long]$pairedCandidate.requiredNFormal)
    $familyRows.Add([pscustomobject][ordered]@{
        familyId = $family.familyId; comparisonCohortId = $family.comparisonCohortId; contrast = "$($family.second)-vs-$($family.first)"; independentBlockCount = $pairedDifferences.Count
        marginalSigmaLog = $marginalSigma; marginal = $marginalCandidate; pairedLogDifferenceSigma = $pairedSigma; paired = $pairedCandidate
        withinBlockEndpointCorrelation = Get-PearsonCorrelation -X ([double[]]$firstValues.ToArray()) -Y ([double[]]$secondValues.ToArray())
        conservativeRequiredNFormal = $required; candidateNFormal = [long][math]::Min(148, $required); overCap = $required -gt 148; scheduledNFormal = [long][math]::Min(148, $required); harmonizationReason = 'none'
    })
}
$p1 = @($familyRows | Where-Object familyId -eq 'P1-DL-vs-A-shared')[0]
$p3 = @($familyRows | Where-Object familyId -eq 'P3-IDFF-vs-CFF-shared')[0]
$sharedScheduled = [long][math]::Max([long]$p1.candidateNFormal, [long]$p3.candidateNFormal)
$p1.scheduledNFormal = $sharedScheduled; $p3.scheduledNFormal = $sharedScheduled
$p1.harmonizationReason = 'shared-four-algorithm-cohort-max-p1-p3-complete-williams-cycles-v2'; $p3.harmonizationReason = $p1.harmonizationReason
if (@($familyRows | Where-Object overCap).Count -gt 0) { $hardErrors.Add('At least one conservative v2 sample-size requirement exceeds cap 148.') }

$blockSummaryFiles = @(Get-ChildItem -LiteralPath (Join-Path $PilotRoot 'measured') -Recurse -Filter 'b*.summary.json' -File)
$blockPerformance = New-Object System.Collections.Generic.List[object]
foreach ($file in $blockSummaryFiles) {
    $summary = Read-G13R2V2Json -Path $file.FullName
    $record = @($blocks | Where-Object blockId -eq ([string]$summary.blockId))
    if ($record.Count -ne 1) { $hardErrors.Add("V2 block summary cannot be joined: $($summary.blockId)"); continue }
    $blockSamples = @($samples | Where-Object blockId -eq ([string]$summary.blockId))
    $plannerMs = [double](($blockSamples | Measure-Object totalPlannerElapsedMilliseconds -Sum).Sum)
    $outputDirectory = [System.IO.Path]::GetFullPath([string]$summary.outputDirectory)
    if (-not $outputDirectory.StartsWith($PilotRoot.TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase)) { $hardErrors.Add("V2 block summary escapes pilot root: $($summary.blockId)"); continue }
    $blockPerformance.Add([pscustomobject][ordered]@{ blockId = $summary.blockId; comparisonCohortId = $record[0].comparisonCohortId; wallSeconds = [double]$summary.wallSeconds; plannerMilliseconds = $plannerMs; startupAmortizationRatioWallToPlanner = if ($plannerMs -gt 0) { 1000.0 * [double]$summary.wallSeconds / $plannerMs } else { $null }; rawBytes = Get-DirectoryBytes $outputDirectory })
}
if ($blockPerformance.Count -ne 36) { $hardErrors.Add("V2 measured block summary count is $($blockPerformance.Count); expected 36.") }
$wallSeconds = [double[]]@($blockPerformance | ForEach-Object wallSeconds)
$blockBytes = [double[]]@($blockPerformance | ForEach-Object rawBytes)
$medianWall = Get-Median $wallSeconds; $p95Wall = Get-P95 $wallSeconds; $medianBytes = Get-Median $blockBytes; $p95Bytes = Get-P95 $blockBytes
$candidateSchedule = @(
    [pscustomobject]@{ comparisonCohortId = 'four-algorithm-shared-goal-v1'; campaignCount = 32; blocks = [int]$sharedScheduled; algorithms = 4 },
    [pscustomobject]@{ comparisonCohortId = 'per-agent-heterogeneous-goal-v1'; campaignCount = 21; blocks = [int](@($familyRows | Where-Object familyId -eq 'P2-DL-vs-A-hetero')[0].scheduledNFormal); algorithms = 2 },
    [pscustomobject]@{ comparisonCohortId = 'grouped-field-heterogeneous-goal-v1'; campaignCount = 21; blocks = [int](@($familyRows | Where-Object familyId -eq 'P4-IDFF-vs-CFF-grouped')[0].scheduledNFormal); algorithms = 2 }
)
$candidateProcesses = 0L; $candidateSamples = 0L; $candidateMedianSeconds = 0.0; $candidateP95Seconds = 0.0; $candidateMedianBytes = 0L; $candidateP95Bytes = 0L
$cohortBudgets = New-Object System.Collections.Generic.List[object]
foreach ($cohort in $candidateSchedule) {
    $perf = @($blockPerformance | Where-Object comparisonCohortId -eq $cohort.comparisonCohortId)
    $mw = Get-Median ([double[]]@($perf | ForEach-Object wallSeconds)); $pw = Get-P95 ([double[]]@($perf | ForEach-Object wallSeconds)); $mb = Get-Median ([double[]]@($perf | ForEach-Object rawBytes)); $pb = Get-P95 ([double[]]@($perf | ForEach-Object rawBytes))
    $pc = [long]$cohort.campaignCount * [long]$cohort.blocks; $sc = $pc * [long]$cohort.algorithms
    $candidateProcesses += $pc; $candidateSamples += $sc; $candidateMedianSeconds += $pc * $mw; $candidateP95Seconds += $pc * $pw; $candidateMedianBytes += [long][math]::Ceiling($pc * $mb); $candidateP95Bytes += [long][math]::Ceiling($pc * $pb)
    $cohortBudgets.Add([pscustomobject][ordered]@{ comparisonCohortId = $cohort.comparisonCohortId; formalCampaignCount = $cohort.campaignCount; candidateBlocksPerCampaign = $cohort.blocks; candidateBlockProcessCount = $pc; candidateAlgorithmSampleCount = $sc; medianBlockWallSeconds = $mw; p95BlockWallSeconds = $pw; medianBlockRawBytes = $mb; p95BlockRawBytes = $pb })
}
$budget = [ordered]@{ schemaVersion = 1; projectionKind = 'gate13-r2-v2-process-reuse-block-observed-pilot-projection-v1'; measuredBlockProcessCount = 36; cohortProjections = $cohortBudgets.ToArray(); candidateFormalBlockProcessCount = $candidateProcesses; candidateFormalAlgorithmSampleCount = $candidateSamples; candidateProjectedMedianWallHours = $candidateMedianSeconds / 3600.0; candidateProjectedP95WallHours = $candidateP95Seconds / 3600.0; candidateProjectedMedianRawBytes = $candidateMedianBytes; candidateProjectedP95RawBytes = $candidateP95Bytes; medianBlockWallSeconds = $medianWall; p95BlockWallSeconds = $p95Wall; medianBlockRawBytes = $medianBytes; p95BlockRawBytes = $p95Bytes; executionAuthorizationConferred = $false }

$structuralOutput = [ordered]@{ schemaVersion = 1; comparisonCount = $structuralComparisons.Count; mismatchCount = @($structuralComparisons | Where-Object { -not $_.passed }).Count; exactStructuralFieldPolicy = 'gate13-r2-v2-specification-section-8'; freshColdReferenceCount = $coldReferenceMap.Count; comparisons = $structuralComparisons.ToArray(); passed = @($structuralComparisons | Where-Object { -not $_.passed }).Count -eq 0 }
$runtimeDiagnostics = [ordered]@{ schemaVersion = 1; measuredBlockProcessCount = $blocks.Count; distinctProcessIdCount = $processIds.Count; distinctProcessIdentityCount = $processIdentities.Count; measuredSampleCount = $samples.Count; positionBalance = $balanceRows.ToArray(); positionAndProcessAgeAssociations = $associationDiagnostics.ToArray(); resourceDiagnosticsByAlgorithmPosition = $resourceDiagnostics.ToArray(); blockWallAndStartupAmortization = $blockPerformance.ToArray(); blocks = $blocks.ToArray(); hardManagedGrowthLimitBytes = 134217728L; hardWorkingSetGrowthLimitBytes = 536870912L; hardPrivateMemoryGrowthLimitBytes = 536870912L; hardErrorCount = $hardErrors.Count; hardErrors = $hardErrors.ToArray(); passed = $hardErrors.Count -eq 0 }
$candidateOutput = [ordered]@{ schemaVersion = 1; precisionRelativeHalfWidthTarget = 0.10; independentUnit = 'williams-block-unity-process-v2'; withinProcessSamplesCorrelated = $true; formula = 'max-of-marginal-and-within-block-paired-requirements-v1'; minimumIndependentBlocks = 30; cycleMultiple = 4; maximumIndependentBlocks = 148; families = $familyRows.ToArray(); anyOverCap = @($familyRows | Where-Object overCap).Count -gt 0; admissible = $hardErrors.Count -eq 0; formalExecutionAuthorizationConferred = $false }

$structuralPath = Join-Path $PilotRoot 'structural-equivalence.json'; $runtimePath = Join-Path $PilotRoot 'runtime-diagnostics.json'; $candidatePath = Join-Path $PilotRoot 'candidate-sample-sizes.json'; $budgetPath = Join-Path $PilotRoot 'budget-feasibility.json'
foreach ($path in @($structuralPath, $runtimePath, $candidatePath, $budgetPath)) { if (Test-Path -LiteralPath $path) { throw "Create-new v2 analysis output exists: $path" } }
Write-G13R2V2Utf8NoBomJson $structuralPath $structuralOutput 40; Write-G13R2V2Utf8NoBomJson $runtimePath $runtimeDiagnostics 40; Write-G13R2V2Utf8NoBomJson $candidatePath $candidateOutput 40; Write-G13R2V2Utf8NoBomJson $budgetPath $budget 30

$executionManifestPath = Join-Path $PilotRoot 'pilot-execution-manifest.json'
if (-not (Test-Path -LiteralPath $executionManifestPath -PathType Leaf)) { throw 'V2 pilot execution manifest is missing.' }
$analysisManifest = [ordered]@{ schemaVersion = 1; manifestKind = 'gate13-r2-v2-process-reuse-pilot-analysis-manifest-v1'; savedAtUtc = [DateTime]::UtcNow.ToString('o'); pilotPlan = [ordered]@{ relativePath = 'Research/Gate13R2_v2_Pilot_Plan.v1.json'; sha256 = Get-G13R2V2LowerSha256 $PilotPlanPath }; provenance = [ordered]@{ relativePath = Get-G13R2V2ProjectRelativePath $ProjectPath $ProvenancePath; sha256 = Get-G13R2V2LowerSha256 $ProvenancePath }; executionManifest = [ordered]@{ relativePath = 'pilot-execution-manifest.json'; sha256 = Get-G13R2V2LowerSha256 $executionManifestPath }; outputs = @([ordered]@{ relativePath = 'structural-equivalence.json'; sha256 = Get-G13R2V2LowerSha256 $structuralPath }, [ordered]@{ relativePath = 'runtime-diagnostics.json'; sha256 = Get-G13R2V2LowerSha256 $runtimePath }, [ordered]@{ relativePath = 'candidate-sample-sizes.json'; sha256 = Get-G13R2V2LowerSha256 $candidatePath }, [ordered]@{ relativePath = 'budget-feasibility.json'; sha256 = Get-G13R2V2LowerSha256 $budgetPath }); formalCampaign = $false; excludedFromFormalAnalysis = $true; processReuseFormalExecutionAuthorized = $false; passed = $hardErrors.Count -eq 0 }
$analysisManifestPath = Join-Path $PilotRoot 'analysis-manifest.json'; Write-G13R2V2Utf8NoBomJson $analysisManifestPath $analysisManifest 30
$pilotManifest = [ordered]@{ schemaVersion = 1; manifestKind = 'gate13-r2-v2-process-reuse-non-formal-pilot-manifest-v1'; completedAtUtc = [DateTime]::UtcNow.ToString('o'); designId = 'one-fresh-unity-process-per-williams-block-v2-native-telemetry'; pilotPlanSha256 = Get-G13R2V2LowerSha256 $PilotPlanPath; provenanceSha256 = Get-G13R2V2LowerSha256 $ProvenancePath; executionManifestSha256 = Get-G13R2V2LowerSha256 $executionManifestPath; analysisManifestSha256 = Get-G13R2V2LowerSha256 $analysisManifestPath; measuredBlockProcessCount = $blocks.Count; measuredSampleCount = $samples.Count; freshColdReferenceProcessCount = $coldReferenceMap.Count; structuralMismatchCount = [int]$structuralOutput.mismatchCount; distinctMeasuredProcessIdCount = $processIds.Count; candidateSampleSizes = @($familyRows | Select-Object familyId, conservativeRequiredNFormal, candidateNFormal, scheduledNFormal, overCap, harmonizationReason, withinBlockEndpointCorrelation); budgetProjection = $budget; formalCampaign = $false; excludedFromFormalAnalysis = $true; formalExecutionAuthorized = $false; reservedFormalRootCreated = Test-Path $reservedFormalRoot; hardErrorCount = $hardErrors.Count; hardErrors = $hardErrors.ToArray(); completed = $hardErrors.Count -eq 0 }
$pilotManifestPath = Join-Path $PilotRoot 'pilot-manifest.json'; Write-G13R2V2Utf8NoBomJson $pilotManifestPath $pilotManifest 40

$reportLines = @('# Gate 13-R2 v2 Telemetry/Readiness Pilot Validation Report','','## Material Passport','','- Origin Skill: experiment-agent','- Origin Mode: validate','- Origin Date: 2026-10-06',('- Verification Status: ' + $(if ($hardErrors.Count -eq 0) { 'VERIFIED-NON-FORMAL-PILOT' } else { 'FAILED-NO-AUTO-RETRY' })),'- Version Label: `gate13_r2_v2_pilot_validation_v1`','','## Result','',('- Measured block processes: ' + $blocks.Count + ' / 36'),('- Measured samples: ' + $samples.Count + ' / 96'),('- Fresh cold structural controls: ' + $coldReferenceMap.Count + ' / 8'),('- Structural mismatches: ' + $structuralOutput.mismatchCount),('- Distinct measured process IDs: ' + $processIds.Count + ' / 36'),('- Hard errors: ' + $hardErrors.Count),'- Formal campaign: false','- Formal execution authorized: false','','## Candidate independent Williams blocks','','| Family | Marginal sigma | Paired sigma | Correlation | Required | Candidate | Scheduled | Cap status |','|---|---:|---:|---:|---:|---:|---:|---|')
foreach ($family in $familyRows) { $reportLines += ('| {0} | {1:F6} | {2:F6} | {3:F6} | {4} | {5} | {6} | {7} |' -f $family.familyId, $family.marginalSigmaLog, $family.pairedLogDifferenceSigma, [double]$family.withinBlockEndpointCorrelation, $family.conservativeRequiredNFormal, $family.candidateNFormal, $family.scheduledNFormal, $(if ($family.overCap) { 'OVER CAP' } else { 'within cap' })) }
$reportLines += @('','## Budget projection','',('- Median block wall time: {0:F3} s' -f $medianWall),('- P95 block wall time: {0:F3} s' -f $p95Wall),('- Candidate schedule: {0} block processes / {1} algorithm samples' -f $candidateProcesses, $candidateSamples),('- Candidate projected median: {0:F3} h' -f ($candidateMedianSeconds / 3600.0)),('- Candidate projected P95: {0:F3} h' -f ($candidateP95Seconds / 3600.0)),'','This pilot is permanently NON-FORMAL / EXCLUDED-FROM-FORMAL-ANALYSIS and confers no formal execution authority.')
$reportPath = Join-Path $PilotRoot 'Gate13R2_v2_Pilot_Validation_Report.md'; [System.IO.File]::WriteAllLines($reportPath, $reportLines, (New-Object System.Text.UTF8Encoding($false)))

[pscustomobject][ordered]@{ passed = $hardErrors.Count -eq 0; pilotManifestPath = $pilotManifestPath; pilotManifestSha256 = Get-G13R2V2LowerSha256 $pilotManifestPath; measuredBlockProcessCount = $blocks.Count; measuredSampleCount = $samples.Count; structuralMismatchCount = [int]$structuralOutput.mismatchCount; hardErrorCount = $hardErrors.Count; hardErrors = $hardErrors.ToArray(); formalCampaign = $false; formalExecutionAuthorized = $false } | ConvertTo-Json -Depth 20
if ($hardErrors.Count -gt 0) { exit 1 }
exit 0
