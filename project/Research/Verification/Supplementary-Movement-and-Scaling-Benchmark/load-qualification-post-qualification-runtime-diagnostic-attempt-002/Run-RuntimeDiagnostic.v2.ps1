[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$Root = 'H:\DDM_Final_Project\Research\Verification\Gate14Re-ME\load-qualification-post-qualification-runtime-diagnostic-attempt-002'
$ManifestPath = Join-Path $Root 'pre-execution-freeze-manifest.v2.json'
$ScriptPath = Join-Path $Root 'runtime_diagnostic_v2.py'
$PythonPath = 'C:\Users\bdscy\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe'
$TerminalPath = Join-Path $Root 'terminal-receipt.v2.json'
$StdoutPath = Join-Path $Root 'execution.stdout.log'
$StderrPath = Join-Path $Root 'execution.stderr.log'
$ObservationPath = Join-Path $Root 'execution-observation.v2.json'

if (Test-Path -LiteralPath $TerminalPath) {
    throw 'One-shot diagnostic terminal receipt already exists.'
}

$manifest = Get-Content -Raw -LiteralPath $ManifestPath | ConvertFrom-Json -Depth 100
if ($manifest.status -ne 'FROZEN_FOR_ONE_SHOT_EXECUTION') {
    throw 'Pre-execution freeze status mismatch.'
}
foreach ($entry in $manifest.files) {
    $item = Get-Item -LiteralPath ([string]$entry.absolutePath)
    if ($item.Length -ne [int64]$entry.bytes) {
        throw "Frozen byte-count mismatch: $($entry.absolutePath)"
    }
    $actualHash = (Get-FileHash -Algorithm SHA256 -LiteralPath ([string]$entry.absolutePath)).Hash.ToLowerInvariant()
    if ($actualHash -ne [string]$entry.sha256) {
        throw "Frozen SHA-256 mismatch: $($entry.absolutePath)"
    }
}

$pythonItem = Get-Item -LiteralPath $PythonPath
if ($pythonItem.Length -ne [int64]$manifest.runtime.pythonBytes) {
    throw 'Frozen Python byte-count mismatch.'
}
$pythonHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $PythonPath).Hash.ToLowerInvariant()
if ($pythonHash -ne [string]$manifest.runtime.pythonSha256) {
    throw 'Frozen Python SHA-256 mismatch.'
}

$startedAtUtc = [DateTimeOffset]::UtcNow
$stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
& $PythonPath $ScriptPath 1> $StdoutPath 2> $StderrPath
$exitCode = $LASTEXITCODE
$stopwatch.Stop()
$completedAtUtc = [DateTimeOffset]::UtcNow

$observation = [ordered]@{
    schema = 'gate14re-me-runtime-diagnostic-execution-observation-v2'
    startedAtUtc = $startedAtUtc.ToString('o')
    completedAtUtc = $completedAtUtc.ToString('o')
    elapsedSeconds = [Math]::Round($stopwatch.Elapsed.TotalSeconds, 3)
    exitCode = $exitCode
    pythonPath = $PythonPath.Replace('\', '/')
    pythonSha256 = $pythonHash
    scriptSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $ScriptPath).Hash.ToLowerInvariant()
    preExecutionFreezeManifestSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $ManifestPath).Hash.ToLowerInvariant()
    stdoutPath = $StdoutPath.Replace('\', '/')
    stderrPath = $StderrPath.Replace('\', '/')
}
$observation | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $ObservationPath -Encoding utf8NoBOM

if ($exitCode -ne 0) {
    Get-Content -Raw -LiteralPath $StderrPath | Write-Error
    exit $exitCode
}
if (-not (Test-Path -LiteralPath $TerminalPath)) {
    throw 'Diagnostic exited zero without terminal receipt.'
}
$terminal = Get-Content -Raw -LiteralPath $TerminalPath | ConvertFrom-Json -Depth 100
if ($terminal.status -ne 'PASS_POST_QUALIFICATION_DESCRIPTIVE_ENGINEERING_RUNTIME_DIAGNOSTIC') {
    throw "Unexpected diagnostic terminal status: $($terminal.status)"
}
Get-Content -Raw -LiteralPath $StdoutPath
