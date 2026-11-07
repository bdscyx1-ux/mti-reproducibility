Set-StrictMode -Version Latest
$script:G13R2V2Utf8 = New-Object System.Text.UTF8Encoding($false)
$script:G13R2V2ProjectRoot = [System.IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$script:G13R2V2ScheduleModulePath = Join-Path $PSScriptRoot 'Gate13FormalPreparation.psm1'
Import-Module $script:G13R2V2ScheduleModulePath -Force

function Get-G13R2V2LowerSha256 {
    param([Parameter(Mandatory = $true)][string]$Path)
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Read-G13R2V2Json {
    param([Parameter(Mandatory = $true)][string]$Path)
    return Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
}

function ConvertTo-G13R2V2JsonText {
    param([Parameter(Mandatory = $true)]$Value, [int]$Depth = 50)
    $text = $Value | ConvertTo-Json -Depth $Depth
    $text = $text.Replace("`r`n", "`n").Replace("`r", "`n")
    if (-not $text.EndsWith("`n")) { $text += "`n" }
    return $text
}

function Write-G13R2V2Utf8NoBomJson {
    param([Parameter(Mandatory = $true)][string]$Path, [Parameter(Mandatory = $true)]$Value, [int]$Depth = 50)
    [System.IO.File]::WriteAllText($Path, (ConvertTo-G13R2V2JsonText -Value $Value -Depth $Depth), $script:G13R2V2Utf8)
}

function Write-G13R2V2AtomicUtf8NoBomJson {
    param([Parameter(Mandatory = $true)][string]$Path, [Parameter(Mandatory = $true)]$Value, [int]$Depth = 50)
    $directory = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $directory -PathType Container)) { New-Item -ItemType Directory -Path $directory | Out-Null }
    $temporary = $Path + '.tmp-' + [Guid]::NewGuid().ToString('N')
    Write-G13R2V2Utf8NoBomJson -Path $temporary -Value $Value -Depth $Depth
    Move-Item -LiteralPath $temporary -Destination $Path -Force
}

function Get-G13R2V2ProjectRelativePath {
    param([Parameter(Mandatory = $true)][string]$ProjectPath, [Parameter(Mandatory = $true)][string]$FullPath)
    $root = [System.IO.Path]::GetFullPath($ProjectPath).TrimEnd('\') + '\'
    $candidate = [System.IO.Path]::GetFullPath($FullPath)
    if (-not $candidate.StartsWith($root, [System.StringComparison]::OrdinalIgnoreCase)) { throw "Path escapes the project: $candidate" }
    return $candidate.Substring($root.Length).Replace('\', '/')
}

function Assert-G13R2V2BoundFile {
    param(
        [Parameter(Mandatory = $true)][string]$ProjectPath,
        [Parameter(Mandatory = $true)][string]$RelativePath,
        [Parameter(Mandatory = $true)][string]$ExpectedSha256,
        [Parameter(Mandatory = $true)][string]$Label
    )
    $path = [System.IO.Path]::GetFullPath((Join-Path $ProjectPath $RelativePath.Replace('/', '\')))
    $root = [System.IO.Path]::GetFullPath($ProjectPath).TrimEnd('\') + '\'
    if (-not $path.StartsWith($root, [System.StringComparison]::OrdinalIgnoreCase)) { throw "$Label escapes the project: $path" }
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "$Label is missing: $path" }
    $actual = Get-G13R2V2LowerSha256 -Path $path
    if ($actual -ne $ExpectedSha256) { throw "$Label hash mismatch: expected $ExpectedSha256, actual $actual" }
    return $path
}

function Get-G13R2V2AlgorithmSlug {
    param([Parameter(Mandatory = $true)][string]$AlgorithmId)
    switch ($AlgorithmId) {
        'A*-R' { return 'astar-r' }
        'D*L' { return 'dstar-l' }
        'C-FF' { return 'cff' }
        'IDFF' { return 'idff' }
        default { throw "Unsupported algorithm: $AlgorithmId" }
    }
}

function Get-G13R2V2CohortAlgorithms {
    param([Parameter(Mandatory = $true)][string]$ComparisonCohortId)
    switch ($ComparisonCohortId) {
        'four-algorithm-shared-goal-v1' { return [string[]]@('A*-R', 'D*L', 'C-FF', 'IDFF') }
        'per-agent-heterogeneous-goal-v1' { return [string[]]@('A*-R', 'D*L') }
        'grouped-field-heterogeneous-goal-v1' { return [string[]]@('C-FF', 'IDFF') }
        default { throw "Unsupported cohort: $ComparisonCohortId" }
    }
}

function Get-G13R2V2WilliamsRow {
    param(
        [Parameter(Mandatory = $true)][string[]]$Algorithms,
        [Parameter(Mandatory = $true)][ValidateRange(1, 148)][int]$Block
    )
    $count = $Algorithms.Count
    if ($count -notin @(2, 4)) { throw 'Only two- and four-algorithm Williams rows are authorized.' }
    $base = New-Object int[] $count
    $base[0] = 0
    for ($step = 1; $step -lt $count; $step++) { $base[$step] = if ($step % 2 -eq 1) { ($step + 1) / 2 } else { $count - ($step / 2) } }
    $rowIndex = ($Block - 1) % $count
    $row = New-Object string[] $count
    for ($index = 0; $index -lt $count; $index++) { $row[$index] = $Algorithms[($base[$index] + $rowIndex) % $count] }
    return $row
}

function Test-G13R2V2BlockPlanObject {
    param([Parameter(Mandatory = $true)]$Plan)
    $errors = New-Object System.Collections.Generic.List[string]
    try {
        if ([int]$Plan.schemaVersion -ne 2 -or [string]$Plan.designId -ne 'one-fresh-unity-process-per-williams-block-v2-native-telemetry' -or $Plan.formalCampaign -ne $false) { throw 'Block plan schema/design/formal boundary mismatch.' }
        if ([int]$Plan.block -lt 1 -or [int]$Plan.block -gt 148) { throw 'Block ordinal is outside 1..148.' }
        if ([int]$Plan.verificationInjectedFailurePosition -lt 0 -or [int]$Plan.verificationInjectedFailurePosition -gt @($Plan.entries).Count) { throw 'Injected failure position is outside the block.' }
        if ([int]$Plan.verificationInjectedFailurePosition -gt 0 -and [string]$Plan.analysisRole -ne 'excluded-negative-fail-closed-verification') { throw 'Injected failure is allowed only in the excluded negative verification fixture.' }
        foreach ($id in @([string]$Plan.planId, [string]$Plan.blockId, [string]$Plan.campaignId)) { if ($id -notmatch '^[A-Za-z0-9][A-Za-z0-9_.-]{0,127}$') { throw 'Unsafe plan/block/campaign identity.' } }
        $algorithms = @(Get-G13R2V2CohortAlgorithms -ComparisonCohortId ([string]$Plan.comparisonCohortId))
        $expectedRow = @(Get-G13R2V2WilliamsRow -Algorithms $algorithms -Block ([int]$Plan.block))
        $entries = @($Plan.entries)
        if ($entries.Count -ne $algorithms.Count) { throw 'Block-plan entry count does not match cohort.' }
        $seenAlgorithms = New-Object System.Collections.Generic.HashSet[string]
        $seenRuns = New-Object System.Collections.Generic.HashSet[string]
        $seenDirectories = New-Object System.Collections.Generic.HashSet[string]
        for ($index = 0; $index -lt $entries.Count; $index++) {
            $entry = $entries[$index]
            $expectedPredecessor = if ($index -eq 0) { 'NONE' } else { [string]$entries[$index - 1].algorithmId }
            if ([int]$entry.position -ne $index + 1) { throw 'Block positions must be contiguous and one-based.' }
            if ([string]$entry.algorithmId -ne [string]$expectedRow[$index]) { throw 'Block order differs from the frozen Williams row.' }
            if ([string]$entry.predecessorAlgorithmId -ne $expectedPredecessor) { throw 'Predecessor identity mismatch.' }
            if (-not $seenAlgorithms.Add([string]$entry.algorithmId)) { throw 'Duplicate algorithm in block plan.' }
            if ([string]$entry.runId -notmatch '^[A-Za-z0-9][A-Za-z0-9_.-]{0,127}$' -or -not $seenRuns.Add([string]$entry.runId)) { throw 'Unsafe or duplicate run ID.' }
            $directory = [string]$entry.directory
            if ([string]::IsNullOrWhiteSpace($directory) -or [System.IO.Path]::IsPathRooted($directory) -or $directory -match '(^|[\\/])\.\.([\\/]|$)') { throw 'Unsafe child directory.' }
            if (-not $seenDirectories.Add($directory)) { throw 'Duplicate child directory.' }
        }
    } catch { $errors.Add($_.Exception.Message) }
    return [pscustomobject][ordered]@{ passed = $errors.Count -eq 0; errors = $errors.ToArray() }
}

function Test-G13R2V2PilotPlan {
    param(
        [Parameter(Mandatory = $true)][string]$ProjectPath,
        [Parameter(Mandatory = $true)]$Plan,
        [string]$PlanPath
    )
    $errors = New-Object System.Collections.Generic.List[string]
    try {
        if ([int]$Plan.schemaVersion -ne 1 -or [string]$Plan.planId -ne 'gate13-r2-v2-native-telemetry-pilot-plan-v1') { throw 'V2 pilot plan identity mismatch.' }
        if ($Plan.authorizationBoundary.formalCampaignAuthorized -ne $false -or $Plan.authorizationBoundary.formalOutputRootCreationAllowed -ne $false -or [int]$Plan.authorizationBoundary.freshNonFormalPilotAuthorizedCount -ne 1) { throw 'V2 authorization boundary mismatch.' }
        if ([string]$Plan.processReusePolicy.designId -ne 'one-fresh-unity-process-per-williams-block-v2-native-telemetry') { throw 'V2 design mismatch.' }
        if ($Plan.processReusePolicy.oneBlockPerUnityProcess -ne $true -or $Plan.processReusePolicy.oneSamplePerAlgorithmPerProcess -ne $true -or $Plan.processReusePolicy.longLivedCampaignProcessAllowed -ne $false) { throw 'V2 process ownership mismatch.' }
        if ([long]$Plan.hardMemoryLimits.maximumSampleRetainedManagedGrowthBytes -ne 134217728 -or [long]$Plan.hardMemoryLimits.maximumBlockRetainedManagedGrowthBytes -ne 134217728) { throw 'Frozen 128 MiB managed-memory rules changed.' }
        if ([long]$Plan.hardMemoryLimits.maximumBlockWorkingSetGrowthBytes -ne 536870912 -or [long]$Plan.hardMemoryLimits.maximumBlockPrivateMemoryGrowthBytes -ne 536870912) { throw 'Frozen 512 MiB native-memory rules changed.' }
        if ([long]$Plan.telemetryProbe.absoluteToleranceFloorBytes -ne 67108864 -or [double]$Plan.telemetryProbe.relativeToleranceFraction -ne 0.25) { throw 'Telemetry cross-check tolerance changed.' }
        foreach ($property in $Plan.frozenInputs.PSObject.Properties) {
            [void](Assert-G13R2V2BoundFile -ProjectPath $ProjectPath -RelativePath ([string]$property.Value.relativePath) -ExpectedSha256 ([string]$property.Value.sha256) -Label ('V2 frozen input ' + $property.Name))
        }
        if (@($Plan.measuredCampaigns).Count -ne 3) { throw 'V2 pilot must contain exactly three measured campaigns.' }
        $processes = [int](($Plan.measuredCampaigns | Measure-Object -Property expectedBlockProcessCount -Sum).Sum)
        $samples = [int](($Plan.measuredCampaigns | Measure-Object -Property expectedSampleCount -Sum).Sum)
        if ($processes -ne 36 -or $samples -ne 96 -or [int]$Plan.totals.totalUnityProcessCount -ne 45 -or [int]$Plan.totals.totalSampleCount -ne 108) { throw 'V2 pilot cardinality mismatch.' }
        foreach ($campaign in @($Plan.measuredCampaigns)) {
            $algorithms = @(Get-G13R2V2CohortAlgorithms -ComparisonCohortId ([string]$campaign.comparisonCohortId))
            if ([int]$campaign.blocks -ne 12 -or [int]$campaign.expectedBlockProcessCount -ne 12 -or [int]$campaign.expectedSampleCount -ne 12 * $algorithms.Count) { throw "V2 measured campaign cardinality mismatch: $($campaign.campaignId)" }
            if ((@($campaign.algorithms) -join '|') -ne ($algorithms -join '|')) { throw "V2 measured cohort mismatch: $($campaign.campaignId)" }
            [void](Assert-G13R2V2BoundFile -ProjectPath $ProjectPath -RelativePath ([string]$campaign.scenarioRelativePath) -ExpectedSha256 ([string]$campaign.scenarioSourceSha256) -Label ('V2 pilot scenario ' + $campaign.scenarioId))
        }
        $formalRoot = [System.IO.Path]::GetFullPath((Join-Path $ProjectPath ([string]$Plan.paths.reservedFormalRootRelativePath).Replace('/', '\')))
        if (Test-Path -LiteralPath $formalRoot) { throw "Reserved process-reuse formal root exists: $formalRoot" }
        if (-not [string]::IsNullOrWhiteSpace($PlanPath) -and -not (Test-Path -LiteralPath $PlanPath -PathType Leaf)) { throw 'V2 pilot plan file is missing.' }
    } catch { $errors.Add($_.Exception.Message) }
    return [pscustomobject][ordered]@{
        passed = $errors.Count -eq 0
        errors = $errors.ToArray()
        measuredBlockProcessCount = 36
        measuredSampleCount = 96
        formalExecutionAuthorized = $false
    }
}

function New-G13R2V2BlockPlan {
    param(
        [Parameter(Mandatory = $true)][string]$ProjectPath,
        [Parameter(Mandatory = $true)]$PilotPlan,
        [Parameter(Mandatory = $true)]$Provenance,
        [Parameter(Mandatory = $true)][string]$CampaignId,
        [Parameter(Mandatory = $true)][string]$ScenarioRelativePath,
        [Parameter(Mandatory = $true)][string]$ScenarioSourceSha256,
        [Parameter(Mandatory = $true)][string]$ComparisonCohortId,
        [Parameter(Mandatory = $true)][ValidateRange(1, 148)][int]$Block,
        [Parameter(Mandatory = $true)][string]$ProvenancePath,
        [Parameter(Mandatory = $true)][string]$TelemetryProbeResultPath,
        [switch]$Warmup
    )
    if ($CampaignId -notmatch '^[A-Za-z0-9][A-Za-z0-9_.-]{0,95}$') { throw 'Unsafe campaign ID.' }
    $ProjectPath = [System.IO.Path]::GetFullPath($ProjectPath)
    $ProvenancePath = [System.IO.Path]::GetFullPath($ProvenancePath)
    $TelemetryProbeResultPath = [System.IO.Path]::GetFullPath($TelemetryProbeResultPath)
    $probe = Read-G13R2V2Json -Path $TelemetryProbeResultPath
    if ($probe.passed -ne $true -or [string]$probe.executionDesignId -ne 'one-fresh-unity-process-per-williams-block-v2-native-telemetry') { throw 'A successful frozen v2 telemetry probe is required.' }
    $algorithms = @(Get-G13R2V2CohortAlgorithms -ComparisonCohortId $ComparisonCohortId)
    $scheduleBlocks = if ($Block % $algorithms.Count -eq 0) { $Block } else { $Block + ($algorithms.Count - ($Block % $algorithms.Count)) }
    $schedule = New-Gate13WilliamsSchedule -CampaignId $CampaignId -ComparisonCohortId $ComparisonCohortId -Blocks $scheduleBlocks
    $sourceEntries = @($schedule.entries | Where-Object { [int]$_.block -eq $Block } | Sort-Object position)
    if ($sourceEntries.Count -ne $algorithms.Count) { throw 'Could not reconstruct a complete Williams block.' }
    $entries = New-Object System.Collections.Generic.List[object]
    for ($index = 0; $index -lt $sourceEntries.Count; $index++) {
        $source = $sourceEntries[$index]
        $entries.Add([pscustomobject][ordered]@{
            position = [int]$source.position
            algorithmId = [string]$source.algorithmId
            predecessorAlgorithmId = if ($index -eq 0) { 'NONE' } else { [string]$sourceEntries[$index - 1].algorithmId }
            runId = [string]$source.runId
            directory = 'runs/{0}' -f ([string]$source.directory).Split('/')[-1]
        })
    }
    [void](Assert-G13R2V2BoundFile -ProjectPath $ProjectPath -RelativePath $ScenarioRelativePath -ExpectedSha256 $ScenarioSourceSha256 -Label 'V2 block scenario')
    $blockId = '{0}-b{1:D3}' -f $CampaignId, $Block
    return [pscustomobject][ordered]@{
        schemaVersion = 2
        planId = $blockId + '-plan'
        designId = 'one-fresh-unity-process-per-williams-block-v2-native-telemetry'
        blockId = $blockId
        campaignId = $CampaignId
        scenarioRelativePath = $ScenarioRelativePath
        scenarioSourceSha256 = $ScenarioSourceSha256
        comparisonCohortId = $ComparisonCohortId
        block = $Block
        formalCampaign = $false
        analysisRole = if ($Warmup) { 'excluded-warmup' } else { 'measured-non-formal-pilot' }
        verificationInjectedFailurePosition = 0
        pilotPlanRelativePath = [string]$Provenance.pilotPlan.relativePath
        pilotPlanSha256 = [string]$Provenance.pilotPlan.sha256
        specificationRelativePath = [string]$PilotPlan.frozenInputs.specification.relativePath
        specificationSha256 = [string]$PilotPlan.frozenInputs.specification.sha256
        testDesignRelativePath = [string]$PilotPlan.frozenInputs.testDesign.relativePath
        testDesignSha256 = [string]$PilotPlan.frozenInputs.testDesign.sha256
        amendmentRelativePath = [string]$PilotPlan.frozenInputs.amendment.relativePath
        amendmentSha256 = [string]$PilotPlan.frozenInputs.amendment.sha256
        commandRelativePath = [string]$Provenance.processReuseBatchCommand.relativePath
        commandSha256 = [string]$Provenance.processReuseBatchCommand.sha256
        provenanceRelativePath = Get-G13R2V2ProjectRelativePath -ProjectPath $ProjectPath -FullPath $ProvenancePath
        provenanceSha256 = Get-G13R2V2LowerSha256 -Path $ProvenancePath
        telemetryProbeResultRelativePath = Get-G13R2V2ProjectRelativePath -ProjectPath $ProjectPath -FullPath $TelemetryProbeResultPath
        telemetryProbeResultSha256 = Get-G13R2V2LowerSha256 -Path $TelemetryProbeResultPath
        entries = $entries.ToArray()
    }
}

function Test-G13R2V2TelemetryComparison {
    param(
        [Parameter(Mandatory = $true)][long]$NativeBefore,
        [Parameter(Mandatory = $true)][long]$NativeAfter,
        [Parameter(Mandatory = $true)][long]$External
    )
    $lower = [math]::Min($NativeBefore, $NativeAfter)
    $upper = [math]::Max($NativeBefore, $NativeAfter)
    $distance = if ($External -lt $lower) { $lower - $External } elseif ($External -gt $upper) { $External - $upper } else { 0L }
    $maximum = [math]::Max($External, [math]::Max($NativeBefore, $NativeAfter))
    $tolerance = [long][math]::Max(67108864L, [math]::Ceiling(0.25 * $maximum))
    return [pscustomobject][ordered]@{
        nativeBefore = $NativeBefore
        nativeAfter = $NativeAfter
        external = $External
        distanceBytes = [long]$distance
        toleranceBytes = $tolerance
        passed = $NativeBefore -gt 0 -and $NativeAfter -gt 0 -and $External -gt 0 -and $distance -le $tolerance
    }
}

function Test-G13R2V2ManagedMemoryRule {
    param(
        [Parameter(Mandatory = $true)][long]$BeforeBytes,
        [Parameter(Mandatory = $true)][long]$RawAfterBytes,
        [Parameter(Mandatory = $true)][long]$AfterCleanupBytes
    )
    $growth = $AfterCleanupBytes - $BeforeBytes
    return [pscustomobject][ordered]@{
        beforeBytes = $BeforeBytes
        rawAfterBytes = $RawAfterBytes
        afterCleanupBytes = $AfterCleanupBytes
        rawGrowthBytes = $RawAfterBytes - $BeforeBytes
        retainedGrowthBytes = $growth
        maximumRetainedGrowthBytes = 134217728L
        rawGrowthIsDiagnosticOnly = $true
        passed = $BeforeBytes -gt 0 -and $RawAfterBytes -gt 0 -and $AfterCleanupBytes -gt 0 -and $growth -le 134217728L
    }
}

function Get-G13R2V2SampleSizeCandidate {
    param(
        [Parameter(Mandatory = $true)][double]$SigmaLog,
        [double]$Z = 1.96,
        [double]$RelativeHalfWidth = 0.10,
        [int]$MinimumBlocks = 30,
        [int]$CycleMultiple = 4,
        [int]$MaximumBlocks = 148
    )
    if ([double]::IsNaN($SigmaLog) -or [double]::IsInfinity($SigmaLog) -or $SigmaLog -lt 0) { throw 'SigmaLog must be finite and non-negative.' }
    if ($Z -le 0 -or $RelativeHalfWidth -le 0 -or $MinimumBlocks -lt 1 -or $CycleMultiple -lt 1 -or $MaximumBlocks -lt 1) { throw 'Sample-size constants must be positive.' }
    $raw = [long][math]::Ceiling([math]::Pow(($Z * $SigmaLog / [math]::Log(1.0 + $RelativeHalfWidth)), 2.0))
    $required = [long]($CycleMultiple * [math]::Ceiling(([math]::Max($MinimumBlocks, $raw)) / [double]$CycleMultiple))
    return [pscustomobject][ordered]@{
        sigmaLog = $SigmaLog
        z = $Z
        relativeHalfWidth = $RelativeHalfWidth
        nRaw = $raw
        requiredNFormal = $required
        candidateNFormal = [long][math]::Min($MaximumBlocks, $required)
        cycleMultiple = $CycleMultiple
        maximumIndependentBlocks = $MaximumBlocks
        overCap = $required -gt $MaximumBlocks
        precisionStatus = if ($required -gt $MaximumBlocks) { 'blocked-separate-versioned-decision-required' } else { 'within-cap' }
    }
}

Export-ModuleMember -Function @(
    'Get-G13R2V2LowerSha256',
    'Read-G13R2V2Json',
    'ConvertTo-G13R2V2JsonText',
    'Write-G13R2V2Utf8NoBomJson',
    'Write-G13R2V2AtomicUtf8NoBomJson',
    'Get-G13R2V2ProjectRelativePath',
    'Assert-G13R2V2BoundFile',
    'Get-G13R2V2AlgorithmSlug',
    'Get-G13R2V2CohortAlgorithms',
    'Get-G13R2V2WilliamsRow',
    'Test-G13R2V2BlockPlanObject',
    'Test-G13R2V2PilotPlan',
    'New-G13R2V2BlockPlan',
    'Test-G13R2V2TelemetryComparison',
    'Test-G13R2V2ManagedMemoryRule',
    'Get-G13R2V2SampleSizeCandidate'
)
