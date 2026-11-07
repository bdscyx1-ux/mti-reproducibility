[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$ProjectPath,
    [Parameter(Mandatory = $true)][string]$OutputDirectory,
    [Parameter(Mandatory = $true)][string]$AllowedRoot,
    [string]$UnityPath = 'H:\UnityEditor\2022.3.30f1c1\Editor\Unity.exe',
    [switch]$BindingSmokeOnly,
    [int]$TimeoutSeconds = 600
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

function Read-JsonFile([string]$Path) { return (Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json) }
function Write-AtomicJson([string]$Path, [object]$Value) {
    $full = [IO.Path]::GetFullPath($Path)
    $parent = Split-Path -Parent $full
    if (-not (Test-Path -LiteralPath $parent -PathType Container)) { throw "Atomic parent is missing: $parent" }
    $temporary = Join-Path $parent ('.g13tmp-' + [Guid]::NewGuid().ToString('N'))
    try {
        [IO.File]::WriteAllText($temporary, (($Value | ConvertTo-Json -Depth 50) + "`n"), (New-Object Text.UTF8Encoding($false)))
        if (Test-Path -LiteralPath $full) { throw "Create-new JSON target already exists: $full" }
        [IO.File]::Move($temporary, $full)
    } finally {
        if (Test-Path -LiteralPath $temporary -PathType Leaf) { Remove-Item -LiteralPath $temporary -Force }
    }
}

if ([string]::IsNullOrWhiteSpace($ProjectPath) -or -not [IO.Path]::IsPathRooted($ProjectPath)) { throw 'An explicit absolute ProjectPath is required.' }
$ProjectPath = [IO.Path]::GetFullPath($ProjectPath)
if ($BindingSmokeOnly) { Write-Output "BINDING-SMOKE-PASSED|Run-Gate13RPR2MP2TelemetryProbeV1|$ProjectPath"; exit 0 }

$OutputDirectory = [IO.Path]::GetFullPath($OutputDirectory)
$AllowedRoot = [IO.Path]::GetFullPath($AllowedRoot).TrimEnd('\', '/')
$UnityPath = [IO.Path]::GetFullPath($UnityPath)
Import-Module (Join-Path $ProjectPath 'Research\Gate13RPR2MP2MemoryPolicyV2.psm1') -Force
Import-Module (Join-Path $ProjectPath 'Research\Gate10RLockHygieneV3.psm1') -Force
[void](Assert-G13RPR2MP2FormalAttempt3Absent -ProjectPath $ProjectPath)
$verificationBase = [IO.Path]::GetFullPath((Join-Path $ProjectPath 'Research\Verification\Gate13R_PR2_MP2')).TrimEnd('\', '/')
if (-not (Test-G13RPR2MP2PathWithin -BasePath $verificationBase -CandidatePath $AllowedRoot)) { throw 'AllowedRoot is outside the independent MP2 verification base.' }
if (-not (Test-G13RPR2MP2PathWithin -BasePath $AllowedRoot -CandidatePath $OutputDirectory)) { throw 'Telemetry output is outside AllowedRoot.' }
if (-not (Test-Path -LiteralPath $AllowedRoot -PathType Container)) { throw 'AllowedRoot must already exist.' }
if (Test-Path -LiteralPath $OutputDirectory) { throw "Create-new telemetry output exists: $OutputDirectory" }
if (@(Get-Process -Name Unity -ErrorAction SilentlyContinue).Count -gt 0 -or (Test-Path -LiteralPath (Join-Path $ProjectPath 'Temp\UnityLockfile'))) { throw 'Unity must be quiescent before telemetry validation.' }

$parent = Split-Path -Parent $OutputDirectory
if (-not (Test-Path -LiteralPath $parent -PathType Container)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
$unityLog = $OutputDirectory + '.Unity.log'
$stdoutPath = $OutputDirectory + '.wrapper.stdout.log'
$stderrPath = $OutputDirectory + '.wrapper.stderr.log'
$summaryPath = $OutputDirectory + '.summary.json'
$started = [DateTime]::UtcNow
$arguments = @(
    '-batchmode', '-nographics', '-quit',
    '-projectPath', ('"' + $ProjectPath + '"'),
    '-executeMethod', 'DDM.Research.Editor.Gate13RPR2FormalBatchCommandV5.ProbeTelemetry',
    '-ddmGate10RTelemetryProbeDirectory', ('"' + $OutputDirectory + '"'),
    '-logFile', ('"' + $unityLog + '"')
)
$process = Start-Process -FilePath $UnityPath -ArgumentList $arguments -WorkingDirectory (Split-Path -Parent $UnityPath) -WindowStyle Hidden -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath -PassThru
$readyPath = Join-Path $OutputDirectory 'telemetry-probe-ready.json'
$externalPath = Join-Path $OutputDirectory 'external-os-query.json'
$resultPath = Join-Path $OutputDirectory 'telemetry-probe-result.json'
$deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
while (-not (Test-Path -LiteralPath $readyPath -PathType Leaf) -and -not $process.HasExited -and [DateTime]::UtcNow -lt $deadline) { Start-Sleep -Milliseconds 100; $process.Refresh() }
$errors = New-Object Collections.Generic.List[string]
if (-not (Test-Path -LiteralPath $readyPath -PathType Leaf)) { [void]$errors.Add('ready-file-missing') }
else {
    $ready = Read-JsonFile $readyPath
    if ([int]$ready.nativeBefore.processId -ne [int]$process.Id) { [void]$errors.Add('ready-pid-mismatch') }
    $cim = Get-CimInstance Win32_Process -Filter ("ProcessId = {0}" -f [int]$process.Id) -ErrorAction SilentlyContinue
    if ($null -eq $cim) { [void]$errors.Add('cim-process-missing') }
    else {
        $query = [ordered]@{
            schemaVersion = 1
            queryKind = 'gate13r-pr2-mp2-independent-os-memory-query-v1'
            querySourceId = 'cim-win32_process-v1'
            queriedAtUtc = [DateTime]::UtcNow.ToString('o')
            processId = [int]$cim.ProcessId
            name = [string]$cim.Name
            executablePath = [string]$cim.ExecutablePath
            creationDateUtc = ([DateTime]$cim.CreationDate).ToUniversalTime().ToString('o')
            workingSetBytes = [long]$cim.WorkingSetSize
            privateMemoryBytes = [long]$cim.PrivatePageCount
        }
        Write-AtomicJson -Path $externalPath -Value $query
    }
}
if (-not $process.HasExited) {
    if ([DateTime]::UtcNow -ge $deadline) { & taskkill.exe /PID $process.Id /T /F 2>&1 | Out-Null; [void]$errors.Add('timeout') }
    else { Wait-Process -Id $process.Id }
}
try { $process.Refresh() } catch { }
$exitCode = if ($process.HasExited) { [int]$process.ExitCode } else { 124 }
$completed = [DateTime]::UtcNow
$lock = Invoke-Gate10RPostExitQuiescenceV3 -ProjectPath $ProjectPath -OwnedProcessId $process.Id -OwnedProcessStartedAt ([DateTimeOffset]$started) -OwnedProcessCompletedAt ([DateTimeOffset]$completed) -Role 'telemetry' -EvidenceDirectory ($OutputDirectory + '.lock-hygiene') -ContextId 'gate13r-pr2-mp2-telemetry-probe-v1' -QuiescenceSeconds 60 -PollMilliseconds 250 -TimestampToleranceSeconds 2
[void](Assert-G13RPR2MP2FormalAttempt3Absent -ProjectPath $ProjectPath)
$logText = if (Test-Path -LiteralPath $unityLog) { Get-Content -LiteralPath $unityLog -Raw -Encoding UTF8 } else { '' }
$compiler = if ($logText.Length -gt 0) { @($logText | Select-String -Pattern 'error CS\d+|Scripts have compiler errors|Compilation failed|executeMethod.+could not be found' -AllMatches -CaseSensitive:$false) } else { @() }
$serialAssigned = $logText.Contains('Serial number assigned to:')
$noValidLicense = $logText.Contains('No valid Unity Editor license found')
$inactiveHeadless = $logText.Contains('License is not active (com.unity.editor.headless)')
if ($exitCode -ne 0) { [void]$errors.Add("unity-exit-$exitCode") }
if (@($compiler).Count -gt 0) { [void]$errors.Add("compiler-$(@($compiler).Count)") }
if ($noValidLicense -or $inactiveHeadless) { [void]$errors.Add('license-entitlement') }
if ($null -eq $lock -or $lock.passed -ne $true -or [string]$lock.mode -ne 'natural-lock-absence') { [void]$errors.Add('lock-hygiene') }
$result = if (Test-Path -LiteralPath $resultPath -PathType Leaf) { Read-JsonFile $resultPath } else { $null }
if ($null -eq $result) { [void]$errors.Add('result-missing') }
elseif ($result.passed -ne $true -or $result.workingSetPassed -ne $true -or $result.privateMemoryPassed -ne $true -or $result.pidPassed -ne $true -or $result.executablePassed -ne $true -or $result.timestampOrderPassed -ne $true -or $result.creationTimePassed -ne $true) { [void]$errors.Add('psapi-cim-crosscheck') }
$summary = [ordered]@{
    schemaVersion = 1
    summaryKind = 'gate13r-pr2-mp2-validation-only-telemetry-probe-v1'
    savedAtUtc = [DateTime]::UtcNow.ToString('o')
    validationOnly = $true
    formalCampaign = $false
    unityProcessId = [int]$process.Id
    exitCode = $exitCode
    wallSeconds = ($completed - $started).TotalSeconds
    readySha256 = if (Test-Path -LiteralPath $readyPath) { Get-G13RPR2MP2Sha256 $readyPath } else { $null }
    externalQuerySha256 = if (Test-Path -LiteralPath $externalPath) { Get-G13RPR2MP2Sha256 $externalPath } else { $null }
    resultSha256 = if (Test-Path -LiteralPath $resultPath) { Get-G13RPR2MP2Sha256 $resultPath } else { $null }
    lockHygieneMode = if ($null -ne $lock) { [string]$lock.mode } else { $null }
    licenseSerialAssigned = $serialAssigned
    noValidLicenseError = $noValidLicense
    inactiveHeadlessLicenseError = $inactiveHeadless
    automaticRetryAttempted = $false
    automaticResumeAttempted = $false
    errors = $errors.ToArray()
    passed = $errors.Count -eq 0
}
Write-AtomicJson -Path $summaryPath -Value $summary
if ($errors.Count -gt 0) { Write-Error ('Gate 13R-PR2-MP2 telemetry probe failed: ' + ($errors -join '; ')); exit 1 }
Write-Host 'Gate 13R-PR2-MP2 validation-only telemetry probe passed.' -ForegroundColor Green
exit 0
