[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$ProjectPath,
    [Parameter(Mandatory=$true)][string]$VerificationRoot,
    [Parameter(Mandatory=$true)][string]$PilotPlanPath,
    [Parameter(Mandatory=$true)][string]$ProvenancePath,
    [Parameter(Mandatory=$true)][string]$TelemetryResultPath,
    [string]$UnityPath='H:\UnityEditor\2022.3.30f1c1\Editor\Unity.exe',
    [switch]$BindingSmokeOnly
)
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
if([string]::IsNullOrWhiteSpace($ProjectPath)-or-not[IO.Path]::IsPathRooted($ProjectPath)){throw 'PR1B block verification requires an explicit absolute ProjectPath.'};$ProjectPath=[IO.Path]::GetFullPath($ProjectPath)
if($BindingSmokeOnly){Write-Output("BINDING-SMOKE-PASSED|Run-Gate13RPR1BV2BlockVerificationV1|$ProjectPath");exit 0}
$VerificationRoot=[IO.Path]::GetFullPath($VerificationRoot);$PilotPlanPath=[IO.Path]::GetFullPath($PilotPlanPath);$ProvenancePath=[IO.Path]::GetFullPath($ProvenancePath);$TelemetryResultPath=[IO.Path]::GetFullPath($TelemetryResultPath);$UnityPath=[IO.Path]::GetFullPath($UnityPath)
Import-Module (Join-Path $ProjectPath 'Research\Gate13RPR1BOrderEffectPreparationV2.psm1') -Force
$plan=Read-Gate13RPR1BV2Json $PilotPlanPath;$provenance=Read-Gate13RPR1BV2Json $ProvenancePath
$root=Join-Path $VerificationRoot 'BlockVerification';if(Test-Path -LiteralPath $root){throw "Create-new block-verification root exists: $root"};New-Item -ItemType Directory -Path $root -Force|Out-Null;New-Item -ItemType Directory -Path (Join-Path $root 'plans') -Force|Out-Null
$runner=Join-Path $ProjectPath 'Research\Run-Gate13RPR1BMemoryAwareBlockV2.ps1';$winps='C:\WINDOWS\System32\WindowsPowerShell\v1.0\powershell.exe';$native=@('C:\Users\bdscy\Documents\WindowsPowerShell\Modules','C:\Program Files\WindowsPowerShell\Modules','C:\WINDOWS\System32\WindowsPowerShell\v1.0\Modules')-join';'
function Invoke-Child([string[]]$Arguments,[string]$Stdout,[string]$Stderr){$old=$env:PSModulePath;try{$env:PSModulePath=$native;&$winps @Arguments 1>$Stdout 2>$Stderr;return [int]$LASTEXITCODE}finally{$env:PSModulePath=$old}}
function Copy-ItemForRole($Source,[string]$Role,[string]$Prefix,[string]$Relative){return [pscustomobject][ordered]@{ordinal=$Source.ordinal;analysisRole=$Role;wave=$Source.wave;scenarioWaveSlot=$Source.scenarioWaveSlot;scenarioId=$Source.scenarioId;block=$Source.block;mirroredPairId=$Source.mirroredPairId;firstSuperblockOrder=$Source.firstSuperblockOrder;superblockOrder=$Source.superblockOrder;superblockSequencePosition=$Source.superblockSequencePosition;cohortProcessPosition=$Source.cohortProcessPosition;pairProcessPosition=$Source.pairProcessPosition;campaign=$Source.campaign;campaignIdPrefix=$Prefix;relativeOutput=$Relative}}
function Invoke-VerificationBlock($Item,[int]$Ordinal,[bool]$ExpectFailure){
    $injected=if($ExpectFailure){2}else{0};$blockPlan=New-Gate13RPR1BV2BlockPlan -ProjectPath $ProjectPath -Plan $plan -Provenance $provenance -ScheduleItem $Item -ProvenancePath $ProvenancePath -TelemetryProbeResultPath $TelemetryResultPath -InjectedFailurePosition $injected
    $planFile=Join-Path $root ('plans\{0:D2}-{1}.json'-f$Ordinal,[string]$Item.campaignIdPrefix);Write-Gate13RPR1BV2Utf8NoBomJson -Path $planFile -Value $blockPlan -Depth 30
    $output=Join-Path $root ([string]$Item.relativeOutput);$parent=Split-Path -Parent $output;if(-not(Test-Path $parent)){New-Item -ItemType Directory -Path $parent -Force|Out-Null};$stdout=$output+'.stdout.log';$stderr=$output+'.stderr.log'
    $args=@('-NoProfile','-ExecutionPolicy','Bypass','-File',$runner,'-ProjectPath',$ProjectPath,'-BlockPlanPath',$planFile,'-OutputDirectory',$output,'-AllowedRoot',$VerificationRoot,'-Mode','Verification','-UnityPath',$UnityPath)
    if($ExpectFailure){$args+=@('-ExpectFailure','-ExpectedCompletedSamplesBeforeFailure',1)}
    $exit=Invoke-Child $args $stdout $stderr;$summaryPath=$output+'.summary.json';if($exit-ne0-or-not(Test-Path $summaryPath)){throw "Verification block failed: $($blockPlan.blockId) exit=$exit"};$summary=Read-Gate13RPR1BV2Json $summaryPath;if($summary.passed-ne$true){throw "Verification summary failed: $($blockPlan.blockId)"}
    return [pscustomobject][ordered]@{ordinal=$Ordinal;expectedFailure=$ExpectFailure;blockId=[string]$blockPlan.blockId;superblockOrder=[string]$Item.superblockOrder;pairProcessPosition=[int]$Item.pairProcessPosition;comparisonCohortId=[string]$Item.campaign.comparisonCohortId;summaryRelativePath=Get-Gate13RPR1BV2ProjectRelativePath $ProjectPath $summaryPath;summarySha256=Get-Gate13RPR1BV2LowerSha256 $summaryPath;processId=[int]$summary.unityProcessId;sampleCount=[int]$summary.sampleCount;passed=$true}
}
try{
    $campaigns=@(Get-Gate13RPR1BV2Campaigns -ProjectPath $ProjectPath -Plan $plan);$schedule=@(Get-Gate13RPR1BV2ProcessSchedule -Plan $plan -Campaigns $campaigns -AnalysisRole 'measured-non-formal-pilot')
    $source=@($schedule|Where-Object mirroredPairId -eq 'core-r01-s1-hetero::b001'|Sort-Object pairProcessPosition);if($source.Count-ne4){throw 'Positive mirrored fixture schedule count mismatch.'}
    $entries=New-Object Collections.Generic.List[object];$n=0
    foreach($item in $source){$n++;$copy=Copy-ItemForRole $item 'excluded-verification' ('g13r-pr1b-v-pos{0:D2}'-f$n) ('positive-mirrored\p{0:D2}'-f$n);$entries.Add((Invoke-VerificationBlock $copy $n $false))}
    if(@($entries.processId|Select-Object -Unique).Count-ne4){throw 'Positive mirrored fixture did not use four unique Unity processes.'}
    $negSource=@($schedule|Where-Object{$_.scenarioId-eq'core-r01-s1-hetero'-and$_.block-eq2-and$_.superblockOrder-eq'AB'-and$_.cohortProcessPosition-eq1})[0]
    $negative=Copy-ItemForRole $negSource 'excluded-negative-fail-closed-verification' 'g13r-pr1b-v-negative' 'negative-fail-closed\per-agent'
    $negativeResult=Invoke-VerificationBlock $negative 5 $true
    if($negativeResult.sampleCount-ne1){throw 'Negative fail-closed fixture completed an unexpected sample count.'}
    $summary=[ordered]@{schemaVersion=1;summaryKind='gate13r-pr1b-v2-positive-mirrored-and-negative-fail-closed-verification-v1';savedAtUtc=[DateTime]::UtcNow.ToString('o');positiveProcessCount=4;positiveSampleCount=[int](($entries|Measure-Object sampleCount -Sum).Sum);positiveUniqueProcessCount=@($entries.processId|Select-Object -Unique).Count;positiveEntries=$entries.ToArray();negativeEntry=$negativeResult;formalCampaign=$false;passed=$true}
    Write-Gate13RPR1BV2AtomicUtf8NoBomJson -Path (Join-Path $root 'summary.json') -Value $summary -Depth 30;Write-Host 'PR1B block verification passed.' -ForegroundColor Green;exit 0
}catch{$failure=[ordered]@{schemaVersion=1;receiptKind='gate13r-pr1b-v2-block-verification-failure-v1';failedAtUtc=[DateTime]::UtcNow.ToString('o');message=$_.Exception.ToString();formalCampaign=$false;passed=$false};Write-Gate13RPR1BV2AtomicUtf8NoBomJson -Path (Join-Path $root 'failure-receipt.json') -Value $failure -Depth 10;Write-Error $_;exit 1}
