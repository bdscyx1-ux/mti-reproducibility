param(
    [Parameter(Mandatory = $true)]
    [string]$ProjectRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Require-Condition {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw [System.InvalidOperationException]::new($Message) }
}

function Get-Sha256Lower {
    param([string]$Path)
    Require-Condition (Test-Path -LiteralPath $Path -PathType Leaf) "Required file is missing: $Path"
    return (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToLowerInvariant()
}

function Write-JsonExclusive {
    param([string]$Path, [object]$Value)
    Require-Condition (-not (Test-Path -LiteralPath $Path)) "Refusing to overwrite evidence: $Path"
    $parent = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent | Out-Null }
    $json = ($Value | ConvertTo-Json -Depth 100) + [Environment]::NewLine
    [IO.File]::WriteAllText($Path, $json, [Text.UTF8Encoding]::new($false))
}

function Set-Property {
    param([object]$Object, [string]$Name, [object]$Value)
    $Object | Add-Member -MemberType NoteProperty -Name $Name -Value $Value -Force
}

function Set-ManifestArtifact {
    param([object]$Manifest, [string]$Role, [string]$RelativePath, [string]$FullPath)
    $sha = Get-Sha256Lower -Path $FullPath
    $bytes = [int64](Get-Item -LiteralPath $FullPath).Length
    $matches = @($Manifest.artifacts | Where-Object { [string]$_.relativePath -ceq $RelativePath })
    if ($matches.Count -gt 0) {
        Require-Condition ($matches.Count -eq 1) "Manifest contains duplicate artifact path before update: $RelativePath"
        $matches[0].role = $Role
        $matches[0].sha256 = $sha
        $matches[0].bytes = $bytes
    } else {
        $Manifest.artifacts = @($Manifest.artifacts) + [pscustomobject][ordered]@{
            role = $Role
            relativePath = $RelativePath
            sha256 = $sha
            bytes = $bytes
        }
    }
}

$root = [IO.Path]::GetFullPath($ProjectRoot).TrimEnd([IO.Path]::DirectorySeparatorChar)
$corrigendumRoot = Join-Path $root 'Research/Verification/Gate14Re-ME/qualification-measured-root-binding-corrigendum-attempt-001'
$readinessRoot = Join-Path $root 'Research/Verification/Gate14Re-ME/qualification-execution-readiness-recheck-attempt-010'
$contractOldPath = Join-Path $root 'Research/Gate14Re-ME/Execution/v3/load-qualification-execution-contract.v3_4.json'
$contractNewPath = Join-Path $root 'Research/Gate14Re-ME/Execution/v3/load-qualification-execution-contract.v3_5.json'
$manifestOldPath = Join-Path $root 'Research/Gate14Re-ME/Execution/v3/load-qualification-current-implementation-manifest.v3_4.json'
$manifestNewPath = Join-Path $root 'Research/Gate14Re-ME/Execution/v3/load-qualification-current-implementation-manifest.v3_5.json'
$runnerRelative = 'Assets/_Scripts/Research/Editor/Gate14ReMELoadQualificationRunnerV2.cs'
$runnerPath = Join-Path $root $runnerRelative
$supervisorRelative = 'Research/Gate14Re-ME/Execution/v3/Run-Gate14ReMELoadQualification.v3_3.ps1'
$supervisorPath = Join-Path $root $supervisorRelative
$editorAssemblyRelative = 'Library/ScriptAssemblies/Assembly-CSharp-Editor.dll'
$editorAssemblyPath = Join-Path $root $editorAssemblyRelative
$runtimeAssemblyRelative = 'Library/ScriptAssemblies/Assembly-CSharp.dll'
$runtimeAssemblyPath = Join-Path $root $runtimeAssemblyRelative
$compileReceiptRelative = 'Research/Verification/Gate14Re-ME/qualification-measured-root-binding-corrigendum-attempt-001/unity-compile-identity-receipt.v1.json'
$compileReceiptPath = Join-Path $root $compileReceiptRelative
$knownAnswerRelative = 'Research/Verification/Gate14Re-ME/qualification-measured-root-binding-corrigendum-attempt-001/root-binding-known-answer.v1.json'
$knownAnswerPath = Join-Path $root $knownAnswerRelative
$compileScriptRelative = 'Research/Verification/Gate14Re-ME/qualification-measured-root-binding-corrigendum-attempt-001/Invoke-Gate14ReMERootBindingCompileV1.ps1'
$compileScriptPath = Join-Path $root $compileScriptRelative
$freezeScriptRelative = 'Research/Verification/Gate14Re-ME/qualification-measured-root-binding-corrigendum-attempt-001/Freeze-Gate14ReMERootBindingAndReadinessV1.ps1'
$freezeScriptPath = Join-Path $root $freezeScriptRelative
$statusV39Relative = 'Research/Gate14Re-ME/Gate14Re_ME_Status.v39.json'
$statusV39Path = Join-Path $root $statusV39Relative
$statusV40Path = Join-Path $root 'Research/Gate14Re-ME/Gate14Re_ME_Status.v40.json'
$failedAttempt004Relative = 'Research/Verification/Gate14Re-ME/load-qualification-execution-attempt-004/terminal-failure-receipt.v1.json'
$failedAttempt004Path = Join-Path $root $failedAttempt004Relative
$failedMeasuredRoot = Join-Path $root 'Research/PilotRuns/Gate14Re-ME/load-qualification/attempt-002'
$newMeasuredRoot = Join-Path $root 'Research/PilotRuns/Gate14Re-ME/load-qualification/attempt-003'
$newDeliveryRoot = Join-Path $root 'Research/Exports/Gate14Re-ME/load-qualification/attempt-003'

Require-Condition (Test-Path -LiteralPath $corrigendumRoot -PathType Container) 'Corrigendum root is missing.'
Require-Condition (-not (Test-Path -LiteralPath $readinessRoot)) 'Readiness attempt-010 already exists.'
Require-Condition (-not (Test-Path -LiteralPath $contractNewPath)) 'Contract v3.5 already exists.'
Require-Condition (-not (Test-Path -LiteralPath $manifestNewPath)) 'Manifest v3.5 already exists.'
Require-Condition (-not (Test-Path -LiteralPath $statusV40Path)) 'Status v40 already exists.'
Require-Condition ((Get-Sha256Lower -Path $contractOldPath) -ceq 'e3b519f226a3d24eb1d71927fe0cd6d4e16ba879d2c382b0203453a03ff55a85') 'Contract v3.4 drifted.'
Require-Condition ((Get-Sha256Lower -Path $manifestOldPath) -ceq '1e56697a40692ff76fc01273ec4e5b8b7953ea88dcfe228eeeb317d9705a69c1') 'Manifest v3.4 drifted.'
Require-Condition ((Get-Sha256Lower -Path $statusV39Path) -ceq '8c9f329c9106b31c768198833f49c004b87c6cc00c89cb9a9795e93b4d45f0b6') 'Status v39 drifted.'
Require-Condition ((Get-Sha256Lower -Path $failedAttempt004Path) -ceq '89ae588df381230399790bff540913294fab98532c276ff3048d7d21290b5ff8') 'Attempt-004 terminal failure receipt drifted.'
Require-Condition (Test-Path -LiteralPath $failedMeasuredRoot -PathType Container) 'Failed attempt-002 measured root is missing.'
Require-Condition (-not (Test-Path -LiteralPath $newMeasuredRoot)) 'Prospective attempt-003 measured root already exists.'
Require-Condition (-not (Test-Path -LiteralPath $newDeliveryRoot)) 'Prospective attempt-003 delivery root already exists.'
Require-Condition (@(Get-CimInstance Win32_Process -Filter "Name = 'Unity.exe'").Count -eq 0) 'Unity is active during offline freeze.'

$compileReceipt = Get-Content -LiteralPath $compileReceiptPath -Raw -Encoding UTF8 | ConvertFrom-Json -Depth 100 -DateKind String
$knownAnswer = Get-Content -LiteralPath $knownAnswerPath -Raw -Encoding UTF8 | ConvertFrom-Json -Depth 100 -DateKind String
Require-Condition ($compileReceipt.status -eq 'PASS_COMPILE_ONLY_NATURAL_EXIT' -and [bool]$compileReceipt.passed -and [int]$compileReceipt.unity.exitCode -eq 0 -and -not [bool]$compileReceipt.algorithmCodeInvoked) 'Compile-only receipt is not terminal PASS.'
Require-Condition ($knownAnswer.status -eq 'PASS_ROOT_BINDING_SCOPE_KNOWN_ANSWER' -and [bool]$knownAnswer.passed -and @($knownAnswer.cases | Where-Object { -not [bool]$_.passed }).Count -eq 0) 'Root-binding known-answer is not terminal PASS.'

$runnerSha = Get-Sha256Lower -Path $runnerPath
$supervisorSha = Get-Sha256Lower -Path $supervisorPath
$editorAssemblySha = Get-Sha256Lower -Path $editorAssemblyPath
$runtimeAssemblySha = Get-Sha256Lower -Path $runtimeAssemblyPath
Require-Condition ($runnerSha -ceq '21b677cbf277309a69fa51001d6f34e6e496f8e9abaae8c3bae19c85bf6c4952') 'Corrected RunnerV2 source drifted.'
Require-Condition ($supervisorSha -ceq '060d075103d6a7c654a3943863f1a173021a848cd9297dd9ec5860f0a138f1e4') 'Supervisor v3.3 drifted.'
Require-Condition ($editorAssemblySha -ceq [string]$compileReceipt.compiledAssemblies[0].sha256) 'Compiled editor assembly no longer matches the compile receipt.'
Require-Condition ($runtimeAssemblySha -ceq 'c21848ca1618dc010f52a1035489ac9347fe481735b362ee3ac8c8d938324bd1') 'Runtime assembly changed unexpectedly.'

$contract = Get-Content -LiteralPath $contractOldPath -Raw -Encoding UTF8 | ConvertFrom-Json -Depth 100 -DateKind String
$contract.revision = '3.5'
$contract.createdLocalDate = '2026-10-18'
$contract.entryPoint.supervisorRelativePath = $supervisorRelative
$contract.entryPoint.supervisorSha256 = $supervisorSha
$contract.entryPoint.supervisorRevision = '3.3'
$contract.entryPoint.runnerSha256 = $runnerSha
$contract.reservedRoots.qualificationMeasuredRootRelativePath = 'Research/PilotRuns/Gate14Re-ME/load-qualification/attempt-003'
$contract.reservedRoots.completePerObservationDeliveryRootRelativePath = 'Research/Exports/Gate14Re-ME/load-qualification/attempt-003'
Set-Property -Object $contract.currentAuthorization -Name 'measuredRootBindingCorrigendumAuthorized' -Value $true
Set-Property -Object $contract.currentAuthorization -Name 'compileOnlyUnityInvocationAuthorized' -Value $true
Set-Property -Object $contract.currentAuthorization -Name 'prospectiveAttempt003RootBindingUpdateAuthorized' -Value $true
$contract.activationRule = 'This v3.5 contract and supervisor v3.3 become active only through an exact-hash qualification execution authorization bound to a fresh attempt root. Each attempt remains zero-retry and zero-replacement; the user authorizes the external qualification repair loop to create a later fresh attempt only after freezing any technical failure.'
$contract.supersedes = [pscustomobject][ordered]@{
    relativePath = 'Research/Gate14Re-ME/Execution/v3/load-qualification-execution-contract.v3_4.json'
    sha256 = Get-Sha256Lower -Path $contractOldPath
    modifiedOrReclassified = $false
}
$contract.frozenBindings | Add-Member -MemberType NoteProperty -Name 'measuredRootBindingCompileReceipt' -Value ([pscustomobject][ordered]@{
    relativePath = $compileReceiptRelative
    sha256 = Get-Sha256Lower -Path $compileReceiptPath
}) -Force
Set-Property -Object $contract -Name 'measuredRootBindingCorrigendum' -Value ([pscustomobject][ordered]@{
    authorizationId = 'gate14re-me-qualification-closed-loop-until-execution-pass-2026-10-18'
    attemptId = 'qualification-measured-root-binding-corrigendum-attempt-001'
    userAuthorizationTextExact = '授权所有最短下一步直至qualification execution通过'
    retainedStatusV39RelativePath = $statusV39Relative
    retainedStatusV39Sha256 = Get-Sha256Lower -Path $statusV39Path
    retainedAttempt004FailureRelativePath = $failedAttempt004Relative
    retainedAttempt004FailureSha256 = Get-Sha256Lower -Path $failedAttempt004Path
    previousRunnerSha256 = 'e93cbf1ff3d0551daf927acca95b02dc839aa925275ba5d7a0c170b7c5206401'
    correctedRunnerSha256 = $runnerSha
    compileReceiptRelativePath = $compileReceiptRelative
    compileReceiptSha256 = Get-Sha256Lower -Path $compileReceiptPath
    knownAnswerRelativePath = $knownAnswerRelative
    knownAnswerSha256 = Get-Sha256Lower -Path $knownAnswerPath
    scientificDesignChanged = $false
    algorithmImplementationsChanged = $false
    scheduleChanged = $false
    sealedIdentityChanged = $false
    instrumentContractChanged = $false
    runnerMeasuredRootBindingChangedOnly = $true
    qualificationExecutionAuthorizedByThisContractAlone = $false
    formalCollectionAuthorized = $false
    formalAnalysisAuthorized = $false
    rankingAuthorized = $false
    winnerAdjudicationAuthorized = $false
})
Write-JsonExclusive -Path $contractNewPath -Value $contract
$contractNewSha = Get-Sha256Lower -Path $contractNewPath

$manifest = Get-Content -LiteralPath $manifestOldPath -Raw -Encoding UTF8 | ConvertFrom-Json -Depth 100 -DateKind String
$manifest.manifestRevision = '3.5'
$manifest.authorizationId = 'gate14re-me-qualification-closed-loop-until-execution-pass-2026-10-18'
Set-ManifestArtifact -Manifest $manifest -Role 'csharp-source-root-binding-corrected' -RelativePath $runnerRelative -FullPath $runnerPath
Set-ManifestArtifact -Manifest $manifest -Role 'compiled-editor-assembly-root-binding-corrected' -RelativePath $editorAssemblyRelative -FullPath $editorAssemblyPath
Set-ManifestArtifact -Manifest $manifest -Role 'compiled-runtime-assembly-unchanged' -RelativePath $runtimeAssemblyRelative -FullPath $runtimeAssemblyPath
Set-ManifestArtifact -Manifest $manifest -Role 'powershell-supervisor-root-attempt-003' -RelativePath $supervisorRelative -FullPath $supervisorPath
Set-ManifestArtifact -Manifest $manifest -Role 'machine-contract-root-binding-corrigendum' -RelativePath 'Research/Gate14Re-ME/Execution/v3/load-qualification-execution-contract.v3_5.json' -FullPath $contractNewPath
Set-ManifestArtifact -Manifest $manifest -Role 'root-binding-compile-receipt' -RelativePath $compileReceiptRelative -FullPath $compileReceiptPath
Set-ManifestArtifact -Manifest $manifest -Role 'root-binding-offline-known-answer' -RelativePath $knownAnswerRelative -FullPath $knownAnswerPath
Set-ManifestArtifact -Manifest $manifest -Role 'root-binding-compile-orchestrator' -RelativePath $compileScriptRelative -FullPath $compileScriptPath
Set-ManifestArtifact -Manifest $manifest -Role 'root-binding-freeze-orchestrator' -RelativePath $freezeScriptRelative -FullPath $freezeScriptPath
$manifest.compileIdentityProof = [pscustomobject][ordered]@{
    receiptRelativePath = $compileReceiptRelative
    receiptSha256 = Get-Sha256Lower -Path $compileReceiptPath
    status = 'PASS_COMPILE_ONLY_NATURAL_EXIT'
    unityInvocationCount = 1
    executeMethod = $null
    naturalExit = $true
    exitCode = 0
    algorithmCodeInvoked = $false
    qualificationObservationProduced = $false
    editorAssemblySha256 = $editorAssemblySha
    runtimeAssemblySha256 = $runtimeAssemblySha
}
Set-Property -Object $manifest -Name 'measuredRootBindingCorrigendum' -Value ([pscustomobject][ordered]@{
    authorizationId = 'gate14re-me-qualification-closed-loop-until-execution-pass-2026-10-18'
    attemptId = 'qualification-measured-root-binding-corrigendum-attempt-001'
    previousManifestRelativePath = 'Research/Gate14Re-ME/Execution/v3/load-qualification-current-implementation-manifest.v3_4.json'
    previousManifestSha256 = Get-Sha256Lower -Path $manifestOldPath
    retainedAttempt004FailureRelativePath = $failedAttempt004Relative
    retainedAttempt004FailureSha256 = Get-Sha256Lower -Path $failedAttempt004Path
    runnerV2Sha256 = $runnerSha
    compiledEditorAssemblySha256 = $editorAssemblySha
    compiledRuntimeAssemblySha256 = $runtimeAssemblySha
    supervisorV33Sha256 = $supervisorSha
    executionContractV35Sha256 = $contractNewSha
    prospectiveMeasuredRootRelativePath = 'Research/PilotRuns/Gate14Re-ME/load-qualification/attempt-003'
    prospectiveDeliveryRootRelativePath = 'Research/Exports/Gate14Re-ME/load-qualification/attempt-003'
    priorFailedRootsRetained = $true
    newRootsCreated = $false
    scientificDesignChanged = $false
    algorithmImplementationsChanged = $false
    qualificationExecutionPerformed = $false
    formalCollectionAuthorized = $false
    formalAnalysisAuthorized = $false
    rankingAuthorized = $false
    winnerAdjudicationAuthorized = $false
})
$manifest.retainedFailures = @($manifest.retainedFailures) + [pscustomobject][ordered]@{
    relativePath = $failedAttempt004Relative
    sha256 = Get-Sha256Lower -Path $failedAttempt004Path
    status = 'FAILED_CLOSED_FROZEN_RUNNER_MEASURED_ROOT_BINDING_MISMATCH'
    modifiedOrReclassified = $false
}
Write-JsonExclusive -Path $manifestNewPath -Value $manifest
$manifestNewSha = Get-Sha256Lower -Path $manifestNewPath

New-Item -ItemType Directory -Path $readinessRoot | Out-Null
$authorizationReceiptPath = Join-Path $readinessRoot 'authorization-receipt.v1.json'
Write-JsonExclusive -Path $authorizationReceiptPath -Value ([ordered]@{
    schema = 'gate14re-me-qualification-closed-loop-authorization-receipt-v1'
    studyId = 'Gate14Re-ME'
    authorizationId = 'gate14re-me-qualification-closed-loop-until-execution-pass-2026-10-18'
    status = 'AUTHORIZED_ALL_SHORTEST_QUALIFICATION_STEPS_UNTIL_EXECUTION_PASS'
    userAuthorizationTextExact = '授权所有最短下一步直至qualification execution通过'
    withinAttemptRetryResumeTopUpMergeSkipReorderOrParallelAuthorized = $false
    technicalRepairAndFreshAttemptLoopAuthorized = $true
    qualificationExecutionAuthorized = $true
    formalCollectionAuthorized = $false
    formalAnalysisAuthorized = $false
    rankingAuthorized = $false
    weightingAuthorized = $false
    winnerAdjudicationAuthorized = $false
    recordedAtUtc = [DateTime]::UtcNow.ToString('o')
})

$contractCheck = Get-Content -LiteralPath $contractNewPath -Raw -Encoding UTF8 | ConvertFrom-Json -Depth 100 -DateKind String
$manifestCheck = Get-Content -LiteralPath $manifestNewPath -Raw -Encoding UTF8 | ConvertFrom-Json -Depth 100 -DateKind String
$manifestIndex = @{}
foreach ($artifact in @($manifestCheck.artifacts)) {
    $path = [string]$artifact.relativePath
    Require-Condition (-not $manifestIndex.ContainsKey($path)) "Manifest v3.5 contains duplicate artifact path: $path"
    $manifestIndex[$path] = [string]$artifact.sha256
}
foreach ($property in $contractCheck.frozenBindings.PSObject.Properties) {
    $binding = $property.Value
    $full = Join-Path $root ([string]$binding.relativePath)
    Require-Condition ((Get-Sha256Lower -Path $full) -ceq [string]$binding.sha256) "Contract binding drifted: $($property.Name)"
    Require-Condition ($manifestIndex.ContainsKey([string]$binding.relativePath) -and $manifestIndex[[string]$binding.relativePath] -ceq [string]$binding.sha256) "Manifest omits contract binding: $($property.Name)"
}
foreach ($required in @(
    [pscustomobject]@{ path = $runnerRelative; sha = $runnerSha },
    [pscustomobject]@{ path = $supervisorRelative; sha = $supervisorSha },
    [pscustomobject]@{ path = 'Research/Gate14Re-ME/Execution/v3/load-qualification-execution-contract.v3_5.json'; sha = $contractNewSha },
    [pscustomobject]@{ path = $editorAssemblyRelative; sha = $editorAssemblySha },
    [pscustomobject]@{ path = $runtimeAssemblyRelative; sha = $runtimeAssemblySha }
)) {
    Require-Condition ($manifestIndex.ContainsKey($required.path) -and $manifestIndex[$required.path] -ceq $required.sha) "Manifest required binding failed: $($required.path)"
}
Require-Condition ([string]$contractCheck.reservedRoots.qualificationMeasuredRootRelativePath -ceq 'Research/PilotRuns/Gate14Re-ME/load-qualification/attempt-003') 'Contract measured root mismatch.'
Require-Condition ([string]$contractCheck.reservedRoots.completePerObservationDeliveryRootRelativePath -ceq 'Research/Exports/Gate14Re-ME/load-qualification/attempt-003') 'Contract delivery root mismatch.'
Require-Condition ([int]$contractCheck.expectedCardinalities.totalSuperblocks -eq 162 -and [int]$contractCheck.expectedCardinalities.freshAlgorithmProcesses -eq 972 -and [int]$contractCheck.expectedCardinalities.expectedTotalUnityProcessesWithoutFailure -eq 1147 -and [int]$contractCheck.expectedCardinalities.supervisorFinalProcessOrdinal -eq 1147) 'Contract cardinalities changed.'

$scheduleBinding = $contractCheck.frozenBindings.schedule
$schedulePath = Join-Path $root ([string]$scheduleBinding.relativePath)
$rows = @(Get-Content -LiteralPath $schedulePath -Encoding UTF8 | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | ForEach-Object { $_ | ConvertFrom-Json -Depth 100 -DateKind String })
Require-Condition ($rows.Count -eq 162) 'Schedule row count is not 162.'
Require-Condition (@($rows | Where-Object { $null -ne $_.replacement }).Count -eq 0) 'Schedule contains a replacement asset.'
Require-Condition (@($rows | Where-Object { @($_.algorithmOrder).Count -ne 6 }).Count -eq 0) 'Schedule contains a non-six-lane row.'
Require-Condition (-not (Test-Path -LiteralPath $newMeasuredRoot) -and -not (Test-Path -LiteralPath $newDeliveryRoot)) 'Prospective roots changed during readiness validation.'
Require-Condition (@(Get-CimInstance Win32_Process -Filter "Name = 'Unity.exe'").Count -eq 0) 'Unity became active during readiness validation.'

$terminalReceiptPath = Join-Path $readinessRoot 'terminal-readiness-receipt.v1.json'
Write-JsonExclusive -Path $terminalReceiptPath -Value ([ordered]@{
    schema = 'gate14re-me-qualification-execution-readiness-recheck-v1'
    studyId = 'Gate14Re-ME'
    authorizationId = 'gate14re-me-qualification-closed-loop-until-execution-pass-2026-10-18'
    attemptId = 'qualification-execution-readiness-recheck-attempt-010'
    status = 'PASS_EXACT_HASH_READINESS_ROOT_BINDING_CORRECTED_ATTEMPT_003_RESERVED'
    passed = $true
    noUnity = $true
    measuredRootCreated = $false
    deliveryRootCreated = $false
    runnerSha256 = $runnerSha
    supervisorSha256 = $supervisorSha
    executionContractSha256 = $contractNewSha
    implementationManifestSha256 = $manifestNewSha
    compiledEditorAssemblySha256 = $editorAssemblySha
    compiledRuntimeAssemblySha256 = $runtimeAssemblySha
    scheduleSha256 = Get-Sha256Lower -Path $schedulePath
    scheduleRows = $rows.Count
    algorithmLanes = 972
    expectedFreshUnityProcesses = 1147
    zeroReplacementFailStop = $true
    strictSerialExecution = $true
    completePerObservationDeliveryRequired = $true
    technicalRepairAndFreshAttemptLoopAuthorized = $true
    withinAttemptRetryResumeTopUpMergeSkipReorderOrParallelAuthorized = $false
    formalCollectionAuthorized = $false
    formalAnalysisAuthorized = $false
    rankingWeightingOrWinnerAdjudicationAuthorized = $false
    completedAtUtc = [DateTime]::UtcNow.ToString('o')
})

$freezeManifestPath = Join-Path $readinessRoot 'freeze-manifest.v1.json'
$frozenFiles = @(
    $authorizationReceiptPath,
    $terminalReceiptPath,
    $runnerPath,
    $supervisorPath,
    $contractNewPath,
    $manifestNewPath,
    $compileReceiptPath,
    $knownAnswerPath,
    $compileScriptPath,
    $freezeScriptPath,
    $statusV39Path,
    $failedAttempt004Path
)
$rootUri = [Uri]::new($root.TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar)
$freezeEntries = @($frozenFiles | ForEach-Object {
    [ordered]@{
        relativePath = ([Uri]::UnescapeDataString($rootUri.MakeRelativeUri([Uri]::new([IO.Path]::GetFullPath($_))).ToString())).Replace('\', '/')
        sha256 = Get-Sha256Lower -Path $_
        bytes = [int64](Get-Item -LiteralPath $_).Length
    }
})
Write-JsonExclusive -Path $freezeManifestPath -Value ([ordered]@{
    schema = 'gate14re-me-qualification-execution-readiness-recheck-freeze-manifest-v1'
    studyId = 'Gate14Re-ME'
    attemptId = 'qualification-execution-readiness-recheck-attempt-010'
    status = 'FROZEN_TERMINAL_READINESS_PASS'
    files = $freezeEntries
    createdAtUtc = [DateTime]::UtcNow.ToString('o')
})

$statusV40 = [ordered]@{
    schema = 'gate14re-me-status-v40'
    studyId = 'Gate14Re-ME'
    status = 'ROOT_BINDING_CORRIGENDUM_AND_EXECUTION_READINESS_PASS_QUALIFICATION_EXECUTION_AUTHORIZED'
    version = 40
    updatedAtUtc = [DateTime]::UtcNow.ToString('o')
    previousVersionedStatus = [ordered]@{ relativePath = $statusV39Relative; sha256 = Get-Sha256Lower -Path $statusV39Path; retained = $true; reclassified = $false }
    retainedFailedExecution = [ordered]@{ attemptId = 'load-qualification-execution-attempt-004'; terminalFailureReceiptRelativePath = $failedAttempt004Relative; terminalFailureReceiptSha256 = Get-Sha256Lower -Path $failedAttempt004Path; failedMeasuredRootRelativePath = 'Research/PilotRuns/Gate14Re-ME/load-qualification/attempt-002'; modifiedOrReclassified = $false }
    rootBindingCorrigendum = [ordered]@{ attemptId = 'qualification-measured-root-binding-corrigendum-attempt-001'; runnerSha256 = $runnerSha; supervisorSha256 = $supervisorSha; executionContractRelativePath = 'Research/Gate14Re-ME/Execution/v3/load-qualification-execution-contract.v3_5.json'; executionContractSha256 = $contractNewSha; implementationManifestRelativePath = 'Research/Gate14Re-ME/Execution/v3/load-qualification-current-implementation-manifest.v3_5.json'; implementationManifestSha256 = $manifestNewSha; compileReceiptRelativePath = $compileReceiptRelative; compileReceiptSha256 = Get-Sha256Lower -Path $compileReceiptPath; passed = $true }
    executionReadiness = [ordered]@{ attemptId = 'qualification-execution-readiness-recheck-attempt-010'; terminalReceiptRelativePath = 'Research/Verification/Gate14Re-ME/qualification-execution-readiness-recheck-attempt-010/terminal-readiness-receipt.v1.json'; terminalReceiptSha256 = Get-Sha256Lower -Path $terminalReceiptPath; freezeManifestRelativePath = 'Research/Verification/Gate14Re-ME/qualification-execution-readiness-recheck-attempt-010/freeze-manifest.v1.json'; freezeManifestSha256 = Get-Sha256Lower -Path $freezeManifestPath; passed = $true }
    nextExecution = [ordered]@{ evidenceAttemptId = 'load-qualification-execution-attempt-005'; measuredRootRelativePath = 'Research/PilotRuns/Gate14Re-ME/load-qualification/attempt-003'; deliveryRootRelativePath = 'Research/Exports/Gate14Re-ME/load-qualification/attempt-003'; expectedFreshUnityProcesses = 1147; strictSerial = $true; zeroReplacementFailStop = $true; withinAttemptRetryResumeTopUpMergeSkipReorderOrParallelAuthorized = $false }
    authorizationState = [ordered]@{ technicalRepairAndFreshAttemptLoopAuthorizedUntilQualificationExecutionPass = $true; qualificationExecutionAuthorized = $true; formalCollectionAuthorized = $false; formalAnalysisAuthorized = $false; rankingAuthorized = $false; weightingAuthorized = $false; winnerAdjudicationAuthorized = $false }
    nextRequiredAction = 'Create one exact-hash execution authorization for the fresh attempt-003 measured/delivery roots and run the frozen qualification supervisor. Freeze any technical failure before the shortest prospective repair and a later fresh attempt; stop the loop only at qualification execution terminal PASS.'
}
Write-JsonExclusive -Path $statusV40Path -Value $statusV40

foreach ($path in @($runnerPath, $supervisorPath, $contractNewPath, $manifestNewPath, $statusV40Path, $authorizationReceiptPath, $terminalReceiptPath, $freezeManifestPath, $compileReceiptPath, $knownAnswerPath, $compileScriptPath, $freezeScriptPath)) {
    (Get-Item -LiteralPath $path).IsReadOnly = $true
}

[pscustomobject][ordered]@{
    status = 'PASS_ROOT_BINDING_CORRIGENDUM_AND_READINESS'
    runnerSha256 = $runnerSha
    supervisorSha256 = $supervisorSha
    contractV35Sha256 = $contractNewSha
    manifestV35Sha256 = $manifestNewSha
    terminalReadinessReceiptSha256 = Get-Sha256Lower -Path $terminalReceiptPath
    readinessFreezeManifestSha256 = Get-Sha256Lower -Path $freezeManifestPath
    statusV40Sha256 = Get-Sha256Lower -Path $statusV40Path
} | ConvertTo-Json -Depth 10 -Compress
