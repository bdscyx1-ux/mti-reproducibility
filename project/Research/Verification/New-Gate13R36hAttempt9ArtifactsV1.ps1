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
$authorizedOverlays=New-Object Collections.Generic.List[object]
$commonRoutes=@(
    $(Route 'Gate13R36hConcurrencyPreparationV2' 'Gate13R36hConcurrencyPreparationV9'),
    $(Route 'Run-Gate13R36hBlockV2' 'Run-Gate13R36hBlockV9'),
    $(Route 'Run-Gate13R36hTelemetryProbeV2' 'Run-Gate13R36hTelemetryProbeV9'),
    $(Route 'Initialize-Gate13R36hLaneCopiesV2' 'Initialize-Gate13R36hLaneCopiesV9'),
    $(Route 'Run-Gate13R36hConcurrencyPilotV2' 'Run-Gate13R36hConcurrencyPilotV9'),
    $(Route 'Analyze-Gate13R36hConcurrencyPilotV2' 'Analyze-Gate13R36hConcurrencyPilotV9'),
    $(Route 'New-Gate13R36hPilotScheduleV2' 'New-Gate13R36hPilotScheduleV9'),
    $(Route 'Run-Gate13R36hStaticUnitV2' 'Run-Gate13R36hStaticUnitV9'),
    $(Route 'Run-Gate13R36hRetainedRegressionV2' 'Run-Gate13R36hRetainedRegressionV9'),
    $(Route 'Run-Gate13R36hVerificationV2' 'Run-Gate13R36hVerificationV9'),
    $(Route 'Run-Gate13R36hValidationOnlyPrePilotAuditV2' 'Run-Gate13R36hValidationOnlyPrePilotAuditV9'),
    $(Route 'Gate13R_36h_10pct_4Lane_Pilot_Plan.v2.json' 'Gate13R_36h_10pct_4Lane_Pilot_Plan.v9.json'),
    $(Route 'Gate13R_36h_10pct_4Lane_Pilot_Schedule.v2.json' 'Gate13R_36h_10pct_4Lane_Pilot_Schedule.v9.json'),
    $(Route 'Gate13R_36h_10pct_4Lane_Pilot_Schedule_Generation.v2.json' 'Gate13R_36h_10pct_4Lane_Pilot_Schedule_Generation.v9.json'),
    $(Route 'Gate13R_36h_10pct_4Lane_Provenance.v2.json' 'Gate13R_36h_10pct_4Lane_Provenance.v9.json'),
    $(Route 'Gate13R_36h_10pct_4Lane_PrePilot_Defect_Repair_Amendment.v2.json' 'Gate13R_36h_10pct_4Lane_PrePilot_Defect_Repair_Amendment.v9.json'),
    $(Route 'Research\Verification\Gate13R_36h_10pct_4Lane\v2' 'Research\Verification\Gate13R_36h_10pct_4Lane\v9'),
    $(Route 'Research\PilotRuns\Gate13R_36h_10pct_4Lane\v2' 'Research\PilotRuns\Gate13R_36h_10pct_4Lane\v9'),
    $(Route 'H:\DDM_Final_Project_Gate13R36H\v2' 'H:\DDM_Final_Project_Gate13R36H\v9'),
    $(Route 'gate13r-36h-10pct-four-lane-nonformal-pilot-plan-v2' 'gate13r-36h-10pct-four-lane-nonformal-pilot-plan-v9'),
    $(Route 'gate13r-36h-10pct-four-lane-nonformal-pilot-plan-v1' 'gate13r-36h-10pct-four-lane-nonformal-pilot-plan-v9'),
    $(Route 'gate13r-36h-four-lane-block-wrapper-summary-v2' 'gate13r-36h-four-lane-block-wrapper-summary-v9'),
    $(Route 'gate13r-36h-four-lane-block-wrapper-failure-v2' 'gate13r-36h-four-lane-block-wrapper-failure-v9'),
    $(Route 'gate13r-36h-four-lane-telemetry-wrapper-v2' 'gate13r-36h-four-lane-telemetry-wrapper-v9'),
    $(Route 'gate13r-36h-isolated-lane-copy-manifest-v2' 'gate13r-36h-isolated-lane-copy-manifest-v9'),
    $(Route 'gate13r-36h-four-isolated-project-copies-v2' 'gate13r-36h-four-isolated-project-copies-v9'),
    $(Route 'gate13r-36h-four-lane-nonformal-pilot-execution-receipt-v2' 'gate13r-36h-four-lane-nonformal-pilot-execution-receipt-v9'),
    $(Route 'gate13r-36h-four-lane-nonformal-pilot-checkpoint-v2' 'gate13r-36h-four-lane-nonformal-pilot-checkpoint-v9'),
    $(Route 'gate13r-36h-four-lane-nonformal-pilot-execution-manifest-v2' 'gate13r-36h-four-lane-nonformal-pilot-execution-manifest-v9'),
    $(Route 'gate13r-36h-four-lane-nonformal-pilot-failure-v2' 'gate13r-36h-four-lane-nonformal-pilot-failure-v9'),
    $(Route 'gate13r-36h-four-lane-pilot-partial-output-manifest-v1' 'gate13r-36h-four-lane-pilot-partial-output-manifest-v9'),
    $(Route 'gate13r-36h-four-lane-post-pilot-readiness-v2' 'gate13r-36h-four-lane-post-pilot-readiness-v9'),
    $(Route 'gate13r-36h-four-lane-nonformal-pilot-manifest-v2' 'gate13r-36h-four-lane-nonformal-pilot-manifest-v9'),
    $(Route 'gate13r-36h-10pct-four-lane-nonformal-pilot-schedule-v2' 'gate13r-36h-10pct-four-lane-nonformal-pilot-schedule-v9'),
    $(Route 'gate13r-36h-four-lane-pilot-schedule-generation-v2' 'gate13r-36h-four-lane-pilot-schedule-generation-v9'),
    $(Route 'gate13r-36h-four-lane-static-unit-summary-v2' 'gate13r-36h-four-lane-static-unit-summary-v9'),
    $(Route 'gate13r-36h-retained-regression-mechanical-file-scope-derivation-v2' 'gate13r-36h-retained-regression-mechanical-file-scope-derivation-v9'),
    $(Route 'gate13r-36h-four-lane-verification-checkpoint-v2' 'gate13r-36h-four-lane-verification-checkpoint-v9'),
    $(Route 'gate13r-36h-four-lane-nonexecuting-verification-receipt-v2' 'gate13r-36h-four-lane-nonexecuting-verification-receipt-v9'),
    $(Route 'gate13r-36h-four-lane-block-verification-v2' 'gate13r-36h-four-lane-block-verification-v9'),
    $(Route 'gate13r-36h-verification-partial-output-manifest-v2' 'gate13r-36h-verification-partial-output-manifest-v9'),
    $(Route 'gate13r-36h-nonexecuting-verification-failure-v2' 'gate13r-36h-nonexecuting-verification-failure-v9'),
    $(Route 'gate13r-36h-four-lane-validation-only-pre-pilot-audit-v2' 'gate13r-36h-four-lane-validation-only-pre-pilot-audit-v9')
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
    if($applied.Count-lt1){throw "No v9 routes applied to $SourceRelative"}
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
    'Research\Gate13R36hConcurrencyPreparationV9.psm1',
    'Research\Run-Gate13R36hBlockV9.ps1',
    'Research\Run-Gate13R36hTelemetryProbeV9.ps1',
    'Research\Initialize-Gate13R36hLaneCopiesV9.ps1',
    'Research\Run-Gate13R36hConcurrencyPilotV9.ps1',
    'Research\Analyze-Gate13R36hConcurrencyPilotV9.ps1',
    'Research\Verification\New-Gate13R36hPilotScheduleV9.ps1',
    'Research\Verification\Run-Gate13R36hStaticUnitV9.ps1',
    'Research\Verification\Run-Gate13R36hRetainedRegressionV9.ps1',
    'Research\Verification\Run-Gate13R36hVerificationV9.ps1',
    'Research\Verification\Run-Gate13R36hValidationOnlyPrePilotAuditV9.ps1',
    'Research\Gate13R_36h_10pct_4Lane_Pilot_Plan.v9.json',
    'Research\Gate13R_36h_10pct_4Lane_Pilot_Schedule.v9.json',
    'Research\Gate13R_36h_10pct_4Lane_Pilot_Schedule_Generation.v9.json',
    'Research\Gate13R_36h_10pct_4Lane_Provenance.v9.json',
    'Research\Gate13R_36h_10pct_4Lane_Attempt9_Derivation_Receipt.v1.json'
)
foreach($relative in $destinations){if(Test-Path -LiteralPath (Join-Path $ProjectPath $relative)){throw "Create-new v9 target already exists: $relative"}}
foreach($root in @('Research\Verification\Gate13R_36h_10pct_4Lane\v9','Research\PilotRuns\Gate13R_36h_10pct_4Lane\v9','H:\DDM_Final_Project_Gate13R36H\v9')){
    $resolvedRoot=if([IO.Path]::IsPathRooted($root)){$root}else{Join-Path $ProjectPath $root}
    if(Test-Path -LiteralPath $resolvedRoot){throw "Create-new v9 root already exists: $root"}
}
if(Test-Path -LiteralPath (Join-Path $ProjectPath 'Research\FormalRuns\Gate13R_36h_10pct_4Lane\v1')){throw 'Forbidden formal root exists.'}

$frozen=@(
    'Research\Gate13R_36h_10pct_4Lane_PrePilot_Defect_Repair_Amendment.v4.json',
    'Research\Gate13R_36h_10pct_4Lane_Pilot_Plan.v4.json',
    'Research\Gate13R_36h_10pct_4Lane_Pilot_Schedule.v4.json',
    'Research\Gate13R_36h_10pct_4Lane_Pilot_Schedule_Generation.v4.json',
    'Research\Gate13R_36h_10pct_4Lane_Provenance.v4.json',
    'Research\Gate13R_36h_10pct_4Lane_Attempt4_Derivation_Receipt.v1.json',
    'Research\Gate13R_36h_10pct_4Lane_Attempt4_Generator_Derivation_Receipt.v1.json',
    'Research\Verification\New-Gate13R36hAttempt4GeneratorV1.ps1',
    'Research\Verification\New-Gate13R36hAttempt4ArtifactsV1.ps1',
    'Research\Verification\Gate13R_36h_10pct_4Lane_PreImplementation\v9\StaticUnitV4\summary.json',
    'Research\Verification\Gate13R_36h_10pct_4Lane\v4\execution-receipt.json',
    'Research\Verification\Gate13R_36h_10pct_4Lane\v4\verification-checkpoint.json',
    'Research\Verification\Gate13R_36h_10pct_4Lane\v4\failure-receipt.json',
    'Research\Verification\Gate13R_36h_10pct_4Lane\v4\partial-output-manifest.json',
    'Research\Verification\Gate13R_36h_10pct_4Lane\v4\LaneCopies\summary.json',
    'Research\Verification\Gate13R_36h_10pct_4Lane\v4\BlockVerification\negative-fail-closed.wrapper-summary.json',
    'Research\Gate13R_36h_10pct_4Lane_v4_Lock_Failure_Diagnosis.v1.json',
    'Research\Verification\Gate13R36hAttempt5AuthorizedOverlayTemplateV1.ps1.txt',
    'Research\Gate13R_36h_10pct_4Lane_ExpectedNegative_LockHygiene_Test_Design.v5.md',
    'Research\Gate13R_36h_10pct_4Lane_PrePilot_Defect_Repair_Amendment.v5.json',
    'Research\Verification\Run-Gate13R36hLockHygieneUnitV5.ps1',
    'Research\Verification\Gate13R_36h_10pct_4Lane_PreImplementation\v9\LockHygieneUnitV5\summary.json',
    'Research\Verification\New-Gate13R36hAttempt5GeneratorV1.ps1',
    'Research\Gate13R_36h_10pct_4Lane_Attempt5_Generator_Derivation_Receipt.v1.json',
    'Research\Verification\New-Gate13R36hAttempt5ArtifactsV1.ps1',
    'Research\Verification\Write-Gate13R36hAttempt5DerivationFailureV1.ps1',
    'Research\Gate13R_36h_10pct_4Lane_Attempt5_Derivation_Partial_Manifest.v1.json',
    'Research\Gate13R_36h_10pct_4Lane_Attempt5_Derivation_Failure.v1.json',
    'Research\Gate13R_36h_10pct_4Lane_Attempt5_Derivation_Checkpoint.v1.json',
    'Research\Gate13R36hConcurrencyPreparationV5.psm1',
    'Research\Initialize-Gate13R36hLaneCopiesV5.ps1',
    'Research\Run-Gate13R36hTelemetryProbeV5.ps1',
    'Research\Run-Gate13R36hConcurrencyPilotV5.ps1',
    'Research\Analyze-Gate13R36hConcurrencyPilotV5.ps1',
    'Research\Run-Gate13R36hBlockV5.ps1',
    'Research\Verification\New-Gate13R36hPilotScheduleV5.ps1',
    'Research\Verification\Run-Gate13R36hStaticUnitV5.ps1',
    'Research\Verification\Run-Gate13R36hRetainedRegressionV5.ps1',
    'Research\Verification\Run-Gate13R36hVerificationV5.ps1',
    'Research\Verification\Run-Gate13R36hValidationOnlyPrePilotAuditV5.ps1',
    'Research\Gate13R_36h_10pct_4Lane_PrePilot_Defect_Repair_Amendment.v6.json',
    'Research\Verification\New-Gate13R36hAttempt6GeneratorV1.ps1',
    'Research\Gate13R_36h_10pct_4Lane_Attempt6_Generator_Derivation_Receipt.v1.json',
    'Research\Verification\New-Gate13R36hAttempt6ArtifactsV1.ps1',
    'Research\Verification\Write-Gate13R36hAttempt6DerivationFailureV1.ps1',
    'Research\Gate13R_36h_10pct_4Lane_Attempt6_Derivation_Partial_Manifest.v1.json',
    'Research\Gate13R_36h_10pct_4Lane_Attempt6_Derivation_Failure.v1.json',
    'Research\Gate13R_36h_10pct_4Lane_Attempt6_Derivation_Checkpoint.v1.json',
    'Research\Gate13R36hConcurrencyPreparationV6.psm1',
    'Research\Initialize-Gate13R36hLaneCopiesV6.ps1',
    'Research\Run-Gate13R36hTelemetryProbeV6.ps1',
    'Research\Run-Gate13R36hConcurrencyPilotV6.ps1',
    'Research\Analyze-Gate13R36hConcurrencyPilotV6.ps1',
    'Research\Run-Gate13R36hBlockV6.ps1',
    'Research\Verification\New-Gate13R36hPilotScheduleV6.ps1',
    'Research\Verification\Run-Gate13R36hStaticUnitV6.ps1',
    'Research\Verification\Run-Gate13R36hRetainedRegressionV6.ps1',
    'Research\Verification\Run-Gate13R36hVerificationV6.ps1',
    'Research\Verification\Run-Gate13R36hValidationOnlyPrePilotAuditV6.ps1',
    'Research\Gate13R_36h_10pct_4Lane_PrePilot_Defect_Repair_Amendment.v7.json',
    'Research\Verification\New-Gate13R36hAttempt7GeneratorV1.ps1',
    'Research\Gate13R_36h_10pct_4Lane_Attempt7_Generator_Derivation_Receipt.v1.json',
    'Research\Verification\New-Gate13R36hAttempt7ArtifactsV1.ps1',
    'Research\Gate13R_36h_10pct_4Lane_Attempt7_Derivation_Receipt.v1.json',
    'Research\Verification\Write-Gate13R36hAttempt7StaticFailureV1.ps1',
    'Research\Gate13R_36h_10pct_4Lane_Attempt7_PreImplementation_Static_Partial_Manifest.v1.json',
    'Research\Gate13R_36h_10pct_4Lane_Attempt7_PreImplementation_Static_Failure.v1.json',
    'Research\Gate13R_36h_10pct_4Lane_Attempt7_PreImplementation_Static_Checkpoint.v1.json',
    'Research\Verification\Gate13R_36h_10pct_4Lane_PreImplementation\v10\StaticUnitV7\summary.json',
    'Research\Gate13R36hConcurrencyPreparationV7.psm1',
    'Research\Initialize-Gate13R36hLaneCopiesV7.ps1',
    'Research\Run-Gate13R36hTelemetryProbeV7.ps1',
    'Research\Run-Gate13R36hConcurrencyPilotV7.ps1',
    'Research\Analyze-Gate13R36hConcurrencyPilotV7.ps1',
    'Research\Run-Gate13R36hBlockV7.ps1',
    'Research\Verification\New-Gate13R36hPilotScheduleV7.ps1',
    'Research\Verification\Run-Gate13R36hStaticUnitV7.ps1',
    'Research\Verification\Run-Gate13R36hRetainedRegressionV7.ps1',
    'Research\Verification\Run-Gate13R36hVerificationV7.ps1',
    'Research\Verification\Run-Gate13R36hValidationOnlyPrePilotAuditV7.ps1',
    'Research\Gate13R_36h_10pct_4Lane_Pilot_Plan.v7.json',
    'Research\Gate13R_36h_10pct_4Lane_Pilot_Schedule.v7.json',
    'Research\Gate13R_36h_10pct_4Lane_Pilot_Schedule_Generation.v7.json',
    'Research\Gate13R_36h_10pct_4Lane_Provenance.v7.json',
    'Research\Gate13R_36h_10pct_4Lane_PrePilot_Defect_Repair_Amendment.v8.json',
    'Research\Verification\New-Gate13R36hAttempt8GeneratorV1.ps1',
    'Research\Gate13R_36h_10pct_4Lane_Attempt8_Generator_Derivation_Receipt.v1.json',
    'Research\Verification\New-Gate13R36hAttempt8ArtifactsV1.ps1',
    'Research\Verification\Write-Gate13R36hAttempt8DerivationFailureV1.ps1',
    'Research\Gate13R_36h_10pct_4Lane_Attempt8_Derivation_Partial_Manifest.v1.json',
    'Research\Gate13R_36h_10pct_4Lane_Attempt8_Derivation_Failure.v1.json',
    'Research\Gate13R_36h_10pct_4Lane_Attempt8_Derivation_Checkpoint.v1.json',
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
    @('Research\Gate13R36hConcurrencyPreparationV2.psm1','Research\Gate13R36hConcurrencyPreparationV9.psm1'),
    @('Research\Run-Gate13R36hBlockV2.ps1','Research\Run-Gate13R36hBlockV9.ps1'),
    @('Research\Run-Gate13R36hTelemetryProbeV2.ps1','Research\Run-Gate13R36hTelemetryProbeV9.ps1'),
    @('Research\Initialize-Gate13R36hLaneCopiesV2.ps1','Research\Initialize-Gate13R36hLaneCopiesV9.ps1'),
    @('Research\Run-Gate13R36hConcurrencyPilotV2.ps1','Research\Run-Gate13R36hConcurrencyPilotV9.ps1'),
    @('Research\Analyze-Gate13R36hConcurrencyPilotV2.ps1','Research\Analyze-Gate13R36hConcurrencyPilotV9.ps1'),
    @('Research\Verification\New-Gate13R36hPilotScheduleV2.ps1','Research\Verification\New-Gate13R36hPilotScheduleV9.ps1'),
    @('Research\Verification\Run-Gate13R36hStaticUnitV2.ps1','Research\Verification\Run-Gate13R36hStaticUnitV9.ps1'),
    @('Research\Verification\Run-Gate13R36hRetainedRegressionV2.ps1','Research\Verification\Run-Gate13R36hRetainedRegressionV9.ps1'),
    @('Research\Verification\Run-Gate13R36hVerificationV2.ps1','Research\Verification\Run-Gate13R36hVerificationV9.ps1'),
    @('Research\Verification\Run-Gate13R36hValidationOnlyPrePilotAuditV2.ps1','Research\Verification\Run-Gate13R36hValidationOnlyPrePilotAuditV9.ps1')
)
foreach($pair in $map){
    $extra=@()
    if([string]$pair[0]-eq'Research\Verification\Run-Gate13R36hStaticUnitV2.ps1'){$extra=@($(Route 'New-Gate13R36hPilotScheduleV1.ps1' 'New-Gate13R36hPilotScheduleV9.ps1'))}
    New-DerivedFile -SourceRelative ([string]$pair[0]) -DestinationRelative ([string]$pair[1]) -ExtraRoutes $extra
}

function Apply-AuthorizedOverlay([string]$RelativePath,[string]$OverlayId,[object[]]$Replacements){
    $path=Join-Path $ProjectPath $RelativePath
    $before=Get-Hash $path;$content=[IO.File]::ReadAllText($path);$applied=New-Object Collections.Generic.List[object]
    foreach($replacement in $Replacements){$from=[string]$replacement.from;$to=[string]$replacement.to;$count=Get-Count $content $from;if($count-lt1){throw "Authorized overlay route missing in $RelativePath`: $from"};$content=$content.Replace($from,$to);$applied.Add([pscustomobject][ordered]@{from=$from;to=$to;count=$count})}
    $tokens=$null;$parseErrors=$null;[void][Management.Automation.Language.Parser]::ParseInput($content,[ref]$tokens,[ref]$parseErrors);if(@($parseErrors).Count-ne0){throw "Authorized overlay parser failure in $RelativePath`: $(@($parseErrors|ForEach-Object Message)-join'; ')"}
    [IO.File]::WriteAllText($path,$content,$utf8);$after=Get-Hash $path
    $authorizedOverlays.Add([pscustomobject][ordered]@{overlayId=$OverlayId;relativePath=$RelativePath;beforeSha256=$before;afterSha256=$after;routes=$applied.ToArray();parserPassed=$true})
}

$blockImportFrom='$SourceProjectPath=[IO.Path]::GetFullPath($SourceProjectPath);$LaneProjectPath=[IO.Path]::GetFullPath($LaneProjectPath);$UnityPath=[IO.Path]::GetFullPath($UnityPath)'
$blockImportTo=@'
$SourceProjectPath=[IO.Path]::GetFullPath($SourceProjectPath);$LaneProjectPath=[IO.Path]::GetFullPath($LaneProjectPath);$UnityPath=[IO.Path]::GetFullPath($UnityPath)
$lockHygieneModulePath=Join-Path $SourceProjectPath 'Research\Gate10RLockHygieneV3.psm1'
if((Get-LowerHash $lockHygieneModulePath)-ne'9eba2284dc90fcf6dbbc59080301c1ac6db14c5029f8adab69db234c94f879d6'){throw 'Frozen lock-hygiene module hash mismatch.'}
Import-Module $lockHygieneModulePath -Force
'@.Trim()
$quiescenceFrom=@'
$quiescenceDeadline=(Get-Date).AddSeconds(60);$lockPath=Join-Path $LaneProjectPath 'Temp\UnityLockfile'
do{$laneProcesses=@(Get-LaneUnityProcesses $LaneProjectPath);$lockExists=Test-Path -LiteralPath $lockPath;if($laneProcesses.Count-eq0-and-not$lockExists){break};Start-Sleep -Milliseconds 250}while((Get-Date)-lt$quiescenceDeadline)
$laneProcesses=@(Get-LaneUnityProcesses $LaneProjectPath);$lockExists=Test-Path -LiteralPath $lockPath
if($timedOut){$errors.Add("Hard timeout after $TimeoutSeconds seconds.")};if($laneProcesses.Count-ne0){$errors.Add('Lane-owned Unity process remains after exit.')};if($lockExists){$errors.Add('Lane Unity lock remains after quiescence.')}
'@.Trim()
$quiescenceTo=@'
$lockPath=Join-Path $LaneProjectPath 'Temp\UnityLockfile';$lockHygieneResult=$null
if($ExpectFailure){
    $lockEvidenceDirectory=$OutputDirectory+'.lock-hygiene';if(-not(Test-Path -LiteralPath $lockEvidenceDirectory)){New-Item -ItemType Directory -Path $lockEvidenceDirectory|Out-Null}
    try{$lockHygieneResult=Invoke-Gate10RPostExitQuiescenceV3 -ProjectPath $LaneProjectPath -OwnedProcessId $process.Id -OwnedProcessStartedAt $started -OwnedProcessCompletedAt $completed -Role expected-negative -EvidenceDirectory $lockEvidenceDirectory -ContextId ('g13r36-v9-negative-lane-{0:D2}'-f$LaneNumber) -QuiescenceSeconds 60 -PollMilliseconds 250 -TimestampToleranceSeconds 2}catch{$errors.Add('Expected-negative controlled lock hygiene failed: '+$_.Exception.Message)}
    $laneProcesses=@(Get-LaneUnityProcesses $LaneProjectPath);$lockExists=Test-Path -LiteralPath $lockPath
}else{
    $quiescenceDeadline=(Get-Date).AddSeconds(60)
    do{$laneProcesses=@(Get-LaneUnityProcesses $LaneProjectPath);$lockExists=Test-Path -LiteralPath $lockPath;if($laneProcesses.Count-eq0-and-not$lockExists){break};Start-Sleep -Milliseconds 250}while((Get-Date)-lt$quiescenceDeadline)
    $laneProcesses=@(Get-LaneUnityProcesses $LaneProjectPath);$lockExists=Test-Path -LiteralPath $lockPath
}
if($timedOut){$errors.Add("Hard timeout after $TimeoutSeconds seconds.")};if($laneProcesses.Count-ne0){$errors.Add('Lane-owned Unity process remains after exit.')};if($lockExists){$errors.Add('Lane Unity lock remains after quiescence.')}
'@.Trim()
$summaryFrom='automaticResumeAttempted=$false;errors=$errors.ToArray();passed=$passed'
$summaryTo='automaticResumeAttempted=$false;lockHygieneResult=$lockHygieneResult;errors=$errors.ToArray();passed=$passed'
Apply-AuthorizedOverlay 'Research\Run-Gate13R36hBlockV9.ps1' 'expected-negative-lock-hygiene-v9' @($(Route $blockImportFrom $blockImportTo),$(Route $quiescenceFrom $quiescenceTo),$(Route $summaryFrom $summaryTo))

$staticListFrom="'Research\Verification\Run-Gate13R36hVerificationV9.ps1','Research\Verification\Run-Gate13R36hValidationOnlyPrePilotAuditV9.ps1'"
$staticListTo=$staticListFrom+",'Research\Verification\Run-Gate13R36hLockHygieneUnitV5.ps1'"
$staticSmokeFrom="@{name='analysis';script='Research\Analyze-Gate13R36hConcurrencyPilotV9.ps1';arguments=@('-ProjectPath',`$ProjectPath,'-PilotRoot',(Join-Path `$ProjectPath 'Research\PilotRuns\Gate13R_36h_10pct_4Lane\v9'),'-BindingSmokeOnly')},"
$staticSmokeTo=$staticSmokeFrom+"`n      "+"@{name='lock-hygiene-unit';script='Research\Verification\Run-Gate13R36hLockHygieneUnitV5.ps1';arguments=@('-ProjectPath',`$ProjectPath,'-OutputDirectory',(Join-Path `$preImplementationRoot 'BindingSmokeLockHygiene'),'-BindingSmokeOnly')},"
$staticSummaryFrom='$summary=[ordered]@{schemaVersion=1;summaryKind='
$staticAssertions=@'
$blockWrapperText=[IO.File]::ReadAllText((Join-Path $ProjectPath 'Research\Run-Gate13R36hBlockV9.ps1'))
Add-Assertion 'expected-negative-lock-hygiene-source' ($blockWrapperText.Contains('Invoke-Gate10RPostExitQuiescenceV3')-and$blockWrapperText.Contains('-Role expected-negative')-and$blockWrapperText.Contains("if(`$ExpectFailure)")) 'Controlled cleanup must be reachable only through the expected-negative branch.'
Add-Assertion 'frozen-lock-module-hash' ((Get-G13R36LowerSha256 (Join-Path $ProjectPath 'Research\Gate10RLockHygieneV3.psm1'))-eq'9eba2284dc90fcf6dbbc59080301c1ac6db14c5029f8adab69db234c94f879d6') 'Frozen Gate10R lock-hygiene module changed.'
$summary=[ordered]@{schemaVersion=1;summaryKind=
'@.TrimEnd()
Apply-AuthorizedOverlay 'Research\Verification\Run-Gate13R36hStaticUnitV9.ps1' 'lock-hygiene-static-coverage-v9' @($(Route $staticListFrom $staticListTo),$(Route $staticSmokeFrom $staticSmokeTo),$(Route $staticSummaryFrom $staticAssertions))

$verifyFrom=@'
    $static=Read-G13R36Json (Join-Path $verificationRoot 'StaticUnit\summary.json');if($static.passed-ne$true){throw 'Static/unit summary failed.'}

    Write-Checkpoint 'running' 'lane-copy-creation' ''
'@.Trim()
$verifyTo=@'
    $static=Read-G13R36Json (Join-Path $verificationRoot 'StaticUnit\summary.json');if($static.passed-ne$true){throw 'Static/unit summary failed.'}
    Write-Checkpoint 'running' 'lock-hygiene-unit' ''
    [void](Invoke-Child '01b-lock-hygiene-unit' (Join-Path $ProjectPath 'Research\Verification\Run-Gate13R36hLockHygieneUnitV5.ps1') @('-ProjectPath',$ProjectPath,'-OutputDirectory',(Join-Path $verificationRoot 'LockHygieneUnit')) 600)
    $lockUnit=Read-G13R36Json (Join-Path $verificationRoot 'LockHygieneUnit\summary.json');if($lockUnit.passed-ne$true-or[int]$lockUnit.failedAssertionCount-ne0){throw 'Expected-negative lock-hygiene unit summary failed.'}

    Write-Checkpoint 'running' 'lane-copy-creation' ''
'@.Trim()
Apply-AuthorizedOverlay 'Research\Verification\Run-Gate13R36hVerificationV9.ps1' 'official-lock-unit-gate-v9' @($(Route $verifyFrom $verifyTo))

$auditFrom=@'
    $staticPath=Join-Path $VerificationRoot 'StaticUnit\summary.json';$static=Read-IfPresent $staticPath
    Add-Assertion 'static-unit' ($null-ne$static-and$static.passed-eq$true-and[int]$static.failedAssertionCount-eq0) 'Static/unit evidence is missing or failed.'
'@.Trim()
$auditTo=@'
    $staticPath=Join-Path $VerificationRoot 'StaticUnit\summary.json';$static=Read-IfPresent $staticPath
    Add-Assertion 'static-unit' ($null-ne$static-and$static.passed-eq$true-and[int]$static.failedAssertionCount-eq0) 'Static/unit evidence is missing or failed.'
    $lockUnitPath=Join-Path $VerificationRoot 'LockHygieneUnit\summary.json';$lockUnit=Read-IfPresent $lockUnitPath
    Add-Assertion 'expected-negative-lock-hygiene-unit' ($null-ne$lockUnit-and$lockUnit.passed-eq$true-and[int]$lockUnit.failedAssertionCount-eq0-and[string]$lockUnit.cleanupResult.mode-eq'controlled-expected-negative-cleanup') 'Lock-hygiene unit evidence is missing, failed, or did not exercise controlled expected-negative cleanup.'
'@.Trim()
$auditSummaryFrom='staticSummarySha256=if(Test-Path $staticPath){Get-G13R36LowerSha256 $staticPath}else{$null};compileSummarySha256='
$auditSummaryTo='staticSummarySha256=if(Test-Path $staticPath){Get-G13R36LowerSha256 $staticPath}else{$null};lockHygieneUnitSummarySha256=if(Test-Path $lockUnitPath){Get-G13R36LowerSha256 $lockUnitPath}else{$null};compileSummarySha256='
Apply-AuthorizedOverlay 'Research\Verification\Run-Gate13R36hValidationOnlyPrePilotAuditV9.ps1' 'validation-audit-lock-unit-binding-v9' @($(Route $auditFrom $auditTo),$(Route $auditSummaryFrom $auditSummaryTo))

$amendmentPath=Join-Path $ProjectPath 'Research\Gate13R_36h_10pct_4Lane_PrePilot_Defect_Repair_Amendment.v9.json'
$planV2Path=Join-Path $ProjectPath 'Research\Gate13R_36h_10pct_4Lane_Pilot_Plan.v2.json'
$planV9Path=Join-Path $ProjectPath 'Research\Gate13R_36h_10pct_4Lane_Pilot_Plan.v9.json'
$plan=Get-Content -LiteralPath $planV2Path -Raw -Encoding UTF8|ConvertFrom-Json
$plan.planId='gate13r-36h-10pct-four-lane-nonformal-pilot-plan-v9'
$plan.pilotAttempt=9
$plan.paths.pilotRootRelativePath='Research/PilotRuns/Gate13R_36h_10pct_4Lane/v9'
$plan.paths.verificationRootRelativePath='Research/Verification/Gate13R_36h_10pct_4Lane/v9'
$plan.paths.cloneRootAbsolutePath='H:/DDM_Final_Project_Gate13R36H/v9'
foreach($lane in @($plan.lanes)){$lane.projectPath=([string]$lane.projectPath).Replace('/v2/','/v9/')}
$plan.upstreamHashes.prePilotDefectRepairAmendment=Get-Hash $amendmentPath
$plan.upstreamHashes|Add-Member -NotePropertyName attempt2StaticFailureSummary -NotePropertyValue (Get-Hash (Join-Path $ProjectPath 'Research\Verification\Gate13R_36h_10pct_4Lane_PreImplementation\v7\StaticUnitV2\summary.json'))
$plan.upstreamHashes|Add-Member -NotePropertyName attempt3DerivationFailure -NotePropertyValue (Get-Hash (Join-Path $ProjectPath 'Research\Gate13R_36h_10pct_4Lane_Attempt3_Derivation_Attempt2_Failure.v1.json'))
$plan.upstreamHashes|Add-Member -NotePropertyName attempt4VerificationFailure -NotePropertyValue (Get-Hash (Join-Path $ProjectPath 'Research\Verification\Gate13R_36h_10pct_4Lane\v4\failure-receipt.json'))
$plan.upstreamHashes|Add-Member -NotePropertyName attempt4LockDiagnosis -NotePropertyValue (Get-Hash (Join-Path $ProjectPath 'Research\Gate13R_36h_10pct_4Lane_v4_Lock_Failure_Diagnosis.v1.json'))
$plan.upstreamHashes|Add-Member -NotePropertyName attempt5DerivationFailure -NotePropertyValue (Get-Hash (Join-Path $ProjectPath 'Research\Gate13R_36h_10pct_4Lane_Attempt5_Derivation_Failure.v1.json'))
$plan.upstreamHashes|Add-Member -NotePropertyName attempt5DerivationManifest -NotePropertyValue (Get-Hash (Join-Path $ProjectPath 'Research\Gate13R_36h_10pct_4Lane_Attempt5_Derivation_Partial_Manifest.v1.json'))
$plan.upstreamHashes|Add-Member -NotePropertyName attempt6DerivationFailure -NotePropertyValue (Get-Hash (Join-Path $ProjectPath 'Research\Gate13R_36h_10pct_4Lane_Attempt6_Derivation_Failure.v1.json'))
$plan.upstreamHashes|Add-Member -NotePropertyName attempt6DerivationManifest -NotePropertyValue (Get-Hash (Join-Path $ProjectPath 'Research\Gate13R_36h_10pct_4Lane_Attempt6_Derivation_Partial_Manifest.v1.json'))
$plan.upstreamHashes|Add-Member -NotePropertyName attempt7StaticFailure -NotePropertyValue (Get-Hash (Join-Path $ProjectPath 'Research\Gate13R_36h_10pct_4Lane_Attempt7_PreImplementation_Static_Failure.v1.json'))
$plan.upstreamHashes|Add-Member -NotePropertyName attempt7StaticSummary -NotePropertyValue (Get-Hash (Join-Path $ProjectPath 'Research\Verification\Gate13R_36h_10pct_4Lane_PreImplementation\v10\StaticUnitV7\summary.json'))
$plan.upstreamHashes|Add-Member -NotePropertyName attempt8DerivationFailure -NotePropertyValue (Get-Hash (Join-Path $ProjectPath 'Research\Gate13R_36h_10pct_4Lane_Attempt8_Derivation_Failure.v1.json'))
$plan.upstreamHashes|Add-Member -NotePropertyName attempt8DerivationManifest -NotePropertyValue (Get-Hash (Join-Path $ProjectPath 'Research\Gate13R_36h_10pct_4Lane_Attempt8_Derivation_Partial_Manifest.v1.json'))
Write-CreateNewJson $planV9Path $plan 60
& (Join-Path $ProjectPath 'Research\Verification\New-Gate13R36hPilotScheduleV9.ps1') -ProjectPath $ProjectPath|Out-Null

function Bound([string]$RelativePath){$path=Join-Path $ProjectPath $RelativePath;return [ordered]@{relativePath=$RelativePath.Replace('\','/');sha256=Get-Hash $path;bytes=[long](Get-Item -LiteralPath $path).Length}}
$provenancePath=Join-Path $ProjectPath 'Research\Gate13R_36h_10pct_4Lane_Provenance.v9.json'
$provenance=[ordered]@{
    schemaVersion=3;provenanceId='gate13r-36h-10pct-four-isolated-editor-lanes-provenance-v9';createdAtUtc=[DateTime]::UtcNow.ToString('o');executionDesignId='gate13r-36h-10pct-four-isolated-editor-lanes-v1';status='NON-FORMAL / EXCLUDED-FROM-FORMAL-ANALYSIS';formalCampaign=$false;formalExecutionAuthorized=$false;pilotExecutionAuthorizedCount=1;pilotExecutionConsumedCount=0;automaticPilotRetryAuthorized=$false;sameAttemptResumeAuthorized=$false
    authorization=Bound 'Research\Gate13R_36h_Redesign_Pilot_Authorization.v1.json';specification=Bound 'Research\Gate13R_36h_10pct_4Lane_Redesign_Specification.v1.md';testDesign=Bound 'Research\Gate13R_36h_10pct_4Lane_Test_Design.v1.md';readinessAmendment=Bound 'Research\Gate13R_36h_10pct_4Lane_Readiness_Amendment.v1.json';executionAuthorization=Bound 'Research\Gate13R_36h_10pct_4Lane_PrePilot_Defect_Repair_Amendment.v9.json';config=Bound 'Research\Gate13R_36h_10pct_4Lane_Pilot_Plan.v9.json';schedule=Bound 'Research\Gate13R_36h_10pct_4Lane_Pilot_Schedule.v9.json';scheduleGeneration=Bound 'Research\Gate13R_36h_10pct_4Lane_Pilot_Schedule_Generation.v9.json';preservationBaseline=Bound 'Research\Gate13R_36h_10pct_4Lane_PreWrite_Preservation_Baseline.v1.json';commandDerivation=Bound 'Research\Gate13R_36h_Concurrency_Command_Derivation.v1.json';attempt2DerivationReceipt=Bound 'Research\Gate13R_36h_10pct_4Lane_Attempt2_Derivation_Receipt.v1.json';attempt2Plan=Bound 'Research\Gate13R_36h_10pct_4Lane_Pilot_Plan.v2.json';attempt2Provenance=Bound 'Research\Gate13R_36h_10pct_4Lane_Provenance.v2.json';attempt2StaticFailureSummary=Bound 'Research\Verification\Gate13R_36h_10pct_4Lane_PreImplementation\v7\StaticUnitV2\summary.json';attempt2StaticFailureReceipt=Bound 'Research\Verification\Gate13R_36h_10pct_4Lane_PreImplementation\v7\StaticUnitV2\failure-receipt.json';attempt2StaticCheckpoint=Bound 'Research\Verification\Gate13R_36h_10pct_4Lane_PreImplementation\v7\StaticUnitV2\checkpoint.json';attempt3Amendment=Bound 'Research\Gate13R_36h_10pct_4Lane_PrePilot_Defect_Repair_Amendment.v3.json';attempt3PrewriteFailure=Bound 'Research\Gate13R_36h_10pct_4Lane_Attempt3_Derivation_Attempt1_Failure.v1.json';attempt3ReverseFailure=Bound 'Research\Gate13R_36h_10pct_4Lane_Attempt3_Derivation_Attempt2_Failure.v1.json';attempt3PartialManifest=Bound 'Research\Gate13R_36h_10pct_4Lane_Attempt3_Derivation_Attempt2_Partial_Manifest.v1.json';attempt4Amendment=Bound 'Research\Gate13R_36h_10pct_4Lane_PrePilot_Defect_Repair_Amendment.v4.json';attempt4Plan=Bound 'Research\Gate13R_36h_10pct_4Lane_Pilot_Plan.v4.json';attempt4Provenance=Bound 'Research\Gate13R_36h_10pct_4Lane_Provenance.v4.json';attempt4DerivationReceipt=Bound 'Research\Gate13R_36h_10pct_4Lane_Attempt4_Derivation_Receipt.v1.json';attempt4VerificationReceipt=Bound 'Research\Verification\Gate13R_36h_10pct_4Lane\v4\execution-receipt.json';attempt4VerificationCheckpoint=Bound 'Research\Verification\Gate13R_36h_10pct_4Lane\v4\verification-checkpoint.json';attempt4VerificationFailure=Bound 'Research\Verification\Gate13R_36h_10pct_4Lane\v4\failure-receipt.json';attempt4VerificationManifest=Bound 'Research\Verification\Gate13R_36h_10pct_4Lane\v4\partial-output-manifest.json';attempt4LockDiagnosis=Bound 'Research\Gate13R_36h_10pct_4Lane_v4_Lock_Failure_Diagnosis.v1.json';attempt5Amendment=Bound 'Research\Gate13R_36h_10pct_4Lane_PrePilot_Defect_Repair_Amendment.v5.json';attempt5GeneratorBuilder=Bound 'Research\Verification\New-Gate13R36hAttempt5GeneratorV1.ps1';attempt5GeneratorReceipt=Bound 'Research\Gate13R_36h_10pct_4Lane_Attempt5_Generator_Derivation_Receipt.v1.json';attempt5DerivationGenerator=Bound 'Research\Verification\New-Gate13R36hAttempt5ArtifactsV1.ps1';attempt5PartialManifest=Bound 'Research\Gate13R_36h_10pct_4Lane_Attempt5_Derivation_Partial_Manifest.v1.json';attempt5FailureReceipt=Bound 'Research\Gate13R_36h_10pct_4Lane_Attempt5_Derivation_Failure.v1.json';attempt5Checkpoint=Bound 'Research\Gate13R_36h_10pct_4Lane_Attempt5_Derivation_Checkpoint.v1.json';attempt6Amendment=Bound 'Research\Gate13R_36h_10pct_4Lane_PrePilot_Defect_Repair_Amendment.v6.json';attempt6GeneratorBuilder=Bound 'Research\Verification\New-Gate13R36hAttempt6GeneratorV1.ps1';attempt6GeneratorReceipt=Bound 'Research\Gate13R_36h_10pct_4Lane_Attempt6_Generator_Derivation_Receipt.v1.json';attempt6DerivationGenerator=Bound 'Research\Verification\New-Gate13R36hAttempt6ArtifactsV1.ps1';attempt6PartialManifest=Bound 'Research\Gate13R_36h_10pct_4Lane_Attempt6_Derivation_Partial_Manifest.v1.json';attempt6FailureReceipt=Bound 'Research\Gate13R_36h_10pct_4Lane_Attempt6_Derivation_Failure.v1.json';attempt6Checkpoint=Bound 'Research\Gate13R_36h_10pct_4Lane_Attempt6_Derivation_Checkpoint.v1.json';attempt7Amendment=Bound 'Research\Gate13R_36h_10pct_4Lane_PrePilot_Defect_Repair_Amendment.v7.json';attempt7GeneratorBuilder=Bound 'Research\Verification\New-Gate13R36hAttempt7GeneratorV1.ps1';attempt7GeneratorReceipt=Bound 'Research\Gate13R_36h_10pct_4Lane_Attempt7_Generator_Derivation_Receipt.v1.json';attempt7DerivationGenerator=Bound 'Research\Verification\New-Gate13R36hAttempt7ArtifactsV1.ps1';attempt7DerivationReceipt=Bound 'Research\Gate13R_36h_10pct_4Lane_Attempt7_Derivation_Receipt.v1.json';attempt7StaticSummary=Bound 'Research\Verification\Gate13R_36h_10pct_4Lane_PreImplementation\v10\StaticUnitV7\summary.json';attempt7PartialManifest=Bound 'Research\Gate13R_36h_10pct_4Lane_Attempt7_PreImplementation_Static_Partial_Manifest.v1.json';attempt7FailureReceipt=Bound 'Research\Gate13R_36h_10pct_4Lane_Attempt7_PreImplementation_Static_Failure.v1.json';attempt7Checkpoint=Bound 'Research\Gate13R_36h_10pct_4Lane_Attempt7_PreImplementation_Static_Checkpoint.v1.json';attempt8Amendment=Bound 'Research\Gate13R_36h_10pct_4Lane_PrePilot_Defect_Repair_Amendment.v8.json';attempt8GeneratorBuilder=Bound 'Research\Verification\New-Gate13R36hAttempt8GeneratorV1.ps1';attempt8GeneratorReceipt=Bound 'Research\Gate13R_36h_10pct_4Lane_Attempt8_Generator_Derivation_Receipt.v1.json';attempt8DerivationGenerator=Bound 'Research\Verification\New-Gate13R36hAttempt8ArtifactsV1.ps1';attempt8PartialManifest=Bound 'Research\Gate13R_36h_10pct_4Lane_Attempt8_Derivation_Partial_Manifest.v1.json';attempt8FailureReceipt=Bound 'Research\Gate13R_36h_10pct_4Lane_Attempt8_Derivation_Failure.v1.json';attempt8Checkpoint=Bound 'Research\Gate13R_36h_10pct_4Lane_Attempt8_Derivation_Checkpoint.v1.json';expectedNegativeLockTestDesign=Bound 'Research\Gate13R_36h_10pct_4Lane_ExpectedNegative_LockHygiene_Test_Design.v5.md';lockHygieneSpecification=Bound 'Research\Gate10R_Attempt3_Lock_Hygiene_Specification.v1.md';lockHygieneModule=Bound 'Research\Gate10RLockHygieneV3.psm1';lockHygieneUnitRunner=Bound 'Research\Verification\Run-Gate13R36hLockHygieneUnitV5.ps1';preImplementationLockHygieneUnitSummary=Bound 'Research\Verification\Gate13R_36h_10pct_4Lane_PreImplementation\v9\LockHygieneUnitV5\summary.json';attempt5OverlayTemplate=Bound 'Research\Verification\Gate13R36hAttempt5AuthorizedOverlayTemplateV1.ps1.txt';attempt9GeneratorBuilder=Bound 'Research\Verification\New-Gate13R36hAttempt9GeneratorV1.ps1';attempt9GeneratorDerivationReceipt=Bound 'Research\Gate13R_36h_10pct_4Lane_Attempt9_Generator_Derivation_Receipt.v1.json';attempt9DerivationGenerator=Bound 'Research\Verification\New-Gate13R36hAttempt9ArtifactsV1.ps1';unityCommand=Bound 'Assets\_Scripts\Research\Editor\Gate13R36hConcurrencyBatchCommandV1.cs';preparationModule=Bound 'Research\Gate13R36hConcurrencyPreparationV9.psm1';blockRunner=Bound 'Research\Run-Gate13R36hBlockV9.ps1';telemetryRunner=Bound 'Research\Run-Gate13R36hTelemetryProbeV9.ps1';laneCopyInitializer=Bound 'Research\Initialize-Gate13R36hLaneCopiesV9.ps1';pilotOrchestrator=Bound 'Research\Run-Gate13R36hConcurrencyPilotV9.ps1';pilotAnalyzer=Bound 'Research\Analyze-Gate13R36hConcurrencyPilotV9.ps1';scheduleGenerator=Bound 'Research\Verification\New-Gate13R36hPilotScheduleV9.ps1';compileRunner=Bound 'Research\Verification\Run-Gate13R36hCompileV1.ps1';staticUnitRunner=Bound 'Research\Verification\Run-Gate13R36hStaticUnitV9.ps1';retainedRegressionRunner=Bound 'Research\Verification\Run-Gate13R36hRetainedRegressionV9.ps1';verificationRunner=Bound 'Research\Verification\Run-Gate13R36hVerificationV9.ps1';validationOnlyAuditRunner=Bound 'Research\Verification\Run-Gate13R36hValidationOnlyPrePilotAuditV9.ps1';gate11BundleManifest=Bound 'Research\FormalScenarios\Gate11R_5pct\v1\bundle-manifest.json';attempt1FailureReceipt=Bound 'Research\Verification\Gate13R_36h_10pct_4Lane\v1\failure-receipt.json';attempt1Checkpoint=Bound 'Research\Verification\Gate13R_36h_10pct_4Lane\v1\verification-checkpoint.json'
    unityEditor=[ordered]@{absolutePath='H:/UnityEditor/2022.3.30f1c1/Editor/Unity.exe';productVersion='2022.3.30f1c1_a6dc00fbe362';sha256='0a69d14cbe2ca82d0a6168da8156d9e0dd138a6b7d0260dcdea31fd3957ca9cf'}
    paths=[ordered]@{verificationRoot='Research/Verification/Gate13R_36h_10pct_4Lane/v9';pilotRoot='Research/PilotRuns/Gate13R_36h_10pct_4Lane/v9';cloneRoot='H:/DDM_Final_Project_Gate13R36H/v9';reservedFormalRoot='Research/FormalRuns/Gate13R_36h_10pct_4Lane/v1'}
}
Write-CreateNewJson $provenancePath $provenance 70

foreach($relative in $frozen){if((Get-Hash (Join-Path $ProjectPath $relative))-ne[string]$frozenHashes[$relative]){throw "Frozen v1-v8 evidence changed during v9 derivation: $relative"}}
$receipt=[ordered]@{schemaVersion=1;receiptKind='gate13r-36h-prepilot-attempt9-mechanical-derivation-v1';createdAtUtc=[DateTime]::UtcNow.ToString('o');amendmentRelativePath='Research/Gate13R_36h_10pct_4Lane_PrePilot_Defect_Repair_Amendment.v9.json';amendmentSha256=Get-Hash $amendmentPath;derivations=$derivations.ToArray();authorizedOverlays=$authorizedOverlays.ToArray();planV2Sha256=Get-Hash $planV2Path;planV9Sha256=Get-Hash $planV9Path;scheduleV9Sha256=Get-Hash (Join-Path $ProjectPath 'Research\Gate13R_36h_10pct_4Lane_Pilot_Schedule.v9.json');provenanceV9Sha256=Get-Hash $provenancePath;attempt2EvidencePreserved=$true;attempt4EvidencePreserved=$true;attempt5EvidencePreserved=$true;attempt6EvidencePreserved=$true;attempt7EvidencePreserved=$true;attempt8EvidencePreserved=$true;pilotRootCreated=$false;formalCampaign=$false;passed=$true}
Write-CreateNewJson (Join-Path $ProjectPath 'Research\Gate13R_36h_10pct_4Lane_Attempt9_Derivation_Receipt.v1.json') $receipt 90
$receipt|ConvertTo-Json -Depth 8
