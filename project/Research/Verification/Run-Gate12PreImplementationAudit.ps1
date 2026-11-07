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

$summaryPath = Join-Path $scriptDirectory 'Gate12_PreImplementationAudit.summary.json'
$specificationPath = Join-Path $ProjectPath 'Research\Gate12_Pilot_Noise_and_Sample_Size_Specification.md'
$testDesignPath = Join-Path $ProjectPath 'Research\Gate12_Pilot_Test_Design.md'
$pilotPlanPath = Join-Path $ProjectPath 'Research\Gate12_Pilot_Plan.v1.json'
$bundlePath = Join-Path $ProjectPath 'Research\FormalScenarios\v1'
$bundleManifestPath = Join-Path $bundlePath 'bundle-manifest.json'
$matrixPath = Join-Path $bundlePath 'formal-scenario-matrix.json'
$preregistrationPath = Join-Path $bundlePath 'preregistered-analysis.json'

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

function Write-Utf8NoBomJson([string]$Path, $Value, [int]$Depth = 14) {
    $json = $Value | ConvertTo-Json -Depth $Depth
    $json = $json.Replace("`r`n", "`n").Replace("`r", "`n")
    if (-not $json.EndsWith("`n", [System.StringComparison]::Ordinal)) { $json += "`n" }
    $encoding = New-Object System.Text.UTF8Encoding($false, $true)
    [System.IO.File]::WriteAllText($Path, $json, $encoding)
}

$errors = New-Object System.Collections.Generic.List[string]
foreach ($requiredPath in @($specificationPath, $testDesignPath, $pilotPlanPath, $bundleManifestPath, $matrixPath, $preregistrationPath)) {
    if (-not (Test-Path -LiteralPath $requiredPath -PathType Leaf)) { $errors.Add("Required file is missing: $requiredPath") }
}

$plan = $null
$manifest = $null
$matrix = $null
$preregistration = $null
try { $plan = Get-Content -LiteralPath $pilotPlanPath -Raw -Encoding UTF8 | ConvertFrom-Json }
catch { $errors.Add("Pilot plan could not be parsed: $($_.Exception.Message)") }
try { $manifest = Get-Content -LiteralPath $bundleManifestPath -Raw -Encoding UTF8 | ConvertFrom-Json }
catch { $errors.Add("Bundle manifest could not be parsed: $($_.Exception.Message)") }
try { $matrix = Get-Content -LiteralPath $matrixPath -Raw -Encoding UTF8 | ConvertFrom-Json }
catch { $errors.Add("Matrix could not be parsed: $($_.Exception.Message)") }
try { $preregistration = Get-Content -LiteralPath $preregistrationPath -Raw -Encoding UTF8 | ConvertFrom-Json }
catch { $errors.Add("Preregistration could not be parsed: $($_.Exception.Message)") }

$frozenFiles = [ordered]@{}
$frozenDocumentPaths = [ordered]@{
    specification = $specificationPath
    testDesign = $testDesignPath
    pilotPlan = $pilotPlanPath
}
foreach ($entry in $frozenDocumentPaths.GetEnumerator()) {
    if (Test-Path -LiteralPath $entry.Value -PathType Leaf) {
        $item = Get-Item -LiteralPath $entry.Value
        $frozenFiles[$entry.Key] = [ordered]@{
            path = $entry.Value
            sha256 = Get-LowerSha256 $entry.Value
            byteCount = $item.Length
            lastWriteTimeUtc = $item.LastWriteTimeUtc.ToString('o')
        }
    }
}

$productionPaths = @(
    (Join-Path $ProjectPath 'Research\Run-Gate12Pilot.ps1'),
    (Join-Path $ProjectPath 'Research\Analyze-Gate12Pilot.ps1'),
    (Join-Path $ProjectPath 'Research\Gate12PilotAnalysis.psm1'),
    (Join-Path $ProjectPath 'Research\Verification\Run-Gate12AnalysisUnitTests.ps1'),
    (Join-Path $ProjectPath 'Research\Verification\Run-Gate12PilotVerification.ps1'),
    (Join-Path $ProjectPath 'Research\Verification\Run-Gate12FinalAudit.ps1'),
    (Join-Path $ProjectPath 'Research\PilotRuns\Gate12\v1')
)
$prematureProductionPaths = @($productionPaths | Where-Object { Test-Path -LiteralPath $_ })
if ($prematureProductionPaths.Count -ne 0) {
    foreach ($path in $prematureProductionPaths) { $errors.Add("Gate 12 production artifact exists before pre-implementation approval: $path") }
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
            relativePath = $row.relative_path
            exists = $exists
            expectedBytes = [int64]$row.bytes
            actualBytes = $actualBytes
            expectedSha256 = $row.sha256
            actualSha256 = $actualHash
        }
    }
}
if ($baselineChecked -ne 24 -or $baselineMismatches.Count -ne 0) { $errors.Add("Frozen baseline mismatch: checked=$baselineChecked mismatches=$($baselineMismatches.Count)") }

$artifactErrors = @()
$computedAggregate = $null
$bundleFileCount = 0
if ($null -ne $manifest) {
    $aggregateBuilder = New-Object System.Text.StringBuilder
    foreach ($artifact in @($manifest.artifacts)) {
        $path = Join-Path $bundlePath ([string]$artifact.relativePath).Replace('/', '\')
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            $artifactErrors += "Missing artifact: $($artifact.relativePath)"
            continue
        }
        $actualHash = Get-LowerSha256 $path
        $actualBytes = (Get-Item -LiteralPath $path).Length
        if ($actualHash -ne $artifact.sha256 -or $actualBytes -ne [int64]$artifact.byteCount) {
            $artifactErrors += "Artifact identity mismatch: $($artifact.relativePath)"
        }
        [void]$aggregateBuilder.Append([string]$artifact.relativePath).Append("`n").Append([string]$artifact.sha256).Append("`n")
    }
    $computedAggregate = Get-StringSha256 $aggregateBuilder.ToString()
    $bundleFileCount = @(Get-ChildItem -LiteralPath $bundlePath -File -Recurse).Count
    if ($manifest.artifacts.Count -ne 56 -or $bundleFileCount -ne 57) { $artifactErrors += 'Retained bundle file/artifact count differs from 56+manifest.' }
    if ($computedAggregate -ne $manifest.bundleAggregateSha256) { $artifactErrors += 'Retained bundle ordered aggregate differs from manifest.' }
}
if ($artifactErrors.Count -ne 0) { foreach ($errorText in $artifactErrors) { $errors.Add($errorText) } }

$fixedInputErrors = @()
if ($null -ne $plan) {
    $expectedInputPaths = [ordered]@{
        bundleManifest = [ordered]@{ path = $bundleManifestPath; hash = $plan.retainedBundle.manifestSha256 }
        matrix = [ordered]@{ path = $matrixPath; hash = $plan.retainedBundle.matrixSha256 }
        preregistration = [ordered]@{ path = $preregistrationPath; hash = $plan.retainedBundle.preregistrationSha256 }
        fairnessSpecification = [ordered]@{ path = Join-Path $ProjectPath $plan.frozenInputs.fairnessSpecificationRelativePath.Replace('/', '\'); hash = $plan.frozenInputs.fairnessSpecificationSha256 }
        workloadSpecification = [ordered]@{ path = Join-Path $ProjectPath $plan.frozenInputs.workloadSpecificationRelativePath.Replace('/', '\'); hash = $plan.frozenInputs.workloadSpecificationSha256 }
        campaignRunner = [ordered]@{ path = Join-Path $ProjectPath $plan.frozenInputs.campaignRunnerRelativePath.Replace('/', '\'); hash = $plan.frozenInputs.campaignRunnerSha256 }
        workloadRunner = [ordered]@{ path = Join-Path $ProjectPath $plan.frozenInputs.workloadRunnerRelativePath.Replace('/', '\'); hash = $plan.frozenInputs.workloadRunnerSha256 }
        batchCommand = [ordered]@{ path = Join-Path $ProjectPath $plan.frozenInputs.batchCommandRelativePath.Replace('/', '\'); hash = $plan.frozenInputs.batchCommandSha256 }
        workloadImplementation = [ordered]@{ path = Join-Path $ProjectPath $plan.frozenInputs.workloadImplementationRelativePath.Replace('/', '\'); hash = $plan.frozenInputs.workloadImplementationSha256 }
        fairnessContracts = [ordered]@{ path = Join-Path $ProjectPath $plan.frozenInputs.fairnessContractsRelativePath.Replace('/', '\'); hash = $plan.frozenInputs.fairnessContractsSha256 }
        unityExecutable = [ordered]@{ path = $plan.unity.executablePath.Replace('/', '\'); hash = $plan.unity.executableSha256 }
    }
    foreach ($entry in $expectedInputPaths.GetEnumerator()) {
        $actualHash = Get-LowerSha256 $entry.Value.path
        if ($actualHash -ne $entry.Value.hash) { $fixedInputErrors += "$($entry.Key): expected $($entry.Value.hash), actual $actualHash" }
    }
    if ($computedAggregate -ne $plan.retainedBundle.orderedAggregateSha256) { $fixedInputErrors += 'Plan ordered bundle aggregate does not match recomputation.' }
}
if ($fixedInputErrors.Count -ne 0) { foreach ($errorText in $fixedInputErrors) { $errors.Add("Frozen input mismatch: $errorText") } }

$planErrors = @()
if ($null -ne $plan -and $null -ne $matrix) {
    if ($plan.schemaVersion -ne 1 -or $plan.pilotPlanId -ne 'gate12-isolated-pilot-v1') { $planErrors += 'Plan identity/schema mismatch.' }
    if ($plan.formalCampaign -ne $false -or $plan.gate13ExecutionAuthorized -ne $false -or $plan.gate13ResultsPermitted -ne $false) { $planErrors += 'Plan incorrectly authorizes formal/Gate 13 execution.' }
    $scenarioIds = @($plan.pilotSubset.scenarios | ForEach-Object { [string]$_.scenarioId })
    $rows = @($plan.pilotSubset.scenarios | ForEach-Object { [int]$_.structuralRow } | Sort-Object -Unique)
    if ($scenarioIds.Count -ne 8 -or @($scenarioIds | Sort-Object -Unique).Count -ne 8 -or (($rows -join ',') -ne '1,2,7,8')) { $planErrors += 'Pilot scenario subset count, uniqueness, or structural rows mismatch.' }
    foreach ($scenario in @($plan.pilotSubset.scenarios)) {
        $matrixScenario = @($matrix.scenarios | Where-Object scenarioId -eq $scenario.scenarioId)
        if ($matrixScenario.Count -ne 1 -or $matrixScenario[0].relativePath -ne $scenario.relativePath -or $matrixScenario[0].sourceSha256 -ne $scenario.sourceSha256 -or $matrixScenario[0].fingerprintSha256 -ne $scenario.fingerprintSha256 -or $matrixScenario[0].seedReplication -ne 1) {
            $planErrors += "Pilot scenario does not match frozen matrix: $($scenario.scenarioId)"
        }
    }
    foreach ($row in @(1, 2, 7, 8)) {
        $pair = @($plan.pilotSubset.scenarios | Where-Object structuralRow -eq $row)
        if ($pair.Count -ne 2 -or @($pair.goalStructureId | Sort-Object -Unique).Count -ne 2) { $planErrors += "Structural row $row is not a shared/heterogeneous pair." }
    }
    $campaigns = @($plan.measuredCampaigns)
    $ordinals = @($campaigns | Sort-Object ordinal | ForEach-Object { [int]$_.ordinal })
    if ($campaigns.Count -ne 12 -or @($campaigns.campaignId | Sort-Object -Unique).Count -ne 12 -or (($ordinals -join ',') -ne '1,2,3,4,5,6,7,8,9,10,11,12')) { $planErrors += 'Measured campaign count, ids, or ordinals mismatch.' }
    if (($campaigns | Measure-Object -Property expectedSampleCount -Sum).Sum -ne 256 -or $plan.repetitionDesign.measuredUnityProcessCount -ne 256 -or $plan.repetitionDesign.warmupUnityProcessCount -ne 16 -or $plan.repetitionDesign.totalUnityProcessCount -ne 272) { $planErrors += 'Frozen process counts mismatch.' }
    if (@($campaigns | Where-Object blocks -ne 8).Count -ne 0 -or $plan.repetitionDesign.measuredRepetitionsPerAlgorithmPerScenario -ne 8) { $planErrors += 'Repetition count or block count mismatch.' }
    foreach ($row in @(1, 2, 7, 8)) {
        $rowIds = @($plan.pilotSubset.scenarios | Where-Object structuralRow -eq $row | ForEach-Object scenarioId)
        $rowCampaigns = @($campaigns | Where-Object scenarioId -in $rowIds)
        $cohorts = @($rowCampaigns.comparisonCohortId | Sort-Object -Unique)
        if ($rowCampaigns.Count -ne 3 -or (($cohorts -join ',') -ne 'four-algorithm-shared-goal-v1,grouped-field-heterogeneous-goal-v1,per-agent-heterogeneous-goal-v1')) { $planErrors += "Structural row $row does not have all three cohorts exactly once." }
    }
    if ($plan.analysis.families.Count -ne 4 -or $plan.analysis.minimumMeasuredRepetitionsPerCell -ne 8 -or $plan.analysis.minimumPerAlgorithm -ne 30 -or $plan.analysis.cycleMultiple -ne 4 -or $plan.analysis.maximumPerAlgorithm -ne 100) { $planErrors += 'Analysis family or precision constants mismatch.' }
    $outputRoot = [System.IO.Path]::GetFullPath((Join-Path $ProjectPath $plan.output.rootRelativePath.Replace('/', '\')))
    if ($outputRoot.StartsWith($bundlePath, [System.StringComparison]::OrdinalIgnoreCase)) { $planErrors += 'Pilot output root is inside retained bundle.' }
}
if ($planErrors.Count -ne 0) { foreach ($errorText in $planErrors) { $errors.Add("Pilot plan invalid: $errorText") } }

if ($null -ne $manifest) {
    if ($manifest.pilotExecuted -ne $false -or $manifest.formalCampaignExecuted -ne $false) { $errors.Add('Gate 11 manifest execution flags changed before Gate 12 pilot.') }
}
if ($null -ne $preregistration) {
    if ($preregistration.formalSampleSizeStatus -ne 'unset-until-gate12-v1' -or $preregistration.significanceEarlyStoppingAllowed -ne $false -or $preregistration.trendEarlyStoppingAllowed -ne $false) { $errors.Add('Gate 11 preregistration sample-size/stopping state changed.') }
}

$gate11FinalSummaryPath = Join-Path $scriptDirectory 'Gate11_FinalAudit.summary.json'
$gate11FinalPassed = $false
if (Test-Path -LiteralPath $gate11FinalSummaryPath -PathType Leaf) {
    try { $gate11FinalPassed = (Get-Content -LiteralPath $gate11FinalSummaryPath -Raw -Encoding UTF8 | ConvertFrom-Json).passed -eq $true }
    catch { $errors.Add("Gate 11 final summary could not be parsed: $($_.Exception.Message)") }
}
if (-not $gate11FinalPassed) { $errors.Add('Gate 11 final audit evidence is not passing.') }

$powerShellParseErrors = @()
foreach ($file in @(Get-ChildItem -LiteralPath (Join-Path $ProjectPath 'Research') -Filter '*.ps1' -File -Recurse | Sort-Object FullName)) {
    $tokens = $null
    $parseErrors = $null
    $utf8 = New-Object System.Text.UTF8Encoding($false, $true)
    $scriptText = [System.IO.File]::ReadAllText($file.FullName, $utf8)
    [System.Management.Automation.Language.Parser]::ParseInput($scriptText, $file.FullName, [ref]$tokens, [ref]$parseErrors) | Out-Null
    foreach ($parseError in @($parseErrors)) { $powerShellParseErrors += [ordered]@{ file = $file.FullName; message = $parseError.Message; extent = $parseError.Extent.Text } }
}
if ($powerShellParseErrors.Count -ne 0) { $errors.Add("PowerShell parse errors exist: $($powerShellParseErrors.Count)") }

$unityProcesses = @(Get-Process -Name Unity -ErrorAction SilentlyContinue)
$unityLockPath = Join-Path $ProjectPath 'Temp\UnityLockfile'
if ($unityProcesses.Count -ne 0) { $errors.Add("Unity processes are running: $($unityProcesses.Id -join ',')") }
if (Test-Path -LiteralPath $unityLockPath) { $errors.Add("Unity lockfile exists: $unityLockPath") }

$gate13Outputs = @(Get-ChildItem -LiteralPath (Join-Path $ProjectPath 'Research') -Force -Recurse -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '^(Gate13|FormalCampaign)(_|-|$)' } | Select-Object -ExpandProperty FullName)
if ($gate13Outputs.Count -ne 0) { foreach ($path in $gate13Outputs) { $errors.Add("Gate 13/formal output exists: $path") } }

$checks = [ordered]@{
    frozenDocumentsPresentAndParsed = $null -ne $plan -and $null -ne $manifest -and $null -ne $matrix -and $null -ne $preregistration
    productionAbsentBeforeAudit = $prematureProductionPaths.Count -eq 0
    frozenBaselineMatches = $baselineChecked -eq 24 -and $baselineMismatches.Count -eq 0
    retainedBundleMatches = $artifactErrors.Count -eq 0 -and $bundleFileCount -eq 57 -and $computedAggregate -eq '91d9e3c66327185e48f68cafb05c674cc49e929adb576973098d0bfebd2e9a88'
    fixedInputsMatch = $fixedInputErrors.Count -eq 0
    pilotPlanValid = $planErrors.Count -eq 0
    gate11StillPrePilot = $null -ne $manifest -and $manifest.pilotExecuted -eq $false -and $manifest.formalCampaignExecuted -eq $false
    gate11FinalEvidencePassed = $gate11FinalPassed
    powerShellParses = $powerShellParseErrors.Count -eq 0
    noUnityProcess = $unityProcesses.Count -eq 0
    noUnityLockfile = -not (Test-Path -LiteralPath $unityLockPath)
    noGate13Output = $gate13Outputs.Count -eq 0
}
$failedChecks = @($checks.GetEnumerator() | Where-Object { -not $_.Value } | ForEach-Object { $_.Key })
$passed = $errors.Count -eq 0 -and $failedChecks.Count -eq 0
$summary = [ordered]@{
    schemaVersion = 1
    auditId = 'gate12-preimplementation-audit-v1'
    auditMode = 'pre-implementation-freeze'
    savedAt = (Get-Date).ToString('o')
    savedAtUtc = [DateTime]::UtcNow.ToString('o')
    projectPath = $ProjectPath
    frozenFiles = $frozenFiles
    auditScriptSha256 = Get-LowerSha256 $MyInvocation.MyCommand.Path
    baselineChecked = $baselineChecked
    baselineMismatches = $baselineMismatches
    bundleFileCount = $bundleFileCount
    bundleArtifactCount = if ($null -ne $manifest) { $manifest.artifacts.Count } else { 0 }
    computedBundleAggregateSha256 = $computedAggregate
    artifactErrors = $artifactErrors
    fixedInputErrors = $fixedInputErrors
    planErrors = $planErrors
    prematureProductionPaths = $prematureProductionPaths
    gate13Outputs = $gate13Outputs
    powerShellParseErrors = $powerShellParseErrors
    unityProcessIds = @($unityProcesses | ForEach-Object { $_.Id })
    unityLockfilePresent = Test-Path -LiteralPath $unityLockPath
    checks = $checks
    failedChecks = $failedChecks
    errors = @($errors)
    passed = $passed
}
Write-Utf8NoBomJson -Path $summaryPath -Value $summary -Depth 16
$summary | ConvertTo-Json -Depth 8
if (-not $passed) { Write-Error "Gate 12 pre-implementation audit failed. Review $summaryPath"; exit 1 }
Write-Host 'Gate 12 pre-implementation audit passed. Specification, test design, and plan are frozen.' -ForegroundColor Green
exit 0
