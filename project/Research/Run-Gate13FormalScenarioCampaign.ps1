[CmdletBinding(DefaultParameterSetName = 'ValidationOnly')]
param(
    [string]$ProjectPath,
    [string]$ConfigPath,
    [Parameter(Mandatory = $true)][ValidateRange(1, 74)][int]$CampaignOrdinal,
    [Parameter(Mandatory = $true, ParameterSetName = 'ValidationOnly')][switch]$ValidationOnly,
    [Parameter(Mandatory = $true, ParameterSetName = 'Execute')][switch]$Execute,
    [Parameter(Mandatory = $true, ParameterSetName = 'Execute')][string]$ExecutionAuthorizationPath
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0
$scriptDirectory = Split-Path -Parent $MyInvocation.MyCommand.Path
if ([string]::IsNullOrWhiteSpace($ProjectPath)) { $ProjectPath = [System.IO.Path]::GetFullPath((Join-Path $scriptDirectory '..')) }
else { $ProjectPath = [System.IO.Path]::GetFullPath($ProjectPath) }
if ([string]::IsNullOrWhiteSpace($ConfigPath)) { $ConfigPath = Join-Path $ProjectPath 'Research\Gate13_Formal_Campaign_Config.v1.json' }
elseif (-not [System.IO.Path]::IsPathRooted($ConfigPath)) { $ConfigPath = Join-Path $ProjectPath $ConfigPath }
$ConfigPath = [System.IO.Path]::GetFullPath($ConfigPath)

$modulePath = Join-Path $scriptDirectory 'Gate13FormalPreparation.psm1'
$workloadRunnerPath = Join-Path $scriptDirectory 'Run-PlanningWorkload.ps1'
Import-Module $modulePath -Force
if (-not (Test-Path -LiteralPath $ConfigPath -PathType Leaf)) { throw "Gate 13 formal config not found: $ConfigPath" }
if (-not (Test-Path -LiteralPath $workloadRunnerPath -PathType Leaf)) { throw "Planning workload runner not found: $workloadRunnerPath" }
$config = Read-Gate13Json -Path $ConfigPath
$configCheck = Test-Gate13FormalConfig -ProjectPath $ProjectPath -Config $config -ConfigPath $ConfigPath
if (-not $configCheck.passed) { throw "Gate 13 config validation failed: $($configCheck.errors -join '; ')" }
$campaign = @($config.campaigns | Where-Object { [int]$_.ordinal -eq $CampaignOrdinal })
if ($campaign.Count -ne 1) { throw "Config does not contain exactly one campaign ordinal $CampaignOrdinal." }
$campaign = $campaign[0]
$schedule = New-Gate13WilliamsSchedule -CampaignId $campaign.campaignId -ComparisonCohortId $campaign.comparisonCohortId -Blocks ([int]$campaign.blockCount)
if ([int]$schedule.sampleCount -ne [int]$campaign.sampleCount -or
    [int]$schedule.completeBalanceCycleCount -ne [int]$campaign.completeBalanceCycleCount -or
    [string]$schedule.canonicalScheduleSha256 -ne [string]$campaign.canonicalScheduleSha256 -or
    -not $schedule.positionBalanced -or -not $schedule.orderedPredecessorBalanced) {
    throw "Campaign schedule contract mismatch for ordinal $CampaignOrdinal."
}

$scenarioPath = [System.IO.Path]::GetFullPath((Join-Path $ProjectPath ([string]$campaign.scenarioRelativePath).Replace('/', '\')))
$bundleRoot = [System.IO.Path]::GetFullPath((Join-Path $ProjectPath 'Research\FormalScenarios\v1'))
if (-not (Test-Gate13PathWithin -CandidatePath $scenarioPath -RootPath $bundleRoot)) { throw "Scenario path escapes the retained bundle: $scenarioPath" }
if ((Get-Gate13LowerSha256 -Path $scenarioPath) -ne [string]$campaign.scenarioSourceSha256) { throw "Scenario source hash mismatch: $scenarioPath" }
$formalRoot = [System.IO.Path]::GetFullPath((Join-Path $ProjectPath ([string]$config.output.rootRelativePath).Replace('/', '\')))
$campaignDirectory = [System.IO.Path]::GetFullPath((Join-Path $formalRoot ([string]$campaign.outputRelativePath).Replace('/', '\')))
if (-not (Test-Gate13PathWithin -CandidatePath $campaignDirectory -RootPath $formalRoot)) { throw 'Campaign output path escapes the formal root.' }

if ($ValidationOnly) {
    [pscustomobject][ordered]@{
        schemaVersion = 1
        mode = 'validation-only'
        campaignOrdinal = $CampaignOrdinal
        campaignId = $campaign.campaignId
        scenarioId = $campaign.scenarioId
        comparisonCohortId = $campaign.comparisonCohortId
        blockCount = [int]$campaign.blockCount
        sampleCount = [int]$campaign.sampleCount
        canonicalScheduleSha256 = $schedule.canonicalScheduleSha256
        scenarioSourceSha256 = Get-Gate13LowerSha256 -Path $scenarioPath
        outputDirectory = $campaignDirectory
        formalRootExists = Test-Path -LiteralPath $formalRoot
        unityInvoked = $false
        outputCreated = $false
        formalCampaignStartAllowed = $false
        passed = -not (Test-Path -LiteralPath $formalRoot)
    } | ConvertTo-Json -Depth 8
    if (Test-Path -LiteralPath $formalRoot) { Write-Error 'Validation-only refuses to pass while the Gate 13 formal root exists.'; exit 1 }
    exit 0
}

if (-not $Execute) { throw 'Choose exactly one mode: -ValidationOnly or -Execute.' }
if (-not [System.IO.Path]::IsPathRooted($ExecutionAuthorizationPath)) { $ExecutionAuthorizationPath = Join-Path $ProjectPath $ExecutionAuthorizationPath }
$ExecutionAuthorizationPath = [System.IO.Path]::GetFullPath($ExecutionAuthorizationPath)
if (-not (Test-Path -LiteralPath $ExecutionAuthorizationPath -PathType Leaf)) { throw "Execution authorization receipt not found: $ExecutionAuthorizationPath" }
$authorization = Read-Gate13Json -Path $ExecutionAuthorizationPath
$configSha256 = Get-Gate13LowerSha256 -Path $ConfigPath
$amendmentPath = Join-Path $ProjectPath ([string]$config.frozenInputs.gate13Amendment.relativePath).Replace('/', '\')
$amendmentSha256 = Get-Gate13LowerSha256 -Path $amendmentPath
$authorizationCheck = Test-Gate13ExecutionAuthorization -Authorization $authorization -ExpectedConfigSha256 $configSha256 -ExpectedAmendmentSha256 $amendmentSha256 -ExpectedOutputRootRelativePath ([string]$config.output.rootRelativePath)
if (-not $authorizationCheck.passed) { throw "Gate 13 execution authorization is invalid: $($authorizationCheck.errors -join '; ')" }
if (-not (Test-Path -LiteralPath $formalRoot -PathType Container)) { throw 'Formal root must be created by the authorized top-level orchestrator before a scenario campaign starts.' }
$checkpointPath = Join-Path $formalRoot ([string]$config.checkpoint.relativePath).Replace('/', '\')
if (-not (Test-Path -LiteralPath $checkpointPath -PathType Leaf)) { throw 'Top-level formal checkpoint is missing.' }
$checkpoint = Read-Gate13Json -Path $checkpointPath
if ([string]$checkpoint.configSha256 -ne $configSha256 -or [string]$checkpoint.executionAuthorizationSha256 -ne (Get-Gate13LowerSha256 -Path $ExecutionAuthorizationPath)) { throw 'Top-level checkpoint identity mismatch.' }
if ([int]$checkpoint.currentCampaignOrdinal -ne $CampaignOrdinal -or [string]$checkpoint.status -ne 'running-campaign') { throw 'Top-level checkpoint does not authorize this campaign ordinal.' }
if (Test-Path -LiteralPath $campaignDirectory) { throw "Campaign output already exists; refusing to overwrite: $campaignDirectory" }
$campaignSummaryPath = $campaignDirectory + '.summary.json'
if (Test-Path -LiteralPath $campaignSummaryPath) { throw "Campaign summary already exists; refusing to overwrite: $campaignSummaryPath" }
$unityProcesses = @(Get-Process -Name Unity -ErrorAction SilentlyContinue)
$unityLockPath = Join-Path $ProjectPath 'Temp\UnityLockfile'
if ($unityProcesses.Count -gt 0 -or (Test-Path -LiteralPath $unityLockPath)) { throw 'Close Unity and clear the project lock before a formal scenario campaign.' }
$unityPath = [System.IO.Path]::GetFullPath(([string]$config.unity.executablePath).Replace('/', '\'))
if ((Get-Gate13LowerSha256 -Path $unityPath) -ne [string]$config.unity.executableSha256) { throw 'Unity executable hash mismatch.' }

$runsDirectory = Join-Path $campaignDirectory 'runs'
New-Item -ItemType Directory -Path $runsDirectory -Force | Out-Null
$startedAtUtc = [DateTime]::UtcNow
$executedSchedule = New-Object System.Collections.Generic.List[object]
$expectedScenarioId = $null
$expectedFingerprint = $null
$expectedCanonicalSha256 = $null
$expectedFairnessProtocolId = $null
$expectedFairnessProtocolSha256 = $null
$expectedWorkloadSpecificationSha256 = $null
$expectedUnityVersion = $null
$profiles = [ordered]@{}

foreach ($entry in @($schedule.entries)) {
    $childDirectory = Join-Path $campaignDirectory ([string]$entry.directory).Replace('/', '\')
    Write-Host "[campaign $CampaignOrdinal/74 block $($entry.block)/$($campaign.blockCount) position $($entry.position)/$($campaign.algorithmCount)] $($entry.algorithmId) -> $($entry.runId)"
    & powershell -NoProfile -ExecutionPolicy Bypass -File $workloadRunnerPath `
        -ScenarioPath $scenarioPath `
        -OutputDirectory $childDirectory `
        -RunId $entry.runId `
        -Algorithm $entry.algorithmId `
        -UnityPath $unityPath `
        -ProjectPath $ProjectPath
    if ($LASTEXITCODE -ne 0) { throw "Formal child workload failed: $($entry.runId)" }

    $childManifestPath = Join-Path $childDirectory 'manifest.json'
    if (-not (Test-Path -LiteralPath $childManifestPath -PathType Leaf)) { throw "Child manifest is missing: $childManifestPath" }
    $childManifest = Read-Gate13Json -Path $childManifestPath
    $resultPath = Join-Path $childDirectory ([string]$childManifest.workloadResultFile)
    $canonicalPath = Join-Path $childDirectory ([string]$childManifest.canonicalScenarioFile)
    $operationsPath = Join-Path $childDirectory ([string]$childManifest.operationsJsonlFile)
    foreach ($requiredPath in @($resultPath, $canonicalPath, $operationsPath)) {
        if (-not (Test-Path -LiteralPath $requiredPath -PathType Leaf)) { throw "Child artifact is missing: $requiredPath" }
    }
    $result = Read-Gate13Json -Path $resultPath
    if ([int]$childManifest.schemaVersion -ne 2 -or $childManifest.completed -ne $true -or $childManifest.runId -ne $entry.runId -or $childManifest.algorithmId -ne $entry.algorithmId) { throw "Child manifest identity invalid: $childManifestPath" }
    if ($result.completed -ne $true -or $result.runId -ne $entry.runId -or $result.algorithmId -ne $entry.algorithmId -or [int]$result.fairnessSchemaVersion -ne 1) { throw "Child result identity invalid: $resultPath" }
    if ($result.comparisonCohortId -ne $campaign.comparisonCohortId -or $childManifest.comparisonCohortId -ne $campaign.comparisonCohortId -or $result.dynamicCostIncludesAllRepairsAndPostEventPlans -ne $true) { throw "Child fairness/cohort boundary invalid: $resultPath" }
    if ((Get-Gate13LowerSha256 -Path $resultPath) -ne $childManifest.workloadResultSha256 -or
        (Get-Gate13LowerSha256 -Path $canonicalPath) -ne $childManifest.canonicalScenarioSha256 -or
        (Get-Gate13LowerSha256 -Path $operationsPath) -ne $childManifest.operationsJsonlSha256) { throw "Child artifact hash validation failed: $childManifestPath" }
    if ($childManifest.scenarioSourceSha256 -ne $campaign.scenarioSourceSha256) { throw "Child scenario source hash mismatch: $childManifestPath" }

    if ($null -eq $expectedFingerprint) {
        $expectedScenarioId = $result.scenarioId
        $expectedFingerprint = $result.scenarioFingerprintSha256
        $expectedCanonicalSha256 = $childManifest.canonicalScenarioSha256
        $expectedFairnessProtocolId = $result.fairnessProtocolId
        $expectedFairnessProtocolSha256 = $result.fairnessProtocolSha256
        $expectedWorkloadSpecificationSha256 = $result.workloadSpecificationSha256
        $expectedUnityVersion = $childManifest.unityVersion
    } elseif ($result.scenarioId -ne $expectedScenarioId -or
              $result.scenarioFingerprintSha256 -ne $expectedFingerprint -or
              $childManifest.canonicalScenarioSha256 -ne $expectedCanonicalSha256 -or
              $result.fairnessProtocolId -ne $expectedFairnessProtocolId -or
              $result.fairnessProtocolSha256 -ne $expectedFairnessProtocolSha256 -or
              $result.workloadSpecificationSha256 -ne $expectedWorkloadSpecificationSha256 -or
              $childManifest.unityVersion -ne $expectedUnityVersion) {
        throw "Child scenario/protocol/workload/Unity identity differs: $childManifestPath"
    }
    $profiles[$entry.algorithmId] = [ordered]@{
        specificationId = $result.algorithmSpecificationId
        specificationRelativePath = $result.algorithmSpecificationRelativePath
        specificationSha256 = $result.algorithmSpecificationSha256
        implementationRelativePath = $result.algorithmImplementationRelativePath
        implementationSha256 = $result.algorithmImplementationSha256
        plannerStateModelId = $result.plannerStateModelId
        processedWorkUnit = $result.processedWorkUnit
        nativeMetricsSemanticsId = $result.nativeMetricsSemanticsId
    }
    $executedSchedule.Add([pscustomobject][ordered]@{
        block = [int]$entry.block
        position = [int]$entry.position
        algorithmId = [string]$entry.algorithmId
        runId = [string]$entry.runId
        directory = [string]$entry.directory
        manifestFile = ([string]$entry.directory + '/manifest.json')
        manifestSha256 = Get-Gate13LowerSha256 -Path $childManifestPath
        workloadResultFile = ([string]$entry.directory + '/' + [string]$childManifest.workloadResultFile)
        workloadResultSha256 = [string]$childManifest.workloadResultSha256
        operationsJsonlSha256 = [string]$childManifest.operationsJsonlSha256
        planOperationCount = [int]$result.planOperationCount
        repairOperationCount = [int]$result.repairOperationCount
        succeededPlanCount = [int]$result.succeededPlanCount
        budgetExceededOperationCount = [int]$result.budgetExceededOperationCount
        completed = $true
    })
}

if ($expectedScenarioId -ne $campaign.scenarioId -or $expectedFingerprint -ne $campaign.scenarioFingerprintSha256 -or $expectedCanonicalSha256 -ne $campaign.scenarioCanonicalSha256) { throw 'Completed campaign scenario identity differs from frozen config.' }
$canonicalScenarioPath = Join-Path $campaignDirectory (([string]$schedule.entries[0].directory).Replace('/', '\') + '\scenario.canonical.json')
$canonicalScenario = Read-Gate13Json -Path $canonicalScenarioPath
$manifestPath = Join-Path $campaignDirectory 'campaign-manifest.json'
$manifest = [ordered]@{
    schemaVersion = 1
    campaignKind = 'gate13-formal-microbenchmark-v1'
    campaignOrdinal = $CampaignOrdinal
    campaignId = $campaign.campaignId
    configId = $config.configId
    configSha256 = $configSha256
    amendmentSha256 = $amendmentSha256
    executionAuthorizationId = $authorization.authorizationId
    executionAuthorizationSha256 = Get-Gate13LowerSha256 -Path $ExecutionAuthorizationPath
    comparisonCohortId = $campaign.comparisonCohortId
    fairnessProtocolId = $expectedFairnessProtocolId
    fairnessProtocolSha256 = $expectedFairnessProtocolSha256
    workloadSpecificationSha256 = $expectedWorkloadSpecificationSha256
    scenarioId = $expectedScenarioId
    scenarioSourceRelativePath = $campaign.scenarioRelativePath
    scenarioSourceSha256 = $campaign.scenarioSourceSha256
    scenarioFingerprintSha256 = $expectedFingerprint
    canonicalScenarioSha256 = $expectedCanonicalSha256
    initializationBudgetMilliseconds = $canonicalScenario.initializationBudgetMilliseconds
    defaultPlanBudgetMilliseconds = $canonicalScenario.defaultPlanBudgetMilliseconds
    defaultRepairBudgetMilliseconds = $canonicalScenario.defaultRepairBudgetMilliseconds
    effectiveEventRepairBudgetsMilliseconds = @($canonicalScenario.scheduledChanges | ForEach-Object repairBudgetMilliseconds)
    unityVersion = $expectedUnityVersion
    unityExecutable = $unityPath.Replace('\', '/')
    unityExecutableSha256 = $config.unity.executableSha256
    orderDesign = 'williams-balanced-v1'
    canonicalAlgorithmOrder = @($schedule.canonicalAlgorithmOrder)
    canonicalScheduleSha256 = $schedule.canonicalScheduleSha256
    blockCount = [int]$schedule.blockCount
    algorithmCount = [int]$schedule.algorithmCount
    sampleCount = [int]$schedule.sampleCount
    completeBalanceCycleCount = [int]$schedule.completeBalanceCycleCount
    positionCounts = $schedule.positionCounts
    orderedPredecessorCounts = $schedule.orderedPredecessorCounts
    positionBalanced = $schedule.positionBalanced
    orderedPredecessorBalanced = $schedule.orderedPredecessorBalanced
    algorithmProfiles = $profiles
    schedule = $executedSchedule.ToArray()
    startedAtUtc = $startedAtUtc.ToString('o')
    completedAtUtc = [DateTime]::UtcNow.ToString('o')
    formalCampaign = $true
    completed = $true
}
Write-Gate13Utf8NoBomJson -Path $manifestPath -Value $manifest -Depth 30
$summary = [ordered]@{
    schemaVersion = 1
    savedAt = (Get-Date).ToString('o')
    outputDirectory = $campaignDirectory
    campaignManifestPath = $manifestPath
    campaignManifestSha256 = Get-Gate13LowerSha256 -Path $manifestPath
    campaignOrdinal = $CampaignOrdinal
    campaignId = $campaign.campaignId
    sampleCount = [int]$schedule.sampleCount
    formalCampaign = $true
    completed = $true
    passed = $true
}
Write-Gate13Utf8NoBomJson -Path $campaignSummaryPath -Value $summary -Depth 12
$summary | ConvertTo-Json -Depth 8
Write-Host "Gate 13 formal scenario campaign completed: $($campaign.campaignId)" -ForegroundColor Green
exit 0
