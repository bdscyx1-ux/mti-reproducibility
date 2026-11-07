Set-StrictMode -Version Latest

$script:ExecutionDesignId='gate10r-one-fresh-unity-process-per-williams-block-5pct-v1'
$script:PlanId='gate13r-pr1b-balanced-mirrored-order-effect-memory-v2-pilot-v1'
$script:FrozenV1Module=Join-Path $PSScriptRoot 'Gate13RPR1BOrderEffectPreparationV1.psm1'
$script:FrozenV1ModuleSha256='74cf0104b5b54617d4aa8364de19dc7dd522ea538e20a1fb7d53022a437bbeee'
if(-not(Test-Path -LiteralPath $script:FrozenV1Module -PathType Leaf)){throw 'Frozen PR1B v1 preparation module is missing.'}
$actual=(Get-FileHash -LiteralPath $script:FrozenV1Module -Algorithm SHA256).Hash.ToLowerInvariant()
if($actual-ne$script:FrozenV1ModuleSha256){throw "Frozen PR1B v1 preparation module changed: $actual"}
Import-Module $script:FrozenV1Module -Force
Import-Module (Join-Path $PSScriptRoot 'Gate10RProcessReusePreparation.psm1') -Force

function Get-Gate13RPR1BV2LowerSha256 { param([Parameter(Mandatory=$true)][string]$Path) Get-Gate13RPR1BLowerSha256 -Path $Path }
function Read-Gate13RPR1BV2Json { param([Parameter(Mandatory=$true)][string]$Path) Read-Gate13RPR1BJson -Path $Path }
function Write-Gate13RPR1BV2Utf8NoBomJson { param([Parameter(Mandatory=$true)][string]$Path,[Parameter(Mandatory=$true)]$Value,[int]$Depth=60) Write-Gate13RPR1BUtf8NoBomJson -Path $Path -Value $Value -Depth $Depth }
function Write-Gate13RPR1BV2AtomicUtf8NoBomJson { param([Parameter(Mandatory=$true)][string]$Path,[Parameter(Mandatory=$true)]$Value,[int]$Depth=60) Write-Gate13RPR1BAtomicUtf8NoBomJson -Path $Path -Value $Value -Depth $Depth }
function Get-Gate13RPR1BV2ProjectRelativePath { param([Parameter(Mandatory=$true)][string]$ProjectPath,[Parameter(Mandatory=$true)][string]$FullPath) Get-Gate13RPR1BProjectRelativePath -ProjectPath $ProjectPath -FullPath $FullPath }
function Get-Gate13RPR1BV2RawBytes { param([Parameter(Mandatory=$true)][string]$Path) Get-Gate13RPR1BRawBytes -Path $Path }

function Assert-Gate13RPR1BV2PlanIdentity {
    param([Parameter(Mandatory=$true)]$Plan)
    if([int]$Plan.schemaVersion-ne2-or[string]$Plan.planId-ne$script:PlanId-or[string]$Plan.executionDesignId-ne$script:ExecutionDesignId){throw 'PR1B v2 plan identity mismatch.'}
    if($Plan.formalCampaign-ne$false-or$Plan.nonFormal-ne$true-or$Plan.excludedFromFormalAnalysis-ne$true-or$Plan.gate13rFormalAuthorized-ne$false-or$Plan.gate14rAuthorized-ne$false){throw 'PR1B v2 non-formal authorization boundary mismatch.'}
    if([string]$Plan.memoryEligibility.policyId-ne'gate13r-pr1b-v2-sample-alert-128mib-emergency-256mib-block-256mib-v1'){throw 'PR1B v2 memory-policy identity mismatch.'}
    if([long]$Plan.memoryEligibility.sampleAlertThresholdBytes-ne134217728-or[long]$Plan.memoryEligibility.sampleEmergencyStopBytes-ne268435456-or[long]$Plan.memoryEligibility.twoSampleBlockManagedGrowthHardLimitBytes-ne268435456-or[long]$Plan.memoryEligibility.blockWorkingSetGrowthHardLimitBytes-ne536870912-or[long]$Plan.memoryEligibility.blockPrivateMemoryGrowthHardLimitBytes-ne536870912){throw 'PR1B v2 memory thresholds differ from the frozen amendment.'}
    if([int]$Plan.schedule.measuredBlockOrdinalsInclusive[0]-ne1-or[int]$Plan.schedule.measuredBlockOrdinalsInclusive[1]-ne32){throw 'PR1B v2 measured block range mismatch.'}
    if([int]$Plan.totals.measuredMirroredPairs-ne96-or[int]$Plan.totals.measuredBlockProcesses-ne384-or[int]$Plan.totals.measuredSamples-ne768){throw 'PR1B v2 measured cardinality mismatch.'}
}

function ConvertTo-Gate13RPR1BV1PlanProxy {
    param([Parameter(Mandatory=$true)]$Plan)
    Assert-Gate13RPR1BV2PlanIdentity -Plan $Plan
    $json=$Plan|ConvertTo-Json -Depth 60
    $proxy=$json|ConvertFrom-Json
    $proxy.schemaVersion=1
    $proxy.planId='gate13r-pr1b-balanced-mirrored-order-effect-pilot-v1'
    return $proxy
}

function Get-Gate13RPR1BV2Campaigns {
    param([Parameter(Mandatory=$true)][string]$ProjectPath,[Parameter(Mandatory=$true)]$Plan)
    $proxy=ConvertTo-Gate13RPR1BV1PlanProxy -Plan $Plan
    return @(Get-Gate13RPR1BCampaigns -ProjectPath $ProjectPath -Plan $proxy)
}

function Get-Gate13RPR1BV2ProcessSchedule {
    param([Parameter(Mandatory=$true)]$Plan,[Parameter(Mandatory=$true)][object[]]$Campaigns,[ValidateSet('measured-non-formal-pilot','excluded-warmup')][string]$AnalysisRole='measured-non-formal-pilot')
    $proxy=ConvertTo-Gate13RPR1BV1PlanProxy -Plan $Plan
    return @(Get-Gate13RPR1BProcessSchedule -Plan $proxy -Campaigns $Campaigns -AnalysisRole $AnalysisRole)
}

function Test-Gate13RPR1BV2Schedule {
    param([Parameter(Mandatory=$true)]$Plan,[Parameter(Mandatory=$true)][object[]]$Measured,[Parameter(Mandatory=$true)][object[]]$Warmup)
    $proxy=ConvertTo-Gate13RPR1BV1PlanProxy -Plan $Plan
    return Test-Gate13RPR1BSchedule -Plan $proxy -Measured $Measured -Warmup $Warmup
}

function New-Gate13RPR1BV2BlockPlan {
    param(
        [Parameter(Mandatory=$true)][string]$ProjectPath,
        [Parameter(Mandatory=$true)]$Plan,
        [Parameter(Mandatory=$true)]$Provenance,
        [Parameter(Mandatory=$true)]$ScheduleItem,
        [Parameter(Mandatory=$true)][string]$ProvenancePath,
        [Parameter(Mandatory=$true)][string]$TelemetryProbeResultPath,
        [ValidateRange(0,2)][int]$InjectedFailurePosition=0
    )
    Assert-Gate13RPR1BV2PlanIdentity -Plan $Plan
    $adapter=[pscustomobject][ordered]@{designId=[string]$Plan.executionDesignId;formalCampaign=$false}
    return New-Gate10RBlockPlan -ProjectPath $ProjectPath -Config $adapter -Provenance $Provenance -CampaignId (('{0}-{1}'-f[string]$ScheduleItem.campaignIdPrefix,[string]$ScheduleItem.campaign.campaignId).Replace('--','-')) -ScenarioRelativePath ([string]$ScheduleItem.campaign.scenarioRelativePath) -ScenarioSourceSha256 ([string]$ScheduleItem.campaign.scenarioSha256) -ComparisonCohortId ([string]$ScheduleItem.campaign.comparisonCohortId) -Block ([int]$ScheduleItem.block) -ProvenancePath $ProvenancePath -TelemetryProbeResultPath $TelemetryProbeResultPath -AnalysisRole ([string]$ScheduleItem.analysisRole) -InjectedFailurePosition $InjectedFailurePosition
}

Export-ModuleMember -Function @(
    'Get-Gate13RPR1BV2LowerSha256','Read-Gate13RPR1BV2Json','Write-Gate13RPR1BV2Utf8NoBomJson','Write-Gate13RPR1BV2AtomicUtf8NoBomJson','Get-Gate13RPR1BV2ProjectRelativePath','Get-Gate13RPR1BV2RawBytes',
    'Assert-Gate13RPR1BV2PlanIdentity','Get-Gate13RPR1BV2Campaigns','Get-Gate13RPR1BV2ProcessSchedule','Test-Gate13RPR1BV2Schedule','New-Gate13RPR1BV2BlockPlan'
)
