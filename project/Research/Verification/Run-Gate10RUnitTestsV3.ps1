[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$ProjectPath,
    [switch]$BindingSmokeOnly
)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($ProjectPath) -or -not [System.IO.Path]::IsPathRooted($ProjectPath)) { throw 'Attempt 3 requires an explicit absolute ProjectPath.' }
$ProjectPath = [System.IO.Path]::GetFullPath($ProjectPath)
if ($BindingSmokeOnly) { Write-Output ('BINDING-SMOKE-PASSED|Run-Gate10RUnitTestsV3|' + $ProjectPath); exit 0 }
$modulePath = Join-Path $ProjectPath 'Research\Gate10RProcessReusePreparation.psm1'
$lockModulePath = Join-Path $ProjectPath 'Research\Gate10RLockHygieneV3.psm1'
$configPath = Join-Path $ProjectPath 'Research\Gate10R_ProcessReuse_5pct_Attempt3_Config.v3.json'
$authorizationPath = Join-Path $ProjectPath 'Research\Gate10R_Attempt3_Execution_Authorization.v1.json'
$sourcePath = Join-Path $ProjectPath 'Assets\_Scripts\Research\Editor\Gate10RProcessReuseBatchCommand.cs'
$historicalSourcePath = Join-Path $ProjectPath 'Assets\_Scripts\Research\Editor\ResearchPlanningProcessReuseBatchCommandV2.cs'
$root = Join-Path $PSScriptRoot 'Gate10R_ProcessReuse_5pct\v3'
$summaryPath = Join-Path $root 'UnitTests.summary.json'
if (Test-Path -LiteralPath $summaryPath) { throw 'Gate 10R attempt-3 unit-test summary already exists; refusing retry or overwrite.' }
if (-not (Test-Path -LiteralPath $modulePath -PathType Leaf) -or -not (Test-Path -LiteralPath $lockModulePath -PathType Leaf)) { throw 'Gate 10R module is missing.' }
Import-Module $modulePath -Force
Import-Module $lockModulePath -Force
$checks = New-Object System.Collections.Generic.List[object]
function Add-Check([string]$Name, [bool]$Passed, [string]$Detail) { $script:checks.Add([pscustomobject][ordered]@{name=$Name;passed=$Passed;detail=$Detail}) }

$parseTargets = @(
    $modulePath,
    $lockModulePath,
    (Join-Path $ProjectPath 'Research\Run-Gate10RProcessReuseBlockV3.ps1'),
    (Join-Path $ProjectPath 'Research\Run-Gate10RTelemetryProbeV3.ps1'),
    (Join-Path $ProjectPath 'Research\Run-Gate10RColdReferenceV3.ps1')
)
foreach ($target in $parseTargets) {
    $tokens = $null
    $parseErrors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($target, [ref]$tokens, [ref]$parseErrors)
    Add-Check ('powershell-parse-' + [IO.Path]::GetFileName($target)) ($parseErrors.Count -eq 0) ($parseErrors -join '; ')
}

$config = Read-Gate10RJson $configPath
$authorization = Read-Gate10RJson $authorizationPath
Add-Check 'config-design-id' ([string]$config.designId -eq 'gate10r-one-fresh-unity-process-per-williams-block-5pct-v1') ([string]$config.designId)
Add-Check 'config-formal-false' ($config.formalCampaign -eq $false) ([string]$config.formalCampaign)
Add-Check 'config-attempt3-root' ([int]$config.attempt -eq 3 -and [string]$config.verificationRoot -eq 'Research/Verification/Gate10R_ProcessReuse_5pct/v3') ([string]$config.verificationRoot)
Add-Check 'config-5pct-no-cap' ([double]$config.precisionPolicy.targetRelativeCiHalfWidth -eq 0.05 -and $null -eq $config.precisionPolicy.hardCap) '5% / null'
Add-Check 'downstream-authorization-revoked' ($config.downstreamAuthorization.gate11R -eq $false -and $config.downstreamAuthorization.gate12R -eq $false -and $authorization.gate11RConditionalContinuationAuthorized -eq $false -and $authorization.gate12RConditionalContinuationAuthorized -eq $false) 'Gate11R=false;Gate12R=false'
Add-Check 'lock-policy-exact-path' ([string]$config.lockHygiene.absoluteLockPath -eq 'H:/DDM_Final_Project/Temp/UnityLockfile') ([string]$config.lockHygiene.absoluteLockPath)
Add-Check 'lock-policy-bounded-wait' ([int]$config.lockHygiene.naturalQuiescenceSeconds -eq 60 -and [int]$config.lockHygiene.pollMilliseconds -eq 250) '60s / 250ms'
Add-Check 'lock-policy-negative-only' ($config.lockHygiene.expectedNegativeCleanupAllowed -eq $true -and $config.lockHygiene.positiveCleanupAllowed -eq $false -and $config.lockHygiene.compileCleanupAllowed -eq $false -and $config.lockHygiene.telemetryCleanupAllowed -eq $false -and $config.lockHygiene.coldReferenceCleanupAllowed -eq $false) 'negative-only'

$four = @('A*-R', 'D*L', 'C-FF', 'IDFF')
$fourRows = @(1..4 | ForEach-Object { ,@(Get-Gate10RWilliamsRow -Algorithms $four -Block $_) })
$two = @('A*-R', 'D*L')
$twoRows = @(1..2 | ForEach-Object { ,@(Get-Gate10RWilliamsRow -Algorithms $two -Block $_) })
Add-Check 'four-williams-unique-rows' (@(($fourRows | ForEach-Object {$_ -join '|'}) | Select-Object -Unique).Count -eq 4) (($fourRows | ForEach-Object {$_ -join ','}) -join ';')
Add-Check 'two-williams-unique-rows' (@(($twoRows | ForEach-Object {$_ -join '|'}) | Select-Object -Unique).Count -eq 2) (($twoRows | ForEach-Object {$_ -join ','}) -join ';')
$fourPositionBalanced = $true
foreach ($a in $four) { foreach ($p in 0..3) { if (@($fourRows | ForEach-Object {$_[$p]} | Where-Object {$_ -eq $a}).Count -ne 1) { $fourPositionBalanced = $false } } }
Add-Check 'four-position-balance' $fourPositionBalanced 'each algorithm once per position over four rows'

$valid = [pscustomobject][ordered]@{schemaVersion=2;planId='unit-plan';designId='gate10r-one-fresh-unity-process-per-williams-block-5pct-v1';blockId='unit-b001';campaignId='unit';comparisonCohortId='four-algorithm-shared-goal-v1';block=1;formalCampaign=$false;analysisRole='excluded-verification';verificationInjectedFailurePosition=0;entries=@(
    [pscustomobject]@{position=1;algorithmId='A*-R';predecessorAlgorithmId='NONE';runId='u1';directory='runs/p01'},
    [pscustomobject]@{position=2;algorithmId='D*L';predecessorAlgorithmId='A*-R';runId='u2';directory='runs/p02'},
    [pscustomobject]@{position=3;algorithmId='IDFF';predecessorAlgorithmId='D*L';runId='u3';directory='runs/p03'},
    [pscustomobject]@{position=4;algorithmId='C-FF';predecessorAlgorithmId='IDFF';runId='u4';directory='runs/p04'})}
Add-Check 'valid-plan-accepted' (Test-Gate10RBlockPlanObject $valid).passed 'valid'
$duplicate = $valid | ConvertTo-Json -Depth 20 | ConvertFrom-Json; $duplicate.entries[3].algorithmId = 'A*-R'
Add-Check 'duplicate-algorithm-rejected' (-not (Test-Gate10RBlockPlanObject $duplicate).passed) 'rejected'
$wrongPred = $valid | ConvertTo-Json -Depth 20 | ConvertFrom-Json; $wrongPred.entries[1].predecessorAlgorithmId = 'NONE'
Add-Check 'wrong-predecessor-rejected' (-not (Test-Gate10RBlockPlanObject $wrongPred).passed) 'rejected'
$unsafe = $valid | ConvertTo-Json -Depth 20 | ConvertFrom-Json; $unsafe.entries[0].directory = '../escape'
Add-Check 'unsafe-path-rejected' (-not (Test-Gate10RBlockPlanObject $unsafe).passed) 'rejected'
$badFailure = $valid | ConvertTo-Json -Depth 20 | ConvertFrom-Json; $badFailure.verificationInjectedFailurePosition = 2
Add-Check 'injected-failure-role-guard' (-not (Test-Gate10RBlockPlanObject $badFailure).passed) 'rejected'

$mib = 1MB
Add-Check 'managed-negative-growth-pass' (Test-Gate10RManagedMemoryRule (200*$mib) (260*$mib) (190*$mib)).passed 'pass'
Add-Check 'managed-exact-128-pass' (Test-Gate10RManagedMemoryRule (200*$mib) (500*$mib) (328*$mib)).passed 'pass'
Add-Check 'managed-128-plus-one-fail' (-not (Test-Gate10RManagedMemoryRule (200*$mib) (500*$mib) ((328*$mib)+1)).passed) 'fail'
Add-Check 'raw-peak-cleanup-pass' (Test-Gate10RManagedMemoryRule (200*$mib) (900*$mib) (220*$mib)).passed 'pass'
Add-Check 'native-negative-growth-pass' (Test-Gate10RNativeGrowthRule (900*$mib) (800*$mib)).passed 'pass'
Add-Check 'native-exact-512-pass' (Test-Gate10RNativeGrowthRule (900*$mib) (1412*$mib)).passed 'pass'
Add-Check 'native-512-plus-one-fail' (-not (Test-Gate10RNativeGrowthRule (900*$mib) ((1412*$mib)+1)).passed) 'fail'
$telemetry = Test-Gate10RTelemetryComparison (1000*$mib) (1100*$mib) (1050*$mib)
Add-Check 'telemetry-inside-interval-pass' $telemetry.passed ([string]$telemetry.distanceBytes)
$telemetryBad = Test-Gate10RTelemetryComparison (100*$mib) (100*$mib) (1000*$mib)
Add-Check 'telemetry-outside-tolerance-fail' (-not $telemetryBad.passed) ([string]$telemetryBad.distanceBytes)
Add-Check 'telemetry-nonpositive-fail' (-not (Test-Gate10RTelemetryComparison 0 1 1).passed) 'fail'
$n0 = Get-Gate10RSampleSizeCandidate 0
$n1 = Get-Gate10RSampleSizeCandidate 0.1
Add-Check 'sample-size-minimum-32' ($n0.requiredNFormal -eq 32) ([string]$n0.requiredNFormal)
Add-Check 'sample-size-cycle-multiple' ($n1.requiredNFormal -ge 32 -and $n1.requiredNFormal % 4 -eq 0) ([string]$n1.requiredNFormal)
Add-Check 'sample-size-uncapped' ($null -eq $n1.hardCap -and $n1.candidateNFormal -eq $n1.requiredNFormal) 'uncapped'

$expectedPath = [IO.Path]::GetFullPath((Join-Path $ProjectPath 'Temp\UnityLockfile'))
$now = [DateTimeOffset]::UtcNow
$goodSnapshot = [pscustomobject][ordered]@{expectedPath=$expectedPath;resolvedPath=$expectedPath;pathMatchesExpected=$true;exists=$true;isLeaf=$true;isReparsePoint=$false;bytes=0L;sha256='e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855';creationTimeUtc=$now.UtcDateTime.ToString('o');lastWriteTimeUtc=$now.UtcDateTime.ToString('o');exclusiveReadWriteAvailable=$true;exclusiveOpenError=$null}
$goodEligibility = Test-Gate10RLockCleanupEligibilityV3 -Snapshot $goodSnapshot -Role 'expected-negative' -OwnedProcessStartedAt $now.AddSeconds(-1) -OwnedProcessCompletedAt $now.AddSeconds(1) -OwnedProcessAlive $false -UnityProcessCount 0
Add-Check 'lock-good-negative-eligible' $goodEligibility.eligible ($goodEligibility.errors -join ',')
$positiveEligibility = Test-Gate10RLockCleanupEligibilityV3 -Snapshot $goodSnapshot -Role 'positive' -OwnedProcessStartedAt $now.AddSeconds(-1) -OwnedProcessCompletedAt $now.AddSeconds(1) -OwnedProcessAlive $false -UnityProcessCount 0
Add-Check 'lock-positive-cleanup-rejected' (-not $positiveEligibility.eligible -and $positiveEligibility.errors -contains 'cleanup-role-not-authorized') ($positiveEligibility.errors -join ',')
$windowStart = $now.AddSeconds(-1)
$windowEnd = $now.AddSeconds(1)
$nonzero = $goodSnapshot | ConvertTo-Json -Depth 10 | ConvertFrom-Json; $nonzero.bytes = 1
Add-Check 'lock-nonzero-rejected' (-not (Test-Gate10RLockCleanupEligibilityV3 -Snapshot $nonzero -Role 'expected-negative' -OwnedProcessStartedAt $windowStart -OwnedProcessCompletedAt $windowEnd -OwnedProcessAlive $false -UnityProcessCount 0).eligible) 'rejected'
$wrongHash = $goodSnapshot | ConvertTo-Json -Depth 10 | ConvertFrom-Json; $wrongHash.sha256 = ('0' * 64)
Add-Check 'lock-wrong-hash-rejected' (-not (Test-Gate10RLockCleanupEligibilityV3 -Snapshot $wrongHash -Role 'expected-negative' -OwnedProcessStartedAt $windowStart -OwnedProcessCompletedAt $windowEnd -OwnedProcessAlive $false -UnityProcessCount 0).eligible) 'rejected'
$wrongPath = $goodSnapshot | ConvertTo-Json -Depth 10 | ConvertFrom-Json; $wrongPath.pathMatchesExpected = $false
Add-Check 'lock-wrong-path-rejected' (-not (Test-Gate10RLockCleanupEligibilityV3 -Snapshot $wrongPath -Role 'expected-negative' -OwnedProcessStartedAt $windowStart -OwnedProcessCompletedAt $windowEnd -OwnedProcessAlive $false -UnityProcessCount 0).eligible) 'rejected'
$reparse = $goodSnapshot | ConvertTo-Json -Depth 10 | ConvertFrom-Json; $reparse.isReparsePoint = $true
Add-Check 'lock-reparse-rejected' (-not (Test-Gate10RLockCleanupEligibilityV3 -Snapshot $reparse -Role 'expected-negative' -OwnedProcessStartedAt $windowStart -OwnedProcessCompletedAt $windowEnd -OwnedProcessAlive $false -UnityProcessCount 0).eligible) 'rejected'
$notExclusive = $goodSnapshot | ConvertTo-Json -Depth 10 | ConvertFrom-Json; $notExclusive.exclusiveReadWriteAvailable = $false
Add-Check 'lock-nonexclusive-rejected' (-not (Test-Gate10RLockCleanupEligibilityV3 -Snapshot $notExclusive -Role 'expected-negative' -OwnedProcessStartedAt $windowStart -OwnedProcessCompletedAt $windowEnd -OwnedProcessAlive $false -UnityProcessCount 0).eligible) 'rejected'
$oldTime = $goodSnapshot | ConvertTo-Json -Depth 10 | ConvertFrom-Json; $oldTime.creationTimeUtc = $now.AddMinutes(-10).UtcDateTime.ToString('o'); $oldTime.lastWriteTimeUtc = $oldTime.creationTimeUtc
Add-Check 'lock-outside-window-rejected' (-not (Test-Gate10RLockCleanupEligibilityV3 -Snapshot $oldTime -Role 'expected-negative' -OwnedProcessStartedAt $windowStart -OwnedProcessCompletedAt $windowEnd -OwnedProcessAlive $false -UnityProcessCount 0).eligible) 'rejected'
Add-Check 'lock-live-owned-pid-rejected' (-not (Test-Gate10RLockCleanupEligibilityV3 -Snapshot $goodSnapshot -Role 'expected-negative' -OwnedProcessStartedAt $windowStart -OwnedProcessCompletedAt $windowEnd -OwnedProcessAlive $true -UnityProcessCount 0).eligible) 'rejected'
Add-Check 'lock-other-unity-rejected' (-not (Test-Gate10RLockCleanupEligibilityV3 -Snapshot $goodSnapshot -Role 'expected-negative' -OwnedProcessStartedAt $windowStart -OwnedProcessCompletedAt $windowEnd -OwnedProcessAlive $false -UnityProcessCount 1).eligible) 'rejected'
$missingSnapshot = [pscustomobject][ordered]@{expectedPath=$expectedPath;resolvedPath=$expectedPath;pathMatchesExpected=$true;exists=$false;isLeaf=$false;isReparsePoint=$false;bytes=$null;sha256=$null;creationTimeUtc=$null;lastWriteTimeUtc=$null;exclusiveReadWriteAvailable=$false;exclusiveOpenError=$null}
Add-Check 'lock-missing-cleanup-rejected' (-not (Test-Gate10RLockCleanupEligibilityV3 -Snapshot $missingSnapshot -Role 'expected-negative' -OwnedProcessStartedAt $windowStart -OwnedProcessCompletedAt $windowEnd -OwnedProcessAlive $false -UnityProcessCount 0).eligible) 'rejected'
$lockSource = Get-Content -Raw -LiteralPath $lockModulePath
Add-Check 'lock-module-no-recursive-delete' (-not $lockSource.Contains('Remove-Item -Recurse') -and -not $lockSource.Contains('-Recurse -Force')) 'absent'
Add-Check 'lock-module-literal-delete-only' $lockSource.Contains('Remove-Item -LiteralPath $lockPath -Force') 'present'

$historicalResultPath = Join-Path $ProjectPath 'Research\Verification\Gate13R2_PositiveBlockFixtures\v1\four-algorithm-b001\runs\p01-astar-r\workload-result.json'
if (Test-Path -LiteralPath $historicalResultPath) {
    $a = Read-Gate10RJson $historicalResultPath
    $b = Read-Gate10RJson $historicalResultPath
    Add-Check 'structural-identical-pass' (Compare-Gate10RStructuralResults $a $b).passed 'pass'
    $c = Get-Content -Raw -LiteralPath $historicalResultPath | ConvertFrom-Json
    $c.agentCount = [int]$c.agentCount + 1
    Add-Check 'structural-mutation-detected' (-not (Compare-Gate10RStructuralResults $a $c).passed) 'detected'
} else { Add-Check 'structural-fixture-present' $false $historicalResultPath }

$source = Get-Content -Raw -LiteralPath $sourcePath
Add-Check 'source-new-design-only' ($source.Contains('gate10r-one-fresh-unity-process-per-williams-block-5pct-v1') -and -not $source.Contains('one-fresh-unity-process-per-williams-block-v2-native-telemetry')) 'identity'
Add-Check 'source-psapi' ($source.Contains('GetProcessMemoryInfo') -and $source.Contains('PROCESS_MEMORY_COUNTERS_EX') -and $source.Contains('PrivateUsage')) 'present'
Add-Check 'source-no-managed-process-native-fallback' (-not $source.Contains('Process.WorkingSet64') -and -not $source.Contains('Process.PrivateMemorySize64')) 'absent'
Add-Check 'source-no-inlining-boundary' $source.Contains('MethodImplOptions.NoInlining') 'present'
Add-Check 'historical-source-unchanged' ((Get-Gate10RLowerSha256 $historicalSourcePath) -eq '54811fdb7868f7509cd48281397018a29f5814911cfc83d96d63473dd6f50379') (Get-Gate10RLowerSha256 $historicalSourcePath)
Add-Check 'formal-root-absent' (-not (Test-Path -LiteralPath (Join-Path $ProjectPath 'Research\FormalRuns\Gate13R_ProcessReuse_5pct\v1'))) 'absent'
Add-Check 'gate11r-root-absent' (-not (Test-Path -LiteralPath (Join-Path $ProjectPath 'Research\FormalScenarios\Gate11R_5pct\v1'))) 'absent'
Add-Check 'gate12r-root-absent' (-not (Test-Path -LiteralPath (Join-Path $ProjectPath 'Research\PilotRuns\Gate12R_ProcessReuse_5pct\v1'))) 'absent'
Add-Check 'project-lock-absent-before-official-unit' (-not (Test-Path -LiteralPath (Join-Path $ProjectPath 'Temp\UnityLockfile'))) 'absent'

$temp = Join-Path $root 'unit-atomic-temp'
if (Test-Path -LiteralPath $temp) { throw 'Unit atomic temp unexpectedly exists.' }
New-Item -ItemType Directory -Path $temp -Force | Out-Null
$atomicPath = Join-Path $temp 'value.json'
Write-Gate10RAtomicUtf8NoBomJson $atomicPath ([ordered]@{value=1})
$atomicPass = (Read-Gate10RJson $atomicPath).value -eq 1 -and @(Get-ChildItem -LiteralPath $temp -Filter '*.tmp-*').Count -eq 0
Add-Check 'atomic-json-no-temp-residue' $atomicPass 'value=1'
[IO.Directory]::Delete($temp, $true)

$failed = @($checks | Where-Object {-not $_.passed})
$summary = [ordered]@{schemaVersion=1;summaryKind='gate10r-process-reuse-unit-tests-attempt3-v3';savedAtUtc=[DateTime]::UtcNow.ToString('o');assertionCount=$checks.Count;passedCount=$checks.Count-$failed.Count;failedCount=$failed.Count;checks=$checks.ToArray();formalCampaign=$false;automaticRetryAttempted=$false;automaticResumeAttempted=$false;passed=$failed.Count-eq 0}
Write-Gate10RAtomicUtf8NoBomJson $summaryPath $summary 50
if (-not $summary.passed) { Write-Error "Gate 10R attempt-3 unit tests failed: $($failed.name -join ', ')"; exit 1 }
Write-Host "Gate 10R attempt-3 unit tests passed: $($checks.Count)/$($checks.Count)" -ForegroundColor Green
exit 0
