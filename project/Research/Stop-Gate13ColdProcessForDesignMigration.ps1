[CmdletBinding()]
param(
    [string]$ProjectPath = (Split-Path -Parent $PSScriptRoot),
    [int]$OrchestratorProcessId = 3476
)

$ErrorActionPreference = 'Stop'
$ProjectPath = [System.IO.Path]::GetFullPath($ProjectPath)
$researchPath = Join-Path $ProjectPath 'Research'
$formalRoot = [System.IO.Path]::GetFullPath((Join-Path $ProjectPath 'Research\FormalRuns\Gate13\v1'))
$expectedFormalRoot = [System.IO.Path]::GetFullPath('H:\DDM_Final_Project\Research\FormalRuns\Gate13\v1')
$manifestPath = Join-Path $researchPath 'Gate13_ColdProcess_Partial_Output_Manifest.v1.json'
$preTerminationPath = Join-Path $researchPath 'Gate13_ColdProcess_PreTermination_Snapshot.v1.json'
$receiptPath = Join-Path $researchPath 'Gate13_ColdProcess_Termination_Receipt.v1.json'
$exclusionPath = Join-Path $researchPath 'Gate13_ColdProcess_Exclusion_Marker.v1.json'

function ConvertTo-LowerSha256 {
    param([Parameter(Mandatory = $true)][string]$Path)
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Write-AtomicJson {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)]$Value,
        [int]$Depth = 30
    )
    $directory = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $directory -PathType Container)) {
        New-Item -ItemType Directory -Path $directory | Out-Null
    }
    $temporaryPath = $Path + '.tmp-' + [Guid]::NewGuid().ToString('N')
    $json = $Value | ConvertTo-Json -Depth $Depth
    [System.IO.File]::WriteAllText($temporaryPath, $json + [Environment]::NewLine, (New-Object System.Text.UTF8Encoding($false)))
    Move-Item -LiteralPath $temporaryPath -Destination $Path -Force
}

function Get-ProcessTable {
    return @(Get-CimInstance Win32_Process | Select-Object ProcessId, ParentProcessId, Name, CreationDate, ExecutablePath, CommandLine)
}

function Get-OwnedProcessTree {
    param(
        [Parameter(Mandatory = $true)][int]$RootProcessId,
        [Parameter(Mandatory = $true)][object[]]$ProcessTable
    )
    $byParent = @{}
    foreach ($process in $ProcessTable) {
        $parentKey = [int]$process.ParentProcessId
        if (-not $byParent.ContainsKey($parentKey)) { $byParent[$parentKey] = New-Object System.Collections.Generic.List[object] }
        $byParent[$parentKey].Add($process)
    }
    $result = New-Object System.Collections.Generic.List[object]
    $queue = New-Object System.Collections.Generic.Queue[int]
    $queue.Enqueue($RootProcessId)
    while ($queue.Count -gt 0) {
        $current = $queue.Dequeue()
        $process = @($ProcessTable | Where-Object { [int]$_.ProcessId -eq $current })
        if ($process.Count -eq 1) { $result.Add($process[0]) }
        if ($byParent.ContainsKey($current)) {
            foreach ($child in $byParent[$current]) { $queue.Enqueue([int]$child.ProcessId) }
        }
    }
    return @($result.ToArray() | Sort-Object ProcessId)
}

function Convert-ProcessRecord {
    param([Parameter(Mandatory = $true)]$Process)
    return [ordered]@{
        processId = [int]$Process.ProcessId
        parentProcessId = [int]$Process.ParentProcessId
        name = [string]$Process.Name
        creationDate = if ($null -eq $Process.CreationDate) { $null } else { ([DateTime]$Process.CreationDate).ToString('o') }
        executablePath = [string]$Process.ExecutablePath
        commandLine = [string]$Process.CommandLine
    }
}

function Get-ActiveRunIdentity {
    param([Parameter(Mandatory = $true)][object[]]$OwnedProcesses)
    $scenarioProcess = @($OwnedProcesses | Where-Object { $_.CommandLine -like '*Run-Gate13FormalScenarioCampaign.ps1*' } | Select-Object -First 1)
    $workloadProcess = @($OwnedProcesses | Where-Object { $_.CommandLine -like '*Run-PlanningWorkload.ps1*' } | Select-Object -First 1)
    $unityProcess = @($OwnedProcesses | Where-Object { $_.Name -ieq 'Unity.exe' -and $_.CommandLine -like '*ResearchPlanningBatchCommand.Run*' } | Select-Object -First 1)
    $scenarioCommand = if ($scenarioProcess.Count -eq 1) { [string]$scenarioProcess[0].CommandLine } else { '' }
    $workloadCommand = if ($workloadProcess.Count -eq 1) { [string]$workloadProcess[0].CommandLine } else { '' }
    $campaignOrdinal = $null
    if ($scenarioCommand -match '(?i)-CampaignOrdinal\s+(\d+)') { $campaignOrdinal = [int]$Matches[1] }
    $runId = $null
    if ($workloadCommand -match '(?i)-RunId\s+([^\s\"]+)') { $runId = $Matches[1] }
    $algorithm = $null
    if ($workloadCommand -match '(?i)-Algorithm\s+([^\s\"]+)') { $algorithm = $Matches[1] }
    $outputDirectory = $null
    if ($workloadCommand -match '(?i)-OutputDirectory\s+([^\s\"]+)') { $outputDirectory = $Matches[1] }
    $block = $null
    $position = $null
    if ($runId -match '(?i)-b(\d+)-p(\d+)-') { $block = [int]$Matches[1]; $position = [int]$Matches[2] }
    $campaignId = $null
    if ($runId -match '^(g13-c\d{3}-.+)-b\d+-p\d+-[^-]+(?:-[^-]+)?$') { $campaignId = $Matches[1] }
    return [ordered]@{
        campaignOrdinal = $campaignOrdinal
        campaignId = $campaignId
        williamsBlock = $block
        position = $position
        algorithm = $algorithm
        runId = $runId
        outputDirectory = $outputDirectory
        scenarioRunnerProcessId = if ($scenarioProcess.Count -eq 1) { [int]$scenarioProcess[0].ProcessId } else { $null }
        workloadRunnerProcessId = if ($workloadProcess.Count -eq 1) { [int]$workloadProcess[0].ProcessId } else { $null }
        unityProcessId = if ($unityProcess.Count -eq 1) { [int]$unityProcess[0].ProcessId } else { $null }
    }
}

function Get-FileInventory {
    param([Parameter(Mandatory = $true)][string]$Root)
    $records = New-Object System.Collections.Generic.List[object]
    foreach ($file in @(Get-ChildItem -LiteralPath $Root -Recurse -File -Force | Sort-Object FullName)) {
        $relativePath = $file.FullName.Substring($Root.Length).TrimStart('\').Replace('\', '/')
        $hash = $null
        $hashError = $null
        try { $hash = ConvertTo-LowerSha256 -Path $file.FullName } catch { $hashError = $_.Exception.Message }
        $records.Add([pscustomobject][ordered]@{
            relativePath = $relativePath
            lengthBytes = [int64]$file.Length
            lastWriteTimeUtc = $file.LastWriteTimeUtc.ToString('o')
            sha256 = $hash
            hashError = $hashError
        })
    }
    return @($records.ToArray())
}

function Get-CompletedSampleEvidence {
    param([Parameter(Mandatory = $true)][string]$Root)
    $completed = New-Object System.Collections.Generic.List[object]
    foreach ($manifestFile in @(Get-ChildItem -LiteralPath $Root -Recurse -Filter 'manifest.json' -File -Force | Sort-Object FullName)) {
        try {
            $manifest = Get-Content -LiteralPath $manifestFile.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($manifest.completed -eq $true -and -not [string]::IsNullOrWhiteSpace([string]$manifest.runId)) {
                $completed.Add([pscustomobject][ordered]@{
                    runId = [string]$manifest.runId
                    algorithmId = [string]$manifest.algorithmId
                    manifestRelativePath = $manifestFile.FullName.Substring($Root.Length).TrimStart('\').Replace('\', '/')
                    manifestSha256 = ConvertTo-LowerSha256 -Path $manifestFile.FullName
                })
            }
        } catch {
            # An incomplete or concurrently written manifest is not a completed sample.
        }
    }
    return @($completed.ToArray())
}

function Get-ProtectedEvidenceHashes {
    $paths = @(
        'Research\Gate13_Formal_Campaign_Config.v1.json',
        'Research\Gate13_Readiness_Amendment.v1.json',
        'Research\Gate13_Execution_Authorization.v1.json',
        'Research\Gate13_Execution_Authorization.v2.json',
        'Research\Gate13_Formal_Launch_Attempt1_Checkpoint.md',
        'Research\Gate13_Formal_Launch_Attempt2_Checkpoint.md',
        'Research\FormalRuns\Gate13\v1\frozen-config.json',
        'Research\FormalRuns\Gate13\v1\execution-authorization.json',
        'Research\FormalRuns\Gate13\v1\launch-preflight.json',
        'Research\FormalRuns\Gate13\v1\formal-checkpoint.json'
    )
    $records = New-Object System.Collections.Generic.List[object]
    foreach ($relativePath in $paths) {
        $path = Join-Path $ProjectPath $relativePath
        $records.Add([pscustomobject][ordered]@{
            relativePath = $relativePath.Replace('\', '/')
            exists = Test-Path -LiteralPath $path -PathType Leaf
            lengthBytes = if (Test-Path -LiteralPath $path -PathType Leaf) { [int64](Get-Item -LiteralPath $path).Length } else { $null }
            sha256 = if (Test-Path -LiteralPath $path -PathType Leaf) { ConvertTo-LowerSha256 -Path $path } else { $null }
        })
    }
    return @($records.ToArray())
}

if ($formalRoot -cne $expectedFormalRoot) { throw "Resolved formal root differs from the explicitly authorized target: $formalRoot" }
if (-not (Test-Path -LiteralPath $formalRoot -PathType Container)) { throw "Authorized cold-process formal root not found: $formalRoot" }
foreach ($path in @($manifestPath, $preTerminationPath, $receiptPath, $exclusionPath)) {
    if (Test-Path -LiteralPath $path) { throw "Create-new evidence policy refuses overwrite: $path" }
}

$capturedAt = Get-Date
$processTable = Get-ProcessTable
$ownedProcesses = Get-OwnedProcessTree -RootProcessId $OrchestratorProcessId -ProcessTable $processTable
if (@($ownedProcesses | Where-Object { [int]$_.ProcessId -eq $OrchestratorProcessId }).Count -ne 1) { throw "Gate 13 orchestrator PID $OrchestratorProcessId is not running." }
$orchestrator = @($ownedProcesses | Where-Object { [int]$_.ProcessId -eq $OrchestratorProcessId })[0]
if ([string]$orchestrator.CommandLine -notlike '*Run-Gate13FormalCampaign.ps1*' -or [string]$orchestrator.CommandLine -notlike '*Gate13_Execution_Authorization.v2.json*') {
    throw 'The supplied PID is not the authorized Gate 13 attempt-2 orchestrator.'
}
$activeRun = Get-ActiveRunIdentity -OwnedProcesses $ownedProcesses
if ($null -eq $activeRun.scenarioRunnerProcessId) { throw 'No owned Gate 13 scenario runner was found; refusing an ambiguous termination.' }

$checkpointPath = Join-Path $formalRoot 'formal-checkpoint.json'
$checkpointBefore = Get-Content -LiteralPath $checkpointPath -Raw -Encoding UTF8 | ConvertFrom-Json
$inventory = Get-FileInventory -Root $formalRoot
$completedSamples = Get-CompletedSampleEvidence -Root $formalRoot
$inventoryBytes = [int64](($inventory | Measure-Object -Property lengthBytes -Sum).Sum)
$lastWrite = @($inventory | Sort-Object lastWriteTimeUtc -Descending | Select-Object -First 1)

$manifest = [ordered]@{
    schemaVersion = 1
    manifestId = 'gate13-cold-process-partial-output-manifest-v1'
    capturedAt = $capturedAt.ToString('o')
    captureBoundary = 'pre-termination-live-filesystem-snapshot'
    formalRoot = $formalRoot
    disposition = @('USER-TERMINATED-DESIGN-CHANGE', 'EXCLUDED_FROM_ANALYSIS', 'NO-AUTO-RETRY', 'NO-RESUME', 'SUPERSEDED-BY-PROCESS-REUSE-DESIGN')
    fileCount = @($inventory).Count
    rawByteCount = $inventoryBytes
    lastWriteTimeUtc = if ($lastWrite.Count -eq 1) { $lastWrite[0].lastWriteTimeUtc } else { $null }
    completedSampleCount = @($completedSamples).Count
    completedSamples = $completedSamples
    files = $inventory
}
Write-AtomicJson -Path $manifestPath -Value $manifest -Depth 40
$manifestSha256 = ConvertTo-LowerSha256 -Path $manifestPath

$preTermination = [ordered]@{
    schemaVersion = 1
    snapshotId = 'gate13-cold-process-pre-termination-snapshot-v1'
    capturedAt = $capturedAt.ToString('o')
    formalRoot = $formalRoot
    formalRootResolvedMatchesAuthorizedTarget = $true
    orchestratorProcessId = $OrchestratorProcessId
    activeRun = $activeRun
    processTree = @($ownedProcesses | ForEach-Object { Convert-ProcessRecord -Process $_ })
    checkpointBefore = $checkpointBefore
    checkpointBeforeSha256 = ConvertTo-LowerSha256 -Path $checkpointPath
    completedSampleCountFromCompletedManifests = @($completedSamples).Count
    partialOutputFileCount = @($inventory).Count
    partialOutputRawByteCount = $inventoryBytes
    partialOutputLastWriteTimeUtc = if ($lastWrite.Count -eq 1) { $lastWrite[0].lastWriteTimeUtc } else { $null }
    partialOutputManifestRelativePath = 'Research/Gate13_ColdProcess_Partial_Output_Manifest.v1.json'
    partialOutputManifestSha256 = $manifestSha256
    protectedEvidenceHashes = Get-ProtectedEvidenceHashes
}
Write-AtomicJson -Path $preTerminationPath -Value $preTermination -Depth 40
$preTerminationSha256 = ConvertTo-LowerSha256 -Path $preTerminationPath

$initialReceipt = [ordered]@{
    schemaVersion = 1
    receiptId = 'gate13-cold-process-user-termination-design-change-v1'
    status = 'pre-termination-evidence-captured'
    savedAt = (Get-Date).ToString('o')
    authorizationReference = 'user-message-2026-10-06-gate13-cold-process-to-process-reuse-controlled-design-migration'
    attemptNumber = 2
    formalRoot = $formalRoot
    dispositions = @('USER-TERMINATED-DESIGN-CHANGE', 'EXCLUDED_FROM_ANALYSIS', 'NO-AUTO-RETRY', 'NO-RESUME', 'SUPERSEDED-BY-PROCESS-REUSE-DESIGN')
    processReuseFormalCampaignAuthorized = $false
    automaticRetryAuthorized = $false
    automaticResumeAuthorized = $false
    preTerminationSnapshotRelativePath = 'Research/Gate13_ColdProcess_PreTermination_Snapshot.v1.json'
    preTerminationSnapshotSha256 = $preTerminationSha256
    partialOutputManifestRelativePath = 'Research/Gate13_ColdProcess_Partial_Output_Manifest.v1.json'
    partialOutputManifestSha256 = $manifestSha256
    activeRun = $activeRun
}
Write-AtomicJson -Path $receiptPath -Value $initialReceipt -Depth 30

$scenarioRunnerProcessId = [int]$activeRun.scenarioRunnerProcessId
$taskKillOutput = @(& "$env:SystemRoot\System32\taskkill.exe" /PID $scenarioRunnerProcessId /T /F 2>&1 | ForEach-Object { [string]$_ })
$taskKillExitCode = $LASTEXITCODE

$deadline = (Get-Date).AddSeconds(45)
while ((Get-Date) -lt $deadline -and (Get-Process -Id $OrchestratorProcessId -ErrorAction SilentlyContinue)) {
    Start-Sleep -Milliseconds 500
}
$orchestratorExitedNaturallyAfterChildFailure = -not [bool](Get-Process -Id $OrchestratorProcessId -ErrorAction SilentlyContinue)
$orchestratorForcedTermination = $false
if (-not $orchestratorExitedNaturallyAfterChildFailure) {
    $orchestratorForcedTermination = $true
    & "$env:SystemRoot\System32\taskkill.exe" /PID $OrchestratorProcessId /T /F | Out-Null
    Start-Sleep -Seconds 2
}

$postProcessTable = Get-ProcessTable
$remainingOwned = @(Get-OwnedProcessTree -RootProcessId $OrchestratorProcessId -ProcessTable $postProcessTable)
$checkpointAfter = if (Test-Path -LiteralPath $checkpointPath -PathType Leaf) { Get-Content -LiteralPath $checkpointPath -Raw -Encoding UTF8 | ConvertFrom-Json } else { $null }
$failurePath = Join-Path $formalRoot 'formal-failure.json'
$failure = if (Test-Path -LiteralPath $failurePath -PathType Leaf) { Get-Content -LiteralPath $failurePath -Raw -Encoding UTF8 | ConvertFrom-Json } else { $null }
$postFiles = @(Get-ChildItem -LiteralPath $formalRoot -Recurse -File -Force)
$postBytes = [int64](($postFiles | Measure-Object -Property Length -Sum).Sum)
$postLastWrite = @($postFiles | Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 1)

$exclusionMarker = [ordered]@{
    schemaVersion = 1
    markerId = 'gate13-cold-process-exclusion-marker-v1'
    savedAt = (Get-Date).ToString('o')
    formalRoot = $formalRoot
    status = 'USER-TERMINATED-DESIGN-CHANGE'
    analysisDisposition = 'EXCLUDED_FROM_ANALYSIS'
    retryPolicy = 'NO-AUTO-RETRY'
    resumePolicy = 'NO-RESUME'
    supersededBy = 'GATE13-R2-PROCESS-REUSE-DESIGN'
    allowedUses = @('historical-audit', 'termination-evidence', 'non-inferential-diagnostic-reference')
    prohibitedUses = @('formal-inference', 'formal-sample-size-estimation', 'gate14-formal-analysis', 'merge-with-process-reuse-results')
    coldProcessOutputMayBeModified = $false
    processReuseFormalCampaignAuthorized = $false
}
Write-AtomicJson -Path $exclusionPath -Value $exclusionMarker -Depth 20
$exclusionSha256 = ConvertTo-LowerSha256 -Path $exclusionPath

$finalReceipt = [ordered]@{
    schemaVersion = 1
    receiptId = 'gate13-cold-process-user-termination-design-change-v1'
    status = 'terminated-and-excluded'
    savedAt = (Get-Date).ToString('o')
    authorizationReference = 'user-message-2026-10-06-gate13-cold-process-to-process-reuse-controlled-design-migration'
    attemptNumber = 2
    formalRoot = $formalRoot
    dispositions = @('USER-TERMINATED-DESIGN-CHANGE', 'EXCLUDED_FROM_ANALYSIS', 'NO-AUTO-RETRY', 'NO-RESUME', 'SUPERSEDED-BY-PROCESS-REUSE-DESIGN')
    processReuseFormalCampaignAuthorized = $false
    automaticRetryAuthorized = $false
    automaticResumeAuthorized = $false
    preTerminationSnapshotRelativePath = 'Research/Gate13_ColdProcess_PreTermination_Snapshot.v1.json'
    preTerminationSnapshotSha256 = $preTerminationSha256
    partialOutputManifestRelativePath = 'Research/Gate13_ColdProcess_Partial_Output_Manifest.v1.json'
    partialOutputManifestSha256 = $manifestSha256
    exclusionMarkerRelativePath = 'Research/Gate13_ColdProcess_Exclusion_Marker.v1.json'
    exclusionMarkerSha256 = $exclusionSha256
    activeRunAtTermination = $activeRun
    terminatedScenarioRunnerProcessId = $scenarioRunnerProcessId
    taskKillExitCode = $taskKillExitCode
    taskKillOutput = $taskKillOutput
    orchestratorExitedAfterOwnedChildFailure = $orchestratorExitedNaturallyAfterChildFailure
    orchestratorForcedTermination = $orchestratorForcedTermination
    remainingOwnedProcessCount = @($remainingOwned).Count
    checkpointAfter = $checkpointAfter
    checkpointAfterSha256 = if (Test-Path -LiteralPath $checkpointPath -PathType Leaf) { ConvertTo-LowerSha256 -Path $checkpointPath } else { $null }
    formalFailure = $failure
    formalFailureSha256 = if (Test-Path -LiteralPath $failurePath -PathType Leaf) { ConvertTo-LowerSha256 -Path $failurePath } else { $null }
    completedSampleCountFromPreTerminationManifest = @($completedSamples).Count
    postTerminationFileCount = @($postFiles).Count
    postTerminationRawByteCount = $postBytes
    postTerminationLastWriteTimeUtc = if ($postLastWrite.Count -eq 1) { $postLastWrite[0].LastWriteTimeUtc.ToString('o') } else { $null }
    rootContentPolicy = 'frozen-historical-evidence-no-future-writes'
}
Write-AtomicJson -Path $receiptPath -Value $finalReceipt -Depth 40

# Apply a reversible filesystem read-only attribute only after every owned process has exited.
$readOnlyFileCount = 0
foreach ($file in @(Get-ChildItem -LiteralPath $formalRoot -Recurse -File -Force)) {
    if (-not $file.IsReadOnly) { $file.IsReadOnly = $true }
    $readOnlyFileCount++
}
$rootItem = Get-Item -LiteralPath $formalRoot -Force
$rootItem.Attributes = $rootItem.Attributes -bor [System.IO.FileAttributes]::ReadOnly

[pscustomobject][ordered]@{
    passed = ($taskKillExitCode -eq 0 -and @($remainingOwned).Count -eq 0 -and $null -ne $checkpointAfter -and [string]$checkpointAfter.status -eq 'failed-no-auto-retry')
    receiptPath = $receiptPath
    receiptSha256 = ConvertTo-LowerSha256 -Path $receiptPath
    manifestPath = $manifestPath
    manifestSha256 = $manifestSha256
    exclusionMarkerPath = $exclusionPath
    exclusionMarkerSha256 = $exclusionSha256
    completedSampleCount = @($completedSamples).Count
    preTerminationFileCount = @($inventory).Count
    preTerminationRawByteCount = $inventoryBytes
    postTerminationFileCount = @($postFiles).Count
    postTerminationRawByteCount = $postBytes
    readOnlyFileCount = $readOnlyFileCount
    checkpointStatus = if ($null -eq $checkpointAfter) { $null } else { [string]$checkpointAfter.status }
    remainingOwnedProcessCount = @($remainingOwned).Count
    orchestratorForcedTermination = $orchestratorForcedTermination
} | ConvertTo-Json -Depth 10
