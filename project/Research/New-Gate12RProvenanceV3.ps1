[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$ProjectPath,
    [Parameter(Mandatory=$true)][string]$OutputPath,
    [switch]$BindingSmokeOnly
)

$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
if([string]::IsNullOrWhiteSpace($ProjectPath)-or-not[IO.Path]::IsPathRooted($ProjectPath)){throw 'Gate12R v3 provenance requires an explicit absolute ProjectPath.'};$ProjectPath=[IO.Path]::GetFullPath($ProjectPath)
if($BindingSmokeOnly){Write-Output("BINDING-SMOKE-PASSED|New-Gate12RProvenanceV3|$ProjectPath");exit 0}
$OutputPath=if([IO.Path]::IsPathRooted($OutputPath)){[IO.Path]::GetFullPath($OutputPath)}else{[IO.Path]::GetFullPath((Join-Path $ProjectPath $OutputPath))};if(Test-Path $OutputPath){throw "Create-new provenance exists: $OutputPath"}
Import-Module (Join-Path $ProjectPath 'Research\Gate12RProcessReusePreparation.psm1') -Force
$v2Path=Join-Path $ProjectPath 'Research\Gate12R_5pct_ProcessReuse_Pilot_Provenance.v2.json';if((Get-Gate12RLowerSha256 $v2Path)-ne'd1d79d70c78d2abe48eaf5e7b698eb7366db019027b78b96033957d7cc2f4c69'){throw 'Frozen provenance v2 hash mismatch.'};$v2=Read-Gate12RJson $v2Path
$bound=New-Object Collections.Generic.List[object];foreach($binding in @($v2.boundFiles)){$bound.Add([pscustomobject][ordered]@{id=[string]$binding.id;relativePath=[string]$binding.relativePath;rawBytes=[long]$binding.rawBytes;sha256=[string]$binding.sha256})}
function Add-Binding([string]$Id,[string]$RelativePath){$path=Join-Path $ProjectPath $RelativePath.Replace('/','\');if(-not(Test-Path $path -PathType Leaf)){throw "Missing v3 provenance input: $RelativePath"};$item=Get-Item $path;$bound.Add([pscustomobject][ordered]@{id=$Id;relativePath=$RelativePath;rawBytes=[long]$item.Length;sha256=Get-Gate12RLowerSha256 $path})}
Add-Binding 'provenanceV2' 'Research/Gate12R_5pct_ProcessReuse_Pilot_Provenance.v2.json'
Add-Binding 'attempt1FailureDiagnosis' 'Research/Gate12R_Attempt1_Compile_Count_Failure_Diagnosis.v1.md'
Add-Binding 'compileGateV2' 'Research/Verification/Run-Gate12RCompileV2.ps1'
Add-Binding 'telemetryRunnerV2' 'Research/Run-Gate12RTelemetryProbeV2.ps1'
Add-Binding 'coldRunnerV2' 'Research/Run-Gate12RColdReferenceV2.ps1'
Add-Binding 'blockRegressionGateV2' 'Research/Verification/Run-Gate12RBlockAndRegressionGatesV2.ps1'
Add-Binding 'pilotRunnerV2' 'Research/Run-Gate12RPilotV2.ps1'
Add-Binding 'prePilotAttemptV3' 'Research/Verification/Run-Gate12RPrePilotAttemptV3.ps1'
Add-Binding 'provenanceGeneratorV3' 'Research/New-Gate12RProvenanceV3.ps1'
$attempt1Root=Join-Path $ProjectPath 'Research\Verification\Gate12R_ProcessReuse_5pct\v1';if(-not(Test-Path $attempt1Root -PathType Container)){throw 'Frozen official attempt-1 root is missing.'};$attempt1Files=@(Get-ChildItem $attempt1Root -Recurse -File -Force|Sort-Object FullName);$treeRows=New-Object Collections.Generic.List[string];$ordinal=0;foreach($file in $attempt1Files){$ordinal++;$relative=Get-Gate12RProjectRelativePath $ProjectPath $file.FullName;$hash=Get-Gate12RLowerSha256 $file.FullName;$bound.Add([pscustomobject][ordered]@{id=('officialAttempt1File{0:D4}'-f$ordinal);relativePath=$relative;rawBytes=[long]$file.Length;sha256=$hash});$treeRows.Add(($relative+'|'+[long]$file.Length+'|'+$hash))}
function Select-Binding([string]$Id){return @($bound|Where-Object id -eq $Id)[0]}
$attempt1Failure=Read-Gate12RJson (Join-Path $attempt1Root 'failure-receipt.json');if([string]$attempt1Failure.status-ne'FAILED-VERSIONED-REPAIR-RETRY-ALLOWED'-or$attempt1Failure.pilotRootCreated-ne$false-or$attempt1Failure.formalRootCreated-ne$false){throw 'Official attempt-1 terminal state is not the expected frozen fail-closed state.'}
$document=[ordered]@{schemaVersion=3;provenanceId='gate12r-fresh-process-reuse-5pct-pilot-provenance-v3-ps51-empty-array-compatibility';createdAtUtc=[DateTime]::UtcNow.ToString('o');status='FROZEN-BEFORE-OFFICIAL-GATE12R-PRE-PILOT-ATTEMPT-2';attempt=2;implementationRevision=3;changeClass='WINDOWS-POWERSHELL-5.1-EMPTY-ARRAY-COMPATIBILITY-AND-VERSIONED-ROUTING-ONLY';researchSemanticsChanged=$false;executionDesignId='gate10r-one-fresh-unity-process-per-williams-block-5pct-v1';config=Select-Binding 'pilotPlan';specification=Select-Binding 'specification';testDesign=Select-Binding 'testDesign';executionAuthorization=Select-Binding 'executionAuthorization';unityCommand=Select-Binding 'unityCommand';activePreservationBaseline=Select-Binding 'preservationBaselineV2';activeStaticUnitGate=Select-Binding 'staticUnitGateV2';activeCompileGate=Select-Binding 'compileGateV2';activeTelemetryRunner=Select-Binding 'telemetryRunnerV2';activeColdRunner=Select-Binding 'coldRunnerV2';activeBlockRegressionGate=Select-Binding 'blockRegressionGateV2';activePilotRunner=Select-Binding 'pilotRunnerV2';activePrePilotAttempt=Select-Binding 'prePilotAttemptV3';officialAttempt1=[ordered]@{root='Research/Verification/Gate12R_ProcessReuse_5pct/v1';fileCount=$attempt1Files.Count;rawBytes=[long](($attempt1Files|Measure-Object Length -Sum).Sum);treeSha256=Get-Gate12RStringSha256 ($treeRows.ToArray()-join"`n");status='FAILED-VERSIONED-REPAIR-RETRY-ALLOWED';pilotRootCreated=$false;formalRootCreated=$false};boundFiles=$bound.ToArray();authorizedGate11BundleSha256='5baaeec18344a9e99e55da38f3c4875b7e7e9f3bf0add9d5f2d2f1e821b5f7fc';precisionTargetRelativeHalfWidth=0.05;hardCap=$null;processUnit='one-fresh-unity-editor-process-per-complete-williams-block';formalCampaign=$false;pilotExcludedFromFormalAnalysis=$true;versionedRepairRetryAuthorized=$true;sameAttemptResumeAuthorized=$false;partialAttemptMergeAuthorized=$false;gate13rAuthorized=$false}
Write-Gate12RAtomicUtf8NoBomJson -Path $OutputPath -Value $document -Depth 40;Write-Host "Gate12R v3 provenance frozen: $OutputPath" -ForegroundColor Green;exit 0

