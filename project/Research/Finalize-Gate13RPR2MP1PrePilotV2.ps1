[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$ProjectPath,
    [Parameter(Mandatory = $true)][string]$VerificationRoot,
    [switch]$BindingSmokeOnly
)
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
if ([string]::IsNullOrWhiteSpace($ProjectPath) -or -not [IO.Path]::IsPathRooted($ProjectPath)) { throw 'An explicit absolute ProjectPath is required.' }
$ProjectPath=[IO.Path]::GetFullPath($ProjectPath)
if($BindingSmokeOnly){Write-Output "BINDING-SMOKE-PASSED|Finalize-Gate13RPR2MP1PrePilotV2|$ProjectPath";exit 0}
$VerificationRoot=[IO.Path]::GetFullPath($VerificationRoot)
$base=[IO.Path]::GetFullPath((Join-Path $ProjectPath 'Research\Verification\Gate13R_PR2_MP1_v2')).TrimEnd('\','/')
if(-not $VerificationRoot.StartsWith($base+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){throw 'Finalizer verification root is outside the v2 verification base.'}
Import-Module (Join-Path $ProjectPath 'Research\Gate13RPR2MemoryPolicyPilotV2.psm1') -Force
$auditPath=Join-Path $ProjectPath 'Research\Gate13R_PR2_MP1_PrePilot_Final_Audit.v2.json'
$checkpointPath=Join-Path $ProjectPath 'Research\Gate13R_PR2_MP1_PrePilot_Readiness_Checkpoint.v2.json'
foreach($path in @($auditPath,$checkpointPath)){if(Test-Path -LiteralPath $path){throw "Create-new v2 pre-pilot artifact exists: $path"}}
$checks=New-Object Collections.Generic.List[object]
function Add-Check([string]$Id,[bool]$Passed,$Evidence){$script:checks.Add([ordered]@{id=$Id;passed=$Passed;evidence=$Evidence})}
function Read-Summary([string]$Relative){$path=Join-Path $VerificationRoot $Relative; if(-not(Test-Path -LiteralPath $path -PathType Leaf)){throw "Validation summary is absent: $path"}; return Read-G13RPR2MP1V2Json $path}

$static=Read-Summary 'Static\static-unit-summary.json';Add-Check 'static-unit-at-least-345' ($static.passed -eq $true -and [int]$static.checkCount -ge 345 -and [int]$static.passedCheckCount -eq [int]$static.checkCount) ([ordered]@{checkCount=$static.checkCount;sha256=Get-G13RPR2MP1V2Sha256 (Join-Path $VerificationRoot 'Static\static-unit-summary.json')})
$state7=Read-Summary 'CheckpointPS7\checkpoint-state-machine-summary.json';Add-Check 'checkpoint-state-machine-ps7-12-of-12' ($state7.passed -eq $true -and [int]$state7.testCount -eq 12 -and [int]$state7.passedTestCount -eq 12) $state7.runtime
$state51=Read-Summary 'CheckpointPS51\checkpoint-state-machine-summary.json';Add-Check 'checkpoint-state-machine-ps51-12-of-12' ($state51.passed -eq $true -and [int]$state51.testCount -eq 12 -and [int]$state51.passedTestCount -eq 12) $state51.runtime
$zero7=Read-Summary 'ZeroBlockPS7\zero-block-failure-summary.json';Add-Check 'zero-block-outer-failure-ps7' ($zero7.passed -eq $true) $zero7.childExitCode
$zero51=Read-Summary 'ZeroBlockPS51\zero-block-failure-summary.json';Add-Check 'zero-block-outer-failure-ps51' ($zero51.passed -eq $true) $zero51.childExitCode
$runtime=Read-Summary 'RuntimeValidation\runtime-validation-summary.json';Add-Check 'parser-and-binding-both-runtimes' ($runtime.passed -eq $true -and [int]$runtime.parserPassedCount -eq 2 -and [int]$runtime.bindingFailedCount -eq 0) $runtime
$unity=Read-Summary 'UnitySelfTests\unity-self-tests-summary.json';Add-Check 'unity-self-tests-2-of-2' ($unity.passed -eq $true -and [int]$unity.testCount -eq 2 -and [int]$unity.passedTestCount -eq 2) $unity
$memory=Read-Summary 'UnitySelfTests\MemoryPolicySelfTest\memory-policy-self-test.json';Add-Check 'memory-policy-and-telemetry-fixtures' ($memory.passed -eq $true -and [int]$memory.testCount -eq 10 -and [int]$memory.passedTestCount -eq 10 -and [int]$memory.telemetryValidationTestCount -eq 8 -and [int]$memory.telemetryValidationPassedTestCount -eq 8) $memory
$pathsafe=Read-Summary 'UnitySelfTests\PathSafeAtomicSelfTest\path-safe-atomic-self-test.json';Add-Check 'unity-path-safe-atomic-14-of-14' ($pathsafe.passed -eq $true -and [int]$pathsafe.testCount -eq 14 -and [int]$pathsafe.passedTestCount -eq 14 -and [int]$pathsafe.residualOwnedTemporaryFileCount -eq 0) $pathsafe
$telemetry=Read-Summary 'TelemetryProbe\probe.summary.json';Add-Check 'psapi-cim-telemetry-probe' ($telemetry.passed -eq $true -and [int]$telemetry.exitCode -eq 0) $telemetry
$blocks=Read-Summary 'BlockValidation\block-validation-summary.json';Add-Check 'positive-negative-block-validation-2-of-2' ($blocks.passed -eq $true -and [int]$blocks.testCount -eq 2 -and [int]$blocks.passedTestCount -eq 2 -and $blocks.measuredPilotStarted -eq $false) $blocks
$failure7=Read-Summary 'FailurePrecedencePS7\summary.json';Add-Check 'failure-precedence-ps7-6-of-6' ($failure7.passed -eq $true -and [int]$failure7.testCount -eq 6 -and [int]$failure7.passedTestCount -eq 6) $failure7.runtime
$failure51=Read-Summary 'FailurePrecedencePS51\summary.json';Add-Check 'failure-precedence-ps51-6-of-6' ($failure51.passed -eq $true -and [int]$failure51.testCount -eq 6 -and [int]$failure51.passedTestCount -eq 6) $failure51.runtime
$frozen=Read-Summary 'FrozenRoots\frozen-roots-audit.json';Add-Check 'frozen-roots-postvalidation-byte-hash-invariance' ($frozen.passed -eq $true) $frozen.roots

$provenancePath=Join-Path $ProjectPath 'Research\Gate13R_PR2_MP1_Provenance.v2_4.json';$provenance=Read-G13RPR2MP1V2Json $provenancePath;$mismatches=New-Object Collections.Generic.List[object]
foreach($item in @($provenance.artifacts)){$path=Join-Path $ProjectPath ([string]$item.relativePath).Replace('/','\');$actualHash=if(Test-Path -LiteralPath $path -PathType Leaf){Get-G13RPR2MP1V2Sha256 $path}else{$null};$actualBytes=if(Test-Path -LiteralPath $path -PathType Leaf){[long](Get-Item -LiteralPath $path).Length}else{$null};if($actualHash -ne [string]$item.sha256 -or $actualBytes -ne [long]$item.bytes){$mismatches.Add([ordered]@{relativePath=$item.relativePath;expectedSha256=$item.sha256;actualSha256=$actualHash;expectedBytes=$item.bytes;actualBytes=$actualBytes})}}
Add-Check 'provenance-artifacts-byte-identical' ($mismatches.Count -eq 0) ([ordered]@{artifactCount=@($provenance.artifacts).Count;mismatchCount=$mismatches.Count;mismatches=$mismatches.ToArray()})

$pilotV2=Join-Path $ProjectPath 'Research\PilotRuns\Gate13R_PR2_MemoryPolicy\v2';$formal3=Join-Path $ProjectPath 'Research\FormalRuns\Gate13R_RQAligned_S48H48\v3';$formal3Receipt=Join-Path $ProjectPath 'Research\Gate13R_PR2_Formal_Execution_Receipt.v3.json';$lock=Join-Path $ProjectPath 'Temp\UnityLockfile'
Add-Check 'pilot-v2-root-absent' (-not(Test-Path -LiteralPath $pilotV2)) $pilotV2
Add-Check 'formal-attempt3-root-absent' (-not(Test-Path -LiteralPath $formal3)) $formal3
Add-Check 'formal-attempt3-receipt-absent' (-not(Test-Path -LiteralPath $formal3Receipt)) $formal3Receipt
$unityProcesses=@(Get-CimInstance Win32_Process|Where-Object{$_.Name -in @('Unity.exe','UnityCrashHandler64.exe','UnityCrashHandler32.exe')}|Select-Object ProcessId,ParentProcessId,Name,ExecutablePath,CommandLine);Add-Check 'unity-process-tree-zero' ($unityProcesses.Count -eq 0) $unityProcesses
Add-Check 'project-unity-lock-absent' (-not(Test-Path -LiteralPath $lock)) $lock
$drive=Get-PSDrive -Name H;Add-Check 'h-drive-free-at-least-40-gib' ([long]$drive.Free -ge 42949672960L) ([long]$drive.Free)
$os=Get-CimInstance Win32_OperatingSystem;$available=[long]$os.FreePhysicalMemory*1024L;Add-Check 'available-memory-at-least-8-gib' ($available -ge 8589934592L) $available
$power=(& powercfg.exe /getactivescheme 2>&1|Out-String).Trim();Add-Check 'high-performance-power-plan' ($power -match '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c') $power
$sleep=(& powercfg.exe /query SCHEME_CURRENT SUB_SLEEP STANDBYIDLE 2>&1|Out-String);Add-Check 'ac-sleep-disabled' ($sleep -match '0x00000000') $sleep

$failed=@($checks|Where-Object{-not$_.passed});$now=[DateTime]::UtcNow
$audit=[ordered]@{schemaVersion=2;auditKind='gate13r-pr2-mp1-v2-final-validation-only-prepilot-audit-v1';completedAtUtc=$now.ToString('o');completedAtAsiaShanghai=[TimeZoneInfo]::ConvertTimeBySystemTimeZoneId($now,'China Standard Time').ToString('o');verificationRoot=$VerificationRoot;formalCampaign=$false;measuredPilotStarted=$false;formalAttempt3Authorized=$false;formalAnalysisAuthorized=$false;gate14RAuthorized=$false;checkCount=$checks.Count;passedCheckCount=@($checks|Where-Object{$_.passed}).Count;failedCheckCount=$failed.Count;checks=$checks.ToArray();passed=$failed.Count -eq 0}
Write-G13RPR2MP1V2AtomicJson -Path $auditPath -Value $audit -Depth 100
if($failed.Count -ne 0){throw ('MP1 v2 final audit failed: '+(($failed|ForEach-Object{$_.id}) -join ', '))}
$configPath=Join-Path $ProjectPath 'Research\Gate13R_PR2_MP1_Pilot_Config.v2.json';$schedulePath=Join-Path $ProjectPath 'Research\Gate13R_PR2_MP1_Pilot_Schedule.v1.jsonl';$manifestPath=Join-Path $ProjectPath 'Research\Gate13R_PR2_MP1_Pilot_Schedule_Manifest.v1.json'
$checkpoint=[ordered]@{schemaVersion=2;checkpointKind='gate13r-pr2-mp1-v2-prepilot-readiness-checkpoint-v1';savedAtUtc=[DateTime]::UtcNow.ToString('o');status='PRE-PILOT-VALIDATED / MEASURED-PILOT-V2-AUTHORIZED-BUT-NOT-STARTED';passed=$true;verificationRoot=$VerificationRoot;finalAuditRelativePath='Research/Gate13R_PR2_MP1_PrePilot_Final_Audit.v2.json';finalAuditSha256=Get-G13RPR2MP1V2Sha256 $auditPath;authorizationSha256=Get-G13RPR2MP1V2Sha256 (Join-Path $ProjectPath 'Research\Gate13R_PR2_MP1_v2_Authorization.v1.json');provenanceSha256=Get-G13RPR2MP1V2Sha256 $provenancePath;configSha256=Get-G13RPR2MP1V2Sha256 $configPath;scheduleSha256=Get-G13RPR2MP1V2Sha256 $schedulePath;scheduleManifestSha256=Get-G13RPR2MP1V2Sha256 $manifestPath;measuredProcessCount=96;measuredSampleCount=384;warmupProcessCount=0;maximumUnityConcurrency=1;oneFreshUnityProcessPerCompleteWilliamsBlock=$true;automaticMeasuredRetryAuthorized=$false;automaticMeasuredResumeAuthorized=$false;topUpAuthorized=$false;partialMergeAuthorized=$false;formalAttempt3Authorized=$false;formalStatisticalAnalysisAuthorized=$false;gate14RAuthorized=$false;pilotV1FrozenIdentity=$frozen.roots.pilotV1;formalAttempt2FrozenIdentity=$frozen.roots.formalAttempt2;environment=[ordered]@{hDriveFreeBytes=[long]$drive.Free;availablePhysicalMemoryBytes=$available;unityProcessCount=0;unityLockfileExists=$false;highPerformancePowerPlan=$true;acSleepDisabled=$true};labels=@('NON-FORMAL','MEMORY-DIAGNOSTIC-ONLY','EXCLUDED-FROM-FORMAL-ANALYSIS','NOT-ALGORITHM-SUPERIORITY-EVIDENCE')}
Write-G13RPR2MP1V2AtomicJson -Path $checkpointPath -Value $checkpoint -Depth 70
Write-Output "MP1-V2-PRE-PILOT-VALIDATED|$($audit.passedCheckCount)/$($audit.checkCount)|$checkpointPath"
