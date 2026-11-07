[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$ProjectPath,
    [Parameter(Mandatory = $true)][string]$OutputDirectory,
    [switch]$BindingSmokeOnly
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if ([string]::IsNullOrWhiteSpace($ProjectPath) -or -not [IO.Path]::IsPathRooted($ProjectPath)) { throw 'Gate13R serial 10pct formal-preparation generator v2 requires an explicit absolute ProjectPath.' }
$ProjectPath = [IO.Path]::GetFullPath($ProjectPath)
if ($BindingSmokeOnly) { Write-Output "BINDING-SMOKE-PASSED|New-Gate13RSerial10pctFormalPreparationV2|$ProjectPath"; exit 0 }
Import-Module (Join-Path $ProjectPath 'Research\Gate13RSerial10pctFormalPreparationV2.psm1') -Force

$OutputDirectory = [IO.Path]::GetFullPath($OutputDirectory).TrimEnd('\', '/')
$researchRoot = [IO.Path]::GetFullPath((Join-Path $ProjectPath 'Research')).TrimEnd('\', '/')
$verificationBase = [IO.Path]::GetFullPath((Join-Path $ProjectPath 'Research\Verification\Gate13R_Serial_10pct')).TrimEnd('\', '/')
$formalRoot = [IO.Path]::GetFullPath((Join-Path $ProjectPath 'Research\FormalRuns\Gate13R_Serial_10pct\v2')).TrimEnd('\', '/')
$outputAllowed = $OutputDirectory.Equals($researchRoot, [StringComparison]::OrdinalIgnoreCase) -or (Test-G13RPathWithin -BasePath $verificationBase -CandidatePath $OutputDirectory)
if (-not $outputAllowed) { throw 'OutputDirectory must be Research or an isolated Gate13R verification regeneration directory.' }
if (Test-G13RPathWithin -BasePath $formalRoot -CandidatePath $OutputDirectory -AllowBase) { throw 'Preparation artifacts cannot be generated inside the formal root.' }
if (Test-Path -LiteralPath $formalRoot) { throw 'Reserved Gate13R formal root must remain absent during preparation generation.' }
if (-not (Test-Path -LiteralPath $OutputDirectory)) { New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null }

$names = [ordered]@{
    schedule = 'Gate13R_Serial_10pct_Formal_Williams_Block_Schedule.v2.jsonl'
    scheduleManifest = 'Gate13R_Serial_10pct_Formal_Williams_Block_Schedule_Manifest.v2.json'
    config = 'Gate13R_Serial_10pct_Formal_Campaign_Config.v2.json'
    provenance = 'Gate13R_Serial_10pct_Formal_Preparation_Provenance.v2.json'
    summary = 'Gate13R_Serial_10pct_Formal_Preparation_Generation_Summary.v2.json'
}
$paths = @{}
foreach ($key in $names.Keys) {
    $path = Join-Path $OutputDirectory $names[$key]
    if (Test-Path -LiteralPath $path) { throw "Create-new preparation artifact already exists: $path" }
    $paths[$key] = $path
}

$bound = [ordered]@{
    authorization = [ordered]@{ path = 'Research/Gate13R_Serial_10pct_Selection.v1.json'; sha256 = '69dd7f80a5bf415ae4d666fbd8e50fce134bc08150e674fcd16c0ca1917f553c' }
    specification = [ordered]@{ path = 'Research/Gate13R_Serial_10pct_Redesign_Specification.v1.md'; sha256 = '63a417587f05b254f2e42bc8f51b350d920f132795949d95cb7152190b44a940' }
    testDesign = [ordered]@{ path = 'Research/Gate13R_Serial_10pct_Test_Design.v1.md'; sha256 = '39cd0a124a6e7f2fca056fd5b887206d8a180e05a493bf552da18fd4bda3ccf3' }
    amendment = [ordered]@{ path = 'Research/Gate13R_Serial_10pct_Readiness_Amendment.v1.json'; sha256 = 'f0a23f29a7b75afb2ebd981bb341d5c3ef2f4bb875b5cd0faf0ead62fe5c4359' }
    serialReadinessProvenance = [ordered]@{ path = 'Research/Gate13R_Serial_10pct_Provenance.v1.json'; sha256 = '3c86b284010e2f3eea997a1773e85560e971ceafccb8e0652fa6048301d7b388' }
    serialEvidenceAudit = [ordered]@{ path = 'Research/Gate13R_Serial_10pct_Gate12R_v4_Evidence_Audit.v1.json'; sha256 = '84d47ac735a341ae55d8320e83c40833708409c90da47dd40d77cb4b5e14db5f' }
    gate11Bundle = [ordered]@{ path = 'Research/FormalScenarios/Gate11R_5pct/v1/bundle-manifest.json'; sha256 = '5baaeec18344a9e99e55da38f3c4875b7e7e9f3bf0add9d5f2d2f1e821b5f7fc' }
    gate11Matrix = [ordered]@{ path = 'Research/FormalScenarios/Gate11R_5pct/v1/formal-scenario-matrix.json'; sha256 = 'cc5f020003f3fad75bd82ebb2c26df521fd639ff0ee5376132853120dbc16aa3' }
    gate11Preregistration = [ordered]@{ path = 'Research/FormalScenarios/Gate11R_5pct/v1/preregistered-analysis.json'; sha256 = 'd1c81a83d85377f37adc6b234e7523e8b2189632bf55416734bcbbd92bf7db47' }
    campaignCatalog = [ordered]@{ path = 'Research/PlayableExperiments/Gate11R_5pct/v1/campaign-profile-catalog.json'; sha256 = 'f3fd6e390b57f2f230ba62a05a2471f38065d30ec6e8839be6b55b6511f961bd' }
    presetCatalog = [ordered]@{ path = 'Research/PlayableExperiments/Gate11R_5pct/v1/algorithm-preset-catalog.json'; sha256 = 'c0aad543e8dfe8ab8f5245b6d579a459b586f030d18e3cb360917fbce6393253' }
    sceneCatalog = [ordered]@{ path = 'Research/PlayableExperiments/Gate11R_5pct/v1/playable-scene-catalog.json'; sha256 = '9b1265c2a19430016ab4365bdb895ea03f30916355ffa73782e56ab1f6d2b8b8' }
    coverageManifest = [ordered]@{ path = 'Research/PlayableExperiments/Gate11R_5pct/v1/coverage-manifest.json'; sha256 = '615c81b99fc31b65b56390017eeed34deaae8c4f8177b74631abd619f63d22d4' }
    gate12Readiness = [ordered]@{ path = 'Research/Gate12R_Readiness_Checkpoint.v1.json'; sha256 = '93d1ffac30305ecbc3ff32820aa0eee016c7a2cc6824f41c491aac393cfd291d' }
    candidateN = [ordered]@{ path = 'Research/PilotRuns/Gate12R_ProcessReuse_5pct/v4/candidate-n-formal.json'; sha256 = '5e77d9b69c4c0e45dec204ca1943867453d29dcbdf1ebd24f0809af6d649c387' }
    budgetStorage = [ordered]@{ path = 'Research/PilotRuns/Gate12R_ProcessReuse_5pct/v4/budget-storage-projection.json'; sha256 = 'cca76d3206311119b3b81fd72d162f8425a2657f02d85a906a5fc91a35690e1f' }
    memoryAmendment = [ordered]@{ path = 'Research/Gate12R_Memory_Gate_Amendment.v1.json'; sha256 = '69a128f8c41c2e0fad1453daed0729f752bb58b77d300f736a758f5121815c20' }
}
$resolved = @{}
foreach ($key in $bound.Keys) { $resolved[$key] = Assert-G13RBoundFile -ProjectPath $ProjectPath -RelativePath $bound[$key].path -ExpectedSha256 $bound[$key].sha256 -Role $key }

$implementation = [ordered]@{
    module = [ordered]@{ path = 'Research/Gate13RSerial10pctFormalPreparationV2.psm1'; sha256 = Get-G13RLowerSha256 (Join-Path $ProjectPath 'Research\Gate13RSerial10pctFormalPreparationV2.psm1') }
    generator = [ordered]@{ path = 'Research/New-Gate13RSerial10pctFormalPreparationV2.ps1'; sha256 = Get-G13RLowerSha256 $PSCommandPath }
    scheduleValidator = [ordered]@{ path = 'Research/Test-Gate13RSerial10pctFormalScheduleV2.ps1'; sha256 = Get-G13RLowerSha256 (Join-Path $ProjectPath 'Research\Test-Gate13RSerial10pctFormalScheduleV2.ps1') }
    orchestrator = [ordered]@{ path = 'Research/Run-Gate13RSerial10pctFormalCampaignV2.ps1'; sha256 = Get-G13RLowerSha256 (Join-Path $ProjectPath 'Research\Run-Gate13RSerial10pctFormalCampaignV2.ps1') }
    blockWrapper = [ordered]@{ path = 'Research/Run-Gate13RSerial10pctFormalBlockV2.ps1'; sha256 = Get-G13RLowerSha256 (Join-Path $ProjectPath 'Research\Run-Gate13RSerial10pctFormalBlockV2.ps1') }
    compileWrapper = [ordered]@{ path = 'Research/Verification/Run-Gate13RCompileV1.ps1'; sha256 = Get-G13RLowerSha256 (Join-Path $ProjectPath 'Research\Verification\Run-Gate13RCompileV1.ps1') }
    readinessValidator = [ordered]@{ path = 'Research/Test-Gate13RSerial10pctReadinessV1.ps1'; sha256 = Get-G13RLowerSha256 (Join-Path $ProjectPath 'Research\Test-Gate13RSerial10pctReadinessV1.ps1') }
    unityCommand = [ordered]@{ path = 'Assets/_Scripts/Research/Editor/Gate13RProcessReuseFormalBatchCommandV1.cs'; sha256 = Get-G13RLowerSha256 (Join-Path $ProjectPath 'Assets\_Scripts\Research\Editor\Gate13RProcessReuseFormalBatchCommandV1.cs') }
    unityCommandDerivation = [ordered]@{ path = 'Research/Gate13R_Formal_Command_Derivation.v3.json'; sha256 = Get-G13RLowerSha256 (Join-Path $ProjectPath 'Research\Gate13R_Formal_Command_Derivation.v3.json') }
}

$matrix = Read-G13RJson $resolved.gate11Matrix
$candidate = Read-G13RJson $resolved.candidateN
$budget = Read-G13RJson $resolved.budgetStorage
$bundle = Read-G13RJson $resolved.gate11Bundle
$campaignCatalog = Read-G13RJson $resolved.campaignCatalog
$presetCatalog = Read-G13RJson $resolved.presetCatalog
$sceneCatalog = Read-G13RJson $resolved.sceneCatalog
$coverage = Read-G13RJson $resolved.coverageManifest
$readiness = Read-G13RJson $resolved.gate12Readiness
if ([int]$matrix.scenarioCount -ne 53 -or [int]$matrix.campaignCount -ne 74 -or [int]$matrix.eligibilityCount -ne 212) { throw 'Gate11R matrix cardinality changed.' }
if (@($matrix.campaigns).Count -ne 74 -or @($matrix.eligibilityEntries).Count -ne 212) { throw 'Gate11R matrix arrays changed.' }
if ([int]$bundle.scenarioCount -ne 53 -or [int]$bundle.campaignCount -ne 74 -or [int]$bundle.eligibilityCount -ne 212) { throw 'Gate11R bundle cardinality changed.' }
if ([int]$campaignCatalog.campaignCount -ne 74 -or [int]$presetCatalog.presetCount -ne 212 -or [int]$sceneCatalog.sceneCount -ne 53) { throw 'Gate11R Playable catalog cardinality changed.' }
if ([int]$coverage.scenarioCount -ne 53 -or [int]$coverage.campaignCount -ne 74 -or [int]$coverage.presetCount -ne 212 -or $coverage.visualizationOnly -ne $true -or $coverage.timingEvidenceAllowed -ne $false) { throw 'Gate11R Playable coverage boundary changed.' }
if ([string]$readiness.status -ne 'GATE12R-PASSED-GATE13R-NOT-AUTHORIZED') { throw 'Gate12R readiness status changed.' }

$candidateMap = @{}
foreach ($row in @($candidate.cohorts)) {
    $rawN = [int][math]::Ceiling([math]::Pow((1.96 * [double]$row.sigmaUpper / [math]::Log(1.1)), 2))
    $candidateMap[[string]$row.comparisonCohortId] = [int][math]::Max(32, [math]::Ceiling([double]$rawN / 4.0) * 4)
}
if ($candidateMap['four-algorithm-shared-goal-v1'] -ne 144 -or $candidateMap['per-agent-heterogeneous-goal-v1'] -ne 204 -or $candidateMap['grouped-field-heterogeneous-goal-v1'] -ne 108) { throw 'Gate12R-derived 10pct uncapped candidate values changed.' }
$presetMap = @{}
foreach ($entry in @($matrix.eligibilityEntries)) { $presetMap[([string]$entry.campaignId + '|' + [string]$entry.algorithmId)] = $entry }

$scheduleWriter = New-Object IO.StreamWriter($paths.schedule, $false, (New-Object Text.UTF8Encoding($false, $true)))
$scheduleWriter.NewLine = "`n"
$campaignRows = New-Object Collections.Generic.List[object]
$positionBalance = @{}
$globalBlock = 0
$totalSamples = 0
try {
    $campaignOrdinal = 0
    foreach ($campaign in @($matrix.campaigns)) {
        $campaignOrdinal++
        $cohort = [string]$campaign.comparisonCohortId
        $blockCount = [int]$candidateMap[$cohort]
        $algorithms = @($campaign.eligibleAlgorithmIds)
        $williamsRows = @($campaign.williamsRows)
        $expectedAlgorithms = @(Get-G13RExpectedAlgorithms $cohort)
        if ($algorithms.Count -ne $expectedAlgorithms.Count -or $williamsRows.Count -ne $expectedAlgorithms.Count) { throw "Campaign cohort cardinality mismatch: $($campaign.campaignId)" }
        $campaignStart = $globalBlock + 1
        $presetRows = New-Object Collections.Generic.List[object]
        foreach ($algorithm in $algorithms) {
            $presetKey = [string]$campaign.campaignId + '|' + [string]$algorithm
            if (-not $presetMap.ContainsKey($presetKey)) { throw "Playable preset mapping missing: $presetKey" }
            $preset = $presetMap[$presetKey]
            $presetRows.Add([ordered]@{
                algorithmId = [string]$algorithm
                presetId = [string]$preset.presetId
                presetAssetPath = [string]$preset.presetAssetPath
                presetAssetGuid = [string]$preset.presetAssetGuid
                presetSha256 = [string]$preset.presetSha256
            })
        }
        for ($blockOrdinal = 1; $blockOrdinal -le $blockCount; $blockOrdinal++) {
            $globalBlock++
            $rowIndex = ($blockOrdinal - 1) % $williamsRows.Count
            $rowAlgorithms = @($williamsRows[$rowIndex].algorithms)
            $blockId = 'g13rs2-c{0:d2}-b{1:d4}' -f $campaignOrdinal, $blockOrdinal
            $campaignDirectory = 'campaigns/c{0:d2}-{1}' -f $campaignOrdinal, [string]$campaign.campaignId
            $blockOutput = "$campaignDirectory/blocks/b$($blockOrdinal.ToString('d4'))"
            $entries = New-Object Collections.Generic.List[object]
            for ($index = 0; $index -lt $rowAlgorithms.Count; $index++) {
                $position = $index + 1
                $algorithm = [string]$rowAlgorithms[$index]
                $predecessor = if ($index -eq 0) { 'NONE' } else { [string]$rowAlgorithms[$index - 1] }
                $slug = Get-G13RAlgorithmSlug $algorithm
                $runId = "$blockId-p$($position.ToString('d2'))-$slug"
                $child = "runs/p$($position.ToString('d2'))-$slug"
                $entries.Add([ordered]@{
                    position = $position
                    algorithmId = $algorithm
                    predecessorAlgorithmId = $predecessor
                    runId = $runId
                    childDirectory = $child
                    sampleOutputRelativePath = "$blockOutput/$child"
                })
                $positionKey = "$cohort|$algorithm|$position"
                if (-not $positionBalance.ContainsKey($positionKey)) { $positionBalance[$positionKey] = 0 }
                $positionBalance[$positionKey]++
                $totalSamples++
            }
            $record = [ordered]@{
                schemaVersion = 1
                scheduleKind = 'gate13r-serial-10pct-formal-williams-block-schedule-record-v2'
                globalBlockOrdinal = $globalBlock
                campaignOrdinal = $campaignOrdinal
                campaignId = [string]$campaign.campaignId
                scenarioId = [string]$campaign.scenarioId
                scenarioRelativePath = [string]$campaign.scenarioRelativePath
                scenarioSha256 = [string]$campaign.scenarioSha256
                scenarioFingerprintSha256 = [string]$campaign.scenarioFingerprintSha256
                comparisonCohortId = $cohort
                campaignBlockOrdinal = $blockOrdinal
                williamsRowIndex = $rowIndex
                blockId = $blockId
                outputRelativePath = $blockOutput
                expectedSampleCount = $entries.Count
                sceneAssetPath = [string]$campaign.sceneAssetPath
                profileAssetPath = [string]$campaign.profileAssetPath
                profileAssetGuid = [string]$campaign.profileAssetGuid
                profileSha256 = [string]$campaign.profileSha256
                entries = $entries.ToArray()
            }
            $line = ($record | ConvertTo-Json -Depth 20 -Compress).Replace("`r", '').Replace("`n", '')
            $scheduleWriter.WriteLine($line)
        }
        $campaignRows.Add([ordered]@{
            campaignOrdinal = $campaignOrdinal
            campaignId = [string]$campaign.campaignId
            scenarioId = [string]$campaign.scenarioId
            scenarioRelativePath = [string]$campaign.scenarioRelativePath
            scenarioSha256 = [string]$campaign.scenarioSha256
            scenarioFingerprintSha256 = [string]$campaign.scenarioFingerprintSha256
            comparisonCohortId = $cohort
            eligibleAlgorithmIds = $algorithms
            williamsRows = $williamsRows
            blockCount = $blockCount
            sampleCount = $blockCount * $algorithms.Count
            globalBlockStartOrdinal = $campaignStart
            globalBlockEndOrdinal = $globalBlock
            sceneAssetPath = [string]$campaign.sceneAssetPath
            profileAssetPath = [string]$campaign.profileAssetPath
            profileAssetGuid = [string]$campaign.profileAssetGuid
            profileSha256 = [string]$campaign.profileSha256
            algorithmPresets = $presetRows.ToArray()
        })
    }
}
finally { $scheduleWriter.Dispose() }

if ($globalBlock -ne 11160 -or $totalSamples -ne 31536) { throw "Generated serial 10pct formal schedule cardinality mismatch: blocks=$globalBlock samples=$totalSamples" }
$scheduleSha256 = Get-G13RLowerSha256 $paths.schedule
$positionRows = New-Object Collections.Generic.List[object]
foreach ($key in @($positionBalance.Keys | Sort-Object)) {
    $parts = $key.Split('|')
    $positionRows.Add([ordered]@{ comparisonCohortId = $parts[0]; algorithmId = $parts[1]; position = [int]$parts[2]; count = [int]$positionBalance[$key] })
}
$scheduleManifest = [ordered]@{
    schemaVersion = 1
    manifestKind = 'gate13r-serial-10pct-formal-williams-block-schedule-manifest-v2'
    formalDesignId = 'gate13r-one-fresh-unity-process-per-williams-block-10pct-uncapped-serial-v2'
    scheduleRelativePath = 'Research/Gate13R_Serial_10pct_Formal_Williams_Block_Schedule.v2.jsonl'
    scheduleSha256 = $scheduleSha256
    scheduleRawBytes = (Get-Item -LiteralPath $paths.schedule).Length
    blockRecordCount = $globalBlock
    sampleIdentityCount = $totalSamples
    campaignCount = 74
    positionBalance = $positionRows.ToArray()
    formalExecutionAuthorized = $false
    formalCampaignExecuted = $false
}
Write-G13RUtf8NoBomJson -Path $paths.scheduleManifest -Value $scheduleManifest -Depth 30
$scheduleManifestSha256 = Get-G13RLowerSha256 $paths.scheduleManifest

$unityPath = 'H:\UnityEditor\2022.3.30f1c1\Editor\Unity.exe'
if (-not (Test-Path -LiteralPath $unityPath -PathType Leaf)) { throw 'Frozen Unity executable is missing.' }
$config = [ordered]@{
    schemaVersion = 1
    configKind = 'gate13r-strict-serial-10pct-formal-campaign-config-v2'
    configId = 'gate13r-formal-campaign-10pct-uncapped-strict-serial-v2'
    formalDesignId = 'gate13r-one-fresh-unity-process-per-williams-block-10pct-uncapped-serial-v2'
    executionDesignId = 'gate10r-one-fresh-unity-process-per-williams-block-5pct-v1'
    formalCampaignConfigured = $true
    formalExecutionAuthorized = $false
    formalRootCreated = $false
    formalTimingExecuted = $false
    formalRoot = [ordered]@{
        relativePath = 'Research/FormalRuns/Gate13R_Serial_10pct/v2'
        resolvedAtPreparation = $formalRoot.Replace('\', '/')
        createNewRequired = $true
        mustBeAbsentBeforeAuthorizedLaunch = $true
    }
    totals = [ordered]@{
        scenarioCount = 53
        campaignCount = 74
        eligibleCellCount = 212
        blockProcessCount = 11160
        sampleCount = 31536
    }
    cohortDesign = @(
        [ordered]@{ comparisonCohortId = 'four-algorithm-shared-goal-v1'; campaignCount = 32; blocksPerCampaign = 144; blockProcessCount = 4608; samplesPerBlock = 4; sampleCount = 18432 },
        [ordered]@{ comparisonCohortId = 'per-agent-heterogeneous-goal-v1'; campaignCount = 21; blocksPerCampaign = 204; blockProcessCount = 4284; samplesPerBlock = 2; sampleCount = 8568 },
        [ordered]@{ comparisonCohortId = 'grouped-field-heterogeneous-goal-v1'; campaignCount = 21; blocksPerCampaign = 108; blockProcessCount = 2268; samplesPerBlock = 2; sampleCount = 4536 }
    )
    precision = [ordered]@{
        policyId = 'two-sided-95pct-ci-relative-half-width-10pct-uncapped-v1'
        confidenceLevel = 0.95
        criticalValue = 1.96
        relativeHalfWidth = 0.10
        logHalfWidth = 0.09531017980432493
        minimumBlocks = 32
        cycleMultiple = 4
        hardCap = $null
    }
    memory = [ordered]@{
        policyId = 'gate12r-sample-128mib-block-128mib-per-sample-v1'
        blockManagedLimitFormulaId = 'checked-sample-limit-times-expected-sample-count-v1'
        maximumSampleRetainedManagedGrowthBytes = 134217728L
        maximumBlockRetainedManagedGrowthBytesPerSample = 134217728L
        twoSampleBlockRetainedManagedGrowthLimitBytes = 268435456L
        fourSampleBlockRetainedManagedGrowthLimitBytes = 536870912L
        maximumBlockWorkingSetGrowthBytes = 536870912L
        maximumBlockPrivateMemoryGrowthBytes = 536870912L
    }
    storage = [ordered]@{
        projectedRawBytesWithSafety = 43885575792L
        reserveBytes = 42949672960L
        minimumLaunchFreeBytes = 86835248752L
        originalByteComparisonRequired = $true
        freshLaunchRecheckRequired = $true
        gate12SnapshotCanAuthorizeLaunch = $false
    }
    runtimeProjection = [ordered]@{
        serialP50Seconds = 233390.8875456
        serialP95Seconds = 302055.2033292
        serialP50Hours = 64.830802096
        serialP95Hours = 83.904223147
        serialP95Days = 3.49600929779167
        recommendedMaintenanceWindowHours = 96
        hardWallClockLimitHours = $null
        estimateOnly = $true
    }
    processSemantics = [ordered]@{
        maximumConcurrentUnityEditorProcesses = 1
        laneCount = 1
        oneFreshUnityEditorProcessPerCompleteWilliamsBlock = $true
        maximumWilliamsBlocksPerUnityProcess = 1
        oneOccurrencePerEligibleAlgorithmPerProcess = $true
        crossBlockReuseAllowed = $false
        crossCampaignReuseAllowed = $false
        perSampleCompleteResetRequired = $true
        parallelFallbackAllowed = $false
        mixedTopologyAllowed = $false
    }
    failurePolicy = [ordered]@{
        failClosed = $true
        stopAfterFirstFailedSample = $true
        stopAfterFirstFailedBlock = $true
        automaticRetryAllowed = $false
        automaticResumeAllowed = $false
        partialBlockEligible = $false
        partialAttemptMergeAllowed = $false
    }
    headlessTiming = [ordered]@{
        headless = $true
        loadPlayableScene = $false
        render = $false
        obs = $false
        playableBundleVisualizationOnly = $true
    }
    licensing = [ordered]@{
        serialAssignmentRequired = $true
        noValidLicensePattern = 'No valid Unity Editor license found'
        inactiveHeadlessPattern = 'License is not active (com.unity.editor.headless)'
        accessTokenWarningIsDiagnosticOnlyAfterSerialAssignmentAndExitZero = $true
    }
    schedule = [ordered]@{
        relativePath = 'Research/Gate13R_Serial_10pct_Formal_Williams_Block_Schedule.v2.jsonl'
        sha256 = $scheduleSha256
        rawBytes = (Get-Item -LiteralPath $paths.schedule).Length
        manifestRelativePath = 'Research/Gate13R_Serial_10pct_Formal_Williams_Block_Schedule_Manifest.v2.json'
        manifestSha256 = $scheduleManifestSha256
        blockRecordCount = $globalBlock
        sampleIdentityCount = $totalSamples
    }
    bindings = [ordered]@{
        authorizationRelativePath = $bound.authorization.path
        authorizationSha256 = $bound.authorization.sha256
        specificationRelativePath = $bound.specification.path
        specificationSha256 = $bound.specification.sha256
        testDesignRelativePath = $bound.testDesign.path
        testDesignSha256 = $bound.testDesign.sha256
        amendmentRelativePath = $bound.amendment.path
        amendmentSha256 = $bound.amendment.sha256
        gate11BundleManifestSha256 = $bound.gate11Bundle.sha256
        gate11MatrixSha256 = $bound.gate11Matrix.sha256
        gate12ReadinessCheckpointSha256 = $bound.gate12Readiness.sha256
        candidateNFormalSha256 = $bound.candidateN.sha256
        budgetStorageProjectionSha256 = $bound.budgetStorage.sha256
        memoryGateAmendmentSha256 = $bound.memoryAmendment.sha256
        serialReadinessProvenanceSha256 = $bound.serialReadinessProvenance.sha256
        serialEvidenceAuditSha256 = $bound.serialEvidenceAudit.sha256
    }
    implementation = [ordered]@{
        moduleRelativePath = $implementation.module.path
        moduleSha256 = $implementation.module.sha256
        generatorRelativePath = $implementation.generator.path
        generatorSha256 = $implementation.generator.sha256
        scheduleValidatorRelativePath = $implementation.scheduleValidator.path
        scheduleValidatorSha256 = $implementation.scheduleValidator.sha256
        orchestratorRelativePath = $implementation.orchestrator.path
        orchestratorSha256 = $implementation.orchestrator.sha256
        blockWrapperRelativePath = $implementation.blockWrapper.path
        blockWrapperSha256 = $implementation.blockWrapper.sha256
        readinessValidatorRelativePath = $implementation.readinessValidator.path
        readinessValidatorSha256 = $implementation.readinessValidator.sha256
        unityCommandRelativePath = $implementation.unityCommand.path
        unityCommandSha256 = $implementation.unityCommand.sha256
        unityExecutablePath = $unityPath.Replace('\', '/')
        unityExecutableSha256 = Get-G13RLowerSha256 $unityPath
        unityProductVersion = '2022.3.30f1c1_a6dc00fbe362'
    }
    environment = [ordered]@{
        requiredPowerSchemeGuid = '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c'
        requireAcOnline = $true
        minimumFreePhysicalMemoryBytes = 4294967296L
        maximumMeanCpuLoadPercent = 50
        temperatureUnavailablePolicy = 'record-unavailable-controlled-warmup-balanced-order-v1'
    }
    playable = [ordered]@{
        sceneCount = 53
        profileCount = 74
        presetCount = 212
        coverageManifestSha256 = $bound.coverageManifest.sha256
        timingEvidenceAllowed = $false
    }
    campaigns = $campaignRows.ToArray()
}
Write-G13RUtf8NoBomJson -Path $paths.config -Value $config -Depth 60
$configSha256 = Get-G13RLowerSha256 $paths.config

$provenance = [ordered]@{
    schemaVersion = 1
    provenanceKind = 'gate13r-strict-serial-10pct-formal-preparation-provenance-v2'
    formalDesignId = 'gate13r-one-fresh-unity-process-per-williams-block-10pct-uncapped-serial-v2'
    preparationAuthorization = $bound.authorization
    frozenInputs = $bound
    implementation = $implementation
    formalConfig = [ordered]@{ relativePath = 'Research/Gate13R_Serial_10pct_Formal_Campaign_Config.v2.json'; sha256 = $configSha256 }
    schedule = [ordered]@{ relativePath = 'Research/Gate13R_Serial_10pct_Formal_Williams_Block_Schedule.v2.jsonl'; sha256 = $scheduleSha256; manifestRelativePath = 'Research/Gate13R_Serial_10pct_Formal_Williams_Block_Schedule_Manifest.v2.json'; manifestSha256 = $scheduleManifestSha256 }
    sourceCandidateRows = @($candidate.cohorts)
    sourceBudgetRows = @($budget.rows)
    gate12SnapshotAvailableFreeBytes = [long]$budget.availableFreeBytes
    gate12SnapshotCanAuthorizeFormalLaunch = $false
    retainedSupersededParallelEvidence = @(
        'Research/Gate13R_36h_10pct_4Lane_v16_Failed_Checkpoint.md',
        'Research/Gate13R_48h_10pct_3Lane_v1_External_Failure_Receipt.json'
    )
    deterministicGeneration = $true
    formalRootCreated = $false
    formalExecutionReceiptCreated = $false
    formalCampaignExecuted = $false
}
Write-G13RUtf8NoBomJson -Path $paths.provenance -Value $provenance -Depth 60
$provenanceSha256 = Get-G13RLowerSha256 $paths.provenance

$summary = [ordered]@{
    schemaVersion = 1
    summaryKind = 'gate13r-strict-serial-10pct-formal-preparation-generation-summary-v2'
    savedAtUtc = [DateTime]::UtcNow.ToString('o')
    outputDirectory = $OutputDirectory
    scheduleSha256 = $scheduleSha256
    scheduleManifestSha256 = $scheduleManifestSha256
    configSha256 = $configSha256
    provenanceSha256 = $provenanceSha256
    campaignCount = 74
    blockRecordCount = $globalBlock
    sampleIdentityCount = $totalSamples
    formalRootExists = Test-Path -LiteralPath $formalRoot
    formalExecutionReceiptCreated = $false
    formalCampaignExecuted = $false
    passed = $true
}
Write-G13RUtf8NoBomJson -Path $paths.summary -Value $summary -Depth 20
Write-Host "Gate13R strict-serial 10pct non-executing artifacts generated: 74 campaigns / $globalBlock blocks / $totalSamples samples." -ForegroundColor Green
exit 0
