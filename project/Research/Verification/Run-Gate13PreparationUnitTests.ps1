[CmdletBinding()]
param([string]$ProjectPath)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0
$scriptDirectory = Split-Path -Parent $MyInvocation.MyCommand.Path
if ([string]::IsNullOrWhiteSpace($ProjectPath)) { $ProjectPath = [System.IO.Path]::GetFullPath((Join-Path $scriptDirectory '..\..')) }
else { $ProjectPath = [System.IO.Path]::GetFullPath($ProjectPath) }
$modulePath = Join-Path $ProjectPath 'Research\Gate13FormalPreparation.psm1'
$configPath = Join-Path $ProjectPath 'Research\Gate13_Formal_Campaign_Config.v1.json'
$summaryPath = Join-Path $scriptDirectory 'Gate13_Preparation_UnitTests.summary.json'
$formalRoot = Join-Path $ProjectPath 'Research\FormalRuns\Gate13\v1'
Import-Module $modulePath -Force
$config = Read-Gate13Json -Path $configPath
$tests = New-Object System.Collections.Generic.List[object]

function Add-TestResult([string]$Name, [bool]$Passed, [string]$Detail) {
    $tests.Add([pscustomobject][ordered]@{ name = $Name; passed = $Passed; detail = $Detail })
}

function Assert-True([string]$Name, [bool]$Condition, [string]$Detail) {
    Add-TestResult -Name $Name -Passed $Condition -Detail $Detail
}

function Assert-Throws([string]$Name, [scriptblock]$Action, [string]$Pattern) {
    $threw = $false
    $message = $null
    try { & $Action } catch { $threw = $true; $message = $_.Exception.Message }
    $passed = $threw -and ([string]::IsNullOrWhiteSpace($Pattern) -or $message -match $Pattern)
    Add-TestResult -Name $Name -Passed $passed -Detail $(if ($threw) { $message } else { 'did not throw' })
}

$rootPresentBefore = Test-Path -LiteralPath $formalRoot
Assert-True 'formal-root-absent-before' (-not $rootPresentBefore) "present=$rootPresentBefore"

$shared = New-Gate13WilliamsSchedule -CampaignId 'unit-shared' -ComparisonCohortId 'four-algorithm-shared-goal-v1' -Blocks 52
Assert-True 'shared-sample-count-208' ($shared.sampleCount -eq 208) "actual=$($shared.sampleCount)"
Assert-True 'shared-cycle-count-13' ($shared.completeBalanceCycleCount -eq 13) "actual=$($shared.completeBalanceCycleCount)"
Assert-True 'shared-position-balanced' ($shared.positionBalanced -eq $true) 'four algorithms x four positions'
Assert-True 'shared-predecessor-balanced' ($shared.orderedPredecessorBalanced -eq $true) 'all directed adjacent pairs'
Assert-True 'shared-position-counts-13' (@($shared.positionCounts.GetEnumerator() | ForEach-Object { $_.Value.Values } | Where-Object { $_ -ne 13 }).Count -eq 0) 'all position counts must be 13'
Assert-True 'shared-predecessor-counts-13' (@($shared.orderedPredecessorCounts.Values | Where-Object { $_ -ne 13 }).Count -eq 0) 'all predecessor counts must be 13'

$perAgent = New-Gate13WilliamsSchedule -CampaignId 'unit-per-agent' -ComparisonCohortId 'per-agent-heterogeneous-goal-v1' -Blocks 148
Assert-True 'per-agent-sample-count-296' ($perAgent.sampleCount -eq 296) "actual=$($perAgent.sampleCount)"
Assert-True 'per-agent-cycle-count-74' ($perAgent.completeBalanceCycleCount -eq 74) "actual=$($perAgent.completeBalanceCycleCount)"
Assert-True 'per-agent-position-counts-74' (@($perAgent.positionCounts.GetEnumerator() | ForEach-Object { $_.Value.Values } | Where-Object { $_ -ne 74 }).Count -eq 0) 'all position counts must be 74'
Assert-True 'per-agent-predecessor-counts-74' (@($perAgent.orderedPredecessorCounts.Values | Where-Object { $_ -ne 74 }).Count -eq 0) 'both directed pairs must be 74'

$grouped = New-Gate13WilliamsSchedule -CampaignId 'unit-grouped' -ComparisonCohortId 'grouped-field-heterogeneous-goal-v1' -Blocks 52
Assert-True 'grouped-sample-count-104' ($grouped.sampleCount -eq 104) "actual=$($grouped.sampleCount)"
Assert-True 'grouped-cycle-count-26' ($grouped.completeBalanceCycleCount -eq 26) "actual=$($grouped.completeBalanceCycleCount)"
$perAgentAgain = New-Gate13WilliamsSchedule -CampaignId 'unit-per-agent' -ComparisonCohortId 'per-agent-heterogeneous-goal-v1' -Blocks 148
Assert-True 'schedule-deterministic-sha' ($perAgent.canonicalScheduleSha256 -eq $perAgentAgain.canonicalScheduleSha256) $perAgent.canonicalScheduleSha256
Assert-Throws 'schedule-rejects-zero-blocks' { New-Gate13WilliamsSchedule -CampaignId 'bad' -ComparisonCohortId 'per-agent-heterogeneous-goal-v1' -Blocks 0 } 'Blocks'
Assert-Throws 'schedule-rejects-incomplete-cycle' { New-Gate13WilliamsSchedule -CampaignId 'bad' -ComparisonCohortId 'per-agent-heterogeneous-goal-v1' -Blocks 147 } 'multiple'
Assert-Throws 'schedule-rejects-over-cap' { New-Gate13WilliamsSchedule -CampaignId 'bad' -ComparisonCohortId 'per-agent-heterogeneous-goal-v1' -Blocks 149 } '1..148'
Assert-Throws 'schedule-rejects-unknown-cohort' { New-Gate13WilliamsSchedule -CampaignId 'bad' -ComparisonCohortId 'unknown' -Blocks 2 } 'Unsupported'
Assert-Throws 'williams-rejects-odd-count' { Get-Gate13WilliamsBaseIndices -Count 3 } 'even'

$configCheck = Test-Gate13FormalConfig -ProjectPath $ProjectPath -Config $config -ConfigPath $configPath
Assert-True 'config-deterministic-validation' $configCheck.passed ($configCheck.errors -join '; ')
Assert-True 'config-campaign-count-74' (@($config.campaigns).Count -eq 74) "actual=$(@($config.campaigns).Count)"
Assert-True 'config-total-samples-15056' ([int]$config.totals.expectedUnityProcessCount -eq 15056) "actual=$($config.totals.expectedUnityProcessCount)"
$sharedCampaigns = @($config.campaigns | Where-Object comparisonCohortId -eq 'four-algorithm-shared-goal-v1')
$perAgentCampaigns = @($config.campaigns | Where-Object comparisonCohortId -eq 'per-agent-heterogeneous-goal-v1')
$groupedCampaigns = @($config.campaigns | Where-Object comparisonCohortId -eq 'grouped-field-heterogeneous-goal-v1')
Assert-True 'config-cohort-campaign-counts-32-21-21' ($sharedCampaigns.Count -eq 32 -and $perAgentCampaigns.Count -eq 21 -and $groupedCampaigns.Count -eq 21) "$($sharedCampaigns.Count)/$($perAgentCampaigns.Count)/$($groupedCampaigns.Count)"
Assert-True 'config-block-levels-52-148-52' (@($sharedCampaigns | Where-Object blockCount -ne 52).Count -eq 0 -and @($perAgentCampaigns | Where-Object blockCount -ne 148).Count -eq 0 -and @($groupedCampaigns | Where-Object blockCount -ne 52).Count -eq 0) 'cohort block levels'
Assert-True 'config-cohort-samples-6656-6216-2184' ((($sharedCampaigns | Measure-Object sampleCount -Sum).Sum -eq 6656) -and (($perAgentCampaigns | Measure-Object sampleCount -Sum).Sum -eq 6216) -and (($groupedCampaigns | Measure-Object sampleCount -Sum).Sum -eq 2184)) 'cohort sample totals'
Assert-True 'config-unique-campaign-ids' (@($config.campaigns.campaignId | Sort-Object -Unique).Count -eq 74) '74 unique campaign IDs'
Assert-True 'config-unique-output-paths' (@($config.campaigns.outputRelativePath | Sort-Object -Unique).Count -eq 74) '74 unique campaign output paths'
Assert-True 'config-execution-flags-false' ($config.authorizationBoundary.gate13ExecutionAuthorized -eq $false -and $config.authorizationBoundary.formalCampaignStartAllowed -eq $false -and $config.authorizationBoundary.configurationMayAuthorizeExecution -eq $false) 'config cannot authorize formal execution'
Assert-True 'config-cap-148-independent-layer' ([int]$config.scheduleDesign.maximumBlocksSupported -eq 148 -and [int]$config.frozenInputs.gate10CampaignRunner.maximumBlocks -eq 100 -and $config.frozenInputs.gate10CampaignRunner.modifiedForGate13 -eq $false) 'new layer supports 148; Gate 10 remains 100'
$allRunIds = New-Object System.Collections.Generic.List[string]
$scheduleMismatchCount = 0
foreach ($campaign in @($config.campaigns)) {
    $expanded = New-Gate13WilliamsSchedule -CampaignId $campaign.campaignId -ComparisonCohortId $campaign.comparisonCohortId -Blocks ([int]$campaign.blockCount)
    if ($expanded.canonicalScheduleSha256 -ne $campaign.canonicalScheduleSha256 -or $expanded.sampleCount -ne $campaign.sampleCount) { $scheduleMismatchCount++ }
    foreach ($entry in @($expanded.entries)) { $allRunIds.Add([string]$entry.runId) }
}
Assert-True 'all-campaign-schedule-hashes-recompute' ($scheduleMismatchCount -eq 0) "mismatches=$scheduleMismatchCount"
Assert-True 'all-15056-run-ids-unique' ($allRunIds.Count -eq 15056 -and @($allRunIds.ToArray() | Sort-Object -Unique).Count -eq 15056) "count=$($allRunIds.Count)"
$expected1 = New-Gate13FormalConfig -ProjectPath $ProjectPath
$expected2 = New-Gate13FormalConfig -ProjectPath $ProjectPath
$expectedText1 = ConvertTo-Gate13JsonText -Value $expected1 -Depth 30
$expectedText2 = ConvertTo-Gate13JsonText -Value $expected2 -Depth 30
Assert-True 'config-generation-byte-deterministic' ([string]::Equals($expectedText1, $expectedText2, [System.StringComparison]::Ordinal)) (Get-Gate13StringSha256 -Value $expectedText1)

$tampered = $config | ConvertTo-Json -Depth 30 | ConvertFrom-Json
$tampered.campaigns[0].blockCount = 48
$tamperedCheck = Test-Gate13FormalConfig -ProjectPath $ProjectPath -Config $tampered
Assert-True 'config-tamper-block-rejected' (-not $tamperedCheck.passed) ($tamperedCheck.errors -join '; ')
$tampered = $config | ConvertTo-Json -Depth 30 | ConvertFrom-Json
$tampered.frozenInputs.gate13Amendment.sha256 = ('0' * 64)
$tamperedText = ConvertTo-Gate13JsonText -Value $tampered -Depth 30
Assert-True 'config-tamper-amendment-rejected' (-not [string]::Equals($tamperedText, $expectedText1, [System.StringComparison]::Ordinal)) 'canonical deterministic bytes differ'
$tampered = $config | ConvertTo-Json -Depth 30 | ConvertFrom-Json
$tampered.authorizationBoundary.gate13ExecutionAuthorized = $true
$tamperedText = ConvertTo-Gate13JsonText -Value $tampered -Depth 30
Assert-True 'config-tamper-execution-flag-rejected' (-not [string]::Equals($tamperedText, $expectedText1, [System.StringComparison]::Ordinal)) 'canonical deterministic bytes differ'
$tampered = $config | ConvertTo-Json -Depth 30 | ConvertFrom-Json
$tampered.output.rootRelativePath = 'Research/FormalRuns/Gate13/escape'
$tamperedText = ConvertTo-Gate13JsonText -Value $tampered -Depth 30
Assert-True 'config-tamper-output-root-rejected' (-not [string]::Equals($tamperedText, $expectedText1, [System.StringComparison]::Ordinal)) 'canonical deterministic bytes differ'

$minimum = [int64]74417330489
$below = Test-Gate13RawByteStorage -OutputRoot $formalRoot -MinimumFreeBytes $minimum -FreeBytesOverride ([int64]($minimum - 1))
$equal = Test-Gate13RawByteStorage -OutputRoot $formalRoot -MinimumFreeBytes $minimum -FreeBytesOverride $minimum
$above = Test-Gate13RawByteStorage -OutputRoot $formalRoot -MinimumFreeBytes $minimum -FreeBytesOverride ([int64]($minimum + 1))
Assert-True 'storage-minimum-minus-one-fails' (-not $below.passed) "margin=$($below.marginBytes)"
Assert-True 'storage-minimum-equal-passes' $equal.passed "margin=$($equal.marginBytes)"
Assert-True 'storage-minimum-plus-one-passes' $above.passed "margin=$($above.marginBytes)"
Assert-True 'storage-never-confers-authorization' (-not $below.launchAuthorizationConferred -and -not $equal.launchAuthorizationConferred -and -not $above.launchAuthorizationConferred) 'storage verdict is not authorization'
$negative = Test-Gate13RawByteStorage -OutputRoot $formalRoot -MinimumFreeBytes $minimum -FreeBytesOverride ([int64]-1)
Assert-True 'storage-negative-rejected' (-not $negative.passed) ($negative.errors -join '; ')
$fractional = Test-Gate13RawByteStorage -OutputRoot $formalRoot -MinimumFreeBytes $minimum -FreeBytesOverride ([double]$minimum)
Assert-True 'storage-floating-value-rejected' (-not $fractional.passed) ($fractional.errors -join '; ')

$configSha = Get-Gate13LowerSha256 -Path $configPath
$amendmentSha = [string]$config.frozenInputs.gate13Amendment.sha256
$validAuthorization = [pscustomobject][ordered]@{
    schemaVersion = 1
    authorizationKind = 'gate13-formal-execution-authorization-v1'
    authorizationId = 'synthetic-unit-test-only'
    gate13ExecutionAuthorized = $true
    formalCampaignStartAllowed = $true
    configSha256 = $configSha
    amendmentSha256 = $amendmentSha
    outputRootRelativePath = [string]$config.output.rootRelativePath
    userAuthorizationReference = 'synthetic-in-memory-unit-test-not-an-execution-receipt'
    authorizedAt = '2026-10-06T00:00:00+08:00'
}
$authorizationCheck = Test-Gate13ExecutionAuthorization -Authorization $validAuthorization -ExpectedConfigSha256 $configSha -ExpectedAmendmentSha256 $amendmentSha -ExpectedOutputRootRelativePath $config.output.rootRelativePath
Assert-True 'authorization-complete-synthetic-object-validates' $authorizationCheck.passed ($authorizationCheck.errors -join '; ')
$missingAuthorizationCheck = Test-Gate13ExecutionAuthorization -Authorization ([pscustomobject]@{}) -ExpectedConfigSha256 $configSha -ExpectedAmendmentSha256 $amendmentSha -ExpectedOutputRootRelativePath $config.output.rootRelativePath
Assert-True 'authorization-empty-object-rejected' (-not $missingAuthorizationCheck.passed) ($missingAuthorizationCheck.errors -join '; ')
foreach ($mutation in @('false-flag', 'wrong-kind', 'wrong-config', 'wrong-amendment', 'wrong-root', 'empty-reference')) {
    $candidate = $validAuthorization | ConvertTo-Json -Depth 8 | ConvertFrom-Json
    switch ($mutation) {
        'false-flag' { $candidate.gate13ExecutionAuthorized = $false }
        'wrong-kind' { $candidate.authorizationKind = 'wrong' }
        'wrong-config' { $candidate.configSha256 = '0' * 64 }
        'wrong-amendment' { $candidate.amendmentSha256 = '0' * 64 }
        'wrong-root' { $candidate.outputRootRelativePath = 'Research/FormalRuns/Gate13/wrong' }
        'empty-reference' { $candidate.userAuthorizationReference = '' }
    }
    $check = Test-Gate13ExecutionAuthorization -Authorization $candidate -ExpectedConfigSha256 $configSha -ExpectedAmendmentSha256 $amendmentSha -ExpectedOutputRootRelativePath $config.output.rootRelativePath
    Assert-True "authorization-$mutation-rejected" (-not $check.passed) ($check.errors -join '; ')
}

$inside = Join-Path $formalRoot 'campaigns\c001'
$prefixCollision = $formalRoot + '-other\campaigns\c001'
Assert-True 'path-containment-accepts-child' (Test-Gate13PathWithin -CandidatePath $inside -RootPath $formalRoot) $inside
Assert-True 'path-containment-rejects-prefix-collision' (-not (Test-Gate13PathWithin -CandidatePath $prefixCollision -RootPath $formalRoot)) $prefixCollision
Assert-True 'path-containment-rejects-root-without-switch' (-not (Test-Gate13PathWithin -CandidatePath $formalRoot -RootPath $formalRoot)) $formalRoot

$continueDecision = Get-Gate13MonitorDecision -ElapsedSeconds 10 -NoGrowthChecks 0 -HardTimeoutSeconds 10800 -OutputStallChecks 3
$stallDecision = Get-Gate13MonitorDecision -ElapsedSeconds 90 -NoGrowthChecks 3 -HardTimeoutSeconds 10800 -OutputStallChecks 3
$timeoutDecision = Get-Gate13MonitorDecision -ElapsedSeconds 10800 -NoGrowthChecks 0 -HardTimeoutSeconds 10800 -OutputStallChecks 3
Assert-True 'monitor-continue' ($continueDecision.action -eq 'continue' -and -not $continueDecision.mayTerminateOwnedProcessTree) $continueDecision.action
Assert-True 'monitor-stall-advisory-no-kill' ($stallDecision.action -eq 'output-stall-advisory' -and -not $stallDecision.mayTerminateOwnedProcessTree -and -not $stallDecision.autoRetryAllowed) $stallDecision.action
Assert-True 'monitor-hard-timeout-owned-kill-no-retry' ($timeoutDecision.action -eq 'hard-timeout' -and $timeoutDecision.mayTerminateOwnedProcessTree -and -not $timeoutDecision.autoRetryAllowed) $timeoutDecision.action

$missingReceiptPath = Join-Path $ProjectPath 'Research\Verification\does-not-exist-gate13-authorization.json'
$orchestratorPath = Join-Path $ProjectPath 'Research\Run-Gate13FormalCampaign.ps1'
$previousErrorActionPreference = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
$negativeOutput = & powershell -NoProfile -ExecutionPolicy Bypass -File $orchestratorPath -ProjectPath $ProjectPath -ConfigPath $configPath -Execute -ExecutionAuthorizationPath $missingReceiptPath 2>&1
$negativeExitCode = $LASTEXITCODE
$ErrorActionPreference = $previousErrorActionPreference
Assert-True 'execute-without-receipt-fails-before-root' ($negativeExitCode -ne 0 -and -not (Test-Path -LiteralPath $formalRoot)) "exit=$negativeExitCode; output=$($negativeOutput -join ' ')"

$rootPresentAfter = Test-Path -LiteralPath $formalRoot
$unityProcesses = @(Get-Process -Name Unity -ErrorAction SilentlyContinue)
$lockPresent = Test-Path -LiteralPath (Join-Path $ProjectPath 'Temp\UnityLockfile')
Assert-True 'formal-root-absent-after' (-not $rootPresentAfter) "present=$rootPresentAfter"
Assert-True 'no-unity-process-after-unit-tests' ($unityProcesses.Count -eq 0) "ids=$(@($unityProcesses | ForEach-Object { $_.Id }) -join ',')"
Assert-True 'no-unity-lock-after-unit-tests' (-not $lockPresent) "present=$lockPresent"

$failed = @($tests.ToArray() | Where-Object { -not $_.passed })
$summary = [ordered]@{
    schemaVersion = 1
    testSuiteId = 'gate13-nonexecuting-preparation-unit-tests-v1'
    savedAt = (Get-Date).ToString('o')
    projectPath = $ProjectPath
    total = $tests.Count
    passedCount = $tests.Count - $failed.Count
    failedCount = $failed.Count
    formalRootPresentBefore = $rootPresentBefore
    formalRootPresentAfter = $rootPresentAfter
    unityProcessIdsAfter = @($unityProcesses | ForEach-Object { $_.Id })
    unityLockfilePresentAfter = $lockPresent
    tests = $tests.ToArray()
    failedTests = @($failed | ForEach-Object { $_.name })
    passed = $failed.Count -eq 0
}
Write-Gate13Utf8NoBomJson -Path $summaryPath -Value $summary -Depth 20
$summary | ConvertTo-Json -Depth 8
if ($failed.Count -gt 0) { Write-Error "Gate 13 preparation unit tests failed: $($summary.failedTests -join ', ')"; exit 1 }
Write-Host "Gate 13 preparation unit tests passed: $($tests.Count)/$($tests.Count)." -ForegroundColor Green
exit 0
