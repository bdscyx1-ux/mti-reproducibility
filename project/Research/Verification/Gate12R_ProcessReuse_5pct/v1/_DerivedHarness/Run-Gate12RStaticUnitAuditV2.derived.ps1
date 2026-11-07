[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$ProjectPath,
    [Parameter(Mandatory=$true)][string]$VerificationRoot,
    [Parameter(Mandatory=$true)][string]$ProvenancePath,
    [switch]$BindingSmokeOnly
)

$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
if([string]::IsNullOrWhiteSpace($ProjectPath)-or-not[IO.Path]::IsPathRooted($ProjectPath)){throw 'Gate12R static/unit audit requires an explicit absolute ProjectPath.'}
$ProjectPath=[IO.Path]::GetFullPath($ProjectPath)
if($BindingSmokeOnly){Write-Output("BINDING-SMOKE-PASSED|Run-Gate12RStaticUnitAudit|$ProjectPath");exit 0}
$VerificationRoot=[IO.Path]::GetFullPath($VerificationRoot);$ProvenancePath=[IO.Path]::GetFullPath($ProvenancePath)
Import-Module (Join-Path $ProjectPath 'Research\Gate12RProcessReusePreparation.psm1') -Force
Import-Module (Join-Path $ProjectPath 'Research\Gate10RProcessReusePreparation.psm1') -Force
$base=[IO.Path]::GetFullPath((Join-Path $ProjectPath 'Research\Verification\Gate12R_ProcessReuse_5pct'))
if(-not$VerificationRoot.StartsWith($base.TrimEnd('\')+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'VerificationRoot is outside the Gate12R versioned base.'}
$output=Join-Path $VerificationRoot 'StaticUnit';if(Test-Path -LiteralPath $output){throw "Create-new static/unit output exists: $output"};New-Item -ItemType Directory -Path $output|Out-Null
$summaryPath=Join-Path $output 'summary.json'
$assertions=0;$failures=New-Object Collections.Generic.List[string]
function Assert-True([bool]$Condition,[string]$Message){$script:assertions++;if(-not$Condition){$script:failures.Add($Message)}}
function Assert-Near([double]$Actual,[double]$Expected,[double]$Tolerance,[string]$Message){$script:assertions++;if([double]::IsNaN($Actual)-or[math]::Abs($Actual-$Expected)-gt$Tolerance){$script:failures.Add("$Message expected=$Expected actual=$Actual")}}
function Assert-Throws([scriptblock]$Action,[string]$Message){$script:assertions++;$threw=$false;try{&$Action|Out-Null}catch{$threw=$true};if(-not$threw){$script:failures.Add($Message)}}
function Get-TreeIdentity([string]$RelativePath){
    $root=[IO.Path]::GetFullPath((Join-Path $ProjectPath $RelativePath.Replace('/','\'))).TrimEnd('\')
    $files=@(Get-ChildItem -LiteralPath $root -Recurse -File -Force);$rows=New-Object Collections.Generic.List[string]
    foreach($file in $files){$relative=$file.FullName.Substring($root.Length).TrimStart('\').Replace('\','/');$rows.Add("$relative`t$($file.Length)`t$(Get-Gate12RLowerSha256 $file.FullName)")};$rows.Sort([StringComparer]::Ordinal)
    $sum=($files|Measure-Object Length -Sum).Sum;if($null-eq$sum){$sum=0L}
    return [pscustomobject]@{fileCount=$files.Count;rawBytes=[long]$sum;ordinalTreeSha256=Get-Gate12RStringSha256 ($rows-join"`n")}
}

try{
    $planPath=Join-Path $ProjectPath 'Research\Gate12R_5pct_ProcessReuse_Pilot_Plan.v1.json';$plan=Read-Gate12RJson $planPath
    $provenance=Read-Gate12RJson $ProvenancePath
    $baselinePath=Join-Path $ProjectPath 'Research\Gate12R_PreWrite_Preservation_Baseline.v2.json';$baseline=Read-Gate12RJson $baselinePath
    Assert-True ((Get-Gate12RLowerSha256 $planPath)-eq'68f32ee7acdeaa4c43a4f4932825e40e552bb5df473a96c66a9dcffef45d8ff3') 'Frozen pilot-plan hash changed.'
    Assert-True ((Get-Gate12RLowerSha256 (Join-Path $ProjectPath 'Research\Gate12R_5pct_ProcessReuse_Pilot_Specification.v1.md'))-eq'a889ee642d6c468c32aff9296a94afc23164232bcd8e3e6ec4729d427723fc76') 'Frozen specification hash changed.'
    Assert-True ((Get-Gate12RLowerSha256 (Join-Path $ProjectPath 'Research\Gate12R_5pct_ProcessReuse_Pilot_Test_Design.v1.md'))-eq'2d275beffa40e6ce66d16551f9313227e486d230772de32eb5affbae97595930') 'Frozen test-design hash changed.'
    Assert-True ((Get-Gate12RLowerSha256 (Join-Path $ProjectPath 'Research\Gate12R_Execution_Authorization.v1.json'))-eq'ae437dddc19576cfcb37d1dbfb48905a0ea3cc9014328c4237d081cb0464cce0') 'Gate12R authorization hash changed.'
    Assert-True ((Get-Gate12RLowerSha256 (Join-Path $ProjectPath ([string]$plan.paths.gate11BundleManifestRelativePath).Replace('/','\')))-eq'5baaeec18344a9e99e55da38f3c4875b7e7e9f3bf0add9d5f2d2f1e821b5f7fc') 'Authorized Gate11R bundle hash changed.'
    foreach($binding in @($provenance.boundFiles)){$path=Join-Path $ProjectPath ([string]$binding.relativePath).Replace('/','\');Assert-True ((Test-Path -LiteralPath $path -PathType Leaf)-and(Get-Gate12RLowerSha256 $path)-eq[string]$binding.sha256) ("Provenance binding failed: "+[string]$binding.relativePath)}
    foreach($treeName in @('gate10rV4Tree','gate11rScenarioTree','gate11rPlayableCatalogTree','gate11rPlayableAssetTree')){$expected=$baseline.upstream.$treeName;$actual=Get-TreeIdentity ([string]$expected.relativePath);Assert-True ($actual.fileCount-eq[int]$expected.fileCount-and$actual.rawBytes-eq[long]$expected.rawBytes-and$actual.ordinalTreeSha256-eq[string]$expected.ordinalTreeSha256) ("Protected tree changed: $treeName")}
    Assert-True (-not(Test-Path -LiteralPath (Join-Path $ProjectPath 'Research\FormalRuns\Gate13R_ProcessReuse_5pct\v1'))) 'Unauthorized Gate13R formal root exists.'
    Assert-True ($plan.formalCampaign-eq$false-and$plan.excludedFromFormalAnalysis-eq$true-and$plan.gate13rAuthorized-eq$false) 'Non-formal boundary changed.'
    Assert-True ([string]$plan.executionDesignId-eq'gate10r-one-fresh-unity-process-per-williams-block-5pct-v1') 'Execution design ID changed.'
    Assert-True ([int]$plan.measuredBlocksPerCampaign-eq32-and[int]$plan.campaignWaveStep-eq5) 'Measured block/wave policy changed.'
    Assert-True ($null-eq$plan.precision.hardCap-and[double]$plan.precision.relativeHalfWidth-eq0.05-and[int]$plan.precision.minimumBlocks-eq32-and[int]$plan.precision.cycleMultiple-eq4) 'Uncapped 5% precision policy changed.'
    Assert-Near ([double]$plan.precision.logHalfWidth) ([math]::Log(1.05)) 1e-14 'Log half-width mismatch.'

    $campaigns=@(Get-Gate12RCampaigns -ProjectPath $ProjectPath -Plan $plan);$schedule=@(Get-Gate12RMeasuredSchedule -Plan $plan -Campaigns $campaigns)
    Assert-True ($campaigns.Count-eq12) 'Pilot subset is not exactly 12 campaigns.'
    Assert-True (@($campaigns|Where-Object comparisonCohortId -eq 'four-algorithm-shared-goal-v1').Count-eq6) 'Shared pilot count mismatch.'
    Assert-True (@($campaigns|Where-Object comparisonCohortId -eq 'per-agent-heterogeneous-goal-v1').Count-eq3) 'Per-agent pilot count mismatch.'
    Assert-True (@($campaigns|Where-Object comparisonCohortId -eq 'grouped-field-heterogeneous-goal-v1').Count-eq3) 'Grouped pilot count mismatch.'
    Assert-True ($schedule.Count-eq384-and@($plan.warmup.blocks).Count-eq8-and[int]$plan.totals.coldControlProcesses-eq36-and[int]$plan.totals.totalUnityProcesses-eq429-and[int]$plan.totals.totalSamples-eq1212) 'Frozen process/sample cardinalities mismatch.'
    foreach($campaign in $campaigns){$rows=@($schedule|Where-Object {$_.campaign.campaignId-eq$campaign.campaignId});Assert-True ($rows.Count-eq32-and@($rows.block|Sort-Object -Unique).Count-eq32) ("Measured block coverage mismatch: "+$campaign.campaignId);$algorithms=@(Get-Gate12RCohortAlgorithms $campaign.comparisonCohortId);for($position=0;$position-lt$algorithms.Count;$position++){foreach($algorithm in $algorithms){$count=0;foreach($block in 1..32){$row=@(Get-Gate12RWilliamsRow -Algorithms $algorithms -Block $block);if($row[$position]-eq$algorithm){$count++}};$expected=32/$algorithms.Count;Assert-True ($count-eq$expected) ("Position balance mismatch: $($campaign.campaignId)/$algorithm/P$($position+1)")}}}
    for($wave=1;$wave-le32;$wave++){$ids=@($schedule|Where-Object wave -eq $wave|ForEach-Object {$_.campaign.campaignId});Assert-True ($ids.Count-eq12-and@($ids|Sort-Object -Unique).Count-eq12) "Wave $wave is not a campaign permutation."}

    Assert-Near (Get-Gate12RSampleStandardDeviation ([double[]]@(0,1,2,3))) ([math]::Sqrt(5.0/3.0)) 1e-12 'Sample SD fixture mismatch.'
    Assert-Near (Get-Gate12RNearestRankPercentile -Values ([double[]]@(1,2,3,4,5)) -Probability 0.95) 5.0 1e-12 'Nearest-rank p95 mismatch.'
    Assert-Near (Get-Gate12RPearsonCorrelation -X ([double[]]@(1,2,3)) -Y ([double[]]@(2,4,6))) 1.0 1e-12 'Pearson fixture mismatch.'
    Assert-Near (Get-Gate12RSpearmanCorrelation -X ([double[]]@(3,1,2)) -Y ([double[]]@(30,10,20))) 1.0 1e-12 'Spearman fixture mismatch.'
    Assert-Near (Get-Gate12RChiSquareQuantile -Probability 0.1 -DegreesOfFreedom 1) 0.0157907740934312 1e-10 'Chi-square df=1 fixture mismatch.'
    Assert-Near (Get-Gate12RChiSquareQuantile -Probability 0.1 -DegreesOfFreedom 31) 21.4335645003108 1e-9 'Chi-square df=31 fixture mismatch.'
    $sigma=Get-Gate12RSigmaUpper -SampleSd 1.0 -N 32 -Confidence 0.90;Assert-Near $sigma.sigmaUpper 1.20263446540178 1e-10 'One-sided sigma upper fixture mismatch.'
    $candidate=Get-Gate12RSampleSizeCandidate -SigmaUpper 0.25;Assert-True ($candidate.hardCap-eq$null-and$candidate.candidateNFormal%4-eq0-and$candidate.candidateNFormal-ge32-and$candidate.overCap-eq$false) 'Uncapped sample-size result invalid.'
    Assert-Throws {Get-Gate12RSampleSizeCandidate -SigmaUpper ([double]::NaN)} 'NaN sigma was accepted.'
    Assert-Throws {Get-Gate12RChiSquareQuantile -Probability 1.0 -DegreesOfFreedom 31} 'Invalid chi-square probability was accepted.'

    $valid=[pscustomobject][ordered]@{schemaVersion=2;designId='gate10r-one-fresh-unity-process-per-williams-block-5pct-v1';planId='unit-plan';blockId='unit-block';campaignId='unit-campaign';comparisonCohortId='per-agent-heterogeneous-goal-v1';block=1;formalCampaign=$false;analysisRole='excluded-verification';verificationInjectedFailurePosition=0;entries=@([pscustomobject]@{position=1;algorithmId='A*-R';predecessorAlgorithmId='NONE';runId='unit-a';directory='runs/a'},[pscustomobject]@{position=2;algorithmId='D*L';predecessorAlgorithmId='A*-R';runId='unit-d';directory='runs/d'})}
    Assert-True ((Test-Gate10RBlockPlanObject $valid).passed-eq$true) 'Valid block-plan fixture rejected.'
    $badFormal=$valid.PSObject.Copy();$badFormal.formalCampaign=$true;Assert-True ((Test-Gate10RBlockPlanObject $badFormal).passed-eq$false) 'Formal block plan was accepted.'
    $badRow=$valid.PSObject.Copy();$badRow.entries=@($valid.entries[1],$valid.entries[0]);Assert-True ((Test-Gate10RBlockPlanObject $badRow).passed-eq$false) 'Wrong Williams row was accepted.'

    $sceneCatalog=Read-Gate12RJson (Join-Path $ProjectPath ([string]$plan.paths.sceneCatalogRelativePath).Replace('/','\'))
    $profileCatalog=Read-Gate12RJson (Join-Path $ProjectPath ([string]$plan.paths.campaignCatalogRelativePath).Replace('/','\'))
    $presetCatalog=Read-Gate12RJson (Join-Path $ProjectPath ([string]$plan.paths.presetCatalogRelativePath).Replace('/','\'))
    $playableRows=New-Object Collections.Generic.List[object]
    foreach($campaign in $campaigns){$scene=@($sceneCatalog.scenes|Where-Object scenarioId -eq $campaign.scenarioId);$profile=@($profileCatalog.campaigns|Where-Object campaignId -eq $campaign.campaignId);$presets=@($presetCatalog.presets|Where-Object campaignId -eq $campaign.campaignId);Assert-True ($scene.Count-eq1-and$profile.Count-eq1-and$presets.Count-eq$campaign.algorithms.Count) ("Playable mapping cardinality mismatch: "+$campaign.campaignId);if($scene.Count-eq1){$scenePath=Join-Path $ProjectPath ([string]$scene[0].sceneAssetPath).Replace('/','\');Assert-True ((Test-Path $scenePath)-and(Get-Gate12RLowerSha256 $scenePath)-eq[string]$scene[0].sceneSha256) ("Playable scene hash mismatch: "+$campaign.campaignId)};if($profile.Count-eq1){$profilePath=Join-Path $ProjectPath ([string]$profile[0].profileAssetPath).Replace('/','\');Assert-True ((Test-Path $profilePath)-and(Get-Gate12RLowerSha256 $profilePath)-eq[string]$profile[0].profileSha256) ("Campaign profile hash mismatch: "+$campaign.campaignId)};foreach($preset in $presets){$presetPath=Join-Path $ProjectPath ([string]$preset.presetAssetPath).Replace('/','\');Assert-True ((Test-Path $presetPath)-and(Get-Gate12RLowerSha256 $presetPath)-eq[string]$preset.presetSha256) ("Algorithm preset hash mismatch: "+$preset.presetId)};$playableRows.Add([pscustomobject]@{campaignId=$campaign.campaignId;scenarioId=$campaign.scenarioId;sceneAssetPath=$campaign.sceneAssetPath;profileAssetPath=$campaign.profileAssetPath;presetCount=$presets.Count;algorithms=$campaign.algorithms})}
    Write-Gate12RAtomicUtf8NoBomJson -Path (Join-Path $output 'playable-mapping-validation.json') -Value ([ordered]@{schemaVersion=1;campaignCount=$playableRows.Count;rows=$playableRows.ToArray();formalTimingEvidenceAllowed=$false;passed=$true}) -Depth 30
}catch{$failures.Add($_.Exception.ToString())}
$summary=[ordered]@{schemaVersion=1;summaryKind='gate12r-static-unit-audit-v2-tree-identity-compatibility';savedAtUtc=[DateTime]::UtcNow.ToString('o');provenancePath=$ProvenancePath;provenanceSha256=if(Test-Path $ProvenancePath){Get-Gate12RLowerSha256 $ProvenancePath}else{$null};assertionCount=$assertions;failureCount=$failures.Count;failures=$failures.ToArray();formalCampaign=$false;gate13rAuthorized=$false;passed=$failures.Count-eq0}
Write-Gate12RAtomicUtf8NoBomJson -Path $summaryPath -Value $summary -Depth 30
if($failures.Count){Write-Error("Gate12R static/unit audit failed: "+($failures-join'; '));exit 1}
Write-Host "Gate12R static/unit audit passed $assertions assertions." -ForegroundColor Green
exit 0
