[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$ProjectRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-Sha256Lower {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Get-ProjectRelativePath {
    param([string]$Path, [string]$Root)
    $rootUri = [Uri]::new($Root.TrimEnd([System.IO.Path]::DirectorySeparatorChar) + [System.IO.Path]::DirectorySeparatorChar)
    $pathUri = [Uri]::new([System.IO.Path]::GetFullPath($Path))
    return [Uri]::UnescapeDataString($rootUri.MakeRelativeUri($pathUri).ToString()).Replace('\', '/')
}

function Get-StringSha256Lower {
    param([string]$Value)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [System.Text.UTF8Encoding]::new($false).GetBytes($Value)
        return [Convert]::ToHexString($sha.ComputeHash($bytes)).ToLowerInvariant()
    }
    finally { $sha.Dispose() }
}

function Get-Inventory {
    param([string]$Root)
    return @(Get-ChildItem -LiteralPath $Root -Recurse -Force -File | Sort-Object FullName | ForEach-Object {
        [ordered]@{
            relativePath = Get-ProjectRelativePath -Path $_.FullName -Root $Root
            lengthBytes = [int64]$_.Length
            sha256 = Get-Sha256Lower -Path $_.FullName
            readOnly = [bool]$_.IsReadOnly
        }
    })
}

function Get-InventoryDigest {
    param([object[]]$Inventory)
    return Get-StringSha256Lower -Value ($Inventory | ConvertTo-Json -Depth 10 -Compress)
}

function Read-Json {
    param([string]$Path)
    return Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json -Depth 100 -DateKind String
}

$project = [System.IO.Path]::GetFullPath($ProjectRoot).TrimEnd('\')
$checks = [System.Collections.Generic.List[object]]::new()
function Add-Check {
    param([string]$Id, [string]$Domain, [bool]$Passed, [object]$Observed, [object]$Expected)
    $checks.Add([pscustomobject][ordered]@{
        checkId = $Id
        domain = $Domain
        passed = $Passed
        observed = $Observed
        expected = $Expected
    })
}

function Full-Path {
    param([string]$RelativePath)
    return [System.IO.Path]::GetFullPath((Join-Path $project $RelativePath.Replace('/', '\')))
}

$expected = [ordered]@{
    statusV37 = @('Research/Gate14Re-ME/Gate14Re_ME_Status.v37.json', 'effa1a9270965c537bb24c2915f3f4498fd992bc2a29e601acdceba60c8dd232')
    attempt003Failure = @('Research/Verification/Gate14Re-ME/load-qualification-execution-attempt-003/terminal-failure-receipt.v1.json', 'ec78b55c4f7be0d00433958806a26b7ef1e1a3dd75ce140a9013079cadf13df9')
    attempt003Adjudication = @('Research/Verification/Gate14Re-ME/load-qualification-execution-attempt-003/technical-failure-adjudication.v1.json', '0de24cf90557e0e4dcdfa26f299d152f6883af85b3cce4e9ec8a887f693d23ca')
    attempt003Freeze = @('Research/Verification/Gate14Re-ME/load-qualification-execution-attempt-003/freeze-manifest.v1.json', '10764c3f357eeec90eb138701d4c29a3d16a6e1047dbbc48a4a26be551fee249')
    runner = @('Assets/_Scripts/Research/Editor/Gate14ReMELoadQualificationRunnerV2.cs', 'e93cbf1ff3d0551daf927acca95b02dc839aa925275ba5d7a0c170b7c5206401')
    harness = @('Assets/_Scripts/Research/Editor/Gate14ReMEScheduleNullReplacementKnownAnswerV1.cs', 'abad9cf6fdae640384c821e6ce555d2b5bcad88cb9ffa2aa50fecb0a95176448')
    editorAssembly = @('Library/ScriptAssemblies/Assembly-CSharp-Editor.dll', '3d1165d306227a6ec27b1b7472342d04dd3f52770852f522f7c9db4297440b18')
    runtimeAssembly = @('Library/ScriptAssemblies/Assembly-CSharp.dll', 'c21848ca1618dc010f52a1035489ac9347fe481735b362ee3ac8c8d938324bd1')
    corrigendumReceipt = @('Research/Verification/Gate14Re-ME/qualification-schedule-null-replacement-deserialization-corrigendum-attempt-001/corrigendum-pass-receipt.v1.json', '4c56ddecf1fb191dca2188c68b30aa56691f5cc498d5d92879ffd125efc14df2')
    knownAnswerReceipt = @('Research/Verification/Gate14Re-ME/qualification-schedule-null-replacement-deserialization-corrigendum-attempt-001/unity-known-answer-output/known-answer-receipt.v1.json', '3278f19b818f386b83f6fb21fe1fd583937819dcb70be84a777e7c12b0f9c4bd')
    knownAnswerAdjudication = @('Research/Verification/Gate14Re-ME/qualification-schedule-null-replacement-deserialization-corrigendum-attempt-001/unity-known-answer-adjudication.v1.json', '8b5c7591f5b7be4fa656436e214dfd012bd127158ced0825391bfc82f753fc52')
    compiledFreeze = @('Research/Verification/Gate14Re-ME/qualification-schedule-null-replacement-deserialization-corrigendum-attempt-001/compiled-implementation-freeze-manifest.v1.json', 'c8194b7f89940a02dd38749acb97c9e1627de91cecf99d1844ff384e3929fea9')
    supervisor = @('Research/Gate14Re-ME/Execution/v3/Run-Gate14ReMELoadQualification.v3_2.ps1', 'a2fe6db79551f52310a18ef6c16e77d827945aed998812d1f08aa939dd172409')
    contract = @('Research/Gate14Re-ME/Execution/v3/load-qualification-execution-contract.v3_4.json', 'e3b519f226a3d24eb1d71927fe0cd6d4e16ba879d2c382b0203453a03ff55a85')
    manifest = @('Research/Gate14Re-ME/Execution/v3/load-qualification-current-implementation-manifest.v3_4.json', '1e56697a40692ff76fc01273ec4e5b8b7953ea88dcfe228eeeb317d9705a69c1')
    schedule = @('Research/Verification/Gate14Re-ME/qualification-planning-asset-generation-v2-attempt-001/planning-assets/schedule/formal-qualification-williams-schedule.v1.jsonl', '328301be5b496a794b67962693183242286d22bc6030db6c746daf7873582471')
    planningManifest = @('Research/Verification/Gate14Re-ME/qualification-planning-asset-generation-v2-attempt-001/planning-assets-freeze-manifest.v1.json', '7e0cbe77cb8bb8f84642856c6356d318f708e168b52a92e6e348cdf948169aca')
    sealedIdentity = @('Research/Verification/Gate14Re-ME/qualification-planning-asset-generation-v2-attempt-001/planning-assets/identity/anonymous-identity-binding.sealed.v1.json', '4e52f6f37c4ae496268a173c51ae498eba27a0efaf5303d131e6a102f8aabe08')
    outputSchema = @('Research/Gate14Re-ME/Execution/v3/load-qualification-output-schema.v3.json', 'e9a16e52e041b5818f1d25a343bdf86260d654177aff97bb0c5102637d554a7c')
    structural = @('Research/Gate14Re-ME/Tools/gate14re_me_qualification_structural_v3_1.py', '85b037f50cf913753ea4c77a7642b1d25b7550a833a4d5309ab16b41ad3fca7e')
    delivery = @('Research/Gate14Re-ME/Tools/gate14re_me_qualification_delivery_v2_2.py', '197b14309670fc38e26b421c458fbd4fc05abe8ba61f7f715497bbcffb19eb98')
    trustedIdentity = @('Research/Verification/Gate14Re-ME/unity-executable-identity-rule-offline-adjudication-attempt-005/trusted-launch-identity-rule.v1.json', 'f045ef93630202a72d603096687bac655b5b4ff01e8e0743e60d63881bbded06')
    timestampComparator = @('Research/Verification/Gate14Re-ME/unity-trusted-identity-timestamp-comparator-corrigendum-attempt-007/Gate14ReMETrustedTimestampComparatorV1.ps1', 'd024c5471d1fc06fb08e9c9ca1c9cf612424d4299d8b8c6b856883745105eb27')
    typedParquet = @('Research/Gate14Re-ME/Runtime/v1/typed-parquet-runtime-manifest.v1.json', '254375836c5c6c8ed09654d5f1817d1fa88c21a8c02447019f29116e3b2a088e')
}

$expectedFileFailures = [System.Collections.Generic.List[string]]::new()
foreach ($entry in $expected.GetEnumerator()) {
    $full = Full-Path -RelativePath $entry.Value[0]
    $actual = Get-Sha256Lower -Path $full
    if ($actual -ne $entry.Value[1]) { $expectedFileFailures.Add("$($entry.Key):$actual") }
}
Add-Check -Id 'HASHES::AUTHORITATIVE_BINDINGS' -Domain 'hash-binding' -Passed ($expectedFileFailures.Count -eq 0) -Observed @($expectedFileFailures) -Expected 'all expected hashes match'

$statusV37 = Read-Json -Path (Full-Path $expected.statusV37[0])
Add-Check -Id 'RETENTION::STATUS_V37_UNCHANGED_FAILED_CLOSED' -Domain 'retention' -Passed ($statusV37.status -eq 'LOAD_QUALIFICATION_EXECUTION_ATTEMPT_003_FAILED_CLOSED_REPAIR_AUTHORIZATION_PENDING') -Observed $statusV37.status -Expected 'LOAD_QUALIFICATION_EXECUTION_ATTEMPT_003_FAILED_CLOSED_REPAIR_AUTHORIZATION_PENDING'

$attempt003Root = Full-Path 'Research/Verification/Gate14Re-ME/load-qualification-execution-attempt-003'
$failedMeasuredRoot = Full-Path 'Research/PilotRuns/Gate14Re-ME/load-qualification/attempt-001'
$attempt003Inventory = @(Get-Inventory -Root $attempt003Root)
$failedMeasuredInventory = @(Get-Inventory -Root $failedMeasuredRoot)
$attempt003Digest = Get-InventoryDigest -Inventory $attempt003Inventory
$failedMeasuredDigest = Get-InventoryDigest -Inventory $failedMeasuredInventory
Add-Check -Id 'RETENTION::EXECUTION_ATTEMPT_003_INVENTORY_IDENTICAL' -Domain 'retention' -Passed ($attempt003Digest -eq '4609899169ed8db7e4dea41590aa81b1329a8f3a40f7bc7359f89e1baf01afc6') -Observed $attempt003Digest -Expected '4609899169ed8db7e4dea41590aa81b1329a8f3a40f7bc7359f89e1baf01afc6'
Add-Check -Id 'RETENTION::FAILED_MEASURED_ROOT_IDENTICAL_READ_ONLY' -Domain 'retention' -Passed ($failedMeasuredDigest -eq 'bde45ebf6b3945dd8fea8a141805d3c9ddf45605ed6a4a6e228791679576a4cd' -and $failedMeasuredInventory.Count -eq 6 -and @($failedMeasuredInventory | Where-Object { -not $_.readOnly }).Count -eq 0) -Observed ([ordered]@{digest=$failedMeasuredDigest;files=$failedMeasuredInventory.Count;writable=@($failedMeasuredInventory | Where-Object { -not $_.readOnly }).Count}) -Expected ([ordered]@{digest='bde45ebf6b3945dd8fea8a141805d3c9ddf45605ed6a4a6e228791679576a4cd';files=6;writable=0})

$newMeasured = Full-Path 'Research/PilotRuns/Gate14Re-ME/load-qualification/attempt-002'
$newDelivery = Full-Path 'Research/Exports/Gate14Re-ME/load-qualification/attempt-002'
$formalRoot = Full-Path 'Research/FormalRuns/Gate14Re-ME'
Add-Check -Id 'BOUNDARY::PROSPECTIVE_ROOTS_ABSENT' -Domain 'authorization-boundary' -Passed (-not (Test-Path -LiteralPath $newMeasured) -and -not (Test-Path -LiteralPath $newDelivery) -and -not (Test-Path -LiteralPath $formalRoot)) -Observed ([ordered]@{measured=(Test-Path -LiteralPath $newMeasured);delivery=(Test-Path -LiteralPath $newDelivery);formal=(Test-Path -LiteralPath $formalRoot)}) -Expected ([ordered]@{measured=$false;delivery=$false;formal=$false})

$unityProcesses = @(Get-CimInstance Win32_Process -Filter "Name = 'Unity.exe'")
$qualificationSupervisors = @(Get-CimInstance Win32_Process | Where-Object { $_.CommandLine -and $_.CommandLine.Contains('Run-Gate14ReMELoadQualification') })
Add-Check -Id 'BOUNDARY::NO_UNITY_OR_QUALIFICATION_SUPERVISOR' -Domain 'process-boundary' -Passed ($unityProcesses.Count -eq 0 -and $qualificationSupervisors.Count -eq 0) -Observed ([ordered]@{unity=$unityProcesses.Count;supervisor=$qualificationSupervisors.Count}) -Expected ([ordered]@{unity=0;supervisor=0})

$known = Read-Json -Path (Full-Path $expected.knownAnswerReceipt[0])
$caseMap = @{}
foreach ($case in @($known.cases)) { $caseMap[[string]$case.caseId] = $case }
$requiredCases = [ordered]@{
    'replacement-null' = 'NORMALIZED_TO_NO_REPLACEMENT'
    'replacement-member-omitted' = 'NORMALIZED_TO_NO_REPLACEMENT'
    'complete-valid-replacement-object' = 'PRESERVED_FOR_EXISTING_DOWNSTREAM_VALIDATION'
    'empty-replacement-object' = 'FAIL_CLOSED_EMPTY_OR_INCOMPLETE_REPLACEMENT'
    'partial-replacement-object' = 'FAIL_CLOSED_EMPTY_OR_INCOMPLETE_REPLACEMENT'
}
$caseFailures = [System.Collections.Generic.List[string]]::new()
foreach ($entry in $requiredCases.GetEnumerator()) {
    if (-not $caseMap.ContainsKey($entry.Key) -or -not $caseMap[$entry.Key].passed -or $caseMap[$entry.Key].observedDisposition -ne $entry.Value) { $caseFailures.Add($entry.Key) }
}
Add-Check -Id 'CORRIGENDUM::FIVE_CASE_UNITY_KNOWN_ANSWER' -Domain 'known-answer' -Passed ($known.passed -and $caseFailures.Count -eq 0 -and @($known.cases).Count -eq 5) -Observed ([ordered]@{status=$known.status;cases=@($known.cases).Count;failures=@($caseFailures)}) -Expected 'five required cases pass'

$adjudication = Read-Json -Path (Full-Path $expected.knownAnswerAdjudication[0])
Add-Check -Id 'CORRIGENDUM::TRUSTED_IDENTITY_NATURAL_EXIT_NO_RETRY' -Domain 'known-answer' -Passed ($adjudication.passed -and $adjudication.unityInvocationCount -eq 1 -and $adjudication.unityExitCode -eq 0 -and $adjudication.naturalExitObserved -and -not $adjudication.retryPerformed -and $adjudication.externalIdentity.prelaunchLiveStable -and $adjudication.externalIdentity.prelaunchPostExitStable) -Observed ([ordered]@{status=$adjudication.status;invocations=$adjudication.unityInvocationCount;exitCode=$adjudication.unityExitCode;retry=$adjudication.retryPerformed}) -Expected 'one algorithm-free natural-exit invocation with stable trusted identity and no retry'

$runnerText = Get-Content -LiteralPath (Full-Path $expected.runner[0]) -Raw -Encoding UTF8
$runnerSemantics = $runnerText.Contains('ReadQualificationScheduleJsonLines') -and $runnerText.Contains('Schedule replacement object is empty or incomplete: ') -and $runnerText.Contains('Schedule JSON contains duplicate top-level replacement members: ')
Add-Check -Id 'CORRIGENDUM::RUNNER_STRICT_RAW_TOKEN_PATH_PRESENT' -Domain 'source-static' -Passed $runnerSemantics -Observed $runnerSemantics -Expected $true

$contract = Read-Json -Path (Full-Path $expected.contract[0])
$contractHeader = $contract.schema -eq 'gate14re-me-load-qualification-execution-contract-v3' -and $contract.status -eq 'FROZEN_EXECUTION_BINDING_V3_TERMINAL_CHAIN_CORRECTED_QUALIFICATION_EXECUTION_UNAUTHORIZED' -and $contract.revision -eq '3.4'
Add-Check -Id 'CONTRACT::V3_4_HEADER_AND_UNAUTHORIZED_STATE' -Domain 'execution-contract' -Passed $contractHeader -Observed ([ordered]@{schema=$contract.schema;status=$contract.status;revision=$contract.revision}) -Expected ([ordered]@{schema='gate14re-me-load-qualification-execution-contract-v3';status='FROZEN_EXECUTION_BINDING_V3_TERMINAL_CHAIN_CORRECTED_QUALIFICATION_EXECUTION_UNAUTHORIZED';revision='3.4'})
$rootBindingsPass = $contract.reservedRoots.qualificationMeasuredRootRelativePath -ceq 'Research/PilotRuns/Gate14Re-ME/load-qualification/attempt-002' -and $contract.reservedRoots.completePerObservationDeliveryRootRelativePath -ceq 'Research/Exports/Gate14Re-ME/load-qualification/attempt-002' -and -not $contract.reservedRoots.resumeOverwriteMergeTopUpAllowed
Add-Check -Id 'CONTRACT::PROSPECTIVE_ATTEMPT_002_ROOTS' -Domain 'execution-contract' -Passed $rootBindingsPass -Observed $contract.reservedRoots -Expected 'attempt-002 measured/delivery roots and no resume/overwrite/merge/top-up'
$entryPass = $contract.entryPoint.supervisorRelativePath -ceq $expected.supervisor[0] -and $contract.entryPoint.supervisorSha256 -eq $expected.supervisor[1] -and $contract.entryPoint.runnerRelativePath -ceq $expected.runner[0] -and $contract.entryPoint.runnerSha256 -eq $expected.runner[1]
Add-Check -Id 'CONTRACT::SUPERVISOR_AND_RUNNER_BINDINGS' -Domain 'execution-contract' -Passed $entryPass -Observed $contract.entryPoint -Expected 'supervisor v3.2 and corrected RunnerV2 exact hashes'

$contractBindingFailures = [System.Collections.Generic.List[string]]::new()
foreach ($property in $contract.frozenBindings.PSObject.Properties) {
    $binding = $property.Value
    $actual = Get-Sha256Lower -Path (Full-Path ([string]$binding.relativePath))
    if ($actual -ne [string]$binding.sha256) { $contractBindingFailures.Add("$($property.Name):$actual") }
}
Add-Check -Id 'CONTRACT::ALL_FROZEN_BINDINGS_MATCH' -Domain 'execution-contract' -Passed ($contractBindingFailures.Count -eq 0) -Observed @($contractBindingFailures) -Expected 'all contract frozen bindings match'

$manifest = Read-Json -Path (Full-Path $expected.manifest[0])
$manifestHeader = $manifest.schema -eq 'gate14re-me-qualification-implementation-manifest-v1' -and $manifest.status -eq 'FROZEN_IMPLEMENTATION_SOURCE_ONLY_UNCOMPILED' -and $manifest.manifestGeneration -eq 4 -and $manifest.manifestSchemaV3 -eq 'gate14re-me-qualification-current-implementation-manifest-v3' -and $manifest.executionReadinessStatus -eq 'FROZEN_CURRENT_IMPLEMENTATION_COMPILED_TERMINAL_CHAIN_CORRECTED_POWERSHELL_7_6_5_HOST_BOUND_OFFLINE' -and $manifest.manifestRevision -eq '3.4'
Add-Check -Id 'MANIFEST::V3_4_COMPATIBILITY_AND_AUTHORITATIVE_STATE' -Domain 'implementation-manifest' -Passed $manifestHeader -Observed ([ordered]@{schema=$manifest.schema;legacyStatus=$manifest.status;generation=$manifest.manifestGeneration;authoritativeStatus=$manifest.executionReadinessStatus;revision=$manifest.manifestRevision}) -Expected 'legacy compatibility header plus authoritative v3.4 state'
$manifestIndex = @{}
$manifestArtifactFailures = [System.Collections.Generic.List[string]]::new()
$manifestDuplicatePaths = [System.Collections.Generic.List[string]]::new()
foreach ($artifact in @($manifest.artifacts)) {
    $relative = [string]$artifact.relativePath
    if ($manifestIndex.ContainsKey($relative)) { $manifestDuplicatePaths.Add($relative) }
    $manifestIndex[$relative] = [string]$artifact.sha256
    $full = Full-Path $relative
    $actualHash = Get-Sha256Lower -Path $full
    $expectedBytes = if ($null -ne $artifact.PSObject.Properties['bytes']) { [int64]$artifact.bytes } else { [int64]$artifact.lengthBytes }
    $actualBytes = if (Test-Path -LiteralPath $full -PathType Leaf) { [int64](Get-Item -LiteralPath $full).Length } else { -1 }
    if ($actualHash -ne [string]$artifact.sha256 -or $actualBytes -ne $expectedBytes) { $manifestArtifactFailures.Add("$relative|$actualHash|$actualBytes") }
}
Add-Check -Id 'MANIFEST::ALL_53_ARTIFACTS_HASH_AND_LENGTH_MATCH' -Domain 'implementation-manifest' -Passed (@($manifest.artifacts).Count -eq 53 -and $manifestArtifactFailures.Count -eq 0 -and $manifestDuplicatePaths.Count -eq 0) -Observed ([ordered]@{count=@($manifest.artifacts).Count;failures=@($manifestArtifactFailures);duplicates=@($manifestDuplicatePaths)}) -Expected ([ordered]@{count=53;failures=0;duplicates=0})
$manifestClosureFailures = [System.Collections.Generic.List[string]]::new()
foreach ($property in $contract.frozenBindings.PSObject.Properties) {
    $binding = $property.Value
    if (-not $manifestIndex.ContainsKey([string]$binding.relativePath) -or $manifestIndex[[string]$binding.relativePath] -ne [string]$binding.sha256) { $manifestClosureFailures.Add($property.Name) }
}
foreach ($pair in @($expected.supervisor, $expected.runner, $expected.contract, $expected.editorAssembly, $expected.runtimeAssembly)) {
    if (-not $manifestIndex.ContainsKey($pair[0]) -or $manifestIndex[$pair[0]] -ne $pair[1]) { $manifestClosureFailures.Add($pair[0]) }
}
Add-Check -Id 'MANIFEST::CONTRACT_AND_COMPILED_CHAIN_CLOSED' -Domain 'implementation-manifest' -Passed ($manifestClosureFailures.Count -eq 0) -Observed @($manifestClosureFailures) -Expected 'contract bindings, supervisor, runner, contract and assemblies all present with exact hashes'

$supervisorPath = Full-Path $expected.supervisor[0]
$tokens = $null
$parserErrors = $null
[System.Management.Automation.Language.Parser]::ParseFile($supervisorPath, [ref]$tokens, [ref]$parserErrors) | Out-Null
$supervisorText = Get-Content -LiteralPath $supervisorPath -Raw -Encoding UTF8
$supervisorRootPass = @($parserErrors).Count -eq 0 -and $supervisorText.Contains("`$reservedMeasuredRootRelativePath = 'Research/PilotRuns/Gate14Re-ME/load-qualification/attempt-002'") -and $supervisorText.Contains("`$reservedDeliveryRootRelativePath = 'Research/Exports/Gate14Re-ME/load-qualification/attempt-002'") -and -not $supervisorText.Contains('load-qualification/attempt-001')
Add-Check -Id 'SUPERVISOR::V3_2_PARSER_AND_ATTEMPT_002_ONLY_ROOT_GUARD' -Domain 'supervisor-static' -Passed $supervisorRootPass -Observed ([ordered]@{parserErrors=@($parserErrors).Count;attempt002Occurrences=([regex]::Matches($supervisorText,'load-qualification/attempt-002')).Count;attempt001Occurrences=([regex]::Matches($supervisorText,'load-qualification/attempt-001')).Count}) -Expected ([ordered]@{parserErrors=0;attempt002Occurrences=2;attempt001Occurrences=0})

$scheduleRows = @(Get-Content -LiteralPath (Full-Path $expected.schedule[0]) -Encoding UTF8 | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | ForEach-Object { $_ | ConvertFrom-Json -Depth 100 -DateKind String })
$algorithms = @('A*-R','BiA*-R','D*L','LPA*','C-FF','IDFF')
$lanes = @('ALG-A','ALG-B','ALG-C','ALG-D','ALG-E','ALG-F')
$scheduleFailures = [System.Collections.Generic.List[string]]::new()
$superblocks = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
$inputs = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
$positionCounts = @{}
foreach ($algorithm in $algorithms) { $positionCounts[$algorithm] = @(0,0,0,0,0,0) }
for ($i=0; $i -lt $scheduleRows.Count; $i++) {
    $row = $scheduleRows[$i]
    if ([int]$row.ordinal -ne $i -or $null -ne $row.replacement) { $scheduleFailures.Add("row-$i-header") }
    if (-not $superblocks.Add([string]$row.superblockId)) { $scheduleFailures.Add("row-$i-duplicate-superblock") }
    $order = @($row.algorithmOrder)
    if ($order.Count -ne 6 -or ((@($order.algorithmId | Sort-Object) -join '|') -cne (@($algorithms | Sort-Object) -join '|')) -or ((@($order.anonymousLaneId | Sort-Object) -join '|') -cne (@($lanes | Sort-Object) -join '|'))) { $scheduleFailures.Add("row-$i-order") }
    for ($position=0; $position -lt $order.Count; $position++) { $positionCounts[[string]$order[$position].algorithmId][$position]++ }
    $inputFull = Full-Path ([string]$row.inputRelativePath)
    if (-not $inputs.Add([string]$row.inputRelativePath) -or (Get-Sha256Lower -Path $inputFull) -ne [string]$row.inputSha256) { $scheduleFailures.Add("row-$i-input") }
    else {
        $bundle = Read-Json -Path $inputFull
        if ($bundle.superblockId -ne $row.superblockId -or @($bundle.eventGroups).Count -ne 24 -or @($bundle.eventGroups | Where-Object { $_.topology -ne $bundle.changeTopology }).Count -ne 0) { $scheduleFailures.Add("row-$i-bundle") }
    }
}
$williamsPass = $true
foreach ($algorithm in $algorithms) { if ((@($positionCounts[$algorithm]) | Where-Object { $_ -ne 27 }).Count -ne 0) { $williamsPass = $false } }
Add-Check -Id 'SCHEDULE::162_NULL_REPLACEMENT_ROWS_INPUTS_AND_WILLIAMS_BALANCE' -Domain 'schedule' -Passed ($scheduleRows.Count -eq 162 -and $superblocks.Count -eq 162 -and $inputs.Count -eq 162 -and $scheduleFailures.Count -eq 0 -and $williamsPass) -Observed ([ordered]@{rows=$scheduleRows.Count;superblocks=$superblocks.Count;inputs=$inputs.Count;failures=@($scheduleFailures);positionCounts=$positionCounts}) -Expected '162 unique rows/inputs, all replacement null, 24 topology-complete groups, each algorithm 27 times in each position'

$planning = Read-Json -Path (Full-Path $expected.planningManifest[0])
$planningFailures = [System.Collections.Generic.List[string]]::new()
foreach ($artifact in @($planning.artifacts)) {
    $full = Full-Path ([string]$artifact.relativePath)
    $actualHash = Get-Sha256Lower -Path $full
    $actualBytes = if (Test-Path -LiteralPath $full -PathType Leaf) { [int64](Get-Item -LiteralPath $full).Length } else { -1 }
    if ($actualHash -ne [string]$artifact.sha256 -or $actualBytes -ne [int64]$artifact.lengthBytes) { $planningFailures.Add([string]$artifact.relativePath) }
}
Add-Check -Id 'PLANNING::ALL_173_FROZEN_ASSETS_MATCH' -Domain 'planning-assets' -Passed ($planning.status -eq 'FROZEN_PLANNING_ASSETS_PASS' -and @($planning.artifacts).Count -eq 173 -and $planningFailures.Count -eq 0) -Observed ([ordered]@{status=$planning.status;count=@($planning.artifacts).Count;failures=@($planningFailures)}) -Expected ([ordered]@{status='FROZEN_PLANNING_ASSETS_PASS';count=173;failures=0})

$expectedCardinalities = [ordered]@{coreSuperblocks=144;stressSuperblocks=18;totalSuperblocks=162;algorithmLanesPerSuperblock=6;freshAlgorithmProcesses=972;oracleProcesses=162;emptyBoundaryProcesses=12;instrumentSelfTestProcesses=1;expectedTotalUnityProcessesWithoutFailure=1147;eventGroupsPerLane=24;eventGroupRows=23328;d3WindowsPerLane=25;processResourceRows=25272;emptyBoundaryRows=12000;persistentStateMeasurementPointsPerLane=26;acceptedSuperblockReceipts=162;processLedgerRows=1147;processIdentityReceipts=1147;supervisorFinalProcessOrdinal=1147}
$cardinalityFailures = [System.Collections.Generic.List[string]]::new()
foreach ($property in $expectedCardinalities.GetEnumerator()) { if ([int64]$contract.expectedCardinalities.($property.Key) -ne [int64]$property.Value) { $cardinalityFailures.Add($property.Key) } }
Add-Check -Id 'CARDINALITY::FROZEN_1147_PROCESS_CLOSURE' -Domain 'cardinality' -Passed ($cardinalityFailures.Count -eq 0) -Observed @($cardinalityFailures) -Expected $expectedCardinalities

$hostExecutable = [Environment]::ProcessPath
$hostHash = Get-Sha256Lower -Path $hostExecutable
$hostVersion = $PSVersionTable.PSVersion.ToString()
$convertFromJson = Get-Command ConvertFrom-Json
$hostPass = [System.IO.Path]::GetFullPath($hostExecutable) -ieq [System.IO.Path]::GetFullPath('C:\Users\bdscy\.cache\codex-runtimes\codex-primary-runtime\dependencies\native\powershell\pwsh.exe') -and $hostHash -eq '362a356ce7f0940ec74f73a8fc2c990a2cc24a38a11c90bbd8eca947110ad139' -and $hostVersion -eq '7.6.5' -and $convertFromJson.Parameters.ContainsKey('Depth') -and $convertFromJson.Parameters.ContainsKey('DateKind')
Add-Check -Id 'RUNTIME::PINNED_POWERSHELL_7_6_5' -Domain 'runtime' -Passed $hostPass -Observed ([ordered]@{path=$hostExecutable;sha256=$hostHash;version=$hostVersion;Depth=$convertFromJson.Parameters.ContainsKey('Depth');DateKind=$convertFromJson.Parameters.ContainsKey('DateKind')}) -Expected 'exact frozen PowerShell 7.6.5 host with ConvertFrom-Json Depth and DateKind'

$budget = Read-Json -Path (Full-Path 'Research/Gate14Re-ME/Execution/v1/load-qualification-resource-budget.v1.json')
$drive = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='H:'"
$requiredStorage = [int64]$budget.qualificationReservedStorageBytes + [int64]$budget.formalRawAndDeliveryReservedStorageBytes
$computer = Get-CimInstance Win32_ComputerSystem
$budgetPass = $budget.status -eq 'FROZEN_PREEXECUTION_BUDGETS' -and [int]$budget.maximumConcurrentUnityProcesses -eq 1 -and [int64]$drive.FreeSpace -ge $requiredStorage -and [int64]$computer.TotalPhysicalMemory -ge [int64]$budget.qualificationAssignedMemoryBytes
Add-Check -Id 'HOST::FROZEN_RUNTIME_BUDGET' -Domain 'runtime-budget' -Passed $budgetPass -Observed ([ordered]@{freeBytes=[int64]$drive.FreeSpace;requiredStorageBytes=$requiredStorage;memoryBytes=[int64]$computer.TotalPhysicalMemory;requiredMemoryBytes=[int64]$budget.qualificationAssignedMemoryBytes;concurrency=[int]$budget.maximumConcurrentUnityProcesses}) -Expected 'current host satisfies both storage reservations, assigned memory, and serial execution'

$terminalChainExpected = @(
    'write acquisition-complete.v2 with explicit 1147-process closure and no inference',
    'run structural-v3 qualification-full and require PASS_SCHEMA_V3_STRUCTURAL_COMPLETE_RAW_NO_INFERENCE',
    'run delivery-v2.2 schema-v3 adapter build to a new disjoint delivery root while preserving v2 delivery filenames',
    'run delivery-v2.2 verify and require PASS_VERIFIED_SCHEMA_V2_COMPLETE_PER_OBSERVATION_DELIVERY',
    'freeze qualification-complete.v2 declaring complete per-observation delivery and no analysis'
)
Add-Check -Id 'TERMINAL::STRUCTURAL_DELIVERY_NO_ANALYSIS_CHAIN' -Domain 'terminal-chain' -Passed ((@($contract.postAcquisitionTerminalChain) -join '|') -ceq ($terminalChainExpected -join '|')) -Observed @($contract.postAcquisitionTerminalChain) -Expected $terminalChainExpected

$authorizationBoundaryPass = -not $contract.currentAuthorization.qualificationExecutionAuthorized -and -not $contract.currentAuthorization.qualificationMeasuredRootCreationAuthorized -and -not $contract.currentAuthorization.deliveryRootCreationAuthorized -and -not $contract.currentAuthorization.formalCollectionAuthorized -and -not $contract.currentAuthorization.formalAnalysisAuthorized -and -not $contract.currentAuthorization.rankingAuthorized -and -not $contract.currentAuthorization.winnerAdjudicationAuthorized
Add-Check -Id 'BOUNDARY::EXECUTION_AND_ANALYSIS_REMAIN_UNAUTHORIZED' -Domain 'authorization-boundary' -Passed $authorizationBoundaryPass -Observed $contract.currentAuthorization -Expected 'qualification execution, root creation, formal collection/analysis, ranking and winner adjudication all false'

$completed = [DateTime]::UtcNow.ToString('o')
$failed = @($checks | Where-Object { -not $_.passed })
$result = [ordered]@{
    schema = 'gate14re-me-qualification-execution-readiness-recheck-audit-v7'
    studyId = 'Gate14Re-ME'
    protocolId = 'gate14re-me-load-qualification-v1'
    designId = 'gate14re-me-load-qualification-planning-v2'
    authorizationId = 'gate14re-me-qualification-schedule-null-replacement-deserialization-corrigendum-attempt-001'
    attemptId = 'qualification-execution-readiness-recheck-attempt-007'
    mode = 'READ_ONLY_NO_UNITY_STATIC_FROZEN_EVIDENCE_AND_HOST_METADATA'
    completedAtUtc = $completed
    status = if ($failed.Count -eq 0) { 'PASS_QUALIFICATION_EXECUTION_READINESS_RECHECK_V7_NULL_REPLACEMENT_CORRECTED_ATTEMPT_002_BOUND_EXECUTION_UNAUTHORIZED' } else { 'FAILED_CLOSED_QUALIFICATION_EXECUTION_READINESS_RECHECK_V7' }
    passed = $failed.Count -eq 0
    summary = [ordered]@{ totalChecks=$checks.Count; passedChecks=@($checks | Where-Object {$_.passed}).Count; failedChecks=$failed.Count }
    checks = @($checks)
    hardStopReasons = @($failed | ForEach-Object { $_.checkId })
    scientificBoundary = [ordered]@{
        unityInvocationCount = 0
        plannerInvocationCount = 0
        instrumentInvocationCount = 0
        oracleInvocationCount = 0
        emptyBoundaryInvocationCount = 0
        algorithmLaneExecutionCount = 0
        qualificationMeasuredRootCreated = $false
        deliveryRootCreated = $false
        qualificationObservationCount = 0
        formalObservationCount = 0
        formalCollectionPerformed = $false
        formalAnalysisPerformed = $false
        rankingWeightingOrWinnerAdjudicationPerformed = $false
        sealedIdentityMappingOpened = $false
    }
}
$result | ConvertTo-Json -Depth 100
if ($failed.Count -ne 0) { exit 2 }
