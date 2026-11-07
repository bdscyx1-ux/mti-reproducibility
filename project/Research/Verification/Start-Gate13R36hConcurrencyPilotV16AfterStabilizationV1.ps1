[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$ProjectPath,
    [Parameter(Mandatory=$true)][string]$PrePilotAuditPath,
    [string]$UnityPath='H:\UnityEditor\2022.3.30f1c1\Editor\Unity.exe',
    [switch]$BindingSmokeOnly,
    [int]$MaximumWaitSeconds=600,
    [int]$SampleIntervalSeconds=5,
    [int]$RequiredConsecutivePassingSamples=3
)

$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$ProjectPath=[IO.Path]::GetFullPath($ProjectPath)
$PrePilotAuditPath=[IO.Path]::GetFullPath($PrePilotAuditPath)
$UnityPath=[IO.Path]::GetFullPath($UnityPath)
$thresholdBytes=17179869184L
$pilotRoot=[IO.Path]::GetFullPath((Join-Path $ProjectPath 'Research\PilotRuns\Gate13R_36h_10pct_4Lane\v16'))
$formalRoot=[IO.Path]::GetFullPath((Join-Path $ProjectPath 'Research\FormalRuns\Gate13R_36h_10pct_4Lane\v1'))
$pilotScript=[IO.Path]::GetFullPath((Join-Path $ProjectPath 'Research\Run-Gate13R36hConcurrencyPilotV16.ps1'))
$provenancePath=[IO.Path]::GetFullPath((Join-Path $ProjectPath 'Research\Gate13R_36h_10pct_4Lane_Provenance.v16.json'))
$diagnosisPath=[IO.Path]::GetFullPath((Join-Path $ProjectPath 'Research\Gate13R_36h_10pct_4Lane_v16_Pilot_PreRoot_FreeMemory_Race_Diagnosis.v1.json'))
$evidencePath=[IO.Path]::GetFullPath((Join-Path $ProjectPath 'Research\Gate13R_36h_10pct_4Lane_Pilot_Launch_Stabilization.v1.json'))
$utf8=New-Object Text.UTF8Encoding($false,$true)

if($BindingSmokeOnly){
    Write-Output("BINDING-SMOKE-PASSED|Start-Gate13R36hConcurrencyPilotV16AfterStabilizationV1|$ProjectPath")
    exit 0
}
if($MaximumWaitSeconds-ne600-or$SampleIntervalSeconds-ne5-or$RequiredConsecutivePassingSamples-ne3){throw 'Launch stabilization timing differs from the versioned policy.'}
foreach($required in @($PrePilotAuditPath,$UnityPath,$pilotScript,$provenancePath,$diagnosisPath)){
    if(-not(Test-Path -LiteralPath $required -PathType Leaf)){throw "Required launch input missing: $required"}
}
if(Test-Path -LiteralPath $pilotRoot){throw 'The sole pilot root already exists; retry/resume is forbidden.'}
if(Test-Path -LiteralPath $formalRoot){throw 'The formal root exists although no formal campaign is authorized.'}
if(Test-Path -LiteralPath $evidencePath){throw 'Create-new launch-stabilization evidence already exists.'}

$audit=Get-Content -LiteralPath $PrePilotAuditPath -Raw -Encoding UTF8|ConvertFrom-Json
if($audit.passed-ne$true-or$audit.pilotRootCreated-ne$false-or$audit.formalCampaign-ne$false){throw 'The bound pre-pilot audit is not a passing nonexecuting audit.'}
$provenance=Get-Content -LiteralPath $provenancePath -Raw -Encoding UTF8|ConvertFrom-Json
$actualPilotHash=(Get-FileHash -LiteralPath $pilotScript -Algorithm SHA256).Hash.ToLowerInvariant()
if($actualPilotHash-ne[string]$provenance.pilotOrchestrator.sha256){throw 'Frozen v16 pilot orchestrator hash differs from provenance.'}
if([string]$audit.provenanceSha256-ne(Get-FileHash -LiteralPath $provenancePath -Algorithm SHA256).Hash.ToLowerInvariant()){throw 'Pre-pilot audit is not bound to active provenance.'}

$samples=New-Object Collections.Generic.List[object]
$started=[DateTimeOffset]::Now
$deadline=(Get-Date).AddSeconds($MaximumWaitSeconds)
$consecutive=0
$passed=$false
$failure=''
do{
    $unityCount=@(Get-Process Unity -ErrorAction SilentlyContinue).Count
    $laneLocks=New-Object Collections.Generic.List[string]
    foreach($lane in 1..4){
        $lockPath='H:\DDM_Final_Project_Gate13R36H\v16\lane-{0:D2}\Temp\UnityLockfile'-f$lane
        if(Test-Path -LiteralPath $lockPath){$laneLocks.Add($lockPath)}
    }
    $os=Get-CimInstance Win32_OperatingSystem
    $freeBytes=[long]$os.FreePhysicalMemory*1024L
    $samplePassed=$freeBytes-ge$thresholdBytes-and$unityCount-eq0-and$laneLocks.Count-eq0
    if($samplePassed){$consecutive++}else{$consecutive=0}
    $samples.Add([pscustomobject][ordered]@{
        sampledAtUtc=[DateTime]::UtcNow.ToString('o')
        freePhysicalMemoryBytes=$freeBytes
        thresholdBytes=$thresholdBytes
        unityProcessCount=$unityCount
        laneLockCount=$laneLocks.Count
        passed=$samplePassed
        consecutivePassingSamples=$consecutive
    })
    if($unityCount-ne0-or$laneLocks.Count-ne0){
        $failure="Unity quiescence was lost during launch stabilization: processes=$unityCount locks=$($laneLocks.Count)."
        break
    }
    if($consecutive-ge$RequiredConsecutivePassingSamples){$passed=$true;break}
    if((Get-Date)-ge$deadline){
        $failure='Free physical memory did not satisfy the frozen threshold for three consecutive samples within 600 seconds.'
        break
    }
    Start-Sleep -Seconds $SampleIntervalSeconds
}while($true)

$completed=[DateTimeOffset]::Now
$evidence=[ordered]@{
    schemaVersion=1
    evidenceKind='gate13r-36h-v16-noninvasive-pilot-launch-stabilization-v1'
    createdAtUtc=[DateTime]::UtcNow.ToString('o')
    status=if($passed){'PASSED-INVOKING-FROZEN-PILOT'}else{'FAILED-NO-PILOT-ROOT'}
    thresholdBytes=$thresholdBytes
    maximumWaitSeconds=$MaximumWaitSeconds
    sampleIntervalSeconds=$SampleIntervalSeconds
    requiredConsecutivePassingSamples=$RequiredConsecutivePassingSamples
    sampleCount=$samples.Count
    samples=$samples.ToArray()
    startedAt=$started.ToString('o')
    completedAt=$completed.ToString('o')
    wallSeconds=($completed-$started).TotalSeconds
    processTerminationUsed=$false
    workingSetTrimmingUsed=$false
    cacheFlushUsed=$false
    thresholdRelaxed=$false
    pilotOrchestratorRelativePath='Research/Run-Gate13R36hConcurrencyPilotV16.ps1'
    pilotOrchestratorSha256=$actualPilotHash
    diagnosisRelativePath='Research/Gate13R_36h_10pct_4Lane_v16_Pilot_PreRoot_FreeMemory_Race_Diagnosis.v1.json'
    diagnosisSha256=(Get-FileHash -LiteralPath $diagnosisPath -Algorithm SHA256).Hash.ToLowerInvariant()
    prePilotAuditRelativePath=$PrePilotAuditPath.Substring($ProjectPath.TrimEnd('\').Length+1).Replace('\','/')
    prePilotAuditSha256=(Get-FileHash -LiteralPath $PrePilotAuditPath -Algorithm SHA256).Hash.ToLowerInvariant()
    pilotRootCreated=Test-Path -LiteralPath $pilotRoot
    formalRootCreated=Test-Path -LiteralPath $formalRoot
    error=$failure
    passed=$passed
    formalCampaign=$false
}
$json=($evidence|ConvertTo-Json -Depth 30).Replace("`r`n","`n").Replace("`r","`n")+"`n"
$temporary=$evidencePath+'.tmp-'+[Guid]::NewGuid().ToString('N')
[IO.File]::WriteAllText($temporary,$json,$utf8)
[IO.File]::Move($temporary,$evidencePath)
if(-not$passed){Write-Error("Launch stabilization failed: $failure");exit 1}

# Invoke the unchanged frozen orchestrator immediately in this PowerShell host.
# Its own authoritative preflight still applies and its exit terminates this host.
& $pilotScript -ProjectPath $ProjectPath -PilotPlanPath 'Research\Gate13R_36h_10pct_4Lane_Pilot_Plan.v16.json' -SchedulePath 'Research\Gate13R_36h_10pct_4Lane_Pilot_Schedule.v16.json' -ProvenancePath 'Research\Gate13R_36h_10pct_4Lane_Provenance.v16.json' -PrePilotAuditPath $PrePilotAuditPath -UnityPath $UnityPath
exit $LASTEXITCODE
