Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-G13RPR2MP1Sha256 {
    param([Parameter(Mandatory = $true)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "File is missing: $Path" }
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Read-G13RPR2MP1Json {
    param([Parameter(Mandatory = $true)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "JSON file is missing: $Path" }
    return Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
}

function Write-G13RPR2MP1AtomicJson {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)]$Value,
        [int]$Depth = 60,
        [switch]$Replace
    )
    $full = [IO.Path]::GetFullPath($Path)
    $parent = Split-Path -Parent $full
    if (-not (Test-Path -LiteralPath $parent -PathType Container)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
    if (-not $Replace -and (Test-Path -LiteralPath $full)) { throw "Create-new artifact already exists: $full" }
    $temporary = Join-Path $parent ('.g13rpr2-mp1-' + [Guid]::NewGuid().ToString('N'))
    $encoding = New-Object Text.UTF8Encoding($false)
    try {
        $json = $Value | ConvertTo-Json -Depth $Depth
        [IO.File]::WriteAllText($temporary, $json + "`n", $encoding)
        if (-not $Replace -and (Test-Path -LiteralPath $full)) { throw "Create-new artifact appeared during atomic write: $full" }
        if ($Replace -and (Test-Path -LiteralPath $full)) { [IO.File]::Replace($temporary, $full, $null) }
        else { [IO.File]::Move($temporary, $full) }
    }
    finally {
        if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary -Force }
    }
}

function Test-G13RPR2MP1PathWithin {
    param(
        [Parameter(Mandatory = $true)][string]$BasePath,
        [Parameter(Mandatory = $true)][string]$CandidatePath,
        [switch]$AllowBase
    )
    $base = [IO.Path]::GetFullPath($BasePath).TrimEnd('\','/')
    $candidate = [IO.Path]::GetFullPath($CandidatePath).TrimEnd('\','/')
    if ($AllowBase -and $candidate.Equals($base, [StringComparison]::OrdinalIgnoreCase)) { return $true }
    return $candidate.StartsWith($base + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)
}

function Get-G13RPR2MP1ProcessSnapshot {
    param(
        [Parameter(Mandatory = $true)][Diagnostics.Process]$Process,
        [Parameter(Mandatory = $true)][string]$BlockId,
        [switch]$IncludeCim
    )
    $Process.Refresh()
    if ($Process.HasExited) { throw 'Cannot capture memory from an exited Unity process.' }
    $captured = [DateTime]::UtcNow
    $start = $Process.StartTime.ToUniversalTime()
    $cim = $null
    if ($IncludeCim) {
        $cim = Get-CimInstance Win32_Process -Filter ("ProcessId = {0}" -f $Process.Id) -ErrorAction SilentlyContinue
        if ($null -eq $cim) { throw 'Independent CIM process query is unavailable.' }
    }
    $os = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
    $available = [long]$os.FreePhysicalMemory * 1024L
    if ($available -le 0) { throw 'OS available physical memory query returned a non-positive value.' }
    $snapshot = [ordered]@{
        schemaVersion = 1
        snapshotKind = 'gate13r-pr2-mp1-external-process-start-snapshot-v1'
        sourceId = 'system-diagnostics-process-psapi-backed-v1'
        capturedAtUtc = $captured.ToString('o')
        processId = [int]$Process.Id
        processStartTimeUtc = $start.ToString('o')
        processAgeMilliseconds = ($captured - $start).TotalMilliseconds
        workingSetBytes = [long]$Process.WorkingSet64
        privateMemoryBytes = [long]$Process.PrivateMemorySize64
        availablePhysicalMemoryBytes = $available
        blockId = $BlockId
        cimAvailable = $null -ne $cim
        cim = if ($null -ne $cim) {
            [ordered]@{
                sourceId = 'cim-win32-process-v1'
                queriedAtUtc = [DateTime]::UtcNow.ToString('o')
                processId = [int]$cim.ProcessId
                creationDateUtc = ([DateTime]$cim.CreationDate).ToUniversalTime().ToString('o')
                workingSetBytes = [long]$cim.WorkingSetSize
                privateMemoryBytes = [long]$cim.PrivatePageCount
            }
        } else { $null }
    }
    if ($snapshot.workingSetBytes -le 0 -or $snapshot.privateMemoryBytes -le 0 -or $snapshot.processAgeMilliseconds -lt 0) { throw 'External PSAPI-backed process snapshot is invalid.' }
    if ($null -ne $cim) {
        if ([int]$cim.ProcessId -ne [int]$Process.Id) { throw 'PSAPI/CIM process ID mismatch.' }
        $creationDelta = [Math]::Abs((([DateTime]$cim.CreationDate).ToUniversalTime() - $start).TotalSeconds)
        if ($creationDelta -gt 2.0) { throw 'PSAPI/CIM process creation-time mismatch.' }
        foreach ($metric in @('workingSetBytes','privateMemoryBytes')) {
            $primary = [long]$snapshot[$metric]
            $secondary = [long]$snapshot.cim[$metric]
            $tolerance = [Math]::Max(67108864L, [long][Math]::Ceiling(0.25 * [Math]::Max($primary, $secondary)))
            if ([Math]::Abs($primary - $secondary) -gt $tolerance) { throw "PSAPI/CIM $metric cross-check exceeded tolerance." }
        }
    }
    return [pscustomobject]$snapshot
}

function Resolve-G13RPR2MP1FailurePrecedence {
    param(
        [Parameter(Mandatory = $true)][string]$BlockFailurePath,
        [string]$QuiescenceFailurePath,
        [string]$QuiescenceExceptionMessage,
        [int]$UnityExitCode = 0,
        [bool]$TimedOut = $false,
        [string[]]$SafetyStopReasons = @()
    )
    $blockFailure = if (Test-Path -LiteralPath $BlockFailurePath -PathType Leaf) { Read-G13RPR2MP1Json $BlockFailurePath } else { $null }
    $quiescenceFailure = if (-not [string]::IsNullOrWhiteSpace($QuiescenceFailurePath) -and (Test-Path -LiteralPath $QuiescenceFailurePath -PathType Leaf)) { Read-G13RPR2MP1Json $QuiescenceFailurePath } else { $null }
    $primary = $null
    $secondary = New-Object Collections.Generic.List[object]
    if ($null -ne $blockFailure) {
        $primary = [ordered]@{kind='DURABLE-UNITY-BLOCK-FAILURE';reasonCode=[string]$blockFailure.memoryGateReasonCode;source=$BlockFailurePath;failedAtUtc=[string]$blockFailure.failedAtUtc}
    }
    elseif (@($SafetyStopReasons).Count -gt 0) {
        $primary = [ordered]@{kind='EMERGENCY-SAFETY-STOP';reasonCode=(@($SafetyStopReasons) -join '+');source=$null}
    }
    elseif ($TimedOut) { $primary = [ordered]@{kind='HARD-TIMEOUT';reasonCode='HARD-TIMEOUT';source=$null} }
    elseif ($UnityExitCode -ne 0) { $primary = [ordered]@{kind='NONZERO-UNITY-EXIT';reasonCode=('UNITY-EXIT-' + $UnityExitCode);source=$null} }
    if ($null -ne $quiescenceFailure -or -not [string]::IsNullOrWhiteSpace($QuiescenceExceptionMessage)) {
        $cause = [ordered]@{kind='POST-EXIT-QUIESCENCE-FAILURE';reasonCode='POST-EXIT-QUIESCENCE-FAILURE';source=$QuiescenceFailurePath;exceptionMessage=$QuiescenceExceptionMessage}
        if ($null -eq $primary) { $primary = $cause } else { $secondary.Add($cause) }
    }
    $failed = $null -ne $primary
    return [pscustomobject][ordered]@{
        schemaVersion = 1
        resultKind = 'gate13r-pr2-mp1-failure-precedence-resolution-v1'
        failed = $failed
        primaryCause = $primary
        secondaryCauses = $secondary.ToArray()
        failClosed = $failed
        nextBlockAllowed = -not $failed
        automaticRetryAllowed = $false
        automaticResumeAllowed = $false
        topUpAllowed = $false
        partialMergeAllowed = $false
        lockCleanupAuthorizesContinuation = $false
    }
}

function Read-G13RPR2MP1TextWithRetry {
    param([Parameter(Mandatory = $true)][string]$Path,[int]$TimeoutMilliseconds=30000,[int]$PollMilliseconds=250)
    $deadline = [DateTime]::UtcNow.AddMilliseconds($TimeoutMilliseconds)
    do {
        try { return [IO.File]::ReadAllText([IO.Path]::GetFullPath($Path)) }
        catch { if ([DateTime]::UtcNow -ge $deadline) { throw }; Start-Sleep -Milliseconds $PollMilliseconds }
    } while ($true)
}

Export-ModuleMember -Function @(
    'Get-G13RPR2MP1Sha256','Read-G13RPR2MP1Json','Write-G13RPR2MP1AtomicJson',
    'Test-G13RPR2MP1PathWithin','Get-G13RPR2MP1ProcessSnapshot',
    'Resolve-G13RPR2MP1FailurePrecedence','Read-G13RPR2MP1TextWithRetry'
)
