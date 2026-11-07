[CmdletBinding()]
param([Parameter(Mandatory = $true)][string]$ProjectPath)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$ProjectPath = [IO.Path]::GetFullPath($ProjectPath)
Import-Module (Join-Path $ProjectPath 'Research\Gate13RPR2MemoryPolicyPilotV1.psm1') -Force

$pilotRoot = [IO.Path]::GetFullPath((Join-Path $ProjectPath 'Research\PilotRuns\Gate13R_PR2_MemoryPolicy\v1'))
$rawRoot = Join-Path $pilotRoot 'raw'
$receiptPath = Join-Path $pilotRoot 'pilot-execution-receipt.json'
$checkpointPath = Join-Path $pilotRoot 'pilot-checkpoint.json'
$partialPath = Join-Path $pilotRoot 'pilot-partial-output-manifest.json'
$failurePath = Join-Path $pilotRoot 'pilot-failure-receipt.json'
$externalPath = Join-Path $ProjectPath 'Research\Gate13R_PR2_MP1_Pilot_v1_Failure_Preservation_Receipt.v1.json'

foreach ($path in @($pilotRoot,$rawRoot)) {
    if (-not (Test-Path -LiteralPath $path -PathType Container)) { throw "Expected failed pilot directory is missing: $path" }
}
foreach ($path in @($receiptPath,$checkpointPath)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Expected failed pilot evidence is missing: $path" }
}
foreach ($path in @($partialPath,$failurePath,$externalPath)) {
    if (Test-Path -LiteralPath $path) { throw "Create-new failure evidence already exists: $path" }
}
if (@(Get-CimInstance Win32_Process | Where-Object { $_.Name -in @('Unity.exe','UnityCrashHandler64.exe','UnityCrashHandler32.exe') }).Count -ne 0) {
    throw 'Unity process tree is not quiescent; refusal to preserve an ambiguous failure state.'
}
if (Test-Path -LiteralPath (Join-Path $ProjectPath 'Temp\UnityLockfile')) { throw 'UnityLockfile exists; refusal to preserve an ambiguous failure state.' }
if ((Test-Path -LiteralPath (Join-Path $ProjectPath 'Research\FormalRuns\Gate13R_RQAligned_S48H48\v3')) -or
    (Test-Path -LiteralPath (Join-Path $ProjectPath 'Research\Gate13R_PR2_Formal_Execution_Receipt.v3.json'))) {
    throw 'Formal attempt 3 must remain absent.'
}

$receipt = Read-G13RPR2MP1Json $receiptPath
$checkpoint = Read-G13RPR2MP1Json $checkpointPath
if ([string]$receipt.receiptKind -ne 'gate13r-pr2-mp1-targeted-memory-pilot-execution-receipt-v1' -or
    [string]$checkpoint.status -ne 'AUTHORIZED-NOT-STARTED' -or [int]$checkpoint.completedBlockCount -ne 0 -or
    [int]$checkpoint.currentGlobalProcessOrdinal -ne 0) {
    throw 'Failed-pilot pre-preservation identity is not the expected zero-block state.'
}

$rawFiles = @(Get-ChildItem -LiteralPath $rawRoot -Recurse -File -Force)
if ($rawFiles.Count -ne 0) { throw 'Raw files exist even though the orchestration failure should precede the first block.' }
$rawDirectories = @(Get-ChildItem -LiteralPath $rawRoot -Recurse -Directory -Force | Sort-Object FullName)
$failedAtUtc = [DateTime]::UtcNow.ToString('o')
$errorMessage = 'Exception setting "startedAtUtc": The property startedAtUtc cannot be found on this object. Verify that the property exists and can be set.'

$partial = [ordered]@{
    schemaVersion = 1
    manifestKind = 'gate13r-pr2-mp1-zero-sample-partial-output-manifest-v1'
    savedAtUtc = $failedAtUtc
    status = 'FAILED-NO-AUTO-RETRY-NO-RESUME-NO-TOP-UP-NO-MERGE'
    failureStage = 'ORCHESTRATION-CHECKPOINT-START-TRANSITION-BEFORE-FIRST-BLOCK'
    failedGlobalProcessOrdinal = 0
    failedBlockId = $null
    completedBlockCount = 0
    completedSampleCount = 0
    expectedBlockCount = 96
    expectedSampleCount = 384
    warmupProcessCount = 0
    rawFileCount = 0
    rawBytes = 0
    rawDirectories = @($rawDirectories | ForEach-Object { $_.FullName.Substring($rawRoot.Length + 1).Replace('\','/') })
    rawDataComplete = $false
    analysisAuthorized = $false
    files = @()
}
Write-G13RPR2MP1AtomicJson -Path $partialPath -Value $partial -Depth 40

$failure = [ordered]@{
    schemaVersion = 1
    receiptKind = 'gate13r-pr2-mp1-pilot-failure-receipt-v1'
    failedAtUtc = $failedAtUtc
    pilotRoot = $pilotRoot
    status = 'FAILED-NO-AUTO-RETRY-NO-RESUME-NO-TOP-UP-NO-MERGE'
    failureClass = 'ORCHESTRATION-CHECKPOINT-SCHEMA-DEFECT'
    failureStage = 'START-TRANSITION-BEFORE-FIRST-UNITY-BLOCK'
    errorMessage = $errorMessage
    sourceRelativePath = 'Research/Run-Gate13RPR2MemoryPolicyPilotV1.ps1'
    sourceSha256 = Get-G13RPR2MP1Sha256 (Join-Path $ProjectPath 'Research\Run-Gate13RPR2MemoryPolicyPilotV1.ps1')
    sourceLine = 64
    completedBlockCount = 0
    completedSampleCount = 0
    unityEditorProcessStarted = $false
    rawDataComplete = $false
    analysisPending = $false
    phaseACommitted = $false
    retryAuthorized = $false
    resumeAuthorized = $false
    topUpAuthorized = $false
    partialMergeAuthorized = $false
    formalAttempt3Authorized = $false
    formalStatisticalAnalysisAuthorized = $false
    gate14RAuthorized = $false
    pilotExecutionReceiptSha256 = Get-G13RPR2MP1Sha256 $receiptPath
    partialOutputManifestSha256 = Get-G13RPR2MP1Sha256 $partialPath
    labels = @('NON-FORMAL','MEMORY-DIAGNOSTIC-ONLY','EXCLUDED-FROM-FORMAL-ANALYSIS','NOT-ALGORITHM-SUPERIORITY-EVIDENCE')
}
Write-G13RPR2MP1AtomicJson -Path $failurePath -Value $failure -Depth 40

$failedCheckpoint = [ordered]@{
    schemaVersion = 1
    checkpointKind = 'gate13r-pr2-mp1-pilot-checkpoint-v1'
    savedAtUtc = [DateTime]::UtcNow.ToString('o')
    status = 'FAILED-NO-AUTO-RETRY-NO-RESUME-NO-TOP-UP-NO-MERGE'
    failureClass = 'ORCHESTRATION-CHECKPOINT-SCHEMA-DEFECT'
    failureStage = 'START-TRANSITION-BEFORE-FIRST-UNITY-BLOCK'
    completedBlockCount = 0
    completedSampleCount = 0
    expectedBlockCount = 96
    expectedSampleCount = 384
    currentGlobalProcessOrdinal = 0
    currentBlockId = $null
    rawDataComplete = $false
    phaseACommitted = $false
    failureReceiptSha256 = Get-G13RPR2MP1Sha256 $failurePath
    partialOutputManifestSha256 = Get-G13RPR2MP1Sha256 $partialPath
    automaticRetryAuthorized = $false
    automaticResumeAuthorized = $false
    topUpAuthorized = $false
    partialMergeAuthorized = $false
    formalCampaign = $false
    formalAnalysisAuthorized = $false
    gate14RAuthorized = $false
}
Write-G13RPR2MP1AtomicJson -Path $checkpointPath -Value $failedCheckpoint -Depth 40 -Replace

function Get-CanonicalPilotTree {
    param([string]$Root)
    $files = @(Get-ChildItem -LiteralPath $Root -Recurse -File -Force | Sort-Object @{Expression={$_.FullName.Substring($Root.Length + 1).Replace('\','/')}})
    $rows = @($files | ForEach-Object {
        $relative = $_.FullName.Substring($Root.Length + 1).Replace('\','/')
        $hash = Get-G13RPR2MP1Sha256 $_.FullName
        "$relative|$([long]$_.Length)|$hash"
    })
    $bytes = [Text.Encoding]::UTF8.GetBytes(($rows -join "`n"))
    $sha = [Security.Cryptography.SHA256]::Create()
    try { $tree = -join ($sha.ComputeHash($bytes) | ForEach-Object { $_.ToString('x2') }) } finally { $sha.Dispose() }
    return [pscustomobject][ordered]@{ files=$files; fileCount=$files.Count; rawBytes=[long](($files|Measure-Object Length -Sum).Sum); canonicalTreeSha256=$tree }
}

$beforeFreeze = Get-CanonicalPilotTree -Root $pilotRoot
foreach ($file in @($beforeFreeze.files)) { $file.IsReadOnly = $true }
$afterFreeze = Get-CanonicalPilotTree -Root $pilotRoot
$allReadOnly = @($afterFreeze.files | Where-Object { -not $_.IsReadOnly }).Count -eq 0
if ($afterFreeze.canonicalTreeSha256 -ne $beforeFreeze.canonicalTreeSha256 -or -not $allReadOnly) {
    throw 'Failed-pilot read-only freeze postcondition failed.'
}

$external = [ordered]@{
    schemaVersion = 1
    receiptKind = 'gate13r-pr2-mp1-pilot-v1-failure-preservation-receipt-v1'
    savedAtUtc = [DateTime]::UtcNow.ToString('o')
    pilotRoot = $pilotRoot
    status = 'FAILED-NO-AUTO-RETRY-NO-RESUME-NO-TOP-UP-NO-MERGE / ZERO-MEASURED-BLOCKS / IMMUTABLE'
    failureClass = 'ORCHESTRATION-CHECKPOINT-SCHEMA-DEFECT'
    completedBlockCount = 0
    completedSampleCount = 0
    unityProcessCountAfterFailure = 0
    unityLockfileExistsAfterFailure = $false
    fileCount = $afterFreeze.fileCount
    rawBytes = $afterFreeze.rawBytes
    canonicalTreeSha256BeforeReadOnlyFreeze = $beforeFreeze.canonicalTreeSha256
    canonicalTreeSha256AfterReadOnlyFreeze = $afterFreeze.canonicalTreeSha256
    allFilesReadOnly = $allReadOnly
    pilotExecutionReceiptSha256 = Get-G13RPR2MP1Sha256 $receiptPath
    pilotCheckpointSha256 = Get-G13RPR2MP1Sha256 $checkpointPath
    pilotFailureReceiptSha256 = Get-G13RPR2MP1Sha256 $failurePath
    partialOutputManifestSha256 = Get-G13RPR2MP1Sha256 $partialPath
    rawDataComplete = $false
    rawAnalysisAuthorized = $false
    formalAttempt3Authorized = $false
    gate14RAuthorized = $false
}
Write-G13RPR2MP1AtomicJson -Path $externalPath -Value $external -Depth 40
Write-Output "MP1-PILOT-V1-FAILURE-PRESERVED|0/96|$($afterFreeze.canonicalTreeSha256)"

