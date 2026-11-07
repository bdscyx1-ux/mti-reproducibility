Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-G13RPR2Sha256 {
    param([Parameter(Mandatory = $true)][string]$Path)
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Get-G13RPR2StringSha256 {
    param([Parameter(Mandatory = $true)][string]$Text)
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        return ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Text)))).Replace('-', '').ToLowerInvariant()
    }
    finally { $sha.Dispose() }
}

function Read-G13RPR2Json {
    param([Parameter(Mandatory = $true)][string]$Path)
    return ([IO.File]::ReadAllText($Path, [Text.Encoding]::UTF8) | ConvertFrom-Json)
}

function ConvertTo-G13RPR2JsonText {
    param([Parameter(Mandatory = $true)]$Value, [int]$Depth = 60, [switch]$Compress)
    $text = if ($Compress) { $Value | ConvertTo-Json -Depth $Depth -Compress } else { $Value | ConvertTo-Json -Depth $Depth }
    return $text.Replace("`r`n", "`n").Replace("`r", "`n") + "`n"
}

function Write-G13RPR2AtomicJson {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)]$Value,
        [int]$Depth = 60,
        [switch]$AllowReplace
    )
    $full = [IO.Path]::GetFullPath($Path)
    $parent = [IO.Path]::GetDirectoryName($full)
    if (-not (Test-Path -LiteralPath $parent -PathType Container)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
    if ((Test-Path -LiteralPath $full) -and -not $AllowReplace) { throw "Atomic create-new target already exists: $full" }
    $temporary = Join-Path $parent ('.g13tmp-' + [Guid]::NewGuid().ToString('N'))
    $owned = $false
    try {
        [IO.File]::WriteAllText($temporary, (ConvertTo-G13RPR2JsonText -Value $Value -Depth $Depth), (New-Object Text.UTF8Encoding($false, $true)))
        $owned = $true
        if (Test-Path -LiteralPath $full) {
            $backup = Join-Path $parent ('.g13bak-' + [Guid]::NewGuid().ToString('N'))
            try { [IO.File]::Replace($temporary, $full, $backup); $owned = $false }
            finally { if (Test-Path -LiteralPath $backup) { [IO.File]::Delete($backup) } }
        }
        else { [IO.File]::Move($temporary, $full); $owned = $false }
    }
    finally { if ($owned -and (Test-Path -LiteralPath $temporary)) { [IO.File]::Delete($temporary) } }
}

function Test-G13RPR2PathWithin {
    param([Parameter(Mandatory = $true)][string]$BasePath, [Parameter(Mandatory = $true)][string]$CandidatePath, [switch]$AllowBase)
    $base = [IO.Path]::GetFullPath($BasePath).TrimEnd('\', '/')
    $candidate = [IO.Path]::GetFullPath($CandidatePath).TrimEnd('\', '/')
    if ($AllowBase -and $candidate.Equals($base, [StringComparison]::OrdinalIgnoreCase)) { return $true }
    return $candidate.StartsWith($base + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)
}

function Get-G13RPR2ProjectRelativePath {
    param([Parameter(Mandatory = $true)][string]$ProjectPath, [Parameter(Mandatory = $true)][string]$Path)
    $project = [IO.Path]::GetFullPath($ProjectPath).TrimEnd('\', '/')
    $full = [IO.Path]::GetFullPath($Path)
    $prefix = $project + [IO.Path]::DirectorySeparatorChar
    if (-not $full.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) { throw "Path escapes project root: $full" }
    return $full.Substring($prefix.Length).Replace('\', '/')
}

function Assert-G13RPR2BoundFile {
    param(
        [Parameter(Mandatory = $true)][string]$ProjectPath,
        [Parameter(Mandatory = $true)][string]$RelativePath,
        [Parameter(Mandatory = $true)][string]$ExpectedSha256,
        [Parameter(Mandatory = $true)][string]$Role
    )
    if ([IO.Path]::IsPathRooted($RelativePath)) { throw "$Role must be project-relative." }
    $full = [IO.Path]::GetFullPath((Join-Path $ProjectPath $RelativePath.Replace('/', '\')))
    if (-not (Test-G13RPR2PathWithin -BasePath $ProjectPath -CandidatePath $full)) { throw "$Role escapes the project root." }
    if (-not (Test-Path -LiteralPath $full -PathType Leaf)) { throw "$Role is missing: $RelativePath" }
    $actual = Get-G13RPR2Sha256 $full
    if ($actual -ne $ExpectedSha256.ToLowerInvariant()) { throw "$Role SHA-256 mismatch: expected=$ExpectedSha256 actual=$actual" }
    return $full
}

function Get-G13RPR2ExpectedAlgorithms {
    param([Parameter(Mandatory = $true)][string]$ComparisonCohortId)
    switch ($ComparisonCohortId) {
        'four-algorithm-shared-goal-v1' { return @('A*-R', 'D*L', 'C-FF', 'IDFF') }
        'per-agent-heterogeneous-goal-v1' { return @('A*-R', 'D*L') }
        'grouped-field-heterogeneous-goal-v1' { return @('C-FF', 'IDFF') }
        default { throw "Unsupported comparison cohort: $ComparisonCohortId" }
    }
}

function Get-G13RPR2WilliamsRow {
    param([Parameter(Mandatory = $true)][string[]]$Items, [Parameter(Mandatory = $true)][int]$RowIndex)
    $count = $Items.Count
    $baseIndices = New-Object int[] $count
    $baseIndices[0] = 0
    for ($step = 1; $step -lt $count; $step++) {
        $baseIndices[$step] = if (($step % 2) -eq 1) { ($step + 1) / 2 } else { $count - ($step / 2) }
    }
    $row = New-Object string[] $count
    for ($index = 0; $index -lt $count; $index++) { $row[$index] = $Items[($baseIndices[$index] + $RowIndex) % $count] }
    return $row
}

function New-G13RPR2BlockPlanFromScheduleRecord {
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
        planId = 'gate13r-pr2-formal-block-plan-v1'
        designId = 'gate10r-one-fresh-unity-process-per-williams-block-5pct-v1'
        blockId = [string]$ScheduleRecord.blockId
        campaignId = [string]$ScheduleRecord.campaignId
        scenarioRelativePath = [string]$ScheduleRecord.scenarioRelativePath
        scenarioSourceSha256 = [string]$ScheduleRecord.scenarioSha256
        comparisonCohortId = [string]$ScheduleRecord.comparisonCohortId
        block = [int]$ScheduleRecord.campaignBlockOrdinal
        williamsRowIndex = [int]$ScheduleRecord.williamsRowIndex
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
        globalProcessOrdinal = [int]$ScheduleRecord.globalProcessOrdinal
        matchedSuperblock = $ScheduleRecord.matchedSuperblock
        entries = $entries.ToArray()
    }
}

function Test-G13RPR2FormalExecutionReceipt {
    param(
        [Parameter(Mandatory = $true)]$Receipt,
        [Parameter(Mandatory = $true)][string]$ExpectedFormalRoot,
        [Parameter(Mandatory = $true)][hashtable]$ExpectedHashes,
        [DateTime]$NowUtc = ([DateTime]::UtcNow),
        [int]$MaximumPreflightAgeSeconds = 900
    )
    $errors = New-Object Collections.Generic.List[string]
    if ([int]$Receipt.schemaVersion -ne 1) { $errors.Add('schema') }
    if ([string]$Receipt.receiptKind -ne 'gate13r-pr2-s48-h48-formal-raw-acquisition-execution-receipt-v1') { $errors.Add('kind') }
    if ([string]$Receipt.status -ne 'AUTHORIZED-FOR-ONE-RAW-ACQUISITION-ATTEMPT') { $errors.Add('status') }
    if ($Receipt.formalCampaignAuthorized -ne $true -or $Receipt.rawAcquisitionAuthorized -ne $true -or $Receipt.formalAnalysisAuthorized -ne $false -or $Receipt.gate14RAuthorized -ne $false) { $errors.Add('authorization-boundary') }
    if ($Receipt.noAutomaticRetry -ne $true -or $Receipt.noAutomaticResume -ne $true -or $Receipt.noTopUp -ne $true -or $Receipt.noPartialMerge -ne $true) { $errors.Add('failure-policy') }
    if ([string]$Receipt.twoPhaseCommitId -ne 'gate13r-pr2-raw-analysis-two-phase-commit-v1') { $errors.Add('two-phase-id') }
    try { $actualRoot = [IO.Path]::GetFullPath([string]$Receipt.formalRootResolved).TrimEnd('\', '/') }
    catch { $actualRoot = ''; $errors.Add('root-parse') }
    $expectedRoot = [IO.Path]::GetFullPath($ExpectedFormalRoot).TrimEnd('\', '/')
    if (-not $actualRoot.Equals($expectedRoot, [StringComparison]::OrdinalIgnoreCase)) { $errors.Add('root') }
    foreach ($name in $ExpectedHashes.Keys) {
        if ([string]$Receipt.bindings.$name -ne ([string]$ExpectedHashes[$name]).ToLowerInvariant()) { $errors.Add("binding-$name") }
    }
    try {
        $captured = ([DateTime]$Receipt.preflightCompletedAtUtc).ToUniversalTime()
        $age = ($NowUtc.ToUniversalTime() - $captured).TotalSeconds
        if ($age -lt 0 -or $age -gt $MaximumPreflightAgeSeconds) { $errors.Add('preflight-stale') }
    }
    catch { $errors.Add('preflight-time') }
    if ([long]$Receipt.storage.availableFreeBytes -lt 57397541440L -or [long]$Receipt.storage.minimumLaunchFreeBytes -ne 57397541440L) { $errors.Add('storage') }
    return [pscustomobject][ordered]@{ passed = $errors.Count -eq 0; errors = $errors.ToArray() }
}

function Get-G13RPR2RawPayloadSnapshot {
    param([Parameter(Mandatory = $true)][string]$FormalRoot)
    $root = [IO.Path]::GetFullPath($FormalRoot).TrimEnd('\', '/')
    $excludedRootLeaves = @(
        'formal-checkpoint.json',
        'partial-output-manifest.json',
        'raw-execution-manifest.json',
        'raw-payload-file-manifest.jsonl',
        'raw-data-freeze-receipt.json',
        'environment-end-snapshot.json'
    )
    $records = New-Object Collections.Generic.List[object]
    foreach ($file in Get-ChildItem -LiteralPath $root -File -Recurse -Force) {
        $relative = $file.FullName.Substring($root.Length + 1).Replace('\', '/')
        if (($relative.IndexOf('/') -lt 0) -and ($excludedRootLeaves -contains $relative)) { continue }
        $records.Add([ordered]@{ relativePath = $relative; rawBytes = [long]$file.Length; sha256 = Get-G13RPR2Sha256 $file.FullName })
    }
    $array = @($records.ToArray())
    [Array]::Sort($array, [Collections.Generic.Comparer[object]]::Create([Comparison[object]]{
        param($left, $right)
        return [StringComparer]::Ordinal.Compare([string]$left.relativePath, [string]$right.relativePath)
    }))
    $builder = New-Object Text.StringBuilder
    $bytes = 0L
    foreach ($record in $array) {
        $bytes += [long]$record.rawBytes
        [void]$builder.Append([string]$record.relativePath).Append("`t").Append([string]$record.rawBytes).Append("`t").Append([string]$record.sha256).Append("`n")
    }
    return [pscustomobject][ordered]@{
        records = $array
        fileCount = $array.Count
        rawBytes = $bytes
        canonicalTreeSha256 = Get-G13RPR2StringSha256 $builder.ToString()
    }
}

function Write-G13RPR2RawPayloadFileManifest {
    param([Parameter(Mandatory = $true)][string]$Path, [Parameter(Mandatory = $true)]$Snapshot)
    if (Test-Path -LiteralPath $Path) { throw "Raw payload manifest already exists: $Path" }
    $parent = Split-Path -Parent $Path
    $temporary = Join-Path $parent ('.g13tmp-' + [Guid]::NewGuid().ToString('N'))
    $utf8 = New-Object Text.UTF8Encoding($false, $true)
    $writer = $null
    try {
        $writer = New-Object IO.StreamWriter($temporary, $false, $utf8)
        foreach ($record in @($Snapshot.records)) { $writer.Write((ConvertTo-G13RPR2JsonText -Value $record -Depth 10 -Compress)) }
        $writer.Dispose(); $writer = $null
        [IO.File]::Move($temporary, $Path)
    }
    finally {
        if ($null -ne $writer) { $writer.Dispose() }
        if (Test-Path -LiteralPath $temporary) { [IO.File]::Delete($temporary) }
    }
}

function Set-G13RPR2RawPayloadReadOnly {
    param([Parameter(Mandatory = $true)][string]$FormalRoot, [Parameter(Mandatory = $true)]$Snapshot)
    $root = [IO.Path]::GetFullPath($FormalRoot).TrimEnd('\', '/')
    foreach ($record in @($Snapshot.records)) {
        $path = [IO.Path]::GetFullPath((Join-Path $root ([string]$record.relativePath).Replace('/', '\')))
        if (-not (Test-G13RPR2PathWithin -BasePath $root -CandidatePath $path)) { throw "Payload path escapes root: $path" }
        $item = Get-Item -LiteralPath $path -Force
        $item.IsReadOnly = $true
    }
}

Export-ModuleMember -Function @(
    'Get-G13RPR2Sha256',
    'Get-G13RPR2StringSha256',
    'Read-G13RPR2Json',
    'ConvertTo-G13RPR2JsonText',
    'Write-G13RPR2AtomicJson',
    'Test-G13RPR2PathWithin',
    'Get-G13RPR2ProjectRelativePath',
    'Assert-G13RPR2BoundFile',
    'Get-G13RPR2ExpectedAlgorithms',
    'Get-G13RPR2WilliamsRow',
    'New-G13RPR2BlockPlanFromScheduleRecord',
    'Test-G13RPR2FormalExecutionReceipt',
    'Get-G13RPR2RawPayloadSnapshot',
    'Write-G13RPR2RawPayloadFileManifest',
    'Set-G13RPR2RawPayloadReadOnly'
)
