[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$ProjectPath)

$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$ProjectPath=[IO.Path]::GetFullPath($ProjectPath)
$utf8=New-Object Text.UTF8Encoding($false,$true)

function Get-Hash([string]$Path){return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()}
function Get-TextHash([string]$Text){$sha=[Security.Cryptography.SHA256]::Create();try{return [BitConverter]::ToString($sha.ComputeHash($utf8.GetBytes($Text))).Replace('-','').ToLowerInvariant()}finally{$sha.Dispose()}}
function Write-CreateNewText([string]$Path,[string]$Text){
    if(Test-Path -LiteralPath $Path){throw "Create-new target exists: $Path"}
    $parent=Split-Path -Parent $Path
    if(-not(Test-Path -LiteralPath $parent -PathType Container)){New-Item -ItemType Directory -Path $parent|Out-Null}
    [IO.File]::WriteAllText($Path,$Text,$utf8)
}
function Write-CreateNewJson([string]$Path,$Value,[int]$Depth=70){
    $text=($Value|ConvertTo-Json -Depth $Depth).Replace("`r`n","`n").Replace("`r","`n")
    if(-not$text.EndsWith("`n")){$text+="`n"}
    Write-CreateNewText $Path $text
}
function Get-Count([string]$Text,[string]$Needle){if([string]::IsNullOrEmpty($Needle)){return 0};return [regex]::Matches($Text,[regex]::Escape($Needle)).Count}
function Route([string]$From,[string]$To){return [pscustomobject]@{from=$From;to=$To}}
Remove-Item Alias:Route -ErrorAction SilentlyContinue

$derivations=New-Object Collections.Generic.List[object]
$commonRoutes=@(
    $(Route 'Gate13R36hConcurrencyPreparationV2' 'Gate13R36hConcurrencyPreparationV3'),
    $(Route 'Run-Gate13R36hBlockV2' 'Run-Gate13R36hBlockV3'),
    $(Route 'Run-Gate13R36hTelemetryProbeV2' 'Run-Gate13R36hTelemetryProbeV3'),
    $(Route 'Initialize-Gate13R36hLaneCopiesV2' 'Initialize-Gate13R36hLaneCopiesV3'),
    $(Route 'Run-Gate13R36hConcurrencyPilotV2' 'Run-Gate13R36hConcurrencyPilotV3'),
    $(Route 'Analyze-Gate13R36hConcurrencyPilotV2' 'Analyze-Gate13R36hConcurrencyPilotV3'),
    $(Route 'New-Gate13R36hPilotScheduleV2' 'New-Gate13R36hPilotScheduleV3'),
    $(Route 'Run-Gate13R36hStaticUnitV2' 'Run-Gate13R36hStaticUnitV3'),
    $(Route 'Run-Gate13R36hRetainedRegressionV2' 'Run-Gate13R36hRetainedRegressionV3'),
    $(Route 'Run-Gate13R36hVerificationV2' 'Run-Gate13R36hVerificationV3'),
    $(Route 'Run-Gate13R36hValidationOnlyPrePilotAuditV2' 'Run-Gate13R36hValidationOnlyPrePilotAuditV3'),
    $(Route 'Gate13R_36h_10pct_4Lane_Pilot_Plan.v2.json' 'Gate13R_36h_10pct_4Lane_Pilot_Plan.v3.json'),
    $(Route 'Gate13R_36h_10pct_4Lane_Pilot_Schedule.v2.json' 'Gate13R_36h_10pct_4Lane_Pilot_Schedule.v3.json'),
    $(Route 'Gate13R_36h_10pct_4Lane_Pilot_Schedule_Generation.v2.json' 'Gate13R_36h_10pct_4Lane_Pilot_Schedule_Generation.v3.json'),
    $(Route 'Gate13R_36h_10pct_4Lane_Provenance.v2.json' 'Gate13R_36h_10pct_4Lane_Provenance.v3.json'),
    $(Route 'Gate13R_36h_10pct_4Lane_PrePilot_Defect_Repair_Amendment.v2.json' 'Gate13R_36h_10pct_4Lane_PrePilot_Defect_Repair_Amendment.v3.json'),
    $(Route 'Research\Verification\Gate13R_36h_10pct_4Lane\v2' 'Research\Verification\Gate13R_36h_10pct_4Lane\v3'),
    $(Route 'Research\PilotRuns\Gate13R_36h_10pct_4Lane\v2' 'Research\PilotRuns\Gate13R_36h_10pct_4Lane\v3'),
    $(Route 'H:\DDM_Final_Project_Gate13R36H\v2' 'H:\DDM_Final_Project_Gate13R36H\v3'),
    $(Route 'gate13r-36h-10pct-four-lane-nonformal-pilot-plan-v2' 'gate13r-36h-10pct-four-lane-nonformal-pilot-plan-v3'),
    $(Route 'gate13r-36h-10pct-four-lane-nonformal-pilot-plan-v1' 'gate13r-36h-10pct-four-lane-nonformal-pilot-plan-v3'),
    $(Route "-v2'" "-v3'")
)

function New-DerivedFile([string]$SourceRelative,[string]$DestinationRelative,[object[]]$ExtraRoutes){
    $source=Join-Path $ProjectPath $SourceRelative
    $destination=Join-Path $ProjectPath $DestinationRelative
    $sourceText=[IO.File]::ReadAllText($source)
    $derived=$sourceText
    $applied=New-Object Collections.Generic.List[object]
    $routes=@($commonRoutes)+@($ExtraRoutes)
    foreach($route in $routes){
        $from=[string]$route.from;$to=[string]$route.to
        $count=Get-Count $derived $from
        if($count-gt0){
            $derived=$derived.Replace($from,$to)
            $applied.Add([pscustomobject][ordered]@{from=$from;to=$to;count=$count})
        }
    }
    if($applied.Count-lt1){throw "No v3 routes applied to $SourceRelative"}
    $tokens=$null;$parseErrors=$null
    [void][Management.Automation.Language.Parser]::ParseInput($derived,[ref]$tokens,[ref]$parseErrors)
    if(@($parseErrors).Count-ne0){throw "Derived parser failure in $DestinationRelative`: $(@($parseErrors|ForEach-Object Message)-join'; ')"}
    Write-CreateNewText $destination $derived
    $reverse=$derived
    for($i=$applied.Count-1;$i-ge0;$i--){$reverse=$reverse.Replace([string]$applied[$i].to,[string]$applied[$i].from)}
    $sourceHash=Get-Hash $source;$reverseHash=Get-TextHash $reverse
    if($reverseHash-ne$sourceHash){throw "Reverse transform mismatch: $DestinationRelative"}
    $derivations.Add([pscustomobject][ordered]@{sourceRelativePath=$SourceRelative;sourceSha256=$sourceHash;destinationRelativePath=$DestinationRelative;destinationSha256=Get-Hash $destination;routes=$applied.ToArray();reverseTransformSha256=$reverseHash;passed=$true})
}

$destinations=@(
    'Research\Gate13R36hConcurrencyPreparationV3.psm1',
    'Research\Run-Gate13R36hBlockV3.ps1',
    'Research\Run-Gate13R36hTelemetryProbeV3.ps1',
    'Research\Initialize-Gate13R36hLaneCopiesV3.ps1',
    'Research\Run-Gate13R36hConcurrencyPilotV3.ps1',
    'Research\Analyze-Gate13R36hConcurrencyPilotV3.ps1',
    'Research\Verification\New-Gate13R36hPilotScheduleV3.ps1',
    'Research\Verification\Run-Gate13R36hStaticUnitV3.ps1',
    'Research\Verification\Run-Gate13R36hRetainedRegressionV3.ps1',
    'Research\Verification\Run-Gate13R36hVerificationV3.ps1',
    'Research\Verification\Run-Gate13R36hValidationOnlyPrePilotAuditV3.ps1',
    'Research\Gate13R_36h_10pct_4Lane_Pilot_Plan.v3.json',
    'Research\Gate13R_36h_10pct_4Lane_Pilot_Schedule.v3.json',
    'Research\Gate13R_36h_10pct_4Lane_Pilot_Schedule_Generation.v3.json',
    'Research\Gate13R_36h_10pct_4Lane_Provenance.v3.json',
    'Research\Gate13R_36h_10pct_4Lane_Attempt3_Derivation_Receipt.v1.json'
)
foreach($relative in $destinations){if(Test-Path -LiteralPath (Join-Path $ProjectPath $relative)){throw "Create-new v3 target already exists: $relative"}}
foreach($root in @('Research\Verification\Gate13R_36h_10pct_4Lane\v3','Research\PilotRuns\Gate13R_36h_10pct_4Lane\v3','H:\DDM_Final_Project_Gate13R36H\v3')){
    $resolvedRoot=if([IO.Path]::IsPathRooted($root)){$root}else{Join-Path $ProjectPath $root}
    if(Test-Path -LiteralPath $resolvedRoot){throw "Create-new v3 root already exists: $root"}
}
if(Test-Path -LiteralPath (Join-Path $ProjectPath 'Research\FormalRuns\Gate13R_36h_10pct_4Lane\v1')){throw 'Forbidden formal root exists.'}

$frozen=@(
    'Research\Gate13R_36h_10pct_4Lane_Pilot_Plan.v2.json',
    'Research\Gate13R_36h_10pct_4Lane_Pilot_Schedule.v2.json',
    'Research\Gate13R_36h_10pct_4Lane_Pilot_Schedule_Generation.v2.json',
    'Research\Gate13R_36h_10pct_4Lane_Provenance.v2.json',
    'Research\Gate13R_36h_10pct_4Lane_Attempt2_Derivation_Receipt.v1.json',
    'Research\Verification\Gate13R_36h_10pct_4Lane_PreImplementation\v7\StaticUnitV2\summary.json',
    'Research\Verification\Gate13R_36h_10pct_4Lane_PreImplementation\v7\StaticUnitV2\failure-receipt.json',
    'Research\Verification\Gate13R_36h_10pct_4Lane_PreImplementation\v7\StaticUnitV2\partial-output-manifest.json',
    'Research\Verification\Gate13R_36h_10pct_4Lane_PreImplementation\v7\StaticUnitV2\checkpoint.json',
    'Research\Verification\Gate13R_36h_10pct_4Lane\v1\execution-receipt.json',
    'Research\Verification\Gate13R_36h_10pct_4Lane\v1\verification-checkpoint.json',
    'Research\Verification\Gate13R_36h_10pct_4Lane\v1\failure-receipt.json',
    'Research\Verification\Gate13R_36h_10pct_4Lane\v1\partial-output-manifest.json'
)
$frozenHashes=@{};foreach($relative in $frozen){$path=Join-Path $ProjectPath $relative;if(-not(Test-Path -LiteralPath $path -PathType Leaf)){throw "Frozen evidence missing: $relative"};$frozenHashes[$relative]=Get-Hash $path}

$map=@(
    @('Research\Gate13R36hConcurrencyPreparationV2.psm1','Research\Gate13R36hConcurrencyPreparationV3.psm1'),
    @('Research\Run-Gate13R36hBlockV2.ps1','Research\Run-Gate13R36hBlockV3.ps1'),
    @('Research\Run-Gate13R36hTelemetryProbeV2.ps1','Research\Run-Gate13R36hTelemetryProbeV3.ps1'),
    @('Research\Initialize-Gate13R36hLaneCopiesV2.ps1','Research\Initialize-Gate13R36hLaneCopiesV3.ps1'),
    @('Research\Run-Gate13R36hConcurrencyPilotV2.ps1','Research\Run-Gate13R36hConcurrencyPilotV3.ps1'),
    @('Research\Analyze-Gate13R36hConcurrencyPilotV2.ps1','Research\Analyze-Gate13R36hConcurrencyPilotV3.ps1'),
    @('Research\Verification\New-Gate13R36hPilotScheduleV2.ps1','Research\Verification\New-Gate13R36hPilotScheduleV3.ps1'),
    @('Research\Verification\Run-Gate13R36hStaticUnitV2.ps1','Research\Verification\Run-Gate13R36hStaticUnitV3.ps1'),
    @('Research\Verification\Run-Gate13R36hRetainedRegressionV2.ps1','Research\Verification\Run-Gate13R36hRetainedRegressionV3.ps1'),
    @('Research\Verification\Run-Gate13R36hVerificationV2.ps1','Research\Verification\Run-Gate13R36hVerificationV3.ps1'),
    @('Research\Verification\Run-Gate13R36hValidationOnlyPrePilotAuditV2.ps1','Research\Verification\Run-Gate13R36hValidationOnlyPrePilotAuditV3.ps1')
)
foreach($pair in $map){
    $extra=@()
    if([string]$pair[0]-eq'Research\Verification\Run-Gate13R36hStaticUnitV2.ps1'){$extra=@($(Route 'New-Gate13R36hPilotScheduleV1.ps1' 'New-Gate13R36hPilotScheduleV3.ps1'))}
    New-DerivedFile -SourceRelative ([string]$pair[0]) -DestinationRelative ([string]$pair[1]) -ExtraRoutes $extra
}

$amendmentPath=Join-Path $ProjectPath 'Research\Gate13R_36h_10pct_4Lane_PrePilot_Defect_Repair_Amendment.v3.json'
$planV2Path=Join-Path $ProjectPath 'Research\Gate13R_36h_10pct_4Lane_Pilot_Plan.v2.json'
$planV3Path=Join-Path $ProjectPath 'Research\Gate13R_36h_10pct_4Lane_Pilot_Plan.v3.json'
$plan=Get-Content -LiteralPath $planV2Path -Raw -Encoding UTF8|ConvertFrom-Json
$plan.planId='gate13r-36h-10pct-four-lane-nonformal-pilot-plan-v3'
$plan.pilotAttempt=3
$plan.paths.pilotRootRelativePath='Research/PilotRuns/Gate13R_36h_10pct_4Lane/v3'
$plan.paths.verificationRootRelativePath='Research/Verification/Gate13R_36h_10pct_4Lane/v3'
$plan.paths.cloneRootAbsolutePath='H:/DDM_Final_Project_Gate13R36H/v3'
foreach($lane in @($plan.lanes)){$lane.projectPath=([string]$lane.projectPath).Replace('/v2/','/v3/')}
$plan.upstreamHashes.prePilotDefectRepairAmendment=Get-Hash $amendmentPath
$plan.upstreamHashes|Add-Member -NotePropertyName attempt2StaticFailureSummary -NotePropertyValue (Get-Hash (Join-Path $ProjectPath 'Research\Verification\Gate13R_36h_10pct_4Lane_PreImplementation\v7\StaticUnitV2\summary.json'))
Write-CreateNewJson $planV3Path $plan 60
& (Join-Path $ProjectPath 'Research\Verification\New-Gate13R36hPilotScheduleV3.ps1') -ProjectPath $ProjectPath|Out-Null

function Bound([string]$RelativePath){$path=Join-Path $ProjectPath $RelativePath;return [ordered]@{relativePath=$RelativePath.Replace('\','/');sha256=Get-Hash $path;bytes=[long](Get-Item -LiteralPath $path).Length}}
$provenancePath=Join-Path $ProjectPath 'Research\Gate13R_36h_10pct_4Lane_Provenance.v3.json'
$provenance=[ordered]@{
    schemaVersion=3;provenanceId='gate13r-36h-10pct-four-isolated-editor-lanes-provenance-v3';createdAtUtc=[DateTime]::UtcNow.ToString('o');executionDesignId='gate13r-36h-10pct-four-isolated-editor-lanes-v1';status='NON-FORMAL / EXCLUDED-FROM-FORMAL-ANALYSIS';formalCampaign=$false;formalExecutionAuthorized=$false;pilotExecutionAuthorizedCount=1;pilotExecutionConsumedCount=0;automaticPilotRetryAuthorized=$false;sameAttemptResumeAuthorized=$false
    authorization=Bound 'Research\Gate13R_36h_Redesign_Pilot_Authorization.v1.json';specification=Bound 'Research\Gate13R_36h_10pct_4Lane_Redesign_Specification.v1.md';testDesign=Bound 'Research\Gate13R_36h_10pct_4Lane_Test_Design.v1.md';readinessAmendment=Bound 'Research\Gate13R_36h_10pct_4Lane_Readiness_Amendment.v1.json';executionAuthorization=Bound 'Research\Gate13R_36h_10pct_4Lane_PrePilot_Defect_Repair_Amendment.v3.json';config=Bound 'Research\Gate13R_36h_10pct_4Lane_Pilot_Plan.v3.json';schedule=Bound 'Research\Gate13R_36h_10pct_4Lane_Pilot_Schedule.v3.json';scheduleGeneration=Bound 'Research\Gate13R_36h_10pct_4Lane_Pilot_Schedule_Generation.v3.json';preservationBaseline=Bound 'Research\Gate13R_36h_10pct_4Lane_PreWrite_Preservation_Baseline.v1.json';commandDerivation=Bound 'Research\Gate13R_36h_Concurrency_Command_Derivation.v1.json';attempt2DerivationReceipt=Bound 'Research\Gate13R_36h_10pct_4Lane_Attempt2_Derivation_Receipt.v1.json';attempt2Plan=Bound 'Research\Gate13R_36h_10pct_4Lane_Pilot_Plan.v2.json';attempt2Provenance=Bound 'Research\Gate13R_36h_10pct_4Lane_Provenance.v2.json';attempt2StaticFailureSummary=Bound 'Research\Verification\Gate13R_36h_10pct_4Lane_PreImplementation\v7\StaticUnitV2\summary.json';attempt2StaticFailureReceipt=Bound 'Research\Verification\Gate13R_36h_10pct_4Lane_PreImplementation\v7\StaticUnitV2\failure-receipt.json';attempt2StaticCheckpoint=Bound 'Research\Verification\Gate13R_36h_10pct_4Lane_PreImplementation\v7\StaticUnitV2\checkpoint.json';attempt3DerivationGenerator=Bound 'Research\Verification\New-Gate13R36hAttempt3ArtifactsV1.ps1';unityCommand=Bound 'Assets\_Scripts\Research\Editor\Gate13R36hConcurrencyBatchCommandV1.cs';preparationModule=Bound 'Research\Gate13R36hConcurrencyPreparationV3.psm1';blockRunner=Bound 'Research\Run-Gate13R36hBlockV3.ps1';telemetryRunner=Bound 'Research\Run-Gate13R36hTelemetryProbeV3.ps1';laneCopyInitializer=Bound 'Research\Initialize-Gate13R36hLaneCopiesV3.ps1';pilotOrchestrator=Bound 'Research\Run-Gate13R36hConcurrencyPilotV3.ps1';pilotAnalyzer=Bound 'Research\Analyze-Gate13R36hConcurrencyPilotV3.ps1';scheduleGenerator=Bound 'Research\Verification\New-Gate13R36hPilotScheduleV3.ps1';compileRunner=Bound 'Research\Verification\Run-Gate13R36hCompileV1.ps1';staticUnitRunner=Bound 'Research\Verification\Run-Gate13R36hStaticUnitV3.ps1';retainedRegressionRunner=Bound 'Research\Verification\Run-Gate13R36hRetainedRegressionV3.ps1';verificationRunner=Bound 'Research\Verification\Run-Gate13R36hVerificationV3.ps1';validationOnlyAuditRunner=Bound 'Research\Verification\Run-Gate13R36hValidationOnlyPrePilotAuditV3.ps1';gate11BundleManifest=Bound 'Research\FormalScenarios\Gate11R_5pct\v1\bundle-manifest.json';attempt1FailureReceipt=Bound 'Research\Verification\Gate13R_36h_10pct_4Lane\v1\failure-receipt.json';attempt1Checkpoint=Bound 'Research\Verification\Gate13R_36h_10pct_4Lane\v1\verification-checkpoint.json'
    unityEditor=[ordered]@{absolutePath='H:/UnityEditor/2022.3.30f1c1/Editor/Unity.exe';productVersion='2022.3.30f1c1_a6dc00fbe362';sha256='0a69d14cbe2ca82d0a6168da8156d9e0dd138a6b7d0260dcdea31fd3957ca9cf'}
    paths=[ordered]@{verificationRoot='Research/Verification/Gate13R_36h_10pct_4Lane/v3';pilotRoot='Research/PilotRuns/Gate13R_36h_10pct_4Lane/v3';cloneRoot='H:/DDM_Final_Project_Gate13R36H/v3';reservedFormalRoot='Research/FormalRuns/Gate13R_36h_10pct_4Lane/v1'}
}
Write-CreateNewJson $provenancePath $provenance 70

foreach($relative in $frozen){if((Get-Hash (Join-Path $ProjectPath $relative))-ne[string]$frozenHashes[$relative]){throw "Frozen v1/v2 evidence changed during v3 derivation: $relative"}}
$receipt=[ordered]@{schemaVersion=1;receiptKind='gate13r-36h-prepilot-attempt3-mechanical-derivation-v1';createdAtUtc=[DateTime]::UtcNow.ToString('o');amendmentRelativePath='Research/Gate13R_36h_10pct_4Lane_PrePilot_Defect_Repair_Amendment.v3.json';amendmentSha256=Get-Hash $amendmentPath;derivations=$derivations.ToArray();planV2Sha256=Get-Hash $planV2Path;planV3Sha256=Get-Hash $planV3Path;scheduleV3Sha256=Get-Hash (Join-Path $ProjectPath 'Research\Gate13R_36h_10pct_4Lane_Pilot_Schedule.v3.json');provenanceV3Sha256=Get-Hash $provenancePath;attempt2EvidencePreserved=$true;pilotRootCreated=$false;formalCampaign=$false;passed=$true}
Write-CreateNewJson (Join-Path $ProjectPath 'Research\Gate13R_36h_10pct_4Lane_Attempt3_Derivation_Receipt.v1.json') $receipt 90
$receipt|ConvertTo-Json -Depth 8
