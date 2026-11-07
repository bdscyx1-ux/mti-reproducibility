[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$ProjectPath)

$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$ProjectPath=[IO.Path]::GetFullPath($ProjectPath)
$utf8=New-Object Text.UTF8Encoding($false,$true)
function Get-Hash([string]$Path){return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()}
function Write-CreateNewText([string]$Path,[string]$Text){if(Test-Path -LiteralPath $Path){throw "Create-new target exists: $Path"};$parent=Split-Path -Parent $Path;if(-not(Test-Path -LiteralPath $parent -PathType Container)){New-Item -ItemType Directory -Path $parent|Out-Null};[IO.File]::WriteAllText($Path,$Text,$utf8)}
function Write-CreateNewJson([string]$Path,$Value,[int]$Depth=60){$text=($Value|ConvertTo-Json -Depth $Depth).Replace("`r`n","`n").Replace("`r","`n");if(-not$text.EndsWith("`n")){$text+="`n"};Write-CreateNewText $Path $text}
function Get-Count([string]$Text,[string]$Needle){if([string]::IsNullOrEmpty($Needle)){return 0};return [regex]::Matches($Text,[regex]::Escape($Needle)).Count}
$derivations=New-Object Collections.Generic.List[object]
function New-DerivedFile([string]$SourceRelative,[string]$DestinationRelative,[object[]]$Replacements){$source=Join-Path $ProjectPath $SourceRelative;$destination=Join-Path $ProjectPath $DestinationRelative;$sourceText=[IO.File]::ReadAllText($source);$derived=$sourceText;$routes=New-Object Collections.Generic.List[object];foreach($replacement in $Replacements){$from=[string]$replacement.from;$to=[string]$replacement.to;$count=Get-Count $derived $from;if($count-lt1){throw "Mechanical route not found in $SourceRelative`: $from"};if((Get-Count $derived $to)-gt0){throw "Mechanical target already exists in source/intermediate $SourceRelative`: $to"};$derived=$derived.Replace($from,$to);$routes.Add([pscustomobject][ordered]@{from=$from;to=$to;count=$count})};Write-CreateNewText $destination $derived;$reverse=$derived;for($i=$Replacements.Count-1;$i-ge0;$i--){$reverse=$reverse.Replace([string]$Replacements[$i].to,[string]$Replacements[$i].from)};$reverseHash=[BitConverter]::ToString(([Security.Cryptography.SHA256]::Create()).ComputeHash($utf8.GetBytes($reverse))).Replace('-','').ToLowerInvariant();$sourceHash=Get-Hash $source;if($reverseHash-ne$sourceHash){throw "Reverse transform mismatch: $DestinationRelative"};$derivations.Add([pscustomobject][ordered]@{sourceRelativePath=$SourceRelative;sourceSha256=$sourceHash;destinationRelativePath=$DestinationRelative;destinationSha256=Get-Hash $destination;routes=$routes.ToArray();reverseTransformSha256=$reverseHash;passed=$true})}
function R([string]$From,[string]$To){return [pscustomobject]@{from=$From;to=$To}}
Remove-Item Alias:R -ErrorAction SilentlyContinue

$attempt1Bound=@(
 'Research\Gate13R_36h_10pct_4Lane_Provenance.v1.json',
 'Research\Gate13R_36h_10pct_4Lane_Pilot_Plan.v1.json',
 'Research\Gate13R_36h_10pct_4Lane_Pilot_Schedule.v1.json',
 'Research\Verification\Gate13R_36h_10pct_4Lane\v1\execution-receipt.json',
 'Research\Verification\Gate13R_36h_10pct_4Lane\v1\verification-checkpoint.json',
 'Research\Verification\Gate13R_36h_10pct_4Lane\v1\failure-receipt.json',
 'Research\Verification\Gate13R_36h_10pct_4Lane\v1\partial-output-manifest.json'
)
$attempt1Hashes=@{};foreach($relative in $attempt1Bound){$attempt1Hashes[$relative]=Get-Hash (Join-Path $ProjectPath $relative)}

New-DerivedFile 'Research\Gate13R36hConcurrencyPreparationV1.psm1' 'Research\Gate13R36hConcurrencyPreparationV2.psm1' @(
 $(R "gate13r-36h-10pct-four-lane-nonformal-pilot-plan-v1" "gate13r-36h-10pct-four-lane-nonformal-pilot-plan-v2")
)
New-DerivedFile 'Research\Run-Gate13R36hBlockV1.ps1' 'Research\Run-Gate13R36hBlockV2.ps1' @(
 $(R 'Run-Gate13R36hBlockV1' 'Run-Gate13R36hBlockV2'),
 $(R 'return@(' 'return @('),
 $(R 'H:\DDM_Final_Project_Gate13R36H\v1\lane-' 'H:\DDM_Final_Project_Gate13R36H\v2\lane-'),
 $(R 'Research\PilotRuns\Gate13R_36h_10pct_4Lane\v1' 'Research\PilotRuns\Gate13R_36h_10pct_4Lane\v2'),
 $(R 'Research\Verification\Gate13R_36h_10pct_4Lane\v1' 'Research\Verification\Gate13R_36h_10pct_4Lane\v2'),
 $(R 'gate13r-36h-four-lane-block-wrapper-summary-v1' 'gate13r-36h-four-lane-block-wrapper-summary-v2'),
 $(R 'gate13r-36h-four-lane-block-wrapper-failure-v1' 'gate13r-36h-four-lane-block-wrapper-failure-v2')
)
New-DerivedFile 'Research\Run-Gate13R36hTelemetryProbeV1.ps1' 'Research\Run-Gate13R36hTelemetryProbeV2.ps1' @(
 $(R 'Run-Gate13R36hTelemetryProbeV1' 'Run-Gate13R36hTelemetryProbeV2'),
 $(R 'return@(' 'return @('),
 $(R 'H:\DDM_Final_Project_Gate13R36H\v1\lane-' 'H:\DDM_Final_Project_Gate13R36H\v2\lane-'),
 $(R 'Research\Verification\Gate13R_36h_10pct_4Lane\v1' 'Research\Verification\Gate13R_36h_10pct_4Lane\v2'),
 $(R 'gate13r-36h-four-lane-telemetry-wrapper-v1' 'gate13r-36h-four-lane-telemetry-wrapper-v2')
)
New-DerivedFile 'Research\Initialize-Gate13R36hLaneCopiesV1.ps1' 'Research\Initialize-Gate13R36hLaneCopiesV2.ps1' @(
 $(R 'Initialize-Gate13R36hLaneCopiesV1' 'Initialize-Gate13R36hLaneCopiesV2'),
 $(R 'H:\DDM_Final_Project_Gate13R36H\v1' 'H:\DDM_Final_Project_Gate13R36H\v2'),
 $(R "'Gate13R_36h_10pct_4Lane_Readiness_Amendment.v1.json','Gate13R_36h_10pct_4Lane_Pilot_Plan.v1.json','Gate13R_36h_10pct_4Lane_Provenance.v1.json'" "'Gate13R_36h_10pct_4Lane_Readiness_Amendment.v1.json','Gate13R_36h_10pct_4Lane_PrePilot_Defect_Repair_Amendment.v2.json','Gate13R_36h_10pct_4Lane_Pilot_Plan.v2.json','Gate13R_36h_10pct_4Lane_Provenance.v2.json'"),
 $(R 'gate13r-36h-isolated-lane-copy-manifest-v1' 'gate13r-36h-isolated-lane-copy-manifest-v2'),
 $(R 'gate13r-36h-four-isolated-project-copies-v1' 'gate13r-36h-four-isolated-project-copies-v2')
)
New-DerivedFile 'Research\Run-Gate13R36hConcurrencyPilotV1.ps1' 'Research\Run-Gate13R36hConcurrencyPilotV2.ps1' @(
 $(R 'Run-Gate13R36hConcurrencyPilotV1' 'Run-Gate13R36hConcurrencyPilotV2'),
 $(R 'Gate13R_36h_10pct_4Lane_Pilot_Plan.v1.json' 'Gate13R_36h_10pct_4Lane_Pilot_Plan.v2.json'),
 $(R 'Gate13R_36h_10pct_4Lane_Pilot_Schedule.v1.json' 'Gate13R_36h_10pct_4Lane_Pilot_Schedule.v2.json'),
 $(R 'Gate13R_36h_10pct_4Lane_Provenance.v1.json' 'Gate13R_36h_10pct_4Lane_Provenance.v2.json'),
 $(R 'Gate13R36hConcurrencyPreparationV1.psm1' 'Gate13R36hConcurrencyPreparationV2.psm1'),
 $(R 'Research\PilotRuns\Gate13R_36h_10pct_4Lane\v1' 'Research\PilotRuns\Gate13R_36h_10pct_4Lane\v2'),
 $(R 'Research\Verification\Gate13R_36h_10pct_4Lane\v1' 'Research\Verification\Gate13R_36h_10pct_4Lane\v2'),
 $(R 'Run-Gate13R36hBlockV1.ps1' 'Run-Gate13R36hBlockV2.ps1'),
 $(R 'gate13r-36h-four-lane-nonformal-pilot-execution-receipt-v1' 'gate13r-36h-four-lane-nonformal-pilot-execution-receipt-v2'),
 $(R 'gate13r-36h-four-lane-nonformal-pilot-checkpoint-v1' 'gate13r-36h-four-lane-nonformal-pilot-checkpoint-v2'),
 $(R 'gate13r-36h-four-lane-nonformal-pilot-failure-v1' 'gate13r-36h-four-lane-nonformal-pilot-failure-v2'),
 $(R 'gate13r-36h-four-lane-nonformal-pilot-execution-manifest-v1' 'gate13r-36h-four-lane-nonformal-pilot-execution-manifest-v2')
)
New-DerivedFile 'Research\Analyze-Gate13R36hConcurrencyPilotV1.ps1' 'Research\Analyze-Gate13R36hConcurrencyPilotV2.ps1' @(
 $(R 'Analyze-Gate13R36hConcurrencyPilotV1' 'Analyze-Gate13R36hConcurrencyPilotV2'),
 $(R 'Gate13R_36h_10pct_4Lane_Pilot_Plan.v1.json' 'Gate13R_36h_10pct_4Lane_Pilot_Plan.v2.json'),
 $(R 'Gate13R_36h_10pct_4Lane_Provenance.v1.json' 'Gate13R_36h_10pct_4Lane_Provenance.v2.json'),
 $(R 'Gate13R36hConcurrencyPreparationV1.psm1' 'Gate13R36hConcurrencyPreparationV2.psm1'),
 $(R 'Research\PilotRuns\Gate13R_36h_10pct_4Lane\v1' 'Research\PilotRuns\Gate13R_36h_10pct_4Lane\v2'),
 $(R 'gate13r-36h-four-lane-post-pilot-readiness-v1' 'gate13r-36h-four-lane-post-pilot-readiness-v2'),
 $(R 'gate13r-36h-four-lane-nonformal-pilot-manifest-v1' 'gate13r-36h-four-lane-nonformal-pilot-manifest-v2')
)
New-DerivedFile 'Research\Verification\New-Gate13R36hPilotScheduleV1.ps1' 'Research\Verification\New-Gate13R36hPilotScheduleV2.ps1' @(
 $(R 'Gate13R36hConcurrencyPreparationV1.psm1' 'Gate13R36hConcurrencyPreparationV2.psm1'),
 $(R 'Gate13R_36h_10pct_4Lane_Pilot_Plan.v1.json' 'Gate13R_36h_10pct_4Lane_Pilot_Plan.v2.json'),
 $(R 'Gate13R_36h_10pct_4Lane_Pilot_Schedule.v1.json' 'Gate13R_36h_10pct_4Lane_Pilot_Schedule.v2.json'),
 $(R 'Gate13R_36h_10pct_4Lane_Pilot_Schedule_Generation.v1.json' 'Gate13R_36h_10pct_4Lane_Pilot_Schedule_Generation.v2.json'),
 $(R 'gate13r-36h-10pct-four-lane-nonformal-pilot-schedule-v1' 'gate13r-36h-10pct-four-lane-nonformal-pilot-schedule-v2'),
 $(R 'gate13r-36h-four-lane-pilot-schedule-generation-v1' 'gate13r-36h-four-lane-pilot-schedule-generation-v2')
)

$planV1Path=Join-Path $ProjectPath 'Research\Gate13R_36h_10pct_4Lane_Pilot_Plan.v1.json';$planV2Path=Join-Path $ProjectPath 'Research\Gate13R_36h_10pct_4Lane_Pilot_Plan.v2.json';$plan=Get-Content -LiteralPath $planV1Path -Raw -Encoding UTF8|ConvertFrom-Json
$plan.planId='gate13r-36h-10pct-four-lane-nonformal-pilot-plan-v2';$plan.pilotAttempt=2;$plan.paths.pilotRootRelativePath='Research/PilotRuns/Gate13R_36h_10pct_4Lane/v2';$plan.paths.verificationRootRelativePath='Research/Verification/Gate13R_36h_10pct_4Lane/v2';$plan.paths.cloneRootAbsolutePath='H:/DDM_Final_Project_Gate13R36H/v2';foreach($lane in @($plan.lanes)){$lane.projectPath=([string]$lane.projectPath).Replace('/v1/','/v2/')};$amendmentPath=Join-Path $ProjectPath 'Research\Gate13R_36h_10pct_4Lane_PrePilot_Defect_Repair_Amendment.v2.json';$plan.upstreamHashes|Add-Member -NotePropertyName prePilotDefectRepairAmendment -NotePropertyValue (Get-Hash $amendmentPath);Write-CreateNewJson $planV2Path $plan 60
& (Join-Path $ProjectPath 'Research\Verification\New-Gate13R36hPilotScheduleV2.ps1') -ProjectPath $ProjectPath|Out-Null

$commonStaticReplacements=@(
 $(R 'Run-Gate13R36hStaticUnitV1' 'Run-Gate13R36hStaticUnitV2'),
 $(R 'Gate13R_36h_10pct_4Lane_Pilot_Plan.v1.json' 'Gate13R_36h_10pct_4Lane_Pilot_Plan.v2.json'),
 $(R 'Gate13R_36h_10pct_4Lane_Pilot_Schedule.v1.json' 'Gate13R_36h_10pct_4Lane_Pilot_Schedule.v2.json'),
 $(R 'Gate13R_36h_10pct_4Lane_Pilot_Schedule_Generation.v1.json' 'Gate13R_36h_10pct_4Lane_Pilot_Schedule_Generation.v2.json'),
 $(R 'Gate13R_36h_10pct_4Lane_Provenance.v1.json' 'Gate13R_36h_10pct_4Lane_Provenance.v2.json'),
 $(R 'Gate13R36hConcurrencyPreparationV1.psm1' 'Gate13R36hConcurrencyPreparationV2.psm1'),
 $(R 'Research\Verification\Gate13R_36h_10pct_4Lane\v1' 'Research\Verification\Gate13R_36h_10pct_4Lane\v2'),
 $(R 'Research\PilotRuns\Gate13R_36h_10pct_4Lane\v1' 'Research\PilotRuns\Gate13R_36h_10pct_4Lane\v2'),
 $(R 'H:\DDM_Final_Project_Gate13R36H\v1\lane-' 'H:\DDM_Final_Project_Gate13R36H\v2\lane-'),
 $(R 'Run-Gate13R36hBlockV1.ps1' 'Run-Gate13R36hBlockV2.ps1'),
 $(R 'Run-Gate13R36hTelemetryProbeV1.ps1' 'Run-Gate13R36hTelemetryProbeV2.ps1'),
 $(R 'Initialize-Gate13R36hLaneCopiesV1.ps1' 'Initialize-Gate13R36hLaneCopiesV2.ps1'),
 $(R 'Run-Gate13R36hConcurrencyPilotV1.ps1' 'Run-Gate13R36hConcurrencyPilotV2.ps1'),
 $(R 'Analyze-Gate13R36hConcurrencyPilotV1.ps1' 'Analyze-Gate13R36hConcurrencyPilotV2.ps1'),
 $(R 'Run-Gate13R36hRetainedRegressionV1.ps1' 'Run-Gate13R36hRetainedRegressionV2.ps1'),
 $(R 'Run-Gate13R36hVerificationV1.ps1' 'Run-Gate13R36hVerificationV2.ps1'),
 $(R 'Run-Gate13R36hValidationOnlyPrePilotAuditV1.ps1' 'Run-Gate13R36hValidationOnlyPrePilotAuditV2.ps1'),
 $(R 'gate13r-36h-four-lane-static-unit-summary-v1' 'gate13r-36h-four-lane-static-unit-summary-v2')
)
New-DerivedFile 'Research\Verification\Run-Gate13R36hStaticUnitV1.ps1' 'Research\Verification\Run-Gate13R36hStaticUnitV2.ps1' $commonStaticReplacements
New-DerivedFile 'Research\Verification\Run-Gate13R36hRetainedRegressionV1.ps1' 'Research\Verification\Run-Gate13R36hRetainedRegressionV2.ps1' @(
 $(R 'Run-Gate13R36hRetainedRegressionV1' 'Run-Gate13R36hRetainedRegressionV2'),
 $(R 'Research\Verification\Gate13R_36h_10pct_4Lane\v1' 'Research\Verification\Gate13R_36h_10pct_4Lane\v2'),
 $(R 'gate13r-36h-retained-regression-mechanical-file-scope-derivation-v1' 'gate13r-36h-retained-regression-mechanical-file-scope-derivation-v2')
)
New-DerivedFile 'Research\Verification\Run-Gate13R36hVerificationV1.ps1' 'Research\Verification\Run-Gate13R36hVerificationV2.ps1' @(
 $(R 'Run-Gate13R36hVerificationV1' 'Run-Gate13R36hVerificationV2'),
 $(R 'Research\Verification\Gate13R_36h_10pct_4Lane\v1' 'Research\Verification\Gate13R_36h_10pct_4Lane\v2'),
 $(R 'Research\PilotRuns\Gate13R_36h_10pct_4Lane\v1' 'Research\PilotRuns\Gate13R_36h_10pct_4Lane\v2'),
 $(R 'H:\DDM_Final_Project_Gate13R36H\v1' 'H:\DDM_Final_Project_Gate13R36H\v2'),
 $(R 'Gate13R36hConcurrencyPreparationV1.psm1' 'Gate13R36hConcurrencyPreparationV2.psm1'),
 $(R 'Gate13R_36h_10pct_4Lane_Pilot_Plan.v1.json' 'Gate13R_36h_10pct_4Lane_Pilot_Plan.v2.json'),
 $(R 'Gate13R_36h_10pct_4Lane_Pilot_Schedule.v1.json' 'Gate13R_36h_10pct_4Lane_Pilot_Schedule.v2.json'),
 $(R 'Gate13R_36h_10pct_4Lane_Provenance.v1.json' 'Gate13R_36h_10pct_4Lane_Provenance.v2.json'),
 $(R 'Run-Gate13R36hStaticUnitV1.ps1' 'Run-Gate13R36hStaticUnitV2.ps1'),
 $(R 'Initialize-Gate13R36hLaneCopiesV1.ps1' 'Initialize-Gate13R36hLaneCopiesV2.ps1'),
 $(R 'Run-Gate13R36hTelemetryProbeV1.ps1' 'Run-Gate13R36hTelemetryProbeV2.ps1'),
 $(R 'Run-Gate13R36hBlockV1.ps1' 'Run-Gate13R36hBlockV2.ps1'),
 $(R 'Run-Gate13R36hRetainedRegressionV1.ps1' 'Run-Gate13R36hRetainedRegressionV2.ps1'),
 $(R 'Run-Gate13R36hValidationOnlyPrePilotAuditV1.ps1' 'Run-Gate13R36hValidationOnlyPrePilotAuditV2.ps1'),
 $(R 'gate13r-36h-four-lane-verification-checkpoint-v1' 'gate13r-36h-four-lane-verification-checkpoint-v2'),
 $(R 'gate13r-36h-four-lane-nonexecuting-verification-receipt-v1' 'gate13r-36h-four-lane-nonexecuting-verification-receipt-v2'),
 $(R 'gate13r-36h-four-lane-block-verification-v1' 'gate13r-36h-four-lane-block-verification-v2'),
 $(R 'gate13r-36h-verification-partial-output-manifest-v1' 'gate13r-36h-verification-partial-output-manifest-v2'),
 $(R 'gate13r-36h-nonexecuting-verification-failure-v1' 'gate13r-36h-nonexecuting-verification-failure-v2')
)
New-DerivedFile 'Research\Verification\Run-Gate13R36hValidationOnlyPrePilotAuditV1.ps1' 'Research\Verification\Run-Gate13R36hValidationOnlyPrePilotAuditV2.ps1' @(
 $(R 'Run-Gate13R36hValidationOnlyPrePilotAuditV1' 'Run-Gate13R36hValidationOnlyPrePilotAuditV2'),
 $(R 'Research\Verification\Gate13R_36h_10pct_4Lane\v1' 'Research\Verification\Gate13R_36h_10pct_4Lane\v2'),
 $(R 'Gate13R36hConcurrencyPreparationV1.psm1' 'Gate13R36hConcurrencyPreparationV2.psm1'),
 $(R 'Gate13R_36h_10pct_4Lane_Pilot_Plan.v1.json' 'Gate13R_36h_10pct_4Lane_Pilot_Plan.v2.json'),
 $(R 'Gate13R_36h_10pct_4Lane_Pilot_Schedule.v1.json' 'Gate13R_36h_10pct_4Lane_Pilot_Schedule.v2.json'),
 $(R 'Gate13R_36h_10pct_4Lane_Provenance.v1.json' 'Gate13R_36h_10pct_4Lane_Provenance.v2.json'),
 $(R 'H:\DDM_Final_Project_Gate13R36H\v1\lane-' 'H:\DDM_Final_Project_Gate13R36H\v2\lane-'),
 $(R 'Research\PilotRuns\Gate13R_36h_10pct_4Lane\v1' 'Research\PilotRuns\Gate13R_36h_10pct_4Lane\v2'),
 $(R 'gate13r-36h-four-lane-validation-only-pre-pilot-audit-v1' 'gate13r-36h-four-lane-validation-only-pre-pilot-audit-v2')
)

function Bound([string]$RelativePath){$path=Join-Path $ProjectPath $RelativePath;return [ordered]@{relativePath=$RelativePath.Replace('\','/');sha256=Get-Hash $path;bytes=[long](Get-Item -LiteralPath $path).Length}}
$provenancePath=Join-Path $ProjectPath 'Research\Gate13R_36h_10pct_4Lane_Provenance.v2.json'
$provenance=[ordered]@{
 schemaVersion=2;provenanceId='gate13r-36h-10pct-four-isolated-editor-lanes-provenance-v2';createdAtUtc=[DateTime]::UtcNow.ToString('o');executionDesignId='gate13r-36h-10pct-four-isolated-editor-lanes-v1';status='NON-FORMAL / EXCLUDED-FROM-FORMAL-ANALYSIS';formalCampaign=$false;formalExecutionAuthorized=$false;pilotExecutionAuthorizedCount=1;automaticPilotRetryAuthorized=$false;sameAttemptResumeAuthorized=$false
 authorization=Bound 'Research\Gate13R_36h_Redesign_Pilot_Authorization.v1.json';specification=Bound 'Research\Gate13R_36h_10pct_4Lane_Redesign_Specification.v1.md';testDesign=Bound 'Research\Gate13R_36h_10pct_4Lane_Test_Design.v1.md';readinessAmendment=Bound 'Research\Gate13R_36h_10pct_4Lane_Readiness_Amendment.v1.json';executionAuthorization=Bound 'Research\Gate13R_36h_10pct_4Lane_PrePilot_Defect_Repair_Amendment.v2.json';config=Bound 'Research\Gate13R_36h_10pct_4Lane_Pilot_Plan.v2.json';schedule=Bound 'Research\Gate13R_36h_10pct_4Lane_Pilot_Schedule.v2.json';preservationBaseline=Bound 'Research\Gate13R_36h_10pct_4Lane_PreWrite_Preservation_Baseline.v1.json';commandDerivation=Bound 'Research\Gate13R_36h_Concurrency_Command_Derivation.v1.json';attempt2Derivation=Bound 'Research\Verification\New-Gate13R36hAttempt2ArtifactsV1.ps1';unityCommand=Bound 'Assets\_Scripts\Research\Editor\Gate13R36hConcurrencyBatchCommandV1.cs';preparationModule=Bound 'Research\Gate13R36hConcurrencyPreparationV2.psm1';blockRunner=Bound 'Research\Run-Gate13R36hBlockV2.ps1';telemetryRunner=Bound 'Research\Run-Gate13R36hTelemetryProbeV2.ps1';laneCopyInitializer=Bound 'Research\Initialize-Gate13R36hLaneCopiesV2.ps1';pilotOrchestrator=Bound 'Research\Run-Gate13R36hConcurrencyPilotV2.ps1';pilotAnalyzer=Bound 'Research\Analyze-Gate13R36hConcurrencyPilotV2.ps1';scheduleGenerator=Bound 'Research\Verification\New-Gate13R36hPilotScheduleV2.ps1';compileRunner=Bound 'Research\Verification\Run-Gate13R36hCompileV1.ps1';staticUnitRunner=Bound 'Research\Verification\Run-Gate13R36hStaticUnitV2.ps1';retainedRegressionRunner=Bound 'Research\Verification\Run-Gate13R36hRetainedRegressionV2.ps1';verificationRunner=Bound 'Research\Verification\Run-Gate13R36hVerificationV2.ps1';validationOnlyAuditRunner=Bound 'Research\Verification\Run-Gate13R36hValidationOnlyPrePilotAuditV2.ps1';gate11BundleManifest=Bound 'Research\FormalScenarios\Gate11R_5pct\v1\bundle-manifest.json';attempt1FailureReceipt=Bound 'Research\Verification\Gate13R_36h_10pct_4Lane\v1\failure-receipt.json';attempt1Checkpoint=Bound 'Research\Verification\Gate13R_36h_10pct_4Lane\v1\verification-checkpoint.json'
 unityEditor=[ordered]@{absolutePath='H:/UnityEditor/2022.3.30f1c1/Editor/Unity.exe';productVersion='2022.3.30f1c1_a6dc00fbe362';sha256='0a69d14cbe2ca82d0a6168da8156d9e0dd138a6b7d0260dcdea31fd3957ca9cf'}
 paths=[ordered]@{verificationRoot='Research/Verification/Gate13R_36h_10pct_4Lane/v2';pilotRoot='Research/PilotRuns/Gate13R_36h_10pct_4Lane/v2';cloneRoot='H:/DDM_Final_Project_Gate13R36H/v2';reservedFormalRoot='Research/FormalRuns/Gate13R_36h_10pct_4Lane/v1'}
}
Write-CreateNewJson $provenancePath $provenance 60
foreach($relative in $attempt1Bound){if((Get-Hash (Join-Path $ProjectPath $relative))-ne[string]$attempt1Hashes[$relative]){throw "Attempt-1 evidence changed during v2 derivation: $relative"}}
$receipt=[ordered]@{schemaVersion=1;receiptKind='gate13r-36h-prepilot-attempt2-mechanical-derivation-v1';createdAtUtc=[DateTime]::UtcNow.ToString('o');amendmentRelativePath='Research/Gate13R_36h_10pct_4Lane_PrePilot_Defect_Repair_Amendment.v2.json';amendmentSha256=Get-Hash $amendmentPath;derivations=$derivations.ToArray();planV1Sha256=Get-Hash $planV1Path;planV2Sha256=Get-Hash $planV2Path;scheduleV2Sha256=Get-Hash (Join-Path $ProjectPath 'Research\Gate13R_36h_10pct_4Lane_Pilot_Schedule.v2.json');provenanceV2Sha256=Get-Hash $provenancePath;attempt1EvidencePreserved=$true;pilotRootCreated=$false;formalCampaign=$false;passed=$true}
Write-CreateNewJson (Join-Path $ProjectPath 'Research\Gate13R_36h_10pct_4Lane_Attempt2_Derivation_Receipt.v1.json') $receipt 80
$receipt|ConvertTo-Json -Depth 8
