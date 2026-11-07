[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ProjectRoot,

    [Parameter(Mandatory = $true)]
    [string]$UnityExecutable,

    [Parameter(Mandatory = $true)]
    [string]$SourceFreezeManifest,

    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[0-9a-f]{64}$')]
    [string]$SourceFreezeManifestSha256
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$studyId = 'Gate14Re-ME'
$authorizationId = 'gate14re-me-qualification-input-schema-compatibility-corrigendum-attempt-003'
$executeMethod = 'DDM.Research.Editor.InputSchemaCorrigendumAttempt003.Gate14ReMEInputSchemaCompatibilitySelfCheckV2.Run'
$expectedUnitySha256 = '0a69d14cbe2ca82d0a6168da8156d9e0dd138a6b7d0260dcdea31fd3957ca9cf'
$expectedTrustedRuleSha256 = 'f045ef93630202a72d603096687bac655b5b4ff01e8e0743e60d63881bbded06'
$expectedParentStatusSha256 = '59e11282be382c2b46660e03cca3a85c3eb2ee855f49d7b212301c14807bd277'
$chunkSizeBytes = 65536
$unityInvocationCount = 0
$unityProcess = $null
$unityProcessMetadata = $null
$unityExitCode = $null
$stagePassed = $false
$exactFailure = $null
$exceptionType = $null
$stackTrace = $null
$transientCleanup = @()
$prelaunchFingerprint = $null
$liveFingerprint = $null
$postExitFingerprint = $null
$attempt001InventoryBefore = @()
$attempt001InventoryAfter = @()
$attempt001DigestBefore = $null
$attempt001DigestAfter = $null
$attempt002InventoryBefore = @()
$attempt002InventoryAfter = @()
$attempt002DigestBefore = $null
$attempt002DigestAfter = $null

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

function Get-DotNetSha256Lower {
    param([string]$Path)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    $stream = [System.IO.FileStream]::new(
        $Path,
        [System.IO.FileMode]::Open,
        [System.IO.FileAccess]::Read,
        [System.IO.FileShare]::ReadWrite -bor [System.IO.FileShare]::Delete)
    try { return [Convert]::ToHexString($sha.ComputeHash($stream)).ToLowerInvariant() }
    finally { $stream.Dispose(); $sha.Dispose() }
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

function New-DirectoryExclusive {
    param([string]$Path)
    Require-Condition (-not (Test-Path -LiteralPath $Path)) "Refusing to reuse directory: $Path"
    $null = New-Item -ItemType Directory -Path $Path
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

function Get-ExternalFileIdentity {
    param([string]$Path)
    $lines = @(& "$env:SystemRoot\System32\fsutil.exe" file queryfileid $Path 2>&1 | ForEach-Object { [string]$_ })
    $exitCode = $LASTEXITCODE
    $raw = $lines -join [Environment]::NewLine
    $match = [regex]::Match($raw, '0x[0-9A-Fa-f]+')
    return [ordered]@{
        succeeded = ($exitCode -eq 0 -and $match.Success)
        normalizedPath = [System.IO.Path]::GetFullPath($Path).Replace('\', '/')
        fileIdHex = $(if ($match.Success) { $match.Value.Substring(2).ToLowerInvariant() } else { $null })
        fileIndexLow64Hex = $(if ($match.Success) {
            $hex = $match.Value.Substring(2).ToLowerInvariant()
            if ($hex.Length -gt 16) { $hex.Substring($hex.Length - 16) } else { $hex.PadLeft(16, '0') }
        } else { $null })
        fsutilExitCode = $exitCode
        fsutilOutput = $raw
    }
}

function Get-PeIdentity {
    param([string]$Path)
    $result = [ordered]@{
        succeeded = $false
        peHeaderOffset = $null
        optionalHeaderMagicHex = $null
        checksumFieldOffset = $null
        checksumHex = $null
        securityDirectoryFieldOffset = $null
        certificateTableFileOffset = $null
        certificateTableSizeBytes = $null
        exactFailure = $null
    }
    try {
        $stream = [System.IO.FileStream]::new($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite -bor [System.IO.FileShare]::Delete)
        try {
            $reader = [System.IO.BinaryReader]::new($stream, [System.Text.Encoding]::UTF8, $true)
            try {
                Require-Condition ($stream.Length -ge 256) 'PE file is too short.'
                $stream.Position = 0x3c
                $peOffset = $reader.ReadInt32()
                Require-Condition ($peOffset -gt 0 -and ($peOffset + 256) -lt $stream.Length) 'PE header offset is invalid.'
                $stream.Position = $peOffset
                Require-Condition ($reader.ReadUInt32() -eq 0x00004550) 'PE signature is invalid.'
                $optionalHeaderOffset = [int64]$peOffset + 24
                $stream.Position = $optionalHeaderOffset
                $magic = $reader.ReadUInt16()
                Require-Condition ($magic -in @(0x10b, 0x20b)) 'PE optional-header magic is unsupported.'
                $checksumOffset = $optionalHeaderOffset + 64
                $stream.Position = $checksumOffset
                $checksum = $reader.ReadUInt32()
                $dataDirectoryOffset = $optionalHeaderOffset + $(if ($magic -eq 0x20b) { 112 } else { 96 })
                $securityDirectoryOffset = $dataDirectoryOffset + 32
                $stream.Position = $securityDirectoryOffset
                $certificateOffset = $reader.ReadUInt32()
                $certificateSize = $reader.ReadUInt32()
                $result.succeeded = $true
                $result.peHeaderOffset = $peOffset
                $result.optionalHeaderMagicHex = ('{0:x4}' -f $magic)
                $result.checksumFieldOffset = $checksumOffset
                $result.checksumHex = ('{0:x8}' -f $checksum)
                $result.securityDirectoryFieldOffset = $securityDirectoryOffset
                $result.certificateTableFileOffset = $certificateOffset
                $result.certificateTableSizeBytes = $certificateSize
            }
            finally { $reader.Dispose() }
        }
        finally { $stream.Dispose() }
    }
    catch { $result.exactFailure = $_.Exception.GetType().FullName + ': ' + $_.Exception.Message }
    return [pscustomobject]$result
}

function Get-ChunkHashes {
    param([string]$Path, [int]$ChunkSize)
    $chunks = [System.Collections.Generic.List[object]]::new()
    $stream = [System.IO.FileStream]::new($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite -bor [System.IO.FileShare]::Delete)
    try {
        $buffer = [byte[]]::new($ChunkSize)
        $index = 0
        [int64]$offset = 0
        while ($true) {
            $count = 0
            while ($count -lt $buffer.Length) {
                $read = $stream.Read($buffer, $count, $buffer.Length - $count)
                if ($read -eq 0) { break }
                $count += $read
            }
            if ($count -eq 0) { break }
            $sha = [System.Security.Cryptography.SHA256]::Create()
            try { $digest = [Convert]::ToHexString($sha.ComputeHash($buffer, 0, $count)).ToLowerInvariant() }
            finally { $sha.Dispose() }
            $chunks.Add([pscustomobject][ordered]@{
                chunkIndex = $index
                offsetBytes = $offset
                lengthBytes = $count
                sha256 = $digest
            })
            $index++
            $offset += $count
            if ($count -lt $buffer.Length) { break }
        }
    }
    finally { $stream.Dispose() }
    return @($chunks)
}

function Get-ExternalFingerprint {
    param([string]$Path, [string]$Phase)
    $item = Get-Item -LiteralPath $Path -Force
    $signature = Get-AuthenticodeSignature -LiteralPath $Path
    $version = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($item.FullName)
    $getFileHash = Get-Sha256Lower -Path $Path
    $dotNetHash = Get-DotNetSha256Lower -Path $Path
    return [ordered]@{
        schema = 'gate14re-me-external-unity-executable-fingerprint-v1'
        studyId = $studyId
        authorizationId = $authorizationId
        phase = $Phase
        capturedAtUtc = [DateTime]::UtcNow.ToString('o')
        path = $item.FullName.Replace('\', '/')
        lengthBytes = [int64]$item.Length
        creationTimeUtc = $item.CreationTimeUtc.ToString('o')
        lastWriteTimeUtc = $item.LastWriteTimeUtc.ToString('o')
        attributes = $item.Attributes.ToString()
        reparsePoint = (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0)
        fileIdentity = Get-ExternalFileIdentity -Path $item.FullName
        peIdentity = Get-PeIdentity -Path $item.FullName
        authenticode = [ordered]@{
            status = $signature.Status.ToString()
            statusMessage = $signature.StatusMessage
            signerSubject = $(if ($null -ne $signature.SignerCertificate) { $signature.SignerCertificate.Subject } else { $null })
            signerThumbprint = $(if ($null -ne $signature.SignerCertificate) { $signature.SignerCertificate.Thumbprint } else { $null })
        }
        versionMetadata = [ordered]@{
            fileVersion = $version.FileVersion
            productVersion = $version.ProductVersion
            originalFilename = $version.OriginalFilename
            companyName = $version.CompanyName
            productName = $version.ProductName
        }
        fullFileHashes = @(
            [ordered]@{ method = 'powershell-get-filehash'; succeeded = $true; sha256 = $getFileHash },
            [ordered]@{ method = 'dotnet-sha256-filestream'; succeeded = $true; sha256 = $dotNetHash }
        )
        independentHashMethodsAgree = ($getFileHash -eq $dotNetHash)
        chunkSizeBytes = $chunkSizeBytes
        chunkHashes = @(Get-ChunkHashes -Path $item.FullName -ChunkSize $chunkSizeBytes)
    }
}

function Get-HashValue {
    param([object]$Fingerprint, [string]$Method)
    $hashRecords = @($Fingerprint.fullFileHashes | Where-Object { $_.method -eq $Method })
    Require-Condition ($hashRecords.Count -eq 1) "Missing or ambiguous hash method: $Method"
    $hashRecord = $hashRecords[0]
    Require-Condition ([bool]$hashRecord.succeeded) "Failed hash method: $Method"
    $hashValue = [string]$hashRecord.sha256
    Require-Condition ([regex]::IsMatch($hashValue, '^[0-9a-f]{64}$')) "Invalid SHA-256 from hash method: $Method"
    return $hashValue
}

function Test-PathsEqual {
    param([string]$Left, [string]$Right)
    if ([string]::IsNullOrWhiteSpace($Left) -or [string]::IsNullOrWhiteSpace($Right)) { return $false }
    return [System.IO.Path]::GetFullPath($Left).TrimEnd('\') -ieq [System.IO.Path]::GetFullPath($Right).TrimEnd('\')
}

function Compare-ChunkHashes {
    param([object[]]$Left, [object[]]$Right)
    if ($Left.Count -ne $Right.Count) { return $false }
    for ($index = 0; $index -lt $Left.Count; $index++) {
        if ([int]$Left[$index].chunkIndex -ne [int]$Right[$index].chunkIndex -or
            [int64]$Left[$index].offsetBytes -ne [int64]$Right[$index].offsetBytes -or
            [int]$Left[$index].lengthBytes -ne [int]$Right[$index].lengthBytes -or
            [string]$Left[$index].sha256 -ne [string]$Right[$index].sha256) { return $false }
    }
    return $true
}

function Compare-PeIdentity {
    param([object]$Left, [object]$Right)
    return $Left.succeeded -and $Right.succeeded -and
        [int64]$Left.peHeaderOffset -eq [int64]$Right.peHeaderOffset -and
        [string]$Left.optionalHeaderMagicHex -eq [string]$Right.optionalHeaderMagicHex -and
        [int64]$Left.checksumFieldOffset -eq [int64]$Right.checksumFieldOffset -and
        [string]$Left.checksumHex -eq [string]$Right.checksumHex -and
        [int64]$Left.securityDirectoryFieldOffset -eq [int64]$Right.securityDirectoryFieldOffset -and
        [int64]$Left.certificateTableFileOffset -eq [int64]$Right.certificateTableFileOffset -and
        [int64]$Left.certificateTableSizeBytes -eq [int64]$Right.certificateTableSizeBytes
}

function Compare-VersionMetadata {
    param([object]$Left, [object]$Right)
    return [string]$Left.fileVersion -eq [string]$Right.fileVersion -and
        [string]$Left.productVersion -eq [string]$Right.productVersion -and
        [string]$Left.originalFilename -eq [string]$Right.originalFilename -and
        [string]$Left.companyName -eq [string]$Right.companyName -and
        [string]$Left.productName -eq [string]$Right.productName
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

function Get-ActiveGate14ReMEExecutionProcesses {
    return @(Get-CimInstance Win32_Process | Where-Object {
        $_.Name -eq 'Unity.exe' -and (
            $_.CommandLine -match 'Gate14ReME(InputSchemaCompatibilitySelfCheck|LoadQualificationRunner|QualificationPlanner|ReferenceOracle)' -or
            $_.CommandLine -match 'Research[/\\](PilotRuns|FormalRuns|QualificationRuns|MeasuredRuns)[/\\]Gate14Re-ME')
    })
}

function Remove-IsolatedUnityTransientCaches {
    param([string]$IsolatedProjectRoot, [string]$AuthorizedStageRoot)
    $resolvedProject = [System.IO.Path]::GetFullPath($IsolatedProjectRoot).TrimEnd('\')
    $resolvedStage = [System.IO.Path]::GetFullPath($AuthorizedStageRoot).TrimEnd('\')
    $stagePrefix = $resolvedStage + [System.IO.Path]::DirectorySeparatorChar
    Require-Condition $resolvedProject.StartsWith($stagePrefix, [System.StringComparison]::OrdinalIgnoreCase) 'Isolated project is outside the authorized attempt-003 root.'
    $removed = [System.Collections.Generic.List[object]]::new()
    foreach ($name in @('Library', 'Temp', 'Logs', 'obj', 'UserSettings')) {
        $target = [System.IO.Path]::GetFullPath((Join-Path $resolvedProject $name))
        $projectPrefix = $resolvedProject + [System.IO.Path]::DirectorySeparatorChar
        Require-Condition $target.StartsWith($projectPrefix, [System.StringComparison]::OrdinalIgnoreCase) "Transient cleanup target escaped isolated project: $target"
        if (Test-Path -LiteralPath $target -PathType Container) {
            $beforeBytes = [int64](Get-ChildItem -LiteralPath $target -Recurse -Force -File -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
            Remove-Item -LiteralPath $target -Recurse -Force
            Require-Condition (-not (Test-Path -LiteralPath $target)) "Failed to remove regenerable isolated-project cache: $target"
            $removed.Add([pscustomobject][ordered]@{
                relativePath = Get-ProjectRelativePath -Path $target -Root $AuthorizedStageRoot
                bytesRemoved = $beforeBytes
                recoverableByUnityRegeneration = $true
            })
        }
    }
    return @($removed)
}

function Set-ReadOnlyFile {
    param([string]$Path)
    if (Test-Path -LiteralPath $Path -PathType Leaf) { (Get-Item -LiteralPath $Path -Force).IsReadOnly = $true }
}

function Test-ExternalFingerprintAgainstTrustedRule {
    param([object]$Fingerprint, [object]$TrustedRule)
    return $Fingerprint.independentHashMethodsAgree -and
        (Get-HashValue -Fingerprint $Fingerprint -Method 'powershell-get-filehash') -eq $expectedUnitySha256 -and
        (Get-HashValue -Fingerprint $Fingerprint -Method 'dotnet-sha256-filestream') -eq $expectedUnitySha256 -and
        (Test-PathsEqual -Left ([string]$Fingerprint.path) -Right ([string]$TrustedRule.applicability.unityExecutablePath)) -and
        -not [bool]$Fingerprint.reparsePoint -and [bool]$Fingerprint.fileIdentity.succeeded -and
        [string]$Fingerprint.fileIdentity.fileIdHex -eq [string]$TrustedRule.applicability.ntfsFileIdHex -and
        [string]$Fingerprint.fileIdentity.fileIndexLow64Hex -eq [string]$TrustedRule.applicability.ntfsFileIndexLow64Hex -and
        [bool]$Fingerprint.peIdentity.succeeded -and [string]$Fingerprint.authenticode.status -eq 'Valid' -and
        [string]$Fingerprint.authenticode.signerSubject -eq [string]$TrustedRule.applicability.signerSubject -and
        [string]$Fingerprint.authenticode.signerThumbprint -eq [string]$TrustedRule.applicability.signerThumbprint -and
        [int64]$Fingerprint.lengthBytes -eq [int64]$TrustedRule.applicability.fileLengthBytes -and
        [string]$Fingerprint.creationTimeUtc -eq [string]$TrustedRule.applicability.creationTimeUtc -and
        [string]$Fingerprint.lastWriteTimeUtc -eq [string]$TrustedRule.applicability.lastWriteTimeUtc -and
        [int]$Fingerprint.chunkSizeBytes -eq $chunkSizeBytes -and @($Fingerprint.chunkHashes).Count -gt 0
}

$resolvedProjectRoot = Get-NormalizedFullPath -Path $ProjectRoot -Base (Get-Location).Path
$expectedProjectRoot = [System.IO.Path]::GetFullPath('H:\DDM_Final_Project').TrimEnd('\')
Require-Condition ($resolvedProjectRoot -ieq $expectedProjectRoot) 'Project root is not the authorized Gate14Re-ME project root.'

$resolvedUnityExecutable = Get-NormalizedFullPath -Path $UnityExecutable -Base $resolvedProjectRoot
$expectedUnityPath = [System.IO.Path]::GetFullPath('H:\UnityEditor\2022.3.30f1c1\Editor\Unity.exe')
Require-Condition ($resolvedUnityExecutable -ieq $expectedUnityPath) 'Unity executable path is not the authorized path.'

$stageRoot = Join-Path $resolvedProjectRoot 'Research/Verification/Gate14Re-ME/qualification-input-schema-compatibility-corrigendum-attempt-003'
$attempt001Root = Join-Path $resolvedProjectRoot 'Research/Verification/Gate14Re-ME/qualification-input-schema-compatibility-corrigendum-attempt-001'
$attempt002Root = Join-Path $resolvedProjectRoot 'Research/Verification/Gate14Re-ME/qualification-input-schema-compatibility-corrigendum-attempt-002'
$isolatedProjectRoot = Join-Path $stageRoot 'isolated-unity-project'
$unityOutputRoot = Join-Path $stageRoot 'unity-output'
$unityLogPath = Join-Path $stageRoot 'unity-self-check.log'
$readyPath = Join-Path $unityOutputRoot 'in-process-ready-snapshot.v1.json'
$unityReceiptPath = Join-Path $unityOutputRoot 'input-schema-compatibility-self-check-receipt.v2.json'
$trustedRulePath = Join-Path $resolvedProjectRoot 'Research/Verification/Gate14Re-ME/unity-executable-identity-rule-offline-adjudication-attempt-005/trusted-launch-identity-rule.v1.json'
$parentStatusPath = Join-Path $resolvedProjectRoot 'Research/Gate14Re-ME/Gate14Re_ME_Status.v18.json'
$nextStatusPath = Join-Path $resolvedProjectRoot 'Research/Gate14Re-ME/Gate14Re_ME_Status.v19.json'
$finalManifestPath = Join-Path $stageRoot 'source-and-evidence-freeze-manifest.v1.json'

Require-Condition (Test-Path -LiteralPath $stageRoot -PathType Container) 'Authorized attempt-003 evidence root is missing.'
Require-Condition (-not (Test-Path -LiteralPath $nextStatusPath)) 'Status v19 already exists; overwrite or retry is prohibited.'
foreach ($path in @($unityOutputRoot, $unityLogPath, (Join-Path $stageRoot 'external-prelaunch-fingerprint.v1.json'),
    (Join-Path $stageRoot 'external-live-fingerprint.v1.json'), (Join-Path $stageRoot 'external-post-exit-fingerprint.v1.json'),
    (Join-Path $stageRoot 'process-launch-receipt.v1.json'), (Join-Path $stageRoot 'terminal-receipt.v1.json'),
    (Join-Path $stageRoot 'failure-receipt.v1.json'), $finalManifestPath)) {
    Require-Condition (-not (Test-Path -LiteralPath $path)) "Runtime evidence already exists; retry is prohibited: $path"
}

$resolvedSourceFreezeManifest = Get-NormalizedFullPath -Path $SourceFreezeManifest -Base $resolvedProjectRoot
Require-Condition ((Get-Sha256Lower -Path $resolvedSourceFreezeManifest) -eq $SourceFreezeManifestSha256) 'Source freeze manifest SHA-256 mismatch.'
$sourceFreeze = Get-Content -LiteralPath $resolvedSourceFreezeManifest -Raw -Encoding UTF8 | ConvertFrom-Json -Depth 100
Require-Condition ($sourceFreeze.schema -eq 'gate14re-me-input-schema-compatibility-attempt-003-source-freeze-manifest-v1' -and
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

Require-Condition ((Get-Sha256Lower -Path $trustedRulePath) -eq $expectedTrustedRuleSha256) 'Trusted launch identity rule SHA-256 mismatch.'
Require-Condition ((Get-Sha256Lower -Path $parentStatusPath) -eq $expectedParentStatusSha256) 'Parent status v18 SHA-256 mismatch.'
$trustedRule = Get-Content -LiteralPath $trustedRulePath -Raw -Encoding UTF8 | ConvertFrom-Json -Depth 100
Require-Condition ($trustedRule.schema -eq 'gate14re-me-unity-executable-identity-verification-rule-v1' -and
    $trustedRule.studyId -eq $studyId -and $trustedRule.status -eq 'FROZEN_TRUSTED_IDENTITY_RULE_FROM_OFFLINE_ADJUDICATION') 'Trusted identity rule header mismatch.'
Require-Condition ($trustedRule.requirements.externalThreePhaseExpectedSha256AndIndependentMethodAgreement -and
    $trustedRule.requirements.external64KiBChunksPathFileIdPeSignerAndMetadataStable -and
    $trustedRule.requirements.pidCreationTimePathCommandLineAndExecuteMethodBound -and
    $trustedRule.requirements.inProcessPathSourcesAndStructuralIdentityStable -and
    $trustedRule.requirements.knownAnswersPassed -and $trustedRule.requirements.normalExitAndPostExitReconfirmationRequired -and
    -not $trustedRule.requirements.inProcessSelfHashesRequiredForAuthorization -and
    [string]$trustedRule.requirements.fileReadAllBytesRole -eq 'DIAGNOSTIC_ONLY' -and
    [string]$trustedRule.requirements.anyAuthoritativeMismatchDisposition -eq 'FAIL_CLOSED_NO_ADOPTION') 'Trusted identity rule requirements are incomplete or changed.'

Require-Condition ((Get-Sha256Lower -Path $resolvedUnityExecutable) -eq $expectedUnitySha256) 'External preflight Unity SHA-256 mismatch.'
Require-Condition (@(Get-CimInstance Win32_Process | Where-Object { $_.Name -eq 'Unity.exe' }).Count -eq 0) 'A Unity process is already active; isolated identity attribution is unavailable.'
Require-Condition (@(Get-ActiveGate14ReMEExecutionProcesses).Count -eq 0) 'A prohibited Gate14Re-ME Unity process is active.'
Require-Condition (@(Get-ProhibitedRootsPresent -Root $resolvedProjectRoot).Count -eq 0) 'A prohibited Gate14Re-ME measured root already exists.'

$attempt001InventoryBefore = @(Get-FileInventory -Root $attempt001Root)
$attempt001DigestBefore = Get-InventoryContentDigest -Inventory $attempt001InventoryBefore
Require-Condition ($attempt001InventoryBefore.Count -eq [int]$sourceFreeze.retainedAttempt001.fileCount) 'Attempt-001 retained evidence file count differs from the frozen baseline.'
Require-Condition ($attempt001DigestBefore -eq [string]$sourceFreeze.retainedAttempt001.contentDigestSha256) 'Attempt-001 retained evidence digest differs from the frozen baseline.'
$attempt002InventoryBefore = @(Get-FileInventory -Root $attempt002Root)
$attempt002DigestBefore = Get-InventoryContentDigest -Inventory $attempt002InventoryBefore
Require-Condition ($attempt002InventoryBefore.Count -eq [int]$sourceFreeze.retainedAttempt002.fileCount) 'Attempt-002 retained evidence file count differs from the frozen baseline.'
Require-Condition ($attempt002DigestBefore -eq [string]$sourceFreeze.retainedAttempt002.contentDigestSha256) 'Attempt-002 retained evidence digest differs from the frozen baseline.'

try {
    Write-JsonExclusive -Path (Join-Path $stageRoot 'attempt001-inventory.before.v1.json') -Value ([ordered]@{
        schema = 'gate14re-me-retained-schema-compatibility-attempt-inventory-v1'
        studyId = $studyId
        authorizationId = $authorizationId
        phase = 'BEFORE_ATTEMPT_003_UNITY_INVOCATION'
        capturedAtUtc = [DateTime]::UtcNow.ToString('o')
        rootRelativePath = Get-ProjectRelativePath -Path $attempt001Root -Root $resolvedProjectRoot
        fileCount = $attempt001InventoryBefore.Count
        contentDigestSha256 = $attempt001DigestBefore
        files = $attempt001InventoryBefore
    })
    Write-JsonExclusive -Path (Join-Path $stageRoot 'attempt002-inventory.before.v1.json') -Value ([ordered]@{
        schema = 'gate14re-me-retained-schema-compatibility-attempt-inventory-v1'
        studyId = $studyId
        authorizationId = $authorizationId
        phase = 'BEFORE_ATTEMPT_003_UNITY_INVOCATION'
        capturedAtUtc = [DateTime]::UtcNow.ToString('o')
        rootRelativePath = Get-ProjectRelativePath -Path $attempt002Root -Root $resolvedProjectRoot
        fileCount = $attempt002InventoryBefore.Count
        contentDigestSha256 = $attempt002DigestBefore
        files = $attempt002InventoryBefore
    })

    $prelaunchFingerprint = Get-ExternalFingerprint -Path $resolvedUnityExecutable -Phase 'EXTERNAL_PRELAUNCH'
    Require-Condition (Test-ExternalFingerprintAgainstTrustedRule -Fingerprint $prelaunchFingerprint -TrustedRule $trustedRule) 'External prelaunch fingerprint does not satisfy the trusted rule.'
    Write-JsonExclusive -Path (Join-Path $stageRoot 'external-prelaunch-fingerprint.v1.json') -Value $prelaunchFingerprint

    New-DirectoryExclusive -Path $unityOutputRoot
    $unityArguments = @(
        '-batchmode', '-nographics', '-quit',
        '-projectPath', $isolatedProjectRoot,
        '-logFile', $unityLogPath,
        '-executeMethod', $executeMethod,
        '--g14me-source-project-root', $resolvedProjectRoot,
        '--g14me-schema-output-dir', $unityOutputRoot,
        '--g14me-live-hold-seconds', '30',
        '--g14me-source-freeze-manifest', $resolvedSourceFreezeManifest,
        '--g14me-source-freeze-manifest-sha256', $SourceFreezeManifestSha256
    )

    Write-Output 'Launching exactly one isolated, algorithm-free Unity schema-compatibility self-check.'
    $unityProcess = Start-Process -FilePath $resolvedUnityExecutable -ArgumentList $unityArguments -WindowStyle Hidden -PassThru
    $unityInvocationCount = 1
    $unityProcessId = $unityProcess.Id
    $launchedAtUtc = [DateTime]::UtcNow.ToString('o')

    $metadataDeadline = [DateTime]::UtcNow.AddSeconds(30)
    while ($null -eq $unityProcessMetadata -and [DateTime]::UtcNow -lt $metadataDeadline) {
        $unityProcessMetadata = Get-CimInstance Win32_Process -Filter "ProcessId = $unityProcessId" -ErrorAction SilentlyContinue
        if ($null -eq $unityProcessMetadata) { Start-Sleep -Milliseconds 100 }
    }
    Require-Condition ($null -ne $unityProcessMetadata) 'Unable to capture the launched Unity process metadata.'
    $creationUtc = ([DateTime]$unityProcessMetadata.CreationDate).ToUniversalTime().ToString('o')
    $commandLine = [string]$unityProcessMetadata.CommandLine
    Require-Condition (Test-PathsEqual -Left ([string]$unityProcessMetadata.ExecutablePath) -Right $resolvedUnityExecutable) 'Live process executable path differs from the trusted Unity path.'
    Require-Condition ($commandLine.Contains($executeMethod)) 'Live command line lacks the authorized execute method.'
    Require-Condition ($commandLine.Contains($isolatedProjectRoot)) 'Live command line lacks the isolated attempt-003 project root.'
    Require-Condition (-not ($commandLine -match 'Gate14ReMELoadQualificationRunner|Gate14ReMEQualificationPlanner|Gate14ReMEReferenceOracle')) 'A prohibited execution method appeared in the live command line.'

    Write-JsonExclusive -Path (Join-Path $stageRoot 'process-launch-receipt.v1.json') -Value ([ordered]@{
        schema = 'gate14re-me-input-schema-compatibility-unity-launch-receipt-v1'
        studyId = $studyId
        authorizationId = $authorizationId
        status = 'ONE_ISOLATED_ALGORITHM_FREE_UNITY_SCHEMA_SELF_CHECK_LAUNCHED'
        launchedAtUtc = $launchedAtUtc
        invocationOrdinal = 1
        processId = $unityProcessId
        creationTimeUtc = $creationUtc
        executablePath = ([string]$unityProcessMetadata.ExecutablePath).Replace('\', '/')
        commandLine = $commandLine
        executeMethod = $executeMethod
        isolatedProjectRelativePath = Get-ProjectRelativePath -Path $isolatedProjectRoot -Root $resolvedProjectRoot
        retryAuthorized = $false
        plannerAuthorized = $false
        algorithmLaneAuthorized = $false
    })

    $readyDeadline = [DateTime]::UtcNow.AddMinutes(20)
    $nextProgressUtc = [DateTime]::UtcNow.AddSeconds(30)
    while (-not (Test-Path -LiteralPath $readyPath -PathType Leaf)) {
        $unityProcess.Refresh()
        if ($unityProcess.HasExited) { break }
        if ([DateTime]::UtcNow -ge $nextProgressUtc) {
            Write-Output "Unity is compiling the isolated current sources; pid=$unityProcessId; no intervention or retry."
            $nextProgressUtc = [DateTime]::UtcNow.AddSeconds(30)
        }
        Require-Condition ([DateTime]::UtcNow -lt $readyDeadline) 'Unity did not publish the in-process ready snapshot within 20 minutes.'
        Start-Sleep -Milliseconds 250
    }
    Require-Condition (Test-Path -LiteralPath $readyPath -PathType Leaf) 'Unity exited before publishing the in-process ready snapshot.'
    $unityProcess.Refresh()
    Require-Condition (-not $unityProcess.HasExited) 'Unity exited before the live external fingerprint could be taken.'

    $ready = Get-Content -LiteralPath $readyPath -Raw -Encoding UTF8 | ConvertFrom-Json -Depth 100
    Require-Condition ($ready.schema -eq 'gate14re-me-input-schema-compatibility-in-process-ready-snapshot-v1' -and
        $ready.studyId -eq $studyId -and $ready.authorizationId -eq $authorizationId -and
        $ready.status -eq 'IN_PROCESS_SCHEMA_SELF_CHECK_IDENTITY_READY') 'In-process ready snapshot header mismatch.'
    Require-Condition ([int]$ready.process.processId -eq $unityProcessId) 'In-process ready snapshot PID mismatch.'
    Require-Condition (-not $ready.schemaCompatibilitySelfCheckInvoked -and -not $ready.plannerInvoked -and
        -not $ready.algorithmLaneExecuted -and -not $ready.measuredRootCreated) 'Ready snapshot reports prohibited activity.'

    Write-Output 'In-process identity snapshot is ready; capturing the authoritative live external fingerprint.'
    $liveFingerprint = Get-ExternalFingerprint -Path $resolvedUnityExecutable -Phase 'EXTERNAL_WHILE_AUTHORIZED_PID_ALIVE'
    $unityProcess.Refresh()
    Require-Condition (-not $unityProcess.HasExited) 'Unity exited during the live external fingerprint window.'
    Require-Condition (Test-ExternalFingerprintAgainstTrustedRule -Fingerprint $liveFingerprint -TrustedRule $trustedRule) 'Live external fingerprint does not satisfy the trusted rule.'
    Write-JsonExclusive -Path (Join-Path $stageRoot 'external-live-fingerprint.v1.json') -Value $liveFingerprint

    while (-not $unityProcess.HasExited) {
        Start-Sleep -Milliseconds 250
        $unityProcess.Refresh()
    }
    $unityExitCode = $unityProcess.ExitCode
    $exitedAtUtc = [DateTime]::UtcNow.ToString('o')
    Write-Output "Unity exited naturally; pid=$unityProcessId; exitCode=$unityExitCode."
    Require-Condition ($unityExitCode -eq 0) "Unity schema self-check exited nonzero: $unityExitCode"
    Require-Condition (Test-Path -LiteralPath $unityReceiptPath -PathType Leaf) 'Unity terminal schema self-check receipt is missing.'
    $unityReceipt = Get-Content -LiteralPath $unityReceiptPath -Raw -Encoding UTF8 | ConvertFrom-Json -Depth 100

    $postExitFingerprint = Get-ExternalFingerprint -Path $resolvedUnityExecutable -Phase 'EXTERNAL_POST_EXIT'
    Require-Condition (Test-ExternalFingerprintAgainstTrustedRule -Fingerprint $postExitFingerprint -TrustedRule $trustedRule) 'Post-exit external fingerprint does not satisfy the trusted rule.'
    Write-JsonExclusive -Path (Join-Path $stageRoot 'external-post-exit-fingerprint.v1.json') -Value $postExitFingerprint

    $transientCleanup = @(Remove-IsolatedUnityTransientCaches -IsolatedProjectRoot $isolatedProjectRoot -AuthorizedStageRoot $stageRoot)
    $attempt001InventoryAfter = @(Get-FileInventory -Root $attempt001Root)
    $attempt001DigestAfter = Get-InventoryContentDigest -Inventory $attempt001InventoryAfter
    $attempt001Unchanged = $attempt001DigestAfter -eq $attempt001DigestBefore
    Write-JsonExclusive -Path (Join-Path $stageRoot 'attempt001-inventory.after.v1.json') -Value ([ordered]@{
        schema = 'gate14re-me-retained-schema-compatibility-attempt-inventory-v1'
        studyId = $studyId
        authorizationId = $authorizationId
        phase = 'AFTER_ATTEMPT_003_UNITY_INVOCATION'
        capturedAtUtc = [DateTime]::UtcNow.ToString('o')
        rootRelativePath = Get-ProjectRelativePath -Path $attempt001Root -Root $resolvedProjectRoot
        fileCount = $attempt001InventoryAfter.Count
        contentDigestSha256 = $attempt001DigestAfter
        exactlyMatchesBeforeInventory = $attempt001Unchanged
        files = $attempt001InventoryAfter
    })
    Require-Condition $attempt001Unchanged 'Attempt-001 evidence changed during attempt-003.'
    $attempt002InventoryAfter = @(Get-FileInventory -Root $attempt002Root)
    $attempt002DigestAfter = Get-InventoryContentDigest -Inventory $attempt002InventoryAfter
    $attempt002Unchanged = $attempt002DigestAfter -eq $attempt002DigestBefore
    Write-JsonExclusive -Path (Join-Path $stageRoot 'attempt002-inventory.after.v1.json') -Value ([ordered]@{
        schema = 'gate14re-me-retained-schema-compatibility-attempt-inventory-v1'
        studyId = $studyId
        authorizationId = $authorizationId
        phase = 'AFTER_ATTEMPT_003_UNITY_INVOCATION'
        capturedAtUtc = [DateTime]::UtcNow.ToString('o')
        rootRelativePath = Get-ProjectRelativePath -Path $attempt002Root -Root $resolvedProjectRoot
        fileCount = $attempt002InventoryAfter.Count
        contentDigestSha256 = $attempt002DigestAfter
        exactlyMatchesBeforeInventory = $attempt002Unchanged
        files = $attempt002InventoryAfter
    })
    Require-Condition $attempt002Unchanged 'Attempt-002 evidence changed during attempt-003.'

    $externalHashesStable = (Get-HashValue -Fingerprint $prelaunchFingerprint -Method 'powershell-get-filehash') -eq $expectedUnitySha256 -and
        (Get-HashValue -Fingerprint $liveFingerprint -Method 'powershell-get-filehash') -eq $expectedUnitySha256 -and
        (Get-HashValue -Fingerprint $postExitFingerprint -Method 'powershell-get-filehash') -eq $expectedUnitySha256
    $externalChunksStable = Compare-ChunkHashes -Left @($prelaunchFingerprint.chunkHashes) -Right @($liveFingerprint.chunkHashes)
    $externalChunksStable = $externalChunksStable -and (Compare-ChunkHashes -Left @($prelaunchFingerprint.chunkHashes) -Right @($postExitFingerprint.chunkHashes))
    $externalFileIdentityStable = [string]$prelaunchFingerprint.fileIdentity.fileIdHex -eq [string]$liveFingerprint.fileIdentity.fileIdHex -and
        [string]$prelaunchFingerprint.fileIdentity.fileIdHex -eq [string]$postExitFingerprint.fileIdentity.fileIdHex
    $externalPeStable = (Compare-PeIdentity -Left $prelaunchFingerprint.peIdentity -Right $liveFingerprint.peIdentity) -and
        (Compare-PeIdentity -Left $prelaunchFingerprint.peIdentity -Right $postExitFingerprint.peIdentity)
    $externalSignerStable = [string]$prelaunchFingerprint.authenticode.status -eq 'Valid' -and
        [string]$liveFingerprint.authenticode.status -eq 'Valid' -and [string]$postExitFingerprint.authenticode.status -eq 'Valid' -and
        [string]$prelaunchFingerprint.authenticode.signerThumbprint -eq [string]$liveFingerprint.authenticode.signerThumbprint -and
        [string]$prelaunchFingerprint.authenticode.signerThumbprint -eq [string]$postExitFingerprint.authenticode.signerThumbprint
    $externalMetadataStable = [int64]$prelaunchFingerprint.lengthBytes -eq [int64]$liveFingerprint.lengthBytes -and
        [int64]$prelaunchFingerprint.lengthBytes -eq [int64]$postExitFingerprint.lengthBytes -and
        [string]$prelaunchFingerprint.creationTimeUtc -eq [string]$liveFingerprint.creationTimeUtc -and
        [string]$prelaunchFingerprint.creationTimeUtc -eq [string]$postExitFingerprint.creationTimeUtc -and
        [string]$prelaunchFingerprint.lastWriteTimeUtc -eq [string]$liveFingerprint.lastWriteTimeUtc -and
        [string]$prelaunchFingerprint.lastWriteTimeUtc -eq [string]$postExitFingerprint.lastWriteTimeUtc -and
        (Compare-VersionMetadata -Left $prelaunchFingerprint.versionMetadata -Right $liveFingerprint.versionMetadata) -and
        (Compare-VersionMetadata -Left $prelaunchFingerprint.versionMetadata -Right $postExitFingerprint.versionMetadata)

    $processStartDeltaMilliseconds = [Math]::Abs((([DateTime]::Parse([string]$ready.process.processStartTimeUtc)).ToUniversalTime() -
        ([DateTime]::Parse($creationUtc)).ToUniversalTime()).TotalMilliseconds)
    $processPathsAgree = [bool]$ready.process.allExecutablePathsEqual -and
        (Test-PathsEqual -Left ([string]$ready.process.editorApplicationPath) -Right $resolvedUnityExecutable) -and
        (Test-PathsEqual -Left ([string]$ready.process.processMainModulePath) -Right $resolvedUnityExecutable) -and
        (Test-PathsEqual -Left ([string]$ready.process.queryFullProcessImageNamePath) -Right $resolvedUnityExecutable) -and
        (Test-PathsEqual -Left ([string]$unityProcessMetadata.ExecutablePath) -Right $resolvedUnityExecutable)
    $processCompositeIdentitySatisfied = [int]$ready.process.processId -eq $unityProcessId -and
        [int]$unityReceipt.initialProcessIdentity.processId -eq $unityProcessId -and
        [int]$unityReceipt.afterHoldProcessIdentity.processId -eq $unityProcessId -and
        $processStartDeltaMilliseconds -le 1000.0 -and $processPathsAgree -and
        [string]$ready.process.fileIdentity.fileIndexLow64Hex -eq [string]$trustedRule.applicability.ntfsFileIndexLow64Hex -and
        [string]$unityReceipt.afterHoldProcessIdentity.fileIdentity.fileIndexLow64Hex -eq [string]$trustedRule.applicability.ntfsFileIndexLow64Hex

    $schemaChecksPassed = $unityReceipt.schema -eq 'gate14re-me-input-schema-compatibility-unity-self-check-receipt-v2' -and
        $unityReceipt.studyId -eq $studyId -and $unityReceipt.authorizationId -eq $authorizationId -and
        $unityReceipt.status -eq 'PASS_INPUT_SCHEMA_COMPATIBILITY_UNITY_SELF_CHECK_ATTEMPT_003' -and
        $unityReceipt.passed -and $unityReceipt.terminal -and $unityReceipt.authorizationHeaderPassed -and
        $unityReceipt.trustedIdentityRuleHeaderPassed -and $unityReceipt.planningBindingHeaderPassed -and
        $unityReceipt.retainedSchemaKnownAnswerPassed -and $unityReceipt.sourceAndEvidenceBindingsPassed -and
        $unityReceipt.prohibitedRootsAbsentBefore -and $unityReceipt.prohibitedRootsAbsentAfter -and
        $unityReceipt.inProcessStructuralIdentityStableAcrossHold -and -not $unityReceipt.inProcessFileReadHashesAuthoritative -and
        $unityReceipt.reflectionTargetFound -and $unityReceipt.jsonUtilitySerializedTopology -and
        $unityReceipt.jsonUtilityRoundTripPreservedTopology -and $unityReceipt.positiveOracleHeaderPassed -and
        $unityReceipt.missingTopologyJsonControlConstructed -and $unityReceipt.missingTopologyOracleHeaderFailedAsExpected -and
        $unityReceipt.mismatchedTopologyJsonControlConstructed -and $unityReceipt.mismatchedTopologyOracleHeaderFailedAsExpected -and
        [string]$unityReceipt.missingTopologyObservedFailure -eq 'Event-group topology must match the input context.' -and
        [string]$unityReceipt.mismatchedTopologyObservedFailure -eq 'Event-group topology must match the input context.'
    $boundaryPassed = [int]$unityReceipt.schemaCompatibilitySelfCheckInvocations -eq 1 -and
        [int]$unityReceipt.scheduleRowsGenerated -eq 0 -and [int]$unityReceipt.qualificationInputsGenerated -eq 0 -and
        [int]$unityReceipt.anonymousIdentityMappingsGenerated -eq 0 -and -not $unityReceipt.qualificationMeasuredRootCreated -and
        [int]$unityReceipt.plannerInvocations -eq 0 -and [int]$unityReceipt.algorithmLaneExecutions -eq 0 -and
        -not $unityReceipt.formalCollectionPerformed -and -not $unityReceipt.formalAnalysisPerformed -and
        -not $unityReceipt.algorithmRankingPerformed -and -not $unityReceipt.winnerAdjudicationPerformed

    $remainingUnity = @(Get-CimInstance Win32_Process | Where-Object { $_.Name -eq 'Unity.exe' })
    $remainingProhibited = @(Get-ActiveGate14ReMEExecutionProcesses)
    $prohibitedRootsAfter = @(Get-ProhibitedRootsPresent -Root $resolvedProjectRoot)
    $trustedLaunchIdentityPassed = $externalHashesStable -and $externalChunksStable -and $externalFileIdentityStable -and
        $externalPeStable -and $externalSignerStable -and $externalMetadataStable -and $processCompositeIdentitySatisfied -and
        [bool]$unityReceipt.inProcessStructuralIdentityStableAcrossHold -and $unityExitCode -eq 0
    $allPassed = $trustedLaunchIdentityPassed -and $schemaChecksPassed -and $boundaryPassed -and $attempt001Unchanged -and $attempt002Unchanged -and
        $unityInvocationCount -eq 1 -and $remainingUnity.Count -eq 0 -and $remainingProhibited.Count -eq 0 -and $prohibitedRootsAfter.Count -eq 0
    Require-Condition $allPassed 'One or more authoritative identity, schema, boundary, or retained-evidence checks failed.'

    $adjudication = [ordered]@{
        schema = 'gate14re-me-input-schema-compatibility-attempt-003-adjudication-v1'
        studyId = $studyId
        authorizationId = $authorizationId
        status = 'PASS_SCHEMA_COMPATIBILITY_AND_TRUSTED_LAUNCH_IDENTITY'
        completedAtUtc = [DateTime]::UtcNow.ToString('o')
        unityInvocation = [ordered]@{
            count = $unityInvocationCount
            processId = $unityProcessId
            creationTimeUtc = $creationUtc
            launchedAtUtc = $launchedAtUtc
            exitedAtUtc = $exitedAtUtc
            exitCode = $unityExitCode
            executeMethod = $executeMethod
            retryPerformed = $false
            signalOrForcedTerminationSent = $false
        }
        trustedLaunchIdentity = [ordered]@{
            passed = $trustedLaunchIdentityPassed
            externalExpectedSha256AtAllThreePhases = $externalHashesStable
            external64KiBChunksStableAtAllThreePhases = $externalChunksStable
            externalFileIdentityStableAtAllThreePhases = $externalFileIdentityStable
            externalPeIdentityStableAtAllThreePhases = $externalPeStable
            externalAuthenticodeSignerStableAtAllThreePhases = $externalSignerStable
            externalMetadataStableAtAllThreePhases = $externalMetadataStable
            processCompositeIdentitySatisfied = $processCompositeIdentitySatisfied
            processStartDeltaMilliseconds = $processStartDeltaMilliseconds
            inProcessStructuralIdentityStableAcrossHold = [bool]$unityReceipt.inProcessStructuralIdentityStableAcrossHold
            inProcessFileReadHashesAuthoritative = $false
            naturalExitAndPostExitReconfirmationPassed = ($unityExitCode -eq 0)
        }
        schemaCompatibility = [ordered]@{
            passed = $schemaChecksPassed
            jsonUtilitySerializedTopology = [bool]$unityReceipt.jsonUtilitySerializedTopology
            jsonUtilityRoundTripPreservedTopology = [bool]$unityReceipt.jsonUtilityRoundTripPreservedTopology
            actualValidateGroupHeaderReflectionTargetFound = [bool]$unityReceipt.reflectionTargetFound
            matchingTopologyPassed = [bool]$unityReceipt.positiveOracleHeaderPassed
            missingTopologyFailedAsExpected = [bool]$unityReceipt.missingTopologyOracleHeaderFailedAsExpected
            mismatchedTopologyFailedAsExpected = [bool]$unityReceipt.mismatchedTopologyOracleHeaderFailedAsExpected
            expectedFailure = 'Event-group topology must match the input context.'
            missingTopologyObservedFailure = [string]$unityReceipt.missingTopologyObservedFailure
            mismatchedTopologyObservedFailure = [string]$unityReceipt.mismatchedTopologyObservedFailure
        }
        retainedAttempt001 = [ordered]@{
            beforeFileCount = $attempt001InventoryBefore.Count
            afterFileCount = $attempt001InventoryAfter.Count
            beforeContentDigestSha256 = $attempt001DigestBefore
            afterContentDigestSha256 = $attempt001DigestAfter
            unchanged = $attempt001Unchanged
            originalFailureStatusRetained = $true
            reclassified = $false
        }
        retainedAttempt002 = [ordered]@{
            beforeFileCount = $attempt002InventoryBefore.Count
            afterFileCount = $attempt002InventoryAfter.Count
            beforeContentDigestSha256 = $attempt002DigestBefore
            afterContentDigestSha256 = $attempt002DigestAfter
            unchanged = $attempt002Unchanged
            originalFailureStatusRetained = $true
            reclassified = $false
        }
        scientificBoundary = [ordered]@{
            schemaCompatibilitySelfCheckInvocations = 1
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
            transientIsolatedUnityCachesRemoved = $transientCleanup
        }
    }
    $adjudicationPath = Join-Path $stageRoot 'adjudication.v1.json'
    Write-JsonExclusive -Path $adjudicationPath -Value $adjudication

    $terminalReceipt = [ordered]@{
        schema = 'gate14re-me-input-schema-compatibility-corrigendum-attempt-003-terminal-receipt-v1'
        studyId = $studyId
        authorizationId = $authorizationId
        status = 'PASS_INPUT_SCHEMA_V2_AND_PLANNING_BINDING_V2_ADOPTED'
        completedAtUtc = [DateTime]::UtcNow.ToString('o')
        passed = $true
        terminal = $true
        unityInvocationCount = 1
        automaticRetryPerformed = $false
        attempt001RetainedUnchanged = $true
        attempt002RetainedUnchanged = $true
        trustedLaunchIdentityPassed = $true
        unitySchemaCompatibilityPassed = $true
        inputSchemaV2 = [ordered]@{
            relativePath = 'Research/Gate14Re-ME/Execution/v2/load-qualification-input-schema.v2.json'
            sha256 = '1054fd12e2cecc5c74f985f4739c888aaa0550dec23136b5237c87040b6fd117'
            adopted = $true
        }
        planningSchemaBindingV2 = [ordered]@{
            relativePath = 'Research/Gate14Re-ME/Execution/v2/load-qualification-planning-schema-binding.v2.json'
            sha256 = 'abbc8965a58d4ade2696ace3a0d7af47f48d92260540f589b9dc7af1b880d5e7'
            adopted = $true
        }
        adjudication = [ordered]@{
            relativePath = Get-ProjectRelativePath -Path $adjudicationPath -Root $resolvedProjectRoot
            sha256 = Get-Sha256Lower -Path $adjudicationPath
        }
        scientificBoundary = $adjudication.scientificBoundary
        nextAuthorizationRequired = 'A new separate authorization is required before qualification schedule/input/anonymous-map generation, measured-root creation, planner or algorithm-lane execution, formal collection, analysis, ranking or winner adjudication.'
    }
    $terminalReceiptPath = Join-Path $stageRoot 'terminal-receipt.v1.json'
    Write-JsonExclusive -Path $terminalReceiptPath -Value $terminalReceipt

    $statusV19 = [ordered]@{
        schema = 'gate14re-me-status-v19'
        studyId = $studyId
        status = 'INPUT_SCHEMA_V2_UNITY_COMPATIBILITY_FROZEN_PASS_PLANNING_BINDING_V2_ADOPTED'
        version = 19
        updatedAtUtc = [DateTime]::UtcNow.ToString('o')
        previousVersionedStatus = [ordered]@{
            relativePath = 'Research/Gate14Re-ME/Gate14Re_ME_Status.v18.json'
            lengthBytes = (Get-Item -LiteralPath $parentStatusPath).Length
            sha256 = Get-Sha256Lower -Path $parentStatusPath
            retained = $true
        }
        schemaCompatibilityCorrigendumAttempt001 = [ordered]@{
            status = 'FAILED_CLOSED_RETAINED_UNCHANGED'
            evidenceFileCount = $attempt001InventoryAfter.Count
            evidenceContentDigestSha256 = $attempt001DigestAfter
            reclassified = $false
        }
        schemaCompatibilityCorrigendumAttempt002 = [ordered]@{
            status = 'FAILED_CLOSED_RETAINED_UNCHANGED'
            evidenceFileCount = $attempt002InventoryAfter.Count
            evidenceContentDigestSha256 = $attempt002DigestAfter
            reclassified = $false
        }
        schemaCompatibilityCorrigendumAttempt003 = [ordered]@{
            authorizationId = $authorizationId
            status = $terminalReceipt.status
            unityInvocationCount = 1
            retryPerformed = $false
            trustedLaunchIdentityRuleSha256 = $expectedTrustedRuleSha256
            terminalReceiptRelativePath = Get-ProjectRelativePath -Path $terminalReceiptPath -Root $resolvedProjectRoot
            terminalReceiptSha256 = Get-Sha256Lower -Path $terminalReceiptPath
            inputSchemaV2Adopted = $true
            planningSchemaBindingV2Adopted = $true
        }
        activeQualificationInputValidationSchema = [ordered]@{
            relativePath = 'Research/Gate14Re-ME/Execution/v2/load-qualification-input-schema.v2.json'
            sha256 = '1054fd12e2cecc5c74f985f4739c888aaa0550dec23136b5237c87040b6fd117'
        }
        activeQualificationPlanningSchemaBinding = [ordered]@{
            relativePath = 'Research/Gate14Re-ME/Execution/v2/load-qualification-planning-schema-binding.v2.json'
            sha256 = 'abbc8965a58d4ade2696ace3a0d7af47f48d92260540f589b9dc7af1b880d5e7'
        }
        scientificBoundary = $adjudication.scientificBoundary
        authorizationState = [ordered]@{
            schemaCompatibilityAttempt003AuthorizationConsumed = $true
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
        nextRequiredAction = 'Separately authorize the qualification-planning freeze attempt-003. This status does not authorize schedule/input/anonymous-map generation or any Unity algorithm execution.'
    }
    Write-JsonExclusive -Path $nextStatusPath -Value $statusV19

    $evidenceFiles = @(Get-ChildItem -LiteralPath $stageRoot -Recurse -Force -File | Where-Object { $_.FullName -ne $finalManifestPath } | Sort-Object FullName | ForEach-Object {
        [ordered]@{
            relativePath = Get-ProjectRelativePath -Path $_.FullName -Root $resolvedProjectRoot
            lengthBytes = [int64]$_.Length
            sha256 = Get-Sha256Lower -Path $_.FullName
        }
    })
    Write-JsonExclusive -Path $finalManifestPath -Value ([ordered]@{
        schema = 'gate14re-me-input-schema-compatibility-attempt-003-evidence-freeze-manifest-v1'
        studyId = $studyId
        authorizationId = $authorizationId
        status = 'FROZEN_TERMINAL_PASS_EVIDENCE'
        frozenAtUtc = [DateTime]::UtcNow.ToString('o')
        sourceFreezeManifest = [ordered]@{
            relativePath = Get-ProjectRelativePath -Path $resolvedSourceFreezeManifest -Root $resolvedProjectRoot
            sha256 = $SourceFreezeManifestSha256
        }
        statusV19 = [ordered]@{
            relativePath = Get-ProjectRelativePath -Path $nextStatusPath -Root $resolvedProjectRoot
            sha256 = Get-Sha256Lower -Path $nextStatusPath
        }
        evidenceFiles = $evidenceFiles
    })
    foreach ($file in @(Get-ChildItem -LiteralPath $stageRoot -Recurse -Force -File)) { Set-ReadOnlyFile -Path $file.FullName }
    Set-ReadOnlyFile -Path $nextStatusPath
    $stagePassed = $true
    Write-Output ($terminalReceipt | ConvertTo-Json -Depth 100 -Compress)
}
catch {
    $stagePassed = $false
    $exactFailure = $_.Exception.Message
    $exceptionType = $_.Exception.GetType().FullName
    $stackTrace = $_.ScriptStackTrace

    if ($null -ne $unityProcess) {
        try {
            $unityProcess.Refresh()
            while (-not $unityProcess.HasExited) {
                Write-Output "Fail-closed condition recorded; waiting for authorized Unity PID $($unityProcess.Id) to exit naturally. No signal or retry."
                Start-Sleep -Seconds 5
                $unityProcess.Refresh()
            }
            $unityExitCode = $unityProcess.ExitCode
        }
        catch { }
    }

    if ($null -ne $unityProcess -and $unityProcess.HasExited -and $null -eq $postExitFingerprint) {
        try {
            $postExitFingerprint = Get-ExternalFingerprint -Path $resolvedUnityExecutable -Phase 'EXTERNAL_POST_EXIT_AFTER_FAILURE'
            $postFailurePath = Join-Path $stageRoot 'external-post-exit-fingerprint.after-failure.v1.json'
            if (-not (Test-Path -LiteralPath $postFailurePath)) { Write-JsonExclusive -Path $postFailurePath -Value $postExitFingerprint }
        }
        catch { }
    }

    try {
        if (Test-Path -LiteralPath $isolatedProjectRoot -PathType Container) {
            $transientCleanup = @(Remove-IsolatedUnityTransientCaches -IsolatedProjectRoot $isolatedProjectRoot -AuthorizedStageRoot $stageRoot)
        }
    }
    catch { }

    try {
        $attempt001InventoryAfter = @(Get-FileInventory -Root $attempt001Root)
        $attempt001DigestAfter = Get-InventoryContentDigest -Inventory $attempt001InventoryAfter
    }
    catch { }
    $attempt001UnchangedAfterFailure = $null -ne $attempt001DigestBefore -and $attempt001DigestAfter -eq $attempt001DigestBefore
    try {
        $attempt002InventoryAfter = @(Get-FileInventory -Root $attempt002Root)
        $attempt002DigestAfter = Get-InventoryContentDigest -Inventory $attempt002InventoryAfter
    }
    catch { }
    $attempt002UnchangedAfterFailure = $null -ne $attempt002DigestBefore -and $attempt002DigestAfter -eq $attempt002DigestBefore

    $failureReceiptPath = Join-Path $stageRoot 'failure-receipt.v1.json'
    if (-not (Test-Path -LiteralPath $failureReceiptPath)) {
        Write-JsonExclusive -Path $failureReceiptPath -Value ([ordered]@{
            schema = 'gate14re-me-input-schema-compatibility-attempt-003-failure-receipt-v1'
            studyId = $studyId
            authorizationId = $authorizationId
            status = 'FAILED_CLOSED_INPUT_SCHEMA_COMPATIBILITY_ATTEMPT_003'
            failedAtUtc = [DateTime]::UtcNow.ToString('o')
            exceptionType = $exceptionType
            exactFailure = $exactFailure
            stackTrace = $stackTrace
            unityInvocationCount = $unityInvocationCount
            unityExitCode = $unityExitCode
            retryPerformed = $false
            signalOrForcedTerminationSent = $false
            attempt001Evidence = [ordered]@{
                beforeContentDigestSha256 = $attempt001DigestBefore
                afterContentDigestSha256 = $attempt001DigestAfter
                unchanged = $attempt001UnchangedAfterFailure
                reclassified = $false
            }
            attempt002Evidence = [ordered]@{
                beforeContentDigestSha256 = $attempt002DigestBefore
                afterContentDigestSha256 = $attempt002DigestAfter
                unchanged = $attempt002UnchangedAfterFailure
                reclassified = $false
            }
            candidateAdoption = [ordered]@{
                inputSchemaV2Adopted = $false
                planningSchemaBindingV2Adopted = $false
            }
            scientificBoundary = [ordered]@{
                schemaCompatibilitySelfCheckInvocations = $unityInvocationCount
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
                transientIsolatedUnityCachesRemoved = $transientCleanup
            }
        })
    }

    if (-not (Test-Path -LiteralPath $nextStatusPath)) {
        Write-JsonExclusive -Path $nextStatusPath -Value ([ordered]@{
            schema = 'gate14re-me-status-v19'
            studyId = $studyId
            status = 'INPUT_SCHEMA_COMPATIBILITY_ATTEMPT_003_FAILED_CLOSED'
            version = 19
            updatedAtUtc = [DateTime]::UtcNow.ToString('o')
            previousVersionedStatus = [ordered]@{
                relativePath = 'Research/Gate14Re-ME/Gate14Re_ME_Status.v18.json'
                sha256 = $(if (Test-Path -LiteralPath $parentStatusPath) { Get-Sha256Lower -Path $parentStatusPath } else { $null })
                retained = $true
            }
            schemaCompatibilityAttempt003 = [ordered]@{
                authorizationId = $authorizationId
                passed = $false
                failureReceiptRelativePath = Get-ProjectRelativePath -Path $failureReceiptPath -Root $resolvedProjectRoot
                failureReceiptSha256 = Get-Sha256Lower -Path $failureReceiptPath
                inputSchemaV2Adopted = $false
                planningSchemaBindingV2Adopted = $false
                retryPerformed = $false
            }
            scientificBoundary = [ordered]@{
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
            nextRequiredAction = 'A new separate authorization is required. Do not retry or generate qualification planning assets.'
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
            schema = 'gate14re-me-input-schema-compatibility-attempt-003-evidence-freeze-manifest-v1'
            studyId = $studyId
            authorizationId = $authorizationId
            status = 'FROZEN_TERMINAL_FAILURE_EVIDENCE'
            frozenAtUtc = [DateTime]::UtcNow.ToString('o')
            statusV19 = [ordered]@{
                relativePath = Get-ProjectRelativePath -Path $nextStatusPath -Root $resolvedProjectRoot
                sha256 = Get-Sha256Lower -Path $nextStatusPath
            }
            evidenceFiles = $failureEvidenceFiles
        })
    }

    foreach ($file in @(Get-ChildItem -LiteralPath $stageRoot -Recurse -Force -File)) { Set-ReadOnlyFile -Path $file.FullName }
    Set-ReadOnlyFile -Path $nextStatusPath
    Write-Error "Gate14Re-ME schema compatibility attempt-003 failed closed: $exactFailure"
    exit 1
}

if (-not $stagePassed) { exit 1 }
