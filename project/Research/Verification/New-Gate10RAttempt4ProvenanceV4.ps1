[CmdletBinding()]
param([Parameter(Mandatory = $true)][string]$ProjectPath)

$ErrorActionPreference='Stop'
if ([string]::IsNullOrWhiteSpace($ProjectPath) -or -not [IO.Path]::IsPathRooted($ProjectPath)) { throw 'An explicit absolute ProjectPath is required.' }
$ProjectPath=[IO.Path]::GetFullPath($ProjectPath)
$outputPath=Join-Path $ProjectPath 'Research\Gate10R_ProcessReuse_5pct_Attempt4_Provenance.v4.json'
if(Test-Path -LiteralPath $outputPath){throw 'Attempt-4 provenance exists; refusing overwrite.'}
function Get-LowerSha([string]$Path){(Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToLowerInvariant()}
function Get-StringSha([string]$Value){$sha=[Security.Cryptography.SHA256]::Create();try{$bytes=[Text.Encoding]::UTF8.GetBytes($Value);-join($sha.ComputeHash($bytes)|ForEach-Object{$_.ToString('x2')})}finally{$sha.Dispose()}}
function Get-Tree([string]$Path){$root=[IO.Path]::GetFullPath($Path).TrimEnd('\');$files=@(Get-ChildItem -LiteralPath $root -Recurse -File -Force|Sort-Object FullName);$rows=@($files|ForEach-Object{$relative=$_.FullName.Substring($root.Length).TrimStart('\').Replace('\','/');"$relative`t$($_.Length)`t$(Get-LowerSha $_.FullName)"});[ordered]@{fileCount=$files.Count;rawBytes=[long](($files|Measure-Object Length -Sum).Sum);treeSha256=Get-StringSha($rows-join"`n")}}
$relativePaths=@(
 'Research/Gate10R_ProcessReuse_5pct_Specification.md',
 'Research/Gate10R_ProcessReuse_5pct_Test_Design.md',
 'Research/Gate10R_ProcessReuse_5pct_Config.v1.json',
 'Research/Gate10R_Attempt4_RetainedRegression_FileScope_Specification.v1.md',
 'Research/Gate10R_Attempt4_RetainedRegression_Test_Design.v1.md',
 'Research/Gate10R_Attempt4_Execution_Authorization.v1.json',
 'Research/Gate10R_Attempt4_PreWrite_Preservation_Audit.v1.json',
 'Research/Gate10R_ProcessReuse_5pct_Attempt4_Config.v4.json',
 'Research/Gate10R_Attempt3_RetainedRegression_Failure_Diagnosis.v1.md',
 'Research/Gate10R_Attempt3_Final_Integrity_Audit.v1.json',
 'Research/Gate10R_to_Gate12R_LedgerEntries/041-user-attempt4-authorization-source.txt',
 'Assets/_Scripts/Research/Editor/Gate10RProcessReuseBatchCommand.cs',
 'Assets/_Scripts/Research/Editor/Gate10RProcessReuseBatchCommand.cs.meta',
 'Research/Gate10RProcessReusePreparation.psm1',
 'Research/Gate10RLockHygieneV3.psm1',
 'Research/Run-Gate10RProcessReuseBlockV4.ps1',
 'Research/Run-Gate10RTelemetryProbeV4.ps1',
 'Research/Run-Gate10RColdReferenceV4.ps1',
 'Research/Verification/New-Gate10RAttempt4SourcesV4.ps1',
 'Research/Verification/New-Gate10RAttempt4ProvenanceV4.ps1',
 'Research/Verification/Gate10RAttempt4RetainedHarnessV4.ps1',
 'Research/Verification/Run-Gate10RAttempt4OutsideRootPreflightV4.ps1',
 'Research/Verification/Run-Gate10RAttempt4OfficialPreflightV4.ps1',
 'Research/Verification/Run-Gate10RUnitTestsV4.ps1',
 'Research/Verification/Run-Gate10RCompileV4.ps1',
 'Research/Verification/Run-Gate10RBlockVerificationV4.ps1',
 'Research/Verification/Run-Gate10RRetainedRegressionV4.ps1',
 'Research/Verification/Run-Gate10RFinalAuditV4.ps1',
 'Research/Verification/Run-Gate12AnalysisUnitTests.ps1',
 'Research/Verification/Gate12_AnalysisUnitTests.summary.json',
 'Research/Gate10R_Onward_ProcessReuse_5pct_Experiment_Plan.md',
 'Research/Gate10R_5pct_Rebaseline_Decision.v1.json',
 'Research/Gate10R_5pct_Rebaseline_Evidence_Audit.v1.json',
 'Research/Gate10R_5pct_Rebaseline_Planning_Manifest.v1.json'
)
$bound=New-Object Collections.Generic.List[object]
foreach($relative in $relativePaths){$path=Join-Path $ProjectPath $relative.Replace('/','\');if(-not(Test-Path -LiteralPath $path -PathType Leaf)){throw "Bound file missing: $relative"};$item=Get-Item -LiteralPath $path;$bound.Add([ordered]@{relativePath=$relative;bytes=[long]$item.Length;sha256=Get-LowerSha $path})}
$attempt1=Get-Tree (Join-Path $ProjectPath 'Research\Verification\Gate10R_ProcessReuse_5pct\v1');$attempt2=Get-Tree (Join-Path $ProjectPath 'Research\Verification\Gate10R_ProcessReuse_5pct\v2');$attempt3=Get-Tree (Join-Path $ProjectPath 'Research\Verification\Gate10R_ProcessReuse_5pct\v3')
if($attempt1.treeSha256 -ne '2baa66eb6ee95ecf0f68667b2790fba2a30ce8a24f54e8f9fe477cdc716b9e3d' -or $attempt2.treeSha256 -ne 'da9e6312e74db1bc1207660cf90eef28321ecda0abf1297be6c9298e6270dbce' -or $attempt3.treeSha256 -ne '29f5aa8f0461abb120792dea0f2806e46e4dc9836aa843ce747f2436c1645a23'){throw 'Historical attempt tree changed before provenance freeze.'}
$unityPath='H:\UnityEditor\2022.3.30f1c1\Editor\Unity.exe'
$provenance=[ordered]@{schemaVersion=4;provenanceId='gate10r-process-reuse-5pct-attempt4-filescope-retained-regression-provenance-v4';createdAtUtc=[DateTime]::UtcNow.ToString('o');status='FROZEN-READY-FOR-OUTSIDE-V4-ROOT-PREFLIGHT';attempt=4;designId='gate10r-one-fresh-unity-process-per-williams-block-5pct-v1';lineageId='gate10r-onward-one-process-per-williams-block-5pct-playable-v1';changeClass='ORCHESTRATION-RETAINED-REGRESSION-FILE-SCOPE-ONLY';formalCampaign=$false;verificationRoot='Research/Verification/Gate10R_ProcessReuse_5pct/v4';outsidePreflightRoot='Research/Verification/Gate10R_Attempt4_Preflight/v1';boundFiles=$bound.ToArray();historicalAttemptBoundaries=[ordered]@{attempt1=$attempt1;attempt2=$attempt2;attempt3=$attempt3;mutationAllowed=$false;resumeAllowed=$false};unity=[ordered]@{path=$unityPath;bytes=[long](Get-Item -LiteralPath $unityPath).Length;sha256=Get-LowerSha $unityPath};precisionPolicy=[ordered]@{targetRelativeCiHalfWidth=0.05;hardCap=$null;usedForGate10RFixtureSizing=$false};failurePolicy=[ordered]@{failClosed=$true;maximumOfficialExecutionsPerReceipt=1;automaticRetrySeriesAuthorized=$true;automaticResumeSeriesAuthorized=$true;retryRequiresNewVersionedRootAndReceipt=$true;stopOnFirstPass=$true};downstreamAuthorization=[ordered]@{gate11R=$false;gate12R=$false;gate13R=$false;successCheckpoint='GATE10R-PASSED-WAITING-FOR-USER-AUTHORIZATION'}}
$json=($provenance|ConvertTo-Json -Depth 60).Replace("`r`n","`n").Replace("`r","`n");if(-not$json.EndsWith("`n",[StringComparison]::Ordinal)){$json+="`n"};$encoding=New-Object Text.UTF8Encoding($false,$true);$stream=New-Object IO.FileStream($outputPath,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None);try{$writer=New-Object IO.StreamWriter($stream,$encoding);try{$writer.Write($json);$writer.Flush()}finally{$writer.Dispose()}}finally{$stream.Dispose()}
$provenance|ConvertTo-Json -Depth 4
