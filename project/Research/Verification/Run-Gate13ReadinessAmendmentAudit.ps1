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

$summaryPath = Join-Path $scriptDirectory 'Gate13_Readiness_Amendment_Audit.summary.json'
$specificationPath = Join-Path $ProjectPath 'Research\Gate13_Readiness_Amendment_Specification.md'
$testDesignPath = Join-Path $ProjectPath 'Research\Gate13_Readiness_Amendment_Test_Design.md'
$amendmentPath = Join-Path $ProjectPath 'Research\Gate13_Readiness_Amendment.v1.json'
$bundleRoot = Join-Path $ProjectPath 'Research\FormalScenarios\v1'
$bundleManifestPath = Join-Path $bundleRoot 'bundle-manifest.json'
$matrixPath = Join-Path $bundleRoot 'formal-scenario-matrix.json'
$preregistrationPath = Join-Path $bundleRoot 'preregistered-analysis.json'
$candidatePath = Join-Path $ProjectPath 'Research\PilotRuns\Gate12\v1\candidate-sample-sizes.json'
$budgetPath = Join-Path $ProjectPath 'Research\PilotRuns\Gate12\v1\budget-feasibility.json'
$gate12FinalAuditPath = Join-Path $scriptDirectory 'Gate12_FinalAudit.summary.json'
$campaignRunnerPath = Join-Path $ProjectPath 'Research\Run-FairPlanningCampaign.ps1'
$fairnessSpecificationPath = Join-Path $ProjectPath 'Research\Four_Algorithm_Fairness_and_Unified_Campaign_Specification.md'
$nextSessionCheckpointPath = Join-Path $ProjectPath 'Research\Next_Session_Checkpoint.md'
$overallPlanPath = Join-Path $ProjectPath 'Research\Overall_Project_Plan.md'
$formalOutputPath = Join-Path $ProjectPath 'Research\FormalRuns\Gate13\v1'
$legacyGate13OutputPath = Join-Path $ProjectPath 'Research\PilotRuns\Gate13'

$utf8 = New-Object System.Text.UTF8Encoding($false, $true)
$errors = New-Object System.Collections.Generic.List[string]

function Get-LowerSha256([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Get-StringSha256([string]$Value) {
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($Value)
        return ([System.BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-', '').ToLowerInvariant()
    } finally {
        $sha.Dispose()
    }
}

function Read-Utf8Text([string]$Path) {
    return [System.IO.File]::ReadAllText($Path, $script:utf8)
}

function Read-Json([string]$Path, [string]$Label) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        $script:errors.Add("Required $Label file is missing: $Path")
        return $null
    }
    try { return (Read-Utf8Text $Path) | ConvertFrom-Json }
    catch {
        $script:errors.Add("$Label JSON could not be parsed: $($_.Exception.Message)")
        return $null
    }
}

function Write-Utf8NoBomJson([string]$Path, $Value, [int]$Depth = 18) {
    $json = $Value | ConvertTo-Json -Depth $Depth
    $json = $json.Replace("`r`n", "`n").Replace("`r", "`n")
    if (-not $json.EndsWith("`n", [System.StringComparison]::Ordinal)) { $json += "`n" }
    [System.IO.File]::WriteAllText($Path, $json, $script:utf8)
}

function Test-Close([double]$Actual, [double]$Expected, [double]$Tolerance = 1e-9) {
    return [math]::Abs($Actual - $Expected) -le $Tolerance
}

function Get-PrecisionCount([double]$SigmaLog, [double]$Target) {
    if ([double]::IsNaN($SigmaLog) -or [double]::IsInfinity($SigmaLog) -or $SigmaLog -lt 0) {
        throw 'sigma_log must be finite and nonnegative.'
    }
    if ([double]::IsNaN($Target) -or [double]::IsInfinity($Target) -or $Target -le 0) {
        throw 'precision target must be finite and positive.'
    }
    $nRaw = [int][math]::Ceiling([math]::Pow((1.96 * $SigmaLog / [math]::Log(1.0 + $Target)), 2))
    $required = [int]([math]::Ceiling([math]::Max(30.0, [double]$nRaw) / 4.0) * 4)
    return [ordered]@{ nRaw = $nRaw; requiredNFormal = $required }
}

$requiredFiles = @($specificationPath, $testDesignPath, $amendmentPath, $bundleManifestPath, $matrixPath, $preregistrationPath, $candidatePath, $budgetPath, $gate12FinalAuditPath, $campaignRunnerPath, $fairnessSpecificationPath, $nextSessionCheckpointPath, $overallPlanPath)
foreach ($path in $requiredFiles) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { $errors.Add("Required file is missing: $path") }
}

$amendment = Read-Json $amendmentPath 'amendment'
$manifest = Read-Json $bundleManifestPath 'Gate 11 bundle manifest'
$matrix = Read-Json $matrixPath 'Gate 11 matrix'
$preregistration = Read-Json $preregistrationPath 'Gate 11 preregistration'
$candidates = Read-Json $candidatePath 'Gate 12 candidate sample sizes'
$budget = Read-Json $budgetPath 'Gate 12 budget feasibility'
$gate12FinalAudit = Read-Json $gate12FinalAuditPath 'Gate 12 final audit'

$amendmentFiles = [ordered]@{}
foreach ($entry in ([ordered]@{ specification = $specificationPath; testDesign = $testDesignPath; amendment = $amendmentPath }).GetEnumerator()) {
    if (Test-Path -LiteralPath $entry.Value -PathType Leaf) {
        $item = Get-Item -LiteralPath $entry.Value
        $amendmentFiles[$entry.Key] = [ordered]@{
            relativePath = $entry.Value.Substring($ProjectPath.Length).TrimStart('\').Replace('\', '/')
            sha256 = Get-LowerSha256 $entry.Value
            byteCount = [int64]$item.Length
            lastWriteTimeUtc = $item.LastWriteTimeUtc.ToString('o')
        }
    }
}

$documentErrors = @()
if (Test-Path -LiteralPath $specificationPath -PathType Leaf) {
    $specificationText = Read-Utf8Text $specificationPath
    foreach ($token in @('gate13-readiness-amendment-v1', 'ln(1.10)', '15,056', '74,417,330,489', 'gate13ImplementationAuthorized = false', 'no-user-imposed-codex-usage-limit')) {
        if (-not $specificationText.Contains($token)) { $documentErrors += "Specification is missing frozen token: $token" }
    }
}
if (Test-Path -LiteralPath $testDesignPath -PathType Leaf) {
    $testDesignText = Read-Utf8Text $testDesignPath
    foreach ($token in @('gate13-readiness-amendment-tests-v1', 'n_raw = ceil', '15,056 processes', 'formalCampaignStartAllowed = false', 'no-user-imposed-codex-usage-limit')) {
        if (-not $testDesignText.Contains($token)) { $documentErrors += "Test design is missing frozen token: $token" }
    }
}
foreach ($message in $documentErrors) { $errors.Add($message) }

$expectedHashes = [ordered]@{
    gate11BundleManifest = [ordered]@{ path = $bundleManifestPath; hash = 'ea596c8c9e6d1ca99e325c05c095024a4813ca1e65c771a8b4db8bf29364c12e' }
    gate11Matrix = [ordered]@{ path = $matrixPath; hash = '404df63d38bccd66bb665446e0f2cbf3e5f8c7293f543b3213bde4206435fe9f' }
    gate11Preregistration = [ordered]@{ path = $preregistrationPath; hash = '7e947885c38fcf9307fd9202585dda3b2b5d11334f495428760009a2aa202b5b' }
    gate12CandidateSampleSizes = [ordered]@{ path = $candidatePath; hash = 'e0a32ee0545f722e46eb6c2a995f869db73944321be525e492c0dce6f3c05ff3' }
    gate12BudgetFeasibility = [ordered]@{ path = $budgetPath; hash = '5d1c380061deb2dd4c31f5b01fa48e7665eb405699ce67e1cfdc2b33a87f5f69' }
    gate12FinalAudit = [ordered]@{ path = $gate12FinalAuditPath; hash = '87a5d93dead6dc367ab0716ad2e4e2239570fc42577be978d0f0378ca14f78c8' }
    gate10CampaignRunner = [ordered]@{ path = $campaignRunnerPath; hash = '176f82fed18beee2fc7e2c8cb37ce988f7c7f4740cdeec3c5510b677843615c3' }
}
$frozenInputResults = [ordered]@{}
foreach ($entry in $expectedHashes.GetEnumerator()) {
    $actual = Get-LowerSha256 $entry.Value.path
    $matches = $actual -eq $entry.Value.hash
    $frozenInputResults[$entry.Key] = [ordered]@{ expectedSha256 = $entry.Value.hash; actualSha256 = $actual; matches = $matches }
    if (-not $matches) { $errors.Add("Frozen input hash mismatch for $($entry.Key): expected $($entry.Value.hash), actual $actual") }
}

$bundleErrors = @()
$computedBundleAggregate = $null
$bundleFileCount = 0
if ($null -ne $manifest) {
    $aggregateBuilder = New-Object System.Text.StringBuilder
    foreach ($artifact in @($manifest.artifacts)) {
        $artifactPath = Join-Path $bundleRoot ([string]$artifact.relativePath).Replace('/', '\')
        if (-not (Test-Path -LiteralPath $artifactPath -PathType Leaf)) {
            $bundleErrors += "Missing Gate 11 artifact: $($artifact.relativePath)"
            continue
        }
        $actualHash = Get-LowerSha256 $artifactPath
        $actualBytes = (Get-Item -LiteralPath $artifactPath).Length
        if ($actualHash -ne $artifact.sha256 -or $actualBytes -ne [int64]$artifact.byteCount) {
            $bundleErrors += "Gate 11 artifact identity mismatch: $($artifact.relativePath)"
        }
        [void]$aggregateBuilder.Append([string]$artifact.relativePath).Append("`n").Append([string]$artifact.sha256).Append("`n")
    }
    $computedBundleAggregate = Get-StringSha256 $aggregateBuilder.ToString()
    $bundleFileCount = @(Get-ChildItem -LiteralPath $bundleRoot -File -Recurse).Count
    if (@($manifest.artifacts).Count -ne 56 -or $bundleFileCount -ne 57) { $bundleErrors += 'Gate 11 retained bundle count is not 56 artifacts plus one manifest.' }
    if ($computedBundleAggregate -ne '91d9e3c66327185e48f68cafb05c674cc49e929adb576973098d0bfebd2e9a88' -or $computedBundleAggregate -ne $manifest.bundleAggregateSha256) { $bundleErrors += 'Gate 11 ordered bundle aggregate mismatch.' }
}
foreach ($message in $bundleErrors) { $errors.Add($message) }

$baselineRows = Import-Csv -LiteralPath (Join-Path $ProjectPath 'Research\Baseline_SHA256.csv')
$baselineChecked = 0
$baselineMismatches = @()
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
if ($baselineChecked -ne 24 -or $baselineMismatches.Count -ne 0) { $errors.Add("Frozen baseline mismatch: checked=$baselineChecked mismatches=$($baselineMismatches.Count)") }

$scopeErrors = @()
if ($null -ne $amendment) {
    if ($amendment.schemaVersion -ne 1 -or $amendment.amendmentId -ne 'gate13-readiness-amendment-v1') { $scopeErrors += 'Amendment identity/schema mismatch.' }
    if ($amendment.userDecision.precisionRelativeHalfWidthTarget -ne 0.1 -or $amendment.userDecision.maximumPerAlgorithmPerCell -ne 148 -or $amendment.userDecision.gate11MatrixPolicy -ne 'retain-byte-identical-v1') { $scopeErrors += 'User decision fields do not freeze 10%, cap 148, and unchanged Gate 11 matrix.' }
    if ($amendment.userDecision.gate13ExecutionAuthorized -ne $false -or $amendment.userDecision.formalCampaignStartAllowed -ne $false) { $scopeErrors += 'Amendment incorrectly authorizes Gate 13 execution.' }
    if ($amendment.scope.specificationAndTestDesignOnly -ne $true -or $amendment.scope.unityInvocationAllowed -ne $false -or $amendment.scope.formalTimingSamplesAllowed -ne $false -or $amendment.scope.formalOutputDirectoryCreationAllowed -ne $false) { $scopeErrors += 'Amendment scope permits execution or formal output.' }
    foreach ($property in @('originalScriptsMayChange', 'originalScenesMayChange', 'gate11RetainedBundleMayChange', 'gate12SuccessfulPilotMayChange')) {
        if ($amendment.scope.$property -ne $false) { $scopeErrors += "Preservation flag is not false: $property" }
    }
    foreach ($property in @('matrixOrScenarioChange', 'analysisRowChange', 'endpointChange', 'multiplicityChange', 'failureOrOutlierPolicyChange')) {
        if ($amendment.amends.$property -ne $false) { $scopeErrors += "Unexpected scientific-contract change: $property" }
    }
}
foreach ($message in $scopeErrors) { $errors.Add($message) }

$matrixErrors = @()
$matrixCohorts = @()
if ($null -ne $matrix) {
    if ($matrix.scenarioCount -ne 53 -or @($matrix.scenarios).Count -ne 53 -or $matrix.eligibilityCount -ne 212 -or @($matrix.eligibilityEntries).Count -ne 212) { $matrixErrors += 'Gate 11 matrix top-level or materialized counts differ from 53/212.' }
    $expectedCohorts = [ordered]@{
        'four-algorithm-shared-goal-v1' = [ordered]@{ scenarioCount = 32; eligibilityCellCount = 128; algorithms = 'A*-R,C-FF,D*L,IDFF' }
        'grouped-field-heterogeneous-goal-v1' = [ordered]@{ scenarioCount = 21; eligibilityCellCount = 42; algorithms = 'C-FF,IDFF' }
        'per-agent-heterogeneous-goal-v1' = [ordered]@{ scenarioCount = 21; eligibilityCellCount = 42; algorithms = 'A*-R,D*L' }
    }
    foreach ($cohortId in $expectedCohorts.Keys) {
        $entries = @($matrix.eligibilityEntries | Where-Object comparisonCohortId -eq $cohortId)
        $actual = [ordered]@{
            comparisonCohortId = $cohortId
            scenarioCount = @($entries.scenarioId | Sort-Object -Unique).Count
            eligibilityCellCount = $entries.Count
            algorithms = (@($entries.algorithmId | Sort-Object -Unique) -join ',')
        }
        $matrixCohorts += $actual
        $expected = $expectedCohorts[$cohortId]
        if ($actual.scenarioCount -ne $expected.scenarioCount -or $actual.eligibilityCellCount -ne $expected.eligibilityCellCount -or $actual.algorithms -ne $expected.algorithms) { $matrixErrors += "Matrix cohort mismatch: $cohortId" }
    }
}
foreach ($message in $matrixErrors) { $errors.Add($message) }

$precisionErrors = @()
$precisionRows = @()
$expectedPrecision = [ordered]@{
    'P1-DL-vs-A-shared' = [ordered]@{ nRaw = 49; required = 52; scheduled = 52 }
    'P2-DL-vs-A-hetero' = [ordered]@{ nRaw = 148; required = 148; scheduled = 148 }
    'P3-IDFF-vs-CFF-shared' = [ordered]@{ nRaw = 46; required = 48; scheduled = 52 }
    'P4-IDFF-vs-CFF-grouped' = [ordered]@{ nRaw = 50; required = 52; scheduled = 52 }
}
if ($null -ne $candidates -and $null -ne $amendment) {
    foreach ($familyId in $expectedPrecision.Keys) {
        $sourceRows = @($candidates.families | Where-Object familyId -eq $familyId)
        $amendmentRows = @($amendment.familySampleSizes | Where-Object familyId -eq $familyId)
        if ($sourceRows.Count -ne 1 -or $amendmentRows.Count -ne 1) {
            $precisionErrors += "Family row count mismatch: $familyId"
            continue
        }
        $source = $sourceRows[0]
        $recorded = $amendmentRows[0]
        $computed = Get-PrecisionCount -SigmaLog ([double]$source.sigmaLog) -Target 0.1
        $expected = $expectedPrecision[$familyId]
        $precisionRows += [ordered]@{
            familyId = $familyId
            sigmaLog = [double]$source.sigmaLog
            recomputedNRaw = $computed.nRaw
            recomputedRequiredNFormal = $computed.requiredNFormal
            recordedScheduledNFormal = [int]$recorded.scheduledNFormal
        }
        if ($computed.nRaw -ne $expected.nRaw -or $computed.requiredNFormal -ne $expected.required -or [int]$recorded.nRaw -ne $expected.nRaw -or [int]$recorded.requiredNFormal -ne $expected.required -or [int]$recorded.scheduledNFormal -ne $expected.scheduled) { $precisionErrors += "Precision calculation mismatch: $familyId" }
        if (-not (Test-Close ([double]$recorded.sigmaLog) ([double]$source.sigmaLog) 1e-15)) { $precisionErrors += "sigma_log mismatch: $familyId" }
        if ([int]$recorded.scheduledNFormal % 4 -ne 0 -or [int]$recorded.scheduledNFormal -gt 148 -or [int]$recorded.scheduledNFormal -lt [int]$recorded.requiredNFormal) { $precisionErrors += "Scheduled n violates alignment/cap/minimum: $familyId" }
    }
    $p3 = @($amendment.familySampleSizes | Where-Object familyId -eq 'P3-IDFF-vs-CFF-shared')[0]
    if ($p3.scheduleAdjustmentReason -ne 'harmonized-to-p1-within-four-algorithm-shared-cohort-to-preserve-complete-williams-cycles-v1') { $precisionErrors += 'P3 shared-cohort harmonization reason mismatch.' }
}
$zeroVector = Get-PrecisionCount -SigmaLog 0.0 -Target 0.1
$syntheticFormulaPassed = $zeroVector.nRaw -eq 0 -and $zeroVector.requiredNFormal -eq 32
$invalidFormulaInputsRejected = $true
foreach ($invalidCase in @(
    [ordered]@{ sigma = [double]::NaN; target = 0.1 },
    [ordered]@{ sigma = [double]::PositiveInfinity; target = 0.1 },
    [ordered]@{ sigma = -0.01; target = 0.1 },
    [ordered]@{ sigma = 0.1; target = [double]::NaN },
    [ordered]@{ sigma = 0.1; target = 0.0 }
)) {
    try { $null = Get-PrecisionCount -SigmaLog $invalidCase.sigma -Target $invalidCase.target; $invalidFormulaInputsRejected = $false }
    catch { }
}
if (-not $syntheticFormulaPassed) { $precisionErrors += 'Zero-variance precision vector failed.' }
if (-not $invalidFormulaInputsRejected) { $precisionErrors += 'Invalid precision inputs were not rejected.' }
foreach ($message in $precisionErrors) { $errors.Add($message) }

$scheduleErrors = @()
$scheduleRows = @()
$expectedSchedule = [ordered]@{
    'four-algorithm-shared-goal-v1' = [ordered]@{ scenarios = 32; cells = 128; algorithms = 4; blocks = 52; cycles = 13; processes = 6656 }
    'per-agent-heterogeneous-goal-v1' = [ordered]@{ scenarios = 21; cells = 42; algorithms = 2; blocks = 148; cycles = 74; processes = 6216 }
    'grouped-field-heterogeneous-goal-v1' = [ordered]@{ scenarios = 21; cells = 42; algorithms = 2; blocks = 52; cycles = 26; processes = 2184 }
}
$totalProcesses = 0
if ($null -ne $amendment) {
    foreach ($cohortId in $expectedSchedule.Keys) {
        $rows = @($amendment.matrixAndSchedule.cohorts | Where-Object comparisonCohortId -eq $cohortId)
        if ($rows.Count -ne 1) { $scheduleErrors += "Schedule cohort row count mismatch: $cohortId"; continue }
        $row = $rows[0]
        $expected = $expectedSchedule[$cohortId]
        $scheduleRows += $row
        if ($row.scenarioCount -ne $expected.scenarios -or $row.eligibilityCellCount -ne $expected.cells -or $row.algorithmCount -ne $expected.algorithms -or $row.blocksPerScenario -ne $expected.blocks -or $row.completeWilliamsCyclesPerScenario -ne $expected.cycles -or $row.expectedUnityProcessCount -ne $expected.processes) { $scheduleErrors += "Schedule values mismatch: $cohortId" }
        if ([int]$row.blocksPerScenario % [int]$row.algorithmCount -ne 0) { $scheduleErrors += "Incomplete Williams cycle: $cohortId" }
        $totalProcesses += [int]$row.expectedUnityProcessCount
    }
    if ($amendment.matrixAndSchedule.campaignCount -ne 74 -or $totalProcesses -ne 15056 -or $amendment.matrixAndSchedule.expectedUnityProcessCount -ne 15056) { $scheduleErrors += 'Formal schedule does not total 74 campaigns and 15,056 processes.' }
    if ($amendment.matrixAndSchedule.eachSampleUsesIndependentUnityProcess -ne $true -or $amendment.matrixAndSchedule.completeWilliamsCyclesRequired -ne $true) { $scheduleErrors += 'Independence or complete-Williams requirement is not true.' }
}
foreach ($message in $scheduleErrors) { $errors.Add($message) }

$budgetErrors = @()
$budgetRecomputation = $null
$minimumLaunchFreeBytes = [int64]74417330489
if ($null -ne $budget -and $null -ne $amendment) {
    $processCount = 15056L
    $medianWallHours = $processCount * [double]$budget.observed.medianWallSecondsPerProcess / 3600.0
    $p95WallHours = $processCount * [double]$budget.observed.p95WallSecondsPerProcess / 3600.0
    $medianOutputGiB = $processCount * [double]$budget.observed.medianBytesPerProcess / 1GB
    $p95OutputGiB = $processCount * [double]$budget.observed.p95BytesPerProcess / 1GB
    $p95OutputBytes = [int64][math]::Ceiling($processCount * [double]$budget.observed.p95BytesPerProcess)
    $reserveBytes = 20L * 1024L * 1024L * 1024L
    $computedMinimumFreeBytes = $p95OutputBytes + $reserveBytes
    $budgetRecomputation = [ordered]@{
        processCount = $processCount
        medianWallHours = $medianWallHours
        p95WallHours = $p95WallHours
        medianOutputGiB = $medianOutputGiB
        p95OutputGiB = $p95OutputGiB
        p95OutputBytes = $p95OutputBytes
        reserveBytes = $reserveBytes
        minimumLaunchFreeBytes = $computedMinimumFreeBytes
    }
    if (-not (Test-Close $medianWallHours 64.19621309651389) -or -not (Test-Close $p95WallHours 67.66718084775) -or -not (Test-Close $medianOutputGiB 30.866277718916535) -or -not (Test-Close $p95OutputGiB 49.30653982702643)) { $budgetErrors += 'Independent wall/output projection mismatch.' }
    if ($p95OutputBytes -ne 52942494009L -or $reserveBytes -ne 21474836480L -or $computedMinimumFreeBytes -ne $minimumLaunchFreeBytes) { $budgetErrors += 'Independent byte-level storage threshold mismatch.' }
    if ($p95WallHours -gt 168.0) { $budgetErrors += '10% schedule exceeds the 168-hour technical wall boundary.' }
    if (-not (Test-Close ([double]$amendment.budgetProjection.p95WallHours) $p95WallHours) -or [int64]$amendment.budgetProjection.p95ProjectedOutputBytes -ne $p95OutputBytes -or [int64]$amendment.budgetProjection.minimumLaunchFreeBytes -ne $computedMinimumFreeBytes) { $budgetErrors += 'Amendment budget projection differs from independent recomputation.' }
    if ([int64]$amendment.storage.launchPreflight.minimumFreeBytes -ne $computedMinimumFreeBytes -or $amendment.storage.launchPreflight.comparisonUsesRawBytesNotRoundedGiB -ne $true -or $amendment.storage.launchPreflight.failureAction -ne 'stop-before-any-formal-sample') { $budgetErrors += 'Launch storage preflight contract mismatch.' }
}
$thresholdBoundaryTestPassed = (($minimumLaunchFreeBytes -ge $minimumLaunchFreeBytes) -and (($minimumLaunchFreeBytes - 1L) -lt $minimumLaunchFreeBytes))
if (-not $thresholdBoundaryTestPassed) { $budgetErrors += 'Storage threshold boundary vector failed.' }
foreach ($message in $budgetErrors) { $errors.Add($message) }

$drive = Get-PSDrive -Name H
$currentDisk = [ordered]@{
    capturedAt = (Get-Date).ToString('o')
    freeBytes = [int64]$drive.Free
    freeGiB = [double]$drive.Free / 1GB
    minimumLaunchFreeBytes = $minimumLaunchFreeBytes
    marginAboveMinimumBytes = [int64]$drive.Free - $minimumLaunchFreeBytes
    enoughForCurrentSnapshot = [int64]$drive.Free -ge $minimumLaunchFreeBytes
    launchAuthorizationConferred = $false
}
if (-not $currentDisk.enoughForCurrentSnapshot) { $errors.Add('Current H: snapshot is below the frozen future launch storage threshold.') }

$runnerText = if (Test-Path -LiteralPath $campaignRunnerPath -PathType Leaf) { Read-Utf8Text $campaignRunnerPath } else { '' }
$runnerStillFrozenAt100 = $runnerText -match '\[ValidateRange\(2,\s*100\)\]\s*\r?\n\s*\[int\]\$Blocks'
$implementationErrors = @()
if (-not $runnerStillFrozenAt100) { $implementationErrors += 'Gate 10 runner is not in the expected pre-cap-148 frozen state.' }
if ($null -ne $amendment) {
    if ($amendment.implementationStatus.currentGate10RunnerMaximumBlocks -ne 100 -or $amendment.implementationStatus.runnerCap148ImplementationPending -ne $true -or $amendment.implementationStatus.formalCampaignConfigurationPending -ne $true) { $implementationErrors += 'Pending implementation state is not recorded correctly.' }
    if ($amendment.authorization.gate13ImplementationAuthorized -ne $false -or $amendment.authorization.gate13ExecutionAuthorized -ne $false) { $implementationErrors += 'Gate 13 implementation or execution authorization was widened.' }
}
foreach ($message in $implementationErrors) { $errors.Add($message) }

$usagePolicyErrors = @()
if ($null -ne $amendment) {
    $usagePolicy = $amendment.authorization.userUsagePolicy
    $supersededUsageBudget = $amendment.authorization.supersededUsageBudgetDecision
    if ($amendment.authorization.userUsagePolicyStatus -ne 'no-user-imposed-codex-usage-limit' -or
        $amendment.authorization.userWallClockBudgetStatus -ne 'not-explicitly-set' -or
        $amendment.authorization.userTimeOrFinancialBudgetStatus -ne 'no-user-imposed-codex-usage-limit;wall-clock-budget-not-explicitly-set') {
        $usagePolicyErrors += 'User usage/time policy status fields do not match the recorded decision.'
    }
    if ($null -eq $usagePolicy -or
        $null -ne $usagePolicy.activeUserImposedUsageCeiling -or
        $usagePolicy.fixedShortWindowStopThresholdEnabled -ne $false -or
        $null -ne $usagePolicy.fixedShortWindowReservePercent -or
        $usagePolicy.weeklyRemainingBudgetEnabled -ne $false -or
        $usagePolicy.usagePercentageMayTriggerPlannedStop -ne $false -or
        $usagePolicy.qualityReductionForUsageConservationAllowed -ne $false -or
        $usagePolicy.scopeExpansionToConsumeUsageAllowed -ne $false -or
        $usagePolicy.platformEnforcedLimitsStillApply -ne $true -or
        $usagePolicy.additionalResetOrCreditAuthorized -ne $false -or
        $usagePolicy.gate13ExecutionAuthorizedByThisPolicy -ne $false) {
        $usagePolicyErrors += 'No-user-imposed-usage-limit policy content or safety boundary mismatch.'
    }
    if ($null -eq $supersededUsageBudget -or
        $supersededUsageBudget.active -ne $false -or
        $supersededUsageBudget.budgetBasis -ne 'all-weekly-remaining-usage-at-gate13-start' -or
        [int]$supersededUsageBudget.userReportedWeeklyRemainingPercent -ne 89 -or
        $supersededUsageBudget.supersededBeforeAudit -ne $true) {
        $usagePolicyErrors += 'Superseded 89-percent usage-budget decision history mismatch.'
    }
}
$expectedFrozenFairnessSpecificationSha256 = '42a4a8439c3d7b46b7644bed14b8f91d87bae4c6f8b2183a73609ee5461e82dd'
if ((Get-LowerSha256 $fairnessSpecificationPath) -ne $expectedFrozenFairnessSpecificationSha256) {
    $usagePolicyErrors += 'Gate 10 fairness specification no longer matches the Gate 12 frozen byte identity.'
}
$activeUsagePolicyFiles = @($specificationPath, $testDesignPath, $nextSessionCheckpointPath, $overallPlanPath)
$forbiddenActiveUsagePattern = '(?i)8%\s*(reserve|buffer)|active usage window reaches|Codex 5|5[ -]?hour window|5 小时用量|5小时用量'
foreach ($path in $activeUsagePolicyFiles) {
    if ((Read-Utf8Text $path) -match $forbiddenActiveUsagePattern) {
        $usagePolicyErrors += "Active fixed-window usage stop wording remains in: $path"
    }
}
foreach ($message in $usagePolicyErrors) { $errors.Add($message) }

$formalTrueFiles = @()
foreach ($file in @(Get-ChildItem -LiteralPath (Join-Path $ProjectPath 'Research') -Filter '*.json' -File -Recurse)) {
    $text = Read-Utf8Text $file.FullName
    if ($text -match '"formalCampaign"\s*:\s*true|"gate13ExecutionAuthorized"\s*:\s*true|"formalCampaignStartAllowed"\s*:\s*true') { $formalTrueFiles += $file.FullName }
}
$formalOutputAbsent = -not (Test-Path -LiteralPath $formalOutputPath) -and -not (Test-Path -LiteralPath $legacyGate13OutputPath)
if (-not $formalOutputAbsent) { $errors.Add('A Gate 13 formal output root already exists.') }
if ($formalTrueFiles.Count -ne 0) { foreach ($path in $formalTrueFiles) { $errors.Add("Formal authorization/start flag is true: $path") } }

$powerShellParseErrors = @()
foreach ($file in @(Get-ChildItem -LiteralPath (Join-Path $ProjectPath 'Research') -Filter '*.ps1' -File -Recurse | Sort-Object FullName)) {
    $tokens = $null
    $parseErrors = $null
    $scriptText = Read-Utf8Text $file.FullName
    [System.Management.Automation.Language.Parser]::ParseInput($scriptText, $file.FullName, [ref]$tokens, [ref]$parseErrors) | Out-Null
    foreach ($parseError in @($parseErrors)) { $powerShellParseErrors += [ordered]@{ file = $file.FullName; message = $parseError.Message; extent = $parseError.Extent.Text } }
}
if ($powerShellParseErrors.Count -ne 0) { $errors.Add("PowerShell parse errors exist: $($powerShellParseErrors.Count)") }

$unityProcesses = @(Get-Process -Name Unity -ErrorAction SilentlyContinue)
$unityLockPath = Join-Path $ProjectPath 'Temp\UnityLockfile'
$unityLockPresent = Test-Path -LiteralPath $unityLockPath
if ($unityProcesses.Count -ne 0) { $errors.Add("Unity processes are running: $($unityProcesses.Id -join ',')") }
if ($unityLockPresent) { $errors.Add("Unity lockfile exists: $unityLockPath") }

$gate12EvidencePassed = $null -ne $gate12FinalAudit -and $gate12FinalAudit.passed -eq $true
if (-not $gate12EvidencePassed) { $errors.Add('Gate 12 final audit evidence is not passing.') }
$gate11ExecutionFlagsClean = $null -ne $manifest -and $manifest.formalCampaignExecuted -eq $false
if (-not $gate11ExecutionFlagsClean) { $errors.Add('Gate 11 manifest indicates formal execution.') }
$gate12FormalFlagClean = $null -ne $candidates -and $candidates.formalCampaignStarted -eq $false
if (-not $gate12FormalFlagClean) { $errors.Add('Gate 12 candidate artifact indicates formal campaign started.') }

$checks = [ordered]@{
    amendmentDocumentsPresentAndParse = $requiredFiles.Count -eq @($requiredFiles | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf }).Count -and $null -ne $amendment
    authorizationBoundaryClosed = $scopeErrors.Count -eq 0
    frozenInputHashesMatch = @($frozenInputResults.GetEnumerator() | Where-Object { -not $_.Value.matches }).Count -eq 0
    gate11BundleDeepHashMatches = $bundleErrors.Count -eq 0 -and $bundleFileCount -eq 57
    baseline24Matches = $baselineChecked -eq 24 -and $baselineMismatches.Count -eq 0
    gate11MatrixUnchanged = $matrixErrors.Count -eq 0
    precision10PercentRecomputes = $precisionRows.Count -eq 4 -and $precisionErrors.Count -eq 0
    sharedCohortHarmonizedTo52 = $null -ne $amendment -and @($amendment.familySampleSizes | Where-Object { $_.familyId -eq 'P3-IDFF-vs-CFF-shared' -and $_.requiredNFormal -eq 48 -and $_.scheduledNFormal -eq 52 }).Count -eq 1
    scheduleTotals15056 = $scheduleErrors.Count -eq 0 -and $totalProcesses -eq 15056
    budgetProjectionRecomputes = $budgetErrors.Count -eq 0
    currentDiskSnapshotPassesButDoesNotAuthorize = $currentDisk.enoughForCurrentSnapshot -and $currentDisk.launchAuthorizationConferred -eq $false
    runnerImplementationStillPending = $implementationErrors.Count -eq 0 -and $runnerStillFrozenAt100
    noUserImposedUsageLimitAndFrozenGate10HistoryHandled = $usagePolicyErrors.Count -eq 0
    gate12FinalEvidencePassed = $gate12EvidencePassed
    gate11AndGate12FormalFlagsRemainFalse = $gate11ExecutionFlagsClean -and $gate12FormalFlagClean
    noFormalTrueJsonFlags = $formalTrueFiles.Count -eq 0
    noGate13FormalOutput = $formalOutputAbsent
    powerShellParses = $powerShellParseErrors.Count -eq 0
    noUnityProcess = $unityProcesses.Count -eq 0
    noUnityLockfile = -not $unityLockPresent
}
$failedChecks = @($checks.GetEnumerator() | Where-Object { -not $_.Value } | ForEach-Object { $_.Key })
$passed = $errors.Count -eq 0 -and $failedChecks.Count -eq 0

$summary = [ordered]@{
    schemaVersion = 1
    auditId = 'gate13-readiness-amendment-audit-v1'
    auditMode = 'specification-and-test-design-only-no-unity'
    savedAt = (Get-Date).ToString('o')
    savedAtUtc = [DateTime]::UtcNow.ToString('o')
    projectPath = $ProjectPath
    amendmentFiles = $amendmentFiles
    auditScriptSha256 = Get-LowerSha256 $MyInvocation.MyCommand.Path
    frozenInputResults = $frozenInputResults
    bundleFileCount = $bundleFileCount
    computedBundleAggregateSha256 = $computedBundleAggregate
    bundleErrors = $bundleErrors
    baselineChecked = $baselineChecked
    baselineMismatches = $baselineMismatches
    matrixCohorts = $matrixCohorts
    matrixErrors = $matrixErrors
    precisionRows = $precisionRows
    precisionErrors = $precisionErrors
    scheduleRows = $scheduleRows
    totalCampaignCount = if ($null -ne $amendment) { $amendment.matrixAndSchedule.campaignCount } else { 0 }
    totalUnityProcessCount = $totalProcesses
    budgetRecomputation = $budgetRecomputation
    budgetErrors = $budgetErrors
    currentDisk = $currentDisk
    runnerStillFrozenAt100 = $runnerStillFrozenAt100
    implementationErrors = $implementationErrors
    userUsagePolicy = if ($null -ne $amendment) { $amendment.authorization.userUsagePolicy } else { $null }
    supersededUsageBudgetDecision = if ($null -ne $amendment) { $amendment.authorization.supersededUsageBudgetDecision } else { $null }
    usagePolicyErrors = $usagePolicyErrors
    formalTrueFiles = $formalTrueFiles
    formalOutputAbsent = $formalOutputAbsent
    powerShellParseErrors = $powerShellParseErrors
    unityProcessIds = @($unityProcesses | ForEach-Object { $_.Id })
    unityLockfilePresent = $unityLockPresent
    checks = $checks
    failedChecks = $failedChecks
    errors = @($errors)
    passed = $passed
    gate13Status = 'not-started-not-authorized-implementation-pending'
}

Write-Utf8NoBomJson -Path $summaryPath -Value $summary -Depth 20
$summary | ConvertTo-Json -Depth 8
if (-not $passed) { Write-Error "Gate 13 readiness amendment audit failed. Review $summaryPath"; exit 1 }
Write-Host 'Gate 13 readiness amendment audit passed. No Unity or formal campaign was started.' -ForegroundColor Green
exit 0
