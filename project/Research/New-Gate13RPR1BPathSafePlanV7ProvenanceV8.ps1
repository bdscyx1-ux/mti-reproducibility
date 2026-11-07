[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$ProjectPath)

$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$ProjectPath=[IO.Path]::GetFullPath($ProjectPath)
$utf8=New-Object Text.UTF8Encoding($false,$true)
function Lower-Sha([string]$Path){(Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()}
function Binding([string]$Id,[string]$Relative){$path=Join-Path $ProjectPath $Relative.Replace('/','\');if(-not(Test-Path -LiteralPath $path -PathType Leaf)){throw "Binding missing: $Relative"};[pscustomobject][ordered]@{id=$Id;relativePath=$Relative;rawBytes=[long](Get-Item -LiteralPath $path).Length;sha256=Lower-Sha $path}}
function Tree-Identity([string]$Relative){
    $root=(Resolve-Path -LiteralPath (Join-Path $ProjectPath $Relative.Replace('/','\'))).Path
    $rows=@(Get-ChildItem -LiteralPath $root -Recurse -File -Force|Sort-Object FullName|ForEach-Object{"$($_.FullName.Substring($root.Length+1).Replace('\','/'))`t$($_.Length)`t$(Lower-Sha $_.FullName)"})
    $sha=[Security.Cryptography.SHA256]::Create();try{[BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($rows-join"`n"))).Replace('-','').ToLowerInvariant()}finally{$sha.Dispose()}
}

$v13Relative='Research/Verification/Gate12R_ProcessReuse_5pct/v13-gate13r-pr1b-order-effect-pathsafe-v4'
$v13Expected='34ba634c4cff9d90a4f52b01ceca0372cadb7607dec91cc8bf0d1734dc82cce0'
$v13Actual=Tree-Identity $v13Relative
if($v13Actual-ne$v13Expected){throw "Frozen v13 tree changed: $v13Actual"}

$planSource=Join-Path $ProjectPath 'Research/Gate13R_PR1B_OrderEffect_Pilot_Plan.v6.json'
$planOutput=Join-Path $ProjectPath 'Research/Gate13R_PR1B_OrderEffect_Pilot_Plan.v7.json'
if(Test-Path -LiteralPath $planOutput){
    $plan=[IO.File]::ReadAllText($planOutput,[Text.Encoding]::UTF8)|ConvertFrom-Json
    if([int]$plan.attemptNumber-ne5-or[int]$plan.operationalVerificationRevision-ne7-or[string]$plan.paths.verificationRootRelativePath-ne'Research/Verification/Gate12R_ProcessReuse_5pct/v14-gate13r-pr1b-order-effect-pathsafe-v4'-or[string]$plan.paths.verificationAttempt5RootRelativePath-ne$v13Relative){throw 'Existing plan v7 is not the exact idempotent generator result.'}
}else{
    $plan=[IO.File]::ReadAllText($planSource,[Text.Encoding]::UTF8)|ConvertFrom-Json
    $plan.attemptNumber=5
    $plan.operationalVerificationRevision=7
    $plan.paths.verificationRootRelativePath='Research/Verification/Gate12R_ProcessReuse_5pct/v14-gate13r-pr1b-order-effect-pathsafe-v4'
    $plan.paths|Add-Member -NotePropertyName verificationAttempt5RootRelativePath -NotePropertyValue $v13Relative
    $plan.paths|Add-Member -NotePropertyName verificationAttempt5TerminalPreservationRelativePath -NotePropertyValue 'Research/Gate13R_PR1B_v4_PrePilot_v13_Terminal_Preservation.v1.json'
    $planJson=($plan|ConvertTo-Json -Depth 60).Replace("`r`n","`n").Replace("`r","`n")+"`n"
    [IO.File]::WriteAllText($planOutput,$planJson,$utf8)
}

$parentRelative='Research/Gate13R_PR1B_OrderEffect_Provenance.v7.json'
$parentPath=Join-Path $ProjectPath $parentRelative.Replace('/','\')
$p=[IO.File]::ReadAllText($parentPath,[Text.Encoding]::UTF8)|ConvertFrom-Json
foreach($b in @($p.boundFiles)){$path=Join-Path $ProjectPath ([string]$b.relativePath).Replace('/','\');if(-not(Test-Path -LiteralPath $path -PathType Leaf)-or(Lower-Sha $path)-ne[string]$b.sha256){throw "Parent provenance binding failed: $($b.relativePath)"}}
$auth=Binding 'gate13rPr1bV3UserAuthorization' 'Research/Gate13R_PR1B_v3_Authorization.v1.json'
$command=Binding 'gate13rPr1bMemoryAwareProcessReuseBatchCommandV3' 'Assets/_Scripts/Research/Editor/Gate13RPR1BMemoryAwareProcessReuseBatchCommandV3.cs'
if($auth.sha256-ne'03119942fdb7794f8a5fb294494eea2f254b63ea53a0d96957016ae5680272f7'){throw 'Frozen v3 authorization hash mismatch.'}
if($command.sha256-ne'a47a731c979d58304230a150947ca1bb50207d13d1214b7d4de6e683bba6b5d6'){throw 'Frozen V3 Unity command hash mismatch.'}
$config=Binding 'gate13rPr1bPilotPlanV7' 'Research/Gate13R_PR1B_OrderEffect_Pilot_Plan.v7.json'
$extras=@(
    $config,
    (Binding 'parentProvenanceV7' $parentRelative),
    (Binding 'v13TerminalPreservation' 'Research/Gate13R_PR1B_v4_PrePilot_v13_Terminal_Preservation.v1.json'),
    (Binding 'v13FailureDiagnosis' 'Research/Gate13R_PR1B_v4_PrePilot_v13_Failure_Diagnosis.v1.md'),
    (Binding 'v13FailureCheckpoint' 'Research/Gate13R_PR1B_v4_PrePilot_v13_Failure_Checkpoint.v1.json'),
    (Binding 'planProvenanceGeneratorV8' 'Research/New-Gate13RPR1BPathSafePlanV7ProvenanceV8.ps1'),
    (Binding 'provenanceCompatibilitySmokeRunnerV1' 'Research/Verification/Run-Gate13RPR1BProvenanceCompatibilitySmokeV1.ps1')
)
$bound=New-Object Collections.Generic.List[object]
foreach($b in @($p.boundFiles)){$bound.Add($b)}
foreach($b in $extras){$bound.Add($b)}
$p.schemaVersion=8
$p.provenanceId='gate13r-pr1b-v4-pathsafe-provenance-compatibility-repair-v1'
$p.createdAtUtc=[DateTime]::UtcNow.ToString('o')
$p.createdAtAsiaShanghai=[TimeZoneInfo]::ConvertTimeBySystemTimeZoneId([DateTime]::UtcNow,'China Standard Time').ToString('o')+'+08:00'
$p.status='FROZEN-BEFORE-PROVENANCE-COMPATIBILITY-SMOKE-AND-V14-VERIFICATION'
$p.parentProvenance=[pscustomobject][ordered]@{relativePath=$parentRelative;rawBytes=[long](Get-Item -LiteralPath $parentPath).Length;sha256=Lower-Sha $parentPath}
$p.config=$config
$p|Add-Member -NotePropertyName executionAuthorization -NotePropertyValue $auth
$p|Add-Member -NotePropertyName unityCommand -NotePropertyValue $command
$p.boundFiles=@($bound.ToArray())
$p|Add-Member -NotePropertyName failedV13 -NotePropertyValue ([pscustomobject][ordered]@{relativePath=$v13Relative;fileCount=54;rawBytes=381042;treeIdentitySha256=$v13Expected;status='FAILED-NO-PILOT-BEFORE-BLOCK-SAMPLE'})
$output=Join-Path $ProjectPath 'Research/Gate13R_PR1B_OrderEffect_Provenance.v8.json'
if(Test-Path -LiteralPath $output){throw "Create-new provenance exists: $output"}
$json=($p|ConvertTo-Json -Depth 80).Replace("`r`n","`n").Replace("`r","`n")+"`n"
[IO.File]::WriteAllText($output,$json,$utf8)
[pscustomobject]@{passed=$true;plan=$planOutput;planSha256=Lower-Sha $planOutput;provenance=$output;provenanceSha256=Lower-Sha $output;boundFileCount=$bound.Count;v13TreeIdentitySha256=$v13Actual}|ConvertTo-Json -Depth 6
