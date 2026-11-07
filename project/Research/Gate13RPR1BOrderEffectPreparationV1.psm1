Set-StrictMode -Version Latest

$script:Utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$script:ExecutionDesignId = 'gate10r-one-fresh-unity-process-per-williams-block-5pct-v1'
$script:PlanId = 'gate13r-pr1b-balanced-mirrored-order-effect-pilot-v1'
$script:Gate10Module = Join-Path $PSScriptRoot 'Gate10RProcessReusePreparation.psm1'
Import-Module $script:Gate10Module -Force

function Get-Gate13RPR1BLowerSha256 {
    param([Parameter(Mandatory=$true)][string]$Path)
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Read-Gate13RPR1BJson {
    param([Parameter(Mandatory=$true)][string]$Path)
    return Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
}

function ConvertTo-Gate13RPR1BJsonText {
    param([Parameter(Mandatory=$true)]$Value,[int]$Depth=60)
    $text=($Value|ConvertTo-Json -Depth $Depth).Replace("`r`n","`n").Replace("`r","`n")
    if(-not$text.EndsWith("`n")){$text+="`n"}
    return $text
}

function Write-Gate13RPR1BUtf8NoBomJson {
    param([Parameter(Mandatory=$true)][string]$Path,[Parameter(Mandatory=$true)]$Value,[int]$Depth=60)
    $parent=Split-Path -Parent $Path
    if(-not(Test-Path -LiteralPath $parent -PathType Container)){New-Item -ItemType Directory -Path $parent -Force|Out-Null}
    [IO.File]::WriteAllText($Path,(ConvertTo-Gate13RPR1BJsonText -Value $Value -Depth $Depth),$script:Utf8NoBom)
}

function Write-Gate13RPR1BAtomicUtf8NoBomJson {
    param([Parameter(Mandatory=$true)][string]$Path,[Parameter(Mandatory=$true)]$Value,[int]$Depth=60)
    $parent=Split-Path -Parent $Path
    if(-not(Test-Path -LiteralPath $parent -PathType Container)){New-Item -ItemType Directory -Path $parent -Force|Out-Null}
    $temporary=$Path+'.tmp-'+[Guid]::NewGuid().ToString('N')
    Write-Gate13RPR1BUtf8NoBomJson -Path $temporary -Value $Value -Depth $Depth
    Move-Item -LiteralPath $temporary -Destination $Path -Force
}

function Get-Gate13RPR1BProjectRelativePath {
    param([Parameter(Mandatory=$true)][string]$ProjectPath,[Parameter(Mandatory=$true)][string]$FullPath)
    $root=[IO.Path]::GetFullPath($ProjectPath).TrimEnd('\')+'\'
    $candidate=[IO.Path]::GetFullPath($FullPath)
    if(-not$candidate.StartsWith($root,[StringComparison]::OrdinalIgnoreCase)){throw "Path escapes project root: $candidate"}
    return $candidate.Substring($root.Length).Replace('\','/')
}

function Assert-Gate13RPR1BPlanIdentity {
    param([Parameter(Mandatory=$true)]$Plan)
    if([int]$Plan.schemaVersion-ne1-or[string]$Plan.planId-ne$script:PlanId-or[string]$Plan.executionDesignId-ne$script:ExecutionDesignId){throw 'PR1B plan identity mismatch.'}
    if($Plan.formalCampaign-ne$false-or$Plan.nonFormal-ne$true-or$Plan.excludedFromFormalAnalysis-ne$true-or$Plan.gate13rFormalAuthorized-ne$false){throw 'PR1B non-formal boundary mismatch.'}
    if([int]$Plan.schedule.measuredBlockOrdinalsInclusive[0]-ne1-or[int]$Plan.schedule.measuredBlockOrdinalsInclusive[1]-ne32){throw 'PR1B measured block range mismatch.'}
    if([int]$Plan.totals.measuredMirroredPairs-ne96-or[int]$Plan.totals.measuredBlockProcesses-ne384-or[int]$Plan.totals.measuredSamples-ne768){throw 'PR1B frozen measured cardinality mismatch.'}
}

function Get-Gate13RPR1BCampaigns {
    param([Parameter(Mandatory=$true)][string]$ProjectPath,[Parameter(Mandatory=$true)]$Plan)
    Assert-Gate13RPR1BPlanIdentity -Plan $Plan
    $matrixPath=Join-Path $ProjectPath ([string]$Plan.paths.gate11MatrixRelativePath).Replace('/','\')
    if((Get-Gate13RPR1BLowerSha256 $matrixPath)-ne[string]$Plan.upstreamHashes.gate11Matrix){throw 'Gate11R matrix hash mismatch.'}
    $matrix=Read-Gate13RPR1BJson $matrixPath
    $rows=New-Object Collections.Generic.List[object]
    foreach($id in @($Plan.campaignIds)){
        $matches=@($matrix.campaigns|Where-Object campaignId -eq ([string]$id))
        if($matches.Count-ne1){throw "Campaign must resolve exactly once: $id"}
        $m=$matches[0]
        if([string]$m.scenarioId-notin@($Plan.scenarioIds)){throw "Unexpected PR1B scenario: $($m.scenarioId)"}
        $algorithms=@(Get-Gate10RCohortAlgorithms -ComparisonCohortId ([string]$m.comparisonCohortId))
        if((@($m.eligibleAlgorithmIds|Sort-Object)-join'|')-ne(@($algorithms|Sort-Object)-join'|')){throw "Algorithm-set mismatch: $id"}
        if($algorithms.Count-ne2){throw "PR1B requires a two-algorithm heterogeneous cohort: $id"}
        $matrixRows=@($m.williamsRows|Sort-Object rowIndex)
        if($matrixRows.Count-ne2){throw "Williams row count mismatch: $id"}
        for($row=0;$row-lt2;$row++){
            $expected=@(Get-Gate10RWilliamsRow -Algorithms $algorithms -Block ($row+1))
            if([int]$matrixRows[$row].rowIndex-ne$row-or(@($matrixRows[$row].algorithms)-join'|')-ne($expected-join'|')){throw "Williams row mismatch: $id row $row"}
        }
        $scenarioPath=Join-Path $ProjectPath ([string]$m.scenarioRelativePath).Replace('/','\')
        if((Get-Gate13RPR1BLowerSha256 $scenarioPath)-ne[string]$m.scenarioSha256){throw "Scenario hash mismatch: $id"}
        $rows.Add([pscustomobject][ordered]@{
            campaignId=[string]$m.campaignId
            scenarioId=[string]$m.scenarioId
            scenarioRelativePath=[string]$m.scenarioRelativePath
            scenarioSha256=[string]$m.scenarioSha256
            scenarioFingerprintSha256=[string]$m.scenarioFingerprintSha256
            comparisonCohortId=[string]$m.comparisonCohortId
            algorithms=$algorithms
            sceneAssetPath=[string]$m.sceneAssetPath
            profileAssetPath=[string]$m.profileAssetPath
            profileAssetGuid=[string]$m.profileAssetGuid
            profileSha256=[string]$m.profileSha256
        })
    }
    foreach($scenarioId in @($Plan.scenarioIds)){
        $pair=@($rows|Where-Object scenarioId -eq ([string]$scenarioId))
        if($pair.Count-ne2){throw "Scenario must resolve to exactly two cohorts: $scenarioId"}
        if(@($pair.scenarioSha256|Select-Object -Unique).Count-ne1-or@($pair.scenarioFingerprintSha256|Select-Object -Unique).Count-ne1){throw "Cross-cohort canonical identity mismatch: $scenarioId"}
        $cohorts=@($pair.comparisonCohortId|Sort-Object)
        if(($cohorts-join'|')-ne'grouped-field-heterogeneous-goal-v1|per-agent-heterogeneous-goal-v1'){throw "Cohort-pair mismatch: $scenarioId"}
    }
    return $rows.ToArray()
}

function Get-Gate13RPR1BProcessSchedule {
    param(
        [Parameter(Mandatory=$true)]$Plan,
        [Parameter(Mandatory=$true)][object[]]$Campaigns,
        [ValidateSet('measured-non-formal-pilot','excluded-warmup')][string]$AnalysisRole='measured-non-formal-pilot'
    )
    Assert-Gate13RPR1BPlanIdentity -Plan $Plan
    $scenarioIds=@($Plan.scenarioIds)
    $blocks=if($AnalysisRole-eq'excluded-warmup'){@([int]$Plan.warmup.blockOrdinal)}else{[int]$Plan.schedule.measuredBlockOrdinalsInclusive[0]..[int]$Plan.schedule.measuredBlockOrdinalsInclusive[1]}
    $schedule=New-Object Collections.Generic.List[object]
    foreach($block in $blocks){
        $offset=if($AnalysisRole-eq'excluded-warmup'){0}else{($block-1)%$scenarioIds.Count}
        for($slot=0;$slot-lt$scenarioIds.Count;$slot++){
            $scenarioId=[string]$scenarioIds[($offset+$slot)%$scenarioIds.Count]
            $scenarioCampaigns=@($Campaigns|Where-Object scenarioId -eq $scenarioId)
            $perAgent=@($scenarioCampaigns|Where-Object comparisonCohortId -eq 'per-agent-heterogeneous-goal-v1')[0]
            $grouped=@($scenarioCampaigns|Where-Object comparisonCohortId -eq 'grouped-field-heterogeneous-goal-v1')[0]
            if($null-eq$perAgent-or$null-eq$grouped){throw "Missing cohort campaign for $scenarioId"}
            $superblockOrders=if($block%2-eq1){@('AB','BA')}else{@('BA','AB')}
            $pairId=('{0}::b{1:D3}'-f$scenarioId,$block)
            for($superblockIndex=0;$superblockIndex-lt2;$superblockIndex++){
                $order=[string]$superblockOrders[$superblockIndex]
                $cohortCampaigns=if($order-eq'AB'){@($perAgent,$grouped)}else{@($grouped,$perAgent)}
                for($cohortIndex=0;$cohortIndex-lt2;$cohortIndex++){
                    $campaign=$cohortCampaigns[$cohortIndex]
                    $globalOrdinal=$schedule.Count+1
                    $roleSlug=if($AnalysisRole-eq'excluded-warmup'){'w'}else{'m'}
                    $prefix=('g13r-pr1b-{0}-b{1:D3}-{2}-s{3}'-f$roleSlug,$block,$order.ToLowerInvariant(),($superblockIndex+1))
                    $relative=('{0}\wave-{1:D3}\slot-{2:D2}-{3}\pair-b{1:D3}\{4}-s{5}\p{6:D2}-{7}'-f$(if($AnalysisRole-eq'excluded-warmup'){'warmup'}else{'measured'}),$block,($slot+1),$scenarioId,$order.ToLowerInvariant(),($superblockIndex+1),($cohortIndex+1),$(if([string]$campaign.comparisonCohortId-like'per-agent*'){'per-agent'}else{'grouped-field'}))
                    $schedule.Add([pscustomobject][ordered]@{
                        ordinal=$globalOrdinal
                        analysisRole=$AnalysisRole
                        wave=$block
                        scenarioWaveSlot=$slot+1
                        scenarioId=$scenarioId
                        block=$block
                        mirroredPairId=$pairId
                        firstSuperblockOrder=[string]$superblockOrders[0]
                        superblockOrder=$order
                        superblockSequencePosition=$superblockIndex+1
                        cohortProcessPosition=$cohortIndex+1
                        pairProcessPosition=($superblockIndex*2)+$cohortIndex+1
                        campaign=$campaign
                        campaignIdPrefix=$prefix
                        relativeOutput=$relative
                    })
                }
            }
        }
    }
    return $schedule.ToArray()
}

function Test-Gate13RPR1BSchedule {
    param([Parameter(Mandatory=$true)]$Plan,[Parameter(Mandatory=$true)][object[]]$Measured,[Parameter(Mandatory=$true)][object[]]$Warmup)
    $errors=New-Object Collections.Generic.List[string]
    try{
        if($Measured.Count-ne[int]$Plan.totals.measuredBlockProcesses){throw 'Measured process count mismatch.'}
        if($Warmup.Count-ne[int]$Plan.totals.warmupBlockProcesses){throw 'Warm-up process count mismatch.'}
        $pairs=@($Measured|Group-Object mirroredPairId)
        if($pairs.Count-ne96){throw 'Measured mirrored-pair count mismatch.'}
        foreach($pair in $pairs){
            $items=@($pair.Group|Sort-Object pairProcessPosition)
            if($items.Count-ne4-or(@($items.pairProcessPosition)-join'|')-ne'1|2|3|4'){throw "Non-contiguous pair: $($pair.Name)"}
            if(@($items.scenarioId|Select-Object -Unique).Count-ne1-or@($items.block|Select-Object -Unique).Count-ne1){throw "Pair identity mismatch: $($pair.Name)"}
            if((@($items.superblockOrder|Select-Object -Unique|Sort-Object)-join '|')-ne 'AB|BA'){throw "Pair lacks AB/BA: $($pair.Name)"}
            foreach($order in @('AB','BA')){
                $two=@($items|Where-Object superblockOrder -eq $order|Sort-Object cohortProcessPosition)
                $actual=@($two.campaign.comparisonCohortId)
                $expected=if($order-eq'AB'){@('per-agent-heterogeneous-goal-v1','grouped-field-heterogeneous-goal-v1')}else{@('grouped-field-heterogeneous-goal-v1','per-agent-heterogeneous-goal-v1')}
                if(($actual-join'|')-ne($expected-join'|')){throw "Cohort order mismatch: $($pair.Name) $order"}
            }
        }
        foreach($scenarioId in @($Plan.scenarioIds)){
            $items=@($Measured|Where-Object scenarioId -eq([string]$scenarioId))
            if(@($items|Group-Object mirroredPairId).Count-ne32){throw "Scenario pair count mismatch: $scenarioId"}
            $ab=@($items|Where-Object superblockOrder -eq 'AB').Count/2;$ba=@($items|Where-Object superblockOrder -eq 'BA').Count/2
            if($ab-ne32-or$ba-ne32){throw "Scenario AB/BA quota mismatch: $scenarioId"}
            $abFirst=@($items|Group-Object mirroredPairId|ForEach-Object{$_.Group[0]}|Where-Object firstSuperblockOrder -eq 'AB').Count
            $baFirst=@($items|Group-Object mirroredPairId|ForEach-Object{$_.Group[0]}|Where-Object firstSuperblockOrder -eq 'BA').Count
            if($abFirst-ne16-or$baFirst-ne16){throw "Scenario first-superblock quota mismatch: $scenarioId"}
        }
        $scenarioPrefixes=@($Measured|ForEach-Object{"$($_.scenarioId)|$($_.campaignIdPrefix)"}|Select-Object -Unique)
        if($scenarioPrefixes.Count-ne192){throw 'Expected one unique scenario/prefix identity per matched superblock.'}
        $identity=@($Measured|ForEach-Object{"$($_.campaignIdPrefix)|$($_.campaign.campaignId)|$($_.block)"})
        if(@($identity|Select-Object -Unique).Count-ne$Measured.Count){throw 'Generated process/block identity is not unique.'}
    }catch{$errors.Add($_.Exception.Message)}
    return [pscustomobject][ordered]@{passed=$errors.Count-eq0;measuredProcessCount=$Measured.Count;warmupProcessCount=$Warmup.Count;measuredPairCount=@($Measured|Group-Object mirroredPairId).Count;errors=$errors.ToArray()}
}

function New-Gate13RPR1BBlockPlan {
    param(
        [Parameter(Mandatory=$true)][string]$ProjectPath,
        [Parameter(Mandatory=$true)]$Plan,
        [Parameter(Mandatory=$true)]$Provenance,
        [Parameter(Mandatory=$true)]$ScheduleItem,
        [Parameter(Mandatory=$true)][string]$ProvenancePath,
        [Parameter(Mandatory=$true)][string]$TelemetryProbeResultPath,
        [ValidateRange(0,2)][int]$InjectedFailurePosition=0
    )
    $adapter=[pscustomobject][ordered]@{designId=[string]$Plan.executionDesignId;formalCampaign=$false}
    return New-Gate10RBlockPlan -ProjectPath $ProjectPath -Config $adapter -Provenance $Provenance -CampaignId (('{0}-{1}'-f[string]$ScheduleItem.campaignIdPrefix,[string]$ScheduleItem.campaign.campaignId).Replace('--','-')) -ScenarioRelativePath ([string]$ScheduleItem.campaign.scenarioRelativePath) -ScenarioSourceSha256 ([string]$ScheduleItem.campaign.scenarioSha256) -ComparisonCohortId ([string]$ScheduleItem.campaign.comparisonCohortId) -Block ([int]$ScheduleItem.block) -ProvenancePath $ProvenancePath -TelemetryProbeResultPath $TelemetryProbeResultPath -AnalysisRole ([string]$ScheduleItem.analysisRole) -InjectedFailurePosition $InjectedFailurePosition
}

function Get-Gate13RPR1BRawBytes {
    param([Parameter(Mandatory=$true)][string]$Path)
    if(-not(Test-Path -LiteralPath $Path)){return 0L}
    if(Test-Path -LiteralPath $Path -PathType Leaf){return [long](Get-Item -LiteralPath $Path).Length}
    return [long](Get-ChildItem -LiteralPath $Path -Recurse -File -Force|Measure-Object Length -Sum).Sum
}

Export-ModuleMember -Function @(
 'Get-Gate13RPR1BLowerSha256','Read-Gate13RPR1BJson','ConvertTo-Gate13RPR1BJsonText','Write-Gate13RPR1BUtf8NoBomJson','Write-Gate13RPR1BAtomicUtf8NoBomJson','Get-Gate13RPR1BProjectRelativePath',
 'Assert-Gate13RPR1BPlanIdentity','Get-Gate13RPR1BCampaigns','Get-Gate13RPR1BProcessSchedule','Test-Gate13RPR1BSchedule','New-Gate13RPR1BBlockPlan','Get-Gate13RPR1BRawBytes'
)
