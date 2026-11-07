[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$ProjectPath,
    [Parameter(Mandatory=$true)][string]$OutputDirectory,
    [switch]$BindingSmokeOnly
)

$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$ProjectPath=[IO.Path]::GetFullPath($ProjectPath)
$OutputDirectory=[IO.Path]::GetFullPath($OutputDirectory)
$officialRoot=[IO.Path]::GetFullPath((Join-Path $ProjectPath 'Research\Verification\Gate13R_36h_10pct_4Lane\v2'))
$preImplementationRoot=[IO.Path]::GetFullPath((Join-Path $ProjectPath 'Research\Verification\Gate13R_36h_10pct_4Lane_PreImplementation'))
$insideAuthorizedRoot=$OutputDirectory.StartsWith($officialRoot.TrimEnd('\')+'\',[StringComparison]::OrdinalIgnoreCase)-or$OutputDirectory.StartsWith($preImplementationRoot.TrimEnd('\')+'\',[StringComparison]::OrdinalIgnoreCase)
if(-not$insideAuthorizedRoot){throw 'Static/unit output is outside an authorized verification root.'}
if($BindingSmokeOnly){Write-Output("BINDING-SMOKE-PASSED|Run-Gate13R36hStaticUnitV2|$ProjectPath");exit 0}
if(Test-Path -LiteralPath $OutputDirectory){throw "Create-new static/unit output exists: $OutputDirectory"}

$modulePath=Join-Path $ProjectPath 'Research\Gate13R36hConcurrencyPreparationV2.psm1'
$analysisModulePath=Join-Path $ProjectPath 'Research\Gate12RProcessReusePreparationV2.psm1'
Import-Module $modulePath -Force
Import-Module $analysisModulePath -Force
New-Item -ItemType Directory -Path $OutputDirectory -Force|Out-Null
$assertions=New-Object Collections.Generic.List[object]
$failures=New-Object Collections.Generic.List[string]
function Add-Assertion([string]$Name,[bool]$Passed,[string]$Detail){$script:assertions.Add([pscustomobject][ordered]@{name=$Name;passed=$Passed;detail=$Detail});if(-not$Passed){$script:failures.Add("$Name`: $Detail")}}

try{
    $planPath=Join-Path $ProjectPath 'Research\Gate13R_36h_10pct_4Lane_Pilot_Plan.v2.json'
    $schedulePath=Join-Path $ProjectPath 'Research\Gate13R_36h_10pct_4Lane_Pilot_Schedule.v2.json'
    $scheduleReceiptPath=Join-Path $ProjectPath 'Research\Gate13R_36h_10pct_4Lane_Pilot_Schedule_Generation.v2.json'
    $baselinePath=Join-Path $ProjectPath 'Research\Gate13R_36h_10pct_4Lane_PreWrite_Preservation_Baseline.v1.json'
    $provenancePath=Join-Path $ProjectPath 'Research\Gate13R_36h_10pct_4Lane_Provenance.v2.json'
    $plan=Read-G13R36Json $planPath
    $scheduleDocument=Read-G13R36Json $schedulePath
    $scheduleReceipt=Read-G13R36Json $scheduleReceiptPath
    $provenance=Read-G13R36Json $provenancePath

    Add-Assertion 'plan-boundary' ([string]$plan.planId-eq'gate13r-36h-10pct-four-lane-nonformal-pilot-plan-v1'-and$plan.formalCampaign-eq$false-and$plan.excludedFromFormalAnalysis-eq$true) 'Plan must remain non-formal and excluded from formal analysis.'
    Add-Assertion 'matrix-and-lanes' (([int]$plan.formalProjectionCampaignCounts.'four-algorithm-shared-goal-v1'+[int]$plan.formalProjectionCampaignCounts.'per-agent-heterogeneous-goal-v1'+[int]$plan.formalProjectionCampaignCounts.'grouped-field-heterogeneous-goal-v1')-eq74-and@($plan.lanes).Count-eq4) 'Expected 74 campaigns and four isolated lanes.'
    Add-Assertion 'precision-10pct-uncapped' ([math]::Abs([double]$plan.precision.relativeHalfWidth-0.10)-lt1e-15-and[math]::Abs([double]$plan.precision.logHalfWidth-[math]::Log(1.10))-lt1e-15-and$null-eq$plan.precision.hardCap) 'Precision must be 10%, log(1.10), with no hard cap.'
    Add-Assertion 'runtime-gates' ([double]$plan.runtimeProjection.maximumReadinessP95Hours-eq27.0-and[double]$plan.runtimeProjection.hardFormalEndToEndHours-eq36.0) 'Readiness p95 and hard wall-clock gates must be 27 h and 36 h.'
    Add-Assertion 'pilot-cardinality' (@($plan.campaignIds).Count-eq12-and[int]$plan.measuredBlocksPerCampaign-eq32-and[int]$plan.totals.measuredBlockProcesses-eq384-and[int]$plan.totals.measuredSamples-eq1152-and[int]$plan.totals.pilotUnityProcesses-eq392) 'Pilot cardinalities differ from the frozen design.'

    $preservation=Test-G13R36PreservationBaseline -ProjectPath $ProjectPath -BaselinePath $baselinePath
    Add-Assertion 'protected-input-preservation' ([bool]$preservation.passed) "Protected files checked: $($preservation.checkedFileCount)."
    foreach($formal in @('Research\FormalRuns\Gate13R_ProcessReuse_5pct\v1','Research\FormalRuns\Gate13R_36h_10pct_4Lane\v1')){Add-Assertion ('formal-root-absent-'+([IO.Path]::GetFileName((Split-Path $formal -Parent)))) (-not(Test-Path -LiteralPath (Join-Path $ProjectPath $formal))) "Forbidden formal root: $formal"}
    Add-Assertion 'pilot-root-absent' (-not(Test-Path -LiteralPath (Join-Path $ProjectPath 'Research\PilotRuns\Gate13R_36h_10pct_4Lane\v2'))) 'The sole pilot must not have started during static/unit validation.'

    $campaigns=@(Get-G13R36PilotCampaigns -ProjectPath $ProjectPath -Plan $plan)
    $regenerated=@(Get-G13R36MeasuredSchedule -Plan $plan -Campaigns $campaigns)
    $scheduleTest=Test-G13R36Schedule -Schedule $regenerated
    Add-Assertion 'schedule-core-validation' ([bool]$scheduleTest.passed) ($scheduleTest.errors-join'; ')
    Add-Assertion 'schedule-deterministic-rows' ((ConvertTo-G13R36JsonText -Value $regenerated -Depth 30)-ceq(ConvertTo-G13R36JsonText -Value @($scheduleDocument.rows) -Depth 30)) 'Regenerated rows must be byte-stable after canonical serialization.'
    Add-Assertion 'schedule-receipt-hash' ([string]$scheduleReceipt.scheduleSha256-eq(Get-G13R36LowerSha256 $schedulePath)-and[string]$scheduleReceipt.deterministicRegenerationSha256-eq(Get-G13R36LowerSha256 $schedulePath)-and$scheduleReceipt.passed-eq$true) 'Schedule receipt does not bind the active schedule.'

    $expanded=New-Object Collections.Generic.List[object]
    foreach($row in $regenerated){$order=@(Get-G13R36WilliamsRow -Algorithms @($row.algorithms) -Block ([int]$row.block));for($position=0;$position-lt$order.Count;$position++){$expanded.Add([pscustomobject]@{campaignId=[string]$row.campaignId;cohort=[string]$row.comparisonCohortId;lane=[int]$row.lane;block=[int]$row.block;algorithm=[string]$order[$position];position=$position+1;predecessor=$(if($position-eq0){'NONE'}else{[string]$order[$position-1]})})}}
    $positionBalance=$true;foreach($group in @($expanded|Group-Object cohort,algorithm,position)){$laneCounts=@($group.Group|Group-Object lane|Sort-Object Name|Select-Object -ExpandProperty Count);if($laneCounts.Count-ne4-or@($laneCounts|Sort-Object -Unique).Count-ne1){$positionBalance=$false}}
    Add-Assertion 'algorithm-position-lane-balance' $positionBalance 'Every cohort/algorithm/position cell must be equal across all four lanes.'
    $carryoverBalance=$true;foreach($campaign in $campaigns){$rows=@($expanded|Where-Object campaignId -eq $campaign.campaignId);$algorithms=@($campaign.algorithms);foreach($algorithm in $algorithms){$none=@($rows|Where-Object{$_.algorithm-eq$algorithm-and$_.predecessor-eq'NONE'}).Count;if($none-ne(32/$algorithms.Count)){$carryoverBalance=$false};foreach($predecessor in @($algorithms|Where-Object{$_-ne$algorithm})){$count=@($rows|Where-Object{$_.algorithm-eq$algorithm-and$_.predecessor-eq$predecessor}).Count;if($count-ne(32/$algorithms.Count)){$carryoverBalance=$false}}}}
    Add-Assertion 'predecessor-carryover-balance' $carryoverBalance 'Each campaign must balance NONE and every eligible ordered predecessor over 32 blocks.'
    $laneCohorts=@($regenerated|Group-Object lane,comparisonCohortId|ForEach-Object{"$($_.Name)=$($_.Count)"})-join';'
    Add-Assertion 'lane-cohort-counts' (@($regenerated|Where-Object{$_.lane-eq1-and$_.comparisonCohortId-eq'four-algorithm-shared-goal-v1'}).Count-eq48-and@($regenerated|Where-Object{$_.lane-eq1-and$_.comparisonCohortId-eq'per-agent-heterogeneous-goal-v1'}).Count-eq24-and@($regenerated|Where-Object{$_.lane-eq1-and$_.comparisonCohortId-eq'grouped-field-heterogeneous-goal-v1'}).Count-eq24) $laneCohorts

    $formulaZero=Get-Gate12RSampleSizeCandidate -SigmaUpper 0 -Z 1.96 -RelativeHalfWidth 0.10 -MinimumBlocks 32 -CycleMultiple 4
    $formulaHalf=Get-Gate12RSampleSizeCandidate -SigmaUpper 0.6 -Z 1.96 -RelativeHalfWidth 0.10 -MinimumBlocks 32 -CycleMultiple 4
    $expectedHalf=[int]([math]::Ceiling([math]::Ceiling([math]::Pow((1.96*0.6)/[math]::Log(1.10),2))/4.0)*4)
    Add-Assertion 'uncapped-sample-size-formula' ([long]$formulaZero.candidateNFormal-eq32-and[long]$formulaHalf.candidateNFormal-eq$expectedHalf-and[long]$formulaHalf.candidateNFormal-gt148) "Expected uncapped high-variance candidate $expectedHalf."

    $playablePassed=$true;$playableErrors=New-Object Collections.Generic.List[string]
    foreach($campaign in $campaigns){$scene=Join-Path $ProjectPath ([string]$campaign.sceneAssetPath).Replace('/','\');$profile=Join-Path $ProjectPath ([string]$campaign.profileAssetPath).Replace('/','\');if(-not(Test-Path -LiteralPath $scene -PathType Leaf)){$playablePassed=$false;$playableErrors.Add("Scene missing: $($campaign.campaignId)")};if(-not(Test-Path -LiteralPath $profile -PathType Leaf)-or(Get-G13R36LowerSha256 $profile)-ne[string]$campaign.profileSha256){$playablePassed=$false;$playableErrors.Add("Profile missing/hash-invalid: $($campaign.campaignId)")}}
    Add-Assertion 'playable-campaign-mapping' $playablePassed ($playableErrors-join'; ')

    Add-Assertion 'provenance-boundary' ([string]$provenance.executionDesignId-eq[string]$plan.executionDesignId-and$provenance.formalCampaign-eq$false-and$provenance.formalExecutionAuthorized-eq$false) 'Provenance must remain non-formal and match the plan design.'
    foreach($property in $provenance.PSObject.Properties){$value=$property.Value;if($value-is[pscustomobject]-and$value.PSObject.Properties.Name-contains'relativePath'-and$value.PSObject.Properties.Name-contains'sha256'){$bound=Join-Path $ProjectPath ([string]$value.relativePath).Replace('/','\');$ok=(Test-Path -LiteralPath $bound -PathType Leaf)-and(Get-G13R36LowerSha256 $bound)-eq[string]$value.sha256;Add-Assertion ('provenance-'+$property.Name) $ok ([string]$value.relativePath)}}

    $scriptFiles=@(
      'Research\Gate13R36hConcurrencyPreparationV2.psm1','Research\Run-Gate13R36hBlockV2.ps1','Research\Run-Gate13R36hTelemetryProbeV2.ps1','Research\Initialize-Gate13R36hLaneCopiesV2.ps1','Research\Run-Gate13R36hConcurrencyPilotV2.ps1','Research\Analyze-Gate13R36hConcurrencyPilotV2.ps1',
      'Research\Verification\New-Gate13R36hConcurrencyCommandV1.ps1','Research\Verification\New-Gate13R36hPilotScheduleV1.ps1','Research\Verification\Run-Gate13R36hCompileV1.ps1','Research\Verification\Run-Gate13R36hStaticUnitV2.ps1','Research\Verification\Run-Gate13R36hRetainedRegressionV2.ps1','Research\Verification\Run-Gate13R36hVerificationV2.ps1','Research\Verification\Run-Gate13R36hValidationOnlyPrePilotAuditV2.ps1'
    )
    foreach($relative in $scriptFiles){$path=Join-Path $ProjectPath $relative;$tokens=$null;$parseErrors=$null;[void][Management.Automation.Language.Parser]::ParseFile($path,[ref]$tokens,[ref]$parseErrors);$parseDetail=if($parseErrors.Count){@($parseErrors|ForEach-Object{$_.Message})-join'; '}else{''};Add-Assertion ('parser-'+([IO.Path]::GetFileName($relative))) ($parseErrors.Count-eq0) $parseDetail}

    $windowsPowerShell='C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe'
    $smokes=@(
      @{name='block';script='Research\Run-Gate13R36hBlockV2.ps1';arguments=@('-BlockPlanPath',(Join-Path $officialRoot 'BindingSmoke\plan.json'),'-OutputDirectory',(Join-Path $officialRoot 'BindingSmoke\block'),'-AllowedRoot',$officialRoot,'-Mode','Verification','-SourceProjectPath',$ProjectPath,'-LaneProjectPath','H:\DDM_Final_Project_Gate13R36H\v2\lane-01','-LaneNumber','1','-AffinityMaskHex','0x000000FF','-BindingSmokeOnly')},
      @{name='telemetry';script='Research\Run-Gate13R36hTelemetryProbeV2.ps1';arguments=@('-LaneProjectPath','H:\DDM_Final_Project_Gate13R36H\v2\lane-01','-OutputDirectory','H:\DDM_Final_Project_Gate13R36H\v2\lane-01\Research\Verification\Gate13R_36h_10pct_4Lane\v2\BindingSmoke','-LaneNumber','1','-AffinityMaskHex','0x000000FF','-BindingSmokeOnly')},
      @{name='clones';script='Research\Initialize-Gate13R36hLaneCopiesV2.ps1';arguments=@('-ProjectPath',$ProjectPath,'-VerificationOutputRoot',(Join-Path $officialRoot 'BindingSmokeCopies'),'-BindingSmokeOnly')},
      @{name='compile';script='Research\Verification\Run-Gate13R36hCompileV1.ps1';arguments=@('-ProjectPath',$ProjectPath,'-VerificationRoot',(Join-Path $preImplementationRoot 'BindingSmoke'),'-BindingSmokeOnly')},
      @{name='pilot';script='Research\Run-Gate13R36hConcurrencyPilotV2.ps1';arguments=@('-ProjectPath',$ProjectPath,'-PrePilotAuditPath',(Join-Path $officialRoot 'ValidationOnlyPrePilotAudit.summary.json'),'-BindingSmokeOnly')},
      @{name='analysis';script='Research\Analyze-Gate13R36hConcurrencyPilotV2.ps1';arguments=@('-ProjectPath',$ProjectPath,'-PilotRoot',(Join-Path $ProjectPath 'Research\PilotRuns\Gate13R_36h_10pct_4Lane\v2'),'-BindingSmokeOnly')},
      @{name='static';script='Research\Verification\Run-Gate13R36hStaticUnitV2.ps1';arguments=@('-ProjectPath',$ProjectPath,'-OutputDirectory',(Join-Path $preImplementationRoot 'BindingSmokeStatic'),'-BindingSmokeOnly')},
      @{name='retained';script='Research\Verification\Run-Gate13R36hRetainedRegressionV2.ps1';arguments=@('-ProjectPath',$ProjectPath,'-OutputDirectory',(Join-Path $officialRoot 'BindingSmokeRetained'),'-BindingSmokeOnly')},
      @{name='verification';script='Research\Verification\Run-Gate13R36hVerificationV2.ps1';arguments=@('-ProjectPath',$ProjectPath,'-BindingSmokeOnly')},
      @{name='audit';script='Research\Verification\Run-Gate13R36hValidationOnlyPrePilotAuditV2.ps1';arguments=@('-ProjectPath',$ProjectPath,'-VerificationRoot',$officialRoot,'-BindingSmokeOnly')}
    )
    foreach($smoke in $smokes){$scriptPath=Join-Path $ProjectPath $smoke.script;$output=&$windowsPowerShell -NoProfile -ExecutionPolicy Bypass -File $scriptPath @($smoke.arguments) 2>&1;$exit=[int]$LASTEXITCODE;Add-Assertion ('binding-smoke-'+$smoke.name) ($exit-eq0-and($output|Out-String)-like'*BINDING-SMOKE-PASSED*') (($output|Out-String).Trim())}

    $derivation=Read-G13R36Json (Join-Path $ProjectPath 'Research\Gate13R_36h_Concurrency_Command_Derivation.v1.json')
    $commandPath=Join-Path $ProjectPath 'Assets\_Scripts\Research\Editor\Gate13R36hConcurrencyBatchCommandV1.cs'
    Add-Assertion 'unity-command-derivation' ([string]$derivation.outputSha256-eq(Get-G13R36LowerSha256 $commandPath)-and[string]$derivation.reverseTransformSha256-eq[string]$derivation.sourceSha256-and$derivation.workloadLogicChanged-eq$false-and$derivation.resetLogicChanged-eq$false-and$derivation.telemetryLogicChanged-eq$false-and$derivation.memoryThresholdsChanged-eq$false-and$derivation.formalCampaignEnabled-eq$false) 'Mechanical derivation and reverse transform must pass without semantic or formal-boundary changes.'
    $source=Get-Content -LiteralPath $commandPath -Raw
    Add-Assertion 'telemetry-reset-source-signals' ($source.Contains('GetProcessMemoryInfo')-and$source.Contains('planner.Reset();')-and$source.Contains('plannerResetCompleted = true')-and$source.Contains('sampleStateCreatedFresh = true')-and$source.Contains('processAgeBeforeMilliseconds')-and$source.Contains('managedMemoryAfterCleanupBytes')) 'Derived command must retain telemetry, per-sample planner reset/fresh-state, process-age, and managed-memory evidence.'
}catch{$failures.Add($_.Exception.ToString())}

$summary=[ordered]@{schemaVersion=1;summaryKind='gate13r-36h-four-lane-static-unit-summary-v2';completedAtUtc=[DateTime]::UtcNow.ToString('o');assertionCount=$assertions.Count;passedAssertionCount=@($assertions|Where-Object passed).Count;failedAssertionCount=@($assertions|Where-Object{-not$_.passed}).Count;assertions=$assertions.ToArray();failures=$failures.ToArray();formalCampaign=$false;pilotExecuted=$false;passed=$failures.Count-eq0-and@($assertions|Where-Object{-not$_.passed}).Count-eq0}
Write-G13R36AtomicUtf8NoBomJson -Path (Join-Path $OutputDirectory 'summary.json') -Value $summary -Depth 50
$summary|ConvertTo-Json -Depth 8
if(-not$summary.passed){exit 1}
exit 0
