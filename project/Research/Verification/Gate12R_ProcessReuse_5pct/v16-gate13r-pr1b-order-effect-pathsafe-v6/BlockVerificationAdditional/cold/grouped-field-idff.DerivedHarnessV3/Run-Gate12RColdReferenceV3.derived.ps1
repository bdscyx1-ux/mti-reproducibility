[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$ProjectPath,
    [Parameter(Mandatory=$true)][string]$ScenarioPath,
    [Parameter(Mandatory=$true)][string]$OutputDirectory,
    [Parameter(Mandatory=$true)][string]$AllowedRoot,
    [Parameter(Mandatory=$true)][string]$RunId,
    [Parameter(Mandatory=$true)][ValidateSet('A*-R','D*L','C-FF','IDFF')][string]$Algorithm,
    [string]$UnityPath='H:\UnityEditor\2022.3.30f1c1\Editor\Unity.exe',
    [switch]$BindingSmokeOnly,
    [int]$TimeoutSeconds=3600
)

$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
if([string]::IsNullOrWhiteSpace($ProjectPath)-or-not[IO.Path]::IsPathRooted($ProjectPath)){throw 'Gate12R cold control requires an explicit absolute ProjectPath.'}
$ProjectPath=[IO.Path]::GetFullPath($ProjectPath)
if($BindingSmokeOnly){Write-Output("BINDING-SMOKE-PASSED|Run-Gate12RColdReference|$ProjectPath");exit 0}
$ScenarioPath=[IO.Path]::GetFullPath($ScenarioPath)
$OutputDirectory=[IO.Path]::GetFullPath($OutputDirectory)
$AllowedRoot=[IO.Path]::GetFullPath($AllowedRoot)
$UnityPath=[IO.Path]::GetFullPath($UnityPath)
Import-Module (Join-Path $ProjectPath 'Research\Gate12RProcessReusePreparation.psm1') -Force
Import-Module (Join-Path $ProjectPath 'Research\Gate10RLockHygieneV3.psm1') -Force

$verificationBase=[IO.Path]::GetFullPath((Join-Path $ProjectPath 'Research\Verification\Gate12R_ProcessReuse_5pct'))
$pilotBase=[IO.Path]::GetFullPath((Join-Path $ProjectPath 'Research\PilotRuns\Gate12R_ProcessReuse_5pct'))
$allowedInVerification=$AllowedRoot.StartsWith($verificationBase.TrimEnd('\')+'\',[StringComparison]::OrdinalIgnoreCase)
$allowedInPilot=$AllowedRoot.StartsWith($pilotBase.TrimEnd('\')+'\',[StringComparison]::OrdinalIgnoreCase)
if(-not($allowedInVerification-or$allowedInPilot)){throw 'AllowedRoot is outside Gate12R versioned verification/pilot bases.'}
if(-not$OutputDirectory.StartsWith($AllowedRoot.TrimEnd('\')+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'Cold-control output is outside AllowedRoot.'}
if(-not(Test-Path -LiteralPath $ScenarioPath -PathType Leaf)){throw "Scenario missing: $ScenarioPath"}
if(-not(Test-Path -LiteralPath $UnityPath -PathType Leaf)){throw "Unity missing: $UnityPath"}
if($RunId-notmatch'^[A-Za-z0-9][A-Za-z0-9_.-]{0,127}$'){throw 'RunId is not file-safe.'}
if(Test-Path -LiteralPath (Join-Path $ProjectPath 'Research\FormalRuns\Gate13R_ProcessReuse_5pct\v1')){throw 'Gate13R formal root must remain absent.'}
if(Test-Path -LiteralPath $OutputDirectory){if(-not(Test-Path -LiteralPath $OutputDirectory -PathType Container)-or@(Get-ChildItem -LiteralPath $OutputDirectory -Force).Count-gt0){throw "Cold-control output is not fresh: $OutputDirectory"}}
$unityLog=$OutputDirectory+'.Unity.log';$summaryPath=$OutputDirectory+'.summary.json'
foreach($path in @($unityLog,$summaryPath)){if(Test-Path -LiteralPath $path){throw "Create-new cold-control sidecar exists: $path"}}
if(@(Get-Process -Name Unity -ErrorAction SilentlyContinue).Count-gt0-or(Test-Path -LiteralPath (Join-Path $ProjectPath 'Temp\UnityLockfile'))){throw 'Unity must be closed and the project lock absent.'}
$parent=Split-Path -Parent $OutputDirectory;if(-not(Test-Path -LiteralPath $parent -PathType Container)){New-Item -ItemType Directory -Path $parent -Force|Out-Null}

$arguments=@('-batchmode','-nographics','-quit','-projectPath',('"'+$ProjectPath+'"'),'-executeMethod','DDM.Research.Editor.ResearchPlanningBatchCommand.Run','-ddmScenarioPath',('"'+$ScenarioPath+'"'),'-ddmOutputDirectory',('"'+$OutputDirectory+'"'),'-ddmRunId',('"'+$RunId+'"'),'-ddmAlgorithm',('"'+$Algorithm+'"'),'-logFile',('"'+$unityLog+'"'))
$started=Get-Date
$process=Start-Process -FilePath $UnityPath -ArgumentList $arguments -WorkingDirectory (Split-Path -Parent $UnityPath) -WindowStyle Hidden -PassThru
$timedOut=$false;$deadline=(Get-Date).AddSeconds($TimeoutSeconds)
while(-not$process.HasExited){if((Get-Date)-ge$deadline){$timedOut=$true;break};Start-Sleep -Milliseconds 500;$process.Refresh()}
if($timedOut){& taskkill.exe /PID $process.Id /T /F 2>&1|Out-Null;try{Wait-Process -Id $process.Id -Timeout 30 -ErrorAction SilentlyContinue}catch{}}
$process.Refresh();$exitCode=if($timedOut){124}else{[int]$process.ExitCode};$completed=Get-Date
$lock=Invoke-Gate10RPostExitQuiescenceV3 -ProjectPath $ProjectPath -OwnedProcessId $process.Id -OwnedProcessStartedAt ([DateTimeOffset]$started) -OwnedProcessCompletedAt ([DateTimeOffset]$completed) -Role 'cold-reference' -EvidenceDirectory ($OutputDirectory+'.lock-hygiene') -ContextId $RunId -QuiescenceSeconds 60 -PollMilliseconds 250 -TimestampToleranceSeconds 2
$compiler=@();if(Test-Path -LiteralPath $unityLog){$compiler=@(Select-String -LiteralPath $unityLog -Pattern 'error CS\d+|Compilation failed|Scripts have compiler errors|executeMethod.+could not be found' -CaseSensitive:$false)}
$manifestPath=Join-Path $OutputDirectory 'manifest.json';$resultPath=Join-Path $OutputDirectory 'workload-result.json'
$manifest=if(Test-Path -LiteralPath $manifestPath -PathType Leaf){Read-Gate12RJson $manifestPath}else{$null}
$errors=New-Object Collections.Generic.List[string]
if($timedOut){$errors.Add("Hard timeout after $TimeoutSeconds seconds.")};if($exitCode-ne0){$errors.Add("Unity exit code $exitCode.")};if($compiler.Count){$errors.Add("Compiler/error pattern count: $($compiler.Count).")}
if($null-eq$manifest-or$manifest.completed-ne$true-or[string]$manifest.runId-ne$RunId-or[string]$manifest.algorithmId-ne$Algorithm){$errors.Add('Cold-control manifest identity/completion mismatch.')}
if(-not(Test-Path -LiteralPath $resultPath -PathType Leaf)){$errors.Add('Cold-control workload result missing.')}
if($null-eq$lock-or$lock.passed-ne$true-or[string]$lock.mode-ne'natural-lock-absence'){$errors.Add('Post-exit lock hygiene did not pass naturally.')}
$summary=[ordered]@{schemaVersion=1;summaryKind='gate12r-fresh-cold-structural-control-wrapper-v1';savedAtUtc=[DateTime]::UtcNow.ToString('o');runId=$RunId;algorithmId=$Algorithm;scenarioPath=$ScenarioPath;outputDirectory=$OutputDirectory;unityProcessId=[int]$process.Id;exitCode=$exitCode;timedOut=$timedOut;startedAt=$started.ToString('o');completedAt=$completed.ToString('o');wallSeconds=($completed-$started).TotalSeconds;unityLogSha256=if(Test-Path $unityLog){Get-Gate12RLowerSha256 $unityLog}else{$null};manifestSha256=if(Test-Path $manifestPath){Get-Gate12RLowerSha256 $manifestPath}else{$null};workloadResultSha256=if(Test-Path $resultPath){Get-Gate12RLowerSha256 $resultPath}else{$null};lockHygieneMode=[string]$lock.mode;lockHygieneReceiptPath=[string]$lock.receiptPath;lockHygieneReceiptSha256=[string]$lock.receiptSha256;formalCampaign=$false;excludedFromFormalAnalysis=$true;structuralReferenceOnly=$true;errors=$errors.ToArray();passed=$errors.Count-eq0}
Write-Gate12RAtomicUtf8NoBomJson -Path $summaryPath -Value $summary -Depth 20
if($errors.Count){Write-Error("Gate12R cold control failed: "+($errors-join'; '));exit 1}
Write-Host "Gate12R cold control passed: $RunId" -ForegroundColor Green
exit 0
