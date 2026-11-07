Set-StrictMode -Version Latest

$script:G12Utf8 = New-Object System.Text.UTF8Encoding($false)
$script:G12DesignId = 'gate10r-one-fresh-unity-process-per-williams-block-5pct-v1'
$script:G12PlanId = 'gate12r-fresh-process-reuse-5pct-pilot-plan-v3-consolidated-memory-aggregation'
$script:G12Gate10Module = Join-Path $PSScriptRoot 'Gate10RProcessReusePreparation.psm1'
Import-Module $script:G12Gate10Module -Force

function Get-Gate12RLowerSha256 {
    param([Parameter(Mandatory=$true)][string]$Path)
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Get-Gate12RStringSha256 {
    param([Parameter(Mandatory=$true)][string]$Value)
    $sha=[Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash($script:G12Utf8.GetBytes($Value)))).Replace('-','').ToLowerInvariant() }
    finally { $sha.Dispose() }
}

function Read-Gate12RJson {
    param([Parameter(Mandatory=$true)][string]$Path)
    return Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
}

function ConvertTo-Gate12RJsonText {
    param([Parameter(Mandatory=$true)]$Value,[int]$Depth=50)
    $text=($Value|ConvertTo-Json -Depth $Depth).Replace("`r`n","`n").Replace("`r","`n")
    if(-not $text.EndsWith("`n")){$text+="`n"}
    return $text
}

function Write-Gate12RUtf8NoBomJson {
    param([Parameter(Mandatory=$true)][string]$Path,[Parameter(Mandatory=$true)]$Value,[int]$Depth=50)
    [IO.File]::WriteAllText($Path,(ConvertTo-Gate12RJsonText -Value $Value -Depth $Depth),$script:G12Utf8)
}

function Write-Gate12RAtomicUtf8NoBomJson {
    param([Parameter(Mandatory=$true)][string]$Path,[Parameter(Mandatory=$true)]$Value,[int]$Depth=50)
    $directory=Split-Path -Parent $Path
    if(-not(Test-Path -LiteralPath $directory -PathType Container)){New-Item -ItemType Directory -Path $directory|Out-Null}
    $temporary=$Path+'.tmp-'+[Guid]::NewGuid().ToString('N')
    Write-Gate12RUtf8NoBomJson -Path $temporary -Value $Value -Depth $Depth
    Move-Item -LiteralPath $temporary -Destination $Path -Force
}

function Get-Gate12RProjectRelativePath {
    param([Parameter(Mandatory=$true)][string]$ProjectPath,[Parameter(Mandatory=$true)][string]$FullPath)
    $root=[IO.Path]::GetFullPath($ProjectPath).TrimEnd('\')+'\'
    $candidate=[IO.Path]::GetFullPath($FullPath)
    if(-not$candidate.StartsWith($root,[StringComparison]::OrdinalIgnoreCase)){throw "Path escapes project root: $candidate"}
    return $candidate.Substring($root.Length).Replace('\','/')
}

function Get-Gate12RAlgorithmSlug {
    param([Parameter(Mandatory=$true)][string]$AlgorithmId)
    return Get-Gate10RAlgorithmSlug -AlgorithmId $AlgorithmId
}

function Get-Gate12RCohortAlgorithms {
    param([Parameter(Mandatory=$true)][string]$ComparisonCohortId)
    return @(Get-Gate10RCohortAlgorithms -ComparisonCohortId $ComparisonCohortId)
}

function Get-Gate12RWilliamsRow {
    param([Parameter(Mandatory=$true)][string[]]$Algorithms,[Parameter(Mandatory=$true)][int]$Block)
    return @(Get-Gate10RWilliamsRow -Algorithms $Algorithms -Block $Block)
}

function Get-Gate12RCampaigns {
    param([Parameter(Mandatory=$true)][string]$ProjectPath,[Parameter(Mandatory=$true)]$Plan)
    if([string]$Plan.planId-ne$script:G12PlanId-or[string]$Plan.executionDesignId-ne$script:G12DesignId-or$Plan.formalCampaign-ne$false){throw 'Gate12R plan identity or non-formal boundary mismatch.'}
    $matrixPath=Join-Path $ProjectPath ([string]$Plan.paths.gate11MatrixRelativePath).Replace('/','\')
    if((Get-Gate12RLowerSha256 $matrixPath)-ne[string]$Plan.upstreamHashes.gate11Matrix){throw 'Gate11R matrix hash mismatch.'}
    $matrix=Read-Gate12RJson $matrixPath
    $rows=New-Object Collections.Generic.List[object]
    $ordinal=0
    foreach($id in @($Plan.campaignIds)){
        $ordinal++
        $matches=@($matrix.campaigns|Where-Object campaignId -eq ([string]$id))
        if($matches.Count-ne 1){throw "Pilot campaign must resolve exactly once: $id"}
        $m=$matches[0]
        $algorithms=@(Get-Gate12RCohortAlgorithms -ComparisonCohortId ([string]$m.comparisonCohortId))
        if((@($m.eligibleAlgorithmIds|Sort-Object)-join '|')-ne(@($algorithms|Sort-Object)-join '|')){throw "Campaign algorithm set differs from Gate10R contract: $id"}
        $matrixRows=@($m.williamsRows|Sort-Object rowIndex)
        if($matrixRows.Count-ne$algorithms.Count){throw "Campaign Williams row count differs from Gate10R contract: $id"}
        for($rowIndex=0;$rowIndex-lt$matrixRows.Count;$rowIndex++){
            $expectedRow=@(Get-Gate12RWilliamsRow -Algorithms $algorithms -Block ($rowIndex+1))
            if([int]$matrixRows[$rowIndex].rowIndex-ne$rowIndex-or(@($matrixRows[$rowIndex].algorithms)-join '|')-ne($expectedRow-join '|')){throw "Campaign Williams row differs from Gate10R contract: $id row $rowIndex"}
        }
        $scenarioPath=Join-Path $ProjectPath ([string]$m.scenarioRelativePath).Replace('/','\')
        if((Get-Gate12RLowerSha256 $scenarioPath)-ne[string]$m.scenarioSha256){throw "Scenario hash mismatch: $id"}
        $rows.Add([pscustomobject][ordered]@{
            ordinal=$ordinal;campaignId=[string]$m.campaignId;scenarioId=[string]$m.scenarioId;scenarioRelativePath=[string]$m.scenarioRelativePath
            scenarioSha256=[string]$m.scenarioSha256;scenarioFingerprintSha256=[string]$m.scenarioFingerprintSha256
            comparisonCohortId=[string]$m.comparisonCohortId;algorithms=$algorithms;sceneAssetPath=[string]$m.sceneAssetPath
            profileAssetPath=[string]$m.profileAssetPath;profileAssetGuid=[string]$m.profileAssetGuid;profileSha256=[string]$m.profileSha256
        })
    }
    return $rows.ToArray()
}

function Get-Gate12RMeasuredSchedule {
    param([Parameter(Mandatory=$true)]$Plan,[Parameter(Mandatory=$true)][object[]]$Campaigns)
    $schedule=New-Object Collections.Generic.List[object]
    $count=$Campaigns.Count;$step=[int]$Plan.campaignWaveStep
    for($block=1;$block-le[int]$Plan.measuredBlocksPerCampaign;$block++){
        $offset=(($block-1)*$step)%$count
        for($slot=0;$slot-lt$count;$slot++){
            $campaign=$Campaigns[($offset+$slot)%$count]
            $schedule.Add([pscustomobject][ordered]@{ordinal=$schedule.Count+1;wave=$block;waveSlot=$slot+1;block=$block;campaign=$campaign})
        }
    }
    return $schedule.ToArray()
}

function New-Gate12RBlockPlan {
    param(
        [Parameter(Mandatory=$true)][string]$ProjectPath,[Parameter(Mandatory=$true)]$Plan,[Parameter(Mandatory=$true)]$Provenance,
        [Parameter(Mandatory=$true)]$Campaign,[Parameter(Mandatory=$true)][int]$Block,[Parameter(Mandatory=$true)][string]$ProvenancePath,
        [Parameter(Mandatory=$true)][string]$TelemetryProbeResultPath,
        [ValidateSet('excluded-verification','excluded-negative-fail-closed-verification','excluded-warmup','measured-non-formal-pilot')][string]$AnalysisRole='excluded-verification',
        [ValidateRange(0,4)][int]$InjectedFailurePosition=0,[string]$CampaignIdPrefix='g12r'
    )
    $campaignId=('{0}-{1}'-f $CampaignIdPrefix,[string]$Campaign.campaignId).Replace('--','-')
    # Gate 12R deliberately names the frozen upstream contract
    # `executionDesignId`; the retained Gate 10R block-plan builder expects the
    # same value under its historical `designId` adapter property.  Keep this
    # translation local so the frozen Gate 12R plan bytes remain unchanged.
    $gate10ConfigAdapter=[pscustomobject][ordered]@{
        designId=[string]$Plan.executionDesignId
        formalCampaign=[bool]$Plan.formalCampaign
    }
    return New-Gate10RBlockPlan -ProjectPath $ProjectPath -Config $gate10ConfigAdapter -Provenance $Provenance -CampaignId $campaignId -ScenarioRelativePath ([string]$Campaign.scenarioRelativePath) -ScenarioSourceSha256 ([string]$Campaign.scenarioSha256) -ComparisonCohortId ([string]$Campaign.comparisonCohortId) -Block $Block -ProvenancePath $ProvenancePath -TelemetryProbeResultPath $TelemetryProbeResultPath -AnalysisRole $AnalysisRole -InjectedFailurePosition $InjectedFailurePosition
}

function Get-Gate12RMean { param([double[]]$Values) if($Values.Count-lt1){throw 'Mean requires values.'};return [double](($Values|Measure-Object -Average).Average) }

function Get-Gate12RSampleStandardDeviation {
    param([double[]]$Values)
    if($Values.Count-lt2){throw 'Sample standard deviation requires at least two values.'}
    $mean=Get-Gate12RMean $Values;$sum=0.0;foreach($v in $Values){$d=$v-$mean;$sum+=$d*$d};return [math]::Sqrt($sum/($Values.Count-1))
}

function Get-Gate12RNearestRankPercentile {
    param([double[]]$Values,[Parameter(Mandatory=$true)][double]$Probability)
    if($Values.Count-lt1-or$Probability-lt0-or$Probability-gt1){throw 'Invalid percentile input.'}
    $sorted=@($Values|Sort-Object);$rank=[math]::Max(1,[math]::Ceiling($Probability*$sorted.Count));return [double]$sorted[$rank-1]
}

function Get-Gate12RPearsonCorrelation {
    param([double[]]$X,[double[]]$Y)
    if($X.Count-ne$Y.Count-or$X.Count-lt2){throw 'Correlation vectors must have equal length >= 2.'}
    $mx=Get-Gate12RMean $X;$my=Get-Gate12RMean $Y;$cross=0.0;$sx=0.0;$sy=0.0
    for($i=0;$i-lt$X.Count;$i++){$dx=$X[$i]-$mx;$dy=$Y[$i]-$my;$cross+=$dx*$dy;$sx+=$dx*$dx;$sy+=$dy*$dy}
    if($sx-le0-or$sy-le0){return 0.0};return $cross/[math]::Sqrt($sx*$sy)
}

function Get-Gate12RAverageRanks {
    param([double[]]$Values)
    $indexed=for($i=0;$i-lt$Values.Count;$i++){[pscustomobject]@{i=$i;v=$Values[$i]}}
    $sorted=@($indexed|Sort-Object v,i);$ranks=New-Object double[] $Values.Count;$p=0
    while($p-lt$sorted.Count){$q=$p;while($q+1-lt$sorted.Count-and$sorted[$q+1].v-eq$sorted[$p].v){$q++};$rank=(($p+1)+($q+1))/2.0;for($k=$p;$k-le$q;$k++){$ranks[$sorted[$k].i]=$rank};$p=$q+1}
    return $ranks
}

function Get-Gate12RSpearmanCorrelation { param([double[]]$X,[double[]]$Y) return Get-Gate12RPearsonCorrelation (Get-Gate12RAverageRanks $X) (Get-Gate12RAverageRanks $Y) }

function Get-Gate12RConsistencyIcc {
    param([Parameter(Mandatory=$true)][double[][]]$Rows)
    $n=$Rows.Count;if($n-lt2){throw 'ICC requires at least two blocks.'};$k=$Rows[0].Count;if($k-lt2){throw 'ICC requires at least two algorithms.'}
    foreach($row in $Rows){if($row.Count-ne$k){throw 'ICC rows must have equal length.'}}
    $grand=0.0;foreach($row in $Rows){foreach($v in $row){$grand+=$v}};$grand/=($n*$k)
    $rowMeans=@();for($i=0;$i-lt$n;$i++){$rowMeans+=Get-Gate12RMean $Rows[$i]}
    $columnMeans=New-Object double[] $k;for($j=0;$j-lt$k;$j++){$vals=for($i=0;$i-lt$n;$i++){$Rows[$i][$j]};$columnMeans[$j]=Get-Gate12RMean ([double[]]$vals)}
    $ssRows=0.0;foreach($m in $rowMeans){$ssRows+=$k*[math]::Pow($m-$grand,2)}
    $ssCols=0.0;foreach($m in $columnMeans){$ssCols+=$n*[math]::Pow($m-$grand,2)}
    $ssTotal=0.0;for($i=0;$i-lt$n;$i++){for($j=0;$j-lt$k;$j++){$ssTotal+=[math]::Pow($Rows[$i][$j]-$grand,2)}}
    $ssError=[math]::Max(0.0,$ssTotal-$ssRows-$ssCols);$msRows=$ssRows/($n-1);$msError=$ssError/(($n-1)*($k-1));$den=$msRows+($k-1)*$msError
    $icc=if($den-eq0){0.0}else{($msRows-$msError)/$den}
    return [pscustomobject][ordered]@{model='ICC-C-1-two-way-mixed-consistency-v1';blocks=$n;algorithms=$k;msBlock=$msRows;msError=$msError;icc=$icc}
}

function Get-Gate12RLogGamma {
    param([double]$Z)
    $p=@(0.99999999999980993,676.5203681218851,-1259.1392167224028,771.32342877765313,-176.61502916214059,12.507343278686905,-0.13857109526572012,9.9843695780195716e-6,1.5056327351493116e-7)
    if($Z-lt0.5){return [math]::Log([math]::PI)-[math]::Log([math]::Sin([math]::PI*$Z))-(Get-Gate12RLogGamma (1.0-$Z))}
    $z1=$Z-1.0;$x=$p[0];for($i=1;$i-lt$p.Count;$i++){$x+=$p[$i]/($z1+$i)};$t=$z1+7.5
    return 0.5*[math]::Log(2.0*[math]::PI)+($z1+0.5)*[math]::Log($t)-$t+[math]::Log($x)
}

function Get-Gate12RRegularizedGammaP {
    param([double]$A,[double]$X)
    if($A-le0-or$X-lt0){throw 'Invalid gamma arguments.'};if($X-eq0){return 0.0}
    $eps=1e-14;$tiny=1e-300;$gln=Get-Gate12RLogGamma $A
    if($X-lt($A+1.0)){$ap=$A;$sum=1.0/$A;$del=$sum;for($n=1;$n-le10000;$n++){$ap+=1.0;$del*=$X/$ap;$sum+=$del;if([math]::Abs($del)-lt[math]::Abs($sum)*$eps){break}};return $sum*[math]::Exp(-$X+$A*[math]::Log($X)-$gln)}
    $b=$X+1.0-$A;$c=1.0/$tiny;$d=1.0/$b;$h=$d
    for($i=1;$i-le10000;$i++){$an=-$i*($i-$A);$b+=2.0;$d=$an*$d+$b;if([math]::Abs($d)-lt$tiny){$d=$tiny};$c=$b+$an/$c;if([math]::Abs($c)-lt$tiny){$c=$tiny};$d=1.0/$d;$delta=$d*$c;$h*=$delta;if([math]::Abs($delta-1.0)-lt$eps){break}}
    $q=[math]::Exp(-$X+$A*[math]::Log($X)-$gln)*$h;return 1.0-$q
}

function Get-Gate12RChiSquareQuantile {
    param([Parameter(Mandatory=$true)][double]$Probability,[Parameter(Mandatory=$true)][int]$DegreesOfFreedom)
    if($Probability-le0-or$Probability-ge1-or$DegreesOfFreedom-lt1){throw 'Invalid chi-square quantile input.'}
    $low=0.0;$high=[math]::Max(1.0,[double]$DegreesOfFreedom)
    while((Get-Gate12RRegularizedGammaP ($DegreesOfFreedom/2.0) ($high/2.0)) -lt $Probability){$high*=2.0;if($high-gt1e12){throw 'Chi-square quantile bracketing failed.'}}
    for($i=0;$i-lt200;$i++){$mid=($low+$high)/2.0;$cdf=Get-Gate12RRegularizedGammaP ($DegreesOfFreedom/2.0) ($mid/2.0);if($cdf-lt$Probability){$low=$mid}else{$high=$mid}}
    return ($low+$high)/2.0
}

function Get-Gate12RSigmaUpper {
    param([Parameter(Mandatory=$true)][double]$SampleSd,[Parameter(Mandatory=$true)][int]$N,[double]$Confidence=0.90)
    if($SampleSd-lt0-or$N-lt2-or$Confidence-le0-or$Confidence-ge1){throw 'Invalid sigma upper input.'}
    $df=$N-1;$lowerTail=1.0-$Confidence;$q=Get-Gate12RChiSquareQuantile -Probability $lowerTail -DegreesOfFreedom $df
    return [pscustomobject][ordered]@{sampleSd=$SampleSd;n=$N;degreesOfFreedom=$df;confidence=$Confidence;chiSquareLowerTailProbability=$lowerTail;chiSquareQuantile=$q;sigmaUpper=$SampleSd*[math]::Sqrt($df/$q)}
}

function Get-Gate12RSampleSizeCandidate {
    param([Parameter(Mandatory=$true)][double]$SigmaUpper,[double]$Z=1.96,[double]$RelativeHalfWidth=0.05,[int]$MinimumBlocks=32,[int]$CycleMultiple=4)
    return Get-Gate10RSampleSizeCandidate -SigmaUpper $SigmaUpper -Z $Z -RelativeHalfWidth $RelativeHalfWidth -MinimumBlocks $MinimumBlocks -CycleMultiple $CycleMultiple
}

function Get-Gate12RRawBytes {
    param([Parameter(Mandatory=$true)][string]$Path)
    if(-not(Test-Path -LiteralPath $Path)){return 0L};if(Test-Path -LiteralPath $Path -PathType Leaf){return [long](Get-Item -LiteralPath $Path).Length};return [long](Get-ChildItem -LiteralPath $Path -Recurse -File -Force|Measure-Object Length -Sum).Sum
}

Export-ModuleMember -Function @(
 'Get-Gate12RLowerSha256','Get-Gate12RStringSha256','Read-Gate12RJson','ConvertTo-Gate12RJsonText','Write-Gate12RUtf8NoBomJson','Write-Gate12RAtomicUtf8NoBomJson','Get-Gate12RProjectRelativePath',
 'Get-Gate12RAlgorithmSlug','Get-Gate12RCohortAlgorithms','Get-Gate12RWilliamsRow','Get-Gate12RCampaigns','Get-Gate12RMeasuredSchedule','New-Gate12RBlockPlan',
 'Get-Gate12RMean','Get-Gate12RSampleStandardDeviation','Get-Gate12RNearestRankPercentile','Get-Gate12RPearsonCorrelation','Get-Gate12RAverageRanks','Get-Gate12RSpearmanCorrelation','Get-Gate12RConsistencyIcc',
 'Get-Gate12RLogGamma','Get-Gate12RRegularizedGammaP','Get-Gate12RChiSquareQuantile','Get-Gate12RSigmaUpper','Get-Gate12RSampleSizeCandidate','Get-Gate12RRawBytes'
)
