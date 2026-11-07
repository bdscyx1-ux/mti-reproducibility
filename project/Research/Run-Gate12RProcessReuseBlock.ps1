[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$BlockPlanPath,
    [Parameter(Mandatory=$true)][string]$OutputDirectory,
    [Parameter(Mandatory=$true)][string]$AllowedRoot,
    [Parameter(Mandatory=$true)][ValidateSet('Verification','Pilot')][string]$Mode,
    [string]$UnityPath='H:\UnityEditor\2022.3.30f1c1\Editor\Unity.exe',
    [Parameter(Mandatory=$true)][string]$ProjectPath,
    [switch]$BindingSmokeOnly,
    [switch]$ExpectFailure,
    [int]$ExpectedCompletedSamplesBeforeFailure=1,
    [int]$TimeoutSeconds=3600
)

$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
if([string]::IsNullOrWhiteSpace($ProjectPath)-or-not[IO.Path]::IsPathRooted($ProjectPath)){throw 'Gate12R requires an explicit absolute ProjectPath.'}
$ProjectPath=[IO.Path]::GetFullPath($ProjectPath)
if($BindingSmokeOnly){Write-Output("BINDING-SMOKE-PASSED|Run-Gate12RProcessReuseBlock|$ProjectPath|$Mode");exit 0}
$BlockPlanPath=if([IO.Path]::IsPathRooted($BlockPlanPath)){[IO.Path]::GetFullPath($BlockPlanPath)}else{[IO.Path]::GetFullPath((Join-Path $ProjectPath $BlockPlanPath))}
$OutputDirectory=if([IO.Path]::IsPathRooted($OutputDirectory)){[IO.Path]::GetFullPath($OutputDirectory)}else{[IO.Path]::GetFullPath((Join-Path $ProjectPath $OutputDirectory))}
$AllowedRoot=if([IO.Path]::IsPathRooted($AllowedRoot)){[IO.Path]::GetFullPath($AllowedRoot)}else{[IO.Path]::GetFullPath((Join-Path $ProjectPath $AllowedRoot))}
$UnityPath=[IO.Path]::GetFullPath($UnityPath)
Import-Module (Join-Path $PSScriptRoot 'Gate10RProcessReusePreparation.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'Gate10RLockHygieneV3.psm1') -Force

$expectedBase=if($Mode-eq'Pilot'){[IO.Path]::GetFullPath((Join-Path $ProjectPath 'Research\PilotRuns\Gate12R_ProcessReuse_5pct'))}else{[IO.Path]::GetFullPath((Join-Path $ProjectPath 'Research\Verification\Gate12R_ProcessReuse_5pct'))}
if(-not$AllowedRoot.StartsWith($expectedBase.TrimEnd('\')+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'AllowedRoot is outside the Gate12R versioned base.'}
if(-not$OutputDirectory.StartsWith($AllowedRoot.TrimEnd('\')+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'Block output is outside AllowedRoot.'}
if(-not$BlockPlanPath.StartsWith($AllowedRoot.TrimEnd('\')+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'Block plan is outside AllowedRoot.'}
if(-not(Test-Path -LiteralPath $BlockPlanPath -PathType Leaf)){throw "Block plan missing: $BlockPlanPath"}
if(-not(Test-Path -LiteralPath $UnityPath -PathType Leaf)){throw "Unity missing: $UnityPath"}
$formalRoot=[IO.Path]::GetFullPath((Join-Path $ProjectPath 'Research\FormalRuns\Gate13R_ProcessReuse_5pct\v1'))
if(Test-Path -LiteralPath $formalRoot){throw 'Reserved Gate13R formal root must remain absent.'}
if(Test-Path -LiteralPath $OutputDirectory){if(-not(Test-Path -LiteralPath $OutputDirectory -PathType Container)-or@(Get-ChildItem -LiteralPath $OutputDirectory -Force).Count-gt0){throw "Output is not fresh: $OutputDirectory"}}
$unityLog=$OutputDirectory+'.Unity.log';$summaryPath=$OutputDirectory+'.summary.json'
foreach($p in @($unityLog,$summaryPath)){if(Test-Path -LiteralPath $p){throw "Create-new sidecar exists: $p"}}
if(@(Get-Process -Name Unity -ErrorAction SilentlyContinue).Count-gt0-or(Test-Path -LiteralPath (Join-Path $ProjectPath 'Temp\UnityLockfile'))){throw 'Unity must be closed and the project lock absent before a Gate12R block.'}
$plan=Read-Gate10RJson $BlockPlanPath
if([int]$plan.schemaVersion-ne2-or[string]$plan.designId-ne'gate10r-one-fresh-unity-process-per-williams-block-5pct-v1'-or$plan.formalCampaign-ne$false){throw 'Unauthorized block plan identity/boundary.'}
$allowedRoles=if($Mode-eq'Pilot'){@('excluded-warmup','measured-non-formal-pilot')}else{@('excluded-verification','excluded-negative-fail-closed-verification')}
if([string]$plan.analysisRole-notin$allowedRoles){throw "Analysis role is not allowed in $Mode mode."}
if($ExpectFailure-and[string]$plan.analysisRole-ne'excluded-negative-fail-closed-verification'){throw 'ExpectFailure requires the negative role.'}
if(-not$ExpectFailure-and[string]$plan.analysisRole-eq'excluded-negative-fail-closed-verification'){throw 'Negative role requires ExpectFailure.'}
$planSha=Get-Gate10RLowerSha256 $BlockPlanPath;$started=Get-Date
$args=@('-batchmode','-nographics','-quit','-projectPath',('"'+$ProjectPath+'"'),'-executeMethod','DDM.Research.Editor.Gate10RProcessReuseBatchCommand.Run','-ddmGate10RBlockPlanPath',('"'+$BlockPlanPath+'"'),'-ddmGate10RBlockPlanSha256',$planSha,'-ddmGate10ROutputDirectory',('"'+$OutputDirectory+'"'),'-logFile',('"'+$unityLog+'"'))
$process=Start-Process -FilePath $UnityPath -ArgumentList $args -WorkingDirectory (Split-Path -Parent $UnityPath) -WindowStyle Hidden -PassThru
$timedOut=$false;$deadline=(Get-Date).AddSeconds($TimeoutSeconds)
while(-not$process.HasExited){if((Get-Date)-ge$deadline){$timedOut=$true;break};Start-Sleep -Milliseconds 500;$process.Refresh()}
if($timedOut){& taskkill.exe /PID $process.Id /T /F 2>&1|Out-Null;try{Wait-Process -Id $process.Id -Timeout 30 -ErrorAction SilentlyContinue}catch{}}
$process.Refresh();$exitCode=if($timedOut){124}else{[int]$process.ExitCode};$completed=Get-Date
$lock=Invoke-Gate10RPostExitQuiescenceV3 -ProjectPath $ProjectPath -OwnedProcessId $process.Id -OwnedProcessStartedAt ([DateTimeOffset]$started) -OwnedProcessCompletedAt ([DateTimeOffset]$completed) -Role $(if($ExpectFailure){'expected-negative'}else{'positive'}) -EvidenceDirectory ($OutputDirectory+'.lock-hygiene') -ContextId ([string]$plan.blockId) -QuiescenceSeconds 60 -PollMilliseconds 250 -TimestampToleranceSeconds 2
$compiler=@();if(Test-Path -LiteralPath $unityLog){$compiler=@(Select-String -LiteralPath $unityLog -Pattern 'error CS\d+|Compilation failed|Scripts have compiler errors|executeMethod.+could not be found' -CaseSensitive:$false)}
$manifestPath=Join-Path $OutputDirectory 'block-manifest.json';$checkpointPath=Join-Path $OutputDirectory 'block-checkpoint.json';$failurePath=Join-Path $OutputDirectory 'block-failure.json'
$manifest=if(Test-Path -LiteralPath $manifestPath){Read-Gate10RJson $manifestPath}else{$null};$checkpoint=if(Test-Path -LiteralPath $checkpointPath){Read-Gate10RJson $checkpointPath}else{$null}
$errors=New-Object Collections.Generic.List[string];if($timedOut){$errors.Add("Hard timeout after $TimeoutSeconds seconds.")};if($compiler.Count){$errors.Add("Compiler/error patterns: $($compiler.Count).")}
if($ExpectFailure){
 if($exitCode-eq0){$errors.Add('Negative fixture exited zero.')};if($null-ne$manifest){$errors.Add('Negative fixture wrote a completed manifest.')};if(-not(Test-Path -LiteralPath $failurePath)){ $errors.Add('block-failure.json missing.') }
 if($null-eq$checkpoint-or[string]$checkpoint.status-ne'failed-no-auto-retry'){ $errors.Add('Negative terminal checkpoint missing/wrong.') }elseif([int]$checkpoint.completedSampleCount-ne$ExpectedCompletedSamplesBeforeFailure){$errors.Add('Negative completed-sample count mismatch.')}
 for($i=$ExpectedCompletedSamplesBeforeFailure+1;$i-lt@($plan.entries).Count;$i++){if(Test-Path -LiteralPath (Join-Path $OutputDirectory ([string]$plan.entries[$i].directory).Replace('/','\'))){$errors.Add("Later position executed: $i")}}
}else{
 if($exitCode-ne0){$errors.Add("Unity exit code $exitCode.")};if($null-eq$manifest){$errors.Add('Block manifest missing.')}else{
  if($manifest.completed-ne$true-or$manifest.formalCampaign-ne$false-or$manifest.hardMemoryRulesPassed-ne$true){$errors.Add('Block is incomplete/formal/memory-invalid.')}
  if([string]$manifest.executionDesignId-ne'gate10r-one-fresh-unity-process-per-williams-block-5pct-v1'-or[string]$manifest.blockId-ne[string]$plan.blockId-or[string]$manifest.blockPlanSha256-ne$planSha){$errors.Add('Block identity/hash mismatch.')}
  if([int]$manifest.completedSampleCount-ne@($plan.entries).Count-or@($manifest.samples).Count-ne@($plan.entries).Count){$errors.Add('Sample cardinality mismatch.')}
  if($manifest.oneBlockPerUnityProcess-ne$true-or$manifest.oneSamplePerAlgorithmPerProcess-ne$true-or$manifest.allSamplesShareProcessId-ne$true-or$manifest.orderMatchesBlockPlan-ne$true){$errors.Add('Process/Williams assertions failed.')}
  if([long]$manifest.blockRetainedManagedGrowthBytes-gt134217728-or[long]$manifest.blockWorkingSetGrowthBytes-gt536870912-or[long]$manifest.blockPrivateMemoryGrowthBytes-gt536870912){$errors.Add('Frozen memory rule exceeded.')}
  for($i=0;$i-lt@($manifest.samples).Count;$i++){$a=$manifest.samples[$i];$e=$plan.entries[$i];if([int]$a.position-ne[int]$e.position-or[string]$a.algorithmId-ne[string]$e.algorithmId-or[string]$a.runId-ne[string]$e.runId-or[int]$a.processId-ne[int]$manifest.processId-or$a.completed-ne$true){$errors.Add("Sample identity mismatch at $i")};foreach($v in @($a.workingSetBeforeBytes,$a.workingSetRawAfterBytes,$a.workingSetAfterCleanupBytes,$a.privateMemoryBeforeBytes,$a.privateMemoryRawAfterBytes,$a.privateMemoryAfterCleanupBytes,$a.managedMemoryBeforeBytes,$a.managedMemoryRawAfterBytes,$a.managedMemoryAfterCleanupBytes)){if([long]$v-le0){$errors.Add("Non-positive telemetry at $i");break}};$child=Join-Path $OutputDirectory ([string]$a.manifestRelativePath).Replace('/','\');$sum=Join-Path $OutputDirectory ([string]$a.summaryRelativePath).Replace('/','\');$res=Join-Path $OutputDirectory ([string]$a.workloadResultRelativePath).Replace('/','\');if(-not(Test-Path -LiteralPath $child)-or(Get-Gate10RLowerSha256 $child)-ne[string]$a.manifestSha256){$errors.Add("Child manifest hash mismatch at $i")};if(-not(Test-Path -LiteralPath $sum)-or(Get-Gate10RLowerSha256 $sum)-ne[string]$a.summarySha256){$errors.Add("Child summary hash mismatch at $i")};if(-not(Test-Path -LiteralPath $res)-or(Get-Gate10RLowerSha256 $res)-ne[string]$a.workloadResultSha256){$errors.Add("Result hash mismatch at $i")};if(Test-Path -LiteralPath $child){$cm=Read-Gate10RJson $child;if($cm.completed-ne$true-or$cm.forcedGcBeforeCompleted-ne$true-or$cm.forcedGcAfterCompleted-ne$true-or$cm.sampleStateCreatedFresh-ne$true-or$cm.heavySampleReferencesReturned-ne$false-or$cm.plannerResetCompleted-ne$true-or$cm.loggerDisposed-ne$true){$errors.Add("Reset contract failed at $i")}}}
 }
 if($null-eq$checkpoint-or[string]$checkpoint.status-ne'block-completed'){$errors.Add('Completed checkpoint missing/wrong.')}
}
if($null-eq$lock-or$lock.passed-ne$true){$errors.Add('Post-exit lock hygiene failed.')}
$summary=[ordered]@{schemaVersion=1;summaryKind='gate12r-process-reuse-block-wrapper-summary-v1';savedAtUtc=[DateTime]::UtcNow.ToString('o');mode=$Mode;blockId=[string]$plan.blockId;blockPlanPath=$BlockPlanPath;blockPlanSha256=$planSha;outputDirectory=$OutputDirectory;unityLogPath=$unityLog;unityProcessId=[int]$process.Id;exitCode=$exitCode;timedOut=$timedOut;timeoutSeconds=$TimeoutSeconds;startedAt=$started.ToString('o');completedAt=$completed.ToString('o');wallSeconds=($completed-$started).TotalSeconds;expectedFailure=[bool]$ExpectFailure;analysisRole=[string]$plan.analysisRole;sampleCount=if($null-ne$manifest){[int]$manifest.completedSampleCount}elseif($null-ne$checkpoint){[int]$checkpoint.completedSampleCount}else{0};lockHygieneMode=[string]$lock.mode;blockManifestSha256=if(Test-Path $manifestPath){Get-Gate10RLowerSha256 $manifestPath}else{$null};blockFailureSha256=if(Test-Path $failurePath){Get-Gate10RLowerSha256 $failurePath}else{$null};formalCampaign=$false;automaticRetryAttempted=$false;automaticResumeAttempted=$false;errors=$errors.ToArray();passed=$errors.Count-eq0}
Write-Gate10RAtomicUtf8NoBomJson -Path $summaryPath -Value $summary -Depth 30
if($errors.Count){Write-Error("Gate12R block failed: "+($errors-join'; '));exit 1};Write-Host("Gate12R block passed: $($plan.blockId)") -ForegroundColor Green;exit 0
