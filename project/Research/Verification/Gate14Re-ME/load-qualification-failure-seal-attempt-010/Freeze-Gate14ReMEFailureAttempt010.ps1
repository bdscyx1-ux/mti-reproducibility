[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ProjectRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Require-Condition {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw [System.InvalidOperationException]::new($Message) }
}

function Get-Sha256Lower {
    param([string]$Path)
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Write-JsonExclusive {
    param([string]$Path, [object]$Value)
    Require-Condition (-not (Test-Path -LiteralPath $Path)) "Refusing to overwrite evidence: $Path"
    [IO.File]::WriteAllText($Path, (($Value | ConvertTo-Json -Depth 100) + [Environment]::NewLine), [Text.UTF8Encoding]::new($false))
}

$root = [IO.Path]::GetFullPath($ProjectRoot).TrimEnd([IO.Path]::DirectorySeparatorChar)
$evidenceRelative = 'Research/Verification/Gate14Re-ME/load-qualification-execution-attempt-010'
$measuredRelative = 'Research/PilotRuns/Gate14Re-ME/load-qualification/attempt-008'
$sealRelative = 'Research/Verification/Gate14Re-ME/load-qualification-failure-seal-attempt-010'
$evidenceRoot = Join-Path $root $evidenceRelative
$measuredRoot = Join-Path $root $measuredRelative
$sealRoot = Join-Path $root $sealRelative
$manifestPath = Join-Path $sealRoot 'failure-freeze-manifest.v1.json'
$receiptPath = Join-Path $sealRoot 'terminal-failure-seal-receipt.v1.json'

Require-Condition (Test-Path -LiteralPath $evidenceRoot -PathType Container) 'Execution evidence root is missing.'
Require-Condition (Test-Path -LiteralPath $measuredRoot -PathType Container) 'Measured root is missing.'
Require-Condition (-not (Test-Path -LiteralPath $manifestPath)) 'Failure freeze manifest already exists.'
Require-Condition (-not (Test-Path -LiteralPath $receiptPath)) 'Failure seal receipt already exists.'
Require-Condition (Test-Path -LiteralPath (Join-Path $measuredRoot '_control/failure-receipt.v2.json') -PathType Leaf) 'Measured failure receipt is missing.'
Require-Condition (Test-Path -LiteralPath (Join-Path $evidenceRoot 'external-terminal-observation.v1.json') -PathType Leaf) 'External terminal observation is missing.'

$activeUnity = @(Get-CimInstance Win32_Process -Filter "Name = 'Unity.exe'" | Where-Object { $_.CommandLine -like '*attempt-008*' })
$activeSupervisor = @(Get-CimInstance Win32_Process | Where-Object {
    $_.Name -eq 'pwsh.exe' -and $null -ne $_.CommandLine -and
    ([string]$_.CommandLine).Contains('-File') -and
    ([string]$_.CommandLine).Contains('Run-Gate14ReMELoadQualification.v4_1.ps1') -and
    ([string]$_.CommandLine).Contains('attempt-008')
})
Require-Condition ($activeUnity.Count -eq 0 -and $activeSupervisor.Count -eq 0) 'Attempt still has an active Unity or supervisor process.'

$entries = [Collections.Generic.List[object]]::new()
foreach ($source in @(
    [ordered]@{ name = 'execution-evidence'; relativePath = $evidenceRelative; root = $evidenceRoot },
    [ordered]@{ name = 'measured'; relativePath = $measuredRelative; root = $measuredRoot }
)) {
    foreach ($file in @(Get-ChildItem -LiteralPath $source.root -File -Recurse | Sort-Object FullName)) {
        $relativeWithin = [IO.Path]::GetRelativePath([string]$source.root, $file.FullName).Replace('\', '/')
        $entries.Add([ordered]@{
            sourceRoot = [string]$source.name
            relativePath = ([string]$source.relativePath).TrimEnd('/') + '/' + $relativeWithin
            bytes = [int64]$file.Length
            sha256 = Get-Sha256Lower -Path $file.FullName
        })
    }
}

Write-JsonExclusive -Path $manifestPath -Value ([ordered]@{
    schema = 'gate14re-me-load-qualification-failure-freeze-manifest-v1'
    studyId = 'Gate14Re-ME'
    attemptId = 'load-qualification-execution-attempt-010'
    status = 'FROZEN_FAILED_ATTEMPT_COMPLETE_FILE_INVENTORY'
    executionEvidenceRootRelativePath = $evidenceRelative
    measuredRootRelativePath = $measuredRelative
    fileCount = $entries.Count
    files = $entries.ToArray()
    sourceRootsMutationPermitted = $false
    createdAtUtc = [DateTime]::UtcNow.ToString('o')
})

$failureReceiptPath = Join-Path $measuredRoot '_control/failure-receipt.v2.json'
$terminalObservationPath = Join-Path $evidenceRoot 'external-terminal-observation.v1.json'
$failure = Get-Content -LiteralPath $failureReceiptPath -Raw -Encoding UTF8 | ConvertFrom-Json -DateKind String
$terminal = Get-Content -LiteralPath $terminalObservationPath -Raw -Encoding UTF8 | ConvertFrom-Json -DateKind String
Require-Condition ($failure.status -eq 'FAILED_CLOSED_NO_RETRY_NO_REPLACEMENT' -and $failure.failedMode -eq 'oracle-batch') 'Failure receipt state is unexpected.'
Require-Condition ($terminal.status -eq 'SUPERVISOR_NATURAL_EXIT_NONZERO' -and [int]$terminal.exitCode -eq 1 -and $terminal.naturalExitObserved -and -not $terminal.signalOrForcedTerminationSent) 'External terminal state is unexpected.'

Write-JsonExclusive -Path $receiptPath -Value ([ordered]@{
    schema = 'gate14re-me-load-qualification-terminal-failure-seal-v1'
    studyId = 'Gate14Re-ME'
    attemptId = 'load-qualification-execution-attempt-010'
    status = 'PASS_FAILURE_EVIDENCE_FROZEN_NO_RETRY_NO_REUSE'
    exactFailure = [string]$failure.exactFailure
    failedMode = [string]$failure.failedMode
    completedTrustedLedgerRows = 1
    launchedUnityProcessCount = [int]$failure.unityProcessCount
    supervisorNaturalExitCode = [int]$terminal.exitCode
    failureReceiptRelativePath = $measuredRelative + '/_control/failure-receipt.v2.json'
    failureReceiptSha256 = Get-Sha256Lower -Path $failureReceiptPath
    externalTerminalObservationRelativePath = $evidenceRelative + '/external-terminal-observation.v1.json'
    externalTerminalObservationSha256 = Get-Sha256Lower -Path $terminalObservationPath
    failureFreezeManifestRelativePath = $sealRelative + '/failure-freeze-manifest.v1.json'
    failureFreezeManifestSha256 = Get-Sha256Lower -Path $manifestPath
    sourceRootsMutationPermitted = $false
    retryResumeTopUpMergeSkipReorderReplacementOrParallelPerformed = $false
    sealedAtUtc = [DateTime]::UtcNow.ToString('o')
})
