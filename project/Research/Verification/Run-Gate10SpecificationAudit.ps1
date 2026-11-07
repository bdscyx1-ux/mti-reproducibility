[CmdletBinding()]
param(
    [string]$ProjectPath
)

$ErrorActionPreference = 'Stop'
$scriptDirectory = Split-Path -Parent $MyInvocation.MyCommand.Path
if ([string]::IsNullOrWhiteSpace($ProjectPath)) {
    $ProjectPath = [System.IO.Path]::GetFullPath((Join-Path $scriptDirectory '..\..'))
} else {
    $ProjectPath = [System.IO.Path]::GetFullPath($ProjectPath)
}
$summaryPath = Join-Path $scriptDirectory 'Gate10_SpecificationAudit.summary.json'
$specificationPath = Join-Path $ProjectPath 'Research\Four_Algorithm_Fairness_and_Unified_Campaign_Specification.md'
$testDesignPath = Join-Path $ProjectPath 'Research\Gate10_Fairness_Test_Design.md'

function Get-LowerSha256([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

$specification = if (Test-Path -LiteralPath $specificationPath -PathType Leaf) { Get-Content -Raw -LiteralPath $specificationPath -Encoding UTF8 } else { '' }
$testDesign = if (Test-Path -LiteralPath $testDesignPath -PathType Leaf) { Get-Content -Raw -LiteralPath $testDesignPath -Encoding UTF8 } else { '' }
$requiredSpecTokens = @(
    'four-algorithm-fairness-v1',
    'four-algorithm-shared-goal-v1',
    'per-agent-heterogeneous-goal-v1',
    'grouped-field-heterogeneous-goal-v1',
    'dynamic phase elapsed',
    'fairnessSchemaVersion = 1',
    'processedWorkUnit',
    'Williams design',
    'every ordered pair of distinct algorithms occurs exactly once',
    'one algorithm, one scenario fingerprint/source hash',
    'Gate 13 alone may execute the formal campaign',
    'Do not modify any original script or original scene'
)
$requiredTestTokens = @(
    'Specification audit before implementation',
    'Runtime profile and cohort tests',
    'Workload accounting tests',
    'Provenance and batch tests',
    'Identity rejection tests',
    'Balanced scheduler tests',
    '16 independent Unity child processes',
    'Regression and final audit'
)
$missingSpecTokens = @($requiredSpecTokens | Where-Object { $specification.IndexOf($_, [System.StringComparison]::Ordinal) -lt 0 })
$missingTestTokens = @($requiredTestTokens | Where-Object { $testDesign.IndexOf($_, [System.StringComparison]::Ordinal) -lt 0 })

$baselineRows = Import-Csv -LiteralPath (Join-Path $ProjectPath 'Research\Baseline_SHA256.csv')
$baselineMismatches = @()
$baselineChecked = 0
foreach ($row in $baselineRows | Where-Object { $_.scope -in @('external_archive', 'working_copy') }) {
    $baselineChecked++
    $path = [System.IO.Path]::GetFullPath((Join-Path $ProjectPath $row.relative_path))
    $exists = Test-Path -LiteralPath $path -PathType Leaf
    $actualBytes = if ($exists) { (Get-Item -LiteralPath $path).Length } else { $null }
    $actualHash = if ($exists) { Get-LowerSha256 $path } else { $null }
    if (-not $exists -or $actualBytes -ne [int64]$row.bytes -or $actualHash -ne $row.sha256) {
        $baselineMismatches += $row.relative_path
    }
}

$powerShellParseErrors = @()
$powerShellFiles = @(Get-ChildItem -LiteralPath (Join-Path $ProjectPath 'Research') -Filter '*.ps1' -File -Recurse)
foreach ($file in $powerShellFiles) {
    $tokens = $null
    $errors = $null
    [System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$errors) | Out-Null
    foreach ($error in @($errors)) { $powerShellParseErrors += "{0}: {1}" -f $file.FullName, $error.Message }
}

$productionPaths = @(
    (Join-Path $ProjectPath 'Assets\_Scripts\Research\Experiments\PlanningFairnessContracts.cs'),
    (Join-Path $ProjectPath 'Assets\_Scripts\Research\Editor\Gate10FairnessVerification.cs'),
    (Join-Path $ProjectPath 'Research\Run-FairPlanningCampaign.ps1')
)
$existingProductionPaths = @($productionPaths | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf })
$preImplementationBoundaryClean = $existingProductionPaths.Count -eq 0
$specificationHash = Get-LowerSha256 $specificationPath
$testDesignHash = Get-LowerSha256 $testDesignPath
$expectedSpecificationHash = '42a4a8439c3d7b46b7644bed14b8f91d87bae4c6f8b2183a73609ee5461e82dd'
$expectedTestDesignHash = '6ab9b5b47783f727a48d55a9dc3b8ef3a360438da874e6233aa2f0af4d646d38'
$latestFrozenWriteTimeUtc = @((Get-Item -LiteralPath $specificationPath).LastWriteTimeUtc, (Get-Item -LiteralPath $testDesignPath).LastWriteTimeUtc) | Sort-Object -Descending | Select-Object -First 1
$productionCreationTimesUtc = @($existingProductionPaths | ForEach-Object { (Get-Item -LiteralPath $_).CreationTimeUtc })
$frozenBeforeProduction = (
    $specificationHash -eq $expectedSpecificationHash -and
    $testDesignHash -eq $expectedTestDesignHash -and
    ($preImplementationBoundaryClean -or @($productionCreationTimesUtc | Where-Object { $_ -le $latestFrozenWriteTimeUtc }).Count -eq 0)
)
$auditMode = if ($preImplementationBoundaryClean) { 'pre-implementation-boundary' } else { 'post-implementation-frozen-integrity' }
$checks = [ordered]@{
    specificationPresent = Test-Path -LiteralPath $specificationPath -PathType Leaf
    testDesignPresent = Test-Path -LiteralPath $testDesignPath -PathType Leaf
    specificationTokensComplete = $missingSpecTokens.Count -eq 0
    testDesignTokensComplete = $missingTestTokens.Count -eq 0
    noDraftPlaceholders = $specification -notmatch '(?i)\b(TODO|TBD|FIXME)\b' -and $testDesign -notmatch '(?i)\b(TODO|TBD|FIXME)\b'
    frozenBaselineMatches = $baselineChecked -eq 24 -and $baselineMismatches.Count -eq 0
    powerShellParses = $powerShellParseErrors.Count -eq 0
    specificationsFrozenBeforeProduction = $frozenBeforeProduction
}
$failedChecks = @($checks.GetEnumerator() | Where-Object { -not $_.Value } | ForEach-Object Key)
$summary = [ordered]@{
    savedAt = (Get-Date).ToString('o')
    specificationPath = $specificationPath
    specificationSha256 = $specificationHash
    testDesignPath = $testDesignPath
    testDesignSha256 = $testDesignHash
    missingSpecificationTokens = $missingSpecTokens
    missingTestDesignTokens = $missingTestTokens
    baselineChecked = $baselineChecked
    baselineMismatches = $baselineMismatches
    powerShellScriptCount = $powerShellFiles.Count
    powerShellParseErrors = $powerShellParseErrors
    auditMode = $auditMode
    latestFrozenSpecificationWriteTimeUtc = $latestFrozenWriteTimeUtc.ToString('o')
    productionPaths = $productionPaths
    existingProductionPaths = $existingProductionPaths
    productionCreationTimesUtc = @($productionCreationTimesUtc | ForEach-Object { $_.ToString('o') })
    checks = $checks
    failedChecks = $failedChecks
    passed = $failedChecks.Count -eq 0
}
$summary | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $summaryPath -Encoding UTF8
$summary | ConvertTo-Json -Depth 8
if (-not $summary.passed) { Write-Error "Gate 10 specification audit failed. Review $summaryPath."; exit 1 }
Write-Host "Gate 10 specification audit passed ($auditMode)." -ForegroundColor Green
exit 0
