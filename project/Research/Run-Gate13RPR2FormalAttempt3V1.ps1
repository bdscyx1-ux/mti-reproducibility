[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$ProjectPath,
    [ValidateSet('Validate','NoLaunchDryRun','FormalAttempt3')][string]$Mode = 'Validate',
    [string]$PythonPath = 'C:\Users\bdscy\AppData\Local\Python\bin\python.exe',
    [string]$UnityPath = 'H:\UnityEditor\2022.3.30f1c1\Editor\Unity.exe',
    [string]$PrelaunchFinalAuditPath = '',
    [int]$GlobalProcessOrdinal = 1,
    [string]$OutputPath = '',
    [int]$BlockTimeoutSeconds = 3600,
    [switch]$BindingSmokeOnly
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if ([string]::IsNullOrWhiteSpace($ProjectPath) -or -not [IO.Path]::IsPathRooted($ProjectPath)) {
    throw 'An explicit absolute ProjectPath is required.'
}
$ProjectPath = [IO.Path]::GetFullPath($ProjectPath)
if ($BindingSmokeOnly) {
    Write-Output "BINDING-SMOKE-PASSED|Run-Gate13RPR2FormalAttempt3V1|$Mode|$ProjectPath"
    exit 0
}
$PythonPath = [IO.Path]::GetFullPath($PythonPath)
$UnityPath = [IO.Path]::GetFullPath($UnityPath)
$orchestrator = Join-Path $ProjectPath 'Research\Gate13RPR2Attempt3ExecutionV1.py'
foreach ($required in @($ProjectPath, $PythonPath, $orchestrator)) {
    if (-not (Test-Path -LiteralPath $required)) { throw "Required path does not exist: $required" }
}

$arguments = New-Object Collections.Generic.List[string]
if ($Mode -eq 'Validate') {
    foreach ($value in @($orchestrator, 'validate', '--project-root', $ProjectPath)) { [void]$arguments.Add($value) }
    if (-not [string]::IsNullOrWhiteSpace($OutputPath)) {
        [void]$arguments.Add('--output')
        [void]$arguments.Add([IO.Path]::GetFullPath($OutputPath))
    }
} elseif ($Mode -eq 'NoLaunchDryRun') {
    foreach ($value in @($orchestrator, 'plan', '--project-root', $ProjectPath, '--ordinal', [string]$GlobalProcessOrdinal)) { [void]$arguments.Add($value) }
    if (-not [string]::IsNullOrWhiteSpace($OutputPath)) {
        [void]$arguments.Add('--output')
        [void]$arguments.Add([IO.Path]::GetFullPath($OutputPath))
    }
} else {
    $expectedNativeModulePath = @(
        'C:\Users\bdscy\Documents\WindowsPowerShell\Modules',
        'C:\Program Files\WindowsPowerShell\Modules',
        'C:\WINDOWS\System32\WindowsPowerShell\v1.0\Modules'
    ) -join ';'
    if ($PSVersionTable.PSVersion.Major -ne 5 -or [string]$PSVersionTable.PSEdition -ne 'Desktop') {
        throw 'FormalAttempt3 mode requires native Windows PowerShell 5.1 Desktop.'
    }
    if ([string]$env:PSModulePath -ne $expectedNativeModulePath) {
        throw 'FormalAttempt3 mode requires the verified native Windows PowerShell 5.1 PSModulePath.'
    }
    if ([string]::IsNullOrWhiteSpace($PrelaunchFinalAuditPath) -or -not [IO.Path]::IsPathRooted($PrelaunchFinalAuditPath)) {
        throw 'FormalAttempt3 mode requires an explicit absolute PrelaunchFinalAuditPath.'
    }
    $PrelaunchFinalAuditPath = [IO.Path]::GetFullPath($PrelaunchFinalAuditPath)
    foreach ($required in @($UnityPath, $PrelaunchFinalAuditPath)) {
        if (-not (Test-Path -LiteralPath $required -PathType Leaf)) { throw "Required formal runtime file does not exist: $required" }
    }
    foreach ($value in @(
        $orchestrator,
        'run',
        '--project-root', $ProjectPath,
        '--prelaunch-final-audit', $PrelaunchFinalAuditPath,
        '--unity-path', $UnityPath,
        '--powershell-path', $PSHOME + '\powershell.exe',
        '--block-timeout-seconds', [string]$BlockTimeoutSeconds
    )) { [void]$arguments.Add($value) }
}

& $PythonPath @arguments
if ($LASTEXITCODE -ne 0) { throw "Gate13R-PR2 attempt-3 orchestrator exited with code $LASTEXITCODE." }
