[CmdletBinding()]
param(
    [string]$ProjectPath = 'H:\DDM_Final_Project',
    [string]$FormalRoot = 'H:\DDM_Final_Project\Research\FormalRuns\Gate13R_RQAligned_S48H48\v1',
    [string]$EvidenceRoot = 'H:\DDM_Final_Project\Research\Verification\Gate13R_PR2_Formal_Execution\v1'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$ProjectPath = [IO.Path]::GetFullPath($ProjectPath)
$FormalRoot = [IO.Path]::GetFullPath($FormalRoot).TrimEnd('\', '/')
$EvidenceRoot = [IO.Path]::GetFullPath($EvidenceRoot).TrimEnd('\', '/')
Import-Module (Join-Path $ProjectPath 'Research\Gate13RPR2FormalExecutionV3.psm1') -Force

$statusPath = Join-Path $ProjectPath 'Research\Gate13R_PR2_Formal_Execution_Status.v1.json'
$checkpointPath = Join-Path $FormalRoot 'formal-checkpoint.json'
$partialManifestPath = Join-Path $FormalRoot 'partial-output-manifest.json'
$blockRoot = Join-Path $FormalRoot 'campaigns\c01-core-r01-s1-shared--shared\blocks\b0001'
$blockManifestPath = Join-Path $blockRoot 'block-manifest.json'
$blockCheckpointPath = Join-Path $blockRoot 'block-checkpoint.json'
$unityLogPath = "$blockRoot.Unity.log"
$stdoutPath = Join-Path $EvidenceRoot 'orchestrator.stdout.log'
$stderrPath = Join-Path $EvidenceRoot 'orchestrator.stderr.log'
$receiptPath = Join-Path $ProjectPath 'Research\Gate13R_PR2_Formal_Execution_Receipt.v1.json'
$wrapperPath = Join-Path $ProjectPath 'Research\Run-Gate13RPR2FormalBlockV4.ps1'
$campaignPath = Join-Path $ProjectPath 'Research\Run-Gate13RPR2FormalCampaignV4.ps1'
$scriptPath = $PSCommandPath

$launchReceiptPath = Join-Path $EvidenceRoot 'formal-attempt-1-launch-receipt.json'
$diagnosisPath = Join-Path $EvidenceRoot 'formal-attempt-1-failure-diagnosis.json'
$treeManifestPath = Join-Path $EvidenceRoot 'formal-attempt-1-partial-tree-manifest.json'
$freezeReceiptPath = Join-Path $EvidenceRoot 'formal-attempt-1-evidence-freeze-receipt.json'
$evidenceManifestPath = Join-Path $EvidenceRoot 'formal-attempt-1-evidence-manifest.json'

foreach ($required in @($statusPath, $checkpointPath, $partialManifestPath, $blockManifestPath, $blockCheckpointPath, $unityLogPath, $stdoutPath, $stderrPath, $receiptPath, $wrapperPath, $campaignPath, $scriptPath)) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) { throw "Required failure evidence is missing: $required" }
}
foreach ($output in @($launchReceiptPath, $diagnosisPath, $treeManifestPath, $freezeReceiptPath, $evidenceManifestPath)) {
    if (Test-Path -LiteralPath $output) { throw "Failure evidence output already exists: $output" }
}
if (@(Get-Process -Name Unity -ErrorAction SilentlyContinue).Count -ne 0) { throw 'Unity must be quiescent before freezing failure evidence.' }
if (Test-Path -LiteralPath (Join-Path $ProjectPath 'Temp\UnityLockfile')) { throw 'Unity lock is present.' }

$status = Read-G13RPR2Json $statusPath
$checkpoint = Read-G13RPR2Json $checkpointPath
$partial = Read-G13RPR2Json $partialManifestPath
$blockManifest = Read-G13RPR2Json $blockManifestPath
$blockCheckpoint = Read-G13RPR2Json $blockCheckpointPath
$terminal = 'FAILED-NO-AUTO-RETRY-NO-RESUME-NO-TOP-UP-NO-MERGE'
if ([string]$status.status -ne $terminal -or [string]$checkpoint.status -ne $terminal -or [string]$partial.status -ne $terminal) { throw 'Formal failure terminal state mismatch.' }
if ([int]$status.completedProcessCount -ne 0 -or [int]$status.completedSampleCount -ne 0 -or [int]$status.currentGlobalProcessOrdinal -ne 1) { throw 'Unexpected formal completion counters.' }

function Get-FormalAttemptTreeSnapshot {
    $records = New-Object Collections.Generic.List[object]
    $builder = New-Object Text.StringBuilder
    $bytes = 0L
    $files = @(Get-ChildItem -LiteralPath $FormalRoot -File -Recurse -Force)
    $files = @($files | Sort-Object { $_.FullName.Substring($FormalRoot.Length + 1).Replace('\', '/') })
    foreach ($file in $files) {
        $relative = $file.FullName.Substring($FormalRoot.Length + 1).Replace('\', '/')
        $sha = Get-G13RPR2Sha256 $file.FullName
        $bytes += [long]$file.Length
        [void]$builder.Append($relative).Append("`t").Append([string]$file.Length).Append("`t").Append($sha).Append("`n")
        $records.Add([ordered]@{
            relativePath = $relative
            rawBytes = [long]$file.Length
            sha256 = $sha
            lastWriteTimeUtc = $file.LastWriteTimeUtc.ToString('o')
            readOnly = [bool]$file.IsReadOnly
        })
    }
    return [pscustomobject][ordered]@{
        records = $records.ToArray()
        fileCount = $records.Count
        rawBytes = $bytes
        canonicalTreeSha256 = Get-G13RPR2StringSha256 $builder.ToString()
    }
}

$preFreeze = Get-FormalAttemptTreeSnapshot
foreach ($record in @($preFreeze.records)) {
    $path = [IO.Path]::GetFullPath((Join-Path $FormalRoot ([string]$record.relativePath).Replace('/', '\')))
    if (-not (Test-G13RPR2PathWithin -BasePath $FormalRoot -CandidatePath $path)) { throw "Path escapes formal root: $path" }
    (Get-Item -LiteralPath $path -Force).IsReadOnly = $true
}
$postFreeze = Get-FormalAttemptTreeSnapshot
if ([string]$preFreeze.canonicalTreeSha256 -ne [string]$postFreeze.canonicalTreeSha256 -or [long]$preFreeze.rawBytes -ne [long]$postFreeze.rawBytes -or [int]$preFreeze.fileCount -ne [int]$postFreeze.fileCount) { throw 'Read-only freeze changed formal evidence bytes.' }
if (@($postFreeze.records | Where-Object { $_.readOnly -ne $true }).Count -ne 0) { throw 'Not all formal evidence files are read-only.' }

$embeddedSamples = @($blockManifest.samples)
$sampleSummaryFiles = @(Get-ChildItem -LiteralPath (Join-Path $blockRoot 'runs') -Filter 'sample-summary.json' -File -Recurse)
$childManifestFiles = @(Get-ChildItem -LiteralPath (Join-Path $blockRoot 'runs') -Filter 'manifest.json' -File -Recurse)
$memoryEvaluationFiles = @(Get-ChildItem -LiteralPath (Join-Path $blockRoot 'runs') -Filter 'memory-gate-evaluation.json' -File -Recurse)
$embeddedWithFormalProperty = @($embeddedSamples | Where-Object { $_.PSObject.Properties.Name -contains 'formalCampaign' }).Count
$summaryFormalTrue = @($sampleSummaryFiles | Where-Object { (Read-G13RPR2Json $_.FullName).formalCampaign -eq $true }).Count
$childFormalTrue = @($childManifestFiles | Where-Object { (Read-G13RPR2Json $_.FullName).formalCampaign -eq $true }).Count
$memoryFormalTrue = @($memoryEvaluationFiles | Where-Object { (Read-G13RPR2Json $_.FullName).formalCampaign -eq $true }).Count
$capturedAt = [DateTime]::UtcNow.ToString('o')

$launchReceipt = [ordered]@{
    schemaVersion = 1
    receiptKind = 'gate13r-pr2-formal-attempt-1-independent-launch-receipt-v1'
    capturedAtUtc = $capturedAt
    formalAttemptOrdinal = 1
    orchestratorProcessId = 16352
    orchestratorStartTimeUtc = '2026-10-08T17:44:28.0230380Z'
    orchestratorExited = $true
    processExitCodeObserved = $null
    nativeWindowsPowerShellPath = 'C:\WINDOWS\System32\WindowsPowerShell\v1.0\powershell.exe'
    nativeWindowsPowerShellVersion = '5.1.26100.9444'
    launchWindowStyle = 'Hidden'
    independentProcess = $true
    psModulePath = 'C:\Users\bdscy\Documents\WindowsPowerShell\Modules;C:\Program Files\WindowsPowerShell\Modules;C:\WINDOWS\System32\WindowsPowerShell\v1.0\Modules'
    formalRoot = $FormalRoot
    executionReceiptSha256 = Get-G13RPR2Sha256 $receiptPath
    orchestratorSha256 = Get-G13RPR2Sha256 $campaignPath
    blockWrapperSha256 = Get-G13RPR2Sha256 $wrapperPath
    stdoutRelativePath = Get-G13RPR2ProjectRelativePath -ProjectPath $ProjectPath -Path $stdoutPath
    stdoutSha256 = Get-G13RPR2Sha256 $stdoutPath
    stderrRelativePath = Get-G13RPR2ProjectRelativePath -ProjectPath $ProjectPath -Path $stderrPath
    stderrSha256 = Get-G13RPR2Sha256 $stderrPath
    terminalStatus = $terminal
    noAutomaticRetry = $true
    noAutomaticResume = $true
    noTopUp = $true
    noPartialMerge = $true
}
Write-G13RPR2AtomicJson -Path $launchReceiptPath -Value $launchReceipt -Depth 30

$treeManifest = [ordered]@{
    schemaVersion = 1
    manifestKind = 'gate13r-pr2-formal-attempt-1-failed-partial-tree-manifest-v1'
    capturedAtUtc = $capturedAt
    formalRoot = $FormalRoot
    terminalStatus = $terminal
    completedFormalProcessCount = 0
    completedFormalSampleCount = 0
    currentGlobalProcessOrdinal = 1
    partialArtifactsExcludedFromFormalAnalysis = $true
    partialArtifactsMergeAllowed = $false
    fileCount = [int]$postFreeze.fileCount
    rawBytes = [long]$postFreeze.rawBytes
    canonicalTreeSha256 = [string]$postFreeze.canonicalTreeSha256
    files = @($postFreeze.records)
}
Write-G13RPR2AtomicJson -Path $treeManifestPath -Value $treeManifest -Depth 40

$diagnosis = [ordered]@{
    schemaVersion = 1
    diagnosisKind = 'gate13r-pr2-formal-attempt-1-failure-diagnosis-v1'
    capturedAtUtc = $capturedAt
    classification = 'POST-UNITY-BLOCK-WRAPPER-VALIDATION-IMPLEMENTATION-DEFECT'
    terminalStatus = $terminal
    formalAttemptConsumed = $true
    formalRoot = $FormalRoot
    failureAtGlobalProcessOrdinal = 1
    campaignId = [string]$status.currentCampaignId
    blockId = [string]$status.currentBlockId
    firstUnityProcessId = [int]$blockManifest.processId
    firstUnityProcessStartTimeUtc = [string]$blockManifest.processStartTimeUtc
    unityExitedSuccessfully = $true
    unityLogSha256 = Get-G13RPR2Sha256 $unityLogPath
    blockManifestCompleted = [bool]$blockManifest.completed
    blockCheckpointStatus = [string]$blockCheckpoint.status
    generatedAlgorithmArtifactCount = [int]$blockManifest.completedSampleCount
    formalCommittedProcessCount = [int]$status.completedProcessCount
    formalCommittedSampleCount = [int]$status.completedSampleCount
    defect = [ordered]@{
        wrapperRelativePath = Get-G13RPR2ProjectRelativePath -ProjectPath $ProjectPath -Path $wrapperPath
        wrapperSha256 = Get-G13RPR2Sha256 $wrapperPath
        failingLine = 115
        exceptionType = 'System.Management.Automation.PropertyNotFoundException'
        missingProperty = 'formalCampaign'
        embeddedBlockManifestSampleCount = $embeddedSamples.Count
        embeddedSamplesWithFormalCampaignProperty = $embeddedWithFormalProperty
        sampleSummaryFileCount = $sampleSummaryFiles.Count
        sampleSummariesWithFormalCampaignTrue = $summaryFormalTrue
        childManifestFileCount = $childManifestFiles.Count
        childManifestsWithFormalCampaignTrue = $childFormalTrue
        memoryEvaluationFileCount = $memoryEvaluationFiles.Count
        memoryEvaluationsWithFormalCampaignTrue = $memoryFormalTrue
        explanation = 'The completed block manifest top level and every child evidence file carry formalCampaign=true, but each embedded block-manifest samples[] record omits the property. StrictMode property access in the frozen wrapper throws before the wrapper summary and formal block commit are written.'
    }
    disposition = @(
        'PARTIAL-ATTEMPT-EVIDENCE',
        'EXCLUDED-FROM-FORMAL-ANALYSIS',
        'NO-AUTO-RETRY',
        'NO-RESUME',
        'NO-TOP-UP',
        'NO-MERGE',
        'NEW-USER-AUTHORIZATION-REQUIRED-FOR-ANY-NEW-FORMAL-ATTEMPT'
    )
    rawDataComplete = $false
    phaseOneRawCommitReached = $false
    formalAnalysisAuthorized = $false
    gate14RAuthorized = $false
}
Write-G13RPR2AtomicJson -Path $diagnosisPath -Value $diagnosis -Depth 40

$freezeReceipt = [ordered]@{
    schemaVersion = 1
    receiptKind = 'gate13r-pr2-formal-attempt-1-failed-evidence-read-only-freeze-receipt-v1'
    capturedAtUtc = [DateTime]::UtcNow.ToString('o')
    formalRoot = $FormalRoot
    terminalStatus = $terminal
    preFreezeCanonicalTreeSha256 = [string]$preFreeze.canonicalTreeSha256
    postFreezeCanonicalTreeSha256 = [string]$postFreeze.canonicalTreeSha256
    byteIdentityPreserved = [string]$preFreeze.canonicalTreeSha256 -eq [string]$postFreeze.canonicalTreeSha256
    fileCount = [int]$postFreeze.fileCount
    rawBytes = [long]$postFreeze.rawBytes
    allEvidenceFilesReadOnly = $true
    unityProcessCountAfterFailure = 0
    unityLockPresentAfterFailure = $false
    retryAuthorized = $false
    resumeAuthorized = $false
    topUpAuthorized = $false
    mergeAuthorized = $false
}
Write-G13RPR2AtomicJson -Path $freezeReceiptPath -Value $freezeReceipt -Depth 30

$evidenceFiles = @($launchReceiptPath, $diagnosisPath, $treeManifestPath, $freezeReceiptPath, $statusPath, $checkpointPath, $partialManifestPath, $stdoutPath, $stderrPath)
$evidenceRecords = New-Object Collections.Generic.List[object]
foreach ($path in $evidenceFiles) {
    $item = Get-Item -LiteralPath $path -Force
    $evidenceRecords.Add([ordered]@{
        relativePath = Get-G13RPR2ProjectRelativePath -ProjectPath $ProjectPath -Path $path
        rawBytes = [long]$item.Length
        sha256 = Get-G13RPR2Sha256 $path
    })
}
$evidenceManifest = [ordered]@{
    schemaVersion = 1
    manifestKind = 'gate13r-pr2-formal-attempt-1-failure-evidence-manifest-v1'
    capturedAtUtc = [DateTime]::UtcNow.ToString('o')
    terminalStatus = $terminal
    formalRootCanonicalTreeSha256 = [string]$postFreeze.canonicalTreeSha256
    formalRootFileCount = [int]$postFreeze.fileCount
    formalRootRawBytes = [long]$postFreeze.rawBytes
    records = $evidenceRecords.ToArray()
}
Write-G13RPR2AtomicJson -Path $evidenceManifestPath -Value $evidenceManifest -Depth 30

foreach ($path in @($launchReceiptPath, $diagnosisPath, $treeManifestPath, $freezeReceiptPath, $evidenceManifestPath)) {
    (Get-Item -LiteralPath $path -Force).IsReadOnly = $true
}

[pscustomobject][ordered]@{
    passed = $true
    terminalStatus = $terminal
    formalRootCanonicalTreeSha256 = [string]$postFreeze.canonicalTreeSha256
    formalRootFileCount = [int]$postFreeze.fileCount
    formalRootRawBytes = [long]$postFreeze.rawBytes
    formalCommittedProcessCount = 0
    formalCommittedSampleCount = 0
    generatedButExcludedSampleArtifactCount = [int]$blockManifest.completedSampleCount
    failureDiagnosisSha256 = Get-G13RPR2Sha256 $diagnosisPath
    failureEvidenceManifestSha256 = Get-G13RPR2Sha256 $evidenceManifestPath
    allFormalEvidenceFilesReadOnly = $true
    retryAuthorized = $false
    formalAnalysisAuthorized = $false
    gate14RAuthorized = $false
} | ConvertTo-Json -Depth 20
