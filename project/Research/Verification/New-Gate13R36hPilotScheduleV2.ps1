[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$ProjectPath)

$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
$ProjectPath=[IO.Path]::GetFullPath($ProjectPath)
Import-Module (Join-Path $ProjectPath 'Research\Gate13R36hConcurrencyPreparationV2.psm1') -Force
$planPath=Join-Path $ProjectPath 'Research\Gate13R_36h_10pct_4Lane_Pilot_Plan.v2.json'
$schedulePath=Join-Path $ProjectPath 'Research\Gate13R_36h_10pct_4Lane_Pilot_Schedule.v2.json'
$receiptPath=Join-Path $ProjectPath 'Research\Gate13R_36h_10pct_4Lane_Pilot_Schedule_Generation.v2.json'
foreach($path in @($schedulePath,$receiptPath)){if(Test-Path -LiteralPath $path){throw "Create-new schedule artifact exists: $path"}}
$plan=Read-G13R36Json $planPath;$campaigns=@(Get-G13R36PilotCampaigns -ProjectPath $ProjectPath -Plan $plan)
$schedule=@(Get-G13R36MeasuredSchedule -Plan $plan -Campaigns $campaigns);$test=Test-G13R36Schedule -Schedule $schedule
if(-not$test.passed){throw "Generated schedule failed balance checks: $($test.errors-join'; ')"}
$document=[ordered]@{schemaVersion=1;scheduleKind='gate13r-36h-10pct-four-lane-nonformal-pilot-schedule-v2';planId=[string]$plan.planId;executionDesignId=[string]$plan.executionDesignId;formalCampaign=$false;excludedFromFormalAnalysis=$true;laneCount=4;waveCount=96;measuredBlockCount=384;measuredSampleCount=1152;rows=$schedule}
Write-G13R36Utf8NoBomJson -Path $schedulePath -Value $document -Depth 40
$firstHash=Get-G13R36LowerSha256 $schedulePath
$repeatPath=$schedulePath+'.determinism-check.tmp';Write-G13R36Utf8NoBomJson -Path $repeatPath -Value $document -Depth 40
try{$secondHash=Get-G13R36LowerSha256 $repeatPath}finally{[IO.File]::Delete($repeatPath)}
if($firstHash-ne$secondHash){throw 'Schedule deterministic regeneration hash mismatch.'}
$receipt=[ordered]@{schemaVersion=1;receiptKind='gate13r-36h-four-lane-pilot-schedule-generation-v2';createdAtUtc=[DateTime]::UtcNow.ToString('o');planRelativePath='Research/Gate13R_36h_10pct_4Lane_Pilot_Plan.v2.json';planSha256=Get-G13R36LowerSha256 $planPath;scheduleRelativePath='Research/Gate13R_36h_10pct_4Lane_Pilot_Schedule.v2.json';scheduleSha256=$firstHash;deterministicRegenerationSha256=$secondHash;campaignCount=$campaigns.Count;rowCount=$schedule.Count;waveCount=96;laneCount=4;balanceTest=$test;formalCampaign=$false;passed=$true}
Write-G13R36Utf8NoBomJson -Path $receiptPath -Value $receipt -Depth 20
$receipt|ConvertTo-Json -Depth 20
