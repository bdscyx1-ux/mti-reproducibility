Set-StrictMode -Version Latest

$script:ExecutionDesignId='gate10r-one-fresh-unity-process-per-williams-block-5pct-v1'
$script:PlanId='gate13r-pr1b-balanced-mirrored-order-effect-pathsafe-v4-pilot-v1'
$script:FrozenV1Module=Join-Path $PSScriptRoot 'Gate13RPR1BOrderEffectPreparationV1.psm1'
$script:FrozenV1ModuleSha256='74cf0104b5b54617d4aa8364de19dc7dd522ea538e20a1fb7d53022a437bbeee'
if(-not(Test-Path -LiteralPath $script:FrozenV1Module -PathType Leaf)){throw 'Frozen PR1B v1 preparation module is missing.'}
$actual=(Get-FileHash -LiteralPath $script:FrozenV1Module -Algorithm SHA256).Hash.ToLowerInvariant()
if($actual-ne$script:FrozenV1ModuleSha256){throw "Frozen PR1B v1 preparation module changed: $actual"}
Import-Module $script:FrozenV1Module -Force
Import-Module (Join-Path $PSScriptRoot 'Gate10RProcessReusePreparation.psm1') -Force

function Get-Gate13RPR1BV3LowerSha256 { param([Parameter(Mandatory=$true)][string]$Path) Get-Gate13RPR1BLowerSha256 -Path $Path }
function Read-Gate13RPR1BV3Json { param([Parameter(Mandatory=$true)][string]$Path) Read-Gate13RPR1BJson -Path $Path }
function Write-Gate13RPR1BV3Utf8NoBomJson { param([Parameter(Mandatory=$true)][string]$Path,[Parameter(Mandatory=$true)]$Value,[int]$Depth=60) Write-Gate13RPR1BUtf8NoBomJson -Path $Path -Value $Value -Depth $Depth }
function Write-Gate13RPR1BV3AtomicUtf8NoBomJson {
    param([Parameter(Mandatory=$true)][string]$Path,[Parameter(Mandatory=$true)]$Value,[int]$Depth=60)
    $full=[IO.Path]::GetFullPath($Path);$parent=[IO.Path]::GetDirectoryName($full)
    if(-not(Test-Path -LiteralPath $parent -PathType Container)){throw "Atomic JSON parent does not exist: $parent"}
    $parentItem=Get-Item -LiteralPath $parent -Force
    if(($parentItem.Attributes-band[IO.FileAttributes]::ReparsePoint)-ne0){throw "Atomic JSON parent is a reparse point: $parent"}
    $tmp=Join-Path $parent ('.g13tmp-'+[Guid]::NewGuid().ToString('N'))
    $backup=Join-Path $parent ('.g13bak-'+[Guid]::NewGuid().ToString('N'))
    if((Test-Path -LiteralPath $tmp)-or(Test-Path -LiteralPath $backup)){throw 'Atomic JSON helper leaf collision.'}
    $temporaryOwned=$false;$backupMayBeOwned=$true
    try{
        $json=($Value|ConvertTo-Json -Depth $Depth).Replace("`r`n","`n").Replace("`r","`n")+"`n"
        $stream=[IO.File]::Open($tmp,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None);$temporaryOwned=$true
        try{$writer=New-Object IO.StreamWriter($stream,(New-Object Text.UTF8Encoding($false,$true)));try{$writer.Write($json);$writer.Flush()}finally{$writer.Dispose()}}finally{if($stream){$stream.Dispose()}}
        $parentNow=Get-Item -LiteralPath $parent -Force
        if(($parentNow.Attributes-band[IO.FileAttributes]::ReparsePoint)-ne0){throw "Atomic JSON parent became a reparse point: $parent"}
        if(Test-Path -LiteralPath $full -PathType Container){throw "Atomic JSON target is a directory: $full"}
        if(Test-Path -LiteralPath $full -PathType Leaf){
            [IO.File]::Replace($tmp,$full,$backup,$true);$temporaryOwned=$false
        }else{
            [IO.File]::Move($tmp,$full);$temporaryOwned=$false
        }
    }finally{
        if($temporaryOwned-and(Test-Path -LiteralPath $tmp -PathType Leaf)){[IO.File]::Delete($tmp)}
        if($backupMayBeOwned-and(Test-Path -LiteralPath $backup -PathType Leaf)){[IO.File]::Delete($backup)}
    }
}
function Get-Gate13RPR1BV3ProjectRelativePath { param([Parameter(Mandatory=$true)][string]$ProjectPath,[Parameter(Mandatory=$true)][string]$FullPath) Get-Gate13RPR1BProjectRelativePath -ProjectPath $ProjectPath -FullPath $FullPath }
function Get-Gate13RPR1BV3RawBytes { param([Parameter(Mandatory=$true)][string]$Path) Get-Gate13RPR1BRawBytes -Path $Path }

function Assert-Gate13RPR1BV3PlanIdentity {
    param([Parameter(Mandatory=$true)]$Plan)
    if([int]$Plan.schemaVersion-ne2-or[string]$Plan.planId-ne$script:PlanId-or[string]$Plan.executionDesignId-ne$script:ExecutionDesignId){throw 'PR1B v3 plan identity mismatch.'}
    if($Plan.formalCampaign-ne$false-or$Plan.nonFormal-ne$true-or$Plan.excludedFromFormalAnalysis-ne$true-or$Plan.gate13rFormalAuthorized-ne$false-or$Plan.gate14rAuthorized-ne$false){throw 'PR1B v3 non-formal authorization boundary mismatch.'}
    if([string]$Plan.memoryEligibility.policyId-ne'gate13r-pr1b-v2-sample-alert-128mib-emergency-256mib-block-256mib-v1'){throw 'PR1B v3 memory-policy identity mismatch.'}
    if([long]$Plan.memoryEligibility.sampleAlertThresholdBytes-ne134217728-or[long]$Plan.memoryEligibility.sampleEmergencyStopBytes-ne268435456-or[long]$Plan.memoryEligibility.twoSampleBlockManagedGrowthHardLimitBytes-ne268435456-or[long]$Plan.memoryEligibility.blockWorkingSetGrowthHardLimitBytes-ne536870912-or[long]$Plan.memoryEligibility.blockPrivateMemoryGrowthHardLimitBytes-ne536870912){throw 'PR1B v3 memory thresholds differ from the frozen amendment.'}
    if([int]$Plan.schedule.measuredBlockOrdinalsInclusive[0]-ne1-or[int]$Plan.schedule.measuredBlockOrdinalsInclusive[1]-ne32){throw 'PR1B v3 measured block range mismatch.'}
    if([int]$Plan.totals.measuredMirroredPairs-ne96-or[int]$Plan.totals.measuredBlockProcesses-ne384-or[int]$Plan.totals.measuredSamples-ne768){throw 'PR1B v3 measured cardinality mismatch.'}
}

function ConvertTo-Gate13RPR1BV1PlanProxy {
    param([Parameter(Mandatory=$true)]$Plan)
    Assert-Gate13RPR1BV3PlanIdentity -Plan $Plan
    $json=$Plan|ConvertTo-Json -Depth 60
    $proxy=$json|ConvertFrom-Json
    $proxy.schemaVersion=1
    $proxy.planId='gate13r-pr1b-balanced-mirrored-order-effect-pilot-v1'
    return $proxy
}

function Get-Gate13RPR1BV3Campaigns {
    param([Parameter(Mandatory=$true)][string]$ProjectPath,[Parameter(Mandatory=$true)]$Plan)
    $proxy=ConvertTo-Gate13RPR1BV1PlanProxy -Plan $Plan
    return @(Get-Gate13RPR1BCampaigns -ProjectPath $ProjectPath -Plan $proxy)
}

function Get-Gate13RPR1BV3ProcessSchedule {
    param([Parameter(Mandatory=$true)]$Plan,[Parameter(Mandatory=$true)][object[]]$Campaigns,[ValidateSet('measured-non-formal-pilot','excluded-warmup')][string]$AnalysisRole='measured-non-formal-pilot')
    $proxy=ConvertTo-Gate13RPR1BV1PlanProxy -Plan $Plan
    return @(Get-Gate13RPR1BProcessSchedule -Plan $proxy -Campaigns $Campaigns -AnalysisRole $AnalysisRole)
}

function Test-Gate13RPR1BV3Schedule {
    param([Parameter(Mandatory=$true)]$Plan,[Parameter(Mandatory=$true)][object[]]$Measured,[Parameter(Mandatory=$true)][object[]]$Warmup)
    $proxy=ConvertTo-Gate13RPR1BV1PlanProxy -Plan $Plan
    return Test-Gate13RPR1BSchedule -Plan $proxy -Measured $Measured -Warmup $Warmup
}

function New-Gate13RPR1BV3BlockPlan {
    param(
        [Parameter(Mandatory=$true)][string]$ProjectPath,
        [Parameter(Mandatory=$true)]$Plan,
        [Parameter(Mandatory=$true)]$Provenance,
        [Parameter(Mandatory=$true)]$ScheduleItem,
        [Parameter(Mandatory=$true)][string]$ProvenancePath,
        [Parameter(Mandatory=$true)][string]$TelemetryProbeResultPath,
        [ValidateRange(0,2)][int]$InjectedFailurePosition=0
    )
    Assert-Gate13RPR1BV3PlanIdentity -Plan $Plan
    $adapter=[pscustomobject][ordered]@{designId=[string]$Plan.executionDesignId;formalCampaign=$false}
    return New-Gate10RBlockPlan -ProjectPath $ProjectPath -Config $adapter -Provenance $Provenance -CampaignId (('{0}-{1}'-f[string]$ScheduleItem.campaignIdPrefix,[string]$ScheduleItem.campaign.campaignId).Replace('--','-')) -ScenarioRelativePath ([string]$ScheduleItem.campaign.scenarioRelativePath) -ScenarioSourceSha256 ([string]$ScheduleItem.campaign.scenarioSha256) -ComparisonCohortId ([string]$ScheduleItem.campaign.comparisonCohortId) -Block ([int]$ScheduleItem.block) -ProvenancePath $ProvenancePath -TelemetryProbeResultPath $TelemetryProbeResultPath -AnalysisRole ([string]$ScheduleItem.analysisRole) -InjectedFailurePosition $InjectedFailurePosition
}

Export-ModuleMember -Function @(
    'Get-Gate13RPR1BV3LowerSha256','Read-Gate13RPR1BV3Json','Write-Gate13RPR1BV3Utf8NoBomJson','Write-Gate13RPR1BV3AtomicUtf8NoBomJson','Get-Gate13RPR1BV3ProjectRelativePath','Get-Gate13RPR1BV3RawBytes',
    'Assert-Gate13RPR1BV3PlanIdentity','Get-Gate13RPR1BV3Campaigns','Get-Gate13RPR1BV3ProcessSchedule','Test-Gate13RPR1BV3Schedule','New-Gate13RPR1BV3BlockPlan'
)


