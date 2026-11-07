[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$ProjectPath)

$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$ProjectPath=[IO.Path]::GetFullPath($ProjectPath)
$parentRelative='Research/Gate13R_PR1B_OrderEffect_Provenance.v6.json'
$outputRelative='Research/Gate13R_PR1B_OrderEffect_Provenance.v7.json'
$parentPath=Join-Path $ProjectPath $parentRelative.Replace('/','\')
$outputPath=Join-Path $ProjectPath $outputRelative.Replace('/','\')
if(Test-Path -LiteralPath $outputPath){throw "Create-new provenance already exists: $outputPath"}
$p=[IO.File]::ReadAllText($parentPath,[Text.Encoding]::UTF8)|ConvertFrom-Json
foreach($binding in @($p.boundFiles)){
    $path=Join-Path $ProjectPath ([string]$binding.relativePath).Replace('/','\')
    if(-not(Test-Path -LiteralPath $path -PathType Leaf)){throw "Parent provenance input missing: $($binding.relativePath)"}
    $actual=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
    if($actual-ne[string]$binding.sha256){throw "Parent provenance mismatch: $($binding.relativePath)"}
}
$extra=@(
    'Research/Gate13R_PR1B_OrderEffect_Provenance.v6.json',
    'Research/Verification/Run-Gate13RPR1BPowerShellAtomicHelperSmokeV1.ps1',
    'Research/Verification/Gate13R_PR1B_v4_AtomicHelperSmoke/v1/summary.json',
    'Research/Freeze-Gate13RPR1BPathSafeProvenanceV7.ps1'
)
$bound=New-Object Collections.Generic.List[object]
foreach($entry in @($p.boundFiles)){$bound.Add($entry)}
foreach($relative in $extra){
    $path=Join-Path $ProjectPath $relative.Replace('/','\')
    if(-not(Test-Path -LiteralPath $path -PathType Leaf)){throw "V7 provenance input missing: $relative"}
    $bound.Add([pscustomobject][ordered]@{relativePath=$relative;rawBytes=[long](Get-Item -LiteralPath $path).Length;sha256=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()})
}
$p.schemaVersion=7
$p.provenanceId='gate13r-pr1b-v4-winps51-pathsafe-balanced-mirrored-pilot-provenance-v2'
$p.createdAtUtc=[DateTime]::UtcNow.ToString('o')
$p.createdAtAsiaShanghai=[TimeZoneInfo]::ConvertTimeBySystemTimeZoneId([DateTime]::UtcNow,'China Standard Time').ToString('o')+'+08:00'
$p.status='FROZEN-AFTER-WINPS51-ATOMIC-HELPER-SMOKE-BEFORE-V13-VERIFICATION'
$p.parentProvenance=[pscustomobject][ordered]@{relativePath=$parentRelative;rawBytes=[long](Get-Item -LiteralPath $parentPath).Length;sha256=(Get-FileHash -LiteralPath $parentPath -Algorithm SHA256).Hash.ToLowerInvariant()}
$p.boundFiles=@($bound.ToArray())
$p|Add-Member -NotePropertyName winps51AtomicHelperSmoke -NotePropertyValue ([pscustomobject][ordered]@{
    relativePath='Research/Verification/Gate13R_PR1B_v4_AtomicHelperSmoke/v1/summary.json'
    checkCount=7
    passedCheckCount=7
    passed=$true
    unityInvoked=$false
})
$utf8=New-Object Text.UTF8Encoding($false,$true)
$json=($p|ConvertTo-Json -Depth 80).Replace("`r`n","`n").Replace("`r","`n")+"`n"
[IO.File]::WriteAllText($outputPath,$json,$utf8)
[pscustomobject]@{passed=$true;output=$outputPath;boundFileCount=$bound.Count;sha256=(Get-FileHash -LiteralPath $outputPath -Algorithm SHA256).Hash.ToLowerInvariant()}|ConvertTo-Json -Depth 5
