[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$ProjectPath)

$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
$ProjectPath=[IO.Path]::GetFullPath($ProjectPath)
$source=Join-Path $ProjectPath 'Assets\_Scripts\Research\Editor\Gate12RProcessReuseBatchCommandV3.cs'
$output=Join-Path $ProjectPath 'Assets\_Scripts\Research\Editor\Gate13R36hConcurrencyBatchCommandV1.cs'
$receiptPath=Join-Path $ProjectPath 'Research\Gate13R_36h_Concurrency_Command_Derivation.v1.json'
$expected='eeca58f7e1121d0a297e8796430a90ae32f8492c32fc5fb676ae102b5f4a0c97'
$actual=(Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash.ToLowerInvariant()
if($actual-ne$expected){throw "Frozen Gate12R V3 command changed: $actual"}
foreach($path in @($output,$receiptPath)){if(Test-Path -LiteralPath $path){throw "Create-new derivation target exists: $path"}}
$text=[IO.File]::ReadAllText($source,[Text.Encoding]::UTF8)
$routes=@(
 [pscustomobject]@{old='Gate12RProcessReuseBatchCommandV3';new='Gate13R36hConcurrencyBatchCommandV1';count=1},
 [pscustomobject]@{old='gate10r-one-fresh-unity-process-per-williams-block-5pct-v1';new='gate13r-36h-10pct-four-isolated-editor-lanes-v1';count=1},
 [pscustomobject]@{old='gate12r-process-reuse-5pct-process-reuse-block-manifest-v2';new='gate13r-36h-10pct-four-lane-nonformal-block-manifest-v1';count=1},
 [pscustomobject]@{old='gate10r-process-reuse-5pct-process-reuse-sample-summary-v1';new='gate13r-36h-10pct-four-lane-nonformal-sample-summary-v1';count=1},
 [pscustomobject]@{old='gate10r-process-reuse-5pct-process-reuse-block-checkpoint-v1';new='gate13r-36h-10pct-four-lane-nonformal-block-checkpoint-v1';count=1},
 [pscustomobject]@{old='gate10r-process-reuse-5pct-process-reuse-block-failure-v1';new='gate13r-36h-10pct-four-lane-nonformal-block-failure-v1';count=1},
 [pscustomobject]@{old='gate10r-process-reuse-5pct-native-telemetry-probe-ready-v1';new='gate13r-36h-10pct-four-lane-telemetry-probe-ready-v1';count=1},
 [pscustomobject]@{old='gate10r-process-reuse-5pct-native-telemetry-probe-result-v1';new='gate13r-36h-10pct-four-lane-telemetry-probe-result-v1';count=1}
)
$evidence=New-Object Collections.Generic.List[object]
foreach($route in $routes){
 $count=$text.Split([string[]]@([string]$route.old),[StringSplitOptions]::None).Count-1
 if($count-ne[int]$route.count){throw "Replacement count $count, expected $($route.count): $($route.old)"}
 $text=$text.Replace([string]$route.old,[string]$route.new)
 $evidence.Add([pscustomobject][ordered]@{from=[string]$route.old;to=[string]$route.new;count=$count})
}
$utf8=New-Object Text.UTF8Encoding($false,$true)
[IO.File]::WriteAllText($output,$text,$utf8)
$reverse=$text
for($index=$routes.Count-1;$index-ge0;$index--){$reverse=$reverse.Replace([string]$routes[$index].new,[string]$routes[$index].old)}
$reversePath=$output+'.reverse-check.tmp'
[IO.File]::WriteAllText($reversePath,$reverse,$utf8)
try{$reverseHash=(Get-FileHash -LiteralPath $reversePath -Algorithm SHA256).Hash.ToLowerInvariant()}finally{[IO.File]::Delete($reversePath)}
if($reverseHash-ne$expected){throw "Mechanical reverse transform does not recover the frozen source: $reverseHash"}
$receipt=[ordered]@{
 schemaVersion=1;receiptKind='gate13r-36h-four-lane-unity-command-mechanical-derivation-v1';createdAtUtc=[DateTime]::UtcNow.ToString('o')
 sourceRelativePath='Assets/_Scripts/Research/Editor/Gate12RProcessReuseBatchCommandV3.cs';sourceSha256=$actual
 outputRelativePath='Assets/_Scripts/Research/Editor/Gate13R36hConcurrencyBatchCommandV1.cs';outputSha256=(Get-FileHash -LiteralPath $output -Algorithm SHA256).Hash.ToLowerInvariant()
 reverseTransformSha256=$reverseHash;routes=$evidence.ToArray();workloadLogicChanged=$false;resetLogicChanged=$false;telemetryLogicChanged=$false;memoryThresholdsChanged=$false;formalCampaignEnabled=$false
}
$json=($receipt|ConvertTo-Json -Depth 20).Replace("`r`n","`n").Replace("`r","`n")+"`n"
[IO.File]::WriteAllText($receiptPath,$json,$utf8)
$receipt|ConvertTo-Json -Depth 20
