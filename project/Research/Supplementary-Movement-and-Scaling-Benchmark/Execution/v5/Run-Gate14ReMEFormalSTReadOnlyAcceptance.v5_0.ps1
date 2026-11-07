[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$ProjectRoot,
    [Parameter(Mandatory)][string]$RawRoot,
    [Parameter(Mandatory)][string]$AcceptanceOutputRoot,
    [Parameter(Mandatory)][string]$AcceptanceContract,
    [Parameter(Mandatory)][ValidatePattern('^[0-9a-f]{64}$')][string]$AcceptanceContractSha256,
    [Parameter(Mandatory)][string]$AcquisitionContract,
    [Parameter(Mandatory)][ValidatePattern('^[0-9a-f]{64}$')][string]$AcquisitionContractSha256,
    [Parameter(Mandatory)][string]$AcceptanceTool,
    [Parameter(Mandatory)][ValidatePattern('^[0-9a-f]{64}$')][string]$AcceptanceToolSha256,
    [Parameter(Mandatory)][string]$RawOutputContract,
    [Parameter(Mandatory)][ValidatePattern('^[0-9a-f]{64}$')][string]$RawOutputContractSha256,
    [Parameter(Mandatory)][string]$Schedule,
    [Parameter(Mandatory)][ValidatePattern('^[0-9a-f]{64}$')][string]$ScheduleSha256,
    [Parameter(Mandatory)][string]$PythonExecutable,
    [Parameter(Mandatory)][ValidatePattern('^[0-9a-f]{64}$')][string]$PythonExecutableSha256,
    [Parameter(Mandatory)][string]$TypedParquetRuntimeManifest,
    [Parameter(Mandatory)][ValidatePattern('^[0-9a-f]{64}$')][string]$TypedParquetRuntimeManifestSha256,
    [Parameter(Mandatory)][string]$PyArrowRoot,
    [ValidateRange(256, 65536)][int]$BatchSize = 4096
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Require-Condition([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw [System.InvalidOperationException]::new($Message) }
}

function Resolve-FullPath([string]$Path, [string]$Base) {
    if ([System.IO.Path]::IsPathRooted($Path)) { return [System.IO.Path]::GetFullPath($Path) }
    return [System.IO.Path]::GetFullPath((Join-Path $Base $Path))
}

function Get-Sha256Lower([string]$Path) {
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Assert-FileHash([string]$Path, [string]$Expected, [string]$Label) {
    Require-Condition (Test-Path -LiteralPath $Path -PathType Leaf) "$Label is missing: $Path"
    $actual = Get-Sha256Lower $Path
    Require-Condition ($actual -ceq $Expected) "$Label SHA-256 mismatch: expected=$Expected actual=$actual"
}

function Read-Json([string]$Path) {
    return Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json -Depth 100 -DateKind String
}

function Get-TreeMetadataDigest([string]$Root) {
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $builder = [System.Text.StringBuilder]::new()
        Get-ChildItem -LiteralPath $Root -File -Recurse | Sort-Object FullName | ForEach-Object {
            $relative = [System.IO.Path]::GetRelativePath($Root, $_.FullName).Replace('\', '/')
            $null = $builder.Append($relative).Append('|').Append($_.Length).Append('|').Append($_.LastWriteTimeUtc.Ticks).Append("`n")
        }
        return [Convert]::ToHexString($sha.ComputeHash([System.Text.UTF8Encoding]::new($false).GetBytes($builder.ToString()))).ToLowerInvariant()
    }
    finally { $sha.Dispose() }
}

$project = Resolve-FullPath $ProjectRoot (Get-Location).Path
Require-Condition (Test-Path -LiteralPath $project -PathType Container) 'Project root is missing.'
$raw = Resolve-FullPath $RawRoot $project
$output = Resolve-FullPath $AcceptanceOutputRoot $project
Require-Condition (Test-Path -LiteralPath $raw -PathType Container) 'Sealed formal acquisition root is missing.'
Require-Condition (-not (Test-Path -LiteralPath $output)) 'Acceptance output root must be fresh.'

$contractPath = Resolve-FullPath $AcceptanceContract $project
$acquisitionPath = Resolve-FullPath $AcquisitionContract $project
$toolPath = Resolve-FullPath $AcceptanceTool $project
$rawContractPath = Resolve-FullPath $RawOutputContract $project
$schedulePath = Resolve-FullPath $Schedule $project
$pythonPath = Resolve-FullPath $PythonExecutable $project
$runtimeManifestPath = Resolve-FullPath $TypedParquetRuntimeManifest $project
$pyArrowPath = Resolve-FullPath $PyArrowRoot $project

Assert-FileHash $contractPath $AcceptanceContractSha256 'formal ST acceptance contract v5'
Assert-FileHash $acquisitionPath $AcquisitionContractSha256 'formal ST acquisition contract v5'
Assert-FileHash $toolPath $AcceptanceToolSha256 'formal ST acceptance tool v5'
Assert-FileHash $rawContractPath $RawOutputContractSha256 'formal ST raw-output contract v5'
Assert-FileHash $schedulePath $ScheduleSha256 'formal ST frozen schedule'
Assert-FileHash $pythonPath $PythonExecutableSha256 'frozen Python runtime'
Assert-FileHash $runtimeManifestPath $TypedParquetRuntimeManifestSha256 'typed-Parquet runtime manifest'
Require-Condition (Test-Path -LiteralPath $pyArrowPath -PathType Container) 'Frozen PyArrow package root is missing.'

$contract = Read-Json $contractPath
$acquisitionContractObject = Read-Json $acquisitionPath
Require-Condition ($contract.schema -eq 'gate14re-me-formal-st-independent-acceptance-contract-v5' -and $contract.status -eq 'FROZEN_FORMAL_ST_V5_READ_ONLY_ACCEPTANCE') 'Acceptance contract header is invalid.'
Require-Condition ($acquisitionContractObject.schema -eq 'gate14re-me-formal-st-acquisition-contract-v5') 'Acquisition contract header is invalid.'
Require-Condition ([int]$contract.parquetBatchRows -eq $BatchSize) 'Parquet batch size differs from the frozen contract.'
Require-Condition ([string]$contract.entryPoint.launcherRelativePath -ceq [System.IO.Path]::GetRelativePath($project, $PSCommandPath).Replace('\', '/')) 'Acceptance launcher path self-binding mismatch.'
Assert-FileHash $PSCommandPath ([string]$contract.entryPoint.launcherSha256) 'formal ST acceptance launcher self-binding'
Require-Condition ([string]$contract.entryPoint.toolSha256 -ceq $AcceptanceToolSha256) 'Acceptance tool contract binding mismatch.'
Require-Condition ([string]$contract.rawOutputContract.sha256 -ceq $RawOutputContractSha256) 'Raw-output contract binding mismatch.'
Require-Condition ([string]$contract.acquisitionContract.sha256 -ceq $AcquisitionContractSha256) 'Acquisition contract binding mismatch.'

$sealManifest = Join-Path $raw '_control/acquisition-freeze-manifest.v5.json'
$sealTerminal = Join-Path $raw '_control/acquisition-terminal-receipt.v5.json'
Require-Condition (Test-Path -LiteralPath $sealManifest -PathType Leaf) 'Acquisition freeze manifest is missing.'
Require-Condition (Test-Path -LiteralPath $sealTerminal -PathType Leaf) 'Acquisition terminal receipt is missing.'
$sealManifestSha = Get-Sha256Lower $sealManifest
$sealTerminalSha = Get-Sha256Lower $sealTerminal
$beforeDigest = Get-TreeMetadataDigest $raw

$arguments = @(
    $toolPath,
    '--project-root', $project,
    '--raw-root', $raw,
    '--output-root', $output,
    '--output-schema', $rawContractPath,
    '--output-schema-sha256', $RawOutputContractSha256,
    '--seal-manifest', $sealManifest,
    '--seal-manifest-sha256', $sealManifestSha,
    '--seal-terminal', $sealTerminal,
    '--seal-terminal-sha256', $sealTerminalSha,
    '--schedule', $schedulePath,
    '--schedule-sha256', $ScheduleSha256,
    '--runtime-manifest', $runtimeManifestPath,
    '--runtime-manifest-sha256', $TypedParquetRuntimeManifestSha256,
    '--pyarrow-root', $pyArrowPath,
    '--batch-size', "$BatchSize"
)

& $pythonPath @arguments
$exitCode = $LASTEXITCODE
Require-Condition ($exitCode -eq 0) "Independent formal ST acceptance failed closed with exit code $exitCode."
$afterDigest = Get-TreeMetadataDigest $raw
Require-Condition ($beforeDigest -ceq $afterDigest) 'Source measured root metadata changed during read-only acceptance.'
$terminalPath = Join-Path $output 'terminal-final.v5.json'
Require-Condition (Test-Path -LiteralPath $terminalPath -PathType Leaf) 'Acceptance terminal receipt is missing.'
$terminal = Read-Json $terminalPath
Require-Condition ($terminal.status -eq 'PASS_READ_ONLY_FORMAL_ST_ACCEPTANCE' -and $terminal.sourceMeasuredRootWriteBack -eq $false -and $terminal.formalAnalysisPerformed -eq $false) 'Acceptance terminal receipt is not a bounded read-only PASS.'
Write-Output ($terminal | ConvertTo-Json -Depth 100 -Compress)
