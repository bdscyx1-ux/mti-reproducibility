[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$ProjectRoot,
    [Parameter(Mandatory = $true)][string]$MeasuredRoot,
    [Parameter(Mandatory = $true)][string]$ExecutionAuthorization,
    [Parameter(Mandatory = $true)][ValidatePattern('^[0-9a-f]{64}$')][string]$ExecutionAuthorizationSha256,
    [Parameter(Mandatory = $true)][string]$ImplementationManifest,
    [Parameter(Mandatory = $true)][ValidatePattern('^[0-9a-f]{64}$')][string]$ImplementationManifestSha256,
    [Parameter(Mandatory = $true)][string]$ResourceBudget,
    [Parameter(Mandatory = $true)][ValidatePattern('^[0-9a-f]{64}$')][string]$ResourceBudgetSha256,
    [Parameter(Mandatory = $true)][string]$FairnessBinding,
    [Parameter(Mandatory = $true)][ValidatePattern('^[0-9a-f]{64}$')][string]$FairnessBindingSha256,
    [Parameter(Mandatory = $true)][string]$Schedule,
    [Parameter(Mandatory = $true)][ValidatePattern('^[0-9a-f]{64}$')][string]$ScheduleSha256,
    [Parameter(Mandatory = $true)][string]$UnityExecutable,
    [Parameter(Mandatory = $true)][ValidatePattern('^[0-9a-f]{64}$')][string]$UnityExecutableSha256
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$runnerMethod = 'DDM.Research.Editor.Gate14ReMELoadQualificationRunnerV1.Run'
$reservedRelativeRoot = 'Research/PilotRuns/Gate14Re-ME/load-qualification/attempt-001'
$expectedAlgorithms = @('A*-R', 'BiA*-R', 'D*L', 'LPA*', 'C-FF', 'IDFF')
$expectedAnonymousLanes = @('ALG-A', 'ALG-B', 'ALG-C', 'ALG-D', 'ALG-E', 'ALG-F')

function Get-NormalizedFullPath([string]$Path, [string]$Base) {
    $candidate = if ([System.IO.Path]::IsPathRooted($Path)) { $Path } else { Join-Path -Path $Base -ChildPath $Path }
    return [System.IO.Path]::GetFullPath($candidate).TrimEnd([System.IO.Path]::DirectorySeparatorChar)
}

function Assert-InsideProject([string]$Path, [string]$Root, [string]$Label) {
    $prefix = $Root.TrimEnd([System.IO.Path]::DirectorySeparatorChar) + [System.IO.Path]::DirectorySeparatorChar
    if (-not $Path.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "$Label resolves outside the project root."
    }
}

function Get-ProjectRelativePath([string]$Path, [string]$Root) {
    $rootUri = [Uri]::new($Root.TrimEnd([System.IO.Path]::DirectorySeparatorChar) + [System.IO.Path]::DirectorySeparatorChar)
    $pathUri = [Uri]::new($Path)
    return [Uri]::UnescapeDataString($rootUri.MakeRelativeUri($pathUri).ToString()).Replace('\','/')
}

function Get-Sha256([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "Required file is missing: $Path" }
    return (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToLowerInvariant()
}

function Assert-Hash([string]$Path, [string]$Expected, [string]$Label) {
    $actual = Get-Sha256 -Path $Path
    if ($actual -ne $Expected) { throw "$Label SHA-256 mismatch: expected $Expected; actual $actual" }
}

function Read-Json([string]$Path) {
    return Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
}

function Write-JsonAtomic([string]$Path, [object]$Value) {
    $temporary = "$Path.tmp.$([Guid]::NewGuid().ToString('N'))"
    $Value | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $temporary -Encoding UTF8
    if (Test-Path -LiteralPath $Path) { throw "Refusing to overwrite receipt: $Path" }
    Move-Item -LiteralPath $temporary -Destination $Path
}

function Append-JsonLine([string]$Path, [object]$Value) {
    $line = $Value | ConvertTo-Json -Depth 20 -Compress
    Add-Content -LiteralPath $Path -Value $line -Encoding UTF8
}

function Get-CommonRunnerArguments([string]$Mode, [string]$OutputDirectory) {
    return @(
        '-batchmode', '-nographics', '-quit',
        '-projectPath', $script:projectRootFull,
        '-executeMethod', $script:runnerMethod,
        '--g14me-mode', $Mode,
        '--g14me-output-dir', $OutputDirectory,
        '--g14me-execution-authorization', $script:authorizationFull,
        '--g14me-execution-authorization-sha256', $script:ExecutionAuthorizationSha256,
        '--g14me-implementation-manifest', $script:manifestFull,
        '--g14me-implementation-manifest-sha256', $script:ImplementationManifestSha256,
        '--g14me-resource-budget', $script:budgetFull,
        '--g14me-resource-budget-sha256', $script:ResourceBudgetSha256,
        '--g14me-fairness-binding', $script:fairnessFull,
        '--g14me-fairness-binding-sha256', $script:FairnessBindingSha256,
        '--g14me-schedule', $script:scheduleFull,
        '--g14me-schedule-sha256', $script:ScheduleSha256
    )
}

function Invoke-FreshUnityProcess([string]$Mode, [string]$OutputDirectory, [string[]]$AdditionalArguments, [int64]$TimeoutMilliseconds) {
    if (Test-Path -LiteralPath $OutputDirectory) { throw "Fresh process output already exists: $OutputDirectory" }
    $arguments = @(Get-CommonRunnerArguments -Mode $Mode -OutputDirectory $OutputDirectory) + $AdditionalArguments
    $process = Start-Process -FilePath $script:unityFull -ArgumentList $arguments -WindowStyle Hidden -PassThru
    $createdAtUtc = [DateTime]::UtcNow.ToString('o')
    Append-JsonLine -Path $script:processLedger -Value ([ordered]@{
        schema = 'gate14re-me-process-ledger-row-v1'
        mode = $Mode
        processId = $process.Id
        createdAtUtc = $createdAtUtc
        outputRelativePath = Get-ProjectRelativePath -Path $OutputDirectory -Root $script:projectRootFull
        state = 'LAUNCHED'
    })
    if (-not $process.WaitForExit([int]$TimeoutMilliseconds)) {
        Stop-Process -Id $process.Id -Force
        $process.WaitForExit()
        throw "Fresh Unity process exceeded the frozen timeout: mode=$Mode pid=$($process.Id) timeoutMs=$TimeoutMilliseconds"
    }
    Append-JsonLine -Path $script:processLedger -Value ([ordered]@{
        schema = 'gate14re-me-process-ledger-row-v1'
        mode = $Mode
        processId = $process.Id
        createdAtUtc = $createdAtUtc
        exitedAtUtc = [DateTime]::UtcNow.ToString('o')
        exitCode = $process.ExitCode
        outputRelativePath = Get-ProjectRelativePath -Path $OutputDirectory -Root $script:projectRootFull
        state = if ($process.ExitCode -eq 0) { 'EXITED_ZERO' } else { 'EXITED_NONZERO' }
    })
    if ($process.ExitCode -ne 0) { throw "Fresh Unity process exited nonzero: mode=$Mode pid=$($process.Id) code=$($process.ExitCode)" }
}

function Assert-Receipt([string]$Path, [string]$ExpectedStatus) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "Required receipt is missing: $Path" }
    $receipt = Read-Json -Path $Path
    if ($receipt.status -ne $ExpectedStatus) { throw "Receipt has unexpected status at ${Path}: $($receipt.status)" }
    return $receipt
}

function Invoke-Superblock([object]$Record, [string]$InputFull, [string]$InputSha256, [string]$PlannedSuperblockId, [string]$InstanceId, [bool]$IsReplacement) {
    $superblockRoot = Join-Path -Path $script:measuredRootFull -ChildPath "raw/superblocks/$InstanceId"
    if (Test-Path -LiteralPath $superblockRoot) { throw "Superblock output already exists: $superblockRoot" }
    New-Item -ItemType Directory -Path $superblockRoot | Out-Null
    try {
        foreach ($lane in $Record.algorithmOrder) {
            $laneOutput = Join-Path -Path $superblockRoot -ChildPath $lane.anonymousLaneId
            $oracleOutput = Join-Path -Path $script:measuredRootFull -ChildPath "oracle/$($Record.superblockId)"
            $oracleReceipt = Join-Path -Path $oracleOutput -ChildPath 'oracle-pass-receipt.v1.json'
            $oracleReceiptSha = Get-Sha256 -Path $oracleReceipt
            Invoke-FreshUnityProcess -Mode 'lane' -OutputDirectory $laneOutput -TimeoutMilliseconds $script:budget.laneWallClockHardTimeoutMilliseconds -AdditionalArguments @(
                '--g14me-input', $InputFull,
                '--g14me-oracle-receipt', $oracleReceipt,
                '--g14me-oracle-receipt-sha256', $oracleReceiptSha,
                '--g14me-algorithm-id', $lane.algorithmId,
                '--g14me-anonymous-lane-id', $lane.anonymousLaneId,
                '--g14me-identity-binding-sha256', $lane.identityBindingSha256
            )
            Assert-Receipt -Path (Join-Path $laneOutput 'lane-receipt.v1.json') -ExpectedStatus 'COMPLETE_RAW_LANE' | Out-Null
        }
        Write-JsonAtomic -Path (Join-Path $superblockRoot 'accepted-superblock-receipt.v1.json') -Value ([ordered]@{
            schema = 'gate14re-me-accepted-superblock-receipt-v1'
            studyId = 'Gate14Re-ME'
            status = 'ACCEPTED_COMPLETE_SIX_LANE_SUPERBLOCK'
            plannedSuperblockId = $PlannedSuperblockId
            instanceId = $InstanceId
            isReplacement = $IsReplacement
            acceptedAnonymousLanes = 6
            createdAtUtc = [DateTime]::UtcNow.ToString('o')
        })
        return $true
    }
    catch {
        Append-JsonLine -Path $script:voidLedger -Value ([ordered]@{
            schema = 'gate14re-me-whole-superblock-void-row-v1'
            recordId = "void:$PlannedSuperblockId`:$InstanceId"
            plannedSuperblockId = $PlannedSuperblockId
            instanceId = $InstanceId
            isReplacement = $IsReplacement
            status = 'VOID_WHOLE_SUPERBLOCK_TECHNICAL_FAILURE'
            reason = $_.Exception.Message
            createdAtUtc = [DateTime]::UtcNow.ToString('o')
        })
        return $false
    }
}

# Read-only preflight. Nothing under the measured root may exist or be created before every check below passes.
$projectRootFull = Get-NormalizedFullPath -Path $ProjectRoot -Base (Get-Location).Path
if (-not (Test-Path -LiteralPath $projectRootFull -PathType Container)) { throw 'Project root does not exist.' }
$expectedMeasuredRoot = Get-NormalizedFullPath -Path $reservedRelativeRoot -Base $projectRootFull
$measuredRootFull = Get-NormalizedFullPath -Path $MeasuredRoot -Base $projectRootFull
Assert-InsideProject -Path $measuredRootFull -Root $projectRootFull -Label 'Measured root'
if ($measuredRootFull -ne $expectedMeasuredRoot) { throw "Measured root must equal the frozen attempt-001 path: $expectedMeasuredRoot" }
if (Test-Path -LiteralPath $measuredRootFull) { throw 'Measured root already exists; resume and overwrite are prohibited.' }

$authorizationFull = Get-NormalizedFullPath -Path $ExecutionAuthorization -Base $projectRootFull
$manifestFull = Get-NormalizedFullPath -Path $ImplementationManifest -Base $projectRootFull
$budgetFull = Get-NormalizedFullPath -Path $ResourceBudget -Base $projectRootFull
$fairnessFull = Get-NormalizedFullPath -Path $FairnessBinding -Base $projectRootFull
$scheduleFull = Get-NormalizedFullPath -Path $Schedule -Base $projectRootFull
$unityFull = Get-NormalizedFullPath -Path $UnityExecutable -Base $projectRootFull
foreach ($binding in @(
    @{ Path = $authorizationFull; Hash = $ExecutionAuthorizationSha256; Label = 'execution authorization' },
    @{ Path = $manifestFull; Hash = $ImplementationManifestSha256; Label = 'implementation manifest' },
    @{ Path = $budgetFull; Hash = $ResourceBudgetSha256; Label = 'resource budget' },
    @{ Path = $fairnessFull; Hash = $FairnessBindingSha256; Label = 'fairness binding' },
    @{ Path = $scheduleFull; Hash = $ScheduleSha256; Label = 'qualification schedule' },
    @{ Path = $unityFull; Hash = $UnityExecutableSha256; Label = 'Unity executable' }
)) { Assert-Hash -Path $binding.Path -Expected $binding.Hash -Label $binding.Label }

$authorization = Read-Json -Path $authorizationFull
if ($authorization.schema -ne 'gate14re-me-load-qualification-execution-authorization-v1' -or
    $authorization.studyId -ne 'Gate14Re-ME' -or
    $authorization.status -ne 'AUTHORIZED_LOAD_QUALIFICATION_EXECUTION' -or
    -not $authorization.qualificationInputGenerationAuthorized -or
    -not $authorization.qualificationRootCreationAuthorized -or
    -not $authorization.compileOrUnityExecutionAuthorized -or
    -not $authorization.qualificationExecutionAuthorized -or
    $authorization.formalCollectionAuthorized -or
    $authorization.formalAnalysisAuthorized -or
    $authorization.measuredRootRelativePath.Replace('\','/') -ne $reservedRelativeRoot -or
    $authorization.implementationManifestSha256 -ne $ImplementationManifestSha256 -or
    $authorization.scheduleSha256 -ne $ScheduleSha256 -or
    $authorization.implementationManifestRelativePath.Replace('\','/') -ne (Get-ProjectRelativePath -Path $manifestFull -Root $projectRootFull) -or
    $authorization.scheduleRelativePath.Replace('\','/') -ne (Get-ProjectRelativePath -Path $scheduleFull -Root $projectRootFull) -or
    [string]::IsNullOrWhiteSpace($authorization.authorizationNonce)) {
    throw 'Execution authorization is absent, incomplete, unbound, or exceeds the qualification-only boundary.'
}

$manifest = Read-Json -Path $manifestFull
$budget = Read-Json -Path $budgetFull
$fairness = Read-Json -Path $fairnessFull
if ($manifest.status -ne 'FROZEN_IMPLEMENTATION_SOURCE_ONLY_UNCOMPILED') { throw 'Implementation manifest status mismatch.' }
if ($budget.status -ne 'FROZEN_PREEXECUTION_BUDGETS' -or $budget.maximumConcurrentUnityProcesses -ne 1 -or $budget.maximumWholeSuperblockTechnicalReplacements -ne 1) { throw 'Resource budget status or serial/replacement rule mismatch.' }
if ($fairness.status -ne 'FROZEN_SIX_ALGORITHM_BINDING' -or $fairness.algorithms.Count -ne 6) { throw 'Fairness binding mismatch.' }

$records = @(Get-Content -LiteralPath $scheduleFull -Encoding UTF8 | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | ForEach-Object { $_ | ConvertFrom-Json })
if ($records.Count -ne 162) { throw "Qualification schedule must contain exactly 162 records; found $($records.Count)." }
$seenSuperblocks = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
$seenPrimaryInputs = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
$seenInputIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
$identityBindingHashes = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
for ($recordIndex = 0; $recordIndex -lt $records.Count; $recordIndex++) {
    $record = $records[$recordIndex]
    if ($record.schema -ne 'gate14re-me-load-qualification-schedule-row-v1' -or $record.ordinal -ne $recordIndex) { throw "Schedule schema/ordinal mismatch at row $recordIndex." }
    if (-not $seenSuperblocks.Add([string]$record.superblockId)) { throw "Duplicate superblock id: $($record.superblockId)" }
    if ($record.algorithmOrder.Count -ne 6) { throw "Superblock must contain six lanes: $($record.superblockId)" }
    $algorithms = @($record.algorithmOrder | ForEach-Object { $_.algorithmId } | Sort-Object)
    $lanes = @($record.algorithmOrder | ForEach-Object { $_.anonymousLaneId } | Sort-Object)
    if (($algorithms -join '|') -ne (($expectedAlgorithms | Sort-Object) -join '|')) { throw "Algorithm cohort mismatch in $($record.superblockId)." }
    if (($lanes -join '|') -ne (($expectedAnonymousLanes | Sort-Object) -join '|')) { throw "Anonymous lane cohort mismatch in $($record.superblockId)." }
    $inputFull = Get-NormalizedFullPath -Path $record.inputRelativePath -Base $projectRootFull
    Assert-InsideProject -Path $inputFull -Root $projectRootFull -Label 'Input'
    Assert-Hash -Path $inputFull -Expected $record.inputSha256 -Label "input $($record.superblockId)"
    $inputRelative = Get-ProjectRelativePath -Path $inputFull -Root $projectRootFull
    if ($record.inputRelativePath.Replace('\','/') -ne $inputRelative -or -not $seenPrimaryInputs.Add($inputRelative)) { throw "Non-canonical or duplicate primary input path in $($record.superblockId)." }
    $inputBundle = Read-Json -Path $inputFull
    if ($inputBundle.schema -ne 'gate14re-me-qualification-input-bundle-v1' -or $inputBundle.studyId -ne 'Gate14Re-ME' -or $inputBundle.protocolId -ne 'gate14re-me-load-qualification-v1' -or $inputBundle.superblockId -ne $record.superblockId -or [string]::IsNullOrWhiteSpace($inputBundle.inputId) -or -not $seenInputIds.Add([string]$inputBundle.inputId)) { throw "Primary input identity/schema mismatch or duplicate inputId in $($record.superblockId)." }
    foreach ($lane in $record.algorithmOrder) { if (-not [string]::IsNullOrWhiteSpace($lane.identityBindingSha256)) { $null = $identityBindingHashes.Add([string]$lane.identityBindingSha256) } }
}
if ($identityBindingHashes.Count -ne 1 -or -not ([string]($identityBindingHashes | Select-Object -First 1) -match '^[0-9a-f]{64}$')) { throw 'All schedule rows must bind the same lower-case SHA-256 anonymous identity map.' }
$seenReplacementIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
$seenReplacementInputs = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
foreach ($record in $records) {
    if ($null -ne $record.replacement) {
        if ($seenSuperblocks.Contains([string]$record.replacement.superblockId) -or -not $seenReplacementIds.Add([string]$record.replacement.superblockId)) { throw "Replacement superblock id is not unique/disjoint: $($record.replacement.superblockId)" }
        $replacementFull = Get-NormalizedFullPath -Path $record.replacement.inputRelativePath -Base $projectRootFull
        Assert-InsideProject -Path $replacementFull -Root $projectRootFull -Label 'Replacement input'
        Assert-Hash -Path $replacementFull -Expected $record.replacement.inputSha256 -Label "replacement input $($record.superblockId)"
        $replacementRelative = Get-ProjectRelativePath -Path $replacementFull -Root $projectRootFull
        if ($record.replacement.inputRelativePath.Replace('\','/') -ne $replacementRelative -or $seenPrimaryInputs.Contains($replacementRelative) -or -not $seenReplacementInputs.Add($replacementRelative)) { throw "Replacement input is not canonical/unique/disjoint: $replacementRelative" }
        $replacementBundle = Read-Json -Path $replacementFull
        if ($replacementBundle.schema -ne 'gate14re-me-qualification-input-bundle-v1' -or $replacementBundle.studyId -ne 'Gate14Re-ME' -or $replacementBundle.protocolId -ne 'gate14re-me-load-qualification-v1' -or $replacementBundle.superblockId -ne $record.replacement.superblockId -or [string]::IsNullOrWhiteSpace($replacementBundle.inputId) -or -not $seenInputIds.Add([string]$replacementBundle.inputId)) { throw "Replacement input identity/schema mismatch or duplicate inputId in $($record.superblockId)." }
    }
}

$activeRunner = @(Get-CimInstance Win32_Process -Filter "Name = 'Unity.exe'" | Where-Object { $_.CommandLine -like "*$runnerMethod*" -or $_.CommandLine -like "*$measuredRootFull*" })
if ($activeRunner.Count -ne 0) { throw 'A corresponding Gate14Re-ME Unity process is already active.' }
$drive = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='$([System.IO.Path]::GetPathRoot($measuredRootFull).TrimEnd('\'))'"
$requiredReservation = [int64]$budget.qualificationReservedStorageBytes + [int64]$budget.formalRawAndDeliveryReservedStorageBytes
if ($null -eq $drive -or [int64]$drive.FreeSpace -lt $requiredReservation) { throw 'Host free space is below the sum of the two frozen reservations.' }

# Authorized creation boundary begins here.
New-Item -ItemType Directory -Path $measuredRootFull | Out-Null
foreach ($relative in @('_control', 'oracle', 'raw/superblocks', 'raw/empty-boundary', 'instruments')) {
    New-Item -ItemType Directory -Path (Join-Path $measuredRootFull $relative) | Out-Null
}
$processLedger = Join-Path $measuredRootFull '_control/process-ledger.raw.v1.jsonl'
$voidLedger = Join-Path $measuredRootFull '_control/failures-and-voids.raw.v1.jsonl'
$replacementLedger = Join-Path $measuredRootFull '_control/replacement-ledger.raw.v1.jsonl'
New-Item -ItemType File -Path $processLedger | Out-Null
New-Item -ItemType File -Path $voidLedger | Out-Null
New-Item -ItemType File -Path $replacementLedger | Out-Null
Write-JsonAtomic -Path (Join-Path $measuredRootFull '_control/launch-receipt.v1.json') -Value ([ordered]@{
    schema = 'gate14re-me-qualification-launch-receipt-v1'
    studyId = 'Gate14Re-ME'
    status = 'AUTHORIZED_QUALIFICATION_ACQUISITION_STARTED'
    executionAuthorizationSha256 = $ExecutionAuthorizationSha256
    implementationManifestSha256 = $ImplementationManifestSha256
    resourceBudgetSha256 = $ResourceBudgetSha256
    fairnessBindingSha256 = $FairnessBindingSha256
    scheduleSha256 = $ScheduleSha256
    unityExecutableSha256 = $UnityExecutableSha256
    startedAtUtc = [DateTime]::UtcNow.ToString('o')
})

Invoke-FreshUnityProcess -Mode 'instrument-self-test' -OutputDirectory (Join-Path $measuredRootFull 'instruments/csharp') -AdditionalArguments @() -TimeoutMilliseconds $budget.instrumentProcessHardTimeoutMilliseconds
Assert-Receipt -Path (Join-Path $measuredRootFull 'instruments/csharp/instrument-csharp-receipt.v1.json') -ExpectedStatus 'PASS_CSHARP_INSTRUMENT_COMPONENTS_PYTHON_ROUNDTRIP_PENDING' | Out-Null

foreach ($record in $records) {
    $inputFull = Get-NormalizedFullPath -Path $record.inputRelativePath -Base $projectRootFull
    $oracleOutput = Join-Path $measuredRootFull "oracle/$($record.superblockId)"
    Invoke-FreshUnityProcess -Mode 'oracle' -OutputDirectory $oracleOutput -AdditionalArguments @('--g14me-input', $inputFull) -TimeoutMilliseconds $budget.oracleInputHardTimeoutMilliseconds
    Assert-Receipt -Path (Join-Path $oracleOutput 'oracle-pass-receipt.v1.json') -ExpectedStatus 'PASS_ALGORITHM_NEUTRAL_GEOMETRY' | Out-Null
}

for ($ordinal = 0; $ordinal -lt 12; $ordinal++) {
    $emptyOutput = Join-Path $measuredRootFull "raw/empty-boundary/process-$('{0:D2}' -f $ordinal)"
    Invoke-FreshUnityProcess -Mode 'empty-boundary' -OutputDirectory $emptyOutput -AdditionalArguments @('--g14me-process-ordinal', "$ordinal") -TimeoutMilliseconds $budget.emptyBoundaryProcessHardTimeoutMilliseconds
    Assert-Receipt -Path (Join-Path $emptyOutput 'empty-boundary-receipt.v1.json') -ExpectedStatus 'COMPLETE_EMPTY_BOUNDARY_RAW' | Out-Null
}

foreach ($record in $records) {
    $inputFull = Get-NormalizedFullPath -Path $record.inputRelativePath -Base $projectRootFull
    $complete = Invoke-Superblock -Record $record -InputFull $inputFull -InputSha256 $record.inputSha256 -PlannedSuperblockId $record.superblockId -InstanceId $record.superblockId -IsReplacement $false
    if (-not $complete) {
        if ($null -eq $record.replacement) { throw "Superblock failed without a frozen replacement: $($record.superblockId)" }
        Append-JsonLine -Path $replacementLedger -Value ([ordered]@{
            schema = 'gate14re-me-whole-superblock-replacement-row-v1'
            recordId = "replacement:$($record.superblockId)"
            plannedSuperblockId = $record.superblockId
            replacementSuperblockId = $record.replacement.superblockId
            replacementOrdinal = 1
            reason = 'WHOLE_SUPERBLOCK_TECHNICAL_REPLACEMENT'
            createdAtUtc = [DateTime]::UtcNow.ToString('o')
        })
        $replacementInputFull = Get-NormalizedFullPath -Path $record.replacement.inputRelativePath -Base $projectRootFull
        $replacementOracleOutput = Join-Path $measuredRootFull "oracle/$($record.replacement.superblockId)"
        Invoke-FreshUnityProcess -Mode 'oracle' -OutputDirectory $replacementOracleOutput -AdditionalArguments @('--g14me-input', $replacementInputFull) -TimeoutMilliseconds $budget.oracleInputHardTimeoutMilliseconds
        Assert-Receipt -Path (Join-Path $replacementOracleOutput 'oracle-pass-receipt.v1.json') -ExpectedStatus 'PASS_ALGORITHM_NEUTRAL_GEOMETRY' | Out-Null
        $replacementRecord = [pscustomobject]@{
            superblockId = $record.replacement.superblockId
            algorithmOrder = $record.algorithmOrder
        }
        $replacementComplete = Invoke-Superblock -Record $replacementRecord -InputFull $replacementInputFull -InputSha256 $record.replacement.inputSha256 -PlannedSuperblockId $record.superblockId -InstanceId $record.replacement.superblockId -IsReplacement $true
        if (-not $replacementComplete) { throw "The single whole-superblock replacement also failed: $($record.superblockId)" }
    }
}

Write-JsonAtomic -Path (Join-Path $measuredRootFull '_control/acquisition-complete.v1.json') -Value ([ordered]@{
    schema = 'gate14re-me-qualification-acquisition-complete-v1'
    studyId = 'Gate14Re-ME'
    status = 'QUALIFICATION-RAW-COMMIT-PENDING'
    plannedSuperblocks = 162
    plannedAlgorithmLanes = 972
    formalCollectionAuthorized = $false
    formalAnalysisAuthorized = $false
    completedAtUtc = [DateTime]::UtcNow.ToString('o')
})
