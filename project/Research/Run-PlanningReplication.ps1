[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ScenarioPath,
    [ValidateRange(2, 100)]
    [int]$Repetitions = 3,
    [string]$GroupId,
    [string]$OutputDirectory,
    [ValidateSet('A*-R', 'D*L', 'C-FF', 'IDFF')]
    [string]$Algorithm = 'A*-R',
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

if ([string]::IsNullOrWhiteSpace($GroupId)) { $GroupId = 'rep-' + [DateTime]::UtcNow.ToString('yyyyMMddTHHmmssfffZ') }
if ($GroupId -notmatch '^[A-Za-z0-9][A-Za-z0-9_.-]{0,119}$') {
    throw 'GroupId must be 1-120 file-safe ASCII characters and begin with an alphanumeric character.'
}
if ([string]::IsNullOrWhiteSpace($OutputDirectory)) { $OutputDirectory = Join-Path $ProjectPath (Join-Path 'Research\Runs' $GroupId) }
elseif (-not [System.IO.Path]::IsPathRooted($OutputDirectory)) { $OutputDirectory = Join-Path $ProjectPath $OutputDirectory }
$OutputDirectory = [System.IO.Path]::GetFullPath($OutputDirectory)

$summaryPath = $OutputDirectory + '.summary.json'
if (Test-Path -LiteralPath $OutputDirectory) {
    if (-not (Test-Path -LiteralPath $OutputDirectory -PathType Container)) { throw "Output path is not a directory: $OutputDirectory" }
    if (@(Get-ChildItem -LiteralPath $OutputDirectory -Force).Count -gt 0) { throw "Output directory is not empty; refusing to overwrite: $OutputDirectory" }
}
if (Test-Path -LiteralPath $summaryPath) { throw "Replication summary already exists; refusing to overwrite: $summaryPath" }

$projectLockPath = Join-Path $ProjectPath 'Temp\UnityLockfile'
if (@(Get-Process -Name Unity -ErrorAction SilentlyContinue).Count -gt 0 -or (Test-Path -LiteralPath $projectLockPath)) {
    throw 'Close Unity before running the headless planning replication group.'
}

function Get-LowerSha256([string]$Path) {
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Write-Utf8NoBomJson([string]$Path, $Value, [int]$Depth = 10) {
    $json = $Value | ConvertTo-Json -Depth $Depth
    $json = $json.Replace("`r`n", "`n").Replace("`r", "`n")
    if (-not $json.EndsWith("`n", [System.StringComparison]::Ordinal)) { $json += "`n" }
    $encoding = New-Object System.Text.UTF8Encoding($false, $true)
    [System.IO.File]::WriteAllText($Path, $json, $encoding)
}

$runnerPath = Join-Path $scriptDirectory 'Run-PlanningWorkload.ps1'
if (-not (Test-Path -LiteralPath $runnerPath -PathType Leaf)) { throw "Planning workload runner not found: $runnerPath" }

$startedAtUtc = [DateTime]::UtcNow
$scenarioSourceSha256 = Get-LowerSha256 $ScenarioPath
$runsDirectory = Join-Path $OutputDirectory 'runs'
New-Item -ItemType Directory -Path $runsDirectory -Force | Out-Null

$childRuns = @()
$workloadResultPaths = @()
$expectedFingerprint = $null
$expectedScenarioId = $null
$expectedUnityVersion = $null
$expectedFairnessProtocolId = $null
$expectedFairnessProtocolSha256 = $null
$expectedAlgorithmSpecificationId = $null
$expectedAlgorithmSpecificationSha256 = $null
$expectedAlgorithmImplementationSha256 = $null
$expectedWorkloadSpecificationSha256 = $null
$expectedComparisonCohortId = $null

for ($index = 1; $index -le $Repetitions; $index++) {
    $ordinal = 'r{0:D3}' -f $index
    $runId = '{0}-{1}' -f $GroupId, $ordinal
    $childDirectory = Join-Path $runsDirectory $ordinal
    Write-Host "[$index/$Repetitions] Running independent Unity sample $runId..."

    & powershell -NoProfile -ExecutionPolicy Bypass -File $runnerPath `
        -ScenarioPath $ScenarioPath `
        -OutputDirectory $childDirectory `
        -RunId $runId `
        -Algorithm $Algorithm `
        -UnityPath $UnityPath `
        -ProjectPath $ProjectPath
    $childExitCode = $LASTEXITCODE
    if ($childExitCode -ne 0) { throw "Child workload failed with exit code ${childExitCode}: $runId" }

    $manifestPath = Join-Path $childDirectory 'manifest.json'
    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) { throw "Child manifest is missing: $manifestPath" }
    $manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($manifest.schemaVersion -ne 2 -or $manifest.completed -ne $true -or $manifest.runId -ne $runId -or $manifest.algorithmId -ne $Algorithm) {
        throw "Child manifest identity or completion state is invalid: $manifestPath"
    }
    if ($manifest.scenarioSourceSha256 -ne $scenarioSourceSha256) { throw "Child scenario source hash differs: $manifestPath" }

    $canonicalPath = Join-Path $childDirectory $manifest.canonicalScenarioFile
    $operationsPath = Join-Path $childDirectory $manifest.operationsJsonlFile
    $resultPath = Join-Path $childDirectory $manifest.workloadResultFile
    foreach ($requiredPath in @($canonicalPath, $operationsPath, $resultPath)) {
        if (-not (Test-Path -LiteralPath $requiredPath -PathType Leaf)) { throw "Child artifact is missing: $requiredPath" }
    }
    $canonicalSha256 = Get-LowerSha256 $canonicalPath
    $operationsSha256 = Get-LowerSha256 $operationsPath
    $resultSha256 = Get-LowerSha256 $resultPath
    if ($canonicalSha256 -ne $manifest.canonicalScenarioSha256 -or $operationsSha256 -ne $manifest.operationsJsonlSha256 -or $resultSha256 -ne $manifest.workloadResultSha256) {
        throw "Child artifact hash validation failed: $manifestPath"
    }

    $result = Get-Content -LiteralPath $resultPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($result.completed -ne $true -or $result.runId -ne $runId -or $result.algorithmId -ne $Algorithm -or $result.scenarioFingerprintSha256 -ne $manifest.scenarioFingerprintSha256 -or $result.fairnessSchemaVersion -ne 1 -or $result.dynamicCostIncludesAllRepairsAndPostEventPlans -ne $true) {
        throw "Child workload result identity or completion state is invalid: $resultPath"
    }
    if ($manifest.enqueuedLogRecords -ne $manifest.writtenLogRecords) { throw "Child JSONL logger did not flush every record: $manifestPath" }

    if ($null -eq $expectedFingerprint) {
        $expectedFingerprint = $manifest.scenarioFingerprintSha256
        $expectedScenarioId = $result.scenarioId
        $expectedUnityVersion = $manifest.unityVersion
        $expectedFairnessProtocolId = $result.fairnessProtocolId
        $expectedFairnessProtocolSha256 = $result.fairnessProtocolSha256
        $expectedAlgorithmSpecificationId = $result.algorithmSpecificationId
        $expectedAlgorithmSpecificationSha256 = $result.algorithmSpecificationSha256
        $expectedAlgorithmImplementationSha256 = $result.algorithmImplementationSha256
        $expectedWorkloadSpecificationSha256 = $result.workloadSpecificationSha256
        $expectedComparisonCohortId = $result.comparisonCohortId
    } elseif ($manifest.scenarioFingerprintSha256 -ne $expectedFingerprint -or $result.scenarioId -ne $expectedScenarioId -or $manifest.unityVersion -ne $expectedUnityVersion) {
        throw "Child scenario identity or Unity version differs within the replication group: $manifestPath"
    }
    if ($result.fairnessProtocolId -ne $expectedFairnessProtocolId -or
        $result.fairnessProtocolSha256 -ne $expectedFairnessProtocolSha256 -or
        $result.algorithmSpecificationId -ne $expectedAlgorithmSpecificationId -or
        $result.algorithmSpecificationSha256 -ne $expectedAlgorithmSpecificationSha256 -or
        $result.algorithmImplementationSha256 -ne $expectedAlgorithmImplementationSha256 -or
        $result.workloadSpecificationSha256 -ne $expectedWorkloadSpecificationSha256 -or
        $result.comparisonCohortId -ne $expectedComparisonCohortId) {
        throw "Child fairness or algorithm provenance differs within the replication group: $manifestPath"
    }

    $workloadResultPaths += $resultPath
    $childRuns += [ordered]@{
        ordinal = $index
        runId = $runId
        directory = "runs/$ordinal"
        manifestFile = "runs/$ordinal/manifest.json"
        manifestSha256 = Get-LowerSha256 $manifestPath
        canonicalScenarioSha256 = $canonicalSha256
        operationsJsonlSha256 = $operationsSha256
        workloadResultSha256 = $resultSha256
        fairnessProtocolSha256 = $result.fairnessProtocolSha256
        algorithmSpecificationSha256 = $result.algorithmSpecificationSha256
        algorithmImplementationSha256 = $result.algorithmImplementationSha256
        comparisonCohortId = $result.comparisonCohortId
        writtenLogRecords = [int64]$manifest.writtenLogRecords
        planOperationCount = [int]$result.planOperationCount
        repairOperationCount = [int]$result.repairOperationCount
        succeededPlanCount = [int]$result.succeededPlanCount
        completed = $true
    }
}

$requestPath = Join-Path $OutputDirectory 'aggregation-request.json'
$aggregatePath = Join-Path $OutputDirectory 'aggregate.json'
$aggregationLogPath = Join-Path $OutputDirectory 'aggregation.Unity.log'
$groupManifestPath = Join-Path $OutputDirectory 'replication-manifest.json'
$request = [ordered]@{
    schemaVersion = 1
    groupId = $GroupId
    scenarioSourceSha256 = $scenarioSourceSha256
    algorithmId = $Algorithm
    workloadResultPaths = @($workloadResultPaths)
}
Write-Utf8NoBomJson -Path $requestPath -Value $request -Depth 5

$arguments = @(
    '-batchmode'
    '-nographics'
    '-quit'
    '-projectPath'
    ('"{0}"' -f $ProjectPath)
    '-executeMethod'
    'DDM.Research.Editor.ResearchReplicationAggregateCommand.Run'
    '-ddmReplicationRequestPath'
    ('"{0}"' -f $requestPath)
    '-ddmAggregateOutputPath'
    ('"{0}"' -f $aggregatePath)
    '-logFile'
    ('"{0}"' -f $aggregationLogPath)
)

Write-Host 'Aggregating independently produced workload results in Unity...'
$aggregateProcess = Start-Process `
    -FilePath $UnityPath `
    -ArgumentList $arguments `
    -WorkingDirectory (Split-Path -Parent $UnityPath) `
    -WindowStyle Hidden `
    -Wait `
    -PassThru

$compilerPatterns = @('error CS\d{4}', 'Scripts have compiler errors', 'Compilation failed', 'executeMethod.+could not be found')
$compilerMatches = if (Test-Path -LiteralPath $aggregationLogPath) { @(Select-String -LiteralPath $aggregationLogPath -Pattern $compilerPatterns -AllMatches) } else { @() }
$completionMarker = if (Test-Path -LiteralPath $aggregationLogPath) { @(Select-String -LiteralPath $aggregationLogPath -SimpleMatch 'DDM replication aggregation completed. Output:').Count -gt 0 } else { $false }
if ($aggregateProcess.ExitCode -ne 0 -or $compilerMatches.Count -ne 0 -or -not $completionMarker) {
    throw "Replication aggregation failed. Review $aggregationLogPath"
}
if (-not (Test-Path -LiteralPath $aggregatePath -PathType Leaf)) { throw "Replication aggregate is missing: $aggregatePath" }

$aggregate = Get-Content -LiteralPath $aggregatePath -Raw -Encoding UTF8 | ConvertFrom-Json
if ($aggregate.completed -ne $true -or $aggregate.groupId -ne $GroupId -or $aggregate.algorithmId -ne $Algorithm -or $aggregate.scenarioSourceSha256 -ne $scenarioSourceSha256 -or $aggregate.scenarioFingerprintSha256 -ne $expectedFingerprint -or $aggregate.repetitionCount -ne $Repetitions) {
    throw "Replication aggregate identity or completion state is invalid: $aggregatePath"
}
for ($index = 0; $index -lt $Repetitions; $index++) {
    if ($aggregate.childRunIds[$index] -ne $childRuns[$index].runId) { throw "Aggregate child order or identity is invalid at index $index." }
}

$groupManifest = [ordered]@{
    schemaVersion = 2
    groupId = $GroupId
    algorithmId = $Algorithm
    fairnessProtocolId = $expectedFairnessProtocolId
    fairnessProtocolSha256 = $expectedFairnessProtocolSha256
    algorithmSpecificationId = $expectedAlgorithmSpecificationId
    algorithmSpecificationSha256 = $expectedAlgorithmSpecificationSha256
    algorithmImplementationSha256 = $expectedAlgorithmImplementationSha256
    workloadSpecificationSha256 = $expectedWorkloadSpecificationSha256
    comparisonCohortId = $expectedComparisonCohortId
    scenarioId = $expectedScenarioId
    scenarioSourcePath = $ScenarioPath
    scenarioSourceSha256 = $scenarioSourceSha256
    scenarioFingerprintSha256 = $expectedFingerprint
    repetitionCount = $Repetitions
    unityVersion = $expectedUnityVersion
    unityExecutable = $UnityPath
    childRuns = @($childRuns)
    aggregationRequestFile = 'aggregation-request.json'
    aggregationRequestSha256 = Get-LowerSha256 $requestPath
    aggregateFile = 'aggregate.json'
    aggregateSha256 = Get-LowerSha256 $aggregatePath
    aggregationUnityLogFile = 'aggregation.Unity.log'
    aggregationUnityLogSha256 = Get-LowerSha256 $aggregationLogPath
    startedAtUtc = $startedAtUtc.ToString('o')
    completedAtUtc = [DateTime]::UtcNow.ToString('o')
    completed = $true
}
Write-Utf8NoBomJson -Path $groupManifestPath -Value $groupManifest -Depth 10

$summary = [ordered]@{
    savedAt = (Get-Date).ToString('o')
    outputDirectory = $OutputDirectory
    groupManifestPath = $groupManifestPath
    groupManifestSha256 = Get-LowerSha256 $groupManifestPath
    aggregatePath = $aggregatePath
    aggregate = $aggregate
    compilerErrorMatchCount = $compilerMatches.Count
    completionMarkerPresent = $completionMarker
    passed = $true
}
Write-Utf8NoBomJson -Path $summaryPath -Value $summary -Depth 10
$summary | ConvertTo-Json -Depth 10
Write-Host 'Planning replication group completed.' -ForegroundColor Green
exit 0
