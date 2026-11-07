[CmdletBinding()]
param([string]$ProjectPath)

$ErrorActionPreference = 'Stop'
$scriptDirectory = Split-Path -Parent $MyInvocation.MyCommand.Path
if ([string]::IsNullOrWhiteSpace($ProjectPath)) { $ProjectPath = [System.IO.Path]::GetFullPath((Join-Path $scriptDirectory '..\..')) }
else { $ProjectPath = [System.IO.Path]::GetFullPath($ProjectPath) }
$modulePath = Join-Path $ProjectPath 'Research\Gate13ProcessReusePreparation.psm1'
Import-Module $modulePath -Force
$summaryPath = Join-Path $scriptDirectory 'Gate13R2_PrePilotAudit.summary.json'
$regressionSummaryPath = Join-Path $scriptDirectory 'Gate13R2_RetainedRegression63.summary.json'
$negativePlanPath = Join-Path $scriptDirectory 'Gate13R2_NegativeBlockFixture.v1.block-plan.json'
$negativeRoot = Join-Path $scriptDirectory 'Gate13R2_NegativeBlockFixture.v1'
$negativeLogPath = Join-Path $scriptDirectory 'Gate13R2_NegativeBlockFixture.v1.Unity.log'
$positiveRoot = Join-Path $scriptDirectory 'Gate13R2_PositiveBlockFixtures\v1'
$positiveFourPlanPath = Join-Path $scriptDirectory 'Gate13R2_PositiveBlockFixture_4Alg.v1.block-plan.json'
$positiveTwoPlanPath = Join-Path $scriptDirectory 'Gate13R2_PositiveBlockFixture_2Alg.v1.block-plan.json'
if (Test-Path -LiteralPath $summaryPath) { throw "Create-new pre-pilot audit summary already exists: $summaryPath" }

$assertionCount = 0
$failures = New-Object System.Collections.Generic.List[string]
function Assert-True([bool]$Condition, [string]$Message) {
    $script:assertionCount++
    if (-not $Condition) { $script:failures.Add($Message) }
}
function Assert-Throws([scriptblock]$Action, [string]$Message) {
    $script:assertionCount++
    $threw = $false
    try { & $Action | Out-Null } catch { $threw = $true }
    if (-not $threw) { $script:failures.Add($Message) }
}
function Get-AggregateIdentity([string]$Root) {
    $files = @(Get-ChildItem -LiteralPath $Root -Recurse -File -Force | Sort-Object { $_.FullName.Substring($Root.Length + 1).Replace('\', '/') })
    $builder = New-Object System.Text.StringBuilder
    foreach ($file in $files) {
        $relative = $file.FullName.Substring($Root.Length + 1).Replace('\', '/')
        [void]$builder.Append($relative).Append("`n").Append($file.Length).Append("`n").Append((Get-G13R2LowerSha256 -Path $file.FullName)).Append("`n")
    }
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try { $aggregate = ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($builder.ToString())))).Replace('-', '').ToLowerInvariant() }
    finally { $sha.Dispose() }
    return [pscustomobject][ordered]@{
        fileCount = $files.Count
        byteCount = if ($files.Count -eq 0) { [int64]0 } else { [int64](($files | Measure-Object Length -Sum).Sum) }
        aggregateSha256 = $aggregate
    }
}

$pilotRoot = Join-Path $ProjectPath 'Research\PilotRuns\Gate13_ProcessReuse\v1'
$formalRoot = Join-Path $ProjectPath 'Research\FormalRuns\Gate13_ProcessReuse\v1'
$coldRoot = [System.IO.Path]::GetFullPath((Join-Path $ProjectPath 'Research\FormalRuns\Gate13\v1'))
$planPath = Join-Path $ProjectPath 'Research\Gate13_ProcessReuse_Pilot_Plan.v1.json'
$provenancePath = Join-Path $ProjectPath 'Research\Gate13_ProcessReuse_Provenance.v4.json'
$receiptPath = Join-Path $ProjectPath 'Research\Gate13_ColdProcess_Termination_Receipt.v1.json'
$snapshotPath = Join-Path $ProjectPath 'Research\Gate13_ColdProcess_PreTermination_Snapshot.v1.json'
$partialManifestPath = Join-Path $ProjectPath 'Research\Gate13_ColdProcess_Partial_Output_Manifest.v1.json'
$exclusionPath = Join-Path $ProjectPath 'Research\Gate13_ColdProcess_Exclusion_Marker.v1.json'
$plan = Read-G13R2Json -Path $planPath
$provenance = Read-G13R2Json -Path $provenancePath
$receipt = Read-G13R2Json -Path $receiptPath
$snapshot = Read-G13R2Json -Path $snapshotPath

Assert-True (-not (Test-Path -LiteralPath $pilotRoot)) 'Process-reuse pilot root exists before pre-pilot authorization.'
Assert-True (-not (Test-Path -LiteralPath $formalRoot)) 'Reserved process-reuse formal root exists.'
$planCheck = Test-G13R2PilotPlan -ProjectPath $ProjectPath -Plan $plan -PlanPath $planPath
Assert-True ($planCheck.passed -eq $true) ("Pilot plan validation failed: " + ($planCheck.errors -join '; '))
Assert-True ($provenance.provenanceId -eq 'gate13-r2-process-reuse-provenance-v4') 'Process-reuse provenance identity mismatch.'
foreach ($property in $provenance.PSObject.Properties | Where-Object { $_.Value -is [pscustomobject] -and $_.Value.PSObject.Properties.Name -contains 'relativePath' -and $_.Value.PSObject.Properties.Name -contains 'sha256' }) {
    $path = Join-Path $ProjectPath ([string]$property.Value.relativePath).Replace('/', '\')
    Assert-True ((Test-Path -LiteralPath $path -PathType Leaf) -and (Get-G13R2LowerSha256 -Path $path) -eq [string]$property.Value.sha256) ("Provenance-bound file mismatch: " + $property.Name)
}
foreach ($property in $provenance.supersedes.PSObject.Properties | Where-Object { $_.Value -is [pscustomobject] -and $_.Value.PSObject.Properties.Name -contains 'relativePath' -and $_.Value.PSObject.Properties.Name -contains 'sha256' }) {
    $path = Join-Path $ProjectPath ([string]$property.Value.relativePath).Replace('/', '\')
    Assert-True ((Test-Path -LiteralPath $path -PathType Leaf) -and (Get-G13R2LowerSha256 -Path $path) -eq [string]$property.Value.sha256) ("Superseded provenance/audit evidence mismatch: " + $property.Name)
}

$expectedDispositions = @('USER-TERMINATED-DESIGN-CHANGE', 'EXCLUDED_FROM_ANALYSIS', 'NO-AUTO-RETRY', 'NO-RESUME', 'SUPERSEDED-BY-PROCESS-REUSE-DESIGN')
Assert-True (($expectedDispositions -join '|') -eq (@($receipt.dispositions) -join '|')) 'Cold termination dispositions changed.'
Assert-True ((Get-G13R2LowerSha256 -Path $receiptPath) -eq '4661a3edc6e569b068e065456ab34f839d60030b1d668a925ca5b9dad9e481a4') 'Cold termination receipt hash changed.'
Assert-True ((Get-G13R2LowerSha256 -Path $snapshotPath) -eq [string]$receipt.preTerminationSnapshotSha256) 'Pre-termination snapshot hash mismatch.'
Assert-True ((Get-G13R2LowerSha256 -Path $partialManifestPath) -eq [string]$receipt.partialOutputManifestSha256) 'Cold partial-output manifest hash mismatch.'
Assert-True ((Get-G13R2LowerSha256 -Path $exclusionPath) -eq [string]$receipt.exclusionMarkerSha256) 'Cold exclusion marker hash mismatch.'
Assert-True ([System.IO.Path]::GetFullPath([string]$receipt.formalRoot) -eq $coldRoot) 'Cold formal root resolved path changed.'
$coldFiles = @(Get-ChildItem -LiteralPath $coldRoot -Recurse -File -Force)
$coldBytes = [int64](($coldFiles | Measure-Object Length -Sum).Sum)
$coldReadOnlyCount = @($coldFiles | Where-Object { ($_.Attributes -band [IO.FileAttributes]::ReadOnly) -ne 0 }).Count
Assert-True ($coldFiles.Count -eq [int]$receipt.postTerminationFileCount -and $coldBytes -eq [int64]$receipt.postTerminationRawByteCount) 'Cold root file count/raw bytes changed after freeze.'
Assert-True ($coldReadOnlyCount -eq $coldFiles.Count -and ((Get-Item -LiteralPath $coldRoot).Attributes -band [IO.FileAttributes]::ReadOnly) -ne 0) 'Cold root is not fully read-only.'
$coldCheckpointPath = Join-Path $coldRoot 'formal-checkpoint.json'
Assert-True ((Get-G13R2LowerSha256 -Path $coldCheckpointPath) -eq [string]$receipt.checkpointAfterSha256 -and (Read-G13R2Json -Path $coldCheckpointPath).status -eq 'failed-no-auto-retry') 'Cold final checkpoint changed or is resumable.'
foreach ($record in @($snapshot.protectedEvidenceHashes | Where-Object { $_.relativePath -ne 'Research/FormalRuns/Gate13/v1/formal-checkpoint.json' })) {
    $path = Join-Path $ProjectPath ([string]$record.relativePath).Replace('/', '\')
    Assert-True ((Test-Path -LiteralPath $path -PathType Leaf) -and (Get-G13R2LowerSha256 -Path $path) -eq [string]$record.sha256 -and [int64](Get-Item -LiteralPath $path).Length -eq [int64]$record.lengthBytes) ("Protected cold evidence changed: " + $record.relativePath)
}

$gate11ManifestPath = Join-Path $ProjectPath 'Research\FormalScenarios\v1\bundle-manifest.json'
$gate11Manifest = Read-G13R2Json -Path $gate11ManifestPath
Assert-True ((Get-G13R2LowerSha256 -Path $gate11ManifestPath) -eq 'ea596c8c9e6d1ca99e325c05c095024a4813ca1e65c771a8b4db8bf29364c12e') 'Gate 11 retained bundle manifest hash changed.'
Assert-True (@(Get-ChildItem -LiteralPath (Split-Path -Parent $gate11ManifestPath) -Recurse -File).Count -eq 57 -and @($gate11Manifest.artifacts).Count -eq 56) 'Gate 11 retained bundle cardinality changed.'
$gate12Root = Join-Path $ProjectPath 'Research\PilotRuns\Gate12\v1'
Assert-True (@(Get-ChildItem -LiteralPath $gate12Root -Recurse -File -Force).Count -eq 1694) 'Gate 12 successful v1 file count changed.'
Assert-True ((Get-G13R2LowerSha256 -Path (Join-Path $gate12Root 'pilot-manifest.json')) -eq '638ac2e3fe243212ef031bdbed4c06394447e055c4d080be370357c41122e18a') 'Gate 12 successful pilot manifest hash changed.'
$attempt1 = Get-AggregateIdentity -Root (Join-Path $ProjectPath 'Research\PilotRuns\Gate12\v1-failed-pre-sample-attempt1')
$attempt2 = Get-AggregateIdentity -Root (Join-Path $ProjectPath 'Research\PilotRuns\Gate12\v1-failed-warmup-attempt2')
Assert-True ($attempt1.fileCount -eq 1 -and $attempt1.byteCount -eq 20841) 'Gate 12 failure attempt 1 archive changed.'
Assert-True ($attempt2.fileCount -eq 103 -and $attempt2.byteCount -eq 14187382 -and $attempt2.aggregateSha256 -eq 'b52ee8f13c9b96edd2f0ab83f4969161ef5b257d1543588ec9608877086dc500') 'Gate 12 failure attempt 2 archive changed.'

$baselineRows = @(Import-Csv -LiteralPath (Join-Path $ProjectPath 'Research\Baseline_SHA256.csv') | Where-Object { $_.scope -in @('working_copy', 'external_archive') })
$baselineMismatches = New-Object System.Collections.Generic.List[string]
foreach ($row in $baselineRows) {
    $path = if ($row.scope -eq 'external_archive') { [System.IO.Path]::GetFullPath((Join-Path $ProjectPath $row.relative_path)) } else { Join-Path $ProjectPath $row.relative_path.Replace('/', '\') }
    if (-not (Test-Path -LiteralPath $path -PathType Leaf) -or (Get-G13R2LowerSha256 -Path $path) -ne $row.sha256 -or [int64](Get-Item -LiteralPath $path).Length -ne [int64]$row.bytes) { $baselineMismatches.Add([string]$row.relative_path) }
}
Assert-True ($baselineRows.Count -eq 24 -and $baselineMismatches.Count -eq 0) 'Original scripts/scenes baseline is not 24/24.'

$newPowerShellFiles = @(
    'Research/Gate13ProcessReusePreparation.psm1',
    'Research/Run-PlanningProcessReuseBlock.ps1',
    'Research/Run-Gate13ProcessReusePilot.ps1',
    'Research/Run-Gate13ProcessReuseColdReference.ps1',
    'Research/Analyze-Gate13ProcessReusePilot.ps1',
    'Research/New-Gate13ProcessReuseFormalPreparation.ps1',
    'Research/New-Gate13ProcessReuseProvenanceV4.ps1',
    'Research/Verification/Run-Gate13ProcessReusePrePilotAudit.ps1'
)
$parseErrors = New-Object System.Collections.Generic.List[object]
foreach ($relativePath in $newPowerShellFiles) {
    $tokens = $null; $errors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile((Join-Path $ProjectPath $relativePath.Replace('/', '\')), [ref]$tokens, [ref]$errors)
    foreach ($error in @($errors)) { $parseErrors.Add([pscustomobject]@{ relativePath = $relativePath; message = $error.Message }) }
}
Assert-True ($parseErrors.Count -eq 0) 'New process-reuse PowerShell has parser errors.'
$commandPath = Join-Path $ProjectPath 'Assets\_Scripts\Research\Editor\ResearchPlanningProcessReuseBatchCommand.cs'
$commandText = [System.IO.File]::ReadAllText($commandPath)
$mutableStaticFields = @(Select-String -LiteralPath $commandPath -Pattern '^\s*private\s+static\s+(?!readonly\b)[^\(]*;\s*$')
Assert-True ($mutableStaticFields.Count -eq 0) 'Process-reuse Unity command contains mutable static fields.'
foreach ($requiredText in @('ForceCollectionBoundary();', 'new JsonlExperimentLogger', 'WriteAtomicJson(manifestPath, manifest);', 'WriteAtomicJson(summaryPath, summary);', 'WriteAtomicJson(Path.Combine(outputRoot, "block-manifest.json"), blockManifest);', 'automaticRetryAttempted = false', 'automaticResumeAttempted = false')) {
    Assert-True ($commandText.Contains($requiredText)) ("Process-reuse Unity command lacks required reset/atomic/fail-closed construct: " + $requiredText)
}
$compileLogPath = Join-Path $scriptDirectory 'Gate13R2_ProcessReuse_Compile.v3.log'
$compileErrors = @(Select-String -LiteralPath $compileLogPath -Pattern 'error CS\d+|Compilation failed|Scripts have compiler errors' -CaseSensitive:$false)
Assert-True ((Test-Path -LiteralPath $compileLogPath -PathType Leaf) -and $compileErrors.Count -eq 0 -and [System.IO.File]::ReadAllText($compileLogPath).Contains('Exiting batchmode successfully now!')) 'Gate 13-R2 Unity compile v3 is not clean.'

foreach ($vector in @(
    [ordered]@{ sigma = 0.0; raw = 0; required = 32; candidate = 32; overCap = $false },
    [ordered]@{ sigma = 0.5; raw = 106; required = 108; candidate = 108; overCap = $false },
    [ordered]@{ sigma = 0.8; raw = 271; required = 272; candidate = 148; overCap = $true }
)) {
    $actual = Get-G13R2SampleSizeCandidate -SigmaLog ([double]$vector.sigma)
    Assert-True ([long]$actual.nRaw -eq [long]$vector.raw -and [long]$actual.requiredNFormal -eq [long]$vector.required -and [long]$actual.candidateNFormal -eq [long]$vector.candidate -and [bool]$actual.overCap -eq [bool]$vector.overCap) ("Sample-size vector mismatch for sigma=" + $vector.sigma)
}
Assert-Throws { Get-G13R2SampleSizeCandidate -SigmaLog ([double]::NaN) } 'NaN sigma was accepted.'
Assert-Throws { Get-G13R2SampleSizeCandidate -SigmaLog -0.01 } 'Negative sigma was accepted.'

$referenceResultPath = Join-Path $ProjectPath 'Research\Verification\Gate10_FairCampaignFixture_Final\runs\b001\p01-astar-r\workload-result.json'
$reference = Read-G13R2Json -Path $referenceResultPath
$timingMutation = $reference | ConvertTo-Json -Depth 50 | ConvertFrom-Json
$timingMutation.totalPlannerElapsedMilliseconds = [double]$timingMutation.totalPlannerElapsedMilliseconds + 123.0
$structuralMutation = $reference | ConvertTo-Json -Depth 50 | ConvertFrom-Json
$structuralMutation.processedNodesOrCells = [long]$structuralMutation.processedNodesOrCells + 1
Assert-True ((Compare-G13R2StructuralResults -Reference $reference -Candidate $reference).passed) 'Structural comparator rejected an identical result.'
Assert-True ((Compare-G13R2StructuralResults -Reference $reference -Candidate $timingMutation).passed) 'Structural comparator incorrectly includes timing.'
Assert-True (-not (Compare-G13R2StructuralResults -Reference $reference -Candidate $structuralMutation).passed) 'Structural comparator accepted a structural mutation.'

$positionCounts = @{}
$predecessorCounts = @{}
foreach ($campaign in @($plan.measuredCampaigns)) {
    for ($block = 1; $block -le 12; $block++) {
        $blockPlan = New-G13R2BlockPlan -ProjectPath $ProjectPath -PilotPlan $plan -Provenance $provenance -CampaignId ([string]$campaign.campaignId) -ScenarioRelativePath ([string]$campaign.scenarioRelativePath) -ScenarioSourceSha256 ([string]$campaign.scenarioSourceSha256) -ComparisonCohortId ([string]$campaign.comparisonCohortId) -Block $block -ProvenancePath $provenancePath
        Assert-True (@($blockPlan.entries).Count -eq @($campaign.algorithms).Count -and @($blockPlan.entries.algorithmId | Sort-Object -Unique).Count -eq @($campaign.algorithms).Count) ("Block plan cardinality/uniqueness failed: " + $blockPlan.blockId)
        foreach ($entry in @($blockPlan.entries)) {
            $positionKey = '{0}|{1}|{2}' -f $campaign.campaignId, $entry.algorithmId, $entry.position
            $positionCounts[$positionKey] = 1 + [int]$(if ($positionCounts.ContainsKey($positionKey)) { $positionCounts[$positionKey] } else { 0 })
            if ($entry.predecessorAlgorithmId -ne 'NONE') {
                $predecessorKey = '{0}|{1}>{2}' -f $campaign.campaignId, $entry.predecessorAlgorithmId, $entry.algorithmId
                $predecessorCounts[$predecessorKey] = 1 + [int]$(if ($predecessorCounts.ContainsKey($predecessorKey)) { $predecessorCounts[$predecessorKey] } else { 0 })
            }
        }
    }
}
Assert-True (@($positionCounts.Values | Where-Object { $_ -notin @(3, 6) }).Count -eq 0) 'Algorithm-by-position Williams balance failed.'
Assert-True (@($predecessorCounts.Values | Where-Object { $_ -notin @(3, 6) }).Count -eq 0) 'Ordered predecessor Williams balance failed.'
Assert-Throws { New-G13R2BlockPlan -ProjectPath $ProjectPath -PilotPlan $plan -Provenance $provenance -CampaignId '..\escape' -ScenarioRelativePath ([string]$plan.measuredCampaigns[0].scenarioRelativePath) -ScenarioSourceSha256 ([string]$plan.measuredCampaigns[0].scenarioSourceSha256) -ComparisonCohortId 'four-algorithm-shared-goal-v1' -Block 1 -ProvenancePath $provenancePath } 'Unsafe campaign ID was accepted.'
Assert-Throws { New-G13R2BlockPlan -ProjectPath $ProjectPath -PilotPlan $plan -Provenance $provenance -CampaignId 'valid-id' -ScenarioRelativePath ([string]$plan.measuredCampaigns[0].scenarioRelativePath) -ScenarioSourceSha256 ('0' * 64) -ComparisonCohortId 'four-algorithm-shared-goal-v1' -Block 1 -ProvenancePath $provenancePath } 'Scenario hash mutation was accepted.'

$originalRegressionSummaryPath = Join-Path $scriptDirectory 'Gate12_AnalysisUnitTests.summary.json'
$originalRegressionSummaryHashBefore = Get-G13R2LowerSha256 -Path $originalRegressionSummaryPath
$regressionScriptPath = Join-Path $scriptDirectory 'Run-Gate12AnalysisUnitTests.ps1'
if (-not (Test-Path -LiteralPath $regressionSummaryPath -PathType Leaf)) {
    $regressionSource = [System.IO.File]::ReadAllText($regressionScriptPath)
    $escapedDirectory = $scriptDirectory.Replace("'", "''")
    $regressionSource = $regressionSource.Replace('$scriptDirectory = Split-Path -Parent $MyInvocation.MyCommand.Path', ("`$scriptDirectory = '" + $escapedDirectory + "'"))
    $regressionSource = $regressionSource.Replace("`$summaryPath = Join-Path `$scriptDirectory 'Gate12_AnalysisUnitTests.summary.json'", "`$summaryPath = Join-Path `$scriptDirectory 'Gate13R2_RetainedRegression63.summary.json'")
    $regressionSource | & powershell.exe -NoProfile -ExecutionPolicy Bypass -Command '& ([ScriptBlock]::Create([Console]::In.ReadToEnd()))' | Out-Host
    $regressionExitCode = [int]$LASTEXITCODE
    if ($regressionExitCode -ne 0) { $failures.Add("Retained 63-assertion regression child failed with exit $regressionExitCode; no retry was attempted.") }
}
$regressionSummary = if (Test-Path -LiteralPath $regressionSummaryPath -PathType Leaf) { Read-G13R2Json -Path $regressionSummaryPath } else { $null }
Assert-True ($null -ne $regressionSummary -and $regressionSummary.passed -eq $true -and [int]$regressionSummary.assertionCount -eq 63) 'Retained Gate 1-11/Gate 12 regression is not 63/63.'
Assert-True ((Get-G13R2LowerSha256 -Path $originalRegressionSummaryPath) -eq $originalRegressionSummaryHashBefore) 'Original Gate 12 regression evidence was modified.'

$positiveFixtures = New-Object System.Collections.Generic.List[object]
if ($failures.Count -eq 0) {
    $positiveTargets = @($positiveRoot, $positiveFourPlanPath, $positiveTwoPlanPath)
    if (@($positiveTargets | Where-Object { Test-Path -LiteralPath $_ }).Count -gt 0) {
        $failures.Add('Positive block-fixture target already exists; no retry/resume was attempted.')
    }
    else {
        $fixtureDefinitions = @(
            [ordered]@{ label = 'four-algorithm'; campaign = $plan.measuredCampaigns[0]; planPath = $positiveFourPlanPath; outputPath = Join-Path $positiveRoot 'four-algorithm-b001'; expectedSamples = 4 },
            [ordered]@{ label = 'two-algorithm'; campaign = $plan.measuredCampaigns[1]; planPath = $positiveTwoPlanPath; outputPath = Join-Path $positiveRoot 'two-algorithm-b001'; expectedSamples = 2 }
        )
        $blockRunnerPath = Join-Path $ProjectPath 'Research\Run-PlanningProcessReuseBlock.ps1'
        $nativeModulePath = @('C:\Users\bdscy\Documents\WindowsPowerShell\Modules', 'C:\Program Files\WindowsPowerShell\Modules', 'C:\WINDOWS\System32\WindowsPowerShell\v1.0\Modules') -join ';'
        foreach ($fixture in $fixtureDefinitions) {
            if ($failures.Count -gt 0) { break }
            $campaign = $fixture.campaign
            $blockPlan = New-G13R2BlockPlan -ProjectPath $ProjectPath -PilotPlan $plan -Provenance $provenance -CampaignId ("g13r2-positive-$($fixture.label)-v1") -ScenarioRelativePath ([string]$campaign.scenarioRelativePath) -ScenarioSourceSha256 ([string]$campaign.scenarioSourceSha256) -ComparisonCohortId ([string]$campaign.comparisonCohortId) -Block 1 -ProvenancePath $provenancePath
            $blockPlan.analysisRole = 'excluded-positive-process-reuse-verification'
            Write-G13R2Utf8NoBomJson -Path $fixture.planPath -Value $blockPlan -Depth 30
            $previousModulePath = $env:PSModulePath
            try {
                $env:PSModulePath = $nativeModulePath
                & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $blockRunnerPath -BlockPlanPath $fixture.planPath -OutputDirectory $fixture.outputPath -UnityPath ([string]$plan.unity.executablePath).Replace('/', '\') -ProjectPath $ProjectPath -VerificationOnly | Out-Host
                $fixtureExitCode = [int]$LASTEXITCODE
            }
            finally { $env:PSModulePath = $previousModulePath }
            if ($fixtureExitCode -ne 0) { $failures.Add("Positive process-reuse fixture failed without retry: $($fixture.label), exit=$fixtureExitCode"); break }
            $wrapperSummaryPath = $fixture.outputPath + '.summary.json'
            $blockManifestPath = Join-Path $fixture.outputPath 'block-manifest.json'
            $wrapperSummary = Read-G13R2Json -Path $wrapperSummaryPath
            $blockManifest = Read-G13R2Json -Path $blockManifestPath
            if ($wrapperSummary.passed -ne $true -or $blockManifest.completed -ne $true -or [int]$blockManifest.completedSampleCount -ne [int]$fixture.expectedSamples -or @($blockManifest.samples | Where-Object processId -ne ([int]$blockManifest.processId)).Count -gt 0) { $failures.Add("Positive process-reuse fixture identity/completion mismatch: $($fixture.label)"); break }
            $positiveFixtures.Add([pscustomobject][ordered]@{
                label = [string]$fixture.label
                planSha256 = Get-G13R2LowerSha256 -Path $fixture.planPath
                wrapperSummarySha256 = Get-G13R2LowerSha256 -Path $wrapperSummaryPath
                blockManifestSha256 = Get-G13R2LowerSha256 -Path $blockManifestPath
                processId = [int]$blockManifest.processId
                sampleCount = [int]$blockManifest.completedSampleCount
                allSamplesShareProcessId = [bool]$blockManifest.allSamplesShareProcessId
                orderMatchesBlockPlan = [bool]$blockManifest.orderMatchesBlockPlan
                formalCampaign = [bool]$blockManifest.formalCampaign
                passed = $true
            })
            if (@(Get-Process -Name Unity -ErrorAction SilentlyContinue).Count -gt 0 -or (Test-Path -LiteralPath (Join-Path $ProjectPath 'Temp\UnityLockfile'))) { $failures.Add("Unity process/lock remained after positive fixture: $($fixture.label)"); break }
        }
        if ($positiveFixtures.Count -eq 2) { Assert-True ([int]$positiveFixtures[0].processId -ne [int]$positiveFixtures[1].processId) 'Two positive fixture blocks used the same process ID.' }
    }
}

$preUnityFailures = $failures.Count
$negativeFixture = $null
if ($preUnityFailures -eq 0) {
    $negativeArtifactsExist = @(
        (Test-Path -LiteralPath $negativeRoot)
        (Test-Path -LiteralPath $negativePlanPath)
        (Test-Path -LiteralPath $negativeLogPath)
    )
    $negativeEvidenceReused = @($negativeArtifactsExist | Where-Object { $_ }).Count -eq 3
    if (@($negativeArtifactsExist | Where-Object { $_ }).Count -notin @(0, 3)) {
        $failures.Add('Negative-fixture evidence is partial; no rerun/resume was attempted.')
    }
    elseif (-not $negativeEvidenceReused) {
        $campaign = $plan.measuredCampaigns[0]
        $negativePlan = New-G13R2BlockPlan -ProjectPath $ProjectPath -PilotPlan $plan -Provenance $provenance -CampaignId 'g13r2-negative-partial-block-v1' -ScenarioRelativePath ([string]$campaign.scenarioRelativePath) -ScenarioSourceSha256 ([string]$campaign.scenarioSourceSha256) -ComparisonCohortId ([string]$campaign.comparisonCohortId) -Block 1 -ProvenancePath $provenancePath
        $negativePlan.analysisRole = 'excluded-negative-fail-closed-verification'
        $negativePlan.entries[1].directory = [string]$negativePlan.entries[0].directory
        Write-G13R2Utf8NoBomJson -Path $negativePlanPath -Value $negativePlan -Depth 30
        $unityPath = [System.IO.Path]::GetFullPath(([string]$plan.unity.executablePath).Replace('/', '\'))
        $arguments = @(
            '-batchmode', '-nographics', '-quit', '-projectPath', ('"' + $ProjectPath + '"'),
            '-executeMethod', 'DDM.Research.Editor.ResearchPlanningProcessReuseBatchCommand.Run',
            '-ddmProcessReuseBlockPlanPath', ('"' + $negativePlanPath + '"'),
            '-ddmProcessReuseBlockPlanSha256', (Get-G13R2LowerSha256 -Path $negativePlanPath),
            '-ddmProcessReuseOutputDirectory', ('"' + $negativeRoot + '"'),
            '-logFile', ('"' + $negativeLogPath + '"')
        )
        $process = Start-Process -FilePath $unityPath -ArgumentList $arguments -WorkingDirectory (Split-Path -Parent $unityPath) -WindowStyle Hidden -PassThru
        Wait-Process -Id $process.Id
        $process.Refresh()
        $negativeUnityExitCode = [int]$process.ExitCode
    }
    if (@($negativeArtifactsExist | Where-Object { $_ }).Count -in @(0, 3)) {
        if ($negativeEvidenceReused) {
            $attempt3 = Read-G13R2Json -Path (Join-Path $scriptDirectory 'Gate13R2_PrePilotAudit_Attempt3_Failure.v1.json')
            $negativeUnityExitCode = if ([System.IO.File]::ReadAllText($negativeLogPath).Contains('return code 1')) { 1 } else { 0 }
            Assert-True ((Get-G13R2LowerSha256 -Path $negativePlanPath) -eq [string]$attempt3.negativeFixture.planSha256 -and (Get-G13R2LowerSha256 -Path $negativeLogPath) -eq [string]$attempt3.negativeFixture.unityLogSha256) 'Reused negative-fixture plan/log hash mismatch.'
        }
        $failurePath = Join-Path $negativeRoot 'block-failure.json'
        $checkpointPath = Join-Path $negativeRoot 'block-checkpoint.json'
        $failure = if (Test-Path -LiteralPath $failurePath -PathType Leaf) { Read-G13R2Json -Path $failurePath } else { $null }
        $checkpoint = if (Test-Path -LiteralPath $checkpointPath -PathType Leaf) { Read-G13R2Json -Path $checkpointPath } else { $null }
        $sampleSummaries = @(Get-ChildItem -LiteralPath $negativeRoot -Recurse -Filter 'sample-summary.json' -File -ErrorAction SilentlyContinue)
        $negativeFixture = [ordered]@{
            expectedFailureObserved = $negativeUnityExitCode -ne 0
            unityExitCode = $negativeUnityExitCode
            reusedExistingEvidenceWithoutRerun = $negativeEvidenceReused
            planSha256 = Get-G13R2LowerSha256 -Path $negativePlanPath
            unityLogSha256 = Get-G13R2LowerSha256 -Path $negativeLogPath
            failureSha256 = if ($null -eq $failure) { $null } else { Get-G13R2LowerSha256 -Path $failurePath }
            checkpointSha256 = if ($null -eq $checkpoint) { $null } else { Get-G13R2LowerSha256 -Path $checkpointPath }
            completedSampleCount = if ($null -eq $failure) { -1 } else { [int]$failure.completedSampleCount }
            failedPosition = if ($null -eq $failure) { -1 } else { [int]$failure.failedPosition }
            laterPositionsExecuted = if ($null -eq $failure) { $null } else { [bool]$failure.laterPositionsExecuted }
            finalCheckpointStatus = if ($null -eq $checkpoint) { $null } else { [string]$checkpoint.status }
            sampleCompletionMarkerCount = $sampleSummaries.Count
            blockManifestExists = Test-Path -LiteralPath (Join-Path $negativeRoot 'block-manifest.json')
            automaticRetryAttempted = if ($null -eq $failure) { $null } else { [bool]$failure.automaticRetryAttempted }
            automaticResumeAttempted = if ($null -eq $failure) { $null } else { [bool]$failure.automaticResumeAttempted }
        }
        Assert-True ($negativeFixture.expectedFailureObserved -and $negativeFixture.completedSampleCount -eq 1 -and $negativeFixture.failedPosition -eq 2 -and $negativeFixture.laterPositionsExecuted -eq $false -and $negativeFixture.finalCheckpointStatus -eq 'failed-no-auto-retry' -and $negativeFixture.sampleCompletionMarkerCount -eq 1 -and $negativeFixture.blockManifestExists -eq $false -and $negativeFixture.automaticRetryAttempted -eq $false -and $negativeFixture.automaticResumeAttempted -eq $false) 'Injected partial block did not fail closed atomically at position 2.'
    }
}

$unityProcesses = @(Get-Process -Name Unity -ErrorAction SilentlyContinue)
$unityLockfile = Test-Path -LiteralPath (Join-Path $ProjectPath 'Temp\UnityLockfile')
Assert-True ($unityProcesses.Count -eq 0) 'Unity remains running after the pre-pilot audit.'
Assert-True (-not $unityLockfile) 'Unity lockfile remains after the pre-pilot audit.'
Assert-True (-not (Test-Path -LiteralPath $pilotRoot)) 'Pre-pilot audit created the process-reuse pilot root.'
Assert-True (-not (Test-Path -LiteralPath $formalRoot)) 'Pre-pilot audit created the reserved process-reuse formal root.'
$ownedProcessPatterns = @('Run-Gate13FormalCampaign.ps1', 'Run-Gate13FormalScenarioCampaign.ps1', 'Run-PlanningWorkload.ps1')
$ownedProcesses = @(Get-CimInstance Win32_Process | Where-Object { $command = [string]$_.CommandLine; $null -ne $command -and @($ownedProcessPatterns | Where-Object { $command.Contains($_) }).Count -gt 0 })
Assert-True ($ownedProcesses.Count -eq 0) 'A cold Gate 13 owned process remains active.'

$passed = $failures.Count -eq 0
$summary = [ordered]@{
    schemaVersion = 1
    auditId = 'gate13-r2-process-reuse-pre-pilot-audit-v1'
    auditMode = 'preservation-static-unit-regression-negative-fail-closed-validation-only'
    savedAt = (Get-Date).ToString('o')
    projectPath = $ProjectPath
    assertionCount = $assertionCount
    failures = $failures.ToArray()
    pilotPlanSha256 = Get-G13R2LowerSha256 -Path $planPath
    provenanceSha256 = Get-G13R2LowerSha256 -Path $provenancePath
    processReuseCommandSha256 = Get-G13R2LowerSha256 -Path $commandPath
    compileLogSha256 = Get-G13R2LowerSha256 -Path $compileLogPath
    retainedRegression = if ($null -eq $regressionSummary) { $null } else { [ordered]@{ sourceScriptSha256 = Get-G13R2LowerSha256 -Path $regressionScriptPath; assertionCount = [int]$regressionSummary.assertionCount; summarySha256 = Get-G13R2LowerSha256 -Path $regressionSummaryPath; passed = [bool]$regressionSummary.passed } }
    preservation = [ordered]@{
        coldRootFileCount = $coldFiles.Count
        coldRootRawBytes = $coldBytes
        coldRootReadOnlyFileCount = $coldReadOnlyCount
        coldCheckpointSha256 = Get-G13R2LowerSha256 -Path $coldCheckpointPath
        gate11BundleFileCount = 57
        gate12SuccessfulV1FileCount = 1694
        gate12FailureAttempt1 = $attempt1
        gate12FailureAttempt2 = $attempt2
        originalBaselineChecked = $baselineRows.Count
        originalBaselineMismatches = $baselineMismatches.ToArray()
    }
    parserErrors = $parseErrors.ToArray()
    mutableStaticFields = @($mutableStaticFields | ForEach-Object { $_.Line })
    positiveBlockFixtures = $positiveFixtures.ToArray()
    negativeFailClosedFixture = $negativeFixture
    unityProcessIdsAfterAudit = @($unityProcesses | ForEach-Object Id)
    unityLockfileAfterAudit = $unityLockfile
    coldOwnedProcessIdsAfterAudit = @($ownedProcesses | ForEach-Object ProcessId)
    pilotRootExists = Test-Path -LiteralPath $pilotRoot
    reservedFormalRootExists = Test-Path -LiteralPath $formalRoot
    formalExecutionAuthorized = $false
    pilotExecutionAuthorizedByAudit = $passed
    automaticRetryAuthorized = $false
    automaticResumeAuthorized = $false
    passed = $passed
}
Write-G13R2AtomicUtf8NoBomJson -Path $summaryPath -Value $summary -Depth 30
$summary | ConvertTo-Json -Depth 12
if (-not $passed) { Write-Error "Gate 13-R2 pre-pilot audit failed; no pilot was started and no retry is authorized. Review $summaryPath"; exit 1 }
Write-Host "Gate 13-R2 pre-pilot audit passed ($assertionCount assertions plus retained 63/63). Formal execution remains unauthorized." -ForegroundColor Green
exit 0
