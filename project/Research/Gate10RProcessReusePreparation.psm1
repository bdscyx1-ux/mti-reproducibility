Set-StrictMode -Version Latest

$script:Gate10RUtf8 = New-Object System.Text.UTF8Encoding($false)
$script:Gate10RDesignId = 'gate10r-one-fresh-unity-process-per-williams-block-5pct-v1'

function Get-Gate10RLowerSha256 {
    param([Parameter(Mandatory = $true)][string]$Path)
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Get-Gate10RStringSha256 {
    param([Parameter(Mandatory = $true)][string]$Value)
    $bytes = $script:Gate10RUtf8.GetBytes($Value)
    try {
        $sha = [System.Security.Cryptography.SHA256]::Create()
        try { return ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-', '').ToLowerInvariant() }
        finally { $sha.Dispose() }
    } finally { }
}

function Read-Gate10RJson {
    param([Parameter(Mandatory = $true)][string]$Path)
    return Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
}

function ConvertTo-Gate10RJsonText {
    param([Parameter(Mandatory = $true)]$Value, [int]$Depth = 50)
    $text = $Value | ConvertTo-Json -Depth $Depth
    $text = $text.Replace("`r`n", "`n").Replace("`r", "`n")
    if (-not $text.EndsWith("`n")) { $text += "`n" }
    return $text
}

function Write-Gate10RUtf8NoBomJson {
    param([Parameter(Mandatory = $true)][string]$Path, [Parameter(Mandatory = $true)]$Value, [int]$Depth = 50)
    [System.IO.File]::WriteAllText($Path, (ConvertTo-Gate10RJsonText -Value $Value -Depth $Depth), $script:Gate10RUtf8)
}

function Write-Gate10RAtomicUtf8NoBomJson {
    param([Parameter(Mandatory = $true)][string]$Path, [Parameter(Mandatory = $true)]$Value, [int]$Depth = 50)
    $directory = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $directory -PathType Container)) { New-Item -ItemType Directory -Path $directory | Out-Null }
    $temporary = $Path + '.tmp-' + [Guid]::NewGuid().ToString('N')
    Write-Gate10RUtf8NoBomJson -Path $temporary -Value $Value -Depth $Depth
    Move-Item -LiteralPath $temporary -Destination $Path -Force
}

function Get-Gate10RProjectRelativePath {
    param([Parameter(Mandatory = $true)][string]$ProjectPath, [Parameter(Mandatory = $true)][string]$FullPath)
    $root = [System.IO.Path]::GetFullPath($ProjectPath).TrimEnd('\') + '\'
    $candidate = [System.IO.Path]::GetFullPath($FullPath)
    if (-not $candidate.StartsWith($root, [System.StringComparison]::OrdinalIgnoreCase)) { throw "Path escapes project root: $candidate" }
    return $candidate.Substring($root.Length).Replace('\', '/')
}

function Assert-Gate10RBoundFile {
    param(
        [Parameter(Mandatory = $true)][string]$ProjectPath,
        [Parameter(Mandatory = $true)][string]$RelativePath,
        [Parameter(Mandatory = $true)][string]$ExpectedSha256,
        [Parameter(Mandatory = $true)][string]$Label
    )
    $root = [System.IO.Path]::GetFullPath($ProjectPath).TrimEnd('\') + '\'
    $path = [System.IO.Path]::GetFullPath((Join-Path $ProjectPath $RelativePath.Replace('/', '\')))
    if (-not $path.StartsWith($root, [System.StringComparison]::OrdinalIgnoreCase)) { throw "$Label escapes project root." }
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "$Label is missing: $path" }
    $actual = Get-Gate10RLowerSha256 -Path $path
    if ($actual -ne $ExpectedSha256) { throw "$Label hash mismatch: expected $ExpectedSha256, actual $actual" }
    return $path
}

function Get-Gate10RAlgorithmSlug {
    param([Parameter(Mandatory = $true)][string]$AlgorithmId)
    switch ($AlgorithmId) {
        'A*-R' { return 'astar-r' }
        'D*L' { return 'dstar-l' }
        'C-FF' { return 'cff' }
        'IDFF' { return 'idff' }
        default { throw "Unsupported algorithm: $AlgorithmId" }
    }
}

function Get-Gate10RCohortAlgorithms {
    param([Parameter(Mandatory = $true)][string]$ComparisonCohortId)
    switch ($ComparisonCohortId) {
        'four-algorithm-shared-goal-v1' { return [string[]]@('A*-R', 'D*L', 'C-FF', 'IDFF') }
        'per-agent-heterogeneous-goal-v1' { return [string[]]@('A*-R', 'D*L') }
        'grouped-field-heterogeneous-goal-v1' { return [string[]]@('C-FF', 'IDFF') }
        default { throw "Unsupported cohort: $ComparisonCohortId" }
    }
}

function Get-Gate10RWilliamsRow {
    param(
        [Parameter(Mandatory = $true)][string[]]$Algorithms,
        [Parameter(Mandatory = $true)][ValidateRange(1, 1000000)][int]$Block
    )
    $count = $Algorithms.Count
    if ($count -notin @(2, 4)) { throw 'Only two- and four-algorithm Williams rows are authorized.' }
    $base = New-Object int[] $count
    $base[0] = 0
    for ($step = 1; $step -lt $count; $step++) {
        $base[$step] = if ($step % 2 -eq 1) { ($step + 1) / 2 } else { $count - ($step / 2) }
    }
    $rowIndex = ($Block - 1) % $count
    $row = New-Object string[] $count
    for ($index = 0; $index -lt $count; $index++) {
        $row[$index] = $Algorithms[($base[$index] + $rowIndex) % $count]
    }
    return $row
}

function Test-Gate10RBlockPlanObject {
    param([Parameter(Mandatory = $true)]$Plan)
    $errors = New-Object System.Collections.Generic.List[string]
    try {
        if ([int]$Plan.schemaVersion -ne 2 -or [string]$Plan.designId -ne $script:Gate10RDesignId -or $Plan.formalCampaign -ne $false) { throw 'Block-plan schema/design/formal boundary mismatch.' }
        if ([int]$Plan.block -lt 1) { throw 'Block ordinal must be positive.' }
        $entries = @($Plan.entries)
        if ([int]$Plan.verificationInjectedFailurePosition -lt 0 -or [int]$Plan.verificationInjectedFailurePosition -gt $entries.Count) { throw 'Injected failure position is outside the block.' }
        if ([int]$Plan.verificationInjectedFailurePosition -gt 0 -and [string]$Plan.analysisRole -ne 'excluded-negative-fail-closed-verification') { throw 'Injected failure is allowed only in the excluded negative fixture.' }
        foreach ($id in @([string]$Plan.planId, [string]$Plan.blockId, [string]$Plan.campaignId)) {
            if ($id -notmatch '^[A-Za-z0-9][A-Za-z0-9_.-]{0,127}$') { throw 'Unsafe plan/block/campaign identity.' }
        }
        $algorithms = @(Get-Gate10RCohortAlgorithms -ComparisonCohortId ([string]$Plan.comparisonCohortId))
        $expectedRow = @(Get-Gate10RWilliamsRow -Algorithms $algorithms -Block ([int]$Plan.block))
        if ($entries.Count -ne $algorithms.Count) { throw 'Block-plan entry count does not match cohort.' }
        $seenAlgorithms = New-Object System.Collections.Generic.HashSet[string]
        $seenRuns = New-Object System.Collections.Generic.HashSet[string]
        $seenDirectories = New-Object System.Collections.Generic.HashSet[string]
        for ($index = 0; $index -lt $entries.Count; $index++) {
            $entry = $entries[$index]
            $expectedPredecessor = if ($index -eq 0) { 'NONE' } else { [string]$entries[$index - 1].algorithmId }
            if ([int]$entry.position -ne $index + 1) { throw 'Positions must be contiguous and one-based.' }
            if ([string]$entry.algorithmId -ne [string]$expectedRow[$index]) { throw 'Order differs from the frozen Williams row.' }
            if ([string]$entry.predecessorAlgorithmId -ne $expectedPredecessor) { throw 'Predecessor identity mismatch.' }
            if (-not $seenAlgorithms.Add([string]$entry.algorithmId)) { throw 'Duplicate algorithm in one process.' }
            if ([string]$entry.runId -notmatch '^[A-Za-z0-9][A-Za-z0-9_.-]{0,127}$' -or -not $seenRuns.Add([string]$entry.runId)) { throw 'Unsafe or duplicate run ID.' }
            $directory = [string]$entry.directory
            if ([string]::IsNullOrWhiteSpace($directory) -or [System.IO.Path]::IsPathRooted($directory) -or $directory -match '(^|[\\/])\.\.([\\/]|$)' -or -not $seenDirectories.Add($directory)) { throw 'Unsafe or duplicate child directory.' }
        }
    } catch { $errors.Add($_.Exception.Message) }
    return [pscustomobject][ordered]@{ passed = $errors.Count -eq 0; errors = $errors.ToArray() }
}

function New-Gate10RBlockPlan {
    param(
        [Parameter(Mandatory = $true)][string]$ProjectPath,
        [Parameter(Mandatory = $true)]$Config,
        [Parameter(Mandatory = $true)]$Provenance,
        [Parameter(Mandatory = $true)][string]$CampaignId,
        [Parameter(Mandatory = $true)][string]$ScenarioRelativePath,
        [Parameter(Mandatory = $true)][string]$ScenarioSourceSha256,
        [Parameter(Mandatory = $true)][string]$ComparisonCohortId,
        [Parameter(Mandatory = $true)][ValidateRange(1, 1000000)][int]$Block,
        [Parameter(Mandatory = $true)][string]$ProvenancePath,
        [Parameter(Mandatory = $true)][string]$TelemetryProbeResultPath,
        [ValidateSet('excluded-verification','excluded-negative-fail-closed-verification','excluded-warmup','measured-non-formal-pilot')][string]$AnalysisRole = 'excluded-verification',
        [ValidateRange(0, 4)][int]$InjectedFailurePosition = 0
    )
    if ($CampaignId -notmatch '^[A-Za-z0-9][A-Za-z0-9_.-]{0,95}$') { throw 'Unsafe campaign ID.' }
    if ([string]$Config.designId -ne $script:Gate10RDesignId -or $Config.formalCampaign -ne $false) { throw 'Gate 10R config identity/boundary mismatch.' }
    $ProjectPath = [System.IO.Path]::GetFullPath($ProjectPath)
    $ProvenancePath = [System.IO.Path]::GetFullPath($ProvenancePath)
    $TelemetryProbeResultPath = [System.IO.Path]::GetFullPath($TelemetryProbeResultPath)
    $probe = Read-Gate10RJson -Path $TelemetryProbeResultPath
    if ($probe.passed -ne $true -or [string]$probe.executionDesignId -ne $script:Gate10RDesignId) { throw 'A successful Gate 10R telemetry probe is required.' }
    [void](Assert-Gate10RBoundFile -ProjectPath $ProjectPath -RelativePath $ScenarioRelativePath -ExpectedSha256 $ScenarioSourceSha256 -Label 'Gate 10R block scenario')
    $algorithms = @(Get-Gate10RCohortAlgorithms -ComparisonCohortId $ComparisonCohortId)
    $row = @(Get-Gate10RWilliamsRow -Algorithms $algorithms -Block $Block)
    $blockId = '{0}-b{1:D3}' -f $CampaignId, $Block
    $entries = New-Object System.Collections.Generic.List[object]
    for ($index = 0; $index -lt $row.Count; $index++) {
        $algorithm = [string]$row[$index]
        $slug = Get-Gate10RAlgorithmSlug -AlgorithmId $algorithm
        $entries.Add([pscustomobject][ordered]@{
            position = $index + 1
            algorithmId = $algorithm
            predecessorAlgorithmId = if ($index -eq 0) { 'NONE' } else { [string]$row[$index - 1] }
            runId = ('{0}-p{1:D2}-{2}' -f $blockId, ($index + 1), $slug)
            directory = ('runs/p{0:D2}-{1}' -f ($index + 1), $slug)
        })
    }
    $plan = [pscustomobject][ordered]@{
        schemaVersion = 2
        planId = $blockId + '-plan'
        designId = $script:Gate10RDesignId
        blockId = $blockId
        campaignId = $CampaignId
        scenarioRelativePath = $ScenarioRelativePath
        scenarioSourceSha256 = $ScenarioSourceSha256
        comparisonCohortId = $ComparisonCohortId
        block = $Block
        formalCampaign = $false
        analysisRole = $AnalysisRole
        verificationInjectedFailurePosition = $InjectedFailurePosition
        pilotPlanRelativePath = [string]$Provenance.config.relativePath
        pilotPlanSha256 = [string]$Provenance.config.sha256
        specificationRelativePath = [string]$Provenance.specification.relativePath
        specificationSha256 = [string]$Provenance.specification.sha256
        testDesignRelativePath = [string]$Provenance.testDesign.relativePath
        testDesignSha256 = [string]$Provenance.testDesign.sha256
        amendmentRelativePath = [string]$Provenance.executionAuthorization.relativePath
        amendmentSha256 = [string]$Provenance.executionAuthorization.sha256
        commandRelativePath = [string]$Provenance.unityCommand.relativePath
        commandSha256 = [string]$Provenance.unityCommand.sha256
        provenanceRelativePath = Get-Gate10RProjectRelativePath -ProjectPath $ProjectPath -FullPath $ProvenancePath
        provenanceSha256 = Get-Gate10RLowerSha256 -Path $ProvenancePath
        telemetryProbeResultRelativePath = Get-Gate10RProjectRelativePath -ProjectPath $ProjectPath -FullPath $TelemetryProbeResultPath
        telemetryProbeResultSha256 = Get-Gate10RLowerSha256 -Path $TelemetryProbeResultPath
        entries = $entries.ToArray()
    }
    $check = Test-Gate10RBlockPlanObject -Plan $plan
    if (-not $check.passed) { throw "Generated block plan failed validation: $($check.errors -join '; ')" }
    return $plan
}

function Test-Gate10RTelemetryComparison {
    param([long]$NativeBefore, [long]$NativeAfter, [long]$External)
    $lower = [math]::Min($NativeBefore, $NativeAfter)
    $upper = [math]::Max($NativeBefore, $NativeAfter)
    $distance = if ($External -lt $lower) { $lower - $External } elseif ($External -gt $upper) { $External - $upper } else { 0L }
    $maximum = [math]::Max($External, [math]::Max($NativeBefore, $NativeAfter))
    $tolerance = [long][math]::Max(67108864L, [math]::Ceiling(0.25 * $maximum))
    [pscustomobject][ordered]@{ nativeBefore=$NativeBefore;nativeAfter=$NativeAfter;external=$External;distanceBytes=[long]$distance;toleranceBytes=$tolerance;passed=$NativeBefore -gt 0 -and $NativeAfter -gt 0 -and $External -gt 0 -and $distance -le $tolerance }
}

function Test-Gate10RManagedMemoryRule {
    param([long]$BeforeBytes,[long]$RawAfterBytes,[long]$AfterCleanupBytes)
    $growth = $AfterCleanupBytes - $BeforeBytes
    [pscustomobject][ordered]@{beforeBytes=$BeforeBytes;rawAfterBytes=$RawAfterBytes;afterCleanupBytes=$AfterCleanupBytes;rawGrowthBytes=$RawAfterBytes-$BeforeBytes;retainedGrowthBytes=$growth;maximumRetainedGrowthBytes=134217728L;rawGrowthIsDiagnosticOnly=$true;passed=$BeforeBytes -gt 0 -and $RawAfterBytes -gt 0 -and $AfterCleanupBytes -gt 0 -and $growth -le 134217728L}
}

function Test-Gate10RNativeGrowthRule {
    param([long]$BeforeBytes,[long]$AfterCleanupBytes)
    $growth=$AfterCleanupBytes-$BeforeBytes
    [pscustomobject][ordered]@{beforeBytes=$BeforeBytes;afterCleanupBytes=$AfterCleanupBytes;growthBytes=$growth;maximumGrowthBytes=536870912L;passed=$BeforeBytes -gt 0 -and $AfterCleanupBytes -gt 0 -and $growth -le 536870912L}
}

function Get-Gate10RStructuralProjection {
    param([Parameter(Mandatory = $true)]$Result)
    $phases = New-Object System.Collections.Generic.List[object]
    foreach ($phase in @($Result.dynamicPhases)) {
        $phases.Add([pscustomobject][ordered]@{
            simulationTick=[long]$phase.simulationTick;eventIds=@($phase.eventIds|%{[string]$_});finalGridVersion=[long]$phase.finalGridVersion
            repairOperationCount=[int]$phase.repairOperationCount;planOperationCount=[int]$phase.planOperationCount;succeededPlanCount=[int]$phase.succeededPlanCount
            noPathPlanCount=[int]$phase.noPathPlanCount;budgetExceededOperationCount=[int]$phase.budgetExceededOperationCount
            processedNodesOrCells=[long]$phase.processedNodesOrCells;expandedNodes=[long]$phase.expandedNodes;relaxedEdges=[long]$phase.relaxedEdges;repairedCells=[long]$phase.repairedCells
        })
    }
    [pscustomobject][ordered]@{
        scenarioId=[string]$Result.scenarioId;scenarioFingerprintSha256=[string]$Result.scenarioFingerprintSha256;algorithmId=[string]$Result.algorithmId
        agentCount=[int]$Result.agentCount;scheduledEventCount=[int]$Result.scheduledEventCount;dynamicPlanningPhaseCount=[int]$Result.dynamicPlanningPhaseCount
        planOperationCount=[int]$Result.planOperationCount;repairOperationCount=[int]$Result.repairOperationCount;succeededPlanCount=[int]$Result.succeededPlanCount
        noPathPlanCount=[int]$Result.noPathPlanCount;budgetExceededPlanCount=[int]$Result.budgetExceededPlanCount;invalidPlanCount=[int]$Result.invalidPlanCount
        failedPlanCount=[int]$Result.failedPlanCount;budgetExceededOperationCount=[int]$Result.budgetExceededOperationCount;processedNodesOrCells=[long]$Result.processedNodesOrCells
        expandedNodes=[long]$Result.expandedNodes;relaxedEdges=[long]$Result.relaxedEdges;repairedCells=[long]$Result.repairedCells;finalGridVersion=[long]$Result.finalGridVersion
        usesFixedScenarioStarts=[bool]$Result.usesFixedScenarioStarts;fairnessSchemaVersion=[int]$Result.fairnessSchemaVersion;fairnessProtocolId=[string]$Result.fairnessProtocolId
        fairnessProtocolSha256=[string]$Result.fairnessProtocolSha256;algorithmSpecificationId=[string]$Result.algorithmSpecificationId
        algorithmSpecificationSha256=[string]$Result.algorithmSpecificationSha256;algorithmImplementationSha256=[string]$Result.algorithmImplementationSha256
        workloadSpecificationId=[string]$Result.workloadSpecificationId;workloadSpecificationSha256=[string]$Result.workloadSpecificationSha256
        goalCohortId=[string]$Result.goalCohortId;comparisonCohortId=[string]$Result.comparisonCohortId;distinctGoalCount=[int]$Result.distinctGoalCount
        plannerInstanceCount=[int]$Result.plannerInstanceCount;persistentStateInstanceCount=[int]$Result.persistentStateInstanceCount;sharedFieldInstanceCount=[int]$Result.sharedFieldInstanceCount
        plannerStateModelId=[string]$Result.plannerStateModelId;processedWorkUnit=[string]$Result.processedWorkUnit;nativeMetricsSemanticsId=[string]$Result.nativeMetricsSemanticsId
        dynamicCostIncludesAllRepairsAndPostEventPlans=[bool]$Result.dynamicCostIncludesAllRepairsAndPostEventPlans
        initializationProcessedNodesOrCells=[long]$Result.initializationProcessedNodesOrCells;initialPlanningProcessedNodesOrCells=[long]$Result.initialPlanningProcessedNodesOrCells
        dynamicProcessedNodesOrCells=[long]$Result.dynamicProcessedNodesOrCells;completed=[bool]$Result.completed;dynamicPhases=$phases.ToArray()
    }
}

function Compare-Gate10RStructuralResults {
    param([Parameter(Mandatory = $true)]$Reference,[Parameter(Mandatory = $true)]$Candidate)
    $referenceText=ConvertTo-Gate10RJsonText -Value (Get-Gate10RStructuralProjection -Result $Reference) -Depth 20
    $candidateText=ConvertTo-Gate10RJsonText -Value (Get-Gate10RStructuralProjection -Result $Candidate) -Depth 20
    [pscustomobject][ordered]@{passed=[string]::Equals($referenceText,$candidateText,[System.StringComparison]::Ordinal);referenceProjectionSha256=Get-Gate10RStringSha256 -Value $referenceText;candidateProjectionSha256=Get-Gate10RStringSha256 -Value $candidateText}
}

function Get-Gate10RSampleSizeCandidate {
    param([Parameter(Mandatory = $true)][double]$SigmaUpper,[double]$Z=1.96,[double]$RelativeHalfWidth=0.05,[int]$MinimumBlocks=32,[int]$CycleMultiple=4)
    if ([double]::IsNaN($SigmaUpper)-or[double]::IsInfinity($SigmaUpper)-or$SigmaUpper-lt 0){throw 'SigmaUpper must be finite and non-negative.'}
    if($Z-le 0-or$RelativeHalfWidth-le 0-or$MinimumBlocks-lt 1-or$CycleMultiple-lt 1){throw 'Sample-size constants must be positive.'}
    $raw=[long][math]::Ceiling([math]::Pow(($Z*$SigmaUpper/[math]::Log(1.0+$RelativeHalfWidth)),2.0))
    $required=[long]($CycleMultiple*[math]::Ceiling(([math]::Max($MinimumBlocks,$raw))/[double]$CycleMultiple))
    [pscustomobject][ordered]@{sigmaUpper=$SigmaUpper;z=$Z;relativeHalfWidth=$RelativeHalfWidth;nRaw=$raw;requiredNFormal=$required;candidateNFormal=$required;cycleMultiple=$CycleMultiple;minimumIndependentBlocks=$MinimumBlocks;hardCap=$null;overCap=$false}
}

Export-ModuleMember -Function @(
    'Get-Gate10RLowerSha256','Get-Gate10RStringSha256','Read-Gate10RJson','ConvertTo-Gate10RJsonText','Write-Gate10RUtf8NoBomJson','Write-Gate10RAtomicUtf8NoBomJson',
    'Get-Gate10RProjectRelativePath','Assert-Gate10RBoundFile','Get-Gate10RAlgorithmSlug','Get-Gate10RCohortAlgorithms','Get-Gate10RWilliamsRow',
    'Test-Gate10RBlockPlanObject','New-Gate10RBlockPlan','Test-Gate10RTelemetryComparison','Test-Gate10RManagedMemoryRule','Test-Gate10RNativeGrowthRule',
    'Get-Gate10RStructuralProjection','Compare-Gate10RStructuralResults','Get-Gate10RSampleSizeCandidate'
)
