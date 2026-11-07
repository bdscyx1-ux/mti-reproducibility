[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$projectRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
$archiveBase = (Resolve-Path -LiteralPath (Join-Path $projectRoot 'Research\PilotRuns\Gate12')).Path
$sourcePath = (Resolve-Path -LiteralPath (Join-Path $archiveBase 'v1')).Path
$destinationPath = [System.IO.Path]::GetFullPath((Join-Path $archiveBase 'v1-failed-pre-sample-attempt1'))
$receiptPath = [System.IO.Path]::GetFullPath((Join-Path $archiveBase 'Gate12_Attempt1_MoveReceipt.json'))
$expectedEnvironmentHash = 'a643e1791fb157bc4a96fbc871242cdd7772d188eb076cf402f823aa37b7ffe3'
$expectedEnvironmentBytes = 20841

function Assert-ImmediateChildPath {
    param(
        [Parameter(Mandatory = $true)][string]$Candidate,
        [Parameter(Mandatory = $true)][string]$Parent,
        [Parameter(Mandatory = $true)][string]$Label
    )
    $candidateParent = [System.IO.Directory]::GetParent($Candidate)
    if ($null -eq $candidateParent -or -not [string]::Equals($candidateParent.FullName, $Parent, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "$Label is not an immediate child of the Gate 12 archive base: $Candidate"
    }
}

Assert-ImmediateChildPath -Candidate $sourcePath -Parent $archiveBase -Label 'Source'
Assert-ImmediateChildPath -Candidate $destinationPath -Parent $archiveBase -Label 'Destination'

if (Test-Path -LiteralPath $destinationPath) { throw "Archive destination already exists: $destinationPath" }
if (Test-Path -LiteralPath $receiptPath) { throw "Move receipt already exists: $receiptPath" }

$sourceFiles = @(Get-ChildItem -LiteralPath $sourcePath -File -Recurse)
$sourceDirectories = @(Get-ChildItem -LiteralPath $sourcePath -Directory -Recurse)
if ($sourceFiles.Count -ne 1 -or $sourceDirectories.Count -ne 0) {
    throw "Expected exactly one file and no subdirectories in the failed attempt; found $($sourceFiles.Count) files and $($sourceDirectories.Count) subdirectories."
}

$environmentPath = Join-Path $sourcePath 'environment-start.json'
if (-not (Test-Path -LiteralPath $environmentPath -PathType Leaf)) { throw 'The sole failed-attempt file is not environment-start.json.' }
$environmentItem = Get-Item -LiteralPath $environmentPath
$environmentHashBefore = (Get-FileHash -Algorithm SHA256 -LiteralPath $environmentPath).Hash.ToLowerInvariant()
if ($environmentItem.Length -ne $expectedEnvironmentBytes) { throw "Unexpected environment-start.json byte count: $($environmentItem.Length)" }
if ($environmentHashBefore -ne $expectedEnvironmentHash) { throw "Unexpected environment-start.json SHA-256: $environmentHashBefore" }

$environmentJson = [System.IO.File]::ReadAllText($environmentPath, [System.Text.Encoding]::UTF8)
$environment = $environmentJson | ConvertFrom-Json
if ($environment.phase -ne 'start-preflight' -or $environment.preflightVerdict.passed -ne $true) {
    throw 'The failed attempt does not contain the expected successful start-preflight snapshot.'
}

$unexpectedSampleArtifacts = @(Get-ChildItem -LiteralPath $sourcePath -Recurse | Where-Object {
    $_.Name -match '(?i)(warmup|campaign|sample|checkpoint|manifest|result)'
})
if ($unexpectedSampleArtifacts.Count -ne 0) { throw 'Sample or campaign artifacts unexpectedly exist in the failed attempt.' }

$unityProcesses = @(Get-Process -Name Unity -ErrorAction SilentlyContinue)
$unityLockPath = Join-Path $projectRoot 'Temp\UnityLockfile'
if ($unityProcesses.Count -ne 0) { throw "Unity is running ($($unityProcesses.Count) process(es)); refusing to move the attempt directory." }
if (Test-Path -LiteralPath $unityLockPath) { throw "Unity lockfile exists; refusing to move the attempt directory: $unityLockPath" }

$gate13Candidates = @(
    (Join-Path $projectRoot 'Research\FormalRuns\Gate13'),
    (Join-Path $projectRoot 'Research\CampaignRuns\Gate13'),
    (Join-Path $projectRoot 'Research\PilotRuns\Gate13')
)
$gate13Exists = @($gate13Candidates | Where-Object { Test-Path -LiteralPath $_ }).Count -gt 0
if ($gate13Exists) { throw 'A Gate 13 output root exists; the retry precondition requires Gate 13 to remain unstarted.' }

Move-Item -LiteralPath $sourcePath -Destination $destinationPath

if (Test-Path -LiteralPath $sourcePath) { throw 'Source still exists after the archive move.' }
$archivedEnvironmentPath = Join-Path $destinationPath 'environment-start.json'
if (-not (Test-Path -LiteralPath $archivedEnvironmentPath -PathType Leaf)) { throw 'Archived environment snapshot is missing after the move.' }
$environmentHashAfter = (Get-FileHash -Algorithm SHA256 -LiteralPath $archivedEnvironmentPath).Hash.ToLowerInvariant()
$environmentBytesAfter = (Get-Item -LiteralPath $archivedEnvironmentPath).Length
if ($environmentHashAfter -ne $environmentHashBefore -or $environmentBytesAfter -ne $environmentItem.Length) {
    throw 'Archived environment snapshot identity changed during the move.'
}

$authorizationText = (-join @(
    [char]0x6388,
    [char]0x6743,
    [char]0x91cd,
    [char]0x8bd5,
    [char]0x20,
    [char]0x47,
    [char]0x61,
    [char]0x74,
    [char]0x65,
    [char]0x20,
    [char]0x31,
    [char]0x32
))

$receipt = [ordered]@{
    schemaVersion = 1
    receiptId = 'gate12-attempt1-pre-sample-archive-v1'
    movedAt = (Get-Date).ToString('o')
    authorization = [ordered]@{
        source = 'direct-user-message'
        text = $authorizationText
        interpretation = 'Archive the first zero-sample failed attempt intact and perform one Gate 12 retry under the already frozen plan.'
    }
    sourcePath = $sourcePath
    destinationPath = $destinationPath
    operation = 'Move-Item -LiteralPath within Research/PilotRuns/Gate12'
    failedAttemptClassification = 'pre-sample-implementation-failure'
    unityProcessCountAtMove = $unityProcesses.Count
    unityLockfilePresentAtMove = $false
    gate13StartedAtMove = $false
    fileCount = 1
    subdirectoryCount = 0
    completedWarmupProcessCount = 0
    completedMeasuredProcessCount = 0
    environmentSnapshot = [ordered]@{
        relativePath = 'environment-start.json'
        bytesBefore = [int64]$environmentItem.Length
        bytesAfter = [int64]$environmentBytesAfter
        sha256Before = $environmentHashBefore
        sha256After = $environmentHashAfter
        capturedAt = [string]$environment.capturedAt
        preflightPassed = [bool]$environment.preflightVerdict.passed
    }
    preservedIntact = ($environmentHashBefore -eq $environmentHashAfter -and $environmentItem.Length -eq $environmentBytesAfter)
}

$receiptJson = $receipt | ConvertTo-Json -Depth 8
[System.IO.File]::WriteAllText($receiptPath, $receiptJson + [Environment]::NewLine, (New-Object System.Text.UTF8Encoding($false)))

$receipt
