[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$ProjectPath,
    [Parameter(Mandatory=$true)][string]$VerificationRoot,
    [Parameter(Mandatory=$true)][string]$ProvenancePath,
    [switch]$BindingSmokeOnly
)

$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
if([string]::IsNullOrWhiteSpace($ProjectPath)-or-not[IO.Path]::IsPathRooted($ProjectPath)){throw 'Gate12R v5 memory-amended static wrapper requires an explicit absolute ProjectPath.'};$ProjectPath=[IO.Path]::GetFullPath($ProjectPath)
if($BindingSmokeOnly){Write-Output("BINDING-SMOKE-PASSED|Run-Gate12RStaticUnitAuditV5|$ProjectPath");exit 0}
$VerificationRoot=[IO.Path]::GetFullPath($VerificationRoot);$ProvenancePath=[IO.Path]::GetFullPath($ProvenancePath)
$source=Join-Path $ProjectPath 'Research\Verification\Run-Gate12RStaticUnitAudit.ps1';$expectedSourceSha256='dfc8c94e3e2103946aa165c65beb58aa5b0aa744ba948984ac66766de9e8e049';$actualSourceSha256=(Get-FileHash $source -Algorithm SHA256).Hash.ToLowerInvariant();if($actualSourceSha256-ne$expectedSourceSha256){throw "Frozen static v1 source changed: $actualSourceSha256"}
$text=[IO.File]::ReadAllText($source,[Text.Encoding]::UTF8)
$routes=@(
 [pscustomobject]@{old='Gate12R_PreWrite_Preservation_Baseline.v1.json';new='Gate12R_PreWrite_Preservation_Baseline.v2.json';count=1},
 [pscustomobject]@{old='Gate12R_5pct_ProcessReuse_Pilot_Plan.v1.json';new='Gate12R_5pct_ProcessReuse_Pilot_Plan.v5.json';count=1},
 [pscustomobject]@{old='68f32ee7acdeaa4c43a4f4932825e40e552bb5df473a96c66a9dcffef45d8ff3';new='944b628d7b7728cae6013460e719000f046eec3d7f1a331ae5f97217e40c8d97';count=1},
 [pscustomobject]@{old="summaryKind='gate12r-static-unit-audit-v1'";new="summaryKind='gate12r-static-unit-audit-v4-plan-v5-memory-aggregation'";count=1}
)
$evidence=New-Object Collections.Generic.List[object];foreach($route in $routes){$actual=$text.Split([string[]]@([string]$route.old),[StringSplitOptions]::None).Count-1;if($actual-ne[int]$route.count){throw "Static v3 replacement count for '$($route.old)' is $actual, expected $($route.count)."};$text=$text.Replace([string]$route.old,[string]$route.new);$evidence.Add([pscustomobject]@{from=$route.old;to=$route.new;replacementCount=$actual})}
$derivedRoot=Join-Path $VerificationRoot '_DerivedHarness\StaticV5';if(Test-Path $derivedRoot){throw "Create-new static v5 derived root exists: $derivedRoot"};New-Item -ItemType Directory -Path $derivedRoot -Force|Out-Null;$derivedPath=Join-Path $derivedRoot 'Run-Gate12RStaticUnitAuditV5.derived.ps1';[IO.File]::WriteAllText($derivedPath,$text,(New-Object Text.UTF8Encoding($false,$true)))
$memoryUnitScript=Join-Path $ProjectPath 'Research\Verification\Run-Gate12RMemoryGateUnitTestsV2.ps1'
$receipt=[ordered]@{schemaVersion=1;receiptKind='gate12r-static-unit-plan-v5-memory-aggregation-wrapper-v5';createdAtUtc=[DateTime]::UtcNow.ToString('o');sourceSha256=$actualSourceSha256;derivedSha256=(Get-FileHash $derivedPath -Algorithm SHA256).Hash.ToLowerInvariant();memoryUnitScriptSha256=(Get-FileHash $memoryUnitScript -Algorithm SHA256).Hash.ToLowerInvariant();routes=$evidence.ToArray();frozenDesignSemanticsChanged=$false;sampleThresholdChanged=$false;blockAggregationRuleChanged=$true};$json=($receipt|ConvertTo-Json -Depth 12).Replace("`r`n","`n").Replace("`r","`n");[IO.File]::WriteAllText((Join-Path $derivedRoot 'wrapper-receipt.json'),$json+"`n",(New-Object Text.UTF8Encoding($false,$true)))
$windowsPowerShell='C:\WINDOWS\System32\WindowsPowerShell\v1.0\powershell.exe';$nativeModulePath=@('C:\Users\bdscy\Documents\WindowsPowerShell\Modules','C:\Program Files\WindowsPowerShell\Modules','C:\WINDOWS\System32\WindowsPowerShell\v1.0\Modules')-join';';$stdout=Join-Path $derivedRoot 'child.stdout.log';$stderr=Join-Path $derivedRoot 'child.stderr.log';$oldModulePath=$env:PSModulePath
try{$env:PSModulePath=$nativeModulePath;&$windowsPowerShell -NoProfile -ExecutionPolicy Bypass -File $derivedPath -ProjectPath $ProjectPath -VerificationRoot $VerificationRoot -ProvenancePath $ProvenancePath 1>$stdout 2>$stderr;$exit=[int]$LASTEXITCODE}finally{$env:PSModulePath=$oldModulePath}
if($exit-ne0){Write-Error "Gate12R static v5 child failed: exit=$exit stderr=$stderr";exit $exit}
$memoryOutput=Join-Path $VerificationRoot 'StaticUnit\memory-gate-unit-tests.json';$memoryStdout=Join-Path $derivedRoot 'memory-unit.stdout.log';$memoryStderr=Join-Path $derivedRoot 'memory-unit.stderr.log'
try{$env:PSModulePath=$nativeModulePath;&$windowsPowerShell -NoProfile -ExecutionPolicy Bypass -File $memoryUnitScript -ProjectPath $ProjectPath -OutputPath $memoryOutput 1>$memoryStdout 2>$memoryStderr;$memoryExit=[int]$LASTEXITCODE}finally{$env:PSModulePath=$oldModulePath}
if($memoryExit-ne0){Write-Error "Gate12R memory-gate unit tests failed: exit=$memoryExit stderr=$memoryStderr";exit $memoryExit};Write-Host 'Gate12R static/unit v5 and memory-aggregation unit tests passed.' -ForegroundColor Green;exit 0
