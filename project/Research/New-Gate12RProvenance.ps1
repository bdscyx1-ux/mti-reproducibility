[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$ProjectPath,
    [Parameter(Mandatory=$true)][string]$OutputPath,
    [switch]$BindingSmokeOnly
)

$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
if([string]::IsNullOrWhiteSpace($ProjectPath)-or-not[IO.Path]::IsPathRooted($ProjectPath)){throw 'Gate12R provenance generation requires an explicit absolute ProjectPath.'}
$ProjectPath=[IO.Path]::GetFullPath($ProjectPath)
if($BindingSmokeOnly){Write-Output("BINDING-SMOKE-PASSED|New-Gate12RProvenance|$ProjectPath");exit 0}
$OutputPath=if([IO.Path]::IsPathRooted($OutputPath)){[IO.Path]::GetFullPath($OutputPath)}else{[IO.Path]::GetFullPath((Join-Path $ProjectPath $OutputPath))}
Import-Module (Join-Path $ProjectPath 'Research\Gate12RProcessReusePreparation.psm1') -Force
if(Test-Path -LiteralPath $OutputPath){throw "Create-new provenance output exists: $OutputPath"}
$root=$ProjectPath.TrimEnd('\')+'\';if(-not$OutputPath.StartsWith($root,[StringComparison]::OrdinalIgnoreCase)){throw 'Provenance output escapes project root.'}
$sources=[ordered]@{
    pilotPlan='Research/Gate12R_5pct_ProcessReuse_Pilot_Plan.v1.json'
    specification='Research/Gate12R_5pct_ProcessReuse_Pilot_Specification.v1.md'
    testDesign='Research/Gate12R_5pct_ProcessReuse_Pilot_Test_Design.v1.md'
    executionAuthorization='Research/Gate12R_Execution_Authorization.v1.json'
    preservationBaseline='Research/Gate12R_PreWrite_Preservation_Baseline.v1.json'
    gate10PassedCheckpoint='Research/Gate10R_Attempt4_Passed_Checkpoint.md'
    gate11PassedCheckpoint='Research/Gate11R_Attempt2_Passed_Checkpoint.md'
    gate11BundleManifest='Research/FormalScenarios/Gate11R_5pct/v1/bundle-manifest.json'
    gate11Matrix='Research/FormalScenarios/Gate11R_5pct/v1/formal-scenario-matrix.json'
    gate11Preregistration='Research/FormalScenarios/Gate11R_5pct/v1/preregistered-analysis.json'
    campaignCatalog='Research/PlayableExperiments/Gate11R_5pct/v1/campaign-profile-catalog.json'
    presetCatalog='Research/PlayableExperiments/Gate11R_5pct/v1/algorithm-preset-catalog.json'
    sceneCatalog='Research/PlayableExperiments/Gate11R_5pct/v1/playable-scene-catalog.json'
    coverageManifest='Research/PlayableExperiments/Gate11R_5pct/v1/coverage-manifest.json'
    gate10Module='Research/Gate10RProcessReusePreparation.psm1'
    lockHygieneModule='Research/Gate10RLockHygieneV3.psm1'
    unityCommand='Assets/_Scripts/Research/Editor/Gate10RProcessReuseBatchCommand.cs'
    retainedHarness='Research/Verification/Gate10RAttempt4RetainedHarnessV4.ps1'
    retainedFrozenSource='Research/Verification/Run-Gate12AnalysisUnitTests.ps1'
    retainedFrozenSummary='Research/Verification/Gate12_AnalysisUnitTests.summary.json'
    gate12Module='Research/Gate12RProcessReusePreparation.psm1'
    blockRunner='Research/Run-Gate12RProcessReuseBlock.ps1'
    telemetryRunner='Research/Run-Gate12RTelemetryProbe.ps1'
    coldRunner='Research/Run-Gate12RColdReference.ps1'
    analyzer='Research/Analyze-Gate12RPilot.ps1'
    pilotRunner='Research/Run-Gate12RPilot.ps1'
    compileGate='Research/Verification/Run-Gate12RCompile.ps1'
    staticUnitGate='Research/Verification/Run-Gate12RStaticUnitAudit.ps1'
    blockRegressionGate='Research/Verification/Run-Gate12RBlockAndRegressionGates.ps1'
    validationOnlyAudit='Research/Verification/Run-Gate12RValidationOnlyPrePilotAudit.ps1'
    postPilotAudit='Research/Verification/Run-Gate12RPostPilotReadinessAudit.ps1'
    prePilotAttempt='Research/Verification/Run-Gate12RPrePilotAttempt.ps1'
    provenanceGenerator='Research/New-Gate12RProvenance.ps1'
}
$bound=New-Object Collections.Generic.List[object]
foreach($property in $sources.GetEnumerator()){$path=Join-Path $ProjectPath ([string]$property.Value).Replace('/','\');if(-not(Test-Path -LiteralPath $path -PathType Leaf)){throw "Provenance input missing: $($property.Value)"};$file=Get-Item -LiteralPath $path;$bound.Add([pscustomobject][ordered]@{id=[string]$property.Key;relativePath=[string]$property.Value;rawBytes=[long]$file.Length;sha256=Get-Gate12RLowerSha256 $path})}
function Select-Binding([string]$Id){return @($bound|Where-Object id -eq $Id)[0]}
$document=[ordered]@{
    schemaVersion=1
    provenanceId='gate12r-fresh-process-reuse-5pct-pilot-provenance-v1'
    createdAtUtc=[DateTime]::UtcNow.ToString('o')
    status='FROZEN-BEFORE-OFFICIAL-GATE12R-PRE-PILOT-ATTEMPT'
    attempt=1
    executionDesignId='gate10r-one-fresh-unity-process-per-williams-block-5pct-v1'
    config=Select-Binding 'pilotPlan'
    specification=Select-Binding 'specification'
    testDesign=Select-Binding 'testDesign'
    executionAuthorization=Select-Binding 'executionAuthorization'
    unityCommand=Select-Binding 'unityCommand'
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
Write-Gate12RAtomicUtf8NoBomJson -Path $OutputPath -Value $document -Depth 30
Write-Host "Gate12R provenance frozen: $OutputPath" -ForegroundColor Green
exit 0
