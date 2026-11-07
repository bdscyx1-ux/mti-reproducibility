[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ProjectRoot,

    [Parameter(Mandatory = $true)]
    [string]$UnityExecutable,

    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[0-9a-f]{64}$')]
    [string]$RunnerSha256,

    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[0-9a-f]{64}$')]
    [string]$HarnessSha256
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$studyId = 'Gate14Re-ME'
$attemptId = 'qualification-schedule-null-replacement-deserialization-corrigendum-attempt-001'
$authorizationId = 'gate14re-me-qualification-schedule-null-replacement-deserialization-corrigendum-attempt-001'
$executeMethod = 'DDM.Research.Editor.Gate14ReMEScheduleNullReplacementKnownAnswerV1.Run'
$expectedUnitySha256 = '0a69d14cbe2ca82d0a6168da8156d9e0dd138a6b7d0260dcdea31fd3957ca9cf'
$expectedStatusV37Sha256 = 'effa1a9270965c537bb24c2915f3f4498fd992bc2a29e601acdceba60c8dd232'
$expectedAttempt003TerminalSha256 = 'ec78b55c4f7be0d00433958806a26b7ef1e1a3dd75ce140a9013079cadf13df9'
$expectedAttempt003AdjudicationSha256 = '0de24cf90557e0e4dcdfa26f299d152f6883af85b3cce4e9ec8a887f693d23ca'
$expectedAttempt003FreezeSha256 = '10764c3f357eeec90eb138701d4c29a3d16a6e1047dbbc48a4a26be551fee249'
$expectedTrustedRuleSha256 = 'f045ef93630202a72d603096687bac655b5b4ff01e8e0743e60d63881bbded06'
$expectedTimestampComparatorSha256 = 'd024c5471d1fc06fb08e9c9ca1c9cf612424d4299d8b8c6b856883745105eb27'
$chunkSizeBytes = 65536
$unityInvocationCount = 0
$unityProcess = $null
$unityExitCode = $null

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
    $stream = [System.IO.FileStream]::new($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite -bor [System.IO.FileShare]::Delete)
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

function Test-PathsEqual {
    param([string]$Left, [string]$Right)
    if ([string]::IsNullOrWhiteSpace($Left) -or [string]::IsNullOrWhiteSpace($Right)) { return $false }
    return [System.IO.Path]::GetFullPath($Left).TrimEnd('\') -ieq [System.IO.Path]::GetFullPath($Right).TrimEnd('\')
}

function Get-FileIdentity {
    param([string]$Path)
    $lines = @(& "$env:SystemRoot\System32\fsutil.exe" file queryfileid $Path 2>&1 | ForEach-Object { [string]$_ })
    $exitCode = $LASTEXITCODE
    $raw = $lines -join [Environment]::NewLine
    $match = [regex]::Match($raw, '0x[0-9A-Fa-f]+')
    $hex = if ($match.Success) { $match.Value.Substring(2).ToLowerInvariant() } else { $null }
    return [ordered]@{
        succeeded = ($exitCode -eq 0 -and $match.Success)
        fileIdHex = $hex
        fileIndexLow64Hex = if ($match.Success) { if ($hex.Length -gt 16) { $hex.Substring($hex.Length - 16) } else { $hex.PadLeft(16, '0') } } else { $null }
        fsutilExitCode = $exitCode
    }
}

function Get-PeIdentity {
    param([string]$Path)
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
            return [ordered]@{
                succeeded = $true
                peHeaderOffset = $peOffset
                optionalHeaderMagicHex = ('{0:x4}' -f $magic)
                checksumFieldOffset = $checksumOffset
                checksumHex = ('{0:x8}' -f $checksum)
                securityDirectoryFieldOffset = $securityDirectoryOffset
                certificateTableFileOffset = $reader.ReadUInt32()
                certificateTableSizeBytes = $reader.ReadUInt32()
            }
        }
        finally { $reader.Dispose() }
    }
    finally { $stream.Dispose() }
}

function Get-ChunkHashes {
    param([string]$Path)
    $chunks = [System.Collections.Generic.List[object]]::new()
    $stream = [System.IO.FileStream]::new($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite -bor [System.IO.FileShare]::Delete)
    try {
        $buffer = [byte[]]::new($chunkSizeBytes)
        [int64]$offset = 0
        $index = 0
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
            $chunks.Add([pscustomobject][ordered]@{ chunkIndex = $index; offsetBytes = $offset; lengthBytes = $count; sha256 = $digest })
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
    $hashA = Get-Sha256Lower -Path $Path
    $hashB = Get-DotNetSha256Lower -Path $Path
    $chunks = @(Get-ChunkHashes -Path $Path)
    $chunkCanonical = ($chunks | ConvertTo-Json -Depth 10 -Compress)
    return [ordered]@{
        schema = 'gate14re-me-external-unity-executable-fingerprint-v1'
        studyId = $studyId
        authorizationId = $authorizationId
        attemptId = $attemptId
        phase = $Phase
        capturedAtUtc = [DateTime]::UtcNow.ToString('o')
        path = $item.FullName.Replace('\', '/')
        lengthBytes = [int64]$item.Length
        creationTimeUtc = $item.CreationTimeUtc.ToString('o')
        lastWriteTimeUtc = $item.LastWriteTimeUtc.ToString('o')
        attributes = $item.Attributes.ToString()
        reparsePoint = (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0)
        fileIdentity = Get-FileIdentity -Path $Path
        peIdentity = Get-PeIdentity -Path $Path
        authenticode = [ordered]@{
            status = $signature.Status.ToString()
            signerSubject = if ($null -ne $signature.SignerCertificate) { $signature.SignerCertificate.Subject } else { $null }
            signerThumbprint = if ($null -ne $signature.SignerCertificate) { $signature.SignerCertificate.Thumbprint } else { $null }
        }
        versionMetadata = [ordered]@{
            fileVersion = $version.FileVersion
            productVersion = $version.ProductVersion
            originalFilename = $version.OriginalFilename
            companyName = $version.CompanyName
            productName = $version.ProductName
        }
        fullFileHashes = @(
            [ordered]@{ method = 'powershell-get-filehash'; sha256 = $hashA },
            [ordered]@{ method = 'dotnet-sha256-filestream'; sha256 = $hashB }
        )
        independentHashMethodsAgree = ($hashA -eq $hashB)
        chunkSizeBytes = $chunkSizeBytes
        chunkCount = $chunks.Count
        chunkSetDigestSha256 = Get-StringSha256Lower -Value $chunkCanonical
        chunkHashes = $chunks
    }
}

function Assert-TrustedFingerprint {
    param([object]$Fingerprint, [object]$TrustedRule)
    $creation = Compare-Gate14ReMETrustedTimestampV1 -TrustedText ([string]$TrustedRule.applicability.creationTimeUtc) -ObservedText ([string]$Fingerprint.creationTimeUtc)
    $lastWrite = Compare-Gate14ReMETrustedTimestampV1 -TrustedText ([string]$TrustedRule.applicability.lastWriteTimeUtc) -ObservedText ([string]$Fingerprint.lastWriteTimeUtc)
    $hashes = @($Fingerprint.fullFileHashes)
    $passed = [bool](
        (Test-PathsEqual -Left ([string]$Fingerprint.path) -Right ([string]$TrustedRule.applicability.unityExecutablePath)) -and
        [int64]$Fingerprint.lengthBytes -eq [int64]$TrustedRule.applicability.fileLengthBytes -and
        -not [bool]$Fingerprint.reparsePoint -and
        [bool]$Fingerprint.independentHashMethodsAgree -and
        $hashes.Count -eq 2 -and
        [string]$hashes[0].sha256 -eq [string]$TrustedRule.applicability.unityExecutableExpectedSha256 -and
        [string]$hashes[1].sha256 -eq [string]$TrustedRule.applicability.unityExecutableExpectedSha256 -and
        [bool]$Fingerprint.fileIdentity.succeeded -and
        [string]$Fingerprint.fileIdentity.fileIdHex -eq [string]$TrustedRule.applicability.ntfsFileIdHex -and
        [string]$Fingerprint.fileIdentity.fileIndexLow64Hex -eq [string]$TrustedRule.applicability.ntfsFileIndexLow64Hex -and
        [bool]$Fingerprint.peIdentity.succeeded -and
        [string]$Fingerprint.authenticode.status -eq 'Valid' -and
        [string]$Fingerprint.authenticode.signerSubject -eq [string]$TrustedRule.applicability.signerSubject -and
        [string]$Fingerprint.authenticode.signerThumbprint -eq [string]$TrustedRule.applicability.signerThumbprint -and
        [bool]$creation.comparisonAccepted -and [bool]$lastWrite.comparisonAccepted)
    Require-Condition $passed "Unity $($Fingerprint.phase) fingerprint failed the frozen trusted identity rule."
    return [ordered]@{ passed = $passed; creationTimeComparison = $creation; lastWriteTimeComparison = $lastWrite }
}

function Compare-ExternalPhases {
    param([object]$Left, [object]$Right)
    return [bool](
        [string]$Left.path -eq [string]$Right.path -and
        [int64]$Left.lengthBytes -eq [int64]$Right.lengthBytes -and
        [string]$Left.fileIdentity.fileIdHex -eq [string]$Right.fileIdentity.fileIdHex -and
        [string]$Left.creationTimeUtc -eq [string]$Right.creationTimeUtc -and
        [string]$Left.lastWriteTimeUtc -eq [string]$Right.lastWriteTimeUtc -and
        [string]$Left.fullFileHashes[0].sha256 -eq [string]$Right.fullFileHashes[0].sha256 -and
        [string]$Left.fullFileHashes[1].sha256 -eq [string]$Right.fullFileHashes[1].sha256 -and
        [string]$Left.chunkSetDigestSha256 -eq [string]$Right.chunkSetDigestSha256 -and
        [int]$Left.chunkCount -eq [int]$Right.chunkCount -and
        (($Left.peIdentity | ConvertTo-Json -Compress) -ceq ($Right.peIdentity | ConvertTo-Json -Compress)) -and
        (($Left.authenticode | ConvertTo-Json -Compress) -ceq ($Right.authenticode | ConvertTo-Json -Compress)) -and
        (($Left.versionMetadata | ConvertTo-Json -Compress) -ceq ($Right.versionMetadata | ConvertTo-Json -Compress)))
}

function Get-Inventory {
    param([string]$Root)
    return @(Get-ChildItem -LiteralPath $Root -Recurse -Force -File | Sort-Object FullName | ForEach-Object {
        [ordered]@{
            relativePath = Get-ProjectRelativePath -Path $_.FullName -Root $Root
            lengthBytes = [int64]$_.Length
            sha256 = Get-Sha256Lower -Path $_.FullName
            readOnly = [bool]$_.IsReadOnly
        }
    })
}

function Get-InventoryDigest {
    param([object[]]$Inventory)
    return Get-StringSha256Lower -Value ($Inventory | ConvertTo-Json -Depth 10 -Compress)
}

$projectRootFull = Get-NormalizedFullPath -Path $ProjectRoot -Base (Get-Location).Path
$unityFull = Get-NormalizedFullPath -Path $UnityExecutable -Base $projectRootFull
$attemptRoot = Join-Path $projectRootFull 'Research/Verification/Gate14Re-ME/qualification-schedule-null-replacement-deserialization-corrigendum-attempt-001'
$outputRoot = Join-Path $attemptRoot 'unity-known-answer-output'
$readyPath = Join-Path $outputRoot 'in-process-ready-snapshot.v1.json'
$knownAnswerReceiptPath = Join-Path $outputRoot 'known-answer-receipt.v1.json'
$unityLogPath = Join-Path $attemptRoot 'unity-known-answer.log'
$runnerPath = Join-Path $projectRootFull 'Assets/_Scripts/Research/Editor/Gate14ReMELoadQualificationRunnerV2.cs'
$harnessPath = Join-Path $projectRootFull 'Assets/_Scripts/Research/Editor/Gate14ReMEScheduleNullReplacementKnownAnswerV1.cs'
$statusV37Path = Join-Path $projectRootFull 'Research/Gate14Re-ME/Gate14Re_ME_Status.v37.json'
$attempt003Root = Join-Path $projectRootFull 'Research/Verification/Gate14Re-ME/load-qualification-execution-attempt-003'
$failedMeasuredRoot = Join-Path $projectRootFull 'Research/PilotRuns/Gate14Re-ME/load-qualification/attempt-001'
$trustedRulePath = Join-Path $projectRootFull 'Research/Verification/Gate14Re-ME/unity-executable-identity-rule-offline-adjudication-attempt-005/trusted-launch-identity-rule.v1.json'
$comparatorPath = Join-Path $projectRootFull 'Research/Verification/Gate14Re-ME/unity-trusted-identity-timestamp-comparator-corrigendum-attempt-007/Gate14ReMETrustedTimestampComparatorV1.ps1'
$deliveryRoot = Join-Path $projectRootFull 'Research/Exports/Gate14Re-ME/load-qualification/attempt-001'

Require-Condition (Test-Path -LiteralPath $attemptRoot -PathType Container) 'Authorized attempt root is missing.'
Require-Condition (-not (Test-Path -LiteralPath $outputRoot)) 'Known-answer output root already exists; retry is prohibited.'
Require-Condition (-not (Test-Path -LiteralPath $unityLogPath)) 'Known-answer Unity log already exists; retry is prohibited.'
Require-Condition ((Get-Sha256Lower -Path $runnerPath) -eq $RunnerSha256) 'RunnerV2 source hash differs from the authorized repair candidate.'
Require-Condition ((Get-Sha256Lower -Path $harnessPath) -eq $HarnessSha256) 'Known-answer harness hash differs from the authorized candidate.'
Require-Condition ((Get-Sha256Lower -Path $statusV37Path) -eq $expectedStatusV37Sha256) 'Status v37 drifted.'
Require-Condition ((Get-Sha256Lower -Path (Join-Path $attempt003Root 'terminal-failure-receipt.v1.json')) -eq $expectedAttempt003TerminalSha256) 'Attempt-003 terminal failure receipt drifted.'
Require-Condition ((Get-Sha256Lower -Path (Join-Path $attempt003Root 'technical-failure-adjudication.v1.json')) -eq $expectedAttempt003AdjudicationSha256) 'Attempt-003 technical adjudication drifted.'
Require-Condition ((Get-Sha256Lower -Path (Join-Path $attempt003Root 'freeze-manifest.v1.json')) -eq $expectedAttempt003FreezeSha256) 'Attempt-003 freeze manifest drifted.'
Require-Condition (Test-Path -LiteralPath $failedMeasuredRoot -PathType Container) 'Failed measured root is missing.'
Require-Condition (-not (Test-Path -LiteralPath $deliveryRoot)) 'A qualification delivery root already exists unexpectedly.'
Require-Condition ((Get-Sha256Lower -Path $unityFull) -eq $expectedUnitySha256) 'Unity executable hash mismatch.'
Require-Condition ((Get-Sha256Lower -Path $trustedRulePath) -eq $expectedTrustedRuleSha256) 'Trusted Unity identity rule drifted.'
Require-Condition ((Get-Sha256Lower -Path $comparatorPath) -eq $expectedTimestampComparatorSha256) 'Trusted timestamp comparator drifted.'
Require-Condition (@(Get-CimInstance Win32_Process -Filter "Name = 'Unity.exe'").Count -eq 0) 'A Unity process is already active.'

. $comparatorPath
$trustedRule = Get-Content -LiteralPath $trustedRulePath -Raw -Encoding UTF8 | ConvertFrom-Json -Depth 100 -DateKind String
$attempt003Before = @(Get-Inventory -Root $attempt003Root)
$attempt003BeforeDigest = Get-InventoryDigest -Inventory $attempt003Before
$measuredBefore = @(Get-Inventory -Root $failedMeasuredRoot)
$measuredBeforeDigest = Get-InventoryDigest -Inventory $measuredBefore
$pilotRootsBefore = @(Get-ChildItem -LiteralPath (Split-Path -Parent $failedMeasuredRoot) -Directory -Force | Sort-Object FullName | ForEach-Object { $_.FullName })

try {
    $pre = Get-ExternalFingerprint -Path $unityFull -Phase 'EXTERNAL_PRELAUNCH'
    $pre['trustedRuleComparison'] = Assert-TrustedFingerprint -Fingerprint $pre -TrustedRule $trustedRule
    Write-JsonExclusive -Path (Join-Path $attemptRoot 'external-prelaunch-fingerprint.v1.json') -Value $pre

    $arguments = @(
        '-batchmode', '-nographics', '-quit',
        '-projectPath', $projectRootFull,
        '-logFile', $unityLogPath,
        '-executeMethod', $executeMethod,
        '--g14me-known-answer-output', $outputRoot,
        '--g14me-live-hold-seconds', '30'
    )
    $unityProcess = Start-Process -FilePath $unityFull -ArgumentList $arguments -WindowStyle Hidden -PassThru
    $unityInvocationCount = 1
    $processId = $unityProcess.Id
    $metadata = $null
    $metadataDeadline = [DateTime]::UtcNow.AddSeconds(30)
    while ($null -eq $metadata -and [DateTime]::UtcNow -lt $metadataDeadline) {
        $metadata = Get-CimInstance Win32_Process -Filter "ProcessId = $processId" -ErrorAction SilentlyContinue
        if ($null -eq $metadata) { Start-Sleep -Milliseconds 100 }
    }
    Require-Condition ($null -ne $metadata) 'Unable to capture launched Unity process metadata.'
    $commandLine = [string]$metadata.CommandLine
    Require-Condition (Test-PathsEqual -Left ([string]$metadata.ExecutablePath) -Right $unityFull) 'Live Unity executable path mismatch.'
    Require-Condition ($commandLine.Contains($executeMethod) -and $commandLine.Contains($projectRootFull) -and $commandLine.Contains($outputRoot)) 'Live Unity command line is not bound to the exact known-answer invocation.'
    Require-Condition (-not ($commandLine -match 'Gate14ReMELoadQualificationRunnerV2\.Run|instrument-self-test|empty-boundary|--g14me-mode|Gate14ReMEQualificationPlanner|Gate14ReMEReferenceOracle')) 'Prohibited qualification execution appeared in the Unity command line.'
    Write-JsonExclusive -Path (Join-Path $attemptRoot 'process-launch-receipt.v1.json') -Value ([ordered]@{
        schema = 'gate14re-me-schedule-null-replacement-known-answer-launch-receipt-v1'
        studyId = $studyId
        authorizationId = $authorizationId
        attemptId = $attemptId
        status = 'ONE_ALGORITHM_FREE_UNITY_KNOWN_ANSWER_LAUNCHED'
        invocationOrdinal = 1
        processId = $processId
        creationTimeUtc = ([DateTime]$metadata.CreationDate).ToUniversalTime().ToString('o')
        executablePath = ([string]$metadata.ExecutablePath).Replace('\', '/')
        commandLine = $commandLine
        executeMethod = $executeMethod
        retryAuthorized = $false
        qualificationExecutionAuthorized = $false
    })

    $readyDeadline = [DateTime]::UtcNow.AddMinutes(20)
    $nextProgress = [DateTime]::UtcNow.AddSeconds(30)
    while (-not (Test-Path -LiteralPath $readyPath -PathType Leaf)) {
        $unityProcess.Refresh()
        if ($unityProcess.HasExited) { break }
        if ([DateTime]::UtcNow -ge $nextProgress) {
            Write-Output "Unity is compiling the current project for the single algorithm-free known-answer; pid=$processId."
            $nextProgress = [DateTime]::UtcNow.AddSeconds(30)
        }
        Require-Condition ([DateTime]::UtcNow -lt $readyDeadline) 'Unity did not publish the ready snapshot within 20 minutes.'
        Start-Sleep -Milliseconds 250
    }
    Require-Condition (Test-Path -LiteralPath $readyPath -PathType Leaf) 'Unity exited before publishing the ready snapshot.'
    $ready = Get-Content -LiteralPath $readyPath -Raw -Encoding UTF8 | ConvertFrom-Json -Depth 100 -DateKind String
    $unityProcess.Refresh()
    Require-Condition (-not $unityProcess.HasExited) 'Unity exited before live fingerprint capture.'
    Require-Condition ($ready.status -eq 'IN_PROCESS_ALGORITHM_FREE_KNOWN_ANSWER_IDENTITY_READY' -and [int]$ready.processId -eq $processId -and -not [bool]$ready.knownAnswerInvoked) 'In-process ready snapshot identity/status mismatch.'
    Require-Condition ((Test-PathsEqual -Left ([string]$ready.editorApplicationPath) -Right $unityFull) -and (Test-PathsEqual -Left ([string]$ready.processMainModulePath) -Right $unityFull) -and (Test-PathsEqual -Left ([string]$ready.queryFullProcessImageNamePath) -Right $unityFull)) 'In-process Unity path sources disagree.'
    Require-Condition (-not [bool]$ready.activityBoundary.algorithmCodeInvoked -and -not [bool]$ready.activityBoundary.instrumentInvoked -and -not [bool]$ready.activityBoundary.oracleInvoked -and -not [bool]$ready.activityBoundary.emptyBoundaryInvoked -and -not [bool]$ready.activityBoundary.qualificationMeasuredRootCreated -and -not [bool]$ready.activityBoundary.qualificationDeliveryRootCreated) 'Ready snapshot reports prohibited activity.'

    $live = Get-ExternalFingerprint -Path $unityFull -Phase 'EXTERNAL_LIVE_CONCURRENT'
    $live['trustedRuleComparison'] = Assert-TrustedFingerprint -Fingerprint $live -TrustedRule $trustedRule
    $unityProcess.Refresh()
    Require-Condition (-not $unityProcess.HasExited) 'Unity exited during live fingerprint capture.'
    Write-JsonExclusive -Path (Join-Path $attemptRoot 'external-live-fingerprint.v1.json') -Value $live

    $exitDeadline = [DateTime]::UtcNow.AddMinutes(20)
    while (-not $unityProcess.HasExited) {
        Require-Condition ([DateTime]::UtcNow -lt $exitDeadline) 'Unity did not exit naturally within 20 minutes.'
        Start-Sleep -Milliseconds 250
        $unityProcess.Refresh()
    }
    $unityExitCode = $unityProcess.ExitCode
    Require-Condition ($unityExitCode -eq 0) "Unity known-answer exited nonzero: $unityExitCode"
    Require-Condition (Test-Path -LiteralPath $knownAnswerReceiptPath -PathType Leaf) 'Unity known-answer terminal receipt is missing.'

    $post = Get-ExternalFingerprint -Path $unityFull -Phase 'EXTERNAL_POST_EXIT'
    $post['trustedRuleComparison'] = Assert-TrustedFingerprint -Fingerprint $post -TrustedRule $trustedRule
    Require-Condition (Compare-ExternalPhases -Left $pre -Right $live) 'Unity prelaunch/live fingerprints differ.'
    Require-Condition (Compare-ExternalPhases -Left $pre -Right $post) 'Unity prelaunch/post-exit fingerprints differ.'
    Write-JsonExclusive -Path (Join-Path $attemptRoot 'external-post-exit-fingerprint.v1.json') -Value $post

    $receipt = Get-Content -LiteralPath $knownAnswerReceiptPath -Raw -Encoding UTF8 | ConvertFrom-Json -Depth 100 -DateKind String
    Require-Condition ($receipt.status -eq 'PASS_SCHEDULE_NULL_REPLACEMENT_DESERIALIZATION_KNOWN_ANSWER' -and [bool]$receipt.passed) 'Unity known-answer did not return terminal PASS.'
    Require-Condition ([int]$receipt.processId -eq $processId -and (Test-PathsEqual -Left ([string]$receipt.editorApplicationPath) -Right $unityFull) -and (Test-PathsEqual -Left ([string]$receipt.processMainModulePath) -Right $unityFull) -and (Test-PathsEqual -Left ([string]$receipt.queryFullProcessImageNamePath) -Right $unityFull)) 'Unity terminal receipt composite process identity mismatch.'
    Require-Condition ([string]$receipt.runnerSha256 -eq $RunnerSha256 -and [string]$receipt.harnessSha256 -eq $HarnessSha256) 'Unity terminal receipt source hashes mismatch.'
    Require-Condition (@($receipt.cases).Count -eq 5 -and @($receipt.cases | Where-Object { -not [bool]$_.passed }).Count -eq 0) 'One or more authorized known-answer cases failed.'
    $caseIds = @($receipt.cases | ForEach-Object { [string]$_.caseId } | Sort-Object)
    $expectedCaseIds = @('complete-valid-replacement-object','empty-replacement-object','partial-replacement-object','replacement-member-omitted','replacement-null')
    Require-Condition (($caseIds -join '|') -ceq ($expectedCaseIds -join '|')) 'Known-answer case set differs from the five authorized cases.'
    Require-Condition (-not [bool]$receipt.activityBoundary.algorithmCodeInvoked -and -not [bool]$receipt.activityBoundary.instrumentInvoked -and -not [bool]$receipt.activityBoundary.oracleInvoked -and -not [bool]$receipt.activityBoundary.emptyBoundaryInvoked -and -not [bool]$receipt.activityBoundary.qualificationMeasuredRootCreated -and -not [bool]$receipt.activityBoundary.qualificationDeliveryRootCreated -and -not [bool]$receipt.activityBoundary.qualificationObservationProduced -and -not [bool]$receipt.activityBoundary.formalObservationProduced -and -not [bool]$receipt.activityBoundary.analysisRankingWeightingOrWinnerAdjudicationPerformed) 'Unity terminal receipt reports prohibited activity.'

    $editorAssembly = Join-Path $projectRootFull 'Library/ScriptAssemblies/Assembly-CSharp-Editor.dll'
    $runtimeAssembly = Join-Path $projectRootFull 'Library/ScriptAssemblies/Assembly-CSharp.dll'
    Require-Condition (Test-Path -LiteralPath $editorAssembly -PathType Leaf) 'Compiled Assembly-CSharp-Editor.dll is missing.'
    Require-Condition (Test-Path -LiteralPath $runtimeAssembly -PathType Leaf) 'Compiled Assembly-CSharp.dll is missing.'

    $attempt003After = @(Get-Inventory -Root $attempt003Root)
    $measuredAfter = @(Get-Inventory -Root $failedMeasuredRoot)
    $pilotRootsAfter = @(Get-ChildItem -LiteralPath (Split-Path -Parent $failedMeasuredRoot) -Directory -Force | Sort-Object FullName | ForEach-Object { $_.FullName })
    Require-Condition ((Get-InventoryDigest -Inventory $attempt003After) -eq $attempt003BeforeDigest) 'Execution attempt-003 evidence changed.'
    Require-Condition ((Get-InventoryDigest -Inventory $measuredAfter) -eq $measuredBeforeDigest) 'Failed measured root changed.'
    Require-Condition (($pilotRootsAfter -join '|') -ceq ($pilotRootsBefore -join '|')) 'Qualification measured-root directory set changed.'
    Require-Condition (-not (Test-Path -LiteralPath $deliveryRoot)) 'Qualification delivery root was created.'

    Write-JsonExclusive -Path (Join-Path $attemptRoot 'unity-known-answer-adjudication.v1.json') -Value ([ordered]@{
        schema = 'gate14re-me-schedule-null-replacement-deserialization-unity-known-answer-adjudication-v1'
        studyId = $studyId
        authorizationId = $authorizationId
        attemptId = $attemptId
        status = 'PASS_ONE_ALGORITHM_FREE_UNITY_KNOWN_ANSWER_TRUSTED_IDENTITY_NATURAL_EXIT'
        passed = $true
        unityInvocationCount = $unityInvocationCount
        unityProcessId = $processId
        unityExitCode = $unityExitCode
        naturalExitObserved = $true
        signalOrForcedTerminationSent = $false
        retryPerformed = $false
        executeMethod = $executeMethod
        runnerSha256 = $RunnerSha256
        harnessSha256 = $HarnessSha256
        knownAnswerReceiptSha256 = Get-Sha256Lower -Path $knownAnswerReceiptPath
        compiledAssemblies = @(
            [ordered]@{ relativePath = 'Library/ScriptAssemblies/Assembly-CSharp-Editor.dll'; sha256 = Get-Sha256Lower -Path $editorAssembly; lengthBytes = [int64](Get-Item -LiteralPath $editorAssembly).Length },
            [ordered]@{ relativePath = 'Library/ScriptAssemblies/Assembly-CSharp.dll'; sha256 = Get-Sha256Lower -Path $runtimeAssembly; lengthBytes = [int64](Get-Item -LiteralPath $runtimeAssembly).Length }
        )
        externalIdentity = [ordered]@{
            prelaunchLiveStable = Compare-ExternalPhases -Left $pre -Right $live
            prelaunchPostExitStable = Compare-ExternalPhases -Left $pre -Right $post
            expectedSha256 = $expectedUnitySha256
            chunkSizeBytes = $chunkSizeBytes
            chunkCount = [int]$pre.chunkCount
            chunkSetDigestSha256 = [string]$pre.chunkSetDigestSha256
        }
        retainedEvidence = [ordered]@{
            attempt003InventoryDigestBefore = $attempt003BeforeDigest
            attempt003InventoryDigestAfter = Get-InventoryDigest -Inventory $attempt003After
            failedMeasuredRootInventoryDigestBefore = $measuredBeforeDigest
            failedMeasuredRootInventoryDigestAfter = Get-InventoryDigest -Inventory $measuredAfter
            failedMeasuredRootWritableFileCountAfter = @($measuredAfter | Where-Object { -not [bool]$_.readOnly }).Count
        }
        prohibitedActivity = [ordered]@{
            newQualificationMeasuredRootCreated = $false
            qualificationDeliveryRootCreated = $false
            instrumentOracleEmptyBoundaryOrAlgorithmLaneRun = $false
            qualificationOrFormalObservationProduced = $false
            analysisRankingWeightingOrWinnerAdjudicationPerformed = $false
        }
        completedAtUtc = [DateTime]::UtcNow.ToString('o')
    })
}
catch {
    if ($null -ne $unityProcess) {
        $unityProcess.Refresh()
        $naturalWaitDeadline = [DateTime]::UtcNow.AddMinutes(20)
        while (-not $unityProcess.HasExited -and [DateTime]::UtcNow -lt $naturalWaitDeadline) {
            Start-Sleep -Milliseconds 250
            $unityProcess.Refresh()
        }
        if ($unityProcess.HasExited) { $unityExitCode = $unityProcess.ExitCode }
    }
    $failurePath = Join-Path $attemptRoot 'launcher-failure-receipt.v1.json'
    if (-not (Test-Path -LiteralPath $failurePath)) {
        Write-JsonExclusive -Path $failurePath -Value ([ordered]@{
            schema = 'gate14re-me-schedule-null-replacement-deserialization-launcher-failure-receipt-v1'
            studyId = $studyId
            authorizationId = $authorizationId
            attemptId = $attemptId
            status = 'FAILED_CLOSED_NO_RETRY'
            exactFailure = $_.Exception.GetType().FullName + ': ' + $_.Exception.Message
            unityInvocationCount = $unityInvocationCount
            unityExitCode = $unityExitCode
            retryPerformed = $false
            signalOrForcedTerminationSent = $false
            failedAtUtc = [DateTime]::UtcNow.ToString('o')
        })
    }
    throw
}
