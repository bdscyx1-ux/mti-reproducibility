[CmdletBinding()]
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

function Read-Json {
    param([string]$Path)
    return Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json -Depth 100 -DateKind String
}

function Write-JsonExclusive {
    param([string]$Path, [object]$Value)
    Require-Condition (-not (Test-Path -LiteralPath $Path)) "Refusing to overwrite evidence: $Path"
    [IO.File]::WriteAllText($Path, (($Value | ConvertTo-Json -Depth 100) + [Environment]::NewLine), [Text.UTF8Encoding]::new($false))
}

function Resolve-ProjectPath {
    param([string]$Root, [string]$RelativePath)
    $candidate = [IO.Path]::GetFullPath((Join-Path $Root $RelativePath))
    Require-Condition ($candidate.StartsWith($Root + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) "Path escapes project root: $RelativePath"
    return $candidate
}

$root = [IO.Path]::GetFullPath($ProjectRoot).TrimEnd([IO.Path]::DirectorySeparatorChar)
$evidenceRelative = 'Research/Verification/Gate14Re-ME/load-qualification-execution-attempt-010'
$evidenceRoot = Resolve-ProjectPath -Root $root -RelativePath $evidenceRelative
$auditPath = Join-Path $evidenceRoot 'prelaunch-audit.v4_1.json'
$failurePath = Join-Path $evidenceRoot 'prelaunch-failure-receipt.v4_1.json'
$authorizationPath = Join-Path $evidenceRoot 'execution-authorization.v1.json'
$scopePath = Join-Path $evidenceRoot 'user-authorization-scope.v1.json'
$planPath = Join-Path $evidenceRoot 'execution-plan.v4_1.json'
$measuredRelative = 'Research/PilotRuns/Gate14Re-ME/load-qualification/attempt-008'
$measuredRoot = Resolve-ProjectPath -Root $root -RelativePath $measuredRelative

$expected = [ordered]@{
    supervisor = @{ Path = 'Research/Gate14Re-ME/Execution/v4/Run-Gate14ReMELoadQualification.v4_1.ps1'; Sha = '1787264268e78c75e4ad7adc0e1490f7e812ea62f0ac5ba4b742a0cc9cba0fb3' }
    runner = @{ Path = 'Assets/_Scripts/Research/Editor/Gate14ReMELoadQualificationRunnerV4_1.cs'; Sha = 'a3013097068325f314e6842dd9f9bdc2cedbc5d6773a51032200925228690a9f' }
    runnerMeta = @{ Path = 'Assets/_Scripts/Research/Editor/Gate14ReMELoadQualificationRunnerV4_1.cs.meta'; Sha = '6c5b7cdac5391397219e80a414f10ce5c78a3914571e38ab3419a65d0cf72175' }
    manifest = @{ Path = 'Research/Gate14Re-ME/Execution/v4/load-qualification-current-implementation-manifest.v4_1.json'; Sha = '380939df90716130031dc086086607fa1286e8d6f7cf3d1cadae104e5c798658' }
    contract = @{ Path = 'Research/Gate14Re-ME/Execution/v4/load-qualification-acquisition-contract.v4_1.json'; Sha = '1ccf472feecd2c811f4f6547b0424126f74bfa1ac0758885ff9db216cc2834f7' }
    acceptanceContract = @{ Path = 'Research/Gate14Re-ME/Execution/v4/load-qualification-acceptance-contract.v4_2.json'; Sha = '75b9b08e8fff191dc0168c41fe75a8d9e741dd6a6e0bd7eec941848de91ad19c' }
    planningManifest = @{ Path = 'Research/Verification/Gate14Re-ME/qualification-planning-asset-generation-v4-attempt-002/planning-assets-freeze-manifest.v4.json'; Sha = '8624880f6fbe0b709dd6d2127b5861d62d862d592dcd2b0e311c579afffbeee3' }
    schedule = @{ Path = 'Research/Verification/Gate14Re-ME/qualification-planning-asset-generation-v4-attempt-002/planning-assets/schedule/bounded-qualification-williams-schedule.v4.jsonl'; Sha = '8786f687a142900c0cf609817bbc1da957ec3ee9e09d12549e886fb892f026cb' }
    budget = @{ Path = 'Research/Gate14Re-ME/Execution/v4/load-qualification-resource-budget.v4_1.json'; Sha = 'b6938a75285167045fb9736e6c5a765dba1e54eb037edabec91d82e56d5ccc4e' }
    fairness = @{ Path = 'Research/Gate14Re-ME/Execution/v4/six-algorithm-fairness-binding.v4_1.json'; Sha = '5a2ba89c08efa86f79c756ee3b0cc54a68c310e2414760f18f286e95095319ca' }
    identity = @{ Path = 'Research/Verification/Gate14Re-ME/qualification-planning-asset-generation-v4-attempt-002/planning-assets/identity/anonymous-identity-binding.sealed.v4.json'; Sha = '77b88a23a559642d455edf0d4caad9a1f9c06b7ddf33703b8fd100f4a1878bd2' }
    identityRule = @{ Path = 'Research/Verification/Gate14Re-ME/unity-executable-identity-rule-offline-adjudication-attempt-005/trusted-launch-identity-rule.v1.json'; Sha = 'f045ef93630202a72d603096687bac655b5b4ff01e8e0743e60d63881bbded06' }
    timestampComparator = @{ Path = 'Research/Verification/Gate14Re-ME/unity-trusted-identity-timestamp-comparator-corrigendum-attempt-007/Gate14ReMETrustedTimestampComparatorV1.ps1'; Sha = 'd024c5471d1fc06fb08e9c9ca1c9cf612424d4299d8b8c6b856883745105eb27' }
    freezeTerminal = @{ Path = 'Research/Verification/Gate14Re-ME/qualification-design-implementation-freeze-v4_1-attempt-001/terminal-receipt.v4_1.json'; Sha = '400e866654066b204bf46b889f335b3d9debbc74e08029dc6ab6c7c0fac7d403' }
    freezeManifest = @{ Path = 'Research/Verification/Gate14Re-ME/qualification-design-implementation-freeze-v4_1-attempt-001/freeze-manifest.v4_1.json'; Sha = '7f8792fcf42f2e26ce40ee9452cf42980e883ba17e64b362329140e0c4d99e1b' }
    readiness = @{ Path = 'Research/Verification/Gate14Re-ME/qualification-implementation-readiness-v4-attempt-007/compile-readiness-receipt.v4_5.json'; Sha = 'de476e64cb5f9f8558ab77720aeaeb57d757dc263b56a8f93b150b54f60377f6' }
    attempt009Seal = @{ Path = 'Research/Verification/Gate14Re-ME/load-qualification-paused-seal-attempt-009/terminal-seal-receipt.v1.json'; Sha = '7c7c56f7b75b9fd1f4bbfee439960b6c486e180e940bdc09f99c171c059bd705' }
    unity = @{ Path = 'H:/UnityEditor/2022.3.30f1c1/Editor/Unity.exe'; Sha = '0a69d14cbe2ca82d0a6168da8156d9e0dd138a6b7d0260dcdea31fd3957ca9cf' }
    powerShell = @{ Path = 'C:/Users/bdscy/.cache/codex-runtimes/codex-primary-runtime/dependencies/native/powershell/pwsh.exe'; Sha = '362a356ce7f0940ec74f73a8fc2c990a2cc24a38a11c90bbd8eca947110ad139' }
    python = @{ Path = 'C:/Users/bdscy/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe'; Sha = '7d938c92a08d6495421f2f1076ccd7198aec0b288471abc0a55e90b1150d96a1' }
}

try {
    Require-Condition (Test-Path -LiteralPath $evidenceRoot -PathType Container) 'Execution evidence root is missing.'
    Require-Condition (-not (Test-Path -LiteralPath $auditPath)) 'Prelaunch audit already exists.'
    Require-Condition (-not (Test-Path -LiteralPath $failurePath)) 'Prelaunch failure receipt already exists.'
    Require-Condition (-not (Test-Path -LiteralPath $measuredRoot)) 'Fresh measured root already exists.'
    Require-Condition (-not (Test-Path -LiteralPath (Join-Path $evidenceRoot 'external-launch-receipt.v1.json'))) 'External launch receipt already exists.'

    $verifiedHashes = [ordered]@{}
    foreach ($name in $expected.Keys) {
        $item = $expected[$name]
        $path = if ([IO.Path]::IsPathRooted([string]$item.Path)) { [IO.Path]::GetFullPath([string]$item.Path) } else { Resolve-ProjectPath -Root $root -RelativePath ([string]$item.Path) }
        $actual = Get-Sha256Lower -Path $path
        Require-Condition ($actual -ceq [string]$item.Sha) "Frozen hash mismatch for $name."
        $verifiedHashes[$name] = $actual
    }

    $authorization = Read-Json -Path $authorizationPath
    Require-Condition ($authorization.schema -eq 'gate14re-me-load-qualification-execution-authorization-v1' -and $authorization.status -eq 'AUTHORIZED_LOAD_QUALIFICATION_EXECUTION') 'Execution authorization header is invalid.'
    Require-Condition ($authorization.authorizationId -eq 'gate14re-me-load-qualification-execution-attempt-010-37d80e56-786a-40ac-87bc-5ff9eb1f98a5' -and $authorization.attemptId -eq 'load-qualification-execution-attempt-010') 'Execution authorization identity mismatch.'
    Require-Condition ($authorization.measuredRootRelativePath.Replace('\', '/') -ceq $measuredRelative) 'Execution authorization measured-root mismatch.'
    Require-Condition ($authorization.qualificationRootCreationAuthorized -and $authorization.compileOrUnityExecutionAuthorized -and $authorization.qualificationExecutionAuthorized) 'Required qualification permission is absent.'
    Require-Condition (-not $authorization.migrationPackageBuildAuthorized -and -not $authorization.formalCollectionAuthorized -and -not $authorization.formalAnalysisAuthorized -and -not $authorization.rankingAuthorized -and -not $authorization.winnerAdjudicationAuthorized) 'Execution authorization exceeds the approved boundary.'
    Require-Condition ([int]$authorization.strictSerialFreshUnityProcessesAuthorized -eq 775 -and $authorization.zeroReplacementFailStop -and -not $authorization.retryResumeTopUpMergeSkipReorderOrParallelAuthorized) 'One-shot process rules are invalid.'
    Require-Condition ($authorization.implementationManifestSha256 -ceq $expected.manifest.Sha -and $authorization.executionContractSha256 -ceq $expected.contract.Sha -and $authorization.scheduleSha256 -ceq $expected.schedule.Sha) 'Authorization hash binding mismatch.'

    $scope = Read-Json -Path $scopePath
    Require-Condition ($scope.status -eq 'AUTHORIZED_STEPS_001_THROUGH_009_ONLY' -and @($scope.authorizedSteps).Count -eq 9) 'User authorization scope is invalid.'
    Require-Condition (@($scope.authorizedSteps | ForEach-Object { [int]$_.ordinal }) -join ',' -ceq '1,2,3,4,5,6,7,8,9') 'Authorized step ordinals are not exactly 1..9.'
    Require-Condition (@($scope.notAuthorized) -contains 'migration-package-staging-or-build') 'Step-10 exclusion is missing.'

    $plan = Read-Json -Path $planPath
    Require-Condition ($plan.status -eq 'PLANNED_NOT_LAUNCHED' -and [int]$plan.processPlan.total -eq 775 -and [int]$plan.processPlan.algorithmLane -eq 756 -and [int]$plan.processPlan.superblocks -eq 126) 'Execution plan cardinality mismatch.'

    $manifestPath = Resolve-ProjectPath -Root $root -RelativePath $expected.manifest.Path
    $manifest = Read-Json -Path $manifestPath
    Require-Condition (@($manifest.artifacts).Count -eq 33) 'Implementation manifest artifact cardinality mismatch.'
    foreach ($artifact in @($manifest.artifacts)) {
        $artifactPath = Resolve-ProjectPath -Root $root -RelativePath ([string]$artifact.relativePath)
        Require-Condition ((Get-Sha256Lower -Path $artifactPath) -ceq [string]$artifact.sha256) "Implementation-manifest artifact hash mismatch: $($artifact.relativePath)"
    }
    Require-Condition ($manifest.executionReadinessStatus -eq 'FROZEN_V4_1_COMPILED_READINESS_PASS_EXECUTION_UNAUTHORIZED') 'Implementation manifest readiness state mismatch.'

    $readiness = Read-Json -Path (Resolve-ProjectPath -Root $root -RelativePath $expected.readiness.Path)
    Require-Condition ($readiness.status -like 'PASS*') 'Exact v4.1 compile-readiness receipt is not PASS.'

    $errors = $null
    $tokens = $null
    $null = [Management.Automation.Language.Parser]::ParseFile((Resolve-ProjectPath -Root $root -RelativePath $expected.supervisor.Path), [ref]$tokens, [ref]$errors)
    Require-Condition (@($errors).Count -eq 0) 'Supervisor PowerShell AST contains parse errors.'

    $schedulePath = Resolve-ProjectPath -Root $root -RelativePath $expected.schedule.Path
    $scheduleLines = @(Get-Content -LiteralPath $schedulePath -Encoding UTF8 | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    Require-Condition ($scheduleLines.Count -eq 126) 'Schedule must contain exactly 126 rows.'
    $inputPaths = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $identityHashes = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $coreCells = @{}
    $coreCount = 0
    $stressCount = 0
    for ($index = 0; $index -lt $scheduleLines.Count; $index++) {
        $row = $scheduleLines[$index] | ConvertFrom-Json -Depth 100 -DateKind String
        Require-Condition ($row.schema -eq 'gate14re-me-load-qualification-schedule-row-v4' -and [int]$row.ordinal -eq $index) "Schedule schema/ordinal mismatch at row $index."
        Require-Condition ($null -eq $row.replacement -and @($row.algorithmOrder).Count -eq 6) "Schedule row $index violates zero-replacement/six-lane rules."
        $laneIds = @($row.algorithmOrder | ForEach-Object { [string]$_.anonymousLaneId } | Sort-Object -Unique)
        $algorithmIds = @($row.algorithmOrder | ForEach-Object { [string]$_.algorithmId } | Sort-Object -Unique)
        Require-Condition ($laneIds.Count -eq 6 -and $algorithmIds.Count -eq 6) "Schedule row $index does not contain six unique lane identities."
        foreach ($lane in @($row.algorithmOrder)) { $null = $identityHashes.Add([string]$lane.identityBindingSha256) }
        $inputRelative = ([string]$row.inputRelativePath).Replace('\', '/')
        Require-Condition ($inputPaths.Add($inputRelative)) "Duplicate scheduled input path: $inputRelative"
        $inputPath = Resolve-ProjectPath -Root $root -RelativePath $inputRelative
        Require-Condition ((Get-Sha256Lower -Path $inputPath) -ceq [string]$row.inputSha256) "Scheduled input hash mismatch: $inputRelative"
        $input = Read-Json -Path $inputPath
        $g = [int]$input.gridEdge
        $n = [int]$input.agentCount
        $f = [int]$input.changedCellCount
        Require-Condition (@(64, 96, 128) -contains $g -and @(32, 64, 128) -contains $n -and @(1, 9, 25, 81) -contains $f) "Input is outside the frozen G/N/F grid: $inputRelative"
        if ([string]$input.designRegion -eq 'core') {
            $coreCount++
            $key = "$g|$n|$f"
            if (-not $coreCells.ContainsKey($key)) { $coreCells[$key] = 0 }
            $coreCells[$key] = [int]$coreCells[$key] + 1
        }
        elseif ([string]$input.designRegion -eq 'stress') {
            $stressCount++
            Require-Condition ($g -eq 128 -and $n -eq 128 -and $f -eq 81) "Stress input is outside the frozen stress cell: $inputRelative"
        }
        else { throw [System.InvalidOperationException]::new("Unsupported design region: $($input.designRegion)") }
    }
    Require-Condition ($inputPaths.Count -eq 126 -and $coreCount -eq 108 -and $stressCount -eq 18 -and $coreCells.Count -eq 36) 'Schedule/input structural cardinality mismatch.'
    Require-Condition (@($coreCells.Values | Where-Object { [int]$_ -ne 3 }).Count -eq 0) 'A core G/N/F cell does not contain exactly three replicates.'
    Require-Condition ($identityHashes.Count -eq 1 -and @($identityHashes)[0] -ceq $expected.identity.Sha) 'Sealed identity binding mismatch.'

    $activeUnity = @(Get-CimInstance Win32_Process -Filter "Name = 'Unity.exe'")
    Require-Condition ($activeUnity.Count -eq 0) 'Unity is already active.'
    $activeSupervisor = @(Get-CimInstance Win32_Process | Where-Object {
        $_.Name -eq 'pwsh.exe' -and
        $null -ne $_.CommandLine -and
        ([string]$_.CommandLine).Contains('-File') -and
        ([string]$_.CommandLine).Contains('Run-Gate14ReMELoadQualification.v4_1.ps1') -and
        ([string]$_.CommandLine).Contains('attempt-008')
    })
    Require-Condition ($activeSupervisor.Count -eq 0) 'A matching v4.1 qualification supervisor is already active.'

    $powerShellPath = [IO.Path]::GetFullPath($expected.powerShell.Path)
    $powerShellVersion = (& $powerShellPath -NoLogo -NoProfile -NonInteractive -Command '$PSVersionTable.PSVersion.ToString()').Trim()
    Require-Condition ($powerShellVersion -ceq '7.6.5') 'PowerShell host version mismatch.'
    $drive = Get-PSDrive -Name ([IO.Path]::GetPathRoot($root).Substring(0, 1))
    $budget = Read-Json -Path (Resolve-ProjectPath -Root $root -RelativePath $expected.budget.Path)
    $requiredFreeBytes = [int64]$budget.qualificationReservedStorageBytes
    Require-Condition ([int64]$drive.Free -ge $requiredFreeBytes) 'Free space is below the frozen qualification reservation.'

    Write-JsonExclusive -Path $auditPath -Value ([ordered]@{
        schema = 'gate14re-me-load-qualification-prelaunch-audit-v4.1'
        studyId = 'Gate14Re-ME'
        attemptId = 'load-qualification-execution-attempt-010'
        authorizationId = [string]$authorization.authorizationId
        status = 'PASS_PRELAUNCH_FROZEN_HASH_CHAIN_FRESH_ROOT_STRUCTURAL_PLAN_NO_ACTIVE_UNITY'
        passed = $true
        measuredRootRelativePath = $measuredRelative
        measuredRootAbsent = $true
        activeUnityCount = 0
        activeMatchingSupervisorCount = 0
        freeBytes = [int64]$drive.Free
        requiredQualificationReservationBytes = $requiredFreeBytes
        processPlan = [ordered]@{ instrumentSelfTest = 1; oracleBatch = 6; emptyBoundary = 12; algorithmLane = 756; total = 775 }
        schedule = [ordered]@{ rows = 126; coreSuperblocks = 108; coreCells = 36; coreReplicatesPerCell = 3; stressSuperblocks = 18; lanes = 756; sha256 = $verifiedHashes.schedule }
        implementationManifestArtifactsVerified = 33
        authorizationSha256 = Get-Sha256Lower -Path $authorizationPath
        userAuthorizationScopeSha256 = Get-Sha256Lower -Path $scopePath
        executionPlanSha256 = Get-Sha256Lower -Path $planPath
        prelaunchValidatorSha256 = Get-Sha256Lower -Path $PSCommandPath
        verifiedFrozenHashes = $verifiedHashes
        attempt009SealUnchanged = $true
        step10MigrationPackageBuildAuthorized = $false
        formalCollectionAuthorized = $false
        formalAnalysisAuthorized = $false
        auditedAtUtc = [DateTime]::UtcNow.ToString('o')
    })
}
catch {
    if (-not (Test-Path -LiteralPath $failurePath)) {
        Write-JsonExclusive -Path $failurePath -Value ([ordered]@{
            schema = 'gate14re-me-load-qualification-prelaunch-failure-receipt-v4.1'
            studyId = 'Gate14Re-ME'
            attemptId = 'load-qualification-execution-attempt-010'
            status = 'FAIL_CLOSED_PRELAUNCH_NOT_LAUNCHED'
            measuredRootCreated = Test-Path -LiteralPath $measuredRoot
            exactFailure = $_.Exception.GetType().FullName + ': ' + $_.Exception.Message
            failedAtUtc = [DateTime]::UtcNow.ToString('o')
        })
    }
    throw
}
