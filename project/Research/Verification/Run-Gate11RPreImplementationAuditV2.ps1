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

function Write-AtomicUtf8([string]$Path, [string]$Text) {
    $parent = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent | Out-Null }
    $temp = $Path + '.tmp-' + [Guid]::NewGuid().ToString('N')
    [IO.File]::WriteAllText($temp, $Text, (New-Object Text.UTF8Encoding($false)))
    Move-Item -LiteralPath $temp -Destination $Path
}

function Write-AtomicJson([string]$Path, [object]$Value) {
    Write-AtomicUtf8 $Path (($Value | ConvertTo-Json -Depth 12) + [Environment]::NewLine)
}

$root = [IO.Path]::GetFullPath($ProjectPath).TrimEnd('\')
$research = Join-Path $root 'Research'
$outputRoot = Join-Path $research 'Verification\Gate11R_5pct_PreImplementation\v2'
$summaryPath = Join-Path $outputRoot 'Gate11R_PreImplementation_Audit.summary.v2.json'
$ps51IdentityPath = Join-Path $outputRoot 'canonical-tree-identity.powershell51.v2.json'
$ps7IdentityPath = Join-Path $outputRoot 'canonical-tree-identity.powershell7.v2.json'
$helperPath = Join-Path $research 'Verification\Get-Gate11RCanonicalTreeIdentityV2.ps1'
$baselinePath = Join-Path $research 'Gate11R_Attempt2_Canonical_Preservation_Baseline.v2.json'
$prewritePath = Join-Path $research 'Gate11R_PreWrite_Preservation_Audit.v1.json'
$authorizationPath = Join-Path $research 'Gate11R_Attempt2_Execution_Authorization.v2.json'
$specificationPath = Join-Path $research 'Gate11R_5pct_Scenario_Playable_Specification.v1.md'
$testDesignPath = Join-Path $research 'Gate11R_5pct_Scenario_Playable_Test_Design.v1.md'

$checks = New-Object Collections.Generic.List[object]
function Add-Check([string]$Id, [bool]$Passed, [string]$Detail) {
    $checks.Add([pscustomobject][ordered]@{ id = $Id; passed = $Passed; detail = $Detail })
}

Add-Check 'project-path-absolute' ([IO.Path]::IsPathRooted($root)) $root
Add-Check 'attempt2-authorization-hash' ((Get-LowerSha256 $authorizationPath) -eq '419a1ce40e1075a68d2b62bb9f3c413b2f39ee434ad3992aed67dccd316e1552') (Get-LowerSha256 $authorizationPath)
Add-Check 'canonical-baseline-hash' ((Get-LowerSha256 $baselinePath) -eq '344b834562a78c221530401c5dabe5b0a0ffd513580262d504e61492c4981d8d') (Get-LowerSha256 $baselinePath)
Add-Check 'canonical-helper-hash' ((Get-LowerSha256 $helperPath) -eq '498e7e757a3df8144e57c1c16cc75bf8e50991ee09fecf0bbda4aef4efa92ed3') (Get-LowerSha256 $helperPath)
Add-Check 'specification-hash-unchanged' ((Get-LowerSha256 $specificationPath) -eq '18b04a31e7099a7bad52791bd3699b649d31060d06e559ffa1cb6cc6d4810a5d') (Get-LowerSha256 $specificationPath)
Add-Check 'test-design-hash-unchanged' ((Get-LowerSha256 $testDesignPath) -eq '9acbc130a920863d421d00a2add4d7e556f8ca3bc65f92241856438ec32d317e') (Get-LowerSha256 $testDesignPath)

$attempt1Files = [ordered]@{
    'Gate11R_PreImplementation_Audit.summary.v1.json' = '282eaf0dc786e51946a12fb3a5a1c35cc177e6d8e90bb0ecdd011384f3b356fe'
    'Gate11R_PreImplementation_Failure_Receipt.v1.json' = 'b376984203d8f9af29603ba1d6a55d5347537e914b1893f8d6b7aa6256ecc86c'
    'Gate11R_PreImplementation_Failure.diagnostic.log' = '1bf5b1f9b9d4ab1c8a60b99c7e0512d25284c8222a9348fd11226fe92750db22'
    'Gate11R_PreImplementation_Partial_Manifest.v1.json' = '2aa7036a810a3321fa491787c0773362a1cb591573b6a721d362db449d606682'
    'gate11r-preimplementation-failure.checkpoint.v1.json' = 'ed4ecb461d2e7eb795c1a161193921c6f31f76a84d6f8c857735465b6fcb4274'
}
$attempt1Root = Join-Path $research 'Verification\Gate11R_5pct_PreImplementation\v1'
foreach ($name in $attempt1Files.Keys) {
    $path = Join-Path $attempt1Root $name
    $actual = if (Test-Path -LiteralPath $path -PathType Leaf) { Get-LowerSha256 $path } else { $null }
    Add-Check ('attempt1-preserved-' + $name) ($actual -eq [string]$attempt1Files[$name]) ([string]$actual)
}

$prewrite = Get-Content -LiteralPath $prewritePath -Raw | ConvertFrom-Json
foreach ($material in @($prewrite.protectedMaterial)) {
    $path = Join-Path $root ([string]$material.path).Replace('/', '\')
    $exists = Test-Path -LiteralPath $path -PathType Leaf
    $bytes = if ($exists) { (Get-Item -LiteralPath $path).Length } else { -1L }
    $hash = if ($exists) { Get-LowerSha256 $path } else { $null }
    Add-Check ('protected-material-' + ([string]$material.path).Replace('/', '-')) ($exists -and $bytes -eq [long]$material.rawBytes -and $hash -eq [string]$material.sha256) ("bytes={0};sha256={1}" -f $bytes, $hash)
}

$ps51Raw = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $helperPath -ProjectPath $root -BaselinePath $baselinePath
$ps51Exit = $LASTEXITCODE
$pwsh = (Get-Command pwsh.exe -ErrorAction Stop).Source
$ps7Raw = & $pwsh -NoProfile -File $helperPath -ProjectPath $root -BaselinePath $baselinePath
$ps7Exit = $LASTEXITCODE
if ($ps51Exit -eq 0) { Write-AtomicUtf8 $ps51IdentityPath (($ps51Raw -join [Environment]::NewLine) + [Environment]::NewLine) }
if ($ps7Exit -eq 0) { Write-AtomicUtf8 $ps7IdentityPath (($ps7Raw -join [Environment]::NewLine) + [Environment]::NewLine) }
Add-Check 'powershell51-canonical-tree-audit-exit' ($ps51Exit -eq 0) ("exit={0}" -f $ps51Exit)
Add-Check 'powershell7-canonical-tree-audit-exit' ($ps7Exit -eq 0) ("exit={0}" -f $ps7Exit)

if ($ps51Exit -eq 0 -and $ps7Exit -eq 0) {
    $ps51 = ($ps51Raw -join [Environment]::NewLine) | ConvertFrom-Json
    $ps7 = ($ps7Raw -join [Environment]::NewLine) | ConvertFrom-Json
    $ps51Trees = $ps51.trees | ConvertTo-Json -Depth 7 -Compress
    $ps7Trees = $ps7.trees | ConvertTo-Json -Depth 7 -Compress
    Add-Check 'powershell51-canonical-status' ([string]$ps51.status -eq 'PASSED') ([string]$ps51.status)
    Add-Check 'powershell7-canonical-status' ([string]$ps7.status -eq 'PASSED') ([string]$ps7.status)
    Add-Check 'cross-runtime-tree-arrays-exact' ($ps51Trees -ceq $ps7Trees) ("treeCount={0}" -f @($ps51.trees).Count)
    Add-Check 'cross-runtime-baseline-hash-exact' ([string]$ps51.baselineSha256 -eq [string]$ps7.baselineSha256) ([string]$ps51.baselineSha256)
}

$gate10Checkpoint = Join-Path $research 'Verification\Gate10R_ProcessReuse_5pct\v4\gate10r-checkpoint.json'
Add-Check 'gate10r-v4-checkpoint-hash' ((Get-LowerSha256 $gate10Checkpoint) -eq 'fab889a1ff9f2d7911a6018b9cd3316e4dbff6e1c8cd8523678488ef252cbf56') (Get-LowerSha256 $gate10Checkpoint)
$gate10 = Get-Content -LiteralPath $gate10Checkpoint -Raw | ConvertFrom-Json
Add-Check 'gate10r-v4-status' ([string]$gate10.status -eq 'GATE10R-PASSED-WAITING-FOR-USER-AUTHORIZATION') ([string]$gate10.status)

foreach ($relative in @(
    'Research\FormalScenarios\Gate11R_5pct\v1',
    'Research\PlayableExperiments\Gate11R_5pct\v1',
    'Assets\_Scenes\Research\Playable\Gate11R_5pct\v1',
    'Research\Verification\Gate11R_5pct\v1',
    'Research\Verification\Gate11R_5pct\v2',
    'Research\PilotRuns\Gate12R_ProcessReuse_5pct\v1',
    'Research\FormalRuns\Gate13R_ProcessReuse_5pct\v1')) {
    $path = Join-Path $root $relative
    Add-Check ('root-absent-' + $relative.Replace('\', '-')) (-not (Test-Path -LiteralPath $path)) $path
}

$specification = Get-Content -LiteralPath $specificationPath -Raw
foreach ($token in @(
    '53 unique canonical scenarios', '74 campaign conditions', '212 eligible algorithm cells',
    'h = ln(1.05) = 0.048790164169432', 'There is no hard cap',
    'research-visual-direction-glyph-v1', 'VISUALIZATION REPLAY', 'NOT A TIMING RUN',
    'GATE11R-PASSED-WAITING-FOR-GATE12R-AUTHORIZATION')) {
    Add-Check ('spec-token-' + $token.GetHashCode()) ($specification.Contains($token)) $token
}

$unityProcesses = @(Get-Process -Name Unity, UnityHub -ErrorAction SilentlyContinue)
Add-Check 'no-unity-process' ($unityProcesses.Count -eq 0) ("count={0}" -f $unityProcesses.Count)
Add-Check 'no-unity-lockfile' (-not (Test-Path -LiteralPath (Join-Path $root 'Temp\UnityLockfile'))) (Join-Path $root 'Temp\UnityLockfile')
Add-Check 'unity-editor-present' (Test-Path -LiteralPath 'H:\UnityEditor\2022.3.30f1c1\Editor\Unity.exe' -PathType Leaf) 'H:\UnityEditor\2022.3.30f1c1\Editor\Unity.exe'

$failed = @($checks | Where-Object { -not $_.passed })
$summary = [ordered]@{
    schemaVersion = 2
    auditId = 'gate11r-attempt2-preimplementation-audit-v2'
    createdAtUtc = [DateTime]::UtcNow.ToString('o')
    projectPath = $root
    status = if ($failed.Count -eq 0) { 'PASSED' } else { 'FAILED' }
    checkCount = $checks.Count
    passedCount = $checks.Count - $failed.Count
    failedCount = $failed.Count
    repair = 'StringComparer.Ordinal normalized-relative-path tree identity'
    previousAttemptPreserved = $true
    unityStarted = $false
    officialGate11RRootCreated = $false
    checks = $checks.ToArray()
}
Write-AtomicJson $summaryPath $summary
$summary | ConvertTo-Json -Depth 6
if ($failed.Count -ne 0) { exit 1 }
