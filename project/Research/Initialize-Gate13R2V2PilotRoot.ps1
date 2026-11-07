[CmdletBinding()]
param(
    [string]$ProjectPath = (Split-Path -Parent $PSScriptRoot),
    [string]$PilotPlanPath = 'Research\Gate13R2_v2_Pilot_Plan.v1.json',
    [string]$ProvenancePath = 'Research\Gate13R2_v2_Provenance.v1.json'
)

$ErrorActionPreference = 'Stop'
$ProjectPath = [System.IO.Path]::GetFullPath($ProjectPath)
$PilotPlanPath = if ([System.IO.Path]::IsPathRooted($PilotPlanPath)) { [System.IO.Path]::GetFullPath($PilotPlanPath) } else { [System.IO.Path]::GetFullPath((Join-Path $ProjectPath $PilotPlanPath)) }
$ProvenancePath = if ([System.IO.Path]::IsPathRooted($ProvenancePath)) { [System.IO.Path]::GetFullPath($ProvenancePath) } else { [System.IO.Path]::GetFullPath((Join-Path $ProjectPath $ProvenancePath)) }
$modulePath = Join-Path $PSScriptRoot 'Gate13R2V2Preparation.psm1'
Import-Module $modulePath -Force

if (-not (Test-Path -LiteralPath $PilotPlanPath -PathType Leaf)) { throw "V2 pilot plan missing: $PilotPlanPath" }
if (-not (Test-Path -LiteralPath $ProvenancePath -PathType Leaf)) { throw "V2 provenance missing: $ProvenancePath" }
$plan = Read-G13R2V2Json -Path $PilotPlanPath
$provenance = Read-G13R2V2Json -Path $ProvenancePath
$planTest = Test-G13R2V2PilotPlan -ProjectPath $ProjectPath -Plan $plan -PlanPath $PilotPlanPath
if (-not $planTest.passed) { throw "V2 pilot plan validation failed: $($planTest.errors -join '; ')" }
if ([string]$provenance.provenanceId -ne 'gate13-r2-v2-provenance-v1' -or $provenance.formalExecutionAuthorized -ne $false) { throw 'V2 provenance identity/authorization mismatch.' }
$pilotRoot = [System.IO.Path]::GetFullPath((Join-Path $ProjectPath ([string]$plan.paths.pilotRootRelativePath).Replace('/', '\')))
$formalRoot = [System.IO.Path]::GetFullPath((Join-Path $ProjectPath ([string]$plan.paths.reservedFormalRootRelativePath).Replace('/', '\')))
if (Test-Path -LiteralPath $pilotRoot) { throw "V2 pilot root already exists; refusing retry/overwrite: $pilotRoot" }
if (Test-Path -LiteralPath $formalRoot) { throw "Reserved process-reuse formal root must remain absent: $formalRoot" }

$coldFiles = @(Get-ChildItem -LiteralPath (Join-Path $ProjectPath 'Research\FormalRuns\Gate13\v1') -File -Recurse)
$v1Files = @(Get-ChildItem -LiteralPath (Join-Path $ProjectPath 'Research\PilotRuns\Gate13_ProcessReuse\v1') -File -Recurse)
if ($coldFiles.Count -ne 891 -or ($coldFiles | Where-Object { -not $_.IsReadOnly }).Count -ne 0) { throw 'Cold-process historical root preservation check failed.' }
if ($v1Files.Count -ne 838 -or ($v1Files | Where-Object { -not $_.IsReadOnly }).Count -ne 0) { throw 'Process-reuse v1 historical root preservation check failed.' }

New-Item -ItemType Directory -Path $pilotRoot | Out-Null
$receiptPath = Join-Path $pilotRoot 'root-initialization-receipt.json'
$checkpointPath = Join-Path $pilotRoot 'preparation-checkpoint.json'
$createdAt = [DateTime]::UtcNow.ToString('o')
$receipt = [ordered]@{
    schemaVersion = 1
    receiptId = 'gate13-r2-v2-pilot-root-initialization-receipt-v1'
    createdAtUtc = $createdAt
    authorizationReference = 'user-message-2026-10-06-gate13-r2-v2-telemetry-readiness-and-one-fresh-nonformal-pilot'
    rootAbsolutePath = $pilotRoot
    rootRelativePath = [string]$plan.paths.pilotRootRelativePath
    pilotPlan = [ordered]@{ relativePath = Get-G13R2V2ProjectRelativePath -ProjectPath $ProjectPath -FullPath $PilotPlanPath; sha256 = Get-G13R2V2LowerSha256 -Path $PilotPlanPath }
    provenance = [ordered]@{ relativePath = Get-G13R2V2ProjectRelativePath -ProjectPath $ProjectPath -FullPath $ProvenancePath; sha256 = Get-G13R2V2LowerSha256 -Path $ProvenancePath }
    state = 'PREPARATION-ONLY-PILOT-NOT-STARTED'
    authorizedPilotExecutionCount = 1
    pilotExecutionStarted = $false
    formalCampaign = $false
    formalExecutionReceiptCreated = $false
    automaticRetryAuthorized = $false
    automaticResumeAuthorized = $false
    allowedChildrenAtInitialization = @('root-initialization-receipt.json', 'preparation-checkpoint.json')
}
Write-G13R2V2AtomicUtf8NoBomJson -Path $receiptPath -Value $receipt -Depth 20
$checkpoint = [ordered]@{
    schemaVersion = 1
    checkpointId = 'gate13-r2-v2-preparation-checkpoint-v1'
    status = 'PREPARATION-ONLY-PILOT-NOT-STARTED'
    savedAtUtc = [DateTime]::UtcNow.ToString('o')
    rootInitializationReceiptSha256 = Get-G13R2V2LowerSha256 -Path $receiptPath
    pilotPlanSha256 = Get-G13R2V2LowerSha256 -Path $PilotPlanPath
    provenanceSha256 = Get-G13R2V2LowerSha256 -Path $ProvenancePath
    telemetryProbePassed = $false
    prePilotAuditPassed = $false
    pilotExecutionStarted = $false
    completedUnityProcessCount = 0
    completedSampleCount = 0
    formalCampaign = $false
    automaticRetryAuthorized = $false
    automaticResumeAuthorized = $false
}
Write-G13R2V2AtomicUtf8NoBomJson -Path $checkpointPath -Value $checkpoint -Depth 20
if (@(Get-ChildItem -LiteralPath $pilotRoot -Force).Count -ne 2) { throw 'V2 pilot root initialization wrote unexpected children.' }
[pscustomobject][ordered]@{
    passed = $true
    pilotRoot = $pilotRoot
    rootInitializationReceiptSha256 = Get-G13R2V2LowerSha256 -Path $receiptPath
    preparationCheckpointSha256 = Get-G13R2V2LowerSha256 -Path $checkpointPath
    pilotExecutionStarted = $false
    formalCampaign = $false
} | ConvertTo-Json -Depth 10
