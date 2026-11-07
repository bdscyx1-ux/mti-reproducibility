Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-G13RLowerSha256 {
    param([Parameter(Mandatory = $true)][string]$Path)
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Get-G13RStringSha256 {
    param([Parameter(Mandatory = $true)][string]$Text)
    $bytes = [Text.Encoding]::UTF8.GetBytes($Text)
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-', '').ToLowerInvariant() }
    finally { $sha.Dispose() }
}

function Read-G13RJson {
    param([Parameter(Mandatory = $true)][string]$Path)
    return (Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json)
}

function ConvertTo-G13RJsonText {
    param(
        [Parameter(Mandatory = $true)]$Value,
        [int]$Depth = 50,
        [switch]$Compress
    )
    $text = if ($Compress) { $Value | ConvertTo-Json -Depth $Depth -Compress } else { $Value | ConvertTo-Json -Depth $Depth }
    return $text.Replace("`r`n", "`n").Replace("`r", "`n") + "`n"
}

function Write-G13RUtf8NoBomJson {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)]$Value,
        [int]$Depth = 50,
        [switch]$Compress
    )
    $parent = Split-Path -Parent $Path
    if (-not [string]::IsNullOrWhiteSpace($parent) -and -not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }
    [IO.File]::WriteAllText($Path, (ConvertTo-G13RJsonText -Value $Value -Depth $Depth -Compress:$Compress), (New-Object Text.UTF8Encoding($false, $true)))
}

function Write-G13RAtomicUtf8NoBomJson {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)]$Value,
        [int]$Depth = 50
    )
    $parent = Split-Path -Parent $Path
    if (-not [string]::IsNullOrWhiteSpace($parent) -and -not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }
    $temporary = $Path + '.tmp-' + [Guid]::NewGuid().ToString('N')
    try {
        Write-G13RUtf8NoBomJson -Path $temporary -Value $Value -Depth $Depth
        if (Test-Path -LiteralPath $Path) {
            $backup = $Path + '.replace-backup-' + [Guid]::NewGuid().ToString('N')
            try { [IO.File]::Replace($temporary, $Path, $backup) }
            finally { if (Test-Path -LiteralPath $backup) { [IO.File]::Delete($backup) } }
        }
        else { [IO.File]::Move($temporary, $Path) }
    }
    finally { if (Test-Path -LiteralPath $temporary) { [IO.File]::Delete($temporary) } }
}

function Get-G13RProjectRelativePath {
    param(
        [Parameter(Mandatory = $true)][string]$ProjectPath,
        [Parameter(Mandatory = $true)][string]$Path
    )
    $project = [IO.Path]::GetFullPath($ProjectPath).TrimEnd('\', '/')
    $full = [IO.Path]::GetFullPath($Path)
    $prefix = $project + [IO.Path]::DirectorySeparatorChar
    if (-not $full.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) { throw "Path escapes project root: $full" }
    return $full.Substring($prefix.Length).Replace('\', '/')
}

function Test-G13RPathWithin {
    param(
        [Parameter(Mandatory = $true)][string]$BasePath,
        [Parameter(Mandatory = $true)][string]$CandidatePath,
        [switch]$AllowBase
    )
    $base = [IO.Path]::GetFullPath($BasePath).TrimEnd('\', '/')
    $candidate = [IO.Path]::GetFullPath($CandidatePath).TrimEnd('\', '/')
    if ($AllowBase -and $candidate.Equals($base, [StringComparison]::OrdinalIgnoreCase)) { return $true }
    return $candidate.StartsWith($base + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)
}

function Assert-G13RBoundFile {
    param(
        [Parameter(Mandatory = $true)][string]$ProjectPath,
        [Parameter(Mandatory = $true)][string]$RelativePath,
        [Parameter(Mandatory = $true)][string]$ExpectedSha256,
        [Parameter(Mandatory = $true)][string]$Role
    )
    if ([IO.Path]::IsPathRooted($RelativePath)) { throw "$Role path must be project-relative." }
    $full = [IO.Path]::GetFullPath((Join-Path $ProjectPath $RelativePath.Replace('/', '\')))
    if (-not (Test-G13RPathWithin -BasePath $ProjectPath -CandidatePath $full)) { throw "$Role path escapes the project." }
    if (-not (Test-Path -LiteralPath $full -PathType Leaf)) { throw "$Role is missing: $RelativePath" }
    $actual = Get-G13RLowerSha256 $full
    if ($actual -ne $ExpectedSha256.ToLowerInvariant()) { throw "$Role SHA-256 mismatch: expected=$ExpectedSha256 actual=$actual" }
    return $full
}

function Get-G13RAlgorithmSlug {
    param([Parameter(Mandatory = $true)][string]$AlgorithmId)
    switch ($AlgorithmId) {
        'A*-R' { return 'astar-r' }
        'D*L' { return 'dstar-l' }
        'C-FF' { return 'cff' }
        'IDFF' { return 'idff' }
        default { throw "Unsupported algorithm ID: $AlgorithmId" }
    }
}

function Get-G13RExpectedAlgorithms {
    param([Parameter(Mandatory = $true)][string]$ComparisonCohortId)
    switch ($ComparisonCohortId) {
        'four-algorithm-shared-goal-v1' { return @('A*-R', 'D*L', 'IDFF', 'C-FF') }
        'per-agent-heterogeneous-goal-v1' { return @('A*-R', 'D*L') }
        'grouped-field-heterogeneous-goal-v1' { return @('C-FF', 'IDFF') }
        default { throw "Unsupported comparison cohort: $ComparisonCohortId" }
    }
}

function Get-G13RCandidateBlocks {
    param([Parameter(Mandatory = $true)][string]$ComparisonCohortId)
    switch ($ComparisonCohortId) {
        'four-algorithm-shared-goal-v1' { return 548 }
        'per-agent-heterogeneous-goal-v1' { return 768 }
        'grouped-field-heterogeneous-goal-v1' { return 400 }
        default { throw "Unsupported comparison cohort: $ComparisonCohortId" }
    }
}

function Test-G13RSafeId {
    param([Parameter(Mandatory = $true)][string]$Value)
    return $Value -match '^[A-Za-z0-9][A-Za-z0-9_.-]{0,127}$'
}

function Test-G13RStorageGate {
    param(
        [Parameter(Mandatory = $true)][long]$AvailableFreeBytes,
        [long]$MinimumLaunchFreeBytes = 188047724816,
        [Parameter(Mandatory = $true)][string]$ExpectedVolumeRoot,
        [Parameter(Mandatory = $true)][string]$ObservedVolumeRoot,
        [Parameter(Mandatory = $true)][DateTime]$CheckedAtUtc,
        [DateTime]$NowUtc = ([DateTime]::UtcNow),
        [int]$MaximumAgeSeconds = 300,
        [switch]$OriginalByteCount,
        [switch]$LaunchContext
    )
    $errors = New-Object Collections.Generic.List[string]
    if ($AvailableFreeBytes -lt 0) { $errors.Add('available-free-bytes-negative') }
    if ($MinimumLaunchFreeBytes -ne 188047724816) { $errors.Add('minimum-launch-threshold-changed') }
    if (-not $OriginalByteCount) { $errors.Add('free-space-not-original-byte-count') }
    $expectedVolume = [IO.Path]::GetPathRoot([IO.Path]::GetFullPath($ExpectedVolumeRoot))
    $observedVolume = [IO.Path]::GetPathRoot([IO.Path]::GetFullPath($ObservedVolumeRoot))
    if (-not $expectedVolume.Equals($observedVolume, [StringComparison]::OrdinalIgnoreCase)) { $errors.Add('observed-volume-mismatch') }
    $age = ($NowUtc.ToUniversalTime() - $CheckedAtUtc.ToUniversalTime()).TotalSeconds
    if ($age -lt 0 -or $age -gt $MaximumAgeSeconds) { $errors.Add('storage-snapshot-stale-or-future') }
    if ($AvailableFreeBytes -lt $MinimumLaunchFreeBytes) { $errors.Add('insufficient-free-bytes') }
    return [pscustomobject]@{
        schemaVersion = 1
        resultKind = 'gate13r-raw-byte-storage-preflight-result-v1'
        checkedAtUtc = $CheckedAtUtc.ToUniversalTime().ToString('o')
        availableFreeBytes = $AvailableFreeBytes
        minimumLaunchFreeBytes = $MinimumLaunchFreeBytes
        expectedVolumeRoot = $expectedVolume
        observedVolumeRoot = $observedVolume
        originalByteCount = [bool]$OriginalByteCount
        launchContext = [bool]$LaunchContext
        authorizing = [bool]$LaunchContext -and $errors.Count -eq 0
        errors = $errors.ToArray()
        passed = $errors.Count -eq 0
    }
}

function Test-G13RFormalExecutionReceipt {
    param(
        [Parameter(Mandatory = $true)]$Receipt,
        [Parameter(Mandatory = $true)][string]$ExpectedFormalRoot,
        [Parameter(Mandatory = $true)][string]$ExpectedConfigSha256,
        [Parameter(Mandatory = $true)][string]$ExpectedAmendmentSha256,
        [Parameter(Mandatory = $true)][string]$ExpectedProvenanceSha256,
        [Parameter(Mandatory = $true)][string]$ExpectedScheduleManifestSha256,
        [Parameter(Mandatory = $true)][string]$ExpectedOrchestratorSha256,
        [Parameter(Mandatory = $true)][string]$ExpectedUnityCommandSha256,
        [DateTime]$NowUtc = ([DateTime]::UtcNow),
        [int]$MaximumPreflightAgeSeconds = 300
    )
    $errors = New-Object Collections.Generic.List[string]
    if ([int]$Receipt.schemaVersion -ne 1) { $errors.Add('receipt-schema-invalid') }
    if ([string]$Receipt.receiptKind -ne 'gate13r-formal-campaign-execution-receipt-v1') { $errors.Add('receipt-kind-invalid') }
    if ([string]$Receipt.authorizationKind -ne 'gate13r-formal-campaign-user-authorization-v1') { $errors.Add('formal-user-authorization-kind-invalid') }
    if ($Receipt.formalCampaignAuthorized -ne $true -or $Receipt.formalExecutionAuthorized -ne $true) { $errors.Add('formal-execution-not-authorized') }
    if ($Receipt.consumed -ne $false) { $errors.Add('receipt-already-consumed') }
    if ($Receipt.noAutomaticRetry -ne $true -or $Receipt.noAutomaticResume -ne $true) { $errors.Add('retry-resume-policy-invalid') }
    $resolvedExpectedRoot = [IO.Path]::GetFullPath($ExpectedFormalRoot).TrimEnd('\', '/')
    try { $resolvedReceiptRoot = [IO.Path]::GetFullPath([string]$Receipt.formalRootResolved).TrimEnd('\', '/') }
    catch { $resolvedReceiptRoot = ''; $errors.Add('formal-root-path-invalid') }
    if (-not $resolvedReceiptRoot.Equals($resolvedExpectedRoot, [StringComparison]::OrdinalIgnoreCase)) { $errors.Add('formal-root-mismatch') }
    $pairs = @(
        @('configSha256', $ExpectedConfigSha256),
        @('amendmentSha256', $ExpectedAmendmentSha256),
        @('provenanceSha256', $ExpectedProvenanceSha256),
        @('scheduleManifestSha256', $ExpectedScheduleManifestSha256),
        @('orchestratorSha256', $ExpectedOrchestratorSha256),
        @('unityCommandSha256', $ExpectedUnityCommandSha256)
    )
    foreach ($pair in $pairs) {
        $property = [string]$pair[0]
        $expected = ([string]$pair[1]).ToLowerInvariant()
        if ([string]$Receipt.$property -ne $expected) { $errors.Add("binding-mismatch-$property") }
    }
    if ($null -eq $Receipt.storagePreflight) { $errors.Add('storage-preflight-missing') }
    else {
        try {
            $storage = Test-G13RStorageGate -AvailableFreeBytes ([long]$Receipt.storagePreflight.availableFreeBytes) -MinimumLaunchFreeBytes ([long]$Receipt.storagePreflight.minimumLaunchFreeBytes) -ExpectedVolumeRoot $resolvedExpectedRoot -ObservedVolumeRoot ([string]$Receipt.storagePreflight.observedVolumeRoot) -CheckedAtUtc ([DateTime]$Receipt.storagePreflight.checkedAtUtc) -NowUtc $NowUtc -MaximumAgeSeconds $MaximumPreflightAgeSeconds -OriginalByteCount:([bool]$Receipt.storagePreflight.originalByteCount) -LaunchContext
            foreach ($storageError in @($storage.errors)) { $errors.Add("storage-$storageError") }
        }
        catch { $errors.Add('storage-preflight-malformed') }
    }
    if ($null -eq $Receipt.environmentPreflight -or $Receipt.environmentPreflight.passed -ne $true) { $errors.Add('environment-preflight-invalid') }
    return [pscustomobject]@{
        schemaVersion = 1
        resultKind = 'gate13r-formal-execution-receipt-validation-v1'
        errors = $errors.ToArray()
        passed = $errors.Count -eq 0
    }
}

function New-G13RBlockPlanFromScheduleRecord {
    param(
        [Parameter(Mandatory = $true)]$ScheduleRecord,
        [Parameter(Mandatory = $true)][string]$FormalConfigRelativePath,
        [Parameter(Mandatory = $true)][string]$FormalConfigSha256,
        [Parameter(Mandatory = $true)][string]$SpecificationRelativePath,
        [Parameter(Mandatory = $true)][string]$SpecificationSha256,
        [Parameter(Mandatory = $true)][string]$TestDesignRelativePath,
        [Parameter(Mandatory = $true)][string]$TestDesignSha256,
        [Parameter(Mandatory = $true)][string]$AmendmentRelativePath,
        [Parameter(Mandatory = $true)][string]$AmendmentSha256,
        [Parameter(Mandatory = $true)][string]$CommandRelativePath,
        [Parameter(Mandatory = $true)][string]$CommandSha256,
        [Parameter(Mandatory = $true)][string]$ProvenanceRelativePath,
        [Parameter(Mandatory = $true)][string]$ProvenanceSha256,
        [Parameter(Mandatory = $true)][string]$ExecutionReceiptRelativePath,
        [Parameter(Mandatory = $true)][string]$ExecutionReceiptSha256
    )
    $entries = New-Object Collections.Generic.List[object]
    foreach ($entry in @($ScheduleRecord.entries)) {
        $entries.Add([ordered]@{
            position = [int]$entry.position
            algorithmId = [string]$entry.algorithmId
            predecessorAlgorithmId = [string]$entry.predecessorAlgorithmId
            runId = [string]$entry.runId
            directory = [string]$entry.childDirectory
        })
    }
    return [ordered]@{
        schemaVersion = 2
        planId = 'gate13r-formal-block-plan-v1'
        designId = 'gate10r-one-fresh-unity-process-per-williams-block-5pct-v1'
        blockId = [string]$ScheduleRecord.blockId
        campaignId = [string]$ScheduleRecord.campaignId
        scenarioRelativePath = [string]$ScheduleRecord.scenarioRelativePath
        scenarioSourceSha256 = [string]$ScheduleRecord.scenarioSha256
        comparisonCohortId = [string]$ScheduleRecord.comparisonCohortId
        block = [int]$ScheduleRecord.campaignBlockOrdinal
        formalCampaign = $true
        analysisRole = 'formal-timing'
        verificationInjectedFailurePosition = 0
        formalConfigRelativePath = $FormalConfigRelativePath
        formalConfigSha256 = $FormalConfigSha256
        specificationRelativePath = $SpecificationRelativePath
        specificationSha256 = $SpecificationSha256
        testDesignRelativePath = $TestDesignRelativePath
        testDesignSha256 = $TestDesignSha256
        amendmentRelativePath = $AmendmentRelativePath
        amendmentSha256 = $AmendmentSha256
        commandRelativePath = $CommandRelativePath
        commandSha256 = $CommandSha256
        provenanceRelativePath = $ProvenanceRelativePath
        provenanceSha256 = $ProvenanceSha256
        executionReceiptRelativePath = $ExecutionReceiptRelativePath
        executionReceiptSha256 = $ExecutionReceiptSha256
        entries = $entries.ToArray()
    }
}

function Test-G13RCheckpointFixture {
    param(
        [Parameter(Mandatory = $true)]$Checkpoint,
        [Parameter(Mandatory = $true)]$ScheduleRecord,
        [switch]$ExpectFailure
    )
    $errors = New-Object Collections.Generic.List[string]
    $expectedSamples = [int]$ScheduleRecord.expectedSampleCount
    if ([string]$Checkpoint.blockId -ne [string]$ScheduleRecord.blockId) { $errors.Add('checkpoint-block-id-mismatch') }
    if ([int]$Checkpoint.expectedSampleCount -ne $expectedSamples) { $errors.Add('checkpoint-expected-sample-count-mismatch') }
    if ([int]$Checkpoint.completedSampleCount -lt 0 -or [int]$Checkpoint.completedSampleCount -gt $expectedSamples) { $errors.Add('checkpoint-completed-count-invalid') }
    if ($Checkpoint.automaticRetryAttempted -ne $false -or $Checkpoint.automaticResumeAttempted -ne $false) { $errors.Add('checkpoint-retry-resume-invalid') }
    if ($ExpectFailure) {
        if ([string]$Checkpoint.status -ne 'failed-no-auto-retry-no-resume') { $errors.Add('failure-checkpoint-status-invalid') }
        if ([int]$Checkpoint.completedSampleCount -ge $expectedSamples) { $errors.Add('failed-checkpoint-cannot-be-complete') }
        if ($Checkpoint.eligibleForFormalAnalysis -ne $false) { $errors.Add('failed-checkpoint-cannot-be-eligible') }
    }
    else {
        if ([string]$Checkpoint.status -ne 'block-completed') { $errors.Add('complete-checkpoint-status-invalid') }
        if ([int]$Checkpoint.completedSampleCount -ne $expectedSamples) { $errors.Add('complete-checkpoint-count-invalid') }
        if ($Checkpoint.eligibleForFormalAnalysis -ne $true) { $errors.Add('complete-checkpoint-eligibility-invalid') }
    }
    return [pscustomobject]@{ errors = $errors.ToArray(); passed = $errors.Count -eq 0 }
}

Export-ModuleMember -Function @(
    'Get-G13RLowerSha256',
    'Get-G13RStringSha256',
    'Read-G13RJson',
    'ConvertTo-G13RJsonText',
    'Write-G13RUtf8NoBomJson',
    'Write-G13RAtomicUtf8NoBomJson',
    'Get-G13RProjectRelativePath',
    'Test-G13RPathWithin',
    'Assert-G13RBoundFile',
    'Get-G13RAlgorithmSlug',
    'Get-G13RExpectedAlgorithms',
    'Get-G13RCandidateBlocks',
    'Test-G13RSafeId',
    'Test-G13RStorageGate',
    'Test-G13RFormalExecutionReceipt',
    'New-G13RBlockPlanFromScheduleRecord',
    'Test-G13RCheckpointFixture'
)
