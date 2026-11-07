[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$studyId = 'Gate14Re-ME'
$authorizationId = 'gate14re-me-qualification-execution-binding-supervisor-v2-repair-attempt-002'
$projectRoot = [System.IO.Path]::GetFullPath('H:\DDM_Final_Project').TrimEnd('\')
$stageRoot = Join-Path $projectRoot 'Research\Verification\Gate14Re-ME\qualification-execution-binding-supervisor-v2-repair-attempt-002'
$readinessFailureRoot = Join-Path $projectRoot 'Research\Verification\Gate14Re-ME\qualification-execution-readiness-freeze-attempt-001'
$repairAttempt001Root = Join-Path $projectRoot 'Research\Verification\Gate14Re-ME\qualification-execution-binding-supervisor-v2-repair-attempt-001'
$supervisorPath = Join-Path $projectRoot 'Research\Gate14Re-ME\Execution\v2\Run-Gate14ReMELoadQualification.v2.ps1'
$contractPath = Join-Path $projectRoot 'Research\Gate14Re-ME\Execution\v2\load-qualification-execution-contract.v2.json'
$manifestPath = Join-Path $projectRoot 'Research\Gate14Re-ME\Execution\v2\load-qualification-current-implementation-manifest.v2.json'
$compileReceiptPath = Join-Path $stageRoot 'compile-identity-receipt.v1.json'
$processReceiptPath = Join-Path $stageRoot 'process-launch-receipt.v1.json'
$trustedRulePath = Join-Path $projectRoot 'Research\Verification\Gate14Re-ME\unity-executable-identity-rule-offline-adjudication-attempt-005\trusted-launch-identity-rule.v1.json'
$timestampComparatorPath = Join-Path $projectRoot 'Research\Verification\Gate14Re-ME\unity-trusted-identity-timestamp-comparator-corrigendum-attempt-007\Gate14ReMETrustedTimestampComparatorV1.ps1'
$expectedSupervisorSha256 = 'a7e997f7b9d1c48753294b437566d40cf448106ef140e16a2780ce79b7059771'
$expectedContractSha256 = 'bee4b5103cc83c1528322faa98c7227cf6e94a481c4fa1059be93ffa5844ce69'
$expectedManifestSha256 = '53d1b7bd1fc12c6c13514c5180b4f59267c13bf90ea6809d1448038446af144f'
$expectedCompileReceiptSha256 = '07118a3b4be7e9cd0b044d073426d8db24ba116498d548c3bbfa42df2cdf9937'
$expectedReadinessFailureSha256 = 'feea3650801239a1e92ced9031b137f9c22f7e9a9a483d05a6456353f1827b57'
$expectedRepairAttempt001FailureSha256 = 'e5842af9ec3a6205aa9e9014ad1fddd6fab2f99696995577575c4ae4607d4c3e'
$expectedRepairAttempt001FreezeSha256 = '69dd2ba7f58d51b3de7b65cac74285661d4bfd63742c59778ec938a275bbde0a'

function Require-Condition {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw [System.InvalidOperationException]::new($Message) }
}

function Get-Sha256Lower {
    param([string]$Path)
    Require-Condition (Test-Path -LiteralPath $Path -PathType Leaf) "Required file is missing: $Path"
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Get-StringSha256Lower {
    param([string]$Value)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try { return [Convert]::ToHexString($sha.ComputeHash([System.Text.UTF8Encoding]::new($false).GetBytes($Value))).ToLowerInvariant() }
    finally { $sha.Dispose() }
}

function Read-Json {
    param([string]$Path)
    return Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json -Depth 100 -DateKind String
}

function Write-JsonExclusive {
    param([string]$Path, [object]$Value)
    Require-Condition (-not (Test-Path -LiteralPath $Path)) "Refusing to overwrite terminal evidence: $Path"
    $json = ($Value | ConvertTo-Json -Depth 100) + [Environment]::NewLine
    $encoding = [System.Text.UTF8Encoding]::new($false)
    $stream = [System.IO.File]::Open($Path, [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
    try {
        $writer = [System.IO.StreamWriter]::new($stream, $encoding)
        try { $writer.Write($json); $writer.Flush() }
        finally { $writer.Dispose() }
    }
    finally { $stream.Dispose() }
}

function Get-RelativePath {
    param([string]$Path, [string]$Root)
    $rootUri = [Uri]::new($Root.TrimEnd('\') + '\')
    return [Uri]::UnescapeDataString($rootUri.MakeRelativeUri([Uri]::new([System.IO.Path]::GetFullPath($Path))).ToString()).Replace('\', '/')
}

function Get-FileInventory {
    param([string]$Root)
    return @(
        Get-ChildItem -LiteralPath $Root -Recurse -Force -File | Sort-Object FullName | ForEach-Object {
            [pscustomobject][ordered]@{
                relativePath = Get-RelativePath -Path $_.FullName -Root $Root
                bytes = [int64]$_.Length
                sha256 = Get-Sha256Lower -Path $_.FullName
            }
        }
    )
}

function Get-InventoryDigest {
    param([object[]]$Inventory)
    return Get-StringSha256Lower -Value (@($Inventory) | ConvertTo-Json -Depth 20 -Compress)
}

function Compare-Serialized {
    param([object]$Left, [object]$Right)
    return (($Left | ConvertTo-Json -Depth 100 -Compress) -ceq ($Right | ConvertTo-Json -Depth 100 -Compress))
}

function Get-FingerprintHash {
    param([object]$Fingerprint, [string]$Method)
    $items = @($Fingerprint.fullFileHashes | Where-Object { $_.method -eq $Method })
    Require-Condition ($items.Count -eq 1) "Fingerprint is missing unique method $Method."
    return [string]$items[0].sha256
}

function Assert-Fingerprint {
    param([object]$Fingerprint, [object]$Rule, [string]$Phase)
    $app = $Rule.applicability
    Require-Condition $Fingerprint.independentHashMethodsAgree "$Phase independent Unity hashes disagree."
    Require-Condition ((Get-FingerprintHash -Fingerprint $Fingerprint -Method 'powershell-get-filehash') -eq [string]$app.unityExecutableExpectedSha256) "$Phase Unity hash mismatch."
    Require-Condition ((Get-FingerprintHash -Fingerprint $Fingerprint -Method 'dotnet-sha256-filestream') -eq [string]$app.unityExecutableExpectedSha256) "$Phase .NET Unity hash mismatch."
    Require-Condition (-not $Fingerprint.reparsePoint) "$Phase Unity executable is a reparse point."
    Require-Condition ($Fingerprint.fileIdentity.succeeded -and [string]$Fingerprint.fileIdentity.fileIdHex -eq [string]$app.ntfsFileIdHex -and [string]$Fingerprint.fileIdentity.fileIndexLow64Hex -eq [string]$app.ntfsFileIndexLow64Hex) "$Phase NTFS identity mismatch."
    Require-Condition ($Fingerprint.peIdentity.succeeded) "$Phase PE identity is unavailable."
    Require-Condition ([string]$Fingerprint.authenticode.status -eq 'Valid') "$Phase Authenticode is not valid."
    Require-Condition ([string]$Fingerprint.authenticode.signerSubject -eq [string]$app.signerSubject -and [string]$Fingerprint.authenticode.signerThumbprint -eq [string]$app.signerThumbprint) "$Phase signer identity mismatch."
    Require-Condition ([int64]$Fingerprint.lengthBytes -eq [int64]$app.fileLengthBytes) "$Phase Unity file length mismatch."
    Require-Condition ([System.IO.Path]::GetFullPath([string]$Fingerprint.path).TrimEnd('\') -ieq [System.IO.Path]::GetFullPath([string]$app.unityExecutablePath).TrimEnd('\')) "$Phase Unity path mismatch."
    $creation = Compare-Gate14ReMETrustedTimestampV1 -TrustedText ([string]$app.creationTimeUtc) -ObservedText ([string]$Fingerprint.creationTimeUtc)
    $lastWrite = Compare-Gate14ReMETrustedTimestampV1 -TrustedText ([string]$app.lastWriteTimeUtc) -ObservedText ([string]$Fingerprint.lastWriteTimeUtc)
    Require-Condition ($creation.comparisonAccepted -and $lastWrite.comparisonAccepted) "$Phase trusted timestamp comparison failed."
}

function Assert-FingerprintStable {
    param([object]$Reference, [object]$Observed, [string]$Phase)
    Require-Condition ([string]$Reference.path -ieq [string]$Observed.path) "$Phase executable path changed."
    Require-Condition ([int64]$Reference.lengthBytes -eq [int64]$Observed.lengthBytes) "$Phase executable length changed."
    Require-Condition ([string]$Reference.fileIdentity.fileIdHex -eq [string]$Observed.fileIdentity.fileIdHex) "$Phase file identity changed."
    Require-Condition (Compare-Serialized -Left $Reference.peIdentity -Right $Observed.peIdentity) "$Phase PE identity changed."
    Require-Condition (Compare-Serialized -Left $Reference.authenticode -Right $Observed.authenticode) "$Phase Authenticode identity changed."
    Require-Condition (Compare-Serialized -Left @($Reference.chunkHashes) -Right @($Observed.chunkHashes)) "$Phase chunk hashes changed."
}

foreach ($name in @('final-static-closure-receipt.v1.json', 'authorization-boundary-receipt.v1.json', 'terminal-receipt.v1.json', 'source-and-evidence-freeze-manifest.v1.json')) {
    Require-Condition (-not (Test-Path -LiteralPath (Join-Path $stageRoot $name))) "Terminal evidence already exists: $name"
}
Require-Condition (-not (Test-Path -LiteralPath (Join-Path $stageRoot 'failure-receipt.v1.json'))) 'Attempt-002 has a failure receipt and cannot be closed as PASS.'

Require-Condition ((Get-Sha256Lower -Path $supervisorPath) -eq $expectedSupervisorSha256) 'Final supervisor v2 hash mismatch.'
Require-Condition ((Get-Sha256Lower -Path $contractPath) -eq $expectedContractSha256) 'Final execution contract v2 hash mismatch.'
Require-Condition ((Get-Sha256Lower -Path $manifestPath) -eq $expectedManifestSha256) 'Current implementation manifest v2 hash mismatch.'
Require-Condition ((Get-Sha256Lower -Path $compileReceiptPath) -eq $expectedCompileReceiptSha256) 'Compile identity receipt hash mismatch.'

$tokens = $null
$parseErrors = $null
[System.Management.Automation.Language.Parser]::ParseFile($supervisorPath, [ref]$tokens, [ref]$parseErrors) | Out-Null
Require-Condition (@($parseErrors).Count -eq 0) 'Final supervisor v2 has a PowerShell parse error.'
$supervisorText = Get-Content -LiteralPath $supervisorPath -Raw -Encoding UTF8
$requiredSupervisorTokens = @(
    'Gate14ReMELoadQualificationRunnerV2.Run', 'lane-receipt.v2.json', 'empty-boundary-receipt.v2.json',
    'instrument-csharp-receipt.v2.json', 'PRELAUNCH', 'LIVE_CONCURRENT', 'POST_EXIT',
    'Compare-Gate14ReMETrustedTimestampV1', 'exactCommandLine', 'ZERO_REPLACEMENT_FAIL_STOP',
    'contract.frozenBindings', 'ConvertFrom-Json -Depth 100 -DateKind String',
    'PASS_SCHEMA_V2_STRUCTURAL_COMPLETE_RAW_NO_INFERENCE',
    'PASS_VERIFIED_SCHEMA_V2_COMPLETE_PER_OBSERVATION_DELIVERY'
)
$missingTokens = @($requiredSupervisorTokens | Where-Object { -not $supervisorText.Contains($_) })
Require-Condition ($missingTokens.Count -eq 0) "Final supervisor is missing tokens: $($missingTokens -join ', ')"
$forbiddenTokens = @('Gate14ReMELoadQualificationRunnerV1.Run', 'lane-receipt.v1.json', 'empty-boundary-receipt.v1.json', 'instrument-csharp-receipt.v1.json', 'Stop-Process')
$presentForbidden = @($forbiddenTokens | Where-Object { $supervisorText.Contains($_) })
Require-Condition ($presentForbidden.Count -eq 0) "Final supervisor contains stale or forced-termination tokens: $($presentForbidden -join ', ')"

$contract = Read-Json -Path $contractPath
$manifest = Read-Json -Path $manifestPath
Require-Condition ($contract.schema -eq 'gate14re-me-load-qualification-execution-contract-v2' -and $contract.status -eq 'FROZEN_EXECUTION_BINDING_V2_QUALIFICATION_EXECUTION_UNAUTHORIZED') 'Execution contract header mismatch.'
Require-Condition ($contract.entryPoint.supervisorSha256 -eq $expectedSupervisorSha256 -and $contract.entryPoint.runnerSha256 -eq '39d371a5a9e858836bc448aabb04656e8576e296ca9b1cedb479cd3552ad1d73') 'Execution contract entry-point binding mismatch.'
Require-Condition ($manifest.schema -eq 'gate14re-me-qualification-implementation-manifest-v1' -and $manifest.status -eq 'FROZEN_IMPLEMENTATION_SOURCE_ONLY_UNCOMPILED') 'Manifest legacy RunnerV2 compatibility fields changed.'
Require-Condition ([int]$manifest.manifestGeneration -eq 2 -and $manifest.manifestSchemaV2 -eq 'gate14re-me-qualification-current-implementation-manifest-v2' -and $manifest.executionReadinessStatus -eq 'FROZEN_CURRENT_IMPLEMENTATION_COMPILED_AND_ALGORITHM_FREE_IDENTITY_PROBED') 'Manifest authoritative v2 state mismatch.'
Require-Condition ($manifest.legacyRunnerCompatibility.legacyStatusIsNotTheAuthoritativeExecutionReadinessState) 'Manifest does not explicitly quarantine the legacy status field.'
Require-Condition (@($manifest.artifacts).Count -eq 48 -and @($manifest.artifacts.relativePath | Sort-Object -Unique).Count -eq 48) 'Manifest artifact count or uniqueness mismatch.'
$artifactIndex = @{}
foreach ($artifact in @($manifest.artifacts)) {
    $full = [System.IO.Path]::GetFullPath((Join-Path $projectRoot ([string]$artifact.relativePath)))
    Require-Condition ($full.StartsWith($projectRoot + '\', [System.StringComparison]::OrdinalIgnoreCase)) "Manifest path escapes project root: $($artifact.relativePath)"
    Require-Condition ((Get-RelativePath -Path $full -Root $projectRoot) -ceq [string]$artifact.relativePath) "Manifest path is non-canonical: $($artifact.relativePath)"
    Require-Condition ((Get-Item -LiteralPath $full).Length -eq [int64]$artifact.bytes) "Manifest byte count mismatch: $($artifact.relativePath)"
    Require-Condition ((Get-Sha256Lower -Path $full) -eq [string]$artifact.sha256) "Manifest hash mismatch: $($artifact.relativePath)"
    $artifactIndex[[string]$artifact.relativePath] = [string]$artifact.sha256
}
foreach ($property in $contract.frozenBindings.PSObject.Properties) {
    $binding = $property.Value
    $full = Join-Path $projectRoot ([string]$binding.relativePath)
    Require-Condition ((Get-Sha256Lower -Path $full) -eq [string]$binding.sha256) "Contract binding hash mismatch: $($property.Name)"
    Require-Condition ($artifactIndex.ContainsKey([string]$binding.relativePath) -and $artifactIndex[[string]$binding.relativePath] -eq [string]$binding.sha256) "Manifest omits contract binding: $($property.Name)"
}

$schedulePath = Join-Path $projectRoot ([string]$contract.frozenBindings.schedule.relativePath)
$scheduleRows = @(Get-Content -LiteralPath $schedulePath -Encoding UTF8 | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | ForEach-Object { $_ | ConvertFrom-Json -Depth 100 -DateKind String })
Require-Condition ($scheduleRows.Count -eq 162) 'Schedule cardinality is not 162.'
Require-Condition (@($scheduleRows | Where-Object { $null -ne $_.replacement }).Count -eq 0) 'Schedule contains a replacement asset.'
Require-Condition (@($scheduleRows | Where-Object { @($_.algorithmOrder).Count -ne 6 }).Count -eq 0) 'Schedule contains a non-six-lane row.'

$compileReceipt = Read-Json -Path $compileReceiptPath
$processReceipt = Read-Json -Path $processReceiptPath
Require-Condition ($compileReceipt.status -eq 'PASS_CURRENT_PROJECT_COMPILED_ALGORITHM_FREE_TRUSTED_IDENTITY') 'Compile identity receipt is not PASS.'
Require-Condition ([int]$compileReceipt.unityInvocationCount -eq 1 -and [int]$compileReceipt.exitCode -eq 0 -and $compileReceipt.naturalExit -and -not $compileReceipt.signalOrForcedTerminationSent -and -not $compileReceipt.retryPerformed -and $null -eq $compileReceipt.executeMethod) 'Compile identity invocation boundary mismatch.'
Require-Condition ([int]$compileReceipt.algorithmLaneExecutions -eq 0 -and [int]$compileReceipt.qualificationObservations -eq 0 -and [int]$compileReceipt.formalObservations -eq 0 -and [int]$compileReceipt.replacementAssetsGenerated -eq 0 -and -not $compileReceipt.formalAnalysisPerformed -and -not $compileReceipt.rankingOrWinnerComputed) 'Compile identity receipt reports a prohibited activity.'
Require-Condition ([int]$processReceipt.processId -eq [int]$compileReceipt.processId -and $null -eq $processReceipt.executeMethod -and -not ([string]$processReceipt.exactCommandLine).Contains('-executeMethod')) 'Process receipt is not an algorithm-free exact command line.'
Require-Condition ((Get-StringSha256Lower -Value ([string]$processReceipt.exactCommandLine)) -eq [string]$processReceipt.exactCommandLineSha256) 'Process command-line digest mismatch.'
Require-Condition ([string]$processReceipt.executablePath -eq 'H:/UnityEditor/2022.3.30f1c1/Editor/Unity.exe' -and [string]$processReceipt.projectPath -eq 'H:/DDM_Final_Project') 'Process executable/project path mismatch.'

. $timestampComparatorPath
$rule = Read-Json -Path $trustedRulePath
$prePath = Join-Path $stageRoot 'external-prelaunch-fingerprint.v1.json'
$livePath = Join-Path $stageRoot 'external-live-fingerprint.v1.json'
$postPath = Join-Path $stageRoot 'external-post-exit-fingerprint.v1.json'
Require-Condition ((Get-Sha256Lower -Path $prePath) -eq [string]$compileReceipt.prelaunchFingerprintSha256) 'Prelaunch fingerprint receipt hash mismatch.'
Require-Condition ((Get-Sha256Lower -Path $livePath) -eq [string]$compileReceipt.liveFingerprintSha256) 'Live fingerprint receipt hash mismatch.'
Require-Condition ((Get-Sha256Lower -Path $postPath) -eq [string]$compileReceipt.postExitFingerprintSha256) 'Post-exit fingerprint receipt hash mismatch.'
$pre = Read-Json -Path $prePath
$live = Read-Json -Path $livePath
$post = Read-Json -Path $postPath
Assert-Fingerprint -Fingerprint $pre -Rule $rule -Phase 'prelaunch'
Assert-Fingerprint -Fingerprint $live -Rule $rule -Phase 'live'
Assert-Fingerprint -Fingerprint $post -Rule $rule -Phase 'post-exit'
Assert-FingerprintStable -Reference $pre -Observed $live -Phase 'live'
Assert-FingerprintStable -Reference $pre -Observed $post -Phase 'post-exit'

$unityLogPath = Join-Path $stageRoot 'unity-compile-identity-probe.log'
Require-Condition ((Get-Sha256Lower -Path $unityLogPath) -eq [string]$compileReceipt.unityLogSha256) 'Unity compile log hash mismatch.'
$logText = Get-Content -LiteralPath $unityLogPath -Raw -Encoding UTF8
$compilerFailurePatterns = @('error CS\d{4}', 'Scripts have compiler errors', 'Compilation failed', 'CompilerError', 'Aborting batchmode due to failure')
Require-Condition (@($compilerFailurePatterns | Where-Object { $logText -match $_ }).Count -eq 0) 'Unity log contains a compiler failure marker.'
foreach ($assembly in @($compileReceipt.editorAssembly, $compileReceipt.runtimeAssembly)) {
    $assemblyPath = Join-Path $projectRoot ([string]$assembly.relativePath)
    Require-Condition ((Get-Item -LiteralPath $assemblyPath).Length -eq [int64]$assembly.bytes -and (Get-Sha256Lower -Path $assemblyPath) -eq [string]$assembly.sha256) "Compiled assembly drifted: $($assembly.relativePath)"
}

$pythonPath = [string]$manifest.runtimeBindings.pythonExecutable
$powershellPath = [string]$manifest.runtimeBindings.powershellExecutable
$unityPath = [string]$manifest.runtimeBindings.unityExecutable
Require-Condition ((Get-Sha256Lower -Path $pythonPath) -eq [string]$manifest.runtimeBindings.pythonExecutableSha256) 'Python runtime hash mismatch.'
Require-Condition ((Get-Sha256Lower -Path $powershellPath) -eq [string]$manifest.runtimeBindings.powershellExecutableSha256) 'PowerShell runtime hash mismatch.'
Require-Condition ((Get-Sha256Lower -Path $unityPath) -eq [string]$manifest.runtimeBindings.unityExecutableSha256) 'Unity runtime hash mismatch.'
$structuralPath = Join-Path $projectRoot ([string]$contract.frozenBindings.structuralV2.relativePath)
$deliveryPath = Join-Path $projectRoot ([string]$contract.frozenBindings.deliveryV2.relativePath)
$pythonAstCode = 'import ast,sys; [ast.parse(open(p, encoding="utf-8").read(), filename=p) for p in sys.argv[1:]]'
$pythonAstOutput = @(& $pythonPath -c $pythonAstCode $structuralPath $deliveryPath 2>&1 | ForEach-Object { [string]$_ })
Require-Condition ($LASTEXITCODE -eq 0) "Python structural/delivery source parse failed: $($pythonAstOutput -join [Environment]::NewLine)"
Require-Condition ((Get-Content -LiteralPath $structuralPath -Raw).Contains('PASS_SCHEMA_V2_STRUCTURAL_COMPLETE_RAW_NO_INFERENCE')) 'Structural-v2 terminal status token is missing.'
$deliveryText = Get-Content -LiteralPath $deliveryPath -Raw
Require-Condition ($deliveryText.Contains('PASS_SCHEMA_V2_COMPLETE_PER_OBSERVATION_DELIVERY') -and $deliveryText.Contains('PASS_VERIFIED_SCHEMA_V2_COMPLETE_PER_OBSERVATION_DELIVERY')) 'Delivery-v2 terminal status tokens are missing.'

$readinessInventory = @(Get-FileInventory -Root $readinessFailureRoot)
$repairAttempt001Inventory = @(Get-FileInventory -Root $repairAttempt001Root)
Require-Condition ($readinessInventory.Count -eq 7 -and (Get-Sha256Lower -Path (Join-Path $readinessFailureRoot 'failure-receipt.v1.json')) -eq $expectedReadinessFailureSha256) 'Original readiness failure evidence drifted.'
Require-Condition ($repairAttempt001Inventory.Count -eq 8 -and (Get-Sha256Lower -Path (Join-Path $repairAttempt001Root 'failure-receipt.v1.json')) -eq $expectedRepairAttempt001FailureSha256 -and (Get-Sha256Lower -Path (Join-Path $repairAttempt001Root 'source-and-evidence-freeze-manifest.v1.json')) -eq $expectedRepairAttempt001FreezeSha256) 'Repair attempt-001 evidence drifted.'
Require-Condition ((Get-InventoryDigest -Inventory $readinessInventory) -eq [string]$compileReceipt.priorReadinessEvidenceInventoryDigestAfter) 'Original readiness evidence digest differs from the compile receipt.'
Require-Condition ((Get-InventoryDigest -Inventory $repairAttempt001Inventory) -eq [string]$compileReceipt.repairAttempt001EvidenceInventoryDigestAfter) 'Repair attempt-001 evidence digest differs from the compile receipt.'
Require-Condition (@(Get-ChildItem -LiteralPath $repairAttempt001Root -Force -File | Where-Object { -not $_.IsReadOnly }).Count -eq 0) 'Repair attempt-001 is not read-only.'

Require-Condition (@(Get-CimInstance Win32_Process -Filter "Name = 'Unity.exe'").Count -eq 0) 'A Unity process is active at closure.'
$prohibitedRoots = @(
    'Research/PilotRuns/Gate14Re-ME/load-qualification/attempt-001',
    'Research/FormalRuns/Gate14Re-ME',
    'Research/Exports/Gate14Re-ME/load-qualification/attempt-001'
)
$presentProhibitedRoots = @($prohibitedRoots | Where-Object { Test-Path -LiteralPath (Join-Path $projectRoot $_) })
Require-Condition ($presentProhibitedRoots.Count -eq 0) "A prohibited data root exists: $($presentProhibitedRoots -join ', ')"

$finalStaticPath = Join-Path $stageRoot 'final-static-closure-receipt.v1.json'
Write-JsonExclusive -Path $finalStaticPath -Value ([ordered]@{
    schema = 'gate14re-me-qualification-execution-binding-supervisor-v2-final-static-closure-receipt-v1'
    studyId = $studyId
    authorizationId = $authorizationId
    status = 'PASS_FINAL_STATIC_EXECUTION_BINDING_SUPERVISOR_V2'
    completedAtUtc = [DateTime]::UtcNow.ToString('o')
    supervisorSha256 = $expectedSupervisorSha256
    executionContractSha256 = $expectedContractSha256
    currentImplementationManifestSha256 = $expectedManifestSha256
    manifestArtifactsVerified = 48
    contractFrozenBindingsVerified = @($contract.frozenBindings.PSObject.Properties).Count
    runnerV2Sha256 = [string]$contract.entryPoint.runnerSha256
    receiptGeneration = 2
    inputSchemaV2Bound = $true
    instrumentContractV3Bound = $true
    outputSchemaV2Bound = $true
    qualifiedD3V31Bound = $true
    typedParquetRuntimeBound = $true
    structuralV2Bound = $true
    deliveryV2Bound = $true
    completePerObservationDeliveryContractBound = $true
    threePhaseUnityIdentityPassed = $true
    compositeProcessIdentityPassed = $true
    currentProjectCompilationPassed = $true
    structuralAndDeliverySourceParsePassed = $true
    scheduleRows = 162
    algorithmsPerRow = 6
    replacementAssets = 0
    operationalPolicy = 'ZERO_REPLACEMENT_FAIL_STOP'
})

$boundaryPath = Join-Path $stageRoot 'authorization-boundary-receipt.v1.json'
Write-JsonExclusive -Path $boundaryPath -Value ([ordered]@{
    schema = 'gate14re-me-qualification-execution-binding-supervisor-v2-repair-boundary-receipt-v1'
    studyId = $studyId
    authorizationId = $authorizationId
    status = 'PASS_BOUNDARY_NO_QUALIFICATION_OR_FORMAL_EXECUTION'
    completedAtUtc = [DateTime]::UtcNow.ToString('o')
    algorithmFreeUnityCompileIdentityInvocations = 1
    unityProcessesRemaining = 0
    executeMethod = $null
    qualificationMeasuredRootCreated = $false
    deliveryRootCreated = $false
    plannerInvocations = 0
    algorithmLaneExecutions = 0
    qualificationObservations = 0
    formalObservations = 0
    replacementAssetsGenerated = 0
    formalCollectionPerformed = $false
    formalAnalysisPerformed = $false
    rankingPerformed = $false
    winnerAdjudicationPerformed = $false
    priorFailuresModifiedOrReclassified = $false
})

$terminalPath = Join-Path $stageRoot 'terminal-receipt.v1.json'
Write-JsonExclusive -Path $terminalPath -Value ([ordered]@{
    schema = 'gate14re-me-qualification-execution-binding-supervisor-v2-repair-terminal-receipt-v1'
    studyId = $studyId
    authorizationId = $authorizationId
    status = 'PASS_EXECUTION_BINDING_SUPERVISOR_V2_REPAIRED_FROZEN'
    completedAtUtc = [DateTime]::UtcNow.ToString('o')
    supervisor = [ordered]@{ relativePath = Get-RelativePath -Path $supervisorPath -Root $projectRoot; sha256 = $expectedSupervisorSha256 }
    executionContract = [ordered]@{ relativePath = Get-RelativePath -Path $contractPath -Root $projectRoot; sha256 = $expectedContractSha256 }
    currentImplementationManifest = [ordered]@{ relativePath = Get-RelativePath -Path $manifestPath -Root $projectRoot; sha256 = $expectedManifestSha256 }
    compileIdentityReceiptSha256 = $expectedCompileReceiptSha256
    finalStaticClosureReceiptSha256 = Get-Sha256Lower -Path $finalStaticPath
    authorizationBoundaryReceiptSha256 = Get-Sha256Lower -Path $boundaryPath
    priorReadinessFailureRetained = $true
    repairAttempt001FailureRetained = $true
    currentImplementationCompiled = $true
    qualificationExecutionAuthorized = $false
    measuredRootCreated = $false
    algorithmLaneExecuted = $false
    formalCollectionAuthorized = $false
    formalAnalysisAuthorized = $false
    rankingAuthorized = $false
    winnerAdjudicationAuthorized = $false
    nextActionRequiresSeparateAuthorization = $true
})

$freezeManifestPath = Join-Path $stageRoot 'source-and-evidence-freeze-manifest.v1.json'
$attemptInventory = @(Get-FileInventory -Root $stageRoot)
Write-JsonExclusive -Path $freezeManifestPath -Value ([ordered]@{
    schema = 'gate14re-me-qualification-execution-binding-supervisor-v2-repair-source-and-evidence-freeze-manifest-v1'
    studyId = $studyId
    authorizationId = $authorizationId
    status = 'FROZEN_PASS_SOURCE_AND_EVIDENCE'
    frozenAtUtc = [DateTime]::UtcNow.ToString('o')
    terminalReceiptSha256 = Get-Sha256Lower -Path $terminalPath
    currentFrozenArtifacts = @(
        [ordered]@{ relativePath = Get-RelativePath -Path $supervisorPath -Root $projectRoot; bytes = (Get-Item -LiteralPath $supervisorPath).Length; sha256 = $expectedSupervisorSha256 },
        [ordered]@{ relativePath = Get-RelativePath -Path $contractPath -Root $projectRoot; bytes = (Get-Item -LiteralPath $contractPath).Length; sha256 = $expectedContractSha256 },
        [ordered]@{ relativePath = Get-RelativePath -Path $manifestPath -Root $projectRoot; bytes = (Get-Item -LiteralPath $manifestPath).Length; sha256 = $expectedManifestSha256 }
    )
    attemptFiles = $attemptInventory
    attemptFilesCountExcludingThisManifest = $attemptInventory.Count
    selfExcludedToAvoidRecursiveHash = $true
    priorFailuresRetainedWithoutModificationOrReclassification = $true
})

foreach ($file in @(Get-ChildItem -LiteralPath $stageRoot -Force -File) + @(Get-Item -LiteralPath $supervisorPath, $contractPath, $manifestPath)) {
    $file.IsReadOnly = $true
}
Require-Condition (@(Get-ChildItem -LiteralPath $stageRoot -Force -File | Where-Object { -not $_.IsReadOnly }).Count -eq 0) 'Attempt-002 read-only freeze failed.'
Require-Condition (@(Get-Item -LiteralPath $supervisorPath, $contractPath, $manifestPath | Where-Object { -not $_.IsReadOnly }).Count -eq 0) 'Current source/contract/manifest read-only freeze failed.'

Write-Output 'PASS_EXECUTION_BINDING_SUPERVISOR_V2_REPAIRED_FROZEN'
Write-Output "SUPERVISOR_SHA256=$expectedSupervisorSha256"
Write-Output "EXECUTION_CONTRACT_SHA256=$expectedContractSha256"
Write-Output "CURRENT_IMPLEMENTATION_MANIFEST_SHA256=$expectedManifestSha256"
Write-Output "TERMINAL_RECEIPT_SHA256=$(Get-Sha256Lower -Path $terminalPath)"
Write-Output "SOURCE_AND_EVIDENCE_FREEZE_MANIFEST_SHA256=$(Get-Sha256Lower -Path $freezeManifestPath)"
