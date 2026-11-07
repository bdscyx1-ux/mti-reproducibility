[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$ProjectPath,
    [ValidateSet('Validate','NoLaunchDryRun','FormalAttempt4')][string]$Mode = 'Validate',
    [string]$PythonPath = 'C:\Users\bdscy\AppData\Local\Python\pythoncore-3.14-64\python.exe',
    [string]$UnityPath = 'H:\UnityEditor\2022.3.30f1c1\Editor\Unity.exe',
    [string]$PrelaunchFinalAuditPath = '',
    [int]$GlobalProcessOrdinal = 1,
    [string]$OutputPath = '',
    [int]$BlockTimeoutSeconds = 3600,
    [int]$ResumeQuiescenceTimeoutSeconds = 3600,
    [switch]$BindingSmokeOnly,
    [switch]$EmitArgumentsOnly
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if ([string]::IsNullOrWhiteSpace($ProjectPath) -or -not [IO.Path]::IsPathRooted($ProjectPath)) { throw 'An explicit absolute ProjectPath is required.' }
$ProjectPath = [IO.Path]::GetFullPath($ProjectPath)
if ($BindingSmokeOnly) {
    Write-Output "BINDING-SMOKE-PASSED|Run-Gate13RPR2FormalAttempt4V1|$Mode|$ProjectPath"
    exit 0
}
$PythonPath = [IO.Path]::GetFullPath($PythonPath)
$UnityPath = [IO.Path]::GetFullPath($UnityPath)
$orchestrator = Join-Path $ProjectPath 'Research\Gate13RPR2Attempt4ExecutionV1.py'
foreach ($required in @($ProjectPath, $PythonPath, $orchestrator)) { if (-not (Test-Path -LiteralPath $required)) { throw "Required path does not exist: $required" } }

if ($Mode -eq 'Validate') {
    $arguments = @($orchestrator, 'validate', '--project-root', $ProjectPath)
    if (-not [string]::IsNullOrWhiteSpace($OutputPath)) { $arguments += @('--output', [IO.Path]::GetFullPath($OutputPath)) }
    if ($EmitArgumentsOnly) { [pscustomobject]@{schemaVersion=1;mode=$Mode;pythonPath=$PythonPath;arguments=$arguments;unityInvoked=$false;passed=$true} | ConvertTo-Json -Depth 10; exit 0 }
    & $PythonPath @arguments
    if ($LASTEXITCODE -ne 0) { throw "Gate13R-PR2 attempt-4 validation exited with code $LASTEXITCODE." }
    exit 0
}

if ($Mode -eq 'NoLaunchDryRun') {
    $arguments = @($orchestrator, 'plan', '--project-root', $ProjectPath, '--ordinal', [string]$GlobalProcessOrdinal)
    if (-not [string]::IsNullOrWhiteSpace($OutputPath)) { $arguments += @('--output', [IO.Path]::GetFullPath($OutputPath)) }
    if ($EmitArgumentsOnly) { [pscustomobject]@{schemaVersion=1;mode=$Mode;pythonPath=$PythonPath;arguments=$arguments;unityInvoked=$false;passed=$true} | ConvertTo-Json -Depth 10; exit 0 }
    & $PythonPath @arguments
    if ($LASTEXITCODE -ne 0) { throw "Gate13R-PR2 attempt-4 plan generation exited with code $LASTEXITCODE." }
    exit 0
}

$expectedNativeModulePath = @(
    'C:\Users\bdscy\Documents\WindowsPowerShell\Modules',
    'C:\Program Files\WindowsPowerShell\Modules',
    'C:\WINDOWS\System32\WindowsPowerShell\v1.0\Modules'
) -join ';'
if ($PSVersionTable.PSVersion.Major -ne 5 -or [string]$PSVersionTable.PSEdition -ne 'Desktop') { throw 'FormalAttempt4 mode requires native Windows PowerShell 5.1 Desktop.' }
if ([string]$env:PSModulePath -ne $expectedNativeModulePath) { throw 'FormalAttempt4 mode requires the verified native Windows PowerShell 5.1 PSModulePath.' }
if ([string]::IsNullOrWhiteSpace($PrelaunchFinalAuditPath) -or -not [IO.Path]::IsPathRooted($PrelaunchFinalAuditPath)) { throw 'FormalAttempt4 mode requires an explicit absolute PrelaunchFinalAuditPath.' }
$PrelaunchFinalAuditPath = [IO.Path]::GetFullPath($PrelaunchFinalAuditPath)
foreach ($required in @($UnityPath, $PrelaunchFinalAuditPath)) { if (-not (Test-Path -LiteralPath $required -PathType Leaf)) { throw "Required formal runtime file does not exist: $required" } }
$nativePowerShellPath = [IO.Path]::GetFullPath((Join-Path $PSHOME 'powershell.exe'))
$runArguments = @(
    $orchestrator, 'run', '--project-root', $ProjectPath,
    '--prelaunch-final-audit', $PrelaunchFinalAuditPath,
    '--unity-path', $UnityPath,
    '--powershell-path', $nativePowerShellPath,
    '--block-timeout-seconds', [string]$BlockTimeoutSeconds,
    '--resume-quiescence-timeout-seconds', [string]$ResumeQuiescenceTimeoutSeconds
)
if ($EmitArgumentsOnly) {
    [pscustomobject][ordered]@{
        schemaVersion = 1
        validationKind = 'gate13r-pr2-formal-attempt4-launcher-arguments-only-v1'
        mode = $Mode
        pythonPath = $PythonPath
        arguments = $runArguments
        supervisorMaximumAutomaticResumes = 3
        automaticMeasuredRetryAuthorized = $false
        unityInvoked = $false
        passed = $true
    } | ConvertTo-Json -Depth 10
    exit 0
}

$automaticResumeAttempts = 0
while ($true) {
    & $PythonPath @runArguments
    $runExit = $LASTEXITCODE
    if ($runExit -eq 0) { exit 0 }
    if ($automaticResumeAttempts -ge 3) { throw "Gate13R-PR2 attempt-4 exhausted three bounded automatic resumes; last exit code $runExit." }
    $inspectArguments = @(
        $orchestrator, 'inspect-resume', '--project-root', $ProjectPath,
        '--resume-quiescence-timeout-seconds', [string]$ResumeQuiescenceTimeoutSeconds
    )
    & $PythonPath @inspectArguments
    if ($LASTEXITCODE -ne 0) { throw "Gate13R-PR2 attempt-4 is not safe for automatic resume after exit code $runExit." }
    $automaticResumeAttempts += 1
    Start-Sleep -Seconds 5
}
