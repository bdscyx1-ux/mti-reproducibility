[CmdletBinding()]
param(
    [string]$ProjectPath = (Split-Path -Parent $PSScriptRoot),
    [string]$PilotRoot,
    [string]$ProvenancePath
)

$ErrorActionPreference = 'Stop'
$ProjectPath = [System.IO.Path]::GetFullPath($ProjectPath)
if ([string]::IsNullOrWhiteSpace($PilotRoot)) { $PilotRoot = Join-Path $ProjectPath 'Research\PilotRuns\Gate13_ProcessReuse\v1' }
if ([string]::IsNullOrWhiteSpace($ProvenancePath)) { $ProvenancePath = Join-Path $ProjectPath 'Research\Gate13_ProcessReuse_Provenance.v4.json' }
$PilotRoot = [System.IO.Path]::GetFullPath($PilotRoot)
$ProvenancePath = [System.IO.Path]::GetFullPath($ProvenancePath)
$modulePath = Join-Path $PSScriptRoot 'Gate13ProcessReusePreparation.psm1'
Import-Module $modulePath -Force

$formalRoot = Join-Path $ProjectPath 'Research\FormalRuns\Gate13_ProcessReuse\v1'
$amendmentPath = Join-Path $ProjectPath 'Research\Gate13_ProcessReuse_Amendment.v1.json'
$configPath = Join-Path $ProjectPath 'Research\Gate13_ProcessReuse_Formal_Campaign_Config.v1.json'
$manifestPath = Join-Path $ProjectPath 'Research\Gate13_ProcessReuse_Preparation_Manifest.v1.json'
$checkpointPath = Join-Path $ProjectPath 'Research\Gate13_ProcessReuse_Preparation_Checkpoint.v1.json'
foreach ($path in @($formalRoot, $amendmentPath, $configPath, $manifestPath, $checkpointPath)) {
    if (Test-Path -LiteralPath $path) { throw "Create-new process-reuse preparation target already exists: $path" }
}

$evidenceDefinitions = [ordered]@{
    pilotManifest = 'pilot-manifest.json'
    executionManifest = 'pilot-execution-manifest.json'
    analysisManifest = 'analysis-manifest.json'
    candidateSampleSizes = 'candidate-sample-sizes.json'
    budgetFeasibility = 'budget-feasibility.json'
    structuralEquivalence = 'structural-equivalence.json'
    runtimeDiagnostics = 'runtime-diagnostics.json'
}
$evidence = [ordered]@{}
foreach ($entry in $evidenceDefinitions.GetEnumerator()) {
    $path = Join-Path $PilotRoot $entry.Value
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Required process-reuse pilot evidence is missing: $path" }
    $evidence[$entry.Key] = [ordered]@{
        relativePath = Get-G13R2ProjectRelativePath -ProjectPath $ProjectPath -FullPath $path
        sha256 = Get-G13R2LowerSha256 -Path $path
    }
}
$pilotManifest = Read-G13R2Json -Path (Join-Path $PilotRoot 'pilot-manifest.json')
$candidate = Read-G13R2Json -Path (Join-Path $PilotRoot 'candidate-sample-sizes.json')
$structural = Read-G13R2Json -Path (Join-Path $PilotRoot 'structural-equivalence.json')
$runtime = Read-G13R2Json -Path (Join-Path $PilotRoot 'runtime-diagnostics.json')
$budget = Read-G13R2Json -Path (Join-Path $PilotRoot 'budget-feasibility.json')
$provenance = Read-G13R2Json -Path $ProvenancePath
if ($pilotManifest.completed -ne $true -or $pilotManifest.formalCampaign -ne $false -or $pilotManifest.excludedFromFormalAnalysis -ne $true -or $pilotManifest.formalExecutionAuthorized -ne $false) { throw 'Pilot manifest is not a completed excluded non-formal pilot.' }
if ([int]$pilotManifest.measuredBlockProcessCount -ne 36 -or [int]$pilotManifest.measuredSampleCount -ne 96 -or [int]$pilotManifest.structuralMismatchCount -ne 0) { throw 'Pilot cardinality/structural verdict mismatch.' }
if ($structural.passed -ne $true -or [int]$structural.mismatchCount -ne 0 -or $runtime.passed -ne $true -or [int]$runtime.hardErrorCount -ne 0) { throw 'Pilot structural/runtime readiness evidence is not passing.' }
if ($candidate.anyOverCap -ne $false) { throw 'At least one candidate requirement exceeds cap 148; formal preparation is blocked.' }
if ($budget.executionAuthorizationConferred -ne $false) { throw 'Pilot budget evidence unexpectedly confers execution authorization.' }

function Get-Family([string]$FamilyId) {
    $rows = @($candidate.families | Where-Object familyId -eq $FamilyId)
    if ($rows.Count -ne 1) { throw "Candidate family is missing or duplicated: $FamilyId" }
    return $rows[0]
}
$p1 = Get-Family 'P1-DL-vs-A-shared'
$p2 = Get-Family 'P2-DL-vs-A-hetero'
$p3 = Get-Family 'P3-IDFF-vs-CFF-shared'
$p4 = Get-Family 'P4-IDFF-vs-CFF-grouped'
if ([int]$p1.scheduledNFormal -ne [int]$p3.scheduledNFormal) { throw 'P1/P3 shared-cohort schedules are not harmonized.' }
$cohorts = @(
    [ordered]@{ comparisonCohortId = 'four-algorithm-shared-goal-v1'; scheduledIndependentBlocks = [int]$p1.scheduledNFormal; sourceFamilies = @('P1-DL-vs-A-shared', 'P3-IDFF-vs-CFF-shared'); harmonization = 'maximum-of-p1-p3' },
    [ordered]@{ comparisonCohortId = 'per-agent-heterogeneous-goal-v1'; scheduledIndependentBlocks = [int]$p2.scheduledNFormal; sourceFamilies = @('P2-DL-vs-A-hetero'); harmonization = 'none' },
    [ordered]@{ comparisonCohortId = 'grouped-field-heterogeneous-goal-v1'; scheduledIndependentBlocks = [int]$p4.scheduledNFormal; sourceFamilies = @('P4-IDFF-vs-CFF-grouped'); harmonization = 'none' }
)
foreach ($cohort in $cohorts) {
    if ([int]$cohort.scheduledIndependentBlocks -lt 30 -or [int]$cohort.scheduledIndependentBlocks -gt 148 -or [int]$cohort.scheduledIndependentBlocks % 4 -ne 0) { throw "Invalid frozen process-reuse block count: $($cohort.comparisonCohortId)" }
}

$amendment = [ordered]@{
    schemaVersion = 1
    amendmentId = 'gate13-r2-process-reuse-readiness-amendment-v1'
    amendmentKind = 'post-pilot-design-readiness-amendment-nonexecuting-v1'
    recordedAt = (Get-Date).ToString('o')
    materialPassport = [ordered]@{
        originSkill = 'experiment-agent'
        originMode = 'validate'
        verificationStatus = 'PILOT-PASSED-FORMAL-NOT-AUTHORIZED'
        versionLabel = 'gate13_r2_process_reuse_readiness_amendment_v1'
    }
    authorizationBoundary = [ordered]@{
        authorizationReference = 'user-message-2026-10-06-gate13-cold-process-to-process-reuse-controlled-design-migration'
        nonFormalPilotAuthorized = $true
        formalCampaignAuthorized = $false
        formalOutputRootCreationAllowed = $false
        formalExecutionReceiptAllowed = $false
        automaticRetryAllowed = $false
        automaticResumeAllowed = $false
    }
    supersededColdDesign = [ordered]@{
        terminationReceipt = [ordered]@{ relativePath = 'Research/Gate13_ColdProcess_Termination_Receipt.v1.json'; sha256 = '4661a3edc6e569b068e065456ab34f839d60030b1d668a925ca5b9dad9e481a4' }
        outputRootRelativePath = 'Research/FormalRuns/Gate13/v1'
        dispositions = @('USER-TERMINATED-DESIGN-CHANGE', 'EXCLUDED_FROM_ANALYSIS', 'NO-AUTO-RETRY', 'NO-RESUME', 'SUPERSEDED-BY-PROCESS-REUSE-DESIGN')
        mayResume = $false
        mayMerge = $false
        mayEnterGate14 = $false
    }
    frozenInputs = [ordered]@{
        provenance = [ordered]@{ relativePath = Get-G13R2ProjectRelativePath -ProjectPath $ProjectPath -FullPath $ProvenancePath; sha256 = Get-G13R2LowerSha256 -Path $ProvenancePath }
        pilotPlan = $provenance.pilotPlan
        specification = $provenance.specification
        testDesign = $provenance.testDesign
        coldFormalConfig = [ordered]@{ relativePath = 'Research/Gate13_Formal_Campaign_Config.v1.json'; sha256 = 'b74f777f4022d5890839ed54987b2ae28a9ff27ae400c5a8d72dd0efccfd0874' }
        coldReadinessAmendment = [ordered]@{ relativePath = 'Research/Gate13_Readiness_Amendment.v1.json'; sha256 = '1ccf5c6e1e2c646d160e7b597381c797cc14e6123134a28b429fcb773515e8b2' }
        gate11BundleManifest = $provenance.gate11BundleManifest
        gate11Matrix = $provenance.gate11Matrix
        gate11Preregistration = $provenance.gate11Preregistration
    }
    pilotEvidence = $evidence
    processReuseDesign = [ordered]@{
        designId = 'one-fresh-unity-process-per-williams-block-v1'
        independentUnit = 'williams-block-unity-process-v1'
        withinProcessSamplesCorrelated = $true
        oneBlockPerUnityProcess = $true
        algorithmAtMostOncePerProcess = $true
        longLivedCampaignProcessAllowed = $false
    }
    sampleSizeDecision = [ordered]@{
        precisionRelativeHalfWidthTarget = 0.10
        formula = 'max-of-marginal-and-within-block-paired-requirements-v1'
        minimumIndependentBlocks = 30
        cycleMultiple = 4
        maximumIndependentBlocks = 148
        anyOverCap = $false
        cohorts = $cohorts
        families = @($candidate.families | Select-Object familyId, comparisonCohortId, marginalSigmaLog, pairedLogDifferenceSigma, conservativeRequiredNFormal, candidateNFormal, scheduledNFormal, overCap, harmonizationReason)
    }
    reservedFormalRoot = [ordered]@{
        relativePath = 'Research/FormalRuns/Gate13_ProcessReuse/v1'
        existsAtPreparation = $false
        creationAuthorized = $false
    }
    gate14Boundary = [ordered]@{
        futureAcceptedDesign = 'process-reuse-formal-only-after-separate-authorization-and-completion'
        coldRootRejected = $true
        processReusePilotRejected = $true
        mixedDesignTablesRejected = $true
    }
    pilotVerdict = 'PILOT-PASSED-FORMAL-NOT-AUTHORIZED'
}
Write-G13R2AtomicUtf8NoBomJson -Path $amendmentPath -Value $amendment -Depth 40
$config = New-G13R2PilotReestimatedFormalConfig -ProjectPath $ProjectPath -ProvenancePath $ProvenancePath -AmendmentPath $amendmentPath
Write-G13R2AtomicUtf8NoBomJson -Path $configPath -Value $config -Depth 50
$configCheck = Test-G13R2PilotReestimatedFormalConfig -ProjectPath $ProjectPath -Config $config -ConfigPath $configPath -ProvenancePath $ProvenancePath -AmendmentPath $amendmentPath
if (-not $configCheck.passed) { throw "Generated process-reuse config failed deterministic validation: $($configCheck.errors -join '; ')" }
if (Test-Path -LiteralPath $formalRoot) { throw 'Formal root appeared during non-executing preparation.' }

$preparationManifest = [ordered]@{
    schemaVersion = 1
    manifestId = 'gate13-r2-process-reuse-nonexecuting-preparation-manifest-v1'
    recordedAt = (Get-Date).ToString('o')
    provenance = [ordered]@{ relativePath = Get-G13R2ProjectRelativePath -ProjectPath $ProjectPath -FullPath $ProvenancePath; sha256 = Get-G13R2LowerSha256 -Path $ProvenancePath }
    pilotManifest = $evidence.pilotManifest
    amendment = [ordered]@{ relativePath = 'Research/Gate13_ProcessReuse_Amendment.v1.json'; sha256 = Get-G13R2LowerSha256 -Path $amendmentPath }
    config = [ordered]@{ relativePath = 'Research/Gate13_ProcessReuse_Formal_Campaign_Config.v1.json'; sha256 = Get-G13R2LowerSha256 -Path $configPath }
    configValidation = $configCheck
    formalOutputRootRelativePath = 'Research/FormalRuns/Gate13_ProcessReuse/v1'
    formalOutputRootExists = $false
    formalExecutionReceiptCreated = $false
    formalCampaignStarted = $false
    formalExecutionAuthorized = $false
    automaticRetryAuthorized = $false
    automaticResumeAuthorized = $false
    status = 'PILOT-COMPLETE-FORMAL-NOT-AUTHORIZED'
}
Write-G13R2AtomicUtf8NoBomJson -Path $manifestPath -Value $preparationManifest -Depth 30
$checkpoint = [ordered]@{
    schemaVersion = 1
    checkpointId = 'gate13-r2-process-reuse-preparation-checkpoint-v1'
    savedAt = (Get-Date).ToString('o')
    status = 'PILOT-COMPLETE-FORMAL-NOT-AUTHORIZED'
    pilotManifestSha256 = [string]$evidence.pilotManifest.sha256
    amendmentSha256 = Get-G13R2LowerSha256 -Path $amendmentPath
    configSha256 = Get-G13R2LowerSha256 -Path $configPath
    preparationManifestSha256 = Get-G13R2LowerSha256 -Path $manifestPath
    reservedFormalRootExists = $false
    formalExecutionReceiptCreated = $false
    formalCampaignStarted = $false
    formalExecutionAuthorized = $false
    automaticRetryAuthorized = $false
    automaticResumeAuthorized = $false
    nextRequiredAction = 'WAIT-FOR-SEPARATE-USER-AUTHORIZATION-OF-PROCESS-REUSE-FORMAL-CAMPAIGN'
}
Write-G13R2AtomicUtf8NoBomJson -Path $checkpointPath -Value $checkpoint -Depth 20

[pscustomobject][ordered]@{
    passed = $true
    amendmentPath = $amendmentPath
    amendmentSha256 = Get-G13R2LowerSha256 -Path $amendmentPath
    configPath = $configPath
    configSha256 = Get-G13R2LowerSha256 -Path $configPath
    preparationManifestPath = $manifestPath
    preparationManifestSha256 = Get-G13R2LowerSha256 -Path $manifestPath
    checkpointPath = $checkpointPath
    checkpointSha256 = Get-G13R2LowerSha256 -Path $checkpointPath
    expectedUnityBlockProcessCount = [int]$config.totals.expectedUnityBlockProcessCount
    expectedAlgorithmSampleCount = [int]$config.totals.expectedAlgorithmSampleCount
    formalRootCreated = $false
    formalExecutionAuthorized = $false
    status = 'PILOT-COMPLETE-FORMAL-NOT-AUTHORIZED'
} | ConvertTo-Json -Depth 10
exit 0
