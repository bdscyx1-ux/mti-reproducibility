[CmdletBinding()]
param([string]$ProjectPath = (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)))

$ErrorActionPreference = 'Stop'
$ProjectPath = [System.IO.Path]::GetFullPath($ProjectPath)
$sourceScriptPath = Join-Path $PSScriptRoot 'Run-Gate12AnalysisUnitTests.ps1'
$originalSummaryPath = Join-Path $PSScriptRoot 'Gate12_AnalysisUnitTests.summary.json'
$v2SummaryPath = Join-Path $PSScriptRoot 'Gate13R2_v2_RetainedRegression63.summary.json'
$stdoutPath = Join-Path $PSScriptRoot 'Gate13R2_v2_RetainedRegression63.stdout.log'
$stderrPath = Join-Path $PSScriptRoot 'Gate13R2_v2_RetainedRegression63.stderr.log'
if (Test-Path -LiteralPath $v2SummaryPath -or Test-Path -LiteralPath $stdoutPath -or Test-Path -LiteralPath $stderrPath) { throw 'V2 retained-regression evidence already exists; refusing retry/overwrite.' }
$originalHashBefore = (Get-FileHash -LiteralPath $originalSummaryPath -Algorithm SHA256).Hash.ToLowerInvariant()
$source = [System.IO.File]::ReadAllText($sourceScriptPath)
$escapedDirectory = $PSScriptRoot.Replace("'", "''")
$source = $source.Replace('$scriptDirectory = Split-Path -Parent $MyInvocation.MyCommand.Path', ("`$scriptDirectory = '" + $escapedDirectory + "'"))
$source = $source.Replace("`$summaryPath = Join-Path `$scriptDirectory 'Gate12_AnalysisUnitTests.summary.json'", "`$summaryPath = Join-Path `$scriptDirectory 'Gate13R2_v2_RetainedRegression63.summary.json'")
$source | & 'C:\WINDOWS\System32\WindowsPowerShell\v1.0\powershell.exe' -NoProfile -ExecutionPolicy Bypass -Command '& ([ScriptBlock]::Create([Console]::In.ReadToEnd()))' 1> $stdoutPath 2> $stderrPath
$exitCode = [int]$LASTEXITCODE
if ($exitCode -ne 0) { Write-Error "Retained 63-assertion regression failed with exit $exitCode; no retry was attempted."; exit 1 }
if (-not (Test-Path -LiteralPath $v2SummaryPath -PathType Leaf)) { throw 'V2 retained-regression summary is missing.' }
$summary = Get-Content -LiteralPath $v2SummaryPath -Raw -Encoding UTF8 | ConvertFrom-Json
$originalHashAfter = (Get-FileHash -LiteralPath $originalSummaryPath -Algorithm SHA256).Hash.ToLowerInvariant()
if ($summary.passed -ne $true -or [int]$summary.assertionCount -ne 63 -or $originalHashAfter -ne $originalHashBefore) { throw 'V2 retained regression did not pass 63/63 or modified original evidence.' }
Write-Host 'Gate 13-R2 v2 retained regression passed 63/63.' -ForegroundColor Green
exit 0
