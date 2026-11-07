[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$ProjectPath,
    [Parameter(Mandatory = $true)][string]$AttemptRoot,
    [Parameter(Mandatory = $true)][string]$AttemptId,
    [Parameter(Mandatory = $true)][ValidateSet('FAILED','PASSED')][string]$Outcome,
    [Parameter(Mandatory = $true)][string]$LastCompletedGate,
    [string]$FailureCode = '',
    [string]$FailureDiagnosis = '',
    [string]$NextAction = '',
    [int]$UnityProcessesStarted = 0
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

function Get-Sha256([string]$Path) { return (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToLowerInvariant() }
function Write-AtomicJson([string]$Path, [object]$Value) {
    $full = [IO.Path]::GetFullPath($Path)
    $parent = Split-Path -Parent $full
    if (-not (Test-Path -LiteralPath $parent -PathType Container)) { throw "Atomic parent is missing: $parent" }
    $temporary = Join-Path $parent ('.g13tmp-' + [Guid]::NewGuid().ToString('N'))
    try {
        [IO.File]::WriteAllText($temporary, (($Value | ConvertTo-Json -Depth 100) + "`n"), (New-Object Text.UTF8Encoding($false)))
        if (Test-Path -LiteralPath $full) { throw "Create-new JSON target already exists: $full" }
        [IO.File]::Move($temporary, $full)
    } finally {
        if (Test-Path -LiteralPath $temporary -PathType Leaf) { Remove-Item -LiteralPath $temporary -Force }
    }
}

$ProjectPath = [IO.Path]::GetFullPath($ProjectPath)
$AttemptRoot = [IO.Path]::GetFullPath($AttemptRoot).TrimEnd('\', '/')
$verificationBase = [IO.Path]::GetFullPath((Join-Path $ProjectPath 'Research\Verification\Gate13R_PR2_MP2')).TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
if (-not ($AttemptRoot + [IO.Path]::DirectorySeparatorChar).StartsWith($verificationBase, [StringComparison]::OrdinalIgnoreCase)) { throw 'AttemptRoot is outside the MP2 verification base.' }
if (-not (Test-Path -LiteralPath $AttemptRoot -PathType Container)) { throw 'AttemptRoot is missing.' }
if ($Outcome -eq 'FAILED' -and [string]::IsNullOrWhiteSpace($FailureCode)) { throw 'FAILED outcome requires FailureCode.' }
if (@(Get-Process -Name Unity -ErrorAction SilentlyContinue).Count -gt 0) { throw 'Cannot freeze validation attempt while Unity is running.' }
if (Test-Path -LiteralPath (Join-Path $ProjectPath 'Temp\UnityLockfile')) { throw 'Cannot freeze validation attempt while UnityLockfile exists.' }
$formalRoot = Join-Path $ProjectPath 'Research\FormalRuns\Gate13R_RQAligned_S48H48\v3'
$formalReceipt = Join-Path $ProjectPath 'Research\Gate13R_PR2_Formal_Execution_Receipt.v3.json'
$formalStatus = Join-Path $ProjectPath 'Research\Gate13R_PR2_Formal_Execution_Status.v3.json'
if ((Test-Path -LiteralPath $formalRoot) -or (Test-Path -LiteralPath $formalReceipt) -or (Test-Path -LiteralPath $formalStatus)) { throw 'Formal attempt-3 artifacts must remain absent.' }

$reserved = @('partial-output-manifest.json','checkpoint.json','failure-receipt.json','pass-receipt.json')
foreach ($name in $reserved) { if (Test-Path -LiteralPath (Join-Path $AttemptRoot $name)) { throw "Create-new terminal artifact already exists: $name" } }
$files = New-Object Collections.Generic.List[object]
$totalBytes = [int64]0
foreach ($file in @(Get-ChildItem -LiteralPath $AttemptRoot -File -Recurse | Sort-Object FullName)) {
    $relative = $file.FullName.Substring($AttemptRoot.Length).TrimStart('\', '/').Replace('\', '/')
    if ($reserved -contains $relative) { continue }
    $totalBytes += [int64]$file.Length
    [void]$files.Add([ordered]@{relativePath=$relative;rawBytes=[int64]$file.Length;sha256=Get-Sha256 $file.FullName})
}
$manifest = [ordered]@{
    schemaVersion = 1
    manifestKind = 'gate13r-pr2-mp2-validation-attempt-partial-output-manifest-v1'
    attemptId = $AttemptId
    generatedAtUtc = [DateTime]::UtcNow.ToString('o')
    resolvedAttemptRoot = $AttemptRoot
    fileCount = $files.Count
    rawBytes = $totalBytes
    files = $files.ToArray()
    formalSamplesCreated = 0
    formalAttempt3RootCreated = $false
    formalAttempt3ExecutionReceiptCreated = $false
    unityProcessesStarted = $UnityProcessesStarted
}
$manifestPath = Join-Path $AttemptRoot 'partial-output-manifest.json'
Write-AtomicJson -Path $manifestPath -Value $manifest
$checkpoint = [ordered]@{
    schemaVersion = 1
    checkpointKind = 'gate13r-pr2-mp2-validation-attempt-terminal-checkpoint-v1'
    attemptId = $AttemptId
    savedAtUtc = [DateTime]::UtcNow.ToString('o')
    status = if ($Outcome -eq 'PASSED') { 'VALIDATION-PASSED-NON-EXECUTING' } else { 'FAILED-NO-FORMAL-EXECUTION' }
    lastCompletedGate = $LastCompletedGate
    failureCode = if ($Outcome -eq 'FAILED') { $FailureCode } else { $null }
    nextAction = $NextAction
    partialOutputManifestSha256 = Get-Sha256 $manifestPath
    formalAttempt3RootCreated = $false
    formalAttempt3ExecutionReceiptCreated = $false
    automaticFormalRetryAttempted = $false
}
$checkpointPath = Join-Path $AttemptRoot 'checkpoint.json'
Write-AtomicJson -Path $checkpointPath -Value $checkpoint
$receipt = [ordered]@{
    schemaVersion = 1
    receiptKind = if ($Outcome -eq 'PASSED') { 'gate13r-pr2-mp2-validation-pass-receipt-v1' } else { 'gate13r-pr2-mp2-validation-failure-receipt-v1' }
    attemptId = $AttemptId
    savedAtUtc = [DateTime]::UtcNow.ToString('o')
    status = if ($Outcome -eq 'PASSED') { 'PASSED-NON-EXECUTING' } else { 'FAILED-VERSIONED-VALIDATION-REPAIR-AUTHORIZED' }
    lastCompletedGate = $LastCompletedGate
    failureCode = if ($Outcome -eq 'FAILED') { $FailureCode } else { $null }
    failureDiagnosis = if ($Outcome -eq 'FAILED') { $FailureDiagnosis } else { $null }
    nextAction = $NextAction
    checkpointSha256 = Get-Sha256 $checkpointPath
    partialOutputManifestSha256 = Get-Sha256 $manifestPath
    formalAttempt3OutputRootCreated = $false
    formalAttempt3ExecutionReceiptCreated = $false
    formalAttempt3MeasuredCampaignExecuted = $false
    formalStatisticalAnalysisExecuted = $false
    gate14RExecuted = $false
    automaticFormalRetryAttempted = $false
    automaticFormalResumeAttempted = $false
}
$receiptPath = Join-Path $AttemptRoot $(if ($Outcome -eq 'PASSED') { 'pass-receipt.json' } else { 'failure-receipt.json' })
Write-AtomicJson -Path $receiptPath -Value $receipt
Write-Output ([ordered]@{attemptId=$AttemptId;outcome=$Outcome;manifestSha256=Get-Sha256 $manifestPath;checkpointSha256=Get-Sha256 $checkpointPath;receiptSha256=Get-Sha256 $receiptPath} | ConvertTo-Json -Compress)
