[CmdletBinding()]
param([string]$ProjectPath = (Split-Path -Parent $PSScriptRoot))

$ErrorActionPreference = 'Stop'
$ProjectPath = [System.IO.Path]::GetFullPath($ProjectPath)
$modulePath = Join-Path $PSScriptRoot 'Gate13ProcessReusePreparation.psm1'
Import-Module $modulePath -Force

$pilotRoot = Join-Path $ProjectPath 'Research\PilotRuns\Gate13_ProcessReuse\v1'
$formalRoot = Join-Path $ProjectPath 'Research\FormalRuns\Gate13_ProcessReuse\v1'
$manifestPath = Join-Path $ProjectPath 'Research\Gate13_ProcessReuse_Pilot_v1_Failure_Output_Manifest.json'
$receiptPath = Join-Path $ProjectPath 'Research\Gate13_ProcessReuse_Pilot_v1_Failure_Receipt.v1.json'
$checkpointPath = Join-Path $pilotRoot 'pilot-checkpoint.json'
$failurePath = Join-Path $pilotRoot 'pilot-failure.json'
$executionManifestPath = Join-Path $pilotRoot 'pilot-execution-manifest.json'
$pilotManifestPath = Join-Path $pilotRoot 'pilot-manifest.json'
$analysisStdoutPath = Join-Path $pilotRoot 'analysis.stdout.log'

foreach ($path in @($pilotRoot, $checkpointPath, $failurePath, $executionManifestPath, $pilotManifestPath, $analysisStdoutPath)) {
    if (-not (Test-Path -LiteralPath $path)) { throw "Required failed-pilot evidence is missing: $path" }
}
foreach ($path in @($manifestPath, $receiptPath)) {
    if (Test-Path -LiteralPath $path) { throw "Create-new failure archive already exists: $path" }
}
if (Test-Path -LiteralPath $formalRoot) { throw 'Reserved process-reuse formal root must remain absent.' }
if (@(Get-Process -Name Unity -ErrorAction SilentlyContinue).Count -gt 0) { throw 'Unity must be stopped before sealing the pilot.' }
if (Test-Path -LiteralPath (Join-Path $ProjectPath 'Temp\UnityLockfile')) { throw 'Unity lockfile must be absent before sealing the pilot.' }

$checkpoint = Read-G13R2Json -Path $checkpointPath
$failure = Read-G13R2Json -Path $failurePath
$execution = Read-G13R2Json -Path $executionManifestPath
$pilot = Read-G13R2Json -Path $pilotManifestPath
if ($checkpoint.status -ne 'failed-no-auto-retry' -or $checkpoint.automaticRetryAuthorized -ne $false -or $checkpoint.automaticResumeAuthorized -ne $false) { throw 'Pilot checkpoint is not a terminal no-retry/no-resume failure.' }
if ($failure.automaticRetryAttempted -ne $false -or $failure.automaticResumeAttempted -ne $false) { throw 'Pilot failure record reports a retry or resume.' }
if ($execution.completed -ne $true -or [int]$execution.totalUnityProcessCount -ne 45 -or [int]$execution.measuredBlockProcessCount -ne 36 -or [int]$execution.measuredSampleCount -ne 96) { throw 'Pilot execution cardinality is incomplete.' }
if ($pilot.completed -ne $false -or [int]$pilot.structuralMismatchCount -ne 0 -or [int]$pilot.hardErrorCount -ne 208 -or $pilot.formalExecutionAuthorized -ne $false -or $pilot.excludedFromFormalAnalysis -ne $true) { throw 'Pilot analysis failure identity is not the expected fail-closed result.' }

$workingSetErrors = @($pilot.hardErrors | Where-Object { $_ -like 'Non-positive telemetry workingSetBytes:*' }).Count
$privateMemoryErrors = @($pilot.hardErrors | Where-Object { $_ -like 'Non-positive telemetry privateMemoryBytes:*' }).Count
$managedGrowthErrors = @($pilot.hardErrors | Where-Object { $_ -like 'Managed-memory hard limit exceeded:*' }).Count
if ($workingSetErrors -ne 96 -or $privateMemoryErrors -ne 96 -or $managedGrowthErrors -ne 16) { throw 'Pilot hard-error classification changed before sealing.' }

$filesBeforeSeal = @(Get-ChildItem -LiteralPath $pilotRoot -File -Recurse -Force)
foreach ($file in $filesBeforeSeal) { $file.IsReadOnly = $true }
(Get-Item -LiteralPath $pilotRoot).Attributes = (Get-Item -LiteralPath $pilotRoot).Attributes -bor [System.IO.FileAttributes]::ReadOnly

$files = @(Get-ChildItem -LiteralPath $pilotRoot -File -Recurse -Force | Sort-Object FullName)
$records = New-Object System.Collections.Generic.List[object]
$identityLines = New-Object System.Collections.Generic.List[string]
foreach ($file in $files) {
    $relative = Get-G13R2ProjectRelativePath -ProjectPath $ProjectPath -FullPath $file.FullName
    $sha = Get-G13R2LowerSha256 -Path $file.FullName
    $records.Add([pscustomobject][ordered]@{
        relativePath = $relative
        byteCount = [int64]$file.Length
        lastWriteTimeUtc = $file.LastWriteTimeUtc.ToString('o')
        sha256 = $sha
        readOnly = [bool]$file.IsReadOnly
    })
    $identityLines.Add(('{0}|{1}|{2}' -f $relative, [int64]$file.Length, $sha))
}
$identityBytes = [System.Text.Encoding]::UTF8.GetBytes(($identityLines -join "`n"))
$sha256 = [System.Security.Cryptography.SHA256]::Create()
try { $aggregateSha256 = ([BitConverter]::ToString($sha256.ComputeHash($identityBytes))).Replace('-', '').ToLowerInvariant() }
finally { $sha256.Dispose() }

$outputManifest = [ordered]@{
    schemaVersion = 1
    manifestKind = 'gate13-r2-process-reuse-failed-pilot-output-manifest-v1'
    recordedAt = (Get-Date).ToString('o')
    rootAbsolutePath = [System.IO.Path]::GetFullPath($pilotRoot)
    rootRelativePath = 'Research/PilotRuns/Gate13_ProcessReuse/v1'
    disposition = @('FAILED-NO-AUTO-RETRY', 'NON-FORMAL', 'EXCLUDED-FROM-FORMAL-ANALYSIS', 'NO-RESUME', 'NOT-READY-FOR-FORMAL')
    fileCount = $files.Count
    rawByteCount = [int64](($files | Measure-Object Length -Sum).Sum)
    readOnlyFileCount = @($files | Where-Object IsReadOnly).Count
    aggregateSha256 = $aggregateSha256
    aggregateDefinition = 'sha256(UTF8(join(LF, sorted project-relative-path|raw-byte-count|lowercase-file-sha256)))'
    files = $records.ToArray()
}
Write-G13R2AtomicUtf8NoBomJson -Path $manifestPath -Value $outputManifest -Depth 30

function New-BoundEvidence([string]$Path) {
    return [ordered]@{
        relativePath = Get-G13R2ProjectRelativePath -ProjectPath $ProjectPath -FullPath $Path
        sha256 = Get-G13R2LowerSha256 -Path $Path
        byteCount = [int64](Get-Item -LiteralPath $Path).Length
    }
}

$receipt = [ordered]@{
    schemaVersion = 1
    receiptId = 'gate13-r2-process-reuse-pilot-v1-failure-receipt-v1'
    recordedAt = (Get-Date).ToString('o')
    authorizationReference = 'user-message-2026-10-06-gate13-cold-process-to-process-reuse-controlled-design-migration'
    status = 'FAILED-NO-AUTO-RETRY'
    dispositions = @('NON-FORMAL', 'EXCLUDED-FROM-FORMAL-ANALYSIS', 'NO-AUTO-RETRY', 'NO-RESUME', 'NOT-READY-FOR-FORMAL', 'CANDIDATE-N-NOT-ADMISSIBLE')
    execution = [ordered]@{
        totalUnityProcessCount = 45
        warmupBlockProcessCount = 1
        warmupSampleCount = 4
        freshColdProcessCount = 8
        freshColdSampleCount = 8
        measuredBlockProcessCount = 36
        measuredSampleCount = 96
        structuralMismatchCount = 0
        allPlannedSamplesExecuted = $true
        analysisAccepted = $false
    }
    analysisFailure = [ordered]@{
        hardErrorCount = 208
        nonPositiveWorkingSetTelemetryCount = $workingSetErrors
        nonPositivePrivateMemoryTelemetryCount = $privateMemoryErrors
        managedMemoryGrowthLimitExceededBlockCount = $managedGrowthErrors
        frozenManagedMemoryGrowthLimitBytesPerBlock = 134217728
        candidateSampleSizeOutputsAdmissible = $false
        readinessPassed = $false
    }
    evidence = [ordered]@{
        pilotPlan = New-BoundEvidence (Join-Path $ProjectPath 'Research\Gate13_ProcessReuse_Pilot_Plan.v1.json')
        provenanceV4 = New-BoundEvidence (Join-Path $ProjectPath 'Research\Gate13_ProcessReuse_Provenance.v4.json')
        prePilotAudit = New-BoundEvidence (Join-Path $ProjectPath 'Research\Verification\Gate13R2_PrePilotAudit.summary.json')
        executionManifest = New-BoundEvidence $executionManifestPath
        failedPilotManifest = New-BoundEvidence $pilotManifestPath
        failure = New-BoundEvidence $failurePath
        terminalCheckpoint = New-BoundEvidence $checkpointPath
        analysisStdout = New-BoundEvidence $analysisStdoutPath
        outputManifest = New-BoundEvidence $manifestPath
    }
    preservation = [ordered]@{
        pilotRootAbsolutePath = [System.IO.Path]::GetFullPath($pilotRoot)
        pilotRootReadOnly = $true
        pilotRootFileCount = $files.Count
        pilotRootRawByteCount = [int64](($files | Measure-Object Length -Sum).Sum)
        pilotRootAggregateSha256 = $aggregateSha256
        reservedFormalRootAbsolutePath = [System.IO.Path]::GetFullPath($formalRoot)
        reservedFormalRootCreated = $false
        formalExecutionReceiptCreated = $false
        automaticRetryAttempted = $false
        automaticResumeAttempted = $false
    }
    requiredNextAuthorization = 'A separately authorized, versioned telemetry/readiness repair and a fresh pilot root are required before formal process-reuse readiness can be reconsidered.'
}
Write-G13R2AtomicUtf8NoBomJson -Path $receiptPath -Value $receipt -Depth 30

[pscustomobject][ordered]@{
    passed = $true
    receiptPath = $receiptPath
    receiptSha256 = Get-G13R2LowerSha256 -Path $receiptPath
    outputManifestPath = $manifestPath
    outputManifestSha256 = Get-G13R2LowerSha256 -Path $manifestPath
    pilotRootFileCount = $files.Count
    pilotRootRawByteCount = [int64](($files | Measure-Object Length -Sum).Sum)
    pilotRootAggregateSha256 = $aggregateSha256
    readOnlyFileCount = @($files | Where-Object IsReadOnly).Count
    reservedFormalRootCreated = $false
    formalExecutionAuthorized = $false
} | ConvertTo-Json -Depth 12
exit 0
