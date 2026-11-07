[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$ProjectPath,[Parameter(Mandatory=$true)][string]$OutputDirectory)
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
$ProjectPath=[IO.Path]::GetFullPath($ProjectPath);$OutputDirectory=[IO.Path]::GetFullPath($OutputDirectory)
Import-Module (Join-Path $ProjectPath 'Research\Gate13RPR2MemoryPolicyPilotV1.psm1') -Force
if(Test-Path -LiteralPath $OutputDirectory){throw 'Create-new failure-precedence test output exists.'}
New-Item -ItemType Directory -Path $OutputDirectory|Out-Null
$blockPath=Join-Path $OutputDirectory 'block-failure.json';$quiescencePath=Join-Path $OutputDirectory 'quiescence-failure.json'
Write-G13RPR2MP1AtomicJson -Path $blockPath -Value ([ordered]@{failedAtUtc='2026-10-09T00:00:00Z';blockId='fixture';failedRunId='fixture-run';memoryGateReasonCode='FIXTURE-BLOCK-FAILURE'}) -Depth 10
Write-G13RPR2MP1AtomicJson -Path $quiescencePath -Value ([ordered]@{savedAtUtc='2026-10-09T00:00:01Z';passed=$false}) -Depth 10
$missingBlock=Join-Path $OutputDirectory 'missing-block.json';$missingQuiescence=Join-Path $OutputDirectory 'missing-quiescence.json'
$cases=@(
    [ordered]@{id='durable-plus-quiescence';value=Resolve-G13RPR2MP1FailurePrecedence -BlockFailurePath $blockPath -QuiescenceFailurePath $quiescencePath -QuiescenceExceptionMessage 'fixture';expectedPrimary='DURABLE-UNITY-BLOCK-FAILURE';expectedSecondary=1;expectedFailed=$true},
    [ordered]@{id='timeout-plus-quiescence';value=Resolve-G13RPR2MP1FailurePrecedence -BlockFailurePath $missingBlock -QuiescenceFailurePath $quiescencePath -QuiescenceExceptionMessage 'fixture' -TimedOut $true;expectedPrimary='HARD-TIMEOUT';expectedSecondary=1;expectedFailed=$true},
    [ordered]@{id='exit-plus-quiescence';value=Resolve-G13RPR2MP1FailurePrecedence -BlockFailurePath $missingBlock -QuiescenceFailurePath $quiescencePath -QuiescenceExceptionMessage 'fixture' -UnityExitCode 7;expectedPrimary='NONZERO-UNITY-EXIT';expectedSecondary=1;expectedFailed=$true},
    [ordered]@{id='quiescence-only';value=Resolve-G13RPR2MP1FailurePrecedence -BlockFailurePath $missingBlock -QuiescenceFailurePath $quiescencePath -QuiescenceExceptionMessage 'fixture';expectedPrimary='POST-EXIT-QUIESCENCE-FAILURE';expectedSecondary=0;expectedFailed=$true},
    [ordered]@{id='safety-plus-exit';value=Resolve-G13RPR2MP1FailurePrecedence -BlockFailurePath $missingBlock -QuiescenceFailurePath $missingQuiescence -UnityExitCode 9 -SafetyStopReasons @('HARD-FAIL-ABSOLUTE-WORKING-SET-4GIB');expectedPrimary='EMERGENCY-SAFETY-STOP';expectedSecondary=0;expectedFailed=$true},
    [ordered]@{id='success';value=Resolve-G13RPR2MP1FailurePrecedence -BlockFailurePath $missingBlock -QuiescenceFailurePath $missingQuiescence;expectedPrimary=$null;expectedSecondary=0;expectedFailed=$false}
)
$results=New-Object Collections.Generic.List[object]
foreach($case in $cases){$value=$case.value;$primary=if($null-ne$value.primaryCause){[string]$value.primaryCause.kind}else{$null};$passed=$primary -eq $case.expectedPrimary -and @($value.secondaryCauses).Count -eq $case.expectedSecondary -and [bool]$value.failed -eq [bool]$case.expectedFailed -and $value.automaticRetryAllowed -eq $false -and $value.automaticResumeAllowed -eq $false -and $value.topUpAllowed -eq $false -and $value.partialMergeAllowed -eq $false -and $value.lockCleanupAuthorizesContinuation -eq $false;$results.Add([ordered]@{id=$case.id;primary=$primary;secondaryCount=@($value.secondaryCauses).Count;failed=$value.failed;passed=$passed})}
$summary=[ordered]@{schemaVersion=1;summaryKind='gate13r-pr2-mp1-failure-precedence-fixtures-v1';runtime=$PSVersionTable.PSVersion.ToString();testCount=$results.Count;passedTestCount=@($results|Where-Object{$_.passed}).Count;tests=$results.ToArray();passed=@($results|Where-Object{-not $_.passed}).Count -eq 0}
Write-G13RPR2MP1AtomicJson -Path (Join-Path $OutputDirectory 'summary.json') -Value $summary -Depth 30
if(-not $summary.passed){exit 1};Write-Output "FAILURE-PRECEDENCE-PASSED|$($summary.passedTestCount)/$($summary.testCount)|$($summary.runtime)"
