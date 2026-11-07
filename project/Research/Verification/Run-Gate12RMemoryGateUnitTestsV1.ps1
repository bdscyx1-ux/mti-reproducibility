[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$ProjectPath,
    [Parameter(Mandatory = $true)][string]$OutputPath,
    [switch]$BindingSmokeOnly
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

if ([string]::IsNullOrWhiteSpace($ProjectPath) -or -not [IO.Path]::IsPathRooted($ProjectPath)) {
    throw 'Gate12R memory-gate unit tests require an explicit absolute ProjectPath.'
}
$ProjectPath = [IO.Path]::GetFullPath($ProjectPath)
if ($BindingSmokeOnly) {
    Write-Output "BINDING-SMOKE-PASSED|Run-Gate12RMemoryGateUnitTestsV1|$ProjectPath"
    exit 0
}
$OutputPath = [IO.Path]::GetFullPath($OutputPath)
if (Test-Path -LiteralPath $OutputPath) {
    throw "Create-new memory-gate unit-test output exists: $OutputPath"
}

function Read-Json([string]$Path) {
    return Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
}

function Get-LowerSha256([string]$Path) {
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Test-ScaledLimit([long]$ObservedBytes, [int]$ExpectedSampleCount) {
    $limit = [long]134217728 * [long]$ExpectedSampleCount
    return $ObservedBytes -le $limit
}

$assertions = 0
$failures = New-Object Collections.Generic.List[object]
function Assert-True([bool]$Condition, [string]$Name, [string]$Detail) {
    $script:assertions++
    if (-not $Condition) {
        $script:failures.Add([pscustomobject][ordered]@{ name = $Name; detail = $Detail })
    }
}

$planPath = Join-Path $ProjectPath 'Research\Gate12R_5pct_ProcessReuse_Pilot_Plan.v5.json'
$amendmentPath = Join-Path $ProjectPath 'Research\Gate12R_Memory_Gate_Amendment.v1.json'
$specPath = Join-Path $ProjectPath 'Research\Gate12R_5pct_ProcessReuse_Pilot_Specification.v2.md'
$testDesignPath = Join-Path $ProjectPath 'Research\Gate12R_5pct_ProcessReuse_Pilot_Test_Design.v2.md'
$diagnosisPath = Join-Path $ProjectPath 'Research\Gate12R_PilotAttempt3_Managed_Memory_Diagnosis.v1.md'
$preservationPath = Join-Path $ProjectPath 'Research\Gate12R_PilotAttempt3_Terminal_Preservation.v1.json'
$commandV2Path = Join-Path $ProjectPath 'Assets\_Scripts\Research\Editor\Gate12RProcessReuseBatchCommandV2.cs'
$commandV3Path = Join-Path $ProjectPath 'Assets\_Scripts\Research\Editor\Gate12RProcessReuseBatchCommandV3.cs'
$runnerV3Path = Join-Path $ProjectPath 'Research\Run-Gate12RProcessReuseBlockV3.ps1'
$attempt3Root = Join-Path $ProjectPath 'Research\PilotRuns\Gate12R_ProcessReuse_5pct\v3'
$formalRoot = Join-Path $ProjectPath 'Research\FormalRuns\Gate13R_ProcessReuse_5pct\v1'
$attempt4Root = Join-Path $ProjectPath 'Research\PilotRuns\Gate12R_ProcessReuse_5pct\v4'

foreach ($path in @($planPath, $amendmentPath, $specPath, $testDesignPath, $diagnosisPath, $preservationPath, $commandV2Path, $commandV3Path, $runnerV3Path)) {
    Assert-True (Test-Path -LiteralPath $path -PathType Leaf) 'required-file-present' $path
}

$plan = Read-Json $planPath
$amendment = Read-Json $amendmentPath
$preservation = Read-Json $preservationPath
$sampleLimit = [long]134217728
$twoSampleLimit = [long]268435456
$fourSampleLimit = [long]536870912

Assert-True ((Get-LowerSha256 $planPath) -eq '944b628d7b7728cae6013460e719000f046eec3d7f1a331ae5f97217e40c8d97') 'pilot-plan-v5-hash' (Get-LowerSha256 $planPath)
Assert-True ((Get-LowerSha256 $amendmentPath) -eq '69a128f8c41c2e0fad1453daed0729f752bb58b77d300f736a758f5121815c20') 'memory-amendment-hash' (Get-LowerSha256 $amendmentPath)
Assert-True ((Get-LowerSha256 $specPath) -eq '4accd8baf421096f31a85ade5a815a41861bc850d22f70cee1a60c353626c8d1') 'specification-v2-hash' (Get-LowerSha256 $specPath)
Assert-True ((Get-LowerSha256 $testDesignPath) -eq '09423769db6b0820c77e46d8bf84679677fe8dbc769fa994b10b36be911c8ccb') 'test-design-v2-hash' (Get-LowerSha256 $testDesignPath)
Assert-True ((Get-LowerSha256 $diagnosisPath) -eq 'fe0e7b2e37497a695880754603037ace0e4ef6a756962a6a82b478bd03d28281') 'attempt3-diagnosis-hash' (Get-LowerSha256 $diagnosisPath)
Assert-True ((Get-LowerSha256 $preservationPath) -eq 'ceb2562c6f3918f5e68fe32ce52c7b334af028e56ce974aab7feb6e2b91fc511') 'attempt3-preservation-hash' (Get-LowerSha256 $preservationPath)
Assert-True ((Get-LowerSha256 $commandV2Path) -eq '2c1fdd6d8ad4edd8ac36f8d9fb3962e909673cf0eb0a14d85814f975f01b9b06') 'unity-command-v2-unchanged' (Get-LowerSha256 $commandV2Path)
Assert-True ((Get-LowerSha256 $commandV3Path) -eq [string]$plan.memoryGateAmendment.unityCommandSha256) 'unity-command-v3-plan-binding' (Get-LowerSha256 $commandV3Path)

Assert-True ([long]$plan.telemetry.maximumSampleRetainedManagedGrowthBytes -eq $sampleLimit) 'sample-limit-unchanged' ([string]$plan.telemetry.maximumSampleRetainedManagedGrowthBytes)
Assert-True ([long]$plan.telemetry.maximumBlockRetainedManagedGrowthBytesPerSample -eq $sampleLimit) 'block-per-sample-base' ([string]$plan.telemetry.maximumBlockRetainedManagedGrowthBytesPerSample)
Assert-True ([long]$plan.telemetry.twoSampleBlockRetainedManagedGrowthLimitBytes -eq $twoSampleLimit) 'two-sample-limit' ([string]$plan.telemetry.twoSampleBlockRetainedManagedGrowthLimitBytes)
Assert-True ([long]$plan.telemetry.fourSampleBlockRetainedManagedGrowthLimitBytes -eq $fourSampleLimit) 'four-sample-limit' ([string]$plan.telemetry.fourSampleBlockRetainedManagedGrowthLimitBytes)
Assert-True ([string]$plan.telemetry.memoryGatePolicyId -eq 'gate12r-sample-128mib-block-128mib-per-sample-v1') 'memory-policy-id' ([string]$plan.telemetry.memoryGatePolicyId)
Assert-True ([string]$plan.telemetry.blockManagedLimitFormulaId -eq 'checked-sample-limit-times-expected-sample-count-v1') 'memory-formula-id' ([string]$plan.telemetry.blockManagedLimitFormulaId)
Assert-True ([long]$plan.telemetry.maximumBlockWorkingSetGrowthBytes -eq $fourSampleLimit) 'working-set-limit-unchanged' ([string]$plan.telemetry.maximumBlockWorkingSetGrowthBytes)
Assert-True ([long]$plan.telemetry.maximumBlockPrivateMemoryGrowthBytes -eq $fourSampleLimit) 'private-memory-limit-unchanged' ([string]$plan.telemetry.maximumBlockPrivateMemoryGrowthBytes)

Assert-True (Test-ScaledLimit $twoSampleLimit 2) 'two-sample-boundary-pass' ([string]$twoSampleLimit)
Assert-True (-not (Test-ScaledLimit ($twoSampleLimit + 1) 2)) 'two-sample-boundary-fail' ([string]($twoSampleLimit + 1))
Assert-True (Test-ScaledLimit $fourSampleLimit 4) 'four-sample-boundary-pass' ([string]$fourSampleLimit)
Assert-True (-not (Test-ScaledLimit ($fourSampleLimit + 1) 4)) 'four-sample-boundary-fail' ([string]($fourSampleLimit + 1))
Assert-True (Test-ScaledLimit 139771904 2) 'attempt3-observed-growth-now-valid-at-block-level' '139771904 <= 268435456'

$commandV3Text = [IO.File]::ReadAllText($commandV3Path, [Text.Encoding]::UTF8)
$runnerV3Text = [IO.File]::ReadAllText($runnerV3Path, [Text.Encoding]::UTF8)
Assert-True ($commandV3Text.Contains('checked(SampleManagedGrowthLimitBytes * completed.Count)')) 'unity-command-checked-formula' 'checked(sampleLimit * completed.Count)'
Assert-True ($commandV3Text.Contains('sampleRetainedManagedGrowth <= SampleManagedGrowthLimitBytes')) 'unity-command-sample-gate-retained' 'sample retained managed-memory check'
Assert-True ($runnerV3Text.Contains('$expectedBlockManagedLimit=[long]134217728*[long]@($plan.entries).Count')) 'wrapper-independent-formula' 'wrapper recomputes expected limit'
Assert-True ($runnerV3Text.Contains('sampleRetainedManagedGrowthBytes-gt134217728')) 'wrapper-independent-sample-gate' 'wrapper retains per-sample 128 MiB gate'

Assert-True ([string]$preservation.terminalStatus -eq 'FAILED-NO-RESUME-NO-MERGE') 'attempt3-terminal-status' ([string]$preservation.terminalStatus)
Assert-True ($preservation.automaticResumeAuthorized -eq $false -and $preservation.partialAttemptMergeAuthorized -eq $false) 'attempt3-no-resume-no-merge' 'preservation flags'
Assert-True ((Get-LowerSha256 (Join-Path $attempt3Root 'partial-output-manifest.json')) -eq 'd42366ef313834ade6ae4c3cdcfe356eb9b58a8155808a56e7bebf83862b2039') 'attempt3-partial-manifest-hash' 'frozen attempt 3'
Assert-True ((Get-LowerSha256 (Join-Path $attempt3Root 'pilot-checkpoint.json')) -eq 'ad2d2152780b60f6bed68f19ea5df68d14ce9f265b1b89b15c28f7e11d24d5a0') 'attempt3-checkpoint-hash' 'frozen attempt 3'
Assert-True (-not (Test-Path -LiteralPath $attempt4Root)) 'attempt4-root-absent-before-pilot' $attempt4Root
Assert-True (-not (Test-Path -LiteralPath $formalRoot)) 'gate13r-root-absent' $formalRoot

$result = [ordered]@{
    schemaVersion = 1
    summaryKind = 'gate12r-managed-memory-aggregation-unit-tests-v1'
    completedAtUtc = [DateTime]::UtcNow.ToString('o')
    memoryGatePolicyId = 'gate12r-sample-128mib-block-128mib-per-sample-v1'
    maximumSampleRetainedManagedGrowthBytes = $sampleLimit
    twoSampleBlockRetainedManagedGrowthLimitBytes = $twoSampleLimit
    fourSampleBlockRetainedManagedGrowthLimitBytes = $fourSampleLimit
    maximumBlockWorkingSetGrowthBytes = $fourSampleLimit
    maximumBlockPrivateMemoryGrowthBytes = $fourSampleLimit
    assertionCount = $assertions
    failureCount = $failures.Count
    failures = $failures.ToArray()
    sampleThresholdChanged = $false
    blockAggregationRuleChanged = $true
    formalCampaign = $false
    gate13rAuthorized = $false
    passed = $failures.Count -eq 0
}
$parent = Split-Path -Parent $OutputPath
if (-not (Test-Path -LiteralPath $parent)) {
    New-Item -ItemType Directory -Path $parent -Force | Out-Null
}
$json = ($result | ConvertTo-Json -Depth 20).Replace("`r`n", "`n").Replace("`r", "`n") + "`n"
[IO.File]::WriteAllText($OutputPath, $json, (New-Object Text.UTF8Encoding($false, $true)))
if (-not $result.passed) {
    throw "Gate12R memory-gate unit tests failed: $($failures.Count) assertion(s)."
}
$result | ConvertTo-Json -Depth 20
