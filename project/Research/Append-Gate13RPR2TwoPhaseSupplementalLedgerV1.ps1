[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$ProjectPath,
    [Parameter(Mandatory = $true)][string]$AuthorizationSourcePath
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$ProjectPath = [IO.Path]::GetFullPath($ProjectPath)
$AuthorizationSourcePath = [IO.Path]::GetFullPath($AuthorizationSourcePath)
$expectedSourceSha256 = '4af69eb71362f89698d38760db335985a015af49f176dd7f81805cb6d2d4821a'
$passport = Join-Path $ProjectPath 'Research\Gate13R_PR2_Formal_Execution_Run_Passport.md'
$evidenceRoot = Join-Path $ProjectPath 'Research\Verification\Gate13R_PR2_Formal_Prelaunch\v1\Ledger'
$archivePath = Join-Path $ProjectPath 'Research\Gate13R_PR2_TwoPhaseCommit_Supplemental_Authorization.v1.txt'
$openEntryPath = Join-Path $evidenceRoot 'two-phase-supplemental-authorization-checkpoint-opened.v1.json'
$closeEntryPath = Join-Path $evidenceRoot 'two-phase-supplemental-authorization-checkpoint-closed.v1.json'
$fileEntryPath = Join-Path $evidenceRoot 'two-phase-supplemental-authorization-file-reference.v1.json'
$checkpointId = 'gate13r-pr2-two-phase-supplemental-authorization-v1'
$python = 'C:\Users\bdscy\AppData\Local\Python\pythoncore-3.14-64\python.exe'
$runLedger = 'C:\Users\bdscy\.codex\plugins\cache\ars-codex\ars-codex\3.23.0\skills\academic-research-suite\ars\scripts\run_ledger.py'
$utf8 = New-Object Text.UTF8Encoding($false, $true)

foreach ($required in @($passport, $AuthorizationSourcePath, $python, $runLedger)) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) {
        throw "Required file is absent: $required"
    }
}

$sourceSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $AuthorizationSourcePath).Hash.ToLowerInvariant()
if ($sourceSha256 -ne $expectedSourceSha256) {
    throw "Supplemental authorization hash mismatch: expected=$expectedSourceSha256 actual=$sourceSha256"
}

foreach ($createNewPath in @($archivePath, $openEntryPath, $closeEntryPath, $fileEntryPath)) {
    if (Test-Path -LiteralPath $createNewPath) {
        throw "Create-new evidence path already exists: $createNewPath"
    }
}

New-Item -ItemType Directory -Path $evidenceRoot -Force | Out-Null
$authorizationBytes = [IO.File]::ReadAllBytes($AuthorizationSourcePath)
$archiveTempPath = "$archivePath.tmp-$([Guid]::NewGuid().ToString('N'))"
try {
    [IO.File]::WriteAllBytes($archiveTempPath, $authorizationBytes)
    [IO.File]::Move($archiveTempPath, $archivePath)
} finally {
    if (Test-Path -LiteralPath $archiveTempPath) {
        Remove-Item -LiteralPath $archiveTempPath -Force
    }
}

$archivedSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $archivePath).Hash.ToLowerInvariant()
if ($archivedSha256 -ne $expectedSourceSha256) {
    throw "Archived authorization hash mismatch: expected=$expectedSourceSha256 actual=$archivedSha256"
}

$userWords = [IO.File]::ReadAllText($archivePath, [Text.Encoding]::UTF8)
$openEntry = [ordered]@{
    kind = 'checkpoint_opened'
    checkpoint_id = $checkpointId
    stage = 'gate13r-pr2-formal-prelaunch'
    checkpoint_type = 'MANDATORY'
    question = 'Authorize the frozen raw-data / analysis two-phase commit supplement and continuation through one Gate 13R-PR2 S48/H48 formal raw-acquisition attempt after every prelaunch hard gate passes?'
    options = @('AUTHORIZED', 'NOT-AUTHORIZED')
}
$closeEntry = [ordered]@{
    kind = 'checkpoint_closed'
    checkpoint_id = $checkpointId
    answer = 'AUTHORIZED'
    user_words = $userWords
}
$fileEntry = [ordered]@{
    kind = 'file_reference'
    path = 'Gate13R_PR2_TwoPhaseCommit_Supplemental_Authorization.v1.txt'
    sha256 = $archivedSha256
    role = 'exact user supplemental formal authorization'
}

[IO.File]::WriteAllText($openEntryPath, (($openEntry | ConvertTo-Json -Depth 8).Replace("`r`n", "`n").Replace("`r", "`n") + "`n"), $utf8)
[IO.File]::WriteAllText($closeEntryPath, (($closeEntry | ConvertTo-Json -Depth 8).Replace("`r`n", "`n").Replace("`r", "`n") + "`n"), $utf8)
[IO.File]::WriteAllText($fileEntryPath, (($fileEntry | ConvertTo-Json -Depth 8).Replace("`r`n", "`n").Replace("`r", "`n") + "`n"), $utf8)

foreach ($entryPath in @($openEntryPath, $closeEntryPath, $fileEntryPath)) {
    & $python $runLedger append --passport-path $passport --entry-file $entryPath
    if ($LASTEXITCODE -ne 0) {
        throw "run_ledger append failed for $entryPath with exit $LASTEXITCODE"
    }
}

Write-Output "GATE13R-PR2-TWO-PHASE-SUPPLEMENTAL-AUTHORIZATION-LEDGERED sha256=$archivedSha256"
