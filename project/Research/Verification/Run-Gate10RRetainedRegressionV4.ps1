[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$ProjectPath,
    [switch]$BindingSmokeOnly
)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($ProjectPath) -or -not [System.IO.Path]::IsPathRooted($ProjectPath)) { throw 'Attempt 4 requires an explicit absolute ProjectPath.' }
$ProjectPath = [System.IO.Path]::GetFullPath($ProjectPath)
if ($BindingSmokeOnly) { Write-Output ('BINDING-SMOKE-PASSED|Run-Gate10RRetainedRegressionV4|' + $ProjectPath); exit 0 }

$frozenSourcePath = Join-Path $PSScriptRoot 'Run-Gate12AnalysisUnitTests.ps1'
$originalSummaryPath = Join-Path $PSScriptRoot 'Gate12_AnalysisUnitTests.summary.json'
$harnessPath = Join-Path $PSScriptRoot 'Gate10RAttempt4RetainedHarnessV4.ps1'
$root = Join-Path $PSScriptRoot 'Gate10R_ProcessReuse_5pct\v4\RetainedRegression'
$summaryPath = Join-Path $root 'RetainedRegression63.summary.json'
$stdoutPath = Join-Path $root 'RetainedRegression63.stdout.log'
$stderrPath = Join-Path $root 'RetainedRegression63.stderr.log'
$wrapperPath = Join-Path $root 'RetainedRegression63.wrapper.v4.json'
$windowsPowerShell = 'C:\WINDOWS\System32\WindowsPowerShell\v1.0\powershell.exe'
$nativePowerShellModulePath = @('C:\Users\bdscy\Documents\WindowsPowerShell\Modules', 'C:\Program Files\WindowsPowerShell\Modules', 'C:\WINDOWS\System32\WindowsPowerShell\v1.0\Modules') -join ';'

if (Test-Path -LiteralPath $root) { throw 'Gate 10R attempt-4 retained-regression evidence exists; refusing retry/overwrite.' }
foreach ($path in @($frozenSourcePath, $originalSummaryPath, $harnessPath, $windowsPowerShell)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Required retained-regression input is missing: $path" }
}
$sourceHashBefore = (Get-FileHash -Algorithm SHA256 -LiteralPath $frozenSourcePath).Hash.ToLowerInvariant()
$originalHashBefore = (Get-FileHash -Algorithm SHA256 -LiteralPath $originalSummaryPath).Hash.ToLowerInvariant()
if ($sourceHashBefore -ne 'e56a3881c0fc9fc3ecceb760d1c51129e80ec2b306acdcfefed0a3814a6885b1') { throw 'Frozen retained source changed.' }
if ($originalHashBefore -ne '1536ae459c3d8cbb90b8a9dad1f74e7937d5ceb205e6cc088745c798d136e54d') { throw 'Frozen 63/63 retained summary changed.' }

[void](New-Item -ItemType Directory -Path $root)
$previousModulePath = $env:PSModulePath
$startedAtUtc = [DateTime]::UtcNow.ToString('o')
try {
    $env:PSModulePath = $nativePowerShellModulePath
    & $windowsPowerShell -NoProfile -ExecutionPolicy Bypass -File $harnessPath -ProjectPath $ProjectPath -SummaryPath $summaryPath 1>$stdoutPath 2>$stderrPath
    $exitCode = [int]$LASTEXITCODE
} finally { $env:PSModulePath = $previousModulePath }
$completedAtUtc = [DateTime]::UtcNow.ToString('o')

$sourceHashAfter = (Get-FileHash -Algorithm SHA256 -LiteralPath $frozenSourcePath).Hash.ToLowerInvariant()
$originalHashAfter = (Get-FileHash -Algorithm SHA256 -LiteralPath $originalSummaryPath).Hash.ToLowerInvariant()
$summary = if (Test-Path -LiteralPath $summaryPath -PathType Leaf) { Get-Content -LiteralPath $summaryPath -Raw -Encoding UTF8 | ConvertFrom-Json } else { $null }
$passed = $exitCode -eq 0 -and $null -ne $summary -and $summary.passed -eq $true -and [int]$summary.assertionCount -eq 63 -and @($summary.failures).Count -eq 0 -and $sourceHashAfter -eq $sourceHashBefore -and $originalHashAfter -eq $originalHashBefore
$wrapper = [ordered]@{
    schemaVersion = 1
    summaryKind = 'gate10r-attempt4-retained-regression-file-scope-wrapper-v4'
    savedAtUtc = [DateTime]::UtcNow.ToString('o')
    startedAtUtc = $startedAtUtc
    completedAtUtc = $completedAtUtc
    executionMethod = 'Windows PowerShell 5.1 -File'
    childScriptBlockUsed = $false
    harnessPath = $harnessPath
    harnessSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $harnessPath).Hash.ToLowerInvariant()
    summaryPath = $summaryPath
    summarySha256 = if ($null -ne $summary) { (Get-FileHash -Algorithm SHA256 -LiteralPath $summaryPath).Hash.ToLowerInvariant() } else { $null }
    assertionCount = if ($null -ne $summary) { [int]$summary.assertionCount } else { 0 }
    failureCount = if ($null -ne $summary) { @($summary.failures).Count } else { $null }
    exitCode = $exitCode
    frozenSourceSha256Before = $sourceHashBefore
    frozenSourceSha256After = $sourceHashAfter
    originalSummarySha256Before = $originalHashBefore
    originalSummarySha256After = $originalHashAfter
    passed = $passed
}
$json = ($wrapper | ConvertTo-Json -Depth 12).Replace("`r`n", "`n").Replace("`r", "`n")
if (-not $json.EndsWith("`n", [StringComparison]::Ordinal)) { $json += "`n" }
$encoding = New-Object Text.UTF8Encoding($false, $true)
[IO.File]::WriteAllText($wrapperPath, $json, $encoding)
if (-not $passed) { Write-Error "Gate 10R attempt-4 retained regression failed under file scope with exit $exitCode."; exit 1 }
Write-Host 'Gate 10R attempt-4 retained regression passed 63/63 under Windows PowerShell 5.1 file/script scope.' -ForegroundColor Green
exit 0
