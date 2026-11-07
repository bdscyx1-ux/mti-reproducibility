[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$ProjectPath,
    [Parameter(Mandatory = $true)][string]$OutputRoot,
    [switch]$BindingSmokeOnly
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$ProjectPath = [IO.Path]::GetFullPath($ProjectPath)
if ($BindingSmokeOnly) { Write-Output "BINDING-SMOKE-PASSED|Test-Gate13RPR2FormalExecutionV4|$ProjectPath"; exit 0 }
$OutputRoot = [IO.Path]::GetFullPath($OutputRoot)
if (Test-Path -LiteralPath $OutputRoot) { throw "Create-new unit-test root exists: $OutputRoot" }
New-Item -ItemType Directory -Path $OutputRoot -Force | Out-Null
Import-Module (Join-Path $ProjectPath 'Research\Gate13RPR2FormalExecutionV3.psm1') -Force

$checks = New-Object Collections.Generic.List[object]
function Add-Check([string]$Name, [bool]$Passed, [string]$Detail) {
    $script:checks.Add([ordered]@{ name = $Name; passed = $Passed; detail = $Detail })
}

$schedule = Join-Path $ProjectPath 'Research\Gate13R_PR2_Formal_Williams_Matched_Schedule.v2.jsonl'
$wanted = @(1,49,1537,1538,3552)
$records = @{}
foreach ($line in [IO.File]::ReadLines($schedule, [Text.Encoding]::UTF8)) {
    $record = $line | ConvertFrom-Json
    if ($wanted -contains [int]$record.globalProcessOrdinal) { $records[[int]$record.globalProcessOrdinal] = $record }
}
Add-Check 'selected-records-found' ($records.Count -eq $wanted.Count) "found=$($records.Count)"
$dummy = '0' * 64
foreach ($ordinal in $wanted) {
    $record = $records[$ordinal]
    $plan = New-G13RPR2BlockPlanFromScheduleRecord -ScheduleRecord $record -FormalConfigRelativePath 'Research/config.json' -FormalConfigSha256 $dummy -SpecificationRelativePath 'Research/spec.md' -SpecificationSha256 $dummy -TestDesignRelativePath 'Research/test.md' -TestDesignSha256 $dummy -AmendmentRelativePath 'Research/amend.json' -AmendmentSha256 $dummy -CommandRelativePath 'Assets/command.cs' -CommandSha256 $dummy -ProvenanceRelativePath 'Research/provenance.json' -ProvenanceSha256 $dummy -ExecutionReceiptRelativePath 'Research/receipt.json' -ExecutionReceiptSha256 $dummy
    Add-Check "plan-$ordinal-williams-row" ([int]$plan.williamsRowIndex -eq [int]$record.williamsRowIndex) "plan=$($plan.williamsRowIndex) schedule=$($record.williamsRowIndex)"
    Add-Check "plan-$ordinal-block-identity" ([int]$plan.block -eq [int]$record.campaignBlockOrdinal) "plan=$($plan.block) schedule=$($record.campaignBlockOrdinal)"
    $planAlgorithms = @($plan.entries | ForEach-Object { [string]$_.algorithmId }) -join ','
    $recordAlgorithms = @($record.entries | ForEach-Object { [string]$_.algorithmId }) -join ','
    Add-Check "plan-$ordinal-order" ($planAlgorithms -eq $recordAlgorithms) $planAlgorithms
}

$expectedHashes = @{
    readinessSha256 = $dummy; configSha256 = $dummy; scheduleSha256 = $dummy; scheduleManifestSha256 = $dummy
    commandSha256 = $dummy; blockWrapperSha256 = $dummy; orchestratorSha256 = $dummy; moduleSha256 = $dummy
    adapterProvenanceSha256 = $dummy; twoPhaseAmendmentSha256 = $dummy; prelaunchTestDesignSha256 = $dummy
}
$receipt = [pscustomobject][ordered]@{
    schemaVersion = 1
    receiptKind = 'gate13r-pr2-s48-h48-formal-raw-acquisition-execution-receipt-v1'
    status = 'AUTHORIZED-FOR-ONE-RAW-ACQUISITION-ATTEMPT'
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
    formalRootResolved = 'H:\DDM_Final_Project\Research\FormalRuns\Gate13R_RQAligned_S48H48\v1'
    bindings = [pscustomobject]$expectedHashes
    preflightCompletedAtUtc = [DateTime]::UtcNow.ToString('o')
    storage = [pscustomobject]@{ availableFreeBytes = 60000000000L; minimumLaunchFreeBytes = 57397541440L }
}
$valid = Test-G13RPR2FormalExecutionReceipt -Receipt $receipt -ExpectedFormalRoot $receipt.formalRootResolved -ExpectedHashes $expectedHashes
Add-Check 'valid-receipt-accepted' $valid.passed (@($valid.errors) -join ',')
$receipt.rawAcquisitionAuthorized = $false
$invalid = Test-G13RPR2FormalExecutionReceipt -Receipt $receipt -ExpectedFormalRoot $receipt.formalRootResolved -ExpectedHashes $expectedHashes
Add-Check 'unauthorized-receipt-rejected' (-not $invalid.passed -and @($invalid.errors) -contains 'authorization-boundary') (@($invalid.errors) -join ',')
$receipt.rawAcquisitionAuthorized = $true
$receipt.bindings.scheduleSha256 = '1' * 64
$badHash = Test-G13RPR2FormalExecutionReceipt -Receipt $receipt -ExpectedFormalRoot $receipt.formalRootResolved -ExpectedHashes $expectedHashes
Add-Check 'wrong-binding-rejected' (-not $badHash.passed -and @($badHash.errors) -contains 'binding-scheduleSha256') (@($badHash.errors) -join ',')

$stableTextPath = Join-Path $OutputRoot 'stable-text-fixture.log'
[IO.File]::WriteAllText($stableTextPath, "stable-log-text`n", (New-Object Text.UTF8Encoding($false,$true)))
$stableText = Read-G13RPR2TextWithRetry -Path $stableTextPath -TimeoutMilliseconds 2000 -PollMilliseconds 50
Add-Check 'stable-text-readable' ($stableText -eq "stable-log-text`n") "length=$($stableText.Length)"
$exclusive = [IO.File]::Open($stableTextPath, [IO.FileMode]::Open, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
$exclusiveRejected = $false
try { Read-G13RPR2TextWithRetry -Path $stableTextPath -TimeoutMilliseconds 250 -PollMilliseconds 25 | Out-Null }
catch { $exclusiveRejected = $_.Exception.Message.Contains('Timed out waiting for a stable readable text file') }
finally { $exclusive.Dispose() }
Add-Check 'exclusive-log-handle-retried-and-bounded' $exclusiveRejected 'Exclusive handle must produce a bounded retry timeout, not an unclassified sharing exception.'
$recoveredText = Read-G13RPR2TextWithRetry -Path $stableTextPath -TimeoutMilliseconds 2000 -PollMilliseconds 50
Add-Check 'log-readable-after-handle-release' ($recoveredText -eq "stable-log-text`n") "length=$($recoveredText.Length)"

$duringAcquisition = Get-G13RPR2FailureStatus -AllUnityCompleted $false -ErrorMessage 'wrapper failed'
$postUnityTooling = Get-G13RPR2FailureStatus -AllUnityCompleted $true -ErrorMessage 'manifest serializer failed'
$postUnityContract = Get-G13RPR2FailureStatus -AllUnityCompleted $true -ErrorMessage 'RAW-CONTRACT-VIOLATION: missing block evidence'
Add-Check 'two-phase-during-acquisition-fail-closed' ($duringAcquisition -eq 'FAILED-NO-AUTO-RETRY-NO-RESUME-NO-TOP-UP-NO-MERGE') $duringAcquisition
Add-Check 'two-phase-post-unity-tooling-no-rerun' ($postUnityTooling -eq 'UNITY-COLLECTION-COMPLETE / RAW-COMMIT-AUDIT-PENDING / NO-UNITY-RERUN') $postUnityTooling
Add-Check 'two-phase-post-unity-contract-user-decision' ($postUnityContract -eq 'RAW-CONTRACT-VIOLATION / USER-DECISION-REQUIRED / NO-UNITY-RERUN') $postUnityContract

$selfTestSource = [IO.File]::ReadAllText((Join-Path $ProjectPath 'Research\Run-Gate13RPR2FormalUnitySelfTestsV3.ps1'), [Text.Encoding]::UTF8)
$telemetrySource = [IO.File]::ReadAllText((Join-Path $ProjectPath 'Research\Run-Gate13RPR2FormalTelemetryProbeV3.ps1'), [Text.Encoding]::UTF8)
$blockSource = [IO.File]::ReadAllText((Join-Path $ProjectPath 'Research\Run-Gate13RPR2FormalBlockV4.ps1'), [Text.Encoding]::UTF8)
Add-Check 'self-test-explicit-compiler-array-count' ($selfTestSource.Contains('@($compilerMatches).Count')) 'Windows PowerShell 5.1 empty-pipeline collapse is guarded.'
Add-Check 'telemetry-explicit-compiler-array-count' ($telemetrySource.Contains('@($compiler).Count')) 'Windows PowerShell 5.1 empty-pipeline collapse is guarded.'
Add-Check 'formal-block-explicit-compiler-array-count' ($blockSource.Contains('@($compilerMatches).Count')) 'Windows PowerShell 5.1 empty-pipeline collapse is guarded.'

$fixture = Join-Path $OutputRoot 'raw-fixture'
New-Item -ItemType Directory -Path (Join-Path $fixture 'blocks\b1\runs\p01') -Force | Out-Null
[IO.File]::WriteAllText((Join-Path $fixture 'blocks\b1\block-manifest.json'), "{}`n", (New-Object Text.UTF8Encoding($false,$true)))
[IO.File]::WriteAllText((Join-Path $fixture 'blocks\b1\runs\p01\sample-summary.json'), "{}`n", (New-Object Text.UTF8Encoding($false,$true)))
[IO.File]::WriteAllText((Join-Path $fixture 'formal-checkpoint.json'), "{}`n", (New-Object Text.UTF8Encoding($false,$true)))
$snapshot1 = Get-G13RPR2RawPayloadSnapshot -FormalRoot $fixture
$snapshot2 = Get-G13RPR2RawPayloadSnapshot -FormalRoot $fixture
Add-Check 'raw-snapshot-deterministic' ([string]$snapshot1.canonicalTreeSha256 -eq [string]$snapshot2.canonicalTreeSha256) ([string]$snapshot1.canonicalTreeSha256)
Add-Check 'raw-snapshot-excludes-control' ([int]$snapshot1.fileCount -eq 2) "files=$($snapshot1.fileCount)"
$fileManifest = Join-Path $fixture 'raw-payload-file-manifest.jsonl'
Write-G13RPR2RawPayloadFileManifest -Path $fileManifest -Snapshot $snapshot1
Set-G13RPR2RawPayloadReadOnly -FormalRoot $fixture -Snapshot $snapshot1
$readonly = $true
foreach ($record in @($snapshot1.records)) {
    $path = Join-Path $fixture ([string]$record.relativePath).Replace('/', '\')
    if (-not (Get-Item -LiteralPath $path -Force).IsReadOnly) { $readonly = $false }
}
Add-Check 'raw-payload-read-only' $readonly "files=$($snapshot1.fileCount)"
$snapshot3 = Get-G13RPR2RawPayloadSnapshot -FormalRoot $fixture
Add-Check 'read-only-does-not-change-tree' ([string]$snapshot1.canonicalTreeSha256 -eq [string]$snapshot3.canonicalTreeSha256) ([string]$snapshot3.canonicalTreeSha256)

$formalRoot = Join-Path $ProjectPath 'Research\FormalRuns\Gate13R_RQAligned_S48H48\v1'
$formalReceipt = Join-Path $ProjectPath 'Research\Gate13R_PR2_Formal_Execution_Receipt.v1.json'
Add-Check 'formal-root-absent' (-not (Test-Path -LiteralPath $formalRoot)) $formalRoot
Add-Check 'formal-receipt-absent' (-not (Test-Path -LiteralPath $formalReceipt)) $formalReceipt
Add-Check 'unity-zero' (@(Get-Process -Name Unity -ErrorAction SilentlyContinue).Count -eq 0) 'No Unity invocation is permitted in this unit test.'

$failed = @($checks | Where-Object { -not $_.passed })
$summary = [ordered]@{
    schemaVersion = 1
    summaryKind = 'gate13r-pr2-formal-execution-adapter-unit-and-two-phase-fixture-v4'
    completedAtUtc = [DateTime]::UtcNow.ToString('o')
    checkCount = $checks.Count
    passedCheckCount = @($checks | Where-Object passed).Count
    failedCheckCount = $failed.Count
    failedCheckNames = @($failed | ForEach-Object { [string]$_.name })
    checks = $checks.ToArray()
    formalRootAbsent = -not (Test-Path -LiteralPath $formalRoot)
    formalExecutionReceiptAbsent = -not (Test-Path -LiteralPath $formalReceipt)
    unityLaunched = $false
    passed = $failed.Count -eq 0
}
Write-G13RPR2AtomicJson -Path (Join-Path $OutputRoot 'summary.json') -Value $summary -Depth 50
if (-not $summary.passed) { Write-Error ('Formal execution unit tests failed: ' + (@($summary.failedCheckNames) -join ', ')); exit 1 }
Write-Host "Gate13R-PR2 formal execution unit tests passed: $($summary.passedCheckCount)/$($summary.checkCount)." -ForegroundColor Green
exit 0
