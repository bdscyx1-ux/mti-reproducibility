Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

function Get-Gate12LowerSha256 {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "File not found: $Path" }
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Test-Gate12FiniteNumber {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)]$Value)
    try { $number = [double]$Value } catch { return $false }
    return -not [double]::IsNaN($number) -and -not [double]::IsInfinity($number)
}

function Get-Gate12Mean {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][double[]]$Values)
    if ($Values.Count -eq 0) { throw 'Mean requires at least one value.' }
    $sum = 0.0
    foreach ($value in $Values) {
        if (-not (Test-Gate12FiniteNumber $value)) { throw 'Mean input contains a non-finite value.' }
        $sum += $value
    }
    return $sum / $Values.Count
}

function Get-Gate12Median {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][double[]]$Values)
    if ($Values.Count -eq 0) { throw 'Median requires at least one value.' }
    $sorted = @($Values | Sort-Object)
    foreach ($value in $sorted) { if (-not (Test-Gate12FiniteNumber $value)) { throw 'Median input contains a non-finite value.' } }
    $middle = [int][math]::Floor($sorted.Count / 2.0)
    if ($sorted.Count % 2 -eq 1) { return [double]$sorted[$middle] }
    return ([double]$sorted[$middle - 1] + [double]$sorted[$middle]) / 2.0
}

function Get-Gate12NearestRankPercentile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][double[]]$Values,
        [Parameter(Mandatory = $true)][ValidateRange(0.0000001, 1.0)][double]$Probability
    )
    if ($Values.Count -eq 0) { throw 'Percentile requires at least one value.' }
    $sorted = @($Values | Sort-Object)
    foreach ($value in $sorted) { if (-not (Test-Gate12FiniteNumber $value)) { throw 'Percentile input contains a non-finite value.' } }
    $rank = [int][math]::Ceiling($Probability * $sorted.Count)
    if ($rank -lt 1) { $rank = 1 }
    return [double]$sorted[$rank - 1]
}

function Get-Gate12SampleStandardDeviation {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][double[]]$Values)
    if ($Values.Count -lt 2) { throw 'Sample standard deviation requires at least two values.' }
    $mean = Get-Gate12Mean -Values $Values
    $sumSquares = 0.0
    foreach ($value in $Values) {
        $difference = $value - $mean
        $sumSquares += $difference * $difference
    }
    return [math]::Sqrt($sumSquares / ($Values.Count - 1))
}

function Get-Gate12CellStatistics {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][double[]]$Values,
        [switch]$RequireStrictlyPositive
    )
    if ($Values.Count -lt 2) { throw 'Cell statistics require at least two observations.' }
    foreach ($value in $Values) {
        if (-not (Test-Gate12FiniteNumber $value)) { throw 'Cell contains a non-finite value.' }
        if ($RequireStrictlyPositive -and $value -le 0.0) { throw 'Cell contains a non-positive value.' }
    }
    $mean = Get-Gate12Mean -Values $Values
    $sampleSd = Get-Gate12SampleStandardDeviation -Values $Values
    return [ordered]@{
        n = $Values.Count
        mean = $mean
        median = Get-Gate12Median -Values $Values
        p95 = Get-Gate12NearestRankPercentile -Values $Values -Probability 0.95
        sampleStandardDeviation = $sampleSd
        standardError = $sampleSd / [math]::Sqrt($Values.Count)
        minimum = [double]($Values | Measure-Object -Minimum).Minimum
        maximum = [double]($Values | Measure-Object -Maximum).Maximum
    }
}

function Get-Gate12SampleSizeCandidate {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][double]$SigmaLog,
        [double]$Z = 1.96,
        [double]$RelativeHalfWidth = 0.05,
        [int]$MinimumPerAlgorithm = 30,
        [int]$CycleMultiple = 4,
        [int]$MaximumPerAlgorithm = 100
    )
    foreach ($number in @($SigmaLog, $Z, $RelativeHalfWidth)) {
        if (-not (Test-Gate12FiniteNumber $number)) { throw 'Sample-size input contains a non-finite value.' }
    }
    if ($SigmaLog -lt 0.0) { throw 'SigmaLog cannot be negative.' }
    if ($Z -le 0.0 -or $RelativeHalfWidth -le 0.0 -or $MinimumPerAlgorithm -lt 1 -or $CycleMultiple -lt 1 -or $MaximumPerAlgorithm -lt 1) { throw 'Sample-size constants must be positive.' }
    $denominator = [math]::Log(1.0 + $RelativeHalfWidth)
    $rawDouble = [math]::Ceiling([math]::Pow(($Z * $SigmaLog / $denominator), 2.0))
    if (-not (Test-Gate12FiniteNumber $rawDouble) -or $rawDouble -gt [long]::MaxValue) { throw 'Sample-size result exceeds the supported integer range.' }
    $nRaw = [long]$rawDouble
    $minimumRoundedInput = [math]::Max([double]$MinimumPerAlgorithm, [double]$nRaw)
    $required = [long]($CycleMultiple * [math]::Ceiling($minimumRoundedInput / $CycleMultiple))
    $candidate = [long][math]::Min([double]$MaximumPerAlgorithm, [double]$required)
    $overCap = $required -gt $MaximumPerAlgorithm
    return [ordered]@{
        sigmaLog = $SigmaLog
        z = $Z
        relativeHalfWidth = $RelativeHalfWidth
        nRaw = $nRaw
        requiredNFormal = $required
        candidateNFormal = $candidate
        cycleMultiple = $CycleMultiple
        maximumPerAlgorithm = $MaximumPerAlgorithm
        overCap = $overCap
        precisionStatus = if ($overCap) { 'blocked-amendment-required' } else { 'within-cap' }
    }
}

function Get-Gate12FamilyAnalysis {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][object[]]$Samples,
        [Parameter(Mandatory = $true)]$FamilyDefinition,
        [Parameter(Mandatory = $true)][string[]]$ExpectedScenarioIds,
        [int]$ExpectedRepetitionsPerCell = 8
    )
    $cohortId = [string]$FamilyDefinition.comparisonCohortId
    $algorithms = @($FamilyDefinition.algorithms | ForEach-Object { [string]$_ })
    if ($algorithms.Count -ne 2) { throw "Family $($FamilyDefinition.familyId) must contain exactly two algorithms." }
    $familySamples = @($Samples | Where-Object { $_.comparisonCohortId -eq $cohortId -and $_.algorithmId -in $algorithms -and $_.scenarioId -in $ExpectedScenarioIds })
    $expectedTotal = $ExpectedScenarioIds.Count * $algorithms.Count * $ExpectedRepetitionsPerCell
    if ($familySamples.Count -ne $expectedTotal) { throw "Family $($FamilyDefinition.familyId) has $($familySamples.Count) samples; expected $expectedTotal." }

    $cellStatistics = @()
    foreach ($scenarioId in $ExpectedScenarioIds) {
        foreach ($algorithmId in $algorithms) {
            $cellSamples = @($familySamples | Where-Object { $_.scenarioId -eq $scenarioId -and $_.algorithmId -eq $algorithmId } | Sort-Object campaignOrdinal, block, position)
            if ($cellSamples.Count -ne $ExpectedRepetitionsPerCell) { throw "Cell $scenarioId/$algorithmId has $($cellSamples.Count) samples; expected $ExpectedRepetitionsPerCell." }
            $rawValues = @($cellSamples | ForEach-Object { [double]$_.primaryEndpoint })
            foreach ($value in $rawValues) {
                if (-not (Test-Gate12FiniteNumber $value) -or $value -le 0.0) { throw "Cell $scenarioId/$algorithmId has a non-positive or non-finite primary endpoint." }
            }
            $logValues = @($rawValues | ForEach-Object { [math]::Log($_) })
            $rawStatistics = Get-Gate12CellStatistics -Values $rawValues -RequireStrictlyPositive
            $logStatistics = Get-Gate12CellStatistics -Values $logValues
            $cellStatistics += [ordered]@{
                cellId = "$cohortId::$scenarioId::$algorithmId"
                comparisonCohortId = $cohortId
                scenarioId = $scenarioId
                algorithmId = $algorithmId
                repetitionCount = $cellSamples.Count
                runIds = @($cellSamples | ForEach-Object { [string]$_.runId })
                workloadResultRelativePaths = @($cellSamples | ForEach-Object { [string]$_.workloadResultRelativePath })
                rawEndpoint = $rawStatistics
                logEndpoint = $logStatistics
            }
        }
    }
    $governingCell = @($cellStatistics | Sort-Object @{ Expression = { [double]$_.logEndpoint.sampleStandardDeviation }; Descending = $true }, cellId | Select-Object -First 1)[0]
    $sigmaLog = [double]$governingCell.logEndpoint.sampleStandardDeviation
    return [ordered]@{
        familyId = [string]$FamilyDefinition.familyId
        comparisonCohortId = $cohortId
        algorithms = $algorithms
        scenarioIds = $ExpectedScenarioIds
        measuredSampleCount = $familySamples.Count
        cellCount = $cellStatistics.Count
        repetitionsPerCell = $ExpectedRepetitionsPerCell
        sigmaEstimator = 'maximum-valid-cell-sample-standard-deviation-v1'
        sigmaLog = $sigmaLog
        governingCellId = [string]$governingCell.cellId
        cells = $cellStatistics
        sampleSize = Get-Gate12SampleSizeCandidate -SigmaLog $sigmaLog
    }
}

function Get-Gate12ProjectedProcessCount {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][long]$P1,
        [Parameter(Mandatory = $true)][long]$P2,
        [Parameter(Mandatory = $true)][long]$P3,
        [Parameter(Mandatory = $true)][long]$P4,
        [int]$SharedScenarioCount = 32,
        [int]$HeterogeneousScenarioCount = 21
    )
    foreach ($value in @($P1, $P2, $P3, $P4)) { if ($value -lt 1) { throw 'Every family sample count must be positive.' } }
    return [long]($SharedScenarioCount * 2L * $P1 + $HeterogeneousScenarioCount * 2L * $P2 + $SharedScenarioCount * 2L * $P3 + $HeterogeneousScenarioCount * 2L * $P4)
}

function Get-Gate12CompletedSampleCount {
    [CmdletBinding()]
    param([object[]]$Entries)
    $total = 0
    foreach ($entry in @($Entries)) {
        if ($null -eq $entry) { continue }
        if ($entry -is [System.Collections.IDictionary]) {
            if (-not $entry.Contains('sampleCount')) { throw 'Completed entry is missing sampleCount.' }
            $count = [int]$entry['sampleCount']
        }
        else {
            $property = $entry.PSObject.Properties['sampleCount']
            if ($null -eq $property) { throw 'Completed entry is missing sampleCount.' }
            $count = [int]$property.Value
        }
        if ($count -lt 0) { throw 'Completed entry sampleCount cannot be negative.' }
        $total += $count
    }
    return [int]$total
}

function Start-Gate12OwnedProcessCapture {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [Parameter(Mandatory = $true)][string]$Arguments,
        [Parameter(Mandatory = $true)][string]$WorkingDirectory
    )
    if (-not (Test-Path -LiteralPath $FilePath -PathType Leaf)) { throw "Process executable not found: $FilePath" }
    if (-not (Test-Path -LiteralPath $WorkingDirectory -PathType Container)) { throw "Process working directory not found: $WorkingDirectory" }

    $startInfo = New-Object System.Diagnostics.ProcessStartInfo
    $startInfo.FileName = $FilePath
    $startInfo.Arguments = $Arguments
    $startInfo.WorkingDirectory = $WorkingDirectory
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $startInfo
    try {
        if (-not $process.Start()) { throw "Process failed to start: $FilePath" }
        $stdoutTask = $process.StandardOutput.ReadToEndAsync()
        $stderrTask = $process.StandardError.ReadToEndAsync()
        return [pscustomobject]@{
            Process = $process
            StdoutTask = $stdoutTask
            StderrTask = $stderrTask
        }
    }
    catch {
        $process.Dispose()
        throw
    }
}

function Test-Gate12PreflightSnapshot {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Snapshot,
        [Parameter(Mandatory = $true)]$Plan
    )
    $checks = [ordered]@{
        acOnline = -not $Plan.preflight.requireAcOnline -or [int]$Snapshot.acLineStatus -eq 1
        powerSchemeMatches = [string]::Equals([string]$Snapshot.activePowerSchemeGuid, [string]$Plan.preflight.requiredActivePowerSchemeGuid, [System.StringComparison]::OrdinalIgnoreCase)
        freePhysicalMemorySufficient = [double]$Snapshot.freePhysicalMemoryGiB -ge [double]$Plan.preflight.minimumFreePhysicalMemoryGiB
        freeOutputDriveSufficient = [double]$Snapshot.freeOutputDriveGiB -ge [double]$Plan.preflight.minimumFreeOutputDriveGiB
        cpuLoadAcceptable = [double]$Snapshot.meanCpuLoadPercent -le [double]$Plan.preflight.maximumMeanCpuLoadPercent
        noUnityProcess = -not $Plan.preflight.requireNoUnityProcess -or [int]$Snapshot.unityProcessCount -eq 0
        noUnityLockfile = -not $Plan.preflight.requireNoUnityLockfile -or $Snapshot.unityLockfilePresent -eq $false
        unityIdentityMatches = [string]::Equals([string]$Snapshot.unityExecutableSha256, [string]$Plan.unity.executableSha256, [System.StringComparison]::OrdinalIgnoreCase) -and [string]$Snapshot.unityProductVersion -eq [string]$Plan.unity.productVersion
        frozenHashesMatch = $Snapshot.frozenHashesMatch -eq $true
    }
    $failedChecks = @($checks.GetEnumerator() | Where-Object { -not $_.Value } | ForEach-Object { $_.Key })
    return [ordered]@{
        checks = $checks
        failedChecks = $failedChecks
        temperatureStatus = if ($Snapshot.temperatureAvailable -eq $true) { 'available' } else { 'unavailable-advisory' }
        passed = $failedChecks.Count -eq 0
    }
}

function Get-Gate12MonitorDecision {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][double]$ElapsedSeconds,
        [Parameter(Mandatory = $true)][int]$NoGrowthChecks,
        [Parameter(Mandatory = $true)][double]$HardTimeoutSeconds,
        [Parameter(Mandatory = $true)][int]$OutputStallChecks
    )
    if ($ElapsedSeconds -ge $HardTimeoutSeconds) { return 'hard-timeout' }
    if ($NoGrowthChecks -ge $OutputStallChecks) { return 'output-stall-advisory' }
    return 'continue'
}

Export-ModuleMember -Function @(
    'Get-Gate12LowerSha256',
    'Test-Gate12FiniteNumber',
    'Get-Gate12Mean',
    'Get-Gate12Median',
    'Get-Gate12NearestRankPercentile',
    'Get-Gate12SampleStandardDeviation',
    'Get-Gate12CellStatistics',
    'Get-Gate12SampleSizeCandidate',
    'Get-Gate12FamilyAnalysis',
    'Get-Gate12ProjectedProcessCount',
    'Get-Gate12CompletedSampleCount',
    'Start-Gate12OwnedProcessCapture',
    'Test-Gate12PreflightSnapshot',
    'Get-Gate12MonitorDecision'
)
