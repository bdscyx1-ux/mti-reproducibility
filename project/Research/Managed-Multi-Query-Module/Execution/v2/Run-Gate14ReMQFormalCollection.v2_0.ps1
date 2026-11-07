[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$ProjectRoot,
    [Parameter(Mandatory = $true)][string]$MeasuredRoot,
    [Parameter(Mandatory = $true)][string]$ExecutionAuthorization,
    [Parameter(Mandatory = $true)][ValidatePattern('^[0-9a-f]{64}$')][string]$ExecutionAuthorizationSha256,
    [Parameter(Mandatory = $true)][string]$ImplementationManifest,
    [Parameter(Mandatory = $true)][ValidatePattern('^[0-9a-f]{64}$')][string]$ImplementationManifestSha256,
    [Parameter(Mandatory = $true)][string]$ExecutionContract,
    [Parameter(Mandatory = $true)][ValidatePattern('^[0-9a-f]{64}$')][string]$ExecutionContractSha256,
    [Parameter(Mandatory = $true)][string]$Schedule,
    [Parameter(Mandatory = $true)][ValidatePattern('^[0-9a-f]{64}$')][string]$ScheduleSha256,
    [Parameter(Mandatory = $true)][string]$BlockInputs,
    [Parameter(Mandatory = $true)][ValidatePattern('^[0-9a-f]{64}$')][string]$BlockInputsSha256,
    [Parameter(Mandatory = $true)][string]$IdentityMap,
    [Parameter(Mandatory = $true)][ValidatePattern('^[0-9a-f]{64}$')][string]$IdentityMapSha256,
    [Parameter(Mandatory = $true)][string]$FairnessBinding,
    [Parameter(Mandatory = $true)][ValidatePattern('^[0-9a-f]{64}$')][string]$FairnessBindingSha256,
    [Parameter(Mandatory = $true)][string]$ResourceBudget,
    [Parameter(Mandatory = $true)][ValidatePattern('^[0-9a-f]{64}$')][string]$ResourceBudgetSha256,
    [Parameter(Mandatory = $true)][string]$UnityExecutable,
    [Parameter(Mandatory = $true)][ValidatePattern('^[0-9a-f]{64}$')][string]$UnityExecutableSha256
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$studyId = 'Gate14Re-MQ-CFF-IDFF'
$designId = 'gate14re-mq-cff-idff-formal-v2'
$runnerMethod = 'DDM.Research.Editor.Gate14ReMQFormalRunnerV2.Run'
$expectedProcessCount = 864
$reservedMeasuredRootPattern = '^Research/FormalRuns/Gate14Re-MQ-CFF-IDFF/formal-mq/v2/attempt-[0-9]+$'
$measuredRootCreated = $false
$currentOrdinal = -1
$currentProcess = $null

function Require-Condition {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw [System.InvalidOperationException]::new($Message) }
}

function Get-NormalizedFullPath {
    param([string]$Path, [string]$Base)
    $candidate = if ([System.IO.Path]::IsPathRooted($Path)) { $Path } else { Join-Path -Path $Base -ChildPath $Path }
    return [System.IO.Path]::GetFullPath($candidate).TrimEnd([System.IO.Path]::DirectorySeparatorChar)
}

function Get-ProjectRelativePath {
    param([string]$Path, [string]$Root)
    $rootUri = [Uri]::new($Root.TrimEnd([System.IO.Path]::DirectorySeparatorChar) + [System.IO.Path]::DirectorySeparatorChar)
    $pathUri = [Uri]::new([System.IO.Path]::GetFullPath($Path))
    return [Uri]::UnescapeDataString($rootUri.MakeRelativeUri($pathUri).ToString()).Replace('\', '/')
}

function Assert-InsideProject {
    param([string]$Path, [string]$Root, [string]$Label)
    $prefix = $Root.TrimEnd([System.IO.Path]::DirectorySeparatorChar) + [System.IO.Path]::DirectorySeparatorChar
    Require-Condition $Path.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase) "$Label resolves outside project root."
}

function Get-Sha256Lower {
    param([string]$Path)
    Require-Condition (Test-Path -LiteralPath $Path -PathType Leaf) "Required file is missing: $Path"
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Assert-Hash {
    param([string]$Path, [string]$Expected, [string]$Label)
    $actual = Get-Sha256Lower -Path $Path
    Require-Condition ($actual -eq $Expected) "$Label SHA-256 mismatch: expected $Expected; actual $actual"
}

function Read-Json {
    param([string]$Path)
    return Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json -Depth 100 -DateKind String
}

function Write-JsonExclusive {
    param([string]$Path, [object]$Value)
    Require-Condition (-not (Test-Path -LiteralPath $Path)) "Refusing to overwrite evidence: $Path"
    $parent = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
        [System.IO.Directory]::CreateDirectory($parent) | Out-Null
    }
    $json = ($Value | ConvertTo-Json -Depth 100) + [Environment]::NewLine
    $encoding = [System.Text.UTF8Encoding]::new($false)
    $stream = [System.IO.File]::Open($Path, [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
    try {
        $writer = [System.IO.StreamWriter]::new($stream, $encoding)
        try { $writer.Write($json); $writer.Flush() }
        finally { $writer.Dispose() }
    }
    finally { $stream.Dispose() }
}

function Append-JsonLine {
    param([string]$Path, [object]$Value)
    $line = ($Value | ConvertTo-Json -Depth 100 -Compress) + [Environment]::NewLine
    $encoding = [System.Text.UTF8Encoding]::new($false)
    $stream = [System.IO.File]::Open($Path, [System.IO.FileMode]::Append, [System.IO.FileAccess]::Write, [System.IO.FileShare]::Read)
    try {
        $writer = [System.IO.StreamWriter]::new($stream, $encoding)
        try { $writer.Write($line); $writer.Flush() }
        finally { $writer.Dispose() }
    }
    finally { $stream.Dispose() }
}

function Assert-JsonMarker {
    param([string]$Path, [string]$Schema, [string]$Status, [string]$Label)
    $value = Read-Json -Path $Path
    Require-Condition ([string]$value.schema -eq $Schema -and [string]$value.status -eq $Status) "$Label schema/status mismatch."
    return $value
}

function Assert-ImplementationManifest {
    param([object]$Manifest, [string]$Root)
    Require-Condition ([string]$Manifest.schema -eq 'gate14re-mq-formal-implementation-manifest-v2') 'Implementation-manifest schema mismatch.'
    Require-Condition ([string]$Manifest.status -eq 'FROZEN_IMPLEMENTATION_AND_SCHEDULE_READY_FOR_SEPARATE_LAUNCH_AUTHORIZATION') 'Implementation-manifest status mismatch.'
    Require-Condition ([string]$Manifest.studyId -eq $script:studyId -and [string]$Manifest.designId -eq $script:designId) 'Implementation-manifest study/design mismatch.'
    $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    $rows = @($Manifest.artifacts)
    Require-Condition ($rows.Count -ge 15) 'Implementation-manifest has fewer than 15 artifacts.'
    foreach ($row in $rows) {
        $relative = [string]$row.relativePath
        Require-Condition (-not [string]::IsNullOrWhiteSpace($relative) -and $seen.Add($relative)) 'Implementation-manifest path is empty or duplicated.'
        $path = Get-NormalizedFullPath -Path $relative -Base $Root
        Assert-InsideProject -Path $path -Root $Root -Label 'Implementation-manifest artifact'
        Require-Condition ((Get-Item -LiteralPath $path).Length -eq [int64]$row.bytes) "Implementation artifact byte count drifted: $relative"
        Assert-Hash -Path $path -Expected ([string]$row.sha256) -Label "Implementation artifact $relative"
    }
}

function Get-UnityProcesses {
    param([string]$ExecutablePath)
    $normalized = [System.IO.Path]::GetFullPath($ExecutablePath)
    return @(Get-CimInstance Win32_Process -Filter "Name='Unity.exe'" -ErrorAction Stop | Where-Object {
        -not [string]::IsNullOrWhiteSpace([string]$_.ExecutablePath) -and
        [System.IO.Path]::GetFullPath([string]$_.ExecutablePath).Equals($normalized, [System.StringComparison]::OrdinalIgnoreCase)
    })
}

function Get-ProcessIdentity {
    param([int]$ProcessId, [string]$ExpectedExecutable, [string]$RequiredMeasuredRoot)
    $row = Get-CimInstance Win32_Process -Filter "ProcessId=$ProcessId" -ErrorAction Stop
    Require-Condition ($null -ne $row) "Started Unity process $ProcessId is not queryable."
    $actualExecutable = [System.IO.Path]::GetFullPath([string]$row.ExecutablePath)
    Require-Condition $actualExecutable.Equals([System.IO.Path]::GetFullPath($ExpectedExecutable), [System.StringComparison]::OrdinalIgnoreCase) 'Started process executable identity mismatch.'
    $commandLine = [string]$row.CommandLine
    Require-Condition ($commandLine.Contains($script:runnerMethod, [System.StringComparison]::Ordinal) -and
        $commandLine.Contains($RequiredMeasuredRoot, [System.StringComparison]::OrdinalIgnoreCase)) 'Started process command line is not bound to the MQ runner and measured root.'
    return [pscustomobject][ordered]@{
        pid = [int]$row.ProcessId
        creationDate = [string]$row.CreationDate
        executablePath = $actualExecutable.Replace('\', '/')
        commandLine = $commandLine
    }
}

function New-UnityProcess {
    param([string]$Executable, [string[]]$Arguments, [string]$WorkingDirectory)
    $start = [System.Diagnostics.ProcessStartInfo]::new()
    $start.FileName = $Executable
    $start.UseShellExecute = $false
    $start.CreateNoWindow = $true
    $start.WorkingDirectory = $WorkingDirectory
    foreach ($argument in $Arguments) { [void]$start.ArgumentList.Add($argument) }
    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $start
    Require-Condition $process.Start() 'Unity process failed to start.'
    return $process
}

function Get-OutputFreezeRows {
    param([string]$Root)
    $rows = [System.Collections.Generic.List[object]]::new()
    foreach ($file in Get-ChildItem -LiteralPath $Root -File -Recurse | Sort-Object FullName) {
        $relative = Get-ProjectRelativePath -Path $file.FullName -Root $Root
        if ($relative -in @('_control/acquisition-freeze-manifest.v2.json', '_control/acquisition-terminal-receipt.v2.json')) { continue }
        $rows.Add([pscustomobject][ordered]@{
            relativePath = $relative
            bytes = [int64]$file.Length
            sha256 = Get-Sha256Lower -Path $file.FullName
        })
    }
    return @($rows)
}

try {
    $ProjectRoot = Get-NormalizedFullPath -Path $ProjectRoot -Base (Get-Location).Path
    $MeasuredRoot = Get-NormalizedFullPath -Path $MeasuredRoot -Base $ProjectRoot
    $ExecutionAuthorization = Get-NormalizedFullPath -Path $ExecutionAuthorization -Base $ProjectRoot
    $ImplementationManifest = Get-NormalizedFullPath -Path $ImplementationManifest -Base $ProjectRoot
    $ExecutionContract = Get-NormalizedFullPath -Path $ExecutionContract -Base $ProjectRoot
    $Schedule = Get-NormalizedFullPath -Path $Schedule -Base $ProjectRoot
    $BlockInputs = Get-NormalizedFullPath -Path $BlockInputs -Base $ProjectRoot
    $IdentityMap = Get-NormalizedFullPath -Path $IdentityMap -Base $ProjectRoot
    $FairnessBinding = Get-NormalizedFullPath -Path $FairnessBinding -Base $ProjectRoot
    $ResourceBudget = Get-NormalizedFullPath -Path $ResourceBudget -Base $ProjectRoot
    $UnityExecutable = Get-NormalizedFullPath -Path $UnityExecutable -Base $ProjectRoot

    foreach ($bound in @($MeasuredRoot, $ExecutionAuthorization, $ImplementationManifest, $ExecutionContract,
        $Schedule, $BlockInputs, $IdentityMap, $FairnessBinding, $ResourceBudget)) {
        Assert-InsideProject -Path $bound -Root $ProjectRoot -Label 'Formal MQ bound path'
    }
    Require-Condition (Test-Path -LiteralPath $UnityExecutable -PathType Leaf) 'Unity executable is missing.'

    $measuredRelative = Get-ProjectRelativePath -Path $MeasuredRoot -Root $ProjectRoot
    Require-Condition ($measuredRelative -match $reservedMeasuredRootPattern) 'Measured root does not use the reserved fresh attempt naming rule.'
    Require-Condition (-not (Test-Path -LiteralPath $MeasuredRoot)) 'Measured root already exists; resume or overwrite is forbidden.'
    Require-Condition ((Get-UnityProcesses -ExecutablePath $UnityExecutable).Count -eq 0) 'A Unity process is already active; strict-serial launch is blocked.'

    Assert-Hash -Path $UnityExecutable -Expected $UnityExecutableSha256 -Label 'Unity executable'
    Assert-Hash -Path $ExecutionAuthorization -Expected $ExecutionAuthorizationSha256 -Label 'Execution authorization'
    Assert-Hash -Path $ImplementationManifest -Expected $ImplementationManifestSha256 -Label 'Implementation manifest'
    Assert-Hash -Path $ExecutionContract -Expected $ExecutionContractSha256 -Label 'Execution contract'
    Assert-Hash -Path $Schedule -Expected $ScheduleSha256 -Label 'Schedule'
    Assert-Hash -Path $BlockInputs -Expected $BlockInputsSha256 -Label 'Block inputs'
    Assert-Hash -Path $IdentityMap -Expected $IdentityMapSha256 -Label 'Identity map'
    Assert-Hash -Path $FairnessBinding -Expected $FairnessBindingSha256 -Label 'Fairness binding'
    Assert-Hash -Path $ResourceBudget -Expected $ResourceBudgetSha256 -Label 'Resource budget'

    $authorization = Assert-JsonMarker -Path $ExecutionAuthorization -Schema 'gate14re-mq-formal-execution-authorization-v2' -Status 'AUTHORIZED_FORMAL_MQ_COLLECTION_ONE_ATTEMPT' -Label 'Execution authorization'
    Require-Condition ([string]$authorization.studyId -eq $studyId -and [string]$authorization.designId -eq $designId) 'Authorization study/design mismatch.'
    Require-Condition ([bool]$authorization.formalCollectionAuthorized -and -not [bool]$authorization.formalAnalysisAuthorized -and [bool]$authorization.mqOnly) 'Authorization scope is not collection-only MQ.'
    Require-Condition ([string]$authorization.measuredRootRelativePath -eq $measuredRelative) 'Authorization measured root mismatch.'
    Require-Condition ([string]$authorization.implementationManifestSha256 -eq $ImplementationManifestSha256 -and
        [string]$authorization.executionContractSha256 -eq $ExecutionContractSha256 -and
        [string]$authorization.scheduleSha256 -eq $ScheduleSha256 -and
        [string]$authorization.blockInputAssignmentsSha256 -eq $BlockInputsSha256 -and
        [string]$authorization.identityMapSha256 -eq $IdentityMapSha256 -and
        [string]$authorization.fairnessBindingSha256 -eq $FairnessBindingSha256 -and
        [string]$authorization.resourceBudgetSha256 -eq $ResourceBudgetSha256) 'Authorization hash bindings differ from launch arguments.'
    Require-Condition ([string]$authorization.unityExecutableSha256 -eq $UnityExecutableSha256) 'Authorization Unity executable hash differs from launch arguments.'

    $contract = Assert-JsonMarker -Path $ExecutionContract -Schema 'gate14re-mq-formal-execution-contract-v2' -Status 'FROZEN_EXECUTION_CONTRACT_REQUIRES_SEPARATE_LAUNCH_AUTHORIZATION' -Label 'Execution contract'
    Require-Condition ([int]$contract.cardinality.freshUnityProcesses -eq $expectedProcessCount -and [int]$contract.cardinality.matchedBlocks -eq 36 -and [int]$contract.cardinality.lanesPerBlock -eq 16) 'Execution-contract cardinality mismatch.'
    $budget = Assert-JsonMarker -Path $ResourceBudget -Schema 'gate14re-mq-formal-resource-budget-v2' -Status 'FROZEN_RESOURCE_AND_TIMEOUT_GATES' -Label 'Resource budget'
    Require-Condition ([int]$budget.freshUnityProcessCount -eq $expectedProcessCount -and [int]$budget.maximumConcurrentMeasuredUnityProcesses -eq 1) 'Resource-budget process/concurrency mismatch.'
    $perProcessTimeoutSeconds = [int]$budget.perProcessHardTimeoutSeconds
    $wholeAttemptCeiling = [TimeSpan]::FromHours([double]$budget.wholeAttemptHardCeilingHours)
    Require-Condition ($perProcessTimeoutSeconds -gt 0 -and $wholeAttemptCeiling.TotalHours -eq 168) 'Resource-budget timeout gate mismatch.'

    $manifest = Read-Json -Path $ImplementationManifest
    Assert-ImplementationManifest -Manifest $manifest -Root $ProjectRoot

    $scheduleRows = @(Get-Content -LiteralPath $Schedule -Encoding UTF8 | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | ForEach-Object { $_ | ConvertFrom-Json -Depth 100 -DateKind String })
    Require-Condition ($scheduleRows.Count -eq $expectedProcessCount) 'Schedule must contain exactly 864 nonempty rows.'
    for ($index = 0; $index -lt $scheduleRows.Count; $index++) {
        Require-Condition ([int]$scheduleRows[$index].processOrdinal -eq $index -and [string]$scheduleRows[$index].schema -eq 'gate14re-mq-formal-process-schedule-row-v2') "Schedule ordinal/schema mismatch at $index."
    }

    [System.IO.Directory]::CreateDirectory($MeasuredRoot) | Out-Null
    $measuredRootCreated = $true
    $controlRoot = Join-Path $MeasuredRoot '_control'
    $rawBlocksRoot = Join-Path $MeasuredRoot 'raw/blocks'
    [System.IO.Directory]::CreateDirectory($controlRoot) | Out-Null
    [System.IO.Directory]::CreateDirectory($rawBlocksRoot) | Out-Null
    $processLedger = Join-Path $controlRoot 'process-ledger.raw.v2.jsonl'
    $failureLedger = Join-Path $controlRoot 'failures-and-voids.raw.v2.jsonl'
    $replacementLedger = Join-Path $controlRoot 'replacement-ledger.raw.v2.jsonl'
    [System.IO.File]::WriteAllText($processLedger, '', [System.Text.UTF8Encoding]::new($false))
    [System.IO.File]::WriteAllText($failureLedger, '', [System.Text.UTF8Encoding]::new($false))
    [System.IO.File]::WriteAllText($replacementLedger, '', [System.Text.UTF8Encoding]::new($false))

    $startedAt = [DateTimeOffset]::UtcNow
    Write-JsonExclusive -Path (Join-Path $controlRoot 'launch-receipt.v2.json') -Value ([pscustomobject][ordered]@{
        schema = 'gate14re-mq-formal-launch-receipt-v2'
        studyId = $studyId
        designId = $designId
        authorizationId = [string]$authorization.authorizationId
        status = 'AUTHORIZED_AND_LAUNCHED_STRICT_SERIAL_FORMAL_MQ'
        startedAtUtc = $startedAt.ToString('o')
        measuredRootRelativePath = $measuredRelative
        expectedFreshUnityProcesses = $expectedProcessCount
        maximumConcurrentMeasuredUnityProcesses = 1
        executionAuthorizationSha256 = $ExecutionAuthorizationSha256
        implementationManifestSha256 = $ImplementationManifestSha256
        executionContractSha256 = $ExecutionContractSha256
        scheduleSha256 = $ScheduleSha256
        blockInputAssignmentsSha256 = $BlockInputsSha256
        identityMapSha256 = $IdentityMapSha256
        fairnessBindingSha256 = $FairnessBindingSha256
        resourceBudgetSha256 = $ResourceBudgetSha256
        unityExecutableSha256 = $UnityExecutableSha256
        formalAnalysisAuthorized = $false
    })

    for ($ordinal = 0; $ordinal -lt $expectedProcessCount; $ordinal++) {
        $currentOrdinal = $ordinal
        Require-Condition ((Get-UnityProcesses -ExecutablePath $UnityExecutable).Count -eq 0) "Unity overlap detected before ordinal $ordinal."
        Require-Condition (([DateTimeOffset]::UtcNow - $startedAt) -lt $wholeAttemptCeiling) 'Whole-attempt hard ceiling reached.'
        $scheduledRow = $scheduleRows[$ordinal]
        $blockDirectory = Join-Path $rawBlocksRoot ([string]$scheduledRow.blockId)
        $outputDirectory = Join-Path $blockDirectory ('process-{0:D4}' -f $ordinal)
        $logPath = Join-Path $controlRoot (('unity-P{0:D4}.log' -f $ordinal))
        Require-Condition (-not (Test-Path -LiteralPath $outputDirectory) -and -not (Test-Path -LiteralPath $logPath)) 'Per-process output or log already exists.'

        $arguments = @(
            '-batchmode', '-nographics', '-disable-burst-compilation',
            '-projectPath', $ProjectRoot,
            '-executeMethod', $runnerMethod,
            '--g14mq-execution-authorization', $ExecutionAuthorization,
            '--g14mq-execution-authorization-sha256', $ExecutionAuthorizationSha256,
            '--g14mq-implementation-manifest', $ImplementationManifest,
            '--g14mq-implementation-manifest-sha256', $ImplementationManifestSha256,
            '--g14mq-execution-contract', $ExecutionContract,
            '--g14mq-execution-contract-sha256', $ExecutionContractSha256,
            '--g14mq-schedule', $Schedule,
            '--g14mq-schedule-sha256', $ScheduleSha256,
            '--g14mq-block-inputs', $BlockInputs,
            '--g14mq-block-inputs-sha256', $BlockInputsSha256,
            '--g14mq-identity-map', $IdentityMap,
            '--g14mq-identity-map-sha256', $IdentityMapSha256,
            '--g14mq-fairness', $FairnessBinding,
            '--g14mq-fairness-sha256', $FairnessBindingSha256,
            '--g14mq-resource-budget', $ResourceBudget,
            '--g14mq-resource-budget-sha256', $ResourceBudgetSha256,
            '--g14mq-measured-root', $MeasuredRoot,
            '--g14mq-output-dir', $outputDirectory,
            '--g14mq-process-ordinal', [string]$ordinal,
            '-logFile', $logPath
        )
        $launchedAt = [DateTimeOffset]::UtcNow
        $currentProcess = New-UnityProcess -Executable $UnityExecutable -Arguments $arguments -WorkingDirectory $ProjectRoot
        $identity = Get-ProcessIdentity -ProcessId $currentProcess.Id -ExpectedExecutable $UnityExecutable -RequiredMeasuredRoot $MeasuredRoot
        $exited = $currentProcess.WaitForExit([int]([Math]::Min([int64]$perProcessTimeoutSeconds * 1000, [int]::MaxValue)))
        if (-not $exited) {
            $currentProcess.Kill($true)
            $currentProcess.WaitForExit()
            throw [System.TimeoutException]::new("Formal MQ ordinal $ordinal exceeded $perProcessTimeoutSeconds seconds and was terminated; the attempt is failed and cannot resume.")
        }
        $exitCode = $currentProcess.ExitCode
        $exitedAt = [DateTimeOffset]::UtcNow
        $currentProcess.Dispose()
        $currentProcess = $null
        Require-Condition ($exitCode -eq 0) "Formal MQ ordinal $ordinal exited nonzero: $exitCode"
        Require-Condition ((Get-UnityProcesses -ExecutablePath $UnityExecutable).Count -eq 0) "Unity remained active after ordinal $ordinal."

        $terminalPath = Join-Path $outputDirectory 'process-terminal-receipt.v2.json'
        Require-Condition (Test-Path -LiteralPath $terminalPath -PathType Leaf) "Formal MQ ordinal $ordinal is missing its terminal receipt."
        $terminal = Read-Json -Path $terminalPath
        Require-Condition ([string]$terminal.schema -eq 'gate14re-mq-formal-process-terminal-receipt-v2' -and
            [string]$terminal.status -eq 'PASS_ONE_FROZEN_FORMAL_MQ_PROCESS' -and
            [string]$terminal.authorizationId -eq [string]$authorization.authorizationId -and
            [int]$terminal.processOrdinal -eq $ordinal -and
            [int]$terminal.blockOrdinal -eq [int]$scheduledRow.blockOrdinal -and
            [string]$terminal.blockId -eq [string]$scheduledRow.blockId -and
            [string]$terminal.opaqueAlgorithmSlot -eq [string]$scheduledRow.opaqueAlgorithmSlot -and
            [string]$terminal.conditionId -eq [string]$scheduledRow.conditionId -and
            [int]$terminal.workerCount -eq [int]$scheduledRow.workerCount -and
            [int]$terminal.laneCount -eq 16 -and [bool]$terminal.allCorrectnessAndOracleHardGatesPassed -and
            [bool]$terminal.allAffinityBindingsObserved -and [bool]$terminal.completeBatch -and
            -not [bool]$terminal.formalAnalysisStarted) "Formal MQ ordinal $ordinal terminal receipt failed validation."
        Require-Condition ([string]$terminal.scheduleSha256 -eq $ScheduleSha256 -and
            [string]$terminal.blockInputAssignmentsSha256 -eq $BlockInputsSha256 -and
            [string]$terminal.identityMapSha256 -eq $IdentityMapSha256 -and
            [string]$terminal.implementationManifestSha256 -eq $ImplementationManifestSha256 -and
            [string]$terminal.executionContractSha256 -eq $ExecutionContractSha256 -and
            [string]$terminal.fairnessBindingSha256 -eq $FairnessBindingSha256 -and
            [string]$terminal.resourceBudgetSha256 -eq $ResourceBudgetSha256 -and
            [string]$terminal.unityExecutableSha256 -eq $UnityExecutableSha256) "Formal MQ ordinal $ordinal terminal hash bindings differ from the launch."
        $laneEvidencePath = Join-Path $outputDirectory 'formal-lanes.raw.v2.jsonl'
        $batchEvidencePath = Join-Path $outputDirectory 'formal-batch.raw.v2.json'
        $outputManifestPath = Join-Path $outputDirectory 'output-freeze-manifest.v2.json'
        Require-Condition (Test-Path -LiteralPath $laneEvidencePath -PathType Leaf) "Formal MQ ordinal $ordinal is missing lane evidence."
        Require-Condition (Test-Path -LiteralPath $batchEvidencePath -PathType Leaf) "Formal MQ ordinal $ordinal is missing batch evidence."
        Require-Condition (Test-Path -LiteralPath $outputManifestPath -PathType Leaf) "Formal MQ ordinal $ordinal is missing its output manifest."
        Require-Condition ((Get-Sha256Lower -Path $laneEvidencePath) -eq [string]$terminal.laneEvidenceSha256 -and
            (Get-Sha256Lower -Path $batchEvidencePath) -eq [string]$terminal.batchEvidenceSha256 -and
            (Get-Sha256Lower -Path $outputManifestPath) -eq [string]$terminal.outputManifestSha256) "Formal MQ ordinal $ordinal output hashes differ from its terminal receipt."
        $processOutputManifest = Read-Json -Path $outputManifestPath
        Require-Condition ([string]$processOutputManifest.schema -eq 'gate14re-mq-formal-process-output-freeze-manifest-v2' -and
            [string]$processOutputManifest.status -eq 'FROZEN_COMPLETE_PROCESS_OUTPUTS' -and
            @($processOutputManifest.artifacts).Count -eq 2) "Formal MQ ordinal $ordinal output manifest schema/cardinality mismatch."
        Append-JsonLine -Path $processLedger -Value ([pscustomobject][ordered]@{
            schema = 'gate14re-mq-formal-process-ledger-row-v2'
            state = 'EXITED_ZERO_TRUSTED_IDENTITY'
            processOrdinal = $ordinal
            pid = $identity.pid
            creationDate = $identity.creationDate
            executablePath = $identity.executablePath
            commandLine = $identity.commandLine
            launchedAtUtc = $launchedAt.ToString('o')
            exitedAtUtc = $exitedAt.ToString('o')
            exitCode = 0
            terminalReceiptRelativePath = Get-ProjectRelativePath -Path $terminalPath -Root $MeasuredRoot
            terminalReceiptSha256 = Get-Sha256Lower -Path $terminalPath
            retryResumeReplacement = $false
        })
    }

    Require-Condition ((Get-Content -LiteralPath $processLedger | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }).Count -eq $expectedProcessCount) 'Final process-ledger cardinality mismatch.'
    Require-Condition ((Get-Item -LiteralPath $failureLedger).Length -eq 0 -and (Get-Item -LiteralPath $replacementLedger).Length -eq 0) 'Failure or replacement ledger is nonempty.'
    $completedAt = [DateTimeOffset]::UtcNow
    Write-JsonExclusive -Path (Join-Path $controlRoot 'acquisition-complete.v2.json') -Value ([pscustomobject][ordered]@{
        schema = 'gate14re-mq-formal-acquisition-complete-v2'
        status = 'PASS_RAW_FORMAL_MQ_COLLECTION_COMPLETE_ANALYSIS_NOT_STARTED'
        authorizationId = [string]$authorization.authorizationId
        completedFreshUnityProcesses = $expectedProcessCount
        completedAtUtc = $completedAt.ToString('o')
        formalAnalysisStarted = $false
    })
    $freezeRows = Get-OutputFreezeRows -Root $MeasuredRoot
    $freezeManifestPath = Join-Path $controlRoot 'acquisition-freeze-manifest.v2.json'
    Write-JsonExclusive -Path $freezeManifestPath -Value ([pscustomobject][ordered]@{
        schema = 'gate14re-mq-formal-acquisition-freeze-manifest-v2'
        status = 'FROZEN_COMPLETE_RAW_FORMAL_MQ_COLLECTION'
        fileCount = $freezeRows.Count
        files = $freezeRows
        formalAnalysisStarted = $false
        createdAtUtc = [DateTimeOffset]::UtcNow.ToString('o')
    })
    Write-JsonExclusive -Path (Join-Path $controlRoot 'acquisition-terminal-receipt.v2.json') -Value ([pscustomobject][ordered]@{
        schema = 'gate14re-mq-formal-acquisition-terminal-receipt-v2'
        studyId = $studyId
        designId = $designId
        authorizationId = [string]$authorization.authorizationId
        status = 'PASS_RAW_FORMAL_MQ_COLLECTION_COMPLETE_ANALYSIS_NOT_STARTED'
        completedFreshUnityProcesses = $expectedProcessCount
        strictSerial = $true
        maximumObservedConcurrentMeasuredUnityProcesses = 1
        failureCount = 0
        replacementCount = 0
        acquisitionFreezeManifestSha256 = Get-Sha256Lower -Path $freezeManifestPath
        formalAnalysisStarted = $false
        completedAtUtc = [DateTimeOffset]::UtcNow.ToString('o')
    })
    exit 0
}
catch {
    if ($null -ne $currentProcess) {
        try {
            if (-not $currentProcess.HasExited) { $currentProcess.Kill($true); $currentProcess.WaitForExit() }
            $currentProcess.Dispose()
        }
        catch { }
    }
    if ($measuredRootCreated) {
        try {
            $controlRoot = Join-Path $MeasuredRoot '_control'
            $failureLedger = Join-Path $controlRoot 'failures-and-voids.raw.v2.jsonl'
            if (Test-Path -LiteralPath $failureLedger) {
                Append-JsonLine -Path $failureLedger -Value ([pscustomobject][ordered]@{
                    schema = 'gate14re-mq-formal-failure-row-v2'
                    state = 'FAILED_ATTEMPT_NO_RETRY_OR_RESUME'
                    processOrdinal = $currentOrdinal
                    errorType = $_.Exception.GetType().FullName
                    errorMessage = $_.Exception.Message
                    failedAtUtc = [DateTimeOffset]::UtcNow.ToString('o')
                })
            }
            $failureReceipt = Join-Path $controlRoot 'acquisition-failure-receipt.v2.json'
            if (-not (Test-Path -LiteralPath $failureReceipt)) {
                Write-JsonExclusive -Path $failureReceipt -Value ([pscustomobject][ordered]@{
                    schema = 'gate14re-mq-formal-acquisition-failure-receipt-v2'
                    studyId = $studyId
                    designId = $designId
                    status = 'FAIL_CLOSED_ATTEMPT_PRESERVED_NO_RETRY_OR_RESUME'
                    processOrdinal = $currentOrdinal
                    errorType = $_.Exception.GetType().FullName
                    errorMessage = $_.Exception.Message
                    formalAnalysisStarted = $false
                    failedAtUtc = [DateTimeOffset]::UtcNow.ToString('o')
                })
            }
        }
        catch { }
    }
    throw
}
