[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ProjectPath
)

$ErrorActionPreference = 'Stop'
$resolvedProject = (Resolve-Path -LiteralPath $ProjectPath).Path
$analysisRoot = Join-Path $resolvedProject 'Research\Analysis\Gate13R_RQAligned_Preregistration\v1'
$dryRunA = Join-Path $resolvedProject 'Research\Verification\Gate13R_RQAligned_Preregistration\v4-analysis-dryrun-a'
$dryRunB = Join-Path $resolvedProject 'Research\Verification\Gate13R_RQAligned_Preregistration\v4-analysis-dryrun-b'
$validationRoot = Join-Path $resolvedProject 'Research\Verification\Gate13R_RQAligned_Preregistration\v5-final'
$summaryPath = Join-Path $validationRoot 'FinalAudit.summary.json'
$analyzer = Join-Path $resolvedProject 'Research\Analyze-Gate13RRQAlignedPreregistrationV1.py'
$testScript = Join-Path $resolvedProject 'Research\Test-Gate13RRQAlignedPreregistrationV1.ps1'

if (Test-Path -LiteralPath $analysisRoot) {
    throw "Analysis root already exists; refusing to overwrite: $analysisRoot"
}
if (-not (Test-Path -LiteralPath $dryRunA) -or -not (Test-Path -LiteralPath $dryRunB)) {
    throw 'Deterministic validation roots are missing.'
}
if (Test-Path -LiteralPath (Join-Path $resolvedProject 'Research\FormalRuns\Gate13R_Serial_10pct\v2')) {
    throw 'Forbidden formal root exists.'
}

New-Item -ItemType Directory -Path $validationRoot -Force | Out-Null
& py -3 $analyzer --self-test | Set-Content -LiteralPath (Join-Path $validationRoot 'AnalyzerSelfTest.summary.json') -Encoding UTF8
if ($LASTEXITCODE -ne 0) { throw 'Analyzer self-test failed.' }

& py -3 $analyzer --project-root $resolvedProject --output-root $analysisRoot --fixed-time-utc '2026-10-08T10:40:36.7028036Z' | Set-Content -LiteralPath (Join-Path $validationRoot 'AnalysisRun.summary.json') -Encoding UTF8
if ($LASTEXITCODE -ne 0) { throw 'Read-only analysis failed.' }

& $testScript -ProjectPath $resolvedProject -AnalysisRoot $analysisRoot -DeterministicRootA $dryRunA -DeterministicRootB $dryRunB -SummaryPath $summaryPath
if ($LASTEXITCODE -ne 0) { throw 'Final validation failed.' }

Write-Output "GATE13R_RQALIGNED_NONEXECUTING_ANALYSIS_PASS"
