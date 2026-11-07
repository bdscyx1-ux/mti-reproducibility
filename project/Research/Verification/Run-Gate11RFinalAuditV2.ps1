param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$ProjectPath,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$OutputPath
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$checks = New-Object 'Collections.Generic.List[object]'

function Add-Check([string]$Name, [bool]$Passed, [string]$Detail) {
    $checks.Add([pscustomobject][ordered]@{
        name = $Name
        passed = $Passed
        detail = $Detail
    })
}

function Get-LowerSha256([string]$Path) {
    return (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToLowerInvariant()
}

function Get-StringSha256([string]$Value) {
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [Text.Encoding]::UTF8.GetBytes($Value)
        return ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-', '').ToLowerInvariant()
    }
    finally { $sha.Dispose() }
}

function Get-CanonicalTree([string]$FullPath, [string]$RelativePath) {
    $root = [IO.Path]::GetFullPath($FullPath).TrimEnd('\')
    if (-not (Test-Path -LiteralPath $root -PathType Container)) {
        return [pscustomobject][ordered]@{ path = $RelativePath; exists = $false; fileCount = 0; rawBytes = 0L; ordinalTreeSha256 = '' }
    }
    $files = @(Get-ChildItem -LiteralPath $root -Recurse -File -Force)
    $rows = New-Object 'Collections.Generic.List[string]'
    foreach ($file in $files) {
        $relative = $file.FullName.Substring($root.Length).TrimStart('\').Replace('\', '/')
        $rows.Add("$relative`t$($file.Length)`t$(Get-LowerSha256 $file.FullName)")
    }
    $rows.Sort([StringComparer]::Ordinal)
    $sum = ($files | Measure-Object Length -Sum).Sum
    if ($null -eq $sum) { $sum = 0L }
    return [pscustomobject][ordered]@{
        path = $RelativePath
        exists = $true
        fileCount = $files.Count
        rawBytes = [long]$sum
        ordinalTreeSha256 = Get-StringSha256 ($rows -join "`n")
    }
}

function Get-ProjectFullPath([string]$Root, [string]$RelativePath) {
    return [IO.Path]::GetFullPath((Join-Path $Root $RelativePath.Replace('/', '\')))
}

function Test-ArrayExact([object[]]$Actual, [string[]]$Expected) {
    $actualRows = @($Actual)
    if ($actualRows.Count -ne $Expected.Count) { return $false }
    for ($index = 0; $index -lt $Expected.Count; $index++) {
        if ([string]$actualRows[$index] -cne $Expected[$index]) { return $false }
    }
    return $true
}

$projectRoot = [IO.Path]::GetFullPath($ProjectPath).TrimEnd('\')
$outputFullPath = [IO.Path]::GetFullPath($OutputPath)
if (-not $outputFullPath.StartsWith($projectRoot + '\', [StringComparison]::OrdinalIgnoreCase)) { throw 'Output path is outside the project root.' }
if (Test-Path -LiteralPath $outputFullPath) { throw 'Create-new final-audit output already exists.' }

$canonicalBaselinePath = Get-ProjectFullPath $projectRoot 'Research/Gate11R_Attempt2_Canonical_Preservation_Baseline.v2.json'
$canonicalBaseline = Get-Content -LiteralPath $canonicalBaselinePath -Raw | ConvertFrom-Json
$protectedTreeResults = New-Object 'Collections.Generic.List[object]'
foreach ($expected in @($canonicalBaseline.protectedTrees)) {
    $actual = Get-CanonicalTree (Get-ProjectFullPath $projectRoot ([string]$expected.path)) ([string]$expected.path)
    $protectedTreeResults.Add($actual)
    $passed = $actual.exists -and $actual.fileCount -eq [int]$expected.fileCount -and $actual.rawBytes -eq [long]$expected.rawBytes -and $actual.ordinalTreeSha256 -ceq [string]$expected.ordinalTreeSha256
    Add-Check ('protected-tree-' + [string]$expected.path) $passed ("$($actual.fileCount)/$($actual.rawBytes)/$($actual.ordinalTreeSha256)")
}

$prewritePath = Get-ProjectFullPath $projectRoot 'Research/Gate11R_PreWrite_Preservation_Audit.v1.json'
$prewrite = Get-Content -LiteralPath $prewritePath -Raw | ConvertFrom-Json
foreach ($expected in @($prewrite.protectedMaterial)) {
    $full = Get-ProjectFullPath $projectRoot ([string]$expected.path)
    $exists = Test-Path -LiteralPath $full -PathType Leaf
    $length = if ($exists) { (Get-Item -LiteralPath $full).Length } else { -1L }
    $hash = if ($exists) { Get-LowerSha256 $full } else { '' }
    Add-Check ('protected-material-' + [string]$expected.path) ($exists -and $length -eq [long]$expected.rawBytes -and $hash -ceq [string]$expected.sha256) ("$length/$hash")
}

$baselineCsvPath = Get-ProjectFullPath $projectRoot 'Research/Baseline_SHA256.csv'
$baselineRows = @(Import-Csv -LiteralPath $baselineCsvPath)
$materialRows = @($baselineRows | Where-Object { $_.kind -eq 'working_copy' -or $_.kind -eq 'external_archive' })
$archiveEntryRows = @($baselineRows | Where-Object { $_.kind -eq 'archive_entry' })
Add-Check 'baseline-material-cardinality' ($materialRows.Count -eq 24 -and $archiveEntryRows.Count -eq 2) ("material=$($materialRows.Count);archiveEntries=$($archiveEntryRows.Count)")
foreach ($row in $materialRows) {
    $full = Get-ProjectFullPath $projectRoot ([string]$row.path)
    $exists = Test-Path -LiteralPath $full -PathType Leaf
    $length = if ($exists) { (Get-Item -LiteralPath $full).Length } else { -1L }
    $hash = if ($exists) { Get-LowerSha256 $full } else { '' }
    Add-Check ('baseline-material-' + [string]$row.kind + '-' + [string]$row.path) ($exists -and $length -eq [long]$row.raw_bytes -and $hash -ceq [string]$row.sha256) ("$length/$hash")
}

$knownFiles = [ordered]@{
    'Research/Verification/Gate10R_ProcessReuse_5pct/v4/gate10r-checkpoint.json' = 'fab889a1ff9f2d7911a6018b9cd3316e4dbff6e1c8cd8523678488ef252cbf56'
    'Research/Verification/Gate10R_ProcessReuse_5pct/v4/Gate10R_FinalAudit.summary.v4.json' = '8714fea2235d488abad7278bd6ccef9cf50f75aae57969220f40a19de16dd72c'
    'Research/Verification/Gate11R_5pct_PreImplementation/v1/Gate11R_PreImplementation_Audit.summary.v1.json' = '282eaf0dc786e51946a12fb3a5a1c35cc177e6d8e90bb0ecdd011384f3b356fe'
    'Research/Verification/Gate11R_5pct_PreImplementation/v1/Gate11R_PreImplementation_Failure_Receipt.v1.json' = 'b376984203d8f9af29603ba1d6a55d5347537e914b1893f8d6b7aa6256ecc86c'
    'Research/Verification/Gate11R_5pct_PreImplementation/v1/Gate11R_PreImplementation_Failure.diagnostic.log' = '1bf5b1f9b9d4ab1c8a60b99c7e0512d25284c8222a9348fd11226fe92750db22'
    'Research/Verification/Gate11R_5pct_PreImplementation/v1/Gate11R_PreImplementation_Partial_Manifest.v1.json' = '2aa7036a810a3321fa491787c0773362a1cb591573b6a721d362db449d606682'
    'Research/Verification/Gate11R_5pct_PreImplementation/v1/gate11r-preimplementation-failure.checkpoint.v1.json' = 'ed4ecb461d2e7eb795c1a161193921c6f31f76a84d6f8c857735465b6fcb4274'
    'Research/Verification/Gate11R_5pct/v2/Gate11R_Generation.summary.v2.json' = '3df528c308032726379e99da1fdf21590106f18e683bc028fff2b585c85bab57'
    'Research/Verification/Gate11R_5pct/v2/Generation/generation-attempt1.Unity.log' = '3fcfbca8bb49194fa8134a47db9e69717b2e1908eba709572ceffcecc814a508'
    'Research/Verification/Gate11R_5pct/v2/Generation/GenerationAttempt1_Failure_Receipt.v2.1.json' = 'ce8ea34bb436863ac45ccd0c3278268aabfde0b074d84bf46e332cc736feb839'
    'Research/Verification/Gate11R_5pct/v2/Generation/GenerationAttempt1_Partial_Output_Manifest.v2.1.json' = '96e2adb60b2b6232cdef58a86a23762c2a8d150ef5c4462afdd5aaa9c0cdb197'
}
foreach ($entry in $knownFiles.GetEnumerator()) {
    $full = Get-ProjectFullPath $projectRoot ([string]$entry.Key)
    $exists = Test-Path -LiteralPath $full -PathType Leaf
    $hash = if ($exists) { Get-LowerSha256 $full } else { '' }
    Add-Check ('known-evidence-' + [string]$entry.Key) ($exists -and $hash -ceq [string]$entry.Value) $hash
}

$failedArchiveExpected = @(
    [pscustomobject]@{ path = 'Research/Verification/Gate11R_5pct/v2/Generation/FailedAttempt1/Research/FormalScenarios/Gate11R_5pct/v1'; files = 57; bytes = 125217970L; hash = '22ad55f19e0d22937c94f132dda6ed85f4c8263057feb8c1c568a1a30561333d' },
    [pscustomobject]@{ path = 'Research/Verification/Gate11R_5pct/v2/Generation/FailedAttempt1/Research/PlayableExperiments/Gate11R_5pct/v1'; files = 4; bytes = 427601L; hash = 'cbe943e1658323f8153dd567730716e2a78563d040b4c635e465d32d8919a2a2' },
    [pscustomobject]@{ path = 'Research/Verification/Gate11R_5pct/v2/Generation/FailedAttempt1/Assets/_Scenes/Research/Playable/Gate11R_5pct/.staging-v1-attempt2'; files = 680; bytes = 950685L; hash = 'f67183e3ae493906f75d0feaf3c6baebcf55ff0dda18394894e36e4de9ede437' }
)
foreach ($expected in $failedArchiveExpected) {
    $actual = Get-CanonicalTree (Get-ProjectFullPath $projectRoot $expected.path) $expected.path
    Add-Check ('failed-generation-archive-' + $expected.path) ($actual.exists -and $actual.fileCount -eq $expected.files -and $actual.rawBytes -eq $expected.bytes -and $actual.ordinalTreeSha256 -ceq $expected.hash) ("$($actual.fileCount)/$($actual.rawBytes)/$($actual.ordinalTreeSha256)")
}

$unitSummaryPath = Get-ProjectFullPath $projectRoot 'Research/Verification/Gate11R_5pct/v2/Gate11R_UnitTests.summary.v2.json'
$generationSummaryPath = Get-ProjectFullPath $projectRoot 'Research/Verification/Gate11R_5pct/v2/Gate11R_Generation.summary.v2.2.json'
$verificationSummaryPath = Get-ProjectFullPath $projectRoot 'Research/Verification/Gate11R_5pct/v2/Gate11R_Verification.summary.v2.json'
$unit = Get-Content -LiteralPath $unitSummaryPath -Raw | ConvertFrom-Json
$generation = Get-Content -LiteralPath $generationSummaryPath -Raw | ConvertFrom-Json
$verification = Get-Content -LiteralPath $verificationSummaryPath -Raw | ConvertFrom-Json
Add-Check 'unit-summary' ($unit.passed -and $unit.assertionCount -eq 1269 -and $unit.scenarioCount -eq 53 -and $unit.campaignCount -eq 74 -and $unit.presetCount -eq 212 -and -not $unit.pilotExecuted -and -not $unit.formalCampaignExecuted -and -not $unit.timingSamplesCollected) ("assertions=$($unit.assertionCount)")
Add-Check 'generation-summary' ($generation.passed -and $generation.mode -eq 'generate-retry2' -and $generation.assertionCount -eq 1544 -and $generation.scenarioCount -eq 53 -and $generation.campaignCount -eq 74 -and $generation.presetCount -eq 212 -and $generation.artifactCount -eq 744 -and -not $generation.pilotExecuted -and -not $generation.formalCampaignExecuted -and -not $generation.timingSamplesCollected) ("assertions=$($generation.assertionCount);artifacts=$($generation.artifactCount)")
Add-Check 'verification-summary' ($verification.passed -and $verification.assertionCount -eq 5893 -and $verification.scenarioCount -eq 53 -and $verification.campaignCount -eq 74 -and $verification.presetCount -eq 212 -and $verification.plannerInitializationCount -eq 212 -and $verification.artifactCount -eq 744 -and -not $verification.pilotExecuted -and -not $verification.formalCampaignExecuted -and -not $verification.timingSamplesCollected) ("assertions=$($verification.assertionCount);plannerInitializations=$($verification.plannerInitializationCount)")
Add-Check 'summary-manifest-identity' ($generation.manifestSha256 -ceq $verification.manifestSha256 -and $generation.coverageGraphSha256 -ceq $verification.coverageGraphSha256) ("manifest=$($verification.manifestSha256);coverage=$($verification.coverageGraphSha256)")

$scenarioRootRelative = 'Research/FormalScenarios/Gate11R_5pct/v1'
$catalogRootRelative = 'Research/PlayableExperiments/Gate11R_5pct/v1'
$assetRootRelative = 'Assets/_Scenes/Research/Playable/Gate11R_5pct/v1'
$scenarioRoot = Get-ProjectFullPath $projectRoot $scenarioRootRelative
$catalogRoot = Get-ProjectFullPath $projectRoot $catalogRootRelative
$assetRoot = Get-ProjectFullPath $projectRoot $assetRootRelative
$outputRootTrees = @(
    Get-CanonicalTree $scenarioRoot $scenarioRootRelative
    Get-CanonicalTree $catalogRoot $catalogRootRelative
    Get-CanonicalTree $assetRoot $assetRootRelative
)
Add-Check 'production-root-file-counts' ($outputRootTrees[0].fileCount -eq 57 -and $outputRootTrees[1].fileCount -eq 4 -and $outputRootTrees[2].fileCount -eq 684) ("$($outputRootTrees[0].fileCount)/$($outputRootTrees[1].fileCount)/$($outputRootTrees[2].fileCount)")

$manifestPath = Join-Path $scenarioRoot 'bundle-manifest.json'
$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
$manifestHash = Get-LowerSha256 $manifestPath
Add-Check 'bundle-manifest-sha256' ($manifestHash -ceq '5baaeec18344a9e99e55da38f3c4875b7e7e9f3bf0add9d5f2d2f1e821b5f7fc' -and $manifestHash -ceq [string]$verification.manifestSha256) $manifestHash
Add-Check 'bundle-manifest-contract' ($manifest.manifestId -eq 'gate11r-scenario-playable-bundle-manifest-v1' -and $manifest.executionDesignId -eq 'gate10r-one-fresh-unity-process-per-williams-block-5pct-v1' -and $manifest.precisionPolicyId -eq 'two-sided-95pct-ci-relative-half-width-5pct-uncapped-v1' -and $manifest.scenarioCount -eq 53 -and $manifest.campaignCount -eq 74 -and $manifest.eligibilityCount -eq 212 -and $manifest.sceneCount -eq 53 -and $manifest.profileCount -eq 74 -and $manifest.presetCount -eq 212 -and $manifest.visualizationOnly -and -not $manifest.timingEvidenceAllowed -and -not $manifest.pilotExecuted -and -not $manifest.formalCampaignExecuted) '53/74/212;visualization-only;timing-disabled'

$artifactMismatches = New-Object 'Collections.Generic.List[string]'
$artifactRows = New-Object 'Collections.Generic.List[string]'
$artifactPaths = New-Object 'Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
foreach ($artifact in @($manifest.artifacts)) {
    $relative = [string]$artifact.relativePath
    if (-not $artifactPaths.Add($relative)) { $artifactMismatches.Add('duplicate:' + $relative) }
    $full = Get-ProjectFullPath $projectRoot $relative
    if (-not $full.StartsWith($projectRoot + '\', [StringComparison]::OrdinalIgnoreCase)) { $artifactMismatches.Add('escape:' + $relative); continue }
    if (-not (Test-Path -LiteralPath $full -PathType Leaf)) { $artifactMismatches.Add('missing:' + $relative); continue }
    $item = Get-Item -LiteralPath $full
    $hash = Get-LowerSha256 $full
    if ($item.Length -ne [long]$artifact.rawBytes) { $artifactMismatches.Add('bytes:' + $relative) }
    if ($hash -cne [string]$artifact.sha256) { $artifactMismatches.Add('sha256:' + $relative) }
    $artifactRows.Add("$relative`t$($artifact.rawBytes)`t$($artifact.sha256)")
}
$artifactRows.Sort([StringComparer]::Ordinal)
$aggregateText = if ($artifactRows.Count -gt 0) { ($artifactRows -join "`n") + "`n" } else { '' }
$aggregateHash = Get-StringSha256 $aggregateText
Add-Check 'manifest-artifact-live-bytes' (@($manifest.artifacts).Count -eq 744 -and $artifactMismatches.Count -eq 0) ("artifacts=$(@($manifest.artifacts).Count);mismatches=$($artifactMismatches.Count)")
Add-Check 'manifest-artifact-aggregate' ($aggregateHash -ceq [string]$manifest.artifactAggregateSha256) $aggregateHash

$liveProductionPaths = New-Object 'Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
foreach ($rootPair in @(@($scenarioRoot, $scenarioRootRelative), @($catalogRoot, $catalogRootRelative), @($assetRoot, $assetRootRelative))) {
    $fullRoot = ([string]$rootPair[0]).TrimEnd('\')
    foreach ($file in @(Get-ChildItem -LiteralPath $fullRoot -Recurse -File -Force)) {
        $relative = [string]$rootPair[1] + '/' + $file.FullName.Substring($fullRoot.Length).TrimStart('\').Replace('\', '/')
        [void]$liveProductionPaths.Add($relative)
    }
}
$extraPaths = @($liveProductionPaths | Where-Object { -not $artifactPaths.Contains($_) })
$missingPaths = @($artifactPaths | Where-Object { -not $liveProductionPaths.Contains($_) })
Add-Check 'manifest-production-file-set' ($liveProductionPaths.Count -eq 745 -and $missingPaths.Count -eq 0 -and $extraPaths.Count -eq 1 -and $extraPaths[0] -ceq ($scenarioRootRelative + '/bundle-manifest.json')) ("live=$($liveProductionPaths.Count);missing=$($missingPaths.Count);extra=$($extraPaths -join ',')")

$reparsePoints = @()
foreach ($root in @($scenarioRoot, $catalogRoot, $assetRoot)) {
    $reparsePoints += @(Get-ChildItem -LiteralPath $root -Recurse -Force | Where-Object { ($_.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 })
}
Add-Check 'production-roots-no-reparse-points' ($reparsePoints.Count -eq 0) ("count=$($reparsePoints.Count)")

$matrix = Get-Content -LiteralPath (Join-Path $scenarioRoot 'formal-scenario-matrix.json') -Raw | ConvertFrom-Json
$preregistration = Get-Content -LiteralPath (Join-Path $scenarioRoot 'preregistered-analysis.json') -Raw | ConvertFrom-Json
$campaignCatalog = Get-Content -LiteralPath (Join-Path $catalogRoot 'campaign-profile-catalog.json') -Raw | ConvertFrom-Json
$presetCatalog = Get-Content -LiteralPath (Join-Path $catalogRoot 'algorithm-preset-catalog.json') -Raw | ConvertFrom-Json
$sceneCatalog = Get-Content -LiteralPath (Join-Path $catalogRoot 'playable-scene-catalog.json') -Raw | ConvertFrom-Json
$coverage = Get-Content -LiteralPath (Join-Path $catalogRoot 'coverage-manifest.json') -Raw | ConvertFrom-Json

$sharedScenarios = @($matrix.scenarios | Where-Object { $_.goalStructureId -eq 'shared-single-v1' })
$heterogeneousScenarios = @($matrix.scenarios | Where-Object { $_.goalStructureId -eq 'heterogeneous-v1' })
Add-Check 'matrix-counts-and-goal-cohorts' ($matrix.scenarioCount -eq 53 -and @($matrix.scenarios).Count -eq 53 -and $sharedScenarios.Count -eq 32 -and $heterogeneousScenarios.Count -eq 21 -and $matrix.campaignCount -eq 74 -and @($matrix.campaigns).Count -eq 74 -and $matrix.eligibilityCount -eq 212 -and @($matrix.eligibilityEntries).Count -eq 212) '53=32+21;campaigns=74;eligibility=212'
$scenarioIds = @($matrix.scenarios | ForEach-Object { [string]$_.scenarioId })
Add-Check 'matrix-scenario-identities-unique' (@($scenarioIds | Select-Object -Unique).Count -eq 53) 'unique=53'

$cohortGroups = @($campaignCatalog.campaigns | Group-Object comparisonCohortId)
$cohortCounts = @{}
foreach ($group in $cohortGroups) { $cohortCounts[$group.Name] = $group.Count }
Add-Check 'campaign-cohort-counts' ($campaignCatalog.campaignCount -eq 74 -and @($campaignCatalog.campaigns).Count -eq 74 -and $cohortCounts['four-algorithm-shared-goal-v1'] -eq 32 -and $cohortCounts['per-agent-heterogeneous-goal-v1'] -eq 21 -and $cohortCounts['grouped-field-heterogeneous-goal-v1'] -eq 21) 'shared=32;per-agent=21;grouped-field=21'

$williamsMismatch = 0
$sharedRows = @(@('A*-R','D*L','IDFF','C-FF'), @('D*L','C-FF','A*-R','IDFF'), @('C-FF','IDFF','D*L','A*-R'), @('IDFF','A*-R','C-FF','D*L'))
$perAgentRows = @(@('A*-R','D*L'), @('D*L','A*-R'))
$groupedRows = @(@('C-FF','IDFF'), @('IDFF','C-FF'))
foreach ($campaign in @($campaignCatalog.campaigns)) {
    if ($campaign.comparisonCohortId -eq 'four-algorithm-shared-goal-v1') { $expectedRows = $sharedRows; $expectedEligible = @('A*-R','D*L','IDFF','C-FF') }
    elseif ($campaign.comparisonCohortId -eq 'per-agent-heterogeneous-goal-v1') { $expectedRows = $perAgentRows; $expectedEligible = @('A*-R','D*L') }
    elseif ($campaign.comparisonCohortId -eq 'grouped-field-heterogeneous-goal-v1') { $expectedRows = $groupedRows; $expectedEligible = @('C-FF','IDFF') }
    else { $williamsMismatch++; continue }
    if (-not (Test-ArrayExact @($campaign.eligibleAlgorithmIds) $expectedEligible)) { $williamsMismatch++ }
    if (@($campaign.williamsRows).Count -ne $expectedRows.Count) { $williamsMismatch++; continue }
    for ($rowIndex = 0; $rowIndex -lt $expectedRows.Count; $rowIndex++) {
        if ([int]$campaign.williamsRows[$rowIndex].rowIndex -ne $rowIndex -or -not (Test-ArrayExact @($campaign.williamsRows[$rowIndex].algorithms) $expectedRows[$rowIndex])) { $williamsMismatch++ }
    }
}
Add-Check 'williams-mapping-exact' ($williamsMismatch -eq 0) ("mismatches=$williamsMismatch")

$algorithmGroups = @($presetCatalog.presets | Group-Object algorithmId)
$algorithmCounts = @{}
foreach ($group in $algorithmGroups) { $algorithmCounts[$group.Name] = $group.Count }
Add-Check 'algorithm-preset-balance' ($presetCatalog.presetCount -eq 212 -and @($presetCatalog.presets).Count -eq 212 -and $algorithmCounts['A*-R'] -eq 53 -and $algorithmCounts['D*L'] -eq 53 -and $algorithmCounts['C-FF'] -eq 53 -and $algorithmCounts['IDFF'] -eq 53) 'A*-R=53;D*L=53;C-FF=53;IDFF=53'

$expectedLogTarget = 0.048790164169432
Add-Check 'precision-and-sample-size-policy' ($preregistration.precisionPolicyId -eq 'two-sided-95pct-ci-relative-half-width-5pct-uncapped-v1' -and [Math]::Abs([double]$preregistration.logRelativeHalfWidthTarget - $expectedLogTarget) -le 1e-15 -and $preregistration.minimumBlocks -eq 32 -and $preregistration.blockMultiple -eq 4 -and -not $preregistration.hardCapEnabled) ("logTarget=$($preregistration.logRelativeHalfWidthTarget);minimum=$($preregistration.minimumBlocks);multiple=$($preregistration.blockMultiple);cap=$($preregistration.hardCapEnabled)")
Add-Check 'preregistration-table-and-anchor-counts' (@($preregistration.primaryAnalysisIds).Count -eq 4 -and @($preregistration.secondaryAnalysisIds).Count -eq 5 -and @($preregistration.pilotCampaignAnchors).Count -eq 12 -and @($preregistration.exclusionRules).Count -eq 4 -and @($preregistration.forbiddenExclusions).Count -eq 6 -and -not $preregistration.pilotExecuted -and -not $preregistration.formalCampaignExecuted) 'primary=4;secondary=5;anchors=12;allowed=4;forbidden=6'

$watermark = 'VISUALIZATION REPLAY ' + [char]0x2014 + ' NOT A TIMING RUN'
Add-Check 'playable-catalog-contract' ($sceneCatalog.sceneCount -eq 53 -and @($sceneCatalog.scenes).Count -eq 53 -and $sceneCatalog.directionGlyphId -eq 'research-visual-direction-glyph-v1' -and $sceneCatalog.captureLayoutId -eq 'gate11r-fixed-capture-layout-16x9-v1' -and $sceneCatalog.watermark -ceq $watermark -and $coverage.visualizationOnly -and -not $coverage.timingEvidenceAllowed -and -not $coverage.pilotExecuted -and -not $coverage.formalCampaignExecuted) 'scenes=53;glyph/capture/watermark exact;timing disabled'
Add-Check 'coverage-graph-identity' ($coverage.scenarioCount -eq 53 -and $coverage.campaignCount -eq 74 -and $coverage.presetCount -eq 212 -and $coverage.coverageGraphSha256 -ceq [string]$verification.coverageGraphSha256) ([string]$coverage.coverageGraphSha256)

$scenarioJsonCount = @(Get-ChildItem -LiteralPath (Join-Path $scenarioRoot 'Scenarios') -File -Filter '*.scenario.json').Count
$scenarioSceneCount = @(Get-ChildItem -LiteralPath (Join-Path $assetRoot 'Scenarios') -File -Filter '*.unity').Count
$launcherSceneCount = @(Get-ChildItem -LiteralPath (Join-Path $assetRoot 'Launcher') -File -Filter '*.unity').Count
$profileAssetCount = @(Get-ChildItem -LiteralPath (Join-Path $assetRoot 'CampaignProfiles') -File -Filter '*.asset').Count
$presetAssetCount = @(Get-ChildItem -LiteralPath (Join-Path $assetRoot 'AlgorithmPresets') -File -Filter '*.asset').Count
Add-Check 'physical-bundle-cardinality' ($scenarioJsonCount -eq 53 -and $scenarioSceneCount -eq 53 -and $launcherSceneCount -eq 1 -and $profileAssetCount -eq 74 -and $presetAssetCount -eq 212) ("scenarioJson=$scenarioJsonCount;scenarioScenes=$scenarioSceneCount;launcher=$launcherSceneCount;profiles=$profileAssetCount;presets=$presetAssetCount")

$forbiddenRoots = @(
    'Research/Verification/Gate11R_5pct/v1',
    'Research/FormalScenarios/Gate11R_5pct/.staging-v1-attempt2',
    'Research/PlayableExperiments/Gate11R_5pct/.staging-v1-attempt2',
    'Assets/_Scenes/Research/Playable/Gate11R_5pct/.staging-v1-attempt2',
    'Assets/_Scenes/Research/Playable/Gate11R_5pct/_staging-v1-attempt2-retry2',
    'Research/PilotRuns/Gate12R_ProcessReuse_5pct/v1',
    'Research/FormalRuns/Gate13R_ProcessReuse_5pct/v1'
)
foreach ($relative in $forbiddenRoots) {
    Add-Check ('forbidden-root-absent-' + $relative) (-not (Test-Path -LiteralPath (Get-ProjectFullPath $projectRoot $relative))) 'absent-required'
}

$unityCount = @(Get-Process Unity -ErrorAction SilentlyContinue).Count
$crashCount = @(Get-Process UnityCrashHandler64 -ErrorAction SilentlyContinue).Count
$lockPresent = Test-Path -LiteralPath (Join-Path $projectRoot 'Temp\UnityLockfile')
Add-Check 'runtime-clean' ($unityCount -eq 0 -and $crashCount -eq 0 -and -not $lockPresent) ("Unity=$unityCount;CrashHandler=$crashCount;lock=$lockPresent")

$failedChecks = @($checks | Where-Object { -not $_.passed })
$status = if ($failedChecks.Count -eq 0) { 'GATE11R-PASSED-WAITING-FOR-GATE12R-AUTHORIZATION' } else { 'GATE11R-FAILED-AUTO-REPAIR-REQUIRED' }
$summary = [pscustomobject][ordered]@{
    schemaVersion = 2
    summaryKind = 'gate11r-final-audit-v2'
    savedAtUtc = [DateTime]::UtcNow.ToString('o')
    status = $status
    assertionCount = $checks.Count
    passedCount = $checks.Count - $failedChecks.Count
    failedCount = $failedChecks.Count
    checks = $checks.ToArray()
    protectedTreeCount = @($canonicalBaseline.protectedTrees).Count
    protectedMaterialCount = @($prewrite.protectedMaterial).Count
    frozenBaselineMaterialCount = $materialRows.Count
    manifestArtifactCount = @($manifest.artifacts).Count
    manifestArtifactMismatchCount = $artifactMismatches.Count
    bundleManifestSha256 = $manifestHash
    coverageGraphSha256 = [string]$coverage.coverageGraphSha256
    outputRoots = $outputRootTrees
    gate12RAuthorized = $false
    gate12RStarted = $false
    gate13RAuthorized = $false
    gate13RStarted = $false
    pilotExecuted = $false
    formalCampaignExecuted = $false
    timingSamplesCollected = $false
    passed = ($failedChecks.Count -eq 0)
}

$outputDirectory = Split-Path -Parent $outputFullPath
if (-not (Test-Path -LiteralPath $outputDirectory -PathType Container)) { New-Item -ItemType Directory -Force -Path $outputDirectory | Out-Null }
$temporaryPath = $outputFullPath + '.tmp-' + [Guid]::NewGuid().ToString('N')
$encoding = New-Object Text.UTF8Encoding($false)
try {
    [IO.File]::WriteAllText($temporaryPath, ($summary | ConvertTo-Json -Depth 10), $encoding)
    [IO.File]::Move($temporaryPath, $outputFullPath)
}
finally {
    if (Test-Path -LiteralPath $temporaryPath) { Remove-Item -LiteralPath $temporaryPath -Force }
}

$summary | ConvertTo-Json -Depth 4 -Compress
if ($failedChecks.Count -ne 0) { exit 1 }
