[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$ProjectRoot = 'H:\DDM_Final_Project',

    [Parameter(Mandatory = $false)]
    [string]$AnalysisRoot = 'H:\DDM_Final_Project\Research\Verification\Gate14Re-MQ-CFF-IDFF\engineering-runtime-analysis-v2'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

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

function Write-AtomicJson {
    param(
        [Parameter(Mandatory = $true)] [string]$Path,
        [Parameter(Mandatory = $true)] [object]$Value
    )
    $temporaryPath = $Path + '.tmp'
    $json = $Value | ConvertTo-Json -Depth 30
    [System.IO.File]::WriteAllText($temporaryPath, $json + [Environment]::NewLine, [System.Text.UTF8Encoding]::new($false))
    Move-Item -LiteralPath $temporaryPath -Destination $Path
}

$relativeInputs = [ordered]@{
    'Research/Verification/Gate14Re-MQ-CFF-IDFF/engineering-qualification-attempt-001/external-freeze-receipt.v1.json' = 'c2bc8217e48bdb3248e97353538207f9386c2c866fd80e713fabadaf195df33b'
    'Research/Verification/Gate14Re-MQ-CFF-IDFF/engineering-qualification-attempt-001/output/terminal-receipt.v1.json' = 'd5429793cc940ad2e0a1c51fea760d2cbd43766849fb0d1f80f4752ba4c5d09e'
    'Research/Verification/Gate14Re-MQ-CFF-IDFF/engineering-qualification-attempt-001/independent-validation-receipt.v1.json' = '2aa8d07c3957cc260753f7a14043c404d106a20db40ab3b9b5863f91f176a4c3'
    'Research/Verification/Gate14Re-MQ-CFF-IDFF/engineering-qualification-attempt-001/output/condition-summaries.engineering.v1.jsonl' = 'bd53448f0357ba4bbce932b4d563a16e39640b18cb06a08b1f6cd7e4a51ae174'
    'Research/Verification/Gate14Re-MQ-CFF-IDFF/engineering-qualification-attempt-001/output/technical-batches.raw.v1.jsonl' = '3b1fc6a3c3b7a40faa4ce17b50e9f279ac7eb21cef08d4c42478589ae955443f'
}

foreach ($entry in $relativeInputs.GetEnumerator()) {
    $path = Join-Path $ProjectRoot ($entry.Key -replace '/', '\')
    if (-not (Test-Path -LiteralPath $path)) {
        throw "Authorized analysis input is missing: $($entry.Key)"
    }
    if ((Get-Sha256Lower -Path $path) -ne $entry.Value) {
        throw "Authorized analysis input hash mismatch: $($entry.Key)"
    }
}

$attemptRoot = Join-Path $ProjectRoot 'Research\Verification\Gate14Re-MQ-CFF-IDFF\engineering-qualification-attempt-001'
$outputRoot = Join-Path $attemptRoot 'output'
$terminal = Get-Content -LiteralPath (Join-Path $outputRoot 'terminal-receipt.v1.json') -Raw | ConvertFrom-Json -Depth 30
$validation = Get-Content -LiteralPath (Join-Path $attemptRoot 'independent-validation-receipt.v1.json') -Raw | ConvertFrom-Json -Depth 30
$summaries = Read-JsonLines -Path (Join-Path $outputRoot 'condition-summaries.engineering.v1.jsonl')

if ($terminal.status -ne 'PASS_ENGINEERING_QUALIFICATION_FORMAL_MQ_DESIGN_STILL_PENDING' -or
    $validation.status -ne 'PASS_INDEPENDENT_STRUCTURAL_HASH_CARDINALITY_AFFINITY_AND_SEMANTIC_VALIDATION' -or
    $summaries.Count -ne 24) {
    throw 'Engineering qualification prerequisite is not a validated 24-row PASS.'
}

$sumBatchWallSeconds = (($summaries | Measure-Object -Property batchWallMilliseconds -Sum).Sum / 1000.0)
$cffBatchWallSeconds = (($summaries | Where-Object algorithmId -eq 'C-FF' | Measure-Object -Property batchWallMilliseconds -Sum).Sum / 1000.0)
$idffBatchWallSeconds = (($summaries | Where-Object algorithmId -eq 'IDFF' | Measure-Object -Property batchWallMilliseconds -Sum).Sum / 1000.0)
$wholeProcessSeconds = [double]$validation.executionDurationSeconds
$wholeProcessResidualSeconds = $wholeProcessSeconds - $sumBatchWallSeconds
if ($wholeProcessResidualSeconds -le 0) {
    throw 'Whole-process residual is not positive.'
}

$singleCcdScaling = [System.Collections.Generic.List[object]]::new()
foreach ($algorithmId in @('C-FF', 'IDFF')) {
    foreach ($topology in @(
        [pscustomobject]@{ role = 'LARGE_L3_CCD'; direct = 'ST-DIRECT-LARGE-L3'; prefix = 'MQ-LARGE-L3-W' },
        [pscustomobject]@{ role = 'HIGH_FREQUENCY_CCD'; direct = 'ST-DIRECT-HIGH-FREQUENCY'; prefix = 'MQ-HIGH-FREQUENCY-W' }
    )) {
        $baseline = $summaries | Where-Object { $_.algorithmId -eq $algorithmId -and $_.conditionId -eq $topology.direct }
        if (@($baseline).Count -ne 1) {
            throw "Missing or duplicate direct baseline for $algorithmId / $($topology.role)."
        }
        foreach ($workerCount in @(1, 2, 4, 8)) {
            $conditionId = $topology.prefix + $workerCount
            $condition = $summaries | Where-Object { $_.algorithmId -eq $algorithmId -and $_.conditionId -eq $conditionId }
            if (@($condition).Count -ne 1) {
                throw "Missing or duplicate condition $algorithmId / $conditionId."
            }
            $speedup = [double]$baseline.batchWallMilliseconds / [double]$condition.batchWallMilliseconds
            $throughputRatio = [double]$condition.endToEndLaneThroughputPerSecond / [double]$baseline.endToEndLaneThroughputPerSecond
            $singleCcdScaling.Add([ordered]@{
                algorithmId = $algorithmId
                topologyRole = $topology.role
                conditionId = $conditionId
                workerCount = $workerCount
                directReferenceConditionId = $topology.direct
                batchWallSeconds = [math]::Round(([double]$condition.batchWallMilliseconds / 1000.0), 6)
                endToEndLaneThroughputPerSecond = [math]::Round([double]$condition.endToEndLaneThroughputPerSecond, 6)
                technicalWallTimeSpeedup = [math]::Round($speedup, 6)
                technicalThroughputRatio = [math]::Round($throughputRatio, 6)
                technicalParallelEfficiency = [math]::Round(($speedup / $workerCount), 6)
            })
        }
    }
}

$matchedCcdDescriptions = [System.Collections.Generic.List[object]]::new()
foreach ($algorithmId in @('C-FF', 'IDFF')) {
    foreach ($workerCount in @(1, 2, 4, 8)) {
        $large = $summaries | Where-Object { $_.algorithmId -eq $algorithmId -and $_.conditionId -eq ('MQ-LARGE-L3-W' + $workerCount) }
        $high = $summaries | Where-Object { $_.algorithmId -eq $algorithmId -and $_.conditionId -eq ('MQ-HIGH-FREQUENCY-W' + $workerCount) }
        $matchedCcdDescriptions.Add([ordered]@{
            algorithmId = $algorithmId
            workerCount = $workerCount
            highFrequencyToLargeL3BatchWallRatio = [math]::Round(([double]$high.batchWallMilliseconds / [double]$large.batchWallMilliseconds), 6)
            highFrequencyToLargeL3ThroughputRatio = [math]::Round(([double]$high.endToEndLaneThroughputPerSecond / [double]$large.endToEndLaneThroughputPerSecond), 6)
            causalAttributionPermitted = $false
        })
    }
}

$dualCcdDescriptions = @(
    $summaries |
        Where-Object { $_.topologyRole -eq 'DUAL_CCD_BALANCED' } |
        Sort-Object batchOrdinal |
        ForEach-Object {
            [ordered]@{
                algorithmId = $_.algorithmId
                conditionId = $_.conditionId
                workerCount = $_.workerCount
                batchWallSeconds = [math]::Round(([double]$_.batchWallMilliseconds / 1000.0), 6)
                endToEndLaneThroughputPerSecond = [math]::Round([double]$_.endToEndLaneThroughputPerSecond, 6)
                processCpuEquivalentCoreCount = [math]::Round([double]$_.processCpuEquivalentCoreCount, 6)
                causalAttributionPermitted = $false
            }
        }
)

$processesPerMatchedBlock = 24
$nominalFreshProcessSecondsPerBlock = $sumBatchWallSeconds + ($processesPerMatchedBlock * $wholeProcessResidualSeconds)
$runtimeBudgets = @(
    foreach ($candidateB in @(36, 72, 108, 144)) {
        $nominalHours = $candidateB * $nominalFreshProcessSecondsPerBlock / 3600.0
        [ordered]@{
            B = $candidateB
            freshUnityProcessCount = $candidateB * $processesPerMatchedBlock
            inProcessLowerBoundHours = [math]::Round(($candidateB * $sumBatchWallSeconds / 3600.0), 6)
            freshProcessNominalHours = [math]::Round($nominalHours, 6)
            conservativeHoursAt1_5x = [math]::Round(($nominalHours * 1.5), 6)
            stressHoursAt1_9x = [math]::Round(($nominalHours * 1.9), 6)
            reachesSevenDayGateUnderStress = (($nominalHours * 1.9) -ge 168.0)
        }
    }
)

$result = [ordered]@{
    schema = 'gate14re-mq-engineering-runtime-diagnostics-v2'
    studyId = 'Gate14Re-MQ-CFF-IDFF'
    status = 'PASS_ENGINEERING_RESOURCE_DIAGNOSIS_FORMAL_MQ_DESIGN_NOT_FROZEN'
    sourceExecutionId = $terminal.executionId
    qualification = [ordered]@{
        batchCount = 24
        laneRows = 384
        summaryRows = 24
        allHardChecksPassed = $true
    }
    wholeProcess = [ordered]@{
        observedSeconds = [math]::Round($wholeProcessSeconds, 6)
        summedBatchWallSeconds = [math]::Round($sumBatchWallSeconds, 6)
        cffSummedBatchWallSeconds = [math]::Round($cffBatchWallSeconds, 6)
        idffSummedBatchWallSeconds = [math]::Round($idffBatchWallSeconds, 6)
        residualSeconds = [math]::Round($wholeProcessResidualSeconds, 6)
        residualInterpretation = 'Identifiable only as whole-process time outside the 24 recorded batch walls; it is not decomposed into startup, import, or shutdown components.'
    }
    singleCcdScaling = $singleCcdScaling
    matchedCcdDescriptions = $matchedCcdDescriptions
    dualCcdDescriptions = $dualCcdDescriptions
    formalRuntimePlanning = [ordered]@{
        processesPerMatchedBlock = $processesPerMatchedBlock
        nominalFreshProcessSecondsPerBlock = [math]::Round($nominalFreshProcessSecondsPerBlock, 6)
        budgets = $runtimeBudgets
        selectedB = $null
        selectionReason = 'Formal MQ MIPE, power target, multiplicity, stopping rule, and B-selection rule remain unfrozen.'
    }
    interpretationBoundary = [ordered]@{
        formalEffectEstimate = $false
        formalHypothesisTest = $false
        algorithmQualityComparison = $false
        winnerRanking = $false
        causalCcdAttribution = $false
        formalMqCollectionLaunched = $false
        formalAnalysisLaunched = $false
    }
    createdAtUtc = [DateTime]::UtcNow.ToString('o')
}

$outputPath = Join-Path $AnalysisRoot 'engineering-runtime-diagnostics.v2.json'
if (Test-Path -LiteralPath $outputPath) {
    throw "Refusing to overwrite existing analysis output: $outputPath"
}
Write-AtomicJson -Path $outputPath -Value $result

[ordered]@{
    status = $result.status
    outputPath = $outputPath
    outputBytes = (Get-Item -LiteralPath $outputPath).Length
    outputSha256 = Get-Sha256Lower -Path $outputPath
    createdAtUtc = $result.createdAtUtc
} | ConvertTo-Json -Depth 6
