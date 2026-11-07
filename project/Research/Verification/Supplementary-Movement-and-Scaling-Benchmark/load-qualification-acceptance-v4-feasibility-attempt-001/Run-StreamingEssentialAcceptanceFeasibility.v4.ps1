[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$projectRoot = [System.IO.Path]::GetFullPath('H:/DDM_Final_Project')
$attemptRoot = Join-Path $projectRoot 'Research/Verification/Gate14Re-ME/load-qualification-acceptance-v4-feasibility-attempt-001'
$outputRoot = Join-Path $attemptRoot 'delivery'
$python = 'C:/Users/bdscy/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe'
$tool = Join-Path $projectRoot 'Research/Gate14Re-ME/Tools/gate14re_me_qualification_delivery_v4_0.py'
$stdoutPath = Join-Path $attemptRoot 'validator.stdout.log'
$stderrPath = Join-Path $attemptRoot 'validator.stderr.log'
$observationPath = Join-Path $attemptRoot 'execution-observation.v4.json'

if (Test-Path -LiteralPath $outputRoot) {
    throw "Output root already exists; same-attempt retry is prohibited: $outputRoot"
}

$frozen = @{
    $tool = 'c77519c772f6f7fcc1a80f6e3698d446d67445b524d4bd1f0d526eff864df717'
    (Join-Path $attemptRoot 'analysis-plan.v4.json') = 'd9de7de8115855e136585e38824843e0140c8ab79c4a6f6b53d55e64ea3d8bdb'
    (Join-Path $attemptRoot 'user-authorization-receipt.v4.json') = 'c21795c37d9b145a66ff1a8e4b3d9499f5659c68ac2a94452a6d7ae0aa2c8ab5'
    (Join-Path $attemptRoot 'field-boundary.v4.json') = 'fedf07fa507f272247c490c961ee8c6782c37a7c5eaa2971bfd59b70c835f9c8'
    $python = '7d938c92a08d6495421f2f1076ccd7198aec0b288471abc0a55e90b1150d96a1'
}
foreach ($item in $frozen.GetEnumerator()) {
    if (-not (Test-Path -LiteralPath $item.Key -PathType Leaf)) {
        throw "Frozen file missing: $($item.Key)"
    }
    $actual = (Get-FileHash -Algorithm SHA256 -LiteralPath $item.Key).Hash.ToLowerInvariant()
    if ($actual -ne $item.Value) {
        throw "Frozen hash mismatch: $($item.Key); expected=$($item.Value); actual=$actual"
    }
}

$arguments = @(
    $tool,
    '--project-root', $projectRoot,
    '--raw-root', (Join-Path $projectRoot 'Research/PilotRuns/Gate14Re-ME/load-qualification/attempt-007'),
    '--output-root', $outputRoot,
    '--output-schema', (Join-Path $projectRoot 'Research/Gate14Re-ME/Execution/v3/load-qualification-output-schema.v3.json'),
    '--output-schema-sha256', 'e9a16e52e041b5818f1d25a343bdf86260d654177aff97bb0c5102637d554a7c',
    '--seal-manifest', (Join-Path $projectRoot 'Research/Verification/Gate14Re-ME/load-qualification-paused-seal-attempt-009/measured-file-manifest.v1.jsonl'),
    '--seal-manifest-sha256', 'bb05763473cb5af321bd82f3b00a738cd3d066522527a813fef667b6c50a493f',
    '--seal-terminal', (Join-Path $projectRoot 'Research/Verification/Gate14Re-ME/load-qualification-paused-seal-attempt-009/terminal-seal-receipt.v1.json'),
    '--seal-terminal-sha256', '7c7c56f7b75b9fd1f4bbfee439960b6c486e180e940bdc09f99c171c059bd705',
    '--offline-validation-result', (Join-Path $projectRoot 'Research/Verification/Gate14Re-ME/load-qualification-offline-necessary-revalidation-attempt-002/offline-validation-result.v1.json'),
    '--offline-validation-result-sha256', '2afcc259c47e390ff07c2c1cc2d295fe45d3aff249666174e93d862d0f4b9270',
    '--runtime-manifest', (Join-Path $projectRoot 'Research/Gate14Re-ME/Runtime/v1/typed-parquet-runtime-manifest.v1.json'),
    '--runtime-manifest-sha256', '254375836c5c6c8ed09654d5f1817d1fa88c21a8c02447019f29116e3b2a088e',
    '--pyarrow-root', (Join-Path $projectRoot 'Research/Gate14Re-ME/Runtime/v1/python-packages'),
    '--batch-size', '4096'
)

$started = [DateTimeOffset]::UtcNow
$process = Start-Process -FilePath $python -ArgumentList $arguments -WorkingDirectory $projectRoot -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath -PassThru -WindowStyle Hidden
$peakWorkingSet = [int64]0
$peakPagedMemory = [int64]0
while (-not $process.HasExited) {
    $process.Refresh()
    if ($process.WorkingSet64 -gt $peakWorkingSet) { $peakWorkingSet = $process.WorkingSet64 }
    if ($process.PagedMemorySize64 -gt $peakPagedMemory) { $peakPagedMemory = $process.PagedMemorySize64 }
    Start-Sleep -Milliseconds 250
}
$process.WaitForExit()
$process.Refresh()
if ($process.PeakWorkingSet64 -gt $peakWorkingSet) { $peakWorkingSet = $process.PeakWorkingSet64 }
if ($process.PeakPagedMemorySize64 -gt $peakPagedMemory) { $peakPagedMemory = $process.PeakPagedMemorySize64 }
$completed = [DateTimeOffset]::UtcNow

$observation = [ordered]@{
    schema = 'gate14re-me-streaming-essential-acceptance-execution-observation-v4'
    version = 4
    startedAtUtc = $started.ToString('o')
    completedAtUtc = $completed.ToString('o')
    elapsedSeconds = [Math]::Round(($completed - $started).TotalSeconds, 3)
    processId = $process.Id
    exitCode = $process.ExitCode
    peakWorkingSetBytes = $peakWorkingSet
    peakPagedMemoryBytes = $peakPagedMemory
    stdoutRelativePath = 'validator.stdout.log'
    stderrRelativePath = 'validator.stderr.log'
    outputRoot = $outputRoot.Replace('\', '/')
    sourceRootsModified = $false
}
$observation | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $observationPath -Encoding utf8NoBOM

if ($process.ExitCode -ne 0) {
    throw "Streaming essential acceptance feasibility failed closed with exit code $($process.ExitCode); evidence preserved at $attemptRoot"
}

Write-Output ($observation | ConvertTo-Json -Depth 10 -Compress)
