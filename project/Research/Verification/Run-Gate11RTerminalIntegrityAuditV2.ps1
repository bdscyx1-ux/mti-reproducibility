param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$ProjectPath,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$OutputPath
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0
$checks = New-Object 'Collections.Generic.List[object]'

function Add-Check([string]$Name, [bool]$Passed, [string]$Detail) {
    $checks.Add([pscustomobject][ordered]@{ name = $Name; passed = $Passed; detail = $Detail })
}

function Get-LowerSha256([string]$Path) {
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Get-StringSha256([string]$Value) {
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Value)))).Replace('-', '').ToLowerInvariant() }
    finally { $sha.Dispose() }
}

function Get-Full([string]$Root, [string]$Relative) {
    return [IO.Path]::GetFullPath((Join-Path $Root $Relative.Replace('/', '\')))
}

function Read-JsonUtf8([string]$Path) {
    return [IO.File]::ReadAllText($Path, [Text.Encoding]::UTF8) | ConvertFrom-Json
}

function Get-Tree([string]$Root, [string]$Relative) {
    $full = (Get-Full $Root $Relative).TrimEnd('\')
    if (-not (Test-Path -LiteralPath $full -PathType Container)) { return [pscustomobject]@{ path = $Relative; files = 0; bytes = 0L; hash = '' } }
    $files = @(Get-ChildItem -LiteralPath $full -Recurse -File -Force)
    $rows = New-Object 'Collections.Generic.List[string]'
    foreach ($file in $files) {
        $name = $file.FullName.Substring($full.Length).TrimStart('\').Replace('\', '/')
        $rows.Add("$name`t$($file.Length)`t$(Get-LowerSha256 $file.FullName)")
    }
    $rows.Sort([StringComparer]::Ordinal)
    $sum = ($files | Measure-Object Length -Sum).Sum
    if ($null -eq $sum) { $sum = 0L }
    return [pscustomobject][ordered]@{ path = $Relative; files = $files.Count; bytes = [long]$sum; hash = Get-StringSha256 ($rows -join "`n") }
}

$root = [IO.Path]::GetFullPath($ProjectPath).TrimEnd('\')
$output = [IO.Path]::GetFullPath($OutputPath)
if (-not $output.StartsWith($root + '\', [StringComparison]::OrdinalIgnoreCase)) { throw 'Output outside project.' }
if (Test-Path -LiteralPath $output) { throw 'Create-new terminal audit output exists.' }

$checkpointRelative = 'Research/Verification/Gate11R_5pct/v2/gate11r-checkpoint.json'
$checkpointPath = Get-Full $root $checkpointRelative
$checkpointHash = Get-LowerSha256 $checkpointPath
$checkpoint = Read-JsonUtf8 $checkpointPath
Add-Check 'terminal-checkpoint-hash-and-status' ($checkpointHash -ceq 'bb65e9324cfbf6faf3352659d67905ee2a1df8d54d2ad7561af2714208859393' -and $checkpoint.status -eq 'GATE11R-PASSED-WAITING-FOR-GATE12R-AUTHORIZATION') $checkpointHash
Add-Check 'terminal-checkpoint-boundary' (-not $checkpoint.gate12RAuthorized -and -not $checkpoint.gate12RStarted -and -not $checkpoint.gate13RAuthorized -and -not $checkpoint.gate13RStarted -and -not $checkpoint.pilotExecuted -and -not $checkpoint.formalCampaignExecuted -and -not $checkpoint.timingSamplesCollected) 'Gate12R=false;Gate13R=false;timing=false'

$finalPath = Get-Full $root 'Research/Verification/Gate11R_5pct/v2/Gate11R_FinalAudit.summary.v2.2.json'
$finalHash = Get-LowerSha256 $finalPath
$final = Read-JsonUtf8 $finalPath
Add-Check 'final-audit' ($finalHash -ceq '58d9a41c8d84da8438a61a13abfa255242a84dd8cdec425630651c4c89eed68a' -and $final.passed -and $final.assertionCount -eq 89 -and $final.passedCount -eq 89 -and $final.failedCount -eq 0) $finalHash

$evidencePath = Get-Full $root 'Research/Verification/Gate11R_5pct/v2/Gate11R_Evidence_Manifest.v2.json'
$evidenceHash = Get-LowerSha256 $evidencePath
$evidence = Read-JsonUtf8 $evidencePath
$artifactMismatches = New-Object 'Collections.Generic.List[string]'
foreach ($artifact in @($evidence.artifacts)) {
    $full = Get-Full $root ([string]$artifact.path)
    if (-not (Test-Path -LiteralPath $full -PathType Leaf)) { $artifactMismatches.Add('missing:' + [string]$artifact.path); continue }
    $item = Get-Item -LiteralPath $full
    $hash = Get-LowerSha256 $full
    if ($item.Length -ne [long]$artifact.rawBytes -or $hash -cne [string]$artifact.sha256) { $artifactMismatches.Add('mismatch:' + [string]$artifact.path) }
}
Add-Check 'evidence-manifest-and-artifacts' ($evidenceHash -ceq '25ade263b1101d368df4da41ba6476b53dda3639ead4afc9ad68184bf76a2d93' -and $evidence.artifactCount -eq 26 -and @($evidence.artifacts).Count -eq 26 -and $artifactMismatches.Count -eq 0) ("manifest=$evidenceHash;mismatches=$($artifactMismatches.Count)")

$rootExpected = @(
    [pscustomobject]@{ path = 'Research/FormalScenarios/Gate11R_5pct/v1'; files = 57; bytes = 125218919L; hash = '0f41d8db5c01e9a1f1c14c7ee295151150d2efd91f6fc597fdb0b71b4f7eabe5' },
    [pscustomobject]@{ path = 'Research/PlayableExperiments/Gate11R_5pct/v1'; files = 4; bytes = 427601L; hash = '4d269ff4ada239aa2e636169b590b65c23262d351f1d785087a0a9464fbc06f2' },
    [pscustomobject]@{ path = 'Assets/_Scenes/Research/Playable/Gate11R_5pct/v1'; files = 684; bytes = 952341L; hash = '0ab0a465ce560fa7296a537d5fc969d364a6737d586ad8976215da156da4fd53' }
)
$rootResults = New-Object 'Collections.Generic.List[object]'
foreach ($expected in $rootExpected) {
    $actual = Get-Tree $root $expected.path
    $rootResults.Add($actual)
    Add-Check ('production-root-' + $expected.path) ($actual.files -eq $expected.files -and $actual.bytes -eq $expected.bytes -and $actual.hash -ceq $expected.hash) ("$($actual.files)/$($actual.bytes)/$($actual.hash)")
}

$bundleManifestPath = Get-Full $root 'Research/FormalScenarios/Gate11R_5pct/v1/bundle-manifest.json'
$coveragePath = Get-Full $root 'Research/PlayableExperiments/Gate11R_5pct/v1/coverage-manifest.json'
$coverage = Read-JsonUtf8 $coveragePath
Add-Check 'bundle-and-coverage-identity' ((Get-LowerSha256 $bundleManifestPath) -ceq '5baaeec18344a9e99e55da38f3c4875b7e7e9f3bf0add9d5f2d2f1e821b5f7fc' -and $coverage.coverageGraphSha256 -ceq '7298c124ec6ba2036c639f7b4720bf3634f47afb3f62516d1c9c5e58ac902c0e' -and $coverage.visualizationOnly -and -not $coverage.timingEvidenceAllowed) ([string]$coverage.coverageGraphSha256)

$documentExpected = [ordered]@{
    'Research/Gate11R_Attempt2_Passed_Checkpoint.md' = '82fe31348a672ede3b17484d9c179621b054747c0b89421bda2dc80b389c44d7'
    'Research/Gate10R_Onward_ProcessReuse_5pct_Status_Addendum.v2.md' = '77e95756334984533cc63b89c55c947609f6c2bd02567443a42e7a7061bfe02e'
    'Research/Next_Session_Checkpoint.md' = 'a879293041feb323c734a360e24cb1cc68fdd3cfabe167bfe30f1989de46c534'
    'Research/Next_Session_Checkpoint.Gate10R_Attempt4_Passed.v1.md' = '79d46d86adebe5fb9783309f1e6f431a0ea1ce8146dcdd65fda0fa09176292e4'
    'Research/Overall_Project_Plan.md' = '8eab8b7428785eb3bf4224ce5e94b8ed79590d4d82e24dc46a5738859b6fbb9b'
    'Research/Gate10R_Onward_ProcessReuse_5pct_Experiment_Plan.md' = '0cababa30b17fd23cb713b3774622205971cde338f179356d5e7ac06acc04c67'
}
foreach ($entry in $documentExpected.GetEnumerator()) {
    $full = Get-Full $root ([string]$entry.Key)
    $hash = if (Test-Path -LiteralPath $full -PathType Leaf) { Get-LowerSha256 $full } else { '' }
    Add-Check ('document-' + [string]$entry.Key) ($hash -ceq [string]$entry.Value) $hash
}

$overallText = [IO.File]::ReadAllText((Get-Full $root 'Research/Overall_Project_Plan.md'), [Text.Encoding]::UTF8)
Add-Check 'overall-plan-current-state' ($overallText.Contains('版本：3.5') -and $overallText.Contains('GATE11R-PASSED-WAITING-FOR-GATE12R-AUTHORIZATION') -and $overallText.Contains('下一步须由用户单独授权 Gate 12R')) 'version=3.5;Gate11R terminal token;Gate12R authorization boundary'

$forbidden = @(
    'Research/Verification/Gate11R_5pct/v1',
    'Research/FormalScenarios/Gate11R_5pct/.staging-v1-attempt2',
    'Research/PlayableExperiments/Gate11R_5pct/.staging-v1-attempt2',
    'Assets/_Scenes/Research/Playable/Gate11R_5pct/.staging-v1-attempt2',
    'Assets/_Scenes/Research/Playable/Gate11R_5pct/_staging-v1-attempt2-retry2',
    'Research/PilotRuns/Gate12R_ProcessReuse_5pct/v1',
    'Research/FormalRuns/Gate13R_ProcessReuse_5pct/v1'
)
$presentForbidden = @($forbidden | Where-Object { Test-Path -LiteralPath (Get-Full $root $_) })
Add-Check 'staging-and-downstream-roots-absent' ($presentForbidden.Count -eq 0) ($presentForbidden -join ',')

$unityCount = @(Get-Process Unity -ErrorAction SilentlyContinue).Count
$crashCount = @(Get-Process UnityCrashHandler64 -ErrorAction SilentlyContinue).Count
$lock = Test-Path -LiteralPath (Join-Path $root 'Temp\UnityLockfile')
Add-Check 'runtime-clean' ($unityCount -eq 0 -and $crashCount -eq 0 -and -not $lock) ("Unity=$unityCount;Crash=$crashCount;lock=$lock")

$failed = @($checks | Where-Object { -not $_.passed })
$result = [pscustomobject][ordered]@{
    schemaVersion = 2
    auditId = 'gate11r-attempt2-terminal-integrity-audit-v2'
    savedAtUtc = [DateTime]::UtcNow.ToString('o')
    status = if ($failed.Count -eq 0) { 'GATE11R-PASSED-WAITING-FOR-GATE12R-AUTHORIZATION' } else { 'GATE11R-TERMINAL-INTEGRITY-FAILED' }
    assertionCount = $checks.Count
    passedCount = $checks.Count - $failed.Count
    failedCount = $failed.Count
    checks = $checks.ToArray()
    checkpointSha256 = $checkpointHash
    finalAuditSha256 = $finalHash
    evidenceManifestSha256 = $evidenceHash
    productionRoots = $rootResults.ToArray()
    gate12RAuthorized = $false
    gate12RStarted = $false
    gate13RAuthorized = $false
    gate13RStarted = $false
    passed = ($failed.Count -eq 0)
}

$directory = Split-Path -Parent $output
if (-not (Test-Path -LiteralPath $directory)) { New-Item -ItemType Directory -Force -Path $directory | Out-Null }
$temporary = $output + '.tmp-' + [Guid]::NewGuid().ToString('N')
$encoding = New-Object Text.UTF8Encoding($false)
try {
    [IO.File]::WriteAllText($temporary, ($result | ConvertTo-Json -Depth 8), $encoding)
    [IO.File]::Move($temporary, $output)
}
finally { if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary -Force } }

$result | ConvertTo-Json -Depth 4 -Compress
if ($failed.Count -ne 0) { exit 1 }
