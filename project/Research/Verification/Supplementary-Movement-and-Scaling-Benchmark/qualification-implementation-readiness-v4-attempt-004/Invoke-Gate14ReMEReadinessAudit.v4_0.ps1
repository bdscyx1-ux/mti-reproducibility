[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$ProjectRoot = "H:/DDM_Final_Project"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Resolve-ProjectPath {
    param([Parameter(Mandatory = $true)][string]$RelativePath)
    return [System.IO.Path]::GetFullPath((Join-Path $ProjectRoot ($RelativePath -replace '/', [System.IO.Path]::DirectorySeparatorChar)))
}

function Get-Sha256Lower {
    param([Parameter(Mandatory = $true)][string]$LiteralPath)
    return (Get-FileHash -Algorithm SHA256 -LiteralPath $LiteralPath).Hash.ToLowerInvariant()
}

$checks = [System.Collections.Generic.List[object]]::new()
function Add-Check {
    param(
        [Parameter(Mandatory = $true)][string]$CheckId,
        [Parameter(Mandatory = $true)][bool]$Passed,
        [Parameter(Mandatory = $true)][object]$Evidence
    )
    $checks.Add([ordered]@{ checkId = $CheckId; passed = $Passed; evidence = $Evidence })
}

$manifestRelative = "Research/Gate14Re-ME/Execution/v4/load-qualification-current-implementation-manifest.v4_0.json"
$manifestPath = Resolve-ProjectPath $manifestRelative
$manifest = Get-Content -Raw -LiteralPath $manifestPath | ConvertFrom-Json

$artifactResults = @()
foreach ($artifact in $manifest.artifacts) {
    $path = Resolve-ProjectPath ([string]$artifact.relativePath)
    $exists = Test-Path -LiteralPath $path -PathType Leaf
    $actualBytes = if ($exists) { (Get-Item -LiteralPath $path).Length } else { $null }
    $actualSha = if ($exists) { Get-Sha256Lower $path } else { $null }
    $match = $exists -and ($actualBytes -eq [int64]$artifact.bytes) -and ($actualSha -ceq ([string]$artifact.sha256).ToLowerInvariant())
    $artifactResults += [ordered]@{
        role = [string]$artifact.role
        relativePath = [string]$artifact.relativePath
        exists = $exists
        expectedBytes = [int64]$artifact.bytes
        actualBytes = $actualBytes
        expectedSha256 = ([string]$artifact.sha256).ToLowerInvariant()
        actualSha256 = $actualSha
        match = $match
    }
}
Add-Check "implementation-manifest-artifacts" (@($artifactResults | Where-Object { -not $_.match }).Count -eq 0) ([ordered]@{
    manifestSha256 = Get-Sha256Lower $manifestPath
    artifactCount = $artifactResults.Count
    mismatches = @($artifactResults | Where-Object { -not $_.match })
})

$acquisitionContractPath = Resolve-ProjectPath "Research/Gate14Re-ME/Execution/v4/load-qualification-acquisition-contract.v4_0.json"
$acceptanceContractPath = Resolve-ProjectPath "Research/Gate14Re-ME/Execution/v4/load-qualification-acceptance-contract.v4_1.json"
$acquisitionContract = Get-Content -Raw -LiteralPath $acquisitionContractPath | ConvertFrom-Json
$acceptanceContract = Get-Content -Raw -LiteralPath $acceptanceContractPath | ConvertFrom-Json

$bindingResults = [System.Collections.Generic.List[object]]::new()
function Test-BoundFile {
    param([string]$BindingId, [string]$RelativePath, [string]$ExpectedSha256)
    $path = Resolve-ProjectPath $RelativePath
    $exists = Test-Path -LiteralPath $path -PathType Leaf
    $actualSha = if ($exists) { Get-Sha256Lower $path } else { $null }
    $bindingResults.Add([ordered]@{
        bindingId = $BindingId
        relativePath = $RelativePath
        exists = $exists
        expectedSha256 = $ExpectedSha256.ToLowerInvariant()
        actualSha256 = $actualSha
        match = $exists -and ($actualSha -ceq $ExpectedSha256.ToLowerInvariant())
    })
}

Test-BoundFile "acquisition-entry-supervisor" $acquisitionContract.entryPoint.supervisorRelativePath $acquisitionContract.entryPoint.supervisorSha256
Test-BoundFile "acquisition-entry-runner" $acquisitionContract.entryPoint.runnerRelativePath $acquisitionContract.entryPoint.runnerSha256
Test-BoundFile "acquisition-entry-runner-meta" $acquisitionContract.entryPoint.runnerMetaRelativePath $acquisitionContract.entryPoint.runnerMetaSha256
foreach ($property in $acquisitionContract.frozenBindings.PSObject.Properties) {
    $value = $property.Value
    Test-BoundFile ("acquisition-binding-" + $property.Name) $value.relativePath $value.sha256
}
Test-BoundFile "acceptance-entry-launcher" $acceptanceContract.entryPoint.launcherRelativePath $acceptanceContract.entryPoint.launcherSha256
Test-BoundFile "acceptance-entry-tool" $acceptanceContract.entryPoint.toolRelativePath $acceptanceContract.entryPoint.toolSha256
foreach ($property in $acceptanceContract.frozenBindings.PSObject.Properties) {
    $value = $property.Value
    $valuePropertyNames = @($value.PSObject.Properties.Name)
    if (($valuePropertyNames -contains 'relativePath') -and ($valuePropertyNames -contains 'sha256')) {
        Test-BoundFile ("acceptance-binding-" + $property.Name) $value.relativePath $value.sha256
    }
}
Add-Check "contract-file-bindings" (@($bindingResults | Where-Object { -not $_.match }).Count -eq 0) ([ordered]@{
    bindingCount = $bindingResults.Count
    mismatches = @($bindingResults | Where-Object { -not $_.match })
})

$jsonParseResults = @()
foreach ($artifact in ($manifest.artifacts | Where-Object { ([string]$_.relativePath).EndsWith('.json', [System.StringComparison]::OrdinalIgnoreCase) })) {
    $path = Resolve-ProjectPath ([string]$artifact.relativePath)
    try {
        $null = Get-Content -Raw -LiteralPath $path | ConvertFrom-Json
        $jsonParseResults += [ordered]@{ relativePath = [string]$artifact.relativePath; parsed = $true; error = $null }
    }
    catch {
        $jsonParseResults += [ordered]@{ relativePath = [string]$artifact.relativePath; parsed = $false; error = $_.Exception.Message }
    }
}
Add-Check "bound-json-parsing" (@($jsonParseResults | Where-Object { -not $_.parsed }).Count -eq 0) ([ordered]@{
    parsedFileCount = $jsonParseResults.Count
    failures = @($jsonParseResults | Where-Object { -not $_.parsed })
})

$powershellParseResults = @()
foreach ($relativePath in @(
    "Research/Gate14Re-ME/Execution/v4/Run-Gate14ReMELoadQualification.v4_0.ps1",
    "Research/Gate14Re-ME/Execution/v4/Run-Gate14ReMEReadOnlyAcceptance.v4_1.ps1"
)) {
    $tokens = $null
    $errors = $null
    $null = [System.Management.Automation.Language.Parser]::ParseFile((Resolve-ProjectPath $relativePath), [ref]$tokens, [ref]$errors)
    $powershellParseResults += [ordered]@{ relativePath = $relativePath; parseErrorCount = @($errors).Count; parseErrors = @($errors | ForEach-Object { $_.Message }) }
}
Add-Check "powershell-entrypoint-parsing" (@($powershellParseResults | Where-Object { $_.parseErrorCount -ne 0 }).Count -eq 0) $powershellParseResults

$pythonPath = "C:/Users/bdscy/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe"
$pythonToolRelative = "Research/Gate14Re-ME/Tools/gate14re_me_qualification_acceptance_v4_1.py"
$pythonToolPath = Resolve-ProjectPath $pythonToolRelative
$pythonHash = if (Test-Path -LiteralPath $pythonPath) { Get-Sha256Lower $pythonPath } else { $null }
$pythonAstOutput = & $pythonPath -c "import ast,pathlib,sys; ast.parse(pathlib.Path(sys.argv[1]).read_text(encoding='utf-8')); print('AST_PASS')" $pythonToolPath 2>&1
$pythonAstExit = $LASTEXITCODE
Add-Check "python-acceptance-ast" (($pythonAstExit -eq 0) -and ($pythonHash -ceq $acceptanceContract.frozenBindings.pythonExecutableSha256)) ([ordered]@{
    pythonPath = $pythonPath
    pythonSha256 = $pythonHash
    expectedPythonSha256 = $acceptanceContract.frozenBindings.pythonExecutableSha256
    toolRelativePath = $pythonToolRelative
    exitCode = $pythonAstExit
    output = @($pythonAstOutput | ForEach-Object { [string]$_ })
})

$scheduleRelative = "Research/Verification/Gate14Re-ME/qualification-planning-asset-generation-v4-attempt-002/planning-assets/schedule/bounded-qualification-williams-schedule.v4.jsonl"
$schedulePath = Resolve-ProjectPath $scheduleRelative
$scheduleRows = @(Get-Content -LiteralPath $schedulePath | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | ForEach-Object { $_ | ConvertFrom-Json })
$expectedAlgorithms = @('A*-R', 'BiA*-R', 'D*L', 'C-FF', 'IDFF', 'LPA*')
$expectedAnonymous = @('ALG-A', 'ALG-B', 'ALG-C', 'ALG-D', 'ALG-E', 'ALG-F')
$ordinals = @($scheduleRows | ForEach-Object { [int]$_.ordinal })
$ordinalPass = ($ordinals.Count -eq 126) -and (@(Compare-Object -ReferenceObject @(0..125) -DifferenceObject $ordinals).Count -eq 0)
$uniqueSuperblocks = @($scheduleRows.superblockId | Sort-Object -Unique)
$scheduleShapePass = ($scheduleRows.Count -eq 126) -and ($uniqueSuperblocks.Count -eq 126) -and $ordinalPass -and (@($scheduleRows | Where-Object { $_.schema -cne 'gate14re-me-load-qualification-schedule-row-v4' }).Count -eq 0) -and (@($scheduleRows | Where-Object { $null -ne $_.replacement }).Count -eq 0)

$inputResults = @()
$lanePositionCounts = @{}
for ($position = 0; $position -lt 6; $position++) {
    foreach ($algorithm in $expectedAlgorithms) { $lanePositionCounts["$position|$algorithm"] = 0 }
}
$algorithmOccurrenceCounts = @{}
foreach ($algorithm in $expectedAlgorithms) { $algorithmOccurrenceCounts[$algorithm] = 0 }
$coreCellCounts = @{}
$stressCellCounts = @{}
$predecessorCounts = @{}
foreach ($left in $expectedAlgorithms) { foreach ($right in $expectedAlgorithms) { if ($left -cne $right) { $predecessorCounts["$left|$right"] = 0 } } }

foreach ($row in $scheduleRows) {
    $inputPath = Resolve-ProjectPath ([string]$row.inputRelativePath)
    $inputExists = Test-Path -LiteralPath $inputPath -PathType Leaf
    $inputHash = if ($inputExists) { Get-Sha256Lower $inputPath } else { $null }
    $input = if ($inputExists) { Get-Content -Raw -LiteralPath $inputPath | ConvertFrom-Json } else { $null }
    $algorithms = @($row.algorithmOrder | ForEach-Object { [string]$_.algorithmId })
    $anonymous = @($row.algorithmOrder | ForEach-Object { [string]$_.anonymousLaneId })
    $algorithmSetPass = ($algorithms.Count -eq 6) -and (@(Compare-Object -ReferenceObject ($expectedAlgorithms | Sort-Object) -DifferenceObject ($algorithms | Sort-Object)).Count -eq 0)
    $anonymousSetPass = ($anonymous.Count -eq 6) -and (@(Compare-Object -ReferenceObject ($expectedAnonymous | Sort-Object) -DifferenceObject ($anonymous | Sort-Object)).Count -eq 0)
    for ($position = 0; $position -lt $algorithms.Count; $position++) {
        $algorithm = $algorithms[$position]
        $lanePositionCounts["$position|$algorithm"]++
        $algorithmOccurrenceCounts[$algorithm]++
        if ($position -gt 0) { $predecessorCounts["$($algorithms[$position - 1])|$algorithm"]++ }
    }
    $g = if ($null -ne $input) { [int]$input.gridEdge } else { -1 }
    $n = if ($null -ne $input) { [int]$input.agentCount } else { -1 }
    $f = if ($null -ne $input) { [int]$input.changedCellCount } else { -1 }
    $region = if ($null -ne $input) { [string]$input.designRegion } else { '' }
    $cellKey = "$g|$n|$f"
    if ($region -ceq 'core') {
        if (-not $coreCellCounts.ContainsKey($cellKey)) { $coreCellCounts[$cellKey] = 0 }
        $coreCellCounts[$cellKey]++
    }
    elseif ($region -ceq 'stress') {
        if (-not $stressCellCounts.ContainsKey($cellKey)) { $stressCellCounts[$cellKey] = 0 }
        $stressCellCounts[$cellKey]++
    }
    $eventGroupWidthsPass = $false
    if ($null -ne $input) {
        $eventGroupWidthsPass = (@($input.eventGroups).Count -eq 24)
        foreach ($eventGroup in @($input.eventGroups)) {
            $width = 0
            foreach ($partition in @($eventGroup.atomicPartitions)) { $width += @($partition.changes).Count }
            if ($width -ne $f) { $eventGroupWidthsPass = $false; break }
        }
    }
    $inputResults += [ordered]@{
        ordinal = [int]$row.ordinal
        superblockId = [string]$row.superblockId
        inputRelativePath = [string]$row.inputRelativePath
        exists = $inputExists
        expectedSha256 = ([string]$row.inputSha256).ToLowerInvariant()
        actualSha256 = $inputHash
        shaMatch = $inputExists -and ($inputHash -ceq ([string]$row.inputSha256).ToLowerInvariant())
        superblockMatch = ($null -ne $input) -and ([string]$input.superblockId -ceq [string]$row.superblockId)
        algorithmSetPass = $algorithmSetPass
        anonymousSetPass = $anonymousSetPass
        identityHashPass = (@($row.algorithmOrder | Where-Object { ([string]$_.identityBindingSha256).ToLowerInvariant() -cne '77b88a23a559642d455edf0d4caad9a1f9c06b7ddf33703b8fd100f4a1878bd2' }).Count -eq 0)
        gridEdge = $g
        agentCount = $n
        changedCellCount = $f
        designRegion = $region
        eventGroupWidthsPass = $eventGroupWidthsPass
    }
}
$inputFailures = @($inputResults | Where-Object { -not ($_.exists -and $_.shaMatch -and $_.superblockMatch -and $_.algorithmSetPass -and $_.anonymousSetPass -and $_.identityHashPass -and $_.eventGroupWidthsPass) })
Add-Check "schedule-and-input-bindings" ($scheduleShapePass -and $inputFailures.Count -eq 0) ([ordered]@{
    scheduleSha256 = Get-Sha256Lower $schedulePath
    scheduleRows = $scheduleRows.Count
    uniqueSuperblocks = $uniqueSuperblocks.Count
    ordinalCoveragePass = $ordinalPass
    replacementRows = @($scheduleRows | Where-Object { $null -ne $_.replacement }).Count
    inputFailures = $inputFailures
})

$expectedCoreCells = foreach ($g in @(64,96,128)) { foreach ($n in @(32,64,128)) { foreach ($f in @(1,9,25,81)) { "$g|$n|$f" } } }
$coreKeysPass = @(Compare-Object -ReferenceObject ($expectedCoreCells | Sort-Object) -DifferenceObject (@($coreCellCounts.Keys) | Sort-Object)).Count -eq 0
$coreCountsPass = (@($coreCellCounts.GetEnumerator() | Where-Object { $_.Value -ne 3 }).Count -eq 0)
$stressPass = ($stressCellCounts.Count -eq 1) -and $stressCellCounts.ContainsKey('128|128|81') -and ($stressCellCounts['128|128|81'] -eq 18)
$laneBalancePass = (@($lanePositionCounts.GetEnumerator() | Where-Object { $_.Value -ne 21 }).Count -eq 0)
$algorithmOccurrencesPass = (@($algorithmOccurrenceCounts.GetEnumerator() | Where-Object { $_.Value -ne 126 }).Count -eq 0)
$predecessorBalancePass = (@($predecessorCounts.GetEnumerator() | Where-Object { $_.Value -ne 21 }).Count -eq 0)
Add-Check "bounded-gnf-and-williams-design" ($coreKeysPass -and $coreCountsPass -and $stressPass -and $laneBalancePass -and $algorithmOccurrencesPass -and $predecessorBalancePass) ([ordered]@{
    coreSuperblocks = @($inputResults | Where-Object { $_.designRegion -ceq 'core' }).Count
    stressSuperblocks = @($inputResults | Where-Object { $_.designRegion -ceq 'stress' }).Count
    coreCellCount = $coreCellCounts.Count
    coreCellCounts = [ordered]@{} + $coreCellCounts
    stressCellCounts = [ordered]@{} + $stressCellCounts
    lanePositionCounts = [ordered]@{} + $lanePositionCounts
    algorithmOccurrenceCounts = [ordered]@{} + $algorithmOccurrenceCounts
    predecessorCounts = [ordered]@{} + $predecessorCounts
})

$outputSchemaPath = Resolve-ProjectPath "Research/Gate14Re-ME/Execution/v4/load-qualification-output-schema.v4_0.json"
$outputSchema = Get-Content -Raw -LiteralPath $outputSchemaPath | ConvertFrom-Json
$closure = $outputSchema.terminalControlPlane.fullQualificationClosure
$processCountsPass = ([int]$closure.acceptedSuperblockReceipts -eq 126) -and ([int]$closure.laneReceipts -eq 756) -and ([int]$closure.emptyBoundaryReceipts -eq 12) -and ([int]$closure.processLedgerRows -eq 895) -and ([int]$closure.processIdentityReceipts -eq 895) -and ([int]$outputSchema.terminalControlPlane.processLedger.qualificationModeCounts.'instrument-self-test' -eq 1) -and ([int]$outputSchema.terminalControlPlane.processLedger.qualificationModeCounts.oracle -eq 126) -and ([int]$outputSchema.terminalControlPlane.processLedger.qualificationModeCounts.'empty-boundary' -eq 12) -and ([int]$outputSchema.terminalControlPlane.processLedger.qualificationModeCounts.lane -eq 756)
Add-Check "planned-acquisition-cardinality" $processCountsPass ([ordered]@{
    instrumentSelfTest = [int]$outputSchema.terminalControlPlane.processLedger.qualificationModeCounts.'instrument-self-test'
    oracle = [int]$outputSchema.terminalControlPlane.processLedger.qualificationModeCounts.oracle
    emptyBoundary = [int]$outputSchema.terminalControlPlane.processLedger.qualificationModeCounts.'empty-boundary'
    lanes = [int]$outputSchema.terminalControlPlane.processLedger.qualificationModeCounts.lane
    totalFreshProcesses = [int]$closure.processLedgerRows
    maximumReplacementRowsPerPlannedSuperblock = [int](($outputSchema.rawTables | Where-Object { $_.tableId -ceq 'replacement-ledger' }).maximumRowsPerPlannedSuperblock)
})

$sampleDecisionPath = Resolve-ProjectPath "Research/Gate14Re-ME/Execution/v4/formal-sample-size-decision.v4_0.json"
$sampleDecision = Get-Content -Raw -LiteralPath $sampleDecisionPath | ConvertFrom-Json
$candidateB = @($sampleDecision.candidateB | ForEach-Object { [int]$_ })
$candidateGridPass = ($candidateB.Count -gt 0) -and (@($candidateB | Where-Object { ($_ -le 0) -or (($_ % 36) -ne 0) }).Count -eq 0)
$bStatePass = ($null -eq $sampleDecision.finalB) -and ([int]$sampleDecision.provisionalMinimumB -eq 36) -and $candidateGridPass -and ([string]$sampleDecision.status -ceq 'PENDING_NEW_QUALIFICATION_AND_ANONYMOUS_POWER_REFREEZE')
Add-Check "formal-b-state" $bStatePass ([ordered]@{
    status = [string]$sampleDecision.status
    finalB = $sampleDecision.finalB
    provisionalMinimumB = $sampleDecision.provisionalMinimumB
    candidateGridRule = [string]$sampleDecision.candidateGridRule
    candidateB = $candidateB
    candidateGridPass = $candidateGridPass
})

$compileReceiptRelative = "Research/Verification/Gate14Re-ME/qualification-implementation-readiness-v4-attempt-003/compile-readiness-receipt.v4_2.json"
$compileReceiptPath = Resolve-ProjectPath $compileReceiptRelative
$compileReceipt = Get-Content -Raw -LiteralPath $compileReceiptPath | ConvertFrom-Json
$priorFailurePaths = @(
    "Research/Verification/Gate14Re-ME/qualification-implementation-readiness-v4-attempt-001/failure-receipt.v4.json",
    "Research/Verification/Gate14Re-ME/qualification-implementation-readiness-v4-attempt-002/failure-receipt.v4_1.json"
)
$priorFailuresPreserved = @($priorFailurePaths | Where-Object { -not (Test-Path -LiteralPath (Resolve-ProjectPath $_) -PathType Leaf) }).Count -eq 0
$compilePass = ([string]$compileReceipt.status -match 'PASS') -and ([int]$compileReceipt.unity.exitCode -eq 0) -and ([bool]$compileReceipt.unity.naturalExit) -and (-not [bool]$compileReceipt.unity.signalOrForcedTerminationSent) -and $priorFailuresPreserved
Add-Check "compile-readiness-and-failure-preservation" $compilePass ([ordered]@{
    compileReceiptRelativePath = $compileReceiptRelative
    compileReceiptSha256 = Get-Sha256Lower $compileReceiptPath
    compileStatus = [string]$compileReceipt.status
    exitCode = $compileReceipt.unity.exitCode
    naturalExit = $compileReceipt.unity.naturalExit
    signalOrForcedTerminationSent = $compileReceipt.unity.signalOrForcedTerminationSent
    priorFailureReceipts = $priorFailurePaths
    priorFailuresPreserved = $priorFailuresPreserved
})

$sealTerminalRelative = "Research/Verification/Gate14Re-ME/load-qualification-paused-seal-attempt-009/terminal-seal-receipt.v1.json"
$sealManifestRelative = "Research/Verification/Gate14Re-ME/load-qualification-paused-seal-attempt-009/measured-file-manifest.v1.jsonl"
$sealTerminalPath = Resolve-ProjectPath $sealTerminalRelative
$sealManifestPath = Resolve-ProjectPath $sealManifestRelative
$sealTerminalSha = if (Test-Path -LiteralPath $sealTerminalPath) { Get-Sha256Lower $sealTerminalPath } else { $null }
$sealManifestSha = if (Test-Path -LiteralPath $sealManifestPath) { Get-Sha256Lower $sealManifestPath } else { $null }
$unityProcesses = @(Get-CimInstance Win32_Process -Filter "Name='Unity.exe'" | Where-Object { ([string]$_.CommandLine) -match 'Gate14ReMELoadQualificationRunner' })
$newMeasuredRoot = Resolve-ProjectPath "Research/PilotRuns/Gate14Re-ME/load-qualification/attempt-008"
$sealPass = ($sealTerminalSha -ceq '7c7c56f7b75b9fd1f4bbfee439960b6c486e180e940bdc09f99c171c059bd705') -and ($sealManifestSha -ceq 'bb05763473cb5af321bd82f3b00a738cd3d066522527a813fef667b6c50a493f') -and ($unityProcesses.Count -eq 0) -and (-not (Test-Path -LiteralPath $newMeasuredRoot))
Add-Check "attempt-009-seal-and-no-execution" $sealPass ([ordered]@{
    terminalReceiptRelativePath = $sealTerminalRelative
    terminalReceiptSha256 = $sealTerminalSha
    expectedTerminalReceiptSha256 = '7c7c56f7b75b9fd1f4bbfee439960b6c486e180e940bdc09f99c171c059bd705'
    sealManifestRelativePath = $sealManifestRelative
    sealManifestSha256 = $sealManifestSha
    expectedSealManifestSha256 = 'bb05763473cb5af321bd82f3b00a738cd3d066522527a813fef667b6c50a493f'
    activeQualificationUnityRunnerCount = $unityProcesses.Count
    freshMeasuredAttempt008Exists = Test-Path -LiteralPath $newMeasuredRoot
})

$failedChecks = @($checks | Where-Object { -not $_.passed })
$result = [ordered]@{
    schema = "gate14re-me-qualification-readiness-audit-result-v4"
    studyId = "Gate14Re-ME"
    attemptId = "qualification-implementation-readiness-v4-attempt-004"
    checkedAtUtc = (Get-Date).ToUniversalTime().ToString('o')
    status = if ($failedChecks.Count -eq 0) { "PASS_STATIC_AND_COMPILE_READINESS_EXECUTION_UNAUTHORIZED" } else { "FAIL_CLOSED_STATIC_READINESS" }
    checksPassed = @($checks | Where-Object { $_.passed }).Count
    checksFailed = $failedChecks.Count
    checks = $checks
    boundary = [ordered]@{
        qualificationExecutionStarted = $false
        measuredRootCreated = $false
        deliveryRootCreated = $false
        algorithmObservationsRead = $false
        formalAnalysisPerformed = $false
        rankingOrWinnerComputed = $false
        migrationPackageBuilt = $false
    }
}

$result | ConvertTo-Json -Depth 20
if ($failedChecks.Count -ne 0) { exit 2 }
