[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$BlockPlanPath,
    [Parameter(Mandatory = $true)][string]$OutputDirectory,
    [string]$UnityPath = 'H:\UnityEditor\2022.3.30f1c1\Editor\Unity.exe',
    [string]$ProjectPath = (Split-Path -Parent $PSScriptRoot),
    [switch]$VerificationOnly
)

$ErrorActionPreference = 'Stop'
$ProjectPath = [System.IO.Path]::GetFullPath($ProjectPath)
$BlockPlanPath = if ([System.IO.Path]::IsPathRooted($BlockPlanPath)) { [System.IO.Path]::GetFullPath($BlockPlanPath) } else { [System.IO.Path]::GetFullPath((Join-Path $ProjectPath $BlockPlanPath)) }
$OutputDirectory = if ([System.IO.Path]::IsPathRooted($OutputDirectory)) { [System.IO.Path]::GetFullPath($OutputDirectory) } else { [System.IO.Path]::GetFullPath((Join-Path $ProjectPath $OutputDirectory)) }
$UnityPath = [System.IO.Path]::GetFullPath($UnityPath)
$modulePath = Join-Path $PSScriptRoot 'Gate13ProcessReusePreparation.psm1'
Import-Module $modulePath -Force

if (-not (Test-Path -LiteralPath $BlockPlanPath -PathType Leaf)) { throw "Block plan not found: $BlockPlanPath" }
if (-not (Test-Path -LiteralPath $UnityPath -PathType Leaf)) { throw "Unity executable not found: $UnityPath" }
if (-not (Test-Path -LiteralPath (Join-Path $ProjectPath 'Assets') -PathType Container)) { throw "Unity project not found: $ProjectPath" }
$reservedFormalRoot = [System.IO.Path]::GetFullPath((Join-Path $ProjectPath 'Research\FormalRuns\Gate13_ProcessReuse\v1'))
if (Test-Path -LiteralPath $reservedFormalRoot) { throw "Reserved process-reuse formal root must not exist: $reservedFormalRoot" }
$pilotRoot = [System.IO.Path]::GetFullPath((Join-Path $ProjectPath 'Research\PilotRuns\Gate13_ProcessReuse\v1'))
$pilotPrefix = $pilotRoot.TrimEnd('\') + '\'
$verificationRoot = [System.IO.Path]::GetFullPath((Join-Path $ProjectPath 'Research\Verification\Gate13R2_PositiveBlockFixtures\v1'))
$verificationPrefix = $verificationRoot.TrimEnd('\') + '\'
$allowedOutput = if ($VerificationOnly) { $OutputDirectory.StartsWith($verificationPrefix, [System.StringComparison]::OrdinalIgnoreCase) } else { $OutputDirectory.StartsWith($pilotPrefix, [System.StringComparison]::OrdinalIgnoreCase) }
if (-not $allowedOutput) { throw $(if ($VerificationOnly) { 'Verification block output must be inside the versioned verification fixture root.' } else { 'Process-reuse block output must be inside the isolated pilot root.' }) }
if (Test-Path -LiteralPath $OutputDirectory) {
    if (-not (Test-Path -LiteralPath $OutputDirectory -PathType Container)) { throw "Output path is not a directory: $OutputDirectory" }
    if (@(Get-ChildItem -LiteralPath $OutputDirectory -Force).Count -gt 0) { throw "Output directory is not empty: $OutputDirectory" }
}
$unityLogPath = $OutputDirectory + '.Unity.log'
$summaryPath = $OutputDirectory + '.summary.json'
foreach ($path in @($unityLogPath, $summaryPath)) { if (Test-Path -LiteralPath $path) { throw "Create-new policy found an existing output: $path" } }
$unityProcesses = @(Get-Process -Name Unity -ErrorAction SilentlyContinue)
$lockPath = Join-Path $ProjectPath 'Temp\UnityLockfile'
if ($unityProcesses.Count -gt 0 -or (Test-Path -LiteralPath $lockPath)) { throw 'Close Unity and clear the project lock before starting a process-reuse block.' }

$plan = Read-G13R2Json -Path $BlockPlanPath
if ($plan.formalCampaign -ne $false -or $plan.designId -ne 'one-fresh-unity-process-per-williams-block-v1') { throw 'Block plan is not an authorized non-formal process-reuse plan.' }
$planSha256 = Get-G13R2LowerSha256 -Path $BlockPlanPath
$startedAt = Get-Date
$arguments = @(
    '-batchmode',
    '-nographics',
    '-quit',
    '-projectPath', ('"' + $ProjectPath + '"'),
    '-executeMethod', 'DDM.Research.Editor.ResearchPlanningProcessReuseBatchCommand.Run',
    '-ddmProcessReuseBlockPlanPath', ('"' + $BlockPlanPath + '"'),
    '-ddmProcessReuseBlockPlanSha256', $planSha256,
    '-ddmProcessReuseOutputDirectory', ('"' + $OutputDirectory + '"'),
    '-logFile', ('"' + $unityLogPath + '"')
)
$process = Start-Process -FilePath $UnityPath -ArgumentList $arguments -WorkingDirectory (Split-Path -Parent $UnityPath) -WindowStyle Hidden -PassThru
Wait-Process -Id $process.Id
$process.Refresh()
$unityExitCode = [int]$process.ExitCode
$completedAt = Get-Date
$compilerMatches = if (Test-Path -LiteralPath $unityLogPath) { @(Select-String -LiteralPath $unityLogPath -Pattern 'error CS\d+|Compilation failed|Scripts have compiler errors' -CaseSensitive:$false) } else { @() }
$blockManifestPath = Join-Path $OutputDirectory 'block-manifest.json'
$blockCheckpointPath = Join-Path $OutputDirectory 'block-checkpoint.json'
$manifest = if (Test-Path -LiteralPath $blockManifestPath -PathType Leaf) { Read-G13R2Json -Path $blockManifestPath } else { $null }
$checkpoint = if (Test-Path -LiteralPath $blockCheckpointPath -PathType Leaf) { Read-G13R2Json -Path $blockCheckpointPath } else { $null }
$errors = New-Object System.Collections.Generic.List[string]
if ($unityExitCode -ne 0) { $errors.Add("Unity exited with code $unityExitCode.") }
if ($compilerMatches.Count -gt 0) { $errors.Add("Unity compiler errors: $($compilerMatches.Count).") }
if ($null -eq $manifest) { $errors.Add('Block manifest is missing.') }
else {
    if ($manifest.completed -ne $true -or $manifest.formalCampaign -ne $false) { $errors.Add('Block manifest is not a completed non-formal block.') }
    if ($manifest.blockId -ne $plan.blockId -or $manifest.blockPlanSha256 -ne $planSha256) { $errors.Add('Block manifest identity/hash mismatch.') }
    if ([int]$manifest.expectedSampleCount -ne @($plan.entries).Count -or [int]$manifest.completedSampleCount -ne @($plan.entries).Count -or @($manifest.samples).Count -ne @($plan.entries).Count) { $errors.Add('Block manifest sample cardinality mismatch.') }
    if ($manifest.oneBlockPerUnityProcess -ne $true -or $manifest.oneSamplePerAlgorithmPerProcess -ne $true -or $manifest.allSamplesShareProcessId -ne $true -or $manifest.orderMatchesBlockPlan -ne $true) { $errors.Add('Block process-isolation assertions failed.') }
    for ($index = 0; $index -lt @($plan.entries).Count; $index++) {
        $expected = $plan.entries[$index]
        $actual = $manifest.samples[$index]
        if ([int]$actual.position -ne [int]$expected.position -or [string]$actual.algorithmId -ne [string]$expected.algorithmId -or [string]$actual.runId -ne [string]$expected.runId -or [int]$actual.processId -ne [int]$manifest.processId -or $actual.completed -ne $true) { $errors.Add("Sample identity/process mismatch at index $index.") }
        $childManifestPath = Join-Path $OutputDirectory ([string]$actual.manifestRelativePath).Replace('/', '\')
        $childSummaryPath = Join-Path $OutputDirectory ([string]$actual.summaryRelativePath).Replace('/', '\')
        $resultPath = Join-Path $OutputDirectory ([string]$actual.workloadResultRelativePath).Replace('/', '\')
        if (-not (Test-Path -LiteralPath $childManifestPath -PathType Leaf) -or (Get-G13R2LowerSha256 -Path $childManifestPath) -ne [string]$actual.manifestSha256) { $errors.Add("Child manifest hash mismatch at index $index.") }
        if (-not (Test-Path -LiteralPath $childSummaryPath -PathType Leaf) -or (Get-G13R2LowerSha256 -Path $childSummaryPath) -ne [string]$actual.summarySha256) { $errors.Add("Child sample-summary hash mismatch at index $index.") }
        if (-not (Test-Path -LiteralPath $resultPath -PathType Leaf) -or (Get-G13R2LowerSha256 -Path $resultPath) -ne [string]$actual.workloadResultSha256) { $errors.Add("Child workload-result hash mismatch at index $index.") }
        if (Test-Path -LiteralPath $childSummaryPath -PathType Leaf) {
            $childSummary = Read-G13R2Json -Path $childSummaryPath
            if ($childSummary.completed -ne $true -or $childSummary.formalCampaign -ne $false -or [string]$childSummary.runId -ne [string]$expected.runId -or [string]$childSummary.manifestSha256 -ne [string]$actual.manifestSha256 -or [string]$childSummary.workloadResultSha256 -ne [string]$actual.workloadResultSha256) { $errors.Add("Child sample-summary completion/hash binding mismatch at index $index.") }
        }
    }
}
if ($null -eq $checkpoint -or [string]$checkpoint.status -ne 'block-completed') { $errors.Add('Final block checkpoint is missing or incomplete.') }
$passed = $errors.Count -eq 0
$summary = [ordered]@{
    schemaVersion = 1
    summaryKind = 'gate13-r2-process-reuse-block-wrapper-summary-v1'
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
    blockManifestSha256 = if (Test-Path -LiteralPath $blockManifestPath -PathType Leaf) { Get-G13R2LowerSha256 -Path $blockManifestPath } else { $null }
    sampleCount = if ($null -eq $manifest) { 0 } else { [int]$manifest.completedSampleCount }
    formalCampaign = $false
    analysisRole = [string]$plan.analysisRole
    automaticRetryAttempted = $false
    automaticResumeAttempted = $false
    errors = $errors.ToArray()
    passed = $passed
}
Write-G13R2AtomicUtf8NoBomJson -Path $summaryPath -Value $summary -Depth 20
if (-not $passed) { Write-Error "Process-reuse block failed: $($errors -join '; ')"; exit 1 }
Write-Host "Process-reuse block completed: $($plan.blockId)" -ForegroundColor Green
exit 0
