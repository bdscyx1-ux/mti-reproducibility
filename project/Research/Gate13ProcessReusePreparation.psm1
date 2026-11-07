Set-StrictMode -Version Latest
$script:G13R2Utf8 = New-Object System.Text.UTF8Encoding($false)
$script:G13R2ProjectRoot = [System.IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$script:G13R2LegacyModulePath = Join-Path $PSScriptRoot 'Gate13FormalPreparation.psm1'
Import-Module $script:G13R2LegacyModulePath -Force

function Get-G13R2LowerSha256 {
    param([Parameter(Mandatory = $true)][string]$Path)
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Read-G13R2Json {
    param([Parameter(Mandatory = $true)][string]$Path)
    return Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
}

function ConvertTo-G13R2JsonText {
    param([Parameter(Mandatory = $true)]$Value, [int]$Depth = 40)
    $text = $Value | ConvertTo-Json -Depth $Depth
    $text = $text.Replace("`r`n", "`n").Replace("`r", "`n")
    if (-not $text.EndsWith("`n")) { $text += "`n" }
    return $text
}

function Write-G13R2Utf8NoBomJson {
    param([Parameter(Mandatory = $true)][string]$Path, [Parameter(Mandatory = $true)]$Value, [int]$Depth = 40)
    [System.IO.File]::WriteAllText($Path, (ConvertTo-G13R2JsonText -Value $Value -Depth $Depth), $script:G13R2Utf8)
}

function Write-G13R2AtomicUtf8NoBomJson {
    param([Parameter(Mandatory = $true)][string]$Path, [Parameter(Mandatory = $true)]$Value, [int]$Depth = 40)
    $directory = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $directory -PathType Container)) { New-Item -ItemType Directory -Path $directory | Out-Null }
    $temporary = $Path + '.tmp-' + [Guid]::NewGuid().ToString('N')
    Write-G13R2Utf8NoBomJson -Path $temporary -Value $Value -Depth $Depth
    Move-Item -LiteralPath $temporary -Destination $Path -Force
}

function Get-G13R2ProjectRelativePath {
    param([Parameter(Mandatory = $true)][string]$ProjectPath, [Parameter(Mandatory = $true)][string]$FullPath)
    $root = [System.IO.Path]::GetFullPath($ProjectPath).TrimEnd('\') + '\'
    $candidate = [System.IO.Path]::GetFullPath($FullPath)
    if (-not $candidate.StartsWith($root, [System.StringComparison]::OrdinalIgnoreCase)) { throw "Path escapes the project: $candidate" }
    return $candidate.Substring($root.Length).Replace('\', '/')
}

function Assert-G13R2BoundFile {
    param(
        [Parameter(Mandatory = $true)][string]$ProjectPath,
        [Parameter(Mandatory = $true)][string]$RelativePath,
        [Parameter(Mandatory = $true)][string]$ExpectedSha256,
        [Parameter(Mandatory = $true)][string]$Label
    )
    $path = [System.IO.Path]::GetFullPath((Join-Path $ProjectPath $RelativePath.Replace('/', '\')))
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "$Label is missing: $path" }
    $actual = Get-G13R2LowerSha256 -Path $path
    if ($actual -ne $ExpectedSha256) { throw "$Label hash mismatch: expected $ExpectedSha256, actual $actual" }
    return $path
}

function Get-G13R2AlgorithmSlug {
    param([Parameter(Mandatory = $true)][string]$AlgorithmId)
    switch ($AlgorithmId) {
        'A*-R' { return 'astar-r' }
        'D*L' { return 'dstar-l' }
        'C-FF' { return 'cff' }
        'IDFF' { return 'idff' }
        default { throw "Unsupported algorithm: $AlgorithmId" }
    }
}

function Get-G13R2CohortAlgorithms {
    param([Parameter(Mandatory = $true)][string]$ComparisonCohortId)
    switch ($ComparisonCohortId) {
        'four-algorithm-shared-goal-v1' { return [string[]]@('A*-R', 'D*L', 'C-FF', 'IDFF') }
        'per-agent-heterogeneous-goal-v1' { return [string[]]@('A*-R', 'D*L') }
        'grouped-field-heterogeneous-goal-v1' { return [string[]]@('C-FF', 'IDFF') }
        default { throw "Unsupported cohort: $ComparisonCohortId" }
    }
}

function Test-G13R2PilotPlan {
    param(
        [Parameter(Mandatory = $true)][string]$ProjectPath,
        [Parameter(Mandatory = $true)]$Plan,
        [string]$PlanPath
    )
    $errors = New-Object System.Collections.Generic.List[string]
    try {
        if ([int]$Plan.schemaVersion -ne 1 -or [string]$Plan.planId -ne 'gate13-r2-process-reuse-pilot-plan-v1') { throw 'Pilot plan identity mismatch.' }
        if ($Plan.authorizationBoundary.formalCampaignAuthorized -ne $false -or $Plan.authorizationBoundary.formalOutputRootCreationAllowed -ne $false) { throw 'Pilot plan unexpectedly authorizes formal execution/root creation.' }
        if ($Plan.processReusePolicy.designId -ne 'one-fresh-unity-process-per-williams-block-v1') { throw 'Process-reuse design mismatch.' }
        if ($Plan.processReusePolicy.oneBlockPerUnityProcess -ne $true -or $Plan.processReusePolicy.oneSamplePerAlgorithmPerProcess -ne $true -or $Plan.processReusePolicy.longLivedCampaignProcessAllowed -ne $false) { throw 'Process ownership policy mismatch.' }
        foreach ($property in $Plan.frozenInputs.PSObject.Properties) {
            [void](Assert-G13R2BoundFile -ProjectPath $ProjectPath -RelativePath ([string]$property.Value.relativePath) -ExpectedSha256 ([string]$property.Value.sha256) -Label ("Pilot frozen input " + $property.Name))
        }
        if (@($Plan.measuredCampaigns).Count -ne 3) { throw 'Pilot must contain exactly three measured campaign identities.' }
        $processes = [int](($Plan.measuredCampaigns | Measure-Object -Property expectedBlockProcessCount -Sum).Sum)
        $samples = [int](($Plan.measuredCampaigns | Measure-Object -Property expectedSampleCount -Sum).Sum)
        if ($processes -ne 36 -or $samples -ne 96 -or [int]$Plan.totals.totalUnityProcessCount -ne 45 -or [int]$Plan.totals.totalSampleCount -ne 108) { throw 'Pilot cardinality mismatch.' }
        foreach ($campaign in @($Plan.measuredCampaigns)) {
            $algorithms = @(Get-G13R2CohortAlgorithms -ComparisonCohortId ([string]$campaign.comparisonCohortId))
            if ([int]$campaign.blocks -ne 12 -or [int]$campaign.expectedBlockProcessCount -ne 12 -or [int]$campaign.expectedSampleCount -ne 12 * $algorithms.Count) { throw "Measured campaign cardinality mismatch: $($campaign.campaignId)" }
            if (@($campaign.algorithms).Count -ne $algorithms.Count -or (@($campaign.algorithms) -join '|') -ne ($algorithms -join '|')) { throw "Measured campaign cohort mismatch: $($campaign.campaignId)" }
            [void](Assert-G13R2BoundFile -ProjectPath $ProjectPath -RelativePath ([string]$campaign.scenarioRelativePath) -ExpectedSha256 ([string]$campaign.scenarioSourceSha256) -Label ("Pilot scenario " + $campaign.scenarioId))
        }
        $formalRoot = [System.IO.Path]::GetFullPath((Join-Path $ProjectPath ([string]$Plan.paths.reservedFormalRootRelativePath).Replace('/', '\')))
        if (Test-Path -LiteralPath $formalRoot) { throw "Reserved process-reuse formal root already exists: $formalRoot" }
        if (-not [string]::IsNullOrWhiteSpace($PlanPath) -and -not (Test-Path -LiteralPath $PlanPath -PathType Leaf)) { throw 'Pilot plan file is missing.' }
    } catch { $errors.Add($_.Exception.Message) }
    return [pscustomobject][ordered]@{ passed = $errors.Count -eq 0; errors = $errors.ToArray(); measuredBlockProcessCount = 36; measuredSampleCount = 96; formalExecutionAuthorized = $false }
}

function New-G13R2BlockPlan {
    param(
        [Parameter(Mandatory = $true)][string]$ProjectPath,
        [Parameter(Mandatory = $true)]$PilotPlan,
        [Parameter(Mandatory = $true)]$Provenance,
        [Parameter(Mandatory = $true)][string]$CampaignId,
        [Parameter(Mandatory = $true)][string]$ScenarioRelativePath,
        [Parameter(Mandatory = $true)][string]$ScenarioSourceSha256,
        [Parameter(Mandatory = $true)][string]$ComparisonCohortId,
        [Parameter(Mandatory = $true)][ValidateRange(1, 148)][int]$Block,
        [string]$ProvenancePath,
        [switch]$Warmup
    )
    if ($CampaignId -notmatch '^[A-Za-z0-9][A-Za-z0-9_.-]{0,95}$') { throw 'Unsafe campaign ID.' }
    if ([string]::IsNullOrWhiteSpace($ProvenancePath)) { $ProvenancePath = Join-Path $ProjectPath 'Research\Gate13_ProcessReuse_Provenance.v4.json' }
    $ProvenancePath = [System.IO.Path]::GetFullPath($ProvenancePath)
    $algorithms = @(Get-G13R2CohortAlgorithms -ComparisonCohortId $ComparisonCohortId)
    if ($Block % $algorithms.Count -eq 0) { $scheduleBlocks = $Block } else { $scheduleBlocks = $Block + ($algorithms.Count - ($Block % $algorithms.Count)) }
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
    $scenarioPath = Assert-G13R2BoundFile -ProjectPath $ProjectPath -RelativePath $ScenarioRelativePath -ExpectedSha256 $ScenarioSourceSha256 -Label 'Block scenario'
    [void]$scenarioPath
    $blockId = '{0}-b{1:D3}' -f $CampaignId, $Block
    return [pscustomobject][ordered]@{
        schemaVersion = 1
        planId = $blockId + '-plan'
        designId = 'one-fresh-unity-process-per-williams-block-v1'
        blockId = $blockId
        campaignId = $CampaignId
        scenarioRelativePath = $ScenarioRelativePath
        scenarioSourceSha256 = $ScenarioSourceSha256
        comparisonCohortId = $ComparisonCohortId
        block = $Block
        formalCampaign = $false
        analysisRole = if ($Warmup) { 'excluded-warmup' } else { 'measured-non-formal-pilot' }
        pilotPlanRelativePath = [string]$Provenance.pilotPlan.relativePath
        pilotPlanSha256 = [string]$Provenance.pilotPlan.sha256
        specificationRelativePath = [string]$PilotPlan.frozenInputs.specification.relativePath
        specificationSha256 = [string]$PilotPlan.frozenInputs.specification.sha256
        testDesignRelativePath = [string]$PilotPlan.frozenInputs.testDesign.relativePath
        testDesignSha256 = [string]$PilotPlan.frozenInputs.testDesign.sha256
        commandRelativePath = [string]$Provenance.processReuseBatchCommand.relativePath
        commandSha256 = [string]$Provenance.processReuseBatchCommand.sha256
        provenanceRelativePath = Get-G13R2ProjectRelativePath -ProjectPath $ProjectPath -FullPath $ProvenancePath
        provenanceSha256 = Get-G13R2LowerSha256 -Path $ProvenancePath
        entries = $entries.ToArray()
    }
}

function Get-G13R2StructuralProjection {
    param([Parameter(Mandatory = $true)]$Result)
    $phases = New-Object System.Collections.Generic.List[object]
    foreach ($phase in @($Result.dynamicPhases)) {
        $phases.Add([pscustomobject][ordered]@{
            simulationTick = [long]$phase.simulationTick
            eventIds = @($phase.eventIds | ForEach-Object { [string]$_ })
            finalGridVersion = [long]$phase.finalGridVersion
            repairOperationCount = [int]$phase.repairOperationCount
            planOperationCount = [int]$phase.planOperationCount
            succeededPlanCount = [int]$phase.succeededPlanCount
            noPathPlanCount = [int]$phase.noPathPlanCount
            budgetExceededOperationCount = [int]$phase.budgetExceededOperationCount
            processedNodesOrCells = [long]$phase.processedNodesOrCells
            expandedNodes = [long]$phase.expandedNodes
            relaxedEdges = [long]$phase.relaxedEdges
            repairedCells = [long]$phase.repairedCells
        })
    }
    return [pscustomobject][ordered]@{
        scenarioId = [string]$Result.scenarioId
        scenarioFingerprintSha256 = [string]$Result.scenarioFingerprintSha256
        algorithmId = [string]$Result.algorithmId
        agentCount = [int]$Result.agentCount
        scheduledEventCount = [int]$Result.scheduledEventCount
        dynamicPlanningPhaseCount = [int]$Result.dynamicPlanningPhaseCount
        planOperationCount = [int]$Result.planOperationCount
        repairOperationCount = [int]$Result.repairOperationCount
        succeededPlanCount = [int]$Result.succeededPlanCount
        noPathPlanCount = [int]$Result.noPathPlanCount
        budgetExceededPlanCount = [int]$Result.budgetExceededPlanCount
        invalidPlanCount = [int]$Result.invalidPlanCount
        failedPlanCount = [int]$Result.failedPlanCount
        budgetExceededOperationCount = [int]$Result.budgetExceededOperationCount
        processedNodesOrCells = [long]$Result.processedNodesOrCells
        expandedNodes = [long]$Result.expandedNodes
        relaxedEdges = [long]$Result.relaxedEdges
        repairedCells = [long]$Result.repairedCells
        finalGridVersion = [long]$Result.finalGridVersion
        usesFixedScenarioStarts = [bool]$Result.usesFixedScenarioStarts
        fairnessSchemaVersion = [int]$Result.fairnessSchemaVersion
        fairnessProtocolId = [string]$Result.fairnessProtocolId
        fairnessProtocolSha256 = [string]$Result.fairnessProtocolSha256
        algorithmSpecificationId = [string]$Result.algorithmSpecificationId
        algorithmSpecificationSha256 = [string]$Result.algorithmSpecificationSha256
        algorithmImplementationSha256 = [string]$Result.algorithmImplementationSha256
        workloadSpecificationId = [string]$Result.workloadSpecificationId
        workloadSpecificationSha256 = [string]$Result.workloadSpecificationSha256
        goalCohortId = [string]$Result.goalCohortId
        comparisonCohortId = [string]$Result.comparisonCohortId
        distinctGoalCount = [int]$Result.distinctGoalCount
        plannerInstanceCount = [int]$Result.plannerInstanceCount
        persistentStateInstanceCount = [int]$Result.persistentStateInstanceCount
        sharedFieldInstanceCount = [int]$Result.sharedFieldInstanceCount
        plannerStateModelId = [string]$Result.plannerStateModelId
        processedWorkUnit = [string]$Result.processedWorkUnit
        nativeMetricsSemanticsId = [string]$Result.nativeMetricsSemanticsId
        dynamicCostIncludesAllRepairsAndPostEventPlans = [bool]$Result.dynamicCostIncludesAllRepairsAndPostEventPlans
        initializationProcessedNodesOrCells = [long]$Result.initializationProcessedNodesOrCells
        initialPlanningProcessedNodesOrCells = [long]$Result.initialPlanningProcessedNodesOrCells
        dynamicProcessedNodesOrCells = [long]$Result.dynamicProcessedNodesOrCells
        completed = [bool]$Result.completed
        dynamicPhases = $phases.ToArray()
    }
}

function Compare-G13R2StructuralResults {
    param([Parameter(Mandatory = $true)]$Reference, [Parameter(Mandatory = $true)]$Candidate)
    $referenceProjection = Get-G13R2StructuralProjection -Result $Reference
    $candidateProjection = Get-G13R2StructuralProjection -Result $Candidate
    $referenceText = ConvertTo-G13R2JsonText -Value $referenceProjection -Depth 20
    $candidateText = ConvertTo-G13R2JsonText -Value $candidateProjection -Depth 20
    return [pscustomobject][ordered]@{
        passed = [string]::Equals($referenceText, $candidateText, [System.StringComparison]::Ordinal)
        referenceProjectionSha256 = Get-Gate13StringSha256 -Value $referenceText
        candidateProjectionSha256 = Get-Gate13StringSha256 -Value $candidateText
    }
}

function Get-G13R2SampleSizeCandidate {
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
        precisionStatus = if ($required -gt $MaximumBlocks) { 'blocked-versioned-amendment-required' } else { 'within-cap' }
    }
}

function New-G13R2HistoricalProjectionConfig {
    param([Parameter(Mandatory = $true)][string]$ProjectPath, [string]$ProvenancePath)
    $ProjectPath = [System.IO.Path]::GetFullPath($ProjectPath)
    if ([string]::IsNullOrWhiteSpace($ProvenancePath)) { $ProvenancePath = Join-Path $ProjectPath 'Research\Gate13_ProcessReuse_Provenance.v1.json' }
    $provenance = Read-G13R2Json -Path $ProvenancePath
    $coldConfigPath = Join-Path $ProjectPath 'Research\Gate13_Formal_Campaign_Config.v1.json'
    $coldConfig = Read-G13R2Json -Path $coldConfigPath
    if ((Get-G13R2LowerSha256 -Path $coldConfigPath) -ne 'b74f777f4022d5890839ed54987b2ae28a9ff27ae400c5a8d72dd0efccfd0874') { throw 'Cold config hash changed.' }
    $campaigns = New-Object System.Collections.Generic.List[object]
    foreach ($campaign in @($coldConfig.campaigns | Sort-Object ordinal)) {
        $campaigns.Add([pscustomobject][ordered]@{
            ordinal = [int]$campaign.ordinal
            campaignId = ([string]$campaign.campaignId).Replace('g13-', 'g13r2-')
            sourceColdCampaignId = [string]$campaign.campaignId
            scenarioId = [string]$campaign.scenarioId
            scenarioRelativePath = [string]$campaign.scenarioRelativePath
            scenarioSourceSha256 = [string]$campaign.scenarioSourceSha256
            scenarioCanonicalSha256 = [string]$campaign.scenarioCanonicalSha256
            scenarioFingerprintSha256 = [string]$campaign.scenarioFingerprintSha256
            comparisonCohortId = [string]$campaign.comparisonCohortId
            canonicalAlgorithmOrder = @($campaign.canonicalAlgorithmOrder)
            blockCount = [int]$campaign.blockCount
            blockProcessCount = [int]$campaign.blockCount
            algorithmCount = [int]$campaign.algorithmCount
            sampleCount = [int]$campaign.sampleCount
            completeBalanceCycleCount = [int]$campaign.completeBalanceCycleCount
            williamsCycleRows = @($campaign.williamsCycleRows)
            canonicalScheduleSha256 = [string]$campaign.canonicalScheduleSha256
            outputRelativePath = [string]$campaign.outputRelativePath
        })
    }
    $sampleCount = [int](($campaigns.ToArray() | Measure-Object -Property sampleCount -Sum).Sum)
    $blockProcessCount = [int](($campaigns.ToArray() | Measure-Object -Property blockProcessCount -Sum).Sum)
    if ($campaigns.Count -ne 74 -or $sampleCount -ne 15056 -or $blockProcessCount -ne 5864) { throw 'Process-reuse formal projection cardinality mismatch.' }
    return [pscustomobject][ordered]@{
        schemaVersion = 1
        configId = 'gate13-r2-historical-cap148-projection-v1'
        configKind = 'superseded-historical-projection-not-final-config-v1'
        materialPassport = [ordered]@{ originSkill = 'experiment-agent'; originMode = 'plan'; verificationStatus = 'HISTORICAL-PROJECTION-DO-NOT-AUTHORIZE'; versionLabel = 'gate13_r2_historical_projection_v1' }
        authorizationBoundary = [ordered]@{
            authorizationReference = 'user-message-2026-10-06-gate13-cold-process-to-process-reuse-controlled-design-migration'
            nonFormalPilotAuthorized = $true
            gate13ProcessReuseFormalExecutionAuthorized = $false
            formalCampaignStartAllowed = $false
            formalExecutionReceiptPresent = $false
            configurationMayAuthorizeExecution = $false
        }
        sourceColdDesign = [ordered]@{
            configRelativePath = 'Research/Gate13_Formal_Campaign_Config.v1.json'
            configSha256 = 'b74f777f4022d5890839ed54987b2ae28a9ff27ae400c5a8d72dd0efccfd0874'
            terminationReceiptRelativePath = 'Research/Gate13_ColdProcess_Termination_Receipt.v1.json'
            terminationReceiptSha256 = '4661a3edc6e569b068e065456ab34f839d60030b1d668a925ca5b9dad9e481a4'
            disposition = 'USER-TERMINATED-DESIGN-CHANGE-EXCLUDED-FROM-ANALYSIS'
        }
        processReuseDesign = [ordered]@{
            designId = 'one-fresh-unity-process-per-williams-block-v1'
            independentUnit = 'williams-block-unity-process-v1'
            oneBlockPerUnityProcess = $true
            oneSamplePerAlgorithmPerProcess = $true
            eachSampleUsesIndependentUnityProcess = $false
            longLivedCampaignProcessAllowed = $false
            forcedGcBeforeEverySample = $true
            withinProcessSamplesCorrelated = $true
            failurePolicy = 'fail-closed-no-later-position-no-auto-retry-no-resume-v1'
        }
        frozenInputs = [ordered]@{
            provenance = [ordered]@{ relativePath = 'Research/Gate13_ProcessReuse_Provenance.v1.json'; sha256 = Get-G13R2LowerSha256 -Path $ProvenancePath }
            specification = $provenance.specification
            testDesign = $provenance.testDesign
            pilotPlan = $provenance.pilotPlan
            coldFormalConfig = [ordered]@{ relativePath = 'Research/Gate13_Formal_Campaign_Config.v1.json'; sha256 = 'b74f777f4022d5890839ed54987b2ae28a9ff27ae400c5a8d72dd0efccfd0874' }
            readinessAmendment = [ordered]@{ relativePath = 'Research/Gate13_Readiness_Amendment.v1.json'; sha256 = '1ccf5c6e1e2c646d160e7b597381c797cc14e6123134a28b429fcb773515e8b2' }
            gate11BundleManifest = $provenance.gate11BundleManifest
            gate11Matrix = $provenance.gate11Matrix
            gate11Preregistration = $provenance.gate11Preregistration
            planningWorkloadRunner = $provenance.planningWorkloadRunner
            experimentRunner = $provenance.experimentRunner
            jsonlLogger = $provenance.jsonlLogger
            fairnessContracts = $provenance.fairnessContracts
        }
        runtimeFiles = [ordered]@{
            processReuseBatchCommand = $provenance.processReuseBatchCommand
            processReusePowerShellRunner = $provenance.processReusePowerShellRunner
            processReusePreparationModule = $provenance.processReusePreparationModule
            pilotOrchestrator = $provenance.pilotOrchestrator
            pilotAnalyzer = $provenance.pilotAnalyzer
        }
        unity = $coldConfig.unity
        output = [ordered]@{
            rootRelativePath = 'Research/FormalRuns/Gate13_ProcessReuse/v1'
            createNewOnly = $true
            overwriteAllowed = $false
            automaticResumeAllowed = $false
            automaticRetryAllowed = $false
            rootCreationAuthorized = $false
        }
        precisionRule = [ordered]@{
            relativeHalfWidthTarget = 0.10
            formula = 'max-of-marginal-and-within-block-paired-requirements-v1'
            minimumIndependentBlocks = 30
            cycleMultiple = 4
            maximumIndependentBlocks = 148
            pilotReestimationRequiredBeforeFormalAuthorization = $true
        }
        scheduleDesign = [ordered]@{
            orderDesignId = 'williams-balanced-v1'
            scenarioOrder = 'gate11-matrix-original-order'
            completeWilliamsCyclesRequired = $true
            eachBlockUsesIndependentUnityProcess = $true
            eachSampleUsesIndependentUnityProcess = $false
            oneBlockPerUnityProcess = $true
            algorithmOccursAtMostOncePerProcess = $true
            maximumBlocksSupported = 148
        }
        checkpoint = [ordered]@{
            blockCheckpointAtomic = $true
            updateBeforeAndAfterEveryPosition = $true
            campaignCheckpointAtomic = $true
            authorizesAutomaticResume = $false
            authorizesAutomaticRetry = $false
        }
        totals = [ordered]@{
            scenarioCount = 53
            eligibilityCellCount = 212
            campaignCount = 74
            expectedAlgorithmSampleCount = $sampleCount
            expectedUnityBlockProcessCount = $blockProcessCount
            sampleSizesStatus = 'historical-cap148-projection-pending-process-reuse-pilot-reestimation'
        }
        campaigns = $campaigns.ToArray()
    }
}

function Test-G13R2HistoricalProjectionConfig {
    param([Parameter(Mandatory = $true)][string]$ProjectPath, [Parameter(Mandatory = $true)]$Config, [string]$ConfigPath)
    $errors = New-Object System.Collections.Generic.List[string]
    try {
        $expected = New-G13R2HistoricalProjectionConfig -ProjectPath $ProjectPath
        $expectedText = ConvertTo-G13R2JsonText -Value $expected -Depth 40
        $actualText = ConvertTo-G13R2JsonText -Value $Config -Depth 40
        if (-not [string]::Equals($expectedText, $actualText, [System.StringComparison]::Ordinal)) { throw 'Process-reuse historical projection differs from deterministic reconstruction.' }
        if (-not [string]::IsNullOrWhiteSpace($ConfigPath)) {
            $fileText = [System.IO.File]::ReadAllText([System.IO.Path]::GetFullPath($ConfigPath), $script:G13R2Utf8).Replace("`r`n", "`n").Replace("`r", "`n")
            if (-not $fileText.EndsWith("`n")) { $fileText += "`n" }
            if (-not [string]::Equals($fileText, $expectedText, [System.StringComparison]::Ordinal)) { throw 'Process-reuse formal config file bytes are not canonical.' }
        }
        $root = Join-Path $ProjectPath ([string]$Config.output.rootRelativePath).Replace('/', '\')
        if (Test-Path -LiteralPath $root) { throw 'Reserved process-reuse formal root exists during non-executing preparation.' }
        if ($Config.authorizationBoundary.formalCampaignStartAllowed -ne $false -or $Config.output.rootCreationAuthorized -ne $false) { throw 'Formal config unexpectedly authorizes execution.' }
    } catch { $errors.Add($_.Exception.Message) }
    return [pscustomobject][ordered]@{ passed = $errors.Count -eq 0; errors = $errors.ToArray(); campaignCount = @($Config.campaigns).Count; expectedAlgorithmSampleCount = [int]$Config.totals.expectedAlgorithmSampleCount; expectedUnityBlockProcessCount = [int]$Config.totals.expectedUnityBlockProcessCount; formalExecutionAuthorized = $false }
}

function New-G13R2PilotReestimatedFormalConfig {
    param(
        [Parameter(Mandatory = $true)][string]$ProjectPath,
        [string]$ProvenancePath,
        [string]$AmendmentPath
    )
    $ProjectPath = [System.IO.Path]::GetFullPath($ProjectPath)
    if ([string]::IsNullOrWhiteSpace($ProvenancePath)) { $ProvenancePath = Join-Path $ProjectPath 'Research\Gate13_ProcessReuse_Provenance.v4.json' }
    if ([string]::IsNullOrWhiteSpace($AmendmentPath)) { $AmendmentPath = Join-Path $ProjectPath 'Research\Gate13_ProcessReuse_Amendment.v1.json' }
    $ProvenancePath = [System.IO.Path]::GetFullPath($ProvenancePath)
    $AmendmentPath = [System.IO.Path]::GetFullPath($AmendmentPath)
    $provenance = Read-G13R2Json -Path $ProvenancePath
    $amendment = Read-G13R2Json -Path $AmendmentPath
    if ($amendment.amendmentId -ne 'gate13-r2-process-reuse-readiness-amendment-v1' -or $amendment.pilotVerdict -ne 'PILOT-PASSED-FORMAL-NOT-AUTHORIZED') { throw 'Process-reuse amendment identity/verdict mismatch.' }
    if ($amendment.authorizationBoundary.formalCampaignAuthorized -ne $false -or $amendment.authorizationBoundary.formalOutputRootCreationAllowed -ne $false) { throw 'Process-reuse amendment unexpectedly authorizes formal execution.' }
    if ([string]$amendment.frozenInputs.provenance.sha256 -ne (Get-G13R2LowerSha256 -Path $ProvenancePath)) { throw 'Process-reuse amendment provenance hash mismatch.' }
    foreach ($property in $amendment.pilotEvidence.PSObject.Properties) {
        $evidence = $property.Value
        [void](Assert-G13R2BoundFile -ProjectPath $ProjectPath -RelativePath ([string]$evidence.relativePath) -ExpectedSha256 ([string]$evidence.sha256) -Label ("Process-reuse pilot evidence " + $property.Name))
    }
    $pilotManifestPath = Join-Path $ProjectPath ([string]$amendment.pilotEvidence.pilotManifest.relativePath).Replace('/', '\')
    $pilotManifest = Read-G13R2Json -Path $pilotManifestPath
    if ($pilotManifest.completed -ne $true -or $pilotManifest.formalCampaign -ne $false -or $pilotManifest.excludedFromFormalAnalysis -ne $true -or $pilotManifest.formalExecutionAuthorized -ne $false) { throw 'Process-reuse pilot manifest is not a completed excluded non-formal pilot.' }
    $candidatePath = Join-Path $ProjectPath ([string]$amendment.pilotEvidence.candidateSampleSizes.relativePath).Replace('/', '\')
    $candidate = Read-G13R2Json -Path $candidatePath
    if ($candidate.anyOverCap -ne $false -or [int]$candidate.maximumIndependentBlocks -ne 148 -or [double]$candidate.precisionRelativeHalfWidthTarget -ne 0.10) { throw 'Process-reuse pilot candidate decision is not within the frozen cap/precision policy.' }
    $cohortBlocks = [ordered]@{}
    foreach ($decision in @($amendment.sampleSizeDecision.cohorts)) {
        $blocks = [int]$decision.scheduledIndependentBlocks
        if ($blocks -lt 30 -or $blocks -gt 148 -or $blocks % 4 -ne 0) { throw "Invalid scheduled independent block count: $($decision.comparisonCohortId)=$blocks" }
        $cohortBlocks[[string]$decision.comparisonCohortId] = $blocks
    }
    if ($cohortBlocks.Count -ne 3) { throw 'Process-reuse amendment must schedule exactly three cohorts.' }
    $coldConfigPath = Join-Path $ProjectPath 'Research\Gate13_Formal_Campaign_Config.v1.json'
    $coldConfig = Read-G13R2Json -Path $coldConfigPath
    if ((Get-G13R2LowerSha256 -Path $coldConfigPath) -ne 'b74f777f4022d5890839ed54987b2ae28a9ff27ae400c5a8d72dd0efccfd0874') { throw 'Cold config hash changed.' }
    $campaigns = New-Object System.Collections.Generic.List[object]
    foreach ($campaign in @($coldConfig.campaigns | Sort-Object ordinal)) {
        $cohortId = [string]$campaign.comparisonCohortId
        if (-not $cohortBlocks.Contains($cohortId)) { throw "Missing process-reuse cohort schedule: $cohortId" }
        $campaignId = ([string]$campaign.campaignId).Replace('g13-', 'g13r2-')
        $schedule = New-Gate13WilliamsSchedule -CampaignId $campaignId -ComparisonCohortId $cohortId -Blocks ([int]$cohortBlocks[$cohortId])
        $campaigns.Add([pscustomobject][ordered]@{
            ordinal = [int]$campaign.ordinal
            campaignId = $campaignId
            sourceColdCampaignId = [string]$campaign.campaignId
            sourceColdCanonicalScheduleSha256 = [string]$campaign.canonicalScheduleSha256
            scenarioId = [string]$campaign.scenarioId
            scenarioRelativePath = [string]$campaign.scenarioRelativePath
            scenarioSourceSha256 = [string]$campaign.scenarioSourceSha256
            scenarioCanonicalSha256 = [string]$campaign.scenarioCanonicalSha256
            scenarioFingerprintSha256 = [string]$campaign.scenarioFingerprintSha256
            comparisonCohortId = $cohortId
            canonicalAlgorithmOrder = @($schedule.canonicalAlgorithmOrder)
            blockCount = [int]$schedule.blockCount
            blockProcessCount = [int]$schedule.blockCount
            algorithmCount = [int]$schedule.algorithmCount
            sampleCount = [int]$schedule.sampleCount
            completeBalanceCycleCount = [int]$schedule.completeBalanceCycleCount
            williamsCycleRows = @($schedule.williamsCycleRows)
            canonicalScheduleSha256 = [string]$schedule.canonicalScheduleSha256
            outputRelativePath = [string]$campaign.outputRelativePath
        })
    }
    $sampleCount = [int](($campaigns.ToArray() | Measure-Object -Property sampleCount -Sum).Sum)
    $blockProcessCount = [int](($campaigns.ToArray() | Measure-Object -Property blockProcessCount -Sum).Sum)
    if ($campaigns.Count -ne 74) { throw 'Process-reuse formal campaign count must remain 74.' }
    $cohortSummaries = New-Object System.Collections.Generic.List[object]
    foreach ($cohortId in @('four-algorithm-shared-goal-v1', 'per-agent-heterogeneous-goal-v1', 'grouped-field-heterogeneous-goal-v1')) {
        $rows = @($campaigns | Where-Object comparisonCohortId -eq $cohortId)
        $cohortSummaries.Add([pscustomobject][ordered]@{
            comparisonCohortId = $cohortId
            scenarioCount = $rows.Count
            algorithmCount = [int]$rows[0].algorithmCount
            blocksPerScenario = [int]$rows[0].blockCount
            completeWilliamsCyclesPerScenario = [int]$rows[0].completeBalanceCycleCount
            expectedUnityBlockProcessCount = [int](($rows | Measure-Object -Property blockProcessCount -Sum).Sum)
            expectedAlgorithmSampleCount = [int](($rows | Measure-Object -Property sampleCount -Sum).Sum)
        })
    }
    $budgetPath = Join-Path $ProjectPath ([string]$amendment.pilotEvidence.budgetFeasibility.relativePath).Replace('/', '\')
    $budget = Read-G13R2Json -Path $budgetPath
    if ([int]$budget.candidateFormalBlockProcessCount -ne $blockProcessCount -or [int]$budget.candidateFormalAlgorithmSampleCount -ne $sampleCount) { throw 'Pilot budget projection and candidate formal schedule disagree.' }
    $minimumPostCampaignFreeBytes = [int64]21474836480
    $projectedP95Bytes = [int64]$budget.candidateProjectedP95RawBytes
    return [pscustomobject][ordered]@{
        schemaVersion = 1
        configId = 'gate13-r2-process-reuse-formal-campaign-config-v1'
        configKind = 'prepared-nonexecuting-process-reuse-formal-config-v1'
        materialPassport = [ordered]@{ originSkill = 'experiment-agent'; originMode = 'run'; verificationStatus = 'PREPARED-FORMAL-NOT-AUTHORIZED'; versionLabel = 'gate13_r2_process_reuse_formal_config_v1' }
        authorizationBoundary = [ordered]@{
            authorizationReference = 'user-message-2026-10-06-gate13-cold-process-to-process-reuse-controlled-design-migration'
            nonFormalPilotAuthorized = $true
            gate13ProcessReuseFormalExecutionAuthorized = $false
            formalCampaignStartAllowed = $false
            formalExecutionReceiptPresent = $false
            configurationMayAuthorizeExecution = $false
        }
        sourceColdDesign = [ordered]@{
            configRelativePath = 'Research/Gate13_Formal_Campaign_Config.v1.json'
            configSha256 = 'b74f777f4022d5890839ed54987b2ae28a9ff27ae400c5a8d72dd0efccfd0874'
            terminationReceiptRelativePath = 'Research/Gate13_ColdProcess_Termination_Receipt.v1.json'
            terminationReceiptSha256 = '4661a3edc6e569b068e065456ab34f839d60030b1d668a925ca5b9dad9e481a4'
            disposition = 'USER-TERMINATED-DESIGN-CHANGE-EXCLUDED-FROM-ANALYSIS'
        }
        processReuseDesign = [ordered]@{
            designId = 'one-fresh-unity-process-per-williams-block-v1'
            independentUnit = 'williams-block-unity-process-v1'
            oneBlockPerUnityProcess = $true
            oneSamplePerAlgorithmPerProcess = $true
            eachSampleUsesIndependentUnityProcess = $false
            longLivedCampaignProcessAllowed = $false
            forcedGcBeforeEverySample = $true
            withinProcessSamplesCorrelated = $true
            failurePolicy = 'fail-closed-no-later-position-no-auto-retry-no-resume-v1'
        }
        frozenInputs = [ordered]@{
            provenance = [ordered]@{ relativePath = Get-G13R2ProjectRelativePath -ProjectPath $ProjectPath -FullPath $ProvenancePath; sha256 = Get-G13R2LowerSha256 -Path $ProvenancePath }
            processReuseAmendment = [ordered]@{ relativePath = 'Research/Gate13_ProcessReuse_Amendment.v1.json'; sha256 = Get-G13R2LowerSha256 -Path $AmendmentPath }
            specification = $provenance.specification
            testDesign = $provenance.testDesign
            pilotPlan = $provenance.pilotPlan
            pilotManifest = $amendment.pilotEvidence.pilotManifest
            candidateSampleSizes = $amendment.pilotEvidence.candidateSampleSizes
            budgetFeasibility = $amendment.pilotEvidence.budgetFeasibility
            coldFormalConfig = [ordered]@{ relativePath = 'Research/Gate13_Formal_Campaign_Config.v1.json'; sha256 = 'b74f777f4022d5890839ed54987b2ae28a9ff27ae400c5a8d72dd0efccfd0874' }
            readinessAmendment = [ordered]@{ relativePath = 'Research/Gate13_Readiness_Amendment.v1.json'; sha256 = '1ccf5c6e1e2c646d160e7b597381c797cc14e6123134a28b429fcb773515e8b2' }
            gate11BundleManifest = $provenance.gate11BundleManifest
            gate11Matrix = $provenance.gate11Matrix
            gate11Preregistration = $provenance.gate11Preregistration
            planningWorkloadRunner = $provenance.planningWorkloadRunner
            experimentRunner = $provenance.experimentRunner
            jsonlLogger = $provenance.jsonlLogger
            fairnessContracts = $provenance.fairnessContracts
        }
        runtimeFiles = [ordered]@{
            processReuseBatchCommand = $provenance.processReuseBatchCommand
            processReusePowerShellRunner = $provenance.processReusePowerShellRunner
            processReusePreparationModule = $provenance.processReusePreparationModule
            pilotOrchestrator = $provenance.pilotOrchestrator
            pilotAnalyzer = $provenance.pilotAnalyzer
            formalPreparationGenerator = $provenance.formalPreparationGenerator
        }
        unity = $coldConfig.unity
        output = [ordered]@{
            rootRelativePath = 'Research/FormalRuns/Gate13_ProcessReuse/v1'
            createNewOnly = $true
            overwriteAllowed = $false
            automaticResumeAllowed = $false
            automaticRetryAllowed = $false
            rootCreationAuthorized = $false
        }
        launchPreflight = [ordered]@{
            mustRunAfterFutureExecutionAuthorizationValidation = $true
            mustRunImmediatelyBeforeOutputRootCreation = $true
            comparisonUsesRawInt64Bytes = $true
            p95ProjectedOutputBytes = $projectedP95Bytes
            minimumPostCampaignFreeBytes = $minimumPostCampaignFreeBytes
            minimumLaunchFreeBytes = $projectedP95Bytes + $minimumPostCampaignFreeBytes
            failureAction = 'stop-before-formal-root-and-samples'
        }
        environmentPreflight = $coldConfig.environmentPreflight
        precisionRule = [ordered]@{
            relativeHalfWidthTarget = 0.10
            formula = 'max-of-marginal-and-within-block-paired-requirements-v1'
            minimumIndependentBlocks = 30
            cycleMultiple = 4
            maximumIndependentBlocks = 148
            pilotReestimationCompleted = $true
        }
        scheduleDesign = [ordered]@{
            orderDesignId = 'williams-balanced-v1'
            scenarioOrder = 'gate11-matrix-original-order'
            completeWilliamsCyclesRequired = $true
            eachBlockUsesIndependentUnityProcess = $true
            eachSampleUsesIndependentUnityProcess = $false
            oneBlockPerUnityProcess = $true
            algorithmOccursAtMostOncePerProcess = $true
            maximumBlocksSupported = 148
        }
        checkpoint = [ordered]@{
            blockCheckpointAtomic = $true
            updateBeforeAndAfterEveryPosition = $true
            campaignCheckpointAtomic = $true
            authorizesAutomaticResume = $false
            authorizesAutomaticRetry = $false
        }
        totals = [ordered]@{
            scenarioCount = 53
            eligibilityCellCount = 212
            campaignCount = 74
            expectedAlgorithmSampleCount = $sampleCount
            expectedUnityBlockProcessCount = $blockProcessCount
            cohortSummaries = $cohortSummaries.ToArray()
            sampleSizesStatus = 'process-reuse-pilot-reestimated-within-cap-prepared-not-authorized'
        }
        campaigns = $campaigns.ToArray()
    }
}

function Test-G13R2PilotReestimatedFormalConfig {
    param(
        [Parameter(Mandatory = $true)][string]$ProjectPath,
        [Parameter(Mandatory = $true)]$Config,
        [string]$ConfigPath,
        [string]$ProvenancePath,
        [string]$AmendmentPath
    )
    $errors = New-Object System.Collections.Generic.List[string]
    try {
        $expected = New-G13R2PilotReestimatedFormalConfig -ProjectPath $ProjectPath -ProvenancePath $ProvenancePath -AmendmentPath $AmendmentPath
        $expectedText = ConvertTo-G13R2JsonText -Value $expected -Depth 50
        $actualText = ConvertTo-G13R2JsonText -Value $Config -Depth 50
        if (-not [string]::Equals($expectedText, $actualText, [System.StringComparison]::Ordinal)) { throw 'Process-reuse formal config differs from deterministic pilot-reestimated reconstruction.' }
        if (-not [string]::IsNullOrWhiteSpace($ConfigPath)) {
            $fileText = [System.IO.File]::ReadAllText([System.IO.Path]::GetFullPath($ConfigPath), $script:G13R2Utf8).Replace("`r`n", "`n").Replace("`r", "`n")
            if (-not $fileText.EndsWith("`n")) { $fileText += "`n" }
            if (-not [string]::Equals($fileText, $expectedText, [System.StringComparison]::Ordinal)) { throw 'Process-reuse formal config file bytes are not canonical.' }
        }
        $root = Join-Path $ProjectPath ([string]$Config.output.rootRelativePath).Replace('/', '\')
        if (Test-Path -LiteralPath $root) { throw 'Reserved process-reuse formal root exists during non-executing preparation.' }
        if ($Config.authorizationBoundary.formalCampaignStartAllowed -ne $false -or $Config.output.rootCreationAuthorized -ne $false) { throw 'Formal config unexpectedly authorizes execution.' }
    } catch { $errors.Add($_.Exception.Message) }
    return [pscustomobject][ordered]@{
        passed = $errors.Count -eq 0
        errors = $errors.ToArray()
        campaignCount = @($Config.campaigns).Count
        expectedAlgorithmSampleCount = [int]$Config.totals.expectedAlgorithmSampleCount
        expectedUnityBlockProcessCount = [int]$Config.totals.expectedUnityBlockProcessCount
        formalExecutionAuthorized = $false
    }
}

Export-ModuleMember -Function @(
    'Get-G13R2LowerSha256',
    'Read-G13R2Json',
    'ConvertTo-G13R2JsonText',
    'Write-G13R2Utf8NoBomJson',
    'Write-G13R2AtomicUtf8NoBomJson',
    'Get-G13R2ProjectRelativePath',
    'Assert-G13R2BoundFile',
    'Get-G13R2AlgorithmSlug',
    'Get-G13R2CohortAlgorithms',
    'Test-G13R2PilotPlan',
    'New-G13R2BlockPlan',
    'Get-G13R2StructuralProjection',
    'Compare-G13R2StructuralResults',
    'Get-G13R2SampleSizeCandidate',
    'New-G13R2HistoricalProjectionConfig',
    'Test-G13R2HistoricalProjectionConfig',
    'New-G13R2PilotReestimatedFormalConfig',
    'Test-G13R2PilotReestimatedFormalConfig'
)
