[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$ProjectPath,
    [Parameter(Mandatory = $true)][string]$VerificationRoot,
    [string]$UnityPath = 'H:\UnityEditor\2022.3.30f1c1\Editor\Unity.exe',
    [switch]$BindingSmokeOnly,
    [int]$TimeoutSeconds = 1200
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if ([string]::IsNullOrWhiteSpace($ProjectPath) -or -not [IO.Path]::IsPathRooted($ProjectPath)) { throw 'Gate13R compile wrapper requires an explicit absolute ProjectPath.' }
$ProjectPath = [IO.Path]::GetFullPath($ProjectPath)
if ($BindingSmokeOnly) { Write-Output "BINDING-SMOKE-PASSED|Run-Gate13RCompileV1|$ProjectPath"; exit 0 }
Import-Module (Join-Path $ProjectPath 'Research\Gate13RFormalPreparationV1.psm1') -Force
Import-Module (Join-Path $ProjectPath 'Research\Gate10RLockHygieneV3.psm1') -Force

$VerificationRoot = [IO.Path]::GetFullPath($VerificationRoot)
$UnityPath = [IO.Path]::GetFullPath($UnityPath)
$verificationBase = [IO.Path]::GetFullPath((Join-Path $ProjectPath 'Research\Verification\Gate13R_NonExecuting_Preparation'))
$formalRoot = [IO.Path]::GetFullPath((Join-Path $ProjectPath 'Research\FormalRuns\Gate13R_ProcessReuse_5pct\v1'))
if (-not (Test-G13RPathWithin -BasePath $verificationBase -CandidatePath $VerificationRoot)) { throw 'VerificationRoot is outside the Gate13R versioned verification base.' }
if (Test-Path -LiteralPath $formalRoot) { throw 'Reserved Gate13R formal root must remain absent during compile.' }
if (-not (Test-Path -LiteralPath $UnityPath -PathType Leaf)) { throw 'Unity executable is missing.' }
if (@(Get-Process -Name Unity -ErrorAction SilentlyContinue).Count -gt 0 -or (Test-Path -LiteralPath (Join-Path $ProjectPath 'Temp\UnityLockfile'))) { throw 'Unity must be closed and project lock absent before compile.' }

$output = Join-Path $VerificationRoot 'Compile'
if (Test-Path -LiteralPath $output) { throw 'Create-new Gate13R compile output already exists.' }
New-Item -ItemType Directory -Path $output | Out-Null
$logPath = Join-Path $output 'Gate13R.Unity.log'
$summaryPath = Join-Path $output 'summary.json'
$started = Get-Date
$arguments = @('-batchmode', '-nographics', '-quit', '-projectPath', ('"' + $ProjectPath + '"'), '-logFile', ('"' + $logPath + '"'))
$process = Start-Process -FilePath $UnityPath -ArgumentList $arguments -WorkingDirectory (Split-Path -Parent $UnityPath) -WindowStyle Hidden -PassThru
$timedOut = $false
$deadline = (Get-Date).AddSeconds($TimeoutSeconds)
while (-not $process.HasExited) {
    if ((Get-Date) -ge $deadline) { $timedOut = $true; break }
    Start-Sleep -Milliseconds 500
    $process.Refresh()
}
if ($timedOut) {
    & taskkill.exe /PID $process.Id /T /F 2>&1 | Out-Null
    try { Wait-Process -Id $process.Id -Timeout 30 -ErrorAction SilentlyContinue } catch { }
}
$process.Refresh()
$exitCode = if ($timedOut) { 124 } else { [int]$process.ExitCode }
$completed = Get-Date
$lock = Invoke-Gate10RPostExitQuiescenceV3 -ProjectPath $ProjectPath -OwnedProcessId $process.Id -OwnedProcessStartedAt ([DateTimeOffset]$started) -OwnedProcessCompletedAt ([DateTimeOffset]$completed) -Role 'compile' -EvidenceDirectory (Join-Path $output 'LockHygiene') -ContextId 'gate13r-compile-v1' -QuiescenceSeconds 60 -PollMilliseconds 250 -TimestampToleranceSeconds 2
$matches = @()
if (Test-Path -LiteralPath $logPath) { $matches = @(Select-String -LiteralPath $logPath -Pattern 'error CS\d+|Scripts have compiler errors|Compilation failed|executeMethod.+could not be found' -CaseSensitive:$false) }
$errors = New-Object Collections.Generic.List[string]
if ($timedOut) { $errors.Add("Hard timeout after $TimeoutSeconds seconds.") }
if ($exitCode -ne 0) { $errors.Add("Unity exit code $exitCode.") }
if (-not (Test-Path -LiteralPath $logPath -PathType Leaf)) { $errors.Add('Unity compile log missing.') }
if ($matches.Count -gt 0) { $errors.Add("Compiler/error pattern count: $($matches.Count).") }
if ($null -eq $lock -or $lock.passed -ne $true -or [string]$lock.mode -ne 'natural-lock-absence') { $errors.Add('Post-compile lock hygiene did not pass naturally.') }
$commandPath = Join-Path $ProjectPath 'Assets\_Scripts\Research\Editor\Gate13RProcessReuseFormalBatchCommandV1.cs'
$summary = [ordered]@{
    schemaVersion = 1
    summaryKind = 'gate13r-unity-compilation-v1'
    savedAtUtc = [DateTime]::UtcNow.ToString('o')
    unityPath = $UnityPath
    unitySha256 = Get-G13RLowerSha256 $UnityPath
    unityProcessId = [int]$process.Id
    startedAt = $started.ToString('o')
    completedAt = $completed.ToString('o')
    wallSeconds = ($completed - $started).TotalSeconds
    exitCode = $exitCode
    timedOut = $timedOut
    compilerErrorMatchCount = $matches.Count
    logSha256 = if (Test-Path -LiteralPath $logPath) { Get-G13RLowerSha256 $logPath } else { $null }
    unityCommandSha256 = Get-G13RLowerSha256 $commandPath
    lockHygieneMode = if ($null -ne $lock) { [string]$lock.mode } else { $null }
    formalCampaign = $false
    errors = $errors.ToArray()
    passed = $errors.Count -eq 0
}
Write-G13RAtomicUtf8NoBomJson -Path $summaryPath -Value $summary -Depth 20
if ($errors.Count -gt 0) { Write-Error ('Gate13R Unity compilation failed: ' + ($errors -join '; ')); exit 1 }
Write-Host 'Gate13R Unity compilation passed.' -ForegroundColor Green
exit 0
