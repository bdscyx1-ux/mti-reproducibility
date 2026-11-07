[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$ProjectPath,
    [switch]$BindingSmokeOnly
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

if ([string]::IsNullOrWhiteSpace($ProjectPath) -or -not [IO.Path]::IsPathRooted($ProjectPath)) {
    throw 'Gate12R provenance v8 generator requires an explicit absolute ProjectPath.'
}
$ProjectPath = [IO.Path]::GetFullPath($ProjectPath)
if ($BindingSmokeOnly) {
    Write-Output "BINDING-SMOKE-PASSED|New-Gate12RProvenanceV9|$ProjectPath"
    exit 0
}
$output = Join-Path $ProjectPath 'Research\Gate12R_5pct_ProcessReuse_Pilot_Provenance.v8.json'
if (Test-Path -LiteralPath $output) {
    throw "Create-new provenance v8 exists: $output"
}

function New-Binding([string]$Id, [string]$RelativePath) {
    $path = Join-Path $ProjectPath $RelativePath.Replace('/', '\')
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Bound file missing: $RelativePath"
    }
    return [pscustomobject][ordered]@{
        id = $Id
        relativePath = $RelativePath
        rawBytes = [long](Get-Item -LiteralPath $path).Length
        sha256 = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
    }
}

$config = New-Binding 'pilotPlanV5' 'Research/Gate12R_5pct_ProcessReuse_Pilot_Plan.v5.json'
$specification = New-Binding 'specificationV2' 'Research/Gate12R_5pct_ProcessReuse_Pilot_Specification.v2.md'
$testDesign = New-Binding 'testDesignV2' 'Research/Gate12R_5pct_ProcessReuse_Pilot_Test_Design.v2.md'
$executionAuthorization = New-Binding 'memoryGateAmendmentV1' 'Research/Gate12R_Memory_Gate_Amendment.v1.json'
$originalExecutionAuthorization = New-Binding 'originalExecutionAuthorizationV1' 'Research/Gate12R_Execution_Authorization.v1.json'
$unityCommand = New-Binding 'unityCommandV3' 'Assets/_Scripts/Research/Editor/Gate12RProcessReuseBatchCommandV3.cs'

if ($config.sha256 -ne '944b628d7b7728cae6013460e719000f046eec3d7f1a331ae5f97217e40c8d97') { throw 'Pilot plan v5 hash mismatch.' }
if ($specification.sha256 -ne '4accd8baf421096f31a85ade5a815a41861bc850d22f70cee1a60c353626c8d1') { throw 'Specification v2 hash mismatch.' }
if ($testDesign.sha256 -ne '09423769db6b0820c77e46d8bf84679677fe8dbc769fa994b10b36be911c8ccb') { throw 'Test design v2 hash mismatch.' }
if ($executionAuthorization.sha256 -ne '69a128f8c41c2e0fad1453daed0729f752bb58b77d300f736a758f5121815c20') { throw 'Memory-gate amendment hash mismatch.' }
if ($originalExecutionAuthorization.sha256 -ne 'ae437dddc19576cfcb37d1dbfb48905a0ea3cc9014328c4237d081cb0464cce0') { throw 'Original Gate12R execution authorization hash mismatch.' }
if ($unityCommand.sha256 -ne 'eeca58f7e1121d0a297e8796430a90ae32f8492c32fc5fb676ae102b5f4a0c97') { throw 'Unity command v3 hash mismatch.' }

$additional = @(
    @('gate11Bundle', 'Research/FormalScenarios/Gate11R_5pct/v1/bundle-manifest.json'),
    @('pilotPlanV5Generator', 'Research/Verification/New-Gate12RPilotPlanV5.ps1'),
    @('pilotPlanV5Derivation', 'Research/Gate12R_PilotPlanV5_Derivation.v1.json'),
    @('pilotPlanV4Supersession', 'Research/Gate12R_PilotPlanV4_Supersession.v1.json'),
    @('memoryGateDiagnosis', 'Research/Gate12R_PilotAttempt3_Managed_Memory_Diagnosis.v1.md'),
    @('memoryGateTestDesign', 'Research/Gate12R_Memory_Gate_Test_Design.v1.md'),
    @('attempt3Preservation', 'Research/Gate12R_PilotAttempt3_Terminal_Preservation.v1.json'),
    @('attempt3PartialManifest', 'Research/PilotRuns/Gate12R_ProcessReuse_5pct/v3/partial-output-manifest.json'),
    @('attempt3Checkpoint', 'Research/PilotRuns/Gate12R_ProcessReuse_5pct/v3/pilot-checkpoint.json'),
    @('attempt3FailureReceipt', 'Research/PilotRuns/Gate12R_ProcessReuse_5pct/v3/failure-receipt.json'),
    @('attempt3StaleLockRecoveryReceipt', 'Research/Gate12R_PilotAttempt3_Stale_Lock_Recovery_Receipt.v1.json'),
    @('attempt3StaleLockRecoveryScript', 'Research/Verification/Recover-Gate12RAttempt3StaleLockV1.ps1'),
    @('attempt1Preservation', 'Research/Gate12R_PilotAttempt1_Terminal_Preservation.v1.json'),
    @('attempt1PartialManifest', 'Research/PilotRuns/Gate12R_ProcessReuse_5pct/v1/partial-output-manifest.json'),
    @('attempt2Preservation', 'Research/Gate12R_PilotAttempt2_Terminal_Preservation.v1.json'),
    @('attempt2PartialManifest', 'Research/PilotRuns/Gate12R_ProcessReuse_5pct/v2/partial-output-manifest.json'),
    @('failedPilotPreservationAuditorV3', 'Research/Verification/Test-Gate12RFailedPilotPreservationV3.ps1'),
    @('storageAmendment', 'Research/Gate12R_Canonical_Input_Reference_Amendment.v1.json'),
    @('storageTestDesign', 'Research/Gate12R_Canonical_Input_Reference_Test_Design.v1.md'),
    @('canonicalReferenceModuleV2', 'Research/Gate12RCanonicalInputReferenceV2.psm1'),
    @('unityCommandV2Frozen', 'Assets/_Scripts/Research/Editor/Gate12RProcessReuseBatchCommandV2.cs'),
    @('baseBlockRunnerV3', 'Research/Run-Gate12RProcessReuseBlockV3.ps1'),
    @('activeBlockRunnerV5', 'Research/Run-Gate12RProcessReuseBlockV5.ps1'),
    @('activeCompileGateV4', 'Research/Verification/Run-Gate12RCompileV4.ps1'),
    @('activeStaticGateV5', 'Research/Verification/Run-Gate12RStaticUnitAuditV5.ps1'),
    @('memoryGateUnitTestsV1Failed', 'Research/Verification/Run-Gate12RMemoryGateUnitTestsV1.ps1'),
    @('memoryGateUnitTestsV1FailureSummary', 'Research/Verification/Gate12R_MemoryGate/v1/summary.json'),
    @('memoryGateUnitTestsV1FailureReceipt', 'Research/Gate12R_Memory_Gate_Unit_Test_Attempt1_Failure.v1.json'),
    @('memoryGateUnitTestsV2', 'Research/Verification/Run-Gate12RMemoryGateUnitTestsV2.ps1'),
    @('memoryGateUnitTestsV2SuccessSummary', 'Research/Verification/Gate12R_MemoryGate/v2/summary.json'),
    @('failedPilotPreservationInterruptedReceipt', 'Research/Gate12R_Failed_Pilot_Preservation_Audit_Interrupted_Attempt.v1.json'),
    @('failedPilotPreservationV3SuccessSummary', 'Research/Verification/Gate12R_FailedPilotPreservation/v4/summary.json'),
    @('activeTelemetryRunnerV3', 'Research/Run-Gate12RTelemetryProbeV3.ps1'),
    @('activeColdRunnerV3', 'Research/Run-Gate12RColdReferenceV3.ps1'),
    @('activeBlockRegressionGateV6', 'Research/Verification/Run-Gate12RBlockAndRegressionGatesV6.ps1'),
    @('activeValidationOnlyGateV4', 'Research/Verification/Run-Gate12RValidationOnlyPrePilotAuditV4.ps1'),
    @('activePilotRunnerV6', 'Research/Run-Gate12RPilotV6.ps1'),
    @('activePrePilotAttemptV7', 'Research/Verification/Run-Gate12RPrePilotAttemptV7.ps1'),
    @('pilotAnalyzer', 'Research/Analyze-Gate12RPilot.ps1'),
    @('postPilotReadinessAudit', 'Research/Verification/Run-Gate12RPostPilotReadinessAudit.ps1')
)

$bound = New-Object Collections.Generic.List[object]
foreach ($binding in @($config, $specification, $testDesign, $executionAuthorization, $originalExecutionAuthorization, $unityCommand)) {
    $bound.Add($binding)
}
foreach ($item in $additional) {
    $bound.Add((New-Binding ([string]$item[0]) ([string]$item[1])))
}

$gate11 = @($bound | Where-Object { $_.id -eq 'gate11Bundle' })[0]
if ($gate11.sha256 -ne '5baaeec18344a9e99e55da38f3c4875b7e7e9f3bf0add9d5f2d2f1e821b5f7fc') { throw 'Gate11R bundle hash mismatch.' }
$unityCommandV2 = @($bound | Where-Object { $_.id -eq 'unityCommandV2Frozen' })[0]
if ($unityCommandV2.sha256 -ne '2c1fdd6d8ad4edd8ac36f8d9fb3962e909673cf0eb0a14d85814f975f01b9b06') { throw 'Frozen Unity command v2 changed.' }

$provenance = [ordered]@{
    schemaVersion = 8
    provenanceId = 'gate12r-fresh-process-reuse-5pct-pilot-provenance-v8-memory-aggregation'
    createdAtUtc = [DateTime]::UtcNow.ToString('o')
    status = 'FROZEN-BEFORE-OFFICIAL-PREPILOT-ATTEMPT-6'
    attempt = 6
    pilotAttempt = 4
    implementationRevision = 8
    changeClass = 'USER-AUTHORIZED-PROSPECTIVE-BLOCK-MANAGED-MEMORY-AGGREGATION-CORRECTION'
    authorizationBasis = 'User explicitly authorized changing the former 128 MiB retained managed-memory block gate and continuing Gate12R until passage.'
    executionDesignId = 'gate10r-one-fresh-unity-process-per-williams-block-5pct-v1'
    config = $config
    specification = $specification
    testDesign = $testDesign
    executionAuthorization = $executionAuthorization
    originalExecutionAuthorization = $originalExecutionAuthorization
    unityCommand = $unityCommand
    memoryGatePolicy = [ordered]@{
        policyId = 'gate12r-sample-128mib-block-128mib-per-sample-v1'
        maximumSampleRetainedManagedGrowthBytes = 134217728
        blockLimitFormulaId = 'checked-sample-limit-times-expected-sample-count-v1'
        twoSampleBlockLimitBytes = 268435456
        fourSampleBlockLimitBytes = 536870912
        maximumBlockWorkingSetGrowthBytes = 536870912
        maximumBlockPrivateMemoryGrowthBytes = 536870912
        sampleThresholdChanged = $false
        blockAggregationRuleChanged = $true
    }
    storageAmendment = @($bound | Where-Object { $_.id -eq 'storageAmendment' })[0]
    activeCanonicalReferenceModule = @($bound | Where-Object { $_.id -eq 'canonicalReferenceModuleV2' })[0]
    activeBlockRunner = @($bound | Where-Object { $_.id -eq 'activeBlockRunnerV5' })[0]
    activeStaticUnitGate = @($bound | Where-Object { $_.id -eq 'activeStaticGateV5' })[0]
    activeCompileGate = @($bound | Where-Object { $_.id -eq 'activeCompileGateV4' })[0]
    activeTelemetryRunner = @($bound | Where-Object { $_.id -eq 'activeTelemetryRunnerV3' })[0]
    activeColdRunner = @($bound | Where-Object { $_.id -eq 'activeColdRunnerV3' })[0]
    activeBlockRegressionGate = @($bound | Where-Object { $_.id -eq 'activeBlockRegressionGateV6' })[0]
    activeValidationOnlyGate = @($bound | Where-Object { $_.id -eq 'activeValidationOnlyGateV4' })[0]
    activePilotRunner = @($bound | Where-Object { $_.id -eq 'activePilotRunnerV6' })[0]
    activePrePilotAttempt = @($bound | Where-Object { $_.id -eq 'activePrePilotAttemptV7' })[0]
    nonFormalPilotAttempts = @(
        [ordered]@{ attempt = 1; root = 'Research/PilotRuns/Gate12R_ProcessReuse_5pct/v1'; status = 'FAILED-NO-RESUME-NO-MERGE'; eligibleForAnalysis = $false },
        [ordered]@{ attempt = 2; root = 'Research/PilotRuns/Gate12R_ProcessReuse_5pct/v2'; status = 'FAILED-NO-RESUME-NO-MERGE'; eligibleForAnalysis = $false },
        [ordered]@{ attempt = 3; root = 'Research/PilotRuns/Gate12R_ProcessReuse_5pct/v3'; status = 'FAILED-NO-RESUME-NO-MERGE'; eligibleForAnalysis = $false; completedMeasuredBlocks = 328 }
    )
    boundFiles = $bound.ToArray()
    authorizedGate11BundleSha256 = '5baaeec18344a9e99e55da38f3c4875b7e7e9f3bf0add9d5f2d2f1e821b5f7fc'
    precisionTargetRelativeHalfWidth = 0.05
    hardCap = $null
    processUnit = 'one-fresh-unity-editor-process-per-complete-williams-block'
    researchSemanticsChanged = $false
    timedWorkloadSemanticsChanged = $false
    rawTelemetrySemanticsChanged = $false
    cleanupImplementationChanged = $false
    storageLayoutChanged = $false
    frozenThresholdsChanged = $true
    sampleThresholdChanged = $false
    blockAggregationRuleChanged = $true
    formalCampaign = $false
    pilotExcludedFromFormalAnalysis = $true
    versionedRepairRetryAuthorized = $true
    sameAttemptResumeAuthorized = $false
    partialAttemptMergeAuthorized = $false
    gate13rAuthorized = $false
}

$json = ($provenance | ConvertTo-Json -Depth 50).Replace("`r`n", "`n").Replace("`r", "`n") + "`n"
[IO.File]::WriteAllText($output, $json, (New-Object Text.UTF8Encoding($false, $true)))
[pscustomobject]@{
    path = $output
    sha256 = (Get-FileHash -LiteralPath $output -Algorithm SHA256).Hash.ToLowerInvariant()
    rawBytes = [long](Get-Item -LiteralPath $output).Length
    boundFileCount = $bound.Count
} | ConvertTo-Json
