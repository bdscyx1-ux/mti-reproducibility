[CmdletBinding()]
param(
    [string]$ProjectPath = (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)),
    [string]$UnityPath = 'H:\UnityEditor\2022.3.30f1c1\Editor\Unity.exe'
)

$ErrorActionPreference = 'Stop'
$ProjectPath = [System.IO.Path]::GetFullPath($ProjectPath)
$UnityPath = [System.IO.Path]::GetFullPath($UnityPath)
$researchPath = Join-Path $ProjectPath 'Research'
$modulePath = Join-Path $researchPath 'Gate13R2V2Preparation.psm1'
$legacyModulePath = Join-Path $researchPath 'Gate13ProcessReusePreparation.psm1'
$runnerPath = Join-Path $researchPath 'Run-PlanningProcessReuseBlockV2.ps1'
$coldRunnerPath = Join-Path $researchPath 'Run-Gate13R2V2ColdReference.ps1'
$planPath = Join-Path $researchPath 'Gate13R2_v2_Pilot_Plan.v1.json'
$provenancePath = Join-Path $researchPath 'Gate13R2_v2_Provenance.v1.json'
$probePath = Join-Path $PSScriptRoot 'Gate13R2_v2\TelemetryProbe\v1\telemetry-probe-result.json'
$root = Join-Path $PSScriptRoot 'Gate13R2_v2\Fixtures\v1'
$summaryPath = Join-Path $PSScriptRoot 'Gate13R2_v2_BlockVerification.summary.json'
Import-Module $modulePath -Force
Import-Module $legacyModulePath -Force
if (Test-Path -LiteralPath $root -or Test-Path -LiteralPath $summaryPath) { throw 'V2 block-verification evidence already exists; refusing retry/overwrite.' }
if (-not (Test-Path -LiteralPath $probePath -PathType Leaf) -or (Read-G13R2V2Json $probePath).passed -ne $true) { throw 'Successful v2 telemetry probe is required before block verification.' }
if (Test-Path -LiteralPath (Join-Path $ProjectPath 'Research\FormalRuns\Gate13_ProcessReuse\v1')) { throw 'Reserved formal root must remain absent.' }
$plan = Read-G13R2V2Json $planPath; $provenance = Read-G13R2V2Json $provenancePath
$nativePowerShellModulePath = @('C:\Users\bdscy\Documents\WindowsPowerShell\Modules','C:\Program Files\WindowsPowerShell\Modules','C:\WINDOWS\System32\WindowsPowerShell\v1.0\Modules') -join ';'
$windowsPowerShell = 'C:\WINDOWS\System32\WindowsPowerShell\v1.0\powershell.exe'

function Invoke-Child([string[]]$Arguments, [string]$StdoutPath, [string]$StderrPath) {
    $previous = $env:PSModulePath
    try { $env:PSModulePath = $nativePowerShellModulePath; & $windowsPowerShell @Arguments 1> $StdoutPath 2> $StderrPath; return [int]$LASTEXITCODE } finally { $env:PSModulePath = $previous }
}

New-Item -ItemType Directory -Path (Join-Path $root 'plans') -Force | Out-Null
$scenarioRelative = [string]$plan.measuredCampaigns[0].scenarioRelativePath
$scenarioSha = [string]$plan.measuredCampaigns[0].scenarioSourceSha256
$scenarioPath = Join-Path $ProjectPath $scenarioRelative.Replace('/', '\')
$twoPlan = New-G13R2V2BlockPlan -ProjectPath $ProjectPath -PilotPlan $plan -Provenance $provenance -CampaignId 'g13r2v2-verify-two' -ScenarioRelativePath $scenarioRelative -ScenarioSourceSha256 $scenarioSha -ComparisonCohortId 'per-agent-heterogeneous-goal-v1' -Block 1 -ProvenancePath $provenancePath -TelemetryProbeResultPath $probePath
$twoPlan.analysisRole = 'excluded-positive-verification'
$fourPlan = New-G13R2V2BlockPlan -ProjectPath $ProjectPath -PilotPlan $plan -Provenance $provenance -CampaignId 'g13r2v2-verify-four' -ScenarioRelativePath $scenarioRelative -ScenarioSourceSha256 $scenarioSha -ComparisonCohortId 'four-algorithm-shared-goal-v1' -Block 1 -ProvenancePath $provenancePath -TelemetryProbeResultPath $probePath
$fourPlan.analysisRole = 'excluded-positive-and-repeatability-verification'
$negativePlan = New-G13R2V2BlockPlan -ProjectPath $ProjectPath -PilotPlan $plan -Provenance $provenance -CampaignId 'g13r2v2-verify-negative' -ScenarioRelativePath $scenarioRelative -ScenarioSourceSha256 $scenarioSha -ComparisonCohortId 'four-algorithm-shared-goal-v1' -Block 1 -ProvenancePath $provenancePath -TelemetryProbeResultPath $probePath
$negativePlan.analysisRole = 'excluded-negative-fail-closed-verification'; $negativePlan.verificationInjectedFailurePosition = 2
foreach ($item in @($twoPlan, $fourPlan, $negativePlan)) { $check = Test-G13R2V2BlockPlanObject $item; if (-not $check.passed) { throw "Generated v2 fixture plan failed validation: $($check.errors -join '; ')" } }
$twoPlanPath = Join-Path $root 'plans\positive-two.block-plan.json'; $fourPlanPath = Join-Path $root 'plans\positive-four.block-plan.json'; $negativePlanPath = Join-Path $root 'plans\negative-fail-closed.block-plan.json'
Write-G13R2V2Utf8NoBomJson $twoPlanPath $twoPlan 40; Write-G13R2V2Utf8NoBomJson $fourPlanPath $fourPlan 40; Write-G13R2V2Utf8NoBomJson $negativePlanPath $negativePlan 40

$invocations = New-Object System.Collections.Generic.List[object]
function Invoke-BlockFixture([string]$Name, [string]$FixturePlanPath, [string]$OutputPath, [switch]$ExpectFailure) {
    $stdout = $OutputPath + '.orchestrator.stdout.log'; $stderr = $OutputPath + '.orchestrator.stderr.log'
    $arguments = @('-NoProfile','-ExecutionPolicy','Bypass','-File',$runnerPath,'-BlockPlanPath',$FixturePlanPath,'-OutputDirectory',$OutputPath,'-UnityPath',$UnityPath,'-ProjectPath',$ProjectPath,'-VerificationOnly')
    if ($ExpectFailure) { $arguments += @('-ExpectFailure','-ExpectedCompletedSamplesBeforeFailure','1') }
    $exit = Invoke-Child $arguments $stdout $stderr
    if ($exit -ne 0) { throw "V2 block fixture failed: $Name, exit=$exit, stderr=$stderr" }
    $summary = Read-G13R2V2Json ($OutputPath + '.summary.json')
    $script:invocations.Add([pscustomobject][ordered]@{ name = $Name; expectedFailure = [bool]$ExpectFailure; outputRelativePath = Get-G13R2V2ProjectRelativePath $ProjectPath $OutputPath; summarySha256 = Get-G13R2V2LowerSha256 ($OutputPath + '.summary.json'); processId = [int]$summary.unityProcessId; passed = [bool]$summary.passed })
}

$twoOutput = Join-Path $root 'positive-two'; $fourAOutput = Join-Path $root 'positive-four-a'; $fourBOutput = Join-Path $root 'positive-four-b'; $negativeOutput = Join-Path $root 'negative-fail-closed'
Invoke-BlockFixture 'positive-two' $twoPlanPath $twoOutput
Invoke-BlockFixture 'positive-four-a' $fourPlanPath $fourAOutput
Invoke-BlockFixture 'positive-four-b' $fourPlanPath $fourBOutput
Invoke-BlockFixture 'negative-fail-closed' $negativePlanPath $negativeOutput -ExpectFailure

$coldMap = @{}
foreach ($algorithm in @('A*-R','D*L','C-FF','IDFF')) {
    $slug = Get-G13R2V2AlgorithmSlug $algorithm; $output = Join-Path $root ("cold-reference\$slug"); $stdout = $output + '.orchestrator.stdout.log'; $stderr = $output + '.orchestrator.stderr.log'; $parent = Split-Path -Parent $output; if (-not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
    $runId = "g13r2v2-verify-ref-$slug"; $args = @('-NoProfile','-ExecutionPolicy','Bypass','-File',$coldRunnerPath,'-ScenarioPath',$scenarioPath,'-OutputDirectory',$output,'-RunId',$runId,'-Algorithm',$algorithm,'-UnityPath',$UnityPath,'-ProjectPath',$ProjectPath,'-VerificationOnly')
    $exit = Invoke-Child $args $stdout $stderr; if ($exit -ne 0) { throw "V2 verification cold control failed: $algorithm, exit=$exit" }
    $resultPath = Join-Path $output 'workload-result.json'; $coldMap[$algorithm] = [pscustomobject]@{ path = $resultPath; result = Read-G13R2V2Json $resultPath }
}

$comparisons = New-Object System.Collections.Generic.List[object]
foreach ($fixture in @([pscustomobject]@{ name='positive-two'; path=$twoOutput },[pscustomobject]@{ name='positive-four-a'; path=$fourAOutput },[pscustomobject]@{ name='positive-four-b'; path=$fourBOutput })) {
    $manifest = Read-G13R2V2Json (Join-Path $fixture.path 'block-manifest.json')
    foreach ($child in @($manifest.samples | Sort-Object position)) {
        $candidatePath = Join-Path $fixture.path ([string]$child.workloadResultRelativePath).Replace('/', '\'); $candidate = Read-G13R2V2Json $candidatePath; $reference = $coldMap[[string]$candidate.algorithmId]
        $comparison = Compare-G13R2StructuralResults -Reference $reference.result -Candidate $candidate
        $comparisons.Add([pscustomobject][ordered]@{ fixture = $fixture.name; position = [int]$child.position; algorithmId = [string]$candidate.algorithmId; referenceSha256 = Get-G13R2V2LowerSha256 $reference.path; candidateSha256 = Get-G13R2V2LowerSha256 $candidatePath; referenceProjectionSha256 = $comparison.referenceProjectionSha256; candidateProjectionSha256 = $comparison.candidateProjectionSha256; passed = [bool]$comparison.passed })
    }
}
$fourAManifest = Read-G13R2V2Json (Join-Path $fourAOutput 'block-manifest.json'); $fourBManifest = Read-G13R2V2Json (Join-Path $fourBOutput 'block-manifest.json')
$repeatabilityPassed = [int]$fourAManifest.processId -ne [int]$fourBManifest.processId -and [string]$fourAManifest.processStartTimeUtc -ne [string]$fourBManifest.processStartTimeUtc
for ($index = 0; $index -lt 4; $index++) {
    $aPath = Join-Path $fourAOutput ([string]$fourAManifest.samples[$index].workloadResultRelativePath).Replace('/', '\'); $bPath = Join-Path $fourBOutput ([string]$fourBManifest.samples[$index].workloadResultRelativePath).Replace('/', '\')
    if (-not (Compare-G13R2StructuralResults -Reference (Read-G13R2V2Json $aPath) -Candidate (Read-G13R2V2Json $bPath)).passed) { $repeatabilityPassed = $false }
}
$negativeCheckpoint = Read-G13R2V2Json (Join-Path $negativeOutput 'block-checkpoint.json')
$negativePassed = [string]$negativeCheckpoint.status -eq 'failed-no-auto-retry' -and [int]$negativeCheckpoint.completedSampleCount -eq 1 -and -not (Test-Path -LiteralPath (Join-Path $negativeOutput 'block-manifest.json')) -and -not (Test-Path -LiteralPath (Join-Path $negativeOutput 'runs\p03-idff')) -and -not (Test-Path -LiteralPath (Join-Path $negativeOutput 'runs\p04-cff'))
$errors = New-Object System.Collections.Generic.List[string]
if (@($comparisons | Where-Object { -not $_.passed }).Count -gt 0) { $errors.Add('One or more positive fixture samples differ structurally from a fresh cold reference.') }
if (-not $repeatabilityPassed) { $errors.Add('Independent-process repeatability failed.') }
if (-not $negativePassed) { $errors.Add('Negative fail-closed fixture did not stop atomically after one completed sample.') }
$summary = [ordered]@{ schemaVersion = 1; summaryKind = 'gate13-r2-v2-block-verification-v1'; savedAtUtc = [DateTime]::UtcNow.ToString('o'); invocationCount = $invocations.Count; invocations = $invocations.ToArray(); freshColdReferenceCount = $coldMap.Count; structuralComparisonCount = $comparisons.Count; structuralMismatchCount = @($comparisons | Where-Object { -not $_.passed }).Count; comparisons = $comparisons.ToArray(); independentProcessRepeatabilityPassed = $repeatabilityPassed; negativeFailClosedPassed = $negativePassed; negativeCheckpointSha256 = Get-G13R2V2LowerSha256 (Join-Path $negativeOutput 'block-checkpoint.json'); errors = $errors.ToArray(); formalCampaign = $false; automaticRetryAttempted = $false; automaticResumeAttempted = $false; passed = $errors.Count -eq 0 }
Write-G13R2V2AtomicUtf8NoBomJson $summaryPath $summary 50
if (-not $summary.passed) { Write-Error "Gate 13-R2 v2 block verification failed: $($errors -join '; ')"; exit 1 }
Write-Host 'Gate 13-R2 v2 positive, negative, structural, and repeatability block verification passed.' -ForegroundColor Green
exit 0
