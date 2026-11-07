[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$ProjectPath,
    [Parameter(Mandatory=$true)][string]$VerificationRoot,
    [string]$UnityPath='H:\UnityEditor\2022.3.30f1c1\Editor\Unity.exe',
    [switch]$BindingSmokeOnly,
    [int]$TimeoutSeconds=600
)
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
if([string]::IsNullOrWhiteSpace($ProjectPath)-or-not[IO.Path]::IsPathRooted($ProjectPath)){throw 'PR1B v3 path-safe atomic self-test requires an explicit absolute ProjectPath.'};$ProjectPath=[IO.Path]::GetFullPath($ProjectPath)
if($BindingSmokeOnly){Write-Output("BINDING-SMOKE-PASSED|Run-Gate13RPR1BPathSafeAtomicSelfTestV3|$ProjectPath");exit 0}
$VerificationRoot=[IO.Path]::GetFullPath($VerificationRoot);$UnityPath=[IO.Path]::GetFullPath($UnityPath)
Import-Module (Join-Path $ProjectPath 'Research\Gate10RProcessReusePreparation.psm1') -Force
Import-Module (Join-Path $ProjectPath 'Research\Gate10RLockHygieneV3.psm1') -Force
$root=Join-Path $VerificationRoot 'PathSafeAtomicSelfTest';if(Test-Path -LiteralPath $root){throw "Create-new path-safe atomic self-test root exists: $root"}
if(@(Get-Process -Name Unity -ErrorAction SilentlyContinue).Count-or(Test-Path (Join-Path $ProjectPath 'Temp\UnityLockfile'))){throw 'Unity must be closed and project lock absent before path-safe atomic self-test.'}
if(Test-Path (Join-Path $ProjectPath 'Research\FormalRuns\Gate13R_RQAligned\v1')){throw 'Reserved formal root must remain absent.'}
$unityLog=$root+'.Unity.log';$stdout=$root+'.stdout.log';$stderr=$root+'.stderr.log';$summaryPath=$root+'.summary.json'
$started=Get-Date;$args=@('-batchmode','-nographics','-quit','-projectPath',('"'+$ProjectPath+'"'),'-executeMethod','DDM.Research.Editor.Gate13RPR1BMemoryAwareProcessReuseBatchCommandV3.RunPathSafeAtomicSelfTest','-ddmGate13RPR1BPathSafeTestDirectory',('"'+$root+'"'),'-logFile',('"'+$unityLog+'"'))
$process=Start-Process -FilePath $UnityPath -ArgumentList $args -WorkingDirectory (Split-Path -Parent $UnityPath) -WindowStyle Hidden -RedirectStandardOutput $stdout -RedirectStandardError $stderr -PassThru
$deadline=(Get-Date).AddSeconds($TimeoutSeconds);$timedOut=$false;while(-not$process.HasExited){if((Get-Date)-ge$deadline){$timedOut=$true;break};Start-Sleep -Milliseconds 250;$process.Refresh()}
if($timedOut){& taskkill.exe /PID $process.Id /T /F 2>&1|Out-Null;try{Wait-Process -Id $process.Id -Timeout 30 -ErrorAction SilentlyContinue}catch{}}
$process.Refresh();$processId=[int]$process.Id;$exit=if($timedOut){124}else{[int]$process.ExitCode};$completed=Get-Date;try{$process.Dispose()}catch{}
$lock=Invoke-Gate10RPostExitQuiescenceV3 -ProjectPath $ProjectPath -OwnedProcessId $processId -OwnedProcessStartedAt ([DateTimeOffset]$started) -OwnedProcessCompletedAt ([DateTimeOffset]$completed) -Role 'positive' -EvidenceDirectory ($root+'.lock-hygiene') -ContextId 'gate13r-pr1b-v3-path-safe-atomic-self-test' -QuiescenceSeconds 60 -PollMilliseconds 250 -TimestampToleranceSeconds 2
$resultPath=Join-Path $root 'path-safe-atomic-self-test.json';$result=if(Test-Path $resultPath){Get-Content $resultPath -Raw -Encoding UTF8|ConvertFrom-Json}else{$null};$compiler=@();if(Test-Path $unityLog){$compiler=@(Select-String -LiteralPath $unityLog -Pattern 'error CS\d+|Compilation failed|Scripts have compiler errors|executeMethod.+could not be found' -CaseSensitive:$false)}
$errors=New-Object Collections.Generic.List[string]
if($exit-ne0){$errors.Add("Unity exit code $exit")};if($timedOut){$errors.Add('timeout')};if($compiler.Count){$errors.Add("compiler/error matches=$($compiler.Count)")}
if($null-eq$result-or[string]$result.summaryKind-ne'gate13r-pr1b-v3-path-safe-atomic-persistence-self-test-v1'-or$result.passed-ne$true-or[int]$result.testCount-lt14-or[int]$result.testCount-ne[int]$result.passedTestCount-or[int]$result.residualOwnedTemporaryFileCount-ne0){$errors.Add('path-safe fixture result missing or incomplete')}
if($null-ne$result){
    $idff=@($result.tests|Where-Object id -eq 'idff-v6-legacy-temp-260');$cff=@($result.tests|Where-Object id -eq 'cff-position-legacy-temp-259');$long=@($result.tests|Where-Object id -eq 'legacy-temp-280')
    if($idff.Count-ne1-or[int]$idff[0].legacyTemporaryPathLength-ne260-or$idff[0].actualLegacySuccess-ne$false-or$idff[0].pathSafeSuccess-ne$true-or[int]$idff[0].pathSafeTemporaryPathLength-ge260){$errors.Add('v6-equivalent 260-character boundary did not reproduce/repair exactly')}
    if($cff.Count-ne1-or[int]$cff[0].legacyTemporaryPathLength-ne259-or$cff[0].actualLegacySuccess-ne$true-or$cff[0].pathSafeSuccess-ne$true){$errors.Add('C-FF-equivalent 259-character boundary mismatch')}
    if($long.Count-ne1-or$long[0].pathSafeSuccess-ne$true){$errors.Add('longer legacy-temporary boundary mismatch')}
}
if($null-eq$lock-or$lock.passed-ne$true){$errors.Add('lock hygiene failed')}
$summary=[ordered]@{schemaVersion=1;summaryKind='gate13r-pr1b-v3-path-safe-atomic-self-test-wrapper-v1';savedAtUtc=[DateTime]::UtcNow.ToString('o');unityProcessId=$processId;exitCode=$exit;timedOut=$timedOut;wallSeconds=($completed-$started).TotalSeconds;fixtureCount=if($null-ne$result){[int]$result.testCount}else{0};fixturePassedCount=if($null-ne$result){[int]$result.passedTestCount}else{0};resultSha256=if(Test-Path $resultPath){Get-Gate10RLowerSha256 $resultPath}else{$null};lockHygieneRole='positive';lockHygieneMode=[string]$lock.mode;errors=$errors.ToArray();formalCampaign=$false;passed=$errors.Count-eq0}
Write-Gate10RAtomicUtf8NoBomJson -Path $summaryPath -Value $summary -Depth 20
if($errors.Count){Write-Error("PR1B v3 path-safe atomic self-test failed: "+($errors-join'; '));exit 1};Write-Host 'PR1B v3 path-safe atomic Unity self-test passed.' -ForegroundColor Green;exit 0
