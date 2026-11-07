[CmdletBinding()]
param(
    [string]$ProjectPath
)

$ErrorActionPreference = 'Stop'
$scriptDirectory = Split-Path -Parent $MyInvocation.MyCommand.Path
if ([string]::IsNullOrWhiteSpace($ProjectPath)) {
    $ProjectPath = [System.IO.Path]::GetFullPath((Join-Path $scriptDirectory '..\..'))
} else {
    $ProjectPath = [System.IO.Path]::GetFullPath($ProjectPath)
}

$summaryPath = Join-Path $scriptDirectory 'Gate12_FinalAudit.summary.json'
$pilotRoot = Join-Path $ProjectPath 'Research\PilotRuns\Gate12\v1'
$bundleRoot = Join-Path $ProjectPath 'Research\FormalScenarios\v1'
$planPath = Join-Path $ProjectPath 'Research\Gate12_Pilot_Plan.v1.json'
$pilotManifestPath = Join-Path $pilotRoot 'pilot-manifest.json'
$analysisManifestPath = Join-Path $pilotRoot 'analysis-manifest.json'
$noisePath = Join-Path $pilotRoot 'noise-analysis.json'
$candidatePath = Join-Path $pilotRoot 'candidate-sample-sizes.json'
$budgetPath = Join-Path $pilotRoot 'budget-feasibility.json'

function Get-LowerSha256([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Get-StringSha256([string]$Value) {
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($Value)
        return ([System.BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-', '').ToLowerInvariant()
    } finally {
        $sha.Dispose()
    }
}

function Write-Utf8NoBomJson([string]$Path, $Value, [int]$Depth = 16) {
    $json = $Value | ConvertTo-Json -Depth $Depth
    $json = $json.Replace("`r`n", "`n").Replace("`r", "`n")
    if (-not $json.EndsWith("`n", [System.StringComparison]::Ordinal)) { $json += "`n" }
    $encoding = New-Object System.Text.UTF8Encoding($false, $true)
    [System.IO.File]::WriteAllText($Path, $json, $encoding)
}

function Resolve-ProjectRelativePath([string]$RelativePath) {
    return [System.IO.Path]::GetFullPath((Join-Path $ProjectPath $RelativePath.Replace('/', '\')))
}

function Get-SampleStandardDeviation([double[]]$Values) {
    if ($Values.Count -lt 2) { throw 'At least two values are required for sample standard deviation.' }
    $sum = 0.0
    foreach ($value in $Values) { $sum += $value }
    $mean = $sum / $Values.Count
    $sumSquares = 0.0
    foreach ($value in $Values) {
        $delta = $value - $mean
        $sumSquares += $delta * $delta
    }
    return [Math]::Sqrt($sumSquares / ($Values.Count - 1))
}

function Get-Median([double[]]$Values) {
    if ($Values.Count -eq 0) { throw 'Median requires at least one value.' }
    $sorted = @($Values | Sort-Object)
    $middle = [int][Math]::Floor($sorted.Count / 2)
    if (($sorted.Count % 2) -eq 1) { return [double]$sorted[$middle] }
    return ([double]$sorted[$middle - 1] + [double]$sorted[$middle]) / 2.0
}

function Get-NearestRankPercentile([double[]]$Values, [double]$Probability) {
    if ($Values.Count -eq 0) { throw 'Percentile requires at least one value.' }
    $sorted = @($Values | Sort-Object)
    $index = [int][Math]::Ceiling($Probability * $sorted.Count) - 1
    if ($index -lt 0) { $index = 0 }
    if ($index -ge $sorted.Count) { $index = $sorted.Count - 1 }
    return [double]$sorted[$index]
}

function Test-Near([double]$Actual, [double]$Expected, [double]$Tolerance = 1e-10) {
    return [Math]::Abs($Actual - $Expected) -le $Tolerance
}

$errors = New-Object System.Collections.Generic.List[string]
function Add-AuditError([string]$Message) { $script:errors.Add($Message) }

$requiredPaths = @(
    $planPath,
    $pilotManifestPath,
    $analysisManifestPath,
    $noisePath,
    $candidatePath,
    $budgetPath,
    (Join-Path $pilotRoot 'environment-start.json'),
    (Join-Path $pilotRoot 'environment-post-warmup.json'),
    (Join-Path $pilotRoot 'environment-end.json'),
    (Join-Path $pilotRoot 'pilot-checkpoint.json'),
    (Join-Path $scriptDirectory 'Gate12_PreImplementationAudit.summary.json'),
    (Join-Path $scriptDirectory 'Gate12_AnalysisUnitTests.summary.json')
)
foreach ($path in $requiredPaths) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { Add-AuditError "Required file is missing: $path" }
}
if ($errors.Count -ne 0) { throw ($errors -join [Environment]::NewLine) }

$plan = Get-Content -LiteralPath $planPath -Raw -Encoding UTF8 | ConvertFrom-Json
$pilot = Get-Content -LiteralPath $pilotManifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
$analysisManifest = Get-Content -LiteralPath $analysisManifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
$noise = Get-Content -LiteralPath $noisePath -Raw -Encoding UTF8 | ConvertFrom-Json
$candidates = Get-Content -LiteralPath $candidatePath -Raw -Encoding UTF8 | ConvertFrom-Json
$budget = Get-Content -LiteralPath $budgetPath -Raw -Encoding UTF8 | ConvertFrom-Json
$environmentStart = Get-Content -LiteralPath (Join-Path $pilotRoot 'environment-start.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$environmentPostWarmup = Get-Content -LiteralPath (Join-Path $pilotRoot 'environment-post-warmup.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$environmentEnd = Get-Content -LiteralPath (Join-Path $pilotRoot 'environment-end.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$pilotCheckpoint = Get-Content -LiteralPath (Join-Path $pilotRoot 'pilot-checkpoint.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$preAudit = Get-Content -LiteralPath (Join-Path $scriptDirectory 'Gate12_PreImplementationAudit.summary.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$unitTests = Get-Content -LiteralPath (Join-Path $scriptDirectory 'Gate12_AnalysisUnitTests.summary.json') -Raw -Encoding UTF8 | ConvertFrom-Json

# Frozen Gate 12 identities.
$expectedHashes = [ordered]@{
    specification = '29e6ca0de24b10f4a3a679378a353f9ae1821b130d1218f298591d2e89878b7c'
    testDesign = 'c8f71a54f9c73f936e3ddfeff6d4212bd48fb495847b9185a69adf720226e199'
    pilotPlan = 'cc63505f444223c06a7f69a979c6a0d2e7f0d29e8217d910fe46b61db5618ce4'
    bundleManifest = 'ea596c8c9e6d1ca99e325c05c095024a4813ca1e65c771a8b4db8bf29364c12e'
    bundleAggregate = '91d9e3c66327185e48f68cafb05c674cc49e929adb576973098d0bfebd2e9a88'
    analysisModule = '96194e77239ad1e842d6ccacd2ffc870afdf8d3a2701144ae05dadeb472fe676'
    pilotRunner = 'bf45cebf1b04a73f1d3ca4cbdc6375f3aab00b9979e129145ac27e91e62cb025'
    analyzer = '6aab2f34713ca929ca184bdda2238defedf022f2a39f050959aed02194b91a65'
    pilotManifest = '638ac2e3fe243212ef031bdbed4c06394447e055c4d080be370357c41122e18a'
    analysisManifest = 'c8b6586bcc59d7ce1fc332a490cada73ee69052ef5abcc65fe2b3b90cdff7699'
}
$actualHashes = [ordered]@{
    specification = Get-LowerSha256 (Join-Path $ProjectPath 'Research\Gate12_Pilot_Noise_and_Sample_Size_Specification.md')
    testDesign = Get-LowerSha256 (Join-Path $ProjectPath 'Research\Gate12_Pilot_Test_Design.md')
    pilotPlan = Get-LowerSha256 $planPath
    bundleManifest = Get-LowerSha256 (Join-Path $bundleRoot 'bundle-manifest.json')
    analysisModule = Get-LowerSha256 (Join-Path $ProjectPath 'Research\Gate12PilotAnalysis.psm1')
    pilotRunner = Get-LowerSha256 (Join-Path $ProjectPath 'Research\Run-Gate12Pilot.ps1')
    analyzer = Get-LowerSha256 (Join-Path $ProjectPath 'Research\Analyze-Gate12Pilot.ps1')
    pilotManifest = Get-LowerSha256 $pilotManifestPath
    analysisManifest = Get-LowerSha256 $analysisManifestPath
}
$frozenHashErrors = @()
foreach ($key in @('specification', 'testDesign', 'pilotPlan', 'bundleManifest', 'analysisModule', 'pilotRunner', 'analyzer', 'pilotManifest', 'analysisManifest')) {
    if ($actualHashes[$key] -ne $expectedHashes[$key]) {
        $frozenHashErrors += "$key expected $($expectedHashes[$key]), actual $($actualHashes[$key])"
    }
}

# Original-source baseline remains frozen.
$baselineRows = Import-Csv -LiteralPath (Join-Path $ProjectPath 'Research\Baseline_SHA256.csv')
$baselineMismatches = @()
$baselineChecked = 0
foreach ($row in $baselineRows | Where-Object { $_.scope -in @('external_archive', 'working_copy') }) {
    $baselineChecked++
    $path = [System.IO.Path]::GetFullPath((Join-Path $ProjectPath $row.relative_path))
    $exists = Test-Path -LiteralPath $path -PathType Leaf
    $actualBytes = if ($exists) { (Get-Item -LiteralPath $path).Length } else { $null }
    $actualHash = if ($exists) { Get-LowerSha256 $path } else { $null }
    if (-not $exists -or $actualBytes -ne [int64]$row.bytes -or $actualHash -ne $row.sha256) {
        $baselineMismatches += [ordered]@{
            relativePath = $row.relative_path
            exists = $exists
            expectedBytes = [int64]$row.bytes
            actualBytes = $actualBytes
            expectedSha256 = $row.sha256
            actualSha256 = $actualHash
        }
    }
}

# Recompute every retained Gate 11 bundle artifact and its order-sensitive aggregate.
$bundleManifestPath = Join-Path $bundleRoot 'bundle-manifest.json'
$bundleManifest = Get-Content -LiteralPath $bundleManifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
$bundleArtifactErrors = @()
$aggregateBuilder = New-Object System.Text.StringBuilder
foreach ($artifact in @($bundleManifest.artifacts)) {
    $artifactPath = Join-Path $bundleRoot ([string]$artifact.relativePath).Replace('/', '\')
    if (-not (Test-Path -LiteralPath $artifactPath -PathType Leaf)) {
        $bundleArtifactErrors += "Missing retained artifact: $($artifact.relativePath)"
        continue
    }
    $artifactHash = Get-LowerSha256 $artifactPath
    $artifactBytes = (Get-Item -LiteralPath $artifactPath).Length
    if ($artifactHash -ne $artifact.sha256 -or $artifactBytes -ne [int64]$artifact.byteCount) {
        $bundleArtifactErrors += "Retained artifact identity mismatch: $($artifact.relativePath)"
    }
    [void]$aggregateBuilder.Append([string]$artifact.relativePath).Append("`n").Append([string]$artifact.sha256).Append("`n")
}
$computedBundleAggregate = Get-StringSha256 $aggregateBuilder.ToString()
$bundleFileCount = @(Get-ChildItem -LiteralPath $bundleRoot -File -Recurse).Count
$actualHashes.bundleAggregate = $computedBundleAggregate
if ($computedBundleAggregate -ne $expectedHashes.bundleAggregate) {
    $bundleArtifactErrors += "Retained bundle aggregate mismatch: $computedBundleAggregate"
}

# Gate 2-11 retained passing state.
$requiredPassingSummaries = @(
    'Gate2_Unity.summary.json',
    'Gate2_Smoke.summary.json',
    'Gate3_AStar_Compile.summary.json',
    'Gate3_AStar.summary.json',
    'Gate4_ScenarioIO_Compile.summary.json',
    'Gate4_ScenarioWorkload.summary.json',
    'Gate5_BatchFixture_Final.summary.json',
    'Gate5_BatchPipeline.summary.json',
    'Gate6_FinalAudit.summary.json',
    'Gate7_FinalAudit.summary.json',
    'Gate8_FinalAudit.summary.json',
    'Gate9_FinalAudit.summary.json',
    'Gate10_FinalAudit.summary.json',
    'Gate11_FinalAudit.summary.json'
)
$retainedSummaryErrors = @()
$retainedSummaryHashes = [ordered]@{}
foreach ($name in $requiredPassingSummaries) {
    $path = Join-Path $scriptDirectory $name
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        $retainedSummaryErrors += "Missing retained summary: $name"
        continue
    }
    try {
        $value = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
        $retainedSummaryHashes[$name] = Get-LowerSha256 $path
        if ($value.passed -ne $true) { $retainedSummaryErrors += "Retained summary is not passing: $name" }
    } catch {
        $retainedSummaryErrors += "Retained summary could not be parsed: $name - $($_.Exception.Message)"
    }
}

# Validate pilot-level identities, environment snapshots and analysis artifact hashes.
$pilotIdentityErrors = @()
if ($pilot.schemaVersion -ne 1 -or $pilot.pilotManifestId -ne 'gate12-pilot-manifest-v1') { $pilotIdentityErrors += 'Pilot manifest identity/schema mismatch.' }
if ($pilot.classification -ne 'isolated-non-formal-pilot-v1' -or $pilot.formalCampaign -ne $false -or $pilot.gate13ExecutionAuthorized -ne $false -or $pilot.gate13ResultsPermitted -ne $false) { $pilotIdentityErrors += 'Pilot manifest classification or authorization boundary mismatch.' }
if ($pilot.completed -ne $true -or $pilot.measuredCampaignCount -ne 12 -or $pilot.measuredUnityProcessCount -ne 256 -or $pilot.warmupUnityProcessCount -ne 16 -or $pilot.totalUnityProcessCount -ne 272) { $pilotIdentityErrors += 'Pilot completion/process counts mismatch.' }
if ($pilot.technicalInvalidityCount -ne 0 -or $pilot.autoRetryCount -ne 0 -or @($pilot.monitoringEvents).Count -ne 0) { $pilotIdentityErrors += 'Pilot technical-invalidity, retry, or monitoring-event state mismatch.' }
if ($pilot.frozenSpecificationSha256 -ne $expectedHashes.specification -or $pilot.frozenTestDesignSha256 -ne $expectedHashes.testDesign -or $pilot.frozenPilotPlanSha256 -ne $expectedHashes.pilotPlan) { $pilotIdentityErrors += 'Pilot frozen specification/test/plan identities mismatch.' }
if ($pilot.bundleBefore.orderedAggregateSha256 -ne $expectedHashes.bundleAggregate -or $pilot.bundleAfter.orderedAggregateSha256 -ne $expectedHashes.bundleAggregate -or $pilot.bundleBefore.passed -ne $true -or $pilot.bundleAfter.passed -ne $true) { $pilotIdentityErrors += 'Pilot before/after retained-bundle snapshot mismatch.' }
if ($pilotCheckpoint.status -ne 'pilot-completed-analysis-pending' -or $pilotCheckpoint.formalCampaign -ne $false -or $pilotCheckpoint.completedMeasuredCampaignCount -ne 12 -or $pilotCheckpoint.completedMeasuredUnityProcessCount -ne 256) { $pilotIdentityErrors += 'Runner completion checkpoint mismatch.' }

$environmentErrors = @()
foreach ($environment in @($environmentStart, $environmentPostWarmup, $environmentEnd)) {
    if ($environment.preflightVerdict.passed -ne $true -or $environment.frozenHashesMatch -ne $true -or $environment.unityProcessCount -ne 0 -or $environment.unityLockfilePresent -ne $false) {
        $environmentErrors += "Environment phase failed or was unclean: $($environment.phase)"
    }
}
if ($environmentStart.acLineStatus -ne 1 -or $environmentPostWarmup.acLineStatus -ne 1 -or $environmentEnd.acLineStatus -ne 1) { $environmentErrors += 'AC power was not continuously reported online.' }

$analysisArtifactErrors = @()
$analysisArtifacts = [ordered]@{
    noiseAnalysis = [ordered]@{ path = $noisePath; expected = $analysisManifest.noiseAnalysisSha256 }
    candidateSampleSizes = [ordered]@{ path = $candidatePath; expected = $analysisManifest.candidateSampleSizesSha256 }
    budgetFeasibility = [ordered]@{ path = $budgetPath; expected = $analysisManifest.budgetFeasibilitySha256 }
    validationReport = [ordered]@{ path = Join-Path $pilotRoot $analysisManifest.validationReportFile; expected = $analysisManifest.validationReportSha256 }
}
foreach ($entry in $analysisArtifacts.GetEnumerator()) {
    $actual = Get-LowerSha256 $entry.Value.path
    if ($actual -ne $entry.Value.expected) { $analysisArtifactErrors += "$($entry.Key) hash mismatch: expected $($entry.Value.expected), actual $actual" }
}
if ($analysisManifest.completed -ne $true -or $analysisManifest.formalCampaignStarted -ne $false -or $analysisManifest.gate13Authorized -ne $false -or $analysisManifest.measuredSampleCount -ne 256 -or $analysisManifest.warmupSampleCount -ne 16 -or $analysisManifest.warmupExcluded -ne $true -or $analysisManifest.technicalInvalidityCount -ne 0) { $analysisArtifactErrors += 'Analysis manifest completion, authorization, sample, or invalidity state mismatch.' }
if ($analysisManifest.pilotManifestSha256 -ne $expectedHashes.pilotManifest -or $analysisManifest.analyzerSha256 -ne $expectedHashes.analyzer -or $analysisManifest.analysisModuleSha256 -ne $expectedHashes.analysisModule) { $analysisArtifactErrors += 'Analysis input/tool identity mismatch.' }

# Deep campaign and all 272 child-process identity/hash validation.
$campaignErrors = @()
$childErrors = @()
$compilerErrorMatches = @()
$sampleRecords = New-Object System.Collections.Generic.List[object]
$allRunIds = New-Object System.Collections.Generic.List[string]
$measuredRunIds = New-Object System.Collections.Generic.List[string]
$warmupRunIds = New-Object System.Collections.Generic.List[string]
$operationsLineCount = 0
$unityLogCount = 0
$runSummaryCount = 0
$campaignEntries = @($pilot.warmup) + @($pilot.measuredCampaigns)
foreach ($campaignEntry in $campaignEntries) {
    $campaignManifestPath = Resolve-ProjectRelativePath $campaignEntry.campaignManifestRelativePath
    $wrapperSummaryPath = Resolve-ProjectRelativePath $campaignEntry.wrapperSummaryRelativePath
    $stdoutPath = Resolve-ProjectRelativePath $campaignEntry.stdoutRelativePath
    $stderrPath = Resolve-ProjectRelativePath $campaignEntry.stderrRelativePath
    foreach ($identity in @(
        [ordered]@{ label = 'campaign manifest'; path = $campaignManifestPath; expected = $campaignEntry.campaignManifestSha256 },
        [ordered]@{ label = 'wrapper summary'; path = $wrapperSummaryPath; expected = $campaignEntry.wrapperSummarySha256 },
        [ordered]@{ label = 'stdout'; path = $stdoutPath; expected = $campaignEntry.stdoutSha256 },
        [ordered]@{ label = 'stderr'; path = $stderrPath; expected = $campaignEntry.stderrSha256 }
    )) {
        if ((Get-LowerSha256 $identity.path) -ne $identity.expected) { $campaignErrors += "$($campaignEntry.campaignId) $($identity.label) hash mismatch." }
    }
    $campaignManifest = Get-Content -LiteralPath $campaignManifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $wrapper = Get-Content -LiteralPath $wrapperSummaryPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $expectedSamples = [int]$campaignEntry.sampleCount
    if ($campaignManifest.campaignId -ne $campaignEntry.campaignId -or $campaignManifest.comparisonCohortId -ne $campaignEntry.comparisonCohortId -or $campaignManifest.scenarioId -ne $campaignEntry.scenarioId -or $campaignManifest.formalCampaign -ne $false -or $campaignManifest.completed -ne $true) { $campaignErrors += "$($campaignEntry.campaignId) manifest identity/completion mismatch." }
    if ($campaignManifest.sampleCount -ne $expectedSamples -or @($campaignManifest.schedule).Count -ne $expectedSamples -or $campaignManifest.positionBalanced -ne $true -or $campaignManifest.orderedPredecessorBalanced -ne $true) { $campaignErrors += "$($campaignEntry.campaignId) sample count or Williams balance mismatch." }
    if ($wrapper.passed -ne $true -or $wrapper.campaignManifestSha256 -ne $campaignEntry.campaignManifestSha256 -or $wrapper.campaign.completed -ne $true -or $wrapper.campaign.formalCampaign -ne $false) { $campaignErrors += "$($campaignEntry.campaignId) wrapper result mismatch." }

    $campaignDirectory = Split-Path -Parent $campaignManifestPath
    foreach ($schedule in @($campaignManifest.schedule)) {
        $runDirectory = Join-Path $campaignDirectory ([string]$schedule.directory).Replace('/', '\')
        $manifestPath = Join-Path $campaignDirectory ([string]$schedule.manifestFile).Replace('/', '\')
        $workloadPath = Join-Path $campaignDirectory ([string]$schedule.workloadResultFile).Replace('/', '\')
        $operationsPath = Join-Path $runDirectory 'operations.jsonl'
        $canonicalPath = Join-Path $runDirectory 'scenario.canonical.json'
        $runSummaryPath = "$runDirectory.summary.json"
        $unityLogPath = "$runDirectory.Unity.log"
        foreach ($path in @($manifestPath, $workloadPath, $operationsPath, $canonicalPath, $runSummaryPath, $unityLogPath)) {
            if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { $childErrors += "Missing child artifact for $($schedule.runId): $path" }
        }
        if ((Get-LowerSha256 $manifestPath) -ne $schedule.manifestSha256) { $childErrors += "$($schedule.runId) schedule manifest hash mismatch." }
        if ((Get-LowerSha256 $workloadPath) -ne $schedule.workloadResultSha256) { $childErrors += "$($schedule.runId) schedule workload hash mismatch." }
        if ((Get-LowerSha256 $operationsPath) -ne $schedule.operationsJsonlSha256) { $childErrors += "$($schedule.runId) schedule operations hash mismatch." }

        $runManifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $workload = Get-Content -LiteralPath $workloadPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $runSummary = Get-Content -LiteralPath $runSummaryPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $runSummaryCount++
        $unityLogCount++
        if ($runManifest.runId -ne $schedule.runId -or $runManifest.algorithmId -ne $schedule.algorithmId -or $runManifest.comparisonCohortId -ne $campaignEntry.comparisonCohortId -or $runManifest.completed -ne $true) { $childErrors += "$($schedule.runId) run manifest identity/completion mismatch." }
        if ($runManifest.workloadResultSha256 -ne $schedule.workloadResultSha256 -or $runManifest.operationsJsonlSha256 -ne $schedule.operationsJsonlSha256 -or (Get-LowerSha256 $canonicalPath) -ne $runManifest.canonicalScenarioSha256) { $childErrors += "$($schedule.runId) run manifest child hash mismatch." }
        if ($workload.runId -ne $schedule.runId -or $workload.algorithmId -ne $schedule.algorithmId -or $workload.scenarioId -ne $campaignEntry.scenarioId -or $workload.comparisonCohortId -ne $campaignEntry.comparisonCohortId -or $workload.completed -ne $true) { $childErrors += "$($schedule.runId) workload identity/completion mismatch." }
        if ($runSummary.passed -ne $true -or $runSummary.exitCode -ne 0 -or $runSummary.compilerErrorMatchCount -ne 0 -or $runSummary.manifest.runId -ne $schedule.runId) { $childErrors += "$($schedule.runId) Unity wrapper/compile status mismatch." }

        $expectedSequence = 0
        foreach ($line in [System.IO.File]::ReadLines($operationsPath, [System.Text.Encoding]::UTF8)) {
            $record = $line | ConvertFrom-Json
            if ($record.sequence -ne $expectedSequence -or $record.runId -ne $schedule.runId) { $childErrors += "$($schedule.runId) JSONL sequence/identity mismatch at expected sequence $expectedSequence."; break }
            $expectedSequence++
            $operationsLineCount++
        }
        if ($expectedSequence -ne $runManifest.writtenLogRecords -or $runManifest.writtenLogRecords -ne $runManifest.enqueuedLogRecords) { $childErrors += "$($schedule.runId) JSONL/log-record count mismatch." }

        foreach ($match in @(Select-String -LiteralPath $unityLogPath -Pattern @('error CS\d{4}:', 'Scripts have compiler errors', 'Compilation failed', 'executeMethod.+could not be found', 'Unhandled Exception:', 'NullReferenceException', 'Aborting batchmode due to failure') -AllMatches)) {
            $compilerErrorMatches += [ordered]@{ log = $unityLogPath; line = $match.LineNumber; text = $match.Line.Trim() }
        }

        [void]$allRunIds.Add([string]$schedule.runId)
        $isWarmup = $campaignEntry.role -eq 'thermal-warmup-excluded'
        if ($isWarmup) { [void]$warmupRunIds.Add([string]$schedule.runId) }
        else {
            [void]$measuredRunIds.Add([string]$schedule.runId)
            $endpoint = [double]$workload.dynamicHandlingMillisecondsPerScheduledEvent
            if ($endpoint -le 0) { $childErrors += "$($schedule.runId) has non-positive primary endpoint." }
            [void]$sampleRecords.Add([pscustomobject]@{
                runId = [string]$schedule.runId
                campaignId = [string]$campaignEntry.campaignId
                scenarioId = [string]$workload.scenarioId
                comparisonCohortId = [string]$workload.comparisonCohortId
                algorithmId = [string]$workload.algorithmId
                endpoint = $endpoint
                planOperationCount = [int]$workload.planOperationCount
                repairOperationCount = [int]$workload.repairOperationCount
                budgetExceededOperationCount = [int]$workload.budgetExceededOperationCount
                noPathPlanCount = [int]$workload.noPathPlanCount
                budgetExceededPlanCount = [int]$workload.budgetExceededPlanCount
                invalidPlanCount = [int]$workload.invalidPlanCount
                failedPlanCount = [int]$workload.failedPlanCount
            })
        }
    }
}
$uniqueRunIds = @($allRunIds | Sort-Object -Unique)
$overlapRunIds = @($warmupRunIds | Where-Object { $measuredRunIds -contains $_ })

# Independent family sigma and sample-size recomputation from raw workload results.
$familyRecomputations = @()
$statisticalErrors = @()
foreach ($family in @($plan.analysis.families)) {
    $cellRows = @()
    $familyRecords = @($sampleRecords | Where-Object { $_.comparisonCohortId -eq $family.comparisonCohortId -and $family.algorithms -contains $_.algorithmId })
    $groups = @($familyRecords | Group-Object scenarioId, algorithmId)
    foreach ($group in $groups) {
        $records = @($group.Group)
        $logValues = [double[]]@($records | ForEach-Object { [Math]::Log([double]$_.endpoint) })
        $sigma = Get-SampleStandardDeviation $logValues
        $first = $records[0]
        $cellRows += [pscustomobject]@{
            cellId = "$($family.comparisonCohortId)::$($first.scenarioId)::$($first.algorithmId)"
            scenarioId = $first.scenarioId
            algorithmId = $first.algorithmId
            repetitionCount = $records.Count
            sigmaLog = $sigma
        }
        if ($records.Count -ne 8) { $statisticalErrors += "$($family.familyId) cell $($first.scenarioId)/$($first.algorithmId) has $($records.Count), expected 8." }
    }
    $orderedCells = @($cellRows | Sort-Object @{ Expression = 'sigmaLog'; Descending = $true }, @{ Expression = 'cellId'; Descending = $false })
    if ($orderedCells.Count -eq 0) { $statisticalErrors += "$($family.familyId) has no independently selectable cells."; continue }
    $sigmaLog = [double]$orderedCells[0].sigmaLog
    $nRaw = [int][Math]::Ceiling([Math]::Pow((1.96 * $sigmaLog / [Math]::Log(1.05)), 2.0))
    $minimumAdjusted = [Math]::Max(30, $nRaw)
    $required = [int](4 * [Math]::Ceiling($minimumAdjusted / 4.0))
    $candidate = [int][Math]::Min(100, $required)
    $status = if ($required -gt 100) { 'blocked-amendment-required' } else { 'within-cap' }
    $reportedFamily = @($noise.familyResults | Where-Object familyId -eq $family.familyId)
    $reportedCandidate = @($candidates.families | Where-Object familyId -eq $family.familyId)
    if ($reportedFamily.Count -ne 1 -or $reportedCandidate.Count -ne 1) { $statisticalErrors += "$($family.familyId) report multiplicity mismatch."; continue }
    if (-not (Test-Near $reportedFamily[0].sigmaLog $sigmaLog) -or $reportedFamily[0].governingCellId -ne $orderedCells[0].cellId -or $reportedFamily[0].sampleSize.nRaw -ne $nRaw -or $reportedFamily[0].sampleSize.requiredNFormal -ne $required -or $reportedFamily[0].sampleSize.candidateNFormal -ne $candidate -or $reportedFamily[0].sampleSize.precisionStatus -ne $status) { $statisticalErrors += "$($family.familyId) noise/sample-size report differs from independent recomputation." }
    if (-not (Test-Near $reportedCandidate[0].sigmaLog $sigmaLog) -or $reportedCandidate[0].nRaw -ne $nRaw -or $reportedCandidate[0].requiredNFormal -ne $required -or $reportedCandidate[0].candidateNFormal -ne $candidate -or $reportedCandidate[0].precisionStatus -ne $status) { $statisticalErrors += "$($family.familyId) candidate report differs from independent recomputation." }
    $familyRecomputations += [ordered]@{
        familyId = [string]$family.familyId
        measuredSampleCount = $familyRecords.Count
        cellCount = $orderedCells.Count
        repetitionsPerCell = 8
        sigmaLog = $sigmaLog
        governingCellId = $orderedCells[0].cellId
        nRaw = $nRaw
        requiredNFormal = $required
        candidateNFormal = $candidate
        precisionStatus = $status
    }
}

# Independent outer-wall, storage and operational budget recomputation.
$budgetErrors = @()
$wallPerProcess = [double[]]@($pilot.measuredCampaigns | ForEach-Object { [double]$_.wallSeconds / [double]$_.sampleCount })
$bytesPerProcess = [double[]]@($pilot.measuredCampaigns | ForEach-Object { [double]$_.outputBytes / [double]$_.sampleCount })
$medianWall = Get-Median $wallPerProcess
$p95Wall = Get-NearestRankPercentile $wallPerProcess 0.95
$medianBytes = Get-Median $bytesPerProcess
$p95Bytes = Get-NearestRankPercentile $bytesPerProcess 0.95
$familyById = @{}
foreach ($row in $familyRecomputations) { $familyById[$row.familyId] = $row }
$candidateProcessCount = 32 * 2 * [int]$familyById['P1-DL-vs-A-shared'].candidateNFormal + 21 * 2 * [int]$familyById['P2-DL-vs-A-hetero'].candidateNFormal + 32 * 2 * [int]$familyById['P3-IDFF-vs-CFF-shared'].candidateNFormal + 21 * 2 * [int]$familyById['P4-IDFF-vs-CFF-grouped'].candidateNFormal
$requiredProcessCount = 32 * 2 * [int]$familyById['P1-DL-vs-A-shared'].requiredNFormal + 21 * 2 * [int]$familyById['P2-DL-vs-A-hetero'].requiredNFormal + 32 * 2 * [int]$familyById['P3-IDFF-vs-CFF-shared'].requiredNFormal + 21 * 2 * [int]$familyById['P4-IDFF-vs-CFF-grouped'].requiredNFormal
$candidateMedianHours = $candidateProcessCount * $medianWall / 3600.0
$candidateP95Hours = $candidateProcessCount * $p95Wall / 3600.0
$candidateMedianGiB = $candidateProcessCount * $medianBytes / [Math]::Pow(1024.0, 3.0)
$candidateP95GiB = $candidateProcessCount * $p95Bytes / [Math]::Pow(1024.0, 3.0)
$requiredP95Hours = $requiredProcessCount * $p95Wall / 3600.0
$requiredP95GiB = $requiredProcessCount * $p95Bytes / [Math]::Pow(1024.0, 3.0)
$projectedHeadroom = [double]$environmentEnd.freeOutputDriveGiB - $candidateP95GiB
$budgetComparisons = [ordered]@{
    observedMedianWall = Test-Near $budget.observed.medianWallSecondsPerProcess $medianWall
    observedP95Wall = Test-Near $budget.observed.p95WallSecondsPerProcess $p95Wall
    observedMedianBytes = Test-Near $budget.observed.medianBytesPerProcess $medianBytes
    observedP95Bytes = Test-Near $budget.observed.p95BytesPerProcess $p95Bytes
    candidateProcessCount = $budget.candidateProjection.unityProcessCount -eq $candidateProcessCount
    candidateMedianHours = Test-Near $budget.candidateProjection.medianWallHours $candidateMedianHours
    candidateP95Hours = Test-Near $budget.candidateProjection.p95WallHours $candidateP95Hours
    candidateMedianGiB = Test-Near $budget.candidateProjection.medianOutputGiB $candidateMedianGiB
    candidateP95GiB = Test-Near $budget.candidateProjection.p95OutputGiB $candidateP95GiB
    candidateHeadroom = Test-Near $budget.candidateProjection.p95ProjectedHeadroomGiB $projectedHeadroom
    requiredProcessCount = $budget.uncappedRequiredProjection.unityProcessCount -eq $requiredProcessCount
    requiredP95Hours = Test-Near $budget.uncappedRequiredProjection.p95WallHours $requiredP95Hours
    requiredP95GiB = Test-Near $budget.uncappedRequiredProjection.p95OutputGiB $requiredP95GiB
}
foreach ($entry in $budgetComparisons.GetEnumerator()) { if (-not $entry.Value) { $budgetErrors += "Budget recomputation mismatch: $($entry.Key)" } }

$operationTotals = [ordered]@{
    totalPlanOperations = [int64](($sampleRecords | Measure-Object planOperationCount -Sum).Sum)
    totalRepairOperations = [int64](($sampleRecords | Measure-Object repairOperationCount -Sum).Sum)
    totalBudgetExceededOperations = [int64](($sampleRecords | Measure-Object budgetExceededOperationCount -Sum).Sum)
    totalNoPathPlans = [int64](($sampleRecords | Measure-Object noPathPlanCount -Sum).Sum)
    totalBudgetExceededPlans = [int64](($sampleRecords | Measure-Object budgetExceededPlanCount -Sum).Sum)
    totalInvalidPlans = [int64](($sampleRecords | Measure-Object invalidPlanCount -Sum).Sum)
    totalFailedPlans = [int64](($sampleRecords | Measure-Object failedPlanCount -Sum).Sum)
}
foreach ($key in $operationTotals.Keys) {
    if ($operationTotals[$key] -ne [int64]$budget.operationalResults.$key) { $budgetErrors += "Operational total mismatch: $key" }
}
if ($budget.technicalBudgetFeasible -ne $false -or $budget.checks.candidateP95WallWithin168Hours -ne $true -or $budget.checks.candidateStorageLeaves20GiB -ne $false -or $budget.checks.noCampaignHardTimeout -ne $true -or $budget.checks.noTechnicalInvalidity -ne $true -or $budget.formalCampaignStarted -ne $false) { $budgetErrors += 'Budget readiness/check state mismatch.' }

# Parse all Research PowerShell/JSON/JSONL evidence, including archived failed attempts.
$powerShellFiles = @(Get-ChildItem -LiteralPath (Join-Path $ProjectPath 'Research') -Filter '*.ps1' -File -Recurse)
$powerShellParseErrors = @()
foreach ($file in $powerShellFiles) {
    $tokens = $null
    $parseErrors = $null
    # Windows PowerShell 5.1 ParseFile uses its legacy code-page rules for
    # UTF-8 files without a BOM.  Parse the explicitly decoded UTF-8 source so
    # non-ASCII research documentation cannot create false syntax failures.
    $sourceText = Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8
    [System.Management.Automation.Language.Parser]::ParseInput($sourceText, $file.FullName, [ref]$tokens, [ref]$parseErrors) | Out-Null
    foreach ($parseError in @($parseErrors)) { $powerShellParseErrors += [ordered]@{ file = $file.FullName; message = $parseError.Message; extent = $parseError.Extent.Text } }
}
$jsonFiles = @(Get-ChildItem -LiteralPath (Join-Path $ProjectPath 'Research') -Filter '*.json' -File -Recurse | Where-Object { $_.FullName -ne $summaryPath })
$jsonParseErrors = @()
foreach ($file in $jsonFiles) {
    try { Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8 | ConvertFrom-Json | Out-Null }
    catch { $jsonParseErrors += [ordered]@{ file = $file.FullName; message = $_.Exception.Message } }
}
$jsonlFiles = @(Get-ChildItem -LiteralPath (Join-Path $ProjectPath 'Research') -Filter '*.jsonl' -File -Recurse)
$jsonlParseErrors = @()
$parsedJsonlLineCount = 0
foreach ($file in $jsonlFiles) {
    $lineNumber = 0
    foreach ($line in [System.IO.File]::ReadLines($file.FullName, [System.Text.Encoding]::UTF8)) {
        $lineNumber++
        $parsedJsonlLineCount++
        try { $line | ConvertFrom-Json | Out-Null }
        catch { $jsonlParseErrors += [ordered]@{ file = $file.FullName; line = $lineNumber; message = $_.Exception.Message } }
    }
}

# Gate 13 boundary and current process/lock cleanliness.
$formalTrueFiles = @()
foreach ($file in @(Get-ChildItem -LiteralPath $pilotRoot -Filter '*.json' -File -Recurse)) {
    if (Select-String -LiteralPath $file.FullName -Pattern '"formalCampaign"\s*:\s*true|"gate13ExecutionAuthorized"\s*:\s*true|"gate13Authorized"\s*:\s*true' -Quiet) { $formalTrueFiles += $file.FullName }
}
$gate13OutputRoot = Join-Path $ProjectPath 'Research\PilotRuns\Gate13'
$unexpectedFormalDirectories = @(Get-ChildItem -LiteralPath $pilotRoot -Directory -Recurse | Where-Object { $_.Name -match '^(formal|gate13)' } | Select-Object -ExpandProperty FullName)
$unityProcesses = @(Get-Process -Name Unity -ErrorAction SilentlyContinue)
$unityLockfilePath = Join-Path $ProjectPath 'Temp\UnityLockfile'
$unityLockfilePresent = Test-Path -LiteralPath $unityLockfilePath

$checks = [ordered]@{
    frozenGate12HashesMatch = $frozenHashErrors.Count -eq 0
    preImplementationAuditPassed = $preAudit.passed -eq $true -and $preAudit.baselineChecked -eq 24 -and $preAudit.computedBundleAggregateSha256 -eq $expectedHashes.bundleAggregate
    analysisUnitTestsPassed63 = $unitTests.passed -eq $true -and $unitTests.assertionCount -eq 63 -and @($unitTests.failures).Count -eq 0 -and $unitTests.moduleSha256 -eq $expectedHashes.analysisModule -and $unitTests.frozenPlanSha256 -eq $expectedHashes.pilotPlan
    originalBaseline24Of24 = $baselineChecked -eq 24 -and $baselineMismatches.Count -eq 0
    retainedBundle56ArtifactsUnchanged = $bundleManifest.artifacts.Count -eq 56 -and $bundleFileCount -eq 57 -and $bundleArtifactErrors.Count -eq 0 -and $computedBundleAggregate -eq $expectedHashes.bundleAggregate
    gate2Through11RetainedStatePassing = $retainedSummaryErrors.Count -eq 0
    environmentPreflightAllPassing = $environmentErrors.Count -eq 0
    pilotManifestCompleteAndNonFormal = $pilotIdentityErrors.Count -eq 0
    analysisArtifactsHashValid = $analysisArtifactErrors.Count -eq 0
    all13CampaignsCompleteAndBalanced = $campaignEntries.Count -eq 13 -and $campaignErrors.Count -eq 0
    all272ChildIdentitiesAndHashesValid = $allRunIds.Count -eq 272 -and $uniqueRunIds.Count -eq 272 -and $measuredRunIds.Count -eq 256 -and $warmupRunIds.Count -eq 16 -and $overlapRunIds.Count -eq 0 -and $childErrors.Count -eq 0
    warmupExcludedFrom256Measured = $pilot.warmup.analysisExcluded -eq $true -and $noise.warmupExcluded -eq $true -and $noise.measuredSampleCount -eq 256 -and $sampleRecords.Count -eq 256
    independentFourFamilyRecomputeMatches = $familyRecomputations.Count -eq 4 -and $statisticalErrors.Count -eq 0
    candidateValuesAreCapOnlyAndBlocked = @($familyRecomputations | Where-Object { $_.candidateNFormal -eq 100 -and $_.requiredNFormal -gt 100 -and $_.precisionStatus -eq 'blocked-amendment-required' }).Count -eq 4 -and $candidates.gate13PrecisionReadiness -eq 'blocked-versioned-amendment-required'
    independentBudgetRecomputeMatches = $budgetErrors.Count -eq 0
    storageFeasibilityBlocksGate13 = $candidateP95Hours -le 168.0 -and $projectedHeadroom -lt 20.0 -and $budget.technicalBudgetFeasible -eq $false
    powerShellParses = $powerShellParseErrors.Count -eq 0
    jsonParses = $jsonParseErrors.Count -eq 0
    jsonlParses = $jsonlParseErrors.Count -eq 0
    all272UnityLogsClean = $unityLogCount -eq 272 -and $runSummaryCount -eq 272 -and $compilerErrorMatches.Count -eq 0
    noTechnicalInvalidityOrAutoRetry = $pilot.technicalInvalidityCount -eq 0 -and $pilot.autoRetryCount -eq 0 -and $analysisManifest.technicalInvalidityCount -eq 0
    noGate13OrFormalOutput = -not (Test-Path -LiteralPath $gate13OutputRoot) -and $formalTrueFiles.Count -eq 0 -and $unexpectedFormalDirectories.Count -eq 0 -and $analysisManifest.formalCampaignStarted -eq $false
    noUnityProcess = $unityProcesses.Count -eq 0
    noUnityLockfile = -not $unityLockfilePresent
}
$failedChecks = @($checks.GetEnumerator() | Where-Object { -not $_.Value } | ForEach-Object { $_.Key })
$passed = $failedChecks.Count -eq 0

$summary = [ordered]@{
    schemaVersion = 1
    auditId = 'gate12-final-audit-v1'
    savedAt = (Get-Date).ToString('o')
    projectPath = $ProjectPath
    classification = 'isolated-non-formal-pilot-final-audit-v1'
    expectedHashes = $expectedHashes
    actualHashes = $actualHashes
    frozenHashErrors = $frozenHashErrors
    baselineChecked = $baselineChecked
    baselineMismatches = $baselineMismatches
    retainedBundle = [ordered]@{
        fileCount = $bundleFileCount
        artifactCount = $bundleManifest.artifacts.Count
        manifestSha256 = $actualHashes.bundleManifest
        orderedAggregateSha256 = $computedBundleAggregate
        artifactErrors = $bundleArtifactErrors
        beforeMatchesAfter = $pilot.bundleBefore.orderedAggregateSha256 -eq $pilot.bundleAfter.orderedAggregateSha256
    }
    retainedPassingSummaryCount = $requiredPassingSummaries.Count
    retainedSummaryHashes = $retainedSummaryHashes
    retainedSummaryErrors = $retainedSummaryErrors
    processCounts = [ordered]@{
        campaignCount = $campaignEntries.Count
        warmupCampaignCount = 1
        measuredCampaignCount = $pilot.measuredCampaignCount
        warmupUnityProcessCount = $warmupRunIds.Count
        measuredUnityProcessCount = $measuredRunIds.Count
        totalUnityProcessCount = $allRunIds.Count
        uniqueRunIdCount = $uniqueRunIds.Count
        operationsLineCount = $operationsLineCount
    }
    campaignErrors = $campaignErrors
    childErrors = $childErrors
    familyRecomputations = $familyRecomputations
    statisticalErrors = $statisticalErrors
    budgetRecomputation = [ordered]@{
        observedMedianWallSecondsPerProcess = $medianWall
        observedP95WallSecondsPerProcess = $p95Wall
        observedMedianBytesPerProcess = $medianBytes
        observedP95BytesPerProcess = $p95Bytes
        candidateUnityProcessCount = $candidateProcessCount
        candidateMedianWallHours = $candidateMedianHours
        candidateP95WallHours = $candidateP95Hours
        candidateMedianOutputGiB = $candidateMedianGiB
        candidateP95OutputGiB = $candidateP95GiB
        outputDriveFreeGiBBeforeAnalysis = [double]$environmentEnd.freeOutputDriveGiB
        candidateP95ProjectedHeadroomGiB = $projectedHeadroom
        uncappedRequiredUnityProcessCount = $requiredProcessCount
        uncappedRequiredP95WallHours = $requiredP95Hours
        uncappedRequiredP95OutputGiB = $requiredP95GiB
        operationTotals = $operationTotals
        comparisons = $budgetComparisons
        errors = $budgetErrors
    }
    parserCoverage = [ordered]@{
        powerShellScriptCount = $powerShellFiles.Count
        powerShellParseErrors = $powerShellParseErrors
        jsonFileCount = $jsonFiles.Count
        jsonParseErrors = $jsonParseErrors
        jsonlFileCount = $jsonlFiles.Count
        jsonlLineCount = $parsedJsonlLineCount
        jsonlParseErrors = $jsonlParseErrors
    }
    unityLogCount = $unityLogCount
    runSummaryCount = $runSummaryCount
    compilerErrorMatches = $compilerErrorMatches
    technicalInvalidityCount = $pilot.technicalInvalidityCount
    autoRetryCount = $pilot.autoRetryCount
    formalTrueFiles = $formalTrueFiles
    unexpectedFormalDirectories = $unexpectedFormalDirectories
    gate13OutputRootPresent = Test-Path -LiteralPath $gate13OutputRoot
    unityProcessIds = @($unityProcesses | ForEach-Object { $_.Id })
    unityLockfilePresent = $unityLockfilePresent
    gate13Readiness = 'blocked-precision-cap-and-storage-versioned-amendment-required'
    gate13Authorized = $false
    gate13Executed = $false
    checks = $checks
    failedChecks = $failedChecks
    passed = $passed
}

# Prove that the exact summary object is JSON-serializable before saving it.
$summaryJson = $summary | ConvertTo-Json -Depth 16
$summaryJson | ConvertFrom-Json | Out-Null
Write-Utf8NoBomJson -Path $summaryPath -Value $summary -Depth 16
$summary | ConvertTo-Json -Depth 16
if (-not $passed) { Write-Error "Gate 12 final audit failed. Review $summaryPath."; exit 1 }
Write-Host 'Gate 12 final audit passed.' -ForegroundColor Green
exit 0
