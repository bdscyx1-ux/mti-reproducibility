param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$ProjectPath
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

function Get-LowerSha256([string]$Path) {
    return (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToLowerInvariant()
}

function Get-StringSha256([string]$Value) {
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [Text.Encoding]::UTF8.GetBytes($Value)
        return ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-', '').ToLowerInvariant()
    }
    finally { $sha.Dispose() }
}

function Get-TreeIdentity([string]$Path) {
    $root = [IO.Path]::GetFullPath($Path).TrimEnd('\')
    if (-not (Test-Path -LiteralPath $root -PathType Container)) {
        return [pscustomobject][ordered]@{ exists = $false; fileCount = 0; rawBytes = 0L; treeSha256 = $null }
    }
    $files = @(Get-ChildItem -LiteralPath $root -Recurse -File -Force | Sort-Object FullName)
    $rows = @($files | ForEach-Object {
        $relative = $_.FullName.Substring($root.Length).TrimStart('\').Replace('\', '/')
        "$relative`t$($_.Length)`t$(Get-LowerSha256 $_.FullName)"
    })
    $sum = ($files | Measure-Object Length -Sum).Sum
    if ($null -eq $sum) { $sum = 0L }
    return [pscustomobject][ordered]@{
        exists = $true
        fileCount = $files.Count
        rawBytes = [long]$sum
        treeSha256 = Get-StringSha256 ($rows -join "`n")
    }
}

function Write-AtomicUtf8Json([string]$Path, [object]$Value) {
    $parent = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent | Out-Null }
    $temp = $Path + '.tmp-' + [Guid]::NewGuid().ToString('N')
    $json = $Value | ConvertTo-Json -Depth 12
    [IO.File]::WriteAllText($temp, $json + [Environment]::NewLine, (New-Object Text.UTF8Encoding($false)))
    Move-Item -LiteralPath $temp -Destination $Path
}

$resolvedProject = [IO.Path]::GetFullPath($ProjectPath).TrimEnd('\')
if (-not (Test-Path -LiteralPath $resolvedProject -PathType Container)) { throw "ProjectPath is not a directory: $resolvedProject" }

$research = Join-Path $resolvedProject 'Research'
$baselinePath = Join-Path $research 'Gate11R_PreWrite_Preservation_Audit.v1.json'
$authorizationPath = Join-Path $research 'Gate11R_Execution_Authorization.v1.json'
$specificationPath = Join-Path $research 'Gate11R_5pct_Scenario_Playable_Specification.v1.md'
$testDesignPath = Join-Path $research 'Gate11R_5pct_Scenario_Playable_Test_Design.v1.md'
$outputRoot = Join-Path $research 'Verification\Gate11R_5pct_PreImplementation\v1'
$summaryPath = Join-Path $outputRoot 'Gate11R_PreImplementation_Audit.summary.v1.json'

foreach ($required in @($baselinePath, $authorizationPath, $specificationPath, $testDesignPath)) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) { throw "Required preimplementation file is missing: $required" }
}

$baseline = Get-Content -LiteralPath $baselinePath -Raw | ConvertFrom-Json
$authorization = Get-Content -LiteralPath $authorizationPath -Raw | ConvertFrom-Json
$specification = Get-Content -LiteralPath $specificationPath -Raw
$testDesign = Get-Content -LiteralPath $testDesignPath -Raw
$checks = New-Object Collections.Generic.List[object]

function Add-Check([string]$Id, [bool]$Passed, [string]$Detail) {
    $checks.Add([pscustomobject][ordered]@{ id = $Id; passed = $Passed; detail = $Detail })
}

Add-Check 'project-path-absolute' ([IO.Path]::IsPathRooted($resolvedProject)) $resolvedProject
Add-Check 'prewrite-audit-passed' ([string]$baseline.result -eq 'PASSED') ([string]$baseline.result)
Add-Check 'authorization-status' ([string]$authorization.status -eq 'AUTHORIZED') ([string]$authorization.status)
Add-Check 'active-design-id' ([string]$authorization.activeUpstreamDesignId -eq 'gate10r-one-fresh-unity-process-per-williams-block-5pct-v1') ([string]$authorization.activeUpstreamDesignId)
Add-Check 'failure-policy' ([string]$authorization.failurePolicy -eq 'FAIL-CLOSED-AT-FIRST-HARD-GATE-NO-AUTO-RETRY-NO-AUTO-RESUME') ([string]$authorization.failurePolicy)

$authorizationSource = Join-Path $resolvedProject ([string]$baseline.authorizationSource.path).Replace('/', '\')
Add-Check 'authorization-source-exists' (Test-Path -LiteralPath $authorizationSource -PathType Leaf) $authorizationSource
if (Test-Path -LiteralPath $authorizationSource -PathType Leaf) {
    Add-Check 'authorization-source-hash' ((Get-LowerSha256 $authorizationSource) -eq [string]$baseline.authorizationSource.sha256) (Get-LowerSha256 $authorizationSource)
}

$gate10Checkpoint = Join-Path $resolvedProject ([string]$baseline.activeUpstream.terminalCheckpointPath).Replace('/', '\')
$gate10FinalAudit = Join-Path $resolvedProject ([string]$baseline.activeUpstream.finalAuditPath).Replace('/', '\')
Add-Check 'gate10r-terminal-checkpoint-hash' ((Get-LowerSha256 $gate10Checkpoint) -eq [string]$baseline.activeUpstream.terminalCheckpointSha256) (Get-LowerSha256 $gate10Checkpoint)
Add-Check 'gate10r-final-audit-hash' ((Get-LowerSha256 $gate10FinalAudit) -eq [string]$baseline.activeUpstream.finalAuditSha256) (Get-LowerSha256 $gate10FinalAudit)
$gate10CheckpointObject = Get-Content -LiteralPath $gate10Checkpoint -Raw | ConvertFrom-Json
Add-Check 'gate10r-terminal-status' ([string]$gate10CheckpointObject.status -eq 'GATE10R-PASSED-WAITING-FOR-USER-AUTHORIZATION') ([string]$gate10CheckpointObject.status)

foreach ($tree in @($baseline.protectedTrees)) {
    $actual = Get-TreeIdentity (Join-Path $resolvedProject ([string]$tree.path).Replace('/', '\'))
    $passed = $actual.exists -and $actual.fileCount -eq [int]$tree.fileCount -and $actual.rawBytes -eq [long]$tree.rawBytes -and $actual.treeSha256 -eq [string]$tree.treeSha256
    Add-Check ('protected-tree-' + ([string]$tree.path).Replace('/', '-')) $passed ($actual | ConvertTo-Json -Compress)
}

foreach ($material in @($baseline.protectedMaterial)) {
    $path = Join-Path $resolvedProject ([string]$material.path).Replace('/', '\')
    $exists = Test-Path -LiteralPath $path -PathType Leaf
    $actualBytes = if ($exists) { (Get-Item -LiteralPath $path).Length } else { -1L }
    $actualSha = if ($exists) { Get-LowerSha256 $path } else { $null }
    $passed = $exists -and $actualBytes -eq [long]$material.rawBytes -and $actualSha -eq [string]$material.sha256
    Add-Check ('protected-material-' + ([string]$material.path).Replace('/', '-')) $passed ("bytes={0};sha256={1}" -f $actualBytes, $actualSha)
}

foreach ($root in @($baseline.newRootsInitiallyAbsent)) {
    $path = Join-Path $resolvedProject ([string]$root).Replace('/', '\')
    Add-Check ('root-absent-' + ([string]$root).Replace('/', '-')) (-not (Test-Path -LiteralPath $path)) $path
}

$specAssertions = [ordered]@{
    specificationId = 'gate11r-process-reuse-5pct-scenario-playable-spec-v1'
    scenarioMatrixId = 'gate11r-process-reuse-5pct-scenario-matrix-v1'
    generatorId = 'ddm-gate11r-formal-scenario-generator-v1'
    preregistrationId = 'ddm-gate11r-planning-preregistration-v1'
    playableBundleId = 'gate11r-playable-experiment-bundle-v1'
    scenarioCount = '53 unique canonical scenarios'
    campaignCount = '74 campaign conditions'
    cellCount = '212 eligible algorithm cells'
    precision = 'h = ln(1.05) = 0.048790164169432'
    noCap = 'There is no hard cap'
    watermarkPrefix = 'VISUALIZATION REPLAY'
    watermarkSuffix = 'NOT A TIMING RUN'
    glyph = 'research-visual-direction-glyph-v1'
    passedState = 'GATE11R-PASSED-WAITING-FOR-GATE12R-AUTHORIZATION'
}
foreach ($entry in $specAssertions.GetEnumerator()) {
    Add-Check ('spec-contract-' + $entry.Key) ($specification.Contains([string]$entry.Value)) ([string]$entry.Value)
}

foreach ($id in @('P1:', 'P2:', 'P3:', 'P4:', 'Secondary families S1')) {
    Add-Check ('preregistration-' + (Get-StringSha256 $id).Substring(0, 12)) ($specification.Contains($id)) $id
}

foreach ($anchor in @(
    'core-r01-s1-shared', 'core-r07-s2-shared', 'grid-scale-g256-shared',
    'agent-scale-a512-shared', 'dynamic-footprint-f225-shared', 'reachability-c8-strict-shared',
    'core-r01-s1-hetero', 'core-r07-s2-hetero', 'goal-count-g32-hetero')) {
    Add-Check ('pilot-anchor-' + $anchor) ($specification.Contains($anchor)) $anchor
}

foreach ($requiredText in @(
    'one official Gate 11R attempt',
    'fail closed',
    'no automatic retry or resume',
    '53 scenarios, 74 campaigns, 212 algorithm cells',
    'separate-process scenario and Playable verification',
    'Gate 12R and Gate 13R are never invoked')) {
    Add-Check ('test-design-' + (Get-StringSha256 $requiredText).Substring(0, 12)) ($testDesign.Contains($requiredText)) $requiredText
}

$unityProcesses = @(Get-Process -Name Unity, UnityHub -ErrorAction SilentlyContinue)
Add-Check 'no-unity-process' ($unityProcesses.Count -eq 0) ("count={0}" -f $unityProcesses.Count)
Add-Check 'no-unity-lockfile' (-not (Test-Path -LiteralPath (Join-Path $resolvedProject 'Temp\UnityLockfile'))) (Join-Path $resolvedProject 'Temp\UnityLockfile')

$unityPath = 'H:\UnityEditor\2022.3.30f1c1\Editor\Unity.exe'
Add-Check 'verified-unity-present' (Test-Path -LiteralPath $unityPath -PathType Leaf) $unityPath

$failed = @($checks | Where-Object { -not $_.passed })
$summary = [ordered]@{
    schemaVersion = 1
    auditId = 'gate11r-preimplementation-audit-v1'
    createdAtUtc = [DateTime]::UtcNow.ToString('o')
    projectPath = $resolvedProject
    status = if ($failed.Count -eq 0) { 'PASSED' } else { 'FAILED' }
    checkCount = $checks.Count
    passedCount = $checks.Count - $failed.Count
    failedCount = $failed.Count
    unityStarted = $false
    officialProductionRootCreated = $false
    bindings = @(
        [ordered]@{ relativePath = 'Research/Gate11R_PreWrite_Preservation_Audit.v1.json'; bytes = (Get-Item $baselinePath).Length; sha256 = Get-LowerSha256 $baselinePath },
        [ordered]@{ relativePath = 'Research/Gate11R_Execution_Authorization.v1.json'; bytes = (Get-Item $authorizationPath).Length; sha256 = Get-LowerSha256 $authorizationPath },
        [ordered]@{ relativePath = 'Research/Gate11R_5pct_Scenario_Playable_Specification.v1.md'; bytes = (Get-Item $specificationPath).Length; sha256 = Get-LowerSha256 $specificationPath },
        [ordered]@{ relativePath = 'Research/Gate11R_5pct_Scenario_Playable_Test_Design.v1.md'; bytes = (Get-Item $testDesignPath).Length; sha256 = Get-LowerSha256 $testDesignPath }
    )
    checks = $checks.ToArray()
}

Write-AtomicUtf8Json $summaryPath $summary
Write-Output ($summary | ConvertTo-Json -Depth 5)
if ($failed.Count -ne 0) { exit 1 }
