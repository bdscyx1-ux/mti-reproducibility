[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$ProjectRoot,
    [Parameter(Mandatory = $true)][string]$RawRoot,
    [Parameter(Mandatory = $true)][string]$AcceptanceRoot,
    [Parameter(Mandatory = $true)][string]$AcceptanceTool,
    [Parameter(Mandatory = $true)][ValidatePattern('^[0-9a-f]{64}$')][string]$AcceptanceToolSha256,
    [Parameter(Mandatory = $true)][string]$OutputSchema,
    [Parameter(Mandatory = $true)][ValidatePattern('^[0-9a-f]{64}$')][string]$OutputSchemaSha256,
    [Parameter(Mandatory = $true)][string]$Schedule,
    [Parameter(Mandatory = $true)][ValidatePattern('^[0-9a-f]{64}$')][string]$ScheduleSha256,
    [Parameter(Mandatory = $true)][string]$RuntimeManifest,
    [Parameter(Mandatory = $true)][ValidatePattern('^[0-9a-f]{64}$')][string]$RuntimeManifestSha256,
    [Parameter(Mandatory = $true)][string]$PyArrowRoot,
    [Parameter(Mandatory = $true)][string]$PythonExecutable,
    [Parameter(Mandatory = $true)][ValidatePattern('^[0-9a-f]{64}$')][string]$PythonExecutableSha256,
    [ValidateRange(256, 65536)][int]$BatchSize = 4096
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Require-Condition {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw [System.InvalidOperationException]::new($Message) }
}

function Resolve-FullPath {
    param([string]$Path, [string]$Base)
    $candidate = if ([IO.Path]::IsPathRooted($Path)) { $Path } else { Join-Path $Base $Path }
    return [IO.Path]::GetFullPath($candidate).TrimEnd([IO.Path]::DirectorySeparatorChar)
}

function Assert-FileHash {
    param([string]$Path, [string]$Expected, [string]$Label)
    Require-Condition (Test-Path -LiteralPath $Path -PathType Leaf) "$Label is missing: $Path"
    $actual = (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToLowerInvariant()
    Require-Condition ($actual -eq $Expected) "$Label SHA-256 mismatch: expected=$Expected actual=$actual"
}

$project = Resolve-FullPath -Path $ProjectRoot -Base (Get-Location).Path
$raw = Resolve-FullPath -Path $RawRoot -Base $project
$output = Resolve-FullPath -Path $AcceptanceRoot -Base $project
$tool = Resolve-FullPath -Path $AcceptanceTool -Base $project
$schema = Resolve-FullPath -Path $OutputSchema -Base $project
$scheduleFull = Resolve-FullPath -Path $Schedule -Base $project
$runtime = Resolve-FullPath -Path $RuntimeManifest -Base $project
$pyarrow = Resolve-FullPath -Path $PyArrowRoot -Base $project
$python = Resolve-FullPath -Path $PythonExecutable -Base $project

Require-Condition (Test-Path -LiteralPath $project -PathType Container) 'Project root is missing.'
Require-Condition (Test-Path -LiteralPath $raw -PathType Container) 'Sealed raw root is missing.'
Require-Condition (-not (Test-Path -LiteralPath $output)) 'Acceptance root must be new; same-attempt retry/overwrite is prohibited.'
Require-Condition (-not $output.StartsWith($raw + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) 'Acceptance root must be separate from the sealed raw root.'
Require-Condition (Test-Path -LiteralPath $pyarrow -PathType Container) 'Frozen PyArrow root is missing.'
Assert-FileHash -Path $tool -Expected $AcceptanceToolSha256 -Label 'acceptance tool v4.1'
Assert-FileHash -Path $schema -Expected $OutputSchemaSha256 -Label 'output schema v4'
Assert-FileHash -Path $scheduleFull -Expected $ScheduleSha256 -Label 'schedule v4'
Assert-FileHash -Path $runtime -Expected $RuntimeManifestSha256 -Label 'typed-Parquet runtime manifest'
Assert-FileHash -Path $python -Expected $PythonExecutableSha256 -Label 'Python executable'

$sealManifest = Join-Path $raw '_control/acquisition-freeze-manifest.v4.json'
$sealTerminal = Join-Path $raw '_control/acquisition-terminal-receipt.v4.json'
Require-Condition (Test-Path -LiteralPath $sealManifest -PathType Leaf) 'Acquisition freeze manifest is missing.'
Require-Condition (Test-Path -LiteralPath $sealTerminal -PathType Leaf) 'Acquisition terminal receipt is missing.'
$sealManifestSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $sealManifest).Hash.ToLowerInvariant()
$sealTerminalSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $sealTerminal).Hash.ToLowerInvariant()

$arguments = @(
    $tool,
    '--project-root', $project,
    '--raw-root', $raw,
    '--output-root', $output,
    '--output-schema', $schema,
    '--output-schema-sha256', $OutputSchemaSha256,
    '--seal-manifest', $sealManifest,
    '--seal-manifest-sha256', $sealManifestSha256,
    '--seal-terminal', $sealTerminal,
    '--seal-terminal-sha256', $sealTerminalSha256,
    '--schedule', $scheduleFull,
    '--schedule-sha256', $ScheduleSha256,
    '--runtime-manifest', $runtime,
    '--runtime-manifest-sha256', $RuntimeManifestSha256,
    '--pyarrow-root', $pyarrow,
    '--batch-size', [string]$BatchSize
)

& $python @arguments
$exitCode = $LASTEXITCODE
Require-Condition ($exitCode -eq 0) "Independent acceptance failed closed with exit code $exitCode; preserve this acceptance root and use a new versioned root after any repair."

$terminal = Join-Path $output 'terminal-final.v4_1.json'
Require-Condition (Test-Path -LiteralPath $terminal -PathType Leaf) 'Acceptance terminal receipt is missing.'
$receipt = Get-Content -LiteralPath $terminal -Raw -Encoding UTF8 | ConvertFrom-Json -Depth 100
Require-Condition ($receipt.status -eq 'PASS_INDEPENDENT_STREAMING_ESSENTIAL_ACCEPTANCE_FROZEN') 'Acceptance terminal status is not PASS.'
