[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$ProjectPath)
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
$ProjectPath=[IO.Path]::GetFullPath($ProjectPath);$utf8=New-Object Text.UTF8Encoding($false,$true)
function Read-Text([string]$Relative){[IO.File]::ReadAllText((Join-Path $ProjectPath $Relative.Replace('/','\')),[Text.Encoding]::UTF8)}
function Write-New([string]$Relative,[string]$Text){$path=Join-Path $ProjectPath $Relative.Replace('/','\');if(Test-Path $path){throw "Create-new output exists: $path"};[IO.File]::WriteAllText($path,$Text,$utf8)}
function Lower-Sha([string]$Path){(Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()}
function Binding([string]$Id,[string]$Relative){$path=Join-Path $ProjectPath $Relative.Replace('/','\');if(-not(Test-Path $path -PathType Leaf)){throw "Binding missing: $Relative"};[pscustomobject][ordered]@{id=$Id;relativePath=$Relative;rawBytes=[long](Get-Item $path).Length;sha256=Lower-Sha $path}}
function Tree-Id([string]$Relative){$root=(Resolve-Path (Join-Path $ProjectPath $Relative.Replace('/','\'))).Path;$rows=@(Get-ChildItem $root -Recurse -File -Force|Sort-Object FullName|ForEach-Object{"$($_.FullName.Substring($root.Length+1).Replace('\','/'))`t$($_.Length)`t$(Lower-Sha $_.FullName)"});$sha=[Security.Cryptography.SHA256]::Create();try{[BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($rows-join"`n"))).Replace('-','').ToLowerInvariant()}finally{$sha.Dispose()}}
$v15Relative='Research/Verification/Gate12R_ProcessReuse_5pct/v15-gate13r-pr1b-order-effect-pathsafe-v5';$v15Expected='c9aa248972b2f7b5d5dbfdf4ad0be707d276778f4f04a6485edc0145983e0802';if((Tree-Id $v15Relative)-ne$v15Expected){throw 'Frozen passed v15 tree changed.'}

$pilot=Read-Text 'Research/Run-Gate13RPR1BOrderEffectPilotV5.ps1'
$pilot=$pilot.Replace('Run-Gate13RPR1BOrderEffectPilotV5','Run-Gate13RPR1BOrderEffectPilotV6')
$pilot=$pilot.Replace("new='Research\Analyze-Gate13RPR1BOrderEffectPilotV5.py'","new='Research\Analyze-Gate13RPR1BOrderEffectPilotV4.py'")
$old=@'
$derivedRoot=Join-Path $verificationRoot '_DerivedHarness\PilotV5'
if(Test-Path -LiteralPath $derivedRoot){throw "Create-new PR1B v3 pilot derived root exists: $derivedRoot"}
New-Item -ItemType Directory -Path $derivedRoot -Force|Out-Null
$derivedPath=Join-Path $derivedRoot 'Run-Gate13RPR1BOrderEffectPilotV6.derived.ps1'
'@
$new=@'
if($null-eq$plan.paths.PSObject.Properties['pilotLaunchHarnessRootRelativePath']){throw 'Pilot launch harness root is missing from the selected plan.'}
$derivedRoot=[IO.Path]::GetFullPath((Join-Path $ProjectPath ([string]$plan.paths.pilotLaunchHarnessRootRelativePath).Replace('/','\')))
$launchBase=[IO.Path]::GetFullPath((Join-Path $ProjectPath 'Research\Verification\Gate12R_ProcessReuse_5pct'))
if(-not$derivedRoot.StartsWith($launchBase.TrimEnd('\')+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'Pilot launch harness root is outside versioned verification containment.'}
if($derivedRoot-eq$verificationRoot-or$derivedRoot-eq$pilotRoot){throw 'Pilot launch harness root aliases a protected execution root.'}
if(Test-Path -LiteralPath $derivedRoot){throw "Create-new PR1B v3 pilot launch harness root exists: $derivedRoot"}
New-Item -ItemType Directory -Path $derivedRoot -Force|Out-Null
$derivedPath=Join-Path $derivedRoot 'Run-Gate13RPR1BOrderEffectPilotV6.derived.ps1'
'@
if(([regex]::Matches($pilot,[regex]::Escape($old))).Count-ne1){throw 'Pilot launch-root replacement identity mismatch.'}
$pilot=$pilot.Replace($old,$new)
if(-not$pilot.Contains("new='Research\Analyze-Gate13RPR1BOrderEffectPilotV4.py'")){throw 'Pilot analyzer route is not V4.'}
Write-New 'Research/Run-Gate13RPR1BOrderEffectPilotV6.ps1' $pilot

$static=Read-Text 'Research/Verification/Run-Gate13RPR1BStaticUnitV5.ps1';$static=$static.Replace('Run-Gate13RPR1BOrderEffectPilotV5','Run-Gate13RPR1BOrderEffectPilotV6').Replace('Run-Gate13RPR1BStaticUnitV5','Run-Gate13RPR1BStaticUnitV6').Replace('Run-Gate13RPR1BPrePilotV7','Run-Gate13RPR1BPrePilotV8')
$anchor="Add-Check 'formal-root-absent' (-not(Test-Path `$formalRoot)) `$formalRoot"
if(([regex]::Matches($static,[regex]::Escape($anchor))).Count-ne1){throw 'Static launch-root anchor mismatch.'}
$addition=@'
Add-Check 'formal-root-absent' (-not(Test-Path $formalRoot)) $formalRoot
$launchHarnessRoot=Join-Path $ProjectPath ([string]$plan.paths.pilotLaunchHarnessRootRelativePath).Replace('/','\')
Add-Check 'pilot-launch-harness-root-absent' (-not(Test-Path $launchHarnessRoot)) $launchHarnessRoot
$pilotWrapperSource=[IO.File]::ReadAllText((Join-Path $ProjectPath 'Research\Run-Gate13RPR1BOrderEffectPilotV6.ps1'),[Text.Encoding]::UTF8)
Add-Check 'pilot-analyzer-route-bound-v4' ($pilotWrapperSource.Contains("new='Research\Analyze-Gate13RPR1BOrderEffectPilotV4.py'")-and-not$pilotWrapperSource.Contains('Analyze-Gate13RPR1BOrderEffectPilotV5.py')) 'Analyzer V4 is the only active route.'
'@
$static=$static.Replace($anchor,$addition.TrimEnd("`r","`n"));Write-New 'Research/Verification/Run-Gate13RPR1BStaticUnitV6.ps1' $static

$pre=Read-Text 'Research/Verification/Run-Gate13RPR1BPrePilotV7.ps1';$pre=$pre.Replace('Run-Gate13RPR1BPrePilotV7','Run-Gate13RPR1BPrePilotV8').Replace('pre-pilot v7','pre-pilot v8').Replace('Run-Gate13RPR1BStaticUnitV5','Run-Gate13RPR1BStaticUnitV6')
$preAnchor="`$pilotRoot=Join-Path `$ProjectPath ([string]`$plan.paths.pilotRootRelativePath).Replace('/','\');`$formalRoot=Join-Path `$ProjectPath ([string]`$plan.paths.reservedFormalRootRelativePath).Replace('/','\')"
if(([regex]::Matches($pre,[regex]::Escape($preAnchor))).Count-ne1){throw 'Pre-pilot launch-root anchor mismatch.'}
$preReplacement=$preAnchor+";`$launchHarnessRoot=Join-Path `$ProjectPath ([string]`$plan.paths.pilotLaunchHarnessRootRelativePath).Replace('/','\')"
$pre=$pre.Replace($preAnchor,$preReplacement)
$pre=$pre.Replace("if(Test-Path `$pilotRoot){throw 'PR1B v3 pilot root must be absent during pre-pilot.'}","if(Test-Path `$pilotRoot){throw 'PR1B v3 pilot root must be absent during pre-pilot.'};if(Test-Path `$launchHarnessRoot){throw 'PR1B pilot launch harness root must be absent during pre-pilot.'}")
Write-New 'Research/Verification/Run-Gate13RPR1BPrePilotV8.ps1' $pre

$planSource=Join-Path $ProjectPath 'Research/Gate13R_PR1B_OrderEffect_Pilot_Plan.v8.json';$planOutput=Join-Path $ProjectPath 'Research/Gate13R_PR1B_OrderEffect_Pilot_Plan.v9.json';if(Test-Path $planOutput){throw 'Plan v9 exists.'};$plan=[IO.File]::ReadAllText($planSource,[Text.Encoding]::UTF8)|ConvertFrom-Json;$plan.attemptNumber=7;$plan.operationalVerificationRevision=9;$plan.amendmentId='gate13r-pr1b-v6-byte-bound-pilot-launch-routing-v1';$plan.paths.verificationRootRelativePath='Research/Verification/Gate12R_ProcessReuse_5pct/v16-gate13r-pr1b-order-effect-pathsafe-v6';$plan.paths|Add-Member -NotePropertyName pilotLaunchHarnessRootRelativePath -NotePropertyValue 'Research/Verification/Gate12R_ProcessReuse_5pct/v17-gate13r-pr1b-pilot-launch-harness-v1';$plan.paths|Add-Member -NotePropertyName verificationAttempt7RootRelativePath -NotePropertyValue $v15Relative;$plan.paths|Add-Member -NotePropertyName verificationAttempt7LaunchGapRelativePath -NotePropertyValue 'Research/Gate13R_PR1B_v5_PilotLaunch_Routing_Gap_Diagnosis.v1.json';[IO.File]::WriteAllText($planOutput,(($plan|ConvertTo-Json -Depth 70).Replace("`r`n","`n").Replace("`r","`n")+"`n"),$utf8)

$parentRelative='Research/Gate13R_PR1B_OrderEffect_Provenance.v9.json';$parentPath=Join-Path $ProjectPath $parentRelative.Replace('/','\');$p=[IO.File]::ReadAllText($parentPath,[Text.Encoding]::UTF8)|ConvertFrom-Json;foreach($b in @($p.boundFiles)){$path=Join-Path $ProjectPath ([string]$b.relativePath).Replace('/','\');if(-not(Test-Path $path -PathType Leaf)-or(Lower-Sha $path)-ne[string]$b.sha256){throw "Parent provenance mismatch: $($b.relativePath)"}}
$config=Binding 'gate13rPr1bPilotPlanV9' 'Research/Gate13R_PR1B_OrderEffect_Pilot_Plan.v9.json';$extras=@($config,(Binding 'parentProvenanceV9' $parentRelative),(Binding 'pilotLaunchRoutingAmendmentV6' 'Research/Gate13R_PR1B_PathSafe_Atomic_Persistence_Amendment.v6.json'),(Binding 'v15PilotLaunchGapDiagnosis' 'Research/Gate13R_PR1B_v5_PilotLaunch_Routing_Gap_Diagnosis.v1.json'),(Binding 'v15LaunchAuditSuperseded' 'Research/Gate13R_PR1B_v5_Pilot_Launch_Audit.v1.json'),(Binding 'pilotLaunchRoutingBuilderV6' 'Research/Build-Gate13RPR1BPilotLaunchRoutingV6.ps1'),(Binding 'activePilotWrapperV6' 'Research/Run-Gate13RPR1BOrderEffectPilotV6.ps1'),(Binding 'activeStaticUnitV6' 'Research/Verification/Run-Gate13RPR1BStaticUnitV6.ps1'),(Binding 'activePrePilotV8' 'Research/Verification/Run-Gate13RPR1BPrePilotV8.ps1'))
$bound=New-Object Collections.Generic.List[object];foreach($b in @($p.boundFiles)){$bound.Add($b)};foreach($b in $extras){$bound.Add($b)}
$p.schemaVersion=10;$p.provenanceId='gate13r-pr1b-v6-byte-bound-pilot-launch-routing-provenance-v1';$p.createdAtUtc=[DateTime]::UtcNow.ToString('o');$p.createdAtAsiaShanghai=[TimeZoneInfo]::ConvertTimeBySystemTimeZoneId([DateTime]::UtcNow,'China Standard Time').ToString('o')+'+08:00';$p.status='FROZEN-BEFORE-V16-VERIFICATION';$p.parentProvenance=[pscustomobject][ordered]@{relativePath=$parentRelative;rawBytes=[long](Get-Item $parentPath).Length;sha256=Lower-Sha $parentPath};$p.config=$config;$p.boundFiles=@($bound.ToArray());$p|Add-Member -NotePropertyName passedV15SupersededForLaunchRouting -NotePropertyValue ([pscustomobject][ordered]@{relativePath=$v15Relative;treeIdentitySha256=$v15Expected;prePilotPassed=$true;pilotAttemptConsumed=$false})
$provOutput=Join-Path $ProjectPath 'Research/Gate13R_PR1B_OrderEffect_Provenance.v10.json';if(Test-Path $provOutput){throw 'Provenance v10 exists.'};[IO.File]::WriteAllText($provOutput,(($p|ConvertTo-Json -Depth 100).Replace("`r`n","`n").Replace("`r","`n")+"`n"),$utf8)
[pscustomobject]@{passed=$true;planSha256=Lower-Sha $planOutput;provenanceSha256=Lower-Sha $provOutput;boundFileCount=$bound.Count;v15TreeIdentitySha256=$v15Expected}|ConvertTo-Json -Depth 5
