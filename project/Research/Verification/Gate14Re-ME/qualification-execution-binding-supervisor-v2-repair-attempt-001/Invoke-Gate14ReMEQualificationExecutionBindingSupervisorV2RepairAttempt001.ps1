[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$studyId = 'Gate14Re-ME'
$authorizationId = 'gate14re-me-qualification-execution-binding-supervisor-v2-repair-attempt-001'
$projectRoot = [System.IO.Path]::GetFullPath('H:\DDM_Final_Project').TrimEnd('\')
$stageRoot = Join-Path $projectRoot 'Research\Verification\Gate14Re-ME\qualification-execution-binding-supervisor-v2-repair-attempt-001'
$priorRoot = Join-Path $projectRoot 'Research\Verification\Gate14Re-ME\qualification-execution-readiness-freeze-attempt-001'
$supervisorPath = Join-Path $projectRoot 'Research\Gate14Re-ME\Execution\v2\Run-Gate14ReMELoadQualification.v2.ps1'
$contractPath = Join-Path $projectRoot 'Research\Gate14Re-ME\Execution\v2\load-qualification-execution-contract.v2.json'
$trustedRulePath = Join-Path $projectRoot 'Research\Verification\Gate14Re-ME\unity-executable-identity-rule-offline-adjudication-attempt-005\trusted-launch-identity-rule.v1.json'
$timestampComparatorPath = Join-Path $projectRoot 'Research\Verification\Gate14Re-ME\unity-trusted-identity-timestamp-comparator-corrigendum-attempt-007\Gate14ReMETrustedTimestampComparatorV1.ps1'
$unityPath = [System.IO.Path]::GetFullPath('H:\UnityEditor\2022.3.30f1c1\Editor\Unity.exe')
$unityLogPath = Join-Path $stageRoot 'unity-compile-identity-probe.log'
$expectedUnitySha256 = '0a69d14cbe2ca82d0a6168da8156d9e0dd138a6b7d0260dcdea31fd3957ca9cf'
$expectedSupervisorSha256 = 'f51e0eb8f3d1367fdcc0a2fa450fb7f9e7994dc64954eff7f0cae2a92c9e6755'
$trustedRuleSha256 = 'f045ef93630202a72d603096687bac655b5b4ff01e8e0743e60d63881bbded06'
$timestampComparatorSha256 = 'd024c5471d1fc06fb08e9c9ca1c9cf612424d4299d8b8c6b856883745105eb27'
$priorFailureSha256 = 'feea3650801239a1e92ced9031b137f9c22f7e9a9a483d05a6456353f1827b57'
$chunkSizeBytes = 65536
$unityInvocationCount = 0
$unityProcess = $null
$unityLaunched = $false

function Require-Condition {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw [System.InvalidOperationException]::new($Message) }
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

function Get-StringSha256Lower {
    param([string]$Value)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try { return [Convert]::ToHexString($sha.ComputeHash([System.Text.UTF8Encoding]::new($false).GetBytes($Value))).ToLowerInvariant() }
    finally { $sha.Dispose() }
}

function Get-RelativePath {
    param([string]$Path, [string]$Root)
    $rootUri = [Uri]::new($Root.TrimEnd('\') + '\')
    return [Uri]::UnescapeDataString($rootUri.MakeRelativeUri([Uri]::new([System.IO.Path]::GetFullPath($Path))).ToString()).Replace('\', '/')
}

function Read-Json {
    param([string]$Path)
    return Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json -Depth 100
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

function Get-FileInventory {
    param([string]$Root)
    $result = [System.Collections.Generic.List[object]]::new()
    foreach ($file in @(Get-ChildItem -LiteralPath $Root -Recurse -Force -File | Sort-Object FullName)) {
        $result.Add([pscustomobject][ordered]@{
            relativePath = Get-RelativePath -Path $file.FullName -Root $Root
            bytes = [int64]$file.Length
            sha256 = Get-Sha256Lower -Path $file.FullName
        })
    }
    return @($result)
}

function Get-InventoryDigest {
    param([object[]]$Inventory)
    return Get-StringSha256Lower -Value (@($Inventory) | ConvertTo-Json -Depth 20 -Compress)
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
                $securityOffset = $optionalHeaderOffset + $(if ($magic -eq 0x20b) { 112 } else { 96 }) + 32
                $stream.Position = $securityOffset
                $certificateOffset = $reader.ReadUInt32()
                $certificateSize = $reader.ReadUInt32()
                $result.succeeded = $true
                $result.peHeaderOffset = $peOffset
                $result.optionalHeaderMagicHex = ('{0:x4}' -f $magic)
                $result.checksumFieldOffset = $checksumOffset
                $result.checksumHex = ('{0:x8}' -f $checksum)
                $result.securityDirectoryFieldOffset = $securityOffset
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
    param([string]$Path)
    $result = [System.Collections.Generic.List[object]]::new()
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
            $result.Add([pscustomobject][ordered]@{ chunkIndex = $index; offsetBytes = $offset; lengthBytes = $count; sha256 = $digest })
            $index++
            $offset += $count
            if ($count -lt $buffer.Length) { break }
        }
    }
    finally { $stream.Dispose() }
    return @($result)
}

function Get-Fingerprint {
    param([string]$Phase)
    $item = Get-Item -LiteralPath $script:unityPath -Force
    $signature = Get-AuthenticodeSignature -LiteralPath $script:unityPath
    $hashOne = Get-Sha256Lower -Path $script:unityPath
    $hashTwo = Get-DotNetSha256Lower -Path $script:unityPath
    return [pscustomobject][ordered]@{
        schema = 'gate14re-me-external-unity-compile-identity-fingerprint-v1'
        studyId = $script:studyId
        authorizationId = $script:authorizationId
        phase = $Phase
        capturedAtUtc = [DateTime]::UtcNow.ToString('o')
        path = $item.FullName.Replace('\', '/')
        lengthBytes = [int64]$item.Length
        creationTimeUtc = $item.CreationTimeUtc.ToString('o')
        lastWriteTimeUtc = $item.LastWriteTimeUtc.ToString('o')
        attributes = $item.Attributes.ToString()
        reparsePoint = (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0)
        fileIdentity = Get-NtfsFileIdentity -Path $script:unityPath
        peIdentity = Get-PeIdentity -Path $script:unityPath
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
        chunkHashes = @(Get-ChunkHashes -Path $script:unityPath)
    }
}

function Get-FingerprintHash {
    param([object]$Fingerprint)
    $item = @($Fingerprint.fullFileHashes | Where-Object { $_.method -eq 'powershell-get-filehash' })
    Require-Condition ($item.Count -eq 1) 'Fingerprint is missing powershell-get-filehash.'
    return [string]$item[0].sha256
}

function Compare-Serialized {
    param([object]$Left, [object]$Right)
    return (($Left | ConvertTo-Json -Depth 100 -Compress) -ceq ($Right | ConvertTo-Json -Depth 100 -Compress))
}

function Assert-Fingerprint {
    param([object]$Fingerprint, [object]$Rule, [string]$Phase)
    $app = $Rule.applicability
    Require-Condition $Fingerprint.independentHashMethodsAgree "$Phase external hash methods disagree."
    Require-Condition ((Get-FingerprintHash -Fingerprint $Fingerprint) -eq [string]$app.unityExecutableExpectedSha256) "$Phase Unity hash mismatch."
    Require-Condition (-not $Fingerprint.reparsePoint) "$Phase Unity path is a reparse point."
    Require-Condition ($Fingerprint.fileIdentity.succeeded -and [string]$Fingerprint.fileIdentity.fileIdHex -eq [string]$app.ntfsFileIdHex -and [string]$Fingerprint.fileIdentity.fileIndexLow64Hex -eq [string]$app.ntfsFileIndexLow64Hex) "$Phase NTFS identity mismatch."
    Require-Condition $Fingerprint.peIdentity.succeeded "$Phase PE identity is unavailable."
    Require-Condition ([string]$Fingerprint.authenticode.status -eq 'Valid' -and [string]$Fingerprint.authenticode.signerSubject -eq [string]$app.signerSubject -and [string]$Fingerprint.authenticode.signerThumbprint -eq [string]$app.signerThumbprint) "$Phase Authenticode identity mismatch."
    Require-Condition ([int64]$Fingerprint.lengthBytes -eq [int64]$app.fileLengthBytes) "$Phase executable length mismatch."
    Require-Condition ([System.IO.Path]::GetFullPath([string]$Fingerprint.path).TrimEnd('\') -ieq [System.IO.Path]::GetFullPath([string]$app.unityExecutablePath).TrimEnd('\')) "$Phase executable path mismatch."
    $creation = Compare-Gate14ReMETrustedTimestampV1 -TrustedText ([string]$app.creationTimeUtc) -ObservedText ([string]$Fingerprint.creationTimeUtc)
    $lastWrite = Compare-Gate14ReMETrustedTimestampV1 -TrustedText ([string]$app.lastWriteTimeUtc) -ObservedText ([string]$Fingerprint.lastWriteTimeUtc)
    Require-Condition $creation.comparisonAccepted "$Phase creation timestamp mismatch: $($creation.failureCode)"
    Require-Condition $lastWrite.comparisonAccepted "$Phase last-write timestamp mismatch: $($lastWrite.failureCode)"
}

function Assert-Stable {
    param([object]$Reference, [object]$Observed, [string]$Phase)
    Require-Condition ([string]$Reference.path -ieq [string]$Observed.path) "$Phase path changed."
    Require-Condition ([int64]$Reference.lengthBytes -eq [int64]$Observed.lengthBytes) "$Phase length changed."
    Require-Condition ([string]$Reference.creationTimeUtc -eq [string]$Observed.creationTimeUtc -and [string]$Reference.lastWriteTimeUtc -eq [string]$Observed.lastWriteTimeUtc) "$Phase raw timestamp text changed."
    Require-Condition ([string]$Reference.fileIdentity.fileIdHex -eq [string]$Observed.fileIdentity.fileIdHex) "$Phase file ID changed."
    Require-Condition (Compare-Serialized -Left $Reference.peIdentity -Right $Observed.peIdentity) "$Phase PE identity changed."
    Require-Condition (Compare-Serialized -Left $Reference.authenticode -Right $Observed.authenticode) "$Phase Authenticode identity changed."
    Require-Condition (Compare-Serialized -Left @($Reference.chunkHashes) -Right @($Observed.chunkHashes)) "$Phase 64 KiB chunk set changed."
}

function Get-ProhibitedRootsPresent {
    return @(
        'Research/PilotRuns/Gate14Re-ME/load-qualification/attempt-001',
        'Research/FormalRuns/Gate14Re-ME',
        'Research/Exports/Gate14Re-ME/load-qualification/attempt-001'
    ) | Where-Object { Test-Path -LiteralPath (Join-Path $script:projectRoot $_) }
}

try {
Require-Condition (Test-Path -LiteralPath $stageRoot -PathType Container) 'Attempt root is missing.'
foreach ($name in @('precompile-static-known-answer-receipt.v1.json', 'external-prelaunch-fingerprint.v1.json', 'external-live-fingerprint.v1.json', 'external-post-exit-fingerprint.v1.json', 'process-launch-receipt.v1.json', 'compile-identity-receipt.v1.json', 'failure-receipt.v1.json')) {
    Require-Condition (-not (Test-Path -LiteralPath (Join-Path $stageRoot $name))) "Attempt evidence already exists; retry/overwrite prohibited: $name"
}
Require-Condition (-not (Test-Path -LiteralPath $unityLogPath)) 'Unity log already exists; retry/overwrite prohibited.'

$priorBefore = @(Get-FileInventory -Root $priorRoot)
$priorDigestBefore = Get-InventoryDigest -Inventory $priorBefore
Require-Condition ($priorBefore.Count -eq 7) 'Retained readiness attempt file count changed.'
Require-Condition ((Get-Sha256Lower -Path (Join-Path $priorRoot 'failure-receipt.v1.json')) -eq $priorFailureSha256) 'Retained readiness failure receipt drifted.'
Require-Condition (@(Get-CimInstance Win32_Process -Filter "Name = 'Unity.exe'").Count -eq 0) 'A Unity process is already active.'
Require-Condition (@(Get-ProhibitedRootsPresent).Count -eq 0) 'A prohibited measured/formal/delivery root already exists.'
Require-Condition ((Get-Sha256Lower -Path $supervisorPath) -eq $expectedSupervisorSha256) 'Supervisor v2 hash differs from the precompile frozen value.'
Require-Condition ((Get-Sha256Lower -Path $trustedRulePath) -eq $trustedRuleSha256) 'Trusted identity rule hash drifted.'
Require-Condition ((Get-Sha256Lower -Path $timestampComparatorPath) -eq $timestampComparatorSha256) 'Timestamp comparator hash drifted.'
Require-Condition ((Get-Sha256Lower -Path $unityPath) -eq $expectedUnitySha256) 'Unity executable hash drifted.'

$tokens = $null
$parseErrors = $null
[System.Management.Automation.Language.Parser]::ParseFile($supervisorPath, [ref]$tokens, [ref]$parseErrors) | Out-Null
Require-Condition (@($parseErrors).Count -eq 0) 'Supervisor v2 has a PowerShell parse error.'
$supervisorText = Get-Content -LiteralPath $supervisorPath -Raw -Encoding UTF8
$requiredSupervisorTokens = @(
    'Gate14ReMELoadQualificationRunnerV2.Run', 'lane-receipt.v2.json', 'empty-boundary-receipt.v2.json',
    'instrument-csharp-receipt.v2.json', 'PRELAUNCH', 'LIVE_CONCURRENT', 'POST_EXIT',
    'Compare-Gate14ReMETrustedTimestampV1', 'exactCommandLine', 'ZERO_REPLACEMENT_FAIL_STOP',
    'StructuralTool', 'DeliveryTool', 'contract.frozenBindings',
    'PASS_SCHEMA_V2_STRUCTURAL_COMPLETE_RAW_NO_INFERENCE', 'PASS_VERIFIED_SCHEMA_V2_COMPLETE_PER_OBSERVATION_DELIVERY'
)
$missingSupervisorTokens = @($requiredSupervisorTokens | Where-Object { -not $supervisorText.Contains($_) })
Require-Condition ($missingSupervisorTokens.Count -eq 0) "Supervisor v2 is missing required static tokens: $($missingSupervisorTokens -join ', ')"
$forbiddenSupervisorTokens = @('Gate14ReMELoadQualificationRunnerV1.Run', 'lane-receipt.v1.json', 'empty-boundary-receipt.v1.json', 'instrument-csharp-receipt.v1.json', 'Stop-Process')
$presentForbiddenTokens = @($forbiddenSupervisorTokens | Where-Object { $supervisorText.Contains($_) })
Require-Condition ($presentForbiddenTokens.Count -eq 0) "Supervisor v2 contains forbidden stale/termination tokens: $($presentForbiddenTokens -join ', ')"

$contract = Read-Json -Path $contractPath
Require-Condition ($contract.schema -eq 'gate14re-me-load-qualification-execution-contract-v2' -and $contract.status -eq 'FROZEN_EXECUTION_BINDING_V2_QUALIFICATION_EXECUTION_UNAUTHORIZED') 'Execution contract v2 header mismatch.'
Require-Condition ($contract.entryPoint.supervisorSha256 -eq $expectedSupervisorSha256 -and $contract.entryPoint.runnerSha256 -eq '39d371a5a9e858836bc448aabb04656e8576e296ca9b1cedb479cd3552ad1d73') 'Execution contract v2 entry-point binding mismatch.'
foreach ($property in $contract.frozenBindings.PSObject.Properties) {
    $binding = $property.Value
    if ($null -ne $binding.relativePath -and $null -ne $binding.sha256) {
        $full = Join-Path $projectRoot ([string]$binding.relativePath)
        Require-Condition ((Get-Sha256Lower -Path $full) -eq [string]$binding.sha256) "Execution contract frozen binding drifted: $($binding.relativePath)"
    }
}

$schedulePath = Join-Path $projectRoot ([string]$contract.frozenBindings.schedule.relativePath)
$scheduleRows = @(Get-Content -LiteralPath $schedulePath -Encoding UTF8 | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | ForEach-Object { $_ | ConvertFrom-Json -Depth 100 })
Require-Condition ($scheduleRows.Count -eq 162) 'Schedule row count is not 162.'
Require-Condition (@($scheduleRows | Where-Object { $null -ne $_.replacement }).Count -eq 0) 'Schedule contains a replacement asset; zero-replacement freeze failed.'
Require-Condition (@($scheduleRows | Where-Object { @($_.algorithmOrder).Count -ne 6 }).Count -eq 0) 'One or more schedule rows do not contain six lanes.'

. $timestampComparatorPath
$sameInstant = Compare-Gate14ReMETrustedTimestampV1 -TrustedText '2024-06-11T11:26:54Z' -ObservedText '2024-06-11T11:26:54.0000000Z'
$differentInstant = Compare-Gate14ReMETrustedTimestampV1 -TrustedText '2024-06-11T11:26:54Z' -ObservedText '2024-06-11T11:26:55Z'
$invalidInstant = Compare-Gate14ReMETrustedTimestampV1 -TrustedText 'not-a-time' -ObservedText '2024-06-11T11:26:54Z'
$missingInstant = Compare-Gate14ReMETrustedTimestampV1 -TrustedText $null -ObservedText '2024-06-11T11:26:54Z'
Require-Condition ($sameInstant.comparisonAccepted -and -not $differentInstant.comparisonAccepted -and -not $invalidInstant.comparisonAccepted -and -not $missingInstant.comparisonAccepted) 'Attempt-007 timestamp comparator known-answer failed.'

Write-JsonExclusive -Path (Join-Path $stageRoot 'precompile-static-known-answer-receipt.v1.json') -Value ([ordered]@{
    schema = 'gate14re-me-qualification-execution-binding-supervisor-v2-static-known-answer-receipt-v1'
    studyId = $studyId
    authorizationId = $authorizationId
    status = 'PASS_PRECOMPILE_STATIC_BINDING_KNOWN_ANSWER'
    completedAtUtc = [DateTime]::UtcNow.ToString('o')
    supervisorSha256 = $expectedSupervisorSha256
    executionContractSha256 = Get-Sha256Lower -Path $contractPath
    supervisorPowerShellParsePassed = $true
    runnerV2AndReceiptV2BindingPassed = $true
    threePhaseIdentityStaticBindingPassed = $true
    processCompositeIdentityStaticBindingPassed = $true
    structuralV2AndDeliveryV2TerminalChainStaticBindingPassed = $true
    scheduleRows = $scheduleRows.Count
    scheduleReplacementAssets = 0
    zeroReplacementFailStopPassed = $true
    timestampComparatorKnownAnswersPassed = $true
    priorFailureRetained = $true
    measuredRootCreated = $false
    algorithmLaneExecuted = $false
    formalObservationProduced = $false
    rankingOrWinnerComputed = $false
})

    $rule = Read-Json -Path $trustedRulePath
    $pre = Get-Fingerprint -Phase 'EXTERNAL_PRELAUNCH'
    Assert-Fingerprint -Fingerprint $pre -Rule $rule -Phase 'prelaunch'
    Write-JsonExclusive -Path (Join-Path $stageRoot 'external-prelaunch-fingerprint.v1.json') -Value $pre

    $arguments = @('-batchmode', '-nographics', '-quit', '-projectPath', $projectRoot, '-logFile', $unityLogPath)
    $argumentLine = ($arguments | ForEach-Object { if ($_ -match '[\s"]') { '"' + ($_ -replace '"', '\"') + '"' } else { $_ } }) -join ' '
    $expectedCommandLine = '"' + $unityPath + '" ' + $argumentLine
    $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $unityPath
    $startInfo.Arguments = $argumentLine
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $launchedAtUtc = [DateTime]::UtcNow
    $unityProcess = [System.Diagnostics.Process]::Start($startInfo)
    Require-Condition ($null -ne $unityProcess) 'Unity process creation returned null.'
    $unityLaunched = $true
    $unityInvocationCount = 1
    $pidValue = $unityProcess.Id
    $liveMetadata = $null
    for ($poll = 0; $poll -lt 200 -and $null -eq $liveMetadata; $poll++) {
        $liveMetadata = Get-CimInstance Win32_Process -Filter "ProcessId = $pidValue"
        if ($null -eq $liveMetadata) { Start-Sleep -Milliseconds 50 }
    }
    Require-Condition ($null -ne $liveMetadata) 'Unable to capture live Unity process metadata.'
    $creationTimeUtc = ([DateTime]$liveMetadata.CreationDate).ToUniversalTime()
    $startDeltaMilliseconds = [Math]::Abs(($creationTimeUtc - $launchedAtUtc).TotalMilliseconds)
    Require-Condition ($startDeltaMilliseconds -le 1000.0) "Unity process creation-time delta exceeded 1000 ms: $startDeltaMilliseconds"
    Require-Condition ([System.IO.Path]::GetFullPath([string]$liveMetadata.ExecutablePath).TrimEnd('\') -ieq $unityPath) 'Live Unity executable path mismatch.'
    Require-Condition ([string]$liveMetadata.CommandLine -ceq $expectedCommandLine) "Live Unity exact command line mismatch. Expected: $expectedCommandLine Observed: $($liveMetadata.CommandLine)"
    Require-Condition (-not ([string]$liveMetadata.CommandLine).Contains('-executeMethod')) 'Compile identity probe unexpectedly contains an execute method.'
    Write-JsonExclusive -Path (Join-Path $stageRoot 'process-launch-receipt.v1.json') -Value ([ordered]@{
        schema = 'gate14re-me-algorithm-free-unity-compile-process-launch-receipt-v1'
        studyId = $studyId
        authorizationId = $authorizationId
        status = 'CAPTURED_EXACT_COMPOSITE_PROCESS_IDENTITY'
        processId = $pidValue
        creationTimeUtc = $creationTimeUtc.ToString('o')
        launchedAtUtc = $launchedAtUtc.ToString('o')
        processStartDeltaMilliseconds = $startDeltaMilliseconds
        executablePath = ([string]$liveMetadata.ExecutablePath).Replace('\', '/')
        exactCommandLine = [string]$liveMetadata.CommandLine
        exactCommandLineSha256 = Get-StringSha256Lower -Value ([string]$liveMetadata.CommandLine)
        executeMethod = $null
        projectPath = $projectRoot.Replace('\', '/')
        unityInvocationOrdinal = 1
    })

    Require-Condition (-not $unityProcess.HasExited) 'Unity exited before the live-concurrent fingerprint could be captured.'
    $live = Get-Fingerprint -Phase 'EXTERNAL_LIVE_CONCURRENT'
    Require-Condition (-not $unityProcess.HasExited) 'Unity exited during the live-concurrent fingerprint capture.'
    Assert-Fingerprint -Fingerprint $live -Rule $rule -Phase 'live'
    Assert-Stable -Reference $pre -Observed $live -Phase 'live'
    Write-JsonExclusive -Path (Join-Path $stageRoot 'external-live-fingerprint.v1.json') -Value $live

    $naturalExit = $unityProcess.WaitForExit(1200000)
    Require-Condition $naturalExit 'Unity did not exit naturally within 20 minutes; no signal was sent.'
    $exitCode = $unityProcess.ExitCode
    $exitedAtUtc = [DateTime]::UtcNow
    Require-Condition ($exitCode -eq 0) "Unity compile identity probe exited nonzero: $exitCode"
    Require-Condition (@(Get-CimInstance Win32_Process -Filter "ProcessId = $pidValue").Count -eq 0) 'Unity PID still exists after natural WaitForExit.'
    $post = Get-Fingerprint -Phase 'EXTERNAL_POST_EXIT'
    Assert-Fingerprint -Fingerprint $post -Rule $rule -Phase 'post-exit'
    Assert-Stable -Reference $pre -Observed $post -Phase 'post-exit'
    Write-JsonExclusive -Path (Join-Path $stageRoot 'external-post-exit-fingerprint.v1.json') -Value $post

    Require-Condition (Test-Path -LiteralPath $unityLogPath -PathType Leaf) 'Unity compile log is missing.'
    $logText = Get-Content -LiteralPath $unityLogPath -Raw -Encoding UTF8
    $compilerErrorPatterns = @('error CS\d{4}', 'Scripts have compiler errors', 'Compilation failed', 'CompilerError', 'Aborting batchmode due to failure')
    $compilerErrorMatches = @($compilerErrorPatterns | Where-Object { $logText -match $_ })
    Require-Condition ($compilerErrorMatches.Count -eq 0) "Unity compile log contains a failure marker: $($compilerErrorMatches -join ', ')"
    $editorAssemblyPath = Join-Path $projectRoot 'Library\ScriptAssemblies\Assembly-CSharp-Editor.dll'
    $runtimeAssemblyPath = Join-Path $projectRoot 'Library\ScriptAssemblies\Assembly-CSharp.dll'
    Require-Condition (Test-Path -LiteralPath $editorAssemblyPath -PathType Leaf) 'Assembly-CSharp-Editor.dll is missing after Unity compilation.'
    Require-Condition (Test-Path -LiteralPath $runtimeAssemblyPath -PathType Leaf) 'Assembly-CSharp.dll is missing after Unity compilation.'

    $priorAfter = @(Get-FileInventory -Root $priorRoot)
    $priorDigestAfter = Get-InventoryDigest -Inventory $priorAfter
    Require-Condition ($priorDigestAfter -eq $priorDigestBefore) 'Retained readiness failure evidence changed during the repair.'
    Require-Condition (@(Get-ProhibitedRootsPresent).Count -eq 0) 'A prohibited measured/formal/delivery root appeared during the compile probe.'
    Require-Condition (@(Get-CimInstance Win32_Process -Filter "Name = 'Unity.exe'").Count -eq 0) 'A Unity process remains after the compile probe.'

    Write-JsonExclusive -Path (Join-Path $stageRoot 'compile-identity-receipt.v1.json') -Value ([ordered]@{
        schema = 'gate14re-me-qualification-execution-binding-unity-compile-identity-receipt-v1'
        studyId = $studyId
        authorizationId = $authorizationId
        status = 'PASS_CURRENT_PROJECT_COMPILED_ALGORITHM_FREE_TRUSTED_IDENTITY'
        completedAtUtc = [DateTime]::UtcNow.ToString('o')
        unityInvocationCount = $unityInvocationCount
        processId = $pidValue
        creationTimeUtc = $creationTimeUtc.ToString('o')
        launchedAtUtc = $launchedAtUtc.ToString('o')
        exitedAtUtc = $exitedAtUtc.ToString('o')
        exitCode = $exitCode
        naturalExit = $true
        signalOrForcedTerminationSent = $false
        retryPerformed = $false
        executeMethod = $null
        currentProjectCompiled = $true
        compilerFailureMarkersFound = 0
        trustedIdentityRuleSha256 = $trustedRuleSha256
        timestampComparatorSha256 = $timestampComparatorSha256
        prelaunchFingerprintSha256 = Get-Sha256Lower -Path (Join-Path $stageRoot 'external-prelaunch-fingerprint.v1.json')
        liveFingerprintSha256 = Get-Sha256Lower -Path (Join-Path $stageRoot 'external-live-fingerprint.v1.json')
        postExitFingerprintSha256 = Get-Sha256Lower -Path (Join-Path $stageRoot 'external-post-exit-fingerprint.v1.json')
        processLaunchReceiptSha256 = Get-Sha256Lower -Path (Join-Path $stageRoot 'process-launch-receipt.v1.json')
        unityLogSha256 = Get-Sha256Lower -Path $unityLogPath
        editorAssembly = [ordered]@{ relativePath = Get-RelativePath -Path $editorAssemblyPath -Root $projectRoot; bytes = (Get-Item -LiteralPath $editorAssemblyPath).Length; sha256 = Get-Sha256Lower -Path $editorAssemblyPath }
        runtimeAssembly = [ordered]@{ relativePath = Get-RelativePath -Path $runtimeAssemblyPath -Root $projectRoot; bytes = (Get-Item -LiteralPath $runtimeAssemblyPath).Length; sha256 = Get-Sha256Lower -Path $runtimeAssemblyPath }
        priorReadinessFailureEvidenceUnchanged = $true
        priorReadinessEvidenceInventoryDigestBefore = $priorDigestBefore
        priorReadinessEvidenceInventoryDigestAfter = $priorDigestAfter
        measuredRootCreated = $false
        deliveryRootCreated = $false
        plannerInvocations = 0
        algorithmLaneExecutions = 0
        qualificationObservations = 0
        formalObservations = 0
        replacementAssetsGenerated = 0
        formalAnalysisPerformed = $false
        rankingOrWinnerComputed = $false
    })
}
catch {
    $failurePath = Join-Path $stageRoot 'failure-receipt.v1.json'
    if (-not (Test-Path -LiteralPath $failurePath)) {
        Write-JsonExclusive -Path $failurePath -Value ([ordered]@{
            schema = 'gate14re-me-qualification-execution-binding-supervisor-v2-repair-failure-receipt-v1'
            studyId = $studyId
            authorizationId = $authorizationId
            status = 'FAILED_CLOSED_EXECUTION_BINDING_SUPERVISOR_V2_REPAIR'
            failedAtUtc = [DateTime]::UtcNow.ToString('o')
            exceptionType = $_.Exception.GetType().FullName
            exactFailure = $_.Exception.Message
            unityInvocationCount = $unityInvocationCount
            unityLaunched = $unityLaunched
            retryPerformed = $false
            signalOrForcedTerminationSent = $false
            measuredRootCreated = @((Get-ProhibitedRootsPresent)).Count -gt 0
            plannerInvocations = 0
            algorithmLaneExecutions = 0
            qualificationObservations = 0
            formalObservations = 0
            replacementAssetsGenerated = 0
            formalAnalysisPerformed = $false
            rankingOrWinnerComputed = $false
        })
    }
    throw
}
