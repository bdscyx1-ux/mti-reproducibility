[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$ProjectPath,
    [Parameter(Mandatory=$true)][string]$VerificationRoot,
    [string]$PilotPlanPath='Research\Gate13R_48h_10pct_3Lane_Pilot_Plan.v1.json',
    [string]$SchedulePath='Research\Gate13R_48h_10pct_3Lane_Pilot_Schedule.v1.json',
    [string]$ProvenancePath='Research\Gate13R_48h_10pct_3Lane_Provenance.v1.json',
    [string]$LicensingStressManifestPath='Research\Verification\Gate13R_48h_10pct_3Lane\v1\LicensingStress\stress-manifest.json',
    [switch]$BindingSmokeOnly
)
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
$ProjectPath=[IO.Path]::GetFullPath($ProjectPath)
foreach($name in @('VerificationRoot','PilotPlanPath','SchedulePath','ProvenancePath','LicensingStressManifestPath')){$value=Get-Variable -Name $name -ValueOnly;if(-not[IO.Path]::IsPathRooted($value)){$value=Join-Path $ProjectPath $value};Set-Variable -Name $name -Value ([IO.Path]::GetFullPath($value))}
if($BindingSmokeOnly){Write-Output("BINDING-SMOKE-PASSED|Run-Gate13R48h3LaneValidationOnlyPrePilotAuditV1|$ProjectPath");exit 0}
$expectedVerification=[IO.Path]::GetFullPath((Join-Path $ProjectPath 'Research\Verification\Gate13R_48h_10pct_3Lane\v1'));if($VerificationRoot-ne$expectedVerification){throw 'Verification root differs from the frozen path.'}
Import-Module (Join-Path $ProjectPath 'Research\Gate13R48h3LanePreparationV1.psm1') -Force
$summaryPath=Join-Path $VerificationRoot 'ValidationOnlyPrePilotAudit.summary.json';$failurePath=Join-Path $VerificationRoot 'ValidationOnlyPrePilotAudit.failure.json';if(Test-Path $summaryPath){throw 'Create-new validation-only audit summary exists.'}
$assertions=New-Object Collections.Generic.List[object];$errors=New-Object Collections.Generic.List[string]
function A([string]$id,[bool]$passed,[string]$detail){$assertions.Add([pscustomobject]@{id=$id;passed=$passed;detail=$detail});if(-not$passed){$errors.Add("${id}: $detail")}}
function H([string]$path){Get-G13R48LowerSha256 $path}
function P([string]$relative){[IO.Path]::GetFullPath((Join-Path $ProjectPath $relative.Replace('/','\')))}
try{
    $plan=Read-G13R48Json $PilotPlanPath;$schedule=Read-G13R48Json $SchedulePath;$provenance=Read-G13R48Json $ProvenancePath
    $verification=Read-G13R48Json (Join-Path $VerificationRoot 'verification-summary.json');$stress=Read-G13R48Json $LicensingStressManifestPath
    $planSha=H $PilotPlanPath;$scheduleSha=H $SchedulePath;$provenanceSha=H $ProvenancePath;$stressSha=H $LicensingStressManifestPath
    A 'design-identity' ([string]$plan.executionDesignId-eq'gate13r-48h-10pct-three-isolated-editor-lanes-serial-license-admission-v1') ([string]$plan.executionDesignId)
    A 'plan-cardinality' (@($plan.lanes).Count-eq3-and[int]$plan.totals.measuredWaves-eq128-and[int]$plan.totals.measuredBlockProcesses-eq384-and[int]$plan.totals.measuredSamples-eq1152) '3 lanes / 128 waves / 384 blocks / 1152 samples'
    A 'precision-runtime-policy' ([double]$plan.precision.relativeHalfWidth-eq0.10-and$null-eq$plan.precision.hardCap-and[int]$plan.runtimeProjection.maximumReadinessP95Hours-eq42-and[int]$plan.runtimeProjection.hardFormalEndToEndHours-eq48) '10% / uncapped / readiness p95 <= 42 h / hard <= 48 h'
    A 'schedule-cardinality' (@($schedule.rows).Count-eq384-and[int]$schedule.waveCount-eq128-and@($schedule.rows.lane|Sort-Object -Unique).Count-eq3) 'frozen three-lane measured schedule'
    A 'provenance-config-binding' ([string]$provenance.config.sha256-eq$planSha-and[string]$provenance.schedule.sha256-eq$scheduleSha) 'plan and schedule hashes'
    A 'verification-passed' ($verification.passed-eq$true-and$verification.formalCampaign-eq$false) ([string]$verification.summaryKind)
    A 'licensing-stress-passed' ($stress.passed-eq$true-and[int]$stress.waveCount-eq172-and[int]$stress.freshUnityProcessCount-eq516-and[int]$stress.uniqueUnityProcessCount-eq516-and[int]$stress.terminalLicenseFailureCount-eq0-and[int]$stress.retryCount-eq0-and[int]$stress.resumeCount-eq0-and$stress.planningWorkloadExecuted-eq$false) '172 waves / 516 unique PID@start identities / zero terminal license failures'
    A 'licensing-stress-identity-rule' ([string]$stress.processIdentityRule-eq'pid-at-os-process-start-time-utc-v1') ([string]$stress.processIdentityRule)
    foreach($entry in @($provenance.artifacts)){$full=P ([string]$entry.relativePath);A ('provenance-'+[string]$entry.id) ((Test-Path $full -PathType Leaf)-and(H $full)-eq[string]$entry.sha256) ([string]$entry.relativePath)}
    $bundlePath=P ([string]$plan.paths.gate11BundleManifestRelativePath);$matrixPath=P ([string]$plan.paths.gate11MatrixRelativePath);$coveragePath=P ([string]$plan.paths.coverageManifestRelativePath);$profilesPath=P ([string]$plan.paths.campaignCatalogRelativePath);$presetsPath=P ([string]$plan.paths.presetCatalogRelativePath);$scenesPath=P ([string]$plan.paths.sceneCatalogRelativePath)
    A 'gate11-bundle-frozen-hash' ((H $bundlePath)-eq[string]$plan.upstreamHashes.gate11BundleManifest) (H $bundlePath)
    $bundle=Read-G13R48Json $bundlePath;$matrix=Read-G13R48Json $matrixPath;$coverage=Read-G13R48Json $coveragePath;$profiles=Read-G13R48Json $profilesPath;$presets=Read-G13R48Json $presetsPath;$scenes=Read-G13R48Json $scenesPath
    A 'playable-counts' ([int]$bundle.sceneCount-eq53-and[int]$bundle.campaignCount-eq74-and[int]$bundle.presetCount-eq212-and[int]$matrix.campaignCount-eq74-and[int]$coverage.scenarioCount-eq53-and[int]$coverage.campaignCount-eq74-and[int]$coverage.presetCount-eq212) '53 scenes / 74 campaign profiles / 212 algorithm presets'
    A 'playable-boundary' ($bundle.visualizationOnly-eq$true-and$bundle.timingEvidenceAllowed-eq$false-and$coverage.visualizationOnly-eq$true-and$coverage.timingEvidenceAllowed-eq$false) 'visualization only; timing evidence forbidden'
    $artifactFailures=0;foreach($artifact in @($bundle.artifacts)){$full=P ([string]$artifact.relativePath);if(-not(Test-Path $full -PathType Leaf)-or(Get-Item $full).Length-ne[long]$artifact.rawBytes-or(H $full)-ne[string]$artifact.sha256){$artifactFailures++}}
    A 'gate11-bundle-artifact-hashes' ($artifactFailures-eq0) ("checked={0}; failures={1}"-f@($bundle.artifacts).Count,$artifactFailures)
    $mappingFailures=New-Object Collections.Generic.List[string]
    foreach($campaign in @($matrix.campaigns)){
        $profile=@($profiles.campaigns|Where-Object campaignId -eq ([string]$campaign.campaignId));if($profile.Count-ne1){$mappingFailures.Add("profile:$($campaign.campaignId)");continue}
        $scene=@($scenes.scenes|Where-Object scenarioId -eq ([string]$campaign.scenarioId));if($scene.Count-ne1){$mappingFailures.Add("scene:$($campaign.campaignId)");continue}
        if([string]$profile[0].sceneAssetPath-ne[string]$campaign.sceneAssetPath-or[string]$profile[0].profileAssetPath-ne[string]$campaign.profileAssetPath-or[string]$scene[0].sceneAssetPath-ne[string]$campaign.sceneAssetPath){$mappingFailures.Add("paths:$($campaign.campaignId)")}
        if((H (P ([string]$campaign.scenarioRelativePath)))-ne[string]$campaign.scenarioSha256-or(H (P ([string]$campaign.profileAssetPath)))-ne[string]$campaign.profileSha256-or(H (P ([string]$campaign.sceneAssetPath)))-ne[string]$scene[0].sceneSha256){$mappingFailures.Add("hashes:$($campaign.campaignId)")}
        foreach($algorithm in @($campaign.eligibleAlgorithmIds)){$preset=@($presets.presets|Where-Object{[string]$_.campaignId-eq[string]$campaign.campaignId-and[string]$_.algorithmId-eq[string]$algorithm});if($preset.Count-ne1-or(H (P ([string]$preset[0].presetAssetPath)))-ne[string]$preset[0].presetSha256){$mappingFailures.Add("preset:$($campaign.campaignId):$algorithm")}}
    }
    A 'every-experiment-playable-mapping' ($mappingFailures.Count-eq0) ("campaigns=74; mappingFailures={0}"-f$mappingFailures.Count)
    A 'launcher-hash' ((H (P ([string]$coverage.launcherSceneAssetPath)))-eq[string]$coverage.launcherSceneSha256) ([string]$coverage.launcherSceneAssetPath)
    $pilotRoot=P ([string]$plan.paths.pilotRootRelativePath);$formalRoot=P ([string]$plan.paths.reservedFormalRootRelativePath)
    A 'pilot-root-absent' (-not(Test-Path $pilotRoot)) $pilotRoot;A 'formal-root-absent' (-not(Test-Path $formalRoot)) $formalRoot
    A 'unity-quiescent' (@(Get-Process Unity -ErrorAction SilentlyContinue).Count-eq0) 'no Unity process'
    $locks=@($plan.lanes|Where-Object{Test-Path (Join-Path ([string]$_.projectPath) 'Temp\UnityLockfile')});A 'lane-locks-absent' ($locks.Count-eq0) ("lockCount={0}"-f$locks.Count)
    if($errors.Count){throw ($errors-join"`n")}
    $summary=[ordered]@{schemaVersion=1;summaryKind='gate13r-48h-three-lane-validation-only-pre-pilot-audit-v1';completedAtUtc=[DateTime]::UtcNow.ToString('o');executionDesignId=[string]$plan.executionDesignId;pilotPlanSha256=$planSha;scheduleSha256=$scheduleSha;provenanceSha256=$provenanceSha;licensingStressManifestSha256=$stressSha;assertionCount=$assertions.Count;failedAssertionCount=0;assertions=$assertions.ToArray();playableScenarioCount=53;playableCampaignCount=74;playablePresetCount=212;pilotRootCreated=$false;formalRootCreated=$false;formalCampaign=$false;formalExecutionAuthorized=$false;passed=$true}
    Write-G13R48CreateNewUtf8NoBomJson $summaryPath $summary 60;Write-Host("Validation-only pre-pilot audit passed: {0} assertions."-f$assertions.Count)-ForegroundColor Green;exit 0
}catch{
    $failure=[ordered]@{schemaVersion=1;failureKind='gate13r-48h-three-lane-validation-only-pre-pilot-audit-failure-v1';failedAtUtc=[DateTime]::UtcNow.ToString('o');status='FAILED-NO-PILOT-NO-AUTO-RETRY';error=$_.Exception.ToString();assertions=$assertions.ToArray();pilotRootCreated=Test-Path (Join-Path $ProjectPath 'Research\PilotRuns\Gate13R_48h_10pct_3Lane\v1');formalRootCreated=Test-Path (Join-Path $ProjectPath 'Research\FormalRuns\Gate13R_48h_10pct_3Lane\v1');formalCampaign=$false}
    if(Test-Path $failurePath){Write-G13R48AtomicUtf8NoBomJson $failurePath $failure 40}else{Write-G13R48CreateNewUtf8NoBomJson $failurePath $failure 40};Write-Error("Validation-only pre-pilot audit failed: $($_.Exception.Message)");exit 1
}
