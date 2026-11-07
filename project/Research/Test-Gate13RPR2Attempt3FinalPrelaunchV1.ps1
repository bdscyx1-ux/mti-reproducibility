[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$ProjectPath,
    [Parameter(Mandatory = $true)][string]$OutputPath,
    [string]$PythonPath = 'C:\Users\bdscy\AppData\Local\Python\bin\python.exe'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0
$ProjectPath = [IO.Path]::GetFullPath($ProjectPath).TrimEnd('\', '/')
$OutputPath = [IO.Path]::GetFullPath($OutputPath)
$PythonPath = [IO.Path]::GetFullPath($PythonPath)
if (Test-Path -LiteralPath $OutputPath) { throw "Create-new final-prelaunch output exists: $OutputPath" }

$checks = New-Object Collections.Generic.List[object]
function Add-Check([string]$Name, [bool]$Passed, [object]$Detail) {
    $script:checks.Add([ordered]@{ name = $Name; passed = $Passed; detail = $Detail })
}
function Get-Sha256([string]$Path) {
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}
function Get-StringSha256([string]$Text) {
    $algorithm = [Security.Cryptography.SHA256]::Create()
    try {
        $bytes = (New-Object Text.UTF8Encoding($false)).GetBytes($Text)
        return ([BitConverter]::ToString($algorithm.ComputeHash($bytes))).Replace('-', '').ToLowerInvariant()
    } finally { $algorithm.Dispose() }
}
function Read-Json([string]$Path) {
    return (Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json)
}
function Write-AtomicJson([string]$Path, [object]$Value) {
    $parent = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $parent -PathType Container)) { throw "Atomic parent is missing: $parent" }
    $temporary = Join-Path $parent ('.g13tmp-' + [Guid]::NewGuid().ToString('N'))
    try {
        [IO.File]::WriteAllText($temporary, (($Value | ConvertTo-Json -Depth 60) + "`n"), (New-Object Text.UTF8Encoding($false)))
        if (Test-Path -LiteralPath $Path) { throw "Create-new target exists: $Path" }
        [IO.File]::Move($temporary, $Path)
    } finally {
        if (Test-Path -LiteralPath $temporary -PathType Leaf) { Remove-Item -LiteralPath $temporary -Force }
    }
}
function Get-TreeIdentity([string]$Path) {
    $root = [IO.Path]::GetFullPath($Path).TrimEnd('\', '/')
    $files = @(Get-ChildItem -LiteralPath $root -File -Recurse -Force)
    $rows = New-Object 'string[]' $files.Count
    [long]$bytes = 0
    [int]$readOnly = 0
    for ($index = 0; $index -lt $files.Count; $index++) {
        $file = $files[$index]
        $relative = $file.FullName.Substring($root.Length + 1).Replace('\', '/')
        $hash = Get-Sha256 $file.FullName
        $rows[$index] = $relative + [char]0 + ([long]$file.Length).ToString([Globalization.CultureInfo]::InvariantCulture) + [char]0 + $hash + "`n"
        $bytes += [long]$file.Length
        if ($file.IsReadOnly) { $readOnly++ }
    }
    # Reproduce the already-frozen pre-write identity byte-for-byte.  Its
    # recorded label says ordinal, while the original Windows PowerShell
    # capture used Sort-Object; the stored digest is therefore the authority.
    $rows = @($rows | Sort-Object)
    return [ordered]@{
        resolvedAbsolutePath = $root.Replace('\', '/')
        fileCount = $files.Count
        rawBytes = $bytes
        readOnlyFileCount = $readOnly
        canonicalInventorySha256 = Get-StringSha256 (-join $rows)
    }
}
function Get-PowerSettingIndex([string]$Subgroup, [string]$Setting) {
    $raw = (& powercfg.exe /query SCHEME_CURRENT $Subgroup $Setting 2>&1 | Out-String).Trim()
    $matches = [regex]::Matches($raw, '(?i)0x([0-9a-f]+)')
    $value = if ($matches.Count -ge 2) { [Convert]::ToInt64($matches[$matches.Count - 2].Groups[1].Value, 16) } else { $null }
    return [ordered]@{ raw = $raw; acIndex = $value; parsed = $null -ne $value }
}
function Test-PowerShellParser([string]$Path) {
    $tokens = $null
    $errors = $null
    [void][Management.Automation.Language.Parser]::ParseFile($Path, [ref]$tokens, [ref]$errors)
    return [ordered]@{ path = $Path; errorCount = @($errors).Count; errors = @($errors | ForEach-Object { $_.Message }); passed = @($errors).Count -eq 0 }
}

$expectedPsModulePath = @(
    'C:\Users\bdscy\Documents\WindowsPowerShell\Modules',
    'C:\Program Files\WindowsPowerShell\Modules',
    'C:\WINDOWS\System32\WindowsPowerShell\v1.0\Modules'
) -join ';'
$formalRoot = Join-Path $ProjectPath 'Research\FormalRuns\Gate13R_RQAligned_S48H48\v3'
$formalReceipt = Join-Path $ProjectPath 'Research\Gate13R_PR2_Formal_Execution_Receipt.v3.json'
$formalStatus = Join-Path $ProjectPath 'Research\Gate13R_PR2_Formal_Execution_Status.v3.json'
$monitoringRoot = Join-Path $ProjectPath 'Research\Monitoring\Gate13R_PR2_Attempt3\v1'
$prewritePath = Join-Path $ProjectPath 'Research\Gate13R_PR2_Attempt3_Execution_PreWrite_Preservation_Audit.v1.json'
$prewrite = Read-Json $prewritePath

# Historical attempts 1 and 2 must be byte-identical to the pre-write audit.
$historicalTreeAudit = New-Object Collections.Generic.List[object]
foreach ($expected in @($prewrite.historicalFormalRoots)) {
    $historicalRootPath = ([string]$expected.root).Replace('/', '\')
    $actual = Get-TreeIdentity $historicalRootPath
    $passed = [int]$actual.fileCount -eq [int]$expected.fileCount -and
        [long]$actual.rawBytes -eq [long]$expected.rawBytes -and
        [int]$actual.readOnlyFileCount -eq [int]$expected.readOnlyFileCount -and
        [string]$actual.canonicalInventorySha256 -eq [string]$expected.canonicalInventorySha256
    $historicalTreeAudit.Add([ordered]@{ formalAttemptOrdinal = [int]$expected.formalAttemptOrdinal; expected = $expected; actual = $actual; passed = $passed })
}
Add-Check 'historical-formal-roots-byte-identical-and-read-only' (@($historicalTreeAudit | Where-Object { $_.passed -ne $true }).Count -eq 0) $historicalTreeAudit.ToArray()

$keyFileAudit = New-Object Collections.Generic.List[object]
foreach ($property in @($prewrite.frozenKeyFiles.PSObject.Properties)) {
    $expected = $property.Value
    $path = Join-Path $ProjectPath ([string]$expected.relativePath).Replace('/', '\')
    $actual = if (Test-Path -LiteralPath $path -PathType Leaf) { Get-Sha256 $path } else { $null }
    $keyFileAudit.Add([ordered]@{ logicalName = $property.Name; relativePath = [string]$expected.relativePath; expectedSha256 = [string]$expected.sha256; actualSha256 = $actual; passed = $actual -eq [string]$expected.sha256 })
}
Add-Check 'frozen-key-files-byte-identical' (@($keyFileAudit | Where-Object { $_.passed -ne $true }).Count -eq 0) "files=$($keyFileAudit.Count)"

# Parser, binding, current-runtime, and implementation provenance gates.
$parserPaths = @(
    (Join-Path $ProjectPath 'Research\Run-Gate13RPR2FormalAttempt3V2.ps1'),
    (Join-Path $ProjectPath 'Research\Run-Gate13RPR2MP2FormalBlockV3.ps1'),
    (Join-Path $ProjectPath 'Research\Verification\Run-Gate13RPR2MP2MemoryPolicySelfTestV1.ps1'),
    (Join-Path $ProjectPath 'Research\Verification\Run-Gate13RPR2MP2TelemetryProbeV1.ps1'),
    $PSCommandPath
)
$parserAudit = @($parserPaths | ForEach-Object { Test-PowerShellParser $_ })
Add-Check 'native-powershell-parser-pass' (@($parserAudit | Where-Object { $_.passed -ne $true }).Count -eq 0) $parserAudit

$bindingOutputs = New-Object Collections.Generic.List[string]
$bindingPassed = $true
foreach ($entry in @(
    [pscustomobject]@{ Script = 'Research\Run-Gate13RPR2FormalAttempt3V2.ps1'; Parameters = @{ ProjectPath = $ProjectPath; BindingSmokeOnly = $true } },
    [pscustomobject]@{ Script = 'Research\Run-Gate13RPR2MP2FormalBlockV3.ps1'; Parameters = @{ ProjectPath = $ProjectPath; Mode = 'ValidationOnly'; BindingSmokeOnly = $true } },
    [pscustomobject]@{ Script = 'Research\Verification\Run-Gate13RPR2MP2MemoryPolicySelfTestV1.ps1'; Parameters = @{ ProjectPath = $ProjectPath; AttemptRoot = (Split-Path -Parent $OutputPath); BindingSmokeOnly = $true } },
    [pscustomobject]@{ Script = 'Research\Verification\Run-Gate13RPR2MP2TelemetryProbeV1.ps1'; Parameters = @{ ProjectPath = $ProjectPath; OutputDirectory = (Join-Path (Split-Path -Parent $OutputPath) 'binding-unused'); AllowedRoot = (Split-Path -Parent $OutputPath); BindingSmokeOnly = $true } }
)) {
    try {
        $scriptPath = Join-Path $ProjectPath ([string]$entry.Script)
        $parameters = $entry.Parameters
        $text = (& $scriptPath @parameters 2>&1 | Out-String).Trim()
        $bindingOutputs.Add($text)
        if (-not $text.Contains('BINDING-SMOKE-PASSED')) { $bindingPassed = $false }
    } catch { $bindingPassed = $false; $bindingOutputs.Add($_.Exception.Message) }
}
Add-Check 'parameter-binding-smoke-pass' $bindingPassed $bindingOutputs.ToArray()

$pyCompileOutput = (& $PythonPath -m py_compile (Join-Path $ProjectPath 'Research\Gate13RPR2Attempt3ExecutionV1.py') (Join-Path $ProjectPath 'Research\Test-Gate13RPR2FormalAttempt3PrelaunchV1.py') 2>&1 | Out-String).Trim()
Add-Check 'python-parser-pass' ($LASTEXITCODE -eq 0) $pyCompileOutput

$provenancePath = Join-Path $ProjectPath 'Research\Gate13R_PR2_Attempt3_Formal_Execution_Adapter_Provenance.v2.json'
$provenance = Read-Json $provenancePath
$implementationAudit = New-Object Collections.Generic.List[object]
foreach ($property in @($provenance.implementation.PSObject.Properties)) {
    $binding = $property.Value
    $path = Join-Path $ProjectPath ([string]$binding.relativePath).Replace('/', '\')
    $actual = if (Test-Path -LiteralPath $path -PathType Leaf) { Get-Sha256 $path } else { $null }
    $implementationAudit.Add([ordered]@{ logicalName = $property.Name; relativePath = [string]$binding.relativePath; expectedSha256 = [string]$binding.sha256; actualSha256 = $actual; passed = $actual -eq [string]$binding.sha256 })
}
Add-Check 'execution-implementation-provenance-hashes' (@($implementationAudit | Where-Object { $_.passed -ne $true }).Count -eq 0) $implementationAudit.ToArray()

# Static/unit/synthetic, schedule, monitor, no-launch, fresh Unity, and fail-closed validation evidence.
$evidence = [ordered]@{
    staticFinal = 'Research/Verification/Gate13R_PR2_Attempt3_FormalExecution/v1/attempt-3-prelaunch-repair-cycle3/static-unit-synthetic-v2/summary.json'
    mp2Static = 'Research/Verification/Gate13R_PR2_Attempt3_FormalExecution/v1/attempt-1/mp2-static-unit-determinism-summary.json'
    monitoring = 'Research/Verification/Gate13R_PR2_Attempt3_FormalExecution/v1/attempt-1/monitoring-56/validation-summary.json'
    launcherPS5 = 'Research/Verification/Gate13R_PR2_Attempt3_FormalExecution/v1/attempt-3-prelaunch-repair-cycle3/launcher-v2-validate-ps5.json'
    launcherPS7 = 'Research/Verification/Gate13R_PR2_Attempt3_FormalExecution/v1/attempt-3-prelaunch-repair-cycle3/launcher-v2-validate-ps7.json'
    dryPS5First = 'Research/Verification/Gate13R_PR2_Attempt3_FormalExecution/v1/attempt-3-prelaunch-repair-cycle3/launcher-v2-dry-ps5-p000001.json'
    dryPS5Last = 'Research/Verification/Gate13R_PR2_Attempt3_FormalExecution/v1/attempt-3-prelaunch-repair-cycle3/launcher-v2-dry-ps5-p003552.json'
    dryPS7Mid = 'Research/Verification/Gate13R_PR2_Attempt3_FormalExecution/v1/attempt-3-prelaunch-repair-cycle3/launcher-v2-dry-ps7-p002000.json'
    launcherArgumentCapture = 'Research/Verification/Gate13R_PR2_Attempt3_FormalExecution/v1/attempt-3-prelaunch-repair-cycle3/targeted-launcher-validation.json'
    memorySelfTest = 'Research/Verification/Gate13R_PR2_MP2/attempt3-formal-prelaunch-unity-v1/unity-memory-policy-self-test.summary.json'
    telemetryProbe = 'Research/Verification/Gate13R_PR2_MP2/attempt3-formal-prelaunch-unity-v1/telemetry-probe.summary.json'
    positiveBlock = 'Research/Verification/Gate13R_PR2_MP2/attempt3-formal-prelaunch-unity-v1/blocks/positive-p000001.summary.json'
    nativeHard = 'Research/Verification/Gate13R_PR2_MP2/attempt3-formal-prelaunch-unity-v1/blocks/native-hard-p000913.summary.json'
    telemetryFailure = 'Research/Verification/Gate13R_PR2_MP2/attempt3-formal-prelaunch-unity-v1/blocks/telemetry-failure-p000001.summary.json'
    persistenceFailure = 'Research/Verification/Gate13R_PR2_MP2/attempt3-formal-prelaunch-unity-v1/blocks/persistence-failure-p000001.summary.json'
}
$evidenceAudit = New-Object Collections.Generic.List[object]
foreach ($item in $evidence.GetEnumerator()) {
    $path = Join-Path $ProjectPath ([string]$item.Value).Replace('/', '\')
    $document = Read-Json $path
    $passed = $document.passed -eq $true
    $evidenceAudit.Add([ordered]@{ logicalName = [string]$item.Key; relativePath = [string]$item.Value; sha256 = Get-Sha256 $path; passed = $passed })
}
Add-Check 'all-static-unit-monitor-dryrun-and-unity-evidence-pass' (@($evidenceAudit | Where-Object { $_.passed -ne $true }).Count -eq 0) $evidenceAudit.ToArray()
$staticFinal = Read-Json (Join-Path $ProjectPath $evidence.staticFinal.Replace('/', '\'))
$mp2Static = Read-Json (Join-Path $ProjectPath $evidence.mp2Static.Replace('/', '\'))
$monitoring = Read-Json (Join-Path $ProjectPath $evidence.monitoring.Replace('/', '\'))
$launcherPS5 = Read-Json (Join-Path $ProjectPath $evidence.launcherPS5.Replace('/', '\'))
Add-Check 'prelaunch-test-cardinality' ([int]$staticFinal.testCount -eq 54 -and [int]$staticFinal.passedTestCount -eq 54 -and [int]$mp2Static.testCount -eq 69 -and [int]$mp2Static.passedTestCount -eq 69 -and [int]$monitoring.testCount -eq 56 -and [int]$monitoring.passedTestCount -eq 56) '54/54;69/69;56/56'
Add-Check 'schedule-cardinality-and-balance' ([int]$launcherPS5.schedule.scenarioCount -eq 53 -and [int]$launcherPS5.schedule.campaignCount -eq 74 -and [int]$launcherPS5.schedule.processCount -eq 3552 -and [int]$launcherPS5.schedule.sampleCount -eq 10176 -and [int]$launcherPS5.schedule.matchedSuperblockCount -eq 1008 -and [string]$launcherPS5.schedule.abbaSuperblocksPerScenario -eq '24/24' -and [string]$launcherPS5.schedule.orderByWilliamsRowCountPerCell -eq '12') $launcherPS5.schedule
Add-Check 'active-frozen-hash-audit' (@($launcherPS5.frozenHashAudit | Where-Object { $_.passed -ne $true }).Count -eq 0) "files=$(@($launcherPS5.frozenHashAudit).Count)"
Add-Check 'two-stage-commit-and-no-phase-b-static-proof' ($staticFinal.formalStatisticalAnalysisAuthorized -eq $false -and $staticFinal.gate14RAuthorized -eq $false -and @($staticFinal.checks | Where-Object { $_.name -eq 'two-stage-raw-complete-token' -and $_.passed -eq $true }).Count -eq 1 -and @($staticFinal.checks | Where-Object { $_.name -eq 'phase-b-not-invoked' -and $_.passed -eq $true }).Count -eq 1) 'Phase A only; analysis unauthorized'

# Runtime negative no-receipt test: it must stop before creating targets or launching Unity.
$unityBeforeNegative = @(Get-Process -Name Unity -ErrorAction SilentlyContinue).Count
$negativeMessage = ''
$negativeFailed = $false
try {
    & (Join-Path $ProjectPath 'Research\Run-Gate13RPR2MP2FormalBlockV3.ps1') -ProjectPath $ProjectPath -BlockPlanPath (Join-Path $ProjectPath 'Research\Verification\Gate13R_PR2_MP2\attempt3-formal-prelaunch-unity-v1\plans\positive-p000001.json') -OutputDirectory (Join-Path $formalRoot 'campaigns\negative-no-receipt') -AllowedRoot $formalRoot -Mode FormalAttempt3 -ExecutionReceiptPath $formalReceipt -ExpectedOutcome Pass -UnityPath 'H:\UnityEditor\2022.3.30f1c1\Editor\Unity.exe' 2>&1 | Out-String | ForEach-Object { $negativeMessage = $_.Trim() }
} catch { $negativeFailed = $true; $negativeMessage = $_.Exception.Message }
$unityAfterNegative = @(Get-Process -Name Unity -ErrorAction SilentlyContinue).Count
$negativeNoReceiptPassed = $negativeFailed -and $unityBeforeNegative -eq 0 -and $unityAfterNegative -eq 0 -and -not (Test-Path -LiteralPath $formalRoot) -and -not (Test-Path -LiteralPath $formalReceipt) -and -not (Test-Path -LiteralPath $formalStatus)
Add-Check 'negative-no-receipt-fail-closed-no-unity' $negativeNoReceiptPassed $negativeMessage

# Fresh Unity licensing evidence.
$telemetrySummaryPath = Join-Path $ProjectPath $evidence.telemetryProbe.Replace('/', '\')
$telemetrySummary = Read-Json $telemetrySummaryPath
$telemetryLogPath = Join-Path $ProjectPath 'Research\Verification\Gate13R_PR2_MP2\attempt3-formal-prelaunch-unity-v1\telemetry-probe.Unity.log'
$telemetryLog = Get-Content -LiteralPath $telemetryLogPath -Raw -Encoding UTF8
$licensePassed = $telemetrySummary.passed -eq $true -and $telemetrySummary.licenseSerialAssigned -eq $true -and $telemetrySummary.noValidLicenseError -eq $false -and $telemetryLog.Contains('Successfully resolved entitlements') -and $telemetryLog.Contains('Serial number assigned to:') -and -not $telemetryLog.Contains('No valid Unity Editor license found') -and -not $telemetryLog.Contains('LICENSE SYSTEM [ERROR]')
Add-Check 'fresh-unity-license-entitlement-evidence' $licensePassed (Get-Sha256 $telemetryLogPath)

# Power, sleep, environment, telemetry, network, and raw-byte storage preflight.
if (-not ('Gate13RPR2Attempt3NativeMethods' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class Gate13RPR2Attempt3NativeMethods {
  [StructLayout(LayoutKind.Sequential)] public struct SystemPowerStatus { public byte ACLineStatus; public byte BatteryFlag; public byte BatteryLifePercent; public byte Reserved1; public int BatteryLifeTime; public int BatteryFullLifeTime; }
  [DllImport("kernel32.dll")] public static extern bool GetSystemPowerStatus(out SystemPowerStatus status);
}
'@
}
$powerStatus = New-Object Gate13RPR2Attempt3NativeMethods+SystemPowerStatus
$powerStatusAvailable = [Gate13RPR2Attempt3NativeMethods]::GetSystemPowerStatus([ref]$powerStatus)
$powerRaw = (& powercfg.exe /getactivescheme 2>&1 | Out-String).Trim()
$powerMatch = [regex]::Match($powerRaw, '(?i)[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}')
$standby = Get-PowerSettingIndex 'SUB_SLEEP' 'STANDBYIDLE'
$hibernate = Get-PowerSettingIndex 'SUB_SLEEP' 'HIBERNATEIDLE'
$hibernateEnabledRegistry = $null
try { $hibernateEnabledRegistry = [int](Get-ItemPropertyValue -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Control\Power' -Name 'HibernateEnabled' -ErrorAction Stop) } catch { $hibernateEnabledRegistry = $null }
Add-Check 'high-performance-power-scheme' ($powerMatch.Success -and $powerMatch.Value.ToLowerInvariant() -eq '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c') $powerRaw
Add-Check 'ac-online' ($powerStatusAvailable -and [int]$powerStatus.ACLineStatus -eq 1) "available=$powerStatusAvailable;ac=$([int]$powerStatus.ACLineStatus)"
Add-Check 'sleep-disabled-on-ac' ($standby.parsed -and [long]$standby.acIndex -eq 0) "acIndex=$($standby.acIndex)"
Add-Check 'hibernate-disabled-on-ac' ($hibernate.parsed -and [long]$hibernate.acIndex -eq 0 -and $null -ne $hibernateEnabledRegistry -and $hibernateEnabledRegistry -eq 0) "acIndex=$($hibernate.acIndex);registry=$hibernateEnabledRegistry"

$loads = New-Object Collections.Generic.List[double]
for ($index = 0; $index -lt 5; $index++) {
    $processors = @(Get-CimInstance Win32_Processor)
    $load = ($processors | Measure-Object LoadPercentage -Average).Average
    $loads.Add($(if ($null -eq $load) { 0.0 } else { [double]$load }))
    if ($index -lt 4) { Start-Sleep -Seconds 1 }
}
$meanCpuLoad = [double](($loads.ToArray() | Measure-Object -Average).Average)
$os = Get-CimInstance Win32_OperatingSystem
$computer = Get-CimInstance Win32_ComputerSystem
$freePhysicalMemoryBytes = [long]([double]$os.FreePhysicalMemory * 1KB)
$temperatures = @()
$temperatureError = $null
try { $temperatures = @(Get-CimInstance -Namespace root/wmi -ClassName MSAcpi_ThermalZoneTemperature -ErrorAction Stop | ForEach-Object { [math]::Round(([double]$_.CurrentTemperature / 10.0) - 273.15, 2) }) } catch { $temperatureError = $_.Exception.Message }
Add-Check 'quiet-mean-cpu-load-at-most-50pct' ($meanCpuLoad -le 50.0) $meanCpuLoad
Add-Check 'free-physical-memory-at-least-4gib' ($freePhysicalMemoryBytes -ge 4294967296L) $freePhysicalMemoryBytes
Add-Check 'thermal-policy-observed' ($temperatures.Count -gt 0 -or -not [string]::IsNullOrWhiteSpace($temperatureError)) ($(if ($temperatures.Count -gt 0) { $temperatures } else { $temperatureError }))

$networkSucceeded = $false
$networkAttempts = New-Object Collections.Generic.List[object]
foreach ($delay in @(0, 2, 5)) {
    if ($delay -gt 0) { Start-Sleep -Seconds $delay }
    try {
        $client = New-Object Net.Sockets.TcpClient
        $async = $client.BeginConnect('packages.unity.cn', 443, $null, $null)
        $connected = $async.AsyncWaitHandle.WaitOne(10000, $false) -and $client.Connected
        if ($connected) { $client.EndConnect($async); $networkSucceeded = $true }
        $client.Close()
        $networkAttempts.Add([ordered]@{ delaySeconds = $delay; connected = $connected; error = $null })
        if ($networkSucceeded) { break }
    } catch { $networkAttempts.Add([ordered]@{ delaySeconds = $delay; connected = $false; error = $_.Exception.Message }) }
}
Add-Check 'unity-network-tcp443-reachable' $networkSucceeded $networkAttempts.ToArray()

$drive = New-Object IO.DriveInfo 'H:'
$availableFreeBytes = [long]$drive.AvailableFreeSpace
$projectedP95RawBytes = 9631912320L
$projectedSafetyBytes = 14447868480L
$reserveBytes = 42949672960L
$minimumLaunchFreeBytes = 57397541440L
Add-Check 'raw-byte-budget-arithmetic' ($projectedSafetyBytes -eq [long][math]::Ceiling(1.5 * $projectedP95RawBytes) -and $minimumLaunchFreeBytes -eq $projectedSafetyBytes + $reserveBytes) "minimum=$minimumLaunchFreeBytes"
Add-Check 'h-drive-free-space' ($availableFreeBytes -ge $minimumLaunchFreeBytes) "available=$availableFreeBytes;minimum=$minimumLaunchFreeBytes"

# Native runtime identity, heartbeat, lock hygiene, and exact create-new targets.
$unityProcesses = @(Get-Process -Name Unity -ErrorAction SilentlyContinue)
$lockPresent = Test-Path -LiteralPath (Join-Path $ProjectPath 'Temp\UnityLockfile')
Add-Check 'zero-unity-processes' ($unityProcesses.Count -eq 0) "count=$($unityProcesses.Count)"
Add-Check 'unity-project-lock-absent' (-not $lockPresent) "present=$lockPresent"
Add-Check 'native-windows-powershell-5.1' ($PSVersionTable.PSVersion.Major -eq 5 -and [string]$PSVersionTable.PSEdition -eq 'Desktop') "$($PSVersionTable.PSVersion)|$($PSVersionTable.PSEdition)"
Add-Check 'native-psmodulepath-exact' ([string]$env:PSModulePath -eq $expectedPsModulePath) ([string]$env:PSModulePath)
$automationPath = 'C:\Users\bdscy\.codex\automations\gate13r-attempt3-hourly-progress\automation.toml'
$automationText = Get-Content -LiteralPath $automationPath -Raw -Encoding UTF8
$automationSha = Get-Sha256 $automationPath
$automationPassed = $automationSha -eq 'c66d41527f075137b2829a291fb303e1d81af940925e739fa3c898cb8f52b0e4' -and $automationText.Contains('status = "ACTIVE"') -and $automationText.Contains('FREQ=MINUTELY;INTERVAL=5') -and $automationText.Contains('Get-Gate13RPR2Attempt3OperationalProgressV2.ps1')
Add-Check 'hourly-heartbeat-active-and-hash-bound' $automationPassed $automationSha
Add-Check 'formal-root-absent-before-commit' (-not (Test-Path -LiteralPath $formalRoot)) $formalRoot
Add-Check 'formal-receipt-absent-before-commit' (-not (Test-Path -LiteralPath $formalReceipt)) $formalReceipt
Add-Check 'formal-status-absent-before-commit' (-not (Test-Path -LiteralPath $formalStatus)) $formalStatus
Add-Check 'monitoring-root-absent-before-first-event' (-not (Test-Path -LiteralPath $monitoringRoot)) $monitoringRoot

$failed = @($checks | Where-Object { $_.passed -ne $true })
$summary = [ordered]@{
    schemaVersion = 1
    auditKind = 'gate13r-pr2-formal-attempt3-final-prelaunch-environment-storage-preservation-audit-v1'
    observedAtUtc = [DateTime]::UtcNow.ToString('o')
    observedAtAsiaShanghai = [DateTimeOffset]::Now.ToString('o')
    timeZone = 'Asia/Shanghai'
    projectPath = $ProjectPath.Replace('\', '/')
    formalRootResolved = $formalRoot.Replace('\', '/')
    formalReceiptResolved = $formalReceipt.Replace('\', '/')
    formalStatusResolved = $formalStatus.Replace('\', '/')
    checks = $checks.ToArray()
    checkCount = $checks.Count
    passedCheckCount = $checks.Count - $failed.Count
    failedCheckCount = $failed.Count
    failedCheckNames = @($failed | ForEach-Object { [string]$_.name })
    historicalTreeAudit = $historicalTreeAudit.ToArray()
    frozenKeyFileAudit = $keyFileAudit.ToArray()
    implementationAudit = $implementationAudit.ToArray()
    evidenceAudit = $evidenceAudit.ToArray()
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
        acLineStatus = if ($powerStatusAvailable) { [int]$powerStatus.ACLineStatus } else { $null }
        sleepAcSeconds = $standby.acIndex
        hibernateAcSeconds = $hibernate.acIndex
        hibernateEnabledRegistry = $hibernateEnabledRegistry
        thermalTemperaturesCelsius = $temperatures
        thermalQueryError = $temperatureError
        networkHost = 'packages.unity.cn'
        networkPort = 443
        networkTcpSucceeded = $networkSucceeded
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
        telemetrySummaryRelativePath = $evidence.telemetryProbe
        telemetrySummarySha256 = Get-Sha256 $telemetrySummaryPath
        telemetryUnityLogRelativePath = 'Research/Verification/Gate13R_PR2_MP2/attempt3-formal-prelaunch-unity-v1/telemetry-probe.Unity.log'
        telemetryUnityLogSha256 = Get-Sha256 $telemetryLogPath
        serialAssigned = $telemetrySummary.licenseSerialAssigned
        entitlementResolutionObserved = $telemetryLog.Contains('Successfully resolved entitlements')
        passed = $licensePassed
    }
    automation = [ordered]@{ id = 'gate13r-attempt3-hourly-progress'; path = $automationPath; sha256 = $automationSha; active = $automationPassed }
    executionProvenance = [ordered]@{ relativePath = 'Research/Gate13R_PR2_Attempt3_Formal_Execution_Adapter_Provenance.v2.json'; sha256 = Get-Sha256 $provenancePath }
    formalRootAbsent = -not (Test-Path -LiteralPath $formalRoot)
    formalExecutionReceiptAbsent = -not (Test-Path -LiteralPath $formalReceipt)
    formalStatusAbsent = -not (Test-Path -LiteralPath $formalStatus)
    monitoringRootAbsent = -not (Test-Path -LiteralPath $monitoringRoot)
    unityEditorProcessCount = $unityProcesses.Count
    unityLockExists = $lockPresent
    phaseBFormalStatisticalAnalysisAuthorized = $false
    gate14RAuthorized = $false
    passed = $failed.Count -eq 0
}
Write-AtomicJson -Path $OutputPath -Value $summary
if ($failed.Count -ne 0) { throw ('Final prelaunch audit failed: ' + (@($failed | ForEach-Object { [string]$_.name }) -join ', ')) }
Write-Host "Gate13R-PR2 formal attempt-3 final prelaunch audit passed: $($checks.Count)/$($checks.Count)." -ForegroundColor Green
