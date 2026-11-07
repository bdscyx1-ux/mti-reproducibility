[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$ProjectPath,
    [string]$UnityPath = 'H:\UnityEditor\2022.3.30f1c1\Editor\Unity.exe',
    [switch]$BindingSmokeOnly
)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($ProjectPath) -or -not [IO.Path]::IsPathRooted($ProjectPath)) { throw 'Attempt 3 requires an explicit absolute ProjectPath.' }
$ProjectPath = [IO.Path]::GetFullPath($ProjectPath)
if ($BindingSmokeOnly) { Write-Output ('BINDING-SMOKE-PASSED|Run-Gate10RBlockVerificationV3|' + $ProjectPath); exit 0 }
$UnityPath = [IO.Path]::GetFullPath($UnityPath)
$researchPath = Join-Path $ProjectPath 'Research'
$modulePath = Join-Path $researchPath 'Gate10RProcessReusePreparation.psm1'
$runnerPath = Join-Path $researchPath 'Run-Gate10RProcessReuseBlockV3.ps1'
$coldRunnerPath = Join-Path $researchPath 'Run-Gate10RColdReferenceV3.ps1'
$configPath = Join-Path $researchPath 'Gate10R_ProcessReuse_5pct_Attempt3_Config.v3.json'
$provenancePath = Join-Path $researchPath 'Gate10R_ProcessReuse_5pct_Attempt3_Provenance.v3.json'
$probePath = Join-Path $PSScriptRoot 'Gate10R_ProcessReuse_5pct\v3\TelemetryProbe\v1\telemetry-probe-result.json'
$root = Join-Path $PSScriptRoot 'Gate10R_ProcessReuse_5pct\v3\Fixtures\v1'
$summaryPath = Join-Path $PSScriptRoot 'Gate10R_ProcessReuse_5pct\v3\BlockVerification.summary.json'
Import-Module $modulePath -Force
if ((Test-Path -LiteralPath $root) -or (Test-Path -LiteralPath $summaryPath)) { throw 'Gate 10R attempt-3 block-verification evidence exists; refusing retry/overwrite.' }
if (-not (Test-Path -LiteralPath $probePath -PathType Leaf) -or (Read-Gate10RJson $probePath).passed -ne $true) { throw 'Successful Gate 10R attempt-3 telemetry probe is required.' }
if (Test-Path -LiteralPath (Join-Path $ProjectPath 'Research\FormalRuns\Gate13R_ProcessReuse_5pct\v1')) { throw 'Gate 13R formal root must remain absent.' }
$config = Read-Gate10RJson $configPath
$provenance = Read-Gate10RJson $provenancePath
$nativePowerShellModulePath = @('C:\Users\bdscy\Documents\WindowsPowerShell\Modules', 'C:\Program Files\WindowsPowerShell\Modules', 'C:\WINDOWS\System32\WindowsPowerShell\v1.0\Modules') -join ';'
$windowsPowerShell = 'C:\WINDOWS\System32\WindowsPowerShell\v1.0\powershell.exe'
function Invoke-Child([string[]]$Arguments, [string]$StdoutPath, [string]$StderrPath) {
    $previous = $env:PSModulePath
    try { $env:PSModulePath = $nativePowerShellModulePath; & $windowsPowerShell @Arguments 1>$StdoutPath 2>$StderrPath; return [int]$LASTEXITCODE }
    finally { $env:PSModulePath = $previous }
}
New-Item -ItemType Directory -Path (Join-Path $root 'plans') -Force | Out-Null
$sharedRel = 'Research/FormalScenarios/v1/Scenarios/core-r01-s1-shared.scenario.json'
$heteroRel = 'Research/FormalScenarios/v1/Scenarios/core-r01-s1-hetero.scenario.json'
$sharedPath = Join-Path $ProjectPath $sharedRel.Replace('/', '\')
$heteroPath = Join-Path $ProjectPath $heteroRel.Replace('/', '\')
$sharedSha = Get-Gate10RLowerSha256 $sharedPath
$heteroSha = Get-Gate10RLowerSha256 $heteroPath
$twoPlan = New-Gate10RBlockPlan -ProjectPath $ProjectPath -Config $config -Provenance $provenance -CampaignId 'g10r-verify-two' -ScenarioRelativePath $heteroRel -ScenarioSourceSha256 $heteroSha -ComparisonCohortId 'per-agent-heterogeneous-goal-v1' -Block 1 -ProvenancePath $provenancePath -TelemetryProbeResultPath $probePath -AnalysisRole 'excluded-verification'
$fourPlan = New-Gate10RBlockPlan -ProjectPath $ProjectPath -Config $config -Provenance $provenance -CampaignId 'g10r-verify-four' -ScenarioRelativePath $sharedRel -ScenarioSourceSha256 $sharedSha -ComparisonCohortId 'four-algorithm-shared-goal-v1' -Block 1 -ProvenancePath $provenancePath -TelemetryProbeResultPath $probePath -AnalysisRole 'excluded-verification'
$negativePlan = New-Gate10RBlockPlan -ProjectPath $ProjectPath -Config $config -Provenance $provenance -CampaignId 'g10r-verify-negative' -ScenarioRelativePath $sharedRel -ScenarioSourceSha256 $sharedSha -ComparisonCohortId 'four-algorithm-shared-goal-v1' -Block 1 -ProvenancePath $provenancePath -TelemetryProbeResultPath $probePath -AnalysisRole 'excluded-negative-fail-closed-verification' -InjectedFailurePosition 2
foreach ($item in @($twoPlan, $fourPlan, $negativePlan)) { $check = Test-Gate10RBlockPlanObject $item; if (-not $check.passed) { throw "Generated Gate 10R plan failed validation: $($check.errors -join '; ')" } }
$twoPlanPath = Join-Path $root 'plans\positive-two.block-plan.json'
$fourPlanPath = Join-Path $root 'plans\positive-four.block-plan.json'
$negativePlanPath = Join-Path $root 'plans\negative-fail-closed.block-plan.json'
Write-Gate10RUtf8NoBomJson $twoPlanPath $twoPlan 40
Write-Gate10RUtf8NoBomJson $fourPlanPath $fourPlan 40
Write-Gate10RUtf8NoBomJson $negativePlanPath $negativePlan 40

$invocations = New-Object System.Collections.Generic.List[object]
function Invoke-BlockFixture([string]$Name, [string]$PlanPath, [string]$OutputPath, [switch]$ExpectFailure) {
    $stdout = $OutputPath + '.orchestrator.stdout.log'
    $stderr = $OutputPath + '.orchestrator.stderr.log'
    $args = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $runnerPath, '-BlockPlanPath', $PlanPath, '-OutputDirectory', $OutputPath, '-UnityPath', $UnityPath, '-ProjectPath', $ProjectPath, '-VerificationOnly')
    if ($ExpectFailure) { $args += @('-ExpectFailure', '-ExpectedCompletedSamplesBeforeFailure', '1') }
    $exit = Invoke-Child $args $stdout $stderr
    if ($exit -ne 0) { throw "Gate 10R attempt-3 fixture failed: $Name exit=$exit stderr=$stderr" }
    $summary = Read-Gate10RJson ($OutputPath + '.summary.json')
    $script:invocations.Add([pscustomobject][ordered]@{
        name = $Name
        expectedFailure = [bool]$ExpectFailure
        outputRelativePath = Get-Gate10RProjectRelativePath $ProjectPath $OutputPath
        summarySha256 = Get-Gate10RLowerSha256 ($OutputPath + '.summary.json')
        processId = [int]$summary.unityProcessId
        lockHygieneMode = [string]$summary.lockHygieneMode
        lockHygieneReceiptSha256 = [string]$summary.lockHygieneReceiptSha256
        passed = [bool]$summary.passed
    })
}
$twoOutput = Join-Path $root 'positive-two'
$fourAOutput = Join-Path $root 'positive-four-a'
$fourBOutput = Join-Path $root 'positive-four-b'
$negativeOutput = Join-Path $root 'negative-fail-closed'
Invoke-BlockFixture 'positive-two' $twoPlanPath $twoOutput
Invoke-BlockFixture 'positive-four-a' $fourPlanPath $fourAOutput
Invoke-BlockFixture 'positive-four-b' $fourPlanPath $fourBOutput
Invoke-BlockFixture 'negative-fail-closed' $negativePlanPath $negativeOutput -ExpectFailure

$coldMap = @{}
$coldSummaries = New-Object System.Collections.Generic.List[object]
$coldSpecs = @(
    [pscustomobject]@{scenarioId='shared';path=$sharedPath;algorithm='A*-R'},
    [pscustomobject]@{scenarioId='shared';path=$sharedPath;algorithm='D*L'},
    [pscustomobject]@{scenarioId='shared';path=$sharedPath;algorithm='C-FF'},
    [pscustomobject]@{scenarioId='shared';path=$sharedPath;algorithm='IDFF'},
    [pscustomobject]@{scenarioId='hetero';path=$heteroPath;algorithm='A*-R'},
    [pscustomobject]@{scenarioId='hetero';path=$heteroPath;algorithm='D*L'}
)
foreach ($spec in $coldSpecs) {
    $slug = Get-Gate10RAlgorithmSlug $spec.algorithm
    $output = Join-Path $root ("cold-reference\$($spec.scenarioId)-$slug")
    $stdout = $output + '.orchestrator.stdout.log'
    $stderr = $output + '.orchestrator.stderr.log'
    $parent = Split-Path -Parent $output
    if (-not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
    $runId = "g10r-ref-$($spec.scenarioId)-$slug"
    $args = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $coldRunnerPath, '-ScenarioPath', $spec.path, '-OutputDirectory', $output, '-RunId', $runId, '-Algorithm', $spec.algorithm, '-UnityPath', $UnityPath, '-ProjectPath', $ProjectPath, '-VerificationOnly')
    $exit = Invoke-Child $args $stdout $stderr
    if ($exit -ne 0) { throw "Gate 10R attempt-3 cold control failed: $($spec.scenarioId)/$($spec.algorithm), exit=$exit" }
    $resultPath = Join-Path $output 'workload-result.json'
    $summary = Read-Gate10RJson ($output + '.summary.json')
    $coldMap["$($spec.scenarioId)|$($spec.algorithm)"] = [pscustomobject]@{path=$resultPath;result=Read-Gate10RJson $resultPath}
    $coldSummaries.Add([pscustomobject][ordered]@{scenarioId=$spec.scenarioId;algorithmId=$spec.algorithm;processId=[int]$summary.unityProcessId;lockHygieneMode=[string]$summary.lockHygieneMode;summarySha256=Get-Gate10RLowerSha256 ($output + '.summary.json')})
}
$comparisons = New-Object System.Collections.Generic.List[object]
foreach ($fixture in @(
    [pscustomobject]@{name='positive-two';path=$twoOutput;scenarioId='hetero'},
    [pscustomobject]@{name='positive-four-a';path=$fourAOutput;scenarioId='shared'},
    [pscustomobject]@{name='positive-four-b';path=$fourBOutput;scenarioId='shared'})) {
    $manifest = Read-Gate10RJson (Join-Path $fixture.path 'block-manifest.json')
    foreach ($child in @($manifest.samples | Sort-Object position)) {
        $candidatePath = Join-Path $fixture.path ([string]$child.workloadResultRelativePath).Replace('/', '\')
        $candidate = Read-Gate10RJson $candidatePath
        $reference = $coldMap["$($fixture.scenarioId)|$([string]$candidate.algorithmId)"]
        if ($null -eq $reference) { throw "Missing matching cold control for $($fixture.name)/$($candidate.algorithmId)" }
        $comparison = Compare-Gate10RStructuralResults $reference.result $candidate
        $comparisons.Add([pscustomobject][ordered]@{fixture=$fixture.name;position=[int]$child.position;algorithmId=[string]$candidate.algorithmId;referenceSha256=Get-Gate10RLowerSha256 $reference.path;candidateSha256=Get-Gate10RLowerSha256 $candidatePath;referenceProjectionSha256=$comparison.referenceProjectionSha256;candidateProjectionSha256=$comparison.candidateProjectionSha256;passed=[bool]$comparison.passed})
    }
}
$fourAManifest = Read-Gate10RJson (Join-Path $fourAOutput 'block-manifest.json')
$fourBManifest = Read-Gate10RJson (Join-Path $fourBOutput 'block-manifest.json')
$repeatability = [int]$fourAManifest.processId -ne [int]$fourBManifest.processId -and [string]$fourAManifest.processStartTimeUtc -ne [string]$fourBManifest.processStartTimeUtc
for ($index=0; $index -lt 4; $index++) {
    $aPath = Join-Path $fourAOutput ([string]$fourAManifest.samples[$index].workloadResultRelativePath).Replace('/', '\')
    $bPath = Join-Path $fourBOutput ([string]$fourBManifest.samples[$index].workloadResultRelativePath).Replace('/', '\')
    if (-not (Compare-Gate10RStructuralResults (Read-Gate10RJson $aPath) (Read-Gate10RJson $bPath)).passed) { $repeatability = $false }
}
$positivePids = @($invocations | Where-Object {-not $_.expectedFailure} | ForEach-Object {$_.processId})
$distinctPositivePids = @($positivePids | Select-Object -Unique).Count -eq 3
$negativeCheckpoint = Read-Gate10RJson (Join-Path $negativeOutput 'block-checkpoint.json')
$negativePassed = [string]$negativeCheckpoint.status -eq 'failed-no-auto-retry' -and [int]$negativeCheckpoint.completedSampleCount -eq 1 -and -not (Test-Path -LiteralPath (Join-Path $negativeOutput 'block-manifest.json')) -and -not (Test-Path -LiteralPath (Join-Path $negativeOutput 'runs\p03-idff')) -and -not (Test-Path -LiteralPath (Join-Path $negativeOutput 'runs\p04-cff'))
$positiveLockModesPassed = @($invocations | Where-Object {-not $_.expectedFailure -and $_.lockHygieneMode -ne 'natural-lock-absence'}).Count -eq 0
$negativeInvocation = @($invocations | Where-Object {$_.expectedFailure})[0]
$negativeLockModePassed = [string]$negativeInvocation.lockHygieneMode -in @('natural-lock-absence', 'controlled-expected-negative-cleanup')
$coldLockModesPassed = @($coldSummaries | Where-Object {$_.lockHygieneMode -ne 'natural-lock-absence'}).Count -eq 0
$errors = New-Object System.Collections.Generic.List[string]
if (@($comparisons | Where-Object {-not $_.passed}).Count -gt 0) { $errors.Add('A positive sample differs structurally from its same-scenario fresh cold reference.') }
if (-not $repeatability) { $errors.Add('Independent-process repeatability failed.') }
if (-not $distinctPositivePids) { $errors.Add('Positive blocks did not use three distinct Unity processes.') }
if (-not $negativePassed) { $errors.Add('Negative block did not stop atomically after one completed sample.') }
if (-not $positiveLockModesPassed) { $errors.Add('A positive block did not release its lock naturally.') }
if (-not $negativeLockModePassed) { $errors.Add('Negative block has an unauthorized lock-hygiene mode.') }
if (-not $coldLockModesPassed) { $errors.Add('A cold reference did not release its lock naturally.') }
if (Test-Path -LiteralPath (Join-Path $ProjectPath 'Temp\UnityLockfile')) { $errors.Add('Project lock remains after block verification.') }
$summary = [ordered]@{
    schemaVersion = 1
    summaryKind = 'gate10r-block-verification-attempt3-v3'
    savedAtUtc = [DateTime]::UtcNow.ToString('o')
    invocationCount = $invocations.Count
    invocations = $invocations.ToArray()
    freshColdReferenceCount = $coldMap.Count
    coldReferences = $coldSummaries.ToArray()
    structuralComparisonCount = $comparisons.Count
    structuralMismatchCount = @($comparisons | Where-Object {-not $_.passed}).Count
    comparisons = $comparisons.ToArray()
    distinctPositiveProcessIdsPassed = $distinctPositivePids
    independentProcessRepeatabilityPassed = $repeatability
    negativeFailClosedPassed = $negativePassed
    positiveNaturalLockReleasePassed = $positiveLockModesPassed
    negativeLockHygienePassed = $negativeLockModePassed
    negativeLockHygieneMode = [string]$negativeInvocation.lockHygieneMode
    coldNaturalLockReleasePassed = $coldLockModesPassed
    negativeCheckpointSha256 = Get-Gate10RLowerSha256 (Join-Path $negativeOutput 'block-checkpoint.json')
    errors = $errors.ToArray()
    formalCampaign = $false
    automaticRetryAttempted = $false
    automaticResumeAttempted = $false
    passed = $errors.Count -eq 0
}
Write-Gate10RAtomicUtf8NoBomJson $summaryPath $summary 50
if (-not $summary.passed) { Write-Error "Gate 10R attempt-3 block verification failed: $($errors -join '; ')"; exit 1 }
Write-Host 'Gate 10R attempt-3 positive, negative, cold-structural, repeatability, and lock-hygiene verification passed.' -ForegroundColor Green
exit 0

