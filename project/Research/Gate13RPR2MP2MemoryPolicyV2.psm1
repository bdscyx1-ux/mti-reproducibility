Set-StrictMode -Version 2.0

$script:MP2PolicyId = 'gate13r-pr2-mp2-layered-scenario-aware-memory-policy-v1'
$script:MiB = [int64]1048576
$script:GiB = [int64]1073741824
$script:ManagedAlertBytes = [int64](128 * $script:MiB)
$script:ManagedEmergencyBytes = [int64](256 * $script:MiB)
$script:HostAbsoluteNativeBytes = [int64](4 * $script:GiB)
$script:HostRelativeNativeBytes = [int64](2 * $script:GiB)
$script:HostAvailableFloorBytes = [int64](8 * $script:GiB)

function Get-G13RPR2MP2Sha256 {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Path)
    return (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToLowerInvariant()
}

function Get-G13RPR2MP2PolicyConstants {
    [CmdletBinding()]
    param()
    return [pscustomobject][ordered]@{
        policyId = $script:MP2PolicyId
        allowedCanonicalMaximumGridDimensions = @(32, 64, 128, 256)
        tierLe128 = [pscustomobject][ordered]@{
            tierId = 'MP2-NATIVE-LE128'
            nativeAdvisoryBytes = [int64](512 * $script:MiB)
            nativeHardBytes = [int64](640 * $script:MiB)
        }
        tierEq256 = [pscustomobject][ordered]@{
            tierId = 'MP2-NATIVE-EQ256'
            nativeAdvisoryBytes = [int64](640 * $script:MiB)
            nativeHardBytes = [int64](768 * $script:MiB)
        }
        managedAlertBytes = $script:ManagedAlertBytes
        managedSampleEmergencyBytes = $script:ManagedEmergencyBytes
        managedBlockEmergencyBytes = $script:ManagedEmergencyBytes
        hostAbsoluteNativeEmergencyBytes = $script:HostAbsoluteNativeBytes
        hostRelativeNativeGrowthEmergencyBytes = $script:HostRelativeNativeBytes
        hostAvailablePhysicalMemoryFloorBytes = $script:HostAvailableFloorBytes
    }
}

function Resolve-G13RPR2MP2ScenarioTier {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][object]$GridWidth,
        [Parameter(Mandatory = $true)][object]$GridHeight
    )
    $width = [int64]0
    $height = [int64]0
    if (-not [int64]::TryParse([string]$GridWidth, [ref]$width) -or -not [int64]::TryParse([string]$GridHeight, [ref]$height)) {
        throw 'MP2-CONFIGURATION-HARD-FAIL-GRID-DIMENSION-NONINTEGER'
    }
    if ($width -le 0 -or $height -le 0) { throw 'MP2-CONFIGURATION-HARD-FAIL-GRID-DIMENSION-NONPOSITIVE' }
    $maximum = [Math]::Max($width, $height)
    if (@(32L, 64L, 128L, 256L) -notcontains $maximum) {
        throw ('MP2-CONFIGURATION-HARD-FAIL-GRID-DIMENSION-UNSUPPORTED:' + $maximum)
    }
    if ($maximum -le 128L) {
        return [pscustomobject][ordered]@{
            policyId = $script:MP2PolicyId
            tierId = 'MP2-NATIVE-LE128'
            gridWidth = $width
            gridHeight = $height
            canonicalMaximumGridDimension = $maximum
            nativeAdvisoryBytes = [int64](512 * $script:MiB)
            nativeHardBytes = [int64](640 * $script:MiB)
        }
    }
    return [pscustomobject][ordered]@{
        policyId = $script:MP2PolicyId
        tierId = 'MP2-NATIVE-EQ256'
        gridWidth = $width
        gridHeight = $height
        canonicalMaximumGridDimension = $maximum
        nativeAdvisoryBytes = [int64](640 * $script:MiB)
        nativeHardBytes = [int64](768 * $script:MiB)
    }
}

function Test-G13RPR2MP2TelemetryPoint {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][object]$Telemetry)
    $required = @('processId','processStartTimeUtc','processAgeMilliseconds','workingSetBytes','privateMemoryBytes','managedMemoryBytes','availablePhysicalMemoryBytes','gcCollectionCount0','gcCollectionCount1','gcCollectionCount2')
    foreach ($name in $required) {
        if ($null -eq $Telemetry.PSObject.Properties[$name]) {
            return [pscustomobject][ordered]@{ passed=$false; reasonCode=('HARD-FAIL-TELEMETRY-MISSING-' + $name.ToUpperInvariant()) }
        }
    }
    if ([int64]$Telemetry.processId -le 0) { return [pscustomobject][ordered]@{ passed=$false; reasonCode='HARD-FAIL-TELEMETRY-PID-NONPOSITIVE' } }
    if ([string]::IsNullOrWhiteSpace([string]$Telemetry.processStartTimeUtc)) { return [pscustomobject][ordered]@{ passed=$false; reasonCode='HARD-FAIL-TELEMETRY-PROCESS-START-MISSING' } }
    $age = [double]$Telemetry.processAgeMilliseconds
    if ([double]::IsNaN($age) -or [double]::IsInfinity($age) -or $age -lt 0) { return [pscustomobject][ordered]@{ passed=$false; reasonCode='HARD-FAIL-TELEMETRY-PROCESS-AGE-INVALID' } }
    foreach ($name in @('workingSetBytes','privateMemoryBytes','managedMemoryBytes','availablePhysicalMemoryBytes')) {
        if ([int64]$Telemetry.$name -le 0) { return [pscustomobject][ordered]@{ passed=$false; reasonCode=('HARD-FAIL-TELEMETRY-' + $name.ToUpperInvariant() + '-NONPOSITIVE') } }
    }
    foreach ($name in @('gcCollectionCount0','gcCollectionCount1','gcCollectionCount2')) {
        if ([int64]$Telemetry.$name -lt 0) { return [pscustomobject][ordered]@{ passed=$false; reasonCode=('HARD-FAIL-TELEMETRY-' + $name.ToUpperInvariant() + '-NEGATIVE') } }
    }
    return [pscustomobject][ordered]@{ passed=$true; reasonCode='PASS' }
}

function Test-G13RPR2MP2TelemetrySequence {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][object]$BlockBaseline,
        [Parameter(Mandatory = $true)][object]$Current
    )
    $first = Test-G13RPR2MP2TelemetryPoint -Telemetry $BlockBaseline
    if (-not $first.passed) { return $first }
    $second = Test-G13RPR2MP2TelemetryPoint -Telemetry $Current
    if (-not $second.passed) { return $second }
    if ([int64]$BlockBaseline.processId -ne [int64]$Current.processId) { return [pscustomobject][ordered]@{passed=$false;reasonCode='HARD-FAIL-TELEMETRY-MIXED-PID'} }
    if ([string]$BlockBaseline.processStartTimeUtc -ne [string]$Current.processStartTimeUtc) { return [pscustomobject][ordered]@{passed=$false;reasonCode='HARD-FAIL-TELEMETRY-MIXED-PROCESS-START'} }
    if ([double]$Current.processAgeMilliseconds -lt [double]$BlockBaseline.processAgeMilliseconds) { return [pscustomobject][ordered]@{passed=$false;reasonCode='HARD-FAIL-TELEMETRY-PROCESS-AGE-ORDER'} }
    foreach ($name in @('gcCollectionCount0','gcCollectionCount1','gcCollectionCount2')) {
        if ([int64]$Current.$name -lt [int64]$BlockBaseline.$name) { return [pscustomobject][ordered]@{passed=$false;reasonCode='HARD-FAIL-TELEMETRY-GC-COUNT-ORDER'} }
    }
    return [pscustomobject][ordered]@{passed=$true;reasonCode='PASS'}
}

function Get-G13RPR2MP2CheckedDelta {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][int64]$Current,[Parameter(Mandatory=$true)][int64]$Baseline)
    $value = [decimal]$Current - [decimal]$Baseline
    if ($value -gt [decimal][int64]::MaxValue -or $value -lt [decimal][int64]::MinValue) {
        throw 'HARD-FAIL-TELEMETRY-DELTA-OVERFLOW'
    }
    return [int64]$value
}

function Invoke-G13RPR2MP2MemoryEvaluation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][ValidateSet('raw-after-workload','after-forced-cleanup','post-block-pre-exit')][string]$Stage,
        [Parameter(Mandatory = $true)][object]$Tier,
        [Parameter(Mandatory = $true)][object]$BlockBaseline,
        [Parameter(Mandatory = $true)][object]$SampleBaseline,
        [Parameter(Mandatory = $true)][object]$Current,
        [Parameter(Mandatory = $true)][string]$BlockId,
        [int]$ObservedPosition = 0,
        [string]$ObservedAlgorithmId = ''
    )
    if ([string]$Tier.policyId -ne $script:MP2PolicyId -or @('MP2-NATIVE-LE128','MP2-NATIVE-EQ256') -notcontains [string]$Tier.tierId) {
        throw 'MP2-CONFIGURATION-HARD-FAIL-POLICY-TIER-INVALID'
    }
    $sequence = Test-G13RPR2MP2TelemetrySequence -BlockBaseline $BlockBaseline -Current $Current
    if (-not $sequence.passed) {
        return [pscustomobject][ordered]@{
            policyId=$script:MP2PolicyId;tierId=[string]$Tier.tierId;blockId=$BlockId;stage=$Stage
            verdict='HARD-FAIL-TELEMETRY';reasonCode=[string]$sequence.reasonCode;stopCurrentBlock=$true;startNextBlockAllowed=$false
            attributionScope='WHOLE-BLOCK-PROCESS';attributedAlgorithmId=$null;observedPosition=$ObservedPosition;observedAlgorithmId=$ObservedAlgorithmId
        }
    }
    try {
        $workingDelta = Get-G13RPR2MP2CheckedDelta -Current ([int64]$Current.workingSetBytes) -Baseline ([int64]$BlockBaseline.workingSetBytes)
        $privateDelta = Get-G13RPR2MP2CheckedDelta -Current ([int64]$Current.privateMemoryBytes) -Baseline ([int64]$BlockBaseline.privateMemoryBytes)
        $sampleManagedDelta = Get-G13RPR2MP2CheckedDelta -Current ([int64]$Current.managedMemoryBytes) -Baseline ([int64]$SampleBaseline.managedMemoryBytes)
        $blockManagedDelta = Get-G13RPR2MP2CheckedDelta -Current ([int64]$Current.managedMemoryBytes) -Baseline ([int64]$BlockBaseline.managedMemoryBytes)
    } catch {
        return [pscustomobject][ordered]@{
            policyId=$script:MP2PolicyId;tierId=[string]$Tier.tierId;blockId=$BlockId;stage=$Stage
            verdict='HARD-FAIL-TELEMETRY';reasonCode='HARD-FAIL-TELEMETRY-DELTA-OVERFLOW';stopCurrentBlock=$true;startNextBlockAllowed=$false
            attributionScope='WHOLE-BLOCK-PROCESS';attributedAlgorithmId=$null;observedPosition=$ObservedPosition;observedAlgorithmId=$ObservedAlgorithmId
        }
    }
    $nativeMetric = [Math]::Max($workingDelta, $privateDelta)
    $absoluteNative = [Math]::Max([int64]$Current.workingSetBytes, [int64]$Current.privateMemoryBytes)
    $hostReasons = New-Object System.Collections.Generic.List[string]
    if ($absoluteNative -gt $script:HostAbsoluteNativeBytes) { [void]$hostReasons.Add('HARD-FAIL-HOST-ABSOLUTE-NATIVE-4GIB') }
    if ($nativeMetric -gt $script:HostRelativeNativeBytes) { [void]$hostReasons.Add('HARD-FAIL-HOST-RELATIVE-NATIVE-GROWTH-2GIB') }
    if ([int64]$Current.availablePhysicalMemoryBytes -lt $script:HostAvailableFloorBytes) { [void]$hostReasons.Add('HARD-FAIL-HOST-AVAILABLE-MEMORY-BELOW-8GIB') }

    $isCleanup = $Stage -eq 'after-forced-cleanup'
    $isPostBlock = $Stage -eq 'post-block-pre-exit'
    $managedAlert = ($isCleanup -and $sampleManagedDelta -gt $script:ManagedAlertBytes)
    $sampleManagedEmergency = ($isCleanup -and $sampleManagedDelta -gt $script:ManagedEmergencyBytes)
    $blockManagedEmergency = ($isPostBlock -and $blockManagedDelta -gt $script:ManagedEmergencyBytes)
    $nativeAdvisory = (($isCleanup -or $isPostBlock) -and $nativeMetric -gt [int64]$Tier.nativeAdvisoryBytes)
    $nativeHard = (($isCleanup -or $isPostBlock) -and $nativeMetric -gt [int64]$Tier.nativeHardBytes)

    $verdict = 'PASS'
    $reason = 'PASS'
    $stopCurrent = $false
    $startNext = $true
    if ($hostReasons.Count -gt 0) {
        $verdict = 'HARD-FAIL-HOST-EMERGENCY'; $reason = ($hostReasons.ToArray() -join '+'); $stopCurrent = $true; $startNext = $false
    } elseif ($sampleManagedEmergency) {
        $verdict = 'HARD-FAIL-MANAGED-EMERGENCY'; $reason = 'HARD-FAIL-SAMPLE-MANAGED-AFTER-CLEANUP-256MIB'; $stopCurrent = $true; $startNext = $false
    } elseif ($blockManagedEmergency) {
        $verdict = 'HARD-FAIL-MANAGED-EMERGENCY'; $reason = 'HARD-FAIL-BLOCK-MANAGED-AFTER-CLEANUP-256MIB'; $stopCurrent = $true; $startNext = $false
    } elseif ($nativeHard) {
        $verdict = 'HARD-FAIL-NATIVE-ELIGIBILITY'; $reason = 'HARD-FAIL-NATIVE-RESIDENCY-TIER-CEILING'; $stopCurrent = $false; $startNext = $false
    } elseif ($nativeAdvisory -or $managedAlert) {
        $verdict = 'PASS-WITH-ADVISORY'
        $parts = New-Object System.Collections.Generic.List[string]
        if ($nativeAdvisory) { [void]$parts.Add('NATIVE-RESIDENCY-ADVISORY') }
        if ($managedAlert) { [void]$parts.Add('MANAGED-AFTER-CLEANUP-ALERT-128MIB') }
        $reason = $parts.ToArray() -join '+'
    } elseif ($Stage -eq 'raw-after-workload') {
        $reason = 'RAW-TRANSIENT-DIAGNOSTIC-ONLY'
    }

    return [pscustomobject][ordered]@{
        policyId = $script:MP2PolicyId
        tierId = [string]$Tier.tierId
        blockId = $BlockId
        stage = $Stage
        workingSetDeltaFromBlockBaselineBytes = $workingDelta
        privateMemoryDeltaFromBlockBaselineBytes = $privateDelta
        nativeResidencyMetricBytes = $nativeMetric
        nativeAdvisoryBytes = [int64]$Tier.nativeAdvisoryBytes
        nativeHardBytes = [int64]$Tier.nativeHardBytes
        nativeAdvisoryCrossed = $nativeAdvisory
        nativeHardCrossed = $nativeHard
        sampleRetainedManagedGrowthBytes = $sampleManagedDelta
        blockRetainedManagedGrowthBytes = $blockManagedDelta
        managedAlertCrossed = $managedAlert
        sampleManagedEmergencyCrossed = $sampleManagedEmergency
        blockManagedEmergencyCrossed = $blockManagedEmergency
        absoluteNativeBytes = $absoluteNative
        availablePhysicalMemoryBytes = [int64]$Current.availablePhysicalMemoryBytes
        hostEmergency = $hostReasons.Count -gt 0
        rawTransientDiagnosticOnly = $Stage -eq 'raw-after-workload' -and $hostReasons.Count -eq 0
        verdict = $verdict
        reasonCode = $reason
        stopCurrentBlock = $stopCurrent
        startNextBlockAllowed = $startNext
        attributionScope = 'WHOLE-BLOCK-PROCESS'
        attributedAlgorithmId = $null
        observedPosition = $ObservedPosition
        observedAlgorithmId = $ObservedAlgorithmId
    }
}

function Test-G13RPR2MP2PathWithin {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$BasePath,[Parameter(Mandatory=$true)][string]$CandidatePath)
    $base = [IO.Path]::GetFullPath($BasePath).TrimEnd('\','/') + [IO.Path]::DirectorySeparatorChar
    $candidate = [IO.Path]::GetFullPath($CandidatePath)
    return $candidate.StartsWith($base, [StringComparison]::OrdinalIgnoreCase)
}

function Assert-G13RPR2MP2FormalAttempt3Absent {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$ProjectPath)
    $project = [IO.Path]::GetFullPath($ProjectPath)
    $root = Join-Path $project 'Research/FormalRuns/Gate13R_RQAligned_S48H48/v3'
    $receipt = Join-Path $project 'Research/Gate13R_PR2_Formal_Execution_Receipt.v3.json'
    $status = Join-Path $project 'Research/Gate13R_PR2_Formal_Execution_Status.v3.json'
    if (Test-Path -LiteralPath $root) { throw 'FORMAL-ATTEMPT3-ROOT-MUST-REMAIN-ABSENT' }
    if (Test-Path -LiteralPath $receipt) { throw 'FORMAL-ATTEMPT3-RECEIPT-MUST-REMAIN-ABSENT' }
    if (Test-Path -LiteralPath $status) { throw 'FORMAL-ATTEMPT3-STATUS-MUST-REMAIN-ABSENT' }
    return [pscustomobject][ordered]@{passed=$true;formalRoot=$root;formalReceipt=$receipt;formalStatus=$status}
}

Export-ModuleMember -Function @(
    'Get-G13RPR2MP2Sha256',
    'Get-G13RPR2MP2PolicyConstants',
    'Resolve-G13RPR2MP2ScenarioTier',
    'Test-G13RPR2MP2TelemetryPoint',
    'Test-G13RPR2MP2TelemetrySequence',
    'Get-G13RPR2MP2CheckedDelta',
    'Invoke-G13RPR2MP2MemoryEvaluation',
    'Test-G13RPR2MP2PathWithin',
    'Assert-G13RPR2MP2FormalAttempt3Absent'
)
