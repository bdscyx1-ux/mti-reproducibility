[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$ProjectPath,
    [switch]$ValidationOnly
)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($ProjectPath) -or -not [System.IO.Path]::IsPathRooted($ProjectPath)) { throw 'An explicit absolute ProjectPath is required.' }
$ProjectPath = [System.IO.Path]::GetFullPath($ProjectPath)

$utf8NoBom = New-Object System.Text.UTF8Encoding($false, $true)
function Get-LowerSha256([string]$Path) { (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToLowerInvariant() }
function Write-NewText([string]$Path, [string]$Text) {
    if ($ValidationOnly) {
        if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "Generated v4 source is missing: $Path" }
        if (-not [string]::Equals([System.IO.File]::ReadAllText($Path), $Text, [System.StringComparison]::Ordinal)) { throw "Generated v4 source differs from its deterministic transform: $Path" }
        return
    }
    if (Test-Path -LiteralPath $Path) { throw "Refusing to overwrite generated v4 source: $Path" }
    $parent = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $parent -PathType Container)) { throw "Parent directory is missing: $parent" }
    $stream = New-Object System.IO.FileStream($Path, [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
    try {
        $writer = New-Object System.IO.StreamWriter($stream, $utf8NoBom)
        try { $writer.Write($Text); $writer.Flush() } finally { $writer.Dispose() }
    } finally { $stream.Dispose() }
}

$cloneSpecs = @(
    [ordered]@{source='Research/Run-Gate10RProcessReuseBlockV3.ps1';target='Research/Run-Gate10RProcessReuseBlockV4.ps1';sha256='64b169024db23c1afd790178563c036481dec3d64d12cc0f4f9a7ce305c04a1c'},
    [ordered]@{source='Research/Run-Gate10RTelemetryProbeV3.ps1';target='Research/Run-Gate10RTelemetryProbeV4.ps1';sha256='7d555ba7eaf5ae94dd59c614e5d4f2785123fc4fd82b2fcf44f613fdc28d55f8'},
    [ordered]@{source='Research/Run-Gate10RColdReferenceV3.ps1';target='Research/Run-Gate10RColdReferenceV4.ps1';sha256='ad8385d32bdc7a539ca48a1734255d1e23cc40bc00cc5bdb5221e3df287a08d8'},
    [ordered]@{source='Research/Verification/Run-Gate10RUnitTestsV3.ps1';target='Research/Verification/Run-Gate10RUnitTestsV4.ps1';sha256='f2e3e50704f057f3e01b0580cd45f6e50e981f3073ef08c218f1c63e1bc289d2'},
    [ordered]@{source='Research/Verification/Run-Gate10RCompileV3.ps1';target='Research/Verification/Run-Gate10RCompileV4.ps1';sha256='86f8fb690c03a30556369ef0e16d6955bf68e64bf7bc2a6270bf9da5d7756686'},
    [ordered]@{source='Research/Verification/Run-Gate10RBlockVerificationV3.ps1';target='Research/Verification/Run-Gate10RBlockVerificationV4.ps1';sha256='c6e542c2a2e95a12356d7748499a2593b524cee5660c80de067ee0b30a6cd0a7'}
)

$nameMap = [ordered]@{
    'Run-Gate10RProcessReuseBlockV3.ps1' = 'Run-Gate10RProcessReuseBlockV4.ps1'
    'Run-Gate10RTelemetryProbeV3.ps1' = 'Run-Gate10RTelemetryProbeV4.ps1'
    'Run-Gate10RColdReferenceV3.ps1' = 'Run-Gate10RColdReferenceV4.ps1'
    'Run-Gate10RUnitTestsV3.ps1' = 'Run-Gate10RUnitTestsV4.ps1'
    'Run-Gate10RCompileV3.ps1' = 'Run-Gate10RCompileV4.ps1'
    'Run-Gate10RBlockVerificationV3.ps1' = 'Run-Gate10RBlockVerificationV4.ps1'
    'Run-Gate10RRetainedRegressionV3.ps1' = 'Run-Gate10RRetainedRegressionV4.ps1'
    'Run-Gate10RFinalAuditV3.ps1' = 'Run-Gate10RFinalAuditV4.ps1'
    'Run-Gate10RAttempt3PreflightV3.ps1' = 'Run-Gate10RAttempt4OfficialPreflightV4.ps1'
}

foreach ($spec in $cloneSpecs) {
    $sourcePath = Join-Path $ProjectPath ([string]$spec.source).Replace('/', '\')
    $targetPath = Join-Path $ProjectPath ([string]$spec.target).Replace('/', '\')
    if ((Get-LowerSha256 $sourcePath) -ne [string]$spec.sha256) { throw "Frozen v3 source hash mismatch: $($spec.source)" }
    $text = [System.IO.File]::ReadAllText($sourcePath)
    foreach ($oldName in $nameMap.Keys) {
        $newName = [string]$nameMap[$oldName]
        $text = $text.Replace($oldName, $newName)
        $text = $text.Replace($oldName.Substring(0, $oldName.Length - 4) + '|', $newName.Substring(0, $newName.Length - 4) + '|')
    }
    $text = $text.Replace('Gate10R_ProcessReuse_5pct\v3', 'Gate10R_ProcessReuse_5pct\v4')
    $text = $text.Replace('Gate10R_ProcessReuse_5pct/v3', 'Gate10R_ProcessReuse_5pct/v4')
    $text = $text.Replace('attempt-3', 'attempt-4').Replace('Attempt-3', 'Attempt-4')
    $text = $text.Replace('attempt 3', 'attempt 4').Replace('Attempt 3', 'Attempt 4')
    $text = $text.Replace('v3 fixture root', 'v4 fixture root').Replace('versioned Gate10R v3 verification root', 'versioned Gate10R v4 verification root')
    $text = $text.Replace('attempt3', 'attempt4').Replace('Attempt3', 'Attempt4')
    $text = $text.Replace('Gate10R_ProcessReuse_5pct_Attempt4_Config.v3.json', 'Gate10R_ProcessReuse_5pct_Attempt4_Config.v4.json')
    $text = $text.Replace('Gate10R_ProcessReuse_5pct_Attempt4_Provenance.v3.json', 'Gate10R_ProcessReuse_5pct_Attempt4_Provenance.v4.json')
    $text = $text.Replace('attempt4-v3', 'attempt4-v4').Replace('Attempt4-v3', 'Attempt4-v4')
    $text = $text.Replace('Attempt4_Preflight.summary.v3.json', 'Attempt4_Preflight.summary.v4.json')
    $text = $text.Replace('gate10r-preflight-checkpoint.v3.json', 'gate10r-preflight-checkpoint.v4.json')
    $text = $text.Replace('Gate10R_Attempt4_Execution_Receipt.v3.json', 'Gate10R_Attempt4_Execution_Receipt.v4.json')
    $text = $text.Replace('Gate10R_FinalAudit.summary.v3.json', 'Gate10R_FinalAudit.summary.v4.json')
    $text = $text.Replace('Gate10R_Evidence_Manifest.v3.json', 'Gate10R_Evidence_Manifest.v4.json')
    $text = $text.Replace('[int]$config.attempt -eq 3', '[int]$config.attempt -eq 4')
    $text = $text.TrimEnd("`r", "`n") + "`n"
    Write-NewText -Path $targetPath -Text $text
}

$frozenSourcePath = Join-Path $ProjectPath 'Research\Verification\Run-Gate12AnalysisUnitTests.ps1'
if ((Get-LowerSha256 $frozenSourcePath) -ne 'e56a3881c0fc9fc3ecceb760d1c51129e80ec2b306acdcfefed0a3814a6885b1') { throw 'Frozen retained-regression source hash mismatch.' }
$harness = [System.IO.File]::ReadAllText($frozenSourcePath)
$oldHeader = @'
[CmdletBinding()]
param(
    [string]$ProjectPath
)

$ErrorActionPreference = 'Stop'
$scriptDirectory = Split-Path -Parent $MyInvocation.MyCommand.Path
if ([string]::IsNullOrWhiteSpace($ProjectPath)) { $ProjectPath = [System.IO.Path]::GetFullPath((Join-Path $scriptDirectory '..\..')) }
else { $ProjectPath = [System.IO.Path]::GetFullPath($ProjectPath) }
'@
$newHeader = @'
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$ProjectPath,
    [Parameter(Mandatory = $true)][string]$SummaryPath,
    [switch]$BindingSmokeOnly
)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($ProjectPath) -or -not [System.IO.Path]::IsPathRooted($ProjectPath)) { throw 'Gate 10R attempt 4 retained harness requires an explicit absolute ProjectPath.' }
$ProjectPath = [System.IO.Path]::GetFullPath($ProjectPath)
if ([string]::IsNullOrWhiteSpace($SummaryPath) -or -not [System.IO.Path]::IsPathRooted($SummaryPath)) { throw 'Gate 10R attempt 4 retained harness requires an explicit absolute SummaryPath.' }
$resolvedSummaryPath = [System.IO.Path]::GetFullPath($SummaryPath)
$scriptDirectory = [System.IO.Path]::GetFullPath((Join-Path $ProjectPath 'Research\Verification'))
$originalSummaryPath = [System.IO.Path]::GetFullPath((Join-Path $scriptDirectory 'Gate12_AnalysisUnitTests.summary.json'))
if ([string]::Equals($resolvedSummaryPath, $originalSummaryPath, [System.StringComparison]::OrdinalIgnoreCase)) { throw 'The frozen original retained-regression summary is a prohibited output.' }
foreach ($protectedRelative in @('Gate10R_ProcessReuse_5pct\v1', 'Gate10R_ProcessReuse_5pct\v2', 'Gate10R_ProcessReuse_5pct\v3')) {
    $protectedRoot = [System.IO.Path]::GetFullPath((Join-Path $scriptDirectory $protectedRelative)).TrimEnd('\') + '\'
    if ($resolvedSummaryPath.StartsWith($protectedRoot, [System.StringComparison]::OrdinalIgnoreCase)) { throw 'Attempt 1-3 roots are prohibited retained-regression outputs.' }
}
$summaryParent = Split-Path -Parent $resolvedSummaryPath
if (-not (Test-Path -LiteralPath $summaryParent -PathType Container)) { throw 'The isolated retained-regression summary parent must already exist.' }
if ($BindingSmokeOnly) { Write-Output ('BINDING-SMOKE-PASSED|Gate10RAttempt4RetainedHarnessV4|' + $ProjectPath + '|' + $resolvedSummaryPath); exit 0 }
'@
if (-not $harness.StartsWith($oldHeader, [System.StringComparison]::Ordinal)) { throw 'Frozen retained-regression header no longer matches the mechanical transform anchor.' }
$harness = $newHeader + $harness.Substring($oldHeader.Length)
$oldSummaryLine = "$" + "summaryPath = Join-Path `$scriptDirectory 'Gate12_AnalysisUnitTests.summary.json'"
$newSummaryLine = "$" + "summaryPath = `$resolvedSummaryPath"
if (($harness.Split(@($oldSummaryLine), [System.StringSplitOptions]::None).Count - 1) -ne 1) { throw 'Frozen retained-regression summary-routing anchor is not unique.' }
$harness = $harness.Replace($oldSummaryLine, $newSummaryLine)
$harness = $harness.TrimEnd("`r", "`n") + "`n"
Write-NewText -Path (Join-Path $ProjectPath 'Research\Verification\Gate10RAttempt4RetainedHarnessV4.ps1') -Text $harness

$result = [ordered]@{
    schemaVersion = 1
    generator = 'New-Gate10RAttempt4SourcesV4.ps1'
    generatedAtUtc = [DateTime]::UtcNow.ToString('o')
    validationOnly = [bool]$ValidationOnly
    cloneCount = $cloneSpecs.Count
    harnessSourceSha256 = Get-LowerSha256 $frozenSourcePath
    generated = @($cloneSpecs | ForEach-Object { [ordered]@{relativePath=$_.target;sha256=Get-LowerSha256 (Join-Path $ProjectPath ([string]$_.target).Replace('/', '\'))} }) + @([ordered]@{relativePath='Research/Verification/Gate10RAttempt4RetainedHarnessV4.ps1';sha256=Get-LowerSha256 (Join-Path $ProjectPath 'Research\Verification\Gate10RAttempt4RetainedHarnessV4.ps1')})
}
$result | ConvertTo-Json -Depth 8
