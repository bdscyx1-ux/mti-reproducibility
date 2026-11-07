[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$ProjectPath,
    [Parameter(Mandatory=$true)][string]$PilotPlanPath,
    [Parameter(Mandatory=$true)][string]$ProvenancePath,
    [Parameter(Mandatory=$true)][string]$PrePilotAuditPath,
    [Parameter(Mandatory=$true)][string]$TelemetryResultPath,
    [string]$UnityPath='H:\UnityEditor\2022.3.30f1c1\Editor\Unity.exe',
    [switch]$BindingSmokeOnly
)

$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
if([string]::IsNullOrWhiteSpace($ProjectPath)-or-not[IO.Path]::IsPathRooted($ProjectPath)){throw 'PR1B pilot requires an explicit absolute ProjectPath.'}
$ProjectPath=[IO.Path]::GetFullPath($ProjectPath)
if($BindingSmokeOnly){Write-Output("BINDING-SMOKE-PASSED|Run-Gate13RPR1BOrderEffectPilotV1|$ProjectPath");exit 0}
$PilotPlanPath=[IO.Path]::GetFullPath($PilotPlanPath)
$ProvenancePath=[IO.Path]::GetFullPath($ProvenancePath)
$PrePilotAuditPath=[IO.Path]::GetFullPath($PrePilotAuditPath)
$TelemetryResultPath=[IO.Path]::GetFullPath($TelemetryResultPath)
$UnityPath=[IO.Path]::GetFullPath($UnityPath)

Import-Module (Join-Path $ProjectPath 'Research\Gate13RPR1BOrderEffectPreparationV1.psm1') -Force
$plan=Read-Gate13RPR1BJson $PilotPlanPath
$provenance=Read-Gate13RPR1BJson $ProvenancePath
$audit=Read-Gate13RPR1BJson $PrePilotAuditPath
Assert-Gate13RPR1BPlanIdentity $plan
if($audit.passed-ne$true-or$audit.pilotExecutionAuthorized-ne$true-or$audit.gate13rFormalAuthorized-ne$false){throw 'PR1B validation-only audit did not authorize this non-formal pilot.'}
if([string]$audit.pilotPlanSha256-ne(Get-Gate13RPR1BLowerSha256 $PilotPlanPath)-or[string]$audit.provenanceSha256-ne(Get-Gate13RPR1BLowerSha256 $ProvenancePath)-or[string]$audit.telemetryResultSha256-ne(Get-Gate13RPR1BLowerSha256 $TelemetryResultPath)){throw 'PR1B audit is not byte-bound to the selected inputs.'}

$pilotRoot=[IO.Path]::GetFullPath((Join-Path $ProjectPath ([string]$plan.paths.pilotRootRelativePath).Replace('/','\')))
$pilotBase=[IO.Path]::GetFullPath((Join-Path $ProjectPath 'Research\PilotRuns\Gate12R_ProcessReuse_5pct'))
if(-not$pilotRoot.StartsWith($pilotBase.TrimEnd('\')+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'PR1B pilot root is outside the proven versioned containment base.'}
$formalRoot=[IO.Path]::GetFullPath((Join-Path $ProjectPath ([string]$plan.paths.reservedFormalRootRelativePath).Replace('/','\')))
if(Test-Path -LiteralPath $pilotRoot){throw "Create-new PR1B pilot root already exists: $pilotRoot"}
if(Test-Path -LiteralPath $formalRoot){throw 'Reserved Gate13R formal root must remain absent.'}
if((Get-Gate13RPR1BLowerSha256 $UnityPath)-ne[string]$plan.unity.executableSha256){throw 'Unity executable hash mismatch.'}
foreach($binding in @($provenance.boundFiles)){
    $path=Join-Path $ProjectPath ([string]$binding.relativePath).Replace('/','\')
    if(-not(Test-Path -LiteralPath $path -PathType Leaf)-or(Get-Gate13RPR1BLowerSha256 $path)-ne[string]$binding.sha256){throw "PR1B provenance binding failed: $($binding.relativePath)"}
}

$campaigns=@(Get-Gate13RPR1BCampaigns -ProjectPath $ProjectPath -Plan $plan)
$warmupSchedule=@(Get-Gate13RPR1BProcessSchedule -Plan $plan -Campaigns $campaigns -AnalysisRole 'excluded-warmup')
$measuredSchedule=@(Get-Gate13RPR1BProcessSchedule -Plan $plan -Campaigns $campaigns -AnalysisRole 'measured-non-formal-pilot')
$scheduleCheck=Test-Gate13RPR1BSchedule -Plan $plan -Measured $measuredSchedule -Warmup $warmupSchedule
if($scheduleCheck.passed-ne$true){throw "PR1B schedule failed validation: $($scheduleCheck.errors-join'; ')"}

$runner=Join-Path $ProjectPath 'Research\Run-Gate12RProcessReuseBlockV5.ps1'
$analyzer=Join-Path $ProjectPath 'Research\Analyze-Gate13RPR1BOrderEffectPilotV1.py'
$windowsPowerShell='C:\WINDOWS\System32\WindowsPowerShell\v1.0\powershell.exe'
$nativeModulePath=@('C:\Users\bdscy\Documents\WindowsPowerShell\Modules','C:\Program Files\WindowsPowerShell\Modules','C:\WINDOWS\System32\WindowsPowerShell\v1.0\Modules')-join';'
$pythonCommand=(Get-Command py.exe -ErrorAction Stop).Source

if(-not('Gate13RPR1B.NativePower' -as[type])){Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
namespace Gate13RPR1B {
 [StructLayout(LayoutKind.Sequential)] public struct SystemPowerStatus { public byte ACLineStatus; public byte BatteryFlag; public byte BatteryLifePercent; public byte Reserved1; public int BatteryLifeTime; public int BatteryFullLifeTime; }
 public static class NativePower { [DllImport("kernel32.dll", SetLastError=true)] public static extern bool GetSystemPowerStatus(out SystemPowerStatus status); }
}
'@}

function Get-EnvironmentSnapshot([string]$Phase){
    $processors=@(Get-CimInstance Win32_Processor)
    $os=Get-CimInstance Win32_OperatingSystem
    $cs=Get-CimInstance Win32_ComputerSystem
    $loads=New-Object Collections.Generic.List[double]
    for($i=0;$i-lt[int]$plan.environment.cpuLoadSampleCount;$i++){
        $load=($processors|Measure-Object LoadPercentage -Average).Average
        $loads.Add($(if($null-eq$load){0.0}else{[double]$load}))
        if($i-lt[int]$plan.environment.cpuLoadSampleCount-1){Start-Sleep -Seconds ([int]$plan.environment.cpuLoadSampleIntervalSeconds);$processors=@(Get-CimInstance Win32_Processor)}
    }
    $powerRaw=(&powercfg.exe /getactivescheme 2>&1|Out-String).Trim()
    $match=[regex]::Match($powerRaw,'(?i)[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}')
    $powerStatus=New-Object Gate13RPR1B.SystemPowerStatus
    $powerStatusOk=[Gate13RPR1B.NativePower]::GetSystemPowerStatus([ref]$powerStatus)
    $thermal=@();$thermalError=$null
    try{$thermal=@(Get-CimInstance -Namespace root/wmi -ClassName MSAcpi_ThermalZoneTemperature -ErrorAction Stop|ForEach-Object{[math]::Round(([double]$_.CurrentTemperature/10.0)-273.15,2)})}catch{$thermalError=$_.Exception.Message}
    $drive=New-Object IO.DriveInfo ([IO.Path]::GetPathRoot($pilotRoot))
    $mean=[double](($loads.ToArray()|Measure-Object -Average).Average)
    $free=[long]([double]$os.FreePhysicalMemory*1KB)
    $failed=New-Object Collections.Generic.List[string]
    if(-not$match.Success-or$match.Value.ToLowerInvariant()-ne[string]$plan.environment.requiredPowerSchemeGuid){$failed.Add('power-scheme')}
    if(-not$powerStatusOk-or[int]$powerStatus.ACLineStatus-ne1){$failed.Add('ac-line')}
    if($free-lt[long]$plan.environment.minimumFreePhysicalMemoryBytes){$failed.Add('free-memory')}
    if($mean-gt[double]$plan.environment.maximumMeanCpuLoadPercent){$failed.Add('mean-cpu-load')}
    if($drive.AvailableFreeSpace-lt[long]$plan.environment.minimumPilotDriveFreeBytes){$failed.Add('pilot-storage')}
    if(@(Get-Process -Name Unity -ErrorAction SilentlyContinue).Count-gt0){$failed.Add('unity-process')}
    if(Test-Path -LiteralPath (Join-Path $ProjectPath 'Temp\UnityLockfile')){$failed.Add('unity-lockfile')}
    if(Test-Path -LiteralPath $formalRoot){$failed.Add('formal-root')}
    return [pscustomobject][ordered]@{
        schemaVersion=1;snapshotKind='gate13r-pr1b-environment-power-thermal-storage-preflight-v1';phase=$Phase;capturedAtUtc=[DateTime]::UtcNow.ToString('o')
        machineName=$env:COMPUTERNAME;userName=$env:USERNAME;cpuModels=@($processors|ForEach-Object{([string]$_.Name).Trim()});logicalProcessorCount=[int]$cs.NumberOfLogicalProcessors
        totalPhysicalMemoryBytes=[long]$cs.TotalPhysicalMemory;freePhysicalMemoryBytes=$free;operatingSystem=[string]$os.Caption;powerSchemeRaw=$powerRaw
        powerSchemeGuid=if($match.Success){$match.Value.ToLowerInvariant()}else{$null};systemPowerStatusAvailable=$powerStatusOk;acLineStatus=if($powerStatusOk){[int]$powerStatus.ACLineStatus}else{$null}
        batteryFlag=if($powerStatusOk){[int]$powerStatus.BatteryFlag}else{$null};cpuLoadSamplesPercent=$loads.ToArray();meanCpuLoadPercent=$mean
        thermalTemperaturesCelsius=$thermal;thermalStatus=if($thermal.Count){'available'}else{'unavailable-under-preregistered-policy'};thermalQueryError=$thermalError
        temperatureUnavailablePolicy=[string]$plan.environment.temperatureUnavailablePolicy;outputDriveFreeBytes=[long]$drive.AvailableFreeSpace
        unityProcessIds=@(Get-Process -Name Unity -ErrorAction SilentlyContinue|ForEach-Object Id);unityLockfilePresent=Test-Path -LiteralPath (Join-Path $ProjectPath 'Temp\UnityLockfile')
        formalRootPresent=Test-Path -LiteralPath $formalRoot;failedChecks=$failed.ToArray();passed=$failed.Count-eq0
    }
}

function Invoke-WindowsPowerShellChild([string[]]$Arguments,[string]$Stdout,[string]$Stderr){
    $old=$env:PSModulePath
    try{$env:PSModulePath=$nativeModulePath;&$windowsPowerShell @Arguments 1>$Stdout 2>$Stderr;return [int]$LASTEXITCODE}
    finally{$env:PSModulePath=$old}
}

function Write-Checkpoint([string]$Status,[string]$ErrorMessage){
    $checkpoint=[ordered]@{
        schemaVersion=1;checkpointKind='gate13r-pr1b-order-effect-pilot-checkpoint-v1';status=$Status;savedAtUtc=[DateTime]::UtcNow.ToString('o')
        pilotPlanSha256=Get-Gate13RPR1BLowerSha256 $PilotPlanPath;provenanceSha256=Get-Gate13RPR1BLowerSha256 $ProvenancePath;prePilotAuditSha256=Get-Gate13RPR1BLowerSha256 $PrePilotAuditPath
        completedEntryCount=$script:entries.Count;completedMeasuredProcessCount=@($script:entries|Where-Object role -eq 'measured-non-formal-pilot').Count
        entries=$script:entries.ToArray();error=$ErrorMessage;formalCampaign=$false;excludedFromFormalAnalysis=$true;automaticRetryAuthorized=$false;automaticResumeAuthorized=$false;gate13rFormalAuthorized=$false
    }
    Write-Gate13RPR1BAtomicUtf8NoBomJson -Path (Join-Path $pilotRoot 'pilot-checkpoint.json') -Value $checkpoint -Depth 60
}

function Write-PartialManifest([string]$Status){
    $files=@(Get-ChildItem -LiteralPath $pilotRoot -Recurse -File -Force|Where-Object{$_.Name-notlike'*.tmp-*' -and $_.Name-ne'partial-output-manifest.json'})
    $rows=New-Object Collections.Generic.List[object]
    foreach($file in $files){$rows.Add([pscustomobject][ordered]@{relativePath=Get-Gate13RPR1BProjectRelativePath $ProjectPath $file.FullName;rawBytes=[long]$file.Length;sha256=Get-Gate13RPR1BLowerSha256 $file.FullName})}
    $manifest=[ordered]@{schemaVersion=1;manifestKind='gate13r-pr1b-pilot-partial-output-manifest-v1';status=$Status;savedAtUtc=[DateTime]::UtcNow.ToString('o');fileCount=$rows.Count;rawBytes=[long](($files|Measure-Object Length -Sum).Sum);files=$rows.ToArray();formalCampaign=$false;excludedFromFormalAnalysis=$true}
    Write-Gate13RPR1BAtomicUtf8NoBomJson -Path (Join-Path $pilotRoot 'partial-output-manifest.json') -Value $manifest -Depth 30
}

function Invoke-Block($Item,[int]$ProgressOrdinal){
    $blockPlan=New-Gate13RPR1BBlockPlan -ProjectPath $ProjectPath -Plan $plan -Provenance $provenance -ScheduleItem $Item -ProvenancePath $ProvenancePath -TelemetryProbeResultPath $TelemetryResultPath
    $safeName=('{0:D4}-{1}-b{2:D3}-{3}-p{4}'-f$ProgressOrdinal,[string]$Item.campaign.campaignId,[int]$Item.block,[string]$Item.superblockOrder,[int]$Item.cohortProcessPosition)
    $planFile=Join-Path $pilotRoot ('plans\'+[string]$Item.analysisRole+'\'+$safeName+'.block-plan.json')
    Write-Gate13RPR1BUtf8NoBomJson -Path $planFile -Value $blockPlan -Depth 30
    $output=Join-Path $pilotRoot ([string]$Item.relativeOutput)
    $parent=Split-Path -Parent $output
    if(-not(Test-Path -LiteralPath $parent -PathType Container)){New-Item -ItemType Directory -Path $parent -Force|Out-Null}
    $stdout=$output+'.wrapper.stdout.log';$stderr=$output+'.wrapper.stderr.log'
    $args=@('-NoProfile','-ExecutionPolicy','Bypass','-File',$runner,'-ProjectPath',$ProjectPath,'-BlockPlanPath',$planFile,'-OutputDirectory',$output,'-AllowedRoot',$pilotRoot,'-Mode','Pilot','-UnityPath',$UnityPath)
    $started=Get-Date
    Write-Host("[{0}/{1}] {2} {3} b{4:D3} {5} process {6}"-f$ProgressOrdinal,[int]$plan.totals.pilotBlockProcesses,[string]$Item.analysisRole,[string]$Item.scenarioId,[int]$Item.block,[string]$Item.superblockOrder,[int]$Item.cohortProcessPosition) -ForegroundColor Cyan
    $exit=Invoke-WindowsPowerShellChild $args $stdout $stderr
    $completed=Get-Date
    $summaryPath=$output+'.summary.json'
    if($exit-ne0-or-not(Test-Path -LiteralPath $summaryPath -PathType Leaf)){throw "Block failed without retry/resume: $($blockPlan.blockId) exit=$exit stderr=$stderr"}
    $wrapper=Read-Gate13RPR1BJson $summaryPath
    if($wrapper.passed-ne$true){throw "Block wrapper did not pass: $($blockPlan.blockId)"}
    $manifestPath=Join-Path $output 'block-manifest.json'
    $manifest=Read-Gate13RPR1BJson $manifestPath
    return [pscustomobject][ordered]@{
        role=[string]$Item.analysisRole;ordinal=$ProgressOrdinal;wave=[int]$Item.wave;scenarioWaveSlot=[int]$Item.scenarioWaveSlot;scenarioId=[string]$Item.scenarioId;block=[int]$Item.block
        mirroredPairId=[string]$Item.mirroredPairId;firstSuperblockOrder=[string]$Item.firstSuperblockOrder;superblockOrder=[string]$Item.superblockOrder
        superblockSequencePosition=[int]$Item.superblockSequencePosition;cohortProcessPosition=[int]$Item.cohortProcessPosition;pairProcessPosition=[int]$Item.pairProcessPosition
        campaignId=[string]$Item.campaign.campaignId;comparisonCohortId=[string]$Item.campaign.comparisonCohortId;scenarioSha256=[string]$Item.campaign.scenarioSha256
        blockId=[string]$blockPlan.blockId;planRelativePath=Get-Gate13RPR1BProjectRelativePath $ProjectPath $planFile;planSha256=Get-Gate13RPR1BLowerSha256 $planFile
        outputRelativePath=Get-Gate13RPR1BProjectRelativePath $ProjectPath $output;wrapperSummaryRelativePath=Get-Gate13RPR1BProjectRelativePath $ProjectPath $summaryPath
        wrapperSummarySha256=Get-Gate13RPR1BLowerSha256 $summaryPath;blockManifestSha256=Get-Gate13RPR1BLowerSha256 $manifestPath;processId=[int]$manifest.processId
        sampleCount=[int]$manifest.completedSampleCount;wallSeconds=($completed-$started).TotalSeconds;rawBytes=Get-Gate13RPR1BRawBytes $output;formalCampaign=$false;completed=$true
    }
}

$startEnvironment=Get-EnvironmentSnapshot 'launch-preflight-before-pilot-root'
if(-not$startEnvironment.passed){throw "PR1B launch preflight failed before root creation: $($startEnvironment.failedChecks-join', ')"}
New-Item -ItemType Directory -Path $pilotRoot|Out-Null
New-Item -ItemType Directory -Path (Join-Path $pilotRoot 'plans')|Out-Null
$script:entries=New-Object Collections.Generic.List[object]
$pilotStarted=Get-Date
try{
    Write-Gate13RPR1BUtf8NoBomJson -Path (Join-Path $pilotRoot 'environment-start.json') -Value $startEnvironment -Depth 20
    $receipt=[ordered]@{
        schemaVersion=1;receiptKind='gate13r-pr1b-non-formal-order-effect-pilot-execution-receipt-v1';createdAtUtc=[DateTime]::UtcNow.ToString('o');pilotRoot=$pilotRoot
        pilotPlanSha256=Get-Gate13RPR1BLowerSha256 $PilotPlanPath;provenanceSha256=Get-Gate13RPR1BLowerSha256 $ProvenancePath;prePilotAuditSha256=Get-Gate13RPR1BLowerSha256 $PrePilotAuditPath
        telemetryResultSha256=Get-Gate13RPR1BLowerSha256 $TelemetryResultPath;executionDesignId=[string]$plan.executionDesignId;nonFormal=$true;excludedFromFormalAnalysis=$true
        automaticRetryAuthorized=$false;automaticResumeAuthorized=$false;partialAttemptMergeAuthorized=$false;optionalStoppingAuthorized=$false;gate13rFormalAuthorized=$false
    }
    Write-Gate13RPR1BAtomicUtf8NoBomJson -Path (Join-Path $pilotRoot 'execution-receipt.json') -Value $receipt -Depth 20
    Write-Checkpoint 'preflight-passed' $null
    $progress=0
    foreach($item in $warmupSchedule){$progress++;$script:entries.Add((Invoke-Block $item $progress));Write-Checkpoint 'running-excluded-warmup' $null}
    Start-Sleep -Seconds ([int]$plan.warmup.quietStabilizationSeconds)
    $postWarmup=Get-EnvironmentSnapshot 'post-warmup-after-quiet-stabilization'
    Write-Gate13RPR1BUtf8NoBomJson -Path (Join-Path $pilotRoot 'environment-post-warmup.json') -Value $postWarmup -Depth 20
    if(-not$postWarmup.passed){throw "Post-warmup preflight failed: $($postWarmup.failedChecks-join', ')"}
    foreach($item in $measuredSchedule){$progress++;$script:entries.Add((Invoke-Block $item $progress));Write-Checkpoint 'running-measured-mirrored-pairs' $null}
    $endEnvironment=Get-EnvironmentSnapshot 'end-after-measured-mirrored-pairs'
    Write-Gate13RPR1BUtf8NoBomJson -Path (Join-Path $pilotRoot 'environment-end.json') -Value $endEnvironment -Depth 20
    $warmCount=@($script:entries|Where-Object role -eq 'excluded-warmup').Count
    $measuredCount=@($script:entries|Where-Object role -eq 'measured-non-formal-pilot').Count
    $measuredSamples=[int](($script:entries|Where-Object role -eq 'measured-non-formal-pilot'|Measure-Object sampleCount -Sum).Sum)
    if($warmCount-ne12-or$measuredCount-ne384-or$measuredSamples-ne768-or$script:entries.Count-ne396){throw 'PR1B cardinality mismatch before analysis.'}
    $execution=[ordered]@{
        schemaVersion=1;manifestKind='gate13r-pr1b-order-effect-pilot-execution-manifest-v1';startedAtUtc=$pilotStarted.ToUniversalTime().ToString('o');completedAtUtc=[DateTime]::UtcNow.ToString('o')
        pilotPlanSha256=Get-Gate13RPR1BLowerSha256 $PilotPlanPath;provenanceSha256=Get-Gate13RPR1BLowerSha256 $ProvenancePath
        warmupBlockProcessCount=$warmCount;warmupSampleCount=[int](($script:entries|Where-Object role -eq 'excluded-warmup'|Measure-Object sampleCount -Sum).Sum)
        measuredMirroredPairCount=96;measuredMatchedSuperblockCount=192;measuredBlockProcessCount=$measuredCount;measuredSampleCount=$measuredSamples
        totalBlockProcessCount=$script:entries.Count;totalSampleCount=[int](($script:entries|Measure-Object sampleCount -Sum).Sum);entries=$script:entries.ToArray()
        formalCampaign=$false;excludedFromFormalAnalysis=$true;automaticRetryCount=0;automaticResumeCount=0;gate13rFormalAuthorized=$false;completed=$true
    }
    Write-Gate13RPR1BAtomicUtf8NoBomJson -Path (Join-Path $pilotRoot 'pilot-execution-manifest.json') -Value $execution -Depth 60
    Write-Checkpoint 'execution-complete-analysis-pending' $null
    $analysisStdout=Join-Path $pilotRoot 'analysis.stdout.log';$analysisStderr=Join-Path $pilotRoot 'analysis.stderr.log'
    &$pythonCommand -3 $analyzer --project $ProjectPath --pilot-root $pilotRoot --plan $PilotPlanPath --provenance $ProvenancePath 1>$analysisStdout 2>$analysisStderr
    if([int]$LASTEXITCODE-ne0){throw "PR1B analysis failed without retry/resume: exit=$LASTEXITCODE stderr=$analysisStderr"}
    $verificationStdout=Join-Path $pilotRoot 'analysis-deterministic-verification.stdout.log';$verificationStderr=Join-Path $pilotRoot 'analysis-deterministic-verification.stderr.log'
    &$pythonCommand -3 $analyzer --project $ProjectPath --pilot-root $pilotRoot --plan $PilotPlanPath --provenance $ProvenancePath --verify-existing 1>$verificationStdout 2>$verificationStderr
    if([int]$LASTEXITCODE-ne0){throw "PR1B deterministic analysis verification failed: exit=$LASTEXITCODE stderr=$verificationStderr"}
    $pilotManifest=Read-Gate13RPR1BJson (Join-Path $pilotRoot 'pilot-manifest.json')
    if($pilotManifest.completed-ne$true-or$pilotManifest.gate13rFormalAuthorized-ne$false-or$pilotManifest.excludedFromFormalAnalysis-ne$true){throw 'PR1B pilot manifest boundary/completion mismatch.'}
    Write-Checkpoint 'PILOT-COMPLETE-FINAL-AUDIT-PENDING' $null
    Write-PartialManifest 'complete-before-final-audit'
    [pscustomobject]@{passed=$true;pilotRoot=$pilotRoot;pilotManifestSha256=Get-Gate13RPR1BLowerSha256 (Join-Path $pilotRoot 'pilot-manifest.json');measuredMirroredPairs=96;measuredBlockProcesses=384;measuredSamples=768;recommendation=[string]$pilotManifest.recommendation;formalCampaign=$false;gate13rFormalAuthorized=$false}|ConvertTo-Json -Depth 10
    exit 0
}catch{
    $message=$_.Exception.ToString()
    try{
        $failure=[ordered]@{schemaVersion=1;receiptKind='gate13r-pr1b-pilot-failure-receipt-v1';failedAtUtc=[DateTime]::UtcNow.ToString('o');message=$message;completedEntryCount=$script:entries.Count;measuredProcessStarted=@($script:entries|Where-Object role -eq 'measured-non-formal-pilot').Count-gt0;status='FAILED-NO-RETRY-NO-RESUME-NO-MERGE';formalCampaign=$false;excludedFromFormalAnalysis=$true;automaticRetryAuthorized=$false;automaticResumeAuthorized=$false;partialAttemptMergeAuthorized=$false;gate13rFormalAuthorized=$false}
        Write-Gate13RPR1BAtomicUtf8NoBomJson -Path (Join-Path $pilotRoot 'failure-receipt.json') -Value $failure -Depth 20
        Write-Checkpoint 'failed-no-retry-no-resume-no-merge' $message
        Write-PartialManifest 'failed-no-retry-no-resume-no-merge'
    }catch{}
    Write-Error "Gate13R PR1B pilot failed closed: $message"
    exit 1
}
