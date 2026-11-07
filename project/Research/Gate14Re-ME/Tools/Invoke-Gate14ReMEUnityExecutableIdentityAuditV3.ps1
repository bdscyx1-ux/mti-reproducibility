[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ProjectRoot,

    [Parameter(Mandatory = $true)]
    [string]$UnityExecutable,

    [Parameter(Mandatory = $true)]
    [string]$FreezeManifest,

    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[0-9a-f]{64}$')]
    [string]$FreezeManifestSha256
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$studyId = 'Gate14Re-ME'
$authorizationId = 'gate14re-me-unity-executable-identity-discrepancy-audit-attempt-003'
$executeMethod = 'DDM.Research.Editor.UnityExecutableIdentityAuditAttempt001.Gate14ReMEUnityExecutableIdentityAuditV1.Run'
$expectedUnitySha256 = '0a69d14cbe2ca82d0a6168da8156d9e0dd138a6b7d0260dcdea31fd3957ca9cf'
$priorInProcessSha256 = 'ad243c5b18041d674874864cea86626623ff366a6363aede529fec923e80579e'
$chunkSizeBytes = 65536
$unityInvocationCount = 0
$unityProcess = $null
$unityProcessMetadata = $null
$stageRootCreated = $false
$stagePassed = $false
$exactFailure = $null
$exceptionType = $null
$stackTrace = $null
$classification = 'NOT_ADJUDICATED'
$transientCleanup = @()

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
    try {
        $digest = $sha.ComputeHash($stream)
        return [Convert]::ToHexString($digest).ToLowerInvariant()
    }
    finally {
        $stream.Dispose()
        $sha.Dispose()
    }
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

function Write-TextExclusive {
    param([string]$Path, [string]$Value)
    Require-Condition (-not (Test-Path -LiteralPath $Path)) "Refusing to overwrite file: $Path"
    $encoding = [System.Text.UTF8Encoding]::new($false)
    $stream = [System.IO.File]::Open($Path, [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
    try {
        $writer = [System.IO.StreamWriter]::new($stream, $encoding)
        try { $writer.Write($Value); $writer.Flush() }
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
    $result = [System.Collections.Generic.List[object]]::new()
    foreach ($item in @(Get-ChildItem -LiteralPath $Root -Recurse -Force -File | Sort-Object FullName)) {
        $result.Add([pscustomobject][ordered]@{
            relativePath = Get-ProjectRelativePath -Path $item.FullName -Root $Root
            lengthBytes = [int64]$item.Length
            sha256 = Get-Sha256Lower -Path $item.FullName
            attributes = $item.Attributes.ToString()
            creationTimeUtc = $item.CreationTimeUtc.ToString('o')
            lastWriteTimeUtc = $item.LastWriteTimeUtc.ToString('o')
        })
    }
    return @($result)
}

function Get-InventoryContentDigest {
    param([object[]]$Inventory)
    $canonical = @($Inventory | ForEach-Object {
        [ordered]@{
            relativePath = [string]$_.relativePath
            lengthBytes = [int64]$_.lengthBytes
            sha256 = [string]$_.sha256
            attributes = [string]$_.attributes
            creationTimeUtc = [string]$_.creationTimeUtc
            lastWriteTimeUtc = [string]$_.lastWriteTimeUtc
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
    $hashMatches = @($Fingerprint.fullFileHashes | Where-Object { $_.method -eq $Method })
    Require-Condition ($hashMatches.Count -eq 1 -and $hashMatches[0].succeeded -and [string]$hashMatches[0].sha256 -match '^[0-9a-f]{64}$') "Missing or failed hash method: $Method"
    return [string]($hashMatches[0].sha256)
}

function Test-PathsEqual {
    param([string]$Left, [string]$Right)
    if ([string]::IsNullOrWhiteSpace($Left) -or [string]::IsNullOrWhiteSpace($Right)) { return $false }
    return [System.IO.Path]::GetFullPath($Left).TrimEnd('\') -ieq [System.IO.Path]::GetFullPath($Right).TrimEnd('\')
}

function Compare-ChunkHashes {
    param([object[]]$InternalChunks, [object[]]$ExternalChunks)
    $mismatches = [System.Collections.Generic.List[object]]::new()
    $maximum = [Math]::Max($InternalChunks.Count, $ExternalChunks.Count)
    for ($index = 0; $index -lt $maximum; $index++) {
        $inside = if ($index -lt $InternalChunks.Count) { $InternalChunks[$index] } else { $null }
        $outside = if ($index -lt $ExternalChunks.Count) { $ExternalChunks[$index] } else { $null }
        $same = $null -ne $inside -and $null -ne $outside -and
            [int]$inside.chunkIndex -eq [int]$outside.chunkIndex -and
            [int64]$inside.offsetBytes -eq [int64]$outside.offsetBytes -and
            [int]$inside.lengthBytes -eq [int]$outside.lengthBytes -and
            [string]$inside.sha256 -eq [string]$outside.sha256
        if (-not $same) {
            $mismatches.Add([pscustomobject][ordered]@{
                chunkIndex = $index
                offsetBytes = $(if ($null -ne $inside) { [int64]$inside.offsetBytes } elseif ($null -ne $outside) { [int64]$outside.offsetBytes } else { $null })
                internalLengthBytes = $(if ($null -ne $inside) { [int]$inside.lengthBytes } else { $null })
                externalLengthBytes = $(if ($null -ne $outside) { [int]$outside.lengthBytes } else { $null })
                internalSha256 = $(if ($null -ne $inside) { [string]$inside.sha256 } else { $null })
                externalSha256 = $(if ($null -ne $outside) { [string]$outside.sha256 } else { $null })
            })
        }
    }
    return @($mismatches)
}

function Get-ProhibitedRootsPresent {
    param([string]$Root)
    $relativeRoots = @(
        'Research/PilotRuns/Gate14Re-ME',
        'Research/FormalRuns/Gate14Re-ME',
        'Research/QualificationRuns/Gate14Re-ME',
        'Research/MeasuredRuns/Gate14Re-ME'
    )
    $present = [System.Collections.Generic.List[string]]::new()
    foreach ($relative in $relativeRoots) {
        $full = Join-Path $Root $relative
        if (Test-Path -LiteralPath $full) { $present.Add($relative) }
    }
    return @($present)
}

function Get-ActiveProhibitedProcesses {
    $all = @(Get-CimInstance Win32_Process | Where-Object { $_.Name -eq 'Unity.exe' })
    return @($all | Where-Object {
        $_.CommandLine -match 'Gate14ReME(InputSchemaCompatibilitySelfCheck|LoadQualificationRunner|QualificationPlanner|ReferenceOracle)' -or
        $_.CommandLine -match 'Research[/\\](PilotRuns|FormalRuns|QualificationRuns|MeasuredRuns)[/\\]Gate14Re-ME'
    })
}

function Remove-IsolatedUnityTransientCaches {
    param([string]$AuditProjectRoot, [string]$AuthorizedStageRoot)
    $resolvedProject = [System.IO.Path]::GetFullPath($AuditProjectRoot).TrimEnd('\')
    $resolvedStage = [System.IO.Path]::GetFullPath($AuthorizedStageRoot).TrimEnd('\')
    $stagePrefix = $resolvedStage + [System.IO.Path]::DirectorySeparatorChar
    Require-Condition $resolvedProject.StartsWith($stagePrefix, [System.StringComparison]::OrdinalIgnoreCase) 'Isolated audit project is outside the authorized stage root.'
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
    if (Test-Path -LiteralPath $Path -PathType Leaf) {
        $item = Get-Item -LiteralPath $Path -Force
        $item.IsReadOnly = $true
    }
}

$resolvedProjectRoot = Get-NormalizedFullPath -Path $ProjectRoot -Base (Get-Location).Path
$expectedProjectRoot = [System.IO.Path]::GetFullPath('H:\DDM_Final_Project').TrimEnd('\')
Require-Condition ($resolvedProjectRoot -ieq $expectedProjectRoot) 'Project root is not the authorized Gate14Re-ME project root.'

$resolvedUnityExecutable = Get-NormalizedFullPath -Path $UnityExecutable -Base $resolvedProjectRoot
$expectedUnityPath = [System.IO.Path]::GetFullPath('H:\UnityEditor\2022.3.30f1c1\Editor\Unity.exe')
Require-Condition ($resolvedUnityExecutable -ieq $expectedUnityPath) 'Unity executable path is not the authorized path.'

$resolvedFreezeManifest = Get-NormalizedFullPath -Path $FreezeManifest -Base $resolvedProjectRoot
Require-Condition ((Get-Sha256Lower -Path $resolvedFreezeManifest) -eq $FreezeManifestSha256) 'Source freeze manifest SHA-256 mismatch.'
$freeze = Get-Content -LiteralPath $resolvedFreezeManifest -Raw -Encoding UTF8 | ConvertFrom-Json -Depth 100
Require-Condition ($freeze.schema -eq 'gate14re-me-unity-executable-identity-audit-source-freeze-manifest-v1' -and
    $freeze.studyId -eq $studyId -and $freeze.authorizationId -eq $authorizationId -and
    $freeze.status -eq 'FROZEN_PREEXECUTION_IDENTITY_AUDIT_SOURCES') 'Source freeze manifest header mismatch.'

foreach ($binding in @($freeze.bindings)) {
    $full = Get-NormalizedFullPath -Path ([string]$binding.relativePath) -Base $resolvedProjectRoot
    $projectPrefix = $resolvedProjectRoot + [System.IO.Path]::DirectorySeparatorChar
    Require-Condition $full.StartsWith($projectPrefix, [System.StringComparison]::OrdinalIgnoreCase) "Bound file escaped project root: $($binding.relativePath)"
    Require-Condition (Test-Path -LiteralPath $full -PathType Leaf) "Bound file is missing: $($binding.relativePath)"
    Require-Condition ((Get-Sha256Lower -Path $full) -eq [string]$binding.sha256) "Bound file SHA-256 mismatch: $($binding.relativePath)"
    Require-Condition ((Get-Item -LiteralPath $full).Length -eq [int64]$binding.lengthBytes) "Bound file length mismatch: $($binding.relativePath)"
}

$authorizationPath = Join-Path $resolvedProjectRoot 'Research/Gate14Re-ME/Gate14Re_ME_Unity_Executable_Identity_Discrepancy_Audit_Attempt_003_Authorization.v1.json'
$planPath = Join-Path $resolvedProjectRoot 'Research/Gate14Re-ME/Gate14Re_ME_Unity_Executable_Identity_Discrepancy_Audit_Attempt_003_Plan.v1.md'
$probeSourcePath = Join-Path $resolvedProjectRoot 'Research/Gate14Re-ME/Tools/Gate14ReMEUnityExecutableIdentityAuditV3.cs'
$toolPath = [System.IO.Path]::GetFullPath($MyInvocation.MyCommand.Path)
$statusV14Path = Join-Path $resolvedProjectRoot 'Research/Gate14Re-ME/Gate14Re_ME_Status.v14.json'
$statusV15Path = Join-Path $resolvedProjectRoot 'Research/Gate14Re-ME/Gate14Re_ME_Status.v15.json'
$priorAttemptRoot = Join-Path $resolvedProjectRoot 'Research/Verification/Gate14Re-ME/qualification-input-schema-compatibility-corrigendum-attempt-001'
$stageRoot = Join-Path $resolvedProjectRoot 'Research/Verification/Gate14Re-ME/unity-executable-identity-discrepancy-audit-attempt-003'
$auditProjectRoot = Join-Path $stageRoot 'isolated-unity-audit-project'
$unityOutputRoot = Join-Path $stageRoot 'unity-output'
$unityLogPath = Join-Path $stageRoot 'unity-identity-probe.log'
$readyPath = Join-Path $unityOutputRoot 'in-process-ready-snapshot.v1.json'
$unityReceiptPath = Join-Path $unityOutputRoot 'unity-identity-probe-receipt.v1.json'

Require-Condition (-not (Test-Path -LiteralPath $stageRoot)) 'Identity-audit evidence root already exists; overwrite or retry is prohibited.'
Require-Condition (-not (Test-Path -LiteralPath $statusV15Path)) 'Status v15 already exists; overwrite is prohibited.'
Require-Condition ((Get-Sha256Lower -Path $resolvedUnityExecutable) -eq $expectedUnitySha256) 'External preflight Unity SHA-256 mismatch.'
Require-Condition (@(Get-CimInstance Win32_Process | Where-Object { $_.Name -eq 'Unity.exe' }).Count -eq 0) 'A Unity process is already active; isolated identity attribution is unavailable.'
Require-Condition (@(Get-ActiveProhibitedProcesses).Count -eq 0) 'A prohibited Gate14Re-ME Unity process is active.'
Require-Condition (@(Get-ProhibitedRootsPresent -Root $resolvedProjectRoot).Count -eq 0) 'A prohibited Gate14Re-ME measured root already exists.'

$priorInventoryBefore = @(Get-FileInventory -Root $priorAttemptRoot)
$priorInventoryDigestBefore = Get-InventoryContentDigest -Inventory $priorInventoryBefore

try {
    New-DirectoryExclusive -Path $stageRoot
    $stageRootCreated = $true
    Write-JsonExclusive -Path (Join-Path $stageRoot 'prior-attempt-inventory.before.v1.json') -Value ([ordered]@{
        schema = 'gate14re-me-prior-corrigendum-attempt-evidence-inventory-v1'
        studyId = $studyId
        authorizationId = $authorizationId
        phase = 'BEFORE_IDENTITY_AUDIT'
        capturedAtUtc = [DateTime]::UtcNow.ToString('o')
        rootRelativePath = Get-ProjectRelativePath -Path $priorAttemptRoot -Root $resolvedProjectRoot
        fileCount = $priorInventoryBefore.Count
        contentDigestSha256 = $priorInventoryDigestBefore
        files = $priorInventoryBefore
    })

    $prelaunchFingerprint = Get-ExternalFingerprint -Path $resolvedUnityExecutable -Phase 'EXTERNAL_PRELAUNCH'
    Require-Condition $prelaunchFingerprint.independentHashMethodsAgree 'External prelaunch hash methods disagree.'
    Require-Condition ((Get-HashValue -Fingerprint $prelaunchFingerprint -Method 'powershell-get-filehash') -eq $expectedUnitySha256) 'External prelaunch Unity hash differs from the frozen expected value.'
    Require-Condition (-not $prelaunchFingerprint.reparsePoint) 'Unity executable is a reparse point; direct file identity is not established.'
    Require-Condition $prelaunchFingerprint.fileIdentity.succeeded 'Unable to resolve the Unity executable file ID.'
    Require-Condition $prelaunchFingerprint.peIdentity.succeeded 'Unable to parse the Unity executable PE identity fields.'
    Require-Condition ($prelaunchFingerprint.authenticode.status -eq 'Valid') 'Unity Authenticode signature is not valid.'
    Write-JsonExclusive -Path (Join-Path $stageRoot 'external-prelaunch-fingerprint.v1.json') -Value $prelaunchFingerprint

    New-DirectoryExclusive -Path $auditProjectRoot
    $null = New-Item -ItemType Directory -Path (Join-Path $auditProjectRoot 'Assets/Editor')
    $null = New-Item -ItemType Directory -Path (Join-Path $auditProjectRoot 'ProjectSettings')
    $null = New-Item -ItemType Directory -Path (Join-Path $auditProjectRoot 'Packages')
    Copy-Item -LiteralPath $probeSourcePath -Destination (Join-Path $auditProjectRoot 'Assets/Editor/Gate14ReMEUnityExecutableIdentityAuditV1.cs')
    Require-Condition ((Get-Sha256Lower -Path (Join-Path $auditProjectRoot 'Assets/Editor/Gate14ReMEUnityExecutableIdentityAuditV1.cs')) -eq (Get-Sha256Lower -Path $probeSourcePath)) 'Isolated Unity probe source copy mismatch.'
    Write-TextExclusive -Path (Join-Path $auditProjectRoot 'ProjectSettings/ProjectVersion.txt') -Value "m_EditorVersion: 2022.3.30f1c1`nm_EditorVersionWithRevision: 2022.3.30f1c1 (a6dc00fbe362)`n"
    Write-TextExclusive -Path (Join-Path $auditProjectRoot 'Packages/manifest.json') -Value "{`n  `"dependencies`": {}`n}`n"

    $authorizationSha256 = Get-Sha256Lower -Path $authorizationPath
    $planSha256 = Get-Sha256Lower -Path $planPath
    $zeroStreamSha256 = [string]$freeze.zeroStreamKnownAnswer.sha256
    Require-Condition ([int64]$freeze.zeroStreamKnownAnswer.lengthBytes -eq [int64]$prelaunchFingerprint.lengthBytes) 'Zero-stream known-answer length is not bound to the Unity executable length.'
    Require-Condition ($zeroStreamSha256 -match '^[0-9a-f]{64}$') 'Zero-stream known-answer SHA-256 is invalid.'

    $unityArguments = @(
        '-batchmode', '-nographics', '-quit',
        '-projectPath', $auditProjectRoot,
        '-logFile', $unityLogPath,
        '-executeMethod', $executeMethod,
        '--g14me-source-project-root', $resolvedProjectRoot,
        '--g14me-identity-output-dir', $unityOutputRoot,
        '--g14me-hold-seconds', '30',
        '--g14me-authorized-unity-path', $resolvedUnityExecutable,
        '--g14me-authorized-unity-sha256', $expectedUnitySha256,
        '--g14me-zero-stream-sha256', $zeroStreamSha256,
        '--g14me-authorization', $authorizationPath,
        '--g14me-authorization-sha256', $authorizationSha256,
        '--g14me-plan', $planPath,
        '--g14me-plan-sha256', $planSha256,
        '--g14me-freeze-manifest', $resolvedFreezeManifest,
        '--g14me-freeze-manifest-sha256', $FreezeManifestSha256
    )

    Write-Output 'Launching exactly one isolated algorithm-free Unity identity probe.'
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
    Require-Condition (Test-PathsEqual -Left ([string]$unityProcessMetadata.ExecutablePath) -Right $resolvedUnityExecutable) 'Live process executable path differs from the authorized Unity path.'
    Require-Condition ($commandLine.Contains($executeMethod)) 'Live process command line lacks the authorized identity-probe execute method.'
    Require-Condition ($commandLine.Contains($auditProjectRoot)) 'Live process command line lacks the isolated audit project path.'
    Require-Condition (-not $commandLine.Contains('Gate14ReMEInputSchemaCompatibilitySelfCheckV1')) 'Prohibited schema-compatibility self-check appeared in the live process command line.'
    Require-Condition (-not ($commandLine -match 'Gate14ReMELoadQualificationRunner|Gate14ReMEQualificationPlanner|Gate14ReMEReferenceOracle')) 'A prohibited Gate14Re-ME execution method appeared in the live process command line.'

    Write-JsonExclusive -Path (Join-Path $stageRoot 'process-launch-receipt.v1.json') -Value ([ordered]@{
        schema = 'gate14re-me-unity-executable-identity-probe-launch-receipt-v1'
        studyId = $studyId
        authorizationId = $authorizationId
        status = 'ONE_ISOLATED_ALGORITHM_FREE_UNITY_IDENTITY_PROBE_LAUNCHED'
        launchedAtUtc = $launchedAtUtc
        invocationOrdinal = 1
        processId = $unityProcessId
        creationTimeUtc = $creationUtc
        executablePath = ([string]$unityProcessMetadata.ExecutablePath).Replace('\', '/')
        commandLine = $commandLine
        executeMethod = $executeMethod
        isolatedProjectRelativePath = Get-ProjectRelativePath -Path $auditProjectRoot -Root $resolvedProjectRoot
        schemaCompatibilitySelfCheckInvoked = $false
        retryAuthorized = $false
    })

    $nextProgressUtc = [DateTime]::UtcNow.AddSeconds(30)
    while (-not (Test-Path -LiteralPath $readyPath -PathType Leaf)) {
        $unityProcess.Refresh()
        if ($unityProcess.HasExited) { break }
        if ([DateTime]::UtcNow -ge $nextProgressUtc) {
            Write-Output "Unity identity probe is compiling/running; pid=$unityProcessId; no intervention or signal sent."
            $nextProgressUtc = [DateTime]::UtcNow.AddSeconds(30)
        }
        Start-Sleep -Milliseconds 250
    }
    Require-Condition (Test-Path -LiteralPath $readyPath -PathType Leaf) 'Unity exited before publishing the in-process ready snapshot.'
    $unityProcess.Refresh()
    Require-Condition (-not $unityProcess.HasExited) 'Unity exited before the concurrent external fingerprint could be taken.'

    $ready = Get-Content -LiteralPath $readyPath -Raw -Encoding UTF8 | ConvertFrom-Json -Depth 100
    Require-Condition ($ready.schema -eq 'gate14re-me-unity-executable-identity-ready-snapshot-v1' -and
        $ready.studyId -eq $studyId -and $ready.authorizationId -eq $authorizationId -and
        $ready.status -eq 'IN_PROCESS_IDENTITY_SNAPSHOT_READY') 'In-process ready snapshot header mismatch.'
    Require-Condition ([int]$ready.process.processId -eq $unityProcessId) 'In-process ready snapshot PID mismatch.'
    Require-Condition (-not $ready.schemaCompatibilitySelfCheckInvoked -and -not $ready.algorithmCodeLoadedByAuditProject) 'In-process boundary flags indicate prohibited code activity.'

    Write-Output 'In-process snapshot ready; taking the live external fingerprint while the same PID is held.'
    $concurrentFingerprint = Get-ExternalFingerprint -Path $resolvedUnityExecutable -Phase 'EXTERNAL_WHILE_AUTHORIZED_PID_ALIVE'
    $unityProcess.Refresh()
    Require-Condition (-not $unityProcess.HasExited) 'Unity exited during the concurrent external fingerprint window.'
    Write-JsonExclusive -Path (Join-Path $stageRoot 'external-concurrent-fingerprint.v1.json') -Value $concurrentFingerprint

    while (-not $unityProcess.HasExited) {
        Start-Sleep -Milliseconds 250
        $unityProcess.Refresh()
    }
    $unityExitCode = $unityProcess.ExitCode
    $exitedAtUtc = [DateTime]::UtcNow.ToString('o')
    Write-Output "Unity identity probe exited normally observable; pid=$unityProcessId; exitCode=$unityExitCode."

    Require-Condition (Test-Path -LiteralPath $unityReceiptPath -PathType Leaf) 'Unity terminal identity-probe receipt is missing.'
    $unityReceipt = Get-Content -LiteralPath $unityReceiptPath -Raw -Encoding UTF8 | ConvertFrom-Json -Depth 100
    Require-Condition ($unityExitCode -eq 0) "Unity identity probe exited nonzero: $unityExitCode"
    Require-Condition ($unityReceipt.status -eq 'PASS_ALGORITHM_FREE_UNITY_IDENTITY_PROBE_EXTERNAL_ADJUDICATION_PENDING' -and $unityReceipt.passed -and $unityReceipt.terminal) 'Unity identity-probe receipt is not a terminal internal pass.'
    Require-Condition ([int]$unityReceipt.process.processId -eq $unityProcessId) 'Unity receipt PID mismatch.'
    Require-Condition (-not $unityReceipt.schemaCompatibilitySelfCheckInvoked -and -not $unityReceipt.plannerInvoked -and -not $unityReceipt.algorithmLaneExecuted -and -not $unityReceipt.measuredRootCreated) 'Unity receipt reports prohibited activity.'

    $postExitFingerprint = Get-ExternalFingerprint -Path $resolvedUnityExecutable -Phase 'EXTERNAL_POST_EXIT'
    Write-JsonExclusive -Path (Join-Path $stageRoot 'external-post-exit-fingerprint.v1.json') -Value $postExitFingerprint

    $transientCleanup = @(Remove-IsolatedUnityTransientCaches -AuditProjectRoot $auditProjectRoot -AuthorizedStageRoot $stageRoot)

    $priorInventoryAfter = @(Get-FileInventory -Root $priorAttemptRoot)
    $priorInventoryDigestAfter = Get-InventoryContentDigest -Inventory $priorInventoryAfter
    $priorEvidenceUnchanged = $priorInventoryDigestBefore -eq $priorInventoryDigestAfter
    Write-JsonExclusive -Path (Join-Path $stageRoot 'prior-attempt-inventory.after.v1.json') -Value ([ordered]@{
        schema = 'gate14re-me-prior-corrigendum-attempt-evidence-inventory-v1'
        studyId = $studyId
        authorizationId = $authorizationId
        phase = 'AFTER_IDENTITY_AUDIT'
        capturedAtUtc = [DateTime]::UtcNow.ToString('o')
        rootRelativePath = Get-ProjectRelativePath -Path $priorAttemptRoot -Root $resolvedProjectRoot
        fileCount = $priorInventoryAfter.Count
        contentDigestSha256 = $priorInventoryDigestAfter
        exactlyMatchesBeforeInventory = $priorEvidenceUnchanged
        files = $priorInventoryAfter
    })
    Require-Condition $priorEvidenceUnchanged 'Prior schema-compatibility-corrigendum attempt-001 evidence changed during this audit.'

    $preHash = Get-HashValue -Fingerprint $prelaunchFingerprint -Method 'powershell-get-filehash'
    $concurrentHash = Get-HashValue -Fingerprint $concurrentFingerprint -Method 'powershell-get-filehash'
    $postHash = Get-HashValue -Fingerprint $postExitFingerprint -Method 'powershell-get-filehash'
    $externalHashesTrusted = $prelaunchFingerprint.independentHashMethodsAgree -and
        $concurrentFingerprint.independentHashMethodsAgree -and $postExitFingerprint.independentHashMethodsAgree -and
        $preHash -eq $expectedUnitySha256 -and $concurrentHash -eq $expectedUnitySha256 -and $postHash -eq $expectedUnitySha256

    $externalFileIdStable = [string]$prelaunchFingerprint.fileIdentity.fileIdHex -eq [string]$concurrentFingerprint.fileIdentity.fileIdHex -and
        [string]$prelaunchFingerprint.fileIdentity.fileIdHex -eq [string]$postExitFingerprint.fileIdentity.fileIdHex
    $inProcessFileId = [string]$ready.initialExecutableFingerprint.fileIdentity.fileIndexHex
    $inProcessMatchesExternalFileId = $inProcessFileId -eq [string]$concurrentFingerprint.fileIdentity.fileIndexLow64Hex
    $pathsAgree = $ready.process.allExecutablePathsEqual -and
        (Test-PathsEqual -Left ([string]$ready.process.editorApplicationPath) -Right $resolvedUnityExecutable) -and
        (Test-PathsEqual -Left ([string]$unityProcessMetadata.ExecutablePath) -Right $resolvedUnityExecutable)
    $metadataStable = [int64]$prelaunchFingerprint.lengthBytes -eq [int64]$concurrentFingerprint.lengthBytes -and
        [int64]$prelaunchFingerprint.lengthBytes -eq [int64]$postExitFingerprint.lengthBytes -and
        [string]$prelaunchFingerprint.creationTimeUtc -eq [string]$concurrentFingerprint.creationTimeUtc -and
        [string]$prelaunchFingerprint.creationTimeUtc -eq [string]$postExitFingerprint.creationTimeUtc -and
        [string]$prelaunchFingerprint.lastWriteTimeUtc -eq [string]$concurrentFingerprint.lastWriteTimeUtc -and
        [string]$prelaunchFingerprint.lastWriteTimeUtc -eq [string]$postExitFingerprint.lastWriteTimeUtc

    $internalInitialHashes = @($ready.initialExecutableFingerprint.fullFileHashes | Where-Object { $_.succeeded } | ForEach-Object { [string]$_.sha256 })
    $internalAfterHashes = @($unityReceipt.afterHoldExecutableFingerprint.fullFileHashes | Where-Object { $_.succeeded } | ForEach-Object { [string]$_.sha256 })
    $internalInitialUnique = @($internalInitialHashes | Sort-Object -Unique)
    $internalAfterUnique = @($internalAfterHashes | Sort-Object -Unique)
    $internalMethodsAgree = $internalInitialHashes.Count -eq 3 -and $internalAfterHashes.Count -eq 3 -and
        $internalInitialUnique.Count -eq 1 -and $internalAfterUnique.Count -eq 1 -and
        $internalInitialUnique[0] -eq $internalAfterUnique[0]
    $internalHash = $(if ($internalInitialUnique.Count -eq 1) { [string]$internalInitialUnique[0] } else { $null })
    $knownAnswersPassed = [bool]$ready.sha256KnownAnswers.allPassed -and [bool]$unityReceipt.sha256KnownAnswers.allPassed
    $chunkMismatches = @(Compare-ChunkHashes -InternalChunks @($ready.initialExecutableFingerprint.chunkHashes) -ExternalChunks @($concurrentFingerprint.chunkHashes))
    $discrepancyReproduced = $externalHashesTrusted -and $internalMethodsAgree -and $internalHash -ne $expectedUnitySha256
    $exactPriorMismatchReproduced = $discrepancyReproduced -and $internalHash -eq $priorInProcessSha256 -and
        [bool]$unityReceipt.priorMismatchHashReproducedInitially -and [bool]$unityReceipt.priorMismatchHashReproducedAfterHold

    if (-not $knownAnswersPassed) {
        $classification = 'IN_PROCESS_SHA256_IMPLEMENTATION_FAILED_KNOWN_ANSWERS'
    }
    elseif (-not $pathsAgree -or -not $externalFileIdStable -or -not $inProcessMatchesExternalFileId) {
        $classification = 'ALTERNATE_OR_UNSTABLE_EXECUTABLE_PATH_OR_FILE_ID'
    }
    elseif (-not $externalHashesTrusted -or -not $metadataStable) {
        $classification = 'EXTERNAL_EXECUTABLE_BYTES_OR_METADATA_CHANGED_DURING_RUN'
    }
    elseif (-not $internalMethodsAgree) {
        $classification = 'IN_PROCESS_HASH_METHOD_DISAGREEMENT'
    }
    elseif ($internalHash -eq $expectedUnitySha256) {
        $classification = 'PRIOR_DISCREPANCY_NOT_REPRODUCED'
    }
    elseif ($chunkMismatches.Count -gt 0) {
        $classification = 'PROCESS_LOCAL_EXECUTABLE_BYTE_READ_VIEW_DIFFERENCE'
    }
    else {
        $classification = 'IN_PROCESS_WHOLE_FILE_HASH_PATH_DIFFERENCE_WITH_EQUAL_CHUNKS'
    }

    $remainingUnity = @(Get-CimInstance Win32_Process | Where-Object { $_.Name -eq 'Unity.exe' })
    $remainingProhibited = @(Get-ActiveProhibitedProcesses)
    $prohibitedRootsAfter = @(Get-ProhibitedRootsPresent -Root $resolvedProjectRoot)
    $trustworthyRuleSupported = $classification -in @(
        'PROCESS_LOCAL_EXECUTABLE_BYTE_READ_VIEW_DIFFERENCE',
        'IN_PROCESS_WHOLE_FILE_HASH_PATH_DIFFERENCE_WITH_EQUAL_CHUNKS'
    ) -and $knownAnswersPassed -and $externalHashesTrusted -and $metadataStable -and $pathsAgree -and
        $externalFileIdStable -and $inProcessMatchesExternalFileId -and $priorEvidenceUnchanged -and
        $unityInvocationCount -eq 1 -and $remainingUnity.Count -eq 0 -and $remainingProhibited.Count -eq 0 -and
        $prohibitedRootsAfter.Count -eq 0

    $rawAudit = [ordered]@{
        schema = 'gate14re-me-unity-executable-identity-discrepancy-audit-v1'
        studyId = $studyId
        authorizationId = $authorizationId
        status = $(if ($trustworthyRuleSupported) { 'PASS_OPERATIONAL_DISCREPANCY_EXPLANATION' } else { 'FAILED_CLOSED_OPERATIONAL_DISCREPANCY_EXPLANATION' })
        completedAtUtc = [DateTime]::UtcNow.ToString('o')
        unityInvocation = [ordered]@{
            count = $unityInvocationCount
            processId = $unityProcessId
            creationTimeUtc = $creationUtc
            launchedAtUtc = $launchedAtUtc
            exitedAtUtc = $exitedAtUtc
            exitCode = $unityExitCode
            executablePath = ([string]$unityProcessMetadata.ExecutablePath).Replace('\', '/')
            commandLine = $commandLine
            executeMethod = $executeMethod
            retryPerformed = $false
            signalOrForcedTerminationSent = $false
        }
        observations = [ordered]@{
            expectedExternalSha256 = $expectedUnitySha256
            externalPrelaunchSha256 = $preHash
            externalConcurrentSha256 = $concurrentHash
            externalPostExitSha256 = $postHash
            independentExternalHashMethodsAgreeAtAllThreePhases = $externalHashesTrusted
            inProcessSha256 = $internalHash
            inProcessHashMethodsAgree = $internalMethodsAgree
            inProcessFingerprintStableAcrossHold = [bool]$unityReceipt.inProcessFingerprintStableAcrossHold
            discrepancyReproduced = $discrepancyReproduced
            exactPriorMismatchHashReproduced = $exactPriorMismatchReproduced
            sha256KnownAnswersPassed = $knownAnswersPassed
            executablePathsAgree = $pathsAgree
            externalFileIdStable = $externalFileIdStable
            inProcessFileIdMatchesExternalLow64 = $inProcessMatchesExternalFileId
            metadataStable = $metadataStable
            mismatched64KiBChunkCount = $chunkMismatches.Count
            mismatched64KiBChunks = $chunkMismatches
        }
        classification = $classification
        operationalExplanation = $(switch ($classification) {
            'PROCESS_LOCAL_EXECUTABLE_BYTE_READ_VIEW_DIFFERENCE' { 'The discrepancy is reproducible only inside the running Unity process: standard and large-stream SHA-256 known answers pass, three independent managed read/hash paths agree and remain stable, the EditorApplication/MainModule/Win32 paths and NTFS file identity match the externally observed executable, yet one or more per-chunk byte-read digests differ while external prelaunch/live/post-exit hashes remain the frozen expected value. The evidence therefore rules out alternate executable selection, unstable on-disk bytes, and a generic SHA-256 failure. It establishes a process-local executable byte-read view difference, without claiming an unobserved vendor, kernel, filter-driver, or security-product root cause.' }
            'IN_PROCESS_WHOLE_FILE_HASH_PATH_DIFFERENCE_WITH_EQUAL_CHUNKS' { 'The discrepancy is reproducible in whole-file hashing inside Unity while known answers, executable identity, external hashes and all individual chunk hashes remain stable. The evidence therefore establishes an in-process whole-file hashing-path difference rather than a different executable or on-disk mutation; it does not claim an unobserved deeper vendor or operating-system cause.' }
            'PRIOR_DISCREPANCY_NOT_REPRODUCED' { 'The prior discrepancy did not reproduce in the single authorized probe; no causal explanation is asserted.' }
            default { 'The observations do not support a trustworthy operational explanation; the stage fails closed without retry.' }
        })
        priorAttemptEvidence = [ordered]@{
            beforeFileCount = $priorInventoryBefore.Count
            afterFileCount = $priorInventoryAfter.Count
            beforeInventoryDigestSha256 = $priorInventoryDigestBefore
            afterInventoryDigestSha256 = $priorInventoryDigestAfter
            unchanged = $priorEvidenceUnchanged
        }
        boundary = [ordered]@{
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
            remainingUnityProcessCount = $remainingUnity.Count
            remainingProhibitedProcessCount = $remainingProhibited.Count
            prohibitedRootsPresentAfter = $prohibitedRootsAfter
            transientUnityCacheCleanup = $transientCleanup
        }
    }
    $rawAuditPath = Join-Path $stageRoot 'identity-discrepancy-audit.v1.json'
    Write-JsonExclusive -Path $rawAuditPath -Value $rawAudit
    Require-Condition $trustworthyRuleSupported "Identity discrepancy audit did not support a trustworthy rule; classification=$classification"

    $rule = [ordered]@{
        schema = 'gate14re-me-unity-executable-identity-verification-rule-v1'
        studyId = $studyId
        ruleId = 'gate14re-me-unity-2022.3.30f1c1-external-prelaunch-compound-process-identity-v1'
        status = 'FROZEN_TRUSTED_IDENTITY_RULE'
        frozenAtUtc = [DateTime]::UtcNow.ToString('o')
        authorizationId = $authorizationId
        applicability = [ordered]@{
            host = $env:COMPUTERNAME
            unityVersion = '2022.3.30f1c1'
            unityExecutablePath = $resolvedUnityExecutable.Replace('\', '/')
            unityExecutableExpectedSha256 = $expectedUnitySha256
            ntfsFileIdHex = [string]$prelaunchFingerprint.fileIdentity.fileIdHex
            fileLengthBytes = [int64]$prelaunchFingerprint.lengthBytes
            signerSubject = [string]$prelaunchFingerprint.authenticode.signerSubject
            signerThumbprint = [string]$prelaunchFingerprint.authenticode.signerThumbprint
        }
        authoritativeIdentitySources = @(
            'external controller SHA-256 immediately before launch, with two independent external implementations agreeing',
            'external normalized regular-file path and stable NTFS file ID',
            'live PID plus creation time plus Win32 executable path plus exact command line and execute method',
            'external post-exit SHA-256, path, file ID, length and timestamps reconfirmation'
        )
        nonAuthoritativeIdentitySources = @(
            'SHA-256 computed by the running Unity editor over EditorApplication.applicationPath on this frozen host/runtime',
            'process name without PID, creation time, executable path and exact command line'
        )
        prelaunchRequirements = [ordered]@{
            noExistingUnityProcess = $true
            normalizedPathMustEqualFrozenPath = $true
            targetMustBeRegularNonReparseFile = $true
            authenticodeStatusMustBeValid = $true
            signerThumbprintMustEqualFrozenValue = $true
            fileIdLengthAndTimestampsMustEqualFrozenValues = $true
            powershellGetFileHashAndDotNetFileStreamSha256MustAgree = $true
            agreedSha256MustEqualFrozenExpectedValue = $true
        }
        liveProcessRequirements = [ordered]@{
            captureImmediatelyAfterStart = @('PID', 'creationTimeUtc', 'Win32_Process.ExecutablePath', 'exact commandLine')
            executablePathMustEqualPrelaunchPath = $true
            commandLineMustContainOnlyAuthorizedExecuteMethodAndProjectRoot = $true
            externallyResolvedPathAndFileIdMustRemainFrozen = $true
            inProcessSelfHashRequiredForAuthorization = $false
            inProcessSelfHashRole = 'diagnostic-only'
        }
        postExitRequirements = [ordered]@{
            processMustExitNormallyWithoutSignalOrForcedTermination = $true
            samePathFileIdLengthAndTimestampsRequired = $true
            twoIndependentExternalHashesMustAgainAgreeWithFrozenExpectedValue = $true
            anyMismatchDisposition = 'FAIL_CLOSED_NO_RETRY_NO_ADOPTION'
        }
        evidenceClassification = $classification
        explanationBoundary = 'This rule is based on directly observed identities and read views. It does not attribute the process-local difference to an unobserved Unity defect, operating-system defect, filter driver, antivirus product, or other vendor mechanism.'
        evidenceBindings = [ordered]@{
            identityDiscrepancyAudit = [ordered]@{
                relativePath = Get-ProjectRelativePath -Path $rawAuditPath -Root $resolvedProjectRoot
                sha256 = Get-Sha256Lower -Path $rawAuditPath
            }
            unityProbeReceipt = [ordered]@{
                relativePath = Get-ProjectRelativePath -Path $unityReceiptPath -Root $resolvedProjectRoot
                sha256 = Get-Sha256Lower -Path $unityReceiptPath
            }
            externalPrelaunchFingerprint = [ordered]@{
                relativePath = 'Research/Verification/Gate14Re-ME/unity-executable-identity-discrepancy-audit-attempt-003/external-prelaunch-fingerprint.v1.json'
                sha256 = Get-Sha256Lower -Path (Join-Path $stageRoot 'external-prelaunch-fingerprint.v1.json')
            }
            externalConcurrentFingerprint = [ordered]@{
                relativePath = 'Research/Verification/Gate14Re-ME/unity-executable-identity-discrepancy-audit-attempt-003/external-concurrent-fingerprint.v1.json'
                sha256 = Get-Sha256Lower -Path (Join-Path $stageRoot 'external-concurrent-fingerprint.v1.json')
            }
            externalPostExitFingerprint = [ordered]@{
                relativePath = 'Research/Verification/Gate14Re-ME/unity-executable-identity-discrepancy-audit-attempt-003/external-post-exit-fingerprint.v1.json'
                sha256 = Get-Sha256Lower -Path (Join-Path $stageRoot 'external-post-exit-fingerprint.v1.json')
            }
        }
    }
    $rulePath = Join-Path $stageRoot 'unity-executable-identity-verification-rule.v1.json'
    Write-JsonExclusive -Path $rulePath -Value $rule

    $terminalReceipt = [ordered]@{
        schema = 'gate14re-me-unity-executable-identity-discrepancy-audit-terminal-receipt-v1'
        studyId = $studyId
        authorizationId = $authorizationId
        status = 'PASS_UNITY_EXECUTABLE_IDENTITY_DISCREPANCY_EXPLAINED_RULE_FROZEN'
        completedAtUtc = [DateTime]::UtcNow.ToString('o')
        passed = $true
        terminal = $true
        unityInvocationCount = $unityInvocationCount
        classification = $classification
        priorMismatchHashExactlyReproduced = $exactPriorMismatchReproduced
        priorAttemptEvidenceUnchanged = $priorEvidenceUnchanged
        trustedIdentityRule = [ordered]@{
            relativePath = Get-ProjectRelativePath -Path $rulePath -Root $resolvedProjectRoot
            sha256 = Get-Sha256Lower -Path $rulePath
        }
        rawAudit = [ordered]@{
            relativePath = Get-ProjectRelativePath -Path $rawAuditPath -Root $resolvedProjectRoot
            sha256 = Get-Sha256Lower -Path $rawAuditPath
        }
        boundary = $rawAudit.boundary
        nextAuthorizationRequired = 'A new, separate authorization is required before any schema-compatibility retry, qualification planning, schedule/input/identity-map generation, measured-root creation, algorithm lane, collection, analysis, ranking or winner adjudication.'
    }
    $terminalReceiptPath = Join-Path $stageRoot 'terminal-receipt.v1.json'
    Write-JsonExclusive -Path $terminalReceiptPath -Value $terminalReceipt

    $statusV15 = [ordered]@{
        schema = 'gate14re-me-status-v15'
        studyId = $studyId
        status = 'UNITY_EXECUTABLE_IDENTITY_DISCREPANCY_EXPLAINED_TRUSTED_RULE_FROZEN'
        version = 15
        updatedAtUtc = [DateTime]::UtcNow.ToString('o')
        previousVersionedStatus = [ordered]@{
            relativePath = 'Research/Gate14Re-ME/Gate14Re_ME_Status.v14.json'
            lengthBytes = (Get-Item -LiteralPath $statusV14Path).Length
            sha256 = Get-Sha256Lower -Path $statusV14Path
            retained = $true
        }
        identityAudit = [ordered]@{
            authorizationId = $authorizationId
            status = $terminalReceipt.status
            classification = $classification
            priorMismatchHashExactlyReproduced = $exactPriorMismatchReproduced
            trustedRuleRelativePath = Get-ProjectRelativePath -Path $rulePath -Root $resolvedProjectRoot
            trustedRuleSha256 = Get-Sha256Lower -Path $rulePath
            terminalReceiptRelativePath = Get-ProjectRelativePath -Path $terminalReceiptPath -Root $resolvedProjectRoot
            terminalReceiptSha256 = Get-Sha256Lower -Path $terminalReceiptPath
        }
        corrigendumAttempt001 = [ordered]@{
            status = 'RETAINED_FAILED_CLOSED_UNCHANGED'
            evidenceFileCount = $priorInventoryAfter.Count
            beforeInventoryDigestSha256 = $priorInventoryDigestBefore
            afterInventoryDigestSha256 = $priorInventoryDigestAfter
            unchanged = $priorEvidenceUnchanged
            schemaCompatibilitySelfCheckRerun = $false
            correctedSchemaCandidateAdopted = $false
            planningBindingCandidateAdopted = $false
        }
        scientificBoundary = [ordered]@{
            qualificationScheduleRows = 0
            qualificationInputs = 0
            anonymousIdentityMappings = 0
            measuredRootCreated = $false
            plannerInvocations = 0
            algorithmLanes = 0
            formalObservations = 0
            formalAnalysisPerformed = $false
            algorithmRankingPerformed = $false
            winnerAdjudicationPerformed = $false
        }
        authorizationState = [ordered]@{
            unityExecutableIdentityDiscrepancyAuditAuthorizationConsumed = $true
            unityExecutableIdentityDiscrepancyAuditPassed = $true
            inputSchemaCompatibilityAttempt002Authorized = $false
            qualificationPlanningAttempt002Authorized = $false
            qualificationScheduleGenerationAuthorized = $false
            qualificationInputGenerationAuthorized = $false
            anonymousIdentityMapGenerationAuthorized = $false
            measuredRootCreationAuthorized = $false
            algorithmLaneExecutionAuthorized = $false
            formalCollectionAuthorized = $false
            formalAnalysisAuthorized = $false
            rankingAuthorized = $false
            winnerAdjudicationAuthorized = $false
        }
        nextRequiredAction = 'Separately authorize the next minimum stage. The frozen identity rule may be used in a future explicitly authorized Unity stage, but this audit itself authorizes no schema-compatibility retry or qualification activity.'
    }
    Write-JsonExclusive -Path $statusV15Path -Value $statusV15

    $evidenceFiles = @(Get-ChildItem -LiteralPath $stageRoot -Recurse -Force -File | Sort-Object FullName | ForEach-Object {
        [ordered]@{
            relativePath = Get-ProjectRelativePath -Path $_.FullName -Root $resolvedProjectRoot
            lengthBytes = [int64]$_.Length
            sha256 = Get-Sha256Lower -Path $_.FullName
        }
    })
    $finalManifest = [ordered]@{
        schema = 'gate14re-me-unity-executable-identity-audit-evidence-freeze-manifest-v1'
        studyId = $studyId
        authorizationId = $authorizationId
        status = 'FROZEN_TERMINAL_IDENTITY_AUDIT_EVIDENCE'
        frozenAtUtc = [DateTime]::UtcNow.ToString('o')
        sourceFreezeManifest = [ordered]@{
            relativePath = Get-ProjectRelativePath -Path $resolvedFreezeManifest -Root $resolvedProjectRoot
            sha256 = $FreezeManifestSha256
        }
        statusV15 = [ordered]@{
            relativePath = Get-ProjectRelativePath -Path $statusV15Path -Root $resolvedProjectRoot
            sha256 = Get-Sha256Lower -Path $statusV15Path
        }
        evidenceFiles = $evidenceFiles
    }
    $finalManifestPath = Join-Path $stageRoot 'source-and-evidence-freeze-manifest.v1.json'
    Write-JsonExclusive -Path $finalManifestPath -Value $finalManifest

    foreach ($file in @(Get-ChildItem -LiteralPath $stageRoot -Recurse -Force -File)) { Set-ReadOnlyFile -Path $file.FullName }
    foreach ($file in @($authorizationPath, $planPath, $probeSourcePath, $toolPath, $resolvedFreezeManifest, $statusV15Path)) { Set-ReadOnlyFile -Path $file }
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
                Write-Output "Fail-closed condition recorded; waiting for authorized Unity PID $($unityProcess.Id) to exit naturally. No signal sent."
                Start-Sleep -Seconds 5
                $unityProcess.Refresh()
            }
        }
        catch { }
    }

    if ($stageRootCreated) {
        try {
            if (Test-Path -LiteralPath $auditProjectRoot -PathType Container) {
                $transientCleanup = @(Remove-IsolatedUnityTransientCaches -AuditProjectRoot $auditProjectRoot -AuthorizedStageRoot $stageRoot)
            }
        }
        catch { }

        $priorInventoryAfterFailure = @()
        $priorDigestAfterFailure = $null
        $priorUnchangedAfterFailure = $false
        try {
            $priorInventoryAfterFailure = @(Get-FileInventory -Root $priorAttemptRoot)
            $priorDigestAfterFailure = Get-InventoryContentDigest -Inventory $priorInventoryAfterFailure
            $priorUnchangedAfterFailure = $priorDigestAfterFailure -eq $priorInventoryDigestBefore
        }
        catch { }

        $failureReceiptPath = Join-Path $stageRoot 'failure-receipt.v1.json'
        if (-not (Test-Path -LiteralPath $failureReceiptPath)) {
            Write-JsonExclusive -Path $failureReceiptPath -Value ([ordered]@{
                schema = 'gate14re-me-unity-executable-identity-discrepancy-audit-failure-receipt-v1'
                studyId = $studyId
                authorizationId = $authorizationId
                status = 'FAILED_CLOSED_UNITY_EXECUTABLE_IDENTITY_DISCREPANCY_AUDIT'
                failedAtUtc = [DateTime]::UtcNow.ToString('o')
                classification = $classification
                exceptionType = $exceptionType
                exactFailure = $exactFailure
                stackTrace = $stackTrace
                unityInvocationCount = $unityInvocationCount
                retryPerformed = $false
                signalOrForcedTerminationSent = $false
                priorAttemptEvidence = [ordered]@{
                    beforeInventoryDigestSha256 = $priorInventoryDigestBefore
                    afterInventoryDigestSha256 = $priorDigestAfterFailure
                    unchanged = $priorUnchangedAfterFailure
                }
                boundary = [ordered]@{
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
                    transientUnityCacheCleanup = $transientCleanup
                }
            })
        }

        if (-not (Test-Path -LiteralPath $statusV15Path)) {
            Write-JsonExclusive -Path $statusV15Path -Value ([ordered]@{
                schema = 'gate14re-me-status-v15'
                studyId = $studyId
                status = 'UNITY_EXECUTABLE_IDENTITY_DISCREPANCY_AUDIT_FAILED_CLOSED'
                version = 15
                updatedAtUtc = [DateTime]::UtcNow.ToString('o')
                previousVersionedStatus = [ordered]@{
                    relativePath = 'Research/Gate14Re-ME/Gate14Re_ME_Status.v14.json'
                    sha256 = Get-Sha256Lower -Path $statusV14Path
                    retained = $true
                }
                identityAudit = [ordered]@{
                    authorizationId = $authorizationId
                    passed = $false
                    classification = $classification
                    failureReceiptRelativePath = Get-ProjectRelativePath -Path $failureReceiptPath -Root $resolvedProjectRoot
                    failureReceiptSha256 = Get-Sha256Lower -Path $failureReceiptPath
                    retryPerformed = $false
                }
                scientificBoundary = [ordered]@{
                    schemaCompatibilitySelfCheckRerun = $false
                    qualificationScheduleRows = 0
                    qualificationInputs = 0
                    anonymousIdentityMappings = 0
                    measuredRootCreated = $false
                    plannerInvocations = 0
                    algorithmLanes = 0
                    formalAnalysisPerformed = $false
                    algorithmRankingPerformed = $false
                    winnerAdjudicationPerformed = $false
                }
                nextRequiredAction = 'A new separate authorization is required. Do not retry, generate planning artifacts, create a measured root, or run an algorithm lane.'
            })
        }

        foreach ($file in @(Get-ChildItem -LiteralPath $stageRoot -Recurse -Force -File)) { Set-ReadOnlyFile -Path $file.FullName }
        foreach ($file in @($authorizationPath, $planPath, $probeSourcePath, $toolPath, $resolvedFreezeManifest, $statusV15Path)) { Set-ReadOnlyFile -Path $file }
    }
    Write-Error "Gate14Re-ME identity discrepancy audit failed closed: $exactFailure"
    exit 1
}

if (-not $stagePassed) { exit 1 }




