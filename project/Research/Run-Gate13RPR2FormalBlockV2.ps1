[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$ProjectPath,
    [Parameter(Mandatory = $true)][string]$BlockPlanPath,
    [Parameter(Mandatory = $true)][string]$OutputDirectory,
    [Parameter(Mandatory = $true)][string]$AllowedRoot,
    [Parameter(Mandatory = $true)][string]$ExecutionReceiptPath,
    [string]$UnityPath = 'H:\UnityEditor\2022.3.30f1c1\Editor\Unity.exe',
    [switch]$BindingSmokeOnly,
    [int]$TimeoutSeconds = 3600
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if ([string]::IsNullOrWhiteSpace($ProjectPath) -or -not [IO.Path]::IsPathRooted($ProjectPath)) { throw 'An explicit absolute ProjectPath is required.' }
$ProjectPath = [IO.Path]::GetFullPath($ProjectPath)
if ($BindingSmokeOnly) {
    Write-Output "BINDING-SMOKE-PASSED|Run-Gate13RPR2FormalBlockV2|$ProjectPath"
    exit 0
}

Import-Module (Join-Path $ProjectPath 'Research\Gate13RPR2FormalExecutionV2.psm1') -Force
Import-Module (Join-Path $ProjectPath 'Research\Gate10RLockHygieneV3.psm1') -Force

$BlockPlanPath = [IO.Path]::GetFullPath($BlockPlanPath)
$OutputDirectory = [IO.Path]::GetFullPath($OutputDirectory)
$AllowedRoot = [IO.Path]::GetFullPath($AllowedRoot).TrimEnd('\', '/')
$ExecutionReceiptPath = [IO.Path]::GetFullPath($ExecutionReceiptPath)
$UnityPath = [IO.Path]::GetFullPath($UnityPath)
$expectedRoot = [IO.Path]::GetFullPath((Join-Path $ProjectPath 'Research\FormalRuns\Gate13R_RQAligned_S48H48\v1')).TrimEnd('\', '/')
if (-not $AllowedRoot.Equals($expectedRoot, [StringComparison]::OrdinalIgnoreCase)) { throw 'Formal root identity mismatch.' }
if (-not (Test-Path -LiteralPath $AllowedRoot -PathType Container)) { throw 'Committed formal root is missing.' }
if (-not (Test-G13RPR2PathWithin -BasePath $AllowedRoot -CandidatePath $BlockPlanPath)) { throw 'Block plan is outside the formal root.' }
if (-not (Test-G13RPR2PathWithin -BasePath $AllowedRoot -CandidatePath $OutputDirectory)) { throw 'Block output is outside the formal root.' }
if (-not (Test-Path -LiteralPath $BlockPlanPath -PathType Leaf)) { throw 'Block plan is missing.' }
if (-not (Test-Path -LiteralPath $ExecutionReceiptPath -PathType Leaf)) { throw 'Formal execution receipt is missing.' }
if (-not (Test-Path -LiteralPath $UnityPath -PathType Leaf)) { throw 'Unity executable is missing.' }
if (Test-Path -LiteralPath $OutputDirectory) {
    if (-not (Test-Path -LiteralPath $OutputDirectory -PathType Container) -or @(Get-ChildItem -LiteralPath $OutputDirectory -Force).Count -gt 0) { throw "Output is not fresh: $OutputDirectory" }
}

$unityLogPath = $OutputDirectory + '.Unity.log'
$summaryPath = $OutputDirectory + '.summary.json'
foreach ($sidecar in @($unityLogPath, $summaryPath)) { if (Test-Path -LiteralPath $sidecar) { throw "Create-new sidecar exists: $sidecar" } }
if (@(Get-Process -Name Unity -ErrorAction SilentlyContinue).Count -gt 0 -or (Test-Path -LiteralPath (Join-Path $ProjectPath 'Temp\UnityLockfile'))) {
    throw 'Unity must be quiescent and the project lock absent before a formal block.'
}

$plan = Read-G13RPR2Json $BlockPlanPath
if ([int]$plan.schemaVersion -ne 2 -or [string]$plan.planId -ne 'gate13r-pr2-formal-block-plan-v1' -or [string]$plan.designId -ne 'gate10r-one-fresh-unity-process-per-williams-block-5pct-v1') { throw 'Formal block-plan identity mismatch.' }
if ($plan.formalCampaign -ne $true -or [string]$plan.analysisRole -ne 'formal-timing' -or [int]$plan.verificationInjectedFailurePosition -ne 0) { throw 'Formal block-plan authorization boundary mismatch.' }
$receiptSha256 = Get-G13RPR2Sha256 $ExecutionReceiptPath
if ([string]$plan.executionReceiptSha256 -ne $receiptSha256) { throw 'Block plan / execution receipt SHA-256 mismatch.' }
$planSha256 = Get-G13RPR2Sha256 $BlockPlanPath
$started = Get-Date
$arguments = @(
    '-batchmode', '-nographics', '-quit',
    '-projectPath', ('"' + $ProjectPath + '"'),
    '-executeMethod', 'DDM.Research.Editor.Gate13RPR2FormalBatchCommandV2.Run',
    '-ddmGate13RPR2BlockPlanPath', ('"' + $BlockPlanPath + '"'),
    '-ddmGate13RPR2BlockPlanSha256', $planSha256,
    '-ddmGate13RPR2OutputDirectory', ('"' + $OutputDirectory + '"'),
    '-logFile', ('"' + $unityLogPath + '"')
)
$process = Start-Process -FilePath $UnityPath -ArgumentList $arguments -WorkingDirectory (Split-Path -Parent $UnityPath) -WindowStyle Hidden -PassThru
$timedOut = $false
$deadline = (Get-Date).AddSeconds($TimeoutSeconds)
while (-not $process.HasExited) {
    if ((Get-Date) -ge $deadline) { $timedOut = $true; break }
    Start-Sleep -Milliseconds 500
    $process.Refresh()
}
if ($timedOut) {
    & taskkill.exe /PID $process.Id /T /F 2>&1 | Out-Null
    try { Wait-Process -Id $process.Id -Timeout 30 -ErrorAction SilentlyContinue } catch { }
}
$process.Refresh()
$exitCode = if ($timedOut) { 124 } else { [int]$process.ExitCode }
$completed = Get-Date
$lock = Invoke-Gate10RPostExitQuiescenceV3 -ProjectPath $ProjectPath -OwnedProcessId $process.Id -OwnedProcessStartedAt ([DateTimeOffset]$started) -OwnedProcessCompletedAt ([DateTimeOffset]$completed) -Role 'positive' -EvidenceDirectory ($OutputDirectory + '.lock-hygiene') -ContextId ([string]$plan.blockId) -QuiescenceSeconds 60 -PollMilliseconds 250 -TimestampToleranceSeconds 2

$logText = if (Test-Path -LiteralPath $unityLogPath) { [IO.File]::ReadAllText($unityLogPath, [Text.Encoding]::UTF8) } else { '' }
$compilerMatches = if ($logText.Length -gt 0) { @($logText | Select-String -Pattern 'error CS\d+|Compilation failed|Scripts have compiler errors|executeMethod.+could not be found' -AllMatches -CaseSensitive:$false) } else { @() }
$serialAssigned = $logText.Contains('Serial number assigned to:')
$noValidLicense = $logText.Contains('No valid Unity Editor license found')
$inactiveHeadless = $logText.Contains('License is not active (com.unity.editor.headless)')
$accessTokenWarning = $logText.Contains('Access token is unavailable; failed to update')
$manifestPath = Join-Path $OutputDirectory 'block-manifest.json'
$checkpointPath = Join-Path $OutputDirectory 'block-checkpoint.json'
$failurePath = Join-Path $OutputDirectory 'block-failure.json'
$manifest = if (Test-Path -LiteralPath $manifestPath) { Read-G13RPR2Json $manifestPath } else { $null }
$checkpoint = if (Test-Path -LiteralPath $checkpointPath) { Read-G13RPR2Json $checkpointPath } else { $null }
$errors = New-Object Collections.Generic.List[string]
if ($timedOut) { $errors.Add("hard-timeout-$TimeoutSeconds") }
if ($exitCode -ne 0) { $errors.Add("unity-exit-$exitCode") }
if ($compilerMatches.Count -gt 0) { $errors.Add("compiler-patterns-$($compilerMatches.Count)") }
if (-not $serialAssigned) { $errors.Add('license-serial-assignment-missing') }
if ($noValidLicense) { $errors.Add('unity-no-valid-license') }
if ($inactiveHeadless) { $errors.Add('unity-inactive-headless-entitlement') }
if ($null -eq $manifest) { $errors.Add('block-manifest-missing') }
else {
    $expectedCount = @($plan.entries).Count
    if ([int]$manifest.schemaVersion -ne 4 -or [string]$manifest.manifestKind -ne 'gate13r-pr2-rq-aligned-s48-h48-formal-block-manifest-v1') { $errors.Add('manifest-identity') }
    if ($manifest.completed -ne $true -or $manifest.formalCampaign -ne $true -or $manifest.hardMemoryRulesPassed -ne $true) { $errors.Add('manifest-completion-formal-memory') }
    if ([string]$manifest.executionDesignId -ne 'gate10r-one-fresh-unity-process-per-williams-block-5pct-v1' -or [string]$manifest.blockId -ne [string]$plan.blockId -or [string]$manifest.blockPlanSha256 -ne $planSha256) { $errors.Add('manifest-block-plan-identity') }
    if ([int]$manifest.expectedSampleCount -ne $expectedCount -or [int]$manifest.completedSampleCount -ne $expectedCount -or @($manifest.samples).Count -ne $expectedCount) { $errors.Add('manifest-sample-cardinality') }
    if ($manifest.oneBlockPerUnityProcess -ne $true -or $manifest.oneSamplePerAlgorithmPerProcess -ne $true -or $manifest.allSamplesShareProcessId -ne $true -or $manifest.orderMatchesBlockPlan -ne $true) { $errors.Add('manifest-process-williams') }
    if ([string]$manifest.memoryGatePolicyId -ne 'gate13r-pr1b-v2-sample-alert-128mib-emergency-256mib-block-256mib-v1' -or [string]$manifest.blockManagedLimitFormulaId -ne 'fixed-two-sample-independent-block-256mib-v1') { $errors.Add('manifest-memory-policy') }
    if ([long]$manifest.sampleManagedAlertThresholdBytes -ne 134217728L -or [long]$manifest.sampleManagedEmergencyStopBytes -ne 268435456L -or [long]$manifest.maximumSampleRetainedManagedGrowthBytes -ne 268435456L -or [long]$manifest.maximumManagedGrowthBytes -ne 268435456L -or [long]$manifest.maximumNativeGrowthBytes -ne 536870912L) { $errors.Add('manifest-memory-threshold') }
    if ([long]$manifest.blockRetainedManagedGrowthBytes -gt 268435456L -or [long]$manifest.blockWorkingSetGrowthBytes -gt 536870912L -or [long]$manifest.blockPrivateMemoryGrowthBytes -gt 536870912L) { $errors.Add('manifest-memory-exceeded') }
    if ([int]$manifest.processId -ne [int]$process.Id -or [string]::IsNullOrWhiteSpace([string]$manifest.processStartTimeUtc)) { $errors.Add('manifest-process-identity') }
    for ($index = 0; $index -lt @($manifest.samples).Count; $index++) {
        $sample = $manifest.samples[$index]
        $entry = $plan.entries[$index]
        if ($sample.completed -ne $true -or $sample.formalCampaign -ne $true -or [int]$sample.position -ne [int]$entry.position -or [string]$sample.algorithmId -ne [string]$entry.algorithmId -or [string]$sample.runId -ne [string]$entry.runId -or [int]$sample.processId -ne [int]$manifest.processId) { $errors.Add("sample-identity-$index") }
        foreach ($property in @('manifestRelativePath','summaryRelativePath','workloadResultRelativePath','memoryGateEvaluationRelativePath')) {
            $relative = [string]$sample.$property
            $childPath = [IO.Path]::GetFullPath((Join-Path $OutputDirectory $relative.Replace('/', '\')))
            if (-not (Test-G13RPR2PathWithin -BasePath $OutputDirectory -CandidatePath $childPath) -or -not (Test-Path -LiteralPath $childPath -PathType Leaf)) { $errors.Add("sample-file-$property-$index"); continue }
            $hashProperty = $property.Replace('RelativePath', 'Sha256')
            if ((Get-G13RPR2Sha256 $childPath) -ne [string]$sample.$hashProperty) { $errors.Add("sample-hash-$property-$index") }
        }
        $evaluationPath = [IO.Path]::GetFullPath((Join-Path $OutputDirectory ([string]$sample.memoryGateEvaluationRelativePath).Replace('/', '\')))
        if (Test-Path -LiteralPath $evaluationPath) {
            $evaluation = Read-G13RPR2Json $evaluationPath
            if ($evaluation.completed -ne $true -or $evaluation.formalCampaign -ne $true -or [string]$evaluation.memoryGatePolicyId -ne 'gate13r-pr1b-v2-sample-alert-128mib-emergency-256mib-block-256mib-v1' -or [string]$evaluation.verdict -eq 'HARD-FAIL') { $errors.Add("sample-memory-evaluation-$index") }
        }
        $childManifestPath = [IO.Path]::GetFullPath((Join-Path $OutputDirectory ([string]$sample.manifestRelativePath).Replace('/', '\')))
        if (Test-Path -LiteralPath $childManifestPath) {
            $child = Read-G13RPR2Json $childManifestPath
            if ([int]$child.schemaVersion -ne 6 -or $child.completed -ne $true -or $child.formalCampaign -ne $true -or [string]$child.executionReceiptSha256 -ne $receiptSha256 -or $child.forcedGcBeforeCompleted -ne $true -or $child.forcedGcAfterCompleted -ne $true -or $child.sampleStateCreatedFresh -ne $true -or $child.heavySampleReferencesReturned -ne $false -or $child.plannerResetCompleted -ne $true -or $child.loggerDisposed -ne $true -or $child.retainedManagedGrowthWithinLimit -ne $true) { $errors.Add("sample-manifest-contract-$index") }
        }
    }
}
if ($null -eq $checkpoint -or [string]$checkpoint.status -ne 'block-completed' -or $checkpoint.formalCampaign -ne $true) { $errors.Add('terminal-block-checkpoint') }
if (Test-Path -LiteralPath $failurePath) { $errors.Add('unexpected-block-failure') }
if ($null -eq $lock -or $lock.passed -ne $true -or [string]$lock.mode -ne 'natural-lock-absence') { $errors.Add('post-exit-lock-hygiene') }

$summary = [ordered]@{
    schemaVersion = 1
    summaryKind = 'gate13r-pr2-rq-aligned-s48-h48-formal-block-wrapper-summary-v2'
    savedAtUtc = [DateTime]::UtcNow.ToString('o')
    blockId = [string]$plan.blockId
    globalProcessOrdinal = [int]$plan.globalProcessOrdinal
    blockPlanSha256 = $planSha256
    executionReceiptSha256 = $receiptSha256
    outputDirectory = $OutputDirectory
    unityProcessId = [int]$process.Id
    unityProcessStartTimeUtc = if ($null -ne $manifest) { [string]$manifest.processStartTimeUtc } else { $null }
    exitCode = $exitCode
    timedOut = $timedOut
    wallSeconds = ($completed - $started).TotalSeconds
    sampleCount = if ($null -ne $manifest) { [int]$manifest.completedSampleCount } else { 0 }
    blockManifestSha256 = if (Test-Path -LiteralPath $manifestPath) { Get-G13RPR2Sha256 $manifestPath } else { $null }
    blockFailureSha256 = if (Test-Path -LiteralPath $failurePath) { Get-G13RPR2Sha256 $failurePath } else { $null }
    lockHygieneMode = if ($null -ne $lock) { [string]$lock.mode } else { $null }
    licenseSerialAssigned = $serialAssigned
    noValidLicenseError = $noValidLicense
    inactiveHeadlessLicenseError = $inactiveHeadless
    accessTokenWarningObserved = $accessTokenWarning
    formalCampaign = $true
    automaticRetryAttempted = $false
    automaticResumeAttempted = $false
    errors = $errors.ToArray()
    passed = $errors.Count -eq 0
}
Write-G13RPR2AtomicJson -Path $summaryPath -Value $summary -Depth 40
if ($errors.Count -gt 0) { Write-Error ('Gate13R-PR2 formal block failed: ' + ($errors -join '; ')); exit 1 }
Write-Host "Gate13R-PR2 formal block passed: $($plan.blockId)" -ForegroundColor Green
exit 0
