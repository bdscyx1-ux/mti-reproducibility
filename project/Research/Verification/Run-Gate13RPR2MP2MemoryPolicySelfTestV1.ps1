[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$ProjectPath,
    [Parameter(Mandatory = $true)][string]$AttemptRoot,
    [string]$UnityPath = 'H:\UnityEditor\2022.3.30f1c1\Editor\Unity.exe',
    [switch]$BindingSmokeOnly,
    [int]$TimeoutSeconds = 900
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

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
if ($BindingSmokeOnly) {
    Write-Output "BINDING-SMOKE-PASSED|Run-Gate13RPR2MP2MemoryPolicySelfTestV1|$ProjectPath"
    exit 0
}

$AttemptRoot = [IO.Path]::GetFullPath($AttemptRoot)
$UnityPath = [IO.Path]::GetFullPath($UnityPath)
Import-Module (Join-Path $ProjectPath 'Research\Gate13RPR2MP2MemoryPolicyV2.psm1') -Force
Import-Module (Join-Path $ProjectPath 'Research\Gate10RLockHygieneV3.psm1') -Force
[void](Assert-G13RPR2MP2FormalAttempt3Absent -ProjectPath $ProjectPath)
$verificationRoot = [IO.Path]::GetFullPath((Join-Path $ProjectPath 'Research\Verification\Gate13R_PR2_MP2')).TrimEnd('\', '/')
if (-not (Test-G13RPR2MP2PathWithin -BasePath $verificationRoot -CandidatePath $AttemptRoot)) { throw 'AttemptRoot must remain within the independent MP2 verification root.' }
if (-not (Test-Path -LiteralPath $AttemptRoot -PathType Container)) { throw 'AttemptRoot must already exist.' }
if (-not (Test-Path -LiteralPath $UnityPath -PathType Leaf)) { throw 'Unity executable is missing.' }
if (@(Get-Process -Name Unity -ErrorAction SilentlyContinue).Count -gt 0 -or (Test-Path -LiteralPath (Join-Path $ProjectPath 'Temp\UnityLockfile'))) { throw 'Unity must be closed and the project lock must be absent before the validation-only self-test.' }

$resultRoot = Join-Path $AttemptRoot 'unity-memory-policy-self-test'
if (Test-Path -LiteralPath $resultRoot) { throw "Create-new validation root already exists: $resultRoot" }
$unityLog = $resultRoot + '.Unity.log'
$stdout = $resultRoot + '.stdout.log'
$stderr = $resultRoot + '.stderr.log'
$summaryPath = $resultRoot + '.summary.json'
$started = Get-Date
$arguments = @(
    '-batchmode', '-nographics', '-quit',
    '-projectPath', ('"' + $ProjectPath + '"'),
    '-executeMethod', 'DDM.Research.Editor.Gate13RPR2FormalBatchCommandV5.RunMemoryPolicySelfTest',
    '-ddmGate13RPR2MP2MemoryPolicyTestDirectory', ('"' + $resultRoot + '"'),
    '-logFile', ('"' + $unityLog + '"')
)
$process = Start-Process -FilePath $UnityPath -ArgumentList $arguments -WorkingDirectory (Split-Path -Parent $UnityPath) -WindowStyle Hidden -RedirectStandardOutput $stdout -RedirectStandardError $stderr -PassThru
$deadline = (Get-Date).AddSeconds($TimeoutSeconds)
$timedOut = $false
while (-not $process.HasExited) {
    if ((Get-Date) -ge $deadline) { $timedOut = $true; break }
    Start-Sleep -Milliseconds 250
    $process.Refresh()
}
if ($timedOut) {
    & taskkill.exe /PID $process.Id /T /F 2>&1 | Out-Null
    try { Wait-Process -Id $process.Id -Timeout 30 -ErrorAction SilentlyContinue } catch { }
}
$process.Refresh()
$processId = [int]$process.Id
$exitCode = if ($timedOut) { 124 } else { [int]$process.ExitCode }
$completed = Get-Date
try { $process.Dispose() } catch { }

$lock = Invoke-Gate10RPostExitQuiescenceV3 -ProjectPath $ProjectPath -OwnedProcessId $processId -OwnedProcessStartedAt ([DateTimeOffset]$started) -OwnedProcessCompletedAt ([DateTimeOffset]$completed) -Role 'positive' -EvidenceDirectory ($resultRoot + '.lock-hygiene') -ContextId 'gate13r-pr2-mp2-memory-policy-self-test-v1' -QuiescenceSeconds 60 -PollMilliseconds 250 -TimestampToleranceSeconds 2
[void](Assert-G13RPR2MP2FormalAttempt3Absent -ProjectPath $ProjectPath)

$resultPath = Join-Path $resultRoot 'memory-policy-self-test.json'
$result = if (Test-Path -LiteralPath $resultPath -PathType Leaf) { Get-Content -LiteralPath $resultPath -Raw -Encoding UTF8 | ConvertFrom-Json } else { $null }
$logText = if (Test-Path -LiteralPath $unityLog -PathType Leaf) { Get-Content -LiteralPath $unityLog -Raw -Encoding UTF8 } else { '' }
$compilerMatches = if ($logText.Length -gt 0) { @($logText | Select-String -Pattern 'error CS\d+|Compilation failed|Scripts have compiler errors|executeMethod.+could not be found' -AllMatches -CaseSensitive:$false) } else { @() }
$errors = New-Object Collections.Generic.List[string]
if ($exitCode -ne 0) { [void]$errors.Add("unity-exit-$exitCode") }
if ($timedOut) { [void]$errors.Add('unity-timeout') }
if (@($compilerMatches).Count -gt 0) { [void]$errors.Add("compiler-patterns-$(@($compilerMatches).Count)") }
if ($logText.Contains('No valid Unity Editor license found') -or $logText.Contains('License is not active (com.unity.editor.headless)')) { [void]$errors.Add('unity-license-hard-failure') }
if ($null -eq $result -or $result.passed -ne $true -or [int]$result.testCount -ne 22 -or [int]$result.passedTestCount -ne 22 -or [int]$result.telemetryValidationTestCount -ne 8 -or [int]$result.telemetryValidationPassedTestCount -ne 8) { [void]$errors.Add('memory-policy-self-test-result-missing-or-incomplete') }
if ($null -eq $lock -or $lock.passed -ne $true -or [string]$lock.mode -ne 'natural-lock-absence') { [void]$errors.Add('post-exit-lock-hygiene') }

$summary = [ordered]@{
    schemaVersion = 1
    summaryKind = 'gate13r-pr2-mp2-memory-policy-unity-self-test-wrapper-v1'
    savedAtUtc = [DateTime]::UtcNow.ToString('o')
    validationOnly = $true
    formalCampaign = $false
    commandClass = 'DDM.Research.Editor.Gate13RPR2FormalBatchCommandV5'
    unityProcessId = $processId
    exitCode = $exitCode
    timedOut = $timedOut
    wallSeconds = ($completed - $started).TotalSeconds
    fixtureCount = if ($null -ne $result) { [int]$result.testCount } else { 0 }
    fixturePassedCount = if ($null -ne $result) { [int]$result.passedTestCount } else { 0 }
    telemetryValidationFixtureCount = if ($null -ne $result) { [int]$result.telemetryValidationTestCount } else { 0 }
    telemetryValidationPassedFixtureCount = if ($null -ne $result) { [int]$result.telemetryValidationPassedTestCount } else { 0 }
    resultSha256 = if (Test-Path -LiteralPath $resultPath -PathType Leaf) { Get-G13RPR2MP2Sha256 $resultPath } else { $null }
    lockHygieneMode = if ($null -ne $lock) { [string]$lock.mode } else { $null }
    automaticRetryAttempted = $false
    automaticResumeAttempted = $false
    errors = $errors.ToArray()
    passed = $errors.Count -eq 0
}
Write-AtomicJson -Path $summaryPath -Value $summary
if ($errors.Count -gt 0) { Write-Error ('Gate 13R-PR2-MP2 Unity memory-policy self-test failed: ' + ($errors -join '; ')); exit 1 }
Write-Host 'Gate 13R-PR2-MP2 validation-only Unity memory-policy self-test passed.' -ForegroundColor Green
exit 0
