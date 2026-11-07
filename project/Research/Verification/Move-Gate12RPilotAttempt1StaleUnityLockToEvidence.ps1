[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ProjectPath,

    [Parameter(Mandatory = $true)]
    [string]$EvidenceRoot
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Write-AtomicUtf8NoBomJson {
    param(
        [Parameter(Mandatory = $true)][string]$LiteralPath,
        [Parameter(Mandatory = $true)]$Value
    )
    $parent = Split-Path -Parent $LiteralPath
    $temporary = Join-Path $parent (([IO.Path]::GetFileName($LiteralPath)) + '.tmp-' + [Guid]::NewGuid().ToString('N'))
    $json = ($Value | ConvertTo-Json -Depth 20).Replace("`r`n", "`n").Replace("`r", "`n") + "`n"
    [IO.File]::WriteAllText($temporary, $json, (New-Object Text.UTF8Encoding($false, $true)))
    Move-Item -LiteralPath $temporary -Destination $LiteralPath
}

if ([string]::IsNullOrWhiteSpace($ProjectPath) -or -not [IO.Path]::IsPathRooted($ProjectPath)) { throw 'ProjectPath must be an explicit absolute path.' }
if ([string]::IsNullOrWhiteSpace($EvidenceRoot) -or -not [IO.Path]::IsPathRooted($EvidenceRoot)) { throw 'EvidenceRoot must be an explicit absolute path.' }

$ProjectPath = [IO.Path]::GetFullPath($ProjectPath)
$EvidenceRoot = [IO.Path]::GetFullPath($EvidenceRoot)
$expectedEvidenceRoot = [IO.Path]::GetFullPath((Join-Path $ProjectPath 'Research\Verification\Gate12R_PilotAttempt1_StaleLock_Recovery\v1'))
$lockPath = [IO.Path]::GetFullPath((Join-Path $ProjectPath 'Temp\UnityLockfile'))
$expectedLockPath = 'H:\DDM_Final_Project\Temp\UnityLockfile'
$frozenPilotRoot = [IO.Path]::GetFullPath((Join-Path $ProjectPath 'Research\PilotRuns\Gate12R_ProcessReuse_5pct\v1'))

if (-not $ProjectPath.Equals('H:\DDM_Final_Project', [StringComparison]::OrdinalIgnoreCase)) { throw "Unexpected project root: $ProjectPath" }
if (-not $EvidenceRoot.Equals($expectedEvidenceRoot, [StringComparison]::OrdinalIgnoreCase)) { throw "Unexpected evidence root: $EvidenceRoot" }
if (-not $lockPath.Equals($expectedLockPath, [StringComparison]::OrdinalIgnoreCase)) { throw "Unexpected lock path: $lockPath" }
if ($EvidenceRoot.StartsWith($frozenPilotRoot.TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase)) { throw 'Recovery evidence must remain outside the frozen pilot v1 root.' }
if (Test-Path -LiteralPath $EvidenceRoot) { throw "Create-new evidence root already exists: $EvidenceRoot" }
if (-not (Test-Path -LiteralPath $lockPath -PathType Leaf)) { throw "Expected stale lock is missing: $lockPath" }

$unityFamilyNames = @('Unity.exe', 'UnityCrashHandler64.exe', 'UnityPackageManager.exe', 'Unity.Licensing.Client.exe', 'bee_backend.exe', 'shadercompiler.exe')
$matchingProcesses = @(Get-CimInstance Win32_Process | Where-Object { $_.Name -in $unityFamilyNames } | Select-Object ProcessId, ParentProcessId, Name, ExecutablePath, CommandLine, CreationDate)
if ($matchingProcesses.Count -ne 0) { throw ('Unity-family process exists; stale-lock recovery refused: ' + (($matchingProcesses | ForEach-Object { "$($_.Name):$($_.ProcessId)" }) -join ', ')) }

$lockItem = Get-Item -LiteralPath $lockPath -Force
if (($lockItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'UnityLockfile is unexpectedly a reparse point.' }
if ([long]$lockItem.Length -ne 0L) { throw "UnityLockfile is not the expected zero-byte stale artifact: $($lockItem.Length)" }
$lockSha256 = (Get-FileHash -LiteralPath $lockPath -Algorithm SHA256).Hash.ToLowerInvariant()
if ($lockSha256 -ne 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855') { throw "Unexpected zero-byte SHA-256: $lockSha256" }

$stream = $null
try {
    $stream = New-Object IO.FileStream($lockPath, [IO.FileMode]::Open, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
} finally {
    if ($null -ne $stream) { $stream.Dispose() }
}

New-Item -ItemType Directory -Path $EvidenceRoot -Force | Out-Null
$destination = Join-Path $EvidenceRoot 'UnityLockfile.stale-attempt1'
$preMoveReceiptPath = Join-Path $EvidenceRoot 'pre-move-receipt.json'
$finalReceiptPath = Join-Path $EvidenceRoot 'recovery-receipt.json'

$preMove = [ordered]@{
    schemaVersion = 1
    receiptKind = 'gate12r-pilot-attempt1-stale-unity-lock-pre-move-receipt-v1'
    savedAtUtc = [DateTime]::UtcNow.ToString('o')
    projectPath = $ProjectPath
    sourcePath = $lockPath
    destinationPath = $destination
    sourceResolvedToExpectedPath = $true
    sourceIsLeaf = $true
    sourceIsReparsePoint = $false
    sourceRawBytes = [long]$lockItem.Length
    sourceSha256 = $lockSha256
    sourceCreationTimeUtc = $lockItem.CreationTimeUtc.ToString('o')
    sourceLastWriteTimeUtc = $lockItem.LastWriteTimeUtc.ToString('o')
    exclusiveReadWriteAvailable = $true
    unityFamilyProcessCount = 0
    cleanupAction = 'recoverable-move-to-versioned-evidence-root'
    deletionAuthorized = $false
    frozenPilotRootModified = $false
}
Write-AtomicUtf8NoBomJson -LiteralPath $preMoveReceiptPath -Value $preMove

Move-Item -LiteralPath $lockPath -Destination $destination
if (Test-Path -LiteralPath $lockPath) { throw 'UnityLockfile source still exists after recoverable move.' }
if (-not (Test-Path -LiteralPath $destination -PathType Leaf)) { throw 'Recovered stale lock evidence is missing after move.' }
$destinationItem = Get-Item -LiteralPath $destination -Force
$destinationSha256 = (Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash.ToLowerInvariant()
if ([long]$destinationItem.Length -ne 0L -or $destinationSha256 -ne $lockSha256) { throw 'Recovered stale lock bytes/hash changed during move.' }

$final = [ordered]@{
    schemaVersion = 1
    receiptKind = 'gate12r-pilot-attempt1-stale-unity-lock-recovery-receipt-v1'
    completedAtUtc = [DateTime]::UtcNow.ToString('o')
    sourcePath = $lockPath
    sourceAbsentAfterMove = $true
    destinationPath = $destination
    destinationRawBytes = [long]$destinationItem.Length
    destinationSha256 = $destinationSha256
    preMoveReceiptSha256 = (Get-FileHash -LiteralPath $preMoveReceiptPath -Algorithm SHA256).Hash.ToLowerInvariant()
    unityFamilyProcessCountBeforeMove = 0
    exclusiveReadWriteAvailableBeforeMove = $true
    recoveryMode = 'recoverable-versioned-evidence-preservation'
    deleted = $false
    frozenPilotRootModified = $false
    passed = $true
}
Write-AtomicUtf8NoBomJson -LiteralPath $finalReceiptPath -Value $final
Write-Host "Gate12R stale Unity lock moved to versioned evidence: $destination" -ForegroundColor Green

