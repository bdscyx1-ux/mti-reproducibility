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
$checkpointBackupPath = Join-Path $pilotRoot 'pilot-checkpoint.authorized-not-started.backup.json'
$checkpointReplacementPath = Join-Path $pilotRoot 'pilot-checkpoint.failed.replacement.json'
$partialPath = Join-Path $pilotRoot 'pilot-partial-output-manifest.json'
$failurePath = Join-Path $pilotRoot 'pilot-failure-receipt.json'
$attempt1Path = Join-Path $ProjectPath 'Research\Gate13R_PR2_MP1_Pilot_v1_Failure_Preservation_Attempt1_Failure_Receipt.v1.json'
$externalPath = Join-Path $ProjectPath 'Research\Gate13R_PR2_MP1_Pilot_v1_Failure_Preservation_Receipt.v1.json'

foreach ($path in @($receiptPath,$checkpointPath,$partialPath,$failurePath,$attempt1Path)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Required failure evidence is missing: $path" }
}
foreach ($path in @($checkpointBackupPath,$checkpointReplacementPath,$externalPath)) {
    if (Test-Path -LiteralPath $path) { throw "Create-new recovery target exists: $path" }
}

$expectedHashes = [ordered]@{
    $receiptPath = 'a7b8b63842704302be546aaa51d992264c854fc5961605a3bed209a7be160ae3'
    $checkpointPath = '88582a1d4942f02cdc25bcdb32da648bd171e9a2fbfa49dcd0d3587c99637a57'
    $partialPath = '30a7cc396d02aeab273a73e6356401455da38352af290c83decf29afc18250e2'
    $failurePath = '7eaee708fc0dd23e6f391ea2e4e3450d0313b2f0f91a59d2eb71e5b30cc3d214'
}
foreach ($entry in $expectedHashes.GetEnumerator()) {
    $actual = Get-G13RPR2MP1Sha256 $entry.Key
    if ($actual -ne $entry.Value) { throw "Failure evidence changed before recovery: $($entry.Key)" }
}
if (@(Get-ChildItem -LiteralPath $rawRoot -Recurse -File -Force).Count -ne 0) { throw 'Raw root is not the expected zero-file state.' }
if (@(Get-CimInstance Win32_Process | Where-Object { $_.Name -in @('Unity.exe','UnityCrashHandler64.exe','UnityCrashHandler32.exe') }).Count -ne 0) { throw 'Unity process tree is not quiescent.' }
if (Test-Path -LiteralPath (Join-Path $ProjectPath 'Temp\UnityLockfile')) { throw 'UnityLockfile exists.' }
if ((Test-Path -LiteralPath (Join-Path $ProjectPath 'Research\FormalRuns\Gate13R_RQAligned_S48H48\v3')) -or
    (Test-Path -LiteralPath (Join-Path $ProjectPath 'Research\Gate13R_PR2_Formal_Execution_Receipt.v3.json'))) { throw 'Formal attempt 3 must remain absent.' }

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
    unityEditorProcessStarted = $false
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
Write-G13RPR2MP1AtomicJson -Path $checkpointReplacementPath -Value $failedCheckpoint -Depth 40
[IO.File]::Replace($checkpointReplacementPath, $checkpointPath, $checkpointBackupPath)
if (Test-Path -LiteralPath $checkpointReplacementPath) { throw 'Checkpoint replacement temporary still exists.' }
if ((Get-G13RPR2MP1Sha256 $checkpointBackupPath) -ne '88582a1d4942f02cdc25bcdb32da648bd171e9a2fbfa49dcd0d3587c99637a57') {
    throw 'Atomic replacement did not preserve the original checkpoint backup.'
}
$updatedCheckpoint = Read-G13RPR2MP1Json $checkpointPath
if ([string]$updatedCheckpoint.status -ne 'FAILED-NO-AUTO-RETRY-NO-RESUME-NO-TOP-UP-NO-MERGE' -or [int]$updatedCheckpoint.completedBlockCount -ne 0) {
    throw 'Updated failure checkpoint postcondition failed.'
}

function Get-CanonicalPilotTree {
    param([string]$Root)
    $files = @(Get-ChildItem -LiteralPath $Root -Recurse -File -Force | Sort-Object @{Expression={$_.FullName.Substring($Root.Length + 1).Replace('\','/')}})
    $rows = @($files | ForEach-Object {
        $relative = $_.FullName.Substring($Root.Length + 1).Replace('\','/')
        "$relative|$([long]$_.Length)|$(Get-G13RPR2MP1Sha256 $_.FullName)"
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
if ($afterFreeze.canonicalTreeSha256 -ne $beforeFreeze.canonicalTreeSha256 -or -not $allReadOnly) { throw 'Read-only freeze postcondition failed.' }

$external = [ordered]@{
    schemaVersion = 1
    receiptKind = 'gate13r-pr2-mp1-pilot-v1-failure-preservation-receipt-v1'
    savedAtUtc = [DateTime]::UtcNow.ToString('o')
    pilotRoot = $pilotRoot
    status = 'FAILED-NO-AUTO-RETRY-NO-RESUME-NO-TOP-UP-NO-MERGE / ZERO-MEASURED-BLOCKS / IMMUTABLE'
    failureClass = 'ORCHESTRATION-CHECKPOINT-SCHEMA-DEFECT'
    failureStage = 'START-TRANSITION-BEFORE-FIRST-UNITY-BLOCK'
    preservationRecovery = [ordered]@{
        priorAttemptFailed = $true
        priorAttemptReceiptRelativePath = 'Research/Gate13R_PR2_MP1_Pilot_v1_Failure_Preservation_Attempt1_Failure_Receipt.v1.json'
        priorAttemptReceiptSha256 = Get-G13RPR2MP1Sha256 $attempt1Path
        recoveryMethod = 'ATOMIC-FILE-REPLACE-WITH-NONEMPTY-BACKUP-PATH'
        pilotExecutionRetried = $false
    }
    completedBlockCount = 0
    completedSampleCount = 0
    rawFileCount = 0
    unityEditorProcessStarted = $false
    unityProcessCountAfterFailure = 0
    unityLockfileExistsAfterFailure = $false
    fileCount = $afterFreeze.fileCount
    rawBytes = $afterFreeze.rawBytes
    canonicalTreeSha256BeforeReadOnlyFreeze = $beforeFreeze.canonicalTreeSha256
    canonicalTreeSha256AfterReadOnlyFreeze = $afterFreeze.canonicalTreeSha256
    allFilesReadOnly = $allReadOnly
    pilotExecutionReceiptSha256 = Get-G13RPR2MP1Sha256 $receiptPath
    originalCheckpointBackupSha256 = Get-G13RPR2MP1Sha256 $checkpointBackupPath
    failedCheckpointSha256 = Get-G13RPR2MP1Sha256 $checkpointPath
    pilotFailureReceiptSha256 = Get-G13RPR2MP1Sha256 $failurePath
    partialOutputManifestSha256 = Get-G13RPR2MP1Sha256 $partialPath
    rawDataComplete = $false
    rawAnalysisAuthorized = $false
    measuredPilotRetryAuthorized = $false
    measuredPilotResumeAuthorized = $false
    topUpAuthorized = $false
    partialMergeAuthorized = $false
    formalAttempt3Authorized = $false
    formalStatisticalAnalysisAuthorized = $false
    gate14RAuthorized = $false
}
Write-G13RPR2MP1AtomicJson -Path $externalPath -Value $external -Depth 50
Write-Output "MP1-PILOT-V1-FAILURE-PRESERVED|0/96|$($afterFreeze.canonicalTreeSha256)"

