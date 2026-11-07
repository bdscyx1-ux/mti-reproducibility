[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$ProjectPath,
    [Parameter(Mandatory = $true)][string]$OutputPath,
    [switch]$BindingSmokeOnly
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if ([string]::IsNullOrWhiteSpace($ProjectPath) -or -not [IO.Path]::IsPathRooted($ProjectPath)) { throw 'An explicit absolute ProjectPath is required.' }
$ProjectPath = [IO.Path]::GetFullPath($ProjectPath)
if ($BindingSmokeOnly) { Write-Output "BINDING-SMOKE-PASSED|Test-Gate13RPR2Attempt2ExecutionReceiptV1|$ProjectPath"; exit 0 }
$OutputPath = [IO.Path]::GetFullPath($OutputPath)
if (Test-Path -LiteralPath $OutputPath) { throw 'Create-new receipt-validation output exists.' }
Import-Module (Join-Path $ProjectPath 'Research\Gate13RPR2FormalExecutionV5.psm1') -Force
$receiptPath = Join-Path $ProjectPath 'Research\Gate13R_PR2_Formal_Execution_Receipt.v2.json'
$formalRoot = [IO.Path]::GetFullPath((Join-Path $ProjectPath 'Research\FormalRuns\Gate13R_RQAligned_S48H48\v2')).TrimEnd('\', '/')
$statusPath = Join-Path $ProjectPath 'Research\Gate13R_PR2_Formal_Execution_Status.v2.json'
$paths = [ordered]@{
    readinessSha256 = 'Research\Gate13R_PR2_NonExecuting_Readiness_Checkpoint.v1.json'
    configSha256 = 'Research\Gate13R_PR2_Formal_Campaign_Config.v2.json'
    scheduleSha256 = 'Research\Gate13R_PR2_Formal_Williams_Matched_Schedule.v2.jsonl'
    scheduleManifestSha256 = 'Research\Gate13R_PR2_Formal_Williams_Matched_Schedule_Manifest.v2.json'
    commandSha256 = 'Assets\_Scripts\Research\Editor\Gate13RPR2FormalBatchCommandV4.cs'
    blockWrapperSha256 = 'Research\Run-Gate13RPR2FormalBlockV6.ps1'
    orchestratorSha256 = 'Research\Run-Gate13RPR2FormalCampaignV6.ps1'
    moduleSha256 = 'Research\Gate13RPR2FormalExecutionV5.psm1'
    adapterProvenanceSha256 = 'Research\Gate13R_PR2_Attempt2_Formal_Execution_Adapter_Provenance.v2.json'
    twoPhaseAmendmentSha256 = 'Research\Gate13R_PR2_RawAnalysis_TwoPhaseCommit_Amendment.v1.json'
    twoPhaseSpecificationSha256 = 'Research\Gate13R_PR2_RawAnalysis_TwoPhaseCommit_Specification.v1.md'
    priorFormalAuthorizationSha256 = 'Research\Gate13R_PR2_Formal_Execution_Authorization.v2.json'
    attempt2AuthorizationSha256 = 'Research\Gate13R_PR2_Attempt2_Execution_Authorization.v1.json'
    attempt2AuthorizationPromptSha256 = 'Research\Gate13R_PR2_Attempt2_Next_Authorization_Prompt.md'
    attempt2UserAuthorizationSha256 = 'Research\Gate13R_PR2_Attempt2_User_Authorization.v1.txt'
    attempt2PreWriteAuditSha256 = 'Research\Gate13R_PR2_Attempt2_PreWrite_Preservation_Audit.v1.json'
    repairSpecificationSha256 = 'Research\Gate13R_PR2_Attempt2_Embedded_Contract_Repair_Specification.v2.md'
    schemaAmendmentSha256 = 'Research\Gate13R_PR2_Attempt2_Block_Sample_Schema_Amendment.v2.json'
    mechanicalDerivationReceiptSha256 = 'Research\Gate13R_PR2_Attempt2_Mechanical_Derivation_Receipt.v2.json'
    supplementalAuthorizationSha256 = 'Research\Gate13R_PR2_TwoPhaseCommit_Supplemental_Authorization.v1.txt'
    prelaunchTestDesignSha256 = 'Research\Gate13R_PR2_Attempt2_Prelaunch_Test_Design.v1.md'
}
$expectedHashes = @{}
foreach ($entry in $paths.GetEnumerator()) {
    $path = Join-Path $ProjectPath ([string]$entry.Value)
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Receipt-bound file missing: $path" }
    $expectedHashes[[string]$entry.Key] = Get-G13RPR2Sha256 $path
}
$receipt = Read-G13RPR2Json $receiptPath
$check = Test-G13RPR2FormalExecutionReceipt -Receipt $receipt -ExpectedFormalRoot $formalRoot -ExpectedHashes $expectedHashes -MaximumPreflightAgeSeconds 900
$validationPaths = [ordered]@{
    prelaunchCheckpointSha256 = 'Research\Gate13R_PR2_Attempt2_Prelaunch_Checkpoint.v1.json'
    prelaunchEvidenceManifestSha256 = 'Research\Verification\Gate13R_PR2_Formal_Attempt2\v1\prelaunch-evidence-manifest.v1.json'
    finalPrelaunchAuditSha256 = 'Research\Verification\Gate13R_PR2_Formal_Attempt2\v1\FinalPrelaunchAttempt1\audit.json'
    contractRehearsalEvidenceSha256 = 'Research\Verification\Gate13R_PR2_Formal_Attempt2\v1\contract-rehearsal-evidence-manifest.v1.json'
    campaignValidationOnlyDryRunSha256 = 'Research\Verification\Gate13R_PR2_Formal_Attempt2\v1\campaign-validation-only-dry-run-summary.v1.json'
    negativeNoReceiptSha256 = 'Research\Verification\Gate13R_PR2_Formal_Attempt2\v1\NegativeNoReceiptAttempt2\summary.json'
}
$validationErrors = New-Object Collections.Generic.List[string]
foreach ($entry in $validationPaths.GetEnumerator()) {
    $path = Join-Path $ProjectPath ([string]$entry.Value)
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { $validationErrors.Add("missing-$($entry.Key)"); continue }
    if ((Get-G13RPR2Sha256 $path) -ne [string]$receipt.validationBindings.($entry.Key)) { $validationErrors.Add("hash-$($entry.Key)") }
}
if (Test-Path -LiteralPath $formalRoot) { $validationErrors.Add('formal-root-exists') }
if (Test-Path -LiteralPath $statusPath) { $validationErrors.Add('formal-status-exists') }
if (@(Get-Process -Name Unity -ErrorAction SilentlyContinue).Count -ne 0) { $validationErrors.Add('unity-not-quiescent') }
if (Test-Path -LiteralPath (Join-Path $ProjectPath 'Temp\UnityLockfile')) { $validationErrors.Add('project-lock-present') }
$passed = $check.passed -eq $true -and $validationErrors.Count -eq 0
$summary = [ordered]@{
    schemaVersion = 1
    summaryKind = 'gate13r-pr2-attempt2-formal-execution-receipt-validation-v1'
    validatedAtUtc = [DateTime]::UtcNow.ToString('o')
    receiptSha256 = Get-G13RPR2Sha256 $receiptPath
    expectedBindingCount = $expectedHashes.Count
    receiptErrors = @($check.errors)
    validationBindingCount = $validationPaths.Count
    validationErrors = $validationErrors.ToArray()
    formalRootV2Absent = -not (Test-Path -LiteralPath $formalRoot)
    formalStatusV2Absent = -not (Test-Path -LiteralPath $statusPath)
    unityProcessCount = @(Get-Process -Name Unity -ErrorAction SilentlyContinue).Count
    projectLockAbsent = -not (Test-Path -LiteralPath (Join-Path $ProjectPath 'Temp\UnityLockfile'))
    passed = $passed
}
Write-G13RPR2AtomicJson -Path $OutputPath -Value $summary -Depth 30
if (-not $passed) { Write-Error ('Attempt-2 execution receipt validation failed: ' + ((@($check.errors) + @($validationErrors)) -join ', ')); exit 1 }
(Get-Item -LiteralPath $receiptPath -Force).IsReadOnly = $true
Write-Output "GATE13R-PR2-ATTEMPT2-EXECUTION-RECEIPT-PASSED|$($expectedHashes.Count)-BINDINGS|$($validationPaths.Count)-VALIDATION-BINDINGS"
exit 0

