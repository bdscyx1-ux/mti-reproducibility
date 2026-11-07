[CmdletBinding()]
param(
    [string]$ProjectPath
)

$ErrorActionPreference = 'Stop'
$scriptDirectory = Split-Path -Parent $MyInvocation.MyCommand.Path
if ([string]::IsNullOrWhiteSpace($ProjectPath)) { $ProjectPath = [System.IO.Path]::GetFullPath((Join-Path $scriptDirectory '..\..')) }
else { $ProjectPath = [System.IO.Path]::GetFullPath($ProjectPath) }
$summaryPath = Join-Path $scriptDirectory 'Gate11_FinalAudit.summary.json'
$bundlePath = Join-Path $ProjectPath 'Research\FormalScenarios\v1'
$manifestPath = Join-Path $bundlePath 'bundle-manifest.json'
$matrixPath = Join-Path $bundlePath 'formal-scenario-matrix.json'
$catalogPath = Join-Path $bundlePath 'catalog.json'
$preregistrationPath = Join-Path $bundlePath 'preregistered-analysis.json'

function Get-LowerSha256([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Get-StringSha256([string]$Value) {
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($Value)
        return ([System.BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-', '').ToLowerInvariant()
    } finally { $sha.Dispose() }
}

# Frozen original preservation.
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
        $baselineMismatches += [ordered]@{ relativePath = $row.relative_path; exists = $exists; expectedBytes = [int64]$row.bytes; actualBytes = $actualBytes; expectedSha256 = $row.sha256; actualSha256 = $actualHash }
    }
}

# Source/evidence syntax and readability.
$powerShellFiles = @(Get-ChildItem -LiteralPath (Join-Path $ProjectPath 'Research') -Filter '*.ps1' -File -Recurse | Sort-Object FullName)
$powerShellParseErrors = @()
foreach ($file in $powerShellFiles) {
    $tokens = $null
    $parseErrors = $null
    [System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$parseErrors) | Out-Null
    foreach ($parseError in @($parseErrors)) { $powerShellParseErrors += [ordered]@{ file = $file.FullName; message = $parseError.Message; extent = $parseError.Extent.Text } }
}
$jsonFiles = @(Get-ChildItem -LiteralPath (Join-Path $ProjectPath 'Research') -Filter '*.json' -File -Recurse)
$jsonParseErrors = @()
foreach ($file in $jsonFiles) {
    try { Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8 | ConvertFrom-Json | Out-Null }
    catch { $jsonParseErrors += [ordered]@{ file = $file.FullName; message = $_.Exception.Message } }
}
$jsonlFiles = @(Get-ChildItem -LiteralPath (Join-Path $ProjectPath 'Research') -Filter '*.jsonl' -File -Recurse)
$jsonlParseErrors = @()
foreach ($file in $jsonlFiles) {
    $lineNumber = 0
    foreach ($line in Get-Content -LiteralPath $file.FullName -Encoding UTF8) {
        $lineNumber++
        try { $line | ConvertFrom-Json | Out-Null }
        catch { $jsonlParseErrors += [ordered]@{ file = $file.FullName; line = $lineNumber; message = $_.Exception.Message } }
    }
}

# Required regression evidence.
$requiredPassingSummaries = @(
    'Gate11_FullRegression_Compile.summary.json',
    'Gate11_HardenedVerificationCompile.summary.json',
    'Gate11_SpecificationAudit.summary.json',
    'Gate11_ScenarioMatrixVerification.summary.json',
    'Gate2_Smoke.summary.json',
    'Gate3_AStar.summary.json',
    'Gate4_ScenarioWorkload.summary.json',
    'Gate5_BatchPipeline.summary.json',
    'Gate6_ReplicationStatistics.summary.json',
    'Gate6_ScenarioCatalog.summary.json',
    'Gate6_ReplicationPipeline.summary.json',
    'Gate6_FinalAudit.summary.json',
    'Gate7_DStarLite.summary.json',
    'Gate7_DStarLite_BatchPipeline.summary.json',
    'Gate7_DStarLite_ReplicationPipeline.summary.json',
    'Gate7_FinalAudit.summary.json',
    'Gate8_CorrectedFlowField.summary.json',
    'Gate8_CFF_BatchPipeline.summary.json',
    'Gate8_CFF_ReplicationPipeline.summary.json',
    'Gate8_FinalAudit.summary.json',
    'Gate9_IncrementalFlowField.summary.json',
    'Gate9_IDFF_BatchPipeline.summary.json',
    'Gate9_IDFF_ReplicationPipeline.summary.json',
    'Gate9_FinalAudit.summary.json',
    'Gate10_SpecificationAudit.summary.json',
    'Gate10_Fairness.summary.json',
    'Gate10_FairCampaignPipeline.summary.json',
    'Gate10_LegacyCompatibility.summary.json',
    'Gate10_FinalAudit.summary.json'
)
$summaryErrors = @()
foreach ($name in $requiredPassingSummaries) {
    $path = Join-Path $scriptDirectory $name
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { $summaryErrors += "Missing summary: $path"; continue }
    try {
        $value = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($value.passed -ne $true) { $summaryErrors += "Summary is not passing: $path" }
    } catch { $summaryErrors += "Summary could not be parsed: $path - $($_.Exception.Message)" }
}

$specAudit = Get-Content -LiteralPath (Join-Path $scriptDirectory 'Gate11_SpecificationAudit.summary.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$generationResult = Get-Content -LiteralPath (Join-Path $scriptDirectory 'Gate11_ScenarioMatrixGeneration.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$initialGenerationSummary = Get-Content -LiteralPath (Join-Path $scriptDirectory 'Gate11_ScenarioMatrixGeneration.summary.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$verificationSummary = Get-Content -LiteralPath (Join-Path $scriptDirectory 'Gate11_ScenarioMatrixVerification.summary.json') -Raw -Encoding UTF8 | ConvertFrom-Json

# Retained bundle identity.
$manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
$matrix = Get-Content -LiteralPath $matrixPath -Raw -Encoding UTF8 | ConvertFrom-Json
$catalog = Get-Content -LiteralPath $catalogPath -Raw -Encoding UTF8 | ConvertFrom-Json
$preregistration = Get-Content -LiteralPath $preregistrationPath -Raw -Encoding UTF8 | ConvertFrom-Json
$artifactErrors = @()
$aggregateBuilder = New-Object System.Text.StringBuilder
# The manifest array is already written in StringComparer.Ordinal order and that
# exact order is part of the aggregate contract. Sort-Object is culture-aware
# and would reorder uppercase "Scenarios/" relative to lowercase config names.
foreach ($artifact in @($manifest.artifacts)) {
    $path = Join-Path $bundlePath ([string]$artifact.relativePath).Replace('/', '\')
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { $artifactErrors += "Missing artifact: $($artifact.relativePath)"; continue }
    $actualHash = Get-LowerSha256 $path
    $actualBytes = (Get-Item -LiteralPath $path).Length
    if ($actualHash -ne $artifact.sha256 -or $actualBytes -ne [int64]$artifact.byteCount) { $artifactErrors += "Artifact identity mismatch: $($artifact.relativePath)" }
    [void]$aggregateBuilder.Append([string]$artifact.relativePath).Append("`n").Append([string]$artifact.sha256).Append("`n")
}
$computedAggregate = Get-StringSha256 $aggregateBuilder.ToString()
$bundleFiles = @(Get-ChildItem -LiteralPath $bundlePath -File -Recurse)
$scenarioFiles = @(Get-ChildItem -LiteralPath (Join-Path $bundlePath 'Scenarios') -Filter '*.scenario.json' -File)
$maximumScenarioBytes = ($scenarioFiles | Measure-Object -Property Length -Maximum).Maximum
$scenarioIds = @($matrix.scenarios | ForEach-Object { [string]$_.scenarioId })
$matrixEntryIds = @($matrix.eligibilityEntries | ForEach-Object { [string]$_.matrixEntryId })
$sharedEligibilityCount = @($matrix.eligibilityEntries | Where-Object comparisonCohortId -eq 'four-algorithm-shared-goal-v1').Count
$perAgentEligibilityCount = @($matrix.eligibilityEntries | Where-Object comparisonCohortId -eq 'per-agent-heterogeneous-goal-v1').Count
$groupedEligibilityCount = @($matrix.eligibilityEntries | Where-Object comparisonCohortId -eq 'grouped-field-heterogeneous-goal-v1').Count

$expectedHashes = [ordered]@{
    specification = '498d3ea8549b234ebaac27658ee9be1ad67051f49e71e131e5b013287f28f4f4'
    testDesign = 'bfb124d8ecf80ef15e8fcf391b4f0b51ee1b27b8a03303afa1b12a1062304b58'
    countErratum = '8b252970d9836dfe1732c7c7df7b0fd743de79d341a52c82234999bfa8fe8197'
    generatorSource = '248ee464d4ddbc900b229ff4f86386308f652f229751aaef7cff6e72fbc981cb'
    matrix = '404df63d38bccd66bb665446e0f2cbf3e5f8c7293f543b3213bde4206435fe9f'
    preregistration = '7e947885c38fcf9307fd9202585dda3b2b5d11334f495428760009a2aa202b5b'
    catalog = '53466889b80c5f75aa124e623155a6abaac7ff91a979b7d2490dade0978baa1d'
    manifest = 'ea596c8c9e6d1ca99e325c05c095024a4813ca1e65c771a8b4db8bf29364c12e'
    aggregate = '91d9e3c66327185e48f68cafb05c674cc49e929adb576973098d0bfebd2e9a88'
    fairness = '42a4a8439c3d7b46b7644bed14b8f91d87bae4c6f8b2183a73609ee5461e82dd'
    workload = '2af12d33c4a010b14511f86d11d2f45634cac794b6763ea1cc36e8f1940a8ea1'
}
$actualHashes = [ordered]@{
    specification = Get-LowerSha256 (Join-Path $ProjectPath 'Research\Formal_Scenario_Matrix_and_Preregistration_Specification.md')
    testDesign = Get-LowerSha256 (Join-Path $ProjectPath 'Research\Gate11_Formal_Scenario_Matrix_Test_Design.md')
    countErratum = Get-LowerSha256 (Join-Path $ProjectPath 'Research\Gate11_Frozen_Count_Erratum.md')
    generatorSource = Get-LowerSha256 (Join-Path $ProjectPath 'Assets\_Scripts\Research\Scenarios\FormalScenarioMatrixGenerator.cs')
    matrix = Get-LowerSha256 $matrixPath
    preregistration = Get-LowerSha256 $preregistrationPath
    catalog = Get-LowerSha256 $catalogPath
    manifest = Get-LowerSha256 $manifestPath
    aggregate = $computedAggregate
    fairness = Get-LowerSha256 (Join-Path $ProjectPath 'Research\Four_Algorithm_Fairness_and_Unified_Campaign_Specification.md')
    workload = Get-LowerSha256 (Join-Path $ProjectPath 'Research\Scenario_IO_and_Planning_Workload_Specification.md')
}
$hashErrors = @()
foreach ($key in $expectedHashes.Keys) { if ($actualHashes[$key] -ne $expectedHashes[$key]) { $hashErrors += "$key expected $($expectedHashes[$key]), actual $($actualHashes[$key])" } }

# Documentation and authorization boundary.
$checkpointPath = Join-Path $ProjectPath 'Research\Gate11_Checkpoint.md'
$nextCheckpointPath = Join-Path $ProjectPath 'Research\Next_Session_Checkpoint.md'
$overallPlanPath = Join-Path $ProjectPath 'Research\Overall_Project_Plan.md'
$checkpointText = Get-Content -LiteralPath $checkpointPath -Raw -Encoding UTF8
$nextCheckpointText = Get-Content -LiteralPath $nextCheckpointPath -Raw -Encoding UTF8
$overallPlanText = Get-Content -LiteralPath $overallPlanPath -Raw -Encoding UTF8
$documentationValid = (
    $checkpointText -match 'Status: complete' -and
    $checkpointText -match 'Gate 12 is not authorized' -and
    $checkpointText -match '1,497,213' -and
    $nextCheckpointText -match 'Gate 11 formal scenario matrix' -and
    $nextCheckpointText -match 'Gate 12.*not authorized' -and
    $overallPlanText -match '版本：1\.6' -and
    $overallPlanText -match 'Gate 11 已完成'
)

$unauthorizedOutputs = @(
    Get-ChildItem -LiteralPath (Join-Path $ProjectPath 'Research') -Recurse -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match '^(Gate12|Gate13)(_|-|$)' -or $_.Name -match '^(FormalCampaign|PilotCampaign)(_|-|$)' } |
        Select-Object -ExpandProperty FullName
)
$unityProcesses = @(Get-Process -Name Unity -ErrorAction SilentlyContinue)
$lockPath = Join-Path $ProjectPath 'Temp\UnityLockfile'
$logs = @(Get-ChildItem -LiteralPath $scriptDirectory -Filter '*.log' -File -Recurse)
$compilerErrorMatches = @()
foreach ($log in $logs) {
    foreach ($match in @(Select-String -LiteralPath $log.FullName -Pattern @('error CS\d{4}', 'Scripts have compiler errors', 'Compilation failed', 'executeMethod.+could not be found') -AllMatches)) {
        if ($log.Name -ne 'Gate10_Fairness_InitialCompile.log') { $compilerErrorMatches += [ordered]@{ log = $log.FullName; line = $match.LineNumber; text = $match.Line.Trim() } }
    }
}

$checks = [ordered]@{
    frozenBaselineMatches = $baselineChecked -eq 24 -and $baselineMismatches.Count -eq 0
    frozenSpecificationIntegrity = $specAudit.passed -eq $true -and $specAudit.auditMode -eq 'post-implementation-frozen-integrity' -and $specAudit.specificationSha256 -eq $expectedHashes.specification -and $specAudit.testDesignSha256 -eq $expectedHashes.testDesign
    generationCommandCompleted = $generationResult.passed -eq $true -and $generationResult.mode -eq 'generate' -and $generationResult.scenarioCount -eq 53 -and $generationResult.eligibilityCount -eq 212 -and $generationResult.sharedScenarioCount -eq 32 -and $generationResult.heterogeneousScenarioCount -eq 21
    countMismatchDiscoveryPreserved = $initialGenerationSummary.passed -eq $false -and $initialGenerationSummary.generationResult.passed -eq $true -and $actualHashes.countErratum -eq $expectedHashes.countErratum
    retainedVerificationPassed = $verificationSummary.passed -eq $true -and $verificationSummary.verificationResult.assertionCount -eq 1497213 -and $verificationSummary.verificationResult.plannerInitializationCount -eq 212 -and $verificationSummary.verificationResult.reachabilityPhaseCount -eq 265 -and $verificationSummary.verificationResult.negativeTestCount -eq 11 -and $verificationSummary.bundleUnchanged -eq $true
    bundleCountsExact = $bundleFiles.Count -eq 57 -and $scenarioFiles.Count -eq 53 -and $manifest.artifacts.Count -eq 56 -and $manifest.scenarios.Count -eq 53 -and $matrix.scenarioCount -eq 53 -and $matrix.eligibilityCount -eq 212 -and $catalog.scenarioCount -eq 53
    eligibilityBreakdownCorrected = $sharedEligibilityCount -eq 128 -and $perAgentEligibilityCount -eq 42 -and $groupedEligibilityCount -eq 42
    identitiesUnique = @($scenarioIds | Sort-Object -Unique).Count -eq 53 -and @($matrixEntryIds | Sort-Object -Unique).Count -eq 212
    artifactHashesAndAggregateMatch = $artifactErrors.Count -eq 0 -and $computedAggregate -eq $manifest.bundleAggregateSha256 -and $computedAggregate -eq $expectedHashes.aggregate
    frozenEvidenceHashesMatch = $hashErrors.Count -eq 0 -and $manifest.generatorSourceSha256 -eq $expectedHashes.generatorSource -and $manifest.fairnessProtocolSha256 -eq $expectedHashes.fairness -and $manifest.workloadSpecificationSha256 -eq $expectedHashes.workload
    strictScenarioSizeBoundary = $maximumScenarioBytes -gt 0 -and $maximumScenarioBytes -le (16 * 1024 * 1024)
    preregistrationComplete = $preregistration.analysisRows.Count -eq 9 -and $preregistration.formalSampleSizeStatus -eq 'unset-until-gate12-v1' -and $preregistration.significanceEarlyStoppingAllowed -eq $false -and $preregistration.trendEarlyStoppingAllowed -eq $false
    noPilotOrFormalExecution = $manifest.pilotExecuted -eq $false -and $manifest.formalCampaignExecuted -eq $false -and $generationResult.pilotExecuted -eq $false -and $generationResult.formalCampaignExecuted -eq $false -and $unauthorizedOutputs.Count -eq 0
    crossGateRegressionPassed = $summaryErrors.Count -eq 0
    powerShellParses = $powerShellParseErrors.Count -eq 0
    jsonParses = $jsonParseErrors.Count -eq 0
    jsonlParses = $jsonlParseErrors.Count -eq 0
    compilerLogsClean = $compilerErrorMatches.Count -eq 0
    checkpointAndPlanCurrent = $documentationValid
    noUnityProcess = $unityProcesses.Count -eq 0
    noUnityLockfile = -not (Test-Path -LiteralPath $lockPath)
}
$failedChecks = @($checks.GetEnumerator() | Where-Object { -not $_.Value } | ForEach-Object { $_.Key })
$passed = $failedChecks.Count -eq 0
$summary = [ordered]@{
    savedAt = (Get-Date).ToString('o')
    projectPath = $ProjectPath
    baselineChecked = $baselineChecked
    baselineMismatches = $baselineMismatches
    specificationAuditMode = $specAudit.auditMode
    initialGenerationWrapperPassed = $initialGenerationSummary.passed
    generationCommandPassed = $generationResult.passed
    verificationAssertionCount = $verificationSummary.verificationResult.assertionCount
    plannerInitializationCount = $verificationSummary.verificationResult.plannerInitializationCount
    reachabilityPhaseCount = $verificationSummary.verificationResult.reachabilityPhaseCount
    negativeTestCount = $verificationSummary.verificationResult.negativeTestCount
    bundleFileCount = $bundleFiles.Count
    scenarioFileCount = $scenarioFiles.Count
    maximumScenarioBytes = $maximumScenarioBytes
    manifestArtifactCount = $manifest.artifacts.Count
    eligibilityCounts = [ordered]@{ shared = $sharedEligibilityCount; perAgentHeterogeneous = $perAgentEligibilityCount; groupedFieldHeterogeneous = $groupedEligibilityCount; total = $matrix.eligibilityCount }
    expectedHashes = $expectedHashes
    actualHashes = $actualHashes
    hashErrors = $hashErrors
    artifactErrors = $artifactErrors
    requiredPassingSummaryCount = $requiredPassingSummaries.Count
    summaryErrors = $summaryErrors
    powerShellScriptCount = $powerShellFiles.Count
    powerShellParseErrors = $powerShellParseErrors
    jsonFileCount = $jsonFiles.Count
    jsonParseErrors = $jsonParseErrors
    jsonlFileCount = $jsonlFiles.Count
    jsonlParseErrors = $jsonlParseErrors
    compilerErrorMatches = $compilerErrorMatches
    unauthorizedOutputs = $unauthorizedOutputs
    unityProcessIds = @($unityProcesses | ForEach-Object { $_.Id })
    unityLockfilePresent = Test-Path -LiteralPath $lockPath
    checks = $checks
    failedChecks = $failedChecks
    passed = $passed
}
$summary | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $summaryPath -Encoding UTF8
$summary | ConvertTo-Json -Depth 12
if (-not $passed) { Write-Error "Gate 11 final audit failed. Review $summaryPath."; exit 1 }
Write-Host 'Gate 11 final audit passed.' -ForegroundColor Green
exit 0
