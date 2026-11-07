[CmdletBinding()]
param([Parameter(Mandatory = $true)][string]$ProjectPath)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($ProjectPath) -or -not [IO.Path]::IsPathRooted($ProjectPath)) { throw 'An explicit absolute ProjectPath is required.' }
$ProjectPath = [IO.Path]::GetFullPath($ProjectPath)
$researchPath = Join-Path $ProjectPath 'Research'
$root = Join-Path $researchPath 'Verification\Gate10R_ProcessReuse_5pct\v3'
$modulePath = Join-Path $researchPath 'Gate10RProcessReusePreparation.psm1'
$lockModulePath = Join-Path $researchPath 'Gate10RLockHygieneV3.psm1'
Import-Module $modulePath -Force
Import-Module $lockModulePath -Force

$manifestPath = Join-Path $root 'Gate10R_Attempt3_Partial_Output_Manifest.v3.json'
$receiptPath = Join-Path $root 'Gate10R_Attempt3_Failure_Receipt.v3.json'
$checkpointPath = Join-Path $root 'gate10r-checkpoint.json'
foreach ($path in @($manifestPath, $receiptPath, $checkpointPath)) {
    if (Test-Path -LiteralPath $path) { throw "Attempt-3 failure closure already exists; refusing overwrite: $path" }
}

function Read-RequiredJson([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "Required failure evidence is missing: $Path" }
    return Read-Gate10RJson -Path $Path
}
function Get-TreeIdentity([string]$Path) {
    $treeRoot = [IO.Path]::GetFullPath($Path)
    $files = @(Get-ChildItem -LiteralPath $treeRoot -Recurse -File -Force | Sort-Object FullName)
    $rows = New-Object System.Collections.Generic.List[string]
    foreach ($file in $files) {
        $relative = $file.FullName.Substring($treeRoot.Length).TrimStart('\').Replace('\', '/')
        $rows.Add(("{0}`t{1}`t{2}" -f $relative, $file.Length, (Get-Gate10RLowerSha256 -Path $file.FullName)))
    }
    return [pscustomobject][ordered]@{
        fileCount = $files.Count
        rawBytes = [long](($files | Measure-Object Length -Sum).Sum)
        treeSha256 = Get-Gate10RStringSha256V3 -Value ($rows -join "`n")
    }
}

$unitPath = Join-Path $root 'UnitTests.summary.json'
$compilePath = Join-Path $root 'Compile\attempt3.summary.json'
$probePath = Join-Path $root 'TelemetryProbe\v1.summary.json'
$blockPath = Join-Path $root 'BlockVerification.summary.json'
$retainedPath = Join-Path $root 'RetainedRegression\RetainedRegression63.summary.json'
$retainedStdoutPath = Join-Path $root 'RetainedRegression\RetainedRegression63.stdout.log'
$retainedStderrPath = Join-Path $root 'RetainedRegression\RetainedRegression63.stderr.log'
$preflightPath = Join-Path $root 'Gate10R_Attempt3_Preflight.summary.v3.json'
$executionReceiptPath = Join-Path $root 'Gate10R_Attempt3_Execution_Receipt.v3.json'
$finalAuditPath = Join-Path $root 'Gate10R_FinalAudit.summary.v3.json'
$diagnosisPath = Join-Path $researchPath 'Gate10R_Attempt3_RetainedRegression_Failure_Diagnosis.v1.md'
$originalSummaryPath = Join-Path $researchPath 'Verification\Gate12_AnalysisUnitTests.summary.json'
$retainedRunnerPath = Join-Path $researchPath 'Verification\Run-Gate10RRetainedRegressionV3.ps1'
$frozenTestPath = Join-Path $researchPath 'Verification\Run-Gate12AnalysisUnitTests.ps1'

$preflight = Read-RequiredJson $preflightPath
$unit = Read-RequiredJson $unitPath
$compile = Read-RequiredJson $compilePath
$probe = Read-RequiredJson $probePath
$block = Read-RequiredJson $blockPath
$retained = Read-RequiredJson $retainedPath
$executionReceipt = Read-RequiredJson $executionReceiptPath
if ($preflight.passed -ne $true -or [int]$preflight.assertionCount -ne 67 -or [int]$preflight.failedCount -ne 0) { throw 'Preflight evidence is not the frozen 67/67 pass.' }
if ($unit.passed -ne $true -or [int]$unit.assertionCount -ne 59 -or [int]$unit.failedCount -ne 0) { throw 'Unit evidence is not the frozen 59/59 pass.' }
if ($compile.passed -ne $true -or [int]$compile.exitCode -ne 0 -or [string]$compile.lockHygieneMode -ne 'natural-lock-absence') { throw 'Compile evidence is not a natural-lock pass.' }
if ($probe.passed -ne $true -or [int]$probe.exitCode -ne 0 -or [string]$probe.lockHygieneMode -ne 'natural-lock-absence') { throw 'Telemetry evidence is not a natural-lock pass.' }
if ($block.passed -ne $true -or [int]$block.invocationCount -ne 4 -or [int]$block.freshColdReferenceCount -ne 6 -or [int]$block.structuralComparisonCount -ne 10 -or [int]$block.structuralMismatchCount -ne 0) { throw 'Block-verification evidence is not the frozen successful result.' }
if ($retained.passed -ne $true -or [int]$retained.assertionCount -ne 0 -or @($retained.failures).Count -ne 0) { throw 'Retained-regression failure signature is not the diagnosed zero-counter result.' }
if ([string]$executionReceipt.status -ne 'AUTHORIZED-READY-FOR-ONE-OFFICIAL-GATE10R-EXECUTION' -or [int]$executionReceipt.maximumOfficialExecutions -ne 1) { throw 'Attempt-3 execution receipt mismatch.' }
if (Test-Path -LiteralPath $finalAuditPath) { throw 'Final audit evidence unexpectedly exists after the retained-regression hard stop.' }
if (@(Get-Process -Name Unity -ErrorAction SilentlyContinue).Count -ne 0) { throw 'Unity is still running; refusing terminal closure.' }
if (Test-Path -LiteralPath (Join-Path $ProjectPath 'Temp\UnityLockfile')) { throw 'Project lock exists; refusing terminal closure.' }
if ((Get-Gate10RLowerSha256 -Path $originalSummaryPath) -ne '1536ae459c3d8cbb90b8a9dad1f74e7937d5ceb205e6cc088745c798d136e54d') { throw 'Original Gate 12 retained summary changed.' }
if ((Get-Gate10RLowerSha256 -Path $retainedRunnerPath) -ne '7285ba3105c6f32c23b7ce2812dd4691c770ad43f81dfba59586e303e87bb5ed') { throw 'Attempt-3 retained wrapper changed after execution.' }
if ((Get-Gate10RLowerSha256 -Path $frozenTestPath) -ne 'e56a3881c0fc9fc3ecceb760d1c51129e80ec2b306acdcfefed0a3814a6885b1') { throw 'Frozen retained test source changed.' }
if ((Get-Gate10RLowerSha256 -Path $diagnosisPath) -ne 'cf70bfa21b3f47e5e0eca63d0ae5bcfefca6eda93b82461a115424fc12707fb4') { throw 'Failure diagnosis hash mismatch.' }

$attempt1 = Get-TreeIdentity -Path (Join-Path $researchPath 'Verification\Gate10R_ProcessReuse_5pct\v1')
$attempt2 = Get-TreeIdentity -Path (Join-Path $researchPath 'Verification\Gate10R_ProcessReuse_5pct\v2')
if ($attempt1.fileCount -ne 4 -or $attempt1.rawBytes -ne 9577 -or $attempt1.treeSha256 -ne '2baa66eb6ee95ecf0f68667b2790fba2a30ce8a24f54e8f9fe477cdc716b9e3d') { throw 'Attempt-1 history changed.' }
if ($attempt2.fileCount -ne 101 -or $attempt2.rawBytes -ne 9375526 -or $attempt2.treeSha256 -ne 'da9e6312e74db1bc1207660cf90eef28321ecda0abf1297be6c9298e6270dbce') { throw 'Attempt-2 history changed.' }

$forbiddenRoots = @(
    'Research\FormalScenarios\Gate11R_5pct\v1',
    'Research\PlayableExperiments\Gate11R_5pct\v1',
    'Assets\_Scenes\Research\Playable\Gate11R_5pct\v1',
    'Research\PilotRuns\Gate12R_ProcessReuse_5pct\v1',
    'Research\FormalRuns\Gate13R_ProcessReuse_5pct\v1'
)
foreach ($relative in $forbiddenRoots) {
    if (Test-Path -LiteralPath (Join-Path $ProjectPath $relative)) { throw "Unauthorized downstream root exists: $relative" }
}

$artifacts = New-Object System.Collections.Generic.List[object]
foreach ($file in @(Get-ChildItem -LiteralPath $root -Recurse -File -Force | Sort-Object FullName)) {
    if ($file.FullName -in @($manifestPath, $receiptPath, $checkpointPath)) { continue }
    $artifacts.Add([pscustomobject][ordered]@{
        relativePath = Get-Gate10RProjectRelativePath -ProjectPath $ProjectPath -FullPath $file.FullName
        bytes = [long]$file.Length
        sha256 = Get-Gate10RLowerSha256 -Path $file.FullName
    })
}
$manifest = [ordered]@{
    schemaVersion = 1
    manifestId = 'gate10r-attempt3-partial-output-manifest-v3'
    createdAtUtc = [DateTime]::UtcNow.ToString('o')
    attempt = 3
    status = 'FAILED-NO-AUTO-RETRY'
    failedStage = 'retained-regression'
    artifactCount = $artifacts.Count
    rawBytes = [long](($artifacts | Measure-Object bytes -Sum).Sum)
    artifacts = $artifacts.ToArray()
    finalAuditStarted = $false
    gate11RStarted = $false
    gate12RStarted = $false
    gate13RStarted = $false
    excludedFromFormalAnalysis = $true
    formalCampaign = $false
}
Write-Gate10RAtomicUtf8NoBomJson -Path $manifestPath -Value $manifest -Depth 80

$receipt = [ordered]@{
    schemaVersion = 1
    receiptId = 'gate10r-attempt3-retained-regression-failure-v3'
    createdAtUtc = [DateTime]::UtcNow.ToString('o')
    status = 'GATE10R-ATTEMPT3-FAILED-NO-AUTO-RETRY'
    attempt = 3
    officialExecutionCount = 1
    failedStage = 'retained-regression'
    failureClass = 'VERSIONED-ORCHESTRATION-WRAPPER-SCOPE-DEFECT'
    failureSummary = 'The frozen tests reported no failures but the versioned wrapper invocation produced assertionCount=0 instead of the required 63; the hard gate stopped before final audit.'
    diagnosticInference = 'Executing the frozen source as a child ScriptBlock separates its local $assertions from the $script:assertions incremented by assertion helpers under Windows PowerShell 5.1.'
    diagnosticScopeProbe = [ordered]@{localAssertions=0;scriptAssertions=1;exitCode=0;writeOperations=$false}
    passedStages = @('no-unity-preflight-67-of-67','unit-tests-59-of-59','unity-compile-natural-lock-release','telemetry-probe-natural-lock-release','block-verification-4-invocations-6-cold-10-comparisons-zero-mismatch')
    retainedRegression = [ordered]@{
        wrapperExitCode = 1
        summaryRelativePath = Get-Gate10RProjectRelativePath -ProjectPath $ProjectPath -FullPath $retainedPath
        summarySha256 = Get-Gate10RLowerSha256 -Path $retainedPath
        stdoutSha256 = Get-Gate10RLowerSha256 -Path $retainedStdoutPath
        stderrSha256 = Get-Gate10RLowerSha256 -Path $retainedStderrPath
        reportedPassed = [bool]$retained.passed
        reportedFailureCount = @($retained.failures).Count
        reportedAssertionCount = [int]$retained.assertionCount
        requiredAssertionCount = 63
    }
    originalEvidence = [ordered]@{
        frozenTestRelativePath = Get-Gate10RProjectRelativePath -ProjectPath $ProjectPath -FullPath $frozenTestPath
        frozenTestSha256 = Get-Gate10RLowerSha256 -Path $frozenTestPath
        originalSummaryRelativePath = Get-Gate10RProjectRelativePath -ProjectPath $ProjectPath -FullPath $originalSummaryPath
        originalSummarySha256 = Get-Gate10RLowerSha256 -Path $originalSummaryPath
        unchanged = $true
    }
    diagnosis = [ordered]@{
        relativePath = Get-Gate10RProjectRelativePath -ProjectPath $ProjectPath -FullPath $diagnosisPath
        sha256 = Get-Gate10RLowerSha256 -Path $diagnosisPath
    }
    partialOutputManifest = [ordered]@{
        relativePath = Get-Gate10RProjectRelativePath -ProjectPath $ProjectPath -FullPath $manifestPath
        sha256 = Get-Gate10RLowerSha256 -Path $manifestPath
        artifactCount = $manifest.artifactCount
        rawBytes = $manifest.rawBytes
    }
    historicalBoundaries = [ordered]@{attempt1=$attempt1;attempt2=$attempt2}
    unityProcessCountAtClosure = 0
    projectLockExistsAtClosure = $false
    finalAuditStarted = $false
    automaticRetryAttempted = $false
    automaticResumeAttempted = $false
    gate11RAuthorized = $false
    gate11RStarted = $false
    gate12RAuthorized = $false
    gate12RStarted = $false
    gate13RAuthorized = $false
    gate13RStarted = $false
    formalCampaign = $false
}
Write-Gate10RAtomicUtf8NoBomJson -Path $receiptPath -Value $receipt -Depth 50

$checkpoint = [ordered]@{
    schemaVersion = 1
    checkpointKind = 'gate10r-process-reuse-5pct-checkpoint-attempt3-v3'
    savedAtUtc = [DateTime]::UtcNow.ToString('o')
    status = 'GATE10R-ATTEMPT3-FAILED-NO-AUTO-RETRY'
    attempt = 3
    officialExecutionCount = 1
    failedStage = 'retained-regression'
    failureReceiptRelativePath = Get-Gate10RProjectRelativePath -ProjectPath $ProjectPath -FullPath $receiptPath
    failureReceiptSha256 = Get-Gate10RLowerSha256 -Path $receiptPath
    partialOutputManifestRelativePath = Get-Gate10RProjectRelativePath -ProjectPath $ProjectPath -FullPath $manifestPath
    partialOutputManifestSha256 = Get-Gate10RLowerSha256 -Path $manifestPath
    automaticRetryAuthorized = $false
    automaticResumeAuthorized = $false
    gate11RAuthorized = $false
    gate12RAuthorized = $false
    gate13RPreparationAuthorized = $false
    gate13RFormalCampaignAuthorized = $false
    nextAction = 'WAIT-FOR-USER-AUTHORIZATION'
    formalCampaign = $false
}
Write-Gate10RAtomicUtf8NoBomJson -Path $checkpointPath -Value $checkpoint -Depth 30
Write-Host "Gate 10R attempt 3 failure evidence closed: $($manifest.artifactCount) artifacts; no retry; waiting for user authorization." -ForegroundColor Yellow
exit 0
