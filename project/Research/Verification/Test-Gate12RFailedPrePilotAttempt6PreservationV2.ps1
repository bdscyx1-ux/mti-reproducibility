[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$ProjectPath,
    [Parameter(Mandatory = $true)][string]$OutputPath,
    [switch]$BindingSmokeOnly
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if ([string]::IsNullOrWhiteSpace($ProjectPath) -or -not [IO.Path]::IsPathRooted($ProjectPath)) {
    throw 'Gate12R failed pre-pilot attempt 6 preservation audit requires an explicit absolute ProjectPath.'
}
$ProjectPath = [IO.Path]::GetFullPath($ProjectPath)
if ($BindingSmokeOnly) {
    Write-Output "BINDING-SMOKE-PASSED|Test-Gate12RFailedPrePilotAttempt6PreservationV2|$ProjectPath"
    exit 0
}
$OutputPath = [IO.Path]::GetFullPath($OutputPath)
if (Test-Path -LiteralPath $OutputPath) { throw "Create-new audit output exists: $OutputPath" }
function Get-LowerSha256([string]$Path) { return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant() }

$root = Join-Path $ProjectPath 'Research\Verification\Gate12R_ProcessReuse_5pct\v6'
$partialPath = Join-Path $root 'partial-output-manifest.json'
$partial = Get-Content -LiteralPath $partialPath -Raw -Encoding UTF8 | ConvertFrom-Json
$bad = New-Object Collections.Generic.List[object]
foreach ($row in @($partial.files)) {
    $path = Join-Path $ProjectPath ([string]$row.relativePath).Replace('/', '\')
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { $bad.Add([pscustomobject]@{ relativePath = $row.relativePath; reason = 'missing' }); continue }
    $file = Get-Item -LiteralPath $path
    if ([long]$file.Length -ne [long]$row.rawBytes) { $bad.Add([pscustomobject]@{ relativePath = $row.relativePath; reason = 'length' }); continue }
    if ((Get-LowerSha256 $path) -ne [string]$row.sha256) { $bad.Add([pscustomobject]@{ relativePath = $row.relativePath; reason = 'sha256' }) }
}
$files = @(Get-ChildItem -LiteralPath $root -Recurse -File -Force)
$rawBytes = [long](($files | Measure-Object Length -Sum).Sum)
$preservation = Join-Path $ProjectPath 'Research\Gate12R_PrePilotAttempt6_Terminal_Preservation.v1.json'
$passed = $bad.Count -eq 0 -and @($partial.files).Count -eq 10 -and [long]$partial.rawBytes -eq 17684 -and
    $files.Count -eq 11 -and $rawBytes -eq 21176 -and
    (Get-LowerSha256 (Join-Path $root 'execution-receipt.json')) -eq 'a98a0269c7121c204be629abc626675750d22c05d07863de61a08257225037fa' -and
    (Get-LowerSha256 (Join-Path $root 'failure-receipt.json')) -eq 'c685848b8961236e3f425618449f8a4178deb2eab692c1e64b425b64d4f25778' -and
    (Get-LowerSha256 (Join-Path $root 'gate12r-checkpoint.json')) -eq '153102bb1dc61ee967b358f0aa2677f4475d92fb95ae74e54ba6ed44c5de7430' -and
    (Get-LowerSha256 $partialPath) -eq '7f0bcf5a2ba018f5590c9a96c03a4f5e899c9defcc8889ecc775422829944afa' -and
    (Get-LowerSha256 (Join-Path $root 'StaticUnit\summary.json')) -eq 'eddac1032572e0cee5f944758bc6f84afc41f17a179e14cbf073c618e17a3af8' -and
    (Test-Path -LiteralPath $preservation -PathType Leaf)
$result = [ordered]@{
    schemaVersion = 1
    auditKind = 'gate12r-failed-prepilot-attempt6-preservation-audit-v2-ps51-list-array-repair'
    completedAtUtc = [DateTime]::UtcNow.ToString('o')
    verificationRoot = 'Research/Verification/Gate12R_ProcessReuse_5pct/v6'
    listedFileCount = @($partial.files).Count
    listedRawBytes = [long]$partial.rawBytes
    rootFileCount = $files.Count
    rootRawBytes = $rawBytes
    badFileCount = $bad.Count
    badFiles = $bad.ToArray()
    resumeAuthorized = $false
    overwriteAuthorized = $false
    pilotRootAbsent = -not (Test-Path -LiteralPath (Join-Path $ProjectPath 'Research\PilotRuns\Gate12R_ProcessReuse_5pct\v4'))
    formalRootAbsent = -not (Test-Path -LiteralPath (Join-Path $ProjectPath 'Research\FormalRuns\Gate13R_ProcessReuse_5pct\v1'))
    passed = $passed
}
$parent = Split-Path -Parent $OutputPath
if (-not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
$json = ($result | ConvertTo-Json -Depth 20).Replace("`r`n", "`n").Replace("`r", "`n") + "`n"
[IO.File]::WriteAllText($OutputPath, $json, (New-Object Text.UTF8Encoding($false, $true)))
if (-not $passed) { throw 'Failed pre-pilot attempt 6 preservation audit did not pass.' }
$result | ConvertTo-Json -Depth 20
