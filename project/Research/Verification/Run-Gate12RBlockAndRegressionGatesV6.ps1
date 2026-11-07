[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$ProjectPath,
    [Parameter(Mandatory=$true)][string]$VerificationRoot,
    [Parameter(Mandatory=$true)][string]$ProvenancePath,
    [Parameter(Mandatory=$true)][string]$TelemetryResultPath,
    [string]$UnityPath='H:\UnityEditor\2022.3.30f1c1\Editor\Unity.exe',
    [switch]$BindingSmokeOnly
)

$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
if([string]::IsNullOrWhiteSpace($ProjectPath)-or-not[IO.Path]::IsPathRooted($ProjectPath)){throw 'Gate12R block/regression v6 memory-amended wrapper requires an explicit absolute ProjectPath.'};$ProjectPath=[IO.Path]::GetFullPath($ProjectPath)
if($BindingSmokeOnly){Write-Output("BINDING-SMOKE-PASSED|Run-Gate12RBlockAndRegressionGatesV6|$ProjectPath");exit 0}
$VerificationRoot=[IO.Path]::GetFullPath($VerificationRoot);$ProvenancePath=[IO.Path]::GetFullPath($ProvenancePath);$TelemetryResultPath=[IO.Path]::GetFullPath($TelemetryResultPath);$UnityPath=[IO.Path]::GetFullPath($UnityPath)
$source=Join-Path $ProjectPath 'Research\Verification\Run-Gate12RBlockAndRegressionGates.ps1';$expectedSourceSha256='fa2385bc102b93bc90608d3901634d6b51e996429238a9875f0d7c024426511a';$actualSourceSha256=(Get-FileHash $source -Algorithm SHA256).Hash.ToLowerInvariant();if($actualSourceSha256-ne$expectedSourceSha256){throw "Frozen block/regression source changed: $actualSourceSha256"}
$text=[IO.File]::ReadAllText($source,[Text.Encoding]::UTF8)
$routes=@(
 [pscustomobject]@{old='Research\Run-Gate12RProcessReuseBlock.ps1';new='Research\Run-Gate12RProcessReuseBlockV5.ps1';count=1},
 [pscustomobject]@{old='Research\Run-Gate12RColdReference.ps1';new='Research\Run-Gate12RColdReferenceV3.ps1';count=1},
 [pscustomobject]@{old='Research\Gate12R_5pct_ProcessReuse_Pilot_Plan.v1.json';new='Research\Gate12R_5pct_ProcessReuse_Pilot_Plan.v5.json';count=1},
 [pscustomobject]@{old="summaryKind='gate12r-block-cold-repeatability-retained-regression-gates-v1'";new="summaryKind='gate12r-block-cold-repeatability-retained-regression-gates-v4-memory-aggregation'";count=1}
)
$evidence=New-Object Collections.Generic.List[object];foreach($route in $routes){$actual=$text.Split([string[]]@([string]$route.old),[StringSplitOptions]::None).Count-1;if($actual-ne[int]$route.count){throw "Block/regression v4 replacement count for '$($route.old)' is $actual, expected $($route.count)."};$text=$text.Replace([string]$route.old,[string]$route.new);$evidence.Add([pscustomobject]@{from=$route.old;to=$route.new;replacementCount=$actual})}
$derivedRoot=Join-Path $VerificationRoot '_DerivedHarness\BlockRegressionV6';if(Test-Path $derivedRoot){throw "Create-new block/regression v6 derived root exists: $derivedRoot"};New-Item -ItemType Directory -Path $derivedRoot -Force|Out-Null;$derivedPath=Join-Path $derivedRoot 'Run-Gate12RBlockAndRegressionGatesV6.derived.ps1';[IO.File]::WriteAllText($derivedPath,$text,(New-Object Text.UTF8Encoding($false,$true)))
$receipt=[ordered]@{schemaVersion=1;receiptKind='gate12r-block-regression-memory-aggregation-route-wrapper-v6';createdAtUtc=[DateTime]::UtcNow.ToString('o');sourceSha256=$actualSourceSha256;derivedSha256=(Get-FileHash $derivedPath -Algorithm SHA256).Hash.ToLowerInvariant();routes=$evidence.ToArray();thresholdsChanged=$true;sampleThresholdChanged=$false;blockAggregationRuleChanged=$true;memoryGatePolicyId='gate12r-sample-128mib-block-128mib-per-sample-v1';williamsOrderChanged=$false;algorithmSemanticsChanged=$false};$json=($receipt|ConvertTo-Json -Depth 12).Replace("`r`n","`n").Replace("`r","`n");[IO.File]::WriteAllText((Join-Path $derivedRoot 'wrapper-receipt.json'),$json+"`n",(New-Object Text.UTF8Encoding($false,$true)))
$windowsPowerShell='C:\WINDOWS\System32\WindowsPowerShell\v1.0\powershell.exe';$nativeModulePath=@('C:\Users\bdscy\Documents\WindowsPowerShell\Modules','C:\Program Files\WindowsPowerShell\Modules','C:\WINDOWS\System32\WindowsPowerShell\v1.0\Modules')-join';';$stdout=Join-Path $derivedRoot 'child.stdout.log';$stderr=Join-Path $derivedRoot 'child.stderr.log';$oldModulePath=$env:PSModulePath
try{$env:PSModulePath=$nativeModulePath;&$windowsPowerShell -NoProfile -ExecutionPolicy Bypass -File $derivedPath -ProjectPath $ProjectPath -VerificationRoot $VerificationRoot -ProvenancePath $ProvenancePath -TelemetryResultPath $TelemetryResultPath -UnityPath $UnityPath 1>$stdout 2>$stderr;$exit=[int]$LASTEXITCODE}finally{$env:PSModulePath=$oldModulePath}
if($exit-ne0){Write-Error "Gate12R block/regression v6 child failed: exit=$exit stderr=$stderr";exit $exit};Write-Host 'Gate12R block/regression v6 memory-aggregation child passed.' -ForegroundColor Green;exit 0
