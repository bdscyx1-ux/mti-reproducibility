[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$ProjectPath,
    [Parameter(Mandatory=$true)][string]$VerificationRoot,
    [Parameter(Mandatory=$true)][string]$PilotPlanPath,
    [Parameter(Mandatory=$true)][string]$ProvenancePath,
    [Parameter(Mandatory=$true)][string]$TelemetryResultPath,
    [switch]$BindingSmokeOnly
)

$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
if([string]::IsNullOrWhiteSpace($ProjectPath)-or-not[IO.Path]::IsPathRooted($ProjectPath)){throw 'Gate12R pre-pilot audit requires an explicit absolute ProjectPath.'}
$ProjectPath=[IO.Path]::GetFullPath($ProjectPath)
if($BindingSmokeOnly){Write-Output("BINDING-SMOKE-PASSED|Run-Gate12RValidationOnlyPrePilotAudit|$ProjectPath");exit 0}
$VerificationRoot=[IO.Path]::GetFullPath($VerificationRoot);$PilotPlanPath=[IO.Path]::GetFullPath($PilotPlanPath);$ProvenancePath=[IO.Path]::GetFullPath($ProvenancePath);$TelemetryResultPath=[IO.Path]::GetFullPath($TelemetryResultPath)
Import-Module (Join-Path $ProjectPath 'Research\Gate12RProcessReusePreparationV2.psm1') -Force
$plan=Read-Gate12RJson $PilotPlanPath;$provenance=Read-Gate12RJson $ProvenancePath
$base=[IO.Path]::GetFullPath((Join-Path $ProjectPath 'Research\Verification\Gate12R_ProcessReuse_5pct'))
if(-not$VerificationRoot.StartsWith($base.TrimEnd('\')+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'VerificationRoot is outside Gate12R versioned base.'}
$summaryPath=Join-Path $VerificationRoot 'ValidationOnlyPrePilotAudit.summary.json';if(Test-Path $summaryPath){throw "Create-new pre-pilot audit exists: $summaryPath"}
$failures=New-Object Collections.Generic.List[string];$checks=New-Object Collections.Generic.List[object]
function Check([string]$Id,[bool]$Passed,[string]$Evidence){$checks.Add([pscustomobject]@{id=$Id;passed=$Passed;evidence=$Evidence});if(-not$Passed){$failures.Add("$Id`: $Evidence")}}
if(-not('Gate12R.AuditNativePower' -as[type])){Add-Type -TypeDefinition @'
using System; using System.Runtime.InteropServices; namespace Gate12R { [StructLayout(LayoutKind.Sequential)] public struct AuditPowerStatus { public byte ACLineStatus; public byte BatteryFlag; public byte BatteryLifePercent; public byte Reserved1; public int BatteryLifeTime; public int BatteryFullLifeTime; } public static class AuditNativePower { [DllImport("kernel32.dll", SetLastError=true)] public static extern bool GetSystemPowerStatus(out AuditPowerStatus status); } }
'@}

try{
    Check 'plan-hash' ((Get-Gate12RLowerSha256 $PilotPlanPath)-eq'dfce191b62e2ea4ad266c86fb0aec0cd981a79fbe21d2affa7777491709631e3') 'frozen Gate12R plan bytes'
    Check 'bundle-hash' ((Get-Gate12RLowerSha256 (Join-Path $ProjectPath ([string]$plan.paths.gate11BundleManifestRelativePath).Replace('/','\')))-eq'5baaeec18344a9e99e55da38f3c4875b7e7e9f3bf0add9d5f2d2f1e821b5f7fc') 'authorized Gate11R bundle bytes'
    foreach($binding in @($provenance.boundFiles)){$path=Join-Path $ProjectPath ([string]$binding.relativePath).Replace('/','\');Check ('binding-'+[string]$binding.id) ((Test-Path $path)-and(Get-Gate12RLowerSha256 $path)-eq[string]$binding.sha256) ([string]$binding.relativePath)}
    $static=Read-Gate12RJson (Join-Path $VerificationRoot 'StaticUnit\summary.json');Check 'static-unit' ($static.passed-eq$true-and[int]$static.failureCount-eq0) ("assertions=$($static.assertionCount)")
    $playable=Read-Gate12RJson (Join-Path $VerificationRoot 'StaticUnit\playable-mapping-validation.json');Check 'playable-mapping' ($playable.passed-eq$true-and[int]$playable.campaignCount-eq12-and$playable.formalTimingEvidenceAllowed-eq$false) '12 pilot campaigns mapped to visualization-only assets'
    $compile=Read-Gate12RJson (Join-Path $VerificationRoot 'Compile\summary.json');Check 'unity-compile' ($compile.passed-eq$true-and[int]$compile.exitCode-eq0-and[int]$compile.compilerErrorMatchCount-eq0) ([string]$compile.logSha256)
    $telemetry=Read-Gate12RJson $TelemetryResultPath;Check 'psapi-cim-telemetry' ($telemetry.passed-eq$true-and$telemetry.workingSetPassed-eq$true-and$telemetry.privateMemoryPassed-eq$true-and$telemetry.pidPassed-eq$true-and$telemetry.creationTimePassed-eq$true) (Get-Gate12RLowerSha256 $TelemetryResultPath)
    $block=Read-Gate12RJson (Join-Path $VerificationRoot 'BlockAndRegression\summary.json');Check 'positive-negative-repeatability-cold' ($block.passed-eq$true-and[int]$block.positiveBlockCount-eq5-and[int]$block.negativeBlockCount-eq1-and[int]$block.coldControlCount-eq8-and[int]$block.structuralComparisonCount-eq12) ("entries=$($block.entryCount)")
    $retained=Read-Gate12RJson (Join-Path $VerificationRoot 'BlockAndRegression\RetainedRegression\wrapper.json');Check 'retained-regression' ($retained.passed-eq$true-and[int]$retained.assertionCount-eq63-and[int]$retained.failureCount-eq0) '63/63 file-scope regression'
    $pilotRoot=Join-Path $ProjectPath ([string]$plan.paths.pilotRootRelativePath).Replace('/','\');$formalRoot=Join-Path $ProjectPath ([string]$plan.paths.reservedFormalRootRelativePath).Replace('/','\');Check 'pilot-root-absent' (-not(Test-Path $pilotRoot)) $pilotRoot;Check 'formal-root-absent' (-not(Test-Path $formalRoot)) $formalRoot;Check 'unity-closed' (@(Get-Process -Name Unity -ErrorAction SilentlyContinue).Count-eq0) 'no Unity processes';Check 'lock-absent' (-not(Test-Path (Join-Path $ProjectPath 'Temp\UnityLockfile'))) 'project lock absent'
    $powerRaw=(&powercfg.exe /getactivescheme 2>&1|Out-String).Trim();$match=[regex]::Match($powerRaw,'(?i)[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}');Check 'power-scheme' ($match.Success-and$match.Value.ToLowerInvariant()-eq[string]$plan.environment.requiredPowerSchemeGuid) $powerRaw
    $status=New-Object Gate12R.AuditPowerStatus;$statusOk=[Gate12R.AuditNativePower]::GetSystemPowerStatus([ref]$status);Check 'ac-online' ($statusOk-and[int]$status.ACLineStatus-eq1) ("statusAvailable=$statusOk ac=$([int]$status.ACLineStatus)")
    $os=Get-CimInstance Win32_OperatingSystem;$freeMemory=[long]([double]$os.FreePhysicalMemory*1KB);Check 'free-memory' ($freeMemory-ge[long]$plan.environment.minimumFreePhysicalMemoryBytes) ("freeBytes=$freeMemory")
    $loads=New-Object Collections.Generic.List[double];for($i=0;$i-lt[int]$plan.environment.cpuLoadSampleCount;$i++){$processors=@(Get-CimInstance Win32_Processor);$load=($processors|Measure-Object LoadPercentage -Average).Average;$loads.Add($(if($null-eq$load){0}else{[double]$load}));if($i-lt[int]$plan.environment.cpuLoadSampleCount-1){Start-Sleep -Seconds ([int]$plan.environment.cpuLoadSampleIntervalSeconds)}};$meanCpu=[double](($loads|Measure-Object -Average).Average);Check 'mean-cpu-load' ($meanCpu-le[double]$plan.environment.maximumMeanCpuLoadPercent) ("mean=$meanCpu samples=$($loads-join',')")
    $drive=New-Object IO.DriveInfo ([IO.Path]::GetPathRoot($pilotRoot));Check 'pilot-storage-minimum' ($drive.AvailableFreeSpace-ge[long]$plan.environment.minimumPilotDriveFreeBytes) ("freeBytes=$($drive.AvailableFreeSpace)")
    $thermal=@();$thermalError=$null;try{$thermal=@(Get-CimInstance -Namespace root/wmi -ClassName MSAcpi_ThermalZoneTemperature -ErrorAction Stop|ForEach-Object {[math]::Round(([double]$_.CurrentTemperature/10)-273.15,2)})}catch{$thermalError=$_.Exception.Message};Check 'thermal-policy' ($thermal.Count-gt0-or[string]$plan.environment.temperatureUnavailablePolicy-eq'record-unavailable-controlled-warmup-balanced-order-v1') $(if($thermal.Count){$thermal-join','}else{"unavailable: $thermalError"})
    Check 'precision-policy' ($null-eq$plan.precision.hardCap-and[double]$plan.precision.relativeHalfWidth-eq0.05-and[int]$plan.precision.minimumBlocks-eq32-and[int]$plan.precision.cycleMultiple-eq4) '5% minimum-32 multiple-4 no-cap'
    Check 'non-formal-boundary' ($plan.formalCampaign-eq$false-and$plan.gate13rAuthorized-eq$false) 'Gate13R remains unauthorized'
}catch{$failures.Add($_.Exception.ToString())}
$summary=[ordered]@{schemaVersion=1;summaryKind='gate12r-validation-only-pre-pilot-audit-v5-plan-v6-module-v2';auditMode='validation-only-no-pilot-root';savedAtUtc=[DateTime]::UtcNow.ToString('o');pilotPlanSha256=Get-Gate12RLowerSha256 $PilotPlanPath;provenanceSha256=Get-Gate12RLowerSha256 $ProvenancePath;telemetryResultSha256=Get-Gate12RLowerSha256 $TelemetryResultPath;checkCount=$checks.Count;checks=$checks.ToArray();failureCount=$failures.Count;failures=$failures.ToArray();pilotExecutionAuthorizedByAudit=$failures.Count-eq0;formalCampaign=$false;gate13rAuthorized=$false;passed=$failures.Count-eq0}
Write-Gate12RAtomicUtf8NoBomJson -Path $summaryPath -Value $summary -Depth 40
if($failures.Count){Write-Error("Gate12R validation-only pre-pilot audit failed: "+($failures-join'; '));exit 1}
Write-Host "Gate12R validation-only pre-pilot audit passed $($checks.Count) checks." -ForegroundColor Green
exit 0
