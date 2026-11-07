[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ProjectPath,

    [Parameter(Mandatory = $true)]
    [string]$AnalysisRoot,

    [Parameter(Mandatory = $true)]
    [string]$DeterministicRootA,

    [Parameter(Mandatory = $true)]
    [string]$DeterministicRootB,

    [Parameter(Mandatory = $true)]
    [string]$SummaryPath
)

$ErrorActionPreference = 'Stop'
$resolvedProject = (Resolve-Path -LiteralPath $ProjectPath).Path
$resolvedAnalysis = (Resolve-Path -LiteralPath $AnalysisRoot).Path
$resolvedA = (Resolve-Path -LiteralPath $DeterministicRootA).Path
$resolvedB = (Resolve-Path -LiteralPath $DeterministicRootB).Path
$checks = New-Object System.Collections.Generic.List[object]

function Get-Sha256([string]$Path) {
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Get-TreeIdentity([string]$Path) {
    $root = (Resolve-Path -LiteralPath $Path).Path
    $files = @(Get-ChildItem -LiteralPath $root -File -Recurse | Sort-Object FullName)
    $lines = New-Object System.Collections.Generic.List[string]
    [long]$bytes = 0
    foreach ($file in $files) {
        $relative = $file.FullName.Substring($root.Length).TrimStart([char]'\').Replace('\', '/')
        $bytes += $file.Length
        $lines.Add("$relative|$($file.Length)|$(Get-Sha256 $file.FullName)")
    }
    $payload = [System.Text.Encoding]::UTF8.GetBytes(($lines -join "`n"))
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $treeHash = ([BitConverter]::ToString($sha.ComputeHash($payload))).Replace('-', '').ToLowerInvariant()
    }
    finally {
        $sha.Dispose()
    }
    return [ordered]@{ path = $root; fileCount = $files.Count; byteCount = $bytes; treeSha256 = $treeHash }
}

function Add-Check([string]$Name, [bool]$Passed, $Detail) {
    $checks.Add([ordered]@{ name = $Name; passed = $Passed; detail = $Detail })
}

function Write-AtomicJson([string]$Path, $Value) {
    $parent = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }
    $json = $Value | ConvertTo-Json -Depth 100
    $tmp = "$Path.$([Guid]::NewGuid().ToString('N')).tmp"
    [System.IO.File]::WriteAllText($tmp, $json + "`n", (New-Object System.Text.UTF8Encoding($false)))
    Move-Item -LiteralPath $tmp -Destination $Path
}

$auditPath = Join-Path $resolvedProject 'Research\Gate13R_RQAligned_PreWrite_Preservation_Audit.v1.json'
$audit = Get-Content -LiteralPath $auditPath -Raw | ConvertFrom-Json
foreach ($rootEvidence in $audit.protectedRoots) {
    $actual = Get-TreeIdentity $rootEvidence.path
    $passed = ($actual.fileCount -eq $rootEvidence.fileCount -and $actual.byteCount -eq $rootEvidence.byteCount -and $actual.treeSha256 -eq $rootEvidence.treeSha256)
    Add-Check "protected-root:$($rootEvidence.role)" $passed ([ordered]@{ expected = $rootEvidence; actual = $actual })
}
foreach ($fileEvidence in $audit.protectedFiles) {
    $path = Join-Path $resolvedProject $fileEvidence.path
    $item = Get-Item -LiteralPath $path
    $actualSha = Get-Sha256 $path
    Add-Check "protected-file:$($fileEvidence.path)" ($item.Length -eq $fileEvidence.byteCount -and $actualSha -eq $fileEvidence.sha256) ([ordered]@{ byteCount = $item.Length; sha256 = $actualSha })
}

$bundlePath = Join-Path $resolvedProject 'Research\FormalScenarios\Gate11R_5pct\v1\bundle-manifest.json'
Add-Check 'gate11r-bundle-manifest-sha256' ((Get-Sha256 $bundlePath) -eq '5baaeec18344a9e99e55da38f3c4875b7e7e9f3bf0add9d5f2d2f1e821b5f7fc') (Get-Sha256 $bundlePath)

$formalRoot = Join-Path $resolvedProject 'Research\FormalRuns\Gate13R_Serial_10pct\v2'
Add-Check 'formal-root-absent' (-not (Test-Path -LiteralPath $formalRoot)) $formalRoot

$staticJson = @(
    'Research\Gate13R_RQAligned_Preregistration_Authorization.v1.json',
    'Research\Gate13R_RQAligned_PreWrite_Preservation_Audit.v1.json',
    'Research\Gate13R_RQAligned_Preregistration_Amendment.v1.json',
    'Research\Gate13R_RQAligned_Metric_Registry.v1.json',
    'Research\Gate13R_RQAligned_Contrast_Registry.v1.json',
    'Research\Gate13R_RQAligned_Preregistration_Provenance.v1.json'
)
foreach ($relative in $staticJson) {
    $path = Join-Path $resolvedProject $relative
    try {
        Get-Content -LiteralPath $path -Raw | ConvertFrom-Json | Out-Null
        Add-Check "json-parse:$relative" $true $null
    }
    catch {
        Add-Check "json-parse:$relative" $false $_.Exception.Message
    }
}

$metricRegistry = Get-Content -LiteralPath (Join-Path $resolvedProject 'Research\Gate13R_RQAligned_Metric_Registry.v1.json') -Raw | ConvertFrom-Json
$contrastRegistry = Get-Content -LiteralPath (Join-Path $resolvedProject 'Research\Gate13R_RQAligned_Contrast_Registry.v1.json') -Raw | ConvertFrom-Json
Add-Check 'metric-registry-exactly-ten' ($metricRegistry.metrics.Count -eq 10) $metricRegistry.metrics.Count
Add-Check 'contrast-registry-exactly-five' ($contrastRegistry.contrasts.Count -eq 5) $contrastRegistry.contrasts.Count
Add-Check 'c5-two-sided' (($contrastRegistry.contrasts | Where-Object { $_.id -eq 'C5' }).sharedGoalSidedness -eq 'TWO-SIDED') (($contrastRegistry.contrasts | Where-Object { $_.id -eq 'C5' }).sharedGoalSidedness)
Add-Check 'p1-only-confirmatory' (($metricRegistry.metrics | Where-Object { $_.role -eq 'CONFIRMATORY-PRIMARY' }).id -eq 'P1') (($metricRegistry.metrics | Where-Object { $_.role -eq 'CONFIRMATORY-PRIMARY' }).id)

$analysisFiles = @(
    'metric-observability-audit.json',
    'gate12r-v4-contrast-variance-reanalysis.json',
    'heterogeneous-order-audit.json',
    'estimability-matrix.json',
    'candidate-design-sensitivity.json',
    'wallclock-storage-decision-table.json'
)
foreach ($name in $analysisFiles) {
    $path = Join-Path $resolvedAnalysis $name
    $pathA = Join-Path $resolvedA $name
    $pathB = Join-Path $resolvedB $name
    $exists = (Test-Path -LiteralPath $path) -and (Test-Path -LiteralPath $pathA) -and (Test-Path -LiteralPath $pathB)
    Add-Check "analysis-file-present:$name" $exists $path
    if ($exists) {
        $hash = Get-Sha256 $path
        $hashA = Get-Sha256 $pathA
        $hashB = Get-Sha256 $pathB
        Add-Check "deterministic-regeneration:$name" ($hash -eq $hashA -and $hashA -eq $hashB) ([ordered]@{ final = $hash; dryRunA = $hashA; dryRunB = $hashB })
        try {
            Get-Content -LiteralPath $path -Raw | ConvertFrom-Json | Out-Null
            Add-Check "analysis-json-parse:$name" $true $null
        }
        catch {
            Add-Check "analysis-json-parse:$name" $false $_.Exception.Message
        }
    }
}

$observability = Get-Content -LiteralPath (Join-Path $resolvedAnalysis 'metric-observability-audit.json') -Raw | ConvertFrom-Json
Add-Check 'p1-p5-no-instrumentation-gap' (-not $observability.instrumentationGap -and $observability.passed) ([ordered]@{ instrumentationGap = $observability.instrumentationGap; passed = $observability.passed })
Add-Check 'p1-p4-all-1152-finite' (($observability.planningResourceMetrics | Where-Object { $_.metricId -in @('P1','P2','P3','P4') -and $_.presentFiniteCount -eq 1152 }).Count -eq 4) $observability.planningResourceMetrics
$p5Obs = $observability.planningResourceMetrics | Where-Object { $_.metricId -eq 'P5' }
Add-Check 'p5-derived-counts-valid' ($p5Obs.validDerivedCount -eq 1152 -and $p5Obs.invalidDerivedCount -eq 0) $p5Obs
$mVarianceViolation = @($observability.prospectiveGate14RMetrics | Where-Object { $null -ne $_.variance -or $null -ne $_.power -or $null -ne $_.candidateNFormal })
Add-Check 'm1-m5-no-fabricated-variance-power-n' ($mVarianceViolation.Count -eq 0) $mVarianceViolation

$reanalysis = Get-Content -LiteralPath (Join-Path $resolvedAnalysis 'gate12r-v4-contrast-variance-reanalysis.json') -Raw | ConvertFrom-Json
Add-Check 'gate12r-measured-identity' ($reanalysis.source.measuredBlockCount -eq 384 -and $reanalysis.source.measuredSampleCount -eq 1152 -and $reanalysis.source.campaignCount -eq 12 -and $reanalysis.source.uniqueRunIdCount -eq 1152 -and $reanalysis.source.uniqueUnityProcessIdentityCount -eq 384) $reanalysis.source
Add-Check 'p3-slope-not-estimable' ($reanalysis.p3ScalingSlope.estimability -eq 'NOT-ESTIMABLE-FROM-GATE12R-V4') $reanalysis.p3ScalingSlope
$sharedP1 = @($reanalysis.sharedRows | Where-Object { $_.metricId -eq 'P1' -and $_.scope -eq 'PILOT-ANCHOR-POOLED-DESCRIPTIVE' })
Add-Check 'shared-p1-five-contrast-family' ($sharedP1.Count -eq 5 -and @($sharedP1 | Where-Object { $null -ne $_.statistics.holmAdjustedPValue }).Count -eq 5) $sharedP1.Count
$p5Rows = @($reanalysis.p5CountAnalysis.rows)
Add-Check 'p5-zero-events-retained' ($p5Rows.Count -eq 8 -and @($p5Rows | Where-Object { $_.overall.events -eq 0 -and $_.sampleSizeVerdict -eq 'NOT-ESTIMABLE-FROM-ZERO-EVENT-PILOT' }).Count -eq 8) $p5Rows.Count

$hetero = Get-Content -LiteralPath (Join-Path $resolvedAnalysis 'heterogeneous-order-audit.json') -Raw | ConvertFrom-Json
Add-Check 'heterogeneous-96-same-wave' ($hetero.candidateMatchedPairCount -eq 96 -and $hetero.sameWaveCount -eq 96) $hetero
Add-Check 'heterogeneous-order-imbalance-89-7' ($hetero.adjacentCount -eq 89 -and $hetero.cohortOrderCounts.PER_AGENT_THEN_GROUPED -eq 89 -and $hetero.cohortOrderCounts.GROUPED_THEN_PER_AGENT -eq 7) $hetero.cohortOrderCounts
Add-Check 'heterogeneous-verdict-not-effect-driven' ($hetero.supplementalPilotVerdict -eq 'INSUFFICIENT-EVIDENCE-FOR-DECISION') $hetero.supplementalPilotVerdict

$wall = Get-Content -LiteralPath (Join-Path $resolvedAnalysis 'wallclock-storage-decision-table.json') -Raw | ConvertFrom-Json
$s32h32 = $wall.candidates | Where-Object { $_.candidateId -eq 'S32/H32' }
Add-Check 'candidate-s32-h32-arithmetic' ($s32h32.sharedProcesses -eq 1024 -and $s32h32.sharedSamples -eq 4096 -and $s32h32.heterogeneousMatchedSuperblocks -eq 672 -and $s32h32.heterogeneousProcesses -eq 1344 -and $s32h32.heterogeneousSamples -eq 2688 -and $s32h32.totalUnityProcesses -eq 2368 -and $s32h32.totalAlgorithmSamples -eq 6784) $s32h32
Add-Check 'all-six-candidates-present' ($wall.candidates.Count -eq 6) @($wall.candidates.candidateId)
Add-Check 'old-baseline-retained-not-authorized' ($wall.preAmendmentBaseline.totalUnityProcesses -eq 11160 -and $wall.preAmendmentBaseline.totalAlgorithmSamples -eq 31536 -and $wall.preAmendmentBaseline.status -match 'NOT-AUTHORIZED-FOR-LAUNCH') $wall.preAmendmentBaseline
Add-Check 'recommended-candidate-unfrozen' ($wall.recommendedButUnfrozen.candidateId -eq 'S48/H32' -and $wall.recommendedButUnfrozen.status -match 'UNFROZEN') $wall.recommendedButUnfrozen

$sensitivity = Get-Content -LiteralPath (Join-Path $resolvedAnalysis 'candidate-design-sensitivity.json') -Raw | ConvertFrom-Json
Add-Check 'candidate-simulations-stable' (@($sensitivity.candidateRows | Where-Object { -not $_.sharedPrimarySimulation.modelStable }).Count -eq 0) @($sensitivity.candidateRows | ForEach-Object { $_.sharedPrimarySimulation })
Add-Check 'practical-margins-unfrozen' (@($sensitivity.practicalEffectMarginDecisionTable | Where-Object { $_.status -notmatch 'UNFROZEN' }).Count -eq 0) $sensitivity.practicalEffectMarginDecisionTable

$analyzerPath = Join-Path $resolvedProject 'Research\Analyze-Gate13RRQAlignedPreregistrationV1.py'
$analyzerText = Get-Content -LiteralPath $analyzerPath -Raw
$forbiddenInvocationPatterns = @('subprocess\.', 'os\.system\(', 'Popen\(', 'Start-Process\s+.*Unity', 'Unity\.exe', '-batchmode')
$matches = @()
foreach ($pattern in $forbiddenInvocationPatterns) {
    if ($analyzerText -match $pattern) { $matches += $pattern }
}
Add-Check 'static-no-unity-or-process-launch' ($matches.Count -eq 0) $matches

$checkArray = $checks.ToArray()
$failed = @($checkArray | Where-Object { -not $_.passed })
$summary = [ordered]@{
    schemaVersion = 1
    summaryKind = 'gate13r-rq-aligned-preregistration-validation-summary-v1'
    completedAtUtc = [DateTimeOffset]::UtcNow.ToString('o')
    projectPath = $resolvedProject
    analysisRoot = $resolvedAnalysis
    checkCount = $checks.Count
    passedCount = $checks.Count - $failed.Count
    failedCount = $failed.Count
    checks = $checkArray
    unityStarted = $false
    formalCampaignAuthorized = $false
    passed = ($failed.Count -eq 0)
}
Write-AtomicJson $SummaryPath $summary
if ($failed.Count -ne 0) {
    throw "Gate13R-PR1 validation failed: $($failed.Count) hard gate(s). Summary: $SummaryPath"
}
Write-Output "GATE13R_RQALIGNED_VALIDATION_PASS $($checks.Count)/$($checks.Count)"
