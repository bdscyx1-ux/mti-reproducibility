[CmdletBinding()]
param(
    [string]$UnityPath = 'H:\UnityEditor\2022.3.30f1c1\Editor\Unity.exe',
    [string]$ProjectPath = (Split-Path -Parent $PSScriptRoot),
    [string]$OutputDirectory = 'Research\Verification\Gate13R2_v2\TelemetryProbe\v1'
)

$ErrorActionPreference = 'Stop'
$ProjectPath = [System.IO.Path]::GetFullPath($ProjectPath)
$UnityPath = [System.IO.Path]::GetFullPath($UnityPath)
$OutputDirectory = if ([System.IO.Path]::IsPathRooted($OutputDirectory)) { [System.IO.Path]::GetFullPath($OutputDirectory) } else { [System.IO.Path]::GetFullPath((Join-Path $ProjectPath $OutputDirectory)) }
$modulePath = Join-Path $PSScriptRoot 'Gate13R2V2Preparation.psm1'
Import-Module $modulePath -Force

if (-not (Test-Path -LiteralPath $UnityPath -PathType Leaf)) { throw "Unity executable not found: $UnityPath" }
if (-not (Test-Path -LiteralPath (Join-Path $ProjectPath 'Assets') -PathType Container)) { throw "Unity project not found: $ProjectPath" }
$formalRoot = [System.IO.Path]::GetFullPath((Join-Path $ProjectPath 'Research\FormalRuns\Gate13_ProcessReuse\v1'))
if (Test-Path -LiteralPath $formalRoot) { throw "Reserved process-reuse formal root must remain absent: $formalRoot" }
$verificationRoot = [System.IO.Path]::GetFullPath((Join-Path $ProjectPath 'Research\Verification\Gate13R2_v2'))
$verificationPrefix = $verificationRoot.TrimEnd('\') + '\'
if (-not $OutputDirectory.StartsWith($verificationPrefix, [System.StringComparison]::OrdinalIgnoreCase)) { throw 'Telemetry probe output must stay inside the versioned v2 verification root.' }
if (Test-Path -LiteralPath $OutputDirectory) { throw "Telemetry probe output already exists; refusing retry/overwrite: $OutputDirectory" }
$unityProcesses = @(Get-Process -Name Unity -ErrorAction SilentlyContinue)
$lockPath = Join-Path $ProjectPath 'Temp\UnityLockfile'
if ($unityProcesses.Count -gt 0 -or (Test-Path -LiteralPath $lockPath)) { throw 'Close Unity and clear the project lock before the v2 telemetry probe.' }

$unityLogPath = $OutputDirectory + '.Unity.log'
$stdoutPath = $OutputDirectory + '.wrapper.stdout.log'
$stderrPath = $OutputDirectory + '.wrapper.stderr.log'
$summaryPath = $OutputDirectory + '.summary.json'
foreach ($path in @($unityLogPath, $stdoutPath, $stderrPath, $summaryPath)) { if (Test-Path -LiteralPath $path) { throw "Create-new telemetry probe sidecar already exists: $path" } }
$parent = Split-Path -Parent $OutputDirectory
if (-not (Test-Path -LiteralPath $parent -PathType Container)) { New-Item -ItemType Directory -Path $parent | Out-Null }

$startedAtUtc = [DateTime]::UtcNow
$arguments = @(
    '-batchmode',
    '-nographics',
    '-quit',
    '-projectPath', ('"' + $ProjectPath + '"'),
    '-executeMethod', 'DDM.Research.Editor.ResearchPlanningProcessReuseBatchCommandV2.ProbeTelemetry',
    '-ddmProcessReuseV2TelemetryProbeDirectory', ('"' + $OutputDirectory + '"'),
    '-logFile', ('"' + $unityLogPath + '"')
)
$process = Start-Process -FilePath $UnityPath -ArgumentList $arguments -WorkingDirectory (Split-Path -Parent $UnityPath) -WindowStyle Hidden -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath -PassThru
$readyPath = Join-Path $OutputDirectory 'telemetry-probe-ready.json'
$externalPath = Join-Path $OutputDirectory 'external-os-query.json'
$resultPath = Join-Path $OutputDirectory 'telemetry-probe-result.json'
$deadline = [DateTime]::UtcNow.AddMinutes(10)
while (-not (Test-Path -LiteralPath $readyPath -PathType Leaf) -and -not $process.HasExited -and [DateTime]::UtcNow -lt $deadline) {
    Start-Sleep -Milliseconds 100
    $process.Refresh()
}

$wrapperErrors = New-Object System.Collections.Generic.List[string]
if (-not (Test-Path -LiteralPath $readyPath -PathType Leaf)) {
    $wrapperErrors.Add('Unity did not publish telemetry-probe-ready.json before exiting or the wrapper timeout.')
} else {
    $ready = Read-G13R2V2Json -Path $readyPath
    if ([int]$ready.nativeBefore.processId -ne [int]$process.Id) { $wrapperErrors.Add('Ready-file PID does not match the owned Unity PID.') }
    $cim = Get-CimInstance -ClassName Win32_Process -Filter ("ProcessId = {0}" -f [int]$process.Id) -ErrorAction Stop
    if ($null -eq $cim) { $wrapperErrors.Add('Independent Win32_Process query returned no process.') }
    else {
        $query = [ordered]@{
            schemaVersion = 1
            queryKind = 'gate13-r2-v2-independent-os-memory-query-v1'
            querySourceId = 'cim-win32_process-v1'
            queriedAtUtc = [DateTime]::UtcNow.ToString('o')
            processId = [int]$cim.ProcessId
            name = [string]$cim.Name
            executablePath = [string]$cim.ExecutablePath
            creationDateUtc = ([DateTime]$cim.CreationDate).ToUniversalTime().ToString('o')
            workingSetBytes = [long]$cim.WorkingSetSize
            privateMemoryBytes = [long]$cim.PrivatePageCount
        }
        Write-G13R2V2AtomicUtf8NoBomJson -Path $externalPath -Value $query -Depth 10
    }
}

if (-not $process.HasExited) { Wait-Process -Id $process.Id }
$process.Refresh()
$exitCode = [int]$process.ExitCode
$completedAtUtc = [DateTime]::UtcNow
$compilerMatches = if (Test-Path -LiteralPath $unityLogPath) { @(Select-String -LiteralPath $unityLogPath -Pattern 'error CS\d+|Compilation failed|Scripts have compiler errors' -CaseSensitive:$false) } else { @() }
if ($exitCode -ne 0) { $wrapperErrors.Add("Unity exited with code $exitCode.") }
if ($compilerMatches.Count -gt 0) { $wrapperErrors.Add("Unity compiler errors: $($compilerMatches.Count).") }
$result = if (Test-Path -LiteralPath $resultPath -PathType Leaf) { Read-G13R2V2Json -Path $resultPath } else { $null }
if ($null -eq $result) { $wrapperErrors.Add('Telemetry probe result is missing.') }
else {
    if ($result.passed -ne $true) { $wrapperErrors.Add('Unity telemetry probe result did not pass.') }
    if ([long]$result.nativeBefore.workingSetBytes -le 0 -or [long]$result.nativeAfter.workingSetBytes -le 0 -or [long]$result.externalQuery.workingSetBytes -le 0) { $wrapperErrors.Add('Working-set cross-check contains a non-positive value.') }
    if ([long]$result.nativeBefore.privateMemoryBytes -le 0 -or [long]$result.nativeAfter.privateMemoryBytes -le 0 -or [long]$result.externalQuery.privateMemoryBytes -le 0) { $wrapperErrors.Add('Private-memory cross-check contains a non-positive value.') }
    if ($result.workingSetPassed -ne $true -or $result.privateMemoryPassed -ne $true -or $result.pidPassed -ne $true -or $result.executablePassed -ne $true -or $result.timestampOrderPassed -ne $true -or $result.creationTimePassed -ne $true) { $wrapperErrors.Add('One or more frozen telemetry cross-check assertions failed.') }
}
$passed = $wrapperErrors.Count -eq 0
$summary = [ordered]@{
    schemaVersion = 1
    summaryKind = 'gate13-r2-v2-telemetry-probe-wrapper-summary-v1'
    savedAtUtc = [DateTime]::UtcNow.ToString('o')
    outputDirectory = $OutputDirectory
    unityPath = $UnityPath
    unitySha256 = Get-G13R2V2LowerSha256 -Path $UnityPath
    unityProcessId = [int]$process.Id
    startedAtUtc = $startedAtUtc.ToString('o')
    completedAtUtc = $completedAtUtc.ToString('o')
    wallSeconds = ($completedAtUtc - $startedAtUtc).TotalSeconds
    exitCode = $exitCode
    compilerErrorMatchCount = $compilerMatches.Count
    readySha256 = if (Test-Path -LiteralPath $readyPath -PathType Leaf) { Get-G13R2V2LowerSha256 -Path $readyPath } else { $null }
    externalQuerySha256 = if (Test-Path -LiteralPath $externalPath -PathType Leaf) { Get-G13R2V2LowerSha256 -Path $externalPath } else { $null }
    resultSha256 = if (Test-Path -LiteralPath $resultPath -PathType Leaf) { Get-G13R2V2LowerSha256 -Path $resultPath } else { $null }
    errors = $wrapperErrors.ToArray()
    passed = $passed
    automaticRetryAttempted = $false
    automaticResumeAttempted = $false
    formalCampaign = $false
}
Write-G13R2V2AtomicUtf8NoBomJson -Path $summaryPath -Value $summary -Depth 20
if (-not $passed) { Write-Error "Gate 13-R2 v2 telemetry probe failed: $($wrapperErrors -join '; ')"; exit 1 }
Write-Host 'Gate 13-R2 v2 telemetry probe passed.' -ForegroundColor Green
exit 0
