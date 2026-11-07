[CmdletBinding()]
param([string]$ProjectPath = (Split-Path -Parent $PSScriptRoot))

$ErrorActionPreference = 'Stop'
$ProjectPath = [System.IO.Path]::GetFullPath($ProjectPath)
$modulePath = Join-Path $PSScriptRoot 'Gate13ProcessReusePreparation.psm1'
Import-Module $modulePath -Force
$outputPath = Join-Path $ProjectPath 'Research\Gate13_ProcessReuse_Provenance.v2.json'
$pilotRoot = Join-Path $ProjectPath 'Research\PilotRuns\Gate13_ProcessReuse\v1'
$formalRoot = Join-Path $ProjectPath 'Research\FormalRuns\Gate13_ProcessReuse\v1'
if (Test-Path -LiteralPath $outputPath) { throw "Create-new provenance already exists: $outputPath" }
if (Test-Path -LiteralPath $pilotRoot) { throw 'Pilot root exists before provenance v2 freeze.' }
if (Test-Path -LiteralPath $formalRoot) { throw 'Reserved formal root exists before provenance v2 freeze.' }
if (@(Get-Process -Name Unity -ErrorAction SilentlyContinue).Count -gt 0 -or (Test-Path -LiteralPath (Join-Path $ProjectPath 'Temp\UnityLockfile'))) { throw 'Unity must be stopped before provenance v2 freeze.' }

function New-BoundRecord([string]$RelativePath) {
    $path = Join-Path $ProjectPath $RelativePath.Replace('/', '\')
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Provenance source is missing: $RelativePath" }
    return [ordered]@{
        relativePath = $RelativePath
        sha256 = Get-G13R2LowerSha256 -Path $path
        byteCount = [int64](Get-Item -LiteralPath $path).Length
    }
}

$planPath = Join-Path $ProjectPath 'Research\Gate13_ProcessReuse_Pilot_Plan.v1.json'
$plan = Read-G13R2Json -Path $planPath
$planCheck = Test-G13R2PilotPlan -ProjectPath $ProjectPath -Plan $plan -PlanPath $planPath
if (-not $planCheck.passed) { throw "Pilot plan failed before provenance v2 freeze: $($planCheck.errors -join '; ')" }
$unityPath = [System.IO.Path]::GetFullPath(([string]$plan.unity.executablePath).Replace('/', '\'))
if ((Get-G13R2LowerSha256 -Path $unityPath) -ne [string]$plan.unity.executableSha256) { throw 'Unity executable hash mismatch before provenance v2 freeze.' }

$provenance = [ordered]@{
    schemaVersion = 2
    provenanceId = 'gate13-r2-process-reuse-provenance-v2'
    recordedAt = (Get-Date).ToString('o')
    materialPassport = [ordered]@{
        originSkill = 'experiment-agent'
        originMode = 'run'
        verificationStatus = 'IMPLEMENTATION-FROZEN-PRE-PILOT-AFTER-AUDIT-LAUNCH-FIX'
        versionLabel = 'gate13_r2_process_reuse_provenance_v2'
    }
    supersedes = [ordered]@{
        provenance = New-BoundRecord 'Research/Gate13_ProcessReuse_Provenance.v1.json'
        failedAuditEvidence = New-BoundRecord 'Research/Verification/Gate13R2_PrePilotAudit_Attempt1_Failure.v1.json'
        reason = 'Windows command-line length prevented the retained-regression child from starting; no pilot, negative Unity fixture, or formal root had been created.'
        designChanged = $false
        pilotSubsetChanged = $false
        statisticalPolicyChanged = $false
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
    specification = New-BoundRecord 'Research/Gate13_ProcessReuse_Specification.md'
    testDesign = New-BoundRecord 'Research/Gate13_ProcessReuse_Test_Design.md'
    pilotPlan = New-BoundRecord 'Research/Gate13_ProcessReuse_Pilot_Plan.v1.json'
    processReuseBatchCommand = New-BoundRecord 'Assets/_Scripts/Research/Editor/ResearchPlanningProcessReuseBatchCommand.cs'
    processReuseBatchCommandMeta = New-BoundRecord 'Assets/_Scripts/Research/Editor/ResearchPlanningProcessReuseBatchCommand.cs.meta'
    processReusePowerShellRunner = New-BoundRecord 'Research/Run-PlanningProcessReuseBlock.ps1'
    processReusePreparationModule = New-BoundRecord 'Research/Gate13ProcessReusePreparation.psm1'
    pilotOrchestrator = New-BoundRecord 'Research/Run-Gate13ProcessReusePilot.ps1'
    pilotAnalyzer = New-BoundRecord 'Research/Analyze-Gate13ProcessReusePilot.ps1'
    formalPreparationGenerator = New-BoundRecord 'Research/New-Gate13ProcessReuseFormalPreparation.ps1'
    provenanceGenerator = New-BoundRecord 'Research/New-Gate13ProcessReuseProvenanceV2.ps1'
    prePilotAuditScript = New-BoundRecord 'Research/Verification/Run-Gate13ProcessReusePrePilotAudit.ps1'
    unityCompileEvidence = New-BoundRecord 'Research/Verification/Gate13R2_ProcessReuse_Compile.v3.log'
    coldTerminationReceipt = New-BoundRecord 'Research/Gate13_ColdProcess_Termination_Receipt.v1.json'
    coldPreTerminationSnapshot = New-BoundRecord 'Research/Gate13_ColdProcess_PreTermination_Snapshot.v1.json'
    coldPartialOutputManifest = New-BoundRecord 'Research/Gate13_ColdProcess_Partial_Output_Manifest.v1.json'
    coldExclusionMarker = New-BoundRecord 'Research/Gate13_ColdProcess_Exclusion_Marker.v1.json'
    coldFormalConfig = New-BoundRecord 'Research/Gate13_Formal_Campaign_Config.v1.json'
    coldReadinessAmendment = New-BoundRecord 'Research/Gate13_Readiness_Amendment.v1.json'
    coldExecutionAuthorizationV1 = New-BoundRecord 'Research/Gate13_Execution_Authorization.v1.json'
    coldExecutionAuthorizationV2 = New-BoundRecord 'Research/Gate13_Execution_Authorization.v2.json'
    gate11BundleManifest = New-BoundRecord 'Research/FormalScenarios/v1/bundle-manifest.json'
    gate11Matrix = New-BoundRecord 'Research/FormalScenarios/v1/formal-scenario-matrix.json'
    gate11Preregistration = New-BoundRecord 'Research/FormalScenarios/v1/preregistered-analysis.json'
    gate12Plan = New-BoundRecord 'Research/Gate12_Pilot_Plan.v1.json'
    gate12SuccessfulPilotManifest = New-BoundRecord 'Research/PilotRuns/Gate12/v1/pilot-manifest.json'
    gate12FinalAudit = New-BoundRecord 'Research/Verification/Gate12_FinalAudit.summary.json'
    fairnessSpecification = New-BoundRecord 'Research/Four_Algorithm_Fairness_and_Unified_Campaign_Specification.md'
    workloadSpecification = New-BoundRecord 'Research/Scenario_IO_and_Planning_Workload_Specification.md'
    planningWorkloadRunner = New-BoundRecord 'Assets/_Scripts/Research/Experiments/DeterministicPlanningWorkloadRunner.cs'
    coldBatchCommand = New-BoundRecord 'Assets/_Scripts/Research/Editor/ResearchPlanningBatchCommand.cs'
    experimentRunner = New-BoundRecord 'Assets/_Scripts/Research/Experiments/ExperimentRunner.cs'
    jsonlLogger = New-BoundRecord 'Assets/_Scripts/Research/Logging/JsonlExperimentLogger.cs'
    fairnessContracts = New-BoundRecord 'Assets/_Scripts/Research/Experiments/PlanningFairnessContracts.cs'
    coldWorkloadPowerShellRunner = New-BoundRecord 'Research/Run-PlanningWorkload.ps1'
    unity = [ordered]@{
        executablePath = $unityPath
        productVersion = [string]$plan.unity.productVersion
        executableSha256 = Get-G13R2LowerSha256 -Path $unityPath
    }
    executionDesign = [ordered]@{
        designId = 'one-fresh-unity-process-per-williams-block-v1'
        independentUnit = 'williams-block-unity-process-v1'
        oneBlockPerUnityProcess = $true
        algorithmAtMostOncePerProcess = $true
        longLivedCampaignProcessAllowed = $false
        formalCampaign = $false
    }
    paths = [ordered]@{
        pilotRootRelativePath = 'Research/PilotRuns/Gate13_ProcessReuse/v1'
        reservedFormalRootRelativePath = 'Research/FormalRuns/Gate13_ProcessReuse/v1'
        pilotRootExistsAtFreeze = $false
        reservedFormalRootExistsAtFreeze = $false
    }
}
Write-G13R2AtomicUtf8NoBomJson -Path $outputPath -Value $provenance -Depth 30
[pscustomobject][ordered]@{
    passed = $true
    provenancePath = $outputPath
    provenanceSha256 = Get-G13R2LowerSha256 -Path $outputPath
    supersededProvenanceV1Preserved = $true
    failedAuditEvidencePreserved = $true
    pilotRootCreated = $false
    reservedFormalRootCreated = $false
    formalExecutionAuthorized = $false
} | ConvertTo-Json -Depth 8
exit 0
