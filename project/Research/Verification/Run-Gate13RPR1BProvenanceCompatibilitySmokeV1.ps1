[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$ProjectPath,
    [Parameter(Mandatory=$true)][string]$PlanPath,
    [Parameter(Mandatory=$true)][string]$ProvenancePath,
    [Parameter(Mandatory=$true)][string]$TelemetryResultPath,
    [Parameter(Mandatory=$true)][string]$OutputRoot
)
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$ProjectPath=[IO.Path]::GetFullPath($ProjectPath);$PlanPath=[IO.Path]::GetFullPath($PlanPath);$ProvenancePath=[IO.Path]::GetFullPath($ProvenancePath);$TelemetryResultPath=[IO.Path]::GetFullPath($TelemetryResultPath);$OutputRoot=[IO.Path]::GetFullPath($OutputRoot)
$base=[IO.Path]::GetFullPath((Join-Path $ProjectPath 'Research\Verification\Gate13R_PR1B_v4_ProvenanceCompatibilitySmoke'))
if(-not$OutputRoot.StartsWith($base.TrimEnd('\')+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'Smoke root outside dedicated base.'}
if(Test-Path -LiteralPath $OutputRoot){throw "Create-new smoke root exists: $OutputRoot"}
if(@(Get-Process -Name Unity -ErrorAction SilentlyContinue).Count-or(Test-Path (Join-Path $ProjectPath 'Temp\UnityLockfile'))){throw 'Unity must be closed and unlocked.'}
if(Test-Path (Join-Path $ProjectPath 'Research\FormalRuns\Gate13R_RQAligned\v1')){throw 'Formal root must remain absent.'}
New-Item -ItemType Directory -Path $OutputRoot -Force|Out-Null
Import-Module (Join-Path $ProjectPath 'Research\Gate13RPR1BOrderEffectPreparationV4.psm1') -Force
$plan=Read-Gate13RPR1BV3Json $PlanPath;$provenance=Read-Gate13RPR1BV3Json $ProvenancePath;Assert-Gate13RPR1BV3PlanIdentity $plan
$campaigns=@(Get-Gate13RPR1BV3Campaigns -ProjectPath $ProjectPath -Plan $plan)
$schedule=@(Get-Gate13RPR1BV3ProcessSchedule -Plan $plan -Campaigns $campaigns -AnalysisRole 'measured-non-formal-pilot')
if($schedule.Count-ne384){throw "Measured schedule mismatch: $($schedule.Count)"}
$item=$schedule[0]
$blockPlan=New-Gate13RPR1BV3BlockPlan -ProjectPath $ProjectPath -Plan $plan -Provenance $provenance -ScheduleItem $item -ProvenancePath $ProvenancePath -TelemetryProbeResultPath $TelemetryResultPath
$checks=[ordered]@{
    config=$blockPlan.pilotPlanSha256-eq[string]$provenance.config.sha256
    specification=$blockPlan.specificationSha256-eq[string]$provenance.specification.sha256
    testDesign=$blockPlan.testDesignSha256-eq[string]$provenance.testDesign.sha256
    executionAuthorization=$blockPlan.amendmentSha256-eq[string]$provenance.executionAuthorization.sha256
    unityCommand=$blockPlan.commandSha256-eq[string]$provenance.unityCommand.sha256
    provenance=$blockPlan.provenanceSha256-eq(Get-Gate13RPR1BV3LowerSha256 $ProvenancePath)
    telemetry=$blockPlan.telemetryProbeResultSha256-eq(Get-Gate13RPR1BV3LowerSha256 $TelemetryResultPath)
    twoSampleBlock=@($blockPlan.entries).Count-eq2
}
$passed=@($checks.GetEnumerator()|Where-Object{-not$_.Value}).Count-eq0
Write-Gate13RPR1BV3AtomicUtf8NoBomJson -Path (Join-Path $OutputRoot 'block-plan.json') -Value $blockPlan -Depth 30
$summary=[ordered]@{schemaVersion=1;summaryKind='gate13r-pr1b-v4-provenance-compatibility-smoke-v1';savedAtUtc=[DateTime]::UtcNow.ToString('o');measuredScheduleCount=$schedule.Count;campaignCount=$campaigns.Count;checks=$checks;unityInvoked=$false;pilotRootCreated=$false;formalCampaign=$false;passed=$passed}
Write-Gate13RPR1BV3AtomicUtf8NoBomJson -Path (Join-Path $OutputRoot 'summary.json') -Value $summary -Depth 20
if(-not$passed){Write-Error 'Provenance compatibility smoke failed.';exit 1}
$summary|ConvertTo-Json -Depth 20
exit 0
