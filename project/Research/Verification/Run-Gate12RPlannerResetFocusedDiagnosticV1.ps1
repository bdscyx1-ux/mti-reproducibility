[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$ProjectPath,
    [string]$UnityPath='H:\UnityEditor\2022.3.30f1c1\Editor\Unity.exe'
)

$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
if([string]::IsNullOrWhiteSpace($ProjectPath)-or-not[IO.Path]::IsPathRooted($ProjectPath)){throw 'ProjectPath must be an explicit absolute path.'};$ProjectPath=[IO.Path]::GetFullPath($ProjectPath);$UnityPath=[IO.Path]::GetFullPath($UnityPath)
Import-Module (Join-Path $ProjectPath 'Research\Gate12RProcessReusePreparation.psm1') -Force
Import-Module (Join-Path $ProjectPath 'Research\Gate10RProcessReusePreparation.psm1') -Force

$diagnosticRoot=[IO.Path]::GetFullPath((Join-Path $ProjectPath 'Research\Verification\Gate12R_ProcessReuse_5pct\reset-diagnostic-v1'))
$pilotPlanPath=Join-Path $ProjectPath 'Research\Gate12R_5pct_ProcessReuse_Pilot_Plan.v2.json'
$provenancePath=Join-Path $ProjectPath 'Research\Gate12R_5pct_ProcessReuse_Pilot_Provenance.v5.json'
$telemetryResultPath=Join-Path $ProjectPath 'Research\Verification\Gate12R_ProcessReuse_5pct\v3\TelemetryProbe\v1\telemetry-probe-result.json'
$runner=Join-Path $ProjectPath 'Research\Run-Gate12RProcessReuseBlockV2.ps1'
$compileRunner=Join-Path $ProjectPath 'Research\Verification\Run-Gate12RCompileV3.ps1'
$formalRoot=Join-Path $ProjectPath 'Research\FormalRuns\Gate13R_ProcessReuse_5pct\v1'
$pilotV2Root=Join-Path $ProjectPath 'Research\PilotRuns\Gate12R_ProcessReuse_5pct\v2'
$summaryPath=Join-Path $diagnosticRoot 'focused-diagnostic-summary.json'

if(Test-Path -LiteralPath $diagnosticRoot){throw "Create-new diagnostic root exists: $diagnosticRoot"}
if(Test-Path -LiteralPath $formalRoot){throw 'Gate13R formal root must remain absent.'};if(Test-Path -LiteralPath $pilotV2Root){throw 'Pilot v2 root must remain absent during the focused diagnostic.'}
if(@(Get-Process -Name Unity -ErrorAction SilentlyContinue).Count-gt0-or(Test-Path -LiteralPath (Join-Path $ProjectPath 'Temp\UnityLockfile'))){throw 'Unity must be closed and the project lock absent.'}
if((Get-Gate12RLowerSha256 $pilotPlanPath)-ne'c76a0a1dc2ecc4efbc4f5419bee9890cf275c9b1fec7e4c64b22d8e2688849cf'){throw 'Pilot plan v2 hash mismatch.'}
if((Get-Gate12RLowerSha256 $provenancePath)-ne'df5b1990112d8da2f92e1bcb49933967f5abce1c8bea7dba971c2b74fa740de9'){throw 'Provenance v5 hash mismatch.'}
$plan=Read-Gate12RJson $pilotPlanPath;$provenance=Read-Gate12RJson $provenancePath
foreach($binding in @($provenance.boundFiles)){$path=Join-Path $ProjectPath ([string]$binding.relativePath).Replace('/','\');if(-not(Test-Path $path)-or(Get-Gate12RLowerSha256 $path)-ne[string]$binding.sha256){throw "Provenance binding failed: $($binding.relativePath)"}}

New-Item -ItemType Directory -Path $diagnosticRoot|Out-Null
$orchestration=Join-Path $diagnosticRoot 'Orchestration';New-Item -ItemType Directory -Path $orchestration|Out-Null
$plansRoot=Join-Path $diagnosticRoot 'plans';New-Item -ItemType Directory -Path $plansRoot|Out-Null
$runsRoot=Join-Path $diagnosticRoot 'runs';New-Item -ItemType Directory -Path $runsRoot|Out-Null
$windowsPowerShell='C:\WINDOWS\System32\WindowsPowerShell\v1.0\powershell.exe';$nativeModulePath=@('C:\Users\bdscy\Documents\WindowsPowerShell\Modules','C:\Program Files\WindowsPowerShell\Modules','C:\WINDOWS\System32\WindowsPowerShell\v1.0\Modules')-join';'
function Invoke-Child([string[]]$Arguments,[string]$Stdout,[string]$Stderr){$old=$env:PSModulePath;try{$env:PSModulePath=$nativeModulePath;&$windowsPowerShell @Arguments 1>$Stdout 2>$Stderr;return [int]$LASTEXITCODE}finally{$env:PSModulePath=$old}}
function Write-AtomicJson([string]$Path,$Value){Write-Gate12RAtomicUtf8NoBomJson -Path $Path -Value $Value -Depth 50}

$records=New-Object Collections.Generic.List[object];$comparisons=New-Object Collections.Generic.List[object]
try{
    $compileExit=Invoke-Child @('-NoProfile','-ExecutionPolicy','Bypass','-File',$compileRunner,'-ProjectPath',$ProjectPath,'-VerificationRoot',$diagnosticRoot,'-UnityPath',$UnityPath) (Join-Path $orchestration '01-compile.stdout.log') (Join-Path $orchestration '01-compile.stderr.log')
    if($compileExit-ne0){throw "Reset-command compile diagnostic failed: exit=$compileExit"}
    $compile=Read-Gate12RJson (Join-Path $diagnosticRoot 'Compile\summary.json');if($compile.passed-ne$true-or[string]$compile.unityCommandSha256-ne'2c1fdd6d8ad4edd8ac36f8d9fb3962e909673cf0eb0a14d85814f975f01b9b06'){throw 'Compile summary did not bind the passing reset command.'}

    $campaigns=@(Get-Gate12RCampaigns -ProjectPath $ProjectPath -Plan $plan);$campaign=@($campaigns|Where-Object campaignId -eq 'core-r01-s1-hetero--per-agent');if($campaign.Count-ne1){throw 'Focused diagnostic campaign did not resolve exactly once.'};$campaign=$campaign[0]
    $referenceRoot=Join-Path $ProjectPath 'Research\PilotRuns\Gate12R_ProcessReuse_5pct\v1\measured\07-core-r01-s1-hetero--per-agent\b017\runs'
    $referenceByAlgorithm=@{'A*-R'=Join-Path $referenceRoot 'p01-astar-r\workload-result.json';'D*L'=Join-Path $referenceRoot 'p02-dstar-l\workload-result.json'}
    $firstByAlgorithm=@{}
    foreach($repeat in 1..3){
        $prefix='g12r-resetdiag-r{0:D2}'-f$repeat;$blockPlan=New-Gate12RBlockPlan -ProjectPath $ProjectPath -Plan $plan -Provenance $provenance -Campaign $campaign -Block 17 -ProvenancePath $provenancePath -TelemetryProbeResultPath $telemetryResultPath -AnalysisRole 'excluded-verification' -CampaignIdPrefix $prefix
        if((@($blockPlan.entries|ForEach-Object algorithmId)-join'|')-ne'A*-R|D*L'){throw "Focused diagnostic Williams row changed on repeat $repeat."}
        $planPath=Join-Path $plansRoot ('repeat-{0:D2}.block-plan.json'-f$repeat);Write-Gate12RUtf8NoBomJson -Path $planPath -Value $blockPlan -Depth 30
        $output=Join-Path $runsRoot ('repeat-{0:D2}'-f$repeat);$stdout=Join-Path $orchestration ('repeat-{0:D2}.stdout.log'-f$repeat);$stderr=Join-Path $orchestration ('repeat-{0:D2}.stderr.log'-f$repeat)
        $exit=Invoke-Child @('-NoProfile','-ExecutionPolicy','Bypass','-File',$runner,'-ProjectPath',$ProjectPath,'-BlockPlanPath',$planPath,'-OutputDirectory',$output,'-AllowedRoot',$diagnosticRoot,'-Mode','Verification','-UnityPath',$UnityPath) $stdout $stderr
        if($exit-ne0){throw "Focused diagnostic repeat $repeat failed: exit=$exit stderr=$stderr"}
        $wrapper=Read-Gate12RJson ($output+'.summary.json');$manifest=Read-Gate12RJson (Join-Path $output 'block-manifest.json')
        if($wrapper.passed-ne$true-or$manifest.completed-ne$true-or$manifest.hardMemoryRulesPassed-ne$true-or[long]$manifest.blockRetainedManagedGrowthBytes-gt134217728L){throw "Focused diagnostic repeat $repeat did not pass the frozen memory rule."}
        foreach($sample in @($manifest.samples)){
            $childManifest=Read-Gate12RJson (Join-Path $output ([string]$sample.manifestRelativePath).Replace('/','\'));if($childManifest.plannerResetCompleted-ne$true-or$childManifest.forcedGcAfterCompleted-ne$true){throw "Reset/GC contract failed: repeat=$repeat algorithm=$($sample.algorithmId)"}
            $candidatePath=Join-Path $output ([string]$sample.workloadResultRelativePath).Replace('/','\');$candidate=Read-Gate12RJson $candidatePath;$reference=Read-Gate12RJson ([string]$referenceByAlgorithm[[string]$sample.algorithmId]);$comparison=Compare-Gate10RStructuralResults -Reference $reference -Candidate $candidate
            $comparisons.Add([pscustomobject][ordered]@{kind='failed-attempt1-reference';repeat=$repeat;algorithmId=[string]$sample.algorithmId;referenceProjectionSha256=$comparison.referenceProjectionSha256;candidateProjectionSha256=$comparison.candidateProjectionSha256;passed=$comparison.passed})
            if($comparison.passed-ne$true){throw "Structural result differs from the frozen failed-attempt reference: repeat=$repeat algorithm=$($sample.algorithmId)"}
            if($repeat-eq1){$firstByAlgorithm[[string]$sample.algorithmId]=$candidatePath}else{$first=Read-Gate12RJson ([string]$firstByAlgorithm[[string]$sample.algorithmId]);$repeatComparison=Compare-Gate10RStructuralResults -Reference $first -Candidate $candidate;$comparisons.Add([pscustomobject][ordered]@{kind='independent-process-repeatability';repeat=$repeat;algorithmId=[string]$sample.algorithmId;referenceProjectionSha256=$repeatComparison.referenceProjectionSha256;candidateProjectionSha256=$repeatComparison.candidateProjectionSha256;passed=$repeatComparison.passed});if($repeatComparison.passed-ne$true){throw "Independent-process structural mismatch: repeat=$repeat algorithm=$($sample.algorithmId)"}}
        }
        $records.Add([pscustomobject][ordered]@{repeat=$repeat;blockId=[string]$manifest.blockId;processId=[int]$manifest.processId;processStartTimeUtc=[string]$manifest.processStartTimeUtc;blockRetainedManagedGrowthBytes=[long]$manifest.blockRetainedManagedGrowthBytes;blockWorkingSetGrowthBytes=[long]$manifest.blockWorkingSetGrowthBytes;blockPrivateMemoryGrowthBytes=[long]$manifest.blockPrivateMemoryGrowthBytes;sampleCount=[int]$manifest.completedSampleCount;wrapperSummarySha256=Get-Gate12RLowerSha256 ($output+'.summary.json');blockManifestSha256=Get-Gate12RLowerSha256 (Join-Path $output 'block-manifest.json');passed=$true})
    }
    if(@($records|Select-Object -ExpandProperty processId|Sort-Object -Unique).Count-ne3){throw 'Focused diagnostic repeats did not use three distinct Unity process IDs.'}
    if(@($records|Select-Object -ExpandProperty processStartTimeUtc|Sort-Object -Unique).Count-ne3){throw 'Focused diagnostic repeats did not use three distinct process start times.'}
    if(@($comparisons|Where-Object passed -ne $true).Count-ne0-or$comparisons.Count-ne10){throw 'Focused diagnostic structural comparison cardinality/result mismatch.'}
    if(@(Get-Process -Name Unity -ErrorAction SilentlyContinue).Count-ne0-or(Test-Path -LiteralPath (Join-Path $ProjectPath 'Temp\UnityLockfile'))){throw 'Unity/lock remained after focused diagnostic.'}
    $growths=[long[]]@($records|ForEach-Object blockRetainedManagedGrowthBytes)
    $summary=[ordered]@{schemaVersion=1;summaryKind='gate12r-planner-reset-focused-diagnostic-v1';completedAtUtc=[DateTime]::UtcNow.ToString('o');campaignId='core-r01-s1-hetero--per-agent';block=17;williamsOrder=@('A*-R','D*L');freshProcessRepeatCount=3;distinctProcessIdCount=3;blockRetainedManagedGrowthBytes=$growths;maximumBlockRetainedManagedGrowthBytes=[long](($growths|Measure-Object -Maximum).Maximum);frozenManagedLimitBytes=134217728L;memoryRulePassed=$true;structuralComparisonCount=$comparisons.Count;structuralComparisons=$comparisons.ToArray();records=$records.ToArray();originalCommandSha256='9218c72b7e4d1d289feef9a367e376a497b06f048099572ac73042f28d482407';resetCommandSha256='2c1fdd6d8ad4edd8ac36f8d9fb3962e909673cf0eb0a14d85814f975f01b9b06';rawTelemetryBoundaryChanged=$false;thresholdsChanged=$false;formalCampaign=$false;excludedFromFormalAnalysis=$true;pilotV2RootCreated=$false;gate13rRootCreated=$false;passed=$true}
    Write-AtomicJson $summaryPath $summary
    Write-Host 'Gate12R planner-reset focused diagnostic passed 3 fresh processes.' -ForegroundColor Green
    exit 0
}catch{
    $failure=[ordered]@{schemaVersion=1;receiptKind='gate12r-planner-reset-focused-diagnostic-failure-v1';failedAtUtc=[DateTime]::UtcNow.ToString('o');message=$_.Exception.ToString();completedRepeatCount=$records.Count;records=$records.ToArray();formalCampaign=$false;excludedFromFormalAnalysis=$true;automaticResumeAuthorized=$false;pilotV2RootCreated=Test-Path $pilotV2Root;gate13rRootCreated=Test-Path $formalRoot}
    Write-AtomicJson (Join-Path $diagnosticRoot 'failure-receipt.json') $failure
    Write-Error "Gate12R planner-reset focused diagnostic failed closed: $($_.Exception.Message)";exit 1
}

