[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$ProjectPath,
    [Parameter(Mandatory=$true)][string]$VerificationRoot,
    [string]$UnityPath='H:\UnityEditor\2022.3.30f1c1\Editor\Unity.exe',
    [switch]$BindingSmokeOnly,
    [int]$TimeoutSeconds=600
)
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
if([string]::IsNullOrWhiteSpace($ProjectPath)-or-not[IO.Path]::IsPathRooted($ProjectPath)){throw 'PR1B v3 memory-policy self-test v4 requires an explicit absolute ProjectPath.'};$ProjectPath=[IO.Path]::GetFullPath($ProjectPath)
if($BindingSmokeOnly){Write-Output("BINDING-SMOKE-PASSED|Run-Gate13RPR1BMemoryPolicySelfTestV5|$ProjectPath");exit 0}
$VerificationRoot=[IO.Path]::GetFullPath($VerificationRoot);$UnityPath=[IO.Path]::GetFullPath($UnityPath)
Import-Module (Join-Path $ProjectPath 'Research\Gate10RProcessReusePreparation.psm1') -Force
Import-Module (Join-Path $ProjectPath 'Research\Gate10RLockHygieneV3.psm1') -Force
$root=Join-Path $VerificationRoot 'MemoryPolicySelfTest';if(Test-Path -LiteralPath $root){throw "Create-new memory-policy self-test root exists: $root"}
if(@(Get-Process -Name Unity -ErrorAction SilentlyContinue).Count-or(Test-Path (Join-Path $ProjectPath 'Temp\UnityLockfile'))){throw 'Unity must be closed and project lock absent before memory-policy self-test.'}
if(Test-Path (Join-Path $ProjectPath 'Research\FormalRuns\Gate13R_RQAligned\v1')){throw 'Reserved formal root must remain absent.'}
$unityLog=$root+'.Unity.log';$stdout=$root+'.stdout.log';$stderr=$root+'.stderr.log';$summaryPath=$root+'.summary.json'
$started=Get-Date;$args=@('-batchmode','-nographics','-quit','-projectPath',('"'+$ProjectPath+'"'),'-executeMethod','DDM.Research.Editor.Gate13RPR1BMemoryAwareProcessReuseBatchCommandV3.RunMemoryPolicySelfTest','-ddmGate13RPR1BMemoryPolicyTestDirectory',('"'+$root+'"'),'-logFile',('"'+$unityLog+'"'))
$process=Start-Process -FilePath $UnityPath -ArgumentList $args -WorkingDirectory (Split-Path -Parent $UnityPath) -WindowStyle Hidden -RedirectStandardOutput $stdout -RedirectStandardError $stderr -PassThru
$deadline=(Get-Date).AddSeconds($TimeoutSeconds);$timedOut=$false;while(-not$process.HasExited){if((Get-Date)-ge$deadline){$timedOut=$true;break};Start-Sleep -Milliseconds 250;$process.Refresh()}
if($timedOut){& taskkill.exe /PID $process.Id /T /F 2>&1|Out-Null;try{Wait-Process -Id $process.Id -Timeout 30 -ErrorAction SilentlyContinue}catch{}}
$process.Refresh();$processId=[int]$process.Id;$exit=if($timedOut){124}else{[int]$process.ExitCode};$completed=Get-Date;try{$process.Dispose()}catch{}
$lock=Invoke-Gate10RPostExitQuiescenceV3 -ProjectPath $ProjectPath -OwnedProcessId $processId -OwnedProcessStartedAt ([DateTimeOffset]$started) -OwnedProcessCompletedAt ([DateTimeOffset]$completed) -Role 'positive' -EvidenceDirectory ($root+'.lock-hygiene') -ContextId 'gate13r-pr1b-v3-memory-policy-self-test-v4' -QuiescenceSeconds 60 -PollMilliseconds 250 -TimestampToleranceSeconds 2
$resultPath=Join-Path $root 'memory-policy-self-test.json';$result=if(Test-Path $resultPath){Get-Content $resultPath -Raw -Encoding UTF8|ConvertFrom-Json}else{$null};$compiler=@();if(Test-Path $unityLog){$compiler=@(Select-String -LiteralPath $unityLog -Pattern 'error CS\d+|Compilation failed|Scripts have compiler errors|executeMethod.+could not be found' -CaseSensitive:$false)}
$errors=New-Object Collections.Generic.List[string];if($exit-ne0){$errors.Add("Unity exit code $exit")};if($timedOut){$errors.Add('timeout')};if($compiler.Count){$errors.Add("compiler/error matches=$($compiler.Count)")};if($null-eq$result-or$result.passed-ne$true-or[int]$result.testCount-ne12-or[int]$result.telemetryValidationTestCount-ne8){$errors.Add('memory-policy/telemetry fixture result missing or incomplete')};if($null-eq$lock-or$lock.passed-ne$true){$errors.Add('lock hygiene failed')}
$summary=[ordered]@{schemaVersion=2;summaryKind='gate13r-pr1b-v3-pathsafe-memory-policy-unity-self-test-wrapper-v1';savedAtUtc=[DateTime]::UtcNow.ToString('o');unityProcessId=$processId;exitCode=$exit;timedOut=$timedOut;wallSeconds=($completed-$started).TotalSeconds;fixtureCount=if($null-ne$result){[int]$result.testCount}else{0};fixturePassedCount=if($null-ne$result){[int]$result.passedTestCount}else{0};telemetryValidationFixtureCount=if($null-ne$result){[int]$result.telemetryValidationTestCount}else{0};telemetryValidationPassedFixtureCount=if($null-ne$result){[int]$result.telemetryValidationPassedTestCount}else{0};resultSha256=if(Test-Path $resultPath){Get-Gate10RLowerSha256 $resultPath}else{$null};lockHygieneRole='positive';lockHygieneMode=[string]$lock.mode;errors=$errors.ToArray();formalCampaign=$false;passed=$errors.Count-eq0}
Write-Gate10RAtomicUtf8NoBomJson -Path $summaryPath -Value $summary -Depth 20
if($errors.Count){Write-Error("PR1B v3 memory-policy self-test v4 failed: "+($errors-join'; '));exit 1};Write-Host 'PR1B v3 memory-policy Unity self-test v4 passed.' -ForegroundColor Green;exit 0


