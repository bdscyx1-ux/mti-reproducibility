[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$LaneProjectPath,
    [Parameter(Mandatory=$true)][string]$OutputDirectory,
    [Parameter(Mandatory=$true)][ValidateRange(1,4)][int]$LaneNumber,
    [Parameter(Mandatory=$true)][ValidatePattern('^0x[0-9A-Fa-f]{8,16}$')][string]$AffinityMaskHex,
    [string]$UnityPath='H:\UnityEditor\2022.3.30f1c1\Editor\Unity.exe',
    [switch]$BindingSmokeOnly,
    [int]$TimeoutSeconds=300
)

$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
$utf8=New-Object Text.UTF8Encoding($false,$true)
function Get-LowerHash([string]$Path){return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()}
function Read-Json([string]$Path){return Get-Content -LiteralPath $Path -Raw -Encoding UTF8|ConvertFrom-Json}
function Write-AtomicJson([string]$Path,$Value,[int]$Depth=30){$parent=Split-Path -Parent $Path;if(-not(Test-Path -LiteralPath $parent -PathType Container)){New-Item -ItemType Directory -Path $parent|Out-Null};$json=($Value|ConvertTo-Json -Depth $Depth).Replace("`r`n","`n").Replace("`r","`n")+"`n";$tmp=$Path+'.tmp-'+[Guid]::NewGuid().ToString('N');[IO.File]::WriteAllText($tmp,$json,$utf8);if(Test-Path -LiteralPath $Path){$bak=$Path+'.bak-'+[Guid]::NewGuid().ToString('N');[IO.File]::Replace($tmp,$Path,$bak);if(Test-Path -LiteralPath $bak){[IO.File]::Delete($bak)}}else{[IO.File]::Move($tmp,$Path)}}
function Get-LaneUnityProcesses([string]$ProjectPath){return @(Get-CimInstance Win32_Process -Filter "Name='Unity.exe'" -ErrorAction SilentlyContinue|Where-Object{[string]$_.CommandLine -like ('*'+$ProjectPath+'*')})}

$LaneProjectPath=[IO.Path]::GetFullPath($LaneProjectPath);$OutputDirectory=[IO.Path]::GetFullPath($OutputDirectory);$UnityPath=[IO.Path]::GetFullPath($UnityPath)
$expectedLane=[IO.Path]::GetFullPath(('H:\DDM_Final_Project_Gate13R36H\v14\lane-{0:D2}'-f$LaneNumber));if($LaneProjectPath-ne$expectedLane){throw 'Lane path differs from frozen plan.'}
$expectedRoot=[IO.Path]::GetFullPath((Join-Path $LaneProjectPath 'Research\Verification\Gate13R_36h_10pct_4Lane\v14'))
if(-not$OutputDirectory.StartsWith($expectedRoot.TrimEnd('\')+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'Telemetry output is outside the lane-local verification root.'}
$expectedMasks=@('0x000000FF','0x0000FF00','0x00FF0000','0xFF000000');if($AffinityMaskHex.ToUpperInvariant()-ne$expectedMasks[$LaneNumber-1].ToUpperInvariant()){throw 'Affinity mask differs from the frozen lane policy.'}
if($BindingSmokeOnly){Write-Output("BINDING-SMOKE-PASSED|Run-Gate13R36hTelemetryProbeV14|$LaneNumber|$LaneProjectPath");exit 0}
if(-not(Test-Path -LiteralPath $UnityPath -PathType Leaf)){throw 'Unity executable is missing.'};if(Test-Path -LiteralPath $OutputDirectory){throw 'Create-new telemetry output exists.'}
if(Test-Path -LiteralPath (Join-Path $LaneProjectPath 'Temp\UnityLockfile')){throw 'Lane Unity lock exists before telemetry start.'};if(@(Get-LaneUnityProcesses $LaneProjectPath).Count){throw 'Lane Unity process exists before telemetry start.'}
$unityLog=$OutputDirectory+'.Unity.log';$stdout=$OutputDirectory+'.stdout.log';$stderr=$OutputDirectory+'.stderr.log';$summaryPath=$OutputDirectory+'.summary.json'
foreach($path in @($unityLog,$stdout,$stderr,$summaryPath)){if(Test-Path -LiteralPath $path){throw "Create-new telemetry sidecar exists: $path"}}
$parent=Split-Path -Parent $OutputDirectory;if(-not(Test-Path -LiteralPath $parent -PathType Container)){New-Item -ItemType Directory -Path $parent|Out-Null}
$started=[DateTimeOffset]::Now;$args=@('-batchmode','-nographics','-quit','-projectPath',('"'+$LaneProjectPath+'"'),'-executeMethod','DDM.Research.Editor.Gate13R36hConcurrencyBatchCommandV1.ProbeTelemetry','-ddmGate10RTelemetryProbeDirectory',('"'+$OutputDirectory+'"'),'-logFile',('"'+$unityLog+'"'))
$process=Start-Process -FilePath $UnityPath -ArgumentList $args -WorkingDirectory (Split-Path -Parent $UnityPath) -WindowStyle Hidden -RedirectStandardOutput $stdout -RedirectStandardError $stderr -PassThru
$mask=[Convert]::ToUInt64($AffinityMaskHex.Substring(2),16);$process.ProcessorAffinity=[IntPtr]([Int64]$mask);$process.PriorityClass=[Diagnostics.ProcessPriorityClass]::Normal;$process.Refresh();$observedMask=('0x{0:X8}'-f[uint64]$process.ProcessorAffinity.ToInt64())
$readyPath=Join-Path $OutputDirectory 'telemetry-probe-ready.json';$externalPath=Join-Path $OutputDirectory 'external-os-query.json';$resultPath=Join-Path $OutputDirectory 'telemetry-probe-result.json';$deadline=(Get-Date).AddSeconds($TimeoutSeconds);$errors=New-Object Collections.Generic.List[string]
while(-not(Test-Path -LiteralPath $readyPath -PathType Leaf)-and-not$process.HasExited-and(Get-Date)-lt$deadline){Start-Sleep -Milliseconds 100;$process.Refresh()}
if(-not(Test-Path -LiteralPath $readyPath -PathType Leaf)){$errors.Add('Unity did not publish telemetry ready evidence.')}else{
    $ready=Read-Json $readyPath;if([int]$ready.nativeBefore.processId-ne[int]$process.Id){$errors.Add('Ready PID differs from owned Unity PID.')}
    $cim=Get-CimInstance Win32_Process -Filter ("ProcessId = {0}"-f[int]$process.Id) -ErrorAction SilentlyContinue
    if($null-eq$cim){$errors.Add('Independent CIM query returned no process.')}else{
        $query=[ordered]@{schemaVersion=1;queryKind='gate13r-36h-four-lane-independent-os-memory-query-v1';querySourceId='cim-win32_process-v1';queriedAtUtc=[DateTime]::UtcNow.ToString('o');processId=[int]$cim.ProcessId;name=[string]$cim.Name;executablePath=[string]$cim.ExecutablePath;creationDateUtc=([DateTime]$cim.CreationDate).ToUniversalTime().ToString('o');workingSetBytes=[long]$cim.WorkingSetSize;privateMemoryBytes=[long]$cim.PrivatePageCount}
        Write-AtomicJson $externalPath $query 10
    }
}
while(-not$process.HasExited-and(Get-Date)-lt$deadline){Start-Sleep -Milliseconds 100;$process.Refresh()}
$timedOut=$false;if(-not$process.HasExited){$timedOut=$true;&taskkill.exe /PID $process.Id /T /F 2>&1|Out-Null;try{Wait-Process -Id $process.Id -Timeout 30 -ErrorAction SilentlyContinue}catch{};$errors.Add("Hard timeout after $TimeoutSeconds seconds.")}
$process.Refresh();$exitCode=if($timedOut){124}else{[int]$process.ExitCode};$completed=[DateTimeOffset]::Now
$quiescenceDeadline=(Get-Date).AddSeconds(60);$lockPath=Join-Path $LaneProjectPath 'Temp\UnityLockfile';do{$laneProcesses=@(Get-LaneUnityProcesses $LaneProjectPath);$lockExists=Test-Path -LiteralPath $lockPath;if($laneProcesses.Count-eq0-and-not$lockExists){break};Start-Sleep -Milliseconds 250}while((Get-Date)-lt$quiescenceDeadline)
$laneProcesses=@(Get-LaneUnityProcesses $LaneProjectPath);$lockExists=Test-Path -LiteralPath $lockPath;if($exitCode-ne0){$errors.Add("Unity exit code $exitCode.")};if($laneProcesses.Count){$errors.Add('Lane Unity process remains after telemetry exit.')};if($lockExists){$errors.Add('Lane lock remains after telemetry exit.')}
$compiler=@();if(Test-Path -LiteralPath $unityLog){$compiler=@(Select-String -LiteralPath $unityLog -Pattern 'error CS\d+|Compilation failed|Scripts have compiler errors|executeMethod.+could not be found' -CaseSensitive:$false)};if($compiler.Count){$errors.Add("Compiler/error patterns: $($compiler.Count).")}
$result=if(Test-Path -LiteralPath $resultPath){Read-Json $resultPath}else{$null}
if($null-eq$result){$errors.Add('Telemetry result is missing.')}else{foreach($value in @($result.nativeBefore.workingSetBytes,$result.nativeAfter.workingSetBytes,$result.externalQuery.workingSetBytes,$result.nativeBefore.privateMemoryBytes,$result.nativeAfter.privateMemoryBytes,$result.externalQuery.privateMemoryBytes)){if([long]$value-le0){$errors.Add('Telemetry contains a non-positive memory value.');break}};if([string]$result.executionDesignId-ne'gate13r-36h-10pct-four-isolated-editor-lanes-v1'-or$result.passed-ne$true-or$result.workingSetPassed-ne$true-or$result.privateMemoryPassed-ne$true-or$result.pidPassed-ne$true-or$result.executablePassed-ne$true-or$result.timestampOrderPassed-ne$true-or$result.creationTimePassed-ne$true){$errors.Add('PSAPI/CIM assertions failed.')}}
$summary=[ordered]@{schemaVersion=1;summaryKind='gate13r-36h-four-lane-telemetry-wrapper-v14';completedAtUtc=[DateTime]::UtcNow.ToString('o');lane=$LaneNumber;laneProjectPath=$LaneProjectPath;affinityMaskRequested=$AffinityMaskHex;affinityMaskObserved=$observedMask;unityProcessId=$process.Id;startedAt=$started.ToString('o');completedAt=$completed.ToString('o');wallSeconds=($completed-$started).TotalSeconds;exitCode=$exitCode;timedOut=$timedOut;readySha256=if(Test-Path $readyPath){Get-LowerHash $readyPath}else{$null};externalQuerySha256=if(Test-Path $externalPath){Get-LowerHash $externalPath}else{$null};resultSha256=if(Test-Path $resultPath){Get-LowerHash $resultPath}else{$null};laneLockAbsent=-not$lockExists;errors=$errors.ToArray();passed=$errors.Count-eq0}
Write-AtomicJson $summaryPath $summary 20
if($errors.Count){Write-Error("Gate13R 36h telemetry failed: "+($errors-join'; '));exit 1}
Write-Host("Gate13R 36h telemetry passed for lane {0}."-f$LaneNumber)-ForegroundColor Green;exit 0
