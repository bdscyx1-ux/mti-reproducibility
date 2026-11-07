[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$ProjectPath
)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($ProjectPath) -or -not [IO.Path]::IsPathRooted($ProjectPath)) {
    throw 'Gate 10R attempt-4 terminal integrity audit retry requires an explicit absolute ProjectPath.'
}
$ProjectPath = [IO.Path]::GetFullPath($ProjectPath)
$researchPath = Join-Path $ProjectPath 'Research'
$verificationPath = Join-Path $researchPath 'Verification'
$v4Root = Join-Path $verificationPath 'Gate10R_ProcessReuse_5pct\v4'
$failedAuditPath = Join-Path $researchPath 'Gate10R_Attempt4_Terminal_Integrity_Audit.v1.json'
$outputPath = Join-Path $researchPath 'Gate10R_Attempt4_Terminal_Integrity_Audit.v2.json'
if (Test-Path -LiteralPath $outputPath) {
    throw "Terminal audit retry evidence already exists; refusing overwrite: $outputPath"
}

function Get-LowerSha256([string]$Path) {
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Get-StringSha256([string]$Value) {
    $bytes = [Text.Encoding]::UTF8.GetBytes($Value)
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-', '').ToLowerInvariant() }
    finally { $sha.Dispose() }
}

function Get-TreeIdentity([string]$Path) {
    $treeRoot = [IO.Path]::GetFullPath($Path)
    $files = @(Get-ChildItem -LiteralPath $treeRoot -Recurse -File -Force | Sort-Object FullName)
    $rows = New-Object System.Collections.Generic.List[string]
    foreach ($file in $files) {
        $relative = $file.FullName.Substring($treeRoot.Length).TrimStart('\').Replace('\', '/')
        $rows.Add(("{0}`t{1}`t{2}" -f $relative, $file.Length, (Get-LowerSha256 -Path $file.FullName)))
    }
    return [pscustomobject][ordered]@{
        fileCount = $files.Count
        rawBytes = [long](($files | Measure-Object Length -Sum).Sum)
        treeSha256 = Get-StringSha256 -Value ($rows -join "`n")
    }
}

function Write-AtomicJson([string]$Path, $Value) {
    $temporaryPath = $Path + '.tmp-' + [Guid]::NewGuid().ToString('N')
    [IO.File]::WriteAllText($temporaryPath, (($Value | ConvertTo-Json -Depth 80) + [Environment]::NewLine), (New-Object Text.UTF8Encoding($false)))
    [IO.File]::Move($temporaryPath, $Path)
}

$checks = New-Object System.Collections.Generic.List[object]
function Add-Check([string]$Name, [bool]$Passed, [string]$Detail) {
    $script:checks.Add([pscustomobject][ordered]@{name=$Name;passed=$Passed;detail=$Detail})
}

$failedAudit = Get-Content -LiteralPath $failedAuditPath -Raw | ConvertFrom-Json
$failedChecks = @($failedAudit.checks | Where-Object { -not $_.passed })
Add-Check 'v1-failure-evidence-preserved' ((Get-LowerSha256 -Path $failedAuditPath) -eq '0064302e24b68a796b7e470c0abfa64ef5ab25baef19949ee62f485bc8973506') (Get-LowerSha256 -Path $failedAuditPath)
Add-Check 'v1-single-audit-scope-failure' ([int]$failedAudit.assertionCount -eq 14 -and [int]$failedAudit.passedCount -eq 13 -and [int]$failedAudit.failedCount -eq 1 -and $failedChecks.Count -eq 1 -and [string]$failedChecks[0].name -eq 'frozen-baseline-24') ("failed={0}" -f (($failedChecks | ForEach-Object {$_.name}) -join ','))

$baselineRows = @(Import-Csv -LiteralPath (Join-Path $researchPath 'Baseline_SHA256.csv'))
$materialRows = @($baselineRows | Where-Object { $_.scope -in @('working_copy', 'external_archive') })
$archiveEntryRows = @($baselineRows | Where-Object { $_.scope -eq 'archive_entry' })
$baselineErrors = New-Object System.Collections.Generic.List[string]
foreach ($row in $materialRows) {
    $candidate = [IO.Path]::GetFullPath((Join-Path $ProjectPath ([string]$row.relative_path)))
    if (-not (Test-Path -LiteralPath $candidate -PathType Leaf)) {
        $baselineErrors.Add(('missing:' + [string]$row.relative_path))
        continue
    }
    $item = Get-Item -LiteralPath $candidate
    if ([long]$item.Length -ne [long]$row.bytes) { $baselineErrors.Add(('bytes:' + [string]$row.relative_path)) }
    if ((Get-LowerSha256 -Path $candidate) -ne [string]$row.sha256) { $baselineErrors.Add(('sha256:' + [string]$row.relative_path)) }
}
Add-Check 'corrected-frozen-baseline-material-scope' ($materialRows.Count -eq 24 -and $archiveEntryRows.Count -eq 2 -and $baselineErrors.Count -eq 0) ("material={0};archiveEntries={1};errors={2}" -f $materialRows.Count, $archiveEntryRows.Count, $baselineErrors.Count)

$v4Identity = Get-TreeIdentity -Path $v4Root
$v1Tree = $failedAudit.v4Tree
Add-Check 'v4-tree-unchanged-since-v1-audit' ($v4Identity.fileCount -eq [int]$v1Tree.fileCount -and $v4Identity.rawBytes -eq [long]$v1Tree.rawBytes -and $v4Identity.treeSha256 -eq [string]$v1Tree.treeSha256) ($v4Identity | ConvertTo-Json -Compress)

$finalAuditPath = Join-Path $v4Root 'Gate10R_FinalAudit.summary.v4.json'
$checkpointPath = Join-Path $v4Root 'gate10r-checkpoint.json'
$finalAudit = Get-Content -LiteralPath $finalAuditPath -Raw | ConvertFrom-Json
$checkpoint = Get-Content -LiteralPath $checkpointPath -Raw | ConvertFrom-Json
Add-Check 'gate10r-final-audit-still-passed' ($finalAudit.passed -eq $true -and [int]$finalAudit.passedCount -eq 55 -and [int]$finalAudit.failedCount -eq 0) ("{0}/55;sha256={1}" -f $finalAudit.passedCount, (Get-LowerSha256 -Path $finalAuditPath))
Add-Check 'gate10r-terminal-checkpoint-still-passed' ([string]$checkpoint.status -eq 'GATE10R-PASSED-WAITING-FOR-USER-AUTHORIZATION' -and $checkpoint.gate11RAuthorized -eq $false -and $checkpoint.gate12RAuthorized -eq $false -and $checkpoint.gate13RPreparationAuthorized -eq $false -and $checkpoint.gate13RFormalCampaignAuthorized -eq $false) ([string]$checkpoint.status)

$forbiddenRoots = @(
    'Research\FormalScenarios\Gate11R_5pct\v1',
    'Research\PlayableExperiments\Gate11R_5pct\v1',
    'Assets\_Scenes\Research\Playable\Gate11R_5pct\v1',
    'Research\PilotRuns\Gate12R_ProcessReuse_5pct\v1',
    'Research\FormalRuns\Gate13R_ProcessReuse_5pct\v1'
)
$existingForbiddenRoots = @($forbiddenRoots | Where-Object { Test-Path -LiteralPath (Join-Path $ProjectPath $_) })
Add-Check 'unauthorized-downstream-roots-absent' ($existingForbiddenRoots.Count -eq 0) ($existingForbiddenRoots -join ';')
Add-Check 'runtime-clean' (@(Get-Process -Name Unity -ErrorAction SilentlyContinue).Count -eq 0 -and -not (Test-Path -LiteralPath (Join-Path $ProjectPath 'Temp\UnityLockfile'))) 'Unity=0;UnityLockfile=absent'

$failed = @($checks | Where-Object { -not $_.passed })
$report = [ordered]@{
    schemaVersion = 1
    auditId = 'gate10r-attempt4-terminal-integrity-audit-v2'
    savedAtUtc = [DateTime]::UtcNow.ToString('o')
    status = $(if ($failed.Count -eq 0) { 'GATE10R-PASSED-WAITING-FOR-USER-AUTHORIZATION' } else { 'GATE10R-TERMINAL-INTEGRITY-AUDIT-FAILED' })
    retryReason = 'v1 incorrectly treated two archive_entry reference rows as project-root material files and required all 26 CSV rows to equal the documented 24 material baseline entries'
    supersedesAuditResult = 'Research/Gate10R_Attempt4_Terminal_Integrity_Audit.v1.json'
    preservesFailedAudit = $true
    assertionCount = $checks.Count
    passedCount = $checks.Count - $failed.Count
    failedCount = $failed.Count
    checks = $checks.ToArray()
    materialBaselineEntryCount = $materialRows.Count
    archiveReferenceEntryCount = $archiveEntryRows.Count
    v4Tree = $v4Identity
    gate11RAuthorized = $false
    gate12RAuthorized = $false
    gate13RAuthorized = $false
    formalCampaign = $false
}
Write-AtomicJson -Path $outputPath -Value $report
if ($failed.Count -ne 0) { throw ("Gate 10R attempt-4 terminal integrity audit retry failed: {0}" -f (($failed | ForEach-Object {$_.name}) -join ', ')) }
Write-Output ("Gate 10R attempt-4 terminal integrity audit retry passed: {0}/{1}." -f $report.passedCount, $report.assertionCount)
