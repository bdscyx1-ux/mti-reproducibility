[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$ProjectPath,
    [Parameter(Mandatory=$true)][string]$VerificationRoot,
    [Parameter(Mandatory=$true)][string]$ProvenancePath,
    [Parameter(Mandatory=$true)][string]$TelemetryResultPath,
    [string]$UnityPath='H:\UnityEditor\2022.3.30f1c1\Editor\Unity.exe',
    [switch]$BindingSmokeOnly
)

$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
if([string]::IsNullOrWhiteSpace($ProjectPath)-or-not[IO.Path]::IsPathRooted($ProjectPath)){throw 'Gate12R block gate requires an explicit absolute ProjectPath.'}
$ProjectPath=[IO.Path]::GetFullPath($ProjectPath)
if($BindingSmokeOnly){Write-Output("BINDING-SMOKE-PASSED|Run-Gate12RBlockAndRegressionGates|$ProjectPath");exit 0}
$VerificationRoot=[IO.Path]::GetFullPath($VerificationRoot);$ProvenancePath=[IO.Path]::GetFullPath($ProvenancePath);$TelemetryResultPath=[IO.Path]::GetFullPath($TelemetryResultPath);$UnityPath=[IO.Path]::GetFullPath($UnityPath)
Import-Module (Join-Path $ProjectPath 'Research\Gate12RProcessReusePreparation.psm1') -Force
Import-Module (Join-Path $ProjectPath 'Research\Gate10RProcessReusePreparation.psm1') -Force
$base=[IO.Path]::GetFullPath((Join-Path $ProjectPath 'Research\Verification\Gate12R_ProcessReuse_5pct'))
if(-not$VerificationRoot.StartsWith($base.TrimEnd('\')+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'VerificationRoot is outside Gate12R versioned base.'}
if(-not(Test-Path -LiteralPath $VerificationRoot -PathType Container)){throw 'VerificationRoot must already exist.'}
if(-not(Test-Path -LiteralPath $TelemetryResultPath -PathType Leaf)){throw 'Passing telemetry result is missing.'}
if(Test-Path -LiteralPath (Join-Path $ProjectPath 'Research\FormalRuns\Gate13R_ProcessReuse_5pct\v1')){throw 'Gate13R formal root must remain absent.'}
$gateRoot=Join-Path $VerificationRoot 'BlockAndRegression';if(Test-Path -LiteralPath $gateRoot){throw "Create-new block/regression output exists: $gateRoot"};New-Item -ItemType Directory -Path $gateRoot|Out-Null
$plansRoot=Join-Path $gateRoot 'plans';New-Item -ItemType Directory -Path $plansRoot|Out-Null
$summaryPath=Join-Path $gateRoot 'summary.json'
$modulePath=Join-Path $ProjectPath 'Research\Gate12RProcessReusePreparation.psm1'
$runner=Join-Path $ProjectPath 'Research\Run-Gate12RProcessReuseBlock.ps1'
$coldRunner=Join-Path $ProjectPath 'Research\Run-Gate12RColdReferenceV3.ps1'
$harness=Join-Path $ProjectPath 'Research\Verification\Gate10RAttempt4RetainedHarnessV4.ps1'
$frozenRetained=Join-Path $ProjectPath 'Research\Verification\Run-Gate12AnalysisUnitTests.ps1'
$frozenRetainedSummary=Join-Path $ProjectPath 'Research\Verification\Gate12_AnalysisUnitTests.summary.json'
$windowsPowerShell='C:\WINDOWS\System32\WindowsPowerShell\v1.0\powershell.exe'
$nativeModulePath=@('C:\Users\bdscy\Documents\WindowsPowerShell\Modules','C:\Program Files\WindowsPowerShell\Modules','C:\WINDOWS\System32\WindowsPowerShell\v1.0\Modules')-join';'
$plan=Read-Gate12RJson (Join-Path $ProjectPath 'Research\Gate12R_5pct_ProcessReuse_Pilot_Plan.v1.json')
$provenance=Read-Gate12RJson $ProvenancePath
$campaigns=@(Get-Gate12RCampaigns -ProjectPath $ProjectPath -Plan $plan)
$entries=New-Object Collections.Generic.List[object]
$comparisons=New-Object Collections.Generic.List[object]
$errors=New-Object Collections.Generic.List[string]

function Invoke-Child([string[]]$Arguments,[string]$Stdout,[string]$Stderr){$old=$env:PSModulePath;try{$env:PSModulePath=$nativeModulePath;&$windowsPowerShell @Arguments 1>$Stdout 2>$Stderr;return [int]$LASTEXITCODE}finally{$env:PSModulePath=$old}}
function Invoke-Block($Campaign,[int]$Block,[string]$Name,[string]$Prefix,[string]$Role,[int]$InjectedFailurePosition=0){
    $planObject=New-Gate12RBlockPlan -ProjectPath $ProjectPath -Plan $plan -Provenance $provenance -Campaign $Campaign -Block $Block -ProvenancePath $ProvenancePath -TelemetryProbeResultPath $TelemetryResultPath -AnalysisRole $Role -InjectedFailurePosition $InjectedFailurePosition -CampaignIdPrefix $Prefix
    $planFile=Join-Path $plansRoot ($Name+'.block-plan.json');Write-Gate12RUtf8NoBomJson -Path $planFile -Value $planObject -Depth 30
    $output=Join-Path $gateRoot ('fixtures\'+$Name);$stdout=$output+'.wrapper.stdout.log';$stderr=$output+'.wrapper.stderr.log';$parent=Split-Path -Parent $output;if(-not(Test-Path $parent)){New-Item -ItemType Directory -Path $parent -Force|Out-Null}
    $args=@('-NoProfile','-ExecutionPolicy','Bypass','-File',$runner,'-ProjectPath',$ProjectPath,'-BlockPlanPath',$planFile,'-OutputDirectory',$output,'-AllowedRoot',$VerificationRoot,'-Mode','Verification','-UnityPath',$UnityPath)
    if($InjectedFailurePosition-gt0){$args+=@('-ExpectFailure','-ExpectedCompletedSamplesBeforeFailure',($InjectedFailurePosition-1))}
    $started=Get-Date;$exit=Invoke-Child $args $stdout $stderr;$completed=Get-Date
    $wrapperPath=$output+'.summary.json';if($exit-ne0-or-not(Test-Path $wrapperPath)){throw "Block fixture failed: $Name exit=$exit stderr=$stderr"};$wrapper=Read-Gate12RJson $wrapperPath;if($wrapper.passed-ne$true){throw "Block fixture wrapper did not pass: $Name"}
    $record=[pscustomobject][ordered]@{kind='block';name=$Name;role=$Role;blockId=[string]$planObject.blockId;planPath=Get-Gate12RProjectRelativePath $ProjectPath $planFile;planSha256=Get-Gate12RLowerSha256 $planFile;outputPath=Get-Gate12RProjectRelativePath $ProjectPath $output;summarySha256=Get-Gate12RLowerSha256 $wrapperPath;wallSeconds=($completed-$started).TotalSeconds;expectedFailure=$InjectedFailurePosition-gt0;completed=$true}
    $entries.Add($record);return [pscustomobject]@{plan=$planObject;output=$output;record=$record}
}
function Invoke-Cold($Campaign,[string]$Algorithm,[string]$Name){
    $scenario=Join-Path $ProjectPath ([string]$Campaign.scenarioRelativePath).Replace('/','\');$output=Join-Path $gateRoot ('cold\'+$Name);$runId='g12r-verify-cold-'+$Name;$stdout=$output+'.wrapper.stdout.log';$stderr=$output+'.wrapper.stderr.log';$parent=Split-Path -Parent $output;if(-not(Test-Path $parent)){New-Item -ItemType Directory -Path $parent -Force|Out-Null}
    $args=@('-NoProfile','-ExecutionPolicy','Bypass','-File',$coldRunner,'-ProjectPath',$ProjectPath,'-ScenarioPath',$scenario,'-OutputDirectory',$output,'-AllowedRoot',$VerificationRoot,'-RunId',$runId,'-Algorithm',$Algorithm,'-UnityPath',$UnityPath)
    $started=Get-Date;$exit=Invoke-Child $args $stdout $stderr;$completed=Get-Date;$wrapperPath=$output+'.summary.json'
    if($exit-ne0-or-not(Test-Path $wrapperPath)){throw "Cold fixture failed: $Name exit=$exit stderr=$stderr"};$wrapper=Read-Gate12RJson $wrapperPath;if($wrapper.passed-ne$true){throw "Cold fixture wrapper did not pass: $Name"}
    $record=[pscustomobject][ordered]@{kind='cold-control';name=$Name;campaignId=$Campaign.campaignId;algorithmId=$Algorithm;outputPath=Get-Gate12RProjectRelativePath $ProjectPath $output;summarySha256=Get-Gate12RLowerSha256 $wrapperPath;wallSeconds=($completed-$started).TotalSeconds;completed=$true};$entries.Add($record);return [pscustomobject]@{output=$output;record=$record}
}
function Compare-BlockToCold($BlockResult,$ColdByAlgorithm,[string]$Label){
    $manifest=Read-Gate12RJson (Join-Path $BlockResult.output 'block-manifest.json')
    foreach($sample in @($manifest.samples)){$candidate=Read-Gate12RJson (Join-Path $BlockResult.output ([string]$sample.workloadResultRelativePath).Replace('/','\'));$coldOutput=[string]$ColdByAlgorithm[[string]$sample.algorithmId];$reference=Read-Gate12RJson (Join-Path $coldOutput 'workload-result.json');$comparison=Compare-Gate10RStructuralResults -Reference $reference -Candidate $candidate;$comparisons.Add([pscustomobject][ordered]@{label=$Label;algorithmId=[string]$sample.algorithmId;position=[int]$sample.position;referenceProjectionSha256=$comparison.referenceProjectionSha256;candidateProjectionSha256=$comparison.candidateProjectionSha256;passed=$comparison.passed});if($comparison.passed-ne$true){throw "Cold structural mismatch: $Label/$($sample.algorithmId)"}}
}
function Compare-TwoBlocks($Left,$Right,[string]$Label){
    $lm=Read-Gate12RJson (Join-Path $Left.output 'block-manifest.json');$rm=Read-Gate12RJson (Join-Path $Right.output 'block-manifest.json')
    foreach($ls in @($lm.samples)){$rs=@($rm.samples|Where-Object algorithmId -eq $ls.algorithmId);if($rs.Count-ne1){throw "Repeatability sample cardinality mismatch: $Label/$($ls.algorithmId)"};$lr=Read-Gate12RJson (Join-Path $Left.output ([string]$ls.workloadResultRelativePath).Replace('/','\'));$rr=Read-Gate12RJson (Join-Path $Right.output ([string]$rs[0].workloadResultRelativePath).Replace('/','\'));$comparison=Compare-Gate10RStructuralResults -Reference $lr -Candidate $rr;$comparisons.Add([pscustomobject][ordered]@{label=$Label;algorithmId=[string]$ls.algorithmId;referenceProjectionSha256=$comparison.referenceProjectionSha256;candidateProjectionSha256=$comparison.candidateProjectionSha256;passed=$comparison.passed});if($comparison.passed-ne$true){throw "Independent-process repeatability mismatch: $Label/$($ls.algorithmId)"}}
}

try{
    $shared=@($campaigns|Where-Object comparisonCohortId -eq 'four-algorithm-shared-goal-v1')[0]
    $perAgent=@($campaigns|Where-Object comparisonCohortId -eq 'per-agent-heterogeneous-goal-v1')[0]
    $grouped=@($campaigns|Where-Object comparisonCohortId -eq 'grouped-field-heterogeneous-goal-v1')[0]
    $positiveShared=Invoke-Block $shared 1 'positive-shared' 'g12r-v-shared' 'excluded-verification'
    $positivePerAgent=Invoke-Block $perAgent 1 'positive-per-agent' 'g12r-v-per-agent' 'excluded-verification'
    $positiveGrouped=Invoke-Block $grouped 1 'positive-grouped' 'g12r-v-grouped' 'excluded-verification'
    [void](Invoke-Block $shared 1 'negative-fail-closed' 'g12r-v-negative' 'excluded-negative-fail-closed-verification' 2)
    $repeatA=Invoke-Block $shared 2 'repeatability-a' 'g12r-v-repeat-a' 'excluded-verification'
    $repeatB=Invoke-Block $shared 2 'repeatability-b' 'g12r-v-repeat-b' 'excluded-verification'
    Compare-TwoBlocks $repeatA $repeatB 'independent-process-shared-block2'
    $comparisonFixtures=@(
        [pscustomobject]@{campaign=$shared;blockResult=$positiveShared;label='shared'},
        [pscustomobject]@{campaign=$perAgent;blockResult=$positivePerAgent;label='per-agent'},
        [pscustomobject]@{campaign=$grouped;blockResult=$positiveGrouped;label='grouped'}
    )
    foreach($fixture in $comparisonFixtures){$campaign=$fixture.campaign;$blockResult=$fixture.blockResult;$label=[string]$fixture.label;$coldMap=@{};foreach($algorithm in @($campaign.algorithms)){$name=$label+'-'+(Get-Gate12RAlgorithmSlug $algorithm);$cold=Invoke-Cold $campaign $algorithm $name;$coldMap[$algorithm]=$cold.output};Compare-BlockToCold $blockResult $coldMap $label}

    $retainedRoot=Join-Path $gateRoot 'RetainedRegression';New-Item -ItemType Directory -Path $retainedRoot|Out-Null
    $retainedSummary=Join-Path $retainedRoot 'RetainedRegression63.summary.json';$retainedStdout=Join-Path $retainedRoot 'RetainedRegression63.stdout.log';$retainedStderr=Join-Path $retainedRoot 'RetainedRegression63.stderr.log'
    $sourceBefore=Get-Gate12RLowerSha256 $frozenRetained;$summaryBefore=Get-Gate12RLowerSha256 $frozenRetainedSummary
    $exit=Invoke-Child @('-NoProfile','-ExecutionPolicy','Bypass','-File',$harness,'-ProjectPath',$ProjectPath,'-SummaryPath',$retainedSummary) $retainedStdout $retainedStderr
    $retained=if(Test-Path $retainedSummary){Read-Gate12RJson $retainedSummary}else{$null};$sourceAfter=Get-Gate12RLowerSha256 $frozenRetained;$summaryAfter=Get-Gate12RLowerSha256 $frozenRetainedSummary
    $retainedPassed=$exit-eq0-and$null-ne$retained-and$retained.passed-eq$true-and[int]$retained.assertionCount-eq63-and@($retained.failures).Count-eq0-and$sourceBefore-eq$sourceAfter-and$summaryBefore-eq$summaryAfter
    $retainedWrapper=[ordered]@{schemaVersion=1;kind='gate12r-retained-regression-wrapper-v1';savedAtUtc=[DateTime]::UtcNow.ToString('o');executionMethod='Windows PowerShell 5.1 -File';harnessSha256=Get-Gate12RLowerSha256 $harness;summarySha256=if(Test-Path $retainedSummary){Get-Gate12RLowerSha256 $retainedSummary}else{$null};assertionCount=if($null-ne$retained){[int]$retained.assertionCount}else{0};failureCount=if($null-ne$retained){@($retained.failures).Count}else{$null};exitCode=$exit;frozenSourceSha256Before=$sourceBefore;frozenSourceSha256After=$sourceAfter;originalSummarySha256Before=$summaryBefore;originalSummarySha256After=$summaryAfter;passed=$retainedPassed}
    Write-Gate12RAtomicUtf8NoBomJson -Path (Join-Path $retainedRoot 'wrapper.json') -Value $retainedWrapper -Depth 20
    if(-not$retainedPassed){throw "Retained regression did not pass 63/63 (exit=$exit)."}
}catch{$errors.Add($_.Exception.ToString())}
$summary=[ordered]@{schemaVersion=1;summaryKind='gate12r-block-cold-repeatability-retained-regression-gates-v1';savedAtUtc=[DateTime]::UtcNow.ToString('o');entryCount=$entries.Count;entries=$entries.ToArray();structuralComparisonCount=$comparisons.Count;structuralComparisons=$comparisons.ToArray();positiveBlockCount=@($entries|Where-Object {$_.kind-eq'block'-and-not$_.expectedFailure}).Count;negativeBlockCount=@($entries|Where-Object {$_.kind-eq'block'-and$_.expectedFailure}).Count;coldControlCount=@($entries|Where-Object kind -eq 'cold-control').Count;retainedRegressionRequiredAssertions=63;formalCampaign=$false;gate13rAuthorized=$false;errors=$errors.ToArray();passed=$errors.Count-eq0}
Write-Gate12RAtomicUtf8NoBomJson -Path $summaryPath -Value $summary -Depth 50
if($errors.Count){Write-Error("Gate12R block/regression gates failed: "+($errors-join'; '));exit 1}
Write-Host "Gate12R block/regression gates passed: $($entries.Count) process fixtures, $($comparisons.Count) structural comparisons, retained 63/63." -ForegroundColor Green
exit 0
