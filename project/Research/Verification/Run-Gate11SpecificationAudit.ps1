[CmdletBinding()]
param(
    [string]$ProjectPath
)

$ErrorActionPreference = 'Stop'
$scriptDirectory = Split-Path -Parent $MyInvocation.MyCommand.Path
if ([string]::IsNullOrWhiteSpace($ProjectPath)) { $ProjectPath = [System.IO.Path]::GetFullPath((Join-Path $scriptDirectory '..\..')) }
else { $ProjectPath = [System.IO.Path]::GetFullPath($ProjectPath) }

$summaryPath = Join-Path $scriptDirectory 'Gate11_SpecificationAudit.summary.json'
$specificationPath = Join-Path $ProjectPath 'Research\Formal_Scenario_Matrix_and_Preregistration_Specification.md'
$testDesignPath = Join-Path $ProjectPath 'Research\Gate11_Formal_Scenario_Matrix_Test_Design.md'
$expectedSpecificationHash = '498d3ea8549b234ebaac27658ee9be1ad67051f49e71e131e5b013287f28f4f4'
$expectedTestDesignHash = 'bfb124d8ecf80ef15e8fcf391b4f0b51ee1b27b8a03303afa1b12a1062304b58'

function Get-LowerSha256([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

$specification = if (Test-Path -LiteralPath $specificationPath -PathType Leaf) { Get-Content -LiteralPath $specificationPath -Raw -Encoding UTF8 } else { '' }
$testDesign = if (Test-Path -LiteralPath $testDesignPath -PathType Leaf) { Get-Content -LiteralPath $testDesignPath -Raw -Encoding UTF8 } else { '' }
$specificationHash = Get-LowerSha256 $specificationPath
$testDesignHash = Get-LowerSha256 $testDesignPath

$requiredSpecificationTokens = @(
    'formal-scenario-matrix-v1',
    'ddm-formal-scenario-generator-v1',
    'ddm-planning-preregistration-v1',
    'Material Passport',
    '53 unique canonical scenario files',
    '212 eligible algorithm',
    '110011/110012',
    'mixed-five-event-four-phase-v1',
    'temporary-disconnect-restore-v1',
    'P1-DL-vs-A-shared',
    'P4-IDFF-vs-CFF-grouped',
    'n_formal = next multiple of 4',
    'pilotExecuted = false',
    'formalCampaignExecuted = false',
    'edits to original scripts/scenes'
)
$requiredTestTokens = @(
    'Specification audit before implementation',
    'Generator unit and determinism tests',
    'Create-new generation tests',
    'Strict I/O and canonical identity tests',
    'Matrix and parameter coverage tests',
    'Cohort, provenance, and planner initialization tests',
    'Independent reachability tests',
    'Preregistration config tests',
    'Tamper and negative tests',
    'Regression and final audit'
)
$missingSpecificationTokens = @($requiredSpecificationTokens | Where-Object { $specification.IndexOf($_, [System.StringComparison]::Ordinal) -lt 0 })
$missingTestDesignTokens = @($requiredTestTokens | Where-Object { $testDesign.IndexOf($_, [System.StringComparison]::Ordinal) -lt 0 })

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
        $baselineMismatches += [ordered]@{ relativePath = $row.relative_path; exists = $exists; expectedBytes = [int64]$row.bytes; actualBytes = $actualBytes; expectedSha256 = $row.sha256; actualSha256 = $actualHash }
    }
}

$powerShellFiles = @(Get-ChildItem -LiteralPath (Join-Path $ProjectPath 'Research') -Filter '*.ps1' -File -Recurse | Sort-Object FullName)
$powerShellParseErrors = @()
foreach ($file in $powerShellFiles) {
    $tokens = $null
    $parseErrors = $null
    [System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$parseErrors) | Out-Null
    foreach ($parseError in @($parseErrors)) { $powerShellParseErrors += [ordered]@{ file = $file.FullName; message = $parseError.Message; extent = $parseError.Extent.Text } }
}

$productionPaths = @(
    (Join-Path $ProjectPath 'Assets\_Scripts\Research\Scenarios\FormalScenarioMatrixGenerator.cs'),
    (Join-Path $ProjectPath 'Assets\_Scripts\Research\Editor\Gate11FormalScenarioMatrixCommand.cs'),
    (Join-Path $scriptDirectory 'Run-Gate11ScenarioMatrixGeneration.ps1'),
    (Join-Path $scriptDirectory 'Run-Gate11ScenarioMatrixVerification.ps1'),
    (Join-Path $ProjectPath 'Research\FormalScenarios\v1\bundle-manifest.json')
)
$existingProductionPaths = @($productionPaths | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf })
$preImplementationBoundaryClean = $existingProductionPaths.Count -eq 0
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
    frozenHashesMatch = $specificationHash -eq $expectedSpecificationHash -and $testDesignHash -eq $expectedTestDesignHash
    specificationTokensComplete = $missingSpecificationTokens.Count -eq 0
    testDesignTokensComplete = $missingTestDesignTokens.Count -eq 0
    noDraftPlaceholders = $specification -notmatch '(?i)\b(TODO|TBD|FIXME)\b' -and $testDesign -notmatch '(?i)\b(TODO|TBD|FIXME)\b'
    frozenBaselineMatches = $baselineChecked -eq 24 -and $baselineMismatches.Count -eq 0
    powerShellParses = $powerShellParseErrors.Count -eq 0
    specificationsFrozenBeforeProduction = $frozenBeforeProduction
}
$failedChecks = @($checks.GetEnumerator() | Where-Object { -not $_.Value } | ForEach-Object { $_.Key })
$passed = $failedChecks.Count -eq 0
$summary = [ordered]@{
    savedAt = (Get-Date).ToString('o')
    auditMode = $auditMode
    specificationPath = $specificationPath
    specificationSha256 = $specificationHash
    testDesignPath = $testDesignPath
    testDesignSha256 = $testDesignHash
    latestFrozenSpecificationWriteTimeUtc = $latestFrozenWriteTimeUtc.ToString('o')
    productionPaths = $productionPaths
    existingProductionPaths = $existingProductionPaths
    productionCreationTimesUtc = @($productionCreationTimesUtc | ForEach-Object { $_.ToString('o') })
    missingSpecificationTokens = $missingSpecificationTokens
    missingTestDesignTokens = $missingTestDesignTokens
    baselineChecked = $baselineChecked
    baselineMismatches = $baselineMismatches
    powerShellScriptCount = $powerShellFiles.Count
    powerShellParseErrors = $powerShellParseErrors
    checks = $checks
    failedChecks = $failedChecks
    passed = $passed
}
$summary | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $summaryPath -Encoding UTF8
$summary | ConvertTo-Json -Depth 10
if (-not $passed) { Write-Error "Gate 11 specification audit failed. Review $summaryPath."; exit 1 }
Write-Host "Gate 11 specification audit passed ($auditMode)." -ForegroundColor Green
exit 0
