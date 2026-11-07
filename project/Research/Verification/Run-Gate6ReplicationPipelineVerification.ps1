[CmdletBinding()]
param(
    [string]$FixtureDirectory,
    [string]$ScenarioPath
)

$ErrorActionPreference = 'Stop'
$scriptDirectory = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectPath = [System.IO.Path]::GetFullPath((Join-Path $scriptDirectory '..\..'))
if ([string]::IsNullOrWhiteSpace($FixtureDirectory)) { $FixtureDirectory = Join-Path $scriptDirectory 'Gate6_ReplicationFixture_Final' }
if ([string]::IsNullOrWhiteSpace($ScenarioPath)) { $ScenarioPath = Join-Path $projectPath 'Research\Scenarios\dynamic_corridors_sparse_v1.scenario.json' }
$FixtureDirectory = [System.IO.Path]::GetFullPath($FixtureDirectory)
$ScenarioPath = [System.IO.Path]::GetFullPath($ScenarioPath)
$summaryPath = Join-Path $scriptDirectory 'Gate6_ReplicationPipeline.summary.json'

function Get-LowerSha256([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

$groupManifestPath = Join-Path $FixtureDirectory 'replication-manifest.json'
if (-not (Test-Path -LiteralPath $groupManifestPath -PathType Leaf)) { throw "Gate 6 replication manifest not found: $groupManifestPath" }
$groupManifestHashBeforeGuard = Get-LowerSha256 $groupManifestPath
$manifest = Get-Content -LiteralPath $groupManifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
$requestPath = Join-Path $FixtureDirectory $manifest.aggregationRequestFile
$aggregatePath = Join-Path $FixtureDirectory $manifest.aggregateFile
$aggregationLogPath = Join-Path $FixtureDirectory $manifest.aggregationUnityLogFile
$wrapperSummaryPath = $FixtureDirectory + '.summary.json'
$scenarioSourceSha256 = Get-LowerSha256 $ScenarioPath

$requiredGroupFiles = @($requestPath, $aggregatePath, $aggregationLogPath, $wrapperSummaryPath)
$missingFiles = @($requiredGroupFiles | Where-Object { -not (Test-Path -LiteralPath $_ -PathType Leaf) })
$request = if (Test-Path -LiteralPath $requestPath) { Get-Content -LiteralPath $requestPath -Raw -Encoding UTF8 | ConvertFrom-Json } else { $null }
$aggregate = if (Test-Path -LiteralPath $aggregatePath) { Get-Content -LiteralPath $aggregatePath -Raw -Encoding UTF8 | ConvertFrom-Json } else { $null }
$wrapperSummary = if (Test-Path -LiteralPath $wrapperSummaryPath) { Get-Content -LiteralPath $wrapperSummaryPath -Raw -Encoding UTF8 | ConvertFrom-Json } else { $null }

$compilerPatterns = @('error CS\d{4}', 'Scripts have compiler errors', 'Compilation failed', 'executeMethod.+could not be found')
$aggregationCompilerMatches = if (Test-Path -LiteralPath $aggregationLogPath) { @(Select-String -LiteralPath $aggregationLogPath -Pattern $compilerPatterns -AllMatches) } else { @() }
$aggregationCompletionMarker = if (Test-Path -LiteralPath $aggregationLogPath) { @(Select-String -LiteralPath $aggregationLogPath -SimpleMatch 'DDM replication aggregation completed. Output:').Count -gt 0 } else { $false }

$childErrors = @()
$childRunIds = New-Object System.Collections.Generic.HashSet[string]([System.StringComparer]::Ordinal)
$resultPaths = @()
$results = @()
$totalJsonlRecords = 0
$totalPlannerRecords = 0
$totalLifecycleRecords = 0
$totalWorkloadRecords = 0

foreach ($child in @($manifest.childRuns)) {
    $childDirectory = Join-Path $FixtureDirectory $child.directory
    $childManifestPath = Join-Path $FixtureDirectory $child.manifestFile
    $childUnityLogPath = $childDirectory + '.Unity.log'
    $childSummaryPath = $childDirectory + '.summary.json'
    foreach ($requiredPath in @($childManifestPath, $childUnityLogPath, $childSummaryPath)) {
        if (-not (Test-Path -LiteralPath $requiredPath -PathType Leaf)) { $childErrors += "Missing child file: $requiredPath" }
    }
    if (-not (Test-Path -LiteralPath $childManifestPath -PathType Leaf)) { continue }
    if ((Get-LowerSha256 $childManifestPath) -ne $child.manifestSha256) { $childErrors += "Child manifest hash mismatch: $childManifestPath" }
    if (-not $childRunIds.Add([string]$child.runId)) { $childErrors += "Duplicate child run id: $($child.runId)" }

    $childManifest = Get-Content -LiteralPath $childManifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($childManifest.completed -ne $true -or $childManifest.runId -ne $child.runId -or $childManifest.algorithmId -ne $manifest.algorithmId) { $childErrors += "Invalid child manifest identity: $childManifestPath" }
    if ($childManifest.scenarioSourceSha256 -ne $manifest.scenarioSourceSha256 -or $childManifest.scenarioFingerprintSha256 -ne $manifest.scenarioFingerprintSha256) { $childErrors += "Child scenario identity mismatch: $childManifestPath" }
    if ($childManifest.enqueuedLogRecords -ne $childManifest.writtenLogRecords -or $childManifest.writtenLogRecords -ne $child.writtenLogRecords) { $childErrors += "Child logger counts mismatch: $childManifestPath" }

    $canonicalPath = Join-Path $childDirectory $childManifest.canonicalScenarioFile
    $operationsPath = Join-Path $childDirectory $childManifest.operationsJsonlFile
    $resultPath = Join-Path $childDirectory $childManifest.workloadResultFile
    foreach ($requiredPath in @($canonicalPath, $operationsPath, $resultPath)) {
        if (-not (Test-Path -LiteralPath $requiredPath -PathType Leaf)) { $childErrors += "Missing child artifact: $requiredPath" }
    }
    if ((Get-LowerSha256 $canonicalPath) -ne $child.canonicalScenarioSha256 -or $child.canonicalScenarioSha256 -ne $childManifest.canonicalScenarioSha256) { $childErrors += "Child canonical scenario hash mismatch: $childDirectory" }
    if ((Get-LowerSha256 $operationsPath) -ne $child.operationsJsonlSha256 -or $child.operationsJsonlSha256 -ne $childManifest.operationsJsonlSha256) { $childErrors += "Child JSONL hash mismatch: $childDirectory" }
    if ((Get-LowerSha256 $resultPath) -ne $child.workloadResultSha256 -or $child.workloadResultSha256 -ne $childManifest.workloadResultSha256) { $childErrors += "Child result hash mismatch: $childDirectory" }

    if (Test-Path -LiteralPath $resultPath -PathType Leaf) {
        $result = Get-Content -LiteralPath $resultPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $resultPaths += [System.IO.Path]::GetFullPath($resultPath)
        $results += $result
        if ($result.completed -ne $true -or $result.runId -ne $child.runId -or $result.algorithmId -ne $manifest.algorithmId -or $result.scenarioFingerprintSha256 -ne $manifest.scenarioFingerprintSha256) { $childErrors += "Invalid child result identity: $resultPath" }
        if ($result.planOperationCount -ne $child.planOperationCount -or $result.repairOperationCount -ne $child.repairOperationCount -or $result.succeededPlanCount -ne $child.succeededPlanCount) { $childErrors += "Child result counts mismatch: $resultPath" }
        if ($result.planOperationCount -ne $result.succeededPlanCount -or $result.noPathPlanCount -ne 0 -or $result.budgetExceededPlanCount -ne 0 -or $result.invalidPlanCount -ne 0 -or $result.failedPlanCount -ne 0) { $childErrors += "Child planning outcome is not entirely successful: $resultPath" }
    }

    if (Test-Path -LiteralPath $operationsPath -PathType Leaf) {
        $records = @()
        $lineNumber = 0
        foreach ($line in Get-Content -LiteralPath $operationsPath -Encoding UTF8) {
            $lineNumber++
            try { $records += ($line | ConvertFrom-Json) }
            catch { $childErrors += "JSONL parse failure at ${operationsPath}:$lineNumber - $($_.Exception.Message)" }
        }
        for ($recordIndex = 0; $recordIndex -lt $records.Count; $recordIndex++) {
            if ([int64]$records[$recordIndex].sequence -ne $recordIndex -or $records[$recordIndex].runId -ne $child.runId -or $records[$recordIndex].schemaVersion -ne 1) {
                $childErrors += "JSONL sequence or identity mismatch: $operationsPath"
                break
            }
        }
        $plannerRecords = @($records | Where-Object { $_.recordType -eq 'planner_operation' }).Count
        $lifecycleRecords = @($records | Where-Object { $_.recordType -eq 'runner_lifecycle' }).Count
        $workloadRecords = @($records | Where-Object { $_.recordType -eq 'planning_workload_result' }).Count
        if ($records.Count -ne $childManifest.writtenLogRecords -or $plannerRecords -ne ($child.planOperationCount + $child.repairOperationCount + 1) -or $lifecycleRecords -ne 3 -or $workloadRecords -ne 1) { $childErrors += "JSONL record counts mismatch: $operationsPath" }
        $totalJsonlRecords += $records.Count
        $totalPlannerRecords += $plannerRecords
        $totalLifecycleRecords += $lifecycleRecords
        $totalWorkloadRecords += $workloadRecords
    }

    if (Test-Path -LiteralPath $childUnityLogPath -PathType Leaf) {
        if (@(Select-String -LiteralPath $childUnityLogPath -Pattern $compilerPatterns -AllMatches).Count -ne 0) { $childErrors += "Compiler error signature in child log: $childUnityLogPath" }
        if (@(Select-String -LiteralPath $childUnityLogPath -SimpleMatch 'DDM planning batch completed. Manifest:').Count -eq 0) { $childErrors += "Completion marker missing in child log: $childUnityLogPath" }
    }
    if (Test-Path -LiteralPath $childSummaryPath -PathType Leaf) {
        $childSummary = Get-Content -LiteralPath $childSummaryPath -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($childSummary.passed -ne $true) { $childErrors += "Child wrapper summary failed: $childSummaryPath" }
    }
}

$metricErrors = @()
if ($null -ne $aggregate) {
    foreach ($metricName in @('initializationMilliseconds', 'planP95Milliseconds', 'dynamicHandlingP95Milliseconds', 'totalPlannerElapsedMilliseconds', 'managedAllocatedBytes', 'planSuccessRate', 'budgetOverrunRate')) {
        $metric = $aggregate.$metricName
        if ($null -eq $metric -or $metric.count -ne $manifest.repetitionCount) { $metricErrors += "$metricName has an invalid sample count."; continue }
        if ($metric.minimum -gt $metric.mean -or $metric.mean -gt $metric.maximum -or $metric.minimum -gt $metric.median -or $metric.median -gt $metric.maximum -or $metric.minimum -gt $metric.p95NearestRank -or $metric.p95NearestRank -gt $metric.maximum) { $metricErrors += "$metricName has invalid location bounds." }
        if ($metric.sampleStandardDeviation -lt 0 -or $metric.standardError -lt 0 -or $metric.confidence95Lower -gt $metric.mean -or $metric.confidence95Upper -lt $metric.mean) { $metricErrors += "$metricName has invalid dispersion or confidence bounds." }
    }
}

$requestPathsMatch = $null -ne $request -and @($request.workloadResultPaths).Count -eq $resultPaths.Count
if ($requestPathsMatch) {
    for ($index = 0; $index -lt $resultPaths.Count; $index++) {
        if ([System.IO.Path]::GetFullPath([string]$request.workloadResultPaths[$index]) -ne $resultPaths[$index]) { $requestPathsMatch = $false; break }
    }
}

$runnerPath = [System.IO.Path]::GetFullPath((Join-Path $scriptDirectory '..\Run-PlanningReplication.ps1'))
$savedErrorActionPreference = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
$overwriteGuardOutput = @(& powershell -NoProfile -ExecutionPolicy Bypass -File $runnerPath `
    -ScenarioPath $ScenarioPath `
    -Repetitions 2 `
    -GroupId 'overwrite-must-fail' `
    -OutputDirectory $FixtureDirectory `
    -Algorithm 'A*-R' 2>&1 | ForEach-Object { $_.ToString() })
$overwriteGuardExitCode = $LASTEXITCODE
$ErrorActionPreference = $savedErrorActionPreference
$groupManifestHashAfterGuard = Get-LowerSha256 $groupManifestPath
$overwriteGuardVerified = $overwriteGuardExitCode -ne 0 -and ($overwriteGuardOutput -join "`n") -match 'refusing to overwrite' -and $groupManifestHashAfterGuard -eq $groupManifestHashBeforeGuard

$unauthorizedOutputPath = Join-Path $scriptDirectory ('Gate6_UnauthorizedAlgorithm_MustNotExist_' + [Guid]::NewGuid().ToString('N'))
$savedErrorActionPreference = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
$unauthorizedAlgorithmOutput = @(& powershell -NoProfile -ExecutionPolicy Bypass -File $runnerPath `
    -ScenarioPath $ScenarioPath `
    -Repetitions 2 `
    -GroupId 'unauthorized-algorithm-must-fail' `
    -OutputDirectory $unauthorizedOutputPath `
    -Algorithm 'UNSUPPORTED' 2>&1 | ForEach-Object { $_.ToString() })
$unauthorizedAlgorithmExitCode = $LASTEXITCODE
$ErrorActionPreference = $savedErrorActionPreference

$invalidRepetitionOutputPath = Join-Path $scriptDirectory ('Gate6_InvalidRepetition_MustNotExist_' + [Guid]::NewGuid().ToString('N'))
$savedErrorActionPreference = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
$invalidRepetitionOutput = @(& powershell -NoProfile -ExecutionPolicy Bypass -File $runnerPath `
    -ScenarioPath $ScenarioPath `
    -Repetitions 1 `
    -GroupId 'invalid-repetition-must-fail' `
    -OutputDirectory $invalidRepetitionOutputPath `
    -Algorithm 'A*-R' 2>&1 | ForEach-Object { $_.ToString() })
$invalidRepetitionExitCode = $LASTEXITCODE
$ErrorActionPreference = $savedErrorActionPreference
$inputParameterGuardsVerified = (
    $unauthorizedAlgorithmExitCode -ne 0 -and
    $invalidRepetitionExitCode -ne 0 -and
    -not (Test-Path -LiteralPath $unauthorizedOutputPath) -and
    -not (Test-Path -LiteralPath $invalidRepetitionOutputPath)
)

$checks = [ordered]@{
    requiredGroupFilesPresent = $missingFiles.Count -eq 0
    manifestCompleted = $manifest.schemaVersion -eq 1 -and $manifest.completed -eq $true
    expectedReplicationIdentity = $manifest.groupId -eq 'gate6-replication-final' -and $manifest.algorithmId -eq 'A*-R' -and $manifest.scenarioId -eq 'dynamic-corridors-sparse-v1' -and $manifest.repetitionCount -eq 3
    scenarioSourceHashMatches = $scenarioSourceSha256 -eq $manifest.scenarioSourceSha256
    groupArtifactHashesMatch = (Get-LowerSha256 $requestPath) -eq $manifest.aggregationRequestSha256 -and (Get-LowerSha256 $aggregatePath) -eq $manifest.aggregateSha256 -and (Get-LowerSha256 $aggregationLogPath) -eq $manifest.aggregationUnityLogSha256
    wrapperSummaryValid = $null -ne $wrapperSummary -and $wrapperSummary.passed -eq $true -and $wrapperSummary.groupManifestSha256 -eq $groupManifestHashBeforeGuard
    requestIdentityAndPathsValid = $null -ne $request -and $request.schemaVersion -eq 1 -and $request.groupId -eq $manifest.groupId -and $request.algorithmId -eq $manifest.algorithmId -and $request.scenarioSourceSha256 -eq $manifest.scenarioSourceSha256 -and $requestPathsMatch
    childRunCountAndUniquenessValid = @($manifest.childRuns).Count -eq 3 -and $childRunIds.Count -eq 3 -and $results.Count -eq 3
    childArtifactsAndLogsValid = $childErrors.Count -eq 0
    expectedJsonlCounts = $totalJsonlRecords -eq 51 -and $totalPlannerRecords -eq 39 -and $totalLifecycleRecords -eq 9 -and $totalWorkloadRecords -eq 3
    aggregationLogValid = $aggregationCompilerMatches.Count -eq 0 -and $aggregationCompletionMarker
    aggregateIdentityValid = $null -ne $aggregate -and $aggregate.completed -eq $true -and $aggregate.groupId -eq $manifest.groupId -and $aggregate.algorithmId -eq $manifest.algorithmId -and $aggregate.scenarioId -eq $manifest.scenarioId -and $aggregate.scenarioFingerprintSha256 -eq $manifest.scenarioFingerprintSha256 -and $aggregate.scenarioSourceSha256 -eq $manifest.scenarioSourceSha256 -and $aggregate.repetitionCount -eq 3
    aggregateTotalsValid = $null -ne $aggregate -and $aggregate.totalPlanOperationCount -eq 24 -and $aggregate.totalRepairOperationCount -eq 12 -and $aggregate.totalSucceededPlanCount -eq 24 -and $aggregate.totalNoPathPlanCount -eq 0 -and $aggregate.totalBudgetExceededPlanCount -eq 0 -and $aggregate.totalInvalidPlanCount -eq 0 -and $aggregate.totalFailedPlanCount -eq 0
    aggregateRunFlagsValid = $null -ne $aggregate -and $aggregate.allRunsCompleted -eq $true -and $aggregate.allRunsUseFixedScenarioStarts -eq $true
    deterministicWorkCountsValid = $null -ne $aggregate -and $aggregate.deterministicWorkCountsConsistent -eq $true -and $aggregate.consistentProcessedNodesOrCells -eq 592 -and $aggregate.consistentExpandedNodes -eq 102 -and $aggregate.consistentRelaxedEdges -eq 231
    statisticalSummariesValid = $metricErrors.Count -eq 0
    outcomeRatesValid = $null -ne $aggregate -and $aggregate.planSuccessRate.mean -eq 1.0 -and $aggregate.budgetOverrunRate.mean -eq 0.0
    overwriteGuardVerified = $overwriteGuardVerified
    inputParameterGuardsVerified = $inputParameterGuardsVerified
}
$failedChecks = @($checks.GetEnumerator() | Where-Object { -not $_.Value } | ForEach-Object { $_.Key })
$passed = $failedChecks.Count -eq 0

$summary = [ordered]@{
    savedAt = (Get-Date).ToString('o')
    fixtureDirectory = $FixtureDirectory
    scenarioPath = $ScenarioPath
    groupManifestPath = $groupManifestPath
    groupManifestSha256 = $groupManifestHashBeforeGuard
    missingFiles = $missingFiles
    childErrors = $childErrors
    metricErrors = $metricErrors
    aggregationCompilerErrorMatches = @($aggregationCompilerMatches | ForEach-Object { "{0}:{1}" -f $_.LineNumber, $_.Line.Trim() })
    childRunCount = @($manifest.childRuns).Count
    totalJsonlRecords = $totalJsonlRecords
    totalPlannerRecords = $totalPlannerRecords
    totalLifecycleRecords = $totalLifecycleRecords
    totalWorkloadRecords = $totalWorkloadRecords
    overwriteGuardExitCode = $overwriteGuardExitCode
    overwriteGuardOutput = $overwriteGuardOutput
    unauthorizedAlgorithmExitCode = $unauthorizedAlgorithmExitCode
    unauthorizedAlgorithmOutput = $unauthorizedAlgorithmOutput
    invalidRepetitionExitCode = $invalidRepetitionExitCode
    invalidRepetitionOutput = $invalidRepetitionOutput
    checks = $checks
    failedChecks = $failedChecks
    passed = $passed
}
$summary | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $summaryPath -Encoding UTF8
$summary | ConvertTo-Json -Depth 10
if (-not $passed) { Write-Error "Gate 6 replication-pipeline verification failed. Review $summaryPath."; exit 1 }
Write-Host 'Gate 6 replication-pipeline verification passed.' -ForegroundColor Green
exit 0
