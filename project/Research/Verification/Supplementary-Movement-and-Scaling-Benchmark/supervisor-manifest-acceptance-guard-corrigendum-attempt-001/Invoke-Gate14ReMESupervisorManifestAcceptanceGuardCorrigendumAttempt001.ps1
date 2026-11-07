[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ProjectRoot,

    [Parameter(Mandatory = $true)]
    [string]$AttemptRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$studyId = 'Gate14Re-ME'
$authorizationId = 'gate14re-me-supervisor-manifest-acceptance-guard-corrigendum-auto-repair-until-pass-263a2c10-45da-4ede-ae8e-684baf3e9057'
$attemptId = 'supervisor-manifest-acceptance-guard-corrigendum-attempt-001'
$expectedPowerShellPath = 'C:/Users/bdscy/.cache/codex-runtimes/codex-primary-runtime/dependencies/native/powershell/pwsh.exe'
$expectedPowerShellSha256 = '362a356ce7f0940ec74f73a8fc2c990a2cc24a38a11c90bbd8eca947110ad139'
$expectedPowerShellVersion = '7.6.5'
$sourceSupervisorRelativePath = 'Research/Gate14Re-ME/Execution/v3/Run-Gate14ReMELoadQualification.v3.ps1'
$sourceSupervisorSha256 = 'e672d2bc3e584192d1f9850ed2bb76538ba11fead80e1ce94670febd9fb45035'
$correctedSupervisorRelativePath = 'Research/Gate14Re-ME/Execution/v3/Run-Gate14ReMELoadQualification.v3_1.ps1'
$correctedSupervisorSha256 = '33764e996f9a2fe8ff5487eabd5b455a931b82f0923b8ac083b4aef9dc7242dc'
$sourceContractRelativePath = 'Research/Gate14Re-ME/Execution/v3/load-qualification-execution-contract.v3_2.json'
$sourceContractSha256 = '10c5689a3fccfbc5faef13d83a3b1db3026b8931581b510fbee9be1cd3a0e9d0'
$correctedContractRelativePath = 'Research/Gate14Re-ME/Execution/v3/load-qualification-execution-contract.v3_3.json'
$correctedContractSha256 = '6e35abb3f36f956f0f685f816e2b2a7c1ce2aa513a86bd16d575964bd619802a'
$sourceManifestRelativePath = 'Research/Gate14Re-ME/Execution/v3/load-qualification-current-implementation-manifest.v3_2.json'
$sourceManifestSha256 = '83ef4c7081a77f7093e9f37f53b786f628459c404ca9e89b78d6e93ce64d2514'
$correctedManifestRelativePath = 'Research/Gate14Re-ME/Execution/v3/load-qualification-current-implementation-manifest.v3_3.json'
$correctedManifestSha256 = 'a85968ee3c759c5f0c3c3bf3a5d9c3bda7c3cfca7628f3e983cb64142bfe4579'
$failureRelativePath = 'Research/Verification/Gate14Re-ME/load-qualification-execution-attempt-002/failure-receipt.v1.json'
$failureSha256 = '83882d9bcfba2cc08c86c87da9e8ae2fb920b32814b7b1fee165e59025323c10'
$statusV33RelativePath = 'Research/Gate14Re-ME/Gate14Re_ME_Status.v33.json'
$statusV33Sha256 = 'f2e3f84699914aed337b0c5058038976e1eae272e7b9ca0421208b837b845c1d'
$reservedMeasuredRootRelativePath = 'Research/PilotRuns/Gate14Re-ME/load-qualification/attempt-001'
$reservedDeliveryRootRelativePath = 'Research/Exports/Gate14Re-ME/load-qualification/attempt-001'
$expectedManifestSchema = 'gate14re-me-qualification-current-implementation-manifest-v3'
$expectedReadinessStatus = 'FROZEN_CURRENT_IMPLEMENTATION_COMPILED_TERMINAL_CHAIN_CORRECTED_POWERSHELL_7_6_5_HOST_BOUND_OFFLINE'
$guardMessage = 'Authoritative implementation manifest v3 state is not adopted.'

$script:checks = [System.Collections.Generic.List[object]]::new()

function Get-NormalizedPath {
    param([Parameter(Mandatory = $true)][string]$Path)
    return [System.IO.Path]::GetFullPath($Path).Replace('\', '/')
}

function Get-ProjectPath {
    param([Parameter(Mandatory = $true)][string]$RelativePath)
    return [System.IO.Path]::GetFullPath((Join-Path $script:projectRootFull $RelativePath))
}

function Get-Sha256 {
    param([Parameter(Mandatory = $true)][string]$Path)
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Add-Pass {
    param([Parameter(Mandatory = $true)][string]$Name, [object]$Observed = $true)
    $script:checks.Add([pscustomobject][ordered]@{
        name = $Name
        passed = $true
        observed = $Observed
    })
}

function Require-Check {
    param(
        [Parameter(Mandatory = $true)][bool]$Condition,
        [Parameter(Mandatory = $true)][string]$Name,
        [object]$Observed = $null
    )
    if (-not $Condition) {
        $rendered = if ($null -eq $Observed) { '<null>' } else { [string]$Observed }
        throw [System.InvalidOperationException]::new("$Name failed; observed=$rendered")
    }
    Add-Pass -Name $Name -Observed $Observed
}

function Assert-Hash {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Expected,
        [Parameter(Mandatory = $true)][string]$Name
    )
    Require-Check -Condition (Test-Path -LiteralPath $Path -PathType Leaf) -Name "$Name exists" -Observed $Path
    $actual = Get-Sha256 -Path $Path
    Require-Check -Condition ($actual -ceq $Expected) -Name "$Name SHA-256" -Observed $actual
}

function Read-Json {
    param([Parameter(Mandatory = $true)][string]$Path)
    return Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json -Depth 100 -DateKind String
}

function Write-JsonAtomic {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][object]$Value
    )
    if (Test-Path -LiteralPath $Path) {
        throw [System.InvalidOperationException]::new("Evidence output already exists: $Path")
    }
    $json = $Value | ConvertTo-Json -Depth 100
    $temp = "$Path.tmp-$([guid]::NewGuid().ToString('N'))"
    [System.IO.File]::WriteAllText($temp, $json + [Environment]::NewLine, [System.Text.UTF8Encoding]::new($false))
    Move-Item -LiteralPath $temp -Destination $Path
}

function Get-GuardPredicate {
    param([Parameter(Mandatory = $true)][string]$SupervisorPath)
    $matches = @(Get-Content -LiteralPath $SupervisorPath | Where-Object { $_.Contains("'$guardMessage'") })
    Require-Check -Condition ($matches.Count -eq 1) -Name "one exact guard statement in $([System.IO.Path]::GetFileName($SupervisorPath))" -Observed $matches.Count
    $line = [string]$matches[0]
    $prefix = 'Require-Condition ('
    $suffix = ") '$guardMessage'"
    Require-Check -Condition ($line.StartsWith($prefix, [System.StringComparison]::Ordinal) -and $line.EndsWith($suffix, [System.StringComparison]::Ordinal)) -Name "extractable exact guard syntax in $([System.IO.Path]::GetFileName($SupervisorPath))" -Observed $line
    return $line.Substring($prefix.Length, $line.Length - $prefix.Length - $suffix.Length)
}

function Test-GuardAccepts {
    param(
        [Parameter(Mandatory = $true)][string]$Predicate,
        [Parameter(Mandatory = $true)][object]$Manifest
    )
    $body = 'param([object]$manifest)' + [Environment]::NewLine + 'Set-StrictMode -Version Latest' + [Environment]::NewLine + '[bool](' + $Predicate + ')'
    try {
        return [bool](& ([scriptblock]::Create($body)) $Manifest)
    }
    catch {
        return $false
    }
}

function Get-Gate14UnityRunnerSnapshot {
    $items = @(Get-CimInstance Win32_Process -Filter "Name = 'Unity.exe'" | Where-Object {
        [string]$_.CommandLine -like '*DDM.Research.Editor.Gate14ReMELoadQualificationRunnerV2.Run*'
    } | ForEach-Object {
        [pscustomobject][ordered]@{
            pid = [int]$_.ProcessId
            executablePath = [string]$_.ExecutablePath
            creationDate = if ($null -eq $_.CreationDate) { $null } else { ([DateTimeOffset]$_.CreationDate).ToUniversalTime().ToString('o') }
            commandLine = [string]$_.CommandLine
        }
    })
    return @($items)
}

$projectRootFull = [System.IO.Path]::GetFullPath($ProjectRoot)
$attemptRootFull = [System.IO.Path]::GetFullPath($AttemptRoot)
$knownAnswerPath = Join-Path $attemptRootFull 'exact-predicate-known-answer-receipt.v1.json'
$failureReceiptPath = Join-Path $attemptRootFull 'failure-receipt.v1.json'
$startedAtUtc = [DateTimeOffset]::UtcNow.ToString('o')
$unityBefore = @()

try {
    Require-Check -Condition (Test-Path -LiteralPath $projectRootFull -PathType Container) -Name 'project root exists' -Observed $projectRootFull
    Require-Check -Condition (Test-Path -LiteralPath $attemptRootFull -PathType Container) -Name 'attempt root exists' -Observed $attemptRootFull
    Require-Check -Condition ((Get-NormalizedPath -Path $attemptRootFull).StartsWith((Get-NormalizedPath -Path $projectRootFull) + '/', [System.StringComparison]::OrdinalIgnoreCase)) -Name 'attempt root is inside project root' -Observed $attemptRootFull

    $processPath = Get-NormalizedPath -Path ([Environment]::ProcessPath)
    Require-Check -Condition ($processPath -ceq $expectedPowerShellPath) -Name 'exact PowerShell host path' -Observed $processPath
    Assert-Hash -Path ([Environment]::ProcessPath) -Expected $expectedPowerShellSha256 -Name 'PowerShell host runtime'
    Require-Check -Condition ($PSVersionTable.PSVersion.ToString() -ceq $expectedPowerShellVersion) -Name 'exact PowerShell host version' -Observed $PSVersionTable.PSVersion.ToString()

    $sourceSupervisorPath = Get-ProjectPath -RelativePath $sourceSupervisorRelativePath
    $correctedSupervisorPath = Get-ProjectPath -RelativePath $correctedSupervisorRelativePath
    $sourceContractPath = Get-ProjectPath -RelativePath $sourceContractRelativePath
    $correctedContractPath = Get-ProjectPath -RelativePath $correctedContractRelativePath
    $sourceManifestPath = Get-ProjectPath -RelativePath $sourceManifestRelativePath
    $correctedManifestPath = Get-ProjectPath -RelativePath $correctedManifestRelativePath
    $retainedFailurePath = Get-ProjectPath -RelativePath $failureRelativePath
    $statusV33Path = Get-ProjectPath -RelativePath $statusV33RelativePath
    $reservedMeasuredRoot = Get-ProjectPath -RelativePath $reservedMeasuredRootRelativePath
    $reservedDeliveryRoot = Get-ProjectPath -RelativePath $reservedDeliveryRootRelativePath

    Assert-Hash -Path $sourceSupervisorPath -Expected $sourceSupervisorSha256 -Name 'retained source supervisor v3'
    Assert-Hash -Path $correctedSupervisorPath -Expected $correctedSupervisorSha256 -Name 'corrected supervisor v3.1'
    Assert-Hash -Path $sourceContractPath -Expected $sourceContractSha256 -Name 'retained execution contract v3.2'
    Assert-Hash -Path $correctedContractPath -Expected $correctedContractSha256 -Name 'corrected execution contract v3.3'
    Assert-Hash -Path $sourceManifestPath -Expected $sourceManifestSha256 -Name 'retained implementation manifest v3.2'
    Assert-Hash -Path $correctedManifestPath -Expected $correctedManifestSha256 -Name 'corrected implementation manifest v3.3'
    Assert-Hash -Path $retainedFailurePath -Expected $failureSha256 -Name 'retained load qualification execution attempt-002 failure receipt'
    Assert-Hash -Path $statusV33Path -Expected $statusV33Sha256 -Name 'retained Status v33'

    Require-Check -Condition ((Get-Item -LiteralPath $sourceSupervisorPath).IsReadOnly) -Name 'source supervisor remains read-only' -Observed $true
    Require-Check -Condition ((Get-Item -LiteralPath $sourceContractPath).IsReadOnly) -Name 'source contract remains read-only' -Observed $true
    Require-Check -Condition ((Get-Item -LiteralPath $sourceManifestPath).IsReadOnly) -Name 'source manifest remains read-only' -Observed $true
    Require-Check -Condition ((Get-Item -LiteralPath $retainedFailurePath).IsReadOnly) -Name 'attempt-002 failure receipt remains read-only' -Observed $true
    Require-Check -Condition ((Get-Item -LiteralPath $statusV33Path).IsReadOnly) -Name 'Status v33 remains read-only' -Observed $true

    Require-Check -Condition (-not (Test-Path -LiteralPath $reservedMeasuredRoot)) -Name 'reserved measured root absent before known-answer' -Observed $reservedMeasuredRoot
    Require-Check -Condition (-not (Test-Path -LiteralPath $reservedDeliveryRoot)) -Name 'reserved delivery root absent before known-answer' -Observed $reservedDeliveryRoot
    $unityBefore = @(Get-Gate14UnityRunnerSnapshot)
    Require-Check -Condition ($unityBefore.Count -eq 0) -Name 'no Gate14Re-ME Unity runner before known-answer' -Observed $unityBefore.Count

    $sourceLines = [System.IO.File]::ReadAllLines($sourceSupervisorPath)
    $correctedLines = [System.IO.File]::ReadAllLines($correctedSupervisorPath)
    Require-Check -Condition ($sourceLines.Count -eq $correctedLines.Count) -Name 'supervisor line count unchanged' -Observed $correctedLines.Count
    $changedLineNumbers = [System.Collections.Generic.List[int]]::new()
    for ($i = 0; $i -lt $sourceLines.Count; $i++) {
        if (-not [string]::Equals($sourceLines[$i], $correctedLines[$i], [System.StringComparison]::Ordinal)) {
            $changedLineNumbers.Add($i + 1)
        }
    }
    Require-Check -Condition ($changedLineNumbers.Count -eq 1) -Name 'exactly one supervisor source line changed' -Observed ($changedLineNumbers -join ',')
    Require-Check -Condition ($changedLineNumbers[0] -eq 540) -Name 'only supervisor line 540 changed' -Observed $changedLineNumbers[0]

    $tokens = $null
    $parseErrors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($correctedSupervisorPath, [ref]$tokens, [ref]$parseErrors)
    Require-Check -Condition (@($parseErrors).Count -eq 0) -Name 'corrected supervisor PowerShell syntax' -Observed @($parseErrors).Count

    $sourcePredicate = Get-GuardPredicate -SupervisorPath $sourceSupervisorPath
    $correctedPredicate = Get-GuardPredicate -SupervisorPath $correctedSupervisorPath
    Require-Check -Condition (-not [string]::Equals($sourcePredicate, $correctedPredicate, [System.StringComparison]::Ordinal)) -Name 'guard predicate changed' -Observed $true
    Require-Check -Condition ($correctedPredicate.Contains('$manifest.manifestGeneration -eq 4')) -Name 'corrected predicate binds manifest generation 4' -Observed $correctedPredicate
    Require-Check -Condition ($correctedPredicate.Contains("$expectedReadinessStatus")) -Name 'corrected predicate binds exact host-bound readiness status' -Observed $correctedPredicate

    $sourceManifest = Read-Json -Path $sourceManifestPath
    $correctedManifest = Read-Json -Path $correctedManifestPath
    $correctedContract = Read-Json -Path $correctedContractPath
    Require-Check -Condition (-not (Test-GuardAccepts -Predicate $sourcePredicate -Manifest $sourceManifest)) -Name 'source predicate reproduces rejection of authoritative manifest v3.2' -Observed $false
    Require-Check -Condition (Test-GuardAccepts -Predicate $correctedPredicate -Manifest $sourceManifest) -Name 'corrected predicate accepts authoritative manifest v3.2' -Observed $true
    Require-Check -Condition (Test-GuardAccepts -Predicate $correctedPredicate -Manifest $correctedManifest) -Name 'corrected predicate accepts successor manifest v3.3' -Observed $true

    $positiveFixture = [pscustomobject][ordered]@{
        manifestGeneration = 4
        manifestSchemaV3 = $expectedManifestSchema
        executionReadinessStatus = $expectedReadinessStatus
    }
    $generationNegative = [pscustomobject][ordered]@{
        manifestGeneration = 3
        manifestSchemaV3 = $expectedManifestSchema
        executionReadinessStatus = $expectedReadinessStatus
    }
    $schemaNegative = [pscustomobject][ordered]@{
        manifestGeneration = 4
        manifestSchemaV3 = 'gate14re-me-qualification-current-implementation-manifest-v2'
        executionReadinessStatus = $expectedReadinessStatus
    }
    $statusNegative = [pscustomobject][ordered]@{
        manifestGeneration = 4
        manifestSchemaV3 = $expectedManifestSchema
        executionReadinessStatus = 'FROZEN_CURRENT_IMPLEMENTATION_COMPILED_AND_TERMINAL_CHAIN_CORRECTED_OFFLINE'
    }
    $missingGenerationNegative = [pscustomobject][ordered]@{
        manifestSchemaV3 = $expectedManifestSchema
        executionReadinessStatus = $expectedReadinessStatus
    }
    $missingSchemaNegative = [pscustomobject][ordered]@{
        manifestGeneration = 4
        executionReadinessStatus = $expectedReadinessStatus
    }
    $missingStatusNegative = [pscustomobject][ordered]@{
        manifestGeneration = 4
        manifestSchemaV3 = $expectedManifestSchema
    }
    Require-Check -Condition (Test-GuardAccepts -Predicate $correctedPredicate -Manifest $positiveFixture) -Name 'positive synthetic manifest accepted' -Observed $true
    Require-Check -Condition (-not (Test-GuardAccepts -Predicate $correctedPredicate -Manifest $generationNegative)) -Name 'wrong generation rejected' -Observed $false
    Require-Check -Condition (-not (Test-GuardAccepts -Predicate $correctedPredicate -Manifest $schemaNegative)) -Name 'wrong schema rejected' -Observed $false
    Require-Check -Condition (-not (Test-GuardAccepts -Predicate $correctedPredicate -Manifest $statusNegative)) -Name 'stale readiness status rejected' -Observed $false
    Require-Check -Condition (-not (Test-GuardAccepts -Predicate $correctedPredicate -Manifest $missingGenerationNegative)) -Name 'missing generation rejected' -Observed $false
    Require-Check -Condition (-not (Test-GuardAccepts -Predicate $correctedPredicate -Manifest $missingSchemaNegative)) -Name 'missing schema rejected' -Observed $false
    Require-Check -Condition (-not (Test-GuardAccepts -Predicate $correctedPredicate -Manifest $missingStatusNegative)) -Name 'missing readiness status rejected' -Observed $false

    Require-Check -Condition ($correctedManifest.manifestGeneration -eq 4 -and $correctedManifest.manifestSchemaV3 -ceq $expectedManifestSchema -and $correctedManifest.executionReadinessStatus -ceq $expectedReadinessStatus -and $correctedManifest.manifestRevision -ceq '3.3') -Name 'successor manifest authoritative header' -Observed $correctedManifest.manifestRevision
    Require-Check -Condition ($correctedContract.schema -ceq 'gate14re-me-load-qualification-execution-contract-v3' -and $correctedContract.status -ceq 'FROZEN_EXECUTION_BINDING_V3_TERMINAL_CHAIN_CORRECTED_QUALIFICATION_EXECUTION_UNAUTHORIZED' -and $correctedContract.revision -ceq '3.3') -Name 'successor contract frozen unauthorized header' -Observed $correctedContract.revision
    Require-Check -Condition ($correctedContract.entryPoint.supervisorRelativePath -ceq $correctedSupervisorRelativePath -and $correctedContract.entryPoint.supervisorSha256 -ceq $correctedSupervisorSha256 -and $correctedContract.entryPoint.supervisorRevision -ceq '3.1') -Name 'successor contract binds corrected supervisor' -Observed $correctedContract.entryPoint.supervisorRelativePath
    Require-Check -Condition ($correctedContract.supersedes.relativePath -ceq $sourceContractRelativePath -and $correctedContract.supersedes.sha256 -ceq $sourceContractSha256 -and -not $correctedContract.supersedes.modifiedOrReclassified) -Name 'successor contract retains v3.2 without reclassification' -Observed $correctedContract.supersedes.sha256
    Require-Check -Condition (-not $correctedContract.currentAuthorization.unityInvocationAuthorized -and -not $correctedContract.currentAuthorization.qualificationMeasuredRootCreationAuthorized -and -not $correctedContract.currentAuthorization.deliveryRootCreationAuthorized -and -not $correctedContract.currentAuthorization.qualificationExecutionAuthorized -and -not $correctedContract.currentAuthorization.formalCollectionAuthorized -and -not $correctedContract.currentAuthorization.formalAnalysisAuthorized -and -not $correctedContract.currentAuthorization.rankingAuthorized -and -not $correctedContract.currentAuthorization.winnerAdjudicationAuthorized) -Name 'successor contract preserves prohibited execution and analysis boundaries' -Observed $true

    $manifestPathGroups = @($correctedManifest.artifacts | Group-Object -Property relativePath)
    Require-Check -Condition (@($manifestPathGroups | Where-Object { $_.Count -ne 1 }).Count -eq 0) -Name 'successor manifest artifact paths are unique' -Observed $manifestPathGroups.Count
    $manifestIndex = @{}
    foreach ($artifact in @($correctedManifest.artifacts)) {
        $manifestIndex[[string]$artifact.relativePath] = $artifact
    }
    foreach ($sourceArtifact in @($sourceManifest.artifacts)) {
        $path = [string]$sourceArtifact.relativePath
        Require-Check -Condition ($manifestIndex.ContainsKey($path)) -Name "successor manifest retains source artifact $path" -Observed $path
        $successorArtifact = $manifestIndex[$path]
        Require-Check -Condition ([string]$successorArtifact.sha256 -ceq [string]$sourceArtifact.sha256 -and [long]$successorArtifact.bytes -eq [long]$sourceArtifact.bytes -and [string]$successorArtifact.role -ceq [string]$sourceArtifact.role) -Name "successor manifest preserves source artifact binding $path" -Observed $successorArtifact.sha256
        $artifactFull = Get-ProjectPath -RelativePath $path
        Assert-Hash -Path $artifactFull -Expected ([string]$sourceArtifact.sha256) -Name "retained manifest artifact $path"
        Require-Check -Condition ((Get-Item -LiteralPath $artifactFull).Length -eq [long]$sourceArtifact.bytes) -Name "retained manifest artifact byte count $path" -Observed (Get-Item -LiteralPath $artifactFull).Length
    }
    Require-Check -Condition ($manifestIndex.ContainsKey($correctedSupervisorRelativePath) -and [string]$manifestIndex[$correctedSupervisorRelativePath].sha256 -ceq $correctedSupervisorSha256) -Name 'successor manifest binds corrected supervisor' -Observed $manifestIndex[$correctedSupervisorRelativePath].sha256
    Require-Check -Condition ($manifestIndex.ContainsKey($correctedContractRelativePath) -and [string]$manifestIndex[$correctedContractRelativePath].sha256 -ceq $correctedContractSha256) -Name 'successor manifest binds corrected contract' -Observed $manifestIndex[$correctedContractRelativePath].sha256
    Require-Check -Condition (-not $correctedManifest.supervisorManifestAcceptanceGuardCorrigendum.readinessRecheckAuthorized -and -not $correctedManifest.supervisorManifestAcceptanceGuardCorrigendum.qualificationExecutionAuthorized -and -not $correctedManifest.supervisorManifestAcceptanceGuardCorrigendum.formalCollectionAuthorized -and -not $correctedManifest.supervisorManifestAcceptanceGuardCorrigendum.formalAnalysisAuthorized -and -not $correctedManifest.supervisorManifestAcceptanceGuardCorrigendum.rankingAuthorized -and -not $correctedManifest.supervisorManifestAcceptanceGuardCorrigendum.winnerAdjudicationAuthorized) -Name 'successor manifest preserves authorization boundary' -Observed $true

    Require-Check -Condition (-not (Test-Path -LiteralPath $reservedMeasuredRoot)) -Name 'reserved measured root absent after known-answer' -Observed $reservedMeasuredRoot
    Require-Check -Condition (-not (Test-Path -LiteralPath $reservedDeliveryRoot)) -Name 'reserved delivery root absent after known-answer' -Observed $reservedDeliveryRoot
    $unityAfter = @(Get-Gate14UnityRunnerSnapshot)
    Require-Check -Condition ($unityAfter.Count -eq 0) -Name 'no Gate14Re-ME Unity runner after known-answer' -Observed $unityAfter.Count

    $receipt = [ordered]@{
        schema = 'gate14re-me-supervisor-manifest-acceptance-guard-corrigendum-exact-predicate-known-answer-receipt-v1'
        studyId = $studyId
        authorizationId = $authorizationId
        attemptId = $attemptId
        status = 'PASS_EXACT_SUPERVISOR_MANIFEST_ACCEPTANCE_PREDICATE_OFFLINE'
        passed = $true
        terminal = true
        startedAtUtc = $startedAtUtc
        completedAtUtc = [DateTimeOffset]::UtcNow.ToString('o')
        hostRuntime = [ordered]@{
            executablePath = $processPath
            sha256 = $expectedPowerShellSha256
            version = $PSVersionTable.PSVersion.ToString()
        }
        sourceSupervisor = [ordered]@{
            relativePath = $sourceSupervisorRelativePath
            sha256 = $sourceSupervisorSha256
            exactPredicate = $sourcePredicate
        }
        correctedSupervisor = [ordered]@{
            relativePath = $correctedSupervisorRelativePath
            sha256 = $correctedSupervisorSha256
            exactPredicate = $correctedPredicate
            changedLineNumbers = @($changedLineNumbers)
        }
        authoritativeManifestV32AcceptedBySourcePredicate = $false
        authoritativeManifestV32AcceptedByCorrectedPredicate = $true
        successorManifestV33AcceptedByCorrectedPredicate = $true
        negativeCasesRejected = @(
            'wrong generation',
            'wrong schema',
            'stale readiness status',
            'missing generation',
            'missing schema',
            'missing readiness status'
        )
        preservedSourceManifestArtifactCount = @($sourceManifest.artifacts).Count
        successorManifestArtifactCount = @($correctedManifest.artifacts).Count
        checksPassed = $script:checks.Count
        checks = @($script:checks)
        scientificBoundary = [ordered]@{
            unityInvocationCount = 0
            gate14UnityRunnerCountBefore = $unityBefore.Count
            gate14UnityRunnerCountAfter = $unityAfter.Count
            qualificationMeasuredRootCreated = $false
            deliveryRootCreated = $false
            plannerInvocationCount = 0
            algorithmLaneExecutionCount = 0
            qualificationObservationCount = 0
            formalObservationCount = 0
            formalCollectionPerformed = $false
            formalAnalysisPerformed = $false
            rankingOrWinnerComputed = $false
        }
        nextGate = 'SEPARATE_EXECUTION_READINESS_RECHECK_AUTHORIZATION_REQUIRED'
    }
    Write-JsonAtomic -Path $knownAnswerPath -Value $receipt
    $receipt | ConvertTo-Json -Depth 8
    exit 0
}
catch {
    $unityAfterFailure = @(Get-Gate14UnityRunnerSnapshot)
    $failure = [ordered]@{
        schema = 'gate14re-me-supervisor-manifest-acceptance-guard-corrigendum-attempt-001-failure-receipt-v1'
        studyId = $studyId
        authorizationId = $authorizationId
        attemptId = $attemptId
        status = 'FAILED_CLOSED_SUPERVISOR_MANIFEST_ACCEPTANCE_GUARD_CORRIGENDUM'
        passed = $false
        terminal = $true
        failedAtUtc = [DateTimeOffset]::UtcNow.ToString('o')
        exactStructuralReason = $_.Exception.Message
        checksPassedBeforeFailure = $script:checks.Count
        checks = @($script:checks)
        scientificBoundary = [ordered]@{
            unityInvocationCount = 0
            gate14UnityRunnerCountBefore = @($unityBefore).Count
            gate14UnityRunnerCountAfter = $unityAfterFailure.Count
            qualificationMeasuredRootCreated = Test-Path -LiteralPath (Get-ProjectPath -RelativePath $reservedMeasuredRootRelativePath)
            deliveryRootCreated = Test-Path -LiteralPath (Get-ProjectPath -RelativePath $reservedDeliveryRootRelativePath)
            plannerInvocationCount = 0
            algorithmLaneExecutionCount = 0
            qualificationObservationCount = 0
            formalObservationCount = 0
            formalCollectionPerformed = $false
            formalAnalysisPerformed = $false
            rankingOrWinnerComputed = $false
        }
        disposition = 'PRESERVE_THIS_ATTEMPT_AND_USE_AUTHORIZED_NEXT_CORRIGENDUM_ATTEMPT_WITHOUT_SCOPE_EXPANSION'
    }
    if (-not (Test-Path -LiteralPath $failureReceiptPath)) {
        Write-JsonAtomic -Path $failureReceiptPath -Value $failure
    }
    [Console]::Error.WriteLine($_.Exception.ToString())
    exit 1
}
