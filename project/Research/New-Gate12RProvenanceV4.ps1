[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$ProjectPath,
    [Parameter(Mandatory=$true)][string]$OutputPath,
    [switch]$BindingSmokeOnly
)

$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
if([string]::IsNullOrWhiteSpace($ProjectPath)-or-not[IO.Path]::IsPathRooted($ProjectPath)){throw 'Gate12R v4 provenance requires an explicit absolute ProjectPath.'};$ProjectPath=[IO.Path]::GetFullPath($ProjectPath)
if($BindingSmokeOnly){Write-Output("BINDING-SMOKE-PASSED|New-Gate12RProvenanceV4|$ProjectPath");exit 0}
$OutputPath=if([IO.Path]::IsPathRooted($OutputPath)){[IO.Path]::GetFullPath($OutputPath)}else{[IO.Path]::GetFullPath((Join-Path $ProjectPath $OutputPath))};if(Test-Path $OutputPath){throw "Create-new provenance exists: $OutputPath"}
Import-Module (Join-Path $ProjectPath 'Research\Gate12RProcessReusePreparation.psm1') -Force
$v3Path=Join-Path $ProjectPath 'Research\Gate12R_5pct_ProcessReuse_Pilot_Provenance.v3.json';if((Get-Gate12RLowerSha256 $v3Path)-ne'0d34fa3d721ec8e1b08d2dce711d378c070526d01ea8bd98a04ccde27e74545c'){throw 'Frozen provenance v3 hash mismatch.'};$v3=Read-Gate12RJson $v3Path
$bound=New-Object Collections.Generic.List[object];foreach($binding in @($v3.boundFiles)){$bound.Add([pscustomobject][ordered]@{id=[string]$binding.id;relativePath=[string]$binding.relativePath;rawBytes=[long]$binding.rawBytes;sha256=[string]$binding.sha256})}
function Add-Binding([string]$Id,[string]$RelativePath){$path=Join-Path $ProjectPath $RelativePath.Replace('/','\');if(-not(Test-Path $path -PathType Leaf)){throw "Missing v4 provenance input: $RelativePath"};$item=Get-Item $path;$bound.Add([pscustomobject][ordered]@{id=$Id;relativePath=$RelativePath;rawBytes=[long]$item.Length;sha256=Get-Gate12RLowerSha256 $path})}
Add-Binding 'provenanceV3' 'Research/Gate12R_5pct_ProcessReuse_Pilot_Provenance.v3.json'
Add-Binding 'attempt2FailureDiagnosis' 'Research/Gate12R_Attempt2_Derived_PSScriptRoot_Failure_Diagnosis.v1.md'
Add-Binding 'telemetryRunnerV3' 'Research/Run-Gate12RTelemetryProbeV3.ps1'
Add-Binding 'coldRunnerV3' 'Research/Run-Gate12RColdReferenceV3.ps1'
Add-Binding 'blockRegressionGateV3' 'Research/Verification/Run-Gate12RBlockAndRegressionGatesV3.ps1'
Add-Binding 'pilotRunnerV3' 'Research/Run-Gate12RPilotV3.ps1'
Add-Binding 'prePilotAttemptV4' 'Research/Verification/Run-Gate12RPrePilotAttemptV4.ps1'
Add-Binding 'provenanceGeneratorV4' 'Research/New-Gate12RProvenanceV4.ps1'
$attempt2Root=Join-Path $ProjectPath 'Research\Verification\Gate12R_ProcessReuse_5pct\v2';if(-not(Test-Path $attempt2Root -PathType Container)){throw 'Frozen official attempt-2 root is missing.'};$attempt2Files=@(Get-ChildItem $attempt2Root -Recurse -File -Force|Sort-Object FullName);$treeRows=New-Object Collections.Generic.List[string];$ordinal=0;foreach($file in $attempt2Files){$ordinal++;$relative=Get-Gate12RProjectRelativePath $ProjectPath $file.FullName;$hash=Get-Gate12RLowerSha256 $file.FullName;$bound.Add([pscustomobject][ordered]@{id=('officialAttempt2File{0:D4}'-f$ordinal);relativePath=$relative;rawBytes=[long]$file.Length;sha256=$hash});$treeRows.Add(($relative+'|'+[long]$file.Length+'|'+$hash))}
function Select-Binding([string]$Id){return @($bound|Where-Object id -eq $Id)[0]}
$attempt2Failure=Read-Gate12RJson (Join-Path $attempt2Root 'failure-receipt.json');if([string]$attempt2Failure.status-ne'FAILED-VERSIONED-REPAIR-RETRY-ALLOWED'-or$attempt2Failure.pilotRootCreated-ne$false-or$attempt2Failure.formalRootCreated-ne$false){throw 'Official attempt-2 terminal state is not the expected frozen fail-closed state.'}
$document=[ordered]@{schemaVersion=4;provenanceId='gate12r-fresh-process-reuse-5pct-pilot-provenance-v4-derived-module-path-compatibility';createdAtUtc=[DateTime]::UtcNow.ToString('o');status='FROZEN-BEFORE-OFFICIAL-GATE12R-PRE-PILOT-ATTEMPT-3';attempt=3;implementationRevision=4;changeClass='DERIVED-SCRIPT-EXPLICIT-PROJECT-RESEARCH-MODULE-PATH-AND-CHILD-LOG-CAPTURE-ONLY';researchSemanticsChanged=$false;executionDesignId='gate10r-one-fresh-unity-process-per-williams-block-5pct-v1';config=Select-Binding 'pilotPlan';specification=Select-Binding 'specification';testDesign=Select-Binding 'testDesign';executionAuthorization=Select-Binding 'executionAuthorization';unityCommand=Select-Binding 'unityCommand';activePreservationBaseline=Select-Binding 'preservationBaselineV2';activeStaticUnitGate=Select-Binding 'staticUnitGateV2';activeCompileGate=Select-Binding 'compileGateV2';activeTelemetryRunner=Select-Binding 'telemetryRunnerV3';activeColdRunner=Select-Binding 'coldRunnerV3';activeBlockRegressionGate=Select-Binding 'blockRegressionGateV3';activePilotRunner=Select-Binding 'pilotRunnerV3';activePrePilotAttempt=Select-Binding 'prePilotAttemptV4';officialAttempt1=$v3.officialAttempt1;officialAttempt2=[ordered]@{root='Research/Verification/Gate12R_ProcessReuse_5pct/v2';fileCount=$attempt2Files.Count;rawBytes=[long](($attempt2Files|Measure-Object Length -Sum).Sum);treeSha256=Get-Gate12RStringSha256 ($treeRows.ToArray()-join"`n");status='FAILED-VERSIONED-REPAIR-RETRY-ALLOWED';compilePassed=$true;telemetryUnityStarted=$false;pilotRootCreated=$false;formalRootCreated=$false};boundFiles=$bound.ToArray();authorizedGate11BundleSha256='5baaeec18344a9e99e55da38f3c4875b7e7e9f3bf0add9d5f2d2f1e821b5f7fc';precisionTargetRelativeHalfWidth=0.05;hardCap=$null;processUnit='one-fresh-unity-editor-process-per-complete-williams-block';formalCampaign=$false;pilotExcludedFromFormalAnalysis=$true;versionedRepairRetryAuthorized=$true;sameAttemptResumeAuthorized=$false;partialAttemptMergeAuthorized=$false;gate13rAuthorized=$false}
Write-Gate12RAtomicUtf8NoBomJson -Path $OutputPath -Value $document -Depth 50;Write-Host "Gate12R v4 provenance frozen: $OutputPath" -ForegroundColor Green;exit 0

