[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$ProjectPath,
    [switch]$BindingSmokeOnly
)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($ProjectPath) -or -not [IO.Path]::IsPathRooted($ProjectPath)) { throw 'Attempt 4 requires an explicit absolute ProjectPath.' }
$ProjectPath = [IO.Path]::GetFullPath($ProjectPath)
if ($BindingSmokeOnly) { Write-Output ('BINDING-SMOKE-PASSED|Run-Gate10RFinalAuditV4R2|' + $ProjectPath); exit 0 }

$researchPath = Join-Path $ProjectPath 'Research'
$modulePath = Join-Path $researchPath 'Gate10RProcessReusePreparation.psm1'
$lockModulePath = Join-Path $researchPath 'Gate10RLockHygieneV3.psm1'
Import-Module $modulePath -Force
Import-Module $lockModulePath -Force
$root = Join-Path $PSScriptRoot 'Gate10R_ProcessReuse_5pct\v4'
$summaryPath = Join-Path $root 'Gate10R_FinalAudit.summary.v4.json'
$manifestPath = Join-Path $root 'Gate10R_Evidence_Manifest.v4.json'
$checkpointPath = Join-Path $root 'gate10r-checkpoint.json'
foreach ($path in @($summaryPath, $manifestPath, $checkpointPath)) {
    if (Test-Path -LiteralPath $path) { throw "Gate 10R attempt-4 final evidence exists; refusing retry/overwrite: $path" }
}

$checks = New-Object System.Collections.Generic.List[object]
function Add-Check([string]$Name, [bool]$Passed, [string]$Detail) {
    $script:checks.Add([pscustomobject][ordered]@{name=$Name;passed=$Passed;detail=$Detail})
}
function Load-JsonIfPresent([string]$Path) {
    if (Test-Path -LiteralPath $Path -PathType Leaf) { return Read-Gate10RJson -Path $Path }
    return $null
}
function Get-TreeIdentity([string]$Path) {
    $treeRoot = [IO.Path]::GetFullPath($Path)
    $files = @(Get-ChildItem -LiteralPath $treeRoot -Recurse -File -Force | Sort-Object FullName)
    $rows = New-Object System.Collections.Generic.List[string]
    foreach ($file in $files) {
        $relative = $file.FullName.Substring($treeRoot.Length).TrimStart('\').Replace('\', '/')
        $rows.Add(("{0}`t{1}`t{2}" -f $relative, $file.Length, (Get-Gate10RLowerSha256 -Path $file.FullName)))
    }
    return [pscustomobject][ordered]@{
        fileCount = $files.Count
        rawBytes = [long](($files | Measure-Object Length -Sum).Sum)
        treeSha256 = Get-Gate10RStringSha256V3 -Value ($rows -join "`n")
    }
}
function Test-BoundReference($Reference) {
    if ($null -eq $Reference -or [string]::IsNullOrWhiteSpace([string]$Reference.relativePath) -or [string]::IsNullOrWhiteSpace([string]$Reference.sha256)) { return $false }
    $path = Join-Path $ProjectPath ([string]$Reference.relativePath).Replace('/', '\')
    return (Test-Path -LiteralPath $path -PathType Leaf) -and (Get-Gate10RLowerSha256 -Path $path) -eq [string]$Reference.sha256
}
function Test-ReceiptBinding([string]$Path, [string]$ExpectedSha256) {
    return (Test-Path -LiteralPath $Path -PathType Leaf) -and (Get-Gate10RLowerSha256 -Path $Path) -eq $ExpectedSha256
}
function Get-ProtectedRootStats([string]$RelativePath) {
    $path = Join-Path $ProjectPath $RelativePath
    if (-not (Test-Path -LiteralPath $path -PathType Container)) { return [pscustomobject]@{exists=$false;files=0;bytes=0L;nonReadOnly=0} }
    $files = @(Get-ChildItem -LiteralPath $path -Recurse -File -Force)
    return [pscustomobject]@{exists=$true;files=$files.Count;bytes=[long](($files | Measure-Object Length -Sum).Sum);nonReadOnly=@($files | Where-Object {-not $_.IsReadOnly}).Count}
}

$unitPath = Join-Path $root 'UnitTests.summary.json'
$compilePath = Join-Path $root 'Compile\attempt4.summary.json'
$probePath = Join-Path $root 'TelemetryProbe\v1.summary.json'
$blockPath = Join-Path $root 'BlockVerification.summary.json'
$regressionPath = Join-Path $root 'RetainedRegression\RetainedRegression63.summary.json'
$regressionWrapperPath = Join-Path $root 'RetainedRegression\RetainedRegression63.wrapper.v4.json'
$preflightPath = Join-Path $root 'Gate10R_Attempt4_Preflight.summary.v4.json'
$preflightCheckpointPath = Join-Path $root 'gate10r-preflight-checkpoint.v4.json'
$receiptPath = Join-Path $root 'Gate10R_Attempt4_Execution_Receipt.v4.json'
$unit = Load-JsonIfPresent $unitPath
$compile = Load-JsonIfPresent $compilePath
$probe = Load-JsonIfPresent $probePath
$block = Load-JsonIfPresent $blockPath
$regression = Load-JsonIfPresent $regressionPath
$regressionWrapper = Load-JsonIfPresent $regressionWrapperPath
$preflight = Load-JsonIfPresent $preflightPath
$preflightCheckpoint = Load-JsonIfPresent $preflightCheckpointPath
$receipt = Load-JsonIfPresent $receiptPath

Add-Check 'no-prior-final-evidence' $true 'create-new paths confirmed'
Add-Check 'preflight-pass' ($null -ne $preflight -and $preflight.passed -eq $true -and [int]$preflight.failedCount -eq 0 -and $preflight.unityStarted -eq $false) $(if ($null -eq $preflight) {'missing'} else {"$($preflight.passedCount)/$($preflight.assertionCount)"})
Add-Check 'preflight-checkpoint' ($null -ne $preflightCheckpoint -and [string]$preflightCheckpoint.status -eq 'GATE10R-ATTEMPT4-OFFICIAL-PREFLIGHT-PASSED-RECEIPT-CONSUMED' -and [int]$preflightCheckpoint.officialExecutionCount -eq 1) $(if ($null -eq $preflightCheckpoint) {'missing'} else {[string]$preflightCheckpoint.status})
Add-Check 'unit-tests' ($null -ne $unit -and $unit.passed -eq $true -and [int]$unit.failedCount -eq 0) $(if ($null -eq $unit) {'missing'} else {"$($unit.passedCount)/$($unit.assertionCount)"})
Add-Check 'unity-compile' ($null -ne $compile -and $compile.passed -eq $true -and [int]$compile.exitCode -eq 0 -and [int]$compile.compilerErrorMatchCount -eq 0 -and [string]$compile.lockHygieneMode -eq 'natural-lock-absence') $(if ($null -eq $compile) {'missing'} else {"exit=$($compile.exitCode);lock=$($compile.lockHygieneMode)"})
Add-Check 'telemetry-probe' ($null -ne $probe -and $probe.passed -eq $true -and [int]$probe.exitCode -eq 0 -and [string]$probe.lockHygieneMode -eq 'natural-lock-absence') $(if ($null -eq $probe) {'missing'} else {"pid=$($probe.unityProcessId);lock=$($probe.lockHygieneMode)"})
Add-Check 'block-verification' ($null -ne $block -and $block.passed -eq $true -and [int]$block.structuralMismatchCount -eq 0) $(if ($null -eq $block) {'missing'} else {"comparisons=$($block.structuralComparisonCount);mismatch=$($block.structuralMismatchCount)"})
Add-Check 'block-cardinality' ($null -ne $block -and [int]$block.invocationCount -eq 4 -and [int]$block.freshColdReferenceCount -eq 6 -and [int]$block.structuralComparisonCount -eq 10) $(if ($null -eq $block) {'missing'} else {"$($block.invocationCount)/$($block.freshColdReferenceCount)/$($block.structuralComparisonCount)"})
Add-Check 'independent-process-repeatability' ($null -ne $block -and $block.distinctPositiveProcessIdsPassed -eq $true -and $block.independentProcessRepeatabilityPassed -eq $true) 'required'
Add-Check 'negative-fail-closed' ($null -ne $block -and $block.negativeFailClosedPassed -eq $true) 'required'
Add-Check 'lock-hygiene-modes' ($null -ne $block -and $block.positiveNaturalLockReleasePassed -eq $true -and $block.negativeLockHygienePassed -eq $true -and $block.coldNaturalLockReleasePassed -eq $true -and [string]$block.negativeLockHygieneMode -in @('natural-lock-absence','controlled-expected-negative-cleanup')) $(if ($null -eq $block) {'missing'} else {"negative=$($block.negativeLockHygieneMode)"})
Add-Check 'retained-regression-63' ($null -ne $regression -and $regression.passed -eq $true -and [int]$regression.assertionCount -eq 63 -and @($regression.failures).Count -eq 0) $(if ($null -eq $regression) {'missing'} else {"failures=$(@($regression.failures).Count);assertions=$($regression.assertionCount)"})
Add-Check 'retained-regression-file-scope-wrapper' ($null -ne $regressionWrapper -and $regressionWrapper.passed -eq $true -and [string]$regressionWrapper.executionMethod -eq 'Windows PowerShell 5.1 -File' -and $regressionWrapper.childScriptBlockUsed -eq $false -and [int]$regressionWrapper.assertionCount -eq 63 -and [int]$regressionWrapper.failureCount -eq 0) $(if ($null -eq $regressionWrapper) {'missing'} else {[string]$regressionWrapper.executionMethod})

$configPath = Join-Path $researchPath 'Gate10R_ProcessReuse_5pct_Attempt4_Config.v4.json'
$provenancePath = Join-Path $researchPath 'Gate10R_ProcessReuse_5pct_Attempt4_Provenance.v4.json'
$retryProvenancePath = Join-Path $researchPath 'Gate10R_ProcessReuse_5pct_Attempt4_PreflightRetry_Provenance.v4.2.json'
$authorizationPath = Join-Path $researchPath 'Gate10R_Attempt4_Execution_Authorization.v1.json'
$config = Read-Gate10RJson -Path $configPath
$provenance = Read-Gate10RJson -Path $provenancePath
$retryProvenance = Read-Gate10RJson -Path $retryProvenancePath
$authorization = Read-Gate10RJson -Path $authorizationPath
Add-Check 'config-identity' ([int]$config.attempt -eq 4 -and [string]$config.designId -eq 'gate10r-one-fresh-unity-process-per-williams-block-5pct-v1' -and [string]$config.changeClass -eq 'ORCHESTRATION-RETAINED-REGRESSION-FILE-SCOPE-ONLY' -and $config.formalCampaign -eq $false) ([string]$config.configId)
Add-Check 'provenance-identity' ([int]$provenance.attempt -eq 4 -and [string]$provenance.designId -eq [string]$config.designId -and $provenance.formalCampaign -eq $false) ([string]$provenance.provenanceId)
Add-Check 'retry-provenance-identity' ([string]$retryProvenance.provenanceId -eq 'gate10r-attempt4-outside-preflight-retry2-provenance-v4.2' -and [string]$retryProvenance.baseProvenance.sha256 -eq (Get-Gate10RLowerSha256 -Path $provenancePath) -and $retryProvenance.formalCampaign -eq $false) ([string]$retryProvenance.provenanceId)
Add-Check 'authorization-gate10-only' ([int]$authorization.attempt -eq 4 -and [string]$authorization.status -eq 'AUTHORIZED-GATE10R-ATTEMPT4-SERIES-ONLY' -and $authorization.gate11RConditionalContinuationAuthorized -eq $false -and $authorization.gate12RConditionalContinuationAuthorized -eq $false -and $authorization.gate13RFormalCampaignAuthorized -eq $false -and [int]$authorization.attempt4MaximumOfficialExecutionsPerReceipt -eq 1) ([string]$authorization.authorizationId)

$references = @($provenance.boundFiles) + @($retryProvenance.boundFiles)
$referenceErrors = New-Object System.Collections.Generic.List[string]
foreach ($reference in $references) {
    if (-not (Test-BoundReference -Reference $reference)) { $referenceErrors.Add([string]$reference.relativePath) }
}
Add-Check 'provenance-file-bindings' ($referenceErrors.Count -eq 0) ($referenceErrors -join ';')
Add-Check 'unity-binary-bound' ((Get-Gate10RLowerSha256 -Path 'H:\UnityEditor\2022.3.30f1c1\Editor\Unity.exe') -eq [string]$provenance.unity.sha256) ([string]$provenance.unity.sha256)

$outsidePreflightPath = Join-Path $PSScriptRoot 'Gate10R_Attempt4_Preflight\v3\Gate10R_Attempt4_OutsideRoot_Preflight.summary.v4.json'
$receiptOk = $null -ne $receipt -and [string]$receipt.status -eq 'CONSUMED-FOR-ONE-OFFICIAL-GATE10R-EXECUTION' -and [int]$receipt.attempt -eq 4 -and [int]$receipt.maximumExecutionsForThisReceipt -eq 1 -and $receipt.gate11RAuthorized -eq $false -and $receipt.gate12RAuthorized -eq $false -and $receipt.gate13RAuthorized -eq $false -and [string]$receipt.config.sha256 -eq (Get-Gate10RLowerSha256 -Path $configPath) -and [string]$receipt.provenance.sha256 -eq (Get-Gate10RLowerSha256 -Path $provenancePath) -and [string]$receipt.retryProvenance.sha256 -eq (Get-Gate10RLowerSha256 -Path $retryProvenancePath) -and [string]$receipt.outsidePreflight.sha256 -eq (Get-Gate10RLowerSha256 -Path $outsidePreflightPath)
Add-Check 'attempt4-execution-receipt' $receiptOk $(if ($null -eq $receipt) {'missing'} else {[string]$receipt.status})

Add-Check 'outside-root-preflight-bound' ((Test-Path -LiteralPath $outsidePreflightPath -PathType Leaf) -and [string]$receipt.outsidePreflight.sha256 -eq (Get-Gate10RLowerSha256 -Path $outsidePreflightPath)) ([string]$receipt.outsidePreflight.sha256)
Add-Check 'frozen-retained-source-unchanged' ((Get-Gate10RLowerSha256 -Path (Join-Path $PSScriptRoot 'Run-Gate12AnalysisUnitTests.ps1')) -eq 'e56a3881c0fc9fc3ecceb760d1c51129e80ec2b306acdcfefed0a3814a6885b1') 'e56a3881...6885b1'
Add-Check 'frozen-retained-summary-unchanged' ((Get-Gate10RLowerSha256 -Path (Join-Path $PSScriptRoot 'Gate12_AnalysisUnitTests.summary.json')) -eq '1536ae459c3d8cbb90b8a9dad1f74e7937d5ceb205e6cc088745c798d136e54d') '1536ae45...136e54d'

$attempt1Identity = Get-TreeIdentity -Path (Join-Path $PSScriptRoot 'Gate10R_ProcessReuse_5pct\v1')
$attempt2Identity = Get-TreeIdentity -Path (Join-Path $PSScriptRoot 'Gate10R_ProcessReuse_5pct\v2')
$attempt3Identity = Get-TreeIdentity -Path (Join-Path $PSScriptRoot 'Gate10R_ProcessReuse_5pct\v3')
Add-Check 'attempt1-tree-byte-identical' ($attempt1Identity.fileCount -eq 4 -and $attempt1Identity.rawBytes -eq 9577 -and $attempt1Identity.treeSha256 -eq '2baa66eb6ee95ecf0f68667b2790fba2a30ce8a24f54e8f9fe477cdc716b9e3d') ($attempt1Identity | ConvertTo-Json -Compress)
Add-Check 'attempt2-tree-byte-identical' ($attempt2Identity.fileCount -eq 101 -and $attempt2Identity.rawBytes -eq 9375526 -and $attempt2Identity.treeSha256 -eq 'da9e6312e74db1bc1207660cf90eef28321ecda0abf1297be6c9298e6270dbce') ($attempt2Identity | ConvertTo-Json -Compress)
Add-Check 'attempt3-tree-byte-identical' ($attempt3Identity.fileCount -eq 165 -and $attempt3Identity.rawBytes -eq 14661809 -and $attempt3Identity.treeSha256 -eq '29f5aa8f0461abb120792dea0f2806e46e4dc9836aa843ce747f2436c1645a23') ($attempt3Identity | ConvertTo-Json -Compress)

if ($null -ne $block) {
    foreach ($invocation in @($block.invocations)) {
        $expectedMode = if ($invocation.expectedFailure) { @('natural-lock-absence','controlled-expected-negative-cleanup') } else { @('natural-lock-absence') }
        $receiptFile = if ([string]::IsNullOrWhiteSpace([string]$invocation.lockHygieneReceiptSha256)) { $null } else {
            Get-ChildItem -LiteralPath $root -Recurse -File -Force | Where-Object {(Get-Gate10RLowerSha256 -Path $_.FullName) -eq [string]$invocation.lockHygieneReceiptSha256} | Select-Object -First 1
        }
        Add-Check ('block-lock-receipt-' + [string]$invocation.name) ([string]$invocation.lockHygieneMode -in $expectedMode -and $null -ne $receiptFile) ("mode={0};sha={1}" -f $invocation.lockHygieneMode, $invocation.lockHygieneReceiptSha256)
    }
    foreach ($coldReference in @($block.coldReferences)) {
        Add-Check ("cold-lock-natural-$($coldReference.scenarioId)-$($coldReference.algorithmId)") ([string]$coldReference.lockHygieneMode -eq 'natural-lock-absence') ([string]$coldReference.summarySha256)
    }
}

foreach ($fixtureName in @('positive-two','positive-four-a','positive-four-b')) {
    $fixturePath = Join-Path $root "Fixtures\v1\$fixtureName\block-manifest.json"
    $fixture = Load-JsonIfPresent $fixturePath
    $fixtureOk = $null -ne $fixture -and $fixture.completed -eq $true -and $fixture.formalCampaign -eq $false -and $fixture.oneBlockPerUnityProcess -eq $true -and $fixture.oneSamplePerAlgorithmPerProcess -eq $true -and $fixture.allSamplesShareProcessId -eq $true -and $fixture.hardMemoryRulesPassed -eq $true -and [long]$fixture.blockRetainedManagedGrowthBytes -le 134217728 -and [long]$fixture.blockWorkingSetGrowthBytes -le 536870912 -and [long]$fixture.blockPrivateMemoryGrowthBytes -le 536870912
    Add-Check ("fixture-$fixtureName") $fixtureOk $(if ($null -eq $fixture) {'missing'} else {"pid=$($fixture.processId);samples=$($fixture.completedSampleCount)"})
}
$negativePath = Join-Path $root 'Fixtures\v1\negative-fail-closed\block-checkpoint.json'
$negative = Load-JsonIfPresent $negativePath
Add-Check 'negative-terminal-state' ($null -ne $negative -and [string]$negative.status -eq 'failed-no-auto-retry' -and [int]$negative.completedSampleCount -eq 1 -and $negative.automaticRetryAuthorized -eq $false -and $negative.automaticResumeAuthorized -eq $false) $(if ($null -eq $negative) {'missing'} else {[string]$negative.status})

$coldHistorical = Get-ProtectedRootStats -RelativePath 'Research\FormalRuns\Gate13\v1'
$reuseV1Historical = Get-ProtectedRootStats -RelativePath 'Research\PilotRuns\Gate13_ProcessReuse\v1'
$reuseV2Historical = Get-ProtectedRootStats -RelativePath 'Research\PilotRuns\Gate13_ProcessReuse\v2'
Add-Check 'historical-cold-root' ($coldHistorical.exists -and $coldHistorical.files -eq 891 -and $coldHistorical.bytes -eq 129667391 -and $coldHistorical.nonReadOnly -eq 0) ("$($coldHistorical.files)/$($coldHistorical.bytes)/$($coldHistorical.nonReadOnly)")
Add-Check 'historical-process-reuse-v1-root' ($reuseV1Historical.exists -and $reuseV1Historical.files -eq 838 -and $reuseV1Historical.bytes -eq 91219643 -and $reuseV1Historical.nonReadOnly -eq 0) ("$($reuseV1Historical.files)/$($reuseV1Historical.bytes)/$($reuseV1Historical.nonReadOnly)")
Add-Check 'historical-process-reuse-v2-root' ($reuseV2Historical.exists -and $reuseV2Historical.files -eq 4 -and $reuseV2Historical.bytes -eq 8899 -and $reuseV2Historical.nonReadOnly -eq 0) ("$($reuseV2Historical.files)/$($reuseV2Historical.bytes)/$($reuseV2Historical.nonReadOnly)")
Add-Check 'original-archive-unchanged' ((Get-Gate10RLowerSha256 -Path 'H:\DDM_Final_Project_Original.zip') -eq 'b2431197f962fab8af8893772e822ee641a575120a95e47f04444e5172bcd5aa') 'b2431197...bcd5aa'

$forbidden = @(
    'Research\FormalScenarios\Gate11R_5pct\v1',
    'Research\PlayableExperiments\Gate11R_5pct\v1',
    'Assets\_Scenes\Research\Playable\Gate11R_5pct\v1',
    'Research\PilotRuns\Gate12R_ProcessReuse_5pct\v1',
    'Research\FormalRuns\Gate13R_ProcessReuse_5pct\v1'
)
foreach ($relative in $forbidden) { Add-Check ('absent-' + $relative.Replace('\','-')) (-not (Test-Path -LiteralPath (Join-Path $ProjectPath $relative))) 'absent' }
Add-Check 'no-unity-process' (@(Get-Process -Name Unity -ErrorAction SilentlyContinue).Count -eq 0) 'zero'
Add-Check 'no-project-lock' (-not (Test-Path -LiteralPath (Join-Path $ProjectPath 'Temp\UnityLockfile'))) 'absent'

$failed = @($checks | Where-Object {-not $_.passed})
$artifacts = New-Object System.Collections.Generic.List[object]
foreach ($file in @(Get-ChildItem -LiteralPath $root -Recurse -File -Force | Sort-Object FullName)) {
    if ($file.FullName -in @($summaryPath, $manifestPath, $checkpointPath)) { continue }
    $artifacts.Add([pscustomobject][ordered]@{
        relativePath = Get-Gate10RProjectRelativePath -ProjectPath $ProjectPath -FullPath $file.FullName
        bytes = [long]$file.Length
        sha256 = Get-Gate10RLowerSha256 -Path $file.FullName
    })
}
$manifest = [ordered]@{
    schemaVersion = 1
    manifestId = 'gate10r-process-reuse-5pct-evidence-manifest-attempt4-v4'
    createdAtUtc = [DateTime]::UtcNow.ToString('o')
    attempt = 4
    designId = [string]$provenance.designId
    artifactCount = $artifacts.Count
    artifacts = $artifacts.ToArray()
    gate11RAuthorized = $false
    gate12RAuthorized = $false
    gate13RAuthorized = $false
    formalCampaign = $false
}
Write-Gate10RAtomicUtf8NoBomJson -Path $manifestPath -Value $manifest -Depth 60
$summary = [ordered]@{
    schemaVersion = 1
    summaryKind = 'gate10r-final-audit-attempt4-v4'
    savedAtUtc = [DateTime]::UtcNow.ToString('o')
    attempt = 4
    assertionCount = $checks.Count
    passedCount = $checks.Count - $failed.Count
    failedCount = $failed.Count
    checks = $checks.ToArray()
    evidenceManifestRelativePath = Get-Gate10RProjectRelativePath -ProjectPath $ProjectPath -FullPath $manifestPath
    evidenceManifestSha256 = Get-Gate10RLowerSha256 -Path $manifestPath
    gate11RAuthorized = $false
    gate12RAuthorized = $false
    gate13RAuthorized = $false
    formalCampaign = $false
    automaticRetryAttempted = $false
    automaticResumeAttempted = $false
    passed = $failed.Count -eq 0
}
Write-Gate10RAtomicUtf8NoBomJson -Path $summaryPath -Value $summary -Depth 60
$checkpoint = [ordered]@{
    schemaVersion = 1
    checkpointKind = 'gate10r-process-reuse-5pct-checkpoint-attempt4-v4'
    savedAtUtc = [DateTime]::UtcNow.ToString('o')
    status = if ($summary.passed) {'GATE10R-PASSED-WAITING-FOR-USER-AUTHORIZATION'} else {'GATE10R-ATTEMPT4-FAILED-ATOMIC-CLOSURE-RETRY-AUTHORIZED'}
    attempt = 4
    officialExecutionCount = 1
    designId = [string]$provenance.designId
    summarySha256 = Get-Gate10RLowerSha256 -Path $summaryPath
    evidenceManifestSha256 = Get-Gate10RLowerSha256 -Path $manifestPath
    automaticRetryAuthorized = $true
    automaticResumeAuthorized = $true
    stopOnFirstPass = $true
    gate11RAuthorized = $false
    gate12RAuthorized = $false
    gate13RPreparationAuthorized = $false
    gate13RFormalCampaignAuthorized = $false
    formalCampaign = $false
}
Write-Gate10RAtomicUtf8NoBomJson -Path $checkpointPath -Value $checkpoint -Depth 20
if (-not $summary.passed) { Write-Error "Gate 10R attempt-4 final audit failed: $($failed.name -join ', ')"; exit 1 }
Write-Host "Gate 10R attempt-4 final audit passed: $($checks.Count)/$($checks.Count); Gate 11R and Gate 12R remain unauthorized." -ForegroundColor Green
exit 0
