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
    $(Route 'Gate13R36hConcurrencyPreparationV2' 'Gate13R36hConcurrencyPreparationV4'),
    $(Route 'Run-Gate13R36hBlockV2' 'Run-Gate13R36hBlockV4'),
    $(Route 'Run-Gate13R36hTelemetryProbeV2' 'Run-Gate13R36hTelemetryProbeV4'),
    $(Route 'Initialize-Gate13R36hLaneCopiesV2' 'Initialize-Gate13R36hLaneCopiesV4'),
    $(Route 'Run-Gate13R36hConcurrencyPilotV2' 'Run-Gate13R36hConcurrencyPilotV4'),
    $(Route 'Analyze-Gate13R36hConcurrencyPilotV2' 'Analyze-Gate13R36hConcurrencyPilotV4'),
    $(Route 'New-Gate13R36hPilotScheduleV2' 'New-Gate13R36hPilotScheduleV4'),
    $(Route 'Run-Gate13R36hStaticUnitV2' 'Run-Gate13R36hStaticUnitV4'),
    $(Route 'Run-Gate13R36hRetainedRegressionV2' 'Run-Gate13R36hRetainedRegressionV4'),
    $(Route 'Run-Gate13R36hVerificationV2' 'Run-Gate13R36hVerificationV4'),
    $(Route 'Run-Gate13R36hValidationOnlyPrePilotAuditV2' 'Run-Gate13R36hValidationOnlyPrePilotAuditV4'),
    $(Route 'Gate13R_36h_10pct_4Lane_Pilot_Plan.v2.json' 'Gate13R_36h_10pct_4Lane_Pilot_Plan.v4.json'),
    $(Route 'Gate13R_36h_10pct_4Lane_Pilot_Schedule.v2.json' 'Gate13R_36h_10pct_4Lane_Pilot_Schedule.v4.json'),
    $(Route 'Gate13R_36h_10pct_4Lane_Pilot_Schedule_Generation.v2.json' 'Gate13R_36h_10pct_4Lane_Pilot_Schedule_Generation.v4.json'),
    $(Route 'Gate13R_36h_10pct_4Lane_Provenance.v2.json' 'Gate13R_36h_10pct_4Lane_Provenance.v4.json'),
    $(Route 'Gate13R_36h_10pct_4Lane_PrePilot_Defect_Repair_Amendment.v2.json' 'Gate13R_36h_10pct_4Lane_PrePilot_Defect_Repair_Amendment.v4.json'),
    $(Route 'Research\Verification\Gate13R_36h_10pct_4Lane\v2' 'Research\Verification\Gate13R_36h_10pct_4Lane\v4'),
    $(Route 'Research\PilotRuns\Gate13R_36h_10pct_4Lane\v2' 'Research\PilotRuns\Gate13R_36h_10pct_4Lane\v4'),
    $(Route 'H:\DDM_Final_Project_Gate13R36H\v2' 'H:\DDM_Final_Project_Gate13R36H\v4'),
    $(Route 'gate13r-36h-10pct-four-lane-nonformal-pilot-plan-v2' 'gate13r-36h-10pct-four-lane-nonformal-pilot-plan-v4'),
    $(Route 'gate13r-36h-10pct-four-lane-nonformal-pilot-plan-v1' 'gate13r-36h-10pct-four-lane-nonformal-pilot-plan-v4'),
    $(Route 'gate13r-36h-four-lane-block-wrapper-summary-v2' 'gate13r-36h-four-lane-block-wrapper-summary-v4'),
    $(Route 'gate13r-36h-four-lane-block-wrapper-failure-v2' 'gate13r-36h-four-lane-block-wrapper-failure-v4'),
    $(Route 'gate13r-36h-four-lane-telemetry-wrapper-v2' 'gate13r-36h-four-lane-telemetry-wrapper-v4'),
    $(Route 'gate13r-36h-isolated-lane-copy-manifest-v2' 'gate13r-36h-isolated-lane-copy-manifest-v4'),
    $(Route 'gate13r-36h-four-isolated-project-copies-v2' 'gate13r-36h-four-isolated-project-copies-v4'),
    $(Route 'gate13r-36h-four-lane-nonformal-pilot-execution-receipt-v2' 'gate13r-36h-four-lane-nonformal-pilot-execution-receipt-v4'),
    $(Route 'gate13r-36h-four-lane-nonformal-pilot-checkpoint-v2' 'gate13r-36h-four-lane-nonformal-pilot-checkpoint-v4'),
    $(Route 'gate13r-36h-four-lane-nonformal-pilot-execution-manifest-v2' 'gate13r-36h-four-lane-nonformal-pilot-execution-manifest-v4'),
    $(Route 'gate13r-36h-four-lane-nonformal-pilot-failure-v2' 'gate13r-36h-four-lane-nonformal-pilot-failure-v4'),
    $(Route 'gate13r-36h-four-lane-pilot-partial-output-manifest-v1' 'gate13r-36h-four-lane-pilot-partial-output-manifest-v4'),
    $(Route 'gate13r-36h-four-lane-post-pilot-readiness-v2' 'gate13r-36h-four-lane-post-pilot-readiness-v4'),
    $(Route 'gate13r-36h-four-lane-nonformal-pilot-manifest-v2' 'gate13r-36h-four-lane-nonformal-pilot-manifest-v4'),
    $(Route 'gate13r-36h-10pct-four-lane-nonformal-pilot-schedule-v2' 'gate13r-36h-10pct-four-lane-nonformal-pilot-schedule-v4'),
    $(Route 'gate13r-36h-four-lane-pilot-schedule-generation-v2' 'gate13r-36h-four-lane-pilot-schedule-generation-v4'),
    $(Route 'gate13r-36h-four-lane-static-unit-summary-v2' 'gate13r-36h-four-lane-static-unit-summary-v4'),
    $(Route 'gate13r-36h-retained-regression-mechanical-file-scope-derivation-v2' 'gate13r-36h-retained-regression-mechanical-file-scope-derivation-v4'),
    $(Route 'gate13r-36h-four-lane-verification-checkpoint-v2' 'gate13r-36h-four-lane-verification-checkpoint-v4'),
    $(Route 'gate13r-36h-four-lane-nonexecuting-verification-receipt-v2' 'gate13r-36h-four-lane-nonexecuting-verification-receipt-v4'),
    $(Route 'gate13r-36h-four-lane-block-verification-v2' 'gate13r-36h-four-lane-block-verification-v4'),
    $(Route 'gate13r-36h-verification-partial-output-manifest-v2' 'gate13r-36h-verification-partial-output-manifest-v4'),
    $(Route 'gate13r-36h-nonexecuting-verification-failure-v2' 'gate13r-36h-nonexecuting-verification-failure-v4'),
    $(Route 'gate13r-36h-four-lane-validation-only-pre-pilot-audit-v2' 'gate13r-36h-four-lane-validation-only-pre-pilot-audit-v4')
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
    if($applied.Count-lt1){throw "No v4 routes applied to $SourceRelative"}
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
    'Research\Gate13R36hConcurrencyPreparationV4.psm1',
    'Research\Run-Gate13R36hBlockV4.ps1',
    'Research\Run-Gate13R36hTelemetryProbeV4.ps1',
    'Research\Initialize-Gate13R36hLaneCopiesV4.ps1',
    'Research\Run-Gate13R36hConcurrencyPilotV4.ps1',
    'Research\Analyze-Gate13R36hConcurrencyPilotV4.ps1',
    'Research\Verification\New-Gate13R36hPilotScheduleV4.ps1',
    'Research\Verification\Run-Gate13R36hStaticUnitV4.ps1',
    'Research\Verification\Run-Gate13R36hRetainedRegressionV4.ps1',
    'Research\Verification\Run-Gate13R36hVerificationV4.ps1',
    'Research\Verification\Run-Gate13R36hValidationOnlyPrePilotAuditV4.ps1',
    'Research\Gate13R_36h_10pct_4Lane_Pilot_Plan.v4.json',
    'Research\Gate13R_36h_10pct_4Lane_Pilot_Schedule.v4.json',
    'Research\Gate13R_36h_10pct_4Lane_Pilot_Schedule_Generation.v4.json',
    'Research\Gate13R_36h_10pct_4Lane_Provenance.v4.json',
    'Research\Gate13R_36h_10pct_4Lane_Attempt4_Derivation_Receipt.v1.json'
)
foreach($relative in $destinations){if(Test-Path -LiteralPath (Join-Path $ProjectPath $relative)){throw "Create-new v4 target already exists: $relative"}}
foreach($root in @('Research\Verification\Gate13R_36h_10pct_4Lane\v4','Research\PilotRuns\Gate13R_36h_10pct_4Lane\v4','H:\DDM_Final_Project_Gate13R36H\v4')){
    $resolvedRoot=if([IO.Path]::IsPathRooted($root)){$root}else{Join-Path $ProjectPath $root}
    if(Test-Path -LiteralPath $resolvedRoot){throw "Create-new v4 root already exists: $root"}
}
if(Test-Path -LiteralPath (Join-Path $ProjectPath 'Research\FormalRuns\Gate13R_36h_10pct_4Lane\v1')){throw 'Forbidden formal root exists.'}

$frozen=@(
    'Research\Gate13R_36h_10pct_4Lane_PrePilot_Defect_Repair_Amendment.v3.json',
    'Research\Gate13R_36h_10pct_4Lane_Attempt3_Derivation_Attempt1_Failure.v1.json',
    'Research\Gate13R_36h_10pct_4Lane_Attempt3_Derivation_Attempt2_Failure.v1.json',
    'Research\Gate13R_36h_10pct_4Lane_Attempt3_Derivation_Attempt2_Partial_Manifest.v1.json',
    'Research\Gate13R36hConcurrencyPreparationV3.psm1',
    'Research\Initialize-Gate13R36hLaneCopiesV3.ps1',
    'Research\Run-Gate13R36hBlockV3.ps1',
    'Research\Run-Gate13R36hConcurrencyPilotV3.ps1',
    'Research\Run-Gate13R36hTelemetryProbeV3.ps1',
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
    @('Research\Gate13R36hConcurrencyPreparationV2.psm1','Research\Gate13R36hConcurrencyPreparationV4.psm1'),
    @('Research\Run-Gate13R36hBlockV2.ps1','Research\Run-Gate13R36hBlockV4.ps1'),
    @('Research\Run-Gate13R36hTelemetryProbeV2.ps1','Research\Run-Gate13R36hTelemetryProbeV4.ps1'),
    @('Research\Initialize-Gate13R36hLaneCopiesV2.ps1','Research\Initialize-Gate13R36hLaneCopiesV4.ps1'),
    @('Research\Run-Gate13R36hConcurrencyPilotV2.ps1','Research\Run-Gate13R36hConcurrencyPilotV4.ps1'),
    @('Research\Analyze-Gate13R36hConcurrencyPilotV2.ps1','Research\Analyze-Gate13R36hConcurrencyPilotV4.ps1'),
    @('Research\Verification\New-Gate13R36hPilotScheduleV2.ps1','Research\Verification\New-Gate13R36hPilotScheduleV4.ps1'),
    @('Research\Verification\Run-Gate13R36hStaticUnitV2.ps1','Research\Verification\Run-Gate13R36hStaticUnitV4.ps1'),
    @('Research\Verification\Run-Gate13R36hRetainedRegressionV2.ps1','Research\Verification\Run-Gate13R36hRetainedRegressionV4.ps1'),
    @('Research\Verification\Run-Gate13R36hVerificationV2.ps1','Research\Verification\Run-Gate13R36hVerificationV4.ps1'),
    @('Research\Verification\Run-Gate13R36hValidationOnlyPrePilotAuditV2.ps1','Research\Verification\Run-Gate13R36hValidationOnlyPrePilotAuditV4.ps1')
)
foreach($pair in $map){
    $extra=@()
    if([string]$pair[0]-eq'Research\Verification\Run-Gate13R36hStaticUnitV2.ps1'){$extra=@($(Route 'New-Gate13R36hPilotScheduleV1.ps1' 'New-Gate13R36hPilotScheduleV4.ps1'))}
    New-DerivedFile -SourceRelative ([string]$pair[0]) -DestinationRelative ([string]$pair[1]) -ExtraRoutes $extra
}

$amendmentPath=Join-Path $ProjectPath 'Research\Gate13R_36h_10pct_4Lane_PrePilot_Defect_Repair_Amendment.v4.json'
$planV2Path=Join-Path $ProjectPath 'Research\Gate13R_36h_10pct_4Lane_Pilot_Plan.v2.json'
$planV4Path=Join-Path $ProjectPath 'Research\Gate13R_36h_10pct_4Lane_Pilot_Plan.v4.json'
$plan=Get-Content -LiteralPath $planV2Path -Raw -Encoding UTF8|ConvertFrom-Json
$plan.planId='gate13r-36h-10pct-four-lane-nonformal-pilot-plan-v4'
$plan.pilotAttempt=4
$plan.paths.pilotRootRelativePath='Research/PilotRuns/Gate13R_36h_10pct_4Lane/v4'
$plan.paths.verificationRootRelativePath='Research/Verification/Gate13R_36h_10pct_4Lane/v4'
$plan.paths.cloneRootAbsolutePath='H:/DDM_Final_Project_Gate13R36H/v4'
foreach($lane in @($plan.lanes)){$lane.projectPath=([string]$lane.projectPath).Replace('/v2/','/v4/')}
$plan.upstreamHashes.prePilotDefectRepairAmendment=Get-Hash $amendmentPath
$plan.upstreamHashes|Add-Member -NotePropertyName attempt2StaticFailureSummary -NotePropertyValue (Get-Hash (Join-Path $ProjectPath 'Research\Verification\Gate13R_36h_10pct_4Lane_PreImplementation\v7\StaticUnitV2\summary.json'))
$plan.upstreamHashes|Add-Member -NotePropertyName attempt3DerivationFailure -NotePropertyValue (Get-Hash (Join-Path $ProjectPath 'Research\Gate13R_36h_10pct_4Lane_Attempt3_Derivation_Attempt2_Failure.v1.json'))
Write-CreateNewJson $planV4Path $plan 60
& (Join-Path $ProjectPath 'Research\Verification\New-Gate13R36hPilotScheduleV4.ps1') -ProjectPath $ProjectPath|Out-Null

function Bound([string]$RelativePath){$path=Join-Path $ProjectPath $RelativePath;return [ordered]@{relativePath=$RelativePath.Replace('\','/');sha256=Get-Hash $path;bytes=[long](Get-Item -LiteralPath $path).Length}}
$provenancePath=Join-Path $ProjectPath 'Research\Gate13R_36h_10pct_4Lane_Provenance.v4.json'
$provenance=[ordered]@{
    schemaVersion=3;provenanceId='gate13r-36h-10pct-four-isolated-editor-lanes-provenance-v4';createdAtUtc=[DateTime]::UtcNow.ToString('o');executionDesignId='gate13r-36h-10pct-four-isolated-editor-lanes-v1';status='NON-FORMAL / EXCLUDED-FROM-FORMAL-ANALYSIS';formalCampaign=$false;formalExecutionAuthorized=$false;pilotExecutionAuthorizedCount=1;pilotExecutionConsumedCount=0;automaticPilotRetryAuthorized=$false;sameAttemptResumeAuthorized=$false
    authorization=Bound 'Research\Gate13R_36h_Redesign_Pilot_Authorization.v1.json';specification=Bound 'Research\Gate13R_36h_10pct_4Lane_Redesign_Specification.v1.md';testDesign=Bound 'Research\Gate13R_36h_10pct_4Lane_Test_Design.v1.md';readinessAmendment=Bound 'Research\Gate13R_36h_10pct_4Lane_Readiness_Amendment.v1.json';executionAuthorization=Bound 'Research\Gate13R_36h_10pct_4Lane_PrePilot_Defect_Repair_Amendment.v4.json';config=Bound 'Research\Gate13R_36h_10pct_4Lane_Pilot_Plan.v4.json';schedule=Bound 'Research\Gate13R_36h_10pct_4Lane_Pilot_Schedule.v4.json';scheduleGeneration=Bound 'Research\Gate13R_36h_10pct_4Lane_Pilot_Schedule_Generation.v4.json';preservationBaseline=Bound 'Research\Gate13R_36h_10pct_4Lane_PreWrite_Preservation_Baseline.v1.json';commandDerivation=Bound 'Research\Gate13R_36h_Concurrency_Command_Derivation.v1.json';attempt2DerivationReceipt=Bound 'Research\Gate13R_36h_10pct_4Lane_Attempt2_Derivation_Receipt.v1.json';attempt2Plan=Bound 'Research\Gate13R_36h_10pct_4Lane_Pilot_Plan.v2.json';attempt2Provenance=Bound 'Research\Gate13R_36h_10pct_4Lane_Provenance.v2.json';attempt2StaticFailureSummary=Bound 'Research\Verification\Gate13R_36h_10pct_4Lane_PreImplementation\v7\StaticUnitV2\summary.json';attempt2StaticFailureReceipt=Bound 'Research\Verification\Gate13R_36h_10pct_4Lane_PreImplementation\v7\StaticUnitV2\failure-receipt.json';attempt2StaticCheckpoint=Bound 'Research\Verification\Gate13R_36h_10pct_4Lane_PreImplementation\v7\StaticUnitV2\checkpoint.json';attempt3Amendment=Bound 'Research\Gate13R_36h_10pct_4Lane_PrePilot_Defect_Repair_Amendment.v3.json';attempt3PrewriteFailure=Bound 'Research\Gate13R_36h_10pct_4Lane_Attempt3_Derivation_Attempt1_Failure.v1.json';attempt3ReverseFailure=Bound 'Research\Gate13R_36h_10pct_4Lane_Attempt3_Derivation_Attempt2_Failure.v1.json';attempt3PartialManifest=Bound 'Research\Gate13R_36h_10pct_4Lane_Attempt3_Derivation_Attempt2_Partial_Manifest.v1.json';attempt4GeneratorBuilder=Bound 'Research\Verification\New-Gate13R36hAttempt4GeneratorV1.ps1';attempt4GeneratorDerivationReceipt=Bound 'Research\Gate13R_36h_10pct_4Lane_Attempt4_Generator_Derivation_Receipt.v1.json';attempt4DerivationGenerator=Bound 'Research\Verification\New-Gate13R36hAttempt4ArtifactsV1.ps1';unityCommand=Bound 'Assets\_Scripts\Research\Editor\Gate13R36hConcurrencyBatchCommandV1.cs';preparationModule=Bound 'Research\Gate13R36hConcurrencyPreparationV4.psm1';blockRunner=Bound 'Research\Run-Gate13R36hBlockV4.ps1';telemetryRunner=Bound 'Research\Run-Gate13R36hTelemetryProbeV4.ps1';laneCopyInitializer=Bound 'Research\Initialize-Gate13R36hLaneCopiesV4.ps1';pilotOrchestrator=Bound 'Research\Run-Gate13R36hConcurrencyPilotV4.ps1';pilotAnalyzer=Bound 'Research\Analyze-Gate13R36hConcurrencyPilotV4.ps1';scheduleGenerator=Bound 'Research\Verification\New-Gate13R36hPilotScheduleV4.ps1';compileRunner=Bound 'Research\Verification\Run-Gate13R36hCompileV1.ps1';staticUnitRunner=Bound 'Research\Verification\Run-Gate13R36hStaticUnitV4.ps1';retainedRegressionRunner=Bound 'Research\Verification\Run-Gate13R36hRetainedRegressionV4.ps1';verificationRunner=Bound 'Research\Verification\Run-Gate13R36hVerificationV4.ps1';validationOnlyAuditRunner=Bound 'Research\Verification\Run-Gate13R36hValidationOnlyPrePilotAuditV4.ps1';gate11BundleManifest=Bound 'Research\FormalScenarios\Gate11R_5pct\v1\bundle-manifest.json';attempt1FailureReceipt=Bound 'Research\Verification\Gate13R_36h_10pct_4Lane\v1\failure-receipt.json';attempt1Checkpoint=Bound 'Research\Verification\Gate13R_36h_10pct_4Lane\v1\verification-checkpoint.json'
    unityEditor=[ordered]@{absolutePath='H:/UnityEditor/2022.3.30f1c1/Editor/Unity.exe';productVersion='2022.3.30f1c1_a6dc00fbe362';sha256='0a69d14cbe2ca82d0a6168da8156d9e0dd138a6b7d0260dcdea31fd3957ca9cf'}
    paths=[ordered]@{verificationRoot='Research/Verification/Gate13R_36h_10pct_4Lane/v4';pilotRoot='Research/PilotRuns/Gate13R_36h_10pct_4Lane/v4';cloneRoot='H:/DDM_Final_Project_Gate13R36H/v4';reservedFormalRoot='Research/FormalRuns/Gate13R_36h_10pct_4Lane/v1'}
}
Write-CreateNewJson $provenancePath $provenance 70

foreach($relative in $frozen){if((Get-Hash (Join-Path $ProjectPath $relative))-ne[string]$frozenHashes[$relative]){throw "Frozen v1/v2 evidence changed during v4 derivation: $relative"}}
$receipt=[ordered]@{schemaVersion=1;receiptKind='gate13r-36h-prepilot-attempt4-mechanical-derivation-v1';createdAtUtc=[DateTime]::UtcNow.ToString('o');amendmentRelativePath='Research/Gate13R_36h_10pct_4Lane_PrePilot_Defect_Repair_Amendment.v4.json';amendmentSha256=Get-Hash $amendmentPath;derivations=$derivations.ToArray();planV2Sha256=Get-Hash $planV2Path;planV4Sha256=Get-Hash $planV4Path;scheduleV4Sha256=Get-Hash (Join-Path $ProjectPath 'Research\Gate13R_36h_10pct_4Lane_Pilot_Schedule.v4.json');provenanceV4Sha256=Get-Hash $provenancePath;attempt2EvidencePreserved=$true;pilotRootCreated=$false;formalCampaign=$false;passed=$true}
Write-CreateNewJson (Join-Path $ProjectPath 'Research\Gate13R_36h_10pct_4Lane_Attempt4_Derivation_Receipt.v1.json') $receipt 90
$receipt|ConvertTo-Json -Depth 8
