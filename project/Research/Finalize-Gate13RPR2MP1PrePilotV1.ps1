[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$ProjectPath,
    [switch]$BindingSmokeOnly
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

if ([string]::IsNullOrWhiteSpace($ProjectPath) -or -not [IO.Path]::IsPathRooted($ProjectPath)) {
    throw 'An explicit absolute ProjectPath is required.'
}
$ProjectPath = [IO.Path]::GetFullPath($ProjectPath)
if ($BindingSmokeOnly) {
    Write-Output "BINDING-SMOKE-PASSED|Finalize-Gate13RPR2MP1PrePilotV1|$ProjectPath"
    exit 0
}

Import-Module (Join-Path $ProjectPath 'Research\Gate13RPR2MemoryPolicyPilotV1.psm1') -Force

$auditPath = Join-Path $ProjectPath 'Research\Gate13R_PR2_MP1_PrePilot_Final_Audit.v1.json'
$checkpointPath = Join-Path $ProjectPath 'Research\Gate13R_PR2_MP1_PrePilot_Readiness_Checkpoint.v1.json'
$pilotRoot = Join-Path $ProjectPath 'Research\PilotRuns\Gate13R_PR2_MemoryPolicy\v1'
$formalAttempt3Root = Join-Path $ProjectPath 'Research\FormalRuns\Gate13R_RQAligned_S48H48\v3'
$formalAttempt3Receipt = Join-Path $ProjectPath 'Research\Gate13R_PR2_Formal_Execution_Receipt.v3.json'
$unityLock = Join-Path $ProjectPath 'Temp\UnityLockfile'
$verificationRoot = Join-Path $ProjectPath 'Research\Verification\Gate13R_PR2_MP1\v3'

foreach ($path in @($auditPath, $checkpointPath)) {
    if (Test-Path -LiteralPath $path) { throw "Create-new pre-pilot artifact already exists: $path" }
}

$checks = New-Object Collections.Generic.List[object]
function Add-Check {
    param([string]$Id, [bool]$Passed, $Evidence)
    $script:checks.Add([ordered]@{ id = $Id; passed = $Passed; evidence = $Evidence })
}

$expectedUpstream = [ordered]@{
    'Research/Gate13R_PR2_Attempt2_Failure_Diagnosis_Checkpoint.v1.json' = '388b7a1921fe07daf97827353f402c365b0f208a9dc62cbbff2d4b5ea2829b7d'
    'Research/Gate13R_PR2_Attempt2_Failure_Diagnosis_Provenance.v1.json' = 'f192265e12155d0e56e1aa94e18cea1305b66e2fbc0eeb0eeb6ad9618aeb3c3a'
    'Research/Gate13R_PR2_Attempt2_Partial_Output_Evidence_Manifest.v1.json' = '11cf507ad3daee5c4d17adf3d7349e50b73a925f58fdb175e2b68315240eff5b'
    'Research/Analysis/Gate13R_PR2_Attempt2_Failure_Diagnosis/v1/evidence-manifest.json' = '73e34e3910a38462d8dc3a125eaf88e2c800b8f1808206db054fbe50e4f24c46'
    'Research/Analysis/Gate13R_PR2_Attempt2_Failure_Diagnosis/v2/evidence-manifest.json' = '847e93f13fe7e46eea154741d3e93421ff7c4df389b1a7a2e10cb1b676e4eb3b'
}
foreach ($entry in $expectedUpstream.GetEnumerator()) {
    $path = Join-Path $ProjectPath ($entry.Key -replace '/', '\')
    $actual = if (Test-Path -LiteralPath $path -PathType Leaf) { Get-G13RPR2MP1Sha256 $path } else { $null }
    Add-Check -Id ("upstream-sha256:" + $entry.Key) -Passed ($actual -eq $entry.Value) -Evidence ([ordered]@{ expected = $entry.Value; actual = $actual })
}

$preservationPath = Join-Path $verificationRoot 'FinalPrePilot\attempt2-preservation-final-audit.json'
$preservation = Read-G13RPR2MP1Json $preservationPath
$preservationPassed = (
    $preservation.passed -eq $true -and
    [int]$preservation.failedRoot.fileCount -eq 28020 -and
    [long]$preservation.failedRoot.rawBytes -eq 8536611302L -and
    [string]$preservation.failedRoot.canonicalTreeSha256 -eq 'aafd8018d67b54b0965dcf778d502aadbba249dc53f80ea0f7722c0c1a05867e' -and
    $preservation.failedRoot.allFilesReadOnly -eq $true
)
Add-Check -Id 'attempt2-final-preservation-audit' -Passed $preservationPassed -Evidence ([ordered]@{
    relativePath = 'Research/Verification/Gate13R_PR2_MP1/v3/FinalPrePilot/attempt2-preservation-final-audit.json'
    sha256 = Get-G13RPR2MP1Sha256 $preservationPath
    fileCount = $preservation.failedRoot.fileCount
    rawBytes = $preservation.failedRoot.rawBytes
    canonicalTreeSha256 = $preservation.failedRoot.canonicalTreeSha256
    allFilesReadOnly = $preservation.failedRoot.allFilesReadOnly
})

$provenancePath = Join-Path $ProjectPath 'Research\Gate13R_PR2_MP1_Provenance.v1.json'
$provenance = Read-G13RPR2MP1Json $provenancePath
$provenanceMismatches = New-Object Collections.Generic.List[object]
foreach ($item in @($provenance.artifacts)) {
    $path = Join-Path $ProjectPath ([string]$item.relativePath -replace '/', '\')
    $actualHash = if (Test-Path -LiteralPath $path -PathType Leaf) { Get-G13RPR2MP1Sha256 $path } else { $null }
    $actualBytes = if (Test-Path -LiteralPath $path -PathType Leaf) { (Get-Item -LiteralPath $path).Length } else { $null }
    if ($actualHash -ne [string]$item.sha256 -or $actualBytes -ne [long]$item.bytes) {
        $provenanceMismatches.Add([ordered]@{ relativePath = $item.relativePath; expectedSha256 = $item.sha256; actualSha256 = $actualHash; expectedBytes = $item.bytes; actualBytes = $actualBytes })
    }
}
Add-Check -Id 'provenance-bound-artifacts-byte-identical' -Passed ($provenanceMismatches.Count -eq 0) -Evidence ([ordered]@{ artifactCount = @($provenance.artifacts).Count; mismatchCount = $provenanceMismatches.Count; mismatches = $provenanceMismatches.ToArray() })

$summarySpecs = @(
    [ordered]@{ id='static-unit-345-of-345'; path='Research\Verification\Gate13R_PR2_MP1\v2\Static\static-unit-summary.json'; predicate={ param($v) $v.passed -eq $true -and [int]$v.checkCount -eq 345 -and [int]$v.passedCheckCount -eq 345 } },
    [ordered]@{ id='unity-self-tests-2-of-2'; path='Research\Verification\Gate13R_PR2_MP1\v3\UnitySelfTests\unity-self-tests-summary.json'; predicate={ param($v) $v.passed -eq $true -and [int]$v.testCount -eq 2 -and [int]$v.passedTestCount -eq 2 } },
    [ordered]@{ id='memory-policy-boundary-and-telemetry-fixtures'; path='Research\Verification\Gate13R_PR2_MP1\v3\UnitySelfTests\MemoryPolicySelfTest\memory-policy-self-test.json'; predicate={ param($v) $v.passed -eq $true -and [int]$v.testCount -eq 10 -and [int]$v.passedTestCount -eq 10 -and [int]$v.telemetryValidationTestCount -eq 8 -and [int]$v.telemetryValidationPassedTestCount -eq 8 } },
    [ordered]@{ id='path-safe-atomic-self-tests-14-of-14'; path='Research\Verification\Gate13R_PR2_MP1\v3\UnitySelfTests\PathSafeAtomicSelfTest\path-safe-atomic-self-test.json'; predicate={ param($v) $v.passed -eq $true -and [int]$v.testCount -eq 14 -and [int]$v.passedTestCount -eq 14 -and [int]$v.residualOwnedTemporaryFileCount -eq 0 } },
    [ordered]@{ id='psapi-cim-telemetry-probe'; path='Research\Verification\Gate13R_PR2_MP1\v3\TelemetryProbe\probe.summary.json'; predicate={ param($v) $v.passed -eq $true -and [int]$v.exitCode -eq 0 -and $v.formalCampaign -eq $false -and $v.excludedFromFormalAnalysis -eq $true } },
    [ordered]@{ id='positive-negative-block-validation-2-of-2'; path='Research\Verification\Gate13R_PR2_MP1\v3\BlockValidation\block-validation-summary.json'; predicate={ param($v) $v.passed -eq $true -and [int]$v.testCount -eq 2 -and [int]$v.passedTestCount -eq 2 -and $v.measuredPilotStarted -eq $false } },
    [ordered]@{ id='failure-precedence-powershell7-6-of-6'; path='Research\Verification\Gate13R_PR2_MP1\v3\FailurePrecedencePS7\summary.json'; predicate={ param($v) $v.passed -eq $true -and [int]$v.testCount -eq 6 -and [int]$v.passedTestCount -eq 6 } },
    [ordered]@{ id='failure-precedence-windows-powershell51-6-of-6'; path='Research\Verification\Gate13R_PR2_MP1\v3\FailurePrecedencePS51\summary.json'; predicate={ param($v) $v.passed -eq $true -and [int]$v.testCount -eq 6 -and [int]$v.passedTestCount -eq 6 } }
)
foreach ($spec in $summarySpecs) {
    $path = Join-Path $ProjectPath $spec.path
    $value = Read-G13RPR2MP1Json $path
    $passed = & $spec.predicate $value
    Add-Check -Id $spec.id -Passed $passed -Evidence ([ordered]@{ relativePath = ($spec.path -replace '\\','/'); sha256 = Get-G13RPR2MP1Sha256 $path })
}

$positiveStagePath = Join-Path $verificationRoot 'BlockValidation\positive-complete-block\block-stage-telemetry.json'
$positiveStage = Read-G13RPR2MP1Json $positiveStagePath
$stageCounts = [ordered]@{}
foreach ($record in @($positiveStage.records)) {
    $key = [string]$record.stageId
    if (-not $stageCounts.Contains($key)) { $stageCounts[$key] = 0 }
    $stageCounts[$key] = [int]$stageCounts[$key] + 1
}
$stagePassed = (
    $positiveStage.completed -eq $true -and @($positiveStage.records).Count -eq 19 -and
    [int]$stageCounts['unity-command-entry-project-loaded'] -eq 1 -and
    [int]$stageCounts['before-scenario-load'] -eq 1 -and
    [int]$stageCounts['sample-before'] -eq 4 -and
    [int]$stageCounts['sample-raw-after-workload'] -eq 4 -and
    [int]$stageCounts['sample-after-cleanup'] -eq 4 -and
    [int]$stageCounts['post-block-pre-exit'] -eq 1
)
Add-Check -Id 'stage-separated-positive-block-19-records' -Passed $stagePassed -Evidence ([ordered]@{ sha256 = Get-G13RPR2MP1Sha256 $positiveStagePath; recordCount = @($positiveStage.records).Count; stageCounts = $stageCounts })

$negativeResolutionPath = Join-Path $verificationRoot 'BlockValidation\negative-fail-closed\wrapper-failure-resolution.json'
$negativeResolution = Read-G13RPR2MP1Json $negativeResolutionPath
$negativePassed = (
    $negativeResolution.failed -eq $true -and $negativeResolution.failClosed -eq $true -and
    $negativeResolution.nextBlockAllowed -eq $false -and
    [string]$negativeResolution.primaryCause.kind -eq 'DURABLE-UNITY-BLOCK-FAILURE' -and
    $negativeResolution.automaticRetryAllowed -eq $false -and
    $negativeResolution.automaticResumeAllowed -eq $false -and
    $negativeResolution.topUpAllowed -eq $false -and
    $negativeResolution.partialMergeAllowed -eq $false
)
Add-Check -Id 'negative-durable-failure-precedence-fail-closed' -Passed $negativePassed -Evidence ([ordered]@{ sha256 = Get-G13RPR2MP1Sha256 $negativeResolutionPath; primaryCause = $negativeResolution.primaryCause.kind; secondaryCauseCount = @($negativeResolution.secondaryCauses).Count })

$parserScript = Join-Path $ProjectPath 'Research\Test-Gate13RPR2MP1PowerShellParserV1.ps1'
$pwshExe = (Get-Process -Id $PID).Path
$ps51Exe = 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe'
$runtimeExecutables = @(
    [ordered]@{ id='powershell-current'; path=$pwshExe; nativeModulePath=$false },
    [ordered]@{ id='windows-powershell-5.1'; path=$ps51Exe; nativeModulePath=$true }
)
$parserResults = New-Object Collections.Generic.List[object]
$bindingResults = New-Object Collections.Generic.List[object]
$entryScripts = @(
    [ordered]@{ id='block-wrapper'; path='Research\Run-Gate13RPR2MemoryPolicyPilotBlockV1.ps1'; args=@('-ProjectPath',$ProjectPath,'-BlockPlanPath',(Join-Path $ProjectPath 'Research\Verification\Gate13R_PR2_MP1\binding-smoke-plan.json'),'-OutputDirectory',(Join-Path $ProjectPath 'Research\Verification\Gate13R_PR2_MP1\binding-smoke-block'),'-AllowedRoot',(Join-Path $ProjectPath 'Research\Verification\Gate13R_PR2_MP1'),'-ExecutionReceiptPath',(Join-Path $ProjectPath 'Research\Verification\Gate13R_PR2_MP1\binding-smoke-receipt.json'),'-BindingSmokeOnly') },
    [ordered]@{ id='campaign-orchestrator'; path='Research\Run-Gate13RPR2MemoryPolicyPilotV1.ps1'; args=@('-ProjectPath',$ProjectPath,'-PilotRoot',(Join-Path $ProjectPath 'Research\PilotRuns\Gate13R_PR2_MemoryPolicy\binding-smoke'),'-ExecutionReceiptPath',(Join-Path $ProjectPath 'Research\Verification\Gate13R_PR2_MP1\binding-smoke-receipt.json'),'-BindingSmokeOnly') },
    [ordered]@{ id='one-shot-launcher'; path='Research\Start-Gate13RPR2MemoryPolicyPilotV1.ps1'; args=@('-ProjectPath',$ProjectPath,'-BindingSmokeOnly') },
    [ordered]@{ id='unity-self-tests'; path='Research\Run-Gate13RPR2MemoryPolicyPilotUnitySelfTestsV1.ps1'; args=@('-ProjectPath',$ProjectPath,'-VerificationRoot',(Join-Path $ProjectPath 'Research\Verification\Gate13R_PR2_MP1\binding-smoke-selftests'),'-BindingSmokeOnly') },
    [ordered]@{ id='telemetry-probe'; path='Research\Run-Gate13RPR2MemoryPolicyPilotTelemetryProbeV1.ps1'; args=@('-ProjectPath',$ProjectPath,'-OutputDirectory',(Join-Path $ProjectPath 'Research\Verification\Gate13R_PR2_MP1\binding-smoke-probe'),'-AllowedRoot',(Join-Path $ProjectPath 'Research\Verification\Gate13R_PR2_MP1'),'-BindingSmokeOnly') },
    [ordered]@{ id='block-validation'; path='Research\Invoke-Gate13RPR2MemoryPolicyPilotBlockValidationV1.ps1'; args=@('-ProjectPath',$ProjectPath,'-VerificationRoot',(Join-Path $ProjectPath 'Research\Verification\Gate13R_PR2_MP1\binding-smoke-validation'),'-BindingSmokeOnly') },
    [ordered]@{ id='prepilot-finalizer'; path='Research\Finalize-Gate13RPR2MP1PrePilotV1.ps1'; args=@('-ProjectPath',$ProjectPath,'-BindingSmokeOnly') }
)
$nativeModulePath = @('C:\Users\bdscy\Documents\WindowsPowerShell\Modules','C:\Program Files\WindowsPowerShell\Modules','C:\WINDOWS\System32\WindowsPowerShell\v1.0\Modules') -join ';'
$previousModulePath = $env:PSModulePath
try {
    foreach ($runtime in $runtimeExecutables) {
        if ($runtime.nativeModulePath) { $env:PSModulePath = $nativeModulePath } else { $env:PSModulePath = $previousModulePath }
        $parserLines = @(& $runtime.path -NoProfile -ExecutionPolicy Bypass -File $parserScript -ProjectPath $ProjectPath 2>&1)
        $parserExit = $LASTEXITCODE
        $parserValue = if ($parserExit -eq 0) { ($parserLines -join "`n") | ConvertFrom-Json } else { $null }
        $parserPassed = $parserExit -eq 0 -and $null -ne $parserValue -and $parserValue.passed -eq $true -and [int]$parserValue.fileCount -eq 7 -and [int]$parserValue.passedFileCount -eq 7
        $parserResults.Add([ordered]@{ runtimeId=$runtime.id; executable=$runtime.path; exitCode=$parserExit; runtimeVersion=if($null-ne$parserValue){$parserValue.runtime}else{$null}; fileCount=if($null-ne$parserValue){$parserValue.fileCount}else{$null}; passed=$parserPassed; output=if($parserPassed){$null}else{($parserLines -join "`n")} })
        foreach ($entry in $entryScripts) {
            $scriptPath = Join-Path $ProjectPath $entry.path
            $arguments = @('-NoProfile','-ExecutionPolicy','Bypass','-File',$scriptPath) + @($entry.args)
            $lines = @(& $runtime.path @arguments 2>&1)
            $exitCode = $LASTEXITCODE
            $output = $lines -join "`n"
            $passed = $exitCode -eq 0 -and $output -match '^BINDING-SMOKE-PASSED\|'
            $bindingResults.Add([ordered]@{ runtimeId=$runtime.id; entryId=$entry.id; relativePath=($entry.path -replace '\\','/'); exitCode=$exitCode; passed=$passed; output=$output })
        }
    }
}
finally {
    $env:PSModulePath = $previousModulePath
}
Add-Check -Id 'powershell-parser-both-runtimes' -Passed (@($parserResults | Where-Object { -not $_.passed }).Count -eq 0) -Evidence $parserResults.ToArray()
Add-Check -Id 'parameter-binding-both-runtimes' -Passed (@($bindingResults | Where-Object { -not $_.passed }).Count -eq 0) -Evidence ([ordered]@{ testCount=$bindingResults.Count; passedCount=@($bindingResults|Where-Object{$_.passed}).Count; results=$bindingResults.ToArray() })

$configPath = Join-Path $ProjectPath 'Research\Gate13R_PR2_MP1_Pilot_Config.v1.json'
$schedulePath = Join-Path $ProjectPath 'Research\Gate13R_PR2_MP1_Pilot_Schedule.v1.jsonl'
$manifestPath = Join-Path $ProjectPath 'Research\Gate13R_PR2_MP1_Pilot_Schedule_Manifest.v1.json'
$config = Read-G13RPR2MP1Json $configPath
$manifest = Read-G13RPR2MP1Json $manifestPath
$cardinalityPassed = (
    [int]$config.matrix.measuredProcesses -eq 96 -and [int]$config.matrix.measuredSamples -eq 384 -and
    [int]$config.matrix.warmupProcesses -eq 0 -and [int]$manifest.measuredProcessCount -eq 96 -and
    [int]$manifest.measuredSampleCount -eq 384 -and [int]$manifest.warmupProcessCount -eq 0
)
Add-Check -Id 'frozen-pilot-cardinality-96-blocks-384-samples' -Passed $cardinalityPassed -Evidence ([ordered]@{ configSha256=Get-G13RPR2MP1Sha256 $configPath; scheduleSha256=Get-G13RPR2MP1Sha256 $schedulePath; scheduleManifestSha256=Get-G13RPR2MP1Sha256 $manifestPath; measuredProcesses=$manifest.measuredProcessCount; measuredSamples=$manifest.measuredSampleCount; warmupProcesses=$manifest.warmupProcessCount })

$unityProcesses = @(Get-CimInstance Win32_Process | Where-Object { $_.Name -in @('Unity.exe','UnityCrashHandler64.exe','UnityCrashHandler32.exe') } | Select-Object ProcessId,ParentProcessId,Name,ExecutablePath,CommandLine)
Add-Check -Id 'unity-process-tree-zero' -Passed ($unityProcesses.Count -eq 0) -Evidence $unityProcesses
Add-Check -Id 'project-unity-lock-absent' -Passed (-not (Test-Path -LiteralPath $unityLock)) -Evidence ([ordered]@{ path=$unityLock; exists=Test-Path -LiteralPath $unityLock })
Add-Check -Id 'pilot-root-absent-before-one-shot-launch' -Passed (-not (Test-Path -LiteralPath $pilotRoot)) -Evidence ([ordered]@{ path=$pilotRoot; exists=Test-Path -LiteralPath $pilotRoot })
Add-Check -Id 'formal-attempt3-root-absent' -Passed (-not (Test-Path -LiteralPath $formalAttempt3Root)) -Evidence ([ordered]@{ path=$formalAttempt3Root; exists=Test-Path -LiteralPath $formalAttempt3Root })
Add-Check -Id 'formal-attempt3-receipt-absent' -Passed (-not (Test-Path -LiteralPath $formalAttempt3Receipt)) -Evidence ([ordered]@{ path=$formalAttempt3Receipt; exists=Test-Path -LiteralPath $formalAttempt3Receipt })

$drive = Get-PSDrive -Name H
Add-Check -Id 'h-drive-free-at-least-40-gib' -Passed ([long]$drive.Free -ge 42949672960L) -Evidence ([ordered]@{ freeBytes=[long]$drive.Free; requiredBytes=42949672960L })
$os = Get-CimInstance Win32_OperatingSystem
$availablePhysicalMemoryBytes = [long]$os.FreePhysicalMemory * 1024L
Add-Check -Id 'available-physical-memory-above-8-gib' -Passed ($availablePhysicalMemoryBytes -ge 8589934592L) -Evidence ([ordered]@{ availablePhysicalMemoryBytes=$availablePhysicalMemoryBytes; requiredBytes=8589934592L })
$powerPlanText = (& powercfg /getactivescheme) -join "`n"
$sleepText = (& powercfg /query SCHEME_CURRENT SUB_SLEEP STANDBYIDLE) -join "`n"
Add-Check -Id 'high-performance-power-plan' -Passed ($powerPlanText -match '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c') -Evidence $powerPlanText
Add-Check -Id 'ac-sleep-disabled' -Passed ($sleepText -match '0x00000000') -Evidence $sleepText

$failed = @($checks | Where-Object { -not $_.passed })
$completedUtc = [DateTime]::UtcNow
$audit = [ordered]@{
    schemaVersion = 1
    auditKind = 'gate13r-pr2-mp1-final-validation-only-prepilot-audit-v1'
    completedAtUtc = $completedUtc.ToString('o')
    completedAtAsiaShanghai = [TimeZoneInfo]::ConvertTimeBySystemTimeZoneId($completedUtc, 'China Standard Time').ToString('o')
    projectPath = $ProjectPath
    formalCampaign = $false
    measuredPilotStarted = $false
    unityMeasuredBlockCreated = $false
    formalAttempt3Authorized = $false
    formalAnalysisAuthorized = $false
    gate14RAuthorized = $false
    checkCount = $checks.Count
    passedCheckCount = @($checks | Where-Object { $_.passed }).Count
    failedCheckCount = $failed.Count
    checks = $checks.ToArray()
    passed = $failed.Count -eq 0
}
Write-G13RPR2MP1AtomicJson -Path $auditPath -Value $audit -Depth 80
if ($failed.Count -gt 0) {
    throw ("Final pre-pilot audit failed: " + (($failed | ForEach-Object { $_.id }) -join ', '))
}

$checkpoint = [ordered]@{
    schemaVersion = 1
    checkpointKind = 'gate13r-pr2-mp1-prepilot-readiness-checkpoint-v1'
    savedAtUtc = [DateTime]::UtcNow.ToString('o')
    status = 'PRE-PILOT-VALIDATED / MEASURED-PILOT-AUTHORIZED-BUT-NOT-STARTED'
    passed = $true
    finalAuditRelativePath = 'Research/Gate13R_PR2_MP1_PrePilot_Final_Audit.v1.json'
    finalAuditSha256 = Get-G13RPR2MP1Sha256 $auditPath
    authorizationSha256 = Get-G13RPR2MP1Sha256 (Join-Path $ProjectPath 'Research\Gate13R_PR2_MP1_Authorization.v1.json')
    provenanceSha256 = Get-G13RPR2MP1Sha256 $provenancePath
    configSha256 = Get-G13RPR2MP1Sha256 $configPath
    scheduleSha256 = Get-G13RPR2MP1Sha256 $schedulePath
    scheduleManifestSha256 = Get-G13RPR2MP1Sha256 $manifestPath
    measuredProcessCount = 96
    measuredSampleCount = 384
    warmupProcessCount = 0
    maximumUnityConcurrency = 1
    oneFreshUnityProcessPerCompleteWilliamsBlock = $true
    automaticMeasuredRetryAuthorized = $false
    automaticMeasuredResumeAuthorized = $false
    topUpAuthorized = $false
    partialMergeAuthorized = $false
    formalAttempt3Authorized = $false
    formalStatisticalAnalysisAuthorized = $false
    gate14RAuthorized = $false
    attempt2FrozenIdentity = [ordered]@{ fileCount=28020; rawBytes=8536611302L; canonicalOrdinalTreeSha256='aafd8018d67b54b0965dcf778d502aadbba249dc53f80ea0f7722c0c1a05867e'; allFilesReadOnly=$true }
    environment = [ordered]@{ hDriveFreeBytes=[long]$drive.Free; availablePhysicalMemoryBytes=$availablePhysicalMemoryBytes; unityProcessCount=0; unityLockfileExists=$false; highPerformancePowerPlan=$true; acSleepDisabled=$true }
    labels = @('NON-FORMAL','MEMORY-DIAGNOSTIC-ONLY','EXCLUDED-FROM-FORMAL-ANALYSIS','NOT-ALGORITHM-SUPERIORITY-EVIDENCE')
}
Write-G13RPR2MP1AtomicJson -Path $checkpointPath -Value $checkpoint -Depth 50
Write-Output "MP1-PRE-PILOT-VALIDATED|$($audit.passedCheckCount)/$($audit.checkCount)|$checkpointPath"

