[CmdletBinding()]
param(
    [string]$FixtureDirectory,
    [string]$ScenarioPath,
    [string]$UnityLogPath
)

$ErrorActionPreference = 'Stop'
$scriptDirectory = Split-Path -Parent $MyInvocation.MyCommand.Path
if ([string]::IsNullOrWhiteSpace($FixtureDirectory)) { $FixtureDirectory = Join-Path $scriptDirectory 'Gate7_DStarLite_BatchFixture_Final' }
if ([string]::IsNullOrWhiteSpace($ScenarioPath)) { $ScenarioPath = Join-Path $scriptDirectory '..\Scenarios\dynamic_corridors_sparse_v1.scenario.json' }
$FixtureDirectory = [System.IO.Path]::GetFullPath($FixtureDirectory)
$ScenarioPath = [System.IO.Path]::GetFullPath($ScenarioPath)
if ([string]::IsNullOrWhiteSpace($UnityLogPath)) { $UnityLogPath = $FixtureDirectory + '.Unity.log' }
$UnityLogPath = [System.IO.Path]::GetFullPath($UnityLogPath)
$summaryPath = Join-Path $scriptDirectory 'Gate7_DStarLite_BatchPipeline.summary.json'

function Get-LowerSha256([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

$manifestPath = Join-Path $FixtureDirectory 'manifest.json'
if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) { throw "Gate 7 D* Lite manifest not found: $manifestPath" }
$manifestHashBeforeGuard = Get-LowerSha256 $manifestPath
$manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
$canonicalPath = Join-Path $FixtureDirectory $manifest.canonicalScenarioFile
$operationsPath = Join-Path $FixtureDirectory $manifest.operationsJsonlFile
$resultPath = Join-Path $FixtureDirectory $manifest.workloadResultFile

$requiredFiles = @($ScenarioPath, $canonicalPath, $operationsPath, $resultPath, $UnityLogPath)
$missingFiles = @($requiredFiles | Where-Object { -not (Test-Path -LiteralPath $_ -PathType Leaf) })
$scenarioHash = Get-LowerSha256 $ScenarioPath
$canonicalHash = Get-LowerSha256 $canonicalPath
$operationsHash = Get-LowerSha256 $operationsPath
$resultHash = Get-LowerSha256 $resultPath
$result = if (Test-Path -LiteralPath $resultPath -PathType Leaf) { Get-Content -LiteralPath $resultPath -Raw -Encoding UTF8 | ConvertFrom-Json } else { $null }

$records = @()
$jsonlParseErrors = @()
if (Test-Path -LiteralPath $operationsPath -PathType Leaf) {
    $lineNumber = 0
    foreach ($line in Get-Content -LiteralPath $operationsPath -Encoding UTF8) {
        $lineNumber++
        try { $records += ($line | ConvertFrom-Json) }
        catch { $jsonlParseErrors += "${lineNumber}: $($_.Exception.Message)" }
    }
}

$sequenceValid = $true
for ($index = 0; $index -lt $records.Count; $index++) {
    if ([int64]$records[$index].sequence -ne $index) { $sequenceValid = $false; break }
}
$recordRunIdsValid = @($records | Where-Object { $_.runId -ne $manifest.runId }).Count -eq 0
$recordSchemasValid = @($records | Where-Object { $_.schemaVersion -ne 1 }).Count -eq 0
$payloadAlgorithmsValid = @($records | Where-Object { $null -ne $_.payload.algorithmId -and $_.payload.algorithmId -ne 'D*L' }).Count -eq 0
$plannerOperationCount = @($records | Where-Object recordType -eq 'planner_operation').Count
$lifecycleCount = @($records | Where-Object recordType -eq 'runner_lifecycle').Count
$workloadRecordCount = @($records | Where-Object recordType -eq 'planning_workload_result').Count
$positiveAllocationOperationCount = @($records | Where-Object { $_.recordType -eq 'planner_operation' -and $_.payload.managedAllocatedBytes -gt 0 }).Count

$compilerPatterns = @('error CS\d{4}', 'Scripts have compiler errors', 'Compilation failed', 'executeMethod.+could not be found')
$compilerMatches = if (Test-Path -LiteralPath $UnityLogPath -PathType Leaf) { @(Select-String -LiteralPath $UnityLogPath -Pattern $compilerPatterns -AllMatches) } else { @() }
$completionMarker = if (Test-Path -LiteralPath $UnityLogPath -PathType Leaf) { @(Select-String -LiteralPath $UnityLogPath -SimpleMatch 'DDM planning batch completed. Manifest:').Count -gt 0 } else { $false }

$runnerPath = [System.IO.Path]::GetFullPath((Join-Path $scriptDirectory '..\Run-PlanningWorkload.ps1'))
$savedErrorActionPreference = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
$overwriteGuardOutput = @(& powershell -NoProfile -ExecutionPolicy Bypass -File $runnerPath `
    -ScenarioPath $ScenarioPath `
    -OutputDirectory $FixtureDirectory `
    -RunId 'gate7-overwrite-must-fail' `
    -Algorithm 'D*L' 2>&1 | ForEach-Object { $_.ToString() })
$overwriteGuardExitCode = $LASTEXITCODE
$ErrorActionPreference = $savedErrorActionPreference
$manifestHashAfterGuard = Get-LowerSha256 $manifestPath
$overwriteGuardVerified = $overwriteGuardExitCode -ne 0 -and ($overwriteGuardOutput -join "`n") -match 'refusing to overwrite' -and $manifestHashAfterGuard -eq $manifestHashBeforeGuard

$unauthorizedOutputPath = Join-Path $scriptDirectory ('Gate7_UnauthorizedAlgorithm_MustNotExist_' + [Guid]::NewGuid().ToString('N'))
$savedErrorActionPreference = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
$unauthorizedOutput = @(& powershell -NoProfile -ExecutionPolicy Bypass -File $runnerPath `
    -ScenarioPath $ScenarioPath `
    -OutputDirectory $unauthorizedOutputPath `
    -RunId 'gate7-unauthorized-must-fail' `
    -Algorithm 'UNSUPPORTED' 2>&1 | ForEach-Object { $_.ToString() })
$unauthorizedExitCode = $LASTEXITCODE
$ErrorActionPreference = $savedErrorActionPreference
$unauthorizedGuardVerified = $unauthorizedExitCode -ne 0 -and -not (Test-Path -LiteralPath $unauthorizedOutputPath)

$checks = [ordered]@{
    requiredFilesPresent = $missingFiles.Count -eq 0
    retainedManifestMatches = $manifestHashBeforeGuard -eq 'c2c160d0c1aec00a59e7d2d02ebfee776a4ce1272b23fc2929e8d568c09cd427'
    manifestIdentityValid = $manifest.schemaVersion -eq 1 -and $manifest.runId -eq 'gate7-dstar-lite-batch-final' -and $manifest.algorithmId -eq 'D*L' -and $manifest.completed -eq $true
    scenarioIdentityValid = $manifest.scenarioSourceSha256 -eq '7a99bd229df801aafba8e018769c8a7fe3022852b40025b2e48267f3495a2634' -and $manifest.scenarioFingerprintSha256 -eq '85df1443b080ad83f2fb397157bdc185fb0113b473eb1ce853bff86d3764c450' -and $scenarioHash -eq $manifest.scenarioSourceSha256 -and $canonicalHash -eq $scenarioHash
    artifactHashesMatch = $canonicalHash -eq $manifest.canonicalScenarioSha256 -and $operationsHash -eq $manifest.operationsJsonlSha256 -and $resultHash -eq $manifest.workloadResultSha256
    manifestCountsValid = $manifest.enqueuedLogRecords -eq 17 -and $manifest.writtenLogRecords -eq 17 -and $manifest.planOperationCount -eq 8 -and $manifest.repairOperationCount -eq 4
    resultIdentityValid = $null -ne $result -and $result.completed -eq $true -and $result.runId -eq $manifest.runId -and $result.algorithmId -eq 'D*L' -and $result.scenarioId -eq 'dynamic-corridors-sparse-v1' -and $result.scenarioFingerprintSha256 -eq $manifest.scenarioFingerprintSha256
    resultCountsValid = $null -ne $result -and $result.agentCount -eq 2 -and $result.scheduledEventCount -eq 4 -and $result.dynamicPlanningPhaseCount -eq 3 -and $result.planOperationCount -eq 8 -and $result.repairOperationCount -eq 4 -and $result.succeededPlanCount -eq 8 -and $result.finalGridVersion -eq 4
    resultOutcomesValid = $null -ne $result -and $result.noPathPlanCount -eq 0 -and $result.budgetExceededPlanCount -eq 0 -and $result.invalidPlanCount -eq 0 -and $result.failedPlanCount -eq 0 -and $result.budgetExceededOperationCount -eq 0 -and $result.planSuccessRate -eq 1.0 -and $result.budgetOverrunRate -eq 0.0 -and $result.usesFixedScenarioStarts -eq $true
    allocationMetricObserved = $null -ne $result -and $result.managedAllocatedBytes -gt 0 -and $positiveAllocationOperationCount -gt 0
    jsonlParsed = $jsonlParseErrors.Count -eq 0
    jsonlStructureValid = $records.Count -eq 17 -and $records.Count -eq $manifest.writtenLogRecords -and $sequenceValid -and $recordRunIdsValid -and $recordSchemasValid -and $payloadAlgorithmsValid
    jsonlTypeCountsValid = $plannerOperationCount -eq 13 -and $lifecycleCount -eq 3 -and $workloadRecordCount -eq 1
    compilerErrorFree = $compilerMatches.Count -eq 0
    completionMarkerPresent = $completionMarker
    overwriteGuardVerified = $overwriteGuardVerified
    unauthorizedAlgorithmGuardVerified = $unauthorizedGuardVerified
}
$failedChecks = @($checks.GetEnumerator() | Where-Object { -not $_.Value } | ForEach-Object { $_.Key })
$passed = $failedChecks.Count -eq 0

$summary = [ordered]@{
    savedAt = (Get-Date).ToString('o')
    fixtureDirectory = $FixtureDirectory
    manifestPath = $manifestPath
    retainedManifestSha256 = $manifestHashBeforeGuard
    unityLogPath = $UnityLogPath
    missingFiles = $missingFiles
    jsonlParseErrors = $jsonlParseErrors
    compilerErrorMatches = @($compilerMatches | ForEach-Object { "{0}:{1}" -f $_.LineNumber, $_.Line.Trim() })
    recordCount = $records.Count
    plannerOperationCount = $plannerOperationCount
    lifecycleCount = $lifecycleCount
    workloadRecordCount = $workloadRecordCount
    positiveAllocationOperationCount = $positiveAllocationOperationCount
    overwriteGuardExitCode = $overwriteGuardExitCode
    overwriteGuardOutput = $overwriteGuardOutput
    unauthorizedAlgorithmExitCode = $unauthorizedExitCode
    unauthorizedAlgorithmOutput = $unauthorizedOutput
    checks = $checks
    failedChecks = $failedChecks
    passed = $passed
}
$summary | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $summaryPath -Encoding UTF8
$summary | ConvertTo-Json -Depth 8
if (-not $passed) { Write-Error "Gate 7 D* Lite batch-pipeline verification failed. Review $summaryPath."; exit 1 }
Write-Host 'Gate 7 D* Lite batch-pipeline verification passed.' -ForegroundColor Green
exit 0
