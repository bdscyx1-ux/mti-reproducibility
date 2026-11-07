[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ProjectRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-NormalizedPath {
    param([Parameter(Mandatory = $true)][string]$Path)
    return [System.IO.Path]::GetFullPath($Path).TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
}

function Get-Sha256Lower {
    param([Parameter(Mandatory = $true)][string]$Path)
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Write-TextExclusive {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Text
    )
    if (Test-Path -LiteralPath $Path) {
        throw "Overwrite prohibited: $Path"
    }
    $parent = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
        [System.IO.Directory]::CreateDirectory($parent) | Out-Null
    }
    $encoding = [System.Text.UTF8Encoding]::new($false)
    $stream = [System.IO.File]::Open($Path, [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
    try {
        $writer = [System.IO.StreamWriter]::new($stream, $encoding)
        try {
            $writer.Write($Text)
        }
        finally {
            $writer.Dispose()
        }
    }
    finally {
        $stream.Dispose()
    }
}

function Write-JsonExclusive {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)]$Value
    )
    $json = $Value | ConvertTo-Json -Depth 100
    Write-TextExclusive -Path $Path -Text ($json + "`n")
}

function Read-JsonStrict {
    param([Parameter(Mandatory = $true)][string]$Path)
    return Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json -Depth 100 -DateKind String
}

function Get-ProjectRelativePath {
    param([Parameter(Mandatory = $true)][string]$Path)
    $full = Get-NormalizedPath -Path $Path
    if (-not $full.StartsWith($script:ProjectRootFull + [System.IO.Path]::DirectorySeparatorChar, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Path is outside project root: $Path"
    }
    return $full.Substring($script:ProjectRootFull.Length + 1).Replace('\', '/')
}

function Require-Condition {
    param(
        [Parameter(Mandatory = $true)][bool]$Condition,
        [Parameter(Mandatory = $true)][string]$CheckId,
        [Parameter(Mandatory = $true)]$Observed,
        [Parameter(Mandatory = $true)]$Expected
    )
    $record = [ordered]@{
        checkId = $CheckId
        passed = $Condition
        observed = $Observed
        expected = $Expected
    }
    $script:Checks.Add([pscustomobject]$record) | Out-Null
    if (-not $Condition) {
        throw "[$CheckId] expected '$Expected' but observed '$Observed'."
    }
}

function Get-FileInventory {
    param([Parameter(Mandatory = $true)][string]$Root)
    $rootFull = Get-NormalizedPath -Path $Root
    return @(
        Get-ChildItem -LiteralPath $rootFull -File -Recurse |
            Sort-Object FullName |
            ForEach-Object {
                [pscustomobject][ordered]@{
                    relativePath = $_.FullName.Substring($rootFull.Length + 1).Replace('\', '/')
                    bytes = [int64]$_.Length
                    sha256 = Get-Sha256Lower -Path $_.FullName
                    readOnly = [bool]$_.IsReadOnly
                }
            }
    )
}

function Get-UnityProcessSnapshot {
    return @(
        Get-CimInstance Win32_Process |
            Where-Object { $_.Name -ieq 'Unity.exe' } |
            Sort-Object ProcessId |
            ForEach-Object {
                [pscustomobject][ordered]@{
                    pid = [int]$_.ProcessId
                    executablePath = [string]$_.ExecutablePath
                    creationDate = if ($null -eq $_.CreationDate) { $null } else { ([System.Management.ManagementDateTimeConverter]::ToDateTime([string]$_.CreationDate)).ToUniversalTime().ToString('o') }
                    commandLine = [string]$_.CommandLine
                }
            }
    )
}

function Set-FilesReadOnly {
    param([Parameter(Mandatory = $true)][string[]]$Paths)
    foreach ($path in $Paths | Sort-Object -Unique) {
        if (Test-Path -LiteralPath $path -PathType Leaf) {
            $item = Get-Item -LiteralPath $path
            $item.IsReadOnly = $true
        }
    }
}

function New-FreezeArtifact {
    param(
        [Parameter(Mandatory = $true)][string]$Role,
        [Parameter(Mandatory = $true)][string]$Path
    )
    $item = Get-Item -LiteralPath $Path
    return [pscustomobject][ordered]@{
        role = $Role
        relativePath = Get-ProjectRelativePath -Path $item.FullName
        sha256 = Get-Sha256Lower -Path $item.FullName
        bytes = [int64]$item.Length
    }
}

$script:ProjectRootFull = Get-NormalizedPath -Path $ProjectRoot
$expectedProjectRoot = Get-NormalizedPath -Path 'H:/DDM_Final_Project'
if (-not $script:ProjectRootFull.Equals($expectedProjectRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "Project root mismatch: $script:ProjectRootFull"
}

$script:Checks = [System.Collections.Generic.List[object]]::new()
$attemptId = 'supervisor-powershell-host-binding-corrigendum-attempt-002'
$authorizationId = 'gate14re-me-supervisor-powershell-host-binding-corrigendum-attempt-002'
$stageRoot = Join-Path $script:ProjectRootFull 'Research/Verification/Gate14Re-ME/supervisor-powershell-host-binding-corrigendum-attempt-002'
$scriptPath = Join-Path $stageRoot 'Invoke-Gate14ReMESupervisorPowerShellHostBindingCorrigendumAttempt002.ps1'
$authorizationPath = Join-Path $stageRoot 'authorization-receipt.v1.json'
$stageContractPath = Join-Path $stageRoot 'stage-contract.v1.json'
$fixtureJsonPath = Join-Path $stageRoot 'powershell-json-known-answer-fixture.v1.json'
$fixtureJsonlPath = Join-Path $stageRoot 'powershell-jsonl-known-answer-fixture.v1.jsonl'
$invalidJsonPath = Join-Path $stageRoot 'powershell-invalid-json-negative-fixture.v1.txt'
$bindingReceiptPath = Join-Path $stageRoot 'supervisor-parameter-binding-known-answer.v1.json'
$knownAnswerPath = Join-Path $stageRoot 'powershell-known-answer-receipt.v1.json'
$terminalReceiptPath = Join-Path $stageRoot 'terminal-pass-receipt.v1.json'
$failureReceiptPath = Join-Path $stageRoot 'failure-receipt.v1.json'
$freezeManifestPath = Join-Path $stageRoot 'freeze-manifest.v1.json'

$baseContractPath = Join-Path $script:ProjectRootFull 'Research/Gate14Re-ME/Execution/v3/load-qualification-execution-contract.v3_1.json'
$newContractPath = Join-Path $script:ProjectRootFull 'Research/Gate14Re-ME/Execution/v3/load-qualification-execution-contract.v3_2.json'
$baseManifestPath = Join-Path $script:ProjectRootFull 'Research/Gate14Re-ME/Execution/v3/load-qualification-current-implementation-manifest.v3_1.json'
$newManifestPath = Join-Path $script:ProjectRootFull 'Research/Gate14Re-ME/Execution/v3/load-qualification-current-implementation-manifest.v3_2.json'
$supervisorPath = Join-Path $script:ProjectRootFull 'Research/Gate14Re-ME/Execution/v3/Run-Gate14ReMELoadQualification.v3.ps1'
$runnerPath = Join-Path $script:ProjectRootFull 'Assets/_Scripts/Research/Editor/Gate14ReMELoadQualificationRunnerV2.cs'
$oldAttemptRoot = Join-Path $script:ProjectRootFull 'Research/Verification/Gate14Re-ME/load-qualification-execution-attempt-001'
$oldFailurePath = Join-Path $oldAttemptRoot 'failure-receipt.v1.json'
$oldFreezePath = Join-Path $oldAttemptRoot 'freeze-manifest.v1.json'
$statusV30Path = Join-Path $script:ProjectRootFull 'Research/Gate14Re-ME/Gate14Re_ME_Status.v30.json'
$statusV31Path = Join-Path $script:ProjectRootFull 'Research/Gate14Re-ME/Gate14Re_ME_Status.v31.json'
$pwshPath = Get-NormalizedPath -Path 'C:/Users/bdscy/.cache/codex-runtimes/codex-primary-runtime/dependencies/native/powershell/pwsh.exe'
$measuredRoot = Join-Path $script:ProjectRootFull 'Research/PilotRuns/Gate14Re-ME/load-qualification/attempt-001'
$deliveryRoot = Join-Path $script:ProjectRootFull 'Research/Exports/Gate14Re-ME/load-qualification/attempt-001'
$formalRoot = Join-Path $script:ProjectRootFull 'Research/FormalRuns/Gate14Re-ME'

$expectedPwshSha256 = '362a356ce7f0940ec74f73a8fc2c990a2cc24a38a11c90bbd8eca947110ad139'
$expectedPwshVersion = '7.6.5'
$expectedBaseContractSha256 = 'f1fa4b7c10ebdbfacc6a4f82a68d4ae1ca0a94fa18af929d6a74eb0ad39cf801'
$expectedBaseManifestSha256 = 'af0b370258c2bce8b51cd6215c5c790dda6727a3a3eb581fa21713950d53bdf6'
$expectedSupervisorSha256 = 'e672d2bc3e584192d1f9850ed2bb76538ba11fead80e1ce94670febd9fb45035'
$expectedRunnerSha256 = '39d371a5a9e858836bc448aabb04656e8576e296ca9b1cedb479cd3552ad1d73'
$expectedStatusV30Sha256 = 'aae1979990bd9b7e2bfce320f1a301abba8eeb5c0efc62bebd41ef5a42d5ed3b'
$expectedOldFailureSha256 = '9f4d79f100bfe41018bb9972c6cf085ac275845391a1a1450cc1ff7bffd2822d'
$expectedOldFreezeSha256 = '511604d503de30ffcabbeb1734157b85984348604f0dd8f2fcf2bc3fb39d73af'

$expectedOldInventory = [ordered]@{
    'authorization-receipt.v1.json' = 'b11046e20e0988c078d757a931b4a3a4f9d210ad8d94e5b831dbf79856dfe622'
    'failure-receipt.v1.json' = '9f4d79f100bfe41018bb9972c6cf085ac275845391a1a1450cc1ff7bffd2822d'
    'freeze-manifest.v1.json' = '511604d503de30ffcabbeb1734157b85984348604f0dd8f2fcf2bc3fb39d73af'
    'prelaunch-runtime-compatibility-audit.v1.json' = '8259ad9c4c09a6b1e8e6e43cc3d5e38cb27afb6c8401c28bae600d9bfdac097d'
    'stage-contract.v1.json' = '8c21d225c67c702ef0c4b67fdc23805d5776ed9161aff6c2e4a6f7899dffa8eb'
    'status-adoption-receipt.v1.json' = '5ca5c6e6724098cdd933bc10f9cead3cf3f08615578bdfae946094414785bdeb'
}

$userAuthorizationTextExact = @'
单独授权 Gate14Re‑ME supervisor PowerShell host binding corrigendum attempt‑002：完整保留 supervisor PowerShell host binding corrigendum attempt‑001 的失败状态、failure receipt、freeze manifest、冻结编排器和全部证据，不删除、不修改、不改判；不得重用或续跑 attempt‑001。仅允许创建独立 attempt‑002，将编排器中 Unity 进程快照的两个调用点规范化为 $unityBefore = @(Get-UnityProcessSnapshot) 与 $unityAfter = @(Get-UnityProcessSnapshot)，冻结修复后编排器源码及哈希；不得修改其他 known-answer 判定、版本化合同内容、实现清单内容、supervisor v3、RunnerV2、compiled assemblies、input schema、schedule、sealed identity、仪器合同、算法实现、structural‑v3.1 或 delivery‑v2.2。仅允许使用 C:/Users/bdscy/.cache/codex-runtimes/codex-primary-runtime/dependencies/native/powershell/pwsh.exe、SHA‑256 362a356ce7f0940ec74f73a8fc2c990a2cc24a38a11c90bbd8eca947110ad139、版本 7.6.5 执行一次原定的无 Unity PowerShell known-answer；全部断言通过后才允许生成并冻结 execution contract v3.2、implementation manifest v3.2、terminal PASS receipt 与 Status v31。失败时保留并冻结全部证据后停止，不自动重试。仍禁止启动 Unity，禁止创建 qualification measured root、delivery root 或 formal root，禁止 instrument、oracle、empty-boundary、算法 lane、qualification/formal observation、正式采集、正式分析、排名、加权及赢家裁决，也不得创建新的 qualification execution attempt。
'@

$startedAtUtc = [DateTimeOffset]::UtcNow.ToString('o')
$oldInventoryBefore = $null
$rootStateBefore = $null
$unityBefore = $null
$newContractSha256 = $null
$newManifestSha256 = $null

try {
    Require-Condition -Condition (Test-Path -LiteralPath $stageRoot -PathType Container) -CheckId 'attempt-directory-exists' -Observed (Test-Path -LiteralPath $stageRoot) -Expected $true
    $initialAttemptFiles = @(Get-ChildItem -LiteralPath $stageRoot -File -Recurse)
    Require-Condition -Condition ($initialAttemptFiles.Count -eq 1 -and $initialAttemptFiles[0].FullName -eq $scriptPath) -CheckId 'attempt-directory-pristine-except-orchestrator' -Observed ($initialAttemptFiles.FullName -join ';') -Expected $scriptPath
    foreach ($target in @($authorizationPath, $stageContractPath, $fixtureJsonPath, $fixtureJsonlPath, $invalidJsonPath, $bindingReceiptPath, $knownAnswerPath, $terminalReceiptPath, $failureReceiptPath, $freezeManifestPath, $newContractPath, $newManifestPath, $statusV31Path)) {
        Require-Condition -Condition (-not (Test-Path -LiteralPath $target)) -CheckId ('target-absent-' + [System.IO.Path]::GetFileName($target)) -Observed (Test-Path -LiteralPath $target) -Expected $false
    }

    Require-Condition -Condition ((Get-Sha256Lower -Path $statusV30Path) -eq $expectedStatusV30Sha256) -CheckId 'status-v30-hash-retained' -Observed (Get-Sha256Lower -Path $statusV30Path) -Expected $expectedStatusV30Sha256
    Require-Condition -Condition ((Get-Sha256Lower -Path $oldFailurePath) -eq $expectedOldFailureSha256) -CheckId 'attempt001-failure-hash-retained' -Observed (Get-Sha256Lower -Path $oldFailurePath) -Expected $expectedOldFailureSha256
    Require-Condition -Condition ((Get-Sha256Lower -Path $oldFreezePath) -eq $expectedOldFreezeSha256) -CheckId 'attempt001-freeze-hash-retained' -Observed (Get-Sha256Lower -Path $oldFreezePath) -Expected $expectedOldFreezeSha256

    $oldInventoryBefore = Get-FileInventory -Root $oldAttemptRoot
    Require-Condition -Condition ($oldInventoryBefore.Count -eq $expectedOldInventory.Count) -CheckId 'attempt001-file-count-retained' -Observed $oldInventoryBefore.Count -Expected $expectedOldInventory.Count
    foreach ($entry in $oldInventoryBefore) {
        $expectedHash = [string]$expectedOldInventory[$entry.relativePath]
        Require-Condition -Condition (-not [string]::IsNullOrWhiteSpace($expectedHash) -and $entry.sha256 -eq $expectedHash) -CheckId ('attempt001-file-hash-' + $entry.relativePath) -Observed $entry.sha256 -Expected $expectedHash
        Require-Condition -Condition $entry.readOnly -CheckId ('attempt001-file-readonly-' + $entry.relativePath) -Observed $entry.readOnly -Expected $true
    }

    $unityBefore = @(Get-UnityProcessSnapshot)
    Require-Condition -Condition ($unityBefore.Count -eq 0) -CheckId 'unity-process-count-before' -Observed $unityBefore.Count -Expected 0
    $rootStateBefore = [pscustomobject][ordered]@{
        qualificationMeasuredRootExists = Test-Path -LiteralPath $measuredRoot
        deliveryRootExists = Test-Path -LiteralPath $deliveryRoot
        formalRootExists = Test-Path -LiteralPath $formalRoot
    }
    Require-Condition -Condition (-not $rootStateBefore.qualificationMeasuredRootExists) -CheckId 'qualification-measured-root-absent-before' -Observed $rootStateBefore.qualificationMeasuredRootExists -Expected $false
    Require-Condition -Condition (-not $rootStateBefore.deliveryRootExists) -CheckId 'delivery-root-absent-before' -Observed $rootStateBefore.deliveryRootExists -Expected $false

    $currentProcessPath = Get-NormalizedPath -Path ([Environment]::ProcessPath)
    Require-Condition -Condition ($currentProcessPath.Equals($pwshPath, [System.StringComparison]::OrdinalIgnoreCase)) -CheckId 'exact-pwsh-process-path' -Observed $currentProcessPath -Expected $pwshPath
    $observedPwshSha256 = Get-Sha256Lower -Path $currentProcessPath
    Require-Condition -Condition ($observedPwshSha256 -eq $expectedPwshSha256) -CheckId 'exact-pwsh-sha256' -Observed $observedPwshSha256 -Expected $expectedPwshSha256
    $observedPwshVersion = $PSVersionTable.PSVersion.ToString()
    Require-Condition -Condition ($observedPwshVersion -eq $expectedPwshVersion) -CheckId 'exact-pwsh-version' -Observed $observedPwshVersion -Expected $expectedPwshVersion
    $convertCommand = Get-Command ConvertFrom-Json -CommandType Cmdlet
    Require-Condition -Condition $convertCommand.Parameters.ContainsKey('Depth') -CheckId 'convertfrom-json-depth-parameter' -Observed ($convertCommand.Parameters.Keys -contains 'Depth') -Expected $true
    Require-Condition -Condition $convertCommand.Parameters.ContainsKey('DateKind') -CheckId 'convertfrom-json-datekind-parameter' -Observed ($convertCommand.Parameters.Keys -contains 'DateKind') -Expected $true

    Require-Condition -Condition ((Get-Sha256Lower -Path $baseContractPath) -eq $expectedBaseContractSha256) -CheckId 'base-contract-v3_1-hash' -Observed (Get-Sha256Lower -Path $baseContractPath) -Expected $expectedBaseContractSha256
    Require-Condition -Condition ((Get-Sha256Lower -Path $baseManifestPath) -eq $expectedBaseManifestSha256) -CheckId 'base-manifest-v3_1-hash' -Observed (Get-Sha256Lower -Path $baseManifestPath) -Expected $expectedBaseManifestSha256
    Require-Condition -Condition ((Get-Sha256Lower -Path $supervisorPath) -eq $expectedSupervisorSha256) -CheckId 'supervisor-v3-hash-unchanged' -Observed (Get-Sha256Lower -Path $supervisorPath) -Expected $expectedSupervisorSha256
    Require-Condition -Condition ((Get-Sha256Lower -Path $runnerPath) -eq $expectedRunnerSha256) -CheckId 'runnerv2-hash-unchanged' -Observed (Get-Sha256Lower -Path $runnerPath) -Expected $expectedRunnerSha256

    $baseContract = Read-JsonStrict -Path $baseContractPath
    $baseManifest = Read-JsonStrict -Path $baseManifestPath
    foreach ($artifact in @($baseManifest.artifacts)) {
        $artifactPath = Join-Path $script:ProjectRootFull ([string]$artifact.relativePath)
        Require-Condition -Condition (Test-Path -LiteralPath $artifactPath -PathType Leaf) -CheckId ('base-artifact-exists-' + [string]$artifact.relativePath) -Observed (Test-Path -LiteralPath $artifactPath) -Expected $true
        $artifactHash = Get-Sha256Lower -Path $artifactPath
        Require-Condition -Condition ($artifactHash -eq [string]$artifact.sha256) -CheckId ('base-artifact-hash-' + [string]$artifact.relativePath) -Observed $artifactHash -Expected ([string]$artifact.sha256)
    }

    Write-JsonExclusive -Path $authorizationPath -Value ([ordered]@{
        schema = 'gate14re-me-supervisor-powershell-host-binding-corrigendum-attempt-002-user-authorization-receipt-v1'
        studyId = 'Gate14Re-ME'
        protocolId = 'gate14re-me-load-qualification-v1'
        authorizationId = $authorizationId
        attemptId = $attemptId
        status = 'AUTHORIZED_OFFLINE_POWERSHELL_HOST_BINDING_CORRIGENDUM_ONLY'
        authorizedAtUtc = $startedAtUtc
        authorizationSource = 'user-selected response annotation'
        userAuthorizationTextExact = $userAuthorizationTextExact.TrimEnd("`r", "`n")
        exactHostRuntime = [ordered]@{
            executablePath = $pwshPath.Replace('\', '/')
            sha256 = $expectedPwshSha256
            version = $expectedPwshVersion
        }
        explicitProhibitions = @(
            'Unity invocation', 'qualification measured root creation', 'delivery root creation', 'formal root creation',
            'instrument execution', 'oracle execution', 'empty-boundary execution', 'algorithm lane execution',
            'qualification observation', 'formal observation', 'formal collection', 'formal analysis',
            'ranking', 'weighting', 'winner adjudication', 'automatic retry', 'new qualification execution attempt'
        )
    })

    Write-JsonExclusive -Path $stageContractPath -Value ([ordered]@{
        schema = 'gate14re-me-supervisor-powershell-host-binding-corrigendum-attempt-002-stage-contract-v1'
        studyId = 'Gate14Re-ME'
        authorizationId = $authorizationId
        attemptId = $attemptId
        status = 'FROZEN_OFFLINE_HOST_BINDING_CORRIGENDUM_SCOPE'
        createdAtUtc = [DateTimeOffset]::UtcNow.ToString('o')
        retainedFailure = [ordered]@{
            relativePath = Get-ProjectRelativePath -Path $oldFailurePath
            sha256 = $expectedOldFailureSha256
            statusRetained = 'FAILED_CLOSED_PRELAUNCH_FROZEN_POWERSHELL_RUNTIME_INCOMPATIBLE'
            modifiedOrReclassified = $false
        }
        permittedOutputs = @(
            'versioned execution contract v3.2',
            'versioned current implementation manifest v3.2',
            'one no-Unity PowerShell known-answer evidence package',
            'terminal PASS receipt only if every assertion passes',
            'Status v31 only if every assertion passes'
        )
        immutableAssets = @(
            'supervisor v3', 'RunnerV2', 'compiled assemblies', 'input schema v2', 'planning schema binding v2',
            '162-row schedule', 'sealed identity', 'instrument contract v3', 'qualified D3-v3.1',
            'all six algorithm implementations', 'structural-v3.1', 'delivery-v2.2'
        )
        invocationBudget = [ordered]@{
            powershellKnownAnswerProcesses = 1
            unityProcesses = 0
            plannerInvocations = 0
            algorithmLaneExecutions = 0
        }
        retryPolicy = 'NO_AUTOMATIC_RETRY_FAIL_CLOSED'
    })

    $timestampText = '2024-06-11T11:26:54.0000000Z'
    $fixtureJson = @"
{
  "schema": "gate14re-me-powershell-host-json-known-answer-fixture-v1",
  "timestamp": "$timestampText",
  "level01": { "level02": { "level03": { "level04": { "level05": { "level06": { "level07": { "level08": { "level09": { "level10": { "value": 73 } } } } } } } } } },
  "values": [1, 2, 3]
}
"@
    Write-TextExclusive -Path $fixtureJsonPath -Text ($fixtureJson.TrimStart("`r", "`n").TrimEnd("`r", "`n") + "`n")
    $fixtureObject = Read-JsonStrict -Path $fixtureJsonPath
    Require-Condition -Condition ($fixtureObject.level01.level02.level03.level04.level05.level06.level07.level08.level09.level10.value -eq 73) -CheckId 'json-depth-100-deep-value' -Observed $fixtureObject.level01.level02.level03.level04.level05.level06.level07.level08.level09.level10.value -Expected 73
    Require-Condition -Condition ($fixtureObject.timestamp -is [string]) -CheckId 'datetimeoffset-remains-string-type' -Observed $fixtureObject.timestamp.GetType().FullName -Expected 'System.String'
    Require-Condition -Condition ([string]$fixtureObject.timestamp -ceq $timestampText) -CheckId 'datetimeoffset-text-exactly-preserved' -Observed ([string]$fixtureObject.timestamp) -Expected $timestampText

    $jsonlLines = @(
        '{"schema":"gate14re-me-powershell-host-jsonl-known-answer-row-v1","ordinal":1,"timestamp":"2024-06-11T11:26:54Z","payload":{"kind":"alpha"}}',
        '{"schema":"gate14re-me-powershell-host-jsonl-known-answer-row-v1","ordinal":2,"timestamp":"2024-06-11T11:26:54.0000000Z","payload":{"kind":"beta"}}',
        '{"schema":"gate14re-me-powershell-host-jsonl-known-answer-row-v1","ordinal":3,"timestamp":"2024-06-11T11:26:54+00:00","payload":{"kind":"gamma"}}'
    )
    Write-TextExclusive -Path $fixtureJsonlPath -Text (($jsonlLines -join "`n") + "`n")
    $jsonlRows = @(Get-Content -LiteralPath $fixtureJsonlPath -Encoding UTF8 | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | ForEach-Object { $_ | ConvertFrom-Json -Depth 100 -DateKind String })
    Require-Condition -Condition ($jsonlRows.Count -eq 3) -CheckId 'jsonl-row-count' -Observed $jsonlRows.Count -Expected 3
    Require-Condition -Condition (($jsonlRows.ordinal -join ',') -eq '1,2,3') -CheckId 'jsonl-ordinal-sequence' -Observed ($jsonlRows.ordinal -join ',') -Expected '1,2,3'
    Require-Condition -Condition (($jsonlRows | Where-Object { -not ($_.timestamp -is [string]) }).Count -eq 0) -CheckId 'jsonl-datetimeoffset-values-remain-strings' -Observed (($jsonlRows | ForEach-Object { $_.timestamp.GetType().FullName }) -join ',') -Expected 'System.String,System.String,System.String'

    Write-TextExclusive -Path $invalidJsonPath -Text ('{"schema":"broken",]' + "`n")
    $invalidJsonRejected = $false
    $invalidJsonError = $null
    try {
        Get-Content -LiteralPath $invalidJsonPath -Raw -Encoding UTF8 | ConvertFrom-Json -Depth 100 -DateKind String -ErrorAction Stop | Out-Null
    }
    catch {
        $invalidJsonRejected = $true
        $invalidJsonError = $_.Exception.Message
    }
    Require-Condition -Condition $invalidJsonRejected -CheckId 'invalid-json-fails-closed' -Observed $invalidJsonRejected -Expected $true
    Require-Condition -Condition (-not [string]::IsNullOrWhiteSpace($invalidJsonError)) -CheckId 'invalid-json-error-captured' -Observed $invalidJsonError -Expected 'non-empty parse error'

    $invalidJsonlRejected = $false
    $invalidJsonlError = $null
    try {
        '{"ordinal":4,"timestamp":}' | ConvertFrom-Json -Depth 100 -DateKind String -ErrorAction Stop | Out-Null
    }
    catch {
        $invalidJsonlRejected = $true
        $invalidJsonlError = $_.Exception.Message
    }
    Require-Condition -Condition $invalidJsonlRejected -CheckId 'invalid-jsonl-row-fails-closed' -Observed $invalidJsonlRejected -Expected $true

    $tokens = $null
    $parseErrors = $null
    $supervisorAst = [System.Management.Automation.Language.Parser]::ParseFile($supervisorPath, [ref]$tokens, [ref]$parseErrors)
    Require-Condition -Condition ($parseErrors.Count -eq 0) -CheckId 'supervisor-v3-ast-parse-errors' -Observed $parseErrors.Count -Expected 0
    $expectedSupervisorParameters = @(
        'ProjectRoot', 'MeasuredRoot', 'DeliveryRoot', 'ExecutionAuthorization', 'ExecutionAuthorizationSha256',
        'ImplementationManifest', 'ImplementationManifestSha256', 'ExecutionContract', 'ExecutionContractSha256',
        'PlanningAssetsManifest', 'PlanningAssetsManifestSha256', 'ResourceBudget', 'ResourceBudgetSha256',
        'FairnessBinding', 'FairnessBindingSha256', 'Schedule', 'ScheduleSha256', 'OutputSchema', 'OutputSchemaSha256',
        'InstrumentContract', 'InstrumentContractSha256', 'D3Contract', 'D3ContractSha256',
        'TypedParquetRuntimeManifest', 'TypedParquetRuntimeManifestSha256', 'StructuralTool', 'StructuralToolSha256',
        'DeliveryTool', 'DeliveryToolSha256', 'TrustedIdentityRule', 'TrustedIdentityRuleSha256',
        'TimestampComparator', 'TimestampComparatorSha256', 'PythonExecutable', 'PythonExecutableSha256',
        'UnityExecutable', 'UnityExecutableSha256'
    )
    $actualSupervisorParameters = @($supervisorAst.ParamBlock.Parameters | ForEach-Object { $_.Name.VariablePath.UserPath })
    Require-Condition -Condition (($actualSupervisorParameters -join '|') -eq ($expectedSupervisorParameters -join '|')) -CheckId 'supervisor-v3-parameter-order-and-membership' -Observed ($actualSupervisorParameters -join '|') -Expected ($expectedSupervisorParameters -join '|')
    $allMandatory = $true
    foreach ($parameterAst in $supervisorAst.ParamBlock.Parameters) {
        $parameterText = $parameterAst.Extent.Text
        if ($parameterText -notmatch '\[Parameter\s*\(\s*Mandatory\s*=\s*\$true\s*\)\s*\]') {
            $allMandatory = $false
            break
        }
    }
    Require-Condition -Condition $allMandatory -CheckId 'supervisor-v3-all-parameters-mandatory' -Observed $allMandatory -Expected $true
    $supervisorSource = Get-Content -LiteralPath $supervisorPath -Raw -Encoding UTF8
    $strictJsonExpression = 'ConvertFrom-Json -Depth 100 -DateKind String'
    $strictJsonExpressionCount = [regex]::Matches($supervisorSource, [regex]::Escape($strictJsonExpression)).Count
    Require-Condition -Condition ($strictJsonExpressionCount -eq 3) -CheckId 'supervisor-v3-strict-json-expression-count' -Observed $strictJsonExpressionCount -Expected 3

    $contract = Read-JsonStrict -Path $baseContractPath
    $baseFrozenBindingsJson = $contract.frozenBindings | ConvertTo-Json -Depth 100 -Compress
    $baseEntryPointJson = $contract.entryPoint | ConvertTo-Json -Depth 100 -Compress
    $baseExpectedCardinalitiesJson = $contract.expectedCardinalities | ConvertTo-Json -Depth 100 -Compress
    $contract.createdLocalDate = '2026-10-18'
    $contract.activationRule = 'This v3.2 contract and unchanged supervisor v3 remain inert until a separate offline execution-readiness PASS and then a separate exact-hash qualification execution authorization bind this contract and manifest.'
    $contract.supersedes = [pscustomobject][ordered]@{
        relativePath = Get-ProjectRelativePath -Path $baseContractPath
        sha256 = $expectedBaseContractSha256
        modifiedOrReclassified = $false
    }
    $contract.failClosedRules = @($contract.failClosedRules) + @(
        'The supervisor must be launched only by the exact frozen PowerShell 7.6.5 host runtime path and SHA-256 in supervisorHostRuntime; any path, hash, version or ConvertFrom-Json capability mismatch stops before root creation or Unity launch.'
    )
    $contract.currentAuthorization | Add-Member -NotePropertyName hostBindingCorrigendumAuthorized -NotePropertyValue $true -Force
    $contract.currentAuthorization | Add-Member -NotePropertyName offlinePowerShellKnownAnswerAuthorized -NotePropertyValue $true -Force
    $contract.currentAuthorization.unityInvocationAuthorized = $false
    $contract.currentAuthorization.qualificationMeasuredRootCreationAuthorized = $false
    $contract.currentAuthorization.deliveryRootCreationAuthorized = $false
    $contract.currentAuthorization.qualificationExecutionAuthorized = $false
    $contract.currentAuthorization.formalCollectionAuthorized = $false
    $contract.currentAuthorization.formalAnalysisAuthorized = $false
    $contract.currentAuthorization.rankingAuthorized = $false
    $contract.currentAuthorization.winnerAdjudicationAuthorized = $false
    $contract | Add-Member -NotePropertyName revision -NotePropertyValue '3.2' -Force
    $contract | Add-Member -NotePropertyName hostBindingCorrigendumAuthorizationId -NotePropertyValue $authorizationId -Force
    $contract | Add-Member -NotePropertyName hostBindingCorrigendumAttemptId -NotePropertyValue $attemptId -Force
    $contract | Add-Member -NotePropertyName retainedLoadQualificationExecutionAttempt001Failure -NotePropertyValue ([pscustomobject][ordered]@{
        relativePath = Get-ProjectRelativePath -Path $oldFailurePath
        sha256 = $expectedOldFailureSha256
        statusRetained = 'FAILED_CLOSED_PRELAUNCH_FROZEN_POWERSHELL_RUNTIME_INCOMPATIBLE'
        statusV30RelativePath = Get-ProjectRelativePath -Path $statusV30Path
        statusV30Sha256 = $expectedStatusV30Sha256
        modifiedOrReclassified = $false
    }) -Force
    $contract | Add-Member -NotePropertyName supervisorHostRuntime -NotePropertyValue ([pscustomobject][ordered]@{
        executablePath = $pwshPath.Replace('\', '/')
        sha256 = $expectedPwshSha256
        version = $expectedPwshVersion
        commandPrefix = @('-NoLogo', '-NoProfile', '-NonInteractive', '-File')
        requiredCmdlet = 'ConvertFrom-Json'
        requiredParameters = @('Depth', 'DateKind')
        requiredInvocationForm = 'ConvertFrom-Json -Depth 100 -DateKind String'
        exactExecutablePathHashAndVersionRequired = $true
        externalSupervisorLaunchMustUseExactExecutable = $true
        partOfUnityExecutableIdentity = $false
        mismatchDisposition = 'FAIL_CLOSED_BEFORE_ROOT_CREATION_OR_UNITY_LAUNCH'
    }) -Force
    $contract | Add-Member -NotePropertyName hostBindingCorrigendum -NotePropertyValue ([pscustomobject][ordered]@{
        scientificDesignChanged = $false
        supervisorV3Changed = $false
        runnerV2Changed = $false
        compiledAssembliesChanged = $false
        inputSchemaChanged = $false
        scheduleChanged = $false
        sealedIdentityChanged = $false
        instrumentContractChanged = $false
        algorithmImplementationsChanged = $false
        structuralV31Changed = $false
        deliveryV22Changed = $false
        unityInvocationCount = 0
        qualificationObservationCount = 0
        formalObservationCount = 0
    }) -Force

    Require-Condition -Condition (($contract.frozenBindings | ConvertTo-Json -Depth 100 -Compress) -ceq $baseFrozenBindingsJson) -CheckId 'contract-scientific-frozen-bindings-byte-semantic-unchanged' -Observed ($contract.frozenBindings | ConvertTo-Json -Depth 100 -Compress) -Expected $baseFrozenBindingsJson
    Require-Condition -Condition (($contract.entryPoint | ConvertTo-Json -Depth 100 -Compress) -ceq $baseEntryPointJson) -CheckId 'contract-entrypoint-unchanged' -Observed ($contract.entryPoint | ConvertTo-Json -Depth 100 -Compress) -Expected $baseEntryPointJson
    Require-Condition -Condition (($contract.expectedCardinalities | ConvertTo-Json -Depth 100 -Compress) -ceq $baseExpectedCardinalitiesJson) -CheckId 'contract-cardinalities-unchanged' -Observed ($contract.expectedCardinalities | ConvertTo-Json -Depth 100 -Compress) -Expected $baseExpectedCardinalitiesJson
    Write-JsonExclusive -Path $newContractPath -Value $contract
    $newContractSha256 = Get-Sha256Lower -Path $newContractPath

    $manifest = Read-JsonStrict -Path $baseManifestPath
    $baseTerminalChainJson = $manifest.terminalChainCorrigendum | ConvertTo-Json -Depth 100 -Compress
    $manifest.authorizationId = $authorizationId
    $manifest.manifestGeneration = 4
    $manifest.executionReadinessStatus = 'FROZEN_CURRENT_IMPLEMENTATION_COMPILED_TERMINAL_CHAIN_CORRECTED_POWERSHELL_7_6_5_HOST_BOUND_OFFLINE'
    $manifest.createdLocalDate = '2026-10-18'
    $manifest.retainedFailures = @($manifest.retainedFailures) + @(
        [pscustomobject][ordered]@{
            relativePath = Get-ProjectRelativePath -Path $oldFailurePath
            sha256 = $expectedOldFailureSha256
            status = 'FAILED_CLOSED_PRELAUNCH_FROZEN_POWERSHELL_RUNTIME_INCOMPATIBLE'
            statusV30RelativePath = Get-ProjectRelativePath -Path $statusV30Path
            statusV30Sha256 = $expectedStatusV30Sha256
            modifiedOrReclassified = $false
        }
    )
    $contractArtifact = @($manifest.artifacts | Where-Object { $_.relativePath -eq 'Research/Gate14Re-ME/Execution/v3/load-qualification-execution-contract.v3_1.json' })
    Require-Condition -Condition ($contractArtifact.Count -eq 1) -CheckId 'manifest-single-v3_1-contract-artifact' -Observed $contractArtifact.Count -Expected 1
    $contractArtifact[0].relativePath = Get-ProjectRelativePath -Path $newContractPath
    $contractArtifact[0].sha256 = $newContractSha256
    $contractArtifact[0].bytes = [int64](Get-Item -LiteralPath $newContractPath).Length
    $manifest.runtimeBindings.powershellExecutable = $pwshPath.Replace('\', '/')
    $manifest.runtimeBindings.powershellExecutableSha256 = $expectedPwshSha256
    $manifest.runtimeBindings | Add-Member -NotePropertyName powershellVersion -NotePropertyValue $expectedPwshVersion -Force
    $manifest.runtimeBindings | Add-Member -NotePropertyName powershellSupervisorCommandPrefix -NotePropertyValue @('-NoLogo', '-NoProfile', '-NonInteractive', '-File') -Force
    $manifest.evidenceBoundary | Add-Member -NotePropertyName additionalPowerShellKnownAnswerProcessesLaunchedByHostBindingCorrigendum -NotePropertyValue 1 -Force
    $manifest | Add-Member -NotePropertyName manifestRevision -NotePropertyValue '3.2' -Force
    $manifest | Add-Member -NotePropertyName supervisorPowerShellHostBindingCorrigendum -NotePropertyValue ([pscustomobject][ordered]@{
        authorizationId = $authorizationId
        attemptId = $attemptId
        exactExecutablePath = $pwshPath.Replace('\', '/')
        exactExecutableSha256 = $expectedPwshSha256
        exactPowerShellVersion = $expectedPwshVersion
        convertFromJsonDepthPresent = $true
        convertFromJsonDateKindPresent = $true
        jsonKnownAnswerPassed = $true
        jsonlKnownAnswerPassed = $true
        dateTimeOffsetStringPreservationPassed = $true
        exceptionFailClosedPassed = $true
        supervisorParameterBindingPassed = $true
        supervisorV3Changed = $false
        runnerV2Changed = $false
        compiledAssembliesChanged = $false
        scientificAssetsChanged = $false
        unityInvocationCount = 0
        qualificationExecutionAuthorized = $false
    }) -Force
    Require-Condition -Condition (($manifest.terminalChainCorrigendum | ConvertTo-Json -Depth 100 -Compress) -ceq $baseTerminalChainJson) -CheckId 'manifest-terminal-chain-corrigendum-unchanged' -Observed ($manifest.terminalChainCorrigendum | ConvertTo-Json -Depth 100 -Compress) -Expected $baseTerminalChainJson
    Require-Condition -Condition ($manifest.schema -eq 'gate14re-me-qualification-implementation-manifest-v1' -and $manifest.status -eq 'FROZEN_IMPLEMENTATION_SOURCE_ONLY_UNCOMPILED') -CheckId 'manifest-legacy-runnerv2-compatibility-fields-preserved' -Observed ($manifest.schema + '|' + $manifest.status) -Expected 'gate14re-me-qualification-implementation-manifest-v1|FROZEN_IMPLEMENTATION_SOURCE_ONLY_UNCOMPILED'
    Write-JsonExclusive -Path $newManifestPath -Value $manifest
    $newManifestSha256 = Get-Sha256Lower -Path $newManifestPath

    $newContractReadback = Read-JsonStrict -Path $newContractPath
    $newManifestReadback = Read-JsonStrict -Path $newManifestPath
    Require-Condition -Condition ($newContractReadback.revision -eq '3.2') -CheckId 'contract-v3_2-readback' -Observed $newContractReadback.revision -Expected '3.2'
    Require-Condition -Condition ($newManifestReadback.manifestRevision -eq '3.2') -CheckId 'manifest-v3_2-readback' -Observed $newManifestReadback.manifestRevision -Expected '3.2'
    Require-Condition -Condition ($newContractReadback.supervisorHostRuntime.sha256 -eq $expectedPwshSha256) -CheckId 'contract-host-runtime-hash-binding' -Observed $newContractReadback.supervisorHostRuntime.sha256 -Expected $expectedPwshSha256
    Require-Condition -Condition ($newManifestReadback.runtimeBindings.powershellExecutableSha256 -eq $expectedPwshSha256) -CheckId 'manifest-host-runtime-hash-binding' -Observed $newManifestReadback.runtimeBindings.powershellExecutableSha256 -Expected $expectedPwshSha256
    Require-Condition -Condition (-not $newContractReadback.currentAuthorization.qualificationExecutionAuthorized) -CheckId 'contract-qualification-execution-remains-unauthorized' -Observed $newContractReadback.currentAuthorization.qualificationExecutionAuthorized -Expected $false

    $baseArtifacts = @($baseManifest.artifacts)
    $newArtifacts = @($newManifestReadback.artifacts)
    Require-Condition -Condition ($newArtifacts.Count -eq $baseArtifacts.Count) -CheckId 'manifest-artifact-count-unchanged' -Observed $newArtifacts.Count -Expected $baseArtifacts.Count
    for ($index = 0; $index -lt $baseArtifacts.Count; $index++) {
        $baseArtifact = $baseArtifacts[$index]
        $newArtifact = $newArtifacts[$index]
        if ($baseArtifact.relativePath -eq 'Research/Gate14Re-ME/Execution/v3/load-qualification-execution-contract.v3_1.json') {
            Require-Condition -Condition ($newArtifact.relativePath -eq (Get-ProjectRelativePath -Path $newContractPath) -and $newArtifact.sha256 -eq $newContractSha256) -CheckId 'manifest-only-contract-artifact-versioned' -Observed ($newArtifact.relativePath + '|' + $newArtifact.sha256) -Expected ((Get-ProjectRelativePath -Path $newContractPath) + '|' + $newContractSha256)
        }
        else {
            $baseArtifactJson = $baseArtifact | ConvertTo-Json -Depth 100 -Compress
            $newArtifactJson = $newArtifact | ConvertTo-Json -Depth 100 -Compress
            Require-Condition -Condition ($newArtifactJson -ceq $baseArtifactJson) -CheckId ('manifest-noncontract-artifact-unchanged-' + $index) -Observed $newArtifactJson -Expected $baseArtifactJson
        }
    }

    $bindingMap = [ordered]@{}
    foreach ($name in $expectedSupervisorParameters) {
        $bindingMap[$name] = switch ($name) {
            'ProjectRoot' { $script:ProjectRootFull.Replace('\', '/'); break }
            'MeasuredRoot' { $measuredRoot.Replace('\', '/'); break }
            'DeliveryRoot' { $deliveryRoot.Replace('\', '/'); break }
            'ExecutionAuthorization' { 'DEFERRED_SEPARATE_AUTHORIZATION_REQUIRED'; break }
            'ExecutionAuthorizationSha256' { 'DEFERRED_SEPARATE_AUTHORIZATION_REQUIRED'; break }
            'ImplementationManifest' { $newManifestPath.Replace('\', '/'); break }
            'ImplementationManifestSha256' { $newManifestSha256; break }
            'ExecutionContract' { $newContractPath.Replace('\', '/'); break }
            'ExecutionContractSha256' { $newContractSha256; break }
            'PlanningAssetsManifest' { (Join-Path $script:ProjectRootFull $newContractReadback.frozenBindings.planningAssetsManifest.relativePath).Replace('\', '/'); break }
            'PlanningAssetsManifestSha256' { [string]$newContractReadback.frozenBindings.planningAssetsManifest.sha256; break }
            'ResourceBudget' { (Join-Path $script:ProjectRootFull 'Research/Gate14Re-ME/Execution/v1/load-qualification-resource-budget.v1.json').Replace('\', '/'); break }
            'ResourceBudgetSha256' { 'bef0f0c143f325eb7b3ad9e5401cc89bc7d6ff3938287a9b049e985aac04e887'; break }
            'FairnessBinding' { (Join-Path $script:ProjectRootFull 'Research/Gate14Re-ME/Execution/v1/six-algorithm-fairness-binding.v1.json').Replace('\', '/'); break }
            'FairnessBindingSha256' { '1ebabb51cacdaa5bb06f5dfd088f0cc557bcacb69efcf9bc2de67be1b2844e71'; break }
            'Schedule' { (Join-Path $script:ProjectRootFull $newContractReadback.frozenBindings.schedule.relativePath).Replace('\', '/'); break }
            'ScheduleSha256' { [string]$newContractReadback.frozenBindings.schedule.sha256; break }
            'OutputSchema' { (Join-Path $script:ProjectRootFull $newContractReadback.frozenBindings.outputSchema.relativePath).Replace('\', '/'); break }
            'OutputSchemaSha256' { [string]$newContractReadback.frozenBindings.outputSchema.sha256; break }
            'InstrumentContract' { (Join-Path $script:ProjectRootFull $newContractReadback.frozenBindings.instrumentContract.relativePath).Replace('\', '/'); break }
            'InstrumentContractSha256' { [string]$newContractReadback.frozenBindings.instrumentContract.sha256; break }
            'D3Contract' { (Join-Path $script:ProjectRootFull $newContractReadback.frozenBindings.qualifiedD3V31.relativePath).Replace('\', '/'); break }
            'D3ContractSha256' { [string]$newContractReadback.frozenBindings.qualifiedD3V31.sha256; break }
            'TypedParquetRuntimeManifest' { (Join-Path $script:ProjectRootFull $newContractReadback.frozenBindings.typedParquetRuntime.relativePath).Replace('\', '/'); break }
            'TypedParquetRuntimeManifestSha256' { [string]$newContractReadback.frozenBindings.typedParquetRuntime.sha256; break }
            'StructuralTool' { (Join-Path $script:ProjectRootFull $newContractReadback.frozenBindings.structuralV3.relativePath).Replace('\', '/'); break }
            'StructuralToolSha256' { [string]$newContractReadback.frozenBindings.structuralV3.sha256; break }
            'DeliveryTool' { (Join-Path $script:ProjectRootFull $newContractReadback.frozenBindings.deliveryV21.relativePath).Replace('\', '/'); break }
            'DeliveryToolSha256' { [string]$newContractReadback.frozenBindings.deliveryV21.sha256; break }
            'TrustedIdentityRule' { (Join-Path $script:ProjectRootFull $newContractReadback.frozenBindings.trustedUnityIdentityRule.relativePath).Replace('\', '/'); break }
            'TrustedIdentityRuleSha256' { [string]$newContractReadback.frozenBindings.trustedUnityIdentityRule.sha256; break }
            'TimestampComparator' { (Join-Path $script:ProjectRootFull $newContractReadback.frozenBindings.timestampComparator.relativePath).Replace('\', '/'); break }
            'TimestampComparatorSha256' { [string]$newContractReadback.frozenBindings.timestampComparator.sha256; break }
            'PythonExecutable' { [string]$newManifestReadback.runtimeBindings.pythonExecutable; break }
            'PythonExecutableSha256' { [string]$newManifestReadback.runtimeBindings.pythonExecutableSha256; break }
            'UnityExecutable' { [string]$newManifestReadback.runtimeBindings.unityExecutable; break }
            'UnityExecutableSha256' { [string]$newManifestReadback.runtimeBindings.unityExecutableSha256; break }
            default { throw "Unhandled supervisor parameter in binding known-answer: $name" }
        }
    }
    Require-Condition -Condition ($bindingMap.Count -eq 37) -CheckId 'supervisor-binding-map-cardinality' -Observed $bindingMap.Count -Expected 37
    Require-Condition -Condition (($bindingMap.Keys -join '|') -eq ($expectedSupervisorParameters -join '|')) -CheckId 'supervisor-binding-map-exact-parameter-order' -Observed ($bindingMap.Keys -join '|') -Expected ($expectedSupervisorParameters -join '|')
    Write-JsonExclusive -Path $bindingReceiptPath -Value ([ordered]@{
        schema = 'gate14re-me-supervisor-v3-parameter-binding-known-answer-v1'
        studyId = 'Gate14Re-ME'
        authorizationId = $authorizationId
        attemptId = $attemptId
        status = 'PASS_STATIC_BINDING_ALL_37_PARAMETERS'
        supervisorRelativePath = Get-ProjectRelativePath -Path $supervisorPath
        supervisorSha256 = $expectedSupervisorSha256
        parameterCount = 37
        allMandatory = $allMandatory
        bindingMap = $bindingMap
        executionAuthorizationDeferred = $true
        supervisorInvoked = $false
        unityInvoked = $false
    })

    $unityAfter = @(Get-UnityProcessSnapshot)
    Require-Condition -Condition ($unityAfter.Count -eq 0) -CheckId 'unity-process-count-after' -Observed $unityAfter.Count -Expected 0
    $rootStateAfter = [pscustomobject][ordered]@{
        qualificationMeasuredRootExists = Test-Path -LiteralPath $measuredRoot
        deliveryRootExists = Test-Path -LiteralPath $deliveryRoot
        formalRootExists = Test-Path -LiteralPath $formalRoot
    }
    Require-Condition -Condition ($rootStateAfter.qualificationMeasuredRootExists -eq $rootStateBefore.qualificationMeasuredRootExists) -CheckId 'qualification-measured-root-state-unchanged' -Observed $rootStateAfter.qualificationMeasuredRootExists -Expected $rootStateBefore.qualificationMeasuredRootExists
    Require-Condition -Condition ($rootStateAfter.deliveryRootExists -eq $rootStateBefore.deliveryRootExists) -CheckId 'delivery-root-state-unchanged' -Observed $rootStateAfter.deliveryRootExists -Expected $rootStateBefore.deliveryRootExists
    Require-Condition -Condition ($rootStateAfter.formalRootExists -eq $rootStateBefore.formalRootExists) -CheckId 'formal-root-state-unchanged' -Observed $rootStateAfter.formalRootExists -Expected $rootStateBefore.formalRootExists

    $oldInventoryAfter = Get-FileInventory -Root $oldAttemptRoot
    $oldBeforeJson = $oldInventoryBefore | ConvertTo-Json -Depth 10 -Compress
    $oldAfterJson = $oldInventoryAfter | ConvertTo-Json -Depth 10 -Compress
    Require-Condition -Condition ($oldAfterJson -ceq $oldBeforeJson) -CheckId 'attempt001-complete-inventory-unchanged' -Observed $oldAfterJson -Expected $oldBeforeJson
    Require-Condition -Condition ((Get-Sha256Lower -Path $statusV30Path) -eq $expectedStatusV30Sha256) -CheckId 'status-v30-still-unchanged-at-close' -Observed (Get-Sha256Lower -Path $statusV30Path) -Expected $expectedStatusV30Sha256
    Require-Condition -Condition ((Get-Sha256Lower -Path $supervisorPath) -eq $expectedSupervisorSha256) -CheckId 'supervisor-v3-still-unchanged-at-close' -Observed (Get-Sha256Lower -Path $supervisorPath) -Expected $expectedSupervisorSha256
    Require-Condition -Condition ((Get-Sha256Lower -Path $runnerPath) -eq $expectedRunnerSha256) -CheckId 'runnerv2-still-unchanged-at-close' -Observed (Get-Sha256Lower -Path $runnerPath) -Expected $expectedRunnerSha256

    Write-JsonExclusive -Path $knownAnswerPath -Value ([ordered]@{
        schema = 'gate14re-me-supervisor-powershell-host-binding-known-answer-receipt-v1'
        studyId = 'Gate14Re-ME'
        authorizationId = $authorizationId
        attemptId = $attemptId
        status = 'PASS_POWERSHELL_7_6_5_JSON_JSONL_FAIL_CLOSED_AND_SUPERVISOR_BINDING'
        passed = $true
        startedAtUtc = $startedAtUtc
        completedAtUtc = [DateTimeOffset]::UtcNow.ToString('o')
        hostRuntime = [ordered]@{
            processPath = $currentProcessPath.Replace('\', '/')
            sha256 = $observedPwshSha256
            version = $observedPwshVersion
            convertFromJsonDepth = $true
            convertFromJsonDateKind = $true
        }
        fixtures = [ordered]@{
            json = [ordered]@{ relativePath = Get-ProjectRelativePath -Path $fixtureJsonPath; sha256 = Get-Sha256Lower -Path $fixtureJsonPath }
            jsonl = [ordered]@{ relativePath = Get-ProjectRelativePath -Path $fixtureJsonlPath; sha256 = Get-Sha256Lower -Path $fixtureJsonlPath; rows = 3 }
            invalidJson = [ordered]@{ relativePath = Get-ProjectRelativePath -Path $invalidJsonPath; sha256 = Get-Sha256Lower -Path $invalidJsonPath; rejected = $true; error = $invalidJsonError }
            invalidJsonlRowRejected = $invalidJsonlRejected
            invalidJsonlError = $invalidJsonlError
        }
        dateTimeOffsetStringExact = $timestampText
        supervisor = [ordered]@{
            relativePath = Get-ProjectRelativePath -Path $supervisorPath
            sha256 = $expectedSupervisorSha256
            parameterCount = 37
            strictJsonExpressionCount = $strictJsonExpressionCount
            invoked = $false
        }
        versionedBindings = [ordered]@{
            executionContractRelativePath = Get-ProjectRelativePath -Path $newContractPath
            executionContractSha256 = $newContractSha256
            implementationManifestRelativePath = Get-ProjectRelativePath -Path $newManifestPath
            implementationManifestSha256 = $newManifestSha256
        }
        checks = @($script:Checks)
        scopeEvidence = [ordered]@{
            unityInvocationCount = 0
            instrumentInvocationCount = 0
            oracleInvocationCount = 0
            emptyBoundaryInvocationCount = 0
            algorithmLaneExecutionCount = 0
            qualificationObservationCount = 0
            formalObservationCount = 0
            formalCollectionPerformed = $false
            formalAnalysisPerformed = $false
            rankingPerformed = $false
            weightingPerformed = $false
            winnerAdjudicationPerformed = $false
            rootStateBefore = $rootStateBefore
            rootStateAfter = $rootStateAfter
        }
    })
    $knownAnswerSha256 = Get-Sha256Lower -Path $knownAnswerPath

    Write-JsonExclusive -Path $terminalReceiptPath -Value ([ordered]@{
        schema = 'gate14re-me-supervisor-powershell-host-binding-corrigendum-attempt-002-terminal-receipt-v1'
        studyId = 'Gate14Re-ME'
        authorizationId = $authorizationId
        attemptId = $attemptId
        status = 'PASS_FROZEN_POWERSHELL_7_6_5_SUPERVISOR_HOST_BINDING'
        passed = $true
        terminal = $true
        completedAtUtc = [DateTimeOffset]::UtcNow.ToString('o')
        knownAnswerReceipt = [ordered]@{ relativePath = Get-ProjectRelativePath -Path $knownAnswerPath; sha256 = $knownAnswerSha256 }
        executionContract = [ordered]@{ relativePath = Get-ProjectRelativePath -Path $newContractPath; sha256 = $newContractSha256 }
        implementationManifest = [ordered]@{ relativePath = Get-ProjectRelativePath -Path $newManifestPath; sha256 = $newManifestSha256 }
        exactHostRuntime = [ordered]@{ executablePath = $pwshPath.Replace('\', '/'); sha256 = $expectedPwshSha256; version = $expectedPwshVersion }
        retainedAttempt001Failure = [ordered]@{ relativePath = Get-ProjectRelativePath -Path $oldFailurePath; sha256 = $expectedOldFailureSha256; modifiedOrReclassified = $false }
        unchangedAssets = [ordered]@{
            supervisorV3Sha256 = $expectedSupervisorSha256
            runnerV2Sha256 = $expectedRunnerSha256
            compiledEditorAssemblySha256 = 'abef0c3232d02818e60a5603600fbc8899dba2fbe383e73b255a04eab01b5e88'
            compiledRuntimeAssemblySha256 = 'c21848ca1618dc010f52a1035489ac9347fe481735b362ee3ac8c8d938324bd1'
            inputSchemaV2Sha256 = '1054fd12e2cecc5c74f985f4739c888aaa0550dec23136b5237c87040b6fd117'
            scheduleSha256 = '328301be5b496a794b67962693183242286d22bc6030db6c746daf7873582471'
            sealedIdentitySha256 = '4e52f6f37c4ae496268a173c51ae498eba27a0efaf5303d131e6a102f8aabe08'
            instrumentContractV3Sha256 = 'c4f37f3457c222111914af95259630bba8b4c90db81aba892719634924166312'
            structuralV31Sha256 = '85b037f50cf913753ea4c77a7642b1d25b7550a833a4d5309ab16b41ad3fca7e'
            deliveryV22Sha256 = '197b14309670fc38e26b421c458fbd4fc05abe8ba61f7f715497bbcffb19eb98'
        }
        authorizationState = [ordered]@{
            hostBindingCorrigendumComplete = $true
            executionReadinessRecheckAuthorized = $false
            qualificationExecutionAuthorized = $false
            unityInvocationAuthorized = $false
            formalCollectionAuthorized = $false
            formalAnalysisAuthorized = $false
            rankingAuthorized = $false
            weightingAuthorized = $false
            winnerAdjudicationAuthorized = $false
        }
    })
    $terminalReceiptSha256 = Get-Sha256Lower -Path $terminalReceiptPath

    Write-JsonExclusive -Path $statusV31Path -Value ([ordered]@{
        schema = 'gate14re-me-status-v31'
        studyId = 'Gate14Re-ME'
        status = 'SUPERVISOR_POWERSHELL_HOST_BINDING_CORRIGENDUM_ATTEMPT_001_PASS'
        version = 31
        updatedAtUtc = [DateTimeOffset]::UtcNow.ToString('o')
        previousVersionedStatus = [ordered]@{
            relativePath = Get-ProjectRelativePath -Path $statusV30Path
            sha256 = $expectedStatusV30Sha256
            retained = $true
            modifiedOrReclassified = $false
        }
        retainedLoadQualificationExecutionAttempt001Failure = [ordered]@{
            relativePath = Get-ProjectRelativePath -Path $oldFailurePath
            sha256 = $expectedOldFailureSha256
            statusRetained = 'FAILED_CLOSED_PRELAUNCH_FROZEN_POWERSHELL_RUNTIME_INCOMPATIBLE'
            modifiedOrReclassified = $false
        }
        supervisorPowerShellHostBindingCorrigendumAttempt002 = [ordered]@{
            authorizationId = $authorizationId
            terminalReceiptRelativePath = Get-ProjectRelativePath -Path $terminalReceiptPath
            terminalReceiptSha256 = $terminalReceiptSha256
            knownAnswerReceiptRelativePath = Get-ProjectRelativePath -Path $knownAnswerPath
            knownAnswerReceiptSha256 = $knownAnswerSha256
            executionContractRelativePath = Get-ProjectRelativePath -Path $newContractPath
            executionContractSha256 = $newContractSha256
            implementationManifestRelativePath = Get-ProjectRelativePath -Path $newManifestPath
            implementationManifestSha256 = $newManifestSha256
            exactHostRuntimePath = $pwshPath.Replace('\', '/')
            exactHostRuntimeSha256 = $expectedPwshSha256
            exactHostRuntimeVersion = $expectedPwshVersion
            passed = $true
        }
        scientificState = [ordered]@{
            scientificDesignChanged = $false
            supervisorV3Changed = $false
            runnerV2Changed = $false
            compiledAssembliesChanged = $false
            scheduleChanged = $false
            algorithmImplementationsChanged = $false
            qualificationObservations = 0
            formalObservations = 0
        }
        authorizationState = [ordered]@{
            hostBindingCorrigendumConsumed = $true
            offlineExecutionReadinessRecheckAuthorized = $false
            newQualificationExecutionAttemptAuthorized = $false
            qualificationMeasuredRootCreationAuthorized = $false
            deliveryRootCreationAuthorized = $false
            unityInvocationAuthorized = $false
            formalCollectionAuthorized = $false
            formalAnalysisAuthorized = $false
            rankingAuthorized = $false
            weightingAuthorized = $false
            winnerAdjudicationAuthorized = $false
        }
        nextRequiredAction = 'Obtain a separate minimal authorization for a no-Unity offline execution-readiness recheck that binds execution contract v3.2, implementation manifest v3.2 and the exact PowerShell 7.6.5 host runtime. Only after that recheck passes may a separate new qualification execution attempt be authorized.'
    })

    $freezeArtifacts = [System.Collections.Generic.List[object]]::new()
    foreach ($file in Get-ChildItem -LiteralPath $stageRoot -File -Recurse | Sort-Object FullName) {
        if ($file.FullName -ne $freezeManifestPath) {
            $role = switch ($file.Name) {
                'Invoke-Gate14ReMESupervisorPowerShellHostBindingCorrigendumAttempt002.ps1' { 'offline-known-answer-orchestrator'; break }
                'authorization-receipt.v1.json' { 'user-authorization-receipt'; break }
                'stage-contract.v1.json' { 'stage-contract'; break }
                'powershell-known-answer-receipt.v1.json' { 'known-answer-receipt'; break }
                'supervisor-parameter-binding-known-answer.v1.json' { 'supervisor-parameter-binding-receipt'; break }
                'terminal-pass-receipt.v1.json' { 'terminal-pass-receipt'; break }
                default { 'known-answer-evidence'; break }
            }
            $freezeArtifacts.Add((New-FreezeArtifact -Role $role -Path $file.FullName)) | Out-Null
        }
    }
    $freezeArtifacts.Add((New-FreezeArtifact -Role 'versioned-execution-contract' -Path $newContractPath)) | Out-Null
    $freezeArtifacts.Add((New-FreezeArtifact -Role 'versioned-implementation-manifest' -Path $newManifestPath)) | Out-Null
    $freezeArtifacts.Add((New-FreezeArtifact -Role 'status-v31' -Path $statusV31Path)) | Out-Null
    Write-JsonExclusive -Path $freezeManifestPath -Value ([ordered]@{
        schema = 'gate14re-me-supervisor-powershell-host-binding-corrigendum-attempt-002-freeze-manifest-v1'
        studyId = 'Gate14Re-ME'
        authorizationId = $authorizationId
        attemptId = $attemptId
        status = 'FROZEN_TERMINAL_PASS_EVIDENCE'
        frozenAtUtc = [DateTimeOffset]::UtcNow.ToString('o')
        artifacts = @($freezeArtifacts)
        retainedExternalEvidence = @(
            [ordered]@{ relativePath = Get-ProjectRelativePath -Path $statusV30Path; sha256 = $expectedStatusV30Sha256; modifiedOrReclassified = $false },
            [ordered]@{ relativePath = Get-ProjectRelativePath -Path $oldFailurePath; sha256 = $expectedOldFailureSha256; modifiedOrReclassified = $false },
            [ordered]@{ relativePath = Get-ProjectRelativePath -Path $oldFreezePath; sha256 = $expectedOldFreezeSha256; modifiedOrReclassified = $false },
            [ordered]@{ relativePath = Get-ProjectRelativePath -Path $baseContractPath; sha256 = $expectedBaseContractSha256; modifiedOrReclassified = $false },
            [ordered]@{ relativePath = Get-ProjectRelativePath -Path $baseManifestPath; sha256 = $expectedBaseManifestSha256; modifiedOrReclassified = $false },
            [ordered]@{ relativePath = Get-ProjectRelativePath -Path $supervisorPath; sha256 = $expectedSupervisorSha256; modifiedOrReclassified = $false },
            [ordered]@{ relativePath = Get-ProjectRelativePath -Path $runnerPath; sha256 = $expectedRunnerSha256; modifiedOrReclassified = $false }
        )
        forbiddenActivityCounts = [ordered]@{
            unityProcesses = 0
            instrumentProcesses = 0
            oracleProcesses = 0
            emptyBoundaryProcesses = 0
            algorithmLaneProcesses = 0
            qualificationObservations = 0
            formalObservations = 0
            retries = 0
            newQualificationExecutionAttempts = 0
        }
    })

    $filesToFreeze = @(
        (Get-ChildItem -LiteralPath $stageRoot -File -Recurse | ForEach-Object { $_.FullName }),
        $newContractPath,
        $newManifestPath,
        $statusV31Path
    )
    Set-FilesReadOnly -Paths $filesToFreeze

    $result = [ordered]@{
        status = 'PASS_FROZEN_POWERSHELL_7_6_5_SUPERVISOR_HOST_BINDING'
        attemptId = $attemptId
        executionContractSha256 = $newContractSha256
        implementationManifestSha256 = $newManifestSha256
        knownAnswerReceiptSha256 = $knownAnswerSha256
        terminalReceiptSha256 = $terminalReceiptSha256
        statusV31Sha256 = Get-Sha256Lower -Path $statusV31Path
        freezeManifestSha256 = Get-Sha256Lower -Path $freezeManifestPath
        unityInvocationCount = 0
        qualificationExecutionAuthorized = $false
    }
    $result | ConvertTo-Json -Depth 10
}
catch {
    $failedAtUtc = [DateTimeOffset]::UtcNow.ToString('o')
    $exactFailure = $_.Exception.Message
    try {
        if (-not (Test-Path -LiteralPath $failureReceiptPath)) {
            Write-JsonExclusive -Path $failureReceiptPath -Value ([ordered]@{
                schema = 'gate14re-me-supervisor-powershell-host-binding-corrigendum-attempt-002-failure-receipt-v1'
                studyId = 'Gate14Re-ME'
                authorizationId = $authorizationId
                attemptId = $attemptId
                status = 'FAILED_CLOSED_SUPERVISOR_POWERSHELL_HOST_BINDING_CORRIGENDUM'
                passed = $false
                terminal = $true
                failedAtUtc = $failedAtUtc
                exactStructuralReason = $exactFailure
                checks = @($script:Checks)
                disposition = [ordered]@{
                    automaticRetryPerformed = $false
                    newQualificationExecutionAttemptCreated = $false
                    unityInvocationCount = 0
                    qualificationMeasuredRootCreated = Test-Path -LiteralPath $measuredRoot
                    deliveryRootCreated = Test-Path -LiteralPath $deliveryRoot
                    supervisorV3Modified = $false
                    runnerV2Modified = $false
                    formalCollectionPerformed = $false
                    formalAnalysisPerformed = $false
                    rankingWeightingOrWinnerComputed = $false
                }
            })
        }
        if (-not (Test-Path -LiteralPath $freezeManifestPath)) {
            $partialArtifacts = @(
                Get-ChildItem -LiteralPath $stageRoot -File -Recurse |
                    Where-Object { $_.FullName -ne $freezeManifestPath } |
                    Sort-Object FullName |
                    ForEach-Object { New-FreezeArtifact -Role 'failed-attempt-evidence' -Path $_.FullName }
            )
            if (Test-Path -LiteralPath $newContractPath) { $partialArtifacts += New-FreezeArtifact -Role 'failed-attempt-versioned-contract' -Path $newContractPath }
            if (Test-Path -LiteralPath $newManifestPath) { $partialArtifacts += New-FreezeArtifact -Role 'failed-attempt-versioned-manifest' -Path $newManifestPath }
            Write-JsonExclusive -Path $freezeManifestPath -Value ([ordered]@{
                schema = 'gate14re-me-supervisor-powershell-host-binding-corrigendum-attempt-002-failure-freeze-manifest-v1'
                studyId = 'Gate14Re-ME'
                authorizationId = $authorizationId
                attemptId = $attemptId
                status = 'FROZEN_FAILED_CLOSED_EVIDENCE'
                frozenAtUtc = $failedAtUtc
                exactFailure = $exactFailure
                artifacts = @($partialArtifacts)
                retainedAttempt001FailureSha256 = $expectedOldFailureSha256
                unityInvocationCount = 0
                automaticRetryPerformed = $false
            })
        }
        $failureFiles = @((Get-ChildItem -LiteralPath $stageRoot -File -Recurse | ForEach-Object { $_.FullName }))
        if (Test-Path -LiteralPath $newContractPath) { $failureFiles += $newContractPath }
        if (Test-Path -LiteralPath $newManifestPath) { $failureFiles += $newManifestPath }
        Set-FilesReadOnly -Paths $failureFiles
    }
    catch {
        Write-Error "Primary failure: $exactFailure; secondary evidence-freeze failure: $($_.Exception.Message)"
        exit 2
    }
    Write-Error $exactFailure
    exit 1
}
