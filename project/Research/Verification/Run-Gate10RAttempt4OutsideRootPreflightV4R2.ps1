[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$ProjectPath,
    [switch]$BindingSmokeOnly
)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($ProjectPath) -or -not [System.IO.Path]::IsPathRooted($ProjectPath)) { throw 'Attempt 4 requires an explicit absolute ProjectPath.' }
$ProjectPath = [System.IO.Path]::GetFullPath($ProjectPath)
if ($BindingSmokeOnly) { Write-Output ('BINDING-SMOKE-PASSED|Run-Gate10RAttempt4OutsideRootPreflightV4R2|' + $ProjectPath); exit 0 }

$researchPath = Join-Path $ProjectPath 'Research'
$verificationPath = Join-Path $researchPath 'Verification'
$officialRoot = Join-Path $verificationPath 'Gate10R_ProcessReuse_5pct\v4'
$preflightRoot = Join-Path $verificationPath 'Gate10R_Attempt4_Preflight\v3'
$summaryPath = Join-Path $preflightRoot 'Gate10R_Attempt4_OutsideRoot_Preflight.summary.v4.json'
$smokeSummaryPath = Join-Path $preflightRoot 'RetainedRegression63.validation-only.summary.json'
$smokeStdoutPath = Join-Path $preflightRoot 'RetainedRegression63.validation-only.stdout.log'
$smokeStderrPath = Join-Path $preflightRoot 'RetainedRegression63.validation-only.stderr.log'
$generatorStdoutPath = Join-Path $preflightRoot 'MechanicalTransform.validation-only.stdout.log'
$generatorStderrPath = Join-Path $preflightRoot 'MechanicalTransform.validation-only.stderr.log'
$frozenSourcePath = Join-Path $verificationPath 'Run-Gate12AnalysisUnitTests.ps1'
$originalSummaryPath = Join-Path $verificationPath 'Gate12_AnalysisUnitTests.summary.json'
$harnessPath = Join-Path $verificationPath 'Gate10RAttempt4RetainedHarnessV4.ps1'
$generatorPath = Join-Path $verificationPath 'New-Gate10RAttempt4SourcesV4.ps1'
$retainedRunnerPath = Join-Path $verificationPath 'Run-Gate10RRetainedRegressionV4.ps1'
$windowsPowerShell = 'C:\WINDOWS\System32\WindowsPowerShell\v1.0\powershell.exe'
$nativePowerShellModulePath = @('C:\Users\bdscy\Documents\WindowsPowerShell\Modules', 'C:\Program Files\WindowsPowerShell\Modules', 'C:\WINDOWS\System32\WindowsPowerShell\v1.0\Modules') -join ';'

if (Test-Path -LiteralPath $officialRoot) { throw 'Official v4 root exists before outside-root preflight.' }
if (Test-Path -LiteralPath $preflightRoot) { throw 'Attempt-4 outside-root preflight evidence already exists; refusing retry/overwrite.' }
[void](New-Item -ItemType Directory -Path $preflightRoot)

$checks = New-Object System.Collections.Generic.List[object]
function Add-Check([string]$Name, [bool]$Passed, [string]$Detail) { $script:checks.Add([pscustomobject][ordered]@{name=$Name;passed=$Passed;detail=$Detail}) }
function Get-LowerSha([string]$Path) { (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToLowerInvariant() }
function Get-StringSha([string]$Value) { $sha=[Security.Cryptography.SHA256]::Create();try{$bytes=[Text.Encoding]::UTF8.GetBytes($Value);-join ($sha.ComputeHash($bytes)|ForEach-Object{$_.ToString('x2')})}finally{$sha.Dispose()} }
function Get-TreeIdentity([string]$Path) {
    $treeRoot = [IO.Path]::GetFullPath($Path).TrimEnd('\')
    $files = @(Get-ChildItem -LiteralPath $treeRoot -Recurse -File -Force | Sort-Object FullName)
    $rows = @($files | ForEach-Object { $relative=$_.FullName.Substring($treeRoot.Length).TrimStart('\').Replace('\','/'); "$relative`t$($_.Length)`t$(Get-LowerSha $_.FullName)" })
    [pscustomobject][ordered]@{fileCount=$files.Count;rawBytes=[long](($files|Measure-Object Length -Sum).Sum);treeSha256=Get-StringSha ($rows -join "`n")}
}
function Write-AtomicJson([string]$Path, $Value, [int]$Depth=50) {
    $json=($Value|ConvertTo-Json -Depth $Depth).Replace("`r`n","`n").Replace("`r","`n");if(-not $json.EndsWith("`n",[StringComparison]::Ordinal)){$json+="`n"}
    $temporary=$Path+'.tmp-'+[guid]::NewGuid().ToString('N');$encoding=New-Object Text.UTF8Encoding($false,$true)
    [IO.File]::WriteAllText($temporary,$json,$encoding);[IO.File]::Move($temporary,$Path)
}
function Invoke-ChildProcess([string[]]$Arguments, [string]$StdoutPath, [string]$StderrPath) {
    $startInfo = New-Object Diagnostics.ProcessStartInfo
    $startInfo.FileName = $windowsPowerShell
    $startInfo.Arguments = ($Arguments -join ' ')
    $startInfo.WorkingDirectory = $ProjectPath
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $startInfo.EnvironmentVariables['PSModulePath'] = $nativePowerShellModulePath
    $process = New-Object Diagnostics.Process
    $process.StartInfo = $startInfo
    if (-not $process.Start()) { throw 'Child process failed to start.' }
    $stdout = $process.StandardOutput.ReadToEnd()
    $stderr = $process.StandardError.ReadToEnd()
    $process.WaitForExit()
    $exitCode = [int]$process.ExitCode
    $process.Dispose()
    $encoding = New-Object Text.UTF8Encoding($false, $true)
    if (-not [string]::IsNullOrWhiteSpace($StdoutPath)) { [IO.File]::WriteAllText($StdoutPath, $stdout, $encoding) }
    if (-not [string]::IsNullOrWhiteSpace($StderrPath)) { [IO.File]::WriteAllText($StderrPath, $stderr, $encoding) }
    [pscustomobject][ordered]@{exitCode=$exitCode;stdout=$stdout;stderr=$stderr}
}

$attempt1Before = Get-TreeIdentity (Join-Path $verificationPath 'Gate10R_ProcessReuse_5pct\v1')
$attempt2Before = Get-TreeIdentity (Join-Path $verificationPath 'Gate10R_ProcessReuse_5pct\v2')
$attempt3Before = Get-TreeIdentity (Join-Path $verificationPath 'Gate10R_ProcessReuse_5pct\v3')
$sourceHashBefore = Get-LowerSha $frozenSourcePath
$originalHashBefore = Get-LowerSha $originalSummaryPath
Add-Check 'attempt1-tree-baseline' ($attempt1Before.fileCount -eq 4 -and $attempt1Before.rawBytes -eq 9577 -and $attempt1Before.treeSha256 -eq '2baa66eb6ee95ecf0f68667b2790fba2a30ce8a24f54e8f9fe477cdc716b9e3d') ($attempt1Before|ConvertTo-Json -Compress)
Add-Check 'attempt2-tree-baseline' ($attempt2Before.fileCount -eq 101 -and $attempt2Before.rawBytes -eq 9375526 -and $attempt2Before.treeSha256 -eq 'da9e6312e74db1bc1207660cf90eef28321ecda0abf1297be6c9298e6270dbce') ($attempt2Before|ConvertTo-Json -Compress)
Add-Check 'attempt3-tree-baseline' ($attempt3Before.fileCount -eq 165 -and $attempt3Before.rawBytes -eq 14661809 -and $attempt3Before.treeSha256 -eq '29f5aa8f0461abb120792dea0f2806e46e4dc9836aa843ce747f2436c1645a23') ($attempt3Before|ConvertTo-Json -Compress)
Add-Check 'frozen-source-hash' ($sourceHashBefore -eq 'e56a3881c0fc9fc3ecceb760d1c51129e80ec2b306acdcfefed0a3814a6885b1') $sourceHashBefore
Add-Check 'frozen-summary-hash' ($originalHashBefore -eq '1536ae459c3d8cbb90b8a9dad1f74e7937d5ceb205e6cc088745c798d136e54d') $originalHashBefore
Add-Check 'official-v4-root-absent-before' (-not (Test-Path -LiteralPath $officialRoot)) $officialRoot
Add-Check 'unity-zero-before' (@(Get-Process -Name Unity -ErrorAction SilentlyContinue).Count -eq 0) ([string]@(Get-Process -Name Unity -ErrorAction SilentlyContinue).Count)
Add-Check 'project-lock-absent-before' (-not (Test-Path -LiteralPath (Join-Path $ProjectPath 'Temp\UnityLockfile'))) 'absent'
$v1FailureReceipt = Join-Path $verificationPath 'Gate10R_Attempt4_Preflight\v1\Gate10R_Attempt4_OutsideRoot_Preflight_Failure_Receipt.v1.json'
$v1Checkpoint = Join-Path $verificationPath 'Gate10R_Attempt4_Preflight\v1\gate10r-attempt4-outside-root-preflight-checkpoint.v1.json'
Add-Check 'v1-failure-receipt-frozen' ((Get-LowerSha $v1FailureReceipt) -eq '126619727e9603fb14036bcd9c5c07a817f738a3fe8bdcaa2dd3db8bdd6a84ac') (Get-LowerSha $v1FailureReceipt)
Add-Check 'v1-failure-checkpoint-frozen' ((Get-Content -LiteralPath $v1Checkpoint -Raw -Encoding UTF8 | ConvertFrom-Json).status -eq 'GATE10R-ATTEMPT4-OUTSIDE-PREFLIGHT-V1-FAILED-CLOSED-RETRY-V2-AUTHORIZED') (Get-LowerSha $v1Checkpoint)
$v2FailureReceipt = Join-Path $verificationPath 'Gate10R_Attempt4_Preflight\v2\Gate10R_Attempt4_OutsideRoot_Preflight_Failure_Receipt.v2.json'
$v2Checkpoint = Join-Path $verificationPath 'Gate10R_Attempt4_Preflight\v2\gate10r-attempt4-outside-root-preflight-checkpoint.v2.json'
Add-Check 'v2-failure-receipt-frozen' ((Get-LowerSha $v2FailureReceipt) -eq '020a7beef7dfd60102b0a9780aed9fd40c1cd892d5c998013e903e637536872a') (Get-LowerSha $v2FailureReceipt)
Add-Check 'v2-failure-checkpoint-frozen' ((Get-Content -LiteralPath $v2Checkpoint -Raw -Encoding UTF8 | ConvertFrom-Json).status -eq 'GATE10R-ATTEMPT4-OUTSIDE-PREFLIGHT-V2-FAILED-CLOSED-RETRY-V3-AUTHORIZED') (Get-LowerSha $v2Checkpoint)

$entryPoints = @(
    [pscustomobject]@{path=Join-Path $verificationPath 'Run-Gate10RAttempt4OutsideRootPreflightV4R2.ps1';args=@('-ProjectPath',$ProjectPath,'-BindingSmokeOnly');marker='Run-Gate10RAttempt4OutsideRootPreflightV4R2'},
    [pscustomobject]@{path=Join-Path $verificationPath 'Run-Gate10RAttempt4OfficialPreflightV4R2.ps1';args=@('-ProjectPath',$ProjectPath,'-BindingSmokeOnly');marker='Run-Gate10RAttempt4OfficialPreflightV4R2'},
    [pscustomobject]@{path=Join-Path $verificationPath 'Run-Gate10RUnitTestsV4.ps1';args=@('-ProjectPath',$ProjectPath,'-BindingSmokeOnly');marker='Run-Gate10RUnitTestsV4'},
    [pscustomobject]@{path=Join-Path $verificationPath 'Run-Gate10RCompileV4.ps1';args=@('-ProjectPath',$ProjectPath,'-BindingSmokeOnly');marker='Run-Gate10RCompileV4'},
    [pscustomobject]@{path=Join-Path $verificationPath 'Run-Gate10RBlockVerificationV4.ps1';args=@('-ProjectPath',$ProjectPath,'-BindingSmokeOnly');marker='Run-Gate10RBlockVerificationV4'},
    [pscustomobject]@{path=$retainedRunnerPath;args=@('-ProjectPath',$ProjectPath,'-BindingSmokeOnly');marker='Run-Gate10RRetainedRegressionV4'},
    [pscustomobject]@{path=Join-Path $verificationPath 'Run-Gate10RFinalAuditV4R2.ps1';args=@('-ProjectPath',$ProjectPath,'-BindingSmokeOnly');marker='Run-Gate10RFinalAuditV4R2'},
    [pscustomobject]@{path=Join-Path $researchPath 'Run-Gate10RTelemetryProbeV4.ps1';args=@('-ProjectPath',$ProjectPath,'-BindingSmokeOnly');marker='Run-Gate10RTelemetryProbeV4'},
    [pscustomobject]@{path=Join-Path $researchPath 'Run-Gate10RProcessReuseBlockV4.ps1';args=@('-ProjectPath',$ProjectPath,'-BlockPlanPath','binding-smoke.json','-OutputDirectory',(Join-Path $officialRoot 'Fixtures\binding-block'),'-BindingSmokeOnly');marker='Run-Gate10RProcessReuseBlockV4'},
    [pscustomobject]@{path=Join-Path $researchPath 'Run-Gate10RColdReferenceV4.ps1';args=@('-ProjectPath',$ProjectPath,'-ScenarioPath',(Join-Path $ProjectPath 'binding-smoke.json'),'-OutputDirectory',(Join-Path $officialRoot 'Fixtures\binding-cold'),'-RunId','binding-smoke','-Algorithm','A*-R','-BindingSmokeOnly');marker='Run-Gate10RColdReferenceV4'},
    [pscustomobject]@{path=$harnessPath;args=@('-ProjectPath',$ProjectPath,'-SummaryPath',(Join-Path $preflightRoot 'binding-smoke.summary.json'),'-BindingSmokeOnly');marker='Gate10RAttempt4RetainedHarnessV4'}
)
$parseTargets = @($generatorPath, $retainedRunnerPath, $harnessPath) + @($entryPoints.path) | Select-Object -Unique
foreach ($path in $parseTargets) {
    $tokens=$null;$errors=$null;[void][Management.Automation.Language.Parser]::ParseFile($path,[ref]$tokens,[ref]$errors)
    Add-Check ('parser-'+[IO.Path]::GetFileName($path)) ($errors.Count -eq 0) ($errors -join '; ')
}

$previousModulePath=$env:PSModulePath
try {
    $env:PSModulePath=$nativePowerShellModulePath
    foreach($entry in $entryPoints){
        $output=@(& $windowsPowerShell -NoProfile -ExecutionPolicy Bypass -File $entry.path @($entry.args) 2>&1|ForEach-Object{[string]$_});$exit=[int]$LASTEXITCODE;$joined=$output -join "`n"
        Add-Check ('binding-'+[IO.Path]::GetFileName($entry.path)) ($exit -eq 0 -and $joined.Contains('BINDING-SMOKE-PASSED|'+$entry.marker+'|')) ("exit=$exit;marker="+$joined.Contains('BINDING-SMOKE-PASSED|'+$entry.marker+'|'))
        Add-Check ('official-root-still-absent-'+[IO.Path]::GetFileName($entry.path)) (-not(Test-Path -LiteralPath $officialRoot)) $officialRoot
    }
    & $windowsPowerShell -NoProfile -ExecutionPolicy Bypass -File $generatorPath -ProjectPath $ProjectPath -ValidationOnly 1>$generatorStdoutPath 2>$generatorStderrPath
    $generatorExit=[int]$LASTEXITCODE
    Add-Check 'mechanical-transform-exact' ($generatorExit -eq 0) ("exit=$generatorExit")
} finally { $env:PSModulePath=$previousModulePath }

$frozenText=[IO.File]::ReadAllText($frozenSourcePath);$harnessText=[IO.File]::ReadAllText($harnessPath)
$bodyAnchor='$modulePath = Join-Path $ProjectPath ''Research\Gate12PilotAnalysis.psm1'''
$sourceBody=$frozenText.Substring($frozenText.IndexOf($bodyAnchor,[StringComparison]::Ordinal))
$harnessBody=$harnessText.Substring($harnessText.IndexOf($bodyAnchor,[StringComparison]::Ordinal))
$expectedBody=$sourceBody.Replace("`$summaryPath = Join-Path `$scriptDirectory 'Gate12_AnalysisUnitTests.summary.json'",'$summaryPath = $resolvedSummaryPath')
Add-Check 'mechanical-test-body-exact-except-summary-route' ([string]::Equals($harnessBody,$expectedBody,[StringComparison]::Ordinal)) ("sourceBodySha=$(Get-StringSha $sourceBody);harnessBodySha=$(Get-StringSha $harnessBody)")
$runnerText=[IO.File]::ReadAllText($retainedRunnerPath)
Add-Check 'wrapper-uses-file-scope' ($runnerText.Contains('-File $harnessPath') -and -not $runnerText.Contains('ScriptBlock]::Create') -and -not $runnerText.Contains('Invoke-Expression')) 'powershell.exe -File harness'

$negativeCases=@(
    [pscustomobject]@{name='reject-original-summary';path=$originalSummaryPath},
    [pscustomobject]@{name='reject-attempt1-root';path=(Join-Path $verificationPath 'Gate10R_ProcessReuse_5pct\v1\forbidden.summary.json')}
)
foreach($case in $negativeCases){
    $caseStdout=Join-Path $preflightRoot ($case.name+'.stdout.log');$caseStderr=Join-Path $preflightRoot ($case.name+'.stderr.log')
    $result=Invoke-ChildProcess -Arguments @('-NoProfile','-ExecutionPolicy','Bypass','-File',$harnessPath,'-ProjectPath',$ProjectPath,'-SummaryPath',$case.path,'-BindingSmokeOnly') -StdoutPath $caseStdout -StderrPath $caseStderr
    $targetInvariantPassed = if ($case.name -eq 'reject-original-summary') { (Get-LowerSha $case.path) -eq $originalHashBefore } else { -not (Test-Path -LiteralPath $case.path) }
    Add-Check ('output-isolation-'+$case.name) ($result.exitCode -ne 0 -and $targetInvariantPassed) ("exit=$($result.exitCode);targetInvariant=$targetInvariantPassed")
}
$relativeResult=Invoke-ChildProcess -Arguments @('-NoProfile','-ExecutionPolicy','Bypass','-File',$harnessPath,'-ProjectPath',$ProjectPath,'-SummaryPath','relative.summary.json','-BindingSmokeOnly') -StdoutPath (Join-Path $preflightRoot 'reject-relative.stdout.log') -StderrPath (Join-Path $preflightRoot 'reject-relative.stderr.log')
Add-Check 'output-isolation-reject-relative' ($relativeResult.exitCode -ne 0) ("exit=$($relativeResult.exitCode)")
$smokeResult=Invoke-ChildProcess -Arguments @('-NoProfile','-ExecutionPolicy','Bypass','-File',$harnessPath,'-ProjectPath',$ProjectPath,'-SummaryPath',$smokeSummaryPath) -StdoutPath $smokeStdoutPath -StderrPath $smokeStderrPath
$smokeExit=[int]$smokeResult.exitCode
$smoke=if(Test-Path -LiteralPath $smokeSummaryPath -PathType Leaf){Get-Content -LiteralPath $smokeSummaryPath -Raw -Encoding UTF8|ConvertFrom-Json}else{$null}
Add-Check 'validation-only-retained-63-of-63' ($smokeExit -eq 0 -and $null -ne $smoke -and $smoke.passed -eq $true -and [int]$smoke.assertionCount -eq 63 -and @($smoke.failures).Count -eq 0) ("exit=$smokeExit;assertions="+$(if($null -ne $smoke){[int]$smoke.assertionCount}else{0}))

$attempt1After=Get-TreeIdentity (Join-Path $verificationPath 'Gate10R_ProcessReuse_5pct\v1');$attempt2After=Get-TreeIdentity (Join-Path $verificationPath 'Gate10R_ProcessReuse_5pct\v2');$attempt3After=Get-TreeIdentity (Join-Path $verificationPath 'Gate10R_ProcessReuse_5pct\v3')
Add-Check 'attempt1-unchanged-after-smoke' ($attempt1After.treeSha256 -eq $attempt1Before.treeSha256 -and $attempt1After.fileCount -eq $attempt1Before.fileCount -and $attempt1After.rawBytes -eq $attempt1Before.rawBytes) ($attempt1After|ConvertTo-Json -Compress)
Add-Check 'attempt2-unchanged-after-smoke' ($attempt2After.treeSha256 -eq $attempt2Before.treeSha256 -and $attempt2After.fileCount -eq $attempt2Before.fileCount -and $attempt2After.rawBytes -eq $attempt2Before.rawBytes) ($attempt2After|ConvertTo-Json -Compress)
Add-Check 'attempt3-unchanged-after-smoke' ($attempt3After.treeSha256 -eq $attempt3Before.treeSha256 -and $attempt3After.fileCount -eq $attempt3Before.fileCount -and $attempt3After.rawBytes -eq $attempt3Before.rawBytes) ($attempt3After|ConvertTo-Json -Compress)
Add-Check 'frozen-source-unchanged-after-smoke' ((Get-LowerSha $frozenSourcePath) -eq $sourceHashBefore) (Get-LowerSha $frozenSourcePath)
Add-Check 'frozen-summary-unchanged-after-smoke' ((Get-LowerSha $originalSummaryPath) -eq $originalHashBefore) (Get-LowerSha $originalSummaryPath)
Add-Check 'official-v4-root-absent-after' (-not(Test-Path -LiteralPath $officialRoot)) $officialRoot
Add-Check 'unity-zero-after' (@(Get-Process -Name Unity -ErrorAction SilentlyContinue).Count -eq 0) ([string]@(Get-Process -Name Unity -ErrorAction SilentlyContinue).Count)
Add-Check 'project-lock-absent-after' (-not(Test-Path -LiteralPath (Join-Path $ProjectPath 'Temp\UnityLockfile'))) 'absent'
Add-Check 'gate11r-root-absent' (-not(Test-Path -LiteralPath (Join-Path $researchPath 'FormalScenarios\Gate11R_5pct\v1'))) 'absent'
Add-Check 'gate12r-root-absent' (-not(Test-Path -LiteralPath (Join-Path $researchPath 'PilotRuns\Gate12R_ProcessReuse_5pct\v1'))) 'absent'
Add-Check 'gate13r-root-absent' (-not(Test-Path -LiteralPath (Join-Path $researchPath 'FormalRuns\Gate13R_ProcessReuse_5pct\v1'))) 'absent'

$failed=@($checks|Where-Object{-not $_.passed})
$summary=[ordered]@{schemaVersion=1;summaryKind='gate10r-attempt4-outside-v4-root-preflight-v4-retry2';savedAtUtc=[DateTime]::UtcNow.ToString('o');attempt=4;preflightExecutionOrdinal=3;supersedesFailedPreflightRoots=@('Research/Verification/Gate10R_Attempt4_Preflight/v1','Research/Verification/Gate10R_Attempt4_Preflight/v2');unityStarted=$false;officialRootCreated=$false;assertionCount=$checks.Count;passedCount=$checks.Count-$failed.Count;failedCount=$failed.Count;checks=$checks.ToArray();retainedSmoke=[ordered]@{exitCode=$smokeExit;assertionCount=$(if($null -ne $smoke){[int]$smoke.assertionCount}else{0});summaryRelativePath='RetainedRegression63.validation-only.summary.json';summarySha256=$(if($null -ne $smoke){Get-LowerSha $smokeSummaryPath}else{$null})};gate11RAuthorized=$false;gate12RAuthorized=$false;gate13RAuthorized=$false;passed=$failed.Count -eq 0}
Write-AtomicJson $summaryPath $summary 60
if(-not $summary.passed){Write-Error "Gate 10R attempt-4 outside-root preflight failed: $($failed.name -join ', ')";exit 1}
Write-Host "Gate 10R attempt-4 outside-root preflight passed: $($checks.Count)/$($checks.Count), retained smoke 63/63, Unity not started, v4 root absent." -ForegroundColor Green
exit 0
