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
if ($BindingSmokeOnly) { Write-Output "BINDING-SMOKE-PASSED|Start-Gate13RPR2MemoryPolicyPilotV1|$ProjectPath"; exit 0 }
Import-Module (Join-Path $ProjectPath 'Research\Gate13RPR2MemoryPolicyPilotV1.psm1') -Force

$pilotRoot = [IO.Path]::GetFullPath((Join-Path $ProjectPath 'Research\PilotRuns\Gate13R_PR2_MemoryPolicy\v1'))
$rawRoot = Join-Path $pilotRoot 'raw'
$receiptPath = Join-Path $pilotRoot 'pilot-execution-receipt.json'
$checkpointPath = Join-Path $pilotRoot 'pilot-checkpoint.json'
$configPath = Join-Path $ProjectPath 'Research\Gate13R_PR2_MP1_Pilot_Config.v1.json'
$schedulePath = Join-Path $ProjectPath 'Research\Gate13R_PR2_MP1_Pilot_Schedule.v1.jsonl'
$manifestPath = Join-Path $ProjectPath 'Research\Gate13R_PR2_MP1_Pilot_Schedule_Manifest.v1.json'
$provenancePath = Join-Path $ProjectPath 'Research\Gate13R_PR2_MP1_Provenance.v1.json'
$prePilotPath = Join-Path $ProjectPath 'Research\Gate13R_PR2_MP1_PrePilot_Readiness_Checkpoint.v1.json'
$authorizationPath = Join-Path $ProjectPath 'Research\Gate13R_PR2_MP1_Authorization.v1.json'
$campaignPath = Join-Path $ProjectPath 'Research\Run-Gate13RPR2MemoryPolicyPilotV1.ps1'
$UnityPath = [IO.Path]::GetFullPath($UnityPath)
foreach ($path in @($configPath,$schedulePath,$manifestPath,$provenancePath,$prePilotPath,$authorizationPath,$campaignPath,$UnityPath)) { if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Required pilot-launch input missing: $path" } }
if (Test-Path -LiteralPath $pilotRoot) { throw 'The one-shot MP1 pilot root already exists; retry/resume/top-up/merge is not authorized.' }
if (@(Get-Process -Name Unity -ErrorAction SilentlyContinue).Count -gt 0 -or (Test-Path -LiteralPath (Join-Path $ProjectPath 'Temp\UnityLockfile'))) { throw 'Unity must be quiescent and the project lock absent before MP1 launch.' }
if ((Test-Path -LiteralPath (Join-Path $ProjectPath 'Research\FormalRuns\Gate13R_RQAligned_S48H48\v3')) -or (Test-Path -LiteralPath (Join-Path $ProjectPath 'Research\Gate13R_PR2_Formal_Execution_Receipt.v3.json'))) { throw 'Formal attempt 3 must remain absent.' }
$prePilot = Read-G13RPR2MP1Json $prePilotPath
if ($prePilot.passed -ne $true -or [string]$prePilot.status -ne 'PRE-PILOT-VALIDATED / MEASURED-PILOT-AUTHORIZED-BUT-NOT-STARTED') { throw 'Pre-pilot readiness checkpoint is not passed.' }
$config = Read-G13RPR2MP1Json $configPath
$manifest = Read-G13RPR2MP1Json $manifestPath
if ([int]$config.matrix.measuredProcesses -ne 96 -or [int]$config.matrix.measuredSamples -ne 384 -or [int]$manifest.measuredProcessCount -ne 96 -or [int]$manifest.measuredSampleCount -ne 384) { throw 'Frozen pilot cardinality mismatch.' }
if ([long](Get-PSDrive -Name H).Free -lt 42949672960L) { throw 'MP1 launch requires at least 40 GiB free on H:.' }

New-Item -ItemType Directory -Path $rawRoot -Force | Out-Null
$receipt = [ordered]@{
    schemaVersion = 1
    receiptKind = 'gate13r-pr2-mp1-targeted-memory-pilot-execution-receipt-v1'
    createdAtUtc = [DateTime]::UtcNow.ToString('o')
    pilotRoot = $pilotRoot
    rawRoot = $rawRoot
    configSha256 = Get-G13RPR2MP1Sha256 $configPath
    scheduleSha256 = Get-G13RPR2MP1Sha256 $schedulePath
    scheduleManifestSha256 = Get-G13RPR2MP1Sha256 $manifestPath
    provenanceSha256 = Get-G13RPR2MP1Sha256 $provenancePath
    prePilotReadinessSha256 = Get-G13RPR2MP1Sha256 $prePilotPath
    authorizationSha256 = Get-G13RPR2MP1Sha256 $authorizationPath
    measuredProcessCount = 96
    measuredSampleCount = 384
    warmupProcessCount = 0
    measuredPilotAuthorized = $true
    formalCampaignAuthorized = $false
    formalAnalysisAuthorized = $false
    gate14RAuthorized = $false
    automaticRetryAuthorized = $false
    automaticResumeAuthorized = $false
    topUpAuthorized = $false
    partialMergeAuthorized = $false
    labels = @('NON-FORMAL','MEMORY-DIAGNOSTIC-ONLY','EXCLUDED-FROM-FORMAL-ANALYSIS','NOT-ALGORITHM-SUPERIORITY-EVIDENCE')
    status = 'PILOT-EXECUTION-AUTHORIZED'
}
Write-G13RPR2MP1AtomicJson -Path $receiptPath -Value $receipt -Depth 40
$checkpoint = [ordered]@{schemaVersion=1;checkpointKind='gate13r-pr2-mp1-pilot-checkpoint-v1';savedAtUtc=[DateTime]::UtcNow.ToString('o');status='AUTHORIZED-NOT-STARTED';completedBlockCount=0;expectedBlockCount=96;expectedSampleCount=384;currentGlobalProcessOrdinal=0;currentBlockId=$null;automaticRetryAuthorized=$false;automaticResumeAuthorized=$false;topUpAuthorized=$false;partialMergeAuthorized=$false;formalCampaign=$false}
Write-G13RPR2MP1AtomicJson -Path $checkpointPath -Value $checkpoint -Depth 30

$powershellExe = 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe'
$expectedNativeModulePath = @('C:\Users\bdscy\Documents\WindowsPowerShell\Modules','C:\Program Files\WindowsPowerShell\Modules','C:\WINDOWS\System32\WindowsPowerShell\v1.0\Modules') -join ';'
$previousModulePath = $env:PSModulePath
try {
    $env:PSModulePath = $expectedNativeModulePath
    & $powershellExe -NoProfile -ExecutionPolicy Bypass -File $campaignPath -ProjectPath $ProjectPath -PilotRoot $pilotRoot -ExecutionReceiptPath $receiptPath -ConfigPath $configPath -SchedulePath $schedulePath -ProvenancePath $provenancePath -UnityPath $UnityPath -BlockTimeoutSeconds $BlockTimeoutSeconds
    $exit = $LASTEXITCODE
}
finally { $env:PSModulePath = $previousModulePath }
if ($exit -ne 0) { throw "Gate13R-PR2-MP1 measured pilot terminated fail-closed with exit code $exit; no automatic retry/resume/top-up/merge is authorized." }
Write-Host 'Gate13R-PR2-MP1 measured raw acquisition and Phase-A commit completed.' -ForegroundColor Green
exit 0
