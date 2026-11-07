[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$ProjectPath)

$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$ProjectPath=[IO.Path]::GetFullPath($ProjectPath)
$utf8=New-Object Text.UTF8Encoding($false,$true)
function Hash([string]$Path){return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()}
function Write-NewText([string]$Path,[string]$Text){if(Test-Path -LiteralPath $Path){throw "Create-new target exists: $Path"};$parent=Split-Path -Parent $Path;if(-not(Test-Path -LiteralPath $parent -PathType Container)){New-Item -ItemType Directory -Path $parent|Out-Null};[IO.File]::WriteAllText($Path,$Text,$utf8)}
function Write-NewJson([string]$Path,$Value,[int]$Depth=80){$json=($Value|ConvertTo-Json -Depth $Depth).Replace("`r`n","`n").Replace("`r","`n")+"`n";Write-NewText $Path $json}
function Parse-PowerShell([string]$Path){$tokens=$null;$errors=$null;[void][Management.Automation.Language.Parser]::ParseFile($Path,[ref]$tokens,[ref]$errors);if(@($errors).Count){throw "PowerShell 5.1 parser failure in $Path`: $(@($errors|ForEach-Object Message)-join'; ')"}}
function Bound([string]$RelativePath){$path=Join-Path $ProjectPath $RelativePath;return [ordered]@{relativePath=$RelativePath.Replace('\','/');sha256=Hash $path;bytes=[long](Get-Item -LiteralPath $path).Length}}

$amendmentRelative='Research\Gate13R_36h_10pct_4Lane_PrePilot_Defect_Repair_Amendment.v13.json'
$diagnosisRelative='Research\Gate13R_36h_10pct_4Lane_v12_Telemetry_Compile_Contention_Diagnosis.v1.json'
$bootstrapRelative='Research\Verification\Run-Gate13R36hLaneBootstrapCompileV13.ps1'
foreach($required in @($amendmentRelative,$diagnosisRelative,$bootstrapRelative)){if(-not(Test-Path -LiteralPath (Join-Path $ProjectPath $required) -PathType Leaf)){throw "Required v13 input missing: $required"}}
$amendment=Get-Content -LiteralPath (Join-Path $ProjectPath $amendmentRelative) -Raw -Encoding UTF8|ConvertFrom-Json
if([string]$amendment.status-ne'AUTHORIZED-VERSIONED-PRE-PILOT-DEFECT-REPAIR'-or[bool]$amendment.executionBoundary.formalCampaignAuthorized-ne$false){throw 'Attempt-13 amendment boundary is invalid.'}
if([string]$amendment.upstreamDiagnosis.sha256-ne(Hash (Join-Path $ProjectPath $diagnosisRelative))){throw 'Attempt-13 amendment does not bind the v12 diagnosis.'}
Parse-PowerShell (Join-Path $ProjectPath $bootstrapRelative)

$formalRoot=Join-Path $ProjectPath 'Research\FormalRuns\Gate13R_36h_10pct_4Lane\v1'
$pilotRoot=Join-Path $ProjectPath 'Research\PilotRuns\Gate13R_36h_10pct_4Lane\v13'
$verificationRoot=Join-Path $ProjectPath 'Research\Verification\Gate13R_36h_10pct_4Lane\v13'
$cloneRoot='H:\DDM_Final_Project_Gate13R36H\v13'
foreach($path in @($formalRoot,$pilotRoot,$verificationRoot,$cloneRoot)){if(Test-Path -LiteralPath $path){throw "Forbidden/create-new root already exists: $path"}}

$sources=[ordered]@{
 'Research\Gate13R36hConcurrencyPreparationV12.psm1'='Research\Gate13R36hConcurrencyPreparationV13.psm1'
 'Research\Run-Gate13R36hBlockV12.ps1'='Research\Run-Gate13R36hBlockV13.ps1'
 'Research\Run-Gate13R36hTelemetryProbeV12.ps1'='Research\Run-Gate13R36hTelemetryProbeV13.ps1'
 'Research\Initialize-Gate13R36hLaneCopiesV12.ps1'='Research\Initialize-Gate13R36hLaneCopiesV13.ps1'
 'Research\Run-Gate13R36hConcurrencyPilotV12.ps1'='Research\Run-Gate13R36hConcurrencyPilotV13.ps1'
 'Research\Analyze-Gate13R36hConcurrencyPilotV12.ps1'='Research\Analyze-Gate13R36hConcurrencyPilotV13.ps1'
 'Research\Verification\New-Gate13R36hPilotScheduleV12.ps1'='Research\Verification\New-Gate13R36hPilotScheduleV13.ps1'
 'Research\Verification\Run-Gate13R36hStaticUnitV12.ps1'='Research\Verification\Run-Gate13R36hStaticUnitV13.ps1'
 'Research\Verification\Run-Gate13R36hRetainedRegressionV12.ps1'='Research\Verification\Run-Gate13R36hRetainedRegressionV13.ps1'
 'Research\Verification\Run-Gate13R36hVerificationV12.ps1'='Research\Verification\Run-Gate13R36hVerificationV13.ps1'
 'Research\Verification\Run-Gate13R36hValidationOnlyPrePilotAuditV12.ps1'='Research\Verification\Run-Gate13R36hValidationOnlyPrePilotAuditV13.ps1'
 'Research\Verification\Run-Gate13R36hLockHygieneUnitV12.ps1'='Research\Verification\Run-Gate13R36hLockHygieneUnitV13.ps1'
}
$v12Evidence=@(
 'Research\Gate13R_36h_10pct_4Lane_PrePilot_Defect_Repair_Amendment.v12.json',
 'Research\Gate13R_36h_10pct_4Lane_Pilot_Plan.v12.json',
 'Research\Gate13R_36h_10pct_4Lane_Pilot_Schedule.v12.json',
 'Research\Gate13R_36h_10pct_4Lane_Pilot_Schedule_Generation.v12.json',
 'Research\Gate13R_36h_10pct_4Lane_Provenance.v12.json',
 'Research\Gate13R_36h_10pct_4Lane_Attempt12_Derivation_Receipt.v1.json',
 'Research\Verification\Gate13R_36h_10pct_4Lane\v12\execution-receipt.json',
 'Research\Verification\Gate13R_36h_10pct_4Lane\v12\verification-checkpoint.json',
 'Research\Verification\Gate13R_36h_10pct_4Lane\v12\failure-receipt.json',
 'Research\Verification\Gate13R_36h_10pct_4Lane\v12\partial-output-manifest.json'
)+@($sources.Keys)
$before=@{}
foreach($relative in $v12Evidence){$path=Join-Path $ProjectPath $relative;if(-not(Test-Path -LiteralPath $path -PathType Leaf)){throw "Frozen v12 evidence missing: $relative"};$before[$relative]=Hash $path}

$derivations=New-Object Collections.Generic.List[object]
foreach($entry in $sources.GetEnumerator()){
    $sourcePath=Join-Path $ProjectPath ([string]$entry.Key)
    $destinationPath=Join-Path $ProjectPath ([string]$entry.Value)
    $sourceText=[IO.File]::ReadAllText($sourcePath)
    $upperCount=[regex]::Matches($sourceText,[regex]::Escape('V12')).Count
    $lowerCount=[regex]::Matches($sourceText,[regex]::Escape('v12')).Count
    if(($upperCount+$lowerCount)-lt1){throw "No active v12 identity found in $($entry.Key)"}
    $derived=$sourceText.Replace('V12','V13').Replace('v12','v13')
    Write-NewText $destinationPath $derived
    Parse-PowerShell $destinationPath
    $derivations.Add([pscustomobject][ordered]@{sourceRelativePath=[string]$entry.Key;sourceSha256=Hash $sourcePath;destinationRelativePath=[string]$entry.Value;destinationSha256=Hash $destinationPath;uppercaseRouteCount=$upperCount;lowercaseRouteCount=$lowerCount;parserPassed=$true})
}

# Overlay the v13 verification with a serial, non-measured, no-workload bootstrap for each newly copied lane.
$verifyPath=Join-Path $ProjectPath 'Research\Verification\Run-Gate13R36hVerificationV13.ps1'
$verify=[IO.File]::ReadAllText($verifyPath)
$verifyAnchor=@'
    $copies=Read-G13R36Json (Join-Path $verificationRoot 'LaneCopies\summary.json');if($copies.passed-ne$true-or[int]$copies.laneCount-ne4){throw 'Four-lane copy creation/audit failed.'}

    Write-Checkpoint 'running' 'four-lane-telemetry' ''
'@
$verifyReplacement=@'
    $copies=Read-G13R36Json (Join-Path $verificationRoot 'LaneCopies\summary.json');if($copies.passed-ne$true-or[int]$copies.laneCount-ne4){throw 'Four-lane copy creation/audit failed.'}

    Write-Checkpoint 'running' 'serial-lane-bootstrap-compile' ''
    $bootstrapPids=New-Object Collections.Generic.List[int]
    foreach($lane in 1..4){
        $laneRecord=@($plan.lanes|Where-Object lane -eq $lane)[0]
        $laneRoot=[IO.Path]::GetFullPath([string]$laneRecord.projectPath)
        $output=Join-Path $laneRoot 'Research\Verification\Gate13R_36h_10pct_4Lane\v13\BootstrapCompile'
        [void](Invoke-Child ('02b-bootstrap-lane-{0:D2}'-f$lane) (Join-Path $ProjectPath 'Research\Verification\Run-Gate13R36hLaneBootstrapCompileV13.ps1') @('-LaneProjectPath',$laneRoot,'-OutputPrefix',$output,'-LaneNumber',[string]$lane,'-AffinityMaskHex',[string]$laneRecord.affinityMaskHex,'-UnityPath',$UnityPath) 1200)
        $bootstrap=Read-G13R36Json ($output+'.summary.json')
        if($bootstrap.passed-ne$true-or$bootstrap.measured-ne$false-or$bootstrap.planningWorkloadExecuted-ne$false-or$bootstrap.naturalLaneLockRelease-ne$true-or$bootstrap.controlledLockCleanupUsed-ne$false){throw "Lane $lane bootstrap summary failed or violated the frozen non-measured boundary."}
        $bootstrapPids.Add([int]$bootstrap.unityProcessId)
        Assert-Quiescent
    }
    if(@($bootstrapPids|Sort-Object -Unique).Count-ne4){throw 'Lane bootstrap did not use four unique Unity processes.'}

    Write-Checkpoint 'running' 'four-lane-telemetry' ''
'@
if(-not$verify.Contains($verifyAnchor)){throw 'Verification bootstrap insertion anchor missing.'}
$verify=$verify.Replace($verifyAnchor,$verifyReplacement)
$telemetryAnchor="if(@(`$telemetryPids|Sort-Object -Unique).Count-ne4){throw 'Telemetry probes did not use four unique Unity processes.'}"
$telemetryReplacement=$telemetryAnchor+";if(@(@(`$telemetryPids)+@(`$bootstrapPids)|Sort-Object -Unique).Count-ne8){throw 'Bootstrap and telemetry did not use eight distinct Unity processes.'}"
if(-not$verify.Contains($telemetryAnchor)){throw 'Verification telemetry uniqueness anchor missing.'}
$verify=$verify.Replace($telemetryAnchor,$telemetryReplacement)
[IO.File]::WriteAllText($verifyPath,$verify,$utf8)
Parse-PowerShell $verifyPath

# Overlay static/unit coverage for the bootstrap policy, runner, binding, and no-workload boundary.
$staticPath=Join-Path $ProjectPath 'Research\Verification\Run-Gate13R36hStaticUnitV13.ps1'
$static=[IO.File]::ReadAllText($staticPath)
$cardinalityAnchor="    Add-Assertion 'pilot-cardinality' (@(`$plan.campaignIds).Count-eq12-and[int]`$plan.measuredBlocksPerCampaign-eq32-and[int]`$plan.totals.measuredBlockProcesses-eq384-and[int]`$plan.totals.measuredSamples-eq1152-and[int]`$plan.totals.pilotUnityProcesses-eq392) 'Pilot cardinalities differ from the frozen design.'"
$cardinalityReplacement=$cardinalityAnchor+"`n    Add-Assertion 'serial-nonmeasured-lane-bootstrap-policy' ([string]`$plan.laneBootstrap.policyId-eq'serial-nonmeasured-fresh-lane-bootstrap-before-concurrent-gates-v1'-and[int]`$plan.laneBootstrap.processes-eq4-and`$plan.laneBootstrap.serial-eq`$true-and`$plan.laneBootstrap.measured-eq`$false-and`$plan.laneBootstrap.executePlanningWorkload-eq`$false-and`$plan.laneBootstrap.controlledLockCleanupAllowed-eq`$false-and[int]`$plan.totals.verificationUnityProcessesMinimum-eq15-and[int]`$plan.totals.pilotUnityProcesses-eq392) 'Lane bootstrap must be serial, non-measured, no-workload, natural-release-only, and excluded from pilot process totals.'"
if(-not$static.Contains($cardinalityAnchor)){throw 'Static bootstrap policy anchor missing.'};$static=$static.Replace($cardinalityAnchor,$cardinalityReplacement)
$scriptListAnchor="'Research\Verification\Run-Gate13R36hValidationOnlyPrePilotAuditV13.ps1','Research\Verification\Run-Gate13R36hLockHygieneUnitV13.ps1'"
$scriptListReplacement="'Research\Verification\Run-Gate13R36hValidationOnlyPrePilotAuditV13.ps1','Research\Verification\Run-Gate13R36hLockHygieneUnitV13.ps1','Research\Verification\Run-Gate13R36hLaneBootstrapCompileV13.ps1'"
if(-not$static.Contains($scriptListAnchor)){throw 'Static script list anchor missing.'};$static=$static.Replace($scriptListAnchor,$scriptListReplacement)
$smokeAnchor="      @{name='telemetry';script='Research\Run-Gate13R36hTelemetryProbeV13.ps1';arguments=@('-LaneProjectPath','H:\DDM_Final_Project_Gate13R36H\v13\lane-01','-OutputDirectory','H:\DDM_Final_Project_Gate13R36H\v13\lane-01\Research\Verification\Gate13R_36h_10pct_4Lane\v13\BindingSmoke','-LaneNumber','1','-AffinityMaskHex','0x000000FF','-BindingSmokeOnly')},"
$smokeReplacement=$smokeAnchor+"`n      @{name='lane-bootstrap';script='Research\Verification\Run-Gate13R36hLaneBootstrapCompileV13.ps1';arguments=@('-LaneProjectPath','H:\DDM_Final_Project_Gate13R36H\v13\lane-01','-OutputPrefix','H:\DDM_Final_Project_Gate13R36H\v13\lane-01\Research\Verification\Gate13R_36h_10pct_4Lane\v13\BindingSmokeBootstrap','-LaneNumber','1','-AffinityMaskHex','0x000000FF','-BindingSmokeOnly')},"
if(-not$static.Contains($smokeAnchor)){throw 'Static bootstrap smoke anchor missing.'};$static=$static.Replace($smokeAnchor,$smokeReplacement)
$wrapperAnchor=@'
$blockWrapperText=[IO.File]::ReadAllText((Join-Path $ProjectPath 'Research\Run-Gate13R36hBlockV13.ps1'))
'@
$wrapperReplacement=@'
$bootstrapRunnerText=[IO.File]::ReadAllText((Join-Path $ProjectPath 'Research\Verification\Run-Gate13R36hLaneBootstrapCompileV13.ps1'))
Add-Assertion 'bootstrap-no-workload-no-cleanup-source' ($bootstrapRunnerText.Contains('planningWorkloadExecuted=$false')-and$bootstrapRunnerText.Contains('controlledLockCleanupUsed=$false')-and$bootstrapRunnerText.Contains('PostProcessing failed')-and-not$bootstrapRunnerText.Contains('RunPlanningWorkload')) 'Bootstrap must run no planning workload, perform no lock cleanup, and fail on IL post-processing contention.'

$blockWrapperText=[IO.File]::ReadAllText((Join-Path $ProjectPath 'Research\Run-Gate13R36hBlockV13.ps1'))
'@
if(-not$static.Contains($wrapperAnchor)){throw 'Static bootstrap source anchor missing.'};$static=$static.Replace($wrapperAnchor,$wrapperReplacement)
[IO.File]::WriteAllText($staticPath,$static,$utf8)
Parse-PowerShell $staticPath

# Overlay validation-only audit to require four successful bootstrap summaries and PIDs disjoint from telemetry.
$auditPath=Join-Path $ProjectPath 'Research\Verification\Run-Gate13R36hValidationOnlyPrePilotAuditV13.ps1'
$audit=[IO.File]::ReadAllText($auditPath)
$copyAnchor="    Add-Assertion 'four-isolated-project-copies' `$copyPassed 'All four scientific trees must be hash-identical normal copies with no reparse points or hard links.'"
$copyReplacement=$copyAnchor+@'


    $bootstrapPassed=$true;$bootstrapPids=New-Object Collections.Generic.List[int];$bootstrapHashes=New-Object Collections.Generic.List[string]
    foreach($lane in 1..4){$laneRoot=('H:\DDM_Final_Project_Gate13R36H\v13\lane-{0:D2}'-f$lane);$bootstrapPath=(Join-Path $laneRoot 'Research\Verification\Gate13R_36h_10pct_4Lane\v13\BootstrapCompile')+'.summary.json';$bootstrap=Read-IfPresent $bootstrapPath;if($null-eq$bootstrap-or$bootstrap.passed-ne$true-or$bootstrap.measured-ne$false-or$bootstrap.planningWorkloadExecuted-ne$false-or$bootstrap.naturalLaneLockRelease-ne$true-or$bootstrap.controlledLockCleanupUsed-ne$false){$bootstrapPassed=$false}else{$bootstrapPids.Add([int]$bootstrap.unityProcessId);$bootstrapHashes.Add((Get-G13R36LowerSha256 $bootstrapPath))}}
    Add-Assertion 'serial-nonmeasured-lane-bootstrap' ($bootstrapPassed-and@($bootstrapPids|Sort-Object -Unique).Count-eq4) 'Each fresh lane requires one successful serial, non-measured, no-workload bootstrap with natural lock release.'
'@
if(-not$audit.Contains($copyAnchor)){throw 'Audit bootstrap insertion anchor missing.'};$audit=$audit.Replace($copyAnchor,$copyReplacement)
$telemetryAuditAnchor="    Add-Assertion 'four-lane-telemetry' (`$telemetryPassed-and@(`$telemetryPids|Sort-Object -Unique).Count-eq4) 'Each lane requires its own positive PSAPI/CIM result and unique Unity PID.'"
$telemetryAuditReplacement=$telemetryAuditAnchor+"`n    Add-Assertion 'bootstrap-telemetry-fresh-process-separation' (@(@(`$bootstrapPids)+@(`$telemetryPids)|Sort-Object -Unique).Count-eq8) 'Bootstrap and concurrent telemetry must use eight distinct Unity processes.'"
if(-not$audit.Contains($telemetryAuditAnchor)){throw 'Audit telemetry separation anchor missing.'};$audit=$audit.Replace($telemetryAuditAnchor,$telemetryAuditReplacement)
$summaryAuditAnchor='copySummarySha256=if(Test-Path $copySummaryPath){Get-G13R36LowerSha256 $copySummaryPath}else{$null};blockVerificationSummarySha256='
$summaryAuditReplacement='copySummarySha256=if(Test-Path $copySummaryPath){Get-G13R36LowerSha256 $copySummaryPath}else{$null};laneBootstrapSummarySha256s=$bootstrapHashes.ToArray();blockVerificationSummarySha256='
if(-not$audit.Contains($summaryAuditAnchor)){throw 'Audit bootstrap hash anchor missing.'};$audit=$audit.Replace($summaryAuditAnchor,$summaryAuditReplacement)
[IO.File]::WriteAllText($auditPath,$audit,$utf8)
Parse-PowerShell $auditPath

# Build the versioned v13 plan without changing pilot or formal statistical semantics.
$planV12Path=Join-Path $ProjectPath 'Research\Gate13R_36h_10pct_4Lane_Pilot_Plan.v12.json'
$planV13Path=Join-Path $ProjectPath 'Research\Gate13R_36h_10pct_4Lane_Pilot_Plan.v13.json'
$plan=Get-Content -LiteralPath $planV12Path -Raw -Encoding UTF8|ConvertFrom-Json
$plan.planId='gate13r-36h-10pct-four-lane-nonformal-pilot-plan-v13'
$plan.pilotAttempt=13
$plan.paths.pilotRootRelativePath='Research/PilotRuns/Gate13R_36h_10pct_4Lane/v13'
$plan.paths.verificationRootRelativePath='Research/Verification/Gate13R_36h_10pct_4Lane/v13'
$plan.paths.cloneRootAbsolutePath='H:/DDM_Final_Project_Gate13R36H/v13'
foreach($lane in @($plan.lanes)){$lane.projectPath=([string]$lane.projectPath).Replace('/v12/','/v13/')}
$plan.upstreamHashes.prePilotDefectRepairAmendment=Hash (Join-Path $ProjectPath $amendmentRelative)
$plan.upstreamHashes|Add-Member -NotePropertyName attempt12Plan -NotePropertyValue (Hash $planV12Path)
$plan.upstreamHashes|Add-Member -NotePropertyName attempt12VerificationFailure -NotePropertyValue (Hash (Join-Path $ProjectPath 'Research\Verification\Gate13R_36h_10pct_4Lane\v12\failure-receipt.json'))
$plan.upstreamHashes|Add-Member -NotePropertyName attempt12VerificationCheckpoint -NotePropertyValue (Hash (Join-Path $ProjectPath 'Research\Verification\Gate13R_36h_10pct_4Lane\v12\verification-checkpoint.json'))
$plan.upstreamHashes|Add-Member -NotePropertyName attempt12TelemetryDiagnosis -NotePropertyValue (Hash (Join-Path $ProjectPath $diagnosisRelative))
$plan.upstreamHashes|Add-Member -NotePropertyName laneBootstrapRunnerV13 -NotePropertyValue (Hash (Join-Path $ProjectPath $bootstrapRelative))
$plan.totals.verificationUnityProcessesMinimum=15
$plan.totals|Add-Member -NotePropertyName laneBootstrapProcesses -NotePropertyValue 4
$plan|Add-Member -NotePropertyName laneBootstrap -NotePropertyValue ([pscustomobject][ordered]@{policyId='serial-nonmeasured-fresh-lane-bootstrap-before-concurrent-gates-v1';laneOrder=@(1,2,3,4);processes=4;oneFreshUnityEditorProcessPerLane=$true;serial=$true;measured=$false;executePlanningWorkload=$false;excludedFromFormalAnalysis=$true;requiredBeforeConcurrentTelemetry=$true;naturalLockReleaseSeconds=60;controlledLockCleanupAllowed=$false;includedInPilotUnityProcessCount=$false})
Write-NewJson $planV13Path $plan 80

# Generate the schedule and its deterministic receipt from the v13 plan.
$scheduleGenerator=Join-Path $ProjectPath 'Research\Verification\New-Gate13R36hPilotScheduleV13.ps1'
&'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe' -NoProfile -ExecutionPolicy Bypass -File $scheduleGenerator -ProjectPath $ProjectPath
if($LASTEXITCODE-ne0){throw "V13 schedule generation failed with exit $LASTEXITCODE."}

# Extend v12 provenance, preserving all earlier bindings while making every active artifact v13-specific.
$provenanceV12Path=Join-Path $ProjectPath 'Research\Gate13R_36h_10pct_4Lane_Provenance.v12.json'
$provenancePath=Join-Path $ProjectPath 'Research\Gate13R_36h_10pct_4Lane_Provenance.v13.json'
$provenance=Get-Content -LiteralPath $provenanceV12Path -Raw -Encoding UTF8|ConvertFrom-Json
$provenance.schemaVersion=4
$provenance.provenanceId='gate13r-36h-10pct-four-isolated-editor-lanes-provenance-v13'
$provenance.createdAtUtc=[DateTime]::UtcNow.ToString('o')
$provenance.executionAuthorization=Bound $amendmentRelative
$provenance.config=Bound 'Research\Gate13R_36h_10pct_4Lane_Pilot_Plan.v13.json'
$provenance.schedule=Bound 'Research\Gate13R_36h_10pct_4Lane_Pilot_Schedule.v13.json'
$provenance.scheduleGeneration=Bound 'Research\Gate13R_36h_10pct_4Lane_Pilot_Schedule_Generation.v13.json'
$provenance.preparationModule=Bound 'Research\Gate13R36hConcurrencyPreparationV13.psm1'
$provenance.blockRunner=Bound 'Research\Run-Gate13R36hBlockV13.ps1'
$provenance.telemetryRunner=Bound 'Research\Run-Gate13R36hTelemetryProbeV13.ps1'
$provenance.laneCopyInitializer=Bound 'Research\Initialize-Gate13R36hLaneCopiesV13.ps1'
$provenance.pilotOrchestrator=Bound 'Research\Run-Gate13R36hConcurrencyPilotV13.ps1'
$provenance.pilotAnalyzer=Bound 'Research\Analyze-Gate13R36hConcurrencyPilotV13.ps1'
$provenance.scheduleGenerator=Bound 'Research\Verification\New-Gate13R36hPilotScheduleV13.ps1'
$provenance.staticUnitRunner=Bound 'Research\Verification\Run-Gate13R36hStaticUnitV13.ps1'
$provenance.retainedRegressionRunner=Bound 'Research\Verification\Run-Gate13R36hRetainedRegressionV13.ps1'
$provenance.verificationRunner=Bound 'Research\Verification\Run-Gate13R36hVerificationV13.ps1'
$provenance.validationOnlyAuditRunner=Bound 'Research\Verification\Run-Gate13R36hValidationOnlyPrePilotAuditV13.ps1'
$provenance.lockHygieneUnitRunner=Bound 'Research\Verification\Run-Gate13R36hLockHygieneUnitV13.ps1'
$provenance.paths.verificationRoot='Research/Verification/Gate13R_36h_10pct_4Lane/v13'
$provenance.paths.pilotRoot='Research/PilotRuns/Gate13R_36h_10pct_4Lane/v13'
$provenance.paths.cloneRoot='H:/DDM_Final_Project_Gate13R36H/v13'
$provenance|Add-Member -NotePropertyName attempt12Amendment -NotePropertyValue (Bound 'Research\Gate13R_36h_10pct_4Lane_PrePilot_Defect_Repair_Amendment.v12.json')
$provenance|Add-Member -NotePropertyName attempt12Plan -NotePropertyValue (Bound 'Research\Gate13R_36h_10pct_4Lane_Pilot_Plan.v12.json')
$provenance|Add-Member -NotePropertyName attempt12Provenance -NotePropertyValue (Bound 'Research\Gate13R_36h_10pct_4Lane_Provenance.v12.json')
$provenance|Add-Member -NotePropertyName attempt12DerivationReceipt -NotePropertyValue (Bound 'Research\Gate13R_36h_10pct_4Lane_Attempt12_Derivation_Receipt.v1.json')
$provenance|Add-Member -NotePropertyName attempt12VerificationReceipt -NotePropertyValue (Bound 'Research\Verification\Gate13R_36h_10pct_4Lane\v12\execution-receipt.json')
$provenance|Add-Member -NotePropertyName attempt12VerificationCheckpoint -NotePropertyValue (Bound 'Research\Verification\Gate13R_36h_10pct_4Lane\v12\verification-checkpoint.json')
$provenance|Add-Member -NotePropertyName attempt12VerificationFailure -NotePropertyValue (Bound 'Research\Verification\Gate13R_36h_10pct_4Lane\v12\failure-receipt.json')
$provenance|Add-Member -NotePropertyName attempt12VerificationManifest -NotePropertyValue (Bound 'Research\Verification\Gate13R_36h_10pct_4Lane\v12\partial-output-manifest.json')
$provenance|Add-Member -NotePropertyName attempt12TelemetryDiagnosis -NotePropertyValue (Bound $diagnosisRelative)
$provenance|Add-Member -NotePropertyName attempt13Amendment -NotePropertyValue (Bound $amendmentRelative)
$provenance|Add-Member -NotePropertyName attempt13DerivationGenerator -NotePropertyValue (Bound 'Research\Verification\New-Gate13R36hAttempt13ArtifactsV1.ps1')
$provenance|Add-Member -NotePropertyName laneBootstrapRunner -NotePropertyValue (Bound $bootstrapRelative)
Write-NewJson $provenancePath $provenance 100

# Verify frozen v12 byte identity after the v13 derivation.
$preserved=New-Object Collections.Generic.List[object]
foreach($relative in $v12Evidence){$after=Hash (Join-Path $ProjectPath $relative);$same=$after-eq[string]$before[$relative];$preserved.Add([pscustomobject][ordered]@{relativePath=$relative.Replace('\','/');beforeSha256=[string]$before[$relative];afterSha256=$after;preserved=$same});if(-not$same){throw "Frozen v12 evidence changed: $relative"}}
$receiptPath=Join-Path $ProjectPath 'Research\Gate13R_36h_10pct_4Lane_Attempt13_Derivation_Receipt.v1.json'
$receipt=[ordered]@{schemaVersion=1;receiptKind='gate13r-36h-prepilot-attempt13-fresh-clone-bootstrap-derivation-v1';createdAtUtc=[DateTime]::UtcNow.ToString('o');status='NON-EXECUTING-PRE-PILOT-REPAIR';amendmentRelativePath=$amendmentRelative.Replace('\','/');amendmentSha256=Hash (Join-Path $ProjectPath $amendmentRelative);diagnosisRelativePath=$diagnosisRelative.Replace('\','/');diagnosisSha256=Hash (Join-Path $ProjectPath $diagnosisRelative);derivations=$derivations.ToArray();overlays=@('serial-lane-bootstrap-in-verification','bootstrap-static-unit-coverage','bootstrap-validation-audit-coverage');bootstrapRunnerSha256=Hash (Join-Path $ProjectPath $bootstrapRelative);planV13Sha256=Hash $planV13Path;scheduleV13Sha256=Hash (Join-Path $ProjectPath 'Research\Gate13R_36h_10pct_4Lane_Pilot_Schedule.v13.json');scheduleGenerationV13Sha256=Hash (Join-Path $ProjectPath 'Research\Gate13R_36h_10pct_4Lane_Pilot_Schedule_Generation.v13.json');provenanceV13Sha256=Hash $provenancePath;frozenV12Evidence=$preserved.ToArray();frozenV12EvidencePreserved=$true;verificationRootCreated=$false;cloneRootCreated=$false;pilotRootCreated=$false;formalRootCreated=$false;pilotStarted=$false;formalCampaign=$false;passed=$true}
Write-NewJson $receiptPath $receipt 100
$receipt|ConvertTo-Json -Depth 8
