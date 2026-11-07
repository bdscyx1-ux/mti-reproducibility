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
        try { $writer.Write($Text) } finally { $writer.Dispose() }
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
    Write-TextExclusive -Path $Path -Text (($Value | ConvertTo-Json -Depth 100) + "`n")
}

function Read-JsonStrict {
    param([Parameter(Mandatory = $true)][string]$Path)
    return Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json -Depth 100 -DateKind String
}

function Get-ProjectRelativePath {
    param([Parameter(Mandatory = $true)][string]$Path)
    $full = Get-NormalizedPath -Path $Path
    if (-not $full.StartsWith($script:ProjectRootFull + [System.IO.Path]::DirectorySeparatorChar, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Path outside project root: $Path"
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
    $script:Checks.Add([pscustomobject][ordered]@{
        checkId = $CheckId
        passed = $Condition
        observed = $Observed
        expected = $Expected
    }) | Out-Null
    if (-not $Condition) {
        throw "[$CheckId] expected '$Expected' but observed '$Observed'."
    }
}

function New-ArtifactRecord {
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
        readOnly = [bool]$item.IsReadOnly
    }
}

function Set-PathsReadOnly {
    param([Parameter(Mandatory = $true)][string[]]$Paths)
    foreach ($path in @($Paths | Sort-Object -Unique)) {
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            throw "Cannot freeze missing file: $path"
        }
        (Get-Item -LiteralPath $path).IsReadOnly = $true
    }
}

$script:ProjectRootFull = Get-NormalizedPath -Path $ProjectRoot
$expectedProjectRoot = Get-NormalizedPath -Path 'H:/DDM_Final_Project'
if (-not $script:ProjectRootFull.Equals($expectedProjectRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "Project root mismatch: $script:ProjectRootFull"
}

$script:Checks = [System.Collections.Generic.List[object]]::new()
$attemptId = 'supervisor-powershell-host-binding-corrigendum-attempt-004'
$authorizationId = 'gate14re-me-supervisor-powershell-host-binding-auto-repair-until-pass'
$stageRoot = Join-Path $script:ProjectRootFull 'Research/Verification/Gate14Re-ME/supervisor-powershell-host-binding-corrigendum-attempt-004'
$scriptPath = Join-Path $stageRoot 'Invoke-Gate14ReMESupervisorPowerShellHostBindingCorrigendumAttempt004.ps1'
$authorizationPath = Join-Path $stageRoot 'authorization-receipt.v1.json'
$stageContractPath = Join-Path $stageRoot 'stage-contract.v1.json'
$closureReceiptPath = Join-Path $stageRoot 'readonly-freeze-closure-receipt.v1.json'
$terminalReceiptPath = Join-Path $stageRoot 'terminal-pass-receipt.v1.json'
$failureReceiptPath = Join-Path $stageRoot 'failure-receipt.v1.json'
$freezeManifestPath = Join-Path $stageRoot 'freeze-manifest.v1.json'

$attempt003Root = Join-Path $script:ProjectRootFull 'Research/Verification/Gate14Re-ME/supervisor-powershell-host-binding-corrigendum-attempt-003'
$attempt003TerminalPath = Join-Path $attempt003Root 'terminal-pass-receipt.v1.json'
$attempt003KnownAnswerPath = Join-Path $attempt003Root 'powershell-known-answer-receipt.v1.json'
$attempt003FreezePath = Join-Path $attempt003Root 'freeze-manifest.v1.json'
$contractV32Path = Join-Path $script:ProjectRootFull 'Research/Gate14Re-ME/Execution/v3/load-qualification-execution-contract.v3_2.json'
$manifestV32Path = Join-Path $script:ProjectRootFull 'Research/Gate14Re-ME/Execution/v3/load-qualification-current-implementation-manifest.v3_2.json'
$statusV31Path = Join-Path $script:ProjectRootFull 'Research/Gate14Re-ME/Gate14Re_ME_Status.v31.json'
$measuredRoot = Join-Path $script:ProjectRootFull 'Research/PilotRuns/Gate14Re-ME/load-qualification/attempt-001'
$deliveryRoot = Join-Path $script:ProjectRootFull 'Research/Exports/Gate14Re-ME/load-qualification/attempt-001'
$formalRoot = Join-Path $script:ProjectRootFull 'Research/FormalRuns/Gate14Re-ME'
$pwshPath = Get-NormalizedPath -Path 'C:/Users/bdscy/.cache/codex-runtimes/codex-primary-runtime/dependencies/native/powershell/pwsh.exe'

$expectedPwshSha256 = '362a356ce7f0940ec74f73a8fc2c990a2cc24a38a11c90bbd8eca947110ad139'
$expectedPwshVersion = '7.6.5'
$expectedContractV32Sha256 = '10c5689a3fccfbc5faef13d83a3b1db3026b8931581b510fbee9be1cd3a0e9d0'
$expectedManifestV32Sha256 = '83ef4c7081a77f7093e9f37f53b786f628459c404ca9e89b78d6e93ce64d2514'
$expectedStatusV31Sha256 = '27e766ac61ce77321a6e01ed772398d19135e5dc57e70419bf849292b2ad5529'
$expectedAttempt003Files = [ordered]@{
    'authorization-receipt.v1.json' = '865258f5fcd79153d5a265940e897c6be35db358308910c592935fbd3e7be7e7'
    'freeze-manifest.v1.json' = 'f884b5bce36f82c3f5e8424a4da29910252a9155953abb7a589b4c1ca18e3cc5'
    'Invoke-Gate14ReMESupervisorPowerShellHostBindingCorrigendumAttempt003.ps1' = '5180fb118783e38890878f17e38a0a51ea6d33112b5cc58a05505ca61934de86'
    'powershell-invalid-json-negative-fixture.v1.txt' = '2e665de337bdff4f542f3d6cc02d448a430e83ecb3e8b869ce5252e0f4830d3b'
    'powershell-json-known-answer-fixture.v1.json' = 'a6971c57c616b09d1680a41ab5e4203d690301d1bfc2ff176a1fdcd7db7d5429'
    'powershell-jsonl-known-answer-fixture.v1.jsonl' = '414e560e34a206ddeae831ed556985acee7f924305c82729564a046a2db77682'
    'powershell-known-answer-receipt.v1.json' = 'd105d621077d301aa99d925a215887f827213a8d3725a194ba2a9e515194a158'
    'stage-contract.v1.json' = '7b69c587879a1acd19c157af3cec04a829228a279547e54353b5a255f6078df7'
    'supervisor-parameter-binding-known-answer.v1.json' = '55627382558751e15883f12fb1a9d2deac7e3a2877233d6205232bfea242016e'
    'terminal-pass-receipt.v1.json' = '3ac34ef5e92af59648828e719add81a0d42078bfbd4ff4a9f1eb5b1613af6418'
}

$userAuthorizationTextExact = '授权PowerShell host binding部分允许自动修复重试直至通过'
$startedAtUtc = [DateTimeOffset]::UtcNow.ToString('o')

try {
    Require-Condition -Condition (Test-Path -LiteralPath $stageRoot -PathType Container) -CheckId 'attempt004-directory-exists' -Observed (Test-Path -LiteralPath $stageRoot) -Expected $true
    $initialFiles = @(Get-ChildItem -LiteralPath $stageRoot -File -Recurse)
    Require-Condition -Condition ($initialFiles.Count -eq 1 -and $initialFiles[0].FullName -eq $scriptPath) -CheckId 'attempt004-pristine-except-orchestrator' -Observed ($initialFiles.FullName -join ';') -Expected $scriptPath
    foreach ($target in @($authorizationPath, $stageContractPath, $closureReceiptPath, $terminalReceiptPath, $failureReceiptPath, $freezeManifestPath)) {
        Require-Condition -Condition (-not (Test-Path -LiteralPath $target)) -CheckId ('target-absent-' + [System.IO.Path]::GetFileName($target)) -Observed (Test-Path -LiteralPath $target) -Expected $false
    }

    $currentProcessPath = Get-NormalizedPath -Path ([Environment]::ProcessPath)
    Require-Condition -Condition ($currentProcessPath.Equals($pwshPath, [System.StringComparison]::OrdinalIgnoreCase)) -CheckId 'exact-pwsh-process-path' -Observed $currentProcessPath -Expected $pwshPath
    Require-Condition -Condition ((Get-Sha256Lower -Path $currentProcessPath) -eq $expectedPwshSha256) -CheckId 'exact-pwsh-sha256' -Observed (Get-Sha256Lower -Path $currentProcessPath) -Expected $expectedPwshSha256
    Require-Condition -Condition ($PSVersionTable.PSVersion.ToString() -eq $expectedPwshVersion) -CheckId 'exact-pwsh-version' -Observed $PSVersionTable.PSVersion.ToString() -Expected $expectedPwshVersion

    $unityCount = @(Get-CimInstance Win32_Process | Where-Object { $_.Name -ieq 'Unity.exe' }).Count
    Require-Condition -Condition ($unityCount -eq 0) -CheckId 'unity-process-count' -Observed $unityCount -Expected 0
    Require-Condition -Condition (-not (Test-Path -LiteralPath $measuredRoot)) -CheckId 'qualification-measured-root-absent' -Observed (Test-Path -LiteralPath $measuredRoot) -Expected $false
    Require-Condition -Condition (-not (Test-Path -LiteralPath $deliveryRoot)) -CheckId 'delivery-root-absent' -Observed (Test-Path -LiteralPath $deliveryRoot) -Expected $false
    Require-Condition -Condition (-not (Test-Path -LiteralPath $formalRoot)) -CheckId 'formal-root-absent' -Observed (Test-Path -LiteralPath $formalRoot) -Expected $false

    foreach ($entry in @(
        [pscustomobject]@{ Path = $contractV32Path; Hash = $expectedContractV32Sha256; Id = 'contract-v3_2' },
        [pscustomobject]@{ Path = $manifestV32Path; Hash = $expectedManifestV32Sha256; Id = 'manifest-v3_2' },
        [pscustomobject]@{ Path = $statusV31Path; Hash = $expectedStatusV31Sha256; Id = 'status-v31' }
    )) {
        Require-Condition -Condition (Test-Path -LiteralPath $entry.Path -PathType Leaf) -CheckId ($entry.Id + '-exists') -Observed (Test-Path -LiteralPath $entry.Path) -Expected $true
        Require-Condition -Condition ((Get-Sha256Lower -Path $entry.Path) -eq $entry.Hash) -CheckId ($entry.Id + '-hash') -Observed (Get-Sha256Lower -Path $entry.Path) -Expected $entry.Hash
        Require-Condition -Condition ([bool](Get-Item -LiteralPath $entry.Path).IsReadOnly) -CheckId ($entry.Id + '-readonly') -Observed (Get-Item -LiteralPath $entry.Path).IsReadOnly -Expected $true
    }

    $attempt003Files = @(Get-ChildItem -LiteralPath $attempt003Root -File | Sort-Object Name)
    Require-Condition -Condition ($attempt003Files.Count -eq $expectedAttempt003Files.Count) -CheckId 'attempt003-file-count' -Observed $attempt003Files.Count -Expected $expectedAttempt003Files.Count
    foreach ($file in $attempt003Files) {
        $expectedHash = [string]$expectedAttempt003Files[$file.Name]
        Require-Condition -Condition (-not [string]::IsNullOrWhiteSpace($expectedHash)) -CheckId ('attempt003-file-expected-' + $file.Name) -Observed $expectedHash -Expected 'non-empty expected hash'
        Require-Condition -Condition ((Get-Sha256Lower -Path $file.FullName) -eq $expectedHash) -CheckId ('attempt003-file-hash-' + $file.Name) -Observed (Get-Sha256Lower -Path $file.FullName) -Expected $expectedHash
    }

    $attempt003Terminal = Read-JsonStrict -Path $attempt003TerminalPath
    $attempt003Known = Read-JsonStrict -Path $attempt003KnownAnswerPath
    $attempt003Freeze = Read-JsonStrict -Path $attempt003FreezePath
    $statusV31 = Read-JsonStrict -Path $statusV31Path
    Require-Condition -Condition ([bool]$attempt003Terminal.passed -and [bool]$attempt003Terminal.terminal -and [string]$attempt003Terminal.status -eq 'PASS_FROZEN_POWERSHELL_7_6_5_SUPERVISOR_HOST_BINDING') -CheckId 'attempt003-terminal-pass-content' -Observed ([string]$attempt003Terminal.status) -Expected 'PASS_FROZEN_POWERSHELL_7_6_5_SUPERVISOR_HOST_BINDING'
    Require-Condition -Condition ([bool]$attempt003Known.passed -and [string]$attempt003Known.status -eq 'PASS_POWERSHELL_7_6_5_JSON_JSONL_FAIL_CLOSED_AND_SUPERVISOR_BINDING') -CheckId 'attempt003-known-answer-pass-content' -Observed ([string]$attempt003Known.status) -Expected 'PASS_POWERSHELL_7_6_5_JSON_JSONL_FAIL_CLOSED_AND_SUPERVISOR_BINDING'
    Require-Condition -Condition (@($attempt003Known.checks).Count -eq 222) -CheckId 'attempt003-known-answer-check-count' -Observed @($attempt003Known.checks).Count -Expected 222
    Require-Condition -Condition ([string]$attempt003Freeze.status -eq 'FROZEN_TERMINAL_PASS_EVIDENCE') -CheckId 'attempt003-freeze-manifest-content' -Observed ([string]$attempt003Freeze.status) -Expected 'FROZEN_TERMINAL_PASS_EVIDENCE'
    Require-Condition -Condition ([int]$attempt003Known.scopeEvidence.unityInvocationCount -eq 0 -and [int]$attempt003Known.scopeEvidence.instrumentInvocationCount -eq 0 -and [int]$attempt003Known.scopeEvidence.oracleInvocationCount -eq 0 -and [int]$attempt003Known.scopeEvidence.emptyBoundaryInvocationCount -eq 0 -and [int]$attempt003Known.scopeEvidence.algorithmLaneExecutionCount -eq 0) -CheckId 'attempt003-forbidden-process-counts-zero' -Observed ($attempt003Known.scopeEvidence | ConvertTo-Json -Compress -Depth 20) -Expected 'all prohibited process counts zero'
    Require-Condition -Condition (-not [bool]$attempt003Known.scopeEvidence.formalCollectionPerformed -and -not [bool]$attempt003Known.scopeEvidence.formalAnalysisPerformed -and -not [bool]$attempt003Known.scopeEvidence.rankingPerformed -and -not [bool]$attempt003Known.scopeEvidence.weightingPerformed -and -not [bool]$attempt003Known.scopeEvidence.winnerAdjudicationPerformed) -CheckId 'attempt003-forbidden-analysis-flags-false' -Observed ($attempt003Known.scopeEvidence | ConvertTo-Json -Compress -Depth 20) -Expected 'all prohibited analysis flags false'
    Require-Condition -Condition ([int]$statusV31.version -eq 31 -and [string]$statusV31.status -eq 'SUPERVISOR_POWERSHELL_HOST_BINDING_CORRIGENDUM_ATTEMPT_003_PASS' -and [bool]$statusV31.supervisorPowerShellHostBindingCorrigendumAttempt003.passed) -CheckId 'status-v31-attempt003-pass-binding' -Observed ([string]$statusV31.status) -Expected 'SUPERVISOR_POWERSHELL_HOST_BINDING_CORRIGENDUM_ATTEMPT_003_PASS'

    Write-JsonExclusive -Path $authorizationPath -Value ([ordered]@{
        schema = 'gate14re-me-supervisor-powershell-host-binding-corrigendum-attempt-004-user-authorization-receipt-v1'
        studyId = 'Gate14Re-ME'
        authorizationId = $authorizationId
        attemptId = $attemptId
        status = 'AUTHORIZED_AUTOMATIC_REPAIR_WITHIN_POWERSHELL_HOST_BINDING_UNTIL_PASS'
        authorizedAtUtc = $startedAtUtc
        authorizationSource = 'direct user message'
        userAuthorizationTextExact = $userAuthorizationTextExact
        scope = 'metadata-only readonly freeze closure for attempt-003 terminal PASS evidence'
        contentMutationAuthorized = $false
        unityInvocationAuthorized = $false
        qualificationExecutionAuthorized = $false
    })
    Write-JsonExclusive -Path $stageContractPath -Value ([ordered]@{
        schema = 'gate14re-me-supervisor-powershell-host-binding-corrigendum-attempt-004-stage-contract-v1'
        studyId = 'Gate14Re-ME'
        authorizationId = $authorizationId
        attemptId = $attemptId
        status = 'FROZEN_METADATA_ONLY_READONLY_CLOSURE_SCOPE'
        createdAtUtc = [DateTimeOffset]::UtcNow.ToString('o')
        defect = 'attempt-003 nested path array prevented the intended readonly metadata assignment for its ten stage files'
        permittedMutation = 'set readonly file attribute only on exact-hash attempt-003 evidence and freeze attempt-004 closure evidence'
        prohibited = @('content mutation', 'known-answer rerun', 'Unity invocation', 'qualification execution', 'planner execution', 'algorithm lane execution', 'formal collection', 'analysis', 'ranking', 'weighting', 'winner adjudication')
    })

    Set-PathsReadOnly -Paths @($attempt003Files.FullName)
    foreach ($file in $attempt003Files) {
        Require-Condition -Condition ([bool](Get-Item -LiteralPath $file.FullName).IsReadOnly) -CheckId ('attempt003-file-readonly-closed-' + $file.Name) -Observed (Get-Item -LiteralPath $file.FullName).IsReadOnly -Expected $true
        Require-Condition -Condition ((Get-Sha256Lower -Path $file.FullName) -eq [string]$expectedAttempt003Files[$file.Name]) -CheckId ('attempt003-file-hash-after-readonly-' + $file.Name) -Observed (Get-Sha256Lower -Path $file.FullName) -Expected ([string]$expectedAttempt003Files[$file.Name])
    }

    Write-JsonExclusive -Path $closureReceiptPath -Value ([ordered]@{
        schema = 'gate14re-me-supervisor-powershell-host-binding-corrigendum-attempt-004-readonly-freeze-closure-receipt-v1'
        studyId = 'Gate14Re-ME'
        authorizationId = $authorizationId
        attemptId = $attemptId
        status = 'PASS_ATTEMPT_003_CONTENT_PRESERVED_AND_READONLY_FREEZE_CLOSED'
        passed = $true
        terminal = $true
        completedAtUtc = [DateTimeOffset]::UtcNow.ToString('o')
        repairedDefect = 'flattened readonly target application performed by independent closure attempt'
        attempt003ContentModified = $false
        attempt003FileCount = $attempt003Files.Count
        attempt003AllReadOnly = @($attempt003Files | Where-Object { -not (Get-Item -LiteralPath $_.FullName).IsReadOnly }).Count -eq 0
        retainedBindings = [ordered]@{
            executionContractV32Sha256 = $expectedContractV32Sha256
            implementationManifestV32Sha256 = $expectedManifestV32Sha256
            statusV31Sha256 = $expectedStatusV31Sha256
        }
        checks = @($script:Checks)
        forbiddenActivityCounts = [ordered]@{
            unityProcesses = 0
            instrumentProcesses = 0
            oracleProcesses = 0
            emptyBoundaryProcesses = 0
            algorithmLaneProcesses = 0
            qualificationObservations = 0
            formalObservations = 0
            qualificationExecutionAttempts = 0
        }
    })
    $closureSha256 = Get-Sha256Lower -Path $closureReceiptPath

    Write-JsonExclusive -Path $terminalReceiptPath -Value ([ordered]@{
        schema = 'gate14re-me-supervisor-powershell-host-binding-corrigendum-attempt-004-terminal-receipt-v1'
        studyId = 'Gate14Re-ME'
        authorizationId = $authorizationId
        attemptId = $attemptId
        status = 'PASS_FROZEN_POWERSHELL_HOST_BINDING_READONLY_CLOSURE'
        passed = $true
        terminal = $true
        completedAtUtc = [DateTimeOffset]::UtcNow.ToString('o')
        closureReceipt = [ordered]@{ relativePath = Get-ProjectRelativePath -Path $closureReceiptPath; sha256 = $closureSha256 }
        authoritativeStatusRetained = [ordered]@{ relativePath = Get-ProjectRelativePath -Path $statusV31Path; sha256 = $expectedStatusV31Sha256; modified = $false }
        executionContractRetained = [ordered]@{ relativePath = Get-ProjectRelativePath -Path $contractV32Path; sha256 = $expectedContractV32Sha256; modified = $false }
        implementationManifestRetained = [ordered]@{ relativePath = Get-ProjectRelativePath -Path $manifestV32Path; sha256 = $expectedManifestV32Sha256; modified = $false }
        unityInvocationCount = 0
        qualificationExecutionAuthorized = $false
    })

    $freezeArtifacts = [System.Collections.Generic.List[object]]::new()
    foreach ($file in @(Get-ChildItem -LiteralPath $stageRoot -File | Sort-Object Name)) {
        if ($file.FullName -ne $freezeManifestPath) {
            $freezeArtifacts.Add((New-ArtifactRecord -Role 'readonly-closure-evidence' -Path $file.FullName)) | Out-Null
        }
    }
    foreach ($file in $attempt003Files) {
        $freezeArtifacts.Add((New-ArtifactRecord -Role 'retained-attempt003-terminal-evidence' -Path $file.FullName)) | Out-Null
    }
    foreach ($external in @($contractV32Path, $manifestV32Path, $statusV31Path)) {
        $freezeArtifacts.Add((New-ArtifactRecord -Role 'retained-external-binding' -Path $external)) | Out-Null
    }
    Write-JsonExclusive -Path $freezeManifestPath -Value ([ordered]@{
        schema = 'gate14re-me-supervisor-powershell-host-binding-corrigendum-attempt-004-freeze-manifest-v1'
        studyId = 'Gate14Re-ME'
        authorizationId = $authorizationId
        attemptId = $attemptId
        status = 'FROZEN_TERMINAL_PASS_READONLY_CLOSURE_EVIDENCE'
        frozenAtUtc = [DateTimeOffset]::UtcNow.ToString('o')
        artifacts = @($freezeArtifacts)
        contentHashesChangedByRepair = $false
        unityInvocationCount = 0
        qualificationExecutionAttemptCount = 0
    })

    $stageFiles = @(Get-ChildItem -LiteralPath $stageRoot -File | ForEach-Object { $_.FullName })
    Set-PathsReadOnly -Paths $stageFiles
    $notReadOnly = @(Get-ChildItem -LiteralPath $stageRoot -File | Where-Object { -not $_.IsReadOnly })
    if ($notReadOnly.Count -ne 0) {
        throw "Attempt-004 freeze incomplete: $($notReadOnly.FullName -join ';')"
    }

    [ordered]@{
        status = 'PASS_FROZEN_POWERSHELL_HOST_BINDING_READONLY_CLOSURE'
        attemptId = $attemptId
        repairedAttemptId = 'supervisor-powershell-host-binding-corrigendum-attempt-003'
        closureReceiptSha256 = $closureSha256
        terminalReceiptSha256 = Get-Sha256Lower -Path $terminalReceiptPath
        freezeManifestSha256 = Get-Sha256Lower -Path $freezeManifestPath
        attempt003AllReadOnly = $true
        attempt003ContentHashesChanged = $false
        unityInvocationCount = 0
        qualificationExecutionAttemptCount = 0
    } | ConvertTo-Json -Depth 10
}
catch {
    $failure = $_.Exception.Message
    try {
        if (-not (Test-Path -LiteralPath $failureReceiptPath)) {
            Write-JsonExclusive -Path $failureReceiptPath -Value ([ordered]@{
                schema = 'gate14re-me-supervisor-powershell-host-binding-corrigendum-attempt-004-failure-receipt-v1'
                studyId = 'Gate14Re-ME'
                authorizationId = $authorizationId
                attemptId = $attemptId
                status = 'FAILED_CLOSED_POWERSHELL_HOST_BINDING_READONLY_CLOSURE'
                passed = $false
                terminal = $true
                failedAtUtc = [DateTimeOffset]::UtcNow.ToString('o')
                exactStructuralReason = $failure
                checks = @($script:Checks)
                unityInvocationCount = 0
                qualificationExecutionAttemptCount = 0
            })
        }
        $failureFiles = @(Get-ChildItem -LiteralPath $stageRoot -File | ForEach-Object { $_.FullName })
        Set-PathsReadOnly -Paths $failureFiles
    }
    catch {
        Write-Error "Primary failure: $failure; secondary freeze failure: $($_.Exception.Message)"
        exit 2
    }
    Write-Error $failure
    exit 1
}
