Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:EmptyFileSha256 = 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855'
$script:AllowedCleanupRoles = @('pre-existing-attempt2-negative', 'expected-negative')

function Get-Gate10RLockFileSha256V3 {
    param([Parameter(Mandatory = $true)][string]$Path)
    $stream = [System.IO.File]::Open($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
    try {
        $sha = [System.Security.Cryptography.SHA256]::Create()
        try { return ([BitConverter]::ToString($sha.ComputeHash($stream))).Replace('-', '').ToLowerInvariant() }
        finally { $sha.Dispose() }
    }
    finally { $stream.Dispose() }
}

function Get-Gate10RStringSha256V3 {
    param([Parameter(Mandatory = $true)][AllowEmptyString()][string]$Value)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($Value)))).Replace('-', '').ToLowerInvariant() }
    finally { $sha.Dispose() }
}

function Write-Gate10RNewAtomicJsonV3 {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)]$Value,
        [int]$Depth = 30
    )
    $full = [System.IO.Path]::GetFullPath($Path)
    if (Test-Path -LiteralPath $full) { throw "Create-new receipt already exists: $full" }
    $parent = Split-Path -Parent $full
    if (-not (Test-Path -LiteralPath $parent -PathType Container)) { [void](New-Item -ItemType Directory -Path $parent -Force) }
    $temporary = $full + '.tmp-' + [Guid]::NewGuid().ToString('N')
    $json = $Value | ConvertTo-Json -Depth $Depth
    $encoding = New-Object System.Text.UTF8Encoding($false)
    try {
        [System.IO.File]::WriteAllText($temporary, $json + "`n", $encoding)
        if (Test-Path -LiteralPath $full) { throw "Create-new receipt appeared during atomic write: $full" }
        [System.IO.File]::Move($temporary, $full)
    }
    finally {
        if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary -Force }
    }
}

function Get-Gate10RLockSnapshotV3 {
    param(
        [Parameter(Mandatory = $true)][string]$ProjectPath,
        [string]$LockPath
    )
    $project = [System.IO.Path]::GetFullPath($ProjectPath)
    $expected = [System.IO.Path]::GetFullPath((Join-Path $project 'Temp\UnityLockfile'))
    $resolved = if ([string]::IsNullOrWhiteSpace($LockPath)) { $expected } else { [System.IO.Path]::GetFullPath($LockPath) }
    if (-not (Test-Path -LiteralPath $resolved)) {
        return [pscustomobject][ordered]@{
            expectedPath = $expected
            resolvedPath = $resolved
            pathMatchesExpected = [string]::Equals($expected, $resolved, [System.StringComparison]::OrdinalIgnoreCase)
            exists = $false
            isLeaf = $false
            isReparsePoint = $false
            bytes = $null
            sha256 = $null
            creationTimeUtc = $null
            lastWriteTimeUtc = $null
            exclusiveReadWriteAvailable = $false
            exclusiveOpenError = $null
        }
    }
    $item = Get-Item -LiteralPath $resolved -Force
    $isLeaf = -not [bool]$item.PSIsContainer
    $isReparse = ([int]$item.Attributes -band [int][System.IO.FileAttributes]::ReparsePoint) -ne 0
    $exclusive = $false
    $exclusiveError = $null
    if ($isLeaf -and -not $isReparse) {
        try {
            $handle = [System.IO.File]::Open($resolved, [System.IO.FileMode]::Open, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)
            try { $exclusive = $true } finally { $handle.Dispose() }
        }
        catch { $exclusiveError = $_.Exception.Message }
    }
    [pscustomobject][ordered]@{
        expectedPath = $expected
        resolvedPath = $resolved
        pathMatchesExpected = [string]::Equals($expected, $resolved, [System.StringComparison]::OrdinalIgnoreCase)
        exists = $true
        isLeaf = $isLeaf
        isReparsePoint = $isReparse
        bytes = if ($isLeaf) { [long]$item.Length } else { $null }
        sha256 = if ($isLeaf -and -not $isReparse) { Get-Gate10RLockFileSha256V3 -Path $resolved } else { $null }
        creationTimeUtc = $item.CreationTimeUtc.ToString('o')
        lastWriteTimeUtc = $item.LastWriteTimeUtc.ToString('o')
        exclusiveReadWriteAvailable = $exclusive
        exclusiveOpenError = $exclusiveError
    }
}

function Test-Gate10RLockCleanupEligibilityV3 {
    param(
        [Parameter(Mandatory = $true)]$Snapshot,
        [Parameter(Mandatory = $true)][ValidateSet('pre-existing-attempt2-negative', 'expected-negative', 'positive', 'compile', 'telemetry', 'cold-reference')][string]$Role,
        [Parameter(Mandatory = $true)][DateTimeOffset]$OwnedProcessStartedAt,
        [Parameter(Mandatory = $true)][DateTimeOffset]$OwnedProcessCompletedAt,
        [Parameter(Mandatory = $true)][bool]$OwnedProcessAlive,
        [Parameter(Mandatory = $true)][int]$UnityProcessCount,
        [int]$TimestampToleranceSeconds = 2
    )
    $errors = New-Object System.Collections.Generic.List[string]
    if ($script:AllowedCleanupRoles -notcontains $Role) { $errors.Add('cleanup-role-not-authorized') }
    if ($OwnedProcessAlive) { $errors.Add('owned-process-still-alive') }
    if ($UnityProcessCount -ne 0) { $errors.Add('unity-process-count-not-zero') }
    if (-not [bool]$Snapshot.pathMatchesExpected) { $errors.Add('lock-path-not-exact') }
    if (-not [bool]$Snapshot.exists) { $errors.Add('lock-does-not-exist') }
    if (-not [bool]$Snapshot.isLeaf) { $errors.Add('lock-is-not-a-leaf-file') }
    if ([bool]$Snapshot.isReparsePoint) { $errors.Add('lock-is-reparse-point') }
    if ($null -eq $Snapshot.bytes -or [long]$Snapshot.bytes -ne 0) { $errors.Add('lock-is-not-zero-bytes') }
    if ([string]$Snapshot.sha256 -ne $script:EmptyFileSha256) { $errors.Add('lock-sha256-is-not-empty-file-hash') }
    if (-not [bool]$Snapshot.exclusiveReadWriteAvailable) { $errors.Add('lock-cannot-be-opened-exclusively') }
    $lower = $OwnedProcessStartedAt.UtcDateTime.AddSeconds(-1 * $TimestampToleranceSeconds)
    $upper = $OwnedProcessCompletedAt.UtcDateTime.AddSeconds($TimestampToleranceSeconds)
    if ($OwnedProcessCompletedAt -lt $OwnedProcessStartedAt) { $errors.Add('owned-process-window-reversed') }
    try {
        $creation = [DateTime]::Parse([string]$Snapshot.creationTimeUtc).ToUniversalTime()
        $lastWrite = [DateTime]::Parse([string]$Snapshot.lastWriteTimeUtc).ToUniversalTime()
        if ($creation -lt $lower -or $creation -gt $upper) { $errors.Add('lock-creation-outside-owned-window') }
        if ($lastWrite -lt $lower -or $lastWrite -gt $upper) { $errors.Add('lock-last-write-outside-owned-window') }
    }
    catch { $errors.Add('lock-timestamp-unparseable') }
    [pscustomobject][ordered]@{
        role = $Role
        eligible = $errors.Count -eq 0
        errors = $errors.ToArray()
        expectedEmptyFileSha256 = $script:EmptyFileSha256
        timestampToleranceSeconds = $TimestampToleranceSeconds
        ownedProcessStartedAtUtc = $OwnedProcessStartedAt.UtcDateTime.ToString('o')
        ownedProcessCompletedAtUtc = $OwnedProcessCompletedAt.UtcDateTime.ToString('o')
        ownedProcessAlive = $OwnedProcessAlive
        unityProcessCount = $UnityProcessCount
    }
}

function Invoke-Gate10RControlledLockCleanupV3 {
    param(
        [Parameter(Mandatory = $true)][string]$ProjectPath,
        [Parameter(Mandatory = $true)][int]$OwnedProcessId,
        [Parameter(Mandatory = $true)][DateTimeOffset]$OwnedProcessStartedAt,
        [Parameter(Mandatory = $true)][DateTimeOffset]$OwnedProcessCompletedAt,
        [Parameter(Mandatory = $true)][ValidateSet('pre-existing-attempt2-negative', 'expected-negative')][string]$Role,
        [Parameter(Mandatory = $true)][string]$EvidenceDirectory,
        [Parameter(Mandatory = $true)][ValidatePattern('^[A-Za-z0-9][A-Za-z0-9_.-]{0,127}$')][string]$ContextId,
        [int]$TimestampToleranceSeconds = 2
    )
    $project = [System.IO.Path]::GetFullPath($ProjectPath)
    $lockPath = [System.IO.Path]::GetFullPath((Join-Path $project 'Temp\UnityLockfile'))
    $ownedAlive = $null -ne (Get-Process -Id $OwnedProcessId -ErrorAction SilentlyContinue)
    $unityCount = @(Get-Process -Name Unity -ErrorAction SilentlyContinue).Count
    $snapshot = Get-Gate10RLockSnapshotV3 -ProjectPath $project -LockPath $lockPath
    $eligibility = Test-Gate10RLockCleanupEligibilityV3 -Snapshot $snapshot -Role $Role -OwnedProcessStartedAt $OwnedProcessStartedAt -OwnedProcessCompletedAt $OwnedProcessCompletedAt -OwnedProcessAlive $ownedAlive -UnityProcessCount $unityCount -TimestampToleranceSeconds $TimestampToleranceSeconds
    $capturePath = Join-Path ([System.IO.Path]::GetFullPath($EvidenceDirectory)) ($ContextId + '.lock-capture.json')
    $completionPath = Join-Path ([System.IO.Path]::GetFullPath($EvidenceDirectory)) ($ContextId + '.lock-cleanup.json')
    $capture = [ordered]@{
        schemaVersion = 1
        receiptKind = 'gate10r-attempt3-lock-pre-delete-capture-v1'
        capturedAtUtc = [DateTime]::UtcNow.ToString('o')
        contextId = $ContextId
        role = $Role
        ownedProcessId = $OwnedProcessId
        snapshot = $snapshot
        eligibility = $eligibility
        deletionAttempted = $false
        formalCampaign = $false
    }
    Write-Gate10RNewAtomicJsonV3 -Path $capturePath -Value $capture -Depth 30
    $captureSha = Get-Gate10RLockFileSha256V3 -Path $capturePath
    if (-not $eligibility.eligible) { throw "Lock cleanup refused after evidence capture: $($eligibility.errors -join ', ')" }
    Remove-Item -LiteralPath $lockPath -Force -ErrorAction Stop
    $postSnapshot = Get-Gate10RLockSnapshotV3 -ProjectPath $project -LockPath $lockPath
    $postOwnedAlive = $null -ne (Get-Process -Id $OwnedProcessId -ErrorAction SilentlyContinue)
    $postUnityCount = @(Get-Process -Name Unity -ErrorAction SilentlyContinue).Count
    $postPassed = -not $postSnapshot.exists -and -not $postOwnedAlive -and $postUnityCount -eq 0
    $completion = [ordered]@{
        schemaVersion = 1
        receiptKind = 'gate10r-attempt3-lock-cleanup-completion-v1'
        completedAtUtc = [DateTime]::UtcNow.ToString('o')
        contextId = $ContextId
        role = $Role
        ownedProcessId = $OwnedProcessId
        captureReceiptPath = $capturePath
        captureReceiptSha256 = $captureSha
        exactLiteralPathRemoved = $lockPath
        recursiveDeleteUsed = $false
        wildcardDeleteUsed = $false
        postSnapshot = $postSnapshot
        postOwnedProcessAlive = $postOwnedAlive
        postUnityProcessCount = $postUnityCount
        passed = $postPassed
        formalCampaign = $false
    }
    Write-Gate10RNewAtomicJsonV3 -Path $completionPath -Value $completion -Depth 30
    if (-not $postPassed) { throw 'Lock cleanup postcondition failed after exact-file removal.' }
    [pscustomobject][ordered]@{
        mode = 'controlled-' + $Role + '-cleanup'
        captureReceiptPath = $capturePath
        captureReceiptSha256 = $captureSha
        completionReceiptPath = $completionPath
        completionReceiptSha256 = Get-Gate10RLockFileSha256V3 -Path $completionPath
        passed = $true
    }
}

function Invoke-Gate10RPostExitQuiescenceV3 {
    param(
        [Parameter(Mandatory = $true)][string]$ProjectPath,
        [Parameter(Mandatory = $true)][int]$OwnedProcessId,
        [Parameter(Mandatory = $true)][DateTimeOffset]$OwnedProcessStartedAt,
        [Parameter(Mandatory = $true)][DateTimeOffset]$OwnedProcessCompletedAt,
        [Parameter(Mandatory = $true)][ValidateSet('expected-negative', 'positive', 'compile', 'telemetry', 'cold-reference')][string]$Role,
        [Parameter(Mandatory = $true)][string]$EvidenceDirectory,
        [Parameter(Mandatory = $true)][ValidatePattern('^[A-Za-z0-9][A-Za-z0-9_.-]{0,127}$')][string]$ContextId,
        [int]$QuiescenceSeconds = 60,
        [int]$PollMilliseconds = 250,
        [int]$TimestampToleranceSeconds = 2
    )
    if ($QuiescenceSeconds -lt 1 -or $QuiescenceSeconds -gt 60) { throw 'QuiescenceSeconds must be between 1 and 60.' }
    if ($PollMilliseconds -lt 100 -or $PollMilliseconds -gt 1000) { throw 'PollMilliseconds must be between 100 and 1000.' }
    $project = [System.IO.Path]::GetFullPath($ProjectPath)
    $lockPath = [System.IO.Path]::GetFullPath((Join-Path $project 'Temp\UnityLockfile'))
    $startedWaitingAt = [DateTime]::UtcNow
    $deadline = $startedWaitingAt.AddSeconds($QuiescenceSeconds)
    $pollCount = 0
    do {
        $pollCount++
        $ownedAlive = $null -ne (Get-Process -Id $OwnedProcessId -ErrorAction SilentlyContinue)
        $unityCount = @(Get-Process -Name Unity -ErrorAction SilentlyContinue).Count
        $lockExists = Test-Path -LiteralPath $lockPath
        if (-not $ownedAlive -and $unityCount -eq 0 -and -not $lockExists) {
            $receiptPath = Join-Path ([System.IO.Path]::GetFullPath($EvidenceDirectory)) ($ContextId + '.quiescence.json')
            $receipt = [ordered]@{
                schemaVersion = 1
                receiptKind = 'gate10r-attempt3-post-exit-quiescence-v1'
                savedAtUtc = [DateTime]::UtcNow.ToString('o')
                contextId = $ContextId
                role = $Role
                ownedProcessId = $OwnedProcessId
                ownedProcessStartedAtUtc = $OwnedProcessStartedAt.UtcDateTime.ToString('o')
                ownedProcessCompletedAtUtc = $OwnedProcessCompletedAt.UtcDateTime.ToString('o')
                mode = 'natural-lock-absence'
                pollCount = $pollCount
                quiescenceSeconds = $QuiescenceSeconds
                pollMilliseconds = $PollMilliseconds
                ownedProcessAlive = $false
                unityProcessCount = 0
                lockExists = $false
                cleanupAttempted = $false
                passed = $true
                formalCampaign = $false
            }
            Write-Gate10RNewAtomicJsonV3 -Path $receiptPath -Value $receipt -Depth 20
            return [pscustomobject][ordered]@{mode='natural-lock-absence';receiptPath=$receiptPath;receiptSha256=Get-Gate10RLockFileSha256V3 -Path $receiptPath;passed=$true}
        }
        if ([DateTime]::UtcNow -lt $deadline) { Start-Sleep -Milliseconds $PollMilliseconds }
    } while ([DateTime]::UtcNow -lt $deadline)

    if ($Role -eq 'expected-negative') {
        return Invoke-Gate10RControlledLockCleanupV3 -ProjectPath $project -OwnedProcessId $OwnedProcessId -OwnedProcessStartedAt $OwnedProcessStartedAt -OwnedProcessCompletedAt $OwnedProcessCompletedAt -Role 'expected-negative' -EvidenceDirectory $EvidenceDirectory -ContextId $ContextId -TimestampToleranceSeconds $TimestampToleranceSeconds
    }

    $failurePath = Join-Path ([System.IO.Path]::GetFullPath($EvidenceDirectory)) ($ContextId + '.quiescence-failure.json')
    $failure = [ordered]@{
        schemaVersion = 1
        receiptKind = 'gate10r-attempt3-post-exit-quiescence-failure-v1'
        savedAtUtc = [DateTime]::UtcNow.ToString('o')
        contextId = $ContextId
        role = $Role
        ownedProcessId = $OwnedProcessId
        pollCount = $pollCount
        ownedProcessAlive = $null -ne (Get-Process -Id $OwnedProcessId -ErrorAction SilentlyContinue)
        unityProcessCount = @(Get-Process -Name Unity -ErrorAction SilentlyContinue).Count
        lockSnapshot = Get-Gate10RLockSnapshotV3 -ProjectPath $project -LockPath $lockPath
        cleanupAttempted = $false
        passed = $false
        formalCampaign = $false
    }
    Write-Gate10RNewAtomicJsonV3 -Path $failurePath -Value $failure -Depth 30
    throw "Post-exit quiescence failed for role $Role; cleanup is not authorized."
}

Export-ModuleMember -Function @(
    'Get-Gate10RLockFileSha256V3',
    'Get-Gate10RStringSha256V3',
    'Write-Gate10RNewAtomicJsonV3',
    'Get-Gate10RLockSnapshotV3',
    'Test-Gate10RLockCleanupEligibilityV3',
    'Invoke-Gate10RControlledLockCleanupV3',
    'Invoke-Gate10RPostExitQuiescenceV3'
)

