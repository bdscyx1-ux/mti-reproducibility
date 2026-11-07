[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$ProjectPath,
    [string]$OutputPath = 'Research\Verification\Gate12R_PreImplementation\v1\summary.json'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$ProjectPath = [IO.Path]::GetFullPath($ProjectPath)
$OutputPath = if ([IO.Path]::IsPathRooted($OutputPath)) { [IO.Path]::GetFullPath($OutputPath) } else { [IO.Path]::GetFullPath((Join-Path $ProjectPath $OutputPath)) }
$utf8 = New-Object Text.UTF8Encoding($false)
$checks = New-Object Collections.Generic.List[object]
function Sha([string]$p) { (Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash.ToLowerInvariant() }
function ReadJson([string]$p) { Get-Content -LiteralPath $p -Raw -Encoding UTF8 | ConvertFrom-Json }
function AddCheck([string]$name, [bool]$passed, [string]$detail) { $checks.Add([pscustomobject][ordered]@{name=$name;passed=$passed;detail=$detail}) }
function Full([string]$r) { [IO.Path]::GetFullPath((Join-Path $ProjectPath $r.Replace('/','\'))) }

$spec = Full 'Research/Gate12R_5pct_ProcessReuse_Pilot_Specification.v1.md'
$tests = Full 'Research/Gate12R_5pct_ProcessReuse_Pilot_Test_Design.v1.md'
$auth = Full 'Research/Gate12R_Execution_Authorization.v1.json'
$planPath = Full 'Research/Gate12R_5pct_ProcessReuse_Pilot_Plan.v1.json'
$baselinePath = Full 'Research/Gate12R_PreWrite_Preservation_Baseline.v1.json'
$bundlePath = Full 'Research/FormalScenarios/Gate11R_5pct/v1/bundle-manifest.json'
$matrixPath = Full 'Research/FormalScenarios/Gate11R_5pct/v1/formal-scenario-matrix.json'
$preregPath = Full 'Research/FormalScenarios/Gate11R_5pct/v1/preregistered-analysis.json'
$campaignPath = Full 'Research/PlayableExperiments/Gate11R_5pct/v1/campaign-profile-catalog.json'
$presetPath = Full 'Research/PlayableExperiments/Gate11R_5pct/v1/algorithm-preset-catalog.json'
$scenePath = Full 'Research/PlayableExperiments/Gate11R_5pct/v1/playable-scene-catalog.json'
foreach($p in @($spec,$tests,$auth,$planPath,$baselinePath,$bundlePath,$matrixPath,$preregPath,$campaignPath,$presetPath,$scenePath)){AddCheck ('exists-'+[IO.Path]::GetFileName($p)) (Test-Path -LiteralPath $p -PathType Leaf) $p}

$plan=ReadJson $planPath;$matrix=ReadJson $matrixPath;$prereg=ReadJson $preregPath;$campaigns=ReadJson $campaignPath;$presets=ReadJson $presetPath;$scenes=ReadJson $scenePath;$authObj=ReadJson $auth
AddCheck 'bundle-hash' ((Sha $bundlePath)-eq [string]$plan.upstreamHashes.gate11BundleManifest) (Sha $bundlePath)
AddCheck 'matrix-hash' ((Sha $matrixPath)-eq [string]$plan.upstreamHashes.gate11Matrix) (Sha $matrixPath)
AddCheck 'preregistration-hash' ((Sha $preregPath)-eq [string]$plan.upstreamHashes.gate11Preregistration) (Sha $preregPath)
AddCheck 'campaign-catalog-hash' ((Sha $campaignPath)-eq [string]$plan.upstreamHashes.campaignCatalog) (Sha $campaignPath)
AddCheck 'preset-catalog-hash' ((Sha $presetPath)-eq [string]$plan.upstreamHashes.presetCatalog) (Sha $presetPath)
AddCheck 'scene-catalog-hash' ((Sha $scenePath)-eq [string]$plan.upstreamHashes.sceneCatalog) (Sha $scenePath)
AddCheck 'design-id' ([string]$plan.executionDesignId -eq 'gate10r-one-fresh-unity-process-per-williams-block-5pct-v1') ([string]$plan.executionDesignId)
AddCheck 'non-formal-boundary' ($plan.formalCampaign -eq $false -and $plan.excludedFromFormalAnalysis -eq $true -and $plan.gate13rAuthorized -eq $false) 'formal=false;excluded=true;gate13=false'
AddCheck 'authorization-gate12-only' ($authObj.authorized.gate12rPrePilotGates -eq $true -and $authObj.notAuthorized.gate13rFormalCampaign -eq $true) ([string]$authObj.status)

$ids=@($plan.campaignIds);$unique=@($ids|Sort-Object -Unique)
AddCheck 'campaign-cardinality-and-uniqueness' ($ids.Count -eq 12 -and $unique.Count -eq 12) ("count={0};unique={1}" -f $ids.Count,$unique.Count)
$resolved=@();foreach($id in $ids){$row=@($matrix.campaigns|Where-Object campaignId -eq $id);if($row.Count -eq 1){$resolved+=$row[0]}}
AddCheck 'all-campaigns-resolve-once' ($resolved.Count -eq 12) ("resolved={0}" -f $resolved.Count)
$shared=@($resolved|Where-Object comparisonCohortId -eq 'four-algorithm-shared-goal-v1').Count;$pa=@($resolved|Where-Object comparisonCohortId -eq 'per-agent-heterogeneous-goal-v1').Count;$gf=@($resolved|Where-Object comparisonCohortId -eq 'grouped-field-heterogeneous-goal-v1').Count
AddCheck 'cohort-counts-6-3-3' ($shared -eq 6 -and $pa -eq 3 -and $gf -eq 3) ("shared={0};pa={1};gf={2}" -f $shared,$pa,$gf)
AddCheck 'anchors-equal-preregistered-set' ((@($ids|Sort-Object)-join '|') -eq (@($prereg.pilotCampaignAnchors|Sort-Object)-join '|')) 'exact-set'
AddCheck 'matrix-counts-53-74-212' ([int]$matrix.scenarioCount -eq 53 -and [int]$matrix.campaignCount -eq 74 -and [int]$matrix.eligibilityCount -eq 212) ("{0}/{1}/{2}" -f $matrix.scenarioCount,$matrix.campaignCount,$matrix.eligibilityCount)
AddCheck 'catalog-counts-74-212-53' ([int]$campaigns.campaignCount -eq 74 -and [int]$presets.presetCount -eq 212 -and [int]$scenes.sceneCount -eq 53) ("{0}/{1}/{2}" -f $campaigns.campaignCount,$presets.presetCount,$scenes.sceneCount)
$mappingErrors=@();foreach($c in $resolved){if(@($campaigns.campaigns|Where-Object campaignId -eq $c.campaignId).Count-ne 1){$mappingErrors+="profile:$($c.campaignId)"};foreach($a in @($c.eligibleAlgorithmIds)){if(@($presets.presets|Where-Object{$_.campaignId-eq$c.campaignId-and$_.algorithmId-eq$a}).Count-ne 1){$mappingErrors+="preset:$($c.campaignId):$a"}};if(@($scenes.scenes|Where-Object scenarioId -eq $c.scenarioId).Count-ne 1){$mappingErrors+="scene:$($c.scenarioId)"}}
AddCheck 'anchor-playable-mapping' ($mappingErrors.Count -eq 0) ($mappingErrors -join ';')
AddCheck 'measured-blocks-32' ([int]$plan.measuredBlocksPerCampaign -eq 32) ([string]$plan.measuredBlocksPerCampaign)
AddCheck 'wave-step-coprime' ([int]$plan.campaignWaveStep -eq 5) ([string]$plan.campaignWaveStep)
$warm=@($plan.warmup.blocks);$warmSamples=0;foreach($w in $warm){$c=@($resolved|Where-Object campaignId -eq $w.campaignId)[0];$warmSamples+=@($c.eligibleAlgorithmIds).Count}
AddCheck 'warmup-8-processes-24-samples' ($warm.Count -eq 8 -and $warmSamples -eq 24) ("{0}/{1}" -f $warm.Count,$warmSamples)
$coldSamples=($resolved|ForEach-Object{@($_.eligibleAlgorithmIds).Count}|Measure-Object -Sum).Sum;$measuredSamples=32*$coldSamples
AddCheck 'cold-36-and-measured-1152' ($coldSamples -eq 36 -and $measuredSamples -eq 1152) ("cold={0};measured={1}" -f $coldSamples,$measuredSamples)
AddCheck 'total-arithmetic-429-1212' ([int]$plan.totals.totalUnityProcesses -eq 1+8+36+384 -and [int]$plan.totals.totalSamples -eq 24+36+1152) ("{0}/{1}" -f $plan.totals.totalUnityProcesses,$plan.totals.totalSamples)
AddCheck 'precision-5pct-uncapped' ([double]$plan.precision.relativeHalfWidth -eq 0.05 -and $null -eq $plan.precision.hardCap -and [int]$plan.precision.minimumBlocks -eq 32 -and [int]$plan.precision.cycleMultiple -eq 4) '5pct;min32;multiple4;cap=null'
AddCheck 'formal-campaign-counts-32-21-21' ([int]$plan.formalProjectionCampaignCounts.'four-algorithm-shared-goal-v1' -eq 32 -and [int]$plan.formalProjectionCampaignCounts.'per-agent-heterogeneous-goal-v1' -eq 21 -and [int]$plan.formalProjectionCampaignCounts.'grouped-field-heterogeneous-goal-v1' -eq 21) '32/21/21'
$pilot=Full ([string]$plan.paths.pilotRootRelativePath);$formal=Full ([string]$plan.paths.reservedFormalRootRelativePath)
AddCheck 'pilot-root-absent-before-implementation' (-not(Test-Path -LiteralPath $pilot)) $pilot
AddCheck 'gate13r-root-absent' (-not(Test-Path -LiteralPath $formal)) $formal
AddCheck 'no-unity-process' (@(Get-Process -Name Unity -ErrorAction SilentlyContinue).Count -eq 0) 'Unity count'
AddCheck 'no-project-lock' (-not(Test-Path -LiteralPath (Join-Path $ProjectPath 'Temp\UnityLockfile'))) 'Temp/UnityLockfile'

$failed=@($checks|Where-Object passed -ne $true);$summary=[ordered]@{schemaVersion=1;summaryKind='gate12r-preimplementation-audit-v1';savedAtUtc=[DateTime]::UtcNow.ToString('o');assertionCount=$checks.Count;failureCount=$failed.Count;checks=$checks.ToArray();implementationAuthorizedByAudit=$failed.Count-eq 0;pilotExecutionAuthorizedByAudit=$false;gate13rAuthorized=$false;passed=$failed.Count-eq 0}
$dir=Split-Path -Parent $OutputPath;if(-not(Test-Path -LiteralPath $dir)){New-Item -ItemType Directory -Path $dir|Out-Null};if(Test-Path -LiteralPath $OutputPath){throw "Create-new audit output exists: $OutputPath"};[IO.File]::WriteAllText($OutputPath,(($summary|ConvertTo-Json -Depth 20)+"`n"),$utf8)
if($failed.Count){Write-Error("Gate12R preimplementation audit failed: "+(($failed|ForEach-Object name)-join ', '));exit 1};Write-Host("Gate12R preimplementation audit passed: {0}/{0}" -f $checks.Count) -ForegroundColor Green
