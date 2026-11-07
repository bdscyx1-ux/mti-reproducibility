[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$ProjectPath)
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
$ProjectPath=[IO.Path]::GetFullPath($ProjectPath);$output=Join-Path $ProjectPath 'Research\Gate12R_5pct_ProcessReuse_Pilot_Provenance.v7.json';if(Test-Path $output){throw "Create-new provenance v7 exists: $output"}
function New-Binding([string]$Id,[string]$RelativePath){$path=Join-Path $ProjectPath $RelativePath.Replace('/','\');if(-not(Test-Path -LiteralPath $path -PathType Leaf)){throw "Bound file missing: $RelativePath"};return [pscustomobject][ordered]@{id=$Id;relativePath=$RelativePath;rawBytes=[long](Get-Item $path).Length;sha256=(Get-FileHash $path -Algorithm SHA256).Hash.ToLowerInvariant()}}
$config=New-Binding 'pilotPlanV3' 'Research/Gate12R_5pct_ProcessReuse_Pilot_Plan.v3.json';if($config.sha256-ne'498f0bac34f5ba98c946efab5577f1feed5631a4766fdd8817c74f445b150c98'){throw 'Pilot plan v3 hash mismatch.'}
$spec=New-Binding 'specification' 'Research/Gate12R_5pct_ProcessReuse_Pilot_Specification.v1.md';if($spec.sha256-ne'a889ee642d6c468c32aff9296a94afc23164232bcd8e3e6ec4729d427723fc76'){throw 'Specification hash mismatch.'}
$tests=New-Binding 'testDesign' 'Research/Gate12R_5pct_ProcessReuse_Pilot_Test_Design.v1.md';if($tests.sha256-ne'2d275beffa40e6ce66d16551f9313227e486d230772de32eb5affbae97595930'){throw 'Test-design hash mismatch.'}
$authorization=New-Binding 'executionAuthorization' 'Research/Gate12R_Execution_Authorization.v1.json';if($authorization.sha256-ne'ae437dddc19576cfcb37d1dbfb48905a0ea3cc9014328c4237d081cb0464cce0'){throw 'Execution-authorization hash mismatch.'}
$command=New-Binding 'unityCommandV2' 'Assets/_Scripts/Research/Editor/Gate12RProcessReuseBatchCommandV2.cs';if($command.sha256-ne'2c1fdd6d8ad4edd8ac36f8d9fb3962e909673cf0eb0a14d85814f975f01b9b06'){throw 'Unity command V2 hash mismatch.'}
$boundSpecs=@(
 @('gate11Bundle','Research/FormalScenarios/Gate11R_5pct/v1/bundle-manifest.json'),
 @('pilotPlanV3Derivation','Research/Gate12R_PilotPlanV3_Derivation.v1.json'),
 @('pilotPlanV3Generator','Research/Verification/New-Gate12RPilotPlanV3.ps1'),
 @('storageDiagnosis','Research/Gate12R_PilotAttempt2_Storage_Feasibility_Diagnosis.v1.md'),
 @('storageAmendment','Research/Gate12R_Canonical_Input_Reference_Amendment.v1.json'),
 @('storageTestDesign','Research/Gate12R_Canonical_Input_Reference_Test_Design.v1.md'),
 @('pilotAttempt1Preservation','Research/Gate12R_PilotAttempt1_Terminal_Preservation.v1.json'),
 @('pilotAttempt1PartialManifest','Research/PilotRuns/Gate12R_ProcessReuse_5pct/v1/partial-output-manifest.json'),
 @('pilotAttempt2Preservation','Research/Gate12R_PilotAttempt2_Terminal_Preservation.v1.json'),
 @('pilotAttempt2PartialManifest','Research/PilotRuns/Gate12R_ProcessReuse_5pct/v2/partial-output-manifest.json'),
 @('failedPilotPreservationAuditorV2','Research/Verification/Test-Gate12RFailedPilotPreservationV2.ps1'),
 @('canonicalReferenceModuleV1Failed','Research/Gate12RCanonicalInputReference.psm1'),
 @('canonicalReferenceModuleV2','Research/Gate12RCanonicalInputReferenceV2.psm1'),
 @('canonicalReferenceModuleV2Derivation','Research/Gate12R_CanonicalInputReferenceV2_Derivation.v1.json'),
 @('canonicalReferenceUnitV1Failure','Research/Verification/Gate12R_CanonicalInputReference/v1/failure-receipt.json'),
 @('canonicalReferenceUnitV3Summary','Research/Verification/Gate12R_CanonicalInputReference/v3/summary.json'),
 @('canonicalReferenceUnitV3Runner','Research/Verification/Run-Gate12RCanonicalInputReferenceUnitTestsV3.ps1'),
 @('canonicalReferenceFreshUnityBlockManifest','Research/Verification/Gate12R_ProcessReuse_5pct/storage-reference-wrapper-v1/block/block-manifest.json'),
 @('canonicalReferenceFreshUnityReceipt','Research/Verification/Gate12R_ProcessReuse_5pct/storage-reference-wrapper-v1/block/canonical-input-reference-receipt.json'),
 @('canonicalReferenceFreshUnityWrapperSummary','Research/Verification/Gate12R_ProcessReuse_5pct/storage-reference-wrapper-v1/block.summary.json'),
 @('blockRunnerV4','Research/Run-Gate12RProcessReuseBlockV4.ps1'),
 @('blockRunnerV4Derivation','Research/Gate12R_ProcessReuse_BlockRunnerV4_Derivation.v1.json'),
 @('compileGateV3','Research/Verification/Run-Gate12RCompileV3.ps1'),
 @('staticGateV4','Research/Verification/Run-Gate12RStaticUnitAuditV4.ps1'),
 @('telemetryRunnerV3','Research/Run-Gate12RTelemetryProbeV3.ps1'),
 @('coldRunnerV3','Research/Run-Gate12RColdReferenceV3.ps1'),
 @('blockRegressionGateV5','Research/Verification/Run-Gate12RBlockAndRegressionGatesV5.ps1'),
 @('validationOnlyGateV3','Research/Verification/Run-Gate12RValidationOnlyPrePilotAuditV3.ps1'),
 @('pilotRunnerV5','Research/Run-Gate12RPilotV5.ps1'),
 @('prePilotAttemptV6','Research/Verification/Run-Gate12RPrePilotAttemptV6.ps1'),
 @('wrapperDerivationAttempt1Failure','Research/Gate12R_StorageReference_Wrapper_Derivation_Attempt1_Failure.v1.json'),
 @('wrapperDerivationV2','Research/Gate12R_StorageReference_Wrapper_Derivation.v2.json'),
 @('pilotAnalyzer','Research/Analyze-Gate12RPilot.ps1'),
 @('postPilotAudit','Research/Verification/Run-Gate12RPostPilotReadinessAudit.ps1')
)
$bound=New-Object Collections.Generic.List[object];$bound.Add($config);$bound.Add($spec);$bound.Add($tests);$bound.Add($authorization);$bound.Add($command);foreach($item in $boundSpecs){$bound.Add((New-Binding ([string]$item[0]) ([string]$item[1])))}
$gate11=@($bound|Where-Object id -eq'gate11Bundle')[0];if($gate11.sha256-ne'5baaeec18344a9e99e55da38f3c4875b7e7e9f3bf0add9d5f2d2f1e821b5f7fc'){throw 'Gate 11R bundle hash mismatch.'}
$provenance=[ordered]@{schemaVersion=7;provenanceId='gate12r-fresh-process-reuse-5pct-pilot-provenance-v7-upstream-canonical-reference';createdAtUtc=[DateTime]::UtcNow.ToString('o');status='FROZEN-BEFORE-OFFICIAL-PREPILOT-ATTEMPT-5';attempt=5;pilotAttempt=3;implementationRevision=7;changeClass='EXACT-BYTE-IDENTICAL-FROZEN-UPSTREAM-CANONICAL-INPUT-REFERENCE';researchSemanticsChanged=$false;timedWorkloadSemanticsChanged=$false;rawTelemetrySemanticsChanged=$false;cleanupImplementationChanged=$false;storageLayoutChanged=$true;frozenThresholdsChanged=$false;executionDesignId='gate10r-one-fresh-unity-process-per-williams-block-5pct-v1';config=$config;specification=$spec;testDesign=$tests;executionAuthorization=$authorization;unityCommand=$command;storageAmendment=@($bound|Where-Object id -eq'storageAmendment')[0];storageTestDesign=@($bound|Where-Object id -eq'storageTestDesign')[0];activeCanonicalReferenceModule=@($bound|Where-Object id -eq'canonicalReferenceModuleV2')[0];activeBlockRunner=@($bound|Where-Object id -eq'blockRunnerV4')[0];activeStaticUnitGate=@($bound|Where-Object id -eq'staticGateV4')[0];activeCompileGate=@($bound|Where-Object id -eq'compileGateV3')[0];activeTelemetryRunner=@($bound|Where-Object id -eq'telemetryRunnerV3')[0];activeColdRunner=@($bound|Where-Object id -eq'coldRunnerV3')[0];activeBlockRegressionGate=@($bound|Where-Object id -eq'blockRegressionGateV5')[0];activeValidationOnlyGate=@($bound|Where-Object id -eq'validationOnlyGateV3')[0];activePilotRunner=@($bound|Where-Object id -eq'pilotRunnerV5')[0];activePrePilotAttempt=@($bound|Where-Object id -eq'prePilotAttemptV6')[0];nonFormalPilotAttempt1=@{root='Research/PilotRuns/Gate12R_ProcessReuse_5pct/v1';status='FAILED-NO-RESUME-NO-MERGE';eligibleForAnalysis=$false};nonFormalPilotAttempt2=@{root='Research/PilotRuns/Gate12R_ProcessReuse_5pct/v2';status='FAILED-NO-RESUME-NO-MERGE';eligibleForAnalysis=$false;completedMeasuredBlocks=384;completedMeasuredSamples=1152;failure='frozen-p95-storage-feasibility'};canonicalDuplicationEvidence=@{measuredSamplesAudited=1152;exactByteMatches=1152;mismatches=0;duplicatedRawBytes=3806864000;uniqueFrozenSources=9;uniqueFrozenSourceRawBytes=29741125};boundFiles=$bound.ToArray();authorizedGate11BundleSha256='5baaeec18344a9e99e55da38f3c4875b7e7e9f3bf0add9d5f2d2f1e821b5f7fc';precisionTargetRelativeHalfWidth=0.05;hardCap=$null;processUnit='one-fresh-unity-editor-process-per-complete-williams-block';formalCampaign=$false;pilotExcludedFromFormalAnalysis=$true;versionedRepairRetryAuthorized=$true;sameAttemptResumeAuthorized=$false;partialAttemptMergeAuthorized=$false;gate13rAuthorized=$false}
$json=($provenance|ConvertTo-Json -Depth 40).Replace("`r`n","`n").Replace("`r","`n")+"`n";[IO.File]::WriteAllText($output,$json,(New-Object Text.UTF8Encoding($false,$true)));[pscustomobject]@{path=$output;sha256=(Get-FileHash $output -Algorithm SHA256).Hash.ToLowerInvariant();rawBytes=(Get-Item $output).Length;boundFileCount=$bound.Count}|ConvertTo-Json
