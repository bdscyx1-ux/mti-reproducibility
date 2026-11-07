[CmdletBinding()]
param(
    [string]$ProjectPath,
    [string]$OutputRoot,
    [string]$PythonPath = 'C:\Users\bdscy\AppData\Local\Python\pythoncore-3.14-64\python.exe'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

if ([string]::IsNullOrWhiteSpace($ProjectPath)) {
    $ProjectPath = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
}
else {
    $ProjectPath = [IO.Path]::GetFullPath($ProjectPath)
}
if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    $OutputRoot = Join-Path $ProjectPath 'Research\Verification\Gate13R_PR2_NonExecuting_Preparation\v2'
}
else {
    $OutputRoot = [IO.Path]::GetFullPath($OutputRoot)
}

$researchRoot = Join-Path $ProjectPath 'Research'
$formalRoot = Join-Path $ProjectPath 'Research\FormalRuns\Gate13R_RQAligned_S48H48\v1'
$prewritePath = Join-Path $researchRoot 'Gate13R_PR2_PreWrite_Preservation_Audit.v1.json'
$coreValidator = Join-Path $researchRoot 'Test-Gate13RPR2FormalPreparationV2.py'
$coreRoot = Join-Path $OutputRoot 'core'

function Get-LowerSha256([string]$Path) {
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Get-StringSha256([string]$Text) {
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        return ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Text)))).Replace('-', '').ToLowerInvariant()
    }
    finally {
        $sha.Dispose()
    }
}

function Get-TreeIdentity([string]$Path) {
    $root = [IO.Path]::GetFullPath($Path).TrimEnd('\')
    $files = @(Get-ChildItem -LiteralPath $root -Recurse -File -Force)
    $rows = New-Object 'System.Collections.Generic.List[string]'
    foreach ($file in $files) {
        $relative = $file.FullName.Substring($root.Length).TrimStart('\').Replace('\', '/')
        $rows.Add("$relative`t$($file.Length)`t$(Get-LowerSha256 $file.FullName)")
    }
    $rows.Sort([StringComparer]::Ordinal)
    return [pscustomobject][ordered]@{
        relativePath = $null
        resolvedAbsolutePath = $root.Replace('\', '/')
        fileCount = $files.Count
        rawBytes = [long](($files | Measure-Object Length -Sum).Sum)
        canonicalTreeSha256 = Get-StringSha256 ($rows.ToArray() -join "`n")
    }
}

function Write-AtomicJson([string]$Path, [object]$Value) {
    if (Test-Path -LiteralPath $Path) {
        throw "Refusing to overwrite validation evidence: $Path"
    }
    $parent = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }
    $temporary = Join-Path $parent ('.' + [IO.Path]::GetFileName($Path) + '.' + [Guid]::NewGuid().ToString('N') + '.tmp')
    try {
        $json = $Value | ConvertTo-Json -Depth 100
        [IO.File]::WriteAllText($temporary, $json + "`n", [Text.UTF8Encoding]::new($false))
        Move-Item -LiteralPath $temporary -Destination $Path
    }
    finally {
        if (Test-Path -LiteralPath $temporary) {
            Remove-Item -LiteralPath $temporary -Force
        }
    }
}

function Get-FrozenTreeAudit([object[]]$ExpectedTrees) {
    $results = @()
    foreach ($expected in $ExpectedTrees) {
        $actual = Get-TreeIdentity (Join-Path $ProjectPath ([string]$expected.relativePath).Replace('/', '\'))
        $actual.relativePath = [string]$expected.relativePath
        $passed = (
            $actual.fileCount -eq [int]$expected.fileCount -and
            $actual.rawBytes -eq [long]$expected.rawBytes -and
            $actual.canonicalTreeSha256 -eq [string]$expected.canonicalTreeSha256
        )
        $results += [pscustomobject][ordered]@{
            relativePath = [string]$expected.relativePath
            passed = $passed
            expected = [pscustomobject][ordered]@{
                fileCount = [int]$expected.fileCount
                rawBytes = [long]$expected.rawBytes
                canonicalTreeSha256 = [string]$expected.canonicalTreeSha256
            }
            actual = $actual
        }
    }
    return @($results)
}

if (-not (Test-Path -LiteralPath $PythonPath -PathType Leaf)) {
    throw "Python runtime not found: $PythonPath"
}
if (-not (Test-Path -LiteralPath $prewritePath -PathType Leaf)) {
    throw "Pre-write audit not found: $prewritePath"
}
if (-not (Test-Path -LiteralPath $coreValidator -PathType Leaf)) {
    throw "Core validator not found: $coreValidator"
}
if (Test-Path -LiteralPath $OutputRoot) {
    throw "Validation output root already exists: $OutputRoot"
}
if ($OutputRoot.StartsWith((Join-Path $ProjectPath 'Research\FormalRuns'), [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Validation root cannot be under Research/FormalRuns.'
}

$prewrite = Get-Content -Raw -LiteralPath $prewritePath | ConvertFrom-Json
$unityBefore = @(Get-Process -Name Unity -ErrorAction SilentlyContinue)
$formalReceiptsBefore = @(Get-ChildItem -LiteralPath $researchRoot -Filter 'Gate13R_PR2*Formal*Execution*Receipt*' -File -ErrorAction SilentlyContinue)
$preTrees = Get-FrozenTreeAudit @($prewrite.frozenTrees)
$preAudit = [pscustomobject][ordered]@{
    schemaVersion = 1
    auditId = 'gate13r-pr2-validation-pre-preservation-audit-v2'
    observedAtUtc = [DateTimeOffset]::UtcNow.ToString('o')
    projectPath = $ProjectPath.Replace('\', '/')
    formalRootAbsent = -not (Test-Path -LiteralPath $formalRoot)
    formalExecutionReceiptAbsent = $formalReceiptsBefore.Count -eq 0
    unityEditorProcessCount = $unityBefore.Count
    frozenTrees = $preTrees
    passed = (
        (@($preTrees | Where-Object { -not $_.passed }).Count -eq 0) -and
        (-not (Test-Path -LiteralPath $formalRoot)) -and
        ($formalReceiptsBefore.Count -eq 0) -and
        ($unityBefore.Count -eq 0)
    )
}

New-Item -ItemType Directory -Path $OutputRoot -Force | Out-Null
Write-AtomicJson (Join-Path $OutputRoot 'pre-validation-preservation-audit.json') $preAudit

$stdoutPath = Join-Path $OutputRoot 'core-validation.stdout.log'
$stderrPath = Join-Path $OutputRoot 'core-validation.stderr.log'
$coreExit = 99
if ($preAudit.passed) {
    & $PythonPath $coreValidator --output-root $coreRoot 1> $stdoutPath 2> $stderrPath
    $coreExit = $LASTEXITCODE
}
else {
    [IO.File]::WriteAllText($stdoutPath, '', [Text.UTF8Encoding]::new($false))
    [IO.File]::WriteAllText($stderrPath, 'Pre-validation preservation audit failed; core validation was not started.' + "`n", [Text.UTF8Encoding]::new($false))
}

$postTrees = Get-FrozenTreeAudit @($prewrite.frozenTrees)
$unityAfter = @(Get-Process -Name Unity -ErrorAction SilentlyContinue)
$formalReceiptsAfter = @(Get-ChildItem -LiteralPath $researchRoot -Filter 'Gate13R_PR2*Formal*Execution*Receipt*' -File -ErrorAction SilentlyContinue)
$postAudit = [pscustomobject][ordered]@{
    schemaVersion = 1
    auditId = 'gate13r-pr2-validation-post-preservation-audit-v2'
    observedAtUtc = [DateTimeOffset]::UtcNow.ToString('o')
    formalRootAbsent = -not (Test-Path -LiteralPath $formalRoot)
    formalExecutionReceiptAbsent = $formalReceiptsAfter.Count -eq 0
    unityEditorProcessCount = $unityAfter.Count
    frozenTrees = $postTrees
    prePostIdentical = @($preTrees | ForEach-Object {
        $before = $_
        $after = $postTrees | Where-Object { $_.relativePath -eq $before.relativePath } | Select-Object -First 1
        [pscustomobject][ordered]@{
            relativePath = $before.relativePath
            identical = (
                $before.actual.fileCount -eq $after.actual.fileCount -and
                $before.actual.rawBytes -eq $after.actual.rawBytes -and
                $before.actual.canonicalTreeSha256 -eq $after.actual.canonicalTreeSha256
            )
        }
    })
}
$postAudit | Add-Member -NotePropertyName passed -NotePropertyValue (
    (@($postTrees | Where-Object { -not $_.passed }).Count -eq 0) -and
    (@($postAudit.prePostIdentical | Where-Object { -not $_.identical }).Count -eq 0) -and
    $postAudit.formalRootAbsent -and
    $postAudit.formalExecutionReceiptAbsent -and
    ($postAudit.unityEditorProcessCount -eq 0)
)
Write-AtomicJson (Join-Path $OutputRoot 'post-validation-preservation-audit.json') $postAudit

$coreSummaryPath = Join-Path $coreRoot 'core-validation-summary.json'
$coreSummary = $null
if (Test-Path -LiteralPath $coreSummaryPath -PathType Leaf) {
    $coreSummary = Get-Content -Raw -LiteralPath $coreSummaryPath | ConvertFrom-Json
}
$passed = (
    $preAudit.passed -and
    $coreExit -eq 0 -and
    $null -ne $coreSummary -and
    $coreSummary.status -eq 'PASS' -and
    $postAudit.passed
)
$finalAudit = [pscustomobject][ordered]@{
    schemaVersion = 1
    auditId = 'gate13r-pr2-nonexecuting-validation-only-final-audit-v2'
    observedAtUtc = [DateTimeOffset]::UtcNow.ToString('o')
    status = $(if ($passed) { 'PASS' } else { 'FAIL' })
    prePreservationPassed = [bool]$preAudit.passed
    coreValidatorExitCode = $coreExit
    coreStatus = $(if ($null -ne $coreSummary) { [string]$coreSummary.status } else { 'NOT-RUN-OR-MISSING' })
    coreCheckCount = $(if ($null -ne $coreSummary) { [int]$coreSummary.checkCount } else { 0 })
    corePassedCheckCount = $(if ($null -ne $coreSummary) { [int]$coreSummary.passedCheckCount } else { 0 })
    coreFailedCheckCount = $(if ($null -ne $coreSummary) { [int]$coreSummary.failedCheckCount } else { 0 })
    postPreservationPassed = [bool]$postAudit.passed
    formalRootAbsent = [bool]$postAudit.formalRootAbsent
    formalExecutionReceiptAbsent = [bool]$postAudit.formalExecutionReceiptAbsent
    unityEditorProcessCountBefore = $unityBefore.Count
    unityEditorProcessCountAfter = $unityAfter.Count
    formalCampaignAuthorized = $false
    gate14rAuthorized = $false
}
Write-AtomicJson (Join-Path $OutputRoot 'validation-only-final-audit.json') $finalAudit

$evidenceFiles = @(Get-ChildItem -LiteralPath $OutputRoot -Recurse -File -Force | Sort-Object FullName)
$evidenceRows = @($evidenceFiles | ForEach-Object {
    [pscustomobject][ordered]@{
        relativePath = $_.FullName.Substring($OutputRoot.Length).TrimStart('\').Replace('\', '/')
        rawBytes = [long]$_.Length
        sha256 = Get-LowerSha256 $_.FullName
    }
})
$evidenceManifest = [pscustomobject][ordered]@{
    schemaVersion = 1
    manifestId = 'gate13r-pr2-validation-evidence-manifest-v2'
    status = $finalAudit.status
    fileCount = $evidenceRows.Count
    files = $evidenceRows
    formalCampaignAuthorized = $false
    gate14rAuthorized = $false
}
Write-AtomicJson (Join-Path $OutputRoot 'evidence-manifest.json') $evidenceManifest

$finalAudit | ConvertTo-Json -Depth 20
if (-not $passed) {
    exit 1
}
