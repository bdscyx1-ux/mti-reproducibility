[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$BlockPlanPath,
    [Parameter(Mandatory = $true)][string]$OutputDirectory,
    [string]$UnityPath = 'H:\UnityEditor\2022.3.30f1c1\Editor\Unity.exe',
    [Parameter(Mandatory = $true)][string]$ProjectPath,
    [switch]$BindingSmokeOnly,
    [switch]$VerificationOnly,
    [switch]$ExpectFailure,
    [int]$ExpectedCompletedSamplesBeforeFailure = 1
)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($ProjectPath) -or -not [System.IO.Path]::IsPathRooted($ProjectPath)) { throw 'Attempt 3 requires an explicit absolute ProjectPath.' }
$ProjectPath = [System.IO.Path]::GetFullPath($ProjectPath)
if ($BindingSmokeOnly) { Write-Output ('BINDING-SMOKE-PASSED|Run-Gate10RProcessReuseBlockV3|' + $ProjectPath); exit 0 }
$BlockPlanPath = if ([System.IO.Path]::IsPathRooted($BlockPlanPath)) { [System.IO.Path]::GetFullPath($BlockPlanPath) } else { [System.IO.Path]::GetFullPath((Join-Path $ProjectPath $BlockPlanPath)) }
$OutputDirectory = if ([System.IO.Path]::IsPathRooted($OutputDirectory)) { [System.IO.Path]::GetFullPath($OutputDirectory) } else { [System.IO.Path]::GetFullPath((Join-Path $ProjectPath $OutputDirectory)) }
$UnityPath = [System.IO.Path]::GetFullPath($UnityPath)
$modulePath = Join-Path $PSScriptRoot 'Gate10RProcessReusePreparation.psm1'
$lockModulePath = Join-Path $PSScriptRoot 'Gate10RLockHygieneV3.psm1'
Import-Module $modulePath -Force
Import-Module $lockModulePath -Force

if (-not $VerificationOnly) { throw 'Attempt 3 block runner is authorized for Gate 10R verification only.' }
if (-not (Test-Path -LiteralPath $BlockPlanPath -PathType Leaf)) { throw "Gate10R block plan not found: $BlockPlanPath" }
if (-not (Test-Path -LiteralPath $UnityPath -PathType Leaf)) { throw "Unity executable not found: $UnityPath" }
if (-not (Test-Path -LiteralPath (Join-Path $ProjectPath 'Assets') -PathType Container)) { throw "Unity project not found: $ProjectPath" }
$reservedFormalRoot = [System.IO.Path]::GetFullPath((Join-Path $ProjectPath 'Research\FormalRuns\Gate13R_ProcessReuse_5pct\v1'))
if (Test-Path -LiteralPath $reservedFormalRoot) { throw "Reserved process-reuse formal root must not exist: $reservedFormalRoot" }
$verificationRoot = [System.IO.Path]::GetFullPath((Join-Path $ProjectPath 'Research\Verification\Gate10R_ProcessReuse_5pct\v3\Fixtures'))
$verificationPrefix = $verificationRoot.TrimEnd('\') + '\'
if (-not $OutputDirectory.StartsWith($verificationPrefix, [System.StringComparison]::OrdinalIgnoreCase)) { throw 'Gate 10R attempt-3 verification output must be inside the v3 fixture root.' }
if (Test-Path -LiteralPath $OutputDirectory) {
    if (-not (Test-Path -LiteralPath $OutputDirectory -PathType Container)) { throw "Output path is not a directory: $OutputDirectory" }
    if (@(Get-ChildItem -LiteralPath $OutputDirectory -Force).Count -gt 0) { throw "Output directory is not empty: $OutputDirectory" }
}
$unityLogPath = $OutputDirectory + '.Unity.log'
$summaryPath = $OutputDirectory + '.summary.json'
foreach ($path in @($unityLogPath, $summaryPath)) { if (Test-Path -LiteralPath $path) { throw "Create-new policy found an existing output: $path" } }
$unityProcesses = @(Get-Process -Name Unity -ErrorAction SilentlyContinue)
$lockPath = Join-Path $ProjectPath 'Temp\UnityLockfile'
if ($unityProcesses.Count -gt 0 -or (Test-Path -LiteralPath $lockPath)) { throw 'Close Unity and require the project lock to be absent before starting an attempt-3 block.' }

$plan = Read-Gate10RJson -Path $BlockPlanPath
if ($plan.formalCampaign -ne $false -or [string]$plan.designId -ne 'gate10r-one-fresh-unity-process-per-williams-block-5pct-v1' -or [int]$plan.schemaVersion -ne 2) { throw 'Block plan is not an authorized non-formal Gate10R plan.' }
if ($ExpectFailure -and [string]$plan.analysisRole -ne 'excluded-negative-fail-closed-verification') { throw 'Expected-failure cleanup is limited to the frozen negative-fixture analysis role.' }
if (-not $ExpectFailure -and [string]$plan.analysisRole -eq 'excluded-negative-fail-closed-verification') { throw 'Negative-fixture plan requires ExpectFailure.' }
$planSha256 = Get-Gate10RLowerSha256 -Path $BlockPlanPath
$startedAt = Get-Date
$arguments = @(
    '-batchmode',
    '-nographics',
    '-quit',
    '-projectPath', ('"' + $ProjectPath + '"'),
    '-executeMethod', 'DDM.Research.Editor.Gate10RProcessReuseBatchCommand.Run',
    '-ddmGate10RBlockPlanPath', ('"' + $BlockPlanPath + '"'),
    '-ddmGate10RBlockPlanSha256', $planSha256,
    '-ddmGate10ROutputDirectory', ('"' + $OutputDirectory + '"'),
    '-logFile', ('"' + $unityLogPath + '"')
)
$process = Start-Process -FilePath $UnityPath -ArgumentList $arguments -WorkingDirectory (Split-Path -Parent $UnityPath) -WindowStyle Hidden -PassThru
Wait-Process -Id $process.Id
$process.Refresh()
$unityExitCode = [int]$process.ExitCode
$completedAt = Get-Date
$lockEvidenceDirectory = $OutputDirectory + '.lock-hygiene'
$lockRole = if ($ExpectFailure) { 'expected-negative' } else { 'positive' }
$lockResult = Invoke-Gate10RPostExitQuiescenceV3 -ProjectPath $ProjectPath -OwnedProcessId $process.Id -OwnedProcessStartedAt ([DateTimeOffset]$startedAt) -OwnedProcessCompletedAt ([DateTimeOffset]$completedAt) -Role $lockRole -EvidenceDirectory $lockEvidenceDirectory -ContextId ([string]$plan.blockId) -QuiescenceSeconds 60 -PollMilliseconds 250 -TimestampToleranceSeconds 2
$compilerMatches = if (Test-Path -LiteralPath $unityLogPath) { @(Select-String -LiteralPath $unityLogPath -Pattern 'error CS\d+|Compilation failed|Scripts have compiler errors' -CaseSensitive:$false) } else { @() }
$blockManifestPath = Join-Path $OutputDirectory 'block-manifest.json'
$blockCheckpointPath = Join-Path $OutputDirectory 'block-checkpoint.json'
$blockFailurePath = Join-Path $OutputDirectory 'block-failure.json'
$manifest = if (Test-Path -LiteralPath $blockManifestPath -PathType Leaf) { Read-Gate10RJson -Path $blockManifestPath } else { $null }
$checkpoint = if (Test-Path -LiteralPath $blockCheckpointPath -PathType Leaf) { Read-Gate10RJson -Path $blockCheckpointPath } else { $null }
$errors = New-Object System.Collections.Generic.List[string]

if ($ExpectFailure) {
    if ($unityExitCode -eq 0) { $errors.Add('Negative fixture unexpectedly exited zero.') }
    if ($compilerMatches.Count -gt 0) { $errors.Add("Unity compiler errors: $($compilerMatches.Count).") }
    if ($null -ne $manifest) { $errors.Add('Negative fixture unexpectedly wrote a completed block manifest.') }
    if (-not (Test-Path -LiteralPath $blockFailurePath -PathType Leaf)) { $errors.Add('Negative fixture block-failure.json is missing.') }
    if ($null -eq $checkpoint -or [string]$checkpoint.status -ne 'failed-no-auto-retry') { $errors.Add('Negative fixture terminal checkpoint is missing or has the wrong status.') }
    else {
        if ([int]$checkpoint.completedSampleCount -ne $ExpectedCompletedSamplesBeforeFailure) { $errors.Add('Negative fixture completed-sample count mismatch.') }
        if ($checkpoint.automaticRetryAuthorized -ne $false -or $checkpoint.automaticResumeAuthorized -ne $false) { $errors.Add('Negative fixture unexpectedly authorizes retry/resume.') }
    }
    for ($index = $ExpectedCompletedSamplesBeforeFailure + 1; $index -lt @($plan.entries).Count; $index++) {
        $later = Join-Path $OutputDirectory ([string]$plan.entries[$index].directory).Replace('/', '\')
        if (Test-Path -LiteralPath $later) { $errors.Add("A later position executed after the intended failure: $later") }
    }
} else {
    if ($unityExitCode -ne 0) { $errors.Add("Unity exited with code $unityExitCode.") }
    if ($compilerMatches.Count -gt 0) { $errors.Add("Unity compiler errors: $($compilerMatches.Count).") }
    if ($null -eq $manifest) { $errors.Add('Gate10R block manifest is missing.') }
    else {
        if ($manifest.completed -ne $true -or $manifest.formalCampaign -ne $false -or $manifest.hardMemoryRulesPassed -ne $true) { $errors.Add('Gate10R block manifest is not a completed, memory-valid, non-formal block.') }
        if ([string]$manifest.executionDesignId -ne 'gate10r-one-fresh-unity-process-per-williams-block-5pct-v1') { $errors.Add('Gate10R block design identity mismatch.') }
        if ($manifest.blockId -ne $plan.blockId -or $manifest.blockPlanSha256 -ne $planSha256) { $errors.Add('Gate10R block manifest identity/hash mismatch.') }
        if ([int]$manifest.expectedSampleCount -ne @($plan.entries).Count -or [int]$manifest.completedSampleCount -ne @($plan.entries).Count -or @($manifest.samples).Count -ne @($plan.entries).Count) { $errors.Add('Gate10R block manifest sample cardinality mismatch.') }
        if ($manifest.oneBlockPerUnityProcess -ne $true -or $manifest.oneSamplePerAlgorithmPerProcess -ne $true -or $manifest.allSamplesShareProcessId -ne $true -or $manifest.orderMatchesBlockPlan -ne $true) { $errors.Add('Gate10R block process-isolation assertions failed.') }
        if ([long]$manifest.blockRetainedManagedGrowthBytes -gt 134217728 -or [long]$manifest.blockWorkingSetGrowthBytes -gt 536870912 -or [long]$manifest.blockPrivateMemoryGrowthBytes -gt 536870912) { $errors.Add('Gate10R block exceeded a frozen memory rule.') }
        for ($index = 0; $index -lt @($plan.entries).Count; $index++) {
            $expected = $plan.entries[$index]
            $actual = $manifest.samples[$index]
            if ([int]$actual.position -ne [int]$expected.position -or [string]$actual.algorithmId -ne [string]$expected.algorithmId -or [string]$actual.runId -ne [string]$expected.runId -or [int]$actual.processId -ne [int]$manifest.processId -or $actual.completed -ne $true) { $errors.Add("Gate10R sample identity/process mismatch at index $index.") }
            foreach ($value in @($actual.workingSetBeforeBytes, $actual.workingSetRawAfterBytes, $actual.workingSetAfterCleanupBytes, $actual.privateMemoryBeforeBytes, $actual.privateMemoryRawAfterBytes, $actual.privateMemoryAfterCleanupBytes, $actual.managedMemoryBeforeBytes, $actual.managedMemoryRawAfterBytes, $actual.managedMemoryAfterCleanupBytes)) { if ([long]$value -le 0) { $errors.Add("Gate10R sample has non-positive telemetry at index $index."); break } }
            if ([long]$actual.sampleRetainedManagedGrowthBytes -gt 134217728) { $errors.Add("Gate10R sample retained managed growth exceeded 128 MiB at index $index.") }
            if ([double]$actual.processAgeBeforeMilliseconds -gt [double]$actual.processAgeRawAfterMilliseconds -or [double]$actual.processAgeRawAfterMilliseconds -gt [double]$actual.processAgeAfterCleanupMilliseconds) { $errors.Add("Gate10R sample process ages are unordered at index $index.") }
            $childManifestPath = Join-Path $OutputDirectory ([string]$actual.manifestRelativePath).Replace('/', '\')
            $childSummaryPath = Join-Path $OutputDirectory ([string]$actual.summaryRelativePath).Replace('/', '\')
            $resultPath = Join-Path $OutputDirectory ([string]$actual.workloadResultRelativePath).Replace('/', '\')
            if (-not (Test-Path -LiteralPath $childManifestPath -PathType Leaf) -or (Get-Gate10RLowerSha256 -Path $childManifestPath) -ne [string]$actual.manifestSha256) { $errors.Add("Gate10R child manifest hash mismatch at index $index.") }
            if (-not (Test-Path -LiteralPath $childSummaryPath -PathType Leaf) -or (Get-Gate10RLowerSha256 -Path $childSummaryPath) -ne [string]$actual.summarySha256) { $errors.Add("Gate10R child summary hash mismatch at index $index.") }
            if (-not (Test-Path -LiteralPath $resultPath -PathType Leaf) -or (Get-Gate10RLowerSha256 -Path $resultPath) -ne [string]$actual.workloadResultSha256) { $errors.Add("Gate10R child result hash mismatch at index $index.") }
            if (Test-Path -LiteralPath $childManifestPath -PathType Leaf) {
                $childManifest = Read-Gate10RJson -Path $childManifestPath
                if ($childManifest.completed -ne $true -or $childManifest.forcedGcBeforeCompleted -ne $true -or $childManifest.forcedGcAfterCompleted -ne $true -or $childManifest.sampleStateCreatedFresh -ne $true -or $childManifest.heavySampleReferencesReturned -ne $false -or $childManifest.plannerResetCompleted -ne $true -or $childManifest.loggerDisposed -ne $true) { $errors.Add("Gate10R child reset/cleanup contract failed at index $index.") }
            }
        }
    }
    if ($null -eq $checkpoint -or [string]$checkpoint.status -ne 'block-completed') { $errors.Add('Gate10R final block checkpoint is missing or incomplete.') }
}
if ($null -eq $lockResult -or $lockResult.passed -ne $true) { $errors.Add('Post-exit lock-hygiene result did not pass.') }

$passed = $errors.Count -eq 0
$summary = [ordered]@{
    schemaVersion = 1
    summaryKind = 'gate10r-process-reuse-5pct-process-reuse-block-wrapper-summary-attempt3-v3'
    savedAt = (Get-Date).ToString('o')
    blockId = [string]$plan.blockId
    blockPlanPath = $BlockPlanPath
    blockPlanSha256 = $planSha256
    outputDirectory = $OutputDirectory
    unityLogPath = $unityLogPath
    unityProcessId = [int]$process.Id
    exitCode = $unityExitCode
    startedAt = $startedAt.ToString('o')
    completedAt = $completedAt.ToString('o')
    wallSeconds = ($completedAt - $startedAt).TotalSeconds
    compilerErrorMatchCount = $compilerMatches.Count
    expectedFailure = [bool]$ExpectFailure
    lockHygieneMode = [string]$lockResult.mode
    lockHygieneReceiptPath = if ($null -ne $lockResult.receiptPath) { [string]$lockResult.receiptPath } else { [string]$lockResult.completionReceiptPath }
    lockHygieneReceiptSha256 = if ($null -ne $lockResult.receiptSha256) { [string]$lockResult.receiptSha256 } else { [string]$lockResult.completionReceiptSha256 }
    blockManifestSha256 = if (Test-Path -LiteralPath $blockManifestPath -PathType Leaf) { Get-Gate10RLowerSha256 -Path $blockManifestPath } else { $null }
    blockFailureSha256 = if (Test-Path -LiteralPath $blockFailurePath -PathType Leaf) { Get-Gate10RLowerSha256 -Path $blockFailurePath } else { $null }
    sampleCount = if ($null -eq $manifest) { if ($null -eq $checkpoint) { 0 } else { [int]$checkpoint.completedSampleCount } } else { [int]$manifest.completedSampleCount }
    formalCampaign = $false
    analysisRole = [string]$plan.analysisRole
    automaticRetryAttempted = $false
    automaticResumeAttempted = $false
    errors = $errors.ToArray()
    passed = $passed
}
Write-Gate10RAtomicUtf8NoBomJson -Path $summaryPath -Value $summary -Depth 30
if (-not $passed) { Write-Error "Gate10R process-reuse block verification failed: $($errors -join '; ')"; exit 1 }
Write-Host "Gate10R attempt-3 process-reuse block behavior verified: $($plan.blockId)" -ForegroundColor Green
exit 0

