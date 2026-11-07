[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$scriptDirectory = Split-Path -Parent $MyInvocation.MyCommand.Path
$fixtureDirectory = Join-Path $scriptDirectory 'Gate9_IDFF_BatchFixture_Final'
$scenarioPath = [System.IO.Path]::GetFullPath((Join-Path $scriptDirectory '..\Scenarios\dynamic_corridors_sparse_v1.scenario.json'))
$unityLogPath = $fixtureDirectory + '.Unity.log'
$summaryPath = Join-Path $scriptDirectory 'Gate9_IDFF_BatchPipeline.summary.json'

function Get-LowerSha256([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

$manifestPath = Join-Path $fixtureDirectory 'manifest.json'
if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) { throw "Gate 9 IDFF manifest not found: $manifestPath" }
$manifestHashBefore = Get-LowerSha256 $manifestPath
$manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
$canonicalPath = Join-Path $fixtureDirectory $manifest.canonicalScenarioFile
$operationsPath = Join-Path $fixtureDirectory $manifest.operationsJsonlFile
$resultPath = Join-Path $fixtureDirectory $manifest.workloadResultFile
$requiredFiles = @($scenarioPath, $canonicalPath, $operationsPath, $resultPath, $unityLogPath)
$missingFiles = @($requiredFiles | Where-Object { -not (Test-Path -LiteralPath $_ -PathType Leaf) })
$result = if (Test-Path -LiteralPath $resultPath -PathType Leaf) { Get-Content -LiteralPath $resultPath -Raw -Encoding UTF8 | ConvertFrom-Json } else { $null }

$records = @()
$jsonlErrors = @()
if (Test-Path -LiteralPath $operationsPath -PathType Leaf) {
    $lineNumber = 0
    foreach ($line in Get-Content -LiteralPath $operationsPath -Encoding UTF8) {
        $lineNumber++
        try { $records += ($line | ConvertFrom-Json) }
        catch { $jsonlErrors += "${lineNumber}: $($_.Exception.Message)" }
    }
}
$sequenceValid = $true
for ($index = 0; $index -lt $records.Count; $index++) {
    if ([int64]$records[$index].sequence -ne $index -or $records[$index].runId -ne $manifest.runId -or $records[$index].schemaVersion -ne 1 -or ($null -ne $records[$index].payload.algorithmId -and $records[$index].payload.algorithmId -ne 'IDFF')) { $sequenceValid = $false; break }
}
$plannerRecords = @($records | Where-Object recordType -eq 'planner_operation').Count
$lifecycleRecords = @($records | Where-Object recordType -eq 'runner_lifecycle').Count
$workloadRecords = @($records | Where-Object recordType -eq 'planning_workload_result').Count
$positiveAllocationRecords = @($records | Where-Object { $_.recordType -eq 'planner_operation' -and $_.payload.managedAllocatedBytes -gt 0 }).Count
$compilerPatterns = @('error CS\d{4}', 'Scripts have compiler errors', 'Compilation failed', 'executeMethod.+could not be found')
$compilerMatches = if (Test-Path -LiteralPath $unityLogPath -PathType Leaf) { @(Select-String -LiteralPath $unityLogPath -Pattern $compilerPatterns -AllMatches) } else { @() }
$completionMarker = if (Test-Path -LiteralPath $unityLogPath -PathType Leaf) { @(Select-String -LiteralPath $unityLogPath -SimpleMatch 'DDM planning batch completed. Manifest:').Count -gt 0 } else { $false }

$runnerPath = [System.IO.Path]::GetFullPath((Join-Path $scriptDirectory '..\Run-PlanningWorkload.ps1'))
$savedPreference = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
$overwriteOutput = @(& powershell -NoProfile -ExecutionPolicy Bypass -File $runnerPath -ScenarioPath $scenarioPath -OutputDirectory $fixtureDirectory -RunId 'gate9-overwrite-must-fail' -Algorithm 'IDFF' 2>&1 | ForEach-Object { $_.ToString() })
$overwriteExit = $LASTEXITCODE
$ErrorActionPreference = $savedPreference
$manifestHashAfter = Get-LowerSha256 $manifestPath

$unsupportedPath = Join-Path $scriptDirectory ('Gate9_UnsupportedAlgorithm_MustNotExist_' + [Guid]::NewGuid().ToString('N'))
$savedPreference = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
$unsupportedOutput = @(& powershell -NoProfile -ExecutionPolicy Bypass -File $runnerPath -ScenarioPath $scenarioPath -OutputDirectory $unsupportedPath -RunId 'gate9-unsupported-must-fail' -Algorithm 'UNSUPPORTED' 2>&1 | ForEach-Object { $_.ToString() })
$unsupportedExit = $LASTEXITCODE
$ErrorActionPreference = $savedPreference

$checks = [ordered]@{
    requiredFilesPresent = $missingFiles.Count -eq 0
    retainedManifestMatches = $manifestHashBefore -eq 'cc241d5359235bd4dc62d8eac6937e9d90e5cd06610a49598a84e26cc270df10'
    manifestIdentityValid = $manifest.schemaVersion -eq 1 -and $manifest.runId -eq 'gate9-idff-batch-final' -and $manifest.algorithmId -eq 'IDFF' -and $manifest.completed -eq $true
    scenarioIdentityValid = $manifest.scenarioSourceSha256 -eq '7a99bd229df801aafba8e018769c8a7fe3022852b40025b2e48267f3495a2634' -and $manifest.scenarioFingerprintSha256 -eq '85df1443b080ad83f2fb397157bdc185fb0113b473eb1ce853bff86d3764c450' -and (Get-LowerSha256 $scenarioPath) -eq $manifest.scenarioSourceSha256
    artifactHashesMatch = (Get-LowerSha256 $canonicalPath) -eq $manifest.canonicalScenarioSha256 -and (Get-LowerSha256 $operationsPath) -eq $manifest.operationsJsonlSha256 -and (Get-LowerSha256 $resultPath) -eq $manifest.workloadResultSha256
    resultIdentityValid = $null -ne $result -and $result.completed -eq $true -and $result.runId -eq $manifest.runId -and $result.algorithmId -eq 'IDFF' -and $result.scenarioFingerprintSha256 -eq $manifest.scenarioFingerprintSha256
    resultCountsValid = $null -ne $result -and $result.agentCount -eq 2 -and $result.scheduledEventCount -eq 4 -and $result.dynamicPlanningPhaseCount -eq 3 -and $result.planOperationCount -eq 8 -and $result.repairOperationCount -eq 4 -and $result.succeededPlanCount -eq 8 -and $result.finalGridVersion -eq 4
    resultOutcomesValid = $null -ne $result -and $result.noPathPlanCount -eq 0 -and $result.budgetExceededPlanCount -eq 0 -and $result.invalidPlanCount -eq 0 -and $result.failedPlanCount -eq 0 -and $result.budgetExceededOperationCount -eq 0 -and $result.planSuccessRate -eq 1.0 -and $result.budgetOverrunRate -eq 0.0
    deterministicWorkValid = $null -ne $result -and $result.processedNodesOrCells -eq 3033 -and $result.expandedNodes -eq 148 -and $result.relaxedEdges -eq 854 -and $result.repairedCells -eq 109
    incrementalFootprintValid = $null -ne $result -and $result.repairedCells -gt 0 -and $result.repairedCells -lt ($result.repairOperationCount * 60)
    allocationObserved = $null -ne $result -and $result.managedAllocatedBytes -gt 0 -and $positiveAllocationRecords -gt 0
    jsonlValid = $jsonlErrors.Count -eq 0 -and $sequenceValid -and $records.Count -eq 17 -and $records.Count -eq $manifest.writtenLogRecords -and $manifest.enqueuedLogRecords -eq $manifest.writtenLogRecords
    jsonlTypeCountsValid = $plannerRecords -eq 13 -and $lifecycleRecords -eq 3 -and $workloadRecords -eq 1
    compilerAndCompletionValid = $compilerMatches.Count -eq 0 -and $completionMarker
    overwriteGuardVerified = $overwriteExit -ne 0 -and ($overwriteOutput -join "`n") -match 'refusing to overwrite' -and $manifestHashAfter -eq $manifestHashBefore
    unsupportedAlgorithmGuardVerified = $unsupportedExit -ne 0 -and -not (Test-Path -LiteralPath $unsupportedPath)
}
$failedChecks = @($checks.GetEnumerator() | Where-Object { -not $_.Value } | ForEach-Object { $_.Key })
$passed = $failedChecks.Count -eq 0
$summary = [ordered]@{
    savedAt = (Get-Date).ToString('o')
    fixtureDirectory = $fixtureDirectory
    retainedManifestSha256 = $manifestHashBefore
    missingFiles = $missingFiles
    jsonlErrors = $jsonlErrors
    recordCount = $records.Count
    plannerRecordCount = $plannerRecords
    lifecycleRecordCount = $lifecycleRecords
    workloadRecordCount = $workloadRecords
    compilerErrorMatches = @($compilerMatches | ForEach-Object { "{0}:{1}" -f $_.LineNumber, $_.Line.Trim() })
    overwriteGuardExitCode = $overwriteExit
    unsupportedAlgorithmExitCode = $unsupportedExit
    checks = $checks
    failedChecks = $failedChecks
    passed = $passed
}
$summary | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $summaryPath -Encoding UTF8
$summary | ConvertTo-Json -Depth 8
if (-not $passed) { Write-Error "Gate 9 IDFF batch-pipeline verification failed. Review $summaryPath."; exit 1 }
Write-Host 'Gate 9 IDFF batch-pipeline verification passed.' -ForegroundColor Green
exit 0
