[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$ProjectPath,
    [Parameter(Mandatory = $true)][string]$VerificationRoot,
    [Parameter(Mandatory = $true)][string]$AuthorizationPromptPath,
    [switch]$BindingSmokeOnly
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if ([string]::IsNullOrWhiteSpace($ProjectPath) -or -not [IO.Path]::IsPathRooted($ProjectPath)) { throw 'Gate13R readiness sealer requires an explicit absolute ProjectPath.' }
$ProjectPath = [IO.Path]::GetFullPath($ProjectPath)
if ($BindingSmokeOnly) { Write-Output "BINDING-SMOKE-PASSED|New-Gate13RNonExecutingReadinessV1|$ProjectPath"; exit 0 }
Import-Module (Join-Path $ProjectPath 'Research\Gate13RFormalPreparationV1.psm1') -Force

$VerificationRoot = [IO.Path]::GetFullPath($VerificationRoot)
$AuthorizationPromptPath = [IO.Path]::GetFullPath($AuthorizationPromptPath)
$verificationBase = [IO.Path]::GetFullPath((Join-Path $ProjectPath 'Research\Verification\Gate13R_NonExecuting_Preparation'))
$formalRoot = [IO.Path]::GetFullPath((Join-Path $ProjectPath 'Research\FormalRuns\Gate13R_ProcessReuse_5pct\v1'))
if (-not (Test-G13RPathWithin -BasePath $verificationBase -CandidatePath $VerificationRoot)) { throw 'VerificationRoot is outside Gate13R verification base.' }
if (Test-Path -LiteralPath $formalRoot) { throw 'Cannot seal readiness while the formal root exists.' }
if (@(Get-Process -Name Unity -ErrorAction SilentlyContinue).Count -gt 0 -or (Test-Path -LiteralPath (Join-Path $ProjectPath 'Temp\UnityLockfile'))) { throw 'Cannot seal readiness while Unity or the project lock is active.' }
if (-not (Test-Path -LiteralPath $AuthorizationPromptPath -PathType Leaf)) { throw 'Formal authorization prompt is missing.' }
$evidenceManifestPath = Join-Path $ProjectPath 'Research\Gate13R_NonExecuting_Preparation_Evidence_Manifest.v1.json'
$checkpointPath = Join-Path $ProjectPath 'Research\Gate13R_NonExecuting_Readiness_Checkpoint.v1.json'
foreach ($path in @($evidenceManifestPath, $checkpointPath)) { if (Test-Path -LiteralPath $path) { throw "Create-new readiness artifact already exists: $path" } }

$finalAuditPath = Join-Path $VerificationRoot 'FinalAudit.summary.json'
if (-not (Test-Path -LiteralPath $finalAuditPath -PathType Leaf)) { throw 'Final audit summary is missing.' }
$audit = Read-G13RJson $finalAuditPath
if ($audit.passed -ne $true -or [string]$audit.status -ne 'GATE13R-NONEXECUTING-PREPARATION-PASSED-FORMAL-CAMPAIGN-NOT-AUTHORIZED') { throw 'Final audit is not terminal-passed.' }

$entries = New-Object Collections.Generic.List[object]
$aggregateBuilder = New-Object Text.StringBuilder
$totalBytes = 0L
foreach ($file in @(Get-ChildItem -LiteralPath $VerificationRoot -Recurse -File -Force | Sort-Object FullName)) {
    $relative = Get-G13RProjectRelativePath -ProjectPath $ProjectPath -Path $file.FullName
    $sha256 = Get-G13RLowerSha256 $file.FullName
    $totalBytes += [long]$file.Length
    $entries.Add([ordered]@{ relativePath = $relative; rawBytes = [long]$file.Length; sha256 = $sha256 })
    $null = $aggregateBuilder.Append($relative).Append('|').Append([long]$file.Length).Append('|').Append($sha256).Append("`n")
}
$evidenceManifest = [ordered]@{
    schemaVersion = 1
    manifestKind = 'gate13r-nonexecuting-preparation-evidence-manifest-v1'
    createdAtUtc = [DateTime]::UtcNow.ToString('o')
    verificationRoot = Get-G13RProjectRelativePath -ProjectPath $ProjectPath -Path $VerificationRoot
    fileCount = $entries.Count
    rawBytes = $totalBytes
    aggregateSha256 = Get-G13RStringSha256 $aggregateBuilder.ToString()
    artifacts = $entries.ToArray()
    formalRootCreated = $false
    formalExecutionReceiptCreated = $false
    formalCampaignExecuted = $false
}
Write-G13RAtomicUtf8NoBomJson -Path $evidenceManifestPath -Value $evidenceManifest -Depth 30

$configPath = Join-Path $ProjectPath 'Research\Gate13R_Formal_Campaign_Config.v1.json'
$provenancePath = Join-Path $ProjectPath 'Research\Gate13R_NonExecuting_Preparation_Provenance.v1.json'
$schedulePath = Join-Path $ProjectPath 'Research\Gate13R_Formal_Williams_Block_Schedule.v1.jsonl'
$scheduleManifestPath = Join-Path $ProjectPath 'Research\Gate13R_Formal_Williams_Block_Schedule_Manifest.v1.json'
$checkpoint = [ordered]@{
    schemaVersion = 1
    checkpointKind = 'gate13r-nonexecuting-readiness-checkpoint-v1'
    completedAtUtc = [DateTime]::UtcNow.ToString('o')
    status = 'GATE13R-NONEXECUTING-PREPARATION-PASSED-FORMAL-CAMPAIGN-NOT-AUTHORIZED'
    executionDesignId = 'gate10r-one-fresh-unity-process-per-williams-block-5pct-v1'
    formalDesignId = 'gate13r-one-fresh-unity-process-per-williams-block-5pct-uncapped-v1'
    configSha256 = Get-G13RLowerSha256 $configPath
    provenanceSha256 = Get-G13RLowerSha256 $provenancePath
    scheduleSha256 = Get-G13RLowerSha256 $schedulePath
    scheduleManifestSha256 = Get-G13RLowerSha256 $scheduleManifestPath
    finalAuditSha256 = Get-G13RLowerSha256 $finalAuditPath
    evidenceManifestSha256 = Get-G13RLowerSha256 $evidenceManifestPath
    authorizationPromptSha256 = Get-G13RLowerSha256 $AuthorizationPromptPath
    campaignCount = 74
    blockProcessCount = 42064
    sampleCount = 119200
    minimumLaunchFreeBytes = 188047724816L
    serialP95Seconds = 1141436.3340784
    formalRootExists = $false
    formalExecutionReceiptCreated = $false
    formalCampaignExecuted = $false
    nextAction = 'request-separate-user-authorization-for-gate13r-formal-campaign'
}
Write-G13RAtomicUtf8NoBomJson -Path $checkpointPath -Value $checkpoint -Depth 20
Write-Host "Gate13R non-executing readiness sealed: $($evidenceManifest.fileCount) evidence files / $totalBytes bytes." -ForegroundColor Green
exit 0
