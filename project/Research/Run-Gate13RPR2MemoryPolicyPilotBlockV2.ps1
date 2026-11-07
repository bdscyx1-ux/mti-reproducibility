# Mechanically derived for Gate13R-PR2-MP1 attempt 2 / v2.
# Frozen source: Research/Run-Gate13RPR2MemoryPolicyPilotBlockV1.ps1; SHA-256 d9b4acc8f5354cb10577795948a2748119c7eaa9185bf7417e315c0a78dd0e7c.
# Allowed changes: v2 root/receipt/output routing and v2 path-safe atomic writer only.
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$ProjectPath,
    [Parameter(Mandatory = $true)][string]$BlockPlanPath,
    [Parameter(Mandatory = $true)][string]$OutputDirectory,
    [Parameter(Mandatory = $true)][string]$AllowedRoot,
    [Parameter(Mandatory = $true)][string]$ExecutionReceiptPath,
    [string]$UnityPath = 'H:\UnityEditor\2022.3.30f1c1\Editor\Unity.exe',
    [switch]$ValidationOnly,
    [switch]$ExpectFailure,
    [switch]$BindingSmokeOnly,
    [int]$TimeoutSeconds = 3600
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if ([string]::IsNullOrWhiteSpace($ProjectPath) -or -not [IO.Path]::IsPathRooted($ProjectPath)) { throw 'An explicit absolute ProjectPath is required.' }
$ProjectPath = [IO.Path]::GetFullPath($ProjectPath)
if ($BindingSmokeOnly) { Write-Output "BINDING-SMOKE-PASSED|Run-Gate13RPR2MemoryPolicyPilotBlockV2|$ProjectPath"; exit 0 }

Import-Module (Join-Path $ProjectPath 'Research\Gate13RPR2MemoryPolicyPilotV1.psm1') -Force
Import-Module (Join-Path $ProjectPath 'Research\Gate13RPR2MemoryPolicyPilotV2.psm1') -Force
Import-Module (Join-Path $ProjectPath 'Research\Gate10RLockHygieneV3.psm1') -Force

$BlockPlanPath = [IO.Path]::GetFullPath($BlockPlanPath)
$OutputDirectory = [IO.Path]::GetFullPath($OutputDirectory)
$AllowedRoot = [IO.Path]::GetFullPath($AllowedRoot).TrimEnd('\','/')
$ExecutionReceiptPath = [IO.Path]::GetFullPath($ExecutionReceiptPath)
$UnityPath = [IO.Path]::GetFullPath($UnityPath)
$measuredRoot = [IO.Path]::GetFullPath((Join-Path $ProjectPath 'Research\PilotRuns\Gate13R_PR2_MemoryPolicy\v2\raw')).TrimEnd('\','/')
$verificationBase = [IO.Path]::GetFullPath((Join-Path $ProjectPath 'Research\Verification\Gate13R_PR2_MP1_v2')).TrimEnd('\','/')
if ($ValidationOnly) {
    if (-not (Test-G13RPR2MP1PathWithin -BasePath $verificationBase -CandidatePath $AllowedRoot -AllowBase)) { throw 'Validation output root is outside the MP1 verification base.' }
}
elseif (-not $AllowedRoot.Equals($measuredRoot, [StringComparison]::OrdinalIgnoreCase)) { throw 'Measured pilot root identity mismatch.' }
if (-not (Test-Path -LiteralPath $AllowedRoot -PathType Container)) { throw 'Allowed root is missing.' }
if (-not (Test-G13RPR2MP1PathWithin -BasePath $AllowedRoot -CandidatePath $BlockPlanPath)) { throw 'Block plan is outside the allowed root.' }
if (-not (Test-G13RPR2MP1PathWithin -BasePath $AllowedRoot -CandidatePath $OutputDirectory)) { throw 'Block output is outside the allowed root.' }
if (-not (Test-Path -LiteralPath $BlockPlanPath -PathType Leaf)) { throw 'Block plan is missing.' }
if (-not (Test-Path -LiteralPath $ExecutionReceiptPath -PathType Leaf)) { throw 'Execution receipt is missing.' }
if (-not (Test-Path -LiteralPath $UnityPath -PathType Leaf)) { throw 'Unity executable is missing.' }
if (Test-Path -LiteralPath $OutputDirectory) { throw "Create-new block output already exists: $OutputDirectory" }
if (@(Get-Process -Name Unity -ErrorAction SilentlyContinue).Count -gt 0 -or (Test-Path -LiteralPath (Join-Path $ProjectPath 'Temp\UnityLockfile'))) { throw 'Unity must be quiescent and the project lock absent before a block.' }

$plan = Read-G13RPR2MP1Json $BlockPlanPath
if ([int]$plan.schemaVersion -ne 2 -or [string]$plan.planId -ne 'gate13r-pr2-mp1-block-plan-v1' -or [string]$plan.designId -ne 'gate13r-pr2-mp1-stage-separated-memory-targeted-pilot-v1') { throw 'MP1 block-plan identity mismatch.' }
if ($plan.formalCampaign -ne $false -or $plan.excludedFromFormalAnalysis -ne $true -or [string]$plan.analysisRole -ne 'memory-diagnostic-only') { throw 'MP1 block-plan authorization boundary mismatch.' }
if ([bool]$plan.validationOnly -ne [bool]$ValidationOnly) { throw 'Block plan validation-only identity mismatch.' }
if ($ExpectFailure -and (-not $ValidationOnly -or [int]$plan.verificationInjectedFailurePosition -lt 1)) { throw 'Expected failure is allowed only for an injected validation-only plan.' }
if (-not $ExpectFailure -and [int]$plan.verificationInjectedFailurePosition -ne 0) { throw 'Unexpected injected failure position.' }
if (@($plan.entries).Count -ne 4) { throw 'MP1 requires a complete four-sample Williams block.' }
$receipt = Read-G13RPR2MP1Json $ExecutionReceiptPath
if ($ValidationOnly) {
    if ([string]$receipt.receiptKind -ne 'gate13r-pr2-mp1-validation-only-execution-receipt-v2' -or $receipt.measuredPilotAuthorized -ne $false -or $receipt.formalCampaignAuthorized -ne $false) { throw 'Validation-only receipt identity mismatch.' }
}
else {
    if ([string]$receipt.receiptKind -ne 'gate13r-pr2-mp1-targeted-memory-pilot-execution-receipt-v2' -or $receipt.measuredPilotAuthorized -ne $true -or $receipt.formalCampaignAuthorized -ne $false -or $receipt.formalAnalysisAuthorized -ne $false -or $receipt.gate14RAuthorized -ne $false) { throw 'Measured pilot receipt identity mismatch.' }
}
$receiptSha256 = Get-G13RPR2MP1Sha256 $ExecutionReceiptPath
if ([string]$plan.executionReceiptSha256 -ne $receiptSha256) { throw 'Block plan / execution receipt SHA-256 mismatch.' }
$planSha256 = Get-G13RPR2MP1Sha256 $BlockPlanPath

$telemetryStartDirectory = Join-Path $AllowedRoot 'external-start'
if (-not (Test-Path -LiteralPath $telemetryStartDirectory -PathType Container)) { New-Item -ItemType Directory -Path $telemetryStartDirectory -Force | Out-Null }
$externalStartPath = Join-Path $telemetryStartDirectory (([string]$plan.blockId) + '.json')
if (Test-Path -LiteralPath $externalStartPath) { throw "Create-new external start snapshot exists: $externalStartPath" }
$unityLogSidecar = $OutputDirectory + '.Unity.log'
if (Test-Path -LiteralPath $unityLogSidecar) { throw "Create-new Unity log exists: $unityLogSidecar" }

$started = [DateTime]::UtcNow
$arguments = @(
    '-batchmode','-nographics','-quit',
    '-projectPath',('"'+$ProjectPath+'"'),
    '-executeMethod','DDM.Research.Editor.Gate13RPR2MemoryPolicyPilotBatchCommandV1.Run',
    '-ddmGate13RPR2BlockPlanPath',('"'+$BlockPlanPath+'"'),
    '-ddmGate13RPR2BlockPlanSha256',$planSha256,
    '-ddmGate13RPR2OutputDirectory',('"'+$OutputDirectory+'"'),
    '-ddmGate13RPR2MP1ExternalStartPath',('"'+$externalStartPath+'"'),
    '-logFile',('"'+$unityLogSidecar+'"')
)
$process = Start-Process -FilePath $UnityPath -ArgumentList $arguments -WorkingDirectory (Split-Path -Parent $UnityPath) -WindowStyle Hidden -PassThru
$externalStart = $null
$snapshotDeadline = [DateTime]::UtcNow.AddSeconds(60)
do {
    try { $externalStart = Get-G13RPR2MP1ProcessSnapshot -Process $process -BlockId ([string]$plan.blockId) -IncludeCim }
    catch { if ([DateTime]::UtcNow -ge $snapshotDeadline -or $process.HasExited) { throw }; Start-Sleep -Milliseconds 50 }
} while ($null -eq $externalStart)
Write-G13RPR2MP1V2AtomicJson -Path $externalStartPath -Value $externalStart -Depth 20

$baselineWorking = [long]$externalStart.workingSetBytes
$baselinePrivate = [long]$externalStart.privateMemoryBytes
$maxWorking = $baselineWorking
$maxPrivate = $baselinePrivate
$minAvailable = [long]$externalStart.availablePhysicalMemoryBytes
$monitorSamples = 1
$safetyStopReasons = New-Object Collections.Generic.List[string]
$timedOut = $false
$deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
$nextOsQuery = [DateTime]::UtcNow
while (-not $process.HasExited) {
    $process.Refresh()
    if ($process.HasExited) { break }
    $maxWorking = [Math]::Max($maxWorking, [long]$process.WorkingSet64)
    $maxPrivate = [Math]::Max($maxPrivate, [long]$process.PrivateMemorySize64)
    $monitorSamples++
    if ([long]$process.WorkingSet64 -gt 4294967296L) { $safetyStopReasons.Add('HARD-FAIL-ABSOLUTE-WORKING-SET-4GIB') }
    if ([long]$process.PrivateMemorySize64 -gt 4294967296L) { $safetyStopReasons.Add('HARD-FAIL-ABSOLUTE-PRIVATE-MEMORY-4GIB') }
    if (([long]$process.WorkingSet64 - $baselineWorking) -gt 2147483648L) { $safetyStopReasons.Add('HARD-FAIL-PROCESS-WORKING-SET-GROWTH-2GIB') }
    if (([long]$process.PrivateMemorySize64 - $baselinePrivate) -gt 2147483648L) { $safetyStopReasons.Add('HARD-FAIL-PROCESS-PRIVATE-MEMORY-GROWTH-2GIB') }
    if ([DateTime]::UtcNow -ge $nextOsQuery) {
        $available = [long](Get-CimInstance Win32_OperatingSystem -ErrorAction Stop).FreePhysicalMemory * 1024L
        $minAvailable = [Math]::Min($minAvailable, $available)
        if ($available -lt 8589934592L) { $safetyStopReasons.Add('HARD-FAIL-AVAILABLE-PHYSICAL-BELOW-8GIB') }
        $nextOsQuery = [DateTime]::UtcNow.AddSeconds(2)
    }
    if ($safetyStopReasons.Count -gt 0) { break }
    if ([DateTime]::UtcNow -ge $deadline) { $timedOut = $true; break }
    Start-Sleep -Milliseconds 250
}
if ($timedOut -or $safetyStopReasons.Count -gt 0) {
    & taskkill.exe /PID $process.Id /T /F 2>&1 | Out-Null
    try { Wait-Process -Id $process.Id -Timeout 30 -ErrorAction SilentlyContinue } catch { }
}
$process.Refresh()
$exitCode = if ($timedOut) { 124 } elseif ($process.HasExited) { [int]$process.ExitCode } else { 125 }
$completed = [DateTime]::UtcNow

$lock = $null
$quiescenceException = $null
$lockEvidenceDirectory = $OutputDirectory + '.lock-hygiene'
$lockRole = if ($ExpectFailure) { 'expected-negative' } else { 'positive' }
try {
    $lock = Invoke-Gate10RPostExitQuiescenceV3 -ProjectPath $ProjectPath -OwnedProcessId $process.Id -OwnedProcessStartedAt ([DateTimeOffset]$started) -OwnedProcessCompletedAt ([DateTimeOffset]$completed) -Role $lockRole -EvidenceDirectory $lockEvidenceDirectory -ContextId ([string]$plan.blockId) -QuiescenceSeconds 60 -PollMilliseconds 250 -TimestampToleranceSeconds 2
}
catch { $quiescenceException = $_.Exception.Message }

if (-not (Test-Path -LiteralPath $OutputDirectory -PathType Container)) { New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null }
$unityLogPath = Join-Path $OutputDirectory 'Unity.log'
if (Test-Path -LiteralPath $unityLogSidecar -PathType Leaf) {
    if (Test-Path -LiteralPath $unityLogPath) { throw 'Unity log target unexpectedly exists.' }
    Move-Item -LiteralPath $unityLogSidecar -Destination $unityLogPath
}
$externalTelemetryPath = Join-Path $OutputDirectory 'external-stage-telemetry.json'
$externalTelemetry = [ordered]@{
    schemaVersion = 1
    telemetryKind = 'gate13r-pr2-mp1-external-stage-telemetry-v1'
    designId = 'gate13r-pr2-mp1-stage-separated-memory-targeted-pilot-v1'
    blockId = [string]$plan.blockId
    processId = [int]$process.Id
    processStartTimeUtc = [string]$externalStart.processStartTimeUtc
    stages = @(
        [ordered]@{stageId='external-first-valid-psapi-after-process-create';capturedAtUtc=[string]$externalStart.capturedAtUtc;snapshot=$externalStart},
        [ordered]@{stageId='process-exit';capturedAtUtc=$completed.ToString('o');exitCode=$exitCode;timedOut=$timedOut;safetyStopReasons=$safetyStopReasons.ToArray()},
        [ordered]@{stageId='post-exit-quiescence';capturedAtUtc=[DateTime]::UtcNow.ToString('o');passed=($null -ne $lock -and $lock.passed -eq $true);mode=if($null-ne$lock){[string]$lock.mode}else{$null};exceptionMessage=$quiescenceException}
    )
    monitor = [ordered]@{sampleCount=$monitorSamples;baselineWorkingSetBytes=$baselineWorking;baselinePrivateMemoryBytes=$baselinePrivate;maximumWorkingSetBytes=$maxWorking;maximumPrivateMemoryBytes=$maxPrivate;minimumAvailablePhysicalMemoryBytes=$minAvailable}
    formalCampaign = $false
    excludedFromFormalAnalysis = $true
    completed = $true
}
Write-G13RPR2MP1V2AtomicJson -Path $externalTelemetryPath -Value $externalTelemetry -Depth 40

$blockFailurePath = Join-Path $OutputDirectory 'block-failure.json'
$quiescenceFailurePath = Join-Path $lockEvidenceDirectory (([string]$plan.blockId) + '.quiescence-failure.json')
$resolution = Resolve-G13RPR2MP1FailurePrecedence -BlockFailurePath $blockFailurePath -QuiescenceFailurePath $quiescenceFailurePath -QuiescenceExceptionMessage $quiescenceException -UnityExitCode $exitCode -TimedOut $timedOut -SafetyStopReasons $safetyStopReasons.ToArray()
$resolutionPath = Join-Path $OutputDirectory 'wrapper-failure-resolution.json'
Write-G13RPR2MP1V2AtomicJson -Path $resolutionPath -Value $resolution -Depth 40

$errors = New-Object Collections.Generic.List[string]
$logText = if (Test-Path -LiteralPath $unityLogPath -PathType Leaf) { Read-G13RPR2MP1TextWithRetry -Path $unityLogPath } else { '' }
$compilerMatches = if ($logText.Length -gt 0) { @($logText | Select-String -Pattern 'error CS\d+|Compilation failed|Scripts have compiler errors|executeMethod.+could not be found' -AllMatches -CaseSensitive:$false) } else { @() }
$serialAssigned = $logText.Contains('Serial number assigned to:')
$noValidLicense = $logText.Contains('No valid Unity Editor license found')
$inactiveHeadless = $logText.Contains('License is not active (com.unity.editor.headless)')
if (@($compilerMatches).Count -gt 0) { $errors.Add("compiler-patterns-$(@($compilerMatches).Count)") }
if (-not $serialAssigned -or $noValidLicense -or $inactiveHeadless) { $errors.Add('license-entitlement') }
$manifestPath = Join-Path $OutputDirectory 'block-manifest.json'
$stagePath = Join-Path $OutputDirectory 'block-stage-telemetry.json'
$checkpointPath = Join-Path $OutputDirectory 'block-checkpoint.json'
$manifest = if (Test-Path -LiteralPath $manifestPath -PathType Leaf) { Read-G13RPR2MP1Json $manifestPath } else { $null }
$stage = if (Test-Path -LiteralPath $stagePath -PathType Leaf) { Read-G13RPR2MP1Json $stagePath } else { $null }
$checkpoint = if (Test-Path -LiteralPath $checkpointPath -PathType Leaf) { Read-G13RPR2MP1Json $checkpointPath } else { $null }
if ($ExpectFailure) {
    if (-not $resolution.failed -or $null -eq $resolution.primaryCause -or [string]$resolution.primaryCause.kind -ne 'DURABLE-UNITY-BLOCK-FAILURE') { $errors.Add('expected-durable-primary-failure-missing') }
    if ($resolution.nextBlockAllowed -ne $false -or $resolution.automaticRetryAllowed -ne $false -or $resolution.automaticResumeAllowed -ne $false) { $errors.Add('expected-failure-not-fail-closed') }
}
else {
    if ($resolution.failed) { $errors.Add('failure-precedence-reported-failure') }
    if ($exitCode -ne 0) { $errors.Add("unity-exit-$exitCode") }
    if ($safetyStopReasons.Count -gt 0) { $errors.Add('emergency-safety-stop') }
    if ($null -eq $manifest) { $errors.Add('block-manifest-missing') }
    else {
        if ([int]$manifest.schemaVersion -ne 4 -or [string]$manifest.manifestKind -ne 'gate13r-pr2-mp1-memory-diagnostic-block-manifest-v1') { $errors.Add('manifest-identity') }
        if ($manifest.completed -ne $true -or $manifest.formalCampaign -ne $false -or $manifest.hardMemoryRulesPassed -ne $true) { $errors.Add('manifest-completion-boundary') }
        if ([string]$manifest.executionDesignId -ne 'gate13r-pr2-mp1-stage-separated-memory-targeted-pilot-v1' -or [string]$manifest.blockId -ne [string]$plan.blockId -or [string]$manifest.blockPlanSha256 -ne $planSha256) { $errors.Add('manifest-plan-identity') }
        if ([int]$manifest.expectedSampleCount -ne 4 -or [int]$manifest.completedSampleCount -ne 4 -or @($manifest.samples).Count -ne 4) { $errors.Add('manifest-sample-cardinality') }
        if ($manifest.oneBlockPerUnityProcess -ne $true -or $manifest.oneSamplePerAlgorithmPerProcess -ne $true -or $manifest.allSamplesShareProcessId -ne $true -or $manifest.orderMatchesBlockPlan -ne $true) { $errors.Add('manifest-process-williams') }
        if ([long]$manifest.blockRetainedManagedGrowthBytes -gt 268435456L) { $errors.Add('block-managed-emergency') }
        for ($i=0; $i -lt @($manifest.samples).Count; $i++) {
            $sample=$manifest.samples[$i]; $entry=$plan.entries[$i]
            if ($sample.completed -ne $true -or [int]$sample.position -ne [int]$entry.position -or [string]$sample.algorithmId -ne [string]$entry.algorithmId -or [string]$sample.runId -ne [string]$entry.runId -or [int]$sample.processId -ne [int]$manifest.processId) { $errors.Add("sample-identity-$i") }
            foreach ($property in @('manifestRelativePath','summaryRelativePath','workloadResultRelativePath','memoryGateEvaluationRelativePath')) {
                $relative=[string]$sample.$property; $child=[IO.Path]::GetFullPath((Join-Path $OutputDirectory $relative.Replace('/','\')))
                if (-not (Test-G13RPR2MP1PathWithin -BasePath $OutputDirectory -CandidatePath $child) -or -not (Test-Path -LiteralPath $child -PathType Leaf)) { $errors.Add("sample-file-$property-$i"); continue }
                $hashProperty=$property.Replace('RelativePath','Sha256'); if ((Get-G13RPR2MP1Sha256 $child) -ne [string]$sample.$hashProperty) { $errors.Add("sample-hash-$property-$i") }
            }
        }
    }
    if ($null -eq $stage -or [string]$stage.telemetryKind -ne 'gate13r-pr2-mp1-stage-separated-memory-telemetry-v1' -or $stage.completed -ne $true -or @($stage.records).Count -ne 19) { $errors.Add('stage-telemetry-completeness') }
    else {
        foreach ($required in @('unity-command-entry-project-loaded','before-scenario-load','after-scenario-load-before-first-sample','post-block-pre-exit')) { if (@($stage.records | Where-Object { [string]$_.stageId -eq $required }).Count -ne 1) { $errors.Add("stage-$required") } }
        foreach ($required in @('sample-before','sample-raw-after-workload','sample-after-cleanup')) { if (@($stage.records | Where-Object { [string]$_.stageId -eq $required }).Count -ne 4) { $errors.Add("stage-$required") } }
    }
    if ($null -eq $checkpoint -or [string]$checkpoint.status -ne 'block-completed' -or $checkpoint.formalCampaign -ne $false) { $errors.Add('terminal-checkpoint') }
    if ($null -eq $lock -or $lock.passed -ne $true -or [string]$lock.mode -ne 'natural-lock-absence') { $errors.Add('post-exit-quiescence') }
}

$blockPlanCopy = Join-Path $OutputDirectory 'block-plan.json'
if (-not (Test-Path -LiteralPath $blockPlanCopy)) { Copy-Item -LiteralPath $BlockPlanPath -Destination $blockPlanCopy }
$summary = [ordered]@{
    schemaVersion = 1
    summaryKind = 'gate13r-pr2-mp1-block-wrapper-summary-v2'
    savedAtUtc = [DateTime]::UtcNow.ToString('o')
    blockId = [string]$plan.blockId
    globalProcessOrdinal = [int]$plan.globalProcessOrdinal
    blockPlanSha256 = $planSha256
    executionReceiptSha256 = $receiptSha256
    outputDirectory = $OutputDirectory
    unityProcessId = [int]$process.Id
    unityProcessStartTimeUtc = [string]$externalStart.processStartTimeUtc
    exitCode = $exitCode
    timedOut = $timedOut
    wallSeconds = ($completed-$started).TotalSeconds
    maximumWorkingSetBytes = $maxWorking
    maximumPrivateMemoryBytes = $maxPrivate
    minimumAvailablePhysicalMemoryBytes = $minAvailable
    safetyStopReasons = $safetyStopReasons.ToArray()
    failureResolutionSha256 = Get-G13RPR2MP1Sha256 $resolutionPath
    lockHygieneMode = if($null-ne$lock){[string]$lock.mode}else{$null}
    licenseSerialAssigned = $serialAssigned
    noValidLicenseError = $noValidLicense
    inactiveHeadlessLicenseError = $inactiveHeadless
    validationOnly = [bool]$ValidationOnly
    expectedFailure = [bool]$ExpectFailure
    formalCampaign = $false
    excludedFromFormalAnalysis = $true
    automaticRetryAttempted = $false
    automaticResumeAttempted = $false
    topUpAttempted = $false
    partialMergeAttempted = $false
    errors = $errors.ToArray()
    passed = $errors.Count -eq 0
}
$summaryPath = Join-Path $OutputDirectory 'wrapper-summary.json'
Write-G13RPR2MP1V2AtomicJson -Path $summaryPath -Value $summary -Depth 50
if ($errors.Count -gt 0) { Write-Error ('Gate13R-PR2-MP1 block failed: ' + ($errors -join '; ')); exit 1 }
Write-Host "Gate13R-PR2-MP1 block validation passed: $($plan.blockId)" -ForegroundColor Green
exit 0
