[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$ProjectPath,
    [string]$UnityPath = 'H:\UnityEditor\2022.3.30f1c1\Editor\Unity.exe',
    [switch]$BindingSmokeOnly,
    [int]$TimeoutSeconds = 3600
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if ([string]::IsNullOrWhiteSpace($ProjectPath) -or -not [IO.Path]::IsPathRooted($ProjectPath)) { throw 'An explicit absolute ProjectPath is required.' }
$ProjectPath = [IO.Path]::GetFullPath($ProjectPath)
if ($BindingSmokeOnly) { Write-Output "BINDING-SMOKE-PASSED|Invoke-Gate13RPR2Attempt2ContractRehearsalV1|$ProjectPath"; exit 0 }

$UnityPath = [IO.Path]::GetFullPath($UnityPath)
$rehearsalRoot = [IO.Path]::GetFullPath((Join-Path $ProjectPath 'Research\Verification\Gate13R_PR2_Formal_Attempt2\v1\ContractRehearsal')).TrimEnd('\', '/')
$formalRoot = Join-Path $ProjectPath 'Research\FormalRuns\Gate13R_RQAligned_S48H48\v2'
$formalReceipt = Join-Path $ProjectPath 'Research\Gate13R_PR2_Formal_Execution_Receipt.v2.json'
$formalStatus = Join-Path $ProjectPath 'Research\Gate13R_PR2_Formal_Execution_Status.v2.json'
$modulePath = Join-Path $ProjectPath 'Research\Gate13RPR2FormalExecutionV5.psm1'
$wrapperPath = Join-Path $ProjectPath 'Research\Run-Gate13RPR2FormalBlockV6.ps1'
$schedulePath = Join-Path $ProjectPath 'Research\Gate13R_PR2_Formal_Williams_Matched_Schedule.v2.jsonl'
$configPath = Join-Path $ProjectPath 'Research\Gate13R_PR2_Formal_Campaign_Config.v2.json'
$specificationPath = Join-Path $ProjectPath 'Research\Gate13R_PR2_RawAnalysis_TwoPhaseCommit_Specification.v1.md'
$testDesignPath = Join-Path $ProjectPath 'Research\Gate13R_PR2_Attempt2_Prelaunch_Test_Design.v1.md'
$amendmentPath = Join-Path $ProjectPath 'Research\Gate13R_PR2_RawAnalysis_TwoPhaseCommit_Amendment.v1.json'
$commandPath = Join-Path $ProjectPath 'Assets\_Scripts\Research\Editor\Gate13RPR2FormalBatchCommandV4.cs'
$provenancePath = Join-Path $ProjectPath 'Research\Gate13R_PR2_Attempt2_Validation_Provenance.v1.json'
$authorizationPath = Join-Path $ProjectPath 'Research\Gate13R_PR2_Attempt2_Execution_Authorization.v1.json'
$receiptPath = Join-Path $rehearsalRoot 'validation-only-rehearsal-receipt.json'
$planPath = Join-Path $rehearsalRoot 'validation-only-block-plan.json'
$wrapperStdout = Join-Path $rehearsalRoot 'block-wrapper.stdout.log'
$wrapperStderr = Join-Path $rehearsalRoot 'block-wrapper.stderr.log'
$auditPath = Join-Path $rehearsalRoot 'rehearsal-contract-audit.json'

Import-Module $modulePath -Force
foreach ($required in @($UnityPath,$wrapperPath,$schedulePath,$configPath,$specificationPath,$testDesignPath,$amendmentPath,$commandPath,$provenancePath,$authorizationPath)) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) { throw "Required rehearsal input is missing: $required" }
}
if (Test-Path -LiteralPath $rehearsalRoot) { throw 'Create-new contract rehearsal root already exists.' }
if ((Test-Path -LiteralPath $formalRoot) -or (Test-Path -LiteralPath $formalReceipt) -or (Test-Path -LiteralPath $formalStatus)) { throw 'Formal root, receipt and status must remain absent during rehearsal.' }
if (@(Get-Process -Name Unity -ErrorAction SilentlyContinue).Count -ne 0 -or (Test-Path -LiteralPath (Join-Path $ProjectPath 'Temp\UnityLockfile'))) { throw 'Unity must be quiescent and the project lock absent before rehearsal.' }

New-Item -ItemType Directory -Path $rehearsalRoot | Out-Null
try {
    $scheduleRecord = ([IO.File]::ReadLines($schedulePath, [Text.Encoding]::UTF8) | Select-Object -First 1) | ConvertFrom-Json
    if ([int]$scheduleRecord.globalProcessOrdinal -ne 1 -or [string]$scheduleRecord.comparisonCohortId -ne 'four-algorithm-shared-goal-v1' -or [int]$scheduleRecord.expectedSampleCount -ne 4 -or @($scheduleRecord.entries).Count -ne 4) { throw 'Frozen first schedule record is not the required four-algorithm rehearsal block.' }
    $receipt = [ordered]@{
        schemaVersion = 1
        receiptKind = 'gate13r-pr2-attempt2-validation-only-contract-rehearsal-receipt-v1'
        createdAtUtc = [DateTime]::UtcNow.ToString('o')
        status = 'VALIDATION-ONLY / EXCLUDED-FROM-FORMAL-ANALYSIS'
        contractRehearsalId = 'gate13r-pr2-attempt2-embedded-contract-rehearsal-v1'
        formalExecutionAuthorized = $false
        formalStatisticalAnalysisAuthorized = $false
        gate14RAuthorized = $false
        rehearsalRootResolved = $rehearsalRoot
        authorizationSha256 = Get-G13RPR2Sha256 $authorizationPath
        provenanceSha256 = Get-G13RPR2Sha256 $provenancePath
        commandSha256 = Get-G13RPR2Sha256 $commandPath
        wrapperSha256 = Get-G13RPR2Sha256 $wrapperPath
        noMergeWithFormalData = $true
    }
    Write-G13RPR2AtomicJson -Path $receiptPath -Value $receipt -Depth 30
    $receiptSha = Get-G13RPR2Sha256 $receiptPath
    $plan = New-G13RPR2BlockPlanFromScheduleRecord -ScheduleRecord $scheduleRecord -FormalConfigRelativePath (Get-G13RPR2ProjectRelativePath -ProjectPath $ProjectPath -Path $configPath) -FormalConfigSha256 (Get-G13RPR2Sha256 $configPath) -SpecificationRelativePath (Get-G13RPR2ProjectRelativePath -ProjectPath $ProjectPath -Path $specificationPath) -SpecificationSha256 (Get-G13RPR2Sha256 $specificationPath) -TestDesignRelativePath (Get-G13RPR2ProjectRelativePath -ProjectPath $ProjectPath -Path $testDesignPath) -TestDesignSha256 (Get-G13RPR2Sha256 $testDesignPath) -AmendmentRelativePath (Get-G13RPR2ProjectRelativePath -ProjectPath $ProjectPath -Path $amendmentPath) -AmendmentSha256 (Get-G13RPR2Sha256 $amendmentPath) -CommandRelativePath (Get-G13RPR2ProjectRelativePath -ProjectPath $ProjectPath -Path $commandPath) -CommandSha256 (Get-G13RPR2Sha256 $commandPath) -ProvenanceRelativePath (Get-G13RPR2ProjectRelativePath -ProjectPath $ProjectPath -Path $provenancePath) -ProvenanceSha256 (Get-G13RPR2Sha256 $provenancePath) -ExecutionReceiptRelativePath (Get-G13RPR2ProjectRelativePath -ProjectPath $ProjectPath -Path $receiptPath) -ExecutionReceiptSha256 $receiptSha
    $plan.Add('validationOnly', $true)
    $plan.Add('excludedFromFormalAnalysis', $true)
    $plan.Add('formalExecutionAuthorized', $false)
    $plan.Add('contractRehearsalId', 'gate13r-pr2-attempt2-embedded-contract-rehearsal-v1')
    Write-G13RPR2AtomicJson -Path $planPath -Value $plan -Depth 40
    $outputDirectory = [IO.Path]::GetFullPath((Join-Path $rehearsalRoot ([string]$scheduleRecord.outputRelativePath).Replace('/', '\')))
    $windowsPowerShell = 'C:\WINDOWS\System32\WindowsPowerShell\v1.0\powershell.exe'
    & $windowsPowerShell -NoProfile -ExecutionPolicy Bypass -File $wrapperPath -ProjectPath $ProjectPath -BlockPlanPath $planPath -OutputDirectory $outputDirectory -AllowedRoot $rehearsalRoot -ExecutionReceiptPath $receiptPath -UnityPath $UnityPath -ValidationOnlyContractRehearsal -TimeoutSeconds $TimeoutSeconds 1>$wrapperStdout 2>$wrapperStderr
    $wrapperExit = [int]$LASTEXITCODE
    if ($wrapperExit -ne 0) { throw "Validation-only block wrapper exited $wrapperExit." }

    $wrapperSummaryPath = $outputDirectory + '.summary.json'
    $manifestPath = Join-Path $outputDirectory 'block-manifest.json'
    if (-not (Test-Path -LiteralPath $wrapperSummaryPath -PathType Leaf) -or -not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) { throw 'Rehearsal wrapper summary or block manifest is missing.' }
    $wrapperSummary = Read-G13RPR2Json $wrapperSummaryPath
    $manifest = Read-G13RPR2Json $manifestPath
    $embedded = Test-G13RPR2EmbeddedSampleFormalCampaignContract -Samples @($manifest.samples) -ExpectedCount 4
    if ($wrapperSummary.passed -ne $true -or $wrapperSummary.validationOnly -ne $true -or $wrapperSummary.excludedFromFormalAnalysis -ne $true -or $wrapperSummary.formalExecutionAuthorized -ne $false -or $wrapperSummary.embeddedFormalCampaignContractPassed -ne $true -or $manifest.completed -ne $true -or $manifest.formalCampaign -ne $true -or $embedded.passed -ne $true) { throw 'Rehearsal top-level or embedded formalCampaign contract failed.' }
    $documentChecks = New-Object Collections.Generic.List[object]
    foreach ($sample in @($manifest.samples)) {
        $documents = [ordered]@{
            sampleSummary = [IO.Path]::GetFullPath((Join-Path $outputDirectory ([string]$sample.summaryRelativePath).Replace('/', '\')))
            childManifest = [IO.Path]::GetFullPath((Join-Path $outputDirectory ([string]$sample.manifestRelativePath).Replace('/', '\')))
            memoryEvaluation = [IO.Path]::GetFullPath((Join-Path $outputDirectory ([string]$sample.memoryGateEvaluationRelativePath).Replace('/', '\')))
        }
        foreach ($role in $documents.Keys) {
            $path = [string]$documents[$role]
            if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Rehearsal child document missing: $role run=$($sample.runId)" }
            $document = Read-G13RPR2Json $path
            $formalProperty = $document.PSObject.Properties['formalCampaign']
            if ($null -eq $formalProperty -or $formalProperty.Value -isnot [bool] -or $formalProperty.Value -ne $true) { throw "Rehearsal child formalCampaign contract failed: $role run=$($sample.runId)" }
            $documentChecks.Add([ordered]@{ runId = [string]$sample.runId; role = $role; relativePath = Get-G13RPR2ProjectRelativePath -ProjectPath $ProjectPath -Path $path; sha256 = Get-G13RPR2Sha256 $path; formalCampaign = $true })
        }
    }
    if (@($manifest.samples | Select-Object -ExpandProperty processId -Unique).Count -ne 1 -or [int]$manifest.processId -le 0) { throw 'Rehearsal samples do not share one valid Unity process identity.' }
    $audit = [ordered]@{
        schemaVersion = 1
        auditKind = 'gate13r-pr2-attempt2-validation-only-full-block-contract-rehearsal-audit-v1'
        savedAtUtc = [DateTime]::UtcNow.ToString('o')
        status = 'VALIDATION-ONLY / EXCLUDED-FROM-FORMAL-ANALYSIS / PASSED'
        contractRehearsalId = 'gate13r-pr2-attempt2-embedded-contract-rehearsal-v1'
        scheduleSourceGlobalOrdinal = 1
        blockId = [string]$manifest.blockId
        unityProcessId = [int]$manifest.processId
        sampleCount = @($manifest.samples).Count
        embeddedFormalCampaignTrueCount = @($manifest.samples | Where-Object { $_.formalCampaign -eq $true }).Count
        sampleSummaryFormalCampaignTrueCount = @($documentChecks | Where-Object role -eq 'sampleSummary').Count
        childManifestFormalCampaignTrueCount = @($documentChecks | Where-Object role -eq 'childManifest').Count
        memoryEvaluationFormalCampaignTrueCount = @($documentChecks | Where-Object role -eq 'memoryEvaluation').Count
        wrapperSummarySha256 = Get-G13RPR2Sha256 $wrapperSummaryPath
        blockManifestSha256 = Get-G13RPR2Sha256 $manifestPath
        blockPlanSha256 = Get-G13RPR2Sha256 $planPath
        validationReceiptSha256 = $receiptSha
        childDocuments = $documentChecks.ToArray()
        formalRootV2Created = Test-Path -LiteralPath $formalRoot
        formalReceiptV2Created = Test-Path -LiteralPath $formalReceipt
        formalStatusV2Created = Test-Path -LiteralPath $formalStatus
        passed = $true
    }
    Write-G13RPR2AtomicJson -Path $auditPath -Value $audit -Depth 50
    Write-Output "GATE13R-PR2-ATTEMPT2-CONTRACT-REHEARSAL-PASSED|$($manifest.blockId)|4-SAMPLES"
    exit 0
}
catch {
    $files = @(Get-ChildItem -LiteralPath $rehearsalRoot -File -Recurse -Force -ErrorAction SilentlyContinue)
    $failure = [ordered]@{
        schemaVersion = 1
        receiptKind = 'gate13r-pr2-attempt2-validation-only-contract-rehearsal-failure-v1'
        savedAtUtc = [DateTime]::UtcNow.ToString('o')
        status = 'FAILED-VALIDATION-ONLY / EXCLUDED-FROM-FORMAL-ANALYSIS / FORMAL-ROOT-NOT-CREATED'
        error = $_.Exception.ToString()
        fileCount = $files.Count
        rawBytes = [long](($files | Measure-Object Length -Sum).Sum)
        formalRootV2Created = Test-Path -LiteralPath $formalRoot
        formalReceiptV2Created = Test-Path -LiteralPath $formalReceipt
        formalStatusV2Created = Test-Path -LiteralPath $formalStatus
        automaticFormalRetryAttempted = $false
    }
    $failurePath = Join-Path $rehearsalRoot 'rehearsal-failure-receipt.json'
    Write-G13RPR2AtomicJson -Path $failurePath -Value $failure -Depth 40
    Write-Error "Gate13R-PR2 attempt-2 contract rehearsal failed: $($_.Exception.Message)"
    exit 1
}

