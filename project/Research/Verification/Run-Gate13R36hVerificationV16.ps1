[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$ProjectPath,
    [string]$UnityPath='H:\UnityEditor\2022.3.30f1c1\Editor\Unity.exe',
    [switch]$BindingSmokeOnly,
    [int]$ChildTimeoutSeconds=3600
)

$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$ProjectPath=[IO.Path]::GetFullPath($ProjectPath)
$UnityPath=[IO.Path]::GetFullPath($UnityPath)
$verificationRoot=[IO.Path]::GetFullPath((Join-Path $ProjectPath 'Research\Verification\Gate13R_36h_10pct_4Lane\v16'))
if($BindingSmokeOnly){Write-Output("BINDING-SMOKE-PASSED|Run-Gate13R36hVerificationV16|$ProjectPath");exit 0}
if(Test-Path -LiteralPath $verificationRoot){throw 'Create-new Gate13R 36h verification root already exists.'}
if(@(Get-Process -Name Unity -ErrorAction SilentlyContinue).Count){throw 'Unity must be closed before verification starts.'}
foreach($root in @('Research\PilotRuns\Gate13R_36h_10pct_4Lane\v16','Research\FormalRuns\Gate13R_ProcessReuse_5pct\v1','Research\FormalRuns\Gate13R_36h_10pct_4Lane\v1')){if(Test-Path -LiteralPath (Join-Path $ProjectPath $root)){throw "Forbidden execution root exists: $root"}}
if(Test-Path -LiteralPath 'H:\DDM_Final_Project_Gate13R36H\v16'){throw 'Create-new lane clone root already exists.'}

Import-Module (Join-Path $ProjectPath 'Research\Gate13R36hConcurrencyPreparationV16.psm1') -Force
Import-Module (Join-Path $ProjectPath 'Research\Gate10RProcessReusePreparation.psm1') -Force
$planPath=Join-Path $ProjectPath 'Research\Gate13R_36h_10pct_4Lane_Pilot_Plan.v16.json'
$schedulePath=Join-Path $ProjectPath 'Research\Gate13R_36h_10pct_4Lane_Pilot_Schedule.v16.json'
$provenancePath=Join-Path $ProjectPath 'Research\Gate13R_36h_10pct_4Lane_Provenance.v16.json'
$plan=Read-G13R36Json $planPath;$provenance=Read-G13R36Json $provenancePath;$schedule=Read-G13R36Json $schedulePath
$windowsPowerShell='C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe'
$nativePowerShellModulePath=@('C:\Users\bdscy\Documents\WindowsPowerShell\Modules','C:\Program Files\WindowsPowerShell\Modules','C:\WINDOWS\System32\WindowsPowerShell\v1.0\Modules')-join';'
$utf8=New-Object Text.UTF8Encoding($false,$true)
New-Item -ItemType Directory -Path $verificationRoot -Force|Out-Null
$orchestration=Join-Path $verificationRoot 'Orchestration';New-Item -ItemType Directory -Path $orchestration -Force|Out-Null
$checkpointPath=Join-Path $verificationRoot 'verification-checkpoint.json'
function Write-Checkpoint([string]$Status,[string]$Stage,[string]$ErrorText){Write-G13R36AtomicUtf8NoBomJson -Path $checkpointPath -Value ([ordered]@{schemaVersion=1;checkpointKind='gate13r-36h-four-lane-verification-checkpoint-v16';savedAtUtc=[DateTime]::UtcNow.ToString('o');status=$Status;stage=$Stage;error=$ErrorText;pilotRootCreated=Test-Path (Join-Path $ProjectPath 'Research\PilotRuns\Gate13R_36h_10pct_4Lane\v16');formalCampaign=$false;automaticRetryAuthorized=$false;automaticResumeAuthorized=$false}) -Depth 20}
function Invoke-Child([string]$Name,[string]$ScriptPath,[string[]]$Arguments,[int]$TimeoutSeconds=$ChildTimeoutSeconds){$stdout=Join-Path $orchestration ($Name+'.stdout.log');$stderr=Join-Path $orchestration ($Name+'.stderr.log');$old=$env:PSModulePath;try{$env:PSModulePath=$nativePowerShellModulePath;$process=Start-Process -FilePath $windowsPowerShell -ArgumentList (@('-NoProfile','-ExecutionPolicy','Bypass','-File',$ScriptPath)+$Arguments) -WorkingDirectory $ProjectPath -WindowStyle Hidden -RedirectStandardOutput $stdout -RedirectStandardError $stderr -PassThru;$deadline=(Get-Date).AddSeconds($TimeoutSeconds);while(-not$process.HasExited-and(Get-Date)-lt$deadline){Start-Sleep -Milliseconds 500;$process.Refresh()};if(-not$process.HasExited){&taskkill.exe /PID $process.Id /T /F 2>&1|Out-Null;throw "$Name exceeded hard timeout $TimeoutSeconds seconds."};$process.Refresh();if([int]$process.ExitCode-ne0){throw "$Name failed with exit $($process.ExitCode); stderr=$stderr"};return [pscustomobject]@{name=$Name;processId=$process.Id;exitCode=[int]$process.ExitCode;stdout=$stdout;stderr=$stderr}}finally{$env:PSModulePath=$old}}
function Wait-OwnedChildren([object[]]$Children,[int]$TimeoutSeconds,[string]$Label){$deadline=(Get-Date).AddSeconds($TimeoutSeconds);do{$alive=@($Children|Where-Object{-not$_.process.HasExited});if($alive.Count-eq0){break};if((Get-Date)-ge$deadline){foreach($child in $alive){&taskkill.exe /PID $child.process.Id /T /F 2>&1|Out-Null};throw "$Label exceeded hard timeout $TimeoutSeconds seconds."};Start-Sleep -Seconds 1;foreach($child in $alive){$child.process.Refresh()}}while($true);foreach($child in $Children){$child.process.Refresh();if([int]$child.process.ExitCode-ne0){throw "$Label child failed: $($child.name), exit=$($child.process.ExitCode), stderr=$($child.stderr)"}}}
function Assert-Quiescent(){if(@(Get-Process -Name Unity -ErrorAction SilentlyContinue).Count){throw 'Unexpected Unity process at verification boundary.'};foreach($lane in 1..4){$root='H:\DDM_Final_Project_Gate13R36H\v16\lane-{0:D2}'-f$lane;if(Test-Path -LiteralPath (Join-Path $root 'Temp\UnityLockfile')){throw "Lane lock remains: $root"}}}

$receipt=[ordered]@{schemaVersion=1;receiptKind='gate13r-36h-four-lane-nonexecuting-verification-receipt-v16';createdAtUtc=[DateTime]::UtcNow.ToString('o');status='NON-EXECUTING-READINESS-VERIFICATION';tokens=@('NON-FORMAL','PILOT-NOT-STARTED','FORMAL-CAMPAIGN-NOT-AUTHORIZED','NO-AUTO-RETRY','NO-RESUME');verificationRoot=$verificationRoot;planSha256=Get-G13R36LowerSha256 $planPath;scheduleSha256=Get-G13R36LowerSha256 $schedulePath;provenanceSha256=Get-G13R36LowerSha256 $provenancePath;formalCampaign=$false;formalExecutionAuthorized=$false}
Write-G13R36CreateNewUtf8NoBomJson -Path (Join-Path $verificationRoot 'execution-receipt.json') -Value $receipt -Depth 20
Write-Checkpoint 'started' 'receipt' ''

try{
    Write-Checkpoint 'running' 'static-unit' ''
    [void](Invoke-Child '01-static-unit' (Join-Path $ProjectPath 'Research\Verification\Run-Gate13R36hStaticUnitV16.ps1') @('-ProjectPath',$ProjectPath,'-OutputDirectory',(Join-Path $verificationRoot 'StaticUnit')) 600)
    $static=Read-G13R36Json (Join-Path $verificationRoot 'StaticUnit\summary.json');if($static.passed-ne$true){throw 'Static/unit summary failed.'}
    Write-Checkpoint 'running' 'lock-hygiene-unit' ''
    [void](Invoke-Child '01b-lock-hygiene-unit' (Join-Path $ProjectPath 'Research\Verification\Run-Gate13R36hLockHygieneUnitV16.ps1') @('-ProjectPath',$ProjectPath,'-OutputDirectory',(Join-Path $verificationRoot 'LockHygieneUnit')) 600)
    $lockUnit=Read-G13R36Json (Join-Path $verificationRoot 'LockHygieneUnit\summary.json');if($lockUnit.passed-ne$true-or[int]$lockUnit.failedAssertionCount-ne0){throw 'Expected-negative lock-hygiene unit summary failed.'}

    Write-Checkpoint 'running' 'lane-copy-creation' ''
    [void](Invoke-Child '02-lane-copies' (Join-Path $ProjectPath 'Research\Initialize-Gate13R36hLaneCopiesV16.ps1') @('-ProjectPath',$ProjectPath,'-VerificationOutputRoot',(Join-Path $verificationRoot 'LaneCopies')) 7200)
    $copies=Read-G13R36Json (Join-Path $verificationRoot 'LaneCopies\summary.json');if($copies.passed-ne$true-or[int]$copies.laneCount-ne4){throw 'Four-lane copy creation/audit failed.'}

    Write-Checkpoint 'running' 'serial-lane-bootstrap-compile' ''
    $bootstrapPids=New-Object Collections.Generic.List[int]
    foreach($lane in 1..4){
        $laneRecord=@($plan.lanes|Where-Object lane -eq $lane)[0]
        $laneRoot=[IO.Path]::GetFullPath([string]$laneRecord.projectPath)
        $output=Join-Path $laneRoot 'Research\Verification\Gate13R_36h_10pct_4Lane\v16\BootstrapCompile'
        [void](Invoke-Child ('02b-bootstrap-lane-{0:D2}'-f$lane) (Join-Path $ProjectPath 'Research\Verification\Run-Gate13R36hLaneBootstrapCompileV16.ps1') @('-LaneProjectPath',$laneRoot,'-OutputPrefix',$output,'-LaneNumber',[string]$lane,'-AffinityMaskHex',[string]$laneRecord.affinityMaskHex,'-UnityPath',$UnityPath) 1200)
        $bootstrap=Read-G13R36Json ($output+'.summary.json')
        if($bootstrap.passed-ne$true-or$bootstrap.measured-ne$false-or$bootstrap.planningWorkloadExecuted-ne$false-or$bootstrap.naturalLaneLockRelease-ne$true-or$bootstrap.controlledLockCleanupUsed-ne$false){throw "Lane $lane bootstrap summary failed or violated the frozen non-measured boundary."}
        $bootstrapPids.Add([int]$bootstrap.unityProcessId)
        Assert-Quiescent
    }
    if(@($bootstrapPids|Sort-Object -Unique).Count-ne4){throw 'Lane bootstrap did not use four unique Unity processes.'}

    Write-Checkpoint 'running' 'four-lane-telemetry' ''
    $telemetryChildren=New-Object Collections.Generic.List[object];$old=$env:PSModulePath
    try{$env:PSModulePath=$nativePowerShellModulePath;foreach($lane in 1..4){$laneRecord=@($plan.lanes|Where-Object lane -eq $lane)[0];$laneRoot=[IO.Path]::GetFullPath([string]$laneRecord.projectPath);$output=Join-Path $laneRoot 'Research\Verification\Gate13R_36h_10pct_4Lane\v16\TelemetryProbe';$stdout=Join-Path $orchestration ('03-telemetry-lane-{0:D2}.stdout.log'-f$lane);$stderr=Join-Path $orchestration ('03-telemetry-lane-{0:D2}.stderr.log'-f$lane);$args=@('-NoProfile','-ExecutionPolicy','Bypass','-File',(Join-Path $ProjectPath 'Research\Run-Gate13R36hTelemetryProbeV16.ps1'),'-LaneProjectPath',$laneRoot,'-OutputDirectory',$output,'-LaneNumber',[string]$lane,'-AffinityMaskHex',[string]$laneRecord.affinityMaskHex,'-UnityPath',$UnityPath);$child=Start-Process -FilePath $windowsPowerShell -ArgumentList $args -WorkingDirectory $ProjectPath -WindowStyle Hidden -RedirectStandardOutput $stdout -RedirectStandardError $stderr -PassThru;$telemetryChildren.Add([pscustomobject]@{name=('telemetry-lane-{0:D2}'-f$lane);process=$child;stdout=$stdout;stderr=$stderr})};Wait-OwnedChildren $telemetryChildren.ToArray() 900 'four-lane telemetry'}finally{$env:PSModulePath=$old}
    Assert-Quiescent
    $telemetryPids=@();foreach($lane in 1..4){$root='H:\DDM_Final_Project_Gate13R36H\v16\lane-{0:D2}'-f$lane;$summary=Read-G13R36Json ((Join-Path $root 'Research\Verification\Gate13R_36h_10pct_4Lane\v16\TelemetryProbe')+'.summary.json');if($summary.passed-ne$true){throw "Lane $lane telemetry summary failed."};$telemetryPids+=[int]$summary.unityProcessId};if(@($telemetryPids|Sort-Object -Unique).Count-ne4){throw 'Telemetry probes did not use four unique Unity processes.'};if(@(@($telemetryPids)+@($bootstrapPids)|Sort-Object -Unique).Count-ne8){throw 'Bootstrap and telemetry did not use eight distinct Unity processes.'}

    Write-Checkpoint 'running' 'block-verification' ''
    $blockRoot=Join-Path $verificationRoot 'BlockVerification';New-Item -ItemType Directory -Path (Join-Path $blockRoot 'plans') -Force|Out-Null
    $campaigns=@(Get-G13R36PilotCampaigns -ProjectPath $ProjectPath -Plan $plan);$campaignMap=@{};foreach($campaign in $campaigns){$campaignMap[[string]$campaign.campaignId]=$campaign}
    function New-VerificationPlan($ScheduleRow,[string]$Name,[string]$Role,[int]$FailurePosition){$lane=[int]$ScheduleRow.lane;$laneRecord=@($plan.lanes|Where-Object lane -eq $lane)[0];$laneRoot=[IO.Path]::GetFullPath([string]$laneRecord.projectPath);$campaign=$campaignMap[[string]$ScheduleRow.campaignId];$path=Join-Path $blockRoot ('plans\'+$Name+'.block-plan.json');$object=New-G13R36BlockPlan -LaneProjectPath $laneRoot -Plan $plan -Provenance $provenance -Campaign $campaign -Block ([int]$ScheduleRow.block) -LaneProvenancePath (Join-Path $laneRoot 'Research\Gate13R_36h_10pct_4Lane_Provenance.v16.json') -LaneTelemetryProbeResultPath (Join-Path $laneRoot 'Research\Verification\Gate13R_36h_10pct_4Lane\v16\TelemetryProbe\telemetry-probe-result.json') -AnalysisRole $Role -InjectedFailurePosition $FailurePosition -CampaignIdPrefix 'g13r36verify';Write-G13R36Utf8NoBomJson -Path $path -Value $object -Depth 30;return [pscustomobject]@{path=$path;object=$object;lane=$lane;laneRecord=$laneRecord;originalCampaignId=[string]$campaign.campaignId}}
    function Start-BlockChild($Fixture,[string]$Name,[string]$Output,[bool]$ExpectFailure){$stdout=$Output+'.orchestrator.stdout.log';$stderr=$Output+'.orchestrator.stderr.log';$args=@('-NoProfile','-ExecutionPolicy','Bypass','-File',(Join-Path $ProjectPath 'Research\Run-Gate13R36hBlockV16.ps1'),'-BlockPlanPath',$Fixture.path,'-OutputDirectory',$Output,'-AllowedRoot',$verificationRoot,'-Mode','Verification','-SourceProjectPath',$ProjectPath,'-LaneProjectPath',[string]$Fixture.laneRecord.projectPath,'-LaneNumber',[string]$Fixture.lane,'-AffinityMaskHex',[string]$Fixture.laneRecord.affinityMaskHex,'-UnityPath',$UnityPath,'-TimeoutSeconds',[string]$ChildTimeoutSeconds);if($ExpectFailure){$args+=@('-ExpectFailure','-ExpectedCompletedSamplesBeforeFailure','1')};$child=Start-Process -FilePath $windowsPowerShell -ArgumentList $args -WorkingDirectory $ProjectPath -WindowStyle Hidden -RedirectStandardOutput $stdout -RedirectStandardError $stderr -PassThru;return [pscustomobject]@{name=$Name;process=$child;stdout=$stdout;stderr=$stderr;output=$Output;fixture=$Fixture}}
    $positiveChildren=New-Object Collections.Generic.List[object];$firstWave=@($schedule.rows|Where-Object wave -eq 1|Sort-Object lane);$old=$env:PSModulePath
    try{$env:PSModulePath=$nativePowerShellModulePath;foreach($row in $firstWave){$name='positive-concurrent-lane-{0:D2}'-f[int]$row.lane;$fixture=New-VerificationPlan $row $name 'excluded-verification' 0;$output=Join-Path $blockRoot ('positive-concurrent\'+$name);$positiveChildren.Add((Start-BlockChild $fixture $name $output $false))};Wait-OwnedChildren $positiveChildren.ToArray() $ChildTimeoutSeconds 'positive concurrent block wave'}finally{$env:PSModulePath=$old}
    Assert-Quiescent

    $negativeRow=[pscustomobject]@{lane=1;campaignId='core-r01-s1-shared--shared';block=1};$negativeFixture=New-VerificationPlan $negativeRow 'negative-fail-closed' 'excluded-negative-fail-closed-verification' 2;$negativeOutput=Join-Path $blockRoot 'negative-fail-closed';$old=$env:PSModulePath;try{$env:PSModulePath=$nativePowerShellModulePath;$negativeChild=Start-BlockChild $negativeFixture 'negative-fail-closed' $negativeOutput $true;Wait-OwnedChildren @($negativeChild) $ChildTimeoutSeconds 'negative fail-closed block'}finally{$env:PSModulePath=$old};Assert-Quiescent

    $repeatRow=[pscustomobject]@{lane=1;campaignId='core-r01-s1-shared--shared';block=2};$repeatFixture=New-VerificationPlan $repeatRow 'repeatability' 'excluded-verification' 0;$repeatOutputs=@();foreach($suffix in @('a','b')){$output=Join-Path $blockRoot ('repeatability-'+$suffix);$old=$env:PSModulePath;try{$env:PSModulePath=$nativePowerShellModulePath;$child=Start-BlockChild $repeatFixture ('repeatability-'+$suffix) $output $false;Wait-OwnedChildren @($child) $ChildTimeoutSeconds ('repeatability-'+$suffix)}finally{$env:PSModulePath=$old};Assert-Quiescent;$repeatOutputs+=$output}

    $comparisons=New-Object Collections.Generic.List[object];$positiveRecords=New-Object Collections.Generic.List[object];foreach($child in $positiveChildren){$positiveRecords.Add([pscustomobject]@{output=$child.output;campaignId=[string]$child.fixture.originalCampaignId})};foreach($output in $repeatOutputs){$positiveRecords.Add([pscustomobject]@{output=$output;campaignId=[string]$repeatFixture.originalCampaignId})};$coldRoot=Join-Path $ProjectPath 'Research\PilotRuns\Gate12R_ProcessReuse_5pct\v4\cold-control';$processIds=New-Object Collections.Generic.List[int]
    foreach($record in $positiveRecords){$output=[string]$record.output;$campaignId=[string]$record.campaignId;$manifest=Read-G13R36Json (Join-Path $output 'block-manifest.json');$processIds.Add([int]$manifest.processId);foreach($sample in @($manifest.samples)){$candidatePath=Join-Path $output ([string]$sample.workloadResultRelativePath).Replace('/','\');$slug=Get-G13R36AlgorithmSlug ([string]$sample.algorithmId);$referencePath=Join-Path $coldRoot ($campaignId+'\'+$slug+'\workload-result.json');if(-not(Test-Path -LiteralPath $referencePath)){throw "Cold structural control missing: $referencePath"};$comparison=Compare-Gate10RStructuralResults -Reference (Read-G13R36Json $referencePath) -Candidate (Read-G13R36Json $candidatePath);$comparisons.Add([pscustomobject][ordered]@{output=$output;campaignId=$campaignId;algorithmId=[string]$sample.algorithmId;position=[int]$sample.position;referenceSha256=Get-G13R36LowerSha256 $referencePath;candidateSha256=Get-G13R36LowerSha256 $candidatePath;referenceProjectionSha256=$comparison.referenceProjectionSha256;candidateProjectionSha256=$comparison.candidateProjectionSha256;passed=[bool]$comparison.passed})}}
    $negativeWrapper=Read-G13R36Json ($negativeOutput+'.wrapper-summary.json');$processIds.Add([int]$negativeWrapper.processId)
    $repeatA=Read-G13R36Json (Join-Path $repeatOutputs[0] 'block-manifest.json');$repeatB=Read-G13R36Json (Join-Path $repeatOutputs[1] 'block-manifest.json');$repeatabilityPassed=[int]$repeatA.processId-ne[int]$repeatB.processId-and[string]$repeatA.processStartTimeUtc-ne[string]$repeatB.processStartTimeUtc
    for($i=0;$i-lt@($repeatA.samples).Count;$i++){$a=Read-G13R36Json (Join-Path $repeatOutputs[0] ([string]$repeatA.samples[$i].workloadResultRelativePath).Replace('/','\'));$b=Read-G13R36Json (Join-Path $repeatOutputs[1] ([string]$repeatB.samples[$i].workloadResultRelativePath).Replace('/','\'));if((Compare-Gate10RStructuralResults -Reference $a -Candidate $b).passed-ne$true){$repeatabilityPassed=$false}}
    $negativeCheckpoint=Read-G13R36Json (Join-Path $negativeOutput 'block-checkpoint.json');$negativePassed=$negativeWrapper.passed-eq$true-and[string]$negativeCheckpoint.status-eq'failed-no-auto-retry'-and[int]$negativeCheckpoint.completedSampleCount-eq1-and-not(Test-Path -LiteralPath (Join-Path $negativeOutput 'block-manifest.json'))
    $uniqueProcesses=@($processIds|Sort-Object -Unique).Count-eq$processIds.Count;$mismatches=@($comparisons|Where-Object passed -ne $true).Count
    $blockPassed=$positiveChildren.Count-eq4-and$mismatches-eq0-and$negativePassed-and$repeatabilityPassed-and$uniqueProcesses
    $blockSummary=[ordered]@{schemaVersion=1;summaryKind='gate13r-36h-four-lane-block-verification-v16';completedAtUtc=[DateTime]::UtcNow.ToString('o');concurrentPositiveBlockCount=$positiveChildren.Count;structuralComparisonCount=$comparisons.Count;structuralMismatchCount=$mismatches;comparisons=$comparisons.ToArray();negativeFailClosedPassed=$negativePassed;negativeCheckpointSha256=Get-G13R36LowerSha256 (Join-Path $negativeOutput 'block-checkpoint.json');independentProcessRepeatabilityPassed=$repeatabilityPassed;unityProcessIds=$processIds.ToArray();uniqueUnityProcessPassed=$uniqueProcesses;formalCampaign=$false;passed=$blockPassed}
    Write-G13R36AtomicUtf8NoBomJson -Path (Join-Path $blockRoot 'summary.json') -Value $blockSummary -Depth 50;if(-not$blockPassed){throw 'Block verification summary failed.'}

    Write-Checkpoint 'running' 'retained-regression' ''
    [void](Invoke-Child '04-retained-regression' (Join-Path $ProjectPath 'Research\Verification\Run-Gate13R36hRetainedRegressionV16.ps1') @('-ProjectPath',$ProjectPath,'-OutputDirectory',(Join-Path $verificationRoot 'RetainedRegression')) 600)
    Write-Checkpoint 'running' 'environment-stabilization' ''
    [void](Invoke-Child '04b-environment-stabilization' (Join-Path $ProjectPath 'Research\Verification\Wait-Gate13R36hEnvironmentStabilizationV16.ps1') @('-ProjectPath',$ProjectPath,'-VerificationRoot',$verificationRoot) 660)
    $stabilization=Read-G13R36Json (Join-Path $verificationRoot 'EnvironmentStabilization.summary.json');if($stabilization.passed-ne$true-or[long]$stabilization.thresholdBytes-ne17179869184L-or$stabilization.processTerminationUsed-ne$false-or$stabilization.workingSetTrimmingUsed-ne$false-or$stabilization.cacheFlushUsed-ne$false-or$stabilization.thresholdRelaxed-ne$false){throw 'Non-invasive environment stabilization failed or changed the frozen gate.'}
    Write-Checkpoint 'running' 'validation-only-audit' ''
    [void](Invoke-Child '05-validation-only-audit' (Join-Path $ProjectPath 'Research\Verification\Run-Gate13R36hValidationOnlyPrePilotAuditV16.ps1') @('-ProjectPath',$ProjectPath,'-VerificationRoot',$verificationRoot) 600)
    $audit=Read-G13R36Json (Join-Path $verificationRoot 'ValidationOnlyPrePilotAudit.summary.json');if($audit.passed-ne$true){throw 'Validation-only pre-pilot audit failed.'}
    Write-Checkpoint 'passed-pilot-authorized-once' 'complete' ''
    Write-Host 'Gate13R 36h non-executing verification passed. Exactly one non-formal pilot may start; no formal campaign is authorized.' -ForegroundColor Green
    exit 0
}catch{
    $errorText=$_.Exception.ToString();Write-Checkpoint 'failed-no-auto-retry' 'verification' $errorText
    $files=New-Object Collections.Generic.List[object];foreach($file in Get-ChildItem -LiteralPath $verificationRoot -Recurse -File -Force){$files.Add([pscustomobject][ordered]@{relativePath=$file.FullName.Substring($verificationRoot.TrimEnd('\').Length+1).Replace('\','/');bytes=[long]$file.Length;sha256=(Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()})}
    Write-G13R36AtomicUtf8NoBomJson -Path (Join-Path $verificationRoot 'partial-output-manifest.json') -Value ([ordered]@{schemaVersion=1;manifestKind='gate13r-36h-verification-partial-output-manifest-v16';savedAtUtc=[DateTime]::UtcNow.ToString('o');fileCount=$files.Count;files=$files.ToArray();formalCampaign=$false}) -Depth 40
    Write-G13R36AtomicUtf8NoBomJson -Path (Join-Path $verificationRoot 'failure-receipt.json') -Value ([ordered]@{schemaVersion=1;failureKind='gate13r-36h-nonexecuting-verification-failure-v16';failedAtUtc=[DateTime]::UtcNow.ToString('o');status='FAILED-NO-AUTO-RETRY';error=$errorText;pilotStarted=$false;formalCampaign=$false;automaticRetryAttempted=$false;automaticResumeAttempted=$false}) -Depth 20
    Write-Error "Gate13R 36h verification failed closed: $errorText"
    exit 1
}
