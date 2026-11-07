[CmdletBinding()]
param(
    [string]$ProjectPath
)

$ErrorActionPreference = 'Stop'
$scriptDirectory = Split-Path -Parent $MyInvocation.MyCommand.Path
if ([string]::IsNullOrWhiteSpace($ProjectPath)) { $ProjectPath = [System.IO.Path]::GetFullPath((Join-Path $scriptDirectory '..\..')) }
else { $ProjectPath = [System.IO.Path]::GetFullPath($ProjectPath) }

$modulePath = Join-Path $ProjectPath 'Research\Gate12PilotAnalysis.psm1'
$planPath = Join-Path $ProjectPath 'Research\Gate12_Pilot_Plan.v1.json'
$preAuditPath = Join-Path $scriptDirectory 'Gate12_PreImplementationAudit.summary.json'
$summaryPath = Join-Path $scriptDirectory 'Gate12_AnalysisUnitTests.summary.json'
Import-Module $modulePath -Force

function Write-Utf8NoBomJson([string]$Path, $Value, [int]$Depth = 14) {
    $json = $Value | ConvertTo-Json -Depth $Depth
    $json = $json.Replace("`r`n", "`n").Replace("`r", "`n")
    if (-not $json.EndsWith("`n", [System.StringComparison]::Ordinal)) { $json += "`n" }
    $encoding = New-Object System.Text.UTF8Encoding($false, $true)
    [System.IO.File]::WriteAllText($Path, $json, $encoding)
}

$assertions = 0
$failures = New-Object System.Collections.Generic.List[string]
function Assert-True([bool]$Condition, [string]$Message) {
    $script:assertions++
    if (-not $Condition) { $script:failures.Add($Message) }
}
function Assert-Near([double]$Actual, [double]$Expected, [double]$Tolerance, [string]$Message) {
    $script:assertions++
    if ([double]::IsNaN($Actual) -or [math]::Abs($Actual - $Expected) -gt $Tolerance) { $script:failures.Add("$Message Expected=$Expected Actual=$Actual") }
}
function Assert-Throws([scriptblock]$Action, [string]$Message) {
    $script:assertions++
    $threw = $false
    try { & $Action | Out-Null } catch { $threw = $true }
    if (-not $threw) { $script:failures.Add($Message) }
}

$plan = Get-Content -LiteralPath $planPath -Raw -Encoding UTF8 | ConvertFrom-Json
$preAudit = Get-Content -LiteralPath $preAuditPath -Raw -Encoding UTF8 | ConvertFrom-Json
Assert-True ($preAudit.passed -eq $true -and $preAudit.auditMode -eq 'pre-implementation-freeze') 'Pre-implementation audit evidence is not passing.'
Assert-True ((Get-Gate12LowerSha256 $planPath) -eq $preAudit.frozenFiles.pilotPlan.sha256) 'Frozen pilot plan hash changed after pre-implementation audit.'
Assert-True ((Get-Gate12LowerSha256 (Join-Path $ProjectPath 'Research\Gate12_Pilot_Noise_and_Sample_Size_Specification.md')) -eq $preAudit.frozenFiles.specification.sha256) 'Frozen specification hash changed.'
Assert-True ((Get-Gate12LowerSha256 (Join-Path $ProjectPath 'Research\Gate12_Pilot_Test_Design.md')) -eq $preAudit.frozenFiles.testDesign.sha256) 'Frozen test-design hash changed.'
Assert-True ($plan.pilotSubset.scenarios.Count -eq 8 -and $plan.measuredCampaigns.Count -eq 12) 'Frozen scenario/campaign counts differ.'
Assert-True (($plan.measuredCampaigns | Measure-Object expectedSampleCount -Sum).Sum -eq 256) 'Measured process count does not sum to 256.'
Assert-True ($plan.formalCampaign -eq $false -and $plan.gate13ExecutionAuthorized -eq $false) 'Plan authorizes formal/Gate 13 execution.'

$sdZero = Get-Gate12SampleStandardDeviation -Values @(1.0, 1.0, 1.0, 1.0)
Assert-Near $sdZero 0.0 1e-12 'Identical-value sample SD mismatch.'
$logFixture = @(0.0, 1.0, 2.0, 3.0)
$sdFixture = Get-Gate12SampleStandardDeviation -Values $logFixture
Assert-Near $sdFixture ([math]::Sqrt(5.0 / 3.0)) 1e-12 'Bessel sample SD fixture mismatch.'
$endpointFixture = @(1.0, [math]::Exp(1.0), [math]::Exp(2.0), [math]::Exp(3.0))
$endpointLogs = @($endpointFixture | ForEach-Object { [math]::Log($_) })
Assert-Near (Get-Gate12SampleStandardDeviation -Values $endpointLogs) ([math]::Sqrt(5.0 / 3.0)) 1e-12 'Natural-log transform fixture mismatch.'
Assert-Near (Get-Gate12Median -Values @(4.0, 1.0, 3.0, 2.0)) 2.5 1e-12 'Even median mismatch.'
Assert-Near (Get-Gate12NearestRankPercentile -Values @(1.0, 2.0, 3.0, 4.0, 5.0) -Probability 0.95) 5.0 1e-12 'Nearest-rank p95 mismatch.'
Assert-Throws { Get-Gate12CellStatistics -Values @(1.0, 0.0) -RequireStrictlyPositive } 'Zero endpoint was accepted.'
Assert-Throws { Get-Gate12CellStatistics -Values @(1.0, -1.0) -RequireStrictlyPositive } 'Negative endpoint was accepted.'
Assert-Throws { Get-Gate12CellStatistics -Values @(1.0, [double]::NaN) -RequireStrictlyPositive } 'NaN endpoint was accepted.'
Assert-Throws { Get-Gate12CellStatistics -Values @(1.0, [double]::PositiveInfinity) -RequireStrictlyPositive } 'Infinite endpoint was accepted.'

$formulaVectors = @(
    [ordered]@{ sigma = 0.00; raw = 0; required = 32; candidate = 32; status = 'within-cap' },
    [ordered]@{ sigma = 0.15; raw = 37; required = 40; candidate = 40; status = 'within-cap' },
    [ordered]@{ sigma = 0.24; raw = 93; required = 96; candidate = 96; status = 'within-cap' },
    [ordered]@{ sigma = 0.25; raw = 101; required = 104; candidate = 100; status = 'blocked-amendment-required' }
)
foreach ($vector in $formulaVectors) {
    $actual = Get-Gate12SampleSizeCandidate -SigmaLog $vector.sigma
    Assert-True ($actual.nRaw -eq $vector.raw) "n_raw mismatch for sigma=$($vector.sigma)."
    Assert-True ($actual.requiredNFormal -eq $vector.required) "required n mismatch for sigma=$($vector.sigma)."
    Assert-True ($actual.candidateNFormal -eq $vector.candidate) "candidate n mismatch for sigma=$($vector.sigma)."
    Assert-True ($actual.precisionStatus -eq $vector.status) "precision status mismatch for sigma=$($vector.sigma)."
}
Assert-Throws { Get-Gate12SampleSizeCandidate -SigmaLog -0.01 } 'Negative sigma was accepted.'
Assert-Throws { Get-Gate12SampleSizeCandidate -SigmaLog ([double]::NaN) } 'NaN sigma was accepted.'
Assert-Throws { Get-Gate12SampleSizeCandidate -SigmaLog ([double]::PositiveInfinity) } 'Infinite sigma was accepted.'

$syntheticSamples = @()
$scenarioIds = @('synthetic-s1', 'synthetic-s2', 'synthetic-s3', 'synthetic-s4')
$algorithms = @('A*-R', 'D*L')
foreach ($scenarioId in $scenarioIds) {
    foreach ($algorithmId in $algorithms) {
        for ($repetition = 1; $repetition -le 8; $repetition++) {
            $scale = if ($scenarioId -eq 'synthetic-s4' -and $algorithmId -eq 'D*L') { 0.20 } else { 0.01 }
            $centered = $repetition - 4.5
            $syntheticSamples += [pscustomobject]@{
                comparisonCohortId = 'four-algorithm-shared-goal-v1'
                scenarioId = $scenarioId
                algorithmId = $algorithmId
                primaryEndpoint = [math]::Exp(1.0 + $scale * $centered)
                runId = "synthetic-$scenarioId-$algorithmId-$repetition"
                workloadResultRelativePath = "synthetic/$scenarioId/$algorithmId/$repetition.json"
                campaignOrdinal = 1
                block = $repetition
                position = 1
            }
        }
    }
}
$familyDefinition = [pscustomobject]@{ familyId = 'synthetic-family'; comparisonCohortId = 'four-algorithm-shared-goal-v1'; algorithms = @('A*-R', 'D*L') }
$family = Get-Gate12FamilyAnalysis -Samples $syntheticSamples -FamilyDefinition $familyDefinition -ExpectedScenarioIds $scenarioIds -ExpectedRepetitionsPerCell 8
$expectedGoverningSd = Get-Gate12SampleStandardDeviation -Values @(-0.7, -0.5, -0.3, -0.1, 0.1, 0.3, 0.5, 0.7)
Assert-True ($family.measuredSampleCount -eq 64 -and $family.cellCount -eq 8) 'Synthetic family count mismatch.'
Assert-True ($family.governingCellId -eq 'four-algorithm-shared-goal-v1::synthetic-s4::D*L') 'Worst-cell selection mismatch.'
Assert-Near $family.sigmaLog $expectedGoverningSd 1e-12 'Worst-cell sigma mismatch.'
$badSamples = @($syntheticSamples | ForEach-Object { $_.PSObject.Copy() })
$badSamples[0].primaryEndpoint = 0.0
Assert-Throws { Get-Gate12FamilyAnalysis -Samples $badSamples -FamilyDefinition $familyDefinition -ExpectedScenarioIds $scenarioIds -ExpectedRepetitionsPerCell 8 } 'Family analysis accepted a zero endpoint.'
Assert-Throws { Get-Gate12FamilyAnalysis -Samples @($syntheticSamples | Select-Object -Skip 1) -FamilyDefinition $familyDefinition -ExpectedScenarioIds $scenarioIds -ExpectedRepetitionsPerCell 8 } 'Family analysis accepted an incomplete cell.'

$projectedAll32 = Get-Gate12ProjectedProcessCount -P1 32 -P2 32 -P3 32 -P4 32
Assert-True ($projectedAll32 -eq 6784) 'All-32 formal process projection is not 6,784.'
$projectedMixed = Get-Gate12ProjectedProcessCount -P1 32 -P2 40 -P3 96 -P4 100
$expectedMixed = 32 * 2 * 32 + 21 * 2 * 40 + 32 * 2 * 96 + 21 * 2 * 100
Assert-True ($projectedMixed -eq $expectedMixed) 'Mixed-family formal process projection mismatch.'
Assert-True ((Get-Gate12CompletedSampleCount -Entries @()) -eq 0) 'Empty completed-entry list did not yield zero samples.'
$countFixture = @([pscustomobject]@{ sampleCount = 16 }, [pscustomobject]@{ sampleCount = 32 })
Assert-True ((Get-Gate12CompletedSampleCount -Entries $countFixture) -eq 48) 'Completed-entry sample sum mismatch.'
$orderedCountFixture = @([ordered]@{ sampleCount = 16 }, [ordered]@{ sampleCount = 32 })
Assert-True ((Get-Gate12CompletedSampleCount -Entries $orderedCountFixture) -eq 48) 'Ordered-dictionary completed-entry sample sum mismatch.'
Assert-Throws { Get-Gate12CompletedSampleCount -Entries @([pscustomobject]@{ sampleCount = -1 }) } 'Negative completed-entry sample count was accepted.'

$probePowerShellPath = (Get-Command powershell.exe -ErrorAction Stop).Source
$processCapture = Start-Gate12OwnedProcessCapture -FilePath $probePowerShellPath -Arguments '-NoProfile -Command "Write-Output ''gate12-owned-process-probe''; exit 0"' -WorkingDirectory $ProjectPath
$probeExited = $processCapture.Process.WaitForExit(10000)
if (-not $probeExited) { $processCapture.Process.Kill() }
$processCapture.Process.WaitForExit()
$processCapture.StdoutTask.Wait()
$processCapture.StderrTask.Wait()
Assert-True $probeExited 'Owned child-process probe did not exit within ten seconds.'
Assert-True ($null -ne $processCapture.Process.ExitCode -and $processCapture.Process.ExitCode -eq 0) 'Owned child-process probe did not expose exit code zero.'
Assert-True ($processCapture.StdoutTask.Result -match 'gate12-owned-process-probe') 'Owned child-process probe stdout was not drained.'
Assert-True ([string]::IsNullOrWhiteSpace([string]$processCapture.StderrTask.Result)) 'Owned child-process probe produced unexpected stderr.'
$processCapture.Process.Dispose()

$baseSnapshot = [ordered]@{
    acLineStatus = 1
    activePowerSchemeGuid = '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c'
    freePhysicalMemoryGiB = 8.0
    freeOutputDriveGiB = 30.0
    meanCpuLoadPercent = 10.0
    unityProcessCount = 0
    unityLockfilePresent = $false
    unityExecutableSha256 = $plan.unity.executableSha256
    unityProductVersion = $plan.unity.productVersion
    frozenHashesMatch = $true
    temperatureAvailable = $false
}
$preflight = Test-Gate12PreflightSnapshot -Snapshot ([pscustomobject]$baseSnapshot) -Plan $plan
Assert-True ($preflight.passed -eq $true -and $preflight.temperatureStatus -eq 'unavailable-advisory') 'Valid preflight or optional temperature policy failed.'
$negativeMutations = @(
    [ordered]@{ property = 'acLineStatus'; value = 0; failedCheck = 'acOnline' },
    [ordered]@{ property = 'activePowerSchemeGuid'; value = '00000000-0000-0000-0000-000000000000'; failedCheck = 'powerSchemeMatches' },
    [ordered]@{ property = 'freePhysicalMemoryGiB'; value = 3.9; failedCheck = 'freePhysicalMemorySufficient' },
    [ordered]@{ property = 'freeOutputDriveGiB'; value = 9.9; failedCheck = 'freeOutputDriveSufficient' },
    [ordered]@{ property = 'meanCpuLoadPercent'; value = 50.1; failedCheck = 'cpuLoadAcceptable' },
    [ordered]@{ property = 'unityProcessCount'; value = 1; failedCheck = 'noUnityProcess' },
    [ordered]@{ property = 'unityLockfilePresent'; value = $true; failedCheck = 'noUnityLockfile' },
    [ordered]@{ property = 'unityExecutableSha256'; value = ('0' * 64); failedCheck = 'unityIdentityMatches' },
    [ordered]@{ property = 'frozenHashesMatch'; value = $false; failedCheck = 'frozenHashesMatch' }
)
foreach ($mutation in $negativeMutations) {
    $copy = [ordered]@{}
    foreach ($key in $baseSnapshot.Keys) { $copy[$key] = $baseSnapshot[$key] }
    $copy[$mutation.property] = $mutation.value
    $verdict = Test-Gate12PreflightSnapshot -Snapshot ([pscustomobject]$copy) -Plan $plan
    Assert-True (-not $verdict.passed -and $mutation.failedCheck -in $verdict.failedChecks) "Preflight did not fail closed for $($mutation.property)."
}

Assert-True ((Get-Gate12MonitorDecision -ElapsedSeconds 1799 -NoGrowthChecks 2 -HardTimeoutSeconds 1800 -OutputStallChecks 3) -eq 'continue') 'Monitor continue decision mismatch.'
Assert-True ((Get-Gate12MonitorDecision -ElapsedSeconds 90 -NoGrowthChecks 3 -HardTimeoutSeconds 1800 -OutputStallChecks 3) -eq 'output-stall-advisory') 'Monitor stall advisory mismatch.'
Assert-True ((Get-Gate12MonitorDecision -ElapsedSeconds 1800 -NoGrowthChecks 0 -HardTimeoutSeconds 1800 -OutputStallChecks 3) -eq 'hard-timeout') 'Monitor hard-timeout decision mismatch.'

$passed = $failures.Count -eq 0
$summary = [ordered]@{
    schemaVersion = 1
    testId = 'gate12-analysis-unit-tests-v1'
    savedAt = (Get-Date).ToString('o')
    modulePath = $modulePath
    moduleSha256 = Get-Gate12LowerSha256 $modulePath
    frozenPlanSha256 = Get-Gate12LowerSha256 $planPath
    formulaVectors = $formulaVectors
    assertionCount = $assertions
    failures = @($failures)
    passed = $passed
}
Write-Utf8NoBomJson -Path $summaryPath -Value $summary -Depth 14
$summary | ConvertTo-Json -Depth 8
if (-not $passed) { Write-Error "Gate 12 analysis unit tests failed. Review $summaryPath"; exit 1 }
Write-Host "Gate 12 analysis unit tests passed ($assertions assertions)." -ForegroundColor Green
exit 0
