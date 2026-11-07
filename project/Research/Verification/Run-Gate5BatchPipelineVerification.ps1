[CmdletBinding()]
param(
    [string]$FixtureDirectory,
    [string]$UnityLogPath
)

$ErrorActionPreference = 'Stop'
$scriptDirectory = Split-Path -Parent $MyInvocation.MyCommand.Path
if ([string]::IsNullOrWhiteSpace($FixtureDirectory)) { $FixtureDirectory = Join-Path $scriptDirectory 'Gate5_BatchFixture_Final' }
$FixtureDirectory = [System.IO.Path]::GetFullPath($FixtureDirectory)
if ([string]::IsNullOrWhiteSpace($UnityLogPath)) { $UnityLogPath = $FixtureDirectory + '.Unity.log' }
$UnityLogPath = [System.IO.Path]::GetFullPath($UnityLogPath)
$summaryPath = Join-Path $scriptDirectory 'Gate5_BatchPipeline.summary.json'

$manifestPath = Join-Path $FixtureDirectory 'manifest.json'
if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) { throw "Gate 5 manifest not found: $manifestPath" }
$manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
$canonicalPath = Join-Path $FixtureDirectory $manifest.canonicalScenarioFile
$operationsPath = Join-Path $FixtureDirectory $manifest.operationsJsonlFile
$resultPath = Join-Path $FixtureDirectory $manifest.workloadResultFile

$requiredFiles = @($canonicalPath, $operationsPath, $resultPath, $UnityLogPath)
$missingFiles = @($requiredFiles | Where-Object { -not (Test-Path -LiteralPath $_ -PathType Leaf) })
$canonicalHash = if (Test-Path -LiteralPath $canonicalPath) { (Get-FileHash -LiteralPath $canonicalPath -Algorithm SHA256).Hash.ToLowerInvariant() } else { $null }
$operationsHash = if (Test-Path -LiteralPath $operationsPath) { (Get-FileHash -LiteralPath $operationsPath -Algorithm SHA256).Hash.ToLowerInvariant() } else { $null }
$resultHash = if (Test-Path -LiteralPath $resultPath) { (Get-FileHash -LiteralPath $resultPath -Algorithm SHA256).Hash.ToLowerInvariant() } else { $null }
$result = if (Test-Path -LiteralPath $resultPath) { Get-Content -LiteralPath $resultPath -Raw -Encoding UTF8 | ConvertFrom-Json } else { $null }

$records = @()
$jsonlParseErrors = @()
if (Test-Path -LiteralPath $operationsPath) {
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
$plannerOperationCount = @($records | Where-Object recordType -eq 'planner_operation').Count
$lifecycleCount = @($records | Where-Object recordType -eq 'runner_lifecycle').Count
$workloadRecordCount = @($records | Where-Object recordType -eq 'planning_workload_result').Count
$positiveAllocationOperationCount = @($records | Where-Object { $_.recordType -eq 'planner_operation' -and $_.payload.managedAllocatedBytes -gt 0 }).Count

$compilerPatterns = @('error CS\d{4}', 'Scripts have compiler errors', 'Compilation failed', 'executeMethod.+could not be found')
$compilerMatches = if (Test-Path -LiteralPath $UnityLogPath) { @(Select-String -LiteralPath $UnityLogPath -Pattern $compilerPatterns -AllMatches) } else { @() }
$completionMarker = if (Test-Path -LiteralPath $UnityLogPath) { @(Select-String -LiteralPath $UnityLogPath -SimpleMatch 'DDM planning batch completed. Manifest:').Count -gt 0 } else { $false }

$runnerPath = [System.IO.Path]::GetFullPath((Join-Path $scriptDirectory '..\Run-PlanningWorkload.ps1'))
$savedErrorActionPreference = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
$overwriteGuardOutput = @(& powershell -NoProfile -ExecutionPolicy Bypass -File $runnerPath `
    -ScenarioPath $canonicalPath `
    -OutputDirectory $FixtureDirectory `
    -RunId 'overwrite-must-fail' `
    -Algorithm 'A*-R' 2>&1 | ForEach-Object { $_.ToString() })
$overwriteGuardExitCode = $LASTEXITCODE
$ErrorActionPreference = $savedErrorActionPreference
$overwriteGuardVerified = $overwriteGuardExitCode -ne 0 -and ($overwriteGuardOutput -join "`n") -match 'refusing to overwrite'

$checks = [ordered]@{
    requiredFilesPresent = $missingFiles.Count -eq 0
    canonicalHashMatches = $canonicalHash -eq $manifest.canonicalScenarioSha256
    operationsHashMatches = $operationsHash -eq $manifest.operationsJsonlSha256
    resultHashMatches = $resultHash -eq $manifest.workloadResultSha256
    sourceAndCanonicalHashMatch = $manifest.scenarioSourceSha256 -eq $manifest.canonicalScenarioSha256
    manifestCompleted = $manifest.completed -eq $true
    resultCompleted = $null -ne $result -and $result.completed -eq $true
    resultIdentityMatches = $null -ne $result -and $result.runId -eq $manifest.runId -and $result.algorithmId -eq $manifest.algorithmId -and $result.scenarioFingerprintSha256 -eq $manifest.scenarioFingerprintSha256
    expectedWorkloadCounts = $null -ne $result -and $result.planOperationCount -eq 6 -and $result.repairOperationCount -eq 3 -and $result.dynamicPlanningPhaseCount -eq 2 -and $result.finalGridVersion -eq 3
    allocationMetricObserved = $null -ne $result -and $result.managedAllocatedBytes -gt 0 -and $positiveAllocationOperationCount -gt 0
    jsonlParsed = $jsonlParseErrors.Count -eq 0
    jsonlRecordCountMatches = $records.Count -eq $manifest.writtenLogRecords -and $manifest.enqueuedLogRecords -eq $manifest.writtenLogRecords
    jsonlSequenceValid = $sequenceValid
    jsonlIdentityValid = $recordRunIdsValid -and $recordSchemasValid
    jsonlTypeCountsValid = $plannerOperationCount -eq 10 -and $lifecycleCount -eq 3 -and $workloadRecordCount -eq 1
    compilerErrorFree = $compilerMatches.Count -eq 0
    completionMarkerPresent = $completionMarker
    overwriteGuardVerified = $overwriteGuardVerified
}
$failedChecks = @($checks.GetEnumerator() | Where-Object { -not $_.Value } | ForEach-Object { $_.Key })
$passed = $failedChecks.Count -eq 0

$summary = [ordered]@{
    savedAt = (Get-Date).ToString('o')
    fixtureDirectory = $FixtureDirectory
    manifestPath = $manifestPath
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
    canonicalSha256 = $canonicalHash
    operationsSha256 = $operationsHash
    resultSha256 = $resultHash
    checks = $checks
    failedChecks = $failedChecks
    passed = $passed
}
$summary | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $summaryPath -Encoding UTF8
$summary | ConvertTo-Json -Depth 8
if (-not $passed) { Write-Error "Gate 5 batch-pipeline verification failed. Review $summaryPath."; exit 1 }
Write-Host 'Gate 5 batch-pipeline verification passed.' -ForegroundColor Green
exit 0
