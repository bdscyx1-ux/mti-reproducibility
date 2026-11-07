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
$summaryPath = Join-Path $scriptDirectory 'Gate6_FinalAudit.summary.json'

$baselineRows = Import-Csv -LiteralPath (Join-Path $ProjectPath 'Research\Baseline_SHA256.csv')
$baselineMismatches = @()
$baselineChecked = 0
foreach ($row in $baselineRows | Where-Object { $_.scope -in @('external_archive', 'working_copy') }) {
    $baselineChecked++
    $path = [System.IO.Path]::GetFullPath((Join-Path $ProjectPath $row.relative_path))
    $exists = Test-Path -LiteralPath $path -PathType Leaf
    $actualBytes = if ($exists) { (Get-Item -LiteralPath $path).Length } else { $null }
    $actualHash = if ($exists) { (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant() } else { $null }
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
    'Gate6_FinalCompile.summary.json',
    'Gate2_Smoke.summary.json',
    'Gate3_AStar.summary.json',
    'Gate4_ScenarioWorkload.summary.json',
    'Gate5_BatchPipeline.summary.json',
    'Gate6_ReplicationStatistics.summary.json',
    'Gate6_ScenarioCatalog.summary.json',
    'Gate6_ReplicationPipeline.summary.json',
    'Gate7_DStarLite.summary.json'
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

$algorithmFiles = @(Get-ChildItem -LiteralPath (Join-Path $ProjectPath 'Assets\_Scripts\Research\Algorithms') -Filter '*.cs' -File | Sort-Object Name)
$plannerImplementationMatches = @(
    Get-ChildItem -LiteralPath (Join-Path $ProjectPath 'Assets\_Scripts\Research') -Filter '*.cs' -File -Recurse |
        Select-String -Pattern 'class\s+[A-Za-z0-9_]+\s*:\s*INavigationPlanner' |
        ForEach-Object { [ordered]@{ file = $_.Path; line = $_.LineNumber; text = $_.Line.Trim() } }
)
$plannerImplementationsExpected = (
    $plannerImplementationMatches.Count -eq 6 -and
    @($plannerImplementationMatches | Where-Object { $_.file -like '*\Algorithms\AStarRepeatedPlanner.cs' -and $_.text -match 'AStarRepeatedPlanner' }).Count -eq 1 -and
    @($plannerImplementationMatches | Where-Object { $_.file -like '*\Algorithms\DStarLitePlanner.cs' -and $_.text -match 'DStarLitePlanner' }).Count -eq 1 -and
    @($plannerImplementationMatches | Where-Object { $_.file -like '*\Algorithms\CorrectedFullRecomputeFlowFieldPlanner.cs' -and $_.text -match 'CorrectedFullRecomputeFlowFieldPlanner' }).Count -eq 1 -and
    @($plannerImplementationMatches | Where-Object { $_.file -like '*\Algorithms\IncrementalDynamicFlowFieldPlanner.cs' -and $_.text -match 'IncrementalDynamicFlowFieldPlanner' }).Count -eq 1 -and
    @($plannerImplementationMatches | Where-Object { $_.file -like '*\Editor\Gate2SmokeVerification.cs' -and $_.text -match 'RecordingPlanner' }).Count -eq 1 -and
    @($plannerImplementationMatches | Where-Object { $_.file -like '*\Editor\Gate10FairnessVerification.cs' -and $_.text -match 'ScriptedMetricsPlanner' }).Count -eq 1
)
$algorithmFileNames = @($algorithmFiles.Name)
$algorithmScopeValid = (
    $algorithmFiles.Count -eq 4 -and
    @($algorithmFileNames | Where-Object { $_ -eq 'AStarRepeatedPlanner.cs' }).Count -eq 1 -and
    @($algorithmFileNames | Where-Object { $_ -eq 'DStarLitePlanner.cs' }).Count -eq 1 -and
    @($algorithmFileNames | Where-Object { $_ -eq 'CorrectedFullRecomputeFlowFieldPlanner.cs' }).Count -eq 1 -and
    @($algorithmFileNames | Where-Object { $_ -eq 'IncrementalDynamicFlowFieldPlanner.cs' }).Count -eq 1 -and
    $plannerImplementationsExpected
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

$unityProcesses = @(Get-Process -Name Unity -ErrorAction SilentlyContinue)
$lockPath = Join-Path $ProjectPath 'Temp\UnityLockfile'
$fixtureManifestPath = Join-Path $scriptDirectory 'Gate6_ReplicationFixture_Final\replication-manifest.json'
$fixtureManifestHash = if (Test-Path -LiteralPath $fixtureManifestPath -PathType Leaf) { (Get-FileHash -LiteralPath $fixtureManifestPath -Algorithm SHA256).Hash.ToLowerInvariant() } else { $null }
$fixtureAggregatePath = Join-Path $scriptDirectory 'Gate6_ReplicationFixture_Final\aggregate.json'
$revalidatedAggregatePath = Join-Path $scriptDirectory 'Gate6_CurrentCodeAggregate_Revalidation.json'
$revalidationLogPath = Join-Path $scriptDirectory 'Gate6_CurrentCodeAggregate_Revalidation.Unity.log'
$fixtureAggregateHash = if (Test-Path -LiteralPath $fixtureAggregatePath -PathType Leaf) { (Get-FileHash -LiteralPath $fixtureAggregatePath -Algorithm SHA256).Hash.ToLowerInvariant() } else { $null }
$revalidatedAggregateHash = if (Test-Path -LiteralPath $revalidatedAggregatePath -PathType Leaf) { (Get-FileHash -LiteralPath $revalidatedAggregatePath -Algorithm SHA256).Hash.ToLowerInvariant() } else { $null }
$revalidationCompilerErrors = if (Test-Path -LiteralPath $revalidationLogPath -PathType Leaf) { @(Select-String -LiteralPath $revalidationLogPath -Pattern @('error CS\d{4}', 'Scripts have compiler errors', 'Compilation failed', 'executeMethod.+could not be found') -AllMatches) } else { @('missing log') }
$revalidationCompletionMarker = if (Test-Path -LiteralPath $revalidationLogPath -PathType Leaf) { @(Select-String -LiteralPath $revalidationLogPath -SimpleMatch 'DDM replication aggregation completed. Output:').Count -gt 0 } else { $false }

$checks = [ordered]@{
    frozenBaselineMatches = $baselineChecked -eq 24 -and $baselineMismatches.Count -eq 0
    latestGateSummariesPass = $summaryErrors.Count -eq 0
    powerShellParses = $powerShellParseErrors.Count -eq 0
    jsonParses = $jsonParseErrors.Count -eq 0
    jsonlParses = $jsonlParseErrors.Count -eq 0
    algorithmScopePreserved = $algorithmScopeValid
    compilerWarningsExpected = $warningsExpected
    retainedGate6ManifestMatches = $fixtureManifestHash -eq 'f7d20028012c631f455cff67a2612e9c8d9333d1f189a9e7d0c5b57f1a79ce52'
    currentCodeAggregateRevalidationMatches = $fixtureAggregateHash -eq '41879b0c14747e0cf926527f43819d827cf03561bdbfc58f364b8924375f1b95' -and $revalidatedAggregateHash -eq $fixtureAggregateHash -and $revalidationCompilerErrors.Count -eq 0 -and $revalidationCompletionMarker
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
    powerShellScriptCount = $powerShellFiles.Count
    powerShellParseErrors = $powerShellParseErrors
    jsonFileCount = $jsonFiles.Count
    jsonParseErrors = $jsonParseErrors
    jsonlFileCount = $jsonlFiles.Count
    jsonlParseErrors = $jsonlParseErrors
    algorithmFiles = @($algorithmFiles.Name)
    plannerImplementationMatches = $plannerImplementationMatches
    uniqueCompilerWarnings = $uniqueWarningTexts
    unityProcessIds = @($unityProcesses | ForEach-Object { $_.Id })
    unityLockfilePresent = Test-Path -LiteralPath $lockPath
    retainedGate6ManifestSha256 = $fixtureManifestHash
    retainedAggregateSha256 = $fixtureAggregateHash
    currentCodeRevalidatedAggregateSha256 = $revalidatedAggregateHash
    revalidationCompilerErrorMatchCount = $revalidationCompilerErrors.Count
    revalidationCompletionMarkerPresent = $revalidationCompletionMarker
    checks = $checks
    failedChecks = $failedChecks
    passed = $passed
}
$summary | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $summaryPath -Encoding UTF8
$summary | ConvertTo-Json -Depth 10
if (-not $passed) { Write-Error "Gate 6 final audit failed. Review $summaryPath."; exit 1 }
Write-Host 'Gate 6 final audit passed.' -ForegroundColor Green
exit 0
