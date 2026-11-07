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
if ([string]::IsNullOrWhiteSpace($ProjectPath) -or -not [IO.Path]::IsPathRooted($ProjectPath)) { throw 'Gate13R formal block wrapper requires an explicit absolute ProjectPath.' }
$ProjectPath = [IO.Path]::GetFullPath($ProjectPath)
if ($BindingSmokeOnly) { Write-Output "BINDING-SMOKE-PASSED|Run-Gate13RFormalBlockV1|$ProjectPath"; exit 0 }

$BlockPlanPath = [IO.Path]::GetFullPath($BlockPlanPath)
$OutputDirectory = [IO.Path]::GetFullPath($OutputDirectory)
$AllowedRoot = [IO.Path]::GetFullPath($AllowedRoot).TrimEnd('\', '/')
$ExecutionReceiptPath = [IO.Path]::GetFullPath($ExecutionReceiptPath)
$UnityPath = [IO.Path]::GetFullPath($UnityPath)
$reservedRoot = [IO.Path]::GetFullPath((Join-Path $ProjectPath 'Research\FormalRuns\Gate13R_ProcessReuse_5pct\v1')).TrimEnd('\', '/')
Import-Module (Join-Path $ProjectPath 'Research\Gate13RFormalPreparationV1.psm1') -Force
Import-Module (Join-Path $ProjectPath 'Research\Gate10RLockHygieneV3.psm1') -Force

if (-not $AllowedRoot.Equals($reservedRoot, [StringComparison]::OrdinalIgnoreCase)) { throw 'AllowedRoot is not the exact reserved Gate13R formal root.' }
if (-not (Test-Path -LiteralPath $AllowedRoot -PathType Container)) { throw 'Reserved formal root has not been created by the authorized orchestrator.' }
if (-not (Test-G13RPathWithin -BasePath $AllowedRoot -CandidatePath $OutputDirectory)) { throw 'Block output escapes the reserved formal root.' }
if (-not (Test-G13RPathWithin -BasePath $AllowedRoot -CandidatePath $BlockPlanPath)) { throw 'Block plan escapes the reserved formal root.' }
if (-not (Test-Path -LiteralPath $BlockPlanPath -PathType Leaf)) { throw 'Formal block plan is missing.' }
if (-not (Test-Path -LiteralPath $ExecutionReceiptPath -PathType Leaf)) { throw 'Formal execution receipt is missing.' }
if (-not (Test-Path -LiteralPath $UnityPath -PathType Leaf)) { throw 'Unity executable is missing.' }
if (Test-Path -LiteralPath $OutputDirectory) { throw 'Formal block output must be create-new.' }
if (@(Get-Process -Name Unity -ErrorAction SilentlyContinue).Count -gt 0 -or (Test-Path -LiteralPath (Join-Path $ProjectPath 'Temp\UnityLockfile'))) { throw 'Unity must be closed and the project lock absent before a formal block.' }

$plan = Read-G13RJson $BlockPlanPath
if ([int]$plan.schemaVersion -ne 2 -or [string]$plan.designId -ne 'gate10r-one-fresh-unity-process-per-williams-block-5pct-v1' -or $plan.formalCampaign -ne $true -or [string]$plan.analysisRole -ne 'formal-timing') { throw 'Unauthorized Gate13R formal block-plan identity.' }
if ([int]$plan.verificationInjectedFailurePosition -ne 0) { throw 'Formal block plan cannot inject a verification failure.' }
$configFull = Assert-G13RBoundFile -ProjectPath $ProjectPath -RelativePath ([string]$plan.formalConfigRelativePath) -ExpectedSha256 ([string]$plan.formalConfigSha256) -Role 'formal config'
$specFull = Assert-G13RBoundFile -ProjectPath $ProjectPath -RelativePath ([string]$plan.specificationRelativePath) -ExpectedSha256 ([string]$plan.specificationSha256) -Role 'specification'
$testFull = Assert-G13RBoundFile -ProjectPath $ProjectPath -RelativePath ([string]$plan.testDesignRelativePath) -ExpectedSha256 ([string]$plan.testDesignSha256) -Role 'test design'
$amendmentFull = Assert-G13RBoundFile -ProjectPath $ProjectPath -RelativePath ([string]$plan.amendmentRelativePath) -ExpectedSha256 ([string]$plan.amendmentSha256) -Role 'amendment'
$commandFull = Assert-G13RBoundFile -ProjectPath $ProjectPath -RelativePath ([string]$plan.commandRelativePath) -ExpectedSha256 ([string]$plan.commandSha256) -Role 'formal Unity command'
$provenanceFull = Assert-G13RBoundFile -ProjectPath $ProjectPath -RelativePath ([string]$plan.provenanceRelativePath) -ExpectedSha256 ([string]$plan.provenanceSha256) -Role 'provenance'
$receiptRelative = Get-G13RProjectRelativePath -ProjectPath $ProjectPath -Path $ExecutionReceiptPath
if ($receiptRelative -ne [string]$plan.executionReceiptRelativePath -or (Get-G13RLowerSha256 $ExecutionReceiptPath) -ne [string]$plan.executionReceiptSha256) { throw 'Execution receipt path/hash differs from the block plan.' }

$config = Read-G13RJson $configFull
$receipt = Read-G13RJson $ExecutionReceiptPath
$receiptCheck = Test-G13RFormalExecutionReceipt -Receipt $receipt -ExpectedFormalRoot $reservedRoot -ExpectedConfigSha256 ([string]$plan.formalConfigSha256) -ExpectedAmendmentSha256 ([string]$plan.amendmentSha256) -ExpectedProvenanceSha256 ([string]$plan.provenanceSha256) -ExpectedScheduleManifestSha256 ([string]$config.schedule.manifestSha256) -ExpectedOrchestratorSha256 ([string]$config.implementation.orchestratorSha256) -ExpectedUnityCommandSha256 ([string]$plan.commandSha256)
if ($receiptCheck.passed -ne $true) { throw ('Formal execution receipt rejected: ' + (@($receiptCheck.errors) -join ', ')) }

$planSha256 = Get-G13RLowerSha256 $BlockPlanPath
$unityLogPath = $OutputDirectory + '.Unity.log'
$summaryPath = $OutputDirectory + '.wrapper-summary.json'
$started = Get-Date
$arguments = @(
    '-batchmode', '-nographics', '-quit', '-projectPath', ('"' + $ProjectPath + '"'),
    '-executeMethod', 'DDM.Research.Editor.Gate13RProcessReuseFormalBatchCommandV1.Run',
    '-ddmGate13RBlockPlanPath', ('"' + $BlockPlanPath + '"'),
    '-ddmGate13RBlockPlanSha256', $planSha256,
    '-ddmGate13ROutputDirectory', ('"' + $OutputDirectory + '"'),
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
$lock = Invoke-Gate10RPostExitQuiescenceV3 -ProjectPath $ProjectPath -OwnedProcessId $process.Id -OwnedProcessStartedAt ([DateTimeOffset]$started) -OwnedProcessCompletedAt ([DateTimeOffset]$completed) -Role 'formal' -EvidenceDirectory ($OutputDirectory + '.lock-hygiene') -ContextId ([string]$plan.blockId) -QuiescenceSeconds 60 -PollMilliseconds 250 -TimestampToleranceSeconds 2
$compilerMatches = @()
if (Test-Path -LiteralPath $unityLogPath) { $compilerMatches = @(Select-String -LiteralPath $unityLogPath -Pattern 'error CS\d+|Compilation failed|Scripts have compiler errors|executeMethod.+could not be found' -CaseSensitive:$false) }
$manifestPath = Join-Path $OutputDirectory 'block-manifest.json'
$checkpointPath = Join-Path $OutputDirectory 'block-checkpoint.json'
$failurePath = Join-Path $OutputDirectory 'block-failure.json'
$manifest = if (Test-Path -LiteralPath $manifestPath) { Read-G13RJson $manifestPath } else { $null }
$checkpoint = if (Test-Path -LiteralPath $checkpointPath) { Read-G13RJson $checkpointPath } else { $null }
$errors = New-Object Collections.Generic.List[string]
if ($timedOut) { $errors.Add("Hard timeout after $TimeoutSeconds seconds.") }
if ($exitCode -ne 0) { $errors.Add("Unity exit code $exitCode.") }
if ($compilerMatches.Count -gt 0) { $errors.Add("Compiler/error pattern count: $($compilerMatches.Count).") }
if ($null -eq $manifest) { $errors.Add('Formal block manifest missing.') }
else {
    $expectedCount = @($plan.entries).Count
    $expectedManagedLimit = 134217728L * [long]$expectedCount
    if ([string]$manifest.manifestKind -ne 'gate13r-process-reuse-5pct-formal-block-manifest-v1' -or $manifest.formalCampaign -ne $true -or $manifest.completed -ne $true -or $manifest.hardMemoryRulesPassed -ne $true) { $errors.Add('Formal manifest identity/completion/memory verdict invalid.') }
    if ([string]$manifest.blockId -ne [string]$plan.blockId -or [string]$manifest.blockPlanSha256 -ne $planSha256 -or [int]$manifest.completedSampleCount -ne $expectedCount) { $errors.Add('Formal block identity/cardinality mismatch.') }
    if ($manifest.oneBlockPerUnityProcess -ne $true -or $manifest.oneSamplePerAlgorithmPerProcess -ne $true -or $manifest.allSamplesShareProcessId -ne $true -or $manifest.orderMatchesBlockPlan -ne $true) { $errors.Add('Formal process/Williams assertions failed.') }
    if ([long]$manifest.maximumSampleRetainedManagedGrowthBytes -ne 134217728 -or [long]$manifest.maximumManagedGrowthBytes -ne $expectedManagedLimit -or [long]$manifest.blockRetainedManagedGrowthBytes -gt $expectedManagedLimit -or [long]$manifest.blockWorkingSetGrowthBytes -gt 536870912 -or [long]$manifest.blockPrivateMemoryGrowthBytes -gt 536870912) { $errors.Add('Formal memory-gate contract failed.') }
}
if ($null -eq $checkpoint -or [string]$checkpoint.status -ne 'block-completed' -or $checkpoint.formalCampaign -ne $true) { $errors.Add('Formal terminal block checkpoint missing or invalid.') }
if (Test-Path -LiteralPath $failurePath) { $errors.Add('Unexpected formal block failure record exists.') }
if ($null -eq $lock -or $lock.passed -ne $true -or [string]$lock.mode -ne 'natural-lock-absence') { $errors.Add('Formal post-exit lock hygiene failed.') }

$summary = [ordered]@{
    schemaVersion = 1
    summaryKind = 'gate13r-formal-block-wrapper-summary-v1'
    savedAtUtc = [DateTime]::UtcNow.ToString('o')
    blockId = [string]$plan.blockId
    blockPlanSha256 = $planSha256
    outputDirectory = $OutputDirectory
    unityProcessId = [int]$process.Id
    exitCode = $exitCode
    timedOut = $timedOut
    wallSeconds = ($completed - $started).TotalSeconds
    sampleCount = if ($null -ne $manifest) { [int]$manifest.completedSampleCount } else { 0 }
    blockManifestSha256 = if (Test-Path -LiteralPath $manifestPath) { Get-G13RLowerSha256 $manifestPath } else { $null }
    blockFailureSha256 = if (Test-Path -LiteralPath $failurePath) { Get-G13RLowerSha256 $failurePath } else { $null }
    lockHygieneMode = if ($null -ne $lock) { [string]$lock.mode } else { $null }
    formalCampaign = $true
    automaticRetryAttempted = $false
    automaticResumeAttempted = $false
    errors = $errors.ToArray()
    passed = $errors.Count -eq 0
}
Write-G13RAtomicUtf8NoBomJson -Path $summaryPath -Value $summary -Depth 30
if ($errors.Count -gt 0) { Write-Error ('Gate13R formal block failed: ' + ($errors -join '; ')); exit 1 }
Write-Host "Gate13R formal block passed: $($plan.blockId)" -ForegroundColor Green
exit 0
