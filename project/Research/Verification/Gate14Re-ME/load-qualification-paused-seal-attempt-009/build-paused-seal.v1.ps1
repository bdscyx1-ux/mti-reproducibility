[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$projectRoot = 'H:\DDM_Final_Project'
$measuredRoot = 'H:\DDM_Final_Project\Research\PilotRuns\Gate14Re-ME\load-qualification\attempt-007'
$executionEvidenceRoot = 'H:\DDM_Final_Project\Research\Verification\Gate14Re-ME\load-qualification-execution-attempt-009'
$deliveryRoot = 'H:\DDM_Final_Project\Research\Exports\Gate14Re-ME\load-qualification\attempt-007'
$sealRoot = 'H:\DDM_Final_Project\Research\Verification\Gate14Re-ME\load-qualification-paused-seal-attempt-009'
$supervisorPid = 89976
$validatorPid = 125488
$stoppedAtUtc = '2026-10-19T09:45:39.9516217Z'

function Write-JsonUtf8 {
    param(
        [Parameter(Mandatory)] [string] $Path,
        [Parameter(Mandatory)] $Value,
        [int] $Depth = 12
    )
    $json = $Value | ConvertTo-Json -Depth $Depth
    [System.IO.File]::WriteAllText($Path, $json + [Environment]::NewLine, [System.Text.UTF8Encoding]::new($false))
}

function Get-RelativePathNormalized {
    param(
        [Parameter(Mandatory)] [string] $BasePath,
        [Parameter(Mandatory)] [string] $FullPath
    )
    return [System.IO.Path]::GetRelativePath($BasePath, $FullPath).Replace('\', '/')
}

function Write-FileInventory {
    param(
        [Parameter(Mandatory)] [string] $SourceRoot,
        [Parameter(Mandatory)] [string] $OutputPath,
        [Parameter(Mandatory)] [string] $RootLabel
    )

    if (-not (Test-Path -LiteralPath $SourceRoot -PathType Container)) {
        throw "Inventory source root does not exist: $SourceRoot"
    }

    $files = @(Get-ChildItem -LiteralPath $SourceRoot -File -Recurse -Force | Sort-Object FullName)
    $writer = [System.IO.StreamWriter]::new($OutputPath, $false, [System.Text.UTF8Encoding]::new($false))
    $totalBytes = [int64]0
    try {
        foreach ($file in $files) {
            $beforeLength = [int64]$file.Length
            $beforeWriteUtc = $file.LastWriteTimeUtc
            $sha256 = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
            $after = Get-Item -LiteralPath $file.FullName -Force
            if ([int64]$after.Length -ne $beforeLength -or $after.LastWriteTimeUtc -ne $beforeWriteUtc) {
                throw "File changed while sealing: $($file.FullName)"
            }
            $entry = [ordered]@{
                schema = 'gate14re-me-paused-seal-file-row-v1'
                root = $RootLabel
                relativePath = Get-RelativePathNormalized -BasePath $SourceRoot -FullPath $file.FullName
                bytes = $beforeLength
                sha256 = $sha256
                lastWriteTimeUtc = $beforeWriteUtc.ToString('o')
            }
            $writer.WriteLine(($entry | ConvertTo-Json -Compress))
            $totalBytes += $beforeLength
        }
    }
    finally {
        $writer.Dispose()
    }

    $postFiles = @(Get-ChildItem -LiteralPath $SourceRoot -File -Recurse -Force | Sort-Object FullName)
    if ($postFiles.Count -ne $files.Count) {
        throw "File cardinality changed while sealing root: $SourceRoot"
    }

    return [ordered]@{
        root = $RootLabel
        absolutePath = $SourceRoot
        fileCount = $files.Count
        byteCount = $totalBytes
        manifestFile = [System.IO.Path]::GetFileName($OutputPath)
        manifestSha256 = (Get-FileHash -LiteralPath $OutputPath -Algorithm SHA256).Hash.ToLowerInvariant()
    }
}

function Assert-NoActiveQualificationProcesses {
    $normalizedMeasured = $measuredRoot.Replace('\', '/')
    $matches = @(Get-CimInstance Win32_Process | Where-Object {
        $command = if ($null -eq $_.CommandLine) { '' } else { $_.CommandLine.Replace('\', '/') }
        $_.ProcessId -in @($supervisorPid, $validatorPid) -or
        ($_.Name -eq 'Unity.exe' -and $command.Contains('DDM.Research.Editor.Gate14ReMELoadQualificationRunnerV3.Run') -and $command.Contains($normalizedMeasured)) -or
        ($_.Name -eq 'python.exe' -and $command.Contains('gate14re_me_qualification_structural_v3_1.py') -and $command.Contains($normalizedMeasured))
    })
    if ($matches.Count -ne 0) {
        throw "Qualification process still active; seal refused. PIDs: $($matches.ProcessId -join ',')"
    }
}

if ((Resolve-Path -LiteralPath $sealRoot).Path -ne $sealRoot) {
    throw 'Seal root path resolution mismatch.'
}
Assert-NoActiveQualificationProcesses

$authorizationReceiptPath = Join-Path $sealRoot 'pause-authorization-receipt.v1.json'
$measuredManifestPath = Join-Path $sealRoot 'measured-file-manifest.v1.jsonl'
$evidenceManifestPath = Join-Path $sealRoot 'execution-evidence-file-manifest.v1.jsonl'
$summaryPath = Join-Path $sealRoot 'seal-summary.v1.json'
$artifactManifestPath = Join-Path $sealRoot 'seal-artifact-manifest.v1.json'
$terminalReceiptPath = Join-Path $sealRoot 'terminal-seal-receipt.v1.json'

foreach ($path in @($authorizationReceiptPath, $measuredManifestPath, $evidenceManifestPath, $summaryPath, $artifactManifestPath, $terminalReceiptPath)) {
    if (Test-Path -LiteralPath $path) {
        throw "Seal output already exists; refusing overwrite: $path"
    }
}

$authorizationReceipt = [ordered]@{
    schema = 'gate14re-me-qualification-pause-authorization-receipt-v1'
    status = 'USER_AUTHORIZED_STOP_AND_TEMPORARY_SEAL'
    userInstruction = '先停止验收工作 保留原始数据暂时封存 不要等全部PASS了 停止后向我汇报'
    instructionReceivedLocalDate = '2026-10-19'
    stoppedAtUtc = $stoppedAtUtc
    supervisorPidStopped = $supervisorPid
    validatorPidStopped = $validatorPid
    acquisitionWasComplete = $true
    qualificationPassClaimed = $false
    measuredRoot = $measuredRoot
    executionEvidenceRoot = $executionEvidenceRoot
    deliveryRoot = $deliveryRoot
    sealRoot = $sealRoot
    sameAttemptContinuationAuthorized = $false
    formalCollectionAuthorized = $false
    formalAnalysisAuthorized = $false
}
Write-JsonUtf8 -Path $authorizationReceiptPath -Value $authorizationReceipt

$measuredInventory = Write-FileInventory -SourceRoot $measuredRoot -OutputPath $measuredManifestPath -RootLabel 'measured'
$evidenceInventory = Write-FileInventory -SourceRoot $executionEvidenceRoot -OutputPath $evidenceManifestPath -RootLabel 'execution-evidence'

Assert-NoActiveQualificationProcesses

$processLedgerPath = Join-Path $measuredRoot '_control\process-ledger.raw.v2.jsonl'
$failureLedgerPath = Join-Path $measuredRoot '_control\failures-and-voids.raw.v1.jsonl'
$replacementLedgerPath = Join-Path $measuredRoot '_control\replacement-ledger.raw.v1.jsonl'
$acquisitionCompletePath = Join-Path $measuredRoot '_control\acquisition-complete.v2.json'

$ledgerRows = @(Get-Content -LiteralPath $processLedgerPath | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | ForEach-Object { $_ | ConvertFrom-Json })
if ($ledgerRows.Count -ne 1147) { throw "Unexpected process ledger cardinality: $($ledgerRows.Count)" }
for ($index = 0; $index -lt $ledgerRows.Count; $index++) {
    $row = $ledgerRows[$index]
    if ($row.schema -cne 'gate14re-me-process-ledger-row-v2' -or [int]$row.ordinal -ne $index -or $row.state -cne 'EXITED_ZERO_TRUSTED_IDENTITY' -or [int]$row.exitCode -ne 0) {
        throw "Process ledger validation failed at ordinal $index"
    }
}
$failureCount = @(Get-Content -LiteralPath $failureLedgerPath | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }).Count
$replacementCount = @(Get-Content -LiteralPath $replacementLedgerPath | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }).Count
$acquisitionComplete = Get-Content -LiteralPath $acquisitionCompletePath -Raw | ConvertFrom-Json

$qualificationCompleteFiles = @(Get-ChildItem -LiteralPath $measuredRoot -File -Recurse -Force | Where-Object { $_.Name -match 'qualification-complete|structural.*terminal|delivery.*terminal' })

$summary = [ordered]@{
    schema = 'gate14re-me-qualification-paused-seal-summary-v1'
    status = 'PAUSED_SEALED_NOT_QUALIFIED'
    createdAtUtc = [datetime]::UtcNow.ToString('o')
    stop = [ordered]@{
        stoppedAtUtc = $stoppedAtUtc
        supervisorPid = $supervisorPid
        validatorPid = $validatorPid
        remainingMatchingProcessCount = 0
    }
    acquisition = [ordered]@{
        receiptPresent = $true
        receiptStatus = $acquisitionComplete.status
        plannedProcesses = 1147
        trustedExitedZeroProcesses = $ledgerRows.Count
        failureLedgerRows = $failureCount
        replacementLedgerRows = $replacementCount
    }
    qualification = [ordered]@{
        terminalPass = $false
        terminalReceiptCount = $qualificationCompleteFiles.Count
        structuralValidationInterruptedByUser = $true
        deliveryBuildStarted = (Test-Path -LiteralPath $deliveryRoot)
        typedParquetRoundTripPass = $false
    }
    preservation = [ordered]@{
        mode = 'CRYPTOGRAPHIC_INVENTORY_WITHOUT_SOURCE_ROOT_MODIFICATION'
        measured = $measuredInventory
        executionEvidence = $evidenceInventory
        observationValuesParsedOrReportedBySeal = $false
        sourceFilesDeletedMovedOrModifiedBySeal = $false
    }
    gates = [ordered]@{
        sameAttemptRetryResumeTopUpMergeReplacementAuthorized = $false
        formalCollectionAuthorized = $false
        formalAnalysisAuthorized = $false
        rankingOrWinnerComputed = $false
    }
}
Write-JsonUtf8 -Path $summaryPath -Value $summary

$artifactFiles = @(
    'build-paused-seal.v1.ps1',
    'pause-authorization-receipt.v1.json',
    'measured-file-manifest.v1.jsonl',
    'execution-evidence-file-manifest.v1.jsonl',
    'seal-summary.v1.json'
)
$artifactEntries = foreach ($name in $artifactFiles) {
    $path = Join-Path $sealRoot $name
    $item = Get-Item -LiteralPath $path
    [ordered]@{
        relativePath = $name
        bytes = [int64]$item.Length
        sha256 = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
    }
}
$artifactManifest = [ordered]@{
    schema = 'gate14re-me-paused-seal-artifact-manifest-v1'
    createdAtUtc = [datetime]::UtcNow.ToString('o')
    artifacts = @($artifactEntries)
}
Write-JsonUtf8 -Path $artifactManifestPath -Value $artifactManifest

$terminalReceipt = [ordered]@{
    schema = 'gate14re-me-qualification-paused-seal-terminal-receipt-v1'
    status = 'PASS_PAUSED_SEAL_CREATED_QUALIFICATION_NOT_PASS'
    createdAtUtc = [datetime]::UtcNow.ToString('o')
    sealRoot = $sealRoot
    measuredRoot = $measuredRoot
    executionEvidenceRoot = $executionEvidenceRoot
    authorizationReceiptSha256 = (Get-FileHash -LiteralPath $authorizationReceiptPath -Algorithm SHA256).Hash.ToLowerInvariant()
    measuredFileManifestSha256 = (Get-FileHash -LiteralPath $measuredManifestPath -Algorithm SHA256).Hash.ToLowerInvariant()
    executionEvidenceFileManifestSha256 = (Get-FileHash -LiteralPath $evidenceManifestPath -Algorithm SHA256).Hash.ToLowerInvariant()
    sealSummarySha256 = (Get-FileHash -LiteralPath $summaryPath -Algorithm SHA256).Hash.ToLowerInvariant()
    sealArtifactManifestSha256 = (Get-FileHash -LiteralPath $artifactManifestPath -Algorithm SHA256).Hash.ToLowerInvariant()
    qualificationPass = $false
    noActiveQualificationProcesses = $true
    rawDataPreserved = $true
}
Write-JsonUtf8 -Path $terminalReceiptPath -Value $terminalReceipt

$result = [ordered]@{
    status = $terminalReceipt.status
    createdAtUtc = $terminalReceipt.createdAtUtc
    sealRoot = $sealRoot
    terminalReceipt = $terminalReceiptPath
    terminalReceiptSha256 = (Get-FileHash -LiteralPath $terminalReceiptPath -Algorithm SHA256).Hash.ToLowerInvariant()
    measuredFileCount = $measuredInventory.fileCount
    measuredByteCount = $measuredInventory.byteCount
    executionEvidenceFileCount = $evidenceInventory.fileCount
    executionEvidenceByteCount = $evidenceInventory.byteCount
    noActiveQualificationProcesses = $true
    qualificationPass = $false
}
$result | ConvertTo-Json -Depth 8 -Compress
