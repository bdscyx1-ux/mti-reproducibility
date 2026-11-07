param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$ProjectPath,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$BaselinePath
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

function Get-CanonicalTree([string]$Path, [string]$RelativeRoot) {
    $root = [IO.Path]::GetFullPath($Path).TrimEnd('\')
    if (-not (Test-Path -LiteralPath $root -PathType Container)) { throw "Protected tree missing: $RelativeRoot" }
    $files = @(Get-ChildItem -LiteralPath $root -Recurse -File -Force)
    $rows = New-Object 'Collections.Generic.List[string]'
    foreach ($file in $files) {
        $relative = $file.FullName.Substring($root.Length).TrimStart('\').Replace('\', '/')
        $rows.Add("$relative`t$($file.Length)`t$(Get-LowerSha256 $file.FullName)")
    }
    $rows.Sort([StringComparer]::Ordinal)
    $sum = ($files | Measure-Object Length -Sum).Sum
    if ($null -eq $sum) { $sum = 0L }
    return [pscustomobject][ordered]@{
        path = $RelativeRoot
        fileCount = $files.Count
        rawBytes = [long]$sum
        ordinalTreeSha256 = Get-StringSha256 ($rows -join "`n")
        firstRow = if ($rows.Count -gt 0) { $rows[0] } else { $null }
        lastRow = if ($rows.Count -gt 0) { $rows[$rows.Count - 1] } else { $null }
    }
}

$resolvedProject = [IO.Path]::GetFullPath($ProjectPath).TrimEnd('\')
$resolvedBaseline = [IO.Path]::GetFullPath($BaselinePath)
$baseline = Get-Content -LiteralPath $resolvedBaseline -Raw | ConvertFrom-Json
$trees = New-Object Collections.Generic.List[object]
$mismatches = New-Object Collections.Generic.List[string]

foreach ($expected in @($baseline.protectedTrees)) {
    $relative = [string]$expected.path
    $actual = Get-CanonicalTree (Join-Path $resolvedProject $relative.Replace('/', '\')) $relative
    $trees.Add($actual)
    if ($actual.fileCount -ne [int]$expected.fileCount) { $mismatches.Add("fileCount:$relative") }
    if ($actual.rawBytes -ne [long]$expected.rawBytes) { $mismatches.Add("rawBytes:$relative") }
    if ($actual.ordinalTreeSha256 -ne [string]$expected.ordinalTreeSha256) { $mismatches.Add("ordinalTreeSha256:$relative") }
}

$result = [ordered]@{
    schemaVersion = 2
    identityId = 'gate11r-canonical-ordinal-relative-path-tree-identity-v2'
    runtime = [ordered]@{
        powerShellVersion = $PSVersionTable.PSVersion.ToString()
        edition = if ($PSVersionTable.PSObject.Properties.Name -contains 'PSEdition') { [string]$PSVersionTable.PSEdition } else { 'Desktop' }
    }
    projectPath = $resolvedProject
    baselineSha256 = Get-LowerSha256 $resolvedBaseline
    status = if ($mismatches.Count -eq 0) { 'PASSED' } else { 'FAILED' }
    mismatchCount = $mismatches.Count
    mismatches = $mismatches.ToArray()
    trees = $trees.ToArray()
}

$result | ConvertTo-Json -Depth 7 -Compress
if ($mismatches.Count -ne 0) { exit 1 }
