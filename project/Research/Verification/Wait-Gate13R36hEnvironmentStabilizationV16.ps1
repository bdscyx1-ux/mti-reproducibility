[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$ProjectPath,
    [Parameter(Mandatory=$true)][string]$VerificationRoot,
    [switch]$BindingSmokeOnly,
    [int]$MaximumWaitSeconds=600,
    [int]$SampleIntervalSeconds=5,
    [int]$RequiredConsecutivePassingSamples=3
)
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest;$ProjectPath=[IO.Path]::GetFullPath($ProjectPath);$VerificationRoot=[IO.Path]::GetFullPath($VerificationRoot);$utf8=New-Object Text.UTF8Encoding($false,$true)
$expected=[IO.Path]::GetFullPath((Join-Path $ProjectPath 'Research\Verification\Gate13R_36h_10pct_4Lane\v16'));if($VerificationRoot-ne$expected){throw 'Environment stabilization root differs from frozen v16 verification root.'}
if($BindingSmokeOnly){Write-Output("BINDING-SMOKE-PASSED|Wait-Gate13R36hEnvironmentStabilizationV16|$ProjectPath");exit 0}
if($MaximumWaitSeconds-ne600-or$SampleIntervalSeconds-ne5-or$RequiredConsecutivePassingSamples-ne3){throw 'Environment stabilization timing differs from the frozen v16 policy.'}
$summaryPath=Join-Path $VerificationRoot 'EnvironmentStabilization.summary.json';if(Test-Path -LiteralPath $summaryPath){throw 'Create-new environment stabilization summary exists.'}
$plan=Get-Content -LiteralPath (Join-Path $ProjectPath 'Research\Gate13R_36h_10pct_4Lane_Pilot_Plan.v16.json') -Raw -Encoding UTF8|ConvertFrom-Json;$threshold=[long]$plan.environment.minimumFreePhysicalMemoryBytes;if($threshold-ne17179869184L){throw 'Free-memory threshold differs from the frozen 16 GiB gate.'}
foreach($root in @('Research\PilotRuns\Gate13R_36h_10pct_4Lane\v16','Research\FormalRuns\Gate13R_36h_10pct_4Lane\v1')){if(Test-Path -LiteralPath (Join-Path $ProjectPath $root)){throw "Forbidden experiment root exists: $root"}}
$samples=New-Object Collections.Generic.List[object];$started=[DateTimeOffset]::Now;$deadline=(Get-Date).AddSeconds($MaximumWaitSeconds);$consecutive=0;$passed=$false;$failure=''
do{
    $unityCount=@(Get-Process Unity -ErrorAction SilentlyContinue).Count;$locks=New-Object Collections.Generic.List[string];foreach($root in @(1..4|ForEach-Object{'H:\DDM_Final_Project_Gate13R36H\v16\lane-{0:D2}'-f$_})){if(Test-Path -LiteralPath (Join-Path $root 'Temp\UnityLockfile')){$locks.Add($root)}}
    $os=Get-CimInstance Win32_OperatingSystem;$free=[long]$os.FreePhysicalMemory*1024L;$samplePassed=$free-ge$threshold-and$unityCount-eq0-and$locks.Count-eq0;if($samplePassed){$consecutive++}else{$consecutive=0}
    $samples.Add([pscustomobject][ordered]@{sampledAtUtc=[DateTime]::UtcNow.ToString('o');freePhysicalMemoryBytes=$free;thresholdBytes=$threshold;unityProcessCount=$unityCount;laneLockCount=$locks.Count;passed=$samplePassed;consecutivePassingSamples=$consecutive})
    if($unityCount-ne0-or$locks.Count-ne0){$failure="Unity quiescence was lost during environment stabilization: processes=$unityCount locks=$($locks.Count).";break}
    if($consecutive-ge$RequiredConsecutivePassingSamples){$passed=$true;break}
    if((Get-Date)-ge$deadline){$failure='Free physical memory did not satisfy the frozen threshold for three consecutive samples within 600 seconds.';break}
    Start-Sleep -Seconds $SampleIntervalSeconds
}while($true)
$completed=[DateTimeOffset]::Now;$summary=[ordered]@{schemaVersion=1;summaryKind='gate13r-36h-noninvasive-environment-stabilization-v16';completedAtUtc=[DateTime]::UtcNow.ToString('o');maximumWaitSeconds=$MaximumWaitSeconds;sampleIntervalSeconds=$SampleIntervalSeconds;requiredConsecutivePassingSamples=$RequiredConsecutivePassingSamples;thresholdBytes=$threshold;sampleCount=$samples.Count;samples=$samples.ToArray();startedAt=$started.ToString('o');completedAt=$completed.ToString('o');wallSeconds=($completed-$started).TotalSeconds;processTerminationUsed=$false;workingSetTrimmingUsed=$false;cacheFlushUsed=$false;thresholdRelaxed=$false;pilotRootCreated=Test-Path (Join-Path $ProjectPath 'Research\PilotRuns\Gate13R_36h_10pct_4Lane\v16');formalCampaign=$false;error=$failure;passed=$passed}
$json=($summary|ConvertTo-Json -Depth 30).Replace("`r`n","`n").Replace("`r","`n")+"`n";$tmp=$summaryPath+'.tmp-'+[Guid]::NewGuid().ToString('N');[IO.File]::WriteAllText($tmp,$json,$utf8);[IO.File]::Move($tmp,$summaryPath)
if(-not$passed){Write-Error("Environment stabilization failed: $failure");exit 1};Write-Host("Environment stabilization passed after {0} samples; frozen 16 GiB threshold unchanged."-f$samples.Count)-ForegroundColor Green;exit 0
