[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$ProjectPath,
    [string]$BlockPlanPath,
    [string]$OutputDirectory,
    [string]$AllowedRoot,
    [ValidateSet('ValidationOnly','FormalAttempt3')][string]$Mode = 'ValidationOnly',
    [string]$ExecutionReceiptPath = '',
    [string]$UnityPath = 'H:\UnityEditor\2022.3.30f1c1\Editor\Unity.exe',
    [ValidateSet('Pass','NativeHard','TelemetryFailure','PersistenceFailure','AnyFailure')][string]$ExpectedOutcome = 'Pass',
    [switch]$BindingSmokeOnly,
    [switch]$NoLaunchDryRun,
    [int]$TimeoutSeconds = 3600
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

function Read-JsonFile([string]$Path) {
    return (Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json)
}

function Write-AtomicJson([string]$Path, [object]$Value) {
    $full = [IO.Path]::GetFullPath($Path)
    $parent = Split-Path -Parent $full
    if (-not (Test-Path -LiteralPath $parent -PathType Container)) { throw "Atomic parent is missing: $parent" }
    $temporary = Join-Path $parent ('.g13tmp-' + [Guid]::NewGuid().ToString('N'))
    try {
        [IO.File]::WriteAllText($temporary, (($Value | ConvertTo-Json -Depth 50) + "`n"), (New-Object Text.UTF8Encoding($false)))
        if (Test-Path -LiteralPath $full) { throw "Create-new JSON target already exists: $full" }
        [IO.File]::Move($temporary, $full)
    } finally {
        if (Test-Path -LiteralPath $temporary -PathType Leaf) { Remove-Item -LiteralPath $temporary -Force }
    }
}

if ([string]::IsNullOrWhiteSpace($ProjectPath) -or -not [IO.Path]::IsPathRooted($ProjectPath)) { throw 'An explicit absolute ProjectPath is required.' }
$ProjectPath = [IO.Path]::GetFullPath($ProjectPath)
if ($BindingSmokeOnly) {
    Write-Output "BINDING-SMOKE-PASSED|Run-Gate13RPR2MP2FormalBlockV2|$Mode|$ProjectPath"
    exit 0
}

Import-Module (Join-Path $ProjectPath 'Research\Gate13RPR2MP2MemoryPolicyV2.psm1') -Force
Import-Module (Join-Path $ProjectPath 'Research\Gate10RLockHygieneV3.psm1') -Force
if ([string]::IsNullOrWhiteSpace($BlockPlanPath) -or [string]::IsNullOrWhiteSpace($OutputDirectory) -or [string]::IsNullOrWhiteSpace($AllowedRoot)) { throw 'BlockPlanPath, OutputDirectory and AllowedRoot are required outside binding-smoke mode.' }
$BlockPlanPath = [IO.Path]::GetFullPath($BlockPlanPath)
$OutputDirectory = [IO.Path]::GetFullPath($OutputDirectory)
$AllowedRoot = [IO.Path]::GetFullPath($AllowedRoot).TrimEnd('\', '/')
$UnityPath = [IO.Path]::GetFullPath($UnityPath)
if (-not (Test-Path -LiteralPath $BlockPlanPath -PathType Leaf)) { throw 'Block plan is missing.' }
if (-not (Test-Path -LiteralPath $AllowedRoot -PathType Container)) { throw 'Allowed root must already exist; this adapter never creates a run root.' }
if (-not (Test-G13RPR2MP2PathWithin -BasePath $AllowedRoot -CandidatePath $BlockPlanPath) -or -not (Test-G13RPR2MP2PathWithin -BasePath $AllowedRoot -CandidatePath $OutputDirectory)) { throw 'Block plan/output escapes the allowed root.' }

$formalRoot = [IO.Path]::GetFullPath((Join-Path $ProjectPath 'Research\FormalRuns\Gate13R_RQAligned_S48H48\v3')).TrimEnd('\', '/')
$verificationRoot = [IO.Path]::GetFullPath((Join-Path $ProjectPath 'Research\Verification\Gate13R_PR2_MP2')).TrimEnd('\', '/')
$formalReceipt = [IO.Path]::GetFullPath((Join-Path $ProjectPath 'Research\Gate13R_PR2_Formal_Execution_Receipt.v3.json'))
if ($Mode -eq 'ValidationOnly') {
    [void](Assert-G13RPR2MP2FormalAttempt3Absent -ProjectPath $ProjectPath)
    if (-not (Test-G13RPR2MP2PathWithin -BasePath $verificationRoot -CandidatePath $AllowedRoot)) { throw 'Validation mode is restricted to the independent MP2 verification root.' }
    if (-not [string]::IsNullOrWhiteSpace($ExecutionReceiptPath)) { throw 'Validation mode cannot accept a formal execution receipt.' }
} else {
    if (-not $AllowedRoot.Equals($formalRoot, [StringComparison]::OrdinalIgnoreCase)) { throw 'Formal attempt-3 root identity mismatch.' }
    if ([string]::IsNullOrWhiteSpace($ExecutionReceiptPath)) { throw 'Formal attempt-3 mode requires an explicit receipt path.' }
    $ExecutionReceiptPath = [IO.Path]::GetFullPath($ExecutionReceiptPath)
    if (-not $ExecutionReceiptPath.Equals($formalReceipt, [StringComparison]::OrdinalIgnoreCase) -or -not (Test-Path -LiteralPath $ExecutionReceiptPath -PathType Leaf)) { throw 'Formal attempt-3 receipt identity/missing error.' }
}

$plan = Read-JsonFile $BlockPlanPath
if ([int]$plan.schemaVersion -ne 3 -or [string]$plan.planId -ne 'gate13r-pr2-mp2-block-plan-v1' -or [string]$plan.designId -ne 'gate10r-one-fresh-unity-process-per-williams-block-5pct-v1') { throw 'MP2 block-plan identity mismatch.' }
if ([string]$plan.memoryPolicyId -ne 'gate13r-pr2-mp2-layered-scenario-aware-memory-policy-v1') { throw 'MP2 policy identity mismatch.' }
if ($Mode -eq 'ValidationOnly') {
    if ($plan.validationOnly -ne $true -or $plan.formalCampaign -ne $false -or [string]$plan.analysisRole -ne 'validation-only') { throw 'Validation block-plan authorization boundary mismatch.' }
} else {
    if ($plan.validationOnly -ne $false -or $plan.formalCampaign -ne $true -or [string]$plan.analysisRole -ne 'formal-timing') { throw 'Formal attempt-3 block-plan authorization boundary mismatch.' }
    if ([int]$plan.verificationInjectedFailurePosition -ne 0 -or [int]$plan.validationInjectedNativeHardPosition -ne 0 -or [int]$plan.validationInjectedTelemetryFailurePosition -ne 0 -or [int]$plan.validationInjectedPersistenceFailurePosition -ne 0) { throw 'Formal plans cannot contain validation injections.' }
    if ([string]$plan.executionReceiptSha256 -ne (Get-G13RPR2MP2Sha256 $ExecutionReceiptPath)) { throw 'Block plan / formal attempt-3 receipt SHA-256 mismatch.' }
}

$bound = @(
    @([string]$plan.formalConfigRelativePath,[string]$plan.formalConfigSha256),
    @([string]$plan.specificationRelativePath,[string]$plan.specificationSha256),
    @([string]$plan.testDesignRelativePath,[string]$plan.testDesignSha256),
    @([string]$plan.amendmentRelativePath,[string]$plan.amendmentSha256),
    @([string]$plan.commandRelativePath,[string]$plan.commandSha256),
    @([string]$plan.provenanceRelativePath,[string]$plan.provenanceSha256),
    @([string]$plan.memoryPolicyRegistryRelativePath,[string]$plan.memoryPolicyRegistrySha256),
    @([string]$plan.scenarioPolicyMappingRelativePath,[string]$plan.scenarioPolicyMappingSha256),
    @([string]$plan.schedulePolicyOverlayRelativePath,[string]$plan.schedulePolicyOverlaySha256)
)
foreach ($pair in $bound) {
    $path = [IO.Path]::GetFullPath((Join-Path $ProjectPath $pair[0].Replace('/', '\')))
    if (-not (Test-G13RPR2MP2PathWithin -BasePath $ProjectPath -CandidatePath $path) -or -not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Bound file is missing/outside project: $($pair[0])" }
    if ((Get-G13RPR2MP2Sha256 $path) -ne $pair[1]) { throw "Bound file SHA-256 mismatch: $($pair[0])" }
}
$tier = Resolve-G13RPR2MP2ScenarioTier -GridWidth $plan.gridWidth -GridHeight $plan.gridHeight
if ([string]$tier.tierId -ne [string]$plan.policyTierId -or [int64]$tier.nativeAdvisoryBytes -ne [int64]$plan.nativeAdvisoryThresholdBytes -or [int64]$tier.nativeHardBytes -ne [int64]$plan.nativeHardThresholdBytes) { throw 'Block plan tier differs from deterministic MP2 policy.' }
if ([int64]$plan.hostAbsoluteNativeEmergencyBytes -ne 4294967296L -or [int64]$plan.hostRelativeNativeGrowthEmergencyBytes -ne 2147483648L -or [int64]$plan.hostAvailablePhysicalMemoryFloorBytes -ne 8589934592L) { throw 'Host safety threshold mismatch.' }

if ($NoLaunchDryRun) {
    [pscustomobject][ordered]@{passed=$true;mode=$Mode;noUnityLaunched=$true;blockId=[string]$plan.blockId;policyTierId=[string]$plan.policyTierId;canonicalMaximumGridDimension=[int]$plan.canonicalMaximumGridDimension;formalAttempt3RootAbsent=(-not (Test-Path -LiteralPath $formalRoot));formalAttempt3ReceiptAbsent=(-not (Test-Path -LiteralPath $formalReceipt))} | ConvertTo-Json -Depth 10
    exit 0
}

if (-not (Test-Path -LiteralPath $UnityPath -PathType Leaf)) { throw 'Unity executable is missing.' }
if (Test-Path -LiteralPath $OutputDirectory) { if (-not (Test-Path -LiteralPath $OutputDirectory -PathType Container) -or @(Get-ChildItem -LiteralPath $OutputDirectory -Force).Count -gt 0) { throw "Output is not fresh: $OutputDirectory" } }
$unityLogPath = $OutputDirectory + '.Unity.log'
$summaryPath = $OutputDirectory + '.summary.json'
foreach ($sidecar in @($unityLogPath,$summaryPath)) { if (Test-Path -LiteralPath $sidecar) { throw "Create-new sidecar exists: $sidecar" } }
if (@(Get-Process -Name Unity -ErrorAction SilentlyContinue).Count -gt 0 -or (Test-Path -LiteralPath (Join-Path $ProjectPath 'Temp\UnityLockfile'))) { throw 'Unity must be quiescent and the project lock absent before a block.' }

$planSha256 = Get-G13RPR2MP2Sha256 $BlockPlanPath
$started = Get-Date
$arguments = @('-batchmode','-nographics','-quit','-projectPath',('"'+$ProjectPath+'"'),'-executeMethod','DDM.Research.Editor.Gate13RPR2FormalBatchCommandV5.Run','-ddmGate13RPR2BlockPlanPath',('"'+$BlockPlanPath+'"'),'-ddmGate13RPR2BlockPlanSha256',$planSha256,'-ddmGate13RPR2OutputDirectory',('"'+$OutputDirectory+'"'),'-logFile',('"'+$unityLogPath+'"'))
$process = Start-Process -FilePath $UnityPath -ArgumentList $arguments -WorkingDirectory (Split-Path -Parent $UnityPath) -WindowStyle Hidden -PassThru
$timedOut = $false
$deadline = (Get-Date).AddSeconds($TimeoutSeconds)
while (-not $process.HasExited) { if ((Get-Date) -ge $deadline) { $timedOut=$true;break }; Start-Sleep -Milliseconds 500; $process.Refresh() }
if ($timedOut) { & taskkill.exe /PID $process.Id /T /F 2>&1 | Out-Null; try { Wait-Process -Id $process.Id -Timeout 30 -ErrorAction SilentlyContinue } catch {} }
$process.Refresh()
$exitCode = if ($timedOut) { 124 } else { [int]$process.ExitCode }
$completedAt = Get-Date
$lockRole = if ($ExpectedOutcome -eq 'Pass') { 'positive' } else { 'expected-negative' }
$lock = Invoke-Gate10RPostExitQuiescenceV3 -ProjectPath $ProjectPath -OwnedProcessId $process.Id -OwnedProcessStartedAt ([DateTimeOffset]$started) -OwnedProcessCompletedAt ([DateTimeOffset]$completedAt) -Role $lockRole -EvidenceDirectory ($OutputDirectory + '.lock-hygiene') -ContextId ([string]$plan.blockId) -QuiescenceSeconds 10 -PollMilliseconds 250 -TimestampToleranceSeconds 2

$logText = if (Test-Path -LiteralPath $unityLogPath) { Get-Content -LiteralPath $unityLogPath -Raw -Encoding UTF8 } else { '' }
$compilerMatches = if ($logText.Length -gt 0) { @($logText | Select-String -Pattern 'error CS\d+|Compilation failed|Scripts have compiler errors|executeMethod.+could not be found' -AllMatches -CaseSensitive:$false) } else { @() }
$manifestPath=Join-Path $OutputDirectory 'block-manifest.json'; $checkpointPath=Join-Path $OutputDirectory 'block-checkpoint.json'; $failurePath=Join-Path $OutputDirectory 'block-failure.json'
$manifest=if(Test-Path $manifestPath){Read-JsonFile $manifestPath}else{$null}; $checkpoint=if(Test-Path $checkpointPath){Read-JsonFile $checkpointPath}else{$null}; $failure=if(Test-Path $failurePath){Read-JsonFile $failurePath}else{$null}
$errors=New-Object Collections.Generic.List[string]
if($timedOut){$errors.Add("hard-timeout-$TimeoutSeconds")}; if(@($compilerMatches).Count -gt 0){$errors.Add("compiler-patterns-$(@($compilerMatches).Count)")}; if($logText.Contains('No valid Unity Editor license found') -or $logText.Contains('License is not active (com.unity.editor.headless)')){$errors.Add('unity-license-hard-failure')}; if($null -eq $lock -or $lock.passed -ne $true -or [string]$lock.mode -ne 'natural-lock-absence'){$errors.Add('post-exit-lock-hygiene')}
if($ExpectedOutcome -eq 'Pass'){
    if($exitCode -ne 0){$errors.Add("unity-exit-$exitCode")}; if($null -eq $manifest -or [int]$manifest.schemaVersion -ne 5 -or [string]$manifest.manifestKind -ne 'gate13r-pr2-mp2-formal-attempt3-candidate-block-manifest-v1'){$errors.Add('positive-manifest-identity')}elseif($manifest.completed -ne $true -or $manifest.hardMemoryRulesPassed -ne $true -or [string]$manifest.memoryGatePolicyId -ne 'gate13r-pr2-mp2-layered-scenario-aware-memory-policy-v1' -or [string]$manifest.nativeCrossingAttributionScope -ne 'WHOLE-BLOCK-PROCESS' -or -not [string]::IsNullOrEmpty([string]$manifest.attributedAlgorithmId)){$errors.Add('positive-manifest-contract')}; if($null -eq $checkpoint -or [string]$checkpoint.status -ne 'block-completed'){$errors.Add('positive-terminal-checkpoint')}; if($null -ne $failure){$errors.Add('positive-unexpected-failure')}
}else{
    if($exitCode -eq 0){$errors.Add('negative-unexpected-zero-exit')}; if($null -eq $failure -or [string]$failure.message -eq ''){$errors.Add('negative-failure-evidence-missing')}; if($null -eq $checkpoint -or [string]$checkpoint.status -ne 'failed-no-auto-retry'){$errors.Add('negative-terminal-checkpoint')}; if($null -ne $failure -and ($failure.automaticRetryAttempted -ne $false -or $failure.automaticResumeAttempted -ne $false -or $failure.laterPositionsExecuted -ne $false)){$errors.Add('negative-fail-closed-semantics')}
    if($ExpectedOutcome -eq 'NativeHard'){if($null -eq $manifest -or $manifest.completed -ne $true -or $manifest.hardMemoryRulesPassed -ne $false -or $manifest.nativeHardCrossed -ne $true -or [string]$manifest.nativeCrossingAttributionScope -ne 'WHOLE-BLOCK-PROCESS' -or -not [string]::IsNullOrEmpty([string]$manifest.attributedAlgorithmId)){$errors.Add('negative-native-hard-contract')}; if($null -eq $failure -or -not ([string]$failure.memoryGateReasonCode).Contains('HARD-FAIL-NATIVE-RESIDENCY-TIER-CEILING')){$errors.Add('negative-native-hard-reason')}}
    if($ExpectedOutcome -eq 'TelemetryFailure' -and ($null -eq $failure -or -not ([string]$failure.memoryGateReasonCode).Contains('HARD-FAIL-TELEMETRY'))){$errors.Add('negative-telemetry-reason')}; if($ExpectedOutcome -eq 'PersistenceFailure' -and ($null -eq $failure -or -not ([string]$failure.message).Contains('HARD-FAIL-PERSISTENCE-VALIDATION-INJECTION'))){$errors.Add('negative-persistence-reason')}
}
$summary = [ordered]@{
    schemaVersion = 1
    summaryKind = 'gate13r-pr2-mp2-block-wrapper-validation-summary-v1'
    savedAtUtc = [DateTime]::UtcNow.ToString('o')
    mode = $Mode
    expectedOutcome = $ExpectedOutcome
    blockId = [string]$plan.blockId
    blockPlanSha256 = $planSha256
    outputDirectory = $OutputDirectory
    unityProcessId = [int]$process.Id
    exitCode = $exitCode
    timedOut = $timedOut
    wallSeconds = ($completedAt - $started).TotalSeconds
    blockManifestSha256 = if (Test-Path $manifestPath) { Get-G13RPR2MP2Sha256 $manifestPath } else { $null }
    blockFailureSha256 = if (Test-Path $failurePath) { Get-G13RPR2MP2Sha256 $failurePath } else { $null }
    lockHygieneMode = if ($null -ne $lock) { [string]$lock.mode } else { $null }
    validationOnly = $Mode -eq 'ValidationOnly'
    formalCampaign = $Mode -eq 'FormalAttempt3'
    automaticRetryAttempted = $false
    automaticResumeAttempted = $false
    errors = $errors.ToArray()
    passed = $errors.Count -eq 0
}
Write-AtomicJson -Path $summaryPath -Value $summary
if($Mode -eq 'ValidationOnly'){[void](Assert-G13RPR2MP2FormalAttempt3Absent -ProjectPath $ProjectPath)}
if($errors.Count -gt 0){Write-Error ('Gate13R-PR2-MP2 block validation failed: '+($errors-join'; '));exit 1}
Write-Host "Gate13R-PR2-MP2 block wrapper passed: $($plan.blockId) / $ExpectedOutcome" -ForegroundColor Green
exit 0
