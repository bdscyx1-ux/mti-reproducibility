[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$BlockPlanPath,
    [Parameter(Mandatory=$true)][string]$OutputDirectory,
    [Parameter(Mandatory=$true)][string]$AllowedRoot,
    [Parameter(Mandatory=$true)][ValidateSet('Verification','Pilot')][string]$Mode,
    [string]$UnityPath='H:\UnityEditor\2022.3.30f1c1\Editor\Unity.exe',
    [Parameter(Mandatory=$true)][string]$ProjectPath,
    [switch]$BindingSmokeOnly,
    [switch]$ExpectFailure,
    [int]$ExpectedCompletedSamplesBeforeFailure=1,
    [int]$TimeoutSeconds=3600
)

$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
if([string]::IsNullOrWhiteSpace($ProjectPath)-or-not[IO.Path]::IsPathRooted($ProjectPath)){throw 'Gate13R-PR1B v3 block wrapper requires an explicit absolute ProjectPath.'}
$ProjectPath=[IO.Path]::GetFullPath($ProjectPath)
if($BindingSmokeOnly){Write-Output("BINDING-SMOKE-PASSED|Run-Gate13RPR1BMemoryAwareBlockV3|$ProjectPath|$Mode");exit 0}
$BlockPlanPath=[IO.Path]::GetFullPath($BlockPlanPath)
$OutputDirectory=[IO.Path]::GetFullPath($OutputDirectory)
$AllowedRoot=[IO.Path]::GetFullPath($AllowedRoot)
$UnityPath=[IO.Path]::GetFullPath($UnityPath)

$baseWrapper=Join-Path $ProjectPath 'Research\Run-Gate12RProcessReuseBlockV3.ps1'
$canonicalModule=Join-Path $ProjectPath 'Research\Gate12RCanonicalInputReferenceV2.psm1'
$expectedBaseSha256='b5ac864438c3f98684cc62a988f742ef9500434feb41504b5e4742af14d7ef8a'
if(-not(Test-Path -LiteralPath $baseWrapper -PathType Leaf)-or-not(Test-Path -LiteralPath $canonicalModule -PathType Leaf)){throw 'Gate13R-PR1B v2 block dependencies are missing.'}
$actualBaseSha256=(Get-FileHash -LiteralPath $baseWrapper -Algorithm SHA256).Hash.ToLowerInvariant()
if($actualBaseSha256-ne$expectedBaseSha256){throw "Frozen Gate12R V3 block wrapper changed: $actualBaseSha256"}

$text=[IO.File]::ReadAllText($baseWrapper,[Text.Encoding]::UTF8)
$routes=@(
    [pscustomobject]@{from="Import-Module (Join-Path `$PSScriptRoot 'Gate10RProcessReusePreparation.psm1') -Force";to="Import-Module (Join-Path `$ProjectPath 'Research\Gate10RProcessReusePreparation.psm1') -Force";count=1},
    [pscustomobject]@{from="Import-Module (Join-Path `$PSScriptRoot 'Gate10RLockHygieneV3.psm1') -Force";to="Import-Module (Join-Path `$ProjectPath 'Research\Gate10RLockHygieneV3.psm1') -Force";count=1},
    [pscustomobject]@{from="`$formalRoot=[IO.Path]::GetFullPath((Join-Path `$ProjectPath 'Research\FormalRuns\Gate13R_ProcessReuse_5pct\v1'))";to="`$formalRoot=[IO.Path]::GetFullPath((Join-Path `$ProjectPath 'Research\FormalRuns\Gate13R_RQAligned\v1'))";count=1},
    [pscustomobject]@{from="DDM.Research.Editor.Gate12RProcessReuseBatchCommandV3.Run";to="DDM.Research.Editor.Gate13RPR1BMemoryAwareProcessReuseBatchCommandV3.Run";count=1},
    [pscustomobject]@{from="`$expectedBlockManagedLimit=[long]134217728*[long]@(`$plan.entries).Count";to="`$expectedBlockManagedLimit=[long]268435456";count=1},
    [pscustomobject]@{from="[int]`$manifest.schemaVersion-ne3-or[string]`$manifest.manifestKind-ne'gate12r-process-reuse-5pct-process-reuse-block-manifest-v2'";to="[int]`$manifest.schemaVersion-ne4-or[string]`$manifest.manifestKind-ne'gate13r-pr1b-v2-memory-aware-process-reuse-block-manifest-v1'";count=1},
    [pscustomobject]@{from="[string]`$manifest.memoryGatePolicyId-ne'gate12r-sample-128mib-block-128mib-per-sample-v1'-or[string]`$manifest.blockManagedLimitFormulaId-ne'checked-sample-limit-times-expected-sample-count-v1'-or[long]`$manifest.maximumSampleRetainedManagedGrowthBytes-ne134217728-or[long]`$manifest.maximumManagedGrowthBytes-ne`$expectedBlockManagedLimit";to="[string]`$manifest.memoryGatePolicyId-ne'gate13r-pr1b-v2-sample-alert-128mib-emergency-256mib-block-256mib-v1'-or[string]`$manifest.blockManagedLimitFormulaId-ne'fixed-two-sample-independent-block-256mib-v1'-or[long]`$manifest.maximumSampleRetainedManagedGrowthBytes-ne268435456-or[long]`$manifest.sampleManagedAlertThresholdBytes-ne134217728-or[long]`$manifest.sampleManagedEmergencyStopBytes-ne268435456-or[long]`$manifest.maximumManagedGrowthBytes-ne`$expectedBlockManagedLimit";count=1},
    [pscustomobject]@{from="if([long]`$a.sampleRetainedManagedGrowthBytes-gt134217728){`$errors.Add(`"Sample retained managed-memory growth exceeded 128 MiB at `$i`")}";to="if([long]`$a.sampleRetainedManagedGrowthBytes-gt268435456){`$errors.Add(`"Sample retained managed-memory growth exceeded emergency 256 MiB at `$i`")}";count=1},
    [pscustomobject]@{from="[int]`$cm.schemaVersion-ne5-or[string]`$cm.memoryGatePolicyId-ne'gate12r-sample-128mib-block-128mib-per-sample-v1'-or[long]`$cm.maximumSampleRetainedManagedGrowthBytes-ne134217728-or`$cm.retainedManagedGrowthWithinLimit-ne`$true";to="[int]`$cm.schemaVersion-ne6-or[string]`$cm.memoryGatePolicyId-ne'gate13r-pr1b-v2-sample-alert-128mib-emergency-256mib-block-256mib-v1'-or[long]`$cm.maximumSampleRetainedManagedGrowthBytes-ne268435456-or[long]`$cm.sampleManagedAlertThresholdBytes-ne134217728-or[long]`$cm.sampleManagedEmergencyStopBytes-ne268435456-or`$cm.sampleEmergencyStopPassed-ne`$true-or`$cm.retainedManagedGrowthWithinLimit-ne`$true";count=1}
)
$routeEvidence=New-Object Collections.Generic.List[object]
foreach($route in $routes){
    $actual=$text.Split([string[]]@([string]$route.from),[StringSplitOptions]::None).Count-1
    if($actual-ne[int]$route.count){throw "Gate13R-PR1B v3 mechanical replacement count was $actual, expected $($route.count)."}
    $text=$text.Replace([string]$route.from,[string]$route.to)
    $routeEvidence.Add([pscustomobject]@{from=[string]$route.from;to=[string]$route.to;replacementCount=$actual})
}

$derivedRoot=$OutputDirectory+'.DerivedHarnessPR1BV3'
if(Test-Path -LiteralPath $derivedRoot){throw "Create-new Gate13R-PR1B v3 derived root exists: $derivedRoot"}
New-Item -ItemType Directory -Path $derivedRoot -Force|Out-Null
$derivedPath=Join-Path $derivedRoot 'Run-Gate13RPR1BMemoryAwareBlockV3.derived.ps1'
[IO.File]::WriteAllText($derivedPath,$text,(New-Object Text.UTF8Encoding($false,$true)))
$derivedReceipt=[ordered]@{
    schemaVersion=1;receiptKind='gate13r-pr1b-v3-pathsafe-memory-aware-block-derived-wrapper-receipt-v1';createdAtUtc=[DateTime]::UtcNow.ToString('o')
    sourceRelativePath='Research/Run-Gate12RProcessReuseBlockV3.ps1';sourceSha256=$actualBaseSha256
    derivedSha256=(Get-FileHash -LiteralPath $derivedPath -Algorithm SHA256).Hash.ToLowerInvariant();routes=$routeEvidence.ToArray()
    researchSemanticsChanged=$false;memoryEligibilityAmendmentApplied=$true;formalCampaign=$false
}
$derivedReceiptPath=Join-Path $derivedRoot 'wrapper-receipt.json'
[IO.File]::WriteAllText($derivedReceiptPath,(($derivedReceipt|ConvertTo-Json -Depth 20).Replace("`r`n","`n").Replace("`r","`n")+"`n"),(New-Object Text.UTF8Encoding($false,$true)))

$windowsPowerShell='C:\WINDOWS\System32\WindowsPowerShell\v1.0\powershell.exe'
$nativeModulePath=@('C:\Users\bdscy\Documents\WindowsPowerShell\Modules','C:\Program Files\WindowsPowerShell\Modules','C:\WINDOWS\System32\WindowsPowerShell\v1.0\Modules')-join';'
$stdout=Join-Path $derivedRoot 'child.stdout.log'
$stderr=Join-Path $derivedRoot 'child.stderr.log'
$arguments=@('-NoProfile','-ExecutionPolicy','Bypass','-File',$derivedPath,'-BlockPlanPath',$BlockPlanPath,'-OutputDirectory',$OutputDirectory,'-AllowedRoot',$AllowedRoot,'-Mode',$Mode,'-UnityPath',$UnityPath,'-ProjectPath',$ProjectPath,'-TimeoutSeconds',$TimeoutSeconds)
if($ExpectFailure){$arguments+=@('-ExpectFailure','-ExpectedCompletedSamplesBeforeFailure',$ExpectedCompletedSamplesBeforeFailure)}
$oldModulePath=$env:PSModulePath
try{$env:PSModulePath=$nativeModulePath;&$windowsPowerShell @arguments 1>$stdout 2>$stderr;$childExit=[int]$LASTEXITCODE}finally{$env:PSModulePath=$oldModulePath}
if($childExit-ne0){Write-Error "Gate13R-PR1B v3 derived block child failed: exit=$childExit stderr=$stderr";exit $childExit}
if($ExpectFailure){Write-Host 'Gate13R-PR1B v3 negative fail-closed block passed.' -ForegroundColor Green;exit 0}

$failurePath=$OutputDirectory+'.memory-v3-wrapper-failure.json'
try{
    $manifestPath=Join-Path $OutputDirectory 'block-manifest.json'
    $manifest=Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8|ConvertFrom-Json
    if([int]$manifest.schemaVersion-ne4-or[string]$manifest.manifestKind-ne'gate13r-pr1b-v2-memory-aware-process-reuse-block-manifest-v1'){throw 'Memory-v2 block manifest identity mismatch.'}
    if([int]$manifest.expectedSampleCount-ne2-or[int]$manifest.completedSampleCount-ne2-or@($manifest.samples).Count-ne2){throw 'Memory-v2 wrapper only accepts a complete two-sample independent block.'}
    if([string]$manifest.memoryGatePolicyId-ne'gate13r-pr1b-v2-sample-alert-128mib-emergency-256mib-block-256mib-v1'-or[string]$manifest.blockManagedLimitFormulaId-ne'fixed-two-sample-independent-block-256mib-v1'){throw 'Memory-v2 policy identity mismatch.'}
    if([long]$manifest.maximumManagedGrowthBytes-ne268435456-or[long]$manifest.maximumNativeGrowthBytes-ne536870912-or$manifest.hardMemoryRulesPassed-ne$true){throw 'Memory-v2 block hard-limit contract mismatch.'}
    $alertCount=0
    foreach($sample in @($manifest.samples)){
        $evaluationPath=Join-Path $OutputDirectory ([string]$sample.memoryGateEvaluationRelativePath).Replace('/','\')
        if(-not(Test-Path -LiteralPath $evaluationPath -PathType Leaf)){throw "Memory evaluation missing: $evaluationPath"}
        $evaluationSha=(Get-FileHash -LiteralPath $evaluationPath -Algorithm SHA256).Hash.ToLowerInvariant()
        if($evaluationSha-ne[string]$sample.memoryGateEvaluationSha256){throw "Memory evaluation hash mismatch: $evaluationPath"}
        $evaluation=Get-Content -LiteralPath $evaluationPath -Raw -Encoding UTF8|ConvertFrom-Json
        if([int]$evaluation.schemaVersion-ne1-or[string]$evaluation.evaluationKind-ne'gate13r-pr1b-v2-memory-gate-evaluation-v1'-or$evaluation.completed-ne$true-or$evaluation.telemetryValid-ne$true-or$evaluation.sampleEmergencyStopPassed-ne$true){throw "Memory evaluation is incomplete or ineligible: $evaluationPath"}
        if([string]$evaluation.verdict-notin@('PASS','MEMORY-ALERT-128MIB')){throw "Unexpected passing evaluation verdict: $($evaluation.verdict)"}
        if([long]$evaluation.sampleManagedAlertThresholdBytes-ne134217728-or[long]$evaluation.sampleManagedEmergencyStopBytes-ne268435456-or[long]$evaluation.blockRetainedManagedGrowthHardLimitBytes-ne268435456){throw 'Memory evaluation threshold mismatch.'}
        if([bool]$evaluation.sampleMemoryAlert128MiB){$alertCount++}
        $childManifestPath=Join-Path $OutputDirectory ([string]$sample.manifestRelativePath).Replace('/','\')
        $childManifest=Get-Content -LiteralPath $childManifestPath -Raw -Encoding UTF8|ConvertFrom-Json
        if([int]$childManifest.schemaVersion-ne6-or[string]$childManifest.memoryGateEvaluationSha256-ne$evaluationSha-or[string]$childManifest.memoryGateVerdict-ne[string]$evaluation.verdict){throw 'Child manifest is not byte-bound to its memory evaluation.'}
    }
    if($alertCount-ne[int]$manifest.memoryAlertSampleCount-or([bool]$manifest.anySampleMemoryAlert128MiB)-ne($alertCount-gt0)){throw 'Block memory-alert aggregation mismatch.'}

    Import-Module $canonicalModule -Force
    $beforeBytes=[long](Get-ChildItem -LiteralPath $OutputDirectory -Recurse -File -Force|Measure-Object Length -Sum).Sum
    $referenceResult=Invoke-Gate12RCanonicalInputExternalization -ProjectPath $ProjectPath -OutputDirectory $OutputDirectory -BlockPlanPath $BlockPlanPath
    if($referenceResult.passed-ne$true){throw 'Canonical input externalization did not return passed=true.'}
    $afterBytes=[long](Get-ChildItem -LiteralPath $OutputDirectory -Recurse -File -Force|Measure-Object Length -Sum).Sum
    $summaryPath=$OutputDirectory+'.summary.json'
    $summary=Get-Content -LiteralPath $summaryPath -Raw -Encoding UTF8|ConvertFrom-Json
    $updates=[ordered]@{
        summaryKind='gate13r-pr1b-v3-pathsafe-memory-aware-block-wrapper-summary-v1'
        memoryGatePolicyId='gate13r-pr1b-v2-sample-alert-128mib-emergency-256mib-block-256mib-v1'
        maximumSampleRetainedManagedGrowthBytes=268435456L
        sampleManagedAlertThresholdBytes=134217728L
        sampleManagedEmergencyStopBytes=268435456L
        memoryAlertSampleCount=$alertCount
        derivedHarnessReceiptRelativePath=([IO.Path]::GetFileName($derivedRoot)+'/'+[IO.Path]::GetFileName($derivedReceiptPath))
        derivedHarnessReceiptSha256=(Get-FileHash -LiteralPath $derivedReceiptPath -Algorithm SHA256).Hash.ToLowerInvariant()
        canonicalScenarioStorageKind=[string]$referenceResult.storageKind
        canonicalInputReferenceReceiptRelativePath='canonical-input-reference-receipt.json'
        canonicalInputReferenceReceiptSha256=[string]$referenceResult.receiptSha256
        canonicalReferenceCount=[int]$referenceResult.referenceCount
        canonicalLogicalRawBytesRemoved=[long]$referenceResult.removedLocalCanonicalRawBytes
        blockRawBytesBeforeExternalization=$beforeBytes
        blockRawBytesAfterExternalization=$afterBytes
        canonicalReferenceValidationPassed=$true
    }
    foreach($name in $updates.Keys){if($null-ne$summary.PSObject.Properties[$name]){$summary.$name=$updates[$name]}else{$summary|Add-Member -NotePropertyName $name -NotePropertyValue $updates[$name]}}
    $json=($summary|ConvertTo-Json -Depth 50).Replace("`r`n","`n").Replace("`r","`n")+"`n"
    $summaryParent=[IO.Path]::GetDirectoryName([IO.Path]::GetFullPath($summaryPath));$tmp=Join-Path $summaryParent ('.g13tmp-'+[Guid]::NewGuid().ToString('N'));$owned=$false
    try{[IO.File]::WriteAllText($tmp,$json,(New-Object Text.UTF8Encoding($false,$true)));$owned=$true;[IO.File]::Replace($tmp,$summaryPath,$null);$owned=$false}finally{if($owned-and(Test-Path -LiteralPath $tmp)){[IO.File]::Delete($tmp)}}
    Write-Host ("Gate13R-PR1B v3 block passed; alerts={0}, canonical duplicated bytes removed={1}."-f$alertCount,$referenceResult.removedLocalCanonicalRawBytes) -ForegroundColor Green
    exit 0
}catch{
    $failure=[ordered]@{schemaVersion=1;receiptKind='gate13r-pr1b-v3-pathsafe-memory-aware-wrapper-failure-v1';failedAtUtc=[DateTime]::UtcNow.ToString('o');message=$_.Exception.ToString();baseBlockPassed=$true;memoryEvidenceValidationPassed=$false;canonicalExternalizationPassed=$false;formalCampaign=$false;automaticRetryAttempted=$false;automaticResumeAttempted=$false;passed=$false}
    $failureJson=(($failure|ConvertTo-Json -Depth 20).Replace("`r`n","`n").Replace("`r","`n")+"`n");$failureParent=[IO.Path]::GetDirectoryName([IO.Path]::GetFullPath($failurePath));$failureTmp=Join-Path $failureParent ('.g13tmp-'+[Guid]::NewGuid().ToString('N'));$failureOwned=$false
    try{[IO.File]::WriteAllText($failureTmp,$failureJson,(New-Object Text.UTF8Encoding($false,$true)));$failureOwned=$true;[IO.File]::Move($failureTmp,$failurePath);$failureOwned=$false}finally{if($failureOwned-and(Test-Path -LiteralPath $failureTmp)){[IO.File]::Delete($failureTmp)}}
    Write-Error "Gate13R-PR1B v3 post-block validation failed: $($_.Exception.Message)"
    exit 1
}


