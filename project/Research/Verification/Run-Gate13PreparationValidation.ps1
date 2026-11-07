[CmdletBinding()]
param([string]$ProjectPath)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0
$scriptDirectory = Split-Path -Parent $MyInvocation.MyCommand.Path
if ([string]::IsNullOrWhiteSpace($ProjectPath)) { $ProjectPath = [System.IO.Path]::GetFullPath((Join-Path $scriptDirectory '..\..')) }
else { $ProjectPath = [System.IO.Path]::GetFullPath($ProjectPath) }
$modulePath = Join-Path $ProjectPath 'Research\Gate13FormalPreparation.psm1'
$configPath = Join-Path $ProjectPath 'Research\Gate13_Formal_Campaign_Config.v1.json'
$generatorPath = Join-Path $ProjectPath 'Research\New-Gate13FormalCampaignConfig.ps1'
$scenarioRunnerPath = Join-Path $ProjectPath 'Research\Run-Gate13FormalScenarioCampaign.ps1'
$orchestratorPath = Join-Path $ProjectPath 'Research\Run-Gate13FormalCampaign.ps1'
$formalRoot = Join-Path $ProjectPath 'Research\FormalRuns\Gate13\v1'
$summaryPath = Join-Path $scriptDirectory 'Gate13_Preparation_Validation.summary.json'
$errors = New-Object System.Collections.Generic.List[string]
Import-Module $modulePath -Force

$rootPresentBefore = Test-Path -LiteralPath $formalRoot
$unityBefore = @(Get-Process -Name Unity -ErrorAction SilentlyContinue)
$lockBefore = Test-Path -LiteralPath (Join-Path $ProjectPath 'Temp\UnityLockfile')
if ($rootPresentBefore) { $errors.Add('Gate 13 formal root exists before validation.') }
if ($unityBefore.Count -gt 0) { $errors.Add('Unity is running before validation.') }
if ($lockBefore) { $errors.Add('Unity lockfile exists before validation.') }

$powerShellParseErrors = New-Object System.Collections.Generic.List[object]
$powerShellFiles = @(Get-ChildItem -LiteralPath (Join-Path $ProjectPath 'Research') -File -Recurse | Where-Object { $_.Extension -in @('.ps1', '.psm1') } | Sort-Object FullName)
foreach ($file in $powerShellFiles) {
    $tokens = $null
    $parseErrors = $null
    $utf8 = New-Object System.Text.UTF8Encoding($false, $true)
    $scriptText = [System.IO.File]::ReadAllText($file.FullName, $utf8)
    [void][System.Management.Automation.Language.Parser]::ParseInput($scriptText, $file.FullName, [ref]$tokens, [ref]$parseErrors)
    foreach ($parseError in @($parseErrors)) { $powerShellParseErrors.Add([pscustomobject]@{ path = $file.FullName; message = $parseError.Message }) }
}
if ($powerShellParseErrors.Count -gt 0) { $errors.Add("PowerShell parse errors: $($powerShellParseErrors.Count)") }

$jsonParseErrors = New-Object System.Collections.Generic.List[object]
$jsonFiles = @(Get-ChildItem -LiteralPath (Join-Path $ProjectPath 'Research') -Filter '*.json' -File -Recurse | Sort-Object FullName)
foreach ($file in $jsonFiles) {
    try { [void](Read-Gate13Json -Path $file.FullName) }
    catch { $jsonParseErrors.Add([pscustomobject]@{ path = $file.FullName; message = $_.Exception.Message }) }
}
if ($jsonParseErrors.Count -gt 0) { $errors.Add("JSON parse errors: $($jsonParseErrors.Count)") }

$config = Read-Gate13Json -Path $configPath
$configCheck = Test-Gate13FormalConfig -ProjectPath $ProjectPath -Config $config -ConfigPath $configPath
if (-not $configCheck.passed) { foreach ($message in @($configCheck.errors)) { $errors.Add("Config: $message") } }
$amendment = Read-Gate13Json -Path (Join-Path $ProjectPath 'Research\Gate13_Readiness_Amendment.v1.json')
$bundleCheck = Get-Gate13BundleVerification -ProjectPath $ProjectPath -Amendment $amendment
if (-not $bundleCheck.passed) { foreach ($message in @($bundleCheck.errors)) { $errors.Add("Gate11: $message") } }

$baselineRows = @(Import-Csv -LiteralPath (Join-Path $ProjectPath 'Research\Baseline_SHA256.csv') | Where-Object { $_.scope -in @('working_copy', 'external_archive') })
$baselineMismatches = New-Object System.Collections.Generic.List[object]
foreach ($row in $baselineRows) {
    $path = if ($row.scope -eq 'external_archive') { [System.IO.Path]::GetFullPath((Join-Path $ProjectPath $row.relative_path)) } else { Join-Path $ProjectPath $row.relative_path.Replace('/', '\') }
    $actualHash = $null
    $actualBytes = $null
    if (Test-Path -LiteralPath $path -PathType Leaf) { $actualHash = Get-Gate13LowerSha256 -Path $path; $actualBytes = [int64](Get-Item -LiteralPath $path).Length }
    if ($actualHash -ne $row.sha256 -or $actualBytes -ne [int64]$row.bytes) { $baselineMismatches.Add([pscustomobject]@{ relativePath = $row.relative_path; expectedSha256 = $row.sha256; actualSha256 = $actualHash; expectedBytes = [int64]$row.bytes; actualBytes = $actualBytes }) }
}
if ($baselineRows.Count -ne 24 -or $baselineMismatches.Count -gt 0) { $errors.Add("Original baseline mismatch: checked=$($baselineRows.Count), mismatches=$($baselineMismatches.Count)") }

$gate12Root = Join-Path $ProjectPath 'Research\PilotRuns\Gate12\v1'
$gate12Files = @(Get-ChildItem -LiteralPath $gate12Root -File -Recurse)
$gate12KeyChecks = New-Object System.Collections.Generic.List[object]
foreach ($entry in @(
    [ordered]@{ relativePath = 'Research/PilotRuns/Gate12/v1/pilot-manifest.json'; expected = '638ac2e3fe243212ef031bdbed4c06394447e055c4d080be370357c41122e18a' },
    [ordered]@{ relativePath = 'Research/PilotRuns/Gate12/v1/candidate-sample-sizes.json'; expected = 'e0a32ee0545f722e46eb6c2a995f869db73944321be525e492c0dce6f3c05ff3' },
    [ordered]@{ relativePath = 'Research/PilotRuns/Gate12/v1/budget-feasibility.json'; expected = '5d1c380061deb2dd4c31f5b01fa48e7665eb405699ce67e1cfdc2b33a87f5f69' },
    [ordered]@{ relativePath = 'Research/Verification/Gate12_FinalAudit.summary.json'; expected = '87a5d93dead6dc367ab0716ad2e4e2239570fc42577be978d0f0378ca14f78c8' }
)) {
    $path = Join-Path $ProjectPath $entry.relativePath.Replace('/', '\')
    $actual = if (Test-Path -LiteralPath $path -PathType Leaf) { Get-Gate13LowerSha256 -Path $path } else { $null }
    $matches = $actual -eq $entry.expected
    $gate12KeyChecks.Add([pscustomobject][ordered]@{ relativePath = $entry.relativePath; expectedSha256 = $entry.expected; actualSha256 = $actual; matches = $matches })
    if (-not $matches) { $errors.Add("Gate 12 frozen evidence mismatch: $($entry.relativePath)") }
}
$gate12Final = Read-Gate13Json -Path (Join-Path $ProjectPath 'Research\Verification\Gate12_FinalAudit.summary.json')
if ($gate12Files.Count -ne 1694 -or $gate12Final.passed -ne $true) { $errors.Add("Gate 12 successful v1 evidence mismatch: files=$($gate12Files.Count), finalPassed=$($gate12Final.passed)") }
$gate12Preflights = @('environment-start.json', 'environment-post-warmup.json', 'environment-end.json')
foreach ($name in $gate12Preflights) {
    $path = Join-Path $gate12Root $name
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { $errors.Add("Gate 12 archived preflight evidence missing: $name") }
    else {
        $snapshot = Read-Gate13Json -Path $path
        if ($snapshot.preflightVerdict.passed -ne $true) { $errors.Add("Gate 12 archived preflight evidence is not passing: $name") }
    }
}

$unitSummary = Read-Gate13Json -Path (Join-Path $scriptDirectory 'Gate13_Preparation_UnitTests.summary.json')
if ($unitSummary.passed -ne $true -or [int]$unitSummary.total -ne 60 -or [int]$unitSummary.failedCount -ne 0) { $errors.Add('Gate 13 preparation unit-test evidence is not 60/60 passing.') }
$gate12UnitSummary = Read-Gate13Json -Path (Join-Path $scriptDirectory 'Gate12_AnalysisUnitTests.summary.json')
if ($gate12UnitSummary.passed -ne $true -or [int]$gate12UnitSummary.assertionCount -ne 63) { $errors.Add('Gate 12 analysis regression is not 63/63 passing.') }
$amendmentAudit = Read-Gate13Json -Path (Join-Path $scriptDirectory 'Gate13_Readiness_Amendment_Audit.summary.json')
if ($amendmentAudit.passed -ne $true) { $errors.Add('Gate 13 readiness amendment audit is not passing.') }

function Invoke-ValidationChild([string]$Label, [string[]]$Arguments) {
    $previous = $script:ErrorActionPreference
    $script:ErrorActionPreference = 'Continue'
    $output = & powershell @Arguments 2>&1
    $exitCode = $LASTEXITCODE
    $script:ErrorActionPreference = $previous
    if ($exitCode -ne 0) { $script:errors.Add("$Label failed with exit $exitCode`: $($output -join ' ')") }
    return [pscustomobject][ordered]@{ label = $Label; exitCode = $exitCode; passed = $exitCode -eq 0; outputTail = @($output | Select-Object -Last 12) }
}

$childResults = New-Object System.Collections.Generic.List[object]
$childResults.Add((Invoke-ValidationChild -Label 'deterministic-config-check-only' -Arguments @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $generatorPath, '-ProjectPath', $ProjectPath, '-CheckOnly')))
$childResults.Add((Invoke-ValidationChild -Label 'top-level-orchestrator-validation-only' -Arguments @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $orchestratorPath, '-ProjectPath', $ProjectPath, '-ValidationOnly')))
$childResults.Add((Invoke-ValidationChild -Label 'cap-148-scenario-validation-only' -Arguments @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $scenarioRunnerPath, '-ProjectPath', $ProjectPath, '-CampaignOrdinal', '2', '-ValidationOnly')))

$orchestratorText = [System.IO.File]::ReadAllText($orchestratorPath)
$authorizationIndex = $orchestratorText.IndexOf('Test-Gate13ExecutionAuthorization', [System.StringComparison]::Ordinal)
$launchPreflightIndex = $orchestratorText.IndexOf("-Purpose 'launch-after-authorization'", [System.StringComparison]::Ordinal)
$rootCreationIndex = $orchestratorText.IndexOf('New-Item -ItemType Directory -Path $formalRoot', [System.StringComparison]::Ordinal)
$staticSafetyChecks = [ordered]@{
    explicitParameterSets = $orchestratorText.Contains("ParameterSetName = 'ValidationOnly'") -and $orchestratorText.Contains("ParameterSetName = 'Execute'")
    authorizationBeforeLaunchPreflight = $authorizationIndex -ge 0 -and $launchPreflightIndex -gt $authorizationIndex
    launchPreflightImmediatelyBeforeRootCreation = $rootCreationIndex -gt $launchPreflightIndex -and $orchestratorText.Substring($launchPreflightIndex, $rootCreationIndex - $launchPreflightIndex) -notmatch 'New-Item|Start-Process|powershell.exe'
    noAutomaticRetry = $config.monitoring.automaticRetryAllowed -eq $false -and $config.output.automaticRetryAllowed -eq $false
    noAutomaticResume = $config.output.automaticResumeAllowed -eq $false -and $config.checkpoint.authorizesAutomaticResume -eq $false
    rawByteThresholdExact = [int64]$config.launchPreflight.minimumLaunchFreeBytes -eq 74417330489 -and $config.launchPreflight.comparisonUsesRawInt64Bytes -eq $true
}
foreach ($entry in $staticSafetyChecks.GetEnumerator()) { if (-not $entry.Value) { $errors.Add("Static safety check failed: $($entry.Key)") } }

$formalTrueJsonFiles = New-Object System.Collections.Generic.List[string]
foreach ($file in @(Get-ChildItem -LiteralPath (Join-Path $ProjectPath 'Research') -Filter '*.json' -File -Recurse)) {
    $text = [System.IO.File]::ReadAllText($file.FullName)
    if ($text -match '"formalCampaign"\s*:\s*true|"gate13ExecutionAuthorized"\s*:\s*true|"formalCampaignStartAllowed"\s*:\s*true') { $formalTrueJsonFiles.Add($file.FullName) }
}
if ($formalTrueJsonFiles.Count -gt 0) { $errors.Add("Formal true flags found in JSON evidence: $($formalTrueJsonFiles.Count)") }
$authorizationReceipts = @(Get-ChildItem -LiteralPath (Join-Path $ProjectPath 'Research') -Filter '*Gate13*Authorization*.json' -File -Recurse -ErrorAction SilentlyContinue)
if ($authorizationReceipts.Count -gt 0) { $errors.Add("Unexpected Gate 13 execution authorization receipt exists: $($authorizationReceipts.FullName -join ', ')") }

$rootPresentAfter = Test-Path -LiteralPath $formalRoot
$unityAfter = @(Get-Process -Name Unity -ErrorAction SilentlyContinue)
$lockAfter = Test-Path -LiteralPath (Join-Path $ProjectPath 'Temp\UnityLockfile')
if ($rootPresentAfter) { $errors.Add('Gate 13 formal root exists after validation.') }
if ($unityAfter.Count -gt 0) { $errors.Add('Unity is running after validation.') }
if ($lockAfter) { $errors.Add('Unity lockfile exists after validation.') }

$checks = [ordered]@{
    allResearchPowerShellParses = $powerShellParseErrors.Count -eq 0
    allResearchJsonParses = $jsonParseErrors.Count -eq 0
    configDeterministicAndHashBound = $configCheck.passed
    gate11RetainedBundleUnchanged = $bundleCheck.passed -and $bundleCheck.fileCount -eq 57 -and $bundleCheck.artifactCount -eq 56
    originalBaseline24Of24 = $baselineRows.Count -eq 24 -and $baselineMismatches.Count -eq 0
    gate12SuccessfulV1Unchanged = $gate12Files.Count -eq 1694 -and @($gate12KeyChecks.ToArray() | Where-Object { -not $_.matches }).Count -eq 0 -and $gate12Final.passed
    gate12ArchivedPreflightsPass = @($gate12Preflights | Where-Object { -not (Test-Path -LiteralPath (Join-Path $gate12Root $_) -PathType Leaf) }).Count -eq 0
    gate13UnitTests60Of60 = $unitSummary.passed -and [int]$unitSummary.total -eq 60
    gate12Regression63Of63 = $gate12UnitSummary.passed -and [int]$gate12UnitSummary.assertionCount -eq 63
    gate13AmendmentAuditPasses = $amendmentAudit.passed
    validationOnlyChildrenPass = @($childResults.ToArray() | Where-Object { -not $_.passed }).Count -eq 0
    staticAuthorizationPreflightOrderPasses = @($staticSafetyChecks.GetEnumerator() | Where-Object { -not $_.Value }).Count -eq 0
    noFormalTrueJson = $formalTrueJsonFiles.Count -eq 0
    noExecutionReceiptCreated = $authorizationReceipts.Count -eq 0
    noFormalRootBeforeOrAfter = -not $rootPresentBefore -and -not $rootPresentAfter
    noUnityBeforeOrAfter = $unityBefore.Count -eq 0 -and $unityAfter.Count -eq 0
    noUnityLockBeforeOrAfter = -not $lockBefore -and -not $lockAfter
}
$failedChecks = @($checks.GetEnumerator() | Where-Object { -not $_.Value } | ForEach-Object { $_.Key })
$passed = $errors.Count -eq 0 -and $failedChecks.Count -eq 0
$summary = [ordered]@{
    schemaVersion = 1
    validationId = 'gate13-nonexecuting-preparation-validation-v1'
    savedAt = (Get-Date).ToString('o')
    projectPath = $ProjectPath
    configSha256 = Get-Gate13LowerSha256 -Path $configPath
    amendmentSha256 = Get-Gate13LowerSha256 -Path (Join-Path $ProjectPath 'Research\Gate13_Readiness_Amendment.v1.json')
    powerShellFileCount = $powerShellFiles.Count
    powerShellParseErrors = $powerShellParseErrors.ToArray()
    jsonFileCount = $jsonFiles.Count
    jsonParseErrors = $jsonParseErrors.ToArray()
    bundle = $bundleCheck
    baselineChecked = $baselineRows.Count
    baselineMismatches = $baselineMismatches.ToArray()
    gate12V1FileCount = $gate12Files.Count
    gate12KeyChecks = $gate12KeyChecks.ToArray()
    childValidationResults = $childResults.ToArray()
    staticSafetyChecks = $staticSafetyChecks
    formalTrueJsonFiles = $formalTrueJsonFiles.ToArray()
    executionAuthorizationReceiptFiles = @($authorizationReceipts | ForEach-Object { $_.FullName })
    formalRootPresentBefore = $rootPresentBefore
    formalRootPresentAfter = $rootPresentAfter
    unityProcessIdsBefore = @($unityBefore | ForEach-Object { $_.Id })
    unityProcessIdsAfter = @($unityAfter | ForEach-Object { $_.Id })
    unityLockfilePresentBefore = $lockBefore
    unityLockfilePresentAfter = $lockAfter
    checks = $checks
    failedChecks = $failedChecks
    errors = $errors.ToArray()
    passed = $passed
}
Write-Gate13Utf8NoBomJson -Path $summaryPath -Value $summary -Depth 24
$summary | ConvertTo-Json -Depth 10
if (-not $passed) { Write-Error "Gate 13 preparation validation failed: $($failedChecks -join ', '); $($errors -join '; ')"; exit 1 }
Write-Host 'Gate 13 nonexecuting preparation validation passed; no formal root or Unity process was created.' -ForegroundColor Green
exit 0
