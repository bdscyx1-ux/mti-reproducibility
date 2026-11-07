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
$authorizationId = 'gate14re-me-unity-trusted-identity-timestamp-comparator-corrigendum-attempt-004'
$expectedStatusV19Sha256 = '94a4697c7bb501d21aefcc0f44abd34cac026cccbf5b074c0b831efb5c14213c'
$expectedTrustedRuleSha256 = 'f045ef93630202a72d603096687bac655b5b4ff01e8e0743e60d63881bbded06'
$expectedAttempt003FailureSha256 = 'aea859d3b2935ff71d66a4cd9bcdd005c3acddf093e409b712e129374a9b5a97'
$expectedAttempt003FinalManifestSha256 = '0d87c68508c5505a1b886d3206af56d92f4c0c792daabba0ffac7591b6ae2277'
$knownAnswerInvocationCount = 0
$stagePassed = $false
$exactFailure = $null
$exceptionType = $null
$stackTrace = $null
$attempt003InventoryBefore = @()
$attempt003InventoryAfter = @()
$attempt003DigestBefore = $null
$attempt003DigestAfter = $null

function Require-Condition {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw [System.InvalidOperationException]::new($Message) }
}

function Get-NormalizedFullPath {
    param([string]$Path, [string]$Base)
    $candidate = if ([System.IO.Path]::IsPathRooted($Path)) { $Path } else { Join-Path -Path $Base -ChildPath $Path }
    return [System.IO.Path]::GetFullPath($candidate).TrimEnd([System.IO.Path]::DirectorySeparatorChar)
}

function Get-ProjectRelativePath {
    param([string]$Path, [string]$Root)
    $rootUri = [Uri]::new($Root.TrimEnd([System.IO.Path]::DirectorySeparatorChar) + [System.IO.Path]::DirectorySeparatorChar)
    $pathUri = [Uri]::new([System.IO.Path]::GetFullPath($Path))
    return [Uri]::UnescapeDataString($rootUri.MakeRelativeUri($pathUri).ToString()).Replace('\', '/')
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
    finally { $sha.Dispose() }
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
        try { $writer.Write($json); $writer.Flush() }
        finally { $writer.Dispose() }
    }
    finally { $stream.Dispose() }
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

function Set-ReadOnlyFile {
    param([string]$Path)
    if (Test-Path -LiteralPath $Path -PathType Leaf) { (Get-Item -LiteralPath $Path -Force).IsReadOnly = $true }
}

function Test-OriginalTextPreserved {
    param([object]$Comparison, [AllowNull()][object]$Trusted, [AllowNull()][object]$Observed)
    $expectedTrusted = if ($null -eq $Trusted) { $null } else { [string]$Trusted }
    $expectedObserved = if ($null -eq $Observed) { $null } else { [string]$Observed }
    return [object]::Equals($Comparison.trustedOriginalText, $expectedTrusted) -and
        [object]::Equals($Comparison.observedOriginalText, $expectedObserved) -and
        [object]::Equals($Comparison.trusted.originalText, $expectedTrusted) -and
        [object]::Equals($Comparison.observed.originalText, $expectedObserved)
}

function New-ComparisonKnownAnswer {
    param(
        [string]$CaseId,
        [AllowNull()][object]$Trusted,
        [AllowNull()][object]$Observed,
        [bool]$ExpectedAccepted,
        [AllowNull()][string]$ExpectedFailureCode
    )
    $comparison = Compare-Gate14ReMETrustedTimestampV1 -TrustedText $Trusted -ObservedText $Observed
    $textPreserved = Test-OriginalTextPreserved -Comparison $comparison -Trusted $Trusted -Observed $Observed
    $passed = [bool]($comparison.comparisonAccepted -eq $ExpectedAccepted -and
        [object]::Equals($comparison.failureCode, $ExpectedFailureCode) -and $textPreserved -and
        ($ExpectedAccepted -or $comparison.failClosed))
    return [pscustomobject][ordered]@{
        caseId = $CaseId
        expectedAccepted = $ExpectedAccepted
        expectedFailureCode = $ExpectedFailureCode
        originalTextPreserved = $textPreserved
        passed = $passed
        comparison = $comparison
    }
}

$resolvedProjectRoot = Get-NormalizedFullPath -Path $ProjectRoot -Base (Get-Location).Path
$expectedProjectRoot = [System.IO.Path]::GetFullPath('H:\DDM_Final_Project').TrimEnd('\')
Require-Condition ($resolvedProjectRoot -ieq $expectedProjectRoot) 'Project root is not the authorized Gate14Re-ME project root.'

$stageRoot = Join-Path $resolvedProjectRoot 'Research/Verification/Gate14Re-ME/unity-trusted-identity-timestamp-comparator-corrigendum-attempt-004'
$attempt003Root = Join-Path $resolvedProjectRoot 'Research/Verification/Gate14Re-ME/qualification-input-schema-compatibility-corrigendum-attempt-003'
$parentStatusPath = Join-Path $resolvedProjectRoot 'Research/Gate14Re-ME/Gate14Re_ME_Status.v19.json'
$nextStatusPath = Join-Path $resolvedProjectRoot 'Research/Gate14Re-ME/Gate14Re_ME_Status.v20.json'
$trustedRulePath = Join-Path $resolvedProjectRoot 'Research/Verification/Gate14Re-ME/unity-executable-identity-rule-offline-adjudication-attempt-005/trusted-launch-identity-rule.v1.json'
$comparatorPath = Join-Path $stageRoot 'Gate14ReMETrustedTimestampComparatorV1.ps1'
$knownAnswerReceiptPath = Join-Path $stageRoot 'known-answer-receipt.v1.json'
$failureReceiptPath = Join-Path $stageRoot 'failure-receipt.v1.json'
$finalManifestPath = Join-Path $stageRoot 'source-and-evidence-freeze-manifest.v1.json'

Require-Condition (Test-Path -LiteralPath $stageRoot -PathType Container) 'Authorized attempt-004 evidence root is missing.'
Require-Condition (-not (Test-Path -LiteralPath $nextStatusPath)) 'Status v20 already exists; overwrite or retry is prohibited.'
foreach ($path in @($knownAnswerReceiptPath, $failureReceiptPath, $finalManifestPath,
    (Join-Path $stageRoot 'attempt003-inventory.before.v1.json'),
    (Join-Path $stageRoot 'attempt003-inventory.after.v1.json'))) {
    Require-Condition (-not (Test-Path -LiteralPath $path)) "Runtime evidence already exists; retry is prohibited: $path"
}

$resolvedSourceFreezeManifest = Get-NormalizedFullPath -Path $SourceFreezeManifest -Base $resolvedProjectRoot
Require-Condition ((Get-Sha256Lower -Path $resolvedSourceFreezeManifest) -eq $SourceFreezeManifestSha256) 'Source freeze manifest SHA-256 mismatch.'
$sourceFreeze = Get-Content -LiteralPath $resolvedSourceFreezeManifest -Raw -Encoding UTF8 | ConvertFrom-Json -Depth 100
Require-Condition ($sourceFreeze.schema -eq 'gate14re-me-trusted-timestamp-comparator-attempt-004-source-freeze-manifest-v1' -and
    $sourceFreeze.studyId -eq $studyId -and $sourceFreeze.authorizationId -eq $authorizationId -and
    $sourceFreeze.status -eq 'FROZEN_PREEXECUTION_SOURCES_AND_BINDINGS') 'Source freeze manifest header mismatch.'
foreach ($binding in @($sourceFreeze.bindings)) {
    $full = Get-NormalizedFullPath -Path ([string]$binding.relativePath) -Base $resolvedProjectRoot
    $projectPrefix = $resolvedProjectRoot + [System.IO.Path]::DirectorySeparatorChar
    Require-Condition $full.StartsWith($projectPrefix, [System.StringComparison]::OrdinalIgnoreCase) "Bound file escaped project root: $($binding.relativePath)"
    Require-Condition (Test-Path -LiteralPath $full -PathType Leaf) "Bound file is missing: $($binding.relativePath)"
    Require-Condition ((Get-Sha256Lower -Path $full) -eq [string]$binding.sha256) "Bound file SHA-256 mismatch: $($binding.relativePath)"
    Require-Condition ((Get-Item -LiteralPath $full).Length -eq [int64]$binding.lengthBytes) "Bound file length mismatch: $($binding.relativePath)"
}

Require-Condition ((Get-Sha256Lower -Path $parentStatusPath) -eq $expectedStatusV19Sha256) 'Status v19 SHA-256 mismatch.'
Require-Condition ((Get-Sha256Lower -Path $trustedRulePath) -eq $expectedTrustedRuleSha256) 'Trusted launch identity rule v1 SHA-256 mismatch.'
Require-Condition ((Get-Sha256Lower -Path (Join-Path $attempt003Root 'failure-receipt.v1.json')) -eq $expectedAttempt003FailureSha256) 'Attempt-003 failure receipt SHA-256 mismatch.'
Require-Condition ((Get-Sha256Lower -Path (Join-Path $attempt003Root 'source-and-evidence-freeze-manifest.v1.json')) -eq $expectedAttempt003FinalManifestSha256) 'Attempt-003 final evidence manifest SHA-256 mismatch.'
Require-Condition (@(Get-CimInstance Win32_Process | Where-Object { $_.Name -eq 'Unity.exe' }).Count -eq 0) 'A Unity process is active; offline-only boundary is not satisfied.'
Require-Condition (@(Get-ProhibitedRootsPresent -Root $resolvedProjectRoot).Count -eq 0) 'A prohibited Gate14Re-ME measured root exists.'

$attempt003InventoryBefore = @(Get-FileInventory -Root $attempt003Root)
$attempt003DigestBefore = Get-InventoryContentDigest -Inventory $attempt003InventoryBefore
Require-Condition ($attempt003InventoryBefore.Count -eq [int]$sourceFreeze.retainedAttempt003.fileCount) 'Attempt-003 retained evidence file count differs from the frozen baseline.'
Require-Condition ($attempt003DigestBefore -eq [string]$sourceFreeze.retainedAttempt003.contentDigestSha256) 'Attempt-003 retained evidence digest differs from the frozen baseline.'
Require-Condition (-not [bool]@($attempt003InventoryBefore | Where-Object { -not $_.readOnly }).Count) 'Attempt-003 contains a non-read-only evidence file.'

try {
    Write-JsonExclusive -Path (Join-Path $stageRoot 'attempt003-inventory.before.v1.json') -Value ([ordered]@{
        schema = 'gate14re-me-retained-attempt-inventory-v1'
        studyId = $studyId
        authorizationId = $authorizationId
        phase = 'BEFORE_OFFLINE_KNOWN_ANSWER'
        capturedAtUtc = [DateTime]::UtcNow.ToString('o')
        rootRelativePath = Get-ProjectRelativePath -Path $attempt003Root -Root $resolvedProjectRoot
        fileCount = $attempt003InventoryBefore.Count
        contentDigestSha256 = $attempt003DigestBefore
        files = $attempt003InventoryBefore
    })

    $scriptFiles = @($comparatorPath, $PSCommandPath)
    foreach ($scriptPath in $scriptFiles) {
        $tokens = $null
        $parseErrors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$parseErrors)
        Require-Condition ($parseErrors.Count -eq 0) "PowerShell parser errors exist in: $scriptPath"
        $prohibitedCommands = @($ast.FindAll({
            param($node)
            $node -is [System.Management.Automation.Language.CommandAst] -and
                $node.GetCommandName() -in @('Start-Process', 'Stop-Process', 'Invoke-Command')
        }, $true))
        Require-Condition ($prohibitedCommands.Count -eq 0) "A prohibited process-control command exists in offline source: $scriptPath"
    }

    . $comparatorPath
    $knownAnswerInvocationCount = 1
    $trustedRule = Get-Content -LiteralPath $trustedRulePath -Raw -Encoding UTF8 | ConvertFrom-Json -Depth 100
    Require-Condition ($trustedRule.schema -eq 'gate14re-me-unity-executable-identity-verification-rule-v1' -and
        $trustedRule.studyId -eq $studyId -and
        $trustedRule.status -eq 'FROZEN_TRUSTED_IDENTITY_RULE_FROM_OFFLINE_ADJUDICATION') 'Trusted launch identity rule header mismatch.'
    Require-Condition ([string]$trustedRule.applicability.creationTimeUtc -eq '2024-06-11T11:26:54Z') 'Frozen trusted creationTimeUtc differs from the authorized known-answer input.'
    Require-Condition ([string]$trustedRule.applicability.lastWriteTimeUtc -eq '2024-06-11T11:26:54Z') 'Frozen trusted lastWriteTimeUtc differs from the authorized known-answer input.'

    $cases = [System.Collections.Generic.List[object]]::new()
    $cases.Add((New-ComparisonKnownAnswer -CaseId 'frozen-rule-creation-zero-fraction-equivalence' -Trusted $trustedRule.applicability.creationTimeUtc -Observed '2024-06-11T11:26:54.0000000Z' -ExpectedAccepted $true -ExpectedFailureCode $null))
    $cases.Add((New-ComparisonKnownAnswer -CaseId 'frozen-rule-lastwrite-zero-fraction-equivalence' -Trusted $trustedRule.applicability.lastWriteTimeUtc -Observed '2024-06-11T11:26:54.0000000Z' -ExpectedAccepted $true -ExpectedFailureCode $null))
    $cases.Add((New-ComparisonKnownAnswer -CaseId 'explicit-offset-equivalence' -Trusted '2024-06-11T11:26:54Z' -Observed '2024-06-11T19:26:54+08:00' -ExpectedAccepted $true -ExpectedFailureCode $null))
    $cases.Add((New-ComparisonKnownAnswer -CaseId 'identical-seven-digit-fraction' -Trusted '2024-06-11T11:26:54.1234567Z' -Observed '2024-06-11T11:26:54.1234567Z' -ExpectedAccepted $true -ExpectedFailureCode $null))
    $cases.Add((New-ComparisonKnownAnswer -CaseId 'one-tick-difference' -Trusted '2024-06-11T11:26:54.0000000Z' -Observed '2024-06-11T11:26:54.0000001Z' -ExpectedAccepted $false -ExpectedFailureCode 'UTC_INSTANT_MISMATCH'))
    $cases.Add((New-ComparisonKnownAnswer -CaseId 'one-second-difference' -Trusted '2024-06-11T11:26:54Z' -Observed '2024-06-11T11:26:55Z' -ExpectedAccepted $false -ExpectedFailureCode 'UTC_INSTANT_MISMATCH'))
    $cases.Add((New-ComparisonKnownAnswer -CaseId 'same-wall-clock-different-offset' -Trusted '2024-06-11T11:26:54Z' -Observed '2024-06-11T11:26:54+08:00' -ExpectedAccepted $false -ExpectedFailureCode 'UTC_INSTANT_MISMATCH'))
    $cases.Add((New-ComparisonKnownAnswer -CaseId 'invalid-trusted-text' -Trusted 'invalid' -Observed '2024-06-11T11:26:54Z' -ExpectedAccepted $false -ExpectedFailureCode 'TRUSTED_NOT_STRICT_ISO8601_OFFSET_TIMESTAMP'))
    $cases.Add((New-ComparisonKnownAnswer -CaseId 'invalid-observed-text' -Trusted '2024-06-11T11:26:54Z' -Observed 'invalid' -ExpectedAccepted $false -ExpectedFailureCode 'OBSERVED_NOT_STRICT_ISO8601_OFFSET_TIMESTAMP'))
    $cases.Add((New-ComparisonKnownAnswer -CaseId 'missing-trusted-value' -Trusted $null -Observed '2024-06-11T11:26:54Z' -ExpectedAccepted $false -ExpectedFailureCode 'TRUSTED_MISSING_VALUE'))
    $cases.Add((New-ComparisonKnownAnswer -CaseId 'missing-observed-value' -Trusted '2024-06-11T11:26:54Z' -Observed $null -ExpectedAccepted $false -ExpectedFailureCode 'OBSERVED_MISSING_VALUE'))
    $cases.Add((New-ComparisonKnownAnswer -CaseId 'empty-trusted-value' -Trusted '' -Observed '2024-06-11T11:26:54Z' -ExpectedAccepted $false -ExpectedFailureCode 'TRUSTED_EMPTY_VALUE'))
    $cases.Add((New-ComparisonKnownAnswer -CaseId 'timezone-free-trusted-value' -Trusted '2024-06-11T11:26:54' -Observed '2024-06-11T11:26:54Z' -ExpectedAccepted $false -ExpectedFailureCode 'TRUSTED_NOT_STRICT_ISO8601_OFFSET_TIMESTAMP'))
    $cases.Add((New-ComparisonKnownAnswer -CaseId 'excessive-fraction-observed-value' -Trusted '2024-06-11T11:26:54Z' -Observed '2024-06-11T11:26:54.00000000Z' -ExpectedAccepted $false -ExpectedFailureCode 'OBSERVED_NOT_STRICT_ISO8601_OFFSET_TIMESTAMP'))
    $cases.Add((New-ComparisonKnownAnswer -CaseId 'invalid-offset-observed-value' -Trusted '2024-06-11T11:26:54Z' -Observed '2024-06-11T11:26:54+25:00' -ExpectedAccepted $false -ExpectedFailureCode 'OBSERVED_STRICT_PARSE_FAILED'))

    $duplicateFormat = "yyyy-MM-dd'T'HH:mm:ssK"
    $ambiguous = ConvertTo-Gate14ReMEStrictUtcInstantCoreV1 -Value '2024-06-11T11:26:54Z' -Formats ([string[]]@($duplicateFormat, $duplicateFormat))
    $cases.Add([pscustomobject][ordered]@{
        caseId = 'deliberately-non-unique-format-set'
        expectedAccepted = $false
        expectedFailureCode = 'NON_UNIQUE_PARSE'
        originalTextPreserved = ([string]$ambiguous.originalText -eq '2024-06-11T11:26:54Z')
        passed = (-not $ambiguous.parsed -and -not $ambiguous.uniqueParse -and
            [int]$ambiguous.successfulFormatCount -eq 2 -and $ambiguous.failureCode -eq 'NON_UNIQUE_PARSE' -and
            [string]$ambiguous.originalText -eq '2024-06-11T11:26:54Z')
        parse = $ambiguous
    })

    $failedCases = @($cases | Where-Object { -not $_.passed })
    Require-Condition ($cases.Count -eq 16) 'Known-answer cardinality mismatch.'
    Require-Condition ($failedCases.Count -eq 0) "One or more offline timestamp known-answer cases failed: $($failedCases.caseId -join ', ')"

    $attempt003InventoryAfter = @(Get-FileInventory -Root $attempt003Root)
    $attempt003DigestAfter = Get-InventoryContentDigest -Inventory $attempt003InventoryAfter
    $attempt003Unchanged = $attempt003DigestAfter -eq $attempt003DigestBefore
    Write-JsonExclusive -Path (Join-Path $stageRoot 'attempt003-inventory.after.v1.json') -Value ([ordered]@{
        schema = 'gate14re-me-retained-attempt-inventory-v1'
        studyId = $studyId
        authorizationId = $authorizationId
        phase = 'AFTER_OFFLINE_KNOWN_ANSWER'
        capturedAtUtc = [DateTime]::UtcNow.ToString('o')
        rootRelativePath = Get-ProjectRelativePath -Path $attempt003Root -Root $resolvedProjectRoot
        fileCount = $attempt003InventoryAfter.Count
        contentDigestSha256 = $attempt003DigestAfter
        exactlyMatchesBeforeInventory = $attempt003Unchanged
        files = $attempt003InventoryAfter
    })
    Require-Condition $attempt003Unchanged 'Attempt-003 evidence changed during attempt-004.'
    Require-Condition ((Get-Sha256Lower -Path $parentStatusPath) -eq $expectedStatusV19Sha256) 'Status v19 changed during attempt-004.'
    Require-Condition ((Get-Sha256Lower -Path $trustedRulePath) -eq $expectedTrustedRuleSha256) 'Trusted launch identity rule changed during attempt-004.'
    Require-Condition (@(Get-CimInstance Win32_Process | Where-Object { $_.Name -eq 'Unity.exe' }).Count -eq 0) 'A Unity process appeared during the offline-only known-answer.'
    Require-Condition (@(Get-ProhibitedRootsPresent -Root $resolvedProjectRoot).Count -eq 0) 'A prohibited Gate14Re-ME measured root appeared.'

    $knownAnswerReceipt = [ordered]@{
        schema = 'gate14re-me-unity-trusted-timestamp-comparator-known-answer-receipt-v1'
        studyId = $studyId
        authorizationId = $authorizationId
        status = 'PASS_TRUSTED_TIMESTAMP_COMPARATOR_OFFLINE_KNOWN_ANSWER'
        completedAtUtc = [DateTime]::UtcNow.ToString('o')
        passed = $true
        terminal = $true
        offlineKnownAnswerInvocationCount = $knownAnswerInvocationCount
        retryPerformed = $false
        unityInvocationCount = 0
        comparator = [ordered]@{
            relativePath = Get-ProjectRelativePath -Path $comparatorPath -Root $resolvedProjectRoot
            sha256 = Get-Sha256Lower -Path $comparatorPath
            acceptedInputContract = 'STRICT_ISO8601_WITH_EXPLICIT_OFFSET_AND_OPTIONAL_1_TO_7_FRACTIONAL_DIGITS'
            comparisonBasis = 'UTC_TICKS'
            originalTextPreserved = $true
            zeroParseDisposition = 'FAIL_CLOSED'
            nonUniqueParseDisposition = 'FAIL_CLOSED'
            differentInstantDisposition = 'FAIL_CLOSED'
        }
        trustedRule = [ordered]@{
            relativePath = Get-ProjectRelativePath -Path $trustedRulePath -Root $resolvedProjectRoot
            sha256BeforeAndAfter = $expectedTrustedRuleSha256
            modified = $false
        }
        casesPassed = $cases.Count
        casesFailed = 0
        cases = @($cases)
        retainedAttempt003 = [ordered]@{
            beforeFileCount = $attempt003InventoryBefore.Count
            afterFileCount = $attempt003InventoryAfter.Count
            beforeContentDigestSha256 = $attempt003DigestBefore
            afterContentDigestSha256 = $attempt003DigestAfter
            unchanged = $true
            originalFailureStatusRetained = $true
            reclassified = $false
        }
        preservedNonTimestampRequirements = [ordered]@{
            sha256 = $true
            chunkDigests = $true
            executablePath = $true
            ntfsFileIdentity = $true
            peIdentity = $true
            authenticode = $true
            fileLength = $true
            processCompositeIdentity = $true
        }
        scientificBoundary = [ordered]@{
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
    }
    Write-JsonExclusive -Path $knownAnswerReceiptPath -Value $knownAnswerReceipt

    $statusV20 = [ordered]@{
        schema = 'gate14re-me-status-v20'
        studyId = $studyId
        status = 'TRUSTED_TIMESTAMP_COMPARATOR_CORRIGENDUM_OFFLINE_QUALIFIED_PASS'
        version = 20
        updatedAtUtc = [DateTime]::UtcNow.ToString('o')
        previousVersionedStatus = [ordered]@{
            relativePath = 'Research/Gate14Re-ME/Gate14Re_ME_Status.v19.json'
            sha256 = $expectedStatusV19Sha256
            retained = $true
        }
        schemaCompatibilityCorrigendumAttempt003 = [ordered]@{
            status = 'FAILED_CLOSED_RETAINED_UNCHANGED'
            evidenceFileCount = $attempt003InventoryAfter.Count
            evidenceContentDigestSha256 = $attempt003DigestAfter
            inputSchemaV2Adopted = $false
            planningSchemaBindingV2Adopted = $false
            reclassified = $false
        }
        trustedTimestampComparatorCorrigendumAttempt004 = [ordered]@{
            authorizationId = $authorizationId
            status = $knownAnswerReceipt.status
            offlineKnownAnswerInvocationCount = 1
            unityInvocationCount = 0
            retryPerformed = $false
            comparatorRelativePath = Get-ProjectRelativePath -Path $comparatorPath -Root $resolvedProjectRoot
            comparatorSha256 = Get-Sha256Lower -Path $comparatorPath
            knownAnswerReceiptRelativePath = Get-ProjectRelativePath -Path $knownAnswerReceiptPath -Root $resolvedProjectRoot
            knownAnswerReceiptSha256 = Get-Sha256Lower -Path $knownAnswerReceiptPath
            trustedLaunchIdentityRuleModified = $false
        }
        adoptionState = [ordered]@{
            inputSchemaV2Adopted = $false
            planningSchemaBindingV2Adopted = $false
            timestampComparatorQualifiedOffline = $true
            schemaCompatibilityUnitySelfCheckPassed = $false
        }
        authorizationState = [ordered]@{
            attempt004AuthorizationConsumed = $true
            unityLaunchAuthorized = $false
            schemaCompatibilityUnitySelfCheckAuthorized = $false
            qualificationPlanningAuthorized = $false
            scheduleGenerationAuthorized = $false
            inputGenerationAuthorized = $false
            anonymousIdentityMapGenerationAuthorized = $false
            measuredRootCreationAuthorized = $false
            plannerAuthorized = $false
            algorithmLaneExecutionAuthorized = $false
            formalCollectionAuthorized = $false
            formalAnalysisAuthorized = $false
            rankingAuthorized = $false
            winnerAdjudicationAuthorized = $false
        }
        nextRequiredAction = 'Separately authorize a new isolated algorithm-free Unity schema-compatibility attempt that imports the qualified timestamp comparator without weakening any other trusted identity requirement.'
    }
    Write-JsonExclusive -Path $nextStatusPath -Value $statusV20

    $evidenceFiles = @(Get-ChildItem -LiteralPath $stageRoot -Recurse -Force -File | Where-Object { $_.FullName -ne $finalManifestPath } | Sort-Object FullName | ForEach-Object {
        [ordered]@{
            relativePath = Get-ProjectRelativePath -Path $_.FullName -Root $resolvedProjectRoot
            lengthBytes = [int64]$_.Length
            sha256 = Get-Sha256Lower -Path $_.FullName
        }
    })
    Write-JsonExclusive -Path $finalManifestPath -Value ([ordered]@{
        schema = 'gate14re-me-trusted-timestamp-comparator-attempt-004-evidence-freeze-manifest-v1'
        studyId = $studyId
        authorizationId = $authorizationId
        status = 'FROZEN_TERMINAL_PASS_EVIDENCE'
        frozenAtUtc = [DateTime]::UtcNow.ToString('o')
        sourceFreezeManifest = [ordered]@{
            relativePath = Get-ProjectRelativePath -Path $resolvedSourceFreezeManifest -Root $resolvedProjectRoot
            sha256 = $SourceFreezeManifestSha256
        }
        statusV20 = [ordered]@{
            relativePath = Get-ProjectRelativePath -Path $nextStatusPath -Root $resolvedProjectRoot
            sha256 = Get-Sha256Lower -Path $nextStatusPath
        }
        evidenceFiles = $evidenceFiles
    })
    foreach ($file in @(Get-ChildItem -LiteralPath $stageRoot -Recurse -Force -File)) { Set-ReadOnlyFile -Path $file.FullName }
    Set-ReadOnlyFile -Path $nextStatusPath
    $stagePassed = $true
    Write-Output ($knownAnswerReceipt | ConvertTo-Json -Depth 100 -Compress)
}
catch {
    $stagePassed = $false
    $exactFailure = $_.Exception.Message
    $exceptionType = $_.Exception.GetType().FullName
    $stackTrace = $_.ScriptStackTrace

    try {
        $attempt003InventoryAfter = @(Get-FileInventory -Root $attempt003Root)
        $attempt003DigestAfter = Get-InventoryContentDigest -Inventory $attempt003InventoryAfter
    }
    catch { }
    $attempt003UnchangedAfterFailure = $null -ne $attempt003DigestBefore -and $attempt003DigestAfter -eq $attempt003DigestBefore

    if (-not (Test-Path -LiteralPath $failureReceiptPath)) {
        Write-JsonExclusive -Path $failureReceiptPath -Value ([ordered]@{
            schema = 'gate14re-me-trusted-timestamp-comparator-attempt-004-failure-receipt-v1'
            studyId = $studyId
            authorizationId = $authorizationId
            status = 'FAILED_CLOSED_TRUSTED_TIMESTAMP_COMPARATOR_ATTEMPT_004'
            failedAtUtc = [DateTime]::UtcNow.ToString('o')
            exceptionType = $exceptionType
            exactFailure = $exactFailure
            stackTrace = $stackTrace
            offlineKnownAnswerInvocationCount = $knownAnswerInvocationCount
            retryPerformed = $false
            unityInvocationCount = 0
            attempt003Evidence = [ordered]@{
                beforeContentDigestSha256 = $attempt003DigestBefore
                afterContentDigestSha256 = $attempt003DigestAfter
                unchanged = $attempt003UnchangedAfterFailure
                reclassified = $false
            }
            scientificBoundary = [ordered]@{
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
        })
    }

    if (-not (Test-Path -LiteralPath $nextStatusPath)) {
        Write-JsonExclusive -Path $nextStatusPath -Value ([ordered]@{
            schema = 'gate14re-me-status-v20'
            studyId = $studyId
            status = 'TRUSTED_TIMESTAMP_COMPARATOR_CORRIGENDUM_ATTEMPT_004_FAILED_CLOSED'
            version = 20
            updatedAtUtc = [DateTime]::UtcNow.ToString('o')
            previousVersionedStatus = [ordered]@{
                relativePath = 'Research/Gate14Re-ME/Gate14Re_ME_Status.v19.json'
                sha256 = $(if (Test-Path -LiteralPath $parentStatusPath) { Get-Sha256Lower -Path $parentStatusPath } else { $null })
                retained = $true
            }
            timestampComparatorAttempt004 = [ordered]@{
                authorizationId = $authorizationId
                passed = $false
                failureReceiptRelativePath = Get-ProjectRelativePath -Path $failureReceiptPath -Root $resolvedProjectRoot
                failureReceiptSha256 = Get-Sha256Lower -Path $failureReceiptPath
                retryPerformed = $false
                unityInvocationCount = 0
            }
            nextRequiredAction = 'A new separate authorization is required. Do not retry or start Unity.'
        })
    }

    if (-not (Test-Path -LiteralPath $finalManifestPath)) {
        $failureEvidenceFiles = @(Get-ChildItem -LiteralPath $stageRoot -Recurse -Force -File | Where-Object { $_.FullName -ne $finalManifestPath } | Sort-Object FullName | ForEach-Object {
            [ordered]@{
                relativePath = Get-ProjectRelativePath -Path $_.FullName -Root $resolvedProjectRoot
                lengthBytes = [int64]$_.Length
                sha256 = Get-Sha256Lower -Path $_.FullName
            }
        })
        Write-JsonExclusive -Path $finalManifestPath -Value ([ordered]@{
            schema = 'gate14re-me-trusted-timestamp-comparator-attempt-004-evidence-freeze-manifest-v1'
            studyId = $studyId
            authorizationId = $authorizationId
            status = 'FROZEN_TERMINAL_FAILURE_EVIDENCE'
            frozenAtUtc = [DateTime]::UtcNow.ToString('o')
            statusV20 = [ordered]@{
                relativePath = Get-ProjectRelativePath -Path $nextStatusPath -Root $resolvedProjectRoot
                sha256 = Get-Sha256Lower -Path $nextStatusPath
            }
            evidenceFiles = $failureEvidenceFiles
        })
    }

    foreach ($file in @(Get-ChildItem -LiteralPath $stageRoot -Recurse -Force -File)) { Set-ReadOnlyFile -Path $file.FullName }
    Set-ReadOnlyFile -Path $nextStatusPath
    Write-Error "Gate14Re-ME timestamp comparator attempt-004 failed closed: $exactFailure"
    exit 1
}

if (-not $stagePassed) { exit 1 }
