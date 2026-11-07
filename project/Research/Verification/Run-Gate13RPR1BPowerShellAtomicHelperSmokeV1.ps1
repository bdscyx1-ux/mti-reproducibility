[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$ProjectPath,
    [Parameter(Mandatory=$true)][string]$OutputRoot
)

$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
if([string]::IsNullOrWhiteSpace($ProjectPath)-or-not[IO.Path]::IsPathRooted($ProjectPath)){throw 'Explicit absolute ProjectPath required.'}
if([string]::IsNullOrWhiteSpace($OutputRoot)-or-not[IO.Path]::IsPathRooted($OutputRoot)){throw 'Explicit absolute OutputRoot required.'}
$ProjectPath=[IO.Path]::GetFullPath($ProjectPath)
$OutputRoot=[IO.Path]::GetFullPath($OutputRoot)
$verificationBase=[IO.Path]::GetFullPath((Join-Path $ProjectPath 'Research\Verification\Gate13R_PR1B_v4_AtomicHelperSmoke'))
if(-not$OutputRoot.StartsWith($verificationBase.TrimEnd('\')+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'Smoke output root is outside the dedicated verification base.'}
if(Test-Path -LiteralPath $OutputRoot){throw "Create-new smoke root already exists: $OutputRoot"}
if(@(Get-Process -Name Unity -ErrorAction SilentlyContinue).Count){throw 'Unity must not be running during the non-Unity atomic-helper smoke.'}
if(Test-Path -LiteralPath (Join-Path $ProjectPath 'Temp\UnityLockfile')){throw 'Unity lock must be absent during the non-Unity atomic-helper smoke.'}
if(Test-Path -LiteralPath (Join-Path $ProjectPath 'Research\FormalRuns\Gate13R_RQAligned\v1')){throw 'Reserved formal root must remain absent.'}

New-Item -ItemType Directory -Path $OutputRoot -Force|Out-Null
Import-Module (Join-Path $ProjectPath 'Research\Gate13RPR1BOrderEffectPreparationV4.psm1') -Force
$checks=New-Object Collections.Generic.List[object]
$errors=New-Object Collections.Generic.List[string]
function Add-Check([string]$Id,[bool]$Passed,[string]$Detail){
    $script:checks.Add([pscustomobject][ordered]@{id=$Id;passed=$Passed;detail=$Detail})
    if(-not$Passed){$script:errors.Add("${Id}: $Detail")}
}

$target=Join-Path $OutputRoot 'mutable.json'
Write-Gate13RPR1BV3AtomicUtf8NoBomJson -Path $target -Value ([ordered]@{generation=1;payload='create-new'}) -Depth 10
$first=Read-Gate13RPR1BV3Json $target
Add-Check 'create-new-same-directory-move' ($first.generation-eq1-and(Get-Content -LiteralPath $target -Encoding Byte -TotalCount 3)[0]-ne0xEF) $target

Write-Gate13RPR1BV3AtomicUtf8NoBomJson -Path $target -Value ([ordered]@{generation=2;payload='replace-existing'}) -Depth 10
$second=Read-Gate13RPR1BV3Json $target
Add-Check 'replace-existing-with-short-backup-leaf' ($second.generation-eq2-and[string]$second.payload-eq'replace-existing') $target

$directoryTarget=Join-Path $OutputRoot 'directory-target'
New-Item -ItemType Directory -Path $directoryTarget -Force|Out-Null
$directoryRejected=$false
try{Write-Gate13RPR1BV3AtomicUtf8NoBomJson -Path $directoryTarget -Value ([ordered]@{invalid=$true}) -Depth 5}catch{$directoryRejected=$_.Exception.Message-like'*target is a directory*'}
Add-Check 'directory-target-rejected' $directoryRejected $directoryTarget

$missingParentTarget=Join-Path $OutputRoot 'missing-parent\value.json'
$missingParentRejected=$false
try{Write-Gate13RPR1BV3AtomicUtf8NoBomJson -Path $missingParentTarget -Value ([ordered]@{invalid=$true}) -Depth 5}catch{$missingParentRejected=$_.Exception.Message-like'*parent does not exist*'}
Add-Check 'missing-parent-rejected' $missingParentRejected $missingParentTarget

$ordinaryParent=Join-Path $OutputRoot 'ordinary-parent'
$junctionParent=Join-Path $OutputRoot 'junction-parent'
New-Item -ItemType Directory -Path $ordinaryParent -Force|Out-Null
$junctionCreated=$false;$junctionRejected=$false;$junctionDetail=$null
try{
    New-Item -ItemType Junction -Path $junctionParent -Target $ordinaryParent -ErrorAction Stop|Out-Null
    $junctionCreated=$true
    try{Write-Gate13RPR1BV3AtomicUtf8NoBomJson -Path (Join-Path $junctionParent 'value.json') -Value ([ordered]@{invalid=$true}) -Depth 5}catch{$junctionRejected=$_.Exception.Message-like'*reparse point*';$junctionDetail=$_.Exception.Message}
}finally{
    if($junctionCreated-and(Test-Path -LiteralPath $junctionParent)){Remove-Item -LiteralPath $junctionParent -Force}
}
Add-Check 'reparse-parent-rejected' ($junctionCreated-and$junctionRejected) $(if($junctionDetail){$junctionDetail}else{'junction unavailable or unexpectedly accepted'})

$lockedTarget=Join-Path $OutputRoot 'locked-mutable.json'
Write-Gate13RPR1BV3AtomicUtf8NoBomJson -Path $lockedTarget -Value ([ordered]@{generation=1}) -Depth 5
$replaceRejected=$false
$handle=[IO.File]::Open($lockedTarget,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::None)
try{try{Write-Gate13RPR1BV3AtomicUtf8NoBomJson -Path $lockedTarget -Value ([ordered]@{generation=2}) -Depth 5}catch{$replaceRejected=$true}}finally{$handle.Dispose()}
$lockedValue=Read-Gate13RPR1BV3Json $lockedTarget
Add-Check 'replace-failure-preserves-target' ($replaceRejected-and$lockedValue.generation-eq1) $lockedTarget

$residues=@(Get-ChildItem -LiteralPath $OutputRoot -Recurse -File -Force|Where-Object{$_.Name-like'.g13tmp-*'-or$_.Name-like'.g13bak-*'})
Add-Check 'zero-owned-helper-residues' ($residues.Count-eq0) (($residues|ForEach-Object FullName)-join'; ')

$summary=[ordered]@{
    schemaVersion=1
    summaryKind='gate13r-pr1b-v4-winps51-atomic-helper-smoke-v1'
    savedAtUtc=[DateTime]::UtcNow.ToString('o')
    windowsPowerShellVersion=$PSVersionTable.PSVersion.ToString()
    moduleSha256=Get-Gate13RPR1BV3LowerSha256 (Join-Path $ProjectPath 'Research\Gate13RPR1BOrderEffectPreparationV4.psm1')
    checkCount=$checks.Count
    passedCheckCount=@($checks|Where-Object passed).Count
    checks=$checks.ToArray()
    errors=$errors.ToArray()
    unityInvoked=$false
    pilotRootCreated=$false
    formalCampaign=$false
    passed=$errors.Count-eq0
}
Write-Gate13RPR1BV3AtomicUtf8NoBomJson -Path (Join-Path $OutputRoot 'summary.json') -Value $summary -Depth 30
if($errors.Count){Write-Error("Atomic-helper smoke failed: "+($errors-join'; '));exit 1}
Write-Output($summary|ConvertTo-Json -Depth 30)
exit 0
