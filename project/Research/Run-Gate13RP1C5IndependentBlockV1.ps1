[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$ProjectPath,
    [Parameter(Mandatory = $true)][string]$BlockPlanPath,
    [Parameter(Mandatory = $true)][string]$OutputDirectory,
    [Parameter(Mandatory = $true)][string]$AllowedRoot,
    [ValidateSet('FormalIndependentStudy')][string]$Mode = 'FormalIndependentStudy',
    [Parameter(Mandatory = $true)][string]$ExecutionReceiptPath,
    [string]$UnityPath = 'H:\UnityEditor\2022.3.30f1c1\Editor\Unity.exe',
    [ValidateSet('Pass')][string]$ExpectedOutcome = 'Pass',
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
    Write-Output "BINDING-SMOKE-PASSED|Run-Gate13RP1C5IndependentBlockV1|$Mode|$ProjectPath"
    exit 0
}

Import-Module (Join-Path $ProjectPath 'Research\Gate13RPR2MP2MemoryPolicyV2.psm1') -Force
Import-Module (Join-Path $ProjectPath 'Research\Gate10RLockHygieneV3.psm1') -Force
$BlockPlanPath = [IO.Path]::GetFullPath($BlockPlanPath)
$OutputDirectory = [IO.Path]::GetFullPath($OutputDirectory)
$AllowedRoot = [IO.Path]::GetFullPath($AllowedRoot).TrimEnd('\', '/')
$ExecutionReceiptPath = [IO.Path]::GetFullPath($ExecutionReceiptPath)
$UnityPath = [IO.Path]::GetFullPath($UnityPath)
$formalRoot = [IO.Path]::GetFullPath((Join-Path $ProjectPath 'Research\FormalRuns\Gate13R_P1C5_Independent\v1')).TrimEnd('\', '/')
$formalReceipt = [IO.Path]::GetFullPath((Join-Path $ProjectPath 'Research\Gate13R_P1C5_Independent_Execution_Receipt.v1.json'))

foreach ($required in @($BlockPlanPath, $ExecutionReceiptPath)) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) { throw "Required P1-C5 study file is missing: $required" }
}
if (-not (Test-Path -LiteralPath $AllowedRoot -PathType Container)) { throw 'Allowed root must already exist; this adapter never creates a run root.' }
if (-not $AllowedRoot.Equals($formalRoot, [StringComparison]::OrdinalIgnoreCase)) { throw 'P1-C5 independent formal root identity mismatch.' }
if (-not $ExecutionReceiptPath.Equals($formalReceipt, [StringComparison]::OrdinalIgnoreCase)) { throw 'P1-C5 independent receipt identity mismatch.' }
if (-not (Test-G13RPR2MP2PathWithin -BasePath $AllowedRoot -CandidatePath $BlockPlanPath) -or -not (Test-G13RPR2MP2PathWithin -BasePath $AllowedRoot -CandidatePath $OutputDirectory)) { throw 'Block plan/output escapes the allowed root.' }

$plan = Read-JsonFile $BlockPlanPath
if ([int]$plan.schemaVersion -ne 3 -or [string]$plan.planId -ne 'gate13r-p1c5-independent-block-plan-v1' -or [string]$plan.designId -ne 'gate13r-p1c5-independent-confirmatory-study-v1') { throw 'P1-C5 block-plan identity mismatch.' }
if ([string]$plan.memoryPolicyId -ne 'gate13r-pr2-mp2-layered-scenario-aware-memory-policy-v1') { throw 'MP2 policy identity mismatch.' }
if ($plan.validationOnly -ne $false -or $plan.formalCampaign -ne $true -or [string]$plan.analysisRole -ne 'formal-timing') { throw 'P1-C5 formal block-plan authorization boundary mismatch.' }
if ([int]$plan.verificationInjectedFailurePosition -ne 0 -or [int]$plan.validationInjectedNativeHardPosition -ne 0 -or [int]$plan.validationInjectedTelemetryFailurePosition -ne 0 -or [int]$plan.validationInjectedPersistenceFailurePosition -ne 0) { throw 'Formal plans cannot contain validation injections.' }
if ([string]$plan.executionReceiptRelativePath -ne 'Research/Gate13R_P1C5_Independent_Execution_Receipt.v1.json') { throw 'Block plan / P1-C5 receipt path mismatch.' }
if ([string]$plan.executionReceiptSha256 -ne (Get-G13RPR2MP2Sha256 $ExecutionReceiptPath)) { throw 'Block plan / P1-C5 receipt SHA-256 mismatch.' }

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
    [pscustomobject][ordered]@{passed=$true;mode=$Mode;noUnityLaunched=$true;blockId=[string]$plan.blockId;policyTierId=[string]$plan.policyTierId;canonicalMaximumGridDimension=[int]$plan.canonicalMaximumGridDimension;formalRoot=$formalRoot;formalReceipt=$formalReceipt} | ConvertTo-Json -Depth 10
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
$arguments = @('-batchmode','-nographics','-quit','-projectPath',('"'+$ProjectPath+'"'),'-executeMethod','DDM.Research.Editor.Gate13RP1C5FormalBatchCommandV1.Run','-ddmGate13RP1C5BlockPlanPath',('"'+$BlockPlanPath+'"'),'-ddmGate13RP1C5BlockPlanSha256',$planSha256,'-ddmGate13RP1C5OutputDirectory',('"'+$OutputDirectory+'"'),'-logFile',('"'+$unityLogPath+'"'))
$process = Start-Process -FilePath $UnityPath -ArgumentList $arguments -WorkingDirectory (Split-Path -Parent $UnityPath) -WindowStyle Hidden -PassThru
$timedOut = $false
$deadline = (Get-Date).AddSeconds($TimeoutSeconds)
while (-not $process.HasExited) { if ((Get-Date) -ge $deadline) { $timedOut=$true;break }; Start-Sleep -Milliseconds 500; $process.Refresh() }
if ($timedOut) { & taskkill.exe /PID $process.Id /T /F 2>&1 | Out-Null; try { Wait-Process -Id $process.Id -Timeout 30 -ErrorAction SilentlyContinue } catch {} }
$process.Refresh()
$exitCode = if ($timedOut) { 124 } else { [int]$process.ExitCode }
$completedAt = Get-Date
$lock = Invoke-Gate10RPostExitQuiescenceV3 -ProjectPath $ProjectPath -OwnedProcessId $process.Id -OwnedProcessStartedAt ([DateTimeOffset]$started) -OwnedProcessCompletedAt ([DateTimeOffset]$completedAt) -Role 'positive' -EvidenceDirectory ($OutputDirectory + '.lock-hygiene') -ContextId ([string]$plan.blockId) -QuiescenceSeconds 10 -PollMilliseconds 250 -TimestampToleranceSeconds 2

$logText = if (Test-Path -LiteralPath $unityLogPath) { Get-Content -LiteralPath $unityLogPath -Raw -Encoding UTF8 } else { '' }
$compilerMatches = if ($logText.Length -gt 0) { @($logText | Select-String -Pattern 'error CS\d+|Compilation failed|Scripts have compiler errors|executeMethod.+could not be found' -AllMatches -CaseSensitive:$false) } else { @() }
$manifestPath=Join-Path $OutputDirectory 'block-manifest.json'; $checkpointPath=Join-Path $OutputDirectory 'block-checkpoint.json'; $failurePath=Join-Path $OutputDirectory 'block-failure.json'
$manifest=if(Test-Path $manifestPath){Read-JsonFile $manifestPath}else{$null}; $checkpoint=if(Test-Path $checkpointPath){Read-JsonFile $checkpointPath}else{$null}; $failure=if(Test-Path $failurePath){Read-JsonFile $failurePath}else{$null}
$errors=New-Object Collections.Generic.List[string]
$lockMode = if ($null -ne $lock) { [string]$lock.mode } else { '' }
if($timedOut){$errors.Add("hard-timeout-$TimeoutSeconds")}; if(@($compilerMatches).Count -gt 0){$errors.Add("compiler-patterns-$(@($compilerMatches).Count)")}; if($logText.Contains('No valid Unity Editor license found') -or $logText.Contains('License is not active (com.unity.editor.headless)')){$errors.Add('unity-license-hard-failure')}; if($null -eq $lock -or $lock.passed -ne $true -or $lockMode -ne 'natural-lock-absence'){$errors.Add('post-exit-lock-hygiene')}
if($exitCode -ne 0){$errors.Add("unity-exit-$exitCode")}; if($null -eq $manifest -or [int]$manifest.schemaVersion -ne 5 -or [string]$manifest.manifestKind -ne 'gate13r-p1c5-independent-formal-block-manifest-v1'){$errors.Add('positive-manifest-identity')}elseif($manifest.completed -ne $true -or $manifest.hardMemoryRulesPassed -ne $true -or [string]$manifest.memoryGatePolicyId -ne 'gate13r-pr2-mp2-layered-scenario-aware-memory-policy-v1' -or [string]$manifest.nativeCrossingAttributionScope -ne 'WHOLE-BLOCK-PROCESS' -or -not [string]::IsNullOrEmpty([string]$manifest.attributedAlgorithmId)){$errors.Add('positive-manifest-contract')}; if($null -eq $checkpoint -or [string]$checkpoint.status -ne 'block-completed'){$errors.Add('positive-terminal-checkpoint')}; if($null -ne $failure){$errors.Add('positive-unexpected-failure')}
$summary = [ordered]@{
    schemaVersion = 1
    summaryKind = 'gate13r-p1c5-independent-block-wrapper-summary-v1'
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
    lockHygieneRole = 'positive'
    lockHygieneModeAccepted = $lockMode -eq 'natural-lock-absence'
    validationOnly = $false
    formalCampaign = $true
    formalAttemptOrdinal = 1
    automaticRetryAttempted = $false
    automaticResumeAttempted = $false
    errors = $errors.ToArray()
    passed = $errors.Count -eq 0
}
Write-AtomicJson -Path $summaryPath -Value $summary
if($errors.Count -gt 0){Write-Error ('Gate13R P1-C5 block validation failed: '+($errors-join'; '));exit 1}
Write-Host "Gate13R P1-C5 block wrapper passed: $($plan.blockId)" -ForegroundColor Green
exit 0
