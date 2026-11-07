[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$ProjectPath)

$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
if([string]::IsNullOrWhiteSpace($ProjectPath)-or-not[IO.Path]::IsPathRooted($ProjectPath)){throw 'ProjectPath must be an explicit absolute path.'};$ProjectPath=[IO.Path]::GetFullPath($ProjectPath)
Import-Module (Join-Path $ProjectPath 'Research\Gate12RProcessReusePreparation.psm1') -Force

$sourcePath=Join-Path $ProjectPath 'Research\Gate12R_5pct_ProcessReuse_Pilot_Provenance.v4.json'
$outputPath=Join-Path $ProjectPath 'Research\Gate12R_5pct_ProcessReuse_Pilot_Provenance.v5.json'
$expectedSourceSha256='637155dadfee477c0b2682937b1e3f190fe947dda9d916356cbe48fea2682638'
if(Test-Path -LiteralPath $outputPath){throw "Create-new provenance v5 exists: $outputPath"}
if((Get-Gate12RLowerSha256 $sourcePath)-ne$expectedSourceSha256){throw 'Frozen provenance v4 hash changed.'}
$v4=Read-Gate12RJson $sourcePath
$bound=New-Object Collections.Generic.List[object]
foreach($binding in @($v4.boundFiles)){$bound.Add([pscustomobject][ordered]@{id=[string]$binding.id;relativePath=[string]$binding.relativePath;rawBytes=[long]$binding.rawBytes;sha256=[string]$binding.sha256})}

function Add-Binding([string]$Id,[string]$RelativePath){
    if(@($bound|Where-Object id -eq $Id).Count-ne0){throw "Duplicate provenance binding id: $Id"}
    $path=Join-Path $ProjectPath $RelativePath.Replace('/','\');if(-not(Test-Path -LiteralPath $path -PathType Leaf)){throw "Binding file missing: $RelativePath"}
    $item=Get-Item -LiteralPath $path;$bound.Add([pscustomobject][ordered]@{id=$Id;relativePath=$RelativePath;rawBytes=[long]$item.Length;sha256=Get-Gate12RLowerSha256 $path})
}
function Select-Binding([string]$Id){$matches=@($bound|Where-Object id -eq $Id);if($matches.Count-ne1){throw "Binding does not resolve exactly once: $Id"};return $matches[0]}

Add-Binding 'provenanceV4' 'Research/Gate12R_5pct_ProcessReuse_Pilot_Provenance.v4.json'
Add-Binding 'pilotPlanV2' 'Research/Gate12R_5pct_ProcessReuse_Pilot_Plan.v2.json'
Add-Binding 'pilotPlanV2Derivation' 'Research/Gate12R_PilotPlanV2_Derivation.v1.json'
Add-Binding 'pilotPlanV2Generator' 'Research/Verification/New-Gate12RPilotPlanV2.ps1'
Add-Binding 'pilotAttempt1FailureDiagnosis' 'Research/Gate12R_PilotAttempt1_ManagedMemory_Failure_Diagnosis.v1.md'
Add-Binding 'pilotAttempt1Preservation' 'Research/Gate12R_PilotAttempt1_Terminal_Preservation.v1.json'
Add-Binding 'pilotAttempt1PreservationGenerator' 'Research/Verification/New-Gate12RPilotAttempt1PreservationManifest.ps1'
Add-Binding 'pilotAttempt1PartialManifest' 'Research/PilotRuns/Gate12R_ProcessReuse_5pct/v1/partial-output-manifest.json'
Add-Binding 'pilotAttempt1FailureReceipt' 'Research/PilotRuns/Gate12R_ProcessReuse_5pct/v1/failure-receipt.json'
Add-Binding 'pilotAttempt1Checkpoint' 'Research/PilotRuns/Gate12R_ProcessReuse_5pct/v1/pilot-checkpoint.json'
Add-Binding 'pilotAttempt1LockRecoveryScript' 'Research/Verification/Move-Gate12RPilotAttempt1StaleUnityLockToEvidence.ps1'
Add-Binding 'pilotAttempt1LockPreMoveReceipt' 'Research/Verification/Gate12R_PilotAttempt1_StaleLock_Recovery/v1/pre-move-receipt.json'
Add-Binding 'pilotAttempt1LockRecoveryReceipt' 'Research/Verification/Gate12R_PilotAttempt1_StaleLock_Recovery/v1/recovery-receipt.json'
Add-Binding 'pilotAttempt1RecoveredLockBytes' 'Research/Verification/Gate12R_PilotAttempt1_StaleLock_Recovery/v1/UnityLockfile.stale-attempt1'
Add-Binding 'officialPrePilotAttempt3Manifest' 'Research/Verification/Gate12R_ProcessReuse_5pct/v3/partial-output-manifest.json'
Add-Binding 'officialPrePilotAttempt3Checkpoint' 'Research/Verification/Gate12R_ProcessReuse_5pct/v3/gate12r-checkpoint.json'
Add-Binding 'officialPrePilotAttempt3Audit' 'Research/Verification/Gate12R_ProcessReuse_5pct/v3/ValidationOnlyPrePilotAudit.summary.json'
Add-Binding 'unityCommandV2' 'Assets/_Scripts/Research/Editor/Gate12RProcessReuseBatchCommandV2.cs'
Add-Binding 'unityCommandV2Derivation' 'Research/Gate12R_ProcessReuse_CommandV2_Derivation.v1.json'
Add-Binding 'unityCommandV2Generator' 'Research/Verification/New-Gate12RProcessReuseBatchCommandV2.ps1'
Add-Binding 'blockRunnerV2' 'Research/Run-Gate12RProcessReuseBlockV2.ps1'
Add-Binding 'blockRunnerV2Derivation' 'Research/Gate12R_ProcessReuse_BlockRunnerV2_Derivation.v1.json'
Add-Binding 'blockRunnerV2Generator' 'Research/Verification/New-Gate12RProcessReuseBlockRunnerV2.ps1'
Add-Binding 'compileGateV3' 'Research/Verification/Run-Gate12RCompileV3.ps1'
Add-Binding 'staticUnitGateV3' 'Research/Verification/Run-Gate12RStaticUnitAuditV3.ps1'
Add-Binding 'validationOnlyGateV2' 'Research/Verification/Run-Gate12RValidationOnlyPrePilotAuditV2.ps1'
Add-Binding 'blockRegressionGateV4' 'Research/Verification/Run-Gate12RBlockAndRegressionGatesV4.ps1'
Add-Binding 'pilotRunnerV4' 'Research/Run-Gate12RPilotV4.ps1'
Add-Binding 'prePilotAttemptV5' 'Research/Verification/Run-Gate12RPrePilotAttemptV5.ps1'

$ids=@($bound|ForEach-Object id);if(@($ids|Sort-Object -Unique).Count-ne$ids.Count){throw 'Provenance binding IDs are not unique.'}
foreach($binding in $bound){$path=Join-Path $ProjectPath ([string]$binding.relativePath).Replace('/','\');if((Get-Gate12RLowerSha256 $path)-ne[string]$binding.sha256-or[long](Get-Item $path).Length-ne[long]$binding.rawBytes){throw "Binding changed during construction: $($binding.relativePath)"}}

$pilotV1Preservation=Read-Gate12RJson (Join-Path $ProjectPath 'Research\Gate12R_PilotAttempt1_Terminal_Preservation.v1.json')
if([string]$pilotV1Preservation.status-ne'FAILED-NO-RESUME-NO-MERGE'-or$pilotV1Preservation.independentFullHashAuditPassed-ne$true-or$pilotV1Preservation.eligibleForSampleSizeEstimation-ne$false){throw 'Pilot attempt-1 preservation terminal claims are invalid.'}
$attempt3Checkpoint=Read-Gate12RJson (Join-Path $ProjectPath 'Research\Verification\Gate12R_ProcessReuse_5pct\v3\gate12r-checkpoint.json')
if([string]$attempt3Checkpoint.status-ne'PRE-PILOT-GATES-PASSED-PILOT-NOT-YET-STARTED'-or$attempt3Checkpoint.pilotRootPresent-ne$false-or$attempt3Checkpoint.formalRootPresent-ne$false){throw 'Official pre-pilot attempt 3 is not the frozen passing upstream.'}
$planV2=Read-Gate12RJson (Join-Path $ProjectPath 'Research\Gate12R_5pct_ProcessReuse_Pilot_Plan.v2.json')
if([int]$planV2.attempt-ne2-or[string]$planV2.paths.pilotRootRelativePath-ne'Research/PilotRuns/Gate12R_ProcessReuse_5pct/v2'-or[double]$planV2.precision.relativeHalfWidth-ne0.05-or$null-ne$planV2.precision.hardCap){throw 'Pilot plan v2 attempt/root/precision boundary is invalid.'}
if(Test-Path -LiteralPath (Join-Path $ProjectPath 'Research\PilotRuns\Gate12R_ProcessReuse_5pct\v2')){throw 'Pilot v2 root must remain absent before provenance freeze.'}
if(Test-Path -LiteralPath (Join-Path $ProjectPath 'Research\FormalRuns\Gate13R_ProcessReuse_5pct\v1')){throw 'Gate13R formal root must remain absent.'}

$document=[ordered]@{
    schemaVersion=5
    provenanceId='gate12r-fresh-process-reuse-5pct-pilot-provenance-v5-planner-reset-contract-repair'
    createdAtUtc=[DateTime]::UtcNow.ToString('o')
    status='FROZEN-BEFORE-RESET-DIAGNOSTIC-AND-OFFICIAL-PREPILOT-ATTEMPT-4'
    attempt=4
    pilotAttempt=2
    implementationRevision=5
    changeClass='POST-RAW-TELEMETRY-PER-SAMPLE-PLANNER-RESET-CONTRACT-CORRECTION'
    researchSemanticsChanged=$false
    timedWorkloadSemanticsChanged=$false
    rawTelemetrySemanticsChanged=$false
    cleanupImplementationChanged=$true
    frozenThresholdsChanged=$false
    executionDesignId='gate10r-one-fresh-unity-process-per-williams-block-5pct-v1'
    config=Select-Binding 'pilotPlanV2'
    specification=$v4.specification
    testDesign=$v4.testDesign
    executionAuthorization=$v4.executionAuthorization
    unityCommand=Select-Binding 'unityCommandV2'
    activePreservationBaseline=$v4.activePreservationBaseline
    activeBlockRunner=Select-Binding 'blockRunnerV2'
    activeStaticUnitGate=Select-Binding 'staticUnitGateV3'
    activeCompileGate=Select-Binding 'compileGateV3'
    activeTelemetryRunner=$v4.activeTelemetryRunner
    activeColdRunner=$v4.activeColdRunner
    activeValidationOnlyGate=Select-Binding 'validationOnlyGateV2'
    activeBlockRegressionGate=Select-Binding 'blockRegressionGateV4'
    activePilotRunner=Select-Binding 'pilotRunnerV4'
    activePrePilotAttempt=Select-Binding 'prePilotAttemptV5'
    officialAttempt1=$v4.officialAttempt1
    officialAttempt2=$v4.officialAttempt2
    officialAttempt3=[ordered]@{
        root='Research/Verification/Gate12R_ProcessReuse_5pct/v3'
        rootFileCountIncludingPartialManifest=284
        rootRawBytesIncludingPartialManifest=21628515L
        partialManifestSha256='b64d9685f8a3d477033c7cd38aac6d45df664454d71a886c0e80b8e28ed7d227'
        status='PRE-PILOT-GATES-PASSED-PILOT-NOT-YET-STARTED'
        staticUnitPassed=$true
        unityCompilePassed=$true
        telemetryPassed=$true
        blockRegressionPassed=$true
        retainedRegressionAssertions=63
        validationOnlyChecks=121
        pilotRootCreated=$false
        formalRootCreated=$false
    }
    nonFormalPilotAttempt1=[ordered]@{
        root='Research/PilotRuns/Gate12R_ProcessReuse_5pct/v1'
        status='FAILED-NO-RESUME-NO-MERGE'
        completedEntryCount=246
        completedMeasuredBlockCount=202
        completedMeasuredSampleCount=608
        primaryFailure='block-retained-managed-memory-growth-over-128MiB'
        preservationManifest=Select-Binding 'pilotAttempt1Preservation'
        partialManifest=Select-Binding 'pilotAttempt1PartialManifest'
        eligibleForAnalysis=$false
        eligibleForSampleSizeEstimation=$false
        resumeAuthorized=$false
        mergeAuthorized=$false
    }
    resetContractRepair=[ordered]@{
        diagnosis=Select-Binding 'pilotAttempt1FailureDiagnosis'
        derivedCommand=Select-Binding 'unityCommandV2'
        derivationReceipt=Select-Binding 'unityCommandV2Derivation'
        resetPosition='after-raw-after-workload-telemetry-before-core-return'
        timedWorkloadChanged=$false
        rawTelemetryBoundaryChanged=$false
        focusedFreshProcessDiagnosticRequired=$true
        completePrePilotRerunRequired=$true
    }
    boundFiles=$bound.ToArray()
    authorizedGate11BundleSha256='5baaeec18344a9e99e55da38f3c4875b7e7e9f3bf0add9d5f2d2f1e821b5f7fc'
    precisionTargetRelativeHalfWidth=0.05
    hardCap=$null
    processUnit='one-fresh-unity-editor-process-per-complete-williams-block'
    formalCampaign=$false
    pilotExcludedFromFormalAnalysis=$true
    versionedRepairRetryAuthorized=$true
    sameAttemptResumeAuthorized=$false
    partialAttemptMergeAuthorized=$false
    gate13rAuthorized=$false
}
Write-Gate12RUtf8NoBomJson -Path $outputPath -Value $document -Depth 50
Write-Host "Gate12R provenance v5 frozen: $outputPath" -ForegroundColor Green

