[CmdletBinding()]
param(
    [string]$ProjectPath
)

$ErrorActionPreference = 'Stop'
$scriptDirectory = Split-Path -Parent $MyInvocation.MyCommand.Path
if ([string]::IsNullOrWhiteSpace($ProjectPath)) { $ProjectPath = [System.IO.Path]::GetFullPath((Join-Path $scriptDirectory '..\..')) }
else { $ProjectPath = [System.IO.Path]::GetFullPath($ProjectPath) }
$summaryPath = Join-Path $scriptDirectory 'Gate10_FinalAudit.summary.json'

function Get-LowerSha256([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

# Frozen-original preservation.
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

# All retained executable evidence must remain syntactically readable.
$powerShellFiles = @(Get-ChildItem -LiteralPath (Join-Path $ProjectPath 'Research') -Filter '*.ps1' -File -Recurse | Sort-Object FullName)
$powerShellParseErrors = @()
foreach ($file in $powerShellFiles) {
    $tokens = $null
    $parseErrors = $null
    [System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$parseErrors) | Out-Null
    foreach ($parseError in @($parseErrors)) { $powerShellParseErrors += [ordered]@{ file = $file.FullName; message = $parseError.Message; extent = $parseError.Extent.Text } }
}
$jsonFiles = @(Get-ChildItem -LiteralPath (Join-Path $ProjectPath 'Research') -Filter '*.json' -File -Recurse)
$jsonParseErrors = @()
foreach ($file in $jsonFiles) {
    try { Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8 | ConvertFrom-Json | Out-Null }
    catch { $jsonParseErrors += [ordered]@{ file = $file.FullName; message = $_.Exception.Message } }
}
$jsonlFiles = @(Get-ChildItem -LiteralPath (Join-Path $ProjectPath 'Research') -Filter '*.jsonl' -File -Recurse)
$jsonlParseErrors = @()
foreach ($file in $jsonlFiles) {
    $lineNumber = 0
    foreach ($line in Get-Content -LiteralPath $file.FullName -Encoding UTF8) {
        $lineNumber++
        try { $line | ConvertFrom-Json | Out-Null }
        catch { $jsonlParseErrors += [ordered]@{ file = $file.FullName; line = $lineNumber; message = $_.Exception.Message } }
    }
}

$requiredSummaries = @(
    'Gate2_Smoke.summary.json',
    'Gate3_AStar.summary.json',
    'Gate4_ScenarioWorkload.summary.json',
    'Gate5_BatchPipeline.summary.json',
    'Gate6_ReplicationStatistics.summary.json',
    'Gate6_ScenarioCatalog.summary.json',
    'Gate6_ReplicationPipeline.summary.json',
    'Gate6_FinalAudit.summary.json',
    'Gate7_DStarLite.summary.json',
    'Gate7_DStarLite_BatchPipeline.summary.json',
    'Gate7_DStarLite_ReplicationPipeline.summary.json',
    'Gate7_FinalAudit.summary.json',
    'Gate8_CorrectedFlowField.summary.json',
    'Gate8_CFF_BatchPipeline.summary.json',
    'Gate8_CFF_ReplicationPipeline.summary.json',
    'Gate8_FinalAudit.summary.json',
    'Gate9_IncrementalFlowField.summary.json',
    'Gate9_IDFF_BatchPipeline.summary.json',
    'Gate9_IDFF_ReplicationPipeline.summary.json',
    'Gate9_FinalAudit.summary.json',
    'Gate10_FullRegression_Compile.summary.json',
    'Gate10_SpecificationAudit.summary.json',
    'Gate10_Fairness.summary.json',
    'Gate10_FairCampaignPipeline.summary.json',
    'Gate10_LegacyCompatibility.summary.json'
)
$summaryErrors = @()
foreach ($name in $requiredSummaries) {
    $path = Join-Path $scriptDirectory $name
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { $summaryErrors += "Missing summary: $path"; continue }
    try {
        $value = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($value.passed -ne $true) { $summaryErrors += "Summary is not passing: $path" }
    } catch { $summaryErrors += "Summary could not be parsed: $path - $($_.Exception.Message)" }
}

$requiredGate10Files = @(
    (Join-Path $ProjectPath 'Research\Four_Algorithm_Fairness_and_Unified_Campaign_Specification.md'),
    (Join-Path $ProjectPath 'Research\Gate10_Fairness_Test_Design.md'),
    (Join-Path $ProjectPath 'Research\Gate10_Checkpoint.md'),
    (Join-Path $ProjectPath 'Research\Run-FairPlanningCampaign.ps1'),
    (Join-Path $ProjectPath 'Assets\_Scripts\Research\Experiments\PlanningFairnessContracts.cs'),
    (Join-Path $ProjectPath 'Assets\_Scripts\Research\Editor\Gate10FairnessVerification.cs'),
    (Join-Path $scriptDirectory 'Run-Gate10SpecificationAudit.ps1'),
    (Join-Path $scriptDirectory 'Run-Gate10FairnessVerification.ps1'),
    (Join-Path $scriptDirectory 'Run-Gate10CampaignPipelineVerification.ps1'),
    (Join-Path $scriptDirectory 'Run-Gate10LegacyCompatibilityVerification.ps1'),
    (Join-Path $scriptDirectory 'Gate10_SharedGoal.scenario.json'),
    (Join-Path $scriptDirectory 'Gate10_FairCampaignFixture_Final\campaign-manifest.json')
)
$missingGate10Files = @($requiredGate10Files | Where-Object { -not (Test-Path -LiteralPath $_ -PathType Leaf) })

# Exactly four production planners are authorized. Two explicitly named Editor-only test doubles are allowed.
$algorithmFiles = @(Get-ChildItem -LiteralPath (Join-Path $ProjectPath 'Assets\_Scripts\Research\Algorithms') -Filter '*.cs' -File | Sort-Object Name)
$algorithmFileNames = @($algorithmFiles.Name)
$plannerImplementationMatches = @(
    Get-ChildItem -LiteralPath (Join-Path $ProjectPath 'Assets\_Scripts\Research') -Filter '*.cs' -File -Recurse |
        Select-String -Pattern 'class\s+[A-Za-z0-9_]+\s*:\s*INavigationPlanner' |
        ForEach-Object { [ordered]@{ file = $_.Path; line = $_.LineNumber; text = $_.Line.Trim() } }
)
$algorithmScopeValid = (
    $algorithmFiles.Count -eq 4 -and
    @($algorithmFileNames | Where-Object { $_ -eq 'AStarRepeatedPlanner.cs' }).Count -eq 1 -and
    @($algorithmFileNames | Where-Object { $_ -eq 'DStarLitePlanner.cs' }).Count -eq 1 -and
    @($algorithmFileNames | Where-Object { $_ -eq 'CorrectedFullRecomputeFlowFieldPlanner.cs' }).Count -eq 1 -and
    @($algorithmFileNames | Where-Object { $_ -eq 'IncrementalDynamicFlowFieldPlanner.cs' }).Count -eq 1 -and
    $plannerImplementationMatches.Count -eq 6 -and
    @($plannerImplementationMatches | Where-Object { $_.file -like '*\Algorithms\AStarRepeatedPlanner.cs' -and $_.text -match 'AStarRepeatedPlanner' }).Count -eq 1 -and
    @($plannerImplementationMatches | Where-Object { $_.file -like '*\Algorithms\DStarLitePlanner.cs' -and $_.text -match 'DStarLitePlanner' }).Count -eq 1 -and
    @($plannerImplementationMatches | Where-Object { $_.file -like '*\Algorithms\CorrectedFullRecomputeFlowFieldPlanner.cs' -and $_.text -match 'CorrectedFullRecomputeFlowFieldPlanner' }).Count -eq 1 -and
    @($plannerImplementationMatches | Where-Object { $_.file -like '*\Algorithms\IncrementalDynamicFlowFieldPlanner.cs' -and $_.text -match 'IncrementalDynamicFlowFieldPlanner' }).Count -eq 1 -and
    @($plannerImplementationMatches | Where-Object { $_.file -like '*\Editor\Gate2SmokeVerification.cs' -and $_.text -match 'RecordingPlanner' }).Count -eq 1 -and
    @($plannerImplementationMatches | Where-Object { $_.file -like '*\Editor\Gate10FairnessVerification.cs' -and $_.text -match 'ScriptedMetricsPlanner' }).Count -eq 1
)

# One warning from frozen original code is expected. The first Gate 10 import compile is retained as superseded history.
$logs = @(Get-ChildItem -LiteralPath $scriptDirectory -Filter '*.log' -File -Recurse)
$warningMatches = @()
foreach ($log in $logs) {
    foreach ($match in @(Select-String -LiteralPath $log.FullName -Pattern 'warning CS\d{4}' -AllMatches)) { $warningMatches += [ordered]@{ log = $log.FullName; line = $match.LineNumber; text = $match.Line.Trim() } }
}
$uniqueWarningTexts = @($warningMatches | ForEach-Object { $_.text } | Sort-Object -Unique)
$warningsExpected = $uniqueWarningTexts.Count -eq 1 -and $uniqueWarningTexts[0] -match "Unit\.cs\(33,19\): warning CS0414: The field 'Unit\.gravityMultiplier'"
$compilerErrorMatches = @()
foreach ($log in $logs) {
    foreach ($match in @(Select-String -LiteralPath $log.FullName -Pattern @('error CS\d{4}', 'Scripts have compiler errors', 'Compilation failed', 'executeMethod.+could not be found') -AllMatches)) { $compilerErrorMatches += [ordered]@{ log = $log.FullName; line = $match.LineNumber; text = $match.Line.Trim() } }
}
$initialCompileSummaryPath = Join-Path $scriptDirectory 'Gate10_Fairness_InitialCompile.summary.json'
$afterImportSummaryPath = Join-Path $scriptDirectory 'Gate10_Fairness_Compile_AfterImport.summary.json'
$runtimeCompileSummaryPath = Join-Path $scriptDirectory 'Gate10_RuntimeCompile.summary.json'
$initialCompileSummary = Get-Content -LiteralPath $initialCompileSummaryPath -Raw -Encoding UTF8 | ConvertFrom-Json
$afterImportSummary = Get-Content -LiteralPath $afterImportSummaryPath -Raw -Encoding UTF8 | ConvertFrom-Json
$runtimeCompileSummary = Get-Content -LiteralPath $runtimeCompileSummaryPath -Raw -Encoding UTF8 | ConvertFrom-Json
$supersededInitialCompileExpected = (
    $initialCompileSummary.passed -eq $false -and
    $initialCompileSummary.compilerErrorMatchCount -eq 3 -and
    @($compilerErrorMatches | Where-Object { $_.log -notlike '*\Gate10_Fairness_InitialCompile.log' }).Count -eq 0 -and
    $afterImportSummary.passed -eq $true -and $afterImportSummary.compilerErrorMatchCount -eq 0 -and
    $runtimeCompileSummary.passed -eq $true -and $runtimeCompileSummary.compilerErrorMatchCount -eq 0
)

$evidenceHashes = [ordered]@{
    fairnessSpecification = Get-LowerSha256 (Join-Path $ProjectPath 'Research\Four_Algorithm_Fairness_and_Unified_Campaign_Specification.md')
    fairnessTestDesign = Get-LowerSha256 (Join-Path $ProjectPath 'Research\Gate10_Fairness_Test_Design.md')
    fairnessContractSource = Get-LowerSha256 (Join-Path $ProjectPath 'Assets\_Scripts\Research\Experiments\PlanningFairnessContracts.cs')
    campaignLauncher = Get-LowerSha256 (Join-Path $ProjectPath 'Research\Run-FairPlanningCampaign.ps1')
    fairnessResult = Get-LowerSha256 (Join-Path $scriptDirectory 'Gate10_Fairness.json')
    sharedGoalScenario = Get-LowerSha256 (Join-Path $scriptDirectory 'Gate10_SharedGoal.scenario.json')
    campaignManifest = Get-LowerSha256 (Join-Path $scriptDirectory 'Gate10_FairCampaignFixture_Final\campaign-manifest.json')
    legacyGate6 = Get-LowerSha256 (Join-Path $scriptDirectory 'Gate10_LegacyRevalidation_Gate6.json')
    legacyGate7 = Get-LowerSha256 (Join-Path $scriptDirectory 'Gate10_LegacyRevalidation_Gate7.json')
    legacyGate8 = Get-LowerSha256 (Join-Path $scriptDirectory 'Gate10_LegacyRevalidation_Gate8.json')
    legacyGate9 = Get-LowerSha256 (Join-Path $scriptDirectory 'Gate10_LegacyRevalidation_Gate9.json')
}
$evidenceHashesValid = (
    $evidenceHashes.fairnessSpecification -eq '42a4a8439c3d7b46b7644bed14b8f91d87bae4c6f8b2183a73609ee5461e82dd' -and
    $evidenceHashes.fairnessTestDesign -eq '6ab9b5b47783f727a48d55a9dc3b8ef3a360438da874e6233aa2f0af4d646d38' -and
    $evidenceHashes.fairnessContractSource -eq '42e1865294439986e808547115b22ccaaff53f3293790a8c4a135fb529ef3a60' -and
    $evidenceHashes.campaignLauncher -eq '176f82fed18beee2fc7e2c8cb37ce988f7c7f4740cdeec3c5510b677843615c3' -and
    $evidenceHashes.fairnessResult -eq 'e1dd0202f0aebd21010f69a7a5e76347f10751865f66e658afd38535b7b4888f' -and
    $evidenceHashes.sharedGoalScenario -eq '98981cd9504d1132099f1812209125c4110b2d3987c581e6ff1696c22d5985a3' -and
    $evidenceHashes.campaignManifest -eq '4d9d61b15f2e375909c541f6070bd405624e90ae516e6ecb7d7b4ebb7585e987' -and
    $evidenceHashes.legacyGate6 -eq '41879b0c14747e0cf926527f43819d827cf03561bdbfc58f364b8924375f1b95' -and
    $evidenceHashes.legacyGate7 -eq '40be411b5b6f59def94a0c013831389a26b380f47ff61f1fd9c674fcc4fd40dd' -and
    $evidenceHashes.legacyGate8 -eq 'b1783ae22c6d6224bdb9c38d1e79f9a105caf8a2eb50b0220a5aa517e1bdd620' -and
    $evidenceHashes.legacyGate9 -eq 'a8cddf0494d70d93ca43d1ae5107d2ee83b39aa665cece64469c8ce8c5a30eac'
)

$campaignSummary = Get-Content -LiteralPath (Join-Path $scriptDirectory 'Gate10_FairCampaignPipeline.summary.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$campaignEvidenceValid = (
    $campaignSummary.passed -eq $true -and
    $campaignSummary.sampleCount -eq 16 -and
    $campaignSummary.totalJsonlRecords -eq 272 -and
    $campaignSummary.totalPlanOperations -eq 128 -and
    $campaignSummary.totalRepairOperations -eq 64 -and
    $campaignSummary.totalSucceededPlans -eq 128 -and
    $campaignSummary.totalBudgetExceededOperations -eq 0
)
$unityProcesses = @(Get-Process -Name Unity -ErrorAction SilentlyContinue)
$lockPath = Join-Path $ProjectPath 'Temp\UnityLockfile'
$checks = [ordered]@{
    frozenBaselineMatches = $baselineChecked -eq 24 -and $baselineMismatches.Count -eq 0
    latestGateSummariesPass = $summaryErrors.Count -eq 0
    gate10FilesPresent = $missingGate10Files.Count -eq 0
    powerShellParses = $powerShellParseErrors.Count -eq 0
    jsonParses = $jsonParseErrors.Count -eq 0
    jsonlParses = $jsonlParseErrors.Count -eq 0
    authorizedAlgorithmScopeExact = $algorithmScopeValid
    compilerWarningsExpected = $warningsExpected
    supersededInitialCompileAndCleanFinalCompiles = $supersededInitialCompileExpected
    retainedEvidenceHashesMatch = $evidenceHashesValid
    campaignEvidenceComplete = $campaignEvidenceValid
    noUnityProcess = $unityProcesses.Count -eq 0
    noUnityLockfile = -not (Test-Path -LiteralPath $lockPath)
}
$failedChecks = @($checks.GetEnumerator() | Where-Object { -not $_.Value } | ForEach-Object { $_.Key })
$passed = $failedChecks.Count -eq 0
$summary = [ordered]@{
    savedAt = (Get-Date).ToString('o')
    projectPath = $ProjectPath
    baselineChecked = $baselineChecked
    baselineMismatches = $baselineMismatches
    requiredGateSummaryCount = $requiredSummaries.Count
    summaryErrors = $summaryErrors
    missingGate10Files = $missingGate10Files
    powerShellScriptCount = $powerShellFiles.Count
    powerShellParseErrors = $powerShellParseErrors
    jsonFileCount = $jsonFiles.Count
    jsonParseErrors = $jsonParseErrors
    jsonlFileCount = $jsonlFiles.Count
    jsonlParseErrors = $jsonlParseErrors
    algorithmFiles = $algorithmFileNames
    plannerImplementationMatches = $plannerImplementationMatches
    uniqueCompilerWarnings = $uniqueWarningTexts
    compilerErrorMatches = $compilerErrorMatches
    evidenceHashes = $evidenceHashes
    campaignTotals = [ordered]@{ samples = $campaignSummary.sampleCount; jsonlRecords = $campaignSummary.totalJsonlRecords; plans = $campaignSummary.totalPlanOperations; repairs = $campaignSummary.totalRepairOperations; succeededPlans = $campaignSummary.totalSucceededPlans; budgetExceededOperations = $campaignSummary.totalBudgetExceededOperations }
    unityProcessIds = @($unityProcesses | ForEach-Object { $_.Id })
    unityLockfilePresent = Test-Path -LiteralPath $lockPath
    checks = $checks
    failedChecks = $failedChecks
    passed = $passed
}
$summary | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $summaryPath -Encoding UTF8
$summary | ConvertTo-Json -Depth 10
if (-not $passed) { Write-Error "Gate 10 final audit failed. Review $summaryPath."; exit 1 }
Write-Host 'Gate 10 final audit passed.' -ForegroundColor Green
exit 0
