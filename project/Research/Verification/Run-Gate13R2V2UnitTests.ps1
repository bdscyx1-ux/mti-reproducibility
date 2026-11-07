[CmdletBinding()]
param([string]$ProjectPath = (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)))

$ErrorActionPreference = 'Stop'
$ProjectPath = [System.IO.Path]::GetFullPath($ProjectPath)
$researchPath = Join-Path $ProjectPath 'Research'
$modulePath = Join-Path $researchPath 'Gate13R2V2Preparation.psm1'
Import-Module $modulePath -Force
$summaryPath = Join-Path $PSScriptRoot 'Gate13R2_v2_UnitTests.summary.json'
$assertions = New-Object System.Collections.Generic.List[object]
$errors = New-Object System.Collections.Generic.List[string]

function Add-Assertion([string]$Name, [bool]$Passed, [string]$Detail) {
    $script:assertions.Add([pscustomobject][ordered]@{ name = $Name; passed = $Passed; detail = $Detail })
    if (-not $Passed) { $script:errors.Add("$Name`: $Detail") }
}

try {
    $planPath = Join-Path $researchPath 'Gate13R2_v2_Pilot_Plan.v1.json'
    $plan = Read-G13R2V2Json -Path $planPath
    $planTest = Test-G13R2V2PilotPlan -ProjectPath $ProjectPath -Plan $plan -PlanPath $planPath
    Add-Assertion 'pilot-plan-validation' ([bool]$planTest.passed) ($planTest.errors -join '; ')
    $jsonA = ConvertTo-G13R2V2JsonText -Value $plan -Depth 60
    $jsonB = ConvertTo-G13R2V2JsonText -Value $plan -Depth 60
    Add-Assertion 'json-determinism' ([string]::Equals($jsonA, $jsonB, [StringComparison]::Ordinal)) 'Repeated serialization must be byte-identical.'

    $inside = Test-G13R2V2TelemetryComparison -NativeBefore 100000000 -NativeAfter 120000000 -External 110000000
    Add-Assertion 'telemetry-inside-interval' ([bool]$inside.passed -and [long]$inside.distanceBytes -eq 0) 'External value inside native interval must pass at distance zero.'
    $atTolerance = Test-G13R2V2TelemetryComparison -NativeBefore 100000000 -NativeAfter 100000000 -External 167108864
    Add-Assertion 'telemetry-at-absolute-tolerance' ([bool]$atTolerance.passed -and [long]$atTolerance.distanceBytes -eq 67108864) 'Exactly 64 MiB distance must pass.'
    $beyondTolerance = Test-G13R2V2TelemetryComparison -NativeBefore 100000000 -NativeAfter 100000000 -External 167108865
    Add-Assertion 'telemetry-beyond-tolerance' (-not [bool]$beyondTolerance.passed) 'One byte beyond the applicable tolerance must fail.'
    $nonPositive = Test-G13R2V2TelemetryComparison -NativeBefore 0 -NativeAfter 100000000 -External 100000000
    Add-Assertion 'telemetry-non-positive' (-not [bool]$nonPositive.passed) 'A non-positive capture must fail.'

    $managedNegative = Test-G13R2V2ManagedMemoryRule -BeforeBytes 300000000 -RawAfterBytes 500000000 -AfterCleanupBytes 250000000
    Add-Assertion 'managed-negative-growth' ([bool]$managedNegative.passed) 'Negative retained growth must pass.'
    $managedExact = Test-G13R2V2ManagedMemoryRule -BeforeBytes 100000000 -RawAfterBytes 400000000 -AfterCleanupBytes 234217728
    Add-Assertion 'managed-exact-128mib' ([bool]$managedExact.passed -and [long]$managedExact.retainedGrowthBytes -eq 134217728) 'Exactly 128 MiB retained growth must pass.'
    $managedOver = Test-G13R2V2ManagedMemoryRule -BeforeBytes 100000000 -RawAfterBytes 400000000 -AfterCleanupBytes 234217729
    Add-Assertion 'managed-128mib-plus-one' (-not [bool]$managedOver.passed) '128 MiB plus one byte must fail.'
    $rawHighCleanupLow = Test-G13R2V2ManagedMemoryRule -BeforeBytes 100000000 -RawAfterBytes 500000000 -AfterCleanupBytes 110000000
    Add-Assertion 'managed-raw-diagnostic-only' ([bool]$rawHighCleanupLow.passed -and [long]$rawHighCleanupLow.rawGrowthBytes -gt 134217728) 'A high raw peak with low post-cleanup retention must pass.'

    $candidateZero = Get-G13R2V2SampleSizeCandidate -SigmaLog 0
    Add-Assertion 'sample-size-minimum' ([long]$candidateZero.requiredNFormal -eq 32 -and [long]$candidateZero.candidateNFormal -eq 32) 'Minimum 30 rounds to one complete four-block cycle (32).'
    $candidateOver = Get-G13R2V2SampleSizeCandidate -SigmaLog 2
    Add-Assertion 'sample-size-over-cap' ([bool]$candidateOver.overCap -and [long]$candidateOver.candidateNFormal -eq 148 -and [long]$candidateOver.requiredNFormal -gt 148) 'Over-cap requirement must preserve raw required n and cap candidate at 148.'

    $four = @('A*-R', 'D*L', 'C-FF', 'IDFF')
    $fourRows = for ($block = 1; $block -le 4; $block++) { ,@(Get-G13R2V2WilliamsRow -Algorithms $four -Block $block) }
    $positionCounts = @{}
    $predecessorCounts = @{}
    for ($r = 0; $r -lt $fourRows.Count; $r++) {
        for ($p = 0; $p -lt 4; $p++) {
            $key = "$($fourRows[$r][$p])|$($p + 1)"; $positionCounts[$key] = 1 + [int]$positionCounts[$key]
            if ($p -gt 0) { $key = "$($fourRows[$r][$p - 1])|$($fourRows[$r][$p])"; $predecessorCounts[$key] = 1 + [int]$predecessorCounts[$key] }
        }
    }
    Add-Assertion 'williams-four-position-balance' (@($positionCounts.Values | Where-Object { $_ -ne 1 }).Count -eq 0 -and $positionCounts.Count -eq 16) 'Four-row cycle must place every algorithm once in every position.'
    Add-Assertion 'williams-four-predecessor-balance' (@($predecessorCounts.Values | Where-Object { $_ -ne 1 }).Count -eq 0 -and $predecessorCounts.Count -eq 12) 'Four-row cycle must cover each ordered distinct predecessor pair once.'
    $two = @('A*-R', 'D*L')
    $twoRows = for ($block = 1; $block -le 2; $block++) { ,@(Get-G13R2V2WilliamsRow -Algorithms $two -Block $block) }
    Add-Assertion 'williams-two-balance' (($twoRows[0] -join '|') -eq 'A*-R|D*L' -and ($twoRows[1] -join '|') -eq 'D*L|A*-R') 'Two-row cycle must reverse order.'

    $validEntries = for ($i = 0; $i -lt 4; $i++) { [pscustomobject][ordered]@{ position = $i + 1; algorithmId = $fourRows[0][$i]; predecessorAlgorithmId = if ($i -eq 0) { 'NONE' } else { $fourRows[0][$i - 1] }; runId = "unit-b001-p$($i + 1)"; directory = "runs/p$($i + 1)" } }
    $validPlan = [pscustomobject][ordered]@{ schemaVersion = 2; designId = 'one-fresh-unity-process-per-williams-block-v2-native-telemetry'; planId = 'unit-plan'; blockId = 'unit-block'; campaignId = 'unit-campaign'; block = 1; formalCampaign = $false; analysisRole = 'verification'; verificationInjectedFailurePosition = 0; comparisonCohortId = 'four-algorithm-shared-goal-v1'; entries = $validEntries }
    Add-Assertion 'block-plan-valid' ([bool](Test-G13R2V2BlockPlanObject -Plan $validPlan).passed) 'Valid block-plan vector must pass.'
    $duplicate = $validPlan | ConvertTo-Json -Depth 20 | ConvertFrom-Json
    $duplicate.entries[1].directory = $duplicate.entries[0].directory
    Add-Assertion 'block-plan-duplicate-directory-rejected' (-not [bool](Test-G13R2V2BlockPlanObject -Plan $duplicate).passed) 'Duplicate child directory must be rejected by static validation.'
    $wrongPredecessor = $validPlan | ConvertTo-Json -Depth 20 | ConvertFrom-Json
    $wrongPredecessor.entries[2].predecessorAlgorithmId = 'NONE'
    Add-Assertion 'block-plan-wrong-predecessor-rejected' (-not [bool](Test-G13R2V2BlockPlanObject -Plan $wrongPredecessor).passed) 'Wrong predecessor must be rejected.'
    $escaping = $validPlan | ConvertTo-Json -Depth 20 | ConvertFrom-Json
    $escaping.entries[2].directory = '../escape'
    Add-Assertion 'block-plan-escape-rejected' (-not [bool](Test-G13R2V2BlockPlanObject -Plan $escaping).passed) 'Escaping child path must be rejected.'

    $sourcePath = Join-Path $ProjectPath 'Assets\_Scripts\Research\Editor\ResearchPlanningProcessReuseBatchCommandV2.cs'
    $source = Get-Content -LiteralPath $sourcePath -Raw
    Add-Assertion 'source-native-api' ($source.Contains('GetProcessMemoryInfo') -and $source.Contains('PROCESS_MEMORY_COUNTERS_EX') -and $source.Contains('WorkingSetSize') -and $source.Contains('PrivateUsage')) 'V2 source must contain the frozen native API/field mappings.'
    Add-Assertion 'source-no-authoritative-process-properties' (-not $source.Contains('process.WorkingSet64') -and -not $source.Contains('process.PrivateMemorySize64')) 'V2 source must not use v1 zero-valued Process memory properties.'
    Add-Assertion 'source-no-inline-cleanup-boundary' ($source.Contains('[MethodImpl(MethodImplOptions.NoInlining)]') -and $source.Contains('telemetryAfterCleanup')) 'V2 source must expose a non-inlined post-return cleanup boundary.'
    $mutableStaticMatches = @(Select-String -LiteralPath $sourcePath -Pattern '^\s*private static (?!readonly|extern|void|[A-Za-z0-9_<>\[\]]+\s+[A-Za-z0-9_]+\s*\()' -CaseSensitive)
    Add-Assertion 'source-no-mutable-static-state' ($mutableStaticMatches.Count -eq 0) "Unexpected mutable static declarations: $($mutableStaticMatches.Count)."

    Add-Assertion 'formal-root-absent' (-not (Test-Path -LiteralPath (Join-Path $ProjectPath 'Research\FormalRuns\Gate13_ProcessReuse\v1'))) 'Process-reuse formal root must remain absent.'
} catch {
    $errors.Add($_.Exception.ToString())
}

$summary = [ordered]@{
    schemaVersion = 1
    summaryKind = 'gate13-r2-v2-unit-and-static-tests-v1'
    savedAtUtc = [DateTime]::UtcNow.ToString('o')
    assertionCount = $assertions.Count
    passedAssertionCount = @($assertions | Where-Object passed).Count
    failedAssertionCount = @($assertions | Where-Object { -not $_.passed }).Count
    assertions = $assertions.ToArray()
    errors = $errors.ToArray()
    formalCampaign = $false
    automaticRetryAttempted = $false
    automaticResumeAttempted = $false
    passed = $errors.Count -eq 0 -and @($assertions | Where-Object { -not $_.passed }).Count -eq 0
}
Write-G13R2V2AtomicUtf8NoBomJson -Path $summaryPath -Value $summary -Depth 40
$summary | ConvertTo-Json -Depth 8
if (-not $summary.passed) { exit 1 }
exit 0
