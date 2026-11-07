[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ProjectPath
)

$ErrorActionPreference = 'Stop'
$projectRoot = [System.IO.Path]::GetFullPath($ProjectPath)
$expectedLock = [System.IO.Path]::GetFullPath((Join-Path $projectRoot 'Temp\UnityLockfile'))
$receiptPath = Join-Path $projectRoot 'Research\Gate12R_PilotAttempt3_Stale_Lock_Recovery_Receipt.v1.json'
$emptySha = 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855'

if (-not (Test-Path -LiteralPath $expectedLock -PathType Leaf)) {
    throw "Expected stale Unity lock is absent: $expectedLock"
}
if (@(Get-Process -Name Unity -ErrorAction SilentlyContinue).Count -ne 0) {
    throw 'A Unity process is running; stale-lock recovery is prohibited.'
}

$item = Get-Item -LiteralPath $expectedLock -Force
if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
    throw 'Unity lock is a reparse point; recovery is prohibited.'
}
if ($item.Length -ne 0) { throw 'Unity lock is not zero bytes; recovery is prohibited.' }
$sha = (Get-FileHash -LiteralPath $expectedLock -Algorithm SHA256).Hash.ToLowerInvariant()
if ($sha -ne $emptySha) { throw 'Unity lock does not have the frozen empty-file SHA-256.' }

$stream = [System.IO.File]::Open($expectedLock, [System.IO.FileMode]::Open, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)
$stream.Dispose()

$receipt = [ordered]@{
    schemaVersion = 1
    receiptKind = 'gate12r-attempt3-stale-unity-lock-recovery-v1'
    recoveredAtUtc = [DateTime]::UtcNow.ToString('O')
    projectRoot = $projectRoot
    resolvedLockPath = $expectedLock
    priorAttemptRoot = 'Research/PilotRuns/Gate12R_ProcessReuse_5pct/v3'
    priorAttemptStatus = 'FAILED-NO-RESUME-NO-MERGE'
    unityProcessCountBefore = 0
    bytesBefore = [long]$item.Length
    sha256Before = $sha
    reparsePointBefore = $false
    exclusiveReadWriteAvailableBefore = $true
    deletionScope = 'EXACT-STALE-TEMP-LOCK-ONLY'
    cleanupAuthorizedBy = 'Gate12R versioned repair required for a fresh attempt after user-authorized memory-gate amendment'
    priorQuiescenceFailureSha256 = 'b6fdf3a9da31d90338db2cc6c684fc784baae31f01b4203e473bf39368d2db6a'
    removed = $false
}

$prePath = "$receiptPath.pre-recovery.json"
$utf8 = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($prePath, (($receipt | ConvertTo-Json -Depth 8) + "`n"), $utf8)

Remove-Item -LiteralPath $expectedLock -Force
if (Test-Path -LiteralPath $expectedLock) { throw 'Stale Unity lock still exists after exact-path removal.' }
$receipt.removed = $true
$receipt.unityProcessCountAfter = @(Get-Process -Name Unity -ErrorAction SilentlyContinue).Count
$receipt.lockExistsAfter = Test-Path -LiteralPath $expectedLock
$receipt.completed = ($receipt.unityProcessCountAfter -eq 0 -and -not $receipt.lockExistsAfter)
$temporary = "$receiptPath.tmp-$([Guid]::NewGuid().ToString('N'))"
[System.IO.File]::WriteAllText($temporary, (($receipt | ConvertTo-Json -Depth 8) + "`n"), $utf8)
if (Test-Path -LiteralPath $receiptPath) { throw 'Versioned stale-lock receipt already exists.' }
[System.IO.File]::Move($temporary, $receiptPath)
Remove-Item -LiteralPath $prePath -Force
if (-not $receipt.completed) { throw 'Stale-lock recovery postcondition failed.' }
$receipt | ConvertTo-Json -Depth 8
