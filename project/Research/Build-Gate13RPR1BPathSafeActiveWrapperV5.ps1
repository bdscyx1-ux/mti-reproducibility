[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$ProjectPath)

$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$ProjectPath=[IO.Path]::GetFullPath($ProjectPath)
$utf8=New-Object Text.UTF8Encoding($false,$true)
function Read-Text([string]$Relative){[IO.File]::ReadAllText((Join-Path $ProjectPath $Relative.Replace('/','\')),[Text.Encoding]::UTF8)}
function Write-New([string]$Relative,[string]$Text){$path=Join-Path $ProjectPath $Relative.Replace('/','\');if(Test-Path $path){throw "Create-new output exists: $path"};[IO.File]::WriteAllText($path,$Text,$utf8)}
function Lower-Sha([string]$Path){(Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()}
function Binding([string]$Id,[string]$Relative){$path=Join-Path $ProjectPath $Relative.Replace('/','\');if(-not(Test-Path $path -PathType Leaf)){throw "Binding missing: $Relative"};[pscustomobject][ordered]@{id=$Id;relativePath=$Relative;rawBytes=[long](Get-Item $path).Length;sha256=Lower-Sha $path}}
function Tree-Id([string]$Relative){$root=(Resolve-Path (Join-Path $ProjectPath $Relative.Replace('/','\'))).Path;$rows=@(Get-ChildItem $root -Recurse -File -Force|Sort-Object FullName|ForEach-Object{"$($_.FullName.Substring($root.Length+1).Replace('\','/'))`t$($_.Length)`t$(Lower-Sha $_.FullName)"});$sha=[Security.Cryptography.SHA256]::Create();try{[BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($rows-join"`n"))).Replace('-','').ToLowerInvariant()}finally{$sha.Dispose()}}

$v14Relative='Research/Verification/Gate12R_ProcessReuse_5pct/v14-gate13r-pr1b-order-effect-pathsafe-v4'
$v14Expected='c9998236dae887c8451f76650422dd6ac7205e6cf82298b454a5b79f9dc75bc9'
if((Tree-Id $v14Relative)-ne$v14Expected){throw 'Frozen v14 verification tree changed.'}

$block=Read-Text 'Research/Run-Gate13RPR1BMemoryAwareBlockV4.ps1'
$block=$block.Replace('Run-Gate13RPR1BMemoryAwareBlockV4','Run-Gate13RPR1BMemoryAwareBlockV5')
$anchor='$UnityPath=[IO.Path]::GetFullPath($UnityPath)'
if(([regex]::Matches($block,[regex]::Escape($anchor))).Count-ne1){throw 'Block wrapper import anchor mismatch.'}
$block=$block.Replace($anchor,$anchor+"`r`nImport-Module (Join-Path `$ProjectPath 'Research\Gate13RPR1BOrderEffectPreparationV4.psm1') -Force")
$old=@'
    $json=($summary|ConvertTo-Json -Depth 50).Replace("`r`n","`n").Replace("`r","`n")+"`n"
    $summaryParent=[IO.Path]::GetDirectoryName([IO.Path]::GetFullPath($summaryPath));$tmp=Join-Path $summaryParent ('.g13tmp-'+[Guid]::NewGuid().ToString('N'));$owned=$false
    try{[IO.File]::WriteAllText($tmp,$json,(New-Object Text.UTF8Encoding($false,$true)));$owned=$true;[IO.File]::Replace($tmp,$summaryPath,$null);$owned=$false}finally{if($owned-and(Test-Path -LiteralPath $tmp)){[IO.File]::Delete($tmp)}}
'@
$new=@'
    Write-Gate13RPR1BV3AtomicUtf8NoBomJson -Path $summaryPath -Value $summary -Depth 50
'@
if(([regex]::Matches($block,[regex]::Escape($old))).Count-ne1){throw 'Embedded null-backup summary replacement identity mismatch.'}
$block=$block.Replace($old,$new)
if($block-match'(?i)File\]::Replace\([^\r\n]*,\s*\$null(?:\s*,|\s*\))'){throw 'Null-backup File.Replace remains in new block wrapper.'}
Write-New 'Research/Run-Gate13RPR1BMemoryAwareBlockV5.ps1' $block

function Derive([string]$Source,[string]$Destination,[Collections.IDictionary]$Map){$text=Read-Text $Source;foreach($key in $Map.Keys){$text=$text.Replace([string]$key,[string]$Map[$key])};Write-New $Destination $text}
Derive 'Research/Verification/Run-Gate13RPR1BBlockVerificationV5.ps1' 'Research/Verification/Run-Gate13RPR1BBlockVerificationV6.ps1' ([ordered]@{'Run-Gate13RPR1BBlockVerificationV5'='Run-Gate13RPR1BBlockVerificationV6';'Run-Gate13RPR1BMemoryAwareBlockV4'='Run-Gate13RPR1BMemoryAwareBlockV5';'BlockVerificationV5'='BlockVerificationV6'})
Derive 'Research/Run-Gate13RPR1BOrderEffectPilotV4.ps1' 'Research/Run-Gate13RPR1BOrderEffectPilotV5.ps1' ([ordered]@{'Run-Gate13RPR1BOrderEffectPilotV4'='Run-Gate13RPR1BOrderEffectPilotV5';'Run-Gate13RPR1BMemoryAwareBlockV4'='Run-Gate13RPR1BMemoryAwareBlockV5';'PilotV4'='PilotV5'})
Derive 'Research/Verification/Run-Gate13RPR1BStaticUnitV4.ps1' 'Research/Verification/Run-Gate13RPR1BStaticUnitV5.ps1' ([ordered]@{'Run-Gate13RPR1BStaticUnitV4'='Run-Gate13RPR1BStaticUnitV5';'Run-Gate13RPR1BMemoryAwareBlockV4'='Run-Gate13RPR1BMemoryAwareBlockV5';'Run-Gate13RPR1BOrderEffectPilotV4'='Run-Gate13RPR1BOrderEffectPilotV5';'Run-Gate13RPR1BBlockVerificationV5'='Run-Gate13RPR1BBlockVerificationV6';'Run-Gate13RPR1BPrePilotV6'='Run-Gate13RPR1BPrePilotV7'})
$staticPath=Join-Path $ProjectPath 'Research/Verification/Run-Gate13RPR1BStaticUnitV5.ps1'
$static=[IO.File]::ReadAllText($staticPath,[Text.Encoding]::UTF8)
$staticAnchor="`$python=Join-Path `$ProjectPath 'Research\Analyze-Gate13RPR1BOrderEffectPilotV4.py'"
if(([regex]::Matches($static,[regex]::Escape($staticAnchor))).Count-ne1){throw 'Static insertion anchor mismatch.'}
$staticCheck=@'
$nullBackupHits=New-Object Collections.Generic.List[string]
foreach($relative in $scripts){$activePath=Join-Path $ProjectPath $relative;if(Test-Path $activePath){$activeSource=[IO.File]::ReadAllText($activePath,[Text.Encoding]::UTF8);if($activeSource-match'(?i)File\]::Replace\([^\r\n]*,\s*\$null(?:\s*,|\s*\))'){$nullBackupHits.Add($relative)}}}
Add-Check 'active-powershell-zero-null-backup-file-replace' ($nullBackupHits.Count-eq0) ($nullBackupHits-join'; ')

'@
$static=$static.Replace($staticAnchor,$staticCheck+$staticAnchor)
[IO.File]::WriteAllText($staticPath,$static,$utf8)
Derive 'Research/Verification/Run-Gate13RPR1BPrePilotV6.ps1' 'Research/Verification/Run-Gate13RPR1BPrePilotV7.ps1' ([ordered]@{'Run-Gate13RPR1BPrePilotV6'='Run-Gate13RPR1BPrePilotV7';'pre-pilot v6'='pre-pilot v7';'Run-Gate13RPR1BStaticUnitV4'='Run-Gate13RPR1BStaticUnitV5';'Run-Gate13RPR1BBlockVerificationV5'='Run-Gate13RPR1BBlockVerificationV6'})

$planSource=Join-Path $ProjectPath 'Research/Gate13R_PR1B_OrderEffect_Pilot_Plan.v7.json';$planOutput=Join-Path $ProjectPath 'Research/Gate13R_PR1B_OrderEffect_Pilot_Plan.v8.json';if(Test-Path $planOutput){throw 'Plan v8 already exists.'}
$plan=[IO.File]::ReadAllText($planSource,[Text.Encoding]::UTF8)|ConvertFrom-Json;$plan.attemptNumber=6;$plan.operationalVerificationRevision=8;$plan.amendmentId='gate13r-pr1b-v5-active-powershell-null-backup-elimination-v1';$plan.paths.verificationRootRelativePath='Research/Verification/Gate12R_ProcessReuse_5pct/v15-gate13r-pr1b-order-effect-pathsafe-v5';$plan.paths|Add-Member -NotePropertyName verificationAttempt6RootRelativePath -NotePropertyValue $v14Relative;$plan.paths|Add-Member -NotePropertyName verificationAttempt6TerminalPreservationRelativePath -NotePropertyValue 'Research/Gate13R_PR1B_v4_PrePilot_v14_Terminal_Preservation.v1.json';[IO.File]::WriteAllText($planOutput,(($plan|ConvertTo-Json -Depth 60).Replace("`r`n","`n").Replace("`r","`n")+"`n"),$utf8)

$parentRelative='Research/Gate13R_PR1B_OrderEffect_Provenance.v8.json';$parentPath=Join-Path $ProjectPath $parentRelative.Replace('/','\');$p=[IO.File]::ReadAllText($parentPath,[Text.Encoding]::UTF8)|ConvertFrom-Json
foreach($b in @($p.boundFiles)){$path=Join-Path $ProjectPath ([string]$b.relativePath).Replace('/','\');if(-not(Test-Path $path -PathType Leaf)-or(Lower-Sha $path)-ne[string]$b.sha256){throw "Parent provenance mismatch: $($b.relativePath)"}}
$config=Binding 'gate13rPr1bPilotPlanV8' 'Research/Gate13R_PR1B_OrderEffect_Pilot_Plan.v8.json'
$extras=@($config,(Binding 'parentProvenanceV8' $parentRelative),(Binding 'activeNullBackupAmendmentV5' 'Research/Gate13R_PR1B_PathSafe_Atomic_Persistence_Amendment.v5.json'),(Binding 'v14TerminalPreservation' 'Research/Gate13R_PR1B_v4_PrePilot_v14_Terminal_Preservation.v1.json'),(Binding 'v14FailureDiagnosis' 'Research/Gate13R_PR1B_v4_PrePilot_v14_Failure_Diagnosis.v1.md'),(Binding 'v14FailureCheckpoint' 'Research/Gate13R_PR1B_v4_PrePilot_v14_Failure_Checkpoint.v1.json'),(Binding 'activeWrapperBuilderV5' 'Research/Build-Gate13RPR1BPathSafeActiveWrapperV5.ps1'),(Binding 'activeBlockWrapperV5' 'Research/Run-Gate13RPR1BMemoryAwareBlockV5.ps1'),(Binding 'activePilotWrapperV5' 'Research/Run-Gate13RPR1BOrderEffectPilotV5.ps1'),(Binding 'activeStaticUnitV5' 'Research/Verification/Run-Gate13RPR1BStaticUnitV5.ps1'),(Binding 'activeBlockVerificationV6' 'Research/Verification/Run-Gate13RPR1BBlockVerificationV6.ps1'),(Binding 'activePrePilotV7' 'Research/Verification/Run-Gate13RPR1BPrePilotV7.ps1'))
$bound=New-Object Collections.Generic.List[object];foreach($b in @($p.boundFiles)){$bound.Add($b)};foreach($b in $extras){$bound.Add($b)}
$p.schemaVersion=9;$p.provenanceId='gate13r-pr1b-v5-active-powershell-null-backup-elimination-provenance-v1';$p.createdAtUtc=[DateTime]::UtcNow.ToString('o');$p.createdAtAsiaShanghai=[TimeZoneInfo]::ConvertTimeBySystemTimeZoneId([DateTime]::UtcNow,'China Standard Time').ToString('o')+'+08:00';$p.status='FROZEN-BEFORE-V15-VERIFICATION';$p.parentProvenance=[pscustomobject][ordered]@{relativePath=$parentRelative;rawBytes=[long](Get-Item $parentPath).Length;sha256=Lower-Sha $parentPath};$p.config=$config;$p.boundFiles=@($bound.ToArray());$p|Add-Member -NotePropertyName failedV14 -NotePropertyValue ([pscustomobject][ordered]@{relativePath=$v14Relative;fileCount=78;rawBytes=624428;treeIdentitySha256=$v14Expected;status='FAILED-NO-PILOT-FIRST-POSITIVE-BASE-BLOCK-PASSED'})
$provOutput=Join-Path $ProjectPath 'Research/Gate13R_PR1B_OrderEffect_Provenance.v9.json';if(Test-Path $provOutput){throw 'Provenance v9 already exists.'};[IO.File]::WriteAllText($provOutput,(($p|ConvertTo-Json -Depth 90).Replace("`r`n","`n").Replace("`r","`n")+"`n"),$utf8)
[pscustomobject]@{passed=$true;planSha256=Lower-Sha $planOutput;provenanceSha256=Lower-Sha $provOutput;boundFileCount=$bound.Count;v14TreeIdentitySha256=$v14Expected}|ConvertTo-Json -Depth 5
