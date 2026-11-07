[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$ProjectPath,
    [switch]$ValidationOnly
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

if ([string]::IsNullOrWhiteSpace($ProjectPath) -or -not [IO.Path]::IsPathRooted($ProjectPath)) {
    throw 'ProjectPath must be an explicit absolute path.'
}
$ProjectPath = [IO.Path]::GetFullPath($ProjectPath).TrimEnd('\', '/')
$expectedParent = [IO.Path]::GetFullPath((Join-Path $ProjectPath 'Temp')).TrimEnd('\', '/')
$expected = [IO.Path]::GetFullPath((Join-Path $expectedParent 'UnityLockfile'))
$failedRoot = [IO.Path]::GetFullPath((Join-Path $ProjectPath 'Research\FormalRuns\Gate13R_RQAligned_S48H48\v2')).TrimEnd('\', '/')
$quiescencePath = Join-Path $failedRoot 'campaigns\c52-grid-scale-g256-shared--shared\blocks\b0022.lock-hygiene\g13rpr2-c52-b0022.quiescence-failure.json'
$preCleanupEvidencePath = Join-Path $ProjectPath 'Research\Gate13R_PR2_Attempt2_Stale_Lock_PreCleanup_Evidence.v1.json'
$expectedEmptyHash = 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855'
$expectedTree = 'aafd8018d67b54b0965dcf778d502aadbba249dc53f80ea0f7722c0c1a05867e'

foreach ($required in @($failedRoot, $quiescencePath, $preCleanupEvidencePath)) {
    if (-not (Test-Path -LiteralPath $required)) { throw "Required evidence is missing: $required" }
}
if (@(Get-Process -Name Unity -ErrorAction SilentlyContinue).Count -ne 0) { throw 'Unity process exists.' }
if ($null -ne (Get-Process -Id 3548 -ErrorAction SilentlyContinue)) { throw 'Attempt-2 orchestrator still exists.' }
if (-not (Test-Path -LiteralPath $expected -PathType Leaf)) { throw 'Expected stale lock is absent or not a leaf.' }

$resolved = (Resolve-Path -LiteralPath $expected).Path
if (-not $resolved.Equals($expected, [StringComparison]::OrdinalIgnoreCase)) { throw 'Resolved lock path mismatch.' }
$resolvedParent = [IO.Path]::GetDirectoryName($resolved).TrimEnd('\', '/')
if (-not $resolvedParent.Equals($expectedParent, [StringComparison]::OrdinalIgnoreCase)) { throw 'Lock parent mismatch.' }

$item = Get-Item -LiteralPath $resolved -Force
if ($item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw 'Lock is a directory or reparse point.' }
if ([long]$item.Length -ne 0) { throw 'Lock is nonzero.' }
$hash = (Get-FileHash -LiteralPath $resolved -Algorithm SHA256).Hash.ToLowerInvariant()
if ($hash -ne $expectedEmptyHash) { throw 'Lock hash mismatch.' }
$quiescence = Get-Content -Raw -LiteralPath $quiescencePath | ConvertFrom-Json
if ($item.LastWriteTimeUtc -ne ([DateTime]$quiescence.lockSnapshot.lastWriteTimeUtc).ToUniversalTime()) { throw 'Lock timestamp mismatch.' }

$stream = $null
try {
    $stream = [IO.File]::Open($resolved, [IO.FileMode]::Open, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
}
catch {
    throw "Lock exclusive-open failed: $($_.Exception.Message)"
}
finally {
    if ($null -ne $stream) { $stream.Dispose() }
}

if ($ValidationOnly) {
    [pscustomobject][ordered]@{
        validationOnly = $true
        passed = $true
        resolvedExactPath = $resolved
        bytes = [long]$item.Length
        sha256 = $hash
        unityProcessCount = 0
        orchestratorAlive = $false
        exclusiveReadWriteAvailable = $true
        deletionPerformed = $false
    } | ConvertTo-Json -Depth 10
    exit 0
}

# The exact, pre-resolved, zero-byte stale lock is the only authorized deletion.
Remove-Item -LiteralPath $resolved -Force
if (Test-Path -LiteralPath $expected) { throw 'Lock still exists after exact removal.' }

$files = @(Get-ChildItem -LiteralPath $failedRoot -File -Recurse -Force)
$paths = @($files | ForEach-Object { $_.FullName.Substring($failedRoot.Length + 1).Replace('\', '/') })
[Array]::Sort($paths, [StringComparer]::Ordinal)
$map = @{}
foreach ($file in $files) { $map[$file.FullName.Substring($failedRoot.Length + 1).Replace('\', '/')] = $file }
$builder = New-Object Text.StringBuilder
foreach ($relative in $paths) {
    $file = $map[$relative]
    $fileHash = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
    [void]$builder.Append($relative)
    [void]$builder.Append("`t")
    [void]$builder.Append([string]$file.Length)
    [void]$builder.Append("`t")
    [void]$builder.Append($fileHash)
    [void]$builder.Append("`n")
}
$sha = [Security.Cryptography.SHA256]::Create()
try {
    $tree = ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($builder.ToString())))).Replace('-', '').ToLowerInvariant()
}
finally {
    $sha.Dispose()
}
if ($tree -ne $expectedTree) { throw "Failed-root hash changed during stale-lock cleanup: $tree" }

[pscustomobject][ordered]@{
    cleanedAtUtc = [DateTime]::UtcNow.ToString('o')
    removedExactPath = $resolved
    removedBytes = [long]$item.Length
    removedSha256 = $hash
    lockAbsentAfter = -not (Test-Path -LiteralPath $expected)
    unityProcessCountAfter = @(Get-Process -Name Unity -ErrorAction SilentlyContinue).Count
    attempt2OrchestratorAliveAfter = $null -ne (Get-Process -Id 3548 -ErrorAction SilentlyContinue)
    failedRootFileCount = $files.Count
    failedRootRawBytes = [long](($files | Measure-Object Length -Sum).Sum)
    failedRootNotReadOnlyCount = @($files | Where-Object { -not $_.IsReadOnly }).Count
    failedRootCanonicalTreeSha256 = $tree
    failedRootHashUnchanged = $tree -eq $expectedTree
} | ConvertTo-Json -Depth 10
