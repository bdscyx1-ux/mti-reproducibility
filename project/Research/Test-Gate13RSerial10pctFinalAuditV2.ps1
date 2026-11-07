[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$ProjectPath,
    [Parameter(Mandatory = $true)][string]$SummaryPath
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

if ([string]::IsNullOrWhiteSpace($ProjectPath) -or -not [IO.Path]::IsPathRooted($ProjectPath)) {
    throw 'Gate13R serial final audit requires an explicit absolute ProjectPath.'
}
$ProjectPath = [IO.Path]::GetFullPath($ProjectPath).TrimEnd('\', '/')
$SummaryPath = [IO.Path]::GetFullPath($SummaryPath)
$formalRootV1 = [IO.Path]::GetFullPath((Join-Path $ProjectPath 'Research\FormalRuns\Gate13R_Serial_10pct\v1')).TrimEnd('\', '/')
$formalRootV2 = [IO.Path]::GetFullPath((Join-Path $ProjectPath 'Research\FormalRuns\Gate13R_Serial_10pct\v2')).TrimEnd('\', '/')

function Get-ProjectPath([string]$RelativePath) {
    return [IO.Path]::GetFullPath((Join-Path $ProjectPath $RelativePath.Replace('/', '\')))
}

function Get-LowerSha256([string]$Path) {
    return (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToLowerInvariant()
}

function Read-Json([string]$Path) {
    return [IO.File]::ReadAllText($Path, [Text.Encoding]::UTF8) | ConvertFrom-Json
}

function Write-AtomicJson([string]$Path, $Value) {
    $directory = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $directory -PathType Container)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }
    if (Test-Path -LiteralPath $Path) {
        throw "Final-audit output already exists and will not be overwritten: $Path"
    }
    $temporary = $Path + '.tmp-' + [Guid]::NewGuid().ToString('N')
    $json = $Value | ConvertTo-Json -Depth 100
    [IO.File]::WriteAllText($temporary, $json + [Environment]::NewLine, (New-Object Text.UTF8Encoding($false)))
    Move-Item -LiteralPath $temporary -Destination $Path
}

$errors = New-Object Collections.Generic.List[string]
$assertions = 0
function Assert-Condition([bool]$Condition, [string]$Id) {
    $script:assertions++
    if (-not $Condition) { $script:errors.Add($Id) }
}

Assert-Condition (-not $SummaryPath.StartsWith($formalRootV1, [StringComparison]::OrdinalIgnoreCase)) 'summary-inside-formal-root-v1'
Assert-Condition (-not $SummaryPath.StartsWith($formalRootV2, [StringComparison]::OrdinalIgnoreCase)) 'summary-inside-formal-root-v2'
Assert-Condition (-not (Test-Path -LiteralPath $formalRootV1)) 'formal-root-v1-exists'
Assert-Condition (-not (Test-Path -LiteralPath $formalRootV2)) 'formal-root-v2-exists'

$unityProcesses = @(Get-Process -Name Unity -ErrorAction SilentlyContinue)
Assert-Condition ($unityProcesses.Count -eq 0) 'unity-process-running'

$expectedHashes = [ordered]@{
    'Research/Gate13R_Serial_10pct_Selection.v1.json' = '69dd7f80a5bf415ae4d666fbd8e50fce134bc08150e674fcd16c0ca1917f553c'
    'Research/Gate13R_Serial_10pct_Redesign_Specification.v1.md' = '63a417587f05b254f2e42bc8f51b350d920f132795949d95cb7152190b44a940'
    'Research/Gate13R_Serial_10pct_Test_Design.v1.md' = '39cd0a124a6e7f2fca056fd5b887206d8a180e05a493bf552da18fd4bda3ccf3'
    'Research/Gate13R_Serial_10pct_Readiness_Amendment.v1.json' = 'f0a23f29a7b75afb2ebd981bb341d5c3ef2f4bb875b5cd0faf0ead62fe5c4359'
    'Research/Gate13R_Serial_10pct_Formal_Plan.v1.json' = '73bb2ca8ac4862f1addd227e52ec79d01f69f9c2f26910dc85004bc6e09b99ce'
    'Research/Gate13R_Serial_10pct_Gate12R_v4_Evidence_Audit.v1.json' = '84d47ac735a341ae55d8320e83c40833708409c90da47dd40d77cb4b5e14db5f'
    'Research/Gate13R_Serial_10pct_Provenance.v1.json' = '3c86b284010e2f3eea997a1773e85560e971ceafccb8e0652fa6048301d7b388'
    'Research/Gate13R_Serial_10pct_Formal_Campaign_Config.v2.json' = 'faaec5613a2625aee462038305310e229c7cf8fdf67edb800a0b3eb256f1a300'
    'Research/Gate13R_Serial_10pct_Formal_Williams_Block_Schedule.v2.jsonl' = 'd9300cce732e12a7b90ec43ad9d5f8fe52cbad58da713c25879754eb31ea0ead'
    'Research/Gate13R_Serial_10pct_Formal_Williams_Block_Schedule_Manifest.v2.json' = '8bf87ae8c206355930dd6b720756216ef74052ce9d0551680e3a91933a970dc9'
    'Research/Gate13R_Serial_10pct_Formal_Preparation_Provenance.v2.json' = '409b79506b006378c79a0cb777909e0157b9917a2e439c90d59d0679b2340f7b'
    'Research/Gate13RSerial10pctFormalPreparationV2.psm1' = '42896b6c1718a62e343c08ab0caeaa464ecc234cf920d67245f33826d47bf0c2'
    'Research/New-Gate13RSerial10pctFormalPreparationV2.ps1' = '69b2fbe0d6a58e88f4b78795dd939f732685da4545abadccae0885cf78c036b1'
    'Research/Test-Gate13RSerial10pctFormalScheduleV2.ps1' = 'c12686fd056ac637b9b74bc9454063addc061c5dcc0fa869ed1d86ad9d905e18'
    'Research/Run-Gate13RSerial10pctFormalCampaignV2.ps1' = '8bdd8f7b1edc8fc84f8ef35099f103fd55f789f352e47537874f2095a6116770'
    'Research/Run-Gate13RSerial10pctFormalBlockV2.ps1' = 'b4827065ec609f148fa0dd58959cb79e5c9bf54f35fd7aa8b64ef172d820fe1b'
    'Research/Test-Gate13RSerial10pctReadinessV1.ps1' = '6b05a4625c73c0838bffa027c180a98955a29d1039a17ed4131eed4beffe56bc'
    'Assets/_Scripts/Research/Editor/Gate13RProcessReuseFormalBatchCommandV1.cs' = '4ddf154a4ac27d58f3c873d5d983b7ca6abdf2db9b51969ad48b9347cda938d1'
    'Research/Verification/Gate13R_Serial_10pct/v1/ReadinessValidation.summary.json' = 'adcf7605891608cb31e5489a9314a5c4b11b9d51a637921f3292ee23465bfbf5'
    'Research/Verification/Gate13R_Serial_10pct/v5-v2-schedule/ScheduleValidation.summary.json' = '0b10e4dd6e94f2540e456a2a27b43073d06654d53d642769787d54fc102e9132'
    'Research/Verification/Gate13R_Serial_10pct/v6-v2-deterministic/DeterministicRegeneration.summary.json' = 'c23cc4728bf51ac5ff197b308c77dadfe5a6967420b38dd7b3de947189282ec3'
    'Research/Verification/Gate13R_Serial_10pct/v7-v2-orchestrator/OrchestratorValidation.summary.json' = 'b6a7d6f531c88a4514d0bf348b2bc2d5f514373d0ff00c804f25edc3c9f42722'
    'Research/Verification/Gate13R_Serial_10pct/v8-v2-negative-no-receipt/NegativeReceiptGuard.summary.json' = '5455d9bc4af925806ad609e9e8b0723792d726cb95d7ec4c7982221693cbce0b'
    'Research/FormalScenarios/Gate11R_5pct/v1/bundle-manifest.json' = '5baaeec18344a9e99e55da38f3c4875b7e7e9f3bf0add9d5f2d2f1e821b5f7fc'
    'Research/PilotRuns/Gate12R_ProcessReuse_5pct/v4/pilot-execution-manifest.json' = 'fce4c7f9c7fe7df5f424c8a8ae888133942ed49dbede71d4499e502ba812ebd6'
    'Research/PilotRuns/Gate12R_ProcessReuse_5pct/v4/candidate-n-formal.json' = '5e77d9b69c4c0e45dec204ca1943867453d29dcbdf1ebd24f0809af6d649c387'
    'Research/PilotRuns/Gate12R_ProcessReuse_5pct/v4/budget-storage-projection.json' = 'cca76d3206311119b3b81fd72d162f8425a2657f02d85a906a5fc91a35690e1f'
    'Research/Gate12R_Readiness_Checkpoint.v1.json' = '93d1ffac30305ecbc3ff32820aa0eee016c7a2cc6824f41c491aac393cfd291d'
}

$hashEvidence = New-Object Collections.Generic.List[object]
foreach ($item in $expectedHashes.GetEnumerator()) {
    $path = Get-ProjectPath $item.Key
    $exists = Test-Path -LiteralPath $path -PathType Leaf
    Assert-Condition $exists ('missing-' + $item.Key)
    if ($exists) {
        $actual = Get-LowerSha256 $path
        Assert-Condition ($actual -eq $item.Value) ('hash-mismatch-' + $item.Key)
        $hashEvidence.Add([ordered]@{
            relativePath = $item.Key
            sha256 = $actual
            rawBytes = (Get-Item -LiteralPath $path).Length
        })
    }
}

$config = Read-Json (Get-ProjectPath 'Research/Gate13R_Serial_10pct_Formal_Campaign_Config.v2.json')
$provenance = Read-Json (Get-ProjectPath 'Research/Gate13R_Serial_10pct_Formal_Preparation_Provenance.v2.json')
$scheduleManifest = Read-Json (Get-ProjectPath 'Research/Gate13R_Serial_10pct_Formal_Williams_Block_Schedule_Manifest.v2.json')
$readiness = Read-Json (Get-ProjectPath 'Research/Verification/Gate13R_Serial_10pct/v1/ReadinessValidation.summary.json')
$scheduleValidation = Read-Json (Get-ProjectPath 'Research/Verification/Gate13R_Serial_10pct/v5-v2-schedule/ScheduleValidation.summary.json')
$regeneration = Read-Json (Get-ProjectPath 'Research/Verification/Gate13R_Serial_10pct/v6-v2-deterministic/DeterministicRegeneration.summary.json')
$orchestrator = Read-Json (Get-ProjectPath 'Research/Verification/Gate13R_Serial_10pct/v7-v2-orchestrator/OrchestratorValidation.summary.json')
$negativeGuard = Read-Json (Get-ProjectPath 'Research/Verification/Gate13R_Serial_10pct/v8-v2-negative-no-receipt/NegativeReceiptGuard.summary.json')

Assert-Condition ([string]$config.configKind -eq 'gate13r-strict-serial-10pct-formal-campaign-config-v2') 'config-kind'
Assert-Condition ([string]$config.formalDesignId -eq 'gate13r-one-fresh-unity-process-per-williams-block-10pct-uncapped-serial-v2') 'formal-design-id'
Assert-Condition ($config.formalExecutionAuthorized -eq $false) 'formal-execution-authorized'
Assert-Condition ($config.formalRootCreated -eq $false) 'formal-root-created-flag'
Assert-Condition ($config.formalTimingExecuted -eq $false) 'formal-timing-executed-flag'
Assert-Condition ([int]$config.totals.scenarioCount -eq 53) 'scenario-count'
Assert-Condition ([int]$config.totals.campaignCount -eq 74) 'campaign-count'
Assert-Condition ([int]$config.totals.eligibleCellCount -eq 212) 'eligible-cell-count'
Assert-Condition ([int]$config.totals.blockProcessCount -eq 11160) 'block-count'
Assert-Condition ([int]$config.totals.sampleCount -eq 31536) 'sample-count'
Assert-Condition ([double]$config.precision.relativeHalfWidth -eq 0.10) 'precision'
Assert-Condition ($null -eq $config.precision.hardCap) 'hard-cap'
Assert-Condition ([int]$config.processSemantics.maximumConcurrentUnityEditorProcesses -eq 1) 'maximum-concurrency'
Assert-Condition ([int]$config.processSemantics.laneCount -eq 1) 'lane-count'
Assert-Condition ($config.processSemantics.oneFreshUnityEditorProcessPerCompleteWilliamsBlock -eq $true) 'one-fresh-process-per-block'
Assert-Condition ($config.processSemantics.crossBlockReuseAllowed -eq $false) 'cross-block-reuse'
Assert-Condition ($config.processSemantics.parallelFallbackAllowed -eq $false) 'parallel-fallback'
Assert-Condition ($config.processSemantics.mixedTopologyAllowed -eq $false) 'mixed-topology'
Assert-Condition ([double]$config.runtimeProjection.serialP50Hours -eq 64.830802096) 'serial-p50-hours'
Assert-Condition ([double]$config.runtimeProjection.serialP95Hours -eq 83.904223147) 'serial-p95-hours'
Assert-Condition ([int]$config.runtimeProjection.recommendedMaintenanceWindowHours -eq 96) 'maintenance-window-hours'
Assert-Condition ($null -eq $config.runtimeProjection.hardWallClockLimitHours) 'hard-wall-clock-limit-must-be-null'
Assert-Condition ([long]$config.storage.projectedRawBytesWithSafety -eq 43885575792) 'projected-storage-bytes'
Assert-Condition ([long]$config.storage.minimumLaunchFreeBytes -eq 86835248752) 'minimum-launch-free-bytes'
Assert-Condition ($config.storage.freshLaunchRecheckRequired -eq $true) 'fresh-storage-check-required'
Assert-Condition ([string]$config.formalRoot.relativePath -eq 'Research/FormalRuns/Gate13R_Serial_10pct/v2') 'formal-root-path'
Assert-Condition ([string]$config.schedule.sha256 -eq 'd9300cce732e12a7b90ec43ad9d5f8fe52cbad58da713c25879754eb31ea0ead') 'config-schedule-hash'
Assert-Condition ([string]$config.schedule.manifestSha256 -eq '8bf87ae8c206355930dd6b720756216ef74052ce9d0551680e3a91933a970dc9') 'config-schedule-manifest-hash'

Assert-Condition ([string]$provenance.formalConfig.sha256 -eq 'faaec5613a2625aee462038305310e229c7cf8fdf67edb800a0b3eb256f1a300') 'provenance-config-hash'
Assert-Condition ([string]$provenance.schedule.sha256 -eq 'd9300cce732e12a7b90ec43ad9d5f8fe52cbad58da713c25879754eb31ea0ead') 'provenance-schedule-hash'
Assert-Condition ([string]$provenance.schedule.manifestSha256 -eq '8bf87ae8c206355930dd6b720756216ef74052ce9d0551680e3a91933a970dc9') 'provenance-schedule-manifest-hash'
Assert-Condition ($provenance.formalRootCreated -eq $false) 'provenance-formal-root-created'
Assert-Condition ($provenance.formalExecutionReceiptCreated -eq $false) 'provenance-formal-receipt-created'
Assert-Condition ($provenance.formalCampaignExecuted -eq $false) 'provenance-formal-campaign-executed'

foreach ($implementationProperty in $config.implementation.PSObject.Properties) {
    if ($implementationProperty.Name.EndsWith('RelativePath')) {
        $stem = $implementationProperty.Name.Substring(0, $implementationProperty.Name.Length - 'RelativePath'.Length)
        $shaProperty = $config.implementation.PSObject.Properties[$stem + 'Sha256']
        if ($null -ne $shaProperty) {
            $implementationPath = Get-ProjectPath ([string]$implementationProperty.Value)
            Assert-Condition (Test-Path -LiteralPath $implementationPath -PathType Leaf) ('implementation-missing-' + $stem)
            if (Test-Path -LiteralPath $implementationPath -PathType Leaf) {
                Assert-Condition ((Get-LowerSha256 $implementationPath) -eq [string]$shaProperty.Value) ('implementation-hash-mismatch-' + $stem)
            }
        }
    }
}

Assert-Condition ([int]$scheduleManifest.blockRecordCount -eq 11160) 'schedule-manifest-block-count'
Assert-Condition ([int]$scheduleManifest.sampleIdentityCount -eq 31536) 'schedule-manifest-sample-count'
Assert-Condition ([int]$scheduleManifest.campaignCount -eq 74) 'schedule-manifest-campaign-count'
Assert-Condition ($scheduleManifest.formalExecutionAuthorized -eq $false) 'schedule-manifest-formal-authorized'
Assert-Condition ($scheduleManifest.formalCampaignExecuted -eq $false) 'schedule-manifest-formal-executed'

Assert-Condition ($readiness.passed -eq $true) 'readiness-not-passed'
Assert-Condition ([int]$readiness.assertionCount -eq 114) 'readiness-assertion-count'
Assert-Condition ([int]$readiness.failureCount -eq 0) 'readiness-failure-count'
Assert-Condition ([int]$readiness.newUnityProcessCount -eq 0) 'readiness-new-unity-process-count'
Assert-Condition ($readiness.formalRootExists -eq $false) 'readiness-formal-root-exists'
Assert-Condition ($readiness.formalExecutionReceiptCreated -eq $false) 'readiness-formal-receipt-created'
Assert-Condition ($readiness.formalTimingSamplesCreated -eq $false) 'readiness-formal-timing-created'

Assert-Condition ($scheduleValidation.passed -eq $true) 'schedule-validation-not-passed'
Assert-Condition ([int]$scheduleValidation.assertionCount -eq 38) 'schedule-validation-assertion-count'
Assert-Condition ([int]$scheduleValidation.errorCount -eq 0) 'schedule-validation-error-count'
Assert-Condition ([int]$scheduleValidation.blockRecordCount -eq 11160) 'schedule-validation-block-count'
Assert-Condition ([int]$scheduleValidation.sampleIdentityCount -eq 31536) 'schedule-validation-sample-count'
Assert-Condition ([int]$scheduleValidation.uniqueBlockIdCount -eq 11160) 'schedule-validation-unique-blocks'
Assert-Condition ([int]$scheduleValidation.uniqueRunIdCount -eq 31536) 'schedule-validation-unique-runs'

Assert-Condition ($regeneration.passed -eq $true) 'regeneration-not-passed'
Assert-Condition ([string]$regeneration.status -eq 'BYTE-IDENTICAL') 'regeneration-status'
Assert-Condition (@($regeneration.artifacts).Count -eq 4) 'regeneration-artifact-count'
Assert-Condition (@($regeneration.artifacts | Where-Object { $_.byteIdentical -ne $true }).Count -eq 0) 'regeneration-byte-mismatch'
Assert-Condition ($regeneration.formalRootCreated -eq $false) 'regeneration-formal-root-created'
Assert-Condition ($regeneration.unityLaunched -eq $false) 'regeneration-unity-launched'

Assert-Condition ($orchestrator.passed -eq $true) 'orchestrator-validation-not-passed'
Assert-Condition ([string]$orchestrator.status -eq 'VALIDATION-ONLY-PASSED-FORMAL-NOT-AUTHORIZED') 'orchestrator-status'
Assert-Condition ([int]$orchestrator.scheduleBlockCount -eq 11160) 'orchestrator-block-count'
Assert-Condition ([int]$orchestrator.scheduleSampleCount -eq 31536) 'orchestrator-sample-count'
Assert-Condition ($orchestrator.currentStorageSnapshot.passed -eq $true) 'storage-snapshot-not-passed'
Assert-Condition (@($orchestrator.currentStorageSnapshot.errors).Count -eq 0) 'storage-snapshot-errors'
Assert-Condition ($orchestrator.currentStorageSnapshot.authorizing -eq $false) 'storage-snapshot-authorizing'
Assert-Condition ($orchestrator.currentStorageSnapshot.launchContext -eq $false) 'storage-snapshot-launch-context'
Assert-Condition ([long]$orchestrator.currentStorageSnapshot.minimumLaunchFreeBytes -eq 86835248752) 'storage-snapshot-threshold'
Assert-Condition ([long]$orchestrator.currentStorageSnapshot.availableFreeBytes -ge 86835248752) 'storage-snapshot-observed-below-threshold'
Assert-Condition ([int]$orchestrator.unityProcessCount -eq 0) 'orchestrator-unity-process-count'
Assert-Condition ($orchestrator.formalRootExists -eq $false) 'orchestrator-formal-root-exists'
Assert-Condition ($orchestrator.formalExecutionReceiptCreated -eq $false) 'orchestrator-formal-receipt-created'
Assert-Condition ($orchestrator.formalCampaignExecuted -eq $false) 'orchestrator-formal-campaign-executed'

Assert-Condition ($negativeGuard.passed -eq $true) 'negative-receipt-guard-not-passed'
Assert-Condition ($negativeGuard.expectedFailure -eq $true) 'negative-receipt-guard-not-expected-failure'
Assert-Condition ([int]$negativeGuard.exitCode -eq 1) 'negative-receipt-guard-exit-code'
Assert-Condition ([string]$negativeGuard.matchedReason -eq 'A separately authorized formal execution receipt is required.') 'negative-receipt-guard-reason'
Assert-Condition ($negativeGuard.formalRootCreated -eq $false) 'negative-receipt-formal-root-created'
Assert-Condition ([int]$negativeGuard.unityProcessCount -eq 0) 'negative-receipt-unity-process-count'
Assert-Condition ($negativeGuard.formalTimingSamplesCreated -eq $false) 'negative-receipt-formal-timing-created'

$activeReceiptCandidates = @(Get-ChildItem -LiteralPath (Get-ProjectPath 'Research') -File -Filter 'Gate13R_Serial_10pct*Execution*Receipt*.json' -ErrorAction SilentlyContinue)
Assert-Condition ($activeReceiptCandidates.Count -eq 0) 'active-formal-execution-receipt-present'

$summary = [ordered]@{
    schemaVersion = 1
    summaryKind = 'gate13r-serial-10pct-nonexecuting-final-audit-summary-v2'
    savedAtUtc = [DateTime]::UtcNow.ToString('o')
    status = if ($errors.Count -eq 0) { 'GATE13R-SERIAL-10PCT-NONEXECUTING-PREPARATION-PASSED-FORMAL-NOT-AUTHORIZED' } else { 'GATE13R-SERIAL-10PCT-NONEXECUTING-FINAL-AUDIT-FAILED' }
    formalDesignId = [string]$config.formalDesignId
    topology = [ordered]@{
        maximumConcurrentUnityEditorProcesses = 1
        laneCount = 1
        oneFreshUnityEditorProcessPerCompleteWilliamsBlock = $true
        parallelFallbackAllowed = $false
        mixedTopologyAllowed = $false
    }
    scale = [ordered]@{
        campaignCount = 74
        blockProcessCount = 11160
        sampleCount = 31536
        sharedBlocksPerCampaign = 144
        perAgentBlocksPerCampaign = 204
        groupedFieldBlocksPerCampaign = 108
    }
    runtimeProjection = [ordered]@{
        p50Hours = 64.830802096
        p95Hours = 83.904223147
        recommendedMaintenanceWindowHours = 96
        hardWallClockLimitHours = $null
        old36HourLimitFeasible = $false
        estimateOnly = $true
    }
    storage = [ordered]@{
        projectedRawBytesWithSafety = 43885575792
        reserveBytes = 42949672960
        minimumLaunchFreeBytes = 86835248752
        validationOnlyObservedFreeBytes = [long]$orchestrator.currentStorageSnapshot.availableFreeBytes
        validationOnlyObservationAuthorizesLaunch = $false
        freshLaunchCheckRequired = $true
    }
    boundHashes = $hashEvidence.ToArray()
    assertionCount = $assertions
    errorCount = $errors.Count
    errors = $errors.ToArray()
    unityProcessCount = $unityProcesses.Count
    formalRootV1Exists = Test-Path -LiteralPath $formalRootV1
    formalRootV2Exists = Test-Path -LiteralPath $formalRootV2
    activeFormalExecutionReceiptCount = $activeReceiptCandidates.Count
    formalExecutionAuthorized = $false
    formalCampaignExecuted = $false
    formalTimingSamplesCreated = $false
    passed = $errors.Count -eq 0
}

Write-AtomicJson -Path $SummaryPath -Value $summary
if ($errors.Count -gt 0) {
    Write-Error ('Gate13R serial 10pct final audit failed: ' + ($errors -join '; '))
    exit 1
}
Write-Host "Gate13R serial 10pct final audit passed: $assertions assertions; no Unity or formal execution." -ForegroundColor Green
exit 0
