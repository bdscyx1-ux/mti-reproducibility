Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-G13RPR2MP1V2Sha256 {
    param([Parameter(Mandatory = $true)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "File is missing: $Path" }
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Read-G13RPR2MP1V2Json {
    param([Parameter(Mandatory = $true)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "JSON file is missing: $Path" }
    return Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
}

function Write-G13RPR2MP1V2AtomicJson {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)]$Value,
        [int]$Depth = 80,
        [switch]$Replace,
        [switch]$PassThru
    )

    $full = [IO.Path]::GetFullPath($Path)
    $parent = Split-Path -Parent $full
    if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }
    $targetExisted = Test-Path -LiteralPath $full -PathType Leaf
    if (-not $Replace -and $targetExisted) { throw "Create-new artifact already exists: $full" }

    $token = [Guid]::NewGuid().ToString('N')
    $temporary = Join-Path $parent ('.g13rpr2-mp1-v2-temp-' + $token)
    $backup = Join-Path $parent ('.g13rpr2-mp1-v2-backup-' + $token)
    $encoding = New-Object Text.UTF8Encoding($false)
    $commitVerified = $false
    $backupUsed = $false
    try {
        $json = $Value | ConvertTo-Json -Depth $Depth
        [IO.File]::WriteAllText($temporary, $json + "`n", $encoding)
        $expectedSha256 = Get-G13RPR2MP1V2Sha256 $temporary

        if (-not $Replace -and (Test-Path -LiteralPath $full)) {
            throw "Create-new artifact appeared during atomic write: $full"
        }
        if ($Replace -and (Test-Path -LiteralPath $full -PathType Leaf)) {
            # A non-empty, same-directory backup path is mandatory. Passing $null is
            # interpreted as an empty path by PowerShell 7/.NET 10 on this host.
            [IO.File]::Replace($temporary, $full, $backup)
            $backupUsed = $true
        }
        else {
            [IO.File]::Move($temporary, $full)
        }

        if (-not (Test-Path -LiteralPath $full -PathType Leaf)) { throw "Atomic destination is absent after commit: $full" }
        $actualSha256 = Get-G13RPR2MP1V2Sha256 $full
        if ($actualSha256 -ne $expectedSha256) { throw "Atomic destination SHA-256 postcondition failed: $full" }
        $null = Read-G13RPR2MP1V2Json $full
        $commitVerified = $true

        if ($backupUsed) {
            if (-not (Test-Path -LiteralPath $backup -PathType Leaf)) { throw "Atomic replace backup postcondition failed: $backup" }
            Remove-Item -LiteralPath $backup -Force
        }
        if ((Test-Path -LiteralPath $temporary) -or (Test-Path -LiteralPath $backup)) {
            throw "Residual atomic temporary or backup artifact remains for: $full"
        }
        if ($PassThru) {
            return [pscustomobject][ordered]@{
                path = $full
                sha256 = $actualSha256
                targetExisted = $targetExisted
                replaceRequested = [bool]$Replace
                backupUsed = $backupUsed
                schemaReadBackPassed = $true
                residualTemporaryCount = 0
            }
        }
    }
    finally {
        if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary -Force }
        # Remove the owned backup only after the new destination has been verified.
        # On a failed commit it is intentionally retained as recovery evidence.
        if ($commitVerified -and (Test-Path -LiteralPath $backup)) { Remove-Item -LiteralPath $backup -Force }
    }
}

function Get-G13RPR2MP1V2CheckpointRequiredFields {
    return @(
        'schemaVersion','checkpointKind','savedAtUtc','status','startedAtUtc','completedAtUtc',
        'completedBlockCount','completedSampleCount','expectedBlockCount','expectedSampleCount',
        'currentGlobalProcessOrdinal','currentBlockId','lastCompletedGlobalProcessOrdinal','lastCompletedBlockId',
        'failureClass','failureStage','failureMessage','failureReceiptRelativePath','failureReceiptSha256',
        'partialOutputManifestRelativePath','partialOutputManifestSha256','phaseACommitStartedAtUtc',
        'phaseACommittedAtUtc','phaseACommitted','rawDataComplete','rawTreeSha256','rawManifestRelativePath',
        'rawManifestSha256','environmentEndSnapshotRelativePath','environmentEndSnapshotSha256',
        'automaticRetryAuthorized','automaticResumeAuthorized','topUpAuthorized','partialMergeAuthorized',
        'formalCampaign','formalAnalysisAuthorized','gate14RAuthorized'
    )
}

function Test-G13RPR2MP1V2CheckpointSchema {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)]$Checkpoint)

    $required = @(Get-G13RPR2MP1V2CheckpointRequiredFields)
    $actual = @($Checkpoint.PSObject.Properties.Name)
    foreach ($name in $required) {
        if ($actual -notcontains $name) { throw "Checkpoint required field is absent: $name" }
    }
    if ([int]$Checkpoint.schemaVersion -ne 2 -or [string]$Checkpoint.checkpointKind -ne 'gate13r-pr2-mp1-pilot-checkpoint-v2') {
        throw 'Checkpoint schema/version identity mismatch.'
    }
    $allowed = @(
        'AUTHORIZED-NOT-STARTED',
        'MEASURED-ACQUISITION-RUNNING',
        'BLOCK-PROGRESS',
        'PHASE-A-COMMIT-IN-PROGRESS',
        'PILOT-RAW-DATA-COMPLETE / ANALYSIS-PENDING / IMMUTABLE',
        'FAILED-NO-AUTO-RETRY-NO-RESUME-NO-TOP-UP-NO-MERGE'
    )
    if ($allowed -notcontains [string]$Checkpoint.status) { throw "Checkpoint status is not registered: $($Checkpoint.status)" }
    foreach ($field in @('savedAtUtc')) {
        $parsed = [DateTime]::MinValue
        if (-not [DateTime]::TryParse([string]$Checkpoint.$field, [ref]$parsed)) { throw "Checkpoint timestamp is invalid: $field" }
    }
    foreach ($field in @('startedAtUtc','completedAtUtc','phaseACommitStartedAtUtc','phaseACommittedAtUtc')) {
        if ($null -ne $Checkpoint.$field -and -not [string]::IsNullOrWhiteSpace([string]$Checkpoint.$field)) {
            $parsed = [DateTime]::MinValue
            if (-not [DateTime]::TryParse([string]$Checkpoint.$field, [ref]$parsed)) { throw "Checkpoint timestamp is invalid: $field" }
        }
    }
    if ([int]$Checkpoint.expectedBlockCount -ne 96 -or [int]$Checkpoint.expectedSampleCount -ne 384) { throw 'Checkpoint expected cardinality mismatch.' }
    if ([int]$Checkpoint.completedBlockCount -lt 0 -or [int]$Checkpoint.completedBlockCount -gt 96) { throw 'Checkpoint completedBlockCount is outside [0,96].' }
    if ([int]$Checkpoint.completedSampleCount -ne ([int]$Checkpoint.completedBlockCount * 4)) { throw 'Checkpoint completed sample/block relationship is invalid.' }
    if ([int]$Checkpoint.currentGlobalProcessOrdinal -lt 0 -or [int]$Checkpoint.currentGlobalProcessOrdinal -gt 96) { throw 'Checkpoint current global ordinal is outside [0,96].' }
    if ([int]$Checkpoint.lastCompletedGlobalProcessOrdinal -lt 0 -or [int]$Checkpoint.lastCompletedGlobalProcessOrdinal -gt 96) { throw 'Checkpoint last completed ordinal is outside [0,96].' }
    foreach ($field in @('automaticRetryAuthorized','automaticResumeAuthorized','topUpAuthorized','partialMergeAuthorized','formalCampaign','formalAnalysisAuthorized','gate14RAuthorized')) {
        if ([bool]$Checkpoint.$field) { throw "Checkpoint authorization boundary must remain false: $field" }
    }
    $rawComplete = [string]$Checkpoint.status -eq 'PILOT-RAW-DATA-COMPLETE / ANALYSIS-PENDING / IMMUTABLE'
    if ($rawComplete) {
        if (-not [bool]$Checkpoint.phaseACommitted -or -not [bool]$Checkpoint.rawDataComplete -or [int]$Checkpoint.completedBlockCount -ne 96) { throw 'Raw-complete checkpoint cardinality/flags mismatch.' }
        foreach ($field in @('rawTreeSha256','rawManifestRelativePath','rawManifestSha256','environmentEndSnapshotRelativePath','environmentEndSnapshotSha256','phaseACommittedAtUtc','completedAtUtc')) {
            if ([string]::IsNullOrWhiteSpace([string]$Checkpoint.$field)) { throw "Raw-complete checkpoint field is empty: $field" }
        }
    }
    if ([string]$Checkpoint.status -eq 'FAILED-NO-AUTO-RETRY-NO-RESUME-NO-TOP-UP-NO-MERGE') {
        foreach ($field in @('failureClass','failureStage','failureMessage','failureReceiptRelativePath','failureReceiptSha256','partialOutputManifestRelativePath','partialOutputManifestSha256')) {
            if ([string]::IsNullOrWhiteSpace([string]$Checkpoint.$field)) { throw "Failed checkpoint field is empty: $field" }
        }
    }
    foreach ($field in @('failureReceiptSha256','partialOutputManifestSha256','rawTreeSha256','rawManifestSha256','environmentEndSnapshotSha256')) {
        $value = [string]$Checkpoint.$field
        if (-not [string]::IsNullOrWhiteSpace($value) -and $value -notmatch '^[0-9a-f]{64}$') { throw "Checkpoint SHA-256 field is invalid: $field" }
    }
    return $true
}

function New-G13RPR2MP1V2Checkpoint {
    [CmdletBinding()]
    param([string]$SavedAtUtc = ([DateTime]::UtcNow.ToString('o')))
    $checkpoint = [pscustomobject][ordered]@{
        schemaVersion = 2
        checkpointKind = 'gate13r-pr2-mp1-pilot-checkpoint-v2'
        savedAtUtc = $SavedAtUtc
        status = 'AUTHORIZED-NOT-STARTED'
        startedAtUtc = $null
        completedAtUtc = $null
        completedBlockCount = 0
        completedSampleCount = 0
        expectedBlockCount = 96
        expectedSampleCount = 384
        currentGlobalProcessOrdinal = 0
        currentBlockId = $null
        lastCompletedGlobalProcessOrdinal = 0
        lastCompletedBlockId = $null
        failureClass = $null
        failureStage = $null
        failureMessage = $null
        failureReceiptRelativePath = $null
        failureReceiptSha256 = $null
        partialOutputManifestRelativePath = $null
        partialOutputManifestSha256 = $null
        phaseACommitStartedAtUtc = $null
        phaseACommittedAtUtc = $null
        phaseACommitted = $false
        rawDataComplete = $false
        rawTreeSha256 = $null
        rawManifestRelativePath = $null
        rawManifestSha256 = $null
        environmentEndSnapshotRelativePath = $null
        environmentEndSnapshotSha256 = $null
        automaticRetryAuthorized = $false
        automaticResumeAuthorized = $false
        topUpAuthorized = $false
        partialMergeAuthorized = $false
        formalCampaign = $false
        formalAnalysisAuthorized = $false
        gate14RAuthorized = $false
    }
    $null = Test-G13RPR2MP1V2CheckpointSchema $checkpoint
    return $checkpoint
}

function New-G13RPR2MP1V2CheckpointTransition {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Current,
        [Parameter(Mandatory = $true)][ValidateSet('MEASURED-ACQUISITION-RUNNING','BLOCK-PROGRESS','PHASE-A-COMMIT-IN-PROGRESS','PILOT-RAW-DATA-COMPLETE / ANALYSIS-PENDING / IMMUTABLE','FAILED-NO-AUTO-RETRY-NO-RESUME-NO-TOP-UP-NO-MERGE')][string]$Status,
        [int]$CompletedBlockCount = -1,
        [int]$CurrentGlobalProcessOrdinal = -1,
        [AllowNull()][string]$CurrentBlockId,
        [AllowNull()][string]$FailureClass,
        [AllowNull()][string]$FailureStage,
        [AllowNull()][string]$FailureMessage,
        [AllowNull()][string]$FailureReceiptRelativePath,
        [AllowNull()][string]$FailureReceiptSha256,
        [AllowNull()][string]$PartialOutputManifestRelativePath,
        [AllowNull()][string]$PartialOutputManifestSha256,
        [AllowNull()][string]$RawTreeSha256,
        [AllowNull()][string]$RawManifestRelativePath,
        [AllowNull()][string]$RawManifestSha256,
        [AllowNull()][string]$EnvironmentEndSnapshotRelativePath,
        [AllowNull()][string]$EnvironmentEndSnapshotSha256,
        [string]$SavedAtUtc = ([DateTime]::UtcNow.ToString('o'))
    )

    $null = Test-G13RPR2MP1V2CheckpointSchema $Current
    $from = [string]$Current.status
    $allowedTransitions = @{
        'AUTHORIZED-NOT-STARTED' = @('MEASURED-ACQUISITION-RUNNING','FAILED-NO-AUTO-RETRY-NO-RESUME-NO-TOP-UP-NO-MERGE')
        'MEASURED-ACQUISITION-RUNNING' = @('BLOCK-PROGRESS','PHASE-A-COMMIT-IN-PROGRESS','FAILED-NO-AUTO-RETRY-NO-RESUME-NO-TOP-UP-NO-MERGE')
        'BLOCK-PROGRESS' = @('BLOCK-PROGRESS','PHASE-A-COMMIT-IN-PROGRESS','FAILED-NO-AUTO-RETRY-NO-RESUME-NO-TOP-UP-NO-MERGE')
        'PHASE-A-COMMIT-IN-PROGRESS' = @('PILOT-RAW-DATA-COMPLETE / ANALYSIS-PENDING / IMMUTABLE','FAILED-NO-AUTO-RETRY-NO-RESUME-NO-TOP-UP-NO-MERGE')
    }
    if (-not $allowedTransitions.ContainsKey($from) -or $allowedTransitions[$from] -notcontains $Status) { throw "Illegal checkpoint transition: $from -> $Status" }

    $completed = if ($CompletedBlockCount -ge 0) { $CompletedBlockCount } else { [int]$Current.completedBlockCount }
    $ordinal = if ($CurrentGlobalProcessOrdinal -ge 0) { $CurrentGlobalProcessOrdinal } else { [int]$Current.currentGlobalProcessOrdinal }
    $blockId = if ($PSBoundParameters.ContainsKey('CurrentBlockId')) { $CurrentBlockId } else { [string]$Current.currentBlockId }
    $started = [string]$Current.startedAtUtc
    if ($Status -eq 'MEASURED-ACQUISITION-RUNNING' -and [string]::IsNullOrWhiteSpace($started)) { $started = $SavedAtUtc }
    $lastCompletedOrdinal = [int]$Current.lastCompletedGlobalProcessOrdinal
    $lastCompletedBlock = [string]$Current.lastCompletedBlockId
    if ($Status -eq 'BLOCK-PROGRESS') {
        if ($completed -le [int]$Current.completedBlockCount -or $completed -gt 96) { throw 'BLOCK-PROGRESS must increase completedBlockCount within the frozen cardinality.' }
        if ($ordinal -ne $completed -or [string]::IsNullOrWhiteSpace($blockId)) { throw 'BLOCK-PROGRESS ordinal/block identity mismatch.' }
        $lastCompletedOrdinal = $ordinal
        $lastCompletedBlock = $blockId
    }
    if ($Status -eq 'PHASE-A-COMMIT-IN-PROGRESS' -and $completed -ne 96) { throw 'Phase-A commit requires 96 completed blocks.' }

    $failed = $Status -eq 'FAILED-NO-AUTO-RETRY-NO-RESUME-NO-TOP-UP-NO-MERGE'
    $rawComplete = $Status -eq 'PILOT-RAW-DATA-COMPLETE / ANALYSIS-PENDING / IMMUTABLE'
    $phaseStart = [string]$Current.phaseACommitStartedAtUtc
    if ($Status -eq 'PHASE-A-COMMIT-IN-PROGRESS' -and [string]::IsNullOrWhiteSpace($phaseStart)) { $phaseStart = $SavedAtUtc }
    $checkpoint = [pscustomobject][ordered]@{
        schemaVersion = 2
        checkpointKind = 'gate13r-pr2-mp1-pilot-checkpoint-v2'
        savedAtUtc = $SavedAtUtc
        status = $Status
        startedAtUtc = $started
        completedAtUtc = if ($failed -or $rawComplete) { $SavedAtUtc } else { $null }
        completedBlockCount = $completed
        completedSampleCount = $completed * 4
        expectedBlockCount = 96
        expectedSampleCount = 384
        currentGlobalProcessOrdinal = $ordinal
        currentBlockId = $blockId
        lastCompletedGlobalProcessOrdinal = $lastCompletedOrdinal
        lastCompletedBlockId = $lastCompletedBlock
        failureClass = if ($failed) { $FailureClass } else { $null }
        failureStage = if ($failed) { $FailureStage } else { $null }
        failureMessage = if ($failed) { $FailureMessage } else { $null }
        failureReceiptRelativePath = if ($failed) { $FailureReceiptRelativePath } else { $null }
        failureReceiptSha256 = if ($failed) { $FailureReceiptSha256 } else { $null }
        partialOutputManifestRelativePath = if ($failed) { $PartialOutputManifestRelativePath } else { $null }
        partialOutputManifestSha256 = if ($failed) { $PartialOutputManifestSha256 } else { $null }
        phaseACommitStartedAtUtc = $phaseStart
        phaseACommittedAtUtc = if ($rawComplete) { $SavedAtUtc } else { $null }
        phaseACommitted = $rawComplete
        rawDataComplete = $rawComplete
        rawTreeSha256 = if ($rawComplete) { $RawTreeSha256 } else { $null }
        rawManifestRelativePath = if ($rawComplete) { $RawManifestRelativePath } else { $null }
        rawManifestSha256 = if ($rawComplete) { $RawManifestSha256 } else { $null }
        environmentEndSnapshotRelativePath = if ($rawComplete) { $EnvironmentEndSnapshotRelativePath } else { [string]$Current.environmentEndSnapshotRelativePath }
        environmentEndSnapshotSha256 = if ($rawComplete) { $EnvironmentEndSnapshotSha256 } else { [string]$Current.environmentEndSnapshotSha256 }
        automaticRetryAuthorized = $false
        automaticResumeAuthorized = $false
        topUpAuthorized = $false
        partialMergeAuthorized = $false
        formalCampaign = $false
        formalAnalysisAuthorized = $false
        gate14RAuthorized = $false
    }
    $null = Test-G13RPR2MP1V2CheckpointSchema $checkpoint
    return $checkpoint
}

function Write-G13RPR2MP1V2CheckpointTransition {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Status,
        [hashtable]$TransitionArguments = @{}
    )
    $current = Read-G13RPR2MP1V2Json $Path
    $null = Test-G13RPR2MP1V2CheckpointSchema $current
    $arguments = @{} + $TransitionArguments
    $arguments.Current = $current
    $arguments.Status = $Status
    $next = New-G13RPR2MP1V2CheckpointTransition @arguments
    $write = Write-G13RPR2MP1V2AtomicJson -Path $Path -Value $next -Depth 50 -Replace -PassThru
    $readBack = Read-G13RPR2MP1V2Json $Path
    $null = Test-G13RPR2MP1V2CheckpointSchema $readBack
    if ((Get-G13RPR2MP1V2Sha256 $Path) -ne [string]$write.sha256) { throw 'Checkpoint transition SHA-256 read-back mismatch.' }
    return $readBack
}

Export-ModuleMember -Function @(
    'Get-G13RPR2MP1V2Sha256','Read-G13RPR2MP1V2Json','Write-G13RPR2MP1V2AtomicJson',
    'Get-G13RPR2MP1V2CheckpointRequiredFields','Test-G13RPR2MP1V2CheckpointSchema',
    'New-G13RPR2MP1V2Checkpoint','New-G13RPR2MP1V2CheckpointTransition',
    'Write-G13RPR2MP1V2CheckpointTransition'
)
