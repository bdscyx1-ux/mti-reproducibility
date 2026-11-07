[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$ProjectPath
)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($ProjectPath) -or -not [IO.Path]::IsPathRooted($ProjectPath)) {
    throw 'Gate 10R attempt-4 terminal integrity audit requires an explicit absolute ProjectPath.'
}
$ProjectPath = [IO.Path]::GetFullPath($ProjectPath)
$researchPath = Join-Path $ProjectPath 'Research'
$verificationPath = Join-Path $researchPath 'Verification'
$v4Root = Join-Path $verificationPath 'Gate10R_ProcessReuse_5pct\v4'
$outputPath = Join-Path $researchPath 'Gate10R_Attempt4_Terminal_Integrity_Audit.v1.json'
if (Test-Path -LiteralPath $outputPath) {
    throw "Terminal audit evidence already exists; refusing overwrite: $outputPath"
}

function Get-LowerSha256([string]$Path) {
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Get-StringSha256([string]$Value) {
    $bytes = [Text.Encoding]::UTF8.GetBytes($Value)
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        return ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-', '').ToLowerInvariant()
    }
    finally {
        $sha.Dispose()
    }
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
    $parent = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }
    $temporaryPath = $Path + '.tmp-' + [Guid]::NewGuid().ToString('N')
    $json = $Value | ConvertTo-Json -Depth 80
    [IO.File]::WriteAllText($temporaryPath, $json + [Environment]::NewLine, (New-Object Text.UTF8Encoding($false)))
    [IO.File]::Move($temporaryPath, $Path)
}

$checks = New-Object System.Collections.Generic.List[object]
function Add-Check([string]$Name, [bool]$Passed, [string]$Detail) {
    $script:checks.Add([pscustomobject][ordered]@{
        name = $Name
        passed = $Passed
        detail = $Detail
    })
}

$finalAuditPath = Join-Path $v4Root 'Gate10R_FinalAudit.summary.v4.json'
$checkpointPath = Join-Path $v4Root 'gate10r-checkpoint.json'
$manifestPath = Join-Path $v4Root 'Gate10R_Evidence_Manifest.v4.json'
$finalAudit = Get-Content -LiteralPath $finalAuditPath -Raw | ConvertFrom-Json
$checkpoint = Get-Content -LiteralPath $checkpointPath -Raw | ConvertFrom-Json
$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json

Add-Check 'gate10r-final-audit' ($finalAudit.passed -eq $true -and [int]$finalAudit.assertionCount -eq 55 -and [int]$finalAudit.passedCount -eq 55 -and [int]$finalAudit.failedCount -eq 0) ("{0}/{1}" -f $finalAudit.passedCount, $finalAudit.assertionCount)
Add-Check 'gate10r-terminal-checkpoint' ([string]$checkpoint.status -eq 'GATE10R-PASSED-WAITING-FOR-USER-AUTHORIZATION' -and $checkpoint.stopOnFirstPass -eq $true) ([string]$checkpoint.status)
Add-Check 'downstream-authorization-boundary' ($checkpoint.gate11RAuthorized -eq $false -and $checkpoint.gate12RAuthorized -eq $false -and $checkpoint.gate13RPreparationAuthorized -eq $false -and $checkpoint.gate13RFormalCampaignAuthorized -eq $false) 'Gate 11R, Gate 12R, and Gate 13R remain unauthorized'
Add-Check 'final-audit-to-manifest-binding' ([string]$finalAudit.evidenceManifestSha256 -eq (Get-LowerSha256 -Path $manifestPath)) ([string]$finalAudit.evidenceManifestSha256)

$manifestErrors = New-Object System.Collections.Generic.List[string]
foreach ($artifact in @($manifest.artifacts)) {
    $artifactPath = Join-Path $ProjectPath ([string]$artifact.relativePath).Replace('/', '\')
    if (-not (Test-Path -LiteralPath $artifactPath -PathType Leaf)) {
        $manifestErrors.Add(('missing:' + [string]$artifact.relativePath))
        continue
    }
    $item = Get-Item -LiteralPath $artifactPath
    if ([long]$item.Length -ne [long]$artifact.bytes) {
        $manifestErrors.Add(('bytes:' + [string]$artifact.relativePath))
    }
    if ((Get-LowerSha256 -Path $artifactPath) -ne [string]$artifact.sha256) {
        $manifestErrors.Add(('sha256:' + [string]$artifact.relativePath))
    }
}
Add-Check 'v4-evidence-manifest-revalidation' ($manifestErrors.Count -eq 0 -and @($manifest.artifacts).Count -eq [int]$manifest.artifactCount) ("artifacts={0};errors={1}" -f @($manifest.artifacts).Count, $manifestErrors.Count)

$attempt1 = Get-TreeIdentity -Path (Join-Path $verificationPath 'Gate10R_ProcessReuse_5pct\v1')
$attempt2 = Get-TreeIdentity -Path (Join-Path $verificationPath 'Gate10R_ProcessReuse_5pct\v2')
$attempt3 = Get-TreeIdentity -Path (Join-Path $verificationPath 'Gate10R_ProcessReuse_5pct\v3')
Add-Check 'attempt1-tree-byte-identical' ($attempt1.fileCount -eq 4 -and $attempt1.rawBytes -eq 9577 -and $attempt1.treeSha256 -eq '2baa66eb6ee95ecf0f68667b2790fba2a30ce8a24f54e8f9fe477cdc716b9e3d') ($attempt1 | ConvertTo-Json -Compress)
Add-Check 'attempt2-tree-byte-identical' ($attempt2.fileCount -eq 101 -and $attempt2.rawBytes -eq 9375526 -and $attempt2.treeSha256 -eq 'da9e6312e74db1bc1207660cf90eef28321ecda0abf1297be6c9298e6270dbce') ($attempt2 | ConvertTo-Json -Compress)
Add-Check 'attempt3-tree-byte-identical' ($attempt3.fileCount -eq 165 -and $attempt3.rawBytes -eq 14661809 -and $attempt3.treeSha256 -eq '29f5aa8f0461abb120792dea0f2806e46e4dc9836aa843ce747f2436c1645a23') ($attempt3 | ConvertTo-Json -Compress)

$frozenScriptPath = Join-Path $verificationPath 'Run-Gate12AnalysisUnitTests.ps1'
$frozenSummaryPath = Join-Path $verificationPath 'Gate12_AnalysisUnitTests.summary.json'
Add-Check 'frozen-retained-source-byte-identical' ((Get-LowerSha256 -Path $frozenScriptPath) -eq 'e56a3881c0fc9fc3ecceb760d1c51129e80ec2b306acdcfefed0a3814a6885b1' -and (Get-Item -LiteralPath $frozenScriptPath).Length -eq 13713) '13713 bytes / e56a3881...6885b1'
Add-Check 'frozen-retained-summary-byte-identical' ((Get-LowerSha256 -Path $frozenSummaryPath) -eq '1536ae459c3d8cbb90b8a9dad1f74e7937d5ceb205e6cc088745c798d136e54d' -and (Get-Item -LiteralPath $frozenSummaryPath).Length -eq 1748) '1748 bytes / 1536ae45...136e54d'

$baselineRows = @(Import-Csv -LiteralPath (Join-Path $researchPath 'Baseline_SHA256.csv'))
$baselineErrors = New-Object System.Collections.Generic.List[string]
foreach ($row in $baselineRows) {
    $candidate = [IO.Path]::GetFullPath((Join-Path $ProjectPath ([string]$row.relative_path)))
    if (-not (Test-Path -LiteralPath $candidate -PathType Leaf)) {
        $baselineErrors.Add(('missing:' + [string]$row.relative_path))
        continue
    }
    $item = Get-Item -LiteralPath $candidate
    if ([long]$item.Length -ne [long]$row.bytes) {
        $baselineErrors.Add(('bytes:' + [string]$row.relative_path))
    }
    if ((Get-LowerSha256 -Path $candidate) -ne [string]$row.sha256) {
        $baselineErrors.Add(('sha256:' + [string]$row.relative_path))
    }
}
Add-Check 'frozen-baseline-24' ($baselineRows.Count -eq 24 -and $baselineErrors.Count -eq 0) ("entries={0};errors={1}" -f $baselineRows.Count, $baselineErrors.Count)

$forbiddenRoots = @(
    'Research\FormalScenarios\Gate11R_5pct\v1',
    'Research\PlayableExperiments\Gate11R_5pct\v1',
    'Assets\_Scenes\Research\Playable\Gate11R_5pct\v1',
    'Research\PilotRuns\Gate12R_ProcessReuse_5pct\v1',
    'Research\FormalRuns\Gate13R_ProcessReuse_5pct\v1'
)
$existingForbiddenRoots = @($forbiddenRoots | Where-Object { Test-Path -LiteralPath (Join-Path $ProjectPath $_) })
Add-Check 'unauthorized-downstream-roots-absent' ($existingForbiddenRoots.Count -eq 0) ($existingForbiddenRoots -join ';')
Add-Check 'no-unity-process' (@(Get-Process -Name Unity -ErrorAction SilentlyContinue).Count -eq 0) 'zero'
Add-Check 'no-project-lock' (-not (Test-Path -LiteralPath (Join-Path $ProjectPath 'Temp\UnityLockfile'))) 'absent'

$v4Identity = Get-TreeIdentity -Path $v4Root
$failed = @($checks | Where-Object { -not $_.passed })
$report = [ordered]@{
    schemaVersion = 1
    auditId = 'gate10r-attempt4-terminal-integrity-audit-v1'
    savedAtUtc = [DateTime]::UtcNow.ToString('o')
    status = $(if ($failed.Count -eq 0) { 'GATE10R-PASSED-WAITING-FOR-USER-AUTHORIZATION' } else { 'GATE10R-TERMINAL-INTEGRITY-AUDIT-FAILED' })
    assertionCount = $checks.Count
    passedCount = $checks.Count - $failed.Count
    failedCount = $failed.Count
    checks = $checks.ToArray()
    v4Tree = $v4Identity
    finalAudit = [ordered]@{
        relativePath = 'Research/Verification/Gate10R_ProcessReuse_5pct/v4/Gate10R_FinalAudit.summary.v4.json'
        sha256 = Get-LowerSha256 -Path $finalAuditPath
    }
    terminalCheckpoint = [ordered]@{
        relativePath = 'Research/Verification/Gate10R_ProcessReuse_5pct/v4/gate10r-checkpoint.json'
        sha256 = Get-LowerSha256 -Path $checkpointPath
    }
    gate11RAuthorized = $false
    gate12RAuthorized = $false
    gate13RAuthorized = $false
    formalCampaign = $false
}
Write-AtomicJson -Path $outputPath -Value $report
if ($failed.Count -ne 0) {
    throw ("Gate 10R attempt-4 terminal integrity audit failed: {0}" -f (($failed | ForEach-Object { $_.name }) -join ', '))
}
Write-Output ("Gate 10R attempt-4 terminal integrity audit passed: {0}/{1}." -f $report.passedCount, $report.assertionCount)
