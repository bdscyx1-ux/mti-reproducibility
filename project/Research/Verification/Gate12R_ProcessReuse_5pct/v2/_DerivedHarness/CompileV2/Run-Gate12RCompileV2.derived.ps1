[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$ProjectPath,
    [Parameter(Mandatory=$true)][string]$VerificationRoot,
    [string]$UnityPath='H:\UnityEditor\2022.3.30f1c1\Editor\Unity.exe',
    [switch]$BindingSmokeOnly,
    [int]$TimeoutSeconds=1200
)

$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
if([string]::IsNullOrWhiteSpace($ProjectPath)-or-not[IO.Path]::IsPathRooted($ProjectPath)){throw 'Gate12R compile requires an explicit absolute ProjectPath.'}
$ProjectPath=[IO.Path]::GetFullPath($ProjectPath)
if($BindingSmokeOnly){Write-Output("BINDING-SMOKE-PASSED|Run-Gate12RCompile|$ProjectPath");exit 0}
$VerificationRoot=[IO.Path]::GetFullPath($VerificationRoot);$UnityPath=[IO.Path]::GetFullPath($UnityPath)
Import-Module (Join-Path $ProjectPath 'Research\Gate12RProcessReusePreparation.psm1') -Force
Import-Module (Join-Path $ProjectPath 'Research\Gate10RLockHygieneV3.psm1') -Force
$base=[IO.Path]::GetFullPath((Join-Path $ProjectPath 'Research\Verification\Gate12R_ProcessReuse_5pct'))
if(-not$VerificationRoot.StartsWith($base.TrimEnd('\')+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'VerificationRoot is outside the Gate12R versioned base.'}
if(Test-Path -LiteralPath (Join-Path $ProjectPath 'Research\FormalRuns\Gate13R_ProcessReuse_5pct\v1')){throw 'Gate13R formal root must remain absent.'}
if(-not(Test-Path -LiteralPath $UnityPath -PathType Leaf)){throw "Unity missing: $UnityPath"}
if(@(Get-Process -Name Unity -ErrorAction SilentlyContinue).Count-gt0-or(Test-Path -LiteralPath (Join-Path $ProjectPath 'Temp\UnityLockfile'))){throw 'Unity must be closed and the project lock absent.'}
$output=Join-Path $VerificationRoot 'Compile';if(Test-Path -LiteralPath $output){throw "Create-new compile output exists: $output"};New-Item -ItemType Directory -Path $output|Out-Null
$log=Join-Path $output 'Gate12R.Unity.log';$summaryPath=Join-Path $output 'summary.json'
$started=Get-Date;$args=@('-batchmode','-nographics','-quit','-projectPath',('"'+$ProjectPath+'"'),'-logFile',('"'+$log+'"'))
$process=Start-Process -FilePath $UnityPath -ArgumentList $args -WorkingDirectory (Split-Path -Parent $UnityPath) -WindowStyle Hidden -PassThru
$timedOut=$false;$deadline=(Get-Date).AddSeconds($TimeoutSeconds)
while(-not$process.HasExited){if((Get-Date)-ge$deadline){$timedOut=$true;break};Start-Sleep -Milliseconds 500;$process.Refresh()}
if($timedOut){& taskkill.exe /PID $process.Id /T /F 2>&1|Out-Null;try{Wait-Process -Id $process.Id -Timeout 30 -ErrorAction SilentlyContinue}catch{}}
$process.Refresh();$exitCode=if($timedOut){124}else{[int]$process.ExitCode};$completed=Get-Date
$lock=Invoke-Gate10RPostExitQuiescenceV3 -ProjectPath $ProjectPath -OwnedProcessId $process.Id -OwnedProcessStartedAt ([DateTimeOffset]$started) -OwnedProcessCompletedAt ([DateTimeOffset]$completed) -Role 'compile' -EvidenceDirectory (Join-Path $output 'LockHygiene') -ContextId 'gate12r-compile' -QuiescenceSeconds 60 -PollMilliseconds 250 -TimestampToleranceSeconds 2
$matches=@();if(Test-Path -LiteralPath $log){$matches=@(Select-String -LiteralPath $log -Pattern 'error CS\d+|Scripts have compiler errors|Compilation failed|executeMethod.+could not be found' -CaseSensitive:$false)}
$errors=New-Object Collections.Generic.List[string]
if($timedOut){$errors.Add("Hard timeout after $TimeoutSeconds seconds.")};if($exitCode-ne0){$errors.Add("Unity exit code $exitCode.")};if(-not(Test-Path -LiteralPath $log -PathType Leaf)){$errors.Add('Unity compile log missing.')};if($matches.Count){$errors.Add("Compiler/error pattern count: $($matches.Count).")};if($null-eq$lock-or$lock.passed-ne$true-or[string]$lock.mode-ne'natural-lock-absence'){$errors.Add('Post-exit lock hygiene did not pass naturally.')}
$summary=[ordered]@{schemaVersion=1;summaryKind='gate12r-unity-compilation-v1';savedAtUtc=[DateTime]::UtcNow.ToString('o');unityPath=$UnityPath;unitySha256=Get-Gate12RLowerSha256 $UnityPath;unityProcessId=[int]$process.Id;startedAt=$started.ToString('o');completedAt=$completed.ToString('o');wallSeconds=($completed-$started).TotalSeconds;exitCode=$exitCode;timedOut=$timedOut;compilerErrorMatchCount=$matches.Count;logSha256=if(Test-Path $log){Get-Gate12RLowerSha256 $log}else{$null};unityCommandSha256=Get-Gate12RLowerSha256 (Join-Path $ProjectPath 'Assets\_Scripts\Research\Editor\Gate10RProcessReuseBatchCommand.cs');lockHygieneMode=[string]$lock.mode;lockHygieneReceiptPath=[string]$lock.receiptPath;lockHygieneReceiptSha256=[string]$lock.receiptSha256;formalCampaign=$false;errors=$errors.ToArray();passed=$errors.Count-eq0}
Write-Gate12RAtomicUtf8NoBomJson -Path $summaryPath -Value $summary -Depth 20
if($errors.Count){Write-Error("Gate12R compilation failed: "+($errors-join'; '));exit 1}
Write-Host 'Gate12R Unity compilation passed.' -ForegroundColor Green
exit 0
