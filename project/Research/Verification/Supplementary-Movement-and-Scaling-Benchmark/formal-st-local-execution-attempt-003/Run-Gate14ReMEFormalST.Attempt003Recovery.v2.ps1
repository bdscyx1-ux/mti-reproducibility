[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$ProjectRoot,
    [Parameter(Mandatory = $true)][string]$MeasuredRoot,
    [Parameter(Mandatory = $true)][string]$RecoveryAuthorization,
    [Parameter(Mandatory = $true)][ValidatePattern('^[0-9a-f]{64}$')][string]$RecoveryAuthorizationSha256,
    [Parameter(Mandatory = $true)][string]$ExecutionAuthorization,
    [Parameter(Mandatory = $true)][ValidatePattern('^[0-9a-f]{64}$')][string]$ExecutionAuthorizationSha256,
    [Parameter(Mandatory = $true)][string]$ImplementationManifest,
    [Parameter(Mandatory = $true)][ValidatePattern('^[0-9a-f]{64}$')][string]$ImplementationManifestSha256,
    [Parameter(Mandatory = $true)][string]$ExecutionContract,
    [Parameter(Mandatory = $true)][ValidatePattern('^[0-9a-f]{64}$')][string]$ExecutionContractSha256,
    [Parameter(Mandatory = $true)][string]$InputFreezeManifest,
    [Parameter(Mandatory = $true)][ValidatePattern('^[0-9a-f]{64}$')][string]$InputFreezeManifestSha256,
    [Parameter(Mandatory = $true)][string]$ResourceBudget,
    [Parameter(Mandatory = $true)][ValidatePattern('^[0-9a-f]{64}$')][string]$ResourceBudgetSha256,
    [Parameter(Mandatory = $true)][string]$FairnessBinding,
    [Parameter(Mandatory = $true)][ValidatePattern('^[0-9a-f]{64}$')][string]$FairnessBindingSha256,
    [Parameter(Mandatory = $true)][string]$Schedule,
    [Parameter(Mandatory = $true)][ValidatePattern('^[0-9a-f]{64}$')][string]$ScheduleSha256,
    [Parameter(Mandatory = $true)][string]$TrustedIdentityRule,
    [Parameter(Mandatory = $true)][ValidatePattern('^[0-9a-f]{64}$')][string]$TrustedIdentityRuleSha256,
    [Parameter(Mandatory = $true)][string]$TimestampComparator,
    [Parameter(Mandatory = $true)][ValidatePattern('^[0-9a-f]{64}$')][string]$TimestampComparatorSha256,
    [Parameter(Mandatory = $true)][string]$UnityExecutable,
    [Parameter(Mandatory = $true)][ValidatePattern('^[0-9a-f]{64}$')][string]$UnityExecutableSha256,
    [switch]$PreflightOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ErrorView = 'DetailedView'

$studyId = 'Gate14Re-ME'
$runnerMethod = 'DDM.Research.Editor.Gate14ReMEFormalSTRunnerV5_1.Run'
$originalSupervisorRelativePath = 'Research/Gate14Re-ME/Execution/v5_3/Run-Gate14ReMEFormalST.v5_3.ps1'
$originalSupervisorExpectedSha256 = 'fcfbc5c080e714c3c3e079797195b455d9a32db29e937ccb37768a34a3cbdda1'
$recoveryAuthorizationSchema = 'gate14re-me-formal-st-attempt-003-recovery-authorization-v2'
$recoveryStartOrdinal = 7519
$recoveredLedgerOrdinal = 7518
$recoveredSuperblockOrdinal = 1241
$firstNewSuperblockOrdinal = 1242
$plannedFreshProcesses = 7843
$remainingNewUnityProcesses = 324
$chunkSizeBytes = 65536
$processOrdinal = $recoveryStartOrdinal
$measuredRootCreated = $false
$currentMode = 'RECOVERY_PREFLIGHT'

function Read-JsonLinesShared {
    param([string]$Path)
    $values = [System.Collections.Generic.List[object]]::new()
    $stream = [System.IO.FileStream]::new(
        $Path,
        [System.IO.FileMode]::Open,
        [System.IO.FileAccess]::Read,
        [System.IO.FileShare]::ReadWrite -bor [System.IO.FileShare]::Delete)
    try {
        $reader = [System.IO.StreamReader]::new($stream, [System.Text.UTF8Encoding]::new($false), $true)
        try {
            while (-not $reader.EndOfStream) {
                $line = $reader.ReadLine()
                if (-not [string]::IsNullOrWhiteSpace($line)) {
                    $values.Add(($line | ConvertFrom-Json -Depth 100 -DateKind String))
                }
            }
        }
        finally { $reader.Dispose() }
    }
    finally { $stream.Dispose() }
    return @($values)
}

function Import-FrozenSupervisorFunctions {
    param([string]$Path)
    $tokens = $null
    $errors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$tokens, [ref]$errors)
    if (@($errors).Count -ne 0) {
        throw [System.InvalidOperationException]::new('Frozen v5.3 supervisor cannot be parsed for function import.')
    }
    $functions = @($ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true))
    if ($functions.Count -lt 20) {
        throw [System.InvalidOperationException]::new('Frozen v5.3 supervisor function inventory is unexpectedly incomplete.')
    }
    return @($functions | ForEach-Object { $_.Extent.Text })
}

function Assert-ProcessLedgerPrefix {
    param([object[]]$Rows, [int]$ExpectedCount)
    Require-Condition ($Rows.Count -eq $ExpectedCount) "Process ledger row count mismatch: expected $ExpectedCount; actual $($Rows.Count)."
    for ($index = 0; $index -lt $Rows.Count; $index++) {
        $row = $Rows[$index]
        Require-Condition (
            [string]$row.schema -ceq 'gate14re-me-formal-st-process-ledger-row-v5' -and
            [int]$row.ordinal -eq $index -and
            [string]$row.state -ceq 'EXITED_ZERO_TRUSTED_IDENTITY' -and
            [int]$row.exitCode -eq 0
        ) "Process ledger trust/ordinal invariant failed at row $index."
    }
}

function Assert-IdentityReceipt {
    param([string]$Path, [int]$Ordinal, [string]$Mode)
    $receipt = Read-Json -Path $Path
    Require-Condition (
        [string]$receipt.schema -ceq 'gate14re-me-formal-st-qualified-unity-process-identity-receipt-v5' -and
        [string]$receipt.status -ceq 'PASS_TRUSTED_THREE_PHASE_COMPOSITE_IDENTITY_NATURAL_EXIT' -and
        [int]$receipt.ordinal -eq $Ordinal -and
        [string]$receipt.mode -ceq $Mode -and
        [int]$receipt.exitCode -eq 0 -and
        [bool]$receipt.naturalExit -and
        -not [bool]$receipt.signalOrForcedTerminationSent -and
        -not [bool]$receipt.retryPerformed -and
        [string]$receipt.executeMethod -ceq $script:runnerMethod
    ) "Identity receipt is not a trusted natural zero exit for ordinal $Ordinal."
    return $receipt
}

function Assert-RecoveredSuperblockComplete {
    param([object]$Record, [string]$ExpectedAcceptedReceiptSha256)
    Require-Condition ([int]$Record.ordinal -eq $script:recoveredSuperblockOrdinal) 'Recovery superblock ordinal mismatch.'
    $superblockRoot = Join-Path $script:measuredRootFull "raw/superblocks/$($Record.superblockId)"
    Require-Condition (Test-Path -LiteralPath $superblockRoot -PathType Container) 'Recovery superblock output root is missing.'
    $acceptedPath = Join-Path $superblockRoot 'accepted-superblock-receipt.v1.json'
    Assert-Hash -Path $acceptedPath -Expected $ExpectedAcceptedReceiptSha256 -Label 'v1 recovered superblock accepted receipt'
    $accepted = Assert-Receipt -Path $acceptedPath -ExpectedStatus 'ACCEPTED_COMPLETE_SIX_LANE_SUPERBLOCK'
    Require-Condition (
        [string]$accepted.plannedSuperblockId -ceq [string]$Record.superblockId -and
        [int]$accepted.acceptedAnonymousLanes -eq 6 -and
        -not [bool]$accepted.isReplacement
    ) 'The v1 recovered superblock accepted receipt differs from the authorized v2 boundary.'
    return $acceptedPath
}

function Assert-NoProcessArtifactsAtOrdinal {
    param([int]$Ordinal)
    $identityPath = Join-Path $script:processIdentityRoot ('process-{0:D4}.identity.v5.json' -f $Ordinal)
    $unityLogPath = Join-Path $script:unityLogRoot ('process-{0:D4}.unity.log' -f $Ordinal)
    $lifecyclePattern = 'process-{0:D4}.*.json' -f $Ordinal
    Require-Condition (-not (Test-Path -LiteralPath $identityPath)) "Unexpected identity receipt exists for not-yet-created process ordinal $Ordinal."
    Require-Condition (-not (Test-Path -LiteralPath $unityLogPath)) "Unexpected Unity log exists for not-yet-created process ordinal $Ordinal."
    Require-Condition (@(Get-ChildItem -LiteralPath $script:processLifecycleRoot -File -Filter $lifecyclePattern).Count -eq 0) "Unexpected lifecycle receipt exists for not-yet-created process ordinal $Ordinal."
}

function Invoke-RecoverySuperblockFromExistingEmptyRoot {
    param([object]$Record, [string]$InputFull)
    Require-Condition ([int]$Record.ordinal -eq $script:firstNewSuperblockOrdinal) 'Recovery v2 existing-root execution is restricted to schedule ordinal 1242.'
    Require-Condition ([string]$Record.superblockId -ceq 'formal-sb-1242') 'Recovery v2 existing-root execution is restricted to formal-sb-1242.'
    $superblockRoot = Join-Path $script:measuredRootFull "raw/superblocks/$($Record.superblockId)"
    Require-Condition (Test-Path -LiteralPath $superblockRoot -PathType Container) "Recovery v2 requires the preserved empty superblock root: $superblockRoot"
    $superblockRootItem = Get-Item -LiteralPath $superblockRoot -Force
    Require-Condition (-not [bool]($superblockRootItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint)) "Recovery v2 refuses a reparse-point superblock root: $superblockRoot"
    Require-Condition (@(Get-ChildItem -LiteralPath $superblockRoot -Force).Count -eq 0) "Recovery v2 superblock root is not empty: $superblockRoot"
    try {
        foreach ($lane in $Record.algorithmOrder) {
            $laneOutput = Join-Path $superblockRoot ([string]$lane.anonymousLaneId)
            $cacheBindingReceipt = Join-Path $script:measuredRootFull "oracle/$($Record.superblockId)/oracle-cache-binding-receipt.v5.json"
            $cacheBinding = Assert-Receipt -Path $cacheBindingReceipt -ExpectedStatus 'PASS_FROZEN_ALGORITHM_NEUTRAL_ORACLE_CACHE_V5'
            Require-Condition ([int]$cacheBinding.scheduleOrdinal -eq [int]$Record.ordinal -and [string]$cacheBinding.superblockId -ceq [string]$Record.superblockId) 'Oracle cache binding does not match the scheduled superblock.'
            $cacheBindingReceiptSha = Get-Sha256Lower -Path $cacheBindingReceipt
            Invoke-VerifiedFreshUnityProcess -Mode 'lane' -OutputDirectory $laneOutput -TimeoutMilliseconds ([int64]$script:budget.laneWallClockHardTimeoutMilliseconds) -AdditionalArguments @(
                '--g14me-input', $InputFull,
                '--g14me-oracle-cache-binding', $cacheBindingReceipt,
                '--g14me-oracle-cache-binding-sha256', $cacheBindingReceiptSha,
                '--g14me-algorithm-id', [string]$lane.algorithmId,
                '--g14me-anonymous-lane-id', [string]$lane.anonymousLaneId,
                '--g14me-identity-binding-sha256', [string]$lane.identityBindingSha256
            )
            $null = Assert-Receipt -Path (Join-Path $laneOutput 'lane-receipt.v5.json') -ExpectedStatus 'COMPLETE_RAW_FORMAL_ST_LANE'
            $cacheLink = Assert-Receipt -Path (Join-Path $laneOutput 'lane-oracle-cache-link.v5.json') -ExpectedStatus 'BOUND_TO_FROZEN_ALGORITHM_NEUTRAL_ORACLE_CACHE_V5'
            Require-Condition ([int]$cacheLink.referenceOracleEvaluationsPerformedInsideLane -eq 0 -and [string]$cacheLink.oracleCacheBindingSha256 -ceq $cacheBindingReceiptSha) 'Lane did not prove zero reference-oracle evaluation and exact cache binding.'
        }
        Write-JsonExclusive -Path (Join-Path $superblockRoot 'accepted-superblock-receipt.v1.json') -Value ([ordered]@{
            schema = 'gate14re-me-formal-st-accepted-superblock-receipt-v5'
            studyId = $script:studyId
            status = 'ACCEPTED_COMPLETE_SIX_LANE_SUPERBLOCK'
            plannedSuperblockId = [string]$Record.superblockId
            instanceId = [string]$Record.superblockId
            isReplacement = $false
            acceptedAnonymousLanes = 6
            createdAtUtc = [DateTime]::UtcNow.ToString('o')
        })
    }
    catch {
        Append-JsonLine -Path $script:voidLedger -Value ([ordered]@{
            schema = 'gate14re-me-formal-st-whole-superblock-void-row-v5'
            recordId = "void:$($Record.superblockId):$($Record.superblockId):recovery-v2:$([DateTime]::UtcNow.ToString('yyyyMMddTHHmmssfffffffZ'))"
            plannedSuperblockId = [string]$Record.superblockId
            instanceId = [string]$Record.superblockId
            isReplacement = $false
            status = 'VOID_WHOLE_SUPERBLOCK_TECHNICAL_FAILURE'
            reason = $_.Exception.Message
            createdAtUtc = [DateTime]::UtcNow.ToString('o')
        })
        throw [System.InvalidOperationException]::new("Whole superblock failed during authorized recovery v2; no automatic retry: $($Record.superblockId). $($_.Exception.Message)")
    }
}

function Write-RecoveryTerminalArtifacts {
    $processRows = @(Read-JsonLinesShared -Path $script:processLedger)
    Assert-ProcessLedgerPrefix -Rows $processRows -ExpectedCount $script:plannedFreshProcesses
    $voidRows = @(Read-JsonLinesShared -Path $script:voidLedger)
    Require-Condition ($voidRows.Count -eq 2) 'Recovery v2 terminal requires exactly the two preserved technical-failure rows.'
    Require-Condition (
        [string]$voidRows[0].schema -ceq 'gate14re-me-formal-st-whole-superblock-void-row-v5' -and
        [string]$voidRows[0].plannedSuperblockId -ceq 'formal-sb-1241' -and
        [string]$voidRows[0].status -ceq 'VOID_WHOLE_SUPERBLOCK_TECHNICAL_FAILURE' -and
        [string]$voidRows[1].schema -ceq 'gate14re-me-formal-st-whole-superblock-void-row-v5' -and
        [string]$voidRows[1].plannedSuperblockId -ceq 'formal-sb-1242' -and
        [string]$voidRows[1].status -ceq 'VOID_WHOLE_SUPERBLOCK_TECHNICAL_FAILURE'
    ) 'Preserved technical-failure rows differ from the authorized recovery v2 boundary.'
    Require-Condition (Test-Path -LiteralPath (Join-Path $script:measuredRootFull '_control/failure-resolution.v1.json') -PathType Leaf) 'Recovery v1 resolution receipt is missing at terminal.'
    Require-Condition (Test-Path -LiteralPath (Join-Path $script:measuredRootFull '_control/failure-resolution.v2.json') -PathType Leaf) 'Recovery v2 resolution receipt is missing at terminal.'
    Require-Condition ((Get-Item -LiteralPath $script:replacementLedger).Length -eq 0) 'Replacement ledger is non-empty under the no-replacement recovery boundary.'
    Write-JsonExclusive -Path (Join-Path $script:measuredRootFull '_control/acquisition-complete.v5.json') -Value ([ordered]@{
        schema = 'gate14re-me-formal-st-acquisition-complete-v5'
        studyId = $script:studyId
        status = 'FORMAL_ST_ACQUISITION_COMPLETE_RAW_ACCEPTANCE_PENDING_AUTHORIZED_CONTROL_PLANE_RECOVERY'
        plannedSuperblocks = 1296
        acceptedSuperblocks = 1296
        plannedAlgorithmLanes = 7776
        acceptedAlgorithmLanes = 7776
        plannedOracleBatches = 54
        completedOracleBatches = 54
        algorithmNeutralOracleCaches = 1296
        laneReferenceOracleEvaluations = 0
        unityProcessCount = $script:plannedFreshProcesses
        wholeSuperblockReplacements = 0
        preservedTechnicalFailureRows = 2
        resolvedControlPlaneFailures = 2
        reconstructedLedgerRows = 1
        resumedNewUnityProcesses = $script:remainingNewUnityProcesses
        replayedAlgorithmLanes = 0
        recoveryAuthorizationSha256 = $script:RecoveryAuthorizationSha256
        formalCollectionAuthorized = $true
        formalAnalysisAuthorized = $false
        formalSTTerminalPass = $false
        independentReadOnlyOfflineAcceptanceRequired = $true
        rankingOrWinnerComputed = $false
        completedAtUtc = [DateTime]::UtcNow.ToString('o')
    })
    Write-JsonExclusive -Path (Join-Path $script:measuredRootFull '_control/acceptance-pending.v5.json') -Value ([ordered]@{
        schema = 'gate14re-me-formal-st-acceptance-pending-v5'
        studyId = $script:studyId
        status = 'SEALED_RAW_REQUIRES_NEW_READ_ONLY_OFFLINE_ACCEPTANCE_AFTER_AUTHORIZED_CONTROL_PLANE_RECOVERY'
        sourceMutationPermitted = $false
        formalSTTerminalPass = $false
        recoveryAuthorizationSha256 = $script:RecoveryAuthorizationSha256
        preservedTechnicalFailureRows = 2
        duplicateCanonicalJsonlRequired = $false
        csvRequired = $false
        gzipRequired = $false
        typedParquetFullRoundTripRequired = $true
        createdAtUtc = [DateTime]::UtcNow.ToString('o')
    })
    $freezeManifestPath = Join-Path $script:measuredRootFull '_control/acquisition-freeze-manifest.v5.json'
    Write-AcquisitionFreezeManifest -Root $script:measuredRootFull -Path $freezeManifestPath
    $freezeManifestSha256 = Get-Sha256Lower -Path $freezeManifestPath
    Write-JsonExclusive -Path (Join-Path $script:measuredRootFull '_control/acquisition-terminal-receipt.v5.json') -Value ([ordered]@{
        schema = 'gate14re-me-formal-st-acquisition-terminal-receipt-v5'
        studyId = $script:studyId
        status = 'PASS_ACQUISITION_ONLY_WITH_AUTHORIZED_CONTROL_PLANE_RECOVERY_RAW_FROZEN_ACCEPTANCE_PENDING'
        acquisitionFreezeManifestSha256 = $freezeManifestSha256
        recoveryAuthorizationSha256 = $script:RecoveryAuthorizationSha256
        plannedFreshProcesses = $script:plannedFreshProcesses
        completedFreshProcesses = $script:plannedFreshProcesses
        preservedTechnicalFailureRows = 2
        resolvedControlPlaneFailures = 2
        reconstructedLedgerRows = 1
        resumedNewUnityProcesses = $script:remainingNewUnityProcesses
        replayedAlgorithmLanes = 0
        formalSTTerminalPass = $false
        formalCollectionPerformed = $true
        formalAnalysisPerformed = $false
        rankingOrWinnerComputed = $false
        completedAtUtc = [DateTime]::UtcNow.ToString('o')
    })
}

$bootstrapProjectRoot = [System.IO.Path]::GetFullPath($ProjectRoot).TrimEnd([System.IO.Path]::DirectorySeparatorChar)
$bootstrapOriginalSupervisor = Join-Path $bootstrapProjectRoot $originalSupervisorRelativePath.Replace('/', [System.IO.Path]::DirectorySeparatorChar)
if (-not (Test-Path -LiteralPath $bootstrapOriginalSupervisor -PathType Leaf)) {
    throw [System.IO.FileNotFoundException]::new('Frozen v5.3 supervisor source is missing.', $bootstrapOriginalSupervisor)
}
$bootstrapOriginalHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $bootstrapOriginalSupervisor).Hash.ToLowerInvariant()
if ($bootstrapOriginalHash -ne $originalSupervisorExpectedSha256) {
    throw [System.InvalidOperationException]::new("Frozen v5.3 supervisor hash mismatch: $bootstrapOriginalHash")
}
$frozenFunctionDefinitions = @(Import-FrozenSupervisorFunctions -Path $bootstrapOriginalSupervisor)
foreach ($functionDefinition in $frozenFunctionDefinitions) {
    Invoke-Expression $functionDefinition
}

# Recovery preflight. The imported functions are the exact frozen v5.3 process,
# lifecycle, fingerprint, and superblock implementations; only orchestration is amended.
$projectRootFull = Get-NormalizedFullPath -Path $ProjectRoot -Base (Get-Location).Path
$measuredRootFull = Get-NormalizedFullPath -Path $MeasuredRoot -Base $projectRootFull
Assert-InsideProject -Path $measuredRootFull -Root $projectRootFull -Label 'Measured root'
Require-Condition (Test-Path -LiteralPath $measuredRootFull -PathType Container) 'Attempt-003 measured root is missing.'
$measuredRootCreated = $true
$processIdentityRoot = Join-Path $measuredRootFull '_control/process-identities'
$processLifecycleRoot = Join-Path $measuredRootFull '_control/process-lifecycle'
$unityLogRoot = Join-Path $measuredRootFull '_control/unity-logs'
$processLedger = Join-Path $measuredRootFull '_control/process-ledger.raw.v5.jsonl'
$voidLedger = Join-Path $measuredRootFull '_control/failures-and-voids.raw.v5.jsonl'
$replacementLedger = Join-Path $measuredRootFull '_control/replacement-ledger.raw.v5.jsonl'

$bindings = @(
    @{ Variable = 'recoveryAuthorizationFull'; Path = $RecoveryAuthorization; Hash = $RecoveryAuthorizationSha256; Label = 'attempt-003 recovery authorization' },
    @{ Variable = 'authorizationFull'; Path = $ExecutionAuthorization; Hash = $ExecutionAuthorizationSha256; Label = 'original execution authorization' },
    @{ Variable = 'manifestFull'; Path = $ImplementationManifest; Hash = $ImplementationManifestSha256; Label = 'original implementation manifest' },
    @{ Variable = 'executionContractFull'; Path = $ExecutionContract; Hash = $ExecutionContractSha256; Label = 'original acquisition contract' },
    @{ Variable = 'inputFreezeManifestFull'; Path = $InputFreezeManifest; Hash = $InputFreezeManifestSha256; Label = 'input freeze manifest' },
    @{ Variable = 'budgetFull'; Path = $ResourceBudget; Hash = $ResourceBudgetSha256; Label = 'operational resource budget' },
    @{ Variable = 'fairnessFull'; Path = $FairnessBinding; Hash = $FairnessBindingSha256; Label = 'fairness binding' },
    @{ Variable = 'scheduleFull'; Path = $Schedule; Hash = $ScheduleSha256; Label = 'schedule' },
    @{ Variable = 'identityRuleFull'; Path = $TrustedIdentityRule; Hash = $TrustedIdentityRuleSha256; Label = 'trusted Unity identity rule' },
    @{ Variable = 'timestampComparatorFull'; Path = $TimestampComparator; Hash = $TimestampComparatorSha256; Label = 'timestamp comparator' },
    @{ Variable = 'unityFull'; Path = $UnityExecutable; Hash = $UnityExecutableSha256; Label = 'Unity executable' }
)
foreach ($binding in $bindings) {
    $full = Get-NormalizedFullPath -Path ([string]$binding.Path) -Base $projectRootFull
    Set-Variable -Scope Script -Name ([string]$binding.Variable) -Value $full
    Assert-Hash -Path $full -Expected ([string]$binding.Hash) -Label ([string]$binding.Label)
}
. $timestampComparatorFull
Require-Condition ($null -ne (Get-Command Compare-Gate14ReMETrustedTimestampV1 -ErrorAction SilentlyContinue)) 'Timestamp comparator function did not load for recovery v2.'

$recoveryAuthorizationDocument = Read-Json -Path $recoveryAuthorizationFull
Require-Condition (
    [string]$recoveryAuthorizationDocument.schema -ceq $recoveryAuthorizationSchema -and
    [string]$recoveryAuthorizationDocument.studyId -ceq $studyId -and
    [string]$recoveryAuthorizationDocument.status -ceq 'AUTHORIZED_ATTEMPT_003_RECOVERY_V2_PREPARATION_AND_COMMAND_GATED_CONTINUATION' -and
    [string]$recoveryAuthorizationDocument.measuredRootRelativePath -ceq (Get-ProjectRelativePath -Path $measuredRootFull -Root $projectRootFull) -and
    [int]$recoveryAuthorizationDocument.recoveryPlan.processLedgerRowsAtV2Boundary -eq $recoveryStartOrdinal -and
    [int]$recoveryAuthorizationDocument.recoveryPlan.resumeFirstNewOrdinal -eq $recoveryStartOrdinal -and
    [int]$recoveryAuthorizationDocument.recoveryPlan.resumeFirstNewSuperblockOrdinal -eq $firstNewSuperblockOrdinal -and
    [int]$recoveryAuthorizationDocument.recoveryPlan.remainingNewUnityProcesses -eq $remainingNewUnityProcesses -and
    [bool]$recoveryAuthorizationDocument.recoveryPlan.reusePreservedEmptySuperblockRootOrdinal1242 -and
    -not [bool]$recoveryAuthorizationDocument.recoveryPlan.rerunExistingAlgorithmLane -and
    -not [bool]$recoveryAuthorizationDocument.recoveryPlan.replacementPerformed -and
    -not [bool]$recoveryAuthorizationDocument.authorizationBoundary.formalAnalysisAuthorized -and
    -not [bool]$recoveryAuthorizationDocument.authorizationBoundary.mqAuthorized -and
    -not [bool]$recoveryAuthorizationDocument.authorizationBoundary.mtAuthorized
) 'Recovery authorization is absent, incomplete, or exceeds the requested collection-only boundary.'
$recoverySupervisorRelative = Get-ProjectRelativePath -Path $PSCommandPath -Root $projectRootFull
Require-Condition ([string]$recoveryAuthorizationDocument.recoverySupervisor.relativePath -ceq $recoverySupervisorRelative) 'Recovery authorization supervisor path mismatch.'
Assert-Hash -Path $PSCommandPath -Expected ([string]$recoveryAuthorizationDocument.recoverySupervisor.sha256) -Label 'attempt-003 recovery supervisor self-binding'

$authorization = Read-Json -Path $authorizationFull
$manifest = Read-Json -Path $manifestFull
$contract = Read-Json -Path $executionContractFull
$budget = Read-Json -Path $budgetFull
$identityRule = Read-Json -Path $identityRuleFull
Require-Condition (
    [string]$authorization.schema -ceq 'gate14re-me-formal-st-execution-authorization-v5' -and
    [string]$authorization.authorizationId -ceq 'gate14re-me-formal-st-local-attempt-003-4e2ed5bc-57ca-43ea-b143-81c942344904' -and
    [string]$authorization.authorizationNonce -ceq 'f858378c-c0ed-4664-b59b-94bb86cfe07a' -and
    [string]$authorization.measuredRootRelativePath -ceq (Get-ProjectRelativePath -Path $measuredRootFull -Root $projectRootFull) -and
    [string]$authorization.implementationManifestSha256 -ceq $ImplementationManifestSha256 -and
    [string]$authorization.executionContractSha256 -ceq $ExecutionContractSha256 -and
    [string]$authorization.inputFreezeManifestSha256 -ceq $InputFreezeManifestSha256 -and
    [string]$authorization.scheduleSha256 -ceq $ScheduleSha256 -and
    [bool]$authorization.formalCollectionAuthorized -and
    -not [bool]$authorization.formalAnalysisAuthorized
) 'Original attempt-003 execution authorization binding mismatch.'
Require-Condition ([string]$manifest.status -ceq 'FROZEN_FORMAL_ST_V5_IMPLEMENTATION_READY') 'Original implementation manifest status mismatch.'
Require-Condition ([string]$contract.status -ceq 'FROZEN_FORMAL_ST_V5_ACQUISITION_EXECUTION_REQUIRES_SEPARATE_AUTHORIZATION') 'Original acquisition contract status mismatch.'
foreach ($property in $contract.frozenBindings.PSObject.Properties) {
    $frozenFull = Get-NormalizedFullPath -Path ([string]$property.Value.relativePath) -Base $projectRootFull
    Assert-Hash -Path $frozenFull -Expected ([string]$property.Value.sha256) -Label "original frozen binding $($property.Name)"
}

$records = @(Get-Content -LiteralPath $scheduleFull -Encoding UTF8 | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | ForEach-Object { $_ | ConvertFrom-Json -Depth 100 -DateKind String })
Require-Condition ($records.Count -eq 1296) 'Frozen schedule does not contain exactly 1296 rows.'
for ($index = 0; $index -lt $records.Count; $index++) {
    Require-Condition ([int]$records[$index].ordinal -eq $index -and @($records[$index].algorithmOrder).Count -eq 6 -and $null -eq $records[$index].replacement) "Frozen schedule recovery invariant failed at row $index."
}

$launchReceiptPath = Join-Path $measuredRootFull '_control/launch-receipt.v2.json'
$failureReceiptPath = Join-Path $measuredRootFull '_control/failure-receipt.v2.json'
$recoveryV1StartPath = Join-Path $measuredRootFull '_control/recovery-start-receipt.v1.json'
$recoveryV1FailurePath = Join-Path $measuredRootFull '_control/recovery-failure-receipt.v1.json'
$recoveryV1ResolutionPath = Join-Path $measuredRootFull '_control/failure-resolution.v1.json'
$evidenceRootFull = Split-Path -Parent $recoveryAuthorizationFull
$recoveryV1AuthorizationPath = Join-Path $evidenceRootFull 'attempt-003-recovery-authorization.v1.json'
$recoveryV1SupervisorPath = Join-Path $evidenceRootFull 'Run-Gate14ReMEFormalST.Attempt003Recovery.v1.ps1'
$recoveryV1PreflightPath = Join-Path $evidenceRootFull 'recovery-preflight-receipt.v1.json'
$recoveryV1LaunchContractPath = Join-Path $evidenceRootFull 'recovery-launch-contract.v1.json'
$recoveryV1ExactConfirmationPath = Join-Path $evidenceRootFull 'recovery-exact-command-confirmation-receipt.v1.json'
Assert-Hash -Path $launchReceiptPath -Expected ([string]$recoveryAuthorizationDocument.priorRecoveryState.launchReceiptSha256) -Label 'original measured launch receipt'
Assert-Hash -Path $processLedger -Expected ([string]$recoveryAuthorizationDocument.priorRecoveryState.processLedgerSha256AtV2Boundary) -Label 'process ledger at recovery v2 boundary'
Assert-Hash -Path $failureReceiptPath -Expected ([string]$recoveryAuthorizationDocument.priorRecoveryState.originalFailureReceiptSha256) -Label 'original supervisor failure receipt'
Assert-Hash -Path $voidLedger -Expected ([string]$recoveryAuthorizationDocument.priorRecoveryState.failureLedgerSha256AtV2Boundary) -Label 'failure ledger at recovery v2 boundary'
Assert-Hash -Path $replacementLedger -Expected ([string]$recoveryAuthorizationDocument.priorRecoveryState.replacementLedgerSha256) -Label 'replacement ledger at recovery v2 boundary'
Assert-Hash -Path $recoveryV1StartPath -Expected ([string]$recoveryAuthorizationDocument.priorRecoveryState.recoveryV1StartReceiptSha256) -Label 'recovery v1 start receipt'
Assert-Hash -Path $recoveryV1FailurePath -Expected ([string]$recoveryAuthorizationDocument.priorRecoveryState.recoveryV1FailureReceiptSha256) -Label 'recovery v1 failure receipt'
Assert-Hash -Path $recoveryV1ResolutionPath -Expected ([string]$recoveryAuthorizationDocument.priorRecoveryState.recoveryV1ResolutionReceiptSha256) -Label 'recovery v1 failure resolution receipt'
Assert-Hash -Path $recoveryV1AuthorizationPath -Expected ([string]$recoveryAuthorizationDocument.priorRecoveryState.recoveryV1AuthorizationSha256) -Label 'recovery v1 authorization'
Assert-Hash -Path $recoveryV1SupervisorPath -Expected ([string]$recoveryAuthorizationDocument.priorRecoveryState.recoveryV1SupervisorSha256) -Label 'recovery v1 supervisor'
Assert-Hash -Path $recoveryV1PreflightPath -Expected ([string]$recoveryAuthorizationDocument.priorRecoveryState.recoveryV1PreflightReceiptSha256) -Label 'recovery v1 preflight receipt'
Assert-Hash -Path $recoveryV1LaunchContractPath -Expected ([string]$recoveryAuthorizationDocument.priorRecoveryState.recoveryV1LaunchContractSha256) -Label 'recovery v1 launch contract'
Assert-Hash -Path $recoveryV1ExactConfirmationPath -Expected ([string]$recoveryAuthorizationDocument.priorRecoveryState.recoveryV1ExactCommandConfirmationReceiptSha256) -Label 'recovery v1 exact-command confirmation receipt'
$recoveryV1Failure = Read-Json -Path $recoveryV1FailurePath
Require-Condition (
    [string]$recoveryV1Failure.status -ceq 'RECOVERY_FAILED_CLOSED_NO_AUTOMATIC_RETRY' -and
    [string]$recoveryV1Failure.failedMode -ceq 'lane' -and
    [int]$recoveryV1Failure.processOrdinal -eq 7520 -and
    [string]$recoveryV1Failure.exactFailure -like '*Compare-Gate14ReMETrustedTimestampV1*' -and
    -not [bool]$recoveryV1Failure.retryPerformed -and
    -not [bool]$recoveryV1Failure.replacementPerformed -and
    -not [bool]$recoveryV1Failure.formalAnalysisPerformed
) 'Recovery v1 failure receipt differs from the authorized prelaunch comparator-load failure.'
$failureReceipt = Read-Json -Path $failureReceiptPath
Require-Condition (
    [string]$failureReceipt.status -ceq 'FAILED_CLOSED_NO_RETRY_NO_REPLACEMENT' -and
    [string]$failureReceipt.failedMode -ceq 'lane' -and
    [int]$failureReceipt.unityProcessCount -eq $recoveryStartOrdinal -and
    -not [bool]$failureReceipt.retryPerformed -and
    -not [bool]$failureReceipt.replacementPerformed
) 'Original supervisor failure receipt differs from the authorized recovery boundary.'

$processRows = @(Read-JsonLinesShared -Path $processLedger)
Assert-ProcessLedgerPrefix -Rows $processRows -ExpectedCount $recoveryStartOrdinal
$voidRows = @(Read-JsonLinesShared -Path $voidLedger)
Require-Condition (
    $voidRows.Count -eq 2 -and
    [string]$voidRows[0].schema -ceq 'gate14re-me-formal-st-whole-superblock-void-row-v5' -and
    [string]$voidRows[0].recordId -ceq 'void:formal-sb-1241:formal-sb-1241' -and
    [string]$voidRows[0].plannedSuperblockId -ceq 'formal-sb-1241' -and
    [string]$voidRows[0].status -ceq 'VOID_WHOLE_SUPERBLOCK_TECHNICAL_FAILURE' -and
    [string]$voidRows[1].schema -ceq 'gate14re-me-formal-st-whole-superblock-void-row-v5' -and
    [string]$voidRows[1].recordId -ceq 'void:formal-sb-1242:formal-sb-1242' -and
    [string]$voidRows[1].status -ceq 'VOID_WHOLE_SUPERBLOCK_TECHNICAL_FAILURE' -and
    [string]$voidRows[1].plannedSuperblockId -ceq 'formal-sb-1242'
) 'Failure ledger differs from the authorized two-row recovery v2 boundary.'
Require-Condition ((Get-Item -LiteralPath $replacementLedger).Length -eq 0) 'Replacement ledger is not empty.'
$recoveredIdentityPath = Join-Path $processIdentityRoot ('process-{0:D4}.identity.v5.json' -f $recoveredLedgerOrdinal)
Assert-Hash -Path $recoveredIdentityPath -Expected ([string]$recoveryAuthorizationDocument.priorRecoveryState.recoveredIdentityReceiptSha256) -Label 'ordinal 7518 identity receipt'
$recoveredIdentity = Assert-IdentityReceipt -Path $recoveredIdentityPath -Ordinal $recoveredLedgerOrdinal -Mode 'lane'
$recoveredAcceptedPath = Assert-RecoveredSuperblockComplete -Record $records[$recoveredSuperblockOrdinal] -ExpectedAcceptedReceiptSha256 ([string]$recoveryAuthorizationDocument.priorRecoveryState.recoveredAcceptedSuperblockReceiptSha256)
$firstNewSuperblockRoot = Join-Path $measuredRootFull "raw/superblocks/$($records[$firstNewSuperblockOrdinal].superblockId)"
Require-Condition (Test-Path -LiteralPath $firstNewSuperblockRoot -PathType Container) 'The preserved formal-sb-1242 output root is missing.'
$firstNewSuperblockRootItem = Get-Item -LiteralPath $firstNewSuperblockRoot -Force
Require-Condition (-not [bool]($firstNewSuperblockRootItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint)) 'The preserved formal-sb-1242 output root is a reparse point.'
Require-Condition (@(Get-ChildItem -LiteralPath $firstNewSuperblockRoot -Force).Count -eq 0) 'The preserved formal-sb-1242 output root is not empty.'
Assert-NoProcessArtifactsAtOrdinal -Ordinal $recoveryStartOrdinal
for ($recordIndex = ($firstNewSuperblockOrdinal + 1); $recordIndex -lt $records.Count; $recordIndex++) {
    $futureRoot = Join-Path $measuredRootFull "raw/superblocks/$($records[$recordIndex].superblockId)"
    Require-Condition (-not (Test-Path -LiteralPath $futureRoot)) "Future recovery output already exists: $futureRoot"
}
foreach ($terminalName in @('recovery-start-receipt.v2.json', 'failure-resolution.v2.json', 'acquisition-complete.v5.json', 'acceptance-pending.v5.json', 'acquisition-freeze-manifest.v5.json', 'acquisition-terminal-receipt.v5.json', 'recovery-failure-receipt.v2.json')) {
    Require-Condition (-not (Test-Path -LiteralPath (Join-Path $measuredRootFull "_control/$terminalName"))) "Recovery/terminal artifact already exists: $terminalName"
}
Require-Condition (@(Get-CimInstance Win32_Process -Filter "Name = 'Unity.exe'").Count -eq 0) 'A Unity process is already active.'

$driveId = [System.IO.Path]::GetPathRoot($measuredRootFull).TrimEnd('\')
$drive = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='$driveId'"
$conservativeRemainingReservation = [int64]$budget.formalRawAndDeliveryReservedStorageBytes
Require-Condition ($null -ne $drive -and [int64]$drive.FreeSpace -ge $conservativeRemainingReservation) 'Host free space is below the full frozen acquisition reservation used as a conservative v2 continuation bound.'

if ($PreflightOnly) {
    [pscustomobject][ordered]@{
        schema = 'gate14re-me-formal-st-attempt-003-recovery-preflight-v2'
        studyId = $studyId
        status = 'PASS_READ_ONLY_RECOVERY_V2_PREFLIGHT_NO_MEASURED_ROOT_MUTATION'
        processLedgerRows = $processRows.Count
        lastCompletedOrdinal = $recoveredLedgerOrdinal
        resumeFirstNewOrdinal = $recoveryStartOrdinal
        resumeFirstNewSuperblockOrdinal = $firstNewSuperblockOrdinal
        remainingNewUnityProcesses = $remainingNewUnityProcesses
        priorRecoveredSuperblockId = [string]$records[$recoveredSuperblockOrdinal].superblockId
        preservedEmptySuperblockId = [string]$records[$firstNewSuperblockOrdinal].superblockId
        preservedEmptySuperblockEntryCount = 0
        preservedFailureRows = $voidRows.Count
        replacementRows = 0
        rerunExistingAlgorithmLane = $false
        firstNewUnityProcessHasNoPriorIdentityLifecycleOrLog = $true
        timestampComparatorLoaded = $true
        formalAnalysisAuthorized = $false
        rawAlgorithmObservationsInterpreted = $false
        checkedAtUtc = [DateTime]::UtcNow.ToString('o')
    } | ConvertTo-Json -Depth 20
    return
}

try {
    $currentMode = 'RECOVERY_V2_START'
    Write-JsonExclusive -Path (Join-Path $measuredRootFull '_control/recovery-start-receipt.v2.json') -Value ([ordered]@{
        schema = 'gate14re-me-formal-st-attempt-003-recovery-start-v2'
        studyId = $studyId
        status = 'AUTHORIZED_CONTROL_PLANE_RECOVERY_V2_STARTED'
        recoveryAuthorizationSha256 = $RecoveryAuthorizationSha256
        processLedgerRowsAtStart = $recoveryStartOrdinal
        lastCompletedOrdinal = $recoveredLedgerOrdinal
        resumeFirstNewOrdinal = $recoveryStartOrdinal
        resumeFirstNewSuperblockOrdinal = $firstNewSuperblockOrdinal
        remainingNewUnityProcesses = $remainingNewUnityProcesses
        timestampComparatorLoaded = $true
        rerunExistingAlgorithmLane = $false
        replacementPerformed = $false
        formalAnalysisAuthorized = $false
        startedAtUtc = [DateTime]::UtcNow.ToString('o')
    })
    Write-JsonExclusive -Path (Join-Path $measuredRootFull '_control/failure-resolution.v2.json') -Value ([ordered]@{
        schema = 'gate14re-me-formal-st-attempt-003-failure-resolution-v2'
        studyId = $studyId
        status = 'RESOLVED_BY_LOADING_FROZEN_TIMESTAMP_COMPARATOR_BEFORE_FIRST_NEW_UNITY_PROCESS'
        recoveryAuthorizationSha256 = $RecoveryAuthorizationSha256
        preservedFailureRecordId = [string]$voidRows[1].recordId
        preservedFailureLedgerSha256BeforeRecoveryV2 = [string]$recoveryAuthorizationDocument.priorRecoveryState.failureLedgerSha256AtV2Boundary
        failedSuperblockId = [string]$records[$firstNewSuperblockOrdinal].superblockId
        failedBeforeUnityProcessStart = $true
        unityProcessCreatedDuringRecoveryV1Continuation = $false
        algorithmObservationCreatedDuringRecoveryV1Continuation = $false
        failedOrdinalIdentityLifecycleOrLogCreated = $false
        failedSuperblockRootPreservedAndEmpty = $true
        reusedVerifiedEmptySuperblockRoot = $true
        fixedByDotSourcingFrozenTimestampComparator = $true
        resumeFirstNewOrdinal = $recoveryStartOrdinal
        rerunExistingAlgorithmLane = $false
        replacementPerformed = $false
        failureRowDeletedOrRewritten = $false
        formalAnalysisPerformed = $false
        resolvedAtUtc = [DateTime]::UtcNow.ToString('o')
    })

    $currentMode = 'lane'
    $processOrdinal = $recoveryStartOrdinal
    $firstRecord = $records[$firstNewSuperblockOrdinal]
    $firstInputFull = Get-NormalizedFullPath -Path ([string]$firstRecord.inputRelativePath) -Base $projectRootFull
    Assert-Hash -Path $firstInputFull -Expected ([string]$firstRecord.inputSha256) -Label "input $($firstRecord.superblockId)"
    Invoke-RecoverySuperblockFromExistingEmptyRoot -Record $firstRecord -InputFull $firstInputFull
    for ($recordIndex = ($firstNewSuperblockOrdinal + 1); $recordIndex -lt $records.Count; $recordIndex++) {
        $record = $records[$recordIndex]
        $inputFull = Get-NormalizedFullPath -Path ([string]$record.inputRelativePath) -Base $projectRootFull
        Assert-Hash -Path $inputFull -Expected ([string]$record.inputSha256) -Label "input $($record.superblockId)"
        Invoke-Superblock -Record $record -InputFull $inputFull
    }
    Require-Condition ($processOrdinal -eq $plannedFreshProcesses) "Terminal process ordinal mismatch: expected $plannedFreshProcesses; actual $processOrdinal."
    Write-RecoveryTerminalArtifacts
    Get-ChildItem -LiteralPath $measuredRootFull -File -Recurse | ForEach-Object { $_.IsReadOnly = $true }
}
catch {
    $failurePath = Join-Path $measuredRootFull '_control/recovery-failure-receipt.v2.json'
    if (-not (Test-Path -LiteralPath $failurePath)) {
        $trustedRowsAtFailure = @(Read-JsonLinesShared -Path $processLedger)
        Write-JsonExclusive -Path $failurePath -Value ([ordered]@{
            schema = 'gate14re-me-formal-st-attempt-003-recovery-failure-v2'
            studyId = $studyId
            status = 'RECOVERY_FAILED_CLOSED_NO_AUTOMATIC_RETRY'
            failedMode = $currentMode
            exactFailure = $_.Exception.Message
            exceptionType = $_.Exception.GetType().FullName
            inMemoryProcessOrdinal = $processOrdinal
            trustedCompletedProcessLedgerRows = $trustedRowsAtFailure.Count
            lastTrustedCompletedOrdinal = if ($trustedRowsAtFailure.Count -gt 0) { [int]$trustedRowsAtFailure[-1].ordinal } else { $null }
            recoveryAuthorizationSha256 = $RecoveryAuthorizationSha256
            retryPerformed = $false
            replacementPerformed = $false
            formalAnalysisPerformed = $false
            failedAtUtc = [DateTime]::UtcNow.ToString('o')
        })
    }
    throw
}


