[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ScenarioPath,
    [ValidateSet('four-algorithm-shared-goal-v1', 'per-agent-heterogeneous-goal-v1', 'grouped-field-heterogeneous-goal-v1')]
    [string]$ComparisonCohortId = 'four-algorithm-shared-goal-v1',
    [ValidateRange(2, 100)]
    [int]$Blocks = 4,
    [string]$CampaignId,
    [string]$OutputDirectory,
    [string]$UnityPath = 'H:\UnityEditor\2022.3.30f1c1\Editor\Unity.exe',
    [string]$ProjectPath
)

$ErrorActionPreference = 'Stop'
$scriptDirectory = Split-Path -Parent $MyInvocation.MyCommand.Path
if ([string]::IsNullOrWhiteSpace($ProjectPath)) {
    $ProjectPath = [System.IO.Path]::GetFullPath((Join-Path $scriptDirectory '..'))
} else {
    $ProjectPath = [System.IO.Path]::GetFullPath($ProjectPath)
}

if (-not [System.IO.Path]::IsPathRooted($ScenarioPath)) { $ScenarioPath = Join-Path (Get-Location).Path $ScenarioPath }
$ScenarioPath = [System.IO.Path]::GetFullPath($ScenarioPath)
if (-not (Test-Path -LiteralPath $ScenarioPath -PathType Leaf)) { throw "Scenario file not found: $ScenarioPath" }
if (-not (Test-Path -LiteralPath $UnityPath -PathType Leaf)) { throw "Unity executable not found: $UnityPath" }
if (-not (Test-Path -LiteralPath (Join-Path $ProjectPath 'Assets') -PathType Container)) { throw "Unity project not found: $ProjectPath" }

$algorithms = switch ($ComparisonCohortId) {
    'four-algorithm-shared-goal-v1' { @('A*-R', 'D*L', 'C-FF', 'IDFF') }
    'per-agent-heterogeneous-goal-v1' { @('A*-R', 'D*L') }
    'grouped-field-heterogeneous-goal-v1' { @('C-FF', 'IDFF') }
    default { throw "Unsupported comparison cohort: $ComparisonCohortId" }
}
$algorithmCount = $algorithms.Count
if ($Blocks % $algorithmCount -ne 0) {
    throw "Blocks must be a positive multiple of the cohort algorithm count ($algorithmCount) so every Williams balance cycle is complete."
}

if ([string]::IsNullOrWhiteSpace($CampaignId)) { $CampaignId = 'fair-' + [DateTime]::UtcNow.ToString('yyyyMMddTHHmmssfffZ') }
if ($CampaignId -notmatch '^[A-Za-z0-9][A-Za-z0-9_.-]{0,95}$') {
    throw 'CampaignId must be 1-96 file-safe ASCII characters and begin with an alphanumeric character.'
}
if ([string]::IsNullOrWhiteSpace($OutputDirectory)) { $OutputDirectory = Join-Path $ProjectPath (Join-Path 'Research\Runs' $CampaignId) }
elseif (-not [System.IO.Path]::IsPathRooted($OutputDirectory)) { $OutputDirectory = Join-Path $ProjectPath $OutputDirectory }
$OutputDirectory = [System.IO.Path]::GetFullPath($OutputDirectory)
$summaryPath = $OutputDirectory + '.summary.json'

if (Test-Path -LiteralPath $OutputDirectory) {
    if (-not (Test-Path -LiteralPath $OutputDirectory -PathType Container)) { throw "Output path is not a directory: $OutputDirectory" }
    if (@(Get-ChildItem -LiteralPath $OutputDirectory -Force).Count -gt 0) { throw "Output directory is not empty; refusing to overwrite: $OutputDirectory" }
}
if (Test-Path -LiteralPath $summaryPath) { throw "Campaign summary already exists; refusing to overwrite: $summaryPath" }

$projectLockPath = Join-Path $ProjectPath 'Temp\UnityLockfile'
if (@(Get-Process -Name Unity -ErrorAction SilentlyContinue).Count -gt 0 -or (Test-Path -LiteralPath $projectLockPath)) {
    throw 'Close Unity before running the fair planning campaign.'
}

function Get-LowerSha256([string]$Path) {
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Write-Utf8NoBomJson([string]$Path, $Value, [int]$Depth = 12) {
    $json = $Value | ConvertTo-Json -Depth $Depth
    $json = $json.Replace("`r`n", "`n").Replace("`r", "`n")
    if (-not $json.EndsWith("`n", [System.StringComparison]::Ordinal)) { $json += "`n" }
    $encoding = New-Object System.Text.UTF8Encoding($false, $true)
    [System.IO.File]::WriteAllText($Path, $json, $encoding)
}

function Get-AlgorithmSlug([string]$Algorithm) {
    switch ($Algorithm) {
        'A*-R' { return 'astar-r' }
        'D*L' { return 'dstar-l' }
        'C-FF' { return 'cff' }
        'IDFF' { return 'idff' }
        default { throw "Unsupported algorithm: $Algorithm" }
    }
}

function Get-WilliamsBaseIndices([int]$Count) {
    if ($Count -lt 2 -or $Count % 2 -ne 0) { throw 'Williams scheduling requires a positive even algorithm count.' }
    $indices = New-Object System.Collections.Generic.List[int]
    $indices.Add(0)
    for ($step = 1; $step -lt $Count; $step++) {
        if ($step % 2 -eq 1) { $indices.Add([int](($step + 1) / 2)) }
        else { $indices.Add([int]($Count - ($step / 2))) }
    }
    return @($indices)
}

function Get-WilliamsRow([string[]]$Items, [int]$RowIndex) {
    $base = @(Get-WilliamsBaseIndices $Items.Count)
    $row = @()
    foreach ($baseIndex in $base) { $row += $Items[($baseIndex + $RowIndex) % $Items.Count] }
    return $row
}

$runnerPath = Join-Path $scriptDirectory 'Run-PlanningWorkload.ps1'
if (-not (Test-Path -LiteralPath $runnerPath -PathType Leaf)) { throw "Planning workload runner not found: $runnerPath" }

$startedAtUtc = [DateTime]::UtcNow
$scenarioSourceSha256 = Get-LowerSha256 $ScenarioPath
$runsDirectory = Join-Path $OutputDirectory 'runs'
New-Item -ItemType Directory -Path $runsDirectory -Force | Out-Null

$schedule = @()
$expectedScenarioId = $null
$expectedFingerprint = $null
$expectedCanonicalSha256 = $null
$expectedFairnessProtocolId = $null
$expectedFairnessProtocolSha256 = $null
$expectedWorkloadSpecificationSha256 = $null
$expectedUnityVersion = $null
$profiles = [ordered]@{}

for ($block = 0; $block -lt $Blocks; $block++) {
    $rowIndex = $block % $algorithmCount
    $row = @(Get-WilliamsRow $algorithms $rowIndex)
    $blockName = 'b{0:D3}' -f ($block + 1)
    for ($position = 0; $position -lt $algorithmCount; $position++) {
        $algorithm = $row[$position]
        $positionName = 'p{0:D2}-{1}' -f ($position + 1), (Get-AlgorithmSlug $algorithm)
        $runId = '{0}-{1}-{2}' -f $CampaignId, $blockName, $positionName
        $childDirectory = Join-Path $runsDirectory (Join-Path $blockName $positionName)
        Write-Host "[block $($block + 1)/$Blocks position $($position + 1)/$algorithmCount] $algorithm -> $runId"

        & powershell -NoProfile -ExecutionPolicy Bypass -File $runnerPath `
            -ScenarioPath $ScenarioPath `
            -OutputDirectory $childDirectory `
            -RunId $runId `
            -Algorithm $algorithm `
            -UnityPath $UnityPath `
            -ProjectPath $ProjectPath
        if ($LASTEXITCODE -ne 0) { throw "Campaign child workload failed: $runId" }

        $manifestPath = Join-Path $childDirectory 'manifest.json'
        if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) { throw "Child manifest is missing: $manifestPath" }
        $manifest = Get-Content -Raw -Encoding UTF8 -LiteralPath $manifestPath | ConvertFrom-Json
        $resultPath = Join-Path $childDirectory $manifest.workloadResultFile
        $canonicalPath = Join-Path $childDirectory $manifest.canonicalScenarioFile
        $operationsPath = Join-Path $childDirectory $manifest.operationsJsonlFile
        foreach ($requiredPath in @($resultPath, $canonicalPath, $operationsPath)) {
            if (-not (Test-Path -LiteralPath $requiredPath -PathType Leaf)) { throw "Child artifact is missing: $requiredPath" }
        }
        $result = Get-Content -Raw -Encoding UTF8 -LiteralPath $resultPath | ConvertFrom-Json
        if ($manifest.schemaVersion -ne 2 -or $manifest.completed -ne $true -or $manifest.runId -ne $runId -or $manifest.algorithmId -ne $algorithm) {
            throw "Child manifest identity is invalid: $manifestPath"
        }
        if ($result.completed -ne $true -or $result.runId -ne $runId -or $result.algorithmId -ne $algorithm -or $result.fairnessSchemaVersion -ne 1) {
            throw "Child result identity or fairness extension is invalid: $resultPath"
        }
        if ($result.comparisonCohortId -ne $ComparisonCohortId -or $manifest.comparisonCohortId -ne $ComparisonCohortId -or $result.dynamicCostIncludesAllRepairsAndPostEventPlans -ne $true) {
            throw "Child comparison cohort or dynamic-cost boundary is invalid: $resultPath"
        }
        if ((Get-LowerSha256 $resultPath) -ne $manifest.workloadResultSha256 -or
            (Get-LowerSha256 $canonicalPath) -ne $manifest.canonicalScenarioSha256 -or
            (Get-LowerSha256 $operationsPath) -ne $manifest.operationsJsonlSha256) {
            throw "Child artifact hash validation failed: $manifestPath"
        }

        if ($null -eq $expectedFingerprint) {
            $expectedScenarioId = $result.scenarioId
            $expectedFingerprint = $result.scenarioFingerprintSha256
            $expectedCanonicalSha256 = $manifest.canonicalScenarioSha256
            $expectedFairnessProtocolId = $result.fairnessProtocolId
            $expectedFairnessProtocolSha256 = $result.fairnessProtocolSha256
            $expectedWorkloadSpecificationSha256 = $result.workloadSpecificationSha256
            $expectedUnityVersion = $manifest.unityVersion
        } elseif ($result.scenarioId -ne $expectedScenarioId -or
                  $result.scenarioFingerprintSha256 -ne $expectedFingerprint -or
                  $manifest.canonicalScenarioSha256 -ne $expectedCanonicalSha256 -or
                  $result.fairnessProtocolId -ne $expectedFairnessProtocolId -or
                  $result.fairnessProtocolSha256 -ne $expectedFairnessProtocolSha256 -or
                  $result.workloadSpecificationSha256 -ne $expectedWorkloadSpecificationSha256 -or
                  $manifest.unityVersion -ne $expectedUnityVersion) {
            throw "Campaign child scenario, protocol, workload, or Unity identity differs: $manifestPath"
        }
        if ($manifest.scenarioSourceSha256 -ne $scenarioSourceSha256) { throw "Child scenario source hash differs: $manifestPath" }

        $profiles[$algorithm] = [ordered]@{
            specificationId = $result.algorithmSpecificationId
            specificationRelativePath = $result.algorithmSpecificationRelativePath
            specificationSha256 = $result.algorithmSpecificationSha256
            implementationRelativePath = $result.algorithmImplementationRelativePath
            implementationSha256 = $result.algorithmImplementationSha256
            plannerStateModelId = $result.plannerStateModelId
            processedWorkUnit = $result.processedWorkUnit
            nativeMetricsSemanticsId = $result.nativeMetricsSemanticsId
        }
        $schedule += [ordered]@{
            block = $block + 1
            position = $position + 1
            algorithmId = $algorithm
            runId = $runId
            directory = ('runs/{0}/{1}' -f $blockName, $positionName)
            manifestFile = ('runs/{0}/{1}/manifest.json' -f $blockName, $positionName)
            manifestSha256 = Get-LowerSha256 $manifestPath
            workloadResultFile = ('runs/{0}/{1}/{2}' -f $blockName, $positionName, $manifest.workloadResultFile)
            workloadResultSha256 = $manifest.workloadResultSha256
            operationsJsonlSha256 = $manifest.operationsJsonlSha256
            planOperationCount = [int]$result.planOperationCount
            repairOperationCount = [int]$result.repairOperationCount
            succeededPlanCount = [int]$result.succeededPlanCount
            budgetExceededOperationCount = [int]$result.budgetExceededOperationCount
            completed = $true
        }
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
    $entries = @($schedule | Where-Object block -eq $block | Sort-Object position)
    if ($entries.Count -ne $algorithmCount -or @($entries.algorithmId | Sort-Object -Unique).Count -ne $algorithmCount) {
        throw "Campaign block is incomplete or duplicates an algorithm: $block"
    }
    for ($position = 0; $position -lt $algorithmCount; $position++) {
        $algorithm = $entries[$position].algorithmId
        $positionCounts[$algorithm]["p$($position + 1)"]++
        if ($position -lt $algorithmCount - 1) {
            $pair = "$algorithm>$($entries[$position + 1].algorithmId)"
            $predecessorCounts[$pair]++
        }
    }
}
$positionBalanced = @($positionCounts.GetEnumerator() | ForEach-Object { $_.Value.Values } | Where-Object { $_ -ne $completeCycles }).Count -eq 0
$predecessorBalanced = @($predecessorCounts.Values | Where-Object { $_ -ne $completeCycles }).Count -eq 0
if (-not $positionBalanced -or -not $predecessorBalanced) { throw 'Williams schedule balance validation failed.' }

$canonicalScenario = Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $OutputDirectory $schedule[0].directory | Join-Path -ChildPath 'scenario.canonical.json') | ConvertFrom-Json
$manifestPath = Join-Path $OutputDirectory 'campaign-manifest.json'
$manifest = [ordered]@{
    schemaVersion = 1
    campaignKind = 'gate10-pipeline-validation'
    campaignId = $CampaignId
    comparisonCohortId = $ComparisonCohortId
    fairnessProtocolId = $expectedFairnessProtocolId
    fairnessProtocolSha256 = $expectedFairnessProtocolSha256
    workloadSpecificationSha256 = $expectedWorkloadSpecificationSha256
    scenarioId = $expectedScenarioId
    scenarioSourcePath = $ScenarioPath
    scenarioSourceSha256 = $scenarioSourceSha256
    scenarioFingerprintSha256 = $expectedFingerprint
    canonicalScenarioSha256 = $expectedCanonicalSha256
    initializationBudgetMilliseconds = $canonicalScenario.initializationBudgetMilliseconds
    defaultPlanBudgetMilliseconds = $canonicalScenario.defaultPlanBudgetMilliseconds
    defaultRepairBudgetMilliseconds = $canonicalScenario.defaultRepairBudgetMilliseconds
    effectiveEventRepairBudgetsMilliseconds = @($canonicalScenario.scheduledChanges | ForEach-Object repairBudgetMilliseconds)
    unityVersion = $expectedUnityVersion
    unityExecutable = $UnityPath
    orderDesign = 'williams-balanced-v1'
    canonicalAlgorithmOrder = @($algorithms)
    blockCount = $Blocks
    algorithmCount = $algorithmCount
    sampleCount = $schedule.Count
    completeBalanceCycleCount = $completeCycles
    positionCounts = $positionCounts
    orderedPredecessorCounts = $predecessorCounts
    positionBalanced = $positionBalanced
    orderedPredecessorBalanced = $predecessorBalanced
    algorithmProfiles = $profiles
    schedule = @($schedule)
    startedAtUtc = $startedAtUtc.ToString('o')
    completedAtUtc = [DateTime]::UtcNow.ToString('o')
    formalCampaign = $false
    completed = $true
}
Write-Utf8NoBomJson -Path $manifestPath -Value $manifest -Depth 14

$summary = [ordered]@{
    savedAt = (Get-Date).ToString('o')
    outputDirectory = $OutputDirectory
    campaignManifestPath = $manifestPath
    campaignManifestSha256 = Get-LowerSha256 $manifestPath
    campaign = $manifest
    passed = $true
}
Write-Utf8NoBomJson -Path $summaryPath -Value $summary -Depth 14
$summary | ConvertTo-Json -Depth 6
Write-Host 'Fair planning campaign pipeline validation completed.' -ForegroundColor Green
exit 0
