[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$ScenarioPath,
    [Parameter(Mandatory = $true)][string]$OutputDirectory,
    [Parameter(Mandatory = $true)][string]$RunId,
    [Parameter(Mandatory = $true)][ValidateSet('A*-R', 'D*L', 'C-FF', 'IDFF')][string]$Algorithm,
    [string]$UnityPath = 'H:\UnityEditor\2022.3.30f1c1\Editor\Unity.exe',
    [string]$ProjectPath = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = 'Stop'
$ProjectPath = [System.IO.Path]::GetFullPath($ProjectPath)
$ScenarioPath = [System.IO.Path]::GetFullPath($ScenarioPath)
$OutputDirectory = [System.IO.Path]::GetFullPath($OutputDirectory)
$UnityPath = [System.IO.Path]::GetFullPath($UnityPath)
$modulePath = Join-Path $PSScriptRoot 'Gate13ProcessReusePreparation.psm1'
Import-Module $modulePath -Force
if (-not (Test-Path -LiteralPath $ScenarioPath -PathType Leaf)) { throw "Scenario file not found: $ScenarioPath" }
if (-not (Test-Path -LiteralPath $UnityPath -PathType Leaf)) { throw "Unity executable not found: $UnityPath" }
if ($RunId -notmatch '^[A-Za-z0-9][A-Za-z0-9_.-]{0,127}$') { throw 'RunId is not file-safe.' }
$pilotRoot = [System.IO.Path]::GetFullPath((Join-Path $ProjectPath 'Research\PilotRuns\Gate13_ProcessReuse\v1'))
$pilotPrefix = $pilotRoot.TrimEnd('\') + '\'
$reservedFormalRoot = [System.IO.Path]::GetFullPath((Join-Path $ProjectPath 'Research\FormalRuns\Gate13_ProcessReuse\v1'))
if (-not $OutputDirectory.StartsWith($pilotPrefix, [StringComparison]::OrdinalIgnoreCase)) { throw 'Cold reference output must be inside the isolated process-reuse pilot root.' }
if (Test-Path -LiteralPath $reservedFormalRoot) { throw 'Reserved process-reuse formal root must remain absent.' }
if (Test-Path -LiteralPath $OutputDirectory) {
    if (-not (Test-Path -LiteralPath $OutputDirectory -PathType Container) -or @(Get-ChildItem -LiteralPath $OutputDirectory -Force).Count -gt 0) { throw "Cold reference output is not a fresh empty directory: $OutputDirectory" }
}
$unityLogPath = $OutputDirectory + '.Unity.log'
$summaryPath = $OutputDirectory + '.summary.json'
foreach ($path in @($unityLogPath, $summaryPath)) { if (Test-Path -LiteralPath $path) { throw "Create-new cold-reference output exists: $path" } }
if (@(Get-Process -Name Unity -ErrorAction SilentlyContinue).Count -gt 0 -or (Test-Path -LiteralPath (Join-Path $ProjectPath 'Temp\UnityLockfile'))) { throw 'Unity must be closed and the project lock absent.' }
$parent = Split-Path -Parent $OutputDirectory
if (-not (Test-Path -LiteralPath $parent -PathType Container)) { [void](New-Item -ItemType Directory -Path $parent -Force) }
$arguments = @(
    '-batchmode', '-nographics', '-quit', '-projectPath', ('"' + $ProjectPath + '"'),
    '-executeMethod', 'DDM.Research.Editor.ResearchPlanningBatchCommand.Run',
    '-ddmScenarioPath', ('"' + $ScenarioPath + '"'),
    '-ddmOutputDirectory', ('"' + $OutputDirectory + '"'),
    '-ddmRunId', ('"' + $RunId + '"'),
    '-ddmAlgorithm', ('"' + $Algorithm + '"'),
    '-logFile', ('"' + $unityLogPath + '"')
)
$startedAt = Get-Date
$process = Start-Process -FilePath $UnityPath -ArgumentList $arguments -WorkingDirectory (Split-Path -Parent $UnityPath) -WindowStyle Hidden -PassThru
Wait-Process -Id $process.Id
$process.Refresh()
$exitCode = [int]$process.ExitCode
$completedAt = Get-Date
$compilerPatterns = @('error CS\d{4}', 'Scripts have compiler errors', 'Compilation failed', 'executeMethod.+could not be found')
$compilerMatches = if (Test-Path -LiteralPath $unityLogPath) { @(Select-String -LiteralPath $unityLogPath -Pattern $compilerPatterns -AllMatches) } else { @() }
$manifestPath = Join-Path $OutputDirectory 'manifest.json'
$resultPath = Join-Path $OutputDirectory 'workload-result.json'
$manifest = if (Test-Path -LiteralPath $manifestPath -PathType Leaf) { Read-G13R2Json -Path $manifestPath } else { $null }
$errors = New-Object System.Collections.Generic.List[string]
if ($exitCode -ne 0) { $errors.Add("Unity exited with code $exitCode.") }
if ($compilerMatches.Count -gt 0) { $errors.Add("Unity compiler-error matches: $($compilerMatches.Count).") }
if ($null -eq $manifest -or $manifest.completed -ne $true -or [string]$manifest.runId -ne $RunId -or [string]$manifest.algorithmId -ne $Algorithm) { $errors.Add('Cold-reference manifest identity/completion mismatch.') }
if (-not (Test-Path -LiteralPath $resultPath -PathType Leaf)) { $errors.Add('Cold-reference workload result is missing.') }
$summary = [ordered]@{
    schemaVersion = 1
    summaryKind = 'gate13-r2-fresh-cold-structural-reference-wrapper-summary-v1'
    savedAt = (Get-Date).ToString('o')
    runId = $RunId
    algorithmId = $Algorithm
    scenarioPath = $ScenarioPath
    outputDirectory = $OutputDirectory
    unityProcessId = [int]$process.Id
    exitCode = $exitCode
    startedAt = $startedAt.ToString('o')
    completedAt = $completedAt.ToString('o')
    wallSeconds = ($completedAt - $startedAt).TotalSeconds
    unityLogPath = $unityLogPath
    unityLogSha256 = if (Test-Path -LiteralPath $unityLogPath -PathType Leaf) { Get-G13R2LowerSha256 -Path $unityLogPath } else { $null }
    manifestSha256 = if (Test-Path -LiteralPath $manifestPath -PathType Leaf) { Get-G13R2LowerSha256 -Path $manifestPath } else { $null }
    workloadResultSha256 = if (Test-Path -LiteralPath $resultPath -PathType Leaf) { Get-G13R2LowerSha256 -Path $resultPath } else { $null }
    formalCampaign = $false
    excludedFromFormalAnalysis = $true
    structuralReferenceOnly = $true
    automaticRetryAttempted = $false
    automaticResumeAttempted = $false
    errors = $errors.ToArray()
    passed = $errors.Count -eq 0
}
Write-G13R2AtomicUtf8NoBomJson -Path $summaryPath -Value $summary -Depth 20
$summary | ConvertTo-Json -Depth 8
if ($errors.Count -gt 0) { Write-Error "Fresh cold structural reference failed without retry: $($errors -join '; ')"; exit 1 }
exit 0
