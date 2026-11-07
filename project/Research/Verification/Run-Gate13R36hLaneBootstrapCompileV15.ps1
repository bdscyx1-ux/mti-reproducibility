[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$LaneProjectPath,
    [Parameter(Mandatory=$true)][string]$OutputPrefix,
    [Parameter(Mandatory=$true)][ValidateRange(1,4)][int]$LaneNumber,
    [Parameter(Mandatory=$true)][ValidatePattern('^0x[0-9A-Fa-f]{8,16}$')][string]$AffinityMaskHex,
    [string]$UnityPath='H:\UnityEditor\2022.3.30f1c1\Editor\Unity.exe',
    [switch]$BindingSmokeOnly,
    [int]$TimeoutSeconds=1200
)

$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$utf8=New-Object Text.UTF8Encoding($false,$true)
function Get-LowerHash([string]$Path){return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()}
function Write-AtomicJson([string]$Path,$Value,[int]$Depth=30){$parent=Split-Path -Parent $Path;if(-not(Test-Path -LiteralPath $parent -PathType Container)){New-Item -ItemType Directory -Path $parent|Out-Null};$json=($Value|ConvertTo-Json -Depth $Depth).Replace("`r`n","`n").Replace("`r","`n")+"`n";$tmp=$Path+'.tmp-'+[Guid]::NewGuid().ToString('N');[IO.File]::WriteAllText($tmp,$json,$utf8);if(Test-Path -LiteralPath $Path){throw "Create-new bootstrap summary exists: $Path"};[IO.File]::Move($tmp,$Path)}
function Get-LaneUnityProcesses([string]$ProjectPath){return @(Get-CimInstance Win32_Process -Filter "Name='Unity.exe'" -ErrorAction SilentlyContinue|Where-Object{[string]$_.CommandLine -like ('*'+$ProjectPath+'*')})}

$LaneProjectPath=[IO.Path]::GetFullPath($LaneProjectPath)
$OutputPrefix=[IO.Path]::GetFullPath($OutputPrefix)
$UnityPath=[IO.Path]::GetFullPath($UnityPath)
$expectedLane=[IO.Path]::GetFullPath(('H:\DDM_Final_Project_Gate13R36H\v15\lane-{0:D2}'-f$LaneNumber))
if($LaneProjectPath-ne$expectedLane){throw 'Lane path differs from the frozen v15 plan.'}
$expectedRoot=[IO.Path]::GetFullPath((Join-Path $LaneProjectPath 'Research\Verification\Gate13R_36h_10pct_4Lane\v15'))
if(-not$OutputPrefix.StartsWith($expectedRoot.TrimEnd('\')+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'Bootstrap output is outside the lane-local v15 verification root.'}
$expectedMasks=@('0x000000FF','0x0000FF00','0x00FF0000','0xFF000000')
if($AffinityMaskHex.ToUpperInvariant()-ne$expectedMasks[$LaneNumber-1].ToUpperInvariant()){throw 'Affinity mask differs from the frozen lane policy.'}
if($BindingSmokeOnly){Write-Output("BINDING-SMOKE-PASSED|Run-Gate13R36hLaneBootstrapCompileV15|$LaneNumber|$LaneProjectPath");exit 0}
if(-not(Test-Path -LiteralPath $UnityPath -PathType Leaf)){throw 'Unity executable is missing.'}
if(Test-Path -LiteralPath (Join-Path $LaneProjectPath 'Temp\UnityLockfile')){throw 'Lane Unity lock exists before bootstrap.'}
if(@(Get-LaneUnityProcesses $LaneProjectPath).Count){throw 'Lane Unity process exists before bootstrap.'}

$unityLog=$OutputPrefix+'.Unity.log'
$stdout=$OutputPrefix+'.stdout.log'
$stderr=$OutputPrefix+'.stderr.log'
$summaryPath=$OutputPrefix+'.summary.json'
foreach($path in @($unityLog,$stdout,$stderr,$summaryPath)){if(Test-Path -LiteralPath $path){throw "Create-new bootstrap sidecar exists: $path"}}
$parent=Split-Path -Parent $OutputPrefix
if(-not(Test-Path -LiteralPath $parent -PathType Container)){New-Item -ItemType Directory -Path $parent|Out-Null}

$started=[DateTimeOffset]::Now
$args=@('-batchmode','-nographics','-quit','-projectPath',('"'+$LaneProjectPath+'"'),'-logFile',('"'+$unityLog+'"'))
$process=Start-Process -FilePath $UnityPath -ArgumentList $args -WorkingDirectory (Split-Path -Parent $UnityPath) -WindowStyle Hidden -RedirectStandardOutput $stdout -RedirectStandardError $stderr -PassThru
$mask=[Convert]::ToUInt64($AffinityMaskHex.Substring(2),16)
$process.ProcessorAffinity=[IntPtr]([Int64]$mask)
$process.PriorityClass=[Diagnostics.ProcessPriorityClass]::Normal
$process.Refresh()
$observedMask=('0x{0:X8}'-f[uint64]$process.ProcessorAffinity.ToInt64())
$deadline=(Get-Date).AddSeconds($TimeoutSeconds)
$timedOut=$false
while(-not$process.HasExited){if((Get-Date)-ge$deadline){$timedOut=$true;break};Start-Sleep -Milliseconds 250;$process.Refresh()}
if($timedOut){&taskkill.exe /PID $process.Id /T /F 2>&1|Out-Null;try{Wait-Process -Id $process.Id -Timeout 30 -ErrorAction SilentlyContinue}catch{}}
try{$process.WaitForExit()}catch{}
$process.Refresh()
$exitCode=if($timedOut){124}else{[int]$process.ExitCode}
$completed=[DateTimeOffset]::Now

$lockPath=Join-Path $LaneProjectPath 'Temp\UnityLockfile'
$quiescenceDeadline=(Get-Date).AddSeconds(60)
do{$laneProcesses=@(Get-LaneUnityProcesses $LaneProjectPath);$lockExists=Test-Path -LiteralPath $lockPath;if($laneProcesses.Count-eq0-and-not$lockExists){break};Start-Sleep -Milliseconds 250}while((Get-Date)-lt$quiescenceDeadline)
$laneProcesses=@(Get-LaneUnityProcesses $LaneProjectPath)
$lockExists=Test-Path -LiteralPath $lockPath
$patterns=@('error CS\d+','Compilation failed','Scripts have compiler errors','executeMethod.+could not be found','PostProcessing failed','Tundra build failed','System\.IO\.IOException.+being used by another process')
$matches=@()
$errors=New-Object Collections.Generic.List[string]
if($timedOut){$errors.Add("Hard timeout after $TimeoutSeconds seconds.")}
if($exitCode-ne0){$errors.Add("Unity exit code $exitCode.")}
$logHash=$null;$logHashError='';$logHashWaitStarted=[DateTimeOffset]::Now
if(Test-Path -LiteralPath $unityLog -PathType Leaf){
    $logHashDeadline=(Get-Date).AddSeconds(60)
    do{try{$logHash=Get-LowerHash $unityLog;$logHashError='';break}catch{$logHashError=$_.Exception.Message;Start-Sleep -Milliseconds 250}}while((Get-Date)-lt$logHashDeadline)
    if($null-eq$logHash){$errors.Add('Bootstrap Unity log did not become readable for hashing within 60 seconds: '+$logHashError)}
}else{$errors.Add('Bootstrap Unity log is missing.')}
$logHashWaitSeconds=([DateTimeOffset]::Now-$logHashWaitStarted).TotalSeconds
if($null-ne$logHash){try{$matches=@(Select-String -LiteralPath $unityLog -Pattern $patterns -CaseSensitive:$false)}catch{$errors.Add('Bootstrap Unity log could not be scanned after hashing: '+$_.Exception.Message)}}
if($matches.Count){$errors.Add("Compiler/import contention patterns: $($matches.Count).")}
if($laneProcesses.Count){$errors.Add('Lane-owned Unity process remains after bootstrap exit.')}
if($lockExists){$errors.Add('Lane Unity lock remains after natural bootstrap quiescence.')}
if($observedMask.ToUpperInvariant()-ne$AffinityMaskHex.ToUpperInvariant()){$errors.Add('Observed affinity differs from requested affinity.')}
$summary=[ordered]@{
    schemaVersion=1
    summaryKind='gate13r-36h-serial-lane-bootstrap-compile-v15'
    completedAtUtc=[DateTime]::UtcNow.ToString('o')
    policyId='serial-nonmeasured-fresh-lane-bootstrap-before-concurrent-gates-v1'
    lane=$LaneNumber
    laneProjectPath=$LaneProjectPath
    measured=$false
    planningWorkloadExecuted=$false
    excludedFromFormalAnalysis=$true
    unityProcessId=$process.Id
    startedAt=$started.ToString('o')
    completedAt=$completed.ToString('o')
    wallSeconds=($completed-$started).TotalSeconds
    exitCode=$exitCode
    timedOut=$timedOut
    affinityMaskRequested=$AffinityMaskHex
    affinityMaskObserved=$observedMask
    compilerOrImportErrorMatchCount=$matches.Count
    unityLogSha256=$logHash
    logHashFinalized=$null-ne$logHash
    logHashWaitSeconds=$logHashWaitSeconds
    naturalLaneLockRelease=-not$lockExists
    controlledLockCleanupUsed=$false
    remainingLaneUnityProcessCount=$laneProcesses.Count
    errors=$errors.ToArray()
    formalCampaign=$false
    passed=$errors.Count-eq0
}
Write-AtomicJson -Path $summaryPath -Value $summary -Depth 20
if($errors.Count){Write-Error("Gate13R v15 lane bootstrap failed: "+($errors-join'; '));exit 1}
Write-Host("Gate13R v15 serial lane bootstrap passed for lane {0}."-f$LaneNumber)-ForegroundColor Green
exit 0
