[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$ProjectPath,
    [Parameter(Mandatory=$true)][string]$OutputDirectory,
    [Parameter(Mandatory=$true)][string]$AllowedRoot,
    [string]$UnityPath='H:\UnityEditor\2022.3.30f1c1\Editor\Unity.exe',
    [switch]$BindingSmokeOnly,
    [int]$TimeoutSeconds=600
)

$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
if([string]::IsNullOrWhiteSpace($ProjectPath)-or-not[IO.Path]::IsPathRooted($ProjectPath)){throw 'Gate12R telemetry requires an explicit absolute ProjectPath.'}
$ProjectPath=[IO.Path]::GetFullPath($ProjectPath)
if($BindingSmokeOnly){Write-Output("BINDING-SMOKE-PASSED|Run-Gate12RTelemetryProbe|$ProjectPath");exit 0}
$OutputDirectory=if([IO.Path]::IsPathRooted($OutputDirectory)){[IO.Path]::GetFullPath($OutputDirectory)}else{[IO.Path]::GetFullPath((Join-Path $ProjectPath $OutputDirectory))}
$AllowedRoot=if([IO.Path]::IsPathRooted($AllowedRoot)){[IO.Path]::GetFullPath($AllowedRoot)}else{[IO.Path]::GetFullPath((Join-Path $ProjectPath $AllowedRoot))}
$UnityPath=[IO.Path]::GetFullPath($UnityPath)
Import-Module (Join-Path $PSScriptRoot 'Gate12RProcessReusePreparation.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'Gate10RLockHygieneV3.psm1') -Force

$verificationBase=[IO.Path]::GetFullPath((Join-Path $ProjectPath 'Research\Verification\Gate12R_ProcessReuse_5pct'))
if(-not$AllowedRoot.StartsWith($verificationBase.TrimEnd('\')+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'AllowedRoot is outside the Gate12R versioned verification base.'}
if(-not$OutputDirectory.StartsWith($AllowedRoot.TrimEnd('\')+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'Telemetry output is outside AllowedRoot.'}
if(-not(Test-Path -LiteralPath $UnityPath -PathType Leaf)){throw "Unity executable missing: $UnityPath"}
if(Test-Path -LiteralPath (Join-Path $ProjectPath 'Research\FormalRuns\Gate13R_ProcessReuse_5pct\v1')){throw 'Gate13R formal root must remain absent.'}
if(Test-Path -LiteralPath $OutputDirectory){throw "Create-new telemetry output already exists: $OutputDirectory"}
if(@(Get-Process -Name Unity -ErrorAction SilentlyContinue).Count-gt0-or(Test-Path -LiteralPath (Join-Path $ProjectPath 'Temp\UnityLockfile'))){throw 'Unity must be closed and the project lock absent.'}

$unityLog=$OutputDirectory+'.Unity.log'
$stdoutPath=$OutputDirectory+'.wrapper.stdout.log'
$stderrPath=$OutputDirectory+'.wrapper.stderr.log'
$summaryPath=$OutputDirectory+'.summary.json'
foreach($path in @($unityLog,$stdoutPath,$stderrPath,$summaryPath)){if(Test-Path -LiteralPath $path){throw "Create-new telemetry sidecar exists: $path"}}
$parent=Split-Path -Parent $OutputDirectory
if(-not(Test-Path -LiteralPath $parent -PathType Container)){New-Item -ItemType Directory -Path $parent -Force|Out-Null}

$started=[DateTime]::UtcNow
$arguments=@('-batchmode','-nographics','-quit','-projectPath',('"'+$ProjectPath+'"'),'-executeMethod','DDM.Research.Editor.Gate10RProcessReuseBatchCommand.ProbeTelemetry','-ddmGate10RTelemetryProbeDirectory',('"'+$OutputDirectory+'"'),'-logFile',('"'+$unityLog+'"'))
$process=Start-Process -FilePath $UnityPath -ArgumentList $arguments -WorkingDirectory (Split-Path -Parent $UnityPath) -WindowStyle Hidden -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath -PassThru
$readyPath=Join-Path $OutputDirectory 'telemetry-probe-ready.json'
$externalPath=Join-Path $OutputDirectory 'external-os-query.json'
$resultPath=Join-Path $OutputDirectory 'telemetry-probe-result.json'
$deadline=[DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
while(-not(Test-Path -LiteralPath $readyPath -PathType Leaf)-and-not$process.HasExited-and[DateTime]::UtcNow-lt$deadline){Start-Sleep -Milliseconds 100;$process.Refresh()}
$errors=New-Object Collections.Generic.List[string]
if(-not(Test-Path -LiteralPath $readyPath -PathType Leaf)){$errors.Add('Unity did not publish telemetry-probe-ready.json before exit/timeout.')}else{
    $ready=Read-Gate12RJson $readyPath
    if([int]$ready.nativeBefore.processId-ne[int]$process.Id){$errors.Add('Ready PID differs from owned Unity PID.')}
    $cim=Get-CimInstance Win32_Process -Filter ("ProcessId = {0}"-f[int]$process.Id) -ErrorAction SilentlyContinue
    if($null-eq$cim){$errors.Add('Independent CIM query returned no process.')}else{
        $query=[ordered]@{schemaVersion=1;queryKind='gate12r-independent-os-memory-query-v1';querySourceId='cim-win32_process-v1';queriedAtUtc=[DateTime]::UtcNow.ToString('o');processId=[int]$cim.ProcessId;name=[string]$cim.Name;executablePath=[string]$cim.ExecutablePath;creationDateUtc=([DateTime]$cim.CreationDate).ToUniversalTime().ToString('o');workingSetBytes=[long]$cim.WorkingSetSize;privateMemoryBytes=[long]$cim.PrivatePageCount}
        Write-Gate12RAtomicUtf8NoBomJson -Path $externalPath -Value $query -Depth 10
    }
}
if(-not$process.HasExited){if([DateTime]::UtcNow-ge$deadline){& taskkill.exe /PID $process.Id /T /F 2>&1|Out-Null;$errors.Add('Telemetry process exceeded wrapper timeout.')}else{Wait-Process -Id $process.Id}}
try{$process.Refresh()}catch{}
$exitCode=if($process.HasExited){[int]$process.ExitCode}else{124}
$completed=[DateTime]::UtcNow
$lock=Invoke-Gate10RPostExitQuiescenceV3 -ProjectPath $ProjectPath -OwnedProcessId $process.Id -OwnedProcessStartedAt ([DateTimeOffset]$started) -OwnedProcessCompletedAt ([DateTimeOffset]$completed) -Role 'telemetry' -EvidenceDirectory ($OutputDirectory+'.lock-hygiene') -ContextId 'gate12r-telemetry-probe' -QuiescenceSeconds 60 -PollMilliseconds 250 -TimestampToleranceSeconds 2
$compiler=@();if(Test-Path -LiteralPath $unityLog){$compiler=@(Select-String -LiteralPath $unityLog -Pattern 'error CS\d+|Compilation failed|Scripts have compiler errors|executeMethod.+could not be found' -CaseSensitive:$false)}
if($exitCode-ne0){$errors.Add("Unity exit code $exitCode.")}
if($compiler.Count){$errors.Add("Compiler/error pattern count: $($compiler.Count).")}
if($null-eq$lock-or$lock.passed-ne$true-or[string]$lock.mode-ne'natural-lock-absence'){$errors.Add('Post-exit lock hygiene did not pass naturally.')}
$result=if(Test-Path -LiteralPath $resultPath -PathType Leaf){Read-Gate12RJson $resultPath}else{$null}
if($null-eq$result){$errors.Add('Telemetry result is missing.')}else{
    foreach($value in @($result.nativeBefore.workingSetBytes,$result.nativeAfter.workingSetBytes,$result.externalQuery.workingSetBytes,$result.nativeBefore.privateMemoryBytes,$result.nativeAfter.privateMemoryBytes,$result.externalQuery.privateMemoryBytes)){if([long]$value-le0){$errors.Add('Telemetry contains a non-positive memory value.');break}}
    if($result.passed-ne$true-or$result.workingSetPassed-ne$true-or$result.privateMemoryPassed-ne$true-or$result.pidPassed-ne$true-or$result.executablePassed-ne$true-or$result.timestampOrderPassed-ne$true-or$result.creationTimePassed-ne$true){$errors.Add('Frozen PSAPI/CIM cross-check assertions failed.')}
}
$summary=[ordered]@{schemaVersion=1;summaryKind='gate12r-telemetry-probe-wrapper-v1';savedAtUtc=[DateTime]::UtcNow.ToString('o');outputDirectory=$OutputDirectory;unityPath=$UnityPath;unitySha256=Get-Gate12RLowerSha256 $UnityPath;unityProcessId=[int]$process.Id;startedAtUtc=$started.ToString('o');completedAtUtc=$completed.ToString('o');wallSeconds=($completed-$started).TotalSeconds;exitCode=$exitCode;compilerErrorMatchCount=$compiler.Count;readySha256=if(Test-Path $readyPath){Get-Gate12RLowerSha256 $readyPath}else{$null};externalQuerySha256=if(Test-Path $externalPath){Get-Gate12RLowerSha256 $externalPath}else{$null};resultSha256=if(Test-Path $resultPath){Get-Gate12RLowerSha256 $resultPath}else{$null};lockHygieneMode=[string]$lock.mode;lockHygieneReceiptPath=[string]$lock.receiptPath;lockHygieneReceiptSha256=[string]$lock.receiptSha256;formalCampaign=$false;excludedFromFormalAnalysis=$true;errors=$errors.ToArray();passed=$errors.Count-eq0}
Write-Gate12RAtomicUtf8NoBomJson -Path $summaryPath -Value $summary -Depth 20
if($errors.Count){Write-Error("Gate12R telemetry probe failed: "+($errors-join'; '));exit 1}
Write-Host 'Gate12R telemetry probe passed.' -ForegroundColor Green
exit 0
