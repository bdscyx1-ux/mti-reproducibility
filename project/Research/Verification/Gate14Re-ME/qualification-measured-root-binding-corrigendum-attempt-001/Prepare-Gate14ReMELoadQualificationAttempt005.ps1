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

function Get-TextSha256Lower {
    param([string]$Text)
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return [Convert]::ToHexString($sha.ComputeHash([Text.UTF8Encoding]::new($false).GetBytes($Text))).ToLowerInvariant() }
    finally { $sha.Dispose() }
}

function Write-JsonExclusive {
    param([string]$Path, [object]$Value)
    Require-Condition (-not (Test-Path -LiteralPath $Path)) "Refusing to overwrite evidence: $Path"
    [IO.File]::WriteAllText($Path, (($Value | ConvertTo-Json -Depth 100) + [Environment]::NewLine), [Text.UTF8Encoding]::new($false))
}

$root = [IO.Path]::GetFullPath($ProjectRoot).TrimEnd([IO.Path]::DirectorySeparatorChar)
$attemptId = 'load-qualification-execution-attempt-005'
$evidenceRoot = Join-Path $root 'Research/Verification/Gate14Re-ME/load-qualification-execution-attempt-005'
$measuredRoot = Join-Path $root 'Research/PilotRuns/Gate14Re-ME/load-qualification/attempt-003'
$deliveryRoot = Join-Path $root 'Research/Exports/Gate14Re-ME/load-qualification/attempt-003'
$statusPath = Join-Path $root 'Research/Gate14Re-ME/Gate14Re_ME_Status.v40.json'
$readinessReceiptPath = Join-Path $root 'Research/Verification/Gate14Re-ME/qualification-execution-readiness-recheck-attempt-010/terminal-readiness-receipt.v1.json'
$readinessFreezePath = Join-Path $root 'Research/Verification/Gate14Re-ME/qualification-execution-readiness-recheck-attempt-010/freeze-manifest.v1.json'
$supervisorPath = Join-Path $root 'Research/Gate14Re-ME/Execution/v3/Run-Gate14ReMELoadQualification.v3_3.ps1'
$manifestPath = Join-Path $root 'Research/Gate14Re-ME/Execution/v3/load-qualification-current-implementation-manifest.v3_5.json'
$contractPath = Join-Path $root 'Research/Gate14Re-ME/Execution/v3/load-qualification-execution-contract.v3_5.json'
$launcherPath = Join-Path $root 'Research/Verification/Gate14Re-ME/qualification-measured-root-binding-corrigendum-attempt-001/Invoke-Gate14ReMELoadQualificationAttempt005.ps1'
$preparationPath = Join-Path $root 'Research/Verification/Gate14Re-ME/qualification-measured-root-binding-corrigendum-attempt-001/Prepare-Gate14ReMELoadQualificationAttempt005.ps1'
$hostPath = 'C:/Users/bdscy/.cache/codex-runtimes/codex-primary-runtime/dependencies/native/powershell/pwsh.exe'
$hostSha = '362a356ce7f0940ec74f73a8fc2c990a2cc24a38a11c90bbd8eca947110ad139'

Require-Condition (-not (Test-Path -LiteralPath $evidenceRoot)) 'Execution evidence attempt-005 already exists.'
Require-Condition (-not (Test-Path -LiteralPath $measuredRoot)) 'Measured root attempt-003 already exists.'
Require-Condition (-not (Test-Path -LiteralPath $deliveryRoot)) 'Delivery root attempt-003 already exists.'
Require-Condition ((Get-Sha256Lower -Path $statusPath) -ceq '6dcb4d2095382b3ad31911dce2b872e022d95ee6f57952e2edf2f77182ea4163') 'Status v40 drifted.'
Require-Condition ((Get-Sha256Lower -Path $readinessReceiptPath) -ceq '593d34d011409541cb1915ff846b032e1a96c5f6ed7a5b9146b58ae1e71734f8') 'Readiness receipt drifted.'
Require-Condition ((Get-Sha256Lower -Path $readinessFreezePath) -ceq 'f6525264b1eab6656fc44e023562fa46ae3fe1a784195d8aae31ea030679e360') 'Readiness freeze manifest drifted.'
Require-Condition ((Get-Sha256Lower -Path $supervisorPath) -ceq '060d075103d6a7c654a3943863f1a173021a848cd9297dd9ec5860f0a138f1e4') 'Supervisor v3.3 drifted.'
Require-Condition ((Get-Sha256Lower -Path $manifestPath) -ceq '7ac832ef41f69137e763244b97c210dd0a57458c56622019b51384fd401ff742') 'Manifest v3.5 drifted.'
Require-Condition ((Get-Sha256Lower -Path $contractPath) -ceq '83586aa1eaffc73b26ae1d59670ff4984df07aa02a30f857969e6ca14c2a869e') 'Contract v3.5 drifted.'
Require-Condition ((Get-Sha256Lower -Path $hostPath) -ceq $hostSha) 'PowerShell host drifted.'
Require-Condition (@(Get-CimInstance Win32_Process -Filter "Name = 'Unity.exe'").Count -eq 0) 'Unity is active.'
Require-Condition (@(Get-CimInstance Win32_Process | Where-Object { $_.Name -eq 'pwsh.exe' -and [string]$_.CommandLine -like '*Run-Gate14ReMELoadQualification.v3_3.ps1*' }).Count -eq 0) 'A matching supervisor is active.'

New-Item -ItemType Directory -Path $evidenceRoot | Out-Null
$authorizationId = 'gate14re-me-load-qualification-execution-attempt-005-' + [Guid]::NewGuid().ToString()
$authorizationNonce = [Guid]::NewGuid().ToString()
$authorizationPath = Join-Path $evidenceRoot 'execution-authorization.v1.json'
$authorization = [ordered]@{
    schema = 'gate14re-me-load-qualification-execution-authorization-v1'
    studyId = 'Gate14Re-ME'
    protocolId = 'gate14re-me-load-qualification-v1'
    designId = 'gate14re-me-load-qualification-planning-v2'
    authorizationId = $authorizationId
    authorizationNonce = $authorizationNonce
    attemptId = $attemptId
    status = 'AUTHORIZED_LOAD_QUALIFICATION_EXECUTION'
    authorizedAtUtc = [DateTime]::UtcNow.ToString('o')
    authorizationSource = 'direct user authorization of all shortest qualification steps until qualification execution passes'
    userAuthorizationTextExact = '授权所有最短下一步直至qualification execution通过'
    authoritativeReadinessStatusRelativePath = 'Research/Gate14Re-ME/Gate14Re_ME_Status.v40.json'
    authoritativeReadinessStatusSha256 = Get-Sha256Lower -Path $statusPath
    authoritativeReadinessReceiptRelativePath = 'Research/Verification/Gate14Re-ME/qualification-execution-readiness-recheck-attempt-010/terminal-readiness-receipt.v1.json'
    authoritativeReadinessReceiptSha256 = Get-Sha256Lower -Path $readinessReceiptPath
    authoritativeReadinessFreezeManifestRelativePath = 'Research/Verification/Gate14Re-ME/qualification-execution-readiness-recheck-attempt-010/freeze-manifest.v1.json'
    authoritativeReadinessFreezeManifestSha256 = Get-Sha256Lower -Path $readinessFreezePath
    qualificationInputGenerationAuthorized = $true
    qualificationRootCreationAuthorized = $true
    compileOrUnityExecutionAuthorized = $true
    qualificationExecutionAuthorized = $true
    deliveryConstructionAuthorized = $true
    technicalRepairAndFreshAttemptLoopAuthorized = $true
    formalCollectionAuthorized = $false
    formalAnalysisAuthorized = $false
    crossAlgorithmEffectsAuthorized = $false
    rankingAuthorized = $false
    weightingAuthorized = $false
    winnerAdjudicationAuthorized = $false
    measuredRootRelativePath = 'Research/PilotRuns/Gate14Re-ME/load-qualification/attempt-003'
    deliveryRootRelativePath = 'Research/Exports/Gate14Re-ME/load-qualification/attempt-003'
    supervisorRelativePath = 'Research/Gate14Re-ME/Execution/v3/Run-Gate14ReMELoadQualification.v3_3.ps1'
    supervisorSha256 = Get-Sha256Lower -Path $supervisorPath
    implementationManifestRelativePath = 'Research/Gate14Re-ME/Execution/v3/load-qualification-current-implementation-manifest.v3_5.json'
    implementationManifestSha256 = Get-Sha256Lower -Path $manifestPath
    executionContractRelativePath = 'Research/Gate14Re-ME/Execution/v3/load-qualification-execution-contract.v3_5.json'
    executionContractSha256 = Get-Sha256Lower -Path $contractPath
    scheduleRelativePath = 'Research/Verification/Gate14Re-ME/qualification-planning-asset-generation-v2-attempt-001/planning-assets/schedule/formal-qualification-williams-schedule.v1.jsonl'
    scheduleSha256 = '328301be5b496a794b67962693183242286d22bc6030db6c746daf7873582471'
    powerShellHostRuntime = [ordered]@{ executablePath = $hostPath; sha256 = $hostSha; version = '7.6.5' }
    strictSerialFreshUnityProcessesAuthorized = 1147
    zeroReplacementFailStop = $true
    retryResumeTopUpMergeSkipReorderOrParallelAuthorized = $false
    automaticFreshAttemptAfterFrozenTechnicalFailureAuthorized = $true
    qualificationInputGenerationAlreadyFrozen = $true
    qualificationInputRegenerationPerformedByThisAttempt = $false
    sealedIdentityMappingMayBeOpened = $false
}
Write-JsonExclusive -Path $authorizationPath -Value $authorization
$authorizationSha = Get-Sha256Lower -Path $authorizationPath

$stageContractPath = Join-Path $evidenceRoot 'stage-contract.v1.json'
Write-JsonExclusive -Path $stageContractPath -Value ([ordered]@{
    schema = 'gate14re-me-load-qualification-execution-attempt-005-stage-contract-v1'
    studyId = 'Gate14Re-ME'
    authorizationId = $authorizationId
    attemptId = $attemptId
    status = 'FROZEN_QUALIFICATION_ONLY_EXECUTION_BOUNDARY'
    measuredRoot = 'Research/PilotRuns/Gate14Re-ME/load-qualification/attempt-003'
    deliveryRoot = 'Research/Exports/Gate14Re-ME/load-qualification/attempt-003'
    expectedFreshUnityProcesses = 1147
    strictSerial = $true
    zeroReplacementFailStop = $true
    retryResumeTopUpMergeSkipReorderOrParallelWithinAttempt = $false
    completePerObservationRawDeliveryRequired = $true
    formalCollectionAuthorized = $false
    formalAnalysisAuthorized = $false
    rankingWeightingOrWinnerAdjudicationAuthorized = $false
    createdAtUtc = [DateTime]::UtcNow.ToString('o')
})

$prelaunchAuditPath = Join-Path $evidenceRoot 'prelaunch-audit.v1.json'
$driveId = [IO.Path]::GetPathRoot($measuredRoot).TrimEnd('\')
$drive = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='$driveId'"
Write-JsonExclusive -Path $prelaunchAuditPath -Value ([ordered]@{
    schema = 'gate14re-me-load-qualification-prelaunch-audit-v1'
    studyId = 'Gate14Re-ME'
    authorizationId = $authorizationId
    attemptId = $attemptId
    status = 'PASS_PRELAUNCH_ROOTS_ABSENT_EXACT_HASH_CHAIN_NO_ACTIVE_UNITY'
    passed = $true
    measuredRootAbsent = -not (Test-Path -LiteralPath $measuredRoot)
    deliveryRootAbsent = -not (Test-Path -LiteralPath $deliveryRoot)
    activeUnityCount = @(Get-CimInstance Win32_Process -Filter "Name = 'Unity.exe'").Count
    activeMatchingSupervisorCount = @(Get-CimInstance Win32_Process | Where-Object { $_.Name -eq 'pwsh.exe' -and [string]$_.CommandLine -like '*Run-Gate14ReMELoadQualification.v3_3.ps1*' }).Count
    freeBytes = [int64]$drive.FreeSpace
    requiredFrozenReservationBytes = 154618822656
    statusV40Sha256 = Get-Sha256Lower -Path $statusPath
    readinessReceiptSha256 = Get-Sha256Lower -Path $readinessReceiptPath
    readinessFreezeManifestSha256 = Get-Sha256Lower -Path $readinessFreezePath
    supervisorSha256 = Get-Sha256Lower -Path $supervisorPath
    implementationManifestSha256 = Get-Sha256Lower -Path $manifestPath
    executionContractSha256 = Get-Sha256Lower -Path $contractPath
    executionAuthorizationSha256 = $authorizationSha
    auditedAtUtc = [DateTime]::UtcNow.ToString('o')
})
Require-Condition ([int64]$drive.FreeSpace -ge 154618822656) 'Free space is below the frozen combined reservation.'

$planningAssets = 'H:/DDM_Final_Project/Research/Verification/Gate14Re-ME/qualification-planning-asset-generation-v2-attempt-001/planning-assets-freeze-manifest.v1.json'
$resourceBudget = 'H:/DDM_Final_Project/Research/Gate14Re-ME/Execution/v1/load-qualification-resource-budget.v1.json'
$fairness = 'H:/DDM_Final_Project/Research/Gate14Re-ME/Execution/v1/six-algorithm-fairness-binding.v1.json'
$schedule = 'H:/DDM_Final_Project/Research/Verification/Gate14Re-ME/qualification-planning-asset-generation-v2-attempt-001/planning-assets/schedule/formal-qualification-williams-schedule.v1.jsonl'
$outputSchema = 'H:/DDM_Final_Project/Research/Gate14Re-ME/Execution/v3/load-qualification-output-schema.v3.json'
$instrumentContract = 'H:/DDM_Final_Project/Research/Gate14Re-ME/Execution/v3/load-qualification-instrument-contract.v3.json'
$d3Contract = 'H:/DDM_Final_Project/Research/Gate14Re-ME/Execution/v3/d3-cumulative-managed-allocation-contract.qualified.v1.json'
$parquetManifest = 'H:/DDM_Final_Project/Research/Gate14Re-ME/Runtime/v1/typed-parquet-runtime-manifest.v1.json'
$structuralTool = 'H:/DDM_Final_Project/Research/Gate14Re-ME/Tools/gate14re_me_qualification_structural_v3_1.py'
$deliveryTool = 'H:/DDM_Final_Project/Research/Gate14Re-ME/Tools/gate14re_me_qualification_delivery_v2_2.py'
$identityRule = 'H:/DDM_Final_Project/Research/Verification/Gate14Re-ME/unity-executable-identity-rule-offline-adjudication-attempt-005/trusted-launch-identity-rule.v1.json'
$timestampComparator = 'H:/DDM_Final_Project/Research/Verification/Gate14Re-ME/unity-trusted-identity-timestamp-comparator-corrigendum-attempt-007/Gate14ReMETrustedTimestampComparatorV1.ps1'
$python = 'C:/Users/bdscy/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe'
$unity = 'H:/UnityEditor/2022.3.30f1c1/Editor/Unity.exe'

$arguments = @(
    '-NoLogo','-NoProfile','-NonInteractive','-File',$supervisorPath.Replace('\','/'),
    '-ProjectRoot',$root.Replace('\','/'),
    '-MeasuredRoot',$measuredRoot.Replace('\','/'),
    '-DeliveryRoot',$deliveryRoot.Replace('\','/'),
    '-ExecutionAuthorization',$authorizationPath.Replace('\','/'),'-ExecutionAuthorizationSha256',$authorizationSha,
    '-ImplementationManifest',$manifestPath.Replace('\','/'),'-ImplementationManifestSha256',(Get-Sha256Lower -Path $manifestPath),
    '-ExecutionContract',$contractPath.Replace('\','/'),'-ExecutionContractSha256',(Get-Sha256Lower -Path $contractPath),
    '-PlanningAssetsManifest',$planningAssets,'-PlanningAssetsManifestSha256',(Get-Sha256Lower -Path $planningAssets),
    '-ResourceBudget',$resourceBudget,'-ResourceBudgetSha256',(Get-Sha256Lower -Path $resourceBudget),
    '-FairnessBinding',$fairness,'-FairnessBindingSha256',(Get-Sha256Lower -Path $fairness),
    '-Schedule',$schedule,'-ScheduleSha256',(Get-Sha256Lower -Path $schedule),
    '-OutputSchema',$outputSchema,'-OutputSchemaSha256',(Get-Sha256Lower -Path $outputSchema),
    '-InstrumentContract',$instrumentContract,'-InstrumentContractSha256',(Get-Sha256Lower -Path $instrumentContract),
    '-D3Contract',$d3Contract,'-D3ContractSha256',(Get-Sha256Lower -Path $d3Contract),
    '-TypedParquetRuntimeManifest',$parquetManifest,'-TypedParquetRuntimeManifestSha256',(Get-Sha256Lower -Path $parquetManifest),
    '-StructuralTool',$structuralTool,'-StructuralToolSha256',(Get-Sha256Lower -Path $structuralTool),
    '-DeliveryTool',$deliveryTool,'-DeliveryToolSha256',(Get-Sha256Lower -Path $deliveryTool),
    '-TrustedIdentityRule',$identityRule,'-TrustedIdentityRuleSha256',(Get-Sha256Lower -Path $identityRule),
    '-TimestampComparator',$timestampComparator,'-TimestampComparatorSha256',(Get-Sha256Lower -Path $timestampComparator),
    '-PythonExecutable',$python,'-PythonExecutableSha256',(Get-Sha256Lower -Path $python),
    '-UnityExecutable',$unity,'-UnityExecutableSha256',(Get-Sha256Lower -Path $unity)
)
$canonicalArguments = $arguments | ConvertTo-Json -Compress
$launchContractPath = Join-Path $evidenceRoot 'launch-contract.v1.json'
Write-JsonExclusive -Path $launchContractPath -Value ([ordered]@{
    schema = 'gate14re-me-load-qualification-execution-attempt-005-launch-contract-v1'
    studyId = 'Gate14Re-ME'
    authorizationId = $authorizationId
    attemptId = $attemptId
    status = 'FROZEN_EXTERNAL_LAUNCH_CONTRACT'
    createdAtUtc = [DateTime]::UtcNow.ToString('o')
    executable = [ordered]@{ path = $hostPath; sha256 = $hostSha; version = '7.6.5' }
    argumentVectorCanonicalSerialization = 'JSON_UTF8_NO_BOM_COMPRESSED'
    argumentVectorSha256 = Get-TextSha256Lower -Text $canonicalArguments
    argumentVector = $arguments
    argumentCount = $arguments.Count
    projectRoot = $root.Replace('\','/')
    measuredRoot = $measuredRoot.Replace('\','/')
    deliveryRoot = $deliveryRoot.Replace('\','/')
    executionAuthorization = [ordered]@{ relativePath = 'Research/Verification/Gate14Re-ME/load-qualification-execution-attempt-005/execution-authorization.v1.json'; sha256 = $authorizationSha }
    stageContract = [ordered]@{ relativePath = 'Research/Verification/Gate14Re-ME/load-qualification-execution-attempt-005/stage-contract.v1.json'; sha256 = Get-Sha256Lower -Path $stageContractPath }
    prelaunchAudit = [ordered]@{ relativePath = 'Research/Verification/Gate14Re-ME/load-qualification-execution-attempt-005/prelaunch-audit.v1.json'; sha256 = Get-Sha256Lower -Path $prelaunchAuditPath }
    executionContract = [ordered]@{ relativePath = 'Research/Gate14Re-ME/Execution/v3/load-qualification-execution-contract.v3_5.json'; sha256 = Get-Sha256Lower -Path $contractPath }
    implementationManifest = [ordered]@{ relativePath = 'Research/Gate14Re-ME/Execution/v3/load-qualification-current-implementation-manifest.v3_5.json'; sha256 = Get-Sha256Lower -Path $manifestPath }
    launcher = [ordered]@{ relativePath = 'Research/Verification/Gate14Re-ME/qualification-measured-root-binding-corrigendum-attempt-001/Invoke-Gate14ReMELoadQualificationAttempt005.ps1'; sha256 = Get-Sha256Lower -Path $launcherPath }
    stdoutRelativePath = 'Research/Verification/Gate14Re-ME/load-qualification-execution-attempt-005/supervisor.stdout.log'
    stderrRelativePath = 'Research/Verification/Gate14Re-ME/load-qualification-execution-attempt-005/supervisor.stderr.log'
    workingDirectory = $root.Replace('\','/')
    windowStyle = 'Hidden'
    waitForCompletionAtLaunch = $false
    signalOrForcedTerminationAuthorized = $false
})

foreach ($path in @($authorizationPath, $stageContractPath, $prelaunchAuditPath, $launchContractPath, $launcherPath, $preparationPath)) { (Get-Item -LiteralPath $path).IsReadOnly = $true }

[pscustomobject][ordered]@{
    status = 'PASS_EXECUTION_ATTEMPT_005_PREPARED'
    authorizationId = $authorizationId
    executionAuthorizationSha256 = $authorizationSha
    stageContractSha256 = Get-Sha256Lower -Path $stageContractPath
    prelaunchAuditSha256 = Get-Sha256Lower -Path $prelaunchAuditPath
    launchContractSha256 = Get-Sha256Lower -Path $launchContractPath
    argumentCount = $arguments.Count
    argumentVectorSha256 = Get-TextSha256Lower -Text $canonicalArguments
} | ConvertTo-Json -Depth 10 -Compress
