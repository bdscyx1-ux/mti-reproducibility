[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$ProjectRoot = 'H:\DDM_Final_Project',

    [Parameter(Mandatory = $false)]
    [string]$AttemptRoot = 'H:\DDM_Final_Project\Research\Verification\Gate14Re-MQ-CFF-IDFF\engineering-qualification-attempt-001'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$outputRoot = Join-Path $AttemptRoot 'output'
$errors = [System.Collections.Generic.List[string]]::new()

function Test-Requirement {
    param(
        [Parameter(Mandatory = $true)] [bool]$Condition,
        [Parameter(Mandatory = $true)] [string]$Message
    )
    if (-not $Condition) {
        $script:errors.Add($Message)
    }
}

function Get-Sha256Lower {
    param([Parameter(Mandatory = $true)] [string]$Path)
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Read-JsonLines {
    param([Parameter(Mandatory = $true)] [string]$Path)
    return @(
        [System.IO.File]::ReadLines($Path) |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
            ForEach-Object { $_ | ConvertFrom-Json -Depth 100 }
    )
}

$terminalPath = Join-Path $outputRoot 'terminal-receipt.v1.json'
$terminal = Get-Content -LiteralPath $terminalPath -Raw | ConvertFrom-Json -Depth 30
Test-Requirement ($terminal.schema -eq 'gate14re-mq-engineering-qualification-terminal-receipt-v1') 'terminal schema mismatch'
Test-Requirement ($terminal.executionId -eq 'gate14re-mq-engineering-attempt-001-c8d8e31e-74b5-4633-bfa3-773f84f6e3a6') 'execution id mismatch'
Test-Requirement ($terminal.status -eq 'PASS_ENGINEERING_QUALIFICATION_FORMAL_MQ_DESIGN_STILL_PENDING') 'terminal status mismatch'
Test-Requirement ($terminal.batchCount -eq 24 -and $terminal.laneRows -eq 384 -and $terminal.summaryRows -eq 24) 'terminal cardinality mismatch'
Test-Requirement ($terminal.gate13rPrerequisiteVerified -and $terminal.allBatchesPassed -and $terminal.allTerminalDigestsInvariant -and $terminal.explicitWorkloadBoundariesPresent) 'terminal hard-pass flag mismatch'
Test-Requirement (-not $terminal.formalMQCollectionExecuted -and -not $terminal.formalAnalysisExecuted -and -not $terminal.formalSTOrMTTouched) 'formal-scope flag mismatch'
Test-Requirement (-not (Test-Path -LiteralPath (Join-Path $outputRoot 'failure-receipt.v1.json'))) 'failure receipt exists'

$outputManifestPath = Join-Path $outputRoot 'output-freeze-manifest.v1.json'
$outputManifest = Get-Content -LiteralPath $outputManifestPath -Raw | ConvertFrom-Json -Depth 20
Test-Requirement ($outputManifest.schema -eq 'gate14re-mq-engineering-output-freeze-manifest-v1' -and $outputManifest.files.Count -eq 4) 'output manifest schema/cardinality mismatch'
for ($index = 0; $index -lt $outputManifest.files.Count; $index++) {
    $binding = $outputManifest.files[$index]
    $path = Join-Path $outputRoot $binding.relativePath
    Test-Requirement ($binding.ordinal -eq $index) "output manifest ordinal mismatch at $index"
    Test-Requirement (Test-Path -LiteralPath $path) "missing output $($binding.relativePath)"
    if (Test-Path -LiteralPath $path) {
        Test-Requirement ((Get-Item -LiteralPath $path).Length -eq $binding.bytes) "output byte count mismatch for $($binding.relativePath)"
        Test-Requirement ((Get-Sha256Lower -Path $path) -eq $binding.sha256) "output hash mismatch for $($binding.relativePath)"
    }
}

$sourceManifestPath = Join-Path $outputRoot 'source-bindings-manifest.v1.json'
$sourceManifest = Get-Content -LiteralPath $sourceManifestPath -Raw | ConvertFrom-Json -Depth 20
Test-Requirement ($sourceManifest.schema -eq 'gate14re-mq-engineering-source-bindings-manifest-v1' -and $sourceManifest.files.Count -eq 8) 'source manifest schema/cardinality mismatch'
for ($index = 0; $index -lt $sourceManifest.files.Count; $index++) {
    $binding = $sourceManifest.files[$index]
    $path = Join-Path $ProjectRoot ($binding.relativePath -replace '/', '\')
    Test-Requirement ($binding.ordinal -eq $index) "source manifest ordinal mismatch at $index"
    Test-Requirement (Test-Path -LiteralPath $path) "missing source $($binding.relativePath)"
    if (Test-Path -LiteralPath $path) {
        Test-Requirement ((Get-Item -LiteralPath $path).Length -eq $binding.bytes) "source byte count mismatch for $($binding.relativePath)"
        Test-Requirement ((Get-Sha256Lower -Path $path) -eq $binding.sha256) "source hash mismatch for $($binding.relativePath)"
    }
}

$gate13OutputRoot = Join-Path $ProjectRoot 'Research\Verification\Gate14Re-MQ-CFF-IDFF\gate13r-mq-qualification-attempt-001\output'
$inventoryPath = Join-Path $gate13OutputRoot 'input-inventory.v1.json'
$inventory = Get-Content -LiteralPath $inventoryPath -Raw | ConvertFrom-Json -Depth 30
Test-Requirement ($inventory.lanes.Count -eq 16) 'Gate13R input-inventory lane count mismatch'

$laneGeometry = @()
for ($laneIndex = 0; $laneIndex -lt 16; $laneIndex++) {
    $binding = $inventory.lanes[$laneIndex]
    $inputPath = Join-Path $ProjectRoot ($binding.relativePath -replace '/', '\')
    Test-Requirement ((Get-Sha256Lower -Path $inputPath) -eq $binding.sha256) "input hash mismatch at lane $laneIndex"
    $input = Get-Content -LiteralPath $inputPath -Raw | ConvertFrom-Json -Depth 100
    Test-Requirement ($input.agentCount -eq $binding.agentCount) "agent binding mismatch at lane $laneIndex"
    Test-Requirement ($input.eventGroups.Count -eq 24) "event-group count mismatch at lane $laneIndex"
    Test-Requirement ($input.sameTickAtomicPartitions -ge 1) "atomic-partition count invalid at lane $laneIndex"
    $laneGeometry += [pscustomobject]@{
        agentCount = [int]$input.agentCount
        partitions = [int]$input.sameTickAtomicPartitions
        eventGroups = [int]$input.eventGroups.Count
    }
}

$expectedConditions = @(
    'ST-DIRECT-LARGE-L3',
    'MQ-LARGE-L3-W1',
    'MQ-LARGE-L3-W2',
    'MQ-LARGE-L3-W4',
    'MQ-LARGE-L3-W8',
    'ST-DIRECT-HIGH-FREQUENCY',
    'MQ-HIGH-FREQUENCY-W1',
    'MQ-HIGH-FREQUENCY-W2',
    'MQ-HIGH-FREQUENCY-W4',
    'MQ-HIGH-FREQUENCY-W8',
    'MQ-DUAL-CCD-W8-4PLUS4',
    'MQ-DUAL-CCD-W16-8PLUS8'
)

$summariesPath = Join-Path $outputRoot 'condition-summaries.engineering.v1.jsonl'
$summaries = Read-JsonLines -Path $summariesPath
Test-Requirement ($summaries.Count -eq 24) 'summary row count mismatch'
Test-Requirement (@($summaries.batchOrdinal | Sort-Object -Unique).Count -eq 24) 'summary batch ordinals are not unique'
for ($index = 0; $index -lt $summaries.Count; $index++) {
    $row = $summaries[$index]
    $expectedAlgorithm = if ($index -lt 12) { 'C-FF' } else { 'IDFF' }
    $expectedCondition = $expectedConditions[$index % 12]
    Test-Requirement ($row.schema -eq 'gate14re-mq-condition-summary-engineering-v1') "summary schema mismatch at $index"
    Test-Requirement ($row.batchOrdinal -eq $index) "summary ordinal mismatch at $index"
    Test-Requirement ($row.algorithmId -eq $expectedAlgorithm) "summary algorithm mismatch at $index"
    Test-Requirement ($row.conditionId -eq $expectedCondition) "summary condition mismatch at $index"
    Test-Requirement ($row.laneCount -eq 16 -and $row.totalQueryCount -eq 16000 -and $row.totalRepairCount -eq 960) "summary workload cardinality mismatch at $index"
    Test-Requirement $row.exactTerminalDigestInvariancePassed "summary digest-invariance flag failed at $index"
    Test-Requirement ($row.batchWallMilliseconds -gt 0 -and $row.workloadWallP50Milliseconds -gt 0) "summary timing invalid at $index"
    Test-Requirement ($row.interpretationBoundary -match 'NOT_FORMAL') "summary interpretation boundary missing at $index"
}

$batchesPath = Join-Path $outputRoot 'technical-batches.raw.v1.jsonl'
$batches = Read-JsonLines -Path $batchesPath
Test-Requirement ($batches.Count -eq 24) 'batch row count mismatch'
Test-Requirement (@($batches.batchId | Sort-Object -Unique).Count -eq 24) 'batch identifiers are not unique'
for ($index = 0; $index -lt $batches.Count; $index++) {
    $batch = $batches[$index]
    Test-Requirement ($batch.schema -eq 'gate14re-mq-managed-batch-runtime-v1') "batch schema mismatch at $index"
    Test-Requirement ($batch.succeeded -and $batch.status -eq 'PASS_ALL_LANES_COMPLETED') "batch status failed at $index"
    Test-Requirement ($batch.laneCount -eq 16 -and $batch.completedLaneCount -eq 16 -and $batch.failedLaneCount -eq 0 -and $batch.skippedLaneCount -eq 0) "batch cardinality mismatch at $index"
    Test-Requirement ($null -eq $batch.firstFailure -or [string]::IsNullOrEmpty([string]$batch.firstFailure)) "batch firstFailure populated at $index"
    Test-Requirement ($batch.lanes.Count -eq 16) "nested batch-lane count mismatch at $index"
    Test-Requirement (@($batch.lanes.ordinal | Sort-Object -Unique).Count -eq 16) "nested batch-lane ordinals are not unique at $index"
    foreach ($laneRuntime in $batch.lanes) {
        Test-Requirement ($laneRuntime.state -eq 'COMPLETED') "batch lane did not complete at $index/$($laneRuntime.ordinal)"
        Test-Requirement $laneRuntime.stayedOnConfiguredCpuSet "batch lane affinity failed at $index/$($laneRuntime.ordinal)"
        Test-Requirement ([string]::IsNullOrEmpty([string]$laneRuntime.error)) "batch lane error populated at $index/$($laneRuntime.ordinal)"
    }
}

$lanesPath = Join-Path $outputRoot 'performance-lanes.raw.v1.jsonl'
$lanes = Read-JsonLines -Path $lanesPath
Test-Requirement ($lanes.Count -eq 384) 'performance-lane row count mismatch'
$digests = @{}
$maxBoundaryDeltaMilliseconds = 0.0
for ($index = 0; $index -lt $lanes.Count; $index++) {
    $row = $lanes[$index]
    $batchOrdinal = [int][math]::Floor($index / 16)
    $laneOrdinal = $index % 16
    $expectedAlgorithm = if ($batchOrdinal -lt 12) { 'C-FF' } else { 'IDFF' }
    $geometry = $laneGeometry[$laneOrdinal]
    $expectedQueryCount = $geometry.agentCount * ($geometry.eventGroups + 1)
    $expectedRepairCount = $geometry.partitions * $geometry.eventGroups

    Test-Requirement ($row.schema -eq 'gate14re-mq-performance-lane-evidence-v1') "lane schema mismatch at $index"
    Test-Requirement ($row.batchOrdinal -eq $batchOrdinal -and $row.laneOrdinal -eq $laneOrdinal) "lane ordinal mismatch at $index"
    Test-Requirement ($row.conditionId -eq $expectedConditions[$batchOrdinal % 12]) "lane condition mismatch at $index"
    Test-Requirement ($row.executorRuntime.ordinal -eq $laneOrdinal -and $row.executorRuntime.state -eq 'COMPLETED') "executor lane status mismatch at $index"
    Test-Requirement $row.executorRuntime.stayedOnConfiguredCpuSet "executor affinity failed at $index"
    Test-Requirement ([string]::IsNullOrEmpty([string]$row.executorRuntime.error)) "executor error populated at $index"
    Test-Requirement ($row.workload.schema -eq 'gate14re-mq-performance-lane-result-v1' -and $row.workload.status -eq 'PASS_TECHNICAL_PERFORMANCE_KERNEL') "workload status failed at $index"
    Test-Requirement ($row.workload.algorithmId -eq $expectedAlgorithm) "workload algorithm mismatch at $index"
    Test-Requirement ($row.workload.inputId -eq $inventory.lanes[$laneOrdinal].inputId -and $row.workload.inputSha256 -eq $inventory.lanes[$laneOrdinal].sha256 -and $row.sourceReplicaIndex -eq $inventory.lanes[$laneOrdinal].replicaIndex) "input binding mismatch at $index"
    Test-Requirement ($row.workload.eventGroupCount -eq $geometry.eventGroups -and $row.workload.initialQueryCount -eq $geometry.agentCount -and $row.workload.postEventQueryCount -eq ($geometry.agentCount * $geometry.eventGroups) -and $row.workload.totalQueryCount -eq $expectedQueryCount -and $row.workload.repairCount -eq $expectedRepairCount) "workload cardinality mismatch at $index"
    Test-Requirement (($row.workload.succeededQueryCount + $row.workload.noPathQueryCount) -eq $row.workload.totalQueryCount) "query outcome cardinality mismatch at $index"
    Test-Requirement ($row.workload.queryWallMilliseconds.Count -eq $expectedQueryCount -and $row.workload.gridMutationAndRepairWallMilliseconds.Count -eq $expectedRepairCount -and $row.workload.eventGroupWallMilliseconds.Count -eq $geometry.eventGroups) "timing vector cardinality mismatch at $index"

    $workloadStart = $row.workload.workloadStartUtc
    $workloadEnd = $row.workload.workloadEndUtc
    Test-Requirement ($workloadStart -is [datetime] -and $workloadEnd -is [datetime] -and $workloadEnd.Ticks -gt $workloadStart.Ticks) "workload boundary order invalid at $index"
    $boundaryMilliseconds = ($workloadEnd - $workloadStart).TotalMilliseconds
    $boundaryDeltaMilliseconds = [math]::Abs($boundaryMilliseconds - $row.workload.workloadWallMilliseconds)
    if ($boundaryDeltaMilliseconds -gt $maxBoundaryDeltaMilliseconds) {
        $maxBoundaryDeltaMilliseconds = $boundaryDeltaMilliseconds
    }
    Test-Requirement ($boundaryDeltaMilliseconds -le 5.0) "workload boundary discrepancy exceeds 5 ms at $index"

    $digestKey = "$expectedAlgorithm|$laneOrdinal"
    if (-not $digests.ContainsKey($digestKey)) {
        $digests[$digestKey] = $row.workload.terminalSemanticDigestSha256
    } else {
        Test-Requirement ($digests[$digestKey] -eq $row.workload.terminalSemanticDigestSha256) "terminal digest changed for $digestKey at batch $batchOrdinal"
    }
}
Test-Requirement ($digests.Count -eq 32) 'terminal digest key cardinality mismatch'

$laneHash = Get-Sha256Lower -Path $lanesPath
$batchHash = Get-Sha256Lower -Path $batchesPath
$summaryHash = Get-Sha256Lower -Path $summariesPath
Test-Requirement ($terminal.performanceLaneEvidenceSha256 -eq $laneHash -and $terminal.batchRuntimeSha256 -eq $batchHash -and $terminal.conditionSummarySha256 -eq $summaryHash) 'terminal output hash binding mismatch'

$result = [ordered]@{
    schema = 'gate14re-mq-engineering-independent-validation-result-v1'
    status = if ($errors.Count -eq 0) { 'PASS' } else { 'FAIL' }
    errorCount = $errors.Count
    errors = @($errors | Select-Object -First 100)
    terminalSha256 = Get-Sha256Lower -Path $terminalPath
    batchRows = $batches.Count
    laneRows = $lanes.Count
    summaryRows = $summaries.Count
    digestKeys = $digests.Count
    maxWorkloadBoundaryDeltaMilliseconds = [math]::Round($maxBoundaryDeltaMilliseconds, 6)
    validatedAtUtc = [DateTime]::UtcNow.ToString('o')
}

$result | ConvertTo-Json -Depth 8
if ($errors.Count -gt 0) {
    exit 1
}
