[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$ProjectRoot,
    [Parameter(Mandatory = $true)][string]$MeasuredRoot,
    [Parameter(Mandatory = $true)][string]$DeliveryRoot,
    [Parameter(Mandatory = $true)][string]$ExecutionAuthorization,
    [Parameter(Mandatory = $true)][ValidatePattern('^[0-9a-f]{64}$')][string]$ExecutionAuthorizationSha256,
    [Parameter(Mandatory = $true)][string]$ImplementationManifest,
    [Parameter(Mandatory = $true)][ValidatePattern('^[0-9a-f]{64}$')][string]$ImplementationManifestSha256,
    [Parameter(Mandatory = $true)][string]$ExecutionContract,
    [Parameter(Mandatory = $true)][ValidatePattern('^[0-9a-f]{64}$')][string]$ExecutionContractSha256,
    [Parameter(Mandatory = $true)][string]$PlanningAssetsManifest,
    [Parameter(Mandatory = $true)][ValidatePattern('^[0-9a-f]{64}$')][string]$PlanningAssetsManifestSha256,
    [Parameter(Mandatory = $true)][string]$ResourceBudget,
    [Parameter(Mandatory = $true)][ValidatePattern('^[0-9a-f]{64}$')][string]$ResourceBudgetSha256,
    [Parameter(Mandatory = $true)][string]$FairnessBinding,
    [Parameter(Mandatory = $true)][ValidatePattern('^[0-9a-f]{64}$')][string]$FairnessBindingSha256,
    [Parameter(Mandatory = $true)][string]$Schedule,
    [Parameter(Mandatory = $true)][ValidatePattern('^[0-9a-f]{64}$')][string]$ScheduleSha256,
    [Parameter(Mandatory = $true)][string]$OutputSchema,
    [Parameter(Mandatory = $true)][ValidatePattern('^[0-9a-f]{64}$')][string]$OutputSchemaSha256,
    [Parameter(Mandatory = $true)][string]$InstrumentContract,
    [Parameter(Mandatory = $true)][ValidatePattern('^[0-9a-f]{64}$')][string]$InstrumentContractSha256,
    [Parameter(Mandatory = $true)][string]$D3Contract,
    [Parameter(Mandatory = $true)][ValidatePattern('^[0-9a-f]{64}$')][string]$D3ContractSha256,
    [Parameter(Mandatory = $true)][string]$TypedParquetRuntimeManifest,
    [Parameter(Mandatory = $true)][ValidatePattern('^[0-9a-f]{64}$')][string]$TypedParquetRuntimeManifestSha256,
    [Parameter(Mandatory = $true)][string]$StructuralTool,
    [Parameter(Mandatory = $true)][ValidatePattern('^[0-9a-f]{64}$')][string]$StructuralToolSha256,
    [Parameter(Mandatory = $true)][string]$DeliveryTool,
    [Parameter(Mandatory = $true)][ValidatePattern('^[0-9a-f]{64}$')][string]$DeliveryToolSha256,
    [Parameter(Mandatory = $true)][string]$TrustedIdentityRule,
    [Parameter(Mandatory = $true)][ValidatePattern('^[0-9a-f]{64}$')][string]$TrustedIdentityRuleSha256,
    [Parameter(Mandatory = $true)][string]$TimestampComparator,
    [Parameter(Mandatory = $true)][ValidatePattern('^[0-9a-f]{64}$')][string]$TimestampComparatorSha256,
    [Parameter(Mandatory = $true)][string]$PythonExecutable,
    [Parameter(Mandatory = $true)][ValidatePattern('^[0-9a-f]{64}$')][string]$PythonExecutableSha256,
    [Parameter(Mandatory = $true)][string]$UnityExecutable,
    [Parameter(Mandatory = $true)][ValidatePattern('^[0-9a-f]{64}$')][string]$UnityExecutableSha256
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$studyId = 'Gate14Re-ME'
$runnerMethod = 'DDM.Research.Editor.Gate14ReMELoadQualificationRunnerV2.Run'
$reservedMeasuredRootRelativePath = 'Research/PilotRuns/Gate14Re-ME/load-qualification/attempt-001'
$reservedDeliveryRootRelativePath = 'Research/Exports/Gate14Re-ME/load-qualification/attempt-001'
$expectedAlgorithms = @('A*-R', 'BiA*-R', 'D*L', 'LPA*', 'C-FF', 'IDFF')
$expectedAnonymousLanes = @('ALG-A', 'ALG-B', 'ALG-C', 'ALG-D', 'ALG-E', 'ALG-F')
$chunkSizeBytes = 65536
$processOrdinal = 0
$measuredRootCreated = $false
$deliveryRootCreated = $false
$currentMode = 'PREFLIGHT'

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

function Assert-InsideProject {
    param([string]$Path, [string]$Root, [string]$Label)
    $prefix = $Root.TrimEnd([System.IO.Path]::DirectorySeparatorChar) + [System.IO.Path]::DirectorySeparatorChar
    Require-Condition $Path.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase) "$Label resolves outside the project root."
}

function Get-Sha256Lower {
    param([string]$Path)
    Require-Condition (Test-Path -LiteralPath $Path -PathType Leaf) "Required file is missing: $Path"
    return (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToLowerInvariant()
}

function Get-DotNetSha256Lower {
    param([string]$Path)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    $stream = [System.IO.FileStream]::new($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite -bor [System.IO.FileShare]::Delete)
    try { return [Convert]::ToHexString($sha.ComputeHash($stream)).ToLowerInvariant() }
    finally { $stream.Dispose(); $sha.Dispose() }
}

function Assert-Hash {
    param([string]$Path, [string]$Expected, [string]$Label)
    $actual = Get-Sha256Lower -Path $Path
    Require-Condition ($actual -eq $Expected) "$Label SHA-256 mismatch: expected $Expected; actual $actual"
}

function Read-Json {
    param([string]$Path)
    return Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json -Depth 100 -DateKind String
}

function Write-JsonExclusive {
    param([string]$Path, [object]$Value)
    Require-Condition (-not (Test-Path -LiteralPath $Path)) "Refusing to overwrite evidence: $Path"
    $parent = Split-Path -Parent $Path
    Require-Condition (Test-Path -LiteralPath $parent -PathType Container) "Evidence parent is missing: $parent"
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

function Append-JsonLine {
    param([string]$Path, [object]$Value)
    $line = ($Value | ConvertTo-Json -Depth 100 -Compress) + [Environment]::NewLine
    $encoding = [System.Text.UTF8Encoding]::new($false)
    $stream = [System.IO.File]::Open($Path, [System.IO.FileMode]::Append, [System.IO.FileAccess]::Write, [System.IO.FileShare]::Read)
    try {
        $writer = [System.IO.StreamWriter]::new($stream, $encoding)
        try { $writer.Write($line); $writer.Flush() }
        finally { $writer.Dispose() }
    }
    finally { $stream.Dispose() }
}

function ConvertTo-CommandLineArgument {
    param([string]$Value)
    if ($Value -notmatch '[\s"]') { return $Value }
    return '"' + ($Value -replace '(\\*)"', '$1$1\"' -replace '(\\+)$', '$1$1') + '"'
}

function Get-ChunkHashes {
    param([string]$Path)
    $chunks = [System.Collections.Generic.List[object]]::new()
    $stream = [System.IO.FileStream]::new($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite -bor [System.IO.FileShare]::Delete)
    try {
        $buffer = [byte[]]::new($script:chunkSizeBytes)
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
            $chunks.Add([pscustomobject][ordered]@{ chunkIndex = $index; offsetBytes = $offset; lengthBytes = $count; sha256 = $digest })
            $index++
            $offset += $count
            if ($count -lt $buffer.Length) { break }
        }
    }
    finally { $stream.Dispose() }
    return @($chunks)
}

function Get-NtfsFileIdentity {
    param([string]$Path)
    $lines = @(& "$env:SystemRoot\System32\fsutil.exe" file queryfileid $Path 2>&1 | ForEach-Object { [string]$_ })
    $exitCode = $LASTEXITCODE
    $raw = $lines -join [Environment]::NewLine
    $match = [regex]::Match($raw, '0x[0-9A-Fa-f]+')
    $hex = if ($match.Success) { $match.Value.Substring(2).ToLowerInvariant() } else { $null }
    return [pscustomobject][ordered]@{
        succeeded = ($exitCode -eq 0 -and $match.Success)
        fileIdHex = $hex
        fileIndexLow64Hex = if ($match.Success) { if ($hex.Length -gt 16) { $hex.Substring($hex.Length - 16) } else { $hex.PadLeft(16, '0') } } else { $null }
        fsutilExitCode = $exitCode
        fsutilOutput = $raw
    }
}

function Get-PeIdentity {
    param([string]$Path)
    $result = [ordered]@{ succeeded = $false; peHeaderOffset = $null; optionalHeaderMagicHex = $null; checksumFieldOffset = $null; checksumHex = $null; securityDirectoryFieldOffset = $null; certificateTableFileOffset = $null; certificateTableSizeBytes = $null; exactFailure = $null }
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
                $securityDirectoryOffset = $optionalHeaderOffset + $(if ($magic -eq 0x20b) { 112 } else { 96 }) + 32
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

function Get-UnityFingerprint {
    param([string]$Path, [string]$Phase)
    $item = Get-Item -LiteralPath $Path -Force
    $signature = Get-AuthenticodeSignature -LiteralPath $Path
    $hashOne = Get-Sha256Lower -Path $Path
    $hashTwo = Get-DotNetSha256Lower -Path $Path
    return [pscustomobject][ordered]@{
        schema = 'gate14re-me-unity-executable-operational-fingerprint-v2'
        studyId = $script:studyId
        phase = $Phase
        capturedAtUtc = [DateTime]::UtcNow.ToString('o')
        path = $item.FullName.Replace('\', '/')
        lengthBytes = [int64]$item.Length
        creationTimeUtc = $item.CreationTimeUtc.ToString('o')
        lastWriteTimeUtc = $item.LastWriteTimeUtc.ToString('o')
        attributes = $item.Attributes.ToString()
        reparsePoint = (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0)
        fileIdentity = Get-NtfsFileIdentity -Path $item.FullName
        peIdentity = Get-PeIdentity -Path $item.FullName
        authenticode = [pscustomobject][ordered]@{
            status = $signature.Status.ToString()
            signerSubject = if ($null -ne $signature.SignerCertificate) { $signature.SignerCertificate.Subject } else { $null }
            signerThumbprint = if ($null -ne $signature.SignerCertificate) { $signature.SignerCertificate.Thumbprint } else { $null }
        }
        fullFileHashes = @(
            [pscustomobject][ordered]@{ method = 'powershell-get-filehash'; sha256 = $hashOne },
            [pscustomobject][ordered]@{ method = 'dotnet-sha256-filestream'; sha256 = $hashTwo }
        )
        independentHashMethodsAgree = ($hashOne -eq $hashTwo)
        chunkSizeBytes = $script:chunkSizeBytes
        chunkHashes = @(Get-ChunkHashes -Path $item.FullName)
    }
}

function Get-FingerprintHash {
    param([object]$Fingerprint, [string]$Method)
    $items = @($Fingerprint.fullFileHashes | Where-Object { $_.method -eq $Method })
    Require-Condition ($items.Count -eq 1 -and [string]$items[0].sha256 -match '^[0-9a-f]{64}$') "Fingerprint is missing hash method $Method."
    return [string]$items[0].sha256
}

function Compare-SerializedValue {
    param([object]$Left, [object]$Right)
    return (($Left | ConvertTo-Json -Depth 100 -Compress) -ceq ($Right | ConvertTo-Json -Depth 100 -Compress))
}

function Assert-FingerprintAgainstRule {
    param([object]$Fingerprint, [object]$Rule, [string]$Phase)
    $app = $Rule.applicability
    Require-Condition $Fingerprint.independentHashMethodsAgree "$Phase external hash methods disagree."
    Require-Condition ((Get-FingerprintHash -Fingerprint $Fingerprint -Method 'powershell-get-filehash') -eq [string]$app.unityExecutableExpectedSha256) "$Phase Unity SHA-256 mismatch."
    Require-Condition (-not $Fingerprint.reparsePoint) "$Phase Unity executable is a reparse point."
    Require-Condition $Fingerprint.fileIdentity.succeeded "$Phase NTFS file identity is unavailable."
    Require-Condition ([string]$Fingerprint.fileIdentity.fileIdHex -eq [string]$app.ntfsFileIdHex) "$Phase NTFS file ID mismatch."
    Require-Condition ([string]$Fingerprint.fileIdentity.fileIndexLow64Hex -eq [string]$app.ntfsFileIndexLow64Hex) "$Phase NTFS low-64 file index mismatch."
    Require-Condition $Fingerprint.peIdentity.succeeded "$Phase PE identity is unavailable."
    Require-Condition ([string]$Fingerprint.authenticode.status -eq 'Valid') "$Phase Authenticode status is not valid."
    Require-Condition ([string]$Fingerprint.authenticode.signerSubject -eq [string]$app.signerSubject) "$Phase signer subject mismatch."
    Require-Condition ([string]$Fingerprint.authenticode.signerThumbprint -eq [string]$app.signerThumbprint) "$Phase signer thumbprint mismatch."
    Require-Condition ([int64]$Fingerprint.lengthBytes -eq [int64]$app.fileLengthBytes) "$Phase Unity file length mismatch."
    Require-Condition ([System.IO.Path]::GetFullPath([string]$Fingerprint.path).TrimEnd('\') -ieq [System.IO.Path]::GetFullPath([string]$app.unityExecutablePath).TrimEnd('\')) "$Phase Unity path mismatch."
    $creation = Compare-Gate14ReMETrustedTimestampV1 -TrustedText ([string]$app.creationTimeUtc) -ObservedText ([string]$Fingerprint.creationTimeUtc)
    $lastWrite = Compare-Gate14ReMETrustedTimestampV1 -TrustedText ([string]$app.lastWriteTimeUtc) -ObservedText ([string]$Fingerprint.lastWriteTimeUtc)
    Require-Condition $creation.comparisonAccepted "$Phase Unity creation timestamp mismatch: $($creation.failureCode)"
    Require-Condition $lastWrite.comparisonAccepted "$Phase Unity last-write timestamp mismatch: $($lastWrite.failureCode)"
}

function Assert-FingerprintStable {
    param([object]$Reference, [object]$Observed, [string]$Phase)
    Require-Condition ([string]$Reference.path -ieq [string]$Observed.path) "$Phase path changed."
    Require-Condition ([int64]$Reference.lengthBytes -eq [int64]$Observed.lengthBytes) "$Phase length changed."
    Require-Condition ([string]$Reference.fileIdentity.fileIdHex -eq [string]$Observed.fileIdentity.fileIdHex) "$Phase file ID changed."
    Require-Condition (Compare-SerializedValue -Left $Reference.peIdentity -Right $Observed.peIdentity) "$Phase PE identity changed."
    Require-Condition (Compare-SerializedValue -Left $Reference.authenticode -Right $Observed.authenticode) "$Phase Authenticode identity changed."
    Require-Condition (Compare-SerializedValue -Left @($Reference.chunkHashes) -Right @($Observed.chunkHashes)) "$Phase 64 KiB chunk digest set changed."
}

function Get-CommonRunnerArguments {
    param([string]$Mode, [string]$OutputDirectory, [string]$LogPath)
    return @(
        '-batchmode', '-nographics', '-quit', '-projectPath', $script:projectRootFull,
        '-logFile', $LogPath, '-executeMethod', $script:runnerMethod,
        '--g14me-mode', $Mode, '--g14me-output-dir', $OutputDirectory,
        '--g14me-execution-authorization', $script:authorizationFull,
        '--g14me-execution-authorization-sha256', $script:ExecutionAuthorizationSha256,
        '--g14me-implementation-manifest', $script:manifestFull,
        '--g14me-implementation-manifest-sha256', $script:ImplementationManifestSha256,
        '--g14me-resource-budget', $script:budgetFull,
        '--g14me-resource-budget-sha256', $script:ResourceBudgetSha256,
        '--g14me-fairness-binding', $script:fairnessFull,
        '--g14me-fairness-binding-sha256', $script:FairnessBindingSha256,
        '--g14me-schedule', $script:scheduleFull,
        '--g14me-schedule-sha256', $script:ScheduleSha256
    )
}

function Invoke-VerifiedFreshUnityProcess {
    param([string]$Mode, [string]$OutputDirectory, [string[]]$AdditionalArguments, [int64]$TimeoutMilliseconds)
    Require-Condition (-not (Test-Path -LiteralPath $OutputDirectory)) "Fresh process output already exists: $OutputDirectory"
    $script:currentMode = $Mode
    $ordinal = $script:processOrdinal
    $script:processOrdinal++
    $identityPath = Join-Path $script:processIdentityRoot ('process-{0:D4}.identity.v2.json' -f $ordinal)
    $logPath = Join-Path $script:unityLogRoot ('process-{0:D4}.unity.log' -f $ordinal)
    $pre = Get-UnityFingerprint -Path $script:unityFull -Phase 'PRELAUNCH'
    Assert-FingerprintAgainstRule -Fingerprint $pre -Rule $script:identityRule -Phase 'prelaunch'
    Require-Condition (@(Get-CimInstance Win32_Process -Filter "Name = 'Unity.exe'").Count -eq 0) 'Another Unity process is active; composite attribution is not unique.'

    $arguments = @(Get-CommonRunnerArguments -Mode $Mode -OutputDirectory $OutputDirectory -LogPath $logPath) + $AdditionalArguments
    $argumentLine = ($arguments | ForEach-Object { ConvertTo-CommandLineArgument -Value ([string]$_) }) -join ' '
    # CreateProcess records the executable image as a quoted first token even
    # when its path has no whitespace. Freeze that exact representation.
    $expectedCommandLine = '"' + $script:unityFull + '" ' + $argumentLine
    $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $script:unityFull
    $startInfo.Arguments = $argumentLine
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $launchedAtUtc = [DateTime]::UtcNow
    $process = [System.Diagnostics.Process]::Start($startInfo)
    Require-Condition ($null -ne $process) 'Unity process creation returned null.'
    $processId = $process.Id
    $liveMetadata = $null
    for ($poll = 0; $poll -lt 100 -and $null -eq $liveMetadata; $poll++) {
        $liveMetadata = Get-CimInstance Win32_Process -Filter "ProcessId = $processId"
        if ($null -eq $liveMetadata) { Start-Sleep -Milliseconds 50 }
    }
    Require-Condition ($null -ne $liveMetadata) 'Unable to capture live Unity process metadata.'
    $creationTimeUtc = ([DateTime]$liveMetadata.CreationDate).ToUniversalTime()
    $startDeltaMilliseconds = [Math]::Abs(($creationTimeUtc - $launchedAtUtc).TotalMilliseconds)
    Require-Condition ($startDeltaMilliseconds -le 1000.0) "Unity creation time differs from controller launch time by $startDeltaMilliseconds ms."
    Require-Condition ([System.IO.Path]::GetFullPath([string]$liveMetadata.ExecutablePath).TrimEnd('\') -ieq $script:unityFull) 'Live Unity executable path mismatch.'
    Require-Condition ([string]$liveMetadata.CommandLine -ceq $expectedCommandLine) 'Live Unity command line differs from the exact controller command line.'
    Require-Condition ([string]$liveMetadata.CommandLine -like "*$script:runnerMethod*") 'Live Unity command line lacks RunnerV2.'
    Require-Condition ([string]$liveMetadata.CommandLine -like "*$script:measuredRootFull*") 'Live Unity command line lacks the exact measured root output.'
    $live = Get-UnityFingerprint -Path $script:unityFull -Phase 'LIVE_CONCURRENT'
    Assert-FingerprintAgainstRule -Fingerprint $live -Rule $script:identityRule -Phase 'live'
    Assert-FingerprintStable -Reference $pre -Observed $live -Phase 'live'

    $exitedNaturally = $process.WaitForExit([int]$TimeoutMilliseconds)
    Require-Condition $exitedNaturally "Unity exceeded the frozen timeout without receiving a signal: mode=$Mode pid=$processId timeoutMs=$TimeoutMilliseconds"
    $exitCode = $process.ExitCode
    $exitedAtUtc = [DateTime]::UtcNow
    $post = Get-UnityFingerprint -Path $script:unityFull -Phase 'POST_EXIT'
    Assert-FingerprintAgainstRule -Fingerprint $post -Rule $script:identityRule -Phase 'post-exit'
    Assert-FingerprintStable -Reference $pre -Observed $post -Phase 'post-exit'
    Require-Condition ($exitCode -eq 0) "Unity exited nonzero: mode=$Mode pid=$processId exitCode=$exitCode"
    Require-Condition (@(Get-CimInstance Win32_Process -Filter "ProcessId = $processId").Count -eq 0) 'Unity PID still exists after WaitForExit.'

    Write-JsonExclusive -Path $identityPath -Value ([ordered]@{
        schema = 'gate14re-me-qualified-unity-process-identity-receipt-v2'
        studyId = $script:studyId
        status = 'PASS_TRUSTED_THREE_PHASE_COMPOSITE_IDENTITY_NATURAL_EXIT'
        ordinal = $ordinal
        mode = $Mode
        processId = $processId
        creationTimeUtc = $creationTimeUtc.ToString('o')
        launchedAtUtc = $launchedAtUtc.ToString('o')
        exitedAtUtc = $exitedAtUtc.ToString('o')
        processStartDeltaMilliseconds = $startDeltaMilliseconds
        executablePath = ([string]$liveMetadata.ExecutablePath).Replace('\', '/')
        exactCommandLine = [string]$liveMetadata.CommandLine
        exactCommandLineSha256 = Get-StringSha256Lower -Value ([string]$liveMetadata.CommandLine)
        executeMethod = $script:runnerMethod
        outputRelativePath = Get-ProjectRelativePath -Path $OutputDirectory -Root $script:projectRootFull
        exitCode = $exitCode
        naturalExit = $true
        signalOrForcedTerminationSent = $false
        retryPerformed = $false
        trustedIdentityRuleSha256 = $script:TrustedIdentityRuleSha256
        timestampComparatorSha256 = $script:TimestampComparatorSha256
        prelaunchFingerprint = $pre
        liveConcurrentFingerprint = $live
        postExitFingerprint = $post
    })
    Append-JsonLine -Path $script:processLedger -Value ([ordered]@{
        schema = 'gate14re-me-process-ledger-row-v2'
        ordinal = $ordinal
        mode = $Mode
        processId = $processId
        creationTimeUtc = $creationTimeUtc.ToString('o')
        exitedAtUtc = $exitedAtUtc.ToString('o')
        exitCode = $exitCode
        identityReceiptRelativePath = Get-ProjectRelativePath -Path $identityPath -Root $script:projectRootFull
        identityReceiptSha256 = Get-Sha256Lower -Path $identityPath
        state = 'EXITED_ZERO_TRUSTED_IDENTITY'
    })
}

function Get-StringSha256Lower {
    param([string]$Value)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try { return [Convert]::ToHexString($sha.ComputeHash([System.Text.UTF8Encoding]::new($false).GetBytes($Value))).ToLowerInvariant() }
    finally { $sha.Dispose() }
}

function Assert-Receipt {
    param([string]$Path, [string]$ExpectedStatus)
    Require-Condition (Test-Path -LiteralPath $Path -PathType Leaf) "Required receipt is missing: $Path"
    $receipt = Read-Json -Path $Path
    Require-Condition ([string]$receipt.status -eq $ExpectedStatus) "Receipt has unexpected status at ${Path}: $($receipt.status)"
    return $receipt
}

function Invoke-Superblock {
    param([object]$Record, [string]$InputFull)
    $superblockRoot = Join-Path $script:measuredRootFull "raw/superblocks/$($Record.superblockId)"
    Require-Condition (-not (Test-Path -LiteralPath $superblockRoot)) "Superblock output already exists: $superblockRoot"
    $null = New-Item -ItemType Directory -Path $superblockRoot
    try {
        foreach ($lane in $Record.algorithmOrder) {
            $laneOutput = Join-Path $superblockRoot ([string]$lane.anonymousLaneId)
            $oracleReceipt = Join-Path $script:measuredRootFull "oracle/$($Record.superblockId)/oracle-pass-receipt.v1.json"
            $oracleReceiptSha = Get-Sha256Lower -Path $oracleReceipt
            Invoke-VerifiedFreshUnityProcess -Mode 'lane' -OutputDirectory $laneOutput -TimeoutMilliseconds ([int64]$script:budget.laneWallClockHardTimeoutMilliseconds) -AdditionalArguments @(
                '--g14me-input', $InputFull,
                '--g14me-oracle-receipt', $oracleReceipt,
                '--g14me-oracle-receipt-sha256', $oracleReceiptSha,
                '--g14me-algorithm-id', [string]$lane.algorithmId,
                '--g14me-anonymous-lane-id', [string]$lane.anonymousLaneId,
                '--g14me-identity-binding-sha256', [string]$lane.identityBindingSha256
            )
            $null = Assert-Receipt -Path (Join-Path $laneOutput 'lane-receipt.v2.json') -ExpectedStatus 'COMPLETE_RAW_LANE'
        }
        Write-JsonExclusive -Path (Join-Path $superblockRoot 'accepted-superblock-receipt.v1.json') -Value ([ordered]@{
            schema = 'gate14re-me-accepted-superblock-receipt-v1'
            studyId = $script:studyId
            status = 'ACCEPTED_COMPLETE_SIX_LANE_SUPERBLOCK'
            plannedSuperblockId = [string]$Record.superblockId
            instanceId = [string]$Record.superblockId
            isReplacement = $false
            acceptedAnonymousLanes = 6
            createdAtUtc = [DateTime]::UtcNow.ToString('o')
        })
    }
    catch {
        Append-JsonLine -Path $script:voidLedger -Value ([ordered]@{
            schema = 'gate14re-me-whole-superblock-void-row-v1'
            recordId = "void:$($Record.superblockId):$($Record.superblockId)"
            plannedSuperblockId = [string]$Record.superblockId
            instanceId = [string]$Record.superblockId
            isReplacement = $false
            status = 'VOID_WHOLE_SUPERBLOCK_TECHNICAL_FAILURE'
            reason = $_.Exception.Message
            createdAtUtc = [DateTime]::UtcNow.ToString('o')
        })
        throw [System.InvalidOperationException]::new("Whole superblock failed; zero-replacement fail-stop is frozen: $($Record.superblockId). $($_.Exception.Message)")
    }
}

function Invoke-JsonTool {
    param([string]$ToolPath, [string[]]$Arguments, [string]$Label)
    $output = @(& $script:pythonFull $ToolPath @Arguments 2>&1 | ForEach-Object { [string]$_ })
    $exitCode = $LASTEXITCODE
    Require-Condition ($exitCode -eq 0) "$Label exited nonzero ($exitCode): $($output -join [Environment]::NewLine)"
    $text = $output -join [Environment]::NewLine
    try { return $text | ConvertFrom-Json -Depth 100 -DateKind String }
    catch { throw [System.InvalidOperationException]::new("$Label did not emit one valid JSON receipt: $text") }
}

# Read-only preflight: no measured or delivery root may be created before every binding passes.
$projectRootFull = Get-NormalizedFullPath -Path $ProjectRoot -Base (Get-Location).Path
Require-Condition (Test-Path -LiteralPath $projectRootFull -PathType Container) 'Project root does not exist.'
$measuredRootFull = Get-NormalizedFullPath -Path $MeasuredRoot -Base $projectRootFull
$deliveryRootFull = Get-NormalizedFullPath -Path $DeliveryRoot -Base $projectRootFull
Assert-InsideProject -Path $measuredRootFull -Root $projectRootFull -Label 'Measured root'
Assert-InsideProject -Path $deliveryRootFull -Root $projectRootFull -Label 'Delivery root'
Require-Condition ((Get-ProjectRelativePath -Path $measuredRootFull -Root $projectRootFull) -ceq $reservedMeasuredRootRelativePath) 'Measured root differs from the frozen attempt-001 path.'
Require-Condition ((Get-ProjectRelativePath -Path $deliveryRootFull -Root $projectRootFull) -ceq $reservedDeliveryRootRelativePath) 'Delivery root differs from the frozen attempt-001 delivery path.'
Require-Condition (-not (Test-Path -LiteralPath $measuredRootFull)) 'Measured root already exists; retry/resume/overwrite are prohibited.'
Require-Condition (-not (Test-Path -LiteralPath $deliveryRootFull)) 'Delivery root already exists; retry/resume/overwrite are prohibited.'

$bindings = @(
    @{ Variable = 'authorizationFull'; Path = $ExecutionAuthorization; Hash = $ExecutionAuthorizationSha256; Label = 'execution authorization' },
    @{ Variable = 'manifestFull'; Path = $ImplementationManifest; Hash = $ImplementationManifestSha256; Label = 'implementation manifest v3' },
    @{ Variable = 'executionContractFull'; Path = $ExecutionContract; Hash = $ExecutionContractSha256; Label = 'execution contract v3' },
    @{ Variable = 'planningAssetsManifestFull'; Path = $PlanningAssetsManifest; Hash = $PlanningAssetsManifestSha256; Label = 'planning-assets manifest' },
    @{ Variable = 'budgetFull'; Path = $ResourceBudget; Hash = $ResourceBudgetSha256; Label = 'resource budget' },
    @{ Variable = 'fairnessFull'; Path = $FairnessBinding; Hash = $FairnessBindingSha256; Label = 'fairness binding' },
    @{ Variable = 'scheduleFull'; Path = $Schedule; Hash = $ScheduleSha256; Label = 'qualification schedule' },
    @{ Variable = 'outputSchemaFull'; Path = $OutputSchema; Hash = $OutputSchemaSha256; Label = 'output schema v3' },
    @{ Variable = 'instrumentContractFull'; Path = $InstrumentContract; Hash = $InstrumentContractSha256; Label = 'instrument contract v3' },
    @{ Variable = 'd3ContractFull'; Path = $D3Contract; Hash = $D3ContractSha256; Label = 'qualified D3-v3.1 contract' },
    @{ Variable = 'parquetManifestFull'; Path = $TypedParquetRuntimeManifest; Hash = $TypedParquetRuntimeManifestSha256; Label = 'typed-Parquet runtime manifest' },
    @{ Variable = 'structuralToolFull'; Path = $StructuralTool; Hash = $StructuralToolSha256; Label = 'structural-v3 tool' },
    @{ Variable = 'deliveryToolFull'; Path = $DeliveryTool; Hash = $DeliveryToolSha256; Label = 'delivery-v2.1 schema-v3 adapter' },
    @{ Variable = 'identityRuleFull'; Path = $TrustedIdentityRule; Hash = $TrustedIdentityRuleSha256; Label = 'trusted Unity identity rule' },
    @{ Variable = 'timestampComparatorFull'; Path = $TimestampComparator; Hash = $TimestampComparatorSha256; Label = 'attempt-007 timestamp comparator' },
    @{ Variable = 'pythonFull'; Path = $PythonExecutable; Hash = $PythonExecutableSha256; Label = 'Python executable' },
    @{ Variable = 'unityFull'; Path = $UnityExecutable; Hash = $UnityExecutableSha256; Label = 'Unity executable' }
)
foreach ($binding in $bindings) {
    $full = Get-NormalizedFullPath -Path ([string]$binding.Path) -Base $projectRootFull
    Set-Variable -Scope Script -Name ([string]$binding.Variable) -Value $full
    Assert-Hash -Path $full -Expected ([string]$binding.Hash) -Label ([string]$binding.Label)
}
. $timestampComparatorFull
Require-Condition ($null -ne (Get-Command Compare-Gate14ReMETrustedTimestampV1 -ErrorAction SilentlyContinue)) 'Timestamp comparator function did not load.'

$authorization = Read-Json -Path $authorizationFull
$manifest = Read-Json -Path $manifestFull
$contract = Read-Json -Path $executionContractFull
$planningAssets = Read-Json -Path $planningAssetsManifestFull
$budget = Read-Json -Path $budgetFull
$fairness = Read-Json -Path $fairnessFull
$identityRule = Read-Json -Path $identityRuleFull
Require-Condition ($authorization.schema -eq 'gate14re-me-load-qualification-execution-authorization-v1' -and $authorization.studyId -eq $studyId -and $authorization.status -eq 'AUTHORIZED_LOAD_QUALIFICATION_EXECUTION') 'Execution authorization header is invalid.'
Require-Condition ($authorization.qualificationInputGenerationAuthorized -and $authorization.qualificationRootCreationAuthorized -and $authorization.compileOrUnityExecutionAuthorized -and $authorization.qualificationExecutionAuthorized -and $authorization.deliveryConstructionAuthorized) 'Execution authorization omits a required qualification permission.'
Require-Condition (-not $authorization.formalCollectionAuthorized -and -not $authorization.formalAnalysisAuthorized -and -not $authorization.rankingAuthorized -and -not $authorization.winnerAdjudicationAuthorized) 'Execution authorization exceeds the qualification-only boundary.'
Require-Condition ($authorization.measuredRootRelativePath.Replace('\', '/') -ceq $reservedMeasuredRootRelativePath -and $authorization.deliveryRootRelativePath.Replace('\', '/') -ceq $reservedDeliveryRootRelativePath) 'Execution authorization root binding mismatch.'
Require-Condition ($authorization.implementationManifestSha256 -eq $ImplementationManifestSha256 -and $authorization.executionContractSha256 -eq $ExecutionContractSha256 -and $authorization.scheduleSha256 -eq $ScheduleSha256) 'Execution authorization artifact-hash binding mismatch.'
Require-Condition ($manifest.schema -eq 'gate14re-me-qualification-implementation-manifest-v1' -and $manifest.status -eq 'FROZEN_IMPLEMENTATION_SOURCE_ONLY_UNCOMPILED') 'RunnerV2 compatibility fields in implementation manifest v3 are invalid.'
Require-Condition ($manifest.manifestGeneration -eq 4 -and $manifest.manifestSchemaV3 -eq 'gate14re-me-qualification-current-implementation-manifest-v3' -and $manifest.executionReadinessStatus -eq 'FROZEN_CURRENT_IMPLEMENTATION_COMPILED_TERMINAL_CHAIN_CORRECTED_POWERSHELL_7_6_5_HOST_BOUND_OFFLINE') 'Authoritative implementation manifest v3 state is not adopted.'
Require-Condition ($contract.schema -eq 'gate14re-me-load-qualification-execution-contract-v3' -and $contract.status -eq 'FROZEN_EXECUTION_BINDING_V3_TERMINAL_CHAIN_CORRECTED_QUALIFICATION_EXECUTION_UNAUTHORIZED') 'Execution contract v3 header is invalid.'
Require-Condition ($planningAssets.schema -eq 'gate14re-me-qualification-planning-asset-generation-v2-freeze-manifest-v1' -and $planningAssets.status -eq 'FROZEN_PLANNING_ASSETS_PASS') 'Planning assets are not terminally frozen.'
Require-Condition ($budget.status -eq 'FROZEN_PREEXECUTION_BUDGETS' -and [int]$budget.maximumConcurrentUnityProcesses -eq 1) 'Resource budget serial-process rule mismatch.'
Require-Condition ([int]$budget.maximumWholeSuperblockTechnicalReplacements -ge 0) 'Resource budget replacement field is malformed.'
Require-Condition ($fairness.status -eq 'FROZEN_SIX_ALGORITHM_BINDING' -and @($fairness.algorithms).Count -eq 6) 'Six-algorithm fairness binding mismatch.'
Require-Condition ($identityRule.schema -eq 'gate14re-me-unity-executable-identity-verification-rule-v1' -and $identityRule.status -eq 'FROZEN_TRUSTED_IDENTITY_RULE_FROM_OFFLINE_ADJUDICATION') 'Trusted identity rule header mismatch.'
Require-Condition ([string]$identityRule.applicability.unityExecutableExpectedSha256 -eq $UnityExecutableSha256) 'Trusted identity rule Unity hash mismatch.'

$supervisorSelfRelative = Get-ProjectRelativePath -Path $PSCommandPath -Root $projectRootFull
Require-Condition ([string]$contract.entryPoint.supervisorRelativePath -ceq $supervisorSelfRelative) 'Execution contract supervisor path does not identify this exact script.'
Assert-Hash -Path $PSCommandPath -Expected ([string]$contract.entryPoint.supervisorSha256) -Label 'supervisor v3 self-binding'
$runnerFull = Get-NormalizedFullPath -Path ([string]$contract.entryPoint.runnerRelativePath) -Base $projectRootFull
Assert-InsideProject -Path $runnerFull -Root $projectRootFull -Label 'RunnerV2 source'
Assert-Hash -Path $runnerFull -Expected ([string]$contract.entryPoint.runnerSha256) -Label 'RunnerV2 source'

$contractFrozenBindings = [System.Collections.Generic.List[object]]::new()
foreach ($property in $contract.frozenBindings.PSObject.Properties) {
    $frozenBinding = $property.Value
    Require-Condition (-not [string]::IsNullOrWhiteSpace([string]$frozenBinding.relativePath)) "Execution contract frozen binding lacks a relative path: $($property.Name)"
    Require-Condition ([string]$frozenBinding.sha256 -match '^[0-9a-f]{64}$') "Execution contract frozen binding lacks a valid SHA-256: $($property.Name)"
    $frozenFull = Get-NormalizedFullPath -Path ([string]$frozenBinding.relativePath) -Base $projectRootFull
    Assert-InsideProject -Path $frozenFull -Root $projectRootFull -Label "execution contract binding $($property.Name)"
    Require-Condition ((Get-ProjectRelativePath -Path $frozenFull -Root $projectRootFull) -ceq [string]$frozenBinding.relativePath) "Execution contract binding path is non-canonical: $($property.Name)"
    Assert-Hash -Path $frozenFull -Expected ([string]$frozenBinding.sha256) -Label "execution contract binding $($property.Name)"
    $contractFrozenBindings.Add([pscustomobject][ordered]@{
        name = [string]$property.Name
        relativePath = [string]$frozenBinding.relativePath
        sha256 = [string]$frozenBinding.sha256
    })
}

$manifestIndex = @{}
foreach ($artifact in @($manifest.artifacts)) { $manifestIndex[[string]$artifact.relativePath] = [string]$artifact.sha256 }
Require-Condition ($manifestIndex.ContainsKey($supervisorSelfRelative) -and $manifestIndex[$supervisorSelfRelative] -eq [string]$contract.entryPoint.supervisorSha256) 'Implementation manifest v3 does not bind the supervisor v3 source.'
$runnerRelative = Get-ProjectRelativePath -Path $runnerFull -Root $projectRootFull
Require-Condition ($manifestIndex.ContainsKey($runnerRelative) -and $manifestIndex[$runnerRelative] -eq [string]$contract.entryPoint.runnerSha256) 'Implementation manifest v3 does not bind RunnerV2 source.'
foreach ($frozenBinding in $contractFrozenBindings) {
    Require-Condition ($manifestIndex.ContainsKey([string]$frozenBinding.relativePath) -and $manifestIndex[[string]$frozenBinding.relativePath] -eq [string]$frozenBinding.sha256) "Implementation manifest v3 does not bind contract artifact $($frozenBinding.relativePath)."
}
foreach ($binding in $bindings | Where-Object { $_.Variable -notin @('authorizationFull', 'manifestFull', 'pythonFull', 'unityFull') }) {
    $full = Get-Variable -Scope Script -Name ([string]$binding.Variable) -ValueOnly
    $relative = Get-ProjectRelativePath -Path $full -Root $projectRootFull
    Require-Condition ($manifestIndex.ContainsKey($relative) -and $manifestIndex[$relative] -eq [string]$binding.Hash) "Implementation manifest v3 does not bind $relative."
}

$records = @(Get-Content -LiteralPath $scheduleFull -Encoding UTF8 | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | ForEach-Object { $_ | ConvertFrom-Json -Depth 100 -DateKind String })
Require-Condition ($records.Count -eq 162) "Qualification schedule must contain exactly 162 rows; found $($records.Count)."
$seenSuperblocks = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
$seenInputs = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
$identityHashes = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
for ($index = 0; $index -lt $records.Count; $index++) {
    $record = $records[$index]
    Require-Condition ($record.schema -eq 'gate14re-me-load-qualification-schedule-row-v1' -and [int]$record.ordinal -eq $index) "Schedule schema/ordinal mismatch at row $index."
    Require-Condition $seenSuperblocks.Add([string]$record.superblockId) "Duplicate superblock ID: $($record.superblockId)"
    Require-Condition ($null -eq $record.replacement) "Schedule row $index contains a replacement asset; v2 freezes zero-replacement fail-stop."
    Require-Condition (@($record.algorithmOrder).Count -eq 6) "Schedule row $index does not contain six lanes."
    Require-Condition ((@($record.algorithmOrder | ForEach-Object { $_.algorithmId } | Sort-Object) -join '|') -ceq (@($expectedAlgorithms | Sort-Object) -join '|')) "Algorithm cohort mismatch at row $index."
    Require-Condition ((@($record.algorithmOrder | ForEach-Object { $_.anonymousLaneId } | Sort-Object) -join '|') -ceq (@($expectedAnonymousLanes | Sort-Object) -join '|')) "Anonymous-lane cohort mismatch at row $index."
    foreach ($lane in $record.algorithmOrder) { $null = $identityHashes.Add([string]$lane.identityBindingSha256) }
    $inputFull = Get-NormalizedFullPath -Path ([string]$record.inputRelativePath) -Base $projectRootFull
    Assert-InsideProject -Path $inputFull -Root $projectRootFull -Label 'Input bundle'
    Assert-Hash -Path $inputFull -Expected ([string]$record.inputSha256) -Label "input $($record.superblockId)"
    $inputRelative = Get-ProjectRelativePath -Path $inputFull -Root $projectRootFull
    Require-Condition ([string]$record.inputRelativePath -ceq $inputRelative -and $seenInputs.Add($inputRelative)) "Input path is non-canonical or duplicate at row $index."
    $bundle = Read-Json -Path $inputFull
    Require-Condition ($bundle.schema -eq 'gate14re-me-qualification-input-bundle-v1' -and $bundle.superblockId -eq $record.superblockId -and @($bundle.eventGroups).Count -eq 24) "Input bundle identity/cardinality mismatch at row $index."
    foreach ($group in $bundle.eventGroups) { Require-Condition ([string]$group.topology -eq [string]$bundle.changeTopology) "Input event-group topology mismatch at row $index." }
}
Require-Condition ($identityHashes.Count -eq 1) 'Schedule does not bind exactly one sealed identity hash.'
$identityBindingSha256 = [string]($identityHashes | Select-Object -First 1)
Require-Condition ($identityBindingSha256 -match '^[0-9a-f]{64}$') 'Schedule identity binding is not a lower-case SHA-256.'
Require-Condition (@(Get-CimInstance Win32_Process -Filter "Name = 'Unity.exe'").Count -eq 0) 'A Unity process is already active.'

$driveId = [System.IO.Path]::GetPathRoot($measuredRootFull).TrimEnd('\')
$drive = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='$driveId'"
$requiredReservation = [int64]$budget.qualificationReservedStorageBytes + [int64]$budget.formalRawAndDeliveryReservedStorageBytes
Require-Condition ($null -ne $drive -and [int64]$drive.FreeSpace -ge $requiredReservation) 'Host free space is below the two frozen reservations.'

try {
    # A later, separately authorized invocation reaches this mutation boundary.
    $null = New-Item -ItemType Directory -Path $measuredRootFull
    $measuredRootCreated = $true
    foreach ($relative in @('_control', '_control/process-identities', '_control/unity-logs', 'oracle', 'raw/superblocks', 'raw/empty-boundary', 'instruments')) { $null = New-Item -ItemType Directory -Path (Join-Path $measuredRootFull $relative) }
    $processIdentityRoot = Join-Path $measuredRootFull '_control/process-identities'
    $unityLogRoot = Join-Path $measuredRootFull '_control/unity-logs'
    $processLedger = Join-Path $measuredRootFull '_control/process-ledger.raw.v2.jsonl'
    $voidLedger = Join-Path $measuredRootFull '_control/failures-and-voids.raw.v1.jsonl'
    $replacementLedger = Join-Path $measuredRootFull '_control/replacement-ledger.raw.v1.jsonl'
    foreach ($file in @($processLedger, $voidLedger, $replacementLedger)) { $null = New-Item -ItemType File -Path $file }
    Write-JsonExclusive -Path (Join-Path $measuredRootFull '_control/launch-receipt.v2.json') -Value ([ordered]@{
        schema = 'gate14re-me-qualification-launch-receipt-v2'; studyId = $studyId; status = 'AUTHORIZED_QUALIFICATION_ACQUISITION_STARTED'
        executionAuthorizationSha256 = $ExecutionAuthorizationSha256; implementationManifestSha256 = $ImplementationManifestSha256
        executionContractSha256 = $ExecutionContractSha256; planningAssetsManifestSha256 = $PlanningAssetsManifestSha256
        resourceBudgetSha256 = $ResourceBudgetSha256; fairnessBindingSha256 = $FairnessBindingSha256; scheduleSha256 = $ScheduleSha256
        outputSchemaSha256 = $OutputSchemaSha256; instrumentContractSha256 = $InstrumentContractSha256; d3ContractSha256 = $D3ContractSha256
        typedParquetRuntimeManifestSha256 = $TypedParquetRuntimeManifestSha256; structuralToolSha256 = $StructuralToolSha256; deliveryToolSha256 = $DeliveryToolSha256
        identityBindingSha256 = $identityBindingSha256
        trustedIdentityRuleSha256 = $TrustedIdentityRuleSha256; timestampComparatorSha256 = $TimestampComparatorSha256
        unityExecutableSha256 = $UnityExecutableSha256; pythonExecutableSha256 = $PythonExecutableSha256
        runnerMethod = $runnerMethod; replacementPolicy = 'ZERO_REPLACEMENT_FAIL_STOP'; startedAtUtc = [DateTime]::UtcNow.ToString('o')
    })

    Invoke-VerifiedFreshUnityProcess -Mode 'instrument-self-test' -OutputDirectory (Join-Path $measuredRootFull 'instruments/csharp') -AdditionalArguments @() -TimeoutMilliseconds ([int64]$budget.instrumentProcessHardTimeoutMilliseconds)
    $null = Assert-Receipt -Path (Join-Path $measuredRootFull 'instruments/csharp/instrument-csharp-receipt.v2.json') -ExpectedStatus 'PASS_CSHARP_INSTRUMENT_COMPONENTS_PYTHON_ROUNDTRIP_PENDING'
    foreach ($record in $records) {
        $inputFull = Get-NormalizedFullPath -Path ([string]$record.inputRelativePath) -Base $projectRootFull
        $oracleOutput = Join-Path $measuredRootFull "oracle/$($record.superblockId)"
        Invoke-VerifiedFreshUnityProcess -Mode 'oracle' -OutputDirectory $oracleOutput -AdditionalArguments @('--g14me-input', $inputFull) -TimeoutMilliseconds ([int64]$budget.oracleInputHardTimeoutMilliseconds)
        $null = Assert-Receipt -Path (Join-Path $oracleOutput 'oracle-pass-receipt.v1.json') -ExpectedStatus 'PASS_ALGORITHM_NEUTRAL_GEOMETRY'
    }
    for ($ordinal = 0; $ordinal -lt 12; $ordinal++) {
        $emptyOutput = Join-Path $measuredRootFull ('raw/empty-boundary/process-{0:D2}' -f $ordinal)
        Invoke-VerifiedFreshUnityProcess -Mode 'empty-boundary' -OutputDirectory $emptyOutput -AdditionalArguments @('--g14me-process-ordinal', "$ordinal") -TimeoutMilliseconds ([int64]$budget.emptyBoundaryProcessHardTimeoutMilliseconds)
        $null = Assert-Receipt -Path (Join-Path $emptyOutput 'empty-boundary-receipt.v2.json') -ExpectedStatus 'COMPLETE_EMPTY_BOUNDARY_RAW'
    }
    foreach ($record in $records) {
        $inputFull = Get-NormalizedFullPath -Path ([string]$record.inputRelativePath) -Base $projectRootFull
        Invoke-Superblock -Record $record -InputFull $inputFull
    }
    Require-Condition ($processOrdinal -eq 1147) "Terminal process ordinal mismatch: expected 1147; actual $processOrdinal."
    Require-Condition ((Get-Item -LiteralPath $replacementLedger).Length -eq 0) 'Replacement ledger is not empty under the zero-replacement contract.'
    Write-JsonExclusive -Path (Join-Path $measuredRootFull '_control/acquisition-complete.v2.json') -Value ([ordered]@{
        schema = 'gate14re-me-qualification-acquisition-complete-v2'; studyId = $studyId; status = 'QUALIFICATION_RAW_STRUCTURAL_VALIDATION_PENDING'
        plannedSuperblocks = 162; acceptedSuperblocks = 162; plannedAlgorithmLanes = 972; acceptedAlgorithmLanes = 972
        unityProcessCount = $processOrdinal; wholeSuperblockReplacements = 0; formalCollectionAuthorized = $false; formalAnalysisAuthorized = $false
        rankingOrWinnerComputed = $false; completedAtUtc = [DateTime]::UtcNow.ToString('o')
    })

    $structuralReceipt = Invoke-JsonTool -ToolPath $structuralToolFull -Label 'structural-v3' -Arguments @(
        'validate', '--project-root', $projectRootFull, '--raw-root', $measuredRootFull,
        '--output-schema', $outputSchemaFull, '--output-schema-sha256', $OutputSchemaSha256,
        '--d3-contract', $d3ContractFull, '--d3-contract-sha256', $D3ContractSha256,
        '--identity-binding-sha256', $identityBindingSha256, '--profile', 'qualification-full'
    )
    Require-Condition ($structuralReceipt.status -eq 'PASS_SCHEMA_V3_STRUCTURAL_COMPLETE_RAW_NO_INFERENCE') 'structural-v3 did not return its terminal pass status.'
    Write-JsonExclusive -Path (Join-Path $measuredRootFull '_control/structural-validation-receipt.v3.json') -Value $structuralReceipt

    $deliveryReceipt = $null
    try {
        $deliveryReceipt = Invoke-JsonTool -ToolPath $deliveryToolFull -Label 'delivery-v2 build' -Arguments @(
            'build', '--project-root', $projectRootFull, '--raw-root', $measuredRootFull, '--output-root', $deliveryRootFull,
            '--output-schema', $outputSchemaFull, '--output-schema-sha256', $OutputSchemaSha256,
            '--d3-contract', $d3ContractFull, '--d3-contract-sha256', $D3ContractSha256,
            '--typed-parquet-runtime-manifest', $parquetManifestFull, '--typed-parquet-runtime-manifest-sha256', $TypedParquetRuntimeManifestSha256,
            '--identity-binding-sha256', $identityBindingSha256, '--profile', 'qualification-full'
        )
    }
    finally {
        $deliveryRootCreated = Test-Path -LiteralPath $deliveryRootFull -PathType Container
    }
    Require-Condition ($deliveryReceipt.status -eq 'PASS_SCHEMA_V2_COMPLETE_PER_OBSERVATION_DELIVERY') 'delivery-v2 build did not return its terminal pass status.'
    $deliveryVerifyReceipt = Invoke-JsonTool -ToolPath $deliveryToolFull -Label 'delivery-v2 verify' -Arguments @(
        'verify', '--project-root', $projectRootFull, '--delivery-root', $deliveryRootFull,
        '--typed-parquet-runtime-manifest', $parquetManifestFull, '--typed-parquet-runtime-manifest-sha256', $TypedParquetRuntimeManifestSha256
    )
    Require-Condition ($deliveryVerifyReceipt.status -eq 'PASS_VERIFIED_SCHEMA_V2_COMPLETE_PER_OBSERVATION_DELIVERY') 'delivery-v2 verification did not return its terminal pass status.'
    Write-JsonExclusive -Path (Join-Path $measuredRootFull '_control/qualification-complete.v2.json') -Value ([ordered]@{
        schema = 'gate14re-me-qualification-complete-receipt-v2'; studyId = $studyId
        status = 'QUALIFICATION_RAW_STRUCTURAL_AND_COMPLETE_PER_OBSERVATION_DELIVERY_FROZEN'
        structuralReceiptSha256 = Get-Sha256Lower -Path (Join-Path $measuredRootFull '_control/structural-validation-receipt.v3.json')
        deliveryManifestSha256 = [string]$deliveryReceipt.deliveryManifestSha256
        deliveryVerified = $true; completePerObservationRawDeliverable = $true; aggregateOnlyPackage = $false
        qualificationOnly = $true; formalCollectionAuthorized = $false; formalAnalysisAuthorized = $false; rankingOrWinnerComputed = $false
        completedAtUtc = [DateTime]::UtcNow.ToString('o')
    })
}
catch {
    if ($measuredRootCreated -and (Test-Path -LiteralPath (Join-Path $measuredRootFull '_control') -PathType Container)) {
        $failurePath = Join-Path $measuredRootFull '_control/failure-receipt.v2.json'
        if (-not (Test-Path -LiteralPath $failurePath)) {
            Write-JsonExclusive -Path $failurePath -Value ([ordered]@{
                schema = 'gate14re-me-qualification-supervisor-failure-receipt-v2'; studyId = $studyId; status = 'FAILED_CLOSED_NO_RETRY_NO_REPLACEMENT'
                failedMode = $currentMode; exactFailure = $_.Exception.Message; exceptionType = $_.Exception.GetType().FullName
                measuredRootCreated = $measuredRootCreated; deliveryRootCreated = $deliveryRootCreated; unityProcessCount = $processOrdinal
                retryPerformed = $false; replacementPerformed = $false; signalOrForcedTerminationSentBySupervisor = $false
                formalCollectionPerformed = $false; formalAnalysisPerformed = $false; rankingOrWinnerComputed = $false; failedAtUtc = [DateTime]::UtcNow.ToString('o')
            })
        }
    }
    throw
}
