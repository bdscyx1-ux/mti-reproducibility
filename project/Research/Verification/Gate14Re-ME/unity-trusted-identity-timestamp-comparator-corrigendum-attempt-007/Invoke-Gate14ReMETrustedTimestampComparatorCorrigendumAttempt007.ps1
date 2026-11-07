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
$attemptId = 'gate14re-me-unity-trusted-identity-timestamp-comparator-corrigendum-attempt-007'
$expectedStatusHashes = [ordered]@{
    v19 = '94a4697c7bb501d21aefcc0f44abd34cac026cccbf5b074c0b831efb5c14213c'
    v20 = '153658e56dca6af6ff0d7a43fb5c5a5c9ffe74bc3fb50e499e2c9c9abde49b10'
    v21 = '529c0ccf9d7c3172d2548dadee7ad9f61b4d6eda2a28e6a4622d16da16ed55bd'
    v22 = 'be3f26e833396c174de874f5dd7349530a454320bc33073d506812f980fb8a8d'
}
$expectedTrustedRuleSha256 = 'f045ef93630202a72d603096687bac655b5b4ff01e8e0743e60d63881bbded06'
$expectedAttempt006FailureSha256 = 'fb94c0845370964b68a0b6b37273cdacf9fb17879d6e9bd50660b5ffdd6908b0'
$expectedAttempt006FinalManifestSha256 = '3bf56aabebbb1bfbca1bafc8240486f710aa6df499039304976e71c61e012443'
$knownAnswerInvocationCount = 0
$stagePassed = $false
$exactFailure = $null
$exceptionType = $null
$stackTrace = $null
$cases = [System.Collections.Generic.List[object]]::new()
$retainedBefore = [ordered]@{}
$retainedAfter = [ordered]@{}

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

function Get-RetainedState {
    param([object]$Config)
    $inventory = @(Get-FileInventory -Root $Config.root)
    return [pscustomobject][ordered]@{
        key = [string]$Config.key
        label = [string]$Config.label
        root = [string]$Config.root
        fileCount = $inventory.Count
        contentDigestSha256 = Get-InventoryContentDigest -Inventory $inventory
        allReadOnly = (@($inventory | Where-Object { -not $_.readOnly }).Count -eq 0)
        files = $inventory
    }
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
    param([System.Text.Json.JsonElement]$Object, [string]$PropertyName)
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
        [AllowNull()][object]$ExpectedFailureCode
    )
    $comparison = Compare-Gate14ReMETrustedTimestampV1 -TrustedText $Trusted -ObservedText $Observed
    $textPreserved = Test-OriginalTextPreserved -Comparison $comparison -Trusted $Trusted -Observed $Observed
    $failureCodeMatches = if ($null -eq $ExpectedFailureCode) {
        $null -eq $comparison.failureCode
    }
    else {
        [string]$comparison.failureCode -eq [string]$ExpectedFailureCode
    }
    $passed = [bool]($comparison.comparisonAccepted -eq $ExpectedAccepted -and
        $failureCodeMatches -and $textPreserved -and ($ExpectedAccepted -or $comparison.failClosed))
    return [pscustomobject][ordered]@{
        caseId = $CaseId
        expectedAccepted = $ExpectedAccepted
        expectedFailureCode = $ExpectedFailureCode
        actualFailureCode = $comparison.failureCode
        originalTextPreserved = $textPreserved
        passed = $passed
        comparison = $comparison
    }
}

$resolvedProjectRoot = Get-NormalizedFullPath -Path $ProjectRoot -Base (Get-Location).Path
$expectedProjectRoot = [System.IO.Path]::GetFullPath('H:\DDM_Final_Project').TrimEnd('\')
Require-Condition ($resolvedProjectRoot -ieq $expectedProjectRoot) 'Project root is not the authorized Gate14Re-ME project root.'

$stageRoot = Join-Path $resolvedProjectRoot 'Research/Verification/Gate14Re-ME/unity-trusted-identity-timestamp-comparator-corrigendum-attempt-007'
$statusPaths = [ordered]@{
    v19 = Join-Path $resolvedProjectRoot 'Research/Gate14Re-ME/Gate14Re_ME_Status.v19.json'
    v20 = Join-Path $resolvedProjectRoot 'Research/Gate14Re-ME/Gate14Re_ME_Status.v20.json'
    v21 = Join-Path $resolvedProjectRoot 'Research/Gate14Re-ME/Gate14Re_ME_Status.v21.json'
    v22 = Join-Path $resolvedProjectRoot 'Research/Gate14Re-ME/Gate14Re_ME_Status.v22.json'
}
$nextStatusPath = Join-Path $resolvedProjectRoot 'Research/Gate14Re-ME/Gate14Re_ME_Status.v23.json'
$trustedRulePath = Join-Path $resolvedProjectRoot 'Research/Verification/Gate14Re-ME/unity-executable-identity-rule-offline-adjudication-attempt-005/trusted-launch-identity-rule.v1.json'
$comparatorPath = Join-Path $stageRoot 'Gate14ReMETrustedTimestampComparatorV1.ps1'
$knownAnswerReceiptPath = Join-Path $stageRoot 'known-answer-receipt.v1.json'
$failureReceiptPath = Join-Path $stageRoot 'failure-receipt.v1.json'
$finalManifestPath = Join-Path $stageRoot 'source-and-evidence-freeze-manifest.v1.json'

$retainedConfigs = @(
    [pscustomobject][ordered]@{
        key = 'attempt003'
        label = 'qualification-input-schema-compatibility-corrigendum-attempt-003'
        root = Join-Path $resolvedProjectRoot 'Research/Verification/Gate14Re-ME/qualification-input-schema-compatibility-corrigendum-attempt-003'
        expectedFileCount = 15
        expectedDigestSha256 = '770a7f1bf25f763d42186bba77a148280dde6193e05f9887ed0d9a5ffe02deef'
    },
    [pscustomobject][ordered]@{
        key = 'attempt004'
        label = 'unity-trusted-identity-timestamp-comparator-corrigendum-attempt-004'
        root = Join-Path $resolvedProjectRoot 'Research/Verification/Gate14Re-ME/unity-trusted-identity-timestamp-comparator-corrigendum-attempt-004'
        expectedFileCount = 8
        expectedDigestSha256 = '83b30dc296f8acc92e95bcd55a64b0635cd65b1192bfe511795ca3bf125c69f6'
    },
    [pscustomobject][ordered]@{
        key = 'attempt005'
        label = 'unity-trusted-identity-timestamp-comparator-corrigendum-attempt-005'
        root = Join-Path $resolvedProjectRoot 'Research/Verification/Gate14Re-ME/unity-trusted-identity-timestamp-comparator-corrigendum-attempt-005'
        expectedFileCount = 9
        expectedDigestSha256 = '111efac5220e65df22c092547387c24b168701cf4c52a2e41944b2b647e9b88a'
    },
    [pscustomobject][ordered]@{
        key = 'attempt006'
        label = 'unity-trusted-identity-timestamp-comparator-corrigendum-attempt-006'
        root = Join-Path $resolvedProjectRoot 'Research/Verification/Gate14Re-ME/unity-trusted-identity-timestamp-comparator-corrigendum-attempt-006'
        expectedFileCount = 10
        expectedDigestSha256 = '1e8b18cbc9fb1ccb782f3a63c190d2266d069dbbe301f4614a50cc949823b991'
    }
)

Require-Condition (Test-Path -LiteralPath $stageRoot -PathType Container) 'Authorized attempt-007 evidence root is missing.'
Require-Condition (-not (Test-Path -LiteralPath $nextStatusPath)) 'Status v23 already exists; overwrite or same-attempt retry is prohibited.'
$runtimePaths = @($knownAnswerReceiptPath, $failureReceiptPath, $finalManifestPath)
foreach ($config in $retainedConfigs) {
    $runtimePaths += Join-Path $stageRoot "$($config.key)-inventory.before.v1.json"
    $runtimePaths += Join-Path $stageRoot "$($config.key)-inventory.after.v1.json"
}
foreach ($path in $runtimePaths) {
    Require-Condition (-not (Test-Path -LiteralPath $path)) "Runtime evidence already exists; same-attempt retry is prohibited: $path"
}

$resolvedSourceFreezeManifest = Get-NormalizedFullPath -Path $SourceFreezeManifest -Base $resolvedProjectRoot
Require-Condition ((Get-Sha256Lower -Path $resolvedSourceFreezeManifest) -eq $SourceFreezeManifestSha256) 'Source freeze manifest SHA-256 mismatch.'
$sourceFreeze = Get-Content -LiteralPath $resolvedSourceFreezeManifest -Raw -Encoding UTF8 | ConvertFrom-Json -Depth 100
Require-Condition ($sourceFreeze.schema -eq 'gate14re-me-trusted-timestamp-comparator-attempt-007-source-freeze-manifest-v1' -and
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

foreach ($key in $statusPaths.Keys) {
    Require-Condition ((Get-Sha256Lower -Path $statusPaths[$key]) -eq $expectedStatusHashes[$key]) "Status $key SHA-256 mismatch."
}
Require-Condition ((Get-Sha256Lower -Path $trustedRulePath) -eq $expectedTrustedRuleSha256) 'Trusted launch identity rule v1 SHA-256 mismatch.'
$attempt006Root = ($retainedConfigs | Where-Object key -eq 'attempt006').root
Require-Condition ((Get-Sha256Lower -Path (Join-Path $attempt006Root 'failure-receipt.v1.json')) -eq $expectedAttempt006FailureSha256) 'Attempt-006 failure receipt SHA-256 mismatch.'
Require-Condition ((Get-Sha256Lower -Path (Join-Path $attempt006Root 'source-and-evidence-freeze-manifest.v1.json')) -eq $expectedAttempt006FinalManifestSha256) 'Attempt-006 final evidence manifest SHA-256 mismatch.'
Require-Condition (@(Get-CimInstance Win32_Process | Where-Object { $_.Name -eq 'Unity.exe' }).Count -eq 0) 'A Unity process is active; offline-only boundary is not satisfied.'
Require-Condition (@(Get-ProhibitedRootsPresent -Root $resolvedProjectRoot).Count -eq 0) 'A prohibited Gate14Re-ME measured root exists.'

foreach ($config in $retainedConfigs) {
    $state = Get-RetainedState -Config $config
    Require-Condition ($state.fileCount -eq [int]$config.expectedFileCount) "$($config.label) file count differs from the frozen baseline."
    Require-Condition ($state.contentDigestSha256 -eq [string]$config.expectedDigestSha256) "$($config.label) digest differs from the frozen baseline."
    Require-Condition $state.allReadOnly "$($config.label) contains a non-read-only evidence file."
    $retainedBefore[$config.key] = $state
}

try {
    foreach ($config in $retainedConfigs) {
        $state = $retainedBefore[$config.key]
        Write-JsonExclusive -Path (Join-Path $stageRoot "$($config.key)-inventory.before.v1.json") -Value ([ordered]@{
            schema = 'gate14re-me-retained-attempt-inventory-v1'
            studyId = $studyId
            authorizationId = $authorizationId
            attemptId = $attemptId
            retainedAttempt = $config.label
            phase = 'BEFORE_OFFLINE_KNOWN_ANSWER'
            capturedAtUtc = [DateTime]::UtcNow.ToString('o')
            fileCount = $state.fileCount
            contentDigestSha256 = $state.contentDigestSha256
            files = $state.files
        })
    }

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
        actualFailureCode = $ambiguous.failureCode
        originalTextPreserved = ([string]$ambiguous.originalText -eq '2024-06-11T11:26:54Z')
        passed = (-not $ambiguous.parsed -and -not $ambiguous.uniqueParse -and
            [int]$ambiguous.successfulFormatCount -eq 2 -and $ambiguous.failureCode -eq 'NON_UNIQUE_PARSE' -and
            [string]$ambiguous.originalText -eq '2024-06-11T11:26:54Z')
        parse = $ambiguous
    })

    $failedCases = @($cases | Where-Object { -not $_.passed })
    Require-Condition ($cases.Count -eq 16) 'Known-answer cardinality mismatch.'
    if ($failedCases.Count -ne 0) {
        $failedCaseIds = @($failedCases | ForEach-Object { [string]$_.caseId })
        throw [System.InvalidOperationException]::new("One or more offline timestamp known-answer cases failed: $($failedCaseIds -join ', ')")
    }

    foreach ($config in $retainedConfigs) {
        $after = Get-RetainedState -Config $config
        $retainedAfter[$config.key] = $after
        Write-JsonExclusive -Path (Join-Path $stageRoot "$($config.key)-inventory.after.v1.json") -Value ([ordered]@{
            schema = 'gate14re-me-retained-attempt-inventory-v1'
            studyId = $studyId
            authorizationId = $authorizationId
            attemptId = $attemptId
            retainedAttempt = $config.label
            phase = 'AFTER_OFFLINE_KNOWN_ANSWER'
            capturedAtUtc = [DateTime]::UtcNow.ToString('o')
            fileCount = $after.fileCount
            contentDigestSha256 = $after.contentDigestSha256
            exactlyMatchesBeforeInventory = ($after.contentDigestSha256 -eq $retainedBefore[$config.key].contentDigestSha256)
            files = $after.files
        })
        Require-Condition ($after.contentDigestSha256 -eq $retainedBefore[$config.key].contentDigestSha256) "$($config.label) evidence changed during attempt-007."
    }
    foreach ($key in $statusPaths.Keys) {
        Require-Condition ((Get-Sha256Lower -Path $statusPaths[$key]) -eq $expectedStatusHashes[$key]) "Status $key changed during attempt-007."
    }
    Require-Condition ((Get-Sha256Lower -Path $trustedRulePath) -eq $expectedTrustedRuleSha256) 'Trusted launch identity rule changed during attempt-007.'
    Require-Condition (@(Get-CimInstance Win32_Process | Where-Object { $_.Name -eq 'Unity.exe' }).Count -eq 0) 'A Unity process appeared during the offline-only known-answer.'
    Require-Condition (@(Get-ProhibitedRootsPresent -Root $resolvedProjectRoot).Count -eq 0) 'A prohibited Gate14Re-ME measured root appeared.'

    $retainedSummary = @($retainedConfigs | ForEach-Object {
        $before = $retainedBefore[$_.key]
        $after = $retainedAfter[$_.key]
        [ordered]@{
            retainedAttempt = $_.label
            beforeFileCount = $before.fileCount
            afterFileCount = $after.fileCount
            beforeContentDigestSha256 = $before.contentDigestSha256
            afterContentDigestSha256 = $after.contentDigestSha256
            unchanged = $true
            originalFailureStatusRetained = $true
            reclassified = $false
        }
    })

    $knownAnswerReceipt = [ordered]@{
        schema = 'gate14re-me-unity-trusted-timestamp-comparator-attempt-007-known-answer-receipt-v1'
        studyId = $studyId
        authorizationId = $authorizationId
        attemptId = $attemptId
        status = 'PASS_TRUSTED_TIMESTAMP_COMPARATOR_OFFLINE_KNOWN_ANSWER'
        completedAtUtc = [DateTime]::UtcNow.ToString('o')
        passed = $true
        terminal = $true
        offlineKnownAnswerInvocationCount = $knownAnswerInvocationCount
        sameAttemptRetryPerformed = $false
        priorFailedAttemptsRetained = @('attempt-004', 'attempt-005', 'attempt-006')
        unityInvocationCount = 0
        correctedDefects = @(
            'JSON_TIMESTAMP_DATE_COERCION_REMOVED_IN_ATTEMPT_005',
            'OPTIONAL_FRACTION_FORMAT_OVERLAP_REMOVED_IN_ATTEMPT_006',
            'NULL_EXPECTED_FAILURE_CODE_BINDING_CORRECTED_IN_ATTEMPT_006'
            'EAGER_EMPTY_FAILED_CASE_ID_EXPANSION_REMOVED_IN_ATTEMPT_007'
        )
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
            formatSelection = 'ONE_EXACT_FORMAT_SELECTED_FROM_LEXICAL_FRACTION_DIGIT_COUNT'
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
        retainedEvidence = $retainedSummary
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

    $statusV23 = [ordered]@{
        schema = 'gate14re-me-status-v23'
        studyId = $studyId
        status = 'TRUSTED_TIMESTAMP_COMPARATOR_CORRIGENDUM_OFFLINE_QUALIFIED_PASS'
        version = 23
        updatedAtUtc = [DateTime]::UtcNow.ToString('o')
        previousVersionedStatus = [ordered]@{
            relativePath = 'Research/Gate14Re-ME/Gate14Re_ME_Status.v22.json'
            sha256 = $expectedStatusHashes.v22
            retained = $true
        }
        priorTimestampComparatorAttempts = @(
            [ordered]@{ attempt = 'attempt-004'; status = 'FAILED_CLOSED_RETAINED_UNCHANGED'; reclassified = $false },
            [ordered]@{ attempt = 'attempt-005'; status = 'FAILED_CLOSED_RETAINED_UNCHANGED'; reclassified = $false }
            [ordered]@{ attempt = 'attempt-006'; status = 'FAILED_CLOSED_RETAINED_UNCHANGED'; reclassified = $false }
        )
        trustedTimestampComparatorCorrigendumAttempt007 = [ordered]@{
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
            autoAttemptsUntilPassAuthorizationSatisfiedAtAttempt007 = $true
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
    Write-JsonExclusive -Path $nextStatusPath -Value $statusV23

    $evidenceFiles = @(Get-ChildItem -LiteralPath $stageRoot -Recurse -Force -File | Where-Object { $_.FullName -ne $finalManifestPath } | Sort-Object FullName | ForEach-Object {
        [ordered]@{
            relativePath = Get-ProjectRelativePath -Path $_.FullName -Root $resolvedProjectRoot
            lengthBytes = [int64]$_.Length
            sha256 = Get-Sha256Lower -Path $_.FullName
        }
    })
    Write-JsonExclusive -Path $finalManifestPath -Value ([ordered]@{
        schema = 'gate14re-me-trusted-timestamp-comparator-attempt-007-evidence-freeze-manifest-v1'
        studyId = $studyId
        authorizationId = $authorizationId
        attemptId = $attemptId
        status = 'FROZEN_TERMINAL_PASS_EVIDENCE'
        frozenAtUtc = [DateTime]::UtcNow.ToString('o')
        sourceFreezeManifest = [ordered]@{
            relativePath = Get-ProjectRelativePath -Path $resolvedSourceFreezeManifest -Root $resolvedProjectRoot
            sha256 = $SourceFreezeManifestSha256
        }
        statusV23 = [ordered]@{
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

    foreach ($config in $retainedConfigs) {
        try { $retainedAfter[$config.key] = Get-RetainedState -Config $config }
        catch { }
    }
    $failedCaseSummary = @($cases | Where-Object { -not $_.passed } | ForEach-Object {
        [ordered]@{
            caseId = $_.caseId
            expectedAccepted = $_.expectedAccepted
            expectedFailureCode = $_.expectedFailureCode
            actualFailureCode = $_.actualFailureCode
            originalTextPreserved = $_.originalTextPreserved
        }
    })

    if (-not (Test-Path -LiteralPath $failureReceiptPath)) {
        Write-JsonExclusive -Path $failureReceiptPath -Value ([ordered]@{
            schema = 'gate14re-me-trusted-timestamp-comparator-attempt-007-failure-receipt-v1'
            studyId = $studyId
            authorizationId = $authorizationId
            attemptId = $attemptId
            status = 'FAILED_CLOSED_TRUSTED_TIMESTAMP_COMPARATOR_ATTEMPT_007'
            failedAtUtc = [DateTime]::UtcNow.ToString('o')
            exceptionType = $exceptionType
            exactFailure = $exactFailure
            stackTrace = $stackTrace
            offlineKnownAnswerInvocationCount = $knownAnswerInvocationCount
            sameAttemptRetryPerformed = $false
            unityInvocationCount = 0
            failedCases = $failedCaseSummary
            retainedEvidence = @($retainedConfigs | ForEach-Object {
                $before = $retainedBefore[$_.key]
                $after = $retainedAfter[$_.key]
                [ordered]@{
                    retainedAttempt = $_.label
                    beforeDigestSha256 = $(if ($null -ne $before) { $before.contentDigestSha256 } else { $null })
                    afterDigestSha256 = $(if ($null -ne $after) { $after.contentDigestSha256 } else { $null })
                    unchanged = ($null -ne $before -and $null -ne $after -and $before.contentDigestSha256 -eq $after.contentDigestSha256)
                    reclassified = $false
                }
            })
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
            schema = 'gate14re-me-status-v23'
            studyId = $studyId
            status = 'TRUSTED_TIMESTAMP_COMPARATOR_CORRIGENDUM_ATTEMPT_007_FAILED_CLOSED'
            version = 23
            updatedAtUtc = [DateTime]::UtcNow.ToString('o')
            previousVersionedStatus = [ordered]@{
                relativePath = 'Research/Gate14Re-ME/Gate14Re_ME_Status.v22.json'
                sha256 = $(if (Test-Path -LiteralPath $statusPaths.v22) { Get-Sha256Lower -Path $statusPaths.v22 } else { $null })
                retained = $true
            }
            timestampComparatorAttempt007 = [ordered]@{
                authorizationId = $authorizationId
                attemptId = $attemptId
                passed = $false
                failureReceiptRelativePath = Get-ProjectRelativePath -Path $failureReceiptPath -Root $resolvedProjectRoot
                failureReceiptSha256 = Get-Sha256Lower -Path $failureReceiptPath
                sameAttemptRetryPerformed = $false
                unityInvocationCount = 0
            }
            nextRequiredAction = 'Create the next independently frozen offline attempt under the standing auto-attempt authorization; do not retry attempt-007 or start Unity.'
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
            schema = 'gate14re-me-trusted-timestamp-comparator-attempt-007-evidence-freeze-manifest-v1'
            studyId = $studyId
            authorizationId = $authorizationId
            attemptId = $attemptId
            status = 'FROZEN_TERMINAL_FAILURE_EVIDENCE'
            frozenAtUtc = [DateTime]::UtcNow.ToString('o')
            statusV23 = [ordered]@{
                relativePath = Get-ProjectRelativePath -Path $nextStatusPath -Root $resolvedProjectRoot
                sha256 = Get-Sha256Lower -Path $nextStatusPath
            }
            evidenceFiles = $failureEvidenceFiles
        })
    }

    foreach ($file in @(Get-ChildItem -LiteralPath $stageRoot -Recurse -Force -File)) { Set-ReadOnlyFile -Path $file.FullName }
    Set-ReadOnlyFile -Path $nextStatusPath
    Write-Error "Gate14Re-ME timestamp comparator attempt-007 failed closed: $exactFailure"
    exit 1
}

if (-not $stagePassed) { exit 1 }
