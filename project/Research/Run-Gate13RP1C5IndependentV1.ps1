[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$ProjectPath,
    [ValidateSet('Validate','FormalPhaseA')][string]$Mode = 'Validate',
    [Parameter(Mandatory = $true)][ValidatePattern('^[0-9a-f]{64}$')][string]$ExecutionContractSha256,
    [string]$PythonPath = 'C:\Users\bdscy\AppData\Local\Python\pythoncore-3.14-64\python.exe',
    [string]$UnityPath = 'H:\UnityEditor\2022.3.30f1c1\Editor\Unity.exe',
    [string]$PreflightReportPath = '',
    [string]$PreflightReportSha256 = '',
    [int]$BlockTimeoutSeconds = 3600,
    [int]$OverallTimeoutSeconds = 64800,
    [string]$OutputPath = '',
    [switch]$BindingSmokeOnly,
    [switch]$EmitArgumentsOnly
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if ([string]::IsNullOrWhiteSpace($ProjectPath) -or -not [IO.Path]::IsPathRooted($ProjectPath)) { throw 'An explicit absolute ProjectPath is required.' }
$ProjectPath = [IO.Path]::GetFullPath($ProjectPath)
if ($BindingSmokeOnly) {
    Write-Output "BINDING-SMOKE-PASSED|Run-Gate13RP1C5IndependentV1|$Mode|$ProjectPath"
    exit 0
}
$PythonPath = [IO.Path]::GetFullPath($PythonPath)
$UnityPath = [IO.Path]::GetFullPath($UnityPath)
$orchestrator = Join-Path $ProjectPath 'Research\Gate13RP1C5IndependentExecutionV1.py'
foreach ($required in @($ProjectPath, $PythonPath, $orchestrator)) {
    if (-not (Test-Path -LiteralPath $required)) { throw "Required path does not exist: $required" }
}

if ($Mode -eq 'Validate') {
    $arguments = @($orchestrator, 'validate', '--project-root', $ProjectPath, '--contract-sha256', $ExecutionContractSha256)
    if (-not [string]::IsNullOrWhiteSpace($OutputPath)) { $arguments += @('--output', [IO.Path]::GetFullPath($OutputPath)) }
    if ($EmitArgumentsOnly) {
        [pscustomobject][ordered]@{schemaVersion=1;mode=$Mode;pythonPath=$PythonPath;arguments=$arguments;unityInvoked=$false;passed=$true} | ConvertTo-Json -Depth 10
        exit 0
    }
    & $PythonPath @arguments
    if ($LASTEXITCODE -ne 0) { throw "P1-C5 validation exited with code $LASTEXITCODE." }
    exit 0
}

if ($PSVersionTable.PSVersion.Major -ne 5 -or [string]$PSVersionTable.PSEdition -ne 'Desktop') { throw 'FormalPhaseA requires native Windows PowerShell 5.1 Desktop.' }
if ([string]::IsNullOrWhiteSpace($PreflightReportPath) -or -not [IO.Path]::IsPathRooted($PreflightReportPath)) { throw 'FormalPhaseA requires an explicit absolute PreflightReportPath.' }
if ($PreflightReportSha256 -notmatch '^[0-9a-f]{64}$') { throw 'FormalPhaseA requires the exact lowercase SHA-256 of the preflight report.' }
if ($BlockTimeoutSeconds -le 0 -or $OverallTimeoutSeconds -le 0) { throw 'Timeouts must be positive.' }
$PreflightReportPath = [IO.Path]::GetFullPath($PreflightReportPath)
foreach ($required in @($UnityPath, $PreflightReportPath)) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) { throw "Required formal runtime file does not exist: $required" }
}
$nativePowerShellPath = [IO.Path]::GetFullPath((Join-Path $PSHOME 'powershell.exe'))
$arguments = @(
    $orchestrator, 'run',
    '--project-root', $ProjectPath,
    '--contract-sha256', $ExecutionContractSha256,
    '--preflight-report', $PreflightReportPath,
    '--preflight-report-sha256', $PreflightReportSha256,
    '--unity-path', $UnityPath,
    '--powershell-path', $nativePowerShellPath,
    '--block-timeout-seconds', [string]$BlockTimeoutSeconds,
    '--overall-timeout-seconds', [string]$OverallTimeoutSeconds
)
if ($EmitArgumentsOnly) {
    [pscustomobject][ordered]@{
        schemaVersion = 1
        validationKind = 'gate13r-p1c5-independent-launcher-arguments-only-v1'
        mode = $Mode
        pythonPath = $PythonPath
        arguments = $arguments
        strictSerial = $true
        automaticRetryAuthorized = $false
        automaticResumeAuthorized = $false
        phaseBAnalysisAuthorized = $false
        gate14RAuthorized = $false
        m1ThroughM5Authorized = $false
        unityInvoked = $false
        passed = $true
    } | ConvertTo-Json -Depth 10
    exit 0
}

& $PythonPath @arguments
$runExit = $LASTEXITCODE
if ($runExit -ne 0) { throw "Gate 13R P1-C5 Phase A stopped fail-closed with exit code $runExit; no retry or resume was attempted." }
exit 0
