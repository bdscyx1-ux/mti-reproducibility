[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$ProjectPath,
    [switch]$BindingSmokeOnly
)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($ProjectPath) -or -not [IO.Path]::IsPathRooted($ProjectPath)) { throw 'Attempt 4 requires an explicit absolute ProjectPath.' }
$ProjectPath = [IO.Path]::GetFullPath($ProjectPath)
if ($BindingSmokeOnly) { Write-Output ('BINDING-SMOKE-PASSED|Run-Gate10RAttempt4OfficialPreflightV4|' + $ProjectPath); exit 0 }

$researchPath=Join-Path $ProjectPath 'Research';$verificationPath=Join-Path $researchPath 'Verification'
$root=Join-Path $verificationPath 'Gate10R_ProcessReuse_5pct\v4'
$outsideSummaryPath=Join-Path $verificationPath 'Gate10R_Attempt4_Preflight\v1\Gate10R_Attempt4_OutsideRoot_Preflight.summary.v4.json'
$configPath=Join-Path $researchPath 'Gate10R_ProcessReuse_5pct_Attempt4_Config.v4.json'
$provenancePath=Join-Path $researchPath 'Gate10R_ProcessReuse_5pct_Attempt4_Provenance.v4.json'
$authorizationPath=Join-Path $researchPath 'Gate10R_Attempt4_Execution_Authorization.v1.json'
$frozenSourcePath=Join-Path $verificationPath 'Run-Gate12AnalysisUnitTests.ps1'
$originalSummaryPath=Join-Path $verificationPath 'Gate12_AnalysisUnitTests.summary.json'
$summaryPath=Join-Path $root 'Gate10R_Attempt4_Preflight.summary.v4.json'
$checkpointPath=Join-Path $root 'gate10r-preflight-checkpoint.v4.json'
$receiptPath=Join-Path $root 'Gate10R_Attempt4_Execution_Receipt.v4.json'

function Get-LowerSha([string]$Path){(Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToLowerInvariant()}
function Get-StringSha([string]$Value){$sha=[Security.Cryptography.SHA256]::Create();try{$bytes=[Text.Encoding]::UTF8.GetBytes($Value);-join($sha.ComputeHash($bytes)|ForEach-Object{$_.ToString('x2')})}finally{$sha.Dispose()}}
function Get-Tree([string]$Path){$treeRoot=[IO.Path]::GetFullPath($Path).TrimEnd('\');$files=@(Get-ChildItem -LiteralPath $treeRoot -Recurse -File -Force|Sort-Object FullName);$rows=@($files|ForEach-Object{$relative=$_.FullName.Substring($treeRoot.Length).TrimStart('\').Replace('\','/');"$relative`t$($_.Length)`t$(Get-LowerSha $_.FullName)"});[pscustomobject][ordered]@{fileCount=$files.Count;rawBytes=[long](($files|Measure-Object Length -Sum).Sum);treeSha256=Get-StringSha($rows-join"`n")}}
function Write-AtomicJson([string]$Path,$Value,[int]$Depth=60){$json=($Value|ConvertTo-Json -Depth $Depth).Replace("`r`n","`n").Replace("`r","`n");if(-not$json.EndsWith("`n",[StringComparison]::Ordinal)){$json+="`n"};$temporary=$Path+'.tmp-'+[guid]::NewGuid().ToString('N');$encoding=New-Object Text.UTF8Encoding($false,$true);[IO.File]::WriteAllText($temporary,$json,$encoding);[IO.File]::Move($temporary,$Path)}

if(Test-Path -LiteralPath $root){throw 'Attempt-4 official root already exists; refusing retry/overwrite.'}
foreach($path in @($outsideSummaryPath,$configPath,$provenancePath,$authorizationPath,$frozenSourcePath,$originalSummaryPath)){if(-not(Test-Path -LiteralPath $path -PathType Leaf)){throw "Required attempt-4 preflight input is missing: $path"}}
$checks=New-Object Collections.Generic.List[object]
function Add-Check([string]$Name,[bool]$Passed,[string]$Detail){$script:checks.Add([pscustomobject][ordered]@{name=$Name;passed=$Passed;detail=$Detail})}
$outside=Get-Content -LiteralPath $outsideSummaryPath -Raw -Encoding UTF8|ConvertFrom-Json
$config=Get-Content -LiteralPath $configPath -Raw -Encoding UTF8|ConvertFrom-Json
$provenance=Get-Content -LiteralPath $provenancePath -Raw -Encoding UTF8|ConvertFrom-Json
$authorization=Get-Content -LiteralPath $authorizationPath -Raw -Encoding UTF8|ConvertFrom-Json
Add-Check 'outside-root-preflight-passed' ($outside.passed -eq $true -and [int]$outside.retainedSmoke.assertionCount -eq 63 -and $outside.unityStarted -eq $false -and $outside.officialRootCreated -eq $false) ([string]$outside.summaryKind)
Add-Check 'config-identity' ([int]$config.attempt -eq 4 -and [string]$config.verificationRoot -eq 'Research/Verification/Gate10R_ProcessReuse_5pct/v4' -and [string]$config.changeClass -eq 'ORCHESTRATION-RETAINED-REGRESSION-FILE-SCOPE-ONLY') ([string]$config.configId)
Add-Check 'authorization-identity' ([int]$authorization.attempt -eq 4 -and [string]$authorization.status -eq 'AUTHORIZED-GATE10R-ATTEMPT4-SERIES-ONLY' -and $authorization.automaticRetryAuthorized -eq $true -and $authorization.gate11RConditionalContinuationAuthorized -eq $false -and $authorization.gate12RConditionalContinuationAuthorized -eq $false -and $authorization.gate13RFormalCampaignAuthorized -eq $false) ([string]$authorization.authorizationId)
Add-Check 'provenance-identity' ([int]$provenance.attempt -eq 4 -and [string]$provenance.designId -eq [string]$config.designId -and $provenance.formalCampaign -eq $false) ([string]$provenance.provenanceId)
Add-Check 'frozen-source-byte-identical' ((Get-LowerSha $frozenSourcePath) -eq 'e56a3881c0fc9fc3ecceb760d1c51129e80ec2b306acdcfefed0a3814a6885b1') (Get-LowerSha $frozenSourcePath)
Add-Check 'frozen-summary-byte-identical' ((Get-LowerSha $originalSummaryPath) -eq '1536ae459c3d8cbb90b8a9dad1f74e7937d5ceb205e6cc088745c798d136e54d') (Get-LowerSha $originalSummaryPath)
$a1=Get-Tree (Join-Path $verificationPath 'Gate10R_ProcessReuse_5pct\v1');$a2=Get-Tree (Join-Path $verificationPath 'Gate10R_ProcessReuse_5pct\v2');$a3=Get-Tree (Join-Path $verificationPath 'Gate10R_ProcessReuse_5pct\v3')
Add-Check 'attempt1-tree-byte-identical' ($a1.fileCount -eq 4 -and $a1.rawBytes -eq 9577 -and $a1.treeSha256 -eq '2baa66eb6ee95ecf0f68667b2790fba2a30ce8a24f54e8f9fe477cdc716b9e3d') ($a1|ConvertTo-Json -Compress)
Add-Check 'attempt2-tree-byte-identical' ($a2.fileCount -eq 101 -and $a2.rawBytes -eq 9375526 -and $a2.treeSha256 -eq 'da9e6312e74db1bc1207660cf90eef28321ecda0abf1297be6c9298e6270dbce') ($a2|ConvertTo-Json -Compress)
Add-Check 'attempt3-tree-byte-identical' ($a3.fileCount -eq 165 -and $a3.rawBytes -eq 14661809 -and $a3.treeSha256 -eq '29f5aa8f0461abb120792dea0f2806e46e4dc9836aa843ce747f2436c1645a23') ($a3|ConvertTo-Json -Compress)
Add-Check 'unity-zero' (@(Get-Process -Name Unity -ErrorAction SilentlyContinue).Count -eq 0) ([string]@(Get-Process -Name Unity -ErrorAction SilentlyContinue).Count)
Add-Check 'project-lock-absent' (-not(Test-Path -LiteralPath (Join-Path $ProjectPath 'Temp\UnityLockfile'))) 'absent'
Add-Check 'gate11r-root-absent' (-not(Test-Path -LiteralPath (Join-Path $researchPath 'FormalScenarios\Gate11R_5pct\v1'))) 'absent'
Add-Check 'gate12r-root-absent' (-not(Test-Path -LiteralPath (Join-Path $researchPath 'PilotRuns\Gate12R_ProcessReuse_5pct\v1'))) 'absent'
Add-Check 'gate13r-root-absent' (-not(Test-Path -LiteralPath (Join-Path $researchPath 'FormalRuns\Gate13R_ProcessReuse_5pct\v1'))) 'absent'

$bindingErrors=New-Object Collections.Generic.List[string]
foreach($reference in @($provenance.boundFiles)){$path=Join-Path $ProjectPath ([string]$reference.relativePath).Replace('/','\');if(-not(Test-Path -LiteralPath $path -PathType Leaf)){$bindingErrors.Add('missing:'+$reference.relativePath)}elseif((Get-LowerSha $path) -ne [string]$reference.sha256){$bindingErrors.Add('hash:'+$reference.relativePath)}}
Add-Check 'provenance-file-bindings' ($bindingErrors.Count -eq 0) ($bindingErrors-join'; ')
$failed=@($checks|Where-Object{-not$_.passed})
if($failed.Count -ne 0){throw "Gate 10R attempt-4 official preflight failed before root creation: $($failed.name -join ', ')"}

[void](New-Item -ItemType Directory -Path $root)
$receipt=[ordered]@{schemaVersion=1;receiptId='gate10r-attempt4-v4-one-use-execution-receipt';createdAtUtc=[DateTime]::UtcNow.ToString('o');status='CONSUMED-FOR-ONE-OFFICIAL-GATE10R-EXECUTION';attempt=4;executionOrdinal=1;designId=[string]$config.designId;lineageId=[string]$config.lineageId;config=[ordered]@{relativePath='Research/Gate10R_ProcessReuse_5pct_Attempt4_Config.v4.json';sha256=Get-LowerSha $configPath};provenance=[ordered]@{relativePath='Research/Gate10R_ProcessReuse_5pct_Attempt4_Provenance.v4.json';sha256=Get-LowerSha $provenancePath};authorization=[ordered]@{relativePath='Research/Gate10R_Attempt4_Execution_Authorization.v1.json';sha256=Get-LowerSha $authorizationPath};outsidePreflight=[ordered]@{relativePath='Research/Verification/Gate10R_Attempt4_Preflight/v1/Gate10R_Attempt4_OutsideRoot_Preflight.summary.v4.json';sha256=Get-LowerSha $outsideSummaryPath};verificationRoot='Research/Verification/Gate10R_ProcessReuse_5pct/v4';maximumExecutionsForThisReceipt=1;automaticRetryUsesThisReceipt=$false;formalCampaign=$false;gate11RAuthorized=$false;gate12RAuthorized=$false;gate13RAuthorized=$false}
Write-AtomicJson $receiptPath $receipt 20
$summary=[ordered]@{schemaVersion=1;summaryKind='gate10r-attempt4-official-preflight-v4';savedAtUtc=[DateTime]::UtcNow.ToString('o');attempt=4;assertionCount=$checks.Count;passedCount=$checks.Count;failedCount=0;checks=$checks.ToArray();unityStarted=$false;officialRootCreated=$true;executionReceiptRelativePath='Gate10R_Attempt4_Execution_Receipt.v4.json';executionReceiptSha256=Get-LowerSha $receiptPath;passed=$true}
Write-AtomicJson $summaryPath $summary 60
$checkpoint=[ordered]@{schemaVersion=1;checkpointKind='gate10r-attempt4-official-preflight-checkpoint-v4';savedAtUtc=[DateTime]::UtcNow.ToString('o');status='GATE10R-ATTEMPT4-OFFICIAL-PREFLIGHT-PASSED-RECEIPT-CONSUMED';attempt=4;officialExecutionCount=1;summarySha256=Get-LowerSha $summaryPath;receiptSha256=Get-LowerSha $receiptPath;unityStarted=$false;gate11RAuthorized=$false;gate12RAuthorized=$false;gate13RAuthorized=$false}
Write-AtomicJson $checkpointPath $checkpoint 20
Write-Host "Gate 10R attempt-4 official preflight passed: $($checks.Count)/$($checks.Count); one-use receipt consumed; Unity not started." -ForegroundColor Green
exit 0
