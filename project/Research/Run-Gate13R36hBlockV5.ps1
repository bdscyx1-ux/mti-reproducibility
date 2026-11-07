[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$BlockPlanPath,
    [Parameter(Mandatory=$true)][string]$OutputDirectory,
    [Parameter(Mandatory=$true)][string]$AllowedRoot,
    [Parameter(Mandatory=$true)][ValidateSet('Verification','Pilot')][string]$Mode,
    [Parameter(Mandatory=$true)][string]$SourceProjectPath,
    [Parameter(Mandatory=$true)][string]$LaneProjectPath,
    [Parameter(Mandatory=$true)][ValidateRange(1,4)][int]$LaneNumber,
    [Parameter(Mandatory=$true)][ValidatePattern('^0x[0-9A-Fa-f]{8,16}$')][string]$AffinityMaskHex,
    [string]$UnityPath='H:\UnityEditor\2022.3.30f1c1\Editor\Unity.exe',
    [switch]$BindingSmokeOnly,
    [switch]$ExpectFailure,
    [int]$ExpectedCompletedSamplesBeforeFailure=1,
    [int]$TimeoutSeconds=3600
)

$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
$utf8=New-Object Text.UTF8Encoding($false,$true)
function Get-LowerHash([string]$Path){return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()}
function Read-Json([string]$Path){return Get-Content -LiteralPath $Path -Raw -Encoding UTF8|ConvertFrom-Json}
function Write-AtomicJson([string]$Path,$Value,[int]$Depth=50){$parent=Split-Path -Parent $Path;if(-not(Test-Path -LiteralPath $parent -PathType Container)){New-Item -ItemType Directory -Path $parent|Out-Null};$json=($Value|ConvertTo-Json -Depth $Depth).Replace("`r`n","`n").Replace("`r","`n")+"`n";$tmp=$Path+'.tmp-'+[Guid]::NewGuid().ToString('N');[IO.File]::WriteAllText($tmp,$json,$utf8);if(Test-Path -LiteralPath $Path){$bak=$Path+'.replace-backup-'+[Guid]::NewGuid().ToString('N');[IO.File]::Replace($tmp,$Path,$bak);if(Test-Path -LiteralPath $bak){[IO.File]::Delete($bak)}}else{[IO.File]::Move($tmp,$Path)}}
function Is-Within([string]$Candidate,[string]$Root){$r=[IO.Path]::GetFullPath($Root).TrimEnd('\')+'\';return [IO.Path]::GetFullPath($Candidate).StartsWith($r,[StringComparison]::OrdinalIgnoreCase)}
function Get-LaneUnityProcesses([string]$ProjectPath){return @(Get-CimInstance Win32_Process -Filter "Name='Unity.exe'" -ErrorAction SilentlyContinue|Where-Object{[string]$_.CommandLine -like ('*'+$ProjectPath+'*')})}

$SourceProjectPath=[IO.Path]::GetFullPath($SourceProjectPath);$LaneProjectPath=[IO.Path]::GetFullPath($LaneProjectPath);$UnityPath=[IO.Path]::GetFullPath($UnityPath)
$lockHygieneModulePath=Join-Path $SourceProjectPath 'Research\Gate10RLockHygieneV3.psm1'
if((Get-LowerHash $lockHygieneModulePath)-ne'9eba2284dc90fcf6dbbc59080301c1ac6db14c5029f8adab69db234c94f879d6'){throw 'Frozen lock-hygiene module hash mismatch.'}
Import-Module $lockHygieneModulePath -Force
$BlockPlanPath=[IO.Path]::GetFullPath($BlockPlanPath);$OutputDirectory=[IO.Path]::GetFullPath($OutputDirectory);$AllowedRoot=[IO.Path]::GetFullPath($AllowedRoot)
$expectedLane=[IO.Path]::GetFullPath(('H:\DDM_Final_Project_Gate13R36H\v5\lane-{0:D2}'-f$LaneNumber))
if($LaneProjectPath-ne$expectedLane){throw "Lane project path mismatch: expected $expectedLane"}
$expectedAllowed=if($Mode-eq'Pilot'){[IO.Path]::GetFullPath((Join-Path $SourceProjectPath 'Research\PilotRuns\Gate13R_36h_10pct_4Lane\v5'))}else{[IO.Path]::GetFullPath((Join-Path $SourceProjectPath 'Research\Verification\Gate13R_36h_10pct_4Lane\v5'))}
if($AllowedRoot-ne$expectedAllowed){throw "Allowed root mismatch for mode $Mode."}
if(-not(Is-Within $OutputDirectory $AllowedRoot)-or-not(Is-Within $BlockPlanPath $AllowedRoot)){throw 'Block plan/output must be below the authorized version root.'}
if($BindingSmokeOnly){Write-Output("BINDING-SMOKE-PASSED|Run-Gate13R36hBlockV5|$LaneNumber|$Mode|$LaneProjectPath");exit 0}
if(-not(Test-Path -LiteralPath $LaneProjectPath -PathType Container)-or-not(Test-Path -LiteralPath (Join-Path $LaneProjectPath 'Assets') -PathType Container)){throw 'Lane project copy is missing.'}
if(-not(Test-Path -LiteralPath $UnityPath -PathType Leaf)){throw 'Unity executable is missing.'}
if(-not(Test-Path -LiteralPath $BlockPlanPath -PathType Leaf)){throw "Block plan missing: $BlockPlanPath"}
foreach($formal in @('Research\FormalRuns\Gate13R_ProcessReuse_5pct\v1','Research\FormalRuns\Gate13R_36h_10pct_4Lane\v1')){if(Test-Path -LiteralPath (Join-Path $SourceProjectPath $formal)){throw "Forbidden formal root exists: $formal"}}
if(Test-Path -LiteralPath (Join-Path $LaneProjectPath 'Temp\UnityLockfile')){throw 'Lane Unity lock exists before block start.'}
if(@(Get-LaneUnityProcesses $LaneProjectPath).Count-ne0){throw 'A Unity process already owns the lane project.'}
if(Test-Path -LiteralPath $OutputDirectory){if(-not(Test-Path -LiteralPath $OutputDirectory -PathType Container)-or@(Get-ChildItem -LiteralPath $OutputDirectory -Force).Count-gt0){throw "Output is not fresh: $OutputDirectory"}}
$unityLog=$OutputDirectory+'.Unity.log';$summaryPath=$OutputDirectory+'.wrapper-summary.json';$failureSidecar=$OutputDirectory+'.wrapper-failure.json'
foreach($path in @($unityLog,$summaryPath,$failureSidecar)){if(Test-Path -LiteralPath $path){throw "Create-new sidecar exists: $path"}}
$plan=Read-Json $BlockPlanPath
if([int]$plan.schemaVersion-ne2-or[string]$plan.designId-ne'gate13r-36h-10pct-four-isolated-editor-lanes-v1'-or$plan.formalCampaign-ne$false){throw 'Unauthorized block-plan identity/boundary.'}
$allowedRoles=if($Mode-eq'Pilot'){@('excluded-warmup','measured-non-formal-pilot')}else{@('excluded-verification','excluded-negative-fail-closed-verification')}
if([string]$plan.analysisRole-notin$allowedRoles){throw "Analysis role is not allowed in $Mode mode."}
if($ExpectFailure-and[string]$plan.analysisRole-ne'excluded-negative-fail-closed-verification'){throw 'ExpectFailure requires the negative verification role.'}
if(-not$ExpectFailure-and[string]$plan.analysisRole-eq'excluded-negative-fail-closed-verification'){throw 'Negative role requires ExpectFailure.'}
$expectedMasks=@('0x000000FF','0x0000FF00','0x00FF0000','0xFF000000')
if($AffinityMaskHex.ToUpperInvariant()-ne$expectedMasks[$LaneNumber-1].ToUpperInvariant()){throw 'Affinity mask differs from the frozen lane policy.'}
$maskValue=[Convert]::ToUInt64($AffinityMaskHex.Substring(2),16);$planSha=Get-LowerHash $BlockPlanPath;$started=[DateTimeOffset]::Now;$process=$null;$timedOut=$false;$exitCode=-1;$actualMask=$null;$errors=New-Object Collections.Generic.List[string]
try{
    $args=@('-batchmode','-nographics','-quit','-projectPath',('"'+$LaneProjectPath+'"'),'-executeMethod','DDM.Research.Editor.Gate13R36hConcurrencyBatchCommandV1.Run','-ddmGate10RBlockPlanPath',('"'+$BlockPlanPath+'"'),'-ddmGate10RBlockPlanSha256',$planSha,'-ddmGate10ROutputDirectory',('"'+$OutputDirectory+'"'),'-logFile',('"'+$unityLog+'"'))
    $process=Start-Process -FilePath $UnityPath -ArgumentList $args -WorkingDirectory (Split-Path -Parent $UnityPath) -WindowStyle Hidden -PassThru
    $process.ProcessorAffinity=[IntPtr]([Int64]$maskValue);$process.PriorityClass=[Diagnostics.ProcessPriorityClass]::Normal;$process.Refresh();$actualMask=('0x{0:X8}'-f[uint64]$process.ProcessorAffinity.ToInt64())
    $deadline=(Get-Date).AddSeconds($TimeoutSeconds)
    while(-not$process.HasExited){if((Get-Date)-ge$deadline){$timedOut=$true;break};Start-Sleep -Milliseconds 500;$process.Refresh()}
    if($timedOut){& taskkill.exe /PID $process.Id /T /F 2>&1|Out-Null;try{Wait-Process -Id $process.Id -Timeout 30 -ErrorAction SilentlyContinue}catch{}}
    $process.Refresh();$exitCode=if($timedOut){124}else{[int]$process.ExitCode}
}catch{$errors.Add($_.Exception.ToString());if($null-ne$process-and-not$process.HasExited){& taskkill.exe /PID $process.Id /T /F 2>&1|Out-Null}}
$completed=[DateTimeOffset]::Now
$lockPath=Join-Path $LaneProjectPath 'Temp\UnityLockfile';$lockHygieneResult=$null
if($ExpectFailure){
    $lockEvidenceDirectory=$OutputDirectory+'.lock-hygiene';if(-not(Test-Path -LiteralPath $lockEvidenceDirectory)){New-Item -ItemType Directory -Path $lockEvidenceDirectory|Out-Null}
    try{$lockHygieneResult=Invoke-Gate10RPostExitQuiescenceV3 -ProjectPath $LaneProjectPath -OwnedProcessId $process.Id -OwnedProcessStartedAt $started -OwnedProcessCompletedAt $completed -Role expected-negative -EvidenceDirectory $lockEvidenceDirectory -ContextId ('g13r36-v5-negative-lane-{0:D2}'-f$LaneNumber) -QuiescenceSeconds 60 -PollMilliseconds 250 -TimestampToleranceSeconds 2}catch{$errors.Add('Expected-negative controlled lock hygiene failed: '+$_.Exception.Message)}
    $laneProcesses=@(Get-LaneUnityProcesses $LaneProjectPath);$lockExists=Test-Path -LiteralPath $lockPath
}else{
    $quiescenceDeadline=(Get-Date).AddSeconds(60)
    do{$laneProcesses=@(Get-LaneUnityProcesses $LaneProjectPath);$lockExists=Test-Path -LiteralPath $lockPath;if($laneProcesses.Count-eq0-and-not$lockExists){break};Start-Sleep -Milliseconds 250}while((Get-Date)-lt$quiescenceDeadline)
    $laneProcesses=@(Get-LaneUnityProcesses $LaneProjectPath);$lockExists=Test-Path -LiteralPath $lockPath
}
if($timedOut){$errors.Add("Hard timeout after $TimeoutSeconds seconds.")};if($laneProcesses.Count-ne0){$errors.Add('Lane-owned Unity process remains after exit.')};if($lockExists){$errors.Add('Lane Unity lock remains after quiescence.')}
$compiler=@();if(Test-Path -LiteralPath $unityLog){$compiler=@(Select-String -LiteralPath $unityLog -Pattern 'error CS\d+|Compilation failed|Scripts have compiler errors|executeMethod.+could not be found' -CaseSensitive:$false)};if($compiler.Count){$errors.Add("Compiler/execute-method patterns: $($compiler.Count).")}
$manifestPath=Join-Path $OutputDirectory 'block-manifest.json';$checkpointPath=Join-Path $OutputDirectory 'block-checkpoint.json';$blockFailurePath=Join-Path $OutputDirectory 'block-failure.json'
$manifest=if(Test-Path -LiteralPath $manifestPath){Read-Json $manifestPath}else{$null};$checkpoint=if(Test-Path -LiteralPath $checkpointPath){Read-Json $checkpointPath}else{$null}
if($ExpectFailure){
    if($exitCode-eq0){$errors.Add('Negative fixture exited zero.')};if($null-ne$manifest){$errors.Add('Negative fixture wrote a completed block manifest.')};if(-not(Test-Path -LiteralPath $blockFailurePath)){$errors.Add('Negative block-failure.json missing.')}
    if($null-eq$checkpoint-or[string]$checkpoint.status-ne'failed-no-auto-retry'){$errors.Add('Negative terminal checkpoint missing/wrong.')}elseif([int]$checkpoint.completedSampleCount-ne$ExpectedCompletedSamplesBeforeFailure){$errors.Add('Negative completed-sample count mismatch.')}
    for($i=$ExpectedCompletedSamplesBeforeFailure;$i-lt@($plan.entries).Count;$i++){
        $laterDirectory=Join-Path $OutputDirectory ([string]$plan.entries[$i].directory).Replace('/','\')
        if(Test-Path -LiteralPath $laterDirectory){$errors.Add("Later position executed: $($i+1), $laterDirectory")}
    }
}else{
    if($exitCode-ne0){$errors.Add("Unity exit code $exitCode.")};if($null-eq$manifest){$errors.Add('Block manifest missing.')}else{
        $expectedCount=@($plan.entries).Count;$expectedManaged=[long]134217728*$expectedCount
        if([int]$manifest.schemaVersion-ne3-or[string]$manifest.manifestKind-ne'gate13r-36h-10pct-four-lane-nonformal-block-manifest-v1'){$errors.Add('Block manifest schema/kind mismatch.')}
        if($manifest.completed-ne$true-or$manifest.formalCampaign-ne$false-or$manifest.hardMemoryRulesPassed-ne$true){$errors.Add('Block incomplete/formal/memory-invalid.')}
        if([string]$manifest.executionDesignId-ne'gate13r-36h-10pct-four-isolated-editor-lanes-v1'-or[string]$manifest.blockId-ne[string]$plan.blockId-or[string]$manifest.blockPlanSha256-ne$planSha){$errors.Add('Block identity/hash mismatch.')}
        if([int]$manifest.completedSampleCount-ne$expectedCount-or@($manifest.samples).Count-ne$expectedCount){$errors.Add('Sample cardinality mismatch.')}
        if($manifest.oneBlockPerUnityProcess-ne$true-or$manifest.oneSamplePerAlgorithmPerProcess-ne$true-or$manifest.allSamplesShareProcessId-ne$true-or$manifest.orderMatchesBlockPlan-ne$true){$errors.Add('Process/Williams assertions failed.')}
        if([string]$manifest.memoryGatePolicyId-ne'gate12r-sample-128mib-block-128mib-per-sample-v1'-or[long]$manifest.maximumSampleRetainedManagedGrowthBytes-ne134217728-or[long]$manifest.maximumManagedGrowthBytes-ne$expectedManaged){$errors.Add('Memory policy mismatch.')}
        if([long]$manifest.blockRetainedManagedGrowthBytes-gt$expectedManaged-or[long]$manifest.blockWorkingSetGrowthBytes-gt536870912-or[long]$manifest.blockPrivateMemoryGrowthBytes-gt536870912){$errors.Add('Frozen memory rule exceeded.')}
        for($i=0;$i-lt@($manifest.samples).Count;$i++){
            $sample=$manifest.samples[$i];$entry=$plan.entries[$i]
            if([int]$sample.position-ne[int]$entry.position-or[string]$sample.algorithmId-ne[string]$entry.algorithmId-or[string]$sample.runId-ne[string]$entry.runId-or$sample.completed-ne$true-or[int]$sample.processId-ne[int]$manifest.processId){$errors.Add("Sample identity mismatch at index $i.")}
            foreach($value in @($sample.workingSetBeforeBytes,$sample.workingSetRawAfterBytes,$sample.workingSetAfterCleanupBytes,$sample.privateMemoryBeforeBytes,$sample.privateMemoryRawAfterBytes,$sample.privateMemoryAfterCleanupBytes,$sample.managedMemoryBeforeBytes,$sample.managedMemoryRawAfterBytes,$sample.managedMemoryAfterCleanupBytes)){if([long]$value-le0){$errors.Add("Non-positive telemetry at index $i.");break}}
            foreach($pair in @(@([string]$sample.manifestRelativePath,[string]$sample.manifestSha256),@([string]$sample.summaryRelativePath,[string]$sample.summarySha256),@([string]$sample.workloadResultRelativePath,[string]$sample.workloadResultSha256))){$child=Join-Path $OutputDirectory $pair[0].Replace('/','\');if(-not(Test-Path -LiteralPath $child)-or(Get-LowerHash $child)-ne$pair[1]){$errors.Add("Child hash mismatch at index $i for $($pair[0]).")}}
            if([long]$sample.sampleRetainedManagedGrowthBytes-gt134217728){$errors.Add("Sample retained managed-memory limit exceeded at index $i.")}
        }
    }
    if($null-eq$checkpoint-or[string]$checkpoint.status-ne'block-completed'-or[int]$checkpoint.completedSampleCount-ne@($plan.entries).Count){$errors.Add('Terminal block checkpoint missing/wrong.')}
    if(Test-Path -LiteralPath $blockFailurePath){$errors.Add('Unexpected block failure record exists.')}
}
$passed=$errors.Count-eq0;$summary=[ordered]@{schemaVersion=1;summaryKind='gate13r-36h-four-lane-block-wrapper-summary-v5';completedAtUtc=[DateTime]::UtcNow.ToString('o');mode=$Mode;lane=$LaneNumber;laneProjectPath=$LaneProjectPath;affinityMaskRequested=$AffinityMaskHex;affinityMaskObserved=$actualMask;blockPlanPath=$BlockPlanPath;blockPlanSha256=$planSha;blockId=[string]$plan.blockId;campaignId=[string]$plan.campaignId;block=[int]$plan.block;analysisRole=[string]$plan.analysisRole;processId=if($null-ne$process){$process.Id}else{$null};startedAt=$started.ToString('o');completedAt=$completed.ToString('o');wrapperWallSeconds=($completed-$started).TotalSeconds;unityExitCode=$exitCode;timedOut=$timedOut;laneLockAbsent=-not$lockExists;laneProcessCountAfter=$laneProcesses.Count;formalCampaign=$false;automaticRetryAttempted=$false;automaticResumeAttempted=$false;lockHygieneResult=$lockHygieneResult;errors=$errors.ToArray();passed=$passed}
Write-AtomicJson $summaryPath $summary
if(-not$passed){Write-AtomicJson $failureSidecar ([ordered]@{schemaVersion=1;failureKind='gate13r-36h-four-lane-block-wrapper-failure-v5';failedAtUtc=[DateTime]::UtcNow.ToString('o');lane=$LaneNumber;blockId=[string]$plan.blockId;errors=$errors.ToArray();automaticRetryAttempted=$false;automaticResumeAttempted=$false;formalCampaign=$false});Write-Error("Gate13R 36h block wrapper failed: "+($errors-join'; '));exit 1}
Write-Host("Gate13R 36h block passed: lane {0}, {1}, {2:n2}s"-f$LaneNumber,$plan.blockId,($completed-$started).TotalSeconds)-ForegroundColor Green
exit 0
