[CmdletBinding()]
param([string]$ProjectPath)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0
$scriptDirectory = Split-Path -Parent $MyInvocation.MyCommand.Path
if ([string]::IsNullOrWhiteSpace($ProjectPath)) { $ProjectPath = [System.IO.Path]::GetFullPath((Join-Path $scriptDirectory '..\..')) }
else { $ProjectPath = [System.IO.Path]::GetFullPath($ProjectPath) }
$modulePath = Join-Path $ProjectPath 'Research\Gate13FormalPreparation.psm1'
$manifestPath = Join-Path $ProjectPath 'Research\Gate13_NonExecuting_Preparation_Manifest.v1.json'
$configPath = Join-Path $ProjectPath 'Research\Gate13_Formal_Campaign_Config.v1.json'
$amendmentPath = Join-Path $ProjectPath 'Research\Gate13_Readiness_Amendment.v1.json'
$formalRoot = Join-Path $ProjectPath 'Research\FormalRuns\Gate13\v1'
$summaryPath = Join-Path $scriptDirectory 'Gate13_Preparation_Final_Audit.summary.json'
$errors = New-Object System.Collections.Generic.List[string]
Import-Module $modulePath -Force

function Add-Error([string]$Message) { $script:errors.Add($Message) }
function Test-RecordedFile($Record, [string]$Label) {
    if ($null -eq $Record -or [string]::IsNullOrWhiteSpace([string]$Record.relativePath)) { Add-Error "$Label record is missing."; return $null }
    $path = Join-Path $ProjectPath ([string]$Record.relativePath).Replace('/', '\')
    $actual = if (Test-Path -LiteralPath $path -PathType Leaf) { Get-Gate13LowerSha256 -Path $path } else { $null }
    $matches = $actual -eq [string]$Record.sha256
    if (-not $matches) { Add-Error "$Label hash mismatch: $($Record.relativePath)" }
    return [pscustomobject][ordered]@{ relativePath = $Record.relativePath; expectedSha256 = $Record.sha256; actualSha256 = $actual; matches = $matches }
}

$requiredPaths = @($modulePath, $manifestPath, $configPath, $amendmentPath)
foreach ($path in $requiredPaths) { if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { Add-Error "Required Gate 13 preparation file is missing: $path" } }
$manifest = Read-Gate13Json -Path $manifestPath
$config = Read-Gate13Json -Path $configPath
$amendment = Read-Gate13Json -Path $amendmentPath

$manifestIdentityErrors = New-Object System.Collections.Generic.List[string]
if ([int]$manifest.schemaVersion -ne 1 -or $manifest.manifestId -ne 'gate13-nonexecuting-preparation-manifest-v1') { $manifestIdentityErrors.Add('Preparation manifest identity mismatch.') }
if ($manifest.classification -ne 'implementation-and-validation-only-no-formal-execution') { $manifestIdentityErrors.Add('Preparation manifest classification mismatch.') }
if ($manifest.authorizationBoundary.nonExecutingPreparationAuthorized -ne $true -or
    $manifest.authorizationBoundary.gate13ExecutionAuthorized -ne $false -or
    $manifest.authorizationBoundary.formalCampaignStartAllowed -ne $false -or
    $manifest.authorizationBoundary.executionAuthorizationReceiptCreated -ne $false -or
    $manifest.authorizationBoundary.formalOutputRootCreationAllowedInThisStage -ne $false -or
    $manifest.authorizationBoundary.timingCampaignAllowedInThisStage -ne $false) { $manifestIdentityErrors.Add('Preparation manifest authorization boundary widened.') }
if ($manifest.finalState.nonExecutingPreparationImplementationComplete -ne $true -or
    $manifest.finalState.validationOnlyPassed -ne $true -or
    $manifest.finalState.formalOutputRootCreated -ne $false -or
    $manifest.finalState.timingCampaignStarted -ne $false -or
    $manifest.finalState.gate13FormalExecutionStatus -ne 'not-started-not-authorized') { $manifestIdentityErrors.Add('Preparation manifest final-state fields mismatch.') }
foreach ($message in $manifestIdentityErrors) { Add-Error $message }

$recordedFileChecks = New-Object System.Collections.Generic.List[object]
$recordedFileChecks.Add((Test-RecordedFile -Record $manifest.upstreamDecision -Label 'Gate 13 amendment'))
$recordedFileChecks.Add((Test-RecordedFile -Record $manifest.preparationDocuments.specification -Label 'Preparation specification'))
$recordedFileChecks.Add((Test-RecordedFile -Record $manifest.preparationDocuments.testDesign -Label 'Preparation test design'))
$recordedFileChecks.Add((Test-RecordedFile -Record $manifest.configuration -Label 'Formal config'))
foreach ($record in @($manifest.implementationFiles)) { $recordedFileChecks.Add((Test-RecordedFile -Record $record -Label "Implementation file $($record.id)")) }
foreach ($record in @($manifest.verificationEvidence)) {
    $scriptRecord = [pscustomobject]@{ relativePath = $record.scriptRelativePath; sha256 = $record.scriptSha256 }
    $summaryRecord = [pscustomobject]@{ relativePath = $record.summaryRelativePath; sha256 = $record.summarySha256 }
    $recordedFileChecks.Add((Test-RecordedFile -Record $scriptRecord -Label "Verification script $($record.id)"))
    $recordedFileChecks.Add((Test-RecordedFile -Record $summaryRecord -Label "Verification summary $($record.id)"))
    if ($record.passed -ne $true) { Add-Error "Verification evidence not marked passing: $($record.id)" }
}

$configCheck = Test-Gate13FormalConfig -ProjectPath $ProjectPath -Config $config -ConfigPath $configPath
if (-not $configCheck.passed) { foreach ($message in @($configCheck.errors)) { Add-Error "Config: $message" } }
$configScheduleErrors = New-Object System.Collections.Generic.List[string]
$cohortExpectations = [ordered]@{
    'four-algorithm-shared-goal-v1' = [ordered]@{ campaigns = 32; blocks = 52; samples = 6656 }
    'per-agent-heterogeneous-goal-v1' = [ordered]@{ campaigns = 21; blocks = 148; samples = 6216 }
    'grouped-field-heterogeneous-goal-v1' = [ordered]@{ campaigns = 21; blocks = 52; samples = 2184 }
}
foreach ($entry in $cohortExpectations.GetEnumerator()) {
    $campaigns = @($config.campaigns | Where-Object comparisonCohortId -eq $entry.Key)
    $samples = [int](($campaigns | Measure-Object -Property sampleCount -Sum).Sum)
    if ($campaigns.Count -ne $entry.Value.campaigns -or @($campaigns | Where-Object blockCount -ne $entry.Value.blocks).Count -gt 0 -or $samples -ne $entry.Value.samples) { $configScheduleErrors.Add("Cohort schedule mismatch: $($entry.Key)") }
}
if (@($config.campaigns).Count -ne 74 -or [int]$config.totals.expectedUnityProcessCount -ne 15056) { $configScheduleErrors.Add('Formal total must be 74 campaigns / 15056 samples.') }
if ($config.authorizationBoundary.gate13ExecutionAuthorized -ne $false -or $config.authorizationBoundary.formalCampaignStartAllowed -ne $false) { $configScheduleErrors.Add('Config attempts to authorize formal execution.') }
foreach ($message in $configScheduleErrors) { Add-Error $message }

$verificationSummaries = [ordered]@{
    gate13Unit = Read-Gate13Json -Path (Join-Path $scriptDirectory 'Gate13_Preparation_UnitTests.summary.json')
    gate13Validation = Read-Gate13Json -Path (Join-Path $scriptDirectory 'Gate13_Preparation_Validation.summary.json')
    gate13AmendmentAudit = Read-Gate13Json -Path (Join-Path $scriptDirectory 'Gate13_Readiness_Amendment_Audit.summary.json')
    gate12Regression = Read-Gate13Json -Path (Join-Path $scriptDirectory 'Gate12_AnalysisUnitTests.summary.json')
}
$verificationSummaryErrors = New-Object System.Collections.Generic.List[string]
if ($verificationSummaries.gate13Unit.passed -ne $true -or [int]$verificationSummaries.gate13Unit.total -ne 60 -or [int]$verificationSummaries.gate13Unit.failedCount -ne 0) { $verificationSummaryErrors.Add('Gate 13 unit summary is not 60/60.') }
if ($verificationSummaries.gate13Validation.passed -ne $true -or @($verificationSummaries.gate13Validation.failedChecks).Count -ne 0) { $verificationSummaryErrors.Add('Gate 13 validation summary is not passing.') }
if ($verificationSummaries.gate13AmendmentAudit.passed -ne $true) { $verificationSummaryErrors.Add('Gate 13 amendment audit is not passing.') }
if ($verificationSummaries.gate12Regression.passed -ne $true -or [int]$verificationSummaries.gate12Regression.assertionCount -ne 63) { $verificationSummaryErrors.Add('Gate 12 regression is not 63/63.') }
foreach ($message in $verificationSummaryErrors) { Add-Error $message }

$bundleCheck = Get-Gate13BundleVerification -ProjectPath $ProjectPath -Amendment $amendment
if (-not $bundleCheck.passed) { foreach ($message in @($bundleCheck.errors)) { Add-Error "Gate11: $message" } }
$baselineRows = @(Import-Csv -LiteralPath (Join-Path $ProjectPath 'Research\Baseline_SHA256.csv') | Where-Object { $_.scope -in @('working_copy', 'external_archive') })
$baselineMismatches = New-Object System.Collections.Generic.List[object]
foreach ($row in $baselineRows) {
    $path = if ($row.scope -eq 'external_archive') { [System.IO.Path]::GetFullPath((Join-Path $ProjectPath $row.relative_path)) } else { Join-Path $ProjectPath $row.relative_path.Replace('/', '\') }
    $actualHash = if (Test-Path -LiteralPath $path -PathType Leaf) { Get-Gate13LowerSha256 -Path $path } else { $null }
    $actualBytes = if (Test-Path -LiteralPath $path -PathType Leaf) { [int64](Get-Item -LiteralPath $path).Length } else { $null }
    if ($actualHash -ne $row.sha256 -or $actualBytes -ne [int64]$row.bytes) { $baselineMismatches.Add([pscustomobject]@{ relativePath = $row.relative_path; actualSha256 = $actualHash; actualBytes = $actualBytes }) }
}
if ($baselineRows.Count -ne 24 -or $baselineMismatches.Count -gt 0) { Add-Error "Original baseline mismatch: checked=$($baselineRows.Count), mismatches=$($baselineMismatches.Count)" }

$protectedHashChecks = New-Object System.Collections.Generic.List[object]
foreach ($entry in @(
    [ordered]@{ id = 'gate11-bundle-manifest'; path = 'Research/FormalScenarios/v1/bundle-manifest.json'; expected = $manifest.protectedEvidence.gate11BundleManifestSha256 },
    [ordered]@{ id = 'gate12-pilot-manifest'; path = 'Research/PilotRuns/Gate12/v1/pilot-manifest.json'; expected = $manifest.protectedEvidence.gate12PilotManifestSha256 },
    [ordered]@{ id = 'gate12-final-audit'; path = 'Research/Verification/Gate12_FinalAudit.summary.json'; expected = $manifest.protectedEvidence.gate12FinalAuditSha256 },
    [ordered]@{ id = 'gate10-fairness-specification'; path = 'Research/Four_Algorithm_Fairness_and_Unified_Campaign_Specification.md'; expected = $manifest.protectedEvidence.gate10FairnessSpecificationSha256 },
    [ordered]@{ id = 'gate10-runner'; path = 'Research/Run-FairPlanningCampaign.ps1'; expected = $manifest.protectedEvidence.gate10RunnerSha256 },
    [ordered]@{ id = 'workload-runner'; path = 'Research/Run-PlanningWorkload.ps1'; expected = $manifest.protectedEvidence.workloadRunnerSha256 }
)) {
    $path = Join-Path $ProjectPath $entry.path.Replace('/', '\')
    $actual = if (Test-Path -LiteralPath $path -PathType Leaf) { Get-Gate13LowerSha256 -Path $path } else { $null }
    $matches = $actual -eq [string]$entry.expected
    $protectedHashChecks.Add([pscustomobject][ordered]@{ id = $entry.id; relativePath = $entry.path; expectedSha256 = $entry.expected; actualSha256 = $actual; matches = $matches })
    if (-not $matches) { Add-Error "Protected evidence hash mismatch: $($entry.id)" }
}
$gate12FileCount = @(Get-ChildItem -LiteralPath (Join-Path $ProjectPath 'Research\PilotRuns\Gate12\v1') -File -Recurse).Count
if ($gate12FileCount -ne 1694) { Add-Error "Gate 12 successful v1 file count changed: $gate12FileCount" }

$utf8 = New-Object System.Text.UTF8Encoding($false, $true)
$powerShellParseErrors = New-Object System.Collections.Generic.List[object]
$powerShellFiles = @(Get-ChildItem -LiteralPath (Join-Path $ProjectPath 'Research') -File -Recurse | Where-Object { $_.Extension -in @('.ps1', '.psm1') } | Sort-Object FullName)
foreach ($file in $powerShellFiles) {
    $tokens = $null; $parseErrors = $null
    $scriptText = [System.IO.File]::ReadAllText($file.FullName, $utf8)
    [void][System.Management.Automation.Language.Parser]::ParseInput($scriptText, $file.FullName, [ref]$tokens, [ref]$parseErrors)
    foreach ($parseError in @($parseErrors)) { $powerShellParseErrors.Add([pscustomobject]@{ path = $file.FullName; message = $parseError.Message }) }
}
if ($powerShellParseErrors.Count -gt 0) { Add-Error "PowerShell parse errors: $($powerShellParseErrors.Count)" }
$jsonParseErrors = New-Object System.Collections.Generic.List[object]
$jsonFiles = @(Get-ChildItem -LiteralPath (Join-Path $ProjectPath 'Research') -Filter '*.json' -File -Recurse | Sort-Object FullName)
foreach ($file in $jsonFiles) { try { [void](Read-Gate13Json -Path $file.FullName) } catch { $jsonParseErrors.Add([pscustomobject]@{ path = $file.FullName; message = $_.Exception.Message }) } }
if ($jsonParseErrors.Count -gt 0) { Add-Error "JSON parse errors: $($jsonParseErrors.Count)" }

$formalTrueJsonFiles = New-Object System.Collections.Generic.List[string]
foreach ($file in $jsonFiles) {
    $text = [System.IO.File]::ReadAllText($file.FullName, $utf8)
    if ($text -match '"formalCampaign"\s*:\s*true|"gate13ExecutionAuthorized"\s*:\s*true|"formalCampaignStartAllowed"\s*:\s*true') { $formalTrueJsonFiles.Add($file.FullName) }
}
if ($formalTrueJsonFiles.Count -gt 0) { Add-Error "Formal true flags found in JSON: $($formalTrueJsonFiles.Count)" }
$authorizationReceipts = @(Get-ChildItem -LiteralPath (Join-Path $ProjectPath 'Research') -Filter '*Gate13*Authorization*.json' -File -Recurse -ErrorAction SilentlyContinue)
if ($authorizationReceipts.Count -gt 0) { Add-Error "Unexpected Gate 13 authorization receipt exists: $($authorizationReceipts.FullName -join ', ')" }
$formalRootPresent = Test-Path -LiteralPath $formalRoot
$unityProcesses = @(Get-Process -Name Unity -ErrorAction SilentlyContinue)
$unityLockPresent = Test-Path -LiteralPath (Join-Path $ProjectPath 'Temp\UnityLockfile')
if ($formalRootPresent) { Add-Error 'Gate 13 formal root exists.' }
if ($unityProcesses.Count -gt 0) { Add-Error "Unity processes are running: $(@($unityProcesses | ForEach-Object { $_.Id }) -join ',')" }
if ($unityLockPresent) { Add-Error 'Unity lockfile exists.' }
$storage = Test-Gate13RawByteStorage -OutputRoot $formalRoot -MinimumFreeBytes ([int64]$config.launchPreflight.minimumLaunchFreeBytes) -Purpose 'validation-only-advisory'
if (-not $storage.passed) { Add-Error "Current advisory storage snapshot fails: $($storage.errors -join '; ')" }

$checks = [ordered]@{
    preparationManifestIdentityClosed = $manifestIdentityErrors.Count -eq 0
    manifestRecordedFileHashesMatch = @($recordedFileChecks.ToArray() | Where-Object { $null -eq $_ -or -not $_.matches }).Count -eq 0
    amendmentRemainsByteIdentical = (Get-Gate13LowerSha256 -Path $amendmentPath) -eq '1ccf5c6e1e2c646d160e7b597381c797cc14e6123134a28b429fcb773515e8b2'
    configDeterministicAndRuntimeHashBound = $configCheck.passed
    cap148ScheduleTotalsMatch = $configScheduleErrors.Count -eq 0
    gate13UnitTests60Of60 = $verificationSummaries.gate13Unit.passed -and [int]$verificationSummaries.gate13Unit.total -eq 60
    gate13ValidationPasses = $verificationSummaries.gate13Validation.passed
    gate13AmendmentAuditPasses = $verificationSummaries.gate13AmendmentAudit.passed
    gate12Regression63Of63 = $verificationSummaries.gate12Regression.passed -and [int]$verificationSummaries.gate12Regression.assertionCount -eq 63
    gate11Bundle57Files56ArtifactsUnchanged = $bundleCheck.passed -and $bundleCheck.fileCount -eq 57 -and $bundleCheck.artifactCount -eq 56
    originalBaseline24Of24 = $baselineRows.Count -eq 24 -and $baselineMismatches.Count -eq 0
    gate12SuccessfulV1CountUnchanged = $gate12FileCount -eq 1694
    protectedGate10Gate12HashesMatch = @($protectedHashChecks.ToArray() | Where-Object { -not $_.matches }).Count -eq 0
    allResearchPowerShellParsesAsStrictUtf8 = $powerShellParseErrors.Count -eq 0
    allResearchJsonParses = $jsonParseErrors.Count -eq 0
    noFormalTrueJson = $formalTrueJsonFiles.Count -eq 0
    noExecutionAuthorizationReceipt = $authorizationReceipts.Count -eq 0
    noGate13FormalRoot = -not $formalRootPresent
    noUnityProcess = $unityProcesses.Count -eq 0
    noUnityLockfile = -not $unityLockPresent
    rawByteStorageSnapshotPassesButDoesNotAuthorize = $storage.passed -and $storage.launchAuthorizationConferred -eq $false
    formalExecutionStillNotAuthorized = $manifest.authorizationBoundary.gate13ExecutionAuthorized -eq $false -and $config.authorizationBoundary.gate13ExecutionAuthorized -eq $false
    timingCampaignNotStarted = $manifest.finalState.timingCampaignStarted -eq $false
}
$failedChecks = @($checks.GetEnumerator() | Where-Object { -not $_.Value } | ForEach-Object { $_.Key })
$passed = $errors.Count -eq 0 -and $failedChecks.Count -eq 0
$summary = [ordered]@{
    schemaVersion = 1
    auditId = 'gate13-nonexecuting-preparation-final-audit-v1'
    auditMode = 'static-unit-regression-validation-only-no-formal-execution'
    savedAt = (Get-Date).ToString('o')
    projectPath = $ProjectPath
    manifestSha256 = Get-Gate13LowerSha256 -Path $manifestPath
    configSha256 = Get-Gate13LowerSha256 -Path $configPath
    amendmentSha256 = Get-Gate13LowerSha256 -Path $amendmentPath
    recordedFileChecks = $recordedFileChecks.ToArray()
    manifestIdentityErrors = $manifestIdentityErrors.ToArray()
    configValidation = $configCheck
    configScheduleErrors = $configScheduleErrors.ToArray()
    verificationSummaryErrors = $verificationSummaryErrors.ToArray()
    gate11Bundle = $bundleCheck
    baselineChecked = $baselineRows.Count
    baselineMismatches = $baselineMismatches.ToArray()
    gate12SuccessfulV1FileCount = $gate12FileCount
    protectedHashChecks = $protectedHashChecks.ToArray()
    powerShellFileCount = $powerShellFiles.Count
    powerShellParseErrors = $powerShellParseErrors.ToArray()
    jsonFileCount = $jsonFiles.Count
    jsonParseErrors = $jsonParseErrors.ToArray()
    formalTrueJsonFiles = $formalTrueJsonFiles.ToArray()
    executionAuthorizationReceiptFiles = @($authorizationReceipts | ForEach-Object { $_.FullName })
    formalRootPresent = $formalRootPresent
    unityProcessIds = @($unityProcesses | ForEach-Object { $_.Id })
    unityLockfilePresent = $unityLockPresent
    currentStorageSnapshot = $storage
    checks = $checks
    failedChecks = $failedChecks
    errors = $errors.ToArray()
    passed = $passed
    gate13Status = 'nonexecuting-preparation-complete-formal-execution-not-started-not-authorized'
}
Write-Gate13Utf8NoBomJson -Path $summaryPath -Value $summary -Depth 26
$summary | ConvertTo-Json -Depth 10
if (-not $passed) { Write-Error "Gate 13 preparation final audit failed: $($failedChecks -join ', '); $($errors -join '; ')"; exit 1 }
Write-Host 'Gate 13 nonexecuting preparation final audit passed. Formal execution remains not started and not authorized.' -ForegroundColor Green
exit 0
