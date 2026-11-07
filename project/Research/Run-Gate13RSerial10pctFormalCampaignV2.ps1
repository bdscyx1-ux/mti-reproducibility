[CmdletBinding(DefaultParameterSetName = 'ValidationOnly')]
param(
    [Parameter(Mandatory = $true)][string]$ProjectPath,
    [Parameter(Mandatory = $true)][string]$ConfigPath,
    [Parameter(Mandatory = $true)][string]$ProvenancePath,
    [Parameter(Mandatory = $true)][string]$SchedulePath,
    [Parameter(Mandatory = $true)][string]$ScheduleManifestPath,
    [Parameter(Mandatory = $true)][string]$ValidationRoot,
    [Parameter(Mandatory = $true, ParameterSetName = 'ValidationOnly')][switch]$ValidationOnly,
    [Parameter(Mandatory = $true, ParameterSetName = 'Execute')][switch]$Execute,
    [Parameter(Mandatory = $true, ParameterSetName = 'Execute')][string]$ExecutionReceiptPath,
    [string]$UnityPath = 'H:\UnityEditor\2022.3.30f1c1\Editor\Unity.exe',
    [switch]$BindingSmokeOnly,
    [int]$BlockTimeoutSeconds = 3600
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if ([string]::IsNullOrWhiteSpace($ProjectPath) -or -not [IO.Path]::IsPathRooted($ProjectPath)) { throw 'Gate13R serial 10pct formal orchestrator requires an explicit absolute ProjectPath.' }
$ProjectPath = [IO.Path]::GetFullPath($ProjectPath)
if ($BindingSmokeOnly) { Write-Output "BINDING-SMOKE-PASSED|Run-Gate13RSerial10pctFormalCampaignV2|$ProjectPath|$($PSCmdlet.ParameterSetName)"; exit 0 }
Import-Module (Join-Path $ProjectPath 'Research\Gate13RSerial10pctFormalPreparationV2.psm1') -Force

$ConfigPath = [IO.Path]::GetFullPath($ConfigPath)
$ProvenancePath = [IO.Path]::GetFullPath($ProvenancePath)
$SchedulePath = [IO.Path]::GetFullPath($SchedulePath)
$ScheduleManifestPath = [IO.Path]::GetFullPath($ScheduleManifestPath)
$ValidationRoot = [IO.Path]::GetFullPath($ValidationRoot)
$UnityPath = [IO.Path]::GetFullPath($UnityPath)
$formalRoot = [IO.Path]::GetFullPath((Join-Path $ProjectPath 'Research\FormalRuns\Gate13R_Serial_10pct\v2')).TrimEnd('\', '/')
$verificationBase = [IO.Path]::GetFullPath((Join-Path $ProjectPath 'Research\Verification\Gate13R_Serial_10pct'))
if (-not (Test-G13RPathWithin -BasePath $verificationBase -CandidatePath $ValidationRoot)) { throw 'ValidationRoot is outside the Gate13R versioned verification base.' }
if (-not (Test-Path -LiteralPath $ValidationRoot -PathType Container)) { New-Item -ItemType Directory -Path $ValidationRoot -Force | Out-Null }
if (-not (Test-Path -LiteralPath $UnityPath -PathType Leaf)) { throw 'Unity executable is missing.' }
if (Test-Path -LiteralPath $formalRoot) { throw 'Gate13R reserved formal root must be absent at orchestrator entry; retry/resume is forbidden.' }
if (@(Get-Process -Name Unity -ErrorAction SilentlyContinue).Count -gt 0) { throw 'Unity must be closed before Gate13R orchestration.' }
if (Test-Path -LiteralPath (Join-Path $ProjectPath 'Temp\UnityLockfile')) { throw 'Unity project lock must be absent before Gate13R orchestration.' }

$config = Read-G13RJson $ConfigPath
$provenance = Read-G13RJson $ProvenancePath
if ([string]$config.configKind -ne 'gate13r-strict-serial-10pct-formal-campaign-config-v2' -or $config.formalExecutionAuthorized -ne $false -or $config.formalRootCreated -ne $false) { throw 'Gate13R serial config authorization boundary is invalid.' }
if ([string]$config.formalRoot.relativePath -ne 'Research/FormalRuns/Gate13R_Serial_10pct/v2' -or -not ([IO.Path]::GetFullPath((Join-Path $ProjectPath ([string]$config.formalRoot.relativePath).Replace('/', '\'))).TrimEnd('\', '/').Equals($formalRoot, [StringComparison]::OrdinalIgnoreCase))) { throw 'Gate13R serial config formal-root identity mismatch.' }
if ([int]$config.processSemantics.maximumConcurrentUnityEditorProcesses -ne 1 -or [int]$config.processSemantics.laneCount -ne 1 -or $config.processSemantics.parallelFallbackAllowed -ne $false) { throw 'Gate13R serial topology contract is invalid.' }
if ([string]$provenance.formalConfig.sha256 -ne (Get-G13RLowerSha256 $ConfigPath)) { throw 'Gate13R provenance/config hash mismatch.' }

$scheduleValidationSummary = Join-Path $ValidationRoot 'ScheduleValidation.summary.json'
if (Test-Path -LiteralPath $scheduleValidationSummary) { throw 'Create-new schedule validation summary already exists.' }
$validator = Join-Path $ProjectPath 'Research\Test-Gate13RSerial10pctFormalScheduleV2.ps1'
& $validator -ProjectPath $ProjectPath -ConfigPath $ConfigPath -ProvenancePath $ProvenancePath -SchedulePath $SchedulePath -ScheduleManifestPath $ScheduleManifestPath -SummaryPath $scheduleValidationSummary
if ($LASTEXITCODE -ne 0) { throw "Gate13R schedule validator failed with exit code $LASTEXITCODE." }
$scheduleCheck = Read-G13RJson $scheduleValidationSummary
if ($scheduleCheck.passed -ne $true -or [int]$scheduleCheck.blockRecordCount -ne 11160 -or [int]$scheduleCheck.sampleIdentityCount -ne 31536) { throw 'Gate13R serial full schedule validation summary is invalid.' }

if ($ValidationOnly) {
    $driveRoot = [IO.Path]::GetPathRoot($formalRoot)
    $drive = New-Object IO.DriveInfo($driveRoot)
    $storageSnapshot = Test-G13RStorageGate -AvailableFreeBytes ([long]$drive.AvailableFreeSpace) -MinimumLaunchFreeBytes 86835248752 -ExpectedVolumeRoot $formalRoot -ObservedVolumeRoot $driveRoot -CheckedAtUtc ([DateTime]::UtcNow) -OriginalByteCount
    if ($storageSnapshot.passed -ne $true) { throw ('Gate13R serial validation-only storage preflight failed: ' + (@($storageSnapshot.errors) -join ', ')) }
    $summary = [ordered]@{
        schemaVersion = 1
        summaryKind = 'gate13r-serial-10pct-nonexecuting-orchestrator-validation-summary-v2'
        savedAtUtc = [DateTime]::UtcNow.ToString('o')
        configSha256 = Get-G13RLowerSha256 $ConfigPath
        provenanceSha256 = Get-G13RLowerSha256 $ProvenancePath
        scheduleSha256 = Get-G13RLowerSha256 $SchedulePath
        scheduleManifestSha256 = Get-G13RLowerSha256 $ScheduleManifestPath
        scheduleValidationSha256 = Get-G13RLowerSha256 $scheduleValidationSummary
        scheduleBlockCount = [int]$scheduleCheck.blockRecordCount
        scheduleSampleCount = [int]$scheduleCheck.sampleIdentityCount
        currentStorageSnapshot = $storageSnapshot
        currentStorageSnapshotAuthorizing = $false
        unityProcessCount = 0
        unityLockPresent = $false
        formalRootExists = $false
        formalExecutionReceiptCreated = $false
        formalCampaignExecuted = $false
        status = 'VALIDATION-ONLY-PASSED-FORMAL-NOT-AUTHORIZED'
        passed = $true
    }
    $summaryPath = Join-Path $ValidationRoot 'OrchestratorValidation.summary.json'
    Write-G13RAtomicUtf8NoBomJson -Path $summaryPath -Value $summary -Depth 30
    Write-Host 'Gate13R serial 10pct orchestrator validation-only passed; no formal root or timing sample was created.' -ForegroundColor Green
    exit 0
}

if (-not $Execute) { throw 'Choose exactly one orchestrator mode.' }
$ExecutionReceiptPath = [IO.Path]::GetFullPath($ExecutionReceiptPath)
if (-not (Test-Path -LiteralPath $ExecutionReceiptPath -PathType Leaf)) { throw 'A separately authorized formal execution receipt is required.' }
$receipt = Read-G13RJson $ExecutionReceiptPath
$receiptCheck = Test-G13RFormalExecutionReceipt -Receipt $receipt -ExpectedFormalRoot $formalRoot -ExpectedConfigSha256 (Get-G13RLowerSha256 $ConfigPath) -ExpectedAmendmentSha256 ([string]$config.bindings.amendmentSha256) -ExpectedProvenanceSha256 (Get-G13RLowerSha256 $ProvenancePath) -ExpectedScheduleManifestSha256 (Get-G13RLowerSha256 $ScheduleManifestPath) -ExpectedOrchestratorSha256 (Get-G13RLowerSha256 $PSCommandPath) -ExpectedUnityCommandSha256 ([string]$config.implementation.unityCommandSha256)
if ($receiptCheck.passed -ne $true) { throw ('Gate13R formal execution receipt rejected: ' + (@($receiptCheck.errors) -join ', ')) }
$driveRoot = [IO.Path]::GetPathRoot($formalRoot)
$drive = New-Object IO.DriveInfo($driveRoot)
$freshStorage = Test-G13RStorageGate -AvailableFreeBytes ([long]$drive.AvailableFreeSpace) -MinimumLaunchFreeBytes 86835248752 -ExpectedVolumeRoot $formalRoot -ObservedVolumeRoot $driveRoot -CheckedAtUtc ([DateTime]::UtcNow) -OriginalByteCount -LaunchContext
if ($freshStorage.passed -ne $true) { throw ('Fresh launch storage preflight failed: ' + (@($freshStorage.errors) -join ', ')) }
if (Test-Path -LiteralPath $formalRoot) { throw 'Formal root appeared during preflight; refusing to continue.' }

New-Item -ItemType Directory -Path $formalRoot | Out-Null
$plansRoot = Join-Path $formalRoot '_plans'
New-Item -ItemType Directory -Path $plansRoot | Out-Null
$rootCheckpointPath = Join-Path $formalRoot 'formal-checkpoint.json'
$completedBlocks = 0
$completedSamples = 0
$currentBlockId = $null
function Write-G13RRootCheckpoint([string]$Status, [string]$ErrorMessage) {
    $checkpoint = [ordered]@{
        schemaVersion = 1
        checkpointKind = 'gate13r-formal-campaign-root-checkpoint-v1'
        savedAtUtc = [DateTime]::UtcNow.ToString('o')
        status = $Status
        configSha256 = Get-G13RLowerSha256 $ConfigPath
        executionReceiptSha256 = Get-G13RLowerSha256 $ExecutionReceiptPath
        completedBlockCount = $script:completedBlocks
        completedSampleCount = $script:completedSamples
        currentBlockId = $script:currentBlockId
        automaticRetryAttempted = $false
        automaticResumeAttempted = $false
        error = $ErrorMessage
    }
    Write-G13RAtomicUtf8NoBomJson -Path $rootCheckpointPath -Value $checkpoint -Depth 20
}

Write-G13RRootCheckpoint -Status 'preflight-passed-before-first-block' -ErrorMessage $null
$blockWrapper = Join-Path $ProjectPath 'Research\Run-Gate13RSerial10pctFormalBlockV2.ps1'
$receiptRelative = Get-G13RProjectRelativePath -ProjectPath $ProjectPath -Path $ExecutionReceiptPath
$receiptSha256 = Get-G13RLowerSha256 $ExecutionReceiptPath
try {
    foreach ($line in [IO.File]::ReadLines($SchedulePath, [Text.Encoding]::UTF8)) {
        $record = $line | ConvertFrom-Json
        $currentBlockId = [string]$record.blockId
        Write-G13RRootCheckpoint -Status 'before-block' -ErrorMessage $null
        $plan = New-G13RBlockPlanFromScheduleRecord -ScheduleRecord $record -FormalConfigRelativePath (Get-G13RProjectRelativePath -ProjectPath $ProjectPath -Path $ConfigPath) -FormalConfigSha256 (Get-G13RLowerSha256 $ConfigPath) -SpecificationRelativePath ([string]$config.bindings.specificationRelativePath) -SpecificationSha256 ([string]$config.bindings.specificationSha256) -TestDesignRelativePath ([string]$config.bindings.testDesignRelativePath) -TestDesignSha256 ([string]$config.bindings.testDesignSha256) -AmendmentRelativePath ([string]$config.bindings.amendmentRelativePath) -AmendmentSha256 ([string]$config.bindings.amendmentSha256) -CommandRelativePath ([string]$config.implementation.unityCommandRelativePath) -CommandSha256 ([string]$config.implementation.unityCommandSha256) -ProvenanceRelativePath (Get-G13RProjectRelativePath -ProjectPath $ProjectPath -Path $ProvenancePath) -ProvenanceSha256 (Get-G13RLowerSha256 $ProvenancePath) -ExecutionReceiptRelativePath $receiptRelative -ExecutionReceiptSha256 $receiptSha256
        $planPath = Join-Path $plansRoot ($currentBlockId + '.plan.json')
        Write-G13RUtf8NoBomJson -Path $planPath -Value $plan -Depth 30
        $outputDirectory = [IO.Path]::GetFullPath((Join-Path $formalRoot ([string]$record.outputRelativePath).Replace('/', '\')))
        & $blockWrapper -ProjectPath $ProjectPath -BlockPlanPath $planPath -OutputDirectory $outputDirectory -AllowedRoot $formalRoot -ExecutionReceiptPath $ExecutionReceiptPath -UnityPath $UnityPath -TimeoutSeconds $BlockTimeoutSeconds
        if ($LASTEXITCODE -ne 0) { throw "Formal block wrapper failed: $currentBlockId exit=$LASTEXITCODE" }
        $completedBlocks++
        $completedSamples += [int]$record.expectedSampleCount
        Write-G13RRootCheckpoint -Status 'block-completed' -ErrorMessage $null
    }
    if ($completedBlocks -ne 11160 -or $completedSamples -ne 31536) { throw 'Serial formal terminal cardinality mismatch.' }
    Write-G13RRootCheckpoint -Status 'formal-campaign-completed' -ErrorMessage $null
}
catch {
    $message = $_.Exception.ToString()
    Write-G13RRootCheckpoint -Status 'failed-no-auto-retry-no-resume' -ErrorMessage $message
    $partial = [ordered]@{
        schemaVersion = 1
        manifestKind = 'gate13r-formal-partial-output-manifest-v1'
        savedAtUtc = [DateTime]::UtcNow.ToString('o')
        completedBlockCount = $completedBlocks
        completedSampleCount = $completedSamples
        failedBlockId = $currentBlockId
        checkpointSha256 = Get-G13RLowerSha256 $rootCheckpointPath
        automaticRetryAttempted = $false
        automaticResumeAttempted = $false
        excludedUntilComplete = $true
        error = $message
    }
    Write-G13RAtomicUtf8NoBomJson -Path (Join-Path $formalRoot 'partial-output-manifest.json') -Value $partial -Depth 20
    Write-Error 'Gate13R formal campaign failed closed; retry and resume are forbidden.'
    exit 1
}

Write-Host 'Gate13R strict-serial 10pct formal campaign completed.' -ForegroundColor Green
exit 0
