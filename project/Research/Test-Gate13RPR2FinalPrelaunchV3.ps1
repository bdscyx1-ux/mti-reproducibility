[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$ProjectPath,
    [Parameter(Mandatory = $true)][string]$OutputPath
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$ProjectPath = [IO.Path]::GetFullPath($ProjectPath).TrimEnd('\', '/')
$OutputPath = [IO.Path]::GetFullPath($OutputPath)
if (Test-Path -LiteralPath $OutputPath) { throw "Create-new final-prelaunch output exists: $OutputPath" }
Import-Module (Join-Path $ProjectPath 'Research\Gate13RPR2FormalExecutionV3.psm1') -Force

$checks = New-Object Collections.Generic.List[object]
function Add-Check([string]$Name, [bool]$Passed, [object]$Detail) {
    $script:checks.Add([ordered]@{ name = $Name; passed = $Passed; detail = $Detail })
}
function Get-StringSha256([string]$Text) {
    $bytes = [Text.Encoding]::UTF8.GetBytes($Text)
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-', '').ToLowerInvariant() }
    finally { $sha.Dispose() }
}
function Get-TreeIdentity([string]$Path) {
    $root = [IO.Path]::GetFullPath($Path).TrimEnd('\', '/')
    $rows = New-Object Collections.Generic.List[string]
    $bytes = [long]0
    $count = 0
    foreach ($file in @(Get-ChildItem -LiteralPath $root -File -Recurse -Force)) {
        $relative = $file.FullName.Substring($root.Length + 1).Replace('\', '/')
        $hash = Get-G13RPR2Sha256 $file.FullName
        $rows.Add("$relative`t$([long]$file.Length)`t$hash")
        $bytes += [long]$file.Length
        $count++
    }
    $rows.Sort([StringComparer]::Ordinal)
    return [ordered]@{
        resolvedAbsolutePath = $root.Replace('\', '/')
        fileCount = $count
        rawBytes = $bytes
        canonicalTreeSha256 = Get-StringSha256 ($rows.ToArray() -join "`n")
    }
}
function Get-PowerSettingIndex([string]$Subgroup, [string]$Setting) {
    $raw = (& powercfg.exe /query SCHEME_CURRENT $Subgroup $Setting 2>&1 | Out-String).Trim()
    $matches = [regex]::Matches($raw, '(?i)0x([0-9a-f]+)')
    # powercfg emits minimum, maximum, increment, AC, and DC hexadecimal values.
    # Selecting the penultimate value is independent of the localized label text.
    $value = if ($matches.Count -ge 2) { [Convert]::ToInt64($matches[$matches.Count - 2].Groups[1].Value, 16) } else { $null }
    return [ordered]@{ raw = $raw; hexadecimalValueCount = $matches.Count; acIndex = $value; parsed = $null -ne $value }
}

$expectedNativeModulePath = @(
    'C:\Users\bdscy\Documents\WindowsPowerShell\Modules',
    'C:\Program Files\WindowsPowerShell\Modules',
    'C:\WINDOWS\System32\WindowsPowerShell\v1.0\Modules'
) -join ';'
$formalRoot = Join-Path $ProjectPath 'Research\FormalRuns\Gate13R_RQAligned_S48H48\v1'
$formalReceipt = Join-Path $ProjectPath 'Research\Gate13R_PR2_Formal_Execution_Receipt.v1.json'
$formalStatus = Join-Path $ProjectPath 'Research\Gate13R_PR2_Formal_Execution_Status.v1.json'
$prewritePath = Join-Path $ProjectPath 'Research\Gate13R_PR2_PreWrite_Preservation_Audit.v2.json'
$prewrite = Read-G13RPR2Json $prewritePath

$treeAudit = New-Object Collections.Generic.List[object]
foreach ($expected in @($prewrite.frozenTrees)) {
    $actual = Get-TreeIdentity (Join-Path $ProjectPath ([string]$expected.relativePath).Replace('/', '\'))
    $passed = [int]$actual.fileCount -eq [int]$expected.fileCount -and [long]$actual.rawBytes -eq [long]$expected.rawBytes -and [string]$actual.canonicalTreeSha256 -eq [string]$expected.canonicalTreeSha256
    $treeAudit.Add([ordered]@{
        relativePath = [string]$expected.relativePath
        expected = [ordered]@{ fileCount = [int]$expected.fileCount; rawBytes = [long]$expected.rawBytes; canonicalTreeSha256 = [string]$expected.canonicalTreeSha256 }
        actual = $actual
        passed = $passed
    })
}
Add-Check 'frozen-upstream-trees-byte-identical' (@($treeAudit | Where-Object { $_.passed -ne $true }).Count -eq 0) "trees=$($treeAudit.Count)"

$keyFileAudit = New-Object Collections.Generic.List[object]
foreach ($expected in @($prewrite.keyFiles)) {
    $path = Join-Path $ProjectPath ([string]$expected.relativePath).Replace('/', '\')
    $actual = if (Test-Path -LiteralPath $path -PathType Leaf) { Get-G13RPR2Sha256 $path } else { $null }
    $keyFileAudit.Add([ordered]@{ relativePath = [string]$expected.relativePath; expectedSha256 = [string]$expected.sha256; actualSha256 = $actual; passed = $actual -eq [string]$expected.sha256 })
}
Add-Check 'frozen-upstream-key-files-byte-identical' (@($keyFileAudit | Where-Object { $_.passed -ne $true }).Count -eq 0) "files=$($keyFileAudit.Count)"

$activeHashes = [ordered]@{
    readiness = [ordered]@{ relativePath = 'Research/Gate13R_PR2_NonExecuting_Readiness_Checkpoint.v1.json'; expected = '669a5291ab2e219461ca9797696ba29bce32e198c11a983f0f1f31f3f7799fbc' }
    config = [ordered]@{ relativePath = 'Research/Gate13R_PR2_Formal_Campaign_Config.v2.json'; expected = '87d7012af4e8e5b5e16cb64b50f41f1dcb5b1eebf5d7eba1425b29e0fa13dd5e' }
    schedule = [ordered]@{ relativePath = 'Research/Gate13R_PR2_Formal_Williams_Matched_Schedule.v2.jsonl'; expected = 'df8802c34ef033dd2eb906f6a70e8c8fc594bdc0a386a48afe6c756789075dae' }
    scheduleManifest = [ordered]@{ relativePath = 'Research/Gate13R_PR2_Formal_Williams_Matched_Schedule_Manifest.v2.json'; expected = 'b5763f1540c0193199201cd6bf025c43443d5bd2e67cb8808e0a2b86ef91b724' }
    storagePreflight = [ordered]@{ relativePath = 'Research/Gate13R_PR2_Storage_WallClock_Preflight.v2.json'; expected = 'c474499e647d5ad32efe01d199ede187b61f004e9487b8278e44109258cd0435' }
    preparationProvenance = [ordered]@{ relativePath = 'Research/Gate13R_PR2_Formal_Preparation_Provenance.v2.json'; expected = '9e81530bcf6d32dd1792c8bd693d72988bef6f37e59a1ad154019ca228908e56' }
    preparationSchema = [ordered]@{ relativePath = 'Research/Gate13R_PR2_Formal_Preparation_Schema.v2.json'; expected = '940bfca8cb3e677deadff2600471eeaec9e99ff6bab9a06a625a0f30365a9d1e' }
    twoPhaseAmendment = [ordered]@{ relativePath = 'Research/Gate13R_PR2_RawAnalysis_TwoPhaseCommit_Amendment.v1.json'; expected = '805200a362440918682317f3ecf4fdb35fa441a1459457700a0f5f2a43a113df' }
    twoPhaseSpecification = [ordered]@{ relativePath = 'Research/Gate13R_PR2_RawAnalysis_TwoPhaseCommit_Specification.v1.md'; expected = '1641c22ddcb788f46ee1b2956f3bf8c8e13312459b5c22b139396001823085a5' }
    formalAuthorization = [ordered]@{ relativePath = 'Research/Gate13R_PR2_Formal_Execution_Authorization.v2.json'; expected = 'b39323958710c4962cf868ae3ba6057f42649e8f23fb7f5feb04ffd12c438759' }
    supplementalAuthorization = [ordered]@{ relativePath = 'Research/Gate13R_PR2_TwoPhaseCommit_Supplemental_Authorization.v1.txt'; expected = '4af69eb71362f89698d38760db335985a015af49f176dd7f81805cb6d2d4821a' }
    command = [ordered]@{ relativePath = 'Assets/_Scripts/Research/Editor/Gate13RPR2FormalBatchCommandV2.cs'; expected = 'af9156588bc259dfa8cafeec4adb82c93a2b07f5e2ae772b4b0fd4115dce28a8' }
    module = [ordered]@{ relativePath = 'Research/Gate13RPR2FormalExecutionV3.psm1'; expected = '5eaf15a3f1891d17849cf5c417aabaa03bcac7d25771e83ab905060b2db74b74' }
    blockWrapper = [ordered]@{ relativePath = 'Research/Run-Gate13RPR2FormalBlockV4.ps1'; expected = '30bf36239aaf321a4d454bf71f777a668476b1b962021d30ec3bb4d6abe25f54' }
    orchestrator = [ordered]@{ relativePath = 'Research/Run-Gate13RPR2FormalCampaignV4.ps1'; expected = '66821f7642a260a80a5ea30f3e45a4e93e4dbc0c78095a3bcf2800d86bf65b53' }
}
$activeHashAudit = New-Object Collections.Generic.List[object]
foreach ($property in $activeHashes.GetEnumerator()) {
    $path = Join-Path $ProjectPath ([string]$property.Value.relativePath).Replace('/', '\')
    $actual = if (Test-Path -LiteralPath $path -PathType Leaf) { Get-G13RPR2Sha256 $path } else { $null }
    $activeHashAudit.Add([ordered]@{ logicalName = [string]$property.Key; relativePath = [string]$property.Value.relativePath; expectedSha256 = [string]$property.Value.expected; actualSha256 = $actual; passed = $actual -eq [string]$property.Value.expected })
}
Add-Check 'active-frozen-input-hashes' (@($activeHashAudit | Where-Object { $_.passed -ne $true }).Count -eq 0) "files=$($activeHashAudit.Count)"

$unitSummaryPath = Join-Path $ProjectPath 'Research\Verification\Gate13R_PR2_Formal_Prelaunch\v1\AdapterUnitV5\summary.json'
$staticSummaryPath = Join-Path $ProjectPath 'Research\Verification\Gate13R_PR2_Formal_Prelaunch\v1\adapter-static-schedule-summary.v6.json'
$negativeSummaryPath = Join-Path $ProjectPath 'Research\Verification\Gate13R_PR2_Formal_Prelaunch\v1\NegativeNoReceiptV1\negative-no-receipt-summary.json'
$selfTestSummaryPath = Join-Path $ProjectPath 'Research\Verification\Gate13R_PR2_Formal_Prelaunch\v1\UnitySelfTestsV3\unity-self-tests-summary.json'
$telemetrySummaryPath = Join-Path $ProjectPath 'Research\Verification\Gate13R_PR2_Formal_Prelaunch\v1\TelemetryProbeV3\Probe.summary.json'
$unitSummary = Read-G13RPR2Json $unitSummaryPath
$staticSummary = Read-G13RPR2Json $staticSummaryPath
$negativeSummary = Read-G13RPR2Json $negativeSummaryPath
$selfTestSummary = Read-G13RPR2Json $selfTestSummaryPath
$telemetrySummary = Read-G13RPR2Json $telemetrySummaryPath
Add-Check 'unit-and-two-phase-fixtures-pass' ($unitSummary.passed -eq $true -and [int]$unitSummary.passedCheckCount -eq 35) '35/35'
Add-Check 'active-static-deterministic-audit-pass' ($staticSummary.passed -eq $true -and [int]$staticSummary.passedCheckCount -eq 54) '54/54'
Add-Check 'negative-no-receipt-fail-closed-pass' ($negativeSummary.passed -eq $true -and $negativeSummary.noFormalSampleCreated -eq $true) 'formal root absent and Unity not launched'
Add-Check 'unity-compile-memory-atomic-self-tests-pass' ($selfTestSummary.passed -eq $true) (Get-G13RPR2Sha256 $selfTestSummaryPath)
Add-Check 'telemetry-psapi-cim-license-probe-pass' ($telemetrySummary.passed -eq $true -and $telemetrySummary.licenseSerialAssigned -eq $true) (Get-G13RPR2Sha256 $telemetrySummaryPath)

$telemetryLogPath = Join-Path $ProjectPath 'Research\Verification\Gate13R_PR2_Formal_Prelaunch\v1\TelemetryProbeV3\Probe.Unity.log'
$telemetryLog = Read-G13RPR2TextWithRetry -Path $telemetryLogPath -TimeoutMilliseconds 30000
$licensePassed = $telemetryLog.Contains('Successfully resolved entitlements') -and $telemetryLog.Contains('Serial number assigned to:') -and -not $telemetryLog.Contains('No valid Unity Editor license found') -and -not $telemetryLog.Contains('LICENSE SYSTEM [ERROR]')
Add-Check 'fresh-unity-license-entitlement-evidence' $licensePassed (Get-G13RPR2Sha256 $telemetryLogPath)

if (-not ('Gate13RPR2NativeMethods' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class Gate13RPR2NativeMethods {
  [StructLayout(LayoutKind.Sequential)] public struct SystemPowerStatus { public byte ACLineStatus; public byte BatteryFlag; public byte BatteryLifePercent; public byte Reserved1; public int BatteryLifeTime; public int BatteryFullLifeTime; }
  [DllImport("kernel32.dll")] public static extern bool GetSystemPowerStatus(out SystemPowerStatus status);
}
'@
}
$powerStatus = New-Object Gate13RPR2NativeMethods+SystemPowerStatus
$powerStatusAvailable = [Gate13RPR2NativeMethods]::GetSystemPowerStatus([ref]$powerStatus)
$powerRaw = (& powercfg.exe /getactivescheme 2>&1 | Out-String).Trim()
$powerMatch = [regex]::Match($powerRaw, '(?i)[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}')
$standby = Get-PowerSettingIndex 'SUB_SLEEP' 'STANDBYIDLE'
$hibernate = Get-PowerSettingIndex 'SUB_SLEEP' 'HIBERNATEIDLE'
$availableSleepStates = (& powercfg.exe /availablesleepstates 2>&1 | Out-String).Trim()
$hibernateEnabledRegistry = $null
try { $hibernateEnabledRegistry = [int](Get-ItemPropertyValue -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Control\Power' -Name 'HibernateEnabled' -ErrorAction Stop) }
catch { $hibernateEnabledRegistry = $null }
$hibernateUnavailable = $null -ne $hibernateEnabledRegistry -and $hibernateEnabledRegistry -eq 0
Add-Check 'high-performance-power-scheme' ($powerMatch.Success -and $powerMatch.Value.ToLowerInvariant() -eq '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c') $powerRaw
Add-Check 'ac-online' ($powerStatusAvailable -and [int]$powerStatus.ACLineStatus -eq 1) "available=$powerStatusAvailable; ac=$([int]$powerStatus.ACLineStatus)"
Add-Check 'sleep-disabled-on-ac' ($standby.parsed -and [long]$standby.acIndex -eq 0) "acIndex=$($standby.acIndex)"
Add-Check 'hibernate-disabled-on-ac' ($hibernate.parsed -and [long]$hibernate.acIndex -eq 0 -and $hibernateUnavailable) "acIndex=$($hibernate.acIndex); registryEnabled=$hibernateEnabledRegistry"

$processors = @(Get-CimInstance Win32_Processor)
$loads = New-Object Collections.Generic.List[double]
for ($index = 0; $index -lt 5; $index++) {
    $load = ($processors | Measure-Object LoadPercentage -Average).Average
    $loads.Add($(if ($null -eq $load) { 0.0 } else { [double]$load }))
    if ($index -lt 4) { Start-Sleep -Seconds 1; $processors = @(Get-CimInstance Win32_Processor) }
}
$meanCpuLoad = [double](($loads.ToArray() | Measure-Object -Average).Average)
$os = Get-CimInstance Win32_OperatingSystem
$computer = Get-CimInstance Win32_ComputerSystem
$freePhysicalMemoryBytes = [long]([double]$os.FreePhysicalMemory * 1KB)
$temperatures = @()
$temperatureError = $null
try { $temperatures = @(Get-CimInstance -Namespace root/wmi -ClassName MSAcpi_ThermalZoneTemperature -ErrorAction Stop | ForEach-Object { [math]::Round(([double]$_.CurrentTemperature / 10.0) - 273.15, 2) }) }
catch { $temperatureError = $_.Exception.Message }
Add-Check 'free-physical-memory-at-least-4gib' ($freePhysicalMemoryBytes -ge 4294967296L) $freePhysicalMemoryBytes
Add-Check 'quiet-mean-cpu-load-at-most-50pct' ($meanCpuLoad -le 50.0) $meanCpuLoad
Add-Check 'thermal-policy-observed' ($temperatures.Count -gt 0 -or -not [string]::IsNullOrWhiteSpace($temperatureError)) ($(if ($temperatures.Count -gt 0) { $temperatures } else { 'unavailable-under-preregistered-policy' }))

$network = Test-NetConnection -ComputerName 'packages.unity.cn' -Port 443 -InformationLevel Detailed -WarningAction SilentlyContinue
Add-Check 'unity-network-tcp443-reachable' ([bool]$network.TcpTestSucceeded) "remote=$($network.RemoteAddress); port=443"
$drive = New-Object IO.DriveInfo 'H:'
$availableFreeBytes = [long]$drive.AvailableFreeSpace
$projectedP95RawBytes = 9631912320L
$projectedSafetyBytes = 14447868480L
$reserveBytes = 42949672960L
$minimumLaunchFreeBytes = 57397541440L
Add-Check 'raw-byte-budget-arithmetic' ($projectedSafetyBytes -eq [long][math]::Ceiling(1.5 * $projectedP95RawBytes) -and $minimumLaunchFreeBytes -eq $projectedSafetyBytes + $reserveBytes) "minimum=$minimumLaunchFreeBytes"
Add-Check 'h-drive-free-space' ($availableFreeBytes -ge $minimumLaunchFreeBytes) "available=$availableFreeBytes; minimum=$minimumLaunchFreeBytes"

$unityProcesses = @(Get-Process -Name Unity -ErrorAction SilentlyContinue)
$lockExists = Test-Path -LiteralPath (Join-Path $ProjectPath 'Temp\UnityLockfile')
Add-Check 'zero-unity-processes' ($unityProcesses.Count -eq 0) "count=$($unityProcesses.Count)"
Add-Check 'unity-project-lock-absent' (-not $lockExists) "present=$lockExists"
Add-Check 'native-windows-powershell-5.1' ($PSVersionTable.PSVersion.Major -eq 5 -and $PSVersionTable.PSEdition -eq 'Desktop') "$($PSVersionTable.PSVersion)|$($PSVersionTable.PSEdition)"
Add-Check 'native-psmodulepath-exact' ([string]$env:PSModulePath -eq $expectedNativeModulePath) ([string]$env:PSModulePath)
Add-Check 'formal-root-absent-before-authorization-commit' (-not (Test-Path -LiteralPath $formalRoot)) $formalRoot
Add-Check 'formal-receipt-absent-before-authorization-commit' (-not (Test-Path -LiteralPath $formalReceipt)) $formalReceipt
Add-Check 'formal-status-absent-before-authorization-commit' (-not (Test-Path -LiteralPath $formalStatus)) $formalStatus

$failedChecks = @($checks | Where-Object { $_.passed -ne $true })
$summary = [ordered]@{
    schemaVersion = 1
    auditKind = 'gate13r-pr2-s48-h48-formal-final-prelaunch-environment-storage-preservation-audit-v1'
    observedAtUtc = [DateTime]::UtcNow.ToString('o')
    observedAtLocal = [DateTimeOffset]::Now.ToString('o')
    timeZone = 'Asia/Shanghai'
    projectPath = $ProjectPath.Replace('\', '/')
    formalRootResolved = $formalRoot.Replace('\', '/')
    checks = $checks.ToArray()
    checkCount = $checks.Count
    passedCheckCount = $checks.Count - $failedChecks.Count
    failedCheckCount = $failedChecks.Count
    failedCheckNames = @($failedChecks.name)
    frozenTreeAudit = $treeAudit.ToArray()
    frozenKeyFileAudit = $keyFileAudit.ToArray()
    activeHashAudit = $activeHashAudit.ToArray()
    environment = [ordered]@{
        computerName = $env:COMPUTERNAME
        userName = $env:USERNAME
        operatingSystem = [string]$os.Caption
        operatingSystemVersion = [string]$os.Version
        cpuModels = @($processors | ForEach-Object { ([string]$_.Name).Trim() })
        logicalProcessorCount = [int]$computer.NumberOfLogicalProcessors
        totalPhysicalMemoryBytes = [long]$computer.TotalPhysicalMemory
        freePhysicalMemoryBytes = $freePhysicalMemoryBytes
        cpuLoadSamplesPercent = $loads.ToArray()
        meanCpuLoadPercent = $meanCpuLoad
        powerSchemeRaw = $powerRaw
        powerSchemeGuid = if ($powerMatch.Success) { $powerMatch.Value.ToLowerInvariant() } else { $null }
        systemPowerStatusAvailable = $powerStatusAvailable
        acLineStatus = if ($powerStatusAvailable) { [int]$powerStatus.ACLineStatus } else { $null }
        batteryFlag = if ($powerStatusAvailable) { [int]$powerStatus.BatteryFlag } else { $null }
        sleepAcSeconds = $standby.acIndex
        hibernateAcSeconds = $hibernate.acIndex
        hibernateEnabledRegistry = $hibernateEnabledRegistry
        hibernateUnavailable = $hibernateUnavailable
        availableSleepStatesRaw = $availableSleepStates
        thermalTemperaturesCelsius = $temperatures
        thermalStatus = if ($temperatures.Count -gt 0) { 'available' } else { 'unavailable-under-preregistered-policy' }
        thermalQueryError = $temperatureError
        networkHost = 'packages.unity.cn'
        networkPort = 443
        networkRemoteAddress = [string]$network.RemoteAddress
        networkTcpSucceeded = [bool]$network.TcpTestSucceeded
        powerShellVersion = [string]$PSVersionTable.PSVersion
        powerShellEdition = [string]$PSVersionTable.PSEdition
        psModulePath = [string]$env:PSModulePath
    }
    storage = [ordered]@{
        drive = 'H:'
        availableFreeBytes = $availableFreeBytes
        projectedP95RawBytes = $projectedP95RawBytes
        projectedSafetyBytes = $projectedSafetyBytes
        reserveBytes = $reserveBytes
        minimumLaunchFreeBytes = $minimumLaunchFreeBytes
        passed = $availableFreeBytes -ge $minimumLaunchFreeBytes
    }
    licenseEvidence = [ordered]@{
        telemetrySummaryRelativePath = Get-G13RPR2ProjectRelativePath -ProjectPath $ProjectPath -Path $telemetrySummaryPath
        telemetrySummarySha256 = Get-G13RPR2Sha256 $telemetrySummaryPath
        telemetryUnityLogRelativePath = Get-G13RPR2ProjectRelativePath -ProjectPath $ProjectPath -Path $telemetryLogPath
        telemetryUnityLogSha256 = Get-G13RPR2Sha256 $telemetryLogPath
        serialAssigned = $telemetrySummary.licenseSerialAssigned
        entitlementResolutionObserved = $telemetryLog.Contains('Successfully resolved entitlements')
        passed = $licensePassed
    }
    formalRootAbsent = -not (Test-Path -LiteralPath $formalRoot)
    formalExecutionReceiptAbsent = -not (Test-Path -LiteralPath $formalReceipt)
    formalStatusAbsent = -not (Test-Path -LiteralPath $formalStatus)
    unityEditorProcessCount = $unityProcesses.Count
    unityLockExists = $lockExists
    passed = $failedChecks.Count -eq 0
}
Write-G13RPR2AtomicJson -Path $OutputPath -Value $summary -Depth 40
if ($failedChecks.Count -ne 0) { throw ('Final prelaunch audit failed: ' + (@($failedChecks.name) -join ', ')) }
Write-Host "Gate13R-PR2 final prelaunch preservation/environment audit passed: $($checks.Count)/$($checks.Count)." -ForegroundColor Green
