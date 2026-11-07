[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$ProjectPath,
    [Parameter(Mandatory = $true)][string]$PilotRoot,
    [Parameter(Mandatory = $true)][string]$ExecutionReceiptPath,
    [string]$ConfigPath,
    [string]$SchedulePath,
    [string]$ProvenancePath,
    [string]$UnityPath = 'H:\UnityEditor\2022.3.30f1c1\Editor\Unity.exe',
    [switch]$BindingSmokeOnly,
    [switch]$ValidationOnly,
    [ValidateSet('None','BeforeFirstBlock','AfterLastBlockBeforeRawFreeze')][string]$InjectedFailureStage = 'None',
    [int]$BlockTimeoutSeconds = 3600
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if ([string]::IsNullOrWhiteSpace($ProjectPath) -or -not [IO.Path]::IsPathRooted($ProjectPath)) { throw 'An explicit absolute ProjectPath is required.' }
$ProjectPath = [IO.Path]::GetFullPath($ProjectPath)
if ($BindingSmokeOnly) { Write-Output "BINDING-SMOKE-PASSED|Run-Gate13RPR2MemoryPolicyPilotV2|$ProjectPath"; exit 0 }

Import-Module (Join-Path $ProjectPath 'Research\Gate13RPR2MemoryPolicyPilotV1.psm1') -Force
Import-Module (Join-Path $ProjectPath 'Research\Gate13RPR2MemoryPolicyPilotV2.psm1') -Force

$PilotRoot = [IO.Path]::GetFullPath($PilotRoot).TrimEnd('\','/')
$expectedPilotRoot = [IO.Path]::GetFullPath((Join-Path $ProjectPath 'Research\PilotRuns\Gate13R_PR2_MemoryPolicy\v2')).TrimEnd('\','/')
$verificationBase = [IO.Path]::GetFullPath((Join-Path $ProjectPath 'Research\Verification\Gate13R_PR2_MP1_v2')).TrimEnd('\','/')
if ($ValidationOnly) {
    if (-not (Test-G13RPR2MP1PathWithin -BasePath $verificationBase -CandidatePath $PilotRoot)) { throw 'Validation-only pilot root is outside the v2 verification base.' }
    if ($InjectedFailureStage -eq 'None') { throw 'Validation-only orchestrator execution requires an injected failure stage.' }
}
elseif (-not $PilotRoot.Equals($expectedPilotRoot,[StringComparison]::OrdinalIgnoreCase)) { throw 'Measured v2 pilot root identity mismatch.' }
if (-not $ValidationOnly) {
    $expectedModulePath = @('C:\Users\bdscy\Documents\WindowsPowerShell\Modules','C:\Program Files\WindowsPowerShell\Modules','C:\WINDOWS\System32\WindowsPowerShell\v1.0\Modules') -join ';'
    if ($PSVersionTable.PSVersion.Major -ne 5 -or [string]$env:PSModulePath -ne $expectedModulePath) { throw 'MP1 v2 measured orchestration requires native Windows PowerShell 5.1 and the verified native PSModulePath.' }
}

$rawRoot = [IO.Path]::GetFullPath((Join-Path $PilotRoot 'raw')).TrimEnd('\','/')
$ExecutionReceiptPath = [IO.Path]::GetFullPath($ExecutionReceiptPath)
$ConfigPath = if ([string]::IsNullOrWhiteSpace($ConfigPath)) { Join-Path $ProjectPath 'Research\Gate13R_PR2_MP1_Pilot_Config.v2.json' } else { [IO.Path]::GetFullPath($ConfigPath) }
$SchedulePath = if ([string]::IsNullOrWhiteSpace($SchedulePath)) { Join-Path $ProjectPath 'Research\Gate13R_PR2_MP1_Pilot_Schedule.v1.jsonl' } else { [IO.Path]::GetFullPath($SchedulePath) }
$ProvenancePath = if ([string]::IsNullOrWhiteSpace($ProvenancePath)) { Join-Path $ProjectPath 'Research\Gate13R_PR2_MP1_Provenance.v2_4.json' } else { [IO.Path]::GetFullPath($ProvenancePath) }
$UnityPath = [IO.Path]::GetFullPath($UnityPath)
$wrapperPath = Join-Path $ProjectPath 'Research\Run-Gate13RPR2MemoryPolicyPilotBlockV2.ps1'
$commandPath = Join-Path $ProjectPath 'Assets\_Scripts\Research\Editor\Gate13RPR2MemoryPolicyPilotBatchCommandV1.cs'
$specificationPath = Join-Path $ProjectPath 'Research\Gate13R_PR2_MP1_Specification.v1.md'
$testDesignPath = Join-Path $ProjectPath 'Research\Gate13R_PR2_MP1_v2_Test_Design.v1.md'
$twoStagePath = Join-Path $ProjectPath 'Research\Gate13R_PR2_MP1_Two_Phase_Commit_Contract.v1.json'
$stateAmendmentPath = Join-Path $ProjectPath 'Research\Gate13R_PR2_MP1_v2_Checkpoint_StateMachine_Amendment.v1.md'
$checkpointPath = Join-Path $PilotRoot 'pilot-checkpoint.json'
$partialPath = Join-Path $PilotRoot 'pilot-partial-output-manifest.json'
$failurePath = Join-Path $PilotRoot 'pilot-failure-receipt.json'
$currentStage = 'INPUT-VALIDATION'
$currentOrdinal = 0
$currentBlockId = $null
$completedBlocks = 0

function Get-V2RawInventory {
    $files = @()
    if (Test-Path -LiteralPath $rawRoot -PathType Container) {
        $files = @(Get-ChildItem -LiteralPath $rawRoot -Recurse -File -Force | Sort-Object FullName)
    }
    $rawBytes = 0L
    if ($files.Count -gt 0) { $rawBytes = [long](($files | Measure-Object Length -Sum).Sum) }
    return [pscustomobject][ordered]@{
        files = $files
        fileCount = $files.Count
        rawBytes = $rawBytes
    }
}

function Save-V2FailureEvidence {
    param([Parameter(Mandatory = $true)][Management.Automation.ErrorRecord]$Failure)
    $inventory = Get-V2RawInventory
    $partial = [ordered]@{
        schemaVersion=2;manifestKind='gate13r-pr2-mp1-partial-output-manifest-v2';savedAtUtc=[DateTime]::UtcNow.ToString('o')
        status='FAILED-NO-AUTO-RETRY-NO-RESUME-NO-TOP-UP-NO-MERGE';failureStage=$currentStage
        failedGlobalProcessOrdinal=$currentOrdinal;failedBlockId=$currentBlockId;completedBlockCount=$completedBlocks;completedSampleCount=$completedBlocks*4
        expectedBlockCount=96;expectedSampleCount=384;fileCount=$inventory.fileCount;rawBytes=$inventory.rawBytes
        files=@($inventory.files | ForEach-Object { [ordered]@{relativePath=$_.FullName.Substring($rawRoot.Length+1).Replace('\','/');bytes=[long]$_.Length;sha256=Get-G13RPR2MP1V2Sha256 $_.FullName} })
        unityProcessCount=@(Get-Process -Name Unity -ErrorAction SilentlyContinue).Count
        projectLockExists=Test-Path -LiteralPath (Join-Path $ProjectPath 'Temp\UnityLockfile')
        automaticRetryAuthorized=$false;automaticResumeAuthorized=$false;topUpAuthorized=$false;partialMergeAuthorized=$false
    }
    if (-not (Test-Path -LiteralPath $partialPath)) { Write-G13RPR2MP1V2AtomicJson -Path $partialPath -Value $partial -Depth 80 }
    $partialSha = Get-G13RPR2MP1V2Sha256 $partialPath
    $failureReceipt = [ordered]@{
        schemaVersion=2;receiptKind='gate13r-pr2-mp1-pilot-failure-receipt-v2';failedAtUtc=[DateTime]::UtcNow.ToString('o')
        status='FAILED-NO-AUTO-RETRY-NO-RESUME-NO-TOP-UP-NO-MERGE';failureClass=$Failure.Exception.GetType().FullName
        failureStage=$currentStage;failureMessage=$Failure.Exception.Message;scriptStackTrace=[string]$Failure.ScriptStackTrace
        failedGlobalProcessOrdinal=$currentOrdinal;failedBlockId=$currentBlockId;completedBlockCount=$completedBlocks;completedSampleCount=$completedBlocks*4
        partialOutputManifestRelativePath='pilot-partial-output-manifest.json';partialOutputManifestSha256=$partialSha
        validationOnly=[bool]$ValidationOnly;injectedFailureStage=$InjectedFailureStage;measuredPilotStarted=(-not $ValidationOnly)
        automaticRetryAuthorized=$false;automaticResumeAuthorized=$false;topUpAuthorized=$false;partialMergeAuthorized=$false
        formalCampaign=$false;formalAnalysisAuthorized=$false;gate14RAuthorized=$false
    }
    if (-not (Test-Path -LiteralPath $failurePath)) { Write-G13RPR2MP1V2AtomicJson -Path $failurePath -Value $failureReceipt -Depth 60 }
    $failureSha = Get-G13RPR2MP1V2Sha256 $failurePath
    if (Test-Path -LiteralPath $checkpointPath -PathType Leaf) {
        $current = Read-G13RPR2MP1V2Json $checkpointPath
        $null = Test-G13RPR2MP1V2CheckpointSchema $current
        if ([string]$current.status -notin @('PILOT-RAW-DATA-COMPLETE / ANALYSIS-PENDING / IMMUTABLE','FAILED-NO-AUTO-RETRY-NO-RESUME-NO-TOP-UP-NO-MERGE')) {
            $arguments = @{
                CompletedBlockCount=$completedBlocks;CurrentGlobalProcessOrdinal=$currentOrdinal;CurrentBlockId=$currentBlockId
                FailureClass=$Failure.Exception.GetType().FullName;FailureStage=$currentStage;FailureMessage=$Failure.Exception.Message
                FailureReceiptRelativePath='pilot-failure-receipt.json';FailureReceiptSha256=$failureSha
                PartialOutputManifestRelativePath='pilot-partial-output-manifest.json';PartialOutputManifestSha256=$partialSha
            }
            $null = Write-G13RPR2MP1V2CheckpointTransition -Path $checkpointPath -Status 'FAILED-NO-AUTO-RETRY-NO-RESUME-NO-TOP-UP-NO-MERGE' -TransitionArguments $arguments
        }
    }
}

try {
    foreach ($path in @($ExecutionReceiptPath,$ConfigPath,$SchedulePath,$ProvenancePath,$wrapperPath,$commandPath,$specificationPath,$testDesignPath,$twoStagePath,$stateAmendmentPath,$checkpointPath)) {
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Required MP1 v2 input is missing: $path" }
    }
    if (-not $ValidationOnly -and -not (Test-Path -LiteralPath $UnityPath -PathType Leaf)) { throw "Unity executable is missing: $UnityPath" }
    if (-not (Test-Path -LiteralPath $rawRoot -PathType Container)) { throw 'Committed MP1 v2 raw root is missing.' }
    $receipt = Read-G13RPR2MP1V2Json $ExecutionReceiptPath
    $config = Read-G13RPR2MP1V2Json $ConfigPath
    $checkpoint = Read-G13RPR2MP1V2Json $checkpointPath
    $null = Test-G13RPR2MP1V2CheckpointSchema $checkpoint
    $expectedReceiptKind = if ($ValidationOnly) { 'gate13r-pr2-mp1-orchestrator-validation-receipt-v2' } else { 'gate13r-pr2-mp1-targeted-memory-pilot-execution-receipt-v2' }
    if ([string]$receipt.receiptKind -ne $expectedReceiptKind -or $receipt.formalCampaignAuthorized -ne $false) { throw 'MP1 v2 execution receipt identity mismatch.' }
    if (-not $ValidationOnly -and ($receipt.measuredPilotAuthorized -ne $true -or $receipt.formalAnalysisAuthorized -ne $false -or $receipt.gate14RAuthorized -ne $false)) { throw 'MP1 v2 measured authorization boundary mismatch.' }
    if ([string]$config.configId -ne 'gate13r-pr2-mp1-targeted-memory-pilot-config-v2' -or [int]$config.matrix.measuredProcesses -ne 96 -or [int]$config.matrix.measuredSamples -ne 384 -or [int]$config.matrix.warmupProcesses -ne 0) { throw 'MP1 v2 config identity/cardinality mismatch.' }
    if ([string]$checkpoint.status -ne 'AUTHORIZED-NOT-STARTED' -or [int]$checkpoint.completedBlockCount -ne 0) { throw 'MP1 v2 acquisition is one-shot and cannot resume.' }
    if ((Get-G13RPR2MP1V2Sha256 $ConfigPath) -ne [string]$receipt.configSha256 -or (Get-G13RPR2MP1V2Sha256 $SchedulePath) -ne [string]$receipt.scheduleSha256 -or (Get-G13RPR2MP1V2Sha256 $ProvenancePath) -ne [string]$receipt.provenanceSha256) { throw 'MP1 v2 receipt/input SHA-256 mismatch.' }
    if ((Get-G13RPR2MP1V2Sha256 $SchedulePath) -ne [string]$config.schedule.sha256) { throw 'MP1 v2 config/schedule SHA-256 mismatch.' }
    if (@(Get-ChildItem -LiteralPath $rawRoot -Force).Count -ne 0) { throw 'MP1 v2 raw root must be empty at measured start.' }
    if (@(Get-Process -Name Unity -ErrorAction SilentlyContinue).Count -gt 0 -or (Test-Path -LiteralPath (Join-Path $ProjectPath 'Temp\UnityLockfile'))) { throw 'Unity must be quiescent at MP1 v2 start.' }
    if (Test-Path -LiteralPath (Join-Path $ProjectPath 'Research\FormalRuns\Gate13R_RQAligned_S48H48\v3')) { throw 'Formal attempt-3 root must remain absent.' }
    if (Test-Path -LiteralPath (Join-Path $ProjectPath 'Research\Gate13R_PR2_Formal_Execution_Receipt.v3.json')) { throw 'Formal attempt-3 receipt must remain absent.' }

    $schedule = @(Get-Content -LiteralPath $SchedulePath -Encoding UTF8 | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | ForEach-Object { $_ | ConvertFrom-Json })
    if ($schedule.Count -ne 96 -or @($schedule | Where-Object { $_.measured -ne $true -or $_.warmup -ne $false }).Count -ne 0) { throw 'MP1 v2 schedule measured/warm-up boundary mismatch.' }
    for ($i=0;$i -lt $schedule.Count;$i++) { if ([int]$schedule[$i].globalProcessOrdinal -ne $i+1) { throw 'MP1 v2 schedule ordinals are not contiguous.' } }

    $currentStage = 'CHECKPOINT-START-TRANSITION'
    $null = Write-G13RPR2MP1V2CheckpointTransition -Path $checkpointPath -Status 'MEASURED-ACQUISITION-RUNNING'
    $currentStage = 'BEFORE-FIRST-BLOCK'
    if ($InjectedFailureStage -eq 'BeforeFirstBlock') { throw 'SYNTHETIC-ZERO-BLOCK-INJECTED-FAILURE' }
    if ($ValidationOnly) {
        if ($InjectedFailureStage -eq 'AfterLastBlockBeforeRawFreeze') {
            $completedBlocks=96;$currentOrdinal=96;$currentBlockId='synthetic-block-096'
            $null = Write-G13RPR2MP1V2CheckpointTransition -Path $checkpointPath -Status 'BLOCK-PROGRESS' -TransitionArguments @{CompletedBlockCount=96;CurrentGlobalProcessOrdinal=96;CurrentBlockId=$currentBlockId}
            $null = Write-G13RPR2MP1V2CheckpointTransition -Path $checkpointPath -Status 'PHASE-A-COMMIT-IN-PROGRESS' -TransitionArguments @{CompletedBlockCount=96;CurrentGlobalProcessOrdinal=96;CurrentBlockId=$currentBlockId}
            $currentStage='AFTER-LAST-BLOCK-BEFORE-RAW-FREEZE'
            throw 'SYNTHETIC-PRE-FREEZE-INJECTED-FAILURE'
        }
        throw 'Validation-only orchestration reached an unregistered path.'
    }

    $plansRoot = Join-Path $rawRoot 'plans'
    $blocksRoot = Join-Path $rawRoot 'blocks'
    New-Item -ItemType Directory -Path $plansRoot,$blocksRoot -Force | Out-Null
    $powershellExe = 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe'
    foreach ($row in $schedule) {
        $currentOrdinal = [int]$row.globalProcessOrdinal
        $currentBlockId = [string]$row.blockId
        $currentStage = 'BLOCK-PLAN-CREATE'
        $blockPlanPath = Join-Path $plansRoot ($currentBlockId + '.json')
        $blockOutput = [IO.Path]::GetFullPath((Join-Path $rawRoot ([string]$row.outputRelativePath).Replace('/','\')))
        $plan = [ordered]@{
            schemaVersion=2;planId='gate13r-pr2-mp1-block-plan-v1';designId='gate13r-pr2-mp1-stage-separated-memory-targeted-pilot-v1'
            globalProcessOrdinal=$currentOrdinal;blockId=$currentBlockId;campaignId=[string]$row.campaignId;scenarioId=[string]$row.scenarioId
            scenarioRelativePath=[string]$row.scenarioRelativePath;scenarioSourceSha256=[string]$row.scenarioSourceSha256
            comparisonCohortId=[string]$row.comparisonCohortId;block=[int]$row.blockOrdinalWithinScenario;williamsRowIndex=[int]$row.williamsRowIndex
            formalCampaign=$false;validationOnly=$false;excludedFromFormalAnalysis=$true;analysisRole='memory-diagnostic-only';verificationInjectedFailurePosition=0
            formalConfigRelativePath='Research/Gate13R_PR2_MP1_Pilot_Config.v2.json';formalConfigSha256=Get-G13RPR2MP1V2Sha256 $ConfigPath
            specificationRelativePath='Research/Gate13R_PR2_MP1_Specification.v1.md';specificationSha256=Get-G13RPR2MP1V2Sha256 $specificationPath
            testDesignRelativePath='Research/Gate13R_PR2_MP1_v2_Test_Design.v1.md';testDesignSha256=Get-G13RPR2MP1V2Sha256 $testDesignPath
            amendmentRelativePath='Research/Gate13R_PR2_MP1_Two_Phase_Commit_Contract.v1.json';amendmentSha256=Get-G13RPR2MP1V2Sha256 $twoStagePath
            orchestrationAmendmentRelativePath='Research/Gate13R_PR2_MP1_v2_Checkpoint_StateMachine_Amendment.v1.md';orchestrationAmendmentSha256=Get-G13RPR2MP1V2Sha256 $stateAmendmentPath
            commandRelativePath='Assets/_Scripts/Research/Editor/Gate13RPR2MemoryPolicyPilotBatchCommandV1.cs';commandSha256=Get-G13RPR2MP1V2Sha256 $commandPath
            provenanceRelativePath='Research/Gate13R_PR2_MP1_Provenance.v2_4.json';provenanceSha256=Get-G13RPR2MP1V2Sha256 $ProvenancePath
            executionReceiptRelativePath='Research/PilotRuns/Gate13R_PR2_MemoryPolicy/v2/pilot-execution-receipt.json';executionReceiptSha256=Get-G13RPR2MP1V2Sha256 $ExecutionReceiptPath
            entries=@($row.entries)
        }
        Write-G13RPR2MP1V2AtomicJson -Path $blockPlanPath -Value $plan -Depth 50
        $currentStage = 'BLOCK-EXECUTION'
        & $powershellExe -NoProfile -ExecutionPolicy Bypass -File $wrapperPath -ProjectPath $ProjectPath -BlockPlanPath $blockPlanPath -OutputDirectory $blockOutput -AllowedRoot $rawRoot -ExecutionReceiptPath $ExecutionReceiptPath -UnityPath $UnityPath -TimeoutSeconds $BlockTimeoutSeconds
        $exit = $LASTEXITCODE
        if ($exit -ne 0) { throw "MP1 v2 measured block failed at global ordinal $currentOrdinal with wrapper exit $exit." }
        $completedBlocks++
        $currentStage = 'BLOCK-CHECKPOINT-COMMIT'
        $null = Write-G13RPR2MP1V2CheckpointTransition -Path $checkpointPath -Status 'BLOCK-PROGRESS' -TransitionArguments @{CompletedBlockCount=$completedBlocks;CurrentGlobalProcessOrdinal=$currentOrdinal;CurrentBlockId=$currentBlockId}
    }

    $currentStage = 'PHASE-A-COMMIT-START'
    $null = Write-G13RPR2MP1V2CheckpointTransition -Path $checkpointPath -Status 'PHASE-A-COMMIT-IN-PROGRESS' -TransitionArguments @{CompletedBlockCount=96;CurrentGlobalProcessOrdinal=96;CurrentBlockId=$currentBlockId}
    if ($InjectedFailureStage -eq 'AfterLastBlockBeforeRawFreeze') { $currentStage='AFTER-LAST-BLOCK-BEFORE-RAW-FREEZE';throw 'SYNTHETIC-PRE-FREEZE-INJECTED-FAILURE' }

    $currentStage = 'ENVIRONMENT-END-SNAPSHOT'
    $environmentEndPath = Join-Path $PilotRoot 'pilot-environment-end-snapshot.json'
    $os = Get-CimInstance Win32_OperatingSystem
    $environmentEnd = [ordered]@{
        schemaVersion=2;snapshotKind='gate13r-pr2-mp1-environment-end-v2';capturedAtUtc=[DateTime]::UtcNow.ToString('o')
        unityProcessCount=@(Get-Process -Name Unity -ErrorAction SilentlyContinue).Count;projectLockExists=Test-Path -LiteralPath (Join-Path $ProjectPath 'Temp\UnityLockfile')
        availablePhysicalMemoryBytes=[long]$os.FreePhysicalMemory*1024L;totalVisibleMemoryBytes=[long]$os.TotalVisibleMemorySize*1024L
        hDriveFreeBytes=[long](Get-PSDrive -Name H).Free;powerScheme=(& powercfg.exe /getactivescheme 2>&1 | Out-String).Trim()
    }
    Write-G13RPR2MP1V2AtomicJson -Path $environmentEndPath -Value $environmentEnd -Depth 30
    if ($environmentEnd.unityProcessCount -ne 0 -or $environmentEnd.projectLockExists) { throw 'End-of-acquisition Unity quiescence failed before raw commit.' }

    $currentStage = 'PHASE-A-RAW-FREEZE'
    $freezeScript = Join-Path $ProjectPath 'Research\Freeze-Gate13RPR2MemoryPolicyPilotRawV2.py'
    $freezeOutput = & py -3 $freezeScript --pilot-root $PilotRoot --raw-root $rawRoot --schedule $SchedulePath --config $ConfigPath --receipt $ExecutionReceiptPath --environment-end $environmentEndPath
    if ($LASTEXITCODE -ne 0) { throw 'MP1 v2 raw freeze failed; measured data will not be rerun automatically.' }
    $freezeResult = $freezeOutput | ConvertFrom-Json
    if ($freezeResult.passed -ne $true) { throw 'MP1 v2 raw freeze did not report passed.' }

    $currentStage = 'RAW-COMPLETE-CHECKPOINT-COMMIT'
    $treeManifestPath = Join-Path $PilotRoot 'pilot-raw-tree-manifest.json'
    $null = Write-G13RPR2MP1V2CheckpointTransition -Path $checkpointPath -Status 'PILOT-RAW-DATA-COMPLETE / ANALYSIS-PENDING / IMMUTABLE' -TransitionArguments @{
        CompletedBlockCount=96;CurrentGlobalProcessOrdinal=96;CurrentBlockId=$currentBlockId;RawTreeSha256=[string]$freezeResult.rawTreeSha256
        RawManifestRelativePath='pilot-raw-tree-manifest.json';RawManifestSha256=Get-G13RPR2MP1V2Sha256 $treeManifestPath
        EnvironmentEndSnapshotRelativePath='pilot-environment-end-snapshot.json';EnvironmentEndSnapshotSha256=Get-G13RPR2MP1V2Sha256 $environmentEndPath
    }
    Write-Host "Gate13R-PR2-MP1 v2 raw acquisition committed: $($freezeResult.rawTreeSha256)" -ForegroundColor Green
    exit 0
}
catch {
    $original = $_
    try { Save-V2FailureEvidence -Failure $original }
    catch { Write-Error ("MP1 v2 failure-evidence persistence also failed: " + $_.Exception.Message) }
    Write-Error ("Gate13R-PR2-MP1 v2 stopped fail-closed at " + $currentStage + ": " + $original.Exception.Message)
    exit 1
}
