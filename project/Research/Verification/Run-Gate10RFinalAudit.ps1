[CmdletBinding()]
param([string]$ProjectPath = (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)))

$ErrorActionPreference='Stop'
$ProjectPath=[IO.Path]::GetFullPath($ProjectPath)
$research=Join-Path $ProjectPath 'Research'
$modulePath=Join-Path $research 'Gate10RProcessReusePreparation.psm1'
Import-Module $modulePath -Force
$root=Join-Path $PSScriptRoot 'Gate10R_ProcessReuse_5pct\v1'
$summaryPath=Join-Path $root 'Gate10R_FinalAudit.summary.json'
$manifestPath=Join-Path $root 'Gate10R_Evidence_Manifest.v1.json'
$checkpointPath=Join-Path $root 'gate10r-checkpoint.json'
foreach($p in @($summaryPath,$manifestPath,$checkpointPath)){if(Test-Path -LiteralPath $p){throw "Gate 10R final evidence exists; refusing retry/overwrite: $p"}}
$checks=New-Object System.Collections.Generic.List[object]
function Add([string]$Name,[bool]$Passed,[string]$Detail){$script:checks.Add([pscustomobject][ordered]@{name=$Name;passed=$Passed;detail=$Detail})}
function Load([string]$p){if(Test-Path -LiteralPath $p -PathType Leaf){return Read-Gate10RJson $p};return $null}
$unit=Load (Join-Path $root 'UnitTests.summary.json')
$compile=Load (Join-Path $root 'Compile\v1.summary.json')
$probe=Load (Join-Path $root 'TelemetryProbe\v1.summary.json')
$block=Load (Join-Path $root 'BlockVerification.summary.json')
$regression=Load (Join-Path $root 'RetainedRegression\RetainedRegression63.summary.json')
Add 'unit-tests' ($null-ne$unit-and$unit.passed-eq$true-and[int]$unit.failedCount-eq 0) $(if($null-eq$unit){'missing'}else{"$($unit.passedCount)/$($unit.assertionCount)"})
Add 'unity-compile' ($null-ne$compile-and$compile.passed-eq$true-and[int]$compile.compilerErrorMatchCount-eq 0) $(if($null-eq$compile){'missing'}else{"exit=$($compile.exitCode)"})
Add 'telemetry-probe' ($null-ne$probe-and$probe.passed-eq$true) $(if($null-eq$probe){'missing'}else{"pid=$($probe.unityProcessId)"})
Add 'block-verification' ($null-ne$block-and$block.passed-eq$true-and[int]$block.structuralMismatchCount-eq 0) $(if($null-eq$block){'missing'}else{"comparisons=$($block.structuralComparisonCount)"})
Add 'block-cardinality' ($null-ne$block-and[int]$block.invocationCount-eq 4-and[int]$block.freshColdReferenceCount-eq 6-and[int]$block.structuralComparisonCount-eq 10) $(if($null-eq$block){'missing'}else{"$($block.invocationCount)/$($block.freshColdReferenceCount)/$($block.structuralComparisonCount)"})
Add 'independent-process-repeatability' ($null-ne$block-and$block.distinctPositiveProcessIdsPassed-eq$true-and$block.independentProcessRepeatabilityPassed-eq$true) 'required'
Add 'negative-fail-closed' ($null-ne$block-and$block.negativeFailClosedPassed-eq$true) 'required'
Add 'retained-regression-63' ($null-ne$regression-and$regression.passed-eq$true-and[int]$regression.assertionCount-eq 63) $(if($null-eq$regression){'missing'}else{"$($regression.passedCount)/$($regression.assertionCount)"})

$provenancePath=Join-Path $research 'Gate10R_ProcessReuse_5pct_Provenance.v1.json'
$provenance=Read-Gate10RJson $provenancePath
Add 'provenance-identity' ([string]$provenance.designId-eq'gate10r-one-fresh-unity-process-per-williams-block-5pct-v1'-and$provenance.formalCampaign-eq$false) ([string]$provenance.designId)
$refs=@($provenance.specification,$provenance.testDesign,$provenance.config,$provenance.executionAuthorization,$provenance.coldStructuralClarification,$provenance.unityCommand,$provenance.unityCommandMeta,$provenance.preparationModule,$provenance.blockRunner,$provenance.telemetryProbeRunner,$provenance.coldReferenceRunner,$provenance.unitTestRunner,$provenance.compileRunner,$provenance.blockVerificationRunner,$provenance.retainedRegressionRunner,$provenance.planningBaseline.experimentPlan,$provenance.planningBaseline.decision,$provenance.planningBaseline.evidenceAudit,$provenance.planningBaseline.planningManifest)
$refErrors=New-Object System.Collections.Generic.List[string]
foreach($ref in $refs){$p=Join-Path $ProjectPath ([string]$ref.relativePath).Replace('/','\');if(-not(Test-Path -LiteralPath $p -PathType Leaf)){$refErrors.Add("missing:$($ref.relativePath)")}elseif((Get-Gate10RLowerSha256 $p)-ne[string]$ref.sha256){$refErrors.Add("hash:$($ref.relativePath)")}}
Add 'provenance-file-bindings' ($refErrors.Count-eq 0) ($refErrors -join ';')
Add 'historical-kernel-unchanged' ((Get-Gate10RLowerSha256 (Join-Path $ProjectPath ([string]$provenance.historicalKernel.relativePath).Replace('/','\')))-eq[string]$provenance.historicalKernel.sha256) ([string]$provenance.historicalKernel.sha256)
Add 'unity-binary-bound' ((Get-Gate10RLowerSha256 'H:\UnityEditor\2022.3.30f1c1\Editor\Unity.exe')-eq[string]$provenance.unity.sha256) ([string]$provenance.unity.sha256)

foreach($fixtureName in @('positive-two','positive-four-a','positive-four-b')){
    $manifest=Read-Gate10RJson (Join-Path $root "Fixtures\v1\$fixtureName\block-manifest.json")
    $ok=$manifest.completed-eq$true-and$manifest.formalCampaign-eq$false-and$manifest.oneBlockPerUnityProcess-eq$true-and$manifest.oneSamplePerAlgorithmPerProcess-eq$true-and$manifest.allSamplesShareProcessId-eq$true-and$manifest.hardMemoryRulesPassed-eq$true-and[long]$manifest.blockRetainedManagedGrowthBytes-le 134217728-and[long]$manifest.blockWorkingSetGrowthBytes-le 536870912-and[long]$manifest.blockPrivateMemoryGrowthBytes-le 536870912
    Add "fixture-$fixtureName" $ok "pid=$($manifest.processId);samples=$($manifest.completedSampleCount)"
}
$negative=Read-Gate10RJson (Join-Path $root 'Fixtures\v1\negative-fail-closed\block-checkpoint.json')
Add 'negative-terminal-state' ([string]$negative.status-eq'failed-no-auto-retry'-and[int]$negative.completedSampleCount-eq 1-and$negative.automaticRetryAuthorized-eq$false-and$negative.automaticResumeAuthorized-eq$false) ([string]$negative.status)

function RootStats([string]$relative){
    $p=Join-Path $ProjectPath $relative
    $files=@(Get-ChildItem -LiteralPath $p -Recurse -File)
    [pscustomobject]@{files=$files.Count;bytes=[long](($files|Measure-Object Length -Sum).Sum);nonReadOnly=@($files|?{-not$_.IsReadOnly}).Count}
}
$cold=RootStats 'Research\FormalRuns\Gate13\v1'
$v1=RootStats 'Research\PilotRuns\Gate13_ProcessReuse\v1'
$v2=RootStats 'Research\PilotRuns\Gate13_ProcessReuse\v2'
Add 'historical-cold-root' ($cold.files-eq 891-and$cold.bytes-eq 129667391-and$cold.nonReadOnly-eq 0) "$($cold.files)/$($cold.bytes)/$($cold.nonReadOnly)"
Add 'historical-process-reuse-v1-root' ($v1.files-eq 838-and$v1.bytes-eq 91219643-and$v1.nonReadOnly-eq 0) "$($v1.files)/$($v1.bytes)/$($v1.nonReadOnly)"
Add 'historical-process-reuse-v2-root' ($v2.files-eq 4-and$v2.bytes-eq 8899-and$v2.nonReadOnly-eq 0) "$($v2.files)/$($v2.bytes)/$($v2.nonReadOnly)"
Add 'original-archive-unchanged' ((Get-Gate10RLowerSha256 'H:\DDM_Final_Project_Original.zip')-eq'b2431197f962fab8af8893772e822ee641a575120a95e47f04444e5172bcd5aa') 'b243...5aa'
$forbidden=@('Research\FormalScenarios\Gate11R_5pct\v1','Research\PlayableExperiments\Gate11R_5pct\v1','Research\PilotRuns\Gate12R_ProcessReuse_5pct\v1','Research\FormalRuns\Gate13R_ProcessReuse_5pct\v1','Assets\_Scenes\Research\Playable\Gate11R_5pct\v1')
foreach($relative in $forbidden){Add ('absent-'+$relative.Replace('\','-')) (-not(Test-Path -LiteralPath (Join-Path $ProjectPath $relative))) 'absent'}
Add 'no-unity-process' (@(Get-Process Unity -ErrorAction SilentlyContinue).Count-eq 0) 'zero'
Add 'no-project-lock' (-not(Test-Path -LiteralPath (Join-Path $ProjectPath 'Temp\UnityLockfile'))) 'absent'

$failed=@($checks|?{-not$_.passed})
$artifacts=New-Object System.Collections.Generic.List[object]
foreach($file in @(Get-ChildItem -LiteralPath $root -Recurse -File|Sort-Object FullName)){
    if($file.FullName-in @($summaryPath,$manifestPath,$checkpointPath)){continue}
    $artifacts.Add([pscustomobject][ordered]@{relativePath=Get-Gate10RProjectRelativePath $ProjectPath $file.FullName;bytes=$file.Length;sha256=Get-Gate10RLowerSha256 $file.FullName})
}
$manifest=[ordered]@{schemaVersion=1;manifestId='gate10r-process-reuse-5pct-evidence-manifest-v1';createdAtUtc=[DateTime]::UtcNow.ToString('o');designId=[string]$provenance.designId;artifactCount=$artifacts.Count;artifacts=$artifacts.ToArray();formalCampaign=$false}
Write-Gate10RAtomicUtf8NoBomJson $manifestPath $manifest 60
$summary=[ordered]@{schemaVersion=1;summaryKind='gate10r-final-audit-v1';savedAtUtc=[DateTime]::UtcNow.ToString('o');assertionCount=$checks.Count;passedCount=$checks.Count-$failed.Count;failedCount=$failed.Count;checks=$checks.ToArray();evidenceManifestRelativePath=Get-Gate10RProjectRelativePath $ProjectPath $manifestPath;evidenceManifestSha256=Get-Gate10RLowerSha256 $manifestPath;formalCampaign=$false;automaticRetryAttempted=$false;automaticResumeAttempted=$false;passed=$failed.Count-eq 0}
Write-Gate10RAtomicUtf8NoBomJson $summaryPath $summary 60
$checkpoint=[ordered]@{schemaVersion=1;checkpointKind='gate10r-process-reuse-5pct-checkpoint-v1';savedAtUtc=[DateTime]::UtcNow.ToString('o');status=if($summary.passed){'GATE10R-PASSED-READY-FOR-GATE11R'}else{'GATE10R-FAILED-NO-AUTO-RETRY'};designId=[string]$provenance.designId;summarySha256=Get-Gate10RLowerSha256 $summaryPath;evidenceManifestSha256=Get-Gate10RLowerSha256 $manifestPath;automaticRetryAuthorized=$false;automaticResumeAuthorized=$false;formalCampaignAuthorized=$false}
Write-Gate10RAtomicUtf8NoBomJson $checkpointPath $checkpoint 20
if(-not$summary.passed){Write-Error "Gate 10R final audit failed: $($failed.name -join ', ')";exit 1}
Write-Host "Gate 10R final audit passed: $($checks.Count)/$($checks.Count)" -ForegroundColor Green
exit 0

