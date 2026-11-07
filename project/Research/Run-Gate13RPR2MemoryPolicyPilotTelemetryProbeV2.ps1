# Mechanically derived for Gate13R-PR2-MP1 attempt 2 / v2.
# Frozen source: Research/Run-Gate13RPR2MemoryPolicyPilotTelemetryProbeV1.ps1; SHA-256 52b5c419e5d39a821f58c026d195a69b8767c8af00cb5aafb87627b62d4b5e33.
# Allowed changes: v2 root/receipt/output routing and v2 path-safe atomic writer only.
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
Set-StrictMode -Version Latest
$ProjectPath = [IO.Path]::GetFullPath($ProjectPath)
if ($BindingSmokeOnly) { Write-Output "BINDING-SMOKE-PASSED|Run-Gate13RPR2MemoryPolicyPilotTelemetryProbeV2|$ProjectPath"; exit 0 }
$OutputDirectory = [IO.Path]::GetFullPath($OutputDirectory)
$AllowedRoot = [IO.Path]::GetFullPath($AllowedRoot).TrimEnd('\', '/')
$UnityPath = [IO.Path]::GetFullPath($UnityPath)
Import-Module (Join-Path $ProjectPath 'Research\Gate13RPR2MemoryPolicyPilotV1.psm1') -Force
Import-Module (Join-Path $ProjectPath 'Research\Gate13RPR2MemoryPolicyPilotV2.psm1') -Force
Import-Module (Join-Path $ProjectPath 'Research\Gate10RLockHygieneV3.psm1') -Force
$verificationBase = [IO.Path]::GetFullPath((Join-Path $ProjectPath 'Research\Verification\Gate13R_PR2_MP1_v2'))
if (-not (Test-G13RPR2MP1PathWithin -BasePath $verificationBase -CandidatePath $AllowedRoot -AllowBase)) { throw 'AllowedRoot is outside the MP1 verification base.' }
if (-not (Test-G13RPR2MP1PathWithin -BasePath $AllowedRoot -CandidatePath $OutputDirectory)) { throw 'Telemetry output is outside AllowedRoot.' }
if (Test-Path -LiteralPath $OutputDirectory) { throw "Create-new telemetry output exists: $OutputDirectory" }
if (Test-Path -LiteralPath (Join-Path $ProjectPath 'Research\PilotRuns\Gate13R_PR2_MemoryPolicy\v2')) { throw 'Measured MP1 pilot root must remain absent during telemetry preflight.' }
if (Test-Path -LiteralPath (Join-Path $ProjectPath 'Research\FormalRuns\Gate13R_RQAligned_S48H48\v3')) { throw 'Formal attempt-3 root must remain absent during telemetry preflight.' }
if (Test-Path -LiteralPath (Join-Path $ProjectPath 'Research\Gate13R_PR2_Formal_Execution_Receipt.v3.json')) { throw 'Formal attempt-3 receipt must remain absent during telemetry preflight.' }
if (@(Get-Process -Name Unity -ErrorAction SilentlyContinue).Count -gt 0 -or (Test-Path -LiteralPath (Join-Path $ProjectPath 'Temp\UnityLockfile'))) { throw 'Unity must be quiescent before telemetry preflight.' }

$unityLog = $OutputDirectory + '.Unity.log'
$stdoutPath = $OutputDirectory + '.wrapper.stdout.log'
$stderrPath = $OutputDirectory + '.wrapper.stderr.log'
$summaryPath = $OutputDirectory + '.summary.json'
$parent = Split-Path -Parent $OutputDirectory
if (-not (Test-Path -LiteralPath $parent -PathType Container)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
$started = [DateTime]::UtcNow
$arguments = @('-batchmode','-nographics','-quit','-projectPath',('"'+$ProjectPath+'"'),'-executeMethod','DDM.Research.Editor.Gate13RPR2MemoryPolicyPilotBatchCommandV1.ProbeTelemetry','-ddmGate10RTelemetryProbeDirectory',('"'+$OutputDirectory+'"'),'-logFile',('"'+$unityLog+'"'))
$process = Start-Process -FilePath $UnityPath -ArgumentList $arguments -WorkingDirectory (Split-Path -Parent $UnityPath) -WindowStyle Hidden -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath -PassThru
$readyPath = Join-Path $OutputDirectory 'telemetry-probe-ready.json'
$externalPath = Join-Path $OutputDirectory 'external-os-query.json'
$resultPath = Join-Path $OutputDirectory 'telemetry-probe-result.json'
$deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
while (-not (Test-Path -LiteralPath $readyPath -PathType Leaf) -and -not $process.HasExited -and [DateTime]::UtcNow -lt $deadline) { Start-Sleep -Milliseconds 100; $process.Refresh() }
$errors = New-Object Collections.Generic.List[string]
if (-not (Test-Path -LiteralPath $readyPath -PathType Leaf)) { $errors.Add('ready-file-missing') }
else {
    $ready = Read-G13RPR2MP1Json $readyPath
    if ([int]$ready.nativeBefore.processId -ne [int]$process.Id) { $errors.Add('ready-pid-mismatch') }
    $cim = Get-CimInstance Win32_Process -Filter ("ProcessId = {0}" -f [int]$process.Id) -ErrorAction SilentlyContinue
    if ($null -eq $cim) { $errors.Add('cim-process-missing') }
    else {
        $query = [ordered]@{
            schemaVersion = 1
            queryKind = 'gate13r-pr2-independent-os-memory-query-v1'
            querySourceId = 'cim-win32_process-v1'
            queriedAtUtc = [DateTime]::UtcNow.ToString('o')
            processId = [int]$cim.ProcessId
            name = [string]$cim.Name
            executablePath = [string]$cim.ExecutablePath
            creationDateUtc = ([DateTime]$cim.CreationDate).ToUniversalTime().ToString('o')
            workingSetBytes = [long]$cim.WorkingSetSize
            privateMemoryBytes = [long]$cim.PrivatePageCount
        }
        Write-G13RPR2MP1V2AtomicJson -Path $externalPath -Value $query -Depth 15
    }
}
if (-not $process.HasExited) {
    if ([DateTime]::UtcNow -ge $deadline) { & taskkill.exe /PID $process.Id /T /F 2>&1 | Out-Null; $errors.Add('timeout') }
    else { Wait-Process -Id $process.Id }
}
try { $process.Refresh() } catch { }
$exitCode = if ($process.HasExited) { [int]$process.ExitCode } else { 124 }
$completed = [DateTime]::UtcNow
$lock = Invoke-Gate10RPostExitQuiescenceV3 -ProjectPath $ProjectPath -OwnedProcessId $process.Id -OwnedProcessStartedAt ([DateTimeOffset]$started) -OwnedProcessCompletedAt ([DateTimeOffset]$completed) -Role 'telemetry' -EvidenceDirectory ($OutputDirectory+'.lock-hygiene') -ContextId 'gate13r-pr2-formal-telemetry-probe' -QuiescenceSeconds 60 -PollMilliseconds 250 -TimestampToleranceSeconds 2
$logText = if (Test-Path -LiteralPath $unityLog) { Read-G13RPR2MP1TextWithRetry -Path $unityLog -TimeoutMilliseconds 30000 -PollMilliseconds 250 } else { '' }
$compiler = if ($logText.Length) { @($logText | Select-String -Pattern 'error CS\d+|Scripts have compiler errors|Compilation failed|executeMethod.+could not be found' -AllMatches -CaseSensitive:$false) } else { @() }
$serialAssigned = $logText.Contains('Serial number assigned to:')
$noValidLicense = $logText.Contains('No valid Unity Editor license found')
$inactiveHeadless = $logText.Contains('License is not active (com.unity.editor.headless)')
if ($exitCode -ne 0) { $errors.Add("unity-exit-$exitCode") }
if (@($compiler).Count) { $errors.Add("compiler-$(@($compiler).Count)") }
if (-not $serialAssigned -or $noValidLicense -or $inactiveHeadless) { $errors.Add('license-entitlement') }
if ($null -eq $lock -or $lock.passed -ne $true -or [string]$lock.mode -ne 'natural-lock-absence') { $errors.Add('lock-hygiene') }
$result = if (Test-Path -LiteralPath $resultPath -PathType Leaf) { Read-G13RPR2MP1Json $resultPath } else { $null }
if ($null -eq $result) { $errors.Add('result-missing') }
elseif ($result.passed -ne $true -or $result.workingSetPassed -ne $true -or $result.privateMemoryPassed -ne $true -or $result.pidPassed -ne $true -or $result.executablePassed -ne $true -or $result.timestampOrderPassed -ne $true -or $result.creationTimePassed -ne $true) { $errors.Add('psapi-cim-crosscheck') }
$summary = [ordered]@{
    schemaVersion = 1; summaryKind = 'gate13r-pr2-mp1-telemetry-preflight-v2'; savedAtUtc = [DateTime]::UtcNow.ToString('o')
    unityProcessId = [int]$process.Id; exitCode = $exitCode; wallSeconds = ($completed-$started).TotalSeconds
    readySha256 = if (Test-Path $readyPath) { Get-G13RPR2MP1Sha256 $readyPath } else { $null }
    externalQuerySha256 = if (Test-Path $externalPath) { Get-G13RPR2MP1Sha256 $externalPath } else { $null }
    resultSha256 = if (Test-Path $resultPath) { Get-G13RPR2MP1Sha256 $resultPath } else { $null }
    lockHygieneMode = if ($null-ne$lock) { [string]$lock.mode } else { $null }
    licenseSerialAssigned = $serialAssigned; noValidLicenseError = $noValidLicense; inactiveHeadlessLicenseError = $inactiveHeadless
    formalCampaign = $false; excludedFromFormalAnalysis = $true; errors = $errors.ToArray(); passed = $errors.Count -eq 0
}
Write-G13RPR2MP1V2AtomicJson -Path $summaryPath -Value $summary -Depth 30
if ($errors.Count) { Write-Error ('Gate13R-PR2 telemetry preflight failed: '+($errors -join '; ')); exit 1 }
Write-Host 'Gate13R-PR2-MP1 telemetry preflight passed.' -ForegroundColor Green
exit 0
