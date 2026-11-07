[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$ProjectPath,
    [Parameter(Mandatory = $true)][string]$VerificationRoot,
    [switch]$BindingSmokeOnly
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if ([string]::IsNullOrWhiteSpace($ProjectPath) -or -not [IO.Path]::IsPathRooted($ProjectPath)) { throw 'Gate13R unit tests v2 require an explicit absolute ProjectPath.' }
$ProjectPath = [IO.Path]::GetFullPath($ProjectPath)
if ($BindingSmokeOnly) { Write-Output "BINDING-SMOKE-PASSED|Run-Gate13RNonExecutingPreparationUnitTestsV2|$ProjectPath"; exit 0 }
Import-Module (Join-Path $ProjectPath 'Research\Gate13RFormalPreparationV1.psm1') -Force

$VerificationRoot = [IO.Path]::GetFullPath($VerificationRoot)
$verificationBase = [IO.Path]::GetFullPath((Join-Path $ProjectPath 'Research\Verification\Gate13R_NonExecuting_Preparation'))
$formalRoot = [IO.Path]::GetFullPath((Join-Path $ProjectPath 'Research\FormalRuns\Gate13R_ProcessReuse_5pct\v1'))
if (-not (Test-G13RPathWithin -BasePath $verificationBase -CandidatePath $VerificationRoot)) { throw 'VerificationRoot is outside the Gate13R versioned verification base.' }
if (Test-Path -LiteralPath $formalRoot) { throw 'Reserved Gate13R formal root must remain absent during unit tests.' }
$unitRoot = Join-Path $VerificationRoot 'Unit'
if (Test-Path -LiteralPath $unitRoot) { throw 'Create-new Gate13R unit root already exists.' }
New-Item -ItemType Directory -Path $unitRoot -Force | Out-Null

$assertions = 0
$failures = New-Object Collections.Generic.List[string]
function Assert-True([bool]$Condition, [string]$Name) {
    $script:assertions++
    if (-not $Condition) { $script:failures.Add($Name) }
}
function Assert-False([bool]$Condition, [string]$Name) { Assert-True (-not $Condition) $Name }
function Clone-Json($Value) { return (($Value | ConvertTo-Json -Depth 40) | ConvertFrom-Json) }

Assert-True ((Get-G13RAlgorithmSlug 'A*-R') -eq 'astar-r') 'slug-astar'
Assert-True ((Get-G13RAlgorithmSlug 'D*L') -eq 'dstar-l') 'slug-dstar'
Assert-True ((Get-G13RAlgorithmSlug 'C-FF') -eq 'cff') 'slug-cff'
Assert-True ((Get-G13RAlgorithmSlug 'IDFF') -eq 'idff') 'slug-idff'
Assert-True ((Get-G13RCandidateBlocks 'four-algorithm-shared-goal-v1') -eq 548) 'candidate-shared'
Assert-True ((Get-G13RCandidateBlocks 'per-agent-heterogeneous-goal-v1') -eq 768) 'candidate-per-agent'
Assert-True ((Get-G13RCandidateBlocks 'grouped-field-heterogeneous-goal-v1') -eq 400) 'candidate-grouped'
Assert-True (@(Get-G13RExpectedAlgorithms 'four-algorithm-shared-goal-v1').Count -eq 4) 'shared-algorithm-count'
Assert-True (@(Get-G13RExpectedAlgorithms 'per-agent-heterogeneous-goal-v1').Count -eq 2) 'per-agent-algorithm-count'
Assert-True (@(Get-G13RExpectedAlgorithms 'grouped-field-heterogeneous-goal-v1').Count -eq 2) 'grouped-algorithm-count'
Assert-True (Test-G13RSafeId 'g13r-c01-b0001-p01-astar-r') 'safe-id-positive'
Assert-False (Test-G13RSafeId '../escape') 'safe-id-path-escape'
Assert-False (Test-G13RSafeId ('x' * 129)) 'safe-id-too-long'
Assert-True (Test-G13RPathWithin -BasePath $verificationBase -CandidatePath (Join-Path $verificationBase 'v1\Unit')) 'path-within-positive'
Assert-False (Test-G13RPathWithin -BasePath $verificationBase -CandidatePath (Join-Path $ProjectPath 'Research\FormalRuns')) 'path-within-negative'

$now = [DateTime]::UtcNow
$storageBelow = Test-G13RStorageGate -AvailableFreeBytes 188047724815 -ExpectedVolumeRoot $formalRoot -ObservedVolumeRoot $formalRoot -CheckedAtUtc $now -NowUtc $now -OriginalByteCount
$storageEqual = Test-G13RStorageGate -AvailableFreeBytes 188047724816 -ExpectedVolumeRoot $formalRoot -ObservedVolumeRoot $formalRoot -CheckedAtUtc $now -NowUtc $now -OriginalByteCount
$storageAbove = Test-G13RStorageGate -AvailableFreeBytes 188047724817 -ExpectedVolumeRoot $formalRoot -ObservedVolumeRoot $formalRoot -CheckedAtUtc $now -NowUtc $now -OriginalByteCount
Assert-False $storageBelow.passed 'storage-one-byte-below-fails'
Assert-True $storageEqual.passed 'storage-exact-boundary-passes'
Assert-True $storageAbove.passed 'storage-one-byte-above-passes'
$storageRounded = Test-G13RStorageGate -AvailableFreeBytes 188047724816 -ExpectedVolumeRoot $formalRoot -ObservedVolumeRoot $formalRoot -CheckedAtUtc $now -NowUtc $now
Assert-False $storageRounded.passed 'storage-original-byte-required'
$storageStale = Test-G13RStorageGate -AvailableFreeBytes 188047724816 -ExpectedVolumeRoot $formalRoot -ObservedVolumeRoot $formalRoot -CheckedAtUtc $now.AddSeconds(-301) -NowUtc $now -OriginalByteCount
Assert-False $storageStale.passed 'storage-stale-fails'
$storageWrongVolume = Test-G13RStorageGate -AvailableFreeBytes 188047724816 -ExpectedVolumeRoot $formalRoot -ObservedVolumeRoot 'C:\' -CheckedAtUtc $now -NowUtc $now -OriginalByteCount
Assert-False $storageWrongVolume.passed 'storage-wrong-volume-fails'
Assert-False $storageEqual.authorizing 'validation-storage-not-authorizing'
$storageLaunch = Test-G13RStorageGate -AvailableFreeBytes 188047724816 -ExpectedVolumeRoot $formalRoot -ObservedVolumeRoot $formalRoot -CheckedAtUtc $now -NowUtc $now -OriginalByteCount -LaunchContext
Assert-True $storageLaunch.authorizing 'launch-storage-authorizing-when-valid'

$hashA = 'a' * 64
$hashB = 'b' * 64
$hashC = 'c' * 64
$hashD = 'd' * 64
$hashE = 'e' * 64
$hashF = 'f' * 64
$positiveReceipt = [ordered]@{
    schemaVersion = 1
    receiptKind = 'gate13r-formal-campaign-execution-receipt-v1'
    authorizationKind = 'gate13r-formal-campaign-user-authorization-v1'
    formalCampaignAuthorized = $true
    formalExecutionAuthorized = $true
    consumed = $false
    noAutomaticRetry = $true
    noAutomaticResume = $true
    formalRootResolved = $formalRoot
    configSha256 = $hashA
    amendmentSha256 = $hashB
    provenanceSha256 = $hashC
    scheduleManifestSha256 = $hashD
    orchestratorSha256 = $hashE
    unityCommandSha256 = $hashF
    storagePreflight = [ordered]@{
        availableFreeBytes = 188047724816L
        minimumLaunchFreeBytes = 188047724816L
        observedVolumeRoot = [IO.Path]::GetPathRoot($formalRoot)
        checkedAtUtc = $now.ToString('o')
        originalByteCount = $true
    }
    environmentPreflight = [ordered]@{ passed = $true }
}
$receiptArguments = @{
    ExpectedFormalRoot = $formalRoot
    ExpectedConfigSha256 = $hashA
    ExpectedAmendmentSha256 = $hashB
    ExpectedProvenanceSha256 = $hashC
    ExpectedScheduleManifestSha256 = $hashD
    ExpectedOrchestratorSha256 = $hashE
    ExpectedUnityCommandSha256 = $hashF
    NowUtc = $now
}
$positiveCheck = Test-G13RFormalExecutionReceipt -Receipt ([pscustomobject]$positiveReceipt) @receiptArguments
Assert-True $positiveCheck.passed 'receipt-positive-fixture'
$mutations = @(
    [pscustomobject]@{ name = 'receipt-nonexecuting-auth-kind'; apply = { param($r) $r.authorizationKind = 'gate13r-nonexecuting-preparation-authorization-v1' } },
    [pscustomobject]@{ name = 'receipt-formal-false'; apply = { param($r) $r.formalExecutionAuthorized = $false } },
    [pscustomobject]@{ name = 'receipt-consumed'; apply = { param($r) $r.consumed = $true } },
    [pscustomobject]@{ name = 'receipt-retry-enabled'; apply = { param($r) $r.noAutomaticRetry = $false } },
    [pscustomobject]@{ name = 'receipt-resume-enabled'; apply = { param($r) $r.noAutomaticResume = $false } },
    [pscustomobject]@{ name = 'receipt-root-mismatch'; apply = { param($r) $r.formalRootResolved = 'C:\escape' } },
    [pscustomobject]@{ name = 'receipt-config-hash-mismatch'; apply = { param($r) $r.configSha256 = '0' * 64 } },
    [pscustomobject]@{ name = 'receipt-schedule-hash-mismatch'; apply = { param($r) $r.scheduleManifestSha256 = '0' * 64 } },
    [pscustomobject]@{ name = 'receipt-storage-insufficient'; apply = { param($r) $r.storagePreflight.availableFreeBytes = 188047724815L } },
    [pscustomobject]@{ name = 'receipt-storage-stale'; apply = { param($r) $r.storagePreflight.checkedAtUtc = $now.AddSeconds(-301).ToString('o') } },
    [pscustomobject]@{ name = 'receipt-environment-failed'; apply = { param($r) $r.environmentPreflight.passed = $false } }
)
foreach ($mutation in $mutations) {
    $copy = Clone-Json ([pscustomobject]$positiveReceipt)
    & $mutation.apply $copy
    $check = Test-G13RFormalExecutionReceipt -Receipt $copy @receiptArguments
    Assert-False $check.passed ([string]$mutation.name)
}

$scheduleRecord = [pscustomobject]@{
    blockId = 'g13r-c01-b0001'
    expectedSampleCount = 2
}
$completedCheckpoint = [pscustomobject]@{
    blockId = 'g13r-c01-b0001'
    expectedSampleCount = 2
    completedSampleCount = 2
    status = 'block-completed'
    automaticRetryAttempted = $false
    automaticResumeAttempted = $false
    eligibleForFormalAnalysis = $true
}
$failedCheckpoint = [pscustomobject]@{
    blockId = 'g13r-c01-b0001'
    expectedSampleCount = 2
    completedSampleCount = 1
    status = 'failed-no-auto-retry-no-resume'
    automaticRetryAttempted = $false
    automaticResumeAttempted = $false
    eligibleForFormalAnalysis = $false
}
Assert-True ((Test-G13RCheckpointFixture -Checkpoint $completedCheckpoint -ScheduleRecord $scheduleRecord).passed) 'checkpoint-completed-positive'
Assert-True ((Test-G13RCheckpointFixture -Checkpoint $failedCheckpoint -ScheduleRecord $scheduleRecord -ExpectFailure).passed) 'checkpoint-failed-positive'
$invalidFailure = Clone-Json $failedCheckpoint
$invalidFailure.completedSampleCount = 2
Assert-False ((Test-G13RCheckpointFixture -Checkpoint $invalidFailure -ScheduleRecord $scheduleRecord -ExpectFailure).passed) 'checkpoint-failed-complete-rejected'
$invalidRetry = Clone-Json $failedCheckpoint
$invalidRetry.automaticRetryAttempted = $true
Assert-False ((Test-G13RCheckpointFixture -Checkpoint $invalidRetry -ScheduleRecord $scheduleRecord -ExpectFailure).passed) 'checkpoint-retry-rejected'

$atomicPath = Join-Path $unitRoot 'atomic-checkpoint-fixture.json'
Write-G13RAtomicUtf8NoBomJson -Path $atomicPath -Value $failedCheckpoint -Depth 10
Assert-True (Test-Path -LiteralPath $atomicPath -PathType Leaf) 'atomic-checkpoint-created'
Assert-True (@(Get-ChildItem -LiteralPath $unitRoot -Filter '*.tmp-*' -Force).Count -eq 0) 'atomic-no-temp-files'
Assert-True ((Read-G13RJson $atomicPath).status -eq 'failed-no-auto-retry-no-resume') 'atomic-roundtrip'

$boundPaths = @(
    @('Research/Gate13R_NonExecuting_Preparation_Authorization.v1.json', 'b9bc74c033f1c2be795136067eb91305fea1a3cf3ce89a97bb7379a279ec7c99'),
    @('Research/Gate13R_NonExecuting_Preparation_Specification.v1.md', '0ea4c99fc86f6de4db4c52d39b7667436fad1bb8278bcd824e6fe7dba7f94f0a'),
    @('Research/Gate13R_NonExecuting_Preparation_Test_Design.v1.md', '9fdea33cb9ba25fade02179bebeeedb23da2a8f7389e478f671fb91a8cec45c6'),
    @('Research/Gate13R_Readiness_Amendment.v1.json', '72d6ed97aebcf652d6796a72a3794ff11b39ed166271eb9ee8d87e8205984db7'),
    @('Research/FormalScenarios/Gate11R_5pct/v1/bundle-manifest.json', '5baaeec18344a9e99e55da38f3c4875b7e7e9f3bf0add9d5f2d2f1e821b5f7fc'),
    @('Research/Gate12R_Readiness_Checkpoint.v1.json', '93d1ffac30305ecbc3ff32820aa0eee016c7a2cc6824f41c491aac393cfd291d')
)
foreach ($binding in $boundPaths) {
    try { $null = Assert-G13RBoundFile -ProjectPath $ProjectPath -RelativePath $binding[0] -ExpectedSha256 $binding[1] -Role $binding[0]; Assert-True $true ("bound-" + $binding[0]) }
    catch { Assert-True $false ("bound-" + $binding[0]) }
}
Assert-False (Test-Path -LiteralPath $formalRoot) 'formal-root-remains-absent'
Assert-True (@(Get-Process -Name Unity -ErrorAction SilentlyContinue).Count -eq 0) 'unity-process-count-zero'
Assert-False (Test-Path -LiteralPath (Join-Path $ProjectPath 'Temp\UnityLockfile')) 'unity-lock-absent'

$summary = [ordered]@{
    schemaVersion = 1
    summaryKind = 'gate13r-nonexecuting-preparation-unit-tests-v2'
    versionedRepair = 'windows-powershell-5.1-empty-enumeration-array-wrap-v1'
    attempt1FailureRelativePath = 'Research/Gate13R_UnitAttempt1_Failure.v1.json'
    savedAtUtc = [DateTime]::UtcNow.ToString('o')
    assertionCount = $assertions
    failureCount = $failures.Count
    failures = $failures.ToArray()
    formalRootExists = Test-Path -LiteralPath $formalRoot
    formalExecutionReceiptCreated = $false
    unityProcessCount = @(Get-Process -Name Unity -ErrorAction SilentlyContinue).Count
    passed = $failures.Count -eq 0
}
$summaryPath = Join-Path $unitRoot 'summary.json'
Write-G13RAtomicUtf8NoBomJson -Path $summaryPath -Value $summary -Depth 20
if ($failures.Count -gt 0) { Write-Error ('Gate13R unit tests failed: ' + ($failures -join '; ')); exit 1 }
Write-Host "Gate13R unit tests passed: $assertions assertions." -ForegroundColor Green
exit 0
