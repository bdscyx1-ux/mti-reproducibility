[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$ProjectPath,
    [Parameter(Mandatory=$true)][string]$VerificationRoot,
    [switch]$BindingSmokeOnly
)

$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$ProjectPath=[IO.Path]::GetFullPath($ProjectPath)
$VerificationRoot=[IO.Path]::GetFullPath($VerificationRoot)
$expectedRoot=[IO.Path]::GetFullPath((Join-Path $ProjectPath 'Research\Verification\Gate13R_36h_10pct_4Lane\v12'))
if($VerificationRoot-ne$expectedRoot){throw 'Validation-only audit root differs from the frozen verification root.'}
if($BindingSmokeOnly){Write-Output("BINDING-SMOKE-PASSED|Run-Gate13R36hValidationOnlyPrePilotAuditV12|$ProjectPath");exit 0}
if(-not(Test-Path -LiteralPath $VerificationRoot -PathType Container)){throw 'Verification root is missing.'}
$summaryPath=Join-Path $VerificationRoot 'ValidationOnlyPrePilotAudit.summary.json'
if(Test-Path -LiteralPath $summaryPath){throw 'Create-new validation-only audit summary already exists.'}

Import-Module (Join-Path $ProjectPath 'Research\Gate13R36hConcurrencyPreparationV12.psm1') -Force
$planPath=Join-Path $ProjectPath 'Research\Gate13R_36h_10pct_4Lane_Pilot_Plan.v12.json'
$schedulePath=Join-Path $ProjectPath 'Research\Gate13R_36h_10pct_4Lane_Pilot_Schedule.v12.json'
$provenancePath=Join-Path $ProjectPath 'Research\Gate13R_36h_10pct_4Lane_Provenance.v12.json'
$baselinePath=Join-Path $ProjectPath 'Research\Gate13R_36h_10pct_4Lane_PreWrite_Preservation_Baseline.v1.json'
$plan=Read-G13R36Json $planPath
$provenance=Read-G13R36Json $provenancePath
$assertions=New-Object Collections.Generic.List[object]
$failures=New-Object Collections.Generic.List[string]
$powerRaw='';$freePhysical=0L;$sourceDrive=[pscustomobject]@{AvailableFreeSpace=0L};$cloneDrive=[pscustomobject]@{AvailableFreeSpace=0L};$batteries=@();$acPassed=$false;$cpuSamples=New-Object Collections.Generic.List[double];$meanCpu=[double]::NaN;$temperatures=@();$unityProcesses=@();$locks=New-Object Collections.Generic.List[string]
function Add-Assertion([string]$Name,[bool]$Passed,[string]$Detail){$script:assertions.Add([pscustomobject][ordered]@{name=$Name;passed=$Passed;detail=$Detail});if(-not$Passed){$script:failures.Add("$Name`: $Detail")}}
function Read-IfPresent([string]$Path){if(Test-Path -LiteralPath $Path -PathType Leaf){return (Read-G13R36Json $Path)};return $null}

try{
    $preservation=Test-G13R36PreservationBaseline -ProjectPath $ProjectPath -BaselinePath $baselinePath
    Add-Assertion 'protected-input-preservation' ([bool]$preservation.passed) "Protected files checked: $($preservation.checkedFileCount)."
    Add-Assertion 'plan-provenance-boundary' ([string]$plan.executionDesignId-eq[string]$provenance.executionDesignId-and$plan.formalCampaign-eq$false-and$provenance.formalCampaign-eq$false-and$provenance.formalExecutionAuthorized-eq$false) 'Plan/provenance must bind the same non-formal design.'
    foreach($property in $provenance.PSObject.Properties){$value=$property.Value;if($value-is[pscustomobject]-and$value.PSObject.Properties.Name-contains'relativePath'-and$value.PSObject.Properties.Name-contains'sha256'){$path=Join-Path $ProjectPath ([string]$value.relativePath).Replace('/','\');$ok=(Test-Path -LiteralPath $path -PathType Leaf)-and(Get-G13R36LowerSha256 $path)-eq[string]$value.sha256;Add-Assertion ('provenance-'+$property.Name) $ok ([string]$value.relativePath)}}

    $compilePath=Join-Path $ProjectPath 'Research\Verification\Gate13R_36h_10pct_4Lane_PreImplementation\v6\Compile\summary.json'
    $compile=Read-IfPresent $compilePath
    Add-Assertion 'source-unity-compile' ($null-ne$compile-and$compile.passed-eq$true-and[int]$compile.exitCode-eq0-and[int]$compile.compilerErrorMatchCount-eq0-and[string]$compile.commandSha256-eq[string]$plan.upstreamHashes.unityCommand) 'Source-project Unity compilation is missing, failed, or bound to another command.'
    $staticPath=Join-Path $VerificationRoot 'StaticUnit\summary.json';$static=Read-IfPresent $staticPath
    Add-Assertion 'static-unit' ($null-ne$static-and$static.passed-eq$true-and[int]$static.failedAssertionCount-eq0) 'Static/unit evidence is missing or failed.'
    $lockUnitPath=Join-Path $VerificationRoot 'LockHygieneUnit\summary.json';$lockUnit=Read-IfPresent $lockUnitPath
    Add-Assertion 'expected-negative-lock-hygiene-unit' ($null-ne$lockUnit-and$lockUnit.passed-eq$true-and[int]$lockUnit.failedAssertionCount-eq0-and[string]$lockUnit.cleanupResult.mode-eq'controlled-expected-negative-cleanup') 'Lock-hygiene unit evidence is missing, failed, or did not exercise controlled expected-negative cleanup.'
    $copySummaryPath=Join-Path $VerificationRoot 'LaneCopies\summary.json';$copySummary=Read-IfPresent $copySummaryPath
    $copyPassed=$null-ne$copySummary-and$copySummary.passed-eq$true-and[int]$copySummary.laneCount-eq4
    if($copyPassed){foreach($record in @($copySummary.laneManifests)){$manifest=Read-IfPresent ([string]$record.path);if($null-eq$manifest-or$manifest.passed-ne$true-or[int]$manifest.reparsePointCount-ne0-or[int]$manifest.hardLinkedScientificFileCount-ne0){$copyPassed=$false}}}
    Add-Assertion 'four-isolated-project-copies' $copyPassed 'All four scientific trees must be hash-identical normal copies with no reparse points or hard links.'

    $telemetryPassed=$true;$telemetryPids=New-Object Collections.Generic.List[int]
    foreach($lane in 1..4){$laneRoot=('H:\DDM_Final_Project_Gate13R36H\v12\lane-{0:D2}'-f$lane);$resultPath=Join-Path $laneRoot 'Research\Verification\Gate13R_36h_10pct_4Lane\v12\TelemetryProbe\telemetry-probe-result.json';$wrapperPath=(Join-Path $laneRoot 'Research\Verification\Gate13R_36h_10pct_4Lane\v12\TelemetryProbe')+'.summary.json';$result=Read-IfPresent $resultPath;$wrapper=Read-IfPresent $wrapperPath;if($null-eq$result-or$null-eq$wrapper-or$result.passed-ne$true-or$wrapper.passed-ne$true-or[long]$result.nativeBefore.workingSetBytes-le0-or[long]$result.nativeBefore.privateMemoryBytes-le0-or[long]$result.externalQuery.workingSetBytes-le0-or[long]$result.externalQuery.privateMemoryBytes-le0){$telemetryPassed=$false}else{$telemetryPids.Add([int]$wrapper.unityProcessId)};$laneProvenance=Join-Path $laneRoot 'Research\Gate13R_36h_10pct_4Lane_Provenance.v12.json';if(-not(Test-Path -LiteralPath $laneProvenance)-or(Get-G13R36LowerSha256 $laneProvenance)-ne(Get-G13R36LowerSha256 $provenancePath)){$telemetryPassed=$false}}
    Add-Assertion 'four-lane-telemetry' ($telemetryPassed-and@($telemetryPids|Sort-Object -Unique).Count-eq4) 'Each lane requires its own positive PSAPI/CIM result and unique Unity PID.'
    $blockPath=Join-Path $VerificationRoot 'BlockVerification\summary.json';$block=Read-IfPresent $blockPath
    Add-Assertion 'block-verification' ($null-ne$block-and$block.passed-eq$true-and[int]$block.concurrentPositiveBlockCount-eq4-and[int]$block.structuralMismatchCount-eq0-and$block.negativeFailClosedPassed-eq$true-and$block.independentProcessRepeatabilityPassed-eq$true-and$block.uniqueUnityProcessPassed-eq$true) 'Concurrent positive, negative fail-closed, cold structural, or repeatability verification failed.'
    $retainedPath=Join-Path $VerificationRoot 'RetainedRegression\Gate12_AnalysisUnitTests.summary.json';$retained=Read-IfPresent $retainedPath
    Add-Assertion 'retained-regression-63' ($null-ne$retained-and$retained.passed-eq$true-and[int]$retained.assertionCount-eq63) 'Retained regression is not 63/63.'

    $pilotRoot=Join-Path $ProjectPath 'Research\PilotRuns\Gate13R_36h_10pct_4Lane\v12'
    Add-Assertion 'pilot-root-absent' (-not(Test-Path -LiteralPath $pilotRoot)) 'Validation-only work must not create the sole pilot root.'
    foreach($formal in @('Research\FormalRuns\Gate13R_ProcessReuse_5pct\v1','Research\FormalRuns\Gate13R_36h_10pct_4Lane\v1')){Add-Assertion ('formal-root-absent-'+([IO.Path]::GetFileName((Split-Path $formal -Parent)))) (-not(Test-Path -LiteralPath (Join-Path $ProjectPath $formal))) "Forbidden formal root: $formal"}

    $unityProcesses=@(Get-Process -Name Unity -ErrorAction SilentlyContinue);$locks=New-Object Collections.Generic.List[string]
    foreach($root in @($ProjectPath)+@(1..4|ForEach-Object{'H:\DDM_Final_Project_Gate13R36H\v12\lane-{0:D2}'-f$_})){if(Test-Path -LiteralPath (Join-Path $root 'Temp\UnityLockfile')){$locks.Add($root)}}
    Add-Assertion 'unity-quiescence' ($unityProcesses.Count-eq0-and$locks.Count-eq0) "Unity processes=$($unityProcesses.Count), locks=$($locks.Count)."
    $powerRaw=(&powercfg.exe /GETACTIVESCHEME 2>&1|Out-String).Trim();$powerOk=$powerRaw.ToLowerInvariant().Contains(([string]$plan.environment.requiredPowerSchemeGuid).ToLowerInvariant())
    Add-Assertion 'power-scheme' $powerOk $powerRaw
    $os=Get-CimInstance Win32_OperatingSystem;$freePhysical=[long]$os.FreePhysicalMemory*1024L
    Add-Assertion 'free-physical-memory' ($freePhysical-ge[long]$plan.environment.minimumFreePhysicalMemoryBytes) "Free bytes: $freePhysical"
    $sourceDrive=New-Object IO.DriveInfo -ArgumentList @([IO.Path]::GetPathRoot($ProjectPath));$cloneDrive=New-Object IO.DriveInfo -ArgumentList @([IO.Path]::GetPathRoot('H:\DDM_Final_Project_Gate13R36H\v1'))
    Add-Assertion 'source-storage' ($sourceDrive.AvailableFreeSpace-ge[long]$plan.environment.minimumSourceDriveFreeBytes) "Free bytes: $($sourceDrive.AvailableFreeSpace)"
    Add-Assertion 'clone-storage' ($cloneDrive.AvailableFreeSpace-ge[long]$plan.environment.minimumCloneDriveFreeBytes) "Free bytes: $($cloneDrive.AvailableFreeSpace)"
    $batteries=@(Get-CimInstance Win32_Battery -ErrorAction SilentlyContinue);$acPassed=$true;foreach($battery in $batteries){if([int]$battery.BatteryStatus-in@(1,4,5)){$acPassed=$false}}
    Add-Assertion 'ac-power' $acPassed $(if($batteries.Count-eq0){'Desktop/no battery device; mains assumed.'}else{'All batteries must not report discharging.'})
    $cpuSamples=New-Object Collections.Generic.List[double];for($i=0;$i-lt[int]$plan.environment.cpuLoadSampleCount;$i++){$values=@(Get-CimInstance Win32_Processor|ForEach-Object{[double]$_.LoadPercentage});$cpuSamples.Add([double](($values|Measure-Object -Average).Average));if($i-lt[int]$plan.environment.cpuLoadSampleCount-1){Start-Sleep -Seconds ([int]$plan.environment.cpuLoadSampleIntervalSeconds)}};$meanCpu=[double](($cpuSamples|Measure-Object -Average).Average)
    Add-Assertion 'cpu-load' ($meanCpu-le[double]$plan.environment.maximumMeanCpuLoadPercent) "Mean CPU load: $meanCpu%."
    $temperatures=@();try{$temperatures=@(Get-CimInstance -Namespace root/wmi -ClassName MSAcpi_ThermalZoneTemperature -ErrorAction Stop|ForEach-Object{([double]$_.CurrentTemperature/10.0)-273.15})}catch{$temperatures=@()}
    Add-Assertion 'thermal-policy' ($temperatures.Count-ge0-and[string]$plan.environment.temperatureUnavailablePolicy-eq'record-unavailable-controlled-warmup-balanced-order-v1') $(if($temperatures.Count){'Celsius: '+($temperatures-join', ')}else{'Unavailable; frozen unavailable policy applies.'})
}catch{$failures.Add($_.Exception.ToString())}

$passed=$failures.Count-eq0-and@($assertions|Where-Object{-not$_.passed}).Count-eq0
$summary=[ordered]@{schemaVersion=1;summaryKind='gate13r-36h-four-lane-validation-only-pre-pilot-audit-v12';completedAtUtc=[DateTime]::UtcNow.ToString('o');projectPath=$ProjectPath;verificationRoot=$VerificationRoot;assertionCount=$assertions.Count;passedAssertionCount=@($assertions|Where-Object passed).Count;failedAssertionCount=@($assertions|Where-Object{-not$_.passed}).Count;assertions=$assertions.ToArray();failures=$failures.ToArray();environment=[ordered]@{powerSchemeRaw=$powerRaw;freePhysicalMemoryBytes=$freePhysical;sourceDriveFreeBytes=[long]$sourceDrive.AvailableFreeSpace;cloneDriveFreeBytes=[long]$cloneDrive.AvailableFreeSpace;batteryCount=$batteries.Count;acPassed=$acPassed;cpuLoadSamplesPercent=$cpuSamples.ToArray();meanCpuLoadPercent=$meanCpu;temperatureCelsius=$temperatures;temperaturePolicy=[string]$plan.environment.temperatureUnavailablePolicy;unityProcessCount=$unityProcesses.Count;lockCount=$locks.Count};pilotPlanSha256=Get-G13R36LowerSha256 $planPath;scheduleSha256=Get-G13R36LowerSha256 $schedulePath;provenanceSha256=Get-G13R36LowerSha256 $provenancePath;staticSummarySha256=if(Test-Path $staticPath){Get-G13R36LowerSha256 $staticPath}else{$null};lockHygieneUnitSummarySha256=if(Test-Path $lockUnitPath){Get-G13R36LowerSha256 $lockUnitPath}else{$null};compileSummarySha256=if(Test-Path $compilePath){Get-G13R36LowerSha256 $compilePath}else{$null};copySummarySha256=if(Test-Path $copySummaryPath){Get-G13R36LowerSha256 $copySummaryPath}else{$null};blockVerificationSummarySha256=if(Test-Path $blockPath){Get-G13R36LowerSha256 $blockPath}else{$null};retainedRegressionSummarySha256=if(Test-Path $retainedPath){Get-G13R36LowerSha256 $retainedPath}else{$null};pilotRootCreated=Test-Path -LiteralPath $pilotRoot;pilotExecutionAuthorizedByAudit=$passed;authorizedPilotExecutionCount=if($passed){1}else{0};formalCampaign=$false;formalExecutionAuthorized=$false;formalRootCreated=$false;automaticRetryAuthorized=$false;automaticResumeAuthorized=$false;passed=$passed}
Write-G13R36AtomicUtf8NoBomJson -Path $summaryPath -Value $summary -Depth 60
if(-not$passed){Write-Error("Gate13R 36h validation-only pre-pilot audit failed: "+($failures-join'; '));exit 1}
Write-Host("Gate13R 36h validation-only pre-pilot audit passed: {0}/{0}. Exactly one non-formal pilot is permitted; formal campaign remains unauthorized."-f$assertions.Count)-ForegroundColor Green
exit 0
