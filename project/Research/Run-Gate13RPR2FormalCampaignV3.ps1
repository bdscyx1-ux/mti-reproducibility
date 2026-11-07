[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$ProjectPath,
    [Parameter(Mandatory = $true)][string]$ConfigPath,
    [Parameter(Mandatory = $true)][string]$SchedulePath,
    [Parameter(Mandatory = $true)][string]$ScheduleManifestPath,
    [Parameter(Mandatory = $true)][string]$ReadinessPath,
    [Parameter(Mandatory = $true)][string]$AdapterProvenancePath,
    [Parameter(Mandatory = $true)][string]$ExecutionReceiptPath,
    [string]$UnityPath = 'H:\UnityEditor\2022.3.30f1c1\Editor\Unity.exe',
    [switch]$BindingSmokeOnly,
    [int]$BlockTimeoutSeconds = 3600
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if ([string]::IsNullOrWhiteSpace($ProjectPath) -or -not [IO.Path]::IsPathRooted($ProjectPath)) { throw 'An explicit absolute ProjectPath is required.' }
$ProjectPath = [IO.Path]::GetFullPath($ProjectPath)
if ($BindingSmokeOnly) {
    Write-Output "BINDING-SMOKE-PASSED|Run-Gate13RPR2FormalCampaignV3|$ProjectPath"
    exit 0
}

Import-Module (Join-Path $ProjectPath 'Research\Gate13RPR2FormalExecutionV3.psm1') -Force
$ConfigPath = [IO.Path]::GetFullPath($ConfigPath)
$SchedulePath = [IO.Path]::GetFullPath($SchedulePath)
$ScheduleManifestPath = [IO.Path]::GetFullPath($ScheduleManifestPath)
$ReadinessPath = [IO.Path]::GetFullPath($ReadinessPath)
$AdapterProvenancePath = [IO.Path]::GetFullPath($AdapterProvenancePath)
$ExecutionReceiptPath = [IO.Path]::GetFullPath($ExecutionReceiptPath)
$UnityPath = [IO.Path]::GetFullPath($UnityPath)
$formalRoot = [IO.Path]::GetFullPath((Join-Path $ProjectPath 'Research\FormalRuns\Gate13R_RQAligned_S48H48\v1')).TrimEnd('\', '/')
$statusPath = Join-Path $ProjectPath 'Research\Gate13R_PR2_Formal_Execution_Status.v1.json'
$modulePath = Join-Path $ProjectPath 'Research\Gate13RPR2FormalExecutionV3.psm1'
$blockWrapper = Join-Path $ProjectPath 'Research\Run-Gate13RPR2FormalBlockV3.ps1'
$commandPath = Join-Path $ProjectPath 'Assets\_Scripts\Research\Editor\Gate13RPR2FormalBatchCommandV2.cs'
$twoPhasePath = Join-Path $ProjectPath 'Research\Gate13R_PR2_RawAnalysis_TwoPhaseCommit_Amendment.v1.json'
$specificationPath = Join-Path $ProjectPath 'Research\Gate13R_PR2_RawAnalysis_TwoPhaseCommit_Specification.v1.md'
$testDesignPath = Join-Path $ProjectPath 'Research\Gate13R_PR2_Formal_Execution_Prelaunch_Test_Design.v1.md'

foreach ($required in @($ConfigPath,$SchedulePath,$ScheduleManifestPath,$ReadinessPath,$AdapterProvenancePath,$ExecutionReceiptPath,$UnityPath,$modulePath,$blockWrapper,$commandPath,$twoPhasePath,$specificationPath,$testDesignPath)) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) { throw "Required formal input is missing: $required" }
}
if (Test-Path -LiteralPath $formalRoot) { throw 'Formal root must be absent at the one-shot orchestrator entry.' }
if (Test-Path -LiteralPath $statusPath) { throw 'Formal execution status sidecar already exists; retry/resume is forbidden.' }
if (@(Get-Process -Name Unity -ErrorAction SilentlyContinue).Count -gt 0 -or (Test-Path -LiteralPath (Join-Path $ProjectPath 'Temp\UnityLockfile'))) { throw 'Unity is not quiescent at formal orchestrator entry.' }

$expectedNativeModulePath = @('C:\Users\bdscy\Documents\WindowsPowerShell\Modules','C:\Program Files\WindowsPowerShell\Modules','C:\WINDOWS\System32\WindowsPowerShell\v1.0\Modules') -join ';'
if ([string]$env:PSModulePath -ne $expectedNativeModulePath) { throw 'The formal orchestrator requires the verified native Windows PowerShell 5.1 PSModulePath.' }

$config = Read-G13RPR2Json $ConfigPath
if ([string]$config.configKind -ne 'gate13r-pr2-rq-aligned-s48-h48-formal-campaign-config-v2' -or $config.formalExecutionAuthorized -ne $false -or $config.formalRootCreated -ne $false) { throw 'Active v2 config authorization boundary mismatch.' }
if ([int]$config.totals.processCount -ne 3552 -or [int]$config.totals.sampleCount -ne 10176 -or [int]$config.totals.campaignCount -ne 74 -or [int]$config.totals.heterogeneousMatchedSuperblockCount -ne 1008) { throw 'Active v2 config cardinality mismatch.' }
if ([int]$config.processSemantics.maximumConcurrentUnityEditorProcesses -ne 1 -or $config.processSemantics.strictSerial -ne $true -or $config.processSemantics.crossBlockReuseAllowed -ne $false) { throw 'Strict-serial process contract mismatch.' }
if ([string]$config.memoryEligibility.policyId -ne 'gate13r-pr1b-v2-sample-alert-128mib-emergency-256mib-block-256mib-v1') { throw 'Frozen memory policy identity mismatch.' }

$expectedHashes = @{
    readinessSha256 = '669a5291ab2e219461ca9797696ba29bce32e198c11a983f0f1f31f3f7799fbc'
    configSha256 = '87d7012af4e8e5b5e16cb64b50f41f1dcb5b1eebf5d7eba1425b29e0fa13dd5e'
    scheduleSha256 = 'df8802c34ef033dd2eb906f6a70e8c8fc594bdc0a386a48afe6c756789075dae'
    scheduleManifestSha256 = 'b5763f1540c0193199201cd6bf025c43443d5bd2e67cb8808e0a2b86ef91b724'
    commandSha256 = Get-G13RPR2Sha256 $commandPath
    blockWrapperSha256 = Get-G13RPR2Sha256 $blockWrapper
    orchestratorSha256 = Get-G13RPR2Sha256 $PSCommandPath
    moduleSha256 = Get-G13RPR2Sha256 $modulePath
    adapterProvenanceSha256 = Get-G13RPR2Sha256 $AdapterProvenancePath
    twoPhaseAmendmentSha256 = Get-G13RPR2Sha256 $twoPhasePath
    prelaunchTestDesignSha256 = Get-G13RPR2Sha256 $testDesignPath
}
if ((Get-G13RPR2Sha256 $ConfigPath) -ne $expectedHashes.configSha256 -or (Get-G13RPR2Sha256 $SchedulePath) -ne $expectedHashes.scheduleSha256 -or (Get-G13RPR2Sha256 $ScheduleManifestPath) -ne $expectedHashes.scheduleManifestSha256 -or (Get-G13RPR2Sha256 $ReadinessPath) -ne $expectedHashes.readinessSha256) { throw 'Frozen active input SHA-256 mismatch.' }
$receipt = Read-G13RPR2Json $ExecutionReceiptPath
$receiptCheck = Test-G13RPR2FormalExecutionReceipt -Receipt $receipt -ExpectedFormalRoot $formalRoot -ExpectedHashes $expectedHashes
if ($receiptCheck.passed -ne $true) { throw ('Formal execution receipt rejected: ' + (@($receiptCheck.errors) -join ', ')) }

$drive = New-Object IO.DriveInfo([IO.Path]::GetPathRoot($formalRoot))
if ([long]$drive.AvailableFreeSpace -lt 57397541440L) { throw "Fresh H: storage gate failed: $($drive.AvailableFreeSpace)" }
if (Test-Path -LiteralPath $formalRoot) { throw 'Formal root appeared during final commit check.' }

New-Item -ItemType Directory -Path $formalRoot | Out-Null
$plansRoot = Join-Path $formalRoot '_plans'
New-Item -ItemType Directory -Path $plansRoot | Out-Null
$checkpointPath = Join-Path $formalRoot 'formal-checkpoint.json'
$completedProcesses = 0
$completedSamples = 0
$currentRecord = $null
$allUnityCompleted = $false
$receiptSha256 = Get-G13RPR2Sha256 $ExecutionReceiptPath
$formalConfigRelative = Get-G13RPR2ProjectRelativePath -ProjectPath $ProjectPath -Path $ConfigPath
$specificationRelative = Get-G13RPR2ProjectRelativePath -ProjectPath $ProjectPath -Path $specificationPath
$testDesignRelative = Get-G13RPR2ProjectRelativePath -ProjectPath $ProjectPath -Path $testDesignPath
$amendmentRelative = Get-G13RPR2ProjectRelativePath -ProjectPath $ProjectPath -Path $twoPhasePath
$commandRelative = Get-G13RPR2ProjectRelativePath -ProjectPath $ProjectPath -Path $commandPath
$provenanceRelative = Get-G13RPR2ProjectRelativePath -ProjectPath $ProjectPath -Path $AdapterProvenancePath
$receiptRelative = Get-G13RPR2ProjectRelativePath -ProjectPath $ProjectPath -Path $ExecutionReceiptPath

function Write-FormalStatus([string]$Status, [string]$ErrorMessage) {
    $value = [ordered]@{
        schemaVersion = 1
        statusKind = 'gate13r-pr2-formal-raw-acquisition-status-v1'
        savedAtUtc = [DateTime]::UtcNow.ToString('o')
        status = $Status
        formalRoot = $formalRoot
        executionReceiptSha256 = $receiptSha256
        completedProcessCount = $script:completedProcesses
        completedSampleCount = $script:completedSamples
        currentGlobalProcessOrdinal = if ($null -ne $script:currentRecord) { [int]$script:currentRecord.globalProcessOrdinal } else { 0 }
        currentCampaignId = if ($null -ne $script:currentRecord) { [string]$script:currentRecord.campaignId } else { $null }
        currentBlockId = if ($null -ne $script:currentRecord) { [string]$script:currentRecord.blockId } else { $null }
        currentMatchedSuperblock = if ($null -ne $script:currentRecord) { $script:currentRecord.matchedSuperblock } else { $null }
        currentRunIds = if ($null -ne $script:currentRecord) { @($script:currentRecord.entries | ForEach-Object { [string]$_.runId }) } else { @() }
        rawDataComplete = $Status -eq 'RAW-DATA-COMPLETE / ANALYSIS-PENDING / IMMUTABLE'
        analysisAuthorized = $false
        gate14RAuthorized = $false
        automaticRetryAttempted = $false
        automaticResumeAttempted = $false
        error = $ErrorMessage
    }
    Write-G13RPR2AtomicJson -Path $statusPath -Value $value -Depth 40 -AllowReplace
}

function Write-RootCheckpoint([string]$Status, [string]$ErrorMessage) {
    $value = [ordered]@{
        schemaVersion = 1
        checkpointKind = 'gate13r-pr2-formal-raw-acquisition-checkpoint-v1'
        savedAtUtc = [DateTime]::UtcNow.ToString('o')
        status = $Status
        executionReceiptSha256 = $receiptSha256
        completedProcessCount = $script:completedProcesses
        completedSampleCount = $script:completedSamples
        expectedProcessCount = 3552
        expectedSampleCount = 10176
        currentGlobalProcessOrdinal = if ($null -ne $script:currentRecord) { [int]$script:currentRecord.globalProcessOrdinal } else { 0 }
        currentCampaignId = if ($null -ne $script:currentRecord) { [string]$script:currentRecord.campaignId } else { $null }
        currentBlockId = if ($null -ne $script:currentRecord) { [string]$script:currentRecord.blockId } else { $null }
        currentMatchedSuperblock = if ($null -ne $script:currentRecord) { $script:currentRecord.matchedSuperblock } else { $null }
        automaticRetryAttempted = $false
        automaticResumeAttempted = $false
        topUpAttempted = $false
        partialMergeAttempted = $false
        error = $ErrorMessage
    }
    Write-G13RPR2AtomicJson -Path $checkpointPath -Value $value -Depth 40 -AllowReplace
}

function Get-PartialSnapshot {
    $files = @(Get-ChildItem -LiteralPath $formalRoot -File -Recurse -Force)
    $rawBytes = [long](($files | Measure-Object -Property Length -Sum).Sum)
    $last = $files | Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 1
    return [pscustomobject][ordered]@{
        fileCount = $files.Count
        rawBytes = $rawBytes
        lastWriteTimeUtc = if ($null -ne $last) { $last.LastWriteTimeUtc.ToString('o') } else { $null }
        lastWrittenRelativePath = if ($null -ne $last) { $last.FullName.Substring($formalRoot.Length + 1).Replace('\', '/') } else { $null }
    }
}

Write-RootCheckpoint -Status 'COMMITTED / BEFORE-FIRST-BLOCK' -ErrorMessage $null
Write-FormalStatus -Status 'COMMITTED / FORMAL-ATTEMPT-CONSUMED / BEFORE-FIRST-BLOCK' -ErrorMessage $null

try {
    $expectedOrdinal = 0
    foreach ($line in [IO.File]::ReadLines($SchedulePath, [Text.Encoding]::UTF8)) {
        $record = $line | ConvertFrom-Json
        $expectedOrdinal++
        if ([int]$record.globalProcessOrdinal -ne $expectedOrdinal) { throw "RAW-CONTRACT-VIOLATION: schedule ordinal mismatch at $expectedOrdinal" }
        $currentRecord = $record
        Write-RootCheckpoint -Status 'BEFORE-BLOCK' -ErrorMessage $null
        Write-FormalStatus -Status 'RUNNING-RAW-ACQUISITION' -ErrorMessage $null
        $plan = New-G13RPR2BlockPlanFromScheduleRecord -ScheduleRecord $record -FormalConfigRelativePath $formalConfigRelative -FormalConfigSha256 $expectedHashes.configSha256 -SpecificationRelativePath $specificationRelative -SpecificationSha256 (Get-G13RPR2Sha256 $specificationPath) -TestDesignRelativePath $testDesignRelative -TestDesignSha256 $expectedHashes.prelaunchTestDesignSha256 -AmendmentRelativePath $amendmentRelative -AmendmentSha256 $expectedHashes.twoPhaseAmendmentSha256 -CommandRelativePath $commandRelative -CommandSha256 $expectedHashes.commandSha256 -ProvenanceRelativePath $provenanceRelative -ProvenanceSha256 $expectedHashes.adapterProvenanceSha256 -ExecutionReceiptRelativePath $receiptRelative -ExecutionReceiptSha256 $receiptSha256
        $planPath = Join-Path $plansRoot ('p{0:D6}.json' -f $expectedOrdinal)
        Write-G13RPR2AtomicJson -Path $planPath -Value $plan -Depth 40
        $outputDirectory = [IO.Path]::GetFullPath((Join-Path $formalRoot ([string]$record.outputRelativePath).Replace('/', '\')))
        if (-not (Test-G13RPR2PathWithin -BasePath $formalRoot -CandidatePath $outputDirectory)) { throw "RAW-CONTRACT-VIOLATION: output path escapes formal root at ordinal $expectedOrdinal" }
        & $blockWrapper -ProjectPath $ProjectPath -BlockPlanPath $planPath -OutputDirectory $outputDirectory -AllowedRoot $formalRoot -ExecutionReceiptPath $ExecutionReceiptPath -UnityPath $UnityPath -TimeoutSeconds $BlockTimeoutSeconds
        if ($LASTEXITCODE -ne 0) { throw "RAW-CONTRACT-VIOLATION: formal block wrapper failed at ordinal $expectedOrdinal with exit $LASTEXITCODE" }
        $completedProcesses++
        $completedSamples += [int]$record.expectedSampleCount
        Write-RootCheckpoint -Status 'BLOCK-COMPLETED' -ErrorMessage $null
    }
    if ($completedProcesses -ne 3552 -or $completedSamples -ne 10176) { throw "RAW-CONTRACT-VIOLATION: terminal cardinality processes=$completedProcesses samples=$completedSamples" }
    $allUnityCompleted = $true
    Write-RootCheckpoint -Status 'UNITY-COLLECTION-COMPLETE / RAW-COMMIT-AUDIT-PENDING / NO-UNITY-RERUN' -ErrorMessage $null
    Write-FormalStatus -Status 'UNITY-COLLECTION-COMPLETE / RAW-COMMIT-AUDIT-PENDING / NO-UNITY-RERUN' -ErrorMessage $null

    $verifiedProcesses = 0
    $verifiedSamples = 0
    $seenRuns = New-Object 'Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
    foreach ($line in [IO.File]::ReadLines($SchedulePath, [Text.Encoding]::UTF8)) {
        $record = $line | ConvertFrom-Json
        $outputDirectory = [IO.Path]::GetFullPath((Join-Path $formalRoot ([string]$record.outputRelativePath).Replace('/', '\')))
        $manifestPath = Join-Path $outputDirectory 'block-manifest.json'
        $wrapperSummaryPath = $outputDirectory + '.summary.json'
        if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf) -or -not (Test-Path -LiteralPath $wrapperSummaryPath -PathType Leaf)) { throw "RAW-CONTRACT-VIOLATION: missing block evidence at ordinal $($record.globalProcessOrdinal)" }
        $manifest = Read-G13RPR2Json $manifestPath
        $wrapper = Read-G13RPR2Json $wrapperSummaryPath
        if ($manifest.completed -ne $true -or $manifest.formalCampaign -ne $true -or $manifest.hardMemoryRulesPassed -ne $true -or $wrapper.passed -ne $true -or [string]$manifest.blockId -ne [string]$record.blockId) { throw "RAW-CONTRACT-VIOLATION: invalid block evidence at ordinal $($record.globalProcessOrdinal)" }
        if ([int]$manifest.completedSampleCount -ne [int]$record.expectedSampleCount -or @($manifest.samples).Count -ne [int]$record.expectedSampleCount) { throw "RAW-CONTRACT-VIOLATION: sample cardinality mismatch at ordinal $($record.globalProcessOrdinal)" }
        foreach ($sample in @($manifest.samples)) {
            if (-not $seenRuns.Add([string]$sample.runId)) { throw "RAW-CONTRACT-VIOLATION: duplicate run ID $($sample.runId)" }
            foreach ($property in @('manifestRelativePath','summaryRelativePath','workloadResultRelativePath','memoryGateEvaluationRelativePath')) {
                $path = [IO.Path]::GetFullPath((Join-Path $outputDirectory ([string]$sample.$property).Replace('/', '\')))
                $hashProperty = $property.Replace('RelativePath', 'Sha256')
                if (-not (Test-Path -LiteralPath $path -PathType Leaf) -or (Get-G13RPR2Sha256 $path) -ne [string]$sample.$hashProperty) { throw "RAW-CONTRACT-VIOLATION: sample file/hash mismatch run=$($sample.runId) property=$property" }
            }
            $verifiedSamples++
        }
        $verifiedProcesses++
    }
    if ($verifiedProcesses -ne 3552 -or $verifiedSamples -ne 10176 -or $seenRuns.Count -ne 10176) { throw 'RAW-CONTRACT-VIOLATION: final verified cardinality mismatch' }

    $power = (& powercfg.exe /GETACTIVESCHEME 2>&1 | Out-String).Trim()
    $os = Get-CimInstance Win32_OperatingSystem
    $batteries = @(Get-CimInstance Win32_Battery -ErrorAction SilentlyContinue)
    $temperatures = @()
    try { $temperatures = @(Get-CimInstance -Namespace root/wmi -ClassName MSAcpi_ThermalZoneTemperature -ErrorAction Stop | ForEach-Object { ([double]$_.CurrentTemperature / 10.0) - 273.15 }) } catch { $temperatures = @() }
    $endSnapshot = [ordered]@{
        schemaVersion = 1
        snapshotKind = 'gate13r-pr2-formal-raw-acquisition-environment-end-snapshot-v1'
        capturedAtUtc = [DateTime]::UtcNow.ToString('o')
        powerScheme = $power
        freePhysicalMemoryBytes = [long]([double]$os.FreePhysicalMemory * 1KB)
        hFreeBytes = [long](New-Object IO.DriveInfo('H:\')).AvailableFreeSpace
        batteryCount = $batteries.Count
        batteries = @($batteries | ForEach-Object { [ordered]@{ status = [int]$_.BatteryStatus; estimatedChargeRemaining = [int]$_.EstimatedChargeRemaining } })
        temperatureCelsius = $temperatures
        unityProcessCount = @(Get-Process -Name Unity -ErrorAction SilentlyContinue).Count
        projectLockExists = Test-Path -LiteralPath (Join-Path $ProjectPath 'Temp\UnityLockfile')
    }
    $endSnapshotPath = Join-Path $formalRoot 'environment-end-snapshot.json'
    Write-G13RPR2AtomicJson -Path $endSnapshotPath -Value $endSnapshot -Depth 30
    if ([int]$endSnapshot.unityProcessCount -ne 0 -or $endSnapshot.projectLockExists -ne $false) { throw 'RAW-CONTRACT-VIOLATION: Unity/lock not quiescent at raw commit' }

    $rawExecution = [ordered]@{
        schemaVersion = 1
        manifestKind = 'gate13r-pr2-s48-h48-formal-raw-execution-manifest-v1'
        createdAtUtc = [DateTime]::UtcNow.ToString('o')
        terminalTokens = @('RAW-DATA-COMPLETE','ANALYSIS-PENDING','IMMUTABLE')
        executionReceiptSha256 = $receiptSha256
        configSha256 = $expectedHashes.configSha256
        scheduleSha256 = $expectedHashes.scheduleSha256
        scheduleManifestSha256 = $expectedHashes.scheduleManifestSha256
        processCount = $verifiedProcesses
        sampleCount = $verifiedSamples
        campaignCount = 74
        heterogeneousMatchedSuperblockCount = 1008
        sharedBlockCount = 1536
        heterogeneousBlockProcessCount = 2016
        abBaQuotaPerHeterogeneousScenario = '24/24'
        orderByWilliamsRowCountPerCell = 12
        allRunIdsUnique = $seenRuns.Count -eq 10176
        blockAndSampleCompletenessPassed = $true
        scheduleWilliamsAndAbBaPassed = $true
        rawAnalysisTwoPhaseCommitId = 'gate13r-pr2-raw-analysis-two-phase-commit-v1'
        formalAnalysisAuthorized = $false
        gate14RAuthorized = $false
    }
    $rawExecutionPath = Join-Path $formalRoot 'raw-execution-manifest.json'
    Write-G13RPR2AtomicJson -Path $rawExecutionPath -Value $rawExecution -Depth 30

    $snapshot = Get-G13RPR2RawPayloadSnapshot -FormalRoot $formalRoot
    $payloadManifestPath = Join-Path $formalRoot 'raw-payload-file-manifest.jsonl'
    Write-G13RPR2RawPayloadFileManifest -Path $payloadManifestPath -Snapshot $snapshot
    Set-G13RPR2RawPayloadReadOnly -FormalRoot $formalRoot -Snapshot $snapshot
    $postFreeze = Get-G13RPR2RawPayloadSnapshot -FormalRoot $formalRoot
    if ([string]$postFreeze.canonicalTreeSha256 -ne [string]$snapshot.canonicalTreeSha256 -or [long]$postFreeze.rawBytes -ne [long]$snapshot.rawBytes -or [int]$postFreeze.fileCount -ne [int]$snapshot.fileCount) { throw 'RAW-CONTRACT-VIOLATION: raw payload changed while applying immutable attributes' }
    $notReadOnly = 0
    foreach ($record in @($postFreeze.records)) {
        $path = Join-Path $formalRoot ([string]$record.relativePath).Replace('/', '\')
        if (-not (Get-Item -LiteralPath $path -Force).IsReadOnly) { $notReadOnly++ }
    }
    if ($notReadOnly -ne 0) { throw "RAW-CONTRACT-VIOLATION: $notReadOnly payload files are not read-only" }

    $freezeReceipt = [ordered]@{
        schemaVersion = 1
        receiptKind = 'gate13r-pr2-s48-h48-formal-raw-data-freeze-receipt-v1'
        committedAtUtc = [DateTime]::UtcNow.ToString('o')
        status = 'RAW-DATA-COMPLETE / ANALYSIS-PENDING / IMMUTABLE'
        formalRoot = $formalRoot
        executionReceiptSha256 = $receiptSha256
        rawExecutionManifestSha256 = Get-G13RPR2Sha256 $rawExecutionPath
        rawPayloadFileManifestSha256 = Get-G13RPR2Sha256 $payloadManifestPath
        environmentEndSnapshotSha256 = Get-G13RPR2Sha256 $endSnapshotPath
        rawPayloadFileCount = [int]$snapshot.fileCount
        rawPayloadOriginalBytes = [long]$snapshot.rawBytes
        rawPayloadCanonicalTreeSha256 = [string]$snapshot.canonicalTreeSha256
        allPayloadFilesReadOnly = $true
        analysisPending = $true
        analysisAuthorized = $false
        ordinaryAuditOrAnalysisFailureMayTriggerUnityRerun = $false
        automaticRetryResumeTopUpMergeAllowed = $false
        gate14RAuthorized = $false
    }
    $freezeReceiptPath = Join-Path $formalRoot 'raw-data-freeze-receipt.json'
    Write-G13RPR2AtomicJson -Path $freezeReceiptPath -Value $freezeReceipt -Depth 30
    foreach ($path in @($rawExecutionPath,$payloadManifestPath,$endSnapshotPath,$freezeReceiptPath)) { (Get-Item -LiteralPath $path -Force).IsReadOnly = $true }
    Write-RootCheckpoint -Status 'RAW-DATA-COMPLETE / ANALYSIS-PENDING / IMMUTABLE' -ErrorMessage $null
    Write-FormalStatus -Status 'RAW-DATA-COMPLETE / ANALYSIS-PENDING / IMMUTABLE' -ErrorMessage $null
}
catch {
    $message = $_.Exception.ToString()
    $partial = Get-PartialSnapshot
    $status = Get-G13RPR2FailureStatus -AllUnityCompleted $allUnityCompleted -ErrorMessage $message
    Write-RootCheckpoint -Status $status -ErrorMessage $message
    Write-FormalStatus -Status $status -ErrorMessage $message
    $failureManifest = [ordered]@{
        schemaVersion = 1
        manifestKind = 'gate13r-pr2-formal-partial-or-uncommitted-raw-output-manifest-v1'
        savedAtUtc = [DateTime]::UtcNow.ToString('o')
        status = $status
        allUnityProcessesCompleted = $allUnityCompleted
        completedProcessCount = $completedProcesses
        completedSampleCount = $completedSamples
        currentGlobalProcessOrdinal = if ($null -ne $currentRecord) { [int]$currentRecord.globalProcessOrdinal } else { 0 }
        currentCampaignId = if ($null -ne $currentRecord) { [string]$currentRecord.campaignId } else { $null }
        currentBlockId = if ($null -ne $currentRecord) { [string]$currentRecord.blockId } else { $null }
        currentMatchedSuperblock = if ($null -ne $currentRecord) { $currentRecord.matchedSuperblock } else { $null }
        currentRunIds = if ($null -ne $currentRecord) { @($currentRecord.entries | ForEach-Object { [string]$_.runId }) } else { @() }
        fileCount = [int]$partial.fileCount
        originalBytes = [long]$partial.rawBytes
        lastWriteTimeUtc = $partial.lastWriteTimeUtc
        lastWrittenRelativePath = $partial.lastWrittenRelativePath
        automaticRetryAllowed = $false
        automaticResumeAllowed = $false
        topUpAllowed = $false
        mergeAllowed = $false
        unityRerunAllowedForOrdinaryPostCollectionToolFailure = $false
        error = $message
    }
    $failurePath = Join-Path $formalRoot 'partial-output-manifest.json'
    if (Test-Path -LiteralPath $failurePath) { Write-G13RPR2AtomicJson -Path $failurePath -Value $failureManifest -Depth 40 -AllowReplace }
    else { Write-G13RPR2AtomicJson -Path $failurePath -Value $failureManifest -Depth 40 }
    Write-Error "Gate13R-PR2 stopped: $status"
    exit 1
}

Write-Host 'Gate13R-PR2 raw acquisition committed: RAW-DATA-COMPLETE / ANALYSIS-PENDING / IMMUTABLE.' -ForegroundColor Green
exit 0
