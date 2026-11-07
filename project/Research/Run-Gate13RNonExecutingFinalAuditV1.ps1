[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$ProjectPath,
    [Parameter(Mandatory = $true)][string]$VerificationRoot,
    [Parameter(Mandatory = $true)][string]$ConfigPath,
    [Parameter(Mandatory = $true)][string]$ProvenancePath,
    [Parameter(Mandatory = $true)][string]$SchedulePath,
    [Parameter(Mandatory = $true)][string]$ScheduleManifestPath,
    [Parameter(Mandatory = $true)][string]$RegenerationRoot,
    [switch]$BindingSmokeOnly
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if ([string]::IsNullOrWhiteSpace($ProjectPath) -or -not [IO.Path]::IsPathRooted($ProjectPath)) { throw 'Gate13R final audit requires an explicit absolute ProjectPath.' }
$ProjectPath = [IO.Path]::GetFullPath($ProjectPath)
if ($BindingSmokeOnly) { Write-Output "BINDING-SMOKE-PASSED|Run-Gate13RNonExecutingFinalAuditV1|$ProjectPath"; exit 0 }
Import-Module (Join-Path $ProjectPath 'Research\Gate13RFormalPreparationV1.psm1') -Force

$VerificationRoot = [IO.Path]::GetFullPath($VerificationRoot)
$ConfigPath = [IO.Path]::GetFullPath($ConfigPath)
$ProvenancePath = [IO.Path]::GetFullPath($ProvenancePath)
$SchedulePath = [IO.Path]::GetFullPath($SchedulePath)
$ScheduleManifestPath = [IO.Path]::GetFullPath($ScheduleManifestPath)
$RegenerationRoot = [IO.Path]::GetFullPath($RegenerationRoot)
$formalRoot = [IO.Path]::GetFullPath((Join-Path $ProjectPath 'Research\FormalRuns\Gate13R_ProcessReuse_5pct\v1'))
$verificationBase = [IO.Path]::GetFullPath((Join-Path $ProjectPath 'Research\Verification\Gate13R_NonExecuting_Preparation'))
if (-not (Test-G13RPathWithin -BasePath $verificationBase -CandidatePath $VerificationRoot)) { throw 'VerificationRoot is outside Gate13R verification base.' }
if (-not (Test-G13RPathWithin -BasePath $VerificationRoot -CandidatePath $RegenerationRoot)) { throw 'RegenerationRoot is outside the active verification root.' }
$summaryPath = Join-Path $VerificationRoot 'FinalAudit.summary.json'
if (Test-Path -LiteralPath $summaryPath) { throw 'Create-new Gate13R final-audit summary already exists.' }

$assertions = 0
$errors = New-Object Collections.Generic.List[string]
function Assert-Audit([bool]$Condition, [string]$Message) {
    $script:assertions++
    if (-not $Condition) { $script:errors.Add($Message) }
}

$config = Read-G13RJson $ConfigPath
$provenance = Read-G13RJson $ProvenancePath
$scheduleManifest = Read-G13RJson $ScheduleManifestPath
$unitSummaryPath = Join-Path $VerificationRoot 'Unit\summary.json'
$compileSummaryPath = Join-Path $VerificationRoot 'Compile\summary.json'
$orchestratorSummaryPath = Join-Path $VerificationRoot 'OrchestratorValidation.summary.json'
$scheduleValidationPath = Join-Path $VerificationRoot 'ScheduleValidation.summary.json'
foreach ($path in @($unitSummaryPath, $compileSummaryPath, $orchestratorSummaryPath, $scheduleValidationPath)) { Assert-Audit (Test-Path -LiteralPath $path -PathType Leaf) ("missing-summary-" + (Split-Path -Leaf $path)) }
$unit = if (Test-Path -LiteralPath $unitSummaryPath) { Read-G13RJson $unitSummaryPath } else { $null }
$compile = if (Test-Path -LiteralPath $compileSummaryPath) { Read-G13RJson $compileSummaryPath } else { $null }
$orchestrator = if (Test-Path -LiteralPath $orchestratorSummaryPath) { Read-G13RJson $orchestratorSummaryPath } else { $null }
$scheduleValidation = if (Test-Path -LiteralPath $scheduleValidationPath) { Read-G13RJson $scheduleValidationPath } else { $null }
Assert-Audit ($null -ne $unit -and $unit.passed -eq $true -and [int]$unit.assertionCount -ge 51) 'unit-summary-invalid'
Assert-Audit ($null -ne $compile -and $compile.passed -eq $true -and [int]$compile.compilerErrorMatchCount -eq 0) 'compile-summary-invalid'
Assert-Audit ($null -ne $orchestrator -and $orchestrator.passed -eq $true -and [string]$orchestrator.status -eq 'VALIDATION-ONLY-PASSED-FORMAL-NOT-AUTHORIZED') 'orchestrator-summary-invalid'
Assert-Audit ($null -ne $scheduleValidation -and $scheduleValidation.passed -eq $true -and [int]$scheduleValidation.blockRecordCount -eq 42064 -and [int]$scheduleValidation.sampleIdentityCount -eq 119200) 'schedule-validation-invalid'

Assert-Audit ([string]$config.configKind -eq 'gate13r-process-reuse-5pct-formal-campaign-config-v1') 'config-kind-invalid'
Assert-Audit ($config.formalExecutionAuthorized -eq $false -and $config.formalRootCreated -eq $false -and $config.formalTimingExecuted -eq $false) 'config-authorization-boundary-invalid'
Assert-Audit ([int]$config.totals.campaignCount -eq 74 -and [int]$config.totals.blockProcessCount -eq 42064 -and [int]$config.totals.sampleCount -eq 119200) 'config-cardinality-invalid'
Assert-Audit ($null -eq $config.precision.hardCap -and [double]$config.precision.relativeHalfWidth -eq 0.05) 'config-precision-invalid'
Assert-Audit ([long]$config.storage.minimumLaunchFreeBytes -eq 188047724816) 'config-storage-invalid'
Assert-Audit ([double]$config.runtimeProjection.serialP95Seconds -eq 1141436.3340784) 'config-runtime-disclosure-invalid'
Assert-Audit ([string]$config.schedule.sha256 -eq (Get-G13RLowerSha256 $SchedulePath)) 'config-schedule-hash-invalid'
Assert-Audit ([string]$config.schedule.manifestSha256 -eq (Get-G13RLowerSha256 $ScheduleManifestPath)) 'config-schedule-manifest-hash-invalid'
Assert-Audit ([string]$provenance.formalConfig.sha256 -eq (Get-G13RLowerSha256 $ConfigPath)) 'provenance-config-hash-invalid'
Assert-Audit ([string]$provenance.schedule.sha256 -eq (Get-G13RLowerSha256 $SchedulePath)) 'provenance-schedule-hash-invalid'
Assert-Audit ([int]$scheduleManifest.blockRecordCount -eq 42064 -and [int]$scheduleManifest.sampleIdentityCount -eq 119200) 'schedule-manifest-cardinality-invalid'

$implementationPairs = @(
    @('moduleSha256', 'Research\Gate13RFormalPreparationV1.psm1'),
    @('generatorSha256', 'Research\New-Gate13RFormalPreparationV2.ps1'),
    @('scheduleValidatorSha256', 'Research\Test-Gate13RFormalScheduleV1.ps1'),
    @('orchestratorSha256', 'Research\Run-Gate13RFormalCampaignV1.ps1'),
    @('blockWrapperSha256', 'Research\Run-Gate13RFormalBlockV1.ps1'),
    @('unityCommandSha256', 'Assets\_Scripts\Research\Editor\Gate13RProcessReuseFormalBatchCommandV1.cs'),
    @('unitTestsSha256', 'Research\Run-Gate13RNonExecutingPreparationUnitTestsV2.ps1'),
    @('finalAuditSha256', 'Research\Run-Gate13RNonExecutingFinalAuditV1.ps1'),
    @('readinessSealerSha256', 'Research\New-Gate13RNonExecutingReadinessV1.ps1')
)
foreach ($pair in $implementationPairs) {
    $actual = Get-G13RLowerSha256 (Join-Path $ProjectPath $pair[1])
    Assert-Audit ([string]$config.implementation.($pair[0]) -eq $actual) ("implementation-hash-invalid-" + $pair[0])
}

$protected = @(
    @('Research\FormalScenarios\Gate11R_5pct\v1\bundle-manifest.json', '5baaeec18344a9e99e55da38f3c4875b7e7e9f3bf0add9d5f2d2f1e821b5f7fc'),
    @('Research\FormalScenarios\Gate11R_5pct\v1\formal-scenario-matrix.json', 'cc5f020003f3fad75bd82ebb2c26df521fd639ff0ee5376132853120dbc16aa3'),
    @('Research\Gate12R_Readiness_Checkpoint.v1.json', '93d1ffac30305ecbc3ff32820aa0eee016c7a2cc6824f41c491aac393cfd291d'),
    @('Research\PilotRuns\Gate12R_ProcessReuse_5pct\v4\candidate-n-formal.json', '5e77d9b69c4c0e45dec204ca1943867453d29dcbdf1ebd24f0809af6d649c387'),
    @('Research\PilotRuns\Gate12R_ProcessReuse_5pct\v4\budget-storage-projection.json', 'cca76d3206311119b3b81fd72d162f8425a2657f02d85a906a5fc91a35690e1f'),
    @('Assets\_Scripts\Research\Editor\Gate12RProcessReuseBatchCommandV3.cs', 'eeca58f7e1121d0a297e8796430a90ae32f8492c32fc5fb676ae102b5f4a0c97')
)
foreach ($pair in $protected) { Assert-Audit ((Get-G13RLowerSha256 (Join-Path $ProjectPath $pair[0])) -eq $pair[1]) ("protected-hash-invalid-" + $pair[0]) }

$deterministicNames = @(
    'Gate13R_Formal_Williams_Block_Schedule.v1.jsonl',
    'Gate13R_Formal_Williams_Block_Schedule_Manifest.v1.json',
    'Gate13R_Formal_Campaign_Config.v1.json',
    'Gate13R_NonExecuting_Preparation_Provenance.v1.json'
)
foreach ($name in $deterministicNames) {
    $official = Join-Path $ProjectPath ('Research\' + $name)
    $regenerated = Join-Path $RegenerationRoot $name
    Assert-Audit (Test-Path -LiteralPath $regenerated -PathType Leaf) ("regenerated-missing-$name")
    if (Test-Path -LiteralPath $regenerated -PathType Leaf) { Assert-Audit ((Get-G13RLowerSha256 $official) -eq (Get-G13RLowerSha256 $regenerated)) ("deterministic-regeneration-mismatch-$name") }
}

Assert-Audit (-not (Test-Path -LiteralPath $formalRoot)) 'formal-root-must-remain-absent'
Assert-Audit (-not (Test-Path -LiteralPath (Join-Path $ProjectPath 'Research\Gate13R_Formal_Execution_Receipt.v1.json'))) 'formal-execution-receipt-must-not-exist'
Assert-Audit (@(Get-Process -Name Unity -ErrorAction SilentlyContinue).Count -eq 0) 'unity-process-count-must-be-zero'
Assert-Audit (-not (Test-Path -LiteralPath (Join-Path $ProjectPath 'Temp\UnityLockfile'))) 'unity-lock-must-be-absent'
Assert-Audit (Test-Path -LiteralPath (Join-Path $ProjectPath 'Research\Verification\Gate13R_NonExecuting_Preparation\v1\attempt-failure-receipt.json')) 'attempt1-failure-evidence-missing'

$summary = [ordered]@{
    schemaVersion = 1
    summaryKind = 'gate13r-nonexecuting-preparation-final-audit-v1'
    savedAtUtc = [DateTime]::UtcNow.ToString('o')
    assertionCount = $assertions
    failureCount = $errors.Count
    failures = $errors.ToArray()
    configSha256 = Get-G13RLowerSha256 $ConfigPath
    provenanceSha256 = Get-G13RLowerSha256 $ProvenancePath
    scheduleSha256 = Get-G13RLowerSha256 $SchedulePath
    scheduleManifestSha256 = Get-G13RLowerSha256 $ScheduleManifestPath
    unitSummarySha256 = if (Test-Path -LiteralPath $unitSummaryPath) { Get-G13RLowerSha256 $unitSummaryPath } else { $null }
    compileSummarySha256 = if (Test-Path -LiteralPath $compileSummaryPath) { Get-G13RLowerSha256 $compileSummaryPath } else { $null }
    orchestratorSummarySha256 = if (Test-Path -LiteralPath $orchestratorSummaryPath) { Get-G13RLowerSha256 $orchestratorSummaryPath } else { $null }
    formalRootExists = Test-Path -LiteralPath $formalRoot
    formalExecutionReceiptCreated = $false
    formalCampaignExecuted = $false
    status = if ($errors.Count -eq 0) { 'GATE13R-NONEXECUTING-PREPARATION-PASSED-FORMAL-CAMPAIGN-NOT-AUTHORIZED' } else { 'GATE13R-NONEXECUTING-PREPARATION-FAILED' }
    passed = $errors.Count -eq 0
}
Write-G13RAtomicUtf8NoBomJson -Path $summaryPath -Value $summary -Depth 30
if ($errors.Count -gt 0) { Write-Error ('Gate13R final audit failed: ' + ($errors -join '; ')); exit 1 }
Write-Host "Gate13R final audit passed: $assertions assertions." -ForegroundColor Green
exit 0
