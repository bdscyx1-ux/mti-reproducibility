Set-StrictMode -Version 2.0

$script:Gate13Utf8 = New-Object System.Text.UTF8Encoding($false, $true)

function Get-Gate13LowerSha256 {
    param([Parameter(Mandatory = $true)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "File not found: $Path" }
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Get-Gate13StringSha256 {
    param([Parameter(Mandatory = $true)][AllowEmptyString()][string]$Value)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($Value)
        return ([System.BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-', '').ToLowerInvariant()
    } finally {
        $sha.Dispose()
    }
}

function Read-Gate13Json {
    param([Parameter(Mandatory = $true)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "JSON file not found: $Path" }
    return [System.IO.File]::ReadAllText($Path, $script:Gate13Utf8) | ConvertFrom-Json
}

function ConvertTo-Gate13JsonText {
    param([Parameter(Mandatory = $true)]$Value, [int]$Depth = 30)
    $json = $Value | ConvertTo-Json -Depth $Depth
    $json = $json.Replace("`r`n", "`n").Replace("`r", "`n")
    if (-not $json.EndsWith("`n", [System.StringComparison]::Ordinal)) { $json += "`n" }
    return $json
}

function Write-Gate13Utf8NoBomJson {
    param([Parameter(Mandatory = $true)][string]$Path, [Parameter(Mandatory = $true)]$Value, [int]$Depth = 30)
    $parent = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $parent -PathType Container)) { throw "Parent directory does not exist: $parent" }
    [System.IO.File]::WriteAllText($Path, (ConvertTo-Gate13JsonText -Value $Value -Depth $Depth), $script:Gate13Utf8)
}

function Write-Gate13AtomicUtf8NoBomJson {
    param([Parameter(Mandatory = $true)][string]$Path, [Parameter(Mandatory = $true)]$Value, [int]$Depth = 30)
    $parent = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $parent -PathType Container)) { throw "Atomic JSON parent directory does not exist: $parent" }
    $temporaryPath = Join-Path $parent ('.gate13-' + [guid]::NewGuid().ToString('N') + '.tmp')
    try {
        Write-Gate13Utf8NoBomJson -Path $temporaryPath -Value $Value -Depth $Depth
        Move-Item -LiteralPath $temporaryPath -Destination $Path -Force
    } finally {
        if (Test-Path -LiteralPath $temporaryPath -PathType Leaf) { Remove-Item -LiteralPath $temporaryPath -Force }
    }
}

function Get-Gate13ProjectRelativePath {
    param([Parameter(Mandatory = $true)][string]$ProjectPath, [Parameter(Mandatory = $true)][string]$FullPath)
    $projectRoot = [System.IO.Path]::GetFullPath($ProjectPath).TrimEnd('\', '/') + [System.IO.Path]::DirectorySeparatorChar
    $full = [System.IO.Path]::GetFullPath($FullPath)
    if (-not $full.StartsWith($projectRoot, [System.StringComparison]::OrdinalIgnoreCase)) { throw "Path is outside project root: $full" }
    return $full.Substring($projectRoot.Length).Replace('\', '/')
}

function Test-Gate13PathWithin {
    param([Parameter(Mandatory = $true)][string]$CandidatePath, [Parameter(Mandatory = $true)][string]$RootPath, [switch]$AllowRoot)
    $candidate = [System.IO.Path]::GetFullPath($CandidatePath).TrimEnd('\', '/')
    $root = [System.IO.Path]::GetFullPath($RootPath).TrimEnd('\', '/')
    if ($AllowRoot -and [string]::Equals($candidate, $root, [System.StringComparison]::OrdinalIgnoreCase)) { return $true }
    $rootPrefix = $root + [System.IO.Path]::DirectorySeparatorChar
    return $candidate.StartsWith($rootPrefix, [System.StringComparison]::OrdinalIgnoreCase)
}

function Get-Gate13AlgorithmSlug {
    param([Parameter(Mandatory = $true)][string]$AlgorithmId)
    switch ($AlgorithmId) {
        'A*-R' { return 'astar-r' }
        'D*L' { return 'dstar-l' }
        'C-FF' { return 'cff' }
        'IDFF' { return 'idff' }
        default { throw "Unsupported algorithm: $AlgorithmId" }
    }
}

function Get-Gate13CohortDefinition {
    param([Parameter(Mandatory = $true)][string]$ComparisonCohortId)
    switch ($ComparisonCohortId) {
        'four-algorithm-shared-goal-v1' {
            return [pscustomobject][ordered]@{ comparisonCohortId = $ComparisonCohortId; shortId = 's4'; algorithms = [string[]]@('A*-R', 'D*L', 'C-FF', 'IDFF'); blocks = 52 }
        }
        'per-agent-heterogeneous-goal-v1' {
            return [pscustomobject][ordered]@{ comparisonCohortId = $ComparisonCohortId; shortId = 'pa2'; algorithms = [string[]]@('A*-R', 'D*L'); blocks = 148 }
        }
        'grouped-field-heterogeneous-goal-v1' {
            return [pscustomobject][ordered]@{ comparisonCohortId = $ComparisonCohortId; shortId = 'gf2'; algorithms = [string[]]@('C-FF', 'IDFF'); blocks = 52 }
        }
        default { throw "Unsupported comparison cohort: $ComparisonCohortId" }
    }
}

function Get-Gate13WilliamsBaseIndices {
    param([Parameter(Mandatory = $true)][int]$Count)
    if ($Count -lt 2 -or $Count % 2 -ne 0) { throw 'Williams scheduling requires an even algorithm count of at least two.' }
    $indices = New-Object System.Collections.Generic.List[int]
    $indices.Add(0)
    for ($step = 1; $step -lt $Count; $step++) {
        if ($step % 2 -eq 1) { $indices.Add([int](($step + 1) / 2)) }
        else { $indices.Add([int]($Count - ($step / 2))) }
    }
    return $indices.ToArray()
}

function Get-Gate13WilliamsRow {
    param([Parameter(Mandatory = $true)][string[]]$Items, [Parameter(Mandatory = $true)][int]$RowIndex)
    if ($Items.Count -lt 2 -or $Items.Count % 2 -ne 0) { throw 'Williams rows require an even item count of at least two.' }
    $base = @(Get-Gate13WilliamsBaseIndices -Count $Items.Count)
    $row = New-Object System.Collections.Generic.List[string]
    foreach ($baseIndex in $base) { $row.Add($Items[($baseIndex + $RowIndex) % $Items.Count]) }
    return $row.ToArray()
}

function New-Gate13WilliamsSchedule {
    param(
        [Parameter(Mandatory = $true)][string]$CampaignId,
        [Parameter(Mandatory = $true)][string]$ComparisonCohortId,
        [Parameter(Mandatory = $true)][int]$Blocks
    )
    if ($CampaignId -notmatch '^[A-Za-z0-9][A-Za-z0-9_.-]{0,95}$') { throw 'CampaignId must be 1-96 file-safe ASCII characters beginning with an alphanumeric character.' }
    $cohort = Get-Gate13CohortDefinition -ComparisonCohortId $ComparisonCohortId
    $algorithms = [string[]]$cohort.algorithms
    $algorithmCount = $algorithms.Count
    if ($Blocks -lt 1 -or $Blocks -gt 148 -or $Blocks % $algorithmCount -ne 0) { throw "Blocks must be in 1..148 and a multiple of algorithm count $algorithmCount." }

    $entries = New-Object System.Collections.Generic.List[object]
    $canonical = New-Object System.Text.StringBuilder
    $cycleRows = New-Object System.Collections.Generic.List[object]
    for ($rowIndex = 0; $rowIndex -lt $algorithmCount; $rowIndex++) {
        $cycleRows.Add(@(Get-Gate13WilliamsRow -Items $algorithms -RowIndex $rowIndex))
    }
    for ($blockIndex = 0; $blockIndex -lt $Blocks; $blockIndex++) {
        $block = $blockIndex + 1
        $row = @(Get-Gate13WilliamsRow -Items $algorithms -RowIndex ($blockIndex % $algorithmCount))
        $blockName = 'b{0:D3}' -f $block
        for ($positionIndex = 0; $positionIndex -lt $algorithmCount; $positionIndex++) {
            $position = $positionIndex + 1
            $algorithm = $row[$positionIndex]
            $positionName = 'p{0:D2}-{1}' -f $position, (Get-Gate13AlgorithmSlug -AlgorithmId $algorithm)
            $runId = '{0}-{1}-{2}' -f $CampaignId, $blockName, $positionName
            $directory = 'runs/{0}/{1}' -f $blockName, $positionName
            $entry = [pscustomobject][ordered]@{
                block = $block
                position = $position
                algorithmId = $algorithm
                runId = $runId
                directory = $directory
            }
            $entries.Add($entry)
            [void]$canonical.Append($block).Append('|').Append($position).Append('|').Append($algorithm).Append('|').Append($runId).Append('|').Append($directory).Append("`n")
        }
    }

    $completeCycles = [int]($Blocks / $algorithmCount)
    $positionCounts = [ordered]@{}
    $predecessorCounts = [ordered]@{}
    foreach ($algorithm in $algorithms) {
        $positionCounts[$algorithm] = [ordered]@{}
        for ($position = 1; $position -le $algorithmCount; $position++) { $positionCounts[$algorithm]["p$position"] = 0 }
        foreach ($successor in $algorithms) {
            if ($successor -ne $algorithm) { $predecessorCounts["$algorithm>$successor"] = 0 }
        }
    }
    for ($block = 1; $block -le $Blocks; $block++) {
        $blockEntries = @($entries.ToArray() | Where-Object { $_.block -eq $block } | Sort-Object position)
        if ($blockEntries.Count -ne $algorithmCount -or @($blockEntries.algorithmId | Sort-Object -Unique).Count -ne $algorithmCount) { throw "Incomplete Williams block: $block" }
        for ($positionIndex = 0; $positionIndex -lt $algorithmCount; $positionIndex++) {
            $algorithm = $blockEntries[$positionIndex].algorithmId
            $positionCounts[$algorithm]["p$($positionIndex + 1)"]++
            if ($positionIndex -lt $algorithmCount - 1) { $predecessorCounts["$algorithm>$($blockEntries[$positionIndex + 1].algorithmId)"]++ }
        }
    }
    $positionBalanced = @($positionCounts.GetEnumerator() | ForEach-Object { $_.Value.Values } | Where-Object { $_ -ne $completeCycles }).Count -eq 0
    $predecessorBalanced = @($predecessorCounts.Values | Where-Object { $_ -ne $completeCycles }).Count -eq 0
    if (-not $positionBalanced -or -not $predecessorBalanced) { throw 'Williams balance validation failed.' }

    return [pscustomobject][ordered]@{
        comparisonCohortId = $ComparisonCohortId
        canonicalAlgorithmOrder = @($algorithms)
        blockCount = $Blocks
        algorithmCount = $algorithmCount
        sampleCount = $entries.Count
        completeBalanceCycleCount = $completeCycles
        williamsCycleRows = $cycleRows.ToArray()
        positionCounts = $positionCounts
        orderedPredecessorCounts = $predecessorCounts
        positionBalanced = $positionBalanced
        orderedPredecessorBalanced = $predecessorBalanced
        canonicalScheduleSha256 = Get-Gate13StringSha256 -Value $canonical.ToString()
        entries = $entries.ToArray()
    }
}

function Get-Gate13BundleVerification {
    param([Parameter(Mandatory = $true)][string]$ProjectPath, [Parameter(Mandatory = $true)]$Amendment)
    $bundleRoot = Join-Path $ProjectPath 'Research\FormalScenarios\v1'
    $manifestPath = Join-Path $bundleRoot 'bundle-manifest.json'
    $manifest = Read-Gate13Json -Path $manifestPath
    $errors = New-Object System.Collections.Generic.List[string]
    $builder = New-Object System.Text.StringBuilder
    foreach ($artifact in @($manifest.artifacts)) {
        $artifactPath = Join-Path $bundleRoot ([string]$artifact.relativePath).Replace('/', '\')
        if (-not (Test-Path -LiteralPath $artifactPath -PathType Leaf)) {
            $errors.Add("Missing Gate 11 artifact: $($artifact.relativePath)")
            continue
        }
        $hash = Get-Gate13LowerSha256 -Path $artifactPath
        $bytes = [int64](Get-Item -LiteralPath $artifactPath).Length
        if ($hash -ne [string]$artifact.sha256 -or $bytes -ne [int64]$artifact.byteCount) { $errors.Add("Gate 11 artifact mismatch: $($artifact.relativePath)") }
        [void]$builder.Append([string]$artifact.relativePath).Append("`n").Append([string]$artifact.sha256).Append("`n")
    }
    $aggregate = Get-Gate13StringSha256 -Value $builder.ToString()
    $fileCount = @(Get-ChildItem -LiteralPath $bundleRoot -File -Recurse).Count
    if ($fileCount -ne 57) { $errors.Add("Gate 11 bundle file count is $fileCount; expected 57.") }
    if ((Get-Gate13LowerSha256 -Path $manifestPath) -ne [string]$Amendment.frozenInputs.gate11BundleManifestSha256) { $errors.Add('Gate 11 bundle manifest hash mismatch.') }
    if ($aggregate -ne [string]$Amendment.frozenInputs.gate11OrderedBundleAggregateSha256 -or $aggregate -ne [string]$manifest.bundleAggregateSha256) { $errors.Add('Gate 11 ordered aggregate mismatch.') }
    return [pscustomobject][ordered]@{
        passed = $errors.Count -eq 0
        errors = $errors.ToArray()
        fileCount = $fileCount
        artifactCount = @($manifest.artifacts).Count
        manifestSha256 = Get-Gate13LowerSha256 -Path $manifestPath
        orderedAggregateSha256 = $aggregate
    }
}

function Assert-Gate13FileHash {
    param([string]$ProjectPath, [string]$RelativePath, [string]$ExpectedSha256, [string]$Label)
    $path = Join-Path $ProjectPath $RelativePath.Replace('/', '\')
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "$Label is missing: $path" }
    $actual = Get-Gate13LowerSha256 -Path $path
    if ($actual -ne $ExpectedSha256) { throw "$Label hash mismatch: expected $ExpectedSha256, actual $actual" }
    return $path
}

function New-Gate13FormalConfig {
    param(
        [Parameter(Mandatory = $true)][string]$ProjectPath,
        [string]$AmendmentPath
    )
    $ProjectPath = [System.IO.Path]::GetFullPath($ProjectPath)
    if ([string]::IsNullOrWhiteSpace($AmendmentPath)) { $AmendmentPath = Join-Path $ProjectPath 'Research\Gate13_Readiness_Amendment.v1.json' }
    elseif (-not [System.IO.Path]::IsPathRooted($AmendmentPath)) { $AmendmentPath = Join-Path $ProjectPath $AmendmentPath }
    $AmendmentPath = [System.IO.Path]::GetFullPath($AmendmentPath)
    $amendment = Read-Gate13Json -Path $AmendmentPath
    if ($amendment.schemaVersion -ne 1 -or $amendment.amendmentId -ne 'gate13-readiness-amendment-v1') { throw 'Unsupported Gate 13 amendment identity.' }
    if ([double]$amendment.userDecision.precisionRelativeHalfWidthTarget -ne 0.1 -or [int]$amendment.userDecision.maximumPerAlgorithmPerCell -ne 148) { throw 'Gate 13 precision/cap decision mismatch.' }
    if ($amendment.userDecision.gate13ExecutionAuthorized -ne $false -or $amendment.userDecision.formalCampaignStartAllowed -ne $false) { throw 'Frozen amendment unexpectedly authorizes formal execution.' }

    $bundleCheck = Get-Gate13BundleVerification -ProjectPath $ProjectPath -Amendment $amendment
    if (-not $bundleCheck.passed) { throw "Gate 11 retained bundle validation failed: $($bundleCheck.errors -join '; ')" }
    $matrixPath = Assert-Gate13FileHash -ProjectPath $ProjectPath -RelativePath $amendment.frozenInputs.gate11MatrixRelativePath -ExpectedSha256 $amendment.frozenInputs.gate11MatrixSha256 -Label 'Gate 11 matrix'
    [void](Assert-Gate13FileHash -ProjectPath $ProjectPath -RelativePath $amendment.frozenInputs.gate11PreregistrationRelativePath -ExpectedSha256 $amendment.frozenInputs.gate11PreregistrationSha256 -Label 'Gate 11 preregistration')
    [void](Assert-Gate13FileHash -ProjectPath $ProjectPath -RelativePath $amendment.frozenInputs.gate12CandidateSampleSizesRelativePath -ExpectedSha256 $amendment.frozenInputs.gate12CandidateSampleSizesSha256 -Label 'Gate 12 candidate sample sizes')
    [void](Assert-Gate13FileHash -ProjectPath $ProjectPath -RelativePath $amendment.frozenInputs.gate12BudgetFeasibilityRelativePath -ExpectedSha256 $amendment.frozenInputs.gate12BudgetFeasibilitySha256 -Label 'Gate 12 budget feasibility')
    [void](Assert-Gate13FileHash -ProjectPath $ProjectPath -RelativePath $amendment.frozenInputs.gate12FinalAuditRelativePath -ExpectedSha256 $amendment.frozenInputs.gate12FinalAuditSha256 -Label 'Gate 12 final audit')
    [void](Assert-Gate13FileHash -ProjectPath $ProjectPath -RelativePath $amendment.frozenInputs.gate10CampaignRunnerRelativePath -ExpectedSha256 $amendment.frozenInputs.gate10CampaignRunnerSha256 -Label 'Gate 10 campaign runner')

    $gate12PlanPath = Join-Path $ProjectPath 'Research\Gate12_Pilot_Plan.v1.json'
    $gate12Plan = Read-Gate13Json -Path $gate12PlanPath
    foreach ($entry in @(
        [ordered]@{ label = 'Gate 10 fairness specification'; path = $gate12Plan.frozenInputs.fairnessSpecificationRelativePath; hash = $gate12Plan.frozenInputs.fairnessSpecificationSha256 },
        [ordered]@{ label = 'Planning workload specification'; path = $gate12Plan.frozenInputs.workloadSpecificationRelativePath; hash = $gate12Plan.frozenInputs.workloadSpecificationSha256 },
        [ordered]@{ label = 'Planning workload runner'; path = $gate12Plan.frozenInputs.workloadRunnerRelativePath; hash = $gate12Plan.frozenInputs.workloadRunnerSha256 },
        [ordered]@{ label = 'Planning batch command'; path = $gate12Plan.frozenInputs.batchCommandRelativePath; hash = $gate12Plan.frozenInputs.batchCommandSha256 },
        [ordered]@{ label = 'Planning workload implementation'; path = $gate12Plan.frozenInputs.workloadImplementationRelativePath; hash = $gate12Plan.frozenInputs.workloadImplementationSha256 },
        [ordered]@{ label = 'Planning fairness contracts'; path = $gate12Plan.frozenInputs.fairnessContractsRelativePath; hash = $gate12Plan.frozenInputs.fairnessContractsSha256 }
    )) { [void](Assert-Gate13FileHash -ProjectPath $ProjectPath -RelativePath $entry.path -ExpectedSha256 $entry.hash -Label $entry.label) }
    $unityPath = [System.IO.Path]::GetFullPath(([string]$gate12Plan.unity.executablePath).Replace('/', '\'))
    if ((Get-Gate13LowerSha256 -Path $unityPath) -ne [string]$gate12Plan.unity.executableSha256) { throw 'Unity executable hash mismatch.' }

    $runtimeRelativePaths = [ordered]@{
        module = 'Research/Gate13FormalPreparation.psm1'
        configGenerator = 'Research/New-Gate13FormalCampaignConfig.ps1'
        scenarioCampaignRunner = 'Research/Run-Gate13FormalScenarioCampaign.ps1'
        formalOrchestrator = 'Research/Run-Gate13FormalCampaign.ps1'
    }
    $runtimeFiles = [ordered]@{}
    foreach ($entry in $runtimeRelativePaths.GetEnumerator()) {
        $path = Join-Path $ProjectPath $entry.Value.Replace('/', '\')
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Gate 13 runtime file is missing: $($entry.Value)" }
        $runtimeFiles[$entry.Key] = [ordered]@{ relativePath = $entry.Value; sha256 = Get-Gate13LowerSha256 -Path $path }
    }
    $preparationDocuments = [ordered]@{}
    foreach ($entry in ([ordered]@{
        specification = 'Research/Gate13_NonExecuting_Preparation_Specification.md'
        testDesign = 'Research/Gate13_NonExecuting_Preparation_Test_Design.md'
    }).GetEnumerator()) {
        $path = Join-Path $ProjectPath $entry.Value.Replace('/', '\')
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Gate 13 preparation document missing: $($entry.Value)" }
        $preparationDocuments[$entry.Key] = [ordered]@{ relativePath = $entry.Value; sha256 = Get-Gate13LowerSha256 -Path $path }
    }

    $matrix = Read-Gate13Json -Path $matrixPath
    if ([int]$matrix.scenarioCount -ne 53 -or @($matrix.scenarios).Count -ne 53 -or [int]$matrix.eligibilityCount -ne 212 -or @($matrix.eligibilityEntries).Count -ne 212) { throw 'Gate 11 matrix cardinality mismatch.' }
    $cohortOrder = [string[]]@('four-algorithm-shared-goal-v1', 'per-agent-heterogeneous-goal-v1', 'grouped-field-heterogeneous-goal-v1')
    $campaigns = New-Object System.Collections.Generic.List[object]
    $campaignOrdinal = 0
    foreach ($scenario in @($matrix.scenarios)) {
        foreach ($cohortId in $cohortOrder) {
            if (@($scenario.comparisonCohorts) -notcontains $cohortId) { continue }
            $campaignOrdinal++
            $cohort = Get-Gate13CohortDefinition -ComparisonCohortId $cohortId
            $campaignId = 'g13-c{0:D3}-{1}-{2}' -f $campaignOrdinal, ([string]$scenario.scenarioId), ([string]$cohort.shortId)
            if ($campaignId.Length -gt 96) { throw "Campaign ID is too long: $campaignId" }
            $schedule = New-Gate13WilliamsSchedule -CampaignId $campaignId -ComparisonCohortId $cohortId -Blocks ([int]$cohort.blocks)
            $eligibility = @($matrix.eligibilityEntries | Where-Object { $_.scenarioId -eq $scenario.scenarioId -and $_.comparisonCohortId -eq $cohortId })
            if ($eligibility.Count -ne $cohort.algorithms.Count) { throw "Eligibility count mismatch for $($scenario.scenarioId) / $cohortId" }
            foreach ($algorithm in $cohort.algorithms) {
                if (@($eligibility | Where-Object algorithmId -eq $algorithm).Count -ne 1) { throw "Missing/duplicate eligibility for $($scenario.scenarioId) / $cohortId / $algorithm" }
            }
            $scenarioRelativePath = 'Research/FormalScenarios/v1/' + ([string]$scenario.relativePath).Replace('\', '/')
            $scenarioPath = Join-Path $ProjectPath $scenarioRelativePath.Replace('/', '\')
            if ((Get-Gate13LowerSha256 -Path $scenarioPath) -ne [string]$scenario.sourceSha256) { throw "Scenario source hash mismatch: $scenarioRelativePath" }
            $campaigns.Add([pscustomobject][ordered]@{
                ordinal = $campaignOrdinal
                campaignId = $campaignId
                scenarioId = [string]$scenario.scenarioId
                scenarioRelativePath = $scenarioRelativePath
                scenarioSourceSha256 = [string]$scenario.sourceSha256
                scenarioCanonicalSha256 = [string]$scenario.canonicalSha256
                scenarioFingerprintSha256 = [string]$scenario.fingerprintSha256
                comparisonCohortId = $cohortId
                canonicalAlgorithmOrder = @($cohort.algorithms)
                blockCount = [int]$cohort.blocks
                algorithmCount = [int]$cohort.algorithms.Count
                sampleCount = [int]$schedule.sampleCount
                completeBalanceCycleCount = [int]$schedule.completeBalanceCycleCount
                williamsCycleRows = @($schedule.williamsCycleRows)
                canonicalScheduleSha256 = [string]$schedule.canonicalScheduleSha256
                outputRelativePath = ('campaigns/c{0:D3}-{1}-{2}' -f $campaignOrdinal, ([string]$scenario.scenarioId), ([string]$cohort.shortId))
            })
        }
    }
    if ($campaigns.Count -ne 74) { throw "Formal campaign count is $($campaigns.Count); expected 74." }

    $cohortSummaries = New-Object System.Collections.Generic.List[object]
    foreach ($cohortId in $cohortOrder) {
        $definition = Get-Gate13CohortDefinition -ComparisonCohortId $cohortId
        $items = @($campaigns.ToArray() | Where-Object comparisonCohortId -eq $cohortId)
        $cohortSummaries.Add([pscustomobject][ordered]@{
            comparisonCohortId = $cohortId
            scenarioCount = $items.Count
            algorithmCount = $definition.algorithms.Count
            blocksPerScenario = $definition.blocks
            completeWilliamsCyclesPerScenario = [int]($definition.blocks / $definition.algorithms.Count)
            expectedUnityProcessCount = [int](($items | Measure-Object -Property sampleCount -Sum).Sum)
        })
    }
    $expectedUnityProcessCount = [int](($campaigns.ToArray() | Measure-Object -Property sampleCount -Sum).Sum)
    if ($expectedUnityProcessCount -ne 15056) { throw "Formal sample total is $expectedUnityProcessCount; expected 15056." }

    $frozenInputs = [ordered]@{
        gate13Amendment = [ordered]@{ relativePath = Get-Gate13ProjectRelativePath -ProjectPath $ProjectPath -FullPath $AmendmentPath; sha256 = Get-Gate13LowerSha256 -Path $AmendmentPath }
        gate11BundleManifest = [ordered]@{ relativePath = $amendment.frozenInputs.gate11BundleManifestRelativePath; sha256 = $amendment.frozenInputs.gate11BundleManifestSha256; orderedAggregateSha256 = $amendment.frozenInputs.gate11OrderedBundleAggregateSha256 }
        gate11Matrix = [ordered]@{ relativePath = $amendment.frozenInputs.gate11MatrixRelativePath; sha256 = $amendment.frozenInputs.gate11MatrixSha256 }
        gate11Preregistration = [ordered]@{ relativePath = $amendment.frozenInputs.gate11PreregistrationRelativePath; sha256 = $amendment.frozenInputs.gate11PreregistrationSha256 }
        gate12Plan = [ordered]@{ relativePath = 'Research/Gate12_Pilot_Plan.v1.json'; sha256 = Get-Gate13LowerSha256 -Path $gate12PlanPath }
        gate12CandidateSampleSizes = [ordered]@{ relativePath = $amendment.frozenInputs.gate12CandidateSampleSizesRelativePath; sha256 = $amendment.frozenInputs.gate12CandidateSampleSizesSha256 }
        gate12BudgetFeasibility = [ordered]@{ relativePath = $amendment.frozenInputs.gate12BudgetFeasibilityRelativePath; sha256 = $amendment.frozenInputs.gate12BudgetFeasibilitySha256 }
        gate12FinalAudit = [ordered]@{ relativePath = $amendment.frozenInputs.gate12FinalAuditRelativePath; sha256 = $amendment.frozenInputs.gate12FinalAuditSha256 }
        gate12PilotManifest = [ordered]@{ relativePath = 'Research/PilotRuns/Gate12/v1/pilot-manifest.json'; sha256 = Get-Gate13LowerSha256 -Path (Join-Path $ProjectPath 'Research\PilotRuns\Gate12\v1\pilot-manifest.json') }
        gate10FairnessSpecification = [ordered]@{ relativePath = $gate12Plan.frozenInputs.fairnessSpecificationRelativePath; sha256 = $gate12Plan.frozenInputs.fairnessSpecificationSha256; historicalUsageRuleSupersededForGate13 = $true }
        gate10CampaignRunner = [ordered]@{ relativePath = $amendment.frozenInputs.gate10CampaignRunnerRelativePath; sha256 = $amendment.frozenInputs.gate10CampaignRunnerSha256; maximumBlocks = 100; modifiedForGate13 = $false }
        planningWorkloadSpecification = [ordered]@{ relativePath = $gate12Plan.frozenInputs.workloadSpecificationRelativePath; sha256 = $gate12Plan.frozenInputs.workloadSpecificationSha256 }
        planningWorkloadRunner = [ordered]@{ relativePath = $gate12Plan.frozenInputs.workloadRunnerRelativePath; sha256 = $gate12Plan.frozenInputs.workloadRunnerSha256 }
        planningBatchCommand = [ordered]@{ relativePath = $gate12Plan.frozenInputs.batchCommandRelativePath; sha256 = $gate12Plan.frozenInputs.batchCommandSha256 }
        planningWorkloadImplementation = [ordered]@{ relativePath = $gate12Plan.frozenInputs.workloadImplementationRelativePath; sha256 = $gate12Plan.frozenInputs.workloadImplementationSha256 }
        planningFairnessContracts = [ordered]@{ relativePath = $gate12Plan.frozenInputs.fairnessContractsRelativePath; sha256 = $gate12Plan.frozenInputs.fairnessContractsSha256 }
    }

    return [pscustomobject][ordered]@{
        schemaVersion = 1
        configId = 'gate13-formal-campaign-config-v1'
        configKind = 'nonexecuting-formal-orchestration-config-v1'
        materialPassport = [ordered]@{ originSkill = 'experiment-agent'; originMode = 'execute'; verificationStatus = 'PREPARED-NOT-EXECUTION-AUTHORIZED'; versionLabel = 'gate13_formal_campaign_config_v1' }
        authorizationBoundary = [ordered]@{
            nonExecutingPreparationAuthorized = $true
            authorizationSource = 'user-message-2026-10-06-gate13-nonexecuting-preparation'
            gate13ExecutionAuthorized = $false
            formalCampaignStartAllowed = $false
            configurationMayAuthorizeExecution = $false
            executionReceiptRequired = $true
        }
        frozenInputs = $frozenInputs
        preparationDocuments = $preparationDocuments
        runtimeFiles = $runtimeFiles
        unity = [ordered]@{
            executablePath = $unityPath.Replace('\', '/')
            productVersion = [string]$gate12Plan.unity.productVersion
            executableSha256 = [string]$gate12Plan.unity.executableSha256
        }
        output = [ordered]@{
            rootRelativePath = [string]$amendment.storage.plannedOutputRootRelativePath
            createNewOnly = $true
            overwriteAllowed = $false
            automaticResumeAllowed = $false
            automaticRetryAllowed = $false
        }
        launchPreflight = [ordered]@{
            mustRunAfterExecutionAuthorizationValidation = $true
            mustRunImmediatelyBeforeOutputRootCreation = $true
            comparisonUsesRawInt64Bytes = $true
            p95ProjectedOutputBytes = [int64]$amendment.budgetProjection.p95ProjectedOutputBytes
            minimumPostCampaignFreeBytes = [int64]$amendment.budgetProjection.minimumPostCampaignFreeBytes
            minimumLaunchFreeBytes = [int64]$amendment.storage.launchPreflight.minimumFreeBytes
            failureAction = 'stop-before-formal-root-and-samples'
        }
        environmentPreflight = [ordered]@{
            requiredActivePowerSchemeGuid = [string]$gate12Plan.preflight.requiredActivePowerSchemeGuid
            requiredActivePowerSchemeName = [string]$gate12Plan.preflight.requiredActivePowerSchemeName
            requireAcOnline = [bool]$gate12Plan.preflight.requireAcOnline
            minimumFreePhysicalMemoryBytes = [int64](4GB)
            cpuLoadSampleCount = [int]$gate12Plan.preflight.cpuLoadSampleCount
            cpuLoadSampleIntervalSeconds = [int]$gate12Plan.preflight.cpuLoadSampleIntervalSeconds
            maximumMeanCpuLoadPercent = [double]$gate12Plan.preflight.maximumMeanCpuLoadPercent
            requireNoUnityProcess = $true
            requireNoUnityLockfile = $true
            temperatureUnavailablePolicy = [string]$gate12Plan.preflight.temperatureUnavailablePolicy
        }
        monitoring = [ordered]@{
            checkIntervalSeconds = 30
            outputStallChecks = 3
            hardTimeoutSecondsPerCampaign = 10800
            outputStallAction = 'advisory-only'
            hardTimeoutMayTerminateOwnedProcessTree = $true
            automaticRetryAllowed = $false
        }
        checkpoint = [ordered]@{
            relativePath = 'formal-checkpoint.json'
            atomicSameDirectoryReplace = $true
            updateBeforeAndAfterEveryCampaign = $true
            authorizesAutomaticResume = $false
            authorizesAutomaticRetry = $false
        }
        scheduleDesign = [ordered]@{
            orderDesignId = 'williams-balanced-v1'
            scenarioOrder = 'gate11-matrix-original-order'
            cohortOrder = @($cohortOrder)
            completeWilliamsCyclesRequired = $true
            eachSampleUsesIndependentUnityProcess = $true
            maximumBlocksSupported = 148
        }
        totals = [ordered]@{
            scenarioCount = 53
            eligibilityCellCount = 212
            campaignCount = 74
            expectedUnityProcessCount = $expectedUnityProcessCount
            cohortSummaries = $cohortSummaries.ToArray()
            projectedP95WallHours = [double]$amendment.budgetProjection.p95WallHours
            maximumTechnicalWallClockHours = [double]$amendment.budgetProjection.maximumTechnicalWallClockHours
        }
        campaigns = $campaigns.ToArray()
    }
}

function Test-Gate13FormalConfig {
    param(
        [Parameter(Mandatory = $true)][string]$ProjectPath,
        [Parameter(Mandatory = $true)]$Config,
        [string]$ConfigPath
    )
    $errors = New-Object System.Collections.Generic.List[string]
    $expected = $null
    try { $expected = New-Gate13FormalConfig -ProjectPath $ProjectPath }
    catch { $errors.Add("Expected config could not be reconstructed: $($_.Exception.Message)") }
    if ($null -ne $expected) {
        $actualText = ConvertTo-Gate13JsonText -Value $Config -Depth 30
        $expectedText = ConvertTo-Gate13JsonText -Value $expected -Depth 30
        if (-not [string]::Equals($actualText, $expectedText, [System.StringComparison]::Ordinal)) { $errors.Add('Config content differs from the deterministic reconstruction.') }
        if (-not [string]::IsNullOrWhiteSpace($ConfigPath)) {
            if (-not (Test-Path -LiteralPath $ConfigPath -PathType Leaf)) { $errors.Add("Config file is missing: $ConfigPath") }
            else {
                $fileText = [System.IO.File]::ReadAllText($ConfigPath, $script:Gate13Utf8)
                if (-not [string]::Equals($fileText, $expectedText, [System.StringComparison]::Ordinal)) { $errors.Add('Config file bytes differ from canonical deterministic JSON.') }
            }
        }
    }
    return [pscustomobject][ordered]@{
        passed = $errors.Count -eq 0
        errors = $errors.ToArray()
        campaignCount = if ($null -eq $Config) { 0 } else { @($Config.campaigns).Count }
        expectedUnityProcessCount = if ($null -eq $Config) { 0 } else { [int]$Config.totals.expectedUnityProcessCount }
        deterministicConfigSha256 = if ($null -eq $expected) { $null } else { Get-Gate13StringSha256 -Value (ConvertTo-Gate13JsonText -Value $expected -Depth 30) }
    }
}

function Test-Gate13ExecutionAuthorization {
    param(
        [Parameter(Mandatory = $true)]$Authorization,
        [Parameter(Mandatory = $true)][string]$ExpectedConfigSha256,
        [Parameter(Mandatory = $true)][string]$ExpectedAmendmentSha256,
        [Parameter(Mandatory = $true)][string]$ExpectedOutputRootRelativePath
    )
    $errors = New-Object System.Collections.Generic.List[string]
    if ($null -eq $Authorization) { $errors.Add('Execution authorization is missing.') }
    else {
        $values = [ordered]@{}
        foreach ($name in @('schemaVersion', 'authorizationKind', 'authorizationId', 'gate13ExecutionAuthorized', 'formalCampaignStartAllowed', 'configSha256', 'amendmentSha256', 'outputRootRelativePath', 'userAuthorizationReference', 'authorizedAt')) {
            $property = $Authorization.PSObject.Properties[$name]
            $values[$name] = if ($null -eq $property) { $null } else { $property.Value }
        }
        if ($null -eq $values.schemaVersion -or [int]$values.schemaVersion -ne 1) { $errors.Add('Authorization schemaVersion must be 1.') }
        if ($values.authorizationKind -ne 'gate13-formal-execution-authorization-v1') { $errors.Add('Authorization kind mismatch.') }
        if ([string]::IsNullOrWhiteSpace([string]$values.authorizationId) -or [string]$values.authorizationId -notmatch '^[A-Za-z0-9][A-Za-z0-9_.-]{0,95}$') { $errors.Add('Authorization ID is missing or unsafe.') }
        if ($values.gate13ExecutionAuthorized -ne $true) { $errors.Add('gate13ExecutionAuthorized is not true.') }
        if ($values.formalCampaignStartAllowed -ne $true) { $errors.Add('formalCampaignStartAllowed is not true.') }
        if ([string]$values.configSha256 -ne $ExpectedConfigSha256) { $errors.Add('Authorization config SHA-256 mismatch.') }
        if ([string]$values.amendmentSha256 -ne $ExpectedAmendmentSha256) { $errors.Add('Authorization amendment SHA-256 mismatch.') }
        if ([string]$values.outputRootRelativePath -ne $ExpectedOutputRootRelativePath) { $errors.Add('Authorization output root mismatch.') }
        if ([string]::IsNullOrWhiteSpace([string]$values.userAuthorizationReference)) { $errors.Add('User authorization reference is missing.') }
        $parsedAt = [DateTimeOffset]::MinValue
        if (-not [DateTimeOffset]::TryParse([string]$values.authorizedAt, [ref]$parsedAt)) { $errors.Add('Authorization timestamp is invalid.') }
    }
    return [pscustomobject][ordered]@{ passed = $errors.Count -eq 0; errors = $errors.ToArray() }
}

function Test-Gate13RawByteStorage {
    param(
        [Parameter(Mandatory = $true)][string]$OutputRoot,
        [Parameter(Mandatory = $true)][int64]$MinimumFreeBytes,
        [object]$FreeBytesOverride = $null,
        [ValidateSet('validation-only-advisory', 'launch-after-authorization')][string]$Purpose = 'validation-only-advisory'
    )
    $errors = New-Object System.Collections.Generic.List[string]
    $freeBytes = [int64]0
    $driveRoot = $null
    try {
        if ($MinimumFreeBytes -lt 0) { throw 'MinimumFreeBytes cannot be negative.' }
        $fullOutputRoot = [System.IO.Path]::GetFullPath($OutputRoot)
        $driveRoot = [System.IO.Path]::GetPathRoot($fullOutputRoot)
        if ([string]::IsNullOrWhiteSpace($driveRoot)) { throw 'Output root has no drive root.' }
        if ($null -ne $FreeBytesOverride) {
            if ($FreeBytesOverride -is [double] -or $FreeBytesOverride -is [single] -or $FreeBytesOverride -is [decimal]) { throw 'FreeBytesOverride must be an integer type.' }
            $freeBytes = [int64]$FreeBytesOverride
        } else {
            $drive = New-Object System.IO.DriveInfo -ArgumentList @($driveRoot)
            if (-not $drive.IsReady) { throw "Output drive is not ready: $driveRoot" }
            $freeBytes = [int64]$drive.AvailableFreeSpace
        }
        if ($freeBytes -lt 0) { throw 'Free bytes cannot be negative.' }
    } catch {
        $errors.Add($_.Exception.Message)
    }
    $thresholdPassed = $errors.Count -eq 0 -and $freeBytes -ge $MinimumFreeBytes
    if ($errors.Count -eq 0 -and -not $thresholdPassed) { $errors.Add("Free bytes $freeBytes are below required minimum $MinimumFreeBytes.") }
    return [pscustomobject][ordered]@{
        purpose = $Purpose
        driveRoot = $driveRoot
        freeBytes = $freeBytes
        minimumFreeBytes = $MinimumFreeBytes
        marginBytes = [int64]($freeBytes - $MinimumFreeBytes)
        comparison = 'raw-int64-freeBytes-greater-than-or-equal-minimumFreeBytes'
        thresholdPassed = $thresholdPassed
        launchAuthorizationConferred = $false
        passed = $errors.Count -eq 0 -and $thresholdPassed
        errors = $errors.ToArray()
    }
}

function Get-Gate13Mean {
    param([double[]]$Values)
    if ($null -eq $Values -or $Values.Count -eq 0) { throw 'Cannot compute a mean of an empty sequence.' }
    return [double](($Values | Measure-Object -Average).Average)
}

function Get-Gate13EnvironmentPreflight {
    param(
        [Parameter(Mandatory = $true)][string]$ProjectPath,
        [Parameter(Mandatory = $true)]$Config,
        [ValidateSet('validation-only-advisory', 'launch-after-authorization')][string]$Purpose = 'validation-only-advisory',
        [object]$FreeBytesOverride = $null,
        [switch]$SkipCpuSampling
    )
    $ProjectPath = [System.IO.Path]::GetFullPath($ProjectPath)
    $outputRoot = Join-Path $ProjectPath ([string]$Config.output.rootRelativePath).Replace('/', '\')
    $failed = New-Object System.Collections.Generic.List[string]
    $loadSamples = @()
    $powerGuid = $null
    $powerRaw = $null
    $acLineStatus = $null
    $freeMemoryBytes = [int64]0
    $temperature = [ordered]@{ available = $false; celsius = @(); error = $null }
    try {
        if (-not ('Gate13NativePower' -as [type])) {
            Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
[StructLayout(LayoutKind.Sequential)]
public struct Gate13SystemPowerStatus { public byte ACLineStatus; public byte BatteryFlag; public byte BatteryLifePercent; public byte SystemStatusFlag; public int BatteryLifeTime; public int BatteryFullLifeTime; }
public static class Gate13NativePower { [DllImport("kernel32.dll")] public static extern bool GetSystemPowerStatus(ref Gate13SystemPowerStatus status); }
'@
        }
        $status = New-Object Gate13SystemPowerStatus
        if (-not [Gate13NativePower]::GetSystemPowerStatus([ref]$status)) { throw 'GetSystemPowerStatus failed.' }
        $acLineStatus = [int]$status.ACLineStatus
        $powerRaw = (& powercfg.exe /getactivescheme 2>&1 | Out-String).Trim()
        $match = [regex]::Match($powerRaw, '(?i)[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}')
        if (-not $match.Success) { throw "Could not parse active power scheme: $powerRaw" }
        $powerGuid = $match.Value.ToLowerInvariant()
    } catch { $failed.Add("power:$($_.Exception.Message)") }
    try {
        $operatingSystem = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
        $freeMemoryBytes = [int64]([double]$operatingSystem.FreePhysicalMemory * 1KB)
    } catch { $failed.Add("memory:$($_.Exception.Message)") }
    try {
        $count = if ($SkipCpuSampling) { 1 } else { [int]$Config.environmentPreflight.cpuLoadSampleCount }
        for ($index = 0; $index -lt $count; $index++) {
            $load = (Get-CimInstance Win32_Processor -ErrorAction Stop | Measure-Object -Property LoadPercentage -Average).Average
            if ($null -eq $load) { $load = 0.0 }
            $loadSamples += [double]$load
            if (-not $SkipCpuSampling -and $index -lt $count - 1) { Start-Sleep -Seconds ([int]$Config.environmentPreflight.cpuLoadSampleIntervalSeconds) }
        }
    } catch { $failed.Add("cpu:$($_.Exception.Message)") }
    try {
        $zones = @(Get-CimInstance -Namespace 'root/wmi' -ClassName 'MSAcpi_ThermalZoneTemperature' -ErrorAction Stop)
        $values = @($zones | Where-Object { $null -ne $_.CurrentTemperature -and [double]$_.CurrentTemperature -gt 0 } | ForEach-Object { [math]::Round(([double]$_.CurrentTemperature / 10.0) - 273.15, 3) })
        $temperature = [ordered]@{ available = $values.Count -gt 0; celsius = $values; error = $null }
    } catch { $temperature = [ordered]@{ available = $false; celsius = @(); error = $_.Exception.Message } }

    $meanCpu = if ($loadSamples.Count -gt 0) { Get-Gate13Mean -Values ([double[]]$loadSamples) } else { [double]::PositiveInfinity }
    $unityProcesses = @(Get-Process -Name Unity -ErrorAction SilentlyContinue)
    $lockPath = Join-Path $ProjectPath 'Temp\UnityLockfile'
    $lockPresent = Test-Path -LiteralPath $lockPath
    $formalRootPresent = Test-Path -LiteralPath $outputRoot
    $storage = Test-Gate13RawByteStorage -OutputRoot $outputRoot -MinimumFreeBytes ([int64]$Config.launchPreflight.minimumLaunchFreeBytes) -FreeBytesOverride $FreeBytesOverride -Purpose $Purpose
    if ($Config.environmentPreflight.requireAcOnline -and $acLineStatus -ne 1) { $failed.Add('ac-online') }
    if ($powerGuid -ne [string]$Config.environmentPreflight.requiredActivePowerSchemeGuid) { $failed.Add('power-scheme') }
    if ($freeMemoryBytes -lt [int64]$Config.environmentPreflight.minimumFreePhysicalMemoryBytes) { $failed.Add('free-memory') }
    if ($meanCpu -gt [double]$Config.environmentPreflight.maximumMeanCpuLoadPercent) { $failed.Add('mean-cpu-load') }
    if ($Config.environmentPreflight.requireNoUnityProcess -and $unityProcesses.Count -gt 0) { $failed.Add('unity-process') }
    if ($Config.environmentPreflight.requireNoUnityLockfile -and $lockPresent) { $failed.Add('unity-lockfile') }
    if ($formalRootPresent) { $failed.Add('formal-root-already-exists') }
    if (-not $storage.passed) { $failed.Add('raw-byte-storage') }

    return [pscustomobject][ordered]@{
        schemaVersion = 1
        phase = $Purpose
        capturedAt = (Get-Date).ToString('o')
        outputRoot = $outputRoot
        acLineStatus = $acLineStatus
        activePowerSchemeGuid = $powerGuid
        activePowerSchemeRaw = $powerRaw
        freePhysicalMemoryBytes = $freeMemoryBytes
        cpuLoadSamplesPercent = @($loadSamples)
        meanCpuLoadPercent = $meanCpu
        temperatureAvailable = $temperature.available
        temperatureCelsius = @($temperature.celsius)
        temperatureError = $temperature.error
        unityProcessIds = @($unityProcesses | ForEach-Object { $_.Id })
        unityLockfilePresent = $lockPresent
        formalOutputRootPresent = $formalRootPresent
        storage = $storage
        launchAuthorizationConferred = $false
        failedChecks = $failed.ToArray()
        passed = $failed.Count -eq 0
    }
}

function Get-Gate13MonitorDecision {
    param(
        [Parameter(Mandatory = $true)][double]$ElapsedSeconds,
        [Parameter(Mandatory = $true)][int]$NoGrowthChecks,
        [Parameter(Mandatory = $true)][double]$HardTimeoutSeconds,
        [Parameter(Mandatory = $true)][int]$OutputStallChecks
    )
    if ($ElapsedSeconds -ge $HardTimeoutSeconds) { return [pscustomobject][ordered]@{ action = 'hard-timeout'; mayTerminateOwnedProcessTree = $true; autoRetryAllowed = $false } }
    if ($NoGrowthChecks -ge $OutputStallChecks) { return [pscustomobject][ordered]@{ action = 'output-stall-advisory'; mayTerminateOwnedProcessTree = $false; autoRetryAllowed = $false } }
    return [pscustomobject][ordered]@{ action = 'continue'; mayTerminateOwnedProcessTree = $false; autoRetryAllowed = $false }
}

function Get-Gate13DirectoryByteCount {
    param([Parameter(Mandatory = $true)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Container)) { return [int64]0 }
    $measurement = Get-ChildItem -LiteralPath $Path -File -Recurse -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum
    if ($null -eq $measurement.Sum) { return [int64]0 }
    return [int64]$measurement.Sum
}

Export-ModuleMember -Function @(
    'Get-Gate13LowerSha256',
    'Get-Gate13StringSha256',
    'Read-Gate13Json',
    'ConvertTo-Gate13JsonText',
    'Write-Gate13Utf8NoBomJson',
    'Write-Gate13AtomicUtf8NoBomJson',
    'Get-Gate13ProjectRelativePath',
    'Test-Gate13PathWithin',
    'Get-Gate13AlgorithmSlug',
    'Get-Gate13CohortDefinition',
    'Get-Gate13WilliamsBaseIndices',
    'Get-Gate13WilliamsRow',
    'New-Gate13WilliamsSchedule',
    'Get-Gate13BundleVerification',
    'New-Gate13FormalConfig',
    'Test-Gate13FormalConfig',
    'Test-Gate13ExecutionAuthorization',
    'Test-Gate13RawByteStorage',
    'Get-Gate13EnvironmentPreflight',
    'Get-Gate13MonitorDecision',
    'Get-Gate13DirectoryByteCount'
)
