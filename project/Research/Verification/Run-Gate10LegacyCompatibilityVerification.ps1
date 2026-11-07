[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$scriptDirectory = Split-Path -Parent $MyInvocation.MyCommand.Path
$summaryPath = Join-Path $scriptDirectory 'Gate10_LegacyCompatibility.summary.json'

function Get-LowerSha256([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

$cases = @(
    [ordered]@{ gate = 'Gate6'; retained = 'Gate6_ReplicationFixture_Final\aggregate.json'; revalidated = 'Gate10_LegacyRevalidation_Gate6.json'; log = 'Gate10_LegacyRevalidation_Gate6.Unity.log'; expected = '41879b0c14747e0cf926527f43819d827cf03561bdbfc58f364b8924375f1b95' },
    [ordered]@{ gate = 'Gate7'; retained = 'Gate7_DStarLite_ReplicationFixture_Final\aggregate.json'; revalidated = 'Gate10_LegacyRevalidation_Gate7.json'; log = 'Gate10_LegacyRevalidation_Gate7.Unity.log'; expected = '40be411b5b6f59def94a0c013831389a26b380f47ff61f1fd9c674fcc4fd40dd' },
    [ordered]@{ gate = 'Gate8'; retained = 'Gate8_CFF_ReplicationFixture_Final\aggregate.json'; revalidated = 'Gate10_LegacyRevalidation_Gate8.json'; log = 'Gate10_LegacyRevalidation_Gate8.Unity.log'; expected = 'b1783ae22c6d6224bdb9c38d1e79f9a105caf8a2eb50b0220a5aa517e1bdd620' },
    [ordered]@{ gate = 'Gate9'; retained = 'Gate9_IDFF_ReplicationFixture_Final\aggregate.json'; revalidated = 'Gate10_LegacyRevalidation_Gate9.json'; log = 'Gate10_LegacyRevalidation_Gate9.Unity.log'; expected = 'a8cddf0494d70d93ca43d1ae5107d2ee83b39aa665cece64469c8ce8c5a30eac' }
)

$results = @()
foreach ($case in $cases) {
    $retainedPath = Join-Path $scriptDirectory $case.retained
    $revalidatedPath = Join-Path $scriptDirectory $case.revalidated
    $logPath = Join-Path $scriptDirectory $case.log
    $retainedHash = Get-LowerSha256 $retainedPath
    $revalidatedHash = Get-LowerSha256 $revalidatedPath
    $compilerMatches = if (Test-Path -LiteralPath $logPath -PathType Leaf) { @(Select-String -LiteralPath $logPath -Pattern @('error CS\d{4}', 'Scripts have compiler errors', 'Compilation failed', 'executeMethod.+could not be found') -AllMatches) } else { @() }
    $completionMarkers = if (Test-Path -LiteralPath $logPath -PathType Leaf) { @(Select-String -LiteralPath $logPath -SimpleMatch 'DDM replication aggregation completed. Output:').Count } else { 0 }
    $jsonParses = $false
    if (Test-Path -LiteralPath $revalidatedPath -PathType Leaf) {
        try {
            Get-Content -LiteralPath $revalidatedPath -Raw -Encoding UTF8 | ConvertFrom-Json | Out-Null
            $jsonParses = $true
        } catch { $jsonParses = $false }
    }
    $passed = (
        $retainedHash -eq $case.expected -and
        $revalidatedHash -eq $case.expected -and
        $retainedHash -eq $revalidatedHash -and
        $jsonParses -and
        $compilerMatches.Count -eq 0 -and
        $completionMarkers -eq 1
    )
    $results += [ordered]@{
        gate = $case.gate
        retainedAggregatePath = $retainedPath
        retainedAggregateSha256 = $retainedHash
        currentCodeAggregatePath = $revalidatedPath
        currentCodeAggregateSha256 = $revalidatedHash
        expectedSha256 = $case.expected
        byteIdentical = $retainedHash -eq $revalidatedHash
        jsonParses = $jsonParses
        compilerErrorMatchCount = $compilerMatches.Count
        completionMarkerCount = $completionMarkers
        passed = $passed
    }
}

$checks = [ordered]@{
    allFourHistoricalFormatsAccepted = @($results | Where-Object { -not $_.passed }).Count -eq 0
    allCurrentCodeOutputsByteIdentical = @($results | Where-Object { -not $_.byteIdentical }).Count -eq 0
    allUnityRunsClean = @($results | Where-Object { $_.compilerErrorMatchCount -ne 0 -or $_.completionMarkerCount -ne 1 }).Count -eq 0
}
$failedChecks = @($checks.GetEnumerator() | Where-Object { -not $_.Value } | ForEach-Object { $_.Key })
$passed = $failedChecks.Count -eq 0
$summary = [ordered]@{
    savedAt = (Get-Date).ToString('o')
    cases = $results
    checks = $checks
    failedChecks = $failedChecks
    passed = $passed
}
$summary | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $summaryPath -Encoding UTF8
$summary | ConvertTo-Json -Depth 8
if (-not $passed) { Write-Error "Gate 10 legacy compatibility verification failed. Review $summaryPath."; exit 1 }
Write-Host 'Gate 10 legacy compatibility verification passed.' -ForegroundColor Green
exit 0
