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
$authorizationId = 'gate14re-me-unity-trusted-identity-timestamp-comparator-corrigendum-auto-attempts-until-pass'
$attemptId = 'gate14re-me-unity-trusted-identity-timestamp-comparator-corrigendum-attempt-005'
$expectedStatusV19Sha256 = '94a4697c7bb501d21aefcc0f44abd34cac026cccbf5b074c0b831efb5c14213c'
$expectedStatusV20Sha256 = '153658e56dca6af6ff0d7a43fb5c5a5c9ffe74bc3fb50e499e2c9c9abde49b10'
$expectedTrustedRuleSha256 = 'f045ef93630202a72d603096687bac655b5b4ff01e8e0743e60d63881bbded06'
$expectedAttempt003DigestSha256 = '770a7f1bf25f763d42186bba77a148280dde6193e05f9887ed0d9a5ffe02deef'
$expectedAttempt004DigestSha256 = '83b30dc296f8acc92e95bcd55a64b0635cd65b1192bfe511795ca3bf125c69f6'
$expectedAttempt004FailureSha256 = '9679462397caa5d8aeed29dcac6cdda6b3f39cbb1e28308bc6e87c43f9490542'
$expectedAttempt004FinalManifestSha256 = '93b88567d1006b237ebc54373ee21bbef7be4cf9f997d58aa56b08c9d81f8b36'
$knownAnswerInvocationCount = 0
$stagePassed = $false
$exactFailure = $null
$exceptionType = $null
$stackTrace = $null
$attempt003InventoryBefore = @()
$attempt003InventoryAfter = @()
$attempt004InventoryBefore = @()
$attempt004InventoryAfter = @()
$attempt003DigestBefore = $null
$attempt003DigestAfter = $null
$attempt004DigestBefore = $null
$attempt004DigestAfter = $null

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

function Get-ExactJsonStringPropertyV1 {
    param(
        [System.Text.Json.JsonElement]$Object,
        [string]$PropertyName
    )
    $element = $Object.GetProperty($PropertyName)
    Require-Condition ($element.ValueKind -eq [System.Text.Json.JsonValueKind]::String) "JSON property is not a string: $PropertyName"
    return [pscustomobject][ordered]@{
        propertyName = $PropertyName
        value = $element.GetString()
        rawJsonToken = $element.GetRawText()
        valueKind = $element.ValueKind.ToString()
    }
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

$stageRoot = Join-Path $resolvedProjectRoot 'Research/Verification/Gate14Re-ME/unity-trusted-identity-timestamp-comparator-corrigendum-attempt-005'
$attempt003Root = Join-Path $resolvedProjectRoot 'Research/Verification/Gate14Re-ME/qualification-input-schema-compatibility-corrigendum-attempt-003'
$attempt004Root = Join-Path $resolvedProjectRoot 'Research/Verification/Gate14Re-ME/unity-trusted-identity-timestamp-comparator-corrigendum-attempt-004'
$statusV19Path = Join-Path $resolvedProjectRoot 'Research/Gate14Re-ME/Gate14Re_ME_Status.v19.json'
$parentStatusPath = Join-Path $resolvedProjectRoot 'Research/Gate14Re-ME/Gate14Re_ME_Status.v20.json'
$nextStatusPath = Join-Path $resolvedProjectRoot 'Research/Gate14Re-ME/Gate14Re_ME_Status.v21.json'
$trustedRulePath = Join-Path $resolvedProjectRoot 'Research/Verification/Gate14Re-ME/unity-executable-identity-rule-offline-adjudication-attempt-005/trusted-launch-identity-rule.v1.json'
$comparatorPath = Join-Path $stageRoot 'Gate14ReMETrustedTimestampComparatorV1.ps1'
$knownAnswerReceiptPath = Join-Path $stageRoot 'known-answer-receipt.v1.json'
$failureReceiptPath = Join-Path $stageRoot 'failure-receipt.v1.json'
$finalManifestPath = Join-Path $stageRoot 'source-and-evidence-freeze-manifest.v1.json'

Require-Condition (Test-Path -LiteralPath $stageRoot -PathType Container) 'Authorized attempt-005 evidence root is missing.'
Require-Condition (-not (Test-Path -LiteralPath $nextStatusPath)) 'Status v21 already exists; overwrite or same-attempt retry is prohibited.'
foreach ($path in @(
    $knownAnswerReceiptPath,
    $failureReceiptPath,
    $finalManifestPath,
    (Join-Path $stageRoot 'attempt003-inventory.before.v1.json'),
    (Join-Path $stageRoot 'attempt003-inventory.after.v1.json'),
    (Join-Path $stageRoot 'attempt004-inventory.before.v1.json'),
    (Join-Path $stageRoot 'attempt004-inventory.after.v1.json')
)) {
    Require-Condition (-not (Test-Path -LiteralPath $path)) "Runtime evidence already exists; same-attempt retry is prohibited: $path"
}

$resolvedSourceFreezeManifest = Get-NormalizedFullPath -Path $SourceFreezeManifest -Base $resolvedProjectRoot
Require-Condition ((Get-Sha256Lower -Path $resolvedSourceFreezeManifest) -eq $SourceFreezeManifestSha256) 'Source freeze manifest SHA-256 mismatch.'
$sourceFreeze = Get-Content -LiteralPath $resolvedSourceFreezeManifest -Raw -Encoding UTF8 | ConvertFrom-Json -Depth 100
Require-Condition ($sourceFreeze.schema -eq 'gate14re-me-trusted-timestamp-comparator-attempt-005-source-freeze-manifest-v1' -and
    $sourceFreeze.studyId -eq $studyId -and $sourceFreeze.authorizationId -eq $authorizationId -and
    $sourceFreeze.attemptId -eq $attemptId -and
    $sourceFreeze.status -eq 'FROZEN_PREEXECUTION_SOURCES_AND_BINDINGS') 'Source freeze manifest header mismatch.'
foreach ($binding in @($sourceFreeze.bindings)) {
    $full = Get-NormalizedFullPath -Path ([string]$binding.relativePath) -Base $resolvedProjectRoot
    $projectPrefix = $resolvedProjectRoot + [System.IO.Path]::DirectorySeparatorChar
    Require-Condition $full.StartsWith($projectPrefix, [System.StringComparison]::OrdinalIgnoreCase) "Bound file escaped project root: $($binding.relativePath)"
    Require-Condition (Test-Path -LiteralPath $full -PathType Leaf) "Bound file is missing: $($binding.relativePath)"
    Require-Condition ((Get-Sha256Lower -Path $full) -eq [string]$binding.sha256) "Bound file SHA-256 mismatch: $($binding.relativePath)"
    Require-Condition ((Get-Item -LiteralPath $full).Length -eq [int64]$binding.lengthBytes) "Bound file length mismatch: $($binding.relativePath)"
}

Require-Condition ((Get-Sha256Lower -Path $statusV19Path) -eq $expectedStatusV19Sha256) 'Status v19 SHA-256 mismatch.'
Require-Condition ((Get-Sha256Lower -Path $parentStatusPath) -eq $expectedStatusV20Sha256) 'Status v20 SHA-256 mismatch.'
Require-Condition ((Get-Sha256Lower -Path $trustedRulePath) -eq $expectedTrustedRuleSha256) 'Trusted launch identity rule v1 SHA-256 mismatch.'
Require-Condition ((Get-Sha256Lower -Path (Join-Path $attempt004Root 'failure-receipt.v1.json')) -eq $expectedAttempt004FailureSha256) 'Attempt-004 failure receipt SHA-256 mismatch.'
Require-Condition ((Get-Sha256Lower -Path (Join-Path $attempt004Root 'source-and-evidence-freeze-manifest.v1.json')) -eq $expectedAttempt004FinalManifestSha256) 'Attempt-004 final evidence manifest SHA-256 mismatch.'
Require-Condition (@(Get-CimInstance Win32_Process | Where-Object { $_.Name -eq 'Unity.exe' }).Count -eq 0) 'A Unity process is active; offline-only boundary is not satisfied.'
Require-Condition (@(Get-ProhibitedRootsPresent -Root $resolvedProjectRoot).Count -eq 0) 'A prohibited Gate14Re-ME measured root exists.'

$attempt003InventoryBefore = @(Get-FileInventory -Root $attempt003Root)
$attempt003DigestBefore = Get-InventoryContentDigest -Inventory $attempt003InventoryBefore
Require-Condition ($attempt003InventoryBefore.Count -eq 15) 'Attempt-003 retained evidence file count differs from the frozen baseline.'
Require-Condition ($attempt003DigestBefore -eq $expectedAttempt003DigestSha256) 'Attempt-003 retained evidence digest differs from the frozen baseline.'
Require-Condition (-not [bool]@($attempt003InventoryBefore | Where-Object { -not $_.readOnly }).Count) 'Attempt-003 contains a non-read-only evidence file.'

$attempt004InventoryBefore = @(Get-FileInventory -Root $attempt004Root)
$attempt004DigestBefore = Get-InventoryContentDigest -Inventory $attempt004InventoryBefore
Require-Condition ($attempt004InventoryBefore.Count -eq 8) 'Attempt-004 retained evidence file count differs from the frozen baseline.'
Require-Condition ($attempt004DigestBefore -eq $expectedAttempt004DigestSha256) 'Attempt-004 retained evidence digest differs from the frozen baseline.'
Require-Condition (-not [bool]@($attempt004InventoryBefore | Where-Object { -not $_.readOnly }).Count) 'Attempt-004 contains a non-read-only evidence file.'

try {
    Write-JsonExclusive -Path (Join-Path $stageRoot 'attempt003-inventory.before.v1.json') -Value ([ordered]@{
        schema = 'gate14re-me-retained-attempt-inventory-v1'
        studyId = $studyId
        authorizationId = $authorizationId
        attemptId = $attemptId
        retainedAttempt = 'qualification-input-schema-compatibility-corrigendum-attempt-003'
        phase = 'BEFORE_OFFLINE_KNOWN_ANSWER'
        capturedAtUtc = [DateTime]::UtcNow.ToString('o')
        fileCount = $attempt003InventoryBefore.Count
        contentDigestSha256 = $attempt003DigestBefore
        files = $attempt003InventoryBefore
    })
    Write-JsonExclusive -Path (Join-Path $stageRoot 'attempt004-inventory.before.v1.json') -Value ([ordered]@{
        schema = 'gate14re-me-retained-attempt-inventory-v1'
        studyId = $studyId
        authorizationId = $authorizationId
        attemptId = $attemptId
        retainedAttempt = 'unity-trusted-identity-timestamp-comparator-corrigendum-attempt-004'
        phase = 'BEFORE_OFFLINE_KNOWN_ANSWER'
        capturedAtUtc = [DateTime]::UtcNow.ToString('o')
        fileCount = $attempt004InventoryBefore.Count
        contentDigestSha256 = $attempt004DigestBefore
        files = $attempt004InventoryBefore
    })

    foreach ($scriptPath in @($comparatorPath, $PSCommandPath)) {
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

    $utf8Strict = [System.Text.UTF8Encoding]::new($false, $true)
    $trustedRuleRaw = [System.IO.File]::ReadAllText($trustedRulePath, $utf8Strict)
    $trustedRuleDocument = [System.Text.Json.JsonDocument]::Parse($trustedRuleRaw)
    try {
        $rootElement = $trustedRuleDocument.RootElement
        $schemaField = Get-ExactJsonStringPropertyV1 -Object $rootElement -PropertyName 'schema'
        $studyField = Get-ExactJsonStringPropertyV1 -Object $rootElement -PropertyName 'studyId'
        $statusField = Get-ExactJsonStringPropertyV1 -Object $rootElement -PropertyName 'status'
        Require-Condition ($schemaField.value -eq 'gate14re-me-unity-executable-identity-verification-rule-v1' -and
            $studyField.value -eq $studyId -and
            $statusField.value -eq 'FROZEN_TRUSTED_IDENTITY_RULE_FROM_OFFLINE_ADJUDICATION') 'Trusted launch identity rule header mismatch.'
        $applicabilityElement = $rootElement.GetProperty('applicability')
        Require-Condition ($applicabilityElement.ValueKind -eq [System.Text.Json.JsonValueKind]::Object) 'Trusted launch identity applicability is not an object.'
        $creationField = Get-ExactJsonStringPropertyV1 -Object $applicabilityElement -PropertyName 'creationTimeUtc'
        $lastWriteField = Get-ExactJsonStringPropertyV1 -Object $applicabilityElement -PropertyName 'lastWriteTimeUtc'
    }
    finally { $trustedRuleDocument.Dispose() }

    $cases = [System.Collections.Generic.List[object]]::new()
    $cases.Add((New-ComparisonKnownAnswer -CaseId 'frozen-rule-creation-zero-fraction-equivalence' -Trusted $creationField.value -Observed '2024-06-11T11:26:54Z' -ExpectedAccepted $true -ExpectedFailureCode $null))
    $cases.Add((New-ComparisonKnownAnswer -CaseId 'frozen-rule-lastwrite-zero-fraction-equivalence' -Trusted $lastWriteField.value -Observed '2024-06-11T11:26:54Z' -ExpectedAccepted $true -ExpectedFailureCode $null))
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
    $attempt004InventoryAfter = @(Get-FileInventory -Root $attempt004Root)
    $attempt004DigestAfter = Get-InventoryContentDigest -Inventory $attempt004InventoryAfter
    Write-JsonExclusive -Path (Join-Path $stageRoot 'attempt003-inventory.after.v1.json') -Value ([ordered]@{
        schema = 'gate14re-me-retained-attempt-inventory-v1'
        studyId = $studyId
        authorizationId = $authorizationId
        attemptId = $attemptId
        retainedAttempt = 'qualification-input-schema-compatibility-corrigendum-attempt-003'
        phase = 'AFTER_OFFLINE_KNOWN_ANSWER'
        capturedAtUtc = [DateTime]::UtcNow.ToString('o')
        fileCount = $attempt003InventoryAfter.Count
        contentDigestSha256 = $attempt003DigestAfter
        exactlyMatchesBeforeInventory = ($attempt003DigestAfter -eq $attempt003DigestBefore)
        files = $attempt003InventoryAfter
    })
    Write-JsonExclusive -Path (Join-Path $stageRoot 'attempt004-inventory.after.v1.json') -Value ([ordered]@{
        schema = 'gate14re-me-retained-attempt-inventory-v1'
        studyId = $studyId
        authorizationId = $authorizationId
        attemptId = $attemptId
        retainedAttempt = 'unity-trusted-identity-timestamp-comparator-corrigendum-attempt-004'
        phase = 'AFTER_OFFLINE_KNOWN_ANSWER'
        capturedAtUtc = [DateTime]::UtcNow.ToString('o')
        fileCount = $attempt004InventoryAfter.Count
        contentDigestSha256 = $attempt004DigestAfter
        exactlyMatchesBeforeInventory = ($attempt004DigestAfter -eq $attempt004DigestBefore)
        files = $attempt004InventoryAfter
    })
    Require-Condition ($attempt003DigestAfter -eq $attempt003DigestBefore) 'Attempt-003 evidence changed during attempt-005.'
    Require-Condition ($attempt004DigestAfter -eq $attempt004DigestBefore) 'Attempt-004 evidence changed during attempt-005.'
    Require-Condition ((Get-Sha256Lower -Path $statusV19Path) -eq $expectedStatusV19Sha256) 'Status v19 changed during attempt-005.'
    Require-Condition ((Get-Sha256Lower -Path $parentStatusPath) -eq $expectedStatusV20Sha256) 'Status v20 changed during attempt-005.'
    Require-Condition ((Get-Sha256Lower -Path $trustedRulePath) -eq $expectedTrustedRuleSha256) 'Trusted launch identity rule changed during attempt-005.'
    Require-Condition (@(Get-CimInstance Win32_Process | Where-Object { $_.Name -eq 'Unity.exe' }).Count -eq 0) 'A Unity process appeared during the offline-only known-answer.'
    Require-Condition (@(Get-ProhibitedRootsPresent -Root $resolvedProjectRoot).Count -eq 0) 'A prohibited Gate14Re-ME measured root appeared.'

    $knownAnswerReceipt = [ordered]@{
        schema = 'gate14re-me-unity-trusted-timestamp-comparator-attempt-005-known-answer-receipt-v1'
        studyId = $studyId
        authorizationId = $authorizationId
        attemptId = $attemptId
        status = 'PASS_TRUSTED_TIMESTAMP_COMPARATOR_OFFLINE_KNOWN_ANSWER'
        completedAtUtc = [DateTime]::UtcNow.ToString('o')
        passed = $true
        terminal = $true
        offlineKnownAnswerInvocationCount = $knownAnswerInvocationCount
        sameAttemptRetryPerformed = $false
        priorFailedAttemptsRetained = @('attempt-004')
        unityInvocationCount = 0
        jsonTimestampIngestion = [ordered]@{
            parser = 'System.Text.Json.JsonDocument'
            dateCoercionPerformed = $false
            creationTimeUtc = $creationField
            lastWriteTimeUtc = $lastWriteField
        }
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
        retainedEvidence = [ordered]@{
            attempt003BeforeDigestSha256 = $attempt003DigestBefore
            attempt003AfterDigestSha256 = $attempt003DigestAfter
            attempt003Unchanged = $true
            attempt004BeforeDigestSha256 = $attempt004DigestBefore
            attempt004AfterDigestSha256 = $attempt004DigestAfter
            attempt004Unchanged = $true
            attempt004FailureStatusRetained = $true
            priorEvidenceReclassified = $false
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

    $statusV21 = [ordered]@{
        schema = 'gate14re-me-status-v21'
        studyId = $studyId
        status = 'TRUSTED_TIMESTAMP_COMPARATOR_CORRIGENDUM_OFFLINE_QUALIFIED_PASS'
        version = 21
        updatedAtUtc = [DateTime]::UtcNow.ToString('o')
        previousVersionedStatus = [ordered]@{
            relativePath = 'Research/Gate14Re-ME/Gate14Re_ME_Status.v20.json'
            sha256 = $expectedStatusV20Sha256
            retained = $true
        }
        trustedTimestampComparatorCorrigendumAttempt004 = [ordered]@{
            status = 'FAILED_CLOSED_RETAINED_UNCHANGED'
            evidenceFileCount = $attempt004InventoryAfter.Count
            evidenceContentDigestSha256 = $attempt004DigestAfter
            reclassified = $false
        }
        trustedTimestampComparatorCorrigendumAttempt005 = [ordered]@{
            authorizationId = $authorizationId
            attemptId = $attemptId
            status = $knownAnswerReceipt.status
            offlineKnownAnswerInvocationCount = 1
            unityInvocationCount = 0
            sameAttemptRetryPerformed = $false
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
            autoAttemptsUntilPassAuthorizationConsumedAtAttempt005 = $true
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
    Write-JsonExclusive -Path $nextStatusPath -Value $statusV21

    $evidenceFiles = @(Get-ChildItem -LiteralPath $stageRoot -Recurse -Force -File | Where-Object { $_.FullName -ne $finalManifestPath } | Sort-Object FullName | ForEach-Object {
        [ordered]@{
            relativePath = Get-ProjectRelativePath -Path $_.FullName -Root $resolvedProjectRoot
            lengthBytes = [int64]$_.Length
            sha256 = Get-Sha256Lower -Path $_.FullName
        }
    })
    Write-JsonExclusive -Path $finalManifestPath -Value ([ordered]@{
        schema = 'gate14re-me-trusted-timestamp-comparator-attempt-005-evidence-freeze-manifest-v1'
        studyId = $studyId
        authorizationId = $authorizationId
        attemptId = $attemptId
        status = 'FROZEN_TERMINAL_PASS_EVIDENCE'
        frozenAtUtc = [DateTime]::UtcNow.ToString('o')
        sourceFreezeManifest = [ordered]@{
            relativePath = Get-ProjectRelativePath -Path $resolvedSourceFreezeManifest -Root $resolvedProjectRoot
            sha256 = $SourceFreezeManifestSha256
        }
        statusV21 = [ordered]@{
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
        $attempt004InventoryAfter = @(Get-FileInventory -Root $attempt004Root)
        $attempt004DigestAfter = Get-InventoryContentDigest -Inventory $attempt004InventoryAfter
    }
    catch { }

    if (-not (Test-Path -LiteralPath $failureReceiptPath)) {
        Write-JsonExclusive -Path $failureReceiptPath -Value ([ordered]@{
            schema = 'gate14re-me-trusted-timestamp-comparator-attempt-005-failure-receipt-v1'
            studyId = $studyId
            authorizationId = $authorizationId
            attemptId = $attemptId
            status = 'FAILED_CLOSED_TRUSTED_TIMESTAMP_COMPARATOR_ATTEMPT_005'
            failedAtUtc = [DateTime]::UtcNow.ToString('o')
            exceptionType = $exceptionType
            exactFailure = $exactFailure
            stackTrace = $stackTrace
            offlineKnownAnswerInvocationCount = $knownAnswerInvocationCount
            sameAttemptRetryPerformed = $false
            unityInvocationCount = 0
            retainedEvidence = [ordered]@{
                attempt003BeforeDigestSha256 = $attempt003DigestBefore
                attempt003AfterDigestSha256 = $attempt003DigestAfter
                attempt003Unchanged = ($null -ne $attempt003DigestBefore -and $attempt003DigestAfter -eq $attempt003DigestBefore)
                attempt004BeforeDigestSha256 = $attempt004DigestBefore
                attempt004AfterDigestSha256 = $attempt004DigestAfter
                attempt004Unchanged = ($null -ne $attempt004DigestBefore -and $attempt004DigestAfter -eq $attempt004DigestBefore)
                priorEvidenceReclassified = $false
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
            schema = 'gate14re-me-status-v21'
            studyId = $studyId
            status = 'TRUSTED_TIMESTAMP_COMPARATOR_CORRIGENDUM_ATTEMPT_005_FAILED_CLOSED'
            version = 21
            updatedAtUtc = [DateTime]::UtcNow.ToString('o')
            previousVersionedStatus = [ordered]@{
                relativePath = 'Research/Gate14Re-ME/Gate14Re_ME_Status.v20.json'
                sha256 = $(if (Test-Path -LiteralPath $parentStatusPath) { Get-Sha256Lower -Path $parentStatusPath } else { $null })
                retained = $true
            }
            timestampComparatorAttempt005 = [ordered]@{
                authorizationId = $authorizationId
                attemptId = $attemptId
                passed = $false
                failureReceiptRelativePath = Get-ProjectRelativePath -Path $failureReceiptPath -Root $resolvedProjectRoot
                failureReceiptSha256 = Get-Sha256Lower -Path $failureReceiptPath
                sameAttemptRetryPerformed = $false
                unityInvocationCount = 0
            }
            nextRequiredAction = 'Create the next independently frozen offline attempt under the standing auto-attempt authorization; do not retry attempt-005 or start Unity.'
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
            schema = 'gate14re-me-trusted-timestamp-comparator-attempt-005-evidence-freeze-manifest-v1'
            studyId = $studyId
            authorizationId = $authorizationId
            attemptId = $attemptId
            status = 'FROZEN_TERMINAL_FAILURE_EVIDENCE'
            frozenAtUtc = [DateTime]::UtcNow.ToString('o')
            statusV21 = [ordered]@{
                relativePath = Get-ProjectRelativePath -Path $nextStatusPath -Root $resolvedProjectRoot
                sha256 = Get-Sha256Lower -Path $nextStatusPath
            }
            evidenceFiles = $failureEvidenceFiles
        })
    }

    foreach ($file in @(Get-ChildItem -LiteralPath $stageRoot -Recurse -Force -File)) { Set-ReadOnlyFile -Path $file.FullName }
    Set-ReadOnlyFile -Path $nextStatusPath
    Write-Error "Gate14Re-ME timestamp comparator attempt-005 failed closed: $exactFailure"
    exit 1
}

if (-not $stagePassed) { exit 1 }
