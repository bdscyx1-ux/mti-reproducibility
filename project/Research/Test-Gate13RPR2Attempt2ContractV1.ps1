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
if ($BindingSmokeOnly) {
    Write-Output "BINDING-SMOKE-PASSED|Test-Gate13RPR2Attempt2ContractV1|$ProjectPath"
    exit 0
}
$OutputPath = [IO.Path]::GetFullPath($OutputPath)
$verificationBase = [IO.Path]::GetFullPath((Join-Path $ProjectPath 'Research\Verification\Gate13R_PR2_Formal_Attempt2\v1')).TrimEnd('\', '/')
if (-not $OutputPath.StartsWith($verificationBase + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) { throw 'OutputPath escapes the attempt-2 verification root.' }
if (Test-Path -LiteralPath $OutputPath) { throw 'Create-new unit summary already exists.' }
if (Test-Path -LiteralPath (Join-Path $ProjectPath 'Research\FormalRuns\Gate13R_RQAligned_S48H48\v2')) { throw 'Attempt-2 formal root must remain absent during unit tests.' }
if (Test-Path -LiteralPath (Join-Path $ProjectPath 'Research\Gate13R_PR2_Formal_Execution_Receipt.v2.json')) { throw 'Attempt-2 formal receipt must remain absent during unit tests.' }

Import-Module (Join-Path $ProjectPath 'Research\Gate13RPR2FormalExecutionV5.psm1') -Force

$tests = New-Object Collections.Generic.List[object]
function Add-Test([string]$Id, [bool]$Passed, [string]$Detail) {
    $script:tests.Add([ordered]@{ id = $Id; passed = $Passed; detail = $Detail })
}
function New-Sample([string]$RunId, $FormalCampaign, [bool]$IncludeFormal = $true) {
    $value = [ordered]@{ runId = $RunId; completed = $true }
    if ($IncludeFormal) { $value.formalCampaign = $FormalCampaign }
    return [pscustomobject]$value
}
function Test-EmbeddedFixture([string]$Id, [object[]]$Samples, [bool]$Expected, [string]$ExpectedReason) {
    $actual = Test-G13RPR2EmbeddedSampleFormalCampaignContract -Samples $Samples -ExpectedCount 4
    $reasonMatched = if ([string]::IsNullOrWhiteSpace($ExpectedReason)) { $true } else { (@($actual.errors | Where-Object { $_ -like $ExpectedReason }).Count -gt 0) }
    Add-Test $Id (($actual.passed -eq $Expected) -and $reasonMatched) ((@($actual.errors) -join ','))
}

$valid = @(
    (New-Sample 'run-1' $true),
    (New-Sample 'run-2' $true),
    (New-Sample 'run-3' $true),
    (New-Sample 'run-4' $true)
)
Test-EmbeddedFixture 'embedded-positive-four-boolean-true' $valid $true ''

$missing = @($valid[0],$valid[1],$valid[2],(New-Sample 'run-4' $null $false))
Test-EmbeddedFixture 'embedded-missing-fails' $missing $false 'embedded-formalCampaign-missing-*'
$falseValue = @($valid[0],$valid[1],$valid[2],(New-Sample 'run-4' $false))
Test-EmbeddedFixture 'embedded-false-fails' $falseValue $false 'embedded-formalCampaign-false-*'
$stringValue = @($valid[0],$valid[1],$valid[2],(New-Sample 'run-4' 'true'))
Test-EmbeddedFixture 'embedded-string-fails' $stringValue $false 'embedded-formalCampaign-type-*'
$numericValue = @($valid[0],$valid[1],$valid[2],(New-Sample 'run-4' 1))
Test-EmbeddedFixture 'embedded-number-fails' $numericValue $false 'embedded-formalCampaign-type-*'
$nullValue = @($valid[0],$valid[1],$valid[2],(New-Sample 'run-4' $null))
Test-EmbeddedFixture 'embedded-null-fails' $nullValue $false 'embedded-formalCampaign-type-*'
$duplicate = @($valid[0],$valid[1],$valid[2],(New-Sample 'run-3' $true))
Test-EmbeddedFixture 'embedded-duplicate-run-fails' $duplicate $false 'embedded-runId-duplicate-*'
Test-EmbeddedFixture 'embedded-cardinality-fails' @($valid[0],$valid[1],$valid[2]) $false 'embedded-sample-cardinality'

$root = [IO.Path]::GetFullPath((Join-Path $ProjectPath 'Research\FormalRuns\Gate13R_RQAligned_S48H48\v2')).TrimEnd('\', '/')
$expectedHashes = @{ testBinding = ('a' * 64) }
$baseReceipt = [ordered]@{
    schemaVersion = 1
    receiptKind = 'gate13r-pr2-s48-h48-formal-raw-acquisition-execution-receipt-attempt-2-v1'
    status = 'AUTHORIZED-FOR-ONE-RAW-ACQUISITION-ATTEMPT'
    formalAttemptOrdinal = 2
    attempt2AuthorizationId = 'gate13r-pr2-s48-h48-formal-attempt-2-embedded-sample-contract-repair-and-one-raw-acquisition-v1'
    attempt1Disposition = 'FAILED-NO-AUTO-RETRY-NO-RESUME-NO-TOP-UP-NO-MERGE / PARTIAL-ATTEMPT-EVIDENCE / EXCLUDED-FROM-FORMAL-ANALYSIS'
    attempt1CanonicalTreeSha256 = '026b9830f220b06af3f0a106f638b3d918d115ba08f5f06c13d9d76542ba4f56'
    formalCampaignAuthorized = $true
    rawAcquisitionAuthorized = $true
    formalAnalysisAuthorized = $false
    gate14RAuthorized = $false
    noAutomaticRetry = $true
    noAutomaticResume = $true
    noTopUp = $true
    noPartialMerge = $true
    twoPhaseCommitId = 'gate13r-pr2-raw-analysis-two-phase-commit-v1'
    twoPhaseCommitRequired = $true
    ordinaryPostCollectionToolFailureMayRerunUnity = $false
    analysisFailureMayRerunUnity = $false
    supplementalAuthorizationId = 'gate13r-pr2-two-phase-supplemental-authorization-v1'
    formalRootResolved = $root
    bindings = [ordered]@{ testBinding = ('a' * 64) }
    preflightCompletedAtUtc = [DateTime]::UtcNow.ToString('o')
    storage = [ordered]@{ availableFreeBytes = 60000000000L; minimumLaunchFreeBytes = 57397541440L }
}
function Copy-Receipt($Value) { return (($Value | ConvertTo-Json -Depth 20) | ConvertFrom-Json) }
function Test-ReceiptFixture([string]$Id, $Value, [bool]$Expected, [string]$ExpectedReason, [DateTime]$Now = ([DateTime]::UtcNow)) {
    $actual = Test-G13RPR2FormalExecutionReceipt -Receipt $Value -ExpectedFormalRoot $root -ExpectedHashes $expectedHashes -NowUtc $Now
    $reasonMatched = if ([string]::IsNullOrWhiteSpace($ExpectedReason)) { $true } else { @($actual.errors | Where-Object { $_ -eq $ExpectedReason }).Count -gt 0 }
    Add-Test $Id (($actual.passed -eq $Expected) -and $reasonMatched) ((@($actual.errors) -join ','))
}

Test-ReceiptFixture 'receipt-positive-attempt2' (Copy-Receipt $baseReceipt) $true ''
$wrongAttempt = Copy-Receipt $baseReceipt; $wrongAttempt.formalAttemptOrdinal = 1
Test-ReceiptFixture 'receipt-attempt1-reuse-rejected' $wrongAttempt $false 'formal-attempt-ordinal'
$wrongRoot = Copy-Receipt $baseReceipt; $wrongRoot.formalRootResolved = (Join-Path $ProjectPath 'Research\FormalRuns\Gate13R_RQAligned_S48H48\v1')
Test-ReceiptFixture 'receipt-wrong-root-rejected' $wrongRoot $false 'root'
$wrongKind = Copy-Receipt $baseReceipt; $wrongKind.receiptKind = 'gate13r-pr2-s48-h48-formal-raw-acquisition-execution-receipt-v1'
Test-ReceiptFixture 'receipt-attempt1-kind-rejected' $wrongKind $false 'kind'
$wrongBinding = Copy-Receipt $baseReceipt; $wrongBinding.bindings.testBinding = ('b' * 64)
Test-ReceiptFixture 'receipt-binding-rejected' $wrongBinding $false 'binding-testBinding'
$stale = Copy-Receipt $baseReceipt; $stale.preflightCompletedAtUtc = [DateTime]::UtcNow.AddHours(-1).ToString('o')
Test-ReceiptFixture 'receipt-stale-rejected' $stale $false 'preflight-stale'
$analysis = Copy-Receipt $baseReceipt; $analysis.formalAnalysisAuthorized = $true
Test-ReceiptFixture 'receipt-analysis-authorization-rejected' $analysis $false 'authorization-boundary'

Add-Test 'failure-before-unity-complete' ((Get-G13RPR2FailureStatus -AllUnityCompleted $false -ErrorMessage 'x') -eq 'FAILED-NO-AUTO-RETRY-NO-RESUME-NO-TOP-UP-NO-MERGE') 'pre-collection failure token'
Add-Test 'failure-after-unity-ordinary-tool' ((Get-G13RPR2FailureStatus -AllUnityCompleted $true -ErrorMessage 'ordinary auditor error') -eq 'UNITY-COLLECTION-COMPLETE / RAW-COMMIT-AUDIT-PENDING / NO-UNITY-RERUN') 'post-collection ordinary tool token'
Add-Test 'failure-after-unity-raw-contract' ((Get-G13RPR2FailureStatus -AllUnityCompleted $true -ErrorMessage 'RAW-CONTRACT-VIOLATION: fixture') -eq 'RAW-CONTRACT-VIOLATION / USER-DECISION-REQUIRED / NO-UNITY-RERUN') 'post-collection raw violation token'

$failed = @($tests | Where-Object { $_.passed -ne $true })
$summary = [ordered]@{
    schemaVersion = 1
    summaryKind = 'gate13r-pr2-attempt2-contract-unit-summary-v1'
    savedAtUtc = [DateTime]::UtcNow.ToString('o')
    testCount = $tests.Count
    passedTestCount = $tests.Count - $failed.Count
    failedTestCount = $failed.Count
    tests = $tests.ToArray()
    formalRootCreated = $false
    unityStarted = $false
    passed = $failed.Count -eq 0
}
Write-G13RPR2AtomicJson -Path $OutputPath -Value $summary -Depth 40
if ($failed.Count -gt 0) { Write-Error ("Gate13R-PR2 attempt-2 contract tests failed: " + (($failed | ForEach-Object id) -join ', ')); exit 1 }
Write-Output "GATE13R-PR2-ATTEMPT2-CONTRACT-TESTS-PASSED|$($tests.Count)-OF-$($tests.Count)"
exit 0

