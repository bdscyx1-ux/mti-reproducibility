[CmdletBinding()]
param(
    [string]$ProjectPath,
    [string]$PlanPath,
    [string]$OutputRoot,
    [switch]$PreflightOnly
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0
$scriptDirectory = Split-Path -Parent $MyInvocation.MyCommand.Path
if ([string]::IsNullOrWhiteSpace($ProjectPath)) { $ProjectPath = [System.IO.Path]::GetFullPath((Join-Path $scriptDirectory '..')) }
else { $ProjectPath = [System.IO.Path]::GetFullPath($ProjectPath) }
if ([string]::IsNullOrWhiteSpace($PlanPath)) { $PlanPath = Join-Path $ProjectPath 'Research\Gate12_Pilot_Plan.v1.json' }
elseif (-not [System.IO.Path]::IsPathRooted($PlanPath)) { $PlanPath = Join-Path $ProjectPath $PlanPath }
$PlanPath = [System.IO.Path]::GetFullPath($PlanPath)

$modulePath = Join-Path $ProjectPath 'Research\Gate12PilotAnalysis.psm1'
$preAuditPath = Join-Path $ProjectPath 'Research\Verification\Gate12_PreImplementationAudit.summary.json'
$campaignRunnerPath = Join-Path $ProjectPath 'Research\Run-FairPlanningCampaign.ps1'
$bundleRoot = Join-Path $ProjectPath 'Research\FormalScenarios\v1'
$unityLockPath = Join-Path $ProjectPath 'Temp\UnityLockfile'
Import-Module $modulePath -Force

function Write-Utf8NoBomJson([string]$Path, $Value, [int]$Depth = 20) {
    $json = $Value | ConvertTo-Json -Depth $Depth
    $json = $json.Replace("`r`n", "`n").Replace("`r", "`n")
    if (-not $json.EndsWith("`n", [System.StringComparison]::Ordinal)) { $json += "`n" }
    $encoding = New-Object System.Text.UTF8Encoding($false, $true)
    [System.IO.File]::WriteAllText($Path, $json, $encoding)
}

function Write-AtomicUtf8NoBomJson([string]$Path, $Value, [int]$Depth = 20) {
    $directory = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $directory -PathType Container)) { New-Item -ItemType Directory -Path $directory -Force | Out-Null }
    $temporaryPath = Join-Path $directory ('.gate12-' + [guid]::NewGuid().ToString('N') + '.tmp')
    Write-Utf8NoBomJson -Path $temporaryPath -Value $Value -Depth $Depth
    Move-Item -LiteralPath $temporaryPath -Destination $Path -Force
}

function Get-StringSha256([string]$Value) {
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($Value)
        return ([System.BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-', '').ToLowerInvariant()
    } finally { $sha.Dispose() }
}

function Get-ProjectRelativePath([string]$FullPath) {
    $root = $ProjectPath.TrimEnd('\', '/') + [System.IO.Path]::DirectorySeparatorChar
    $full = [System.IO.Path]::GetFullPath($FullPath)
    if (-not $full.StartsWith($root, [System.StringComparison]::OrdinalIgnoreCase)) { throw "Path is outside project root: $full" }
    return $full.Substring($root.Length).Replace('\', '/')
}

function Get-DirectoryByteCount([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Container)) { return [long]0 }
    $measurement = Get-ChildItem -LiteralPath $Path -File -Recurse -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum
    if ($null -eq $measurement.Sum) { return [long]0 }
    return [long]$measurement.Sum
}

function Get-BundleVerification($Plan) {
    $manifestPath = Join-Path $ProjectPath $Plan.retainedBundle.manifestRelativePath.Replace('/', '\')
    $manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $errors = New-Object System.Collections.Generic.List[string]
    $builder = New-Object System.Text.StringBuilder
    foreach ($artifact in @($manifest.artifacts)) {
        $path = Join-Path $bundleRoot ([string]$artifact.relativePath).Replace('/', '\')
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            $errors.Add("Missing bundle artifact: $($artifact.relativePath)")
            continue
        }
        $hash = Get-Gate12LowerSha256 $path
        $bytes = (Get-Item -LiteralPath $path).Length
        if ($hash -ne $artifact.sha256 -or $bytes -ne [int64]$artifact.byteCount) { $errors.Add("Bundle artifact mismatch: $($artifact.relativePath)") }
        [void]$builder.Append([string]$artifact.relativePath).Append("`n").Append([string]$artifact.sha256).Append("`n")
    }
    $aggregate = Get-StringSha256 $builder.ToString()
    $bundleFiles = @(Get-ChildItem -LiteralPath $bundleRoot -File -Recurse)
    if ($bundleFiles.Count -ne 57) { $errors.Add("Bundle file count is $($bundleFiles.Count), expected 57.") }
    if ((Get-Gate12LowerSha256 $manifestPath) -ne $Plan.retainedBundle.manifestSha256) { $errors.Add('Bundle manifest hash mismatch.') }
    if ($aggregate -ne $Plan.retainedBundle.orderedAggregateSha256 -or $aggregate -ne $manifest.bundleAggregateSha256) { $errors.Add('Bundle ordered aggregate mismatch.') }
    if ($manifest.pilotExecuted -ne $false -or $manifest.formalCampaignExecuted -ne $false) { $errors.Add('Retained bundle execution flags changed.') }
    return [ordered]@{
        manifestSha256 = Get-Gate12LowerSha256 $manifestPath
        orderedAggregateSha256 = $aggregate
        fileCount = $bundleFiles.Count
        artifactCount = $manifest.artifacts.Count
        errors = $errors.ToArray()
        passed = $errors.Count -eq 0
    }
}

function Get-FrozenHashVerification($Plan, $PreAudit) {
    $entries = New-Object System.Collections.Generic.List[object]
    $errors = New-Object System.Collections.Generic.List[string]
    $paths = [ordered]@{
        specification = [ordered]@{ path = Join-Path $ProjectPath 'Research\Gate12_Pilot_Noise_and_Sample_Size_Specification.md'; expected = $PreAudit.frozenFiles.specification.sha256 }
        testDesign = [ordered]@{ path = Join-Path $ProjectPath 'Research\Gate12_Pilot_Test_Design.md'; expected = $PreAudit.frozenFiles.testDesign.sha256 }
        pilotPlan = [ordered]@{ path = $PlanPath; expected = $PreAudit.frozenFiles.pilotPlan.sha256 }
        fairnessSpecification = [ordered]@{ path = Join-Path $ProjectPath $Plan.frozenInputs.fairnessSpecificationRelativePath.Replace('/', '\'); expected = $Plan.frozenInputs.fairnessSpecificationSha256 }
        workloadSpecification = [ordered]@{ path = Join-Path $ProjectPath $Plan.frozenInputs.workloadSpecificationRelativePath.Replace('/', '\'); expected = $Plan.frozenInputs.workloadSpecificationSha256 }
        campaignRunner = [ordered]@{ path = Join-Path $ProjectPath $Plan.frozenInputs.campaignRunnerRelativePath.Replace('/', '\'); expected = $Plan.frozenInputs.campaignRunnerSha256 }
        workloadRunner = [ordered]@{ path = Join-Path $ProjectPath $Plan.frozenInputs.workloadRunnerRelativePath.Replace('/', '\'); expected = $Plan.frozenInputs.workloadRunnerSha256 }
        batchCommand = [ordered]@{ path = Join-Path $ProjectPath $Plan.frozenInputs.batchCommandRelativePath.Replace('/', '\'); expected = $Plan.frozenInputs.batchCommandSha256 }
        workloadImplementation = [ordered]@{ path = Join-Path $ProjectPath $Plan.frozenInputs.workloadImplementationRelativePath.Replace('/', '\'); expected = $Plan.frozenInputs.workloadImplementationSha256 }
        fairnessContracts = [ordered]@{ path = Join-Path $ProjectPath $Plan.frozenInputs.fairnessContractsRelativePath.Replace('/', '\'); expected = $Plan.frozenInputs.fairnessContractsSha256 }
        matrix = [ordered]@{ path = Join-Path $ProjectPath $Plan.retainedBundle.matrixRelativePath.Replace('/', '\'); expected = $Plan.retainedBundle.matrixSha256 }
        preregistration = [ordered]@{ path = Join-Path $ProjectPath $Plan.retainedBundle.preregistrationRelativePath.Replace('/', '\'); expected = $Plan.retainedBundle.preregistrationSha256 }
        unityExecutable = [ordered]@{ path = $Plan.unity.executablePath.Replace('/', '\'); expected = $Plan.unity.executableSha256 }
    }
    foreach ($entry in $paths.GetEnumerator()) {
        $actual = if (Test-Path -LiteralPath $entry.Value.path -PathType Leaf) { Get-Gate12LowerSha256 $entry.Value.path } else { $null }
        $matches = $actual -eq $entry.Value.expected
        if (-not $matches) { $errors.Add("$($entry.Key) hash mismatch: expected $($entry.Value.expected), actual $actual") }
        $entries.Add([ordered]@{ id = $entry.Key; path = $entry.Value.path; expectedSha256 = $entry.Value.expected; actualSha256 = $actual; matches = $matches })
    }
    $bundle = Get-BundleVerification -Plan $Plan
    foreach ($errorText in @($bundle.errors)) { $errors.Add($errorText) }
    return [ordered]@{
        entries = $entries.ToArray()
        bundle = $bundle
        errors = $errors.ToArray()
        passed = $errors.Count -eq 0
    }
}

if (-not ('Gate12NativePower' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

[StructLayout(LayoutKind.Sequential)]
public struct Gate12SystemPowerStatus
{
    public byte ACLineStatus;
    public byte BatteryFlag;
    public byte BatteryLifePercent;
    public byte SystemStatusFlag;
    public int BatteryLifeTime;
    public int BatteryFullLifeTime;
}

public static class Gate12NativePower
{
    [DllImport("kernel32.dll")]
    public static extern bool GetSystemPowerStatus(ref Gate12SystemPowerStatus status);
}
'@
}

function Get-PowerSnapshot {
    $status = New-Object Gate12SystemPowerStatus
    if (-not [Gate12NativePower]::GetSystemPowerStatus([ref]$status)) { throw 'GetSystemPowerStatus failed.' }
    $powerCfgRaw = (& powercfg.exe /getactivescheme 2>&1 | Out-String).Trim()
    $match = [regex]::Match($powerCfgRaw, '(?i)[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}')
    if (-not $match.Success) { throw "Could not parse active power-scheme GUID: $powerCfgRaw" }
    return [ordered]@{
        acLineStatus = [int]$status.ACLineStatus
        batteryFlag = [int]$status.BatteryFlag
        batteryLifePercent = [int]$status.BatteryLifePercent
        systemStatusFlag = [int]$status.SystemStatusFlag
        batteryLifeTimeSeconds = [int]$status.BatteryLifeTime
        batteryFullLifeTimeSeconds = [int]$status.BatteryFullLifeTime
        activePowerSchemeGuid = $match.Value.ToLowerInvariant()
        activePowerSchemeRaw = $powerCfgRaw
    }
}

function Get-TemperatureSnapshot {
    try {
        $zones = @(Get-CimInstance -Namespace 'root/wmi' -ClassName 'MSAcpi_ThermalZoneTemperature' -ErrorAction Stop)
        $values = @()
        foreach ($zone in $zones) {
            if ($null -ne $zone.CurrentTemperature -and [double]$zone.CurrentTemperature -gt 0.0) {
                $values += [math]::Round(([double]$zone.CurrentTemperature / 10.0) - 273.15, 3)
            }
        }
        return [ordered]@{ available = $values.Count -gt 0; celsius = $values; source = 'MSAcpi_ThermalZoneTemperature'; error = $null }
    } catch {
        return [ordered]@{ available = $false; celsius = @(); source = 'MSAcpi_ThermalZoneTemperature'; error = $_.Exception.Message }
    }
}

function Get-TopProcessSnapshot([int]$Count) {
    $rows = @()
    foreach ($process in @(Get-Process -ErrorAction SilentlyContinue)) {
        try {
            $rows += [pscustomobject]@{
                name = $process.ProcessName
                id = $process.Id
                cpuSeconds = if ($null -eq $process.CPU) { 0.0 } else { [double]$process.CPU }
                workingSetBytes = [long]$process.WorkingSet64
                startTime = try { $process.StartTime.ToString('o') } catch { $null }
            }
        } catch { }
    }
    return @($rows | Sort-Object @{ Expression = 'cpuSeconds'; Descending = $true }, @{ Expression = 'workingSetBytes'; Descending = $true } | Select-Object -First $Count)
}

function Get-EnvironmentSnapshot([string]$Phase, $Plan, $PreAudit) {
    $capturedAt = Get-Date
    $processors = @(Get-CimInstance Win32_Processor)
    $operatingSystem = Get-CimInstance Win32_OperatingSystem
    $computerSystem = Get-CimInstance Win32_ComputerSystem
    $loadSamples = @()
    for ($index = 0; $index -lt [int]$Plan.preflight.cpuLoadSampleCount; $index++) {
        $load = (Get-CimInstance Win32_Processor | Measure-Object -Property LoadPercentage -Average).Average
        if ($null -eq $load) { $load = 0.0 }
        $loadSamples += [double]$load
        if ($index -lt [int]$Plan.preflight.cpuLoadSampleCount - 1) { Start-Sleep -Seconds ([int]$Plan.preflight.cpuLoadSampleIntervalSeconds) }
    }
    $power = Get-PowerSnapshot
    $thermal = Get-TemperatureSnapshot
    $unityPath = $Plan.unity.executablePath.Replace('/', '\')
    $unityItem = Get-Item -LiteralPath $unityPath
    $driveRoot = [System.IO.Path]::GetPathRoot($OutputRoot)
    $drive = New-Object System.IO.DriveInfo -ArgumentList @($driveRoot)
    $unityProcesses = @(Get-Process -Name Unity -ErrorAction SilentlyContinue)
    $frozen = Get-FrozenHashVerification -Plan $Plan -PreAudit $PreAudit
    $snapshot = [ordered]@{
        schemaVersion = 1
        phase = $Phase
        capturedAt = $capturedAt.ToString('o')
        capturedAtUtc = $capturedAt.ToUniversalTime().ToString('o')
        machineName = $env:COMPUTERNAME
        userDomainName = $env:USERDOMAIN
        cpuModels = @($processors | ForEach-Object { ([string]$_.Name).Trim() })
        physicalCoreCount = [int](($processors | Measure-Object -Property NumberOfCores -Sum).Sum)
        logicalProcessorCount = [int](($processors | Measure-Object -Property NumberOfLogicalProcessors -Sum).Sum)
        cpuLoadSamplesPercent = $loadSamples
        meanCpuLoadPercent = Get-Gate12Mean -Values ([double[]]$loadSamples)
        installedPhysicalMemoryGiB = [math]::Round(([double]$computerSystem.TotalPhysicalMemory / 1GB), 3)
        freePhysicalMemoryGiB = [math]::Round(([double]$operatingSystem.FreePhysicalMemory * 1KB / 1GB), 3)
        windowsCaption = [string]$operatingSystem.Caption
        windowsVersion = [string]$operatingSystem.Version
        windowsBuildNumber = [string]$operatingSystem.BuildNumber
        unityExecutablePath = $unityPath
        unityProductVersion = [string]$unityItem.VersionInfo.ProductVersion
        unityFileVersion = [string]$unityItem.VersionInfo.FileVersion
        unityExecutableBytes = [long]$unityItem.Length
        unityExecutableSha256 = Get-Gate12LowerSha256 $unityPath
        acLineStatus = $power.acLineStatus
        batteryFlag = $power.batteryFlag
        batteryLifePercent = $power.batteryLifePercent
        batteryLifeTimeSeconds = $power.batteryLifeTimeSeconds
        activePowerSchemeGuid = $power.activePowerSchemeGuid
        activePowerSchemeRaw = $power.activePowerSchemeRaw
        outputDriveName = $drive.Name
        outputDriveFormat = $drive.DriveFormat
        outputDriveTotalGiB = [math]::Round(([double]$drive.TotalSize / 1GB), 3)
        freeOutputDriveGiB = [math]::Round(([double]$drive.AvailableFreeSpace / 1GB), 3)
        unityProcessCount = $unityProcesses.Count
        unityProcessIds = @($unityProcesses | ForEach-Object { $_.Id })
        unityLockfilePresent = Test-Path -LiteralPath $unityLockPath
        backgroundProcesses = Get-TopProcessSnapshot -Count ([int]$Plan.preflight.topProcessSnapshotCount)
        temperatureAvailable = $thermal.available
        temperatureCelsius = $thermal.celsius
        temperatureSource = $thermal.source
        temperatureError = $thermal.error
        frozenHashVerification = $frozen
        frozenHashesMatch = $frozen.passed
    }
    $snapshot['preflightVerdict'] = Test-Gate12PreflightSnapshot -Snapshot ([pscustomobject]$snapshot) -Plan $Plan
    return $snapshot
}

function Get-ObservedOutputBytes([string]$CampaignDirectory, [string]$StdoutPath, [string]$StderrPath) {
    $total = Get-DirectoryByteCount $CampaignDirectory
    foreach ($path in @($StdoutPath, $StderrPath, ($CampaignDirectory + '.summary.json'))) {
        if (Test-Path -LiteralPath $path -PathType Leaf) { $total += (Get-Item -LiteralPath $path).Length }
    }
    return [long]$total
}

$script:monitoringEvents = New-Object System.Collections.Generic.List[object]
function Invoke-Gate12Campaign {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Role,
        [Parameter(Mandatory = $true)][int]$Ordinal,
        [Parameter(Mandatory = $true)][string]$CampaignId,
        [Parameter(Mandatory = $true)][string]$ScenarioRelativePath,
        [Parameter(Mandatory = $true)][string]$ScenarioId,
        [Parameter(Mandatory = $true)][string]$ComparisonCohortId,
        [Parameter(Mandatory = $true)][int]$Blocks,
        [Parameter(Mandatory = $true)][int]$ExpectedSampleCount,
        [Parameter(Mandatory = $true)][string]$CampaignDirectory,
        [Parameter(Mandatory = $true)]$Plan
    )
    if (Test-Path -LiteralPath $CampaignDirectory) { throw "Campaign output already exists; refusing to overwrite: $CampaignDirectory" }
    $campaignParent = Split-Path -Parent $CampaignDirectory
    if (-not (Test-Path -LiteralPath $campaignParent -PathType Container)) { New-Item -ItemType Directory -Path $campaignParent -Force | Out-Null }
    $scenarioPath = Join-Path $bundleRoot $ScenarioRelativePath.Replace('/', '\')
    $stdoutPath = $CampaignDirectory + '.stdout.log'
    $stderrPath = $CampaignDirectory + '.stderr.log'
    $powershellPath = (Get-Command powershell.exe -ErrorAction Stop).Source
    $argumentString = '-NoProfile -ExecutionPolicy Bypass -File "{0}" -ScenarioPath "{1}" -ComparisonCohortId "{2}" -Blocks {3} -CampaignId "{4}" -OutputDirectory "{5}" -UnityPath "{6}" -ProjectPath "{7}"' -f $campaignRunnerPath, $scenarioPath, $ComparisonCohortId, $Blocks, $CampaignId, $CampaignDirectory, $Plan.unity.executablePath.Replace('/', '\'), $ProjectPath
    $startedAt = Get-Date
    Write-Host ("[{0}] Starting {1} campaign {2}: {3}, {4}, blocks={5}, samples={6}" -f $Ordinal, $Role, $CampaignId, $ScenarioId, $ComparisonCohortId, $Blocks, $ExpectedSampleCount) -ForegroundColor Cyan
    $capture = Start-Gate12OwnedProcessCapture -FilePath $powershellPath -Arguments $argumentString -WorkingDirectory $ProjectPath
    $process = $capture.Process
    $stdoutTask = $capture.StdoutTask
    $stderrTask = $capture.StderrTask
    $lastBytes = -1L
    $noGrowthChecks = 0
    $stallReported = $false
    $hardTimedOut = $false
    while (-not $process.WaitForExit([int]$Plan.monitoring.checkIntervalSeconds * 1000)) {
        $elapsed = ((Get-Date) - $startedAt).TotalSeconds
        $bytes = Get-ObservedOutputBytes -CampaignDirectory $CampaignDirectory -StdoutPath $stdoutPath -StderrPath $stderrPath
        if ($bytes -gt $lastBytes) { $noGrowthChecks = 0 } else { $noGrowthChecks++ }
        $lastBytes = $bytes
        $decision = Get-Gate12MonitorDecision -ElapsedSeconds $elapsed -NoGrowthChecks $noGrowthChecks -HardTimeoutSeconds ([double]$Plan.monitoring.hardTimeoutSecondsPerCampaign) -OutputStallChecks ([int]$Plan.monitoring.outputStallChecks)
        Write-Host ("[{0}] {1}: elapsed={2:N0}s, output={3:N0} bytes, no-growth-checks={4}" -f $Ordinal, $CampaignId, $elapsed, $bytes, $noGrowthChecks)
        if ($decision -eq 'output-stall-advisory' -and -not $stallReported) {
            $event = [ordered]@{ timestamp = (Get-Date).ToString('o'); type = 'OUTPUT_STALL'; role = $Role; campaignId = $CampaignId; elapsedSeconds = $elapsed; noGrowthChecks = $noGrowthChecks; action = 'advisory-continue-no-auto-retry' }
            $script:monitoringEvents.Add($event)
            Write-Warning "OUTPUT_STALL advisory for $CampaignId; continuing until completion or hard timeout."
            $stallReported = $true
        }
        if ($decision -eq 'hard-timeout') {
            $event = [ordered]@{ timestamp = (Get-Date).ToString('o'); type = 'HARD_TIMEOUT'; role = $Role; campaignId = $CampaignId; elapsedSeconds = $elapsed; action = 'terminate-process-tree' }
            $script:monitoringEvents.Add($event)
            & taskkill.exe /PID $process.Id /T /F | Out-Null
            $hardTimedOut = $true
            break
        }
    }
    if (-not $process.HasExited) { $process.WaitForExit() }
    $process.WaitForExit()
    $stdoutTask.Wait()
    $stderrTask.Wait()
    $textEncoding = New-Object System.Text.UTF8Encoding($false, $true)
    [System.IO.File]::WriteAllText($stdoutPath, [string]$stdoutTask.Result, $textEncoding)
    [System.IO.File]::WriteAllText($stderrPath, [string]$stderrTask.Result, $textEncoding)
    $rawExitCode = $process.ExitCode
    if ($null -eq $rawExitCode) {
        $process.Dispose()
        throw "Campaign process exit code was unavailable: $CampaignId"
    }
    $exitCode = [int]$rawExitCode
    $process.Dispose()
    $completedAt = Get-Date
    if ($hardTimedOut) { throw "Campaign hard timeout: $CampaignId" }
    if ($exitCode -ne 0) {
        $stderrTail = if (Test-Path -LiteralPath $stderrPath) { @(Get-Content -LiteralPath $stderrPath -Tail 50) -join "`n" } else { '<missing stderr>' }
        throw "Campaign failed with exit code ${exitCode}: $CampaignId`n$stderrTail"
    }
    $manifestPath = Join-Path $CampaignDirectory 'campaign-manifest.json'
    $summaryPath = $CampaignDirectory + '.summary.json'
    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf) -or -not (Test-Path -LiteralPath $summaryPath -PathType Leaf)) { throw "Campaign output is incomplete: $CampaignId" }
    $manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $summary = Get-Content -LiteralPath $summaryPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($summary.passed -ne $true -or $manifest.completed -ne $true -or $manifest.formalCampaign -ne $false -or $manifest.campaignId -ne $CampaignId -or $manifest.comparisonCohortId -ne $ComparisonCohortId -or $manifest.scenarioId -ne $ScenarioId -or $manifest.blockCount -ne $Blocks -or $manifest.sampleCount -ne $ExpectedSampleCount -or $manifest.positionBalanced -ne $true -or $manifest.orderedPredecessorBalanced -ne $true) {
        throw "Campaign manifest identity/balance failed: $CampaignId"
    }
    $bytes = Get-ObservedOutputBytes -CampaignDirectory $CampaignDirectory -StdoutPath $stdoutPath -StderrPath $stderrPath
    return [ordered]@{
        role = $Role
        ordinal = $Ordinal
        campaignId = $CampaignId
        scenarioId = $ScenarioId
        scenarioRelativePath = $ScenarioRelativePath
        comparisonCohortId = $ComparisonCohortId
        blocks = $Blocks
        sampleCount = $manifest.sampleCount
        campaignDirectory = Get-ProjectRelativePath $CampaignDirectory
        campaignManifestRelativePath = Get-ProjectRelativePath $manifestPath
        campaignManifestSha256 = Get-Gate12LowerSha256 $manifestPath
        wrapperSummaryRelativePath = Get-ProjectRelativePath $summaryPath
        wrapperSummarySha256 = Get-Gate12LowerSha256 $summaryPath
        stdoutRelativePath = Get-ProjectRelativePath $stdoutPath
        stdoutSha256 = Get-Gate12LowerSha256 $stdoutPath
        stderrRelativePath = Get-ProjectRelativePath $stderrPath
        stderrSha256 = Get-Gate12LowerSha256 $stderrPath
        outputBytes = $bytes
        startedAt = $startedAt.ToString('o')
        completedAt = $completedAt.ToString('o')
        wallSeconds = ($completedAt - $startedAt).TotalSeconds
        hardTimedOut = $false
        formalCampaign = $false
        completed = $true
    }
}

function Write-PilotCheckpoint([string]$Status, $Plan, $WarmupEntry, [object[]]$MeasuredEntries, [string]$ErrorMessage) {
    $checkpoint = [ordered]@{
        schemaVersion = 1
        checkpointId = 'gate12-pilot-checkpoint-v1'
        pilotPlanId = $Plan.pilotPlanId
        classification = $Plan.classification
        status = $Status
        savedAt = (Get-Date).ToString('o')
        formalCampaign = $false
        gate13ExecutionAuthorized = $false
        expectedMeasuredCampaignCount = $Plan.repetitionDesign.measuredCampaignCount
        completedMeasuredCampaignCount = $MeasuredEntries.Count
        expectedMeasuredUnityProcessCount = $Plan.repetitionDesign.measuredUnityProcessCount
        completedMeasuredUnityProcessCount = Get-Gate12CompletedSampleCount -Entries $MeasuredEntries
        warmup = $WarmupEntry
        measuredCampaigns = @($MeasuredEntries)
        monitoringEvents = $script:monitoringEvents.ToArray()
        error = $ErrorMessage
    }
    Write-AtomicUtf8NoBomJson -Path (Join-Path $OutputRoot 'pilot-checkpoint.json') -Value $checkpoint -Depth 16
}

if (-not (Test-Path -LiteralPath $PlanPath -PathType Leaf)) { throw "Pilot plan not found: $PlanPath" }
if (-not (Test-Path -LiteralPath $preAuditPath -PathType Leaf)) { throw "Pre-implementation audit not found: $preAuditPath" }
if (-not (Test-Path -LiteralPath $campaignRunnerPath -PathType Leaf)) { throw "Campaign runner not found: $campaignRunnerPath" }
$plan = Get-Content -LiteralPath $PlanPath -Raw -Encoding UTF8 | ConvertFrom-Json
$preAudit = Get-Content -LiteralPath $preAuditPath -Raw -Encoding UTF8 | ConvertFrom-Json
if ($preAudit.passed -ne $true -or $preAudit.auditMode -ne 'pre-implementation-freeze') { throw 'Gate 12 pre-implementation audit is not passing.' }
if ($plan.formalCampaign -ne $false -or $plan.gate13ExecutionAuthorized -ne $false -or $plan.gate13ResultsPermitted -ne $false) { throw 'Pilot plan attempts to authorize formal/Gate 13 execution.' }

$plannedOutputRoot = [System.IO.Path]::GetFullPath((Join-Path $ProjectPath $plan.output.rootRelativePath.Replace('/', '\')))
if ([string]::IsNullOrWhiteSpace($OutputRoot)) { $OutputRoot = $plannedOutputRoot }
elseif (-not [System.IO.Path]::IsPathRooted($OutputRoot)) { $OutputRoot = Join-Path $ProjectPath $OutputRoot }
$OutputRoot = [System.IO.Path]::GetFullPath($OutputRoot)
if (-not [string]::Equals($OutputRoot, $plannedOutputRoot, [System.StringComparison]::OrdinalIgnoreCase)) { throw "Output root must equal the frozen plan path: $plannedOutputRoot" }
if (Test-Path -LiteralPath $OutputRoot) { throw "Pilot output root already exists; create-new policy refuses to overwrite or resume automatically: $OutputRoot" }
if ($OutputRoot.StartsWith($bundleRoot, [System.StringComparison]::OrdinalIgnoreCase)) { throw 'Pilot output root cannot be inside the retained bundle.' }

if ($PreflightOnly) {
    $snapshot = Get-EnvironmentSnapshot -Phase 'validation-only-no-output' -Plan $plan -PreAudit $preAudit
    $snapshot | ConvertTo-Json -Depth 10
    if ($snapshot.preflightVerdict.passed -ne $true) { Write-Error "Gate 12 validation-only preflight failed: $($snapshot.preflightVerdict.failedChecks -join ', ')"; exit 1 }
    Write-Host 'Gate 12 validation-only preflight passed; no output directory or timing sample was created.' -ForegroundColor Green
    exit 0
}

New-Item -ItemType Directory -Path $OutputRoot | Out-Null
$startedAt = Get-Date
$warmupEntry = $null
$measuredEntries = New-Object System.Collections.Generic.List[object]
try {
    Write-Host 'Capturing Gate 12 start preflight...' -ForegroundColor Cyan
    $startSnapshot = Get-EnvironmentSnapshot -Phase 'start-preflight' -Plan $plan -PreAudit $preAudit
    Write-Utf8NoBomJson -Path (Join-Path $OutputRoot 'environment-start.json') -Value $startSnapshot -Depth 18
    if ($startSnapshot.preflightVerdict.passed -ne $true) { throw "Start preflight failed: $($startSnapshot.preflightVerdict.failedChecks -join ', ')" }
    Write-PilotCheckpoint -Status 'preflight-passed' -Plan $plan -WarmupEntry $null -MeasuredEntries @() -ErrorMessage $null

    $warmupDirectory = Join-Path $OutputRoot 'warmup\g12p-warmup-r01-shared'
    $warmupEntry = Invoke-Gate12Campaign -Role 'thermal-warmup-excluded' -Ordinal 0 -CampaignId 'g12p-warmup-r01-shared' -ScenarioRelativePath $plan.thermalWarmup.scenarioRelativePath -ScenarioId $plan.thermalWarmup.scenarioId -ComparisonCohortId $plan.thermalWarmup.comparisonCohortId -Blocks ([int]$plan.thermalWarmup.blocks) -ExpectedSampleCount ([int]$plan.thermalWarmup.unityProcessCount) -CampaignDirectory $warmupDirectory -Plan $plan
    $warmupEntry['analysisExcluded'] = $true
    Write-PilotCheckpoint -Status 'warmup-completed' -Plan $plan -WarmupEntry $warmupEntry -MeasuredEntries @() -ErrorMessage $null

    $quietSeconds = [int]$plan.thermalWarmup.quietStabilizationSecondsAfterWarmup
    Write-Host "Warm-up complete; beginning frozen $quietSeconds-second quiet stabilization." -ForegroundColor Cyan
    Start-Sleep -Seconds $quietSeconds
    $postWarmupSnapshot = Get-EnvironmentSnapshot -Phase 'post-warmup-stabilized' -Plan $plan -PreAudit $preAudit
    Write-Utf8NoBomJson -Path (Join-Path $OutputRoot 'environment-post-warmup.json') -Value $postWarmupSnapshot -Depth 18
    if ($postWarmupSnapshot.preflightVerdict.passed -ne $true) { throw "Post-warmup preflight failed: $($postWarmupSnapshot.preflightVerdict.failedChecks -join ', ')" }

    foreach ($campaign in @($plan.measuredCampaigns | Sort-Object ordinal)) {
        $directoryName = '{0:D3}-{1}' -f [int]$campaign.ordinal, [string]$campaign.campaignId
        $campaignDirectory = Join-Path $OutputRoot (Join-Path 'measured' $directoryName)
        $entry = Invoke-Gate12Campaign -Role 'measured-non-formal-pilot' -Ordinal ([int]$campaign.ordinal) -CampaignId ([string]$campaign.campaignId) -ScenarioRelativePath ([string]$campaign.scenarioRelativePath) -ScenarioId ([string]$campaign.scenarioId) -ComparisonCohortId ([string]$campaign.comparisonCohortId) -Blocks ([int]$campaign.blocks) -ExpectedSampleCount ([int]$campaign.expectedSampleCount) -CampaignDirectory $campaignDirectory -Plan $plan
        $measuredEntries.Add($entry)
        Write-PilotCheckpoint -Status 'running-measured-campaigns' -Plan $plan -WarmupEntry $warmupEntry -MeasuredEntries ($measuredEntries.ToArray()) -ErrorMessage $null
    }

    $endSnapshot = Get-EnvironmentSnapshot -Phase 'end-preflight' -Plan $plan -PreAudit $preAudit
    Write-Utf8NoBomJson -Path (Join-Path $OutputRoot 'environment-end.json') -Value $endSnapshot -Depth 18
    if ($endSnapshot.preflightVerdict.passed -ne $true) { throw "End preflight failed: $($endSnapshot.preflightVerdict.failedChecks -join ', ')" }
    if ($startSnapshot.activePowerSchemeGuid -ne $postWarmupSnapshot.activePowerSchemeGuid -or $startSnapshot.activePowerSchemeGuid -ne $endSnapshot.activePowerSchemeGuid -or $startSnapshot.acLineStatus -ne 1 -or $postWarmupSnapshot.acLineStatus -ne 1 -or $endSnapshot.acLineStatus -ne 1) { throw 'AC/power-scheme state changed across the pilot.' }

    $measuredProcessCount = Get-Gate12CompletedSampleCount -Entries ($measuredEntries.ToArray())
    if ($measuredEntries.Count -ne [int]$plan.repetitionDesign.measuredCampaignCount -or $measuredProcessCount -ne [int]$plan.repetitionDesign.measuredUnityProcessCount) { throw "Measured completion count mismatch: campaigns=$($measuredEntries.Count), samples=$measuredProcessCount" }
    $bundleBefore = $startSnapshot.frozenHashVerification.bundle
    $bundleAfter = $endSnapshot.frozenHashVerification.bundle
    if ($bundleBefore.passed -ne $true -or $bundleAfter.passed -ne $true -or $bundleBefore.manifestSha256 -ne $bundleAfter.manifestSha256 -or $bundleBefore.orderedAggregateSha256 -ne $bundleAfter.orderedAggregateSha256) { throw 'Retained bundle changed during pilot.' }

    $completedAt = Get-Date
    $manifest = [ordered]@{
        schemaVersion = 1
        pilotManifestId = 'gate12-pilot-manifest-v1'
        pilotPlanId = $plan.pilotPlanId
        classification = $plan.classification
        formalCampaign = $false
        gate13ExecutionAuthorized = $false
        gate13ResultsPermitted = $false
        frozenSpecificationSha256 = $preAudit.frozenFiles.specification.sha256
        frozenTestDesignSha256 = $preAudit.frozenFiles.testDesign.sha256
        frozenPilotPlanSha256 = $preAudit.frozenFiles.pilotPlan.sha256
        preImplementationAuditRelativePath = Get-ProjectRelativePath $preAuditPath
        preImplementationAuditSha256 = Get-Gate12LowerSha256 $preAuditPath
        runnerRelativePath = Get-ProjectRelativePath $MyInvocation.MyCommand.Path
        runnerSha256 = Get-Gate12LowerSha256 $MyInvocation.MyCommand.Path
        analysisModuleRelativePath = Get-ProjectRelativePath $modulePath
        analysisModuleSha256 = Get-Gate12LowerSha256 $modulePath
        outputRootRelativePath = Get-ProjectRelativePath $OutputRoot
        environmentStartFile = 'environment-start.json'
        environmentStartSha256 = Get-Gate12LowerSha256 (Join-Path $OutputRoot 'environment-start.json')
        environmentPostWarmupFile = 'environment-post-warmup.json'
        environmentPostWarmupSha256 = Get-Gate12LowerSha256 (Join-Path $OutputRoot 'environment-post-warmup.json')
        environmentEndFile = 'environment-end.json'
        environmentEndSha256 = Get-Gate12LowerSha256 (Join-Path $OutputRoot 'environment-end.json')
        bundleBefore = $bundleBefore
        bundleAfter = $bundleAfter
        warmup = $warmupEntry
        measuredCampaignCount = $measuredEntries.Count
        measuredUnityProcessCount = $measuredProcessCount
        warmupUnityProcessCount = [int]$warmupEntry.sampleCount
        totalUnityProcessCount = $measuredProcessCount + [int]$warmupEntry.sampleCount
        measuredCampaigns = $measuredEntries.ToArray()
        monitoringEvents = $script:monitoringEvents.ToArray()
        technicalInvalidityCount = 0
        autoRetryCount = 0
        startedAt = $startedAt.ToString('o')
        startedAtUtc = $startedAt.ToUniversalTime().ToString('o')
        completedAt = $completedAt.ToString('o')
        completedAtUtc = $completedAt.ToUniversalTime().ToString('o')
        wallSeconds = ($completedAt - $startedAt).TotalSeconds
        completed = $true
    }
    Write-Utf8NoBomJson -Path (Join-Path $OutputRoot 'pilot-manifest.json') -Value $manifest -Depth 20
    Write-PilotCheckpoint -Status 'pilot-completed-analysis-pending' -Plan $plan -WarmupEntry $warmupEntry -MeasuredEntries ($measuredEntries.ToArray()) -ErrorMessage $null
    $result = [ordered]@{
        passed = $true
        outputRoot = $OutputRoot
        pilotManifestPath = Join-Path $OutputRoot 'pilot-manifest.json'
        pilotManifestSha256 = Get-Gate12LowerSha256 (Join-Path $OutputRoot 'pilot-manifest.json')
        measuredCampaignCount = $measuredEntries.Count
        measuredUnityProcessCount = $measuredProcessCount
        warmupUnityProcessCount = [int]$warmupEntry.sampleCount
        totalUnityProcessCount = $manifest.totalUnityProcessCount
        wallSeconds = $manifest.wallSeconds
        formalCampaign = $false
        gate13Executed = $false
    }
    $result | ConvertTo-Json -Depth 8
    Write-Host 'Gate 12 isolated non-formal pilot completed. Analysis has not yet been run.' -ForegroundColor Green
    exit 0
} catch {
    $message = $_.Exception.Message
    try {
        $failure = [ordered]@{
            schemaVersion = 1
            pilotPlanId = $plan.pilotPlanId
            classification = $plan.classification
            failedAt = (Get-Date).ToString('o')
            error = $message
            formalCampaign = $false
            gate13Executed = $false
            completedMeasuredCampaignCount = $measuredEntries.Count
            completedMeasuredUnityProcessCount = Get-Gate12CompletedSampleCount -Entries ($measuredEntries.ToArray())
            warmup = $warmupEntry
            monitoringEvents = $script:monitoringEvents.ToArray()
            autoRetryCount = 0
            completed = $false
        }
        Write-AtomicUtf8NoBomJson -Path (Join-Path $OutputRoot 'pilot-failure.json') -Value $failure -Depth 16
        Write-PilotCheckpoint -Status 'failed-no-auto-retry' -Plan $plan -WarmupEntry $warmupEntry -MeasuredEntries ($measuredEntries.ToArray()) -ErrorMessage $message
    } catch { }
    Write-Error "Gate 12 pilot failed without auto-retry: $message"
    exit 1
}
