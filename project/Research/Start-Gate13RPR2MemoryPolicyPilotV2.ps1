[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$ProjectPath,
    [string]$UnityPath = 'H:\UnityEditor\2022.3.30f1c1\Editor\Unity.exe',
    [int]$BlockTimeoutSeconds = 3600,
    [switch]$BindingSmokeOnly
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if ([string]::IsNullOrWhiteSpace($ProjectPath) -or -not [IO.Path]::IsPathRooted($ProjectPath)) { throw 'An explicit absolute ProjectPath is required.' }
$ProjectPath = [IO.Path]::GetFullPath($ProjectPath)
if ($BindingSmokeOnly) { Write-Output "BINDING-SMOKE-PASSED|Start-Gate13RPR2MemoryPolicyPilotV2|$ProjectPath"; exit 0 }
Import-Module (Join-Path $ProjectPath 'Research\Gate13RPR2MemoryPolicyPilotV2.psm1') -Force

$pilotRoot = [IO.Path]::GetFullPath((Join-Path $ProjectPath 'Research\PilotRuns\Gate13R_PR2_MemoryPolicy\v2'))
$rawRoot = Join-Path $pilotRoot 'raw'
$receiptPath = Join-Path $pilotRoot 'pilot-execution-receipt.json'
$checkpointPath = Join-Path $pilotRoot 'pilot-checkpoint.json'
$configPath = Join-Path $ProjectPath 'Research\Gate13R_PR2_MP1_Pilot_Config.v2.json'
$schedulePath = Join-Path $ProjectPath 'Research\Gate13R_PR2_MP1_Pilot_Schedule.v1.jsonl'
$manifestPath = Join-Path $ProjectPath 'Research\Gate13R_PR2_MP1_Pilot_Schedule_Manifest.v1.json'
$provenancePath = Join-Path $ProjectPath 'Research\Gate13R_PR2_MP1_Provenance.v2_4.json'
$prePilotPath = Join-Path $ProjectPath 'Research\Gate13R_PR2_MP1_PrePilot_Readiness_Checkpoint.v2.json'
$authorizationPath = Join-Path $ProjectPath 'Research\Gate13R_PR2_MP1_v2_Authorization.v1.json'
$promptPath = Join-Path $ProjectPath 'Research\Gate13R_PR2_MP1_Attempt2_Next_Authorization_Prompt.md'
$campaignPath = Join-Path $ProjectPath 'Research\Run-Gate13RPR2MemoryPolicyPilotV2.ps1'
$stateModulePath = Join-Path $ProjectPath 'Research\Gate13RPR2MemoryPolicyPilotV2.psm1'
$stateAmendmentPath = Join-Path $ProjectPath 'Research\Gate13R_PR2_MP1_v2_Checkpoint_StateMachine_Amendment.v1.md'
$UnityPath = [IO.Path]::GetFullPath($UnityPath)
foreach ($path in @($configPath,$schedulePath,$manifestPath,$provenancePath,$prePilotPath,$authorizationPath,$promptPath,$campaignPath,$stateModulePath,$stateAmendmentPath,$UnityPath)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Required v2 launch input missing: $path" }
}
if (Test-Path -LiteralPath $pilotRoot) { throw 'The one-shot MP1 v2 pilot root already exists; retry/resume/top-up/merge is not authorized.' }
if (@(Get-Process -Name Unity -ErrorAction SilentlyContinue).Count -gt 0 -or (Test-Path -LiteralPath (Join-Path $ProjectPath 'Temp\UnityLockfile'))) { throw 'Unity must be quiescent and the project lock absent before MP1 v2 launch.' }
if ((Test-Path -LiteralPath (Join-Path $ProjectPath 'Research\FormalRuns\Gate13R_RQAligned_S48H48\v3')) -or (Test-Path -LiteralPath (Join-Path $ProjectPath 'Research\Gate13R_PR2_Formal_Execution_Receipt.v3.json'))) { throw 'Formal attempt 3 must remain absent.' }
$prePilot = Read-G13RPR2MP1V2Json $prePilotPath
if ($prePilot.passed -ne $true -or [string]$prePilot.status -ne 'PRE-PILOT-VALIDATED / MEASURED-PILOT-V2-AUTHORIZED-BUT-NOT-STARTED') { throw 'MP1 v2 pre-pilot readiness checkpoint is not passed.' }
$config = Read-G13RPR2MP1V2Json $configPath
$manifest = Read-G13RPR2MP1V2Json $manifestPath
if ([string]$config.configId -ne 'gate13r-pr2-mp1-targeted-memory-pilot-config-v2' -or [int]$config.matrix.measuredProcesses -ne 96 -or [int]$config.matrix.measuredSamples -ne 384 -or [int]$manifest.measuredProcessCount -ne 96 -or [int]$manifest.measuredSampleCount -ne 384) { throw 'Frozen v2 pilot cardinality mismatch.' }
if ([long](Get-PSDrive -Name H).Free -lt 42949672960L) { throw 'MP1 v2 launch requires at least 40 GiB free on H:.' }

$rootCreated = $false
try {
    New-Item -ItemType Directory -Path $rawRoot -Force | Out-Null
    $rootCreated = $true
    $receipt = [ordered]@{
        schemaVersion=2;receiptKind='gate13r-pr2-mp1-targeted-memory-pilot-execution-receipt-v2';createdAtUtc=[DateTime]::UtcNow.ToString('o')
        attemptId='gate13r-pr2-mp1-attempt2-v2';pilotRoot=$pilotRoot;rawRoot=$rawRoot
        configSha256=Get-G13RPR2MP1V2Sha256 $configPath;scheduleSha256=Get-G13RPR2MP1V2Sha256 $schedulePath
        scheduleManifestSha256=Get-G13RPR2MP1V2Sha256 $manifestPath;provenanceSha256=Get-G13RPR2MP1V2Sha256 $provenancePath
        prePilotReadinessSha256=Get-G13RPR2MP1V2Sha256 $prePilotPath;authorizationSha256=Get-G13RPR2MP1V2Sha256 $authorizationPath
        authorizationPromptSha256=Get-G13RPR2MP1V2Sha256 $promptPath;checkpointModuleSha256=Get-G13RPR2MP1V2Sha256 $stateModulePath
        checkpointAmendmentSha256=Get-G13RPR2MP1V2Sha256 $stateAmendmentPath
        measuredProcessCount=96;measuredSampleCount=384;warmupProcessCount=0;measuredPilotAuthorized=$true
        formalCampaignAuthorized=$false;formalAnalysisAuthorized=$false;gate14RAuthorized=$false
        automaticRetryAuthorized=$false;automaticResumeAuthorized=$false;topUpAuthorized=$false;partialMergeAuthorized=$false
        labels=@('NON-FORMAL','MEMORY-DIAGNOSTIC-ONLY','EXCLUDED-FROM-FORMAL-ANALYSIS','NOT-ALGORITHM-SUPERIORITY-EVIDENCE')
        status='PILOT-V2-EXECUTION-AUTHORIZED'
    }
    Write-G13RPR2MP1V2AtomicJson -Path $receiptPath -Value $receipt -Depth 50
    Write-G13RPR2MP1V2AtomicJson -Path $checkpointPath -Value (New-G13RPR2MP1V2Checkpoint) -Depth 50

    $powershellExe = 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe'
    $expectedNativeModulePath = @('C:\Users\bdscy\Documents\WindowsPowerShell\Modules','C:\Program Files\WindowsPowerShell\Modules','C:\WINDOWS\System32\WindowsPowerShell\v1.0\Modules') -join ';'
    $previousModulePath = $env:PSModulePath
    try {
        $env:PSModulePath = $expectedNativeModulePath
        & $powershellExe -NoProfile -ExecutionPolicy Bypass -File $campaignPath -ProjectPath $ProjectPath -PilotRoot $pilotRoot -ExecutionReceiptPath $receiptPath -ConfigPath $configPath -SchedulePath $schedulePath -ProvenancePath $provenancePath -UnityPath $UnityPath -BlockTimeoutSeconds $BlockTimeoutSeconds
        $exit = $LASTEXITCODE
    }
    finally { $env:PSModulePath = $previousModulePath }
    if ($exit -ne 0) { throw "Gate13R-PR2-MP1 v2 measured pilot terminated fail-closed with exit code $exit; no automatic retry/resume/top-up/merge is authorized." }
    $terminal = Read-G13RPR2MP1V2Json $checkpointPath
    $null = Test-G13RPR2MP1V2CheckpointSchema $terminal
    if ([string]$terminal.status -ne 'PILOT-RAW-DATA-COMPLETE / ANALYSIS-PENDING / IMMUTABLE') { throw 'MP1 v2 campaign exited zero without a committed Phase-A checkpoint.' }
    foreach ($path in @($receiptPath,$checkpointPath)) { Set-ItemProperty -LiteralPath $path -Name IsReadOnly -Value $true }
    Write-Host 'Gate13R-PR2-MP1 v2 measured raw acquisition and Phase-A commit completed.' -ForegroundColor Green
    exit 0
}
catch {
    $launchFailure = $_
    if ($rootCreated -and (Test-Path -LiteralPath $pilotRoot -PathType Container)) {
        try {
            $partialPath = Join-Path $pilotRoot 'pilot-partial-output-manifest.json'
            $failurePath = Join-Path $pilotRoot 'pilot-failure-receipt.json'
            if (-not (Test-Path -LiteralPath $partialPath)) {
                $rawFiles = @()
                if (Test-Path -LiteralPath $rawRoot) { $rawFiles = @(Get-ChildItem -LiteralPath $rawRoot -Recurse -File -Force) }
                $rawBytes = 0L
                if ($rawFiles.Count -gt 0) { $rawBytes = [long](($rawFiles|Measure-Object Length -Sum).Sum) }
                $partial = [ordered]@{schemaVersion=2;manifestKind='gate13r-pr2-mp1-launch-partial-output-manifest-v2';savedAtUtc=[DateTime]::UtcNow.ToString('o');status='FAILED-NO-AUTO-RETRY-NO-RESUME-NO-TOP-UP-NO-MERGE';fileCount=$rawFiles.Count;rawBytes=$rawBytes;completedBlockCount=0;completedSampleCount=0}
                Write-G13RPR2MP1V2AtomicJson -Path $partialPath -Value $partial -Depth 30
            }
            if (-not (Test-Path -LiteralPath $failurePath)) {
                $failure = [ordered]@{schemaVersion=2;receiptKind='gate13r-pr2-mp1-launch-failure-receipt-v2';failedAtUtc=[DateTime]::UtcNow.ToString('o');status='FAILED-NO-AUTO-RETRY-NO-RESUME-NO-TOP-UP-NO-MERGE';failureClass=$launchFailure.Exception.GetType().FullName;failureStage='LAUNCHER';failureMessage=$launchFailure.Exception.Message;partialOutputManifestSha256=Get-G13RPR2MP1V2Sha256 $partialPath;automaticRetryAuthorized=$false;automaticResumeAuthorized=$false;topUpAuthorized=$false;partialMergeAuthorized=$false;formalCampaign=$false;formalAnalysisAuthorized=$false;gate14RAuthorized=$false}
                Write-G13RPR2MP1V2AtomicJson -Path $failurePath -Value $failure -Depth 40
            }
            if (Test-Path -LiteralPath $checkpointPath -PathType Leaf) {
                $current = Read-G13RPR2MP1V2Json $checkpointPath
                if ([string]$current.status -notin @('PILOT-RAW-DATA-COMPLETE / ANALYSIS-PENDING / IMMUTABLE','FAILED-NO-AUTO-RETRY-NO-RESUME-NO-TOP-UP-NO-MERGE')) {
                    $null = Write-G13RPR2MP1V2CheckpointTransition -Path $checkpointPath -Status 'FAILED-NO-AUTO-RETRY-NO-RESUME-NO-TOP-UP-NO-MERGE' -TransitionArguments @{CompletedBlockCount=[int]$current.completedBlockCount;CurrentGlobalProcessOrdinal=[int]$current.currentGlobalProcessOrdinal;CurrentBlockId=[string]$current.currentBlockId;FailureClass=$launchFailure.Exception.GetType().FullName;FailureStage='LAUNCHER';FailureMessage=$launchFailure.Exception.Message;FailureReceiptRelativePath='pilot-failure-receipt.json';FailureReceiptSha256=Get-G13RPR2MP1V2Sha256 $failurePath;PartialOutputManifestRelativePath='pilot-partial-output-manifest.json';PartialOutputManifestSha256=Get-G13RPR2MP1V2Sha256 $partialPath}
                }
            }
            Get-ChildItem -LiteralPath $pilotRoot -Recurse -File -Force | ForEach-Object { Set-ItemProperty -LiteralPath $_.FullName -Name IsReadOnly -Value $true }
        }
        catch { Write-Error ("MP1 v2 launcher failure-evidence persistence also failed: " + $_.Exception.Message) }
    }
    throw $launchFailure
}
