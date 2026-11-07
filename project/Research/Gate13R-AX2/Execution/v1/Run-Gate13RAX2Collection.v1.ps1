[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('Verification', 'Formal')]
    [string]$Mode,

    [Parameter(Mandatory = $true)]
    [string]$ProjectRoot,

    [Parameter(Mandatory = $true)]
    [string]$UnityExe,

    [Parameter(Mandatory = $true)]
    [string]$SchedulePath,

    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[0-9a-fA-F]{64}$')]
    [string]$ScheduleSha256,

    [Parameter(Mandatory = $true)]
    [string]$OutputSchemaPath,

    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[0-9a-fA-F]{64}$')]
    [string]$OutputSchemaSha256,

    [Parameter(Mandatory = $true)]
    [string]$ExecutionContractPath,

    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[0-9a-fA-F]{64}$')]
    [string]$ExecutionContractSha256,

    [Parameter(Mandatory = $true)]
    [string]$MeasuredRoot,

    [Parameter(Mandatory = $true)]
    [string]$PythonExe,

    [Parameter(Mandatory = $true)]
    [string]$StructuralToolPath,

    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[0-9a-fA-F]{64}$')]
    [string]$StructuralToolSha256,

    [string[]]$BlockIds = @(),

    [ValidateRange(0, 4)]
    [int]$InjectFailurePosition = 0,

    [switch]$DisableReplacement,

    [ValidateRange(60, 86400)]
    [int]$ProcessTimeoutSeconds = 3600,

    [string]$AuthorizationPath = '',

    [string]$AuthorizationSha256 = '',

    [string]$FinalReadinessPath = '',

    [string]$FinalReadinessSha256 = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:Utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$script:DesignId = 'gate13r-ax2-shared32-b48-four-treatment-v1'
$script:RunnerMethod = 'DDM.Research.Editor.Gate13RAX2BlockRunnerV1.Run'
$script:StartedAtUtc = [DateTime]::UtcNow
$script:LaunchedProcesses = 0
$script:AcceptedBlocks = 0
$script:WholeBlockReplacements = 0
$script:PlannedBlocks = 0

function Get-FullPathStrict {
    param([Parameter(Mandatory = $true)][string]$Path)
    return [System.IO.Path]::GetFullPath($Path)
}

function Get-Sha256 {
    param([Parameter(Mandatory = $true)][string]$Path)
    if (-not [System.IO.File]::Exists($Path)) { throw "Required file is missing: $Path" }
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Assert-FileBinding {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$ExpectedSha256,
        [Parameter(Mandatory = $true)][string]$Label
    )
    $actual = Get-Sha256 -Path $Path
    if ($actual -ne $ExpectedSha256.ToLowerInvariant()) {
        throw "$Label SHA-256 mismatch: expected $($ExpectedSha256.ToLowerInvariant()), got $actual."
    }
}

function Test-IsWithin {
    param(
        [Parameter(Mandatory = $true)][string]$Candidate,
        [Parameter(Mandatory = $true)][string]$Root
    )
    $normalizedRoot = (Get-FullPathStrict $Root).TrimEnd('\', '/') + [System.IO.Path]::DirectorySeparatorChar
    $normalizedCandidate = Get-FullPathStrict $Candidate
    return $normalizedCandidate.StartsWith($normalizedRoot, [System.StringComparison]::OrdinalIgnoreCase)
}

function ConvertTo-CanonicalCommandText {
    param([Parameter(Mandatory = $true)][string[]]$Arguments)
    return [string]::Join("`n", $Arguments)
}

function Get-StringSha256 {
    param([Parameter(Mandatory = $true)][string]$Value)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = $script:Utf8NoBom.GetBytes($Value)
        $hash = $sha.ComputeHash($bytes)
        return ([System.BitConverter]::ToString($hash)).Replace('-', '').ToLowerInvariant()
    }
    finally {
        $sha.Dispose()
    }
}

function Write-JsonNew {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)]$Value,
        [int]$Depth = 20
    )
    if ([System.IO.File]::Exists($Path)) { throw "Refusing to overwrite existing receipt: $Path" }
    $parent = [System.IO.Path]::GetDirectoryName($Path)
    if (-not [System.IO.Directory]::Exists($parent)) {
        [void][System.IO.Directory]::CreateDirectory($parent)
    }
    $json = ($Value | ConvertTo-Json -Depth $Depth).Replace("`r`n", "`n").Replace("`r", "`n") + "`n"
    [System.IO.File]::WriteAllText($Path, $json, $script:Utf8NoBom)
}

function Write-JsonReplace {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)]$Value,
        [int]$Depth = 20
    )
    $parent = [System.IO.Path]::GetDirectoryName($Path)
    if (-not [System.IO.Directory]::Exists($parent)) {
        [void][System.IO.Directory]::CreateDirectory($parent)
    }
    $json = ($Value | ConvertTo-Json -Depth $Depth).Replace("`r`n", "`n").Replace("`r", "`n") + "`n"
    $temporary = $Path + '.tmp-' + [Guid]::NewGuid().ToString('N')
    [System.IO.File]::WriteAllText($temporary, $json, $script:Utf8NoBom)
    [System.IO.File]::Move($temporary, $Path, $true)
}

function Read-JsonStrict {
    param([Parameter(Mandatory = $true)][string]$Path)
    if (-not [System.IO.File]::Exists($Path)) { throw "Required JSON is missing: $Path" }
    return (Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json)
}

function Get-ExecutionStatus {
    param([Parameter(Mandatory = $true)][string]$Status)
    return [ordered]@{
        schemaVersion = 1
        artifactKind = 'GATE13R-AX2-EXECUTION-STATUS'
        designId = $script:DesignId
        mode = $Mode
        status = $Status
        updatedAtUtc = [DateTime]::UtcNow.ToString('O')
        startedAtUtc = $script:StartedAtUtc.ToString('O')
        plannedBlocks = $script:PlannedBlocks
        acceptedBlocks = $script:AcceptedBlocks
        remainingBlocks = $script:PlannedBlocks - $script:AcceptedBlocks
        acceptedAnonymousSamples = $script:AcceptedBlocks * 4
        plannedAnonymousSamples = $script:PlannedBlocks * 4
        launchedProcesses = $script:LaunchedProcesses
        wholeBlockReplacements = $script:WholeBlockReplacements
        currentBlockId = $script:CurrentBlockId
        currentAttemptNumber = $script:CurrentAttemptNumber
        noPerAlgorithmRetryResumeTopUpMergeSkipReorder = $true
    }
}

function Update-ExecutionStatus {
    param([Parameter(Mandatory = $true)][string]$Status)
    Write-JsonReplace -Path (Join-Path $MeasuredRoot '_control\execution-status.json') -Value (Get-ExecutionStatus -Status $Status)
}

function Get-ScheduleRecords {
    param([Parameter(Mandatory = $true)][string]$Path)
    $records = New-Object System.Collections.Generic.List[object]
    $lineNumber = 0
    foreach ($line in [System.IO.File]::ReadLines($Path, $script:Utf8NoBom)) {
        $lineNumber++
        if ([string]::IsNullOrWhiteSpace($line)) { throw "Schedule contains a blank line at $lineNumber." }
        $record = $line | ConvertFrom-Json
        if ($record.designId -ne $script:DesignId) { throw "Schedule design mismatch at line $lineNumber." }
        $records.Add($record)
    }
    return $records.ToArray()
}

function Stop-ProcessTreeBestEffort {
    param([Parameter(Mandatory = $true)][System.Diagnostics.Process]$Process)
    try {
        $killWithTree = $Process.GetType().GetMethod('Kill', [Type[]]@([bool]))
        if ($null -ne $killWithTree) {
            $killWithTree.Invoke($Process, @($true))
        }
        else {
            Stop-Process -Id $Process.Id -Force -ErrorAction SilentlyContinue
        }
    }
    catch {
        Stop-Process -Id $Process.Id -Force -ErrorAction SilentlyContinue
    }
}

function Invoke-BlockAttempt {
    param(
        [Parameter(Mandatory = $true)]$Record,
        [Parameter(Mandatory = $true)][int]$AttemptNumber
    )
    $blockId = [string]$Record.blockId
    $attemptRelative = 'blocks/' + $blockId + '/attempt-' + $AttemptNumber.ToString('00')
    $attemptPath = Join-Path $MeasuredRoot ($attemptRelative.Replace('/', '\'))
    if ([System.IO.Directory]::Exists($attemptPath) -or [System.IO.File]::Exists($attemptPath)) {
        throw "Block attempt path already exists; resume/overwrite is forbidden: $attemptPath"
    }
    $logRelative = '_control/process-logs/' + $blockId + '-a' + $AttemptNumber.ToString('00') + '.log'
    $logPath = Join-Path $MeasuredRoot ($logRelative.Replace('/', '\'))
    $structuralRelative = '_control/structural-receipts/' + $blockId + '-a' + $AttemptNumber.ToString('00') + '.v1.json'
    $structuralPath = Join-Path $MeasuredRoot ($structuralRelative.Replace('/', '\'))
    $processReceiptRelative = '_control/process-receipts/' + $blockId + '-a' + $AttemptNumber.ToString('00') + '.v1.json'
    $processReceiptPath = Join-Path $MeasuredRoot ($processReceiptRelative.Replace('/', '\'))

    $arguments = @(
        '-batchmode',
        '-nographics',
        '-quit',
        '-projectPath', $ProjectRoot,
        '-executeMethod', $script:RunnerMethod,
        '-logFile', $logPath,
        '-ddmGate13RAX2SchedulePath', $SchedulePath,
        '-ddmGate13RAX2ScheduleSha256', $ScheduleSha256.ToLowerInvariant(),
        '-ddmGate13RAX2OutputSchemaPath', $OutputSchemaPath,
        '-ddmGate13RAX2OutputSchemaSha256', $OutputSchemaSha256.ToLowerInvariant(),
        '-ddmGate13RAX2ExecutionContractPath', $ExecutionContractPath,
        '-ddmGate13RAX2ExecutionContractSha256', $ExecutionContractSha256.ToLowerInvariant(),
        '-ddmGate13RAX2AllowedRoot', $MeasuredRoot,
        '-ddmGate13RAX2OutputDirectory', $attemptPath,
        '-ddmGate13RAX2BlockId', $blockId,
        '-ddmGate13RAX2Mode', $Mode
    )
    if ($InjectFailurePosition -gt 0) {
        $arguments += @('-ddmGate13RAX2InjectFailurePosition', $InjectFailurePosition.ToString([System.Globalization.CultureInfo]::InvariantCulture))
    }
    $commandText = ConvertTo-CanonicalCommandText -Arguments (@($UnityExe) + $arguments)
    $process = $null
    $processCreationUtc = ''
    $exitCode = $null
    $timedOut = $false
    $peakWorkingSetBytes = [int64]0
    $peakPrivateMemoryBytes = [int64]0
    $attemptStarted = [DateTime]::UtcNow
    $launchError = ''
    try {
        $process = Start-Process -FilePath $UnityExe -ArgumentList $arguments -PassThru -WindowStyle Hidden
        $script:LaunchedProcesses++
        try { $processCreationUtc = $process.StartTime.ToUniversalTime().ToString('O') } catch { $processCreationUtc = '' }
        while (-not $process.WaitForExit(250)) {
            $process.Refresh()
            if ($process.WorkingSet64 -gt $peakWorkingSetBytes) { $peakWorkingSetBytes = $process.WorkingSet64 }
            if ($process.PrivateMemorySize64 -gt $peakPrivateMemoryBytes) { $peakPrivateMemoryBytes = $process.PrivateMemorySize64 }
            if (([DateTime]::UtcNow - $attemptStarted).TotalSeconds -gt $ProcessTimeoutSeconds) {
                $timedOut = $true
                Stop-ProcessTreeBestEffort -Process $process
                [void]$process.WaitForExit(30000)
                break
            }
        }
        $process.Refresh()
        if ($process.WorkingSet64 -gt $peakWorkingSetBytes) { $peakWorkingSetBytes = $process.WorkingSet64 }
        if ($process.PrivateMemorySize64 -gt $peakPrivateMemoryBytes) { $peakPrivateMemoryBytes = $process.PrivateMemorySize64 }
        if ($process.HasExited) { $exitCode = $process.ExitCode }
    }
    catch {
        $launchError = $_.Exception.ToString()
    }

    $structuralPassed = $false
    $structuralOutput = ''
    $structuralExitCode = $null
    if (-not $timedOut -and $null -ne $exitCode -and $exitCode -eq 0 -and [System.IO.Directory]::Exists($attemptPath)) {
        $structuralArguments = @(
            $StructuralToolPath,
            'validate-block',
            '--attempt-root', $attemptPath,
            '--schedule', $SchedulePath,
            '--schedule-sha256', $ScheduleSha256.ToLowerInvariant(),
            '--schema', $OutputSchemaPath,
            '--schema-sha256', $OutputSchemaSha256.ToLowerInvariant(),
            '--contract-sha256', $ExecutionContractSha256.ToLowerInvariant(),
            '--block-id', $blockId,
            '--expected-process-id', $process.Id.ToString([System.Globalization.CultureInfo]::InvariantCulture),
            '--receipt', $structuralPath
        )
        $structuralOutput = (& $PythonExe @structuralArguments 2>&1 | Out-String).Trim()
        $structuralExitCode = $LASTEXITCODE
        $structuralPassed = $structuralExitCode -eq 0 -and [System.IO.File]::Exists($structuralPath)
    }

    $success = (-not $timedOut) -and [string]::IsNullOrEmpty($launchError) -and $exitCode -eq 0 -and $structuralPassed
    $receipt = [ordered]@{
        schemaVersion = 1
        artifactKind = 'GATE13R-AX2-PROCESS-RECEIPT'
        designId = $script:DesignId
        mode = $Mode
        blockId = $blockId
        attemptNumber = $AttemptNumber
        processId = if ($null -ne $process) { $process.Id } else { 0 }
        processStartUtc = $processCreationUtc
        startedAtUtc = $attemptStarted.ToString('O')
        completedAtUtc = [DateTime]::UtcNow.ToString('O')
        commandLineSha256 = Get-StringSha256 -Value $commandText
        runnerMethod = $script:RunnerMethod
        exitCode = $exitCode
        timedOut = $timedOut
        hardTimeoutSeconds = $ProcessTimeoutSeconds
        peakWorkingSetBytes = $peakWorkingSetBytes
        peakPrivateMemoryBytes = $peakPrivateMemoryBytes
        attemptRelativePath = $attemptRelative
        logRelativePath = $logRelative
        structuralValidationInvoked = $null -ne $structuralExitCode
        structuralValidationExitCode = $structuralExitCode
        structuralValidationPassed = $structuralPassed
        structuralReceiptRelativePath = if ($structuralPassed) { $structuralRelative } else { $null }
        structuralReceiptSha256 = if ($structuralPassed) { Get-Sha256 -Path $structuralPath } else { $null }
        structuralToolOutput = $structuralOutput
        launchError = $launchError
        freshProcessForCompleteBlockAttempt = $true
        perAlgorithmRetryResumeTopUpMergeSkipReorder = $false
        accepted = $success
    }
    Write-JsonNew -Path $processReceiptPath -Value $receipt
    return [pscustomobject]@{
        Success = $success
        BlockId = $blockId
        AttemptNumber = $AttemptNumber
        AttemptRelativePath = $attemptRelative
        AttemptPath = $attemptPath
        ProcessId = if ($null -ne $process) { $process.Id } else { 0 }
        ProcessStartUtc = $processCreationUtc
        ProcessReceiptRelativePath = $processReceiptRelative
        ProcessReceiptPath = $processReceiptPath
        StructuralReceiptRelativePath = if ($structuralPassed) { $structuralRelative } else { '' }
        StructuralReceiptPath = if ($structuralPassed) { $structuralPath } else { '' }
        ExitCode = $exitCode
        TimedOut = $timedOut
        LaunchError = $launchError
        StructuralPassed = $structuralPassed
    }
}

$ProjectRoot = Get-FullPathStrict $ProjectRoot
$UnityExe = Get-FullPathStrict $UnityExe
$SchedulePath = Get-FullPathStrict $SchedulePath
$OutputSchemaPath = Get-FullPathStrict $OutputSchemaPath
$ExecutionContractPath = Get-FullPathStrict $ExecutionContractPath
$MeasuredRoot = Get-FullPathStrict $MeasuredRoot
$PythonExe = Get-FullPathStrict $PythonExe
$StructuralToolPath = Get-FullPathStrict $StructuralToolPath
$ScheduleSha256 = $ScheduleSha256.ToLowerInvariant()
$OutputSchemaSha256 = $OutputSchemaSha256.ToLowerInvariant()
$ExecutionContractSha256 = $ExecutionContractSha256.ToLowerInvariant()
$StructuralToolSha256 = $StructuralToolSha256.ToLowerInvariant()
$script:CurrentBlockId = $null
$script:CurrentAttemptNumber = 0

try {
    if (-not [System.IO.Directory]::Exists($ProjectRoot)) { throw "Project root is missing: $ProjectRoot" }
    if (-not [System.IO.File]::Exists($UnityExe)) { throw "Unity executable is missing: $UnityExe" }
    if (-not [System.IO.File]::Exists($PythonExe)) { throw "Python executable is missing: $PythonExe" }
    Assert-FileBinding -Path $SchedulePath -ExpectedSha256 $ScheduleSha256 -Label 'Schedule'
    Assert-FileBinding -Path $OutputSchemaPath -ExpectedSha256 $OutputSchemaSha256 -Label 'Output schema'
    Assert-FileBinding -Path $ExecutionContractPath -ExpectedSha256 $ExecutionContractSha256 -Label 'Execution contract'
    Assert-FileBinding -Path $StructuralToolPath -ExpectedSha256 $StructuralToolSha256 -Label 'Structural tool'
    if ([System.IO.Directory]::Exists($MeasuredRoot) -or [System.IO.File]::Exists($MeasuredRoot)) {
        throw "Measured root already exists; resume/overwrite is forbidden: $MeasuredRoot"
    }
    $verificationRoot = Join-Path $ProjectRoot 'Research\Verification\Gate13R-AX2'
    $formalRoot = Join-Path $ProjectRoot 'Research\FormalRuns\Gate13R-AX2'
    if ($Mode -eq 'Verification') {
        if (-not (Test-IsWithin -Candidate $MeasuredRoot -Root $verificationRoot)) { throw 'Verification measured root is outside the isolated Gate13R-AX2 verification space.' }
        if ($BlockIds.Count -lt 1) { throw 'Verification mode requires one or more explicit block IDs.' }
    }
    else {
        if (-not (Test-IsWithin -Candidate $MeasuredRoot -Root $formalRoot)) { throw 'Formal measured root is outside Gate13R-AX2 FormalRuns.' }
        if ($BlockIds.Count -ne 0) { throw 'Formal mode forbids a block subset.' }
        if ($InjectFailurePosition -ne 0) { throw 'Formal mode forbids failure injection.' }
        if ([string]::IsNullOrWhiteSpace($AuthorizationPath) -or [string]::IsNullOrWhiteSpace($AuthorizationSha256)) { throw 'Formal mode requires a bound authorization receipt.' }
        if ([string]::IsNullOrWhiteSpace($FinalReadinessPath) -or [string]::IsNullOrWhiteSpace($FinalReadinessSha256)) { throw 'Formal mode requires a bound final-readiness receipt.' }
        $AuthorizationPath = Get-FullPathStrict $AuthorizationPath
        $FinalReadinessPath = Get-FullPathStrict $FinalReadinessPath
        Assert-FileBinding -Path $AuthorizationPath -ExpectedSha256 $AuthorizationSha256 -Label 'Authorization receipt'
        Assert-FileBinding -Path $FinalReadinessPath -ExpectedSha256 $FinalReadinessSha256 -Label 'Final readiness receipt'
        $authorization = Read-JsonStrict -Path $AuthorizationPath
        $readiness = Read-JsonStrict -Path $FinalReadinessPath
        if ($authorization.designId -ne $script:DesignId -or $authorization.formalCollectionAuthorized -ne $true) { throw 'Authorization receipt does not authorize this formal design.' }
        if ($readiness.designId -ne $script:DesignId -or $readiness.status -ne 'FINAL-READINESS-PASS') { throw 'Final readiness receipt does not pass for this formal design.' }
    }

    $allSchedule = Get-ScheduleRecords -Path $SchedulePath
    if ($allSchedule.Count -ne 1536) { throw "Frozen schedule must contain 1536 blocks; found $($allSchedule.Count)." }
    if ($Mode -eq 'Formal') {
        $selected = @($allSchedule)
    }
    else {
        $scheduleById = @{}
        foreach ($record in $allSchedule) { $scheduleById[[string]$record.blockId] = $record }
        $selectedList = New-Object System.Collections.Generic.List[object]
        $seen = @{}
        foreach ($blockId in $BlockIds) {
            if ($seen.ContainsKey($blockId)) { throw "Duplicate verification block ID: $blockId" }
            $seen[$blockId] = $true
            if (-not $scheduleById.ContainsKey($blockId)) { throw "Verification block is absent from frozen schedule: $blockId" }
            $selectedList.Add($scheduleById[$blockId])
        }
        $selected = @($selectedList.ToArray() | Sort-Object -Property globalBlockOrdinal)
    }
    $script:PlannedBlocks = $selected.Count
    if ($Mode -eq 'Formal' -and $script:PlannedBlocks -ne 1536) { throw 'Formal mode requires all 1536 blocks.' }

    [void][System.IO.Directory]::CreateDirectory($MeasuredRoot)
    foreach ($relative in @('_control', '_control\accepted-blocks', '_control\process-logs', '_control\process-receipts', '_control\structural-receipts', 'blocks')) {
        [void][System.IO.Directory]::CreateDirectory((Join-Path $MeasuredRoot $relative))
    }
    $launch = [ordered]@{
        schemaVersion = 1
        artifactKind = 'GATE13R-AX2-LAUNCH-RECEIPT'
        designId = $script:DesignId
        mode = $Mode
        status = if ($Mode -eq 'Formal') { 'FORMAL-ACQUISITION-LAUNCHED' } else { 'VERIFICATION-ACQUISITION-LAUNCHED' }
        launchedAtUtc = $script:StartedAtUtc.ToString('O')
        projectRoot = $ProjectRoot
        measuredRoot = $MeasuredRoot
        plannedBlocks = $script:PlannedBlocks
        plannedAnonymousSamples = $script:PlannedBlocks * 4
        selectedBlockIds = @($selected | ForEach-Object { $_.blockId })
        schedule = [ordered]@{ path = $SchedulePath; sha256 = $ScheduleSha256 }
        outputSchema = [ordered]@{ path = $OutputSchemaPath; sha256 = $OutputSchemaSha256 }
        executionContract = [ordered]@{ path = $ExecutionContractPath; sha256 = $ExecutionContractSha256 }
        structuralTool = [ordered]@{ path = $StructuralToolPath; sha256 = $StructuralToolSha256 }
        unityExe = [ordered]@{ path = $UnityExe; sha256 = Get-Sha256 -Path $UnityExe }
        pythonExe = [ordered]@{ path = $PythonExe; sha256 = Get-Sha256 -Path $PythonExe }
        maximumWholeBlockTechnicalReplacements = if ($DisableReplacement) { 0 } else { 1 }
        processHardTimeoutSeconds = $ProcessTimeoutSeconds
        failureInjectionPosition = $InjectFailurePosition
        perAlgorithmRetryResumeTopUpMergeSkipReorder = $false
        formalCollectionAuthorized = $Mode -eq 'Formal'
        authorization = if ($Mode -eq 'Formal') { [ordered]@{ path = $AuthorizationPath; sha256 = $AuthorizationSha256.ToLowerInvariant() } } else { $null }
        finalReadiness = if ($Mode -eq 'Formal') { [ordered]@{ path = $FinalReadinessPath; sha256 = $FinalReadinessSha256.ToLowerInvariant() } } else { $null }
    }
    Write-JsonNew -Path (Join-Path $MeasuredRoot '_control\launch-receipt.v1.json') -Value $launch
    Update-ExecutionStatus -Status 'ACQUISITION-IN-PROGRESS'

    foreach ($record in $selected) {
        $script:CurrentBlockId = [string]$record.blockId
        $accepted = $false
        $maximumAttempts = if ($DisableReplacement) { 1 } else { 2 }
        for ($attemptNumber = 1; $attemptNumber -le $maximumAttempts; $attemptNumber++) {
            $script:CurrentAttemptNumber = $attemptNumber
            if ($attemptNumber -eq 2) { $script:WholeBlockReplacements++ }
            Update-ExecutionStatus -Status 'ACQUISITION-IN-PROGRESS'
            $attempt = Invoke-BlockAttempt -Record $record -AttemptNumber $attemptNumber
            if ($attempt.Success) {
                $acceptedReceipt = [ordered]@{
                    schemaVersion = 1
                    artifactKind = 'GATE13R-AX2-ACCEPTED-BLOCK'
                    designId = $script:DesignId
                    blockId = [string]$record.blockId
                    campaignOrdinal = [int]$record.campaignOrdinal
                    campaignBlockOrdinal = [int]$record.campaignBlockOrdinal
                    globalBlockOrdinal = [int]$record.globalBlockOrdinal
                    attemptNumber = $attemptNumber
                    attemptRelativePath = $attempt.AttemptRelativePath
                    processId = $attempt.ProcessId
                    processStartUtc = $attempt.ProcessStartUtc
                    processReceiptRelativePath = $attempt.ProcessReceiptRelativePath
                    processReceiptSha256 = Get-Sha256 -Path $attempt.ProcessReceiptPath
                    structuralReceiptRelativePath = $attempt.StructuralReceiptRelativePath
                    structuralReceiptSha256 = Get-Sha256 -Path $attempt.StructuralReceiptPath
                    acceptedAtUtc = [DateTime]::UtcNow.ToString('O')
                    wholeBlockReplacementUsed = $attemptNumber -eq 2
                    perAlgorithmRetryResumeTopUpMergeSkipReorder = $false
                }
                Write-JsonNew -Path (Join-Path $MeasuredRoot ('_control\accepted-blocks\' + [string]$record.blockId + '.v1.json')) -Value $acceptedReceipt
                $script:AcceptedBlocks++
                $accepted = $true
                Update-ExecutionStatus -Status 'ACQUISITION-IN-PROGRESS'
                break
            }
        }
        if (-not $accepted) {
            throw "Block $($record.blockId) failed all authorized whole-block attempts."
        }
    }

    $script:CurrentBlockId = $null
    $script:CurrentAttemptNumber = 0
    $completion = [ordered]@{
        schemaVersion = 1
        artifactKind = 'GATE13R-AX2-ACQUISITION-COMPLETE'
        designId = $script:DesignId
        mode = $Mode
        status = if ($Mode -eq 'Formal') { 'FORMAL-ACQUISITION-COMPLETE' } else { 'VERIFICATION-ACQUISITION-COMPLETE' }
        completedAtUtc = [DateTime]::UtcNow.ToString('O')
        plannedBlocks = $script:PlannedBlocks
        acceptedBlocks = $script:AcceptedBlocks
        acceptedAnonymousSamples = $script:AcceptedBlocks * 4
        launchedProcesses = $script:LaunchedProcesses
        wholeBlockReplacements = $script:WholeBlockReplacements
        freshProcessPerCompleteBlockAttempt = $true
        noPerAlgorithmRetryResumeTopUpMergeSkipReorder = $true
        rawCommitPending = $true
    }
    Write-JsonNew -Path (Join-Path $MeasuredRoot '_control\acquisition-complete.v1.json') -Value $completion
    $terminalStatus = if ($Mode -eq 'Formal') { 'FORMAL-RAW-COMMIT-PENDING' } else { 'VERIFICATION-RAW-COMMIT-PENDING' }
    Update-ExecutionStatus -Status $terminalStatus
    Write-Output ($completion | ConvertTo-Json -Compress)
    exit 0
}
catch {
    $message = $_.Exception.Message
    if ([System.IO.Directory]::Exists($MeasuredRoot)) {
        try {
            $failurePath = Join-Path $MeasuredRoot '_control\failure-receipt.v1.json'
            if (-not [System.IO.File]::Exists($failurePath)) {
                $failure = [ordered]@{
                    schemaVersion = 1
                    artifactKind = 'GATE13R-AX2-ACQUISITION-FAILURE'
                    designId = $script:DesignId
                    mode = $Mode
                    status = 'FAIL-CLOSED'
                    failedAtUtc = [DateTime]::UtcNow.ToString('O')
                    currentBlockId = $script:CurrentBlockId
                    currentAttemptNumber = $script:CurrentAttemptNumber
                    plannedBlocks = $script:PlannedBlocks
                    acceptedBlocks = $script:AcceptedBlocks
                    launchedProcesses = $script:LaunchedProcesses
                    wholeBlockReplacements = $script:WholeBlockReplacements
                    errorType = $_.Exception.GetType().FullName
                    message = $message
                    automaticWholeAttemptRetry = $false
                    perAlgorithmRetryResumeTopUpMergeSkipReorder = $false
                    formalCollectionStarted = $Mode -eq 'Formal'
                }
                Write-JsonNew -Path $failurePath -Value $failure
            }
            Update-ExecutionStatus -Status 'FAIL-CLOSED'
        }
        catch {
            [Console]::Error.WriteLine("Failed to persist failure receipt: $($_.Exception.Message)")
        }
    }
    [Console]::Error.WriteLine($message)
    exit 2
}
