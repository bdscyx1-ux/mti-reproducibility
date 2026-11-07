[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$ProjectRoot = 'H:\DDM_Final_Project',

    [Parameter(Mandatory = $false)]
    [string]$OutputRoot = 'H:\DDM_Final_Project\Research\Verification\Gate14Re-ME\formal-st-anonymous-power-attempt-001'
)

$ErrorActionPreference = 'Stop'
$project = [System.IO.Path]::GetFullPath($ProjectRoot)
$output = [System.IO.Path]::GetFullPath($OutputRoot)
$python = 'C:\Users\bdscy\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe'
$packages = Join-Path $project 'Research\Gate14Re-ME\Runtime\v1\python-packages'
$script = Join-Path $output 'anonymous_power_v1.py'
$manifestPath = Join-Path $output 'pre-execution-freeze-manifest.v1.json'

if (-not (Test-Path -LiteralPath $python -PathType Leaf)) { throw "Pinned Python is missing: $python" }
if (-not (Test-Path -LiteralPath $packages -PathType Container)) { throw "Pinned Python packages are missing: $packages" }
if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) { throw "Freeze manifest is missing: $manifestPath" }

$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
if ($manifest.schema -ne 'gate14re-me-formal-st-anonymous-power-pre-execution-freeze-manifest-v1') {
    throw 'Unexpected pre-execution freeze manifest schema.'
}
foreach ($entry in $manifest.files) {
    $path = Join-Path $output $entry.relativePath
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Frozen file missing: $($entry.relativePath)" }
    $item = Get-Item -LiteralPath $path
    if ($item.Length -ne [int64]$entry.bytes) { throw "Frozen file size mismatch: $($entry.relativePath)" }
    $hash = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($hash -ne $entry.sha256) { throw "Frozen file hash mismatch: $($entry.relativePath)" }
}

$expectedPythonHash = '7d938c92a08d6495421f2f1076ccd7198aec0b288471abc0a55e90b1150d96a1'
$actualPythonHash = (Get-FileHash -LiteralPath $python -Algorithm SHA256).Hash.ToLowerInvariant()
if ($actualPythonHash -ne $expectedPythonHash) { throw "Pinned Python hash mismatch: $actualPythonHash" }

$env:PYTHONPATH = $packages
$stdout = Join-Path $output 'execution.stdout.log'
$stderr = Join-Path $output 'execution.stderr.log'
& $python $script --project-root $project --output-root $output 1> $stdout 2> $stderr
$exitCode = $LASTEXITCODE
if (Test-Path -LiteralPath $stdout) { (Get-Item -LiteralPath $stdout).IsReadOnly = $true }
if (Test-Path -LiteralPath $stderr) { (Get-Item -LiteralPath $stderr).IsReadOnly = $true }
if ($exitCode -ne 0) { throw "Anonymous power calculation failed closed with exit code $exitCode. See $stderr" }

Get-Content -LiteralPath $stdout -Raw
