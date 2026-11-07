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
$summaryPath = Join-Path $scriptDirectory 'Gate9_FinalAudit.summary.json'

function Get-LowerSha256([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

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
        $baselineMismatches += [ordered]@{
            scope = $row.scope
            relativePath = $row.relative_path
            exists = $exists
            expectedBytes = [int64]$row.bytes
            actualBytes = $actualBytes
            expectedSha256 = $row.sha256
            actualSha256 = $actualHash
        }
    }
}

$powerShellFiles = @(Get-ChildItem -LiteralPath (Join-Path $ProjectPath 'Research') -Filter '*.ps1' -File -Recurse | Sort-Object FullName)
$powerShellParseErrors = @()
foreach ($file in $powerShellFiles) {
    $tokens = $null
    $parseErrors = $null
    [System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$parseErrors) | Out-Null
    foreach ($parseError in @($parseErrors)) {
        $powerShellParseErrors += [ordered]@{ file = $file.FullName; message = $parseError.Message; extent = $parseError.Extent.Text }
    }
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
    'Gate8_CorrectedFlowField.summary.json',
    'Gate8_CFF_BatchPipeline.summary.json',
    'Gate8_CFF_ReplicationPipeline.summary.json',
    'Gate9_FullRegression_Compile.summary.json',
    'Gate9_IncrementalFlowField.summary.json',
    'Gate9_IDFF_BatchPipeline.summary.json',
    'Gate9_IDFF_ReplicationPipeline.summary.json'
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

$requiredGate9Files = @(
    (Join-Path $ProjectPath 'Research\Incremental_Dynamic_Flow_Field_Specification.md'),
    (Join-Path $ProjectPath 'Research\Gate9_IDFF_Test_Design.md'),
    (Join-Path $ProjectPath 'Research\Gate9_Checkpoint.md'),
    (Join-Path $ProjectPath 'Assets\_Scripts\Research\Algorithms\IncrementalDynamicFlowFieldPlanner.cs'),
    (Join-Path $ProjectPath 'Assets\_Scripts\Research\Editor\Gate9IncrementalFlowFieldVerification.cs'),
    (Join-Path $scriptDirectory 'Run-Gate9IncrementalFlowFieldVerification.ps1'),
    (Join-Path $scriptDirectory 'Run-Gate9BatchPipelineVerification.ps1'),
    (Join-Path $scriptDirectory 'Run-Gate9ReplicationPipelineVerification.ps1')
)
$missingGate9Files = @($requiredGate9Files | Where-Object { -not (Test-Path -LiteralPath $_ -PathType Leaf) })

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

$logs = @(Get-ChildItem -LiteralPath $scriptDirectory -Filter '*.log' -File)
$warningMatches = @()
foreach ($log in $logs) {
    foreach ($match in @(Select-String -LiteralPath $log.FullName -Pattern 'warning CS\d{4}' -AllMatches)) {
        $warningMatches += [ordered]@{ log = $log.Name; line = $match.LineNumber; text = $match.Line.Trim() }
    }
}
$uniqueWarningTexts = @($warningMatches | ForEach-Object { $_.text } | Sort-Object -Unique)
$warningsExpected = $uniqueWarningTexts.Count -eq 1 -and $uniqueWarningTexts[0] -match "Unit\.cs\(33,19\): warning CS0414: The field 'Unit\.gravityMultiplier'"

$evidenceHashes = [ordered]@{
    gate5BatchManifest = Get-LowerSha256 (Join-Path $scriptDirectory 'Gate5_BatchFixture_Final\manifest.json')
    gate6ReplicationManifest = Get-LowerSha256 (Join-Path $scriptDirectory 'Gate6_ReplicationFixture_Final\replication-manifest.json')
    gate6Aggregate = Get-LowerSha256 (Join-Path $scriptDirectory 'Gate6_ReplicationFixture_Final\aggregate.json')
    gate6RevalidatedAggregate = Get-LowerSha256 (Join-Path $scriptDirectory 'Gate6_CurrentCodeAggregate_Revalidation.json')
    gate7BatchManifest = Get-LowerSha256 (Join-Path $scriptDirectory 'Gate7_DStarLite_BatchFixture_Final\manifest.json')
    gate7ReplicationManifest = Get-LowerSha256 (Join-Path $scriptDirectory 'Gate7_DStarLite_ReplicationFixture_Final\replication-manifest.json')
    gate7Aggregate = Get-LowerSha256 (Join-Path $scriptDirectory 'Gate7_DStarLite_ReplicationFixture_Final\aggregate.json')
    gate7RevalidatedAggregate = Get-LowerSha256 (Join-Path $scriptDirectory 'Gate7_DStarLite_CurrentCodeAggregate_Revalidation.json')
    gate8AlgorithmResult = Get-LowerSha256 (Join-Path $scriptDirectory 'Gate8_CorrectedFlowField.json')
    gate8BatchManifest = Get-LowerSha256 (Join-Path $scriptDirectory 'Gate8_CFF_BatchFixture_Final\manifest.json')
    gate8ReplicationManifest = Get-LowerSha256 (Join-Path $scriptDirectory 'Gate8_CFF_ReplicationFixture_Final\replication-manifest.json')
    gate8Aggregate = Get-LowerSha256 (Join-Path $scriptDirectory 'Gate8_CFF_ReplicationFixture_Final\aggregate.json')
    gate8RevalidatedAggregate = Get-LowerSha256 (Join-Path $scriptDirectory 'Gate8_CFF_CurrentCodeAggregate_Revalidation.json')
    gate9AlgorithmResult = Get-LowerSha256 (Join-Path $scriptDirectory 'Gate9_IncrementalFlowField.json')
    gate9BatchManifest = Get-LowerSha256 (Join-Path $scriptDirectory 'Gate9_IDFF_BatchFixture_Final\manifest.json')
    gate9ReplicationManifest = Get-LowerSha256 (Join-Path $scriptDirectory 'Gate9_IDFF_ReplicationFixture_Final\replication-manifest.json')
    gate9Aggregate = Get-LowerSha256 (Join-Path $scriptDirectory 'Gate9_IDFF_ReplicationFixture_Final\aggregate.json')
    gate9RevalidatedAggregate = Get-LowerSha256 (Join-Path $scriptDirectory 'Gate9_IDFF_CurrentCodeAggregate_Revalidation.json')
}
$evidenceHashesValid = (
    $evidenceHashes.gate5BatchManifest -eq 'b74eb4f7a2722610c370a196e130449b971dc8733d7424b45a74e152ce6e0313' -and
    $evidenceHashes.gate6ReplicationManifest -eq 'f7d20028012c631f455cff67a2612e9c8d9333d1f189a9e7d0c5b57f1a79ce52' -and
    $evidenceHashes.gate6Aggregate -eq '41879b0c14747e0cf926527f43819d827cf03561bdbfc58f364b8924375f1b95' -and
    $evidenceHashes.gate6RevalidatedAggregate -eq $evidenceHashes.gate6Aggregate -and
    $evidenceHashes.gate7BatchManifest -eq 'c2c160d0c1aec00a59e7d2d02ebfee776a4ce1272b23fc2929e8d568c09cd427' -and
    $evidenceHashes.gate7ReplicationManifest -eq '24fca9a22a24e2f7c18003162790a9bc775c6aaf4a9e4ca95ff4261dc589e4fc' -and
    $evidenceHashes.gate7Aggregate -eq '40be411b5b6f59def94a0c013831389a26b380f47ff61f1fd9c674fcc4fd40dd' -and
    $evidenceHashes.gate7RevalidatedAggregate -eq $evidenceHashes.gate7Aggregate -and
    $evidenceHashes.gate8AlgorithmResult -eq '31ee6aa7a717815fcf2df8bdd71b341accbf765c2ac82fa5c44aaa56352aac57' -and
    $evidenceHashes.gate8BatchManifest -eq '27ec8cab7b1d0151df8c5b56ffa0c89b8c8b29f41500d00baddf73f31ad678fc' -and
    $evidenceHashes.gate8ReplicationManifest -eq '8b08bbbad0b9962d877e60f8ec7257b50b53a29659584f5115594b1c98718c19' -and
    $evidenceHashes.gate8Aggregate -eq 'b1783ae22c6d6224bdb9c38d1e79f9a105caf8a2eb50b0220a5aa517e1bdd620' -and
    $evidenceHashes.gate8RevalidatedAggregate -eq $evidenceHashes.gate8Aggregate -and
    $evidenceHashes.gate9AlgorithmResult -eq '605db09fdca3176e3db21a03da0fb1cca9e7a31ec1037de1b6d8860b69dc0328' -and
    $evidenceHashes.gate9BatchManifest -eq 'cc241d5359235bd4dc62d8eac6937e9d90e5cd06610a49598a84e26cc270df10' -and
    $evidenceHashes.gate9ReplicationManifest -eq '9350a571e895c011080765e75b71fcd38f818d05ec7025fd12a96895ca90ce1b' -and
    $evidenceHashes.gate9Aggregate -eq 'a8cddf0494d70d93ca43d1ae5107d2ee83b39aa665cece64469c8ce8c5a30eac' -and
    $evidenceHashes.gate9RevalidatedAggregate -eq $evidenceHashes.gate9Aggregate
)

$unityProcesses = @(Get-Process -Name Unity -ErrorAction SilentlyContinue)
$lockPath = Join-Path $ProjectPath 'Temp\UnityLockfile'
$checks = [ordered]@{
    frozenBaselineMatches = $baselineChecked -eq 24 -and $baselineMismatches.Count -eq 0
    latestGateSummariesPass = $summaryErrors.Count -eq 0
    gate9FilesPresent = $missingGate9Files.Count -eq 0
    powerShellParses = $powerShellParseErrors.Count -eq 0
    jsonParses = $jsonParseErrors.Count -eq 0
    jsonlParses = $jsonlParseErrors.Count -eq 0
    authorizedAlgorithmScopeExact = $algorithmScopeValid
    compilerWarningsExpected = $warningsExpected
    retainedEvidenceHashesMatch = $evidenceHashesValid
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
    missingGate9Files = $missingGate9Files
    powerShellScriptCount = $powerShellFiles.Count
    powerShellParseErrors = $powerShellParseErrors
    jsonFileCount = $jsonFiles.Count
    jsonParseErrors = $jsonParseErrors
    jsonlFileCount = $jsonlFiles.Count
    jsonlParseErrors = $jsonlParseErrors
    algorithmFiles = $algorithmFileNames
    plannerImplementationMatches = $plannerImplementationMatches
    uniqueCompilerWarnings = $uniqueWarningTexts
    evidenceHashes = $evidenceHashes
    unityProcessIds = @($unityProcesses | ForEach-Object { $_.Id })
    unityLockfilePresent = Test-Path -LiteralPath $lockPath
    checks = $checks
    failedChecks = $failedChecks
    passed = $passed
}
$summary | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $summaryPath -Encoding UTF8
$summary | ConvertTo-Json -Depth 10
if (-not $passed) { Write-Error "Gate 9 final audit failed. Review $summaryPath."; exit 1 }
Write-Host 'Gate 9 final audit passed.' -ForegroundColor Green
exit 0

