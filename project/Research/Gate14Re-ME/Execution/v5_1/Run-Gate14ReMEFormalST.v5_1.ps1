[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$ProjectRoot,
    [Parameter(Mandatory = $true)][string]$MeasuredRoot,
    [Parameter(Mandatory = $true)][string]$ExecutionAuthorization,
    [Parameter(Mandatory = $true)][ValidatePattern('^[0-9a-f]{64}$')][string]$ExecutionAuthorizationSha256,
    [Parameter(Mandatory = $true)][string]$ImplementationManifest,
    [Parameter(Mandatory = $true)][ValidatePattern('^[0-9a-f]{64}$')][string]$ImplementationManifestSha256,
    [Parameter(Mandatory = $true)][string]$ExecutionContract,
    [Parameter(Mandatory = $true)][ValidatePattern('^[0-9a-f]{64}$')][string]$ExecutionContractSha256,
    [Parameter(Mandatory = $true)][string]$InputFreezeManifest,
    [Parameter(Mandatory = $true)][ValidatePattern('^[0-9a-f]{64}$')][string]$InputFreezeManifestSha256,
    [Parameter(Mandatory = $true)][string]$ResourceBudget,
    [Parameter(Mandatory = $true)][ValidatePattern('^[0-9a-f]{64}$')][string]$ResourceBudgetSha256,
    [Parameter(Mandatory = $true)][string]$FairnessBinding,
    [Parameter(Mandatory = $true)][ValidatePattern('^[0-9a-f]{64}$')][string]$FairnessBindingSha256,
    [Parameter(Mandatory = $true)][string]$Schedule,
    [Parameter(Mandatory = $true)][ValidatePattern('^[0-9a-f]{64}$')][string]$ScheduleSha256,
    [Parameter(Mandatory = $true)][string]$TrustedIdentityRule,
    [Parameter(Mandatory = $true)][ValidatePattern('^[0-9a-f]{64}$')][string]$TrustedIdentityRuleSha256,
    [Parameter(Mandatory = $true)][string]$TimestampComparator,
    [Parameter(Mandatory = $true)][ValidatePattern('^[0-9a-f]{64}$')][string]$TimestampComparatorSha256,
    [Parameter(Mandatory = $true)][string]$UnityExecutable,
    [Parameter(Mandatory = $true)][ValidatePattern('^[0-9a-f]{64}$')][string]$UnityExecutableSha256
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$studyId = 'Gate14Re-ME'
$runnerMethod = 'DDM.Research.Editor.Gate14ReMEFormalSTRunnerV5_1.Run'
$reservedMeasuredRootPattern = '^Research/FormalRuns/Gate14Re-ME/formal-st/v5/attempt-[0-9]+$'
$expectedAlgorithms = @('A*-R', 'BiA*-R', 'D*L', 'LPA*', 'C-FF', 'IDFF')
$expectedAnonymousLanes = @('ALG-A', 'ALG-B', 'ALG-C', 'ALG-D', 'ALG-E', 'ALG-F')
$williamsOrders = @(
    @('A*-R', 'BiA*-R', 'IDFF', 'D*L', 'C-FF', 'LPA*'),
    @('BiA*-R', 'D*L', 'A*-R', 'LPA*', 'IDFF', 'C-FF'),
    @('D*L', 'LPA*', 'BiA*-R', 'C-FF', 'A*-R', 'IDFF'),
    @('LPA*', 'C-FF', 'D*L', 'IDFF', 'BiA*-R', 'A*-R'),
    @('C-FF', 'IDFF', 'LPA*', 'A*-R', 'D*L', 'BiA*-R'),
    @('IDFF', 'A*-R', 'C-FF', 'BiA*-R', 'LPA*', 'D*L')
)
$chunkSizeBytes = 65536
$processOrdinal = 0
$measuredRootCreated = $false
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
    param([string]$Mode, [string]$OutputDirectory, [string]$LogPath, [int]$FormalProcessOrdinal)
    return @(
        '-batchmode', '-nographics', '-projectPath', $script:projectRootFull,
        '-logFile', $LogPath, '-executeMethod', $script:runnerMethod,
        '--g14me-mode', $Mode, '--g14me-output-dir', $OutputDirectory,
        '--g14me-formal-process-ordinal', "$FormalProcessOrdinal",
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

function Get-LifecycleReceiptPath {
    param([int]$Ordinal, [string]$Suffix)
    return Join-Path $script:processLifecycleRoot ('process-{0:D4}.{1}.v5_1.json' -f $Ordinal, $Suffix)
}

function Assert-LifecycleReceipt {
    param(
        [string]$Path,
        [string]$ExpectedStatus,
        [string]$Mode,
        [int]$Ordinal,
        [int]$ProcessId,
        [DateTime]$CreationTimeUtc
    )
    $receipt = Read-Json -Path $Path
    Require-Condition ([string]$receipt.schema -ceq 'gate14re-me-formal-st-process-lifecycle-receipt-v5.1') "Lifecycle receipt schema mismatch: $Path"
    Require-Condition ([string]$receipt.studyId -ceq $script:studyId -and [string]$receipt.status -ceq $ExpectedStatus) "Lifecycle receipt status mismatch: $Path"
    Require-Condition ([int]$receipt.formalProcessOrdinal -eq $Ordinal -and [string]$receipt.mode -ceq $Mode -and [int]$receipt.processId -eq $ProcessId) "Lifecycle receipt process identity mismatch: $Path"
    Require-Condition ([string]$receipt.implementationManifestSha256 -ceq $script:ImplementationManifestSha256 -and [string]$receipt.resourceBudgetSha256 -ceq $script:ResourceBudgetSha256) "Lifecycle receipt frozen-binding mismatch: $Path"
    $receiptStartUtc = ([DateTimeOffset]::Parse([string]$receipt.processStartTimeUtc, [Globalization.CultureInfo]::InvariantCulture)).UtcDateTime
    $receiptStartDeltaMilliseconds = [Math]::Abs(($receiptStartUtc - $CreationTimeUtc).TotalMilliseconds)
    Require-Condition ($receiptStartDeltaMilliseconds -le 1000.0) "Lifecycle receipt process-start identity mismatch: $Path"
    Require-Condition ([string]::IsNullOrEmpty([string]$receipt.failure)) "Successful lifecycle receipt contains a failure: $Path"
    if ($ExpectedStatus -ceq 'BURST_COMPILATION_STABLY_DONE') {
        Require-Condition ([bool]$receipt.burstFinalCompilationDone -and [int]$receipt.burstRequiredConsecutiveDoneObservations -eq 3 -and [int]$receipt.burstAchievedConsecutiveDoneObservations -ge 3) "Burst lifecycle receipt lacks the frozen stable-completion proof: $Path"
    }
    return $receipt
}

function Write-LifecycleTimeoutReceipt {
    param(
        [System.Diagnostics.Process]$Process,
        [int]$ProcessId,
        [DateTime]$CreationTimeUtc,
        [int]$Ordinal,
        [string]$Mode,
        [string]$Phase,
        [int64]$TimeoutMilliseconds,
        [int64]$ObservedElapsedMilliseconds
    )
    $metadata = Get-CimInstance Win32_Process -Filter "ProcessId = $ProcessId"
    $cpuSeconds = $null
    $threadCount = $null
    try {
        $Process.Refresh()
        if (-not $Process.HasExited) {
            $cpuSeconds = $Process.TotalProcessorTime.TotalSeconds
            $threadCount = $Process.Threads.Count
        }
    }
    catch { }
    $path = Get-LifecycleReceiptPath -Ordinal $Ordinal -Suffix (($Phase.ToLowerInvariant() -replace '[^a-z0-9]+', '-') + '-timeout')
    if (-not (Test-Path -LiteralPath $path)) {
        Write-JsonExclusive -Path $path -Value ([ordered]@{
            schema = 'gate14re-me-formal-st-host-lifecycle-timeout-v5.1'
            studyId = $script:studyId
            status = 'FAILED_CLOSED_HOST_LIFECYCLE_TIMEOUT'
            formalProcessOrdinal = $Ordinal
            mode = $Mode
            phase = $Phase
            processId = $ProcessId
            processCreationTimeUtc = $CreationTimeUtc.ToString('o')
            timeoutMilliseconds = $TimeoutMilliseconds
            observedElapsedMilliseconds = $ObservedElapsedMilliseconds
            executablePath = if ($null -eq $metadata) { $null } else { [string]$metadata.ExecutablePath }
            exactCommandLine = if ($null -eq $metadata) { $null } else { [string]$metadata.CommandLine }
            cpuSeconds = $cpuSeconds
            threadCount = $threadCount
            processStillPresent = ($null -ne $metadata)
            signalOrForcedTerminationSentBySupervisor = $false
            retryResumeReplacementPerformed = $false
            createdAtUtc = [DateTime]::UtcNow.ToString('o')
        })
    }
    return $path
}

function Wait-ForLifecycleReceipt {
    param(
        [System.Diagnostics.Process]$Process,
        [string]$Path,
        [string]$ExpectedStatus,
        [string]$Mode,
        [int]$Ordinal,
        [int]$ProcessId,
        [DateTime]$CreationTimeUtc,
        [int64]$TimeoutMilliseconds,
        [string]$Phase
    )
    $watch = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        while ($watch.ElapsedMilliseconds -lt $TimeoutMilliseconds) {
            if (Test-Path -LiteralPath $Path -PathType Leaf) {
                return Assert-LifecycleReceipt -Path $Path -ExpectedStatus $ExpectedStatus -Mode $Mode -Ordinal $Ordinal -ProcessId $ProcessId -CreationTimeUtc $CreationTimeUtc
            }
            if ($Process.HasExited) {
                Start-Sleep -Milliseconds ([Math]::Min(250, [int]$script:budget.lifecyclePollMilliseconds))
                if (Test-Path -LiteralPath $Path -PathType Leaf) {
                    return Assert-LifecycleReceipt -Path $Path -ExpectedStatus $ExpectedStatus -Mode $Mode -Ordinal $Ordinal -ProcessId $ProcessId -CreationTimeUtc $CreationTimeUtc
                }
                $Process.WaitForExit()
                throw [System.InvalidOperationException]::new("Unity exited before the required lifecycle phase: phase=$Phase mode=$Mode ordinal=$Ordinal pid=$ProcessId exitCode=$($Process.ExitCode)")
            }
            Start-Sleep -Milliseconds ([int]$script:budget.lifecyclePollMilliseconds)
        }
        $timeoutReceipt = Write-LifecycleTimeoutReceipt -Process $Process -ProcessId $ProcessId -CreationTimeUtc $CreationTimeUtc -Ordinal $Ordinal -Mode $Mode -Phase $Phase -TimeoutMilliseconds $TimeoutMilliseconds -ObservedElapsedMilliseconds $watch.ElapsedMilliseconds
        throw [System.TimeoutException]::new("Unity lifecycle phase exceeded its independent frozen timeout without receiving a signal: phase=$Phase mode=$Mode ordinal=$Ordinal pid=$ProcessId timeoutMs=$TimeoutMilliseconds timeoutReceipt=$timeoutReceipt")
    }
    finally {
        $watch.Stop()
    }
}

function Invoke-VerifiedFreshUnityProcess {
    param([string]$Mode, [string]$OutputDirectory, [string[]]$AdditionalArguments, [int64]$TimeoutMilliseconds)
    Require-Condition (-not (Test-Path -LiteralPath $OutputDirectory)) "Fresh process output already exists: $OutputDirectory"
    $script:currentMode = $Mode
    $ordinal = $script:processOrdinal
    $script:processOrdinal++
    $identityPath = Join-Path $script:processIdentityRoot ('process-{0:D4}.identity.v5.json' -f $ordinal)
    $logPath = Join-Path $script:unityLogRoot ('process-{0:D4}.unity.log' -f $ordinal)
    $modeStartedPath = Get-LifecycleReceiptPath -Ordinal $ordinal -Suffix 'mode-started'
    $modeOutputFrozenPath = Get-LifecycleReceiptPath -Ordinal $ordinal -Suffix 'mode-output-frozen'
    $burstStablePath = Get-LifecycleReceiptPath -Ordinal $ordinal -Suffix 'burst-stably-done'
    foreach ($lifecyclePath in @($modeStartedPath, $modeOutputFrozenPath, $burstStablePath)) {
        Require-Condition (-not (Test-Path -LiteralPath $lifecyclePath)) "Fresh process lifecycle receipt already exists: $lifecyclePath"
    }
    $pre = Get-UnityFingerprint -Path $script:unityFull -Phase 'PRELAUNCH'
    Assert-FingerprintAgainstRule -Fingerprint $pre -Rule $script:identityRule -Phase 'prelaunch'
    Require-Condition (@(Get-CimInstance Win32_Process -Filter "Name = 'Unity.exe'").Count -eq 0) 'Another Unity process is active; composite attribution is not unique.'

    $arguments = @(Get-CommonRunnerArguments -Mode $Mode -OutputDirectory $OutputDirectory -LogPath $logPath -FormalProcessOrdinal $ordinal) + $AdditionalArguments
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
    $process = $null
    try {
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
        Require-Condition ([string]$liveMetadata.CommandLine -like "*$script:runnerMethod*") 'Live Unity command line lacks FormalSTRunnerV5_1.'
        Require-Condition ([string]$liveMetadata.CommandLine -like "*$script:measuredRootFull*") 'Live Unity command line lacks the exact measured root output.'
        Require-Condition ([string]$liveMetadata.CommandLine -notlike '* -quit *' -and [string]$liveMetadata.CommandLine -notmatch '(?i)(^|\s)-quit($|\s)') 'Formal ST v5.1 forbids command-line -quit; the runner must own terminal exit.'
        $live = Get-UnityFingerprint -Path $script:unityFull -Phase 'LIVE_CONCURRENT'
        Assert-FingerprintAgainstRule -Fingerprint $live -Rule $script:identityRule -Phase 'live'
        Assert-FingerprintStable -Reference $pre -Observed $live -Phase 'live'

        $null = Wait-ForLifecycleReceipt -Process $process -Path $modeStartedPath -ExpectedStatus 'MODE_EXECUTION_STARTED' -Mode $Mode -Ordinal $ordinal -ProcessId $processId -CreationTimeUtc $creationTimeUtc -TimeoutMilliseconds ([int64]$script:budget.unityStartupAndValidationHardTimeoutMilliseconds) -Phase 'UNITY_STARTUP_AND_VALIDATION'
        $null = Wait-ForLifecycleReceipt -Process $process -Path $modeOutputFrozenPath -ExpectedStatus 'MODE_OUTPUT_FROZEN' -Mode $Mode -Ordinal $ordinal -ProcessId $processId -CreationTimeUtc $creationTimeUtc -TimeoutMilliseconds $TimeoutMilliseconds -Phase 'MODE_EXECUTION'
        $burstReceiptObservationTimeoutMilliseconds = [int64]$script:budget.burstCompletionTimeoutMilliseconds + [int64]$script:budget.lifecycleReceiptObservationGraceMilliseconds
        $burstReceipt = Wait-ForLifecycleReceipt -Process $process -Path $burstStablePath -ExpectedStatus 'BURST_COMPILATION_STABLY_DONE' -Mode $Mode -Ordinal $ordinal -ProcessId $processId -CreationTimeUtc $creationTimeUtc -TimeoutMilliseconds $burstReceiptObservationTimeoutMilliseconds -Phase 'POST_OUTPUT_BURST_DRAIN'

        $exitWatch = [System.Diagnostics.Stopwatch]::StartNew()
        try {
            $exitedNaturally = $process.WaitForExit([int]$script:budget.editorNaturalExitGraceMilliseconds)
            if (-not $exitedNaturally) {
                $timeoutReceipt = Write-LifecycleTimeoutReceipt -Process $process -ProcessId $processId -CreationTimeUtc $creationTimeUtc -Ordinal $ordinal -Mode $Mode -Phase 'EDITOR_NATURAL_EXIT' -TimeoutMilliseconds ([int64]$script:budget.editorNaturalExitGraceMilliseconds) -ObservedElapsedMilliseconds $exitWatch.ElapsedMilliseconds
                throw [System.TimeoutException]::new("Unity editor did not terminate naturally within the independent post-Burst exit grace; no signal was sent: mode=$Mode ordinal=$ordinal pid=$processId timeoutMs=$($script:budget.editorNaturalExitGraceMilliseconds) timeoutReceipt=$timeoutReceipt")
            }
        }
        finally {
            $exitWatch.Stop()
        }

        $exitCode = $process.ExitCode
        $exitedAtUtc = [DateTime]::UtcNow
        $post = Get-UnityFingerprint -Path $script:unityFull -Phase 'POST_EXIT'
        Assert-FingerprintAgainstRule -Fingerprint $post -Rule $script:identityRule -Phase 'post-exit'
        Assert-FingerprintStable -Reference $pre -Observed $post -Phase 'post-exit'
        Require-Condition ($exitCode -eq 0) "Unity exited nonzero: mode=$Mode pid=$processId exitCode=$exitCode"
        Require-Condition (@(Get-CimInstance Win32_Process -Filter "ProcessId = $processId").Count -eq 0) 'Unity PID still exists after WaitForExit.'

        Write-JsonExclusive -Path $identityPath -Value ([ordered]@{
            schema = 'gate14re-me-formal-st-qualified-unity-process-identity-receipt-v5'
            studyId = $script:studyId
            status = 'PASS_TRUSTED_THREE_PHASE_COMPOSITE_IDENTITY_NATURAL_EXIT'
            implementationRevision = 'v5.1-host-lifecycle-corrigendum'
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
            commandLineQuitPresent = $false
            runnerOwnsTerminalExit = $true
            outputRelativePath = Get-ProjectRelativePath -Path $OutputDirectory -Root $script:projectRootFull
            modeStartedReceiptRelativePath = Get-ProjectRelativePath -Path $modeStartedPath -Root $script:projectRootFull
            modeStartedReceiptSha256 = Get-Sha256Lower -Path $modeStartedPath
            modeOutputFrozenReceiptRelativePath = Get-ProjectRelativePath -Path $modeOutputFrozenPath -Root $script:projectRootFull
            modeOutputFrozenReceiptSha256 = Get-Sha256Lower -Path $modeOutputFrozenPath
            burstStableReceiptRelativePath = Get-ProjectRelativePath -Path $burstStablePath -Root $script:projectRootFull
            burstStableReceiptSha256 = Get-Sha256Lower -Path $burstStablePath
            burstWaitElapsedMilliseconds = [int64]$burstReceipt.burstWaitElapsedMilliseconds
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
            schema = 'gate14re-me-formal-st-process-ledger-row-v5'
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
    finally {
        if ($null -ne $process) { $process.Dispose() }
    }
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

function Get-FormalSTOracleBatchIndexV5 {
    param([int]$Ordinal, [int]$BatchCount)
    Require-Condition ($Ordinal -ge 0 -and $Ordinal -lt 1296) 'Oracle batch assignment requires formal schedule ordinal 0..1295.'
    Require-Condition ($BatchCount -gt 0 -and $BatchCount -le 1296 -and (1296 % $BatchCount) -eq 0) 'Oracle batch count must be a positive divisor of 1296.'
    return [int]($Ordinal % $BatchCount)
}

function Invoke-Superblock {
    param([object]$Record, [string]$InputFull)
    $superblockRoot = Join-Path $script:measuredRootFull "raw/superblocks/$($Record.superblockId)"
    Require-Condition (-not (Test-Path -LiteralPath $superblockRoot)) "Superblock output already exists: $superblockRoot"
    $null = New-Item -ItemType Directory -Path $superblockRoot
    try {
        foreach ($lane in $Record.algorithmOrder) {
            $laneOutput = Join-Path $superblockRoot ([string]$lane.anonymousLaneId)
            $cacheBindingReceipt = Join-Path $script:measuredRootFull "oracle/$($Record.superblockId)/oracle-cache-binding-receipt.v5.json"
            $cacheBinding = Assert-Receipt -Path $cacheBindingReceipt -ExpectedStatus 'PASS_FROZEN_ALGORITHM_NEUTRAL_ORACLE_CACHE_V5'
            Require-Condition ([int]$cacheBinding.scheduleOrdinal -eq [int]$Record.ordinal -and [string]$cacheBinding.superblockId -ceq [string]$Record.superblockId) 'Oracle cache binding does not match the scheduled superblock.'
            $cacheBindingReceiptSha = Get-Sha256Lower -Path $cacheBindingReceipt
            Invoke-VerifiedFreshUnityProcess -Mode 'lane' -OutputDirectory $laneOutput -TimeoutMilliseconds ([int64]$script:budget.laneWallClockHardTimeoutMilliseconds) -AdditionalArguments @(
                '--g14me-input', $InputFull,
                '--g14me-oracle-cache-binding', $cacheBindingReceipt,
                '--g14me-oracle-cache-binding-sha256', $cacheBindingReceiptSha,
                '--g14me-algorithm-id', [string]$lane.algorithmId,
                '--g14me-anonymous-lane-id', [string]$lane.anonymousLaneId,
                '--g14me-identity-binding-sha256', [string]$lane.identityBindingSha256
            )
            $null = Assert-Receipt -Path (Join-Path $laneOutput 'lane-receipt.v5.json') -ExpectedStatus 'COMPLETE_RAW_FORMAL_ST_LANE'
            $cacheLink = Assert-Receipt -Path (Join-Path $laneOutput 'lane-oracle-cache-link.v5.json') -ExpectedStatus 'BOUND_TO_FROZEN_ALGORITHM_NEUTRAL_ORACLE_CACHE_V5'
            Require-Condition ([int]$cacheLink.referenceOracleEvaluationsPerformedInsideLane -eq 0 -and [string]$cacheLink.oracleCacheBindingSha256 -ceq $cacheBindingReceiptSha) 'Lane did not prove zero reference-oracle evaluation and exact cache binding.'
        }
        Write-JsonExclusive -Path (Join-Path $superblockRoot 'accepted-superblock-receipt.v1.json') -Value ([ordered]@{
            schema = 'gate14re-me-formal-st-accepted-superblock-receipt-v5'
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
            schema = 'gate14re-me-formal-st-whole-superblock-void-row-v5'
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

function Write-AcquisitionFreezeManifest {
    param([string]$Root, [string]$Path)
    $artifacts = @(
        Get-ChildItem -LiteralPath $Root -File -Recurse |
            Sort-Object -Property FullName |
            ForEach-Object {
                [ordered]@{
                    relativePath = Get-ProjectRelativePath -Path $_.FullName -Root $Root
                    lengthBytes = [int64]$_.Length
                    sha256 = Get-Sha256Lower -Path $_.FullName
                }
            }
    )
    Write-JsonExclusive -Path $Path -Value ([ordered]@{
        schema = 'gate14re-me-formal-st-acquisition-freeze-manifest-v5'
        studyId = $script:studyId
        status = 'SEALED_ACQUISITION_RAW_ACCEPTANCE_PENDING'
        measuredRootRelativePath = Get-ProjectRelativePath -Path $Root -Root $script:projectRootFull
        artifactCount = $artifacts.Count
        artifacts = $artifacts
        rawObservationsInterpreted = $false
        formalCollectionPerformed = $true
        formalAnalysisPerformed = $false
        createdAtUtc = [DateTime]::UtcNow.ToString('o')
    })
}

# Read-only preflight: no measured root may be created before every binding passes.
$projectRootFull = Get-NormalizedFullPath -Path $ProjectRoot -Base (Get-Location).Path
Require-Condition (Test-Path -LiteralPath $projectRootFull -PathType Container) 'Project root does not exist.'
$measuredRootFull = Get-NormalizedFullPath -Path $MeasuredRoot -Base $projectRootFull
Assert-InsideProject -Path $measuredRootFull -Root $projectRootFull -Label 'Measured root'
$measuredRootRelativePath = Get-ProjectRelativePath -Path $measuredRootFull -Root $projectRootFull
Require-Condition ($measuredRootRelativePath -cmatch $reservedMeasuredRootPattern) 'Measured root is not a fresh versioned formal-st attempt path.'
Require-Condition (-not (Test-Path -LiteralPath $measuredRootFull)) 'Measured root already exists; retry/resume/overwrite are prohibited.'

$bindings = @(
    @{ Variable = 'authorizationFull'; Path = $ExecutionAuthorization; Hash = $ExecutionAuthorizationSha256; Label = 'execution authorization' },
    @{ Variable = 'manifestFull'; Path = $ImplementationManifest; Hash = $ImplementationManifestSha256; Label = 'formal ST implementation manifest v5' },
    @{ Variable = 'executionContractFull'; Path = $ExecutionContract; Hash = $ExecutionContractSha256; Label = 'formal ST acquisition contract v5' },
    @{ Variable = 'inputFreezeManifestFull'; Path = $InputFreezeManifest; Hash = $InputFreezeManifestSha256; Label = 'formal ST input freeze manifest v5' },
    @{ Variable = 'budgetFull'; Path = $ResourceBudget; Hash = $ResourceBudgetSha256; Label = 'formal ST operational resource budget v5' },
    @{ Variable = 'fairnessFull'; Path = $FairnessBinding; Hash = $FairnessBindingSha256; Label = 'frozen six-algorithm fairness binding' },
    @{ Variable = 'scheduleFull'; Path = $Schedule; Hash = $ScheduleSha256; Label = 'formal ST schedule v5' },
    @{ Variable = 'identityRuleFull'; Path = $TrustedIdentityRule; Hash = $TrustedIdentityRuleSha256; Label = 'trusted Unity identity rule' },
    @{ Variable = 'timestampComparatorFull'; Path = $TimestampComparator; Hash = $TimestampComparatorSha256; Label = 'trusted timestamp comparator' },
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
$inputFreezeManifest = Read-Json -Path $inputFreezeManifestFull
$budget = Read-Json -Path $budgetFull
$fairness = Read-Json -Path $fairnessFull
$identityRule = Read-Json -Path $identityRuleFull
Require-Condition ($authorization.schema -eq 'gate14re-me-formal-st-execution-authorization-v5' -and $authorization.studyId -eq $studyId -and $authorization.designId -eq 'gate14re-me-formal-st-bounded-gnf-v5' -and $authorization.status -eq 'AUTHORIZED_FORMAL_ST_COLLECTION') 'Execution authorization header is invalid.'
Require-Condition ($authorization.formalRootCreationAuthorized -and $authorization.compileOrUnityExecutionAuthorized -and $authorization.formalCollectionAuthorized) 'Execution authorization omits a required acquisition permission.'
Require-Condition (-not $authorization.formalInputGenerationAuthorized -and -not $authorization.formalAcceptanceExecutionAuthorized -and -not $authorization.formalAnalysisAuthorized -and -not $authorization.mqAuthorized -and -not $authorization.mtAuthorized) 'Execution authorization exceeds the formal ST collection-only boundary.'
Require-Condition ([int]$authorization.oracleBatchCount -gt 0 -and [int]$authorization.oracleBatchCount -le 1296 -and (1296 % [int]$authorization.oracleBatchCount) -eq 0) 'Execution authorization oracle batch count must be a positive divisor of 1296.'
Require-Condition ($authorization.measuredRootRelativePath.Replace('\', '/') -ceq $measuredRootRelativePath) 'Execution authorization measured-root binding mismatch.'
Require-Condition ($authorization.implementationManifestSha256 -eq $ImplementationManifestSha256 -and $authorization.executionContractSha256 -eq $ExecutionContractSha256 -and $authorization.inputFreezeManifestSha256 -eq $InputFreezeManifestSha256 -and $authorization.scheduleSha256 -eq $ScheduleSha256) 'Execution authorization artifact-hash binding mismatch.'
Require-Condition ($manifest.schema -eq 'gate14re-me-formal-st-implementation-manifest-v5' -and $manifest.studyId -eq $studyId -and $manifest.designId -eq 'gate14re-me-formal-st-bounded-gnf-v5' -and $manifest.status -eq 'FROZEN_FORMAL_ST_V5_IMPLEMENTATION_READY') 'Implementation manifest v5 header is invalid.'
Require-Condition ($contract.schema -eq 'gate14re-me-formal-st-acquisition-contract-v5' -and $contract.status -eq 'FROZEN_FORMAL_ST_V5_ACQUISITION_EXECUTION_REQUIRES_SEPARATE_AUTHORIZATION') 'Acquisition contract v5 header is invalid.'
Require-Condition ($inputFreezeManifest.schema -eq 'gate14re-me-formal-st-input-freeze-manifest-v5' -and $inputFreezeManifest.status -eq 'FROZEN_FORMAL_INPUTS_AND_SCHEDULE_EXECUTION_NOT_AUTHORIZED') 'Formal input material is not terminally frozen.'
Require-Condition ($budget.schema -eq 'gate14re-me-formal-st-operational-resource-budget-v5' -and $budget.status -eq 'FROZEN_FORMAL_ST_V5_OPERATIONAL_LIMITS' -and [int]$budget.maximumConcurrentUnityProcesses -eq 1) 'Resource budget serial-process rule mismatch.'
Require-Condition (
    [int64]$budget.eventGroupHardTimeoutMilliseconds -eq 300000L -and
    [int64]$budget.laneWallClockHardTimeoutMilliseconds -eq 600000L -and
    [int64]$budget.oracleBatchHardTimeoutMilliseconds -eq 3600000L -and
    [int64]$budget.instrumentProcessHardTimeoutMilliseconds -eq 600000L -and
    [int64]$budget.emptyBoundaryProcessHardTimeoutMilliseconds -eq 300000L -and
    [int64]$budget.unityStartupAndValidationHardTimeoutMilliseconds -eq 1800000L -and
    [int64]$budget.burstCompletionTimeoutMilliseconds -eq 300000L -and
    [int64]$budget.editorNaturalExitGraceMilliseconds -eq 300000L -and
    [int64]$budget.lifecyclePollMilliseconds -eq 250L -and
    [int64]$budget.lifecycleReceiptObservationGraceMilliseconds -eq 5000L
) 'Resource budget scientific/host-lifecycle timeout values differ from the frozen v5.1 limits.'
Require-Condition ([int]$authorization.oracleBatchCount -ge [int]$budget.oracleCacheV5.minimumBatchCount -and [int]$authorization.oracleBatchCount -le [int]$budget.oracleCacheV5.maximumBatchCount) 'Authorization oracle batch count is outside the frozen operational range.'
Require-Condition ([int]$budget.maximumWholeSuperblockTechnicalReplacements -eq 0) 'Resource budget must freeze zero replacement.'
Require-Condition ($fairness.status -eq 'FROZEN_SIX_ALGORITHM_BINDING' -and @($fairness.algorithms).Count -eq 6) 'Six-algorithm fairness binding mismatch.'
Require-Condition ($identityRule.schema -eq 'gate14re-me-unity-executable-identity-verification-rule-v1' -and $identityRule.status -eq 'FROZEN_TRUSTED_IDENTITY_RULE_FROM_OFFLINE_ADJUDICATION') 'Trusted identity rule header mismatch.'
Require-Condition ([string]$identityRule.applicability.unityExecutableExpectedSha256 -eq $UnityExecutableSha256) 'Trusted identity rule Unity hash mismatch.'

$supervisorSelfRelative = Get-ProjectRelativePath -Path $PSCommandPath -Root $projectRootFull
Require-Condition ([string]$contract.entryPoint.supervisorRelativePath -ceq $supervisorSelfRelative) 'Execution contract supervisor path does not identify this exact script.'
Assert-Hash -Path $PSCommandPath -Expected ([string]$contract.entryPoint.supervisorSha256) -Label 'formal ST supervisor v5 self-binding'
$runnerFull = Get-NormalizedFullPath -Path ([string]$contract.entryPoint.runnerRelativePath) -Base $projectRootFull
Assert-InsideProject -Path $runnerFull -Root $projectRootFull -Label 'FormalSTRunnerV5 source'
Assert-Hash -Path $runnerFull -Expected ([string]$contract.entryPoint.runnerSha256) -Label 'FormalSTRunnerV5 source'

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
Require-Condition ($manifestIndex.ContainsKey($supervisorSelfRelative) -and $manifestIndex[$supervisorSelfRelative] -eq [string]$contract.entryPoint.supervisorSha256) 'Implementation manifest v5 does not bind the supervisor v5 source.'
$runnerRelative = Get-ProjectRelativePath -Path $runnerFull -Root $projectRootFull
Require-Condition ($manifestIndex.ContainsKey($runnerRelative) -and $manifestIndex[$runnerRelative] -eq [string]$contract.entryPoint.runnerSha256) 'Implementation manifest v5 does not bind FormalSTRunnerV5 source.'
foreach ($frozenBinding in $contractFrozenBindings) {
    Require-Condition ($manifestIndex.ContainsKey([string]$frozenBinding.relativePath) -and $manifestIndex[[string]$frozenBinding.relativePath] -eq [string]$frozenBinding.sha256) "Implementation manifest v5 does not bind contract artifact $($frozenBinding.relativePath)."
}
foreach ($binding in $bindings | Where-Object { $_.Variable -notin @('authorizationFull', 'manifestFull', 'inputFreezeManifestFull', 'scheduleFull', 'unityFull') }) {
    $full = Get-Variable -Scope Script -Name ([string]$binding.Variable) -ValueOnly
    $relative = Get-ProjectRelativePath -Path $full -Root $projectRootFull
    Require-Condition ($manifestIndex.ContainsKey($relative) -and $manifestIndex[$relative] -eq [string]$binding.Hash) "Implementation manifest v5 does not bind $relative."
}

$records = @(Get-Content -LiteralPath $scheduleFull -Encoding UTF8 | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | ForEach-Object { $_ | ConvertFrom-Json -Depth 100 -DateKind String })
Require-Condition ($records.Count -eq 1296) "Formal ST schedule must contain exactly 1296 rows; found $($records.Count)."
Require-Condition ([int]$inputFreezeManifest.inputCount -eq 1296 -and [int]$inputFreezeManifest.scheduleRowCount -eq 1296 -and [string]$inputFreezeManifest.scheduleSha256 -ceq $ScheduleSha256) 'Formal input freeze manifest cardinality/schedule binding mismatch.'
$seenSuperblocks = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
$seenInputs = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
$identityHashes = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
$cellCounts = @{}
$orderCounts = @(0, 0, 0, 0, 0, 0)
for ($index = 0; $index -lt $records.Count; $index++) {
    $record = $records[$index]
    Require-Condition ($record.schema -eq 'gate14re-me-formal-st-schedule-row-v5' -and [int]$record.ordinal -eq $index) "Schedule schema/ordinal mismatch at row $index."
    $expectedCellOrdinal = [Math]::Floor($index / 36)
    $expectedReplicate = $index % 36
    $expectedContext = $expectedReplicate % 18
    $expectedOrder = if ($expectedReplicate -lt 18) { ($expectedContext + $expectedCellOrdinal) % 6 } else { ($expectedContext + 3 + $expectedCellOrdinal) % 6 }
    Require-Condition ([int]$record.cellOrdinal -eq $expectedCellOrdinal -and [int]$record.replicateIndex -eq $expectedReplicate -and [int]$record.contextStratumIndex -eq $expectedContext -and [int]$record.orderIndex -eq $expectedOrder) "Schedule cell/replicate/context/order rule mismatch at row $index."
    Require-Condition $seenSuperblocks.Add([string]$record.superblockId) "Duplicate superblock ID: $($record.superblockId)"
    Require-Condition ($null -eq $record.replacement) "Schedule row $index contains a replacement asset; v5 freezes zero-replacement fail-stop."
    Require-Condition (@($record.algorithmOrder).Count -eq 6) "Schedule row $index does not contain six lanes."
    Require-Condition ((@($record.algorithmOrder | ForEach-Object { $_.algorithmId } | Sort-Object) -join '|') -ceq (@($expectedAlgorithms | Sort-Object) -join '|')) "Algorithm cohort mismatch at row $index."
    Require-Condition ((@($record.algorithmOrder | ForEach-Object { $_.anonymousLaneId } | Sort-Object) -join '|') -ceq (@($expectedAnonymousLanes | Sort-Object) -join '|')) "Anonymous-lane cohort mismatch at row $index."
    Require-Condition ((@($record.algorithmOrder | ForEach-Object { [string]$_.algorithmId }) -join '|') -ceq (@($williamsOrders[[int]$record.orderIndex]) -join '|')) "Williams-order mismatch at row $index."
    foreach ($lane in $record.algorithmOrder) { $null = $identityHashes.Add([string]$lane.identityBindingSha256) }
    $inputFull = Get-NormalizedFullPath -Path ([string]$record.inputRelativePath) -Base $projectRootFull
    Assert-InsideProject -Path $inputFull -Root $projectRootFull -Label 'Input bundle'
    Assert-Hash -Path $inputFull -Expected ([string]$record.inputSha256) -Label "input $($record.superblockId)"
    $inputRelative = Get-ProjectRelativePath -Path $inputFull -Root $projectRootFull
    Require-Condition ([string]$record.inputRelativePath -ceq $inputRelative -and $seenInputs.Add($inputRelative)) "Input path is non-canonical or duplicate at row $index."
    $bundle = Read-Json -Path $inputFull
    Require-Condition ($bundle.schema -eq 'gate14re-me-formal-st-input-bundle-v5' -and $bundle.studyId -eq $studyId -and $bundle.designId -eq 'gate14re-me-formal-st-bounded-gnf-v5' -and $bundle.protocolId -eq 'gate14re-me-formal-st-v5' -and $bundle.superblockId -eq $record.superblockId -and @($bundle.eventGroups).Count -eq 24) "Input bundle identity/cardinality mismatch at row $index."
    Require-Condition ([int]$bundle.gridEdge -in @(64, 96, 128)) "Input G is outside the bounded v5 set at row $index."
    Require-Condition ([int]$bundle.agentCount -in @(32, 64, 128)) "Input N is outside the bounded v5 set at row $index."
    Require-Condition ([int]$bundle.changedCellCount -in @(1, 9, 25, 81)) "Input F is outside the bounded v5 set at row $index."
    Require-Condition ([string]$bundle.designRegion -in @('core', 'stress')) "Input design region is invalid at row $index."
    foreach ($group in $bundle.eventGroups) { Require-Condition ([string]$group.topology -eq [string]$bundle.changeTopology) "Input event-group topology mismatch at row $index." }
    $cellKey = "$($bundle.gridEdge):$($bundle.agentCount):$($bundle.changedCellCount)"
    if (-not $cellCounts.ContainsKey($cellKey)) { $cellCounts[$cellKey] = 0 }
    $cellCounts[$cellKey] = [int]$cellCounts[$cellKey] + 1
    $orderCounts[[int]$record.orderIndex] = [int]$orderCounts[[int]$record.orderIndex] + 1
}
Require-Condition ($identityHashes.Count -eq 1) 'Schedule does not bind exactly one sealed identity hash.'
Require-Condition ($cellCounts.Count -eq 36) 'Schedule does not cover exactly 36 G x N x F cells.'
foreach ($cellKey in $cellCounts.Keys) { Require-Condition ([int]$cellCounts[$cellKey] -eq 36) "Schedule cell replicate count mismatch: $cellKey" }
foreach ($orderCount in $orderCounts) { Require-Condition ([int]$orderCount -eq 216) 'Schedule Williams-order global balance mismatch.' }
$identityBindingSha256 = [string]($identityHashes | Select-Object -First 1)
Require-Condition ($identityBindingSha256 -match '^[0-9a-f]{64}$') 'Schedule identity binding is not a lower-case SHA-256.'
Require-Condition (@(Get-CimInstance Win32_Process -Filter "Name = 'Unity.exe'").Count -eq 0) 'A Unity process is already active.'
$oracleBatchCount = [int]$authorization.oracleBatchCount
$oracleInputsPerBatch = [int](1296 / $oracleBatchCount)
$plannedFreshProcesses = 1 + $oracleBatchCount + 12 + 7776

$driveId = [System.IO.Path]::GetPathRoot($measuredRootFull).TrimEnd('\')
$drive = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='$driveId'"
$requiredReservation = [int64]$budget.formalRawAndDeliveryReservedStorageBytes
Require-Condition ($null -ne $drive -and [int64]$drive.FreeSpace -ge $requiredReservation) 'Host free space is below the frozen formal-st-acquisition reservation.'

try {
    # A later, separately authorized invocation reaches this mutation boundary.
    $null = New-Item -ItemType Directory -Path $measuredRootFull
    $measuredRootCreated = $true
    foreach ($relative in @('_control', '_control/process-identities', '_control/process-lifecycle', '_control/unity-logs', 'oracle', 'oracle-batches', 'raw/superblocks', 'raw/empty-boundary', 'instruments')) { $null = New-Item -ItemType Directory -Path (Join-Path $measuredRootFull $relative) }
    $processIdentityRoot = Join-Path $measuredRootFull '_control/process-identities'
    $processLifecycleRoot = Join-Path $measuredRootFull '_control/process-lifecycle'
    $unityLogRoot = Join-Path $measuredRootFull '_control/unity-logs'
    $processLedger = Join-Path $measuredRootFull '_control/process-ledger.raw.v5.jsonl'
    $voidLedger = Join-Path $measuredRootFull '_control/failures-and-voids.raw.v5.jsonl'
    $replacementLedger = Join-Path $measuredRootFull '_control/replacement-ledger.raw.v5.jsonl'
    foreach ($file in @($processLedger, $voidLedger, $replacementLedger)) { $null = New-Item -ItemType File -Path $file }
    Write-JsonExclusive -Path (Join-Path $measuredRootFull '_control/launch-receipt.v2.json') -Value ([ordered]@{
        schema = 'gate14re-me-formal-st-launch-receipt-v5'; studyId = $studyId; status = 'AUTHORIZED_FORMAL_ST_ACQUISITION_STARTED'
        executionAuthorizationSha256 = $ExecutionAuthorizationSha256; implementationManifestSha256 = $ImplementationManifestSha256
        executionContractSha256 = $ExecutionContractSha256; inputFreezeManifestSha256 = $InputFreezeManifestSha256
        resourceBudgetSha256 = $ResourceBudgetSha256; fairnessBindingSha256 = $FairnessBindingSha256; scheduleSha256 = $ScheduleSha256
        identityBindingSha256 = $identityBindingSha256
        trustedIdentityRuleSha256 = $TrustedIdentityRuleSha256; timestampComparatorSha256 = $TimestampComparatorSha256
        unityExecutableSha256 = $UnityExecutableSha256
        implementationRevision = 'v5.1-host-lifecycle-corrigendum'
        runnerMethod = $runnerMethod; commandLineQuitPresent = $false; runnerOwnsTerminalExit = $true
        hostLifecycleTimeoutsMilliseconds = [ordered]@{
            unityStartupAndValidation = [int64]$budget.unityStartupAndValidationHardTimeoutMilliseconds
            postOutputBurstDrain = [int64]$budget.burstCompletionTimeoutMilliseconds
            editorNaturalExitGrace = [int64]$budget.editorNaturalExitGraceMilliseconds
            lifecyclePoll = [int64]$budget.lifecyclePollMilliseconds
            lifecycleReceiptObservationGrace = [int64]$budget.lifecycleReceiptObservationGraceMilliseconds
        }
        replacementPolicy = 'ZERO_REPLACEMENT_FAIL_STOP'
        plannedSuperblocks = 1296; plannedAlgorithmLanes = 7776; plannedOracleBatches = $oracleBatchCount; plannedFreshProcesses = $plannedFreshProcesses
        oracleCachePolicy = 'ONE_HASH_BOUND_ALGORITHM_NEUTRAL_CACHE_PER_INPUT_REUSED_READ_ONLY_BY_SIX_LANES'
        acquisitionAcceptanceSeparation = 'ACQUISITION_ONLY_THEN_INDEPENDENT_READ_ONLY_OFFLINE_ACCEPTANCE'
        startedAtUtc = [DateTime]::UtcNow.ToString('o')
    })

    Invoke-VerifiedFreshUnityProcess -Mode 'instrument-self-test' -OutputDirectory (Join-Path $measuredRootFull 'instruments/csharp') -AdditionalArguments @() -TimeoutMilliseconds ([int64]$budget.instrumentProcessHardTimeoutMilliseconds)
    $null = Assert-Receipt -Path (Join-Path $measuredRootFull 'instruments/csharp/instrument-readiness-receipt.v5.json') -ExpectedStatus 'PASS_FORMAL_ST_INSTRUMENT_COMPONENTS_PYTHON_ROUNDTRIP_PENDING'
    for ($batchIndex = 0; $batchIndex -lt $oracleBatchCount; $batchIndex++) {
        $oracleBatchOutput = Join-Path $measuredRootFull ('oracle-batches/batch-{0:D2}' -f $batchIndex)
        Invoke-VerifiedFreshUnityProcess -Mode 'oracle-batch' -OutputDirectory $oracleBatchOutput -AdditionalArguments @('--g14me-oracle-batch-index', "$batchIndex") -TimeoutMilliseconds ([int64]$budget.oracleBatchHardTimeoutMilliseconds)
        $batchReceipt = Assert-Receipt -Path (Join-Path $oracleBatchOutput 'oracle-batch-receipt.v5.json') -ExpectedStatus 'PASS_ORACLE_BATCH_COMPLETE_V5'
        Require-Condition ([int]$batchReceipt.batchIndex -eq $batchIndex -and [int]$batchReceipt.batchCount -eq $oracleBatchCount -and [string]$batchReceipt.assignmentRule -ceq 'schedule-ordinal-mod-authorization-batch-count-v5' -and [int]$batchReceipt.inputCount -eq $oracleInputsPerBatch -and @($batchReceipt.members).Count -eq $oracleInputsPerBatch) "Oracle batch $batchIndex has invalid membership/cardinality."
    }
    foreach ($record in $records) {
        $cacheBindingPath = Join-Path $measuredRootFull "oracle/$($record.superblockId)/oracle-cache-binding-receipt.v5.json"
        $cacheBinding = Assert-Receipt -Path $cacheBindingPath -ExpectedStatus 'PASS_FROZEN_ALGORITHM_NEUTRAL_ORACLE_CACHE_V5'
        Require-Condition ([int]$cacheBinding.scheduleOrdinal -eq [int]$record.ordinal -and [int]$cacheBinding.batchIndex -eq (Get-FormalSTOracleBatchIndexV5 -Ordinal ([int]$record.ordinal) -BatchCount $oracleBatchCount) -and [string]$cacheBinding.superblockId -ceq [string]$record.superblockId) 'Oracle cache binding schedule identity mismatch.'
    }
    for ($ordinal = 0; $ordinal -lt 12; $ordinal++) {
        $emptyOutput = Join-Path $measuredRootFull ('raw/empty-boundary/process-{0:D2}' -f $ordinal)
        Invoke-VerifiedFreshUnityProcess -Mode 'empty-boundary' -OutputDirectory $emptyOutput -AdditionalArguments @('--g14me-process-ordinal', "$ordinal") -TimeoutMilliseconds ([int64]$budget.emptyBoundaryProcessHardTimeoutMilliseconds)
        $null = Assert-Receipt -Path (Join-Path $emptyOutput 'empty-boundary-receipt.v5.json') -ExpectedStatus 'COMPLETE_EMPTY_BOUNDARY_RAW'
    }
    foreach ($record in $records) {
        $inputFull = Get-NormalizedFullPath -Path ([string]$record.inputRelativePath) -Base $projectRootFull
        Invoke-Superblock -Record $record -InputFull $inputFull
    }
    Require-Condition ($processOrdinal -eq $plannedFreshProcesses) "Terminal process ordinal mismatch: expected $plannedFreshProcesses; actual $processOrdinal."
    Require-Condition ((Get-Item -LiteralPath $voidLedger).Length -eq 0) 'Failure/void ledger is not empty at acquisition completion.'
    Require-Condition ((Get-Item -LiteralPath $replacementLedger).Length -eq 0) 'Replacement ledger is not empty under the zero-replacement contract.'
    Write-JsonExclusive -Path (Join-Path $measuredRootFull '_control/acquisition-complete.v5.json') -Value ([ordered]@{
        schema = 'gate14re-me-formal-st-acquisition-complete-v5'; studyId = $studyId; status = 'FORMAL_ST_ACQUISITION_COMPLETE_RAW_ACCEPTANCE_PENDING'
        plannedSuperblocks = 1296; acceptedSuperblocks = 1296; plannedAlgorithmLanes = 7776; acceptedAlgorithmLanes = 7776
        plannedOracleBatches = $oracleBatchCount; completedOracleBatches = $oracleBatchCount; algorithmNeutralOracleCaches = 1296; laneReferenceOracleEvaluations = 0
        unityProcessCount = $processOrdinal; wholeSuperblockReplacements = 0; formalCollectionAuthorized = $true; formalAnalysisAuthorized = $false
        formalSTTerminalPass = $false; independentReadOnlyOfflineAcceptanceRequired = $true
        rankingOrWinnerComputed = $false; completedAtUtc = [DateTime]::UtcNow.ToString('o')
    })
    Write-JsonExclusive -Path (Join-Path $measuredRootFull '_control/acceptance-pending.v5.json') -Value ([ordered]@{
        schema = 'gate14re-me-formal-st-acceptance-pending-v5'; studyId = $studyId
        status = 'SEALED_RAW_REQUIRES_NEW_READ_ONLY_OFFLINE_ACCEPTANCE_ATTEMPT'
        sourceMutationPermitted = $false; formalSTTerminalPass = $false
        duplicateCanonicalJsonlRequired = $false; csvRequired = $false; gzipRequired = $false
        typedParquetFullRoundTripRequired = $true; createdAtUtc = [DateTime]::UtcNow.ToString('o')
    })
    $freezeManifestPath = Join-Path $measuredRootFull '_control/acquisition-freeze-manifest.v5.json'
    Write-AcquisitionFreezeManifest -Root $measuredRootFull -Path $freezeManifestPath
    $freezeManifestSha256 = Get-Sha256Lower -Path $freezeManifestPath
    Write-JsonExclusive -Path (Join-Path $measuredRootFull '_control/acquisition-terminal-receipt.v5.json') -Value ([ordered]@{
        schema = 'gate14re-me-formal-st-acquisition-terminal-receipt-v5'; studyId = $studyId
        status = 'PASS_ACQUISITION_ONLY_RAW_FROZEN_ACCEPTANCE_PENDING'
        acquisitionFreezeManifestSha256 = $freezeManifestSha256
        plannedFreshProcesses = $plannedFreshProcesses; completedFreshProcesses = $plannedFreshProcesses
        formalSTTerminalPass = $false; formalCollectionPerformed = $true; formalAnalysisPerformed = $false
        rankingOrWinnerComputed = $false; completedAtUtc = [DateTime]::UtcNow.ToString('o')
    })
    Get-ChildItem -LiteralPath $measuredRootFull -File -Recurse | ForEach-Object { $_.IsReadOnly = $true }
}
catch {
    if ($measuredRootCreated -and (Test-Path -LiteralPath (Join-Path $measuredRootFull '_control') -PathType Container)) {
        $failurePath = Join-Path $measuredRootFull '_control/failure-receipt.v2.json'
        if (-not (Test-Path -LiteralPath $failurePath)) {
            Write-JsonExclusive -Path $failurePath -Value ([ordered]@{
                schema = 'gate14re-me-formal-st-supervisor-failure-receipt-v5'; studyId = $studyId; status = 'FAILED_CLOSED_NO_RETRY_NO_REPLACEMENT'
                failedMode = $currentMode; exactFailure = $_.Exception.Message; exceptionType = $_.Exception.GetType().FullName
                measuredRootCreated = $measuredRootCreated; deliveryRootCreated = $false; unityProcessCount = $processOrdinal
                retryPerformed = $false; replacementPerformed = $false; signalOrForcedTerminationSentBySupervisor = $false
                formalCollectionPerformed = $false; formalAnalysisPerformed = $false; rankingOrWinnerComputed = $false; failedAtUtc = [DateTime]::UtcNow.ToString('o')
            })
        }
    }
    throw
}
