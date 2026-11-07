[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$projectRoot = 'H:\DDM_Final_Project'
$rawRoot = 'H:\DDM_Final_Project\Research\PilotRuns\Gate14Re-ME\load-qualification\attempt-007'
$executionEvidenceRoot = 'H:\DDM_Final_Project\Research\Verification\Gate14Re-ME\load-qualification-execution-attempt-009'
$sealRoot = 'H:\DDM_Final_Project\Research\Verification\Gate14Re-ME\load-qualification-paused-seal-attempt-009'
$outputRoot = 'H:\DDM_Final_Project\Research\Verification\Gate14Re-ME\load-qualification-offline-necessary-revalidation-attempt-001'
$python = 'C:\Users\bdscy\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe'
$validator = Join-Path $outputRoot 'offline_necessary_validator_v1.py'
$freezeManifest = Join-Path $outputRoot 'pre-execution-freeze-manifest.v1.json'
$resultPath = Join-Path $outputRoot 'offline-validation-result.v1.json'
$progressPath = Join-Path $outputRoot 'progress.v1.json'
$stdoutPath = Join-Path $outputRoot 'validator.stdout.log'
$stderrPath = Join-Path $outputRoot 'validator.stderr.log'
$observationPath = Join-Path $outputRoot 'execution-observation.v1.json'
$timeoutSeconds = 1800
$expectedPythonSha256 = '7d938c92a08d6495421f2f1076ccd7198aec0b288471abc0a55e90b1150d96a1'

function Get-UtcIso {
    return [DateTimeOffset]::UtcNow.ToString('o')
}

function Write-JsonAtomic {
    param(
        [Parameter(Mandatory = $true)] [string] $LiteralPath,
        [Parameter(Mandatory = $true)] [object] $Value
    )
    $temporary = "$LiteralPath.tmp"
    $Value | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $temporary -Encoding utf8
    Move-Item -LiteralPath $temporary -Destination $LiteralPath -Force
}

if (-not (Test-Path -LiteralPath $python -PathType Leaf)) {
    throw "Frozen Python executable is missing: $python"
}
$actualPythonSha256 = (Get-FileHash -LiteralPath $python -Algorithm SHA256).Hash.ToLowerInvariant()
if ($actualPythonSha256 -ne $expectedPythonSha256) {
    throw "Frozen Python SHA-256 mismatch: $actualPythonSha256"
}
foreach ($required in @($validator, $freezeManifest)) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) {
        throw "Required frozen artifact is missing: $required"
    }
}
foreach ($freshOutput in @($resultPath, $progressPath, $stdoutPath, $stderrPath, $observationPath)) {
    if (Test-Path -LiteralPath $freshOutput) {
        throw "One-shot output already exists; refusing same-attempt retry: $freshOutput"
    }
}

$processRows = @(Get-CimInstance Win32_Process -ErrorAction Stop)
$activeQualification = @($processRows | Where-Object {
    $commandLine = [string]$_.CommandLine
    $commandLine.Contains('DDM.Research.Editor.Gate14ReMELoadQualificationRunnerV3.Run') -and
    $commandLine.Contains($rawRoot)
})
$activeOriginalSupervisor = @($processRows | Where-Object {
    $_.ProcessId -eq 89976
})
$activeOfflineValidator = @($processRows | Where-Object {
    $commandLine = [string]$_.CommandLine
    $commandLine.Contains('offline_necessary_validator_v1.py') -and
    -not $commandLine.Contains('Run-OfflineNecessaryRevalidation.v1.ps1')
})
if ($activeQualification.Count -ne 0 -or $activeOriginalSupervisor.Count -ne 0 -or $activeOfflineValidator.Count -ne 0) {
    throw "Concurrent acquisition/supervisor/offline-validator process detected; fail closed."
}

$arguments = @(
    $validator,
    '--project-root', $projectRoot,
    '--raw-root', $rawRoot,
    '--execution-evidence-root', $executionEvidenceRoot,
    '--seal-root', $sealRoot,
    '--output-root', $outputRoot,
    '--freeze-manifest', $freezeManifest,
    '--output', $resultPath,
    '--progress', $progressPath
)

$startedAtUtc = Get-UtcIso
$stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
$peakWorkingSetBytes = 0L
$peakPrivateMemoryBytes = 0L
$peakCpuSeconds = 0.0
$timedOut = $false
$process = Start-Process -FilePath $python -ArgumentList $arguments -WorkingDirectory $outputRoot -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath -PassThru -WindowStyle Hidden

while (-not $process.HasExited) {
    Start-Sleep -Milliseconds 1000
    $process.Refresh()
    if (-not $process.HasExited) {
        $peakWorkingSetBytes = [Math]::Max($peakWorkingSetBytes, [int64]$process.WorkingSet64)
        $peakPrivateMemoryBytes = [Math]::Max($peakPrivateMemoryBytes, [int64]$process.PrivateMemorySize64)
        $peakCpuSeconds = [Math]::Max($peakCpuSeconds, $process.TotalProcessorTime.TotalSeconds)
    }
    if ($stopwatch.Elapsed.TotalSeconds -ge $timeoutSeconds) {
        $timedOut = $true
        Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
        $process.WaitForExit()
        break
    }
}
$process.WaitForExit()
$process.Refresh()
$stopwatch.Stop()

$exitCode = if ($timedOut) { -2 } else { $process.ExitCode }
$resultStatus = $null
if (Test-Path -LiteralPath $resultPath -PathType Leaf) {
    try {
        $resultStatus = (Get-Content -LiteralPath $resultPath -Raw | ConvertFrom-Json).status
    }
    catch {
        $resultStatus = 'UNREADABLE_RESULT'
    }
}
$observation = [ordered]@{
    schema = 'gate14re-me-offline-revalidation-execution-observation-v1'
    studyId = 'Gate14Re-ME'
    sourceAttemptId = 'load-qualification-execution-attempt-009'
    offlineRevalidationAttemptId = 'load-qualification-offline-necessary-revalidation-attempt-001'
    startedAtUtc = $startedAtUtc
    completedAtUtc = Get-UtcIso
    elapsedSeconds = [Math]::Round($stopwatch.Elapsed.TotalSeconds, 3)
    processId = $process.Id
    exitCode = $exitCode
    timeoutSeconds = $timeoutSeconds
    timedOut = $timedOut
    peakWorkingSetBytes = $peakWorkingSetBytes
    peakPrivateMemoryBytes = $peakPrivateMemoryBytes
    peakCpuSeconds = [Math]::Round($peakCpuSeconds, 3)
    resultStatus = $resultStatus
    pythonPath = $python
    pythonSha256 = $actualPythonSha256
    validatorPath = $validator
    validatorSha256 = (Get-FileHash -LiteralPath $validator -Algorithm SHA256).Hash.ToLowerInvariant()
    freezeManifestPath = $freezeManifest
    freezeManifestSha256 = (Get-FileHash -LiteralPath $freezeManifest -Algorithm SHA256).Hash.ToLowerInvariant()
    sourceRootsWritten = $false
    sameAttemptRetryPerformed = $false
}
Write-JsonAtomic -LiteralPath $observationPath -Value $observation

if ($exitCode -eq 0 -and $resultStatus -eq 'PASS_OFFLINE_NECESSARY_RAW_VALIDATION') {
    exit 0
}
exit 2
