[CmdletBinding(DefaultParameterSetName = 'Validate')]
param(
    [Parameter(Mandatory = $true, ParameterSetName = 'Validate')]
    [switch]$ValidateOnly,

    [Parameter(Mandatory = $true, ParameterSetName = 'Execute')]
    [switch]$Execute,

    [Parameter(Mandatory = $true, ParameterSetName = 'Execute')]
    [string]$AuthorizationPath,

    [Parameter(Mandatory = $true, ParameterSetName = 'Execute')]
    [ValidatePattern('^[0-9a-fA-F]{64}$')]
    [string]$AuthorizationSha256,

    [Parameter(ParameterSetName = 'Validate')]
    [string]$ValidationReceiptPath = 'H:\DDM_Final_Project\Research\Verification\Gate14Re\formal-executor-implementation-attempt-001\formal-supervisor-validation-only-attempt-002\validation-receipt.v1.json'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ProjectRoot = 'H:\DDM_Final_Project'
$PlanPath = Join-Path $ProjectRoot 'Research\Gate14Re\Execution\Gate14Re_Formal_Block_Plan.v1.json'
$ExecutionContractPath = Join-Path $ProjectRoot 'Research\Gate14Re\Execution\Gate14Re_Formal_Execution_Contract.v2.json'
$OutputSchemaPath = Join-Path $ProjectRoot 'Research\Gate14Re\Execution\Gate14Re_Formal_Block_Output_Schema.v2.json'
$BuildRoot = Join-Path $ProjectRoot 'Research\Verification\Gate14Re\formal-executor-implementation-attempt-001\standalone-build-attempt-003'
$ExecutablePath = Join-Path $BuildRoot 'Gate14ReFormalRunner.exe'
$AssemblyPath = Join-Path $BuildRoot 'Gate14ReFormalRunner_Data\Managed\Assembly-CSharp.dll'
$BuildReceiptPath = Join-Path $BuildRoot 'build-receipt.v2.json'
$BuildTreePath = Join-Path $ProjectRoot 'Research\Verification\Gate14Re\formal-executor-implementation-attempt-001\standalone-build-attempt-003.canonical-tree.v1.jsonl'
$BuildFreezeReceiptPath = Join-Path $ProjectRoot 'Research\Verification\Gate14Re\formal-executor-implementation-attempt-001\standalone-build-attempt-003.build-freeze-receipt.v1.json'
$ExpectedAuthorizationPath = Join-Path $ProjectRoot 'Research\Gate14Re\Execution\Gate14Re_Formal_PhaseA_Authorization.v2.json'
$FormalRoot = Join-Path $ProjectRoot 'Research\FormalRuns\Gate14Re\PhaseA\attempt-001'
$FormalAnalysisRoot = Join-Path $ProjectRoot 'Research\Analysis\Gate14Re'
$ProcessTimeoutSeconds = 3600

$PlanSha256 = '9d12fab76865477fed1742c1d51cc79eb57a06c2fcf40e0544f2045cfffd552d'
$ExecutionContractSha256 = '6309d031e00fcf53380e74343adff5863c88aa1c11cb72542cd352a2f19c2bd3'
$OutputSchemaSha256 = '0c248a4046df959bae078f360ba5d4dfc322d603dc0bdd8e920b492db11325c2'
$ExecutableSha256 = '88b1b04971f8b712ddd0f18bca4f7296d287fdd6cdadef57c155d37b9ef0928c'
$AssemblySha256 = '2f763a06d43a5777d6ce47cdba998d5482e82557ad35ee72f9e07dcd193b2961'
$BuildReceiptSha256 = 'd110c97ca2f2f3d5a38490497ebfcf714d976c75b2397a68d46787e29c51ec9a'
$BuildTreeSha256 = 'c4da85e66f9898834bc30b5e5618021458405f9a5962266c4d336479202abd46'
$BuildFreezeReceiptSha256 = '9df8bf66fa7df1d23e3454be5b23cdb99b907fa3e1848942b3845f56373c7199'

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}

function Get-Sha256Lower {
    param([string]$Path)
    return (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToLowerInvariant()
}

function Assert-FrozenFile {
    param([string]$Path, [string]$ExpectedSha256, [Nullable[long]]$ExpectedBytes = $null)
    Assert-True (Test-Path -LiteralPath $Path -PathType Leaf) ('Missing frozen file: ' + $Path)
    $item = Get-Item -LiteralPath $Path
    if ($null -ne $ExpectedBytes) { Assert-True ($item.Length -eq [long]$ExpectedBytes) ('Frozen file byte count mismatch: ' + $Path) }
    Assert-True ($item.IsReadOnly) ('Frozen file is not ReadOnly: ' + $Path)
    Assert-True ((Get-Sha256Lower $Path) -eq $ExpectedSha256) ('Frozen file SHA-256 mismatch: ' + $Path)
}

function Assert-BuildTree {
    Assert-FrozenFile $BuildTreePath $BuildTreeSha256 24433L
    Assert-FrozenFile $BuildFreezeReceiptPath $BuildFreezeReceiptSha256
    $rows = @(Get-Content -LiteralPath $BuildTreePath | ForEach-Object { $_ | ConvertFrom-Json })
    Assert-True ($rows.Count -eq 151) 'Frozen standalone build tree must contain exactly 151 files.'
    $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $rawBytes = 0L
    foreach ($row in $rows) {
        $relative = [string]$row.path
        Assert-True (-not [string]::IsNullOrWhiteSpace($relative)) 'Build-tree record has an empty path.'
        Assert-True ($seen.Add($relative)) ('Duplicate build-tree path: ' + $relative)
        $candidate = [IO.Path]::GetFullPath((Join-Path $BuildRoot ($relative.Replace('/', [IO.Path]::DirectorySeparatorChar))))
        $prefix = [IO.Path]::GetFullPath($BuildRoot).TrimEnd('\') + '\'
        Assert-True ($candidate.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) ('Build-tree path escapes build root: ' + $relative)
        Assert-FrozenFile $candidate ([string]$row.sha256) ([long]$row.bytes)
        $rawBytes += [long]$row.bytes
    }
    Assert-True ($rawBytes -eq 78057154L) 'Frozen standalone build raw-byte total mismatch.'
}

function Assert-ArrayEquals {
    param([object[]]$Actual, [object[]]$Expected, [string]$Label)
    Assert-True ($Actual.Count -eq $Expected.Count) ($Label + ' cardinality mismatch.')
    for ($index = 0; $index -lt $Expected.Count; $index++) {
        Assert-True ([string]$Actual[$index] -ceq [string]$Expected[$index]) ($Label + ' mismatch at index ' + $index)
    }
}

function Assert-Plan {
    param($Plan)
    Assert-True ($Plan.schema -ceq 'gate14re-formal-block-plan-v1') 'Formal plan schema mismatch.'
    Assert-True ($Plan.studyId -ceq 'Gate14Re' -and [int]$Plan.version -eq 1 -and $Plan.status -ceq 'FROZEN_NONEXECUTING') 'Formal plan header mismatch.'
    Assert-True ([int]$Plan.fixedB -eq 48 -and [int]$Plan.plannedValidProcesses -eq 1536) 'Formal plan B/process count mismatch.'
    $blocks = @($Plan.blocks)
    Assert-True ($blocks.Count -eq 1536) 'Formal plan must contain 1536 blocks.'
    $ids = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    for ($index = 0; $index -lt $blocks.Count; $index++) {
        $block = $blocks[$index]
        Assert-True ([int]$block.sequence -eq ($index + 1)) ('Non-contiguous block sequence at ' + ($index + 1))
        Assert-True ($ids.Add([string]$block.blockId)) ('Duplicate block id: ' + $block.blockId)
        Assert-True ([int]$block.blockIndex -ge 1 -and [int]$block.blockIndex -le 48) ('Invalid block index: ' + $block.blockId)
        Assert-True ([int]$block.williamsRow -eq ((([int]$block.blockIndex - 1) % 4) + 1)) ('Invalid Williams row: ' + $block.blockId)
        Assert-True ([int]$block.maximumWholeBlockReplacements -eq 1) ('Invalid replacement maximum: ' + $block.blockId)
        Assert-True ($block.lane -ceq 'movement' -or $block.lane -ceq 'm4') ('Invalid lane: ' + $block.blockId)
    }
    return $blocks
}

function Assert-BlockOutputObject {
    param($Output, $Block, [string]$AuthorizationId)
    Assert-True ($Output.schema -ceq 'gate14re-formal-block-output-v2') 'Block output schema mismatch.'
    Assert-True ($Output.studyId -ceq 'Gate14Re' -and $Output.status -ceq 'COMPLETE') 'Block output header mismatch.'
    Assert-True ($Output.blockId -ceq $Block.blockId -and [int]$Output.blockSequence -eq [int]$Block.sequence) 'Block output identity mismatch.'
    Assert-True ($Output.module -ceq $Block.module -and $Output.lane -ceq $Block.lane -and $Output.conditionId -ceq $Block.conditionId) 'Block output design-cell mismatch.'
    Assert-True ($Output.scenarioId -ceq $Block.scenarioId -and $Output.scenarioSha256 -ceq $Block.scenarioSha256) 'Block output scenario mismatch.'
    Assert-True ([int]$Output.unitCount -eq [int]$Block.unitCount -and [int]$Output.blockIndex -eq [int]$Block.blockIndex -and [int]$Output.williamsRow -eq [int]$Block.williamsRow) 'Block output N/index/order mismatch.'
    Assert-True ($Output.planSha256 -ceq $PlanSha256 -and $Output.executableSha256 -ceq $ExecutableSha256 -and $Output.assemblyCSharpSha256 -ceq $AssemblySha256 -and $Output.buildReceiptSha256 -ceq $BuildReceiptSha256) 'Block output build identity mismatch.'
    Assert-True ($Output.authorizationId -ceq $AuthorizationId) 'Block output authorization id mismatch.'
    Assert-True ([bool]$Output.completeFourAlgorithmBlock -and [bool]$Output.formalObservationProduced -and [bool]$Output.formalPhaseA) 'Block output completion flags are not affirmative.'

    $movement = @($Output.movement)
    $m4 = @($Output.m4)
    $expectedLabels = @($Block.algorithmLabelsInOrder)
    $expectedIds = @($Block.algorithmIdsInOrder)
    Assert-True ($expectedLabels.Count -eq 4 -and $expectedIds.Count -eq 4) 'Frozen block algorithm order is incomplete.'

    if ($Block.lane -ceq 'movement') {
        Assert-True ($movement.Count -eq 4 -and $m4.Count -eq 0) 'Movement block lane cardinality mismatch.'
        $minimum = [Math]::Max(1, [int][Math]::Ceiling(0.8 * [int]$Block.unitCount))
        $mask = @($Output.m2CommonMaskAgentIds)
        Assert-True ([int]$Output.m2CommonMaskMinimum -eq $minimum) 'M2 common-mask minimum mismatch.'
        Assert-True ($mask.Count -eq @($mask | Select-Object -Unique).Count) 'M2 common mask contains duplicate agent ids.'
        foreach ($agentId in $mask) { Assert-True ([int]$agentId -ge 0 -and [int]$agentId -lt [int]$Block.unitCount) 'M2 common-mask agent id is out of range.' }
        Assert-True ([bool]$Output.m2CommonMaskSufficient -eq ($mask.Count -ge $minimum)) 'M2 common-mask sufficiency flag mismatch.'
        for ($index = 0; $index -lt 4; $index++) {
            $sample = $movement[$index]
            Assert-True ($sample.algorithmLabel -ceq $expectedLabels[$index] -and $sample.productionAlgorithmId -ceq $expectedIds[$index] -and [int]$sample.orderPosition -eq ($index + 1)) 'Movement algorithm/order mismatch.'
            Assert-True ([int]$sample.unitCount -eq [int]$Block.unitCount) 'Movement unit count mismatch.'
            $units = @($sample.units)
            Assert-True ($units.Count -eq [int]$Block.unitCount) 'Movement per-unit record count mismatch.'
            $agentIds = @($units | ForEach-Object { [int]$_.agentId } | Sort-Object)
            for ($agent = 0; $agent -lt [int]$Block.unitCount; $agent++) { Assert-True ($agentIds[$agent] -eq $agent) 'Movement agent ids are not exactly 0..N-1.' }
            $terminalTotal = [int]$sample.arrivedCount + [int]$sample.activeAtCapCount + [int]$sample.noPathCount + [int]$sample.budgetExceededCount + [int]$sample.invalidPlanCount + [int]$sample.internalFailureCount
            Assert-True ($terminalTotal -eq [int]$Block.unitCount) 'Movement terminal counts do not sum to N.'
            Assert-True ([double]$sample.m1Seconds -ge 0.0 -and [double]$sample.m1Seconds -le 180.0) 'Movement M1 is outside the frozen range.'
            Assert-True ([int]$sample.m2CommonMaskCount -eq $mask.Count -and [bool]$sample.m2CommonMaskSufficient -eq [bool]$Output.m2CommonMaskSufficient) 'Movement M2 mask projection mismatch.'
            Assert-True (@($sample.structuralEvents).Count -le 5) 'Movement structural-event count exceeds the frozen sequence.'
        }
    }
    else {
        Assert-True ($movement.Count -eq 0 -and $m4.Count -eq 4) 'M4 block lane cardinality mismatch.'
        Assert-True ([int]$Output.m2CommonMaskMinimum -eq 0 -and @($Output.m2CommonMaskAgentIds).Count -eq 0 -and -not [bool]$Output.m2CommonMaskSufficient) 'M4 block contains an unexpected M2 mask.'
        for ($index = 0; $index -lt 4; $index++) {
            $sample = $m4[$index]
            Assert-True ($sample.algorithmLabel -ceq $expectedLabels[$index] -and $sample.productionAlgorithmId -ceq $expectedIds[$index] -and [int]$sample.orderPosition -eq ($index + 1)) 'M4 algorithm/order mismatch.'
            Assert-True ([int]$sample.unitCount -eq [int]$Block.unitCount -and [int]$sample.unitsWithEnabledRenderer -eq [int]$Block.unitCount) 'M4 full-population renderer count mismatch.'
            Assert-True ([int]$sample.warmupRenderedFrames -eq 600 -and [int]$sample.measuredRenderedFrameIntervals -eq 1800) 'M4 frame cardinality header mismatch.'
            $intervals = @($sample.frameIntervalsSeconds)
            Assert-True ($intervals.Count -eq 1800) 'M4 raw frame-interval count mismatch.'
            foreach ($interval in $intervals) { Assert-True ([double]$interval -gt 0.0) 'M4 contains a non-positive frame interval.' }
            Assert-True ([double]$sample.medianFrameTimeSeconds -gt 0.0 -and [double]$sample.nearestRankP95FrameTimeSeconds -gt 0.0) 'M4 summaries must be positive.'
            Assert-True (@($sample.structuralEvents).Count -le 5) 'M4 structural-event count exceeds the frozen sequence.'
        }
    }
}

function Assert-BlockOutputFile {
    param([string]$Path, $Block, [string]$AuthorizationId)
    Assert-True (Test-Path -LiteralPath $Path -PathType Leaf) ('Complete block output is missing: ' + $Path)
    $output = Get-Content -Raw -LiteralPath $Path | ConvertFrom-Json -Depth 100
    Assert-BlockOutputObject $output $Block $AuthorizationId
}

function Write-AtomicJson {
    param([string]$Path, $Value, [bool]$AllowReplace = $false)
    $directory = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $directory)) { New-Item -ItemType Directory -Path $directory | Out-Null }
    if (-not $AllowReplace -and (Test-Path -LiteralPath $Path)) { throw ('Refusing to overwrite: ' + $Path) }
    $temporary = $Path + '.tmp-' + [Guid]::NewGuid().ToString('N')
    $json = ($Value | ConvertTo-Json -Depth 100) -replace "`r`n", "`n"
    [IO.File]::WriteAllText($temporary, $json + "`n", [Text.UTF8Encoding]::new($false))
    [IO.File]::Move($temporary, $Path, $AllowReplace)
}

function Append-JsonLine {
    param([string]$Path, $Value)
    $json = ($Value | ConvertTo-Json -Compress -Depth 50) -replace "`r`n", "`n"
    [IO.File]::AppendAllText($Path, $json + "`n", [Text.UTF8Encoding]::new($false))
}

function New-SyntheticOutput {
    param($Block, [string]$AuthorizationId)
    $labels = @($Block.algorithmLabelsInOrder)
    $ids = @($Block.algorithmIdsInOrder)
    $movement = @()
    $m4 = @()
    $mask = @()
    $minimum = 0
    $sufficient = $false
    if ($Block.lane -ceq 'movement') {
        $mask = @(0..([int]$Block.unitCount - 1))
        $minimum = [Math]::Max(1, [int][Math]::Ceiling(0.8 * [int]$Block.unitCount))
        $sufficient = $true
        for ($index = 0; $index -lt 4; $index++) {
            $units = @(for ($agent = 0; $agent -lt [int]$Block.unitCount; $agent++) { [pscustomobject]@{ agentId = $agent; terminalState = 'Arrived'; arrived = $true; arrivalTick = 10; cumulativeHorizontalPathLength = 1.0 } })
            $movement += [pscustomobject]@{ algorithmLabel = $labels[$index]; productionAlgorithmId = $ids[$index]; orderPosition = $index + 1; unitCount = [int]$Block.unitCount; allUnitsArrived = $true; arrivedCount = [int]$Block.unitCount; activeAtCapCount = 0; noPathCount = 0; budgetExceededCount = 0; invalidPlanCount = 0; internalFailureCount = 0; m1Seconds = 1.0; m5CriticalViolationCount = 0; m5CriticalViolationCodes = @(); structuralEventCount = 2; units = $units; structuralEvents = @(); m2CommonMaskCount = $mask.Count; m2CommonMaskSufficient = $true; m2CommonMaskMeanPathLength = 1.0 }
        }
    }
    else {
        $intervals = @(for ($frame = 0; $frame -lt 1800; $frame++) { 0.016 })
        for ($index = 0; $index -lt 4; $index++) {
            $m4 += [pscustomobject]@{ algorithmLabel = $labels[$index]; productionAlgorithmId = $ids[$index]; orderPosition = $index + 1; unitCount = [int]$Block.unitCount; unitsWithEnabledRenderer = [int]$Block.unitCount; warmupRenderedFrames = 600; measuredRenderedFrameIntervals = 1800; frameIntervalsSeconds = $intervals; medianFrameTimeSeconds = 0.016; nearestRankP95FrameTimeSeconds = 0.016; simulationTickAtEnd = 1; structuralEventCount = 0; structuralEvents = @() }
        }
    }
    return [pscustomobject]@{ schema = 'gate14re-formal-block-output-v2'; studyId = 'Gate14Re'; status = 'COMPLETE'; blockId = $Block.blockId; blockSequence = [int]$Block.sequence; module = $Block.module; lane = $Block.lane; conditionId = $Block.conditionId; scenarioId = $Block.scenarioId; scenarioSha256 = $Block.scenarioSha256; unitCount = [int]$Block.unitCount; blockIndex = [int]$Block.blockIndex; williamsRow = [int]$Block.williamsRow; planSha256 = $PlanSha256; executableSha256 = $ExecutableSha256; assemblyCSharpSha256 = $AssemblySha256; buildReceiptSha256 = $BuildReceiptSha256; authorizationId = $AuthorizationId; m2CommonMaskMinimum = $minimum; m2CommonMaskAgentIds = $mask; m2CommonMaskSufficient = $sufficient; movement = $movement; m4 = $m4; completeFourAlgorithmBlock = $true; formalObservationProduced = $true; formalPhaseA = $true }
}

function Assert-BaseBindings {
    Assert-FrozenFile $PlanPath $PlanSha256 1169554L
    Assert-FrozenFile $ExecutionContractPath $ExecutionContractSha256 3989L
    Assert-FrozenFile $OutputSchemaPath $OutputSchemaSha256 5236L
    Assert-FrozenFile $ExecutablePath $ExecutableSha256 666624L
    Assert-FrozenFile $AssemblyPath $AssemblySha256 302080L
    Assert-FrozenFile $BuildReceiptPath $BuildReceiptSha256 1077L
    Assert-BuildTree
    $plan = Get-Content -Raw -LiteralPath $PlanPath | ConvertFrom-Json -Depth 100
    return @(Assert-Plan $plan)
}

$blocks = @(Assert-BaseBindings)

if ($ValidateOnly) {
    Assert-True (-not (Test-Path -LiteralPath $FormalRoot)) 'Formal measured root already exists; validation-only refuses to proceed.'
    Assert-True (-not (Test-Path -LiteralPath $FormalAnalysisRoot)) 'Formal analysis root already exists; validation-only refuses to proceed.'
    $movementBlock = $blocks | Where-Object { $_.lane -ceq 'movement' } | Select-Object -First 1
    $m4Block = $blocks | Where-Object { $_.lane -ceq 'm4' } | Select-Object -First 1
    $syntheticAuthorizationId = 'SYNTHETIC-VALIDATION-ONLY'
    $syntheticMovement = New-SyntheticOutput $movementBlock $syntheticAuthorizationId
    $syntheticM4 = New-SyntheticOutput $m4Block $syntheticAuthorizationId
    Assert-BlockOutputObject $syntheticMovement $movementBlock $syntheticAuthorizationId
    Assert-BlockOutputObject $syntheticM4 $m4Block $syntheticAuthorizationId
    $tampered = $syntheticMovement | ConvertTo-Json -Depth 100 | ConvertFrom-Json -Depth 100
    $tampered.assemblyCSharpSha256 = ('0' * 64)
    $rejected = $false
    try { Assert-BlockOutputObject $tampered $movementBlock $syntheticAuthorizationId } catch { $rejected = $true }
    Assert-True $rejected 'Tampered assembly identity was not rejected.'
    $tampered = $syntheticM4 | ConvertTo-Json -Depth 100 | ConvertFrom-Json -Depth 100
    $tampered.m4[0].frameIntervalsSeconds = @($tampered.m4[0].frameIntervalsSeconds | Select-Object -First 1799)
    $rejected = $false
    try { Assert-BlockOutputObject $tampered $m4Block $syntheticAuthorizationId } catch { $rejected = $true }
    Assert-True $rejected 'Tampered M4 interval cardinality was not rejected.'
    $receipt = [ordered]@{
        schema = 'gate14re-formal-supervisor-validation-receipt-v1'
        studyId = 'Gate14Re'
        status = 'PASS'
        supervisorSha256 = Get-Sha256Lower $PSCommandPath
        frozenPlanBlocksValidated = 1536
        frozenBuildFilesValidated = 151
        syntheticMovementOutputAccepted = $true
        syntheticM4OutputAccepted = $true
        tamperedAssemblyIdentityRejected = $true
        tamperedM4CardinalityRejected = $true
        authorizationRead = $false
        formalRootCreated = $false
        formalObservationProduced = $false
        formalPhaseAStarted = $false
    }
    Write-AtomicJson ([IO.Path]::GetFullPath($ValidationReceiptPath)) $receipt $false
    Write-Output 'GATE14RE_FORMAL_SUPERVISOR_VALIDATION_PASS'
    exit 0
}

Assert-True ($Execute.IsPresent) 'Formal execution requires the explicit -Execute switch.'
Assert-True ((Get-Item -LiteralPath $PSCommandPath).IsReadOnly) 'Formal supervisor script is not frozen ReadOnly.'
$AuthorizationPath = [IO.Path]::GetFullPath($AuthorizationPath)
Assert-True ($AuthorizationPath -ceq [IO.Path]::GetFullPath($ExpectedAuthorizationPath)) 'Authorization receipt path is not the frozen Gate 14Re v2 path.'
$AuthorizationSha256 = $AuthorizationSha256.ToLowerInvariant()
Assert-FrozenFile $AuthorizationPath $AuthorizationSha256
$authorization = Get-Content -Raw -LiteralPath $AuthorizationPath | ConvertFrom-Json -Depth 50
Assert-True ($authorization.schema -ceq 'gate14re-formal-phase-a-authorization-v2' -and $authorization.studyId -ceq 'Gate14Re' -and $authorization.status -ceq 'AUTHORIZED') 'Formal authorization schema/status mismatch.'
Assert-True ([bool]$authorization.userExplicitlyAuthorizedFormalPhaseA) 'Formal authorization lacks the explicit user-authorized flag.'
Assert-True (-not [string]::IsNullOrWhiteSpace([string]$authorization.authorizationId)) 'Formal authorization id is missing.'
Assert-True ($authorization.planSha256 -ceq $PlanSha256 -and $authorization.executionContractSha256 -ceq $ExecutionContractSha256 -and $authorization.outputSchemaSha256 -ceq $OutputSchemaSha256) 'Formal authorization design/plan binding mismatch.'
Assert-True ($authorization.executableSha256 -ceq $ExecutableSha256 -and $authorization.assemblyCSharpSha256 -ceq $AssemblySha256 -and $authorization.buildReceiptSha256 -ceq $BuildReceiptSha256) 'Formal authorization executable/assembly/build-receipt binding mismatch.'
Assert-True ($authorization.buildCanonicalTreeSha256 -ceq $BuildTreeSha256 -and $authorization.buildFreezeReceiptSha256 -ceq $BuildFreezeReceiptSha256) 'Formal authorization full-build-tree binding mismatch.'
Assert-True ($authorization.supervisorSha256 -ceq (Get-Sha256Lower $PSCommandPath)) 'Formal authorization supervisor binding mismatch.'
Assert-True ([IO.Path]::GetFullPath([string]$authorization.formalRoot) -ceq [IO.Path]::GetFullPath($FormalRoot)) 'Formal authorization root mismatch.'
Assert-True (-not (Test-Path -LiteralPath $FormalRoot)) 'Formal root already exists; no resume or overwrite is permitted.'
Assert-True (-not (Test-Path -LiteralPath $FormalAnalysisRoot)) 'Formal analysis root already exists unexpectedly.'

$controlRoot = Join-Path $FormalRoot '_control'
$blocksRoot = Join-Path $FormalRoot 'blocks'
$logsRoot = Join-Path $FormalRoot 'logs'
New-Item -ItemType Directory -Path $controlRoot, $blocksRoot, $logsRoot | Out-Null
$acceptedLedgerPath = Join-Path $controlRoot 'accepted-blocks.v1.jsonl'
$executionStatusPath = Join-Path $controlRoot 'execution-status.json'
$launchReceiptPath = Join-Path $controlRoot 'launch-receipt.v1.json'
$authorizationId = [string]$authorization.authorizationId
$replacementCount = 0
$acceptedCount = 0
$processCount = 0

try {
    $launchReceipt = [ordered]@{
        schema = 'gate14re-formal-phase-a-launch-receipt-v1'
        studyId = 'Gate14Re'
        status = 'FORMAL_PHASE_A_ACQUISITION_RUNNING'
        authorizationId = $authorizationId
        authorizationSha256 = $AuthorizationSha256
        planSha256 = $PlanSha256
        executableSha256 = $ExecutableSha256
        assemblyCSharpSha256 = $AssemblySha256
        buildReceiptSha256 = $BuildReceiptSha256
        buildCanonicalTreeSha256 = $BuildTreeSha256
        buildFreezeReceiptSha256 = $BuildFreezeReceiptSha256
        supervisorSha256 = Get-Sha256Lower $PSCommandPath
        plannedBlocks = 1536
        fixedB = 48
        formalRoot = $FormalRoot.Replace('\', '/')
        processTimeoutSeconds = $ProcessTimeoutSeconds
        maximumWholeBlockReplacementsPerBlock = 1
        perAlgorithmRetryResumeTopUpMergeSkipOrReorder = $false
        formalAnalysisStarted = $false
        phaseBStarted = $false
    }
    Write-AtomicJson $launchReceiptPath $launchReceipt $false

    foreach ($block in $blocks) {
        $blockDirectoryName = ('{0:D4}_{1}' -f [int]$block.sequence, [string]$block.blockId)
        $blockDirectory = Join-Path $blocksRoot $blockDirectoryName
        New-Item -ItemType Directory -Path $blockDirectory | Out-Null
        $accepted = $false
        for ($attempt = 1; $attempt -le 2 -and -not $accepted; $attempt++) {
            if ($attempt -eq 2) { $replacementCount++ }
            $attemptDirectory = Join-Path $blockDirectory ('attempt-{0:D3}' -f $attempt)
            New-Item -ItemType Directory -Path $attemptDirectory | Out-Null
            $outputPath = Join-Path $attemptDirectory 'block-output.json'
            $logPath = Join-Path $logsRoot (('{0:D4}_{1}_attempt-{2:D3}.player.log' -f [int]$block.sequence, [string]$block.blockId, $attempt))
            $arguments = @(
                '-batchmode', '-force-d3d11', '-logFile', $logPath,
                '--gate14re-mode', 'formal',
                '--gate14re-project-root', $ProjectRoot,
                '--gate14re-plan', $PlanPath,
                '--gate14re-plan-sha256', $PlanSha256,
                '--gate14re-block-id', [string]$block.blockId,
                '--gate14re-output', $outputPath,
                '--gate14re-formal-authorization', $AuthorizationPath,
                '--gate14re-formal-authorization-sha256', $AuthorizationSha256
            )
            $process = Start-Process -FilePath $ExecutablePath -ArgumentList $arguments -WindowStyle Hidden -PassThru
            $processCount++
            $timedOut = -not $process.WaitForExit($ProcessTimeoutSeconds * 1000)
            if ($timedOut) {
                try { $process.Kill($true) } catch { }
                try { $process.WaitForExit(30000) | Out-Null } catch { }
            }
            $exitCode = if ($timedOut) { -2 } else { $process.ExitCode }
            $validOutput = $false
            $validationMessage = ''
            if (-not $timedOut -and $exitCode -eq 0 -and (Test-Path -LiteralPath $outputPath -PathType Leaf)) {
                try {
                    Assert-BlockOutputFile $outputPath $block $authorizationId
                    $validOutput = $true
                }
                catch { $validationMessage = $_.Exception.Message }
            }
            elseif ($timedOut) { $validationMessage = 'Process hard timeout.' }
            else { $validationMessage = 'Process exited nonzero or complete block output is missing.' }

            $attemptReceipt = [ordered]@{
                schema = 'gate14re-formal-block-process-receipt-v1'
                studyId = 'Gate14Re'
                blockId = [string]$block.blockId
                blockSequence = [int]$block.sequence
                attempt = $attempt
                replacement = ($attempt -eq 2)
                processId = $process.Id
                exitCode = $exitCode
                timedOut = $timedOut
                completeOutputValidated = $validOutput
                outputRelativePath = [IO.Path]::GetRelativePath($FormalRoot, $outputPath).Replace('\', '/')
                outputSha256 = if ($validOutput) { Get-Sha256Lower $outputPath } else { '' }
                validationMessage = $validationMessage
                perAlgorithmRetryOrResume = $false
            }
            Write-AtomicJson (Join-Path $attemptDirectory 'process-receipt.v1.json') $attemptReceipt $false

            if ($validOutput) {
                $accepted = $true
                $acceptedCount++
                Append-JsonLine $acceptedLedgerPath ([ordered]@{ sequence = [int]$block.sequence; blockId = [string]$block.blockId; acceptedAttempt = $attempt; replacement = ($attempt -eq 2); outputRelativePath = [IO.Path]::GetRelativePath($FormalRoot, $outputPath).Replace('\', '/'); outputSha256 = Get-Sha256Lower $outputPath })
            }
        }
        if (-not $accepted) { throw ('Block failed after its single permitted whole-block replacement: ' + $block.blockId) }
        Write-AtomicJson $executionStatusPath ([ordered]@{ schema = 'gate14re-formal-phase-a-execution-status-v1'; studyId = 'Gate14Re'; status = 'FORMAL_PHASE_A_ACQUISITION_RUNNING'; acceptedBlocks = $acceptedCount; plannedBlocks = 1536; launchedProcesses = $processCount; wholeBlockReplacements = $replacementCount; lastAcceptedSequence = [int]$block.sequence; lastAcceptedBlockId = [string]$block.blockId; processRetryResumeTopUpMergeSkipOrReorder = $false; formalAnalysisStarted = $false; phaseBStarted = $false }) $true
    }

    Assert-True ($acceptedCount -eq 1536) 'Formal acquisition did not produce 1536 accepted complete blocks.'
    $complete = [ordered]@{
        schema = 'gate14re-formal-phase-a-acquisition-complete-v1'
        studyId = 'Gate14Re'
        status = 'FORMAL-PHASE-A-ACQUISITION-COMPLETE'
        nextState = 'FORMAL-PHASE-A-RAW-COMMIT-PENDING'
        fixedB = 48
        acceptedBlocks = $acceptedCount
        plannedBlocks = 1536
        launchedProcesses = $processCount
        wholeBlockReplacements = $replacementCount
        maximumWholeBlockReplacementsPerBlock = 1
        processRetryResumeTopUpMergeSkipOrReorder = $false
        formalAnalysisStarted = $false
        phaseBStarted = $false
    }
    Write-AtomicJson (Join-Path $controlRoot 'acquisition-complete.v1.json') $complete $false
    Write-AtomicJson $executionStatusPath ([ordered]@{ schema = 'gate14re-formal-phase-a-execution-status-v1'; studyId = 'Gate14Re'; status = 'FORMAL-PHASE-A-ACQUISITION-COMPLETE'; nextState = 'FORMAL-PHASE-A-RAW-COMMIT-PENDING'; acceptedBlocks = 1536; plannedBlocks = 1536; launchedProcesses = $processCount; wholeBlockReplacements = $replacementCount; processRetryResumeTopUpMergeSkipOrReorder = $false; formalAnalysisStarted = $false; phaseBStarted = $false }) $true
    Write-Output 'GATE14RE_FORMAL_PHASE_A_ACQUISITION_COMPLETE_RAW_COMMIT_PENDING'
}
catch {
    $failure = [ordered]@{
        schema = 'gate14re-formal-phase-a-supervisor-failure-v1'
        studyId = 'Gate14Re'
        status = 'FAIL_CLOSED'
        message = $_.Exception.Message
        acceptedBlocks = $acceptedCount
        launchedProcesses = $processCount
        wholeBlockReplacements = $replacementCount
        partialBlockAdmissible = $false
        processRetryResumeTopUpMergeSkipOrReorder = $false
        formalAnalysisStarted = $false
        phaseBStarted = $false
    }
    $failurePath = Join-Path $controlRoot 'failure-receipt.v1.json'
    if (-not (Test-Path -LiteralPath $failurePath)) { Write-AtomicJson $failurePath $failure $false }
    throw
}
