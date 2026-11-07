[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ProjectRoot,

    [Parameter(Mandatory = $true)]
    [string]$SourceFreezeManifest,

    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[0-9a-f]{64}$')]
    [string]$SourceFreezeManifestSha256
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$studyId = 'Gate14Re-ME'
$authorizationId = 'gate14re-me-qualification-input-schema-compatibility-offline-closure-adjudication-attempt-005'
$sourceAuthorizationId = 'gate14re-me-qualification-input-schema-compatibility-corrigendum-attempt-004'
$expectedProjectRoot = 'H:/DDM_Final_Project'
$expectedStatusV24Sha256 = '103a6c916eb7657d00836a9f276ea57833aae2cf9251f612eecd6e3e94a0628d'
$expectedAttempt004Digest = '70d266bed18b2069106e6356eb405c1e725d81b3cede8772b5092e721c1b783c'
$expectedAttempt004FileCount = 55
$expectedFinalAttempt004ManifestSha256 = 'a93df8cf1663da39f7002d553f9c942195b6e2ef2ab554f876f84bffba19c325'
$expectedFailureReceiptSha256 = '952f9b650a2ff61d973db03239ed6d2f4ee17e54b42f4d02e9669ef9a5135101'
$expectedUnityReceiptSha256 = '47ec9b695010ceb46e9d4422eaacdc03ab75afec75d3f19fb2618840c488790663'
$expectedTrustedRuleSha256 = 'f045ef93630202a72d603096687bac655b5b4ff01e8e0743e60d63881bbded06'
$expectedTimestampComparatorSha256 = 'd024c5471d1fc06fb08e9c9ca1c9cf612424d4299d8b8c6b856883745105eb27'
$expectedTimestampKnownAnswerSha256 = 'ad64fb2bce32f2e6206f6f1f80baa30f273be212075603ee631f61b560cc1b63'
$expectedUnitySha256 = '0a69d14cbe2ca82d0a6168da8156d9e0dd138a6b7d0260dcdea31fd3957ca9cf'
$expectedInputSchemaSha256 = '1054fd12e2cecc5c74f985f4739c888aaa0550dec23136b5237c87040b6fd117'
$expectedPlanningBindingSha256 = 'abbc8965a58d4ade2696ace3a0d7af47f48d92260540f589b9dc7af1b880d5e7'
$expectedOrchestratorSha256 = 'ab7968deaae667be87d1ee6e72680d9ad26a5376a8589250c5772167b4feaf88'
$expectedSelfCheckSourceSha256 = '47b0ee60f08565df421a65814beeff0a10b2f71075b53ff836c9bdb061189587'
$expectedExecuteMethod = 'DDM.Research.Editor.InputSchemaCorrigendumAttempt004.Gate14ReMEInputSchemaCompatibilitySelfCheckV2.Run'
$expectedOracleFailure = 'Event-group topology must match the input context.'
$stagePassed = $false
$exactFailure = $null
$exceptionType = $null
$stackTrace = $null
$resolvedProjectRoot = $null
$stageRoot = $null
$statusV25Path = $null
$attempt004Root = $null
$attempt004Before = @()
$attempt004BeforeDigest = $null
$attempt004DirectoriesBefore = @()

function Require-Condition {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) {
        throw [System.InvalidOperationException]::new($Message)
    }
}

function Get-NormalizedFullPath {
    param([string]$Path, [string]$Base)
    $candidate = if ([System.IO.Path]::IsPathRooted($Path)) { $Path } else { Join-Path -Path $Base -ChildPath $Path }
    return [System.IO.Path]::GetFullPath($candidate).TrimEnd([System.IO.Path]::DirectorySeparatorChar)
}

function Get-ProjectRelativePath {
    param([string]$Path, [string]$Root)
    return [System.IO.Path]::GetRelativePath(
        [System.IO.Path]::GetFullPath($Root),
        [System.IO.Path]::GetFullPath($Path)).Replace('\', '/')
}

function Get-Sha256Lower {
    param([string]$Path)
    Require-Condition (Test-Path -LiteralPath $Path -PathType Leaf) "Required file is missing: $Path"
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Get-StringSha256Lower {
    param([string]$Value)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [System.Text.UTF8Encoding]::new($false).GetBytes($Value)
        return [Convert]::ToHexString($sha.ComputeHash($bytes)).ToLowerInvariant()
    }
    finally {
        $sha.Dispose()
    }
}

function Read-JsonStrict {
    param([string]$Path)
    Require-Condition (Test-Path -LiteralPath $Path -PathType Leaf) "Required JSON is missing: $Path"
    return Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json -Depth 100 -DateKind String
}

function Write-JsonExclusive {
    param([string]$Path, [object]$Value)
    Require-Condition (-not (Test-Path -LiteralPath $Path)) "Refusing to overwrite evidence: $Path"
    $parent = Split-Path -Parent $Path
    Require-Condition (Test-Path -LiteralPath $parent -PathType Container) "Evidence parent directory is missing: $parent"
    $json = ($Value | ConvertTo-Json -Depth 100) + [Environment]::NewLine
    $encoding = [System.Text.UTF8Encoding]::new($false)
    $stream = [System.IO.File]::Open($Path, [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
    try {
        $writer = [System.IO.StreamWriter]::new($stream, $encoding)
        try {
            $writer.Write($json)
            $writer.Flush()
        }
        finally {
            $writer.Dispose()
        }
    }
    finally {
        $stream.Dispose()
    }
}

function Set-ReadOnlyFile {
    param([string]$Path)
    if (Test-Path -LiteralPath $Path -PathType Leaf) {
        (Get-Item -LiteralPath $Path -Force).IsReadOnly = $true
    }
}

function Get-FileInventory {
    param([string]$Root)
    Require-Condition (Test-Path -LiteralPath $Root -PathType Container) "Inventory root is missing: $Root"
    return @(Get-ChildItem -LiteralPath $Root -Recurse -Force -File | Sort-Object FullName | ForEach-Object {
        [pscustomobject][ordered]@{
            relativePath = Get-ProjectRelativePath -Path $_.FullName -Root $Root
            lengthBytes = [int64]$_.Length
            sha256 = Get-Sha256Lower -Path $_.FullName
            readOnly = [bool]$_.IsReadOnly
        }
    })
}

function Get-InventoryContentDigest {
    param([object[]]$Inventory)
    $canonical = @($Inventory | ForEach-Object {
        [ordered]@{
            relativePath = [string]$_.relativePath
            lengthBytes = [int64]$_.lengthBytes
            sha256 = [string]$_.sha256
            readOnly = [bool]$_.readOnly
        }
    }) | ConvertTo-Json -Depth 20 -Compress
    return Get-StringSha256Lower -Value $canonical
}

function Get-DirectoryInventory {
    param([string]$Root)
    return @(Get-ChildItem -LiteralPath $Root -Recurse -Force -Directory | Sort-Object FullName | ForEach-Object {
        Get-ProjectRelativePath -Path $_.FullName -Root $Root
    })
}

function Assert-FileBinding {
    param([object]$Binding, [string]$Root)
    $path = Join-Path $Root ([string]$Binding.relativePath)
    Require-Condition (Test-Path -LiteralPath $path -PathType Leaf) "Bound file is missing: $($Binding.relativePath)"
    $item = Get-Item -LiteralPath $path -Force
    Require-Condition ([int64]$item.Length -eq [int64]$Binding.lengthBytes) "Bound file length mismatch: $($Binding.relativePath)"
    Require-Condition ((Get-Sha256Lower -Path $path) -eq ([string]$Binding.sha256).ToLowerInvariant()) "Bound file hash mismatch: $($Binding.relativePath)"
}

function Get-ProhibitedRootsPresent {
    param([string]$Root)
    $relativeRoots = @(
        'Research/PilotRuns/Gate14Re-ME',
        'Research/FormalRuns/Gate14Re-ME',
        'Research/QualificationRuns/Gate14Re-ME',
        'Research/MeasuredRuns/Gate14Re-ME'
    )
    return @($relativeRoots | Where-Object { Test-Path -LiteralPath (Join-Path $Root $_) })
}

function Get-UnityProcesses {
    return @(Get-CimInstance Win32_Process -Filter "Name = 'Unity.exe'")
}

function Convert-ToCanonicalJson {
    param([object]$Value)
    return $Value | ConvertTo-Json -Depth 100 -Compress
}

function Assert-RetainedInventory {
    param(
        [string]$Name,
        [string]$Root,
        [int]$ExpectedCount,
        [string]$ExpectedDigest
    )
    $inventory = @(Get-FileInventory -Root $Root)
    $digest = Get-InventoryContentDigest -Inventory $inventory
    Require-Condition ($inventory.Count -eq $ExpectedCount) "$Name file count mismatch."
    Require-Condition ($digest -eq $ExpectedDigest) "$Name content digest mismatch."
    Require-Condition (@($inventory | Where-Object { -not [bool]$_.readOnly }).Count -eq 0) "$Name contains a non-read-only file."
    return [pscustomobject][ordered]@{
        fileCount = $inventory.Count
        contentDigestSha256 = $digest
        allReadOnly = $true
    }
}

function Assert-ExternalFingerprint {
    param(
        [object]$Fingerprint,
        [string]$ExpectedPhase,
        [object]$TrustedRule
    )
    Require-Condition ($Fingerprint.schema -eq 'gate14re-me-external-unity-executable-fingerprint-v1') "$ExpectedPhase fingerprint schema mismatch."
    Require-Condition ($Fingerprint.studyId -eq $studyId -and $Fingerprint.authorizationId -eq $sourceAuthorizationId) "$ExpectedPhase fingerprint header mismatch."
    Require-Condition ($Fingerprint.phase -eq $ExpectedPhase) "$ExpectedPhase fingerprint phase mismatch."
    Require-Condition ($Fingerprint.path -eq $TrustedRule.applicability.unityExecutablePath) "$ExpectedPhase executable path mismatch."
    Require-Condition ([int64]$Fingerprint.lengthBytes -eq [int64]$TrustedRule.applicability.fileLengthBytes) "$ExpectedPhase file length mismatch."
    Require-Condition (-not [bool]$Fingerprint.reparsePoint) "$ExpectedPhase executable is a reparse point."
    Require-Condition ([bool]$Fingerprint.fileIdentity.succeeded) "$ExpectedPhase NTFS file identity failed."
    Require-Condition ($Fingerprint.fileIdentity.normalizedPath -eq $TrustedRule.applicability.unityExecutablePath) "$ExpectedPhase normalized path mismatch."
    Require-Condition ($Fingerprint.fileIdentity.fileIdHex -eq $TrustedRule.applicability.ntfsFileIdHex) "$ExpectedPhase NTFS file ID mismatch."
    Require-Condition ($Fingerprint.fileIdentity.fileIndexLow64Hex -eq $TrustedRule.applicability.ntfsFileIndexLow64Hex) "$ExpectedPhase NTFS low-64 file index mismatch."
    Require-Condition ([int]$Fingerprint.fileIdentity.fsutilExitCode -eq 0) "$ExpectedPhase fsutil exit code was nonzero."
    Require-Condition ([bool]$Fingerprint.peIdentity.succeeded) "$ExpectedPhase PE identity failed."
    Require-Condition ($Fingerprint.authenticode.status -eq 'Valid') "$ExpectedPhase Authenticode status is not Valid."
    Require-Condition ($Fingerprint.authenticode.signerSubject -eq $TrustedRule.applicability.signerSubject) "$ExpectedPhase signer subject mismatch."
    Require-Condition ($Fingerprint.authenticode.signerThumbprint -eq $TrustedRule.applicability.signerThumbprint) "$ExpectedPhase signer thumbprint mismatch."
    Require-Condition ([bool]$Fingerprint.independentHashMethodsAgree) "$ExpectedPhase independent SHA-256 implementations disagree."
    Require-Condition (@($Fingerprint.fullFileHashes).Count -eq 2) "$ExpectedPhase full-file hash method count mismatch."
    foreach ($hashObservation in @($Fingerprint.fullFileHashes)) {
        Require-Condition ([bool]$hashObservation.succeeded) "$ExpectedPhase full-file hash method failed: $($hashObservation.method)"
        Require-Condition ($hashObservation.sha256 -eq $expectedUnitySha256) "$ExpectedPhase Unity SHA-256 mismatch for method $($hashObservation.method)."
    }
    $methods = @($Fingerprint.fullFileHashes | ForEach-Object { [string]$_.method } | Sort-Object)
    Require-Condition ((Convert-ToCanonicalJson $methods) -eq (Convert-ToCanonicalJson @('dotnet-sha256-filestream', 'powershell-get-filehash'))) "$ExpectedPhase full-file hash method set mismatch."
    Require-Condition ([int]$Fingerprint.chunkSizeBytes -eq 65536) "$ExpectedPhase chunk size mismatch."
    $chunks = @($Fingerprint.chunkHashes)
    Require-Condition ($chunks.Count -eq 547) "$ExpectedPhase chunk count mismatch."
    [int64]$chunkBytes = 0
    for ($index = 0; $index -lt $chunks.Count; $index++) {
        $chunk = $chunks[$index]
        $expectedOffset = [int64]$index * 65536
        $expectedLength = [Math]::Min([int64]65536, [int64]$Fingerprint.lengthBytes - $expectedOffset)
        Require-Condition ([int]$chunk.chunkIndex -eq $index) "$ExpectedPhase chunk index discontinuity at $index."
        Require-Condition ([int64]$chunk.offsetBytes -eq $expectedOffset) "$ExpectedPhase chunk offset mismatch at $index."
        Require-Condition ([int64]$chunk.lengthBytes -eq $expectedLength) "$ExpectedPhase chunk length mismatch at $index."
        Require-Condition ([string]$chunk.sha256 -match '^[0-9a-f]{64}$') "$ExpectedPhase chunk hash is malformed at $index."
        $chunkBytes += [int64]$chunk.lengthBytes
    }
    Require-Condition ($chunkBytes -eq [int64]$Fingerprint.lengthBytes) "$ExpectedPhase chunk lengths do not cover the full file."

    $comparison = $Fingerprint.trustedRuleComparison
    Require-Condition ([bool]$comparison.passed -and [bool]$comparison.nonTimestampChecksPassed) "$ExpectedPhase trusted-rule comparison did not pass."
    Require-Condition ($comparison.comparatorSha256 -eq $expectedTimestampComparatorSha256) "$ExpectedPhase comparator hash binding mismatch."
    Require-Condition ($comparison.comparisonBasis -eq 'STRICT_DATETIMEOFFSET_ROUND_TRIP_TO_UTC_TICKS') "$ExpectedPhase comparator basis mismatch."
    Require-Condition ([bool]$comparison.trustedRawTextPreserved) "$ExpectedPhase trusted timestamp text was not preserved."

    $recomputed = [ordered]@{}
    foreach ($field in @('creationTimeUtc', 'lastWriteTimeUtc')) {
        $stored = $comparison.$field
        $trustedText = [string]$TrustedRule.applicability.$field
        $observedText = [string]$Fingerprint.$field
        Require-Condition ($stored.trustedOriginalText -ceq $trustedText) "$ExpectedPhase $field trusted raw text mismatch."
        Require-Condition ($stored.observedOriginalText -ceq $observedText) "$ExpectedPhase $field observed raw text mismatch."
        Require-Condition ([bool]$stored.bothParsedUniquely -and [bool]$stored.sameUtcInstant -and [bool]$stored.comparisonAccepted -and -not [bool]$stored.failClosed) "$ExpectedPhase stored $field comparison did not accept."
        Require-Condition ($stored.comparisonBasis -eq 'UTC_TICKS') "$ExpectedPhase stored $field basis mismatch."
        $fresh = Compare-Gate14ReMETrustedTimestampV1 -TrustedText $trustedText -ObservedText $observedText
        Require-Condition ([bool]$fresh.comparisonAccepted -and [bool]$fresh.bothParsedUniquely -and [bool]$fresh.sameUtcInstant) "$ExpectedPhase recomputed $field comparison failed."
        Require-Condition ([int64]$fresh.trusted.utcTicks -eq [int64]$stored.trusted.utcTicks) "$ExpectedPhase recomputed trusted $field ticks mismatch."
        Require-Condition ([int64]$fresh.observed.utcTicks -eq [int64]$stored.observed.utcTicks) "$ExpectedPhase recomputed observed $field ticks mismatch."
        $recomputed[$field] = $fresh
    }
    return [pscustomobject][ordered]@{
        phase = $ExpectedPhase
        trustedIdentityPassed = $true
        fullFileSha256 = $expectedUnitySha256
        independentHashMethodsAgree = $true
        chunkCount = $chunks.Count
        timestampsRecomputed = [pscustomobject]$recomputed
    }
}

function Assert-FingerprintStable {
    param([object]$Left, [object]$Right, [string]$Description)
    foreach ($field in @('path', 'lengthBytes', 'creationTimeUtc', 'lastWriteTimeUtc', 'attributes', 'reparsePoint', 'chunkSizeBytes')) {
        Require-Condition (([string]$Left.$field) -ceq ([string]$Right.$field)) "$Description scalar mismatch: $field"
    }
    foreach ($field in @('fileIdentity', 'peIdentity', 'authenticode', 'versionMetadata', 'fullFileHashes', 'chunkHashes')) {
        Require-Condition ((Convert-ToCanonicalJson $Left.$field) -ceq (Convert-ToCanonicalJson $Right.$field)) "$Description structured mismatch: $field"
    }
}

function Convert-ToStrictTicks {
    param([string]$Value, [string]$Description)
    $parsed = ConvertTo-Gate14ReMEStrictUtcInstantV1 -Value $Value
    Require-Condition ([bool]$parsed.parsed -and [bool]$parsed.uniqueParse) "$Description is not a strict unique timestamp."
    return [int64]$parsed.utcTicks
}

try {
    $resolvedProjectRoot = Get-NormalizedFullPath -Path $ProjectRoot -Base (Get-Location).Path
    $expectedResolvedProjectRoot = Get-NormalizedFullPath -Path $expectedProjectRoot -Base (Get-Location).Path
    Require-Condition ($resolvedProjectRoot -eq $expectedResolvedProjectRoot) "Project root mismatch: $resolvedProjectRoot"

    $stageRoot = Join-Path $resolvedProjectRoot 'Research/Verification/Gate14Re-ME/qualification-input-schema-compatibility-offline-closure-adjudication-attempt-005'
    $attempt004Root = Join-Path $resolvedProjectRoot 'Research/Verification/Gate14Re-ME/qualification-input-schema-compatibility-corrigendum-attempt-004'
    $statusV24Path = Join-Path $resolvedProjectRoot 'Research/Gate14Re-ME/Gate14Re_ME_Status.v24.json'
    $statusV25Path = Join-Path $resolvedProjectRoot 'Research/Gate14Re-ME/Gate14Re_ME_Status.v25.json'
    $authorizationPath = Join-Path $stageRoot 'authorization-receipt.v1.json'
    $stageContractPath = Join-Path $stageRoot 'stage-contract.v1.json'
    $adjudicatorPath = $MyInvocation.MyCommand.Path
    $offlineAdjudicationPath = Join-Path $stageRoot 'offline-evidence-adjudication.v1.json'
    $terminalReceiptPath = Join-Path $stageRoot 'terminal-receipt.v1.json'
    $failureReceiptPath = Join-Path $stageRoot 'failure-receipt.v1.json'
    $finalManifestPath = Join-Path $stageRoot 'source-and-evidence-freeze-manifest.v1.json'

    Require-Condition (Test-Path -LiteralPath $stageRoot -PathType Container) 'Attempt-005 stage root is missing.'
    Require-Condition (Test-Path -LiteralPath $attempt004Root -PathType Container) 'Attempt-004 evidence root is missing.'
    Require-Condition (-not (Test-Path -LiteralPath $statusV25Path)) 'Status v25 already exists; refusing to reuse this authorization.'
    Require-Condition (-not (Test-Path -LiteralPath $offlineAdjudicationPath)) 'Attempt-005 adjudication already exists.'
    Require-Condition (-not (Test-Path -LiteralPath $terminalReceiptPath)) 'Attempt-005 terminal receipt already exists.'
    Require-Condition (-not (Test-Path -LiteralPath $failureReceiptPath)) 'Attempt-005 failure receipt already exists.'
    Require-Condition (-not (Test-Path -LiteralPath $finalManifestPath)) 'Attempt-005 final manifest already exists.'
    Require-Condition (@(Get-UnityProcesses).Count -eq 0) 'Unity is running; offline adjudication requires zero Unity processes.'
    Require-Condition (@(Get-ProhibitedRootsPresent -Root $resolvedProjectRoot).Count -eq 0) 'A prohibited Gate14Re-ME measured root exists.'

    $resolvedSourceManifest = Get-NormalizedFullPath -Path $SourceFreezeManifest -Base $resolvedProjectRoot
    Require-Condition ($resolvedSourceManifest -eq (Get-NormalizedFullPath -Path (Join-Path $stageRoot 'source-freeze-manifest.v1.json') -Base $resolvedProjectRoot)) 'Source-freeze manifest path mismatch.'
    Require-Condition ((Get-Sha256Lower -Path $resolvedSourceManifest) -eq $SourceFreezeManifestSha256) 'Source-freeze manifest SHA-256 mismatch.'
    $sourceManifest = Read-JsonStrict -Path $resolvedSourceManifest
    Require-Condition ($sourceManifest.schema -eq 'gate14re-me-qualification-input-schema-compatibility-offline-closure-adjudication-attempt-005-source-freeze-manifest-v1') 'Attempt-005 source-freeze schema mismatch.'
    Require-Condition ($sourceManifest.studyId -eq $studyId -and $sourceManifest.authorizationId -eq $authorizationId) 'Attempt-005 source-freeze header mismatch.'
    Require-Condition ($sourceManifest.status -eq 'FROZEN_PREEXECUTION_OFFLINE_ADJUDICATOR_AND_EVIDENCE_BINDINGS') 'Attempt-005 source-freeze status mismatch.'
    foreach ($binding in @($sourceManifest.bindings)) {
        Assert-FileBinding -Binding $binding -Root $resolvedProjectRoot
    }
    Require-Condition (@($sourceManifest.bindings | Group-Object relativePath | Where-Object Count -ne 1).Count -eq 0) 'Attempt-005 source-freeze has duplicate bindings.'

    $authorization = Read-JsonStrict -Path $authorizationPath
    Require-Condition ($authorization.schema -eq 'gate14re-me-qualification-input-schema-compatibility-offline-closure-adjudication-authorization-v1') 'Attempt-005 authorization schema mismatch.'
    Require-Condition ($authorization.studyId -eq $studyId -and $authorization.authorizationId -eq $authorizationId) 'Attempt-005 authorization header mismatch.'
    Require-Condition ($authorization.status -eq 'AUTHORIZED_OFFLINE_READ_ONLY_CLOSURE_ADJUDICATION_NO_UNITY') 'Attempt-005 authorization status mismatch.'
    Require-Condition ($authorization.failureDisposition -eq 'FAIL_CLOSED_FREEZE_ATTEMPT_005_FAILURE_EVIDENCE_NO_RETRY_NO_ADOPTION') 'Attempt-005 failure disposition mismatch.'

    $stageContract = Read-JsonStrict -Path $stageContractPath
    Require-Condition ($stageContract.schema -eq 'gate14re-me-qualification-input-schema-compatibility-offline-closure-adjudication-attempt-005-stage-contract-v1') 'Attempt-005 stage-contract schema mismatch.'
    Require-Condition ($stageContract.studyId -eq $studyId -and $stageContract.authorizationId -eq $authorizationId) 'Attempt-005 stage-contract header mismatch.'
    Require-Condition ($stageContract.status -eq 'FROZEN_PREEXECUTION_OFFLINE_READ_ONLY_STAGE_CONTRACT') 'Attempt-005 stage-contract status mismatch.'
    Require-Condition ([int]$stageContract.executionBoundary.unityInvocationMaximum -eq 0) 'Attempt-005 stage contract unexpectedly permits Unity.'
    foreach ($field in @(
        'automaticRetryAuthorized', 'attempt004DeletionAuthorized', 'attempt004ModificationAuthorized',
        'attempt004ReclassificationAuthorized', 'scheduleGenerationAuthorized',
        'qualificationInputGenerationAuthorized', 'anonymousIdentityMappingAuthorized',
        'measuredRootCreationAuthorized', 'plannerAuthorized', 'algorithmLaneAuthorized',
        'formalCollectionAuthorized', 'formalAnalysisAuthorized', 'rankingAuthorized',
        'winnerAdjudicationAuthorized')) {
        Require-Condition (-not [bool]$stageContract.executionBoundary.$field) "Attempt-005 stage contract unexpectedly authorizes $field."
    }

    $selfText = [System.IO.File]::ReadAllText($adjudicatorPath, [System.Text.UTF8Encoding]::new($false, $true))
    $selfTokens = $null
    $selfErrors = $null
    $selfAst = [System.Management.Automation.Language.Parser]::ParseFile($adjudicatorPath, [ref]$selfTokens, [ref]$selfErrors)
    Require-Condition (@($selfErrors).Count -eq 0) 'Attempt-005 adjudicator has PowerShell parser errors.'
    $selfCommands = @($selfAst.FindAll({ param($node) $node -is [System.Management.Automation.Language.CommandAst] }, $true))
    $legacyForcedTerminationToken = 'task' + 'kill'
    Require-Condition (@($selfCommands | Where-Object { $_.GetCommandName() -in @('Start-Process', 'Stop-Process', 'Remove-Item', 'Move-Item', 'Rename-Item') }).Count -eq 0) 'Attempt-005 adjudicator contains a prohibited mutating or process-control command.'
    Require-Condition ($selfText -notmatch ("(?i)\b{0}\b" -f [regex]::Escape($legacyForcedTerminationToken))) 'Attempt-005 adjudicator contains a prohibited forced-termination utility token.'

    $attempt004Before = @(Get-FileInventory -Root $attempt004Root)
    $attempt004BeforeDigest = Get-InventoryContentDigest -Inventory $attempt004Before
    $attempt004DirectoriesBefore = @(Get-DirectoryInventory -Root $attempt004Root)
    Require-Condition ($attempt004Before.Count -eq $expectedAttempt004FileCount) 'Attempt-004 file count mismatch.'
    Require-Condition ($attempt004BeforeDigest -eq $expectedAttempt004Digest) 'Attempt-004 content digest mismatch.'
    Require-Condition (@($attempt004Before | Where-Object { -not [bool]$_.readOnly }).Count -eq 0) 'Attempt-004 contains a non-read-only file.'
    $expectedDirectories = @($sourceManifest.sourceAttempt004.directoryInventory | Sort-Object)
    Require-Condition ((Convert-ToCanonicalJson @($attempt004DirectoriesBefore | Sort-Object)) -ceq (Convert-ToCanonicalJson $expectedDirectories)) 'Attempt-004 directory residue inventory mismatch.'

    Require-Condition ((Get-Sha256Lower -Path $statusV24Path) -eq $expectedStatusV24Sha256) 'Status v24 hash mismatch.'
    Require-Condition ((Get-Item -LiteralPath $statusV24Path -Force).IsReadOnly) 'Status v24 is not read-only.'
    $statusV24 = Read-JsonStrict -Path $statusV24Path
    Require-Condition ($statusV24.schema -eq 'gate14re-me-status-v24' -and [int]$statusV24.version -eq 24) 'Status v24 schema/version mismatch.'
    Require-Condition ($statusV24.studyId -eq $studyId -and $statusV24.status -eq 'INPUT_SCHEMA_COMPATIBILITY_ATTEMPT_004_FAILED_CLOSED') 'Status v24 terminal status mismatch.'
    Require-Condition (-not [bool]$statusV24.schemaCompatibilityAttempt004.passed) 'Status v24 improperly marks attempt-004 passed.'
    Require-Condition (-not [bool]$statusV24.schemaCompatibilityAttempt004.inputSchemaV2Adopted -and -not [bool]$statusV24.schemaCompatibilityAttempt004.planningSchemaBindingV2Adopted) 'Status v24 improperly adopted a candidate schema.'
    Require-Condition (-not [bool]$statusV24.schemaCompatibilityAttempt004.retryPerformed) 'Status v24 records an unauthorized retry.'
    Require-Condition ([int]$statusV24.scientificBoundary.scheduleRowsGenerated -eq 0 -and
        [int]$statusV24.scientificBoundary.qualificationInputsGenerated -eq 0 -and
        [int]$statusV24.scientificBoundary.anonymousIdentityMappingsGenerated -eq 0 -and
        -not [bool]$statusV24.scientificBoundary.measuredRootCreated -and
        [int]$statusV24.scientificBoundary.plannerInvocations -eq 0 -and
        [int]$statusV24.scientificBoundary.algorithmLaneExecutions -eq 0 -and
        -not [bool]$statusV24.scientificBoundary.formalCollectionPerformed -and
        -not [bool]$statusV24.scientificBoundary.formalAnalysisPerformed -and
        -not [bool]$statusV24.scientificBoundary.algorithmRankingPerformed -and
        -not [bool]$statusV24.scientificBoundary.winnerAdjudicationPerformed) 'Status v24 scientific boundary is not clean.'

    $a4AuthorizationPath = Join-Path $attempt004Root 'authorization-receipt.v1.json'
    $a4StageContractPath = Join-Path $attempt004Root 'stage-contract.v1.json'
    $a4SourceFreezePath = Join-Path $attempt004Root 'source-freeze-manifest.v1.json'
    $a4FailurePath = Join-Path $attempt004Root 'failure-receipt.v1.json'
    $a4FinalManifestPath = Join-Path $attempt004Root 'source-and-evidence-freeze-manifest.v1.json'
    $a4PrelaunchPath = Join-Path $attempt004Root 'external-prelaunch-fingerprint.v1.json'
    $a4LivePath = Join-Path $attempt004Root 'external-live-fingerprint.v1.json'
    $a4PostExitPath = Join-Path $attempt004Root 'external-post-exit-fingerprint.v1.json'
    $a4LaunchPath = Join-Path $attempt004Root 'process-launch-receipt.v1.json'
    $a4ReadyPath = Join-Path $attempt004Root 'unity-output/in-process-ready-snapshot.v1.json'
    $a4UnityReceiptPath = Join-Path $attempt004Root 'unity-output/input-schema-compatibility-self-check-receipt.v2.json'
    $a4OrchestratorPath = Join-Path $attempt004Root 'Invoke-Gate14ReMEInputSchemaCompatibilityAttempt004.ps1'
    $a4SelfCheckSourcePath = Join-Path $attempt004Root 'isolated-unity-project/Assets/Editor/Gate14ReMEInputSchemaCompatibilitySelfCheckV2.cs'
    $trustedRulePath = Join-Path $resolvedProjectRoot 'Research/Verification/Gate14Re-ME/unity-executable-identity-rule-offline-adjudication-attempt-005/trusted-launch-identity-rule.v1.json'
    $timestampComparatorPath = Join-Path $resolvedProjectRoot 'Research/Verification/Gate14Re-ME/unity-trusted-identity-timestamp-comparator-corrigendum-attempt-007/Gate14ReMETrustedTimestampComparatorV1.ps1'

    Require-Condition ((Get-Sha256Lower -Path $trustedRulePath) -eq $expectedTrustedRuleSha256) 'Trusted launch identity rule hash mismatch.'
    Require-Condition ((Get-Sha256Lower -Path $timestampComparatorPath) -eq $expectedTimestampComparatorSha256) 'Attempt-007 comparator hash mismatch.'
    Require-Condition ((Get-Sha256Lower -Path (Join-Path (Split-Path -Parent $timestampComparatorPath) 'known-answer-receipt.v1.json')) -eq $expectedTimestampKnownAnswerSha256) 'Attempt-007 known-answer receipt hash mismatch.'
    . $timestampComparatorPath
    Require-Condition ($null -ne (Get-Command Compare-Gate14ReMETrustedTimestampV1 -ErrorAction Stop)) 'Attempt-007 comparator function was not loaded.'

    $trustedRule = Read-JsonStrict -Path $trustedRulePath
    Require-Condition ($trustedRule.schema -eq 'gate14re-me-unity-executable-identity-verification-rule-v1') 'Trusted launch identity rule schema mismatch.'
    Require-Condition ($trustedRule.studyId -eq $studyId -and $trustedRule.status -eq 'FROZEN_TRUSTED_IDENTITY_RULE_FROM_OFFLINE_ADJUDICATION') 'Trusted launch identity rule header mismatch.'
    Require-Condition ($trustedRule.applicability.unityExecutableExpectedSha256 -eq $expectedUnitySha256) 'Trusted rule Unity SHA-256 mismatch.'
    Require-Condition ($trustedRule.requirements.fileReadAllBytesRole -eq 'DIAGNOSTIC_ONLY' -and -not [bool]$trustedRule.requirements.inProcessSelfHashesRequiredForAuthorization) 'Trusted rule improperly promotes in-process file reads.'

    $a4Authorization = Read-JsonStrict -Path $a4AuthorizationPath
    Require-Condition ($a4Authorization.schema -eq 'gate14re-me-qualification-input-schema-compatibility-corrigendum-authorization-v4') 'Attempt-004 authorization schema mismatch.'
    Require-Condition ($a4Authorization.studyId -eq $studyId -and $a4Authorization.authorizationId -eq $sourceAuthorizationId) 'Attempt-004 authorization header mismatch.'
    Require-Condition ($a4Authorization.status -eq 'AUTHORIZED_ONE_ISOLATED_ALGORITHM_FREE_UNITY_SCHEMA_COMPATIBILITY_SELF_CHECK') 'Attempt-004 authorization status mismatch.'
    Require-Condition ($a4Authorization.failureDisposition -eq 'FAIL_CLOSED_FREEZE_ALL_EVIDENCE_NO_RETRY_NO_ADOPTION') 'Attempt-004 authorization failure disposition mismatch.'

    $a4StageContract = Read-JsonStrict -Path $a4StageContractPath
    Require-Condition ($a4StageContract.schema -eq 'gate14re-me-input-schema-compatibility-attempt-004-stage-contract-v1') 'Attempt-004 stage contract schema mismatch.'
    Require-Condition ($a4StageContract.studyId -eq $studyId -and $a4StageContract.authorizationId -eq $sourceAuthorizationId) 'Attempt-004 stage contract header mismatch.'
    Require-Condition ($a4StageContract.status -eq 'FROZEN_PREEXECUTION_STAGE_CONTRACT') 'Attempt-004 stage contract status mismatch.'
    Require-Condition ([int]$a4StageContract.executionBoundary.unityInvocationMaximum -eq 1 -and [int]$a4StageContract.executionBoundary.schemaCompatibilitySelfCheckInvocationMaximum -eq 1) 'Attempt-004 invocation maxima mismatch.'
    Require-Condition (-not [bool]$a4StageContract.executionBoundary.automaticRetryAuthorized -and [bool]$a4StageContract.executionBoundary.naturalExitRequired -and -not [bool]$a4StageContract.executionBoundary.signalOrForcedTerminationAuthorized) 'Attempt-004 process boundary mismatch.'

    $a4SourceFreeze = Read-JsonStrict -Path $a4SourceFreezePath
    Require-Condition ($a4SourceFreeze.schema -eq 'gate14re-me-input-schema-compatibility-attempt-004-source-freeze-manifest-v1') 'Attempt-004 source-freeze schema mismatch.'
    Require-Condition ($a4SourceFreeze.studyId -eq $studyId -and $a4SourceFreeze.authorizationId -eq $sourceAuthorizationId) 'Attempt-004 source-freeze header mismatch.'
    Require-Condition ($a4SourceFreeze.status -eq 'FROZEN_PREEXECUTION_SOURCES_AND_BINDINGS') 'Attempt-004 source-freeze status mismatch.'
    Require-Condition (@($a4SourceFreeze.bindings).Count -eq 23) 'Attempt-004 source-freeze binding count mismatch.'
    foreach ($binding in @($a4SourceFreeze.bindings)) {
        Assert-FileBinding -Binding $binding -Root $resolvedProjectRoot
    }
    Require-Condition ([int]$a4SourceFreeze.authorizedIntegration.powershellParserErrorCount -eq 0 -and
        [int]$a4SourceFreeze.authorizedIntegration.startProcessSyntacticCount -eq 1 -and
        [int]$a4SourceFreeze.authorizedIntegration.stopOrKillProcessSyntacticCount -eq 0 -and
        -not [bool]$a4SourceFreeze.authorizedIntegration.scientificSchemaAssertionsChanged -and
        -not [bool]$a4SourceFreeze.authorizedIntegration.trustedLaunchIdentityRuleModified -and
        -not [bool]$a4SourceFreeze.authorizedIntegration.nonTimestampIdentityRequirementsWeakened) 'Attempt-004 source-freeze integration boundary mismatch.'

    $retained001 = Assert-RetainedInventory -Name 'attempt-001' -Root (Join-Path $resolvedProjectRoot 'Research/Verification/Gate14Re-ME/qualification-input-schema-compatibility-corrigendum-attempt-001') -ExpectedCount 6 -ExpectedDigest 'f8401239543226c4b96d89b08db2150e7e578b55afc53e7f80aaa7062fd03fb3'
    $retained002 = Assert-RetainedInventory -Name 'attempt-002' -Root (Join-Path $resolvedProjectRoot 'Research/Verification/Gate14Re-ME/qualification-input-schema-compatibility-corrigendum-attempt-002') -ExpectedCount 14 -ExpectedDigest '6feaa2fa863bf1546e5e7d7fe6367ad4da605b7318936e4c0189baa7ab33f9fc'
    $retained003 = Assert-RetainedInventory -Name 'attempt-003' -Root (Join-Path $resolvedProjectRoot 'Research/Verification/Gate14Re-ME/qualification-input-schema-compatibility-corrigendum-attempt-003') -ExpectedCount 15 -ExpectedDigest '770a7f1bf25f763d42186bba77a148280dde6193e05f9887ed0d9a5ffe02deef'
    $retainedComparator007 = Assert-RetainedInventory -Name 'timestamp comparator attempt-007' -Root (Split-Path -Parent $timestampComparatorPath) -ExpectedCount 15 -ExpectedDigest 'cfe7185263dcc343bbf143291246d1ca2e68b050f328d271d8770e2e215bf9f5'

    Require-Condition ((Get-Sha256Lower -Path $a4FailurePath) -eq $expectedFailureReceiptSha256) 'Attempt-004 failure receipt hash mismatch.'
    $a4Failure = Read-JsonStrict -Path $a4FailurePath
    Require-Condition ($a4Failure.schema -eq 'gate14re-me-input-schema-compatibility-attempt-004-failure-receipt-v1') 'Attempt-004 failure receipt schema mismatch.'
    Require-Condition ($a4Failure.status -eq 'FAILED_CLOSED_INPUT_SCHEMA_COMPATIBILITY_ATTEMPT_004') 'Attempt-004 failure receipt status mismatch.'
    Require-Condition ($a4Failure.exceptionType -eq 'System.Management.Automation.PropertyNotFoundException') 'Attempt-004 exception type mismatch.'
    Require-Condition ($a4Failure.exactFailure -eq "The property 'Sum' cannot be found on this object. Verify that the property exists.") 'Attempt-004 exact failure mismatch.'
    Require-Condition ($a4Failure.stackTrace -match 'Remove-IsolatedUnityTransientCaches.+line 386' -and $a4Failure.stackTrace -match '<ScriptBlock>.+line 705') 'Attempt-004 failure stack does not bind frozen lines 386 and 705.'
    Require-Condition ([int]$a4Failure.unityInvocationCount -eq 1 -and [int]$a4Failure.unityExitCode -eq 0) 'Attempt-004 Unity invocation count or natural exit code mismatch.'
    Require-Condition (-not [bool]$a4Failure.retryPerformed -and -not [bool]$a4Failure.signalOrForcedTerminationSent) 'Attempt-004 records retry or forced termination.'
    Require-Condition (-not [bool]$a4Failure.candidateAdoption.inputSchemaV2Adopted -and -not [bool]$a4Failure.candidateAdoption.planningSchemaBindingV2Adopted) 'Attempt-004 failure receipt improperly adopted schemas.'
    Require-Condition ([int]$a4Failure.scientificBoundary.schemaCompatibilitySelfCheckInvocations -eq 1 -and
        [int]$a4Failure.scientificBoundary.scheduleRowsGenerated -eq 0 -and
        [int]$a4Failure.scientificBoundary.qualificationInputsGenerated -eq 0 -and
        [int]$a4Failure.scientificBoundary.anonymousIdentityMappingsGenerated -eq 0 -and
        -not [bool]$a4Failure.scientificBoundary.measuredRootCreated -and
        [int]$a4Failure.scientificBoundary.plannerInvocations -eq 0 -and
        [int]$a4Failure.scientificBoundary.algorithmLaneExecutions -eq 0 -and
        -not [bool]$a4Failure.scientificBoundary.formalCollectionPerformed -and
        -not [bool]$a4Failure.scientificBoundary.formalAnalysisPerformed -and
        -not [bool]$a4Failure.scientificBoundary.algorithmRankingPerformed -and
        -not [bool]$a4Failure.scientificBoundary.winnerAdjudicationPerformed) 'Attempt-004 failure-receipt scientific boundary is not clean.'
    Require-Condition (@($a4Failure.scientificBoundary.transientIsolatedUnityCachesRemoved).Count -eq 0) 'Attempt-004 failure receipt unexpectedly finalized a cache-removal ledger.'
    foreach ($evidenceName in @('attempt001Evidence', 'attempt002Evidence', 'attempt003Evidence')) {
        $evidence = $a4Failure.$evidenceName
        Require-Condition ([bool]$evidence.unchanged -and -not [bool]$evidence.reclassified -and $evidence.beforeContentDigestSha256 -eq $evidence.afterContentDigestSha256) "Attempt-004 $evidenceName was changed or reclassified."
    }
    Require-Condition ([bool]$a4Failure.timestampComparatorAttempt007Evidence.unchanged -and -not [bool]$a4Failure.timestampComparatorAttempt007Evidence.modified) 'Attempt-007 comparator evidence changed during attempt-004.'

    $prelaunch = Read-JsonStrict -Path $a4PrelaunchPath
    $live = Read-JsonStrict -Path $a4LivePath
    $postExit = Read-JsonStrict -Path $a4PostExitPath
    $prelaunchCheck = Assert-ExternalFingerprint -Fingerprint $prelaunch -ExpectedPhase 'EXTERNAL_PRELAUNCH' -TrustedRule $trustedRule
    $liveCheck = Assert-ExternalFingerprint -Fingerprint $live -ExpectedPhase 'EXTERNAL_WHILE_AUTHORIZED_PID_ALIVE' -TrustedRule $trustedRule
    $postExitCheck = Assert-ExternalFingerprint -Fingerprint $postExit -ExpectedPhase 'EXTERNAL_POST_EXIT' -TrustedRule $trustedRule
    Assert-FingerprintStable -Left $prelaunch -Right $live -Description 'prelaunch/live external identity'
    Assert-FingerprintStable -Left $prelaunch -Right $postExit -Description 'prelaunch/post-exit external identity'

    $launch = Read-JsonStrict -Path $a4LaunchPath
    $ready = Read-JsonStrict -Path $a4ReadyPath
    Require-Condition ($launch.schema -eq 'gate14re-me-input-schema-compatibility-unity-launch-receipt-v1') 'Attempt-004 launch receipt schema mismatch.'
    Require-Condition ($launch.studyId -eq $studyId -and $launch.authorizationId -eq $sourceAuthorizationId) 'Attempt-004 launch receipt header mismatch.'
    Require-Condition ($launch.status -eq 'ONE_ISOLATED_ALGORITHM_FREE_UNITY_SCHEMA_SELF_CHECK_LAUNCHED' -and [int]$launch.invocationOrdinal -eq 1) 'Attempt-004 launch status or ordinal mismatch.'
    Require-Condition ($launch.executablePath -eq $trustedRule.applicability.unityExecutablePath -and $launch.executeMethod -eq $expectedExecuteMethod) 'Attempt-004 launch executable or execute method mismatch.'
    Require-Condition (-not [bool]$launch.retryAuthorized -and -not [bool]$launch.plannerAuthorized -and -not [bool]$launch.algorithmLaneAuthorized) 'Attempt-004 launch receipt widens authorization.'
    Require-Condition ($launch.commandLine.Contains($expectedExecuteMethod)) 'Attempt-004 command line is missing the execute method.'
    Require-Condition ($launch.commandLine -match '(?i)-batchmode' -and $launch.commandLine -match '(?i)-nographics' -and $launch.commandLine -match '(?i)-quit') 'Attempt-004 command line is missing the isolated batch-mode controls.'
    Require-Condition ($launch.commandLine -match [regex]::Escape('qualification-input-schema-compatibility-corrigendum-attempt-004\isolated-unity-project')) 'Attempt-004 command line is missing the isolated project path.'
    Require-Condition ($launch.commandLine -notmatch '(?i)LoadQualificationRunner|QualificationPlanner|Gate14ReMEReferenceOracleV1\.Run') 'Attempt-004 command line contains a prohibited planner or algorithm entry point.'

    Require-Condition ($ready.schema -eq 'gate14re-me-input-schema-compatibility-in-process-ready-snapshot-v1') 'Attempt-004 ready snapshot schema mismatch.'
    Require-Condition ($ready.studyId -eq $studyId -and $ready.authorizationId -eq $sourceAuthorizationId -and $ready.status -eq 'IN_PROCESS_SCHEMA_SELF_CHECK_IDENTITY_READY') 'Attempt-004 ready snapshot header mismatch.'
    Require-Condition (-not [bool]$ready.schemaCompatibilitySelfCheckInvoked -and -not [bool]$ready.plannerInvoked -and -not [bool]$ready.algorithmLaneExecuted -and -not [bool]$ready.measuredRootCreated) 'Attempt-004 ready snapshot shows premature or prohibited activity.'
    Require-Condition ([int]$ready.process.processId -eq [int]$launch.processId) 'Attempt-004 PID mismatch between launch and ready evidence.'
    Require-Condition ([bool]$ready.process.allExecutablePathsEqual) 'Attempt-004 in-process executable paths disagree.'
    foreach ($field in @('editorApplicationPath', 'processMainModulePath', 'queryFullProcessImageNamePath')) {
        Require-Condition ($ready.process.$field -eq $trustedRule.applicability.unityExecutablePath) "Attempt-004 ready snapshot $field mismatch."
    }
    Require-Condition ([int64]$ready.process.fileLengthBytes -eq [int64]$trustedRule.applicability.fileLengthBytes) 'Attempt-004 ready snapshot file length mismatch.'
    Require-Condition ([bool]$ready.process.fileIdentity.succeeded -and $ready.process.fileIdentity.fileIndexLow64Hex -eq $trustedRule.applicability.ntfsFileIndexLow64Hex) 'Attempt-004 ready snapshot NTFS identity mismatch.'
    Require-Condition ([bool]$ready.process.peIdentity.succeeded) 'Attempt-004 ready snapshot PE identity failed.'
    $launchTicks = Convert-ToStrictTicks -Value ([string]$launch.creationTimeUtc) -Description 'launch creationTimeUtc'
    $readyTicks = Convert-ToStrictTicks -Value ([string]$ready.process.processStartTimeUtc) -Description 'ready processStartTimeUtc'
    $processStartDeltaTicks = [Math]::Abs($launchTicks - $readyTicks)
    Require-Condition ($processStartDeltaTicks -le 10000) "Attempt-004 WMI/.NET process start times differ by more than 1 ms: $processStartDeltaTicks ticks."

    Require-Condition ((Get-Sha256Lower -Path $a4UnityReceiptPath) -eq $expectedUnityReceiptSha256) 'Attempt-004 Unity terminal schema receipt hash mismatch.'
    $unityReceipt = Read-JsonStrict -Path $a4UnityReceiptPath
    Require-Condition ($unityReceipt.schema -eq 'gate14re-me-input-schema-compatibility-unity-self-check-receipt-v2') 'Attempt-004 Unity receipt schema mismatch.'
    Require-Condition ($unityReceipt.studyId -eq $studyId -and $unityReceipt.authorizationId -eq $sourceAuthorizationId) 'Attempt-004 Unity receipt header mismatch.'
    Require-Condition ($unityReceipt.status -eq 'PASS_INPUT_SCHEMA_COMPATIBILITY_UNITY_SELF_CHECK_ATTEMPT_004' -and [bool]$unityReceipt.passed -and [bool]$unityReceipt.terminal) 'Attempt-004 Unity schema receipt is not terminal PASS.'
    foreach ($field in @(
        'authorizationHeaderPassed', 'trustedIdentityRuleHeaderPassed', 'planningBindingHeaderPassed',
        'retainedSchemaKnownAnswerPassed', 'sourceAndEvidenceBindingsPassed',
        'prohibitedRootsAbsentBefore', 'prohibitedRootsAbsentAfter',
        'inProcessStructuralIdentityStableAcrossHold', 'reflectionTargetFound',
        'jsonUtilitySerializedTopology', 'jsonUtilityRoundTripPreservedTopology',
        'positiveOracleHeaderPassed', 'missingTopologyJsonControlConstructed',
        'missingTopologyOracleHeaderFailedAsExpected', 'mismatchedTopologyJsonControlConstructed',
        'mismatchedTopologyOracleHeaderFailedAsExpected')) {
        Require-Condition ([bool]$unityReceipt.$field) "Attempt-004 Unity schema assertion failed: $field"
    }
    Require-Condition (-not [bool]$unityReceipt.inProcessFileReadHashesAuthoritative) 'Attempt-004 receipt improperly treats in-process byte reads as authoritative.'
    Require-Condition ($unityReceipt.expectedOracleFailureMessage -eq $expectedOracleFailure -and
        $unityReceipt.missingTopologyObservedFailure -eq $expectedOracleFailure -and
        $unityReceipt.mismatchedTopologyObservedFailure -eq $expectedOracleFailure) 'Attempt-004 negative-control failure reason mismatch.'
    Require-Condition ([int]$unityReceipt.schemaCompatibilitySelfCheckInvocations -eq 1 -and
        [int]$unityReceipt.scheduleRowsGenerated -eq 0 -and
        [int]$unityReceipt.qualificationInputsGenerated -eq 0 -and
        [int]$unityReceipt.anonymousIdentityMappingsGenerated -eq 0 -and
        -not [bool]$unityReceipt.qualificationMeasuredRootCreated -and
        [int]$unityReceipt.plannerInvocations -eq 0 -and
        [int]$unityReceipt.algorithmLaneExecutions -eq 0 -and
        -not [bool]$unityReceipt.formalCollectionPerformed -and
        -not [bool]$unityReceipt.formalAnalysisPerformed -and
        -not [bool]$unityReceipt.algorithmRankingPerformed -and
        -not [bool]$unityReceipt.winnerAdjudicationPerformed) 'Attempt-004 Unity receipt scientific boundary is not clean.'
    foreach ($binding in @($unityReceipt.bindings)) {
        $bindingPath = Join-Path $resolvedProjectRoot ([string]$binding.relativePath)
        Require-Condition ([bool]$binding.matched) "Unity receipt binding was not matched: $($binding.role)"
        Require-Condition (Test-Path -LiteralPath $bindingPath -PathType Leaf) "Unity receipt bound file is missing: $($binding.relativePath)"
        Require-Condition ([int64](Get-Item -LiteralPath $bindingPath).Length -eq [int64]$binding.lengthBytes) "Unity receipt bound length mismatch: $($binding.role)"
        $actualHash = Get-Sha256Lower -Path $bindingPath
        Require-Condition ($actualHash -eq $binding.expectedSha256 -and $actualHash -eq $binding.actualSha256) "Unity receipt bound hash mismatch: $($binding.role)"
    }
    Require-Condition ([int]$unityReceipt.initialProcessIdentity.processId -eq [int]$launch.processId -and [int]$unityReceipt.afterHoldProcessIdentity.processId -eq [int]$launch.processId) 'Attempt-004 PID mismatch across process receipts.'
    Require-Condition ((Convert-ToCanonicalJson $unityReceipt.initialProcessIdentity) -ceq (Convert-ToCanonicalJson $ready.process)) 'Attempt-004 ready snapshot and initial terminal-receipt process identity differ.'
    foreach ($field in @('processStartTimeUtc', 'editorApplicationPath', 'processMainModulePath', 'queryFullProcessImageNamePath', 'fileLengthBytes', 'creationTimeUtc', 'lastWriteTimeUtc')) {
        Require-Condition (([string]$unityReceipt.initialProcessIdentity.$field) -ceq ([string]$unityReceipt.afterHoldProcessIdentity.$field)) "Attempt-004 in-process identity changed across hold: $field"
    }
    Require-Condition ((Convert-ToCanonicalJson $unityReceipt.initialProcessIdentity.fileIdentity) -ceq (Convert-ToCanonicalJson $unityReceipt.afterHoldProcessIdentity.fileIdentity)) 'Attempt-004 NTFS identity changed across hold.'
    Require-Condition ((Convert-ToCanonicalJson $unityReceipt.initialProcessIdentity.peIdentity) -ceq (Convert-ToCanonicalJson $unityReceipt.afterHoldProcessIdentity.peIdentity)) 'Attempt-004 PE identity changed across hold.'

    Require-Condition ((Get-Sha256Lower -Path $a4OrchestratorPath) -eq $expectedOrchestratorSha256) 'Attempt-004 orchestrator hash mismatch.'
    Require-Condition ((Get-Sha256Lower -Path $a4SelfCheckSourcePath) -eq $expectedSelfCheckSourceSha256) 'Attempt-004 Unity self-check source hash mismatch.'
    $orchestratorLines = Get-Content -LiteralPath $a4OrchestratorPath
    Require-Condition ($orchestratorLines.Count -ge 705) 'Attempt-004 orchestrator is shorter than frozen failure lines.'
    Require-Condition ($orchestratorLines[385].Trim() -eq '$beforeBytes = [int64](Get-ChildItem -LiteralPath $target -Recurse -Force -File -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum') 'Attempt-004 frozen failure expression at line 386 mismatch.'
    Require-Condition ($orchestratorLines[704].Trim() -eq '$transientCleanup = @(Remove-IsolatedUnityTransientCaches -IsolatedProjectRoot $isolatedProjectRoot -AuthorizedStageRoot $stageRoot)') 'Attempt-004 frozen cleanup call at line 705 mismatch.'
    $orchestratorText = [System.IO.File]::ReadAllText($a4OrchestratorPath, [System.Text.UTF8Encoding]::new($false, $true))
    $cleanupLoopNeedle = 'foreach (' + [char]36 + "name in @('Library', 'Temp', 'Logs', 'obj', 'UserSettings'))"
    Require-Condition ($orchestratorText.Contains($cleanupLoopNeedle)) 'Attempt-004 transient-cache order mismatch.'
    $a4Tokens = $null
    $a4Errors = $null
    $a4Ast = [System.Management.Automation.Language.Parser]::ParseFile($a4OrchestratorPath, [ref]$a4Tokens, [ref]$a4Errors)
    Require-Condition (@($a4Errors).Count -eq 0) 'Attempt-004 orchestrator has parser errors.'
    $a4Commands = @($a4Ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.CommandAst] }, $true))
    Require-Condition (@($a4Commands | Where-Object { $_.GetCommandName() -eq 'Start-Process' }).Count -eq 1) 'Attempt-004 Start-Process syntax count mismatch.'
    Require-Condition (@($a4Commands | Where-Object { $_.GetCommandName() -in @('Stop-Process', $legacyForcedTerminationToken) }).Count -eq 0) 'Attempt-004 contains prohibited process termination syntax.'
    $selfCheckText = [System.IO.File]::ReadAllText($a4SelfCheckSourcePath, [System.Text.UTF8Encoding]::new($false, $true))
    Require-Condition ($selfCheckText.Contains('ValidateGroupHeader') -and $selfCheckText.Contains('jsonUtilityRoundTripPreservedTopology')) 'Attempt-004 self-check source lacks the frozen validator and topology assertions.'

    $isolatedRoot = Join-Path $attempt004Root 'isolated-unity-project'
    $libraryPath = Join-Path $isolatedRoot 'Library'
    $tempPath = Join-Path $isolatedRoot 'Temp'
    $logsPath = Join-Path $isolatedRoot 'Logs'
    $objPath = Join-Path $isolatedRoot 'obj'
    $userSettingsPath = Join-Path $isolatedRoot 'UserSettings'
    Require-Condition (-not (Test-Path -LiteralPath $libraryPath)) 'Attempt-004 residual Library directory is unexpectedly present.'
    Require-Condition (-not (Test-Path -LiteralPath $tempPath)) 'Attempt-004 residual Temp directory is unexpectedly present.'
    Require-Condition (Test-Path -LiteralPath $logsPath -PathType Container) 'Attempt-004 residual Logs directory is missing.'
    Require-Condition (@(Get-ChildItem -LiteralPath $logsPath -Recurse -Force -File).Count -eq 0) 'Attempt-004 residual Logs directory is not empty.'
    Require-Condition (-not (Test-Path -LiteralPath $objPath)) 'Attempt-004 residual obj directory is unexpectedly present.'
    Require-Condition (Test-Path -LiteralPath $userSettingsPath -PathType Container) 'Attempt-004 residual UserSettings directory is missing.'
    $emptyMeasure = @() | Measure-Object -Property Length -Sum
    Require-Condition ($null -eq $emptyMeasure) 'Empty-pipeline Measure-Object behavior no longer matches the frozen failure mechanism.'
    $unityCompletedTicks = Convert-ToStrictTicks -Value ([string]$unityReceipt.completedAtUtc) -Description 'Unity receipt completedAtUtc'
    $postExitTicks = Convert-ToStrictTicks -Value ([string]$postExit.capturedAtUtc) -Description 'post-exit fingerprint capturedAtUtc'
    $failedTicks = Convert-ToStrictTicks -Value ([string]$a4Failure.failedAtUtc) -Description 'attempt-004 failedAtUtc'
    Require-Condition ($unityCompletedTicks -le $postExitTicks -and $postExitTicks -le $failedTicks) 'Attempt-004 timestamps do not prove scientific completion and post-exit identity before cleanup failure.'

    $a4FinalManifest = Read-JsonStrict -Path $a4FinalManifestPath
    Require-Condition ((Get-Sha256Lower -Path $a4FinalManifestPath) -eq $expectedFinalAttempt004ManifestSha256) 'Attempt-004 terminal evidence manifest hash mismatch.'
    Require-Condition ($a4FinalManifest.schema -eq 'gate14re-me-input-schema-compatibility-attempt-004-evidence-freeze-manifest-v1') 'Attempt-004 terminal evidence manifest schema mismatch.'
    Require-Condition ($a4FinalManifest.studyId -eq $studyId -and $a4FinalManifest.authorizationId -eq $sourceAuthorizationId -and $a4FinalManifest.status -eq 'FROZEN_TERMINAL_FAILURE_EVIDENCE') 'Attempt-004 terminal evidence manifest header mismatch.'
    Require-Condition ($a4FinalManifest.statusV24.sha256 -eq $expectedStatusV24Sha256) 'Attempt-004 manifest Status v24 binding mismatch.'
    Require-Condition (@($a4FinalManifest.evidenceFiles).Count -eq 54) 'Attempt-004 terminal evidence manifest entry count mismatch.'
    $manifestPaths = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($entry in @($a4FinalManifest.evidenceFiles)) {
        $entryPath = Join-Path $resolvedProjectRoot ([string]$entry.relativePath)
        Require-Condition ($manifestPaths.Add([string]$entry.relativePath)) "Duplicate attempt-004 terminal manifest path: $($entry.relativePath)"
        Require-Condition (Test-Path -LiteralPath $entryPath -PathType Leaf) "Attempt-004 terminal manifest file is missing: $($entry.relativePath)"
        Require-Condition ([int64](Get-Item -LiteralPath $entryPath).Length -eq [int64]$entry.lengthBytes) "Attempt-004 terminal manifest length mismatch: $($entry.relativePath)"
        Require-Condition ((Get-Sha256Lower -Path $entryPath) -eq $entry.sha256) "Attempt-004 terminal manifest hash mismatch: $($entry.relativePath)"
    }
    $actualWithoutFinalManifest = @($attempt004Before | Where-Object { $_.relativePath -ne 'source-and-evidence-freeze-manifest.v1.json' })
    Require-Condition ($actualWithoutFinalManifest.Count -eq 54) 'Attempt-004 actual evidence count excluding terminal manifest mismatch.'
    foreach ($entry in $actualWithoutFinalManifest) {
        $projectRelative = Get-ProjectRelativePath -Path (Join-Path $attempt004Root $entry.relativePath) -Root $resolvedProjectRoot
        Require-Condition ($manifestPaths.Contains($projectRelative)) "Attempt-004 terminal manifest omits: $projectRelative"
    }

    Require-Condition ((Get-Sha256Lower -Path (Join-Path $resolvedProjectRoot 'Research/Gate14Re-ME/Execution/v2/load-qualification-input-schema.v2.json')) -eq $expectedInputSchemaSha256) 'Candidate input schema v2 hash mismatch.'
    Require-Condition ((Get-Sha256Lower -Path (Join-Path $resolvedProjectRoot 'Research/Gate14Re-ME/Execution/v2/load-qualification-planning-schema-binding.v2.json')) -eq $expectedPlanningBindingSha256) 'Candidate planning schema binding v2 hash mismatch.'

    $attempt004After = @(Get-FileInventory -Root $attempt004Root)
    $attempt004AfterDigest = Get-InventoryContentDigest -Inventory $attempt004After
    $attempt004DirectoriesAfter = @(Get-DirectoryInventory -Root $attempt004Root)
    Require-Condition ($attempt004AfterDigest -eq $attempt004BeforeDigest -and $attempt004AfterDigest -eq $expectedAttempt004Digest) 'Attempt-004 changed during offline adjudication.'
    Require-Condition ((Convert-ToCanonicalJson $attempt004After) -ceq (Convert-ToCanonicalJson $attempt004Before)) 'Attempt-004 file inventory changed during offline adjudication.'
    Require-Condition ((Convert-ToCanonicalJson $attempt004DirectoriesAfter) -ceq (Convert-ToCanonicalJson $attempt004DirectoriesBefore)) 'Attempt-004 directory residue changed during offline adjudication.'
    Require-Condition ((Get-Sha256Lower -Path $statusV24Path) -eq $expectedStatusV24Sha256) 'Status v24 changed during offline adjudication.'
    Require-Condition (@(Get-UnityProcesses).Count -eq 0) 'Unity appeared during offline adjudication.'
    Require-Condition (@(Get-ProhibitedRootsPresent -Root $resolvedProjectRoot).Count -eq 0) 'A prohibited Gate14Re-ME root appeared during offline adjudication.'

    $adjudicatedAtUtc = [DateTime]::UtcNow.ToString('o')
    $scientificBoundary = [ordered]@{
        offlineAdjudicatorInvocations = 1
        unityInvocations = 0
        schemaCompatibilitySelfCheckInvocations = 0
        scheduleRowsGenerated = 0
        qualificationInputsGenerated = 0
        anonymousIdentityMappingsGenerated = 0
        measuredRootCreated = $false
        plannerInvocations = 0
        algorithmLaneExecutions = 0
        formalCollectionPerformed = $false
        formalAnalysisPerformed = $false
        algorithmRankingPerformed = $false
        winnerAdjudicationPerformed = $false
    }
    $adjudication = [ordered]@{
        schema = 'gate14re-me-qualification-input-schema-compatibility-offline-closure-adjudication-attempt-005-v1'
        studyId = $studyId
        authorizationId = $authorizationId
        status = 'PASS_OFFLINE_CLOSURE_ADJUDICATION_INPUT_SCHEMA_V2_AND_PLANNING_BINDING_V2_ELIGIBLE_FOR_ADOPTION'
        adjudicatedAtUtc = $adjudicatedAtUtc
        passed = $true
        sourceAttempt = [ordered]@{
            authorizationId = $sourceAuthorizationId
            retainedOutcome = 'FAILED_CLOSED_INPUT_SCHEMA_COMPATIBILITY_ATTEMPT_004'
            reclassified = $false
            modified = $false
            deleted = $false
            beforeFileCount = $attempt004Before.Count
            afterFileCount = $attempt004After.Count
            beforeContentDigestSha256 = $attempt004BeforeDigest
            afterContentDigestSha256 = $attempt004AfterDigest
            directoriesUnchanged = $true
            allFilesReadOnly = $true
        }
        sourceEvidenceChecks = [ordered]@{
            authorizationPassed = $true
            stageContractPassed = $true
            sourceFreezeBindingsPassed = $true
            terminalFailureReceiptPreserved = $true
            terminalEvidenceManifestPassed = $true
            statusV24Preserved = $true
        }
        schemaCompatibility = [ordered]@{
            unityTerminalReceiptPassed = $true
            authorizationHeaderPassed = $true
            trustedIdentityRuleHeaderPassed = $true
            planningBindingHeaderPassed = $true
            retainedSchemaKnownAnswerPassed = $true
            sourceAndEvidenceBindingsPassed = $true
            jsonUtilitySerializedTopology = $true
            jsonUtilityRoundTripPreservedTopology = $true
            validatorActuallyInvoked = $true
            matchingTopologyPassed = $true
            missingTopologyFailedForFrozenReason = $true
            mismatchedTopologyFailedForFrozenReason = $true
            frozenFailureReason = $expectedOracleFailure
        }
        trustedIdentity = [ordered]@{
            trustedRuleSha256 = $expectedTrustedRuleSha256
            timestampComparatorSha256 = $expectedTimestampComparatorSha256
            timestampKnownAnswerReceiptSha256 = $expectedTimestampKnownAnswerSha256
            prelaunch = $prelaunchCheck
            liveConcurrent = $liveCheck
            postExit = $postExitCheck
            threePhaseExternalIdentityStable = $true
            inProcessStructuralIdentityStableAcrossHold = $true
            inProcessFileReadHashesAuthoritative = $false
        }
        processCompositeIdentity = [ordered]@{
            processId = [int]$launch.processId
            launchCreationTimeUtc = [string]$launch.creationTimeUtc
            readyProcessStartTimeUtc = [string]$ready.process.processStartTimeUtc
            startTimeDeltaTicks = $processStartDeltaTicks
            startTimeToleranceTicks = 10000
            executablePath = [string]$launch.executablePath
            executeMethod = [string]$launch.executeMethod
            isolatedProjectRelativePath = [string]$launch.isolatedProjectRelativePath
            commandLineBound = $true
            unityInvocationCount = 1
            naturalExitCode = 0
            forcedTerminationSent = $false
        }
        postScientificCleanupFailure = [ordered]@{
            scientificReceiptCompletedAtUtc = [string]$unityReceipt.completedAtUtc
            postExitFingerprintCapturedAtUtc = [string]$postExit.capturedAtUtc
            failureRecordedAtUtc = [string]$a4Failure.failedAtUtc
            chronologyPassed = $true
            frozenFailureLine = 386
            frozenCallerLine = 705
            exactFailure = [string]$a4Failure.exactFailure
            LibraryAbsentAfterAuthorizedCleanup = $true
            TempAbsentAfterAuthorizedCleanup = $true
            LogsPresentAndEmptyAtFailure = $true
            objAbsent = $true
            UserSettingsRetained = $true
            emptyPipelineMeasureObjectReturnedNull = $true
            failureClassification = 'POST_RESULT_EMPTY_DIRECTORY_CACHE_SIZE_ACCOUNTING_ONLY'
        }
        retainedEvidence = [ordered]@{
            attempt001 = $retained001
            attempt002 = $retained002
            attempt003 = $retained003
            timestampComparatorAttempt007 = $retainedComparator007
        }
        candidateAdoption = [ordered]@{
            inputSchemaV2 = [ordered]@{
                adopted = $true
                relativePath = 'Research/Gate14Re-ME/Execution/v2/load-qualification-input-schema.v2.json'
                sha256 = $expectedInputSchemaSha256
            }
            planningSchemaBindingV2 = [ordered]@{
                adopted = $true
                relativePath = 'Research/Gate14Re-ME/Execution/v2/load-qualification-planning-schema-binding.v2.json'
                sha256 = $expectedPlanningBindingSha256
            }
        }
        scientificBoundary = $scientificBoundary
        nextAuthorizationRequired = 'A new separate authorization is required before qualification planning freeze, schedule/input/anonymous-map generation, measured-root creation, planner or algorithm-lane execution, formal collection, analysis, ranking or winner adjudication.'
    }
    Write-JsonExclusive -Path $offlineAdjudicationPath -Value $adjudication

    $terminalReceipt = [ordered]@{
        schema = 'gate14re-me-qualification-input-schema-compatibility-offline-closure-adjudication-attempt-005-terminal-receipt-v1'
        studyId = $studyId
        authorizationId = $authorizationId
        status = 'PASS_INPUT_SCHEMA_V2_AND_PLANNING_SCHEMA_BINDING_V2_ADOPTED_BY_OFFLINE_CLOSURE'
        completedAtUtc = [DateTime]::UtcNow.ToString('o')
        passed = $true
        terminal = $true
        unityLaunched = $false
        sourceAttemptOutcomeRetained = 'FAILED_CLOSED_INPUT_SCHEMA_COMPATIBILITY_ATTEMPT_004'
        sourceAttemptReclassified = $false
        sourceAttemptModified = $false
        offlineAdjudication = [ordered]@{
            relativePath = Get-ProjectRelativePath -Path $offlineAdjudicationPath -Root $resolvedProjectRoot
            sha256 = Get-Sha256Lower -Path $offlineAdjudicationPath
        }
        adoptedSchemas = [ordered]@{
            inputSchemaV2Sha256 = $expectedInputSchemaSha256
            planningSchemaBindingV2Sha256 = $expectedPlanningBindingSha256
        }
        scientificBoundary = $scientificBoundary
    }
    Write-JsonExclusive -Path $terminalReceiptPath -Value $terminalReceipt

    $statusV25 = [ordered]@{
        schema = 'gate14re-me-status-v25'
        studyId = $studyId
        status = 'INPUT_SCHEMA_V2_COMPATIBILITY_OFFLINE_CLOSURE_PASS_PLANNING_BINDING_V2_ADOPTED'
        version = 25
        updatedAtUtc = [DateTime]::UtcNow.ToString('o')
        previousVersionedStatus = [ordered]@{
            relativePath = 'Research/Gate14Re-ME/Gate14Re_ME_Status.v24.json'
            sha256 = $expectedStatusV24Sha256
            retained = $true
            reclassified = $false
        }
        schemaCompatibilityAttempt004 = [ordered]@{
            authorizationId = $sourceAuthorizationId
            retainedStatus = 'INPUT_SCHEMA_COMPATIBILITY_ATTEMPT_004_FAILED_CLOSED'
            passed = $false
            failureReceiptSha256 = $expectedFailureReceiptSha256
            modified = $false
            deleted = $false
            reclassified = $false
        }
        offlineClosureAdjudicationAttempt005 = [ordered]@{
            authorizationId = $authorizationId
            passed = $true
            terminalReceiptRelativePath = Get-ProjectRelativePath -Path $terminalReceiptPath -Root $resolvedProjectRoot
            terminalReceiptSha256 = Get-Sha256Lower -Path $terminalReceiptPath
            adjudicationRelativePath = Get-ProjectRelativePath -Path $offlineAdjudicationPath -Root $resolvedProjectRoot
            adjudicationSha256 = Get-Sha256Lower -Path $offlineAdjudicationPath
            unityInvocations = 0
        }
        adoptedQualificationSchemas = [ordered]@{
            inputSchemaV2 = [ordered]@{
                relativePath = 'Research/Gate14Re-ME/Execution/v2/load-qualification-input-schema.v2.json'
                sha256 = $expectedInputSchemaSha256
                adopted = $true
            }
            planningSchemaBindingV2 = [ordered]@{
                relativePath = 'Research/Gate14Re-ME/Execution/v2/load-qualification-planning-schema-binding.v2.json'
                sha256 = $expectedPlanningBindingSha256
                adopted = $true
            }
        }
        scientificBoundary = $scientificBoundary
        nextRequiredAction = 'Obtain a new, separate authorization for the Gate14Re-ME qualification planning freeze. No schedule, inputs, anonymous identity map, measured root, planner, algorithm lane, formal collection, analysis, ranking or winner adjudication is authorized by Status v25.'
    }
    Write-JsonExclusive -Path $statusV25Path -Value $statusV25

    $attempt005EvidenceFiles = @(Get-ChildItem -LiteralPath $stageRoot -Recurse -Force -File | Sort-Object FullName | ForEach-Object {
        [ordered]@{
            relativePath = Get-ProjectRelativePath -Path $_.FullName -Root $resolvedProjectRoot
            lengthBytes = [int64]$_.Length
            sha256 = Get-Sha256Lower -Path $_.FullName
        }
    })
    $finalManifest = [ordered]@{
        schema = 'gate14re-me-qualification-input-schema-compatibility-offline-closure-adjudication-attempt-005-evidence-freeze-manifest-v1'
        studyId = $studyId
        authorizationId = $authorizationId
        status = 'FROZEN_TERMINAL_PASS_EVIDENCE'
        frozenAtUtc = [DateTime]::UtcNow.ToString('o')
        sourceAttempt = [ordered]@{
            relativePath = Get-ProjectRelativePath -Path $attempt004Root -Root $resolvedProjectRoot
            retainedStatus = 'FAILED_CLOSED_INPUT_SCHEMA_COMPATIBILITY_ATTEMPT_004'
            fileCount = $expectedAttempt004FileCount
            contentDigestSha256 = $expectedAttempt004Digest
            reclassified = $false
        }
        statusV25 = [ordered]@{
            relativePath = Get-ProjectRelativePath -Path $statusV25Path -Root $resolvedProjectRoot
            sha256 = Get-Sha256Lower -Path $statusV25Path
        }
        evidenceFiles = $attempt005EvidenceFiles
    }
    Write-JsonExclusive -Path $finalManifestPath -Value $finalManifest

    foreach ($file in @(Get-ChildItem -LiteralPath $stageRoot -Recurse -Force -File)) {
        Set-ReadOnlyFile -Path $file.FullName
    }
    Set-ReadOnlyFile -Path $statusV25Path

    Require-Condition (@(Get-UnityProcesses).Count -eq 0) 'Unity appeared while finalizing offline evidence.'
    Require-Condition ((Get-InventoryContentDigest -Inventory (Get-FileInventory -Root $attempt004Root)) -eq $expectedAttempt004Digest) 'Attempt-004 changed during finalization.'
    Require-Condition ((Get-Sha256Lower -Path $statusV24Path) -eq $expectedStatusV24Sha256) 'Status v24 changed during finalization.'
    Require-Condition ((Read-JsonStrict -Path $statusV25Path).status -eq 'INPUT_SCHEMA_V2_COMPATIBILITY_OFFLINE_CLOSURE_PASS_PLANNING_BINDING_V2_ADOPTED') 'Status v25 final verification failed.'
    Require-Condition ((Read-JsonStrict -Path $terminalReceiptPath).status -eq 'PASS_INPUT_SCHEMA_V2_AND_PLANNING_SCHEMA_BINDING_V2_ADOPTED_BY_OFFLINE_CLOSURE') 'Terminal receipt final verification failed.'
    Require-Condition (@(Get-ChildItem -LiteralPath $stageRoot -Recurse -Force -File | Where-Object { -not $_.IsReadOnly }).Count -eq 0) 'Attempt-005 contains a non-read-only file after freeze.'
    Require-Condition ((Get-Item -LiteralPath $statusV25Path -Force).IsReadOnly) 'Status v25 is not read-only after freeze.'

    $stagePassed = $true
    [pscustomobject][ordered]@{
        status = 'PASS_INPUT_SCHEMA_V2_AND_PLANNING_SCHEMA_BINDING_V2_ADOPTED_BY_OFFLINE_CLOSURE'
        attempt004RetainedDigestSha256 = $expectedAttempt004Digest
        terminalReceiptSha256 = Get-Sha256Lower -Path $terminalReceiptPath
        statusV25Sha256 = Get-Sha256Lower -Path $statusV25Path
        finalManifestSha256 = Get-Sha256Lower -Path $finalManifestPath
        unityInvocations = 0
    } | ConvertTo-Json -Depth 20
}
catch {
    $exactFailure = $_.Exception.Message
    $exceptionType = $_.Exception.GetType().FullName
    $stackTrace = $_.ScriptStackTrace
    if ($null -eq $stageRoot -and $null -ne $resolvedProjectRoot) {
        $stageRoot = Join-Path $resolvedProjectRoot 'Research/Verification/Gate14Re-ME/qualification-input-schema-compatibility-offline-closure-adjudication-attempt-005'
    }
    if ($null -eq $statusV25Path -and $null -ne $resolvedProjectRoot) {
        $statusV25Path = Join-Path $resolvedProjectRoot 'Research/Gate14Re-ME/Gate14Re_ME_Status.v25.json'
    }
    if ($null -ne $stageRoot -and (Test-Path -LiteralPath $stageRoot -PathType Container)) {
        $failureReceiptPath = Join-Path $stageRoot 'failure-receipt.v1.json'
        if (-not (Test-Path -LiteralPath $failureReceiptPath)) {
            Write-JsonExclusive -Path $failureReceiptPath -Value ([ordered]@{
                schema = 'gate14re-me-qualification-input-schema-compatibility-offline-closure-adjudication-attempt-005-failure-receipt-v1'
                studyId = $studyId
                authorizationId = $authorizationId
                status = 'FAILED_CLOSED_OFFLINE_CLOSURE_ADJUDICATION_ATTEMPT_005'
                failedAtUtc = [DateTime]::UtcNow.ToString('o')
                exceptionType = $exceptionType
                exactFailure = $exactFailure
                stackTrace = $stackTrace
                retryPerformed = $false
                unityLaunched = $false
                sourceAttemptReclassified = $false
                candidateAdoption = [ordered]@{
                    inputSchemaV2Adopted = $false
                    planningSchemaBindingV2Adopted = $false
                }
                scientificBoundary = [ordered]@{
                    unityInvocations = 0
                    scheduleRowsGenerated = 0
                    qualificationInputsGenerated = 0
                    anonymousIdentityMappingsGenerated = 0
                    measuredRootCreated = $false
                    plannerInvocations = 0
                    algorithmLaneExecutions = 0
                    formalCollectionPerformed = $false
                    formalAnalysisPerformed = $false
                    algorithmRankingPerformed = $false
                    winnerAdjudicationPerformed = $false
                }
            })
        }
        if ($null -ne $statusV25Path -and -not (Test-Path -LiteralPath $statusV25Path)) {
            Write-JsonExclusive -Path $statusV25Path -Value ([ordered]@{
                schema = 'gate14re-me-status-v25'
                studyId = $studyId
                status = 'INPUT_SCHEMA_COMPATIBILITY_OFFLINE_CLOSURE_ATTEMPT_005_FAILED_CLOSED'
                version = 25
                updatedAtUtc = [DateTime]::UtcNow.ToString('o')
                previousVersionedStatus = [ordered]@{
                    relativePath = 'Research/Gate14Re-ME/Gate14Re_ME_Status.v24.json'
                    sha256 = $expectedStatusV24Sha256
                    retained = $true
                    reclassified = $false
                }
                offlineClosureAdjudicationAttempt005 = [ordered]@{
                    passed = $false
                    failureReceiptRelativePath = Get-ProjectRelativePath -Path $failureReceiptPath -Root $resolvedProjectRoot
                    failureReceiptSha256 = Get-Sha256Lower -Path $failureReceiptPath
                    unityInvocations = 0
                }
                adoptedQualificationSchemas = [ordered]@{
                    inputSchemaV2Adopted = $false
                    planningSchemaBindingV2Adopted = $false
                }
                nextRequiredAction = 'Fail closed. Do not retry, adopt schemas, generate qualification assets, create a measured root, run Unity, planner or algorithm lanes, or perform collection, analysis, ranking or winner adjudication without a new authorization.'
            })
        }
        $failureManifestPath = Join-Path $stageRoot 'source-and-evidence-freeze-manifest.v1.json'
        if (-not (Test-Path -LiteralPath $failureManifestPath)) {
            $failureEvidence = @(Get-ChildItem -LiteralPath $stageRoot -Recurse -Force -File | Sort-Object FullName | ForEach-Object {
                [ordered]@{
                    relativePath = Get-ProjectRelativePath -Path $_.FullName -Root $resolvedProjectRoot
                    lengthBytes = [int64]$_.Length
                    sha256 = Get-Sha256Lower -Path $_.FullName
                }
            })
            Write-JsonExclusive -Path $failureManifestPath -Value ([ordered]@{
                schema = 'gate14re-me-qualification-input-schema-compatibility-offline-closure-adjudication-attempt-005-evidence-freeze-manifest-v1'
                studyId = $studyId
                authorizationId = $authorizationId
                status = 'FROZEN_TERMINAL_FAILURE_EVIDENCE'
                frozenAtUtc = [DateTime]::UtcNow.ToString('o')
                evidenceFiles = $failureEvidence
            })
        }
        foreach ($file in @(Get-ChildItem -LiteralPath $stageRoot -Recurse -Force -File)) {
            Set-ReadOnlyFile -Path $file.FullName
        }
        if ($null -ne $statusV25Path -and (Test-Path -LiteralPath $statusV25Path -PathType Leaf)) {
            Set-ReadOnlyFile -Path $statusV25Path
        }
    }
    Write-Error "Gate14Re-ME offline closure adjudication attempt-005 failed closed: $exactFailure"
    exit 1
}

if (-not $stagePassed) {
    exit 1
}
