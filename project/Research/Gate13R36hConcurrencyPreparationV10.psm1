Set-StrictMode -Version Latest

$script:G13Utf8 = New-Object System.Text.UTF8Encoding($false)
$script:G13DesignId = 'gate13r-36h-10pct-four-isolated-editor-lanes-v1'
$script:G13PlanId = 'gate13r-36h-10pct-four-lane-nonformal-pilot-plan-v100'

function Get-G13R36LowerSha256 {
    param([Parameter(Mandatory=$true)][string]$Path)
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Get-G13R36StringSha256 {
    param([Parameter(Mandatory=$true)][string]$Value)
    $sha=[Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash($script:G13Utf8.GetBytes($Value)))).Replace('-','').ToLowerInvariant() }
    finally { $sha.Dispose() }
}

function Read-G13R36Json {
    param([Parameter(Mandatory=$true)][string]$Path)
    return Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
}

function ConvertTo-G13R36JsonText {
    param([Parameter(Mandatory=$true)]$Value,[int]$Depth=60)
    $text=($Value|ConvertTo-Json -Depth $Depth).Replace("`r`n","`n").Replace("`r","`n")
    if(-not$text.EndsWith("`n")){$text+="`n"}
    return $text
}

function Write-G13R36Utf8NoBomJson {
    param([Parameter(Mandatory=$true)][string]$Path,[Parameter(Mandatory=$true)]$Value,[int]$Depth=60)
    $parent=Split-Path -Parent $Path
    if(-not(Test-Path -LiteralPath $parent -PathType Container)){New-Item -ItemType Directory -Path $parent|Out-Null}
    [IO.File]::WriteAllText($Path,(ConvertTo-G13R36JsonText -Value $Value -Depth $Depth),$script:G13Utf8)
}

function Write-G13R36AtomicUtf8NoBomJson {
    param([Parameter(Mandatory=$true)][string]$Path,[Parameter(Mandatory=$true)]$Value,[int]$Depth=60)
    $parent=Split-Path -Parent $Path
    if(-not(Test-Path -LiteralPath $parent -PathType Container)){New-Item -ItemType Directory -Path $parent|Out-Null}
    $temporary=$Path+'.tmp-'+[Guid]::NewGuid().ToString('N')
    [IO.File]::WriteAllText($temporary,(ConvertTo-G13R36JsonText -Value $Value -Depth $Depth),$script:G13Utf8)
    if(Test-Path -LiteralPath $Path){
        $backup=$Path+'.replace-backup-'+[Guid]::NewGuid().ToString('N')
        [IO.File]::Replace($temporary,$Path,$backup)
        if(Test-Path -LiteralPath $backup){[IO.File]::Delete($backup)}
    }else{[IO.File]::Move($temporary,$Path)}
}

function Write-G13R36CreateNewUtf8NoBomJson {
    param([Parameter(Mandatory=$true)][string]$Path,[Parameter(Mandatory=$true)]$Value,[int]$Depth=60)
    if(Test-Path -LiteralPath $Path){throw "Create-new target already exists: $Path"}
    Write-G13R36Utf8NoBomJson -Path $Path -Value $Value -Depth $Depth
}

function Get-G13R36ProjectRelativePath {
    param([Parameter(Mandatory=$true)][string]$ProjectPath,[Parameter(Mandatory=$true)][string]$FullPath)
    $root=[IO.Path]::GetFullPath($ProjectPath).TrimEnd('\')+'\'
    $candidate=[IO.Path]::GetFullPath($FullPath)
    if(-not$candidate.StartsWith($root,[StringComparison]::OrdinalIgnoreCase)){throw "Path escapes project root: $candidate"}
    return $candidate.Substring($root.Length).Replace('\','/')
}

function Get-G13R36RawBytes {
    param([Parameter(Mandatory=$true)][string]$Path)
    if(-not(Test-Path -LiteralPath $Path)){return 0L}
    if(Test-Path -LiteralPath $Path -PathType Leaf){return [long](Get-Item -LiteralPath $Path).Length}
    $sum=(Get-ChildItem -LiteralPath $Path -Recurse -File -Force|Measure-Object Length -Sum).Sum
    return $(if($null-eq$sum){0L}else{[long]$sum})
}

function Get-G13R36AlgorithmSlug {
    param([Parameter(Mandatory=$true)][string]$AlgorithmId)
    switch($AlgorithmId){'A*-R'{'astar-r'};'D*L'{'dstar-l'};'C-FF'{'cff'};'IDFF'{'idff'};default{throw "Unsupported algorithm: $AlgorithmId"}}
}

function Get-G13R36CohortAlgorithms {
    param([Parameter(Mandatory=$true)][string]$ComparisonCohortId)
    switch($ComparisonCohortId){
        'four-algorithm-shared-goal-v1'{return @('A*-R','D*L','C-FF','IDFF')}
        'per-agent-heterogeneous-goal-v1'{return @('A*-R','D*L')}
        'grouped-field-heterogeneous-goal-v1'{return @('C-FF','IDFF')}
        default{throw "Unsupported cohort: $ComparisonCohortId"}
    }
}

function Get-G13R36WilliamsRow {
    param([Parameter(Mandatory=$true)][string[]]$Algorithms,[Parameter(Mandatory=$true)][ValidateRange(1,1000000)][int]$Block)
    $count=$Algorithms.Count
    if($count-notin@(2,4)){throw 'Only two- and four-algorithm Williams rows are valid.'}
    $base=New-Object int[] $count;$base[0]=0
    for($step=1;$step-lt$count;$step++){$base[$step]=if($step%2-eq1){($step+1)/2}else{$count-($step/2)}}
    $rowIndex=($Block-1)%$count;$row=New-Object string[] $count
    for($index=0;$index-lt$count;$index++){$row[$index]=$Algorithms[($base[$index]+$rowIndex)%$count]}
    return $row
}

function Get-G13R36LaneNumber {
    param([Parameter(Mandatory=$true)][int]$CampaignOrdinal,[Parameter(Mandatory=$true)][int]$Block,[Parameter(Mandatory=$true)][int]$CohortSize)
    $rowIndex=($Block-1)%$CohortSize
    $cycleIndex=[math]::Floor(($Block-1)/[double]$CohortSize)
    return 1+(($rowIndex+[int]$cycleIndex+($CampaignOrdinal-1))%4)
}

function Get-G13R36PilotCampaigns {
    param([Parameter(Mandatory=$true)][string]$ProjectPath,[Parameter(Mandatory=$true)]$Plan)
    if([string]$Plan.planId-ne$script:G13PlanId-or[string]$Plan.executionDesignId-ne$script:G13DesignId-or$Plan.formalCampaign-ne$false){throw 'Gate13R 36h pilot plan identity/boundary mismatch.'}
    $matrixPath=Join-Path $ProjectPath ([string]$Plan.paths.gate11MatrixRelativePath).Replace('/','\')
    if((Get-G13R36LowerSha256 $matrixPath)-ne[string]$Plan.upstreamHashes.gate11Matrix){throw 'Gate11R matrix hash mismatch.'}
    $matrix=Read-G13R36Json $matrixPath;$rows=New-Object Collections.Generic.List[object];$ordinal=0
    foreach($id in @($Plan.campaignIds)){
        $ordinal++;$matches=@($matrix.campaigns|Where-Object campaignId -eq ([string]$id))
        if($matches.Count-ne1){throw "Pilot campaign must resolve exactly once: $id"}
        $m=$matches[0];$algorithms=@(Get-G13R36CohortAlgorithms ([string]$m.comparisonCohortId))
        if((@($m.eligibleAlgorithmIds|Sort-Object)-join'|')-ne(@($algorithms|Sort-Object)-join'|')){throw "Algorithm-set mismatch: $id"}
        $matrixRows=@($m.williamsRows|Sort-Object rowIndex)
        if($matrixRows.Count-ne$algorithms.Count){throw "Williams row cardinality mismatch: $id"}
        for($i=0;$i-lt$matrixRows.Count;$i++){
            $expected=@(Get-G13R36WilliamsRow -Algorithms $algorithms -Block ($i+1))
            if([int]$matrixRows[$i].rowIndex-ne$i-or(@($matrixRows[$i].algorithms)-join'|')-ne($expected-join'|')){throw "Williams row mismatch: $id/$i"}
        }
        $scenario=Join-Path $ProjectPath ([string]$m.scenarioRelativePath).Replace('/','\')
        if((Get-G13R36LowerSha256 $scenario)-ne[string]$m.scenarioSha256){throw "Scenario hash mismatch: $id"}
        $rows.Add([pscustomobject][ordered]@{ordinal=$ordinal;campaignId=[string]$m.campaignId;scenarioId=[string]$m.scenarioId;scenarioRelativePath=[string]$m.scenarioRelativePath;scenarioSha256=[string]$m.scenarioSha256;scenarioFingerprintSha256=[string]$m.scenarioFingerprintSha256;comparisonCohortId=[string]$m.comparisonCohortId;algorithms=$algorithms;sceneAssetPath=[string]$m.sceneAssetPath;profileAssetPath=[string]$m.profileAssetPath;profileSha256=[string]$m.profileSha256})
    }
    return $rows.ToArray()
}

function Get-G13R36MeasuredSchedule {
    param([Parameter(Mandatory=$true)]$Plan,[Parameter(Mandatory=$true)][object[]]$Campaigns)
    $base=New-Object Collections.Generic.List[object];$count=$Campaigns.Count;$step=[int]$Plan.campaignWaveStep
    for($block=1;$block-le[int]$Plan.measuredBlocksPerCampaign;$block++){
        $offset=(($block-1)*$step)%$count
        for($slot=0;$slot-lt$count;$slot++){
            $campaign=$Campaigns[($offset+$slot)%$count];$size=@($campaign.algorithms).Count
            $lane=Get-G13R36LaneNumber -CampaignOrdinal ([int]$campaign.ordinal) -Block $block -CohortSize $size
            $base.Add([pscustomobject][ordered]@{baseOrdinal=$base.Count+1;block=$block;campaign=$campaign;lane=$lane})
        }
    }
    $queues=@{}
    foreach($lane in 1..4){$queues[$lane]=@($base|Where-Object lane -eq $lane)}
    foreach($lane in 1..4){if($queues[$lane].Count-ne96){throw "Lane $lane does not contain 96 measured blocks."}}
    $schedule=New-Object Collections.Generic.List[object]
    for($wave=1;$wave-le96;$wave++){
        foreach($lane in 1..4){
            $item=$queues[$lane][$wave-1];$campaign=$item.campaign
            $schedule.Add([pscustomobject][ordered]@{ordinal=$schedule.Count+1;wave=$wave;waveSlot=$lane;lane=$lane;baseOrdinal=[int]$item.baseOrdinal;block=[int]$item.block;campaignOrdinal=[int]$campaign.ordinal;campaignId=[string]$campaign.campaignId;scenarioId=[string]$campaign.scenarioId;scenarioRelativePath=[string]$campaign.scenarioRelativePath;scenarioSha256=[string]$campaign.scenarioSha256;comparisonCohortId=[string]$campaign.comparisonCohortId;algorithms=@($campaign.algorithms)})
        }
    }
    return $schedule.ToArray()
}

function Test-G13R36Schedule {
    param([Parameter(Mandatory=$true)][object[]]$Schedule)
    $errors=New-Object Collections.Generic.List[string]
    if($Schedule.Count-ne384){$errors.Add("Expected 384 rows; found $($Schedule.Count).")}
    foreach($lane in 1..4){$rows=@($Schedule|Where-Object lane -eq $lane);if($rows.Count-ne96){$errors.Add("Lane $lane count is $($rows.Count).")}}
    foreach($wave in 1..96){$rows=@($Schedule|Where-Object wave -eq $wave);if($rows.Count-ne4-or(@($rows.lane|Sort-Object -Unique)-join',')-ne'1,2,3,4'){$errors.Add("Wave $wave is not a complete four-lane wave.")}}
    foreach($g in @($Schedule|Group-Object campaignId,lane)){if($g.Count-ne8){$errors.Add("Campaign/lane cell $($g.Name) count is $($g.Count), expected 8.")}}
    foreach($row in $Schedule){$expected=Get-G13R36LaneNumber -CampaignOrdinal ([int]$row.campaignOrdinal) -Block ([int]$row.block) -CohortSize @($row.algorithms).Count;if([int]$row.lane-ne$expected){$errors.Add("Lane formula mismatch at ordinal $($row.ordinal).")}}
    return [pscustomobject][ordered]@{passed=$errors.Count-eq0;errorCount=$errors.Count;errors=$errors.ToArray();rowCount=$Schedule.Count;waveCount=@($Schedule.wave|Sort-Object -Unique).Count}
}

function New-G13R36BlockPlan {
    param(
        [Parameter(Mandatory=$true)][string]$LaneProjectPath,[Parameter(Mandatory=$true)]$Plan,[Parameter(Mandatory=$true)]$Provenance,
        [Parameter(Mandatory=$true)]$Campaign,[Parameter(Mandatory=$true)][int]$Block,[Parameter(Mandatory=$true)][string]$LaneProvenancePath,
        [Parameter(Mandatory=$true)][string]$LaneTelemetryProbeResultPath,
        [ValidateSet('excluded-verification','excluded-negative-fail-closed-verification','excluded-warmup','measured-non-formal-pilot')][string]$AnalysisRole='excluded-verification',
        [ValidateRange(0,4)][int]$InjectedFailurePosition=0,[string]$CampaignIdPrefix='g13r36'
    )
    if([string]$Plan.executionDesignId-ne$script:G13DesignId-or$Plan.formalCampaign-ne$false){throw 'Unauthorized Gate13R 36h plan identity/boundary.'}
    $LaneProjectPath=[IO.Path]::GetFullPath($LaneProjectPath)
    $scenarioPath=Join-Path $LaneProjectPath ([string]$Campaign.scenarioRelativePath).Replace('/','\')
    if((Get-G13R36LowerSha256 $scenarioPath)-ne[string]$Campaign.scenarioSha256){throw 'Lane scenario is missing or hash-invalid.'}
    $probe=Read-G13R36Json $LaneTelemetryProbeResultPath
    if($probe.passed-ne$true-or[string]$probe.executionDesignId-ne$script:G13DesignId){throw 'A passing lane-local telemetry result is required.'}
    $algorithms=@(Get-G13R36CohortAlgorithms ([string]$Campaign.comparisonCohortId));$row=@(Get-G13R36WilliamsRow -Algorithms $algorithms -Block $Block)
    $safeCampaign=('{0}-{1}'-f$CampaignIdPrefix,[string]$Campaign.campaignId).Replace('--','-')
    if($safeCampaign-notmatch'^[A-Za-z0-9][A-Za-z0-9_.-]{0,95}$'){throw 'Unsafe campaign identifier.'}
    $blockId='{0}-b{1:D3}'-f$safeCampaign,$Block;$entries=New-Object Collections.Generic.List[object]
    for($i=0;$i-lt$row.Count;$i++){$slug=Get-G13R36AlgorithmSlug ([string]$row[$i]);$entries.Add([pscustomobject][ordered]@{position=$i+1;algorithmId=[string]$row[$i];predecessorAlgorithmId=$(if($i-eq0){'NONE'}else{[string]$row[$i-1]});runId=('{0}-p{1:D2}-{2}'-f$blockId,($i+1),$slug);directory=('runs/p{0:D2}-{1}'-f($i+1),$slug)})}
    $planObject=[pscustomobject][ordered]@{
        schemaVersion=2;planId=$blockId+'-plan';designId=$script:G13DesignId;blockId=$blockId;campaignId=$safeCampaign
        scenarioRelativePath=[string]$Campaign.scenarioRelativePath;scenarioSourceSha256=[string]$Campaign.scenarioSha256;comparisonCohortId=[string]$Campaign.comparisonCohortId;block=$Block
        formalCampaign=$false;analysisRole=$AnalysisRole;verificationInjectedFailurePosition=$InjectedFailurePosition
        pilotPlanRelativePath=[string]$Provenance.config.relativePath;pilotPlanSha256=[string]$Provenance.config.sha256
        specificationRelativePath=[string]$Provenance.specification.relativePath;specificationSha256=[string]$Provenance.specification.sha256
        testDesignRelativePath=[string]$Provenance.testDesign.relativePath;testDesignSha256=[string]$Provenance.testDesign.sha256
        amendmentRelativePath=[string]$Provenance.executionAuthorization.relativePath;amendmentSha256=[string]$Provenance.executionAuthorization.sha256
        commandRelativePath=[string]$Provenance.unityCommand.relativePath;commandSha256=[string]$Provenance.unityCommand.sha256
        provenanceRelativePath=Get-G13R36ProjectRelativePath -ProjectPath $LaneProjectPath -FullPath $LaneProvenancePath;provenanceSha256=Get-G13R36LowerSha256 $LaneProvenancePath
        telemetryProbeResultRelativePath=Get-G13R36ProjectRelativePath -ProjectPath $LaneProjectPath -FullPath $LaneTelemetryProbeResultPath;telemetryProbeResultSha256=Get-G13R36LowerSha256 $LaneTelemetryProbeResultPath
        entries=$entries.ToArray()
    }
    return $planObject
}

function Test-G13R36PreservationBaseline {
    param([Parameter(Mandatory=$true)][string]$ProjectPath,[Parameter(Mandatory=$true)][string]$BaselinePath)
    $baseline=Read-G13R36Json $BaselinePath;$rows=New-Object Collections.Generic.List[object];$passed=$true
    foreach($item in @($baseline.protectedFiles)){
        $path=Join-Path $ProjectPath ([string]$item.path).Replace('/','\');$exists=Test-Path -LiteralPath $path -PathType Leaf
        $bytes=if($exists){[long](Get-Item -LiteralPath $path).Length}else{-1L};$sha=if($exists){Get-G13R36LowerSha256 $path}else{$null}
        $ok=$exists-and$bytes-eq[long]$item.bytes-and$sha-eq[string]$item.sha256;if(-not$ok){$passed=$false}
        $rows.Add([pscustomobject][ordered]@{path=[string]$item.path;exists=$exists;expectedBytes=[long]$item.bytes;actualBytes=$bytes;expectedSha256=[string]$item.sha256;actualSha256=$sha;passed=$ok})
    }
    foreach($relative in @($baseline.mustRemainAbsent)){if(Test-Path -LiteralPath (Join-Path $ProjectPath ([string]$relative).Replace('/','\'))){$passed=$false}}
    return [pscustomobject][ordered]@{passed=$passed;checkedFileCount=$rows.Count;files=$rows.ToArray();mustRemainAbsent=@($baseline.mustRemainAbsent)}
}

Export-ModuleMember -Function @(
 'Get-G13R36LowerSha256','Get-G13R36StringSha256','Read-G13R36Json','ConvertTo-G13R36JsonText','Write-G13R36Utf8NoBomJson','Write-G13R36AtomicUtf8NoBomJson','Write-G13R36CreateNewUtf8NoBomJson','Get-G13R36ProjectRelativePath','Get-G13R36RawBytes',
 'Get-G13R36AlgorithmSlug','Get-G13R36CohortAlgorithms','Get-G13R36WilliamsRow','Get-G13R36LaneNumber','Get-G13R36PilotCampaigns','Get-G13R36MeasuredSchedule','Test-G13R36Schedule','New-G13R36BlockPlan','Test-G13R36PreservationBaseline'
)
