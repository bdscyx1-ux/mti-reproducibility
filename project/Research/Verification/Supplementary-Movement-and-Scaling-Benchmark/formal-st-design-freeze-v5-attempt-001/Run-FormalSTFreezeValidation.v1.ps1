[CmdletBinding()]
param(
    [string]$ProjectRoot = 'H:\DDM_Final_Project',
    [string]$EvidenceRoot = 'H:\DDM_Final_Project\Research\Verification\Gate14Re-ME\formal-st-design-freeze-v5-attempt-001'
)

$ErrorActionPreference = 'Stop'
$project = [System.IO.Path]::GetFullPath($ProjectRoot)
$evidence = [System.IO.Path]::GetFullPath($EvidenceRoot)
$python = 'C:\Users\bdscy\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe'
$expectedPythonSha256 = '7d938c92a08d6495421f2f1076ccd7198aec0b288471abc0a55e90b1150d96a1'
$script = Join-Path $evidence 'validate_formal_st_freeze_v5.py'
$preFreeze = Join-Path $evidence 'pre-validation-freeze-manifest.v1.json'

if (-not (Test-Path -LiteralPath $python -PathType Leaf)) { throw "Pinned Python missing: $python" }
if (((Get-FileHash -LiteralPath $python -Algorithm SHA256).Hash.ToLowerInvariant()) -ne $expectedPythonSha256) { throw 'Pinned Python hash mismatch.' }
if (-not (Test-Path -LiteralPath $preFreeze -PathType Leaf)) { throw 'Pre-validation freeze manifest missing.' }

$stdout = Join-Path $evidence 'execution.stdout.log'
$stderr = Join-Path $evidence 'execution.stderr.log'
& $python $script --project-root $project --evidence-root $evidence 1> $stdout 2> $stderr
$exitCode = $LASTEXITCODE
if (Test-Path -LiteralPath $stdout) { (Get-Item -LiteralPath $stdout).IsReadOnly = $true }
if (Test-Path -LiteralPath $stderr) { (Get-Item -LiteralPath $stderr).IsReadOnly = $true }
if ($exitCode -ne 0) { throw "Formal ST freeze validation failed closed with exit code $exitCode. See $stderr" }
Get-Content -LiteralPath $stdout -Raw
