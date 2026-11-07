[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$ProjectPath,
    [string]$OutputPath='Research\Gate13R_48h_10pct_3Lane_Provenance.v1.json',
    [switch]$BindingSmokeOnly
)
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
$ProjectPath=[IO.Path]::GetFullPath($ProjectPath);if(-not[IO.Path]::IsPathRooted($OutputPath)){$OutputPath=Join-Path $ProjectPath $OutputPath};$OutputPath=[IO.Path]::GetFullPath($OutputPath)
if($BindingSmokeOnly){Write-Output("BINDING-SMOKE-PASSED|New-Gate13R48h3LaneProvenanceV1|$OutputPath");exit 0}
$expected=[IO.Path]::GetFullPath((Join-Path $ProjectPath 'Research\Gate13R_48h_10pct_3Lane_Provenance.v1.json'));if($OutputPath-ne$expected){throw 'Provenance output differs from the frozen path.'};if(Test-Path $OutputPath){throw 'Create-new provenance already exists.'}
Import-Module (Join-Path $ProjectPath 'Research\Gate13R48h3LanePreparationV1.psm1') -Force
function Ref([string]$relative){$full=Join-Path $ProjectPath $relative;$item=Get-Item $full -ErrorAction Stop;return [pscustomobject][ordered]@{relativePath=$relative.Replace('\','/');sha256=Get-G13R48LowerSha256 $full;rawBytes=[long]$item.Length}}
$sourceMap=[ordered]@{
    selection='Research\Gate13R_LowerLane_Stability_Selection.v1.json'
    specification='Research\Gate13R_48h_10pct_3Lane_Redesign_Specification.v1.md'
    testDesign='Research\Gate13R_48h_10pct_3Lane_Test_Design.v1.md'
    executionAuthorization='Research\Gate13R_48h_10pct_3Lane_Authorization_Amendment.v1.json'
    config='Research\Gate13R_48h_10pct_3Lane_Pilot_Plan.v1.json'
    schedule='Research\Gate13R_48h_10pct_3Lane_Pilot_Schedule.v1.json'
    scheduleGeneration='Research\Gate13R_48h_10pct_3Lane_Pilot_Schedule_Generation.v1.json'
    unityCommand='Assets\_Scripts\Research\Editor\Gate13R48h3LaneBatchCommandV1.cs'
}
$refs=@{};foreach($key in $sourceMap.Keys){$refs[$key]=Ref $sourceMap[$key]}
$plan=Read-G13R48Json (Join-Path $ProjectPath $sourceMap.config);if([string]$plan.upstreamHashes.selection-ne[string]$refs.selection.sha256-or[string]$plan.upstreamHashes.specification-ne[string]$refs.specification.sha256-or[string]$plan.upstreamHashes.testDesign-ne[string]$refs.testDesign.sha256-or[string]$plan.upstreamHashes.authorizationAmendment-ne[string]$refs.executionAuthorization.sha256-or[string]$plan.upstreamHashes.unityCommand-ne[string]$refs.unityCommand.sha256){throw 'Pilot plan source hashes are stale.'}
$artifactSources=[ordered]@{
    selection=$sourceMap.selection;specification=$sourceMap.specification;test_design=$sourceMap.testDesign;authorization_amendment=$sourceMap.executionAuthorization;pilot_plan=$sourceMap.config;pilot_schedule=$sourceMap.schedule;schedule_generation=$sourceMap.scheduleGeneration;unity_command=$sourceMap.unityCommand
    preparation_module='Research\Gate13R48h3LanePreparationV1.psm1';lane_copy_initializer='Research\Initialize-Gate13R48h3LaneCopiesV1.ps1';telemetry_probe='Research\Run-Gate13R48h3LaneTelemetryProbeV1.ps1';block_runner='Research\Run-Gate13R48h3LaneBlockV1.ps1';license_probe='Research\Run-Gate13R48h3LaneLicenseProbeV1.ps1';pilot_runner='Research\Run-Gate13R48h3LanePilotV1.ps1';pilot_analyzer='Research\Analyze-Gate13R48h3LanePilotV1.ps1'
    plan_generator='Research\Verification\New-Gate13R48h3LanePlanV1.ps1';schedule_generator='Research\Verification\New-Gate13R48h3LaneScheduleV1.ps1';provenance_generator='Research\Verification\New-Gate13R48h3LaneProvenanceV1.ps1';compile_runner='Research\Verification\Run-Gate13R48h3LaneCompileV1.ps1';bootstrap_runner='Research\Verification\Run-Gate13R48h3LaneBootstrapCompileV1.ps1';static_unit_runner='Research\Verification\Run-Gate13R48h3LaneStaticUnitV1.ps1';binding_smoke_runner='Research\Verification\Run-Gate13R48h3LaneBindingSmokeV1.ps1';retained_regression_runner='Research\Verification\Run-Gate13R48h3LaneRetainedRegressionV1.ps1';verification_runner='Research\Verification\Run-Gate13R48h3LaneVerificationV1.ps1';licensing_stress_runner='Research\Verification\Run-Gate13R48h3LaneLicensingStressV1.ps1';validation_only_audit_runner='Research\Verification\Run-Gate13R48h3LaneValidationOnlyPrePilotAuditV1.ps1';environment_stabilizer='Research\Verification\Wait-Gate13R48h3LaneEnvironmentStabilizationV1.ps1'
    compile_summary='Research\Verification\Gate13R_48h_10pct_3Lane_PreImplementation\v1\Compile\summary.json';final_static_summary='Research\Verification\Gate13R_48h_10pct_3Lane_PreImplementation\v1\StaticUnitV5\summary.json';final_binding_summary='Research\Verification\Gate13R_48h_10pct_3Lane_PreImplementation\v1\BindingSmokeV4\summary.json'
    gate11_bundle_manifest='Research\FormalScenarios\Gate11R_5pct\v1\bundle-manifest.json';gate11_matrix='Research\FormalScenarios\Gate11R_5pct\v1\formal-scenario-matrix.json';gate11_preregistration='Research\FormalScenarios\Gate11R_5pct\v1\preregistered-analysis.json';campaign_profile_catalog='Research\PlayableExperiments\Gate11R_5pct\v1\campaign-profile-catalog.json';algorithm_preset_catalog='Research\PlayableExperiments\Gate11R_5pct\v1\algorithm-preset-catalog.json';playable_scene_catalog='Research\PlayableExperiments\Gate11R_5pct\v1\playable-scene-catalog.json';playable_coverage_manifest='Research\PlayableExperiments\Gate11R_5pct\v1\coverage-manifest.json'
    v16_failure_receipt='Research\PilotRuns\Gate13R_36h_10pct_4Lane\v16\failure-receipt.json';v16_partial_manifest='Research\PilotRuns\Gate13R_36h_10pct_4Lane\v16\partial-output-manifest.json';v16_failure_diagnosis='Research\Gate13R_36h_10pct_4Lane_v16_Licensing_Failure_Diagnosis.v1.json';v16_failed_checkpoint='Research\Gate13R_36h_10pct_4Lane_v16_Failed_Checkpoint.md';v17_original_authorization_prompt='Research\Gate13R_36h_10pct_4Lane_v17_Licensing_Repair_Authorization_Prompt.md'
}
$artifacts=New-Object Collections.Generic.List[object];foreach($entry in $artifactSources.GetEnumerator()){$ref=Ref ([string]$entry.Value);$artifacts.Add([pscustomobject][ordered]@{id=[string]$entry.Key;relativePath=[string]$ref.relativePath;sha256=[string]$ref.sha256;rawBytes=[long]$ref.rawBytes})}
$unityPath=[IO.Path]::GetFullPath(([string]$plan.unity.executablePath).Replace('/','\'));$unity=Get-Item $unityPath -ErrorAction Stop;if((Get-G13R48LowerSha256 $unityPath)-ne[string]$plan.unity.executableSha256){throw 'Unity executable hash differs from the frozen plan.'}
$provenance=[ordered]@{
    schemaVersion=1;provenanceId='gate13r-48h-10pct-three-lane-nonformal-pilot-provenance-v1';createdAtUtc=[DateTime]::UtcNow.ToString('o');executionDesignId=[string]$plan.executionDesignId
    selection=$refs.selection;specification=$refs.specification;testDesign=$refs.testDesign;executionAuthorization=$refs.executionAuthorization;config=$refs.config;schedule=$refs.schedule;scheduleGeneration=$refs.scheduleGeneration;unityCommand=$refs.unityCommand
    unityExecutable=[ordered]@{absolutePath=$unityPath.Replace('\','/');sha256=Get-G13R48LowerSha256 $unityPath;rawBytes=[long]$unity.Length;productVersion=[string]$plan.unity.productVersion}
    artifacts=$artifacts.ToArray();processIdentityRule='pid-at-os-process-start-time-utc-v1';laneCount=3;precisionRelativeHalfWidth=0.10;hardCap=$null;readinessP95MaximumHours=42;formalHardMaximumHours=48;licensingStressWaves=172;licensingStressFreshUnityProcesses=516
    pilotExecutionAuthorizedCount=1;formalCampaign=$false;formalExecutionAuthorized=$false;gate14Authorized=$false;automaticRetryAuthorized=$false;automaticResumeAuthorized=$false;historicalFourLaneV16Excluded=$true
}
Write-G13R48CreateNewUtf8NoBomJson $OutputPath $provenance 60;Write-Host("Provenance created: {0}"-f$OutputPath)-ForegroundColor Green;exit 0
