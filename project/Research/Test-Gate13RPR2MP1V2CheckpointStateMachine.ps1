[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$ProjectPath,
    [Parameter(Mandatory = $true)][string]$OutputRoot,
    [switch]$BindingSmokeOnly
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if ([string]::IsNullOrWhiteSpace($ProjectPath) -or -not [IO.Path]::IsPathRooted($ProjectPath)) { throw 'An explicit absolute ProjectPath is required.' }
$ProjectPath = [IO.Path]::GetFullPath($ProjectPath)
if ($BindingSmokeOnly) { Write-Output "BINDING-SMOKE-PASSED|Test-Gate13RPR2MP1V2CheckpointStateMachine|$ProjectPath"; exit 0 }
$OutputRoot = [IO.Path]::GetFullPath($OutputRoot)
$verificationBase = [IO.Path]::GetFullPath((Join-Path $ProjectPath 'Research\Verification\Gate13R_PR2_MP1_v2')).TrimEnd('\','/')
if (-not $OutputRoot.StartsWith($verificationBase + [IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)) { throw 'State-machine fixture root is outside the v2 verification base.' }
if (Test-Path -LiteralPath $OutputRoot) { throw "Create-new fixture root exists: $OutputRoot" }
if (Test-Path -LiteralPath (Join-Path $ProjectPath 'Research\PilotRuns\Gate13R_PR2_MemoryPolicy\v2')) { throw 'Measured v2 pilot root must remain absent during checkpoint fixtures.' }
if (@(Get-Process -Name Unity -ErrorAction SilentlyContinue).Count -ne 0) { throw 'Unity must not run during checkpoint fixtures.' }

Import-Module (Join-Path $ProjectPath 'Research\Gate13RPR2MemoryPolicyPilotV2.psm1') -Force
New-Item -ItemType Directory -Path $OutputRoot -Force | Out-Null
$tests = New-Object Collections.Generic.List[object]
function Add-Test([string]$Id,[bool]$Passed,[string]$Detail) {
    $tests.Add([ordered]@{id=$Id;passed=$Passed;detail=$Detail})
    if (-not $Passed) { throw "$Id failed: $Detail" }
}

$successPath = Join-Path $OutputRoot 'success-checkpoint.json'
$initial = New-G13RPR2MP1V2Checkpoint
$initialWrite = Write-G13RPR2MP1V2AtomicJson -Path $successPath -Value $initial -Depth 50 -PassThru
Add-Test 'create-new-initial' ($initialWrite.targetExisted -eq $false -and $initialWrite.backupUsed -eq $false) ([string]$initialWrite.sha256)
$collisionRejected = $false
try { Write-G13RPR2MP1V2AtomicJson -Path $successPath -Value $initial -Depth 50 } catch { $collisionRejected = $true }
Add-Test 'create-new-collision-rejected' $collisionRejected 'A duplicate create-new write must fail.'

$running = Write-G13RPR2MP1V2CheckpointTransition -Path $successPath -Status 'MEASURED-ACQUISITION-RUNNING'
Add-Test 'running-transition' ([string]$running.status -eq 'MEASURED-ACQUISITION-RUNNING' -and -not [string]::IsNullOrWhiteSpace([string]$running.startedAtUtc)) ([string]$running.status)
$progress1 = Write-G13RPR2MP1V2CheckpointTransition -Path $successPath -Status 'BLOCK-PROGRESS' -TransitionArguments @{CompletedBlockCount=1;CurrentGlobalProcessOrdinal=1;CurrentBlockId='fixture-block-001'}
Add-Test 'first-block-progress' ([int]$progress1.completedSampleCount -eq 4 -and [string]$progress1.lastCompletedBlockId -eq 'fixture-block-001') ([string]$progress1.status)
$progress96 = Write-G13RPR2MP1V2CheckpointTransition -Path $successPath -Status 'BLOCK-PROGRESS' -TransitionArguments @{CompletedBlockCount=96;CurrentGlobalProcessOrdinal=96;CurrentBlockId='fixture-block-096'}
Add-Test 'last-block-progress' ([int]$progress96.completedSampleCount -eq 384) ([string]$progress96.completedSampleCount)
$phase = Write-G13RPR2MP1V2CheckpointTransition -Path $successPath -Status 'PHASE-A-COMMIT-IN-PROGRESS' -TransitionArguments @{CompletedBlockCount=96;CurrentGlobalProcessOrdinal=96;CurrentBlockId='fixture-block-096'}
Add-Test 'phase-a-start' (-not [string]::IsNullOrWhiteSpace([string]$phase.phaseACommitStartedAtUtc)) ([string]$phase.phaseACommitStartedAtUtc)
$rawHash = ('ab' * 32)
$manifestHash = ('cd' * 32)
$environmentHash = ('ef' * 32)
$complete = Write-G13RPR2MP1V2CheckpointTransition -Path $successPath -Status 'PILOT-RAW-DATA-COMPLETE / ANALYSIS-PENDING / IMMUTABLE' -TransitionArguments @{
    CompletedBlockCount=96;CurrentGlobalProcessOrdinal=96;CurrentBlockId='fixture-block-096';RawTreeSha256=$rawHash;
    RawManifestRelativePath='pilot-raw-tree-manifest.json';RawManifestSha256=$manifestHash;
    EnvironmentEndSnapshotRelativePath='pilot-environment-end-snapshot.json';EnvironmentEndSnapshotSha256=$environmentHash
}
Add-Test 'raw-complete-persistence' ([string]$complete.rawTreeSha256 -eq $rawHash -and $complete.phaseACommitted -eq $true -and $complete.rawDataComplete -eq $true) ([string]$complete.rawTreeSha256)

function Invoke-FailureFixture([string]$Id,[string]$FromStatus,[int]$Completed,[int]$Ordinal,[string]$BlockId) {
    $root = Join-Path $OutputRoot $Id
    New-Item -ItemType Directory -Path $root -Force | Out-Null
    $path = Join-Path $root 'checkpoint.json'
    Write-G13RPR2MP1V2AtomicJson -Path $path -Value (New-G13RPR2MP1V2Checkpoint) -Depth 50
    if ($FromStatus -ne 'AUTHORIZED-NOT-STARTED') {
        $null = Write-G13RPR2MP1V2CheckpointTransition -Path $path -Status 'MEASURED-ACQUISITION-RUNNING'
    }
    if ($FromStatus -eq 'BLOCK-PROGRESS') {
        $null = Write-G13RPR2MP1V2CheckpointTransition -Path $path -Status 'BLOCK-PROGRESS' -TransitionArguments @{CompletedBlockCount=$Completed;CurrentGlobalProcessOrdinal=$Ordinal;CurrentBlockId=$BlockId}
    }
    if ($FromStatus -eq 'PHASE-A-COMMIT-IN-PROGRESS') {
        $null = Write-G13RPR2MP1V2CheckpointTransition -Path $path -Status 'BLOCK-PROGRESS' -TransitionArguments @{CompletedBlockCount=96;CurrentGlobalProcessOrdinal=96;CurrentBlockId='fixture-block-096'}
        $null = Write-G13RPR2MP1V2CheckpointTransition -Path $path -Status 'PHASE-A-COMMIT-IN-PROGRESS' -TransitionArguments @{CompletedBlockCount=96;CurrentGlobalProcessOrdinal=96;CurrentBlockId='fixture-block-096'}
        $Completed=96;$Ordinal=96;$BlockId='fixture-block-096'
    }
    $partialPath = Join-Path $root 'partial-output-manifest.json'
    $failurePath = Join-Path $root 'failure-receipt.json'
    Write-G13RPR2MP1V2AtomicJson -Path $partialPath -Value ([ordered]@{schemaVersion=1;manifestKind='fixture-partial';fileCount=0;rawBytes=0}) -Depth 10
    Write-G13RPR2MP1V2AtomicJson -Path $failurePath -Value ([ordered]@{schemaVersion=1;receiptKind='fixture-failure';failureStage=$Id}) -Depth 10
    $failed = Write-G13RPR2MP1V2CheckpointTransition -Path $path -Status 'FAILED-NO-AUTO-RETRY-NO-RESUME-NO-TOP-UP-NO-MERGE' -TransitionArguments @{
        CompletedBlockCount=$Completed;CurrentGlobalProcessOrdinal=$Ordinal;CurrentBlockId=$BlockId;
        FailureClass='SYNTHETIC-FAILURE';FailureStage=$Id;FailureMessage=('fixture '+$Id);
        FailureReceiptRelativePath='failure-receipt.json';FailureReceiptSha256=Get-G13RPR2MP1V2Sha256 $failurePath;
        PartialOutputManifestRelativePath='partial-output-manifest.json';PartialOutputManifestSha256=Get-G13RPR2MP1V2Sha256 $partialPath
    }
    Add-Test $Id ([string]$failed.status -eq 'FAILED-NO-AUTO-RETRY-NO-RESUME-NO-TOP-UP-NO-MERGE' -and [int]$failed.completedBlockCount -eq $Completed) ([string]$failed.failureStage)
}

Invoke-FailureFixture 'failure-before-first-block' 'AUTHORIZED-NOT-STARTED' 0 0 $null
Invoke-FailureFixture 'failure-inside-block' 'BLOCK-PROGRESS' 4 4 'fixture-block-004'
Invoke-FailureFixture 'failure-after-last-before-freeze' 'PHASE-A-COMMIT-IN-PROGRESS' 96 96 'fixture-block-096'

$residual = @(Get-ChildItem -LiteralPath $OutputRoot -Recurse -Force -File | Where-Object { $_.Name -like '.g13rpr2-mp1-v2-temp-*' -or $_.Name -like '.g13rpr2-mp1-v2-backup-*' })
Add-Test 'no-residual-atomic-artifacts' ($residual.Count -eq 0) ([string]$residual.Count)
Add-Test 'unity-not-invoked' (@(Get-Process -Name Unity -ErrorAction SilentlyContinue).Count -eq 0) 'Checkpoint fixtures do not invoke Unity.'

$summary = [ordered]@{
    schemaVersion=1;summaryKind='gate13r-pr2-mp1-v2-checkpoint-state-machine-fixtures-v1';savedAtUtc=[DateTime]::UtcNow.ToString('o')
    runtime=$PSVersionTable.PSVersion.ToString();testCount=$tests.Count;passedTestCount=@($tests|Where-Object{$_.passed}).Count
    tests=$tests.ToArray();measuredPilotStarted=$false;unityInvoked=$false;formalCampaign=$false;formalAnalysis=$false;gate14R=$false
    passed=@($tests|Where-Object{-not $_.passed}).Count -eq 0
}
Write-G13RPR2MP1V2AtomicJson -Path (Join-Path $OutputRoot 'checkpoint-state-machine-summary.json') -Value $summary -Depth 40
Write-Host "Gate13R-PR2-MP1 v2 checkpoint fixtures passed: $($summary.passedTestCount)/$($summary.testCount) on PowerShell $($summary.runtime)." -ForegroundColor Green
exit 0
